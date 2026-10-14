-- @TYPE: TELEMATIQUE / AUTO
-- @DESC: Comparateur des prix des carburants (Gazole, SP98, E10) en direct via l'API OpenData gouvernementale.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- PARSEUR JSON NATIF LUA (AVEC GESTION D'ACCOLADES %b{})
-- =====================================================================
local function decode_json_str(str)
    if not str then return "INCONNU" end
    str = str:gsub("\\u00[eE][89aAbB]", "E")
    str = str:gsub("\\u00[eE][02]", "A")
    str = str:gsub("\\u00[eE][eEfF]", "I")
    str = str:gsub("\\u00[fF][46]", "O")
    str = str:gsub("\\u00[fF][9bBcC]", "U")
    str = str:gsub("\\u00[eE]7", "C")
    str = str:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\n", " "):gsub("\\r", "")
    return string.upper(minitel.clean_accents(str))
end

local function extract_str(block, field)
    local val = block:match('"' .. field .. '"%s*:%s*"([^"]*)"')
    if val and val ~= "" then return decode_json_str(val) end
    return nil
end

local function extract_price(block, field)
    -- Gere aussi bien les nombres (1.759) que les chaines ("1.759")
    local val = block:match('"' .. field .. '"%s*:%s*"?([%d%.]+)"?')
    if val and tonumber(val) then
        local num = tonumber(val)
        -- Certains flux renvoient les prix en milliemes d'euros (ex: 1759 au lieu de 1.759)
        if num > 100 then num = num / 1000 end
        return string.format("%.3f", num)
    end
    return "N/A"
end

local function parse_stations_from_json(json)
    local stations = {}
    if not json or json == "" then return stations end

    -- On isole le tableau "results" grace au motif equilibre %b[] de Lua !
    local results_array = json:match('"results"%s*:%s*(%b[])')
    if not results_array then return stations end

    -- On parcourt chaque objet station { ... } grace au motif equilibre %b{}
    local inner = results_array:sub(2, -2)
    for block in inner:gmatch("%b{}") do
        local adr = extract_str(block, "adresse")
        local vil = extract_str(block, "ville")

        -- On verifie que c'est bien un bloc de station (qui contient une adresse ou une ville)
        if adr or vil then
            local gaz  = extract_price(block, "gazole_prix")
            local sp98 = extract_price(block, "sp98_prix")
            local e10  = extract_price(block, "e10_prix")
            local sp95 = extract_price(block, "sp95_prix")

            -- Si E10 absent mais SP95 present, on affiche le SP95 dans la colonne E10/95
            if e10 == "N/A" and sp95 ~= "N/A" then e10 = sp95 end

            table.insert(stations, {
                adresse = adr or "STATION",
                ville   = vil or "INCONNUE",
                gazole  = gaz,
                sp98    = sp98,
                e10     = e10
            })
        end
    end

    -- Tri par prix du Gazole croissant (les stations en rupture a la fin)
    table.sort(stations, function(a, b)
        local pa = tonumber(a.gazole) or 999
        local pb = tonumber(b.gazole) or 999
        return pa < pb
    end)

    return stations
end

-- =====================================================================
-- MOTEUR DE RECUPERATION API GOUVERNEMENTALE (AVEC FALLBACK DEPARTEMENT)
-- =====================================================================
local function query_url(url)
    local cmd = string.format('curl -sL -k -m 10 -A "Mozilla/5.0" "%s" 2>/dev/null', url)
    local f = io.popen(cmd)
    if not f then return nil end
    local res = f:read("*a")
    f:close()
    return res
end

local function fetch_stations(cp)
    minitel.draw_window(15, 9, 52, 5, "INTERROGATION SERVEUR ETAT")
    io.write("\x1b[11;17H" .. minitel.center("RECHERCHE CODE POSTAL : " .. cp, 48))
    io.flush()
    minitel.play_sound("hit")

    local base_api = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records"

    -- 1. Recherche exacte sur le Code Postal via refine=cp:XXXXX (aucun guillemet problematique)
    local url_cp = base_api .. "?limit=25&refine=cp:" .. cp
    local json = query_url(url_cp)

    if not json or json == "" then
        return nil, false
    end

    local stations = parse_stations_from_json(json)

    -- 2. Si aucune station dans ce code postal exact, on elargit aux villes commencant par les 2 chiffres du departement !
    if #stations == 0 then
        local dept = string.sub(cp, 1, 2)
        io.write("\x1b[11;17H" .. minitel.center("ELARGISSEMENT AU DEPARTEMENT " .. dept .. "...", 48))
        io.flush()

        local url_dept = base_api .. "?limit=30&where=startswith(cp%2C%22" .. dept .. "%22)"
        local json_dept = query_url(url_dept)
        if json_dept and json_dept ~= "" then
            stations = parse_stations_from_json(json_dept)
            return stations, true -- true indique qu'on affiche tout le departement
        end
    end

    return stations, false
end

-- =====================================================================
-- AFFICHAGE DU TABLEAU COMPARATEUR (DELTA-DRAWING 9600 BAUDS)
-- =====================================================================
local max_visible = 12

