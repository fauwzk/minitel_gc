-- @GENRE: SIMULATION / GARAGE 90S
-- @DESC: Atelier mecanique annees 90 (Valise XR25, Station TEP 92, Banc Souriau) et preparation EPROM 27C256 sur banc a rouleaux !

local minitel = require("minitel")
minitel.init()

math.randomseed(os.time())

local cash = 2000
local rep  = 100

-- =====================================================================
-- 1. DOSSIERS D'ATELIER YOUNGTIMERS ANNÉES 1990
-- =====================================================================
local CASES = {
    {
        car = "PEUGEOT 205 GTI 1.9 130CH (XU9JA - BOSCH LE2-JETRONIC)",
        symptom = "Ralenti tres instable a chaud, trous a la reprise et bougies noires.",
        dtc = "STATION SOURIAU : Aucun calculateur a memoire (Injection analogique Bosch).",
        live = {
            "Analyseur 4 Gaz : CO = 5.8% (Norme < 3.5%) | Lambda : Trop riche",
            "Pression rampe essence : 2.5 bars (OK) | Contacteur papillon : Clic OK",
            "Tension piste debimetre a volet : Coupure franche a mi-ouverture !"
        },
        test_hint = "Ohmmètre sur debimetre Bosch : Piste graphite usee sur les premiers degres du volet-sonde.",
        parts = {
            "1. Remplacer la tete d'allumeur Ducellier et le doigt (180 F)",
            "2. Reconditionner le debimetre a volet-sonde + reglage CO (450 F)",
            "3. Remplacer le tiroir d'air additionnel (320 F)",
            "4. Remplacer le module d'allumage Bosch MTR02 (290 F)"
        },
        correct = 2,
        reward = 650,
        explanation = "Bien joue ! Sur le XU9JA L-Jetronic, la piste carbone du debimetre a volet s'use avec les vibrations et fausse toute la richesse."
    },
    {
        car = "RENAULT 25 V6 TURBO 205CH (Z7U - GESTION RENIX)",
        symptom = "Coupure violente d'injection en pleine charge en 3e a 4000 tr/min.",
        dtc = "VALISE RENAULT XR25 (Fiche #18) : Bargraphe Defaut Pression Suralimentation.",
        live = {
            "Manometre tableau de bord : L'aiguille tape en zone rouge (> 1.1 bar) !",
            "Coupure securite pressostat : DECLENCHEE | Cliquetis Renix : 0 deg",
            "Resistance capteur PMH cloche de boite : 220 Ohms (OK)"
        },
        test_hint = "Pompe a pression : La petite durite entre le collecteur et la capsule Wastegate du turbo Garrett T3 est fendue !",
        parts = {
            "1. Remplacer la durite silicone de Wastegate et tarer a 0.85 bar (120 F)",
            "2. Remplacer le calculateur Renix Bendix complet (2400 F)",
            "3. Remplacer les 6 injecteurs Bosch (1800 F)",
            "4. Remplacer la pompe a essence externe sous caisse (650 F)"
        },
        correct = 1,
        reward = 550,
        explanation = "Exact ! Quand la durite de la Wastegate est percee, le turbo charge a l'infini et le pressostat de securite coupe l'injection !"
    },
    {
        car = "CITROEN ZX VOLCANE 1.9 TD (XUD9TE - POMPE BOSCH VE)",
        symptom = "Moteur mou, aucune poussee quand le turbo souffle, pas de fumee noire.",
        dtc = "STATION CITROEN ELIT : Moteur 100% mecanique (Pas d'electronique moteur).",
        live = {
            "Manometre sur collecteur d'admission : Le turbo souffle bien a 0.9 bar !",
            "Calage comparateur pompe Bosch VE : 0.88 mm (Parfait)",
            "Enrichissement suralimentation (Capsule LDA sur pompe) : Aucun mouvement"
        },
        test_hint = "Demontage couvercle LDA : La membrane caoutchouc est percee et le petit tuyau de pression d'air est bouche !",
        parts = {
            "1. Remplacer le turbocompresseur KKK K14 (3200 F)",
            "2. Remplacer les 4 bougies de prechauffage Beru (240 F)",
            "3. Remplacer la membrane de LDA sur la pompe Bosch et deboucher le piquage (190 F)",
            "4. Refaire le joint de culasse (1900 F)"
        },
        correct = 3,
        reward = 600,
        explanation = "Le grand classique du XUD9TE ! Sans pression sur la membrane de LDA, la pompe Bosch n'enrichit jamais en gazole quand le turbo charge."
    },
    {
        car = "SEAT MARBELLA 900CC SPECIAL (ALLUMAGE & CARBU WEBER)",
        symptom = "Demarrage difficile, petarades a la deceleration et cale aux feux rouges.",
        dtc = "CONTROLEUR SOURIAU : Angle Dwell / Came hors tolerance, etincelle faible.",
        live = {
            "Lampe stroboscopique : Le repere sur le volant moteur saute de 8 degres !",
            "Gicleur de ralenti : Propre | Etouffoir electrique : 12V OK",
            "Condensateur et vis platinées (Rupteur) : Contacts creuses et charbonnes"
        },
        test_hint = "Jauge d'epaisseur : L'ecartement des vis platinées est tombe a 0.15 mm au lieu de 0.40 mm et le condensateur fuit.",
        parts = {
            "1. Remplacer le kit Rupteur + Condensateur et regler l'avance a la lampe strobo (150 F)",
            "2. Remplacer le carburateur Weber 32 ICEV complet (1400 F)",
            "3. Remplacer l'alternateur (750 F)",
            "4. Remplacer la chaine de distribution (900 F)"
        },
        correct = 1,
        reward = 450,
        explanation = "Impeccable ! Un jeu de vis platinées deregle avec un condensateur fatigue ruine l'allumage et le ralenti."
    }
}

