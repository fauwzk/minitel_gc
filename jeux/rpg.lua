local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- GESTION DE LA CONFIGURATION (SAUVEGARDE LOCALE)
-- =====================================================================
local config = {
    START_HP = 30,
    BASE_ENEMIES = 8,
    ENEMY_MULT = 2.0,
    POTIONS = 5,
    MAP_DENSITY = 100
}

local function load_config()
    local file = io.open("minitel_rpg.cfg", "r")
    if file then
        for line in file:lines() do
            local k, v = string.match(line, "([^=]+)=(.+)")
            if k and v and config[k] ~= nil then
                config[k] = tonumber(v) or config[k]
            end
        end
        file:close()
    end
end

local function save_config()
    local file = io.open("minitel_rpg.cfg", "w")
    if file then
        for k, v in pairs(config) do
            file:write(k .. "=" .. tostring(v) .. "\n")
        end
        file:close()
    end
end

local CFG_MAX_ENEMIES = 40
local CFG_POTION_DECAY = 4
local CFG_HEAL_MIN = 15
local CFG_HEAL_MAX = 25

load_config()

-- =====================================================================
-- DONNEES DU JOUEUR ET DU JEU
-- =====================================================================
local state = "TITLE"
local floor_depth = 1
local p_x, p_y = 2, 2
local p_hp, p_max = config.START_HP, config.START_HP
local p_lvl, p_exp = 1, 0
local p_kills = 0
local p_atk = 0

local current_map = {}
local enemies = {}
local items = {}
local current_enemy = nil
local map_msg = "TROUVEZ LA PASSERELLE (>) POUR DESCENDRE."

local title_cursor = 1
local combat_cursor = 1
local settings_cursor = 1
local msg_combat = ""
local skip_intro = false

-- NOUVEAU BESTIAIRE (LORE INFORMATIQUE)
local BESTIAIRE = {{
    name = "WORM BASIQUE",
    base_hp = 10,
    base_atk = 2
}, {
    name = "TROJAN CACHE",
    base_hp = 15,
    base_atk = 4
}, {
    name = "MALWARE",
    base_hp = 22,
    base_atk = 6
}, {
    name = "LOGICIEL RANCON",
    base_hp = 30,
    base_atk = 8
}, {
    name = "DAEMON ACTIF",
    base_hp = 45,
    base_atk = 11
}, {
    name = "NOYAU FANTOME",
    base_hp = 70,
    base_atk = 16
}}

-- =====================================================================
-- MOTEUR AUDIO ET UTILITAIRES D'INTERRUPTION
-- =====================================================================
local function play_game_sound(effect)
    if skip_intro then
        return
    end
    if effect == "gameover" then
        for i = 1, 4 do
            minitel.play_sound("hit")
            minitel.sleep(0.5)
        end
    elseif effect == "levelup" then
        minitel.play_sound("win")
    else
        minitel.play_sound(effect)
    end
end

local function wait(seconds)
    if skip_intro then
        return true
    end
    local t0 = os.clock()
    while os.clock() - t0 <= seconds do
        local k = minitel.get_key()
        if k == " " or k == "\n" or k == "\r" or k == "P" or k == "p" or k == "ESC" then
            skip_intro = true
            return true
        end
    end
    return false
end

-- =====================================================================
-- CINEMATIQUE D'INTRODUCTION
-- =====================================================================
local function type_text(y, x, text, delay)
    io.write("\x1b[" .. y .. ";" .. x .. "H")
    for i = 1, #text do
        io.write(text:sub(i, i))
        io.flush()
        minitel.sleep(delay or 0.03)
    end
end

