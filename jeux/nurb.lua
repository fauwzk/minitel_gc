-- @GENRE: COURSE / SIMULATION AUTO
-- @DESC: Domptez les 20,8 km de la Nordschleife en Touristenfahrten. Gerez freins, pneus, meteo et signez le record BTG !

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local REC_FILE = "jeux/nordschleife.rec"

-- =====================================================================
-- 1. BASE DE DONNEES DES VEHICULES & DES 10 SECTEURS (100% ASCII PUR)
-- =====================================================================
local CARS = {
    {
        id = "MARBELLA",
        name = "CITADINE 900CC (40 CH - 680 KG)",
        short = "CITADINE 900CC",
        base_btg = 670,
        power = 3,
        weight = 2,
        grip = 6,
        desc = "Poids plume indestructible ! Freins inusables, mais chaque relance en cote demande une trajectoire parfaite."
    },
    {
        id = "ZX_SWAP",
        name = "COMPACTE SWAP 2.2L (170 CH - 1080 KG)",
        short = "COMPACTE 2.2L",
        base_btg = 515,
        power = 7,
        weight = 5,
        grip = 8,
        desc = "Preparation piste equilibree (gestion standalone). Redoutable dans Hatzenbach et Hohe Acht."
    },
    {
        id = "V6_GT",
        name = "BERLINE ROUTIERE V6 (210 CH - 1580 KG)",
        short = "BERLINE V6",
        base_btg = 535,
        power = 9,
        weight = 9,
        grip = 7,
        desc = "Allonge impressionnante dans Kesselchen et Dottinger Hohe, mais attention au fading des freins !"
    }
}

