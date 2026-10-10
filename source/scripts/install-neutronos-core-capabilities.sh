#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(id -u)" == 0 ]] || { echo "Run as root." >&2; exit 77; }

install -d -m 0755 /usr/local/sbin /usr/lib/systemd/system-generators /usr/lib/systemd/system /etc/neutronos
install -m 0755 \
    "$ROOT/scripts/neutronos-recovery-control" \
    "$ROOT/scripts/neutronos-recovery-banner" \
    "$ROOT/scripts/neutronos-shell-failure" \
    "$ROOT/scripts/neutronos-shell-mark-stable" \
    /usr/local/sbin/
install -m 0755 "$ROOT/scripts/neutronos-recovery-generator" \
    /usr/lib/systemd/system-generators/neutronos-recovery-generator
install -m 0644 \
    "$ROOT/systemd/neutronos-recovery-console.service" \
    "$ROOT/systemd/neutronos-shell-failure.service" \
    "$ROOT/systemd/neutronos-shell-stability.service" \
    /usr/lib/systemd/system/
install -m 0644 "$ROOT/systemd/neutronos.service" /etc/systemd/system/neutronos.service
install -d -m 0755 /etc/neutronos/keys
install -m 0644 "$ROOT/deployment/etc/neutronos/keys/neutronos-release.gpg" /etc/neutronos/keys/neutronos-release.gpg
install -m 0755 "$ROOT/scripts/neutronos-release-verify" /usr/local/libexec/neutronos-release-verify
install -m 0755 "$ROOT/scripts/neutronos-napp-verify.py" /usr/local/libexec/neutronos-napp-verify
rm -f /etc/neutronos/app-store-trusted-keys.json

systemctl daemon-reload
systemd-analyze verify \
    /etc/systemd/system/neutronos.service \
    /usr/lib/systemd/system/neutronos-recovery-console.service \
    /usr/lib/systemd/system/neutronos-shell-failure.service \
    /usr/lib/systemd/system/neutronos-shell-stability.service

echo "Core capability helpers installed; no service was started, stopped, or restarted."
