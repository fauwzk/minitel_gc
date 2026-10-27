-- Fichier : utils/reseau.lua
-- 3615 RESEAU : connexions Wi-Fi et Ethernet du Raspberry Pi, pense pour le
-- Minitel (80 colonnes, 9600 bauds) a la place de nmtui. Tout passe par nmcli
-- (NetworkManager), donc avec les memes droits que nmtui.
-- @TYPE: RESEAU / WI-FI
-- @DESC: Etat de l'Ethernet et du Wi-Fi, recherche des reseaux a proximite, connexion avec mot de passe, deconnexion, oubli d'un reseau.
-- @ART1:       ( ( ( o ) ) )
-- @ART2:          \  |  /
-- @ART3:      ETH0 --+-- WLAN0
-- @ART4:        [##] | [###.]
-- @ART5:     3615 RESEAU  Wi-Fi

local minitel = require("minitel")
minitel.init()

local LIST_TOP, LIST_ROWS = 12, 9

-- =====================================================================
-- OUTILS
-- =====================================================================
local function sh_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function run(cmd)
    local p = io.popen(cmd .. " 2>&1")
    if not p then return false, "" end
    local out = p:read("*a") or ""
    local ok = p:close() == true -- nil en cas d'echec : nil voudrait dire "annule"
    return ok, out
end

local function lines_of(cmd)
    local t = {}
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return t end
    for l in p:lines() do t[#t + 1] = l end
    p:close()
    return t
end

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local l = f:read("*l")
    f:close()
    return l
end

local function ascii(s)
    return (string.gsub(minitel.clean_accents(s or ""), "[^\32-\126]", "?"))
end

local function pad(s, n)
    s = string.sub(s or "", 1, n)
    return s .. string.rep(" ", n - #s)
end

-- Decoupe une ligne de "nmcli -t" : champs separes par ":", "\:" et "\\"
-- echappent un deux-points ou une barre dans une valeur (SSID, adresse MAC)
local function split_terse(line, max_fields)
    local fields, cur, i = {}, {}, 1
    while i <= #line do
        local c = string.sub(line, i, i)
        if c == "\\" and i < #line then
            cur[#cur + 1] = string.sub(line, i + 1, i + 1)
            i = i + 2
        elseif c == ":" and (not max_fields or #fields < max_fields - 1) then
            fields[#fields + 1] = table.concat(cur)
            cur = {}
            i = i + 1
        else
            cur[#cur + 1] = c
            i = i + 1
        end
    end
    fields[#fields + 1] = table.concat(cur)
    return fields
end

local HAS_NMCLI = os.execute("command -v nmcli >/dev/null 2>&1")

-- =====================================================================
-- DONNEES : INTERFACES, RESEAUX WI-FI, CONNEXIONS ENREGISTREES
-- =====================================================================
local STATES = {
    connected = "CONNECTE", disconnected = "DECONNECTE", unavailable = "INDISPONIBLE",
    unmanaged = "NON GERE", connecting = "CONNEXION...", deactivating = "DECONNEXION...",
}

local function state_label(s)
    if not s then return "?" end
    if STATES[s] then return STATES[s] end
    if string.find(s, "^connecting") then return "CONNEXION..." end
    return string.upper(s)
end

local function device_details(dev)
    local d = { dns = {} }
    for _, l in ipairs(lines_of("nmcli -t -f GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show " .. sh_quote(dev))) do
        local f = split_terse(l, 2)
        local key, val = f[1], f[2] or ""
        if key == "GENERAL.HWADDR" then d.mac = val
        elseif string.find(key, "^IP4.ADDRESS") and not d.ip then d.ip = val
        elseif key == "IP4.GATEWAY" and val ~= "" then d.gw = val
        elseif string.find(key, "^IP4.DNS") then d.dns[#d.dns + 1] = val end
    end
    local speed = tonumber(read_first_line("/sys/class/net/" .. dev .. "/speed") or "")
    if speed and speed > 0 then d.speed = speed end
    return d
end

-- Une interface Ethernet et une Wi-Fi au plus : celles du Raspberry Pi
local function read_devices()
    local eth, wifi
    for _, l in ipairs(lines_of("nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device")) do
        local f = split_terse(l)
        local dev = { name = f[1], type = f[2], state = f[3], conn = f[4] ~= "" and f[4] or nil }
        if dev.type == "ethernet" and not eth then eth = dev end
        if dev.type == "wifi" and not wifi then wifi = dev end
    end
    for _, dev in ipairs({ eth or {}, wifi or {} }) do
        if dev.name then
            local d = device_details(dev.name)
            for k, v in pairs(d) do dev[k] = v end
        end
    end
    return eth, wifi
end

local function saved_wifi()
    local saved = {}
    for _, l in ipairs(lines_of("nmcli -t -f NAME,TYPE connection show")) do
        local f = split_terse(l)
        if f[2] == "802-11-wireless" then saved[f[1]] = true end
    end
    return saved
end

-- Reseaux a proximite, un par nom (le point d'acces le plus fort), tries par
-- signal ; les reseaux caches (sans nom) sont laisses de cote
local function scan_wifi(rescan)
    local by_ssid, list = {}, {}
    local cmd = "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY,CHAN device wifi list --rescan " .. (rescan and "yes" or "auto")
    for _, l in ipairs(lines_of(cmd)) do
        local f = split_terse(l)
        local ssid = f[2] or ""
        if ssid ~= "" then
            local net = { ssid = ssid, in_use = f[1] == "*", signal = tonumber(f[3]) or 0,
                          security = (f[4] or ""):gsub("^%-%-$", ""), chan = f[5] or "" }
            local old = by_ssid[ssid]
            if not old then
                by_ssid[ssid] = net
                list[#list + 1] = net
            else
                if net.signal > old.signal then old.signal, old.chan = net.signal, net.chan end
                old.in_use = old.in_use or net.in_use
            end
        end
    end
    table.sort(list, function(a, b)
        if a.in_use ~= b.in_use then return a.in_use end
        return a.signal > b.signal
    end)
    return list
end

-- =====================================================================
-- AFFICHAGE DIFFERENTIEL
-- =====================================================================
local shown = {}

local function put(y, x, text, attr)
    local key = y .. ":" .. x
    local cell = (attr or "") .. text
    if shown[key] == cell then return end
    shown[key] = cell
    io.write(string.format("\x1b[%d;%dH", y, x), attr or "", text, attr and "\x1b[0m" or "")
end

local function draw_static()
    shown = {}
    io.write("\x1b[0m\x1b[2J")
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m" .. minitel.center("3615 RESEAU  -  CONNEXIONS DU RASPBERRY PI", 80) .. "\x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[10;1H" .. string.rep("-", 80))
    io.write("\x1b[11;3H\x1b[1mRESEAUX WI-FI A PROXIMITE\x1b[0m")
    io.write("\x1b[11;46HSIGNAL        SECURITE  CANAL")
    io.write("\x1b[24;1H\x1b[7m" .. pad(" [Z/S] CHOIX [ENVOI] CONNECTER [D] DECONNECTER [O] OUBLIER [C] CACHE [A] ACTU.", 80) .. "\x1b[0m")
    io.flush()
end

local function iface_lines(label, dev)
    if not dev or not dev.name then
        return pad(label .. " : AUCUNE INTERFACE", 78), ""
    end
    local head = string.format("%s (%s) : %s", label, dev.name, state_label(dev.state))
    if dev.state == "connected" and dev.conn then
        head = head .. (dev.type == "wifi" and "  RESEAU " or "  PROFIL ") .. ascii(dev.conn)
    end
    if dev.speed and dev.type == "ethernet" and dev.state == "connected" then
        head = head .. string.format("  %d MBIT/S", dev.speed)
    end
    local detail = ""
    if dev.ip then
        detail = "IP " .. dev.ip
        if dev.gw then detail = detail .. "  PASSERELLE " .. dev.gw end
        if dev.dns[1] then detail = detail .. "  DNS " .. dev.dns[1] end
    elseif dev.state == "unavailable" and dev.type == "ethernet" then
        detail = "CABLE DEBRANCHE"
    end
    if dev.mac and #detail + 18 <= 74 then detail = detail .. (detail ~= "" and "  " or "") .. "MAC " .. dev.mac end
    return pad(head, 78), pad(detail, 74)
end

-- "WPA1 WPA2" -> "WPA2", "WPA2 802.1X" -> "ENTREPR." (identifiant + mot de passe)
local function security_label(sec)
    if sec == "" then return "OUVERT" end
    if string.find(sec, "802.1X", 1, true) then return "ENTREPR." end
    local best
    for w in string.gmatch(sec, "%S+") do best = w end
    return string.sub(best or sec, 1, 8)
end

local function signal_bar(s)
    local n = math.floor((s + 10) / 20)
    return "[" .. string.rep("#", n) .. string.rep(".", 5 - n) .. "]" .. string.format(" %3d%%", s)
end

local state = { eth = nil, wifi = nil, nets = {}, saved = {}, cursor = 1, top = 1, msg = "", internet = nil }

local function draw_devices()
    local h1, d1 = iface_lines("ETHERNET", state.eth)
    local h2, d2 = iface_lines("WI-FI", state.wifi)
    put(5, 2, h1); put(6, 6, d1)
    put(7, 2, h2); put(8, 6, d2)
    local inet = state.internet == nil and "INTERNET : TEST..." or
                 (state.internet and "INTERNET : EN LIGNE" or "INTERNET : HORS LIGNE")
    put(9, 2, pad(inet, 30), state.internet and "\x1b[7m" or nil)
end

local function draw_list()
    local nets = state.nets
    if state.cursor > #nets then state.cursor = math.max(1, #nets) end
    if state.cursor < state.top then state.top = state.cursor end
    if state.cursor >= state.top + LIST_ROWS then state.top = state.cursor - LIST_ROWS + 1 end
    for r = 1, LIST_ROWS do
        local i = state.top + r - 1
        local net = nets[i]
        local y = LIST_TOP + r - 1
        if net then
            local mark = net.in_use and "*" or (state.saved[net.ssid] and "+" or " ")
            local line = string.format("%s %s %s  %-8s  %3s", mark, pad(ascii(net.ssid), 41),
                signal_bar(net.signal), security_label(net.security), net.chan)
            put(y, 2, pad(line, 78), i == state.cursor and "\x1b[7m" or nil)
        elseif i == 1 then
            put(y, 2, pad(HAS_NMCLI and "  AUCUN RESEAU WI-FI TROUVE ([A] POUR RELANCER LA RECHERCHE)"
                or "  NMCLI ABSENT : NETWORKMANAGER N'EST PAS INSTALLE", 78))
        else
            put(y, 2, string.rep(" ", 78))
        end
    end
    local count = #nets > 0 and string.format("(%d/%d)", state.cursor, #nets) or ""
    put(11, 30, pad(count, 10))
    put(21, 2, pad("* CONNECTE   + ENREGISTRE   [N] NMTUI   [RETOUR] QUITTER", 78))
end

local function set_msg(text, attr)
    state.msg = text
    put(22, 1, pad(" " .. text, 80), attr)
    io.write("\x1b[24;80H")
    io.flush()
end

local function refresh(rescan)
    if not HAS_NMCLI then draw_list(); return end
    set_msg(rescan and "RECHERCHE DES RESEAUX WI-FI..." or "LECTURE DE L'ETAT DU RESEAU...")
    state.eth, state.wifi = read_devices()
    state.saved = saved_wifi()
    state.nets = scan_wifi(rescan)
    draw_devices()
    draw_list()
    set_msg("")
end

local function check_internet()
    state.internet = os.execute("ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1") and true or false
    draw_devices()
    io.flush()
end

-- =====================================================================
-- SAISIE DU MOT DE PASSE (MASQUE, AVEC [GUIDE] POUR L'AFFICHER)
-- =====================================================================
local function ask_password(title)
    local x, y, w = 13, 9, 56
    minitel.draw_window(x, y, w, 8, title)
    io.write(string.format("\x1b[%d;%dH\x1b[1mMOT DE PASSE DU RESEAU :\x1b[0m", y + 2, x + 3))
    io.write(string.format("\x1b[%d;%dH[ENVOI] OK [GUIDE] VOIR [CORRECTION] [RETOUR] ANNULER", y + 6, x + 2))
    local str, visible = "", false
    local function field()
        local disp = visible and str or string.rep("*", #str)
        if #disp > 44 then disp = string.sub(disp, -44) end
        io.write(string.format("\x1b[%d;%dH> \x1b[7m %-44s \x1b[0m", y + 4, x + 3, disp))
        io.flush()
    end
    field()
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" then return str
            elseif k == "RETOUR" or k == "ESC" then return nil
            elseif k == "GUIDE" then visible = not visible; field()
            elseif k == "ANNULATION" then str = ""; field()
            elseif k == "CORRECTION" then str = string.sub(str, 1, -2); field()
            elseif #k == 1 and string.byte(k) >= 32 and string.byte(k) < 127 and #str < 63 then
                str = str .. k; field()
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- ACTIONS
-- =====================================================================
local function redraw_all()
    draw_static()
    draw_devices()
    draw_list()
    set_msg(state.msg)
end

-- Les erreurs courantes de nmcli, en clair ; les autres telles quelles
local NM_ERRORS = {
    { "Secrets were required", "ECHEC : MOT DE PASSE REFUSE" },
    { "No network with SSID", "ECHEC : RESEAU INTROUVABLE" },
    { "[Tt]imeout", "ECHEC : PAS DE REPONSE DU RESEAU (DELAI DEPASSE)" },
    { "[Nn]ot authorized", "ECHEC : DROITS INSUFFISANTS (POLKIT)" },
}

local function first_line(out)
    for _, e in ipairs(NM_ERRORS) do
        if string.find(out or "", e[1]) then return e[2] end
    end
    out = string.gsub(out or "", "^Error: ", "ERREUR : ")
    return string.upper(ascii(string.match(out, "^%s*([^\r\n]*)") or ""))
end

local function connect_to(ssid, secured, hidden)
    local ok, out
    if state.saved[ssid] and not hidden then
        set_msg("CONNEXION A " .. ascii(ssid) .. " (RESEAU ENREGISTRE)...")
        ok, out = run("nmcli --wait 30 connection up id " .. sh_quote(ssid))
        if ok then return true, out end
    end
    local pw
    if secured then
        pw = ask_password("CONNEXION A " .. string.upper(ascii(ssid)))
        redraw_all()
        if not pw then return nil end
    end
    set_msg("CONNEXION A " .. ascii(ssid) .. "... (30 S AU PLUS)")
    local cmd = "nmcli --wait 30 device wifi connect " .. sh_quote(ssid)
    if pw and pw ~= "" then cmd = cmd .. " password " .. sh_quote(pw) end
    if hidden then cmd = cmd .. " hidden yes" end
    if state.wifi and state.wifi.name then cmd = cmd .. " ifname " .. sh_quote(state.wifi.name) end
    return run(cmd)
end

local function after_action(ok, out, good_msg)
    if ok == nil then set_msg("ANNULE"); return end
    refresh(false)
    if ok then
        minitel.play_sound("win")
        set_msg(good_msg, "\x1b[7m")
    else
        minitel.play_sound("damage")
        set_msg(first_line(out), "\x1b[7m")
    end
    state.internet = nil
    draw_devices()
    check_internet()
end

local function action_connect()
    local net = state.nets[state.cursor]
    if not net then return end
    if net.in_use then set_msg("DEJA CONNECTE A " .. ascii(net.ssid)); return end
    local ok, out = connect_to(net.ssid, net.security ~= "", false)
    after_action(ok, out, "CONNECTE A " .. ascii(net.ssid))
end

local function action_hidden()
    local ssid = minitel.input_box("RESEAU CACHE", "NOM DU RESEAU (SSID) :", "", 32)
    redraw_all()
    if not ssid or ssid == "" then set_msg("ANNULE"); return end
    local ok, out = connect_to(ssid, true, true)
    after_action(ok, out, "CONNECTE A " .. ascii(ssid))
end

local function action_disconnect()
    local wifi = state.wifi
    if not wifi or wifi.state ~= "connected" then set_msg("LE WI-FI N'EST PAS CONNECTE"); return end
    local ok = minitel.confirm_box("DECONNEXION", "Deconnecter le Wi-Fi de " .. ascii(wifi.conn or "") .. " ?")
    redraw_all()
    if not ok then set_msg("ANNULE"); return end
    set_msg("DECONNEXION...")
    local done, out = run("nmcli device disconnect " .. sh_quote(wifi.name))
    after_action(done, out, "WI-FI DECONNECTE")
end

local function action_forget()
    local net = state.nets[state.cursor]
    if not net or not state.saved[net.ssid] then set_msg("CE RESEAU N'EST PAS ENREGISTRE"); return end
    local ok = minitel.confirm_box("OUBLIER", "Oublier " .. ascii(net.ssid) .. " et son mot de passe ?")
    redraw_all()
    if not ok then set_msg("ANNULE"); return end
    local done, out = run("nmcli connection delete id " .. sh_quote(net.ssid))
    after_action(done, out, "RESEAU " .. ascii(net.ssid) .. " OUBLIE")
end

local function action_nmtui()
    minitel.cleanup()
    os.execute("bash outils/shell_minitel.sh nmtui")
    minitel.init()
    redraw_all()
    refresh(false)
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
draw_static()
refresh(false)
check_internet()

local last_auto = os.time()
while true do
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "z" or k == "Z" or k == "UP" then
            state.cursor = state.cursor > 1 and state.cursor - 1 or math.max(1, #state.nets)
            draw_list()
        elseif k == "s" or k == "S" or k == "DOWN" then
            state.cursor = state.cursor < #state.nets and state.cursor + 1 or 1
            draw_list()
        elseif k == "ENVOI" then action_connect()
        elseif k == "a" or k == "A" then refresh(true); check_internet()
        elseif k == "d" or k == "D" then action_disconnect()
        elseif k == "o" or k == "O" then action_forget()
        elseif k == "c" or k == "C" then action_hidden()
        elseif k == "n" or k == "N" then action_nmtui()
        elseif k == "REPETITION" then redraw_all()
        end
        io.write("\x1b[24;80H")
        io.flush()
        last_auto = os.time()
    elseif os.time() - last_auto >= 15 then
        -- etat des interfaces tenu a jour sans nouvelle recherche Wi-Fi
        state.eth, state.wifi = read_devices()
        draw_devices()
        io.write("\x1b[24;80H")
        io.flush()
        last_auto = os.time()
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
