local minitel = require("minitel")
minitel.init()

local function draw_interface(step_msg)
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[3;11H\x1b[7m==========================================================\x1b[0m\r\n")
    io.write("\x1b[4;11H\x1b[7m|            3 6 1 5   M I S E   A   J O U R             |\x1b[0m\r\n")
    io.write("\x1b[5;11H\x1b[7m==========================================================\x1b[0m\r\n\r\n")
    
    io.write("\x1b[12;23H" .. step_msg .. "\r\n")
    
    io.write("\x1b[22;11H==========================================================\r\n")
    io.write("\x1b[23;14H VEUILLEZ PATIENTER PENDANT LA SYNCHRONISATION...\r\n")
    io.flush()
end

-- Etape 1 : Initialisation
draw_interface("\x1b[1m VERIFICATION DU SYSTEME... \x1b[0m")
minitel.play_sound("hit")
minitel.sleep(1)

-- Autorisation Git (sécurité)
os.execute("git config --global --add safe.directory '*' >/dev/null 2>&1")

-- Etape 2 : Préparation
draw_interface("\x1b[1m NETTOYAGE DU CACHE LOCAL... \x1b[0m")
os.execute("git reset --hard HEAD >/dev/null 2>&1")
minitel.sleep(1)

-- Etape 3 : Téléchargement
draw_interface("\x1b[7m TELECHARGEMENT DES NOUVELLES DONNEES... \x1b[0m")
minitel.play_sound("pickup")
os.execute("git pull >/dev/null 2>&1")
minitel.sleep(1.5)

-- Etape 4 : Fin
draw_interface("\x1b[1m MISE A JOUR TERMINEE AVEC SUCCES ! \x1b[0m")
minitel.play_sound("win")
minitel.sleep(2)

draw_interface("\x1b[7m REDEMARRAGE DU MAGIS CLUB... \x1b[0m")
minitel.sleep(1.5)

minitel.cleanup()

-- Nettoyage agressif des processus Lua en cours et relance du service
os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
os.execute("killall -9 lua5.3 2>/dev/null")
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")