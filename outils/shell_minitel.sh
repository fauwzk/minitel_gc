#!/bin/bash
# =====================================================================
# TERMINAL LINUX ADAPTE AU MINITEL
# =====================================================================
# Le Minitel en teleinformatique comprend le VT100, mais ni les couleurs, ni
# les caracteres graphiques DEC (les cadres de nmtui, htop, mc... sortent en
# lettres "lqqqk"), ni l'UTF-8. On cree une fois pour toutes un type de
# terminal "minitel" (le vt100 sans graphismes), puis on regle l'environnement
# en consequence : les programmes en mode texte dessinent alors leurs cadres
# avec + - |.
#
# Usage : shell_minitel.sh            -> session Bash interactive
#         shell_minitel.sh nmtui ...  -> lance la commande dans ce terminal

TI="$HOME/.terminfo"
if ! TERMINFO="$TI" infocmp minitel >/dev/null 2>&1 && command -v tic >/dev/null; then
    infocmp -x vt100 2>/dev/null \
        | sed -e 's/^vt100|[^,]*,/minitel|Minitel Magis Club (VT100 sans graphismes),/' \
              -e 's/acsc=[^,]*, *//; s/smacs=[^,]*, *//; s/rmacs=[^,]*, *//; s/enacs=[^,]*, *//' \
        | tic -x -o "$TI" - >/dev/null 2>&1
fi
if TERMINFO="$TI" infocmp minitel >/dev/null 2>&1; then
    export TERMINFO="$TI" TERM=minitel
else
    export TERM=vt100
fi

# Ni accents ni UTF-8 : messages en anglais, caracteres ASCII seulement
export LANG=C LC_ALL=C
# Ni couleurs ni pagineur pour les outils qui en mettent d'office
export NO_COLOR=1 SYSTEMD_COLORS=0 SYSTEMD_PAGER=cat GIT_PAGER=cat
export PAGER=less LESS=-X EDITOR=nano
unset LS_COLORS

stty sane rows 24 cols 80 2>/dev/null

if [ $# -gt 0 ]; then
    exec "$@"
fi

clear
echo "TERMINAL LINUX DU MINITEL  -  TAPEZ exit POUR REVENIR AU PORTAIL"
echo
exec bash --rcfile "$(dirname "$0")/bashrc_minitel" -i
