-- Fichier : jeux/briques.lua
-- 3615 BRIQUES : casse-briques en Videotex couleur. Le Minitel repasse en
-- 40 colonnes pour ses couleurs et ses caracteres mosaiques : chaque case est
-- decoupee en 2 x 3 pixels, et la balle se deplace pixel par pixel.
-- @GENRE: ARCADE / VIDEOTEX COULEUR
-- @DESC: Casse-briques en Videotex couleur : briques en mosaiques, balle au pixel pres, niveaux de plus en plus rapides. Fleches ou Q / D, ENVOI pour lancer.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- VIDEOTEX : CODES DE BASE
-- =====================================================================
local FF, US, SO, SI, ESC, REP = "\x0c", "\x1f", "\x0e", "\x0f", "\x1b", "\x12"
local COFF, CON = "\x14", "\x11"
local NOIR, ROUGE, VERT, JAUNE, BLEU, MAGENTA, CYAN, BLANC = 0, 1, 2, 3, 4, 5, 6, 7

local function at(row, col) return US .. string.char(0x40 + row, 0x40 + col) end
local function fg(c) return ESC .. string.char(0x40 + c) end
local function bg(c) return ESC .. string.char(0x50 + c) end
local BLINK, STEADY = ESC .. "\x48", ESC .. "\x49"
local NORMAL_SIZE, DOUBLE_HEIGHT, DOUBLE_SIZE = ESC .. "\x4c", ESC .. "\x4d", ESC .. "\x4f"

-- Caractere mosaique : bits des 6 pixels (haut gauche, haut droit, milieu
-- gauche, milieu droit, bas gauche, bas droit)
local PIXEL_BIT = { [0] = { [0] = 1, 2 }, { [0] = 4, 8 }, { [0] = 16, 64 } }
local FULL = string.char(0x7f)

local function mosaic(bits) return string.char(0x20 + bits) end

local function send(s)
    io.write(s)
end

