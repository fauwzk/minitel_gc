-- @TYPE: SANTE / APPLE HEALTH
-- @DESC: Carnet de sante Apple Health : pas, coeur, sommeil, poids et seances lus depuis l'export de l'iPhone, avec courbes 30 jours.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- 0. CONFIGURATION
-- =====================================================================
local CONFIG = {
    DOSSIER = "utils/sante/",
    CACHE = "utils/sante/cache_sante.lua",
    TITRE = "3615 SANTE - CARNET APPLE HEALTH",
    OBJ_PAS = 10000,
    OBJ_EXERCICE = 30,      -- minutes
    OBJ_SOMMEIL = 8 * 60,   -- minutes
    CHART_DAYS = 30
}

os.execute("mkdir -p " .. CONFIG.DOSSIER .. " 2>/dev/null")

-- =====================================================================
-- 1. FORMATAGE & CALENDRIER
-- =====================================================================
local JOURS = { "DIMANCHE", "LUNDI", "MARDI", "MERCREDI", "JEUDI", "VENDREDI", "SAMEDI" }
local MOIS = { "JANVIER", "FEVRIER", "MARS", "AVRIL", "MAI", "JUIN", "JUILLET",
               "AOUT", "SEPTEMBRE", "OCTOBRE", "NOVEMBRE", "DECEMBRE" }

-- Les jours sont manipules a midi pour rester insensibles aux changements d'heure
local function key_to_ts(key)
    local y, m, d = tostring(key):match("^(%d+)%-(%d+)%-(%d+)")
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

local function ts_to_key(ts)
    return os.date("%Y-%m-%d", ts)
end

local function today_ts()
    local t = os.date("*t")
    return os.time({ year = t.year, month = t.month, day = t.day, hour = 12 })
end

local function long_date(ts)
    local t = os.date("*t", ts)
    return string.format("%s %d %s %d", JOURS[t.wday], t.day, MOIS[t.month], t.year)
end

local function abbr_date(ts)
    local t = os.date("*t", ts)
    return string.format("%s. %02d/%02d/%04d", JOURS[t.wday]:sub(1, 3), t.day, t.month, t.year)
end

local function short_key(key)
    local y, m, d = tostring(key):match("^(%d+)%-(%d+)%-(%d+)")
    return y and (d .. "/" .. m .. "/" .. y) or tostring(key)
end

-- "2026-10-24 07:12:30 +0200" -> horodatage UTC (secondes)
local function parse_ts(s)
    local Y, M, D, h, mi, sec, sg, oh, om = tostring(s):match("^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+) ([%+%-])(%d%d)(%d%d)")
    if not Y then return nil end
    local t = os.time({ year = tonumber(Y), month = tonumber(M), day = tonumber(D),
                        hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec), isdst = false })
    local off = tonumber(oh) * 3600 + tonumber(om) * 60
    if sg == "-" then off = -off end
    return t - off
end

local function fmt_int(v)
    if not v then return "--" end
    local s = tostring(math.floor(v + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""))
end

local function fmt_dec(v, n)
    if not v then return "--" end
    return string.format("%." .. (n or 1) .. "f", v)
end

local function fmt_hm(minutes)
    if not minutes then return "--" end
    local m = math.floor(minutes + 0.5)
    return string.format("%dh%02d", math.floor(m / 60), m % 60)
end

local function with_unit(str, unit)
    if str == "--" then return str end
    return str .. " " .. unit
end

-- Jauge identique a minitel.progress_bar, mais renvoyee en chaine pour le delta-drawing
local function gauge(width, current, max, show_pct)
    local bar_w = show_pct and (width - 7) or (width - 2)
    if bar_w < 2 then bar_w = 2 end
    local ratio = 0
    if current and max and max > 0 then ratio = math.max(0, math.min(1, current / max)) end
    local filled = math.floor(ratio * bar_w + 0.5)
    local bar = "[" .. (filled > 0 and ("\x1b[7m" .. string.rep(" ", filled) .. "\x1b[0m") or "")
             .. string.rep(".", bar_w - filled) .. "]"
    if show_pct then
        if current and max and max > 0 then
            bar = bar .. string.format(" %3d%%", math.min(999, math.floor(current / max * 100 + 0.5)))
        else
            bar = bar .. "  --%"
        end
    end
    return bar
end

local function sh_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function sh_ok(cmd)
    local r = os.execute(cmd)
    return r == true or r == 0
end

-- =====================================================================
-- 2. CARNET DE DONNEES (CACHE LUA AGREGE PAR JOUR)
-- =====================================================================
local data = { meta = nil, days = {}, workouts = {} }
local dates = {}
local best_steps, best_steps_key = nil, nil