local SECTORS = {
    {
        name = "01. BRIDGE -> HATZENBACH",
        km = "2.2K",
        type = "TECHNIQUE",
        brake_load = 12, tire_load = 10, eng_load = 8,
        art = {
            "      ||  [ PONT BILSTEIN ]  ||     ",
            "     /  \\                   /  \\    ",
            "    |    '--.           .--'    |   ",
            "     \\       '-.     .-'       /    "
        },
        info = "Passage sous le pont ! Enchainement rapide gauche-droite sur les vibreurs de Hatzenbach."
    },
    {
        name = "02. FLUGPLATZ -> SCHWEDENKREUZ",
        km = "2.3K",
        type = "HAUTE VITESSE",
        brake_load = 16, tire_load = 14, eng_load = 15,
        art = {
            "          .-------.                 ",
            "        .' CRETE   '.    /\\         ",
            "   ____/  FLUGPLATZ  \\__/  \\____    ",
            "  ==============================    "
        },
        info = "Delestage sur la bosse de Flugplatz puis pleine charge jusqu'au freinage en appui d'Aremberg !"
    },
    {
        name = "03. FUCHSROHRE -> ADENAUER F.",
        km = "2.1K",
        type = "GROS FREINAGE",
        brake_load = 24, tire_load = 15, eng_load = 12,
        art = {
            "   \\  \\                       /  /  ",
            "    \\  \\   [ COMPRESSION ]   /  /   ",
            "     \\  '-------------------'  /    ",
            "      '-----------------------'     "
        },
        info = "Descente vertigineuse dans le tube de Fuchsrohre suivie de la chicane piegeuse d'Adenauer Forst."
    },
    {
        name = "04. METZGESFELD -> WEHRSEIFEN",
        km = "2.0K",
        type = "SINUEUX",
        brake_load = 18, tire_load = 12, eng_load = 9,
        art = {
            "         .---.                      ",
            "        /     \\       .----.        ",
            "   ----'       '-----'      '----   ",
            "                                    "
        },
        info = "Section rapide a Kallenhard puis plongee vers l'epingle la plus lente du circuit a Wehrseifen."
    },
    {
        name = "05. BREIDSCHEID -> EX-MUHLE",
        km = "1.8K",
        type = "FORTE MONTEE",
        brake_load = 14, tire_load = 13, eng_load = 18,
        art = {
            "                      .---'         ",
            "                 .---'  EX-MUHLE    ",
            "            .---'                   ",
            "   ========'  [PONT BREIDSCHEID]    "
        },
        info = "Point le plus bas du circuit (320m) suivi de la rampe abrupte d'Ex-Muhle. Le couple moteur parle !"
    },
    {
        name = "06. BERGWERK -> KESSELCHEN",
        km = "2.8K",
        type = "PLEINE CHARGE",
        brake_load = 10, tire_load = 11, eng_load = 24,
        art = {
            "     /  /   /  /   /  /   /  /      ",
            "    /  /   [ MUTTKURVE ] /  /       ",
            "   /  /                 /  /        ",
            "  /  /                 /  /         "
        },
        info = "Sortie cruciale a Bergwerk : elle conditionne toute la longue montee a fond de Kesselchen !"
    },
    {
        name = "07. CARACCIOLA KARUSSELL",
        km = "1.5K",
        type = "BANKING BETON",
        brake_load = 14, tire_load = 20, eng_load = 10,
        is_karussell = true,
        art = {
            "        .==================.        ",
            "      .'  ################  '.      ",
            "     |   # DALLES BETON 27% # |     ",
            "      '.  ################  .'      "
        },
        info = "Le mythique virage releve en dalles de beton ! Plonger a la corde fait gagner 3s mais secoue l'auto."
    },
    {
        name = "08. HOHE ACHT -> WIPPERMANN",
        km = "2.2K",
        type = "MONTAGNES RUSSES",
        brake_load = 16, tire_load = 18, eng_load = 12,
        art = {
            "       /\\    /\\    /\\    /\\         ",
            "      /  \\  /  \\  /  \\  /  \\        ",
            "     /    \\/    \\/    \\/    \\       ",
            "    [ POINT CULMINANT : 620M ]      "
        },
        info = "Sommet du circuit (620m) puis descente ultra-technique entre Hohe Acht, Hedwigshohe et Wippermann."
    },
    {
        name = "09. BRUNNCHEN -> PFLANZGARTEN",
        km = "2.1K",
        type = "SAUT & PUBLIC",
        brake_load = 18, tire_load = 16, eng_load = 11,
        art = {
            "   [PUBLIC PHOTO]      .---.        ",
            "   [o] [o] [o]       .' SAUT '.     ",
            "  ==================/         \\===  ",
            "                                    "
        },
        info = "Les photographes de Racetracker vous attendent a Brunnchen ! Puis le celebre saut de Pflanzgarten."
    },
    {
        name = "10. SCHWALBENSCHWANZ -> GANTRY",
        km = "1.8K",
        type = "SPRINT FINAL",
        brake_load = 8, tire_load = 10, eng_load = 20,
        art = {
            "   ================================ ",
            "   |    [ GANTRY AUDI SPORT ]     | ",
            "   |        CHRONO FINAL !        | ",
            "   ================================ "
        },
        info = "Petit Karussell, Galgenkopf et c'est la ligne droite de Dottinger Hohe jusqu'au portique Gantry !"
    }
}

-- =====================================================================
-- 2. GESTION DES RECORDS BTG SUR DISQUE
-- =====================================================================
local records = {
    MARBELLA = { time = 665.4, driver = "FANTOME_52" },
    ZX_SWAP  = { time = 508.2, driver = "FANTOME_52" },
    V6_GT    = { time = 524.8, driver = "FANTOME_52" }
}

local function load_records()
    local f = loadfile(REC_FILE)
    if f then
        local ok, data = pcall(f)
        if ok and type(data) == "table" then records = data end
    end
end

local function save_records()
    local f = io.open(REC_FILE, "w")
    if f then
        f:write("return {\n")
        for k, v in pairs(records) do
            f:write(string.format("  %s = { time = %.2f, driver = %q },\n", k, v.time, v.driver))
        end
        f:write("}\n")
        f:close()
    end
end

load_records()

local function format_btg(sec)
    local m = math.floor(sec / 60)
    local s = sec - (m * 60)
    return string.format("%02d'%05.2f\"", m, s)
end

