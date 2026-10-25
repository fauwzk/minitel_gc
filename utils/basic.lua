-- @TYPE: DEVELOPPEMENT / EXEC
-- @DESC: Interpreteur BASIC V6.1 avec GPIO, generateur PWM (0-100%), Frequence (Hz), lecture ADC analogique et moniteur temps reel.

local minitel = require("minitel")
minitel.init()

os.execute("stty raw -echo -icanon min 0 time 0 2>/dev/null")
os.execute("mkdir -p utils/prog_basic")

local program = {}
local vars = {}
local current_filename = nil
local is_modified = false
local key_buffer = nil
local expr_error = false -- Leve par eval_expr quand une expression est invalide

-- =====================================================================
-- 1. PILOTE MATERIEL GPIO, PWM, FREQUENCE & ADC (RASPBERRY PI)
-- =====================================================================
-- Broches protegees : GPIO 14 (UART TX) et GPIO 15 (UART RX) pour le Minitel
local PROTECTED_PINS = { [14] = true, [15] = true }
local pin_states = {}
local pin_modes  = {}
local pwm_duties = {} -- Stocke le % PWM actif par broche
local pwm_freqs  = {} -- Stocke la frequence Hz par broche
local sim_adc    = { [0] = 512, [1] = 256, [2] = 0, [3] = 1023 }

local function detect_gpio_backend()
    local f1 = io.popen("which pinctrl 2>/dev/null")
    if f1 then
        local r = f1:read("*l"); f1:close()
        if r and r ~= "" then return "pinctrl" end
    end
    local f2 = io.popen("which raspi-gpio 2>/dev/null")
    if f2 then
        local r = f2:read("*l"); f2:close()
        if r and r ~= "" then return "raspi-gpio" end
    end
    return "sysfs"
end

local function detect_pigpio()
    local f = io.popen("pigs t 2>/dev/null")
    if f then
        local r = f:read("*l"); f:close()
        if r and tonumber(r) then return true end
    end
    return false
end

local GPIO_BACKEND = detect_gpio_backend()
local HAS_PIGPIO   = detect_pigpio()
local sysfs_exported = {}

local function sysfs_ensure_export(pin)
    if sysfs_exported[pin] then return end
    local check = io.open("/sys/class/gpio/gpio" .. pin .. "/value", "r")
    if check then
        check:close()
        sysfs_exported[pin] = true
        return
    end
    local f = io.open("/sys/class/gpio/export", "w")
    if f then
        f:write(tostring(pin))
        f:close()
        minitel.sleep(0.03)
    end
    sysfs_exported[pin] = true
end

-- Arrete proprement tout oscillateur PWM logiciel sur une broche
local function stop_pin_pwm(pin)
    pwm_duties[pin] = nil
    pwm_freqs[pin]  = nil
    local pid_file = "/tmp/minitel_pwm_" .. pin .. ".pid"
    local f = io.open(pid_file, "r")
    if f then
        local pid = f:read("*l")
        f:close()
        if pid and pid ~= "" then
            os.execute("kill -9 " .. pid .. " 2>/dev/null")
        end
        os.remove(pid_file)
    end
    if HAS_PIGPIO then
        os.execute(string.format("pigs p %d 0 2>/dev/null", pin))
    end
end

local function stop_all_pwm()
    for p = 2, 27 do
        if pwm_duties[p] or pwm_freqs[p] then
            stop_pin_pwm(p)
        end
    end
    os.execute("rm -f /tmp/minitel_pwm_*.pid 2>/dev/null")
end

local function gpio_mode(pin, mode_str)
    pin = math.floor(tonumber(pin) or -1)
    if pin < 2 or pin > 27 or PROTECTED_PINS[pin] then return false end
    stop_pin_pwm(pin)

    local m = tostring(mode_str):upper()
    local is_out = (m == "1" or m == "OUT" or m == "OUTPUT")
    local is_pu  = (m == "2" or m == "PU"  or m == "PULLUP")
    local is_pd  = (m == "3" or m == "PD"  or m == "PULLDOWN")

    pin_modes[pin] = is_out and "OUT" or "IN"

    if GPIO_BACKEND == "pinctrl" then
        local mode_arg = is_out and "op" or (is_pu and "ip pu" or (is_pd and "ip pd" or "ip pn"))
        os.execute(string.format("pinctrl set %d %s >/dev/null 2>&1", pin, mode_arg))
    elseif GPIO_BACKEND == "raspi-gpio" then
        local mode_arg = is_out and "op" or (is_pu and "ip pu" or (is_pd and "ip pd" or "ip pn"))
        os.execute(string.format("raspi-gpio set %d %s >/dev/null 2>&1", pin, mode_arg))
    else
        sysfs_ensure_export(pin)
        local f = io.open("/sys/class/gpio/gpio" .. pin .. "/direction", "w")
        if f then f:write(is_out and "out" or "in"); f:close() end
    end
    return true
end

local function gpio_write(pin, val)
    pin = math.floor(tonumber(pin) or -1)
    if pin < 2 or pin > 27 or PROTECTED_PINS[pin] then return false end
    stop_pin_pwm(pin)

    local high = (tonumber(val) or 0) ~= 0
    pin_states[pin] = high and 1 or 0

    if pin_modes[pin] ~= "OUT" then gpio_mode(pin, "OUT") end

    if GPIO_BACKEND == "pinctrl" then
        os.execute(string.format("pinctrl set %d op %s >/dev/null 2>&1", pin, high and "dh" or "dl"))
    elseif GPIO_BACKEND == "raspi-gpio" then
        os.execute(string.format("raspi-gpio set %d op %s >/dev/null 2>&1", pin, high and "dh" or "dl"))
    else
        sysfs_ensure_export(pin)
        local f = io.open("/sys/class/gpio/gpio" .. pin .. "/value", "w")
        if f then f:write(high and "1" or "0"); f:close() end
    end
    return true
end

local function gpio_read(pin)
    pin = math.floor(tonumber(pin) or -1)
    if pin < 0 or pin > 27 then return 0 end

    if GPIO_BACKEND == "pinctrl" then
        local f = io.popen(string.format("pinctrl get %d 2>/dev/null", pin))
        if f then
            local out = f:read("*a") or ""; f:close()
            return out:find("| hi") and 1 or 0
        end
    elseif GPIO_BACKEND == "raspi-gpio" then
        local f = io.popen(string.format("raspi-gpio get %d 2>/dev/null", pin))
        if f then
            local out = f:read("*a") or ""; f:close()
            return tonumber(out:match("level=(%d)")) or 0
        end
    else
        sysfs_ensure_export(pin)
        local f = io.open("/sys/class/gpio/gpio" .. pin .. "/value", "r")
        if f then
            local v = f:read("*l"); f:close()
            return tonumber(v) or 0
        end
    end
    return 0
end

