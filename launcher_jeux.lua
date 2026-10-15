local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION DU PORTAIL DE JEUX (100% DYNAMIQUE @ 9600 BAUDS)
-- =====================================================================
local CONFIG = {
    DOSSIER = "jeux/",
    TITRE = "3615 MAGIS ARCADE - SALLE DE JEUX",
    SOUS_TITRE = " CATALOGUE DES CARTOUCHES ",
    MSG_VIDE = "AUCUN JEU DETECTE"
}

-- =====================================================================
-- BANQUE DE LOGOS AUTOMATIQUES SELON LE MOT-CLE DU @GENRE
-- =====================================================================
local GENRE_LOGOS = {
    {
        keywords = {"CASINO", "CARTE", "POKER", "HASARD"},
        art = {
            "   .-------.  .-------.   ",
            "   | *   * |  | (M)   |   ",
            "   | ETOILE|  | MAGIS |   ",
            "   | *   * |  |   (M) |   ",
            "   '-------'  '-------'   "
        }
    },
    {
        keywords = {"ROGUE", "RPG", "AVENTURE", "DONJON", "CYBER"},
        art = {
            "      #########           ",
            "      # @ . > #   /_/\\    ",
            "      # . # * #  [X X]    ",
            "      #########   ===     ",
            "    NOEUD RESEAU INFECTE  "
        }
    },
    {
        keywords = {"GESTION", "BOURSE", "SPECULATION", "COMMERCE", "FINANCE"},
        art = {
            "   15k |        /\\   /    ",
            "   10k |   /\\  /  \\ /     ",
            "    5k |  /  \\/    v      ",
            "       +----------------  ",
            "       PARIS  LYON REIMS  "
        }
    },
    {
        keywords = {"FICTION", "TEXTE", "HISTOIRE", "ENQUETE", "ANOMALIE"},
        art = {
            "    .------------------.  ",
            "    | > SECTEUR 4 : HS |  ",
            "    | > OZONE DETECTE  |  ",
            "    | > CHOIX [1-4] _  |  ",
            "    '------------------'  "
        }
    },
    {
        keywords = {"LOGIQUE", "HACK", "PUZZLE", "REFLEXION", "PIRATE"},
        art = {
            "   0x7F4A  [!@#$%]  0x7F50",
            "   0x7F4B  [ACCES]  0x7F51",
            "   0x7F4C  [>*<  ]  0x7F52",
            "   -----------------------",
            "   TENTATIVES : [][][][]  "
        }
    },
    {
        keywords = {"COURSE", "AUTO", "SIMULATION", "VITESSE", "CIRCUIT"},
        art = {
            "         /   |   \\        ",
            "       /   .-'-.   \\      ",
            "     /   .'     '.   \\    ",
            "    |  =[_O_____O_]=  |   ",
            "   =====================  "
        }
    },
    {
        keywords = {"ACTION", "TIR", "SHOOT", "ESPACE", "ARCADE"},
        art = {
            "      *     /\\     .      ",
            "    .      /  \\       *   ",
            "          |[<>]|          ",
            "         /_ || _\\         ",
            "           v  v           "
        }
    }
}

local DEFAULT_LOGO = {
    "       .------------.     ",
    "       | [CARTOUCHE]|     ",
    "       |   .----.   |     ",
    "       |   | () |   |     ",
    "       '---'----'---'     "
}

local function select_logo_by_genre(genre_str, game_name)
    local search_target = string.upper((genre_str or "") .. " " .. (game_name or ""))
    for _, entry in ipairs(GENRE_LOGOS) do
        for _, kw in ipairs(entry.keywords) do
            if string.find(search_target, kw, 1, true) then
                return entry.art
            end
        end
    end
    return DEFAULT_LOGO
end

