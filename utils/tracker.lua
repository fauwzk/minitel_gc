-- @TYPE: MUSIQUE / TRACKER 4 PISTES
-- @DESC: Sequenceur musical Chiptune 4 pistes (style ProTracker Amiga) avec boite a rythmes, piano direct et synthese SoX temps reel.

local minitel = require("minitel")
minitel.init()

os.execute("mkdir -p utils/music 2>/dev/null")

-- =====================================================================
-- 1. TABLE DES FREQUENCES MUSICALES (OCTAVES 2 A 5) & BATTERIE
-- =====================================================================
local NOTE_FREQS = {
    ["C-2"] = 65.41,  ["C#2"] = 69.30,  ["D-2"] = 73.42,  ["D#2"] = 77.78,  ["E-2"] = 82.41,  ["F-2"] = 87.31,
    ["F#2"] = 92.50,  ["G-2"] = 98.00,  ["G#2"] = 103.83, ["A-2"] = 110.00, ["A#2"] = 116.54, ["B-2"] = 123.47,
    ["C-3"] = 130.81, ["C#3"] = 138.59, ["D-3"] = 146.83, ["D#3"] = 155.56, ["E-3"] = 164.81, ["F-3"] = 174.61,
    ["F#3"] = 185.00, ["G-3"] = 196.00, ["G#3"] = 207.65, ["A-3"] = 220.00, ["A#3"] = 233.08, ["B-3"] = 246.94,
    ["C-4"] = 261.63, ["C#4"] = 277.18, ["D-4"] = 293.66, ["D#4"] = 311.13, ["E-4"] = 329.63, ["F-4"] = 349.23,
    ["F#4"] = 369.99, ["G-4"] = 392.00, ["G#4"] = 415.30, ["A-4"] = 440.00, ["A#4"] = 466.16, ["B-4"] = 493.88,
    ["C-5"] = 523.25, ["C#5"] = 554.37, ["D-5"] = 587.33, ["D#5"] = 622.25, ["E-5"] = 659.25, ["F-5"] = 698.46,
    ["F#5"] = 739.99, ["G-5"] = 783.99, ["G#5"] = 830.61, ["A-5"] = 880.00, ["A#5"] = 932.33, ["B-5"] = 987.77
}

-- Touches du clavier Minitel pour saisir les 7 notes de la gamme (A Z E R T Y U)
local KEY_TO_NOTE = {
    ["A"] = "C-", ["Z"] = "D-", ["E"] = "E-", ["R"] = "F-",
    ["T"] = "G-", ["Y"] = "A-", ["U"] = "B-"
}

-- Touches pour la Piste 4 (Boite a rythmes : 1=KICK, 2=SNARE, 3=HIHAT, 4=CLAP)
local DRUM_NAMES = {
    ["1"] = "KICK", ["2"] = "SNAR", ["3"] = "HHAT", ["4"] = "CLAP",
    ["A"] = "KICK", ["Z"] = "SNAR", ["E"] = "HHAT", ["R"] = "CLAP"
}

-- =====================================================================
-- 2. ETAT DU SEQUENCEUR & BANQUE DE DEMOS 80S / 90S
-- =====================================================================
local NUM_STEPS  = 16
local NUM_TRACKS = 4
local bpm = 125
local current_octave = 4
local is_playing = false
local play_step = 1
local prev_play_step = 1
local cur_track = 1
local cur_step  = 1
local track_mute = { false, false, false, false }
local song_name = "DEMO_SYNTH.MOD"

local pattern = {}
local function clear_pattern()
    for s = 1, NUM_STEPS do
        pattern[s] = { "---", "---", "---", "---" }
    end
end
clear_pattern()

