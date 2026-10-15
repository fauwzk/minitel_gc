-- @GENRE: STRATEGIE / MULTIJOUEUR EN LIGNE
-- @DESC: Bataille Navale en ligne (Minitel contre Web ou Minitel) et mode solo contre l'Amiral IA.

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

-- =====================================================================
-- CONFIGURATION RESEAU (PARTAGEE AVEC 3615 PICTO)
-- =====================================================================
local CFG_FILE = "utils/pictochat.cfg"
local server_url = "http://127.0.0.1:8085"
local pseudo = "AMIRAL_52"

local function load_config()
    local f = io.open(CFG_FILE, "r")
    if f then
        local s = f:read("*l")
        local p = f:read("*l")
        f:close()
        if s and s ~= "" then server_url = s end
        if p and p ~= "" then pseudo = p end
    end
end
load_config()

local function urlencode(str)
    str = tostring(str or "")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

local function http_query(path)
    local cmd = string.format("curl -sL -k -m 4 '%s%s' 2>/dev/null", server_url, path)
    local f = io.popen(cmd)
    if not f then return "" end
    local res = f:read("*a") or ""
    f:close()
    return res
end

-- =====================================================================
-- CONSTANTES ET FLOTTE (GRILLE 8x8 : A-H / 1-8)
-- =====================================================================
local GRID_SIZE = 8
local TOTAL_SHIP_CELLS = 14 -- 4 + 3 + 3 + 2 + 2 = 14 cases
local SHIPS_DEF = {4, 3, 3, 2, 2}
local ROW_NAMES = {"A", "B", "C", "D", "E", "F", "G", "H"}

local function create_empty_grid()
    local g = {}
    for y = 1, GRID_SIZE do
        g[y] = {}
        for x = 1, GRID_SIZE do g[y][x] = "." end
    end
    return g
end

local function place_fleet_random(grid)
    for y = 1, GRID_SIZE do
        for x = 1, GRID_SIZE do grid[y][x] = "." end
    end
    for _, len in ipairs(SHIPS_DEF) do
        local placed = false
        while not placed do
            local horiz = (math.random(1, 2) == 1)
            local sx = math.random(1, horiz and (GRID_SIZE - len + 1) or GRID_SIZE)
            local sy = math.random(1, horiz and GRID_SIZE or (GRID_SIZE - len + 1))
            local free = true
            for i = 0, len - 1 do
                local cx = horiz and (sx + i) or sx
                local cy = horiz and sy or (sy + i)
                if grid[cy][cx] ~= "." then free = false; break end
            end
            if free then
                for i = 0, len - 1 do
                    local cx = horiz and (sx + i) or sx
                    local cy = horiz and sy or (sy + i)
                    grid[cy][cx] = "#"
                end
                placed = true
            end
        end
    end
end

local function serialize_fleet(grid)
    local chars = {}
    for y = 1, GRID_SIZE do
        for x = 1, GRID_SIZE do
            table.insert(chars, grid[y][x] == "#" and "1" or "0")
        end
    end
    return table.concat(chars)
end

-- =====================================================================
-- RENDU GRAPHIQUE DELTA-DRAWING DES DEUX GRILLES
-- =====================================================================
-- Grille Gauche (Ma Flotte) : X = 6, Y = 7
-- Grille Droite (Radar Ennemi) : X = 46, Y = 7
local function draw_single_cell(is_radar, grid, x, y, is_cursor)
    local base_x = is_radar and 48 or 8
    local scr_x = base_x + (x - 1) * 3
    local scr_y = 7 + y
    local val = grid[y][x]

    local disp = " . "
    if val == "#" then disp = "\x1b[7m # \x1b[0m"
    elseif val == "X" then disp = "\x1b[1m[X]\x1b[0m"
    elseif val == "o" then disp = " o "
    end

    if is_cursor then
        local raw_c = (val == "." and ".") or val
        disp = "\x1b[7m>" .. raw_c .. "<\x1b[0m"
    end

    io.write(string.format("\x1b[%d;%dH%s", scr_y, scr_x, disp))
end

