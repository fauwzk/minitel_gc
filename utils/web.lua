-- Fichier : utils/web.lua
-- 3615 WEB : client FrogFind pour le Minitel. FrogFind (frogfind.com) cherche
-- sur le web et reduit chaque page a du HTML tout simple pour les vieux
-- ordinateurs ; ce client le met en page sur 78 colonnes : titres,
-- paragraphes, listes et liens numerotes, lus page par page. On suit un lien
-- en tapant son numero. Si FrogFind ne repond pas, le Pi fait le meme travail
-- lui-meme (recherche DuckDuckGo, nettoyage local des pages). Favoris et
-- historique sont gardes dans utils/web.cfg.
-- @TYPE: INTERNET / NAVIGATEUR
-- @DESC: Client FrogFind : le web en mode texte, recherche, pages reduites a leur texte, liens numerotes, favoris et historique.
-- @ART1:        _   _
-- @ART2:       (o)-(o)     .-------------.
-- @ART3:      /  ___  \    | 3615  W E B |
-- @ART4:      \_'---'_/    '-------------'
-- @ART5:     ===[ LE WEB EN MODE TEXTE ]===

local minitel = require("minitel")
minitel.init()

local CFG_FILE = "utils/web.cfg"
local UA = "Mozilla/5.0 (X11; Linux armv7l) MinitelMagisClub/1.0"
local FROGFIND = "http://frogfind.com/"
local SEARCH_URL = "https://html.duckduckgo.com/html/?kl=fr-fr&q="
local engine = "frogfind" -- passe a "local" si FrogFind ne repond pas
local MAX_BYTES = 3000000
local TEXT_TOP, TEXT_ROWS, TEXT_W = 3, 19, 78
local MAX_HISTORY = 9

