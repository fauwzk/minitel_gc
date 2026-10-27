-- @GENRE: FICTION INTERACTIVE
-- @DESC: Aventure textuelle avec inventaire et sauvegarde persistante. Explorez la station relais et survivez a l'anomalie.

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p jeux/saves_anomalie 2>/dev/null")

-- =====================================================================
-- VARIABLES D'ETAT ET SAUVEGARDE MULTI-FICHIERS
-- =====================================================================
local state = {
    player = "OPERATEUR",
    node = "start",
    hp = 100,
    max_hp = 100,
    credits = 0,
    inventory = {},
    visited = {}
}

local last_event_msg = ""
local is_playing = false
local is_modified = false

local function save_game(filepath)
    local f = io.open(filepath, "w")
    if not f then return false end
    f:write("return {\n")
    f:write(string.format("  player = %q, node = %q, hp = %d, max_hp = %d, credits = %d,\n",
        state.player, state.node, state.hp, state.max_hp, state.credits))
    f:write("  inventory = {")
    for k, v in pairs(state.inventory) do
        if v then f:write(string.format("[%q]=true,", k)) end
    end
    f:write("},\n  visited = {")
    for k, v in pairs(state.visited) do
        if v then f:write(string.format("[%q]=true,", k)) end
    end
    f:write("}\n}\n")
    f:close()
    return true
end

local function load_game(filepath)
    local f = loadfile(filepath)
    if f then
        local ok, data = pcall(f)
        if ok and type(data) == "table" and data.node then
            state = data
            state.inventory = state.inventory or {}
            state.visited = state.visited or {}
            is_modified = false
            return true
        end
    end
    return false
end

-- =====================================================================
-- LE MOTEUR D'HISTOIRE (LES NOEUDS)
-- =====================================================================
local STORY = {
    ["start"] = {
        title = "SAS PRINCIPAL - SECTEUR 4",
        text = "Vous vous reveillez dans l'obscurite. L'odeur d'ozone et de metal brule vous prend a la gorge. Les ecrans de controle autour de vous clignotent faiblement, affichant 'ERREUR SECTEUR 4'. Vous etes dans le sas principal de la station relais.",
        choices = {
            { label = "Examiner la porte blindee du sas", dest = "porte_sas" },
            { label = "Fouiller le casier metallique entrouvert", dest = "casier", req_not_item = "BADGE" },
            { label = "S'enfoncer dans le couloir de maintenance", dest = "couloir" }
        }
    },
    
    ["casier"] = {
        title = "CASIER D'URGENCE",
        text = "Le casier grince. A l'interieur, parmi des manuels techniques jaunis, vous trouvez un BADGE DE SECURITE magnetique ainsi qu'une trousse de premiers secours.",
        on_enter = function() 
            state.inventory["BADGE"] = true 
            state.hp = math.min(state.max_hp, state.hp + 15)
            last_event_msg = "OBTENTION : BADGE DE SECURITE | +15 INTEGRITE"
            minitel.play_sound("pickup")
        end,
        choices = {
            { label = "Refermer le casier et revenir au sas", dest = "start" }
        }
    },
    
    ["porte_sas"] = {
        title = "PORTE BLINDEE DU SAS",
        text = "La lourde porte mene vers l'antenne exterieure et le terminal de secours. Un lecteur de carte magnetique rougeoie sur le panneau lateral.",
        choices = {
            { label = "Passer le Badge de Securite dans le lecteur", dest = "passerelle", req_item = "BADGE" },
            { label = "Tenter de forcer le panneau (Risque d'choc)", dest = "porte_sas", on_choose = function()
                state.hp = state.hp - 10
                last_event_msg = "COURT-CIRCUIT ! VOUS PERDEZ 10 INT."
                minitel.play_sound("lose")
            end },
            { label = "Retourner au centre du sas", dest = "start" }
        }
    },

    ["passerelle"] = {
        title = "PASSERELLE D'OBSERVATION",
        text = "Le lecteur bippe au vert. Vous accedez a la passerelle vitree. Sur une console abandonnee, vous trouvez une CLEF CRYPTOGRAPHIQUE permettant de desactiver les drones de securite.",
        on_enter = function()
            state.inventory["CLEF_CRYPTO"] = true
            state.credits = state.credits + 100
            last_event_msg = "OBTENTION : CLEF CRYPTO | +100 CREDITS"
            minitel.play_sound("win")
        end,
        choices = {
            { label = "Revenir dans le sas principal", dest = "start" }
        }
    },
    
    ["couloir"] = {
        title = "COULOIR DE MAINTENANCE",
        text = "Le couloir est plonge dans le noir. Soudain, un DRONE DE SECURITE au comportement erratique bloque le passage. Ses pinces crepitent d'electricite !",
        choices = {
            { label = "Neutraliser le drone avec la Clef Crypto", dest = "couloir_safe", req_item = "CLEF_CRYPTO", on_choose = function()
                last_event_msg = "SIGNAL ENVOYE : LE DRONE S'ETEINT SANS COMBAT !"
                minitel.play_sound("win")
            end },
            { label = "Affronter le drone a mains nues", dest = "combat_drone" },
            { label = "Rebrousser chemin vers le sas", dest = "start" }
        }
    },
    
    ["combat_drone"] = {
        title = "AFFRONTEMENT MECANIQUE",
        text = "Vous vous jetez sur la machine pour arracher son cable d'alimentation. Les etincelles volent dans le couloir etroit...",
        always_trigger = true,
        on_enter = function()
            local dmg = math.random(20, 35)
            state.hp = state.hp - dmg
            state.credits = state.credits + 50
            if state.hp > 0 then
                last_event_msg = "DRONE DETRUIT ! -" .. dmg .. " INT | +50 CREDITS"
                minitel.play_sound("hit")
            else
                minitel.play_sound("lose")
            end
        end,
        choices = {
            { label = "Enjamber l'epave et avancer", dest = "couloir_safe", req_hp = 1 },
            { label = "Sombrer dans l'inconscience...", dest = "gameover", req_hp = -999 }
        }
    },
    
    ["couloir_safe"] = {
        title = "ACCES SALLE DES SERVEURS",
        text = "Le passage est libre. Au bout du couloir se dresse la porte menant au coeur informatique de la station relais.",
        choices = {
            { label = "Entrer dans la salle des serveurs", dest = "serveurs" },
            { label = "Retourner au sas principal", dest = "start" }
        }
    },
    
    ["serveurs"] = {
        title = "SALLE DU CALCULATEUR CENTRAL",
        text = "Les baies VAX et Teletel ronronnent. C'est ici que l'anomalie reseau a pris naissance. La console maitre attend une commande d'execution.",
        choices = {
            { label = "Executer la sequence de purge totale", dest = "victoire" },
            { label = "Consolider l'integrite sur le terminal (+10 INT)", dest = "serveurs", on_choose = function() 
                state.hp = math.min(state.max_hp, state.hp + 10)
                last_event_msg = "DIAGNOSTIC : +10 INTEGRITE RESTAUREE."
                minitel.play_sound("pickup")
            end }
        }
    },
    
    ["victoire"] = {
        title = "TRANSMISSION RETABLIE",
        text = "Les ecrans virent au vert. L'anomalie est purgee et le reseau 3615 Magis Club est de nouveau operationnel sur tout le territoire. Felicitations !",
        choices = {
            { label = "Terminer la mission (Menu Principal)", dest = "menu", on_choose = function() is_playing = false end }
        }
    },
    
    ["gameover"] = {
        title = "SIGNAL PERDU",
        text = "Vos blessures sont trop graves. Les lumieres du secteur s'eteignent une a une. Fin de transmission...",
        choices = {
            { label = "Retourner au menu principal", dest = "menu", on_choose = function() is_playing = false end }
        }
    }
}

