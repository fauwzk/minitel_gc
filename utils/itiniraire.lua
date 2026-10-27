-- Fichier : utils/itiniraire.lua
-- 3615 ITINERAIRE : calcul d'un trajet routier, carte du trace, feuille de
-- route et guidage etape par etape, facon Mappy telematique.
-- Donnees : api-adresse.data.gouv.fr (communes) et OSRM (routes), sans cle.
-- @TYPE: TELEMATIQUE / AUTO
-- @DESC: Carte du trajet, feuille de route detaillee (km, duree, directions), heure d'arrivee, consommation et guidage etape par etape.
-- @ART1:      A *
-- @ART2:         *  *   .-------.
-- @ART3:              * | 152KM |
-- @ART4:             *  '-------'
-- @ART5:            B   [ MAPPY ]

local minitel = require("minitel")
minitel.init()

local CFG_FILE = "utils/itiniraire.cfg"  -- dernier trajet (conserve par la mise a jour)
local CONSO = 6.5                         -- litres aux 100 km, pour l'estimation

-- Carte : cadre colonnes 1-34, lignes 4-19 ; liste des etapes a droite
local MAP_X, MAP_Y, MAP_W, MAP_H = 2, 5, 32, 14
local LIST_X, LIST_Y, LIST_W, LIST_ROWS = 37, 5, 43, 14

