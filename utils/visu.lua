-- =====================================================================
-- INITIALISATION DU TERMINAL MINITEL
-- =====================================================================
local function init_terminal()
    os.execute("stty -F /dev/ttyUSB0 raw -echo -icanon min 0 time 0")
    io.write("\x1b[?3h\x1b(B\x1b9{C\x1b[2J\x1b[?25l")
    io.flush()
end

init_terminal()
os.execute("mkdir -p images") -- S'assure que le dossier existe

-- =====================================================================
-- MOTEUR DE DETECTION DES IMAGES
-- =====================================================================
local function scan_images()
    local list = {}
    -- Liste les fichiers JPG, JPEG, PNG en ignorant les erreurs
    local f = io.popen("ls -1 images/*.jpg images/*.jpeg images/*.png 2>/dev/null")
    if f then
        for file in f:lines() do
            local name = string.match(file, "images/(.+)")
            if name then
                table.insert(list, { filepath = file, display = string.upper(name) })
            end
        end
        f:close()
    end
    
    if #list == 0 then
        table.insert(list, { filepath = nil, display = "AUCUNE IMAGE DANS /images" })
    end
    return list
end

local images = scan_images()
local cursor = 1
local offset = 0
local page_size = 12 

-- =====================================================================
-- FONCTIONS UTILITAIRES ET MOTEUR DE LECTURE
-- =====================================================================
-- =====================================================================
-- PILOTE DE CLAVIER MINITEL UNIVERSEL (Vidéotex + VT100)
-- =====================================================================
local function get_key()
    local c = io.read(1)
    if not c then return nil end
    
    -- Remplacement de os.clock() par une boucle matérielle très rapide
    -- pour éviter que les Raspberry Pi ne ratent la fin de la séquence
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

        -- VOS TOUCHES MINITEL DEDUITES DU DIAGNOSTIC
        if full_seq == "OR" then return "RETOUR" end
        if full_seq == "On" then return "SUITE" end
        if full_seq == "Ol" then return "CORRECTION" end
        if full_seq == "OQ" then return "ANNULATION" end
        
        -- Touche Envoi (généralement OM)
        if full_seq == "OM" then return "ENVOI" end

        return "UNKNOWN_ESC"
    end
    
    return c
end

local function sleep(seconds)
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do end
end

local function play_blip()
    io.write("\x07") io.flush()
end

-- =====================================================================
-- INTERFACE DU MENU
-- =====================================================================
local function draw_menu_static()
    io.write("\x1b[2J\x1b[H") 
    io.flush()
    sleep(0.08)
    
    io.write("\x1b[2;11H==========================================================\r\n")
    io.write("\x1b[3;11H|            \x1b[7m GALERIE VIDEOTEX - 3615 IMG \x1b[0m               |\r\n")
    io.write("\x1b[4;11H|========================================================|\r\n")
    io.write("\x1b[5;11H| DOSSIER SOURCE : /images                               |\r\n")
    io.write("\x1b[6;11H==========================================================\r\n")
    
    io.write("\x1b[21;11H==========================================================\r\n")
    io.write("\x1b[23;14H ZQSD / FLECHES : NAVIGUER  |  ESPACE / ENTREE : VOIR \r\n")
    io.flush()
end

