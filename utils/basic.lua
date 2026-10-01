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
local function replace_word_op(expr, word, op)
    return string.gsub(expr, "%f[%a]" .. word .. "%f[%A]", op)
end

local function eval_expr(expr)
    local e = expr
    
    e = replace_word_op(e, "EQ", "==")
    e = replace_word_op(e, "NEQ", "~=")
    e = replace_word_op(e, "LT", "<")
    e = replace_word_op(e, "GT", ">")
    e = replace_word_op(e, "LE", "<=")
    e = replace_word_op(e, "GE", ">=")
    e = replace_word_op(e, "PLUS", "+")
    e = replace_word_op(e, "MINUS", "-")
    e = replace_word_op(e, "MUL", "*")
    e = replace_word_op(e, "DIV", "/")
    
    e = string.gsub(e, "=", "==")
    e = string.gsub(e, "<==", "<=")
    e = string.gsub(e, ">==", ">=")
    e = string.gsub(e, "<>", "~=")
    
    e = string.gsub(e, "%a+", function(w)
        if w == "RND" or w == "MKEY" or w == "AND" or w == "OR" or w == "NOT" then 
            return string.lower(w) 
        end
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
-- LECTURE DU CLAVIER
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
-- MOTEUR D'EXECUTION DES LIGNES
-- =====================================================================
local function execute_line(line)
    line = string.match(line, "^%s*(.-)%s*$")
    if line == "" then return "OK" end
    
    local cmd, rest = string.match(line, "^(%a+)%s*(.*)$")
    
    if cmd == "PRINT" then
        if string.sub(rest, 1, 1) == '"' then
            local str, after = string.match(rest, '^"(.-)"%s*;?%s*(.*)$')
            io.write(str or "")
            if after and after ~= "" then
                io.write(tostring(eval_expr(after)))
            end
            io.write("\r\n") io.flush()
        else
            io.write(tostring(eval_expr(rest)) .. "\r\n") io.flush()
        end
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
            vars[v] = tonumber(res) or 0
        else return "SYNTAX ERROR" end
        return "OK"
        
    elseif cmd == "GOTO" then
        local target = tonumber(eval_expr(rest))
        if target then return "GOTO", target else return "SYNTAX ERROR" end
        
    elseif cmd == "IF" then
        local cond, then_cmd = string.match(rest, "^(.-)%s+THEN%s+(.*)$")
        if cond and then_cmd then
            local cond_val = eval_expr(cond)
            if cond_val ~= 0 then return execute_line(then_cmd) end
        else return "SYNTAX ERROR" end
        return "OK"
        
    elseif cmd == "CLS" then
        io.write("\x1b[2J\x1b[2;1H") io.flush() return "OK"
        
    elseif cmd == "BEEP" then
        minitel.play_sound("hit") return "OK"
        
    elseif cmd == "LOCATE" then
        -- Correction: Utilisation de eval_expr pour gérer les variables au lieu de demander des chiffres (%d)
        local str_x, str_y = string.match(rest, "^(.-)%s*,%s*(.*)$")
        if str_x and str_y then
            local x = math.floor(eval_expr(str_x))
            local y = math.floor(eval_expr(str_y))
            -- Protection: empécher le curseur de sortir de l'écran (VT100 n'aime pas le 0 ou l'overflow)
            x = math.max(1, math.min(80, x))
            y = math.max(1, math.min(24, y))
            io.write("\x1b["..y..";"..x.."H") io.flush()
        else return "SYNTAX ERROR" end
        return "OK"
        
    elseif cmd == "INVERT" then
        io.write("\x1b[7m") io.flush() return "OK"
        
    elseif cmd == "NORMAL" then
        io.write("\x1b[0m") io.flush() return "OK"
        
    elseif cmd == "PAUSE" then
        local sec = tonumber(eval_expr(rest))
        if sec then minitel.sleep(sec) else return "SYNTAX ERROR" end
        return "OK"
        
    elseif cmd == "END" then return "END"
    elseif cmd == "REM" then return "OK"
    end
    
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
            io.write("\r\nBREAK IN " .. sorted_lines[pc] .. "\r\n") io.flush()
            break
        end
        
        local line_num = sorted_lines[pc]
        local line_str = program[line_num]
        
        local stat, arg = execute_line(line_str)
        
        if stat == "SYNTAX ERROR" then
            io.write("SYNTAX ERROR IN " .. line_num .. "\r\n") io.flush()
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
                io.write("UNDEFINED LINE " .. arg .. " IN " .. line_num .. "\r\n") io.flush()
                break
            end
        else
            pc = pc + 1
        end
        minitel.sleep(0.005) 
    end
end

-- =====================================================================
-- ECRAN D'AIDE
-- =====================================================================
local function show_help()
    io.write("\x1b[r") 
    io.write("\x1b[2J\x1b[H")
    
    io.write("\x1b[1;1H\x1b[7m MICRO-BASIC : MANUEL DE REFERENCE                  [RETOUR] POUR QUITTER \x1b[K\x1b[0m\r\n")
    
    io.write("\r\n\x1b[1m COMMANDES SYSTEME \x1b[0m\r\n")
    io.write(" RUN        : Execute le code en memoire\r\n")
    io.write(" LIST       : Affiche tout le code\r\n")
    io.write(" LIST 10    : Affiche la ligne 10\r\n")
    io.write(" LIST 10-50 : Affiche les lignes 10 a 50\r\n")
    io.write(" NEW        : Efface la memoire\r\n")
    io.write(" DIR        : Liste les fichiers locaux\r\n")
    io.write(" SAVE       : Ex: SAVE \"NOM\" (sans .bas)\r\n")
    io.write(" LOAD       : Ex: LOAD \"NOM\"\r\n")
    io.write(" EXIT       : Quitter l'interpreteur\r\n")
    
    io.write("\r\n\x1b[1m INSTRUCTIONS DU LANGAGE \x1b[0m\r\n")
    io.write(" PRINT \"X\"  : Affiche du texte\r\n")
    io.write(" INPUT X    : Demande une valeur\r\n")
    io.write(" LET X EQ 5 : Assigner (ou X = 5)\r\n")
    io.write(" IF..THEN   : Condition\r\n")
    io.write(" GOTO X     : Saute a la ligne X\r\n")
    io.write(" PAUSE X    : Pause de X secondes\r\n")
    
    io.write("\r\n\x1b[1m FONCTIONS MINITEL \x1b[0m\r\n")
    io.write(" CLS / BEEP / INVERT / NORMAL\r\n")
    io.write(" LOCATE X,Y : Place le curseur en X, Y (ex: LOCATE X PLUS 1, Y)\r\n")
    io.write(" MKEY()     : Lecture clavier en direct\r\n")
    
    io.write("\x1b[24;1H\x1b[7m APPUYEZ SUR [RETOUR] OU [ESPACE] POUR FERMER \x1b[K\x1b[0m")
    io.flush()
    
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == " " or k == "ENVOI" or k == "\r" or k == "\n" then
            break
        end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- MISE A JOUR DE L'INTERFACE
-- =====================================================================
local function update_ui()
    io.write("\x1b7")
    
    io.write("\x1b[1;1H\x1b[7m MICRO-BASIC TELETEL V1.6               [EXIT] OU [RETOUR] POUR QUITTER \x1b[K\x1b[0m")
    
    local count = 0
    for _ in pairs(program) do count = count + 1 end
    
    local fname = current_filename or "SANS NOM"
    local mod_star = is_modified and "*" or ""
    
    local status_text = string.format(" LIGNES : %03d | FICHIER : %s%s | TAPEZ 'HELP' ", count, fname, mod_star)
    io.write("\x1b[24;1H\x1b[7m" .. status_text .. "\x1b[K\x1b[0m")
    
    io.write("\x1b8")
    io.flush()
end

-- =====================================================================
-- INVITE DE COMMANDE
-- =====================================================================
local function shell()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;23r") 
    io.write("\x1b[2;1H")
    
    io.write("\x1b[7m INITIALISATION DU SYSTEME \x1b[0m\r\n")
    io.write("READY.\r\n")
    io.flush()
    
    while true do
        update_ui()
        local line = input_string("> ")
        
        if line == "" then
            -- Ne rien faire
        elseif line == "HELP" then
            show_help()
            io.write("\x1b[2;23r\x1b[2J\x1b[2;1H") 
            io.write("READY.\r\n") io.flush()
        elseif line == "EXIT" or line == "QUIT" then
            break
            
        elseif string.match(line, "^LIST") then
            local param = string.match(line, "^LIST%s*(.*)$")
            local start_l, end_l
            
            if param ~= "" then
                local n1, n2 = string.match(param, "^(%d+)%s*[-]%s*(%d+)$")
                if n1 and n2 then
                    start_l, end_l = tonumber(n1), tonumber(n2)
                else
                    local n1_start = string.match(param, "^(%d+)%s*[-]$")
                    if n1_start then
                        start_l = tonumber(n1_start)
                    else
                        local n1_only = string.match(param, "^(%d+)$")
                        if n1_only then
                            start_l, end_l = tonumber(n1_only), tonumber(n1_only)
                        end
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
            
            if not found and param ~= "" then
                io.write("LINE NOT FOUND\r\n")
            end
            io.flush()
            
        elseif line == "RUN" then
            run_program()
            io.write("READY.\r\n") io.flush()
        elseif line == "NEW" then
            program = {}
            vars = {}
            current_filename = nil
            is_modified = false
            io.write("READY.\r\n") io.flush()
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
            io.write("READY.\r\n") io.flush()
            
        elseif string.match(line, '^SAVE%s+"(.-)"') then
            local filename = string.match(line, '^SAVE%s+"(.-)"')
            if filename then
                local f = io.open("utils/prog_basic/" .. filename .. ".bas", "w")
                if f then
                    local sorted_lines = {}
                    for k in pairs(program) do table.insert(sorted_lines, k) end
                    table.sort(sorted_lines)
                    for _, l in ipairs(sorted_lines) do
                        f:write(l .. " " .. program[l] .. "\n")
                    end
                    f:close()
                    current_filename = filename
                    is_modified = false
                    io.write("SAVED " .. filename .. "\r\n")
                else
                    io.write("FILE ERROR\r\n")
                end
            end
            io.write("READY.\r\n") io.flush()
            
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
                else
                    io.write("FILE NOT FOUND\r\n")
                end
            end
            io.write("READY.\r\n") io.flush()
            
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
                    io.write("SYNTAX ERROR\r\n") io.flush()
                elseif stat == "GOTO" then
                    io.write("CANNOT GOTO IN IMMEDIATE MODE\r\n") io.flush()
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