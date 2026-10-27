#!/bin/bash
# Script de mise a jour : joue une seule fois, en root, par updater.lua.
#
# Installe l'interface web d'administration (service minitel-web, port
# 8080) et enregistre son mot de passe, demande pendant la mise a jour.
#
# QUESTION: MOT_DE_PASSE_WEB|Choisissez le mot de passe de l'interface web d'administration (8 caracteres au moins) :|secret,confirmer,min=8,si_absent=/home/minitel/.minitel_web
set -e
. "$DEPOT/maj/lib/reponses.sh"

bash "$DEPOT/install_web.sh" --sans-mot-de-passe

mdp=$(reponse MOT_DE_PASSE_WEB)
if [ -n "$mdp" ]; then
    printf '%s\n' "$mdp" | sudo -u minitel -H python3 "$DEPOT/web/admin.py" --mot-de-passe-stdin
elif [ ! -f /home/minitel/.minitel_web ]; then
    echo "Pas de mot de passe : sudo -u minitel -H python3 $DEPOT/web/admin.py --mot-de-passe"
fi
