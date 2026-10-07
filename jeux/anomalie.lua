local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")

-- =====================================================================
-- VARIABLES GLOBALES ET SAUVEGARDE
-- =====================================================================
local state = {
    node = "start",
    hp = 100,
    max_hp = 100,
    credits = 0,
    inventory = {}
}

local save_file = "jeux/anomalie_save.txt"
local last_event_msg = ""
local is_playing = false

local function save_game()
    local f = io.open(save_file, "w")
    if f then
        f:write("node=" .. state.node .. "\n")
        f:write("hp=" .. state.hp .. "\n")
        f:write("max_hp=" .. state.max_hp .. "\n")
        f:write("credits=" .. state.credits .. "\n")
        for k, v in pairs(state.inventory) do
            if v then f:write("inv_" .. k .. "=true\n") end
        end
        f:close()
        return true
    end
    return false
end

local function load_game()
    local f = io.open(save_file, "r")
    if f then
        state.inventory = {}
        for line in f:lines() do
            local k, v = string.match(line, "([^=]+)=(.+)")
            if k == "node" then state.node = v
            elseif k == "hp" then state.hp = tonumber(v)
            elseif k == "max_hp" then state.max_hp = tonumber(v)
            elseif k == "credits" then state.credits = tonumber(v)
            elseif string.sub(k, 1, 4) == "inv_" then
                local item = string.sub(k, 5)
                state.inventory[item] = (v == "true")
            end
        end
        f:close()
        return true
    end
    return false
end

-- =====================================================================
-- LE MOTEUR D'HISTOIRE (LES NOEUDS)
-- =====================================================================
-- Chaque noeud (node) contient un texte et des choix.
-- Les choix peuvent avoir des conditions (req_item) ou declencher des actions (on_choose).
local STORY = {
    ["start"] = {
        text = "VOUS VOUS REVEILLEZ DANS L'OBSCURITE.\nL'odeur d'ozone et de metal brule vous prend a la gorge. Les ecrans de controle autour de vous clignotent faiblement, affichant 'ERREUR SECTEUR 4'. Vous etes dans le sas principal de la station relais.",
        choices = {
            { label = "Examiner la porte du sas", dest = "porte_sas" },
            { label = "Fouiller le casier entrouvert", dest = "casier", req_not_item = "badge" },
            { label = "S'enfoncer dans le couloir sombre", dest = "couloir" }
        }
    },
    
    ["casier"] = {
        text = "Le casier grince. A l'interieur, vous trouvez un VIEUX BADGE DE SECURITE et une ration d'urgence.",
        on_enter = function() 
            state.inventory["badge"] = true 
            state.hp = math.min(state.max_hp, state.hp + 10)
            last_event_msg = "OBTENTION: BADGE DE SECURITE | +10 INT" 
        end,
        choices = {
            { label = "Retourner au sas", dest = "start" }
        }
    },
    
    ["porte_sas"] = {
        text = "La lourde porte blindee est verouillee. Un lecteur magnetique rougeoie sur le panneau lateral.",
        choices = {
            { label = "Utiliser le badge de securite", dest = "dehors", req_item = "badge" },
            { label = "Frapper la porte (Inutile)", dest = "porte_sas", on_choose = function() last_event_msg = "La porte ne bouge pas d'un millimetre." end },
            { label = "Retourner au centre de la piece", dest = "start" }
        }
    },
    
    ["couloir"] = {
        text = "Le couloir est plonge dans le noir. Soudain, un DRONE DE MAINTENANCE au comportement erratique bloque le passage. Ses pinces crépitent d'electricite !",
        choices = {
            { label = "Attaquer le drone avec les poings", dest = "combat_drone" },
            { label = "Fuir vers le sas", dest = "start" }
        }
    },
    
    ["combat_drone"] = {
        text = "Vous vous jetez sur la machine. Les etincelles volent, le metal grince...",
        on_enter = function()
            local dmg = math.random(15, 30)
            state.hp = state.hp - dmg
            state.credits = state.credits + 50
            if state.hp > 0 then
                last_event_msg = "DRONE DETRUIT ! VOUS PERDEZ " .. dmg .. " INT | +50 CREDITS"
            end
        end,
        choices = {
            { label = "Continuer d'avancer", dest = "couloir_safe", req_hp = 1 },
            { label = "Accepter la defaite", dest = "gameover", req_hp = -999 } -- S'affiche si mort
        }
    },
    
    ["couloir_safe"] = {
        text = "L'epave du drone fume a vos pieds. Le couloir mene vers la salle des serveurs. La lumiere y est stable.",
        choices = {
            { label = "Entrer dans la salle des serveurs", dest = "serveurs" },
            { label = "Retourner au sas", dest = "start" }
        }
    },
    
    ["serveurs"] = {
        text = "Vous y etes. L'ordinateur central ronronne. C'est ici que l'anomalie a commence. Que voulez-vous faire ?",
        choices = {
            { label = "Lancer la sequence de purge", dest = "victoire" },
            { label = "Se reposer un instant", dest = "serveurs", on_choose = function() 
                state.hp = math.min(state.max_hp, state.hp + 5)
                last_event_msg = "REPOS: +5 INT" 
            end }
        }
    },
    
    ["victoire"] = {
        text = "Les ecrans virent au vert. La station est sauvee. FIN DE LA DEMONSTRATION.",
        choices = {
            { label = "Retourner au menu principal", dest = "menu_principal", on_choose = function() is_playing = false end }
        }
    },
    
    ["gameover"] = {
        text = "Vos blessures sont trop graves. Votre vision s'obscurcit. FIN DE TRANSMISSION.",
        choices = {
            { label = "Retourner au menu principal", dest = "menu_principal", on_choose = function() is_playing = false end }
        }
    }
}