local function draw_full_grid(is_radar, grid, cur_x, cur_y)
    local base_x = is_radar and 45 or 5
    io.write(string.format("\x1b[7;%dH    1  2  3  4  5  6  7  8", base_x))
    for y = 1, GRID_SIZE do
        io.write(string.format("\x1b[%d;%dH %s ", 7 + y, base_x, ROW_NAMES[y]))
        for x = 1, GRID_SIZE do
            draw_single_cell(is_radar, grid, x, y, is_radar and (x == cur_x and y == cur_y))
        end
    end
end

local function draw_battle_screen(title_right, my_grid, radar_grid, cx, cy, status_msg, my_hits, en_hits)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 BATAILLE NAVALE - COMMANDEMENT TACTIQUE  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(2, 3, 38, 15, "MA FLOTTE (" .. pseudo .. ")")
    minitel.draw_window(42, 3, 38, 15, title_right)

    draw_full_grid(false, my_grid, 0, 0)
    draw_full_grid(true, radar_grid, cx, cy)

    io.write(string.format("\x1b[16;4HTOUCHES SUBIES : %02d / %02d", en_hits, TOTAL_SHIP_CELLS))
    io.write(string.format("\x1b[16;44HCIBLES DETRUITES : %02d / %02d", my_hits, TOTAL_SHIP_CELLS))

    minitel.draw_window(2, 19, 78, 4, "JOURNAL DES OPERATIONS")
    io.write("\x1b[21;4H> " .. minitel.pad(status_msg, 73))

    io.write("\x1b[24;1H\x1b[7m  [ZQSD/FLECHES] VISER   |   [ENVOI] FEU !   |   [R] RAFRAICHIR   |   [RETOUR]  \x1b[0m")
    io.flush()
end

local function update_status_box(msg, my_hits, en_hits)
    io.write(string.format("\x1b[16;4HTOUCHES SUBIES : %02d / %02d", en_hits, TOTAL_SHIP_CELLS))
    io.write(string.format("\x1b[16;44HCIBLES DETRUITES : %02d / %02d", my_hits, TOTAL_SHIP_CELLS))
    io.write("\x1b[21;4H> " .. minitel.pad(msg, 73))
    io.flush()
end

