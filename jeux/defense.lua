local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- GESTION DE LA CONFIGURATION ET SAUVEGARDE
-- =====================================================================
local config = {
    difficulty = 2 -- 1: Facile, 2: Normal, 3: Difficile
}
local diff_names = {"FACILE", "NORMAL", "DIFFICILE"}

local function load_config()
    local file = io.open("jeux/minitel_defense.cfg", "r")
    if file then
        for line in file:lines() do
            local k, v = string.match(line, "(%w+)=(%w+)")
            if k == "difficulty" then config.difficulty = tonumber(v) or 2 end
        end
        file:close()
    end
end

local function save_config()
    local file = io.open("jeux/minitel_defense.cfg", "w")
    if file then
        file:write("difficulty=" .. config.difficulty .. "\n")
        file:close()
    end
end

-- =====================================================================
-- PARAMETRES DE LA CARTE ET DU CHEMIN
-- =====================================================================
local map_w, map_h = 16, 10
local path_coords = {
    {1,2}, {2,2}, {3,2}, {4,2}, {5,2}, {6,2}, {7,2},
    {7,3}, {7,4}, {7,5}, {7,6},
    {8,6}, {9,6}, {10,6}, {11,6}, {12,6},
    {12,7}, {12,8},
    {13,8}, {14,8}, {15,8}, {16,8}
}

local is_path = {}
for _, p in ipairs(path_coords) do
    is_path[p[1] .. "," .. p[2]] = true
end

-- =====================================================================
-- ETAT DU JEU
-- =====================================================================
local state = "TITLE"
local menu_cursor = 1
local gold = 45
local hp = 10
local wave = 1
local enemies_to_spawn = 3
local enemies = {} 
local towers = {}  
local cx, cy = 8, 4
local msg = ""

local function reset_game()
    -- Ajustement selon la difficulté
    if config.difficulty == 1 then gold = 60; hp = 15
    elseif config.difficulty == 2 then gold = 45; hp = 10
    else gold = 30; hp = 5 end
    
    wave = 1
    enemies_to_spawn = 3
    enemies = {}
    towers = {}
    cx, cy = 8, 4
    msg = "JEU DEMARRE. PLACEZ VOS TOURELLES (15 OR)."
end

