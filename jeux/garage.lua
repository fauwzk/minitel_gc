-- @GENRE: SIMULATION / AUTO & ECU
-- @DESC: Atelier de diagnostic mecanique (Valise OBD, DTC, Mesures Live) et reprogrammation ECU sur banc de puissance.

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local cash = 1500
local rep  = 100

-- =====================================================================
-- 1. BASE DE DONNEES DES DOSSIERS D'ATELIER (DIAGNOSTIC REEL)
-- =====================================================================
local CASES = {
    {
        car = "CROSSOVER 1.6 HDI 110 (DV6TED4 - EDC16C34)",
        symptom = "Mode degrade a 3000 tr/min en pleine charge en cote. Voyant moteur allume.",
        dtc = "P0234 : Pression de suralimentation mesurée superieure a la consigne (+350 mbar).",
        live = {
            "Consigne Turbo : 2150 mbar  | Mesure MAP : 2540 mbar (OVERBOOST !)",
            "RCO Electrovanne Turbo : 85% | Depression capsule : 0.0 bar (Nulle)",
            "Correction debits injecteurs : Cyl1:-0.2 | Cyl2:+0.1 | Cyl3:+0.1 | Cyl4:0.0"
        },
        test_hint = "Test circuit de vide : Durite de depression fendue sur le raccord de l'electrovanne de turbo !",
        parts = {
            "1. Remplacer le turbocompresseur complet (850 F)",
            "2. Remplacer durite de vide & electrovanne N75 (95 F)",
            "3. Remplacer les 4 injecteurs piezo (900 F)",
            "4. Nettoyer le capteur MAP d'admission (40 F)"
        },
        correct = 2,
        reward = 350,
        explanation = "Bravo ! Une fuite ou electrovanne bloquee empechait la regulation de la geometrie variable, causant l'overboost P0234."
    },
    {
        car = "BERLINE COMPACTE 1.6 16V (K4M - SAGEM S3000)",
        symptom = "Ralenti instable qui oscille entre 1500 et 2200 tr/min apres nettoyage moteur.",
        dtc = "P0507 : Regime de ralenti superieur a la valeur attendue (Aucun court-circuit).",
        live = {
            "Regime moteur : 1850 tr/min | Temp. Eau : 89 C (Moteur chaud)",
            "Angle papillon motorise : 14.5% au repos (Butée non apprise)",
            "Pression collecteur (MAP) : 480 mbar | Bobines crayons : OK"
        },
        test_hint = "Test actionneur : Le boitier papillon motorise a perdu ses butees mini/maxi en memoire EEPROM.",
        parts = {
            "1. Remplacer les 4 bobines d'allumage crayons (280 F)",
            "2. Remplacer le capteur PMH sur cloche de boite (110 F)",
            "3. Effectuer un reapprentissage des butees papillon a la valise (80 F)",
            "4. Remplacer la sonde Lambda amont (190 F)"
        },
        correct = 3,
        reward = 280,
        explanation = "Exact ! Sur le K4M, apres debranchement ou nettoyage du boitier papillon, l'apprentissage des butees est indispensable."
    },
    {
        car = "CITADINE 900CC MONOPOINT (ECU SPEEDUINO)",
        symptom = "Moteur qui ratatouille a chaud, fumee noire a l'echappement et forte odeur d'essence.",
        dtc = "ERR_CLT : Signal capteur temperature liquide de refroidissement hors plage (-40 C).",
        live = {
            "Regime : 950 tr/min | Temp. reelle radiateur : 88 C | Lecture ECU CLT : -39 C",
            "Enrichissement demarrage a froid (Warmup Enrichment) : 145% ACTIF !",
            "AFR Large Bande : 10.2:1 (Beaucoup trop riche !) | Avance : 12 deg"
        },
        test_hint = "Controle multimetre : Fil coupe sur le connecteur de la sonde CTN 2 broches (Resistance infinie).",
        parts = {
            "1. Remplacer la pompe a essence immergee (220 F)",
            "2. Remplacer la bobine jumostatique (160 F)",
            "3. Reparer le faisceau et remplacer la sonde de temperature d'eau CTN (75 F)",
            "4. Remplacer l'injecteur monopoint (310 F)"
        },
        correct = 3,
        reward = 300,
        explanation = "Parfait ! Une sonde CTN debranchee indique -40 C au calculateur, qui maintient l'enrichissement de depart a froid en permanence."
    },
    {
        car = "COMPACTE SWAP 2.2 16V (EW12J4 - EMU BLACK)",
        symptom = "Coupure franche a 4500 tr/min et perte du compte-tours par intermittence a chaud.",
        dtc = "SYNC_LOSS : Perte de synchronisation dent manquante cible 60-2 vilebrequin.",
        live = {
            "Compteur Trigger Error : 42 erreurs | Signal Camshaft (AAC) : OK",
            "Ecartement capteur PMH : 1.8 mm (Trop eloigne) | Resistance : 1200 Ohms a chaud",
            "Pression rampe injection : 3.5 bars constants"
        },
        test_hint = "Oscilloscope : Le signal sinusoïdal du capteur PMH inductif s'effondre passe 4500 tr/min a chaud.",
        parts = {
            "1. Remplacer le capteur PMH (Vilebrequin 60-2) et regler l'entrefer (120 F)",
            "2. Remplacer le dephaseur d'arbre a cames VVT (540 F)",
            "3. Remplacer le relais double d'alimentation (90 F)",
            "4. Monter des bougies froides Iridium (140 F)"
        },
        correct = 1,
        reward = 380,
        explanation = "Bien vu ! Un capteur PMH inductif vieillissant perd son signal a haut regime quand sa bobine interne chauffe."
    }
}