local DEMOS = {
    {
        name = "1. AXEL-F / BEVERLY 84",
        bpm = 120,
        data = {
            {"F-4", "F-3", "F-2", "KICK"},
            {"---", "---", "---", "HHAT"},
            {"G#4", "C-4", "F-2", "HHAT"},
            {"F-4", "---", "---", "KICK"},
            {"F-4", "A-3", "C-3", "SNAR"},
            {"A#4", "---", "---", "HHAT"},
            {"F-4", "F-3", "F-2", "KICK"},
            {"D#4", "---", "D#2", "HHAT"},
            {"F-4", "F-3", "F-2", "KICK"},
            {"---", "---", "---", "HHAT"},
            {"C-5", "E-4", "C-3", "HHAT"},
            {"F-4", "---", "---", "KICK"},
            {"F-4", "G#3", "C#3", "SNAR"},
            {"C#5", "---", "---", "HHAT"},
            {"C-5", "G-3", "C-3", "KICK"},
            {"G#4", "E-3", "C-2", "SNAR"}
        }
    },
    {
        name = "2. TECHNO RAVE 1992",
        bpm = 138,
        data = {
            {"C-4", "G-3", "C-2", "KICK"},
            {"---", "---", "C-3", "HHAT"},
            {"D#4", "A#3", "C-2", "HHAT"},
            {"---", "---", "C-3", "HHAT"},
            {"F-4", "C-4", "F-2", "SNAR"},
            {"---", "---", "F-3", "HHAT"},
            {"D#4", "A#3", "D#2", "KICK"},
            {"D-4", "---", "D-3", "HHAT"},
            {"C-4", "G-3", "C-2", "KICK"},
            {"---", "---", "C-3", "HHAT"},
            {"G-4", "D-4", "G-2", "HHAT"},
            {"---", "---", "G-3", "HHAT"},
            {"F-4", "C-4", "G#2", "SNAR"},
            {"D#4", "---", "G#2", "HHAT"},
            {"D-4", "A#3", "G-2", "KICK"},
            {"---", "---", "G-3", "CLAP"}
        }
    },
    {
        name = "3. OUTRUN NIGHT DRIVE",
        bpm = 128,
        data = {
            {"A-4", "E-4", "A-2", "KICK"},
            {"---", "---", "A-2", "HHAT"},
            {"E-4", "C-4", "A-3", "SNAR"},
            {"A-4", "---", "A-2", "HHAT"},
            {"G-4", "D-4", "G-2", "KICK"},
            {"---", "---", "G-2", "HHAT"},
            {"D-4", "B-3", "G-3", "SNAR"},
            {"G-4", "---", "G-2", "HHAT"},
            {"F-4", "C-4", "F-2", "KICK"},
            {"---", "---", "F-2", "HHAT"},
            {"C-4", "A-3", "F-3", "SNAR"},
            {"F-4", "---", "F-2", "HHAT"},
            {"E-4", "B-3", "E-2", "KICK"},
            {"---", "---", "E-2", "HHAT"},
            {"G#4", "E-4", "E-3", "SNAR"},
            {"B-4", "---", "E-2", "CLAP"}
        }
    }
}

local function load_demo(idx)
    local d = DEMOS[idx]
    if not d then return end
    bpm = d.bpm
    song_name = d.name:gsub("^%d+%.%s*", ""):gsub("%s+", "_") .. ".MOD"
    for s = 1, NUM_STEPS do
        for t = 1, NUM_TRACKS do
            pattern[s][t] = d.data[s][t] or "---"
        end
    end
end

load_demo(1)

-- =====================================================================
-- 3. MOTEUR DE SYNTHESE POLYPHONIQUE SOX TEMPS REEL
-- =====================================================================
local function trigger_step_audio(step_idx)
    local row = pattern[step_idx]
    if not row then return end

    local step_dur = string.format("%.2f", (60.0 / bpm) / 2.2)
    local sox_inputs = {}

    -- Pistes 1 a 3 : Synthetiseurs melodiques (Square, Sawtooth, Triangle)
    local waves = { "square", "sawtooth", "triangle" }
    local vols  = { "0.28", "0.22", "0.35" }

    for t = 1, 3 do
        if not track_mute[t] then
            local note = row[t]
            local freq = NOTE_FREQS[note]
            if freq then
                local cmd_part = string.format("\"|sox -n -p synth %s %s %.2f vol %s\"",
                    step_dur, waves[t], freq, vols[t])
                table.insert(sox_inputs, cmd_part)
            end
        end
    end

    -- Piste 4 : Boite a rythmes (KICK, SNAR, HHAT, CLAP)
    if not track_mute[4] then
        local drm = row[4]
        if drm == "KICK" then
            table.insert(sox_inputs, "\"|sox -n -p synth 0.11 sine 130-42 vol 0.45\"")
        elseif drm == "SNAR" then
            table.insert(sox_inputs, "\"|sox -n -p synth 0.10 noise bandpass 1200 800 vol 0.30\"")
        elseif drm == "HHAT" then
            table.insert(sox_inputs, "\"|sox -n -p synth 0.04 noise highpass 5000 vol 0.18\"")
        elseif drm == "CLAP" then
            table.insert(sox_inputs, "\"|sox -n -p synth 0.09 noise bandpass 1800 600 vol 0.32\"")
        end
    end

    if #sox_inputs == 1 then
        -- Une seule voix active : appel direct ultra-rapide
        local single = sox_inputs[1]:gsub('^"|sox %-n %-p ', ""):gsub('"$', "")
        os.execute("which play >/dev/null 2>&1 && (play -q -n " .. single .. " >/dev/null 2>&1 &)")
    elseif #sox_inputs > 1 then
        -- Plusieurs voix simultanées : mixage temps reel (-m) en un seul processus !
        local mix_cmd = "which play >/dev/null 2>&1 && (play -q -m " .. table.concat(sox_inputs, " ") .. " >/dev/null 2>&1 &)"
        os.execute(mix_cmd)
    end
