#!/usr/bin/env bash
# Make this EndeavourOS install look and identify as plain Arch Linux.
# Review, then run:  sudo bash ~/make-arch.sh
#
# KEPT on purpose (invisible plumbing, removing them can break boot/updates):
#   dracut, eos-dracut          -> rebuild boot files (initramfs) on kernel updates
#   endeavouros-keyring/-mirrorlist -> keep the EndeavourOS repo working for eos-dracut + yay
#   yay, downgrade              -> AUR helper + package rollback tool
# The boot menu is not touched.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

BRANDING=(
    eos-hooks                 # rewrites os-release/lsb-release to "EndeavourOS"
    welcome eos-quickstart eos-apps-info eos-log-tool eos-packagelist eos-hwtool
    eos-rankmirrors reflector-simple eos-update eos-settings-plasma
    eos-bash-shared bash-app-translate eos-translations
    endeavouros-branding endeavouros-konsole-colors eos-qogir-icons
)

step "1. Removing EndeavourOS branding and helper apps"
installed=()
for p in "${BRANDING[@]}"; do pacman -Qq "$p" &>/dev/null && installed+=("$p"); done
if ((${#installed[@]})); then
    pacman -Rns --noconfirm "${installed[@]}"
else
    echo "   nothing to remove"
fi

step "2. Restoring Arch's own os-release and lsb-release"
pacman -S --noconfirm filesystem lsb-release

step "Done. This system now identifies as:"
grep -E '^(NAME|PRETTY_NAME|ID)=' /etc/os-release
echo
echo "Kept: $(pacman -Qq dracut eos-dracut endeavouros-keyring endeavouros-mirrorlist yay 2>/dev/null | paste -sd' ')"
echo "Open a new terminal and run: fastfetch"
