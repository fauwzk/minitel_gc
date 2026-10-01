-- Fichier : minitel.lua
-- Moteur de base pour Minitel Magis Club (9600 bauds 8N1)

local M = {}

function M.init()
    os.execute("stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb raw -echo -icanon min 0 time 0")
    io.write("\x1b[?25l") -- Masque le curseur
    io.flush()
end

function M.cleanup()
    io.write("\x1b[?25h\x1b[2J\x1b[H") -- Réaffiche le curseur et efface l'écran
    io.flush()
    os.execute("stty -F /dev/ttyUSB0 sane")
end

function M.sleep(seconds)
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do end
end

function M.play_sound(effect)
    -- L'exécution avec " >/dev/null 2>&1 &" permet de lancer le son en tâche de fond 
    -- sans bloquer l'exécution de Lua et sans salir l'affichage du Minitel.
    
    if not effect or effect == "blip" or effect == "hit" then
        -- Petit bip court "arcade" (Onde carrée à 880 Hz pendant 50ms)
        os.execute("play -q -n synth 0.05 square 880 >/dev/null 2>&1 &")
        
    elseif effect == "win" or effect == "pickup" then
        -- Son de ramassage/victoire (Onde carrée montante de 440 Hz à 1200 Hz pendant 150ms)
        os.execute("play -q -n synth 0.15 square 440-1200 >/dev/null 2>&1 &")
        
    elseif effect == "lose" or effect == "damage" then
        -- Son grave d'erreur/dégât (Onde en dent de scie descendante de 300 Hz à 100 Hz pendant 300ms)
        os.execute("play -q -n synth 0.3 sawtooth 300-100 >/dev/null 2>&1 &")
        
    end
end

function M.get_key()
    local c = io.read(1)
    if not c then return nil end
    
    local function read_next()
        -- Boucle matérielle pour éviter de rater la fin des séquences à 9600 bauds
        for i = 1, 50000 do 
            local n = io.read(1)
            if n then return n end
        end
        return nil
    end

    if c == "\x1b" then
        local seq1 = read_next()
        if not seq1 then return "ESC" end
        local seq2 = read_next()
        local full_seq = seq1 .. (seq2 or "")

        -- Flèches
        if full_seq == "[A" then return "UP" end
        if full_seq == "[B" then return "DOWN" end
        if full_seq == "[C" then return "RIGHT" end
        if full_seq == "[D" then return "LEFT" end
        
        -- Touches spéciales Magis Club
        if full_seq == "OR" then return "RETOUR" end
        if full_seq == "On" then return "SUITE" end
        if full_seq == "Ol" then return "CORRECTION" end
        if full_seq == "OQ" then return "ANNULATION" end
        if full_seq == "OM" then return "ENVOI" end

        return "UNKNOWN_ESC"
    end
    return c
end

return M