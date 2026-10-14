-- Fichier : minitel.lua
-- SDK & Moteur Système pour Minitel Magis Club (9600 bauds 8N1)

local M = {}

-- =====================================================================
-- 1. INITIALISATION & MATERIEL
-- =====================================================================
function M.init()
    os.execute("stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb raw -echo -icanon min 0 time 0 2>/dev/null")
    os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
    io.write("\x1b[?25l") -- Masque le curseur matériel
    io.flush()
end

function M.cleanup()
    io.write("\x1b[r\x1b[0m\x1b[?25h\x1b[2J\x1b[H") -- Réinitialise marges, attributs, curseur et écran
    io.flush()
    os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
    os.execute("stty sane 2>/dev/null")
end

function M.sleep(seconds)
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do end
end

function M.play_sound(effect)
    if not effect or effect == "blip" or effect == "hit" then
        os.execute("play -q -n synth 0.05 square 880 >/dev/null 2>&1 &")
    elseif effect == "win" or effect == "pickup" then
        os.execute("play -q -n synth 0.15 square 440-1200 >/dev/null 2>&1 &")
    elseif effect == "lose" or effect == "damage" then
        os.execute("play -q -n synth 0.3 sawtooth 300-100 >/dev/null 2>&1 &")
    end
end

-- =====================================================================
-- 2. GESTION DU CLAVIER (AVEC TOUCHES TELEMATIQUES ETENDUES)
-- =====================================================================
function M.get_key()
    local c = io.read(1)
    if not c then return nil end
    
    local function read_next()
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

        -- Flèches standards
        if full_seq == "[A" then return "UP" end
        if full_seq == "[B" then return "DOWN" end
        if full_seq == "[C" then return "RIGHT" end
        if full_seq == "[D" then return "LEFT" end
        if full_seq == "[H" then return "HOME" end
        if full_seq == "[F" then return "END" end
        
        -- Séquences à 3 caractères (ex: Suppr = \x1b[3~)
        if seq1 == "[" and seq2 and seq2:match("%d") then
            local seq3 = read_next()
            if seq2 == "3" and seq3 == "~" then return "CORRECTION" end
            if seq2 == "5" and seq3 == "~" then return "PAGE_UP" end
            if seq2 == "6" and seq3 == "~" then return "PAGE_DOWN" end
        end

        -- Touches spéciales Magis Club / VT100
        if full_seq == "OP" then return "SOMMAIRE" end
        if full_seq == "OQ" then return "ANNULATION" end
        if full_seq == "OR" then return "RETOUR" end
        if full_seq == "OS" then return "REPETITION" end
        if full_seq == "Om" then return "GUIDE" end
        if full_seq == "Ol" then return "CORRECTION" end
        if full_seq == "On" then return "SUITE" end
        if full_seq == "OM" then return "ENVOI" end

        return "UNKNOWN_ESC"
    end
    return c
end

-- =====================================================================
-- 3. UTILITAIRES DE TEXTE ET FORMATAGE (80 COLONNES)
-- =====================================================================
function M.pad(str, len)
    str = tostring(str or "")
    if #str > len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

function M.center(str, len)
    str = tostring(str or "")
    if #str >= len then return string.sub(str, 1, len) end
    local left = math.floor((len - #str) / 2)
    local right = len - #str - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

function M.clean_accents(str)
    if not str then return "" end
    str = str:gsub("[éèêëÉÈÊË]", "E")
    str = str:gsub("[àâäÀÂÄ]", "A")
    str = str:gsub("[îïÎÏ]", "I")
    str = str:gsub("[ôöÔÖ]", "O")
    str = str:gsub("[ùûüÙÛÜ]", "U")
    str = str:gsub("[çÇ]", "C")
    str = str:gsub("œ", "OE"):gsub("’", "'")
    return str
end

function M.wrap(text, max_width, max_lines)
    local lines = {}
    local current = ""
    for word in tostring(text or ""):gmatch("%S+") do
        if #current + #word + 1 > max_width then
            table.insert(lines, M.pad(current, max_width))
            current = word
            if max_lines and #lines >= max_lines then break end
        else
            current = (current == "") and word or (current .. " " .. word)
        end
    end
    if (not max_lines or #lines < max_lines) and current ~= "" then
        table.insert(lines, M.pad(current, max_width))
    end
    if max_lines then
        while #lines < max_lines do
            table.insert(lines, string.rep(" ", max_width))
        end
    end
    return lines
end

-- =====================================================================
-- 4. PRIMITIVES GRAPHIQUES & COMPOSANTS UI (BOITES DE DIALOGUE)
-- =====================================================================

-- Dessine un cadre générique aux coordonnées (x, y) de taille (w, h)
function M.draw_window(x, y, w, h, title)
    local inner_w = w - 2
    if title and title ~= "" then
        local t_str = " " .. string.sub(title, 1, inner_w - 2) .. " "
        io.write(string.format("\x1b[%d;%dH\x1b[1m+\x1b[0m\x1b[7m%s\x1b[0m\x1b[1m+\x1b[0m", y, x, M.center(t_str, inner_w)))
    else
        io.write(string.format("\x1b[%d;%dH\x1b[1m+%s+\x1b[0m", y, x, string.rep("-", inner_w)))
    end

    local empty_row = string.rep(" ", inner_w)
    for i = 1, h - 2 do
        io.write(string.format("\x1b[%d;%dH\x1b[1m|\x1b[0m%s\x1b[1m|\x1b[0m", y + i, x, empty_row))
    end
    io.write(string.format("\x1b[%d;%dH\x1b[1m+%s+\x1b[0m", y + h - 1, x, string.rep("-", inner_w)))
    io.flush()
end

-- Dessine une barre de progression ASCII (ex: Vie, Charge CPU, Réseau)
function M.progress_bar(x, y, width, current, max, show_pct)
    local bar_w = show_pct and (width - 7) or (width - 2)
    if bar_w < 2 then bar_w = 2 end
    local ratio = math.max(0, math.min(1, current / math.max(1, max)))
    local filled = math.floor(ratio * bar_w + 0.5)
    local empty = bar_w - filled

    local bar = "[" .. "\x1b[7m" .. string.rep(" ", filled) .. "\x1b[0m" .. string.rep(".", empty) .. "]"
    if show_pct then
        bar = bar .. string.format(" %3d%%", math.floor(ratio * 100))
    end
    io.write(string.format("\x1b[%d;%dH%s", y, x, bar))
    io.flush()
end

-- Boîte d'alerte / Notification modale
function M.msg_box(title, message, sound_effect)
    if sound_effect then M.play_sound(sound_effect) end
    local w, h = 50, 8
    local x, y = 16, 8
    M.draw_window(x, y, w, h, title or "INFORMATION")

    local lines = M.wrap(message, w - 6, 3)
    for i = 1, #lines do
        io.write(string.format("\x1b[%d;%dH%s", y + 1 + i, x + 3, M.center(lines[i]:gsub("%s+$", ""), w - 6)))
    end

    io.write(string.format("\x1b[%d;%dH\x1b[7m [ENVOI] CONTINUER \x1b[0m", y + h - 2, x + 15))
    io.flush()

    while true do
        local k = M.get_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == "\r" or k == "\n" or k == " " then
            break
        end
        M.sleep(0.02)
    end
end

-- Boîte de confirmation Oui/Non avec sélection au curseur ou clavier (Retourne true ou false)
function M.confirm_box(title, question)
    M.play_sound("hit")
    local w, h = 50, 8
    local x, y = 16, 8
    M.draw_window(x, y, w, h, title or "CONFIRMATION")

    local lines = M.wrap(question, w - 6, 2)
    for i = 1, #lines do
        io.write(string.format("\x1b[%d;%dH%s", y + 1 + i, x + 3, M.center(lines[i]:gsub("%s+$", ""), w - 6)))
    end

    local choice = true -- true = OUI, false = NON
    local function draw_buttons()
        local b_oui = choice and "\x1b[7m > [ OUI ] < \x1b[0m" or "   [ OUI ]   "
        local b_non = (not choice) and "\x1b[7m > [ NON ] < \x1b[0m" or "   [ NON ]   "
        io.write(string.format("\x1b[%d;%dH%s      %s", y + 5, x + 9, b_oui, b_non))
        io.flush()
    end

    draw_buttons()

    while true do
        local k = M.get_key()
        if k == "LEFT" or k == "RIGHT" or k == "Q" or k == "q" or k == "D" or k == "d" then
            choice = not choice
            draw_buttons()
        elseif k == "O" or k == "o" then
            return true
        elseif k == "N" or k == "n" or k == "RETOUR" or k == "ESC" then
            return false
        elseif k == "ENVOI" or k == "\r" or k == "\n" or k == " " then
            return choice
        end
        M.sleep(0.02)
    end
end

-- Boîte de saisie de texte modale (Retourne la chaîne ou nil si annulé)
function M.input_box(title, prompt, default_val, max_len)
    local w, h = 52, 8
    local x, y = 15, 8
    local limit = math.min(max_len or 36, 44)
    local str = tostring(default_val or "")

    M.draw_window(x, y, w, h, title or "SAISIE")
    io.write(string.format("\x1b[%d;%dH\x1b[1m%s\x1b[0m", y + 2, x + 3, M.pad(prompt or "VALEUR :", w - 6)))
    io.write(string.format("\x1b[%d;%dH[ENVOI] VALIDER  |  [ANNUL.] VIDER  |  [RETOUR] ESC", y + 6, x + 1))

    local function draw_field()
        local disp = string.sub(str, 1, limit)
        io.write(string.format("\x1b[%d;%dH> \x1b[7m %-44s \x1b[0m", y + 4, x + 2, disp))
        io.flush()
    end

    draw_field()

    while true do
        local k = M.get_key()
        if k then
            if k == "ENVOI" or k == "\r" or k == "\n" then
                return str
            elseif k == "RETOUR" or k == "ESC" then
                return nil
            elseif k == "ANNULATION" then
                str = ""
                draw_field()
            elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    draw_field()
                end
            elseif string.match(k, "^[%w%s%p_%.%-]$") and #k == 1 then
                if #str < limit then
                    str = str .. k
                    draw_field()
                end
            end
        end
        M.sleep(0.01)
    end
end

-- =====================================================================
-- 5. EXPLORATEUR DE FICHIERS SYSTEME (DELTA-DRAWING)
-- =====================================================================
function M.file_browser(mode, start_dir)
    local current_dir = start_dir or "./"
    if string.sub(current_dir, -1) ~= "/" then current_dir = current_dir .. "/" end

    local function scan_dir(path)
        local items, dirs, files = {}, {}, {}
        if path ~= "./" and path ~= "" and path ~= "/" then
            table.insert(items, { name = ".. (Dossier Parent)", is_dir = true, real_name = ".." })
        end
        
        local f = io.popen("\\ls -1p '" .. path .. "' 2>/dev/null")
        if f then
            for line in f:lines() do
                if string.sub(line, -1) == "/" then table.insert(dirs, string.sub(line, 1, -2))
                else table.insert(files, line) end
            end
            f:close()
        end
        
        for _, d in ipairs(dirs) do table.insert(items, { name = "[" .. d .. "]", is_dir = true, real_name = d }) end
        for _, file in ipairs(files) do table.insert(items, { name = file, is_dir = false, real_name = file }) end
        if #items == 0 then table.insert(items, { name = "(Dossier Vide)", is_dir = false, real_name = "" }) end
        return items
    end

    local items = scan_dir(current_dir)
    local cursor, list_offset, max_visible = 1, 0, 12
    local input_buffer = ""

    if mode == "SAVE" and items[1] and not items[1].is_dir and items[1].real_name ~= "" then
        input_buffer = items[1].real_name
    end

    local function draw_path_bar()
        io.write(string.format("\x1b[5;17H CHEMIN : \x1b[1m%-38s\x1b[0m", string.sub(current_dir, 1, 38)))
    end

    local function draw_input_box()
        if mode == "SAVE" then
            io.write(string.format("\x1b[20;24H\x1b[7m %-38s \x1b[0m", string.sub(input_buffer, 1, 38)))
        end
    end

    local function draw_single_row(slot)
        local idx = list_offset + slot
        local item = items[idx]
        local y = 6 + slot
        if item then
            local disp = string.sub(item.name, 1, 43)
            if idx == cursor then
                io.write(string.format("\x1b[%d;17H\x1b[7m > %-44s\x1b[0m", y, disp))
            else
                io.write(string.format("\x1b[%d;17H   %-44s", y, disp))
            end
        else
            io.write(string.format("\x1b[%d;17H%s", y, string.rep(" ", 47)))
        end
    end

    local function draw_scrollbar()
        if #items > max_visible then
            local thumb = math.floor(((cursor - 1) / math.max(1, #items - 1)) * (max_visible - 3)) + 2
            for i = 1, max_visible do
                local char = (i == 1 and "^") or (i == max_visible and "v") or (i == thumb and "\x1b[7m#\x1b[0m") or ":"
                io.write(string.format("\x1b[%d;65H%s", 6 + i, char))
            end
        else
            for i = 1, max_visible do io.write(string.format("\x1b[%d;65H ", 6 + i)) end
        end
    end

    local function draw_list_all()
        for i = 1, max_visible do draw_single_row(i) end
        draw_scrollbar()
    end

    local function draw_static_frame()
        local title = mode == "OPEN" and "OUVRIR UN FICHIER" or "SAUVEGARDER LE FICHIER"
        M.draw_window(15, 4, 52, 18, title)
        io.write("\x1b[6;15H\x1b[1m+--------------------------------------------------+\x1b[0m")
        io.write("\x1b[19;15H\x1b[1m+--------------------------------------------------+\x1b[0m")
        if mode == "SAVE" then
            io.write("\x1b[20;16H NOM :                                            ")
        else
            io.write("\x1b[20;16H  [ENVOI] SELECTIONNER     |     [RETOUR] ANNULER ")
        end
        draw_path_bar()
        draw_list_all()
        draw_input_box()
        io.flush()
    end

    draw_static_frame()

    while true do
        local k = M.get_key()
        if k == "RETOUR" or k == "ESC" then
            return nil
        elseif mode == "SAVE" and k == "ANNULATION" then
            input_buffer = ""
            draw_input_box()
            io.flush()
        elseif mode == "SAVE" and (string.match(k or "", "^[%w%s%p_%.%-]$") and #k == 1) then
            if #input_buffer < 35 then
                input_buffer = input_buffer .. k
                draw_input_box()
                io.flush()
            end
        elseif mode == "SAVE" and (k == "CORRECTION" or k == "\x08" or k == "\x7f") then
            if #input_buffer > 0 then
                input_buffer = string.sub(input_buffer, 1, -2)
                draw_input_box()
                io.flush()
            end
        elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s" then
            local is_up = (k == "UP" or k == "Z" or k == "z")
            local old_cursor, old_offset = cursor, list_offset

            if is_up then
                if cursor > 1 then
                    cursor = cursor - 1
                    if cursor <= list_offset then list_offset = cursor - 1 end
                else
                    cursor = #items
                    list_offset = math.max(0, #items - max_visible)
                end
            else
                if cursor < #items then
                    cursor = cursor + 1
                    if cursor > list_offset + max_visible then list_offset = cursor - max_visible end
                else
                    cursor, list_offset = 1, 0
                end
            end

            if cursor ~= old_cursor then
                if list_offset ~= old_offset then
                    draw_list_all()
                else
                    draw_single_row(old_cursor - list_offset)
                    draw_single_row(cursor - list_offset)
                    draw_scrollbar()
                end
                if mode == "SAVE" and not items[cursor].is_dir and items[cursor].real_name ~= "" then
                    input_buffer = items[cursor].real_name
                    draw_input_box()
                end
                io.flush()
            end
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local sel = items[cursor]
            if mode == "OPEN" then
                if sel.is_dir then
                    if sel.real_name == ".." then current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else current_dir = current_dir .. sel.real_name .. "/" end
                    items = scan_dir(current_dir)
                    cursor, list_offset = 1, 0
                    draw_path_bar(); draw_list_all(); io.flush()
                elseif sel.real_name ~= "" then
                    return current_dir .. sel.real_name
                end
            elseif mode == "SAVE" then
                if sel and sel.is_dir and input_buffer == "" then
                    if sel.real_name == ".." then current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else current_dir = current_dir .. sel.real_name .. "/" end
                    items = scan_dir(current_dir)
                    cursor, list_offset = 1, 0
                    draw_path_bar(); draw_list_all(); io.flush()
                elseif input_buffer ~= "" then
                    return current_dir .. input_buffer
                end
            end
        end
        M.sleep(0.01)
    end
end

return M