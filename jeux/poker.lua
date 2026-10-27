-- @GENRE: CASINO / CARTES
-- @DESC: Affrontez l'IA du Magis Club au Poker a 5 cartes. Misez vos jetons et tentez le Carre ou les 5 Identiques !

local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- CONFIGURATION DU JEU
-- =====================================================================
local chips = 100
local current_bet = 5

local CARD_TYPES = {
    { val = 1, name = "NUAGE",  symbol = "(=)" },
    { val = 2, name = "CHAMPI", symbol = "(#)" },
    { val = 3, name = "FLEUR",  symbol = "(@)" },
    { val = 4, name = "PIECE",  symbol = "(&)" },
    { val = 5, name = "MAGIS",  symbol = "(M)" },
    { val = 6, name = "ETOILE", symbol = "(*)" }
}

local state = "BETTING"
local player_hand = {}
local dealer_hand = {}
local held_cards = {false, false, false, false, false}
local cursor = 1
local deck = {}
local message = "[Z/S] MISER - [M] LIBRE - [ENVOI] JOUER"

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

local function evaluate(hand)
    local counts = {}
    for _, v in ipairs(hand) do counts[v] = (counts[v] or 0) + 1 end
    
    local group_list = {}
    for val, count in pairs(counts) do table.insert(group_list, {val=val, count=count}) end
    
    table.sort(group_list, function(a,b)
        if a.count ~= b.count then return a.count > b.count end
        return a.val > b.val
    end)

    local score, name = 0, ""
    if group_list[1].count == 5 then score = 7; name = "5 IDENTIQUES (x16)"
    elseif group_list[1].count == 4 then score = 6; name = "CARRE (x8)"
    elseif group_list[1].count == 3 and group_list[2] and group_list[2].count == 2 then score = 5; name = "FULL (x6)"
    elseif group_list[1].count == 3 then score = 4; name = "BRELAN (x4)"
    elseif group_list[1].count == 2 and group_list[2] and group_list[2].count == 2 then score = 3; name = "DOUBLE PAIRE (x3)"
    elseif group_list[1].count == 2 then score = 2; name = "PAIRE (x2)"
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
        local max_val, max_idx = 0, 1
        for i, c in ipairs(hand) do
            if c > max_val then max_val = c; max_idx = i end
        end
        holds[max_idx] = true
    end
    return holds
end

-- =====================================================================
-- MOTEUR GRAPHIQUE OPTIMISE (DELTA-DRAWING & SDK)
-- =====================================================================
local function draw_single_card(x, y, card_val, hidden, inverted)
    local c = (hidden or inverted) and "\x1b[7m" or ""
    local res = "\x1b[0m"
    
    if hidden then
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s| MAGIS |%s", y+1, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s| POKER |%s", y+2, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s|  ***  |%s", y+3, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y+4, x, c, res))
    else
        local t = CARD_TYPES[card_val]
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s|  %-3s  |%s", y+1, x, c, t.symbol, res))
        io.write(string.format("\x1b[%d;%dH%s|%s|%s", y+2, x, c, minitel.center(t.name, 7), res))
        io.write(string.format("\x1b[%d;%dH%s|       |%s", y+3, x, c, res))
        io.write(string.format("\x1b[%d;%dH%s+-------+%s", y+4, x, c, res))
    end
end

local function draw_player_slot(i)
    local x = 11 + ((i - 1) * 12)
    if #player_hand >= i then
        local is_selected = (state == "HOLDING" and cursor == i)
        draw_single_card(x, 15, player_hand[i], false, is_selected)
        if held_cards[i] then
            io.write(string.format("\x1b[20;%dH\x1b[7m  GARDER \x1b[0m", x))
        else
            io.write(string.format("\x1b[20;%dH         ", x))
        end
    else
        for r = 0, 5 do io.write(string.format("\x1b[%d;%dH         ", 15 + r, x)) end
    end
end

local function update_status_box()
    io.write(string.format("\x1b[11;6H\x1b[1mJETONS : %05d\x1b[0m", chips))
    io.write(string.format("\x1b[11;23H\x1b[7m%s\x1b[0m", minitel.center(string.sub(message, 1, 40), 40)))
    io.write(string.format("\x1b[11;66H\x1b[1mMISE : %03d\x1b[0m", current_bet))

    local footer = ""
    if state == "BETTING" then
        footer = "[Z/S] MISER | [M] MISE LIBRE | [ENVOI] DISTRIBUER | [G] TABLE GAINS | [RETOUR]"
    elseif state == "HOLDING" then
        footer = "[Q/D] CHOISIR | [Z/S] GARDER/JETER | [ENVOI] TIRER LES CARTES | [G] GAINS"
    elseif state == "SHOWDOWN" then
        footer = "[ENVOI] NOUVELLE DONNE | [G] TABLE DES GAINS | [RETOUR] QUITTER LE CASINO"
    end
    io.write("\x1b[24;1H\x1b[7m" .. minitel.center(footer, 80) .. "\x1b[0m")
    io.flush()
end