local function draw_list()
    for i = 1, page_size do
        local line_y = 7 + i
        local img_idx = offset + i
        local img = images[img_idx]
        
        io.write("\x1b[" .. line_y .. ";11H\x1b[K") 
        
        if img then
            local display_name = img.display
            if string.len(display_name) > 30 then
                display_name = string.sub(display_name, 1, 27) .. "..."
            end
            
            if img_idx == cursor then
                io.write("\x1b[" .. line_y .. ";22H\x1b[7m > " .. display_name .. " \x1b[0m")
            else
                io.write("\x1b[" .. line_y .. ";22H   " .. display_name .. "   ")
            end
        end
    end
    io.write("\x1b[8;65H\x1b[K " .. cursor .. " / " .. #images)
    io.flush()
end

local function update_cursor_logic(dir)
    cursor = cursor + dir
    if cursor < 1 then cursor = #images end
    if cursor > #images then cursor = 1 end
    
    if cursor <= offset then offset = cursor - 1 end
    if cursor > offset + page_size then offset = cursor - page_size end
end

-- =====================================================================
-- MOTEUR DE CONVERSION ET D'AFFICHAGE D'IMAGE A LA VOLEE
-- =====================================================================
local ascii_palette_normal = {" ", ".", ",", "-", "~", ":", ";", "=", "!", "*", "#", "$", "@"}
local ascii_palette_invert = {"@", "$", "#", "*", "!", "=", ";", ":", "~", "-", ",", ".", " "}

local function render_image(raw_data, invert)
    local palette = invert and ascii_palette_invert or ascii_palette_normal
    local p_len = #palette
    
    local screen_buffer = ""
    
    -- L'image fait 80x22 pixels.
    for y = 0, 21 do
        local line = ""
        for x = 1, 80 do
            local byte_idx = y * 80 + x
            if byte_idx <= #raw_data then
                local gray_val = string.byte(raw_data, byte_idx)
                local p_idx = math.floor((gray_val / 255) * (p_len - 1)) + 1
                line = line .. palette[p_idx]
            else
                line = line .. " "
            end
        end
        screen_buffer = screen_buffer .. "\x1b[" .. (y+1) .. ";1H" .. line
    end
    
    io.write(screen_buffer)
    io.flush()
end

local function view_image(img_node)
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[12;28H\x1b[7m TRAITEMENT EN COURS... \x1b[0m")
    io.flush()
    
    -- ====================================================================
    -- LA MODIFICATION EST ICI :
    -- On demande à ImageMagick de conserver les proportions (-resize 80x22)
    -- de centrer l'image (-gravity center) et de combler le vide avec 
    -- du noir (-background black -extent 80x22). Le noir se transformera 
    -- en espaces vides sur le minitel.
    -- ====================================================================
    local cmd = string.format("convert %q -resize 80x22 -gravity center -background black -extent 80x22 -colorspace gray -depth 8 gray:- 2>/dev/null", img_node.filepath)
    local f = io.popen(cmd, "r")
    
    if not f then
        io.write("\x1b[12;20H\x1b[7m ERREUR: IMAGEMAGICK INTROUVABLE \x1b[0m")
        io.flush()
        sleep(2)
        return
    end
    
    local raw_data = f:read("*a")
    f:close()
    
    if #raw_data == 0 then
        io.write("\x1b[12;20H\x1b[7m ERREUR: IMPOSSIBLE DE LIRE L'IMAGE \x1b[0m")
        io.flush()
        sleep(2)
        return
    end
    
    local invert_colors = false
    play_blip()
    
    while true do
        render_image(raw_data, invert_colors)
        
        local hud = "\x1b[24;1H\x1b[K\x1b[7m FICHIER: " .. img_node.display .. " \x1b[0m  |  [I] INVERSER COULEURS  |  [P] RETOUR MENU "
        io.write(hud)
        io.flush()
        
        local k = get_key()
        if k == "p" or k == "P" or k == "ESC" then
            break
        elseif k == "i" or k == "I" then
            invert_colors = not invert_colors
            play_blip()
        end
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE DU PROGRAMME
-- =====================================================================
draw_menu_static()
draw_list()

while true do
    local key = get_key()
    
    if key == "r" or key == "R" then
        images = scan_images()
        cursor = 1
        offset = 0
        draw_list()
    elseif key == "z" or key == "Z" or key == "UP" then
        update_cursor_logic(-1)
        draw_list()
    elseif key == "s" or key == "S" or key == "DOWN" then
        update_cursor_logic(1)
        draw_list()
    elseif key == " " or key == "\n" or key == "\r" then
        local selected = images[cursor]
        if selected and selected.filepath then
            view_image(selected)
            init_terminal()
            draw_menu_static()
            draw_list()
        end
    elseif key == "p" or key == "P" then
        break 
    end
    sleep(0.02)
end

-- NETTOYAGE A LA FERMETURE 
io.write("\x1b[?25h\x1b[2J\x1b[H") 
io.flush()
os.execute("stty -F /dev/ttyUSB0 sane")