-- =====================================================================
-- MOTEUR D'AFFICHAGE ET UTILITAIRES
-- =====================================================================
local function word_wrap(text, max_len)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        local current = ""
        for word in line:gmatch("%S+") do
            if #current + #word + 1 > max_len then
                table.insert(lines, current)
                current = word
            else
                if current == "" then current = word
                else current = current .. " " .. word end
            end
        end
        table.insert(lines, current)
    end
    return lines
end

local function draw_hud()
    io.write("\x1b[1;1H\x1b[7m 3615 ANOMALIE \x1b[0m")
    local status = string.format("  INTEGRITE : %03d/%03d  |  CREDITS : %04d  ", state.hp, state.max_hp, state.credits)
    local pad = 80 - 15 - #status
    io.write(string.rep(" ", pad) .. "\x1b[7m" .. status .. "\x1b[0m\r\n")
    io.write("\x1b[2;1H================================================================================\r\n")
end

local function draw_menu()
    io.write("\x1b[2J\x1b[H")
    io.flush()
    minitel.sleep(0.08)

    io.write("\x1b[5;24H\x1b[1m+--------------------------------+\x1b[0m\r\n")
    io.write("\x1b[6;24H\x1b[1m|                                |\x1b[0m\r\n")
    io.write("\x1b[7;24H\x1b[1m|        3 6 1 5   A N O M       |\x1b[0m\r\n")
    io.write("\x1b[8;24H\x1b[1m|                                |\x1b[0m\r\n")
    io.write("\x1b[9;24H\x1b[1m+--------------------------------+\x1b[0m\r\n")
    
    io.write("\x1b[14;29H\x1b[7m [1] \x1b[0m NOUVELLE PARTIE\r\n")
    
    local f = io.open(save_file, "r")
    if f then
        io.write("\x1b[16;29H\x1b[7m [2] \x1b[0m CHARGER LA PARTIE\r\n")
        f:close()
    else
        io.write("\x1b[16;29H\x1b[2m [2] CHARGER LA PARTIE (VIDE) \x1b[0m\r\n")
    end
    
    io.write("\x1b[18;29H\x1b[7m [3] \x1b[0m QUITTER VERS TELEMATIQUE\r\n")
    
    io.write("\x1b[23;19H CHOISISSEZ UNE OPTION AVEC LES TOUCHES 1, 2 OU 3 ")
    io.flush()