local function play_intro()
    skip_intro = false
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    local boot_lines = {"BIOS MINITEL V1.02 ... OK", "TEST MEMOIRE: 64K ... OK", "CHARGEMENT MODULE VIDEOTEX ...",
                        "INITIALISATION PROTOCOLE X.25 ...", "ATTENTE DE CONNEXION..."}
    for i, line in ipairs(boot_lines) do
        io.write("\x1b[" .. i .. ";2H" .. line)
        io.flush()
        if wait(0.3) then
            return
        end
    end
    if wait(0.8) then
        return
    end

    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)
    io.write("\x1b[5;26H.-------------------------.\r\n")
    io.write("\x1b[6;26H|    \x1b[7m TELETEL ACTIVE \x1b[0m     |\r\n")
    io.write("\x1b[7;26H|                         |\r\n")
    io.write("\x1b[8;26H| >                       |\r\n")
    io.write("\x1b[9;26H|                         |\r\n")
    io.write("\x1b[10;26H'-------------------------'\r\n")
    io.write("\x1b[15;26H\x1b[7m [ESPACE] POUR PASSER \x1b[0m\r\n")
    io.flush()
    if wait(0.5) then
        return
    end

    local target = "3615 ENIGMA"
    for i = 1, #target do
        io.write("\x1b[8;" .. (29 + i) .. "H" .. target:sub(i, i))
        io.flush()
        if wait(0.1) then
            return
        end
    end
    if wait(0.5) then
        return
    end

    io.write("\x1b[12;20HTRANSFERT [")
    for i = 1, 30 do
        if skip_intro then
            return
        end
        io.write("\x1b[12;" .. (30 + i) .. "H#")

        io.write("\x1b[13;30H\x1b[K")
        local eq = ""
        for j = 1, 8 do
            local r = math.random(1, 3)
            if r == 1 then
                eq = eq .. "_"
            elseif r == 2 then
                eq = eq .. "-"
            else
                eq = eq .. "^"
            end
        end
        io.write("\x1b[13;31H" .. eq)
        io.flush()

        play_game_sound("hit")
        wait(0.03 + (math.random(1, 5) / 100.0))
    end
    io.write("\x1b[12;61H] OK")
    io.flush()
    if wait(0.5) then
        return
    end

    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)
    io.write("\x1b[23;26H\x1b[7m [ESPACE] POUR PASSER \x1b[0m")
    io.write("\x1b[2;25H\x1b[1m[ ANALYSE DU VERROU ENIGMA ]\x1b[0m")
    io.write("\x1b[18;31H ETAT: \x1b[7m INTACT \x1b[0m")
    io.flush()

    local points_3d = {{-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1}, {-1, -1, 1}, {1, -1, 1}, {1, 1, 1},
                       {-1, 1, 1}, {0, -1, -1}, {0, 1, -1}, {0, -1, 1}, {0, 1, 1}, {-1, 0, -1}, {1, 0, -1}, {-1, 0, 1},
                       {1, 0, 1}, {-1, -1, 0}, {1, -1, 0}, {1, 1, 0}, {-1, 1, 0}, {0, 0, 0}}

    local angle_x, angle_y, angle_z = 0, 0, 0
    local old_pts = {}

    for frame = 1, 55 do
        if wait(0.01) then
            break
        end

        if frame == 30 then
            io.write("\x1b[18;28H ETAT: \x1b[7m BRECHE CRITIQUE! \x1b[0m")
            play_game_sound("damage")
        end

        for _, p in ipairs(old_pts) do
            io.write(string.format("\x1b[%d;%dH ", p.y, p.x))
        end

        local new_pts_map = {}
        local new_pts = {}

        for i, p in ipairs(points_3d) do
            local x, y, z = p[1], p[2], p[3]

            local xy = y * math.cos(angle_x) - z * math.sin(angle_x)
            local xz = z * math.cos(angle_x) + y * math.sin(angle_x)
            local yx = x * math.cos(angle_y) - xz * math.sin(angle_y)
            local yz = xz * math.cos(angle_y) + x * math.sin(angle_y)
            local zx = yx * math.cos(angle_z) - xy * math.sin(angle_z)
            local zy = xy * math.cos(angle_z) + yx * math.sin(angle_z)

            local sx = math.floor(40 + zx * 8)
            local sy = math.floor(10 + zy * 4)

            if sx >= 1 and sx <= 80 and sy >= 1 and sy <= 24 then
                local key = sy * 1000 + sx
                if not new_pts_map[key] then
                    new_pts_map[key] = true
                    local char = (i == 21) and "@" or "*"
                    table.insert(new_pts, {
                        x = sx,
                        y = sy,
                        c = char
                    })
                end
            end
        end

        for _, p in ipairs(new_pts) do
            io.write(string.format("\x1b[%d;%dH%s", p.y, p.x, p.c))
        end
        io.flush()

        old_pts = new_pts
        angle_x = angle_x + 0.12
        angle_y = angle_y + 0.18
        angle_z = angle_z + 0.08

        if wait(0.06) then
            break
        end
    end

    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)
    for i = 1, 3 do
        if skip_intro then
            break
        end
        io.write("\x1b[7m\x1b[2J\x1b[12;30H ERREUR FATALE \x1b[0m")
        io.flush()
        play_game_sound("hit")
        wait(0.15)
        io.write("\x1b[0m\x1b[2J")
        io.flush()
        wait(0.15)
    end

    local msg1 = "LE VERROU EST BRISE. VOTRE CONSCIENCE EST ASPIREE."
    local msg2 = "PLONGEZ DANS LES NOEUDS DU RESEAU POUR SURVIVRE."

    for frame = 1, 15 do
        if skip_intro then
            break
        end
        io.write("\x1b[10;15H")
        for i = 1, #msg1 do
            io.write(string.char(math.random(65, 90)))
        end
        io.write("\x1b[12;16H")
        for i = 1, #msg2 do
            io.write(string.char(math.random(65, 90)))
        end
        io.flush()
        play_game_sound("hit")
        wait(0.05)
    end

    io.write("\x1b[10;15H\x1b[1m" .. msg1 .. "\x1b[0m")
    io.write("\x1b[12;16H\x1b[1m" .. msg2 .. "\x1b[0m")
    io.write("\x1b[18;18H\x1b[7m APPUYEZ SUR ESPACE POUR ACCEPTER VOTRE DESTIN \x1b[0m")
    io.flush()

    skip_intro = false
    play_game_sound("levelup")
    while not skip_intro do
        if wait(0.1) then
            return
        end
    end
