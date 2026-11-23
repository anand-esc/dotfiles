#!/usr/bin/env bash
# SDDM login screen: sddm-astronaut-theme (pinned) + jake_the_dog with AI-upscaled 2880x1800 video.
# Takes effect at the next boot.   Run:  sudo bash sddm/install.sh
#
# If the login screen ever fails: Ctrl+Alt+F2, log in, then
#   sudo systemctl disable sddm; sudo systemctl enable plasmalogin; sudo reboot
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
USR=${SUDO_USER:-$(logname)}
REPO=https://github.com/Keyitdev/sddm-astronaut-theme.git
PIN=abb3163            # version tested with this setup
DST=/usr/share/sddm/themes/sddm-astronaut-theme
# Screen layout size = physical resolution / scale. Defaults match a 2880x1800 panel at 1.5x.
SCALE=${SDDM_SCALE:-1.5}; LAYOUT_W=${SDDM_LAYOUT_W:-1920}; LAYOUT_H=${SDDM_LAYOUT_H:-1200}

step "1. Packages"
pacman -S --needed --noconfirm sddm sddm-kcm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg git

step "2. Theme (upstream $PIN + overlay)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
git clone -q "$REPO" "$TMP/theme"
git -C "$TMP/theme" checkout -q "$PIN"
rm -rf "$TMP/theme/.git"
cp -r "$HERE/theme-overlay/." "$TMP/theme/"
sed -i "s|^ScreenWidth=.*|ScreenWidth=\"$LAYOUT_W\"|; s|^ScreenHeight=.*|ScreenHeight=\"$LAYOUT_H\"|" "$TMP/theme/Themes/jake_the_dog.conf"
[[ -d $DST ]] && mv "$DST" "${DST}.bak-$(date +%s)"
mkdir -p "$DST"; cp -r "$TMP/theme/." "$DST/"
chown -R root:root "$DST"; chmod -R u=rwX,go=rX "$DST"

step "3. Fonts"
mkdir -p /usr/share/fonts/sddm-astronaut
cp -r "$DST"/Fonts/. /usr/share/fonts/sddm-astronaut/
chmod -R u=rwX,go=rX /usr/share/fonts/sddm-astronaut
fc-cache -f >/dev/null

step "4. SDDM config"
mkdir -p /etc/sddm.conf.d
rm -f /etc/sddm.conf.d/10-theme.conf   # qylock-sword.sh config, if switching back
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

step "5. Preselect $USR + Hyprland"
install -d -o sddm -g sddm /var/lib/sddm
printf '[Last]\nSession=/usr/share/wayland-sessions/hyprland.desktop\nUser=%s\n' "$USR" > /var/lib/sddm/state.conf
chown sddm:sddm /var/lib/sddm/state.conf

step "6. Enable SDDM at next boot"
for dm in plasmalogin gdm lightdm ly greetd; do systemctl disable "$dm.service" 2>/dev/null || true; done
systemctl enable sddm.service
echo "display-manager -> $(readlink /etc/systemd/system/display-manager.service)"
echo "Done. Reboot to see it."