end

local function get_valid_choices(node_data)
    local valid = {}
    if not node_data.choices then return valid end
    
    for _, choice in ipairs(node_data.choices) do
        local is_valid = true
        if choice.req_item and not state.inventory[choice.req_item] then is_valid = false end
        if choice.req_not_item and state.inventory[choice.req_not_item] then is_valid = false end
        
        if choice.req_hp then
            if choice.req_hp > 0 and state.hp <= 0 then is_valid = false end
            if choice.req_hp < 0 and state.hp > 0 then is_valid = false end
        end
        
        if is_valid then table.insert(valid, choice) end
    end
    return valid
end

local function draw_node()
    io.write("\x1b[2J\x1b[H")
    draw_hud()
    
    local node = STORY[state.node]
    
    -- Affichage de l'evenement special s'il y en a un (ex: objet recu)
    if last_event_msg ~= "" then
        io.write("\x1b[4;3H\x1b[1m> " .. last_event_msg .. "\x1b[0m\r\n\r\n")
        last_event_msg = ""
    else
        io.write("\x1b[4;1H\r\n")
    end
    
    -- Affichage du texte descriptif
    local lines = word_wrap(node.text, 74)
    for _, l in ipairs(lines) do
        io.write("   " .. l .. "\r\n")
    end
    
    -- Affichage des choix possibles
    local valid_choices = get_valid_choices(node)
    
    io.write("\x1b[16;1H--------------------------------------------------------------------------------\r\n")
    for i, choice in ipairs(valid_choices) do
        io.write(string.format("\x1b[%d;3H\x1b[7m [%d] \x1b[0m %s\r\n", 16 + i, i, choice.label))
    end
    
    io.write("\x1b[24;1H\x1b[7m  CLAVIER NUMERIQUE : CHOISIR   |   [S] SAUVEGARDER   |   [Q] MENU PRINCIPAL  \x1b[0m")
    io.flush()
    return valid_choices
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    draw_menu()
    
    local in_menu = true
    while in_menu do
        local k = minitel.get_key()
        if k == "1" then
            state = { node = "start", hp = 100, max_hp = 100, credits = 0, inventory = {} }
            is_playing = true
            in_menu = false
        elseif k == "2" then
            if load_game() then
                is_playing = true
                in_menu = false
                last_event_msg = "PARTIE CHARGEE AVEC SUCCES."
            end
        elseif k == "3" or k == "Q" or k == "q" or k == "ESC" or k == "RETOUR" then
            io.write("\x1b[r\x1b[2J\x1b[H")
            io.flush()
            minitel.cleanup()
            os.exit()
        end
        minitel.sleep(0.05)
    end
    
    -- Moteur de jeu
    while is_playing do
        if STORY[state.node].on_enter then
            STORY[state.node].on_enter()
            STORY[state.node].on_enter = nil -- Evite de redonner les bonus en boucle
        end
        
        local current_choices = draw_node()
        local waiting_input = true
        
        while waiting_input and is_playing do
            local k = minitel.get_key()
            
            if k == "S" or k == "s" then
                if save_game() then
                    last_event_msg = "SAUVEGARDE EFFECTUEE SUR LE TERMINAL LOCAL."
                    waiting_input = false
                end
            elseif k == "Q" or k == "q" then
                is_playing = false
                waiting_input = false
            else
                local num = tonumber(k)
                if num and num >= 1 and num <= #current_choices then
                    local choice = current_choices[num]
                    if choice.on_choose then choice.on_choose() end
                    state.node = choice.dest
                    waiting_input = false
                end
            end
            minitel.sleep(0.05)
        end
    end
end