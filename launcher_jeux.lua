local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION DU LANCEUR (MODIFIER CES 3 LIGNES POUR UN NOUVEAU MENU)
-- =====================================================================
local CONFIG = {
    DOSSIER = "jeux/",
    TITRE = "MODULE DE DIVERTISSEMENT",
    MSG_VIDE = "AUCUN JEU DETECTE DANS /jeux"
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
                table.insert(item_list, {
                    filepath = file,
                    display = string.upper(name)
                })
            end
        end
        f:close()
    end

    if #item_list == 0 then
        table.insert(item_list, {
            filepath = nil,
            display = CONFIG.MSG_VIDE
        })
    end
    return item_list
end

local items = scan_directory()
local cursor = 1
local offset = 0
local max_visible = 12
local start_y = 8

-- =====================================================================
-- AFFICHAGE STATIQUE (HEADER ET FOOTER FACON MASTER.LUA)
-- =====================================================================
local function draw_static_menu()
    io.write("\x1b[2J\x1b[H")
    minitel.sleep(0.08)
    
    io.write("\x1b[1;1H\x1b[7m                                                                                \x1b[0m\r\n")
    io.write("\x1b[2;1H\x1b[7m      * * *   P O R T A I L   S Y S T E M E   :   M A G I S   C L U B   * * *   \x1b[0m\r\n")
    io.write("\x1b[3;1H\x1b[7m                                                                                \x1b[0m\r\n")
    
    io.write("\x1b[5;4H\x1b[1m[ SELECTION DU MODULE : " .. string.upper(CONFIG.TITRE) .. " ]\x1b[0m\r\n")
    
    io.write("\x1b[23;1H\x1b[7m                                                                                \x1b[0m\r\n")
    io.write("\x1b[24;1H\x1b[7m  FLECHES: NAVIGUER  |  ENVOI: EXECUTER  |  [RETOUR] MENU PRINCIPAL             \x1b[0m")
    io.flush()
end

-- =====================================================================
-- GESTION DE LA LISTE ET DU DEFILEMENT (SCROLL)
-- =====================================================================
local function draw_full_list()
    -- On nettoie la zone de la liste
    for i = 1, max_visible do
        io.write("\x1b[" .. (start_y + i - 1) .. ";1H\x1b[K")
    end
    
    -- On dessine les elements visibles
    for i = 1, max_visible do
        local idx = offset + i
        local item = items[idx]
        if item then
            local line_y = start_y + i - 1
            if idx == cursor then
                io.write("\x1b[" .. line_y .. ";8H\x1b[7m > " .. item.display .. " \x1b[0m")
            else
                io.write("\x1b[" .. line_y .. ";8H   " .. item.display .. "   ")
            end
        end
    end
    
    -- Indicateur de defilement si la liste est longue
    io.write("\x1b[21;1H\x1b[K")
    if #items > max_visible then
        local progress = math.floor(((offset + max_visible) / math.max(1, #items)) * 100)
        if progress > 100 then progress = 100 end
        io.write(string.format("\x1b[21;64H\x1b[1m DEFILEMENT : %02d%% \x1b[0m", progress))
    end
    
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_y = start_y + (old_index - offset) - 1
    local new_y = start_y + (new_index - offset) - 1
    
    local old_item = items[old_index]
    if old_item and old_y >= start_y and old_y < start_y + max_visible then
        io.write("\x1b[" .. old_y .. ";1H\x1b[K\x1b[" .. old_y .. ";8H   " .. old_item.display .. "   ")
    end
    
    local new_item = items[new_index]
    if new_item and new_y >= start_y and new_y < start_y + max_visible then
        io.write("\x1b[" .. new_y .. ";1H\x1b[K\x1b[" .. new_y .. ";8H\x1b[7m > " .. new_item.display .. " \x1b[0m")
    end
    io.flush()
end

-- =====================================================================
-- INITIALISATION ET BOUCLE PRINCIPALE
-- =====================================================================
draw_static_menu()
draw_full_list()

while true do
    local key = minitel.get_key()
    local old_cursor = cursor

    if key == "r" or key == "R" then
        items = scan_directory()
        cursor = 1
        offset = 0
        draw_full_list()
        
    elseif key == "z" or key == "Z" or key == "UP" then
        if cursor > 1 then
            cursor = cursor - 1
            if cursor <= offset then
                offset = cursor - 1
                draw_full_list()
            else
                update_cursor(old_cursor, cursor)
            end
        else
            -- Boucle vers le bas
            cursor = #items
            offset = math.max(0, #items - max_visible)
            draw_full_list()
        end
        
    elseif key == "s" or key == "S" or key == "DOWN" then
        if cursor < #items then
            cursor = cursor + 1
            if cursor > offset + max_visible then
                offset = cursor - max_visible
                draw_full_list()
            else
                update_cursor(old_cursor, cursor)
            end
        else
            -- Boucle vers le haut
            cursor = 1
            offset = 0
            draw_full_list()
        end
        
    elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
        minitel.play_sound("hit")
        local selected = items[cursor]
        if selected.filepath then
            minitel.cleanup()
            os.execute("lua5.3 " .. selected.filepath)
            minitel.init()
            
            -- Re-scan et re-dessine en cas d'ajout de fichiers
            items = scan_directory()
            if cursor > #items then 
                cursor = 1
                offset = 0
            end
            draw_static_menu()
            draw_full_list()
        end
        
    elseif key == "RETOUR" or key == "ESC" then
        break
    end
    
    minitel.sleep(0.02)
end

minitel.cleanup()