-- =====================================================================
-- 3. SELECTION DU VEHICULE & REGLAGES PADDOCK (DELTA-DRAWING)
-- =====================================================================
local function choose_car_and_setup()
    local cur = 1

    local function draw_car_rows_and_specs()
        for i, c in ipairs(CARS) do
            local y = 4 + (i * 2)
            local rec = records[c.id] and format_btg(records[c.id].time) or "AUCUN"
            local line = string.format(" %d. %-38s | RECORD: %s (%s)", i, c.name, rec, string.sub(records[c.id].driver, 1, 10))
            if i == cur then
                io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 74)))
            else
                io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 74)))
            end
        end

        local sel = CARS[cur]
        local t_str = " FICHE TECHNIQUE : " .. sel.short .. " "
        io.write(string.format("\x1b[15;2H\x1b[1m+\x1b[0m\x1b[7m%s\x1b[0m\x1b[1m+\x1b[0m", minitel.center(t_str, 76)))

        io.write("\x1b[17;4HPUISSANCE : ")
        minitel.progress_bar(16, 17, 22, sel.power, 10, false)
        io.write("\x1b[17;42HLEGERETE  : ")
        minitel.progress_bar(54, 17, 22, 11 - sel.weight, 10, false)
        io.write("\x1b[18;4HCHASSIS   : ")
        minitel.progress_bar(16, 18, 22, sel.grip, 10, false)

        local d_lines = minitel.wrap(sel.desc, 72, 2)
        io.write("\x1b[20;4H" .. minitel.pad(d_lines[1], 72))
        io.write("\x1b[21;4H" .. minitel.pad(d_lines[2], 72))
        io.flush()
    end

    local function draw_garage_static()
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 NORDSCHLEIFE - PADDOCK TOURISTENFAHRTEN  * * *", 80) .. "\x1b[0m")
        minitel.draw_window(2, 3, 78, 11, "CHOIX DU VEHICULE POUR LE TOUR BTG (20.8 KM)")
        minitel.draw_window(2, 15, 78, 8, "FICHE TECHNIQUE")
        io.write("\x1b[24;1H\x1b[7m  [Z/S] CHOISIR AUTO   |   [ENVOI] VALIDER & REGLER   |   [RETOUR] QUITTER      \x1b[0m")
        draw_car_rows_and_specs()
    end

    draw_garage_static()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then return nil, nil
        elseif k == "UP" or k == "Z" or k == "z" then
            cur = (cur > 1) and (cur - 1) or #CARS
            minitel.play_sound("hit")
            draw_car_rows_and_specs()
        elseif k == "DOWN" or k == "S" or k == "s" then
            cur = (cur < #CARS) and (cur + 1) or 1
            minitel.play_sound("hit")
            draw_car_rows_and_specs()
        elseif k == "ENVOI" or k == " " then
            minitel.play_sound("pickup")
            break
        end
        minitel.sleep(0.02)
    end

    local semi_slick = minitel.confirm_box(
        "MONTE PNEUMATIQUE",
        "Monter des pneus SEMI-SLICK ? (OUI = Gain de 12s sur le sec mais usure rapide / NON = Pneus Route endurants)"
    )

    return CARS[cur], semi_slick
end

-- =====================================================================
-- 4. MOTEUR DE COURSE SECTEUR PAR SECTEUR (SQUELETTE STATIQUE + DELTA)
-- =====================================================================
local function run_lap(car, semi_slick)
    local tire_hp   = 100
    local brake_tmp = 25
    local eng_tmp   = 85
    local fuel_pct  = 100
    local cur_time  = 0
    local target_base = car.base_btg - (semi_slick and 12 or 0)
    local last_event = "BARRIERE DE PEAGE OUVERTE ! BON TOUR DANS L'ENFER VERT !"

    local weather_types = {"PISTE SECHE (18 C)", "FRAIS & GRIP OPTIMAL (12 C)", "AVERSES SUR HOHE ACHT !"}
    local weather_idx = math.random(1, 10) <= 7 and 1 or (math.random(1, 2) + 1)
    local weather_str = weather_types[weather_idx]

    -- Dessin initial unique des 3 cadres de course (evite tout clignotement entre les 10 secteurs !)
    local function draw_race_skeleton()
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)

        local top = string.format("3615 NORDSCHLEIFE | %s | METEO: %s", car.short, weather_str)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

        minitel.draw_window(2, 3, 44, 14, "SECTEUR")
        io.write("\x1b[9;2H\x1b[1m+------------------------------------------+\x1b[0m")

        minitel.draw_window(47, 3, 33, 14, "TELEMETRIE EMBARQUEE")
        io.write("\x1b[5;49HADHERENCE PNEUS :")
        io.write("\x1b[8;49HTEMPERATURE FREINS :")
        io.write("\x1b[14;49HCARBURANT :")

        minitel.draw_window(2, 18, 78, 5, "RADIO PISTE & RYTHME DE PILOTAGE")
        io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2] OU [3] POUR FRANCHIR LE SECTEUR   |   [RETOUR] ABANDONNER      \x1b[0m")
        io.flush()
    end

    draw_race_skeleton()

    for s_idx, sec in ipairs(SECTORS) do
        local sec_base_time = target_base / #SECTORS

        -- 1. Mise a jour chirurgicale de la fenetre Secteur (Gauche : X=2, W=44, interieur=42)
        local sec_title = " " .. sec.name .. " (" .. sec.km .. ") "
        io.write(string.format("\x1b[3;2H\x1b[1m+\x1b[0m\x1b[7m%s\x1b[0m\x1b[1m+\x1b[0m", minitel.center(sec_title, 42)))

        for i = 1, 4 do
            io.write(string.format("\x1b[%d;4H\x1b[1m%s\x1b[0m", 4 + i, minitel.center(sec.art[i] or "", 40)))
        end

        local prof_str = string.format("PROFIL : \x1b[7m %-18s \x1b[0m", sec.type)
        io.write("\x1b[10;4H" .. prof_str .. string.rep(" ", 11))

        local desc_w = minitel.wrap(sec.info, 40, 3)
        for i = 1, 3 do
            io.write(string.format("\x1b[%d;4H%s", 11 + i, minitel.pad(desc_w[i], 40)))
        end
        io.write(string.format("\x1b[15;4HCHRONO CUMULE : \x1b[1m%-24s\x1b[0m", format_btg(cur_time)))

        -- 2. Mise a jour des jauges de Telemetrie (Droite)
        minitel.progress_bar(49, 6, 29, tire_hp, 100, true)
        minitel.progress_bar(49, 9, 29, brake_tmp, 100, true)
        io.write(string.format("\x1b[11;49HTEMP. EAU/HUILE : %3d C    ", eng_tmp))
        minitel.progress_bar(49, 12, 29, math.max(0, eng_tmp - 60), 70, false)
        minitel.progress_bar(49, 15, 29, fuel_pct, 100, true)

        -- 3. Mise a jour de la boite Radio & Choix (Bas : X=2, W=78, interieur=76, de Col 3 a 78)
        io.write("\x1b[19;4H> " .. minitel.pad(last_event, 72))

        if sec.is_karussell then
            -- Exactement 73 caracteres (Col 4 a 76) : ne touche jamais la bordure Col 79 !
            io.write("\x1b[21;4H\x1b[7m[1]\x1b[0m EXTERIEUR (+2s)   | \x1b[7m[2]\x1b[0m DALLES BETON (-3.2s)  | \x1b[7m[3]\x1b[0m ATTAQUE MAXIMALE ")
        else
            io.write("\x1b[21;4H\x1b[7m[1]\x1b[0m ENROULER / COOL   | \x1b[7m[2]\x1b[0m TRAJECTOIRE PROPRE    | \x1b[7m[3]\x1b[0m ATTAQUE MAXIMALE ")
        end
        io.flush()

        local choice = nil
        while not choice do
            local k = minitel.get_key()
            if k == "1" or k == "2" or k == "3" then
                choice = tonumber(k)
            elseif k == "REPETITION" then
                draw_race_skeleton()
                break
            elseif k == "RETOUR" or k == "ESC" then
                return
            end
            minitel.sleep(0.02)
        end

        if choice then
            minitel.play_sound("hit")

            local delta_t = 0
            local weight_factor = car.weight / 5.0
            local tire_wear_mult = semi_slick and 1.35 or 1.0

            if choice == 1 then
                delta_t = 2.8
                brake_tmp = math.max(20, brake_tmp - 18)
                eng_tmp   = math.max(82, eng_tmp - 5)
                tire_hp   = math.max(0, tire_hp - math.floor(sec.tire_load * 0.3 * tire_wear_mult))
                last_event = "Rythme souple : les freins et le moteur refroidissent."
            elseif choice == 2 then
                delta_t = -0.6
                if sec.is_karussell then delta_t = -3.2 end
                brake_tmp = math.min(100, brake_tmp + math.floor(sec.brake_load * 0.45 * weight_factor) - 6)
                eng_tmp   = math.min(130, eng_tmp + math.floor(sec.eng_load * 0.25) - 2)
                tire_hp   = math.max(0, tire_hp - math.floor(sec.tire_load * 0.55 * tire_wear_mult))
                last_event = sec.is_karussell and "Passage parfait dans le banking en beton du Karussell !" or "Belle trajectoire tendue a la corde !"
            elseif choice == 3 then
                delta_t = -3.1 - (car.power * 0.15)
                brake_tmp = math.min(100, brake_tmp + math.floor(sec.brake_load * 0.95 * weight_factor))
                eng_tmp   = math.min(130, eng_tmp + math.floor(sec.eng_load * 0.55))
                tire_hp   = math.max(0, tire_hp - math.floor(sec.tire_load * 0.95 * tire_wear_mult))
                last_event = "Attaque a la limite sur les vibreurs ! Gros gain au chrono."
            end

            if weather_idx == 3 and s_idx >= 7 and semi_slick and choice == 3 then
                minitel.play_sound("lose")
                delta_t = delta_t + 9.5
                last_event = "AQUAPLANING en Semi-Slick sous l'averse ! Grosse frayeur (+9.5s) !"
            elseif brake_tmp >= 88 and sec.brake_load >= 16 then
                minitel.play_sound("lose")
                delta_t = delta_t + 7.5
                brake_tmp = 75
                last_event = "PEDALE DE FREIN MOLLE (Fading) ! Vous tirez large dans l'herbe (+7.5s) !"
            elseif eng_tmp >= 115 then
                minitel.play_sound("lose")
                delta_t = delta_t + 6.0
                eng_tmp = 104
                last_event = "ALERTE TEMP. HUILE/EAU ! Vous devez soulager en ligne droite (+6.0s)."
            elseif tire_hp <= 25 and choice >= 2 then
                minitel.play_sound("lose")
                delta_t = delta_t + 5.5
                last_event = "PNEUS SUR LA TOILE ! Sous-virage prononce en courbe (+5.5s)."
            elseif s_idx == 9 and choice >= 2 then
                last_event = "FLASH PHOTO RACETRACKER.DE A BRUNNCHEN ! Passage spectaculaire !"
            end

            fuel_pct = math.max(5, fuel_pct - 9)
            cur_time = cur_time + sec_base_time + delta_t + (math.random(-40, 40) / 100.0)
        end
    end

    -- =====================================================================
    -- 5. ARRIVEE SOUS LE PORTIQUE GANTRY & CLASSEMENT BTG
    -- =====================================================================
    local prev_rec = records[car.id] and records[car.id].time or 9999
    local is_new_record = cur_time < prev_rec

    if is_new_record then
        minitel.play_sound("win")
        local drv = minitel.input_box(
            "NOUVEAU RECORD BTG : " .. format_btg(cur_time),
            "Entrez votre nom pour le classement officiel :",
            "PILOTE_52",
            14
        )
        if drv and drv ~= "" then
            records[car.id] = { time = cur_time, driver = string.upper(minitel.clean_accents(drv)) }
            save_records()
        end
    else
        minitel.msg_box(
            "ARRIVEE AU PORTIQUE GANTRY",
            string.format("Temps BTG : %s (Record categorie : %s par %s)",
                format_btg(cur_time), format_btg(prev_rec), records[car.id].driver),
            "pickup"
        )
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    local car, semi_slick = choose_car_and_setup()
    if not car then break end
    run_lap(car, semi_slick)
end

minitel.cleanup()