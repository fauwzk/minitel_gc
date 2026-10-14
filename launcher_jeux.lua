local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION DU PORTAIL DE JEUX (OPTIMISE 9600 BAUDS)
-- =====================================================================
local CONFIG = {
    DOSSIER = "jeux/",
    TITRE = "3615 MAGIS ARCADE - SALLE DE JEUX",
    SOUS_TITRE = " CATALOGUE DES CARTOUCHES ",
    MSG_VIDE = "AUCUN JEU DETECTE"
}

-- Base de donnees visuelle des jeux connus (Art ASCII 34 col max x 5 lignes)
local GAME_DB = {
    ["POKER"] = {
        genre = "CASINO / CARTES",
        players = "1 JOUEUR VS CROUPIER",
        art = {
            "   .-------.  .-------.   ",
            "   | *   * |  | (M)   |   ",
            "   | ETOILE|  | MAGIS |   ",
            "   | *   * |  |   (M) |   ",
            "   '-------'  '-------'   "
        },
        desc = "Affrontez l'IA du Magis Club au Poker a 5 cartes. Misez vos jetons et tentez le Carre ou les 5 Identiques !"
    },
    ["ENIGMA"] = {
        genre = "ROGUE-LIKE / CYBER",
        players = "1 JOUEUR (AVENTURE)",
        art = {
            "      #########           ",
            "      # @ . > #   /_/\\    ",
            "      # . # * #  [X X]    ",
            "      #########   ===     ",
            "    NOEUD RESEAU INFECTE  "
        },
        desc = "Plongez dans les noeuds du reseau. Purgez les malwares, compilez des patchs et survivez aux couches profondes."
    },
    ["MINITEL_RPG"] = {
        genre = "ROGUE-LIKE / CYBER",
        players = "1 JOUEUR (AVENTURE)",
        art = {
            "      #########           ",
            "      # @ . > #   /_/\\    ",
            "      # . # * #  [X X]    ",
            "      #########   ===     ",
            "    NOEUD RESEAU INFECTE  "
        },
        desc = "Plongez dans les noeuds du reseau. Purgez les malwares, compilez des patchs et survivez aux couches profondes."
    },
    ["ANOMALIE"] = {
        genre = "FICTION INTERACTIVE",
        players = "1 JOUEUR (SAUVEGARDE)",
        art = {
            "    .------------------.  ",
            "    | > SECTEUR 4 : HS |  ",
            "    | > OZONE DETECTE  |  ",
            "    | > _              |  ",
            "    '------------------'  "
        },
        desc = "Aventure textuelle avec inventaire et sauvegarde persistante. Explorez la station relais et survivez a l'anomalie."
    },
    [" PIRATE"] = {
        genre = "LOGIQUE / HACKING",
        players = "1 JOUEUR",
        art = {
            "   0x7F4A  [!@#$%]  0x7F50",
            "   0x7F4B  [ACCES]  0x7F51",
            "   0x7F4C  [>*<  ]  0x7F52",
            "   -----------------------",
            "   TENTATIVES : [][][][]  "
        },
        desc = "Infiltrez le terminal central en devinant le mot de passe cache dans les octets de la memoire."
    }
}

local DEFAULT_META = {
    genre = "ARCADE / LOGICIEL",
    players = "1 JOUEUR",
    art = {
        "       .------------.     ",
        "       | [________] |     ",
        "       |   .----.   |     ",
        "       |   | () |   |     ",
        "       '---'----'---'     "
    },
    desc = "Cartouche de divertissement compatible avec le standard Minitel 80 colonnes du Magis Club."
}

-- =====================================================================
-- LECTURE DU DOSSIER ET DES METADONNEES
-- =====================================================================
local function get_file_metadata(filepath, display_name)
    local meta = {
        genre = DEFAULT_META.genre,
        players = DEFAULT_META.players,
        art = DEFAULT_META.art,
        desc = DEFAULT_META.desc,
        size = "0 Ko"
    }

    -- Recherche d'une correspondance dans GAME_DB (exacte ou partielle)
    for k, v in pairs(GAME_DB) do
        if display_name == k or string.find(display_name, k) then
            meta.genre = v.genre
            meta.players = v.players
            meta.art = v.art
            meta.desc = v.desc
            break
        end
    end

    -- Lecture de la taille et d'eventuels tags "-- @DESC:" ou "-- @GENRE:" dans le fichier
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
            local custom_genre = string.match(content, "%-%-%s*@GENRE:%s*([^\r\n]+)")
            local custom_desc = string.match(content, "%-%-%s*@DESC:%s*([^\r\n]+)")
            if custom_genre then meta.genre = custom_genre end
            if custom_desc then meta.desc = custom_desc end
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
                players = "-",
                art = {
                    "                          ",
                    "      [ PORT VIDE ]       ",
                    "   INSEREZ UNE DISQUETTE  ",
                    "      DANS /" .. CONFIG.DOSSIER .. "          ",
                    "                          "
                },
                desc = "Aucun script Lua n'a ete trouve dans le repertoire des jeux.",
                size = "0 o"
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

