#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Serveur 3615 PICTO (Style Nintendo DS PictoChat pour Minitel & Web)
Zéro dépendance externe (Python 3 Standard Library uniquement)
Port par défaut : 8085
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.parse
import json
import time
import unicodedata
import threading

PORT = 8085
MAX_HISTORY_PER_ROOM = 60
PRESENCE_TIMEOUT = 15  # Secondes avant qu'un utilisateur inactif disparaisse du compteur

lock = threading.Lock()

# Les 4 salons façon PictoChat (A, B, C, D)
rooms = {
    "A": [{"id": 1, "time": time.strftime("%H:%M"), "user": "SYSTEME", "text": "BIENVENUE DANS LE SALON A (GENERAL) !"}],
    "B": [{"id": 1, "time": time.strftime("%H:%M"), "user": "SYSTEME", "text": "SALON B (TECH & HARDWARE) OUVERT."}],
    "C": [{"id": 1, "time": time.strftime("%H:%M"), "user": "SYSTEME", "text": "SALON C (JEUX & ARCADE) OUVERT."}],
    "D": [{"id": 1, "time": time.strftime("%H:%M"), "user": "SYSTEME", "text": "SALON D (VIP / NOCTURNE) OUVERT."}]
}
next_id = {"A": 2, "B": 2, "C": 2, "D": 2}

# Suivi des connectés : presence[room][user] = timestamp
presence = {"A": {}, "B": {}, "C": {}, "D": {}}


def to_ascii_minitel(s):
    """Nettoie les accents et caractères spéciaux pour l'écran 80 col du Minitel."""
    if not s:
        return ""
    s = s.replace("œ", "oe").replace("Œ", "OE").replace("’", "'").replace("|", "/")
    norm = unicodedata.normalize("NFKD", s)
    clean = "".join(c for c in norm if not unicodedata.combining(c))
    # Garde uniquement les caracteres imprimables ASCII (32 a 126)
    return "".join(c if 32 <= ord(c) <= 126 else " " for c in clean).strip()


def update_presence_and_counts(active_room=None, user=None):
    now = time.time()
    if active_room in presence and user:
        # Si l'utilisateur était dans une autre salle, on l'en retire
        for r in presence:
            if r != active_room and user in presence[r]:
                del presence[r][user]
        presence[active_room][user] = now

    counts = {}
    users_by_room = {}
    for r in ("A", "B", "C", "D"):
        expired = [u for u, ts in presence[r].items() if now - ts > PRESENCE_TIMEOUT]
        for u in expired:
            del presence[r][u]
        counts[r] = len(presence[r])
        users_by_room[r] = list(presence[r].keys())
    return counts, users_by_room


