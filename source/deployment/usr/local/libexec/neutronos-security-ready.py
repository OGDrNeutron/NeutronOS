#!/usr/bin/env python3
from __future__ import annotations
import json
import subprocess
import time
from pathlib import Path

STATE = Path('/var/lib/neutronos/security-core/state.json')

subprocess.run(['/usr/bin/systemctl', 'start', 'neutron-securityd.service'], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def ready() -> bool:
    try:
        value = json.loads(STATE.read_text(encoding='utf-8'))
        stats = value.get('stats', {}) if isinstance(value, dict) else {}
        return (
            isinstance(value.get('securityScore'), int) and
            isinstance(value.get('auditValid'), bool) and
            bool(value.get('heartbeat')) and
            str(stats.get('firewallProtectionState', '')).upper() in {'SECURE', 'DEGRADED', 'CRITICAL'}
        )
    except Exception:
        return False

for _ in range(45):
    if ready():
        print('NeutronOS Security: authoritative state ready')
        raise SystemExit(0)
    time.sleep(1)

# One recovery restart, then one short final wait. Do not brick the shell if the
# daemon is genuinely unhealthy; the UI will still surface that failure.
subprocess.run(['/usr/bin/systemctl', 'restart', 'neutron-securityd.service'], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(15):
    if ready():
        print('NeutronOS Security: authoritative state ready after restart')
        raise SystemExit(0)
    time.sleep(1)
print('NeutronOS Security: state readiness timed out')
raise SystemExit(0)
