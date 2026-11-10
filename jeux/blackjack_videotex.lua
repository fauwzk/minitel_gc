-- Fichier : jeux/blackjack_videotex.lua
-- 3615 BLACKJACK en Videotex couleur : la meme partie que black.lua, sur un
-- tapis vert, avec de vraies cartes blanches et leurs enseignes dessinees en
-- mosaiques (coeurs et carreaux en rouge). Le Minitel repasse en 40 colonnes
-- le temps de la partie. Reglages (fonds, mise minimale, jeux de cartes) :
-- ceux de la version 80 colonnes, jeux/minitel_blackjack.cfg.
-- @GENRE: CASINO / VIDEOTEX COULEUR
-- @DESC: Le blackjack sur tapis vert en Videotex couleur : cartes blanches, coeurs et carreaux rouges, mise, doublement, blackjack paye 3 pour 2.

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- VIDEOTEX : CODES DE BASE
-- =====================================================================
local FF, US, SO, SI, ESC, REP = "\x0c", "\x1f", "\x0e", "\x0f", "\x1b", "\x12"
local COFF, CON = "\x14", "\x11"
local NOIR, ROUGE, VERT, JAUNE, BLEU, MAGENTA, CYAN, BLANC = 0, 1, 2, 3, 4, 5, 6, 7

local function at(row, col) return US .. string.char(0x40 + row, 0x40 + col) end
local function fg(c) return ESC .. string.char(0x40 + c) end
local function bg(c) return ESC .. string.char(0x50 + c) end
local BLINK, STEADY = ESC .. "\x48", ESC .. "\x49"
local NORMAL_SIZE, DOUBLE_HEIGHT, DOUBLE_SIZE = ESC .. "\x4c", ESC .. "\x4d", ESC .. "\x4f"

local function send(s) io.write(s) end

