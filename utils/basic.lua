local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic")

local program = {}
local vars = {}

local current_filename = nil
local is_modified = false

-- =====================================================================
-- EVALUATEUR MATHEMATIQUE INTEGRE (ROBUSTE)
-- =====================================================================
local function eval_expr(expr)
    local e = string.upper(expr)

    e = string.gsub(e, "<>", "~=")
    e = string.gsub(e, "<=", "<=")
    e = string.gsub(e, ">=", ">=")
    e = string.gsub(e, "=", "==")
    e = string.gsub(e, "====", "==") 

    e = string.gsub(e, "%a+", function(w)
        if w == "EQ" then return "==" end
        if w == "NEQ" then return "~=" end
        if w == "LT" then return "<" end
        if w == "GT" then return ">" end
        if w == "LE" then return "<=" end
        if w == "GE" then return ">=" end
        if w == "PLUS" then return "+" end
        if w == "MINUS" then return "-" end
        if w == "MUL" then return "*" end
        if w == "DIV" then return "/" end
        
        if w == "AND" or w == "OR" or w == "NOT" then return string.lower(w) end
        if w == "RND" or w == "MKEY" then return string.lower(w) end
        
        return tostring(vars[w] or 0)
    end)

    local env = {
        rnd = function(max) return math.random(1, math.floor(max or 10)) end,
        mkey = function()
            local k = minitel.get_key()
            if not k then return 0 end
            if k == "UP" then return 200 end
            if k == "DOWN" then return 201 end
            if k == "LEFT" then return 202 end
            if k == "RIGHT" then return 203 end
            if k == "ENVOI" or k == "\r" or k == "\n" then return 13 end
            if k == "RETOUR" or k == "ESC" then return 27 end
            return string.byte(k) or 0
        end
    }

    local func = load("return " .. e, "eval", "t", env)
    if func then
        local ok, val = pcall(func)
        if ok then
            if type(val) == "boolean" then return val and 1 or 0 end
            return tonumber(val) or 0
        end
    end
    return 0
end

