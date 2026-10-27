-- @GENRE: COURSE / ARCADE 3D
-- @DESC: Course d'arcade en Pseudo-3D temps reel ! Vibreurs animes, force centrifuge, trafic et Checkpoints chronometres !

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

-- =====================================================================
-- 1. TRACE DE LA ROUTE (SEGMENTS : LONGUEUR & COURBURE -2 A +2)
-- =====================================================================
local TRACK = {
    { len = 60,  curve = 0,    name = "LIGNE DROITE DU DEPART" },
    { len = 70,  curve = 1.2,  name = "GRANDE COURBE DE LA COTE" },
    { len = 50,  curve = -1.6, name = "GAUCHE RAPIDE DES PALMIERS" },
    { len = 45,  curve = 0,    name = "LIGNE DROITE DU BORD DE MER" },
    { len = 65,  curve = 2.0,  name = "EPINGLE DROITE DU ROCHER" },
    { len = 60,  curve = -1.8, name = "S DE LA FALAISE" },
    { len = 70,  curve = 1.4,  name = "COURBE DU SOLEIL COUCHANT" },
    { len = 80,  curve = -2.1, name = "GRAND GAUCHE DU CASINO" },
    { len = 70,  curve = 0,    name = "SPRINT VERS LE CHECKPOINT !" }
}

-- =====================================================================
-- 2. MOTEUR DE RENDU DIFFERENTIEL DE LA ROUTE PSEUDO-3D
-- =====================================================================
local ROAD_ROWS = 10 -- Lignes 10 a 19 sur l'ecran Minitel
local prev_slices = {}
local prev_car_scr_x = -1
local prev_rival_scr = { row = -1, x = -1 }

local hud_shown = {}

local function hud_put(slot, seq)
    if hud_shown[slot] ~= seq then
        hud_shown[slot] = seq
        io.write(seq)
    end
end

local function reset_render_cache()
    for i = 1, ROAD_ROWS do
        prev_slices[i] = { l = -1, r = -1, m = -1, rumble = false }
    end
    prev_car_scr_x = -1
    prev_rival_scr = { row = -1, x = -1 }
    hud_shown = {}
end

