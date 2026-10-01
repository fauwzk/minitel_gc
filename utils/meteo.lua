local minitel = require("minitel")
minitel.init()

local function input_string(prompt)
    io.write(prompt)
    io.flush()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                return str
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D") io.flush()
                end
            elseif string.match(k, "^[%w%s%-]$") and #k == 1 then
                str = str .. k
                io.write(k) io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

while true do
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;11H==========================================================\r\n")
    io.write("\x1b[3;11H|                  \x1b[1m 3 6 1 5   M E T E O \x1b[0m                 |\r\n")
    io.write("\x1b[4;11H==========================================================\r\n\r\n")
    
    io.write("  Veuillez saisir votre ville (ou laissez vide pour detection auto)\r\n")
    io.write("  [RETOUR] pour quitter.\r\n\r\n")
    
    local city = input_string("  > VILLE : ")
    
    if city == "" then city = "" else city = string.gsub(city, " ", "%%20") end
    
    -- Le Minitel ne peut pas envoyer "RETOUR" dans le input_string, on permet de taper "EXIT"
    if string.upper(city) == "EXIT" or string.upper(city) == "QUIT" then break end
    
    io.write("\r\n\x1b[7m INTERROGATION DU SATELLITE... \x1b[0m\r\n")
    io.flush()
    
    -- ?0 = Aujourd'hui seulement. T = Pas de couleurs ANSI (qui bugueraient sur Minitel)
    local cmd = "curl -s -m 5 'wttr.in/" .. city .. "?0T' 2>/dev/null"
    local f = io.popen(cmd)
    
    if f then
        local result = f:read("*a")
        f:close()
        
        io.write("\x1b[2J\x1b[H")
        io.write("\x1b[1;1H\x1b[1mBULLETIN METEOROLOGIQUE :\x1b[0m\r\n\r\n")
        -- On décale un peu le texte pour qu'il soit centré sur les 80 colonnes
        for line in string.gmatch(result, "[^\r\n]+") do
            io.write("      " .. line .. "\r\n")
        end
        io.write("\r\n\x1b[7m APPUYEZ SUR UNE TOUCHE POUR CONTINUER \x1b[0m")
        io.flush()
        
        -- Attente d'une touche
        while not minitel.get_key() do minitel.sleep(0.05) end
    else
        io.write("\r\nERREUR RESEAU.\r\n")
        minitel.sleep(2)
    end
end

minitel.cleanup()