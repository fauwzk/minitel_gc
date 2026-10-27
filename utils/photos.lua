-- Fichier : utils/photos.lua
-- 3615 PHOTOS : visionneuse de photos en caracteres. ImageMagick reduit la
-- photo a la grille de l'ecran, en niveaux de gris ; chaque case devient un
-- caractere plus ou moins "plein", en video normale ou inverse, avec une
-- diffusion d'erreur pour les demi-teintes.
-- @TYPE: IMAGES / PHOTOS
-- @DESC: Vos photos JPEG et PNG (dossier photos/ ou cle USB) affichees en caracteres sur le Minitel, avec diaporama.
-- @ART1:     .:++##%%##++:.
-- @ART2:    :+#%%@@@@@@%%#+:
-- @ART3:    .:+##%@@@@%##+:.
-- @ART4:      .:++####++:.
-- @ART5:     3615 PHOTOS  [JPG]

local minitel = require("minitel")
minitel.init()

local PHOTO_DIR = "photos"
local VIEW_X, VIEW_Y, VIEW_W, VIEW_H = 2, 2, 78, 21
local SLIDE_DELAY = 12

-- Niveaux de luminosite, du noir au blanc : caractere, video inverse, et
-- part de la case allumee a l'ecran (estimee)
local LEVELS = {
    { " ", false, 0.00 }, { ".", false, 0.07 }, { ":", false, 0.14 }, { "+", false, 0.24 },
    { "*", false, 0.32 }, { "#", false, 0.45 },
    { "#", true, 0.56 }, { "+", true, 0.76 }, { ":", true, 0.86 }, { ".", true, 0.93 }, { " ", true, 1.00 },
}

local MODES = { "NORMAL", "CONTRASTE", "NEGATIF" }

-- =====================================================================
-- FICHIERS ET IMAGEMAGICK
-- =====================================================================
local function sh_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function have(cmd)
    return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == true
end

local IM = have("magick") and "magick" or (have("convert") and "convert" or nil)

