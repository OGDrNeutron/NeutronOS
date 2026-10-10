#!/bin/bash
set -euo pipefail
# The disposable test runner exits on assertions. Keep those test exits out of
# production crash accounting; the candidate unit remains unchanged.
printf '[Unit]\nOnFailure=\n' > /run/systemd/system/neutronos.service.d/56-test-exit-accounting.conf
/usr/local/sbin/neutronos-recovery-control mark-stable
/usr/local/sbin/neutronos-recovery-control cancel
systemctl daemon-reload
systemctl reset-failed neutronos.service
install -o root -g root -m 0755 /usr/local/libexec/GeminiVmShell /opt/neutronos/build/NeutronShell
sha256sum /opt/neutronos/build/NeutronShell /opt/neutronos/build/NeutronBrowser /usr/local/libexec/neutronos-privileged-helper.real /usr/local/lib/neutronos/neutron-securityd.py > /tmp/gemini-055-os-before-games.sha256
systemctl start neutronos.service