-- Demarre un signal PWM (duty = 0..100%) et/ou une frequence en Hz sur une broche
local function gpio_pwm(pin, duty_pct, freq_hz)
    pin = math.floor(tonumber(pin) or -1)
    if pin < 2 or pin > 27 or PROTECTED_PINS[pin] then return false end

    duty_pct = math.max(0, math.min(100, tonumber(duty_pct) or 0))
    freq_hz  = math.max(1, math.min(2000, tonumber(freq_hz) or 100))

    stop_pin_pwm(pin)

    if duty_pct <= 0 then
        gpio_write(pin, 0)
        return true
    elseif duty_pct >= 100 then
        gpio_write(pin, 1)
        pwm_duties[pin] = 100
        return true
    end

    pwm_duties[pin] = math.floor(duty_pct)
    pwm_freqs[pin]  = math.floor(freq_hz)

    -- 1. Si le demon DMA pigpiod est actif, on l'utilise (precision microseconde !)
    if HAS_PIGPIO then
        local duty_255 = math.floor((duty_pct / 100.0) * 255)
        os.execute(string.format("pigs pfs %d %d >/dev/null 2>&1 && pigs p %d %d >/dev/null 2>&1",
            pin, math.floor(freq_hz), pin, duty_255))
        return true
    end

    -- 2. Sinon, oscillateur PWM logiciel en tache de fond autonome
    gpio_mode(pin, "OUT")
    local period = 1.0 / freq_hz
    local t_on   = string.format("%.4f", period * (duty_pct / 100.0))
    local t_off  = string.format("%.4f", period * (1.0 - duty_pct / 100.0))
    local pid_file = "/tmp/minitel_pwm_" .. pin .. ".pid"

    local set_hi, set_lo
    if GPIO_BACKEND == "pinctrl" then
        set_hi = string.format("pinctrl set %d op dh", pin)
        set_lo = string.format("pinctrl set %d op dl", pin)
    elseif GPIO_BACKEND == "raspi-gpio" then
        set_hi = string.format("raspi-gpio set %d op dh", pin)
        set_lo = string.format("raspi-gpio set %d op dl", pin)
    else
        sysfs_ensure_export(pin)
        set_hi = string.format("echo 1 > /sys/class/gpio/gpio%d/value", pin)
        set_lo = string.format("echo 0 > /sys/class/gpio/gpio%d/value", pin)
    end

    local cmd = string.format(
        "(while true; do %s; sleep %s; %s; sleep %s; done) >/dev/null 2>&1 & echo $! > %s",
        set_hi, t_on, set_lo, t_off, pid_file
    )
    os.execute(cmd)
    return true
end

-- Lecture Analogique ADC (Canal 0 a 7) :
-- 1. Tente de lire un vrai ADC I2C/SPI via Linux IIO (/sys/bus/iio/devices/iio:device0/in_voltageX_raw)
-- 2. Sinon tente de lire /tmp/adcX (injectable par un script externe / ESP32)
-- 3. Sinon renvoie la valeur d'emulation SETADC
local function adc_read(chan)
    chan = math.floor(tonumber(chan) or 0)
    local iio_path = string.format("/sys/bus/iio/devices/iio:device0/in_voltage%d_raw", chan)
    local f1 = io.open(iio_path, "r")
    if f1 then
        local v = tonumber(f1:read("*l") or "0")
        f1:close()
        if v then return v end
    end

    local tmp_path = string.format("/tmp/adc%d", chan)
    local f2 = io.open(tmp_path, "r")
    if f2 then
        local v = tonumber(f2:read("*l") or "0")
        f2:close()
        if v then return v end
    end

    return sim_adc[chan] or 0
end

local function read_cpu_temp()
    local f = io.open("/sys/class/thermal/thermal_zone0/temp", "r")
    if f then
        local raw = tonumber(f:read("*l") or "0") or 0
        f:close()
        return math.floor((raw / 100.0) + 0.5) / 10.0
    end
    return 0
end

local function check_break()
    local k = minitel.get_key()
    if k then
        if k == "RETOUR" or k == "ESC" then return true end
        key_buffer = k
    end
    return false
end

-- =====================================================================
-- 2. EVALUATEUR MATHEMATIQUE & ENTREES (IN / ADC / TEMP / MKEY)
-- =====================================================================
-- Affichage a la BASIC : 4/2 affiche 2 et non 2.0
local function fmt_num(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return tostring(v)
end

-- Fonctions accessibles depuis les expressions (V = table des variables,
-- mise a jour avant chaque calcul car NEW et LOAD la remplacent)
local expr_env = {
    rnd = function(max) return math.random(1, math.floor(max or 10)) end,
    gpio_in = function(pin) return gpio_read(pin) end,
    adc_in  = function(ch)  return adc_read(ch) end,
    cpu_temp = function() return read_cpu_temp() end,
    mkey = function()
        local k = key_buffer
        key_buffer = nil
        if not k then k = minitel.get_key() end
        if not k then return 0 end
        if k == "UP" or k == "Z" or k == "z" then return 200 end
        if k == "DOWN" or k == "S" or k == "s" then return 201 end
        if k == "LEFT" or k == "Q" or k == "q" then return 202 end
        if k == "RIGHT" or k == "D" or k == "d" then return 203 end
        if k == "ENVOI" or k == "\r" or k == "\n" then return 13 end
        if k == "RETOUR" or k == "ESC" then return 27 end
        return string.byte(k) or 0
    end,
    sin = math.sin, cos = math.cos, tan = math.tan,
    abs = math.abs, sqr = math.sqrt, int = math.floor,
    pi = math.pi, exp = math.exp, log = math.log
}

local EXPR_RESERVED = {
    AND=1, OR=1, NOT=1, RND=1, MKEY=1,
    SIN=1, COS=1, TAN=1, ABS=1, SQR=1, INT=1, PI=1, EXP=1, LOG=1
}

-- Traduit une expression BASIC en fonction Lua. La traduction n'a lieu qu'une
-- fois par texte d'expression : une boucle reutilise la fonction deja compilee.
local function compile_expr(expr)
    local e = string.upper(expr)

    -- Support sans parentheses pour le clavier Minitel :
    -- Ex: "IN 27" -> "IN(27)", "ADC 0" -> "ADC(0)", "ANALOG 1" -> "ADC(1)"
    e = e:gsub("%f[%a]IN%s+(%d+)", "IN(%1)")
    e = e:gsub("%f[%a]PEEK%s+(%d+)", "PEEK(%1)")
    e = e:gsub("%f[%a]ADC%s+(%d+)", "ADC(%1)")
    e = e:gsub("%f[%a]ANALOG%s+(%d+)", "ADC(%1)")
    e = e:gsub("%f[%a]RND%s+(%d+)", "RND(%1)")
    -- "MKEY" et "MKEY()" donnent tous deux un appel de fonction (idem pour TEMP)
    e = e:gsub("%f[%a]MKEY%f[%A]%s*(%(?)", function(paren)
        if paren == "(" then return "MKEY(" end
        return "MKEY() "
    end)
    e = e:gsub("%f[%a]TEMP%f[%A]%s*(%(?)", function(paren)
        if paren == "(" then return "TEMP(" end
        return "TEMP() "
    end)

    -- Les operateurs a deux caracteres sont mis de cote avant de doubler les "=" isoles
    e = e:gsub("<>", "\1"):gsub("~=", "\1"):gsub("<=", "\2"):gsub(">=", "\3"):gsub("==", "\4")
    e = e:gsub("=", "==")
    e = e:gsub("\1", "~="):gsub("\2", "<="):gsub("\3", ">="):gsub("\4", "==")

    e = string.gsub(e, "%a+", function(w)
        if w == "EQ" then return "==" end
        if w == "NEQ" then return "~=" end
        if w == "LT" then return "<" end
        if w == "GT" then return ">" end
        if w == "LE" then return "<=" end
        if w == "GE" then return ">=" end
        if w == "PLUS" or w == "FOIS" then return (w == "PLUS" and "+" or "*") end
        if w == "MINUS" or w == "MOINS" then return "-" end
        if w == "MUL" then return "*" end
        if w == "DIV" then return "/" end
        if w == "MOD" then return "%" end
        if w == "IN" or w == "PEEK" then return "gpio_in" end
        if w == "ADC" or w == "ANALOG" then return "adc_in" end
        if w == "TEMP" then return "cpu_temp" end
        if EXPR_RESERVED[w] then return string.lower(w) end
        -- Variable : lue a l'execution (0 si elle n'existe pas encore)
        return "(V." .. w .. " or 0)"
    end)

    return load("return " .. e, "eval", "t", expr_env) or false
