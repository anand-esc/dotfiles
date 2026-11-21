#!/usr/bin/env bash
# Rename the GRUB boot menu from "EndeavourOS" to "Arch Linux" and drop the removed EndeavourOS splash.
# Safe by design: the new menu is generated to a temp file and checked BEFORE replacing the real one.
# Run:  sudo bash ~/grub-arch.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }

CFG=/boot/grub/grub.cfg
DEF=/etc/default/grub
NEW=$(mktemp /boot/grub/grub.cfg.new.XXXX)
trap 'rm -f "$NEW"' EXIT

cp -a "$DEF" "$DEF.bak-endeavouros"
cp -a "$CFG" "$CFG.bak-endeavouros"
echo "Backups: $DEF.bak-endeavouros  $CFG.bak-endeavouros"

# 1. Settings
sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR='Arch Linux'|" "$DEF"
sed -i "s|^GRUB_BACKGROUND='/usr/share/endeavouros/splash.png'|#&  (removed with EndeavourOS branding)|" "$DEF"

# 2. Generate to a temp file (detects Windows via os-prober)
grub-mkconfig -o "$NEW"

# 3. Check before replacing
fail() { echo "ABORT: $*  -> nothing replaced, restoring settings"; cp -a "$DEF.bak-endeavouros" "$DEF"; exit 1; }
grep -q "^menuentry 'Arch Linux" "$NEW"           || fail "no 'Arch Linux' entry in new menu"
grep -q "vmlinuz-linux" "$NEW"                     || fail "kernel missing from new menu"
grep -q "initramfs-linux.img" "$NEW"               || fail "initramfs missing from new menu"
if grep -qi "windows" "$CFG" && ! grep -qi "windows" "$NEW"; then
    fail "Windows entry was in the old menu but not the new one"
fi

# 4. Replace
mv "$NEW" "$CFG"; chmod 600 "$CFG"; trap - EXIT
echo
echo "Done. Boot menu entries:"
grep -E "^menuentry|^submenu" "$CFG" | sed -E "s/^(menuentry|submenu) '([^']*)'.*/  - \2/"
