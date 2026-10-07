local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic 2>/dev/null")

-- =====================================================================
-- VARIABLES D'ETAT
-- =====================================================================
local lines = {""}
local cx, cy = 1, 1
local offset_y = 0
local filename = ""
local current_dir = "utils/"
local is_modified = false
local running = true

-- =====================================================================
-- EXPLORATEUR NATIF LINUX (INDESCTRUCTIBLE)
-- =====================================================================
local function scan_dir(path)
    local items = {}
    local dirs = {}
    local files = {}
    
    if path ~= "./" and path ~= "" and path ~= "/" then
        table.insert(items, { name = ".. (Dossier Parent)", is_dir = true, real_name = ".." })
    end
    
    -- Le \ls force la commande native sans les alias de couleur
    local cmd = "\\ls -1p '" .. path .. "' 2>/dev/null"
    local f = io.popen(cmd)
    
    if f then
        for line in f:lines() do
            if string.sub(line, -1) == "/" then
                table.insert(dirs, string.sub(line, 1, -2))
            else
                table.insert(files, line)
            end
        end
        f:close()
    end
    
    -- On trie : d'abord les dossiers, puis les fichiers
    for _, d in ipairs(dirs) do
        table.insert(items, { name = "[" .. d .. "]", is_dir = true, real_name = d })
    end
    for _, file in ipairs(files) do
        table.insert(items, { name = file, is_dir = false, real_name = file })
    end
    
    if #items == 0 then 
        table.insert(items, {name = "(Dossier Vide)", is_dir = false, real_name = ""}) 
    end
    
    return items
end

