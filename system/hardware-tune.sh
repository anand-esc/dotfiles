#!/usr/bin/env bash
# Hardware tuning for Acer Swift Go 14 (SFG14-71) on Arch.
# Review, then run:  sudo bash ~/hardware-tune.sh
# Every step is safe to re-run. Optional steps are at the bottom, commented out.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with: sudo bash $0"; exit 1; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "1. Bluetooth: service was disabled (AX211 hardware is fine)"
systemctl enable --now bluetooth.service

step "2. thermald: Intel thermal manager (less throttling, steadier boost)"
pacman -S --needed --noconfirm thermald
systemctl enable --now thermald.service

step "3. Fingerprint reader (FPC 10a5:a305) driver"
pacman -S --needed --noconfirm fprintd
echo "   Enroll afterwards as your user:  fprintd-enroll"

step "4. Wi-Fi country = India (unlocks proper channels/power; was 'world' default)"
sed -i '/^WIRELESS_REGDOM=/d' /etc/conf.d/wireless-regdom
echo 'WIRELESS_REGDOM="IN"' >> /etc/conf.d/wireless-regdom
iw reg set IN || true

step "5. Wi-Fi power saving off (lower latency, steadier connection; small battery cost)"
install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
systemctl reload NetworkManager || true

step "6. CPU: dynamic boost on I/O wait (snappier app launches)"
install -Dm644 /dev/stdin /etc/tmpfiles.d/intel-pstate-boost.conf <<'EOF'
w /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost - - - - 1
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/intel-pstate-boost.conf

step "Done. Status:"
printf '  bluetooth: %s   thermald: %s   wifi country: %s   dynamic boost: %s\n' \
    "$(systemctl is-active bluetooth)" "$(systemctl is-active thermald)" \
    "$(iw reg get | awk '/country/{print $2; exit}' | tr -d :)" \
    "$(cat /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost)"

# ---------------------------------------------------------------------------
# OPTIONAL (uncomment to use)
# ---------------------------------------------------------------------------

# 7. Battery charge limit to 80% (AUR kernel module, needs headers; rebuilt by DKMS on kernel updates).
#    Big lifespan win if you're mostly plugged in. Run as your user, not root:
#      yay -S linux-headers acer-wmi-battery-dkms
#      echo 1 | sudo tee /sys/bus/wmi/drivers/acer-wmi-battery/health_mode

# 8. Deep sleep (S3) instead of s2idle: less battery drain overnight.
#    TEST FIRST:  echo deep | sudo tee /sys/power/mem_sleep ; systemctl suspend
#    If it wakes fine, make it permanent by adding  mem_sleep_default=deep  to the kernel cmdline.
