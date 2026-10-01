local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- DETECTION RESEAU & SYSTEME
-- =====================================================================
local function check_internet()
    local success = os.execute("ping -c 1 -W 1 github.com > /dev/null 2>&1")
    return success
end

local is_connected = check_internet()

-- =====================================================================
-- LISTE DES MODULES
-- =====================================================================
local options = {
    { name = "3615 JEUX (Modules jeux)", cmd = "lua5.3 launcher_jeux.lua" },
    { name = "3615 OUTILS (Modules outils)", cmd = "lua5.3 launcher_utils.lua" }
}

if is_connected then
    table.insert(options, { name = "MISE A JOUR SYSTEME (Git Pull)", cmd = "update" })
end

table.insert(options, { name = "CONFIGURATION RESEAU (nmtui)", cmd = "TERM=vt100 nmtui" })
table.insert(options, { name = "INVITE DE COMMANDE (Shell)", cmd = "bash" })
table.insert(options, { name = "EXTINCTION DU SYSTEME", cmd = "sudo poweroff" })
table.insert(options, { name = "REDEMARRAGE DU SYSTEME", cmd = "sudo reboot" })

local cursor = 1

-- =====================================================================
-- HORLOGE
-- =====================================================================
local function update_clock()
    local datetime = os.date("%H:%M")
    -- Positionnement absolu direct (sans sauvegarde de curseur pour éviter les bugs d'affichage)
    io.write("\x1b[5;55H\x1b[1m[ " .. datetime .. " ]\x1b[0m")
    io.flush()
end

-- =====================================================================
-- INTERFACE GRAPHIQUE (STYLE CLASSIQUE)
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
    
    local line_reseau = ""
    if is_connected then
        -- L'espace manquant a été ajouté pour aligner la bordure
        line_reseau = "| RESEAU : \x1b[7m CONNECTE \x1b[0m                                    |\r\n"
    else
        line_reseau = "| RESEAU :  HORS LIGNE                                   |\r\n"
    end
    
    io.write("\x1b[2;11H==========================================================\r\n")
    io.write("\x1b[3;11H|               \x1b[1m TABLEAU DE BORD PRINCIPAL \x1b[0m              |\r\n")
    io.write("\x1b[4;11H|========================================================|\r\n")
    io.write("\x1b[5;11H" .. line_reseau)
    io.write("\x1b[6;11H|                                                        |\r\n")
    io.write("\x1b[7;11H|             SELECTION DU MODULE DE DEMARRAGE           |\r\n")
    io.write("\x1b[8;11H|                                                        |\r\n")
    io.write("\x1b[9;11H==========================================================\r\n")
    
    io.write("\x1b[21;11H==========================================================\r\n")
    io.write("\x1b[23;14H  ZQSD / FLECHES : NAVIGUER  |  ENVOI : VALIDER   \r\n")
    io.flush()
    
    update_clock()
end

local function draw_list()
    for i=10, 19 do io.write("\x1b["..i..";1H\x1b[K") end
    for i, opt in ipairs(options) do
        local line_y = 10 + i
        if i == cursor then
            io.write("\x1b[" .. line_y .. ";18H\x1b[7m > " .. opt.name .. " \x1b[0m")
        else
            io.write("\x1b[" .. line_y .. ";18H   " .. opt.name .. "   ")
        end
    end
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_opt = options[old_index]
    if old_opt then io.write("\x1b[" .. (10 + old_index) .. ";1H\x1b[K\x1b[" .. (10 + old_index) .. ";18H   " .. old_opt.name .. "   ") end
    local new_opt = options[new_index]
    if new_opt then io.write("\x1b[" .. (10 + new_index) .. ";1H\x1b[K\x1b[" .. (10 + new_index) .. ";18H\x1b[7m > " .. new_opt.name .. " \x1b[0m") end
    io.flush()
end

-- =====================================================================
-- GESTION DE L'ECRAN DE VEILLE (SCREENSAVER)
-- =====================================================================
local ss_x, ss_y = 30, 12
local ss_dx, ss_dy = 1, 1
local ss_text = " \x1b[7m 3615 MINITEL \x1b[0m "
local ss_len = 14 

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
local last_clock_update = os.time()
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
            if now - last_clock_update >= 30 then
                update_clock()
                last_clock_update = now
            end
            
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
                        
                        draw_menu()
                        draw_list()
                        last_input_time = os.time() 
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