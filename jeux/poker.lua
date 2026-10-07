local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

-- =====================================================================
-- CONFIGURATION DU JEU
-- =====================================================================
local chips = 100
local current_bet = 5

-- Noms et valeurs des cartes (de 1 a 6)
local CARD_TYPES = {
    { val = 1, name = "NUAGE", symbol = "(=)" },
    { val = 2, name = "CHAMPI", symbol = "(#)" },
    { val = 3, name = "FLEUR", symbol = "(@)" },
    { val = 4, name = "PIECE", symbol = "(&)" },
    { val = 5, name = "MAGIS", symbol = "(M)" },
    { val = 6, name = "ETOILE", symbol = "(*)" }
}

-- Variables de la partie
local state = "BETTING"
local player_hand = {}
local dealer_hand = {}
local held_cards = {false, false, false, false, false}
local cursor = 1
local deck = {}
local message = "FAITES VOTRE MISE (FLECHES HAUT/BAS)"
local win_amount = 0

-- =====================================================================
-- MOTEUR DU JEU (PAQUET ET IA)
-- =====================================================================
local function init_deck()
    deck = {}
    for i = 1, 6 do
        for j = 1, 6 do table.insert(deck, i) end
    end
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function draw_card()
    if #deck == 0 then init_deck() end
    return table.remove(deck)
end

-- Evalue une main et retourne un score
local function evaluate(hand)
    local counts = {}
    for _, v in ipairs(hand) do counts[v] = (counts[v] or 0) + 1 end
    
    -- CORRECTION : Changement de nom pour ne pas ecraser la fonction pairs() de Lua
    local group_list = {}
    for val, count in pairs(counts) do table.insert(group_list, {val=val, count=count}) end
    
    table.sort(group_list, function(a,b)
        if a.count ~= b.count then return a.count > b.count end
        return a.val > b.val
    end)

    local score = 0
    local name = ""
    -- CORRECTION : Securisation des verifications group_list[2] au cas ou il n'y a qu'un groupe (ex: 5 identiques)
    if group_list[1].count == 5 then score = 7; name = "5 IDENTIQUES !"
    elseif group_list[1].count == 4 then score = 6; name = "CARRE"
    elseif group_list[1].count == 3 and group_list[2] and group_list[2].count == 2 then score = 5; name = "FULL"
    elseif group_list[1].count == 3 then score = 4; name = "BRELAN"
    elseif group_list[1].count == 2 and group_list[2] and group_list[2].count == 2 then score = 3; name = "DOUBLE PAIRE"
    elseif group_list[1].count == 2 then score = 2; name = "PAIRE"
    else score = 1; name = "CARTE HAUTE" end

    return score, group_list, name
end

local function dealer_ai(hand)
    local score, group_list = evaluate(hand)
    local holds = {false, false, false, false, false}
    
    if score >= 2 then
        local vals_to_hold = {}
        for _, p in ipairs(group_list) do
            if p.count >= 2 then vals_to_hold[p.val] = true end
        end
        for i, c in ipairs(hand) do
            if vals_to_hold[c] then holds[i] = true end
        end
    else
        local max_val = 0
        local max_idx = 1
        for i, c in ipairs(hand) do
            if c > max_val then max_val = c; max_idx = i end
        end
        holds[max_idx] = true
    end
    return holds
end

-- =====================================================================
-- MOTEUR GRAPHIQUE
-- =====================================================================
local function draw_single_card(x, y, card_val, hidden, inverted)
    local c = hidden and "\x1b[7m" or ""
    local res = "\x1b[0m"
    if inverted and not hidden then c = "\x1b[7m" end
    
    if hidden then
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s| MAGIS |%s", y+1, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s| POKER |%s", y+2, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s|       |%s", y+3, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y+4, x, c, res))
    else
        local t = CARD_TYPES[card_val]
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s|  %-3s  |%s", y+1, x, c, t.symbol, res))
        io.write(string.format("\x1b[%d;%dH%s|%-7s|%s", y+2, x, c, string.sub(t.name.."      ", 1, 7), res))
        io.write(string.format("\x1b[%d;%dH%s|       |%s", y+3, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y+4, x, c, res))
    end
end

