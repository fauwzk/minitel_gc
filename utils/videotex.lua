-- Fichier : utils/videotex.lua
-- 3615 VIDEOTEX : connexion aux serveurs Minitel encore en ligne. Le Minitel
-- repasse en Videotex 40 colonnes et affiche lui-meme les vraies pages ; le
-- Raspberry Pi ne fait que relayer (outils/videotex_pont.py).
-- @TYPE: TELEMATIQUE / RESEAU
-- @DESC: Les vrais serveurs Minitel d'aujourd'hui (MiniPavi, 3611...) en Videotex natif, couleurs et mosaiques comprises. [Esc] pour raccrocher.
-- @ART1:      .-----------------.
-- @ART2:      | 3615  ......... |
-- @ART3:      |  [ CONNEXION ]  |
-- @ART4:      |   MINIPAVI 1.6  |
-- @ART5:      '---[ VIDEOTEX ]--'

local minitel = require("minitel")
minitel.init()

local CFG_FILE = "utils/videotex.cfg" -- services ajoutes (conserves par la mise a jour)
local BRIDGE = "outils/videotex_pont.py"
local ERR_FILE = "/tmp/minitel_videotex.err"

-- Services fournis d'office ; utils/videotex.cfg en ajoute (NOM|ADRESSE|DESCRIPTION)
local DEFAULTS = {
    { name = "MINIPAVI", url = "ws://go.minipavi.fr:8182",
      desc = "Le portail Minitel d'aujourd'hui : des dizaines de services (jeux, actualites, annuaires, messageries...). Tapez le code du service puis ENVOI." },
    { name = "3611 ANNUAIRE", url = "ws://3611.re/ws",
      desc = "L'annuaire electronique du 3611, ressuscite : recherche par nom ou par rubrique, comme en 1985." },
}

local services = {}

local function load_services()
    services = {}
    for _, s in ipairs(DEFAULTS) do services[#services + 1] = s end
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local name, url, desc = string.match(line, "^([^|#][^|]*)|([^|]+)|?(.*)$")
        if name and url then
            services[#services + 1] = { name = string.upper(name), url = url, desc = desc ~= "" and desc or url, custom = true }
        end
    end
    f:close()
end

local function save_custom()
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    f:write("# Services de 3615 VIDEOTEX : NOM|ADRESSE (ws://, wss:// ou telnet://)|DESCRIPTION\n")
    for _, s in ipairs(services) do
        if s.custom then f:write(s.name .. "|" .. s.url .. "|" .. (s.desc or "") .. "\n") end
    end
    f:close()
end

-- =====================================================================
-- CONNEXION
-- =====================================================================
local function connect(s)
    minitel.draw_window(16, 9, 50, 7, "CONNEXION")
    io.write("\x1b[11;19H" .. minitel.pad("APPEL DE " .. s.name .. "...", 44))
    io.write("\x1b[12;19H" .. minitel.pad(string.sub(s.url, 1, 44), 44))
    io.write("\x1b[14;19H\x1b[1m" .. minitel.pad("[Esc] SEULE POUR RACCROCHER", 44) .. "\x1b[0m")
    io.flush()
    -- la tonalite du modem, pour l'ambiance
    minitel.beep_pattern({ 0, 0.15, 0.3 })
    minitel.sleep(1.5)

    minitel.force_videotex()
    local ok = os.execute(string.format("python3 %s %q 2>%s", BRIDGE, s.url, ERR_FILE))
    minitel.force_80()
    minitel.init()

    local f = io.open(ERR_FILE, "r")
    local err = f and f:read("*a") or ""
    if f then f:close() end
    os.remove(ERR_FILE)
    if not ok then
        local msg = (err:match("[^\r\n]+") or "Erreur inconnue")
        minitel.msg_box("CONNEXION IMPOSSIBLE", minitel.clean_accents(msg), "lose")
    else
        minitel.play_sound("pickup")
    end
end

-- =====================================================================
-- ANNUAIRE DES SERVICES
-- =====================================================================
local TOP, ROWS = 6, 10

local function draw_list(sel)
    for i = 1, ROWS do
        local s = services[i]
        local y = TOP + i - 1
        if s then
            local text = minitel.pad(string.format(" %d  %-16s %s", i, s.name, s.url), 76)
            if i == sel then io.write(string.format("\x1b[%d;3H\x1b[7m%s\x1b[0m", y, text))
            else io.write(string.format("\x1b[%d;3H%s", y, text)) end
        else
            io.write(string.format("\x1b[%d;3H%s", y, string.rep(" ", 76)))
        end
    end
    local s = services[sel]
    local lines = minitel.wrap(s and s.desc or "", 72, 3)
    for i = 1, 3 do io.write(string.format("\x1b[%d;5H%s", 18 + i, lines[i] or "")) end
    io.flush()
end

local function draw_all(sel)
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 VIDEOTEX  -  LES SERVEURS MINITEL D'AUJOURD'HUI")
    io.write("\x1b[3;3HChoisissez un service : le Minitel passe en Videotex 40 colonnes, en couleurs,")
    io.write("\x1b[4;3Het affiche les vraies pages du serveur. \x1b[1m[Esc]\x1b[0m seule raccroche et revient ici.")
    io.write("\x1b[17;1H" .. string.rep("-", 80))
    io.write("\x1b[18;3H\x1b[1mLE SERVICE\x1b[0m")
    minitel.footer("HAUT/BAS:SERVICE  ENVOI:CONNEXION  A:AJOUTER  S:SUPPRIMER  RETOUR:QUITTER")
    draw_list(sel)
end

load_services()
local sel = 1
draw_all(sel)
while true do
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "UP" then sel = sel > 1 and sel - 1 or #services; draw_list(sel)
        elseif k == "DOWN" then sel = sel < #services and sel + 1 or 1; draw_list(sel)
        elseif tonumber(k) and services[tonumber(k)] then sel = tonumber(k); draw_list(sel)
        elseif k == "ENVOI" or k == " " then
            connect(services[sel])
            draw_all(sel)
        elseif (k == "A" or k == "a") and #services < ROWS then
            local name = minitel.input_box("NOUVEAU SERVICE", "Nom du service :", "", 16)
            local url = name and name ~= "" and minitel.input_box("NOUVEAU SERVICE",
                "Adresse (ws://, wss:// ou telnet://hote:port) :", "ws://", 44)
            if url and url:match("^%a+://.+") then
                services[#services + 1] = { name = string.upper(name), url = url, desc = url, custom = true }
                save_custom()
                sel = #services
            end
            draw_all(sel)
        elseif (k == "S" or k == "s") and services[sel].custom then
            if minitel.confirm_box("SUPPRIMER", "Retirer " .. services[sel].name .. " de la liste ?") then
                table.remove(services, sel)
                save_custom()
                sel = math.min(sel, #services)
            end
            draw_all(sel)
        elseif k == "REPETITION" then draw_all(sel)
        end
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
