local minitel = require("minitel")
minitel.init()

io.write("\x1b[2J\x1b[H")
io.write("\x1b[2;11H==========================================================\r\n")
io.write("\x1b[3;11H| \x1b[7m SYNCHRONISATION GITHUB (fauwzk/minitel_gc) \x1b[0m           |\r\n")
io.write("\x1b[4;11H==========================================================\r\n")
for i = 5, 21 do
    io.write("\x1b[" .. i .. ";11H|                                                        |\r\n")
end
io.write("\x1b[22;11H==========================================================\r\n")
io.flush()

local function print_log(y, msg)
    io.write("\x1b[" .. y .. ";13H\x1b[K\x1b[" .. y .. ";68H|")
    -- Tronque le message pour qu'il ne déborde pas du cadre
    local safe_msg = string.sub(msg, 1, 53)
    io.write("\x1b[" .. y .. ";13H" .. safe_msg)
    io.flush()
end

print_log(6, "> PREPARATION : SAUVEGARDE DES FICHIERS *.cfg")
-- Trouve tous les .cfg et les copie en conservant leur chemin exact (jeux/, utils/...)
os.execute(
    "mkdir -p /tmp/minitel_cfg_backup && find . -name '*.cfg' -exec cp --parents {} /tmp/minitel_cfg_backup/ \\; 2>/dev/null")
minitel.sleep(1)

print_log(8, "> CONNEXION AU DEPOT DISTANT...")
local cmd = "git pull https://github.com/fauwzk/minitel_gc.git 2>&1"
local f = io.popen(cmd)
local line_y = 10

if f then
    for line in f:lines() do
        -- Si la log touche le bas du cadre, on efface le contenu central
        if line_y > 19 then
            for i = 10, 19 do
                io.write("\x1b[" .. i .. ";13H\x1b[K\x1b[" .. i .. ";68H|")
            end
            line_y = 10
        end
        print_log(line_y, line)
        line_y = line_y + 1
        minitel.sleep(0.05)
    end
    f:close()
end

print_log(21, "> RESTAURATION DES CONFIGURATIONS DE JEUX...")
os.execute("cp -r /tmp/minitel_cfg_backup/* . 2>/dev/null")
minitel.sleep(1)

io.write("\x1b[24;1H\x1b[K\x1b[24;14H\x1b[7m MISE A JOUR TERMINEE. REBOOT DU MASTER... \x1b[0m")
io.flush()

-- Double bip de validation matérielle
io.write("\x07")
io.flush()
minitel.sleep(0.15)
io.write("\x07")
io.flush()
minitel.sleep(1.5)

minitel.cleanup()
