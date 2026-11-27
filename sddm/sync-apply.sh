#!/usr/bin/env bash
# Root side of the login-screen sync. Installed to /usr/local/lib/sddm-sync/apply by
# astronaut-skyline.sh and run by sddm-sync.service whenever the user's ~/.cache/sddm-sync
# changes (prepared by ~/.local/bin/sddm-sync from the desktop wallpaper).
#
# Safety: the user's files are read *as that user* (runuser), so a symlink there can't make
# root copy anything the user couldn't read anyway; the picture must be a real JPEG and the
# colours must be #rrggbb values for known keys.
set -euo pipefail
USR="${1:?usage: apply USER}"
HOME_USR=$(getent passwd "$USR" | cut -d: -f6)
SRC="$HOME_USR/.cache/sddm-sync"
DST=/usr/share/sddm/themes/sddm-astronaut-theme
LAYOUT_W=${SDDM_LAYOUT_W:-1920}; LAYOUT_H=${SDDM_LAYOUT_H:-1200}
BASE="$DST/Themes/black_hole.conf"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
runuser -u "$USR" -- head -c 40000000 "$SRC/background.jpg" > "$tmp/bg.jpg"
runuser -u "$USR" -- head -c 8192 "$SRC/colors" > "$tmp/colors"
[[ $(file -b --mime-type "$tmp/bg.jpg") == image/jpeg ]] || { echo "sddm-sync: background is not a JPEG"; exit 1; }

args=(
    -e 's|^Background=.*|Background="Backgrounds/skyline.jpg"|'
    -e "s|^ScreenWidth=.*|ScreenWidth=\"$LAYOUT_W\"|"
    -e "s|^ScreenHeight=.*|ScreenHeight=\"$LAYOUT_H\"|"
    -e 's|^PartialBlur=.*|PartialBlur="true"|'
    -e 's|^Blur=.*|Blur="1.0"|'
    -e 's|^BlurMax=.*|BlurMax="48"|'
)
while IFS= read -r line; do
    [[ $line =~ ^([A-Za-z]+)=(#[0-9a-f]{6})$ ]] || continue
    key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
    grep -q "^$key=" "$BASE" || continue          # only keys the theme actually has
    args+=(-e "s|^$key=.*|$key=\"$val\"|")
done < "$tmp/colors"

sed "${args[@]}" "$BASE" > "$tmp/skyline.conf"
rm -f "$DST"/Backgrounds/skyline.*
install -m 644 "$tmp/bg.jpg" "$DST/Backgrounds/skyline.jpg"
install -m 644 "$tmp/skyline.conf" "$DST/Themes/skyline.conf"
echo "sddm-sync: login screen updated"
