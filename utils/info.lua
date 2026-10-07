local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

-- =====================================================================
-- NETTOYAGE INTELLIGENT (PRESERVATION DE LA MISE EN PAGE)
-- =====================================================================
local function clean_text(str)
    if not str then return "" end
    
    -- 1. Supprime les enveloppes CDATA
    str = str:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
    
    -- 2. Convertit les entites de chevrons en vrais chevrons
    str = str:gsub("&lt;", "<"):gsub("&gt;", ">")
    str = str:gsub("&LT;", "<"):gsub("&GT;", ">")
    
    -- 3. SAUVEGARDE DE LA MISE EN PAGE !
    -- On transforme les balises de structure en sauts de ligne (\n)
    str = str:gsub("<[pP]>", "\n\n"):gsub("<[pP]%s+[^>]->", "\n\n")
    str = str:gsub("</[pP]>", "\n\n")
    str = str:gsub("<[bB][rR]%s*/?>", "\n")
    str = str:gsub("<[hH]%d>", "\n\n"):gsub("<[hH]%d%s+[^>]->", "\n\n")
    str = str:gsub("</[hH]%d>", "\n\n")
    
    -- On transforme les listes HTML en vraies listes a tirets
    str = str:gsub("<[lL][iI]>", "\n - "):gsub("<[lL][iI]%s+[^>]->", "\n - ")
    str = str:gsub("</[lL][iI]>", "\n")
    
    -- 4. Supprime TOUTES les autres balises HTML restantes en mettant un espace
    str = str:gsub("<[^>]+>", " ")
    
    -- 5. Decode les codes numeriques caches
    str = str:gsub("&#(%d+);", function(n)
        local num = tonumber(n)
        if num == 10 or num == 13 then return "\n" end
        if num >= 32 and num <= 126 then return string.char(num) end
        return " "
    end)
    
    -- 6. Decode les autres entites HTML courantes
    str = str:gsub("&quot;", '"'):gsub("&QUOT;", '"')
    str = str:gsub("&apos;", "'"):gsub("&rsquo;", "'")
    str = str:gsub("&amp;", "&")
    str = str:gsub("&nbsp;", " ")
    str = str:gsub("&laquo;", '"'):gsub("&raquo;", '"')
    
    -- 7. Nettoyage final des espaces (SANS casser les sauts de ligne \n)
    str = str:gsub("[ \t]+", " ")           -- Reduit les espaces multiples a un seul
    str = str:gsub(" \n", "\n"):gsub("\n ", "\n") -- Retire les espaces en bordure de ligne
    str = str:gsub("\n\n\n+", "\n\n")       -- Limite a un maximum de 2 sauts de ligne de suite
    str = str:match("^%s*(.-)%s*$") or str  -- Retire les sauts de ligne tout au debut ou a la fin
    
    return string.upper(str)
end

-- =====================================================================
-- TELECHARGEMENT DU FLUX RSS
-- =====================================================================
local function fetch_news()
    io.write("\x1b[2J\x1b[H\x1b[12;20H\x1b[7m CONNEXION AU SERVEUR D'ACTUALITES... \x1b[0m")
    io.flush()
    
    local f = io.popen("curl -sL --max-time 15 'https://korben.info/feed/' 2>/dev/null | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null")
    if not f then return {} end
    local xml = f:read("*a")
    f:close()
    
    local items = {}
    for item in xml:gmatch("<item>(.-)</item>") do
        local title = item:match("<title>(.-)</title>")
        local desc = item:match("<content:encoded>(.-)</content:encoded>")
        if not desc then
            desc = item:match("<description>(.-)</description>")
        end
        
        if title then
            title = clean_text(title)
            desc = clean_text(desc)
            if #title > 5 then
                table.insert(items, {title = title, desc = desc})
            end
        end
    end
    return items
end

