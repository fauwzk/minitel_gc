#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Interface web d'administration du Minitel Magis Club.

Depuis un ordinateur du reseau local : etat du Raspberry Pi, terminal dans
le navigateur, mises a jour (depot et systeme), programmes MICRO-BASIC
(editeur et execution sur le Pi) et photos de 3615 PHOTOS.

Bibliotheque standard de Python uniquement. Lance par le service systemd
minitel-web (install_web.sh), sous le compte minitel, sur le port 8080.

  python3 web/admin.py                  demarre le serveur
  python3 web/admin.py --mot-de-passe   choisit le mot de passe d'acces
  python3 web/admin.py --mot-de-passe-stdin   le meme, lu sur l'entree standard
"""

import base64
import fcntl
import getpass
import hashlib
import hmac
import json
import os
import pty
import re
import secrets
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import termios
import threading
import time
import codecs
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MINITEL_WEB_PORT", "8080"))
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATIC = os.path.join(REPO, "web", "static")
BASIC_DIR = os.path.join(REPO, "utils", "prog_basic")
PHOTO_DIR = os.path.join(REPO, "photos")
PASSWORD_FILE = os.path.expanduser(os.environ.get("MINITEL_WEB_SECRET", "~/.minitel_web"))

SESSION_HOURS = 12
MAX_UPLOAD = 25 * 1024 * 1024
PHOTO_EXT = (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,40}$")
PHOTO_RE = re.compile(r"^[A-Za-z0-9_. -]{1,80}$")

sessions = {}          # jeton -> fin de validite
failures = {}          # adresse -> (nombre d'echecs, instant du dernier)
lock = threading.Lock()


# =====================================================================
# MOT DE PASSE (PBKDF2-SHA256, HORS DU DEPOT)
# =====================================================================
def hash_password(password, salt=None, rounds=200000):
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode(), rounds).hex()
    return {"salt": salt, "rounds": rounds, "hash": digest}


def load_secret():
    try:
        with open(PASSWORD_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_password(password):
    data = hash_password(password)
    fd = os.open(PASSWORD_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)


def check_password(password):
    data = load_secret()
    if not data:
        return False
    test = hash_password(password, data["salt"], data["rounds"])["hash"]
    return hmac.compare_digest(test, data["hash"])


# =====================================================================
# OUTILS SYSTEME
# =====================================================================
def run(cmd, timeout=10, cwd=REPO):
    try:
        out = subprocess.run(cmd, shell=isinstance(cmd, str), cwd=cwd, capture_output=True,
                             text=True, timeout=timeout)
        return out.returncode, (out.stdout or "") + (out.stderr or "")
    except (subprocess.TimeoutExpired, OSError) as e:
        return 1, str(e)


def read_file(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def git(*args, timeout=20):
    return run(["git", "-c", "safe.directory=" + REPO] + list(args), timeout=timeout)


def system_info():
    info = {}
    info["modele"] = read_file("/proc/device-tree/model", "").replace("\x00", "").strip() or "?"
    info["hote"] = socket.gethostname()
    info["noyau"] = os.uname().release
    pretty = re.search(r'PRETTY_NAME="([^"]*)"', read_file("/etc/os-release"))
    info["systeme"] = pretty.group(1) if pretty else "?"
    up = float(read_file("/proc/uptime", "0").split()[0])
    info["allume_depuis"] = "%dj %02dh%02d" % (up // 86400, up % 86400 // 3600, up % 3600 // 60)
    info["charge"] = read_file("/proc/loadavg", "0 0 0").split()[:3]
    info["processeurs"] = os.cpu_count()
    temp = read_file("/sys/class/thermal/thermal_zone0/temp", "").strip()
    info["temperature"] = round(int(temp) / 1000, 1) if temp.isdigit() else None
    mem = {}
    for line in read_file("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        mem[k] = int(v.split()[0]) if v.split() else 0
    info["memoire"] = {"totale": mem.get("MemTotal", 0) // 1024, "libre": mem.get("MemAvailable", 0) // 1024}
    du = shutil.disk_usage("/")
    info["disque"] = {"total": du.total // 2**20, "utilise": du.used // 2**20}
    code, out = run(["hostname", "-I"])
    info["adresses"] = out.split() if code == 0 else []
    code, out = run(["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"])
    info["wifi"] = next((l.split(":", 1)[1] for l in out.splitlines() if l.startswith("yes:")), None) if code == 0 else None
    code, out = git("log", "-1", "--format=%h|%cd|%s", "--date=format:%d/%m/%Y %H:%M")
    if code == 0 and "|" in out:
        h, d, s = out.strip().split("|", 2)
        info["depot"] = {"commit": h, "date": d, "message": s}
    services = {}
    for name in ("serial-getty@ttyUSB0", "minitel-boot", "minitel-web", "NetworkManager"):
        code, out = run(["systemctl", "is-active", name])
        services[name] = out.strip() or "?"
    info["services"] = services
    info["outils"] = {
        "imagemagick": bool(shutil.which("convert") or shutil.which("magick")),
        "scripts_maj": os.path.exists("/usr/local/sbin/minitel-maj"),
        "maj_systeme": os.path.exists("/usr/local/sbin/minitel-systeme"),
        "minitel": os.path.exists("/dev/ttyUSB0"),
    }
    return info


def git_check():
    code, out = git("fetch", "--quiet", timeout=40)
    if code != 0:
        return {"erreur": out.strip()[-300:] or "git fetch a echoue"}
    code, out = git("log", "--format=%h|%cd|%s", "--date=format:%d/%m %H:%M", "HEAD..@{u}")
    commits = []
    for line in out.splitlines():
        if line.count("|") >= 2:
            h, d, s = line.split("|", 2)
            commits.append({"commit": h, "date": d, "message": s})
    code, status = git("status", "--porcelain")
    return {"a_venir": commits, "modifications_locales": len(status.splitlines())}


# =====================================================================
# PROGRAMMES MICRO-BASIC
# =====================================================================
def basic_list():
    os.makedirs(BASIC_DIR, exist_ok=True)
    out = []
    for name in sorted(os.listdir(BASIC_DIR)):
        if name.lower().endswith(".bas"):
            st = os.stat(os.path.join(BASIC_DIR, name))
            out.append({"nom": name[:-4], "taille": st.st_size,
                        "modifie": time.strftime("%d/%m/%Y %H:%M", time.localtime(st.st_mtime))})
    return out


def basic_path(name):
    if not NAME_RE.match(name or ""):
        return None
    return os.path.join(BASIC_DIR, name + ".bas")


def basic_normalize(text):
    """Meme format que SAVE : une ligne par instruction, triees par numero."""
    lines, errors = {}, []
    for i, raw in enumerate(text.replace("\r", "").split("\n"), 1):
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"^(\d+)\s*(.*)$", line)
        if not m:
            errors.append("ligne %d : pas de numero de ligne" % i)
            continue
        if m.group(2):
            lines[int(m.group(1))] = m.group(2)
    body = "".join("%d %s\n" % (n, lines[n]) for n in sorted(lines))
    return body, errors


# =====================================================================
# PHOTOS ET APERCU DU RENDU MINITEL
# =====================================================================
LEVELS = [(" ", False, 0.00), (".", False, 0.07), (":", False, 0.14), ("+", False, 0.24),
          ("*", False, 0.32), ("#", False, 0.45), ("#", True, 0.56), ("+", True, 0.76),
          (":", True, 0.86), (".", True, 0.93), (" ", True, 1.00)]


def photo_path(name):
    if not PHOTO_RE.match(name or "") or name.startswith(".") or not name.lower().endswith(PHOTO_EXT):
        return None
    return os.path.join(PHOTO_DIR, name)


def photo_list():
    os.makedirs(PHOTO_DIR, exist_ok=True)
    out = []
    for name in sorted(os.listdir(PHOTO_DIR)):
        if name.lower().endswith(PHOTO_EXT):
            out.append({"nom": name, "taille": os.path.getsize(os.path.join(PHOTO_DIR, name))})
    return out


def minitel_preview(path):
    """Meme conversion que utils/photos.lua : lignes de (caractere, inverse)."""
    im = shutil.which("magick") or shutil.which("convert")
    if not im:
        return None
    try:
        data = subprocess.run([im, path + "[0]", "-auto-orient", "-colorspace", "Gray", "-resize", "78x42",
                               "-resize", "100%x50%", "-depth", "8", "pgm:-"],
                              capture_output=True, timeout=30).stdout
    except (subprocess.TimeoutExpired, OSError):
        return None
    m = re.match(rb"P5\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if not m:
        return None
    w, h, maxv = int(m.group(1)), int(m.group(2)), int(m.group(3))
    px = [[data[m.end() + y * w + x] / maxv for x in range(w)] for y in range(h)]
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            v = min(1.0, max(0.0, px[y][x]))
            li = min(range(len(LEVELS)), key=lambda i: abs(LEVELS[i][2] - v))
            err = v - LEVELS[li][2]
            if x < w - 1:
                px[y][x + 1] += err * 7 / 16
            if y < h - 1:
                if x > 0:
                    px[y + 1][x - 1] += err * 3 / 16
                px[y + 1][x] += err * 5 / 16
                if x < w - 1:
                    px[y + 1][x + 1] += err / 16
            row.append([LEVELS[li][0], LEVELS[li][1]])
        rows.append(row)
    return rows


# =====================================================================
# TERMINAL : PSEUDO-TERMINAL RELIE A UNE WEBSOCKET
# =====================================================================
TERMINAL_COMMANDS = {
    "shell": (["bash", "-l"], 120, 34),
    "maj": (["lua5.3", "updater.lua"], 80, 24),
    "systeme": (["sudo", "-n", "/usr/local/sbin/minitel-systeme"], 100, 30),
    "basic": (["lua5.3", "utils/basic.lua"], 80, 24),
}


def ws_send(sock, payload, opcode=0x1):
    data = payload.encode("utf-8") if isinstance(payload, str) else payload
    head = bytes([0x80 | opcode])
    n = len(data)
    if n < 126:
        head += bytes([n])
    elif n < 65536:
        head += bytes([126]) + struct.pack(">H", n)
    else:
        head += bytes([127]) + struct.pack(">Q", n)
    sock.sendall(head + data)


def ws_recv(sock):
    def exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError
            buf += chunk
        return buf
    b1, b2 = exact(2)
    opcode, n = b1 & 0x0F, b2 & 0x7F
    if n == 126:
        n = struct.unpack(">H", exact(2))[0]
    elif n == 127:
        n = struct.unpack(">Q", exact(8))[0]
    mask = exact(4) if b2 & 0x80 else b"\0\0\0\0"
    data = bytes(c ^ mask[i % 4] for i, c in enumerate(exact(n)))
    return opcode, data


def run_terminal(sock, kind, arg):
    argv, cols, rows = TERMINAL_COMMANDS[kind]
    argv = list(argv)
    if kind == "basic" and arg:
        argv.append(arg)
    env = dict(os.environ, TERM="xterm-256color", LANG="C.UTF-8", MINITEL_PC="1",
               COLUMNS=str(cols), LINES=str(rows))
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(REPO)
        try:
            os.execvpe(argv[0], argv, env)
        finally:
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    ws_send(sock, json.dumps({"type": "taille", "cols": cols, "rows": rows}))
    alive = [True]

    def pump():
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        try:
            while alive[0]:
                r, _, _ = select.select([fd], [], [], 0.5)
                if fd in r:
                    try:
                        data = os.read(fd, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    ws_send(sock, json.dumps({"type": "sortie", "data": decoder.decode(data)}))
        finally:
            alive[0] = False
            try:
                _, status = os.waitpid(pid, 0)
                code = os.waitstatus_to_exitcode(status)
            except ChildProcessError:
                code = None
            try:
                ws_send(sock, json.dumps({"type": "fin", "code": code}))
                ws_send(sock, b"", 0x8)
            except OSError:
                pass

    t = threading.Thread(target=pump, daemon=True)
    t.start()
    try:
        while alive[0]:
            opcode, data = ws_recv(sock)
            if opcode == 0x8:
                break
            if opcode == 0x9:
                ws_send(sock, data, 0xA)
                continue
            if opcode not in (0x1, 0x2):
                continue
            msg = json.loads(data.decode("utf-8", "replace"))
            if msg.get("type") == "entree":
                os.write(fd, msg.get("data", "").encode("utf-8"))
            elif msg.get("type") == "taille" and kind == "shell":
                c, r = int(msg.get("cols", 80)), int(msg.get("rows", 24))
                fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", max(20, r), max(40, c), 0, 0))
    except (ConnectionError, OSError, ValueError):
        pass
    finally:
        if alive[0]:
            alive[0] = False
            try:
                os.kill(pid, signal.SIGHUP)
            except ProcessLookupError:
                pass
        t.join(timeout=3)
        try:
            os.close(fd)
        except OSError:
            pass


# =====================================================================
# SERVEUR HTTP
# =====================================================================
MIME = {".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png",
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".bmp": "image/bmp",
        ".webp": "image/webp", ".ico": "image/x-icon"}


class Handler(BaseHTTPRequestHandler):
    server_version = "MinitelAdmin/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    # --- reponses ---
    def send(self, code, body=b"", ctype="application/json; charset=utf-8", headers=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def error(self, code, msg):
        self.send(code, {"erreur": msg})

    # --- authentification ---
    def session_token(self):
        cookie = self.headers.get("Cookie", "")
        m = re.search(r"(?:^|;\s*)minitel_session=([A-Za-z0-9_-]+)", cookie)
        return m.group(1) if m else None

    def logged_in(self):
        tok = self.session_token()
        with lock:
            exp = sessions.get(tok)
            if exp and exp > time.time():
                return True
            sessions.pop(tok, None)
        return False

    def same_origin(self):
        """Les requetes qui modifient quelque chose doivent venir de la page
        elle-meme (en-tete ajoute par app.js) : protection contre le CSRF."""
        return self.headers.get("X-Minitel") == "1"

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_UPLOAD:
            raise ValueError("fichier trop gros (25 Mo au plus)")
        return self.rfile.read(n) if n else b""

    def json_body(self):
        try:
            return json.loads(self.body().decode("utf-8") or "{}")
        except ValueError:
            return {}

    # --- routage ---
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path.startswith("/ws/"):
            return self.websocket(path)
        if not path.startswith("/api/"):
            return self.static(path)
        if path == "/api/etat":
            return self.send(200, {"connecte": self.logged_in(), "mot_de_passe": load_secret() is not None})
        if not self.logged_in():
            return self.error(401, "connexion requise")
        if path == "/api/info":
            return self.send(200, system_info())
        if path == "/api/basic":
            return self.send(200, basic_list())
        m = re.match(r"^/api/basic/([^/]+)$", path)
        if m:
            p = basic_path(urllib.parse.unquote(m.group(1)))
            if not p or not os.path.exists(p):
                return self.error(404, "programme introuvable")
            return self.send(200, read_file(p), "text/plain; charset=utf-8")
        if path == "/api/photos":
            return self.send(200, photo_list())
        m = re.match(r"^/api/photos/([^/]+)(/minitel)?$", path)
        if m:
            p = photo_path(urllib.parse.unquote(m.group(1)))
            if not p or not os.path.exists(p):
                return self.error(404, "photo introuvable")
            if m.group(2):
                rows = minitel_preview(p)
                if rows is None:
                    return self.error(500, "ImageMagick absent ou photo illisible")
                return self.send(200, rows)
            with open(p, "rb") as f:
                return self.send(200, f.read(), MIME.get(os.path.splitext(p)[1].lower(), "application/octet-stream"))
        return self.error(404, "inconnu")

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.same_origin():
            return self.error(403, "requete refusee")
        if path == "/api/connexion":
            return self.login()
        if not self.logged_in():
            return self.error(401, "connexion requise")
        if path == "/api/deconnexion":
            with lock:
                sessions.pop(self.session_token(), None)
            return self.send(200, {"ok": True}, headers={"Set-Cookie": "minitel_session=; Path=/; Max-Age=0"})
        if path == "/api/git/verifier":
            return self.send(200, git_check())
        if path == "/api/mot-de-passe":
            data = self.json_body()
            if not check_password(data.get("ancien", "")):
                return self.error(403, "ancien mot de passe incorrect")
            new = data.get("nouveau", "")
            if len(new) < 8:
                return self.error(400, "8 caracteres au moins")
            save_password(new)
            with lock:
                sessions.clear()
            return self.send(200, {"ok": True})
        if path == "/api/redemarrer":
            subprocess.Popen(["sudo", "-n", "/usr/sbin/reboot"])
            return self.send(200, {"ok": True})
        return self.error(404, "inconnu")

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.same_origin():
            return self.error(403, "requete refusee")
        if not self.logged_in():
            return self.error(401, "connexion requise")
        try:
            raw = self.body()
        except ValueError as e:
            return self.error(413, str(e))
        m = re.match(r"^/api/basic/([^/]+)$", path)
        if m:
            p = basic_path(urllib.parse.unquote(m.group(1)))
            if not p:
                return self.error(400, "nom invalide : lettres, chiffres, - et _ (40 au plus)")
            text, errors = basic_normalize(raw.decode("utf-8", "replace"))
            if errors:
                return self.error(400, "; ".join(errors[:5]))
            os.makedirs(BASIC_DIR, exist_ok=True)
            with open(p, "w") as f:
                f.write(text)
            return self.send(200, {"ok": True, "texte": text})
        m = re.match(r"^/api/photos/([^/]+)$", path)
        if m:
            p = photo_path(urllib.parse.unquote(m.group(1)))
            if not p:
                return self.error(400, "nom ou type de fichier refuse (JPEG, PNG, GIF, BMP, WebP)")
            os.makedirs(PHOTO_DIR, exist_ok=True)
            with open(p + ".part", "wb") as f:
                f.write(raw)
            os.replace(p + ".part", p)
            return self.send(200, {"ok": True})
        return self.error(404, "inconnu")

    def do_DELETE(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.same_origin():
            return self.error(403, "requete refusee")
        if not self.logged_in():
            return self.error(401, "connexion requise")
        m = re.match(r"^/api/(basic|photos)/([^/]+)$", path)
        if m:
            name = urllib.parse.unquote(m.group(2))
            p = basic_path(name) if m.group(1) == "basic" else photo_path(name)
            if not p or not os.path.exists(p):
                return self.error(404, "introuvable")
            os.remove(p)
            return self.send(200, {"ok": True})
        return self.error(404, "inconnu")

    def login(self):
        ip = self.client_address[0]
        with lock:
            count, last = failures.get(ip, (0, 0))
            if count >= 5 and time.time() - last < 60:
                return self.error(429, "trop d'essais : attendez une minute")
        if load_secret() is None:
            return self.error(403, "aucun mot de passe : sudo -u minitel python3 web/admin.py --mot-de-passe")
        if not check_password(self.json_body().get("mot_de_passe", "")):
            with lock:
                failures[ip] = (count + 1, time.time())
            time.sleep(1)
            return self.error(403, "mot de passe incorrect")
        tok = secrets.token_urlsafe(32)
        with lock:
            failures.pop(ip, None)
            sessions[tok] = time.time() + SESSION_HOURS * 3600
        cookie = "minitel_session=%s; Path=/; HttpOnly; SameSite=Strict; Max-Age=%d" % (tok, SESSION_HOURS * 3600)
        return self.send(200, {"ok": True}, headers={"Set-Cookie": cookie})

    def static(self, path):
        if path == "/":
            path = "/index.html"
        full = os.path.normpath(os.path.join(STATIC, path.lstrip("/")))
        if not full.startswith(STATIC + os.sep) or not os.path.isfile(full):
            return self.error(404, "page introuvable")
        with open(full, "rb") as f:
            self.send(200, f.read(), MIME.get(os.path.splitext(full)[1], "application/octet-stream"))

    def websocket(self, path):
        m = re.match(r"^/ws/terminal/(shell|maj|systeme|basic)(?:/([A-Za-z0-9_-]{1,40}))?$", path)
        origin = self.headers.get("Origin", "")
        host = self.headers.get("Host", "")
        if not m or not self.logged_in() or urllib.parse.urlparse(origin).netloc != host:
            return self.error(403, "terminal refuse")
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.wfile.flush()
        run_terminal(self.connection, m.group(1), m.group(2))
        self.close_connection = True


def main():
    if "--mot-de-passe-stdin" in sys.argv:
        # mot de passe lu sur l'entree standard (script de mise a jour)
        pw = sys.stdin.readline().rstrip("\r\n")
        if len(pw) < 8:
            print("Mot de passe trop court (8 caracteres au moins) : rien n'a change.", file=sys.stderr)
            sys.exit(1)
        save_password(pw)
        print("Mot de passe enregistre dans", PASSWORD_FILE)
        return
    if "--mot-de-passe" in sys.argv:
        while True:
            a = getpass.getpass("Nouveau mot de passe de l'interface web (8 caracteres au moins) : ")
            if len(a) < 8:
                print("Trop court.")
                continue
            if getpass.getpass("Encore une fois : ") != a:
                print("Les deux saisies different.")
                continue
            save_password(a)
            print("Mot de passe enregistre dans", PASSWORD_FILE)
            return
    if load_secret() is None:
        print("Attention : aucun mot de passe. Tapez : python3 web/admin.py --mot-de-passe", file=sys.stderr)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    print("Interface web du Minitel sur le port %d" % PORT, file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
