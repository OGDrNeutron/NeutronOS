#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import json
import os
import sys
from pathlib import Path

MARKER = "NEUTRONOS_SECURITY_AUTHORITATIVE_BOOTSTRAP_V1"
STATE_DIR = Path("/var/lib/neutronos/security-core")
SETUP_DIR = Path("/var/lib/neutronos/setup")
FINALIZED = SETUP_DIR / "security-finalized-v1"
COMMISSIONED = SETUP_DIR / "security-commissioned-v2"
STATE = STATE_DIR / "state.json"
DAEMON = Path("/usr/local/lib/neutronos/neutron-securityd.py")
POLICY = Path("/etc/neutronos/security-authorization.json")
PROJECT = Path("/opt/neutronos")


def load_state() -> dict:
    try:
        value = json.loads(STATE.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def state_ready(value: dict) -> bool:
    stats = value.get("stats", {}) if isinstance(value, dict) else {}
    if not isinstance(stats, dict):
        stats = {}
    return (
        isinstance(value.get("securityScore"), int)
        and isinstance(value.get("auditValid"), bool)
        and bool(value.get("heartbeat"))
        and str(stats.get("firewallProtectionState", "")).upper()
            in {"SECURE", "DEGRADED", "CRITICAL"}
    )


def main() -> int:
    # Before First Boot Setup is finalized, let the regular daemon run normally.
    if not FINALIZED.exists():
        print(f"{MARKER}: setup not finalized; normal daemon startup")
        return 0

    current = load_state()
    if COMMISSIONED.exists() and state_ready(current):
        print(f"{MARKER}: authoritative state already ready; score={current.get('securityScore')}")
        return 0

    # If an earlier failed commissioning left only a marker, re-arm it.
    if COMMISSIONED.exists() and not state_ready(current):
        COMMISSIONED.unlink()

    sys.path.insert(0, "/usr/local/lib/neutronos")
    spec = importlib.util.spec_from_file_location("neutronos_securityd_bootstrap", DAEMON)
    if spec is None or spec.loader is None:
        raise SystemExit(f"unable to load {DAEMON}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    policy = module.AuthorizationPolicy.load(POLICY, require_root_owner=True)
    core = module.SecurityCore(
        STATE_DIR,
        PROJECT,
        "neutronos",
        "neutronos",
        policy,
        legacy_json_requests=False,
    )

    # The finalizer already discarded derived setup-time state. Use the
    # daemon's actual scan API to rebuild package/integrity baselines and
    # calculate firewall/audit health; never synthesize a passing score.
    core.scan()

    result = load_state()
    if not state_ready(result):
        raise SystemExit("commissioning completed without authoritative state.json")

    module.atomic_json(COMMISSIONED, {
        "schema": 2, "commissionedAt": module.utc_now(),
        "marker": MARKER, "auditValid": result.get("auditValid"),
    }, 0o600)
    print(
        f"{MARKER}: READY score={result.get('securityScore')} "
        f"auditValid={result.get('auditValid')} "
        f"firewall={result.get('stats', {}).get('firewallProtectionState')}"
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