-- =====================================================================
-- UTILITAIRES DE MISE EN PAGE
-- =====================================================================
local function pad_str(str, len)
    if #str > len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

local function center_str(str, len)
    if #str >= len then return string.sub(str, 1, len) end
    local left = math.floor((len - #str) / 2)
    local right = len - #str - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function wrap_text(text, max_width, max_lines)
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        if #current + #word + 1 > max_width then
            table.insert(lines, pad_str(current, max_width))
            current = word
            if #lines >= max_lines then break end
        else
            current = (current == "") and word or (current .. " " .. word)
        end
    end
    if #lines < max_lines and current ~= "" then
        table.insert(lines, pad_str(current, max_width))
    end
    while #lines < max_lines do
        table.insert(lines, string.rep(" ", max_width))
    end
    return lines
end

-- =====================================================================
-- AFFICHAGE DU SQUELETTE STATIQUE (CADRES & BANDEAUX)
-- =====================================================================
local function draw_static_portal()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Bandeau Superieur (3 lignes)
    io.write("\x1b[1;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m  [JOY]  " .. center_str("* * *  " .. CONFIG.TITRE .. "  * * *", 60) .. "  9600 BDS \x1b[0m")
    io.write("\x1b[3;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    -- Entetes des 2 panneaux (Ligne 5)
    -- Panneau Gauche : Col 2 a 37 (36 larg) | Panneau Droit : Col 40 a 79 (40 larg)
    io.write("\x1b[5;2H.----------------------------------.")
    io.write("\x1b[5;40H.--------------------------------------.")

    io.write("\x1b[6;2H|\x1b[7m" .. center_str(CONFIG.SOUS_TITRE, 34) .. "\x1b[0m|")
    io.write("\x1b[6;40H|\x1b[7m" .. center_str("APERCU DE LA CARTOUCHE", 38) .. "\x1b[0m|")

    io.write("\x1b[7;2H|----------------------------------|")
    io.write("\x1b[7;40H|--------------------------------------|")

    -- Corps des panneaux (Lignes 8 a 19)
    for y = 8, 19 do
        io.write(string.format("\x1b[%d;2H|                                  |", y))
        io.write(string.format("\x1b[%d;40H|                                      |", y))
    end

    -- Séparateur interne dans le panneau droit (Ligne 13)
    io.write("\x1b[13;40H|--------------------------------------|")

    -- Bas des panneaux (Ligne 20 et 21)
    io.write("\x1b[20;2H|----------------------------------|")
    io.write("\x1b[20;40H|--------------------------------------|")

    io.write("\x1b[21;2H|                                  |")
    io.write("\x1b[21;40H|                                      |")

    io.write("\x1b[22;2H'----------------------------------'")
    io.write("\x1b[22;40H'--------------------------------------'")

    -- Bandeau Inferieur (Ligne 24)
    io.write("\x1b[24;1H\x1b[7m  [Z/S] NAVIGUER   |   [ENVOI] LANCER LE JEU   |   [R] SCAN   |   [RETOUR] MENU \x1b[0m")
    io.flush()
end

-- =====================================================================
-- AFFICHAGE DU PANNEAU DE DROITE (FICHE DU JEU SELECTIONNE)
-- =====================================================================
local function draw_details_panel()
    local item = items[cursor]
    if not item or not item.meta then return end
    local m = item.meta

    -- Illustration ASCII (Lignes 8 a 12, Col 42 a 77 -> 36 chars)
    for i = 1, 5 do
        local art_line = m.art[i] or ""
        io.write(string.format("\x1b[%d;41H\x1b[1m%s\x1b[0m", 7 + i, center_str(art_line, 38)))
    end

    -- Infos techniques (Lignes 14 et 15)
    local title_line = "TITRE : " .. item.display
    local genre_line = "GENRE : " .. m.genre
    io.write(string.format("\x1b[14;42H\x1b[1m%s\x1b[0m", pad_str(title_line, 36)))
    io.write(string.format("\x1b[15;42H%s", pad_str(genre_line, 36)))

    -- Description multi-lignes (Lignes 17 a 19)
    local desc_lines = wrap_text(m.desc, 36, 3)
    for i = 1, 3 do
        io.write(string.format("\x1b[%d;42H%s", 16 + i, desc_lines[i]))
    end

    -- Pied du panneau droit : Taille & Statut (Ligne 21)
    local footer_right = string.format("TAILLE: %-9s        [\x1b[1mPRET\x1b[0m]", m.size)
    io.write(string.format("\x1b[21;42H%-36s", footer_right))
end

-- =====================================================================
-- AFFICHAGE DE LA LISTE GAUCHE ET SCROLLBAR
-- =====================================================================
local function format_list_entry(idx, is_selected)
    local item = items[idx]
    if not item then return string.rep(" ", 32) end
    local num_str = item.filepath and string.format("%02d.", idx) or "   "
    local label = num_str .. " " .. pad_str(item.display, 24)
    if is_selected then
        return "\x1b[7m > " .. label .. " < \x1b[0m"
    else
        return "   " .. label .. "   "
    end
end

local function draw_scrollbar_and_counter()
    -- Compteur en bas du panneau gauche (Ligne 21)
    local count_total = (items[1] and items[1].filepath) and #items or 0
    local count_cur = (count_total > 0) and cursor or 0
    local status_left = string.format("CARTOUCHE : %02d / %02d", count_cur, count_total)
    io.write(string.format("\x1b[21;4H\x1b[1m%s\x1b[0m", center_str(status_left, 30)))

    -- Barre de defilement visuelle sur la colonne 36 (Lignes 8 a 19)
    if #items > max_visible then
        local thumb_pos = math.floor(((cursor - 1) / math.max(1, #items - 1)) * (max_visible - 3)) + 2
        for i = 1, max_visible do
            local y = list_start_y + i - 1
            local char = ":"
            if i == 1 then char = "^"
            elseif i == max_visible then char = "v"
            elseif i == thumb_pos then char = "\x1b[7m#\x1b[0m"
            end
            io.write(string.format("\x1b[%d;36H%s", y, char))
        end
    else
        for i = 1, max_visible do
            io.write(string.format("\x1b[%d;36H ", list_start_y + i - 1))
        end
    end
end

local function draw_full_list()
    for i = 1, max_visible do
        local idx = offset + i
        local y = list_start_y + i - 1
        io.write(string.format("\x1b[%d;3H%s", y, format_list_entry(idx, idx == cursor)))
    end
    draw_scrollbar_and_counter()
    draw_details_panel()
    io.flush()
end

-- Mise a jour ultra-rapide sans redessiner toute la liste
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
    draw_details_panel()
    io.flush()
end

-- =====================================================================
-- ANIMATION DE LANCEMENT (9600 BAUDS)
-- =====================================================================
local function play_launch_effect(game_name)
    io.write("\x1b[21;41H\x1b[7m" .. center_str("CHARGEMENT : " .. game_name, 38) .. "\x1b[0m")
    io.flush()
    minitel.play_sound("hit")
    minitel.sleep(0.25)
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
draw_static_portal()
draw_full_list()

while true do
    local key = minitel.get_key()
    local old_cursor = cursor

    if key == "r" or key == "R" or key == "REPETITION" then
        items = scan_directory()
        cursor = 1
        offset = 0
        draw_static_portal()
        draw_full_list()

    elseif key == "z" or key == "Z" or key == "UP" then
        if cursor > 1 then
            cursor = cursor - 1
            if cursor <= offset then
                offset = cursor - 1
                draw_full_list()
            else
                update_cursor(old_cursor, cursor)
            end
        else
            cursor = #items
            offset = math.max(0, #items - max_visible)
            draw_full_list()
        end

    elseif key == "s" or key == "S" or key == "DOWN" then
        if cursor < #items then
            cursor = cursor + 1
            if cursor > offset + max_visible then
                offset = cursor - max_visible
                draw_full_list()
            else
                update_cursor(old_cursor, cursor)
            end
        else
            cursor = 1
            offset = 0
            draw_full_list()
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
            draw_full_list()
        end

    elseif key == "RETOUR" or key == "ESC" or key == "SOMMAIRE" then
        break
    end

    minitel.sleep(0.01)
end

minitel.cleanup()