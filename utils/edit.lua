local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic")

-- =====================================================================
-- VARIABLES D'ETAT DE L'EDITEUR
-- =====================================================================
local lines = {""}
local cx, cy = 1, 1
local offset_y = 0
local filename = ""
local is_modified = false
local running = true

-- =====================================================================
-- FONCTIONS D'AFFICHAGE
-- =====================================================================
local function update_status()
    io.write("\x1b7") -- Sauvegarde du curseur
    io.write("\x1b[1;1H\x1b[7m MAGIS EDIT V1.0                [RETOUR] MENU FICHIER \x1b[K\x1b[0m")
    
    local fname = filename == "" and "SANS NOM" or filename
    local mod = is_modified and "*" or ""
    local status = string.format(" FICHIER : %s%s | LIGNE : %03d/%03d | COL : %02d ", fname, mod, cy, #lines, cx)
    
    io.write("\x1b[2;1H\x1b[7m" .. string.sub(status, 1, 79) .. "\x1b[K\x1b[0m")
    io.write("\x1b8") -- Restauration du curseur
    io.flush()
end

local function draw_line(y)
    if y > offset_y and y <= offset_y + 22 then
        io.write("\x1b[" .. (y - offset_y + 2) .. ";1H\x1b[K")
        io.write(string.sub(lines[y] or "", 1, 79))
    end
end

local function draw_text()
    io.write("\x1b[3;24r") -- Restreint la zone de défilement
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
    
    -- Gestion du défilement vertical
    local old_offset = offset_y
    if cy <= offset_y then offset_y = cy - 1 end
    if cy > offset_y + 22 then offset_y = cy - 22 end
    
    if old_offset ~= offset_y then draw_text() end
    
    -- Positionnement physique du curseur VT100
    io.write("\x1b[" .. (cy - offset_y + 2) .. ";" .. cx .. "H")
    io.flush()
end

-- =====================================================================
-- INVITE DE COMMANDE POUR LE MENU
-- =====================================================================
local function prompt_input(prompt_text)
    io.write(prompt_text)
    io.flush()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then return str
            elseif k == "RETOUR" or k == "ESC" then return "ABORT"
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D"); io.flush()
                end
            elseif string.match(k, "^[%w%s%p_%.]$") and #k == 1 then
                str = str .. k
                io.write(k); io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- MENU FICHIER
-- =====================================================================
local function show_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[7m MAGIS EDIT : MENU FICHIER \x1b[K\x1b[0m\r\n\r\n")
    io.write(" 1. REPRENDRE L'EDITION\r\n")
    io.write(" 2. NOUVEAU FICHIER\r\n")
    io.write(" 3. SAUVEGARDER\r\n")
    io.write(" 4. OUVRIR UN FICHIER\r\n")
    io.write(" 5. LISTER LE DOSSIER\r\n")
    io.write(" 9. QUITTER MAGIS EDIT\r\n\r\n")
    
    local choice = prompt_input(" CHOIX > ")
    
    if choice == "2" then
        lines = {""}
        cx, cy, offset_y = 1, 1, 0
        filename = ""
        is_modified = false
    elseif choice == "3" then
        local save_name = filename
        if save_name == "" then
            io.write("\r\n\r\n NOM DU FICHIER (ex: monjeu.bas) : ")
            local rep = prompt_input("")
            if rep ~= "ABORT" and rep ~= "" then save_name = rep end
        end
        
        if save_name ~= "" then
            local f = io.open("utils/prog_basic/" .. save_name, "w")
            if f then
                for i = 1, #lines do f:write(lines[i] .. "\n") end
                f:close()
                filename = save_name
                is_modified = false
                io.write("\r\n\r\n \x1b[7m FICHIER SAUVEGARDE ! \x1b[0m")
                minitel.play_sound("hit")
                minitel.sleep(1)
            end
        end
    elseif choice == "4" then
        io.write("\r\n\r\n NOM DU FICHIER A OUVRIR : ")
        local open_name = prompt_input("")
        if open_name ~= "ABORT" and open_name ~= "" then
            local f = io.open("utils/prog_basic/" .. open_name, "r")
            if f then
                lines = {}
                for l in f:lines() do table.insert(lines, l) end
                f:close()
                if #lines == 0 then lines = {""} end
                filename = open_name
                cx, cy, offset_y = 1, 1, 0
                is_modified = false
            else
                io.write("\r\n\r\n \x1b[7m ERREUR : FICHIER INTROUVABLE \x1b[0m")
                minitel.play_sound("hit")
                minitel.sleep(1.5)
            end
        end
    elseif choice == "5" then
        io.write("\r\n\x1b[1m --- FICHIERS PRESENTS --- \x1b[0m\r\n")
        local f = io.popen("ls -1 utils/prog_basic/ 2>/dev/null")
        if f then
            for file in f:lines() do io.write(" " .. file .. "\r\n") end
            f:close()
        end
        io.write("\r\n APPUYEZ SUR [ENVOI] POUR CONTINUER...")
        prompt_input("")
    elseif choice == "9" then
        if is_modified then
            io.write("\r\n\r\n \x1b[7m ATTENTION: FICHIER NON SAUVEGARDE \x1b[0m")
            io.write("\r\n QUITTER QUAND MEME ? (O/N) : ")
            local conf = prompt_input("")
            if conf == "O" or conf == "o" then running = false end
        else
            running = false
        end
    end
    
    -- Redessine l'éditeur au retour
    io.write("\x1b[2J\x1b[H")
    draw_text()
end

-- =====================================================================
-- BOUCLE PRINCIPALE DE L'EDITEUR
-- =====================================================================
io.write("\x1b[2J\x1b[H")
draw_text()

while running do
    update_status()
    clamp_cursor()
    
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
            show_menu()
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local left = string.sub(lines[cy], 1, cx - 1)
            local right = string.sub(lines[cy], cx)
            lines[cy] = left
            table.insert(lines, cy + 1, right)
            cy = cy + 1
            cx = 1
            is_modified = true
            draw_text() -- Redessine le bas de l'écran car tout descend
        elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
            if cx > 1 then
                local left = string.sub(lines[cy], 1, cx - 2)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. right
                cx = cx - 1
                is_modified = true
                draw_line(cy) -- Redessine juste la ligne courante (ultra-rapide)
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
            -- On bloque l'écriture si la ligne dépasse 79 caractères pour protéger le terminal
            if #lines[cy] < 79 then
                local left = string.sub(lines[cy], 1, cx - 1)
                local right = string.sub(lines[cy], cx)
                lines[cy] = left .. k .. right
                cx = cx + 1
                is_modified = true
                draw_line(cy)
            end
        end
    end
    minitel.sleep(0.01)
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()