end

-- =====================================================================
-- MENUS ET JEU PRINCIPAL
-- =====================================================================
local function draw_title(full_redraw)
    if full_redraw then
        io.write("\x1b[2J\x1b[H")
        io.flush()
        minitel.sleep(0.08)

        io.write("\x1b[2;11H+----------------------------------------------------------+\r\n")
        io.write("\x1b[3;11H| // CONNEXION SECURISEE ----------- BAUDS: 9600 //        |\r\n")
        io.write("\x1b[4;11H|==========================================================|\r\n")
        io.write("\x1b[5;11H|                                                          |\r\n")
        io.write("\x1b[6;11H|        __  __ ___ _  _ ___ _____ ___ _                   |\r\n")
        io.write("\x1b[7;11H|       |  \\/  |_ _| \\| |_ _|_   _| __| |                  |\r\n")
        io.write("\x1b[8;11H|       | |\\/| || || .` || |  | | | _|| |__                |\r\n")
        io.write("\x1b[9;11H|       |_|  |_|___|_|\\_|___| |_| |___|____|               |\r\n")
        io.write("\x1b[10;11H|                                                          |\r\n")
        io.write("\x1b[11;11H|            >  R P G : E N I G M A  <                     |\r\n")
        io.write("\x1b[12;11H|                                                          |\r\n")
        io.write("\x1b[13;11H|==========================================================|\r\n")
        io.write("\x1b[14;11H| SYS.OP : LOCALHOST                  STATUS : INFECTE     |\r\n")
        io.write("\x1b[15;11H+----------------------------------------------------------+\r\n")
    end

    local b_jouer = (title_cursor == 1) and "\x1b[7m [ INITIALISER SYSTEME ] \x1b[0m" or "   INITIALISER SYSTEME   "
    local b_param = (title_cursor == 2) and "\x1b[7m [ CONFIGURATION MATERIELLE ] \x1b[0m" or
                        "   CONFIGURATION MATERIELLE   "
    local b_quit = (title_cursor == 3) and "\x1b[7m [ DECONNEXION ] \x1b[0m" or "   DECONNEXION   "

    io.write("\x1b[17;1H\x1b[K\x1b[17;28H" .. b_jouer .. "\r\n")
    io.write("\x1b[19;1H\x1b[K\x1b[19;25H" .. b_param .. "\r\n")
    io.write("\x1b[21;1H\x1b[K\x1b[21;32H" .. b_quit .. "\r\n")

    io.write("\x1b[23;14H ZQSD / FLECHES : NAVIGUER  |  ESPACE / ENTREE : VALIDER \r\n")
    io.flush()