-- =====================================================================
-- ANALYSE DYNAMIQUE DES EN-TETES DE FICHIERS (.LUA)
-- =====================================================================
local function get_file_metadata(filepath, display_name)
    local meta = {
        genre = "ARCADE / LOGICIEL",
        art = DEFAULT_LOGO,
        desc = "Cartouche de divertissement compatible avec le standard Minitel 80 colonnes du Magis Club.",
        size = "0 Ko",
        lines = 0
    }

    local f = io.open(filepath, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content then
            local bytes = #content
            if bytes >= 1024 then
                meta.size = string.format("%.1f Ko", bytes / 1024)
            else
                meta.size = bytes .. " o"
            end

            local l_count = 0
            local header_lines = {}
            for line in content:gmatch("([^\r\n]*)\r?\n?") do
                if line ~= "" or l_count > 0 then
                    l_count = l_count + 1
                    if #header_lines < 15 then
                        table.insert(header_lines, line)
                    end
                end
            end
            meta.lines = math.max(1, l_count - 1)

            local custom_art = {}
            for _, hline in ipairs(header_lines) do
                local g = hline:match("^%-%-%s*@GENRE%s*:%s*(.+)$") or hline:match("^%-%-%s*@TYPE%s*:%s*(.+)$")
                local d = hline:match("^%-%-%s*@DESC%s*:%s*(.+)$")
                local a_idx, a_txt = hline:match("^%-%-%s*@ART([1-5])%s*:%s*(.+)$")

                if g then meta.genre = minitel.clean_accents(g):upper() end
                if d then meta.desc = minitel.clean_accents(d) end
                if a_idx and a_txt then custom_art[tonumber(a_idx)] = a_txt end
            end

            if #custom_art == 5 then
                meta.art = custom_art
            else
                meta.art = select_logo_by_genre(meta.genre, display_name)
            end
        end
    end

    return meta
end

local function scan_directory()
    local item_list = {}
    local cmd = "\\ls -1 " .. CONFIG.DOSSIER .. "*.lua 2>/dev/null"
    local f = io.popen(cmd)

    if f then
        for file in f:lines() do
            local name = string.match(file, CONFIG.DOSSIER .. "(.-)%.lua$")
            if name then
                local disp = string.upper(name)
                table.insert(item_list, {
                    filepath = file,
                    display = disp,
                    meta = get_file_metadata(file, disp)
                })
            end
        end
        f:close()
    end

    if #item_list == 0 then
        table.insert(item_list, {
            filepath = nil,
            display = CONFIG.MSG_VIDE,
            meta = {
                genre = "AUCUN",
                art = {
                    "                          ",
                    "      [ PORT VIDE ]       ",
                    "   INSEREZ UNE DISQUETTE  ",
                    "      DANS /" .. CONFIG.DOSSIER .. "          ",
                    "                          "
                },
                desc = "Aucun script Lua n'a ete trouve dans le repertoire des jeux.",
                size = "0 o",
                lines = 0
            }
        })
    end
    return item_list
end

local items = scan_directory()
local cursor = 1
local offset = 0
local max_visible = 12
local list_start_y = 8

-- Mode Turbo [H] : Si actif, l'aperçu de droite ne se rafraichit qu'au bout de 1.5s d'inactivite
local fast_mode = true
local details_dirty = false
local last_move_ts = 0

local function get_mono_time()
    local f = io.open("/proc/uptime", "r")
    if f then
        local s = f:read("*l")
        f:close()
        local up = s and tonumber(s:match("^([%d%.]+)"))
        if up then return up end
    end
    return os.time()
end

-- =====================================================================
-- AFFICHAGE DU SQUELETTE STATIQUE (CADRES & BANDEAUX)
-- =====================================================================
local function draw_right_header_badge()
    local badge = fast_mode and "APERCU [H: TURBO 1.5S]" or "APERCU [H: DIRECT]"
    io.write("\x1b[6;40H|\x1b[7m" .. minitel.center(badge, 38) .. "\x1b[0m|")
end

local function draw_static_portal()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m  [JOY]  " .. minitel.center("* * *  " .. CONFIG.TITRE .. "  * * *", 60) .. "  9600 BDS \x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    io.write("\x1b[5;2H.----------------------------------.")
    io.write("\x1b[5;40H.--------------------------------------.")

    io.write("\x1b[6;2H|\x1b[7m" .. minitel.center(CONFIG.SOUS_TITRE, 34) .. "\x1b[0m|")
    draw_right_header_badge()

    io.write("\x1b[7;2H|----------------------------------|")
    io.write("\x1b[7;40H|--------------------------------------|")

    for y = 8, 19 do
        io.write(string.format("\x1b[%d;2H|                                  |", y))
        io.write(string.format("\x1b[%d;40H|                                      |", y))
    end

    io.write("\x1b[13;40H|--------------------------------------|")
    io.write("\x1b[20;2H|----------------------------------|")
    io.write("\x1b[20;40H|--------------------------------------|")
    io.write("\x1b[21;2H|                                  |")
    io.write("\x1b[21;40H|                                      |")
    io.write("\x1b[22;2H'----------------------------------'")
    io.write("\x1b[22;40H'--------------------------------------'")

    io.write("\x1b[24;1H\x1b[7m [Z/S] CHOIX | [ENVOI] JOUER | [H] MODE TURBO | [R] SCAN | [RETOUR] MENU     \x1b[0m")
    io.flush()
end

-- =====================================================================
-- AFFICHAGE DU PANNEAU DE DROITE (FICHE DU JEU SELECTIONNE)
-- =====================================================================
local function draw_details_panel()
    local item = items[cursor]
    if not item or not item.meta then return end
    local m = item.meta

    for i = 1, 5 do
        local art_line = m.art[i] or ""
        io.write(string.format("\x1b[%d;41H\x1b[1m%s\x1b[0m", 7 + i, minitel.center(art_line, 38)))
    end

    local title_line = "TITRE : " .. item.display
    local genre_line = "GENRE : " .. m.genre
    io.write(string.format("\x1b[14;42H\x1b[1m%s\x1b[0m", minitel.pad(title_line, 36)))
    io.write(string.format("\x1b[15;42H%s", minitel.pad(genre_line, 36)))

    local desc_lines = minitel.wrap(m.desc, 36, 3)
    for i = 1, 3 do
        io.write(string.format("\x1b[%d;42H%s", 16 + i, desc_lines[i]))
    end

    local footer_right = string.format("TAILLE: %-8s | CODE: %d LIGNES", m.size, m.lines)
    io.write(string.format("\x1b[21;42H%s", minitel.pad(footer_right, 36)))
    details_dirty = false
end

-- =====================================================================
-- AFFICHAGE DE LA LISTE GAUCHE ET SCROLLBAR (DELTA-DRAWING)
-- =====================================================================
local function format_list_entry(idx, is_selected)
    local item = items[idx]
    if not item then return string.rep(" ", 32) end
    local num_str = item.filepath and string.format("%02d.", idx) or "   "
    local label = num_str .. " " .. minitel.pad(item.display, 24)
    if is_selected then
        return "\x1b[7m > " .. label .. " < \x1b[0m"
    else
        return "   " .. label .. "   "
    end
end

local function draw_scrollbar_and_counter()
    local count_total = (items[1] and items[1].filepath) and #items or 0
    local count_cur = (count_total > 0) and cursor or 0
    local status_left = string.format("CARTOUCHE : %02d / %02d", count_cur, count_total)
    io.write(string.format("\x1b[21;4H\x1b[1m%s\x1b[0m", minitel.center(status_left, 30)))

    if #items > max_visible then
        local thumb_pos = math.floor(((cursor - 1) / math.max(1, #items - 1)) * (max_visible - 3)) + 2
        for i = 1, max_visible do
            local y = list_start_y + i - 1
            local char = (i == 1 and "^") or (i == max_visible and "v") or (i == thumb_pos and "\x1b[7m#\x1b[0m") or ":"
            io.write(string.format("\x1b[%d;36H%s", y, char))
        end
    else
        for i = 1, max_visible do
            io.write(string.format("\x1b[%d;36H ", list_start_y + i - 1))
        end
    end
end

local function trigger_details_update(force_now)
    if force_now or not fast_mode then
        draw_details_panel()
    else
        details_dirty = true
        last_move_ts = get_mono_time()
        -- Petit indicateur discret en bas a droite pendant le defilement rapide
        local item = items[cursor]
        if item then
            io.write(string.format("\x1b[21;42H%-36s", "SELECTION : " .. item.display .. " ..."))
        end
    end
end

local function draw_full_list(force_details)
    for i = 1, max_visible do
        local idx = offset + i
        local y = list_start_y + i - 1
        io.write(string.format("\x1b[%d;3H%s", y, format_list_entry(idx, idx == cursor)))
    end
    draw_scrollbar_and_counter()
    trigger_details_update(force_details)
    io.flush()
end

local function update_cursor(old_index, new_index)
    local old_y = list_start_y + (old_index - offset) - 1
    local new_y = list_start_y + (new_index - offset) - 1

    if old_y >= list_start_y and old_y < list_start_y + max_visible then
        io.write(string.format("\x1b[%d;3H%s", old_y, format_list_entry(old_index, false)))
    end
    if new_y >= list_start_y and new_y < list_start_y + max_visible then
        io.write(string.format("\x1b[%d;3H%s", new_y, format_list_entry(new_index, true)))
    end

    draw_scrollbar_and_counter()
    trigger_details_update(false)
    io.flush()
end

local function play_launch_effect(game_name)
    io.write("\x1b[21;41H\x1b[7m" .. minitel.center("CHARGEMENT : " .. game_name, 38) .. "\x1b[0m")
    io.flush()
    minitel.play_sound("hit")
    minitel.sleep(0.25)
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
draw_static_portal()
draw_full_list(true)

while true do
    local key = minitel.get_key()
    local old_cursor = cursor

    -- Si le mode Turbo est actif et que 1.5s s'est ecoulee depuis le dernier mouvement, on affiche l'art !
    if details_dirty and (get_mono_time() - last_move_ts >= 1.5) then
        draw_details_panel()
        io.flush()
    end

    if key == "h" or key == "H" then
        fast_mode = not fast_mode
        draw_right_header_badge()
        draw_details_panel()
        io.flush()

    elseif key == "r" or key == "R" or key == "REPETITION" then
        items = scan_directory()
        cursor = 1
        offset = 0
        draw_static_portal()
        draw_full_list(true)

    elseif key == "z" or key == "Z" or key == "UP" then
        if cursor > 1 then
            cursor = cursor - 1
            if cursor <= offset then
                offset = cursor - 1
                draw_full_list(false)
            else
                update_cursor(old_cursor, cursor)
            end
        else
            cursor = #items
            offset = math.max(0, #items - max_visible)
            draw_full_list(false)
        end

    elseif key == "s" or key == "S" or key == "DOWN" then
        if cursor < #items then
            cursor = cursor + 1
            if cursor > offset + max_visible then
                offset = cursor - max_visible
                draw_full_list(false)
            else
                update_cursor(old_cursor, cursor)
            end
        else
            cursor = 1
            offset = 0
            draw_full_list(false)
        end

    elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
        local selected = items[cursor]
        if selected and selected.filepath then
            play_launch_effect(selected.display)
            minitel.cleanup()
            os.execute("lua5.3 " .. selected.filepath)
            minitel.init()

            items = scan_directory()
            if cursor > #items then
                cursor = 1
                offset = 0
            end
            draw_static_portal()
            draw_full_list(true)
        end

    elseif key == "RETOUR" or key == "ESC" or key == "SOMMAIRE" then
        break
    end

    minitel.sleep(0.01)
end

minitel.cleanup()