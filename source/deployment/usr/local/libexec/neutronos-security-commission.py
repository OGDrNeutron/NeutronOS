#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

MARKER = "NEUTRONOS_SECURITY_PRECOMMISSION_V5"

DERIVED = (
    "state.json",
    "events.json",
    "fingerprints.json",
    "integrity-baseline.json",
    "package-state.json",
    "response-state.json",
    "response-history.json",
    "containment-state.json",
    "watchdog-event.json",
)


def rooted(root: Path, absolute: str) -> Path:
    return root / absolute.lstrip("/")


def atomic_json(path: Path, value: dict, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, mode)
    if os.geteuid() == 0:
        os.chown(tmp, 0, 0)
    os.replace(tmp, path)


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def setup_complete(setup: Path) -> bool:
    return load_json(setup).get("completed") is True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/", help="alternate root used only by package self-tests")
    args = ap.parse_args()
    root = Path(args.root).resolve()

    setup_dir = rooted(root, "/var/lib/neutronos/setup")
    state_dir = rooted(root, "/var/lib/neutronos/security-core")
    setup = setup_dir / "setup.json"
    finalized = setup_dir / "security-finalized-v1"
    commissioned = setup_dir / "security-commissioned-v2"
    old_v4 = setup_dir / "security-commissioned-v4"
    commissioning = state_dir / "commissioning.json"

    if not setup_complete(setup):
        print(f"{MARKER}: setup incomplete; commissioning deferred")
        return 0

    # The daemon's own commissioning path is the authority. Once it has written
    # security-commissioned-v2 and an authoritative state.json exists, never
    # erase that healthy state on a later service restart.
    state = load_json(state_dir / "state.json")
    if commissioned.exists() and isinstance(state.get("securityScore"), int) and state.get("heartbeat"):
        print(f"{MARKER}: authoritative Security state already commissioned")
        return 0

    if not state_dir.is_dir():
        raise SystemExit(f"Security state directory missing: {state_dir}")

    # Setup completion is sufficient to arm the daemon's built-in first-login
    # commissioning path. This marker is intentionally distinct from the
    # commissioned marker that ONLY neutron-securityd is allowed to create.
    if not finalized.exists():
        atomic_json(finalized, {
            "schema": 1,
            "marker": MARKER,
            "finalizedAt": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "reason": "setup complete; Security baseline must be established from final installed system",
        }, 0o600)

    # Repair the broken experimental commissioning state from earlier hotfixes.
    # Most importantly, NEVER create security-commissioned-v2 here. The daemon
    # checks for its absence to decide whether commission_first_login_security()
    # must run. Creating it in ExecStartPre was the reason the UI stayed 0.
    for stale in (commissioned, old_v4):
        try:
            stale.unlink()
        except FileNotFoundError:
            pass

    cutoff = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    removed: list[str] = []
    for name in DERIVED:
        path = state_dir / name
        try:
            if path.is_file() or path.is_symlink():
                path.unlink()
                removed.append(name)
        except FileNotFoundError:
            pass
        for scratch in state_dir.glob(name + ".*"):
            try:
                if scratch.is_file() or scratch.is_symlink():
                    scratch.unlink()
                    removed.append(scratch.name)
            except FileNotFoundError:
                pass

    atomic_json(commissioning, {
        "schema": 2,
        "marker": MARKER,
        "notBefore": cutoff,
        "reason": "pre-daemon cleanup complete; neutron-securityd must now create authoritative baseline/state",
        "daemonCommissionMarker": "/var/lib/neutronos/setup/security-commissioned-v2",
        "derivedStateCleared": sorted(set(removed)),
    }, 0o640)

    print(f"{MARKER}: armed daemon commissioning at {cutoff}; cleared {len(set(removed))} derived files; v2 marker intentionally ABSENT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
