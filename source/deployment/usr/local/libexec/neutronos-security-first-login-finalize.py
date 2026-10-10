#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

MARKER = "NEUTRONOS_SECURITY_FIRST_LOGIN_FINALIZE_V1"

# These are derived monitoring/baseline files. They must describe the final
# configured machine, not the pre-Setup factory image. Security configuration,
# audit history, recovery, vault, malware/quarantine, bans, and event
# fingerprints are intentionally NOT in this list. Fingerprints are preserved
# across the setup cutover so the restarted daemon does not re-import the same
# setup-boot journal records after events.json is reset.
DERIVED_NAMES = (
    "state.json",
    "events.json",
    "integrity-baseline.json",
    "package-state.json",
    "response-state.json",
    "response-history.json",
    "containment-state.json",
    "watchdog-event.json",
)


def remove_file(path: Path) -> None:
    try:
        if path.is_file() or path.is_symlink():
            path.unlink()
    except FileNotFoundError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="/", help="filesystem root; used by offline release-master installer")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    state_dir = root / "var/lib/neutronos/security-core"
    setup_dir = root / "var/lib/neutronos/setup"

    if not state_dir.is_dir():
        raise SystemExit(f"Security Core state directory missing: {state_dir}")

    removed: list[str] = []
    for name in DERIVED_NAMES:
        main_path = state_dir / name
        if main_path.exists() or main_path.is_symlink():
            remove_file(main_path)
            removed.append(name)

        # Clean abandoned atomic-write scratch files from previous runtime.
        for candidate in state_dir.glob(name + ".*"):
            if candidate.is_file() or candidate.is_symlink():
                remove_file(candidate)
                removed.append(candidate.name)

    # Firewall health is authoritative live telemetry. Keep the primary guard
    # state, but discard abandoned scratch copies only.
    for candidate in state_dir.glob("firewall-state.json.*"):
        if candidate.is_file() or candidate.is_symlink():
            remove_file(candidate)
            removed.append(candidate.name)

    # The audit chain is deliberately preserved.  Securityd verifies it on
    # restart and continues from the verified head.
    audit_path = state_dir / "audit.jsonl"
    audit_present = audit_path.is_file()

    setup_dir.mkdir(parents=True, exist_ok=True)
    finalized = setup_dir / "security-finalized-v1"
    payload = {
        "schema": 1,
        "marker": MARKER,
        "derivedStateReset": True,
        "auditPreserved": audit_present,
    }
    tmp = setup_dir / (finalized.name + ".tmp")
    tmp.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    try:
        os.chown(tmp, 0, 0)
    except PermissionError:
        if os.geteuid() == 0:
            raise
    os.replace(tmp, finalized)

    print(f"{MARKER}: removed {len(removed)} derived files; audit preserved={audit_present}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