-- =====================================================================
-- L'INTERFACE "COMMANDER"
-- =====================================================================
local function file_browser(mode)
    local items = scan_dir(current_dir)
    local cursor = 1
    local list_offset = 0
    local max_visible = 12
    local input_buffer = ""
    
    local function draw_browser()
        io.write("\x1b[4;15H\x1b[1m+--------------------------------------------------+\x1b[0m\r\n")
        for i=5, 20 do io.write("\x1b["..i..";15H\x1b[1m|                                                  |\x1b[0m\r\n") end
        io.write("\x1b[21;15H\x1b[1m+--------------------------------------------------+\x1b[0m\r\n")
        
        local title = mode == "OPEN" and " OUVRIR UN FICHIER " or " SAUVEGARDER LE FICHIER "
        local pad = string.rep(" ", math.floor((50 - #title) / 2))
        io.write("\x1b[4;16H\x1b[7m" .. pad .. title .. pad .. "\x1b[0m")
        io.write("\x1b[5;17H CHEMIN : \x1b[1m" .. string.sub(current_dir, 1, 38) .. "\x1b[0m\r\n")
        io.write("\x1b[6;16H--------------------------------------------------\r\n")
        
        for i = 1, max_visible do
            local idx = list_offset + i
            local item = items[idx]
            local y = 6 + i
            io.write("\x1b["..y..";16H\x1b[K\x1b["..y..";66H\x1b[1m|\x1b[0m")
            
            if item then
                local display_name = string.sub(item.name, 1, 45)
                local space_count = math.max(0, 45 - #display_name)
                
                if idx == cursor then
                    io.write("\x1b["..y..";18H\x1b[7m > " .. display_name .. string.rep(" ", space_count) .. "\x1b[0m")
                else
                    io.write("\x1b["..y..";18H   " .. display_name)
                end
            end
        end
        
        if mode == "SAVE" then
            io.write("\x1b[19;16H--------------------------------------------------\r\n")
            local safe_input = string.sub(input_buffer, 1, 38)
            local space_count = math.max(0, 38 - #safe_input)
            io.write("\x1b[20;17H NOM : \x1b[7m " .. safe_input .. string.rep(" ", space_count) .. "\x1b[0m")
        else
            io.write("\x1b[20;17H \x1b[1m [ENVOI] SELECTIONNER   |   [RETOUR] ANNULER \x1b[0m")
        end
        io.flush()
    end
    
    draw_browser()
    
    while true do
        local k = minitel.get_key()
        
        if k == "RETOUR" or k == "ESC" then
            return nil
            
        elseif mode == "SAVE" and (string.match(k or "", "^[%w%s%p_%.%-]$") and #k == 1) then
            if #input_buffer < 35 then
                input_buffer = input_buffer .. k
                draw_browser()
            end
        elseif mode == "SAVE" and (k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f") then
            if #input_buffer > 0 then
                input_buffer = string.sub(input_buffer, 1, -2)
                draw_browser()
            end
            
        elseif k == "UP" or k == "Z" or k == "z" then
            if cursor > 1 then
                cursor = cursor - 1
                if cursor <= list_offset then list_offset = cursor - 1 end
                if mode == "SAVE" and not items[cursor].is_dir and items[cursor].real_name ~= "" then
                    input_buffer = items[cursor].real_name
                end
                draw_browser()
            end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if cursor < #items then
                cursor = cursor + 1
                if cursor > list_offset + max_visible then list_offset = cursor - max_visible end
                if mode == "SAVE" and not items[cursor].is_dir and items[cursor].real_name ~= "" then
                    input_buffer = items[cursor].real_name
                end
                draw_browser()
            end
            
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local sel = items[cursor]
            
            if mode == "OPEN" then
                if sel.is_dir then
                    if sel.real_name == ".." then
                        current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else
                        current_dir = current_dir .. sel.real_name .. "/"
                    end
                    items = scan_dir(current_dir)
                    cursor = 1
                    list_offset = 0
                    draw_browser()
                elseif sel.real_name ~= "" then
                    return current_dir .. sel.real_name
                end
                
            elseif mode == "SAVE" then
                if sel and sel.is_dir and input_buffer == "" then
                    if sel.real_name == ".." then
                        current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else
                        current_dir = current_dir .. sel.real_name .. "/"
                    end
                    items = scan_dir(current_dir)
                    cursor = 1
                    list_offset = 0
                    draw_browser()
                elseif input_buffer ~= "" then
                    return current_dir .. input_buffer
                end
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MENU PRINCIPAL DE L'EDITEUR
-- =====================================================================
local function draw_main_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    
    io.write("\x1b[1;1H\x1b[1m 3615 MAGIS EDIT \x1b[0m                                             \x1b[1m EDITEUR TEXTE \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    
    io.write("\x1b[6;30H\x1b[7m [1] \x1b[0m REPRENDRE L'EDITION\r\n\r\n")
    io.write("\x1b[8;30H\x1b[7m [2] \x1b[0m NOUVEAU FICHIER\r\n\r\n")
    io.write("\x1b[10;30H\x1b[7m [3] \x1b[0m OUVRIR...\r\n\r\n")
    io.write("\x1b[12;30H\x1b[7m [4] \x1b[0m SAUVEGARDER SOUS...\r\n\r\n")
    io.write("\x1b[14;30H\x1b[7m [9] \x1b[0m QUITTER\r\n")
    
    io.write("\x1b[24;1H\x1b[7m  TAPEZ LE NUMERO DE L'OPTION SOUHAITEE                                         \x1b[0m")
    io.flush()
end

local function handle_menu()
    draw_main_menu()
    
    while true do
        local k = minitel.get_key()
        
        if k == "1" or k == "RETOUR" or k == "ESC" then
            return
            
        elseif k == "2" then
            if is_modified then
                io.write("\x1b[24;1H\x1b[7m FICHIER MODIFIE. VOULEZ-VOUS VRAIMENT L'ECRASER ? [O/N]                        \x1b[0m")
                io.flush()
                local rep = ""
                while rep ~= "O" and rep ~= "N" do
                    local rk = minitel.get_key()
                    if rk then rep = string.upper(rk) end
                    minitel.sleep(0.05)
                end
                if rep == "N" then draw_main_menu(); goto continue end
            end
            lines = {""}
            cx, cy, offset_y = 1, 1, 0
            filename = ""
            is_modified = false
            return
            
        elseif k == "3" then
            local target = file_browser("OPEN")
            if target then
                local f = io.open(target, "r")
                if f then
                    lines = {}
                    for l in f:lines() do table.insert(lines, l) end
                    f:close()
                    if #lines == 0 then lines = {""} end
                    filename = string.match(target, "([^/]+)$") or target
                    cx, cy, offset_y = 1, 1, 0
                    is_modified = false
                    return
                end
            end
            draw_main_menu()
            
        elseif k == "4" then
            local target = file_browser("SAVE")
            if target then
                local f = io.open(target, "w")
                if f then
                    for i = 1, #lines do f:write(lines[i] .. "\n") end
                    f:close()
                    filename = string.match(target, "([^/]+)$") or target
                    is_modified = false
                    io.write("\x1b[24;1H\x1b[7m FICHIER SAUVEGARDE AVEC SUCCES. APPUYEZ SUR [ENVOI].                           \x1b[0m")
                    io.flush()
                    while minitel.get_key() ~= "ENVOI" and minitel.get_key() ~= "\r" do minitel.sleep(0.05) end
                    return
                end
            end
            draw_main_menu()
            
        elseif k == "9" then
            if is_modified then
                io.write("\x1b[24;1H\x1b[7m FICHIER NON SAUVEGARDE. QUITTER QUAND MEME ? [O/N]                             \x1b[0m")
                io.flush()
                local rep = ""
                while rep ~= "O" and rep ~= "N" do
                    local rk = minitel.get_key()
                    if rk then rep = string.upper(rk) end
                    minitel.sleep(0.05)
                end
                if rep == "O" then running = false; return end
                draw_main_menu()
            else
                running = false
                return
            end
        end
        ::continue::
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- FONCTIONS D'AFFICHAGE DE L'EDITEUR
-- =====================================================================
local function update_status()
    io.write("\x1b7") 
    io.write("\x1b[1;1H\x1b[7m MAGIS EDIT                                     [RETOUR] MENU FICHIER \x1b[K\x1b[0m")
    
    local fname = filename == "" and "SANS NOM" or filename
    local mod = is_modified and "*" or ""
    local status = string.format(" FICHIER : %s%s | LIGNE : %03d/%03d | COL : %02d ", fname, mod, cy, #lines, cx)
    
    io.write("\x1b[2;1H\x1b[7m" .. string.sub(status, 1, 79) .. "\x1b[K\x1b[0m")
    io.write("\x1b8")
    io.flush()
end

local function draw_line(y)
    if y > offset_y and y <= offset_y + 22 then
        io.write("\x1b[" .. (y - offset_y + 2) .. ";1H\x1b[K")
        io.write(string.sub(lines[y] or "", 1, 79))
    end
end

local function draw_text()
    io.write("\x1b[3;24r") 
    for i = 1, 22 do
        local y = offset_y + i
        io.write("\x1b[" .. (i + 2) .. ";1H\x1b[K")
        if lines[y] then
            io.write(string.sub(lines[y], 1, 79))
        end
    end
    io.flush()
end

local function clamp_cursor()
    if cy < 1 then cy = 1 end
    if cy > #lines then cy = #lines end
    
    local len = #lines[cy]
    if cx < 1 then cx = 1 end
    if cx > len + 1 then cx = len + 1 end
    
    local old_offset = offset_y
    if cy <= offset_y then offset_y = cy - 1 end
    if cy > offset_y + 22 then offset_y = cy - 22 end
    
    if old_offset ~= offset_y then draw_text() end
    
    io.write("\x1b[" .. (cy - offset_y + 2) .. ";" .. cx .. "H")
    io.flush()
end

-- =====================================================================
-- BOUCLE PRINCIPALE DE L'EDITEUR
-- =====================================================================
io.write("\x1b[2J\x1b[H")
draw_text()
clamp_cursor()
update_status()

while running do
    local k = minitel.get_key()
    
    if k then
        if k == "UP" or k == "Z" or k == "z" then
            cy = cy - 1
        elseif k == "DOWN" or k == "S" or k == "s" then
            cy = cy + 1
        elseif k == "LEFT" or k == "Q" or k == "q" then
            cx = cx - 1
            if cx < 1 and cy > 1 then
                cy = cy - 1
                cx = #lines[cy] + 1
            end
        elseif k == "RIGHT" or k == "D" or k == "d" then
            cx = cx + 1
            if cx > #lines[cy] + 1 and cy < #lines then
                cy = cy + 1
                cx = 1
            end
        elseif k == "RETOUR" or k == "ESC" then
            handle_menu()
            if running then
                io.write("\x1b[r\x1b[2J\x1b[H")
                draw_text()
            end
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local left = string.sub(lines[cy], 1, cx - 1)
            local right = string.sub(lines[cy], cx)
            lines[cy] = left
            table.insert(lines, cy + 1, right)
            cy = cy + 1
            cx = 1
            is_modified = true
            draw_text()
        elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
            if cx > 1 then
                local left = string.sub(lines[cy], 1, cx - 2)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. right
                cx = cx - 1
                is_modified = true
                draw_line(cy)
            elseif cy > 1 then
                local prev_len = #lines[cy - 1]
                lines[cy - 1] = lines[cy - 1] .. lines[cy]
                table.remove(lines, cy)
                cy = cy - 1
                cx = prev_len + 1
                is_modified = true
                draw_text()
            end
        elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
            if #lines[cy] < 79 then
                local left = string.sub(lines[cy], 1, cx - 1)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. k .. right
                cx = cx + 1
                is_modified = true
                draw_line(cy)
            end
        end
        
        if running then
            clamp_cursor()
            update_status()
        end
    end
    
    minitel.sleep(0.01)
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()