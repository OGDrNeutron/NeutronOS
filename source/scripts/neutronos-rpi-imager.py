#!/usr/bin/env python3
"""NeutronOS controller-first Raspberry Pi image catalog and writer.

The script is invoked only by the privileged StorageManager. It never permits the
active root disk as a target. Progress is emitted as one-line JSON records prefixed
with NEUTRON_PROGRESS so the QML progress modal can display exact phases, bytes,
speed, ETA, verification, completion, and errors.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import gzip
import hashlib
import json
import lzma
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from typing import Any, BinaryIO, Dict, Iterable, List, Optional, Tuple

OFFICIAL_CATALOG = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json"
NEUTRON_REPOSITORY = "https://github.com/OGDrNeutron/NeutronOS"
NEUTRON_RELEASE_API = "https://api.github.com/repos/OGDrNeutron/NeutronOS/releases/latest"
USER_AGENT = "NeutronOS-Imager/1.0 (+https://github.com/OGDrNeutron/NeutronOS)"
CHUNK = 4 * 1024 * 1024


def emit(phase: str, **values: Any) -> None:
    payload: Dict[str, Any] = {"phase": phase}
    payload.update(values)
    print("NEUTRON_PROGRESS " + json.dumps(payload, separators=(",", ":")), flush=True)


def fail(message: str) -> "NoReturn":
    emit("ERROR", message=message, verification="FAILED")
    raise RuntimeError(message)


def url_json(url: str, timeout: int = 25) -> Dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = response.read()
    parsed = json.loads(data.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError(f"JSON root from {url} is not an object")
    return parsed


def stable_id(name: str, url: str) -> str:
    return hashlib.sha256((name + "\n" + url).encode("utf-8")).hexdigest()[:20]


def detected_device_code() -> str:
    try:
        model = pathlib.Path("/proc/device-tree/model").read_bytes().replace(b"\0", b"").decode("utf-8", "ignore").lower()
    except OSError:
        return ""
    if "raspberry pi 5" in model or "compute module 5" in model:
        return "pi5"
    if "raspberry pi 4" in model or "compute module 4" in model or "pi 400" in model:
        return "pi4"
    if "zero 2" in model:
        return "pi0_2"
    if "raspberry pi 3" in model or "compute module 3" in model:
        return "pi3"
    if "raspberry pi 2" in model:
        return "pi2"
    if "zero" in model:
        return "pi0"
    return ""


def device_compatible(entry: Dict[str, Any], code: str) -> bool:
    if not code:
        return True
    devices = entry.get("devices")
    if not isinstance(devices, list) or not devices:
        return True
    normalized = {str(item).lower().replace("-", "_") for item in devices}
    aliases = {
        "pi5": {"pi5", "pi500", "cm5"},
        "pi4": {"pi4", "pi400", "cm4", "cm4s"},
        "pi0_2": {"pi0_2", "pi02", "pi3"},
        "pi3": {"pi3", "cm3", "cm3plus"},
        "pi2": {"pi2"},
        "pi0": {"pi0", "pi1"},
    }
    return bool(normalized & aliases.get(code, {code}))


def normalize_entry(raw: Dict[str, Any], group: str = "Other") -> Optional[Dict[str, Any]]:
    url = str(raw.get("url") or "").strip()
    name = str(raw.get("name") or raw.get("title") or "").strip()
    if not url or not name:
        return None
    return {
        "id": stable_id(name, url),
        "name": name,
        "description": str(raw.get("description") or "Operating system image").strip(),
        "group": str(raw.get("group") or group or "Other").strip(),
        "url": url,
        "website": str(raw.get("website") or "").strip(),
        "icon": str(raw.get("icon") or "").strip(),
        "releaseDate": str(raw.get("release_date") or "").strip(),
        "downloadBytes": int(raw.get("image_download_size") or raw.get("download_size") or 0),
        "extractBytes": int(raw.get("extract_size") or 0),
        "extractSha256": str(raw.get("extract_sha256") or "").lower().strip(),
        "downloadSha256": str(raw.get("image_download_sha256") or raw.get("download_sha256") or "").lower().strip(),
        "architecture": str(raw.get("architecture") or "").strip(),
        "initFormat": str(raw.get("init_format") or "").strip(),
        "devices": raw.get("devices") if isinstance(raw.get("devices"), list) else [],
        "available": True,
        "source": "Raspberry Pi Imager",
    }


def flatten_catalog(document: Dict[str, Any], base_url: str, seen: set[str], depth: int = 0) -> List[Dict[str, Any]]:
    if depth > 5:
        return []
    result: List[Dict[str, Any]] = []
    entries = document.get("os_list")
    if not isinstance(entries, list):
        entries = document.get("subitems") if isinstance(document.get("subitems"), list) else []
    for raw in entries:
        if not isinstance(raw, dict):
            continue
        group = str(raw.get("name") or raw.get("group") or "Other")
        entry = normalize_entry(raw, str(raw.get("group") or "Other"))
        if entry:
            result.append(entry)
        inline = raw.get("subitems")
        if isinstance(inline, list):
            result.extend(flatten_catalog({"os_list": inline}, base_url, seen, depth + 1))
        sub_url = str(raw.get("subitems_url") or "").strip()
        if sub_url:
            absolute = urllib.parse.urljoin(base_url, sub_url)
            if absolute not in seen:
                seen.add(absolute)
                try:
                    result.extend(flatten_catalog(url_json(absolute), absolute, seen, depth + 1))
                except Exception:
                    pass
    return result


def neutron_entry() -> Dict[str, Any]:
    base: Dict[str, Any] = {
        "id": "neutronos",
        "name": "NeutronOS",
        "description": "Controller-first NeutronOS image for Raspberry Pi",
        "group": "NeutronOS",
        "url": "",
        "website": NEUTRON_REPOSITORY,
        "icon": "",
        "releaseDate": "",
        "downloadBytes": 0,
        "extractBytes": 0,
        "extractSha256": "",
        "downloadSha256": "",
        "architecture": "arm64",
        "initFormat": "systemd",
        "devices": ["pi4", "pi5"],
        "available": False,
        "source": "NeutronOS GitHub Releases",
        "accent": "green",
    }
    try:
        release = url_json(NEUTRON_RELEASE_API)
        assets = release.get("assets") if isinstance(release.get("assets"), list) else []
        candidates: List[Dict[str, Any]] = []
        for asset in assets:
            if not isinstance(asset, dict):
                continue
            name = str(asset.get("name") or "")
            lower = name.lower()
            if any(lower.endswith(suffix) for suffix in (".img.xz", ".img.gz", ".img.zip", ".img", ".iso.xz", ".iso")):
                candidates.append(asset)
        if candidates:
            candidates.sort(key=lambda a: ("arm64" not in str(a.get("name", "")).lower(), -int(a.get("size") or 0)))
            asset = candidates[0]
            base.update({
                "url": str(asset.get("browser_download_url") or ""),
                "releaseDate": str(release.get("published_at") or "")[:10],
                "downloadBytes": int(asset.get("size") or 0),
                "available": bool(asset.get("browser_download_url")),
                "description": str(release.get("name") or "NeutronOS release image"),
            })
    except Exception:
        pass
    return base


def fallback_lite() -> Dict[str, Any]:
    # Official Raspberry Pi OS Lite 64-bit release listed on 2026-06-18.
    url = "https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-06-19/2026-06-18-raspios-trixie-arm64-lite.img.xz"
    return {
        "id": stable_id("Raspberry Pi OS Lite (64-bit)", url),
        "name": "Raspberry Pi OS Lite (64-bit)",
        "description": "Official Raspberry Pi OS Lite with no desktop environment",
        "group": "Raspberry Pi OS",
        "url": url,
        "website": "https://www.raspberrypi.com/software/operating-systems/",
        "icon": "",
        "releaseDate": "2026-06-18",
        "downloadBytes": 501 * 1024 * 1024,
        "extractBytes": 2840 * 1024 * 1024,
        "extractSha256": "acff736ca7945e3b305f07cda4abdb870910e12634991da69783611756e381b3",
        "downloadSha256": "",
        "architecture": "arm64",
        "initFormat": "systemd",
        "devices": ["pi3", "pi4", "pi5", "pi400", "cm3", "cm4", "cm5", "pi0_2"],
        "available": True,
        "source": "Raspberry Pi",
    }


def catalog_command() -> int:
    code = detected_device_code()
    entries: List[Dict[str, Any]] = []
    error = ""
    try:
        doc = url_json(OFFICIAL_CATALOG)
        entries = flatten_catalog(doc, OFFICIAL_CATALOG, {OFFICIAL_CATALOG})
    except Exception as exc:
        error = str(exc)

    dedup: Dict[str, Dict[str, Any]] = {}
    for entry in entries:
        if device_compatible(entry, code):
            dedup[entry["url"]] = entry
    entries = list(dedup.values())

    def is_lite64(item: Dict[str, Any]) -> bool:
        name = str(item.get("name", "")).lower()
        arch = str(item.get("architecture", "")).lower()
        return "raspberry pi os" in name and "lite" in name and ("64" in name or "arm64" in arch or "armv8" in arch)

    lite = next((item for item in entries if is_lite64(item)), None)
    if lite is None:
        lite = fallback_lite()
    else:
        entries.remove(lite)
        lite["name"] = "Raspberry Pi OS Lite (64-bit)"
        lite["group"] = "Raspberry Pi OS"
        if not lite.get("initFormat"):
            lite["initFormat"] = "systemd"

    entries.sort(key=lambda item: (str(item.get("group", "")).lower(), str(item.get("name", "")).lower()))
    output = {
        "ok": True,
        "device": code,
        "warning": error,
        "osList": [neutron_entry(), lite] + entries[:250],
    }
    print(json.dumps(output, separators=(",", ":")))
    return 0


def run_json(command: List[str], timeout: int = 30) -> Dict[str, Any]:
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    return json.loads(result.stdout)


def block_inventory() -> Tuple[Dict[str, Dict[str, Any]], str]:
    data = run_json(["lsblk", "-J", "-b", "-o", "PATH,TYPE,PKNAME,MOUNTPOINTS,FSTYPE,LABEL,PARTLABEL,SIZE"])
    by_path: Dict[str, Dict[str, Any]] = {}

    def walk(nodes: Iterable[Dict[str, Any]], parent: str = "") -> None:
        for node in nodes:
            path = str(node.get("path") or "")
            if path:
                node["parent_path"] = parent
                by_path[path] = node
            children = node.get("children") if isinstance(node.get("children"), list) else []
            walk(children, path)

    walk(data.get("blockdevices") or [])
    root_source = subprocess.run(["findmnt", "-n", "-o", "SOURCE", "/"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
    root_source = os.path.realpath(root_source)
    current = root_source
    while current in by_path and str(by_path[current].get("type")) != "disk":
        parent = str(by_path[current].get("parent_path") or "")
        if not parent:
            break
        current = parent
    return by_path, current


def validate_target(target: str, expected_size: int) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Any]]:
    target = os.path.realpath(target)
    inventory, root_disk = block_inventory()
    node = inventory.get(target)
    if not node or str(node.get("type")) != "disk":
        fail("The target must be a whole block disk, not a partition.")
    if target == root_disk:
        fail("The active NeutronOS boot/root disk can never be flashed.")
    if expected_size and int(node.get("size") or 0) < expected_size:
        fail("The selected target disk is smaller than the expanded image.")
    return inventory, node


def child_partitions(inventory: Dict[str, Dict[str, Any]], target: str) -> List[str]:
    return [path for path, node in inventory.items() if str(node.get("parent_path") or "") == target]


def unmount_target(inventory: Dict[str, Dict[str, Any]], target: str) -> None:
    emit("UNMOUNT", percent=0, message="Unmounting target volumes")
    paths = child_partitions(inventory, target)
    paths.append(target)
    for path in reversed(paths):
        node = inventory.get(path, {})
        mounts = node.get("mountpoints")
        if not isinstance(mounts, list):
            mounts = [node.get("mountpoint")] if node.get("mountpoint") else []
        for mount in mounts:
            if mount:
                subprocess.run(["umount", str(mount)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def filename_from_url(url: str) -> str:
    name = pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
    return name or "image.img.xz"


def download(url: str, destination: pathlib.Path, expected_size: int, expected_sha: str) -> pathlib.Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    emit("DOWNLOAD", percent=0, bytes=0, total=expected_size, message="Downloading image")
    started = time.monotonic()
    digest = hashlib.sha256()
    received = 0
    try:
        with urllib.request.urlopen(request, timeout=45) as response, open(partial, "wb") as out:
            total = int(response.headers.get("Content-Length") or expected_size or 0)
            while True:
                data = response.read(CHUNK)
                if not data:
                    break
                out.write(data)
                digest.update(data)
                received += len(data)
                elapsed = max(0.001, time.monotonic() - started)
                speed = received / elapsed
                eta = int((total - received) / speed) if total and speed > 0 and received < total else 0
                percent = int(received * 100 / total) if total else -1
                emit("DOWNLOAD", percent=percent, bytes=received, total=total,
                     speed=f"{speed:.0f} B/s", eta=eta, message="Downloading image")
            out.flush()
            os.fsync(out.fileno())
    except Exception:
        partial.unlink(missing_ok=True)
        raise
    actual = digest.hexdigest()
    if expected_sha and actual.lower() != expected_sha.lower():
        partial.unlink(missing_ok=True)
        fail(f"Downloaded image checksum mismatch. Expected {expected_sha}, received {actual}.")
    os.replace(partial, destination)
    emit("DOWNLOAD_COMPLETE", percent=100, bytes=received, total=received,
         verification="PASSED" if expected_sha else "COMPUTED", sha256=actual,
         message="Image download complete")
    return destination


def source_stream(path: pathlib.Path) -> Tuple[BinaryIO, int, Optional[zipfile.ZipFile]]:
    lower = path.name.lower()
    if lower.endswith(".xz"):
        return lzma.open(path, "rb"), 0, None
    if lower.endswith(".gz"):
        return gzip.open(path, "rb"), 0, None
    if lower.endswith(".zip"):
        archive = zipfile.ZipFile(path, "r")
        candidates = [info for info in archive.infolist() if info.filename.lower().endswith((".img", ".iso"))]
        if not candidates:
            archive.close()
            fail("The ZIP archive contains no .img or .iso file.")
        member = max(candidates, key=lambda item: item.file_size)
        return archive.open(member, "r"), int(member.file_size), archive
    return open(path, "rb"), int(path.stat().st_size), None


def verify_source(path: pathlib.Path, expected_extract_size: int, expected_extract_sha: str) -> Tuple[int, str]:
    stream, stream_size, archive = source_stream(path)
    total = expected_extract_size or stream_size
    checked = 0
    digest = hashlib.sha256()
    started = time.monotonic()
    emit("VERIFY_DOWNLOAD", percent=0, bytes=0, total=total, verification="RUNNING", message="Verifying downloaded image")
    try:
        with stream:
            while True:
                data = stream.read(CHUNK)
                if not data:
                    break
                digest.update(data)
                checked += len(data)
                elapsed = max(0.001, time.monotonic() - started)
                speed = checked / elapsed
                eta = int((total - checked) / speed) if total and speed > 0 and checked < total else 0
                percent = int(checked * 100 / total) if total else -1
                emit("VERIFY_DOWNLOAD", percent=percent, bytes=checked, total=total,
                     speed=f"{speed:.0f} B/s", eta=eta, verification="RUNNING",
                     message="Verifying downloaded image")
    finally:
        if archive is not None:
            archive.close()
    actual = digest.hexdigest()
    if expected_extract_size and checked != expected_extract_size:
        fail(f"Expanded image size mismatch. Expected {expected_extract_size} bytes, received {checked} bytes.")
    if expected_extract_sha and actual.lower() != expected_extract_sha.lower():
        fail(f"Downloaded image verification failed. Expected extracted SHA-256 {expected_extract_sha}, received {actual}.")
    emit("VERIFY_DOWNLOAD", percent=100, bytes=checked, total=checked,
         verification="PASSED" if expected_extract_sha else "COMPUTED", sha256=actual,
         message="Downloaded image verified")
    return checked, actual


def write_image(path: pathlib.Path, target: str, expected_extract_size: int, expected_extract_sha: str) -> Tuple[int, str]:
    stream, stream_size, archive = source_stream(path)
    total = expected_extract_size or stream_size
    written = 0
    digest = hashlib.sha256()
    started = time.monotonic()
    emit("WRITE", percent=0, bytes=0, total=total, message="Writing image to target")
    try:
        with stream, open(target, "wb", buffering=0) as out:
            while True:
                data = stream.read(CHUNK)
                if not data:
                    break
                out.write(data)
                digest.update(data)
                written += len(data)
                elapsed = max(0.001, time.monotonic() - started)
                speed = written / elapsed
                eta = int((total - written) / speed) if total and speed > 0 and written < total else 0
                percent = int(written * 100 / total) if total else -1
                emit("WRITE", percent=percent, bytes=written, total=total,
                     speed=f"{speed:.0f} B/s", eta=eta, message="Writing image to target")
            os.fsync(out.fileno())
    finally:
        if archive is not None:
            archive.close()
    actual = digest.hexdigest()
    if expected_extract_sha and actual.lower() != expected_extract_sha.lower():
        fail(f"Written image verification failed. Expected extracted SHA-256 {expected_extract_sha}, received {actual}.")
    emit("VERIFY", percent=100, bytes=written, total=written,
         verification="PASSED" if expected_extract_sha else "COMPUTED", sha256=actual,
         message="Image data verified")
    return written, actual


def wait_for_partitions(target: str, seconds: int = 15) -> Tuple[Dict[str, Dict[str, Any]], List[str]]:
    subprocess.run(["partprobe", target], check=False)
    subprocess.run(["udevadm", "settle"], check=False)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        inventory, _ = block_inventory()
        parts = child_partitions(inventory, target)
        if parts:
            return inventory, parts
        time.sleep(1)
    inventory, _ = block_inventory()
    return inventory, child_partitions(inventory, target)


def password_hash(password: str) -> str:
    process = subprocess.run(["openssl", "passwd", "-6", "-stdin"], input=password + "\n", text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    value = process.stdout.strip()
    if not value.startswith("$6$"):
        fail("Could not create the password hash for image setup.")
    return value


def safe_write(path: pathlib.Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".neutron.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def apply_setup(target: str, setup: Dict[str, Any], os_entry: Dict[str, Any]) -> None:
    if not setup:
        emit("SETUP_SKIPPED", percent=100, message="No image setup options selected")
        return
    init_format = str(os_entry.get("initFormat") or "").lower()
    name = str(os_entry.get("name") or "").lower()
    if init_format not in ("systemd", "rpi-preseed") and "raspberry pi os" not in name and "neutronos" not in name:
        emit("SETUP_SKIPPED", percent=100, message="This operating system does not advertise compatible setup customization")
        return

    emit("SETUP", percent=0, message="Applying first-boot settings")
    inventory, parts = wait_for_partitions(target)
    if not parts:
        fail("The image was written, but its partitions did not appear for setup customization.")

    boot_part = ""
    root_part = ""
    largest_ext4 = (0, "")
    for path in parts:
        node = inventory.get(path, {})
        fs = str(node.get("fstype") or "").lower()
        label = (str(node.get("label") or "") + " " + str(node.get("partlabel") or "")).lower()
        size = int(node.get("size") or 0)
        if not boot_part and ("boot" in label or fs in ("vfat", "fat", "fat32")):
            boot_part = path
        if fs == "ext4" and size > largest_ext4[0]:
            largest_ext4 = (size, path)
        if not root_part and "root" in label and fs in ("ext4", "btrfs"):
            root_part = path
    if not root_part:
        root_part = largest_ext4[1]
    if not boot_part or not root_part:
        fail("The image was written, but compatible boot and root filesystems could not be identified for setup.")

    temp_root = pathlib.Path(tempfile.mkdtemp(prefix="neutronos-imager-", dir="/run"))
    boot_mount = temp_root / "boot"
    root_mount = temp_root / "root"
    boot_mount.mkdir()
    root_mount.mkdir()
    mounted: List[pathlib.Path] = []
    try:
        subprocess.run(["mount", root_part, str(root_mount)], check=True)
        mounted.append(root_mount)
        subprocess.run(["mount", boot_part, str(boot_mount)], check=True)
        mounted.append(boot_mount)

        hostname = re.sub(r"[^a-zA-Z0-9-]", "", str(setup.get("hostname") or "").strip())[:63]
        username = re.sub(r"[^a-z0-9_-]", "", str(setup.get("username") or "").strip().lower())[:32]
        password = str(setup.get("password") or "")
        timezone = str(setup.get("timezone") or "UTC").strip() or "UTC"
        locale = str(setup.get("locale") or "en_US.UTF-8").strip() or "en_US.UTF-8"
        keyboard = re.sub(r"[^a-zA-Z0-9_-]", "", str(setup.get("keyboard") or "us").strip()) or "us"

        if bool(setup.get("ssh")):
            (boot_mount / "ssh").touch(exist_ok=True)
        else:
            (boot_mount / "ssh").unlink(missing_ok=True)

        if username and password:
            safe_write(boot_mount / "userconf.txt", f"{username}:{password_hash(password)}\n", 0o600)

        if hostname:
            safe_write(root_mount / "etc/hostname", hostname + "\n")
            hosts_path = root_mount / "etc/hosts"
            if hosts_path.exists():
                hosts = hosts_path.read_text(encoding="utf-8", errors="replace")
                if re.search(r"^127\.0\.1\.1\s+", hosts, flags=re.M):
                    hosts = re.sub(r"^127\.0\.1\.1\s+.*$", f"127.0.1.1\t{hostname}", hosts, flags=re.M)
                else:
                    hosts += f"\n127.0.1.1\t{hostname}\n"
                safe_write(hosts_path, hosts)

        safe_write(root_mount / "etc/timezone", timezone + "\n")
        zone = root_mount / "usr/share/zoneinfo" / timezone
        localtime = root_mount / "etc/localtime"
        if zone.exists():
            localtime.unlink(missing_ok=True)
            localtime.symlink_to(pathlib.Path("/usr/share/zoneinfo") / timezone)
        safe_write(root_mount / "etc/default/locale", f"LANG={locale}\n")
        locale_gen = root_mount / "etc/locale.gen"
        if locale_gen.exists():
            text = locale_gen.read_text(encoding="utf-8", errors="replace")
            text = re.sub(rf"^#\s*({re.escape(locale)}\s+UTF-8)\s*$", r"\1", text, flags=re.M)
            safe_write(locale_gen, text)
        safe_write(root_mount / "etc/default/keyboard",
                   f'XKBMODEL="pc105"\nXKBLAYOUT="{keyboard}"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n')

        if bool(setup.get("wifi")):
            ssid = str(setup.get("ssid") or "").replace("\r", "").replace("\n", "").strip()
            wifi_password = str(setup.get("wifiPassword") or "").replace("\r", "").replace("\n", "")
            country = re.sub(r"[^A-Z]", "", str(setup.get("wifiCountry") or "US").upper())[:2] or "US"
            if not ssid or len(wifi_password) < 8:
                fail("Wi-Fi setup requires an SSID and a password of at least eight characters.")
            connection = (
                "[connection]\n"
                "id=NeutronOS Imager WiFi\n"
                f"uuid={uuid.uuid4()}\n"
                "type=wifi\n"
                "autoconnect=true\n\n"
                "[wifi]\n"
                f"ssid={ssid}\n"
                "mode=infrastructure\n\n"
                "[wifi-security]\n"
                "key-mgmt=wpa-psk\n"
                f"psk={wifi_password}\n\n"
                "[ipv4]\nmethod=auto\n\n"
                "[ipv6]\nmethod=auto\n"
            )
            safe_write(root_mount / "etc/NetworkManager/system-connections/neutronos-imager.nmconnection", connection, 0o600)
            safe_write(root_mount / "etc/default/crda", f"REGDOMAIN={country}\n")

        subprocess.run(["sync"], check=False)
        emit("SETUP", percent=100, message="First-boot settings applied")
    finally:
        for mountpoint in reversed(mounted):
            subprocess.run(["umount", str(mountpoint)], check=False)
        shutil.rmtree(temp_root, ignore_errors=True)


def install_command(job_path: str) -> int:
    job_file = pathlib.Path(job_path)
    job = json.loads(job_file.read_text(encoding="utf-8"))
    if not isinstance(job, dict):
        fail("The image job is invalid.")
    target = os.path.realpath(str(job.get("target") or ""))
    os_entry = job.get("os") if isinstance(job.get("os"), dict) else {}
    setup = job.get("setup") if isinstance(job.get("setup"), dict) else {}
    local_path = str(job.get("localPath") or "").strip()
    url = str(os_entry.get("url") or "").strip()
    if url and urllib.parse.urlparse(url).scheme not in ("http", "https"):
        fail("Recommended image downloads must use an HTTP or HTTPS URL.")
    expected_extract = int(os_entry.get("extractBytes") or 0)
    expected_extract_sha = str(os_entry.get("extractSha256") or "").strip().lower()
    expected_download = int(os_entry.get("downloadBytes") or 0)
    expected_download_sha = str(os_entry.get("downloadSha256") or "").strip().lower()

    inventory, _ = validate_target(target, expected_extract)

    if local_path:
        image_path = pathlib.Path(local_path).expanduser().resolve()
        if not image_path.is_file():
            fail("The selected manual image file no longer exists.")
        emit("LOCAL_IMAGE", percent=100, bytes=image_path.stat().st_size,
             total=image_path.stat().st_size, message="Using selected local image")
    else:
        if not url:
            fail("This operating system has no flashable release image. Publish an .img, .img.xz, .img.gz, or .img.zip asset first.")
        cache_dir = pathlib.Path("/var/cache/neutronos/imager")
        image_path = cache_dir / (stable_id(str(os_entry.get("name") or "image"), url) + "-" + filename_from_url(url))
        if image_path.exists() and expected_download and image_path.stat().st_size == expected_download:
            emit("DOWNLOAD_COMPLETE", percent=100, bytes=image_path.stat().st_size,
                 total=image_path.stat().st_size, verification="CACHED", message="Using verified-size cached download")
        else:
            image_path = download(url, image_path, expected_download, expected_download_sha)

    verified_size, verified_digest = verify_source(image_path, expected_extract, expected_extract_sha)
    expected_extract = verified_size
    expected_extract_sha = verified_digest
    inventory, _ = validate_target(target, expected_extract)
    unmount_target(inventory, target)
    written, digest = write_image(image_path, target, expected_extract, expected_extract_sha)
    emit("FLUSH", percent=100, bytes=written, total=written, message="Flushing target data")
    subprocess.run(["sync"], check=True)
    apply_setup(target, setup, os_entry)
    emit("COMPLETE", percent=100, bytes=written, total=written, speed="", eta=0,
         verification="PASSED" if expected_extract_sha else "COMPUTED",
         sha256=digest, message="Image installation completed successfully")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("catalog")
    install = sub.add_parser("install")
    install.add_argument("--job", required=True)
    args = parser.parse_args()
    try:
        if args.command == "catalog":
            return catalog_command()
        return install_command(args.job)
    except Exception as exc:
        message = str(exc).strip() or exc.__class__.__name__
        if not isinstance(exc, RuntimeError):
            emit("ERROR", message=message, verification="FAILED")
        print(message, file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
