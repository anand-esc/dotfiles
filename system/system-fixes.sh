#!/usr/bin/env bash
# Fixes from the system check. Run:  sudo bash ~/system-fixes.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "1. Locale: en_IN -> en_IN.UTF-8 (fixes 'No Compose file' errors / dead keys). Applies after re-login."
localectl set-locale LANG=en_IN.UTF-8
localectl status | grep LANG

step "2. Let Caelestia recolour folder icons (it runs 'sudo -n papirus-folders -C <colour> -u')"
RULE=/etc/sudoers.d/caelestia-papirus
TMP=$(mktemp)
echo "${SUDO_USER:-$(logname)} ALL=(root) NOPASSWD: /usr/bin/papirus-folders -C * -u" > "$TMP"
if visudo -cf "$TMP" >/dev/null; then
    install -m 440 -o root -g root "$TMP" "$RULE"
    echo "   added $RULE (only this one command, nothing else)"
else
    echo "   sudoers rule failed validation, skipped"
fi
rm -f "$TMP"

step "Done. Log out and back in for the locale change."
