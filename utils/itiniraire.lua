-- @TYPE: TELEMATIQUE / AUTO
-- @DESC: Calculateur d'itineraire routier et feuille de route detaillee (Km, Duree, Directions) en direct.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- UTILITAIRES HTTP & DECODAGE JSON NATIF LUA
-- =====================================================================
local function urlencode(str)
    str = tostring(str or "")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    str = str:gsub(" ", "%%20"):gsub("'", "%%27")
    return str
end

local function decode_json_str(str)
    if not str then return "" end
    str = str:gsub("\\u00[eE][89aAbB]", "E")
    str = str:gsub("\\u00[eE][02]", "A")
    str = str:gsub("\\u00[eE][eEfF]", "I")
    str = str:gsub("\\u00[fF][46]", "O")
    str = str:gsub("\\u00[fF][9bBcC]", "U")
    str = str:gsub("\\u00[eE]7", "C")
    str = str:gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\n", " ")
    return string.upper(minitel.clean_accents(str))
end

local function query_url(url)
    local cmd = string.format('curl -sL -k -m 10 -A "Mozilla/5.0" "%s" 2>/dev/null', url)
    local f = io.popen(cmd)
    if not f then return nil end
    local res = f:read("*a")
    f:close()
    return res
end

-- =====================================================================
-- 1. GEOCODAGE DES VILLES (API ADRESSE GOUV.FR)
-- =====================================================================
local function get_city_coords(city_query)
    local url = "https://api-adresse.data.gouv.fr/search/?q=" .. urlencode(city_query) .. "&type=municipality&limit=1"
    local json = query_url(url)
    if not json or json == "" then return nil, nil end

    local lon, lat = json:match('"coordinates"%s*:%s*%[%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*%]')
    local label = json:match('"label"%s*:%s*"([^"]+)"')
    local postcode = json:match('"postcode"%s*:%s*"([^"]+)"')

    if not lon or not lat then
        url = "https://api-adresse.data.gouv.fr/search/?q=" .. urlencode(city_query) .. "&limit=1"
        json = query_url(url)
        if not json then return nil, nil end
        lon, lat = json:match('"coordinates"%s*:%s*%[%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*%]')
        label = json:match('"city"%s*:%s*"([^"]+)"') or json:match('"label"%s*:%s*"([^"]+)"')
        postcode = json:match('"postcode"%s*:%s*"([^"]+)"')
    end

    if lon and lat then
        local clean_name = decode_json_str(label or city_query)
        if postcode and not clean_name:find(postcode, 1, true) then
            clean_name = clean_name .. " (" .. string.sub(postcode, 1, 2) .. ")"
        end
        return lon .. "," .. lat, clean_name
    end
    return nil, nil
end

-- =====================================================================
-- 2. TRADUCTEUR DE MANOEUVRES OSRM EN FRANCAIS
-- =====================================================================
local MOD_FR = {
    ["left"]         = "A GAUCHE",
    ["right"]        = "A DROITE",
    ["slight left"]  = "LEGER. A GAUCHE",
    ["slight right"] = "LEGER. A DROITE",
    ["sharp left"]   = "FRANCH. A GAUCHE",
    ["sharp right"]  = "FRANCH. A DROITE",
    ["straight"]     = "TOUT DROIT",
    ["uturn"]        = "DEMI-TOUR"
}

