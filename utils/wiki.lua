-- Fichier : utils/wiki.lua
-- 3615 WIKIPEDIA : recherche d'un article sur fr.wikipedia.org et lecture en
-- texte brut, page par page, sur 80 colonnes.
-- @TYPE: ENCYCLOPEDIE / INTERNET
-- @DESC: Cherchez un mot, choisissez l'article, lisez son resume puis la suite avec [SUITE]. Texte brut de fr.wikipedia.org.
-- @ART1:      .----------------.
-- @ART2:      |  W I K I       |
-- @ART3:      |  P E D I A     |
-- @ART4:      |  ==== ====     |
-- @ART5:      '--[ 3615 WIKI ]-'

local minitel = require("minitel")
minitel.init()

local API = "https://fr.wikipedia.org/w/api.php"
local USER_AGENT = "MinitelMagisClub/1.0 (https://github.com/fauwzk/minitel_gc)"
local TEXT_TOP, TEXT_ROWS, TEXT_W = 4, 18, 78

-- =====================================================================
-- RESEAU ET JSON
-- =====================================================================
local function url_encode(s)
    return (string.gsub(s, "[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function http_get(url)
    local cmd = string.format("curl -s -m 15 -A %q %q 2>/dev/null", USER_AGENT, url)
    local p = io.popen(cmd)
    if not p then return nil end
    local body = p:read("*a")
    p:close()
    if not body or body == "" then return nil end
    return body
end

local json_decode = minitel.json_decode

local function strip_html(s)
    s = string.gsub(s or "", "<[^>]+>", "")
    s = string.gsub(s, "&quot;", '"'):gsub("&#039;", "'"):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
    return s
end

local function ascii(s)
    return (string.gsub(minitel.clean_accents(s or ""), "[^\32-\126\n]", ""))
end

local function search(query)
    local body = http_get(API .. "?action=query&list=search&srlimit=9&srprop=snippet&format=json&formatversion=2&utf8=1&srsearch="
        .. url_encode(query))
    if not body then return nil, "PAS DE REPONSE DE WIKIPEDIA (RESEAU ?)" end
    local data = json_decode(body)
    local hits = data and data.query and data.query.search
    if not hits then return nil, "REPONSE ILLISIBLE DE WIKIPEDIA" end
    local list = {}
    for _, h in ipairs(hits) do
        list[#list + 1] = { title = h.title, snippet = ascii(strip_html(h.snippet)) }
    end
    return list
end

local function fetch_article(title)
    local body = http_get(API .. "?action=query&prop=extracts&explaintext=1&exsectionformat=wiki&redirects=1&format=json&formatversion=2&utf8=1&titles="
        .. url_encode(title))
    if not body then return nil, "PAS DE REPONSE DE WIKIPEDIA (RESEAU ?)" end
    local data = json_decode(body)
    local page = data and data.query and data.query.pages and data.query.pages[1]
    if not page or not page.extract or page.extract == "" then return nil, "ARTICLE VIDE OU INTROUVABLE" end
    return page.title, page.extract
end

-- =====================================================================
-- MISE EN PAGE : LE TEXTE EN LIGNES DE 78 CARACTERES
-- =====================================================================
-- Rend une liste de lignes { text, bold } ; les titres "== Section ==" sont
-- en majuscules et en gras, precedes d'une ligne vide
local function layout(text)
    local lines = {}
    for para in (ascii(text) .. "\n"):gmatch("([^\n]*)\n") do
        local level, head = para:match("^(=+)%s*(.-)%s*=+$")
        if head then
            if #lines > 0 and lines[#lines].text ~= "" then lines[#lines + 1] = { text = "" } end
            local mark = (#level <= 2) and "" or "  "
            lines[#lines + 1] = { text = mark .. string.upper(head), bold = true }
        elseif para:match("%S") then
            for _, l in ipairs(minitel.wrap(para, TEXT_W)) do
                lines[#lines + 1] = { text = (l:gsub("%s+$", "")) }
            end
        elseif #lines > 0 and lines[#lines].text ~= "" then
            lines[#lines + 1] = { text = "" }
        end
    end
    -- sections vides (titre suivi d'un autre titre) : on retire leur titre
    local out = {}
    for i, l in ipairs(lines) do
        local nxt = lines[i + 1]
        local nxt2 = lines[i + 2]
        local empty_section = l.bold and (not nxt or nxt.bold or (nxt.text == "" and (not nxt2 or nxt2.bold)))
        if not empty_section then out[#out + 1] = l end
    end
    return out
end

-- =====================================================================
-- ECRANS
-- =====================================================================
local function draw_header(sub)
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 WIKIPEDIA - " .. sub)
end

local function message(text, attr)
    io.write("\x1b[22;1H" .. (attr or "") .. minitel.pad(" " .. text, 80) .. "\x1b[0m")
    io.write("\x1b[24;80H")
    io.flush()
end

local function ask_query(previous)
    draw_header("L'ENCYCLOPEDIE LIBRE EN 80 COLONNES")
    minitel.draw_frame(10, 6, 62, 11, "RECHERCHE")
    io.write("\x1b[8;14HTAPEZ UN MOT OU UN NOM, PUIS [ENVOI] :")
    io.write("\x1b[12;14HEXEMPLES : MINITEL, TOUR EIFFEL, ADA LOVELACE")
    io.write("\x1b[14;14HTEXTE ISSU DE FR.WIKIPEDIA.ORG (LICENCE CC BY-SA)")
    minitel.footer("[ENVOI] CHERCHER  |  [CORRECTION] EFFACER  |  [RETOUR] QUITTER")
    local str = previous or ""
    local function field()
        io.write(string.format("\x1b[10;14H> \x1b[7m %-50s \x1b[0m", string.sub(str, -50)))
        io.write(string.format("\x1b[10;%dH", 17 + math.min(#str, 50)))
        io.flush()
    end
    io.write("\x1b[?25h")
    field()
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" then
                io.write("\x1b[?25l")
                return str
            elseif k == "RETOUR" or k == "ESC" then
                io.write("\x1b[?25l")
                return nil
            elseif k == "CORRECTION" then str = string.sub(str, 1, -2); field()
            elseif k == "ANNULATION" then str = ""; field()
            elseif #k == 1 and string.byte(k) >= 32 and string.byte(k) < 127 and #str < 60 then
                str = str .. k; field()
            end
        end
        minitel.sleep(0.01)
    end
end

local function choose(query, results)
    local cursor = 1
    draw_header("RESULTATS POUR \"" .. string.upper(string.sub(query, 1, 30)) .. "\"")
    minitel.footer("[Z/S] CHOISIR  |  [ENVOI] LIRE  |  [SOMMAIRE] NOUVELLE RECHERCHE")
    local function row(i)
        local r = results[i]
        local y = 2 + i * 2 - 1 + 1
        local sel = i == cursor
        io.write(string.format("\x1b[%d;2H%s%s\x1b[0m", y, sel and "\x1b[7m" or "\x1b[1m",
            minitel.pad(string.format(" %2d. %s", i, ascii(r.title)), 78)))
        io.write(string.format("\x1b[%d;2H%s", y + 1, minitel.pad("     " .. r.snippet, 78)))
    end
    for i = 1, #results do row(i) end
    io.write("\x1b[24;80H")
    io.flush()
    while true do
        local k = minitel.get_key()
        if k then
            local old = cursor
            if k == "z" or k == "Z" or k == "UP" then cursor = cursor > 1 and cursor - 1 or #results
            elseif k == "s" or k == "S" or k == "DOWN" then cursor = cursor < #results and cursor + 1 or 1
            elseif k == "ENVOI" then return results[cursor].title
            elseif k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return nil
            end
            if old ~= cursor then row(old); row(cursor); io.write("\x1b[24;80H"); io.flush() end
        end
        minitel.sleep(0.02)
    end
end

-- Lecture page par page. Rend "SEARCH" (nouvelle recherche) ou "BACK" (liste)
local function read(title, lines)
    local pages = math.max(1, math.ceil(#lines / TEXT_ROWS))
    local page = 1
    draw_header(string.upper(string.sub(ascii(title), 1, 50)))
    io.write("\x1b[3;1H" .. string.rep("-", 80))
    minitel.footer("[SUITE] PAGE SUIVANTE  [RETOUR] PRECEDENTE  [SOMMAIRE] RECHERCHE")
    local shown = {}
    local function draw_page()
        for r = 1, TEXT_ROWS do
            local l = lines[(page - 1) * TEXT_ROWS + r]
            local cell = l and ((l.bold and "\x1b[1m" or "") .. minitel.pad(l.text, 79) .. "\x1b[0m") or string.rep(" ", 79)
            if shown[r] ~= cell then
                shown[r] = cell
                io.write(string.format("\x1b[%d;1H %s", TEXT_TOP + r - 1, cell))
            end
        end
        message(string.format("PAGE %d / %d%s", page, pages,
            page == 1 and "   -   RESUME DE L'ARTICLE, LA SUITE AVEC [SUITE]" or ""), "\x1b[7m")
    end
    draw_page()
    while true do
        local k = minitel.get_key()
        if k then
            local old = page
            if k == "SUITE" or k == "ENVOI" or k == "s" or k == "S" or k == "DOWN" or k == "PAGE_DOWN" or k == " " then
                if page < pages then page = page + 1 end
            elseif k == "RETOUR" or k == "ESC" or k == "z" or k == "Z" or k == "UP" or k == "PAGE_UP" then
                if page > 1 then page = page - 1 else return "BACK" end
            elseif k == "SOMMAIRE" then return "SEARCH"
            elseif k == "REPETITION" then shown = {}; page = page
            end
            if old ~= page or k == "REPETITION" then draw_page() end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
local query
while true do
    query = ask_query(query)
    if not query then break end
    if query:match("%S") then
        message("RECHERCHE SUR WIKIPEDIA...")
        local results, err = search(query)
        if not results then
            minitel.msg_box("WIKIPEDIA", err, "lose")
        elseif #results == 0 then
            minitel.msg_box("WIKIPEDIA", "Aucun article pour : " .. query, "lose")
        else
            while true do
                local title = choose(query, results)
                if not title then break end
                message("CHARGEMENT DE L'ARTICLE...")
                local t, text = fetch_article(title)
                if not t then
                    minitel.msg_box("WIKIPEDIA", text, "lose")
                    break
                end
                local res = read(t, layout(text))
                if res == "SEARCH" then break end
            end
        end
    end
end

minitel.cleanup()
