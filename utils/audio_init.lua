-- @TYPE: SYSTEME / AUDIO
-- @DESC: Diagnostic du son : bip du Minitel, sortie audio du Raspberry Pi et voie audio de la ligne (prise peri-informatique).

-- Rappel (schemas Alcatel du Magis Club) : les broches 6-7-8 de la prise
-- peri-informatique sont une interface audio VERS LA LIGNE TELEPHONIQUE.
-- La broche 6 rejoint le transformateur de ligne, a travers un interrupteur
-- commande par le Minitel (signal COM_AUD) ; elle n'alimente pas directement
-- un haut-parleur. Cet outil verifie donc, sur VOTRE Minitel, ce qui s'entend.

local minitel = require("minitel")
minitel.init()

local PID_FILE = "/tmp/minitel_audio_test.pid"
local results = { bip = nil, pi = nil, ligne = nil }

-- La sortie ecran passe par minitel.lua ; le caractere BEL n'y laisse pas de trace
local function bel()
    io.write("\a")
    io.flush()
end

local function has_play()
    return os.execute("command -v play >/dev/null 2>&1") == true
end

local function first_line(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return nil end
    local s = f:read("*l"); f:close()
    return s
end

-- Son continu joue en tache de fond, que l'on peut couper a tout moment
local function tone_start(seconds)
    os.execute(string.format("(play -q -n synth %d sine 440 vol 0.5 >/dev/null 2>&1 & echo $! > %s)", seconds, PID_FILE))
end

local function tone_stop()
    os.execute("[ -f " .. PID_FILE .. " ] && kill $(cat " .. PID_FILE .. ") 2>/dev/null; rm -f " .. PID_FILE)
end

local function wait_key()
    while true do
        local k = minitel.get_key()
        if k then return k end
        minitel.sleep(0.05)
    end
end

-- Pose la question "entendu ?" ; renvoie true, false ou nil (abandon)
local function ask_heard(y)
    io.write(string.format("\x1b[%d;4H\x1b[7m AVEZ-VOUS ENTENDU UN SON ?  [O] OUI   [N] NON \x1b[0m\x1b[K", y))
    io.flush()
    while true do
        local k = wait_key()
        if k == "o" or k == "O" then return true end
        if k == "n" or k == "N" then return false end
        if k == "RETOUR" or k == "ESC" then return nil end
    end
end

local function status_text(v)
    if v == true then return "\x1b[7m ENTENDU \x1b[0m" end
    if v == false then return "SILENCE  " end
    return "NON TESTE"
end

local function draw_menu()
    io.write("\x1b[r\x1b[0m\x1b[2J")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("3615 AUDIO  -  DIAGNOSTIC DU SON", 80) .. "\x1b[0m")
    io.write("\x1b[3;3HLes broches audio 6-7-8 de la prise peri-informatique du Magis Club sont")
    io.write("\x1b[4;3Hreliees a la LIGNE TELEPHONIQUE, pas directement au haut-parleur. Ces trois")
    io.write("\x1b[5;3Hessais montrent ce qui s'entend reellement sur votre Minitel.")

    io.write("\x1b[8;4H\x1b[7m 1 \x1b[0m BIP DU MINITEL (caractere BEL)            " .. status_text(results.bip))
    io.write("\x1b[10;4H\x1b[7m 2 \x1b[0m SORTIE AUDIO DU RASPBERRY PI (jack)      " .. status_text(results.pi))
    io.write("\x1b[12;4H\x1b[7m 3 \x1b[0m VOIE AUDIO DE LA LIGNE (broche 6)        " .. status_text(results.ligne))

    -- Conclusion d'apres les essais deja faits
    local advice
    if results.bip == true then
        advice = "Le bip du Minitel fonctionne : c'est un son integre, sans cablage, utilisable pour des signaux sonores."
    elseif results.ligne == true then
        advice = "La voie ligne s'entend pendant la connexion : le haut-parleur du Minitel suit la ligne."
    elseif results.pi == false then
        advice = "Le Pi ne produit pas de son : verifiez SoX, la sortie jack (raspi-config) et le volume (alsamixer)."
    elseif results.bip == false and results.ligne == false then
        advice = "Ni bip ni voie ligne : pour la musique, branchez un petit haut-parleur amplifie sur la sortie du Pi."
    else
        advice = "Faites les essais dans l'ordre : 1, puis 2, puis 3."
    end
    local lines = minitel.wrap(advice, 72, 2)
    io.write("\x1b[15;3H\x1b[1mBILAN :\x1b[0m")
    io.write("\x1b[16;5H" .. lines[1] .. "\x1b[17;5H" .. lines[2])

    io.write("\x1b[24;1H\x1b[7m" .. minitel.center("[1] [2] [3] ESSAIS   |   [RETOUR] QUITTER", 80) .. "\x1b[0m")
    io.flush()
