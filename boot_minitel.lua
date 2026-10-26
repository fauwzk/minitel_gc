-- Fichier : boot_minitel.lua
-- Ecran de demarrage du Raspberry Pi sur le Minitel.
--
-- Lance par le service systemd minitel-boot (install_ecran_demarrage.sh) des
-- que l'adaptateur USB-serie apparait. Il met le Minitel en 80 colonnes, puis
-- suit le demarrage de Linux en direct : etapes franchies, derniers messages
-- du journal, reseau. La session Minitel (serial-getty, puis master.lua)
-- attend qu'il ait fini : systeme pret, une touche, ou MAX_WAIT secondes.

local minitel = require("minitel")

local MAX_WAIT = 30
local REFRESH = 0.5
local LOG_TOP, LOG_ROWS = 15, 6

-- Etapes du demarrage, dans l'ordre ou systemd les franchit. multi-user.target
-- et la session ne viennent qu'apres cet ecran, qui les retient.
local STEPS = {
    { unit = "local-fs.target",        label = "SYSTEMES DE FICHIERS MONTES" },
    { unit = "sysinit.target",         label = "INITIALISATION DU SYSTEME" },
    { unit = "basic.target",           label = "SERVICES DE BASE" },
    { unit = "time-sync.target",       label = "HORLOGE" },
    { unit = "NetworkManager.service", label = "GESTIONNAIRE DE RESEAU" },
    { unit = "network.target",         label = "PILE RESEAU" },
    { unit = "network-online.target",  label = "CONNEXION AU RESEAU" },
}

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local l = f:read("*l")
    f:close()
    return l
end

