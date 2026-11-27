#!/usr/bin/env bash
# Stop announcing this laptop's name on networks (every network, not just one):
#   - DHCP: don't send the hostname to routers (NetworkManager)
#   - mDNS/LLMNR: resolve other devices, but never publish or answer for ourselves
#   - Avahi: keep discovering printers etc., stop publishing our name and services
# Run with: sudo bash hide-hostname.sh      (Wi-Fi reconnects once, a few seconds)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }

install -Dm644 /dev/stdin /etc/NetworkManager/conf.d/20-hide-hostname.conf <<'EOF'
# Don't send the hostname to DHCP servers, don't announce it via mDNS/LLMNR
[connection]
ipv4.dhcp-send-hostname=0
ipv6.dhcp-send-hostname=0
connection.mdns=1
connection.llmnr=1
EOF
# (connection.mdns/llmnr = 1 means "resolve only": look others up, never announce)

install -Dm644 /dev/stdin /etc/systemd/resolved.conf.d/20-hide-hostname.conf <<'EOF'
[Resolve]
MulticastDNS=resolve
LLMNR=resolve
EOF

if [[ -f /etc/avahi/avahi-daemon.conf ]]; then
    sed -i -E 's/^#?\s*disable-publishing=.*/disable-publishing=yes/' /etc/avahi/avahi-daemon.conf
    grep -q '^disable-publishing=yes' /etc/avahi/avahi-daemon.conf ||
        sed -i '/^\[publish\]/a disable-publishing=yes' /etc/avahi/avahi-daemon.conf
    systemctl try-restart avahi-daemon
fi

systemctl restart systemd-resolved
systemctl reload NetworkManager
# reconnect so the router gets a DHCP request without the name
dev=$(nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2=="wifi" && $3=="connected"{print $1; exit}')
[[ -n $dev ]] && nmcli device reapply "$dev" >/dev/null 2>&1 || true
[[ -n $dev ]] && { nmcli device disconnect "$dev" >/dev/null; sleep 2; nmcli device connect "$dev" >/dev/null; }
echo "Done. This laptop no longer announces its name on networks."