-- =====================================================================
-- CLAVIER EN VIDEOTEX : touches de fonction (SEP + code), fleches du clavier
-- etendu (ESC [ A..D) et lettres
-- =====================================================================
local SEP_KEYS = { [0x41] = "ENVOI", [0x42] = "RETOUR", [0x43] = "REPETITION", [0x44] = "GUIDE",
                   [0x45] = "ANNULATION", [0x46] = "SOMMAIRE", [0x47] = "CORRECTION", [0x48] = "SUITE" }

local function read_key()
    local c = io.read(1)
    if not c then return nil end
    local b = string.byte(c) & 0x7f
    if b == 0x13 then
        local n = io.read(1)
        return n and SEP_KEYS[string.byte(n) & 0x7f] or nil
    end
    if b == 0x1b then
        local n = io.read(1)
        if not n then return "ESC" end
        if n == "[" then
            local d = io.read(1)
            return ({ A = "UP", B = "DOWN", C = "RIGHT", D = "LEFT" })[d or ""]
        end
        return nil
    end
    if b == 0x0d or b == 0x0a then return "ENVOI" end
    return string.upper(string.char(b))
end

-- =====================================================================
-- TERRAIN : murs en colonnes 1 et 40, plafond en ligne 3, raquette en 23
-- =====================================================================
local COL_MIN, COL_MAX = 2, 39
local ROW_TOP, PADDLE_ROW = 4, 23
local PX_MIN, PX_MAX = 2 * (COL_MIN - 1), 2 * COL_MAX - 1   -- pixels horizontaux
local PY_MIN, PY_LOST = 3 * (ROW_TOP - 1), 3 * 24           -- pixels verticaux
local PADDLE_W = 6

local ROW_COLORS = { ROUGE, MAGENTA, JAUNE, VERT, CYAN, BLEU }
local ROW_POINTS = { 60, 50, 40, 30, 20, 10 }

local bricks          -- bricks[row][col] = brique occupant la case, ou nil
local bricks_left
local paddle          -- colonne de gauche de la raquette
local bx, by, dx, dy  -- balle en pixels, et sa vitesse (dx : -2..2, dy : -1 ou 1)
local stuck           -- balle posee sur la raquette, en attente de ENVOI
local score, lives, level

local function cell_of(px, py) return px // 2 + 1, py // 3 + 1 end

-- Contenu d'une case de la ligne de la raquette ou de la balle
local function draw_cell(col, row)
    local bits, color = 0, BLANC
    local bc, br = cell_of(bx, by)
    if row == PADDLE_ROW and col >= paddle and col < paddle + PADDLE_W then
        bits = bits | 1 | 2
    end
    if bc == col and br == row then
        bits = bits | PIXEL_BIT[by % 3][bx % 2]
        if bits == PIXEL_BIT[by % 3][bx % 2] then color = JAUNE end
    end
    if bits == 0 then
        send(at(row, col) .. " ")
    else
        send(at(row, col) .. fg(color) .. SO .. mosaic(bits) .. SI)
    end
end

local function draw_brick(b)
    if b.alive then
        send(at(b.row, b.col) .. fg(b.color) .. SO .. string.rep(FULL, 3) .. SI)
    else
        send(at(b.row, b.col) .. "   ")
    end
end

local function draw_paddle()
    send(at(PADDLE_ROW, COL_MIN) .. string.rep(" ", COL_MAX - COL_MIN + 1))
    send(at(PADDLE_ROW, paddle) .. fg(BLANC) .. SO .. string.rep(mosaic(3), PADDLE_W) .. SI)
end

local function draw_status()
    local hearts = string.rep("*", lives)
    send(at(1, 1) .. fg(MAGENTA) .. "3615 BRIQUES" .. at(1, 15) .. fg(JAUNE) ..
        string.format("SCORE %05d", score) .. at(1, 28) .. fg(CYAN) .. string.format("NIV %d", level) ..
        at(1, 35) .. fg(ROUGE) .. string.format("%-3s", hearts))
end

local function new_level()
    bricks, bricks_left = {}, 0
    for r = 1, 6 do
        local row = ROW_TOP + 1 + r
        bricks[row] = {}
        for i = 0, 8 do
            local col = COL_MIN + 1 + i * 4
            -- des le niveau 2, des trous en damier dans le mur
            if level == 1 or (r + i + level) % 5 ~= 0 then
                local b = { row = row, col = col, color = ROW_COLORS[r], points = ROW_POINTS[r], alive = true }
                for c = col, col + 2 do bricks[row][c] = b end
                bricks_left = bricks_left + 1
            end
        end
    end
end

local function draw_board()
    send(FF .. COFF)
    -- murs bleus et plafond
    send(at(3, 1) .. fg(BLEU) .. SO .. FULL .. REP .. string.char(0x40 + 39) .. SI)
    for row = 4, 24 do
        send(at(row, 1) .. fg(BLEU) .. SO .. FULL .. SI .. at(row, 40) .. fg(BLEU) .. SO .. FULL .. SI)
    end
    for _, row in pairs(bricks) do
        local seen = {}
        for _, b in pairs(row) do
            if not seen[b] then seen[b] = true; if b.alive then draw_brick(b) end end
        end
    end
    draw_paddle()
    draw_status()
end

local function reset_ball()
    stuck = true
    bx, by = 2 * (paddle - 1) + PADDLE_W, 3 * (PADDLE_ROW - 1) - 1
    dx, dy = 1, -1
end

local function brick_at(px, py)
    local col, row = cell_of(px, py)
    local b = bricks[row] and bricks[row][col]
    return b and b.alive and b or nil
end

local function hit(b)
    b.alive = false
    bricks_left = bricks_left - 1
    score = score + b.points
    draw_brick(b)
    draw_status()
    minitel.play_sound("hit")
end

-- Un pas d'un pixel en diagonale, avec rebonds sur les murs, les briques et
-- la raquette ; rend false si la balle est perdue
local function step(sx, sy)
    local nx, ny = bx + sx, by + sy
    if nx < PX_MIN or nx > PX_MAX then sx = -sx; dx = -dx; nx = bx + sx end
    if ny < PY_MIN then sy = -sy; dy = -dy; ny = by + sy end
    -- briques : on regarde la case visee en x, en y, puis en diagonale
    local bxh, byh = brick_at(nx, by), brick_at(bx, ny)
    if bxh or byh then
        if bxh then hit(bxh); dx = -dx; nx = bx end
        if byh and byh ~= bxh then hit(byh) end
        if byh then dy = -dy; ny = by end
    else
        local bd = brick_at(nx, ny)
        if bd then hit(bd); dx, dy = -dx, -dy; nx, ny = bx, by end
    end
    -- raquette : le haut de la ligne 23
    if sy > 0 and ny == 3 * (PADDLE_ROW - 1) then
        local col = nx // 2 + 1
        if col >= paddle and col < paddle + PADDLE_W then
            local where = nx - 2 * (paddle - 1)           -- 0 .. 2 * PADDLE_W - 1
            local zone = where * 4 // (2 * PADDLE_W)      -- 0..3
            dx = ({ -2, -1, 1, 2 })[zone + 1]
            dy = -1
            ny = by
            minitel.play_sound("pickup")
        end
    end
    local oc, orow = cell_of(bx, by)
    bx, by = nx, ny
    if by >= PY_LOST then return false end
    local nc, nrow = cell_of(bx, by)
    if nc ~= oc or nrow ~= orow then draw_cell(oc, orow) end
    draw_cell(nc, nrow)
    return true
end

-- =====================================================================
-- ECRANS DE TITRE ET DE FIN
-- =====================================================================
local function title_screen()
    send(FF .. COFF)
    -- bandeau de briques de toutes les couleurs
    for r, color in ipairs(ROW_COLORS) do
        send(at(1 + r, 1) .. fg(color) .. SO)
        for i = 0, 9 do send(FULL .. FULL .. FULL .. " ") end
        send(SI)
    end
    send(at(10, 5) .. fg(JAUNE) .. DOUBLE_SIZE .. "3615 BRIQUES" .. NORMAL_SIZE)
    send(at(13, 6) .. fg(CYAN) .. "Le casse-briques du Magis Club")
    send(at(15, 4) .. fg(BLANC) .. "FLECHES OU Q / D : RAQUETTE")
    send(at(16, 4) .. fg(BLANC) .. "ENVOI : LANCER LA BALLE")
    send(at(17, 4) .. fg(BLANC) .. "SOMMAIRE OU ESC : QUITTER")
    local best = minitel.get_record("BRIQUES")
    if best then send(at(19, 4) .. fg(MAGENTA) .. string.format("RECORD : %d POINTS", best)) end
    send(at(22, 9) .. fg(VERT) .. BLINK .. "APPUYEZ SUR ENVOI" .. STEADY)
    io.flush()
    while true do
        local k = read_key()
        if k == "ENVOI" or k == " " then return true end
        if k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false end
        minitel.sleep(0.03)
    end
end

local function game_over_screen(won)
    local record = minitel.submit_record("BRIQUES", score, "high", "PTS", "NIVEAU " .. level)
    send(at(10, 8) .. bg(NOIR) .. fg(won and VERT or ROUGE) .. DOUBLE_HEIGHT .. BLINK ..
        (won and "  BRAVO !  " or " PARTIE TERMINEE ") .. STEADY .. NORMAL_SIZE)
    send(at(13, 10) .. fg(JAUNE) .. string.format("SCORE : %d POINTS", score))
    if record then send(at(15, 11) .. fg(MAGENTA) .. BLINK .. "NOUVEAU RECORD !" .. STEADY) end
    send(at(18, 9) .. fg(BLANC) .. "ENVOI : REJOUER")
    send(at(19, 9) .. fg(BLANC) .. "SOMMAIRE : QUITTER")
    io.flush()
    minitel.play_sound(record and "win" or "lose")
    while true do
        local k = read_key()
        if k == "ENVOI" or k == " " then return true end
        if k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- PARTIE
-- =====================================================================
local function play()
    score, lives, level = 0, 3, 1
    paddle = (COL_MIN + COL_MAX - PADDLE_W) // 2
    new_level()
    reset_ball()
    draw_board()
    draw_cell(cell_of(bx, by))
    io.flush()
    local tick = 0.06
    while true do
        -- touches : toutes celles arrivees depuis la derniere image
        local move = 0
        while true do
            local k = read_key()
            if not k then break end
            if k == "LEFT" or k == "Q" or k == "4" then move = move - 1
            elseif k == "RIGHT" or k == "D" or k == "6" then move = move + 1
            elseif (k == "ENVOI" or k == " " or k == "UP") and stuck then stuck = false
            elseif k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false
            elseif k == "REPETITION" then draw_board(); draw_cell(cell_of(bx, by))
            end
        end
        if move ~= 0 then
            local np = math.max(COL_MIN, math.min(COL_MAX - PADDLE_W + 1, paddle + 2 * move))
            if np ~= paddle then
                paddle = np
                local oc, orow = cell_of(bx, by)
                if stuck then bx = 2 * (paddle - 1) + PADDLE_W end
                draw_paddle()
                if orow ~= PADDLE_ROW then draw_cell(oc, orow) end
                draw_cell(cell_of(bx, by))
            end
        end

        if not stuck then
            local lost = false
            for _ = 1, math.abs(dx) do
                if not step(dx > 0 and 1 or -1, dx ~= 0 and 0 or dy) then lost = true; break end
            end
            if not lost and not step(0, dy) then lost = true end
            if lost then
                lives = lives - 1
                minitel.play_sound("damage")
                draw_status()
                if lives == 0 then io.flush(); return game_over_screen(false) end
                local oc, orow = cell_of(bx, by)
                reset_ball()
                if orow <= 24 then send(at(math.min(orow, 24), oc) .. " ") end
                draw_paddle()
                draw_cell(cell_of(bx, by))
            elseif bricks_left == 0 then
                level = level + 1
                score = score + 100 * level
                minitel.play_sound("win")
                if level > 9 then io.flush(); return game_over_screen(true) end
                new_level()
                reset_ball()
                draw_board()
                draw_cell(cell_of(bx, by))
                tick = math.max(0.025, 0.06 - 0.005 * (level - 1))
            end
        end
        io.flush()
        -- au rythme de la ligne a 9600 bauds, puis de la vitesse du niveau
        minitel.wait_output()
        minitel.sleep(tick)
    end
end

-- =====================================================================
-- LANCEMENT : passage en Videotex, puis retour en 80 colonnes
-- =====================================================================
minitel.force_videotex() -- clavier etendu compris : les fleches envoient ESC [ A..D

while title_screen() do
    if not play() then break end
end

send(FF .. CON)
io.flush()
minitel.force_80()
minitel.cleanup()
