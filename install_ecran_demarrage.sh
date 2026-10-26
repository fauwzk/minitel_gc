#!/bin/bash
# =====================================================================
# ECRAN DE DEMARRAGE DU RASPBERRY PI SUR LE MINITEL (service minitel-boot)
# =====================================================================
# Des que l'adaptateur USB-serie apparait au demarrage, boot_minitel.lua met
# le Minitel en 80 colonnes et suit le demarrage de Linux en direct. La
# session Minitel (serial-getty@ttyUSB0) attend la fin de cet ecran.
#
# Installation (deja faite par install_minitel.sh) :
#   sudo ./install_ecran_demarrage.sh
# Desinstallation :
#   sudo ./install_ecran_demarrage.sh --retirer

if [ "$EUID" -ne 0 ]; then
  echo "ERREUR : Veuillez exécuter ce script en tant que root (sudo $0)"
  exit 1
fi

UNIT=/etc/systemd/system/minitel-boot.service

if [ "$1" = "--retirer" ]; then
    systemctl disable minitel-boot.service 2>/dev/null
    rm -f "$UNIT"
    systemctl daemon-reload
    echo "Ecran de démarrage retiré."
    exit 0
fi

cat <<EOF > "$UNIT"
[Unit]
Description=Ecran de demarrage du Raspberry Pi sur le Minitel
DefaultDependencies=no
BindsTo=dev-ttyUSB0.device
After=dev-ttyUSB0.device systemd-journald.service
Before=serial-getty@ttyUSB0.service

[Service]
Type=oneshot
WorkingDirectory=/home/minitel/minitel_gc
ExecStart=/usr/bin/lua5.3 boot_minitel.lua
StandardInput=tty
StandardOutput=tty
StandardError=journal
TTYPath=/dev/ttyUSB0
TTYReset=no
TTYVHangup=no
TimeoutStartSec=60

[Install]
WantedBy=dev-ttyUSB0.device
EOF

systemctl daemon-reload
systemctl enable minitel-boot.service
echo "Ecran de démarrage installé : il s'affichera au prochain redémarrage (sudo reboot)."