end

-- =====================================================================
-- 4. AFFICHAGE DELTA-DRAWING DU TRACKER (ZERO CLIGNOTEMENT)
-- =====================================================================
local TRACK_COLS = { 12, 26, 40, 54 }

local function draw_cell(s, t, is_cursor)
    local y = 6 + s
    local x = TRACK_COLS[t]
    local val = pattern[s][t] or "---"
    local disp = minitel.center(val, 8)

    if is_cursor then
        io.write(string.format("\x1b[%d;%dH\x1b[7m>%s<\x1b[0m", y, x, disp))
    elseif val ~= "---" then
        io.write(string.format("\x1b[%d;%dH \x1b[1m%s\x1b[0m ", y, x, disp))
    else
        io.write(string.format("\x1b[%d;%dH %s ", y, x, disp))
    end
end

-- Met a jour uniquement la petite fleche de lecture '>' sur la colonne 5 (6 octets !)
local function update_playhead_arrow(old_s, new_s)
    if old_s >= 1 and old_s <= NUM_STEPS then
        io.write(string.format("\x1b[%d;4H %02d ", 6 + old_s, old_s - 1))
    end
    if new_s >= 1 and new_s <= NUM_STEPS then
        if is_playing then
            io.write(string.format("\x1b[%d;4H\x1b[7m>%02d<\x1b[0m", 6 + new_s, new_s - 1))
        else
            io.write(string.format("\x1b[%d;4H %02d ", 6 + new_s, new_s - 1))
        end
    end
end

local function update_top_status()
    local st_play = is_playing and "\x1b[7m [LECTURE EN COURS] \x1b[0m" or " [ARRET - EDITION]  "
    local top = string.format(" 3615 PROTRACKER | %s | BPM:%3d | OCT:%d | %s",
        minitel.pad(song_name, 16), bpm, current_octave, st_play)
    io.write("\x1b[1;1H\x1b[7m" .. minitel.pad(top, 80) .. "\x1b[0m")

    -- Entetes des 4 pistes avec indicateur MUTE
    local t_names = { "1:LEAD SQR", "2:SYNT SAW", "3:BASS SUB", "4:DRUM KIT" }
    for t = 1, 4 do
        local x = TRACK_COLS[t]
        local label = track_mute[t] and " [MUET]   " or t_names[t]
        io.write(string.format("\x1b[5;%dH\x1b[7m%s\x1b[0m", x, label))
    end
end

local function draw_tracker_static()
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)

    minitel.draw_window(2, 3, 64, 20, "GRILLE DU SEQUENCEUR 16 PAS (4 CANAUX)")
    io.write("\x1b[5;4H\x1b[7mPAS \x1b[0m")
    io.write("\x1b[6;3H--------------------------------------------------------------")

    for s = 1, NUM_STEPS do
        local y = 6 + s
        io.write(string.format("\x1b[%d;4H %02d  |          |          |          |          |", y, s - 1))
        for t = 1, NUM_TRACKS do
            draw_cell(s, t, (s == cur_step and t == cur_track))
        end
    end

    -- Panneau d'aide a droite (Colonnes 67 a 79)
    minitel.draw_window(67, 3, 13, 20, "COMMANDES")
    io.write("\x1b[5;68H\x1b[1mNOTES P1-P3:\x1b[0m")
    io.write("\x1b[6;68HA=Do   Z=Re ")
    io.write("\x1b[7;68HE=Mi   R=Fa ")
    io.write("\x1b[8;68HT=Sol  Y=La ")
    io.write("\x1b[9;68HU=Si        ")
    io.write("\x1b[10;68H[#] Diese # ")
    io.write("\x1b[11;68H------------")
    io.write("\x1b[12;68H\x1b[1mDRUMS P4 :\x1b[0m")
    io.write("\x1b[13;68H1/A = KICK  ")
    io.write("\x1b[14;68H2/Z = SNARE ")
    io.write("\x1b[15;68H3/E = HIHAT ")
    io.write("\x1b[16;68H4/R = CLAP  ")
    io.write("\x1b[17;68H------------")
    io.write("\x1b[18;68H[ESP] PLAY  ")
    io.write("\x1b[19;68H[O] OCTAVE  ")
    io.write("\x1b[20;68H[+/-] TEMPO ")
    io.write("\x1b[21;68H[D] DEMOS   ")

    io.write("\x1b[24;1H\x1b[7m [ESPACE] PLAY/STOP | [AZERTYU] NOTES | [ANNUL] EFFACER | [D] DEMOS | [RETOUR]  \x1b[0m")
    update_top_status()
    update_playhead_arrow(1, play_step)
    io.flush()
