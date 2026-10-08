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
-- SEQUENCE DE MISE A JOUR INTELLIGENTE
-- =====================================================================

draw_frame("3 6 1 5   M I S E   A   J O U R")
io.write("\x1b[10;22H\x1b[1mVERIFICATION DU SYSTEME LOCAL...\x1b[0m\r\n")
io.flush()
minitel.play_sound("hit")

-- SAUVEGARDE GLOBALE EN ARRIERE-PLAN (Ceinture de securite)
os.execute("mkdir -p /home/minitel/minitel_gc_backup/utils/prog_basic_backup >/dev/null 2>&1")
os.execute("cp -R /home/minitel/minitel_gc/utils/prog_basic/* /home/minitel/minitel_gc_backup/utils/prog_basic_backup/ >/dev/null 2>&1")

minitel.sleep(0.5)

-- 1. On verifie s'il y a des modifications locales
local is_clean, status_out = run_git("status --porcelain")

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
    
    local choice = ""
    while true do
        local k = minitel.get_key()
        if k == "1" or k == "2" or k == "3" or k == "4" or k == "ESC" or k == "RETOUR" then
            choice = k
            break
        end
        minitel.sleep(0.05)
    end
    
    if choice == "4" or choice == "ESC" or choice == "RETOUR" then
        minitel.cleanup()
        os.execute("touch /tmp/minitel_warmboot")
        os.exit()
        
    elseif choice == "2" then
        -- PROCEDURE DE PUSH
        draw_frame("E N V O I   V E R S   L E   S E R V E U R")
        io.write("\x1b[10;13H MESSAGE DE COMMIT :\r\n")
        io.write("\x1b[12;13H > \x1b[7m                                     \x1b[0m")
        io.write("\x1b[12;16H")
        
        local msg = prompt_input("")
        if msg == "ABORT" or msg == "" then msg = "Modification locale depuis le Minitel" end
        
        io.write("\x1b[15;13H\x1b[1mPREPARATION DES DONNEES...\x1b[0m\x1b[K")
        io.flush()
        run_git("add .")
        run_git('commit -m "' .. msg .. '"')
        
        io.write("\x1b[15;13H\x1b[1mENVOI SUR LE DEPOT DISTANT...\x1b[0m\x1b[K")
        io.flush()
        local push_ok, push_err = run_git("push")
        
        if not push_ok then
            show_error(push_err)
            minitel.cleanup()
            os.execute("touch /tmp/minitel_warmboot")
            os.exit()
        end
        
        minitel.play_sound("win")
        draw_frame("P U S H   T E R M I N E")
        io.write("\x1b[12;17H\x1b[1mVOS FICHIERS ONT ETE ENVOYES AVEC SUCCES.\x1b[0m\r\n")
        io.write("\x1b[23;20H\x1b[7m APPUYEZ SUR ENVOI POUR CONTINUER \x1b[0m")
        io.flush()
        while minitel.get_key() ~= "ENVOI" and minitel.get_key() ~= "\r" do minitel.sleep(0.05) end
        
        minitel.cleanup()
        os.execute("touch /tmp/minitel_warmboot")
        os.exit()
        
    elseif choice == "3" then
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
                os.execute("mv '" .. file .. "' '" .. new_name .. "' 2>/dev/null")
            end
        end
        -- On restaure l'arbre pour que git pull puisse ramener les originaux
        run_git("reset --hard HEAD")
        
    elseif choice == "1" then
        -- PROCEDURE DE RESET HARD
        draw_frame("S Y N C H R O N I S A T I O N")
        io.write("\x1b[10;22H\x1b[1mECRASEMENT DU CACHE LOCAL...\x1b[0m\r\n")
        io.flush()
        run_git("reset --hard HEAD")
        run_git("clean -fd")
    end
end

-- 2. PROCEDURE DE PULL NORMALE
draw_frame("S Y N C H R O N I S A T I O N")
io.write("\x1b[10;17H\x1b[7m TELECHARGEMENT DES NOUVELLES DONNEES... \x1b[0m\r\n")
io.flush()
minitel.play_sound("pickup")

local pull_ok, pull_err = run_git("pull")

if not pull_ok then
    show_error(pull_err)
    minitel.cleanup()
    os.execute("touch /tmp/minitel_warmboot")
    os.exit()
end

-- 3. AFFICHAGE DU SUCCES
local commit_info = get_latest_commit()

draw_frame("M I S E   A   J O U R   R E U S S I E")
if commit_info then
    io.write("\x1b[10;15H\x1b[1mDERNIERE VERSION SYNCHRONISEE :\x1b[0m\r\n")
    io.write("\x1b[12;15H COMMIT  : " .. commit_info.hash .. "\r\n")
    io.write("\x1b[13;15H AUTEUR  : " .. commit_info.author .. "\r\n")
    io.write("\x1b[14;15H MESSAGE : " .. commit_info.msg .. "\r\n")
end

minitel.play_sound("win")
io.write("\x1b[22;11H==========================================================\r\n")
io.write("\x1b[23;17H\x1b[7m SYNCHRONISATION TERMINEE - REDEMARRAGE... \x1b[0m")
io.flush()

minitel.sleep(4.5)
minitel.cleanup()

-- Reboot agressif pour recharger le master.lua
os.execute("stty -F /dev/ttyUSB0 sane 2>/dev/null")
os.execute("killall -9 lua5.3 2>/dev/null")
os.execute("sudo systemctl restart serial-getty@ttyUSB0.service 2>/dev/null")