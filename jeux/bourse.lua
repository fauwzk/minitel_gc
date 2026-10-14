-- @GENRE: GESTION / SPECULATION
-- @DESC: Achetez et revendez des composants rares entre 6 villes en 30 jours. Remboursez votre dette et faites fortune !

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p jeux/saves_bourse 2>/dev/null")
math.randomseed(os.time())

-- =====================================================================
-- CONFIGURATION DU MARCHE & DES VILLES
-- =====================================================================
local ITEMS = {
    { id = "disquette", name = "DISQUETTES 5.25", min_p = 15,   max_p = 65   },
    { id = "modem",     name = "MODEMS V.23",     min_p = 80,   max_p = 260  },
    { id = "eprom",     name = "EPROM 27C256",    min_p = 180,  max_p = 550  },
    { id = "z80",       name = "PROCESSEURS Z80", min_p = 450,  max_p = 1300 },
    { id = "ram",       name = "BARRETTES 64KO",  min_p = 900,  max_p = 2800 },
    { id = "tube",      name = "TUBES CATHOD.",   min_p = 2000, max_p = 5500 },
    { id = "minitel",   name = "TERMINAUX MAGIS", min_p = 4500, max_p = 13000},
    { id = "mainframe", name = "CARTES TELECOM",  min_p = 9500, max_p = 28000}
}

local CITIES = {
    "PARIS - VELIZY",
    "CHAUMONT",
    "REIMS",
    "LYON - LA DOUA",
    "GRENOBLE",
    "RENNES - CCETT"
}

-- =====================================================================
-- ETAT DE LA PARTIE
-- =====================================================================
local state = {}
local cursor = 1
local running = true
local is_modified = false

local function init_new_game()
    state = {
        day = 1,
        max_days = 30,
        city = 1,
        cash = 2500,
        bank = 0,
        debt = 5000, -- Dette de depart (interets +8% par jour !)
        capacity = 100,
        stock = {},
        avg_cost = {},
        prices = {},
        trend = {},
        news = "BIENVENUE SUR 3615 BOURSE. REMBOURSEZ VOTRE DETTE AVANT LE JOUR 30 !"
    }
    for i = 1, #ITEMS do
        state.stock[i] = 0
        state.avg_cost[i] = 0
        state.prices[i] = math.floor((ITEMS[i].min_p + ITEMS[i].max_p) / 2)
        state.trend[i] = " "
    end
    is_modified = false
end

local function get_used_space()
    local total = 0
    for i = 1, #ITEMS do total = total + (state.stock[i] or 0) end
    return total
end

local function get_net_worth()
    local stock_val = 0
    for i = 1, #ITEMS do
        stock_val = stock_val + (state.stock[i] * state.prices[i])
    end
    return state.cash + state.bank + stock_val - state.debt
end

