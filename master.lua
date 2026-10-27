local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- DETECTION RESEAU & TELEMETRIE SYSTEME (LINUX / RASPBERRY PI)
-- =====================================================================
local function get_network_info()
    local info = { connected = false, ip = "HORS LIGNE" }
    local success = os.execute("ping -c 1 -W 1 1.1.1.1 > /dev/null 2>&1")
    
    if success == true or success == 0 then
        info.connected = true
        -- Commande universelle Linux (iproute2 + fallback hostname) avec stderr masque partout
        local cmd = "(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"src\") print $(i+1)}'; hostname -I 2>/dev/null | awk '{print $1}') | head -n 1"
        local f_ip = io.popen(cmd)
        if f_ip then
            local ip = f_ip:read("*l")
            f_ip:close()
            if ip and ip ~= "" then
                info.ip = ip
            else
                info.ip = "LOCALE"
            end
        end
    end
    return info
end

local function get_sys_metrics()
    local temp = "N/A"
    local up = "ACTIF"
    
    local f_t = io.open("/sys/class/thermal/thermal_zone0/temp", "r")
    if f_t then
        local t = tonumber(f_t:read("*l"))
        f_t:close()
        if t then temp = string.format("%.1f C", t / 1000) end
    end
    
    local f_u = io.open("/proc/uptime", "r")
    if f_u then
        local line = f_u:read("*l")
        f_u:close()
        if line then
            local sec = tonumber(string.match(line, "^(%d+)"))
            if sec then
                local h = math.floor(sec / 3600)
                local m = math.floor((sec % 3600) / 60)
                up = string.format("%02dh%02dm", h, m)
            end
        end
    end
    return temp, up
end

local net_info = get_network_info()

-- =====================================================================
-- UTILITAIRES DE FORMATAGE TEXTE
-- =====================================================================
local function pad_str(str, len)
    if #str > len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

