local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

local is_windows = package.config:sub(1,1) == "\\"

local function input_cp()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                if #str == 5 then return str end
            elseif k == "RETOUR" or k == "ESC" then return "ABORT"
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D"); io.flush()
                end
            elseif string.match(k, "^%d$") then
                if #str < 5 then
                    str = str .. k
                    io.write(k); io.flush()
                end
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- LE MOTEUR PYTHON INTEGRE (COMPATIBLE WINDOWS / LINUX)
-- =====================================================================
local function fetch_stations(cp)
    io.write("\x1b[12;15H\x1b[7m INTERROGATION DES SERVEURS GOUVERNEMENTAUX... \x1b[0m\x1b[K")
    io.flush()
    
    local py_script = [[
import urllib.request, json, unicodedata

def clean(s):
    if not s: return "INCONNU"
    return "".join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c)).replace('\n', ' ').upper()

def get_gas():
    cp = "CP_PLACEHOLDER"
    url = 'https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-du-jour/records?limit=30&where=cp%3D%22{}%22'.format(cp)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MagisClub/1.0'})
        data = json.loads(urllib.request.urlopen(req, timeout=8).read().decode('utf-8'))
        records = data.get('results', [])
        for r in records:
            adr = clean(r.get('adresse', 'INCONNU'))
            vil = clean(r.get('ville', 'INCONNU'))
            gaz = r.get('gazole_prix')
            sp98 = r.get('sp98_prix')
            e10 = r.get('e10_prix')
            gaz_s = "{:.3f}".format(float(gaz)) if gaz else "N/A"
            sp98_s = "{:.3f}".format(float(sp98)) if sp98 else "N/A"
            e10_s = "{:.3f}".format(float(e10)) if e10 else "N/A"
            print("{}||{}||{}||{}||{}".format(adr, vil, gaz_s, sp98_s, e10_s))
    except Exception as e:
        print("ERROR")

get_gas()
]]

    py_script = py_script:gsub("CP_PLACEHOLDER", cp)

    local f = io.open("utils/temp_carburant.py", "w")
    if not f then return {} end
    f:write(py_script)
    f:close()
    
    local cmd = is_windows and 'python utils/temp_carburant.py' or 'python3 utils/temp_carburant.py 2>/dev/null'
    f = io.popen(cmd)
    
    local stations = {}
    for line in f:lines() do
        if line == "ERROR" then break end
        local adr, vil, gaz, sp98, e10 = line:match("^(.-)||(.+)||(.+)||(.+)||(.+)$")
        if adr and vil then
            table.insert(stations, {
                adresse = adr, ville = vil, gazole = gaz, sp98 = sp98, e10 = e10
            })
        end
    end
    f:close()
    
    os.remove("utils/temp_carburant.py")
    
    return stations
end

-- =====================================================================
-- AFFICHAGE LISTE (SCROLLABLE)
-- =====================================================================
local function show_stations(cp, stations)
    local offset = 0
    local max_visible = 6 
    
    local function draw_page()
        io.write("\x1b[r\x1b[2J\x1b[H")
        io.write("\x1b[1;1H\x1b[1m 3615 CARBURANT \x1b[0m                                       \x1b[1m STATION SERVICE \x1b[0m\r\n")
        io.write("\x1b[2;1H================================================================================\r\n")
        io.write(string.format("\x1b[3;1H \x1b[7m SECTEUR RECHERCHE : %s (%d STATIONS TROUVEES) \x1b[0m\r\n", cp, #stations))
        io.write("\x1b[4;1H--------------------------------------------------------------------------------\r\n")
        
        for i = 1, max_visible do
            local idx = offset + i
            local y = 5 + ((i - 1) * 3)
            if stations[idx] then
                local st = stations[idx]
                io.write(string.format("\x1b[%d;1H \x1b[1m> %-76s\x1b[0m", y, string.sub(st.adresse .. " - " .. st.ville, 1, 76)))
                
                local p_gaz = st.gazole == "N/A" and " RUPTURE " or st.gazole .. " E"
                local p_98  = st.sp98 == "N/A" and " RUPTURE " or st.sp98 .. " E"
                local p_e10 = st.e10 == "N/A" and " RUPTURE " or st.e10 .. " E"
                
                io.write(string.format("\x1b[%d;1H    GAZOLE : %-11s |  SP98 : %-11s |  E10 : %-11s", y+1, p_gaz, p_98, p_e10))
            end
        end
        
        local progress = math.floor(((offset + max_visible) / math.max(1, #stations)) * 100)
        if progress > 100 then progress = 100 end
        io.write(string.format("\x1b[24;1H\x1b[7m  [FLECHES] FAIRE DEFILER LES STATIONS   |   [RETOUR] NOUVELLE RECH.      %02d%% \x1b[0m", progress))
        io.flush()
    end
    
    draw_page()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then break
        elseif k == "UP" or k == "Z" or k == "z" then if offset > 0 then offset = offset - 1; draw_page() end
        elseif k == "DOWN" or k == "S" or k == "s" then if offset + max_visible < #stations then offset = offset + 1; draw_page() end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[1m 3615 CARBURANT \x1b[0m                                       \x1b[1m COMPARATEUR PRIX \x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
    io.write("\x1b[10;1H                             \x1b[7m COMPARATEUR 2026 \x1b[0m\r\n\r\n")
    io.write("                  INDIQUEZ LE CODE POSTAL DE RECHERCHE\r\n")
    io.write("                  POUR AFFICHER LES PRIX DU JOUR\r\n\r\n")
    io.write("                           CODE POSTAL : \x1b[7m       \x1b[0m\x1b[7D")
    io.flush()
    
    local cp = input_cp()
    if cp == "ABORT" then break end
    if cp and #cp == 5 then
        local stations = fetch_stations(cp)
        if #stations > 0 then
            show_stations(cp, stations)
        else
            io.write("\x1b[12;15H\x1b[7m AUCUNE STATION TROUVEE DANS CE CODE POSTAL. \x1b[0m\x1b[K")
            io.flush()
            while minitel.get_key() ~= "RETOUR" and minitel.get_key() ~= "ESC" do minitel.sleep(0.1) end
        end
    end
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()