local function build_french_instruction(m_type, m_mod, m_exit, name, ref, dest)
    local road = ""
    if ref ~= "" and name ~= "" and ref ~= name then
        road = ref .. " (" .. name .. ")"
    elseif ref ~= "" then
        road = ref
    elseif name ~= "" then
        road = name
    else
        road = "LA VOIE"
    end

    if dest ~= "" then
        -- On garde uniquement la 1ere ou 2e ville de destination pour que ce soit lisible
        local short_dest = dest:match("^([^,]+,[^,]+)") or dest:match("^([^,]+)") or dest
        road = road .. " [DIR. " .. short_dest .. "]"
    end

    local dir = MOD_FR[m_mod or ""] or ""

    if m_type == "depart" then
        return "DEPART SUR " .. road
    elseif m_type == "arrive" then
        return "ARRIVEE A DESTINATION"
    elseif m_type == "roundabout" or m_type == "rotary" or m_type == "roundabout turn" then
        local ex = m_exit and (" (SORTIE " .. m_exit .. ")") or ""
        return "ROND-POINT" .. ex .. " -> " .. road
    elseif m_type == "exit roundabout" or m_type == "exit rotary" then
        return "SORTIE ROND-POINT -> " .. road
    elseif m_type == "fork" then
        return "BIFURQUER " .. (dir ~= "" and dir or "") .. " -> " .. road
    elseif m_type == "on ramp" or m_type == "off ramp" then
        return "BRETELLE " .. (dir ~= "" and dir or "") .. " -> " .. road
    elseif m_type == "merge" then
        return "REJOINDRE " .. road
    elseif m_type == "end of road" then
        return "FIN DE ROUTE, " .. (dir ~= "" and dir or "CONTINUER") .. " SUR " .. road
    elseif m_type == "new name" or m_type == "continue" then
        return "CONTINUER SUR " .. road
    else
        if dir ~= "" then
            return "TOURNER " .. dir .. " SUR " .. road
        else
            return "SUIVRE " .. road
        end
    end
end