local function draw_station_row(stations, slot, offset, cursor)
    local idx = offset + slot
    local st = stations[idx]
    local y = 7 + slot

    if not st then
        io.write(string.format("\x1b[%d;3H%s", y, string.rep(" ", 76)))
        return
    end

    local loc = st.ville .. " - " .. st.adresse
    local gaz_s  = (st.gazole == "N/A") and "  ---  " or (st.gazole .. "E")
    local sp98_s = (st.sp98 == "N/A")   and "  ---  " or (st.sp98 .. "E")
    local e10_s  = (st.e10 == "N/A")    and "  ---  " or (st.e10 .. "E")

    local line = string.format(" %-42s | %-7s | %-7s | %-7s ",
        minitel.pad(loc, 42), gaz_s, sp98_s, e10_s)

    if idx == cursor then
        io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 74)))
    else
        io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 74)))
    end
end

local function draw_board_full(cp, stations, offset, cursor, is_dept)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    local zone_label = is_dept and ("DEPT " .. string.sub(cp, 1, 2) .. " (PROCHE " .. cp .. ")") or ("CP " .. cp)
    local top_bar = string.format("3615 CARBURANT - %s (%d STATIONS)", zone_label, #stations)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top_bar, 80) .. "\x1b[0m")

    minitel.draw_window(2, 3, 78, 19, "COMPARATEUR DES PRIX DU JOUR (TRIE PAR GAZOLE)")
    io.write("\x1b[5;3H\x1b[7m  VILLE & ADRESSE                            | GAZOLE  |  SP98   | E10/95  \x1b[0m")
    io.write("\x1b[6;2H\x1b[1m+----------------------------------------------------------------------------+\x1b[0m")

    for slot = 1, max_visible do
        draw_station_row(stations, slot, offset, cursor)
    end

    io.write("\x1b[24;1H\x1b[7m [Z/S] NAVIGUER | [ENVOI] DETAILS | [N] NOUVEAU CP | [A]CTUALISER | [RETOUR]  \x1b[0m")
    io.flush()
end

local function show_stations_loop(cp, stations, is_dept)
    local cursor = 1
    local offset = 0
    draw_board_full(cp, stations, offset, cursor, is_dept)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return "QUIT"
            elseif k == "N" or k == "n" then
                return "NEW"
            elseif k == "A" or k == "a" or k == "REPETITION" then
                return "REFRESH"
            elseif k == "UP" or k == "Z" or k == "z" then
                local old_c, old_off = cursor, offset
                if cursor > 1 then
                    cursor = cursor - 1
                    if cursor <= offset then offset = cursor - 1 end
                else
                    cursor = #stations
                    offset = math.max(0, #stations - max_visible)
                end
                if offset ~= old_off then
                    for s = 1, max_visible do draw_station_row(stations, s, offset, cursor) end
                else
                    draw_station_row(stations, old_c - offset, offset, cursor)
                    draw_station_row(stations, cursor - offset, offset, cursor)
                end
                io.flush()

            elseif k == "DOWN" or k == "S" or k == "s" then
                local old_c, old_off = cursor, offset
                if cursor < #stations then
                    cursor = cursor + 1
                    if cursor > offset + max_visible then offset = cursor - max_visible end
                else
                    cursor = 1
                    offset = 0
                end
                if offset ~= old_off then
                    for s = 1, max_visible do draw_station_row(stations, s, offset, cursor) end
                else
                    draw_station_row(stations, old_c - offset, offset, cursor)
                    draw_station_row(stations, cursor - offset, offset, cursor)
                end
                io.flush()

            elseif k == "ENVOI" or k == "\r" or k == "\n" or k == " " then
                local st = stations[cursor]
                if st then
                    local msg = string.format("%s (%s) - Gazole: %s E | SP98: %s E | E10/95: %s E",
                        st.adresse, st.ville, st.gazole, st.sp98, st.e10)
                    minitel.msg_box("FICHE STATION SERVICE", msg, "pickup")
                    draw_board_full(cp, stations, offset, cursor, is_dept)
                end
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
local last_cp = "52300"

while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 CARBURANT - OBSERVATOIRE DES PRIX  * * *", 80) .. "\x1b[0m")
    io.flush()

    local cp = minitel.input_box(
        "RECHERCHE PAR CODE POSTAL",
        "Entrez un code postal a 5 chiffres :",
        last_cp,
        5
    )

    if not cp then break end
    cp = cp:gsub("%s+", "")

    if not cp:match("^%d%d%d%d%d$") then
        minitel.msg_box("CODE INVALIDE", "Veuillez saisir exactement 5 chiffres (ex: 52300, 52000, 51100).", "lose")
    else
        last_cp = cp
        local stay = true
        while stay do
            local stations, is_dept = fetch_stations(last_cp)
            if not stations then
                minitel.msg_box("ERREUR RESEAU", "Impossible de contacter data.economie.gouv.fr (Verifiez curl).", "lose")
                stay = false
            elseif #stations == 0 then
                minitel.msg_box("AUCUN RESULTAT", "Aucune station trouvee pour " .. last_cp .. " ni dans son departement.", "lose")
                stay = false
            else
                minitel.play_sound("pickup")
                local act = show_stations_loop(last_cp, stations, is_dept)
                if act == "QUIT" then
                    minitel.cleanup()
                    os.exit()
                elseif act == "NEW" then
                    stay = false
                end
            end
        end
    end
end

minitel.cleanup()