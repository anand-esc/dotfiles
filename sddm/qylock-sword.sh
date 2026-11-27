#!/usr/bin/env bash
# SDDM login screen: the "sword" theme from qylock (https://github.com/Darkkal44/qylock,
# by Darkkal44, GPL-3.0). Downloads the theme at a reviewed commit, installs it to
# /usr/share/sddm/themes/qylock-sword and makes it the current theme.
# Run with: sudo bash qylock-sword.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

COMMIT=c2933f27b655a999911e6699e1b2c67e59cbd428   # reviewed 2026-11-24
DEST=/usr/share/sddm/themes/qylock-sword
CONF_DIR=/etc/sddm.conf.d

for p in sddm qt6-5compat qt6-multimedia-ffmpeg qt6-declarative; do
    pacman -Q "$p" >/dev/null 2>&1 || { echo "Missing package: $p  (pacman -S $p)"; exit 1; }
done

# Only the Sword theme's files (~42 MB, not the whole 1.2 GB repo), each checked
# against the hash of the reviewed version.
RAW=https://raw.githubusercontent.com/Darkkal44/qylock/$COMMIT
FILES=(
    "083db810e67fb833f79e0ba9e3845f4370b064e40e27f79d8eeb597c53513b73 themes/sword/BackgroundVideo.qml"
    "47a063baaa6ce3f19e3bdd95fbe6cd94bc4f7d6c6f67f23be984cb7d4124f6a7 themes/sword/Main.qml"
    "2f15a5ae20d065afb0b3c31496ecb0c372ec64f2d2a036592016310098c7e16a themes/sword/metadata.desktop"
    "932ea1b41a705ba600bf943595ecbe32f922ba108b250096a9d98f35253988ce themes/sword/theme.conf"
    "9edd03523accde78f242620d44c450876b6450eb4dd0c7293bbc1bc821bf1f4e themes/sword/font/The Last Shuriken.ttf"
    "6e8ee0f36d35d507d872ace3a12bf0813eb2db01b42831db2e8f825b2a630809 themes/sword/bg.mp4"
    "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986 LICENSE"
)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "==> Downloading the Sword theme from qylock (${COMMIT:0:7})"
for entry in "${FILES[@]}"; do
    sum=${entry%% *}; path=${entry#* }
    mkdir -p "$tmp/$(dirname "$path")"
    curl -fL --progress-bar -o "$tmp/$path" "$RAW/${path// /%20}"
    echo "$sum  $tmp/$path" | sha256sum -c --quiet - || { echo "Checksum mismatch: $path"; exit 1; }
done

echo "==> Installing theme to $DEST"
rm -rf "$DEST"
cp -r "$tmp/themes/sword" "$DEST"
cp "$tmp/LICENSE" "$DEST/LICENSE"
chmod -R a+rX "$DEST"

echo "==> Making it the current theme"
mkdir -p "$CONF_DIR"
# remove the old astronaut-theme config (1.5x scale, on-screen keyboard), if present
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