end

local expr_cache = {}

local function eval_expr(expr)
    local func = expr_cache[expr]
    if func == nil then
        func = compile_expr(expr)
        expr_cache[expr] = func
    end
    if func then
        expr_env.V = vars
        local ok, val = pcall(func)
        if ok then
            if type(val) == "boolean" then return val and 1 or 0 end
            if type(val) == "number" then return val end
        end
    end
    expr_error = true
    return 0
end

-- =====================================================================
-- 3. LECTURE DU CLAVIER (AVEC GESTION DE CURSEUR ET EDITION)
-- =====================================================================
local function input_string(prompt, initial_text)
    io.write(prompt)
    local str = initial_text or ""
    if str ~= "" then io.write(str) end
    io.flush()

    local pos = #str

    while true do
        local k = minitel.get_key()
        if k then
            if k == "ENVOI" or k == "\n" or k == "\r" then
                io.write("\r\n")
                io.flush()
                return string.upper(str)
            elseif k == "RETOUR" or k == "ESC" then
                return "ABORT", str == ""
            elseif k == "LEFT" then
                if pos > 0 then
                    pos = pos - 1
                    io.write("\x1b[D")
                    io.flush()
                end
            elseif k == "RIGHT" then
                if pos < #str then
                    pos = pos + 1
                    io.write("\x1b[C")
                    io.flush()
                end
            elseif k == "ANNULATION" then
                if #str > 0 then
                    io.write(string.rep("\x1b[D", pos) .. string.rep(" ", #str) .. string.rep("\x1b[D", #str))
                    str = ""
                    pos = 0
                    io.flush()
                end
            elseif k == "CORRECTION" or k == "\x08" or k == "\x7f" then
                if pos > 0 then
                    local left = string.sub(str, 1, pos - 1)
                    local right = string.sub(str, pos + 1)
                    str = left .. right
                    pos = pos - 1
                    if #right > 0 then
                        io.write("\x1b[D" .. right .. " \x1b[" .. (#right + 1) .. "D")
                    else
                        io.write("\x1b[D \x1b[D")
                    end
                    io.flush()
                end
            elseif string.match(k, "^[%w%s%p]$") and #k == 1 then
                k = string.upper(k)
                local left = string.sub(str, 1, pos)
                local right = string.sub(str, pos + 1)
                str = left .. k .. right
                pos = pos + 1
                if #right > 0 then
                    io.write(k .. right .. "\x1b[" .. #right .. "D")
                else
                    io.write(k)
                end
                io.flush()
            end
        end
        minitel.sleep(0.01)
    end
end

-- =====================================================================
-- 4. MISE A JOUR DE L'INTERFACE & MONITEUR GPIO / PWM / ADC ('GPIOMON')
-- =====================================================================
local function update_ui()
    io.write("\x1b7\x1b[s")
    io.write("\x1b[3;24r")
    io.write("\x1b[1;1H\x1b[7m MICRO-BASIC TELETEL V6.1 (GPIO/PWM/ADC)   [EXIT] OU [RETOUR] QUITTER \x1b[K\x1b[0m")
    local count = 0
    for _ in pairs(program) do count = count + 1 end
    local fname = current_filename or "SANS NOM"
    local mod_star = is_modified and "*" or ""
    local status_text = string.format(" LIGNES:%03d | FICHIER:%s%s | PILOTE:%s | 'HELP' / 'GPIOMON' ",
        count, fname, mod_star, GPIO_BACKEND:upper())
    io.write("\x1b[2;1H\x1b[7m" .. minitel.pad(status_text, 80) .. "\x1b[0m")
    io.write("\x1b8\x1b[u")
    io.flush()
end

-- =====================================================================
-- 4 BIS. ECRAN VIRTUEL DES PROGRAMMES (AFFICHAGE DIFFERENTIEL)
-- =====================================================================
-- Pendant un RUN, des que le programme fait CLS ou LOCATE, ses affichages
-- sont ecrits dans un ecran virtuel. present() n'envoie ensuite au Minitel
-- que les caracteres qui ont reellement change : un programme qui efface et
-- redessine tout a chaque image (CLS ... PAUSE ... GOTO) ne fait plus
-- clignoter l'ecran, et la liaison a 9600 bauds n'est plus saturee.
-- L'image est envoyee a chaque CLS (l'image precedente est alors complete),
-- PAUSE, INPUT, fin de programme, et environ toutes les 50 ms de calcul.
local scr_running = false   -- true pendant RUN
local scr_active = false    -- true quand l'ecran virtuel a pris le relais
local want, shown = {}, {}  -- cellules voulues / affichees (nil = inconnue)
local vx, vy, vinv, vwrap = 1, 3, false, false
local px, py, pinv          -- curseur et attribut reels du Minitel
local present_count, present_clock = 0, 0
local dirty = {}             -- lignes de want modifiees depuis le dernier envoi

local function cell(c) return vinv and ("!" .. c) or c end

local function scr_activate()
    if scr_active then return end
    scr_active = true
    want, shown = {}, {}
    for r = 1, 24 do want[r], shown[r] = {}, {} end
    dirty = {}
    px, py, pinv = nil, nil, nil
end

local function present(avec_curseur)
    if not scr_active then return end
    present_count, present_clock = 0, os.clock()
    -- Beaucoup de cases a effacer : un effacement materiel coute moins cher
    local blanks = 0
    for r = 3, 24 do
        if dirty[r] then
            local w, s = want[r], shown[r]
            for c = 1, 80 do
                if w[c] == " " and s[c] ~= " " then blanks = blanks + 1 end
            end
        end
    end
    if blanks > 160 then
        io.write("\x1b[0m\x1b[3;1H\x1b[J")
        pinv, py, px = false, nil, nil
        for r = 3, 24 do
            for c = 1, 80 do shown[r][c] = " " end
            dirty[r] = true
        end
    end

    local out = {}
    for r = 1, 24 do
      if dirty[r] then
        dirty[r] = nil
        local w, s = want[r], shown[r]
        local c = 1
        while c <= 80 do
            if w[c] ~= nil and w[c] ~= s[c] then
                out[#out + 1] = "\x1b[" .. r .. ";" .. c .. "H"
                while c <= 80 and w[c] ~= nil do
                    if w[c] == s[c] then
                        -- On enjambe quelques cases identiques plutot que de
                        -- repositionner le curseur (7 octets)
                        local nxt = c
                        while nxt <= 80 and nxt < c + 5 and w[nxt] ~= nil and w[nxt] == s[nxt] do nxt = nxt + 1 end
                        if nxt > 80 or nxt >= c + 5 or w[nxt] == nil then break end
                    end
                    local inv = #w[c] == 2
                    if inv ~= pinv then out[#out + 1] = inv and "\x1b[7m" or "\x1b[0m"; pinv = inv end
                    out[#out + 1] = string.sub(w[c], -1)
                    s[c] = w[c]
                    c = c + 1
                end
                py, px = r, nil -- le curseur reel est reste sur cette ligne
            else
                c = c + 1
            end
        end
      end
    end

    -- Le curseur n'est replace qu'avant un INPUT et en fin de programme :
    -- chaque trace le repositionne de toute facon
    if avec_curseur then
        local cx = vwrap and 80 or vx
        if py ~= vy or px ~= cx then out[#out + 1] = "\x1b[" .. vy .. ";" .. cx .. "H"; py, px = vy, cx end
        if pinv ~= vinv then out[#out + 1] = vinv and "\x1b[7m" or "\x1b[0m"; pinv = vinv end
    end
    if #out > 0 then io.write(table.concat(out)); io.flush() end
end

-- Saut de ligne ; deja_fait = le Minitel a deja fait defiler son ecran
local function scr_linefeed(deja_fait)
    if vy < 24 then vy = vy + 1; return end
    if not deja_fait then
        -- Le Minitel fait defiler lui-meme sa zone 3-24 : un simple saut de
        -- ligne depuis la ligne 24, au lieu de tout reecrire
        present()
        io.write((pinv ~= false and "\x1b[0m" or "") .. (py ~= 24 and "\x1b[24;1H" or "") .. "\n")
        pinv, py, px = false, 24, nil
    end
    for r = 3, 23 do want[r], shown[r] = want[r + 1], shown[r + 1] end
    want[24], shown[24] = {}, {}
    for c = 1, 80 do want[24][c], shown[24][c] = " ", " " end
end

-- Ecrit du texte dans l'ecran virtuel (memes regles de retour a la ligne
-- automatique que le VT100) ; deja_fait = texte deja affiche par le Minitel
local function scr_text(s, deja_fait)
    for i = 1, #s do
        local ch = string.sub(s, i, i)
        if ch == "\r" then vx, vwrap = 1, false
        elseif ch == "\n" then scr_linefeed(deja_fait)
        elseif string.byte(ch) >= 32 then
            if vwrap then vx, vwrap = 1, false; scr_linefeed(deja_fait) end
            want[vy][vx] = cell(ch)
            dirty[vy] = true
            if deja_fait then shown[vy][vx] = want[vy][vx] end
            if vx == 80 then vwrap = true else vx = vx + 1 end
        end
    end
    if deja_fait then py, px = vy, (vwrap and 80 or vx) end
end

local function scr_write(s)
    if scr_active then scr_text(s) else io.write(s) end
end

local function scr_cls()
    if not scr_running then
        io.write("\x1b[2J"); update_ui(); io.write("\x1b[3;1H"); io.flush(); return
    end
    scr_activate()
    present()
    -- Le programme avait ecrit sur les barres d'etat : on les redessine
    local touched = next(want[1]) or next(want[2])
    if touched then
        update_ui()
        want[1], shown[1], want[2], shown[2] = {}, {}, {}, {}
        pinv, py, px = false, nil, nil
    end
    for r = 3, 24 do
        local w = want[r]
        for c = 1, 80 do w[c] = " " end
        dirty[r] = true
    end
    vx, vy, vwrap = 1, 3, false
end

local function scr_locate(x, y)
    if not scr_running then io.write("\x1b[" .. y .. ";" .. x .. "H"); io.flush(); return end
    scr_activate()
    vx, vy, vwrap = x, y, false
end

local function scr_attr(inv)
    vinv = inv
    if not scr_active then io.write(inv and "\x1b[7m" or "\x1b[0m"); io.flush() end
end

-- Fin du programme : le Minitel rattrape l'ecran virtuel, on rend la main
local function scr_finish()
    present(true)
    scr_active = false
end

local MONITORED_PINS = {2, 3, 4, 17, 27, 22, 10, 9, 11, 5, 6, 13, 19, 26, 18, 23, 24, 25, 8, 7, 12, 16, 20, 21}

local function run_gpio_monitor()
    local function draw_mon_static()
        io.write("\x1b[r\x1b[2J\x1b[H")
        minitel.sleep(0.04)
        io.write("\x1b[1;1H\x1b[7m" .. minitel.center("* * *  MICRO-BASIC - MONITEUR GPIO, PWM & ENTREES ANALOGIQUES  * * *", 80) .. "\x1b[0m")
        minitel.draw_window(2, 3, 78, 19, "ETAT DES BROCHES BCM & CONVERTISSEUR ADC (PILOTE: " .. GPIO_BACKEND:upper() .. ")")
        io.write("\x1b[24;1H\x1b[7m [T] BASCULER 0/1 | [P] TESTER PWM % | [A] SIMULER ADC | [S] STOP PWM | [ESC]   \x1b[0m")
    end

    local function refresh_pins()
        for idx, pin in ipairs(MONITORED_PINS) do
            local col_group = math.floor((idx - 1) / 8)
            local row_offset = ((idx - 1) % 8)
            local x = 4 + col_group * 25
            local y = 5 + row_offset
            if row_offset >= 4 then y = y + 1 end

            local badge
            if pwm_duties[pin] then
                badge = string.format("\x1b[7m[PWM %3d%% %dHz]\x1b[0m", pwm_duties[pin], pwm_freqs[pin] or 100)
            else
                local lvl = gpio_read(pin)
                badge = (lvl == 1) and "\x1b[7m [ 1 / 3.3V ] \x1b[0m" or " [ 0 / GND  ] "
            end
            io.write(string.format("\x1b[%d;%dHGPIO %02d:%s", y, x, pin, badge))
        end

        io.write("\x1b[16;4H--------------------------------------------------------------------------")
        io.write(string.format("\x1b[17;4HCANAUX ANALOGIQUES : ADC0=\x1b[1m%04d\x1b[0m | ADC1=\x1b[1m%04d\x1b[0m | ADC2=\x1b[1m%04d\x1b[0m | ADC3=\x1b[1m%04d\x1b[0m",
            adc_read(0), adc_read(1), adc_read(2), adc_read(3)))
        io.write(string.format("\x1b[19;4HTEMP. CPU RASPBERRY PI : \x1b[1m%.1f C\x1b[0m  | UART MINITEL : GPIO 14/15 PROTEGES", read_cpu_temp()))
        io.flush()
    end

    draw_mon_static()
    refresh_pins()
    local last_t = os.time()

    while true do
        if os.time() - last_t >= 1 then
            last_t = os.time()
            refresh_pins()
        end
        local k = minitel.get_key()
        if k then
            local ku = string.upper(k)
            if k == "RETOUR" or k == "ESC" then break
            elseif k == " " then refresh_pins()
            elseif ku == "S" then
                stop_all_pwm()
                minitel.play_sound("hit")
                refresh_pins()
            elseif ku == "T" then
                local p_str = minitel.input_box("BASCULER BROCHE 0/1", "Numero BCM de la broche (ex: 17) :", "17", 4)
                local p_num = tonumber(p_str)
                if p_num and not PROTECTED_PINS[p_num] then
                    local cur = gpio_read(p_num)
                    gpio_write(p_num, (cur == 1) and 0 or 1)
                end
                draw_mon_static(); refresh_pins()
            elseif ku == "P" then
                local p_str = minitel.input_box("SIGNAL PWM SUR BROCHE", "Numero BCM de la broche (ex: 18) :", "18", 4)
                local d_str = minitel.input_box("RAPPORT CYCLIQUE PWM", "Pourcentage de 0 a 100 % :", "50", 4)
                local p_num, d_num = tonumber(p_str), tonumber(d_str)
                if p_num and d_num and not PROTECTED_PINS[p_num] then
                    gpio_pwm(p_num, d_num, 100)
                end
                draw_mon_static(); refresh_pins()
            elseif ku == "A" then
                local c_str = minitel.input_box("SIMULATION ENTREE ADC", "Canal ADC (0 a 3) :", "0", 2)
                local v_str = minitel.input_box("VALEUR ANALOGIQUE", "Valeur (ex: 0 a 1023) :", "512", 6)
                local c_num, v_num = tonumber(c_str), tonumber(v_str)
                if c_num and v_num then sim_adc[c_num] = v_num end
                draw_mon_static(); refresh_pins()
            end
        end
        minitel.sleep(0.02)
    end
end

-- =====================================================================
-- 5. MOTEUR D'EXECUTION DES LIGNES BASIC
-- =====================================================================
local function parse_two_args(str)
    local a, b = string.match(str, "^(.-)%s*,%s*(.*)$")
    if not a then
        a, b = string.match(str, "^(%S+)%s+(.+)$")
    end
    return a, b
end

-- Texte de ligne -> { ligne normalisee, commande, reste }, calcule une seule fois
local line_cache = {}

local function execute_line(raw)
    local parsed = line_cache[raw]
    if not parsed then
        local outside_quotes = string.gsub(raw, '([^"]*)', function(s) return string.upper(s) end)
        local norm = string.match(outside_quotes, "^%s*(.-)%s*$")
        local c, r = string.match(norm, "^(%a+)%s*(.*)$")
        parsed = { norm, c, r }
        line_cache[raw] = parsed
    end
    local line, cmd, rest = parsed[1], parsed[2], parsed[3]
    if line == "" then return "OK" end

    if cmd == "PRINT" then
        local content = string.match(rest, "^%s*%((.*)%)%s*$") or rest
        local idx, len = 1, #content
        while idx <= len do
            local c = string.sub(content, idx, idx)
            if c == '"' then
                local end_idx = string.find(content, '"', idx + 1)
                if end_idx then
                    scr_write(string.sub(content, idx + 1, end_idx - 1))
                    idx = end_idx + 1
                else
                    scr_write(string.sub(content, idx + 1))
                    break
                end
            elseif c == ';' then idx = idx + 1
            elseif c ~= ' ' then
                local next_semi = string.find(content, ';', idx)
                local sub_expr = next_semi and string.sub(content, idx, next_semi - 1) or string.sub(content, idx)
                idx = next_semi or (len + 1)
                if string.match(sub_expr, "%S") then
                    local v = eval_expr(sub_expr)
                    if expr_error then return "SYNTAX ERROR" end
                    scr_write(fmt_num(v))
                end
            else idx = idx + 1 end
        end
        if not string.match(content, ";%s*$") then
            scr_write("\r\n")
        end
        if not scr_active then io.flush() end
        return "OK"

    -- =================================================================
    -- COMMANDES GPIO, PWM, FREQUENCE & ADC
    -- =================================================================
    elseif cmd == "PINMODE" then
        local p_str, m_str = parse_two_args(rest)
        if not p_str or not m_str then return "SYNTAX ERROR" end
        local pin = math.floor(eval_expr(p_str))
        local m_trim = string.match(m_str, "^%s*(%S+)%s*$") or "IN"
        if m_trim ~= "IN" and m_trim ~= "OUT" and m_trim ~= "PU" and m_trim ~= "PD" then
            m_trim = tostring(math.floor(eval_expr(m_str)))
        end
        gpio_mode(pin, m_trim)
        return "OK"

    elseif cmd == "OUT" or cmd == "POKE" or cmd == "GPIOOUT" then
        local p_str, v_str = parse_two_args(rest)
        if not p_str or not v_str then return "SYNTAX ERROR" end
        gpio_write(math.floor(eval_expr(p_str)), math.floor(eval_expr(v_str)))
        return "OK"

    elseif cmd == "TOGGLE" then
        local pin = math.floor(eval_expr(rest))
        if pin >= 2 and pin <= 27 then
            local cur = pin_states[pin]
            if cur == nil then cur = gpio_read(pin) end
            gpio_write(pin, (cur == 1) and 0 or 1)
            return "OK"
        end
        return "SYNTAX ERROR"

    elseif cmd == "PULSE" then
        local p_str, d_str = parse_two_args(rest)
        if not p_str or not d_str then return "SYNTAX ERROR" end
        local pin = math.floor(eval_expr(p_str))
        local dur = tonumber(eval_expr(d_str)) or 0.2
        gpio_write(pin, 1)
        minitel.sleep(math.max(0.01, math.min(10.0, dur)))
        gpio_write(pin, 0)
        return "OK"

    elseif cmd == "PWM" then
        -- Syntaxe : PWM 18 50 (Rapport cyclique 0 a 100% a 100 Hz)
        local p_str, d_str = parse_two_args(rest)
        if not p_str or not d_str then return "SYNTAX ERROR" end
        local pin  = math.floor(eval_expr(p_str))
        local duty = tonumber(eval_expr(d_str)) or 0
        gpio_pwm(pin, duty, pwm_freqs[pin] or 100)
        return "OK"

    elseif cmd == "FREQ" then
        -- Syntaxe : FREQ 18 250 (Signal carre 50% a 250 Hz, ou FREQ 18 0 pour couper)
        local p_str, f_str = parse_two_args(rest)
        if not p_str or not f_str then return "SYNTAX ERROR" end
        local pin = math.floor(eval_expr(p_str))
        local hz  = tonumber(eval_expr(f_str)) or 0
        if hz <= 0 then
            stop_pin_pwm(pin)
            gpio_write(pin, 0)
        else
            gpio_pwm(pin, pwm_duties[pin] or 50, hz)
        end
        return "OK"

    elseif cmd == "PWMSTOP" then
        stop_all_pwm()
        return "OK"

    elseif cmd == "SETADC" then
        -- Syntaxe : SETADC 0 512 (Definit une valeur d'emulation pour ADC 0)
        local c_str, v_str = parse_two_args(rest)
        if not c_str or not v_str then return "SYNTAX ERROR" end
        local ch  = math.floor(eval_expr(c_str))
        local val = tonumber(eval_expr(v_str)) or 0
        sim_adc[ch] = val
        return "OK"

    elseif cmd == "LET" then
        local v, val = string.match(rest, "^(%a+)%s*=%s*(.*)$")
        if not v then v, val = string.match(rest, "^(%a+)%s+EQ%s+(.*)$") end
        if v then vars[v] = eval_expr(val) else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "INPUT" then
        key_buffer = nil
        local v = string.match(rest, "^(%a+)$")
        if v then
            present(true)
            local res = input_string("? ")
            if res == "ABORT" then return "BREAK" end
            -- Le Minitel a deja affiche la saisie : l'ecran virtuel la note
            if scr_active then scr_text("? " .. res .. "\r\n", true) end
            vars[v] = tonumber(res) or 0
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "GOTO" then
        local target = tonumber(eval_expr(rest))
        if target then return "GOTO", target else return "SYNTAX ERROR" end

    elseif cmd == "GOSUB" then
        local target = tonumber(eval_expr(rest))
        if target then return "GOSUB", target else return "SYNTAX ERROR" end

    elseif cmd == "RETURN" then return "RETURN"

    elseif cmd == "IF" then
        local cond, then_cmd, else_cmd = string.match(rest, "^(.-)%s+THEN%s+(.-)%s+ELSE%s+(.*)$")
        if not cond then cond, then_cmd = string.match(rest, "^(.-)%s+THEN%s+(.*)$") end
        if cond and then_cmd then
            if eval_expr(cond) ~= 0 then return execute_line(then_cmd)
            elseif else_cmd then return execute_line(else_cmd) end
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "FOR" then
        local v, start_expr, end_expr = string.match(rest, "^(%a+)%s*=%s*(.-)%s+TO%s+(.*)$")
        if not v then v, start_expr, end_expr = string.match(rest, "^(%a+)%s+EQ%s+(.-)%s+TO%s+(.*)$") end
        if v and start_expr and end_expr then
            vars[v] = eval_expr(start_expr)
            return "FOR", {var = v, limit = eval_expr(end_expr)}
        else return "SYNTAX ERROR" end

    elseif cmd == "NEXT" then
        local v = string.match(rest, "^(%a+)$")
        if v then return "NEXT", v else return "SYNTAX ERROR" end

    elseif cmd == "WHILE" then return "WHILE", eval_expr(rest) ~= 0
    elseif cmd == "WEND" then return "WEND"
    elseif cmd == "CLEAR" then
        stop_all_pwm()
        program = {}; vars = {}; current_filename = nil; is_modified = false; return "OK"
    elseif cmd == "CLS" then scr_cls(); return "OK"
    elseif cmd == "BEEP" then minitel.play_sound("hit"); return "OK"

    elseif cmd == "LOCATE" then
        local str_x, str_y = parse_two_args(rest)
        if str_x and str_y then
            local x = math.max(1, math.min(80, math.floor(eval_expr(str_x))))
            local y = math.max(1, math.min(24, math.floor(eval_expr(str_y))))
            scr_locate(x, y)
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "INVERT" then scr_attr(true); return "OK"
    elseif cmd == "NORMAL" then scr_attr(false); return "OK"
    elseif cmd == "PAUSE" then
        local sec = tonumber(eval_expr(rest))
        if sec then
            present()
            -- Les dixiemes entiers sont dormis avec "sleep" (le processeur se
            -- repose), le reste en attente active : lancer "sleep" pour une
            -- pause plus courte couterait plus cher que la pause elle-meme.
            local tenths = math.floor(math.max(0, sec) * 10)
            for i = 1, tenths do
                local k = minitel.get_key()
                if k == "RETOUR" or k == "ESC" then return "BREAK" end
                if k then key_buffer = k end
                minitel.sleep(0.1)
            end
            local t0, rest_sec = os.clock(), sec - tenths / 10
            while os.clock() - t0 < rest_sec do
                local k = minitel.get_key()
                if k == "RETOUR" or k == "ESC" then return "BREAK" end
                if k then key_buffer = k end
            end
        else return "SYNTAX ERROR" end
        return "OK"

    elseif cmd == "END" then return "END"
    elseif cmd == "STOP" then return "STOP"
    elseif cmd == "REM" then return "OK" end

    -- Affectation (X = ... ou X EQ ...), analysee une seule fois par ligne
    if parsed[4] == nil then
        local v, val = string.match(line, "^(%a+)%s*=%s*(.*)$")
        if not v then v, val = string.match(line, "^(%a+)%s+EQ%s+(.*)$") end
        parsed[4], parsed[5] = v or false, val
    end
    if parsed[4] then vars[parsed[4]] = eval_expr(parsed[5]); return "OK" end

    return "SYNTAX ERROR"
end

-- =====================================================================
-- 6. BOUCLE D'EXECUTION GLOBALE
-- =====================================================================
-- Message de l'interpreteur : l'ecran virtuel est d'abord rattrape
local function report(msg)
    scr_finish()
    io.write(msg); io.flush()
end

local run_lines

local function run_program()
    scr_running, vinv = true, false
    run_lines()
    scr_finish()
    scr_running = false
end

run_lines = function()
    local sorted_lines = {}
    for k in pairs(program) do table.insert(sorted_lines, k) end
    table.sort(sorted_lines)
    -- Numero de ligne -> position : GOTO et GOSUB trouvent leur cible d'un coup
    local line_index = {}
    for i, num in ipairs(sorted_lines) do line_index[num] = i end

    local pc = 1
    local loop_stack = {}
    local gosub_stack = {}

    while pc <= #sorted_lines do
        if check_break() then
            report("\r\n\x1b[K\x1b[7m BREAK IN " .. sorted_lines[pc] .. " \x1b[0m\r\n"); io.flush(); break
        end

        local line_num = sorted_lines[pc]
        expr_error = false
        local stat, arg = execute_line(program[line_num])
        if expr_error and stat ~= "BREAK" then stat = "SYNTAX ERROR" end

        if stat == "BREAK" then
            report("\r\n\x1b[K\x1b[7m BREAK IN " .. line_num .. " \x1b[0m\r\n"); io.flush(); break
        elseif stat == "STOP" then
            report("\r\n\x1b[K\x1b[7m PROGRAM STOPPED AT LINE " .. line_num .. " \x1b[0m\r\n"); io.flush(); break
        elseif stat == "SYNTAX ERROR" then
            report("\r\n\x1b[K SYNTAX ERROR IN " .. line_num .. "\r\n"); io.flush(); break
        elseif stat == "END" then break
        elseif stat == "GOTO" or stat == "GOSUB" then
            local target = line_index[arg]
            if target then
                if stat == "GOSUB" then table.insert(gosub_stack, pc) end
                pc = target
            else report("\r\n\x1b[K UNDEFINED LINE " .. arg .. " IN " .. line_num .. "\r\n"); io.flush(); break end
        elseif stat == "RETURN" then
            if #gosub_stack > 0 then pc = table.remove(gosub_stack) + 1
            else report("\r\n\x1b[K RETURN WITHOUT GOSUB IN " .. line_num .. "\r\n"); io.flush(); break end
        elseif stat == "FOR" then
            table.insert(loop_stack, {type="FOR", var=arg.var, limit=arg.limit, start_pc=pc}); pc = pc + 1
        elseif stat == "NEXT" then
            local top = loop_stack[#loop_stack]
            if top and top.type == "FOR" and top.var == arg then
                vars[top.var] = vars[top.var] + 1
                if vars[top.var] <= top.limit then pc = top.start_pc + 1 else table.remove(loop_stack); pc = pc + 1 end
            else report("\r\n\x1b[K NEXT WITHOUT FOR IN " .. line_num .. "\r\n"); break end
        elseif stat == "WHILE" then
            if arg then table.insert(loop_stack, {type="WHILE", start_pc=pc}); pc = pc + 1
            else
                local nest = 1; local wend_pc = pc + 1; local found = false
                while wend_pc <= #sorted_lines do
                    local wline = string.match(string.upper(program[sorted_lines[wend_pc]]), "^%s*(.-)%s*$")
                    if string.match(wline, "^WHILE") then nest = nest + 1 end
                    if string.match(wline, "^WEND") then
                        nest = nest - 1; if nest == 0 then found = true; break end
                    end
                    wend_pc = wend_pc + 1
                end
                if found then pc = wend_pc + 1 else report("\r\n\x1b[K WHILE WITHOUT WEND IN " .. line_num .. "\r\n"); break end
            end
        elseif stat == "WEND" then
            local top = loop_stack[#loop_stack]
            if top and top.type == "WHILE" then pc = top.start_pc; table.remove(loop_stack)
            else report("\r\n\x1b[K WEND WITHOUT WHILE IN " .. line_num .. "\r\n"); break end
        else pc = pc + 1 end
        -- Un programme qui calcule longtemps sans CLS ni PAUSE s'affiche quand
        -- meme : l'ecran est rattrape toutes les 50 ms environ
        present_count = present_count + 1
        if present_count >= 64 then
            present_count = 0
            if os.clock() - present_clock >= 0.05 then present() end
        end
    end
end

-- =====================================================================
-- 7. ECRAN D'AIDE COMPLET (SYSTEME, GPIO, PWM, ADC, SYNTAXE MINITEL)
-- =====================================================================
local function show_help()
    io.write("\x1b[r\x1b[2J\x1b[H")
    local help_lines = {
        "\x1b[1m === 1. COMMANDES DU SHELL ============= \x1b[0m",
        " RUN        : Execute le programme   NEW / CLEAR: Efface code + coupe PWM",
        " LIST       : Affiche le code        DIR        : Liste les fichiers .bas",
        " EDIT X     : Edite la ligne X       SAVE NOM   : Sauvegarde (sans \"\")",
        " STOP / END : Arrete l'execution     LOAD NOM   : Charge un programme",
        " GPIOMON    : Moniteur visuel temps reel (GPIO, PWM % et Canaux ADC) !",
        "",
        "\x1b[1m === 2. GPIO NUMERIQUE (BROCHES BCM) === \x1b[0m",
        " PINMODE P M: Mode de la broche P -> OUT (Sortie), IN, PU (PullUp), PD",
        "              Ex: PINMODE 17 OUT   ou   PINMODE 27 PU",
        " OUT P V    : Met la broche P a 1 (3.3V) ou 0 (GND). Alias: POKE P V",
        "              Ex: OUT 17 1   (Allume LED/Relais sur GPIO 17)",
        " TOGGLE P   : Inverse l'etat logique 0/1 de la broche P (Ex: TOGGLE 17)",
        " PULSE P D  : Impulsion a 1 sur la broche P pendant D sec (Ex: PULSE 17 0.5)",
        " IN P       : Lit l'etat (0 ou 1) de la broche P (Aussi: IN(P) ou PEEK P)",
        "              Ex: IF IN 27 EQ 0 THEN PRINT \"BOUTON PRESSE\"",
        "",
        "\x1b[1m === 3. PWM, FREQUENCE & ANALOGIQUE ==== \x1b[0m",
        " PWM P R    : Signal PWM sur broche P avec rapport cyclique R (0 a 100 %)",
        "              Ex: PWM 18 75  (Module la broche 18 a 75%) | PWM 18 0 (Stop)",
        " FREQ P HZ  : Signal carre continu sur broche P en Hertz (Compteur/Buzzer)",
        "              Ex: FREQ 18 150 (150 Hz continu) | FREQ 18 0 (Coupe signal)",
        " PWMSTOP    : Coupe immediatement tous les signaux PWM et FREQ actifs",
        " ADC C      : Lit le canal analogique C (0-7) via I2C IIO ou /tmp/adcC",
        "              Ex: V EQ ADC 0   (Aussi ecrit : V = ANALOG(0))",
        " SETADC C V : Simule la valeur V sur le canal ADC C pour tester son code",
        " TEMP       : Renvoie la temperature du processeur Raspberry Pi en C",
        "",
        "\x1b[1m === 4. SYNTAXE SANS SYMBOLES MINITEL == \x1b[0m",
        " Affectation: X EQ 10 (remplace X = 10) | FOR I EQ 1 TO 10",
        " Comparaison: EQ (=), NEQ (<>), LT (<), GT (>), LE (<=), GE (>=)",
        " Calculs    : PLUS (+), MOINS (-), FOIS ou MUL (*), DIV (/), MOD (%)",
        " Logique    : AND, OR, NOT | Conditions : IF ... THEN ... ELSE ...",
        " Boucles    : FOR..NEXT, WHILE..WEND, GOTO X, GOSUB X / RETURN",
        "",
        "\x1b[1m === 5. AFFICHAGE MINITEL & CLAVIER ==== \x1b[0m",
        " CLS        : Efface l'ecran         LOCATE X Y : Place le curseur (sans ,)",
        " INVERT/NORM: Video inverse          BEEP / PAUSE X : Bip / Pause en sec",
        " MKEY       : Code touche pressee sans bloquer (Haut:200 Bas:201 G:202 D:203)"
    }

    local offset = 1; local max_visible = 20
    local max_offset = math.max(1, #help_lines - max_visible + 1)

    local function draw_help_screen()
        io.write("\x1b[1;1H\x1b[7m MICRO-BASIC V6.1 : MANUEL COMPLET   [Z/S/FLECHES] DEFILER [RETOUR] FERMER\x1b[K\x1b[0m\r\n")
        for i = 1, max_visible do
            local line_idx = offset + i - 1
            io.write("\x1b[" .. (i + 2) .. ";1H\x1b[K")
            if help_lines[line_idx] then io.write(" " .. help_lines[line_idx]) end
        end
        io.write("\x1b[24;1H\x1b[7m LIGNE " .. string.format("%02d/%02d", offset, max_offset) .. " - UTILISEZ LES FLECHES HAUT/BAS OU [RETOUR] POUR QUITTER \x1b[K\x1b[0m")
        io.flush()
    end

    draw_help_screen()
    while true do
        local k = minitel.get_key()
        if k == "RETOUR" or k == "ESC" or k == " " or k == "ENVOI" or k == "\r" or k == "\n" then break
        elseif k == "UP" or k == "Z" or k == "z" then if offset > 1 then offset = offset - 1; draw_help_screen() end
        elseif k == "DOWN" or k == "S" or k == "s" then if offset < max_offset then offset = offset + 1; draw_help_screen() end
        end
        minitel.sleep(0.03)
    end
end

-- =====================================================================
-- 8. INVITE DE COMMANDE SHELL
-- =====================================================================
local function shell()
    io.write("\x1b[2J\x1b[H\x1b[3;24r\x1b[3;1H")
    io.write("\x1b[7m MICRO-BASIC V6.1 - GPIO / PWM / FREQ / ADC (" .. GPIO_BACKEND:upper() .. ") \x1b[0m\r\nREADY.\r\n")
    io.flush()

    while true do
        update_ui()
        local line, was_empty = input_string("\x1b[K> ")

        if line == "ABORT" and was_empty then
            -- [RETOUR] sur une invite vide quitte, apres confirmation si le programme n'est pas sauvegarde
            if not is_modified or minitel.confirm_box("QUITTER LE BASIC", "Le programme n'est pas sauvegarde. Quitter quand meme ?") then
                stop_all_pwm()
                break
            end
            io.write("\x1b[2J\x1b[3;24r\x1b[3;1HREADY.\r\n"); io.flush()
        elseif line == "ABORT" then io.write("\r\n")
        elseif line == "" then -- Rien
        elseif line == "HELP" or line == "GUIDE" then
            show_help()
            io.write("\x1b[2J\x1b[3;24r\x1b[3;1HREADY.\r\n"); io.flush()
        elseif line == "GPIOMON" then
            run_gpio_monitor()
            io.write("\x1b[2J\x1b[3;24r\x1b[3;1HREADY.\r\n"); io.flush()
        elseif line == "EXIT" or line == "QUIT" then
            stop_all_pwm()
            break
        elseif string.match(line, "^EDIT%s+(%d+)") then
            local lnum = tonumber(string.match(line, "^EDIT%s+(%d+)"))
            if program[lnum] then
                local edited = input_string("\x1b[K" .. lnum .. " ", program[lnum])
                if edited ~= "ABORT" and edited ~= "" then
                    program[lnum] = edited; is_modified = true
                elseif edited == "" then
                    program[lnum] = nil; is_modified = true
                end
            else io.write("LINE NOT FOUND\r\n"); io.flush() end
        elseif string.match(line, "^LIST") then
            local sorted_lines = {}
            for k in pairs(program) do table.insert(sorted_lines, k) end
            table.sort(sorted_lines)
            for _, l in ipairs(sorted_lines) do io.write(string.format("\x1b[1m%d\x1b[0m %s\r\n", l, program[l])) end
            io.flush()
        elseif line == "RUN" then
            -- Definir la zone de defilement ramene le curseur en haut : on le sauvegarde autour
            io.write("\x1b7\x1b[3;24r\x1b8"); run_program(); io.write("\x1b[KREADY.\r\n"); io.flush()
        elseif line == "NEW" or line == "CLEAR" then
            stop_all_pwm()
            program = {}; vars = {}; current_filename = nil; is_modified = false; io.write("READY.\r\n"); io.flush()
        elseif line == "DIR" then
            local f = io.popen("ls -1 utils/prog_basic/*.bas 2>/dev/null")
            if f then for file in f:lines() do io.write(string.gsub(file, "utils/prog_basic/", "") .. "\r\n") end; f:close() end
            io.write("READY.\r\n"); io.flush()
        elseif string.match(line, '^SAVE%s+"?(.-)"?$') then
            local filename = string.match(line, '^SAVE%s+"?(.-)"?$'):gsub("%s+$", "")
            if filename ~= "" then
                local f = io.open("utils/prog_basic/" .. filename .. ".bas", "w")
                if f then
                    local sl = {}
                    for k in pairs(program) do table.insert(sl, k) end
                    table.sort(sl)
                    for _, l in ipairs(sl) do f:write(l .. " " .. program[l] .. "\n") end
                    f:close(); current_filename = filename; is_modified = false; io.write("SAVED " .. filename .. "\r\n")
                end
            end
            io.flush()
        elseif string.match(line, '^LOAD%s+"?(.-)"?$') then
            local filename = string.match(line, '^LOAD%s+"?(.-)"?$'):gsub("%s+$", "")
            local f = io.open("utils/prog_basic/" .. filename .. ".bas", "r")
            if f then
                stop_all_pwm()
                program = {}; vars = {}
                for fline in f:lines() do
                    local lnum, rest = string.match(fline, "^(%d+)%s*(.*)$")
                    if lnum then program[tonumber(lnum)] = rest end
                end
                f:close(); current_filename = filename; is_modified = false; io.write("LOADED " .. filename .. "\r\n")
            else
                io.write("FILE NOT FOUND\r\n")
            end
            io.flush()
        else
            local lnum, rest = string.match(line, "^(%d+)%s*(.*)$")
            if lnum then
                lnum = tonumber(lnum)
                if rest == "" then program[lnum] = nil; is_modified = true
                else program[lnum] = rest; is_modified = true end
            else
                expr_error = false
                local stat, _ = execute_line(line)
                if stat == "SYNTAX ERROR" or expr_error then io.write("SYNTAX ERROR\r\n"); io.flush() end
            end
        end
    end
end

math.randomseed(os.time())
shell()
stop_all_pwm()
io.write("\x1b[r")
io.flush()
minitel.cleanup()