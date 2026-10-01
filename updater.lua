local minitel = require("minitel")
minitel.init()

io.write("\x1b[2J\x1b[H")
io.write("\x1b[12;15H\x1b[7m MISE A JOUR DU MAGIS CLUB EN COURS... \x1b[0m\r\n")
io.flush()

-- 1. On autorise Git à travailler ici (règle l'erreur de sécurité "safe.directory")
os.execute("git config --global --add safe.directory /home/minitel/minitel_gc >/dev/null 2>&1")

-- 2. On annule toutes les modifications locales sur les fichiers suivis par Git
-- (Cela évite que le pull soit bloqué par un conflit)
os.execute("git reset --hard HEAD >/dev/null 2>&1")

-- 3. On tire uniquement les nouveaux fichiers depuis GitHub
-- On redirige la sortie pour que l'écran du Minitel reste propre
os.execute("git pull >/dev/null 2>&1")

io.write("\x1b[14;22H\x1b[1m MISE A JOUR TERMINEE ! \x1b[0m\r\n")
io.write("\x1b[16;15H REDEMARRAGE DU SYSTEME DANS 3 SECONDES... \r\n")
io.flush()

minitel.sleep(3)
minitel.cleanup()

-- Redémarrage du service (fonctionne sur le Pi, fera juste une erreur silencieuse sur le PC)
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")