-- Texte sur le tapis : l'espace de tete porte le fond vert (en Videotex, le
-- fond d'un texte ne change qu'apres un espace)
local function felt_text(row, col, color, text, width)
    if width then text = text .. string.rep(" ", math.max(0, width - #text)) end
    send(at(row, col) .. bg(VERT) .. " " .. fg(color) .. text)
end

local function felt_row(row)
    send(at(row, 1) .. bg(VERT) .. SO .. " " .. REP .. string.char(0x40 + 39) .. SI)
end

-- =====================================================================
-- CLAVIER EN VIDEOTEX (touches de fonction SEP + code, ou lettres)
-- =====================================================================
local SEP_KEYS = { [0x41] = "ENVOI", [0x42] = "RETOUR", [0x43] = "REPETITION", [0x44] = "GUIDE",
                   [0x45] = "ANNULATION", [0x46] = "SOMMAIRE", [0x47] = "CORRECTION", [0x48] = "SUITE" }

local function read_key()
    local c = io.read(1)
    if not c then return nil end
    local b = string.byte(c) & 0x7f
    if b == 0x13 then
        local n = io.read(1)
        return n and SEP_KEYS[string.byte(n) & 0x7f] or nil
    end
    if b == 0x1b then
        local n = io.read(1)
        if not n then return "ESC" end
        if n == "[" then
            local d = io.read(1)
            return ({ A = "UP", B = "DOWN", C = "RIGHT", D = "LEFT" })[d or ""]
        end
        return nil
    end
    if b == 0x0d or b == 0x0a then return "ENVOI" end
    return string.upper(string.char(b))
end

local function wait_key()
    while true do
        local k = read_key()
        if k then return k end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- CONFIGURATION (partagee avec la version 80 colonnes)
-- =====================================================================
local config = { START_BANKROLL = 500, MIN_BET = 10, DECKS = 1 }
do
    local f = io.open("jeux/minitel_blackjack.cfg", "r")
    if f then
        for line in f:lines() do
            local k, v = string.match(line, "([^=]+)=(.+)")
            if k and config[k] ~= nil then config[k] = tonumber(v) or config[k] end
        end
        f:close()
    end
end

-- =====================================================================
-- LES CARTES
-- =====================================================================
-- Enseignes en mosaique : 6 x 6 pixels (3 cases sur 2 lignes)
local SUIT_ART = {
    COE = { ".X..X.", "XXXXXX", "XXXXXX", ".XXXX.", "..XX..", "......" },
    CAR = { "..XX..", ".XXXX.", "XXXXXX", ".XXXX.", "..XX..", "......" },
    PIQ = { "..XX..", ".XXXX.", "XXXXXX", "XXXXXX", "..XX..", ".XXXX." },
    TRE = { "..XX..", "..XX..", "XXXXXX", "XX..XX", "..XX..", ".XXXX." },
}
local SUIT_COLOR = { COE = ROUGE, CAR = ROUGE, PIQ = NOIR, TRE = NOIR }
local PIXEL_BIT = { { 1, 2 }, { 4, 8 }, { 16, 64 } }

-- Les deux lignes de caracteres mosaiques d'une enseigne
local function suit_rows(suit)
    local art = SUIT_ART[suit]
    local rows = {}
    for cr = 0, 1 do
        local chars = {}
        for cc = 0, 2 do
            local bits = 0
            for py = 1, 3 do
                for px = 1, 2 do
                    if art[cr * 3 + py]:sub(cc * 2 + px, cc * 2 + px) == "X" then bits = bits | PIXEL_BIT[py][px] end
                end
            end
            chars[#chars + 1] = string.char(0x20 + bits)
        end
        rows[cr + 1] = table.concat(chars)
    end
    return rows
end

local SUIT_ROWS = {}
for s in pairs(SUIT_ART) do SUIT_ROWS[s] = suit_rows(s) end

local CARD_W, CARD_H = 7, 5

-- Carte de 7 x 5 cases a la ligne row, colonne col
local function draw_card(row, col, card, hidden)
    if hidden then
        -- dos bleu a motif
        for i = 0, CARD_H - 1 do
            local pattern = (i % 2 == 0) and string.char(0x20 + 1 + 8 + 16) or string.char(0x20 + 2 + 4 + 64)
            send(at(row + i, col) .. bg(BLEU) .. fg(CYAN) .. SO .. string.rep(pattern, CARD_W) .. SI)
        end
        return
    end
    local color = SUIT_COLOR[card.suit]
    local face = card.face
    local sr = SUIT_ROWS[card.suit]
    send(at(row, col) .. bg(BLANC) .. " " .. fg(color) .. face .. string.rep(" ", CARD_W - 1 - #face))
    send(at(row + 1, col) .. bg(BLANC) .. fg(color) .. SO .. "  " .. sr[1] .. "  " .. SI)
    send(at(row + 2, col) .. bg(BLANC) .. fg(color) .. SO .. "  " .. sr[2] .. "  " .. SI)
    send(at(row + 3, col) .. bg(BLANC) .. " " .. string.rep(" ", CARD_W - 1))
    send(at(row + 4, col) .. bg(BLANC) .. " " .. fg(color) .. string.rep(" ", CARD_W - 2 - #face) .. face .. " ")
end

local deck = {}

local function build_deck()
    deck = {}
    local ranks = { { "2", 2 }, { "3", 3 }, { "4", 4 }, { "5", 5 }, { "6", 6 }, { "7", 7 }, { "8", 8 }, { "9", 9 },
                    { "10", 10 }, { "V", 10 }, { "D", 10 }, { "R", 10 }, { "A", 11 } }
    for _ = 1, config.DECKS do
        for _, s in ipairs({ "COE", "PIQ", "TRE", "CAR" }) do
            for _, r in ipairs(ranks) do deck[#deck + 1] = { suit = s, face = r[1], val = r[2] } end
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function draw_a_card()
    if #deck == 0 then build_deck() end
    return table.remove(deck)
end

local function score(hand)
    local total, aces = 0, 0
    for _, c in ipairs(hand) do
        total = total + c.val
        if c.face == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do total, aces = total - 10, aces - 1 end
    return total
end

local function blackjack(hand) return #hand == 2 and score(hand) == 21 end

-- =====================================================================
-- LE TAPIS
-- =====================================================================
local DEALER_ROW, PLAYER_ROW = 4, 13
local bankroll, bet = config.START_BANKROLL, config.MIN_BET
local player, dealer = {}, {}

local function card_col(i, n)
    local step = n > 5 and 6 or 8
    return 1 + (i - 1) * step
end

local function draw_status()
    send(at(1, 1) .. fg(JAUNE) .. string.format("CAISSE %5d $", bankroll) .. at(1, 22) .. fg(CYAN) ..
        string.format("MISE %4d $", bet) .. "     ")
end

local function draw_scores(hide_dealer)
    local d
    if hide_dealer and dealer[1] then
        d = (dealer[1].face == "A" and 11 or dealer[1].val) .. " + ?"
    else
        d = tostring(score(dealer))
    end
    felt_text(DEALER_ROW - 1, 1, BLANC, "CROUPIER  " .. (#dealer > 0 and d or ""), 24)
    felt_text(PLAYER_ROW - 1, 1, BLANC, "VOUS      " .. (#player > 0 and tostring(score(player)) or ""), 24)
end

local function message(text, color)
    local lines = minitel.wrap(text, 37, 2)
    felt_text(19, 1, color or JAUNE, lines[1] or "", 38)
    felt_text(20, 1, color or JAUNE, lines[2] or "", 38)
end

local function keys_help(text)
    send(at(23, 1) .. fg(BLANC) .. text .. string.rep(" ", math.max(0, 40 - #text)))
end

local function draw_table()
    send(FF .. COFF)
    draw_status()
    for r = 2, 21 do felt_row(r) end
    send(at(22, 1) .. fg(VERT) .. SO .. string.char(0x20 + 1 + 2) .. REP .. string.char(0x40 + 39) .. SI)
    felt_text(9, 9, JAUNE, "BLACKJACK PAIE 3 POUR 2")
    felt_text(10, 7, VERT, "LE CROUPIER TIRE JUSQU'A 16")
end

local function draw_hands(hide_dealer)
    for i, c in ipairs(dealer) do draw_card(DEALER_ROW, card_col(i, #dealer), c, hide_dealer and i == 2) end
    for i, c in ipairs(player) do draw_card(PLAYER_ROW, card_col(i, #player), c, false) end
    draw_scores(hide_dealer)
end

local function deal_to(hand, row, hide)
    hand[#hand + 1] = draw_a_card()
    if #hand > 5 then
        -- les cartes se resserrent : on efface la rangee et on redessine
        for r = row, row + CARD_H - 1 do felt_row(r) end
        for i, c in ipairs(hand) do draw_card(row, card_col(i, #hand), c, hide and i == 2) end
    else
        draw_card(row, card_col(#hand, #hand), hand[#hand], hide)
    end
    minitel.play_sound("hit")
    io.flush()
    minitel.wait_output()
    minitel.sleep(0.35)
end

-- =====================================================================
-- UNE MAIN
-- =====================================================================
local function settle(doubled)
    draw_hands(false)
    local p, d = score(player), score(dealer)
    local pbj, dbj = blackjack(player), blackjack(dealer)
    local gain, text
    if p > 21 then gain, text = -bet, "VOUS SAUTEZ ! PERDU : " .. bet .. " $"
    elseif dbj and not pbj then gain, text = -bet, "BLACKJACK DU CROUPIER. PERDU : " .. bet .. " $"
    elseif pbj and not dbj then gain = math.floor(bet * 1.5); text = "BLACKJACK ! GAGNE : " .. gain .. " $"
    elseif d > 21 then gain, text = bet, "LE CROUPIER SAUTE ! GAGNE : " .. bet .. " $"
    elseif p > d then gain, text = bet, "VOUS BATTEZ LE CROUPIER ! +" .. bet .. " $"
    elseif d > p then gain, text = -bet, "LE CROUPIER GAGNE. PERDU : " .. bet .. " $"
    else gain, text = 0, "EGALITE : VOTRE MISE VOUS EST RENDUE."
    end
    bankroll = bankroll + gain
    minitel.submit_record("BLACKJACK", bankroll, "high", "$", "CAISSE LA PLUS HAUTE")
    if gain > 0 then
        minitel.play_sound("win")
        felt_text(9, 13, JAUNE, BLINK .. " GAGNE ! " .. STEADY, 20)
    elseif gain < 0 then
        minitel.play_sound("lose")
        felt_text(9, 13, ROUGE, " PERDU ", 20)
    else
        felt_text(9, 13, BLANC, " EGALITE ", 20)
    end
    if doubled then bet = bet // 2 end
    if bankroll <= 0 then
        bankroll = config.START_BANKROLL
        text = text .. " LE CASINO VOUS OFFRE " .. bankroll .. " $."
    end
    bet = math.max(config.MIN_BET, math.min(bet, bankroll))
    message(text, gain >= 0 and JAUNE or ROUGE)
    draw_status()
    keys_help("ENVOI : NOUVELLE MAIN  SOMMAIRE : FIN")
    io.flush()
end

local function dealer_turn()
    draw_hands(false)
    io.flush()
    minitel.sleep(0.6)
    while score(dealer) < 17 do
        message("LE CROUPIER TIRE UNE CARTE...", BLANC)
        deal_to(dealer, DEALER_ROW, false)
        draw_scores(false)
        minitel.sleep(0.5)
    end
end

-- Rend false pour quitter
local function play_hand()
    -- la mise
    draw_table()
    felt_text(15, 10, BLANC, "FAITES VOS JEUX", 24)
    local function show_bet()
        felt_text(16, 10, JAUNE, string.format("MISE : %d $", bet), 24)
        draw_status()
        io.flush()
    end
    message("CHOISISSEZ VOTRE MISE, PUIS ENVOI POUR DISTRIBUER.")
    keys_help("+/- MISE  ENVOI DONNE  SOMMAIRE FIN")
    show_bet()
    while true do
        local k = wait_key()
        if k == "+" or k == "UP" or k == "RIGHT" then bet = math.min(bankroll, bet + 10); show_bet()
        elseif k == "-" or k == "DOWN" or k == "LEFT" then bet = math.max(config.MIN_BET, bet - 10); show_bet()
        elseif k == "ENVOI" or k == " " then break
        elseif k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false
        end
    end
    bet = math.min(bet, bankroll)

    -- la donne
    player, dealer = {}, {}
    felt_row(15); felt_row(16)
    message("DISTRIBUTION DES CARTES...", BLANC)
    keys_help("")
    deal_to(player, PLAYER_ROW, false)
    deal_to(dealer, DEALER_ROW, false)
    deal_to(player, PLAYER_ROW, false)
    deal_to(dealer, DEALER_ROW, true)
    draw_scores(true)

    local doubled = false
    if not blackjack(player) then
        message("A VOUS DE JOUER.")
        keys_help("T TIRER  R RESTER  D DOUBLER")
        io.flush()
        while true do
            local k = wait_key()
            if k == "T" then
                deal_to(player, PLAYER_ROW, false)
                draw_scores(true)
                io.flush()
                if score(player) > 21 then break end
            elseif k == "R" or k == "ENVOI" then
                dealer_turn()
                break
            elseif k == "D" then
                if #player ~= 2 then
                    message("ON NE DOUBLE QU'AVEC DEUX CARTES.", ROUGE)
                elseif bankroll < bet * 2 then
                    message("CAISSE INSUFFISANTE POUR DOUBLER.", ROUGE)
                else
                    bet, doubled = bet * 2, true
                    draw_status()
                    deal_to(player, PLAYER_ROW, false)
                    draw_scores(true)
                    if score(player) <= 21 then dealer_turn() end
                    break
                end
                io.flush()
            elseif k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then
                return false
            end
        end
    end
    settle(doubled)
    while true do
        local k = wait_key()
        if k == "ENVOI" or k == " " then return true end
        if k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false end
    end
end

-- =====================================================================
-- ECRAN TITRE
-- =====================================================================
local function title_screen()
    send(FF .. COFF)
    for r = 1, 24 do felt_row(r) end
    send(at(4, 8) .. bg(VERT) .. " " .. fg(JAUNE) .. DOUBLE_SIZE .. "BLACKJACK" .. NORMAL_SIZE)
    felt_text(6, 12, CYAN, "CASINO MAGIS CLUB")
    draw_card(9, 11, { suit = "PIQ", face = "A" })
    draw_card(9, 21, { suit = "COE", face = "R" })
    felt_text(16, 8, BLANC, "BLACKJACK PAYE 3 POUR 2")
    felt_text(18, 8, BLANC, string.format("FONDS DE DEPART : %d $", config.START_BANKROLL))
    local best = minitel.get_record("BLACKJACK")
    if best then felt_text(19, 8, MAGENTA, string.format("RECORD : %d $", best)) end
    send(at(22, 8) .. bg(VERT) .. " " .. fg(JAUNE) .. BLINK .. "ENVOI : PRENDRE PLACE" .. STEADY)
    felt_text(23, 8, BLANC, "SOMMAIRE : QUITTER")
    io.flush()
    while true do
        local k = wait_key()
        if k == "ENVOI" or k == " " then return true end
        if k == "SOMMAIRE" or k == "RETOUR" or k == "ESC" then return false end
    end
end

-- =====================================================================
-- LANCEMENT : passage en Videotex, puis retour en 80 colonnes
-- =====================================================================
math.randomseed(os.time())
minitel.force_videotex()
build_deck()

while title_screen() do
    bankroll, bet = config.START_BANKROLL, config.MIN_BET
    while play_hand() do end
end

send(FF .. CON)
io.flush()
minitel.force_80()
minitel.cleanup()
