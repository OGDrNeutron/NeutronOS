#!/usr/bin/env python3
"""Build the one deterministic distributable NeutronOS Codex package."""

from __future__ import annotations

import argparse
import hashlib
import json
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "appstore/test-packages/codex"
DEFAULT_OUTPUT = ROOT / "dist/apps/Codex-1.0.0-alpha.1-arm64.napp"
STAMP = (2026, 8, 11, 0, 0, 0)


def add_file(archive: zipfile.ZipFile, source: Path, member: str, executable: bool = False) -> None:
    info = zipfile.ZipInfo(member, STAMP)
    info.create_system = 3
    mode = 0o755 if executable else 0o644
    info.external_attr = (stat.S_IFREG | mode) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def build(output: Path) -> dict[str, object]:
    manifest = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    expected = f"Codex-{manifest['version']}-arm64.napp"
    if output.name != expected:
        raise SystemExit(f"canonical filename must be {expected}")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".napp.tmp")
    with zipfile.ZipFile(temporary, "w") as archive:
        add_file(archive, SOURCE / "manifest.json", "manifest.json")
        for source in sorted((SOURCE / "payload").rglob("*")):
            if not source.is_file() or "__pycache__" in source.parts or source.suffix == ".pyc":
                continue
            relative = source.relative_to(SOURCE).as_posix()
            executable = relative.startswith("payload/scripts/apps/")
            add_file(archive, source, relative, executable)
    temporary.replace(output)
    data = output.read_bytes()
    return {
        "path": str(output.resolve()), "filename": output.name,
        "version": manifest["version"], "id": manifest["id"],
        "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(build(args.output), indent=2, sort_keys=True))
