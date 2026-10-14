os.execute("stty -F /dev/ttyUSB0 raw -echo min 1 time 0")
io.write("\x1b[2J\x1b[H")
io.write("--- DIAGNOSTIC CLAVIER MINITEL V2 ---\r\n")
io.write("Appuyez sur TOUTES vos touches speciales.\r\n")
io.write("Appuyez sur [ESPACE] pour quitter.\r\n\r\n")
io.flush()

while true do
    local c = io.read(1)
    if c then
        local byte = string.byte(c)
        
        -- Si c'est une lettre ou un chiffre, on l'affiche, sinon on met un "?"
        local char_disp = "?"
        if string.match(c, "%w") then char_disp = c end
        
        io.write("Code: " .. string.format("%03d", byte) .. " (Hex: " .. string.format("%02X", byte) .. ") -> " .. char_disp .. "\r\n")
        io.flush()
        
        -- 32 est le code universel de la barre ESPACE
        if byte == 32 then 
            break
        end
    end
end

os.execute("stty -F /dev/ttyUSB0 sane")