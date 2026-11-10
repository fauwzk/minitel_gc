#!/usr/bin/env python3
"""Pont entre le Minitel (entree et sortie standard, deja en mode brut) et un
serveur Videotex en ligne, pour 3615 VIDEOTEX.

    python3 outils/videotex_pont.py ws://3611.re/ws
    python3 outils/videotex_pont.py wss://go.minipavi.fr:8181
    python3 outils/videotex_pont.py telnet://hote:23

Les octets passent tels quels dans les deux sens : c'est le Minitel lui-meme
qui affiche les pages Videotex. La touche Esc du Minitel, frappee seule, met
fin a la connexion (les reponses du Minitel aux commandes du serveur, qui
commencent aussi par ESC, arrivent d'un bloc et ne sont pas confondues).
Bibliotheque standard seulement. Code de sortie : 0 fin normale, 1 erreur
(message sur la sortie d'erreur).
"""
import base64
import os
import select
import socket
import ssl
import struct
import sys
import time
import urllib.parse

ESC = 0x1B
ESC_ALONE = 0.25   # secondes sans autre octet apres ESC : c'est la touche Esc


class WebSocket:
    def __init__(self, url):
        u = urllib.parse.urlparse(url)
        port = u.port or (443 if u.scheme == "wss" else 80)
        raw = socket.create_connection((u.hostname, port), timeout=10)
        if u.scheme == "wss":
            raw = ssl.create_default_context().wrap_socket(raw, server_hostname=u.hostname)
        self.sock = raw
        key = base64.b64encode(os.urandom(16)).decode()
        host = u.hostname if u.port is None else "%s:%d" % (u.hostname, u.port)
        req = ("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n"
               "Origin: http://%s\r\nUser-Agent: MinitelMagisClub/1.0\r\n\r\n"
               % (u.path or "/", host, key, u.hostname))
        self.sock.sendall(req.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError("le serveur a ferme la connexion")
            head += chunk
            if len(head) > 8192:
                raise ConnectionError("reponse du serveur invalide")
        status = head.split(b"\r\n", 1)[0].decode("latin-1")
        if " 101 " not in status + " ":
            raise ConnectionError("serveur refuse : " + status)
        self.sock.settimeout(None)
        self.buf = b""

    def fileno(self):
        return self.sock.fileno()

    def pending(self):
        return isinstance(self.sock, ssl.SSLSocket) and self.sock.pending() > 0

    def send(self, data):
        # trame texte masquee (obligatoire cote client) ; les codes Videotex
        # sont tous inferieurs a 128, donc de l'UTF-8 valide
        mask = os.urandom(4)
        n = len(data)
        head = bytes([0x81])
        if n < 126:
            head += bytes([0x80 | n])
        elif n < 65536:
            head += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", n)
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(head + mask + body)

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("connexion fermee")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        """Rend les octets d'une trame de donnees (b"" pour une trame de
        controle) ; leve ConnectionError a la fermeture."""
        b1, b2 = self._read(2)
        opcode, n = b1 & 0x0F, b2 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._read(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._read(8))[0]
        mask = self._read(4) if b2 & 0x80 else None
        data = self._read(n)
        if mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        if opcode == 0x8:
            raise ConnectionError("le serveur a mis fin a la connexion")
        if opcode == 0x9:  # ping -> pong
            mask = os.urandom(4)
            self.sock.sendall(bytes([0x8A, 0x80 | len(data)]) + mask
                              + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))
            return b""
        if opcode == 0x1:
            # texte : chaque caractere est un octet Videotex
            return data.decode("utf-8", "replace").encode("latin-1", "ignore")
        if opcode in (0x0, 0x2):
            return data
        return b""


class Telnet:
    IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240

    def __init__(self, url):
        u = urllib.parse.urlparse(url)
        self.sock = socket.create_connection((u.hostname, u.port or 23), timeout=10)
        self.sock.settimeout(None)
        self.state = None

    def fileno(self):
        return self.sock.fileno()

    def pending(self):
        return False

    def send(self, data):
        self.sock.sendall(data.replace(b"\xff", b"\xff\xff"))

    def recv(self):
        data = self.sock.recv(65536)
        if not data:
            raise ConnectionError("le serveur a mis fin a la connexion")
        out = bytearray()
        for b in data:
            st = self.state
            if st is None:
                if b == self.IAC:
                    self.state = "iac"
                else:
                    out.append(b)
            elif st == "iac":
                if b in (self.DO, self.DONT, self.WILL, self.WONT):
                    self.state = b
                elif b == self.SB:
                    self.state = "sb"
                else:
                    if b == self.IAC:
                        out.append(b)
                    self.state = None
            elif st in (self.DO, self.DONT):
                self.sock.sendall(bytes([self.IAC, self.WONT, b]))  # on ne negocie rien
                self.state = None
            elif st in (self.WILL, self.WONT):
                self.sock.sendall(bytes([self.IAC, self.DONT, b]))
                self.state = None
            elif st == "sb":
                if b == self.IAC:
                    self.state = "sb-iac"
            elif st == "sb-iac":
                self.state = None if b == self.SE else "sb"
        return bytes(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    url = sys.argv[1]
    try:
        conn = Telnet(url) if url.startswith(("telnet://", "tcp://")) else WebSocket(url)
    except (OSError, ConnectionError) as e:
        print("Connexion impossible : %s" % e, file=sys.stderr)
        return 1

    fin, fout = sys.stdin.fileno(), sys.stdout.fileno()
    held = None  # instant ou un ESC seul est arrive du Minitel
    try:
        while True:
            timeout = None
            if held is not None:
                timeout = max(0.0, held + ESC_ALONE - time.monotonic())
            if conn.pending():
                timeout = 0
            r, _, _ = select.select([fin, conn], [], [], timeout)
            if conn in r or conn.pending():
                data = conn.recv()
                if data:
                    os.write(fout, bytes(b & 0x7F for b in data))
            if fin in r:
                data = os.read(fin, 1024)
                if not data:
                    break
                if held is not None:
                    data = bytes([ESC]) + data
                    held = None
                if data == bytes([ESC]):
                    held = time.monotonic()
                elif data:
                    conn.send(data)
            elif held is not None and time.monotonic() >= held + ESC_ALONE:
                break  # touche Esc seule : fin de la connexion
    except ConnectionError:
        pass
    except OSError as e:
        print("Connexion perdue : %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
