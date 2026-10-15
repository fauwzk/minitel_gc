-- @GENRE: SIMULATION / TELECOM 90S
-- @DESC: An 1994 : supervisez le commutateur Alcatel E10, le PABX Matracom RNIS, les baies V.23 Teletel et le reseau X.25 Transpac !

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local trunks = {
    { name = "1. AUTOCOM ALCATEL E10B (MIC E1 2MB)", load = 35, status = "NOMINAL", calls = 24 },
    { name = "2. PABX MATRACOM 6500 (NUMERIS T2)",   load = 40, status = "NOMINAL", calls = 18 },
    { name = "3. FRONTAL VIDEOTEX V.23 (3615 VAP)",  load = 25, status = "NOMINAL", calls = 48 },
    { name = "4. NOEUD X.25 TRANSPAC (CIRCUITS CV)", load = 30, status = "NOMINAL", calls = 32 }
}

local INCIDENTS_90S = {
    { target = 1, code = "PERTE SYNC MIC", msg = "Alarme PVT sur jonction MIC 2 Mbit/s Alcatel E10 ! Resynchronisez avec [P] !" },
    { target = 2, code = "DEFAUT RNIS T0", msg = "Perte du canal D semaphore sur le PABX Matracom 6500 ! Reinitialisez avec [P] !" },
    { target = 3, code = "PORTEUSE 1200B", msg = "Modem V.23 bloque en porteuse continue sur le frontal 3615 ! Purgez avec [P] !" },
    { target = 4, code = "COLLISION X.25", msg = "Saturation des Circuits Virtuels (CV) sur le PAD Transpac ! Relancez avec [P] !" }
}

local TRAFFIC_SPIKES_90S = {
    { target = 3, msg = "POINTE SOIR 20H30 : Afflux massif de connexions Minitel sur 3615 JEUX et 3614 ANNUAIRE !" },
    { target = 1, msg = "ORAGE HERTZIEN : Basculement du trafic interurbain sur le commutateur Alcatel E10B !" },
    { target = 2, msg = "HEURE DE POINTE BUREAUX : Saturation des lignes Numeris et postes Bi-Bop sur le Matracom !" },
    { target = 4, msg = "TRANSFERT BANCAIRE CB : Pic de paquets X.25 des terminaux de paiement Carte Bleue !" }
}

local cursor = 1
local qos_health = 100
local taxed_units = 0
local shift_timer = 90
local backup_cd = 0
local last_log = "CENTRE FRANCE TELECOM (1994) EN LIGNE. TOUTES LES JONCTIONS MIC SONT SYNCHRONISEES."

-- =====================================================================
-- AFFICHAGE DELTA-DRAWING ULTRA-COURT (SANS RE-ENVOYER LES BARRES DE 70 COL)
-- =====================================================================
local function update_trunk_row(idx)
    local t = trunks[idx]
    local y = 5 + (idx - 1) * 2
    local sel = (idx == cursor) and "\x1b[7m>" or " "
    local sel_end = (idx == cursor) and "<\x1b[0m" or " "

    local st_badge = " [NOMINAL]    "
    if t.status ~= "NOMINAL" then
        st_badge = "\x1b[7m [" .. minitel.pad(t.status, 10) .. "] \x1b[0m"
    elseif t.load >= 85 then
        st_badge = "\x1b[7m [SURCHARGE!] \x1b[0m"
    end

    io.write(string.format("\x1b[%d;4H%s %-36s%s | CHARGE: %3d%% | VOIES:%03d |%s",
        y, sel, minitel.pad(t.name, 36), sel_end, t.load, t.calls, st_badge))
end