end

local function draw_settings()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    io.write("\x1b[4;25H\x1b[7m CONFIGURATION MATERIELLE \x1b[0m\r\n\n")

    local opts = {{
        name = "INTEGRITE (INT) DEPART",
        key = "START_HP",
        format = "%d"
    }, {
        name = "MENACES AU NOEUD 1",
        key = "BASE_ENEMIES",
        format = "%d"
    }, {
        name = "TAUX DE REPLICATION",
        key = "ENEMY_MULT",
        format = "%.1f"
    }, {
        name = "PATCHS SUR LE RESEAU",
        key = "POTIONS",
        format = "%d"
    }, {
        name = "DENSITE DES DONNEES (%)",
        key = "MAP_DENSITY",
        format = "%d %%"
    }, {
        name = "RETOUR (COMPILER)",
        key = nil
    }}

    for i, o in ipairs(opts) do
        local line = string.format("\x1b[%d;15H", 7 + (i * 2))
        if i == settings_cursor then
            line = line .. "\x1b[7m> " .. o.name
        else
            line = line .. "  " .. o.name
        end

        if o.key then
            local val_str = string.format(o.format, config[o.key])
            if i == settings_cursor then
                line = line .. string.rep(" ", 32 - string.len(o.name)) .. "[< " .. val_str .. " >]\x1b[0m"
            else
                line = line .. string.rep(" ", 32 - string.len(o.name)) .. "   " .. val_str .. "   \x1b[0m"
            end
        else
            line = line .. " \x1b[0m"
        end
        io.write(line .. "\r\n")
    end
    io.write("\x1b[22;12H FLECHES: MODIFIER & NAVIGUER  |  ESPACE/ENTREE: VALIDER ")
    io.flush()
end

local function modify_setting(dir)
    if settings_cursor == 1 then
        config.START_HP = math.max(10, math.min(100, config.START_HP + (5 * dir)))
    elseif settings_cursor == 2 then
        config.BASE_ENEMIES = math.max(0, math.min(30, config.BASE_ENEMIES + dir))
    elseif settings_cursor == 3 then
        config.ENEMY_MULT = math.max(0.0, math.min(5.0, config.ENEMY_MULT + (0.5 * dir)))
    elseif settings_cursor == 4 then
        config.POTIONS = math.max(0, math.min(20, config.POTIONS + dir))
    elseif settings_cursor == 5 then
        config.MAP_DENSITY = math.max(40, math.min(200, config.MAP_DENSITY + (10 * dir)))
    end
end

