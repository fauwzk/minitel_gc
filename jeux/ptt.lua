-- @GENRE: SIMULATION / TELECOM & PABX
-- @DESC: Gerez l'autocommutateur central PTT (Trunks SIP, Passerelles FXO, Mitel A5000) et evitez la saturation du reseau !

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

-- =====================================================================
-- ETAT DU REPARTITEUR TELEPHONIQUE
-- =====================================================================
local trunks = {
    { name = "TRUNK 1 : PJSIP NATIONAL (PARIS)",   load = 35, status = "NOMINAL", calls = 42 },
    { name = "TRUNK 2 : INTERCO MITEL A5000 AXS",  load = 40, status = "NOMINAL", calls = 28 },
    { name = "TRUNK 3 : PASSERELLE CISCO FXO/RTC", load = 25, status = "NOMINAL", calls = 16 },
    { name = "TRUNK 4 : LIAISON X.25 TRANSPAC",    load = 30, status = "NOMINAL", calls = 34 }
}

local cursor = 1
local qos_health = 100
local routed_packets = 0
local shift_timer = 90 -- Tenir 90 cycles (1 garde complete)
local backup_cd = 0
local last_log = "CENTRE DE COMMUTATION OPERATIONNEL. SURVEILLEZ LA CHARGE DES TRUNKS."

-- =====================================================================
-- AFFICHAGE SQUELETTE STATIQUE + DELTA-DRAWING (9600 BAUDS)
-- =====================================================================
local function update_trunk_row(idx)
    local t = trunks[idx]
    local y = 4 + (idx - 1) * 3
    local sel = (idx == cursor) and "\x1b[7m>" or " "
    local sel_end = (idx == cursor) and "<\x1b[0m" or " "

    local st_badge = " [NOMINAL] "
    if t.status ~= "NOMINAL" then
        st_badge = "\x1b[7m [" .. t.status .. "] \x1b[0m"
    elseif t.load >= 85 then
        st_badge = "\x1b[7m [ALERTE!] \x1b[0m"
    end

    io.write(string.format("\x1b[%d;4H%s %-36s%s | CANAUX: %03d | %s",
        y, sel, minitel.pad(t.name, 36), sel_end, t.calls, st_badge))
    minitel.progress_bar(6, y + 1, 70, t.load, 100, true)
end

local function update_header_and_logs()
    local top = string.format("3615 CENTRAL PTT | QOS RESEAU: %3d%% | TRAMES: %04d | FIN DE GARDE: %02ds",
        qos_health, routed_packets, shift_timer)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

    local bkp_str = (backup_cd == 0) and "\x1b[7m [B] LIGNE SECOURS PRETE \x1b[0m" or string.format("[SECOURS RECHARGE: %02ds]", backup_cd)
    io.write("\x1b[18;4H> " .. minitel.pad(last_log, 72))
    io.write("\x1b[20;4HCOMMANDES : [D] DELESTER VERS VOISIN | [P] RESET SIP/FXO | " .. minitel.pad(bkp_str, 26))
    io.flush()
end

local function draw_static_switchboard()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    minitel.draw_window(2, 3, 78, 13, "SYNOPTIQUE DES FAISCEAUX TELEPHONIQUES (PABX / TRUNKS)")
    minitel.draw_window(2, 17, 78, 5, "JOURNAL D'INCIDENTS & CONSOLE D'EXPLOITATION")
    io.write("\x1b[24;1H\x1b[7m [Z/S] CHOISIR TRUNK | [D] DELESTER CHARGE | [P] PURGER PANNE | [B] SECOURS   \x1b[0m")

    for i = 1, 4 do update_trunk_row(i) end
    update_header_and_logs()
end

