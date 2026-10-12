local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

-- =====================================================================
-- SAISIE DE LA GARE
-- =====================================================================
local function input_station()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                return string.upper(str)
            elseif k == "RETOUR" or k == "ESC" then
                return "ABORT"
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D"); io.flush()
                end
            elseif string.match(k, "^[%w%s%-']$") and #k == 1 then
                if #str < 30 then
                    local char = string.upper(k)
                    str = str .. char
                    io.write(char); io.flush()
                end
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- PARSEUR JSON NATIF LUA & NETTOYAGE
-- =====================================================================
local function urlencode(str)
    str = string.gsub(str, " ", "%%20")
    str = string.gsub(str, "'", "%%27")
    return str
end

local function clean_string(str)
    if not str then return "" end
    -- Nettoyage des codes Unicode JSON (ex: \u00e9)
    str = str:gsub("\\u00e9", "E"):gsub("\\u00e8", "E"):gsub("\\u00ea", "E"):gsub("\\u00eb", "E")
    str = str:gsub("\\u00e0", "A"):gsub("\\u00e2", "A")
    str = str:gsub("\\u00ee", "I"):gsub("\\u00ef", "I")
    str = str:gsub("\\u00f4", "O"):gsub("\\u00f6", "O")
    str = str:gsub("\\u00f9", "U"):gsub("\\u00fb", "U"):gsub("\\u00fc", "U")
    str = str:gsub("\\u00e7", "C")
    
    -- Nettoyage de l'UTF-8 direct si present
    str = str:gsub("é", "E"):gsub("è", "E"):gsub("ê", "E")
    str = str:gsub("à", "A"):gsub("â", "A")
    str = str:gsub("ç", "C")
    str = str:gsub("ô", "O")
    str = str:gsub("î", "I")
    
    -- Retrait des guillemets
    str = str:gsub('\\"', "")
    
    return string.upper(str)
end

-- =====================================================================
-- MOTEUR DE RECUPERATION API (100% LUA)
-- =====================================================================
local function fetch_trains(station_name)
    io.write("\x1b[12;15H\x1b[7m CONNEXION AU RESEAU FERROVIAIRE... \x1b[0m\x1b[K")
    io.flush()
    
    -- Interrogation de l'API Opendata Suisse (couvre la France, sans clé API)
    local url = "http://transport.opendata.ch/v1/stationboard?station=" .. urlencode(station_name) .. "&limit=14"
    local f = io.popen("curl -sL -k '" .. url .. "' 2>/dev/null")
    local json = f:read("*a")
    f:close()
    
    if not json or json == "" then return nil, {} end
    
    -- 1. Extraction du vrai nom de la gare
    local real_station = station_name
    local station_block = json:match('"station"%s*:%s*{(.-)}')
    if station_block then
        local name = station_block:match('"name"%s*:%s*"([^"]+)"')
        if name then real_station = clean_string(name) end
    end
    
    -- 2. Extraction des trains
    local trains = {}
    -- Le gmatch découpe le JSON bloc par bloc pour chaque train
    for block in json:gmatch('{"stop":.-"to"%s*:%s*"[^"]+"') do
        local dep = block:match('"departure"%s*:%s*"([^"]+)"')
        local dest = block:match('"to"%s*:%s*"([^"]+)"')
        local cat = block:match('"category"%s*:%s*"([^"]*)"') or ""
        local num = block:match('"number"%s*:%s*"([^"]*)"') or ""
        
        if dep and dest then
            -- L'heure est au format "2026-10-12T20:37:00+0200"
            local time_str = string.sub(dep, 12, 16) 
            local train_name = string.upper(cat .. " " .. num)
            if train_name == " " or train_name == "" then train_name = "TRAIN" end
            
            table.insert(trains, { 
                time = time_str, 
                dest = clean_string(dest), 
                name = string.sub(train_name, 1, 18) 
            })
        end
    end
    
    return real_station, trains
end

-- =====================================================================
-- AFFICHAGE DU PANNEAU DE GARE
-- =====================================================================
local function show_board(station, trains)
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 TRAIN \x1b[0m                                             \x1b[1m SNCF DIRECT \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    
    io.write(string.format("\x1b[4;1H\x1b[1m GARE : %-72s\x1b[0m\r\n", string.sub(station, 1, 72)))
    io.write("\x1b[5;1H--------------------------------------------------------------------------------\r\n")
    
    -- En-tete du tableau facon Solari
    io.write("\x1b[6;1H\x1b[7m  DEPART  | DESTINATION                             | TRAIN              \x1b[0m\r\n")
    
    if #trains == 0 then
        io.write("\x1b[12;22H\x1b[7m AUCUN DEPART PREVU DANS CETTE GARE \x1b[0m\r\n")
    else
        -- Affichage d'un train par ligne
        for i, tr in ipairs(trains) do
            if i <= 14 then
                local y = 7 + i
                local dest_fmt = string.sub(tr.dest .. string.rep(" ", 39), 1, 39)
                local name_fmt = string.sub(tr.name .. string.rep(" ", 18), 1, 18)
                
                io.write(string.format("\x1b[%d;1H  \x1b[1m%s\x1b[0m    | %s | %s \r\n", y, tr.time, dest_fmt, name_fmt))
            end
        end
    end
    
    io.write("\x1b[24;1H\x1b[7m  [ENVOI] RECHERCHER UNE AUTRE GARE   |   [RETOUR] QUITTER LE MODULE          \x1b[0m")
    io.flush()
    
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then return false
        elseif k == "ENVOI" or k == "\n" or k == "\r" then return true
        end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 TRAIN \x1b[0m                                             \x1b[1m SNCF DIRECT \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    io.write("\x1b[10;1H                             \x1b[7m PROCHAINS DEPARTS \x1b[0m\r\n\r\n")
    io.write("                  INDIQUEZ LE NOM DE LA GARE DE DEPART\r\n")
    io.write("                  (ex: PARIS GARE DE LYON, DIJON, TROYES)\r\n\r\n")
    io.write("                           GARE : \x1b[7m                    \x1b[0m\x1b[20D")
    io.flush()
    
    local search = input_station()
    if search == "ABORT" then break end
    
    if search and search ~= "" then
        local real_name, trains = fetch_trains(search)
        if real_name then
            local play_again = show_board(real_name, trains)
            if not play_again then break end
        else
            io.write("\x1b[12;15H\x1b[7m ERREUR DE CONNEXION AU RESEAU FERROVIAIRE. \x1b[0m\x1b[K")
            io.flush()
            while minitel.get_key() ~= "RETOUR" and minitel.get_key() ~= "ESC" do minitel.sleep(0.1) end
        end
    end
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()