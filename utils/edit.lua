local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic 2>/dev/null")

local lines = {""}
local cx, cy = 1, 1
local offset_y = 0
local filename = ""
local is_modified = false
local running = true

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
                io.write("\x1b[24;1H\x1b[7m FICHIER MODIFIE. L'ECRASER ? [O/N]                                             \x1b[0m")
                io.flush()
                local rep = ""
                while rep ~= "O" and rep ~= "N" do
                    local rk = minitel.get_key()
                    if rk then rep = string.upper(rk) end
                    minitel.sleep(0.05)
                end
                if rep == "N" then draw_main_menu(); goto continue end
            end
            lines = {""}; cx, cy, offset_y = 1, 1, 0; filename = ""; is_modified = false
            return
            
        elseif k == "3" then
            -- APPEL DE L'API SYSTEME MAGIS !
            local target = minitel.file_browser("OPEN", "utils/prog_basic/")
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
            -- APPEL DE L'API SYSTEME MAGIS !
            local target = minitel.file_browser("SAVE", "utils/prog_basic/")
            if target then
                local f = io.open(target, "w")
                if f then
                    for i = 1, #lines do f:write(lines[i] .. "\n") end
                    f:close()
                    filename = string.match(target, "([^/]+)$") or target
                    is_modified = false
                    io.write("\x1b[24;1H\x1b[7m SAUVEGARDE REUSSIE. APPUYEZ SUR [ENVOI].                                       \x1b[0m")
                    io.flush()
                    while minitel.get_key() ~= "ENVOI" and minitel.get_key() ~= "\r" do minitel.sleep(0.05) end
                    return
                end
            end
            draw_main_menu()
            
        elseif k == "9" then
            if is_modified then
                io.write("\x1b[24;1H\x1b[7m FICHIER NON SAUVEGARDE. QUITTER ? [O/N]                                        \x1b[0m")
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
                running = false; return
            end
        end
        ::continue::
        minitel.sleep(0.05)
    end
end

local function update_status()
    io.write("\x1b7") 
    io.write("\x1b[1;1H\x1b[7m MAGIS EDIT                                     [RETOUR] MENU FICHIER \x1b[K\x1b[0m")
    local fname = filename == "" and "SANS NOM" or filename
    local status = string.format(" FICHIER : %s%s | LIGNE : %03d/%03d | COL : %02d ", fname, (is_modified and "*" or ""), cy, #lines, cx)
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
        if lines[y] then io.write(string.sub(lines[y], 1, 79)) end
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

io.write("\x1b[2J\x1b[H")
draw_text()
clamp_cursor()
update_status()

while running do
    local k = minitel.get_key()
    if k then
        if k == "UP" or k == "Z" or k == "z" then cy = cy - 1
        elseif k == "DOWN" or k == "S" or k == "s" then cy = cy + 1
        elseif k == "LEFT" or k == "Q" or k == "q" then
            cx = cx - 1
            if cx < 1 and cy > 1 then cy = cy - 1; cx = #lines[cy] + 1 end
        elseif k == "RIGHT" or k == "D" or k == "d" then
            cx = cx + 1
            if cx > #lines[cy] + 1 and cy < #lines then cy = cy + 1; cx = 1 end
        elseif k == "RETOUR" or k == "ESC" then
            handle_menu()
            if running then io.write("\x1b[r\x1b[2J\x1b[H"); draw_text() end
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local left = string.sub(lines[cy], 1, cx - 1)
            local right = string.sub(lines[cy], cx)
            lines[cy] = left
            table.insert(lines, cy + 1, right)
            cy = cy + 1; cx = 1; is_modified = true; draw_text()
        elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
            if cx > 1 then
                local left = string.sub(lines[cy], 1, cx - 2)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. right
                cx = cx - 1; is_modified = true; draw_line(cy)
            elseif cy > 1 then
                local prev_len = #lines[cy - 1]
                lines[cy - 1] = lines[cy - 1] .. lines[cy]
                table.remove(lines, cy)
                cy = cy - 1; cx = prev_len + 1; is_modified = true; draw_text()
            end
        elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
            if #lines[cy] < 79 then
                local left = string.sub(lines[cy], 1, cx - 1)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. k .. right
                cx = cx + 1; is_modified = true; draw_line(cy)
            end
        end
        if running then clamp_cursor(); update_status() end
    end
    minitel.sleep(0.01)
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()