-- =====================================================================
-- 2. MODULE 1 : ATELIER DE DIAGNOSTIC ANNEES 90
-- =====================================================================
local function run_diagnostic_workshop()
    local case = CASES[math.random(1, #CASES)]
    local dtc_read  = false
    local live_read = false
    local test_done = false

    local function draw_diag_screen()
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)

        local top = string.format("3615 GARAGE 90S - DIAGNOSTIC | CAISSE: %d FRANCS | REPUTATION: %d%%", cash, rep)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

        minitel.draw_window(2, 3, 78, 5, "ORDRE DE REPARATION : " .. case.car)
        io.write("\x1b[5;4H\x1b[1mSYMPTOME CLIENT :\x1b[0m " .. string.sub(case.symptom, 1, 56))
        io.write("\x1b[6;4H\x1b[1mMAIN D'OEUVRE   :\x1b[0m +" .. case.reward .. " Francs (Erreur de piece : -250 F)")

        minitel.draw_window(2, 9, 78, 9, "APPAREILS DE CONTROLE (VALISE XR25 / TEP 92 / BANC SOURIAU)")
        if not dtc_read and not live_read and not test_done then
            io.write("\x1b[12;4H" .. minitel.center("BRANCHEZ LA VALISE XR25 OU LE BANC SOURIAU SUR LE MOTEUR.", 72))
            io.write("\x1b[14;4H" .. minitel.center("Utilisez [A], [B] et [C] pour isoler la panne avant de reparer.", 72))
        else
            if dtc_read then
                io.write("\x1b[11;4H\x1b[7m[XR25]\x1b[0m " .. string.sub(case.dtc, 1, 66))
            else
                io.write("\x1b[11;4H[XR25] Valise diagnostic non branchee (Touche [A])")
            end

            if live_read then
                io.write("\x1b[13;4H\x1b[7m[BANC]\x1b[0m " .. string.sub(case.live[1], 1, 66))
                io.write("\x1b[14;4H       " .. string.sub(case.live[2], 1, 66))
                io.write("\x1b[15;4H       " .. string.sub(case.live[3], 1, 66))
            else
                io.write("\x1b[13;4H[BANC] Controleur Souriau / Manometre non lu (Touche [B])")
            end

            if test_done then
                io.write("\x1b[16;4H\x1b[7m[MECA]\x1b[0m " .. string.sub(case.test_hint, 1, 66))
            else
                io.write("\x1b[16;4H[MECA] Inspection mecanique non effectuee (Touche [C])")
            end
        end

        minitel.draw_window(2, 19, 78, 5, "CHOIX DE L'INTERVENTION MECANIQUE (TOUCHES 1 A 4)")
        io.write("\x1b[20;4H" .. minitel.pad(case.parts[1], 36) .. " | " .. minitel.pad(case.parts[2], 35))
        io.write("\x1b[21;4H" .. minitel.pad(case.parts[3], 36) .. " | " .. minitel.pad(case.parts[4], 35))

        io.write("\x1b[24;1H\x1b[7m [A] VALISE XR25 | [B] BANC SOURIAU | [C] TEST MECA | [1-4] REPARER | [RETOUR]  \x1b[0m")
        io.flush()
    end

    draw_diag_screen()

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then
                return
            elseif k == "A" or k == "a" then
                dtc_read = true; minitel.play_sound("hit"); draw_diag_screen()
            elseif k == "B" or k == "b" then
                live_read = true; minitel.play_sound("hit"); draw_diag_screen()
            elseif k == "C" or k == "c" then
                test_done = true; minitel.play_sound("pickup"); draw_diag_screen()
            elseif k == "1" or k == "2" or k == "3" or k == "4" then
                local choice = tonumber(k)
                if choice == case.correct then
                    cash = cash + case.reward
                    rep  = math.min(100, rep + 5)
                    minitel.msg_box("FACTURE REGLEE (+" .. case.reward .. " FRANCS)", case.explanation, "win")
                else
                    cash = cash - 250
                    rep  = math.max(0, rep - 15)
                    minitel.msg_box("RETOUR CLIENT (-250 FRANCS)", "Piece remplacee pour rien ! La panne est toujours presente sur l'auto.", "lose")
                end
                return
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- 3. MODULE 2 : GRAVURE D'EPROM 27C256 & BANC A ROULEAUX SOURIAU
-- =====================================================================
local boost_bar = 0.85 -- Pression Wastegate (0.85 bar d'origine)
local fuel_hex  = 100  -- Richesse table EPROM 27C256 (%)
local ign_deg   = 18   -- Avance allumeur / table Fenix (degres)

local function run_dyno_tuner()
    local cur_param = 1
    local last_hp   = 160
    local last_nm   = 245
    local last_co   = 2.1
    local status_str = "EPROM 27C256 D'ORIGINE MONTEE SUR SUPPORT TULIPE. PRET POUR ESSAI."

    local function draw_dyno_ui(curve_points)
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)

        local top = string.format("3615 BANC SOURIAU & EPROM 27C256 | DERNIER TIR: %d CH DIN / %d M.KG", last_hp, math.floor(last_nm / 9.81))
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center(top, 80) .. "\x1b[0m")

        minitel.draw_window(2, 3, 38, 14, "REGLAGES & EPROM UV 27C256")

        local p1_sel = (cur_param == 1) and "\x1b[7m> 1. ROBINET TURBO   <\x1b[0m" or "  1. ROBINET TURBO    "
        io.write(string.format("\x1b[5;4H%s : %4.2f BAR", p1_sel, boost_bar))
        minitel.progress_bar(4, 6, 34, math.floor((boost_bar - 0.5) * 100), 120, false)

        local p2_sel = (cur_param == 2) and "\x1b[7m> 2. TABLE RICHESSE  <\x1b[0m" or "  2. TABLE RICHESSE   "
        io.write(string.format("\x1b[8;4H%s : %3d %%", p2_sel, fuel_hex))
        minitel.progress_bar(4, 9, 34, fuel_hex - 70, 70, false)

        local p3_sel = (cur_param == 3) and "\x1b[7m> 3. AVANCE ALLUMEUR <\x1b[0m" or "  3. AVANCE ALLUMEUR  "
        io.write(string.format("\x1b[11;4H%s : %3d DEG", p3_sel, ign_deg))
        minitel.progress_bar(4, 12, 34, ign_deg - 8, 24, false)

        io.write(string.format("\x1b[14;4HTAUX CO : %3.1f %% | COUPLE : %d NM", last_co, last_nm))
        io.write(string.format("\x1b[15;4HPUISSANCE : \x1b[1m%d CH DIN (NORME 90)\x1b[0m", last_hp))

        minitel.draw_window(41, 3, 39, 14, "COURBE BANC BOSCH/SOURIAU (CH DIN)")
        for r = 1, 10 do
            local hp_scale = 260 - (r - 1) * 20
            io.write(string.format("\x1b[%d;42H%3d|                                 ", 4 + r, hp_scale))
        end
        io.write("\x1b[15;42H   +---------------------------------")
        io.write("\x1b[16;42H    2.0k   3.0k   4.0k   5.0k   6.5k ")

        if curve_points then
            for idx, hp_val in ipairs(curve_points) do
                local col = 46 + (idx - 1) * 3
                local row = 14 - math.max(0, math.min(9, math.floor((hp_val - 80) / 20)))
                io.write(string.format("\x1b[%d;%dH\x1b[7m*\x1b[0m", row, col))
            end
        end

        minitel.draw_window(2, 18, 78, 5, "STETHOSCOPE CLIQUETIS & ANALYSEUR 4 GAZ")
        io.write("\x1b[20;4H> " .. minitel.pad(status_str, 72))

        io.write("\x1b[24;1H\x1b[7m [Z/S] CHOIX | [Q/D] REGLER | [ENVOI] GRAVER EPROM & TIR AU BANC | [RETOUR]     \x1b[0m")
        io.flush()
    end

    draw_dyno_ui(nil)

    while true do
        local k = minitel.get_key()
        if k then
            if k == "RETOUR" or k == "ESC" then return
            elseif k == "UP" or k == "Z" or k == "z" then
                cur_param = (cur_param > 1) and (cur_param - 1) or 3
                draw_dyno_ui(nil)
            elseif k == "DOWN" or k == "S" or k == "s" then
                cur_param = (cur_param < 3) and (cur_param + 1) or 1
                draw_dyno_ui(nil)
            elseif k == "LEFT" or k == "Q" or k == "q" or k == "RIGHT" or k == "D" or k == "d" then
                local dir = (k == "RIGHT" or k == "D" or k == "d") and 1 or -1
                if cur_param == 1 then
                    boost_bar = math.max(0.55, math.min(1.65, boost_bar + (dir * 0.05)))
                elseif cur_param == 2 then
                    fuel_hex = math.max(75, math.min(140, fuel_hex + (dir * 5)))
                elseif cur_param == 3 then
                    ign_deg = math.max(10, math.min(32, ign_deg + (dir * 1)))
                end
                minitel.play_sound("hit")
                draw_dyno_ui(nil)

            elseif k == "ENVOI" or k == " " then
                local air_ratio = boost_bar / 0.85
                local rich_ratio = (fuel_hex / 100.0) / air_ratio
                last_co = math.max(0.4, math.min(9.5, 2.2 * rich_ratio * rich_ratio))

                local knock = (ign_deg > 23 and boost_bar > 1.15) or (rich_ratio < 0.90 and boost_bar > 1.0)
                local too_rich = (last_co > 5.5)

                local peak_hp = math.floor(160 * air_ratio * math.min(1.12, rich_ratio) + (ign_deg - 18) * 3.0)
                if too_rich then peak_hp = peak_hp - 22 end
                if knock then peak_hp = math.floor(peak_hp * 0.68) end

                last_hp = math.max(90, peak_hp)
                last_nm = math.floor(last_hp * 1.65)

                local pts = {}
                for step = 1, 10 do
                    local rpm_ratio = step / 10.0
                    table.insert(pts, math.floor(last_hp * math.sin(rpm_ratio * 1.48)))
                end

                if knock then
                    status_str = "ALERTE CLIQUETIS ! Le joint de culasse souffre (Trop d'avance ou trop pauvre) !"
                    minitel.play_sound("lose")
                elseif too_rich then
                    status_str = "ENGORGEMENT (CO = " .. string.format("%.1f%%", last_co) .. ") ! Les bougies s'encrassent, baissez la richesse."
                    minitel.play_sound("hit")
                else
                    status_str = string.format("EPROM VALIDEE : %d CH DIN ! Moteur plein a tous les regimes (CO: %.1f%%).", last_hp, last_co)
                    minitel.play_sound("win")
                end

                draw_dyno_ui(pts)
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- MENU PRINCIPAL DU GARAGE 1993
-- =====================================================================
while true do
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  3615 GARAGE (1993) - DIAGNOSTIC XR25 & PREPARATION EPROM  * * *", 80) .. "\x1b[0m")

    minitel.draw_window(16, 5, 50, 15, "GARAGE DES SPORTS & YOUNGTIMERS")
    io.write(string.format("\x1b[7;20H\x1b[1mCAISSE ATELIER :\x1b[0m %d FRANCS", cash))
    io.write(string.format("\x1b[8;20H\x1b[1mREPUTATION     :\x1b[0m %d %%", rep))

    io.write("\x1b[11;20H\x1b[7m [1] \x1b[0m DIAGNOSTIC PANNE CLIENT (XR25 / SOURIAU)")
    io.write("\x1b[13;20H\x1b[7m [2] \x1b[0m BANC A ROULEAUX & GRAVURE EPROM 27C256")
    io.write("\x1b[16;20H\x1b[7m [RETOUR] \x1b[0m FERMER LE RIDEAU DE L'ATELIER")

    io.write("\x1b[24;1H\x1b[7m  TAPEZ [1] POUR LE DIAGNOSTIC MECANIQUE OU [2] POUR LE BANC DE PUISSANCE       \x1b[0m")
    io.flush()

    local k = minitel.get_key()
    if k == "RETOUR" or k == "ESC" then break
    elseif k == "1" then run_diagnostic_workshop()
    elseif k == "2" then run_dyno_tuner()
    end
    minitel.sleep(0.02)
end

minitel.cleanup()