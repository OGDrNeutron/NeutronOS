#!/usr/bin/env python3
"""Independent NeutronOS Security self-protection watchdog."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

STATE = Path('/var/lib/neutronos/security-core')
PENDING_EVENT = STATE / 'watchdog-event.json'
FIREWALL_STATE = STATE / 'firewall-state.json'
FIREWALL_GUARD = Path('/usr/local/lib/neutronos/neutronos-firewall-guard.py')
SECURITY_STATE = STATE / 'state.json'
SECURITY_HEARTBEAT_MAX_SECONDS = 120

PROTECTED = {
    'securityd': (Path('/usr/local/lib/neutronos/neutron-securityd.py'), STATE / 'securityd.sha256'),
    'watchdog': (Path('/usr/local/lib/neutronos/neutron-security-watchdog.py'), STATE / 'watchdog.sha256'),
    'firewall_guard': (FIREWALL_GUARD, STATE / 'firewall-guard.sha256'),
    'firewall_module': (Path('/usr/local/lib/neutronos/neutronos_firewall.py'), STATE / 'firewall-module.sha256'),
    'privileged_helper': (Path('/usr/local/sbin/neutronos-privileged-helper'), STATE / 'privileged-helper.sha256'),
    'privileged_helper_real': (Path('/usr/local/libexec/neutronos-privileged-helper.real'), STATE / 'privileged-helper-real.sha256'),
    'securityd_unit': (Path('/etc/systemd/system/neutron-securityd.service'), STATE / 'securityd-unit.sha256'),
    'watchdog_unit': (Path('/etc/systemd/system/neutron-security-watchdog.service'), STATE / 'watchdog-unit.sha256'),
    'firewall_guard_unit': (Path('/etc/systemd/system/neutronos-firewall-guard.service'), STATE / 'firewall-guard-unit.sha256'),
    'nftables_compat_config': (Path('/etc/nftables.conf'), STATE / 'nftables-conf.sha256'),
    'firewall_normal_policy': (Path('/etc/neutronos/firewall-normal.nft'), STATE / 'firewall-normal-policy.sha256'),
    'remote_security_isolation': (Path('/etc/systemd/system/neutron-remote-service.service.d/20-neutronos-security-isolation.conf'), STATE / 'remote-security-isolation.sha256'),
}


def stamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def parse_stamp(value: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        return parsed.astimezone(timezone.utc)
    except Exception:
        return None


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def record(action: str, details: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    document = json.dumps({'timestamp': stamp(), 'action': action, 'details': details}, sort_keys=True)
    temporary = PENDING_EVENT.with_suffix('.tmp')
    temporary.write_text(document, encoding='utf-8')
    temporary.chmod(0o640)
    temporary.replace(PENDING_EVENT)


def active(unit: str) -> bool:
    return subprocess.run(['systemctl', 'is-active', '--quiet', unit], check=False).returncode == 0


def restart(unit: str) -> bool:
    subprocess.run(['systemctl', 'restart', unit], check=False)
    return active(unit)


def load_firewall_state() -> dict:
    try:
        value = json.loads(FIREWALL_STATE.read_text(encoding='utf-8'))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return {}


def firewall_state_stale(value: dict, seconds: int = 25) -> bool:
    updated = parse_stamp(str(value.get('updatedAt') or ''))
    if updated is None:
        return True
    return (datetime.now(timezone.utc) - updated).total_seconds() > seconds




def security_state_stale(seconds: int = SECURITY_HEARTBEAT_MAX_SECONDS) -> bool:
    try:
        age = time.time() - SECURITY_STATE.stat().st_mtime
    except OSError:
        return True
    return age > seconds

def request_firewall_repair(reason: str) -> dict:
    result = subprocess.run(
        ['/usr/bin/python3', str(FIREWALL_GUARD), '--apply-once'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
        check=False,
    )
    state = load_firewall_state()
    record('firewall_repair_requested', {
        'reason': reason,
        'returnCode': result.returncode,
        'protectionState': state.get('protectionState', 'UNKNOWN'),
        'output': result.stdout[-1200:],
    })
    return state


def verify_integrity() -> tuple[bool, list[dict]]:
    failures: list[dict] = []
    for name, (source, reference) in PROTECTED.items():
        try:
            expected = reference.read_text(encoding='utf-8').strip()
            actual = digest(source)
        except Exception as exc:
            failures.append({'component': name, 'error': str(exc)})
            continue
        if not expected or actual != expected:
            failures.append({'component': name, 'expected': expected, 'actual': actual})
    return not failures, failures


def self_test() -> int:
    ok, failures = verify_integrity()
    print(json.dumps({'ok': ok, 'protectedComponents': sorted(PROTECTED), 'failures': failures}, sort_keys=True))
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    last_integrity_signature = ''
    last_firewall_state = ''
    while True:
        if not active('neutronos-firewall-guard.service'):
            recovered = restart('neutronos-firewall-guard.service')
            record('firewall_guard_restart_requested', {'activeAfter': recovered})

        firewall = load_firewall_state()
        firewall_state = str(firewall.get('protectionState') or 'UNKNOWN').upper()
        stale = firewall_state_stale(firewall)
        if stale or firewall_state == 'CRITICAL':
            firewall = request_firewall_repair('stale-guard-state' if stale else 'critical-firewall-state')
            firewall_state = str(firewall.get('protectionState') or 'UNKNOWN').upper()

        if firewall_state != last_firewall_state:
            last_firewall_state = firewall_state
            record('firewall_watchdog_state', {
                'protectionState': firewall_state,
                'firewallActive': bool(firewall.get('firewallActive', False)),
                'reason': str(firewall.get('lastError') or firewall.get('reason') or ''),
            })
            priority = 'auth.crit' if firewall_state == 'CRITICAL' else 'auth.warning'
            subprocess.run([
                'logger', '-p', priority,
                f'NeutronOS firewall protection state: {firewall_state}'
            ], check=False)

        security_active = active('neutron-securityd.service')
        heartbeat_stale = security_state_stale()
        if not security_active or heartbeat_stale:
            recovered = restart('neutron-securityd.service')
            record('security_daemon_restart_requested', {
                'activeBefore': security_active,
                'heartbeatStale': heartbeat_stale,
                'activeAfter': recovered,
            })

        try:
            ok, failures = verify_integrity()
            signature = hashlib.sha256(json.dumps(failures, sort_keys=True).encode()).hexdigest() if failures else ''
            if not ok and signature != last_integrity_signature:
                last_integrity_signature = signature
                record('security_integrity_mismatch', {'failures': failures})
                subprocess.run([
                    'logger', '-p', 'auth.crit',
                    'NeutronOS critical Security component integrity mismatch detected'
                ], check=False)
            elif ok:
                last_integrity_signature = ''
        except Exception as exc:
            record('watchdog_check_error', {'error': str(exc)})

        time.sleep(10)


if __name__ == '__main__':
    raise SystemExit(main())