-- =====================================================================
-- LECTURE DU CLAVIER (Gère maintenant l'annulation)
-- =====================================================================
local function input_string(prompt)
    io.write(prompt)
    io.flush()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                io.write("\r\n")
                io.flush()
                return string.upper(str)
            elseif k == "RETOUR" or k == "ESC" then
                -- On intercepte le retour pour forcer un Break !
                return "ABORT"
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D")
                    io.flush()
                end
            elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
                k = string.upper(k)
                str = str .. k
                io.write(k)
                io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- MISE A JOUR DE L'INTERFACE (Remontée pour être utilisée par CLS)
-- =====================================================================
local function update_ui()
    io.write("\x1b7\x1b[s") -- Sauvegarde du curseur (Mix VT100 et ANSI pour sécurité)
    
    -- FORCE la zone de défilement de la ligne 2 à 23 à chaque rafraichissement
    io.write("\x1b[2;23r") 
    
    io.write("\x1b[1;1H\x1b[7m MICRO-BASIC TELETEL V1.9               [EXIT] OU [RETOUR] POUR QUITTER \x1b[K\x1b[0m")

    local count = 0
    for _ in pairs(program) do count = count + 1 end
    local fname = current_filename or "SANS NOM"
    local mod_star = is_modified and "*" or ""

    local status_text = string.format(" LIGNES : %03d | FICHIER : %s%s | TAPEZ 'HELP' ", count, fname, mod_star)
    
    -- COUPE le texte à 78 caractères pour empêcher le terminal de forcer un "Entrée" invisible
    status_text = string.sub(status_text, 1, 78)
    
    io.write("\x1b[24;1H\x1b[7m" .. status_text .. "\x1b[K\x1b[0m")

    io.write("\x1b8\x1b[u") -- Restauration du curseur
    io.flush()
end

-- =====================================================================
-- MOTEUR D'EXECUTION DES LIGNES
-- =====================================================================
local function execute_line(line)
    local outside_quotes = string.gsub(line, '([^"]*)', function(s) return string.upper(s) end)
    line = string.match(outside_quotes, "^%s*(.-)%s*$")
    
    if line == "" then return "OK" end

    local cmd, rest = string.match(line, "^(%a+)%s*(.*)$")

    if cmd == "PRINT" then
        local content = string.match(rest, "^%s*%((.*)%)%s*$") or rest
        if string.sub(content, 1, 1) == '"' then
            local str, after = string.match(content, '^"(.-)"%s*;?%s*(.*)$')
            io.write(str or "")
            if after and after ~= "" then io.write(tostring(eval_expr(after))) end
            io.write("\r\n")
            io.flush()
        else
            io.write(tostring(eval_expr(content)) .. "\r\n")
            io.flush()
        end
        return "OK"

    elseif cmd == "LET" then
        local v, val = string.match(rest, "^(%a+)%s*=%s*(.*)$")
        if not v then v, val = string.match(rest, "^(%a+)%s+EQ%s+(.*)$") end
        if v then vars[v] = eval_expr(val)
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "INPUT" then
        local v = string.match(rest, "^(%a+)$")
        if v then
            local res = input_string("? ")
            if res == "ABORT" then return "BREAK" end
            vars[v] = tonumber(res) or 0
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "GOTO" then
        local target = tonumber(eval_expr(rest))
        if target then return "GOTO", target
        else return "SYNTAX ERROR" end

    elseif cmd == "IF" then
        local cond, then_cmd = string.match(rest, "^(.-)%s+THEN%s+(.*)$")
        if cond and then_cmd then
            local cond_val = eval_expr(cond)
            if cond_val ~= 0 then return execute_line(then_cmd) end
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "CLS" then
        io.write("\x1b[2J") -- Efface tout
        update_ui()         -- Redessine l'interface immédiatement !
        io.write("\x1b[2;1H") -- Replace le curseur au début de la zone propre
        io.flush()
        return "OK"

    elseif cmd == "BEEP" then
        minitel.play_sound("hit")
        return "OK"

    elseif cmd == "LOCATE" then
        local str_x, str_y = string.match(rest, "^(.-)%s*,%s*(.*)$")
        if str_x and str_y then
            local x = math.floor(eval_expr(str_x))
            local y = math.floor(eval_expr(str_y))
            x = math.max(1, math.min(80, x))
            y = math.max(1, math.min(23, y)) -- MAX 23 pour protéger la barre du bas !
            io.write("\x1b[" .. y .. ";" .. x .. "H")
            io.flush()
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "INVERT" then
        io.write("\x1b[7m")
        io.flush()
        return "OK"

    elseif cmd == "NORMAL" then
        io.write("\x1b[0m")
        io.flush()
        return "OK"

    elseif cmd == "PAUSE" then
        local sec = tonumber(eval_expr(rest))
        if sec then
            -- Permet d'interrompre une pause avec RETOUR
            for i=1, math.floor(sec*10) do
                local k = minitel.get_key()
                if k == "RETOUR" or k == "ESC" then return "BREAK" end
                minitel.sleep(0.1)
            end
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "RANDOM" then
        local quotes = {"3615 ULLA EST FERME.", "ERREUR SYSTEME : CAFEINE.", "TAPEZ 3615 PERE NOEL."}
        io.write(quotes[math.random(#quotes)] .. "\r\n")
        io.flush()
        return "OK"

    elseif cmd == "END" then return "END"
    elseif cmd == "REM" then return "OK" end

    local v, val = string.match(line, "^(%a+)%s*=%s*(.*)$")
    if not v then v, val = string.match(line, "^(%a+)%s+EQ%s+(.*)$") end

    if v then
        vars[v] = eval_expr(val)
        return "OK"
    end
    return "SYNTAX ERROR"
end

-- =====================================================================
-- BOUCLE D'EXECUTION GLOBALE (RUN)
-- =====================================================================
local function run_program()
    local sorted_lines = {}
    for k in pairs(program) do table.insert(sorted_lines, k) end
    table.sort(sorted_lines)

    local pc = 1
    while pc <= #sorted_lines do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then
            -- \x1b[K force le nettoyage de la ligne courante avant d'écrire
            io.write("\r\n\x1b[K\x1b[7m BREAK IN " .. sorted_lines[pc] .. " \x1b[0m\r\n")
            io.flush()
            break
        end

        local line_num = sorted_lines[pc]
        local line_str = program[line_num]

        local stat, arg = execute_line(line_str)

        if stat == "BREAK" then
            io.write("\r\n\x1b[K\x1b[7m BREAK IN " .. line_num .. " \x1b[0m\r\n")
            io.flush()
            break
        elseif stat == "SYNTAX ERROR" then
            io.write("\r\n\x1b[K SYNTAX ERROR IN " .. line_num .. "\r\n")
            io.flush()
            break
        elseif stat == "END" then
            break
        elseif stat == "GOTO" then
            local found = false
            for i, v in ipairs(sorted_lines) do
                if v == arg then
                    pc = i
                    found = true
                    break
                end
            end
            if not found then
                io.write("\r\n\x1b[K UNDEFINED LINE " .. arg .. " IN " .. line_num .. "\r\n")
                io.flush()
                break
            end
        else
            pc = pc + 1
        end
        minitel.sleep(0.005)
    end
end

-- =====================================================================
-- ECRAN D'AIDE COMPLET (SCROLLABLE)
-- =====================================================================
local function show_help()
    io.write("\x1b[r\x1b[2J\x1b[H")

    local help_lines = {
        "\x1b[1m COMMANDES SYSTEME \x1b[0m", 
        " RUN        : Execute le code en memoire",
        " LIST       : Affiche tout le code", 
        " NEW        : Efface la memoire",
        " DIR        : Liste les fichiers locaux", 
        " SAVE / LOAD: Ex: SAVE \"NOM\" (sans .bas)",
        " EXIT       : Quitter l'interpreteur", "",
        "\x1b[1m INSTRUCTIONS DU LANGAGE \x1b[0m", 
        " PRINT \"X\"  : Affiche du texte",
        " INPUT X    : Demande une valeur", 
        " LET X EQ 5 : Assigner (ou X = 5)",
        " IF..THEN   : Condition (Ex: IF X EQ 5 THEN GOTO 10)", 
        " GOTO X     : Saute a la ligne X",
        " PAUSE X    : Pause de X secondes", 
        " REM        : Commentaire (Ignore)", "",
        "\x1b[1m FONCTIONS MINITEL \x1b[0m", 
        " CLS        : Efface l'ecran",
        " BEEP       : Joue le son du Minitel", 
        " INVERT / NORMAL : Video inverse/normale",
        " LOCATE X,Y : Place le curseur (Max Y=23)",
        " MKEY()     : Lecture clavier (Fleches: 200-203. Envoi: 13)",
        " RND(X)     : Genere un nombre aleatoire entre 1 et X"
    }

    local offset = 1
    local max_visible = 20
    local max_offset = math.max(1, #help_lines - max_visible + 1)

    local function draw_help_screen()
        io.write("\x1b[1;1H\x1b[7m MICRO-BASIC : MANUEL               [FLECHES] DEFILER  [RETOUR] QUITTER \x1b[K\x1b[0m\r\n")
        for i = 1, max_visible do
            local line_idx = offset + i - 1
            io.write("\x1b[" .. (i + 2) .. ";1H\x1b[K")
            if help_lines[line_idx] then io.write(" " .. help_lines[line_idx]) end
        end
        local scroll_pct = math.floor(((offset - 1) / (max_offset - 1)) * 100)
        if max_offset == 1 then scroll_pct = 100 end
        io.write("\x1b[24;1H\x1b[7m APPUYEZ SUR [RETOUR] POUR FERMER                        SCROLL: " .. string.format("%3d", scroll_pct) .. "% \x1b[K\x1b[0m")
        io.flush()
    end

    draw_help_screen()

    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == " " or k == "ENVOI" or k == "\r" or k == "\n" then break
        elseif k == "UP" or k == "Z" or k == "z" then
            if offset > 1 then offset = offset - 1; draw_help_screen() end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if offset < max_offset then offset = offset + 1; draw_help_screen() end
        end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- INVITE DE COMMANDE SHELL
-- =====================================================================
local function shell()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;23r")
    io.write("\x1b[2;1H")

    io.write("\x1b[7m INITIALISATION DU SYSTEME \x1b[0m\r\nREADY.\r\n")
    io.flush()

    while true do
        update_ui()
        
        -- Le \x1b[K nettoie la ligne avant d'écrire le prompt
        local line = input_string("\x1b[K> ")

        if line == "ABORT" then
            io.write("\r\n")
            -- On annule proprement
        elseif line == "" then
            -- Ne rien faire
        elseif line == "HELP" then
            show_help()
            io.write("\x1b[2J\x1b[2;23r\x1b[2;1HREADY.\r\n")
            io.flush()
        elseif line == "EXIT" or line == "QUIT" then
            break

        elseif string.match(line, "^LIST") then
            local param = string.match(line, "^LIST%s*(.*)$")
            local start_l, end_l

            if param ~= "" then
                local n1, n2 = string.match(param, "^(%d+)%s*[-]%s*(%d+)$")
                if n1 and n2 then start_l, end_l = tonumber(n1), tonumber(n2)
                else
                    local n1_start = string.match(param, "^(%d+)%s*[-]$")
                    if n1_start then start_l = tonumber(n1_start)
                    else
                        local n1_only = string.match(param, "^(%d+)$")
                        if n1_only then start_l, end_l = tonumber(n1_only), tonumber(n1_only) end
                    end
                end
            end

            local sorted_lines = {}
            for k in pairs(program) do table.insert(sorted_lines, k) end
            table.sort(sorted_lines)

            local found = false
            for _, l in ipairs(sorted_lines) do
                local show = true
                if start_l and l < start_l then show = false end
                if end_l and l > end_l then show = false end

                if show then
                    io.write(string.format("\x1b[1m%d\x1b[0m %s\r\n", l, program[l]))
                    found = true
                end
            end
            if not found and param ~= "" then io.write("LINE NOT FOUND\r\n") end
            io.flush()

        elseif line == "RUN" then
            io.write("\x1b[2;23r") -- Sécurité supplémentaire avant exécution
            run_program()
            io.write("\x1b[KREADY.\r\n")
            io.flush()
        elseif line == "NEW" then
            program = {}
            vars = {}
            current_filename = nil
            is_modified = false
            io.write("READY.\r\n")
            io.flush()
        elseif line == "DIR" then
            local f = io.popen("ls -1 utils/prog_basic/*.bas 2>/dev/null")
            if f then
                local count = 0
                for file in f:lines() do
                    local display_name = string.gsub(file, "utils/prog_basic/", "")
                    io.write(display_name .. "\r\n")
                    count = count + 1
                end
                f:close()
                if count == 0 then io.write("NO FILES FOUND\r\n") end
            end
            io.write("READY.\r\n")
            io.flush()

        elseif string.match(line, '^SAVE%s+"(.-)"') then
            local filename = string.match(line, '^SAVE%s+"(.-)"')
            if filename then
                local f = io.open("utils/prog_basic/" .. filename .. ".bas", "w")
                if f then
                    local sorted_lines = {}
                    for k in pairs(program) do table.insert(sorted_lines, k) end
                    table.sort(sorted_lines)
                    for _, l in ipairs(sorted_lines) do f:write(l .. " " .. program[l] .. "\n") end
                    f:close()
                    current_filename = filename
                    is_modified = false
                    io.write("SAVED " .. filename .. "\r\n")
                else io.write("FILE ERROR\r\n") end
            end
            io.write("READY.\r\n")
            io.flush()

        elseif string.match(line, '^LOAD%s+"(.-)"') then
            local filename = string.match(line, '^LOAD%s+"(.-)"')
            if filename then
                local f = io.open("utils/prog_basic/" .. filename .. ".bas", "r")
                if f then
                    program = {}
                    vars = {}
                    for fline in f:lines() do
                        local lnum, rest = string.match(fline, "^(%d+)%s*(.*)$")
                        if lnum then program[tonumber(lnum)] = rest end
                    end
                    f:close()
                    current_filename = filename
                    is_modified = false
                    io.write("LOADED " .. filename .. "\r\n")
                else io.write("FILE NOT FOUND\r\n") end
            end
            io.write("READY.\r\n")
            io.flush()

        else
            local lnum, rest = string.match(line, "^(%d+)%s*(.*)$")
            if lnum then
                lnum = tonumber(lnum)
                if rest == "" then
                    if program[lnum] ~= nil then
                        program[lnum] = nil
                        is_modified = true
                    end
                else
                    if program[lnum] ~= rest then
                        program[lnum] = rest
                        is_modified = true
                    end
                end
            else
                local stat, _ = execute_line(line)
                if stat == "SYNTAX ERROR" then
                    io.write("SYNTAX ERROR\r\n")
                    io.flush()
                elseif stat == "GOTO" then
                    io.write("CANNOT GOTO IN IMMEDIATE MODE\r\n")
                    io.flush()
                end
            end
        end
    end
end

math.randomseed(os.time())
shell()

io.write("\x1b[r")
io.flush()
minitel.cleanup()