-- Fichier : utils/info.lua
-- 3615 MAGIS INFOS : les titres de plusieurs journaux (flux RSS), et la
-- lecture des articles page par page, en minuscules et majuscules.
-- @TYPE: ACTUALITES / INTERNET
-- @DESC: Les derniers articles de plusieurs journaux (Korben, Next, Numerama, franceinfo, Le Monde), lus page par page sur 80 colonnes.

local minitel = require("minitel")
minitel.init()

-- Sources par defaut ; utils/info_flux.cfg peut les remplacer (NOM|ADRESSE)
local SOURCES = {
    { "KORBEN", "https://korben.info/feed/" },
    { "NEXT", "https://next.ink/feed/" },
    { "NUMERAMA", "https://www.numerama.com/feed/" },
    { "FRANCEINFO", "https://www.francetvinfo.fr/titres.rss" },
    { "LE MONDE", "https://www.lemonde.fr/rss/une.xml" },
}
local CFG_FILE = "utils/info_flux.cfg"

local LIST_TOP, LIST_ITEMS = 4, 8      -- 8 articles de 2 lignes
local TEXT_TOP, TEXT_ROWS, TEXT_W = 7, 15, 76

-- =====================================================================
-- NETTOYAGE DU HTML (PARAGRAPHES ET LISTES CONSERVES)
-- =====================================================================
local ENTITIES = {
    quot = '"', apos = "'", amp = "&", lt = "<", gt = ">", nbsp = " ", laquo = '"', raquo = '"',
    rsquo = "'", lsquo = "'", rdquo = '"', ldquo = '"', hellip = "...", ndash = "-", mdash = "-",
    eacute = "e", egrave = "e", ecirc = "e", agrave = "a", acirc = "a", ccedil = "c", ocirc = "o",
    ucirc = "u", ugrave = "u", icirc = "i", iuml = "i", euml = "e", oelig = "oe", euro = "EUR",
}

local function decode_entities(s)
    s = s:gsub("&#[xX](%x+);", function(h) return utf8.char(tonumber(h, 16)) end)
    s = s:gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end)
    s = s:gsub("&(%a+);", function(name) return ENTITIES[name] or ENTITIES[name:lower()] or " " end)
    return s
end

local function clean_text(str)
    if not str then return "" end
    str = str:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    str = str:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    -- en HTML, un saut de ligne du source n'est qu'un espace
    str = str:gsub("[\r\n]+", " ")
    -- le texte des figures, scripts et styles n'a rien a faire a l'ecran
    for _, tag in ipairs({ "script", "style", "figure", "iframe" }) do
        str = str:gsub("<" .. tag .. "[^>]*>.-</" .. tag .. ">", " ")
    end
    -- structure : paragraphes, titres et listes deviennent des sauts de ligne
    str = str:gsub("<[pP]%s[^>]*>", "\n\n"):gsub("<[pP]>", "\n\n"):gsub("</[pP]>", "\n\n")
    str = str:gsub("<[bB][rR]%s*/?>", "\n")
    str = str:gsub("<[hH]%d[^>]*>", "\n\n# "):gsub("</[hH]%d>", "\n\n")
    str = str:gsub("<[lL][iI][^>]*>", "\n- "):gsub("</[lL][iI]>", "\n")
    str = str:gsub("<[^>]+>", "")
    str = decode_entities(str)
    str = minitel.clean_accents(str)
    str = str:gsub("[^\32-\126\n]", "")
    str = str:gsub("[ \t]+", " "):gsub(" \n", "\n"):gsub("\n ", "\n")
    str = str:gsub("\n\n\n+", "\n\n")
    return str:match("^%s*(.-)%s*$") or str
end

-- "Mon, 26 Oct 2026 14:30:00 +0100" ou "2026-10-26T14:30:00Z" -> "26/10 14:30"
local MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }

local function short_date(s)
    if not s then return "" end
    local d, mon, h, mi = s:match("(%d+) (%a%a%a) %d+ (%d+):(%d+)")
    if d and MONTHS[mon] then return string.format("%02d/%02d %s:%s", tonumber(d), MONTHS[mon], h, mi) end
    local y, m, dd, hh, mm = s:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
    if y then return string.format("%s/%s %s:%s", dd, m, hh, mm) end
    return ""
end

