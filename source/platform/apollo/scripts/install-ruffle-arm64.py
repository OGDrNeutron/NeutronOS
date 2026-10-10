#!/usr/bin/env python3
"""Install the latest official stable Ruffle Linux ARM64 desktop release."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import stat
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

API = "https://api.github.com/repos/ruffle-rs/ruffle/releases/latest"
TARGET_DIR = Path("/opt/neutronos/bin")
TARGET = TARGET_DIR / "ruffle"
LINK = Path("/usr/local/bin/ruffle")
MAX_DOWNLOAD = 300 * 1024 * 1024


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "NeutronOS-Ruffle-Installer/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def select_asset(release: dict) -> tuple[str, str]:
    for asset in release.get("assets", []):
        name = str(asset.get("name", ""))
        lower = name.lower()
        if "linux-aarch64" in lower and lower.endswith((".tar.gz", ".tgz")):
            return name, str(asset.get("browser_download_url", ""))
    raise RuntimeError("The latest stable Ruffle release has no Linux ARM64 archive.")


def safe_member(member: tarfile.TarInfo) -> bool:
    path = Path(member.name)
    return not path.is_absolute() and ".." not in path.parts


def main() -> int:
    if os.geteuid() != 0:
        raise RuntimeError("Ruffle installation must run as root.")

    print("Installing the fullscreen kiosk runtime…", flush=True)
    subprocess.run(["apt-get", "-y", "install", "cage", "ca-certificates"], check=True)
    print("Reading the official Ruffle stable release metadata…", flush=True)
    release = fetch_json(API)
    asset_name, url = select_asset(release)
    if not url.startswith("https://github.com/"):
        raise RuntimeError("Ruffle release URL did not pass validation.")

    with tempfile.TemporaryDirectory(prefix="neutronos-ruffle-") as temporary:
        archive = Path(temporary) / asset_name
        request = urllib.request.Request(url, headers={"User-Agent": "NeutronOS-Ruffle-Installer/1.0"})
        print(f"Downloading {asset_name}…", flush=True)
        with urllib.request.urlopen(request, timeout=60) as response, archive.open("wb") as output:
            total = 0
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_DOWNLOAD:
                    raise RuntimeError("Ruffle download exceeded the safety limit.")
                output.write(chunk)

        extract_dir = Path(temporary) / "extract"
        extract_dir.mkdir()
        print("Validating and extracting Ruffle…", flush=True)
        with tarfile.open(archive, "r:gz") as package:
            members = [member for member in package.getmembers() if safe_member(member)]
            if len(members) != len(package.getmembers()):
                raise RuntimeError("Ruffle archive contained an unsafe path.")
            package.extractall(extract_dir, members=members, filter="data")

        candidates = [path for path in extract_dir.rglob("ruffle") if path.is_file()]
        if not candidates:
            raise RuntimeError("The Ruffle executable was not found in the official archive.")
        source = candidates[0]
        TARGET_DIR.mkdir(parents=True, exist_ok=True)
        temporary_target = TARGET.with_suffix(".new")
        shutil.copy2(source, temporary_target)
        temporary_target.chmod(temporary_target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        os.replace(temporary_target, TARGET)

    if LINK.exists() or LINK.is_symlink():
        LINK.unlink()
    LINK.symlink_to(TARGET)
    print(f"Ruffle installed at {TARGET}.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # noqa: BLE001
        print(f"Ruffle installation failed: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
