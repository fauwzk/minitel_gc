local minitel = require("minitel")
minitel.init()

-- Ignore la commande Linux stty si on est sur Windows
os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

-- Detection de l'OS (Windows utilise \ pour les chemins, Linux /)
local is_windows = package.config:sub(1,1) == "\\"

local function input_string()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then return string.upper(str)
            elseif k == "RETOUR" or k == "ESC" then return "ABORT"
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
-- LE MOTEUR PYTHON INTEGRE (COMPATIBLE WINDOWS / LINUX)
-- =====================================================================
local function get_route(city_start, city_end)
    io.write("\x1b[12;20H\x1b[7m CALCUL PAR SATELLITE EN COURS... \x1b[0m\x1b[K")
    io.flush()
    
    local py_script = [[
import urllib.request, json, urllib.parse, unicodedata

def clean(s):
    if not s: return ""
    return "".join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c)).replace('\n', ' ').upper()

def get_coords(city):
    url = 'https://api-adresse.data.gouv.fr/search/?q=' + urllib.parse.quote(city) + '&type=municipality&limit=1'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MagisClub/1.0'})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read().decode('utf-8'))
        coords = data['features'][0]['geometry']['coordinates']
        return str(coords[0]) + ',' + str(coords[1])
    except:
        return None

def get_route():
    c1 = get_coords("CITY_A_PLACEHOLDER")
    c2 = get_coords("CITY_B_PLACEHOLDER")
    if not c1 or not c2:
        print("ERROR_CITY")
        return
    
    url = 'http://router.project-osrm.org/route/v1/driving/{};{}?steps=true&overview=false&language=fr'.format(c1, c2)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MagisClub/1.0'})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read().decode('utf-8'))
        route = data['routes'][0]
        print("SUMMARY|{}|{}".format(route['distance'], route['duration']))
        for step in route['legs'][0]['steps']:
            dist = step['distance']
            inst = step.get('maneuver', {}).get('instruction', '')
            print("STEP|{}|{}".format(dist, clean(inst)))
    except Exception as e:
        print("ERROR_ROUTE")

get_route()
]]
    
    -- On injecte les villes directement dans le code Python pour eviter les bugs de console Windows
    py_script = py_script:gsub("CITY_A_PLACEHOLDER", city_start)
    py_script = py_script:gsub("CITY_B_PLACEHOLDER", city_end)
    
    -- Sauvegarde dans le dossier courant (universel)
    local f = io.open("utils/temp_route.py", "w")
    if not f then return "ERREUR DOSSIER UTILS", nil end
    f:write(py_script)
    f:close()
    
    -- Choix de la commande selon l'OS
    local cmd = is_windows and 'python utils/temp_route.py' or 'python3 utils/temp_route.py 2>/dev/null'
    f = io.popen(cmd)
    
    local summary = nil
    local steps = {}
    
    for line in f:lines() do
        if line == "ERROR_CITY" then return "VILLE INCONNUE", nil end
        if line == "ERROR_ROUTE" then return "ERREUR CALCUL ROUTE", nil end
        
        local t, v1, v2 = line:match("^(.-)|(.-)|(.*)$")
        if t == "SUMMARY" then
            summary = { dist = tonumber(v1) or 0, dur = tonumber(v2) or 0 }
        elseif t == "STEP" then
            table.insert(steps, { distance = tonumber(v1) or 0, instruction = string.sub(v2, 1, 68) })
        end
    end
    f:close()
    
    -- Nettoyage du fichier temp
    os.remove("utils/temp_route.py")
    
    if summary and #steps > 0 then return summary, steps end
    return "AUCUNE DONNEE API", nil
end

-- =====================================================================
-- AFFICHAGE DE LA FEUILLE DE ROUTE
-- =====================================================================
local function show_route(city_a, city_b, summary, steps)
    local tot_dist = math.floor(summary.dist / 1000)
    local tot_dur = math.floor(summary.dur / 60)
    local offset = 0
    local max_visible = 18
    
    local function draw_page()
        io.write("\x1b[r\x1b[2J\x1b[H")
        io.write("\x1b[1;1H\x1b[1m 3615 ITINERAIRE \x1b[0m                                          \x1b[1m FEUILLE DE ROUTE \x1b[0m\r\n")
        io.write("\x1b[2;1H================================================================================\r\n")
        io.write(string.format("\x1b[3;1H \x1b[7m DE: %-31s A: %-31s \x1b[0m\r\n", string.sub(city_a, 1, 31), string.sub(city_b, 1, 31)))
        io.write(string.format("\x1b[4;1H \x1b[1m DISTANCE : %04d KM                         TEMPS ESTIME : %02d H %02d MIN \x1b[0m\r\n", tot_dist, math.floor(tot_dur/60), tot_dur%60))
        io.write("\x1b[5;1H--------------------------------------------------------------------------------\r\n")
        
        for i = 1, max_visible do
            local idx = offset + i
            if steps[idx] then
                local dist_m = steps[idx].distance
                local dist_str = ""
                if dist_m > 1000 then dist_str = string.format("%02d KM", math.floor(dist_m / 1000))
                elseif dist_m > 0 then dist_str = string.format("%03d M", dist_m)
                else dist_str = "ARRIVE" end
                io.write(string.format("\x1b[%d;1H [%-6s] %s\x1b[K", i + 5, dist_str, steps[idx].instruction))
            end
        end
        
        local progress = math.floor(((offset + max_visible) / math.max(1, #steps)) * 100)
        if progress > 100 then progress = 100 end
        io.write(string.format("\x1b[24;1H\x1b[7m  [FLECHES] FAIRE DEFILER LA ROUTE   |   [RETOUR] QUITTER                 %02d%% \x1b[0m", progress))
        io.flush()
    end
    
    draw_page()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then break
        elseif k == "UP" or k == "Z" or k == "z" then if offset > 0 then offset = offset - 1; draw_page() end
        elseif k == "DOWN" or k == "S" or k == "s" then if offset + max_visible < #steps then offset = offset + 1; draw_page() end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 ITINERAIRE \x1b[0m                                             \x1b[1m MAPPY-TEXT \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    io.write("\x1b[5;5H\x1b[7m VILLE DE DEPART : \x1b[0m ")
    io.flush()
    
    local depart = input_string()
    if depart == "ABORT" then break end
    if depart ~= "" then
        io.write("\x1b[12;1H\x1b[K\x1b[7;5H\x1b[7m VILLE D'ARRIVEE : \x1b[0m ")
        io.flush()
        
        local arrivee = input_string()
        if arrivee == "ABORT" then break end
        if arrivee ~= "" then
            local summary, steps = get_route(depart, arrivee)
            if steps then
                show_route(depart, arrivee, summary, steps)
            else
                io.write("\x1b[12;15H\x1b[7m " .. summary .. ". APPUYEZ SUR RETOUR. \x1b[0m\x1b[K")
                io.flush()
                while minitel.get_key() ~= "RETOUR" and minitel.get_key() ~= "ESC" do minitel.sleep(0.1) end
            end
        end
    end
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()