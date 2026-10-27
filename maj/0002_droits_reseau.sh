#!/bin/bash
# Script de mise a jour : joue une seule fois, en root, par updater.lua.
#
# Autorise le compte minitel a gerer le reseau (NetworkManager) depuis sa
# session sur le port serie : polkit n'accorde ces droits qu'aux sessions
# locales "actives" (ecran et clavier du Pi), si bien que nmcli, utilise par
# 3615 RESEAU, et nmtui y repondaient "Not authorized".
set -e

# polkit 0.106 et plus (Raspberry Pi OS Bookworm) : regles JavaScript
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-minitel-reseau.rules <<'EOF'
// Le compte minitel peut gerer le reseau depuis le Minitel (3615 RESEAU)
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.user == "minitel") {
        return polkit.Result.YES;
    }
});
EOF
chmod 644 /etc/polkit-1/rules.d/50-minitel-reseau.rules

# polkit 0.105 (Raspberry Pi OS Bullseye et avant) : fichiers .pkla
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/50-minitel-reseau.pkla <<'EOF'
[Le compte minitel peut gerer le reseau depuis le Minitel]
Identity=unix-user:minitel
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
chmod 644 /etc/polkit-1/localauthority/50-local.d/50-minitel-reseau.pkla

# polkit relit ses regles tout seul ; un redemarrage ne coute rien s'il tarde
systemctl try-restart polkit.service 2>/dev/null || true
