local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- FONCTION : RECUPERER LES INFOS DU DERNIER COMMIT
-- =====================================================================
local function get_latest_commit()
    -- On demande à Git de formater la sortie ainsi : "Hash|Auteur|Message"
    local f = io.popen("git log -1 --format='%h|%an|%s' 2>/dev/null")
    if f then
        local line = f:read("*l") -- On lit la première ligne
        f:close()
        
        if line then
            local h, a, m = string.match(line, "^(.-)|(.-)|(.*)$")
            if h then
                -- On coupe les chaînes trop longues pour ne pas casser l'écran
                return {
                    hash = h, 
                    author = string.sub(a, 1, 25), 
                    msg = string.sub(m, 1, 40)
                }
            end
        end
    end
    return nil -- Retourne nil si Git échoue ou s'il n'y a pas de dépôt
end

-- =====================================================================
-- FONCTION : DESSINER L'INTERFACE DE MISE A JOUR
-- =====================================================================
local function draw_interface(step_msg, commit_data)
    io.write("\x1b[2J\x1b[H")
    
    -- En-tête
    io.write("\x1b[3;11H\x1b[7m==========================================================\x1b[0m\r\n")
    io.write("\x1b[4;11H\x1b[7m|            3 6 1 5   M I S E   A   J O U R             |\x1b[0m\r\n")
    io.write("\x1b[5;11H\x1b[7m==========================================================\x1b[0m\r\n")
    
    -- Message de statut central
    io.write("\x1b[9;20H" .. step_msg .. "\r\n")
    
    -- Affichage du bloc Git (seulement s'il y a des données)
    if commit_data then
        io.write("\x1b[13;13H\x1b[1mDERNIERE VERSION SYNCHRONISEE :\x1b[0m\r\n")
        io.write("\x1b[15;13H COMMIT  : " .. commit_data.hash .. "\r\n")
        io.write("\x1b[16;13H AUTEUR  : " .. commit_data.author .. "\r\n")
        io.write("\x1b[17;13H MESSAGE : " .. commit_data.msg .. "\r\n")
    end
    
    -- Pied de page
    io.write("\x1b[22;11H==========================================================\r\n")
    if not commit_data then
        io.write("\x1b[23;14H VEUILLEZ PATIENTER PENDANT LA SYNCHRONISATION...\r\n")
    else
        io.write("\x1b[23;16H SYNCHRONISATION TERMINEE - REDEMARRAGE...\r\n")
    end
    io.flush()
end

-- =====================================================================
-- SEQUENCE DE MISE A JOUR
-- =====================================================================

-- Etape 1 : Initialisation
draw_interface("\x1b[1m    VERIFICATION DU SYSTEME...    \x1b[0m")
minitel.play_sound("hit")
minitel.sleep(1)

-- Autorisation Git (sécurité)
os.execute("git config --global --add safe.directory '*' >/dev/null 2>&1")

-- Etape 2 : Préparation
draw_interface("\x1b[1m    NETTOYAGE DU CACHE LOCAL...   \x1b[0m")
os.execute("mkdir -p /home/minitel/minitel_gc_backup/utils/prog_basic_backup >/dev/null 2>&1")
os.execute("cp -R /home/minitel/minitel_gc/utils/prog_basic /home/minitel/minitel_gc_backup/utils/prog_basic_backup >/dev/null 2>&1")
os.execute("git reset --hard HEAD >/dev/null 2>&1")
minitel.sleep(1)

-- Etape 3 : Téléchargement
draw_interface("\x1b[7m TELECHARGEMENT DES NOUVELLES DONNEES... \x1b[0m")
minitel.play_sound("pickup")
os.execute("git pull >/dev/null 2>&1")
minitel.sleep(0.5)
os.execute("cp -R /home/minitel/minitel_gc_backup/utils/prog_basic_backup/* /home/minitel/minitel_gc/utils/prog_basic >/dev/null 2>&1")

-- Etape 4 : Fin avec lecture des infos de Commit
local commit_info = get_latest_commit()

draw_interface("\x1b[1m MISE A JOUR TERMINEE AVEC SUCCES ! \x1b[0m", commit_info)
minitel.play_sound("win")

-- On laisse l'utilisateur lire les infos du commit pendant 4.5 secondes
minitel.sleep(4.5)

-- Etape 5 : Reboot
draw_interface("\x1b[7m      REDEMARRAGE DU MAGIS CLUB...      \x1b[0m", commit_info)
minitel.sleep(1.5)

minitel.cleanup()

-- Nettoyage agressif des processus Lua en cours et relance du service
os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
os.execute("killall -9 lua5.3 2>/dev/null")
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")