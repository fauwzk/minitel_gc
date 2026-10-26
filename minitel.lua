-- Fichier : minitel.lua
-- SDK & Moteur Système (Compatible Minitel 9600 Bauds & PC + Framebuffer & Pastebin Print)

local M = {}

local is_pc = true
local f_check = io.open("/dev/ttyUSB0", "r")
if f_check then
    f_check:close()
    is_pc = false
end

-- =====================================================================
-- 0. FRAMEBUFFER VIRTUEL 80x24 (CAPTURE D'ECRAN EN TEMPS REEL)
-- =====================================================================
local orig_write = io.write
local vram = {}
local cur_x, cur_y = 1, 1
local saved_x, saved_y = 1, 1
local ansi_buf = ""
local in_escape = false

local function clear_vram()
    for y = 1, 24 do
        vram[y] = {}
        for x = 1, 80 do vram[y][x] = " " end
    end
    cur_x, cur_y = 1, 1
end
clear_vram()

local function process_ansi_sequence(seq)
    local cmd = string.sub(seq, -1)
    local body = string.sub(seq, 2, -2)

    if seq == "7" or seq == "[s" then
        saved_x, saved_y = cur_x, cur_y
    elseif seq == "8" or seq == "[u" then
        cur_x, cur_y = saved_x, saved_y
    elseif cmd == "J" then
        if body:find("2") then clear_vram() end
    elseif cmd == "H" or cmd == "f" then
        local r, c = body:match("^(%d+);(%d+)$")
        if r and c then
            cur_y = math.max(1, math.min(24, tonumber(r)))
            cur_x = math.max(1, math.min(80, tonumber(c)))
        else
            cur_x, cur_y = 1, 1
        end
    elseif cmd == "K" then
        if vram[cur_y] then
            for x = cur_x, 80 do vram[cur_y][x] = " " end
        end
    elseif cmd == "A" then
        local n = tonumber(body) or 1
        cur_y = math.max(1, cur_y - n)
    elseif cmd == "B" then
        local n = tonumber(body) or 1
        cur_y = math.min(24, cur_y + n)
    elseif cmd == "C" then
        local n = tonumber(body) or 1
        cur_x = math.min(80, cur_x + n)
    elseif cmd == "D" then
        local n = tonumber(body) or 1
        cur_x = math.max(1, cur_x - n)
    end
end

local function feed_vram(str)
    for i = 1, #str do
        local c = string.sub(str, i, i)
        if in_escape then
            ansi_buf = ansi_buf .. c
            if #ansi_buf == 1 then
                if c == "7" or c == "8" then
                    process_ansi_sequence(ansi_buf)
                    in_escape = false
                    ansi_buf = ""
                elseif c ~= "[" and c ~= "?" then
                    in_escape = false
                    ansi_buf = ""
                end
            else
                if c:match("[a-zA-Z~]") then
                    process_ansi_sequence(ansi_buf)
                    in_escape = false
                    ansi_buf = ""
                end
            end
        else
            if c == "\x1b" then
                in_escape = true
                ansi_buf = ""
            elseif c == "\r" then
                cur_x = 1
            elseif c == "\n" then
                cur_y = math.min(24, cur_y + 1)
            elseif c == "\x08" then
                cur_x = math.max(1, cur_x - 1)
            elseif string.byte(c) >= 32 then
                if cur_y >= 1 and cur_y <= 24 and cur_x >= 1 and cur_x <= 80 then
                    vram[cur_y][cur_x] = c
                end
                cur_x = cur_x + 1
            end
        end
    end
end

-- Surcharge transparente de io.write pour alimenter le Framebuffer
io.write = function(...)
    local args = {...}
    for _, v in ipairs(args) do
        feed_vram(tostring(v))
    end
    return orig_write(...)
end

-- Retourne le contenu actuel de l'ecran 80x24 sous forme de texte
function M.get_screen_text()
    local lines = {}
    table.insert(lines, "+--------------------------------------------------------------------------------+")
    for y = 1, 24 do
        local row_str = table.concat(vram[y])
        table.insert(lines, "|" .. row_str .. "|")
    end
    table.insert(lines, "+--------------------------------------------------------------------------------+")
    table.insert(lines, "Capture realisee depuis 3615 MAGIS CLUB le " .. os.date("%d/%m/%Y a %H:%M:%S"))
    return table.concat(lines, "\n")
end

-- =====================================================================
-- 1. INITIALISATION & MATERIEL
-- =====================================================================
function M.init()
    if is_pc then
        os.execute("stty raw -echo min 0 time 0 2>/dev/null")
    else
        os.execute("stty -F /dev/ttyUSB0 9600 cs8 -parenb -cstopb raw -echo -icanon min 0 time 0 2>/dev/null")
        os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
    end
    orig_write("\x1b[?25l")
    io.flush()
end

function M.cleanup()
    orig_write("\x1b[r\x1b[0m\x1b[?25h\x1b[2J\x1b[H")
    io.flush()
    clear_vram()
    if is_pc then
        os.execute("stty sane 2>/dev/null")
    else
        os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
        os.execute("stty sane 2>/dev/null")
    end
end

-- =====================================================================
-- SON : BIP DU MINITEL (CARACTERE BEL) ET SYNTHESE SOX DU RASPBERRY PI
-- =====================================================================
-- Le buzzer du Magis Club n'a qu'une note : les effets se distinguent par
-- leur rythme. Les bips sont planifies et emis au fil des appels a get_key()
-- et sleep() : un motif ne bloque jamais le programme.
-- Le Magis Club ignore les bips trop rapproches : tous les motifs sont
-- construits a partir d'un ecart minimal entre deux bips, mesure a l'oreille
-- avec le calibrage de l'outil AUDIO.
--   Fichier ~/.minitel_son (hors du depot) : ligne 1 = mode ("bip", "sox",
--   "les2", "aucun"), ligne 2 = ecart minimal en secondes
local SOUND_FILE = (os.getenv("HOME") or "/tmp") .. "/.minitel_son"
local SOUND_MODES = { bip = true, sox = true, les2 = true, aucun = true }
local DEFAULT_GAP = 0.25 -- mesure par calibrage sur un Magis Club

local function read_sound_settings()
    local f = io.open(SOUND_FILE, "r")
    local m, g
    if f then m = f:read("*l"); g = tonumber(f:read("*l") or ""); f:close() end
    if not SOUND_MODES[m] then m = "les2" end
    if not g or g < 0.05 or g > 2 then g = DEFAULT_GAP end
    return m, g
end
M.sound_mode, M.bip_gap = read_sound_settings()

local function save_sound_settings()
    local f = io.open(SOUND_FILE, "w")
    if f then f:write(M.sound_mode .. "\n" .. M.bip_gap .. "\n"); f:close() end
end

-- Motifs : instants des bips, en secondes depuis le debut de l'effet, en
-- multiples de l'ecart minimal g
local function build_patterns(g)
    return {
        hit    = { 0 },                       -- un bip : validation, action
        blip   = { 0 },
        pickup = { 0, g },                    -- deux bips : objet, bonus
        damage = { 0, g, 2 * g },             -- trois bips au plus vite : choc
        lose   = { 0, 2.5 * g, 5 * g },       -- trois bips lents : echec
        win    = { 0, g, 2 * g, 4 * g },      -- trois bips, un silence, un bip : victoire
    }
end
M.BIP_PATTERNS = build_patterns(M.bip_gap)

function M.set_sound_mode(mode)
    if not SOUND_MODES[mode] then return false end
    M.sound_mode = mode
    save_sound_settings()
    return true
end

function M.set_bip_gap(gap)
    M.bip_gap = gap
    M.BIP_PATTERNS = build_patterns(gap)
    save_sound_settings()
end

local function mono_time()
    local f = io.open("/proc/uptime", "r")
    if f then
        local up = tonumber((f:read("*l") or ""):match("^([%d%.]+)"))
        f:close()
        if up then return up end
    end
    return os.clock()
end

local bip_queue = {}   -- instants (temps monotone) des bips a venir, tries

local function bel()
    orig_write("\a")
    io.flush()
end

-- Emet les bips dont l'heure est venue ; ceux qui ont trop de retard sont
-- abandonnes plutot que joues en rafale
local function pump_bips()
    if #bip_queue == 0 then return end
    local now = mono_time()
    while bip_queue[1] and bip_queue[1] <= now do
        local t = table.remove(bip_queue, 1)
        if now - t < 0.25 then bel() end
    end
end

-- Joue un motif de bips (liste d'instants) a la suite de ceux en attente
function M.beep_pattern(pattern)
    local now = mono_time()
    local last = bip_queue[#bip_queue]
    local start = last and math.max(now, last + M.bip_gap) or now
    for _, dt in ipairs(pattern) do table.insert(bip_queue, start + dt) end
    pump_bips()
end

function M.sleep(seconds)
    -- Les bips planifies pendant la pause partent a l'heure
    while bip_queue[1] do
        local wait = bip_queue[1] - mono_time()
        if wait >= seconds then break end
        if wait > 0 then M.sleep_raw(wait); seconds = seconds - wait end
        pump_bips()
    end
    M.sleep_raw(seconds)
end

function M.sleep_raw(seconds)
    if seconds <= 0 then return end
    local ok = os.execute(string.format("sleep %.3f 2>/dev/null", seconds))
    if not ok then
        local t0 = os.clock()
        while os.clock() - t0 <= seconds do end
    end
end

function M.play_sound(effect)
    local mode = M.sound_mode
    if mode == "aucun" then return end
    if mode == "bip" or mode == "les2" then
        M.beep_pattern(M.BIP_PATTERNS[effect] or M.BIP_PATTERNS.hit)
    end
    if mode == "bip" then return end

    local freq_cmd, dur, wave = "880", "0.05", "square"
    if effect == "win" or effect == "pickup" then
        wave = "square"; dur = "0.15"; freq_cmd = "440-1200"
    elseif effect == "lose" or effect == "damage" then
        wave = "sawtooth"; dur = "0.3"; freq_cmd = "300-100"
    end
    os.execute(string.format("which play >/dev/null 2>&1 && (play -q -n synth %s %s %s >/dev/null 2>&1 &)", dur, wave, freq_cmd))
end

-- =====================================================================
-- MODE DU MINITEL : 40 COLONNES (VIDEOTEX) OU 80 COLONNES (TELEINFORMATIQUE)
-- =====================================================================
-- Le Minitel s'allume en Videotex 40 colonnes, ou il obeit aux commandes de
-- protocole PRO1/PRO2/PRO3 (ESC 9, ESC :, ESC ;) et y repond. En mode
-- Teleinformatique 80 colonnes (VT100), il les ignore mais repond a la demande
-- de position du curseur ESC [ 6 n. Deux questions suffisent donc a savoir ou
-- il en est, et une commande PRO2 le fait passer en 80 colonnes.

-- En Videotex la liaison est en 7 bits + parite paire : le bit 8 de chaque
-- octet envoye porte la parite, et on l'enleve de ce que le Minitel repond.
local function videotex(seq)
    local out = {}
    for i = 1, #seq do
        local b, x, p = string.byte(seq, i), string.byte(seq, i), 0
        while x > 0 do p = p ~ (x & 1); x = x >> 1 end
        out[i] = string.char(b | (p << 7))
    end
    return table.concat(out)
end

-- Envoie une question et attend une reponse reconnue par le motif, au plus
-- `timeout` secondes. Rend la reponse (7 bits) ou nil.
local function ask_terminal(seq, pattern, timeout)
    while io.read(1) do end -- on vide ce qui trainait (touches, ancien echo)
    orig_write(seq)
    io.flush()
    local buf, t0 = "", mono_time()
    repeat
        local c = io.read(1)
        if c then
            buf = buf .. string.char(string.byte(c) & 0x7F)
            local found = string.match(buf, pattern)
            if found then return found end
        else
            M.sleep_raw(0.03)
        end
    until mono_time() - t0 > timeout
    return nil
end

-- Commande de protocole Videotex : d'abord en 7 bits + parite paire (1200
-- bauds), puis, sans acquittement, en 8 bits sans parite (9600 bauds)
local function pro_command(seq, pattern, timeout)
    local rep = ask_terminal(videotex(seq), pattern, timeout)
    if rep or videotex(seq) == seq then return rep end
    return ask_terminal(seq, pattern, timeout)
end

-- Rend "80" (Teleinformatique), "40" (Videotex), "mixte" (Videotex 80
-- colonnes) ou "inconnu" (rien n'a repondu : on ne peut pas trancher).
function M.detect_mode()
    if ask_terminal("\x1b[6n", "\x1b%[%d+;%d+R", 0.4) then return "80" end
    -- PRO1 STATUS FONCTIONNEMENT -> PRO2 REP STATUS (ESC : s octet)
    local rep = pro_command("\x1b\x39\x72", "\x1b\x3a\x73(.)", 0.5)
    -- En Teleinformatique, ESC 9 est ignore mais le "r" qui suit s'affiche
    orig_write("\r\x1b[K")
    io.flush()
    if not rep then return "inconnu" end
    if string.byte(rep) & 1 == 1 then return "mixte" end
    return "40"
end

-- Fait passer un Minitel en Videotex (40 colonnes ou mixte) en mode
-- Teleinformatique 80 colonnes, avec les reglages que l'ecran d'initialisation
-- fait taper a la main : sans echo local et avec le clavier etendu. Rend true
-- si le Minitel a confirme le changement de mode.
function M.switch_to_80(mode)
    if mode == "mixte" then
        -- pas de passage direct Mixte -> Teleinformatique : retour en Videotex
        pro_command("\x1b\x3a\x32\x7e", "\x1e\x71", 0.5)
    end
    -- PRO3 AIGUILLAGE OFF ECRAN <- MODEM : plus d'echo des touches a l'ecran
    pro_command("\x1b\x3b\x60\x58\x52", "\x1b\x3b..", 0.4)
    -- PRO3 START CLAVIER ETEN : clavier etendu (fleches, touches de fonction)
    pro_command("\x1b\x3b\x69\x59\x41", "\x1b\x3b..", 0.4)
    -- PRO2 TELINFO : passage en Teleinformatique, acquitte par CSI ? z
    local ok = pro_command("\x1b\x3a\x31\x7d", "\x1b%[%?z", 1.0) ~= nil or M.detect_mode() == "80"
    if ok then M.echo_off_80() end
    return ok
end

-- En Teleinformatique, l'echo local ne depend plus des aiguillages Videotex
-- (le Minitel le remet en changeant de mode) : on le coupe par le mode SRM de
-- la norme ISO 6429 / VT100, CSI 12 h, equivalent de Fnct T E.
function M.echo_off_80()
    orig_write("\x1b[12h")
    io.flush()
end

-- =====================================================================
-- 2. FONCTION D'IMPRESSION ECRAN VERS PASTEBIN (TOUCHE IMPRESSION / CTRL+P)
-- =====================================================================
local is_printing = false

function M.print_screen_to_pastebin()
    if is_printing then return end
    is_printing = true

    -- 1. Sauvegarde d'une copie de la VRAM avant d'afficher la popup d'attente
    local saved_vram = {}
    for y = 1, 24 do
        saved_vram[y] = {}
        for x = 1, 80 do saved_vram[y][x] = vram[y][x] end
    end
    local screen_dump = M.get_screen_text()

    -- 2. Enregistrement local dans screenshots/
    os.execute("mkdir -p screenshots 2>/dev/null")
    local filename = "screenshots/screen_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f_loc = io.open(filename, "w")
    if f_loc then
        f_loc:write(screen_dump .. "\n")
        f_loc:close()
    end

    -- 3. Fenetre d'envoi Pastebin (dessinee avec orig_write pour ne pas polluer la VRAM)
    M.play_sound("hit")
    orig_write("\x1b[9;16H\x1b[1m+\x1b[7m           IMPRESSION TELEMATIQUE EN COURS           \x1b[0m\x1b[1m+\x1b[0m")
    orig_write("\x1b[10;16H\x1b[1m|\x1b[0m                                                     \x1b[1m|\x1b[0m")
    orig_write("\x1b[11;16H\x1b[1m|\x1b[0m     ENVOI DE LA CAPTURE 80x24 VERS PASTEBIN...      \x1b[1m|\x1b[0m")
    orig_write("\x1b[12;16H\x1b[1m|\x1b[0m                                                     \x1b[1m|\x1b[0m")
    orig_write("\x1b[13;16H\x1b[1m+-----------------------------------------------------+\x1b[0m")
    io.flush()

    -- 4. Envoi via curl sur dpaste.com (ou fallback sur paste.rs)
    local paste_url = nil
    local cmd1 = string.format("curl -sL -m 8 -F 'content=<%s' -F 'syntax=text' -F 'expiry_days=30' https://dpaste.com/api/v2/ 2>/dev/null", filename)
    local p1 = io.popen(cmd1)
    if p1 then
        local res = p1:read("*a") or ""
        p1:close()
        res = res:gsub("%s+", "")
        if res:match("^https?://") then paste_url = res end
    end

    if not paste_url then
        local cmd2 = string.format("curl -sL -m 8 --data-binary @%s https://paste.rs/ 2>/dev/null", filename)
        local p2 = io.popen(cmd2)
        if p2 then
            local res = p2:read("*a") or ""
            p2:close()
            res = res:gsub("%s+", "")
            if res:match("^https?://") then paste_url = res end
        end
    end

    -- 5. Affichage du resultat (URL Pastebin + chemin local)
    if paste_url then
        M.play_sound("win")
        orig_write("\x1b[9;16H\x1b[1m+\x1b[7m             IMPRESSION PASTEBIN REUSSIE             \x1b[0m\x1b[1m+\x1b[0m")
        orig_write(string.format("\x1b[10;16H\x1b[1m|\x1b[0m LIEN : \x1b[1m%-44s\x1b[0m \x1b[1m|\x1b[0m", string.sub(paste_url, 1, 44)))
        orig_write(string.format("\x1b[11;16H\x1b[1m|\x1b[0m LOCAL: %-44s \x1b[1m|\x1b[0m", string.sub(filename, 1, 44)))
    else
        M.play_sound("lose")
        orig_write("\x1b[9;16H\x1b[1m+\x1b[7m           SAUVEGARDE LOCALE (HORS LIGNE)            \x1b[0m\x1b[1m+\x1b[0m")
        orig_write("\x1b[10;16H\x1b[1m|\x1b[0m Serveur Pastebin injoignable. Capture sauvee sous : \x1b[1m|\x1b[0m")
        orig_write(string.format("\x1b[11;16H\x1b[1m|\x1b[0m \x1b[1m%-51s\x1b[0m \x1b[1m|\x1b[0m", string.sub(filename, 1, 51)))
    end
    orig_write("\x1b[12;16H\x1b[1m|\x1b[0m             \x1b[7m [ENVOI / RETOUR] CONTINUER \x1b[0m            \x1b[1m|\x1b[0m")
    io.flush()

    while true do
        local k = M.get_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == " " then break end
        M.sleep(0.02)
    end

    -- 6. Restauration automatique de l'ecran a partir du Framebuffer !
    for y = 1, 24 do
        vram[y] = saved_vram[y]
        orig_write(string.format("\x1b[%d;1H%s", y, table.concat(vram[y])))
    end
    io.flush()
    is_printing = false
end

-- =====================================================================
-- 3. GESTION DU CLAVIER (AVEC DETECTION IMPRESSION VT100 / CTRL+P / F12)
-- =====================================================================
function M.get_key()
    pump_bips()
    local c = io.read(1)
    if not c then return nil end
    
    local function read_next()
        for i = 1, 50000 do 
            local n = io.read(1)
            if n then return n end
        end
        return nil
    end

    if c == "\r" or c == "\n" then return "ENVOI" end
    if c == "\x7f" or c == "\x08" then return "CORRECTION" end

    -- Ctrl+P (\x10) : Declenche l'impression Pastebin a tout moment !
    if c == "\x10" then
        M.print_screen_to_pastebin()
        return "REPETITION"
    end

    if c == "\x1b" then
        local seq1 = read_next()
        if not seq1 then return "RETOUR" end
        local seq2 = read_next()
        local full_seq = seq1 .. (seq2 or "")

        -- Sequence VT100 Media Copy / Impression (\x1b[i ou \x1bOp)
        if full_seq == "[i" or full_seq == "Op" or full_seq == "OP_PRINT" then
            M.print_screen_to_pastebin()
            return "REPETITION"
        end

        -- Flèches standards
        if full_seq == "[A" then return "UP" end
        if full_seq == "[B" then return "DOWN" end
        if full_seq == "[C" then return "RIGHT" end
        if full_seq == "[D" then return "LEFT" end
        if full_seq == "[H" then return "HOME" end
        if full_seq == "[F" then return "END" end
        
        -- Séquences à 3 ou 4 caractères (Suppr, PageUp/Down, F12, Print VT100 \x1b[0i / \x1b[2i)
        if seq1 == "[" and seq2 and seq2:match("%d") then
            local seq3 = read_next()
            if (seq2 == "0" or seq2 == "2" or seq2 == "4" or seq2 == "5") and seq3 == "i" then
                -- Touche Impression Minitel en mode VT100 (\x1b[0i ou \x1b[2i)
                M.print_screen_to_pastebin()
                return "REPETITION"
            end
            if seq2 == "2" and seq3 == "4" then
                read_next() -- consomme le '~' de F12 (\x1b[24~)
                M.print_screen_to_pastebin()
                return "REPETITION"
            end
            if seq2 == "3" and seq3 == "~" then return "CORRECTION" end
            if seq2 == "5" and seq3 == "~" then return "PAGE_UP" end
            if seq2 == "6" and seq3 == "~" then return "PAGE_DOWN" end
        end

        -- Touches de fonction PC (F1 à F4) & Touches spéciales Minitel
        if full_seq == "OP" or full_seq == "[11~" then return "SOMMAIRE" end
        if full_seq == "OQ" or full_seq == "[12~" then return "ANNULATION" end
        if full_seq == "OR" or full_seq == "[13~" then return "RETOUR" end
        if full_seq == "OS" or full_seq == "[14~" then return "REPETITION" end
        if full_seq == "Om" then return "GUIDE" end
        if full_seq == "Ol" then return "CORRECTION" end
        if full_seq == "On" then return "SUITE" end
        if full_seq == "OM" then return "ENVOI" end

        return "UNKNOWN_ESC"
    end
    return c
end

-- =====================================================================
-- 4. UTILITAIRES DE TEXTE ET FORMATAGE (80 COLONNES)
-- =====================================================================
function M.pad(str, len)
    str = tostring(str or "")
    if #str > len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

function M.center(str, len)
    str = tostring(str or "")
    if #str >= len then return string.sub(str, 1, len) end
    local left = math.floor((len - #str) / 2)
    local right = len - #str - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

function M.clean_accents(str)
    if not str then return "" end
    str = str:gsub("[éèêëÉÈÊË]", "E")
    str = str:gsub("[àâäÀÂÄ]", "A")
    str = str:gsub("[îïÎÏ]", "I")
    str = str:gsub("[ôöÔÖ]", "O")
    str = str:gsub("[ùûüÙÛÜ]", "U")
    str = str:gsub("[çÇ]", "C")
    str = str:gsub("œ", "OE"):gsub("’", "'")
    return str
end

function M.wrap(text, max_width, max_lines)
    local lines = {}
    local current = ""
    for word in tostring(text or ""):gmatch("%S+") do
        if #current + #word + 1 > max_width then
            table.insert(lines, M.pad(current, max_width))
            current = word
            if max_lines and #lines >= max_lines then break end
        else
            current = (current == "") and word or (current .. " " .. word)
        end
    end
    if (not max_lines or #lines < max_lines) and current ~= "" then
        table.insert(lines, M.pad(current, max_width))
    end
    if max_lines then
        while #lines < max_lines do
            table.insert(lines, string.rep(" ", max_width))
        end
    end
    return lines
end

-- =====================================================================
-- 5. PRIMITIVES GRAPHIQUES & COMPOSANTS UI (BOITES DE DIALOGUE)
-- =====================================================================
function M.draw_window(x, y, w, h, title)
    local inner_w = w - 2
    if title and title ~= "" then
        local t_str = " " .. string.sub(title, 1, inner_w - 2) .. " "
        io.write(string.format("\x1b[%d;%dH\x1b[1m+\x1b[0m\x1b[7m%s\x1b[0m\x1b[1m+\x1b[0m", y, x, M.center(t_str, inner_w)))
    else
        io.write(string.format("\x1b[%d;%dH\x1b[1m+%s+\x1b[0m", y, x, string.rep("-", inner_w)))
    end

    local empty_row = string.rep(" ", inner_w)
    for i = 1, h - 2 do
        io.write(string.format("\x1b[%d;%dH\x1b[1m|\x1b[0m%s\x1b[1m|\x1b[0m", y + i, x, empty_row))
    end
    io.write(string.format("\x1b[%d;%dH\x1b[1m+%s+\x1b[0m", y + h - 1, x, string.rep("-", inner_w)))
    io.flush()
end

function M.progress_bar(x, y, width, current, max, show_pct)
    local bar_w = show_pct and (width - 7) or (width - 2)
    if bar_w < 2 then bar_w = 2 end
    local ratio = math.max(0, math.min(1, current / math.max(1, max)))
    local filled = math.floor(ratio * bar_w + 0.5)
    local empty = bar_w - filled

    local bar = "[" .. "\x1b[7m" .. string.rep(" ", filled) .. "\x1b[0m" .. string.rep(".", empty) .. "]"
    if show_pct then
        bar = bar .. string.format(" %3d%%", math.floor(ratio * 100))
    end
    io.write(string.format("\x1b[%d;%dH%s", y, x, bar))
    io.flush()
end

function M.msg_box(title, message, sound_effect)
    if sound_effect then M.play_sound(sound_effect) end
    local w, h = 50, 8
    local x, y = 16, 8
    M.draw_window(x, y, w, h, title or "INFORMATION")

    local lines = M.wrap(message, w - 6, 3)
    for i = 1, #lines do
        io.write(string.format("\x1b[%d;%dH%s", y + 1 + i, x + 3, M.center(lines[i]:gsub("%s+$", ""), w - 6)))
    end

    io.write(string.format("\x1b[%d;%dH\x1b[7m [ENVOI] CONTINUER \x1b[0m", y + h - 2, x + 15))
    io.flush()

    while true do
        local k = M.get_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == "\r" or k == "\n" or k == " " then
            break
        end
        M.sleep(0.02)
    end
end

function M.confirm_box(title, question)
    M.play_sound("hit")
    local w, h = 50, 8
    local x, y = 16, 8
    M.draw_window(x, y, w, h, title or "CONFIRMATION")

    local lines = M.wrap(question, w - 6, 2)
    for i = 1, #lines do
        io.write(string.format("\x1b[%d;%dH%s", y + 1 + i, x + 3, M.center(lines[i]:gsub("%s+$", ""), w - 6)))
    end

    local choice = true
    local function draw_buttons()
        local b_oui = choice and "\x1b[7m > [ OUI ] < \x1b[0m" or "   [ OUI ]   "
        local b_non = (not choice) and "\x1b[7m > [ NON ] < \x1b[0m" or "   [ NON ]   "
        io.write(string.format("\x1b[%d;%dH%s      %s", y + 5, x + 9, b_oui, b_non))
        io.flush()
    end

    draw_buttons()

    while true do
        local k = M.get_key()
        if k == "LEFT" or k == "RIGHT" or k == "Q" or k == "q" or k == "D" or k == "d" then
            choice = not choice
            draw_buttons()
        elseif k == "O" or k == "o" then
            return true
        elseif k == "N" or k == "n" or k == "RETOUR" or k == "ESC" then
            return false
        elseif k == "ENVOI" or k == "\r" or k == "\n" or k == " " then
            return choice
        end
        M.sleep(0.02)
    end
end

function M.input_box(title, prompt, default_val, max_len)
    local w, h = 52, 8
    local x, y = 15, 8
    local limit = math.min(max_len or 36, 44)
    local str = tostring(default_val or "")

    M.draw_window(x, y, w, h, title or "SAISIE")
    io.write(string.format("\x1b[%d;%dH\x1b[1m%s\x1b[0m", y + 2, x + 3, M.pad(prompt or "VALEUR :", w - 6)))
    io.write(string.format("\x1b[%d;%dH[ENVOI] VALIDER  |  [ANNUL.] VIDER  |  [RETOUR] ESC", y + 6, x + 1))

    local function draw_field()
        local disp = string.sub(str, 1, limit)
        io.write(string.format("\x1b[%d;%dH> \x1b[7m %-44s \x1b[0m", y + 4, x + 2, disp))
        io.flush()
    end

    draw_field()

    while true do
        local k = M.get_key()
        if k then
            if k == "ENVOI" or k == "\r" or k == "\n" then
                return str
            elseif k == "RETOUR" or k == "ESC" then
                return nil
            elseif k == "ANNULATION" then
                str = ""
                draw_field()
            elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    draw_field()
                end
            elseif string.match(k, "^[%w%s%p_%.%-]$") and #k == 1 then
                if #str < limit then
                    str = str .. k
                    draw_field()
                end
            end
        end
        M.sleep(0.01)
    end
end

-- =====================================================================
-- 6. EXPLORATEUR DE FICHIERS SYSTEME (DELTA-DRAWING)
-- =====================================================================
function M.file_browser(mode, start_dir)
    local current_dir = start_dir or "./"
    if string.sub(current_dir, -1) ~= "/" then current_dir = current_dir .. "/" end

    local function scan_dir(path)
        local items, dirs, files = {}, {}, {}
        if path ~= "./" and path ~= "" and path ~= "/" then
            table.insert(items, { name = ".. (Dossier Parent)", is_dir = true, real_name = ".." })
        end
        
        local f = io.popen("\\ls -1p '" .. path .. "' 2>/dev/null")
        if f then
            for line in f:lines() do
                if string.sub(line, -1) == "/" then table.insert(dirs, string.sub(line, 1, -2))
                else table.insert(files, line) end
            end
            f:close()
        end
        
        for _, d in ipairs(dirs) do table.insert(items, { name = "[" .. d .. "]", is_dir = true, real_name = d }) end
        for _, file in ipairs(files) do table.insert(items, { name = file, is_dir = false, real_name = file }) end
        if #items == 0 then table.insert(items, { name = "(Dossier Vide)", is_dir = false, real_name = "" }) end
        return items
    end

    local items = scan_dir(current_dir)
    local cursor, list_offset, max_visible = 1, 0, 12
    local input_buffer = ""

    if mode == "SAVE" and items[1] and not items[1].is_dir and items[1].real_name ~= "" then
        input_buffer = items[1].real_name
    end

    local function draw_path_bar()
        io.write(string.format("\x1b[5;17H CHEMIN : \x1b[1m%-38s\x1b[0m", string.sub(current_dir, 1, 38)))
    end

    local function draw_input_box()
        if mode == "SAVE" then
            io.write(string.format("\x1b[20;24H\x1b[7m %-38s \x1b[0m", string.sub(input_buffer, 1, 38)))
        end
    end

    local function draw_single_row(slot)
        local idx = list_offset + slot
        local item = items[idx]
        local y = 6 + slot
        if item then
            local disp = string.sub(item.name, 1, 43)
            if idx == cursor then
                io.write(string.format("\x1b[%d;17H\x1b[7m > %-44s\x1b[0m", y, disp))
            else
                io.write(string.format("\x1b[%d;17H   %-44s", y, disp))
            end
        else
            io.write(string.format("\x1b[%d;17H%s", y, string.rep(" ", 47)))
        end
    end

    local function draw_scrollbar()
        if #items > max_visible then
            local thumb = math.floor(((cursor - 1) / math.max(1, #items - 1)) * (max_visible - 3)) + 2
            for i = 1, max_visible do
                local char = (i == 1 and "^") or (i == max_visible and "v") or (i == thumb and "\x1b[7m#\x1b[0m") or ":"
                io.write(string.format("\x1b[%d;65H%s", 6 + i, char))
            end
        else
            for i = 1, max_visible do io.write(string.format("\x1b[%d;65H ", 6 + i)) end
        end
    end

    local function draw_list_all()
        for i = 1, max_visible do draw_single_row(i) end
        draw_scrollbar()
    end

    local function draw_static_frame()
        local title = mode == "OPEN" and "OUVRIR UN FICHIER" or "SAUVEGARDER LE FICHIER"
        M.draw_window(15, 4, 52, 18, title)
        io.write("\x1b[6;15H\x1b[1m+--------------------------------------------------+\x1b[0m")
        io.write("\x1b[19;15H\x1b[1m+--------------------------------------------------+\x1b[0m")
        if mode == "SAVE" then
            io.write("\x1b[20;16H NOM :                                            ")
        else
            io.write("\x1b[20;16H  [ENVOI] SELECTIONNER     |     [RETOUR] ANNULER ")
        end
        draw_path_bar()
        draw_list_all()
        draw_input_box()
        io.flush()
    end

    draw_static_frame()

    while true do
        local k = M.get_key()
        if k == "RETOUR" or k == "ESC" then
            return nil
        elseif mode == "SAVE" and k == "ANNULATION" then
            input_buffer = ""
            draw_input_box()
            io.flush()
        elseif mode == "SAVE" and (string.match(k or "", "^[%w%s%p_%.%-]$") and #k == 1) then
            if #input_buffer < 35 then
                input_buffer = input_buffer .. k
                draw_input_box()
                io.flush()
            end
        elseif mode == "SAVE" and (k == "CORRECTION" or k == "\x08" or k == "\x7f") then
            if #input_buffer > 0 then
                input_buffer = string.sub(input_buffer, 1, -2)
                draw_input_box()
                io.flush()
            end
        elseif k == "UP" or k == "Z" or k == "z" or k == "DOWN" or k == "S" or k == "s" then
            local is_up = (k == "UP" or k == "Z" or k == "z")
            local old_cursor, old_offset = cursor, list_offset

            if is_up then
                if cursor > 1 then
                    cursor = cursor - 1
                    if cursor <= list_offset then list_offset = cursor - 1 end
                else
                    cursor = #items
                    list_offset = math.max(0, #items - max_visible)
                end
            else
                if cursor < #items then
                    cursor = cursor + 1
                    if cursor > list_offset + max_visible then list_offset = cursor - max_visible end
                else
                    cursor, list_offset = 1, 0
                end
            end

            if cursor ~= old_cursor then
                if list_offset ~= old_offset then
                    draw_list_all()
                else
                    draw_single_row(old_cursor - list_offset)
                    draw_single_row(cursor - list_offset)
                    draw_scrollbar()
                end
                if mode == "SAVE" and not items[cursor].is_dir and items[cursor].real_name ~= "" then
                    input_buffer = items[cursor].real_name
                    draw_input_box()
                end
                io.flush()
            end
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            local sel = items[cursor]
            if mode == "OPEN" then
                if sel.is_dir then
                    if sel.real_name == ".." then current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else current_dir = current_dir .. sel.real_name .. "/" end
                    items = scan_dir(current_dir)
                    cursor, list_offset = 1, 0
                    draw_path_bar(); draw_list_all(); io.flush()
                elseif sel.real_name ~= "" then
                    return current_dir .. sel.real_name
                end
            elseif mode == "SAVE" then
                if sel and sel.is_dir and input_buffer == "" then
                    if sel.real_name == ".." then current_dir = string.match(current_dir, "^(.*)/[^/]+/$") or ""
                    else current_dir = current_dir .. sel.real_name .. "/" end
                    items = scan_dir(current_dir)
                    cursor, list_offset = 1, 0
                    draw_path_bar(); draw_list_all(); io.flush()
                elseif input_buffer ~= "" then
                    return current_dir .. input_buffer
                end
            end
        end
        M.sleep(0.01)
    end
end

return M