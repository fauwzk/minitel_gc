local minitel = require("minitel")
minitel.init()

local config = {
    DIFFICULTY = 2,
    WIDTH = 15,
    HEIGHT = 12,
    MINES = 25,
    SOUND = 1
}

local function play_game_sound(effect)
    if config.SOUND == 1 then minitel.play_sound(effect) end
end

local function apply_difficulty()
    if config.DIFFICULTY == 1 then config.WIDTH, config.HEIGHT, config.MINES = 9, 9, 10
    elseif config.DIFFICULTY == 2 then config.WIDTH, config.HEIGHT, config.MINES = 15, 12, 25
    elseif config.DIFFICULTY == 3 then config.WIDTH, config.HEIGHT, config.MINES = 24, 15, 60
    end
end

local function load_config()
    local file = io.open("minitel_mines.cfg", "r")
    if file then
        for line in file:lines() do
            local k, v = string.match(line, "([^=]+)=(.+)")
            if k and v and config[k] ~= nil then config[k] = tonumber(v) or config[k] end
        end
        file:close()
    end
end

local function save_config()
    local file = io.open("minitel_mines.cfg", "w")
    if file then
        for k, v in pairs(config) do file:write(k .. "=" .. tostring(v) .. "\n") end
        file:close()
    end
end

load_config()

local state = "TITLE" 
local board = {}
local cursor_x, cursor_y = 1, 1
local first_click = true
local flags_placed = 0
local cells_revealed = 0
local total_safe_cells = 0
local title_cursor = 1
local settings_cursor = 1
local msg_board = ""

local function draw_title(full_redraw)
    if full_redraw then
        io.write("\x1b[2J\x1b[H") 
        io.flush()
        minitel.sleep(0.08) 
        io.write("\x1b[4;13H======================================================\r\n")
        io.write("\x1b[5;13H|                                                    |\r\n")
        io.write("\x1b[6;13H|           \x1b[1mM I N I T E L   S W E E P E R\x1b[0m            |\r\n")
        io.write("\x1b[7;13H|                                                    |\r\n")
        io.write("\x1b[8;13H======================================================\r\n")
        io.write("\x1b[11;24H LOGIQUE ET DEDUCTION EN 1200 BAUDS \r\n")
    end
    
    local b_jouer = (title_cursor == 1) and "\x1b[7m [ DEPLOYER LA GRILLE ] \x1b[0m"  or "   DEPLOYER LA GRILLE   "
    local b_param = (title_cursor == 2) and "\x1b[7m [ PARAMETRES DU JEU ] \x1b[0m"   or "   PARAMETRES DU JEU   "
    local b_quit  = (title_cursor == 3) and "\x1b[7m [ QUITTER ] \x1b[0m"             or "   QUITTER   "
    
    io.write("\x1b[16;1H\x1b[K\x1b[16;28H" .. b_jouer .. "\r\n")
    io.write("\x1b[18;1H\x1b[K\x1b[18;30H" .. b_param .. "\r\n")
    io.write("\x1b[20;1H\x1b[K\x1b[20;34H" .. b_quit .. "\r\n")
    io.write("\x1b[23;14H ZQSD / FLECHES : NAVIGUER  |  ENVOI : VALIDER \r\n")
    io.flush()
end

local function draw_settings()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    io.write("\x1b[3;25H\x1b[7m PARAMETRES DU DEMINEUR \x1b[0m\r\n\n")
    local diff_str = {"FACILE", "MOYEN", "EXTREME", "PERSO"}
    local snd_str = {"MUET", "ACTIF"}
    local max_mines = math.floor((config.WIDTH * config.HEIGHT) * 0.5)
    if config.MINES > max_mines then config.MINES = max_mines end

    local opts = {
        {name="DIFFICULTE PREDETERMINEE", val=diff_str[config.DIFFICULTY]},
        {name="LARGEUR (MAX 24)", val=tostring(config.WIDTH)},
        {name="HAUTEUR (MAX 15)", val=tostring(config.HEIGHT)},
        {name="MINES (MAX 50%)", val=tostring(config.MINES)},
        {name="BUZZER MATERIEL", val=snd_str[config.SOUND + 1]},
        {name="RETOUR (SAUVEGARDER)", val=""}
    }

    for i, o in ipairs(opts) do
        local line = string.format("\x1b[%d;12H", 5 + (i*2))
        if i == settings_cursor then line = line .. "\x1b[7m> " .. o.name
        else line = line .. "  " .. o.name end

        if o.val ~= "" then
            if i == settings_cursor then line = line .. string.rep(" ", 32 - string.len(o.name)) .. "[< " .. o.val .. " >]\x1b[0m"
            else line = line .. string.rep(" ", 32 - string.len(o.name)) .. "   " .. o.val .. "   \x1b[0m" end
        else line = line .. " \x1b[0m" end
        io.write(line .. "\r\n")
    end
    io.write("\x1b[22;12H FLECHES: MODIFIER & NAVIGUER  |  ENVOI: VALIDER ")
    io.flush()