-- =====================================================================
-- MOTEUR D'AFFICHAGE (FENETRES & JAUGES SDK)
-- =====================================================================
local function get_valid_choices(node_data)
    local valid = {}
    if not node_data.choices then return valid end
    for _, choice in ipairs(node_data.choices) do
        local ok = true
        if choice.req_item and not state.inventory[choice.req_item] then ok = false end
        if choice.req_not_item and state.inventory[choice.req_not_item] then ok = false end
        if choice.req_hp then
            if choice.req_hp > 0 and state.hp <= 0 then ok = false end
            if choice.req_hp < 0 and state.hp > 0 then ok = false end
        end
        if ok then table.insert(valid, choice) end
    end
    return valid
end

local function draw_node()
    local node = STORY[state.node]
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    -- Bandeau Superieur
    local header = string.format(" 3615 ANOMALIE | OP: %-14s | CREDITS: %04d ", state.player, state.credits)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.pad(header, 80) .. "\x1b[0m")

    -- Fenetre de Gauche : Recit (Col 2 a 55)
    minitel.draw_window(2, 3, 54, 12, node.title or "EXPLORATION")

    local lines = minitel.wrap(node.text, 50, 7)
    for i, l in ipairs(lines) do
        io.write(string.format("\x1b[%d;4H%s", 4 + i, l))
    end

    if last_event_msg ~= "" then
        io.write(string.format("\x1b[13;4H\x1b[7m %s \x1b[0m", minitel.pad(last_event_msg, 48)))
        last_event_msg = ""
    end

    -- Fenetre de Droite : Statut & Inventaire (Col 57 a 79)
    minitel.draw_window(57, 3, 23, 12, "ETAT & INVENTAIRE")
    io.write(string.format("\x1b[5;59HINT : %03d / %03d", math.max(0, state.hp), state.max_hp))
    minitel.progress_bar(59, 6, 19, math.max(0, state.hp), state.max_hp, false)

    io.write("\x1b[8;59H\x1b[1mOBJETS ACTIFS :\x1b[0m")
    local inv_y = 9
    local has_item = false
    for k, v in pairs(state.inventory) do
        if v and inv_y <= 13 then
            io.write(string.format("\x1b[%d;59H- %s", inv_y, string.sub(k, 1, 17)))
            inv_y = inv_y + 1
            has_item = true
        end
    end
    if not has_item then io.write("\x1b[9;59H(Aucun objet)") end

    -- Fenetre du Bas : Choix d'actions (Lignes 16 a 22)
    minitel.draw_window(2, 16, 78, 7, "ACTIONS DISPONIBLES")
    local valid_choices = get_valid_choices(node)
    for i, choice in ipairs(valid_choices) do
        if i <= 4 then
            io.write(string.format("\x1b[%d;4H\x1b[7m [%d] \x1b[0m %s", 17 + i, i, string.sub(choice.label, 1, 66)))
        end
    end

    io.write("\x1b[24;1H\x1b[7m  [1-4] CHOISIR  |  [S] SAUVEGARDER  |  [C] CHARGER  |  [RETOUR] QUITTER        \x1b[0m")
    io.flush()
    return valid_choices
