#!/bin/bash
set -euo pipefail
! systemctl is-active --quiet gemini-regression055.service
systemctl stop gemini-offline-validation.service neutronos.service
install -m 0755 -o root -g root /opt/neutronos/build/NeutronShell /opt/neutronos/tests/gemini/NeutronShell.production
install -m 0755 -o root -g root /usr/local/libexec/GeminiVmShell /opt/neutronos/build/NeutronShell
mkdir -p /run/systemd/system/neutronos.service.d
printf '[Service]\nExecStart=\nExecStart=/opt/neutronos/build/NeutronShell --wifi --ssh-enabled\nRestart=no\n' > /run/systemd/system/neutronos.service.d/55-vm-validation.conf
printf '[Unit]\nOnFailure=\n' > /run/systemd/system/neutronos.service.d/56-test-exit-accounting.conf
systemctl daemon-reload
systemctl start neutronos.service