-- =====================================================================
-- 3. CALCUL DE L'ITINERAIRE PAR OSRM (AVEC PURGE DES POLYLINE GEOMETRY)
-- =====================================================================
local function get_route(city_start, city_end)
    minitel.draw_window(15, 9, 52, 5, "CALCUL SATELLITE EN COURS")
    io.write("\x1b[11;17H" .. minitel.center("GEOLOCALISATION DES VILLES...", 48))
    io.flush()
    minitel.play_sound("hit")

    local coord1, real_a = get_city_coords(city_start)
    if not coord1 then return "VILLE DE DEPART INTROUVABLE : " .. city_start, nil end

    local coord2, real_b = get_city_coords(city_end)
    if not coord2 then return "VILLE D'ARRIVEE INTROUVABLE : " .. city_end, nil end

    io.write("\x1b[11;17H" .. minitel.center("CALCUL DE LA ROUTE OPTIMALE...", 48))
    io.flush()

    local url = "https://router.project-osrm.org/route/v1/driving/" .. coord1 .. ";" .. coord2 .. "?steps=true&overview=false"
    local json = query_url(url)
    if not json or json == "" then return "SERVEUR ROUTIER INJOIGNABLE", nil end

    if not json:find('"code"%s*:%s*"Ok"') then
        return "AUCUN ITINERAIRE ROUTIER TROUVE", nil
    end

    -- CRUCIAL : On supprime les chaines "geometry":"..." et "intersections":[...]
    -- car les polylines OSRM contiennent des caracteres '{' et '}' non apparies qui cassent %b{} !
    json = json:gsub('"geometry"%s*:%s*"[^"]*"%s*,?', "")
    json = json:gsub('"intersections"%s*:%s*%b[]%s*,?', "")

    local steps_array = json:match('"steps"%s*:%s*(%b[])')
    if not steps_array then return "ERREUR LECTURE FEUILLE DE ROUTE", nil end

    local raw_steps = {}
    local sum_dist = 0
    local sum_dur  = 0
    local inner = steps_array:sub(2, -2)

    for step_block in inner:gmatch("%b{}") do
        local dist = tonumber(step_block:match('"distance"%s*:%s*([%d%.]+)')) or 0
        local dur  = tonumber(step_block:match('"duration"%s*:%s*([%d%.]+)')) or 0
        local name = decode_json_str(step_block:match('"name"%s*:%s*"([^"]*)"') or "")
        local ref  = decode_json_str(step_block:match('"ref"%s*:%s*"([^"]*)"') or "")
        local dest = decode_json_str(step_block:match('"destinations"%s*:%s*"([^"]*)"') or "")

        local man_block = step_block:match('"maneuver"%s*:%s*(%b{})') or ""
        local m_type = man_block:match('"type"%s*:%s*"([^"]*)"') or "turn"
        local m_mod  = man_block:match('"modifier"%s*:%s*"([^"]*)"') or ""
        local m_exit = man_block:match('"exit"%s*:%s*(%d+)')

        sum_dist = sum_dist + dist
        sum_dur  = sum_dur + dur

        table.insert(raw_steps, {
            m_type = m_type,
            m_exit = m_exit,
            dist   = dist,
            dur    = dur,
            road_key = ref .. "|" .. name,
            text   = build_french_instruction(m_type, m_mod, m_exit, name, ref, dest)
        })
    end

    -- Fusion intelligente : regroupe l'entree et la sortie d'un meme rond-point ou les segments continus sur la meme route
    local steps = {}
    local i = 1
    while i <= #raw_steps do
        local cur = raw_steps[i]
        local nxt = raw_steps[i + 1]

        if (cur.m_type == "roundabout" or cur.m_type == "rotary") and nxt and (nxt.m_type == "exit roundabout" or nxt.m_type == "exit rotary") then
            -- On garde l'instruction de sortie (qui a le vrai nom de la route suivante) avec le numero de sortie du rond-point !
            local ex_str = cur.m_exit and (" (SORTIE " .. cur.m_exit .. ")") or ""
            local merged_text = nxt.text:gsub("^SORTIE ROND%-POINT", "ROND-POINT" .. ex_str)
            table.insert(steps, {
                distance = cur.dist + nxt.dist,
                duration = cur.dur + nxt.dur,
                instruction = merged_text
            })
            i = i + 2
        elseif cur.m_type ~= "depart" and cur.m_type ~= "arrive" and cur.dist < 25 and #steps > 0 then
            -- Ajoute les micro-segments (< 25m) a l'etape precedente
            steps[#steps].distance = steps[#steps].distance + cur.dist
            steps[#steps].duration = steps[#steps].duration + cur.dur
            i = i + 1
        else
            table.insert(steps, {
                distance = cur.dist,
                duration = cur.dur,
                instruction = cur.text
            })
            i = i + 1
        end
    end

    -- Calcul des distances cumulees pour la fiche detaillee
    local cum_d, cum_t = 0, 0
    for _, s in ipairs(steps) do
        s.cum_dist = cum_d
        s.cum_dur  = cum_t
        cum_d = cum_d + s.distance
        cum_t = cum_t + s.duration
    end

    local summary = {
        from = real_a,
        to   = real_b,
        dist = sum_dist,
        dur  = sum_dur
    }

    return summary, steps
end

-- =====================================================================
-- 4. AFFICHAGE DE LA FEUILLE DE ROUTE (DELTA-DRAWING 9600 BAUDS)
-- =====================================================================
local max_visible = 12

local function format_dist(meters)
    if meters >= 1000 then
        local km = meters / 1000
        if km >= 10 then
            return string.format("%4d KM", math.floor(km + 0.5))
        else
            return string.format("%4.1f KM", km)
        end
    elseif meters > 0 then
        return string.format("%4d M ", math.floor(meters + 0.5))
    else
        return "  FIN  "
    end
end

local function draw_step_row(steps, slot, offset, cursor)
    local idx = offset + slot
    local st = steps[idx]
    local y = 7 + slot

    if not st then
        io.write(string.format("\x1b[%d;3H%s", y, string.rep(" ", 76)))
        return
    end

    local d_str = format_dist(st.distance)
    local line = string.format(" %02d. [%s] %s", idx, d_str, minitel.pad(st.instruction, 58))

    if idx == cursor then
        io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 74)))
    else
        io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 74)))
    end
end

local function draw_scrollbar(total_items, cursor)
    if total_items > max_visible then
        local thumb = math.floor(((cursor - 1) / math.max(1, total_items - 1)) * (max_visible - 3)) + 2
        for i = 1, max_visible do
            local char = (i == 1 and "^") or (i == max_visible and "v") or (i == thumb and "\x1b[7m#\x1b[0m") or ":"
            io.write(string.format("\x1b[%d;78H%s", 7 + i, char))
        end
    end
end