local function draw_full_table()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 POKER - CASINO MAGIS CLUB  * * *", 80) .. "\x1b[0m")
    io.write("\x1b[3;34H\x1b[1m[ LE CROUPIER ]\x1b[0m")

    for i = 1, 5 do
        local x = 11 + ((i - 1) * 12)
        if state == "SHOWDOWN" then
            draw_single_card(x, 4, dealer_hand[i], false, false)
        elseif #dealer_hand > 0 then
            draw_single_card(x, 4, 1, true, false)
        end
    end

    minitel.draw_window(4, 10, 74, 3, "")
    io.write("\x1b[14;34H\x1b[1m[ VOTRE MAIN ]\x1b[0m")

    for i = 1, 5 do draw_player_slot(i) end
    update_status_box()
end

local function show_paytable()
    minitel.draw_window(16, 4, 50, 16, "TABLE DES GAINS & VALEURS")
    io.write("\x1b[6;19H\x1b[1mCOMBINAISONS GAGNANTES :\x1b[0m")
    io.write("\x1b[7;20H- 5 IDENTIQUES : Mise x 16")
    io.write("\x1b[8;20H- CARRE        : Mise x 8")
    io.write("\x1b[9;20H- FULL         : Mise x 6")
    io.write("\x1b[10;20H- BRELAN       : Mise x 4")
    io.write("\x1b[11;20H- DOUBLE PAIRE : Mise x 3")
    io.write("\x1b[12;20H- PAIRE        : Mise x 2")

    io.write("\x1b[14;19H\x1b[1mORDRE DES CARTES (FAIBLE -> FORT) :\x1b[0m")
    io.write("\x1b[15;20H(=) NUAGE < (#) CHAMPI < (@) FLEUR")
    io.write("\x1b[16;20H(&) PIECE < (M) MAGIS  < (*) ETOILE")
    io.write("\x1b[18;28H\x1b[7m [ENVOI / RETOUR] FERMER \x1b[0m")
    io.flush()

    while true do
        local k = minitel.get_key()
        if k == "ENVOI" or k == "RETOUR" or k == "ESC" or k == "\r" or k == "\n" or k == " " then break end
        minitel.sleep(0.02)
    end
    draw_full_table()
end

-- =====================================================================
-- LOGIQUE DES PHASES
-- =====================================================================
local function do_showdown()
    local p_score, p_groups, p_name = evaluate(player_hand)
    local d_score, d_groups, d_name = evaluate(dealer_hand)
    
    local player_wins, tie = false, false
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
        message = "EGALITE ! MISE REMBOURSEE."
        chips = chips + current_bet
        minitel.play_sound("hit")
    elseif player_wins then
        local mult = 2
        if p_score == 7 then mult = 16
        elseif p_score == 6 then mult = 8
        elseif p_score == 5 then mult = 6
        elseif p_score == 4 then mult = 4
        elseif p_score == 3 then mult = 3 end
        
        local gain = current_bet * mult
        message = p_name .. " ! +" .. gain .. " JETONS !"
        chips = chips + gain
        minitel.play_sound("win")
    else
        message = "CROUPIER : " .. d_name .. ". PERDU."
        minitel.play_sound("lose")
    end
    
    state = "SHOWDOWN"
    draw_full_table()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
math.randomseed(os.time())
draw_full_table()

while true do
    local k = minitel.get_key()
    
    if k == "RETOUR" or k == "ESC" then
        if minitel.confirm_box("QUITTER LE CASINO", "Voulez-vous encaisser vos " .. chips .. " jetons et quitter la table ?") then
            break
        end
        draw_full_table()

    elseif k == "G" or k == "g" or k == "GUIDE" then
        show_paytable()

    elseif k == "REPETITION" then
        draw_full_table()
        
    elseif state == "BETTING" then
        if k == "UP" or k == "Z" or k == "z" then
            if current_bet < math.min(50, chips) then
                current_bet = current_bet + 1
                update_status_box()
            end
        elseif k == "DOWN" or k == "S" or k == "s" then
            if current_bet > 1 then
                current_bet = current_bet - 1
                update_status_box()
            end
        elseif k == "M" or k == "m" then
            local max_b = math.min(50, chips)
            local rep = minitel.input_box("MISE PERSONNALISEE", "Entrez votre mise (1 a " .. max_b .. " jetons) :", tostring(current_bet), 5)
            local val = tonumber(rep)
            if val and val >= 1 then
                current_bet = math.floor(math.min(val, max_b))
            end
            draw_full_table()
        elseif k == "ENVOI" or k == "\n" or k == "\r" or k == " " then
            if chips >= current_bet then
                minitel.play_sound("pickup")
                chips = chips - current_bet
                init_deck()
                player_hand = {draw_card(), draw_card(), draw_card(), draw_card(), draw_card()}
                dealer_hand = {draw_card(), draw_card(), draw_card(), draw_card(), draw_card()}
                held_cards = {false, false, false, false, false}
                cursor = 1
                message = "SELECTIONNEZ LES CARTES A GARDER"
                state = "HOLDING"
                draw_full_table()
            end
        end
        
    elseif state == "HOLDING" then
        if k == "LEFT" or k == "Q" or k == "q" then
            local old_c = cursor
            cursor = (cursor > 1) and (cursor - 1) or 5
            draw_player_slot(old_c)
            draw_player_slot(cursor)
            io.flush()
        elseif k == "RIGHT" or k == "D" or k == "d" then
            local old_c = cursor
            cursor = (cursor < 5) and (cursor + 1) or 1
            draw_player_slot(old_c)
            draw_player_slot(cursor)
            io.flush()
        elseif k == "UP" or k == "DOWN" or k == "Z" or k == "S" or k == "z" or k == "s" or k == " " then
            held_cards[cursor] = not held_cards[cursor]
            minitel.play_sound("hit")
            draw_player_slot(cursor)
            io.flush()
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
        if k == "ENVOI" or k == "\n" or k == "\r" or k == " " then
            if chips <= 0 then
                minitel.msg_box("BANQUEROUTE !", "Vous n'avez plus un sou ! Le Magis Club vous offre une avance de 50 jetons.", "win")
                chips = 50
            end
            message = "[Z/S] MISER - [M] LIBRE - [ENVOI] JOUER"
            player_hand = {}
            dealer_hand = {}
            if current_bet > chips then current_bet = chips end
            state = "BETTING"
            draw_full_table()
        end
    end
    
    minitel.sleep(0.01)
end

minitel.cleanup()