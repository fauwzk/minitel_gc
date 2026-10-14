-- @TYPE: BUREAUTIQUE / CODE
-- @DESC: Editeur de texte plein ecran avec explorateur et boites de dialogue systeme.

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p utils/prog_basic 2>/dev/null")

-- =====================================================================
-- VARIABLES D'ETAT
-- =====================================================================
local lines = {""}
local cx, cy = 1, 1
local offset_y = 0
local filename = ""
local is_modified = false
local running = true

-- =====================================================================
-- MENU PRINCIPAL DE L'EDITEUR (AVEC DIALOGUES SDK)
-- =====================================================================
local function draw_main_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 MAGIS EDIT \x1b[0m                                             \x1b[1m EDITEUR TEXTE \x1b[0m")
    io.write("\x1b[2;1H================================================================================")
    
    minitel.draw_window(22, 5, 38, 14, "MENU FICHIER")
    io.write("\x1b[7;26H\x1b[7m [1] \x1b[0m REPRENDRE L'EDITION")
    io.write("\x1b[9;26H\x1b[7m [2] \x1b[0m NOUVEAU FICHIER")
    io.write("\x1b[11;26H\x1b[7m [3] \x1b[0m OUVRIR UN FICHIER...")
    io.write("\x1b[13;26H\x1b[7m [4] \x1b[0m SAUVEGARDER SOUS...")
    io.write("\x1b[16;26H\x1b[7m [9] \x1b[0m QUITTER MAGIS EDIT")
    
    io.write("\x1b[24;1H\x1b[7m  TAPEZ LE NUMERO DE L'OPTION SOUHAITEE OU [RETOUR] POUR REVENIR AU TEXTE      \x1b[0m")
    io.flush()
end

local function handle_menu()
    draw_main_menu()
    while true do
        local k = minitel.get_key()
        
        if k == "1" or k == "RETOUR" or k == "ESC" then
            return
            
        elseif k == "2" then
            if not is_modified or minitel.confirm_box("NOUVEAU FICHIER", "Le document actuel a ete modifie. Voulez-vous vraiment l'ecraser ?") then
                lines = {""}
                cx, cy, offset_y = 1, 1, 0
                filename = ""
                is_modified = false
                return
            end
            draw_main_menu()
            
        elseif k == "3" then
            if is_modified and not minitel.confirm_box("OUVRIR", "Abandonner les modifications en cours et ouvrir un autre fichier ?") then
                draw_main_menu()
            else
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
                    else
                        minitel.msg_box("ERREUR LECTURE", "Impossible de lire le fichier selectionne.", "lose")
                    end
                end
                draw_main_menu()
            end
            
        elseif k == "4" then
            local target = minitel.file_browser("SAVE", "utils/prog_basic/")
            if target then
                local f = io.open(target, "w")
                if f then
                    for i = 1, #lines do f:write(lines[i] .. "\n") end
                    f:close()
                    filename = string.match(target, "([^/]+)$") or target
                    is_modified = false
                    minitel.msg_box("SAUVEGARDE REUSSIE", "Fichier enregistre sous : " .. filename, "win")
                    return
                else
                    minitel.msg_box("ERREUR ECRITURE", "Impossible d'ecrire sur le disque.", "lose")
                end
            end
            draw_main_menu()
            
        elseif k == "9" then
            if not is_modified or minitel.confirm_box("QUITTER", "Modifications non sauvegardees ! Quitter Magis Edit quand meme ?") then
                running = false
                return
            end
            draw_main_menu()
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- FONCTIONS D'AFFICHAGE DE L'EDITEUR (DELTA-DRAWING)
-- =====================================================================
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

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
io.write("\x1b[2J\x1b[H\x1b[?25h") -- On affiche le curseur materiel pour l'edition de texte
draw_text()
clamp_cursor()
update_status()

while running do
    local k = minitel.get_key()
    if k then
        if k == "UP" then cy = cy - 1
        elseif k == "DOWN" then cy = cy + 1
        elseif k == "LEFT" then
            cx = cx - 1
            if cx < 1 and cy > 1 then cy = cy - 1; cx = #lines[cy] + 1 end
        elseif k == "RIGHT" then
            cx = cx + 1
            if cx > #lines[cy] + 1 and cy < #lines then cy = cy + 1; cx = 1 end
        elseif k == "HOME" then cx = 1
        elseif k == "END" then cx = #lines[cy] + 1
        elseif k == "RETOUR" or k == "ESC" then
            io.write("\x1b[?25l") -- Masque le curseur dans le menu
            handle_menu()
            if running then
                io.write("\x1b[r\x1b[2J\x1b[H\x1b[?25h")
                draw_text()
            end
        elseif k == "REPETITION" then
            io.write("\x1b[r\x1b[2J\x1b[H\x1b[?25h")
            draw_text()
        elseif k == "ANNULATION" then
            -- Vide toute la ligne courante d'un coup (Standard Minitel)
            lines[cy] = ""
            cx = 1
            is_modified = true
            draw_line(cy)
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local left = string.sub(lines[cy], 1, cx - 1)
            local right = string.sub(lines[cy], cx)
            lines[cy] = left
            table.insert(lines, cy + 1, right)
            cy = cy + 1; cx = 1; is_modified = true; draw_text()
        elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
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

minitel.cleanup()