local function draw_route_full(summary, steps, offset, cursor)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    local tot_km = math.max(1, math.floor((summary.dist / 1000) + 0.5))
    local tot_min = math.max(1, math.floor((summary.dur / 60) + 0.5))
    local h = math.floor(tot_min / 60)
    local m = tot_min % 60

    local top_title = string.format("3615 ITINERAIRE : %s -> %s", string.sub(summary.from, 1, 24), string.sub(summary.to, 1, 24))
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top_title, 80) .. "\x1b[0m")

    local win_title = string.format("DISTANCE : %d KM | DUREE : %02dH%02d | %d ETAPES", tot_km, h, m, #steps)
    minitel.draw_window(2, 3, 78, 19, win_title)

    io.write("\x1b[5;3H\x1b[7m  N.  | DIST.   | DIRECTION & VOIE A SUIVRE                                 \x1b[0m")
    io.write("\x1b[6;2H\x1b[1m+----------------------------------------------------------------------------+\x1b[0m")

    for slot = 1, max_visible do
        draw_step_row(steps, slot, offset, cursor)
    end
    draw_scrollbar(#steps, cursor)

    io.write("\x1b[24;1H\x1b[7m [Z/S] DEFILER | [ENVOI] DETAIL ETAPE | [N] NOUVEAU TRAJET | [RETOUR] QUITTER \x1b[0m")
    io.flush()
end

local function show_route_loop(summary, steps)
    local cursor = 1
    local offset = 0
    draw_route_full(summary, steps, offset, cursor)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return "QUIT"
            elseif k == "N" or k == "n" then
                return "NEW"
            elseif k == "REPETITION" then
                draw_route_full(summary, steps, offset, cursor)
            elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s" then
                local is_up = (k == "UP" or k == "Z" or k == "z")
                local old_c, old_off = cursor, offset

                if is_up then
                    if cursor > 1 then
                        cursor = cursor - 1
                        if cursor <= offset then offset = cursor - 1 end
                    else
                        cursor = #steps
                        offset = math.max(0, #steps - max_visible)
                    end
                else
                    if cursor < #steps then
                        cursor = cursor + 1
                        if cursor > offset + max_visible then offset = cursor - max_visible end
                    else
                        cursor = 1
                        offset = 0
                    end
                end

                if offset ~= old_off then
                    for s = 1, max_visible do draw_step_row(steps, s, offset, cursor) end
                else
                    draw_step_row(steps, old_c - offset, offset, cursor)
                    draw_step_row(steps, cursor - offset, offset, cursor)
                end
                draw_scrollbar(#steps, cursor)
                io.flush()

            elseif k == "ENVOI" or k == "\r" or k == "\n" or k == " " then
                local st = steps[cursor]
                if st then
                    local km_done = math.floor((st.cum_dist / 1000) + 0.5)
                    local min_done = math.floor((st.cum_dur / 60) + 0.5)
                    local msg = string.format("%s — Suivre sur %s (Cumul: %d km / %d min)",
                        st.instruction, format_dist(st.distance), km_done, min_done)
                    minitel.msg_box(string.format("ETAPE %02d / %02d", cursor, #steps), msg, "pickup")
                    draw_route_full(summary, steps, offset, cursor)
                end
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
local last_start = "JOINVILLE"
local last_end   = "REIMS"

while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 ITINERAIRE - MAPPY TELEMATIQUE  * * *", 80) .. "\x1b[0m")
    io.flush()

    local depart = minitel.input_box("VILLE DE DEPART", "Commune de depart (ex: JOINVILLE, RUPT) :", last_start, 30)
    if not depart or depart == "" then break end
    last_start = decode_json_str(depart)

    local arrivee = minitel.input_box("VILLE D'ARRIVEE", "Destination (ex: REIMS, CHAUMONT, PARIS) :", last_end, 30)
    if arrivee and arrivee ~= "" then
        last_end = decode_json_str(arrivee)
        local summary, steps = get_route(last_start, last_end)

        if not steps then
            minitel.msg_box("ERREUR ITINERAIRE", tostring(summary), "lose")
        else
            minitel.play_sound("win")
            local act = show_route_loop(summary, steps)
            if act == "QUIT" then
                break
            end
        end
    end
end

minitel.cleanup()