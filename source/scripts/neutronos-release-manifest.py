#!/usr/bin/env python3
"""Generate NeutronOS' deterministic local release-integrity manifest."""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "config" / "release-manifest.sha256"
TREES = ("config", "qml", "scripts", "src", "themes", "services", "platform/gemini")
EXCLUDED_PARTS = {"__pycache__", ".patch-backups", "state", "build"}


def included(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if path == OUTPUT or not path.is_file() or any(part in EXCLUDED_PARTS for part in relative.parts):
        return False
    # Installed games are integrity-covered, but personal ROM payloads are user data.
    return relative.parts[:4] != ("qml", "apps", "games", "roms")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main() -> int:
    files = [ROOT / "CMakeLists.txt"]
    for tree in TREES:
        base = ROOT / tree
        if base.is_dir():
            files.extend(path for path in base.rglob("*") if included(path))
    files = sorted(set(files), key=lambda item: item.relative_to(ROOT).as_posix())
    lines = [f"{digest(path)}  {path.relative_to(ROOT).as_posix()}\n" for path in files]
    descriptor, temporary = tempfile.mkstemp(prefix=".release-manifest.", dir=OUTPUT.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.writelines(lines)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, OUTPUT)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    print(f"Generated {OUTPUT.relative_to(ROOT)} with {len(files)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