local function generate_map()
    local w, h = 60, 16
    local grid = {}

    for y = 1, h do
        grid[y] = {}
        for x = 1, w do
            grid[y][x] = "#"
        end
    end

    local rooms = {}
    local density_factor = config.MAP_DENSITY / 100.0
    local num_rooms = math.floor(math.random(4, 7) * density_factor)
    num_rooms = math.max(2, math.min(15, num_rooms))

    for i = 1, num_rooms do
        local rw = math.floor(math.random(6, 14) * density_factor)
        local rh = math.floor(math.random(4, 7) * density_factor)
        rw = math.max(3, math.min(20, rw))
        rh = math.max(3, math.min(10, rh))

        local rx = math.random(2, w - rw - 1)
        local ry = math.random(2, h - rh - 1)

        for y = ry, ry + rh - 1 do
            for x = rx, rx + rw - 1 do
                grid[y][x] = "."
            end
        end

        table.insert(rooms, {
            cx = math.floor(rx + rw / 2),
            cy = math.floor(ry + rh / 2)
        })

        if i > 1 then
            local prev = rooms[i - 1]
            local cx1, cy1 = prev.cx, prev.cy
            local cx2, cy2 = rooms[i].cx, rooms[i].cy

            if math.random() > 0.5 then
                for x = math.min(cx1, cx2), math.max(cx1, cx2) do
                    grid[cy1][x] = "."
                end
                for y = math.min(cy1, cy2), math.max(cy1, cy2) do
                    grid[y][cx2] = "."
                end
            else
                for y = math.min(cy1, cy2), math.max(cy1, cy2) do
                    grid[y][cx1] = "."
                end
                for x = math.min(cx1, cx2), math.max(cx1, cx2) do
                    grid[cy2][x] = "."
                end
            end
        end
    end

    local last = rooms[#rooms]
    grid[last.cy][last.cx] = ">"

    local first = rooms[1]
    p_x, p_y = first.cx, first.cy

    local final_map = {}
    for y = 1, h do
        final_map[y] = table.concat(grid[y])
    end
    return final_map
end

local function get_random_empty_pos(safe_x, safe_y, min_dist)
    while true do
        local rx = math.random(2, 59)
        local ry = math.random(2, 15)
        if string.sub(current_map[ry], rx, rx) == "." then
            if safe_x and safe_y and min_dist then
                local dist = math.abs(rx - safe_x) + math.abs(ry - safe_y)
                if dist >= min_dist then
                    return rx, ry
                end
            else
                if rx ~= p_x or ry ~= p_y then
                    return rx, ry
                end
            end
        end
    end
end

local function reshuffle_enemies()
    for _, e in ipairs(enemies) do
        if e.active then
            local nx, ny = get_random_empty_pos(p_x, p_y, 4)
            e.x, e.y = nx, ny
        end
    end
end

local function init_floor()
    current_map = generate_map()
    enemies = {}

    local num_enemies = math.floor(config.BASE_ENEMIES + (floor_depth * config.ENEMY_MULT))
    if num_enemies > CFG_MAX_ENEMIES then
        num_enemies = CFG_MAX_ENEMIES
    end

    for i = 1, num_enemies do
        local ex, ey = get_random_empty_pos(p_x, p_y, 4)
        local min_mob = math.min(#BESTIAIRE - 1, 1 + math.floor(floor_depth / 3))
        local max_mob = math.min(#BESTIAIRE, min_mob + 2)
        local t_idx = math.random(min_mob, max_mob)

        local template = BESTIAIRE[t_idx]
        local hp_calc = template.base_hp + (floor_depth * 3)
        local atk_calc = template.base_atk + (floor_depth)

        table.insert(enemies, {
            x = ex,
            y = ey,
            name = template.name,
            hp = hp_calc,
            max = hp_calc,
            atk = atk_calc,
            active = true
        })
    end

    items = {}
    local num_potions = math.max(1, config.POTIONS - math.floor(floor_depth / CFG_POTION_DECAY))
    for i = 1, num_potions do
        local ix, iy = get_random_empty_pos(p_x, p_y, 2)
        table.insert(items, {
            x = ix,
            y = iy,
            type = "HP",
            char = "+",
            active = true
        })
    end

    for i = 1, math.random(1, 2) do
        local ix, iy = get_random_empty_pos(p_x, p_y, 2)
        table.insert(items, {
            x = ix,
            y = iy,
            type = "ATK",
            char = "*",
            active = true
        })
    end
end

local function draw_hud()
    local x = 62
    io.write("\x1b[2;" .. x .. "H\x1b[7m   STATISTIQUES   \x1b[0m")
    io.write("\x1b[4;" .. x .. "H LVL   : " .. p_lvl .. "   ")
    io.write("\x1b[5;" .. x .. "H EXP   : " .. p_exp .. "/" .. (p_lvl * 10) .. "   ")
    io.write("\x1b[7;" .. x .. "H INT   : " .. p_hp .. "/" .. p_max .. "   ")
    io.write("\x1b[8;" .. x .. "H OVC   : +" .. p_atk .. "   ")
    io.write("\x1b[10;" .. x .. "H PURGES: " .. p_kills .. "   ")
    io.write("\x1b[12;" .. x .. "H NOEUD : - " .. floor_depth .. "   ")

    io.write("\x1b[15;" .. x .. "H\x1b[7m    CONTROLES     \x1b[0m")
    io.write("\x1b[16;" .. x .. "H ZQSD/FL : NAVIG.")
    io.write("\x1b[17;" .. x .. "H >       : PORT  ")
    io.write("\x1b[18;" .. x .. "H P       : ABORT ")
end

local function draw_msg()
    io.write("\x1b[19;1H\x1b[7m LOGS SYSTEME \x1b[0m==============================================")
    io.write("\x1b[20;1H\x1b[K  " .. map_msg)
end

local function draw_map()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    for y, row in ipairs(current_map) do
        io.write("\x1b[" .. y .. ";1H" .. row)
    end
    for _, it in ipairs(items) do
        if it.active then
            io.write("\x1b[" .. it.y .. ";" .. it.x .. "H" .. it.char)
        end
    end

    draw_hud()
    draw_msg()
    io.write("\x1b[" .. p_y .. ";" .. p_x .. "H\x1b[7m@\x1b[0m")
    io.flush()
end

local function trigger_combat(enemy_ref)
    state = "COMBAT"
    current_enemy = enemy_ref
    combat_cursor = 1
    msg_combat = "PROGRAMME " .. current_enemy.name .. " DETECTE !"

    skip_intro = false
    play_game_sound("hit")

    for i = 1, 3 do
        io.write("\x1b[7m\x1b[2J")
        io.flush()
        minitel.sleep(0.05)
        io.write("\x1b[0m\x1b[2J")
        io.flush()
        minitel.sleep(0.05)
    end
end

local function draw_combat(full_redraw)
    if full_redraw then
        io.write("\x1b[2J\x1b[H")
        io.flush()
        minitel.sleep(0.08)

        io.write("\x1b[4;32H      _-_   \r\n")
        io.write("\x1b[5;32H    /[X X]\\ \r\n")
        io.write("\x1b[6;32H   |   -   |\r\n")
        io.write("\x1b[7;32H    \\ === / \r\n")
        io.write("\x1b[8;32H     -----  \r\n")

        io.write("\x1b[15;1H================================================================================\r\n")
        io.write("\x1b[17;1H================================================================================\r\n")
    end

    io.write("\x1b[11;1H\x1b[K\x1b[11;24H " .. current_enemy.name .. " [ " .. current_enemy.hp .. " / " ..
                 current_enemy.max .. " INT ]")
    io.write("\x1b[16;2H* " .. msg_combat .. "\x1b[K")
    io.write("\x1b[19;1H\x1b[K\x1b[19;2H ROOT LVL " .. p_lvl .. " [ INT: " .. p_hp .. " / " .. p_max .. " ] | OVC: +" ..
                 p_atk)

    local b_rapide = (combat_cursor == 1) and "\x1b[7m [ INJECTION ] \x1b[0m" or "   INJECTION   "
    local b_lourd = (combat_cursor == 2) and "\x1b[7m [ OVERLOAD ] \x1b[0m" or "   OVERLOAD   "
    local b_soin = (combat_cursor == 3) and "\x1b[7m [ PATCHER ] \x1b[0m" or "   PATCHER   "
    local b_fuite = (combat_cursor == 4) and "\x1b[7m [ ABORT ] \x1b[0m" or "   ABORT   "

    io.write("\x1b[22;1H\x1b[K\x1b[22;5H" .. b_rapide .. "    " .. b_lourd .. "    " .. b_soin .. "    " .. b_fuite)
    io.flush()
end

-- =====================================================================
-- SEQUENCE DE DEMARRAGE
-- =====================================================================
math.randomseed(os.time())
play_intro()
skip_intro = false
draw_title(true)

-- BOUCLE PRINCIPALE
while true do
    local key = minitel.get_key()

    if (key == "p" or key == "P" or key == "RETOUR" or key == "ESC") and state ~= "TITLE" then
        if state == "SETTINGS" then
            save_config()
        end
        state = "TITLE"
        title_cursor = 1
        draw_title(true)
    else
        if state == "TITLE" then
            if key == "z" or key == "Z" or key == "UP" then
                title_cursor = title_cursor - 1
                if title_cursor < 1 then
                    title_cursor = 3
                end
                draw_title(false)
            elseif key == "s" or key == "S" or key == "DOWN" then
                title_cursor = title_cursor + 1
                if title_cursor > 3 then
                    title_cursor = 1
                end
                draw_title(false)
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                play_game_sound("hit")
                if title_cursor == 1 then
                    floor_depth = 1
                    p_hp, p_max = config.START_HP, config.START_HP
                    p_lvl, p_exp = 1, 0
                    p_kills = 0
                    p_atk = 0
                    map_msg = "CONNEXION REUSSIE ! TROUVEZ LA PASSERELLE."
                    init_floor()
                    draw_map()
                    state = "MAP"
                elseif title_cursor == 2 then
                    state = "SETTINGS"
                    settings_cursor = 1
                    draw_settings()
                elseif title_cursor == 3 then
                    break
                end
            end
            minitel.sleep(0.05)

        elseif state == "SETTINGS" then
            if key == "z" or key == "Z" or key == "UP" then
                settings_cursor = settings_cursor - 1
                if settings_cursor < 1 then
                    settings_cursor = 6
                end
                draw_settings()
            elseif key == "s" or key == "S" or key == "DOWN" then
                settings_cursor = settings_cursor + 1
                if settings_cursor > 6 then
                    settings_cursor = 1
                end
                draw_settings()
            elseif key == "q" or key == "Q" or key == "LEFT" then
                modify_setting(-1)
                draw_settings()
            elseif key == "d" or key == "D" or key == "RIGHT" then
                modify_setting(1)
                draw_settings()
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                play_game_sound("hit")
                if settings_cursor == 6 then
                    save_config()
                    state = "TITLE"
                    draw_title(true)
                end
            end
            minitel.sleep(0.05)

        elseif state == "MAP" then
            local next_x, next_y = p_x, p_y
            local moved = false

            if key == "z" or key == "Z" or key == "UP" then
                next_y = p_y - 1
                moved = true
            end
            if key == "s" or key == "S" or key == "DOWN" then
                next_y = p_y + 1
                moved = true
            end
            if key == "q" or key == "Q" or key == "LEFT" then
                next_x = p_x - 1
                moved = true
            end
            if key == "d" or key == "D" or key == "RIGHT" then
                next_x = p_x + 1
                moved = true
            end

            if moved then
                local hit_enemy = false
                for _, e in ipairs(enemies) do
                    if e.active and e.x == next_x and e.y == next_y then
                        hit_enemy = true
                        trigger_combat(e)
                        draw_combat(true)
                        break
                    end
                end

                if not hit_enemy then
                    local map_row = current_map[next_y]
                    local char_under = string.sub(map_row, next_x, next_x)

                    if char_under == "#" then
                        -- MUR
                    elseif char_under == ">" then
                        floor_depth = floor_depth + 1
                        map_msg = "CONNEXION AU NOEUD -" .. floor_depth .. ". LA SECURITE AUGMENTE."
                        play_game_sound("pickup")
                        init_floor()
                        draw_map()
                    else
                        for _, it in ipairs(items) do
                            if it.active and it.x == next_x and it.y == next_y then
                                it.active = false
                                play_game_sound("pickup")
                                if it.type == "HP" then
                                    local heal = math.random(CFG_HEAL_MIN, CFG_HEAL_MAX)
                                    p_hp = math.min(p_max, p_hp + heal)
                                    map_msg = "VOUS APPLIQUEZ UN PATCH DE CODE (+ " .. heal .. " INT)."
                                elseif it.type == "ATK" then
                                    p_atk = p_atk + 1
                                    map_msg = "CYCLES PROCESSEUR AUGMENTES (OVC +1) !"
                                end
                                draw_hud()
                                draw_msg()
                                break
                            end
                        end

                        io.write("\x1b[" .. p_y .. ";" .. p_x .. "H.")
                        p_x, p_y = next_x, next_y
                        io.write("\x1b[" .. p_y .. ";" .. p_x .. "H\x1b[7m@\x1b[0m")
                        io.flush()
                    end
                end
            end
            minitel.sleep(0.02)

        elseif state == "COMBAT" then
            if key == "q" or key == "Q" or key == "LEFT" then
                combat_cursor = combat_cursor - 1
                if combat_cursor < 1 then
                    combat_cursor = 4
                end
                draw_combat(false)
            elseif key == "d" or key == "D" or key == "RIGHT" then
                combat_cursor = combat_cursor + 1
                if combat_cursor > 4 then
                    combat_cursor = 1
                end
                draw_combat(false)
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                if combat_cursor == 1 then
                    if math.random() < 0.95 then
                        local dmg = math.random(4, 7) + p_lvl + p_atk
                        current_enemy.hp = current_enemy.hp - dmg
                        msg_combat = "INJECTION REUSSIE ! L'ENNEMI PERD " .. dmg .. " INT."
                        play_game_sound("hit")
                    else
                        msg_combat = "INJECTION REPOUSSEE PAR LE PARE-FEU !"
                    end
                elseif combat_cursor == 2 then
                    if math.random() < 0.60 then
                        local dmg = math.random(9, 16) + p_lvl + (p_atk * 3)
                        current_enemy.hp = current_enemy.hp - dmg
                        msg_combat = "OVERLOAD CRITIQUE ! L'ENNEMI PERD " .. dmg .. " INT."
                        play_game_sound("hit")
                    else
                        msg_combat = "OVERLOAD ESQUIVE ! LA CONNEXION FLANCHE."
                    end
                elseif combat_cursor == 3 then
                    local heal = math.random(CFG_HEAL_MIN, CFG_HEAL_MAX)
                    p_hp = math.min(p_max, p_hp + heal)
                    msg_combat = "VOUS COMPILEZ UN PATCH. +" .. heal .. " INT."
                    play_game_sound("pickup")
                elseif combat_cursor == 4 then
                    if math.random() < 0.5 then
                        msg_combat = "VOUS COUPEZ LA CONNEXION !"
                        draw_combat(false)
                        minitel.sleep(1.5)
                        map_msg = "ABORT REUSSI. LES PROGRAMMES SE RECONFIGURENT."
                        reshuffle_enemies()
                        state = "MAP"
                        draw_map()
                    else
                        msg_combat = "ABORT ECHOUE ! PROCESSUS VERROUILLE."
                    end
                end

                if state == "COMBAT" then
                    draw_combat(false)
                    minitel.sleep(1.5)

                    if current_enemy.hp <= 0 then
                        p_kills = p_kills + 1
                        current_enemy.active = false
                        local xp_gained = math.random(5, 10) + floor_depth
                        p_exp = p_exp + xp_gained

                        if p_exp >= (p_lvl * 10) then
                            p_lvl = p_lvl + 1
                            p_max = p_max + 8
                            p_hp = p_max
                            p_exp = 0
                            msg_combat = "PROCESSUS PURGE ! NOUVEL ACCES ROOT (LVL " .. p_lvl .. ") !"
                            play_game_sound("levelup")
                        else
                            msg_combat = "PROCESSUS EFFACE ! +" .. xp_gained .. " EXP."
                            play_game_sound("pickup")
                        end

                        reshuffle_enemies()
                        draw_combat(false)
                        minitel.sleep(1.5)
                        state = "MAP"
                        map_msg = msg_combat
                        draw_map()
                    else
                        local e_dmg = current_enemy.atk + math.random(0, math.floor(floor_depth / 2))
                        p_hp = p_hp - e_dmg
                        msg_combat = current_enemy.name .. " RIPOSTE ! VOUS PERDEZ " .. e_dmg .. " INT."
                        play_game_sound("damage")
                        draw_combat(false)

                        if p_hp <= 0 then
                            state = "GAMEOVER"
                            io.write("\x1b[2J\x1b[H")
                            io.flush()
                            minitel.sleep(0.08)
                            io.write("\x1b[8;31H\x1b[7m SYSTEME CORROMPU \x1b[0m")
                            io.write("\x1b[11;26H PROFONDEUR ATTEINTE : NOEUD - " .. floor_depth .. " ")
                            io.write("\x1b[12;26H PROGRAMMES PURGES   : " .. p_kills .. " ")
                            io.write("\x1b[16;24H ESPACE / ENTREE / P : REBOOT SYSTEME ")
                            io.flush()
                            play_game_sound("gameover")
                        end
                    end
                end
            end
            minitel.sleep(0.05)

        elseif state == "GAMEOVER" then
            if key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                state = "TITLE"
                title_cursor = 1
                draw_title(true)
            end
            minitel.sleep(0.05)
        end
    end
end

minitel.cleanup()