-- =====================================================================
-- SOURCES ET TELECHARGEMENT
-- =====================================================================
local function load_sources()
    local f = io.open(CFG_FILE, "r")
    if not f then return end
    local list = {}
    for l in f:lines() do
        local name, url = l:match("^%s*([^#|][^|]*)|(%S+)%s*$")
        if name then list[#list + 1] = { string.upper(name), url } end
    end
    f:close()
    if #list > 0 then SOURCES = list end
end

local function fetch_news(url)
    local f = io.popen(string.format("curl -sL --max-time 15 -A 'Mozilla/5.0 (MinitelMagisClub)' %q 2>/dev/null", url))
    if not f then return {} end
    local xml = f:read("*a") or ""
    f:close()

    local items = {}
    local function add(block, desc_tags, date_tag)
        local title = block:match("<title[^>]*>(.-)</title>")
        local desc
        for _, t in ipairs(desc_tags) do
            desc = desc or block:match("<" .. t .. "[^>]*>(.-)</" .. t .. ">")
        end
        if title then
            title = clean_text(title):gsub("\n", " ")
            if #title > 5 then
                local text = clean_text(desc)
                items[#items + 1] = { title = title, text = text, date = short_date(block:match("<" .. date_tag .. ">(.-)</" .. date_tag .. ">")),
                                      summary = (text:gsub("^# ", ""):gsub("\n# ", " "):gsub("\n+", " ")) }
            end
        end
    end
    for item in xml:gmatch("<item[%s>].-</item>") do add(item, { "content:encoded", "description" }, "pubDate") end
    if #items == 0 then -- flux Atom
        for entry in xml:gmatch("<entry[%s>].-</entry>") do add(entry, { "content", "summary" }, "updated") end
    end
    return items
end

-- =====================================================================
-- MISE EN PAGE DES ARTICLES
-- =====================================================================
-- Lignes { text, bold } : titres intermediaires en gras, ligne vide entre
-- les paragraphes, puces des listes alignees
local function layout(text)
    local lines = {}
    for para in (text .. "\n"):gmatch("(.-)\n") do
        if para:match("^# ") then
            if #lines > 0 and lines[#lines].text ~= "" then lines[#lines + 1] = { text = "" } end
            for _, l in ipairs(minitel.wrap(string.upper(para:sub(3)), TEXT_W)) do
                lines[#lines + 1] = { text = (l:gsub("%s+$", "")), bold = true }
            end
        elseif para:match("^%- ") then
            local wrapped = minitel.wrap(para:sub(3), TEXT_W - 2)
            for i, l in ipairs(wrapped) do
                lines[#lines + 1] = { text = (i == 1 and "- " or "  ") .. (l:gsub("%s+$", "")) }
            end
        elseif para:match("%S") then
            for _, l in ipairs(minitel.wrap(para, TEXT_W)) do
                lines[#lines + 1] = { text = (l:gsub("%s+$", "")) }
            end
        elseif #lines > 0 and lines[#lines].text ~= "" then
            lines[#lines + 1] = { text = "" }
        end
    end
    while #lines > 0 and lines[#lines].text == "" do lines[#lines] = nil end
    return lines
end

-- =====================================================================
-- ECRANS
-- =====================================================================
local source_idx, news, fetched_at = 1, {}, ""
local cursor, top = 1, 1

local function line_at(y, x, w, text, attr)
    io.write(string.format("\x1b[%d;%dH%s%s%s", y, x, attr or "", minitel.pad(text, w), attr and "\x1b[0m" or ""))
end

local function draw_list_row(i)
    local idx = top + i - 1
    local y = LIST_TOP + (i - 1) * 2
    local n = news[idx]
    if not n then
        line_at(y, 2, 78, ""); line_at(y + 1, 2, 78, "")
        return
    end
    local sel = idx == cursor
    local head = string.format("%2d %s", idx, n.title)
    line_at(y, 2, 78, " " .. string.sub(head, 1, 77), sel and "\x1b[7m" or "\x1b[1m")
    local sub = (n.date ~= "" and (n.date .. "  ") or "") .. n.summary
    line_at(y + 1, 2, 78, "    " .. string.sub(sub, 1, 74))
end

local function draw_list(full)
    if full then
        io.write("\x1b[0m\x1b[2J")
        minitel.footer("[Z/S] CHOISIR  [ENVOI] LIRE  [F] SOURCE  [A] ACTUALISER  [RETOUR] QUITTER")
    end
    minitel.title_bar("3615 MAGIS INFOS - " .. SOURCES[source_idx][1])
    local names = {}
    for i, s in ipairs(SOURCES) do names[#names + 1] = (i == source_idx) and ("[" .. s[1] .. "]") or s[1] end
    line_at(2, 2, 78, " SOURCES : " .. table.concat(names, "  "))
    for i = 1, LIST_ITEMS do draw_list_row(i) end
    local pages = math.max(1, math.ceil(#news / LIST_ITEMS))
    line_at(21, 2, 78, string.format(" %d ARTICLE(S) - PAGE %d / %d - MIS A JOUR A %s", #news,
        (top - 1) // LIST_ITEMS + 1, pages, fetched_at))
    io.write("\x1b[24;80H")
    io.flush()
end

local function load_source()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 MAGIS INFOS - " .. SOURCES[source_idx][1])
    io.write("\x1b[12;24H\x1b[7m CONNEXION AU SERVEUR D'ACTUALITES... \x1b[0m")
    io.flush()
    news = fetch_news(SOURCES[source_idx][2])
    fetched_at = os.date("%H:%M")
    if #news == 0 then
        news = { { title = "AUCUN ARTICLE RECU DE " .. SOURCES[source_idx][1], date = "",
                   summary = "Verifiez la connexion Internet, ou essayez une autre source avec [F].",
                   text = "Le flux n'a renvoye aucun article. Verifiez la connexion Internet (CONFIG RESEAU), ou essayez une autre source avec la touche [F]." } }
    end
    cursor, top = 1, 1
    draw_list(true)
end

-- Lecture page par page ; rend quand on revient a la liste
local function read_article(n)
    local lines = layout(n.text)
    local pages = math.max(1, math.ceil(#lines / TEXT_ROWS))
    local page = 1
    local words = select(2, n.text:gsub("%S+", ""))
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 MAGIS INFOS - " .. SOURCES[source_idx][1])
    local tl = minitel.wrap(n.title, 78, 2)
    line_at(3, 2, 78, tl[1], "\x1b[1m")
    line_at(4, 2, 78, tl[2] or "", "\x1b[1m")
    line_at(5, 2, 78, string.format("%s%s  -  LECTURE : %d MIN", SOURCES[source_idx][1],
        n.date ~= "" and ("  -  " .. n.date) or "", math.max(1, math.floor(words / 200 + 0.5))))
    io.write("\x1b[6;2H" .. string.rep("-", 78))
    minitel.footer("[SUITE] PAGE SUIVANTE  [RETOUR] PRECEDENTE  [SOMMAIRE] LISTE DES TITRES")
    local shown = {}
    local function draw_page()
        for r = 1, TEXT_ROWS do
            local l = lines[(page - 1) * TEXT_ROWS + r]
            local cell = l and ((l.bold and "\x1b[1m" or "") .. minitel.pad(l.text, TEXT_W) .. "\x1b[0m") or string.rep(" ", TEXT_W)
            if shown[r] ~= cell then
                shown[r] = cell
                io.write(string.format("\x1b[%d;3H%s", TEXT_TOP + r - 1, cell))
            end
        end
        local bar_w = 30
        local fill = math.floor(bar_w * page / pages + 0.5)
        line_at(22, 1, 80, string.format(" PAGE %d / %d  [%s%s]%s", page, pages, string.rep("#", fill),
            string.rep(".", bar_w - fill), page == pages and "  FIN DE L'ARTICLE" or ""), "\x1b[7m")
        io.write("\x1b[24;80H")
        io.flush()
    end
    draw_page()
    while true do
        local k = minitel.get_key()
        if k then
            local old = page
            if k == "SUITE" or k == "ENVOI" or k == " " or k == "s" or k == "S" or k == "DOWN" or k == "PAGE_DOWN" then
                if page < pages then page = page + 1 else return end
            elseif k == "RETOUR" or k == "ESC" or k == "z" or k == "Z" or k == "UP" or k == "PAGE_UP" then
                if page > 1 then page = page - 1 else return end
            elseif k == "SOMMAIRE" or k == "q" or k == "Q" or k == "LEFT" then
                return
            elseif k == "REPETITION" then
                shown = {}
                draw_page()
            end
            if old ~= page then draw_page() end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
load_sources()
load_source()

while true do
    local k = minitel.get_key()
    if k then
        local old_cursor, old_top = cursor, top
        if k == "RETOUR" or k == "ESC" then
            break
        elseif k == "UP" or k == "Z" or k == "z" then
            if cursor > 1 then cursor = cursor - 1 end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if cursor < #news then cursor = cursor + 1 end
        elseif k == "ENVOI" or k == "\n" or k == "\r" or k == "RIGHT" or k == "D" or k == "d" then
            read_article(news[cursor])
            draw_list(true)
        elseif k == "f" or k == "F" or k == "SUITE" then
            source_idx = source_idx % #SOURCES + 1
            load_source()
        elseif k == "a" or k == "A" then
            load_source()
        elseif k == "REPETITION" then
            draw_list(true)
        end
        -- la page de la liste suit le curseur ; sinon seules deux lignes changent
        top = ((cursor - 1) // LIST_ITEMS) * LIST_ITEMS + 1
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
