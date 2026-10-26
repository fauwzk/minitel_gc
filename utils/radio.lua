-- @TYPE: AUDIO / WEBRADIO
-- @DESC: Lecteur de flux Webradio (France Inter) utilisant mplayer en arriere-plan.

local minitel = require("minitel")
minitel.init()

-- On s'assure qu'aucune autre instance de mplayer ne tourne deja
os.execute("killall mplayer 2>/dev/null")

local stream_url = "http://icecast.radiofrance.fr/franceinter-midfi.mp3"

local function draw_player_ui()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 RADIO - FRANCE INTER (EN DIRECT)  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(14, 5, 52, 13, "LECTEUR MPLAYER AUDIO")

    io.write("\x1b[7;18H\x1b[1mFLUX :\x1b[0m " .. string.sub(stream_url, 1, 38) .. "...")
    io.write("\x1b[9;18H\x1b[7m [ EN LECTURE ] \x1b[0m ")
    io.write("\x1b[11;18HLe son est envoye sur la sortie audio du Pi.")
    io.write("\x1b[12;18H(Via la prise DIN 8 ou le Jack 3.5mm)")
    io.write("\x1b[14;18HSi aucun son sur le Minitel, verifiez que")
    io.write("\x1b[15;18Hla commande ATM2 a bien ete acceptee.")

    io.write("\x1b[24;1H\x1b[7m  [RETOUR] COUPER LA RADIO ET QUITTER                                           \x1b[0m")
    io.flush()
end

draw_player_ui()

-- Lancement de mplayer en tâche de fond (&) sans controles console
local cmd = string.format("mplayer -really-quiet -noconsolecontrols '%s' >/dev/null 2>&1 &", stream_url)
os.execute(cmd)

-- Boucle d'animation (Delta-Drawing sur un seul caractere) et ecoute du clavier
local frame = 0
local anim = {"-", "\\", "|", "/"}

while true do
    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    end

    frame = frame + 1
    io.write(string.format("\x1b[9;35H\x1b[1m%s\x1b[0m", anim[(frame % 4) + 1]))
    io.flush()
    
    -- Vitesse de l'animation
    minitel.sleep(0.2)
end

-- Nettoyage a la sortie : on tue mplayer
os.execute("killall mplayer 2>/dev/null")
minitel.cleanup()