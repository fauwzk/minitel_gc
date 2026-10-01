local minitel = require("minitel")
minitel.init()

io.write("\x1b[2J\x1b[H")
io.write("\x1b[2;15H\x1b[7m MISE A JOUR DU MAGIS CLUB EN COURS... \x1b[0m\r\n\r\n")
io.flush()

-- On utilise '*' pour le safe.directory, ça marchera aussi bien sur le Pi que sur le PC portable
os.execute("git config --global --add safe.directory '*'")

-- On laisse Git écrire ses messages à l'écran
io.write("\x1b[1m--- LOGS DE SYNCHRONISATION ---\x1b[0m\r\n")
os.execute("git reset --hard HEAD")
os.execute("git pull")
io.write("\x1b[1m-------------------------------\x1b[0m\r\n\r\n")

io.write("\x1b[7m Lisez l'erreur ci-dessus, puis appuyez sur ENVOI \x1b[0m\r\n")
io.flush()

-- Le script se met en pause infinie tant que vous n'appuyez pas sur ENVOI
while true do
    local k = minitel.get_key()
    if k == "ENVOI" or k == "\r" or k == "\n" then break end
    minitel.sleep(0.05)
end

minitel.cleanup()
os.execute("stty -F /dev/ttyUSB0 sane")
os.execute("killall -9 lua5.3 2>/dev/null")
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")