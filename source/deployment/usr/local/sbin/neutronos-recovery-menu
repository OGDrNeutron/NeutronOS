#!/usr/bin/env python3
"""Authenticated local Recovery strategy selector for tty1."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


HELPER = "/usr/local/lib/neutronos/neutronos-update-recovery"


def catalog() -> dict:
    result = subprocess.run([HELPER, "recovery-catalog"], check=False, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Recovery catalog validation failed")
    return json.loads(result.stdout)


def confirm(prompt: str) -> bool:
    return input(prompt + " Type RESTORE to confirm: ").strip() == "RESTORE"


def main() -> int:
    state = Path("/run/neutronos/recovery-active.json")
    if not state.is_file():
        raise SystemExit("Recovery strategy selection is available only during an authenticated Recovery boot.")
    data = catalog()
    points = data.get("recoveryPoints", [])
    current = data.get("currentVersion", "Unknown")
    reinstall = data.get("reinstallCurrent")
    update = data.get("recoverAndUpdate")
    while True:
        print("\nNEUTRONOS RECOVERY\n")
        choices = []
        for point in points:
            choices.append(("point", point))
            print(f" {len(choices)}) Restore Recovery Point  {point.get('version','Unknown')}  {point.get('createdUtc','Unknown')}")
            print(f"    {point.get('identity','Unknown')}  •  Preserves user files")
        choices.append(("current", reinstall))
        print(f" {len(choices)}) Reinstall Current Version  NeutronOS Gemini {current}")
        print("    Fresh authenticated system files  •  Preserves user files" + ("" if reinstall else "  •  PACKAGE UNAVAILABLE"))
        choices.append(("update", update))
        update_version = update.get("version") if isinstance(update, dict) else "No compatible release"
        print(f" {len(choices)}) Recover & Update  {update_version}")
        print("    Fresh authenticated system files + update  •  Preserves user files" + ("" if update else "  •  UNAVAILABLE"))
        print(f" {len(choices)+1}) Return without changes")
        raw = input("\nChoose a recovery strategy: ").strip()
        if not raw.isdigit() or not (1 <= int(raw) <= len(choices) + 1):
            print("Invalid selection.")
            continue
        selected = int(raw)
        if selected == len(choices) + 1:
            return 0
        kind, value = choices[selected - 1]
        if not value:
            print("That recovery strategy is unavailable because no compatible authenticated full-system package is cached.")
            continue
        if kind == "point":
            if not confirm("Restore this verified recovery point while preserving user files?"):
                print("Cancelled; no files were changed.")
                continue
            completed = subprocess.run([HELPER, "restore-recovery-point", str(value["path"])], check=False)
            return completed.returncode
        print("This authenticated full-system package is eligible, but package application remains disabled until its production format is integrated and validated.")


if __name__ == "__main__":
    raise SystemExit(main())
