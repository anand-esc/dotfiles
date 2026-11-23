#!/usr/bin/env bash
# SDDM login screen: the "sword" theme from qylock (https://github.com/Darkkal44/qylock,
# by Darkkal44, GPL-3.0). Downloads qylock at a reviewed commit, installs the theme to
# /usr/share/sddm/themes/qylock-sword and makes it the current theme.
# Run with: sudo bash qylock-sword.sh        (switch back: sudo bash install.sh)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

REPO=https://github.com/Darkkal44/qylock
COMMIT=c2933f27b655a999911e6699e1b2c67e59cbd428   # reviewed 2026-11-24
DEST=/usr/share/sddm/themes/qylock-sword
CONF_DIR=/etc/sddm.conf.d

for p in sddm qt6-5compat qt6-multimedia-ffmpeg qt6-declarative; do
    pacman -Q "$p" >/dev/null 2>&1 || { echo "Missing package: $p  (pacman -S $p)"; exit 1; }
done

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "==> Downloading qylock (${COMMIT:0:7})"
git -C "$tmp" init -q
git -C "$tmp" fetch -q --depth 1 "$REPO" "$COMMIT"
git -C "$tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD -- themes/sword LICENSE

echo "==> Installing theme to $DEST"
rm -rf "$DEST"
cp -r "$tmp/themes/sword" "$DEST"
cp "$tmp/LICENSE" "$DEST/LICENSE"
chmod -R a+rX "$DEST"

echo "==> Making it the current theme"
mkdir -p "$CONF_DIR"
# the old astronaut config set a 1.5x scale and an on-screen keyboard; this theme
# scales itself to the screen and needs neither
rm -f "$CONF_DIR/10-astronaut.conf"
cat > "$CONF_DIR/10-theme.conf" <<'EOF'
[Theme]
Current=qylock-sword
CursorTheme=breeze_cursors
CursorSize=24

[Users]
RememberLastUser=true
RememberLastSession=true
EOF

echo "Done. You'll see it at the next login screen (log out, or reboot)."
echo "Preview without logging out:  sddm-greeter-qt6 --test-mode --theme $DEST"