local function draw_cockpit_skeleton()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    reset_render_cache()

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 OUTRUN - TURBO ARCADE PSEUDO-3D  * * *", 80) .. "\x1b[0m")

    -- Tableau de bord superieur (Lignes 2 a 5)
    minitel.draw_window(2, 2, 78, 5, "")
    io.write("\x1b[3;4HTEMPS :        | VITESSE :            | RAPPORT :     | SCORE :          ")
    io.write("\x1b[4;4HSECTEUR :                                             | PROCHAIN CP :    ")

    -- Ligne d'horizon & Montagnes (Lignes 7 a 9)
    io.write("\x1b[8;2H    /\\      /\\  /\\        /\\            /\\      /\\        /\\  /\\      /\\    ")
    io.write("\x1b[9;1H" .. string.rep("=", 80))

    -- Bas de l'ecran (Ligne 24)
    io.write("\x1b[24;1H\x1b[7m [Q/D] VOLANT | [Z] GAZ | [S] FREIN | [E/A] BOITE +/- | [M] AUTO/MANU | [ESC]   \x1b[0m")
    io.flush()
end

-- Met a jour uniquement les bords de la route qui ont bouge !
local function render_road_frame(curve, player_x, dist_scroll, rival_z, rival_offset)
    local out = {}

    -- 1. Efface l'ancienne voiture rivale si elle etait visible
    if prev_rival_scr.row > 0 then
        table.insert(out, string.format("\x1b[%d;%dH     ", prev_rival_scr.row, prev_rival_scr.x))
        prev_rival_scr.row = -1
    end

    -- 2. Calcul et dessin differentiel des 10 tranches de perspective (i=1 horizon -> i=10 capot)
    for i = 1, ROAD_ROWS do
        local scr_y = 9 + i
        local depth = i / ROAD_ROWS -- 0.1 (loin) a 1.0 (proche)
        local inv_d = 1.0 - depth

        -- Effet de courbure quadratique vers l'horizon + decalage camera du joueur
        local curve_shift = math.floor(curve * inv_d * inv_d * 24)
        local cam_shift   = math.floor(-player_x * depth * 18)

        local center_x = 40 + curve_shift + cam_shift
        local half_w   = math.floor(5 + depth * 25) -- Largeur de 10 col en haut a 60 col en bas

        local left_x  = math.max(2, math.min(72, center_x - half_w))
        local right_x = math.max(8, math.min(77, center_x + half_w))
        local mid_x   = math.max(5, math.min(74, center_x))

        local phase = (math.floor(dist_scroll + ( ROAD_ROWS - i )) % 2) == 0
        local old = prev_slices[i]

        -- Si le bord gauche a bouge, on efface l'ancien
        if old.l > 0 and old.l ~= left_x then
            table.insert(out, string.format("\x1b[%d;%dH  ", scr_y, old.l))
        end
        -- Si le bord droit a bouge, on efface l'ancien
        if old.r > 0 and old.r ~= right_x then
            table.insert(out, string.format("\x1b[%d;%dH  ", scr_y, old.r))
        end
        -- Si la ligne blanche centrale a bouge, on l'efface
        if old.m > 0 and (old.m ~= mid_x or not phase) then
            table.insert(out, string.format("\x1b[%d;%dH ", scr_y, old.m))
        end

        -- Dessin des nouveaux vibreurs gauche/droite (alternance blanc/normal pour l'effet de vitesse !)
        if old.l ~= left_x or old.rumble ~= phase then
            local l_str = phase and "\x1b[7m//\x1b[0m" or "//"
            table.insert(out, string.format("\x1b[%d;%dH%s", scr_y, left_x, l_str))
        end
        if old.r ~= right_x or old.rumble ~= phase then
            local r_str = phase and "\x1b[7m\\\\\x1b[0m" or "\\\\"
            table.insert(out, string.format("\x1b[%d;%dH%s", scr_y, right_x, r_str))
        end

        -- Ligne centrale discontinue
        if phase then
            table.insert(out, string.format("\x1b[%d;%dH|", scr_y, mid_x))
        end

        old.l, old.r, old.m, old.rumble = left_x, right_x, mid_x, phase

        -- Dessin d'un concurrent sur la piste s'il se trouve sur cette tranche de profondeur
        if rival_z and math.floor(rival_z) == i then
            local rx = math.max(left_x + 3, math.min(right_x - 6, center_x + math.floor(rival_offset * half_w * 0.6) - 2))
            table.insert(out, string.format("\x1b[%d;%dH\x1b[1m[=O=]\x1b[0m", scr_y, rx))
            prev_rival_scr.row = scr_y
            prev_rival_scr.x   = rx
        end
    end

    -- 3. Dessin de la Ferrari / GT du joueur en bas de l'ecran (Lignes 21 et 22)
    local car_x = 34
    if prev_car_scr_x ~= car_x then
        table.insert(out, "\x1b[21;34H  ._______.")
        table.insert(out, "\x1b[22;34H\x1b[7m (O)==V==(O) \x1b[0m")
        prev_car_scr_x = car_x
    end

    io.write(table.concat(out))
end

-- =====================================================================
-- 3. BOUCLE DE COURSE TEMPS REEL
-- =====================================================================
local function run_arcade_race()
    draw_cockpit_skeleton()

    local speed = 0           -- 0 a 290 km/h
    local gear = 1            -- 1 a 5
    local auto_gear = true
    local player_x = 0.0      -- -1.2 (herbe gauche) a +1.2 (herbe droite)
    local dist_total = 0.0
    local seg_idx = 1
    local seg_progress = 0.0
    local cp_dist_left = 250
    local time_left = 45
    local score = 0

    -- Concurrent sur la route
    local rival_z = 2.0       -- 1 (horizon) a 10 (pare-chocs)
    local rival_offset = 0.4  -- -0.5 (voie gauche) a +0.5 (voie droite)

    local last_sec = os.time()
    local gear_max_speeds = { 75, 130, 185, 235, 290 }

    while time_left > 0 do
        -- 1. Lecture de TOUTES les touches en attente dans le buffer serie pour une direction ultra-reactive !
        local steer = 0
        local accel = 0
        while true do
            local k = minitel.get_key()
            if not k then break end

            if k == "RETOUR" or k == "ESC" then
                return score
            elseif k == "LEFT" or k == "Q" or k == "q" then
                steer = -1
            elseif k == "RIGHT" or k == "D" or k == "d" then
                steer = 1
            elseif k == "UP" or k == "Z" or k == "z" then
                accel = 1
            elseif k == "DOWN" or k == "S" or k == "s" then
                accel = -1
            elseif k == "M" or k == "m" then
                auto_gear = not auto_gear
            elseif k == "E" or k == "e" then
                auto_gear = false; gear = math.min(5, gear + 1)
            elseif k == "A" or k == "a" then
                auto_gear = false; gear = math.max(1, gear - 1)
            end
        end

        -- 2. Physique longitudinale (Boite de vitesses & Acceleration)
        if auto_gear then
            for g = 1, 5 do
                if speed <= gear_max_speeds[g] - 5 then gear = g; break end
            end
        end

        local max_g_spd = gear_max_speeds[gear]
        if accel == 1 then
            speed = math.min(max_g_spd, speed + (10 - gear))
        elseif accel == -1 then
            speed = math.max(0, speed - 22)
        else
            -- En arcade sur Minitel, l'accelerateur maintient un filet de gaz automatique si speed > 0 !
            if speed > 0 and speed < max_g_spd then
                speed = math.min(max_g_spd, speed + (6 - math.floor(gear / 2)))
            end
        end

        -- 3. Physique laterale (Volant + Force centrifuge dans les courbes)
        local seg = TRACK[seg_idx]
        if steer ~= 0 then
            player_x = player_x + (steer * 0.16)
        end
        if speed > 20 then
            -- Le virage pousse la voiture vers l'exterieur !
            player_x = player_x - (seg.curve * (speed / 290.0) * 0.085)
        end
        player_x = math.max(-1.35, math.min(1.35, player_x))

        -- Si le joueur mord l'herbe sur les cotes (|player_x| > 0.85)
        if math.abs(player_x) > 0.88 and speed > 70 then
            speed = math.max(65, speed - 18)
            minitel.play_sound("hit")
        end

        -- 4. Avancement sur la piste & Gestion des concurrents
        local step_d = speed / 95.0
        dist_total = dist_total + step_d
        seg_progress = seg_progress + step_d
        cp_dist_left = cp_dist_left - step_d
        score = score + math.floor(speed / 12)

        if seg_progress >= seg.len then
            seg_progress = 0
            seg_idx = (seg_idx % #TRACK) + 1
            seg = TRACK[seg_idx]
        end

        -- Approche du concurrent
        if speed > 90 then
            rival_z = rival_z + ((speed - 90) / 320.0)
            if rival_z >= 9.5 then
                -- Verification de collision avec le concurrent !
                if math.abs(player_x - rival_offset) < 0.35 then
                    minitel.play_sound("lose")
                    speed = math.floor(speed * 0.45)
                else
                    score = score + 250 -- Bonus depassement propre !
                end
                rival_z = 1.0
                rival_offset = (math.random(0, 1) == 0) and -0.42 or 0.42
            end
        end

        -- Passage d'un Checkpoint !
        if cp_dist_left <= 0 then
            cp_dist_left = 280
            time_left = math.min(99, time_left + 25)
            score = score + 1500
            minitel.play_sound("win")
            io.write("\x1b[7;25H\x1b[7m * * * CHECKPOINT ! +25 SECONDES ! * * * \x1b[0m")
        elseif cp_dist_left < 260 and cp_dist_left > 240 then
            io.write("\x1b[7;25H                                         ")
        end

        -- 5. Decompte du chronometre chaque seconde
        local now = os.time()
        if now ~= last_sec then
            last_sec = now
            time_left = time_left - 1
        end

        -- 6. Rendu differentiel de la route 3D & du tableau de bord
        render_road_frame(seg.curve, player_x, dist_total, rival_z, rival_offset)

        -- Tableau de bord : chaque champ n'est renvoye que s'il a change
        local g_mode = auto_gear and "A" or "M"
        hud_put(1, string.format("\x1b[3;12H\x1b[7m %02ds \x1b[0m", time_left))
        hud_put(2, string.format("\x1b[3;29H\x1b[1m%3d KM/H\x1b[0m", speed))
        hud_put(3, string.format("\x1b[3;53H[%d%s]", gear, g_mode))
        hud_put(4, string.format("\x1b[3;68H%07d", score))
        hud_put(5, string.format("\x1b[4;14H%-40s", seg.name))
        hud_put(6, string.format("\x1b[4;72H%3d M", math.max(0, math.floor(cp_dist_left))))
        io.flush()

        -- Image suivante quand celle-ci est affichee (a 9600 bauds, une image
        -- chargee prend plus de 0,08 s) : la course ne prend pas de retard
        minitel.wait_output()
        minitel.sleep(0.04)
    end

    minitel.msg_box("TIME OVER !", "Fin de la course ! Votre score final sur 3615 OUTRUN : " .. score .. " points !", "lose")
    return score
end

-- =====================================================================
-- 4. ECRAN TITRE (DESSINE UNE SEULE FOIS HORS BOUCLE !)
-- =====================================================================
local high_score = 12500

local function draw_title()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 OUTRUN - COURSE D'ARCADE PSEUDO-3D (9600 BAUDS)  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(12, 4, 58, 16, "MAGIS TURBO CHALLENGE")
    io.write("\x1b[6;16H          ._____________.")
    io.write("\x1b[7;16H         /   _________   \\       HIGH SCORE")
    io.write("\x1b[8;16H       _[___/         \\___]_     \x1b[1m" .. string.format("%-10d", high_score) .. "\x1b[0m")
    io.write("\x1b[9;16H      [ (O)  ==3615==   (O) ]    [Z]   GAZ")
    io.write("\x1b[10;16H      '====================='    [Q/D] VOLANT")
    io.write("\x1b[12;16H- Appuyez une fois sur [Z] pour lancer le moteur :")
    io.write("\x1b[13;16H  l'accelerateur reste ensuite maintenu tout seul.")
    io.write("\x1b[14;16H- Compensez la force centrifuge avec [Q] et [D]")
    io.write("\x1b[15;16H  et evitez le trafic pour battre le record !")
    io.write("\x1b[17;23H\x1b[7m [ENVOI] DEMARRER LE MOTEUR V12 \x1b[0m")

    io.write("\x1b[24;1H\x1b[7m  [ENVOI] PRENDRE LE DEPART   |   [RETOUR] QUITTER VERS LE PORTAIL MAGIS        \x1b[0m")
    io.flush()
end

draw_title()

while true do
    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "ENVOI" or k == " " then
        minitel.play_sound("pickup")
        local sc = run_arcade_race()
        if sc and sc > high_score then high_score = sc end
        draw_title()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()