#!/bin/bash
# =====================================================================
# SCRIPTS DE MISE A JOUR : AUTORISE updater.lua A LES LANCER EN ROOT
# =====================================================================
# Installe le lanceur outils/minitel-maj dans /usr/local/sbin (propriete de
# root, hors du depot) et autorise le compte minitel a le lancer par sudo,
# sans mot de passe. Apres chaque git pull, updater.lua l'appelle : il joue
# une seule fois chaque script maj/*.sh livre par le depot.
#
# ATTENTION : tout script ajoute au depot GitHub sera execute en root sur ce
# Raspberry Pi a la mise a jour suivante.
#
# Installation (deja faite par install_minitel.sh) :
#   sudo ./install_scripts_maj.sh
# Desinstallation :
#   sudo ./install_scripts_maj.sh --retirer

if [ "$EUID" -ne 0 ]; then
  echo "ERREUR : Veuillez exécuter ce script en tant que root (sudo $0)"
  exit 1
fi

DEPOT=$(cd "$(dirname "$0")" && pwd)
LANCEUR=/usr/local/sbin/minitel-maj
SUDOERS=/etc/sudoers.d/011_minitel_maj

if [ "$1" = "--retirer" ]; then
    rm -f "$LANCEUR" "$SUDOERS"
    echo "Scripts de mise à jour désactivés (l'historique reste dans /var/lib/minitel)."
    exit 0
fi

install -o root -g root -m 755 "$DEPOT/outils/minitel-maj" "$LANCEUR"

echo "minitel ALL=(root) NOPASSWD: $LANCEUR" > "$SUDOERS.tmp"
chmod 0440 "$SUDOERS.tmp"
if visudo -cf "$SUDOERS.tmp" >/dev/null; then
    mv "$SUDOERS.tmp" "$SUDOERS"
else
    rm -f "$SUDOERS.tmp"
    echo "ERREUR : règle sudo refusée par visudo, rien n'a été changé."
    exit 1
fi

mkdir -p /var/lib/minitel
touch /var/lib/minitel/maj_faites
chmod 644 /var/lib/minitel/maj_faites
echo "Scripts de mise à jour activés : $LANCEUR"
