-- @TYPE: TELEMATIQUE / RESEAU
-- @DESC: Panneau d'affichage des departs ferroviaires en temps reel (TGV, TER, Intercites) avec voies et retards.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- PARSEUR JSON NATIF LUA & NETTOYAGE
-- =====================================================================
local function urlencode(str)
    str = string.gsub(str, " ", "%%20")
    str = string.gsub(str, "'", "%%27")
    return str
end

local function decode_json_string(str)
    if not str then return "" end
    -- Decodage des sequences Unicode JSON courantes
    str = str:gsub("\\u00[eE][89aAbB]", "E")
    str = str:gsub("\\u00[eE][02]", "A")
    str = str:gsub("\\u00[eE][eEfF]", "I")
    str = str:gsub("\\u00[fF][46]", "O")
    str = str:gsub("\\u00[fF][9bBcC]", "U")
    str = str:gsub("\\u00[eE]7", "C")
    str = str:gsub('\\"', '"'):gsub("\\/", "/")
    -- Nettoyage UTF-8 via le SDK
    return string.upper(minitel.clean_accents(str))
end

-- =====================================================================
-- MOTEUR DE RECUPERATION API (100% LUA + FENETRE D'ATTENTE SDK)
-- =====================================================================
local function fetch_trains(station_name)
    minitel.draw_window(18, 9, 46, 5, "CONNEXION RESEAU X.25")
    io.write("\x1b[11;20H" .. minitel.center("INTERROGATION DE : " .. station_name, 42))
    io.flush()
    minitel.play_sound("hit")

    local url = "http://transport.opendata.ch/v1/stationboard?station=" .. urlencode(station_name) .. "&limit=13"
    local f = io.popen("curl -sL -k -m 8 '" .. url .. "' 2>/dev/null")
    if not f then return nil, {} end
    local json = f:read("*a")
    f:close()

    if not json or json == "" then return nil, {} end

    -- 1. Extraction du vrai nom de la gare
    local real_station = station_name
    local station_block = json:match('"station"%s*:%s*{(.-)}')
    if station_block then
        local name = station_block:match('"name"%s*:%s*"([^"]+)"')
        if name then real_station = decode_json_string(name) end
    end

    -- 2. Extraction des trains (heure, destination, numero, voie, retard)
    local trains = {}
    for block in json:gmatch('{"stop":.-"to"%s*:%s*"[^"]+"') do
        local dep  = block:match('"departure"%s*:%s*"([^"]+)"')
        local dest = block:match('"to"%s*:%s*"([^"]+)"')
        local cat  = block:match('"category"%s*:%s*"([^"]*)"') or ""
        local num  = block:match('"number"%s*:%s*"([^"]*)"') or ""
        local plat = block:match('"platform"%s*:%s*"([^"]*)"')
        local dly  = block:match('"delay"%s*:%s*(%d+)')

        if dep and dest then
            local time_str = string.sub(dep, 12, 16)
            local train_name = decode_json_string(cat .. " " .. num):gsub("^%s+", ""):gsub("%s+$", "")
            if train_name == "" then train_name = "TRAIN" end

            local status_str = "A L'HEURE"
            if dly and tonumber(dly) and tonumber(dly) > 0 then
                status_str = "RET +" .. dly .. "M"
            elseif plat and plat ~= "" then
                status_str = "VOIE " .. decode_json_string(plat)
            end

            table.insert(trains, {
                time   = time_str,
                dest   = decode_json_string(dest),
                name   = string.sub(train_name, 1, 14),
                status = string.sub(status_str, 1, 10)
            })
        end
    end

    return real_station, trains
end

-- =====================================================================
-- AFFICHAGE DU PANNEAU DE GARE SOLARI (DELTA-DRAWING 9600 BAUDS)
-- =====================================================================
local function draw_train_row(trains, idx, cursor)
    local tr = trains[idx]
    local y = 7 + idx
    if not tr then return end

    local line = string.format(" %s | %-34s | %-14s | %-10s ",
        tr.time,
        minitel.pad(tr.dest, 34),
        minitel.pad(tr.name, 14),
        minitel.pad(tr.status, 10)
    )

    if idx == cursor then
        io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 74)))
    else
        io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 74)))
    end
