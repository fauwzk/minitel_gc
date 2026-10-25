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
        title = "INTERFACE NMTUI",
        type = "ADMINISTRATION IP/WIFI",
        cmd = "TERM=vt100 nmtui",
        art = {
            "          ( ( ( ) ) )     ",
            "             \\ | /        ",
            "              (|)         ",
            "             / | \\        ",
            "         [ ETH0 / WLAN ]  "
        },
        desc = "Configurez les connexions Wi-Fi, les parametres Ethernet et le routage reseau de l'hote Linux."
    })

    table.insert(options, {
        display = "TERMINAL BASH",
        title = "CONSOLE LINUX",
        type = "ACCES DIRECT HOTE",
        cmd = "bash",
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
-- AFFICHAGE DU SQUELETTE ET DES ENCARTS (9600 BAUDS)
-- =====================================================================
local function draw_boot_screen()
    io.write("\x1b[1;1H\x1b[K========================================")
    io.write("\x1b[2;1H\x1b[K\x1b[7m  INITIALISATION MAGIS CLUB REQUISE   \x1b[0m")
    io.write("\x1b[3;1H\x1b[K========================================")
    io.write("\x1b[5;1H\x1b[KVeuillez taper ces commandes au clavier:")
    io.write("\x1b[7;1H\x1b[K1. 80 Colonnes : \x1b[1mCtrl+Esc\x1b[0m puis \x1b[1mT\x1b[0m puis \x1b[1mA\x1b[0m")
    io.write("\x1b[8;1H\x1b[K2. Echo OFF    : \x1b[1mCtrl+Esc\x1b[0m puis \x1b[1mT\x1b[0m puis \x1b[1mE\x1b[0m")
    io.write("\x1b[9;1H\x1b[K3. Clav. Etendu: \x1b[1mCtrl+Esc\x1b[0m puis \x1b[1mC\x1b[0m puis \x1b[1mE\x1b[0m")
    io.write("\x1b[12;1H\x1b[K(Le terminal s'effacera a chaque fois)")
    io.write("\x1b[15;1H\x1b[K\x1b[7m APPUYEZ SUR [ENVOI] QUAND TERMINE. \x1b[0m")
    io.flush()
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

local function draw_static_portal()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Bandeau Superieur (3 lignes)
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m  [OS]   " .. center_str("* * *  PORTAIL SYSTEME : MAGIS CLUB  * * *", 60) .. "  9600 BDS \x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    -- Entetes des 2 panneaux (Ligne 5)
    io.write("\x1b[5;2H.----------------------------------.")
    io.write("\x1b[5;40H.--------------------------------------.")

    io.write("\x1b[6;2H|\x1b[7m" .. center_str("COMMANDES & MODULES", 34) .. "\x1b[0m|")
    io.write("\x1b[6;40H|\x1b[7m" .. center_str("MONITEUR & APERCU SYSTEME", 38) .. "\x1b[0m|")

    io.write("\x1b[7;2H|----------------------------------|")
    io.write("\x1b[7;40H|--------------------------------------|")

    -- Corps des panneaux (Lignes 8 a 19)
    for y = 8, 19 do
        io.write(string.format("\x1b[%d;2H|                                  |", y))
        io.write(string.format("\x1b[%d;40H|                                      |", y))
    end

    -- Separateur interne dans le panneau droit (Ligne 13)
    io.write("\x1b[13;40H|--------------------------------------|")

    -- Bas des panneaux (Lignes 20 et 21)
    io.write("\x1b[20;2H|----------------------------------|")
    io.write("\x1b[20;40H|--------------------------------------|")

    io.write("\x1b[21;2H|                                  |")
    io.write("\x1b[21;40H|                                      |")

    io.write("\x1b[22;2H'----------------------------------'")
    io.write("\x1b[22;40H'--------------------------------------'")

    -- Bandeau Inferieur (Ligne 24)
    io.write("\x1b[24;1H\x1b[7m  [Z/S] NAVIGUER   |   [ENVOI] VALIDER   |   [R] RECHERCHE LUA   |   [VEILLE]   \x1b[0m")
    draw_telemetry_bar()
end

local function draw_details_panel()
    local item = options[cursor]
    if not item then return end

    for i = 1, 5 do
        local art_line = item.art[i] or ""
        io.write(string.format("\x1b[%d;41H\x1b[1m%s\x1b[0m", 7 + i, center_str(art_line, 38)))
    end

    local title_line = "CIBLE : " .. item.title
    local type_line  = "TYPE  : " .. item.type
    io.write(string.format("\x1b[14;42H\x1b[1m%s\x1b[0m", pad_str(title_line, 36)))
    io.write(string.format("\x1b[15;42H%s", pad_str(type_line, 36)))

    local desc_lines = wrap_text(item.desc, 36, 3)
    for i = 1, 3 do
        io.write(string.format("\x1b[%d;42H%s", 16 + i, desc_lines[i]))
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

    draw_details_panel()
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
local state = "BOOT"
local f = io.open("/tmp/minitel_warmboot", "r")
if f then
    state = "MENU"
    f:close()
    draw_static_portal()
    draw_full_list()
else
    io.write("\x1b[2J\x1b[H")
end

local last_boot_draw = 0
local last_net_update = os.time()
local last_input_time = os.time()
local INACTIVITY_TIMEOUT = 90

while true do
    local key = minitel.get_key()
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
    
    if state == "BOOT" then
        if now - last_boot_draw >= 1 then
            draw_boot_screen()
            last_boot_draw = now
        end
        
        if key == "ENVOI" or key == " " or key == "\n" or key == "\r" then
            minitel.play_sound("hit")
            os.execute("touch /tmp/minitel_warmboot")
            
            net_info = get_network_info()
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
        
    elseif state == "MENU" then
        if now - last_input_time > INACTIVITY_TIMEOUT then
            state = "SCREENSAVER"
            start_screensaver()
        else
            if now - last_net_update >= 30 then
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
                if key == "z" or key == "Z" or key == "UP" then
                    cursor = (cursor > 1) and (cursor - 1) or #options
                    update_cursor(old_cursor, cursor)
                elseif key == "s" or key == "S" or key == "DOWN" then
                    cursor = (cursor < #options) and (cursor + 1) or 1
                    update_cursor(old_cursor, cursor)
                elseif key == "r" or key == "R" then
                    search_and_launch()
                    draw_static_portal()
                    draw_full_list()
                    last_net_update = os.time()
                elseif key == "REPETITION" then
                    draw_static_portal()
                    draw_full_list()
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
        end
        minitel.sleep(0.02)
        
    elseif state == "SCREENSAVER" then
        run_screensaver_frame()
        minitel.sleep(0.1) 
    end
end

minitel.cleanup()