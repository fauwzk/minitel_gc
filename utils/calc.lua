-- @TYPE: TABLEUR / FINANCES
-- @DESC: Tableur dynamique multi-feuilles avec formules et boites de dialogue systeme.

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p utils/prog_calc 2>/dev/null")

-- =====================================================================
-- STRUCTURE DE DONNEES DU TABLEUR
-- =====================================================================
local workbook = {
    sheets = {
        { name = "FEUIL1", cells = {} }
    }
}
local active_sheet = 1
local filename = ""
local is_modified = false
local running = true

-- Navigation et Vue
local cx, cy = 1, 1 -- Curseur absolu (A1 = 1,1)
local view_x, view_y = 1, 1 -- Offset de l'ecran
local COL_WIDTH = 9
local VISIBLE_COLS = 7 -- A a G par defaut
local VISIBLE_ROWS = 18

-- =====================================================================
-- MOTEUR D'EVALUATION DES FORMULES (MAGIS ENGINE)
-- =====================================================================
local function parse_ref(ref)
    local col_str, row_str = string.match(ref, "^([A-Z]+)(%d+)$")
    if not col_str or not row_str then return nil, nil end
    local x = 0
    for i = 1, #col_str do
        x = x * 26 + (string.byte(col_str, i) - 64)
    end
    return x, tonumber(row_str)
end

local function col_name(x)
    local name = ""
    while x > 0 do
        local rem = (x - 1) % 26
        name = string.char(65 + rem) .. name
        x = math.floor((x - 1) / 26)
    end
    return name
end

local eval_env = {}
local eval_stack = {}

local function get_cell_val(ref, sheet_name)
    local target_sheet = workbook.sheets[active_sheet]
    if sheet_name then
        for _, s in ipairs(workbook.sheets) do
            if s.name == sheet_name then target_sheet = s; break end
        end
    end
    
    if not target_sheet then return 0 end
    
    local x, y = parse_ref(ref)
    if not x then return 0 end
    
    local key = x .. "_" .. y
    local raw = target_sheet.cells[key]
    if not raw then return 0 end
    
    if string.sub(raw, 1, 1) ~= "=" then
        return tonumber(raw) or raw
    end
    
    local stack_key = target_sheet.name .. "!" .. key
    if eval_stack[stack_key] then return "#REF!" end
    eval_stack[stack_key] = true
    
    local formula = string.sub(raw, 2)
    formula = string.gsub(formula, "([%w_]+)!([A-Z]+%d+)", "V('%2', '%1')")
    formula = string.gsub(formula, "([A-Z]+%d+)", "V('%1')")
    
    local func = load("return " .. formula, "calc", "t", eval_env)
    local result = "#ERR!"
    if func then
        local ok, val = pcall(func)
        if ok then result = val end
    end
    
    eval_stack[stack_key] = nil
    return result
end

eval_env.V = get_cell_val
eval_env.math = math

eval_env.SOMME = function(range)
    local start_ref, end_ref = string.match(range, "^([A-Z]+%d+):([A-Z]+%d+)$")
    if not start_ref then return 0 end
    local x1, y1 = parse_ref(start_ref)
    local x2, y2 = parse_ref(end_ref)
    if not x1 or not x2 then return 0 end
    
    local total = 0
    for y = math.min(y1, y2), math.max(y1, y2) do
        for x = math.min(x1, x2), math.max(x1, x2) do
            local val = get_cell_val(col_name(x) .. y)
            if type(val) == "number" then total = total + val end
        end
    end
    return total
end

eval_env.MOYENNE = function(range)
    local start_ref, end_ref = string.match(range, "^([A-Z]+%d+):([A-Z]+%d+)$")
    if not start_ref then return 0 end
    local x1, y1 = parse_ref(start_ref)
    local x2, y2 = parse_ref(end_ref)
    if not x1 or not x2 then return 0 end
    
    local total, count = 0, 0
    for y = math.min(y1, y2), math.max(y1, y2) do
        for x = math.min(x1, x2), math.max(x1, x2) do
            local val = get_cell_val(col_name(x) .. y)
            if type(val) == "number" then
                total = total + val
                count = count + 1
            end
        end
    end
    return count > 0 and (total / count) or 0