-- =====================================================================
-- SIMULATION DU MARCHE & EVENEMENTS ALEATOIRES
-- =====================================================================
local function generate_market(trigger_events)
    local event_title, event_msg, event_sound = nil, nil, nil
    state.news = "MARCHE STABLE A " .. CITIES[state.city] .. "."

    -- Calcul des nouveaux prix
    for i, it in ipairs(ITEMS) do
        local old_p = state.prices[i] or it.min_p
        local new_p = math.random(it.min_p, it.max_p)
        state.prices[i] = new_p
        if new_p > old_p * 1.15 then state.trend[i] = "+"
        elseif new_p < old_p * 0.85 then state.trend[i] = "-"
        else state.trend[i] = "=" end
    end

    if not trigger_events then return nil end

    -- Tirage d'un evenement special (40% de chance a chaque voyage)
    local roll = math.random(1, 100)
    if roll <= 15 then
        -- Penurie : un produit explose (x3)
        local idx = math.random(1, #ITEMS)
        state.prices[idx] = math.floor(ITEMS[idx].max_p * math.random(22, 32) / 10)
        state.trend[idx] = "!"
        state.news = "PENURIE : " .. ITEMS[idx].name .. " HORS DE PRIX !"
        event_title = "FLASH BOURSIER : PENURIE"
        event_msg = "Rupture de stock industrielle sur : " .. ITEMS[idx].name .. " ! Les cours s'envolent !"
        event_sound = "win"

    elseif roll <= 30 then
        -- Surplus d'usine : un produit s'effondre (/3)
        local idx = math.random(1, #ITEMS)
        state.prices[idx] = math.max(5, math.floor(ITEMS[idx].min_p / 3))
        state.trend[idx] = "v"
        state.news = "DESTOCKAGE MASSIF : " .. ITEMS[idx].name .. " A PRIX CASSE !"
        event_title = "OPPORTUNITE : SURPLUS"
        event_msg = "Une usine liquide son stock de " .. ITEMS[idx].name .. " a prix derisoire !"
        event_sound = "pickup"

    elseif roll <= 36 and get_used_space() > 0 then
        -- Controle douanier / PTT
        local idx = math.random(1, #ITEMS)
        if state.stock[idx] > 0 then
            local lost = math.max(1, math.floor(state.stock[idx] / 3))
            state.stock[idx] = state.stock[idx] - lost
            state.news = "CONTROLE PTT : SAISIE DE " .. lost .. " " .. ITEMS[idx].name .. "."
            event_title = "INSPECTION DES PTT !"
            event_msg = "La brigade des telecommunications saisit " .. lost .. "x " .. ITEMS[idx].name .. " non homologues dans votre coffre !"
            event_sound = "lose"
        end

    elseif roll <= 42 then
        -- Agrandissement de coffre
        if state.cash >= 1000 and state.capacity < 250 then
            state.news = "UN GARAGISTE LOCAL PROPOSE D'AGRANDIR VOTRE COFFRE."
            if minitel.confirm_box("ATELIER AUTO", "Installer une galerie de toit (+30 places de stock) pour 1000 F ?") then
                state.cash = state.cash - 1000
                state.capacity = state.capacity + 30
                event_title = "ATELIER AUTO"
                event_msg = "Capacite de transport portee a " .. state.capacity .. " unites !"
                event_sound = "win"
            end
        end
    end

    return event_title, event_msg, event_sound
end

-- =====================================================================
-- AFFICHAGE OPTIMISE DELTA-DRAWING (9600 BAUDS)
-- =====================================================================
local function draw_row(idx)
    local it = ITEMS[idx]
    local y = 8 + idx
    local p_str = string.format("%6d F", state.prices[idx])
    local tr = state.trend[idx] or " "
    local st = state.stock[idx] or 0
    local st_str = st > 0 and string.format("%3d", st) or "  -"
    local line = string.format(" %-15s %s %s %s ", it.name, p_str, tr, st_str)

    if idx == cursor then
        io.write(string.format("\x1b[%d;3H\x1b[7m>%s<\x1b[0m", y, minitel.pad(line, 33)))
    else
        io.write(string.format("\x1b[%d;3H %s ", y, minitel.pad(line, 33)))
    end
end

local function draw_stats_panel()
    local used = get_used_space()
    local cur_item = ITEMS[cursor]
    local avg = state.avg_cost[cursor] or 0
    local max_buy = math.min(state.capacity - used, math.floor(state.cash / state.prices[cursor]))

    -- Entete Ville & Jour
    io.write(string.format("\x1b[2;3H\x1b[7m VILLE : %-22s \x1b[0m", CITIES[state.city]))
    io.write(string.format("\x1b[2;56H\x1b[7m JOUR : %02d / %02d \x1b[0m", state.day, state.max_days))

    -- Finances (Panneau droit lignes 8 a 11)
    io.write(string.format("\x1b[8;42H LIQUIDE  : \x1b[1m%12d F\x1b[0m", state.cash))
    io.write(string.format("\x1b[9;42H BANQUE   : %12d F (+3%%/J)", state.bank))
    if state.debt > 0 then
        io.write(string.format("\x1b[10;42H DETTE    : \x1b[7m%12d F\x1b[0m (+8%%/J)", state.debt))
    else
        io.write(string.format("\x1b[10;42H DETTE    : %12s          ", "0 F (SOLDEE)"))
    end
    io.write(string.format("\x1b[11;42H FORTUNE  : \x1b[1m%12d F\x1b[0m", get_net_worth()))

    -- Jauges SDK (Lignes 13 et 15)
    io.write(string.format("\x1b[13;42H COFFRE (%03d/%03d) :", used, state.capacity))
    minitel.progress_bar(43, 14, 34, used, state.capacity, true)

    io.write("\x1b[16;42H ECHEANCE MISSION :")
    minitel.progress_bar(43, 17, 34, state.day, state.max_days, false)

    -- Detail du produit selectionne (Bas du panneau gauche, ligne 18)
    local info_item = string.format("PRIX ACHAT MOY: %d F | MAX: %d", avg, math.max(0, max_buy))
    io.write(string.format("\x1b[18;3H %s", minitel.pad(info_item, 33)))

    -- Bandeau Ticker / Flash Info (Ligne 21)
    io.write(string.format("\x1b[21;4H\x1b[1mFLASH :\x1b[0m %s", minitel.pad(state.news, 66)))
    io.flush()
end

local function draw_full_screen()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Bandeau Titre
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 BOURSE - SPECULATION & COMPOSANTS  * * *", 80) .. "\x1b[0m")
    io.write("\x1b[2;1H\x1b[7m" .. string.rep(" ", 80) .. "\x1b[0m")

    -- Fenetres SDK
    minitel.draw_window(2, 4, 37, 16, "COURS DU MARCHE LOCAL")
    minitel.draw_window(40, 4, 40, 16, "PORTEFEUILLE & TELEMETRIE")

    -- Entete colonnes marche
    io.write("\x1b[6;3H\x1b[1m COMPOSANT          PRIX   T STK\x1b[0m")
    io.write("\x1b[7;2H\x1b[1m+-----------------------------------+\x1b[0m")
    io.write("\x1b[17;2H\x1b[1m+-----------------------------------+\x1b[0m")

    -- Separateur panneau droit
    io.write("\x1b[12;40H\x1b[1m+--------------------------------------+\x1b[0m")
    io.write("\x1b[18;42H [A] ACHETER  [V] VENDRE  [B] BANQUE")

    -- Fenetre Ticker en bas
    minitel.draw_window(2, 20, 78, 3, "")

    -- Pied de page des commandes
    io.write("\x1b[24;1H\x1b[7m [Z/S] CHOIX | [A]CHETER | [V]ENDRE | [T]RAJET | [B]ANQUE | [RETOUR] MENU     \x1b[0m")

    for i = 1, #ITEMS do draw_row(i) end
    draw_stats_panel()
end

-- =====================================================================
-- ACTIONS DU JOUEUR (UTILISATION DES BOITES SDK)
-- =====================================================================
local function action_buy()
    local it = ITEMS[cursor]
    local price = state.prices[cursor]
    local free_space = state.capacity - get_used_space()
    local max_afford = math.floor(state.cash / price)
    local max_buy = math.min(free_space, max_afford)

    if max_buy <= 0 then
        if free_space <= 0 then
            minitel.msg_box("COFFRE PLEIN", "Votre coffre est plein (" .. state.capacity .. " unites max). Vendez d'abord !", "lose")
        else
            minitel.msg_box("FONDS INSUFFISANTS", "Vous n'avez pas assez de liquide pour acheter : " .. it.name, "lose")
        end
        draw_full_screen()
        return
    end

    local prompt = string.format("Prix: %d F | Max possible: %d", price, max_buy)
    local rep = minitel.input_box("ACHETER : " .. it.name, prompt, tostring(max_buy), 10)
    local qty = tonumber(rep)

    if qty and qty > 0 then
        qty = math.floor(math.min(qty, max_buy))
        local total_cost = qty * price
        local old_qty = state.stock[cursor]
        local old_avg = state.avg_cost[cursor]

        state.cash = state.cash - total_cost
        state.stock[cursor] = old_qty + qty
        state.avg_cost[cursor] = math.floor(((old_qty * old_avg) + total_cost) / state.stock[cursor])
        state.news = string.format("ACHAT : %dx %s POUR %d F.", qty, it.name, total_cost)
        is_modified = true
        minitel.play_sound("pickup")
    end
    draw_full_screen()
end

local function action_sell()
    local it = ITEMS[cursor]
    local owned = state.stock[cursor] or 0

    if owned <= 0 then
        minitel.msg_box("STOCK VIDE", "Vous ne possedez aucun stock de : " .. it.name, "lose")
        draw_full_screen()
        return
    end

    local price = state.prices[cursor]
    local avg = state.avg_cost[cursor] or 0
    local diff = price - avg
    local sign = diff >= 0 and "+" or ""
    local prompt = string.format("En stock: %d | Marge/u: %s%d F", owned, sign, diff)

    local rep = minitel.input_box("VENDRE : " .. it.name, prompt, tostring(owned), 10)
    local qty = tonumber(rep)

    if qty and qty > 0 then
        qty = math.floor(math.min(qty, owned))
        local gain = qty * price
        state.cash = state.cash + gain
        state.stock[cursor] = owned - qty
        if state.stock[cursor] == 0 then state.avg_cost[cursor] = 0 end
        state.news = string.format("VENTE : %dx %s POUR %d F.", qty, it.name, gain)
        is_modified = true
        minitel.play_sound("win")
    end
    draw_full_screen()
end

local function action_bank()
    while true do
        minitel.draw_window(18, 6, 46, 12, "CAISSE NATIONALE TELECOM")
        io.write(string.format("\x1b[8;21H LIQUIDE DISPONIBLE : %10d F", state.cash))
        io.write(string.format("\x1b[9;21H EPARGNE (+3%%/JOUR) : %10d F", state.bank))
        io.write(string.format("\x1b[10;21H DETTE   (+8%%/JOUR) : %10d F", state.debt))

        io.write("\x1b[12;21H \x1b[7m [1] \x1b[0m REMBOURSER LA DETTE")
        io.write("\x1b[13;21H \x1b[7m [2] \x1b[0m DEPOSER SUR LE LIVRET")
        io.write("\x1b[14;21H \x1b[7m [3] \x1b[0m RETIRER DU LIVRET")
        io.write("\x1b[16;21H \x1b[7m [RETOUR] \x1b[0m REVENIR AU MARCHE")
        io.flush()

        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then
            break
        elseif k == "1" then
            local max_pay = math.min(state.cash, state.debt)
            if max_pay <= 0 then
                minitel.msg_box("BANQUE", "Aucune dette a rembourser ou pas de liquide !", "lose")
            else
                local rep = minitel.input_box("REMBOURSER DETTE", "Montant (Max " .. max_pay .. " F) :", tostring(max_pay), 12)
                local val = tonumber(rep)
                if val and val > 0 then
                    val = math.floor(math.min(val, max_pay))
                    state.cash = state.cash - val
                    state.debt = state.debt - val
                    is_modified = true
                    minitel.play_sound("win")
                end
            end
        elseif k == "2" then
            if state.cash > 0 then
                local rep = minitel.input_box("DEPOT EPARGNE", "Montant a deposer :", tostring(state.cash), 12)
                local val = tonumber(rep)
                if val and val > 0 then
                    val = math.floor(math.min(val, state.cash))
                    state.cash = state.cash - val
                    state.bank = state.bank + val
                    is_modified = true
                    minitel.play_sound("pickup")
                end
            end
        elseif k == "3" then
            if state.bank > 0 then
                local rep = minitel.input_box("RETRAIT EPARGNE", "Montant a retirer :", tostring(state.bank), 12)
                local val = tonumber(rep)
                if val and val > 0 then
                    val = math.floor(math.min(val, state.bank))
                    state.bank = state.bank - val
                    state.cash = state.cash + val
                    is_modified = true
                    minitel.play_sound("pickup")
                end
            end
        end
        minitel.sleep(0.02)
    end
    draw_full_screen()
end

local function check_end_of_game()
    if state.day > state.max_days then
        local worth = get_net_worth()
        local verdict = worth >= 50000 and "MAGNAT DES TELECOMS !" or (worth >= 0 and "COMMERCANT HONNETE." or "FAILLITE TOTALE...")
        local msg = string.format("Fin du 30e jour ! Fortune nette finale : %d F. Rang : %s", worth, verdict)
        minitel.msg_box("BILAN DE FIN DE CARRIERE", msg, worth >= 0 and "win" or "lose")
        init_new_game()
        generate_market(false)
    end
end

local function action_travel()
    minitel.draw_window(20, 6, 42, 12, "CHOIX DE LA DESTINATION")
    for i, c_name in ipairs(CITIES) do
        local tag = (i == state.city) and "(ACTUEL)" or ""
        io.write(string.format("\x1b[%d;23H \x1b[7m [%d] \x1b[0m %-20s %s", 7 + i, i, c_name, tag))
    end
    io.write("\x1b[16;23H [1-6] VOYAGER  |  [RETOUR] ANNULER")
    io.flush()

    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" then
            draw_full_screen()
            return
        end
        local dest = tonumber(k)
        if dest and dest >= 1 and dest <= #CITIES then
            if dest == state.city then
                minitel.msg_box("TRAJET INUTILE", "Vous etes deja a " .. CITIES[dest] .. " !", "lose")
                draw_full_screen()
                return
            end

            -- Avancement d'un jour, calcul des interets
            state.city = dest
            state.day = state.day + 1
            state.bank = math.floor(state.bank * 1.03)
            state.debt = math.floor(state.debt * 1.08)
            is_modified = true
            minitel.play_sound("hit")

            local ev_title, ev_msg, ev_snd = generate_market(true)
            draw_full_screen()
            if ev_title then
                minitel.msg_box(ev_title, ev_msg, ev_snd)
                draw_full_screen()
            end
            check_end_of_game()
            return
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- SAUVEGARDE / CHARGEMENT & MENU SYSTEME (VIA SDK FILE_BROWSER)
-- =====================================================================
local function save_career(path)
    local f = io.open(path, "w")
    if not f then return false end
    f:write("return {\n")
    f:write(string.format("  day=%d, max_days=%d, city=%d, cash=%d, bank=%d, debt=%d, capacity=%d,\n",
        state.day, state.max_days, state.city, state.cash, state.bank, state.debt, state.capacity))
    f:write(string.format("  news=%q,\n", state.news))
    f:write("  stock={"); for i=1,#ITEMS do f:write((state.stock[i] or 0)..",") end; f:write("},\n")
    f:write("  avg_cost={"); for i=1,#ITEMS do f:write((state.avg_cost[i] or 0)..",") end; f:write("},\n")
    f:write("  prices={"); for i=1,#ITEMS do f:write((state.prices[i] or 100)..",") end; f:write("},\n")
    f:write("  trend={"); for i=1,#ITEMS do f:write(string.format("%q,", state.trend[i] or " ")) end; f:write("}\n")
    f:write("}\n")
    f:close()
    return true
end

local function load_career(path)
    local f = loadfile(path)
    if f then
        local ok, data = pcall(f)
        if ok and type(data) == "table" and data.cash and data.stock then
            state = data
            is_modified = false
            return true
        end
    end
    return false
end

local function handle_system_menu()
    while true do
        io.write("\x1b[r\x1b[2J\x1b[H")
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center("3615 BOURSE - MENU SYSTEME", 80) .. "\x1b[0m")
        minitel.draw_window(22, 5, 38, 14, "GESTION DE CARRIERE")
        io.write("\x1b[7;26H\x1b[7m [1] \x1b[0m REPRENDRE LA PARTIE")
        io.write("\x1b[9;26H\x1b[7m [2] \x1b[0m NOUVELLE CARRIERE")
        io.write("\x1b[11;26H\x1b[7m [3] \x1b[0m CHARGER UNE PARTIE...")
        io.write("\x1b[13;26H\x1b[7m [4] \x1b[0m SAUVEGARDER LA PARTIE...")
        io.write("\x1b[16;26H\x1b[7m [9] \x1b[0m QUITTER VERS LE PORTAIL")
        io.flush()

        local k = minitel.get_key()
        if k == "1" or k == "RETOUR" or k == "ESC" then
            break
        elseif k == "2" then
            if not is_modified or minitel.confirm_box("NOUVELLE PARTIE", "Recommencer a zero et perdre la progression actuelle ?") then
                init_new_game()
                generate_market(false)
                break
            end
        elseif k == "3" then
            local target = minitel.file_browser("OPEN", "jeux/saves_bourse/")
            if target then
                if load_career(target) then
                    minitel.msg_box("CHARGEMENT", "Carriere restauree avec succes !", "win")
                    break
                else
                    minitel.msg_box("ERREUR", "Fichier de sauvegarde invalide.", "lose")
                end
            end
        elseif k == "4" then
            local target = minitel.file_browser("SAVE", "jeux/saves_bourse/")
            if target then
                if save_career(target) then
                    is_modified = false
                    minitel.msg_box("SAUVEGARDE", "Carriere sauvegardee sur le disque !", "win")
                    break
                else
                    minitel.msg_box("ERREUR", "Impossible d'ecrire le fichier.", "lose")
                end
            end
        elseif k == "9" then
            if not is_modified or minitel.confirm_box("QUITTER", "Votre carriere n'est pas sauvegardee. Quitter quand meme ?") then
                running = false
                break
            end
        end
        minitel.sleep(0.02)
    end
    if running then draw_full_screen() end
end

-- =====================================================================
-- INITIALISATION & BOUCLE PRINCIPALE
-- =====================================================================
init_new_game()
generate_market(false)
draw_full_screen()

while running do
    local k = minitel.get_key()
    if k then
        local old_c = cursor
        if k == "UP" or k == "Z" or k == "z" then
            cursor = (cursor > 1) and (cursor - 1) or #ITEMS
            draw_row(old_c)
            draw_row(cursor)
            draw_stats_panel()
        elseif k == "DOWN" or k == "S" or k == "s" then
            cursor = (cursor < #ITEMS) and (cursor + 1) or 1
            draw_row(old_c)
            draw_row(cursor)
            draw_stats_panel()
        elseif k == "A" or k == "a" or k == "ENVOI" or k == "\r" or k == "\n" then
            action_buy()
        elseif k == "V" or k == "v" then
            action_sell()
        elseif k == "B" or k == "b" then
            action_bank()
        elseif k == "T" or k == "t" then
            action_travel()
        elseif k == "REPETITION" then
            draw_full_screen()
        elseif k == "RETOUR" or k == "ESC" then
            handle_system_menu()
        end
    end
    minitel.sleep(0.01)
end

minitel.cleanup()