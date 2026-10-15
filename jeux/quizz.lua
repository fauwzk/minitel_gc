-- @GENRE: QUIZZ / MULTIJOUEUR LIVE
-- @DESC: Jeu televise en direct ! Affrontez les joueurs Web et Discord en temps reel sur la meme question ou jouez en solo.

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local CFG_FILE = "utils/pictochat.cfg"
local server_url = "http://127.0.0.1:8085"
local pseudo = "JOUEUR_52"

local function load_config()
    local f = io.open(CFG_FILE, "r")
    if f then
        local s = f:read("*l")
        local p = f:read("*l")
        f:close()
        if s and s ~= "" then server_url = s end
        if p and p ~= "" then pseudo = p end
    end
end
load_config()

local function urlencode(str)
    str = tostring(str or "")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

local function http_query(path)
    local cmd = string.format("curl -sL -k -m 4 '%s%s' 2>/dev/null", server_url, path)
    local f = io.popen(cmd)
    if not f then return "" end
    local res = f:read("*a") or ""
    f:close()
    return res
end

-- =====================================================================
-- BANQUE LOCALE POUR LE MODE SOLO HORS-LIGNE
-- =====================================================================
local SOLO_QUESTIONS = {
    { cat = "RETRO-TECH", q = "Quelle est la vitesse maximale du port serie du Minitel Magis Club en mode 80 colonnes ?", a = "1200 bauds", b = "4800 bauds", c = "9600 bauds", d = "56000 bauds", ans = 3 },
    { cat = "AUTOMOBILE", q = "Quelle est la longueur approximative de la boucle Nord (Nordschleife) du Nurburgring ?", a = "12,4 km", b = "20,8 km", c = "28,5 km", d = "34,2 km", ans = 2 },
    { cat = "MECANIQUE",  q = "Sur un moteur turbo diesel, que signifie le code defaut OBD standard P0299 ?", a = "Surchauffe liquide", b = "Pression turbo trop basse", c = "Defaut bougie prechauffage", d = "Capteur ABS HS", ans = 2 },
    { cat = "TELECOMS",   q = "Quel protocole reseau a commutation de paquets propulsait le reseau Teletel en France ?", a = "X.25 (Transpac)", b = "Token Ring", c = "ARPANET", d = "Fibre FTTH", ans = 1 },
    { cat = "MICRO 8-BIT", q = "Quel microprocesseur 8 bits equipe la console Nintendo Game Boy et le Sinclair ZX Spectrum ?", a = "MOS 6502", b = "Motorola 68000", c = "Zilog Z80 (ou derive)", d = "Intel 8088", ans = 3 },
    { cat = "GEOGRAPHIE", q = "Quel est le numero du departement de la Haute-Marne ?", a = "51", b = "52", c = "54", d = "55", ans = 2 },
    { cat = "VOIP & PBX", q = "Quel protocole standard est aujourd'hui le plus utilise pour interconnecter deux IPBX (Trunks) ?", a = "SIP (PJSIP)", b = "FTP", c = "SNMP", d = "Telnet", ans = 1 },
    { cat = "AUTOMOBILE", q = "Comment s'appelle le celebre virage releve en dalles de beton sur la Nordschleife ?", a = "Eau Rouge", b = "Parabolica", c = "Caracciola Karussell", d = "Laguna Seca", ans = 3 }
}

