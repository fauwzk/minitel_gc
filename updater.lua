local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("git config --global --add safe.directory '*' >/dev/null 2>&1")

-- =====================================================================
-- MOTEUR GIT (EXECUTION ET CAPTURE D'ERREUR)
-- =====================================================================
local function run_git(args)
    local f = io.popen("git " .. args .. " 2>&1")
    local output = f:read("*a") or ""
    local success, exit_type, exit_code = f:close()
    return success, output
end

local function get_latest_commit()
    local f = io.popen("git log -1 --format='%h|%an|%s' 2>/dev/null")
    if f then
        local line = f:read("*l")
        f:close()
        if line then
            local h, a, m = string.match(line, "^(.-)|(.-)|(.*)$")
            if h then
                return {
                    hash = h, 
                    author = string.sub(a, 1, 20), 
                    msg = string.sub(m, 1, 38)
                }
            end
        end
    end
    return nil
end

-- =====================================================================
-- UTILITAIRES D'INTERFACE
-- =====================================================================
local function draw_frame(title)
    io.write("\x1b[2J\x1b[H")
    io.write("\x1b[2;11H\x1b[7m==========================================================\x1b[0m\r\n")
    local pad_left = math.floor((56 - #title) / 2)
    local pad_right = 56 - #title - pad_left
    io.write("\x1b[3;11H\x1b[7m|" .. string.rep(" ", pad_left) .. title .. string.rep(" ", pad_right) .. "|\x1b[0m\r\n")
    io.write("\x1b[4;11H\x1b[7m==========================================================\x1b[0m\r\n")
end

local function prompt_input(prompt_text)
    io.write(prompt_text)
    io.flush()
    local str = ""
    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then return str
            elseif k == "RETOUR" or k == "ESC" then return "ABORT"
            elseif k == "CORRECTION" or k == "ANNULATION" or k == "\x08" or k == "\x7f" then
                if #str > 0 then
                    str = string.sub(str, 1, -2)
                    io.write("\x1b[D \x1b[D"); io.flush()
                end
            elseif string.match(k, "^[%w%s%p_%.%-]$") and #k == 1 then
                if #str < 35 then
                    str = str .. k
                    io.write(k); io.flush()
                end
            end
        end
        minitel.sleep(0.01)
    end
end

local function show_error(err_msg)
    minitel.play_sound("damage")
    io.write("\x1b[11;11H\x1b[7m ERREUR SYSTEME : \x1b[0m\r\n")
    
    local y = 13
    for line in err_msg:gmatch("[^\r\n]+") do
        if y <= 18 then
            io.write(string.format("\x1b[%d;11H %s\r\n", y, string.sub(line, 1, 56)))
            y = y + 1
        end
    end
    
    io.write("\x1b[22;11H==========================================================\r\n")
    io.write("\x1b[23;20H\x1b[7m [RETOUR] RETOURNER AU MENU PRINCIPAL \x1b[0m")
    io.flush()
    
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == "ENVOI" or k == "\r" or k == "\n" then break end
        minitel.sleep(0.05)
    end
end

-- =====================================================================
-- PROTECTION DES PROGRAMMES BASIC LOCAUX
-- =====================================================================
-- Les programmes enregistres depuis le MICRO-BASIC (utils/prog_basic) ne
-- doivent jamais etre ecrases ni effaces par une mise a jour : ils sont mis
-- de cote avant toute operation git, puis remis en place a l'identique.
local BASIC_DIR = "utils/prog_basic"
local BASIC_STASH = "/tmp/minitel_basic_local"
local NOT_BASIC = "-- . ':(exclude)" .. BASIC_DIR .. "'"
local basic_saved = {}

local function sh_quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function copy_file(src, dst)
    local fi = io.open(src, "rb")
    if not fi then return false end
    local data = fi:read("*a")
    fi:close()
    local fo = io.open(dst, "wb")
    if not fo then return false end
    fo:write(data)
    fo:close()
    return true
end

local function dirname(path)
    return string.match(path, "^(.*)/[^/]*$") or "."
end

-- Met de cote les programmes BASIC crees ou modifies localement, puis rend
-- au dossier son etat du depot pour que git pull ne bute jamais dessus.
local function protect_basic()
    local _, out = run_git("status --porcelain -z --untracked-files=all -- " .. BASIC_DIR)
    os.execute("rm -rf " .. BASIC_STASH .. " && mkdir -p " .. BASIC_STASH)

    local skip_next = false
    for entry in string.gmatch(out, "([^\0]+)") do
        if skip_next then
            skip_next = false -- ancien nom d'un fichier renomme
        else
            local code, path = string.sub(entry, 1, 2), string.sub(entry, 4)
            if string.sub(code, 1, 1) == "R" then skip_next = true end
            local rel = string.sub(path, #BASIC_DIR + 2)
            local dst = BASIC_STASH .. "/" .. rel
            os.execute("mkdir -p " .. sh_quote(dirname(dst)))
            if not string.find(code, "D") and copy_file(path, dst) then
                table.insert(basic_saved, rel)
            end
        end
    end

    if #basic_saved > 0 then
        run_git("reset -q -- " .. BASIC_DIR)
        run_git("checkout -- " .. BASIC_DIR)
        run_git("clean -fdq -- " .. BASIC_DIR)
    end
end

-- Remet en place les versions locales (elles l'emportent sur celles du depot)
local function restore_basic()
    for _, rel in ipairs(basic_saved) do
        local dst = BASIC_DIR .. "/" .. rel
        os.execute("mkdir -p " .. sh_quote(dirname(dst)))
        copy_file(BASIC_STASH .. "/" .. rel, dst)
    end
    os.execute("rm -rf " .. BASIC_STASH)
end

local function git_line(args)
    local ok, out = run_git(args)
    if not ok then return nil end
    return (string.gsub(out, "%s+$", ""))
end

-- Retour au menu principal sans redemarrer (master.lua reprend la main)
local function back_to_menu()
    minitel.cleanup()
    os.exit(0)
end

local function show_commit_info(y)
    local commit_info = get_latest_commit()
    if commit_info then
        io.write(string.format("\x1b[%d;15H COMMIT  : %s\r\n", y, commit_info.hash))
        io.write(string.format("\x1b[%d;15H AUTEUR  : %s\r\n", y + 1, commit_info.author))
        io.write(string.format("\x1b[%d;15H MESSAGE : %s\r\n", y + 2, commit_info.msg))
    end
end

local function show_up_to_date()
    minitel.play_sound("pickup")
    draw_frame("S Y S T E M E   A   J O U R")
    io.write("\x1b[10;15H\x1b[1mAUCUNE NOUVELLE VERSION DISPONIBLE.\x1b[0m\r\n")
    show_commit_info(12)
    io.write("\x1b[22;11H==========================================================\r\n")
    io.write("\x1b[23;24H\x1b[7m RETOUR AU MENU PRINCIPAL... \x1b[0m")
    io.flush()
    minitel.sleep(3)
    back_to_menu()
end

-- =====================================================================
-- SEQUENCE DE MISE A JOUR INTELLIGENTE
-- =====================================================================

draw_frame("3 6 1 5   M I S E   A   J O U R")
io.write("\x1b[10;22H\x1b[1mVERIFICATION DU SYSTEME LOCAL...\x1b[0m\r\n")
io.flush()
minitel.play_sound("hit")

-- SAUVEGARDE GLOBALE EN ARRIERE-PLAN (Ceinture de securite)
os.execute("mkdir -p /home/minitel/minitel_gc_backup/utils/prog_basic_backup >/dev/null 2>&1")
os.execute("cp -R /home/minitel/minitel_gc/utils/prog_basic/* /home/minitel/minitel_gc_backup/utils/prog_basic_backup/ >/dev/null 2>&1")

-- 1. On interroge le depot distant, sans rien modifier en local
io.write("\x1b[12;22H INTERROGATION DU SERVEUR...\r\n")
io.flush()
local head_before = git_line("rev-parse HEAD")
local fetch_ok, fetch_err = run_git("fetch --quiet")
if not fetch_ok then
    show_error(fetch_err)
    back_to_menu()
end
-- Nombre de commits du serveur absents en local (nil si pas de branche suivie)
local behind = tonumber(git_line("rev-list --count HEAD..@{u}") or "")

-- 2. On verifie s'il y a des modifications locales (hors programmes BASIC)
local _, status_out = run_git("status --porcelain " .. NOT_BASIC)

if behind == 0 and status_out == "" then
    show_up_to_date()
end

local choice = ""
if status_out ~= "" then
    -- IL Y A DES MODIFICATIONS
    minitel.play_sound("hit")
    draw_frame("C O N F L I T   L O C A L")
    io.write("\x1b[6;13H\x1b[1mMODIFICATIONS NON SAUVEGARDEES DETECTEES :\x1b[0m\r\n")

    local y = 8
    local file_count = 0
    for line in status_out:gmatch("[^\r\n]+") do
        if file_count < 3 then
            io.write(string.format("\x1b[%d;15H %s\r\n", y, string.sub(line, 1, 45)))
            y = y + 1
        end
        file_count = file_count + 1
    end
    if file_count > 3 then io.write(string.format("\x1b[%d;15H ... et %d autres fichiers.\r\n", y, file_count - 3)) end

    io.write("\x1b[14;14H\x1b[7m [1] \x1b[0m FORCER LA M-A-J (ECRASER LE LOCAL)\r\n")
    io.write("\x1b[16;14H\x1b[7m [2] \x1b[0m SAUVEGARDER ET ENVOYER (PUSH)\r\n")
    io.write("\x1b[18;14H\x1b[7m [3] \x1b[0m RENOMMER LOCAL ET METTRE A JOUR\r\n")
    io.write("\x1b[20;14H\x1b[7m [4] \x1b[0m ANNULER (RETOUR MENU)\r\n")
    io.write("\x1b[24;19H CHOISISSEZ UNE OPTION AVEC LE CLAVIER ")
    io.flush()

    while true do
        local k = minitel.get_key()
        if k == "1" or k == "2" or k == "3" or k == "4" or k == "ESC" or k == "RETOUR" then
            choice = k
            break
        end
        minitel.sleep(0.05)
    end

    if choice == "4" or choice == "ESC" or choice == "RETOUR" then
        back_to_menu()

    elseif choice == "2" then
        -- PROCEDURE DE PUSH (le code en place ne change pas : pas de redemarrage)
        draw_frame("E N V O I   V E R S   L E   S E R V E U R")
        io.write("\x1b[10;13H MESSAGE DE COMMIT :\r\n")
        io.write("\x1b[12;13H > \x1b[7m                                     \x1b[0m")
        io.write("\x1b[12;16H")

        local msg = prompt_input("")
        if msg == "ABORT" or msg == "" then msg = "Modification locale depuis le Minitel" end

        io.write("\x1b[15;13H\x1b[1mPREPARATION DES DONNEES...\x1b[0m\x1b[K")
        io.flush()
        run_git("add .")
        run_git("commit -m " .. sh_quote(msg))

        io.write("\x1b[15;13H\x1b[1mENVOI SUR LE DEPOT DISTANT...\x1b[0m\x1b[K")
        io.flush()
        local push_ok, push_err = run_git("push")

        if not push_ok then
            show_error(push_err)
            back_to_menu()
        end

        minitel.play_sound("win")
        draw_frame("P U S H   T E R M I N E")
        io.write("\x1b[12;17H\x1b[1mVOS FICHIERS ONT ETE ENVOYES AVEC SUCCES.\x1b[0m\r\n")
        io.write("\x1b[23;20H\x1b[7m APPUYEZ SUR ENVOI POUR CONTINUER \x1b[0m")
        io.flush()
        while true do
            local k = minitel.get_key()
            if k == "ENVOI" or k == "\r" or k == "\n" then break end
            minitel.sleep(0.05)
        end
        back_to_menu()
    end
end

-- 3. Les programmes BASIC locaux sont mis a l'abri avant de toucher a l'arbre
protect_basic()
local tree_changed = false

if choice == "3" then
    -- PROCEDURE DE RENOMMAGE (Magie noire !)
    draw_frame("S Y N C H R O N I S A T I O N")
    io.write("\x1b[10;14H\x1b[1mRENOMMAGE DES FICHIERS LOCAUX EN COURS...\x1b[0m\r\n")
    io.flush()

    for line in status_out:gmatch("[^\r\n]+") do
        -- On extrait le nom du fichier (en enlevant le code statut au debut)
        local file = string.sub(line, 4)
        file = file:gsub('^"', ''):gsub('"$', '') -- Retire les guillemets eventuels

        if file and file ~= "" then
            local new_name = ""
            local ext = string.match(file, "(%.[^%.]+)$")
            if ext then
                new_name = string.gsub(file, "(%.[^%.]+)$", "_local%1")
            else
                new_name = file .. "_local"
            end
            os.execute("mv " .. sh_quote(file) .. " " .. sh_quote(new_name) .. " 2>/dev/null")
        end
    end
    -- On restaure l'arbre pour que git pull puisse ramener les originaux
    run_git("reset --hard HEAD")
    tree_changed = true

elseif choice == "1" then
    -- PROCEDURE DE RESET HARD
    draw_frame("S Y N C H R O N I S A T I O N")
    io.write("\x1b[10;22H\x1b[1mECRASEMENT DU CACHE LOCAL...\x1b[0m\r\n")
    io.flush()
    run_git("reset --hard HEAD")
    run_git("clean -fd " .. NOT_BASIC)
    tree_changed = true
end

-- 4. PROCEDURE DE PULL NORMALE
draw_frame("S Y N C H R O N I S A T I O N")
io.write("\x1b[10;17H\x1b[7m TELECHARGEMENT DES NOUVELLES DONNEES... \x1b[0m\r\n")
io.flush()
minitel.play_sound("pickup")

local pull_ok, pull_err = run_git("pull")
restore_basic()

if not pull_ok then
    show_error(pull_err)
    back_to_menu()
end

-- 5. Meme commit qu'avant et arbre intact : inutile de redemarrer
if git_line("rev-parse HEAD") == head_before and not tree_changed then
    show_up_to_date()
end

-- 6. AFFICHAGE DU SUCCES
draw_frame("M I S E   A   J O U R   R E U S S I E")
io.write("\x1b[10;15H\x1b[1mDERNIERE VERSION SYNCHRONISEE :\x1b[0m\r\n")
show_commit_info(12)
if #basic_saved > 0 then
    io.write(string.format("\x1b[16;15H PROGRAMMES BASIC LOCAUX CONSERVES : %d\r\n", #basic_saved))
end

minitel.play_sound("win")
io.write("\x1b[22;11H==========================================================\r\n")
io.write("\x1b[23;17H\x1b[7m SYNCHRONISATION TERMINEE - REDEMARRAGE... \x1b[0m")
io.flush()

minitel.sleep(4.5)
minitel.cleanup()

-- Reboot agressif pour recharger le master.lua
os.execute("touch /tmp/minitel_warmboot")
os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
os.execute("killall -9 lua5.3 2>/dev/null")
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")