local function update_header_and_logs()
    local francs = math.floor(taxed_units * 0.73)
    local top = string.format("3615 CENTRAL FT 1994 | QOS: %3d%% | RECETTE: %05d F | GARDE: %02ds",
        qos_health, francs, shift_timer)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

    local bkp_str = (backup_cd == 0) and "\x1b[7m [B] HERTZIEN SECOURS PRET \x1b[0m" or string.format("[SECOURS RECHARGE: %02ds]   ", backup_cd)
    io.write("\x1b[18;4H> " .. minitel.pad(last_log, 72))
    io.write("\x1b[20;4HACTIONS : [D] BRASSER TRAFIC | [P] REARMER CARTE | " .. minitel.pad(bkp_str, 26))
    io.flush()
end

local function draw_static_switchboard()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    minitel.draw_window(2, 3, 78, 13, "BAIES DE COMMUTATION FRANCE TELECOM (E10B / MATRACOM / TRANSPAC)")
    minitel.draw_window(2, 17, 78, 5, "PUPITRE DE SUPERVISION & TELEIMPRIMEUR D'ALARMES")
    io.write("\x1b[24;1H\x1b[7m [Z/S] CHOISIR BAIE | [D] DELESTER JONCTION | [P] REARMER ALARME | [B] SECOURS  \x1b[0m")

    for i = 1, 4 do update_trunk_row(i) end
    update_header_and_logs()
end

