local minitel = require("minitel")
minitel.init()

-- =====================================================================
-- GESTION DE LA CONFIGURATION (SAUVEGARDE LOCALE)
-- =====================================================================
local config = {
    START_BANKROLL = 500,
    MIN_BET = 10,
    DECKS = 1
}

local function load_config()
    local file = io.open("minitel_blackjack.cfg", "r")
    if file then
        for line in file:lines() do
            local k, v = string.match(line, "([^=]+)=(.+)")
            if k and v and config[k] ~= nil then
                config[k] = tonumber(v) or config[k]
            end
        end
        file:close()
    end
end

local function save_config()
    local file = io.open("minitel_blackjack.cfg", "w")
    if file then
        for k, v in pairs(config) do
            file:write(k .. "=" .. tostring(v) .. "\n")
        end
        file:close()
    end
end

load_config()

-- =====================================================================
-- VARIABLES DU JEU ET DU CASINO
-- =====================================================================
local bankroll = config.START_BANKROLL
local current_bet = config.MIN_BET
local state = "TITLE" 
local msg_board = "BIENVENUE AU CASINO 3615."

local deck = {}
local player_hand = {}
local dealer_hand = {}

local title_cursor = 1
local settings_cursor = 1

-- =====================================================================
-- ECRAN TITRE ET PARAMETRES
-- =====================================================================
local function draw_title(full_redraw)
    if full_redraw then
        io.write("\x1b[2J\x1b[H") 
        io.flush()
        minitel.sleep(0.08) 
        
        io.write("\x1b[4;11H==========================================================\r\n")
        io.write("\x1b[5;11H|                                                        |\r\n")
        io.write("\x1b[6;11H|             \x1b[1m3 6 1 5   B L A C K J A C K\x1b[0m                |\r\n")
        io.write("\x1b[7;11H|                                                        |\r\n")
        io.write("\x1b[8;11H==========================================================\r\n")
        io.write("\x1b[12;23H FAITES SAUTER LA BANQUE (EN ASCII) \r\n")
    end
    
    local b_jouer = (title_cursor == 1) and "\x1b[7m [ ENTRER SUR LE TAPIS ] \x1b[0m" or "   ENTRER SUR LE TAPIS   "
    local b_param = (title_cursor == 2) and "\x1b[7m [ REGLES DU CASINO ] \x1b[0m"    or "   REGLES DU CASINO   "
    local b_quit  = (title_cursor == 3) and "\x1b[7m [ QUITTER ] \x1b[0m"             or "   QUITTER   "
    
    io.write("\x1b[16;1H\x1b[K\x1b[16;28H" .. b_jouer .. "\r\n")
    io.write("\x1b[18;1H\x1b[K\x1b[18;30H" .. b_param .. "\r\n")
    io.write("\x1b[20;1H\x1b[K\x1b[20;34H" .. b_quit .. "\r\n")
    
    io.write("\x1b[23;14H ZQSD / FLECHES : NAVIGUER  |  ESPACE / ENTREE : VALIDER \r\n")
    io.flush()
end

local function draw_settings()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    io.write("\x1b[4;25H\x1b[7m REGLES DU CASINO \x1b[0m\r\n\n")

    local opts = {
        {name="FONDS DE DEPART ($)", key="START_BANKROLL", format="%d"},
        {name="MISE MINIMALE ($)", key="MIN_BET", format="%d"},
        {name="NOMBRE DE JEUX (DECKS)", key="DECKS", format="%d"},
        {name="RETOUR (SAUVEGARDER)", key=nil}
    }

    for i, o in ipairs(opts) do
        local line = string.format("\x1b[%d;15H", 7 + (i*2))
        if i == settings_cursor then
            line = line .. "\x1b[7m> " .. o.name
        else
            line = line .. "  " .. o.name
        end

        if o.key then
            local val_str = string.format(o.format, config[o.key])
            if i == settings_cursor then
                line = line .. string.rep(" ", 32 - string.len(o.name)) .. "[< " .. val_str .. " >]\x1b[0m"
            else
                line = line .. string.rep(" ", 32 - string.len(o.name)) .. "   " .. val_str .. "   \x1b[0m"
            end
        else
            line = line .. " \x1b[0m"
        end
        io.write(line .. "\r\n")
    end
    io.write("\x1b[22;12H FLECHES: MODIFIER & NAVIGUER  |  ESPACE/ENTREE: VALIDER ")
    io.flush()
end

