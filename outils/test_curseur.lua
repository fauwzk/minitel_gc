-- =====================================================================
-- TEST DU CURSEUR : QUELLE COMMANDE LE CACHE SUR CE MINITEL ?
-- =====================================================================
-- En 80 colonnes, le Minitel ignore peut-etre la commande ANSI habituelle
-- (ESC [ ? 25 l). Ce test essaie les commandes connues d'autres terminaux,
-- une par une : pour chacune, dites si le curseur a disparu.
--
--   lua5.3 outils/test_curseur.lua   (depuis le terminal du portail)
--
-- Le resume s'affiche a la fin et reste dans /tmp/test_curseur.txt.

local minitel = require("minitel")
minitel.init()

local ESSAIS = {
    { "Aucune commande (temoin)",            "" },
    { "ANSI DECTCEM : ESC [ ? 25 l",          "\27[?25l" },
    { "Videotex COFF : code 14h",             "\20" },
    { "VT52 etendu : ESC f",                  "\27f" },
    { "Heathkit H19 : ESC x 5",               "\27x5" },
    { "ANSI sans ? : ESC [ 25 l",             "\27[25l" },
    { "Console Linux : ESC [ ? 1 c",          "\27[?1c" },
    { "Videotex COFF + ANSI DECTCEM",         "\20\27[?25l" },
}

-- Toutes les commandes inverses, pour repartir d'un curseur visible
local MONTRER = "\27[?25h\17\27e\27y5\27[?0c"

local function touche()
    while true do
        local k = minitel.get_key()
        if k then return k end
        minitel.sleep(0.05)
    end
end

local resultats = {}
local i = 1
while i <= #ESSAIS do
    local nom, seq = ESSAIS[i][1], ESSAIS[i][2]
    io.write(MONTRER .. "\27[0m\27[2J\27[H")
    minitel.title_bar("TEST DU CURSEUR")
    io.write(string.format("\27[4;3HEssai %d sur %d : \27[1m%s\27[0m", i, #ESSAIS, nom))
    io.write("\27[7;3HRegardez juste apres le signe > de la ligne du bas.")
    io.write("\27[9;3H  [O]  le curseur a disparu")
    io.write("\27[10;3H  [N]  le curseur est toujours visible")
    io.write("\27[11;3H  [P]  disparu, mais des caracteres parasites sont apparus")
    io.write("\27[12;3H  [R]  refaire cet essai        [Q]  arreter")
    minitel.footer("O / N / P : votre reponse    R : refaire    Q : arreter")
    io.write("\27[16;3HLe curseur est-il visible ici >")
    io.flush()
    minitel.sleep(0.3)
    io.write(seq)
    io.flush()

    local k = string.upper(touche())
    if k == "Q" or k == "SOMMAIRE" or k == "RETOUR" then break end
    if k == "O" or k == "N" or k == "P" then
        local verdict = ({ O = "CACHE", N = "visible", P = "cache, avec parasites" })[k]
        resultats[#resultats + 1] = string.format("%d. %-34s %s", i, nom, verdict)
        i = i + 1
    end
end

io.write(MONTRER .. "\27[0m\27[2J\27[H")
minitel.title_bar("TEST DU CURSEUR : RESULTATS")
for n, ligne in ipairs(resultats) do
    io.write(string.format("\27[%d;3H%s", 3 + n, ligne))
end
io.write(string.format("\27[%d;3HResultats enregistres dans /tmp/test_curseur.txt", 5 + #resultats))
minitel.footer("Une touche pour quitter")
io.flush()

local f = io.open("/tmp/test_curseur.txt", "w")
if f then
    f:write(table.concat(resultats, "\n") .. "\n")
    f:close()
end

touche()
minitel.cleanup()