end

local function modify_setting(dir)
    if settings_cursor == 1 then
        config.DIFFICULTY = math.max(1, math.min(4, config.DIFFICULTY + dir))
        apply_difficulty()
    elseif settings_cursor >= 2 and settings_cursor <= 4 then
        config.DIFFICULTY = 4 
        if settings_cursor == 2 then config.WIDTH = math.max(8, math.min(24, config.WIDTH + dir))
        elseif settings_cursor == 3 then config.HEIGHT = math.max(8, math.min(15, config.HEIGHT + dir))
        elseif settings_cursor == 4 then
            local limit = math.floor((config.WIDTH * config.HEIGHT) * 0.5)
            config.MINES = math.max(1, math.min(limit, config.MINES + dir))
        end
    elseif settings_cursor == 5 then config.SOUND = 1 - config.SOUND end
end

local function init_game()
    board = {}
    flags_placed = 0
    cells_revealed = 0
    first_click = true
    total_safe_cells = (config.WIDTH * config.HEIGHT) - config.MINES
    cursor_x = math.floor(config.WIDTH / 2)
    cursor_y = math.floor(config.HEIGHT / 2)
    
    for y = 1, config.HEIGHT do
        board[y] = {}
        for x = 1, config.WIDTH do
            board[y][x] = { is_mine = false, revealed = false, flagged = false, neighbors = 0 }
        end
    end
end

local function place_mines(safe_x, safe_y)
    local placed = 0
    while placed < config.MINES do
        local rx = math.random(1, config.WIDTH)
        local ry = math.random(1, config.HEIGHT)
        local is_safe = math.abs(rx - safe_x) <= 1 and math.abs(ry - safe_y) <= 1
        
        if not is_safe and not board[ry][rx].is_mine then
            board[ry][rx].is_mine = true
            placed = placed + 1
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local nx, ny = rx + dx, ry + dy
                    if nx >= 1 and nx <= config.WIDTH and ny >= 1 and ny <= config.HEIGHT then
                        board[ny][nx].neighbors = board[ny][nx].neighbors + 1
                    end
                end
            end
        end
    end
end

local function update_hud()
    local mines_left = config.MINES - flags_placed
    io.write("\x1b[2;1H\x1b[K\x1b[7m MINES RESTANTES : " .. string.format("%02d", mines_left) .. " \x1b[0m")
    local status_color = (state == "GAMEOVER") and "\x1b[7m" or ""
    io.write("\x1b[2;35H\x1b[K" .. status_color .. " ETAT : " .. state .. " \x1b[0m")
    io.flush()
end

local function update_msg()
    io.write("\x1b[21;1H\x1b[K  " .. msg_board)
    io.flush()
end

local function draw_cell(x, y)
    local cell = board[y][x]
    local is_cursor = (x == cursor_x and y == cursor_y)
    local str = ""
    local invert = is_cursor
    
    if cell.revealed then
        if cell.is_mine then
            str = " * "
            invert = true
        elseif cell.neighbors > 0 then str = " " .. cell.neighbors .. " "
        else str = "   " end
    else
        if cell.flagged then str = " P "
        else str = " . " end
    end
    
    if invert then str = "\x1b[7m" .. str .. "\x1b[0m" end
    local offset_x = math.floor((80 - (config.WIDTH * 3)) / 2)
    io.write(string.format("\x1b[%d;%dH%s", 4 + y, offset_x + (x - 1) * 3, str))
end

local function draw_full_board()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)
    io.write("\x1b[23;1H\x1b[K ZQSD/FL: BOUGER | ENVOI: CREUSER | F: DRAPEAU | RETOUR: MENU ")
    update_hud()
    for y = 1, config.HEIGHT do
        for x = 1, config.WIDTH do draw_cell(x, y) end
    end
    io.flush()
end

local function check_win()
    if cells_revealed == total_safe_cells and state ~= "GAMEOVER" then
        state = "VICTORY"
        msg_board = "SECTEUR SECURISE ! VOUS AVEZ GAGNE !"
        play_game_sound("win")
    end
end

local function reveal_all_mines()
    for y = 1, config.HEIGHT do
        for x = 1, config.WIDTH do
            if board[y][x].is_mine then
                board[y][x].revealed = true
                draw_cell(x, y)
            end
        end
    end
    io.flush()
end

