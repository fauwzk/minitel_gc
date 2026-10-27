-- @GENRE: TABLEAU DES RECORDS
-- @DESC: Les meilleurs resultats de tous les jeux du Magis Club : score, temps, vague, gains, avec la date du record et le nombre de parties.
-- @ART1:      .-----------------.
-- @ART2:      |  1. OUTRUN  ##  |
-- @ART3:      |  2. WOLF-3D #   |
-- @ART4:      |  3. POKER   #   |
-- @ART5:      '---[ RECORDS ]---'

local minitel = require("minitel")
minitel.init()

-- Tous les jeux qui tiennent un record, dans l'ordre d'affichage. Ceux qui
-- n'en ont pas encore apparaissent quand meme, avec un tiret.
local GAMES = {
    { "OUTRUN", "SCORE" },
    { "WOLF-3D", "PAS POUR LES 3 SOUS-SOLS" },
    { "NORDSCHLEIFE", "MEILLEUR TOUR (BTG)" },
    { "DEFENSE", "VAGUE ATTEINTE" },
    { "ENIGMA", "NOEUD LE PLUS PROFOND" },
    { "DECRYPTAGE", "ESSAIS POUR TROUVER" },
    { "QUIZZ SOLO", "CAGNOTTE" },
    { "BLACKJACK", "CAISSE LA PLUS HAUTE" },
    { "POKER", "PILE LA PLUS HAUTE" },
    { "BOURSE", "FORTUNE FINALE" },
    { "CENTRAL PTT", "RECETTE D'UN QUART" },
    { "GARAGE", "CAISSE DE L'ATELIER" },
    { "BATAILLE (VS IA)", "VICTOIRES" },
    { "BATAILLE (EN LIGNE)", "VICTOIRES" },
}

local LIST_TOP, LIST_ROWS = 6, 15

-- Nordschleife garde ses propres records (un par voiture) dans un fichier Lua
local function nordschleife_best()
    local f = loadfile("jeux/nordschleife.rec")
    if not f then return nil end
    local ok, data = pcall(f)
    if not ok or type(data) ~= "table" then return nil end
    local best, car, count = nil, nil, 0
    for k, v in pairs(data) do
        if type(v) == "table" and tonumber(v.time) then
            count = count + 1
            if not best or v.time < best.time then best, car = v, k end
        end
    end
    if not best then return nil end
    return { value = best.time, sense = "low", unit = "BTG", date = "",
             detail = string.upper(tostring(car)) .. " - " .. string.upper(tostring(best.driver or "")),
             plays = count, cars = count }
end

local function thousands(n)
    local s = tostring(math.floor(math.abs(n)))
    s = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return (n < 0 and "-" or "") .. s
end

local function format_value(r)
    if r.unit == "BTG" then
        local m = math.floor(r.value / 60)
        return string.format("%d'%05.2f\"", m, r.value - m * 60)
    elseif r.unit == "S" then
        return string.format("%d:%02d", math.floor(r.value / 60), r.value % 60)
    end
    return thousands(r.value) .. " " .. (r.unit or "")
end

local rows = {}

local function load_rows()
    local recs = minitel.load_records()
    rows = {}
    local seen = {}
    for _, g in ipairs(GAMES) do
        local r = g[1] == "NORDSCHLEIFE" and nordschleife_best() or recs[g[1]]
        rows[#rows + 1] = { name = g[1], what = g[2], rec = r }
        seen[g[1]] = true
    end
    -- Les records du demineur (un par taille de grille) et ceux de jeux a venir
    local extra = {}
    for name in pairs(recs) do
        if not seen[name] then extra[#extra + 1] = name end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        local r = recs[name]
        local what = string.find(name, "^DEMINEUR") and ("TEMPS, " .. (r.detail or "")) or (r.detail or "")
        rows[#rows + 1] = { name = name, what = what, rec = r }
    end
end

local top = 1

local function draw_static()
    io.write("\x1b[0m\x1b[2J")
    minitel.title_bar("3615 RECORDS - LES MEILLEURS RESULTATS DU MAGIS CLUB")
    minitel.draw_frame(1, 3, 80, 20, "TABLEAU D'HONNEUR")
    io.write("\x1b[4;3H\x1b[1m" .. string.format("%-21s%-16s%-25s%-9s%5s", "JEU", "RECORD", "EPREUVE", "DATE", "PART.") .. "\x1b[0m")
    io.write("\x1b[5;3H" .. string.rep("-", 76))
    minitel.footer("[Z/S] DEFILER  |  [X] EFFACER LES RECORDS  |  [RETOUR] QUITTER")
end

local function draw_rows()
    if top > math.max(1, #rows - LIST_ROWS + 1) then top = math.max(1, #rows - LIST_ROWS + 1) end
    for i = 1, LIST_ROWS do
        local row = rows[top + i - 1]
        local line = ""
        if row then
            local r = row.rec
            local val = r and format_value(r) or "-"
            local date = r and r.date ~= "" and string.sub(r.date, 1, 6) .. string.sub(r.date, 9, 10) or ""
            local plays = r and r.plays and tostring(r.plays) or ""
            line = string.format("%-20s %-15s %-24s %-8s %5s",
                string.sub(row.name, 1, 20), string.sub(val, 1, 15), string.sub(row.what, 1, 24), date, plays)
        end
        local attr = row and row.rec and "\x1b[1m" or ""
        io.write(string.format("\x1b[%d;3H%s%s\x1b[0m", LIST_TOP + i - 1, attr, minitel.pad(line, 76)))
    end
    local total = 0
    for _, row in ipairs(rows) do if row.rec then total = total + 1 end end
    io.write("\x1b[21;3H" .. minitel.pad(string.format("%d RECORD(S) SUR %d JEUX", total, #rows) ..
        (#rows > LIST_ROWS and string.format("   (LIGNES %d-%d)", top, math.min(#rows, top + LIST_ROWS - 1)) or ""), 76))
    io.write("\x1b[24;80H")
    io.flush()
end

load_rows()
draw_static()
draw_rows()

while true do
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" or k == "SOMMAIRE" then
            break
        elseif k == "z" or k == "Z" or k == "UP" then
            if top > 1 then top = top - 1; draw_rows() end
        elseif k == "s" or k == "S" or k == "DOWN" then
            if top + LIST_ROWS - 1 < #rows then top = top + 1; draw_rows() end
        elseif k == "x" or k == "X" then
            if minitel.confirm_box("EFFACER", "Effacer tous les records (sauf Nordschleife) ?") then
                os.remove(minitel.RECORDS_FILE)
                load_rows()
            end
            draw_static()
            draw_rows()
        elseif k == "REPETITION" then
            draw_static()
            draw_rows()
        end
    end
    minitel.sleep(0.03)
end

minitel.cleanup()