-- =====================================================================
-- AFFICHAGE : MENU PRINCIPAL
-- =====================================================================
local function draw_title()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[3;11H\x1b[7m==========================================================\x1b[0m\r\n")
    io.write("\x1b[4;11H\x1b[7m|                  3 6 1 5   D E F E N S E               |\x1b[0m\r\n")
    io.write("\x1b[5;11H\x1b[7m==========================================================\x1b[0m\r\n")
    
    io.write("\x1b[9;28H\x1b[1mMENU PRINCIPAL\x1b[0m\r\n")
    
    local options = {
        "NOUVELLE PARTIE",
        "DIFFICULTE : " .. diff_names[config.difficulty],
        "QUITTER LE JEU"
    }
    
    for i, opt in ipairs(options) do
        if i == menu_cursor then
            io.write("\x1b[" .. (11+i*2) .. ";25H\x1b[7m > " .. opt .. " \x1b[0m")
        else
            io.write("\x1b[" .. (11+i*2) .. ";25H   " .. opt .. "   ")
        end
    end
    
    io.write("\x1b[22;11H==========================================================\r\n")
    io.write("\x1b[23;13H ZQSD / FLECHES : NAVIGUER  |  ENVOI : VALIDER / CHANGER\r\n")
    io.flush()
end

-- =====================================================================
-- AFFICHAGE : JEU EN COURS
-- =====================================================================
local function draw_game_ui()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[1;11H\x1b[7m==========================================================\x1b[0m\r\n")
    io.write("\x1b[2;11H\x1b[7m|                  3 6 1 5   D E F E N S E               |\x1b[0m\r\n")
    io.write("\x1b[3;11H\x1b[7m==========================================================\x1b[0m\r\n")
    
    local stats = string.format(" VAGUE: %02d   |   OR: %03d   |   BASE HP: %02d ", wave, gold, hp)
    io.write("\x1b[5;20H\x1b[1m" .. stats .. "\x1b[0m\r\n")
    
    io.write("\x1b[21;4H========================================================================\r\n")
    io.write("\x1b[22;4H [ESPACE] BÂTIR TOUR (15 OR) | [ENVOI] FIN DE TOUR | [RETOUR] QUITTER \r\n")
    io.write("\x1b[23;4H MESSAGE : " .. msg .. " \x1b[K\r\n")
    io.flush()
end

local function draw_grid()
    for y = 1, map_h do
        io.write("\x1b[" .. (y+8) .. ";16H")
        for x = 1, map_w do
            local cell_key = x .. "," .. y
            local cell_str = " . "
            local is_inv = (cx == x and cy == y)
            
            local enemy_here = nil
            for _, e in ipairs(enemies) do
                local ex, ey = path_coords[e.pos][1], path_coords[e.pos][2]
                if ex == x and ey == y then enemy_here = e break end
            end

            if enemy_here then
                local hp_disp = enemy_here.hp
                if hp_disp > 9 then hp_disp = "+" end
                cell_str = "(" .. hp_disp .. ")"
            elseif towers[cell_key] then
                cell_str = "[T]"
            elseif is_path[cell_key] then
                cell_str = "   "
                if x == path_coords[1][1] and y == path_coords[1][2] then cell_str = "[S]" end
                if x == path_coords[#path_coords][1] and y == path_coords[#path_coords][2] then cell_str = "[B]" end
            else
                cell_str = " . "
            end

            if is_inv then
                io.write("\x1b[7m" .. cell_str .. "\x1b[0m")
            else
                io.write(cell_str)
            end
        end
    end
    io.flush()
end

-- =====================================================================
-- RESOLUTION D'UN TOUR
-- =====================================================================
local function execute_turn()
    msg = "RESOLUTION DU TOUR EN COURS..."
    io.write("\x1b[23;15H" .. msg .. "\x1b[K")
    io.flush()
    
    -- 1. Apparition des ennemis
    if enemies_to_spawn > 0 then
        -- HP augmente plus ou moins vite selon la difficulté
        local diff_scale = (config.difficulty == 3) and 1 or (config.difficulty == 2 and 0.5 or 0.25)
        local enemy_hp = 2 + math.floor(wave * diff_scale)
        table.insert(enemies, {pos=1, hp=enemy_hp, max_hp=enemy_hp})
        enemies_to_spawn = enemies_to_spawn - 1
    end
    
    -- 2. Les tourelles attaquent
    for t_pos, t in pairs(towers) do
        local tx, ty = string.match(t_pos, "(%d+),(%d+)")
        tx, ty = tonumber(tx), tonumber(ty)
        
        for _, e in ipairs(enemies) do
            local ex, ey = path_coords[e.pos][1], path_coords[e.pos][2]
            local dist = math.sqrt((tx-ex)^2 + (ty-ey)^2)
            
            if dist <= t.range then
                e.hp = e.hp - t.damage
                minitel.play_sound("hit")
                
                io.write("\x1b[" .. (ey+8) .. ";" .. (16 + (ex-1)*3 + 1) .. "H\x1b[7m*\x1b[0m")
                io.flush()
                minitel.sleep(0.15)
                draw_grid()
                break
            end
        end
    end
    
    -- 3. Nettoyage et gains
    for i = #enemies, 1, -1 do
        if enemies[i].hp <= 0 then
            gold = gold + 5
            table.remove(enemies, i)
            minitel.play_sound("pickup")
        end
    end
    
    -- 4. Déplacement des ennemis
    for i = #enemies, 1, -1 do
        enemies[i].pos = enemies[i].pos + 1
        if enemies[i].pos >= #path_coords then
            hp = hp - 1
            table.remove(enemies, i)
            minitel.play_sound("damage")
        end
    end
    
    -- 5. Vérification fin de vague
    if #enemies == 0 and enemies_to_spawn == 0 then
        wave = wave + 1
        enemies_to_spawn = 2 + wave
        gold = gold + 20
        msg = "VAGUE TERMINEE ! (+20 OR). PREPAREZ LA SUITE."
        minitel.play_sound("win")
    else
        msg = "TOUR TERMINE. A VOUS DE JOUER."
    end
    
    -- 6. Game Over ?
    if hp <= 0 then
        state = "GAMEOVER"
        msg = "BASE DETRUITE ! FIN DE PARTIE. [RETOUR] VERS LE MENU."
        minitel.play_sound("lose")
    end
    
    draw_game_ui()
    draw_grid()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
load_config()
draw_title()

while true do
    local key = minitel.get_key()
    
    if key then
        if state == "TITLE" then
            if key == "UP" or key == "z" or key == "Z" then
                menu_cursor = menu_cursor - 1
                if menu_cursor < 1 then menu_cursor = 3 end
                draw_title()
            elseif key == "DOWN" or key == "s" or key == "S" then
                menu_cursor = menu_cursor + 1
                if menu_cursor > 3 then menu_cursor = 1 end
                draw_title()
            elseif key == "ENVOI" or key == "\r" or key == "\n" then
                minitel.play_sound("hit")
                if menu_cursor == 1 then
                    -- JOUER
                    state = "PLAYING"
                    reset_game()
                    draw_game_ui()
                    draw_grid()
                elseif menu_cursor == 2 then
                    -- CHANGER DIFFICULTE
                    config.difficulty = config.difficulty + 1
                    if config.difficulty > 3 then config.difficulty = 1 end
                    save_config()
                    draw_title()
                elseif menu_cursor == 3 then
                    -- QUITTER
                    break
                end
            elseif key == "RETOUR" or key == "ESC" then
                break
            end
            
        elseif state == "PLAYING" then
            if key == "RETOUR" or key == "ESC" then
                state = "TITLE"
                draw_title()
            else
                if key == "RIGHT" or key == "d" or key == "D" then cx = cx + 1; if cx > map_w then cx = 1 end end
                if key == "LEFT"  or key == "q" or key == "Q" then cx = cx - 1; if cx < 1 then cx = map_w end end
                if key == "DOWN"  or key == "s" or key == "S" then cy = cy + 1; if cy > map_h then cy = 1 end end
                if key == "UP"    or key == "z" or key == "Z" then cy = cy - 1; if cy < 1 then cy = map_h end end
                
                if key == " " then
                    local cell_key = cx .. "," .. cy
                    if is_path[cell_key] then
                        msg = "IMPOSSIBLE DE CONSTRUIRE SUR LE CHEMIN !"
                        minitel.play_sound("blip")
                    elseif towers[cell_key] then
                        msg = "IL Y A DEJA UNE TOUR ICI."
                        minitel.play_sound("blip")
                    elseif gold >= 15 then
                        gold = gold - 15
                        towers[cell_key] = {damage=1, range=2.5}
                        msg = "TOUR CONSTRUITE !"
                        minitel.play_sound("pickup")
                    else
                        msg = "PAS ASSEZ D'OR (COÛT: 15)."
                        minitel.play_sound("blip")
                    end
                    draw_game_ui()
                end
                
                if key == "ENVOI" or key == "\r" or key == "\n" then
                    execute_turn()
                end
                
                draw_grid()
            end
            
        elseif state == "GAMEOVER" then
            if key == "RETOUR" or key == "ESC" or key == "ENVOI" or key == "\r" or key == "\n" then
                state = "TITLE"
                draw_title()
            end
        end
    end
    minitel.sleep(0.02)
end

minitel.cleanup()