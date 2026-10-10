#!/usr/bin/env bash
set -euo pipefail

project_root=${1:-/opt/neutronos}
install -d -o root -g root -m 0755 /usr/local/lib/neutronos /usr/local/libexec /usr/local/sbin /etc/neutronos
install -d -o root -g root -m 0700 /var/lib/neutronos/network
install -o root -g root -m 0755 "$project_root/scripts/neutronos-offline-networkd.py" /usr/local/libexec/neutronos-offline-networkd.py
install -o root -g root -m 0644 "$project_root/scripts/neutronos_firewall.py" /usr/local/lib/neutronos/neutronos_firewall.py
install -o root -g root -m 0755 "$project_root/scripts/neutronos-firewall-generate" /usr/local/sbin/neutronos-firewall-generate
install -o root -g root -m 0755 "$project_root/scripts/neutronos-offline-network-control" /usr/local/sbin/neutronos-offline-network-control
install -o root -g root -m 0755 "$project_root/scripts/neutronos-hotspot-control" /usr/local/sbin/neutronos-hotspot-control
install -o root -g root -m 0644 "$project_root/systemd/neutronos-offline-network.service" /etc/systemd/system/neutronos-offline-network.service
install -o root -g root -m 0640 "$project_root/config/offline-network-authorization.json" /etc/neutronos/offline-network-authorization.json

# Preserve an existing installation's network choices and credential. Defaults
# are installed only on first deployment; they never activate a hotspot.
if [[ ! -e /etc/neutronos/offline-network.json ]]; then
    install -o root -g root -m 0600 "$project_root/config/offline-network.json" /etc/neutronos/offline-network.json
fi

printf '%s\n' 'Patch 71 sources installed. Run systemctl daemon-reload and restart only during an approved live-network validation window.'
