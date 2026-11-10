-- Fichier : utils/moniteur.lua
-- 3615 MONITEUR : charge du processeur (par coeur), memoire, disque,
-- temperature, reseau et processus, en temps reel, pour ce Raspberry Pi ou
-- pour un serveur Linux distant joint par SSH (cle uniquement, jamais de mot
-- de passe). Serveurs dans utils/moniteur.cfg : NOM|utilisateur@hote|port
-- @TYPE: SYSTEME / SUPERVISION
-- @DESC: Processeur coeur par coeur, memoire, disque, temperature, reseau et processus en direct, pour le Pi ou un serveur Linux distant (SSH par cle).
-- @ART1:      .-----------------.
-- @ART2:      | CPU [#####   ]  |
-- @ART3:      | MEM [###     ]  |
-- @ART4:      |  _.-'^'-._.-'^  |
-- @ART5:      '--[ MONITEUR ]---'

local minitel = require("minitel")
minitel.init()

local CFG_FILE = "utils/moniteur.cfg"
local KEY_FILE = os.getenv("HOME") .. "/.ssh/id_ed25519"
local BAR_W = 24
local HIST_W, HIST_H = 18, 7
local PS_TOP, PS_ROWS = 16, 7

-- Collecte, identique en local et a distance : sections marquees @NOM.
-- (pas d'apostrophe : le script passe entre apostrophes a ssh)
local PROBE = table.concat({
    'echo @CPU; grep "^cpu" /proc/stat',
    'echo @MEM; grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):" /proc/meminfo',
    'echo @LOAD; cat /proc/loadavg',
    'echo @UP; cat /proc/uptime',
    'echo @TEMP; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null',
    'echo @NET; tail -n +3 /proc/net/dev',
    'echo @DISK; df -P / | tail -n 1',
    'echo @HOST; hostname; uname -sr',
    'echo @PS; ps -eo pid,user:12,pcpu,pmem,comm --sort=-pcpu --no-headers | head -n ' .. PS_ROWS,
}, "; ")

-- =====================================================================
-- SERVEURS
-- =====================================================================
local servers = {}

local function load_servers()
    servers = { { name = "CE RASPBERRY PI", local_ = true } }
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local name, target, port = string.match(line, "^([^|#][^|]*)|([%w%._%-]+@[%w%._%-]+)|?(%d*)")
        if name then servers[#servers + 1] = { name = string.upper(name), target = target, port = tonumber(port) or 22 } end
    end
    f:close()
end

local function save_servers()
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    f:write("# Serveurs de 3615 MONITEUR : NOM|utilisateur@hote|port\n")
    for _, s in ipairs(servers) do
        if not s.local_ then f:write(string.format("%s|%s|%d\n", s.name, s.target, s.port)) end
    end
    f:close()
end

local function ssh_cmd(s, remote)
    return string.format("ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new "
        .. "-o ControlMaster=auto -o ControlPath=/tmp/minitel-ssh-%%r@%%h:%%p -o ControlPersist=120 "
        .. "-p %d %s '%s' 2>&1", s.port, s.target, remote)
end

local function run(s, script)
    local cmd = s.local_ and ("{ " .. script .. "; } 2>&1") or ssh_cmd(s, script)
    local p = io.popen(cmd)
    if not p then return nil end
    local out = p:read("*a")
    local ok = p:close()
    return out, ok
end

-- =====================================================================
-- LECTURE DES MESURES
-- =====================================================================
local function probe(s)
    local out, ok = run(s, PROBE)
    if not out or not out:find("@CPU") then return nil, (out or ""):match("[^\r\n]+") or "pas de reponse" end
    local sec, d = nil, { cpu = {}, mem = {}, ps = {}, net_rx = 0, net_tx = 0, host = {} }
    for line in out:gmatch("[^\n]+") do
        local tag = line:match("^@(%u+)$")
        if tag then sec = tag
        elseif sec == "CPU" then
            local name, rest = line:match("^(cpu%d*)%s+(.+)$")
            if name then
                local v = {}
                for n in rest:gmatch("%d+") do v[#v + 1] = tonumber(n) end
                local total = 0
                for i = 1, math.min(8, #v) do total = total + v[i] end
                d.cpu[#d.cpu + 1] = { name = name, total = total, idle = (v[4] or 0) + (v[5] or 0) }
            end
        elseif sec == "MEM" then
            local k, v = line:match("^(%w+):%s+(%d+)")
            if k then d.mem[k] = tonumber(v) * 1024 end
        elseif sec == "LOAD" then d.load = line:match("^(%S+ %S+ %S+)")
        elseif sec == "UP" then d.uptime = tonumber(line:match("^([%d%.]+)"))
        elseif sec == "TEMP" then d.temp = tonumber(line) and tonumber(line) / 1000
        elseif sec == "NET" then
            local iface, rest = line:match("^%s*([^:]+):%s*(.+)$")
            if iface and iface ~= "lo" then
                local v = {}
                for n in rest:gmatch("%d+") do v[#v + 1] = tonumber(n) end
                d.net_rx, d.net_tx = d.net_rx + (v[1] or 0), d.net_tx + (v[9] or 0)
            end
        elseif sec == "DISK" then
            local size, used = line:match("^%S+%s+(%d+)%s+(%d+)")
            if size then d.disk = { size = tonumber(size) * 1024, used = tonumber(used) * 1024 } end
        elseif sec == "HOST" then d.host[#d.host + 1] = line
        elseif sec == "PS" then
            local pid, user, pcpu, pmem, comm = line:match("^%s*(%d+)%s+(%S+)%s+([%d%.]+)%s+([%d%.]+)%s+(.+)$")
            if pid then d.ps[#d.ps + 1] = { pid = pid, user = user, cpu = tonumber(pcpu), mem = tonumber(pmem), comm = comm } end
        end
    end
    d.time = os.time()
    return d
end

-- =====================================================================
-- AFFICHAGE DIFFERENTIEL : une zone n'est renvoyee que si elle a change
-- =====================================================================
local shown = {}
local function put(key, y, x, text)
    if shown[key] == text then return end
    shown[key] = text
    io.write(string.format("\x1b[%d;%dH%s", y, x, text))
end

local function human(bytes)
    local units = { "O", "KO", "MO", "GO", "TO" }
    local i = 1
    while bytes >= 1024 and i < #units do bytes = bytes / 1024; i = i + 1 end
    return (i <= 2 and string.format("%d %s", math.floor(bytes + 0.5), units[i])
        or string.format("%.1f %s", bytes, units[i])):gsub("%.", ",")
end

local function bar(frac)
    frac = math.max(0, math.min(1, frac or 0))
    local n = math.floor(frac * BAR_W + 0.5)
    return "[\x1b[7m" .. string.rep(" ", n) .. "\x1b[0m" .. string.rep(".", BAR_W - n) .. "]"
end

local function uptime_str(s)
    if not s then return "?" end
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return string.format("%dJ %02dH%02d", d, h, m) end
    return string.format("%dH%02d", h, m)
end

-- =====================================================================
-- ECRAN DE SUPERVISION
-- =====================================================================
-- Rend "SERVERS" (changer de serveur) ou "QUIT"
local function monitor(s)
    local period = s.local_ and 2 or 3
    local prev, cur
    local hist = {}
    local sel = 1
    local message

    local function draw_static()
        shown = {}
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 MONITEUR  -  " .. s.name)
        io.write(string.format("\x1b[4;%dH\x1b[1mCPU (%d S)\x1b[0m", 80 - HIST_W, period * HIST_W))
        io.write(string.format("\x1b[%d;1H\x1b[7m%s\x1b[0m", PS_TOP - 1,
            minitel.pad("    PID  UTILISATEUR    %CPU  %MEM  COMMANDE", 80)))
        minitel.footer("HAUT/BAS:PROCESSUS  K:ARRETER  +/-:VITESSE  S:SERVEURS  RETOUR:QUITTER")
    end

    local function draw()
        if not cur then return end
        local d = cur
        put("host", 2, 3, minitel.pad(string.format("%s  %s  DEPUIS %s  CHARGE %s",
            string.sub(d.host[1] or "?", 1, 14), string.sub(d.host[2] or "", 1, 18),
            uptime_str(d.uptime), d.load or "?"), 77))
        -- processeur : total, puis une barre par coeur jusqu'a 4 coeurs, ou
        -- des mini-barres de 8 coeurs par ligne au-dela
        local fracs = {}
        for i, c in ipairs(d.cpu) do
            local p = prev and prev.cpu[i]
            fracs[i] = (p and c.total > p.total) and (1 - (c.idle - p.idle) / (c.total - p.total)) or 0
        end
        local function pct(f) return math.floor(f * 100 + 0.5) end
        put("cpu1", 4, 3, string.format("%-10s %s %3d %%", "CPU TOTAL", bar(fracs[1]), pct(fracs[1] or 0)))
        local cores = #d.cpu - 1
        local y = 5
        if cores <= 4 then
            for i = 1, cores do
                put("cpu" .. (i + 1), y, 3, string.format("%-10s %s %3d %%", "  COEUR " .. (i - 1), bar(fracs[i + 1]), pct(fracs[i + 1])))
                y = y + 1
            end
        else
            for first = 1, math.min(cores, 32), 8 do
                local parts = {}
                for i = first, math.min(first + 7, cores) do
                    local n = math.floor(fracs[i + 1] * 3 + 0.5)
                    parts[#parts + 1] = string.format("[%s%s]", string.rep("#", n), string.rep(".", 3 - n))
                end
                local label = string.format("  %d-%d", first - 1, math.min(first + 7, cores) - 1)
                put("cores" .. first, y, 3, minitel.pad(string.format("%-10s %s", label, table.concat(parts, " ")), 59))
                y = y + 1
            end
        end
        local m = d.mem
        local y2 = math.max(y, 9) + 1
        if m.MemTotal then
            local used = m.MemTotal - (m.MemAvailable or 0)
            put("mem", y2, 3, string.format("%-10s %s %s / %s   ", "MEMOIRE", bar(used / m.MemTotal), human(used), human(m.MemTotal)))
        end
        if m.SwapTotal and m.SwapTotal > 0 then
            local used = m.SwapTotal - (m.SwapFree or 0)
            put("swap", y2 + 1, 3, string.format("%-10s %s %s / %s   ", "ECHANGE", bar(used / m.SwapTotal), human(used), human(m.SwapTotal)))
        end
        if d.disk then
            put("disk", y2 + 2, 3, string.format("%-10s %s %s / %s   ", "DISQUE /", bar(d.disk.used / d.disk.size), human(d.disk.used), human(d.disk.size)))
        end
        local rx, tx = 0, 0
        if prev and d.time > prev.time then
            rx = math.max(0, (d.net_rx - prev.net_rx) / (d.time - prev.time))
            tx = math.max(0, (d.net_tx - prev.net_tx) / (d.time - prev.time))
        end
        local temp = d.temp and (string.format("%.1f", d.temp):gsub("%.", ",") .. " C") or "--"
        if d.temp and d.temp >= 75 then temp = "\x1b[5m" .. temp .. "\x1b[0m" end
        put("net", y2 + 3, 3, minitel.pad(string.format("RESEAU     RECU %s/S   ENVOYE %s/S   TEMPERATURE %s",
            human(rx), human(tx), temp), 77))

        -- historique de la charge totale, en colonnes
        for row = 1, HIST_H do
            local line = {}
            for col = 1, HIST_W do
                local v = hist[#hist - HIST_W + col]
                local level = v and math.floor(v * HIST_H + 0.5) or 0
                line[col] = (level >= HIST_H - row + 1) and "#" or (row == HIST_H and "_" or " ")
            end
            put("hist" .. row, 4 + row, 80 - HIST_W, table.concat(line))
        end

        -- processus
        if sel > #d.ps then sel = math.max(1, #d.ps) end
        for i = 1, PS_ROWS do
            local p = d.ps[i]
            local text = p and string.format(" %6s  %-12s %5.1f %5.1f  %s", p.pid, string.sub(p.user, 1, 12), p.cpu, p.mem,
                string.sub(p.comm, 1, 40)) or ""
            text = minitel.pad(text, 80)
            if p and i == sel then text = "\x1b[7m" .. text .. "\x1b[0m" end
            put("ps" .. i, PS_TOP + i - 1, 1, text)
        end
        put("msg", 23, 3, minitel.pad(message or "", 76))
        io.flush()
    end

    local function refresh()
        local d, err = probe(s)
        if not d then
            message = "ERREUR : " .. minitel.clean_accents(err)
            draw()
            return false
        end
        prev, cur = cur, d
        if prev then
            local p, c = prev.cpu[1], d.cpu[1]
            if p and c and c.total > p.total then
                hist[#hist + 1] = 1 - (c.idle - p.idle) / (c.total - p.total)
                if #hist > HIST_W then table.remove(hist, 1) end
            end
        end
        return true
    end

    draw_static()
    io.write("\x1b[12;30HMESURE EN COURS...")
    io.flush()
    if not refresh() then
        minitel.msg_box("CONNEXION IMPOSSIBLE", message, "lose")
        return "SERVERS"
    end
    -- deuxieme mesure rapprochee : les pourcentages se calculent par difference
    minitel.sleep(0.5)
    refresh()
    draw_static()
    draw()
    local next_t = os.time() + period
    while true do
        if os.time() >= next_t then
            refresh()
            draw()
            next_t = os.time() + period
        end
        local k = minitel.get_key()
        if k then
            message = nil
            if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return "QUIT"
            elseif k == "S" or k == "s" then return "SERVERS"
            elseif k == "UP" then sel = math.max(1, sel - 1); draw()
            elseif k == "DOWN" then sel = math.min(math.max(1, cur and #cur.ps or 1), sel + 1); draw()
            elseif k == "+" then period = math.max(1, period - 1); message = "ACTUALISATION TOUTES LES " .. period .. " S"; draw()
            elseif k == "-" then period = math.min(30, period + 1); message = "ACTUALISATION TOUTES LES " .. period .. " S"; draw()
            elseif k == "REPETITION" then draw_static(); draw()
            elseif (k == "K" or k == "k") and cur and cur.ps[sel] then
                local p = cur.ps[sel]
                if minitel.confirm_box("ARRETER UN PROCESSUS", "Arreter " .. string.sub(p.comm, 1, 20) .. " (PID " .. p.pid .. ") ?") then
                    local out, ok = run(s, "kill " .. p.pid)
                    message = ok and ("SIGNAL D'ARRET ENVOYE A " .. p.pid)
                        or ("REFUSE : " .. minitel.clean_accents((out or ""):match("[^\r\n]+") or "droits insuffisants"))
                end
                draw_static()
                draw()
            end
        end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- CHOIX DU SERVEUR
-- =====================================================================
local function show_key()
    local f = io.open(KEY_FILE .. ".pub", "r")
    if not f then
        if not minitel.confirm_box("CLE SSH", "Le Pi n'a pas encore de cle SSH. La creer maintenant ?") then return end
        os.execute(string.format("mkdir -p %q && ssh-keygen -q -t ed25519 -N '' -f %q >/dev/null 2>&1",
            KEY_FILE:match("^(.*)/"), KEY_FILE))
        f = io.open(KEY_FILE .. ".pub", "r")
        if not f then minitel.msg_box("CLE SSH", "Impossible de creer la cle.", "lose"); return end
    end
    local key = f:read("*l") or ""
    f:close()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 MONITEUR  -  CLE SSH DU RASPBERRY PI")
    io.write("\x1b[3;3HPour surveiller un serveur, il doit accepter la cle du Pi (jamais de mot de")
    io.write("\x1b[4;3Hpasse). Le plus simple : TERMINAL BASH du portail, puis une seule fois :")
    io.write("\x1b[6;6H\x1b[1mssh-copy-id utilisateur@serveur\x1b[0m")
    io.write("\x1b[8;3HOu ajoutez a la main cette ligne au fichier ~/.ssh/authorized_keys du serveur :")
    local y = 10
    for i = 1, #key, 76 do
        io.write(string.format("\x1b[%d;3H%s", y, string.sub(key, i, i + 75)))
        y = y + 1
    end
    minitel.footer("UNE TOUCHE POUR REVENIR")
    io.flush()
    while not minitel.get_key() do minitel.sleep(0.05) end
end

local function choose(sel)
    local function draw()
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 MONITEUR  -  QUEL SERVEUR ?")
        for i, s in ipairs(servers) do
            local text = minitel.pad(string.format(" %d  %-20s %s", i, s.name,
                s.local_ and "local" or (s.target .. (s.port ~= 22 and (":" .. s.port) or ""))), 76)
            if i == sel then text = "\x1b[7m" .. text .. "\x1b[0m" end
            io.write(string.format("\x1b[%d;3H%s", 3 + i, text))
        end
        io.write("\x1b[18;3HLes serveurs distants sont joints par SSH, avec la cle du Pi uniquement :")
        io.write("\x1b[19;3H[C] affiche cette cle et la facon de l'installer sur un serveur.")
        minitel.footer("HAUT/BAS  ENVOI:SURVEILLER  A:AJOUTER  D:RETIRER  C:CLE DU PI  RETOUR:QUITTER")
        io.flush()
    end
    draw()
    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return nil
            elseif k == "UP" then sel = sel > 1 and sel - 1 or #servers; draw()
            elseif k == "DOWN" then sel = sel < #servers and sel + 1 or 1; draw()
            elseif tonumber(k) and servers[tonumber(k)] then return tonumber(k)
            elseif k == "ENVOI" or k == " " then return sel
            elseif (k == "C" or k == "c") then show_key(); draw()
            elseif (k == "A" or k == "a") and #servers < 12 then
                local name = minitel.input_box("NOUVEAU SERVEUR", "Nom affiche :", "", 20)
                local target = name and name ~= "" and minitel.input_box("NOUVEAU SERVEUR", "utilisateur@adresse :", "", 40)
                local port = target and minitel.input_box("NOUVEAU SERVEUR", "Port SSH :", "22", 5)
                if target and target:match("^[%w%._%-]+@[%w%._%-]+$") then
                    servers[#servers + 1] = { name = string.upper(name), target = target, port = tonumber(port) or 22 }
                    save_servers()
                    sel = #servers
                elseif target then
                    minitel.msg_box("ADRESSE INVALIDE", "Format attendu : utilisateur@adresse (ex : root@192.168.1.20)", "lose")
                end
                draw()
            elseif (k == "D" or k == "d") and not servers[sel].local_ then
                if minitel.confirm_box("RETIRER", "Retirer " .. servers[sel].name .. " de la liste ?") then
                    table.remove(servers, sel)
                    save_servers()
                    sel = math.min(sel, #servers)
                end
                draw()
            elseif k == "REPETITION" then draw()
            end
        end
        minitel.sleep(0.03)
    end
end

load_servers()
local current = 1
-- seul le Pi est connu : on le surveille tout de suite
local action = #servers == 1 and monitor(servers[1]) or "SERVERS"
while action == "SERVERS" do
    current = choose(current)
    if not current then break end
    action = monitor(servers[current])
end

minitel.cleanup()
