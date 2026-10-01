#!/bin/bash
# =====================================================================
# INSTALLATION SYSTEME - MINITEL MAGIS CLUB
# =====================================================================

# Vérification des droits administrateur
if [ "$EUID" -ne 0 ]; then
  echo "ERREUR : Veuillez exécuter ce script en tant que root (sudo ./install_minitel.sh)"
  exit 1
fi

echo "> 1. MISE A JOUR ET INSTALLATION DES DEPENDANCES..."
apt-get update
# On installe lua, git, network-manager (pour nmtui) et sox (pour le son jack)
apt-get install -y lua5.3 git sox alsa-utils network-manager coreutils

echo "> 2. CREATION DE L'UTILISATEUR 'minitel'..."
if id "minitel" &>/dev/null; then
    echo "L'utilisateur 'minitel' existe déjà."
else
    # Crée l'utilisateur avec /home/minitel
    useradd -m -s /bin/bash minitel
fi
# Ajout aux groupes nécessaires (dialout pour ttyUSB0, audio pour sox)
usermod -aG dialout,audio,video,plugdev minitel

echo "> 3. CONFIGURATION DES DROITS SYSTEMES (SUDO)..."
# Permet au minitel de redémarrer et d'éteindre le Pi sans demander de mot de passe
cat <<EOF > /etc/sudoers.d/010_minitel
minitel ALL=(ALL) NOPASSWD: /usr/sbin/reboot, /usr/sbin/poweroff
EOF
chmod 0440 /etc/sudoers.d/010_minitel

echo "> 4. CLONAGE DU DEPOT GITHUB (fauwzk/minitel_gc)..."
# On vide le dossier temporaire s'il existe
rm -rf /tmp/minitel_temp
# Clonage en tant qu'utilisateur minitel pour que les droits soient corrects
sudo -u minitel git clone https://github.com/fauwzk/minitel_gc.git /tmp/minitel_temp

# Déplacement des fichiers dans le dossier personnel
sudo -u minitel cp -rn /tmp/minitel_temp/* /home/minitel/ 2>/dev/null
rm -rf /tmp/minitel_temp

# Création des dossiers modulaires au cas où ils manqueraient dans le Git
sudo -u minitel mkdir -p /home/minitel/jeux
sudo -u minitel mkdir -p /home/minitel/utils/prog_basic

echo "> 5. CONFIGURATION DE L'AUTOLOGIN SYSTEMD (ttyUSB0)..."
# Remplace le comportement par défaut d'agetty pour le port série
mkdir -p /etc/systemd/system/serial-getty@ttyUSB0.service.d/
cat <<EOF > /etc/systemd/system/serial-getty@ttyUSB0.service.d/autologin.conf
[Service]
# On vide la commande par défaut
ExecStart=
# On lance agetty avec l'autologin sur l'utilisateur 'minitel', avec le type de terminal vt100
ExecStart=-/sbin/agetty -o '-p -- \\u' --keep-baud 9600 %I vt100 --autologin minitel
EOF

# Application des changements systemd
systemctl daemon-reload
systemctl enable serial-getty@ttyUSB0.service

echo "> 6. CONFIGURATION DU BASH_PROFILE (Lancement direct)..."
# Création du fichier profil qui s'exécute à la connexion de l'utilisateur
cat <<'EOF' > /home/minitel/.bash_profile
# Vérifie qu'on est bien sur le port série USB (évite de bloquer si on se connecte en SSH avec cet utilisateur)
if [ "$(tty)" = "/dev/ttyUSB0" ]; then
    cd /home/minitel
    
    # "exec" remplace le bash par lua. 
    # Ainsi, si on quitte Lua (ex: lors d'une mise à jour), la session se ferme
    # et systemd relance instantanément la connexion !
    exec lua5.3 master.lua
fi
EOF
chown minitel:minitel /home/minitel/.bash_profile

echo "====================================================================="
echo " INSTALLATION TERMINEE ! "
echo "====================================================================="
echo "Branchez votre câble adaptateur USB-Série sur le Raspberry Pi."
echo "Pour appliquer toutes les modifications, tapez : sudo reboot"