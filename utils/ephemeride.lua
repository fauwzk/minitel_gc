-- Fichier : utils/ephemeride.lua
-- 3615 EPHEMERIDE : fete du jour, jours feries, soleil, lune et "il y a
-- 40 ans", tout calcule sur le Raspberry Pi, sans reseau.
-- @TYPE: CALENDRIER / ASTRONOMIE
-- @DESC: Fete du jour, jours feries, lever et coucher du soleil, phase de la lune et il y a 40 ans aujourd'hui. Sans connexion.
-- @ART1:        \  |  /     _.._
-- @ART2:      -- (   ) --  (   ')
-- @ART3:        /  |  \     '--'
-- @ART4:     LUN 26 OCT  FETE : DIMITRI
-- @ART5:     LEVER 08:23  COUCHER 18:08

local minitel = require("minitel")
minitel.init()

local CFG_FILE = "utils/ephemeride.cfg"
local YEARS_AGO = 40

local JOURS = { "DIMANCHE", "LUNDI", "MARDI", "MERCREDI", "JEUDI", "VENDREDI", "SAMEDI" }
local MOIS = { "JANVIER", "FEVRIER", "MARS", "AVRIL", "MAI", "JUIN", "JUILLET",
               "AOUT", "SEPTEMBRE", "OCTOBRE", "NOVEMBRE", "DECEMBRE" }
local MOIS_COURT = { "JANV.", "FEVR.", "MARS", "AVRIL", "MAI", "JUIN", "JUIL.",
                     "AOUT", "SEPT.", "OCT.", "NOV.", "DEC." }

-- =====================================================================
-- DONNEES : FETES, HISTOIRE, LIEU
-- =====================================================================
local saints, history = {}, {}

local function load_data()
    local f = io.open("utils/ephemeride_saints.txt", "r")
    if f then
        for l in f:lines() do
            local md, name = l:match("^(%d%d%-%d%d)|(.+)$")
            if md then saints[md] = name end
        end
        f:close()
    end
    f = io.open("utils/ephemeride_histoire.txt", "r")
    if f then
        for l in f:lines() do
            local md, y, ev = l:match("^(%d%d%-%d%d)|(%d+)|(.+)$")
            if md then
                history[md] = history[md] or {}
                table.insert(history[md], { year = tonumber(y), text = minitel.clean_accents(ev) })
            end
        end
        f:close()
    end
end

-- Lieu pour le soleil (Paris par defaut), modifiable avec [V]
local place = { name = "PARIS", lat = 48.8566, lon = 2.3522 }

local function load_place()
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    for l in f:lines() do
        local k, v = l:match("^(%w+)=(.*)$")
        if k == "name" then place.name = v
        elseif k == "lat" and tonumber(v) then place.lat = tonumber(v)
        elseif k == "lon" and tonumber(v) then place.lon = tonumber(v) end
    end
    f:close()
end

local function save_place()
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    f:write(string.format("name=%s\nlat=%.4f\nlon=%.4f\n", place.name, place.lat, place.lon))
    f:close()
end

-- =====================================================================
-- CALENDRIER
-- =====================================================================
local function day_of(y, m, d)
    return os.time({ year = y, month = m, day = d, hour = 12 })
end

local function ymd(t)
    local d = os.date("*t", t)
    return d.year, d.month, d.day, d
end

-- Paques (calcul de Meeus / Jones / Butcher, calendrier gregorien)
local function easter(y)
    local a, b, c = y % 19, y // 100, y % 100
    local d, e = b // 4, b % 4
    local f = (b + 8) // 25
    local g = (b - f + 1) // 3
    local h = (19 * a + b - d - g + 15) % 30
    local i, k = c // 4, c % 4
    local l = (32 + 2 * e + 2 * i - h - k) % 7
    local m = (a + 11 * h + 22 * l) // 451
    local month = (h + l - 7 * m + 114) // 31
    local day = ((h + l - 7 * m + 114) % 31) + 1
    return day_of(y, month, day)
end

local function holidays(y)
    local list = {
        { day_of(y, 1, 1), "JOUR DE L'AN" }, { day_of(y, 5, 1), "FETE DU TRAVAIL" },
        { day_of(y, 5, 8), "VICTOIRE 1945" }, { day_of(y, 7, 14), "FETE NATIONALE" },
        { day_of(y, 8, 15), "ASSOMPTION" }, { day_of(y, 11, 1), "TOUSSAINT" },
        { day_of(y, 11, 11), "ARMISTICE 1918" }, { day_of(y, 12, 25), "NOEL" },
    }
    local e = easter(y)
    for _, x in ipairs({ { 0, "PAQUES" }, { 1, "LUNDI DE PAQUES" }, { 39, "ASCENSION" },
                         { 49, "PENTECOTE" }, { 50, "LUNDI DE PENTECOTE" } }) do
        local yy, mm, dd = ymd(e + x[1] * 86400)
        list[#list + 1] = { day_of(yy, mm, dd), x[2] }
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

local function holiday_on(t)
    local y, m, d = ymd(t)
    for _, h in ipairs(holidays(y)) do
        local hy, hm, hd = ymd(h[1])
        if hm == m and hd == d then return h[2] end
    end
    return nil
end

local function next_holiday(t)
    local y = ymd(t)
    for _, yy in ipairs({ y, y + 1 }) do
        for _, h in ipairs(holidays(yy)) do
            if h[1] > t + 43200 then return h end
        end
    end
end

-- Numero de semaine ISO 8601 (la semaine 1 contient le premier jeudi)
local function iso_week(t)
    local d = os.date("*t", t)
    local wday = (d.wday + 5) % 7 + 1 -- lundi = 1 ... dimanche = 7
    local thursday = t + (4 - wday) * 86400
    local ty = os.date("*t", thursday)
    return (ty.yday - 1) // 7 + 1
end

-- =====================================================================
-- ASTRONOMIE (SOLEIL ET LUNE)
-- =====================================================================
local rad, deg = math.pi / 180, 180 / math.pi

-- Ecart de l'heure locale (ete compris) avec l'heure UTC, en secondes
local function utc_offset(t)
    local loc, utc = os.date("*t", t), os.date("!*t", t)
    utc.isdst = loc.isdst
    return os.difftime(os.time(loc), os.time(utc))
end

-- Equation du lever du soleil : rend lever, coucher (heures locales en
-- secondes depuis minuit) ou nil (jour ou nuit polaire)
local function sun_times(t)
    local y, m, d = ymd(t)
    local noon_utc = os.time({ year = y, month = m, day = d, hour = 12 }) + utc_offset(t)
    local jd = noon_utc / 86400 + 2440587.5
    local n = math.floor(jd - 2451545.0 + 0.0008 + 0.5)
    local jstar = n - place.lon / 360
    local M = (357.5291 + 0.98560028 * jstar) % 360
    local C = 1.9148 * math.sin(M * rad) + 0.02 * math.sin(2 * M * rad) + 0.0003 * math.sin(3 * M * rad)
    local lambda = (M + C + 180 + 102.9372) % 360
    local jtransit = 2451545.0 + jstar + 0.0053 * math.sin(M * rad) - 0.0069 * math.sin(2 * lambda * rad)
    local sin_dec = math.sin(lambda * rad) * math.sin(23.4397 * rad)
    local cos_dec = math.cos(math.asin(sin_dec))
    local cos_w = (math.sin(-0.833 * rad) - math.sin(place.lat * rad) * sin_dec) / (math.cos(place.lat * rad) * cos_dec)
    local function to_local(j)
        local unix = (j - 2440587.5) * 86400
        local lt = os.date("*t", math.floor(unix + 0.5))
        return lt.hour * 3600 + lt.min * 60 + lt.sec
    end
    if cos_w > 1 or cos_w < -1 then return nil, nil, to_local(jtransit), cos_w > 1 and "NUIT POLAIRE" or "JOUR POLAIRE" end
    local w = math.acos(cos_w) * deg
    return to_local(jtransit - w / 360), to_local(jtransit + w / 360), to_local(jtransit)
end

local function hhmm(s)
    if not s then return "--:--" end
    return string.format("%02d:%02d", s // 3600, (s % 3600) // 60)
end

local SYNODIC = 29.530588853

-- Age de la lune en jours (0 = nouvelle lune), d'apres la nouvelle lune du
-- 6 janvier 2000 a 18 h 14 UTC
local function moon_age(t)
    local jd = t / 86400 + 2440587.5 -- t : instant Unix (UTC)
    return (jd - 2451550.26) % SYNODIC
end

local PHASES = {
    { 1.84, "NOUVELLE LUNE" }, { 5.53, "PREMIER CROISSANT" }, { 9.22, "PREMIER QUARTIER" },
    { 12.91, "GIBBEUSE CROISSANTE" }, { 16.61, "PLEINE LUNE" }, { 20.30, "GIBBEUSE DECROISSANTE" },
    { 23.99, "DERNIER QUARTIER" }, { 27.68, "DERNIER CROISSANT" }, { 99, "NOUVELLE LUNE" },
}

local function moon_phase(age)
    for i, p in ipairs(PHASES) do
        if age < p[1] then return p[2], i end
    end
end

-- Dessin de la lune (partie eclairee en #) : 5 lignes de 11 caracteres
local function moon_art(age)
    local lines = {}
    local frac = age / SYNODIC                       -- 0 nouvelle, 0.5 pleine
    local k = math.cos(2 * math.pi * frac)           -- 1 nouvelle ... -1 pleine
    for row = 1, 5 do
        local yv = (row - 3) / 2.2
        local half = math.sqrt(math.max(0, 1 - yv * yv))
        local s = {}
        for col = 1, 11 do
            local xv = (col - 6) / 5
            local c = " "
            if math.abs(xv) <= half then
                -- terminateur : x = k * demi-largeur ; croissante = cote droit eclaire
                local term = k * half
                local lit
                if frac < 0.5 then lit = xv >= term else lit = xv <= -term end
                c = lit and "#" or "."
            end
            s[col] = c
        end
        lines[row] = table.concat(s)
    end
    return lines
end

local function next_phase(t, target_age, name)
    local age = moon_age(t)
    local wait = (target_age - age) % SYNODIC
    if wait < 0.5 then wait = wait + SYNODIC end
    return math.floor(t + wait * 86400), name
end

-- =====================================================================
-- AFFICHAGE
-- =====================================================================
local function date_long(t)
    local y, m, d, dt = ymd(t)
    return string.format("%s %d %s %d", JOURS[dt.wday], d, MOIS[m], y)
end

local function date_short(t)
    local y, m, d, dt = ymd(t)
    return string.format("%s %d %s", string.sub(JOURS[dt.wday], 1, 3), d, MOIS_COURT[m])
end

local function put(y, x, w, text, attr)
    io.write(string.format("\x1b[%d;%dH%s%s%s", y, x, attr or "", minitel.pad(text, w), attr and "\x1b[0m" or ""))
end

local function draw_static()
    io.write("\x1b[0m\x1b[2J")
    minitel.draw_frame(1, 3, 40, 10, "LE JOUR")
    minitel.draw_frame(41, 3, 40, 10, "LE SOLEIL")
    minitel.draw_frame(1, 13, 40, 10, "LA LUNE")
    minitel.draw_frame(41, 13, 40, 10, "IL Y A " .. YEARS_AGO .. " ANS")
    minitel.footer("[Q/D] JOUR -/+ [Z/S] MOIS -/+ [T] AUJOURD'HUI [V] VILLE [RETOUR] QUITTER")
end

local function draw(t)
    local y, m, d, dt = ymd(t)
    local md = string.format("%02d-%02d", m, d)
    local today = os.date("*t")
    local is_today = today.year == y and today.yday == dt.yday
    minitel.title_bar("3615 EPHEMERIDE - " .. date_long(t) .. (is_today and "" or "  (CONSULTATION)"))

    -- Le jour
    local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
    put(5, 3, 36, date_long(t), "\x1b[1m")
    put(6, 3, 36, string.format("SEMAINE %d  -  JOUR %d / %d", iso_week(t), dt.yday, leap and 366 or 365))
    put(8, 3, 36, "FETE : " .. (saints[md] or "?"))
    local hol = holiday_on(t)
    put(9, 3, 36, hol and ("JOUR FERIE : " .. hol) or "", hol and "\x1b[7m" or nil)
    local nh = next_holiday(t)
    if nh then
        local days = math.floor((nh[1] - t) / 86400 + 0.5)
        put(10, 3, 36, "PROCHAIN FERIE : " .. nh[2])
        put(11, 3, 36, string.format("  %s, DANS %d JOUR%s", date_short(nh[1]), days, days > 1 and "S" or ""))
    end

    -- Le soleil
    local rise, set, transit, polar = sun_times(t)
    local rise_y, set_y = sun_times(t - 86400)
    put(5, 43, 36, string.format("%s (%.2f, %.2f)", place.name, place.lat, place.lon), "\x1b[1m")
    if polar then
        put(7, 43, 36, polar)
        put(8, 43, 36, ""); put(9, 43, 36, "")
    else
        put(7, 43, 36, "LEVER    : " .. hhmm(rise))
        put(8, 43, 36, "COUCHER  : " .. hhmm(set))
        local len = set - rise
        local diff = (rise_y and set_y) and (len - (set_y - rise_y)) or 0
        put(9, 43, 36, string.format("DUREE    : %dH%02d  (%s%d MIN / VEILLE)", len // 3600, (len % 3600) // 60,
            diff >= 0 and "+" or "-", math.floor(math.abs(diff) / 60 + 0.5)))
    end
    put(10, 43, 36, "MIDI SOLAIRE : " .. hhmm(transit))
    put(11, 43, 36, "")

    -- La lune (a midi)
    local age = moon_age(t)
    local name = moon_phase(age)
    local lit = (1 - math.cos(2 * math.pi * age / SYNODIC)) / 2
    local art = moon_art(age)
    for i = 1, 5 do put(14 + i, 3, 11, art[i]) end
    put(15, 16, 23, name, "\x1b[1m")
    put(16, 16, 23, string.format("ECLAIREE A %d %%", math.floor(lit * 100 + 0.5)))
    put(17, 16, 23, string.format("AGE : %.1f JOURS", age))
    local fm = next_phase(t, SYNODIC / 2, "PLEINE")
    local nm = next_phase(t, 0, "NOUVELLE")
    put(19, 16, 23, "PLEINE   : " .. date_short(fm))
    put(20, 16, 23, "NOUVELLE : " .. date_short(nm))

    -- Il y a 40 ans
    local past = day_of(y - YEARS_AGO, m, d)
    local pname = moon_phase(moon_age(past))
    put(15, 43, 36, date_long(past), "\x1b[1m")
    local phol = holiday_on(past)
    put(16, 43, 36, phol and ("FERIE : " .. phol) or ("LUNE : " .. pname))
    local evs = history[md] or {}
    table.sort(evs, function(a, b)
        local da, db = math.abs(a.year - (y - YEARS_AGO)), math.abs(b.year - (y - YEARS_AGO))
        return da < db
    end)
    put(18, 43, 36, #evs > 0 and "CE JOUR-LA DANS L'HISTOIRE :" or "RIEN DANS LES ARCHIVES CE JOUR-LA")
    for i = 1, 3 do
        local e = evs[i]
        local text = e and (e.year .. " : " .. e.text) or ""
        put(18 + i, 43, 36, text, e and e.year == y - YEARS_AGO and "\x1b[7m" or nil)
    end
    io.write("\x1b[24;80H")
    io.flush()
end

local function ask_place()
    local name = minitel.input_box("VILLE", "NOM DU LIEU :", place.name, 20)
    if not name then return end
    local lat = tonumber(minitel.input_box("VILLE", "LATITUDE (NORD +, EX. 48.85) :", tostring(place.lat), 10) or "")
    local lon = tonumber(minitel.input_box("VILLE", "LONGITUDE (EST +, EX. 2.35) :", tostring(place.lon), 10) or "")
    if lat and lon and math.abs(lat) <= 90 and math.abs(lon) <= 180 then
        place.name = string.upper(minitel.clean_accents(name))
        place.lat, place.lon = lat, lon
        save_place()
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
load_data()
load_place()

local function today()
    local n = os.date("*t")
    return day_of(n.year, n.month, n.day)
end

local cur = today()
draw_static()
draw(cur)

local last_day = os.date("%j")
while true do
    local k = minitel.get_key()
    local nt
    if k then
        local y, m, d = ymd(cur)
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "d" or k == "D" or k == "RIGHT" then nt = cur + 86400
        elseif k == "q" or k == "Q" or k == "LEFT" then nt = cur - 86400
        elseif k == "s" or k == "S" or k == "DOWN" or k == "z" or k == "Z" or k == "UP" then
            m = m + ((k == "s" or k == "S" or k == "DOWN") and 1 or -1)
            if m > 12 then m, y = 1, y + 1 elseif m < 1 then m, y = 12, y - 1 end
            d = math.min(d, os.date("*t", day_of(y, m + 1, 0)).day)
            nt = day_of(y, m, d)
        elseif k == "t" or k == "T" then nt = today()
        elseif k == "v" or k == "V" then ask_place(); draw_static(); nt = cur
        elseif k == "REPETITION" then draw_static(); nt = cur
        end
    elseif os.date("%j") ~= last_day then
        -- minuit passe : on suit le nouveau jour s'il etait affiche
        last_day = os.date("%j")
        if os.date("%j", cur + 86400) == last_day then nt = today() end
    end
    if nt then
        -- midi du jour vise, pour rester sur la bonne date au changement d'heure
        local y, m, d = ymd(nt)
        cur = day_of(y, m, d)
        draw(cur)
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