end

-- =====================================================================
-- 5. SAUVEGARDE, CHARGEMENT & MENU FICHIER
-- =====================================================================
local function save_song(path)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(string.format("return { bpm = %d, pattern = {\n", bpm))
    for s = 1, NUM_STEPS do
        f:write(string.format("  {%q, %q, %q, %q},\n",
            pattern[s][1], pattern[s][2], pattern[s][3], pattern[s][4]))
    end
    f:write("}}\n")
    f:close()
    return true
end

local function load_song(path)
    local fn = loadfile(path)
    if fn then
        local ok, data = pcall(fn)
        if ok and type(data) == "table" and data.pattern then
            bpm = data.bpm or 125
            for s = 1, NUM_STEPS do
                if data.pattern[s] then
                    for t = 1, NUM_TRACKS do
                        pattern[s][t] = data.pattern[s][t] or "---"
                    end
                end
            end
            song_name = path:match("([^/]+)$") or path
            return true
        end
    end
    return false
end

local function open_tracker_menu()
    is_playing = false
    io.write("\x1b[r\x1b[2J\x1b[H")
    minitel.sleep(0.04)
    minitel.draw_window(20, 5, 42, 15, "MENU STUDIO 3615 PROTRACKER")
    io.write("\x1b[7;24H\x1b[7m [1] \x1b[0m REPRENDRE LA COMPOSITION")
    io.write("\x1b[9;24H\x1b[7m [2] \x1b[0m CHARGER DEMO 1 : AXEL-F 1984")
    io.write("\x1b[10;24H\x1b[7m [3] \x1b[0m CHARGER DEMO 2 : TECHNO 1992")
    io.write("\x1b[11;24H\x1b[7m [4] \x1b[0m CHARGER DEMO 3 : OUTRUN DRIVE")
    io.write("\x1b[13;24H\x1b[7m [5] \x1b[0m VIDER LA GRILLE (NOUVEAU)")
    io.write("\x1b[14;24H\x1b[7m [6] \x1b[0m OUVRIR UN MORCEAU (.MOD)...")
    io.write("\x1b[15;24H\x1b[7m [7] \x1b[0m SAUVEGARDER LE MORCEAU...")
    io.write("\x1b[17;24H\x1b[7m [9] \x1b[0m QUITTER VERS LE PORTAIL")
    io.flush()

    while true do
        local k = minitel.get_key()
        if k == "1" or k == "RETOUR" or k == "ESC" then
            break
        elseif k == "2" or k == "3" or k == "4" then
            load_demo(tonumber(k) - 1)
            minitel.play_sound("pickup")
            break
        elseif k == "5" then
            if minitel.confirm_box("NOUVEAU MORCEAU", "Effacer toutes les notes de la grille ?") then
                clear_pattern()
                song_name = "SANS_TITRE.MOD"
            end
            break
        elseif k == "6" then
            local target = minitel.file_browser("OPEN", "utils/music/")
            if target then load_song(target) end
            break
        elseif k == "7" then
            local target = minitel.file_browser("SAVE", "utils/music/")
            if target then
                if not target:find("%.MOD$") and not target:find("%.lua$") then
                    target = target .. ".MOD"
                end
                if save_song(target) then
                    song_name = target:match("([^/]+)$") or target
                    minitel.msg_box("SAUVEGARDE OK", "Morceau enregistre sous " .. song_name, "win")
                end
            end
            break
        elseif k == "9" then
            return "QUIT"
        end
        minitel.sleep(0.02)
    end
    draw_tracker_static()
    return "CONTINUE"
end

-- =====================================================================
-- 6. BOUCLE PRINCIPALE TEMPS REEL
-- =====================================================================
local function get_mono_time()
    local f = io.open("/proc/uptime", "r")
    if f then
        local s = f:read("*l")
        f:close()
        local up = s and tonumber(s:match("^([%d%.]+)"))
        if up then return up end
    end
    return os.clock()
