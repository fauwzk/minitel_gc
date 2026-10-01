local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION DU LANCEUR (MODIFIER CES 3 LIGNES POUR UN NOUVEAU MENU)
-- =====================================================================
local CONFIG = {
    DOSSIER = "utils/",
    TITRE = "MODULE UTILITAIRE",
    MSG_VIDE = "AUCUN OUTIL DETECTE DANS /utils"
}
-- =====================================================================

local function scan_directory()
    local item_list = {}
    local cmd = "ls -1 " .. CONFIG.DOSSIER .. "*.lua 2>/dev/null"
    local f = io.popen(cmd)
    
    if f then
        for file in f:lines() do
            local name = string.match(file, CONFIG.DOSSIER .. "(.-)%.lua$")
            if name then
                table.insert(item_list, { filepath = file, display = string.upper(name) })
            end
        end
        f:close()
    end
    
    if #item_list == 0 then table.insert(item_list, { filepath = nil, display = CONFIG.MSG_VIDE }) end
    return item_list
end

local items = scan_directory()
local cursor = 1

local function draw_static_menu()
    io.write("\x1b[2J\x1b[H") 
    io.flush()
    minitel.sleep(0.08)
    
    local title_len = string.len(CONFIG.TITRE) + 2
    local pad_left = math.floor((56 - title_len) / 2)
    local pad_right = 56 - title_len - pad_left
    local formatted_title = string.rep(" ", pad_left) .. "\x1b[1m " .. CONFIG.TITRE .. " \x1b[0m" .. string.rep(" ", pad_right)
    
    io.write("\x1b[2;11H==========================================================\r\n")
    io.write("\x1b[3;11H|" .. formatted_title .. "|\r\n")
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
    for i, item in ipairs(items) do
        local line_y = 10 + i
        if i == cursor then
            io.write("\x1b[" .. line_y .. ";25H\x1b[7m > EXECUTER : " .. item.display .. " \x1b[0m")
        else
            io.write("\x1b[" .. line_y .. ";25H   MODULE   : " .. item.display .. "   ")
        end
    end
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_item = items[old_index]
    if old_item then io.write("\x1b[" .. (10 + old_index) .. ";1H\x1b[K\x1b[" .. (10 + old_index) .. ";25H   MODULE   : " .. old_item.display .. "   ") end
    local new_item = items[new_index]
    if new_item then io.write("\x1b[" .. (10 + new_index) .. ";1H\x1b[K\x1b[" .. (10 + new_index) .. ";25H\x1b[7m > EXECUTER : " .. new_item.display .. " \x1b[0m") end
    io.flush()
end

draw_static_menu()
draw_full_list()

while true do
    local key = minitel.get_key()
    local old_cursor = cursor
    
    if key == "r" or key == "R" then
        items = scan_directory()
        cursor = 1
        draw_full_list()
    elseif key == "z" or key == "Z" or key == "UP" then
        cursor = cursor - 1
        if cursor < 1 then cursor = #items end
        update_cursor(old_cursor, cursor)
    elseif key == "s" or key == "S" or key == "DOWN" then
        cursor = cursor + 1
        if cursor > #items then cursor = 1 end
        update_cursor(old_cursor, cursor)
    elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
        minitel.play_sound("hit")
        local selected = items[cursor]
        if selected.filepath then
            minitel.cleanup()
            os.execute("lua5.3 " .. selected.filepath)
            minitel.init()
            items = scan_directory()
            if cursor > #items then cursor = 1 end
            draw_static_menu()
            draw_full_list()
        end
    elseif key == "RETOUR" or key == "ESC" then
        break
    end
    minitel.sleep(0.02)
end

minitel.cleanup()