local function reveal(start_x, start_y)
    local cell = board[start_y][start_x]
    if cell.flagged or cell.revealed then return end
    if first_click then place_mines(start_x, start_y) first_click = false end
    
    local stack = {{x = start_x, y = start_y}}
    while #stack > 0 do
        local curr = table.remove(stack)
        local cx, cy = curr.x, curr.y
        local c = board[cy][cx]
        
        if not c.revealed and not c.flagged then
            c.revealed = true
            cells_revealed = cells_revealed + 1
            draw_cell(cx, cy)
            
            if c.is_mine then
                state = "GAMEOVER"
                msg_board = "VOUS AVEZ DECLENCHE UNE MINE !"
                return
            end
            
            if c.neighbors == 0 then
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nx, ny = cx + dx, cy + dy
                        if nx >= 1 and nx <= config.WIDTH and ny >= 1 and ny <= config.HEIGHT then
                            if not board[ny][nx].revealed and not board[ny][nx].flagged then table.insert(stack, {x = nx, y = ny}) end
                        end
                    end
                end
            end
        end
    end
end

math.randomseed(os.time())
draw_title(true)

while true do
    local key = minitel.get_key()
    
    if (key == "RETOUR" or key == "ESC") and state ~= "TITLE" then
        if state == "SETTINGS" then save_config() end
        state = "TITLE"
        title_cursor = 1
        draw_title(true)
    else
        if state == "TITLE" then
            if key == "z" or key == "Z" or key == "UP" then
                title_cursor = (title_cursor == 1) and 3 or title_cursor - 1
                draw_title(false)
            elseif key == "s" or key == "S" or key == "DOWN" then
                title_cursor = (title_cursor == 3) and 1 or title_cursor + 1
                draw_title(false)
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                play_game_sound("hit")
                if title_cursor == 1 then
                    state = "MAP"
                    msg_board = "ZONE HOSTILE. PROCEDEZ AVEC PRUDENCE."
                    init_game()
                    draw_full_board()
                    update_msg()
                elseif title_cursor == 2 then
                    state = "SETTINGS"
                    settings_cursor = 1
                    draw_settings()
                elseif title_cursor == 3 then
                    break 
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "SETTINGS" then
            if key == "z" or key == "Z" or key == "UP" then
                settings_cursor = (settings_cursor == 1) and 6 or settings_cursor - 1
                draw_settings()
            elseif key == "s" or key == "S" or key == "DOWN" then
                settings_cursor = (settings_cursor == 6) and 1 or settings_cursor + 1
                draw_settings()
            elseif key == "q" or key == "Q" or key == "LEFT" then modify_setting(-1) draw_settings()
            elseif key == "d" or key == "D" or key == "RIGHT" then modify_setting(1) draw_settings()
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                play_game_sound("hit")
                if settings_cursor == 6 then
                    save_config()
                    state = "TITLE"
                    draw_title(true)
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "MAP" then
            local old_x, old_y = cursor_x, cursor_y
            local moved = false
            
            if key == "z" or key == "Z" or key == "UP" then cursor_y = math.max(1, cursor_y - 1) moved = true end
            if key == "s" or key == "S" or key == "DOWN" then cursor_y = math.min(config.HEIGHT, cursor_y + 1) moved = true end
            if key == "q" or key == "Q" or key == "LEFT" then cursor_x = math.max(1, cursor_x - 1) moved = true end
            if key == "d" or key == "D" or key == "RIGHT" then cursor_x = math.min(config.WIDTH, cursor_x + 1) moved = true end
            
            if moved and (old_x ~= cursor_x or old_y ~= cursor_y) then
                draw_cell(old_x, old_y)
                draw_cell(cursor_x, cursor_y)
                io.flush()
            elseif key == "f" or key == "F" then
                local c = board[cursor_y][cursor_x]
                if not c.revealed then
                    c.flagged = not c.flagged
                    flags_placed = flags_placed + (c.flagged and 1 or -1)
                    draw_cell(cursor_x, cursor_y)
                    update_hud()
                    play_game_sound("pickup")
                end
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                if not board[cursor_y][cursor_x].flagged and not board[cursor_y][cursor_x].revealed then
                    reveal(cursor_x, cursor_y)
                    io.flush()
                    if state == "GAMEOVER" then
                        play_game_sound("damage")
                        reveal_all_mines()
                        update_hud()
                        update_msg()
                    else
                        check_win()
                        if state == "VICTORY" then update_hud() update_msg() end
                    end
                end
            end
            minitel.sleep(0.02)
            
        elseif state == "GAMEOVER" or state == "VICTORY" then
            if key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                state = "TITLE"
                draw_title(true)
            end
            minitel.sleep(0.05)
        end
    end
end

minitel.cleanup()
