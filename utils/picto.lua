-- @TYPE: TELEMATIQUE / RESEAU
-- @DESC: Messagerie temps reel style PictoChat a 4 canaux (A, B, C, D) avec pseudos et dessins ASCII.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION & SAUVEGARDE DU SERVEUR / PSEUDO
-- =====================================================================
local CFG_FILE = "utils/pictochat.cfg"
local server_url = "http://127.0.0.1:8085"
local pseudo = "MINITEL"

local function load_config()
    local f = io.open(CFG_FILE, "r")
    if f then
        local s = f:read("*l")
        local p = f:read("*l")
        f:close()
        if s and s ~= "" then server_url = s end
        if p and p ~= "" then pseudo = p end
    end
end

local function save_config()
    local f = io.open(CFG_FILE, "w")
    if f then
        f:write(server_url .. "\n")
        f:write(pseudo .. "\n")
        f:close()
    end
end

load_config()

-- =====================================================================
-- ETAT DU SALON PICTOCHAT
-- =====================================================================
local ROOM_ORDER = {"A", "B", "C", "D"}
local current_room = "A"
local room_counts = { A = 0, B = 0, C = 0, D = 0 }
local room_users = ""
local messages = {}      -- Stocke les messages du salon actif
local MAX_VISIBLE = 14   -- Lignes 6 a 19 pour les messages
local last_id = 0

local input_buf = ""
local poll_in_flight = false
local last_poll_time = 0
local POLL_FILE = "/tmp/picto_poll.txt"

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

local function urlencode(str)
    str = tostring(str or "")
    str = str:gsub("\n", " "):gsub("\r", "")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- =====================================================================
-- AFFICHAGE DELTA-DRAWING (9600 BAUDS - ZERO CLIGNOTEMENT)
-- =====================================================================
local function draw_room_tabs()
    local tabs = {}
    for _, r in ipairs(ROOM_ORDER) do
        local cnt = room_counts[r] or 0
        local label = string.format(" SALLE %s (%d) ", r, cnt)
        if r == current_room then
            table.insert(tabs, "\x1b[7m>" .. label .. "<\x1b[0m")
        else
            table.insert(tabs, " " .. label .. " ")
        end
    end
    io.write("\x1b[3;4H" .. table.concat(tabs, "   "))
end