end

local function draw_main_menu()
    io.write("\x1b[r\x1b[2J\x1b[H")
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 ANOMALIE - FICTION INTERACTIVE  * * *", 80) .. "\x1b[0m")
    
    minitel.draw_window(20, 5, 42, 14, "TERMINAL SECTEUR 4")
    io.write("\x1b[8;25H\x1b[7m [1] \x1b[0m NOUVELLE TRANSMISSION")
    io.write("\x1b[11;25H\x1b[7m [2] \x1b[0m CHARGER UNE SAUVEGARDE...")
    io.write("\x1b[15;25H\x1b[7m [3] \x1b[0m QUITTER VERS LE PORTAIL")
    
    io.write("\x1b[24;1H\x1b[7m" .. minitel.center("CHOISISSEZ UNE OPTION AVEC LES TOUCHES 1, 2 OU 3", 80) .. "\x1b[0m")
    io.flush()
end

-- =====================================================================
-- BOUCLE PRINCIPALE
-- =====================================================================
while true do
    draw_main_menu()
    
    local in_menu = true
    while in_menu do
        local k = minitel.get_key()
        if k == "1" then
            local p_name = minitel.input_box("IDENTIFICATION", "Entrez votre nom d'operateur :", "AGENT_01", 14)
            if p_name then
                if p_name == "" then p_name = "AGENT_01" end
                state = {
                    player = string.upper(p_name),
                    node = "start",
                    hp = 100, max_hp = 100, credits = 0,
                    inventory = {}, visited = {}
                }
                is_playing = true
                is_modified = true
                in_menu = false
            else
                draw_main_menu()
            end
        elseif k == "2" then
            local target = minitel.file_browser("OPEN", "jeux/saves_anomalie/")
            if target then
                if load_game(target) then
                    last_event_msg = "SAUVEGARDE RESTAUREE AVEC SUCCES."
                    is_playing = true
                    in_menu = false
                else
                    minitel.msg_box("ERREUR", "Ce fichier de sauvegarde est invalide.", "lose")
                    draw_main_menu()
                end
            else
                draw_main_menu()
            end
        elseif k == "3" or k == "Q" or k == "q" or k == "ESC" or k == "RETOUR" then
            minitel.cleanup()
            os.exit()
        end
        minitel.sleep(0.02)
    end
    
    -- Boucle d'exploration
    while is_playing do
        local cur_node = STORY[state.node]
        if cur_node.on_enter and (cur_node.always_trigger or not state.visited[state.node]) then
            state.visited[state.node] = true
            cur_node.on_enter()
        end
        if state.hp <= 0 and state.node ~= "gameover" then
            state.node = "gameover"
        end
        
        local current_choices = draw_node()
        local waiting_input = true
        
        while waiting_input and is_playing do
            local k = minitel.get_key()
            
            if k == "S" or k == "s" then
                local target = minitel.file_browser("SAVE", "jeux/saves_anomalie/")
                if target then
                    if save_game(target) then
                        is_modified = false
                        minitel.msg_box("SAUVEGARDE", "Progression enregistree sur le disque !", "win")
                    else
                        minitel.msg_box("ERREUR", "Impossible d'ecrire la sauvegarde.", "lose")
                    end
                end
                waiting_input = false

            elseif k == "C" or k == "c" then
                local target = minitel.file_browser("OPEN", "jeux/saves_anomalie/")
                if target and load_game(target) then
                    last_event_msg = "PARTIE CHARGEE."
                end
                waiting_input = false

            elseif k == "REPETITION" then
                waiting_input = false

            elseif k == "Q" or k == "q" or k == "RETOUR" or k == "ESC" then
                if not is_modified or minitel.confirm_box("QUITTER LA MISSION", "Revenir au menu principal sans sauvegarder ?") then
                    is_playing = false
                end
                waiting_input = false

            else
                local num = tonumber(k)
                if num and num >= 1 and num <= #current_choices then
                    local choice = current_choices[num]
                    if choice.on_choose then choice.on_choose() end
                    if is_playing then
                        state.node = choice.dest
                        is_modified = true
                    end
                    waiting_input = false
                end
            end
            minitel.sleep(0.02)
        end
    end
end