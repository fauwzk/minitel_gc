local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- DETECTION RESEAU & SYSTEME AVANCEE
-- =====================================================================
local function get_network_info()
    local info = { connected = false, ip = "HORS LIGNE" }
    local success = os.execute("ping -c 1 -W 1 github.com > /dev/null 2>&1")
    
    if success == true or success == 0 then
        info.connected = true
        -- Récupération de l'adresse IP locale via le système
        local f_ip = io.popen("hostname -I | awk '{print $1}' 2>/dev/null")
        if f_ip then
            local ip = f_ip:read("*l")
            if ip and ip ~= "" then info.ip = ip else info.ip = "INCONNUE" end
            f_ip:close()
        end
    end
    return info
end

local net_info = get_network_info()

-- =====================================================================
-- LISTE DES MODULES (Dynamique)
-- =====================================================================
local options = {}

local function build_options()
    options = {
        { name = "3615 JEUX (Modules de divertissement)", cmd = "lua5.3 launcher_jeux.lua" },
        { name = "3615 OUTILS (Modules utilitaires)", cmd = "lua5.3 launcher_utils.lua" }
    }

    if net_info.connected then
        table.insert(options, { name = "MISE A JOUR SYSTEME (Git Pull)", cmd = "update" })
    end

    table.insert(options, { name = "CONFIGURATION RESEAU (nmtui)", cmd = "TERM=vt100 nmtui" })
    table.insert(options, { name = "INVITE DE COMMANDE (Shell local)", cmd = "bash" })
    table.insert(options, { name = "EXTINCTION DU SYSTEME", cmd = "sudo poweroff" })
    table.insert(options, { name = "REDEMARRAGE DU SYSTEME", cmd = "sudo reboot" })
end

build_options()
local cursor = 1

-- =====================================================================
-- MOTEUR DE RECHERCHE GLOBALE LUA
-- =====================================================================
local function search_and_launch()
    -- Efface les lignes du bas et affiche l'invite de recherche
    io.write("\x1b[22;1H\x1b[K\x1b[23;1H\x1b[K\x1b[24;1H\x1b[K")
    io.write("\x1b[23;1H\x1b[7m RECHERCHE DE SCRIPT LUA : \x1b[0m ")
    io.flush()
    
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                break
            elseif k == "RETOUR" or k == "ESC" then
                return false
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D")
                    io.flush()
                end
            elseif string.match(k, "^[%w%s%p_]$") and #k == 1 then
                str = str .. string.lower(k)
                io.write(string.lower(k))
                io.flush()
            end
        end
        minitel.sleep(0.01)
    end

    if str ~= "" then
        io.write("\x1b[23;1H\x1b[K\x1b[1m Recherche en cours...\x1b[0m")
        io.flush()
        
        -- Recherche dans le dossier courant et les sous-dossiers (profondeur 2)
        local cmd = "find . -maxdepth 2 -name '*" .. str .. "*.lua' 2>/dev/null | head -n 1"
        local f = io.popen(cmd)
        local result = f:read("*l")
        f:close()

        if result and result ~= "" then
            minitel.play_sound("pickup")
            minitel.cleanup()
            os.execute("lua5.3 " .. result)
            minitel.init()
            return true
        else
            io.write("\x1b[23;1H\x1b[K\x1b[7m AUCUN SCRIPT TROUVE. APPUYEZ SUR [RETOUR] \x1b[0m")
            io.flush()
            while true do
                local k = minitel.get_key()
                if k == "RETOUR" or k == "ESC" or k == "ENVOI" or k == "\r" or k == "\n" then break end
                minitel.sleep(0.05)
            end
        end
    end
    return false
end

-- =====================================================================
-- INTERFACE GRAPHIQUE (PORTAIL SYSADMIN)
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

local function draw_menu()
    io.write("\x1b[2J\x1b[H")
    minitel.sleep(0.08)
    
    -- BANDEAU EN-TETE PORTAIL
    io.write("\x1b[1;1H\x1b[7m                                                                                \x1b[0m\r\n")
    io.write("\x1b[2;1H\x1b[7m      * * *   P O R T A I L   S Y S T E M E   :   M A G I S   C L U B   * * *   \x1b[0m\r\n")
    io.write("\x1b[3;1H\x1b[7m                                                                                \x1b[0m\r\n")
    
    -- PANNEAU D'INFORMATIONS RESEAU
    local status_badge = net_info.connected and "\x1b[7m CONNECTE \x1b[0m" or "HORS LIGNE"
    local formatted_ip = string.format("%-15s", net_info.ip)
    
    io.write("\x1b[5;4H+----------------------------------------------------------------------+\r\n")
    io.write("\x1b[6;4H|  \x1b[1mDIAGNOSTIC RESEAU\x1b[0m                                                 |\r\n")
    io.write("\x1b[7;4H|  STATUT INTERNET : " .. status_badge .. "             ADRESSE IP : " .. formatted_ip .. "  |\r\n")
    io.write("\x1b[8;4H+----------------------------------------------------------------------+\r\n")
    
    -- TITRE LISTE
    io.write("\x1b[11;4H\x1b[1m[ SELECTION DU MODULE D'EXECUTION ]\x1b[0m\r\n")
    
    -- BANDEAU PIED DE PAGE
    io.write("\x1b[23;1H\x1b[7m                                                                                \x1b[0m\r\n")
    io.write("\x1b[24;1H\x1b[7m  FLECHES: NAVIGUER  |  ENVOI: VALIDER  |  [R] RECHERCHE GLOBALE LUA            \x1b[0m")
    io.flush()
