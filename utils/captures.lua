-- @TYPE: TELEMATIQUE / BUREAUTIQUE
-- @DESC: Galerie de visualisation des captures d'ecran 80x24 locales et partage en ligne vers Pastebin.

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p screenshots 2>/dev/null")

-- =====================================================================
-- LECTURE DES CAPTURES D'ECRAN DISPONIBLES
-- =====================================================================
local function scan_screenshots()
    local list = {}
    local f = io.popen("\\ls -1r screenshots/*.txt 2>/dev/null")
    if f then
        for filepath in f:lines() do
            local name = filepath:match("screenshots/(.+)$") or filepath
            local f_in = io.open(filepath, "r")
            local lines = {}
            local date_str = "DATE INCONNUE"
            if f_in then
                for l in f_in:lines() do
                    table.insert(lines, l)
                end
                f_in:close()
                if lines[#lines] and lines[#lines]:find("Capture realisee") then
                    date_str = lines[#lines]:gsub("^Capture realisee depuis 3615 MAGIS CLUB le ", "")
                end
            end
            table.insert(list, {
                path = filepath,
                name = name,
                date = date_str,
                lines = lines
            })
        end
        f:close()
    end
    return list
end

-- =====================================================================
-- ENVOI D'UN FICHIER DE CAPTURE VERS PASTEBIN
-- =====================================================================
local function upload_to_pastebin(filepath)
    minitel.draw_window(16, 9, 50, 5, "ENVOI VERS PASTEBIN")
    io.write("\x1b[11;18H" .. minitel.center("TRANSMISSION DE LA CAPTURE EN COURS...", 46))
    io.flush()
    minitel.play_sound("hit")

    local paste_url = nil
    local cmd1 = string.format("curl -sL -m 8 -F 'content=<%s' -F 'syntax=text' -F 'expiry_days=30' https://dpaste.com/api/v2/ 2>/dev/null", filepath)
    local p1 = io.popen(cmd1)
    if p1 then
        local res = (p1:read("*a") or ""):gsub("%s+", "")
        p1:close()
        if res:match("^https?://") then paste_url = res end
    end

    if not paste_url then
        local cmd2 = string.format("curl -sL -m 8 --data-binary @%s https://paste.rs/ 2>/dev/null", filepath)
        local p2 = io.popen(cmd2)
        if p2 then
            local res = (p2:read("*a") or ""):gsub("%s+", "")
            p2:close()
            if res:match("^https?://") then paste_url = res end
        end
    end

    if paste_url then
        minitel.msg_box("LIEN PASTEBIN GENERE", "Votre capture est accessible sur : " .. paste_url, "win")
    else
        minitel.msg_box("ERREUR RESEAU", "Impossible de joindre les serveurs dpaste.com ou paste.rs.", "lose")
    end
end

-- =====================================================================
-- VISIONNEUSE PLEIN ECRAN (RESTAURATION EXACTE 80x24)
-- =====================================================================
local function view_fullscreen(item)
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Les lignes 2 a 25 du fichier .txt contiennent les 24 lignes encadrees par |...|
    for y = 1, 24 do
        local raw_line = item.lines[y + 1] or ""
        -- On retire le '|' de debut et le '|' de fin ajoutes dans le fichier texte
        local content = raw_line:match("^|(.*)|$") or raw_line
        io.write(string.format("\x1b[%d;1H%s", y, string.sub(content, 1, 80)))
    end

    -- Petit badge discret en bas a droite pour indiquer qu'on est en mode Visionneuse
    io.write("\x1b[24;52H\x1b[7m [APERCU - RETOUR=FERMER] \x1b[0m")
    io.flush()

    while true do
        local k = minitel.get_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == " " then
            break
        elseif k == "P" or k == "p" then
            upload_to_pastebin(item.path)
            break
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- INTERFACE PRINCIPALE DE LA GALERIE (DELTA-DRAWING)
-- =====================================================================
local items = scan_screenshots()
local cursor = 1
local offset = 0
local max_visible = 12

local function draw_row(slot)
    local idx = offset + slot
    local it = items[idx]
    local y = 7 + slot

    if not it then
        io.write(string.format("\x1b[%d;3H%s", y, string.rep(" ", 33)))
        return
    end

    local label = string.format("%02d. %-27s", idx, string.sub(it.name, 1, 27))
    if idx == cursor then
        io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(label, 31)))
    else
        io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(label, 31)))
    end
end

