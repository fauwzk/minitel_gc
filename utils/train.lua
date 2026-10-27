-- Fichier : utils/train.lua
-- 3615 TRAIN : tableau des departs d'une gare facon panneau a palettes,
-- desserte de chaque train et recherche de trajet avec correspondances.
-- Donnees : transport.opendata.ch (horaires SNCF et europeens, sans cle).
-- @TYPE: TELEMATIQUE / RESEAU
-- @DESC: Tableau des departs en direct avec horloge, retards et voies, desserte de chaque train, et trajets d'une gare a une autre avec correspondances.
-- @ART1:    ____________________
-- @ART2:   | 18:16 TER  DIJON   |
-- @ART3:   | 18:35 TGV  PARIS   |
-- @ART4:   |__ooo______ooo______|
-- @ART5:   ====[ 3615 TRAIN ]====

local minitel = require("minitel")
minitel.init()

local API = "http://transport.opendata.ch/v1/"
local CFG_FILE = "utils/train.cfg"   -- gares recentes (conservees par la mise a jour)
local MAX_RECENT = 6
local BOARD_TOP, BOARD_ROWS = 5, 13  -- lignes 5 a 17 du tableau
local REFRESH = 60                   -- actualisation du tableau (secondes)

-- =====================================================================
-- RESEAU ET TEXTE
-- =====================================================================
local function url_encode(s)
    return (string.gsub(s, "[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function fetch(path)
    local p = io.popen(string.format("curl -s -m 15 %q 2>/dev/null", API .. path))
    if not p then return nil end
    local body = p:read("*a")
    p:close()
    return minitel.json_decode(body)
end

-- Texte de l'API -> majuscules ASCII du Minitel
local function up(s)
    return (string.gsub(string.upper(minitel.clean_accents(tostring(s or ""))), "[^\32-\126]", ""))
end

local function hhmm(ts)
    return ts and os.date("%H:%M", ts) or "--:--"
end

-- Duree "00d04:35:00" -> "4H35"
local function duration(d)
    local days, h, m = string.match(d or "", "(%d+)d(%d+):(%d+)")
    if not days then return "?" end
    h = tonumber(days) * 24 + tonumber(h)
    return string.format("%dH%02d", h, tonumber(m))
end

-- "TER" "K4" -> "TER K4" ; les autocars (categorie B) deviennent "CAR"
local function train_label(cat, num)
    cat = up(cat)
    if cat == "B" or cat == "BUS" then cat = "CAR" end
    num = up(num)
    if num ~= "" and num ~= cat then return cat .. " " .. num end
    return cat ~= "" and cat or "TRAIN"
end

local function wait_box(text)
    minitel.draw_window(20, 10, 42, 5, "3615 TRAIN")
    io.write("\x1b[12;22H" .. minitel.center(text, 38))
    io.flush()
end

-- =====================================================================
-- GARES RECENTES (utils/train.cfg : une gare par ligne, "NOM|id")
-- =====================================================================
local recent = {}

local function load_recent()
    recent = {}
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local name, id = string.match(line, "^([^|]+)|(%w+)$")
        if name and #recent < MAX_RECENT then recent[#recent + 1] = { name = name, id = id } end
    end
    f:close()
end

local function remember(st)
    for i = #recent, 1, -1 do
        if recent[i].id == st.id then table.remove(recent, i) end
    end
    table.insert(recent, 1, { name = st.name, id = st.id })
    while #recent > MAX_RECENT do table.remove(recent) end
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    for _, r in ipairs(recent) do f:write(r.name .. "|" .. r.id .. "\n") end
    f:close()
end

-- =====================================================================
-- CHOIX D'UNE GARE (SAISIE PUIS SUGGESTIONS DU SERVEUR)
-- =====================================================================
-- Liste a choisir dans une fenetre : fleches + ENVOI, ou chiffre 1-9.
-- Rend l'element choisi, ou nil (RETOUR).
local function pick(title, items, label)
    local n = math.min(#items, 9)
    local x, y, w = 16, 6, 50
    minitel.draw_window(x, y, w, n + 5, title)
    io.write(string.format("\x1b[%d;%dH%s", y + n + 3, x + 2, minitel.pad("FLECHES + ENVOI, OU 1 A " .. n .. "    RETOUR : ANNULER", w - 4)))
    local sel = 1
    local function row(i)
        local txt = minitel.pad(i .. "  " .. label(items[i]), w - 6)
        if i == sel then
            io.write(string.format("\x1b[%d;%dH\x1b[7m %s \x1b[0m", y + 1 + i, x + 2, txt))
        else
            io.write(string.format("\x1b[%d;%dH %s ", y + 1 + i, x + 2, txt))
        end
    end
    for i = 1, n do row(i) end
    io.flush()
    while true do
        local k = minitel.get_key()
        if k then
            local old = sel
            if k == "UP" then sel = sel > 1 and sel - 1 or n
            elseif k == "DOWN" then sel = sel < n and sel + 1 or 1
            elseif k == "ENVOI" or k == " " then return items[sel]
            elseif k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return nil
            elseif tonumber(k) and tonumber(k) >= 1 and tonumber(k) <= n then return items[tonumber(k)]
            end
            if sel ~= old then row(old); row(sel); io.flush() end
        end
        minitel.sleep(0.02)
    end
end

-- Rend { name, id } ou nil
local function ask_station(title, default)
    local q = minitel.input_box(title, "Nom de la gare (ex : CHAUMONT, PARIS EST) :", default or "", 30)
    if not q or q:match("^%s*$") then return nil end
    wait_box("RECHERCHE DE LA GARE...")
    local data = fetch("locations?type=station&query=" .. url_encode(q))
    if not data then
        minitel.msg_box("ERREUR RESEAU", "Le serveur des horaires ne repond pas. Verifiez la connexion.", "lose")
        return nil
    end
    local trains, others = {}, {}
    for _, s in ipairs(data.stations or {}) do
        if s.id and s.name then
            local st = { id = tostring(s.id), name = up(s.name) }
            if s.icon == "train" then trains[#trains + 1] = st else others[#others + 1] = st end
        end
    end
    local list = #trains > 0 and trains or others
    if #list == 0 then
        minitel.msg_box("GARE INCONNUE", "Aucune gare ne correspond a : " .. up(q), "lose")
        return nil
    end
    if #list == 1 or list[1].name == up(q) then return list[1] end
    return pick("QUELLE GARE ?", list, function(s) return s.name end)
end

-- =====================================================================
-- TABLEAU DES DEPARTS
-- =====================================================================
local function load_board(st)
    local data = fetch("stationboard?limit=20&id=" .. url_encode(st.id))
    if not data then return nil end
    local list = {}
    for _, t in ipairs(data.stationboard or {}) do
        local stop = t.stop or {}
        local ts = tonumber(stop.departureTimestamp)
        if ts then
            local prog = stop.prognosis or {}
            local stops = {}
            for i, p in ipairs(t.passList or {}) do
                local name = p.station and p.station.name
                if i == 1 then name = name or st.name end
                if name then
                    stops[#stops + 1] = {
                        name = up(name),
                        arr = tonumber(p.arrivalTimestamp),
                        dep = tonumber(p.departureTimestamp),
                    }
                end
            end
            list[#list + 1] = {
                ts = ts,
                label = train_label(t.category, t.number),
                number = up(t.name),
                operator = up(t.operator),
                dest = up(t.to),
                platform = up(prog.platform or stop.platform or ""),
                delay = tonumber(stop.delay),
                stops = stops,
            }
        end
    end
    return list
end

-- Colonne INFORMATION : retard, ou temps restant avant le depart
local function info_of(t, now)
    if t.delay and t.delay > 0 then
        return "RETARD " .. t.delay .. " MN", true
    end
    local mn = math.floor((t.ts - now) / 60)
    if mn <= 0 then return "A QUAI", false end
    if mn < 60 then return "DANS " .. mn .. " MN", false end
    return "A L'HEURE", false
end

local function board_row(t, now)
    local info, alert = info_of(t, now)
    local voie = t.platform ~= "" and t.platform or "--"
    local text = string.format(" %s  %s  %s  %s  ", hhmm(t.ts), minitel.pad(t.label, 9),
        minitel.pad(t.dest, 34), minitel.pad(voie, 4))
    return text, minitel.pad(info, 15), alert
end

-- Arrets suivants du train choisi, sur deux lignes
local function desserte_text(t)
    local parts = {}
    for i = 2, #t.stops do
        local s = t.stops[i]
        parts[#parts + 1] = s.name .. " " .. hhmm(s.arr or s.dep)
    end
    if #parts == 0 then return "DESSERTE : TERMINUS DIRECT " .. t.dest end
    return "DESSERTE : " .. table.concat(parts, " - ")
end

-- Fiche d'un train : toutes ses gares, en ligne du temps
local function show_train(t, station)
    local top, rows = 6, 15
    local offset = 0
    local function draw_list()
        for slot = 1, rows do
            local i = offset + slot
            local s = t.stops[i]
            local y = top + slot - 1
            if not s then
                io.write(string.format("\x1b[%d;1H\x1b[K", y))
            else
                local mark = (i == 1 or i == #t.stops) and "O" or "o"
                local arr = s.arr and hhmm(s.arr) or "     "
                local dep = s.dep and hhmm(s.dep) or "     "
                local name = minitel.pad(s.name, 40)
                if s.name == station.name then name = "\x1b[1m" .. name .. "\x1b[0m" end
                io.write(string.format("\x1b[%d;1H      %s   %s      %s   %s", y, arr, dep, mark, name))
            end
        end
        if #t.stops > rows then
            io.write(string.format("\x1b[21;3H%s", minitel.pad(string.format("GARES %d A %d SUR %d", offset + 1,
                math.min(#t.stops, offset + rows), #t.stops), 30)))
        end
        io.flush()
    end
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 TRAIN  -  DESSERTE DU TRAIN")
    local info = info_of(t, os.time())
    io.write(string.format("\x1b[3;3H\x1b[1m%s\x1b[0m  N. %s  %s   DEPART %s   VOIE %s   %s",
        t.label, t.number, t.operator, hhmm(t.ts), t.platform ~= "" and t.platform or "--", info))
    io.write(string.format("\x1b[4;3HDIRECTION \x1b[1m%s\x1b[0m", t.dest))
    io.write("\x1b[5;1H\x1b[7m" .. minitel.pad("      ARR.    DEP.     LIGNE GARE", 80) .. "\x1b[0m")
    minitel.footer("HAUT/BAS : DEFILER    RETOUR : TABLEAU DES DEPARTS")
    draw_list()
    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" or k == "ENVOI" or k == "SOMMAIRE" then return end
            local old = offset
            if (k == "DOWN" or k == "SUITE") and offset + rows < #t.stops then offset = math.min(#t.stops - rows, offset + (k == "SUITE" and rows or 1)) end
            if k == "UP" and offset > 0 then offset = offset - 1 end
            if k == "REPETITION" then return show_train(t, station) end
            if offset ~= old then draw_list() end
        end
        minitel.sleep(0.02)
    end
end

-- Effet du panneau a palettes : la ligne defile en lettres au hasard avant
-- de s'arreter sur la bonne
local function flap(y, text)
    local scrambled = string.gsub(text, "[%w]", function()
        return string.char(math.random(65, 90))
    end)
    io.write(string.format("\x1b[%d;1H%s", y, scrambled))
    io.flush()
    minitel.wait_output()
    minitel.sleep(0.03)
end

-- Rend "QUIT" (RETOUR) ou "TRAJET"
local function show_board(st)
    wait_box("INTERROGATION DE " .. string.sub(st.name, 1, 24))
    local trains = load_board(st)
    if not trains then
        minitel.msg_box("ERREUR RESEAU", "Le serveur des horaires ne repond pas.", "lose")
        return "QUIT"
    end
    remember(st)

    local cursor = 1
    local drawn = {}           -- ligne affichee par emplacement
    local last_clock, next_refresh = "", os.time() + REFRESH

    local function visible()
        local now = os.time()
        local list = {}
        for _, t in ipairs(trains) do
            -- un train parti depuis plus d'une minute quitte le tableau
            if t.ts + 60 * math.max(0, t.delay or 0) >= now - 60 then list[#list + 1] = t end
        end
        return list
    end

    local function draw_rows(animate)
        local list = visible()
        local now = os.time()
        if cursor > #list then cursor = math.max(1, #list) end
        for slot = 1, BOARD_ROWS do
            local t = list[slot]
            local y = BOARD_TOP + slot - 1
            local out
            if t then
                local text, info, alert = board_row(t, now)
                local attr = alert and "\x1b[1;5m" or ""
                if slot == cursor then
                    out = "\x1b[7m" .. text .. attr .. info .. "\x1b[0m"
                else
                    out = text .. attr .. info .. "\x1b[0m"
                end
                if animate then flap(y, text .. info) end
            else
                out = string.rep(" ", 79)
                if slot == 1 then out = minitel.center("AUCUN DEPART ANNONCE DANS CETTE GARE", 79) end
            end
            if drawn[slot] ~= out then
                io.write(string.format("\x1b[%d;1H%s", y, out))
                drawn[slot] = out
            end
        end
        -- desserte du train choisi
        local d = list[cursor] and desserte_text(list[cursor]) or ""
        local lines = minitel.wrap(d, 76, 2)
        local block = minitel.pad(lines[1] or "", 76) .. "|" .. minitel.pad(lines[2] or "", 76)
        if drawn.desserte ~= block then
            io.write(string.format("\x1b[19;3H%s\x1b[20;3H%s", minitel.pad(lines[1] or "", 76), minitel.pad(lines[2] or "", 76)))
            drawn.desserte = block
        end
        io.flush()
        return list
    end

    local function draw_all()
        drawn = {}
        last_clock = ""
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 TRAIN  -  TABLEAU DES DEPARTS")
        io.write(string.format("\x1b[2;3H\x1b[1mDEPARTS  %s\x1b[0m", string.sub(st.name, 1, 50)))
        io.write("\x1b[4;1H\x1b[7m" .. minitel.pad(" HEURE  TRAIN      DESTINATION                         VOIE  INFORMATION", 80) .. "\x1b[0m")
        io.write("\x1b[18;1H" .. string.rep("-", 80))
        minitel.footer("HAUT/BAS:TRAIN  ENVOI:DESSERTE  T:TRAJET  G:GARE  R:ACTUALISER  RETOUR:FIN")
        draw_rows(true)
    end

    draw_all()
    while true do
        local now = os.time()
        -- horloge de la gare et compte a rebours de l'actualisation
        local clock = os.date("%H:%M:%S", now)
        if clock ~= last_clock then
            io.write("\x1b[2;71H\x1b[1m" .. clock .. "\x1b[0m")
            io.write(string.format("\x1b[22;3HACTUALISATION DANS %2d S", math.max(0, next_refresh - now)))
            io.flush()
            -- colonne INFORMATION recalculee a chaque minute ronde
            if string.sub(clock, -2) == "00" then draw_rows(false) end
            last_clock = clock
        end
        if now >= next_refresh then
            io.write("\x1b[22;3HACTUALISATION EN COURS...")
            io.flush()
            local fresh = load_board(st)
            if fresh then trains = fresh end
            next_refresh = os.time() + REFRESH
            draw_rows(false)
        end

        local k = minitel.get_key()
        if k then
            local list = visible()
            if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return "QUIT"
            elseif k == "G" or k == "g" then return "GARE"
            elseif k == "T" or k == "t" then return "TRAJET"
            elseif k == "R" or k == "r" then next_refresh = 0
            elseif k == "REPETITION" then draw_all()
            elseif k == "UP" and #list > 0 then
                cursor = cursor > 1 and cursor - 1 or math.min(#list, BOARD_ROWS)
                draw_rows(false)
            elseif k == "DOWN" and #list > 0 then
                cursor = cursor < math.min(#list, BOARD_ROWS) and cursor + 1 or 1
                draw_rows(false)
            elseif (k == "ENVOI" or k == " ") and list[cursor] then
                minitel.play_sound("pickup")
                show_train(list[cursor], st)
                draw_all()
            end
        end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- TRAJET D'UNE GARE A UNE AUTRE
-- =====================================================================
local function connection_trains(c)
    local parts = {}
    for _, s in ipairs(c.sections or {}) do
        if s.journey then
            parts[#parts + 1] = train_label(s.journey.category, s.journey.number)
        end
    end
    return table.concat(parts, " > ")
end

local function show_connection(c)
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 TRAIN  -  DETAIL DU TRAJET")
    local dep_ts = tonumber(c.from and c.from.departureTimestamp)
    local arr_ts = tonumber(c.to and c.to.arrivalTimestamp)
    io.write(string.format("\x1b[3;3H\x1b[1m%s\x1b[0m  >  \x1b[1m%s\x1b[0m",
        up(c.from.station and c.from.station.name), up(c.to.station and c.to.station.name)))
    io.write(string.format("\x1b[4;3HLE %s   DUREE %s   %d CORRESPONDANCE%s", dep_ts and os.date("%d/%m", dep_ts) or "",
        duration(c.duration), c.transfers or 0, (c.transfers or 0) > 1 and "S" or ""))
    io.write("\x1b[5;1H" .. string.rep("-", 80))
    local y = 6
    local prev_arr
    for _, s in ipairs(c.sections or {}) do
        if y > 18 then break end
        local d, a = s.departure or {}, s.arrival or {}
        local dts, ats = tonumber(d.departureTimestamp), tonumber(a.arrivalTimestamp)
        if s.journey then
            if prev_arr and dts then
                io.write(string.format("\x1b[%d;10H:  CORRESPONDANCE %d MN", y, math.floor((dts - prev_arr) / 60)))
                y = y + 1
            end
            local voie = up(d.platform or "")
            io.write(string.format("\x1b[%d;3H\x1b[1m%s\x1b[0m  O  %s  %s%s", y, hhmm(dts),
                minitel.pad(up(d.station and d.station.name), 34), minitel.pad(train_label(s.journey.category, s.journey.number), 12),
                voie ~= "" and (" VOIE " .. voie) or ""))
            io.write(string.format("\x1b[%d;10H|  DIRECTION %s", y + 1, string.sub(up(s.journey.to), 1, 50)))
            io.write(string.format("\x1b[%d;3H\x1b[1m%s\x1b[0m  O  %s", y + 2, hhmm(ats), up(a.station and a.station.name)))
            y = y + 3
            prev_arr = ats
        elseif s.walk then
            local mn = math.floor((tonumber(s.walk.duration) or 0) / 60)
            io.write(string.format("\x1b[%d;10H:  A PIED JUSQU'A %s (%d MN)", y,
                string.sub(up(a.station and a.station.name), 1, 40), mn))
            y = y + 1
            prev_arr = ats or prev_arr
        end
    end
    io.write(string.format("\x1b[22;3HARRIVEE PREVUE \x1b[1m%s\x1b[0m", arr_ts and os.date("%d/%m A %H:%M", arr_ts) or "?"))
    minitel.footer("RETOUR : LISTE DES TRAJETS")
    io.flush()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == "ENVOI" or k == "SOMMAIRE" then return end
        if k == "REPETITION" then return show_connection(c) end
        minitel.sleep(0.02)
    end
end

local function trajet(from)
    from = from or ask_station("GARE DE DEPART", recent[1] and recent[1].name)
    if not from then return end
    local to = ask_station("GARE D'ARRIVEE", recent[2] and recent[2].name)
    if not to then return end
    remember(to); remember(from)
    wait_box("RECHERCHE DES TRAJETS...")
    local data = fetch("connections?limit=6&from=" .. url_encode(from.id) .. "&to=" .. url_encode(to.id))
    if not data then
        minitel.msg_box("ERREUR RESEAU", "Le serveur des horaires ne repond pas.", "lose")
        return
    end
    local list = data.connections or {}
    if #list == 0 then
        minitel.msg_box("AUCUN TRAJET", "Pas de trajet trouve entre ces deux gares.", "lose")
        return
    end

    local sel = 1
    local function row(i)
        local c = list[i]
        local dts = tonumber(c.from and c.from.departureTimestamp)
        local ats = tonumber(c.to and c.to.arrivalTimestamp)
        local next_day = dts and ats and os.date("%d", dts) ~= os.date("%d", ats)
        local text = string.format(" %s   %s   %s  %-6s  %s     %s", dts and os.date("%d/%m", dts) or "     ",
            hhmm(dts), hhmm(ats) .. (next_day and "+1" or "  "), duration(c.duration),
            tostring(c.transfers or 0), minitel.pad(connection_trains(c), 38))
        text = minitel.pad(text, 80)
        local y = 5 + (i - 1) * 2
        if i == sel then io.write(string.format("\x1b[%d;1H\x1b[7m%s\x1b[0m", y, text))
        else io.write(string.format("\x1b[%d;1H%s", y, text)) end
    end
    local function draw()
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 TRAIN  -  TRAJETS")
        io.write(string.format("\x1b[2;3H\x1b[1m%s\x1b[0m  >  \x1b[1m%s\x1b[0m", from.name, to.name))
        io.write("\x1b[4;1H\x1b[7m" .. minitel.pad(" DATE    DEPART  ARRIVEE  DUREE   CORR. TRAINS", 80) .. "\x1b[0m")
        for i = 1, #list do row(i) end
        minitel.footer("HAUT/BAS : TRAJET    ENVOI : DETAIL    RETOUR : MENU")
        io.flush()
    end
    draw()
    minitel.play_sound("pickup")
    while true do
        local k = minitel.get_key()
        if k then
            local old = sel
            if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then return
            elseif k == "UP" then sel = sel > 1 and sel - 1 or #list
            elseif k == "DOWN" then sel = sel < #list and sel + 1 or 1
            elseif k == "REPETITION" then draw()
            elseif k == "ENVOI" or k == " " then
                show_connection(list[sel])
                draw()
            end
            if sel ~= old then row(old); row(sel); io.flush() end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- ACCUEIL
-- =====================================================================
local LOCO = {
    [[        _______________________________________________________    ]],
    [[       /  ___   ___   ___   ___   ___   ___   ___   ___   ___  |   ]],
    [[      /  |___| |___| |___| |___| |___| |___| |___| |___| |___| |   ]],
    [[     |    3 6 1 5   T R A I N         ===========================|  ]],
    [[     |___________________________________________________________|  ]],
    [[       (O)(O)            (O)(O)             (O)(O)        (O)(O)    ]],
    [[ ========================================================================== ]],
}

local function home()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 TRAIN  -  HORAIRES EN DIRECT")
    for i, l in ipairs(LOCO) do
        io.write(string.format("\x1b[%d;3H%s", 2 + i, l))
    end
    io.write("\x1b[11;8H\x1b[7m 1 \x1b[0m  TABLEAU DES DEPARTS D'UNE GARE")
    io.write("\x1b[12;8H\x1b[7m 2 \x1b[0m  TRAJET D'UNE GARE A UNE AUTRE")
    if #recent > 0 then
        io.write("\x1b[14;8H\x1b[1mGARES RECENTES\x1b[0m")
        for i, r in ipairs(recent) do
            local col = (i - 1) % 2 == 0 and 8 or 44
            local y = 15 + math.floor((i - 1) / 2)
            io.write(string.format("\x1b[%d;%dH\x1b[7m %s \x1b[0m  %s", y, col, string.char(64 + i), string.sub(r.name, 1, 28)))
        end
    end
    io.write("\x1b[20;8HHoraires SNCF et europeens en direct : transport.opendata.ch")
    local letters = #recent == 1 and "A" or ("A-" .. string.char(64 + #recent))
    minitel.footer("1 / 2 : CHOIX     " .. (#recent > 0 and (letters .. " : GARE RECENTE     ") or "") .. "RETOUR : QUITTER")
    io.flush()
end

load_recent()
home()
while true do
    local k = minitel.get_key()
    if k then
        local st, action, redraw
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "1" then
            st = ask_station("TABLEAU DES DEPARTS", recent[1] and recent[1].name)
            redraw = true
        elseif k == "2" then action = "TRAJET"
        elseif k == "REPETITION" then redraw = true
        elseif #k == 1 then
            local i = string.byte(string.upper(k)) - 64
            if recent[i] then st = recent[i] end
        end
        if st or action then redraw = true end
        -- d'un tableau, on peut passer a une autre gare ou a un trajet
        while st or action do
            if action == "TRAJET" then
                trajet(st)
                st, action = nil, nil
            else
                local r = show_board(st)
                st, action = nil, nil
                if r == "GARE" then
                    st = ask_station("TABLEAU DES DEPARTS", "")
                elseif r == "TRAJET" then
                    st, action = recent[1], "TRAJET"
                end
            end
        end
        if redraw then home() end
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
