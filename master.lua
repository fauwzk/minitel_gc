local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- DETECTION RESEAU
-- =====================================================================
local function check_internet()
    local success = os.execute("ping -c 1 -W 1 github.com > /dev/null 2>&1")
    return success
end

local is_connected = check_internet()

-- =====================================================================
-- LISTE DES MODULES DYNAMIQUE
-- =====================================================================
local options = {
    { name = "3615 JEUX (Modules de divertissement)", cmd = "lua5.3 launcher_jeux.lua" },
    { name = "3615 OUTILS (Modules utilitaires)", cmd = "lua5.3 launcher_utils.lua" }
}

-- La fonction de mise à jour n'apparaît que si le minitel détecte internet
if is_connected then
    table.insert(options, { name = "MISE A JOUR SYSTEME (Git Pull)", cmd = "update" })
end

table.insert(options, { name = "CONFIGURATION RESEAU (nmtui)", cmd = "TERM=vt100 nmtui" })
table.insert(options, { name = "INVITE DE COMMANDE (Shell)", cmd = "bash" })
table.insert(options, { name = "EXTINCTION DU SYSTEME", cmd = "sudo poweroff" })
table.insert(options, { name = "REDEMARRAGE DU SYSTEME", cmd = "sudo reboot" })

local cursor = 1

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
    
    -- Formatage strict pour maintenir le cadre à 80 colonnes sans décalage
    local line_reseau = ""
    if is_connected then
        line_reseau = "| RESEAU : \x1b[7m CONNECTE \x1b[0m                                   |\r\n"
    else
        line_reseau = "| RESEAU :  HORS LIGNE                                  |\r\n"
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
-- BOUCLE PRINCIPALE ET GESTION DU REBOOT
-- =====================================================================
local state = "BOOT"

-- Si le fichier de Warmboot existe, on esquive l'écran 40 colonnes
local f = io.open("/tmp/minitel_warmboot", "r")
if f then
    state = "MENU"
    f:close()
    os.remove("/tmp/minitel_warmboot")
    draw_menu()
    draw_list()
else
    io.write("\x1b[2J\x1b[H")
end

local last_boot_draw = 0

while true do
    local key = minitel.get_key()
    
    if state == "BOOT" then
        local now = os.time()
        if now - last_boot_draw >= 1 then
            draw_boot_screen()
            last_boot_draw = now
        end
        
        if key == "ENVOI" or key == " " or key == "\n" or key == "\r" then
            minitel.play_sound("hit")
            state = "MENU"
            draw_menu()
            draw_list()
        end
        
    elseif state == "MENU" then
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
                
                -- Lance l'utilitaire de mise à jour
                os.execute("lua5.3 updater.lua")
                
                -- Crée le flag pour éviter l'écran d'instructions 40 colonnes au prochain lancement
                os.execute("touch /tmp/minitel_warmboot")
                
                -- Quitter la boucle "tue" master.lua, ce qui force Linux à fermer la session.
                -- Systemd relance instantanément agetty -> auto-login -> master.lua avec le code mis à jour !
                break 
                
            else
                minitel.play_sound("hit")
                minitel.cleanup()
                os.execute(selected.cmd)
                minitel.init()
                draw_menu()
                draw_list()
            end
        end
    end
    minitel.sleep(0.02)
end

minitel.cleanup()