-- =====================================================================
-- OUTILS : URL ET TELECHARGEMENT
-- =====================================================================
local function url_encode(s)
    return (string.gsub(s, "[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function url_decode(s)
    return (string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function host_of(url) return url:match("^%a[%w+.-]*://([^/?#]+)") or "" end

-- Adresse d'un lien, relative a la page qui le contient
local function resolve(base, href)
    href = href:gsub("^%s+", ""):gsub("%s+$", ""):gsub("&amp;", "&")
    if href == "" or href:match("^#") or href:match("^javascript:") or href:match("^mailto:")
        or href:match("^tel:") or href:match("^data:") then
        return nil
    end
    href = href:gsub("#.*$", "")
    if href:match("^%a[%w+.-]*:") then return href end
    local scheme, host = base:match("^(%a[%w+.-]*)://([^/?#]+)")
    if not scheme then return nil end
    if href:match("^//") then return scheme .. ":" .. href end
    if href:match("^/") then return scheme .. "://" .. host .. href end
    if href:match("^%?") then return (base:gsub("[?#].*$", "")) .. href end
    local dir = base:gsub("[?#].*$", ""):match("^(%a[%w+.-]*://[^/]+.*/)") or (scheme .. "://" .. host .. "/")
    local path = dir:sub(#scheme + 4 + #host) .. href
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts)
        elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    local out = scheme .. "://" .. host .. "/" .. table.concat(parts, "/")
    if href:match("/$") and not out:match("/$") then out = out .. "/" end
    return out
end

-- Les liens de FrogFind passent par sa page de lecture : on garde l'adresse
-- du vrai site (read.php?a=ADRESSE), et on ignore ses liens internes
local function real_url(url)
    if not url or not url:match("^https?://frogfind%.com") then return url end
    local a = url:match("[?&]a=([^&]+)")
    return a and url_decode(a) or nil
end

-- Rend le corps, l'adresse finale et le type de contenu
local function fetch(url, timeout)
    local cmd = string.format("curl -sL --compressed -m %d --connect-timeout %d --max-filesize %d -A %q -w '\\n@@FIN@@%%{url_effective}@@%%{content_type}@@%%{http_code}' %q 2>/dev/null",
        timeout or 20, math.min(timeout or 20, 8), MAX_BYTES, UA, url)
    local p = io.popen(cmd)
    if not p then return nil end
    local data = p:read("*a") or ""
    p:close()
    local body, final, ctype, code = data:match("^(.*)\n@@FIN@@(.-)@@(.-)@@(%d*)$")
    if not body then return nil end
    return body, (final ~= "" and final or url), ctype:lower(), tonumber(code) or 0
end

-- =====================================================================
-- DU HTML AU TEXTE
-- =====================================================================
local ENTITIES = {
    quot = '"', apos = "'", amp = "&", lt = "<", gt = ">", nbsp = " ", laquo = '"', raquo = '"',
    rsquo = "'", lsquo = "'", rdquo = '"', ldquo = '"', hellip = "...", ndash = "-", mdash = "-",
    eacute = "e", egrave = "e", ecirc = "e", agrave = "a", acirc = "a", ccedil = "c", ocirc = "o",
    ucirc = "u", ugrave = "u", icirc = "i", iuml = "i", euml = "e", oelig = "oe", euro = "EUR",
    Eacute = "E", Egrave = "E", Agrave = "A", Ccedil = "C", copy = "(c)", reg = "(r)", deg = "o",
    times = "x", middot = ".", bull = "-", shy = "", zwj = "", zwnj = "", thinsp = " ", ensp = " ", emsp = " ",
}

local function decode_entities(s)
    s = s:gsub("&#[xX](%x+);?", function(h) local n = tonumber(h, 16); return n and n < 0x110000 and utf8.char(n) or "" end)
    s = s:gsub("&#(%d+);?", function(d) local n = tonumber(d); return n and n < 0x110000 and utf8.char(n) or "" end)
    s = s:gsub("&(%a+);", function(name) return ENTITIES[name] or ENTITIES[name:lower()] or " " end)
    return s
end

-- Les pages en ISO-8859-1 / Windows-1252 sont passees en UTF-8
local function to_utf8(html, ctype)
    local cs = (ctype or ""):match("charset=([%w%-_]+)")
        or html:sub(1, 3000):match("<meta[^>]-charset=[\"']?([%w%-_]+)")
    cs = (cs or "utf-8"):lower()
    if cs:match("8859") or cs:match("1252") or cs:match("latin") then
        return (html:gsub("[\128-\255]", function(c) return utf8.char(string.byte(c)) end))
    end
    return html
end

local function strip_block(html, tag)
    html = html:gsub("<" .. tag .. "[%s>].-</" .. tag .. "%s*>", " ")
    html = html:gsub("<" .. tag:upper() .. "[%s>].-</" .. tag:upper() .. "%s*>", " ")
    return html
end

-- Rend { title, text } : le texte garde ses paragraphes ("\n\n"), titres
-- ("# "), listes ("- ") et liens (texte\1numero\2) ; links[n] = adresse
local function html_to_doc(html, base, links, link_index)
    html = html:gsub("<!%-%-.-%-%->", " ")
    local title = html:match("<[tT][iI][tT][lL][eE][^>]*>(.-)</[tT][iI][tT][lL][eE]>") or ""
    for _, tag in ipairs({ "head", "script", "style", "noscript", "svg", "template", "iframe", "select", "button" }) do
        html = strip_block(html, tag)
    end
    -- le contenu principal, s'il est balise ; sinon tout le corps
    local main = html:match("<main[%s>].-</main>") or html:match("<article[%s>].-</article>")
    if main and #main > 500 then html = main else html = html:match("<body.-</body>") or html end
    for _, tag in ipairs({ "nav", "footer", "aside", "form" }) do html = strip_block(html, tag) end
    -- les longues listes faites seulement de liens sont des menus (langues,
    -- rubriques...) : elles disparaissent, comme chez FrogFind
    html = html:gsub("<[uU][lL][%s>].-</[uU][lL]%s*>", function(list)
        local items = select(2, list:gsub("<[lL][iI][%s>]", ""))
        local anchors = select(2, list:gsub("<[aA]%s", ""))
        local loose = #(list:gsub("<[aA]%s.-</[aA]%s*>", ""):gsub("<[^>]+>", ""):gsub("%s+", ""))
        if items >= 8 and anchors >= items * 0.9 and loose < items * 3 then return " " end
        return list
    end)

    html = html:gsub("[\r\n\t]+", " ")
    -- liens : le texte reste, suivi de son numero
    html = html:gsub("<[aA]%s([^>]*)>(.-)</[aA]%s*>", function(attrs, inner)
        local href = attrs:match("[hH][rR][eE][fF]%s*=%s*\"([^\"]*)\"") or attrs:match("[hH][rR][eE][fF]%s*=%s*'([^']*)'")
            or attrs:match("[hH][rR][eE][fF]%s*=%s*([^%s>]+)")
        local url = href and real_url(resolve(base, decode_entities(href)))
        local text = inner:gsub("<[^>]+>", " ")
        if not url or not text:match("%w") then return inner end
        local n = link_index[url]
        if not n then
            links[#links + 1] = url
            n = #links
            link_index[url] = n
        end
        return inner .. "\1" .. n .. "\2"
    end)
    html = html:gsub("<[iI][mM][gG]%s[^>]-[aA][lL][tT]%s*=%s*\"([^\"]+)\"[^>]*>", " [IMAGE : %1] ")
    -- structure
    html = html:gsub("<[hH]([1-6])[^>]*>", "\n\n# "):gsub("</[hH][1-6]%s*>", "\n\n")
    -- (%f : la balise s'arrete la ; sans elle, <div> avalerait le texte suivant)
    html = html:gsub("<[lL][iI]%f[%s/>][^>]*>", "\n- ")
    html = html:gsub("</?[pP]%f[%s/>][^>]*>", "\n\n")
    html = html:gsub("<[bB][rR]%s*/?>", "\n")
    for _, tag in ipairs({ "div", "section", "article", "blockquote", "ul", "ol", "dl", "table", "tr", "pre", "header",
                           "figcaption", "dd", "dt", "caption" }) do
        html = html:gsub("</?" .. tag .. "%f[%s/>][^>]*>", "\n"):gsub("</?" .. tag:upper() .. "%f[%s/>][^>]*>", "\n")
    end
    -- tableaux : "intitule : valeur | valeur" (fiches techniques, infobox)
    html = html:gsub("</[tT][hH]%s*>", " : "):gsub("</[tT][dD]%s*>", " | ")
    html = html:gsub("<[^>]*>", "")
    html = decode_entities(html)
    html = minitel.clean_accents(html)
    -- les ecritures sans equivalent sur le Minitel (grec, cyrillique, chinois...)
    -- deviendraient des suites de "?" : on les retire
    html = html:gsub("%?%?+", ""):gsub("[^\1\2\32-\126\n]", "")
    html = html:gsub("[ ]+", " "):gsub(" \n", "\n"):gsub("\n ", "\n"):gsub("\n%- *\n", "\n")
    html = html:gsub("|%s*\n", "\n"):gsub(" :\n([^\n])", " : %1"):gsub("\n\n\n+", "\n\n")
    title = minitel.clean_accents(decode_entities(title:gsub("%s+", " "))):gsub("[^\32-\126]", ""):match("^%s*(.-)%s*$")
    return { title = title, text = html:match("^%s*(.-)%s*$") or "" }
end

-- Lignes a afficher : { text, bold }
local function layout(text)
    local lines = {}
    local function add(t, bold) lines[#lines + 1] = { text = (t:gsub("%s+$", "")), bold = bold } end
    for para in (text .. "\n"):gmatch("(.-)\n") do
        if para:match("^# ") then
            if #lines > 0 and lines[#lines].text ~= "" then add("") end
            for _, l in ipairs(minitel.wrap(para:sub(3), TEXT_W)) do add(l, true) end
        elseif para:match("^%- ") then
            for i, l in ipairs(minitel.wrap(para:sub(3), TEXT_W - 2)) do add((i == 1 and "- " or "  ") .. l) end
        elseif para:match("%S") then
            for _, l in ipairs(minitel.wrap(para, TEXT_W)) do add(l) end
        elseif #lines > 0 and lines[#lines].text ~= "" then
            add("")
        end
    end
    while #lines > 0 and lines[#lines].text == "" do lines[#lines] = nil end
    return lines
end

-- =====================================================================
-- RECHERCHE (DUCKDUCKGO, VERSION HTML)
-- =====================================================================
local function search_doc(query)
    local body = fetch(SEARCH_URL .. url_encode(query))
    if not body then return nil, "Le moteur de recherche ne repond pas." end
    local links, text = {}, {}
    -- chaque resultat : lien, titre, extrait
    local pos = 1
    while true do
        local s, e, href, title = body:find('<a[^>]-class="result__a"[^>]-href="([^"]+)"[^>]*>(.-)</a>', pos)
        if not s then
            s, e, href, title = body:find('<a[^>]-href="([^"]+)"[^>]-class="result__a"[^>]*>(.-)</a>', pos)
        end
        if not s then break end
        local next_s = body:find('class="result__a"', e) or #body
        local snippet = body:sub(e, next_s):match('class="result__snippet"[^>]*>(.-)</a>') or ""
        local url = href:match("uddg=([^&]+)")
        url = url and url_decode(url) or (href:match("^//") and ("https:" .. href)) or href
        if url:match("^https?://") and not url:match("duckduckgo%.com/y%.js") then
            links[#links + 1] = url
            local clean = function(x)
                return minitel.clean_accents(decode_entities(x:gsub("<[^>]+>", ""))):gsub("[^\32-\126]", ""):gsub("%s+", " ")
            end
            text[#text + 1] = "# " .. clean(title) .. "\1" .. #links .. "\2"
            text[#text + 1] = host_of(url)
            local sn = clean(snippet)
            if sn:match("%S") then text[#text + 1] = sn end
            text[#text + 1] = ""
        end
        pos = e + 1
    end
    if #links == 0 then
        if body:find("anomaly") then return nil, "DuckDuckGo refuse la recherche pour l'instant. Reessayez plus tard." end
        return nil, "Aucun resultat pour : " .. query
    end
    return { title = "RECHERCHE : " .. string.upper(query), url = "recherche:" .. query,
             text = table.concat(text, "\n"), links = links }
end

-- =====================================================================
-- FAVORIS ET HISTORIQUE (utils/web.cfg : favori=TITRE|URL, vu=TITRE|URL)
-- =====================================================================
local favorites, history = {}, {}

local function load_cfg()
    local f = io.open(CFG_FILE, "r")
    if not f then
        favorites = {
            { title = "WIKIPEDIA (FR)", url = "https://fr.m.wikipedia.org/" },
            { title = "68K NEWS", url = "http://68k.news/" },
            { title = "TEXT-ONLY NPR", url = "https://text.npr.org/" },
            { title = "LITE CNN", url = "https://lite.cnn.com/" },
        }
        return
    end
    for l in f:lines() do
        local kind, title, url = l:match("^(%a+)=([^|]*)|(.+)$")
        if kind == "favori" then favorites[#favorites + 1] = { title = title, url = url }
        elseif kind == "vu" then history[#history + 1] = { title = title, url = url } end
    end
    f:close()
end

local function save_cfg()
    local f = io.open(CFG_FILE, "w")
    if not f then return end
    for _, b in ipairs(favorites) do f:write("favori=" .. b.title:gsub("|", "/") .. "|" .. b.url .. "\n") end
    for _, b in ipairs(history) do f:write("vu=" .. b.title:gsub("|", "/") .. "|" .. b.url .. "\n") end
    f:close()
end

local function remember(doc)
    if doc.url:match("^recherche:") then return end
    for i = #history, 1, -1 do if history[i].url == doc.url then table.remove(history, i) end end
    table.insert(history, 1, { title = string.sub(doc.title ~= "" and doc.title or doc.url, 1, 60), url = doc.url })
    while #history > MAX_HISTORY do table.remove(history) end
    save_cfg()
end

-- =====================================================================
-- CHARGEMENT D'UNE PAGE
-- =====================================================================
local function status(text)
    io.write(string.format("\x1b[22;1H\x1b[7m%s\x1b[0m", minitel.pad(" " .. text, 80)))
    io.flush()
end

local cache = {}

-- Page par FrogFind : sa recherche ou sa page de lecture. Rend un document,
-- ou nil si FrogFind ne repond pas (on passe alors en local)
local function load_frogfind(url)
    local query = url:match("^recherche:(.*)$")
    local ff_url = query and (FROGFIND .. "?q=" .. url_encode(query)) or (FROGFIND .. "read.php?a=" .. url_encode(url))
    status((query and "RECHERCHE" or ("CHARGEMENT DE " .. string.upper(host_of(url)))) .. " PAR FROGFIND...")
    local body, final, ctype, code = fetch(ff_url, 25)
    if not body or body == "" or code >= 500 or code == 0 then return nil end
    local links, index = {}, {}
    status("MISE EN PAGE...")
    local doc = html_to_doc(to_utf8(body, ctype), final, links, index)
    doc.links = links
    doc.url = url
    if query then doc.title = "RECHERCHE : " .. string.upper(query) end
    return doc
end

-- Rend un document { title, url, text, links, lines } ou nil, message
local function load(url)
    if cache[url] then return cache[url] end
    local doc, err
    if engine == "frogfind" then
        doc = load_frogfind(url)
        if not doc then
            engine = "local"
            status("FROGFIND NE REPOND PAS : LE PI PREND LE RELAIS")
            minitel.sleep(1.2)
        end
    end
    if doc then
        -- deja charge par FrogFind
    elseif url:match("^recherche:") then
        status("RECHERCHE EN COURS...")
        doc, err = search_doc(url:sub(11))
        if not doc then return nil, err end
    else
        status("CHARGEMENT DE " .. string.upper(host_of(url)) .. "...")
        local body, final, ctype, code = fetch(url)
        if not body or body == "" then return nil, "Le site ne repond pas (" .. host_of(url) .. ")." end
        if code >= 400 then return nil, "Le site repond par une erreur " .. code .. "." end
        if ctype ~= "" and not ctype:match("html") and not ctype:match("text") and not ctype:match("xml") then
            return nil, "Ce fichier ne s'affiche pas sur le Minitel (" .. ctype:match("^[^;]+") .. ")."
        end
        local links, index = {}, {}
        if ctype:match("text/plain") then
            doc = { title = final:match("([^/]+)$") or final, text = minitel.clean_accents(body):gsub("[^\32-\126\n]", "") }
        else
            status("MISE EN PAGE...")
            doc = html_to_doc(to_utf8(body, ctype), final, links, index)
        end
        doc.url, doc.links = final, links
    end
    doc.lines = layout(doc.text)
    if #doc.lines == 0 then doc.lines = { { text = "(Cette page ne contient pas de texte lisible.)" } } end
    cache[url] = doc
    return doc
end

-- =====================================================================
-- AFFICHAGE D'UNE PAGE : liens numerotes en video inverse
-- =====================================================================
local function render_line(l)
    local s = l.text:gsub("\1(%d+)\2", "\x1b[7m%1\x1b[0m" .. (l.bold and "\x1b[1m" or ""))
    local visible = #(l.text:gsub("[\1\2]", ""))
    return (l.bold and "\x1b[1m" or "") .. s .. "\x1b[0m" .. string.rep(" ", math.max(0, TEXT_W - visible))
end

local function draw_page(doc, top, typed)
    io.write("\x1b[0m\x1b[2J")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.pad(" " .. (doc.title ~= "" and doc.title or "SANS TITRE"), 80) .. "\x1b[0m")
    local url = doc.url:match("^recherche:") and "DuckDuckGo" or doc.url
    io.write("\x1b[2;2H" .. string.sub(url, 1, 78))
    for i = 0, TEXT_ROWS - 1 do
        local l = doc.lines[top + i]
        if l and l.text ~= "" then io.write(string.format("\x1b[%d;2H%s", TEXT_TOP + i, render_line(l))) end
    end
    local pages = math.max(1, math.ceil(#doc.lines / TEXT_ROWS))
    local page = math.floor((top - 1) / TEXT_ROWS) + 1
    status(string.format("PAGE %d/%d   %d LIEN%s   NUMERO + ENVOI : SUIVRE UN LIEN   [%s]", page, pages,
        #doc.links, #doc.links > 1 and "S" or "", engine == "frogfind" and "FROGFIND" or "LOCAL"))
    io.write("\x1b[23;2HLIEN : " .. minitel.pad(typed or "", 6))
    minitel.footer("SUITE/RETOUR:PAGE  P:PAGE PRECED.  L:LIENS  R:RECHERCHE  G:ADRESSE  A:FAVORI  SOMMAIRE")
    io.flush()
end

-- Liste des liens d'une page (L) : rend le numero choisi, ou nil
local function links_screen(doc)
    local top = 1
    local rows = 19
    local typed = ""
    local function draw()
        io.write("\x1b[0m\x1b[2J")
        io.write("\x1b[1;1H\x1b[7m" .. minitel.pad(" LIENS DE : " .. doc.title, 80) .. "\x1b[0m")
        for i = 0, rows - 1 do
            local n = top + i
            local u = doc.links[n]
            if u then io.write(string.format("\x1b[%d;2H\x1b[7m%3d\x1b[0m %s", 3 + i, n, string.sub(u, 1, 73))) end
        end
        io.write("\x1b[23;2HLIEN : " .. minitel.pad(typed, 6))
        minitel.footer("NUMERO + ENVOI : OUVRIR   SUITE / RETOUR : DEFILER   SOMMAIRE : REVENIR A LA PAGE")
        io.flush()
    end
    draw()
    while true do
        local k = minitel.get_key()
        if k then
            if k:match("^%d$") and #typed < 4 then typed = typed .. k; io.write("\x1b[23;9H" .. minitel.pad(typed, 6)); io.flush()
            elseif (k == "CORRECTION") and #typed > 0 then typed = typed:sub(1, -2); io.write("\x1b[23;9H" .. minitel.pad(typed, 6)); io.flush()
            elseif k == "ENVOI" and tonumber(typed) and doc.links[tonumber(typed)] then return tonumber(typed)
            elseif k == "SUITE" or k == "DOWN" then if top + rows <= #doc.links then top = top + rows; draw() end
            elseif k == "RETOUR" or k == "UP" then if top > 1 then top = math.max(1, top - rows); draw() else return nil end
            elseif k == "SOMMAIRE" or k == "ESC" then return nil
            end
        end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- NAVIGATION
-- =====================================================================
local function ask_url()
    local u = minitel.input_box("ALLER A UNE ADRESSE", "Adresse du site (ex : fr.m.wikipedia.org) :", "", 44)
    if not u or u:match("^%s*$") then return nil end
    u = u:gsub("^%s+", ""):gsub("%s+$", "")
    if not u:match("^%a[%w+.-]*://") then u = "https://" .. u end
    return u
end

local function ask_search()
    local q = minitel.input_box("RECHERCHE SUR LE WEB", "Mots a chercher :", "", 44)
    if not q or q:match("^%s*$") then return nil end
    return "recherche:" .. q
end

-- Rend "HOME" (sommaire) ou "QUIT"
local function browse(start_url)
    local stack = {}     -- pages precedentes : { url, top }
    local url, top = start_url, 1
    local doc, err = load(url)
    if not doc then minitel.msg_box("3615 WEB", minitel.clean_accents(err), "lose"); return "HOME" end
    remember(doc)
    local typed = ""
    local function go(new_url)
        local d, e = load(new_url)
        if not d then
            minitel.msg_box("3615 WEB", minitel.clean_accents(e), "lose")
            draw_page(doc, top, typed)
            return
        end
        stack[#stack + 1] = { url = url, top = top }
        url, top, doc = new_url, 1, d
        remember(doc)
        minitel.play_sound("pickup")
        draw_page(doc, top, "")
    end
    draw_page(doc, top, typed)
    while true do
        local k = minitel.get_key()
        if k then
            local max_top = math.max(1, (math.ceil(#doc.lines / TEXT_ROWS) - 1) * TEXT_ROWS + 1)
            if k:match("^%d$") and #typed < 4 then
                typed = typed .. k
                io.write("\x1b[23;9H" .. minitel.pad(typed, 6)); io.flush()
            elseif k == "CORRECTION" and #typed > 0 then
                typed = typed:sub(1, -2)
                io.write("\x1b[23;9H" .. minitel.pad(typed, 6)); io.flush()
            elseif k == "ANNULATION" then
                typed = ""
                io.write("\x1b[23;9H" .. minitel.pad("", 6)); io.flush()
            elseif k == "ENVOI" and typed ~= "" then
                local n = tonumber(typed)
                typed = ""
                if n and doc.links[n] then go(doc.links[n])
                else status("PAS DE LIEN " .. (n or "?") .. " SUR CETTE PAGE"); io.write("\x1b[23;9H      "); io.flush() end
            elseif k == "SUITE" or k == "DOWN" or k == " " or (k == "ENVOI" and typed == "") then
                if top < max_top then top = math.min(max_top, top + TEXT_ROWS); draw_page(doc, top, typed) end
            elseif k == "RETOUR" or k == "UP" then
                if top > 1 then top = math.max(1, top - TEXT_ROWS); draw_page(doc, top, typed)
                elseif #stack > 0 then
                    local prev = table.remove(stack)
                    url, top = prev.url, prev.top
                    doc = load(url) or doc
                    draw_page(doc, top, typed)
                else
                    return "HOME" -- premiere page du premier site : retour a l'accueil
                end
            elseif k == "P" or k == "p" or k == "LEFT" then
                if #stack > 0 then
                    local prev = table.remove(stack)
                    url, top = prev.url, prev.top
                    doc = load(url) or doc
                    draw_page(doc, top, typed)
                end
            elseif k == "L" or k == "l" then
                if #doc.links > 0 then
                    local n = links_screen(doc)
                    if n then go(doc.links[n]) else draw_page(doc, top, typed) end
                end
            elseif k == "R" or k == "r" then
                local q = ask_search()
                if q then go(q) else draw_page(doc, top, typed) end
            elseif k == "G" or k == "g" then
                local u = ask_url()
                if u then go(u) else draw_page(doc, top, typed) end
            elseif k == "A" or k == "a" then
                if not doc.url:match("^recherche:") then
                    table.insert(favorites, 1, { title = string.sub(doc.title ~= "" and doc.title or doc.url, 1, 60), url = doc.url })
                    while #favorites > 9 do table.remove(favorites) end
                    save_cfg()
                    status("PAGE AJOUTEE AUX FAVORIS")
                end
            elseif k == "REPETITION" then
                draw_page(doc, top, typed)
            elseif k == "SOMMAIRE" or k == "ESC" then
                return "HOME"
            end
        end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- ACCUEIL
-- =====================================================================
local FROG = {
    [[      _   _      ]],
    [[     (o)-(o)     ]],
    [[    /  ___  \    ]],
    [[    \_'---'_/    ]],
    [[   //|     |\\   ]],
}

local function home()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 WEB  -  LE WEB EN MODE TEXTE")
    for i, l in ipairs(FROG) do io.write(string.format("\x1b[%d;6H%s", 2 + i, l)) end
    io.write("\x1b[3;28H\x1b[1mLE WEB SUR VOTRE MINITEL, PAR FROGFIND\x1b[0m")
    io.write("\x1b[4;28HChaque page est reduite a son texte et a ses")
    io.write("\x1b[5;28Hliens numerotes.")
    io.write("\x1b[7;28H\x1b[7m ENVOI \x1b[0m CHERCHER SUR LE WEB")
    io.write("\x1b[8;28H\x1b[7m   G   \x1b[0m ALLER A UNE ADRESSE")
    io.write("\x1b[7;58H\x1b[7m M \x1b[0m MOTEUR :")
    io.write("\x1b[8;58H" .. (engine == "frogfind" and "\x1b[1mFROGFIND\x1b[0m" or "\x1b[1mLOCAL\x1b[0m (PI)"))
    io.write("\x1b[10;3H\x1b[1mFAVORIS\x1b[0m (1 A 9)")
    for i, b in ipairs(favorites) do
        if i > 9 then break end
        io.write(string.format("\x1b[%d;3H\x1b[7m %d \x1b[0m %s", 10 + i, i, string.sub(b.title, 1, 33)))
    end
    io.write("\x1b[10;42H\x1b[1mDERNIERES PAGES\x1b[0m (A A I)")
    for i, b in ipairs(history) do
        if i > 9 then break end
        io.write(string.format("\x1b[%d;42H\x1b[7m %s \x1b[0m %s", 10 + i, string.char(64 + i), string.sub(b.title, 1, 33)))
    end
    io.write("\x1b[21;3HFrogFind (frogfind.com) simplifie les pages. S'il ne repond pas, le Pi le fait.")
    minitel.footer("ENVOI:CHERCHER  G:ADRESSE  1-9:FAVORI  A-I:RECENTE  S:SUPPR.FAVORI  M:MOTEUR  RETOUR")
    io.flush()
end

load_cfg()
home()
while true do
    local k = minitel.get_key()
    if k then
        local target
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then break
        elseif k == "ENVOI" or k == " " or k == "R" or k == "r" then target = ask_search(); if not target then home() end
        elseif k == "G" or k == "g" then target = ask_url(); if not target then home() end
        elseif k:match("^[1-9]$") and favorites[tonumber(k)] then target = favorites[tonumber(k)].url
        elseif (k == "S" or k == "s") and #favorites > 0 then
            local n = minitel.input_box("SUPPRIMER UN FAVORI", "Numero du favori a supprimer :", "", 1)
            if n and favorites[tonumber(n) or 0] then table.remove(favorites, tonumber(n)); save_cfg() end
            home()
        elseif #k == 1 and k:upper():match("^[A-I]$") then
            local b = history[string.byte(k:upper()) - 64]
            if b then target = b.url end
        elseif k == "M" or k == "m" then
            engine = engine == "frogfind" and "local" or "frogfind"
            cache = {}
            home()
        elseif k == "REPETITION" then home()
        end
        if target then
            browse(target)
            home()
        end
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
