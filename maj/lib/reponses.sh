# Bibliotheque des scripts de mise a jour (ce n'est pas un script a jouer :
# le lanceur ne joue que maj/*.sh, pas les sous-dossiers).
#
# Un script declare ses questions dans son en-tete :
#   # QUESTION: NOM|Texte de la question|options
# La mise a jour (updater.lua) les pose a l'utilisateur avant de jouer les
# scripts, puis le script lit la reponse avec :
#   . "$DEPOT/maj/lib/reponses.sh"
#   valeur=$(reponse NOM)
# La reponse est vide si l'utilisateur a passe la question, ou si la question
# n'a pas ete posee (option si_absent, ou script joue hors de la mise a jour).

MAJ_REPONSES=/tmp/minitel_maj_reponses

reponse() {
    [ -f "$MAJ_REPONSES" ] || return 0
    local ligne
    while IFS= read -r ligne; do
        case "$ligne" in
            "$1="*) printf '%s' "${ligne#*=}"; return 0 ;;
        esac
    done < "$MAJ_REPONSES"
}