local function draw_preview_panel()
    local it = items[cursor]
    if not it then
        io.write("\x1b[9;41H" .. minitel.center("AUCUNE CAPTURE ENREGISTREE", 38))
        io.write("\x1b[11;41H" .. minitel.center("Appuyez sur [Ctrl+P] ou [Impression]", 38))
        io.write("\x1b[12;41H" .. minitel.center("dans n'importe quel jeu ou outil", 38))
        io.write("\x1b[13;41H" .. minitel.center("pour capturer l'ecran !", 38))
        for r = 15, 20 do io.write(string.format("\x1b[%d;41H%s", r, string.rep(" ", 38))) end
        return
    end

    io.write(string.format("\x1b[6;41H\x1b[1m FICHIER :\x1b[0m %-27s", string.sub(it.name, 1, 27)))
    io.write(string.format("\x1b[7;41H\x1b[1m DATE    :\x1b[0m %-27s", string.sub(it.date, 1, 27)))
    io.write("\x1b[8;40H+--------------------------------------+")
    io.write("\x1b[9;41H\x1b[7m" .. minitel.center("MINIATURE DE L'ECRAN ( EXTRAIT )", 38) .. "\x1b[0m")

    -- Affiche un extrait des 10 premieres lignes non vides de la capture
    local shown = 0
    for i = 2, math.min(25, #it.lines) do
        local content = (it.lines[i] or ""):match("^|(.*)|$") or ""
        if content:match("%S") and shown < 10 then
            shown = shown + 1
            local trimmed = content:gsub("^%s+", "")
            io.write(string.format("\x1b[%d;41H %-36s ", 9 + shown, string.sub(trimmed, 1, 36)))
        end
    end
    while shown < 10 do
        shown = shown + 1
        io.write(string.format("\x1b[%d;41H%s", 9 + shown, string.rep(" ", 38)))
    end
end

local function draw_gallery_full()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 CAPTURES - SPOULEUR D'IMPRESSION & PASTEBIN  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(2, 4, 36, 18, string.format("CAPTURES LOCALES (%d)", #items))
    minitel.draw_window(40, 4, 40, 18, "APERCU & INFOS DU CLICHE")
    io.write("\x1b[6;2H\x1b[1m+----------------------------------+\x1b[0m")
    io.write("\x1b[5;4H\x1b[1mASTUCE : [Ctrl+P] = Capturer\x1b[0m")

    for s = 1, max_visible do draw_row(s) end
    draw_preview_panel()

    io.write("\x1b[24;1H\x1b[7m [ENVOI] PLEIN ECRAN | [P] ENVOI PASTEBIN | [ANNUL.] SUPPRIMER | [RETOUR] MENU \x1b[0m")
    io.flush()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
draw_gallery_full()

while true do
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" then
            break

        elseif k == "R" or k == "r" or k == "REPETITION" then
            items = scan_screenshots()
            cursor = 1; offset = 0
            draw_gallery_full()

        elseif (k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s") and #items > 0 then
            local is_up = (k == "UP" or k == "Z" or k == "z")
            local old_c, old_off = cursor, offset

            if is_up then
                if cursor > 1 then
                    cursor = cursor - 1
                    if cursor <= offset then offset = cursor - 1 end
                else
                    cursor = #items
                    offset = math.max(0, #items - max_visible)
                end
            else
                if cursor < #items then
                    cursor = cursor + 1
                    if cursor > offset + max_visible then offset = cursor - max_visible end
                else
                    cursor = 1; offset = 0
                end
            end

            if offset ~= old_off then
                for s = 1, max_visible do draw_row(s) end
            else
                draw_row(old_c - offset)
                draw_row(cursor - offset)
            end
            draw_preview_panel()
            io.flush()

        elseif (k == "ENVOI" or k == " ") and #items > 0 then
            view_fullscreen(items[cursor])
            draw_gallery_full()

        elseif (k == "P" or k == "p") and #items > 0 then
            upload_to_pastebin(items[cursor].path)
            draw_gallery_full()

        elseif k == "ANNULATION" and #items > 0 then
            local sel = items[cursor]
            if minitel.confirm_box("SUPPRIMER LA CAPTURE", "Effacer definitivement " .. sel.name .. " du disque ?") then
                os.remove(sel.path)
                items = scan_screenshots()
                if cursor > #items then cursor = math.max(1, #items) end
                if offset > 0 and cursor <= offset then offset = math.max(0, cursor - 1) end
            end
            draw_gallery_full()
        end
    end
    minitel.sleep(0.01)
end

minitel.cleanup()