-- Photos du dossier photos/ et des cles USB montees dans /media
local function scan_photos()
    os.execute("mkdir -p " .. PHOTO_DIR)
    local list = {}
    local cmd = "find " .. PHOTO_DIR .. " /media -maxdepth 4 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png'"
        .. " -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \\) -printf '%s\\t%p\\n' 2>/dev/null | sort -t '\t' -k2"
    local p = io.popen(cmd)
    if p then
        for l in p:lines() do
            local size, path = l:match("^(%d+)\t(.+)$")
            if path then
                local name = path:match("([^/]+)$")
                local where = path:find("^/media/") and "USB" or "PHOTOS"
                list[#list + 1] = { path = path, name = minitel.clean_accents(name), size = tonumber(size), where = where }
            end
        end
        p:close()
    end
    return list
end

local function human_size(n)
    if n >= 1048576 then return string.format("%.1f MO", n / 1048576) end
    return string.format("%d KO", math.max(1, n // 1024))
end

-- Rend largeur, hauteur et les niveaux de gris (0-255) ligne par ligne,
-- reduits pour tenir dans la vue (une case fait deux pixels de haut)
local function load_gray(path, mode)
    local extra = ""
    if mode == "CONTRASTE" then extra = " -auto-level -sigmoidal-contrast 4x50%" end
    if mode == "NEGATIF" then extra = " -negate" end
    local cmd = string.format("%s %s -auto-orient -colorspace Gray -resize %dx%d -resize 100%%x50%%%s -depth 8 pgm:- 2>/dev/null",
        IM, sh_quote(path .. "[0]"), VIEW_W, VIEW_H * 2, extra)
    local p = io.popen(cmd)
    if not p then return nil end
    local data = p:read("*a")
    p:close()
    local w, h, maxv, start = data:match("^P5%s+(%d+)%s+(%d+)%s+(%d+)%s()")
    if not w then return nil end
    w, h = tonumber(w), tonumber(h)
    local px = {}
    for y = 1, h do
        local row = {}
        local base = start + (y - 1) * w
        for x = 1, w do row[x] = (string.byte(data, base + x - 1) or 0) / tonumber(maxv) end
        px[y] = row
    end
    return w, h, px
end

local function original_size(path)
    local p = io.popen(string.format("identify -format '%%w %%h' %s 2>/dev/null", sh_quote(path .. "[0]")))
    if not p then return nil end
    local s = p:read("*l")
    p:close()
    return s and s:gsub(" ", " X ") or nil
end

-- =====================================================================
-- CONVERSION EN CARACTERES (DIFFUSION D'ERREUR DE FLOYD-STEINBERG)
-- =====================================================================
local function nearest(v)
    local best, bd = 1, 2
    for i, l in ipairs(LEVELS) do
        local d = math.abs(l[3] - v)
        if d < bd then best, bd = i, d end
    end
    return best
end

local function to_rows(w, h, px, dither)
    local rows = {}
    for y = 1, h do
        local parts, inv = {}, false
        for x = 1, w do
            local v = math.max(0, math.min(1, px[y][x]))
            local li = nearest(v)
            if dither then
                local err = v - LEVELS[li][3]
                if x < w then px[y][x + 1] = px[y][x + 1] + err * 7 / 16 end
                if y < h then
                    if x > 1 then px[y + 1][x - 1] = px[y + 1][x - 1] + err * 3 / 16 end
                    px[y + 1][x] = px[y + 1][x] + err * 5 / 16
                    if x < w then px[y + 1][x + 1] = px[y + 1][x + 1] + err * 1 / 16 end
                end
            end
            local l = LEVELS[li]
            if l[2] ~= inv then
                parts[#parts + 1] = l[2] and "\x1b[7m" or "\x1b[0m"
                inv = l[2]
            end
            parts[#parts + 1] = l[1]
        end
        if inv then parts[#parts + 1] = "\x1b[0m" end
        rows[y] = table.concat(parts)
    end
    return rows
end

-- =====================================================================
-- ECRANS
-- =====================================================================
local photos = {}
local cursor, top = 1, 1
local LIST_TOP, LIST_ROWS = 5, 15
local mode_idx, dither = 1, true

local function line_at(y, x, w, text, attr)
    io.write(string.format("\x1b[%d;%dH%s%s%s", y, x, attr or "", minitel.pad(text, w), attr and "\x1b[0m" or ""))
end

local function draw_list_row(i)
    local idx = top + i - 1
    local ph = photos[idx]
    local text = ""
    if ph then
        text = string.format(" %3d  %-52s %-6s %8s", idx, string.sub(ph.name, 1, 52), ph.where, human_size(ph.size))
    end
    line_at(LIST_TOP + i - 1, 3, 76, text, ph and idx == cursor and "\x1b[7m" or nil)
end

local function draw_list(full)
    if full then
        io.write("\x1b[0m\x1b[2J")
        minitel.title_bar("3615 PHOTOS - VISIONNEUSE")
        minitel.draw_frame(1, 2, 80, 21, "VOS PHOTOS")
        io.write("\x1b[3;3H\x1b[1m" .. string.format(" %3s  %-52s %-6s %8s", "N.", "FICHIER", "LIEU", "TAILLE") .. "\x1b[0m")
        io.write("\x1b[4;3H" .. string.rep("-", 76))
        minitel.footer("[Z/S] CHOISIR  [ENVOI] VOIR  [P] DIAPORAMA  [A] ACTUALISER  [RETOUR] QUITTER")
    end
    if #photos == 0 then
        line_at(7, 5, 72, "AUCUNE PHOTO TROUVEE.", "\x1b[1m")
        line_at(9, 5, 72, "Copiez vos photos (JPEG, PNG...) dans le dossier photos/ du depot,")
        line_at(10, 5, 72, "par exemple depuis un ordinateur :")
        line_at(11, 5, 72, "  scp *.jpg minitel@<adresse du Pi>:minitel_gc/photos/")
        line_at(12, 5, 72, "ou branchez une cle USB : ses photos apparaissent ici.")
    else
        for i = 1, LIST_ROWS do draw_list_row(i) end
    end
    if not IM then
        line_at(20, 3, 76, "IMAGEMAGICK ABSENT : sudo apt install imagemagick", "\x1b[7m")
    end
    line_at(21, 3, 76, #photos > 0 and string.format("%d PHOTO(S)  -  DOSSIER %s/ ET CLES USB", #photos, PHOTO_DIR) or "")
    io.write("\x1b[24;80H")
    io.flush()
end

-- Affiche une photo ; rend la touche qui a fait quitter la vue (ou "NEXT"
-- quand le diaporama passe a la suivante)
local function view(idx, slideshow)
    local ph = photos[idx]
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 PHOTOS - " .. string.upper(string.sub(ph.name, 1, 50)))
    minitel.footer("[Q/D] PREC./SUIV. [M] MODE [T] TRAME [P] DIAPORAMA [RETOUR] LISTE")
    line_at(23, 1, 80, string.format(" %d / %d   CHARGEMENT DE LA PHOTO...", idx, #photos), "\x1b[7m")
    io.flush()
    local w, h, px = load_gray(ph.path, MODES[mode_idx])
    if not w then
        line_at(12, 20, 40, "IMPOSSIBLE DE LIRE CETTE PHOTO", "\x1b[7m")
    else
        local rows = to_rows(w, h, px, dither)
        local x0 = VIEW_X + (VIEW_W - w) // 2
        local y0 = VIEW_Y + (VIEW_H - h) // 2
        for y = 1, h do
            io.write(string.format("\x1b[%d;%dH%s", y0 + y - 1, x0, rows[y]))
        end
    end
    local dims = original_size(ph.path)
    line_at(23, 1, 80, string.format(" %d / %d   %s   %s   MODE %s%s%s", idx, #photos, dims or "?", human_size(ph.size),
        MODES[mode_idx], dither and "" or ", SANS TRAME", slideshow and "   DIAPORAMA" or ""), "\x1b[7m")
    io.write("\x1b[24;80H")
    io.flush()
    minitel.wait_output() -- la photo est affichee : le delai du diaporama part d'ici
    local t0 = os.time()
    while true do
        local k = minitel.get_key()
        if k then return k end
        if slideshow and os.time() - t0 >= SLIDE_DELAY then return "NEXT" end
        minitel.sleep(0.05)
    end
end

local function viewer(start, slideshow)
    local idx = start
    while true do
        local k = view(idx, slideshow)
        if k == "NEXT" or k == "d" or k == "D" or k == "RIGHT" or k == "SUITE" or k == " " or k == "ENVOI" then
            idx = idx % #photos + 1
        elseif k == "q" or k == "Q" or k == "LEFT" then
            idx = (idx - 2) % #photos + 1
            slideshow = false
        elseif k == "m" or k == "M" then
            mode_idx = mode_idx % #MODES + 1
        elseif k == "t" or k == "T" then
            dither = not dither
        elseif k == "p" or k == "P" then
            slideshow = not slideshow
        elseif k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then
            return idx
        elseif slideshow then
            slideshow = false -- toute autre touche arrete le diaporama
        end
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
photos = scan_photos()
draw_list(true)

while true do
    local k = minitel.get_key()
    if k then
        local old_cursor, old_top = cursor, top
        if k == "RETOUR" or k == "ESC" then
            break
        elseif (k == "z" or k == "Z" or k == "UP") and cursor > 1 then
            cursor = cursor - 1
        elseif (k == "s" or k == "S" or k == "DOWN") and cursor < #photos then
            cursor = cursor + 1
        elseif (k == "ENVOI" or k == "p" or k == "P") and #photos > 0 and IM then
            cursor = viewer(cursor, k == "p" or k == "P")
            top = ((cursor - 1) // LIST_ROWS) * LIST_ROWS + 1
            draw_list(true)
            old_cursor, old_top = cursor, top
        elseif k == "a" or k == "A" or k == "REPETITION" then
            photos = scan_photos()
            cursor, top = math.min(cursor, math.max(1, #photos)), 1
            draw_list(true)
        end
        top = ((cursor - 1) // LIST_ROWS) * LIST_ROWS + 1
        if top ~= old_top then
            draw_list(false)
        elseif cursor ~= old_cursor then
            draw_list_row(old_cursor - top + 1)
            draw_list_row(cursor - top + 1)
            io.write("\x1b[24;80H")
            io.flush()
        end
    end
    minitel.sleep(0.02)
end

minitel.cleanup()