-- =====================================================================
-- PHASE DE PREPARATION : PLACEMENT DE LA FLOTTE
-- =====================================================================
local function prepare_my_fleet()
    local my_grid = create_empty_grid()
    place_fleet_random(my_grid)

    while true do
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  DEPLOIEMENT DE VOTRE FLOTTE (5 NAVIRES / 14 CASES)  * * *", 80) .. "\x1b[0m")
        minitel.draw_window(18, 4, 46, 15, "DISPOSITION TACTIQUE")

        io.write("\x1b[6;28H    1  2  3  4  5  6  7  8")
        for y = 1, GRID_SIZE do
            io.write(string.format("\x1b[%d;28H %s ", 6 + y, ROW_NAMES[y]))
            for x = 1, GRID_SIZE do
                local v = my_grid[y][x]
                local d = (v == "#") and "\x1b[7m # \x1b[0m" or " . "
                io.write(d)
            end
        end

        io.write("\x1b[16;21H[R] GENERER UN AUTRE PLACEMENT ALEATOIRE")
        io.write("\x1b[17;21H[ENVOI] VALIDER ET LANCER LA BATAILLE")
        io.write("\x1b[24;1H\x1b[7m  [R] REORGANISER LA FLOTTE   |   [ENVOI] DEPART AU COMBAT   |   [RETOUR] MENU  \x1b[0m")
        io.flush()

        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then return nil
        elseif k == "R" or k == "r" then
            minitel.play_sound("hit")
            place_fleet_random(my_grid)
        elseif k == "ENVOI" or k == " " then
            minitel.play_sound("pickup")
            return my_grid
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MODE 1 : CONTRE L'AMIRAL IA (HORS-LIGNE)
-- =====================================================================
local function play_vs_ai(my_grid)
    local ai_ships = create_empty_grid()
    place_fleet_random(ai_ships)
    local radar_grid = create_empty_grid()

    local cx, cy = 4, 4
    local my_hits, ai_hits = 0, 0
    local ai_targets = {} -- Pile de chasse intelligente de l'IA

    draw_battle_screen("RADAR : FLOTTE AMIRAL IA", my_grid, radar_grid, cx, cy, "A VOUS DE TIRER ! SELECTIONNEZ UNE COORDONNEE.", 0, 0)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                if minitel.confirm_box("ABANDON", "Quitter la bataille en cours ?") then return end
                draw_battle_screen("RADAR : FLOTTE AMIRAL IA", my_grid, radar_grid, cx, cy, "COMBAT REPRIS.", my_hits, ai_hits)

            elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s"
                or k == "LEFT" or k == "Q" or k == "q" or k == "RIGHT" or k == "D" or k == "d" then
                local ox, oy = cx, cy
                if k == "UP" or k == "Z" or k == "z" then cy = (cy > 1) and (cy - 1) or GRID_SIZE
                elseif k == "DOWN" or k == "S" or k == "s" then cy = (cy < GRID_SIZE) and (cy + 1) or 1
                elseif k == "LEFT" or k == "Q" or k == "q" then cx = (cx > 1) and (cx - 1) or GRID_SIZE
                elseif k == "RIGHT" or k == "D" or k == "d" then cx = (cx < GRID_SIZE) and (cx + 1) or 1
                end
                draw_single_cell(true, radar_grid, ox, oy, false)
                draw_single_cell(true, radar_grid, cx, cy, true)
                io.flush()

            elseif k == "ENVOI" or k == " " then
                if radar_grid[cy][cx] ~= "." then
                    minitel.play_sound("lose")
                    update_status_box("VOUS AVEZ DEJA TIRE EN " .. ROW_NAMES[cy] .. cx .. " !", my_hits, ai_hits)
                else
                    -- 1. Tir du joueur
                    local coord_str = ROW_NAMES[cy] .. cx
                    local msg = ""
                    if ai_ships[cy][cx] == "#" then
                        radar_grid[cy][cx] = "X"
                        my_hits = my_hits + 1
                        minitel.play_sound("win")
                        msg = "TIR EN " .. coord_str .. " : TOUCHE !!"
                    else
                        radar_grid[cy][cx] = "o"
                        minitel.play_sound("hit")
                        msg = "TIR EN " .. coord_str .. " : PLOUF (A L'EAU)."
                    end
                    draw_single_cell(true, radar_grid, cx, cy, true)

                    if my_hits >= TOTAL_SHIP_CELLS then
                        minitel.msg_box("VICTOIRE NAVALE !", "Bravo Amiral ! Vous avez coule toute la flotte ennemie !", "win")
                        return
                    end

                    -- 2. Riposte de l'IA
                    local ax, ay
                    while #ai_targets > 0 do
                        local t = table.remove(ai_targets, 1)
                        if my_grid[t.y][t.x] == "." or my_grid[t.y][t.x] == "#" then
                            ax, ay = t.x, t.y
                            break
                        end
                    end
                    if not ax then
                        repeat
                            ax = math.random(1, GRID_SIZE)
                            ay = math.random(1, GRID_SIZE)
                        until my_grid[ay][ax] == "." or my_grid[ay][ax] == "#"
                    end

                    local ai_coord = ROW_NAMES[ay] .. ax
                    if my_grid[ay][ax] == "#" then
                        my_grid[ay][ax] = "X"
                        ai_hits = ai_hits + 1
                        minitel.play_sound("lose")
                        msg = msg .. " | RIPOSTE IA EN " .. ai_coord .. " : TOUCHÉ !"
                        local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
                        for _, d in ipairs(dirs) do
                            local nx, ny = ax + d[1], ay + d[2]
                            if nx >= 1 and nx <= GRID_SIZE and ny >= 1 and ny <= GRID_SIZE then
                                table.insert(ai_targets, {x = nx, y = ny})
                            end
                        end
                    else
                        my_grid[ay][ax] = "o"
                        msg = msg .. " | RIPOSTE IA EN " .. ai_coord .. " : A L'EAU."
                    end
                    draw_single_cell(false, my_grid, ax, ay, false)
                    update_status_box(msg, my_hits, ai_hits)

                    if ai_hits >= TOTAL_SHIP_CELLS then
                        minitel.msg_box("DEFAITE...", "L'Amiral IA a coule l'integralite de votre flotte !", "lose")
                        return
                    end
                end
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MODE 2 : DUEL EN LIGNE MULTIJOUEUR (MINITEL VS WEB OU MINITEL)
-- =====================================================================
local function play_online(my_grid)
    local room = minitel.input_box("SALLE DE COMBAT EN LIGNE", "Choisissez la Salle (A, B, C ou D) :", "A", 1)
    if not room or room == "" then return end
    room = string.upper(room)
    if not room:match("^[ABCD]$") then room = "A" end

    local fleet_bits = serialize_fleet(my_grid)
    local join_res = http_query(string.format("/api/navy/join?room=%s&user=%s&board=%s",
        room, urlencode(pseudo), fleet_bits))

    local my_slot = join_res:match("^JOINED|([12])")
    if not my_slot then
        minitel.msg_box("ERREUR SERVEUR", "Impossible de rejoindre la salle " .. room .. " sur " .. server_url, "lose")
        return
    end
    my_slot = tonumber(my_slot)

    local radar_grid = create_empty_grid()
    local cx, cy = 4, 4
    local last_turn = 0
    local last_shot_seq = 0
    local enemy_name = "EN ATTENTE..."
    local last_poll = 0

    draw_battle_screen("SALLE " .. room .. " : " .. enemy_name, my_grid, radar_grid, cx, cy,
        "CONNECTE EN TANT QUE JOUEUR " .. my_slot .. ". EN ATTENTE D'UN ADVERSAIRE...", 0, 0)

    while true do
        local now = os.time()
        if now - last_poll >= 2 then
            last_poll = now
            local st = http_query(string.format("/api/navy/state?room=%s&slot=%d", room, my_slot))
            -- Format: STATE|status|turn|p1|p2|p1_hits|p2_hits|shot_seq|last_shooter|last_x|last_y|last_res|winner
            local status, turn, p1, p2, h1, h2, seq, shooter, sx, sy, sres, win =
                st:match("^STATE|(.-)|(%d+)|(.-)|(.-)|(%d+)|(%d+)|(%d+)|(.-)|(%d+)|(%d+)|(.-)|(.*)$")

            if status then
                turn = tonumber(turn)
                h1, h2 = tonumber(h1), tonumber(h2)
                seq, sx, sy = tonumber(seq), tonumber(sx), tonumber(sy)
                local my_hits = (my_slot == 1) and h1 or h2
                local en_hits = (my_slot == 1) and h2 or h1
                local opp = (my_slot == 1) and p2 or p1

                if opp ~= "" and opp ~= enemy_name then
                    enemy_name = opp
                    io.write(string.format("\x1b[3;44H\x1b[7m%s\x1b[0m", minitel.center("SALLE " .. room .. " CONTRE " .. enemy_name, 34)))
                end

                if seq > last_shot_seq and sx >= 1 and sy >= 1 then
                    last_shot_seq = seq
                    local c_name = ROW_NAMES[sy] .. sx
                    if tonumber(shooter) == my_slot then
                        radar_grid[sy][sx] = (sres == "HIT") and "X" or "o"
                        draw_single_cell(true, radar_grid, sx, sy, (sx == cx and sy == cy))
                    else
                        my_grid[sy][sx] = (sres == "HIT") and "X" or "o"
                        draw_single_cell(false, my_grid, sx, sy, false)
                        minitel.play_sound(sres == "HIT" and "lose" or "hit")
                    end
                    local info = (tonumber(shooter) == my_slot and "VOTRE TIR EN " or ("TIR DE " .. enemy_name .. " EN "))
                        .. c_name .. " : " .. (sres == "HIT" and "TOUCHE !" or "A L'EAU.")
                    if status == "PLAYING" then
                        info = info .. (turn == my_slot and " -> A VOUS !" or (" -> TOUR DE " .. enemy_name))
                    end
                    update_status_box(info, my_hits, en_hits)
                elseif turn ~= last_turn and status == "PLAYING" then
                    last_turn = turn
                    local msg = (turn == my_slot) and ("A VOUS DE TIRER CONTRE " .. enemy_name .. " !") or ("AU TOUR DE " .. enemy_name .. " DE TIRER...")
                    update_status_box(msg, my_hits, en_hits)
                end

                if status == "FINISHED" then
                    if win == tostring(my_slot) then
                        minitel.msg_box("VICTOIRE EN LIGNE !", "Vous avez aneanti la flotte de " .. enemy_name .. " !", "win")
                    else
                        minitel.msg_box("DEFAITE EN LIGNE", enemy_name .. " a coule votre flotte !", "lose")
                    end
                    return
                end
            end
        end

        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                if minitel.confirm_box("QUITTER SALLE " .. room, "Abandonner le duel en ligne ?") then return end
                draw_battle_screen("SALLE " .. room .. " : " .. enemy_name, my_grid, radar_grid, cx, cy, "REPRISE DU DUEL.", 0, 0)

            elseif k == "R" or k == "r" or k == "REPETITION" then
                last_poll = 0

            elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s"
                or k == "LEFT" or k == "Q" or k == "q" or k == "RIGHT" or k == "D" or k == "d" then
                local ox, oy = cx, cy
                if k == "UP" or k == "Z" or k == "z" then cy = (cy > 1) and (cy - 1) or GRID_SIZE
                elseif k == "DOWN" or k == "S" or k == "s" then cy = (cy < GRID_SIZE) and (cy + 1) or 1
                elseif k == "LEFT" or k == "Q" or k == "q" then cx = (cx > 1) and (cx - 1) or GRID_SIZE
                elseif k == "RIGHT" or k == "D" or k == "d" then cx = (cx < GRID_SIZE) and (cx + 1) or 1
                end
                draw_single_cell(true, radar_grid, ox, oy, false)
                draw_single_cell(true, radar_grid, cx, cy, true)
                io.flush()

            elseif k == "ENVOI" or k == " " then
                if radar_grid[cy][cx] ~= "." then
                    minitel.play_sound("lose")
                else
                    local fire_res = http_query(string.format("/api/navy/fire?room=%s&slot=%d&x=%d&y=%d", room, my_slot, cx, cy))
                    if fire_res:find("^WAIT") then
                        minitel.play_sound("lose")
                    elseif fire_res:find("^OK|HIT") then
                        minitel.play_sound("win")
                        last_poll = 0
                    elseif fire_res:find("^OK|MISS") then
                        minitel.play_sound("hit")
                        last_poll = 0
                    end
                end
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MENU D'ACCUEIL DE LA BATAILLE NAVALE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 BATAILLE NAVALE - AMIRAUTE TELEMATIQUE  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(16, 5, 50, 15, "CHOIX DU MODE D'ENGAGEMENT")
    io.write("\x1b[7;20H\x1b[1mSERVEUR :\x1b[0m " .. string.sub(server_url, 1, 32))
    io.write("\x1b[8;20H\x1b[1mAMIRAL  :\x1b[0m " .. pseudo)
    io.write("\x1b[10;20H\x1b[7m [1] \x1b[0m DUEL EN LIGNE (MINITEL / WEB)")
    io.write("\x1b[12;20H\x1b[7m [2] \x1b[0m ENTRAINEMENT CONTRE L'AMIRAL IA")
    io.write("\x1b[14;20H\x1b[7m [3] \x1b[0m CONFIGURER SERVEUR / PSEUDO")
    io.write("\x1b[17;20H\x1b[7m [RETOUR] \x1b[0m QUITTER VERS LE PORTAIL")

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1], [2] OU [3]   |   CLIENT WEB DISPONIBLE SUR : /bataille             \x1b[0m")
    io.flush()

    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "1" then
        local fleet = prepare_my_fleet()
        if fleet then play_online(fleet) end
    elseif k == "2" then
        local fleet = prepare_my_fleet()
        if fleet then play_vs_ai(fleet) end
    elseif k == "3" then
        local ns = minitel.input_box("SERVEUR EN LIGNE", "URL du serveur :", server_url, 42)
        if ns and ns ~= "" then server_url = ns:gsub("/+$", "") end
        local np = minitel.input_box("NOM D'AMIRAL", "Votre pseudo (10 car. max) :", pseudo, 10)
        if np and np ~= "" then pseudo = string.upper(minitel.clean_accents(np)):gsub("[^%w_%-]", "") end
        local f = io.open(CFG_FILE, "w")
        if f then f:write(server_url .. "\n" .. pseudo .. "\n"); f:close() end
    end
    minitel.sleep(0.02)
end

minitel.cleanup()