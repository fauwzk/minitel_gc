local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- GESTION DU DICTIONNAIRE (MULTI-TAILLES, FAMILIAL)
-- =====================================================================
local fallback_words = {
    -- 3 lettres
    "AMI", "BOL", "BUS", "COU", "DOS", "EAU", "FEU", "GAZ", "JEU", "LAC", "LIT", "MER", "NEZ", "OEU", "POT", "RUE", "SAC", "THE", "VOL", "ZOO",
    -- 4 lettres
    "BLEU", "BOIS", "CAFE", "CHAT", "EST", "JEUX", "JOUR", "LION", "LOUP", "LUNE", "NORD", "NUIT", "OURS", "PAIN", "PAYS", "PONT", "PORT", "ROSE", "SUD", "VELO", "VENT", "VERT",
    -- 5 lettres
    "ARBRE", "AVION", "BALLE", "BOITE", "CHIEN", "COEUR", "ECOLE", "FLEUR", "GLACE", "LAPIN", "LIVRE", "PLUIE", "POMME", "TABLE", "TRAIN", "VILLE",
    -- 6 lettres
    "BANANE", "CERISE", "CHEVAL", "CITRON", "CRAYON", "FRAISE", "GARCON", "GATEAU", "GIRAFE", "JARDIN", "MAISON", "MOTEUR", "OISEAU", "PAPIER", "PIERRE", "POULET", "SOLEIL"
}

local word_list = {}
local word_length = 5

local function load_dictionary()
    -- 1. Tentative de mise à jour réseau si internet est disponible
    local success = os.execute("ping -c 1 -W 1 github.com > /dev/null 2>&1")
    if success then
        io.write("\x1b[12;20H\x1b[7m RECHERCHE DU DICTIONNAIRE EN LIGNE... \x1b[0m")
        io.flush()
        
        -- URL de votre dépôt (à créer/adapter si vous voulez un dico externe)
        local url = "https://raw.githubusercontent.com/fauwzk/minitel_gc/main/dico_fr.txt"
        os.execute("curl -s -f -o jeux/dico_temp.txt " .. url)
        
        -- Si le téléchargement a fonctionné, on écrase l'ancien
        local check = io.open("jeux/dico_temp.txt", "r")
        if check then
            check:close()
            os.rename("jeux/dico_temp.txt", "jeux/dico_minitel.txt")
        end
    end

    -- 2. Chargement depuis le fichier local
    local f = io.open("jeux/dico_minitel.txt", "r")
    if f then
        for line in f:lines() do
            local word = string.match(string.upper(line), "%a+")
            if word then
                local len = string.len(word)
                if len >= 3 and len <= 6 then
                    table.insert(word_list, word)
                end
            end
        end
        f:close()
    end

    -- 3. Sécurité : création du fichier avec les mots de base s'il est vide/inexistant
    if #word_list == 0 then
        io.write("\x1b[12;20H\x1b[7m GENERATION DU DICTIONNAIRE LOCAL... \x1b[0m")
        io.flush()
        
        word_list = fallback_words
        local out = io.open("jeux/dico_minitel.txt", "w")
        if out then
            for _, w in ipairs(word_list) do
                out:write(w .. "\n")
            end
            out:close()
        end
        minitel.sleep(1.5)
    end
end

-- =====================================================================
-- VARIABLES DU JEU
-- =====================================================================
local state = "TITLE"
local target_word = ""
local guesses = {}
local current_input = ""
local max_attempts = 6
local keyboard_status = {}
local msg_board = ""