end

local function draw_list()
    for i=13, 21 do io.write("\x1b["..i..";1H\x1b[K") end
    for i, opt in ipairs(options) do
        local line_y = 12 + i
        if i == cursor then
            io.write("\x1b[" .. line_y .. ";8H\x1b[7m > " .. opt.name .. " \x1b[0m")
        else
            io.write("\x1b[" .. line_y .. ";8H   " .. opt.name .. "   ")
        end
    end
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_opt = options[old_index]
    if old_opt then io.write("\x1b[" .. (12 + old_index) .. ";1H\x1b[K\x1b[" .. (12 + old_index) .. ";8H   " .. old_opt.name .. "   ") end
    local new_opt = options[new_index]
    if new_opt then io.write("\x1b[" .. (12 + new_index) .. ";1H\x1b[K\x1b[" .. (12 + new_index) .. ";8H\x1b[7m > " .. new_opt.name .. " \x1b[0m") end
    io.flush()
end

-- =====================================================================
-- GESTION DE L'ECRAN DE VEILLE (SCREENSAVER)
-- =====================================================================
local ss_x, ss_y = 30, 12
local ss_dx, ss_dy = 1, 1
local ss_text = " \x1b[7m MAGIS CLUB SYS \x1b[0m "
local ss_len = 16 

local function run_screensaver_frame()
    io.write("\x1b["..ss_y..";"..ss_x.."H" .. string.rep(" ", ss_len))
    
    ss_x = ss_x + ss_dx
    ss_y = ss_y + ss_dy
    
    if ss_x <= 1 or ss_x + ss_len >= 81 then
        ss_dx = -ss_dx
        ss_x = ss_x + ss_dx * 2
    end
    if ss_y <= 1 or ss_y >= 25 then
        ss_dy = -ss_dy
        ss_y = ss_y + ss_dy * 2
    end
    
    io.write("\x1b["..ss_y..";"..ss_x.."H" .. ss_text)
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
    draw_menu()
    draw_list()
else
    io.write("\x1b[2J\x1b[H")
end

local last_boot_draw = 0
local last_net_update = os.time()
local last_input_time = os.time()
local INACTIVITY_TIMEOUT = 60

while true do
    local key = minitel.get_key()
    local now = os.time()
    
    if key then 
        last_input_time = now 
        if state == "SCREENSAVER" then
            state = "MENU"
            draw_menu()
            draw_list()
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
            state = "MENU"
            os.execute("touch /tmp/minitel_warmboot")
            draw_menu()
            draw_list()
        end
        
    elseif state == "MENU" then
        if now - last_input_time > INACTIVITY_TIMEOUT then
            state = "SCREENSAVER"
            io.write("\x1b[2J\x1b[H") 
            io.flush()
        else
            -- VERIFICATION DU RESEAU (Toutes les 30 secondes)
            if now - last_net_update >= 30 then
                local old_status = net_info.connected
                net_info = get_network_info()
                
                if net_info.connected ~= old_status then
                    build_options()
                    if cursor > #options then cursor = #options end
                end
                
                -- On redessine silencieusement le panneau réseau pour actualiser l'IP
                draw_menu()
                draw_list()
                last_net_update = now
            end
            
            -- GESTION DU CLAVIER
            if key then
                local old_cursor = cursor
                if key == "z" or key == "Z" or key == "UP" then
                    cursor = cursor - 1
                    if cursor < 1 then cursor = #options end
                    update_cursor(old_cursor, cursor)
                elseif key == "s" or key == "S" or key == "DOWN" then
                    cursor = cursor + 1
                    if cursor > #options then cursor = 1 end
                    update_cursor(old_cursor, cursor)
                elseif key == "r" or key == "R" then
                    local launched = search_and_launch()
                    -- Si un script a été lancé ou annulé, on redessine le menu propre
                    draw_menu()
                    draw_list()
                    last_net_update = os.time()
                elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                    local selected = options[cursor]
                    if selected.cmd == "update" then
                        minitel.play_sound("hit")
                        minitel.cleanup()
                        os.execute("lua5.3 updater.lua")
                        break 
                    else
                        minitel.play_sound("hit")
                        minitel.cleanup()
                        os.execute(selected.cmd)
                        minitel.init()
                        
                        last_net_update = 0 
                        last_input_time = os.time()
                        
                        draw_menu()
                        draw_list()
                    end
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