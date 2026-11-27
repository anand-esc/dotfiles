#!/usr/bin/env bash
# SDDM login screen: sddm-astronaut-theme's "Black hole" layout with your own wallpaper and
# colours picked from it: picture across the whole screen, login panel on the left as
# frosted glass (blurred + tinted).
# Needs the astronaut theme installed first (sudo bash install.sh).
#
#   sudo bash astronaut-skyline.sh [IMAGE]     (default: ~/Pictures/Wallpapers/973967.jpg)
# Switch to the qylock Sword theme instead: sudo bash qylock-sword.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0 [IMAGE]"; exit 1; }

USR=${SUDO_USER:-$(logname)}
HOME_USR=$(getent passwd "$USR" | cut -d: -f6)
IMG=${1:-$HOME_USR/Pictures/Wallpapers/973967.jpg}
DST=/usr/share/sddm/themes/sddm-astronaut-theme
# Screen layout size = physical resolution / scale (2880x1800 panel at 1.5x)
SCALE=${SDDM_SCALE:-1.5}; LAYOUT_W=${SDDM_LAYOUT_W:-1920}; LAYOUT_H=${SDDM_LAYOUT_H:-1200}

[[ -f $IMG ]] || { echo "No such image: $IMG"; exit 1; }
[[ -f $DST/Themes/black_hole.conf ]] || { echo "Astronaut theme not installed; run: sudo bash install.sh"; exit 1; }

echo "==> Background: $IMG"
ext=${IMG##*.}; ext=${ext,,}
rm -f "$DST"/Backgrounds/skyline.*
install -m 644 "$IMG" "$DST/Backgrounds/skyline.$ext"

echo "==> Variant: Black hole layout + skyline colours"
sed -e "s|^Background=.*|Background=\"Backgrounds/skyline.$ext\"|" \
    -e "s|^ScreenWidth=.*|ScreenWidth=\"$LAYOUT_W\"|" \
    -e "s|^ScreenHeight=.*|ScreenHeight=\"$LAYOUT_H\"|" \
    -e 's|^HeaderTextColor=.*|HeaderTextColor="#80a8f1"|' \
    -e 's|^DateTextColor=.*|DateTextColor="#c9d8fb"|' \
    -e 's|^TimeTextColor=.*|TimeTextColor="#efd5e6"|' \
    -e 's|^FormBackgroundColor=.*|FormBackgroundColor="#141332"|' \
    -e 's|^BackgroundColor=.*|BackgroundColor="#141332"|' \
    -e 's|^DimBackgroundColor=.*|DimBackgroundColor="#141332"|' \
    -e 's|^LoginFieldBackgroundColor=.*|LoginFieldBackgroundColor="#2c2752"|' \
    -e 's|^PasswordFieldBackgroundColor=.*|PasswordFieldBackgroundColor="#2c2752"|' \
    -e 's|^LoginFieldTextColor=.*|LoginFieldTextColor="#efd5e6"|' \
    -e 's|^PasswordFieldTextColor=.*|PasswordFieldTextColor="#efd5e6"|' \
    -e 's|^UserIconColor=.*|UserIconColor="#c9d8fb"|' \
    -e 's|^PasswordIconColor=.*|PasswordIconColor="#c9d8fb"|' \
    -e 's|^LoginButtonBackgroundColor=.*|LoginButtonBackgroundColor="#206dde"|' \
    -e 's|^SystemButtonsIconsColor=.*|SystemButtonsIconsColor="#c9d8fb"|' \
    -e 's|^SessionButtonTextColor=.*|SessionButtonTextColor="#c9d8fb"|' \
    -e 's|^VirtualKeyboardButtonTextColor=.*|VirtualKeyboardButtonTextColor="#c9d8fb"|' \
    -e 's|^DropdownSelectedBackgroundColor=.*|DropdownSelectedBackgroundColor="#206dde"|' \
    -e 's|^DropdownBackgroundColor=.*|DropdownBackgroundColor="#0f1230"|' \
    -e 's|^HighlightBackgroundColor=.*|HighlightBackgroundColor="#c9d8fb"|' \
    -e 's|^HighlightBorderColor=.*|HighlightBorderColor="#80a8f1"|' \
    -e 's|^HoverUserIconColor=.*|HoverUserIconColor="#80a8f1"|' \
    -e 's|^HoverPasswordIconColor=.*|HoverPasswordIconColor="#80a8f1"|' \
    -e 's|^HoverSystemButtonsIconsColor=.*|HoverSystemButtonsIconsColor="#80a8f1"|' \
    -e 's|^HoverSessionButtonTextColor=.*|HoverSessionButtonTextColor="#80a8f1"|' \
    -e 's|^HoverVirtualKeyboardButtonTextColor=.*|HoverVirtualKeyboardButtonTextColor="#80a8f1"|' \
    -e 's|^PartialBlur=.*|PartialBlur="true"|' \
    -e 's|^Blur=.*|Blur="1.0"|' \
    -e 's|^BlurMax=.*|BlurMax="48"|' \
    "$DST/Themes/black_hole.conf" > "$DST/Themes/skyline.conf"
chmod 644 "$DST/Themes/skyline.conf"
sed -i 's|^ConfigFile=.*|ConfigFile=Themes/skyline.conf|' "$DST/metadata.desktop"

echo "==> Making the astronaut theme current"
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

echo "Done. You'll see it at the next login screen (log out, or reboot)."
echo "Preview:  sddm-greeter-qt6 --test-mode --theme $DST"
