-- @TYPE: SYSTEME / AUDIO
-- @DESC: Tente de forcer l'activation de l'amplificateur audio du Minitel via commandes AT.

local minitel = require("minitel")
minitel.init()

io.write("\x1b[r\x1b[2J\x1b[H")
io.write("\x1b[7m INITIALISATION AUDIO DU MODEM... \x1b[0m\r\n\n")
io.flush()

-- Séquence d'échappement pour lier la prise périphérique au modem (selon les modèles)
-- Sur certains Minitel, c'est indispensable pour que le modem écoute le port DIN.
io.write("\x1b\x39\x67") 
io.flush()
minitel.sleep(0.5)

-- Envoi des commandes Hayes (AT)
local commands = {
    "AT",    -- Accroche la vitesse (Autobaud)
    "ATL3",  -- Volume au maximum
    "ATM2"   -- Haut-parleur activé en permanence
}

for _, cmd in ipairs(commands) do
    io.write(cmd .. "\r")
    io.flush()
    minitel.sleep(0.5)
end

io.write("Commandes envoyées.\r\n")
io.write("Si 'OK' n'est pas apparu, le modem ne capte pas le port DIN.\r\n")
io.flush()

minitel.sleep(2)
minitel.cleanup()