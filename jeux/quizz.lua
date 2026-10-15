-- @GENRE: QUIZZ / MULTIJOUEUR LIVE
-- @DESC: Jeu televise annees 90 ! Questions generees a la volee sur Internet (Solo) ou plateau multijoueur Live.

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local CFG_FILE = "utils/pictochat.cfg"
local server_url = "http://127.0.0.1:8085"
local pseudo = "CANDIDAT52"

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

local function decode_json_str(str)
    if not str then return "" end
    str = str:gsub("\\u00[eE][89aAbB]", "E")
    str = str:gsub("\\u00[eE][024]", "A")
    str = str:gsub("\\u00[eE][eEfF]", "I")
    str = str:gsub("\\u00[fF][46]", "O")
    str = str:gsub("\\u00[fF][9bBcC]", "U")
    str = str:gsub("\\u00[eE]7", "C")
    str = str:gsub("&quot;", "'"):gsub("&#039;", "'"):gsub("&amp;", "&"):gsub("&eacute;", "E"):gsub("&egrave;", "E"):gsub("&agrave;", "A")
    str = str:gsub('\\"', "'"):gsub("\\/", "/"):gsub("\\n", " ")
    return minitel.clean_accents(str)
end

local function http_query(url_full)
    local cmd = string.format("curl -sL -k -m 4 -A 'Mozilla/5.0' '%s' 2>/dev/null", url_full)
    local f = io.popen(cmd)
    if not f then return "" end
    local res = f:read("*a") or ""
    f:close()
    return res
end

local DEPTS_90 = {
    {"01", "Ain", "Bourg-en-Bresse"}, {"02", "Aisne", "Laon"}, {"06", "Alpes-Maritimes", "Nice"},
    {"08", "Ardennes", "Charleville-Mezieres"}, {"10", "Aube", "Troyes"}, {"13", "Bouches-du-Rhone", "Marseille"},
    {"14", "Calvados", "Caen"}, {"21", "Cote-d'Or", "Dijon"}, {"25", "Doubs", "Besancon"},
    {"29", "Finistere", "Quimper"}, {"31", "Haute-Garonne", "Toulouse"}, {"33", "Gironde", "Bordeaux"},
    {"38", "Isere", "Grenoble"}, {"44", "Loire-Atlantique", "Nantes"}, {"51", "Marne", "Chalons-en-Champagne"},
    {"52", "Haute-Marne", "Chaumont"}, {"54", "Meurthe-et-Moselle", "Nancy"}, {"55", "Meuse", "Bar-le-Duc"},
    {"57", "Moselle", "Metz"}, {"59", "Nord", "Lille"}, {"67", "Bas-Rhin", "Strasbourg"},
    {"69", "Rhone", "Lyon"}, {"75", "Paris", "Paris"}, {"88", "Vosges", "Epinal"}
}

local FALLBACK_90S = {
    { cat = "TELECOM 90S", q = "En quelle annee les PTT sont-elles devenues l'exploitant public France Telecom ?", a = "1982", b = "1991", c = "1998", d = "2004", ans = 2 },
    { cat = "AUTO 90S",    q = "Quel moteur 2.0L 16 soupapes de 167 ch equipe la Citroen ZX 16V et la 306 S16 BV6 ?", a = "XU10J4RS", b = "TU5JP4", c = "PRV V6", d = "XUD9TE", ans = 1 },
    { cat = "TELECOM 90S", q = "Quel etait le nom du premier telephone portable grand public lance par France Telecom en 1991 ?", a = "Bi-Bop", b = "Itineris", c = "Tam-Tam", d = "Mobicarte", ans = 1 },
    { cat = "AUTO 90S",    q = "Quel calculateur d'injection equipe les Renault 25 V6 Turbo et Clio Williams dans les annees 90 ?", a = "Bosch EDC16", b = "Renix / Bendix Fenix", c = "Lucas EPIC", d = "Continental", ans = 2 },
    { cat = "MICRO 90S",   q = "Quel ordinateur 16/32 bits de Commodore utilisait le Workbench sur disquette 3.5 pouces ?", a = "Amiga 500 / 1200", b = "ZX81", c = "Oric Atmos", d = "TO7-70", ans = 1 },
    { cat = "AUTO 90S",    q = "Quel diesel atmospherique ou turbo ultra-robuste a motorise les 205, 405, ZX et BX ?", a = "Moteur XUD (XUD7 / XUD9)", b = "Moteur Douvrin", c = "Moteur Cleon-Fonte", d = "Moteur Poissy", ans = 1 }
}