local function center_str(str, len)
    if #str >= len then return string.sub(str, 1, len) end
    local left = math.floor((len - #str) / 2)
    local right = len - #str - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function wrap_text(text, max_width, max_lines)
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        if #current + #word + 1 > max_width then
            table.insert(lines, pad_str(current, max_width))
            current = word
            if #lines >= max_lines then break end
        else
            current = (current == "") and word or (current .. " " .. word)
        end
    end
    if #lines < max_lines and current ~= "" then
        table.insert(lines, pad_str(current, max_width))
    end
    while #lines < max_lines do
        table.insert(lines, string.rep(" ", max_width))
    end
    return lines
end

-- =====================================================================
-- CATALOGUE DES MODULES DU PORTAIL MAITRE
-- =====================================================================
local options = {}
local cursor = 1
local offset = 0
local max_visible = 12
local list_start_y = 8

local function build_options()
    options = {
        {
            display = "3615 JEUX",
            title = "SALLE D'ARCADE",
            type = "DIVERTISSEMENT",
            cmd = "lua5.3 launcher_jeux.lua",
            art = {
                "       .------------.     ",
                "       | [CARTOUCHE]|     ",
                "       |   .----.   |     ",
                "       |   | () |   |     ",
                "       '---'----'---'     "
            },
            desc = "Accedez au catalogue de jeux du Magis Club : Casino Poker, Rogue-like Enigma et fictions interactives."
        },
        {
            display = "3615 OUTILS",
            title = "POSTE DE TRAVAIL",
            type = "BUREAUTIQUE & TELEMATIQUE",
            cmd = "lua5.3 launcher_utils.lua",
            art = {
                "     .----------------.   ",
                "     | [CALC]  [TRAIN]|   ",
                "     | [EDIT]  [SYS]  |   ",
                "     '----------------'   ",
                "      =======()=======    "
            },
            desc = "Suite logicielle : tableur dynamique multi-feuilles, horaires SNCF en direct et utilitaires systeme."
        },
        {
            display = "MAGIS EDIT",
            title = "EDITEUR DE CODE",
            type = "DEVELOPPEMENT RAPIDE",
            cmd = "lua5.3 utils/edit.lua",
            art = {
                "   .--------------------. ",
                "   | 10 PRINT \"MAGIS\"   | ",
                "   | 20 GOTO 10         | ",
                "   | > _                | ",
                "   '--------------------' "
            },
            desc = "Acces direct a l'editeur de texte plein ecran avec gestionnaire de fichiers style Norton Commander."
        }
    }

    if net_info.connected then
        table.insert(options, {
            display = "MISE A JOUR GIT",
            title = "SYNCHRONISATION",
            type = "MAINTENANCE DEPOT",
            cmd = "update",
            art = {
                "      .---.      .---.    ",
                "     | GIT |<-->| MAG |   ",
                "      '---'      '---'    ",
                "     PULL / PUSH / BKP    ",
                "   ====================== "
            },
            desc = "Synchronise le systeme avec le serveur Git distant. Gere les conflits locaux, sauvegardes et envois (Push)."
        })
    end

    table.insert(options, {
        display = "CONFIG RESEAU",
        title = "3615 RESEAU",
        type = "ADMINISTRATION IP/WIFI",
        cmd = "lua5.3 utils/reseau.lua",
        art = {
            "          ( ( ( ) ) )     ",
            "             \\ | /        ",
            "              (|)         ",
            "             / | \\        ",
            "         [ ETH0 / WLAN ]  "
        },
        desc = "Etat de l'Ethernet et du Wi-Fi, recherche des reseaux et connexion avec mot de passe. [N] ouvre nmtui pour les reglages avances."
    })

    table.insert(options, {
        display = "TERMINAL BASH",
        title = "CONSOLE LINUX",
        type = "ACCES DIRECT HOTE",
        cmd = "bash outils/shell_minitel.sh",
        art = {
            "   .--------------------. ",
            "   | minitel@host:~$ _  | ",
            "   |                    | ",
            "   | [SHELL INTERACTIF] | ",
            "   '--------------------' "
        },
        desc = "Ouvre une session shell Bash native sur le Raspberry Pi. Tapez 'exit' pour revenir au portail Magis."
    })

    table.insert(options, {
        display = "REDEMARRAGE",
        title = "REBOOT SYSTEME",
        type = "ALIMENTATION",
        cmd = "sudo reboot",
        art = {
            "          .------.        ",
            "         /   ||   \\       ",
            "        |    ||    |      ",
            "         \\  '--'  /       ",
            "          '------'        "
        },
        desc = "Redemarre completement le systeme hote Linux et reinitialise tous les services telematiques."
    })

    table.insert(options, {
        display = "EXTINCTION",
        title = "ARRET COMPLET",
        type = "ALIMENTATION",
        cmd = "sudo poweroff",
        art = {
            "       .------------.     ",
            "       |  ARRET DU  |     ",
            "       |  SYSTEME   |     ",
            "       |   [OFF]    |     ",
            "       '------------'     "
        },
        desc = "Parcage des disques et extinction securisee de l'hote Linux avant coupure electrique du Minitel."
    })
end

build_options()

-- =====================================================================
-- FAUX ECRAN DE DEMARRAGE (AUTOTEST FACON MICRO DES ANNEES 80)
-- =====================================================================
-- Affiche apres l'initialisation, une fois le Minitel en 80 colonnes. Les
-- informations sont vraies (modele, memoire, noyau, modules, reseau) ; le test
-- reseau affiche est celui dont le portail a besoin. Une touche abrege tout.
local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*l"); f:close()
    return s
end

local function shell_line(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return nil end
    local s = f:read("*l"); f:close()
    return s
end

local function run_boot_sequence()
    local skip = false
    -- Attente interruptible : une touche fait passer tout le reste sans delai
    local function wait(sec)
        if skip then return end
        local steps = math.max(1, math.floor(sec / 0.05))
        for _ = 1, steps do
            if minitel.get_key() then skip = true; return end
            minitel.sleep(0.05)
        end
    end
    local row = 6
    local function line(label)
        label = string.sub(label, 1, 61)
        io.write(string.format("\x1b[%d;4H%s", row, label .. " " .. string.rep(".", 62 - #label)))
        io.flush()
    end
    local function status(text, inverse)
        io.write(string.format("\x1b[%d;68H%s", row, inverse and ("\x1b[7m " .. text .. " \x1b[0m") or text))
        io.flush()
        row = row + 1
    end

    io.write("\x1b[r\x1b[0m\x1b[2J")
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m" .. center_str("MAGIS CLUB  -  SYSTEME TELEMATIQUE  -  AUTOTEST DE DEMARRAGE", 80) .. "\x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[24;1H\x1b[7m" .. center_str("UNE TOUCHE POUR PASSER", 80) .. "\x1b[0m")
    io.flush()
    minitel.play_sound("hit")
    wait(0.6)

    -- Processeur
    local model = (read_first_line("/proc/device-tree/model") or "PROCESSEUR INCONNU"):gsub("%z", "")
    line("UNITE CENTRALE : " .. string.sub(string.upper(model), 1, 40))
    wait(0.4); status("OK", true)

    -- Memoire : compteur qui grimpe jusqu'a la taille reelle
    local mem_kb = 0
    for l in (io.open("/proc/meminfo") or { lines = function() return function() end end }):lines() do
        local v = l:match("^MemTotal:%s+(%d+)")
        if v then mem_kb = tonumber(v); break end
    end
    line("TEST MEMOIRE")
    for i = 1, 12 do
        io.write(string.format("\x1b[%d;55H%9d KO", row, math.floor(mem_kb * i / 12)))
        io.flush()
        wait(0.08)
    end
    status("OK", true)

    line("LIAISON MINITEL : 9600 BAUDS 8N1, VT100 80 COLONNES")
    wait(0.3); status("OK", true)

    local sox = shell_line("command -v play")
    line("SYNTHESE SONORE (SOX) SUR LA SORTIE AUDIO DU PI")
    wait(0.3); status(sox and "OK" or "ABSENTE", sox ~= nil)

    local kernel = (shell_line("uname -r") or "?"):match("^[%d%.]+") or "?"
    line("NOYAU LINUX " .. kernel .. " / INTERPRETEUR " .. string.upper(_VERSION))
    wait(0.3); status("OK", true)

    local function count(dir)
        return tonumber(shell_line("ls -1 " .. dir .. "/*.lua | wc -l")) or 0
    end
    line("CARTOUCHES DE JEUX (jeux/)")
    wait(0.25); status(string.format("%d TROUVEES", count("jeux")))
    line("OUTILS (utils/)")
    wait(0.25); status(string.format("%d TROUVES", count("utils")))

    line("RESEAU")
    io.write(string.format("\x1b[%d;68HTEST...", row)); io.flush()
    local net = get_network_info()
    io.write(string.format("\x1b[%d;68H       ", row))
    status(net.connected and "EN LIGNE" or "HORS LIGNE", net.connected)
    if net.connected then
        io.write(string.format("\x1b[%d;8HADRESSE IP : %s", row, net.ip))
        row = row + 1
    end

    -- Barre de progression finale
    row = row + 1
    io.write(string.format("\x1b[%d;4HCHARGEMENT DU PORTAIL  [%s]", row, string.rep(" ", 40)))
    for i = 1, 40, 4 do
        io.write(string.format("\x1b[%d;28H\x1b[7m%s\x1b[0m", row, string.rep(" ", i + 3)))
        io.flush()
        wait(0.05)
    end
    minitel.play_sound("win")
    wait(0.8)
    return net
end

-- Met a jour uniquement l'interieur des pieds de cadres (Col 3-36 et Col 41-78) sans toucher aux bordures !
local function draw_telemetry_bar()
    local temp, up = get_sys_metrics()
    local t_str = pad_str(temp, 7)
    local u_str = pad_str(up, 7)

    -- Pied Gauche (34 caracteres entre col 3 et col 36)
    local status_left = string.format("CPU: %s | UP: %s", t_str, u_str)
    io.write(string.format("\x1b[21;3H\x1b[1m%s\x1b[0m", center_str(status_left, 34)))

    -- Pied Droit (38 caracteres exacts entre col 41 et col 78)
    local status_badge = net_info.connected and "\x1b[7m EN LIGNE \x1b[0m" or "HORS LIGNE"
    local ip_str = pad_str(net_info.ip, 15)
    -- 1 (" ") + 4 ("NET:") + 10 (badge) + 4 (" IP:") + 15 (ip_str) + 4 ("    ") = 38 colonnes exactes !
    io.write("\x1b[21;41H NET:" .. status_badge .. " IP:" .. ip_str .. "    ")
    io.flush()
end

-- Contenu actuellement affiche dans le panneau de droite, ligne par ligne :
-- seuls les caracteres qui changent sont renvoyes au Minitel
local panel_shown = {}

-- Mode Turbo [H], actif par defaut : le panneau de droite ne suit le curseur
-- qu'apres 0,3 s d'immobilite ; en mode direct, il suit chaque mouvement
local fast_mode = true
local TURBO_DELAY = 0.3

local function get_mono_time()
    local f = io.open("/proc/uptime", "r")
    if f then
        local s = f:read("*l")
        f:close()
        local up = s and tonumber(s:match("^([%d%.]+)"))
        if up then return up end
    end
    return os.time()
end

local function draw_right_header_badge()
    local badge = fast_mode and "APERCU SYSTEME [H: TURBO 0.3S]" or "APERCU SYSTEME [H: DIRECT]"
    io.write("\x1b[6;40H|\x1b[7m" .. center_str(badge, 38) .. "\x1b[0m|")
end

local function draw_static_portal()
    io.write("\x1b[r\x1b[2J\x1b[H")
    panel_shown = {}
    minitel.sleep(0.04)

    -- Bandeau Superieur (3 lignes)
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m  [OS]   " .. center_str("* * *  PORTAIL SYSTEME : MAGIS CLUB  * * *", 60) .. "  9600 BDS \x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    -- Entetes des 2 panneaux (Ligne 5)
    io.write("\x1b[5;2H.----------------------------------.")
    io.write("\x1b[5;40H.--------------------------------------.")

    io.write("\x1b[6;2H|\x1b[7m" .. center_str("COMMANDES & MODULES", 34) .. "\x1b[0m|")
    draw_right_header_badge()

    io.write("\x1b[7;2H|----------------------------------|")
    io.write("\x1b[7;40H|--------------------------------------|")

    -- Corps des panneaux (Lignes 8 a 19) : l'ecran vient d'etre efface, seules
    -- les bordures sont envoyees, pas les espaces interieurs
    for y = 8, 19 do
        io.write(string.format("\x1b[%d;2H|\x1b[%d;37H|\x1b[%d;40H|\x1b[%d;79H|", y, y, y, y))
    end

    -- Separateur interne dans le panneau droit (Ligne 13)
    io.write("\x1b[13;40H|--------------------------------------|")

    -- Bas des panneaux (Lignes 20 et 21)
    io.write("\x1b[20;2H|----------------------------------|")
    io.write("\x1b[20;40H|--------------------------------------|")

    io.write("\x1b[21;2H|\x1b[21;37H|\x1b[21;40H|\x1b[21;79H|")

    io.write("\x1b[22;2H'----------------------------------'")
    io.write("\x1b[22;40H'--------------------------------------'")

    -- Bandeau Inferieur (Ligne 24)
    io.write("\x1b[24;1H\x1b[7m  [Z/S] NAVIGUER   |   [ENVOI] VALIDER   |   [R] RECHERCHE LUA   |   [H] TURBO  \x1b[0m")
    -- La barre de telemetrie est dessinee par draw_full_list, appele juste apres
end

-- Ecrit une ligne du panneau de droite en n'envoyant que la portion qui
-- differe de ce qui est deja affiche (de la premiere a la derniere difference)
local function panel_line(y, x, text, bold)
    local old = panel_shown[y]
    if old == text then return end
    local i, j = 1, #text
    if old and #old == #text then
        while string.byte(old, i) == string.byte(text, i) do i = i + 1 end
        while string.byte(old, j) == string.byte(text, j) do j = j - 1 end
    end
    io.write(string.format("\x1b[%d;%dH", y, x + i - 1)
        .. (bold and "\x1b[1m" or "") .. string.sub(text, i, j) .. (bold and "\x1b[0m" or ""))
    panel_shown[y] = text
end

local function draw_details_panel()
    local item = options[cursor]
    if not item then return end

    for i = 1, 5 do
        panel_line(7 + i, 41, center_str(item.art[i] or "", 38), true)
    end

    panel_line(14, 42, pad_str("CIBLE : " .. item.title, 36), true)
    panel_line(15, 42, pad_str("TYPE  : " .. item.type, 36), false)

    local desc_lines = wrap_text(item.desc, 36, 3)
    for i = 1, 3 do
        panel_line(16 + i, 42, desc_lines[i], false)
    end
end

local function format_list_entry(idx, is_selected)
    local item = options[idx]
    if not item then return string.rep(" ", 32) end
    local num_str = string.format("%02d.", idx)
    local label = num_str .. " " .. pad_str(item.display, 24)
    if is_selected then
        return "\x1b[7m > " .. label .. " < \x1b[0m"
    else
        return "   " .. label .. "   "
    end
end

local function draw_full_list()
    for i = 1, max_visible do
        local idx = offset + i
        local y = list_start_y + i - 1
        io.write(string.format("\x1b[%d;3H%s", y, format_list_entry(idx, idx == cursor)))
    end
    draw_details_panel()
    draw_telemetry_bar()
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_y = list_start_y + (old_index - offset) - 1
    local new_y = list_start_y + (new_index - offset) - 1

    if old_y >= list_start_y and old_y < list_start_y + max_visible then
        io.write(string.format("\x1b[%d;3H%s", old_y, format_list_entry(old_index, false)))
    end
    if new_y >= list_start_y and new_y < list_start_y + max_visible then
        io.write(string.format("\x1b[%d;3H%s", new_y, format_list_entry(new_index, true)))
    end
    -- Le panneau de droite suit quand le curseur s'arrete (voir details_due_ts)
    io.flush()
end

-- =====================================================================
-- MOTEUR DE RECHERCHE GLOBALE LUA
-- =====================================================================
local function search_and_launch()
    local str = minitel.input_box("RECHERCHE GLOBALE LUA", "Nom du script a chercher et lancer :", "", 30)
    if str and str ~= "" then
        str = string.lower(str:gsub("%s+", ""))
        local cmd = "find . -maxdepth 2 -name '*" .. str .. "*.lua' 2>/dev/null | head -n 1"
        local f = io.popen(cmd)
        local result = f and f:read("*l") or nil
        if f then f:close() end

        if result and result ~= "" then
            minitel.play_sound("pickup")
            minitel.cleanup()
            os.execute("lua5.3 " .. result)
            minitel.init()
            return true
        else
            minitel.msg_box("INTROUVABLE", "Aucun script Lua ne correspond a : " .. str, "lose")
        end
    end
    return false
end

-- =====================================================================
-- GESTION DE L'ECRAN DE VEILLE (SCREENSAVER)
-- =====================================================================
-- Une grande horloge en chiffres de blocs (video inverse), la date dessous,
-- et un ciel d'etoiles qui scintillent. L'horloge change de place toutes les
-- 20 secondes pour ne jamais marquer le tube. Chaque image n'envoie que les
-- quelques caracteres qui changent : etoiles, deux-points, minute.

-- Police 3 x 5 : chaque pixel allume devient deux espaces en video inverse
local SS_FONT = {
    ["0"] = {"111", "101", "101", "101", "111"},
    ["1"] = {"010", "110", "010", "010", "111"},
    ["2"] = {"111", "001", "111", "100", "111"},
    ["3"] = {"111", "001", "111", "001", "111"},
    ["4"] = {"101", "101", "111", "001", "001"},
    ["5"] = {"111", "100", "111", "001", "111"},
    ["6"] = {"111", "100", "111", "101", "111"},
    ["7"] = {"111", "001", "001", "010", "010"},
    ["8"] = {"111", "101", "111", "101", "111"},
    ["9"] = {"111", "101", "111", "001", "111"},
}
local SS_JOURS = {"DIMANCHE", "LUNDI", "MARDI", "MERCREDI", "JEUDI", "VENDREDI", "SAMEDI"}
local SS_MOIS = {"JANVIER", "FEVRIER", "MARS", "AVRIL", "MAI", "JUIN", "JUILLET",
                 "AOUT", "SEPTEMBRE", "OCTOBRE", "NOVEMBRE", "DECEMBRE"}
local SS_W, SS_H = 32, 7          -- horloge (5 lignes) + ligne vide + date
local SS_COLON_X = 15             -- decalage des deux-points dans l'horloge
local SS_TWINKLE = {".", "+", "*", "+", "."}
local SS_NB_STARS = 22

local ss = { x = 24, y = 8, hhmm = nil, colon = nil, moved = 0, stars = {} }

-- Une ligne de l'horloge, codee par plages pour economiser les sequences
local function ss_clock_row(hhmm, row)
    local cells = {}
    local function put(col, on) cells[col] = on; cells[col + 1] = on end
    local digits = { hhmm:sub(1, 1), hhmm:sub(2, 2), hhmm:sub(3, 3), hhmm:sub(4, 4) }
    local starts = { 1, 9, 19, 27 }
    for d = 1, 4 do
        local bits = SS_FONT[digits[d]][row]
        for b = 1, 3 do put(starts[d] + (b - 1) * 2, bits:sub(b, b) == "1") end
    end
    local out, inv = {}, false
    for col = 1, SS_W do
        local on = cells[col] == true
        if on ~= inv then out[#out + 1] = on and "\x1b[7m" or "\x1b[0m"; inv = on end
        out[#out + 1] = " "
    end
    if inv then out[#out + 1] = "\x1b[0m" end
    return table.concat(out)
end

local function ss_draw_colon(visible)
    local seq = visible and "\x1b[7m  \x1b[0m" or "  "
    io.write(string.format("\x1b[%d;%dH%s\x1b[%d;%dH%s",
        ss.y + 1, ss.x + SS_COLON_X, seq, ss.y + 3, ss.x + SS_COLON_X, seq))
end

local function ss_draw_clock(t)
    local hhmm = string.format("%02d%02d", t.hour, t.min)
    for row = 1, 5 do
        io.write(string.format("\x1b[%d;%dH", ss.y + row - 1, ss.x) .. ss_clock_row(hhmm, row))
    end
    local date = string.format("%s %d %s %d", SS_JOURS[t.wday], t.day, SS_MOIS[t.month], t.year)
    local pad = math.floor((SS_W - #date) / 2)
    io.write(string.format("\x1b[%d;%dH%s", ss.y + 6, ss.x, string.rep(" ", pad) .. date .. string.rep(" ", SS_W - pad - #date)))
    ss.hhmm, ss.colon = hhmm, nil
end

-- Une etoile ne doit jamais tomber sur l'horloge (marge d'une case)
local function ss_new_star()
    while true do
        local x, y = math.random(1, 79), math.random(1, 24)
        if x < ss.x - 1 or x > ss.x + SS_W or y < ss.y - 1 or y > ss.y + SS_H then
            return { x = x, y = y, phase = -math.random(0, 8) }
        end
    end
end

-- Nouvelle position de l'horloge, ecran efface, nouveau ciel
local function ss_relocate(t)
    ss.x = math.random(2, 80 - SS_W)
    ss.y = math.random(1, 25 - SS_H)
    io.write("\x1b[0m\x1b[2J")
    ss.stars = {}
    for i = 1, SS_NB_STARS do ss.stars[i] = ss_new_star() end
    ss_draw_clock(t)
    ss.moved = os.time()
end

local function start_screensaver()
    math.randomseed(os.time())
    ss_relocate(os.date("*t"))
    io.flush()
end

local function run_screensaver_frame()
    local now = os.time()
    local t = os.date("*t", now)

    if now - ss.moved >= 20 then ss_relocate(t)
    elseif string.format("%02d%02d", t.hour, t.min) ~= ss.hhmm then ss_draw_clock(t) end

    -- Les deux-points battent la seconde
    local colon = (t.sec % 2 == 0)
    if colon ~= ss.colon then ss_draw_colon(colon); ss.colon = colon end

    -- Chaque etoile parcourt . + * + . puis s'eteint et renait ailleurs
    for i = 1, 2 do
        local s = ss.stars[math.random(1, #ss.stars)]
        s.phase = s.phase + 1
        if s.phase >= 1 then
            local ch = SS_TWINKLE[s.phase]
            if ch then
                io.write(string.format("\x1b[%d;%dH%s", s.y, s.x, ch))
            else
                io.write(string.format("\x1b[%d;%dH ", s.y, s.x))
                local n = ss_new_star()
                s.x, s.y, s.phase = n.x, n.y, n.phase
            end
        end
    end
    -- Curseur range dans le coin, loin de l'horloge
    io.write("\x1b[24;80H")
    io.flush()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
local state = "MENU"

-- Fin de l'initialisation, le Minitel etant en 80 colonnes : autotest de
-- demarrage, qui fait au passage le test reseau dont depend la mise a jour
local function finish_boot()
    os.execute("touch /tmp/minitel_warmboot")
    net_info = run_boot_sequence()
    if net_info.connected then
        -- Si une nouvelle version est installee, l'updater redemarre
        -- la session ; sinon il rend la main et on passe au menu.
        minitel.cleanup()
        os.execute("lua5.3 updater.lua")
        minitel.init()
    end

    build_options()
    state = "MENU"
    draw_static_portal()
    draw_full_list()
end

local f = io.open("/tmp/minitel_warmboot", "r")
if f then
    state = "MENU"
    f:close()
    draw_static_portal()
    draw_full_list()
else
    io.write("\x1b[2J\x1b[H")
    io.flush()
    -- Le Minitel a ete mis en 80 colonnes par l'ecran de demarrage du Pi
    -- (boot_minitel.lua). A la main : voir le manuel (§ 1.4).
    finish_boot()
end

local last_net_update = os.time()
local last_input_time = os.time()
local INACTIVITY_TIMEOUT = 90
local pending_key = nil   -- touche lue en avance pendant un deplacement groupe
local details_due_ts = nil -- instant du dernier mouvement, panneau a rattraper

local function is_nav_key(k)
    return k == "z" or k == "Z" or k == "UP" or k == "s" or k == "S" or k == "DOWN"
end

while true do
    local key = pending_key or minitel.get_key()
    pending_key = nil
    local now = os.time()
    
    if key then 
        last_input_time = now 
        if state == "SCREENSAVER" then
            state = "MENU"
            draw_static_portal()
            draw_full_list()
            key = nil 
        end
    end
    
    if state == "MENU" then
        if now - last_input_time > INACTIVITY_TIMEOUT then
            state = "SCREENSAVER"
            start_screensaver()
        else
            -- Le test reseau (un ping qui peut bloquer une seconde hors ligne)
            -- attend que l'utilisateur ait cesse de naviguer depuis 5 secondes
            if now - last_net_update >= 30 and now - last_input_time >= 5 then
                local old_status = net_info.connected
                net_info = get_network_info()
                
                if net_info.connected ~= old_status then
                    build_options()
                    if cursor > #options then cursor = #options end
                    draw_full_list()
                else
                    draw_telemetry_bar()
                end
                last_net_update = now
            end
            
            if key then
                local old_cursor = cursor
                if is_nav_key(key) then
                    -- Toutes les fleches deja recues sont cumulees en un seul
                    -- deplacement : une touche maintenue ne fait pas d'embouteillage
                    local k = key
                    while k do
                        if k == "z" or k == "Z" or k == "UP" then
                            cursor = (cursor > 1) and (cursor - 1) or #options
                        else
                            cursor = (cursor < #options) and (cursor + 1) or 1
                        end
                        k = minitel.get_key()
                        if k and not is_nav_key(k) then pending_key = k; k = nil end
                    end
                    if cursor ~= old_cursor then
                        update_cursor(old_cursor, cursor)
                        if fast_mode then
                            details_due_ts = get_mono_time()
                        else
                            draw_details_panel()
                            io.flush()
                        end
                    end
                elseif key == "r" or key == "R" then
                    search_and_launch()
                    draw_static_portal()
                    draw_full_list()
                    last_net_update = os.time()
                elseif key == "REPETITION" then
                    draw_static_portal()
                    draw_full_list()
                elseif key == "h" or key == "H" then
                    fast_mode = not fast_mode
                    draw_right_header_badge()
                    details_due_ts = nil
                    draw_details_panel()
                    io.flush()
                elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                    local selected = options[cursor]
                    minitel.play_sound("hit")
                    io.write("\x1b[21;41H\x1b[7m" .. center_str("LANCEMENT : " .. selected.display, 38) .. "\x1b[0m")
                    io.flush()
                    minitel.sleep(0.2)

                    -- L'updater ne rend la main que s'il n'y a rien a recharger
                    local cmd = selected.cmd
                    if cmd == "update" then cmd = "lua5.3 updater.lua" end

                    minitel.cleanup()
                    os.execute(cmd)
                    minitel.init()

                    net_info = get_network_info()
                    build_options()
                    if cursor > #options then cursor = #options end
                    last_net_update = os.time()
                    last_input_time = os.time()

                    draw_static_portal()
                    draw_full_list()
                end
            end

            -- Curseur immobile depuis TURBO_DELAY : le panneau de droite le rattrape
            if details_due_ts then
                if get_mono_time() - details_due_ts >= TURBO_DELAY then
                    details_due_ts = nil
                    draw_details_panel()
                    io.flush()
                end
            end
        end
        minitel.sleep(0.02)
        
    elseif state == "SCREENSAVER" then
        run_screensaver_frame()
        minitel.sleep(0.1) 
    end
end

minitel.cleanup()