end

-- =====================================================================
-- FONCTIONS D'AFFICHAGE OPTIMISEES (DELTA-DRAWING)
-- =====================================================================
local function format_val(val, width)
    if val == nil then return string.rep(" ", width) end
    local s = tostring(val)
    if #s > width then return string.sub(s, 1, width) end
    if type(val) == "number" then
        return string.rep(" ", width - #s) .. s
    else
        return s .. string.rep(" ", width - #s)
    end
end

local function draw_cell(x, y, is_highlighted)
    local scr_x = 6 + (x - view_x) * (COL_WIDTH + 1)
    local scr_y = 5 + (y - view_y)
    
    if x < view_x or x >= view_x + VISIBLE_COLS then return end
    if y < view_y or y >= view_y + VISIBLE_ROWS then return end
    
    local key = x .. "_" .. y
    local raw = workbook.sheets[active_sheet].cells[key]
    local val = ""
    
    if raw then
        if string.sub(raw, 1, 1) == "=" then
            val = get_cell_val(col_name(x) .. y)
        else
            val = raw
        end
    end
    
    local text = format_val(val, COL_WIDTH)
    local c = is_highlighted and "\x1b[7m" or ""
    local res = "\x1b[0m"
    
    io.write(string.format("\x1b[%d;%dH%s %s %s|", scr_y, scr_x, c, text, res))
    io.flush()
end

local function draw_static_top_bar()
    local fname = (filename == "" and "SANS NOM" or filename) .. (is_modified and "*" or "")
    local title = string.format(" MAGIS CALC | FICHIER: %-15s | FEUILLE %d/%d : %-15s ", 
        fname, active_sheet, #workbook.sheets, workbook.sheets[active_sheet].name)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.pad(title, 80) .. "\x1b[0m")
end

local function update_formula_bar()
    io.write("\x1b7")
    local key = cx .. "_" .. cy
    local raw = workbook.sheets[active_sheet].cells[key] or ""
    local ref = string.format("[%s%d]", col_name(cx), cy)
    io.write("\x1b[2;1H\x1b[K \x1b[1m" .. ref .. "\x1b[0m " .. string.sub(raw, 1, 65))
    io.write("\x1b8")
    io.flush()
end

local function refresh_visible_cells()
    for y = view_y, view_y + VISIBLE_ROWS - 1 do
        for x = view_x, view_x + VISIBLE_COLS - 1 do
            draw_cell(x, y, (x == cx and y == cy))
        end
    end
    update_formula_bar()
end

local function draw_grid()
    io.write("\x1b[3;1H\x1b[K    |")
    for i = 0, VISIBLE_COLS - 1 do
        local col_c = col_name(view_x + i)
        io.write("\x1b[7m " .. minitel.center(col_c, COL_WIDTH) .. " \x1b[0m|")
    end
    io.write("\r\n\x1b[4;1H--------------------------------------------------------------------------------\r\n")
    
    for i = 0, VISIBLE_ROWS - 1 do
        local r = view_y + i
        io.write(string.format("\x1b[%d;1H\x1b[K\x1b[7m %02d \x1b[0m|", 5 + i, r))
        for j = 0, VISIBLE_COLS - 1 do
            io.write(string.rep(" ", COL_WIDTH + 2) .. "|")
        end
    end
    
    refresh_visible_cells()
    
    io.write("\x1b[24;1H\x1b[7m  [ENTREE] EDITER | [REPETITION] CALCULER | [< >] FEUILLES | [RETOUR] MENU    \x1b[0m")
    draw_static_top_bar()
    io.flush()
end

-- =====================================================================
-- CONTROLE DU CURSEUR ET EDITION DE CELLULE
-- =====================================================================
local function move_cursor(dx, dy)
    local old_x, old_y = cx, cy
    cx = math.max(1, cx + dx)
    cy = math.max(1, cy + dy)
    
    local need_redraw = false
    if cx < view_x then view_x = cx; need_redraw = true end
    if cx >= view_x + VISIBLE_COLS then view_x = cx - VISIBLE_COLS + 1; need_redraw = true end
    if cy < view_y then view_y = cy; need_redraw = true end
    if cy >= view_y + VISIBLE_ROWS then view_y = cy - VISIBLE_ROWS + 1; need_redraw = true end
    
    if need_redraw then
        draw_grid()
    else
        draw_cell(old_x, old_y, false)
        draw_cell(cx, cy, true)
        update_formula_bar()
    end
end

local function edit_cell()
    local key = cx .. "_" .. cy
    local old_val = workbook.sheets[active_sheet].cells[key] or ""
    local val = old_val
    
    io.write("\x1b[2;1H\x1b[K \x1b[1m[" .. col_name(cx) .. cy .. "]\x1b[0m \x1b[7m" .. val)
    io.flush()
    
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                if val ~= old_val then
                    is_modified = true
                    draw_static_top_bar()
                end
                if val == "" then workbook.sheets[active_sheet].cells[key] = nil
                else workbook.sheets[active_sheet].cells[key] = val end
                break
            elseif k == "RETOUR" or k == "ESC" then
                break
            elseif k == "ANNULATION" then
                val = ""
                io.write("\x1b[2;1H\x1b[K \x1b[1m[" .. col_name(cx) .. cy .. "]\x1b[0m \x1b[7m")
                io.flush()
            elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
                if #val > 0 then
                    val = string.sub(val, 1, -2)
                    io.write("\x1b[D \x1b[D"); io.flush()
                end
            elseif string.match(k, "^[%w%s%p_%.%-=+!:]$") and #k == 1 then
                if #val < 65 then
                    val = val .. k
                    io.write(k); io.flush()
                end
            end
        end
        minitel.sleep(0.01)
    end
    
    eval_stack = {}
    refresh_visible_cells()
end

-- =====================================================================
-- GESTION DES FICHIERS (SERIALISATION LUA)
-- =====================================================================
local function save_workbook(path)
    local f = io.open(path, "w")
    if not f then return false end
    
    f:write("return {\n  sheets = {\n")
    for _, sheet in ipairs(workbook.sheets) do
        f:write(string.format("    { name = %q, cells = {\n", sheet.name))
        for k, v in pairs(sheet.cells) do
            f:write(string.format("      [%q] = %q,\n", k, v))
        end
        f:write("    } },\n")
    end
    f:write("  }\n}\n")
    f:close()
    return true
end

local function load_workbook(path)
    local f = loadfile(path)
    if f then
        local ok, data = pcall(f)
        if ok and type(data) == "table" and data.sheets then
            workbook = data
            active_sheet = 1
            cx, cy, view_x, view_y = 1, 1, 1, 1
            filename = string.match(path, "([^/%\\]+)$") or path
            is_modified = false
            return true
        end
    end
    return false
end

-- =====================================================================
-- MENU PRINCIPAL (AVEC DIALOGUES SDK)
-- =====================================================================
local function draw_calc_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 MAGIS CALC \x1b[0m                                             \x1b[1m TABLEUR PRO \x1b[0m")
    io.write("\x1b[2;1H================================================================================")
    
    minitel.draw_window(22, 5, 38, 16, "MENU CLASSEUR")
    io.write("\x1b[7;26H\x1b[7m [1] \x1b[0m REPRENDRE LE CALCUL")
    io.write("\x1b[9;26H\x1b[7m [2] \x1b[0m NOUVEAU CLASSEUR")
    io.write("\x1b[11;26H\x1b[7m [3] \x1b[0m AJOUTER UNE FEUILLE...")
    io.write("\x1b[13;26H\x1b[7m [4] \x1b[0m OUVRIR UN CLASSEUR...")
    io.write("\x1b[15;26H\x1b[7m [5] \x1b[0m SAUVEGARDER SOUS...")
    io.write("\x1b[18;26H\x1b[7m [9] \x1b[0m QUITTER MAGIS CALC")
    
    io.write("\x1b[24;1H\x1b[7m  TAPEZ LE NUMERO DE L'OPTION SOUHAITEE OU [RETOUR] POUR REVENIR AU TABLEUR    \x1b[0m")
    io.flush()
end

local function handle_menu()
    draw_calc_menu()
    
    while true do
        local k = minitel.get_key()
        if k == "1" or k == "RETOUR" or k == "ESC" then
            break
            
        elseif k == "2" then
            if not is_modified or minitel.confirm_box("NOUVEAU CLASSEUR", "Ecraser le classeur actuel non sauvegarde ?") then
                workbook = { sheets = { { name = "FEUIL1", cells = {} } } }
                active_sheet = 1; cx = 1; cy = 1; view_x = 1; view_y = 1
                filename = ""; is_modified = false
                break
            end
            draw_calc_menu()
            
        elseif k == "3" then
            local default_name = "FEUIL" .. (#workbook.sheets + 1)
            local new_name = minitel.input_box("NOUVELLE FEUILLE", "Nom de la feuille :", default_name, 15)
            if new_name and new_name ~= "" then
                new_name = string.upper(new_name:gsub("%s+", "_"))
                table.insert(workbook.sheets, { name = new_name, cells = {} })
                active_sheet = #workbook.sheets
                cx, cy, view_x, view_y = 1, 1, 1, 1
                is_modified = true
                break
            end
            draw_calc_menu()
            
        elseif k == "4" then
            if is_modified and not minitel.confirm_box("OUVRIR", "Abandonner les calculs non sauvegardes ?") then
                draw_calc_menu()
            else
                local target = minitel.file_browser("OPEN", "utils/prog_calc/")
                if target then
                    if load_workbook(target) then
                        break
                    else
                        minitel.msg_box("ERREUR FORMAT", "Ce fichier n'est pas un classeur Magis Calc valide.", "lose")
                    end
                end
                draw_calc_menu()
            end
            
        elseif k == "5" then
            local target = minitel.file_browser("SAVE", "utils/prog_calc/")
            if target then
                if save_workbook(target) then
                    filename = string.match(target, "([^/%\\]+)$") or target
                    is_modified = false
                    minitel.msg_box("SAUVEGARDE REUSSIE", "Classeur enregistre sous : " .. filename, "win")
                    break
                else
                    minitel.msg_box("ERREUR DISQUE", "Impossible d'enregistrer le classeur.", "lose")
                end
            end
            draw_calc_menu()
            
        elseif k == "9" then
            if not is_modified or minitel.confirm_box("QUITTER", "Le classeur a ete modifie ! Quitter sans sauvegarder ?") then
                running = false
                break
            end
            draw_calc_menu()
        end
        minitel.sleep(0.02)
    end
    
    if running then
        io.write("\x1b[r\x1b[2J\x1b[H")
        draw_grid()
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
io.write("\x1b[r\x1b[2J\x1b[H")
draw_grid()

while running do
    local k = minitel.get_key()
    
    if k then
        if k == "UP" or k == "Z" or k == "z" then move_cursor(0, -1)
        elseif k == "DOWN" or k == "S" or k == "s" then move_cursor(0, 1)
        elseif k == "LEFT" or k == "Q" or k == "q" then move_cursor(-1, 0)
        elseif k == "RIGHT" or k == "D" or k == "d" then move_cursor(1, 0)
        elseif k == "<" then
            if active_sheet > 1 then
                active_sheet = active_sheet - 1
                draw_grid()
            end
        elseif k == ">" then
            if active_sheet < #workbook.sheets then
                active_sheet = active_sheet + 1
                draw_grid()
            end
        elseif k == "ANNULATION" then
            -- Efface rapidement le contenu de la cellule selectionnee
            local key = cx .. "_" .. cy
            if workbook.sheets[active_sheet].cells[key] then
                workbook.sheets[active_sheet].cells[key] = nil
                is_modified = true
                eval_stack = {}
                draw_static_top_bar()
                refresh_visible_cells()
            end
        elseif k == "REPETITION" or k == "SUITE" then
            eval_stack = {}
            draw_grid()
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            edit_cell()
        elseif k == "RETOUR" or k == "ESC" then
            handle_menu()
        end
    end
    minitel.sleep(0.01)
end

minitel.cleanup()