# =====================================================================
# INTERFACE WEB CLIENT INTEGREE (POUR TESTER DEPUIS UN PC / SMARTPHONE)
# =====================================================================
HTML_CLIENT = """<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>3615 PICTO - Terminal Web & Minitel</title>
<style>
  :root { --bg: #0c0d0c; --fg: #33ff66; --dim: #197a32; --inv-bg: #33ff66; --inv-fg: #0c0d0c; }
  * { box-sizing: border-box; font-family: "Courier New", Courier, monospace; }
  body { background: #050505; color: var(--fg); margin: 0; padding: 15px; display: flex; justify-content: center; }
  .crt { width: 100%; max-width: 820px; background: var(--bg); border: 3px solid var(--fg); box-shadow: 0 0 25px rgba(51,255,102,0.2); padding: 12px; }
  .banner { background: var(--inv-bg); color: var(--inv-fg); font-weight: bold; text-align: center; padding: 6px; letter-spacing: 2px; margin-bottom: 12px; }
  .top-bar { display: flex; gap: 10px; flex-wrap: wrap; justify-content: space-between; align-items: center; border-bottom: 2px dashed var(--dim); padding-bottom: 10px; margin-bottom: 10px; }
  .rooms { display: flex; gap: 6px; flex-wrap: wrap; }
  .room-btn { background: transparent; color: var(--fg); border: 2px solid var(--fg); padding: 6px 12px; cursor: pointer; font-weight: bold; font-size: 14px; }
  .room-btn.active, .room-btn:hover { background: var(--inv-bg); color: var(--inv-fg); }
  .pseudo-box input { background: #000; color: var(--fg); border: 1px solid var(--fg); padding: 5px 8px; width: 140px; text-transform: uppercase; font-weight: bold; }
  .main-grid { display: grid; grid-template-columns: 1fr 200px; gap: 10px; }
  @media (max-width: 650px) { .main-grid { grid-template-columns: 1fr; } }
  #chat-box { height: 380px; border: 2px solid var(--fg); padding: 10px; overflow-y: auto; background: #070807; display: flex; flex-direction: column; gap: 6px; }
  .msg { line-height: 1.35; word-break: break-word; }
  .msg .time { color: #88ffaa; }
  .msg .user { background: var(--inv-bg); color: var(--inv-fg); padding: 0 4px; font-weight: bold; margin: 0 4px; }
  .msg.sys .user { background: #ffcc00; color: #000; }
  .side-panel { border: 2px solid var(--fg); padding: 10px; background: #070807; font-size: 14px; }
  .side-title { background: var(--inv-bg); color: var(--inv-fg); text-align: center; font-weight: bold; padding: 3px; margin-bottom: 8px; }
  .input-row { display: flex; gap: 8px; margin-top: 10px; }
  #msg-input { flex: 1; background: #000; color: var(--fg); border: 2px solid var(--fg); padding: 10px; font-size: 15px; }
  .send-btn { background: var(--inv-bg); color: var(--inv-fg); border: none; padding: 0 20px; font-weight: bold; cursor: pointer; font-size: 15px; }
  .ascii-btns { margin-top: 8px; display: flex; gap: 6px; flex-wrap: wrap; }
  .stamp { background: #112214; color: var(--fg); border: 1px solid var(--dim); padding: 3px 8px; cursor: pointer; font-size: 12px; }
  .stamp:hover { border-color: var(--fg); }
</style>
</head>
<body>
<div class="crt">
  <div class="banner">* * * 3615 PICTO - PASSERELLE WEB &lt;-&gt; MINITEL * * *</div>
  <div class="top-bar">
    <div class="rooms">
      <button class="room-btn active" id="btn-A" onclick="setRoom('A')">SALLE A (0)</button>
      <button class="room-btn" id="btn-B" onclick="setRoom('B')">SALLE B (0)</button>
      <button class="room-btn" id="btn-C" onclick="setRoom('C')">SALLE C (0)</button>
      <button class="room-btn" id="btn-D" onclick="setRoom('D')">SALLE D (0)</button>
    </div>
    <div class="pseudo-box">
      PSEUDO: <input type="text" id="pseudo" maxlength="10" value="WEB_USER">
    </div>
  </div>
  <div class="main-grid">
    <div id="chat-box"></div>
    <div class="side-panel">
      <div class="side-title">CONNECTES</div>
      <div id="user-list">Aucun</div>
    </div>
  </div>
  <div class="ascii-btns">
    <span>PICTOS ASCII :</span>
    <button class="stamp" onclick="addStamp(' ( ^_^) ')">( ^_^)</button>
    <button class="stamp" onclick="addStamp(' [3615] ')">[3615]</button>
    <button class="stamp" onclick="addStamp(' \\\\o/ ')">\\o/</button>
    <button class="stamp" onclick="addStamp(' &lt;3 ')">&lt;3</button>
    <button class="stamp" onclick="addStamp(' [CAFE?] ')">[CAFE?]</button>
  </div>
  <form class="input-row" onsubmit="sendMsg(event)">
    <input type="text" id="msg-input" maxlength="60" placeholder="Tapez votre message pour le Minitel..." autocomplete="off">
    <button type="submit" class="send-btn">[ENVOI]</button>
  </form>
</div>
<script>
let currentRoom = 'A';
let lastId = 0;
const pseudoInput = document.getElementById('pseudo');
pseudoInput.value = 'WEB_' + Math.floor(10 + Math.random() * 89);

function setRoom(r) {
  if (r === currentRoom) return;
  currentRoom = r;
  lastId = 0;
  document.getElementById('chat-box').innerHTML = '';
  ['A','B','C','D'].forEach(k => document.getElementById('btn-'+k).classList.toggle('active', k === r));
  poll();
}

function addStamp(s) {
  const inp = document.getElementById('msg-input');
  if ((inp.value + s).length <= 60) inp.value += s;
  inp.focus();
}

async function poll() {
  const user = (pseudoInput.value || 'ANONYME').toUpperCase();
  try {
    const res = await fetch(`/api/poll?room=${currentRoom}&since=${lastId}&user=${encodeURIComponent(user)}`);
    const data = await res.json();
    ['A','B','C','D'].forEach(k => {
      document.getElementById('btn-'+k).textContent = `SALLE ${k} (${data.counts[k] || 0})`;
    });
    const uList = data.users || [];
    document.getElementById('user-list').innerHTML = uList.length ? uList.map(u => '&gt; ' + u).join('<br>') : 'Aucun';
    const box = document.getElementById('chat-box');
    data.messages.forEach(m => {
      lastId = Math.max(lastId, m.id);
      const div = document.createElement('div');
      div.className = 'msg' + (m.user === 'SYSTEME' ? ' sys' : '');
      div.innerHTML = `<span class="time">[${m.time}]</span><span class="user">${m.user}</span> ${m.text}`;
      box.appendChild(div);
      box.scrollTop = box.scrollHeight;
    });
  } catch (e) {}
}

async function sendMsg(e) {
  e.preventDefault();
  const inp = document.getElementById('msg-input');
  const text = inp.value.trim();
  if (!text) return;
  const user = (pseudoInput.value || 'ANONYME').toUpperCase();
  inp.value = '';
  await fetch(`/api/send?room=${currentRoom}&user=${encodeURIComponent(user)}&msg=${encodeURIComponent(text)}`, { method: 'POST' });
  poll();
}

setInterval(poll, 1500);
poll();
</script>
</body>
</html>
"""


class PictoHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Silence les logs HTTP de polling intensif
        pass

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_CLIENT.encode("utf-8"))
            return

        if parsed.path == "/api/poll":
            room = qs.get("room", ["A"])[0].upper()
            if room not in rooms:
                room = "A"
            try:
                since = int(qs.get("since", ["0"])[0])
            except ValueError:
                since = 0
            user = to_ascii_minitel(qs.get("user", [""])[0]).upper()[:10]
            fmt = qs.get("fmt", ["json"])[0]

            with lock:
                counts, users_by_room = update_presence_and_counts(room, user if user else None)
                msgs = [m for m in rooms[room] if m["id"] > since]

            if fmt == "minitel":
                # Format ultra-léger pour Lua :
                # Ligne 1 : META|countA|countB|countC|countD|user1,user2...
                # Lignes suivantes : MSG|id|time|user|text
                u_str = ",".join(users_by_room.get(room, []))
                lines = [f"META|{counts['A']}|{counts['B']}|{counts['C']}|{counts['D']}|{u_str}"]
                for m in msgs:
                    lines.append(f"MSG|{m['id']}|{m['time']}|{m['user']}|{m['text']}")
                payload = "\n".join(lines) + "\n"
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=ascii")
                self.end_headers()
                self.wfile.write(payload.encode("ascii", errors="replace"))
            else:
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(json.dumps({
                    "room": room,
                    "counts": counts,
                    "users": users_by_room.get(room, []),
                    "messages": msgs
                }).encode("utf-8"))
            return

        if parsed.path == "/api/send":
            self.handle_send(qs)
            return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        if parsed.path == "/api/send":
            self.handle_send(qs)
        else:
            self.send_response(404)
            self.end_headers()

    def handle_send(self, qs):
        room = qs.get("room", ["A"])[0].upper()
        if room not in rooms:
            room = "A"
        user = to_ascii_minitel(qs.get("user", ["ANONYME"])[0]).upper()[:10] or "ANONYME"
        text = to_ascii_minitel(qs.get("msg", [""])[0])[:62]

        if text:
            with lock:
                update_presence_and_counts(room, user)
                mid = next_id[room]
                next_id[room] += 1
                rooms[room].append({
                    "id": mid,
                    "time": time.strftime("%H:%M"),
                    "user": user,
                    "text": text
                })
                if len(rooms[room]) > MAX_HISTORY_PER_ROOM:
                    rooms[room] = rooms[room][-MAX_HISTORY_PER_ROOM:]

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK\n")


if __name__ == "__main__":
    print(f"[3615 PICTO] Serveur actif sur http://0.0.0.0:{PORT}")
    server = ThreadingHTTPServer(("0.0.0.0", PORT), PictoHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nArrêt du serveur.")