local function run_shift()
    qos_health = 100
    taxed_units = 0
    shift_timer = 90
    backup_cd = 0
    for _, t in ipairs(trunks) do
        t.load = math.random(25, 45)
        t.status = "NOMINAL"
        t.calls = math.random(15, 40)
    end

    draw_static_switchboard()
    local last_tick_sec = os.time()

    while shift_timer > 0 and qos_health > 0 do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif k == "UP" or k == "Z" or k == "z" then
                local old = cursor
                cursor = (cursor > 1) and (cursor - 1) or 4
                update_trunk_row(old)
                update_trunk_row(cursor)
                io.flush()
            elseif k == "DOWN" or k == "S" or k == "s" then
                local old = cursor
                cursor = (cursor < 4) and (cursor + 1) or 1
                update_trunk_row(old)
                update_trunk_row(cursor)
                io.flush()
            elseif k == "D" or k == "d" or k == "ENVOI" or k == " " then
                local min_idx = 1
                for i = 2, 4 do
                    if i ~= cursor and trunks[i].load < trunks[min_idx].load then min_idx = i end
                end
                if min_idx == cursor then min_idx = (cursor % 4) + 1 end

                local transfer = math.min(28, math.max(0, trunks[cursor].load - 15))
                trunks[cursor].load = trunks[cursor].load - transfer
                trunks[min_idx].load = math.min(100, trunks[min_idx].load + math.floor(transfer * 0.75))
                minitel.play_sound("hit")
                last_log = string.format("Brassage effectue : -%d%% de la Baie %d reroute vers la Baie %d.", transfer, cursor, min_idx)
                update_trunk_row(cursor)
                update_trunk_row(min_idx)
                update_header_and_logs()

            elseif k == "P" or k == "p" then
                local t = trunks[cursor]
                if t.status ~= "NOMINAL" then
                    local old_err = t.status
                    t.status = "NOMINAL"
                    t.load = math.max(25, t.load - 25)
                    minitel.play_sound("pickup")
                    last_log = "Carte reinitialisee sur Baie " .. cursor .. " (Defaut '" .. old_err .. "' acquitte) !"
                    update_trunk_row(cursor)
                    update_header_and_logs()
                else
                    last_log = "Aucun defaut materiel sur la Baie " .. cursor .. " (Voyants verts)."
                    update_header_and_logs()
                end

            elseif (k == "B" or k == "b") and backup_cd == 0 then
                backup_cd = 20
                minitel.play_sound("win")
                for i = 1, 4 do
                    trunks[i].load = math.max(15, trunks[i].load - 30)
                    trunks[i].status = "NOMINAL"
                    update_trunk_row(i)
                end
                last_log = "FAISCEAU HERTZIEN DE SECOURS ACTIVE ! Delestage national effectue."
                update_header_and_logs()
            end
        end

        -- Tick reseau toutes les 2 secondes pour garder une fluidite parfaite du clavier !
        local now = os.time()
        if now - last_tick_sec >= 2 then
            last_tick_sec = now
            shift_timer = math.max(0, shift_timer - 2)
            if backup_cd > 0 then backup_cd = math.max(0, backup_cd - 2) end

            local ev_roll = math.random(1, 100)
            if ev_roll <= 25 then
                local sp = TRAFFIC_SPIKES_90S[math.random(1, #TRAFFIC_SPIKES_90S)]
                trunks[sp.target].load = math.min(100, trunks[sp.target].load + math.random(18, 28))
                last_log = sp.msg
                minitel.play_sound("hit")
            elseif ev_roll <= 38 then
                local inc = INCIDENTS_90S[math.random(1, #INCIDENTS_90S)]
                trunks[inc.target].status = inc.code
                last_log = inc.msg
                minitel.play_sound("lose")
            end

            for i = 1, 4 do
                local t = trunks[i]
                local delta = math.random(-2, 6)
                if t.status ~= "NOMINAL" then delta = delta + 8 end
                t.load = math.max(10, math.min(100, t.load + delta))
                t.calls = math.floor(t.load * 1.2)
                taxed_units = taxed_units + math.floor(t.calls / 3)

                if t.load >= 92 then
                    qos_health = math.max(0, qos_health - 6)
                    last_log = "TONALITE D'OCCUPATION SUR BAIE " .. i .. " ! Appels rejetes (-6% QoS) !"
                    minitel.play_sound("lose")
                end
                update_trunk_row(i)
            end
            update_header_and_logs()
        end

        minitel.sleep(0.02)
    end

    local total_f = math.floor(taxed_units * 0.73)
    if qos_health > 0 then
        minitel.msg_box(
            "FIN DE QUART FRANCE TELECOM",
            string.format("Service irreprochable ! Recette telephonique : %d Francs (QoS : %d%%).", total_f, qos_health),
            "win"
        )
    else
        minitel.msg_box(
            "DISJONCTION DU REPARTITEUR...",
            "Le central Alcatel E10B s'est mis en securite ! Tout le departement est prive de tonalite.",
            "lose"
        )
    end
end

-- =====================================================================
-- ECRAN TITRE (DESSINE UNE SEULE FOIS HORS BOUCLE !)
-- =====================================================================
local function draw_title_screen()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 CENTRAL PTT (1994) - SUPERVISION E10B & TRANSPAC  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(12, 5, 58, 14, "MANUEL DE L'INGENIEUR FRANCE TELECOM (1994)")
    io.write("\x1b[7;15HVous supervisez le centre de commutation departemental :")
    io.write("\x1b[8;15HAlcatel E10B, PABX Matracom RNIS, Frontal 3615 & Transpac.")
    io.write("\x1b[10;15H- Au-dela de \x1b[7m 92% \x1b[0m de charge, les abonnes ont la tonalite")
    io.write("\x1b[11;15H  d'occupation et la Qualite de Service (QoS) chute !")
    io.write("\x1b[12;15H- Touche \x1b[1m[D]\x1b[0m : Brasser le trafic vers une baie disponible.")
    io.write("\x1b[13;15H- Touche \x1b[1m[P]\x1b[0m : Rearmer une carte en alarme (MIC, V.23, X25).")
    io.write("\x1b[14;15H- Touche \x1b[1m[B]\x1b[0m : Activer le Faisceau Hertzien de secours.")
    io.write("\x1b[16;22H\x1b[7m [ENVOI] PRENDRE SON QUART DE NUIT (90S) \x1b[0m")

    io.write("\x1b[24;1H\x1b[7m  [ENVOI] PRENDRE LE SERVICE   |   [RETOUR] QUITTER VERS LE PORTAIL MAGIS       \x1b[0m")
    io.flush()
end

draw_title_screen()

while true do
    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "ENVOI" or k == " " then
        run_shift()
        draw_title_screen()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()