-- Fichier : jeux/donjon_videotex.lua
-- 3615 DONJON : le jeu de role de rpg.lua en Videotex couleur. Memes regles
-- (donjon tire au hasard a chaque etage, monstres de plus en plus forts,
-- potions, bonus de force, combat au tour par tour, niveaux d'experience),
-- dans un donjon en couleurs : murs en mosaiques bleues, monstres en rouge,
-- potions en vert. Le Minitel repasse en 40 colonnes le temps de la partie.
-- Reglages : ceux de la version 80 colonnes, jeux/minitel_rpg.cfg.
-- @GENRE: AVENTURE / VIDEOTEX COULEUR
-- @DESC: Le jeu de role en Videotex couleur : donjon au hasard, monstres, potions et combats au tour par tour. Fleches ou Z Q S D.

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
local BLINK, STEADY = ESC .. "\x48", ESC .. "\x49"
local NORMAL_SIZE, DOUBLE_HEIGHT, DOUBLE_SIZE = ESC .. "\x4c", ESC .. "\x4d", ESC .. "\x4f"
local FULL = string.char(0x7f)

local function send(s) io.write(s) end
local function rep(ch, n)
    if n <= 0 then return "" end
    if n == 1 then return ch end
    return ch .. REP .. string.char(0x40 + n - 1)
end

local function line(row, color, text)
    send(at(row, 1) .. fg(color) .. text .. string.rep(" ", math.max(0, 40 - #text)))
end

-- =====================================================================
-- CLAVIER EN VIDEOTEX
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

local function wait_key()
    while true do
        local k = read_key()
        if k then return k end
        minitel.sleep(0.03)
    end
end

local DIRS = { UP = { 0, -1 }, Z = { 0, -1 }, ["8"] = { 0, -1 }, DOWN = { 0, 1 }, S = { 0, 1 }, ["2"] = { 0, 1 },
               LEFT = { -1, 0 }, Q = { -1, 0 }, ["4"] = { -1, 0 }, RIGHT = { 1, 0 }, D = { 1, 0 }, ["6"] = { 1, 0 } }

-- =====================================================================
-- REGLAGES (partages avec la version 80 colonnes)
-- =====================================================================
local config = { START_HP = 30, BASE_ENEMIES = 8, ENEMY_MULT = 2.0, POTIONS = 5, MAP_DENSITY = 100 }
do
    local f = io.open("jeux/minitel_rpg.cfg", "r")
    if f then
        for l in f:lines() do
            local k, v = string.match(l, "([^=]+)=(.+)")
            if k and config[k] ~= nil then config[k] = tonumber(v) or config[k] end
        end
        f:close()
    end
end
local MAX_ENEMIES, POTION_DECAY, HEAL_MIN, HEAL_MAX = 30, 4, 15, 25

local BESTIAIRE = {
    { name = "RAT GEANT", ch = "r", color = JAUNE, hp = 10, atk = 2 },
    { name = "GOBELIN", ch = "g", color = VERT, hp = 15, atk = 4 },
    { name = "SQUELETTE", ch = "s", color = BLANC, hp = 22, atk = 6 },
    { name = "ORQUE", ch = "o", color = MAGENTA, hp = 30, atk = 8 },
    { name = "TROLL", ch = "T", color = CYAN, hp = 45, atk = 11 },
    { name = "DRAGON", ch = "D", color = ROUGE, hp = 70, atk = 16 },
}

-- =====================================================================
-- ETAT DE LA PARTIE
-- =====================================================================
local MAP_W, MAP_H, MAP_TOP = 40, 16, 2   -- carte en lignes 2 a 17
local map, enemies, items = {}, {}, {}
local px, py
local depth, hp, hp_max, lvl, xp, kills, power = 1, 0, 0, 1, 0, 0, 0
local msg = ""

local function tile(x, y) return map[y] and map[y][x] or "#" end

local function generate_map()
    local grid = {}
    for y = 1, MAP_H do
        grid[y] = {}
        for x = 1, MAP_W do grid[y][x] = "#" end
    end
    local d = config.MAP_DENSITY / 100
    local rooms = {}
    local n = math.max(2, math.min(9, math.floor(math.random(4, 6) * d)))
    for i = 1, n do
        local rw = math.max(3, math.min(12, math.floor(math.random(4, 9) * d)))
        local rh = math.max(3, math.min(7, math.floor(math.random(3, 5) * d)))
        local rx, ry = math.random(2, MAP_W - rw - 1), math.random(2, MAP_H - rh - 1)
        for y = ry, ry + rh - 1 do for x = rx, rx + rw - 1 do grid[y][x] = "." end end
        rooms[i] = { cx = rx + rw // 2, cy = ry + rh // 2 }
        if i > 1 then
            local a, b = rooms[i - 1], rooms[i]
            if math.random() > 0.5 then
                for x = math.min(a.cx, b.cx), math.max(a.cx, b.cx) do grid[a.cy][x] = "." end
                for y = math.min(a.cy, b.cy), math.max(a.cy, b.cy) do grid[y][b.cx] = "." end
            else
                for y = math.min(a.cy, b.cy), math.max(a.cy, b.cy) do grid[y][a.cx] = "." end
                for x = math.min(a.cx, b.cx), math.max(a.cx, b.cx) do grid[b.cy][x] = "." end
            end
        end
    end
    grid[rooms[#rooms].cy][rooms[#rooms].cx] = ">"
    px, py = rooms[1].cx, rooms[1].cy
    return grid
end

local function free_spot(min_dist)
    for _ = 1, 2000 do
        local x, y = math.random(2, MAP_W - 1), math.random(2, MAP_H - 1)
        if map[y][x] == "." and math.abs(x - px) + math.abs(y - py) >= min_dist then
            local taken = false
            for _, e in ipairs(enemies) do if e.alive and e.x == x and e.y == y then taken = true end end
            for _, it in ipairs(items) do if it.active and it.x == x and it.y == y then taken = true end end
            if not taken then return x, y end
        end
    end
    return px, py
end

local function enemy_at(x, y)
    for _, e in ipairs(enemies) do if e.alive and e.x == x and e.y == y then return e end end
end

local function item_at(x, y)
    for _, it in ipairs(items) do if it.active and it.x == x and it.y == y then return it end end
end

local function init_floor()
    map = generate_map()
    enemies, items = {}, {}
    local count = math.min(MAX_ENEMIES, math.floor(config.BASE_ENEMIES + depth * config.ENEMY_MULT))
    local lo = math.min(#BESTIAIRE - 1, 1 + depth // 3)
    local hi = math.min(#BESTIAIRE, lo + 2)
    for _ = 1, count do
        local t = BESTIAIRE[math.random(lo, hi)]
        local x, y = free_spot(4)
        local life = t.hp + depth * 3
        enemies[#enemies + 1] = { x = x, y = y, t = t, hp = life, max = life, atk = t.atk + depth, alive = true }
    end
    for _ = 1, math.max(1, config.POTIONS - depth // POTION_DECAY) do
        local x, y = free_spot(2)
        items[#items + 1] = { x = x, y = y, kind = "HP", active = true }
    end
    for _ = 1, math.random(1, 2) do
        local x, y = free_spot(2)
        items[#items + 1] = { x = x, y = y, kind = "ATK", active = true }
    end
end

-- =====================================================================
-- AFFICHAGE DE LA CARTE
-- =====================================================================
-- Contenu d'une case : murs bleus, sol pointille, objets, monstres, joueur
local function cell(x, y)
    if x == px and y == py then return fg(JAUNE) .. "@" end
    local e = enemy_at(x, y)
    if e then return fg(e.t.color) .. e.t.ch end
    local it = item_at(x, y)
    if it then return it.kind == "HP" and (fg(VERT) .. "+") or (fg(CYAN) .. "*") end
    local t = tile(x, y)
    if t == "#" then return fg(BLEU) .. SO .. FULL .. SI end
    if t == ">" then return fg(BLANC) .. BLINK .. ">" .. STEADY end
    return fg(BLEU) .. "."
end

local function draw_cell(x, y)
    send(at(MAP_TOP + y - 1, x) .. cell(x, y))
end

local function draw_map()
    for y = 1, MAP_H do
        local out, x = { at(MAP_TOP + y - 1, 1) }, 1
        while x <= MAP_W do
            if tile(x, y) == "#" then
                local n = 0
                while x + n <= MAP_W and tile(x + n, y) == "#" do n = n + 1 end
                out[#out + 1] = fg(BLEU) .. SO .. rep(FULL, n) .. SI
                x = x + n
            else
                out[#out + 1] = cell(x, y)
                x = x + 1
            end
        end
        send(table.concat(out))
    end
end

local function bar(row, label, value, max, width, color)
    local n = math.max(0, math.min(width, math.floor(width * value / math.max(1, max) + 0.5)))
    send(at(row, 1) .. fg(BLANC) .. label .. fg(color) .. SO .. rep(FULL, n) .. SI ..
        fg(BLEU) .. SO .. rep(string.char(0x20 + 16 + 64), width - n) .. SI ..
        fg(BLANC) .. string.format(" %d/%d  ", math.max(0, value), max))
end

local function draw_hud()
    send(at(1, 1) .. fg(MAGENTA) .. "3615 DONJON" .. at(1, 14) .. fg(CYAN) ..
        string.format("ETAGE %d  NIV %d  FORCE +%d ", depth, lvl, power))
    bar(19, "VIE ", hp, hp_max, 20, hp <= hp_max // 4 and ROUGE or VERT)
    bar(20, "EXP ", xp, lvl * 10, 20, JAUNE)
end

local function draw_msg()
    local lines = minitel.wrap(msg, 40, 2)
    line(21, JAUNE, lines[1] or "")
    line(22, JAUNE, lines[2] or "")
end

local function draw_screen()
    send(FF .. COFF)
    draw_map()
    send(at(18, 1) .. fg(BLEU) .. SO .. rep(string.char(0x20 + 1 + 2), 40) .. SI)
    draw_hud()
    draw_msg()
    line(24, BLANC, "FLECHES/ZQSD  > DESCENDRE  SOMMAIRE FIN")
end

-- =====================================================================
-- COMBAT
-- =====================================================================
-- Silhouette de monstre en mosaique : 12 x 9 pixels (6 cases sur 3 lignes)
local SPRITE = {
    "..XX....XX..",
    ".XXXX..XXXX.",
    "XX..XXXX..XX",
    "XXXXXXXXXXXX",
    ".XX.XXXX.XX.",
    "..XXXXXXXX..",
    "...X.XX.X...",
    "..XX....XX..",
    ".XX......XX.",
}
local PIXEL_BIT = { { 1, 2 }, { 4, 8 }, { 16, 64 } }

local function sprite_rows()
    local rows = {}
    for cr = 0, 2 do
        local chars = {}
        for cc = 0, 5 do
            local bits = 0
            for y = 1, 3 do
                for x = 1, 2 do
                    if SPRITE[cr * 3 + y]:sub(cc * 2 + x, cc * 2 + x) == "X" then bits = bits | PIXEL_BIT[y][x] end
                end
            end
            chars[#chars + 1] = string.char(0x20 + bits)
        end
        rows[cr + 1] = table.concat(chars)
    end
    return rows
end
local SPRITE_ROWS = sprite_rows()

local ACTIONS = { "ATTAQUE", "COUP FORT", "POTION", "FUITE" }

-- Rend "WIN", "FLED" ou "DEAD"
local function combat(e)
    local choice = 1
    local text = "UN " .. e.t.name .. " VOUS BARRE LA ROUTE !"
    local function draw_menu()
        local out = { at(16, 1) }
        for i, a in ipairs(ACTIONS) do
            if i == choice then out[#out + 1] = fg(JAUNE) .. ">" .. a .. "< "
            else out[#out + 1] = fg(BLANC) .. " " .. a .. "  " end
        end
        send(table.concat(out) .. "  ")
    end
    local function draw_state()
        bar(10, "    ", e.hp, e.max, 22, ROUGE)
        bar(19, "VIE ", hp, hp_max, 20, hp <= hp_max // 4 and ROUGE or VERT)
        local lines = minitel.wrap(text, 40, 2)
        line(13, JAUNE, lines[1] or "")
        line(14, JAUNE, lines[2] or "")
        draw_menu()
        io.flush()
    end
    send(FF .. COFF)
    send(at(1, 1) .. fg(ROUGE) .. BLINK .. "COMBAT !" .. STEADY .. at(1, 14) .. fg(CYAN) ..
        string.format("ETAGE %d  NIV %d", depth, lvl))
    for i, r in ipairs(SPRITE_ROWS) do
        send(at(3 + i, 17) .. fg(e.t.color) .. SO .. r .. SI)
    end
    send(at(9, 1) .. fg(e.t.color) .. DOUBLE_HEIGHT .. minitel.center(e.t.name, 40) .. NORMAL_SIZE)
    line(18, BLANC, "GAUCHE/DROITE OU 1-4, PUIS ENVOI")
    minitel.play_sound("hit")
    draw_state()

    while true do
        local k = wait_key()
        local act
        if k == "LEFT" or k == "Q" then choice = choice > 1 and choice - 1 or 4; draw_menu(); io.flush()
        elseif k == "RIGHT" or k == "D" then choice = choice < 4 and choice + 1 or 1; draw_menu(); io.flush()
        elseif tonumber(k) and tonumber(k) >= 1 and tonumber(k) <= 4 then choice = tonumber(k); act = choice
        elseif k == "ENVOI" or k == " " then act = choice
        end
        if act then
            if act == 1 then
                if math.random() < 0.95 then
                    local dmg = math.random(4, 7) + lvl + power
                    e.hp = e.hp - dmg
                    text = "VOUS FRAPPEZ : " .. dmg .. " POINTS DE DEGATS."
                    minitel.play_sound("hit")
                else
                    text = "LE " .. e.t.name .. " ESQUIVE !"
                end
            elseif act == 2 then
                if math.random() < 0.60 then
                    local dmg = math.random(9, 16) + lvl + power * 3
                    e.hp = e.hp - dmg
                    text = "COUP FORT ! " .. dmg .. " POINTS DE DEGATS."
                    minitel.play_sound("hit")
                else
                    text = "COUP FORT MANQUE !"
                end
            elseif act == 3 then
                local heal = math.random(HEAL_MIN, HEAL_MAX)
                hp = math.min(hp_max, hp + heal)
                text = "VOUS BUVEZ UNE POTION : +" .. heal .. " VIE."
                minitel.play_sound("pickup")
            elseif act == 4 then
                if math.random() < 0.5 then
                    msg = "VOUS PRENEZ LA FUITE. LES MONSTRES CHANGENT DE PLACE."
                    return "FLED"
                end
                text = "IMPOSSIBLE DE FUIR !"
            end
            draw_state()
            minitel.sleep(0.8)
            if e.hp <= 0 then
                e.alive = false
                kills = kills + 1
                local gain = math.random(5, 10) + depth
                xp = xp + gain
                if xp >= lvl * 10 then
                    lvl, xp = lvl + 1, 0
                    hp_max = hp_max + 8
                    hp = hp_max
                    msg = "LE " .. e.t.name .. " EST VAINCU ! VOUS PASSEZ AU NIVEAU " .. lvl .. " !"
                    minitel.play_sound("win")
                else
                    msg = "LE " .. e.t.name .. " EST VAINCU ! +" .. gain .. " EXP."
                    minitel.play_sound("pickup")
                end
                return "WIN"
            end
            local dmg = e.atk + math.random(0, depth // 2)
            hp = hp - dmg
            text = "LE " .. e.t.name .. " RIPOSTE : -" .. dmg .. " VIE."
            minitel.play_sound("damage")
            draw_state()
            if hp <= 0 then return "DEAD" end
        end
    end
end

local function reshuffle()
    for _, e in ipairs(enemies) do
        if e.alive then e.x, e.y = -1, -1 end
    end
    for _, e in ipairs(enemies) do
        if e.alive then e.x, e.y = free_spot(4) end
    end
end

-- =====================================================================
-- ECRANS DE TITRE ET DE FIN
-- =====================================================================
local function title_screen()
    send(FF .. COFF)
    for r = 2, 8 do
        send(at(r, 1) .. fg(BLEU) .. SO .. rep(FULL, 40) .. SI)
    end
    send(at(6, 11) .. fg(JAUNE) .. DOUBLE_SIZE .. " DONJON " .. NORMAL_SIZE)
    for i, r in ipairs(SPRITE_ROWS) do
        send(at(10 + i, 4) .. fg(ROUGE) .. SO .. r .. SI .. at(10 + i, 31) .. fg(VERT) .. SO .. r .. SI)
    end
    send(at(11, 13) .. fg(CYAN) .. "LE JEU DE ROLE")
    send(at(12, 13) .. fg(CYAN) .. "EN COULEURS")
    send(at(16, 3) .. fg(JAUNE) .. "@" .. fg(BLANC) .. " VOUS     " .. fg(VERT) .. "+" .. fg(BLANC) .. " POTION   " ..
        fg(CYAN) .. "*" .. fg(BLANC) .. " FORCE")
    send(at(17, 3) .. fg(BLANC) .. BLINK .. ">" .. STEADY .. fg(BLANC) .. " ESCALIER " .. fg(ROUGE) .. "D" ..
        fg(BLANC) .. " MONSTRE (LETTRE)")
    local best = minitel.get_record("DONJON")
    if best then send(at(19, 3) .. fg(MAGENTA) .. string.format("RECORD : ETAGE %d", best)) end
    send(at(21, 9) .. fg(JAUNE) .. BLINK .. "ENVOI : ENTRER" .. STEADY)
    send(at(22, 9) .. fg(BLANC) .. "SOMMAIRE : QUITTER")
    io.flush()
    while true do
        local k = wait_key()
        if k == "ENVOI" or k == " " then return true end
        if k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false end
    end
end

local function game_over_screen()
    minitel.submit_record("DONJON", depth, "high", "ETAGES", kills .. " MONSTRES, NIV " .. lvl)
    send(FF .. COFF)
    send(at(6, 1) .. fg(ROUGE) .. DOUBLE_HEIGHT .. BLINK .. minitel.center("VOUS ETES MORT", 40) .. STEADY .. NORMAL_SIZE)
    send(at(10, 8) .. fg(BLANC) .. "ETAGE ATTEINT  : " .. fg(JAUNE) .. depth)
    send(at(12, 8) .. fg(BLANC) .. "MONSTRES VAINCUS : " .. fg(JAUNE) .. kills)
    send(at(14, 8) .. fg(BLANC) .. "NIVEAU FINAL   : " .. fg(JAUNE) .. lvl)
    send(at(19, 8) .. fg(VERT) .. "ENVOI : RETOUR AU TITRE")
    io.flush()
    for _ = 1, 3 do minitel.play_sound("lose"); minitel.sleep(0.3) end
    while true do
        local k = wait_key()
        if k == "ENVOI" or k == " " or k == "SOMMAIRE" or k == "ESC" or k == "RETOUR" then return end
    end
end

-- =====================================================================
-- PARTIE
-- =====================================================================
-- Rend false pour quitter le jeu
local function play()
    depth, lvl, xp, kills, power = 1, 1, 0, 0, 0
    hp, hp_max = config.START_HP, config.START_HP
    msg = "TROUVEZ L'ESCALIER (>) POUR DESCENDRE."
    init_floor()
    draw_screen()
    io.flush()
    while true do
        local k = wait_key()
        local d = DIRS[k]
        if k == "SOMMAIRE" or k == "ESC" or k == "RETOUR" then
            msg = "QUITTER LA PARTIE ? O / N"
            draw_msg(); io.flush()
            local a = wait_key()
            if a == "O" then return true end
            msg = "LA PARTIE CONTINUE."
            draw_msg()
        elseif k == "REPETITION" then
            draw_screen()
        elseif d then
            local nx, ny = px + d[1], py + d[2]
            local e = enemy_at(nx, ny)
            if e then
                local r = combat(e)
                if r == "DEAD" then game_over_screen(); return true end
                reshuffle()
                draw_screen()
            elseif tile(nx, ny) == ">" then
                depth = depth + 1
                msg = "VOUS DESCENDEZ A L'ETAGE " .. depth .. ". LES MONSTRES SONT PLUS FORTS."
                minitel.play_sound("pickup")
                init_floor()
                draw_screen()
            elseif tile(nx, ny) ~= "#" then
                local ox, oy = px, py
                px, py = nx, ny
                local it = item_at(nx, ny)
                if it then
                    it.active = false
                    minitel.play_sound("pickup")
                    if it.kind == "HP" then
                        local heal = math.random(HEAL_MIN, HEAL_MAX)
                        hp = math.min(hp_max, hp + heal)
                        msg = "UNE POTION ! +" .. heal .. " VIE."
                    else
                        power = power + 1
                        msg = "UNE GEMME DE FORCE ! FORCE +" .. power .. "."
                    end
                    draw_hud()
                    draw_msg()
                end
                draw_cell(ox, oy)
                draw_cell(px, py)
            end
        end
        io.flush()
        minitel.wait_output()
    end
end

-- =====================================================================
-- LANCEMENT : passage en Videotex, puis retour en 80 colonnes
-- =====================================================================
math.randomseed(os.time())
minitel.force_videotex()

while title_screen() do
    play()
end

send(FF .. CON)
io.flush()
minitel.force_80()
minitel.cleanup()