local function reset_game()
    math.randomseed(os.time())
    target_word = word_list[math.random(#word_list)]
    word_length = string.len(target_word)
    guesses = {}
    current_input = ""
    keyboard_status = {}

    for i = 65, 90 do
        keyboard_status[string.char(i)] = "UNKNOWN"
    end
end

-- =====================================================================
-- LOGIQUE DU JEU
-- =====================================================================
local function evaluate_guess(guess)
    local result = {}
    local target_counts = {}

    for i = 1, word_length do
        local char = string.sub(target_word, i, i)
        target_counts[char] = (target_counts[char] or 0) + 1
        result[i] = {
            char = string.sub(guess, i, i),
            status = "ABSENT"
        }
    end

    for i = 1, word_length do
        if result[i].char == string.sub(target_word, i, i) then
            result[i].status = "EXACT"
            target_counts[result[i].char] = target_counts[result[i].char] - 1
            keyboard_status[result[i].char] = "EXACT"
        end
    end

    for i = 1, word_length do
        if result[i].status ~= "EXACT" then
            local c = result[i].char
            if target_counts[c] and target_counts[c] > 0 then
                result[i].status = "PRESENT"
                target_counts[c] = target_counts[c] - 1
                if keyboard_status[c] ~= "EXACT" then
                    keyboard_status[c] = "PRESENT"
                end
            else
                if keyboard_status[c] == "UNKNOWN" then
                    keyboard_status[c] = "ABSENT"
                end
            end
        end
    end

    table.insert(guesses, result)

    if guess == target_word then
        state = "VICTORY"
        msg_board = "ACCES AUTORISE. MOT DE PASSE VALIDE."
        minitel.play_sound("win")
    elseif #guesses >= max_attempts then
        state = "GAMEOVER"
        msg_board = "ECHEC. LE MOT ETAIT : " .. target_word
        minitel.play_sound("lose")
    end
end

-- =====================================================================
-- AFFICHAGE MINITEL
-- =====================================================================
local function draw_title(full)
    if full then
        io.write("\x1b[2J\x1b[H")
        io.write("\x1b[4;11H==========================================================\r\n")
        io.write("\x1b[5;11H|                                                        |\r\n")
        io.write("\x1b[6;11H|            \x1b[1m3 6 1 5   D E C R Y P T A G E\x1b[0m               |\r\n")
        io.write("\x1b[7;11H|                                                        |\r\n")
        io.write("\x1b[8;11H==========================================================\r\n")
        io.write("\x1b[12;23H PIRATAGE DE SERVEUR (PROTOCOLE MOTUS) \r\n")
    end

    io.write("\x1b[16;1H\x1b[K\x1b[16;25H\x1b[7m [ ENVOI ] LANCER L'INTRUSION \x1b[0m\r\n")
    io.write("\x1b[18;1H\x1b[K\x1b[18;30H   [ RETOUR ] QUITTER   \r\n")
    io.flush()
end

local function update_grid()
    -- Calcul pour centrer la grille automatiquement selon la longueur du mot
    local start_x = math.floor((80 - (word_length * 6)) / 2)
    
    for i = 1, max_attempts do
        local line_y = 6 + (i * 2)
        io.write("\x1b[" .. line_y .. ";" .. start_x .. "H\x1b[K")

        local guess_row = guesses[i]

        if guess_row then
            for j = 1, word_length do
                local block = ""
                if guess_row[j].status == "EXACT" then
                    block = "\x1b[7m[ " .. guess_row[j].char .. " ]\x1b[0m"
                elseif guess_row[j].status == "PRESENT" then
                    block = "( " .. guess_row[j].char .. " )"
                else
                    block = "  " .. guess_row[j].char .. "  "
                end
                io.write(block .. " ")
            end
        elseif i == #guesses + 1 and state == "PLAYING" then
            for j = 1, word_length do
                local c = string.sub(current_input, j, j)
                if c == "" then
                    c = "."
                end
                io.write("  " .. c .. "   ")
            end
        else
            for j = 1, word_length do
                io.write("  .   ")
            end
        end
    end
    io.flush()
end

local function update_keyboard()
    local row1 = {"A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"}
    local row2 = {"Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"}
    local row3 = {"W", "X", "C", "V", "B", "N"}

    local function draw_row(y, x_start, chars)
        io.write("\x1b[" .. y .. ";" .. x_start .. "H\x1b[K")
        for _, c in ipairs(chars) do
            local st = keyboard_status[c]
            if st == "EXACT" then
                io.write("\x1b[7m " .. c .. " \x1b[0m")
            elseif st == "PRESENT" then
                io.write("(" .. c .. ")")
            elseif st == "ABSENT" then
                io.write("   ")
            else
                io.write(" " .. c .. " ")
            end
        end
    end

    draw_row(20, 25, row1)
    draw_row(21, 25, row2)
    draw_row(22, 31, row3)
    io.flush()
end

local function draw_game_screen()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;11H==========================================================\r\n")
    -- L'interface affiche le nombre de lettres requis dynamiquement
    io.write("\x1b[3;11H| \x1b[7m BRUTE-FORCE ACTIF \x1b[0m            FORMAT: " .. word_length .. " LETTRES |\r\n")
    io.write("\x1b[4;11H==========================================================\r\n")

    io.write("\x1b[24;1H\x1b[K\x1b[7m MESSAGE: \x1b[0m " .. msg_board)

    update_grid()
    update_keyboard()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
io.write("\x1b[2J\x1b[H")
load_dictionary()
draw_title(true)

while true do
    local key = minitel.get_key()

    if key == "RETOUR" or key == "ESC" then
        if state == "TITLE" then
            break
        end
        state = "TITLE"
        draw_title(true)

    elseif state == "TITLE" then
        if key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
            state = "PLAYING"
            msg_board = "TAPEZ UN MOT ET APPUYEZ SUR ENVOI."
            reset_game()
            draw_game_screen()
        end

    elseif state == "PLAYING" then
        if key and string.match(key, "%a") and string.len(key) == 1 then
            if string.len(current_input) < word_length then
                current_input = current_input .. string.upper(key)
                minitel.play_sound("hit")
                update_grid()
            end
        elseif key == "\x08" or key == "\x7f" or key == "CORRECTION" or key == "ANNULATION" then
            if string.len(current_input) > 0 then
                current_input = string.sub(current_input, 1, -2)
                update_grid()
            end
        elseif key == "\n" or key == "\r" or key == "ENVOI" then
            if string.len(current_input) == word_length then
                evaluate_guess(current_input)
                current_input = ""

                io.write("\x1b[24;1H\x1b[K\x1b[7m MESSAGE: \x1b[0m " .. msg_board)
                update_grid()
                update_keyboard()
            else
                io.write("\x1b[24;1H\x1b[K\x1b[7m ERREUR: \x1b[0m LE MOT DOIT CONTENIR " .. word_length .. " LETTRES.")
                io.flush()
            end
        end

    elseif state == "GAMEOVER" or state == "VICTORY" then
        if key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
            state = "PLAYING"
            msg_board = "REINITIALISATION DU BRUTE-FORCE..."
            reset_game()
            draw_game_screen()
        end
    end
end

minitel.cleanup()