end

draw_tracker_static()
local last_step_time = get_mono_time()
local demo_cycle = 1

while true do
    -- 1. Horloge du sequenceur musical (16 pas en boucle)
    if is_playing then
        local now = get_mono_time()
        local step_interval = (60.0 / bpm) / 2.0 -- Croches (8th notes)
        if now - last_step_time >= step_interval then
            last_step_time = now
            prev_play_step = play_step
            play_step = (play_step % NUM_STEPS) + 1
            update_playhead_arrow(prev_play_step, play_step)
            io.flush()
            trigger_step_audio(play_step)
        end
    end

    -- 2. Lecture non-bloquante du clavier Minitel
    local k = minitel.get_key()
    if k then
        local ku = string.upper(k)

        if k == "RETOUR" or k == "ESC" or k == "D" or k == "d" then
            if open_tracker_menu() == "QUIT" then break end

        elseif k == " " then
            -- Play / Pause instantane avec la barre d'espace !
            is_playing = not is_playing
            if is_playing then
                last_step_time = get_mono_time()
                trigger_step_audio(play_step)
            end
            update_top_status()
            update_playhead_arrow(prev_play_step, play_step)
            io.flush()

        elseif k == "UP" or k == "DOWN" or k == "LEFT" or k == "RIGHT" then
            local os_s, os_t = cur_step, cur_track
            if k == "UP" then cur_step = (cur_step > 1) and (cur_step - 1) or NUM_STEPS
            elseif k == "DOWN" then cur_step = (cur_step < NUM_STEPS) and (cur_step + 1) or 1
            elseif k == "LEFT" then cur_track = (cur_track > 1) and (cur_track - 1) or NUM_TRACKS
            elseif k == "RIGHT" then cur_track = (cur_track < NUM_TRACKS) and (cur_track + 1) or 1
            end
            draw_cell(os_s, os_t, false)
            draw_cell(cur_step, cur_track, true)
            io.flush()

        elseif ku == "O" then
            current_octave = (current_octave < 5) and (current_octave + 1) or 2
            update_top_status()
            io.flush()

        elseif k == "+" then
            bpm = math.min(200, bpm + 5)
            update_top_status()
            io.flush()

        elseif k == "-" then
            bpm = math.max(60, bpm - 5)
            update_top_status()
            io.flush()

        elseif k == "M" or k == "m" then
            -- Mute / Unmute la piste courante
            track_mute[cur_track] = not track_mute[cur_track]
            update_top_status()
            io.flush()

        elseif k == "ANNULATION" or k == "CORRECTION" or k == "." then
            pattern[cur_step][cur_track] = "---"
            draw_cell(cur_step, cur_track, true)
            io.flush()

        elseif k == "#" then
            -- Bascule une note normale en Diese (ex: C-4 -> C#4)
            local cur_val = pattern[cur_step][cur_track]
            if cur_val:match("^[CDFGA]%-") then
                pattern[cur_step][cur_track] = cur_val:gsub("%-", "#")
                draw_cell(cur_step, cur_track, true)
                io.flush()
            elseif cur_val:match("^[CDFGA]#") then
                pattern[cur_step][cur_track] = cur_val:gsub("#", "-")
                draw_cell(cur_step, cur_track, true)
                io.flush()
            end

        elseif cur_track == 4 and DRUM_NAMES[ku] then
            -- Saisie d'une percussion sur la piste 4
            pattern[cur_step][4] = DRUM_NAMES[ku]
            if not is_playing then trigger_step_audio(cur_step) end
            local old_s = cur_step
            cur_step = (cur_step < NUM_STEPS) and (cur_step + 1) or 1
            draw_cell(old_s, 4, false)
            draw_cell(cur_step, 4, true)
            io.flush()

        elseif cur_track <= 3 and KEY_TO_NOTE[ku] then
            -- Saisie d'une note de musique avec A Z E R T Y U (et avance d'une ligne automatiquement !)
            local new_note = KEY_TO_NOTE[ku] .. tostring(current_octave)
            pattern[cur_step][cur_track] = new_note
            if not is_playing then trigger_step_audio(cur_step) end
            local old_s = cur_step
            cur_step = (cur_step < NUM_STEPS) and (cur_step + 1) or 1
            draw_cell(old_s, cur_track, false)
            draw_cell(cur_step, cur_track, true)
            io.flush()
        end
    end

    minitel.sleep(0.01)
end

minitel.cleanup()