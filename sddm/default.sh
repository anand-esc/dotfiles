#!/usr/bin/env bash
# SDDM login screen: the default Breeze theme, without profile pictures (plain username and
# password form; your username is filled in from the last login).
# Run with: sudo bash default.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }
[[ -f /usr/share/sddm/themes/breeze/Main.qml ]] || { echo "Breeze theme missing: pacman -S plasma-workspace"; exit 1; }

mkdir -p /etc/sddm.conf.d
rm -f /etc/sddm.conf.d/10-astronaut.conf
cat > /etc/sddm.conf.d/10-theme.conf <<'EOF'
[Theme]
Current=breeze
CursorTheme=breeze_cursors
CursorSize=24
# no profile pictures: never show the avatar user list, always the username/password form
EnableAvatars=false
DisableAvatarsThreshold=0

[General]
# 2880x1800 panel: scale the greeter so text and fields aren't tiny
GreeterEnvironment=QT_SCALE_FACTOR=1.5,QT_FONT_DPI=96

[Users]
RememberLastUser=true
RememberLastSession=true
EOF
echo "Done. Default Breeze login screen, no profile pictures (next logout or reboot)."