local function draw_interface()
    -- Efface l'ecran et repositionne
    io.write("\x1b[r\x1b[2J\x1b[H")
    
    -- CORRECTION MISE EN PAGE : On retire les \r\n des lignes pleines (80 colonnes) pour eviter les scrolls inattendus
    io.write("\x1b[1;1H\x1b[1m 3615 POKER \x1b[0m                                             \x1b[1m CASINO MAGIS \x1b[0m")
    io.write("\x1b[2;1H================================================================================")
    
    io.write("\x1b[3;34H LE CROUPIER ")
    for i = 1, 5 do
        local x = 10 + ((i-1) * 12)
        if state == "SHOWDOWN" then
            draw_single_card(x, 4, dealer_hand[i], false, false)
        else
            if state == "BETTING" and #dealer_hand == 0 then
                -- Ne rien dessiner
            else
                draw_single_card(x, 4, 1, true, false)
            end
        end
    end
    
    io.write("\x1b[10;1H--------------------------------------------------------------------------------")
    io.write(string.format("\x1b[11;5H \x1b[1mJETONS : %04d \x1b[0m", chips))
    io.write(string.format("\x1b[11;32H \x1b[7m %s \x1b[0m", string.sub(" " .. message .. string.rep(" ", 30), 1, 38)))
    io.write(string.format("\x1b[11;65H \x1b[1mMISE : %02d \x1b[0m", current_bet))
    io.write("\x1b[12;1H--------------------------------------------------------------------------------")
    
    io.write("\x1b[13;36H VOUS ")
    for i = 1, 5 do
        local x = 10 + ((i-1) * 12)
        if #player_hand >= i then
            local is_selected = (state == "HOLDING" and cursor == i)
            draw_single_card(x, 14, player_hand[i], false, is_selected)
            
            if held_cards[i] then
                io.write(string.format("\x1b[19;%dH\x1b[7m GARDER \x1b[0m", x))
            else
                io.write(string.format("\x1b[19;%dH        ", x))
            end
        end
    end
    
    local footer = ""
    if state == "BETTING" then
        footer = "  [HAUT/BAS] MISER   |   [ENVOI] DISTRIBUER   |   [RETOUR] QUITTER        "
    elseif state == "HOLDING" then
        footer = "  [FLECHES] CHOISIR   |   [HAUT] GARDER/JETER   |   [ENVOI] VALIDER       "
    elseif state == "SHOWDOWN" then
        footer = "  [ENVOI] REJOUER UNE PARTIE   |   [RETOUR] QUITTER LE CASINO             "
    end
    
    local pad = string.rep(" ", 80 - #footer)
    io.write("\x1b[24;1H\x1b[7m" .. footer .. pad .. "\x1b[0m")
    io.flush()
end

-- =====================================================================
-- LOGIQUE DES PHASES
-- =====================================================================
local function do_showdown()
    local p_score, p_groups, p_name = evaluate(player_hand)
    local d_score, d_groups, d_name = evaluate(dealer_hand)
    
    local player_wins = false
    local tie = false
    
    if p_score > d_score then player_wins = true
    elseif p_score < d_score then player_wins = false
    else
        for i = 1, math.min(#p_groups, #d_groups) do
            if p_groups[i].val > d_groups[i].val then player_wins = true; break
            elseif p_groups[i].val < d_groups[i].val then player_wins = false; break
            end
            if i == math.min(#p_groups, #d_groups) then tie = true end
        end
    end
    
    if tie then
        message = "EGALITE ! " .. p_name
        chips = chips + current_bet
    elseif player_wins then
        local mult = 2
        if p_score == 7 then mult = 16
        elseif p_score == 6 then mult = 8
        elseif p_score == 5 then mult = 6
        elseif p_score == 4 then mult = 4
        elseif p_score == 3 then mult = 3 end
        
        local gain = current_bet * mult
        message = p_name .. " ! VOUS GAGNEZ " .. gain .. " !"
        chips = chips + gain
    else
        message = d_name .. " GAGNE ! PERDU."
    end
    
    state = "SHOWDOWN"
    draw_interface()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
math.randomseed(os.time())
draw_interface()

while true do
    local k = minitel.get_key()
    
    if k == "RETOUR" or k == "ESC" then
        break
    end
    
    if state == "BETTING" then
        if k == "UP" or k == "Z" or k == "z" then
            if current_bet < 5 and chips >= current_bet + 1 then current_bet = current_bet + 1 end
            draw_interface()
        elseif k == "DOWN" or k == "S" or k == "s" then
            if current_bet > 1 then current_bet = current_bet - 1 end
            draw_interface()
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            if chips >= current_bet then
                chips = chips - current_bet
                init_deck()
                player_hand = {draw_card(), draw_card(), draw_card(), draw_card(), draw_card()}
                dealer_hand = {draw_card(), draw_card(), draw_card(), draw_card(), draw_card()}
                held_cards = {false, false, false, false, false}
                cursor = 1
                message = "CHOISISSEZ LES CARTES A GARDER."
                state = "HOLDING"
                draw_interface()
            end
        end
        
    elseif state == "HOLDING" then
        if k == "LEFT" or k == "Q" or k == "q" then
            if cursor > 1 then cursor = cursor - 1 end
            draw_interface()
        elseif k == "RIGHT" or k == "D" or k == "d" then
            if cursor < 5 then cursor = cursor + 1 end
            draw_interface()
        elseif k == "UP" or k == "DOWN" or k == "Z" or k == "S" or k == "z" or k == "s" then
            held_cards[cursor] = not held_cards[cursor]
            draw_interface()
        elseif k == "ENVOI" or k == "\n" or k == "\r" then
            for i = 1, 5 do
                if not held_cards[i] then player_hand[i] = draw_card() end
            end
            
            local d_holds = dealer_ai(dealer_hand)
            for i = 1, 5 do
                if not d_holds[i] then dealer_hand[i] = draw_card() end
            end
            
            do_showdown()
        end
        
    elseif state == "SHOWDOWN" then
        if k == "ENVOI" or k == "\n" or k == "\r" then
            if chips == 0 then
                message = "RUINE ! LE MAGIS CLUB VOUS OFFRE 50 JETONS."
                chips = 50
            else
                message = "FAITES VOTRE MISE (FLECHES HAUT/BAS)"
            end
            player_hand = {}
            dealer_hand = {}
            if current_bet > chips then current_bet = chips end
            state = "BETTING"
            draw_interface()
        end
    end
    
    minitel.sleep(0.02)
end

io.write("\x1b[r\x1b[2J\x1b[H")
io.flush()
minitel.cleanup()