-- =====================================================================
-- AFFICHAGE : COUPE LES LIGNES EN RESPECTANT LES PARAGRAPHES
-- =====================================================================
local function word_wrap(text, max_len)
    local lines = {}
    -- On decoupe d'abord le texte en fonction des sauts de ligne \n qu'on a sauves
    for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
        if paragraph == "" or paragraph:match("^%s*$") then
            -- Si c'est un saut de ligne vide, on garde la ligne vide !
            table.insert(lines, "")
        else
            -- Si c'est du texte, on le coupe sans couper les mots
            local current = ""
            for word in paragraph:gmatch("%S+") do
                if #current + #word + 1 > max_len then
                    table.insert(lines, current)
                    current = word
                else
                    if current == "" then current = word
                    else current = current .. " " .. word end
                end
            end
            if current ~= "" then
                table.insert(lines, current)
            end
        end
    end
    return lines
end

-- =====================================================================
-- INTERFACE GRAPHIQUE EPUREE (MENU)
-- =====================================================================
local news = fetch_news()
if #news == 0 then
    table.insert(news, {title = "ERREUR DE CONNEXION AU SERVEUR", desc = "VERIFIEZ VOTRE LIAISON INTERNET."})
end

local cursor = 1
local offset = 0
local max_items = 8

local function draw_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    
    io.write("\x1b[1;1H\x1b[1m 3615 MAGIS INFOS \x1b[0m                                           \x1b[1m LE JOURNAL TECH \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    
    for i = 1, max_items do
        local idx = offset + i
        local line_y = 3 + (i * 2) 
        
        io.write("\x1b[" .. line_y .. ";1H\x1b[K")
        
        if news[idx] then
            local display_title = string.sub(news[idx].title, 1, 72)
            if idx == cursor then
                io.write("\x1b[" .. line_y .. ";3H\x1b[7m > " .. display_title .. " \x1b[0m")
            else
                io.write("\x1b[" .. line_y .. ";3H   " .. display_title)
            end
        end
    end
    
    io.write("\x1b[24;1H\x1b[7m  [FLECHES] NAVIGUER   |   [ENVOI] LIRE L'ARTICLE   |   [RETOUR] QUITTER        \x1b[0m")
    io.flush()
end

-- =====================================================================
-- AFFICHAGE DE L'ARTICLE COMPLET AVEC DEFILEMENT
-- =====================================================================
local function read_article(idx)
    local article = news[idx]
    
    -- Le moteur Word Wrap respecte maintenant les paragraphes et les puces
    local lines = word_wrap(article.desc, 76)
    local offset_y = 0
    local max_lines = 19
    
    local function draw_page()
        io.write("\x1b[r\x1b[2J\x1b[H")
        
        local safe_title = string.sub(article.title, 1, 78)
        local pad = 78 - #safe_title
        io.write("\x1b[1;1H\x1b[7m " .. safe_title .. string.rep(" ", math.max(0, pad)) .. " \x1b[0m\r\n\r\n")
        
        for i = 1, max_lines do
            local l = lines[offset_y + i]
            if l then
                io.write("\x1b[" .. (2 + i) .. ";3H" .. l)
            end
        end
        
        local progress = math.floor(((offset_y + max_lines) / math.max(1, #lines)) * 100)
        if progress > 100 then progress = 100 end
        local footer = string.format(" [RETOUR] LISTE   |   [FLECHES] DEFILER LE TEXTE   |   %02d%% ", progress)
        local pad_foot = 80 - #footer
        io.write("\x1b[24;1H\x1b[7m" .. string.rep(" ", pad_foot) .. footer .. "\x1b[0m")
        io.flush()
    end
    
    draw_page()
    
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == "LEFT" or k == "Q" or k == "q" then
            break
        elseif k == "UP" or k == "Z" or k == "z" then
            if offset_y > 0 then
                offset_y = offset_y - 1
                draw_page()
            end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if offset_y + max_lines < #lines then
                offset_y = offset_y + 1
                draw_page()
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE DU MENU INFO
-- =====================================================================
draw_menu()

while true do
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" then
            break
        elseif k == "UP" or k == "Z" or k == "z" then
            if cursor > 1 then
                cursor = cursor - 1
                if cursor <= offset then offset = cursor - 1 end
                draw_menu()
            end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if cursor < #news then
                cursor = cursor + 1
                if cursor > offset + max_items then offset = cursor - max_items end
                draw_menu()
            end
        elseif k == "ENVOI" or k == "\n" or k == "\r" or k == "RIGHT" or k == "D" or k == "d" then
            read_article(cursor)
            draw_menu()
        end
    end
    minitel.sleep(0.02)
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()