local function modify_setting(dir)
    if settings_cursor == 1 then
        config.START_BANKROLL = math.max(100, math.min(5000, config.START_BANKROLL + (100 * dir)))
    elseif settings_cursor == 2 then
        config.MIN_BET = math.max(5, math.min(500, config.MIN_BET + (5 * dir)))
    elseif settings_cursor == 3 then
        config.DECKS = math.max(1, math.min(6, config.DECKS + dir))
    end
end

-- =====================================================================
-- MOTEUR DU BLACKJACK (CARTES ET SCORE)
-- =====================================================================
local function build_deck()
    deck = {}
    local suits = {"COE", "PIQ", "TRE", "CAR"}
    local ranks = {
        {"2",2}, {"3",3}, {"4",4}, {"5",5}, {"6",6}, {"7",7}, {"8",8}, {"9",9}, {"10",10},
        {"V",10}, {"D",10}, {"R",10}, {"A",11}
    }
    for d = 1, config.DECKS do
        for _, s in ipairs(suits) do
            for _, r in ipairs(ranks) do
                table.insert(deck, {suit = s, face = r[1], val = r[2]})
            end
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

local function get_score(hand)
    local total = 0
    local aces = 0
    for _, c in ipairs(hand) do
        total = total + c.val
        if c.face == "A" then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end
    return total
end

