local minitel = require("minitel")
minitel.init()

local function scan_games()
    local game_list = {}
    local f = io.popen("ls -1 *.lua 2>/dev/null")
    if f then
        for file in f:lines() do
            -- On exclut le launcher lui-même, la lib minitel, et le master
            if file ~= "launcher.lua" and file ~= "minitel.lua" and file ~= "master.lua" then
                local name = string.upper(string.sub(file, 1, -5))
                table.insert(game_list, { filename = file, display = name })
            end
        end
        f:close()
    end
    if #game_list == 0 then table.insert(game_list, { filename = nil, display = "AUCUN JEU DETECTE" }) end
    return game_list
end

local games = scan_games()
local cursor = 1

local function draw_static_menu()
    io.write("\x1b[2J\x1b[H") 
    io.flush()
    minitel.sleep(0.08)
    
    io.write("\x1b[2;11H==========================================================\r\n")
    io.write("\x1b[3;11H|               \x1b[1m MODULE DE DIVERTISSEMENT \x1b[0m               |\r\n")
    io.write("\x1b[4;11H|========================================================|\r\n")
    io.write("\x1b[5;11H|                                                        |\r\n")
    io.write("\x1b[6;11H|              INDEX DES PROGRAMMES DISPONIBLES          |\r\n")
    io.write("\x1b[7;11H|                                                        |\r\n")
    io.write("\x1b[8;11H==========================================================\r\n")
    
    io.write("\x1b[21;11H==========================================================\r\n")
    io.write("\x1b[23;14H  ZQSD / FLECHES : NAVIGUER  |  ENVOI : EXECUTER  \r\n")
    io.flush()
end

local function draw_full_list()
    for i=10, 20 do io.write("\x1b["..i..";1H\x1b[K") end
    for i, game in ipairs(games) do
        local line_y = 10 + i
        if i == cursor then
            io.write("\x1b[" .. line_y .. ";25H\x1b[7m > EXECUTER : " .. game.display .. " \x1b[0m")
        else
            io.write("\x1b[" .. line_y .. ";25H   MODULE   : " .. game.display .. "   ")
        end
    end
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_game = games[old_index]
    if old_game then io.write("\x1b[" .. (10 + old_index) .. ";1H\x1b[K\x1b[" .. (10 + old_index) .. ";25H   MODULE   : " .. old_game.display .. "   ") end
    local new_game = games[new_index]
    if new_game then io.write("\x1b[" .. (10 + new_index) .. ";1H\x1b[K\x1b[" .. (10 + new_index) .. ";25H\x1b[7m > EXECUTER : " .. new_game.display .. " \x1b[0m") end
    io.flush()
end

draw_static_menu()
draw_full_list()

while true do
    local key = minitel.get_key()
    local old_cursor = cursor
    
    if key == "r" or key == "R" then
        games = scan_games()
        cursor = 1
        draw_full_list()
    elseif key == "z" or key == "Z" or key == "UP" then
        cursor = cursor - 1
        if cursor < 1 then cursor = #games end
        update_cursor(old_cursor, cursor)
    elseif key == "s" or key == "S" or key == "DOWN" then
        cursor = cursor + 1
        if cursor > #games then cursor = 1 end
        update_cursor(old_cursor, cursor)
    elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
        minitel.play_sound("hit")
        local selected = games[cursor]
        if selected.filename then
            minitel.cleanup()
            os.execute("lua5.3 " .. selected.filename)
            
            minitel.init()
            games = scan_games()
            if cursor > #games then cursor = 1 end
            draw_static_menu()
            draw_full_list()
        end
    elseif key == "RETOUR" or key == "ESC" then
        break -- Quitte le launcher et redonne la main à master.lua
    end
    minitel.sleep(0.02)
end

minitel.cleanup()