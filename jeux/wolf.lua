-- @GENRE: ACTION / 3D RAYCASTER
-- @DESC: Moteur 3D temps reel par lancer de rayons (Raycasting DDA) avec double-buffer differentiel, radar et 3 niveaux !

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- 1. CARTES DES 3 SOUS-SOLS DU BUNKER (1=Mur, 2=Porte/Sortie, 3=Terminal Secret)
-- =====================================================================
local LEVELS = {
    {
        name = "SOUS-SOL -1 : ARCHIVES TELECOM",
        start_x = 2.5, start_y = 2.5, start_a = 0.0,
        map = {
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
            {1,0,0,0,1,0,0,0,0,0,1,0,0,3,0,1},
            {1,0,1,0,1,0,1,1,1,0,1,0,1,1,0,1},
            {1,0,1,0,0,0,0,0,1,0,0,0,1,0,0,1},
            {1,0,1,1,1,1,1,0,1,1,1,0,1,0,1,1},
            {1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1},
            {1,1,1,0,1,0,1,1,1,0,1,1,1,1,0,1},
            {1,3,0,0,1,0,0,0,1,0,0,0,0,1,0,1},
            {1,1,1,1,1,1,1,0,1,1,1,1,0,1,0,1},
            {1,0,0,0,0,0,0,0,0,0,0,1,0,0,2,1},
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
        }
    },
    {
        name = "SOUS-SOL -2 : SALLE DES SERVEURS X.25",
        start_x = 2.5, start_y = 2.5, start_a = 0.0,
        map = {
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
            {1,0,0,1,0,0,0,1,3,0,0,0,1,0,0,1},
            {1,0,0,1,0,1,0,1,1,1,1,0,1,0,1,1},
            {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
            {1,1,1,1,0,1,1,1,1,0,1,1,1,1,0,1},
            {1,3,0,0,0,0,0,0,1,0,0,0,0,1,0,1},
            {1,0,1,1,1,1,1,0,1,1,1,1,0,1,0,1},
            {1,0,1,0,0,0,1,0,0,0,0,1,0,1,0,1},
            {1,0,1,0,1,0,1,1,1,1,0,1,0,1,0,1},
            {1,0,0,0,1,0,0,0,0,0,0,0,0,1,2,1},
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
        }
    },
    {
        name = "SOUS-SOL -3 : COEUR DU MAINFRAME",
        start_x = 2.5, start_y = 5.5, start_a = 0.0,
        map = {
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
            {1,3,0,0,1,0,0,0,0,0,0,1,0,0,3,1},
            {1,1,1,0,1,0,1,1,1,1,0,1,0,1,1,1},
            {1,0,0,0,0,0,1,3,0,1,0,0,0,0,0,1},
            {1,0,1,1,1,0,1,0,0,1,0,1,1,1,0,1},
            {1,0,0,0,1,0,0,0,0,0,0,1,0,0,0,1},
            {1,0,1,1,1,0,1,1,1,1,0,1,1,1,0,1},
            {1,0,0,0,0,0,1,0,0,0,0,0,0,1,0,1},
            {1,1,1,0,1,1,1,0,1,1,1,1,0,1,0,1},
            {1,3,0,0,0,0,0,0,1,2,0,0,0,0,0,1},
            {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
        }
    }
}

-- =====================================================================
-- 2. PARAMETRES DU MOTEUR RAYCASTING & DOUBLE BUFFERING
-- =====================================================================
local VIEW_W = 50
local VIEW_H = 16
local VIEW_X = 3   -- Colonne de depart sur l'ecran Minitel
local VIEW_Y = 4   -- Ligne de depart sur l'ecran Minitel
local FOV    = 1.05 -- ~60 degres

local prev_buf = {}
local next_buf = {}

local function init_buffers()
    for y = 1, VIEW_H do
        prev_buf[y] = {}
        next_buf[y] = {}
        for x = 1, VIEW_W do
            prev_buf[y][x] = ""
            next_buf[y][x] = " "
        end
    end
end

-- Envoie UNIQUEMENT les segments de caracteres qui ont change entre 2 images.
-- Deux segments separes par quelques caracteres inchanges n'en font qu'un :
-- renvoyer ces caracteres coute moins cher qu'un nouveau positionnement du
-- curseur (ESC [ l ; c H, 6 a 8 octets).
local MERGE_GAP = 6

local function flush_3d_buffer()
    local out = {}
    for y = 1, VIEW_H do
        local nb, pb = next_buf[y], prev_buf[y]
        local x = 1
        while x <= VIEW_W do
            if nb[x] ~= pb[x] then
                local start_x, last = x, x
                local scan = x + 1
                while scan <= VIEW_W and scan - last <= MERGE_GAP do
                    if nb[scan] ~= pb[scan] then last = scan end
                    scan = scan + 1
                end
                local seg = {}
                for i = start_x, last do
                    seg[#seg + 1] = nb[i]
                    pb[i] = nb[i]
                end
                out[#out + 1] = string.format("\x1b[%d;%dH%s", VIEW_Y + y - 1, VIEW_X + start_x - 1, table.concat(seg))
                x = last + 1
            else
                x = x + 1
            end
        end
    end
    if #out > 0 then
        io.write(table.concat(out))
    end
end

-- =====================================================================
-- 3. ALGORITHME DE LANCER DE RAYONS (DDA)
-- =====================================================================
local function render_raycast_view(map, px, py, pa)
    local half_h = VIEW_H / 2

    for x = 1, VIEW_W do
        local cam_x = 2.0 * (x - 1) / (VIEW_W - 1) - 1.0
        local ray_a = pa + cam_x * (FOV / 2.0)
        local rdx = math.cos(ray_a)
        local rdy = math.sin(ray_a)

        local mx = math.floor(px)
        local my = math.floor(py)

        local ddx = (rdx == 0) and 1e30 or math.abs(1.0 / rdx)
        local ddy = (rdy == 0) and 1e30 or math.abs(1.0 / rdy)

        local step_x, side_x
        local step_y, side_y

        if rdx < 0 then
            step_x = -1
            side_x = (px - mx) * ddx
        else
            step_x = 1
            side_x = (mx + 1.0 - px) * ddx
        end

        if rdy < 0 then
            step_y = -1
            side_y = (py - my) * ddy
        else
            step_y = 1
            side_y = (my + 1.0 - py) * ddy
        end

        local hit = 0
        local side = 0
        local steps = 0

        while hit == 0 and steps < 24 do
            steps = steps + 1
            if side_x < side_y then
                side_x = side_x + ddx
                mx = mx + step_x
                side = 0
            else
                side_y = side_y + ddy
                my = my + step_y
                side = 1
            end
            if map[my] and map[my][mx] and map[my][mx] > 0 then
                hit = map[my][mx]
            end
        end

        -- Correction de l'effet fisheye
        local perp_dist
        if side == 0 then
            perp_dist = (side_x - ddx)
        else
            perp_dist = (side_y - ddy)
        end
        if perp_dist < 0.15 then perp_dist = 0.15 end

        local line_h = math.floor(VIEW_H / perp_dist)
        local draw_start = math.max(1, math.floor(half_h - line_h / 2) + 1)
        local draw_end   = math.min(VIEW_H, math.floor(half_h + line_h / 2))

        -- Choix de la texture ASCII selon la distance, l'orientation N/S vs E/O et le type de bloc
        local tex = "."
        if hit == 2 then
            -- Porte de sortie (Ascenseur)
            tex = (perp_dist < 4.5) and "S" or "="
        elseif hit == 3 then
            -- Terminal secret a pirater
            tex = (perp_dist < 4.5) and "@" or "*"
        else
            if side == 0 then
                if perp_dist < 1.3 then tex = "#"
                elseif perp_dist < 2.4 then tex = "H"
                elseif perp_dist < 4.0 then tex = "+"
                elseif perp_dist < 6.5 then tex = ":"
                else tex = "." end
            else
                -- Face ombree pour creer le relief 3D dans les coins !
                if perp_dist < 1.3 then tex = "H"
                elseif perp_dist < 2.4 then tex = "+"
                elseif perp_dist < 4.0 then tex = ":"
                else tex = "." end
            end
        end

        for y = 1, VIEW_H do
            if y < draw_start then
                -- Plafond
                next_buf[y][x] = (y == 1) and "-" or " "
            elseif y >= draw_start and y <= draw_end then
                -- Bord haut et bas des murs proches soulignes pour accentuer la perspective !
                if (y == draw_start or y == draw_end) and perp_dist < 3.8 and hit == 1 then
                    next_buf[y][x] = "-"
                else
                    next_buf[y][x] = tex
                end
            else
                -- Sol avec tramage de profondeur
                next_buf[y][x] = (y > VIEW_H - 2) and "," or " "
            end
        end
    end

    flush_3d_buffer()
end

-- =====================================================================
-- 4. AUTOMAP RADAR & TELEMETRIE A DROITE (DELTA-DRAWING)
-- =====================================================================
local prev_map_px, prev_map_py = -1, -1

local function draw_full_automap(map, px, py)
    local ipx, ipy = math.floor(px), math.floor(py)
    for my = 1, #map do
        local row_chars = {}
        for mx = 1, #map[my] do
            local cell = map[my][mx]
            if mx == ipx and my == ipy then
                table.insert(row_chars, "\x1b[7m@\x1b[0m")
            elseif cell == 1 then
                table.insert(row_chars, "#")
            elseif cell == 2 then
                table.insert(row_chars, "S")
            elseif cell == 3 then
                table.insert(row_chars, "*")
            else
                table.insert(row_chars, " ")
            end
        end
        io.write(string.format("\x1b[%d;59H%s", 4 + my, table.concat(row_chars)))
    end
    prev_map_px, prev_map_py = ipx, ipy
end

local function update_automap_player(map, px, py)
    local ipx, ipy = math.floor(px), math.floor(py)
    if ipx == prev_map_px and ipy == prev_map_py then return end
    if prev_map_px > 0 and prev_map_py > 0 then
        local old_c = map[prev_map_py][prev_map_px]
        local ch = (old_c == 1 and "#") or (old_c == 2 and "S") or (old_c == 3 and "*") or " "
        io.write(string.format("\x1b[%d;%dH%s", 4 + prev_map_py, 58 + prev_map_px, ch))
    end
    io.write(string.format("\x1b[%d;%dH\x1b[7m@\x1b[0m", 4 + ipy, 58 + ipx))
    prev_map_px, prev_map_py = ipx, ipy
end

local function get_compass_dir(angle)
    local deg = math.floor((angle * 180 / math.pi) % 360)
    if deg < 45 or deg >= 315 then return "EST  (000)"
    elseif deg < 135 then return "SUD  (090)"
    elseif deg < 225 then return "OUEST(180)"
    else return "NORD (270)" end
end

-- =====================================================================
-- 5. BOUCLE DE JEU PRINCIPALE PAR NIVEAU
-- =====================================================================
local function play_level(lvl_idx)
    local lvl = LEVELS[lvl_idx]
    -- Copie locale de la carte pour pouvoir collecter les terminaux (*)
    local map = {}
    local total_terminals = 0
    for y = 1, #lvl.map do
        map[y] = {}
        for x = 1, #lvl.map[y] do
            map[y][x] = lvl.map[y][x]
            if map[y][x] == 3 then total_terminals = total_terminals + 1 end
        end
    end

    local px, py, pa = lvl.start_x, lvl.start_y, lvl.start_a
    local hacked_count = 0
    local steps_count = 0
    local log_msg = "TROUVEZ LES TERMINAUX (@/*) PUIS REJOIGNEZ L'ASCENSEUR (S) !"

    local hud_shown = {}

    -- Ecrit un element du HUD seulement s'il a change depuis l'image precedente
    local function hud_put(key, seq)
        if hud_shown[key] ~= seq then
            hud_shown[key] = seq
            io.write(seq)
        end
    end

    local function draw_level_skeleton()
        io.write("\x1b[r\x1b[0m\x1b[2J\x1b[H")
        init_buffers()
        hud_shown = {}

        -- L'ecran vient d'etre efface : cadres sans remplissage, et dans la vue
        -- 3D les espaces deja a l'ecran ne sont pas renvoyes
        for y = 1, VIEW_H do
            for x = 1, VIEW_W do prev_buf[y][x] = " " end
        end
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 WOLF-3D - MOTEUR RAYCASTING TEMPS REEL  * * *", 80) .. "\x1b[0m")
        minitel.draw_frame(2, 3, 52, 18, lvl.name)
        minitel.draw_frame(56, 3, 24, 14, "RADAR & BOUSSOLE")
        minitel.draw_frame(56, 17, 24, 4, "OBJECTIF MISSION")
        minitel.draw_frame(2, 21, 78, 3, "")

        draw_full_automap(map, px, py)
        io.write("\x1b[24;1H\x1b[7m [Z/S] AVANCER/RECULER | [Q/D] TOURNER | [A/E] PAS DE COTE | [RETOUR] QUITTER   \x1b[0m")
        io.write("\x1b[4;58HCAP :\x1b[18;58HTERMINAUX :\x1b[19;58HPAS       :\x1b[22;4H>")
    end

    local function update_hud()
        hud_put("cap", string.format("\x1b[4;64H\x1b[1m%s\x1b[0m", get_compass_dir(pa)))
        hud_put("term", string.format("\x1b[18;70H\x1b[7m %d / %d \x1b[0m", hacked_count, total_terminals))
        hud_put("pas", string.format("\x1b[19;70H%04d", steps_count))
        hud_put("log", "\x1b[22;6H" .. minitel.pad(log_msg, 73))
    end

    draw_level_skeleton()
    render_raycast_view(map, px, py, pa)
    update_hud()
    io.flush()

    while true do
        local k = minitel.get_key()
        local moved = false
        while k do
            local move_speed = 0.42
            local rot_speed  = 0.26 -- ~15 degres par pression

            if k == "RETOUR" or k == "ESC" then
                if minitel.confirm_box("QUITTER MISSION", "Abandonner l'exploration 3D en cours ?") then
                    return "QUIT"
                end
                draw_level_skeleton()
                moved = true

            elseif k == "REPETITION" then
                draw_level_skeleton()
                moved = true

            elseif k == "LEFT" or k == "Q" or k == "q" then
                pa = pa - rot_speed
                moved = true

            elseif k == "RIGHT" or k == "D" or k == "d" then
                pa = pa + rot_speed
                moved = true

            elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s"
                or k == "A" or k == "a" or k == "E" or k == "e" then
                local dir_a = pa
                if k == "DOWN" or k == "S" or k == "s" then dir_a = pa + math.pi
                elseif k == "A" or k == "a" then dir_a = pa - (math.pi / 2)
                elseif k == "E" or k == "e" then dir_a = pa + (math.pi / 2)
                end

                local nx = px + math.cos(dir_a) * move_speed
                local ny = py + math.sin(dir_a) * move_speed
                local cell_x = math.floor(nx)
                local cell_y = math.floor(ny)
                local target_block = (map[cell_y] and map[cell_y][cell_x]) or 1

                if target_block == 0 then
                    px, py = nx, ny
                    steps_count = steps_count + 1
                    moved = true
                elseif target_block == 3 then
                    -- Piratage d'un terminal secret !
                    map[cell_y][cell_x] = 0
                    px, py = nx, ny
                    hacked_count = hacked_count + 1
                    minitel.play_sound("pickup")
                    log_msg = string.format("TERMINAL DECRYPTE (%d/%d) ! Cle d'acces recuperee !", hacked_count, total_terminals)
                    draw_full_automap(map, px, py)
                    moved = true
                elseif target_block == 2 then
                    if hacked_count >= total_terminals then
                        minitel.play_sound("win")
                        return "NEXT"
                    else
                        minitel.play_sound("lose")
                        log_msg = string.format("ASCENSEUR VERROUILLE ! Il reste %d terminal(aux) (*) a pirater !", total_terminals - hacked_count)
                        update_hud()
                        io.flush()
                    end
                else
                    -- Glissement le long des murs (Wall sliding)
                    if map[math.floor(py)][math.floor(nx)] == 0 then
                        px = nx; moved = true
                    elseif map[math.floor(ny)][math.floor(px)] == 0 then
                        py = ny; moved = true
                    end
                end
            end

            -- Touches suivantes deja recues (touche maintenue, frappe rapide) :
            -- elles ne donnent qu'une image, le Minitel ne prend pas de retard
            k = minitel.get_key()
        end
        if moved then
            render_raycast_view(map, px, py, pa)
            update_automap_player(map, px, py)
            update_hud()
            io.flush()
            minitel.wait_output()
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- 6. ECRAN TITRE (DESSINE UNE SEULE FOIS HORS BOUCLE !)
-- =====================================================================
local function draw_title()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 WOLF-3D - EXPLORATION 3D SUBJECTIVE (9600 BAUDS)  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(12, 4, 58, 16, "BRIEFING DE MISSION : BUNKER TRANSPAC")
    io.write("\x1b[6;15H  \\                 /    MOTEUR RAYCASTING")
    io.write("\x1b[7;15H   \\               /     ------------------")
    io.write("\x1b[8;15H    +-------------+      [# H +]  MURS")
    io.write("\x1b[9;15H    |  #   @   #  |      [@ *]    TERMINAUX")
    io.write("\x1b[10;15H    |  #       #  |      [S =]    ASCENSEUR")
    io.write("\x1b[11;15H    +-------------+")
    io.write("\x1b[12;15H   /               \\")
    io.write("\x1b[14;15HPiratez tous les terminaux (*) d'un sous-sol pour")
    io.write("\x1b[15;15Hdeverrouiller l'ascenseur (S) vers le niveau suivant.")
    io.write("\x1b[17;23H\x1b[7m [ENVOI] ENTRER DANS LE LABYRINTHE 3D \x1b[0m")

    io.write("\x1b[24;1H\x1b[7m  [ENVOI] LANCER LA 3D TEMPS REEL   |   [RETOUR] QUITTER VERS LE PORTAIL        \x1b[0m")
    io.flush()
end

draw_title()

while true do
    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "ENVOI" or k == " " then
        local cur_lvl = 1
        while cur_lvl <= #LEVELS do
            local res = play_level(cur_lvl)
            if res == "QUIT" then break
            elseif res == "NEXT" then
                if cur_lvl < #LEVELS then
                    minitel.msg_box("NIVEAU TERMINE !", "Descente vers le " .. LEVELS[cur_lvl + 1].name .. " !", "win")
                else
                    minitel.msg_box("VICTOIRE TOTALE !", "Bravo ! Vous avez infiltre les 3 sous-sols 3D du Bunker !", "win")
                end
                cur_lvl = cur_lvl + 1
            end
        end
        draw_title()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()