end

local function draw_board_full(station, trains, cursor)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Bandeau Superieur
    local top_title = "3615 TRAIN - GARE DE : " .. string.sub(station, 1, 42)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top_title, 80) .. "\x1b[0m")

    -- Cadre Principal Solari
    minitel.draw_window(2, 3, 78, 19, "PANNEAU DES PROCHAINS DEPARTS")

    -- Entete des colonnes
    io.write("\x1b[5;3H\x1b[7m  HEURE | DESTINATION                        | TRAIN          | VOIE/ETAT   \x1b[0m")
    io.write("\x1b[6;2H\x1b[1m+----------------------------------------------------------------------------+\x1b[0m")

    if #trains == 0 then
        io.write("\x1b[12;4H" .. minitel.center("AUCUN DEPART PREVU OU GARE INTROUVABLE SUR LE RESEAU", 74))
    else
        for i = 1, math.min(13, #trains) do
            draw_train_row(trains, i, cursor)
        end
    end

    -- Bandeau Inferieur
    io.write("\x1b[24;1H\x1b[7m [Z/S] CURSEUR | [ENVOI] DETAILS | [N] NOUVELLE GARE | [A]CTUALISER | [RETOUR] \x1b[0m")
    io.flush()
end

local function show_board_loop(station, trains)
    local cursor = 1
    local max_rows = math.min(13, #trains)
    draw_board_full(station, trains, cursor)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return "QUIT"

            elseif k == "N" or k == "n" then
                return "NEW"

            elseif k == "A" or k == "a" or k == "REPETITION" then
                return "REFRESH"

            elseif (k == "UP" or k == "Z" or k == "z") and max_rows > 0 then
                local old_c = cursor
                cursor = (cursor > 1) and (cursor - 1) or max_rows
                draw_train_row(trains, old_c, cursor)
                draw_train_row(trains, cursor, cursor)
                io.flush()

            elseif (k == "DOWN" or k == "S" or k == "s") and max_rows > 0 then
                local old_c = cursor
                cursor = (cursor < max_rows) and (cursor + 1) or 1
                draw_train_row(trains, old_c, cursor)
                draw_train_row(trains, cursor, cursor)
                io.flush()

            elseif k == "ENVOI" or k == "\r" or k == "\n" or k == " " then
                if max_rows > 0 and trains[cursor] then
                    local t = trains[cursor]
                    local detail_msg = string.format("Train %s de %s a destination de %s. Statut : %s.",
                        t.name, t.time, t.dest, t.status)
                    minitel.msg_box("FICHE DU TRAIN", detail_msg, "pickup")
                    draw_board_full(station, trains, cursor)
                else
                    return "NEW"
                end
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
local last_station = "CHAUMONT"

while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 TRAIN - HORAIRES SNCF EN DIRECT  * * *", 80) .. "\x1b[0m")
    io.flush()

    local search = minitel.input_box(
        "RECHERCHE DE GARE SNCF",
        "Gare (ex: CHAUMONT, REIMS, PARIS EST) :",
        last_station,
        30
    )

    if not search then
        break -- L'utilisateur a appuye sur RETOUR ou ESC
    end

    search = decode_json_string(search):gsub("^%s+", ""):gsub("%s+$", "")
    if search ~= "" then
        last_station = search
        local keep_station = true

        while keep_station do
            local real_name, trains = fetch_trains(last_station)
            if not real_name then
                minitel.msg_box("ERREUR RESEAU", "Impossible de joindre le serveur ferroviaire.", "lose")
                keep_station = false
            else
                if #trains > 0 then minitel.play_sound("pickup") else minitel.play_sound("lose") end
                local action = show_board_loop(real_name, trains)
                if action == "QUIT" then
                    minitel.cleanup()
                    os.exit()
                elseif action == "NEW" then
                    keep_station = false
                elseif action == "REFRESH" then
                    -- Relance simplement la boucle sur la meme gare !
                end
            end
        end
    end
end

minitel.cleanup()