end

local function clear_zone()
    for y = 19, 23 do io.write(string.format("\x1b[%d;1H\x1b[K", y)) end
end

-- ESSAI 1 : le Minitel emet lui-meme un bip quand il recoit le caractere BEL
local function test_bip()
    clear_zone()
    io.write("\x1b[19;4HEnvoi de trois bips au Minitel...")
    io.flush()
    for _ = 1, 3 do bel(); minitel.sleep(0.6) end
    local r = ask_heard(21)
    if r ~= nil then results.bip = r end
end

-- ESSAI 2 : la sortie du Pi ; a ecouter au casque, ou sur ce qui est branche au jack
local function test_pi()
    clear_zone()
    if not has_play() then
        io.write("\x1b[19;4HSoX est absent : installez-le avec  sudo apt install sox")
        io.write("\x1b[21;4HAppuyez sur une touche.")
        io.flush(); wait_key()
        results.pi = false
        return
    end
    local card = first_line("aplay -l | grep -m1 '^carte\\|^card'") or "aucune carte detectee"
    io.write("\x1b[19;4HCarte son : " .. minitel.pad(card, 60))
    io.write("\x1b[20;4HLa a 440 Hz pendant 3 s. Ecoutez au casque, branche sur le jack du Pi.")
    io.flush()
    tone_start(3)
    minitel.sleep(3.2)
    tone_stop()
    local r = ask_heard(22)
    if r ~= nil then results.pi = r end
end

-- ESSAI 3 : la broche 6 n'est reliee qu'au circuit de ligne. On joue un son
-- pendant que l'utilisateur met lui-meme le Minitel en connexion.
local function test_ligne()
    clear_zone()
    if not has_play() then
        io.write("\x1b[19;4HSoX est absent : faites d'abord l'essai 2.  (une touche)")
        io.flush(); wait_key(); return
    end
    local ok = minitel.confirm_box("VOIE LIGNE",
        "Le cordon telephonique est-il DEBRANCHE ? Sinon le son partirait sur la ligne.")
    draw_menu()
    if not ok then return end
    io.write("\x1b[19;4HUn son est joue pendant 20 s sur la sortie du Pi (donc sur la broche 6).")
    io.write("\x1b[20;4H1. Appuyez sur la touche \x1b[1mConnexion/Fin\x1b[0m du Minitel et ecoutez.")
    io.write("\x1b[21;4H2. Rappuyez sur \x1b[1mConnexion/Fin\x1b[0m pour raccrocher.")
    io.write("\x1b[22;4H3. Si l'ecran est passe en 40 colonnes : Ctrl+Esc, T, A.   Puis ENVOI ici.")
    io.flush()
    tone_start(20)
    -- On attend ENVOI ; toute autre touche (sequences de connexion...) est ignoree
    while true do
        local k = wait_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" then break end
    end
    tone_stop()
    draw_menu()
    clear_zone()
    local r = ask_heard(21)
    if r ~= nil then results.ligne = r end
end

draw_menu()
while true do
    local k = wait_key()
    if k == "1" then test_bip(); draw_menu()
    elseif k == "2" then test_pi(); draw_menu()
    elseif k == "3" then test_ligne(); draw_menu()
    elseif k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
    end
end

tone_stop()
minitel.cleanup()