local function index_data()
    dates = {}
    for k in pairs(data.days) do dates[#dates + 1] = k end
    table.sort(dates)
    table.sort(data.workouts, function(a, b) return (a.d .. a.h) > (b.d .. b.h) end)
    best_steps, best_steps_key = nil, nil
    for _, k in ipairs(dates) do
        local s = data.days[k].steps
        if s and (not best_steps or s > best_steps) then best_steps, best_steps_key = s, k end
    end
end

local function load_cache()
    local fn = loadfile(CONFIG.CACHE)
    if fn then
        local ok, t = pcall(fn)
        if ok and type(t) == "table" and type(t.days) == "table" then
            data = { meta = t.meta, days = t.days, workouts = t.workouts or {} }
            index_data()
            return true
        end
    end
    data = { meta = nil, days = {}, workouts = {} }
    index_data()
    return false
end

local function num_str(v)
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.2f", v)
end

local function save_cache()
    local f = io.open(CONFIG.CACHE, "w")
    if not f then return false end
    local m = data.meta or {}
    f:write("-- Cache 3615 SANTE (genere automatiquement)\nreturn {\n")
    f:write(string.format("meta = { source = %q, imported = %q, records = %d },\n",
        m.source or "?", m.imported or "?", m.records or 0))
    f:write("days = {\n")
    for _, k in ipairs(dates) do
        local parts = {}
        for field, v in pairs(data.days[k]) do parts[#parts + 1] = field .. "=" .. num_str(v) end
        table.sort(parts)
        f:write(string.format("[%q]={%s},\n", k, table.concat(parts, ",")))
    end
    f:write("},\nworkouts = {\n")
    for _, w in ipairs(data.workouts) do
        f:write(string.format("{d=%q,h=%q,t=%q,dur=%s,dist=%s,kcal=%s},\n",
            w.d, w.h, w.t, num_str(w.dur or 0),
            w.dist and num_str(w.dist) or "nil", w.kcal and num_str(w.kcal) or "nil"))
    end
    f:write("}}\n")
    f:close()
    return true
end

-- Derniere valeur connue d'un champ a la date donnee (ou avant)
local function last_value_before(key, field)
    for i = #dates, 1, -1 do
        local k = dates[i]
        if k <= key and data.days[k][field] then return data.days[k][field], k end
    end
    return nil
end

-- Moyenne d'un champ sur n jours calendaires se terminant a ts_end
local function window_avg(field, ts_end, n)
    local s, c = 0, 0
    for i = 0, n - 1 do
        local d = data.days[ts_to_key(ts_end - i * 86400)]
        if d and d[field] then s = s + d[field]; c = c + 1 end
    end
    return c > 0 and (s / c) or nil
end

-- =====================================================================
-- 3. IMPORTATEUR DE L'EXPORT APPLE HEALTH (export.xml / exportation.zip)
-- =====================================================================
local function conv_dist(v, u)
    if u == "mi" then return v * 1.609344 end
    if u == "m" then return v / 1000 end
    if u == "yd" then return v * 0.0009144 end
    return v
end

local function conv_energy(v, u)
    if u == "kJ" then return v / 4.184 end
    return v
end

local function conv_mass(v, u)
    if u == "lb" then return v * 0.45359237 end
    if u == "g" then return v / 1000 end
    return v
end

local function conv_pct(v)
    if v <= 1.5 then return v * 100 end
    return v
end

-- "sum" : total par source puis meilleure source (evite le double comptage iPhone + Watch)
local QTY = {
    StepCount                = { key = "steps",  mode = "sum" },
    DistanceWalkingRunning   = { key = "dist",   mode = "sum", conv = conv_dist },
    ActiveEnergyBurned       = { key = "kcal",   mode = "sum", conv = conv_energy },
    FlightsClimbed           = { key = "floors", mode = "sum" },
    AppleExerciseTime        = { key = "exo",    mode = "sum" },
    HeartRate                = { key = "hr",     mode = "stat" },
    RestingHeartRate         = { key = "rhr",    mode = "avg" },
    HeartRateVariabilitySDNN = { key = "hrv",    mode = "avg" },
    OxygenSaturation         = { key = "spo2",   mode = "avg", conv = conv_pct },
    BodyMass                 = { key = "weight", mode = "last", conv = conv_mass }
}

local SLEEP_STAGES = {
    InBed = "inbed", Asleep = "asleep", AsleepUnspecified = "asleep",
    AsleepCore = "core", AsleepDeep = "deep", AsleepREM = "rem"
}

local function find_export()
    local f = io.popen("\\ls -1t " .. CONFIG.DOSSIER .. " 2>/dev/null")
    if not f then return nil end
    local found = nil
    for name in f:lines() do
        local low = name:lower()
        if low:match("%.zip$") or (low:match("%.xml$") and not low:find("cda", 1, true)) then
            found = CONFIG.DOSSIER .. name
            break
        end
    end
    f:close()
    return found
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:seek("end")
    f:close()
    return s
end

-- Cherche le gros fichier XML (export.xml / exportation.xml) a l'interieur du ZIP
local function zip_inner_xml(path)
    local p = io.popen("unzip -l " .. sh_quote(path) .. " 2>/dev/null")
    if not p then return nil end
    local best, best_size = nil, nil
    for line in p:lines() do
        local size, name = line:match("^%s*(%d+)%s+%S+%s+%S+%s+(.+%.xml)%s*$")
        if size and not name:lower():find("cda", 1, true) then
            size = tonumber(size)
            if not best_size or size > best_size then best, best_size = name, size end
        end
    end
    p:close()
    return best, best_size
end

local function import_status(nlines, nrec, nwk)
    io.write(string.format("\x1b[20;4H%s", minitel.pad(string.format(
        "LIGNES : %s | MESURES : %s | SEANCES : %d | [RETOUR] STOP",
        fmt_int(nlines), fmt_int(nrec), nwk), 74)))
end

local function import_export(path)
    local is_zip = path:lower():match("%.zip$") ~= nil
    local fh, total

    if is_zip then
        if not sh_ok("which unzip >/dev/null 2>&1") then
            minitel.msg_box("UNZIP ABSENT", "Installez unzip (sudo apt install unzip) ou decompressez l'archive dans utils/sante/.", "lose")
            return false
        end
        local inner, size = zip_inner_xml(path)
        if not inner then
            minitel.msg_box("ARCHIVE INVALIDE", "Aucun fichier export.xml trouve dans cette archive ZIP.", "lose")
            return false
        end
        fh = io.popen("unzip -p " .. sh_quote(path) .. " " .. sh_quote(inner) .. " 2>/dev/null")
        total = size
    else
        fh = io.open(path, "r")
        total = file_size(path)
    end
    if not fh then
        minitel.msg_box("ERREUR", "Impossible d'ouvrir le fichier " .. path, "lose")
        return false
    end
    total = math.max(1, total or 1)

    local sums, hr, avgs, lasts, sleep = {}, {}, {}, {}, {}
    local workouts = {}
    local cur_wk = nil
    local nlines, nread, nrec = 0, 0, 0
    local cancelled = false

    local function finish_workout()
        if cur_wk then workouts[#workouts + 1] = cur_wk end
        cur_wk = nil
    end

    io.write("\x1b[19;4H" .. string.rep(" ", 74))
    import_status(0, 0, 0)
    io.flush()

    for line in fh:lines() do
        nlines = nlines + 1
        nread = nread + #line + 1

        if cur_wk then
            if line:find("</Workout>", 1, true) then
                finish_workout()
            else
                -- Exports iOS 16+ : distance et energie dans les WorkoutStatistics
                local st = line:match('<WorkoutStatistics type="HKQuantityTypeIdentifier(%w+)"')
                if st then
                    local s = tonumber(line:match(' sum="([^"]*)"') or "")
                    local u = line:match(' unit="([^"]*)"')
                    if s then
                        if st:find("^Distance") and not cur_wk.dist then cur_wk.dist = conv_dist(s, u) end
                        if st == "ActiveEnergyBurned" and not cur_wk.kcal then cur_wk.kcal = conv_energy(s, u) end
                    end
                end
            end

        elseif line:find('<Record type="HK', 1, true) then
            local kind, name = line:match('<Record type="HK(%a-)TypeIdentifier(%w+)"')
            local def = (kind == "Quantity") and QTY[name] or nil

            if def then
                local v = tonumber(line:match(' value="([^"]*)"') or "")
                local start = line:match(' startDate="([^"]*)"')
                if v and start then
                    if def.conv then v = def.conv(v, line:match(' unit="([^"]*)"')) end
                    local day = start:sub(1, 10)
                    nrec = nrec + 1

                    if def.mode == "sum" then
                        local src = line:match(' sourceName="([^"]*)"') or "?"
                        local bucket = sums[def.key] or {}
                        sums[def.key] = bucket
                        local by_src = bucket[day] or {}
                        bucket[day] = by_src
                        by_src[src] = (by_src[src] or 0) + v
                    elseif def.mode == "stat" then
                        local t = hr[day]
                        if not t then
                            hr[day] = { s = v, n = 1, mn = v, mx = v }
                        else
                            t.s = t.s + v; t.n = t.n + 1
                            if v < t.mn then t.mn = v end
                            if v > t.mx then t.mx = v end
                        end
                    elseif def.mode == "avg" then
                        local bucket = avgs[def.key] or {}
                        avgs[def.key] = bucket
                        local t = bucket[day]
                        if not t then bucket[day] = { s = v, n = 1 } else t.s = t.s + v; t.n = t.n + 1 end
                    elseif def.mode == "last" then
                        local bucket = lasts[def.key] or {}
                        lasts[def.key] = bucket
                        local t = bucket[day]
                        if not t or start >= t.at then bucket[day] = { at = start, v = v } end
                    end
                end

            elseif kind == "Category" and name == "SleepAnalysis" then
                local stage = SLEEP_STAGES[(line:match(' value="HKCategoryValueSleepAnalysis(%w+)"') or "")]
                local t0 = parse_ts(line:match(' startDate="([^"]*)"'))
                local e_str = line:match(' endDate="([^"]*)"')
                local t1 = parse_ts(e_str)
                if stage and t0 and t1 and t1 > t0 then
                    local dur = (t1 - t0) / 60
                    local day = e_str:sub(1, 10)   -- nuit rattachee au jour du reveil
                    local src = line:match(' sourceName="([^"]*)"') or "?"
                    local by_src = sleep[day] or {}
                    sleep[day] = by_src
                    local acc = by_src[src] or { asleep = 0, core = 0, deep = 0, rem = 0, inbed = 0 }
                    by_src[src] = acc
                    acc[stage] = acc[stage] + dur
                    if stage == "core" or stage == "deep" or stage == "rem" then acc.asleep = acc.asleep + dur end
                    nrec = nrec + 1
                end
            end

        elseif line:find("<Workout ", 1, true) then
            local wtype = line:match('workoutActivityType="HKWorkoutActivityType(%w+)"')
            local start = line:match(' startDate="([^"]*)"')
            if wtype and start then
                local dur = tonumber(line:match(' duration="([^"]*)"') or "") or 0
                local du = line:match(' durationUnit="([^"]*)"')
                if du == "s" then dur = dur / 60 elseif du == "hr" or du == "h" then dur = dur * 60 end
                cur_wk = { t = wtype, d = start:sub(1, 10), h = start:sub(12, 16), dur = dur }
                local td = tonumber(line:match(' totalDistance="([^"]*)"') or "")
                if td and td > 0 then cur_wk.dist = conv_dist(td, line:match(' totalDistanceUnit="([^"]*)"')) end
                local te = tonumber(line:match(' totalEnergyBurned="([^"]*)"') or "")
                if te and te > 0 then cur_wk.kcal = conv_energy(te, line:match(' totalEnergyBurnedUnit="([^"]*)"')) end
                if line:match("/>%s*$") then finish_workout() end
            end
        end

        if nlines % 20000 == 0 then
            minitel.progress_bar(4, 19, 74, math.min(nread, total), total, true)
            import_status(nlines, nrec, #workouts)
            io.flush()
            local k = minitel.get_key()
            if k == "RETOUR" or k == "ANNULATION" then
                cancelled = true
                break
            end
        end
    end
    finish_workout()
    fh:close()

    if cancelled then
        minitel.msg_box("IMPORT ANNULE", "Le carnet precedent est conserve tel quel.", "lose")
        return false
    end
    if nrec == 0 and #workouts == 0 then
        minitel.msg_box("AUCUNE DONNEE", "Ce fichier ne contient aucune mesure Apple Health reconnue.", "lose")
        return false
    end

    minitel.progress_bar(4, 19, 74, 1, 1, true)
    io.write("\x1b[20;4H" .. minitel.pad("AGREGATION DES MESURES PAR JOUR...", 74))
    io.flush()

    -- Agregation finale : une ligne par jour
    local days = {}
    local function day_of(k)
        local t = days[k]
        if not t then t = {}; days[k] = t end
        return t
    end
    for key, bucket in pairs(sums) do
        for k, by_src in pairs(bucket) do
            local best = 0
            for _, v in pairs(by_src) do if v > best then best = v end end
            day_of(k)[key] = best
        end
    end
    for k, t in pairs(hr) do
        local d = day_of(k)
        d.hr_avg, d.hr_min, d.hr_max, d.hr_n = t.s / t.n, t.mn, t.mx, t.n
    end
    for key, bucket in pairs(avgs) do
        for k, t in pairs(bucket) do day_of(k)[key] = t.s / t.n end
    end
    for key, bucket in pairs(lasts) do
        for k, t in pairs(bucket) do day_of(k)[key] = t.v end
    end
    for k, by_src in pairs(sleep) do
        -- Phases : meilleure source (souvent la Watch) ; temps au lit : souvent saisi par l'iPhone
        local best, inbed = nil, 0
        for _, acc in pairs(by_src) do
            if not best or acc.asleep > best.asleep or (acc.asleep == best.asleep and acc.inbed > best.inbed) then
                best = acc
            end
            if acc.inbed > inbed then inbed = acc.inbed end
        end
        local d = day_of(k)
        if best.asleep > 0 then d.sleep = best.asleep end
        if best.core > 0 then d.s_core = best.core end
        if best.deep > 0 then d.s_deep = best.deep end
        if best.rem > 0 then d.s_rem = best.rem end
        if inbed > 0 then d.inbed = inbed end
    end

    data = {
        meta = { source = path:match("([^/]+)$") or path, imported = os.date("%d/%m/%Y %H:%M"), records = nrec },
        days = days,
        workouts = workouts
    }
    index_data()
    save_cache()
    minitel.msg_box("IMPORT TERMINE", string.format("%s mesures, %d jours et %d seances enregistres dans le carnet.",
        fmt_int(nrec), #dates, #workouts), "win")
    return true
end

-- =====================================================================
-- 4. DONNEES DE DEMONSTRATION (POUR TESTER SANS IPHONE)
-- =====================================================================
local function generate_demo()
    math.randomseed(os.time())
    local days, workouts = {}, {}
    local today = today_ts()
    local weight = 76 + math.random() * 4
    local sports = { "Running", "Walking", "Cycling", "TraditionalStrengthTraining", "Yoga", "Swimming", "HighIntensityIntervalTraining" }
    local nrec = 0

    for i = 119, 0, -1 do
        local ts = today - i * 86400
        local wday = os.date("*t", ts).wday
        local weekend = (wday == 1 or wday == 7)
        local steps = math.floor((weekend and 9000 or 6500) + (math.random() - 0.4) * 7000)
        if steps < 900 then steps = 900 + math.random(500) end
        local sleep = 380 + math.random(0, 120) + (weekend and 40 or 0)
        weight = weight + (math.random() - 0.55) * 0.25
        days[ts_to_key(ts)] = {
            steps = steps,
            dist = steps * 0.00072,
            kcal = math.floor(steps * 0.042 + math.random(0, 120)),
            floors = math.random(0, 18),
            exo = math.random(4, 65),
            hr_avg = 68 + math.random() * 10,
            hr_min = 47 + math.random(0, 8),
            hr_max = 115 + math.random(0, 60),
            hr_n = math.random(300, 900),
            rhr = 54 + math.random() * 6,
            hrv = 32 + math.random() * 30,
            spo2 = 95 + math.random() * 4,
            weight = (i % 3 == 0) and weight or nil,
            sleep = sleep,
            s_deep = sleep * (0.12 + math.random() * 0.08),
            s_rem = sleep * (0.18 + math.random() * 0.08),
            inbed = sleep + math.random(10, 45)
        }
        local d = days[ts_to_key(ts)]
        d.s_core = sleep - d.s_deep - d.s_rem
        nrec = nrec + math.floor(d.hr_n + steps / 80)

        if math.random() < 0.4 then
            local t = sports[math.random(#sports)]
            local dur = math.random(20, 75)
            local w = { t = t, d = ts_to_key(ts), h = string.format("%02d:%02d", math.random(7, 20), math.random(0, 59)),
                        dur = dur, kcal = dur * (6 + math.random() * 5) }
            if t == "Running" then w.dist = dur / 5.8 elseif t == "Walking" then w.dist = dur / 11
            elseif t == "Cycling" then w.dist = dur / 2.4 elseif t == "Swimming" then w.dist = dur / 30 end
            workouts[#workouts + 1] = w
        end
    end

    data = {
        meta = { source = "DONNEES DE DEMONSTRATION", imported = os.date("%d/%m/%Y %H:%M"), records = nrec },
        days = days,
        workouts = workouts
    }
    index_data()
    save_cache()
end

-- =====================================================================
-- 5. AFFICHAGE DELTA-DRAWING (CACHE PAR POSITION)
-- =====================================================================
local screen_cache = {}
local chart_cells = {}

local function reset_cache()
    screen_cache = {}
    chart_cells = {}
end

-- N'envoie au Minitel que les zones dont le contenu a change
local function put(y, x, str)
    local k = y * 100 + x
    if screen_cache[k] ~= str then
        screen_cache[k] = str
        io.write(string.format("\x1b[%d;%dH%s", y, x, str))
    end
end

local SPORTS = {
    Running = "COURSE A PIED", Walking = "MARCHE", Cycling = "VELO", Swimming = "NATATION",
    Hiking = "RANDONNEE", Yoga = "YOGA", HighIntensityIntervalTraining = "HIIT",
    TraditionalStrengthTraining = "MUSCULATION", FunctionalStrengthTraining = "RENFO FONCTION.",
    CoreTraining = "GAINAGE", Elliptical = "ELLIPTIQUE", Rowing = "RAMEUR", Dance = "DANSE",
    Soccer = "FOOTBALL", Tennis = "TENNIS", Basketball = "BASKET", Boxing = "BOXE",
    MixedCardio = "CARDIO MIXTE", Cooldown = "RECUPERATION", Pilates = "PILATES",
    StairClimbing = "ESCALIERS", CrossTraining = "CROSS TRAINING", DownhillSkiing = "SKI ALPIN",
    Snowboarding = "SNOWBOARD", Climbing = "ESCALADE", MartialArts = "ARTS MARTIAUX",
    Badminton = "BADMINTON", TableTennis = "PING-PONG", Other = "AUTRE"
}

local function sport_name(t)
    return SPORTS[t] or minitel.clean_accents(t or "?"):upper()
end

local CHARTS = {
    { key = "steps",  label = "PAS QUOTIDIENS",          unit = "pas",  fmt = fmt_int },
    { key = "dist",   label = "DISTANCE MARCHE/COURSE",  unit = "km",   fmt = function(v) return fmt_dec(v, 1) end },
    { key = "kcal",   label = "ENERGIE ACTIVE",          unit = "kcal", fmt = fmt_int },
    { key = "exo",    label = "MINUTES D'EXERCICE",      unit = "min",  fmt = fmt_int },
    { key = "sleep",  label = "DUREE DE SOMMEIL",        unit = "",     fmt = fmt_hm },
    { key = "hr_avg", label = "FREQUENCE CARDIAQUE MOY.", unit = "bpm", fmt = fmt_int, rel = true },
    { key = "rhr",    label = "FREQUENCE CARDIAQUE REPOS", unit = "bpm", fmt = fmt_int, rel = true },
    { key = "hrv",    label = "VARIABILITE CARDIAQUE",   unit = "ms",   fmt = fmt_int, rel = true },
    { key = "weight", label = "POIDS",                   unit = "kg",   fmt = function(v) return fmt_dec(v, 1) end, rel = true }
}

local TABS = { { "1", "JOURNEE", "JOUR" }, { "2", "COURBES", "COURBES" }, { "3", "SEANCES", "SEANCES" }, { "4", "IMPORT", "IMPORT" } }
local TAB_ORDER = { JOUR = 1, COURBES = 2, SEANCES = 3, IMPORT = 4 }

local FOOTERS = {
    JOUR    = " [Q/D] JOUR -/+ | [1-4] ONGLETS | [SUITE] ONGLET SUIV. | [GUIDE] AIDE | [RETOUR]",
    COURBES = " [Z/S] COURBE | [Q/D] CURSEUR | [PAGE] +/-30 JOURS | [ENVOI] LE JOUR | [RETOUR]",
    SEANCES = " [Z/S] CHOIX | [ENVOI] VOIR LE JOUR | [1-4] ONGLETS | [SUITE] ONGLET | [RETOUR]",
    IMPORT  = " [ENVOI] IMPORTER | [F] PARCOURIR | [D] DEMO | [X] EFFACER | [1-4] | [RETOUR]"
}

local view = "JOUR"
local sel_ts = today_ts()
local chart_metric = 1
local chart_end_ts = sel_ts
local chart_cur = CONFIG.CHART_DAYS
local wk_cursor, wk_offset, wk_visible = 1, 0, 11

local function draw_header()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    reset_cache()

    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m  [SYS]  " .. minitel.center("* * *  " .. CONFIG.TITRE .. "  * * *", 60) .. "  9600 BDS \x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    local tabs = ""
    for _, t in ipairs(TABS) do
        local label = " [" .. t[1] .. "] " .. t[2] .. " "
        if t[3] == view then tabs = tabs .. "\x1b[7m" .. label .. "\x1b[0m " else tabs = tabs .. label .. " " end
    end
    io.write("\x1b[4;2H" .. tabs)
    local info = data.meta and ("CARNET : " .. #dates .. " JOURS") or "CARNET VIDE"
    io.write(string.format("\x1b[4;%dH\x1b[1m%s\x1b[0m", 80 - #info, info))

    io.write("\x1b[24;1H\x1b[7m" .. minitel.pad(FOOTERS[view], 80) .. "\x1b[0m")
end

-- ---------------------------------------------------------------------
-- 5.1 ONGLET JOURNEE (TABLEAU DE BORD DU JOUR)
-- ---------------------------------------------------------------------
local HEART_ART = {
    " .-.   .-. ",
    "(   `v'   )",
    " \\       / ",
    "  `.   .'  ",
    "    `v'    "
}

local function draw_day_frame()
    minitel.draw_window(2, 5, 38, 9, "ACTIVITE")
    minitel.draw_window(41, 5, 39, 9, "COEUR")
    minitel.draw_window(2, 14, 38, 9, "SOMMEIL")
    minitel.draw_window(41, 14, 39, 9, "CORPS & TENDANCES")
    for i, l in ipairs(HEART_ART) do
        io.write(string.format("\x1b[%d;67H\x1b[1m%s\x1b[0m", 6 + i, l))
    end
end

local function update_day()
    local key = ts_to_key(sel_ts)
    local d = data.days[key] or {}
    local has = data.days[key] ~= nil

    local bar = "<<  " .. long_date(sel_ts) .. "  >>" .. (has and "" or "   (AUCUNE MESURE)")
    put(3, 1, "\x1b[7m" .. minitel.center(bar, 80) .. "\x1b[0m")

    -- ACTIVITE
    put(6, 4, minitel.pad("PAS          : " .. fmt_int(d.steps) .. " / " .. fmt_int(CONFIG.OBJ_PAS), 34))
    put(7, 4, gauge(34, d.steps, CONFIG.OBJ_PAS, true))
    put(8, 4, minitel.pad("DISTANCE     : " .. with_unit(fmt_dec(d.dist, 2), "km"), 34))
    put(9, 4, minitel.pad("ENERGIE ACT. : " .. with_unit(fmt_int(d.kcal), "kcal"), 34))
    put(10, 4, minitel.pad("ETAGES       : " .. fmt_int(d.floors), 34))
    put(11, 4, minitel.pad("EXERCICE     : " .. fmt_int(d.exo) .. " / " .. CONFIG.OBJ_EXERCICE .. " min", 34))
    put(12, 4, gauge(34, d.exo, CONFIG.OBJ_EXERCICE, true))

    -- COEUR
    local minmax = (d.hr_min and d.hr_max) and (fmt_int(d.hr_min) .. "/" .. fmt_int(d.hr_max)) or "--"
    put(6, 43, minitel.pad("FC MOYENNE : " .. with_unit(fmt_int(d.hr_avg), "bpm"), 23))
    put(7, 43, minitel.pad("FC MIN/MAX : " .. minmax, 23))
    put(8, 43, minitel.pad("FC REPOS   : " .. with_unit(fmt_int(d.rhr), "bpm"), 23))
    put(9, 43, minitel.pad("VFC SDNN   : " .. with_unit(fmt_int(d.hrv), "ms"), 23))
    put(10, 43, minitel.pad("SPO2       : " .. with_unit(fmt_dec(d.spo2, 1), "%"), 23))
    put(12, 43, minitel.pad("RELEVES FC : " .. fmt_int(d.hr_n), 23))

    -- SOMMEIL
    put(15, 4, minitel.pad("DORMI : " .. fmt_hm(d.sleep) .. "     AU LIT : " .. fmt_hm(d.inbed), 34))
    put(16, 4, gauge(34, d.sleep, CONFIG.OBJ_SOMMEIL, true))
    put(17, 4, "PROFOND   " .. minitel.pad(fmt_hm(d.s_deep), 6) .. gauge(18, d.s_deep, d.sleep, true))
    put(18, 4, "PARADOX.  " .. minitel.pad(fmt_hm(d.s_rem), 6) .. gauge(18, d.s_rem, d.sleep, true))
    put(19, 4, "LEGER     " .. minitel.pad(fmt_hm(d.s_core), 6) .. gauge(18, d.s_core, d.sleep, true))
    local eff = (d.sleep and d.inbed and d.inbed > 0) and (math.min(100, math.floor(d.sleep / d.inbed * 100 + 0.5)) .. " %") or "--"
    put(20, 4, minitel.pad("EFFICACITE : " .. eff .. "   OBJ. " .. fmt_hm(CONFIG.OBJ_SOMMEIL), 34))
    put(21, 4, minitel.pad("(NUIT TERMINEE CE MATIN-LA)", 34))

    -- CORPS & TENDANCES
    local w_now, w_key = last_value_before(key, "weight")
    local w_line = "POIDS        : " .. with_unit(fmt_dec(w_now, 1), "kg")
    if w_key and w_key ~= key then w_line = w_line .. " (" .. short_key(w_key):sub(1, 5) .. ")" end
    put(15, 43, minitel.pad(w_line, 35))
    local w_then = last_value_before(ts_to_key(sel_ts - 30 * 86400), "weight")
    local delta = (w_now and w_then) and string.format("%+.1f kg", w_now - w_then) or "--"
    put(16, 43, minitel.pad("VAR. 30 J.   : " .. delta, 35))
    put(17, 43, minitel.pad("MOY. PAS 7J  : " .. fmt_int(window_avg("steps", sel_ts, 7)), 35))
    put(18, 43, minitel.pad("MOY. SOMM. 7J: " .. fmt_hm(window_avg("sleep", sel_ts, 7)), 35))

    local from_key = ts_to_key(sel_ts - 6 * 86400)
    local n_wk, dur_wk = 0, 0
    for _, w in ipairs(data.workouts) do
        if w.d >= from_key and w.d <= key then n_wk = n_wk + 1; dur_wk = dur_wk + (w.dur or 0) end
    end
    put(19, 43, minitel.pad("SEANCES 7J   : " .. n_wk .. (n_wk > 0 and (" (" .. fmt_hm(dur_wk) .. ")") or ""), 35))
    put(20, 43, minitel.pad("RECORD PAS   : " .. fmt_int(best_steps), 35))
    put(21, 43, minitel.pad(best_steps_key and ("  LE " .. abbr_date(key_to_ts(best_steps_key))) or "", 35))
    io.flush()
end

-- Saute au jour precedent / suivant possedant des mesures
local function step_day(dir)
    if #dates == 0 then return end
    local key = ts_to_key(sel_ts)
    if dir < 0 then
        for i = #dates, 1, -1 do
            if dates[i] < key then sel_ts = key_to_ts(dates[i]); return end
        end
    else
        for i = 1, #dates do
            if dates[i] > key then sel_ts = key_to_ts(dates[i]); return end
        end
    end
    minitel.play_sound("hit")
end

-- ---------------------------------------------------------------------
-- 5.2 ONGLET COURBES (HISTOGRAMME 30 JOURS)
-- ---------------------------------------------------------------------
local CH_TOP, CH_H, CH_X = 8, 11, 13

local function draw_chart_frame()
    minitel.draw_window(2, 5, 78, 17, "HISTORIQUE " .. CONFIG.CHART_DAYS .. " JOURS")
    for r = 0, CH_H - 1 do
        io.write(string.format("\x1b[%d;%dH|", CH_TOP + r, CH_X - 1))
    end
    io.write(string.format("\x1b[%d;%dH+", CH_TOP + CH_H, CH_X - 1))
end

-- Ecrit une rangee de cellules : rangee entiere si beaucoup de changements, sinon cellule par cellule
local function draw_cells(y, cells)
    local prev = chart_cells[y]
    if not prev then
        io.write(string.format("\x1b[%d;%dH%s", y, CH_X, table.concat(cells)))
    else
        local diff = {}
        for i = 1, #cells do
            if cells[i] ~= prev[i] then diff[#diff + 1] = i end
        end
        if #diff > 5 then
            io.write(string.format("\x1b[%d;%dH%s", y, CH_X, table.concat(cells)))
        else
            for _, i in ipairs(diff) do
                io.write(string.format("\x1b[%d;%dH%s", y, CH_X + (i - 1) * 2, cells[i]))
            end
        end
    end
    chart_cells[y] = cells
end

local function update_chart()
    local m = CHARTS[chart_metric]
    local n = CONFIG.CHART_DAYS
    put(3, 1, "\x1b[7m" .. minitel.center("<<  " .. m.label .. (m.unit ~= "" and (" (" .. m.unit .. ")") or "") ..
        "  " .. chart_metric .. "/" .. #CHARTS .. "  >>", 80) .. "\x1b[0m")

    local vals, day_nums = {}, {}
    local vmin, vmax, sum, cnt = nil, nil, 0, 0
    for i = 1, n do
        local ts = chart_end_ts - (n - i) * 86400
        local d = data.days[ts_to_key(ts)]
        local v = d and d[m.key] or nil
        vals[i] = v
        day_nums[i] = os.date("*t", ts).day
        if v then
            sum = sum + v; cnt = cnt + 1
            if not vmin or v < vmin then vmin = v end
            if not vmax or v > vmax then vmax = v end
        end
    end

    local base, top = 0, vmax or 1
    if m.rel and vmin then base = vmin - (vmax - vmin) * 0.25 end
    if top <= base then base = top - 1 end
    if not m.rel and base < 0 then base = 0 end

    -- Axe des ordonnees
    put(CH_TOP, 3, minitel.pad(vmax and m.fmt(top) or "", 9))
    put(CH_TOP + math.floor(CH_H / 2), 3, minitel.pad(vmax and m.fmt((top + base) / 2) or "", 9))
    put(CH_TOP + CH_H - 1, 3, minitel.pad(vmax and m.fmt(base) or "", 9))

    local heights = {}
    for i = 1, n do
        local v = vals[i]
        if v then
            local h = math.floor((v - base) / (top - base) * CH_H + 0.5)
            heights[i] = math.max(1, math.min(CH_H, h))
        else
            heights[i] = 0
        end
    end

    for r = 1, CH_H do
        local level = CH_H - r + 1
        local cells = {}
        for i = 1, n do
            local filled = heights[i] >= level
            if i == chart_cur then
                cells[i] = filled and "\x1b[7m \x1b[0m " or "  "
            else
                cells[i] = filled and "# " or "  "
            end
        end
        draw_cells(CH_TOP + r - 1, cells)
    end

    local axis, labels = {}, {}
    for i = 1, n do
        axis[i] = (i == chart_cur) and "^-" or "--"
        labels[i] = ((i - 1) % 5 == 0 or i == n) and string.format("%02d", day_nums[i]) or "  "
    end
    draw_cells(CH_TOP + CH_H, axis)
    draw_cells(CH_TOP + CH_H + 1, labels)

    local cur_ts = chart_end_ts - (n - chart_cur) * 86400
    local cur_v = vals[chart_cur]
    put(6, 4, minitel.pad(abbr_date(cur_ts) .. " : \x1b[1m" .. (cur_v and with_unit(m.fmt(cur_v), m.unit) or "AUCUNE MESURE") .. "\x1b[0m", 82))
    local stats = string.format("MOY %d J : %s  |  MIN : %s  |  MAX : %s  |  JOURS MESURES : %d/%d",
        n, cnt > 0 and m.fmt(sum / cnt) or "--", vmin and m.fmt(vmin) or "--", vmax and m.fmt(vmax) or "--", cnt, n)
    put(22, 3, minitel.pad(stats, 76))
    io.flush()
end

local function chart_move(dir)
    local n = CONFIG.CHART_DAYS
    if dir < 0 then
        if chart_cur > 1 then chart_cur = chart_cur - 1 else chart_end_ts = chart_end_ts - 86400 end
    else
        local limit = math.max(today_ts(), key_to_ts(dates[#dates] or ts_to_key(today_ts())))
        if chart_cur < n then chart_cur = chart_cur + 1
        elseif chart_end_ts + 86400 <= limit then chart_end_ts = chart_end_ts + 86400
        else minitel.play_sound("hit") end
    end
    sel_ts = chart_end_ts - (n - chart_cur) * 86400
end

-- ---------------------------------------------------------------------
-- 5.3 ONGLET SEANCES (JOURNAL DES ENTRAINEMENTS)
-- ---------------------------------------------------------------------
local function draw_workouts_frame()
    minitel.draw_window(2, 5, 78, 17, "JOURNAL DES SEANCES D'ENTRAINEMENT")
    io.write("\x1b[6;4H\x1b[1m" .. minitel.pad(" DATE        HEURE  ACTIVITE              DUREE   DISTANCE    ENERGIE", 73) .. "\x1b[0m")
    io.write("\x1b[7;3H" .. string.rep("-", 76))
    io.write("\x1b[19;3H" .. string.rep("-", 76))
end

local function workout_row(idx)
    local w = data.workouts[idx]
    if not w then return string.rep(" ", 73) end
    local line = string.format(" %-10s  %-5s  %-20s %6s  %9s  %9s",
        short_key(w.d), w.h, sport_name(w.t):sub(1, 20), fmt_hm(w.dur),
        w.dist and (fmt_dec(w.dist, 2) .. " km") or "--", w.kcal and (fmt_int(w.kcal) .. " kcal") or "--")
    line = minitel.pad(line, 73)
    if idx == wk_cursor then return "\x1b[7m" .. line .. "\x1b[0m" end
    return line
end

local function update_workouts()
    local total = #data.workouts
    put(3, 1, "\x1b[7m" .. minitel.center(total > 0 and (total .. " SEANCES ENREGISTREES") or "AUCUNE SEANCE ENREGISTREE", 80) .. "\x1b[0m")
    for i = 1, wk_visible do
        put(7 + i, 4, workout_row(wk_offset + i))
    end

    if total > wk_visible then
        local thumb = math.floor(((wk_cursor - 1) / math.max(1, total - 1)) * (wk_visible - 3)) + 2
        for i = 1, wk_visible do
            local c = (i == 1 and "^") or (i == wk_visible and "v") or (i == thumb and "\x1b[7m#\x1b[0m") or ":"
            put(7 + i, 78, c)
        end
    end

    local tot_dur, tot_dist, tot_kcal = 0, 0, 0
    for _, w in ipairs(data.workouts) do
        tot_dur = tot_dur + (w.dur or 0); tot_dist = tot_dist + (w.dist or 0); tot_kcal = tot_kcal + (w.kcal or 0)
    end
    local summary = string.format("SEANCE %d/%d  |  CUMUL : %s  |  %s km  |  %s kcal",
        total > 0 and wk_cursor or 0, total, fmt_hm(tot_dur), fmt_dec(tot_dist, 1), fmt_int(tot_kcal))
    put(20, 4, "\x1b[1m" .. minitel.center(summary, 74) .. "\x1b[0m")
    io.flush()
end

-- ---------------------------------------------------------------------
-- 5.4 ONGLET IMPORT (MODE D'EMPLOI & CHARGEMENT)
-- ---------------------------------------------------------------------
local function draw_import_frame()
    minitel.draw_window(2, 5, 78, 17, "IMPORT DES DONNEES APPLE HEALTH")
    io.write("\x1b[10;4H\x1b[1mEXPORTER DEPUIS L'IPHONE :\x1b[0m")
    io.write("\x1b[11;4H 1. App SANTE > photo de profil > EXPORTER TOUTES LES DONNEES DE SANTE")
    io.write("\x1b[12;4H 2. Copier le fichier exportation.zip dans le dossier utils/sante/")
    io.write("\x1b[13;4H    du Raspberry Pi (AirDrop vers un Mac puis scp, Samba, cle USB...)")
    io.write("\x1b[14;4H 3. Appuyer sur [ENVOI] : le ZIP est lu directement, sans decompression")
    io.write("\x1b[16;3H" .. string.rep("-", 76))
end

local function update_import()
    put(3, 1, "\x1b[7m" .. minitel.center("APPLE HEALTH N'A PAS D'API RESEAU : LE CARNET LIT L'EXPORT DE L'IPHONE", 80) .. "\x1b[0m")
    if data.meta then
        put(6, 4, minitel.pad("\x1b[1mCARNET ACTUEL :\x1b[0m " .. minitel.clean_accents(data.meta.source or "?"), 82))
        put(7, 4, minitel.pad("IMPORTE LE " .. (data.meta.imported or "?") .. "  |  " .. fmt_int(data.meta.records) ..
            " MESURES  |  " .. #data.workouts .. " SEANCES", 74))
        local periode = (#dates > 0) and ("PERIODE : " .. short_key(dates[1]) .. " -> " .. short_key(dates[#dates]) ..
            "  (" .. #dates .. " JOURS)") or "PERIODE : --"
        put(8, 4, minitel.pad(periode, 74))
    else
        put(6, 4, minitel.pad("\x1b[1mCARNET ACTUEL :\x1b[0m VIDE", 82))
        put(7, 4, minitel.pad("Aucune donnee importee pour le moment.", 74))
        put(8, 4, minitel.pad("", 74))
    end

    local path = find_export()
    local detected
    if path then
        local sz = file_size(path) or 0
        detected = string.format("FICHIER DETECTE : %s (%.1f Mo)", path, sz / 1048576)
    else
        detected = "FICHIER DETECTE : AUCUN (.zip ou .xml) DANS " .. CONFIG.DOSSIER
    end
    put(17, 4, minitel.pad(detected, 74))
    put(18, 4, minitel.pad("Un export de plusieurs annees peut prendre quelques minutes sur le Pi.", 74))
    io.flush()
    return path
end

-- =====================================================================
-- 6. NAVIGATION ENTRE ONGLETS
-- =====================================================================
local function draw_view_full()
    draw_header()
    if view == "JOUR" then
        draw_day_frame(); update_day()
    elseif view == "COURBES" then
        draw_chart_frame(); update_chart()
    elseif view == "SEANCES" then
        draw_workouts_frame(); update_workouts()
    else
        draw_import_frame(); update_import()
    end
    io.flush()
end

local function switch_view(v)
    if v == "COURBES" then
        chart_end_ts = sel_ts
        chart_cur = CONFIG.CHART_DAYS
    end
    view = v
    draw_view_full()
end

local function goto_day(key)
    local ts = key_to_ts(key)
    if ts then sel_ts = ts end
    switch_view("JOUR")
end

local function wk_move(dir)
    local total = #data.workouts
    if total == 0 then return end
    wk_cursor = wk_cursor + dir
    if wk_cursor < 1 then wk_cursor = total; wk_offset = math.max(0, total - wk_visible) end
    if wk_cursor > total then wk_cursor = 1; wk_offset = 0 end
    if wk_cursor <= wk_offset then wk_offset = wk_cursor - 1 end
    if wk_cursor > wk_offset + wk_visible then wk_offset = wk_cursor - wk_visible end
    update_workouts()
end

local function after_data_change()
    sel_ts = (#dates > 0) and key_to_ts(dates[#dates]) or today_ts()
    wk_cursor, wk_offset = 1, 0
    switch_view(#dates > 0 and "JOUR" or "IMPORT")
end

-- =====================================================================
-- 7. BOUCLE PRINCIPALE
-- =====================================================================
load_cache()
if #dates > 0 then
    sel_ts = key_to_ts(dates[#dates])
else
    view = "IMPORT"
end
draw_view_full()

while true do
    local k = minitel.get_key()
    if k then
        local ku = string.upper(k)

        if k == "RETOUR" or k == "SOMMAIRE" then
            break

        elseif k == "REPETITION" then
            draw_view_full()

        elseif k == "1" or k == "2" or k == "3" or k == "4" then
            switch_view(TABS[tonumber(k)][3])

        elseif k == "SUITE" or k == "\t" then
            switch_view(TABS[(TAB_ORDER[view] % #TABS) + 1][3])

        elseif k == "GUIDE" then
            minitel.msg_box("AIDE 3615 SANTE", "Onglets [1]-[4]. Q/D : jour precedent/suivant. Z/S : courbe ou seance. Import : onglet [4].")
            draw_view_full()

        elseif view == "JOUR" then
            if k == "LEFT" or ku == "Q" then step_day(-1); update_day()
            elseif k == "RIGHT" or ku == "D" then step_day(1); update_day()
            elseif k == "HOME" and #dates > 0 then sel_ts = key_to_ts(dates[1]); update_day()
            elseif k == "END" and #dates > 0 then sel_ts = key_to_ts(dates[#dates]); update_day()
            end

        elseif view == "COURBES" then
            if k == "LEFT" or ku == "Q" then chart_move(-1); update_chart()
            elseif k == "RIGHT" or ku == "D" then chart_move(1); update_chart()
            elseif k == "PAGE_UP" then
                chart_end_ts = chart_end_ts - CONFIG.CHART_DAYS * 86400
                sel_ts = chart_end_ts - (CONFIG.CHART_DAYS - chart_cur) * 86400
                update_chart()
            elseif k == "PAGE_DOWN" then
                chart_end_ts = math.min(chart_end_ts + CONFIG.CHART_DAYS * 86400,
                    math.max(today_ts(), key_to_ts(dates[#dates] or ts_to_key(today_ts()))))
                sel_ts = chart_end_ts - (CONFIG.CHART_DAYS - chart_cur) * 86400
                update_chart()
            elseif k == "UP" or ku == "Z" then
                chart_metric = (chart_metric > 1) and (chart_metric - 1) or #CHARTS
                update_chart()
            elseif k == "DOWN" or ku == "S" then
                chart_metric = (chart_metric < #CHARTS) and (chart_metric + 1) or 1
                update_chart()
            elseif k == "ENVOI" then
                goto_day(ts_to_key(sel_ts))
            end

        elseif view == "SEANCES" then
            if k == "UP" or ku == "Z" then wk_move(-1)
            elseif k == "DOWN" or ku == "S" then wk_move(1)
            elseif k == "PAGE_UP" then wk_move(-wk_visible)
            elseif k == "PAGE_DOWN" then wk_move(wk_visible)
            elseif k == "ENVOI" and data.workouts[wk_cursor] then
                goto_day(data.workouts[wk_cursor].d)
            end

        elseif view == "IMPORT" then
            if k == "ENVOI" then
                local path = find_export()
                if path then
                    if import_export(path) then after_data_change() else draw_view_full() end
                else
                    minitel.msg_box("AUCUN FICHIER", "Deposez exportation.zip (ou export.xml) dans " .. CONFIG.DOSSIER .. " puis reessayez.", "lose")
                    draw_view_full()
                end
            elseif ku == "F" then
                local path = minitel.file_browser("OPEN", CONFIG.DOSSIER)
                draw_view_full()
                if path then
                    if import_export(path) then after_data_change() else draw_view_full() end
                end
            elseif ku == "D" then
                if not data.meta or minitel.confirm_box("DONNEES DEMO", "Remplacer le carnet actuel par 120 jours de donnees fictives ?") then
                    generate_demo()
                    minitel.play_sound("pickup")
                    after_data_change()
                else
                    draw_view_full()
                end
            elseif ku == "X" and data.meta then
                if minitel.confirm_box("EFFACER LE CARNET", "Supprimer toutes les donnees importees ? (l'export reste intact)") then
                    os.remove(CONFIG.CACHE)
                    load_cache()
                    after_data_change()
                else
                    draw_view_full()
                end
            end
        end
    end
    minitel.sleep(0.01)
end

minitel.cleanup()