local function check_blackjack(hand)
    return (#hand == 2 and get_score(hand) == 21)
end

-- =====================================================================
-- MOTEUR D'AFFICHAGE DIFFERENTIEL DU TAPIS
-- =====================================================================
local function update_hud_top()
    io.write("\x1b[1;1H\x1b[7m  3615 BLACKJACK   |   CREDITS : " .. bankroll .. " $   |   MISE : " .. current_bet .. " $  \x1b[K\x1b[0m")
    io.flush()
end

local function update_msg_bar()
    io.write("\x1b[23;1H\x1b[K  \x1b[1m" .. msg_board .. "\x1b[0m")
    io.flush()
end

local function update_action_bar()
    if state == "BETTING" then
        io.write("\x1b[24;1H\x1b[K  [Z/S] CHANGER MISE   |   [ESPACE] DISTRIBUER   |   [P] MENU")
    elseif state == "PLAYER_TURN" then
        io.write("\x1b[24;1H\x1b[K  [T] TIRER (HIT)   |   [R] RESTER (STAND)   |   [D] DOUBLER")
    elseif state == "GAMEOVER" then
        io.write("\x1b[24;1H\x1b[K  [ESPACE] NOUVELLE MAIN   |   [P] MENU")
    else
        io.write("\x1b[24;1H\x1b[K")
    end
    io.flush()
end

local function update_scores(hidden_dealer)
    local d_score = 0
    if hidden_dealer and #dealer_hand >= 1 then
        d_score = dealer_hand[1].val
        if dealer_hand[1].face == "A" then d_score = 11 end
    else
        d_score = get_score(dealer_hand)
    end
    
    local display_d_score = hidden_dealer and (d_score .. " + ?") or d_score
    io.write("\x1b[3;5H\x1b[K CROUPIER [ SCORE : " .. display_d_score .. " ]")
    
    local p_score = get_score(player_hand)
    io.write("\x1b[13;5H\x1b[K JOUEUR   [ SCORE : " .. p_score .. " ]")
    io.flush()
end

local function draw_single_card(x, y, card, hidden)
    if hidden then
        io.write("\x1b["..y..";"..x.."H.-------.")
        io.write("\x1b["..(y+1)..";"..x.."H|*******|")
        io.write("\x1b["..(y+2)..";"..x.."H|*MINI-*|")
        io.write("\x1b["..(y+3)..";"..x.."H|*-TEL *|")
        io.write("\x1b["..(y+4)..";"..x.."H|*******|")
        io.write("\x1b["..(y+5)..";"..x.."H'-------'")
    else
        local f = tostring(card.face)
        local s = card.suit
        local space1 = (string.len(f) == 2) and "   " or "    "
        local space2 = (string.len(f) == 2) and "   " or "    "
        
        io.write("\x1b["..y..";"..x.."H.-------.")
        io.write("\x1b["..(y+1)..";"..x.."H| " .. f .. space1 .. "|")
        io.write("\x1b["..(y+2)..";"..x.."H|  " .. s .. "  |")
        io.write("\x1b["..(y+3)..";"..x.."H|       |")
        io.write("\x1b["..(y+4)..";"..x.."H|" .. space2 .. f .. " |")
        io.write("\x1b["..(y+5)..";"..x.."H'-------'")
    end
    io.flush()
end

local function clear_play_area()
    for i=3, 21 do
        io.write("\x1b["..i..";1H\x1b[K")
    end
    io.flush()
end

-- =====================================================================
-- LOGIQUE DU JEU
-- =====================================================================
local function init_betting()
    state = "BETTING"
    clear_play_area()
    update_hud_top()
    update_msg_bar()
    update_action_bar()
    
    io.write("\x1b[10;25H\x1b[7m PLACEZ VOS MISES \x1b[0m")
    io.write("\x1b[12;25H\x1b[K MISE ACTUELLE : " .. current_bet .. " $")
    io.flush()
end

local function resolve_game()
    state = "GAMEOVER"
    local p_score = get_score(player_hand)
    local d_score = get_score(dealer_hand)
    local p_bj = check_blackjack(player_hand)
    local d_bj = check_blackjack(dealer_hand)
    
    draw_single_card(15, 5, dealer_hand[2], false)
    update_scores(false)
    minitel.sleep(0.5)
    
    if p_score > 21 then
        msg_board = "VOUS AVEZ SAUTE (>21) ! VOUS PERDEZ " .. current_bet .. " $."
        bankroll = bankroll - current_bet
        minitel.play_sound("lose")
    elseif d_bj and not p_bj then
        msg_board = "LE CROUPIER FAIT BLACKJACK ! VOUS PERDEZ " .. current_bet .. " $."
        bankroll = bankroll - current_bet
        minitel.play_sound("lose")
    elseif p_bj and not d_bj then
        local win = current_bet * 1.5
        msg_board = "BLACKJACK ! VOUS GAGNEZ " .. win .. " $ !"
        bankroll = bankroll + win
        minitel.play_sound("win")
    elseif p_score <= 21 and d_score > 21 then
        msg_board = "LE CROUPIER SAUTE ! VOUS GAGNEZ " .. current_bet .. " $."
        bankroll = bankroll + current_bet
        minitel.play_sound("win")
    elseif p_score > d_score then
        msg_board = "VOUS BATTEZ LE CROUPIER ! VOUS GAGNEZ " .. current_bet .. " $."
        bankroll = bankroll + current_bet
        minitel.play_sound("win")
    elseif d_score > p_score then
        msg_board = "LE CROUPIER GAGNE ! VOUS PERDEZ " .. current_bet .. " $."
        bankroll = bankroll - current_bet
        minitel.play_sound("lose")
    else
        msg_board = "EGALITE (PUSH). VOTRE MISE EST RECUPEREE."
    end
    
    if bankroll <= 0 then
        bankroll = config.START_BANKROLL
        msg_board = msg_board .. " LE CASINO VOUS OFFRE " .. config.START_BANKROLL .. " $."
    end
    if current_bet > bankroll then current_bet = bankroll end
    if current_bet < config.MIN_BET then current_bet = config.MIN_BET end
    
    update_hud_top()
    update_msg_bar()
    update_action_bar()
end

local function dealer_play()
    state = "DEALER_TURN"
    update_action_bar()
    
    draw_single_card(15, 5, dealer_hand[2], false)
    update_scores(false)
    minitel.sleep(1.0)
    
    while get_score(dealer_hand) < 17 do
        msg_board = "LE CROUPIER TIRE UNE CARTE..."
        update_msg_bar()
        minitel.sleep(0.8)
        
        table.insert(dealer_hand, draw_a_card())
        draw_single_card(5 + (#dealer_hand-1)*10, 5, dealer_hand[#dealer_hand], false)
        update_scores(false)
        minitel.play_sound("hit")
        minitel.sleep(1.0)
    end
    
    resolve_game()
end

-- =====================================================================
-- DEMARRAGE ET BOUCLE PRINCIPALE
-- =====================================================================
math.randomseed(os.time())
draw_title(true)

while true do
    local key = minitel.get_key()
    
    -- RETOUR GLOBAL AU MENU
    if (key == "p" or key == "P" or key == "RETOUR" or key == "ESC") and state ~= "TITLE" then
        if state == "SETTINGS" then save_config() end
        state = "TITLE"
        title_cursor = 1
        draw_title(true)
    else
        if state == "TITLE" then
            if key == "z" or key == "Z" or key == "UP" then
                title_cursor = title_cursor - 1
                if title_cursor < 1 then title_cursor = 3 end
                draw_title(false)
            elseif key == "s" or key == "S" or key == "DOWN" then
                title_cursor = title_cursor + 1
                if title_cursor > 3 then title_cursor = 1 end
                draw_title(false)
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                minitel.play_sound("hit")
                if title_cursor == 1 then
                    -- Lancement du jeu
                    bankroll = config.START_BANKROLL
                    current_bet = config.MIN_BET
                    build_deck()
                    
                    io.write("\x1b[2J\x1b[H")
                    io.write("\x1b[22;1H================================================================================")
                    io.flush()
                    minitel.sleep(0.08)
                    init_betting()
                    
                elseif title_cursor == 2 then
                    state = "SETTINGS"
                    settings_cursor = 1
                    draw_settings()
                elseif title_cursor == 3 then
                    break -- Quitte le script vers le portail Télétel
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "SETTINGS" then
            if key == "z" or key == "Z" or key == "UP" then
                settings_cursor = settings_cursor - 1
                if settings_cursor < 1 then settings_cursor = 4 end
                draw_settings()
            elseif key == "s" or key == "S" or key == "DOWN" then
                settings_cursor = settings_cursor + 1
                if settings_cursor > 4 then settings_cursor = 1 end
                draw_settings()
            elseif key == "q" or key == "Q" or key == "LEFT" then
                modify_setting(-1)
                draw_settings()
            elseif key == "d" or key == "D" or key == "RIGHT" then
                modify_setting(1)
                draw_settings()
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                minitel.play_sound("hit")
                if settings_cursor == 4 then
                    save_config()
                    state = "TITLE"
                    draw_title(true)
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "BETTING" then
            if key == "z" or key == "Z" or key == "UP" then
                current_bet = current_bet + 10
                if current_bet > bankroll then current_bet = bankroll end
                update_hud_top()
                io.write("\x1b[12;25H\x1b[K MISE ACTUELLE : " .. current_bet .. " $") io.flush()
            elseif key == "s" or key == "S" or key == "DOWN" then
                current_bet = current_bet - 10
                if current_bet < config.MIN_BET then current_bet = config.MIN_BET end
                update_hud_top()
                io.write("\x1b[12;25H\x1b[K MISE ACTUELLE : " .. current_bet .. " $") io.flush()
            elseif key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                if current_bet > bankroll then current_bet = bankroll end
                
                player_hand = {}
                dealer_hand = {}
                msg_board = "DISTRIBUTION DES CARTES..."
                
                clear_play_area()
                update_hud_top()
                update_msg_bar()
                
                table.insert(player_hand, draw_a_card())
                draw_single_card(5, 15, player_hand[1], false)
                update_scores(true) minitel.play_sound("hit") minitel.sleep(0.4)
                
                table.insert(dealer_hand, draw_a_card())
                draw_single_card(5, 5, dealer_hand[1], false)
                update_scores(true) minitel.play_sound("hit") minitel.sleep(0.4)
                
                table.insert(player_hand, draw_a_card())
                draw_single_card(15, 15, player_hand[2], false)
                update_scores(true) minitel.play_sound("hit") minitel.sleep(0.4)
                
                table.insert(dealer_hand, draw_a_card())
                draw_single_card(15, 5, dealer_hand[2], true)
                minitel.play_sound("hit") minitel.sleep(0.4)
                
                if check_blackjack(player_hand) then
                    resolve_game()
                else
                    state = "PLAYER_TURN"
                    msg_board = "A VOTRE TOUR DE JOUER."
                    update_msg_bar()
                    update_action_bar()
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "PLAYER_TURN" then
            if key == "t" or key == "T" then
                table.insert(player_hand, draw_a_card())
                draw_single_card(5 + (#player_hand-1)*10, 15, player_hand[#player_hand], false)
                update_scores(true)
                minitel.play_sound("hit")
                
                if get_score(player_hand) > 21 then
                    resolve_game()
                end
                
            elseif key == "r" or key == "R" then
                dealer_play()
                
            elseif key == "d" or key == "D" then
                if #player_hand == 2 and (bankroll >= current_bet * 2) then
                    current_bet = current_bet * 2
                    update_hud_top()
                    
                    table.insert(player_hand, draw_a_card())
                    draw_single_card(25, 15, player_hand[3], false)
                    update_scores(true)
                    minitel.play_sound("hit")
                    minitel.sleep(1.0)
                    
                    if get_score(player_hand) > 21 then
                        resolve_game()
                    else
                        dealer_play()
                    end
                elseif #player_hand ~= 2 then
                    msg_board = "VOUS NE POUVEZ DOUBLER QU'AVEC 2 CARTES."
                    update_msg_bar()
                else
                    msg_board = "FONDS INSUFFISANTS POUR DOUBLER."
                    update_msg_bar()
                end
            end
            minitel.sleep(0.05)
            
        elseif state == "GAMEOVER" then
            if key == " " or key == "\n" or key == "\r" or key == "ENVOI" then
                msg_board = "NOUVELLE DONNE. PLACEZ VOS MISES."
                init_betting()
            end
            minitel.sleep(0.05)
        end
    end
end

minitel.cleanup()