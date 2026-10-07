local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic")

local program = {}
local vars = {}
local current_filename = nil
local is_modified = false

-- =====================================================================
-- EVALUATEUR MATHEMATIQUE INTEGRE
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
        if w == "MOD" then return "%" end
        
        local reserved = {
            AND=1, OR=1, NOT=1, RND=1, MKEY=1, 
            SIN=1, COS=1, TAN=1, ABS=1, SQR=1, INT=1, PI=1, EXP=1, LOG=1
        }
        if reserved[w] then return string.lower(w) end
        return tostring(vars[w] or 0)
    end)

    local env = {
        rnd = function(max) return math.random(1, math.floor(max or 10)) end,
        mkey = function()
            local k = minitel.get_key()
            if not k then return 0 end
            if k == "UP" or k == "Z" or k == "z" then return 200 end
            if k == "DOWN" or k == "S" or k == "s" then return 201 end
            if k == "LEFT" or k == "Q" or k == "q" then return 202 end
            if k == "RIGHT" or k == "D" or k == "d" then return 203 end
            if k == "ENVOI" or k == "\r" or k == "\n" then return 13 end
            if k == "RETOUR" or k == "ESC" then return 27 end
            return string.byte(k) or 0
        end,
        sin = math.sin, cos = math.cos, tan = math.tan,
        abs = math.abs, sqr = math.sqrt, int = math.floor,
        pi = math.pi, exp = math.exp, log = math.log
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
-- LECTURE DU CLAVIER (AVEC GESTION DE CURSEUR ET EDITION)
-- =====================================================================
local function input_string(prompt, initial_text)
    io.write(prompt)
    local str = initial_text or ""
    if str ~= "" then io.write(str) end
    io.flush()
    
    local pos = #str

    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                io.write("\r\n")
                io.flush()
                return string.upper(str)
            elseif k == "RETOUR" or k == "ESC" then
                return "ABORT"
            elseif k == "LEFT" or k == "Q" then
                if pos > 0 then
                    pos = pos - 1
                    io.write("\x1b[D")
                    io.flush()
                end
            elseif k == "RIGHT" or k == "D" then
                if pos < #str then
                    pos = pos + 1
                    io.write("\x1b[C")
                    io.flush()
                end
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if pos > 0 then
                    local left = string.sub(str, 1, pos - 1)
                    local right = string.sub(str, pos + 1)
                    str = left .. right
                    pos = pos - 1
                    if #right > 0 then
                        io.write("\x1b[D" .. right .. " \x1b[" .. (#right + 1) .. "D")
                    else
                        io.write("\x1b[D \x1b[D")
                    end
                    io.flush()
                end
            elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
                k = string.upper(k)
                local left = string.sub(str, 1, pos)
                local right = string.sub(str, pos + 1)
                str = left .. k .. right
                pos = pos + 1
                if #right > 0 then
                    io.write(k .. right .. "\x1b[" .. #right .. "D")
                else
                    io.write(k)
                end
                io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- MISE A JOUR DE L'INTERFACE
-- =====================================================================
local function update_ui()
    io.write("\x1b7\x1b[s")
    io.write("\x1b[3;24r") 
    io.write("\x1b[1;1H\x1b[7m MICRO-BASIC TELETEL V4.0               [EXIT] OU [RETOUR] POUR QUITTER \x1b[K\x1b[0m")
    local count = 0
    for _ in pairs(program) do count = count + 1 end
    local fname = current_filename or "SANS NOM"
    local mod_star = is_modified and "*" or ""
    local status_text = string.format(" LIGNES : %03d | FICHIER : %s%s | TAPEZ 'HELP' ", count, fname, mod_star)
    status_text = string.sub(status_text, 1, 78)
    io.write("\x1b[2;1H\x1b[7m" .. status_text .. "\x1b[K\x1b[0m")
    io.write("\x1b8\x1b[u")
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
        local idx, len = 1, #content
        while idx <= len do
            local c = string.sub(content, idx, idx)
            if c == '"' then
                local end_idx = string.find(content, '"', idx + 1)
                if end_idx then
                    io.write(string.sub(content, idx + 1, end_idx - 1))
                    idx = end_idx + 1
                else
                    io.write(string.sub(content, idx + 1))
                    break
                end
            elseif c == ';' then idx = idx + 1
            elseif c ~= ' ' then
                local next_semi = string.find(content, ';', idx)
                local sub_expr = next_semi and string.sub(content, idx, next_semi - 1) or string.sub(content, idx)
                idx = next_semi or (len + 1)
                if string.match(sub_expr, "%S") then io.write(tostring(eval_expr(sub_expr))) end
            else idx = idx + 1 end
        end
        if not string.match(content, ";%s*$") then
            io.write("\r\n")
        end
        io.flush()
        return "OK"

    elseif cmd == "LET" then
        local v, val = string.match(rest, "^(%a+)%s*=%s*(.*)$")
        if not v then v, val = string.match(rest, "^(%a+)%s+EQ%s+(.*)$") end
        if v then vars[v] = eval_expr(val) else return "SYNTAX ERROR" end
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
        if target then return "GOTO", target else return "SYNTAX ERROR" end
        
    elseif cmd == "GOSUB" then
        local target = tonumber(eval_expr(rest))
        if target then return "GOSUB", target else return "SYNTAX ERROR" end
        
    elseif cmd == "RETURN" then return "RETURN"

    elseif cmd == "IF" then
        local cond, then_cmd, else_cmd = string.match(rest, "^(.-)%s+THEN%s+(.-)%s+ELSE%s+(.*)$")
        if not cond then cond, then_cmd = string.match(rest, "^(.-)%s+THEN%s+(.*)$") end
        if cond and then_cmd then
            if eval_expr(cond) ~= 0 then return execute_line(then_cmd)
            elseif else_cmd then return execute_line(else_cmd) end
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "FOR" then
        local v, start_expr, end_expr = string.match(rest, "^(%a+)%s*=%s*(.-)%s+TO%s+(.*)$")
        if not v then v, start_expr, end_expr = string.match(rest, "^(%a+)%s+EQ%s+(.-)%s+TO%s+(.*)$") end
        if v and start_expr and end_expr then
            vars[v] = eval_expr(start_expr)
            return "FOR", {var = v, limit = eval_expr(end_expr)}
        else return "SYNTAX ERROR" end

    elseif cmd == "NEXT" then
        local v = string.match(rest, "^(%a+)$")
        if v then return "NEXT", v else return "SYNTAX ERROR" end

    elseif cmd == "WHILE" then return "WHILE", eval_expr(rest) ~= 0
    elseif cmd == "WEND" then return "WEND"
    elseif cmd == "CLEAR" then
        program = {}; vars = {}; current_filename = nil; is_modified = false; return "OK"
    elseif cmd == "CLS" then
        io.write("\x1b[2J"); update_ui(); io.write("\x1b[3;1H"); io.flush(); return "OK"
    elseif cmd == "BEEP" then minitel.play_sound("hit"); return "OK"

    elseif cmd == "LOCATE" then
        local str_x, str_y = string.match(rest, "^(.-)%s*,%s*(.*)$")
        if str_x and str_y then
            local x = math.max(1, math.min(80, math.floor(eval_expr(str_x))))
            local y = math.max(3, math.min(24, math.floor(eval_expr(str_y))))
            io.write("\x1b[" .. y .. ";" .. x .. "H"); io.flush()
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "INVERT" then io.write("\x1b[7m"); io.flush(); return "OK"
    elseif cmd == "NORMAL" then io.write("\x1b[0m"); io.flush(); return "OK"
    elseif cmd == "PAUSE" then
        local sec = tonumber(eval_expr(rest))
        if sec then
            if sec < 0.1 then minitel.sleep(sec)
            else
                for i=1, math.floor(sec*10) do
                    local k = minitel.get_key()
                    if k == "RETOUR" or k == "ESC" then return "BREAK" end
                    minitel.sleep(0.1)
                end
            end
        else return "SYNTAX ERROR" end
        return "OK"
        
    elseif cmd == "END" then return "END"
    elseif cmd == "STOP" then return "STOP"
    elseif cmd == "REM" then return "OK" end

    local v, val = string.match(line, "^(%a+)%s*=%s*(.*)$")
    if not v then v, val = string.match(line, "^(%a+)%s+EQ%s+(.*)$") end
    if v then vars[v] = eval_expr(val); return "OK" end

    return "SYNTAX ERROR"
end

-- =====================================================================
-- BOUCLE D'EXECUTION GLOBALE
-- =====================================================================
local function run_program()
    local sorted_lines = {}
    for k in pairs(program) do table.insert(sorted_lines, k) end
    table.sort(sorted_lines)

    local pc = 1
    local loop_stack = {} 
    local gosub_stack = {}

    while pc <= #sorted_lines do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then
            io.write("\r\n\x1b[K\x1b[7m BREAK IN " .. sorted_lines[pc] .. " \x1b[0m\r\n"); io.flush(); break
        end

        local line_num = sorted_lines[pc]
        local stat, arg = execute_line(program[line_num])

        if stat == "BREAK" then
            io.write("\r\n\x1b[K\x1b[7m BREAK IN " .. line_num .. " \x1b[0m\r\n"); io.flush(); break
        elseif stat == "STOP" then
            io.write("\r\n\x1b[K\x1b[7m PROGRAM STOPPED AT LINE " .. line_num .. " \x1b[0m\r\n"); io.flush(); break
        elseif stat == "SYNTAX ERROR" then
            io.write("\r\n\x1b[K SYNTAX ERROR IN " .. line_num .. "\r\n"); io.flush(); break
        elseif stat == "END" then break
        elseif stat == "GOTO" or stat == "GOSUB" then
            local found = false
            for i, v in ipairs(sorted_lines) do
                if v == arg then
                    if stat == "GOSUB" then table.insert(gosub_stack, pc) end
                    pc = i; found = true; break
                end
            end
            if not found then io.write("\r\n\x1b[K UNDEFINED LINE " .. arg .. " IN " .. line_num .. "\r\n"); io.flush(); break end
        elseif stat == "RETURN" then
            if #gosub_stack > 0 then pc = table.remove(gosub_stack) + 1
            else io.write("\r\n\x1b[K RETURN WITHOUT GOSUB IN " .. line_num .. "\r\n"); io.flush(); break end
        elseif stat == "FOR" then
            table.insert(loop_stack, {type="FOR", var=arg.var, limit=arg.limit, start_pc=pc}); pc = pc + 1
        elseif stat == "NEXT" then
            local top = loop_stack[#loop_stack]
            if top and top.type == "FOR" and top.var == arg then
                vars[top.var] = vars[top.var] + 1
                if vars[top.var] <= top.limit then pc = top.start_pc + 1 else table.remove(loop_stack); pc = pc + 1 end
            else io.write("\r\n\x1b[K NEXT WITHOUT FOR IN " .. line_num .. "\r\n"); break end
        elseif stat == "WHILE" then
            if arg then table.insert(loop_stack, {type="WHILE", start_pc=pc}); pc = pc + 1
            else
                local nest = 1; local wend_pc = pc + 1; local found = false
                while wend_pc <= #sorted_lines do
                    local wline = string.match(string.upper(program[sorted_lines[wend_pc]]), "^%s*(.-)%s*$")
                    if string.match(wline, "^WHILE") then nest = nest + 1 end
                    if string.match(wline, "^WEND") then 
                        nest = nest - 1; if nest == 0 then found = true; break end
                    end
                    wend_pc = wend_pc + 1
                end
                if found then pc = wend_pc + 1 else io.write("\r\n\x1b[K WHILE WITHOUT WEND IN " .. line_num .. "\r\n"); break end
            end
        elseif stat == "WEND" then
            local top = loop_stack[#loop_stack]
            if top and top.type == "WHILE" then pc = top.start_pc; table.remove(loop_stack)
            else io.write("\r\n\x1b[K WEND WITHOUT WHILE IN " .. line_num .. "\r\n"); break end
        else pc = pc + 1 end
        minitel.sleep(0.005)
    end
end

-- =====================================================================
-- ECRAN D'AIDE (LE GUIDE COMPLET)
-- =====================================================================
local function show_help()
    io.write("\x1b[r\x1b[2J\x1b[H")
    local help_lines = {
        "\x1b[1m === SYSTEME ========================== \x1b[0m", 
        " RUN        : Execute le code        NEW/CLEAR  : Efface la memoire",
        " LIST       : Affiche le code        DIR        : Fichiers locaux", 
        " EDIT X     : Edite la ligne X       SAVE \"N\"   : Sauvegarde (ex: SAVE \"JEU\")", 
        " STOP / END : Arrete l'execution     LOAD \"N\"   : Charge un fichier",
        "",
        "\x1b[1m === INSTRUCTIONS ET VARIABLES ======== \x1b[0m", 
        " PRINT      : Affiche texte/var. (Ex: PRINT \"X=\" ; X)",
        "              (Terminer par ';' empeche le saut de ligne)",
        " INPUT X    : Met en pause et demande de taper une valeur", 
        " LET X = 5  : Assigne une valeur (ou juste X = 5)",
        " PAUSE X    : Met le programme en pause X secondes",
        " REM        : Ligne de commentaire (ignoree par le systeme)",
        "",
        "\x1b[1m === CONDITIONS ET BOUCLES ============ \x1b[0m", 
        " IF..THEN   : Ex: IF X >= 5 THEN PRINT \"GAGNE\" ELSE GOTO 10", 
        " Operateurs : = (ou EQ), <> (ou NEQ), < (LT), > (GT), <= (LE), >= (GE)",
        " Logique    : AND, OR, NOT",
        " GOTO X     : Saute directement a la ligne X",
        " GOSUB X    : Saute a la ligne X, et revient avec RETURN", 
        " FOR..NEXT  : Ex: FOR I=1 TO 5 (puis) NEXT I",
        " WHILE..WEND: Ex: WHILE X < 10 (puis) WEND",
        "",
        "\x1b[1m === ECRAN MINITEL ET CLAVIER ========= \x1b[0m", 
        " CLS        : Efface l'ecran et replace le curseur",
        " LOCATE X,Y : Place le curseur (Colonnes 1-80, Lignes 3-24)",
        " INVERT/NORM: Bascule en texte inverse (Noir sur Blanc)",
        " BEEP       : Emet un bip sonore",
        " MKEY()     : Lit la touche pressee SANS bloquer le programme.",
        "              (Haut:200, Bas:201, Gauche:202, Droite:203, Envoi:13)",
        "",
        "\x1b[1m === MATHEMATIQUES ==================== \x1b[0m", 
        " RND(X)     : Tire un nombre au hasard entre 1 et X",
        " SIN,COS,TAN: Trigonometrie classique (en radians)",
        " SQR(X)     : Racine carree      ABS(X) : Valeur absolue",
        " INT(X)     : Partie entiere     X MOD Y: Reste de division",
        " EXP(X)     : Exponentielle      LOG(X) : Logarithme",
        " PI         : 3.14159..."
    }

    local offset = 1; local max_visible = 20
    local max_offset = math.max(1, #help_lines - max_visible + 1)

    local function draw_help_screen()
        io.write("\x1b[1;1H\x1b[7m MICRO-BASIC : LE GUIDE COMPLET     [FLECHES] DEFILER  [RETOUR] QUITTER \x1b[K\x1b[0m\r\n")
        for i = 1, max_visible do
            local line_idx = offset + i - 1
            io.write("\x1b[" .. (i + 2) .. ";1H\x1b[K")
            if help_lines[line_idx] then io.write(" " .. help_lines[line_idx]) end
        end
        io.write("\x1b[24;1H\x1b[7m APPUYEZ SUR [RETOUR] POUR FERMER \x1b[K\x1b[0m")
        io.flush()
    end

    draw_help_screen()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == " " or k == "ENVOI" or k == "\r" or k == "\n" then break
        elseif k == "UP" or k == "Z" or k == "z" then if offset > 1 then offset = offset - 1; draw_help_screen() end
        elseif k == "DOWN" or k == "S" or k == "s" then if offset < max_offset then offset = offset + 1; draw_help_screen() end
        end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- INVITE DE COMMANDE SHELL
-- =====================================================================
local function shell()
    io.write("\x1b[2J\x1b[H\x1b[3;24r\x1b[3;1H")
    io.write("\x1b[7m INITIALISATION DU SYSTEME \x1b[0m\r\nREADY.\r\n")
    io.flush()

    while true do
        update_ui()
        local line = input_string("\x1b[K> ")

        if line == "ABORT" then io.write("\r\n")
        elseif line == "" then -- Rien
        elseif line == "HELP" then show_help(); io.write("\x1b[2J\x1b[3;24r\x1b[3;1HREADY.\r\n"); io.flush()
        elseif line == "EXIT" or line == "QUIT" then break
        elseif string.match(line, "^EDIT%s+(%d+)") then
            local lnum = tonumber(string.match(line, "^EDIT%s+(%d+)"))
            if program[lnum] then
                local edited = input_string("\x1b[K" .. lnum .. " ", program[lnum])
                if edited ~= "ABORT" and edited ~= "" then
                    program[lnum] = edited; is_modified = true
                elseif edited == "" then
                    program[lnum] = nil; is_modified = true
                end
            else io.write("LINE NOT FOUND\r\n"); io.flush() end
        elseif string.match(line, "^LIST") then
            local sorted_lines = {}
            for k in pairs(program) do table.insert(sorted_lines, k) end
            table.sort(sorted_lines)
            for _, l in ipairs(sorted_lines) do io.write(string.format("\x1b[1m%d\x1b[0m %s\r\n", l, program[l])) end
            io.flush()
        elseif line == "RUN" then io.write("\x1b[3;24r"); run_program(); io.write("\x1b[KREADY.\r\n"); io.flush()
        elseif line == "NEW" or line == "CLEAR" then
            program = {}; vars = {}; current_filename = nil; is_modified = false; io.write("READY.\r\n"); io.flush()
        elseif line == "DIR" then
            local f = io.popen("ls -1 utils/prog_basic/*.bas 2>/dev/null")
            if f then for file in f:lines() do io.write(string.gsub(file, "utils/prog_basic/", "") .. "\r\n") end; f:close() end
            io.write("READY.\r\n"); io.flush()
        elseif string.match(line, '^SAVE%s+"(.-)"') then
            local filename = string.match(line, '^SAVE%s+"(.-)"')
            local f = io.open("utils/prog_basic/" .. filename .. ".bas", "w")
            if f then
                local sl = {}
                for k in pairs(program) do table.insert(sl, k) end
                table.sort(sl)
                for _, l in ipairs(sl) do f:write(l .. " " .. program[l] .. "\n") end
                f:close(); current_filename = filename; is_modified = false; io.write("SAVED " .. filename .. "\r\n")
            end
            io.flush()
        elseif string.match(line, '^LOAD%s+"(.-)"') then
            local filename = string.match(line, '^LOAD%s+"(.-)"')
            local f = io.open("utils/prog_basic/" .. filename .. ".bas", "r")
            if f then
                program = {}; vars = {}
                for fline in f:lines() do
                    local lnum, rest = string.match(fline, "^(%d+)%s*(.*)$")
                    if lnum then program[tonumber(lnum)] = rest end
                end
                f:close(); current_filename = filename; is_modified = false; io.write("LOADED " .. filename .. "\r\n")
            end
            io.flush()
        else
            local lnum, rest = string.match(line, "^(%d+)%s*(.*)$")
            if lnum then
                lnum = tonumber(lnum)
                if rest == "" then program[lnum] = nil; is_modified = true
                else program[lnum] = rest; is_modified = true end
            else
                local stat, _ = execute_line(line)
                if stat == "SYNTAX ERROR" then io.write("SYNTAX ERROR\r\n"); io.flush() end
            end
        end
    end
end

math.randomseed(os.time())
shell()
io.write("\x1b[r")
io.flush()
minitel.cleanup()