-- =====================================================================
-- SIMULATION TEMPS REEL DU TRAFIC TELEPHONIQUE
-- =====================================================================
local function run_shift()
    qos_health = 100
    routed_packets = 0
    shift_timer = 90
    backup_cd = 0
    for _, t in ipairs(trunks) do
        t.load = math.random(25, 45)
        t.status = "NOMINAL"
        t.calls = math.random(15, 40)
    end

    draw_static_switchboard()
    local tick_acc = 0

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
                -- Deleste 28% de charge du trunk selectionne vers le trunk le moins charge
                local min_idx = 1
                for i = 2, 4 do
                    if i ~= cursor and trunks[i].load < trunks[min_idx].load then min_idx = i end
                end
                if min_idx == cursor then min_idx = (cursor % 4) + 1 end

                local transfer = math.min(28, math.max(0, trunks[cursor].load - 15))
                trunks[cursor].load = trunks[cursor].load - transfer
                trunks[min_idx].load = math.min(100, trunks[min_idx].load + math.floor(transfer * 0.75))
                minitel.play_sound("hit")
                last_log = string.format("Routage dynamique : -%d%% sur Trunk %d bascule vers Trunk %d.", transfer, cursor, min_idx)
                update_trunk_row(cursor)
                update_trunk_row(min_idx)
                update_header_and_logs()

            elseif k == "P" or k == "p" then
                local t = trunks[cursor]
                if t.status ~= "NOMINAL" then
                    t.status = "NOMINAL"
                    t.load = math.max(25, t.load - 25)
                    minitel.play_sound("pickup")
                    last_log = "Trunk " .. cursor .. " reinitialise (SIP Reload / Reset FXO effectue) !"
                    update_trunk_row(cursor)
                    update_header_and_logs()
                else
                    last_log = "Le Trunk " .. cursor .. " ne presente pas d'anomalie protocolaire."
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
                last_log = "FAISCEAU DE DEBORDEMENT NATIONAL ACTIVE ! Tous les Trunks sont soulages."
                update_header_and_logs()
            end
        end

        minitel.sleep(0.05)
        tick_acc = tick_acc + 1

        -- Mise a jour du trafic toutes les secondes (20 cycles de 0.05s)
        if tick_acc >= 20 then
            tick_acc = 0
            shift_timer = shift_timer - 1
            if backup_cd > 0 then backup_cd = backup_cd - 1 end

            -- Evenement aleatoire de pointe ou panne SIP/FXO
            local ev_roll = math.random(1, 100)
            if ev_roll <= 22 then
                local target = math.random(1, 4)
                trunks[target].load = math.min(100, trunks[target].load + math.random(18, 28))
                last_log = "POINTE DE TRAFIC detectee sur " .. trunks[target].name .. " !"
                minitel.play_sound("hit")
            elseif ev_roll <= 34 then
                local target = math.random(1, 4)
                local errs = {"BOUCLE SIP", "ERR CODEC", "PORTEUSE HS"}
                trunks[target].status = errs[math.random(1, #errs)]
                last_log = "PANNE SIGNALISATION sur Trunk " .. target .. " ! Selectionnez-le et appuyez sur [P] !"
                minitel.play_sound("lose")
            end

            for i = 1, 4 do
                local t = trunks[i]
                local delta = math.random(-2, 6)
                if t.status ~= "NOMINAL" then delta = delta + 8 end
                t.load = math.max(10, math.min(100, t.load + delta))
                t.calls = math.floor(t.load * 1.2)
                routed_packets = routed_packets + math.floor(t.calls / 4)

                if t.load >= 92 then
                    qos_health = math.max(0, qos_health - 6)
                    last_log = "SATURATION CRITIQUE SUR TRUNK " .. i .. " ! Perte de paquets audio (-6% QoS) !"
                    minitel.play_sound("lose")
                end
                update_trunk_row(i)
            end
            update_header_and_logs()
        end
    end

    if qos_health > 0 then
        minitel.msg_box(
            "GARDE TERMINEE AVEC SUCCES !",
            string.format("Bravo Ingenieur ! Vous avez achemine %d trames avec une QoS finale de %d%%.", routed_packets, qos_health),
            "win"
        )
    else
        minitel.msg_box(
            "EFFONDREMENT DU RESEAU...",
            "La Qualite de Service est tombee a 0%. L'autocommutateur central a disjoncte !",
            "lose"
        )
    end
end

-- =====================================================================
-- ECRAN TITRE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 CENTRAL PTT - SUPERVISION AUTOCOMMUTATEUR & PABX  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(14, 5, 54, 14, "INSTRUCTIONS DE L'INGENIEUR DE GARDE")
    io.write("\x1b[7;17HVous supervisez 4 faisceaux Telecom (SIP, Mitel, FXO, X25).")
    io.write("\x1b[9;17H- Si un Trunk depasse \x1b[7m 92% \x1b[0m de charge, la QoS chute !")
    io.write("\x1b[10;17H- Appuyez sur \x1b[1m[D]\x1b[0m pour delester un Trunk vers un autre.")
    io.write("\x1b[11;17H- Si un Trunk affiche \x1b[7m[BOUCLE SIP]\x1b[0m, appuyez sur \x1b[1m[P]\x1b[0m.")
    io.write("\x1b[12;17H- En cas d'urgence globale, activez \x1b[1m[B]\x1b[0m (Ligne Secours).")
    io.write("\x1b[15;24H\x1b[7m [ENVOI] PRENDRE SON SERVICE (90 SECONDES) \x1b[0m")

    io.write("\x1b[24;1H\x1b[7m  [ENVOI] DEMARRER LA SUPERVISION   |   [RETOUR] QUITTER VERS LE PORTAIL        \x1b[0m")
    io.flush()

    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then break
    elseif k == "ENVOI" or k == " " then run_shift()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()