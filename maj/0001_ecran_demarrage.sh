#!/bin/bash
# Script de mise a jour : joue une seule fois, en root, par updater.lua.
# Regles : nom NNNN_description.sh, joue depuis la racine du depot ($DEPOT),
# sans clavier ni ecran (la sortie va dans /var/lib/minitel/maj.log), et sans
# danger s'il est rejoue (il l'est apres un echec).
#
# (Re)installe le service de l'ecran de demarrage du Raspberry Pi.
set -e
bash "$DEPOT/install_ecran_demarrage.sh"