local function fetch_dynamic_question()
    local raw = http_query("https://quizzapi.jomoreschi.fr/api/v1/quiz?limit=1")
    if raw and raw:find('"question"') then
        local cat  = decode_json_str(raw:match('"category"%s*:%s*"([^"]+)"') or "CULTURE GENERALE"):upper()
        local qtxt = decode_json_str(raw:match('"question"%s*:%s*"([^"]+)"') or "")
        local good = decode_json_str(raw:match('"answer"%s*:%s*"([^"]+)"') or "")
        local bad_block = raw:match('"badAnswers"%s*:%s*%[(.-)%]')

        if qtxt ~= "" and good ~= "" and bad_block then
            local opts = { good }
            for b in bad_block:gmatch('"([^"]+)"') do
                table.insert(opts, decode_json_str(b))
            end
            if #opts >= 4 then
                local final_opts = { opts[1], opts[2], opts[3], opts[4] }
                for i = 4, 2, -1 do
                    local j = math.random(1, i)
                    final_opts[i], final_opts[j] = final_opts[j], final_opts[i]
                end
                local ans_idx = 1
                for i = 1, 4 do
                    if final_opts[i] == good then ans_idx = i; break end
                end
                return {
                    cat = string.sub(cat, 1, 18),
                    q = qtxt,
                    a = final_opts[1], b = final_opts[2], c = final_opts[3], d = final_opts[4],
                    ans = ans_idx
                }
            end
        end
    end

    if math.random(1, 3) == 1 then
        local target = DEPTS_90[math.random(1, #DEPTS_90)]
        local opts = { target[2] .. " (" .. target[3] .. ")" }
        while #opts < 4 do
            local cand = DEPTS_90[math.random(1, #DEPTS_90)]
            local label = cand[2] .. " (" .. cand[3] .. ")"
            local exists = false
            for _, v in ipairs(opts) do if v == label then exists = true end end
            if not exists then table.insert(opts, label) end
        end
        local good = opts[1]
        for i = 4, 2, -1 do
            local j = math.random(1, i)
            opts[i], opts[j] = opts[j], opts[i]
        end
        local ans_idx = 1
        for i = 1, 4 do if opts[i] == good then ans_idx = i end end
        return {
            cat = "GEOGRAPHIE FRANCE",
            q = "A quel departement et prefecture correspond le numero mineralogique " .. target[1] .. " ?",
            a = opts[1], b = opts[2], c = opts[3], d = opts[4], ans = ans_idx
        }
    else
        return FALLBACK_90S[math.random(1, #FALLBACK_90S)]
    end
end

-- =====================================================================
-- AFFICHAGE DE L'ECRAN DE QUIZZ (SQUELETTE FIXE + MISE A JOUR LEGERE)
-- =====================================================================
local function draw_quizz_skeleton(mode_title)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 QUIZZ LIVE - " .. mode_title .. "  * * *", 80) .. "\x1b[0m")
    minitel.draw_window(2, 3, 52, 14, "QUESTION")
    io.write("\x1b[8;2H\x1b[1m+--------------------------------------------------+\x1b[0m")
    minitel.draw_window(55, 3, 25, 14, "PALMARES DIRECT")
    minitel.draw_window(2, 18, 78, 5, "CHRONOMETRE & VERDICT DU PRESENTATEUR")
    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2], [3] OU [4] POUR BUZZER   |   [RETOUR] QUITTER LE PLATEAU      \x1b[0m")
    io.flush()
end

local function update_quizz_content(cat, q_text, opts, time_left, selected_opt, status_msg, scores_str)
    local t_str = " THEME : " .. string.sub(cat, 1, 36) .. " "
    io.write(string.format("\x1b[3;2H\x1b[1m+\x1b[0m\x1b[7m%s\x1b[0m\x1b[1m+\x1b[0m", minitel.center(t_str, 50)))

    local q_lines = minitel.wrap(q_text, 48, 3)
    for i = 1, 3 do
        io.write(string.format("\x1b[%d;4H\x1b[1m%s\x1b[0m", 4 + i, minitel.pad(q_lines[i], 48)))
    end

    for i = 1, 4 do
        local y = 8 + (i * 2)
        local line = string.format(" [%d] %s", i, minitel.pad(opts[i] or "", 42))
        if selected_opt == i then
            io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 48)))
        else
            io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 48)))
        end
    end

    local s_list = {}
    for entry in tostring(scores_str or ""):gmatch("([^,]+)") do table.insert(s_list, entry) end
    for i = 1, 10 do
        io.write(string.format("\x1b[%d;57H%-21s", 4 + i, string.sub(s_list[i] or "", 1, 21)))
    end

    io.write(string.format("\x1b[19;4HTEMPS RESTANT : \x1b[7m %02d SECONDES \x1b[0m    ", time_left))
    io.write("\x1b[21;4H> " .. minitel.pad(status_msg, 72))
    io.flush()
end

-- =====================================================================
-- MODE 1 : PLATEAU EN DIRECT MULTIJOUEUR
-- =====================================================================
local function play_live_online()
    draw_quizz_skeleton("DIRECT MULTIJOUEUR")
    local cur_qid = -1
    local my_choice = 0
    local status_msg = "CONNEXION AU SERVEUR QUIZZ LIVE..."
    local last_poll = 0

    while true do
        local now = os.time()
        if now - last_poll >= 3 then
            last_poll = now
            local raw = http_query(server_url .. "/api/quizz/state?user=" .. urlencode(pseudo))
            local qid, tleft, cat, qtxt, o1, o2, o3, o4, win_info, board =
                raw:match("^QSTATE|(%d+)|(%d+)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.*)$")

            if not qid then
                minitel.msg_box("ERREUR SERVEUR", "Impossible de joindre le plateau Quizz sur " .. server_url, "lose")
                return
            end

            qid = tonumber(qid)
            tleft = tonumber(tleft) or 20

            if qid ~= cur_qid then
                cur_qid = qid
                my_choice = 0
                minitel.play_sound("pickup")
                status_msg = (win_info ~= "" and win_info) or "NOUVELLE QUESTION ! BUZZEZ VITE (1 A 4) !"
                update_quizz_content(cat, qtxt, {o1, o2, o3, o4}, tleft, my_choice, status_msg, board)
            else
                -- Mise a jour ultra-legere (juste les 2 chiffres des secondes !)
                io.write(string.format("\x1b[19;20H\x1b[7m %02d SECONDES \x1b[0m", tleft))
                io.flush()
            end
        end

        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif (k == "1" or k == "2" or k == "3" or k == "4") and my_choice == 0 and cur_qid >= 0 then
                my_choice = tonumber(k)
                local res = http_query(string.format("%s/api/quizz/answer?user=%s&qid=%d&choice=%d",
                    server_url, urlencode(pseudo), cur_qid, my_choice))

                if res:find("^CORRECT|") then
                    local pts = res:match("^CORRECT|(%d+)") or "100"
                    minitel.play_sound("win")
                    status_msg = "BONNE REPONSE ! VOUS REMPORTEZ +" .. pts .. " POINTS !"
                elseif res:find("^WRONG|") then
                    minitel.play_sound("lose")
                    status_msg = "MAUVAISE REPONSE ! Attendez la prochaine question..."
                else
                    minitel.play_sound("hit")
                    status_msg = "Reponse enregistree."
                end
                io.write("\x1b[21;4H> " .. minitel.pad(status_msg, 72))
                io.flush()
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MODE 2 : SOLO INFINI (SANS RAFRAICHISSEMENT CONTINU)
-- =====================================================================
local function play_solo_infinite()
    draw_quizz_skeleton("SOLO INFINI")
    local score = 0
    local q_num = 0

    while true do
        q_num = q_num + 1
        io.write("\x1b[21;4H> " .. minitel.pad("TIRAGE DE LA QUESTION #" .. q_num .. " EN COURS...", 72))
        io.flush()

        local item = fetch_dynamic_question()
        local board = string.format("1. %s : %d PTS", pseudo, score)

        update_quizz_content(
            item.cat, item.q,
            {item.a, item.b, item.c, item.d},
            20, 0,
            "TAPEZ 1, 2, 3 OU 4 POUR REPONDRE ([RETOUR] = ARRETER)",
            board
        )

        local start_t = os.time()
        local last_sec_drawn = 20
        local answered = false

        while not answered do
            local elapsed = os.time() - start_t
            local t_left = math.max(0, 20 - elapsed)

            if t_left ~= last_sec_drawn then
                last_sec_drawn = t_left
                io.write(string.format("\x1b[19;20H\x1b[7m %02d SECONDES \x1b[0m", t_left))
                io.flush()
            end

            if t_left <= 0 then break end

            local k = minitel.get_key()
            if k == "RETOUR" or k == "ESC" then
                minitel.msg_box("FIN DE PARTIE", "Vous repartez avec une cagnotte de " .. score .. " points !", "pickup")
                return
            elseif k == "1" or k == "2" or k == "3" or k == "4" then
                answered = true
                local c = tonumber(k)
                local opts_arr = {item.a, item.b, item.c, item.d}
                if c == item.ans then
                    local pts = 100 + (t_left * 5)
                    score = score + pts
                    minitel.msg_box("EXACT ! (+" .. pts .. " PTS)", "Bonne reponse : " .. opts_arr[item.ans], "win")
                else
                    minitel.msg_box("DOMMAGE !", "La bonne reponse etait [" .. item.ans .. "] : " .. opts_arr[item.ans], "lose")
                end
                draw_quizz_skeleton("SOLO INFINI")
            end
            minitel.sleep(0.02)
        end

        if not answered then
            local opts_arr = {item.a, item.b, item.c, item.d}
            minitel.msg_box("TEMPS ECOULE !", "La bonne reponse etait [" .. item.ans .. "] : " .. opts_arr[item.ans], "lose")
            draw_quizz_skeleton("SOLO INFINI")
        end
    end
end

-- =====================================================================
-- MENU D'ACCUEIL (DESSINE UNE SEULE FOIS HORS BOUCLE !)
-- =====================================================================
local function draw_main_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 QUIZZ LIVE - LE JEU TELEVISE TELEMATIQUE  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(16, 5, 50, 15, "CHOIX DU PLATEAU")
    io.write("\x1b[7;20H\x1b[1mSERVEUR :\x1b[0m " .. string.sub(server_url, 1, 32))
    io.write("\x1b[8;20H\x1b[1mCANDIDAT:\x1b[0m " .. pseudo)
    io.write("\x1b[10;20H\x1b[7m [1] \x1b[0m PLATEAU LIVE MULTIJOUEUR (WEB/DISCORD)")
    io.write("\x1b[12;20H\x1b[7m [2] \x1b[0m QUIZZ SOLO INFINI (QUESTIONS A LA VOLEE)")
    io.write("\x1b[14;20H\x1b[7m [3] \x1b[0m CONFIGURER SERVEUR / PSEUDO")
    io.write("\x1b[17;20H\x1b[7m [RETOUR] \x1b[0m QUITTER VERS LE PORTAIL")

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2] OU [3]   |   GENERATION AUTOMATIQUE DE QUESTIONS FR            \x1b[0m")
    io.flush()
end

draw_main_menu()

while true do
    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "1" then
        play_live_online()
        draw_main_menu()
    elseif k == "2" then
        play_solo_infinite()
        draw_main_menu()
    elseif k == "3" then
        local ns = minitel.input_box("SERVEUR EN LIGNE", "URL du serveur :", server_url, 42)
        if ns and ns ~= "" then server_url = ns:gsub("/+$", "") end
        local np = minitel.input_box("NOM CANDIDAT", "Votre pseudo (10 car. max) :", pseudo, 10)
        if np and np ~= "" then pseudo = string.upper(minitel.clean_accents(np)):gsub("[^%w_%-]", "") end
        local f = io.open(CFG_FILE, "w")
        if f then f:write(server_url .. "\n" .. pseudo .. "\n"); f:close() end
        draw_main_menu()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()