local minitel = require("minitel")
minitel.init()

local function input_string(prompt)
    io.write(prompt)
    io.flush()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then return "EXIT" end
            if k == "ENVOI" or k == "\n" or k == "\r" then
                return str
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D") io.flush()
                end
            elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
                str = str .. k
                io.write(k) io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

-- Evalue une expression mathématique sous forme de chaîne ("2+2")
local function eval_math(expr)
    local func = load("return " .. expr)
    if func then
        local ok, val = pcall(func)
        if ok and type(val) == "number" then return val end
    end
    return "ERREUR DE SYNTAXE"
end

local history = {}

local function draw_ui()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;4H========================================================================\r\n")
    io.write("\x1b[3;4H| \x1b[7m                    3 6 1 5   C O M P T A B I L I T E                  \x1b[0m|\r\n")
    io.write("\x1b[4;4H========================================================================\r\n")
    io.write("\x1b[5;4H| [1] CALCULATRICE LIBRE (ex: 2.5 * 10)                                |\r\n")
    io.write("\x1b[6;4H| [2] CONVERTISSEUR FRANCS -> EUROS                                    |\r\n")
    io.write("\x1b[7;4H| [3] CONVERTISSEUR EUROS -> FRANCS                                    |\r\n")
    io.write("\x1b[8;4H========================================================================\r\n")
    
    io.write("\x1b[10;4H\x1b[1mHISTORIQUE DES OPERATIONS :\x1b[0m\r\n")
    for i, line in ipairs(history) do
        io.write("    " .. line .. "\r\n")
    end
    
    io.write("\x1b[22;4H========================================================================\r\n")
    io.write("\x1b[23;4H  CHOIX (1-3) OU [RETOUR] POUR QUITTER : ")
    io.flush()
end

while true do
    draw_ui()
    local choice = input_string("")
    
    if choice == "EXIT" then break end
    
    if choice == "1" then
        io.write("\x1b[24;4H\x1b[K  > OPERATION : ") io.flush()
        local calc = input_string("")
        if calc ~= "EXIT" and calc ~= "" then
            local res = eval_math(calc)
            table.insert(history, calc .. " = " .. res)
        end
    elseif choice == "2" then
        io.write("\x1b[24;4H\x1b[K  > SOMME EN FRANCS : ") io.flush()
        local val = tonumber((input_string("")))
        if val then
            local res = val / 6.55957
            table.insert(history, val .. " FRF = " .. string.format("%.2f", res) .. " EUR")
        end
    elseif choice == "3" then
        io.write("\x1b[24;4H\x1b[K  > SOMME EN EUROS : ") io.flush()
        local val = tonumber((input_string("")))
        if val then
            local res = val * 6.55957
            table.insert(history, val .. " EUR = " .. string.format("%.2f", res) .. " FRF")
        end
    end
    
    -- Garde seulement les 8 dernières lignes d'historique pour ne pas déborder
    if #history > 8 then table.remove(history, 1) end
end

minitel.cleanup()