local function shell_lines(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return {} end
    local t = {}
    for l in p:lines() do t[#t + 1] = l end
    p:close()
    return t
end

local function uptime()
    return tonumber((read_first_line("/proc/uptime") or ""):match("^([%d%.]+)")) or 0
end

local function ascii(s)
    return (string.gsub(s, "[^\32-\126]", "?"))
end

local function pad(s, n)
    s = string.sub(s, 1, n)
    return s .. string.rep(" ", n - #s)
end

local function center(s, n)
    return pad(string.rep(" ", math.floor((n - #s) / 2)) .. s, n)
end

-- =====================================================================
-- AFFICHAGE DIFFERENTIEL (9600 BAUDS : ON N'ENVOIE QUE CE QUI CHANGE)
-- =====================================================================
local shown = {}

local function put(y, x, text, attr)
    local key = y .. ":" .. x
    local cell = (attr or "") .. text
    if shown[key] == cell then return end
    shown[key] = cell
    io.write(string.format("\x1b[%d;%dH", y, x), attr or "", text, attr and "\x1b[0m" or "")
end

local function draw_static(model, kernel, host)
    io.write("\x1b[r\x1b[0m\x1b[2J")
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m" .. center("MAGIS CLUB  -  DEMARRAGE DU RASPBERRY PI", 80) .. "\x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[4;3H" .. pad(ascii(model), 76))
    io.write("\x1b[5;3H" .. pad(ascii("LINUX " .. kernel .. "  -  NOM DU SYSTEME : " .. host), 76))
    for i, step in ipairs(STEPS) do
        io.write(string.format("\x1b[%d;4H%s", 6 + i, step.label .. " " .. string.rep(".", 58 - #step.label)))
    end
    io.write("\x1b[14;2H" .. string.rep("-", 78))
    io.write("\x1b[21;2H" .. string.rep("-", 78))
    io.write("\x1b[24;1H\x1b[7m" .. center("LE PORTAIL S'OUVRE DES QUE LE SYSTEME EST PRET  -  UNE TOUCHE POUR PASSER", 80) .. "\x1b[0m")
    io.flush()
end

-- =====================================================================
-- SOURCES : SYSTEMD, JOURNAL, RESEAU
-- =====================================================================
local reached = {}  -- instant (s depuis la mise sous tension) de chaque etape

-- systemd note l'instant exact ou chaque etape a ete atteinte : l'ecran donne
-- les vrais temps du demarrage, meme pour les etapes franchies avant lui
local function poll_steps()
    local units = {}
    for _, s in ipairs(STEPS) do units[#units + 1] = s.unit end
    local info, cur = {}, nil
    for _, l in ipairs(shell_lines("systemctl show -p Id -p ActiveState -p ActiveEnterTimestampMonotonic "
            .. table.concat(units, " "))) do
        local k, v = l:match("^(%w+)=(.*)$")
        if k == "Id" then cur = {}; info[v] = cur
        elseif k and cur then cur[k] = v end
    end
    local done = 0
    for i, step in ipairs(STEPS) do
        local u = info[step.unit]
        if not reached[i] and u and u.ActiveState == "active" then
            local us = tonumber(u.ActiveEnterTimestampMonotonic or "")
            reached[i] = (us and us > 0) and us / 1e6 or uptime()
        end
        if reached[i] then done = done + 1 end
    end
    return done
end

local log_cursor = nil
local log_lines = {}

-- Messages de systemd ajoutes au journal depuis le dernier passage
local function poll_journal()
    local cmd = "journalctl -b -q --no-pager -o short-monotonic --show-cursor -t systemd"
    if log_cursor then
        cmd = cmd .. " --after-cursor='" .. log_cursor .. "'"
    else
        cmd = cmd .. " -n " .. LOG_ROWS
    end
    for _, l in ipairs(shell_lines(cmd)) do
        local c = l:match("^%-%- cursor: (.+)$")
        if c then
            log_cursor = c
        else
            local t, msg = l:match("^%[%s*([%d%.]+)%]%s+%S+%s+[^:]+:%s(.*)$")
            if t then
                log_lines[#log_lines + 1] = string.format("%7.2f  %s", tonumber(t), ascii(msg))
                if #log_lines > LOG_ROWS then table.remove(log_lines, 1) end
            end
        end
    end
end

local function ip_address()
    local l = shell_lines("hostname -I")[1]
    return l and l:match("^(%S+)")
end

-- =====================================================================
-- PROGRAMME
-- =====================================================================
minitel.init()

-- Le Minitel vient peut-etre d'etre allume (40 colonnes) : on le met en 80
-- colonnes, ce que le portail constatera ensuite tout seul
local mode = minitel.detect_mode()
if mode == "40" or mode == "mixte" then
    minitel.switch_to_80(mode)
elseif mode == "80" then
    minitel.echo_off_80()
end

local model = (read_first_line("/proc/device-tree/model") or "RASPBERRY PI"):gsub("%z", "")
local kernel = (shell_lines("uname -r")[1] or "?"):match("^[%w%.%-%+]+") or "?"
local host = shell_lines("hostname")[1] or "?"
draw_static(string.upper(model), kernel, string.upper(host))

local started = uptime()
local done = 0
while uptime() - started < MAX_WAIT and not minitel.get_key() do
    done = poll_steps()
    for i in ipairs(STEPS) do
        if reached[i] then
            put(6 + i, 63, string.format("%7.1f S ", reached[i]), "\x1b[7m")
        else
            put(6 + i, 63, "...       ")
        end
    end

    poll_journal()
    for r = 1, LOG_ROWS do
        put(LOG_TOP + r - 1, 3, pad(log_lines[r] or "", 76))
    end

    local width = 40
    local fill = math.floor(width * done / #STEPS)
    put(22, 3, string.format("T+ %6.1f S", uptime()))
    put(22, 18, "[" .. string.rep("#", fill) .. string.rep(".", width - fill) .. "]")
    local ip = ip_address()
    put(22, 62, pad(ip and ("IP " .. ip) or "RESEAU ...", 18))
    io.write("\x1b[24;80H")
    io.flush()

    if done == #STEPS then break end
    minitel.sleep_raw(REFRESH)
end

put(22, 62, pad(done == #STEPS and "SYSTEME PRET" or "SUITE...", 18), "\x1b[7m")
io.write("\x1b[24;80H")
io.flush()
minitel.sleep_raw(1.5)
-- On rend le port tel quel : le portail repart de son propre etat
