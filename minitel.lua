-- Fichier : minitel.lua
-- Moteur de base pour Minitel Magis Club (9600 bauds 8N1)

local M = {}

function M.init()
    os.execute("stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb raw -echo -icanon min 0 time 0")
    io.write("\x1b[?25l") -- Masque le curseur
    io.flush()
end

function M.cleanup()
    io.write("\x1b[?25h\x1b[2J\x1b[H") -- Réaffiche le curseur et efface l'écran
    io.flush()
    os.execute("stty -F /dev/ttyUSB0 sane")
end

function M.sleep(seconds)
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do end
end

function M.play_sound(effect)
    -- L'exécution avec " >/dev/null 2>&1 &" permet de lancer le son en tâche de fond 
    -- sans bloquer l'exécution de Lua et sans salir l'affichage du Minitel.
    
    if not effect or effect == "blip" or effect == "hit" then
        -- Petit bip court "arcade" (Onde carrée à 880 Hz pendant 50ms)
        os.execute("play -q -n synth 0.05 square 880 >/dev/null 2>&1 &")
        
    elseif effect == "win" or effect == "pickup" then
        -- Son de ramassage/victoire (Onde carrée montante de 440 Hz à 1200 Hz pendant 150ms)
        os.execute("play -q -n synth 0.15 square 440-1200 >/dev/null 2>&1 &")
        
    elseif effect == "lose" or effect == "damage" then
        -- Son grave d'erreur/dégât (Onde en dent de scie descendante de 300 Hz à 100 Hz pendant 300ms)
        os.execute("play -q -n synth 0.3 sawtooth 300-100 >/dev/null 2>&1 &")
        
    end
end

function M.get_key()
    local c = io.read(1)
    if not c then return nil end
    
    local function read_next()
        -- Boucle matérielle pour éviter de rater la fin des séquences à 9600 bauds
        for i = 1, 50000 do 
            local n = io.read(1)
            if n then return n end
        end
        return nil
    end

    if c == "\x1b" then
        local seq1 = read_next()
        if not seq1 then return "ESC" end
        local seq2 = read_next()
        local full_seq = seq1 .. (seq2 or "")

        -- Flèches
        if full_seq == "[A" then return "UP" end
        if full_seq == "[B" then return "DOWN" end
        if full_seq == "[C" then return "RIGHT" end
        if full_seq == "[D" then return "LEFT" end
        
        -- Touches spéciales Magis Club
        if full_seq == "OR" then return "RETOUR" end
        if full_seq == "On" then return "SUITE" end
        if full_seq == "Ol" then return "CORRECTION" end
        if full_seq == "OQ" then return "ANNULATION" end
        if full_seq == "OM" then return "ENVOI" end

        return "UNKNOWN_ESC"
    end
    return c
end

-- =====================================================================
-- EXPLORATEUR DE FICHIERS SYSTEME (STYLE NORTON COMMANDER)
-- =====================================================================
function M.file_browser(mode, start_dir)
    -- mode: "OPEN" ou "SAVE"
    local current_dir = start_dir or "./"
    if string.sub(current_dir, -1) ~= "/" then current_dir = current_dir .. "/" end

    local function scan_dir(path)
        local items = {}
        local dirs = {}
        local files = {}
        
        if path ~= "./" and path ~= "" and path ~= "/" then
            table.insert(items, { name = ".. (Dossier Parent)", is_dir = true, real_name = ".." })
        end
        
        local cmd = "\\ls -1p '" .. path .. "' 2>/dev/null"
        local f = io.popen(cmd)
        if f then
            for line in f:lines() do
                if string.sub(line, -1) == "/" then table.insert(dirs, string.sub(line, 1, -2))
                else table.insert(files, line) end
            end
            f:close()
        end
        
        for _, d in ipairs(dirs) do table.insert(items, { name = "[" .. d .. "]", is_dir = true, real_name = d }) end
        for _, file in ipairs(files) do table.insert(items, { name = file, is_dir = false, real_name = file }) end
        if #items == 0 then table.insert(items, {name = "(Dossier Vide)", is_dir = false, real_name = ""}) end
        
        return items
    end

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
        local k = M.get_key() -- Utilise la fonction interne
        
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
                    cursor = 1; list_offset = 0; draw_browser()
                elseif sel.real_name ~= "" then
                    return current_dir .. sel.real_name
                end
            elseif mode == "SAVE" then
                if sel and sel.is_dir and input_buffer == "" then
                    if sel.real_name == ".." then current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else current_dir = current_dir .. sel.real_name .. "/" end
                    items = scan_dir(current_dir)
                    cursor = 1; list_offset = 0; draw_browser()
                elseif input_buffer ~= "" then
                    return current_dir .. input_buffer
                end
            end
        end
        M.sleep(0.02)
    end
end

return M