-- =====================================================================
-- 2. MODULE 1 : ATELIER DE DIAGNOSTIC MECANIQUE
-- =====================================================================
local function run_diagnostic_workshop()
    local case = CASES[math.random(1, #CASES)]
    local dtc_read  = false
    local live_read = false
    local test_done = false

    local function draw_diag_screen()
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)

        local top = string.format("3615 GARAGE - ATELIER DIAGNOSTIC | TRESORERIE: %d F | REPUTATION: %d%%", cash, rep)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

        minitel.draw_window(2, 3, 78, 5, "ORDRE DE REPARATION : " .. case.car)
        io.write("\x1b[5;4H\x1b[1mSYMPTOME CLIENT :\x1b[0m " .. string.sub(case.symptom, 1, 56))
        io.write("\x1b[6;4H\x1b[1mPRIME REPARATION:\x1b[0m +" .. case.reward .. " F (Penalite erreur de diagnostic : -200 F)")

        minitel.draw_window(2, 9, 78, 9, "CONSOLE DE DIAGNOSTIC (LEXIA / CLIP / STANDALONE)")
        if not dtc_read and not live_read and not test_done then
            io.write("\x1b[12;4H" .. minitel.center("BRANCHEZ LA VALISE SUR LA PRISE OBD2 POUR INTERROGER L'ECU.", 72))
            io.write("\x1b[14;4H" .. minitel.center("Utilisez les touches [A], [B] et [C] avant de commander une piece.", 72))
        else
            if dtc_read then
                io.write("\x1b[11;4H\x1b[7m[DTC]\x1b[0m " .. string.sub(case.dtc, 1, 67))
            else
                io.write("\x1b[11;4H[DTC] Non lu (Appuyez sur [A])")
            end

            if live_read then
                io.write("\x1b[13;4H\x1b[7m[MES]\x1b[0m " .. string.sub(case.live[1], 1, 67))
                io.write("\x1b[14;4H      " .. string.sub(case.live[2], 1, 67))
            else
                io.write("\x1b[13;4H[MES] Mesures parametres non lues (Appuyez sur [B])")
            end

            if test_done then
                io.write("\x1b[16;4H\x1b[7m[TST]\x1b[0m " .. string.sub(case.test_hint, 1, 67))
            else
                io.write("\x1b[16;4H[TST] Controle physique non effectue (Appuyez sur [C])")
            end
        end

        minitel.draw_window(2, 19, 78, 5, "INTERVENTION & REMPLACEMENT DE PIECE (TOUCHES 1 A 4)")
        io.write("\x1b[20;4H" .. minitel.pad(case.parts[1], 36) .. " | " .. minitel.pad(case.parts[2], 35))
        io.write("\x1b[21;4H" .. minitel.pad(case.parts[3], 36) .. " | " .. minitel.pad(case.parts[4], 35))

        io.write("\x1b[24;1H\x1b[7m [A] LIRE DTC | [B] MESURES LIVE | [C] TEST ATELIER | [1-4] REPARER | [RETOUR] \x1b[0m")
        io.flush()
    end

    draw_diag_screen()

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif k == "A" or k == "a" then
                dtc_read = true
                minitel.play_sound("hit")
                draw_diag_screen()
            elseif k == "B" or k == "b" then
                live_read = true
                minitel.play_sound("hit")
                draw_diag_screen()
            elseif k == "C" or k == "c" then
                test_done = true
                minitel.play_sound("pickup")
                draw_diag_screen()
            elseif k == "1" or k == "2" or k == "3" or k == "4" then
                local choice = tonumber(k)
                if choice == case.correct then
                    cash = cash + case.reward
                    rep  = math.min(100, rep + 5)
                    minitel.msg_box("REPARATION REUSSIE (+" .. case.reward .. " F)", case.explanation, "win")
                else
                    cash = cash - 200
                    rep  = math.max(0, rep - 15)
                    minitel.msg_box("ERREUR DE DIAGNOSTIC (-200 F)", "Vous avez remplace la mauvaise piece ! Le defaut client est toujours present.", "lose")
                end
                return
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- 3. MODULE 2 : REPROGRAMMATION ECU & BANC DE PUISSANCE (MAP-TUNER)
-- =====================================================================
local boost_psi = 1.15 -- Pression turbo en Bar (Origine : 1.15 bar)
local fuel_pct  = 100  -- Temps d'injection en % (Origine : 100%)
local ign_adv   = 18   -- Avance a l'allumage en degres (Origine : 18 deg)

local function run_dyno_tuner()
    local cur_param = 1
    local last_hp   = 110
    local last_nm   = 240
    local last_egt  = 680
    local last_afr  = 14.5
    local status_str = "CARTOGRAPHIE D'ORIGINE (STAGE 0). PRET POUR TIR AU BANC."

    local function draw_dyno_ui(curve_points)
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)

        local top = string.format("3615 MAP-TUNER - BANC DE PUISSANCE & ECU | RECORD: %d CH / %d NM", last_hp, last_nm)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

        -- Panneau Gauche : Parametres Cartographie
        minitel.draw_window(2, 3, 38, 14, "TABLES ECU (STAGE 1 / 2)")

        local p1_sel = (cur_param == 1) and "\x1b[7m> 1. CONSIGNE TURBO  <\x1b[0m" or "  1. CONSIGNE TURBO   "
        io.write(string.format("\x1b[5;4H%s : %4.2f BAR", p1_sel, boost_psi))
        minitel.progress_bar(4, 6, 34, math.floor((boost_psi - 0.8) * 100), 120, false)

        local p2_sel = (cur_param == 2) and "\x1b[7m> 2. DEBIT INJECTION <\x1b[0m" or "  2. DEBIT INJECTION  "
        io.write(string.format("\x1b[8;4H%s : %3d %%", p2_sel, fuel_pct))
        minitel.progress_bar(4, 9, 34, fuel_pct - 70, 70, false)

        local p3_sel = (cur_param == 3) and "\x1b[7m> 3. AVANCE ALLUMAGE <\x1b[0m" or "  3. AVANCE ALLUMAGE  "
        io.write(string.format("\x1b[11;4H%s : %3d DEG", p3_sel, ign_adv))
        minitel.progress_bar(4, 12, 34, ign_adv - 8, 24, false)

        io.write(string.format("\x1b[14;4HAFR : %4.1f:1 | EGT : %d C", last_afr, last_egt))
        io.write(string.format("\x1b[15;4HBILAN : \x1b[1m%d CH / %d NM\x1b[0m", last_hp, last_nm))

        -- Panneau Droit : Courbe du Banc d'Essai
        minitel.draw_window(41, 3, 39, 14, "COURBE PUISSANCE (1500-6000 TR)")
        for r = 1, 10 do
            local hp_scale = 220 - (r - 1) * 20
            io.write(string.format("\x1b[%d;42H%3d|                                 ", 4 + r, hp_scale))
        end
        io.write("\x1b[15;42H   +---------------------------------")
        io.write("\x1b[16;42H    1.5k   2.5k   3.5k   4.5k   6.0k ")

        if curve_points then
            for idx, hp_val in ipairs(curve_points) do
                local col = 46 + (idx - 1) * 3
                local row = 14 - math.max(0, math.min(9, math.floor((hp_val - 40) / 20)))
                io.write(string.format("\x1b[%d;%dH\x1b[7m*\x1b[0m", row, col))
            end
        end

        minitel.draw_window(2, 18, 78, 5, "TELEMETRIE BANC A ROULEAUX & SONDE CLIQUETIS (KNOCK)")
        io.write("\x1b[20;4H> " .. minitel.pad(status_str, 72))

        io.write("\x1b[24;1H\x1b[7m [Z/S] PARAMETRE | [Q/D] REGLER -/+ | [ENVOI] LANCER TIR AU BANC | [RETOUR]    \x1b[0m")
        io.flush()
    end

    draw_dyno_ui(nil)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif k == "UP" or k == "Z" or k == "z" then
                cur_param = (cur_param > 1) and (cur_param - 1) or 3
                draw_dyno_ui(nil)
            elseif k == "DOWN" or k == "S" or k == "s" then
                cur_param = (cur_param < 3) and (cur_param + 1) or 1
                draw_dyno_ui(nil)
            elseif k == "LEFT" or k == "Q" or k == "q" or k == "RIGHT" or k == "D" or k == "d" then
                local dir = (k == "RIGHT" or k == "D" or k == "d") and 1 or -1
                if cur_param == 1 then
                    boost_psi = math.max(0.80, math.min(2.00, boost_psi + (dir * 0.05)))
                elseif cur_param == 2 then
                    fuel_pct = math.max(75, math.min(140, fuel_pct + (dir * 5)))
                elseif cur_param == 3 then
                    ign_adv = math.max(10, math.min(32, ign_adv + (dir * 1)))
                end
                minitel.play_sound("hit")
                draw_dyno_ui(nil)

            elseif k == "ENVOI" or k == " " then
                -- Calcul physique de la cartographie
                local air_mass = boost_psi / 1.15
                last_afr = (14.5 * air_mass) / (fuel_pct / 100.0)
                last_egt = math.floor(650 + (boost_psi - 1.0) * 220 + (last_afr - 12.5) * 45 - (ign_adv - 18) * 6)

                local knock_risk = (ign_adv > 24 and boost_psi > 1.45) or (last_afr > 13.8 and boost_psi > 1.35)
                local egt_danger = (last_egt > 930)
                local rich_bog   = (last_afr < 10.6)

                local peak_hp = math.floor(110 * (boost_psi / 1.15) * (fuel_pct / 100.0) * 0.92 + (ign_adv - 18) * 2.5)
                if rich_bog then peak_hp = peak_hp - 25 end
                if knock_risk or egt_danger then peak_hp = math.floor(peak_hp * 0.70) end

                last_hp = math.max(60, peak_hp)
                last_nm = math.floor(last_hp * 2.15)

                local pts = {}
                for step = 1, 10 do
                    local rpm_ratio = step / 10.0
                    local hp_at_rpm = math.floor(last_hp * math.sin(rpm_ratio * 1.45))
                    table.insert(pts, hp_at_rpm)
                end

                if knock_risk then
                    status_str = "ALERTE CLIQUETIS (KNOCK) ! Trop d'avance ou melange trop pauvre sous pression !"
                    minitel.play_sound("lose")
                elseif egt_danger then
                    status_str = "ALERTE EGT (" .. last_egt .. " C) ! Temperature echappement critique, enrichissez !"
                    minitel.play_sound("lose")
                elseif rich_bog then
                    status_str = "MELANGE TROP RICHE (AFR " .. string.format("%.1f", last_afr) .. ") ! Fumee noire, baissez l'injection ou montez le turbo."
                    minitel.play_sound("hit")
                else
                    status_str = string.format("TIR VALIDE : %d CH & %d NM ! Cartographie fiable (AFR %.1f / EGT %d C).", last_hp, last_nm, last_afr, last_egt)
                    minitel.play_sound("win")
                end

                draw_dyno_ui(pts)
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MENU PRINCIPAL DU GARAGE
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 GARAGE - DIAGNOSTIC MECANIQUE & REPROGRAMMATION ECU  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(16, 5, 50, 15, "ATELIER MECANIQUE MAGIS")
    io.write(string.format("\x1b[7;20H\x1b[1mTRESORERIE :\x1b[0m %d FRANCS", cash))
    io.write(string.format("\x1b[8;20H\x1b[1mREPUTATION :\x1b[0m %d %%", rep))

    io.write("\x1b[11;20H\x1b[7m [1] \x1b[0m RECEVOIR UN CLIENT (DIAGNOSTIC PANNE)")
    io.write("\x1b[13;20H\x1b[7m [2] \x1b[0m BANC DE PUISSANCE & CARTOGRAPHIE ECU")
    io.write("\x1b[16;20H\x1b[7m [RETOUR] \x1b[0m FERMER LE GARAGE")

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1] POUR L'ATELIER DIAGNOSTIC OU [2] POUR LE BANC D'ESSAI MAP-TUNER    \x1b[0m")
    io.flush()

    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then
        break
    elseif k == "1" then
        run_diagnostic_workshop()
    elseif k == "2" then
        run_dyno_tuner()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()