-- =====================================================================
-- AFFICHAGE DE L'ECRAN DE QUIZZ (SQUELETTE + DELTA)
-- =====================================================================
local function draw_quizz_screen(mode_title, cat, q_text, opts, time_left, max_time, selected_opt, status_msg, scores_str)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 QUIZZ LIVE - " .. mode_title .. "  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(2, 3, 52, 14, "CATEGORIE : " .. cat)
    local q_lines = minitel.wrap(q_text, 48, 3)
    for i = 1, 3 do
        io.write(string.format("\x1b[%d;4H\x1b[1m%s\x1b[0m", 4 + i, minitel.pad(q_lines[i], 48)))
    end
    io.write("\x1b[8;2H\x1b[1m+--------------------------------------------------+\x1b[0m")

    for i = 1, 4 do
        local y = 8 + (i * 2)
        local line = string.format(" [%d] %s", i, minitel.pad(opts[i] or "", 42))
        if selected_opt == i then
            io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 48)))
        else
            io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 48)))
        end
    end

    minitel.draw_window(55, 3, 25, 14, "CLASSEMENT DIRECT")
    local s_list = {}
    for entry in tostring(scores_str or ""):gmatch("([^,]+)") do
        table.insert(s_list, entry)
    end
    for i = 1, 10 do
        local sc = s_list[i] or ""
        io.write(string.format("\x1b[%d;57H%-21s", 4 + i, string.sub(sc, 1, 21)))
    end

    minitel.draw_window(2, 18, 78, 5, "CHRONOMETRE & VERDICT DU PRESENTATEUR")
    io.write("\x1b[19;4HTEMPS RESTANT : ")
    minitel.progress_bar(20, 19, 56, time_left, max_time, false)
    io.write("\x1b[21;4H> " .. minitel.pad(status_msg, 72))

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2], [3] OU [4] POUR REPONDRE   |   [RETOUR] QUITTER LE PLATEAU    \x1b[0m")
    io.flush()
end

-- =====================================================================
-- MODE 1 : PLATEAU EN DIRECT MULTIJOUEUR (MINITEL + WEB + DISCORD)
-- =====================================================================
local function play_live_online()
    local cur_qid = -1
    local my_choice = 0
    local status_msg = "CONNEXION AU PLATEAU 3615 QUIZZ LIVE EN COURS..."
    local last_poll = 0

    while true do
        local now = os.time()
        if now - last_poll >= 2 then
            last_poll = now
            local raw = http_query("/api/quizz/state?user=" .. urlencode(pseudo))
            -- Format: QSTATE|qid|time_left|cat|question|opt1|opt2|opt3|opt4|last_winner_info|leaderboard
            local qid, tleft, cat, qtxt, o1, o2, o3, o4, win_info, board =
                raw:match("^QSTATE|(%d+)|(%d+)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.*)$")

            if not qid then
                minitel.msg_box("ERREUR SERVEUR", "Impossible de joindre le serveur Quizz sur " .. server_url, "lose")
                return
            end

            qid = tonumber(qid)
            tleft = tonumber(tleft) or 20

            if qid ~= cur_qid then
                cur_qid = qid
                my_choice = 0
                minitel.play_sound("pickup")
                status_msg = (win_info ~= "" and win_info) or "NOUVELLE QUESTION ! SOYEZ LE PLUS RAPIDE (1 A 4) !"
                draw_quizz_screen("DIRECT MULTIJOUEUR", cat, qtxt, {o1, o2, o3, o4}, tleft, 25, my_choice, status_msg, board)
            else
                -- Mise a jour legere de la barre de temps et du classement sans redessiner l'ecran !
                minitel.progress_bar(20, 19, 56, tleft, 25, false)
                local s_list = {}
                for entry in tostring(board or ""):gmatch("([^,]+)") do table.insert(s_list, entry) end
                for i = 1, 10 do
                    io.write(string.format("\x1b[%d;57H%-21s", 4 + i, string.sub(s_list[i] or "", 1, 21)))
                end
                io.flush()
            end
        end

        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif (k == "1" or k == "2" or k == "3" or k == "4") and my_choice == 0 and cur_qid >= 0 then
                my_choice = tonumber(k)
                local res = http_query(string.format("/api/quizz/answer?user=%s&qid=%d&choice=%d",
                    urlencode(pseudo), cur_qid, my_choice))

                if res:find("^CORRECT|") then
                    local pts = res:match("^CORRECT|(%d+)") or "100"
                    minitel.play_sound("win")
                    status_msg = "BONNE REPONSE ! VOUS MARQUEZ +" .. pts .. " POINTS !"
                elseif res:find("^WRONG|") then
                    minitel.play_sound("lose")
                    status_msg = "MAUVAISE REPONSE ! Attendez la prochaine question..."
                else
                    minitel.play_sound("hit")
                    status_msg = "Reponse enregistree."
                end
                io.write("\x1b[21;4H> " .. minitel.pad(status_msg, 72))
                io.flush()
                last_poll = 0
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MODE 2 : ENTRAINEMENT SOLO HORS-LIGNE
-- =====================================================================
local function play_solo()
    local score = 0
    for idx, item in ipairs(SOLO_QUESTIONS) do
        local board = string.format("1. %s : %d PTS", pseudo, score)
        draw_quizz_screen(
            string.format("SOLO (%d/%d)", idx, #SOLO_QUESTIONS),
            item.cat, item.q,
            {item.a, item.b, item.c, item.d},
            20, 20, 0,
            "TAPEZ 1, 2, 3 OU 4 POUR REPONDRE !",
            board
        )

        local t_left = 20
        local tick = 0
        local answered = false

        while t_left > 0 and not answered do
            local k = minitel.get_key()
            if k == "RETOUR" or k == "ESC" then return
            elseif k == "1" or k == "2" or k == "3" or k == "4" then
                answered = true
                local c = tonumber(k)
                if c == item.ans then
                    local pts = 100 + (t_left * 5)
                    score = score + pts
                    minitel.msg_box("EXACT ! (+" .. pts .. " PTS)", "Bonne reponse ! Score total : " .. score .. " pts.", "win")
                else
                    minitel.msg_box("DOMMAGE !", "La bonne reponse etait le choix [" .. item.ans .. "].", "lose")
                end
            end
            minitel.sleep(0.05)
            tick = tick + 1
            if tick >= 20 then
                tick = 0
                t_left = t_left - 1
                minitel.progress_bar(20, 19, 56, t_left, 20, false)
            end
        end
        if not answered then
            minitel.msg_box("TEMPS ECOULE !", "La bonne reponse etait le choix [" .. item.ans .. "].", "lose")
        end
    end
    minitel.msg_box("FIN DU QUIZZ SOLO", "Bravo " .. pseudo .. " ! Votre score final est de " .. score .. " points !", "win")
end

-- =====================================================================
-- MENU D'ACCUEIL DU QUIZZ
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 QUIZZ LIVE - LE GRAND JEU TELEMATIQUE  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(16, 5, 50, 15, "CHOIX DU PLATEAU")
    io.write("\x1b[7;20H\x1b[1mSERVEUR :\x1b[0m " .. string.sub(server_url, 1, 32))
    io.write("\x1b[8;20H\x1b[1mCANDIDAT:\x1b[0m " .. pseudo)
    io.write("\x1b[10;20H\x1b[7m [1] \x1b[0m REJOINDRE LE QUIZZ LIVE (WEB/DISCORD)")
    io.write("\x1b[12;20H\x1b[7m [2] \x1b[0m PARTIE SOLO HORS-LIGNE (8 QUESTIONS)")
    io.write("\x1b[14;20H\x1b[7m [3] \x1b[0m CONFIGURER SERVEUR / PSEUDO")
    io.write("\x1b[17;20H\x1b[7m [RETOUR] \x1b[0m QUITTER VERS LE PORTAIL")

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2] OU [3]   |   JOUEZ AUSSI SUR LE WEB : /quizz                   \x1b[0m")
    io.flush()

    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then break
    elseif k == "1" then play_live_online()
    elseif k == "2" then play_solo()
    elseif k == "3" then
        local ns = minitel.input_box("SERVEUR EN LIGNE", "URL du serveur :", server_url, 42)
        if ns and ns ~= "" then server_url = ns:gsub("/+$", "") end
        local np = minitel.input_box("NOM CANDIDAT", "Votre pseudo (10 car. max) :", pseudo, 10)
        if np and np ~= "" then pseudo = string.upper(minitel.clean_accents(np)):gsub("[^%w_%-]", "") end
        local f = io.open(CFG_FILE, "w")
        if f then f:write(server_url .. "\n" .. pseudo .. "\n"); f:close() end
    end
    minitel.sleep(0.02)
end

minitel.cleanup()