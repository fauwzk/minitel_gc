#!/bin/bash
# =====================================================================
# INSTALLATION SYSTEME - MINITEL MAGIS CLUB (Version Optimisée)
# =====================================================================

# Vérification des droits administrateur
if [ "$EUID" -ne 0 ]; then
  echo "ERREUR : Veuillez exécuter ce script en tant que root (sudo ./install_minitel.sh)"
  exit 1
fi

echo "> 1. MISE A JOUR ET INSTALLATION DES DEPENDANCES..."
apt-get update
# Installation de Lua, Git, Sox (audio), Alsa (gestion matérielle du son)
apt-get install -y lua5.3 git sox alsa-utils network-manager coreutils

echo "> 2. CREATION DE L'UTILISATEUR 'minitel'..."
if id "minitel" &>/dev/null; then
    echo "L'utilisateur 'minitel' existe déjà."
else
    useradd -m -s /bin/bash minitel
fi
# Ajout aux groupes vitaux (dialout/uucp pour le port série, audio pour la carte son)
usermod -aG dialout,audio,video,plugdev minitel

# Autorise l'utilisateur à lancer ses services d'arrière-plan dès le démarrage
loginctl enable-linger minitel 2>/dev/null || true

echo "> 3. CONFIGURATION DES DROITS SYSTEMES (SUDO)..."
cat <<EOF > /etc/sudoers.d/010_minitel
minitel ALL=(ALL) NOPASSWD: /usr/sbin/reboot, /usr/sbin/poweroff
EOF
chmod 0440 /etc/sudoers.d/010_minitel

echo "> 4. CLONAGE DU DEPOT GITHUB (fauwzk/minitel_gc)..."
rm -rf /tmp/minitel_temp
sudo -u minitel git clone https://github.com/fauwzk/minitel_gc.git /tmp/minitel_temp
sudo -u minitel cp -rn /tmp/minitel_temp/* /home/minitel/ 2>/dev/null
rm -rf /tmp/minitel_temp
sudo -u minitel mkdir -p /home/minitel/jeux
sudo -u minitel mkdir -p /home/minitel/utils/prog_basic

echo "> 5. CONFIGURATION DE L'AUTOLOGIN SYSTEMD (ttyUSB0)..."
mkdir -p /etc/systemd/system/serial-getty@ttyUSB0.service.d/
cat <<EOF > /etc/systemd/system/serial-getty@ttyUSB0.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 9600 %I vt100 --autologin minitel
EOF
systemctl daemon-reload
systemctl enable serial-getty@ttyUSB0.service

echo "> 6. CONFIGURATION DU BASH_PROFILE ET DU SON..."
cat <<'EOF' > /home/minitel/.bash_profile
if [ "$(tty)" = "/dev/ttyUSB0" ]; then
    cd /home/minitel
    
    # -------------------------------------------------------------
    # CORRECTIF AUDIO RASPBERRY PI : 
    # Force Sox à utiliser ALSA pour éviter les crashs liés à 
    # PipeWire/PulseAudio lors d'une connexion via le port Série.
    # -------------------------------------------------------------
    export AUDIODRIVER=alsa
    
    exec lua5.3 master.lua
fi
EOF
chown minitel:minitel /home/minitel/.bash_profile

echo "> 7. CONFIGURATION DU DEMARRAGE SILENCIEUX (KIOSK MODE)..."
CMDLINE_FILE="/boot/firmware/cmdline.txt"
if [ ! -f "$CMDLINE_FILE" ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -f "$CMDLINE_FILE" ]; then
    sed -i 's/console=serial0,[0-9]\+ //g' "$CMDLINE_FILE"
    sed -i 's/console=ttyAMA0,[0-9]\+ //g' "$CMDLINE_FILE"
    
    if ! grep -q "quiet" "$CMDLINE_FILE"; then
        sed -i 's/$/ quiet splash loglevel=0 vt.global_cursor_default=0/' "$CMDLINE_FILE"
    fi
    echo "Démarrage silencieux configuré sur le port série."
fi

echo "> 8. DEBLOCAGE ET REGLAGE DU VOLUME AUDIO MATERIEL..."
# Débloque (unmute) la carte son et règle le volume à 85%.
# On teste "Headphone" (prise Jack classique du Pi) et "Master" (par défaut).
sudo -u minitel amixer -q sset Headphone 85% unmute 2>/dev/null || true
sudo -u minitel amixer -q sset Master 85% unmute 2>/dev/null || true
sudo -u minitel amixer -q sset PCM 85% unmute 2>/dev/null || true

echo "====================================================================="
echo " INSTALLATION TERMINEE ! "
echo "====================================================================="
echo "Branchez votre câble adaptateur USB-Série sur le Raspberry Pi."
echo "Pour appliquer toutes les modifications, tapez : sudo reboot"