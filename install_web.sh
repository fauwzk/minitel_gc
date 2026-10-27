#!/bin/bash
# =====================================================================
# INTERFACE WEB D'ADMINISTRATION (service minitel-web, port 8080)
# =====================================================================
# Installe le service qui sert web/admin.py sous le compte minitel, et la
# mise a jour du systeme (apt) qu'il peut lancer en root. Demande ensuite le
# mot de passe de l'interface s'il n'y en a pas encore.
#
#   sudo ./install_web.sh                    installation (et mot de passe)
#   sudo ./install_web.sh --sans-mot-de-passe   sans question (scripts de maj)
#   sudo ./install_web.sh --retirer          desinstallation

if [ "$EUID" -ne 0 ]; then
  echo "ERREUR : Veuillez exécuter ce script en tant que root (sudo $0)"
  exit 1
fi

DEPOT=$(cd "$(dirname "$0")" && pwd)
UNIT=/etc/systemd/system/minitel-web.service
HELPER=/usr/local/sbin/minitel-systeme
SUDOERS=/etc/sudoers.d/012_minitel_web

if [ "$1" = "--retirer" ]; then
    systemctl disable --now minitel-web.service 2>/dev/null
    rm -f "$UNIT" "$HELPER" "$SUDOERS"
    systemctl daemon-reload
    echo "Interface web retirée."
    exit 0
fi

install -o root -g root -m 755 "$DEPOT/outils/minitel-systeme" "$HELPER"
echo "minitel ALL=(root) NOPASSWD: $HELPER" > "$SUDOERS.tmp"
chmod 0440 "$SUDOERS.tmp"
if visudo -cf "$SUDOERS.tmp" >/dev/null; then
    mv "$SUDOERS.tmp" "$SUDOERS"
else
    rm -f "$SUDOERS.tmp"
    echo "ERREUR : règle sudo refusée par visudo."
    exit 1
fi

cat <<EOF > "$UNIT"
[Unit]
Description=Interface web d'administration du Minitel Magis Club
After=network.target

[Service]
User=minitel
WorkingDirectory=$DEPOT
ExecStart=/usr/bin/python3 $DEPOT/web/admin.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minitel-web.service
systemctl restart minitel-web.service

if [ ! -f /home/minitel/.minitel_web ] && [ "$1" != "--sans-mot-de-passe" ]; then
    sudo -u minitel -H python3 "$DEPOT/web/admin.py" --mot-de-passe
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "Interface web : http://${IP:-adresse-du-pi}:8080"
if [ ! -f /home/minitel/.minitel_web ]; then
    echo "Choisissez son mot de passe : sudo -u minitel -H python3 $DEPOT/web/admin.py --mot-de-passe"
fi
