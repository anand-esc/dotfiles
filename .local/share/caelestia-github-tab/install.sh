#!/usr/bin/env bash
# Install the Caelestia GitHub dashboard tab + a pacman hook that re-applies it
# after caelestia-shell updates. Run with: sudo bash install.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/local/share/caelestia-github-tab
HOOK=/etc/pacman.d/hooks/caelestia-github-tab.hook

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

install -Dm644 "$SRC/GitHubTab.qml" "$DEST/GitHubTab.qml"
install -Dm644 "$SRC/NightLight.qml" "$DEST/NightLight.qml"
install -Dm755 "$SRC/apply.py" "$DEST/apply.py"

install -Dm644 /dev/stdin "$HOOK" <<EOF
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = caelestia-shell

[Action]
Description = Re-adding local Caelestia additions (GitHub tab, night light)...
When = PostTransaction
Exec = /usr/bin/python3 -I $DEST/apply.py
EOF

/usr/bin/python3 -I "$DEST/apply.py"
echo "Done. Restart the shell (as your user): qs -c caelestia kill; caelestia shell -d"