-- =====================================================================
-- RESEAU ET TEXTE
-- =====================================================================
local function url_encode(s)
    s = string.gsub(tostring(s or ""), "^%s+", ""):gsub("%s+$", "")
    return (string.gsub(s, "[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function http_json(url)
    local p = io.popen(string.format('curl -sL -m 15 -A "MinitelMagisClub/1.0" %q 2>/dev/null', url))
    if not p then return nil end
    local body = p:read("*a")
    p:close()
    return minitel.json_decode(body)
end

local function up(s)
    return (string.gsub(string.upper(minitel.clean_accents(tostring(s or ""))), "[^\32-\126]", ""))
end

local function format_dist(m)
    if m >= 10000 then return string.format("%d KM", math.floor(m / 1000 + 0.5)) end
    if m >= 1000 then return (string.format("%.1f KM", m / 1000):gsub("%.", ",")) end
    if m > 0 then return string.format("%d M", math.floor(m / 10 + 0.5) * 10) end
    return ""
end

local function format_dur(s)
    local mn = math.max(1, math.floor(s / 60 + 0.5))
    if mn < 60 then return mn .. " MN" end
    return string.format("%dH%02d", math.floor(mn / 60), mn % 60)
end

local function wait_box(text)
    minitel.draw_window(18, 10, 46, 5, "3615 ITINERAIRE")
    io.write("\x1b[12;20H" .. minitel.center(text, 42))
    io.flush()
end

-- =====================================================================
-- DERNIER TRAJET (utils/itiniraire.cfg)
-- =====================================================================
local last = { from = "JOINVILLE", to = "REIMS" }

local function load_last()
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = string.match(line, "^(%w+)=(.+)$")
        if k == "depart" then last.from = v elseif k == "arrivee" then last.to = v end
    end
    f:close()
end

local function save_last()
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    f:write("depart=" .. last.from .. "\narrivee=" .. last.to .. "\n")
    f:close()
end

-- =====================================================================
-- 1. COMMUNES (API ADRESSE DU GOUVERNEMENT)
-- =====================================================================
-- Rend { lon, lat, name } ou nil
local function geocode(q)
    for _, extra in ipairs({ "&type=municipality", "" }) do
        local data = http_json("https://api-adresse.data.gouv.fr/search/?limit=1&q=" .. url_encode(q) .. extra)
        local f = data and data.features and data.features[1]
        if f and f.geometry and f.geometry.coordinates then
            local p = f.properties or {}
            local name = up(p.city or p.name or q)
            if p.postcode then name = name .. " (" .. string.sub(p.postcode, 1, 2) .. ")" end
            return { lon = f.geometry.coordinates[1], lat = f.geometry.coordinates[2], name = name }
        end
        if not data then return nil, "SERVEUR DES ADRESSES INJOIGNABLE" end
    end
    return nil, "COMMUNE INTROUVABLE : " .. up(q)
end

-- =====================================================================
-- 2. ROUTE (OSRM) ET INSTRUCTIONS EN FRANCAIS
-- =====================================================================
local MOD_FR = {
    ["left"] = "A GAUCHE", ["right"] = "A DROITE",
    ["slight left"] = "LEGEREMENT A GAUCHE", ["slight right"] = "LEGEREMENT A DROITE",
    ["sharp left"] = "FRANCHEMENT A GAUCHE", ["sharp right"] = "FRANCHEMENT A DROITE",
    ["straight"] = "TOUT DROIT", ["uturn"] = "DEMI-TOUR",
}

local function instruction(m_type, mod, exit_n, road, dest)
    if road == "" then road = "LA ROUTE" end
    if dest ~= "" then
        local short = dest:match("^([^,]+,[^,]+)") or dest:match("^([^,]+)") or dest
        road = road .. " DIRECTION " .. short
    end
    local dir = MOD_FR[mod] or ""
    if m_type == "depart" then return "PARTEZ PAR " .. road
    elseif m_type == "arrive" then return "VOUS ETES ARRIVE A DESTINATION"
    elseif m_type == "roundabout" or m_type == "rotary" or m_type == "roundabout turn" then
        return "AU ROND-POINT" .. (exit_n and (", PRENEZ LA SORTIE " .. exit_n) or "") .. " VERS " .. road
    elseif m_type == "exit roundabout" or m_type == "exit rotary" then return "SORTEZ DU ROND-POINT VERS " .. road
    elseif m_type == "fork" then return "A L'EMBRANCHEMENT, GARDEZ " .. (dir ~= "" and dir or "LA FILE") .. " VERS " .. road
    elseif m_type == "on ramp" then return "PRENEZ LA BRETELLE " .. dir .. " VERS " .. road
    elseif m_type == "off ramp" then return "PRENEZ LA SORTIE " .. dir .. " VERS " .. road
    elseif m_type == "merge" then return "INSEREZ-VOUS SUR " .. road
    elseif m_type == "end of road" then return "AU BOUT DE LA ROUTE, TOURNEZ " .. dir .. " SUR " .. road
    elseif m_type == "new name" or m_type == "continue" then return "CONTINUEZ SUR " .. road
    elseif dir == "TOUT DROIT" then return "CONTINUEZ TOUT DROIT SUR " .. road
    elseif dir ~= "" then return "TOURNEZ " .. dir .. " SUR " .. road
    end
    return "SUIVEZ " .. road
end

-- Pictogramme de 3 caracteres pour la feuille de route
local function picto(m_type, mod)
    if m_type == "depart" then return "[A]" end
    if m_type == "arrive" then return "[B]" end
    if m_type == "roundabout" or m_type == "rotary" or m_type == "roundabout turn" then return "(O)" end
    if mod == "uturn" then return " U " end
    if mod == "sharp left" then return "<<-" end
    if mod == "sharp right" then return "->>" end
    if mod == "left" then return "<- " end
    if mod == "right" then return " ->" end
    if mod == "slight left" then return "<^ " end
    if mod == "slight right" then return " ^>" end
    return " ^ "
end

-- Rend summary, steps, points (trace) ou nil, message d'erreur
local function compute(from_q, to_q)
    wait_box("RECHERCHE DES COMMUNES...")
    local a, err = geocode(from_q)
    if not a then return nil, err end
    local b
    b, err = geocode(to_q)
    if not b then return nil, err end

    wait_box("CALCUL DE LA ROUTE...")
    minitel.play_sound("hit")
    local url = string.format("https://router.project-osrm.org/route/v1/driving/%s,%s;%s,%s?steps=true&overview=simplified&geometries=geojson",
        a.lon, a.lat, b.lon, b.lat)
    local data = http_json(url)
    if not data then return nil, "SERVEUR ROUTIER INJOIGNABLE" end
    local route = data.routes and data.routes[1]
    if data.code ~= "Ok" or not route then return nil, "AUCUNE ROUTE ENTRE CES DEUX COMMUNES" end

    local raw = {}
    for _, leg in ipairs(route.legs or {}) do
        for _, s in ipairs(leg.steps or {}) do
            local m = s.maneuver or {}
            local ref, name = up(s.ref), up(s.name)
            local road = (ref ~= "" and name ~= "" and ref ~= name) and (ref .. " (" .. name .. ")") or (ref ~= "" and ref or name)
            raw[#raw + 1] = {
                m_type = m.type or "turn", mod = m.modifier or "", exit_n = m.exit,
                loc = m.location, dist = s.distance or 0, dur = s.duration or 0,
                text = instruction(m.type or "turn", m.modifier or "", m.exit, road, up(s.destinations)),
                picto = picto(m.type or "turn", m.modifier or ""),
            }
        end
    end

    -- Regroupe l'entree et la sortie d'un rond-point, et les petits troncons
    local steps, i = {}, 1
    while i <= #raw do
        local cur, nxt = raw[i], raw[i + 1]
        if (cur.m_type == "roundabout" or cur.m_type == "rotary") and nxt
            and (nxt.m_type == "exit roundabout" or nxt.m_type == "exit rotary") then
            cur.dist, cur.dur = cur.dist + nxt.dist, cur.dur + nxt.dur
            steps[#steps + 1] = cur
            i = i + 2
        elseif cur.m_type ~= "depart" and cur.m_type ~= "arrive" and cur.dist < 25 and #steps > 0 then
            steps[#steps].dist = steps[#steps].dist + cur.dist
            steps[#steps].dur = steps[#steps].dur + cur.dur
            i = i + 1
        else
            steps[#steps + 1] = cur
            i = i + 1
        end
    end
    local cd, ct = 0, 0
    for _, s in ipairs(steps) do
        s.cum_dist, s.cum_dur = cd, ct
        cd, ct = cd + s.dist, ct + s.dur
    end

    local points = (route.geometry and route.geometry.coordinates) or {}
    local summary = { from = a.name, to = b.name, dist = route.distance or cd, dur = route.duration or ct }
    return summary, steps, points
end

-- =====================================================================
-- 3. CARTE DU TRACE
-- =====================================================================
-- Projette les points dans la grille de la carte. Une case du Minitel est
-- environ deux fois plus haute que large : une ligne vaut deux colonnes.
local function make_projection(points)
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    local lat0 = 0
    for _, p in ipairs(points) do lat0 = lat0 + p[2] end
    lat0 = math.rad(lat0 / math.max(1, #points))
    local k = math.cos(lat0)
    for _, p in ipairs(points) do
        local x, y = p[1] * k, p[2]
        minx, maxx = math.min(minx, x), math.max(maxx, x)
        miny, maxy = math.min(miny, y), math.max(maxy, y)
    end
    local dx, dy = math.max(maxx - minx, 1e-6), math.max(maxy - miny, 1e-6)
    local scale = math.min((MAP_W - 1) / dx, 2 * (MAP_H - 1) / dy)
    local ox = (MAP_W - 1 - dx * scale) / 2
    local oy = (MAP_H - 1 - dy * scale / 2) / 2
    return function(lon, lat)
        local col = math.floor(ox + (lon * k - minx) * scale + 0.5)
        local row = math.floor(oy + (maxy - lat) * scale / 2 + 0.5)
        return math.max(0, math.min(MAP_W - 1, col)), math.max(0, math.min(MAP_H - 1, row))
    end
end

-- Grille de la carte : trace en points, A et B aux extremites
local function build_map(points, project)
    local grid = {}
    for r = 0, MAP_H - 1 do
        grid[r] = {}
        for c = 0, MAP_W - 1 do grid[r][c] = " " end
    end
    local px, py
    for _, p in ipairs(points) do
        local x, y = project(p[1], p[2])
        if px then
            local steps = math.max(math.abs(x - px), math.abs(y - py), 1)
            for s = 0, steps do
                local cx = math.floor(px + (x - px) * s / steps + 0.5)
                local cy = math.floor(py + (y - py) * s / steps + 0.5)
                grid[cy][cx] = "*"
            end
        end
        px, py = x, y
    end
    if #points > 0 then
        local ax, ay = project(points[1][1], points[1][2])
        local bx, by = project(points[#points][1], points[#points][2])
        grid[ay][ax], grid[by][bx] = "A", "B"
    end
    return grid
end

-- =====================================================================
-- 4. GUIDAGE ETAPE PAR ETAPE (GRANDES FLECHES)
-- =====================================================================
local ARROWS = {
    straight = {
        "       /\\       ", "      /  \\      ", "     /_  _\\     ", "       ||       ",
        "       ||       ", "       ||       ", "       ||       " },
    right = {
        "         \\      ", "   ______ \\     ", "  |______  >    ", "  |       /     ",
        "  |      /      ", "  |             ", "  |             " },
    slight = {
        "       ______   ", "       \\     |  ", "        \\    |  ", "       / \\   |  ",
        "      /   \\  |  ", "     /     \\ |  ", "    /           " },
    uturn = {
        "     ______     ", "    /      \\    ", "   |        |   ", "   |        |   ",
        "  \\|/       |   ", "   V        |   ", "            |   " },
    roundabout = {
        "      .--.      ", "    /      \\    ", "   |   ()   |-->", "    \\      /    ",
        "      '--'      ", "       ||       ", "       ||       " },
    depart = {
        "    |>>>>>>>    ", "    |>>>>>>>    ", "    |           ", "    |           ",
        "    |           ", "   _|_          ", "                " },
    arrive = {
        "    |#_#_#_#    ", "    |_#_#_#_    ", "    |#_#_#_#    ", "    |           ",
        "    |           ", "   _|_          ", "                " },
}

local function mirror(lines)
    local out = {}
    local swap = { ["/"] = "\\", ["\\"] = "/", ["<"] = ">", [">"] = "<", ["("] = ")", [")"] = "(" }
    for i, l in ipairs(lines) do
        out[i] = (string.gsub(string.reverse(l), "[/\\<>()]", swap))
    end
    return out
end

local function arrow_for(st)
    if st.m_type == "depart" then return ARROWS.depart end
    if st.m_type == "arrive" then return ARROWS.arrive end
    if st.picto == "(O)" then return ARROWS.roundabout end
    local m = st.mod
    if m == "uturn" then return ARROWS.uturn end
    if m == "right" or m == "sharp right" then return ARROWS.right end
    if m == "left" or m == "sharp left" then return mirror(ARROWS.right) end
    if m == "slight right" then return ARROWS.slight end
    if m == "slight left" then return mirror(ARROWS.slight) end
    return ARROWS.straight
end

local function guidance(summary, steps, idx)
    local function draw()
        local st = steps[idx]
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar(string.format("3615 ITINERAIRE  -  GUIDAGE  %d / %d", idx, #steps))
        minitel.draw_frame(3, 4, 22, 11, "")
        for i, l in ipairs(arrow_for(st)) do
            io.write(string.format("\x1b[%d;6H%s", 5 + i, l))
        end
        local prev = steps[idx - 1]
        local lead = (prev and prev.dist > 0) and ("DANS " .. format_dist(prev.dist)) or "MAINTENANT"
        if st.m_type == "depart" then lead = "AU DEPART" end
        io.write(string.format("\x1b[5;29H\x1b[1m%s\x1b[0m", lead))
        local lines = minitel.wrap(st.text, 50, 4)
        for i = 1, 4 do io.write(string.format("\x1b[%d;29H%s", 6 + i, lines[i] or "")) end
        if st.dist > 0 then
            io.write(string.format("\x1b[12;29HPUIS SUIVEZ CETTE ROUTE SUR %s", format_dist(st.dist)))
        end
        local nxt = steps[idx + 1]
        if nxt then
            io.write("\x1b[16;3H\x1b[1mENSUITE :\x1b[0m")
            local nl = minitel.wrap(nxt.text, 64, 2)
            io.write(string.format("\x1b[16;13H%s\x1b[17;13H%s", nl[1] or "", nl[2] or ""))
        end
        local done = st.cum_dist
        io.write(string.format("\x1b[19;3HPARCOURU %s SUR %s   RESTE %s", format_dist(done) ~= "" and format_dist(done) or "0 KM",
            format_dist(summary.dist), format_dur(math.max(60, summary.dur - st.cum_dur))))
        minitel.progress_bar(3, 20, 76, done, math.max(1, summary.dist), true)
        minitel.footer("SUITE / BAS : ETAPE SUIVANTE    HAUT : PRECEDENTE    ENVOI : FEUILLE DE ROUTE")
        io.flush()
    end
    draw()
    while true do
        local k = minitel.get_key()
        if k then
            local old = idx
            if k == "SUITE" or k == "DOWN" or k == "RIGHT" or k == " " then idx = math.min(#steps, idx + 1)
            elseif k == "UP" or k == "LEFT" then idx = math.max(1, idx - 1)
            elseif k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return idx
            elseif k == "REPETITION" then draw()
            end
            if idx ~= old then
                minitel.play_sound(idx == #steps and "win" or "pickup")
                draw()
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- 5. ECRAN DU TRAJET : CARTE, RESUME ET FEUILLE DE ROUTE
-- =====================================================================
-- Rend "NEW", "SWAP" ou "QUIT"
local function show_route(summary, steps, points)
    local project = make_projection(points)
    local grid = build_map(points, project)
    local cursor, offset = 1, 0
    local marker -- case de la carte ou est dessine le X de l'etape choisie

    local function map_cell(c, r, ch)
        io.write(string.format("\x1b[%d;%dH%s", MAP_Y + r, MAP_X + c, ch))
    end

    local function draw_marker()
        local st = steps[cursor]
        if marker then
            local ch = grid[marker[2]][marker[1]]
            map_cell(marker[1], marker[2], ch)
        end
        if st and st.loc then
            local c, r = project(st.loc[1], st.loc[2])
            marker = { c, r }
            map_cell(c, r, "\x1b[7mX\x1b[0m")
        end
    end

    local function step_row(slot)
        local i = offset + slot
        local st = steps[i]
        local y = LIST_Y + slot - 1
        if not st then
            io.write(string.format("\x1b[%d;%dH%s", y, LIST_X, string.rep(" ", LIST_W)))
            return
        end
        local text = string.format("%2d %s %7s %s", i, st.picto, format_dist(st.dist), st.text)
        text = minitel.pad(text, LIST_W)
        if i == cursor then
            io.write(string.format("\x1b[%d;%dH\x1b[7m%s\x1b[0m", y, LIST_X, text))
        else
            io.write(string.format("\x1b[%d;%dH%s", y, LIST_X, text))
        end
    end

    local function draw_detail()
        local st = steps[cursor]
        local lines = minitel.wrap(st.text, 76, 2)
        io.write(string.format("\x1b[21;3H%s\x1b[22;3H%s", minitel.pad(lines[1] or "", 76), minitel.pad(lines[2] or "", 76)))
        local at = string.format("ETAPE %d/%d  -  KM %d  -  %s DE ROUTE", cursor, #steps,
            math.floor(st.cum_dist / 1000 + 0.5), format_dur(math.max(60, st.cum_dur)))
        io.write(string.format("\x1b[20;%dH\x1b[1m%s\x1b[0m", LIST_X, minitel.pad(at, LIST_W)))
    end

    local function draw_all()
        marker = nil
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 ITINERAIRE  -  " .. string.sub(summary.from, 1, 24) .. " > " .. string.sub(summary.to, 1, 24))
        local km = summary.dist / 1000
        io.write(string.format("\x1b[2;3H\x1b[1m%s\x1b[0m  EN  \x1b[1m%s\x1b[0m   ARRIVEE VERS %s SI VOUS PARTEZ MAINTENANT",
            format_dist(summary.dist), format_dur(summary.dur), os.date("%H:%M", os.time() + math.floor(summary.dur))))
        local pauses = math.floor(summary.dur / 7200)
        io.write(string.format("\x1b[3;3HCARBURANT ~ %s L (%s L/100 KM)   PAUSE%s CONSEILLEE%s : %d",
            (string.format("%.1f", km * CONSO / 100):gsub("%.", ",")), (tostring(CONSO):gsub("%.", ",")),
            pauses > 1 and "S" or "", pauses > 1 and "S" or "", pauses))
        minitel.draw_frame(MAP_X - 1, MAP_Y - 1, MAP_W + 2, MAP_H + 2, "CARTE")
        for r = 0, MAP_H - 1 do
            local line = table.concat(grid[r], "", 0, MAP_W - 1)
            if r == 0 then line = string.sub(line, 1, MAP_W - 2) .. "^N" end
            if not line:match("^%s*$") then
                io.write(string.format("\x1b[%d;%dH%s", MAP_Y + r, MAP_X, line))
            end
        end
        io.write(string.format("\x1b[%d;%dH\x1b[7m%s\x1b[0m", LIST_Y - 1, LIST_X, minitel.pad(" N DIR   DIST. FEUILLE DE ROUTE", LIST_W)))
        for slot = 1, LIST_ROWS do step_row(slot) end
        draw_detail()
        draw_marker()
        minitel.footer("HAUT/BAS:ETAPE  ENVOI:GUIDAGE  I:INVERSER  N:NOUVEAU TRAJET  RETOUR:FIN")
        io.flush()
    end

    draw_all()
    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return "QUIT"
            elseif k == "N" or k == "n" then return "NEW"
            elseif k == "I" or k == "i" then return "SWAP"
            elseif k == "REPETITION" then draw_all()
            elseif k == "ENVOI" or k == " " then
                cursor = guidance(summary, steps, cursor)
                if cursor <= offset then offset = cursor - 1 end
                if cursor > offset + LIST_ROWS then offset = cursor - LIST_ROWS end
                draw_all()
            elseif k == "UP" or k == "DOWN" or k == "SUITE" then
                local old_c, old_off = cursor, offset
                if k == "UP" then cursor = math.max(1, cursor - 1)
                elseif k == "DOWN" then cursor = math.min(#steps, cursor + 1)
                else cursor = math.min(#steps, cursor + LIST_ROWS) end
                if cursor <= offset then offset = cursor - 1 end
                if cursor > offset + LIST_ROWS then offset = cursor - LIST_ROWS end
                if cursor ~= old_c then
                    if offset ~= old_off then
                        for slot = 1, LIST_ROWS do step_row(slot) end
                    else
                        step_row(old_c - offset)
                        step_row(cursor - offset)
                    end
                    draw_detail()
                    draw_marker()
                    io.flush()
                end
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- ACCUEIL ET BOUCLE PRINCIPALE
-- =====================================================================
local ROAD = {
    [[                 .-------------------.          ]],
    [[      A *        |  3615 ITINERAIRE  |          ]],
    [[         *  *    |  LA ROUTE PAR LE  |    *  B  ]],
    [[               * |  MINITEL          | *        ]],
    [[                *'-------------------'*         ]],
    [[                  *  *  *  *  *  *  *           ]],
}

local function home()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 ITINERAIRE  -  LA ROUTE PAR LE MINITEL")
    for i, l in ipairs(ROAD) do io.write(string.format("\x1b[%d;15H%s", 3 + i, l)) end
    io.write(string.format("\x1b[11;15HDERNIER TRAJET : \x1b[1m%s\x1b[0m  >  \x1b[1m%s\x1b[0m", last.from, last.to))
    io.write("\x1b[13;15H\x1b[7m ENVOI \x1b[0m  NOUVEAU TRAJET")
    io.write("\x1b[14;15H\x1b[7m   R   \x1b[0m  REFAIRE LE DERNIER TRAJET")
    io.write("\x1b[15;15H\x1b[7m   I   \x1b[0m  LE DERNIER TRAJET A L'ENVERS")
    io.write("\x1b[18;15HCommunes : api-adresse.data.gouv.fr   Routes : OSRM")
    minitel.footer("ENVOI : NOUVEAU TRAJET    R : REFAIRE    I : INVERSER    RETOUR : QUITTER")
    io.flush()
end

-- Calcule et affiche un trajet ; rend l'action suivante
local function run(from_q, to_q)
    local summary, steps, points = compute(from_q, to_q)
    if not summary then
        minitel.msg_box("ITINERAIRE", tostring(steps), "lose")
        return nil
    end
    last.from, last.to = from_q, to_q
    save_last()
    minitel.play_sound("win")
    return show_route(summary, steps, points)
end

load_last()
home()
while true do
    local k = minitel.get_key()
    if k then
        local action
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "ENVOI" or k == " " then action = "NEW"
        elseif k == "R" or k == "r" then action = "AGAIN"
        elseif k == "I" or k == "i" then action = "SWAP"
        end
        local redraw = action ~= nil or k == "REPETITION"
        while action do
            local from_q, to_q = last.from, last.to
            if action == "NEW" then
                from_q = minitel.input_box("VILLE DE DEPART", "Commune de depart (ex : JOINVILLE, RUPT) :", last.from, 30)
                if from_q and not from_q:match("^%s*$") then
                    to_q = minitel.input_box("VILLE D'ARRIVEE", "Destination (ex : REIMS, CHAUMONT) :", last.to, 30)
                end
                if not to_q or to_q:match("^%s*$") or not from_q or from_q:match("^%s*$") then from_q = nil end
            elseif action == "SWAP" then
                from_q, to_q = last.to, last.from
            end
            if from_q then
                from_q, to_q = up(from_q), up(to_q)
                action = run(from_q, to_q)
                if action == "QUIT" then action = nil end
            else
                action = nil
            end
        end
        if redraw then home() end
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
