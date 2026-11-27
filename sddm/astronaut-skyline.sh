#!/usr/bin/env bash
# SDDM login screen that follows your desktop wallpaper: sddm-astronaut-theme's "Black hole"
# layout with the current wallpaper across the screen, the login panel as frosted glass, and
# colours picked from the picture. Every wallpaper change updates it automatically:
#   ~/.local/bin/sddm-sync (user, on wallpaper change) -> ~/.cache/sddm-sync/{background.jpg,colors}
#   sddm-sync.service (root, on that change)        -> theme files (sync-apply.sh)
# Needs the astronaut theme installed first (sudo bash install.sh).
#
#   sudo bash astronaut-skyline.sh
# Switch to the qylock Sword theme instead: sudo bash qylock-sword.sh  (also stops the sync)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
USR=${SUDO_USER:-$(logname)}
HOME_USR=$(getent passwd "$USR" | cut -d: -f6)
DST=/usr/share/sddm/themes/sddm-astronaut-theme
SCALE=${SDDM_SCALE:-1.5}

[[ -f $DST/Themes/black_hole.conf ]] || { echo "Astronaut theme not installed; run: sudo bash install.sh"; exit 1; }

echo "==> Root watcher"
install -Dm755 "$HERE/sync-apply.sh" /usr/local/lib/sddm-sync/apply
cat > /etc/systemd/system/sddm-sync.service <<EOF
[Unit]
Description=Update the login screen from $USR's wallpaper

[Service]
Type=oneshot
ExecStart=/usr/local/lib/sddm-sync/apply $USR
ProtectSystem=strict
ReadWritePaths=$DST
ProtectHome=read-only
PrivateTmp=true
EOF
cat > /etc/systemd/system/sddm-sync.path <<EOF
[Unit]
Description=Watch $USR's prepared login-screen wallpaper

[Path]
PathChanged=$HOME_USR/.cache/sddm-sync/colors
Unit=sddm-sync.service

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now sddm-sync.path

echo "==> Making the astronaut theme (skyline variant) current"
sed -i 's|^ConfigFile=.*|ConfigFile=Themes/skyline.conf|' "$DST/metadata.desktop"
mkdir -p /etc/sddm.conf.d
rm -f /etc/sddm.conf.d/10-theme.conf   # qylock-sword.sh config
cat > /etc/sddm.conf.d/10-astronaut.conf <<EOF
[Theme]
Current=sddm-astronaut-theme
CursorTheme=breeze_cursors
CursorSize=24

[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QT_SCALE_FACTOR=$SCALE,QT_FONT_DPI=96

[Users]
RememberLastUser=true
RememberLastSession=true
EOF

echo "==> First sync from the current wallpaper"
runuser -u "$USR" -- "$HOME_USR/.local/bin/sddm-sync"
/usr/local/lib/sddm-sync/apply "$USR"

echo "Done. The login screen now follows your wallpaper (see it at the next logout or reboot)."