local function draw_messages_area()
    local start_idx = math.max(1, #messages - MAX_VISIBLE + 1)
    for slot = 1, MAX_VISIBLE do
        local y = 5 + slot
        local m = messages[start_idx + slot - 1]
        if m then
            local u_tag = minitel.pad(m.user, 10)
            local txt = minitel.pad(m.text, 54)
            if m.user == "SYSTEME" then
                io.write(string.format("\x1b[%d;3H %s \x1b[7m %-10s \x1b[0m %s", y, m.time, u_tag, txt))
            elseif m.user == pseudo then
                io.write(string.format("\x1b[%d;3H %s \x1b[1m<%-10s>\x1b[0m %s", y, m.time, u_tag, txt))
            else
                io.write(string.format("\x1b[%d;3H %s [%-10s] %s", y, m.time, u_tag, txt))
            end
        else
            io.write(string.format("\x1b[%d;3H%s", y, string.rep(" ", 76)))
        end
    end
end

local function draw_input_line()
    local u_prompt = string.format("[%s] > ", pseudo)
    local max_input_w = 74 - #u_prompt
    local disp = string.sub(input_buf, math.max(1, #input_buf - max_input_w + 1))
    local padded = minitel.pad(disp, max_input_w)
    io.write(string.format("\x1b[22;3H\x1b[1m%s\x1b[0m\x1b[7m%s\x1b[0m", u_prompt, padded))
end

local function draw_static_ui()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    local top_title = string.format("3615 PICTO - SALON TELEMATIQUE (%s)", string.sub(server_url, 1, 34))
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top_title, 80) .. "\x1b[0m")

    minitel.draw_window(2, 2, 78, 3, "")
    draw_room_tabs()

    minitel.draw_window(2, 5, 78, 16, "FLUX EN DIRECT - CANAL " .. current_room)
    minitel.draw_window(2, 21, 78, 3, "")

    io.write("\x1b[24;1H\x1b[7m [SUITE] CHANGER SALLE | /A..D SALLES | /QUI CONNECTES | /P1..3 DESSIN | [ESC] \x1b[0m")

    draw_messages_area()
    draw_input_line()
    io.flush()
end

-- =====================================================================
-- RESEAU ASYNCHRONE NON-BLOQUANT (POLLING EN TACHE DE FOND)
-- =====================================================================
local function start_async_poll()
    if poll_in_flight then return end
    poll_in_flight = true
    local url = string.format("%s/api/poll?room=%s&since=%d&user=%s&fmt=minitel",
        server_url, current_room, last_id, urlencode(pseudo))
    -- On ecrit dans un fichier .tmp puis on le renomme atomiquement quand curl a fini !
    local cmd = string.format("(curl -sL -k -m 4 '%s' > %s.tmp 2>/dev/null && mv %s.tmp %s) &",
        url, POLL_FILE, POLL_FILE, POLL_FILE)
    os.execute(cmd)
end

local function check_async_poll_result()
    local f = io.open(POLL_FILE, "r")
    if not f then return end

    local content = f:read("*a")
    f:close()
    os.remove(POLL_FILE)
    poll_in_flight = false
    last_poll_time = get_mono_time()

    if not content or content == "" then return end

    local tabs_changed = false
    local new_msgs = 0

    for line in content:gmatch("[^\r\n]+") do
        local kind = line:match("^(%u+)|")
        if kind == "META" then
            local ca, cb, cc, cd, ulist = line:match("^META|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
            if ca then
                ca, cb, cc, cd = tonumber(ca), tonumber(cb), tonumber(cc), tonumber(cd)
                if ca ~= room_counts.A or cb ~= room_counts.B or cc ~= room_counts.C or cd ~= room_counts.D then
                    room_counts.A, room_counts.B, room_counts.C, room_counts.D = ca, cb, cc, cd
                    tabs_changed = true
                end
                room_users = (ulist and ulist ~= "") and ulist or pseudo
            end
        elseif kind == "MSG" then
            local mid, mtime, muser, mtxt = line:match("^MSG|(%d+)|(.-)|(.-)|(.*)$")
            if mid then
                mid = tonumber(mid)
                if mid > last_id then
                    last_id = mid
                    table.insert(messages, {
                        id = mid,
                        time = mtime,
                        user = muser,
                        text = mtxt
                    })
                    if #messages > 40 then table.remove(messages, 1) end
                    new_msgs = new_msgs + 1
                end
            end
        end
    end

    if tabs_changed then draw_room_tabs() end
    if new_msgs > 0 then
        minitel.play_sound("hit")
        draw_messages_area()
    end
    if tabs_changed or new_msgs > 0 then
        io.flush()
    end
end

local function send_message(txt)
    local url = string.format("%s/api/send?room=%s&user=%s&msg=%s",
        server_url, current_room, urlencode(pseudo), urlencode(txt))
    os.execute(string.format("curl -sL -k -m 4 -X POST '%s' >/dev/null 2>&1 &", url))
end

local function switch_room(new_room)
    if new_room == current_room then return end
    current_room = new_room
    messages = {}
    last_id = 0
    os.remove(POLL_FILE)
    poll_in_flight = false
    minitel.play_sound("pickup")
    draw_static_ui()
    start_async_poll()
end

-- =====================================================================
-- PICTOS ASCII PREDEFINIS (/P1, /P2, /P3)
-- =====================================================================
local PICTOS = {
    ["/P1"] = "[PICTO MINITEL] .---. |[_]| '==='",
    ["/P2"] = "[PAUSE CAFE]  ( (  c[_]  BON CAFE A TOUS !",
    ["/P3"] = "[SALUT !]  \\(^_^)/  3615 MAGIS CLUB EN LIGNE !"
}

-- =====================================================================
-- INITIALISATION : CHOIX DU SERVEUR & DU PSEUDO
-- =====================================================================
os.remove(POLL_FILE)
io.write("\x1b[r\x1b[2J\x1b[H")
io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 PICTO - CONNEXION AU SALON MULTICANAL  * * *", 80) .. "\x1b[0m")

local ask_srv = minitel.input_box("SERVEUR PICTOCHAT", "URL du serveur (ex: https://chat.domaine.fr) :", server_url, 42)
if not ask_srv or ask_srv == "" then
    minitel.cleanup()
    os.exit()
end
server_url = ask_srv:gsub("/+$", "")

local ask_p = minitel.input_box("CHOIX DU PSEUDO", "Votre pseudo dans les salons (10 car. max) :", pseudo, 10)
if not ask_p or ask_p == "" then
    minitel.cleanup()
    os.exit()
end
pseudo = string.upper(minitel.clean_accents(ask_p)):gsub("[^%w_%-]", "")
if pseudo == "" then pseudo = "MINITEL" end
save_config()

draw_static_ui()
start_async_poll()

-- =====================================================================
-- BOUCLE PRINCIPALE TEMPS REEL
-- =====================================================================
while true do
    -- 1. Verifie si une reponse du serveur est arrivee en tache de fond
    check_async_poll_result()

    -- 2. Relance un poll toutes les 1.8 secondes si aucun n'est en cours
    local now = get_mono_time()
    if not poll_in_flight and (now - last_poll_time >= 1.8) then
        start_async_poll()
    end

    -- 3. Lecture instantanee du clavier Minitel
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" then
            if minitel.confirm_box("DECONNEXION", "Quitter le salon 3615 PICTO et revenir au portail ?") then
                break
            end
            draw_static_ui()

        elseif k == "SUITE" then
            -- Bascule rapidement de Salle A -> B -> C -> D -> A
            local next_map = { A = "B", B = "C", C = "D", D = "A" }
            switch_room(next_map[current_room] or "A")

        elseif k == "REPETITION" then
            draw_static_ui()

        elseif k == "ANNULATION" then
            input_buf = ""
            draw_input_line()
            io.flush()

        elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
            if #input_buf > 0 then
                input_buf = string.sub(input_buf, 1, -2)
                draw_input_line()
                io.flush()
            end

        elseif k == "ENVOI" or k == "\r" or k == "\n" then
            local cmd_up = string.upper(input_buf:gsub("^%s+", ""):gsub("%s+$", ""))
            input_buf = ""
            draw_input_line()
            io.flush()

            if cmd_up == "/A" or cmd_up == "/B" or cmd_up == "/C" or cmd_up == "/D" then
                switch_room(string.sub(cmd_up, 2, 2))

            elseif cmd_up == "/QUI" then
                minitel.msg_box("CONNECTES SALLE " .. current_room, "Utilisateurs actifs : " .. (room_users ~= "" and room_users or pseudo), "pickup")
                draw_static_ui()

            elseif cmd_up == "/PSEUDO" then
                local np = minitel.input_box("CHANGER DE PSEUDO", "Nouveau pseudo (10 car. max) :", pseudo, 10)
                if np and np ~= "" then
                    pseudo = string.upper(minitel.clean_accents(np)):gsub("[^%w_%-]", "")
                    save_config()
                end
                draw_static_ui()

            elseif cmd_up == "/SERVEUR" then
                local ns = minitel.input_box("CHANGER DE SERVEUR", "URL du serveur :", server_url, 42)
                if ns and ns ~= "" then
                    server_url = ns:gsub("/+$", "")
                    save_config()
                    messages = {}; last_id = 0
                end
                draw_static_ui()
                start_async_poll()

            elseif PICTOS[cmd_up] then
                send_message(PICTOS[cmd_up])
                last_poll_time = 0

            elseif cmd_up ~= "" then
                send_message(cmd_up)
                last_poll_time = 0 -- Force un rafraichissement rapide
            end

        elseif string.match(k, "^[%w%s%p_%.%-]$") and #k == 1 then
            if #input_buf < 58 then
                input_buf = input_buf .. k
                draw_input_line()
                io.flush()
            end
        end
    end

    minitel.sleep(0.02)
end

os.remove(POLL_FILE)
minitel.cleanup()