local minitel = require("minitel")
minitel.init()

local grid = {
    {0,0,0,0,0,0,0,0}, -- Aigu (Hi-hat)
    {0,0,0,0,0,0,0,0}, -- Bruit (Caisse claire)
    {0,0,0,0,0,0,0,0}  -- Grave (Grosse caisse)
}

local cx, cy = 1, 1
local playing = false
local current_step = 1
local last_step_time = 0
local tempo = 0.25 -- Vitesse de lecture (secondes par pas)

local function draw_interface()
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;11H\x1b[7m==========================================================\x1b[0m\r\n")
    io.write("\x1b[3;11H\x1b[7m|                  3 6 1 5   M A E S T R O               |\x1b[0m\r\n")
    io.write("\x1b[4;11H\x1b[7m==========================================================\x1b[0m\r\n\r\n")
    io.write("           [ESPACE] COCHER/DECOCHER  |  [ENVOI] LECTURE/PAUSE\r\n\r\n")
end

local function draw_grid()
    local tracks = {"[1] AIGU (Hi-hat) ", "[2] BRUIT (Snare) ", "[3] GRAVE (Kick)  "}
    
    -- Ligne d'indication de lecture
    io.write("\x1b[9;23H")
    for x = 1, 8 do
        if playing and x == current_step then
            io.write("\x1b[7m  v  \x1b[0m ")
        else
            io.write("  .   ")
        end
    end
    
    -- Affichage des pistes
    for y = 1, 3 do
        io.write("\x1b[" .. (9 + y) .. ";4H" .. tracks[y])
        for x = 1, 8 do
            local cell = (grid[y][x] == 1) and " (O) " or "  -  "
            if x == cx and y == cy then
                io.write("\x1b[7m" .. cell .. "\x1b[0m ")
            else
                io.write(cell .. " ")
            end
        end
    end
    
    io.write("\x1b[16;4HETAT : " .. (playing and "\x1b[7m EN LECTURE \x1b[0m" or "EN PAUSE   "))
    io.flush()
end

draw_interface()
draw_grid()

while true do
    local key = minitel.get_key()
    local now = os.clock()
    
    if key then
        if key == "RETOUR" or key == "ESC" then break end
        if key == "RIGHT" or key == "d" or key == "D" then cx = cx + 1; if cx > 8 then cx = 1 end end
        if key == "LEFT" or key == "q" or key == "Q" then cx = cx - 1; if cx < 1 then cx = 8 end end
        if key == "DOWN" or key == "s" or key == "S" then cy = cy + 1; if cy > 3 then cy = 1 end end
        if key == "UP" or key == "z" or key == "Z" then cy = cy - 1; if cy < 1 then cy = 3 end end
        
        if key == " " then
            grid[cy][cx] = 1 - grid[cy][cx] -- Inverse (0 devient 1, 1 devient 0)
        end
        
        if key == "ENVOI" or key == "\r" or key == "\n" then
            playing = not playing
            if playing then last_step_time = now - tempo end -- Force le démarrage immédiat
        end
        draw_grid()
    end
    
    if playing and (now - last_step_time >= tempo) then
        last_step_time = now
        
        -- Déclenchement des sons en tâche de fond pour ne pas bloquer
        if grid[1][current_step] == 1 then os.execute("play -q -n synth 0.05 square 6000 >/dev/null 2>&1 &") end
        if grid[2][current_step] == 1 then os.execute("play -q -n synth 0.05 noise >/dev/null 2>&1 &") end
        if grid[3][current_step] == 1 then os.execute("play -q -n synth 0.1 sine 80-30 >/dev/null 2>&1 &") end
        
        draw_grid()
        
        current_step = current_step + 1
        if current_step > 8 then current_step = 1 end
    end
    
    minitel.sleep(0.01)
end

minitel.cleanup()