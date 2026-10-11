#!/usr/bin/env python3
"""NeutronOS privileged disk-image writer.

The helper is intentionally non-interactive. NeutronShell performs the guided
wizard and invokes this process only after the user has armed the destructive
write. This helper repeats all boot-disk and target checks before touching the
selected block device.
"""

from __future__ import annotations

import argparse
import bz2
import gzip
import hashlib
import io
import json
import lzma
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import urllib.parse
import zipfile
from dataclasses import dataclass
from typing import BinaryIO, Iterator, Optional

CHUNK = 4 * 1024 * 1024
SYSTEM_TYPES = {"loop", "rom"}


def emit(stage: str, message: str = "", **values: object) -> None:
    payload = {"stage": stage, "message": message, **values}
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def run(command: list[str], check: bool = True, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=check, timeout=timeout)


def lsblk() -> dict:
    result = run([
        "lsblk", "-J", "-b", "-o",
        "NAME,PATH,TYPE,PKNAME,MOUNTPOINTS,SIZE,RO,RM,MODEL,SERIAL,FSTYPE,LABEL,UUID,PARTUUID"
    ])
    return json.loads(result.stdout or "{}")


def flatten(nodes: list[dict]) -> list[dict]:
    output: list[dict] = []
    for node in nodes:
        output.append(node)
        output.extend(flatten(node.get("children") or []))
    return output


def base_disk(path: str, nodes: list[dict]) -> str:
    mapping = {str(node.get("path") or ""): node for node in flatten(nodes)}
    current = mapping.get(path)
    seen: set[str] = set()
    while current and current.get("pkname") and str(current.get("path")) not in seen:
        seen.add(str(current.get("path")))
        parent_name = str(current.get("pkname"))
        parent_path = "/dev/" + parent_name
        current = mapping.get(parent_path)
    return str((current or {}).get("path") or path)


def root_disk(nodes: list[dict]) -> str:
    source = run(["findmnt", "-n", "-o", "SOURCE", "/"]).stdout.strip()
    if source.startswith("/dev/"):
        return base_disk(os.path.realpath(source), nodes)
    # Overlay/network roots still must not permit the current boot medium.
    for candidate in ("/boot/firmware", "/boot"):
        try:
            source = run(["findmnt", "-n", "-o", "SOURCE", candidate], timeout=10).stdout.strip()
        except Exception:
            continue
        if source.startswith("/dev/"):
            return base_disk(os.path.realpath(source), nodes)
    return ""


def target_node(path: str, nodes: list[dict]) -> dict:
    real = os.path.realpath(path)
    for node in flatten(nodes):
        if os.path.realpath(str(node.get("path") or "")) == real:
            return node
    raise RuntimeError("The selected target device is no longer connected.")


def validate_target(path: str) -> tuple[str, int, list[dict]]:
    if os.geteuid() != 0:
        raise RuntimeError("Image flashing requires the privileged neutronos.service runtime.")
    if not path.startswith("/dev/") or ".." in path or "\n" in path or "\r" in path:
        raise RuntimeError("Invalid target device path.")
    real = os.path.realpath(path)
    st = os.stat(real)
    if not stat.S_ISBLK(st.st_mode):
        raise RuntimeError("The selected target is not a block device.")
    tree = lsblk().get("blockdevices") or []
    node = target_node(real, tree)
    if str(node.get("type") or "") != "disk":
        raise RuntimeError("Select a whole removable disk, not a partition.")
    if int(node.get("ro") or 0):
        raise RuntimeError("The selected target is read-only.")
    if str(node.get("type") or "") in SYSTEM_TYPES:
        raise RuntimeError("The selected target cannot be flashed.")
    system = root_disk(tree)
    if system and os.path.realpath(system) == real:
        raise RuntimeError("NeutronOS blocked an attempt to overwrite the active boot drive.")
    size = int(node.get("size") or 0)
    if size <= 0:
        raise RuntimeError("The target capacity could not be determined.")
    return real, size, tree




def source_disk_for_file(path: pathlib.Path, tree: list[dict]) -> str:
    result = run(["findmnt", "-n", "-o", "SOURCE", "-T", str(path)], check=False, timeout=15)
    source = result.stdout.strip()
    if source.startswith("/dev/"):
        return base_disk(os.path.realpath(source), tree)
    return ""

def child_nodes(target: str, tree: list[dict]) -> list[dict]:
    for node in tree:
        if os.path.realpath(str(node.get("path") or "")) == os.path.realpath(target):
            return flatten(node.get("children") or [])
    return []


def unmount_target(target: str, tree: list[dict]) -> None:
    mounts: list[str] = []
    for node in child_nodes(target, tree):
        for value in node.get("mountpoints") or []:
            if value:
                mounts.append(str(value))
    mounts.sort(key=len, reverse=True)
    for mount in mounts:
        emit("unmounting", f"Unmounting {mount}")
        result = run(["umount", mount], check=False, timeout=60)
        if result.returncode != 0:
            raise RuntimeError(f"Could not unmount {mount}: {result.stdout.strip()}")


@dataclass
class ImageStream:
    stream: BinaryIO
    expected_size: int
    process: Optional[subprocess.Popen[bytes]] = None
    archive: Optional[zipfile.ZipFile] = None

    def close(self) -> None:
        try:
            self.stream.close()
        finally:
            if self.archive is not None:
                self.archive.close()
            if self.process is not None:
                self.process.wait(timeout=30)
                if self.process.returncode not in (0, None):
                    details = b""
                    if self.process.stderr is not None:
                        details = self.process.stderr.read()
                    raise RuntimeError("The compressed image could not be decompressed: " + details.decode(errors="replace").strip())


def open_image(path: pathlib.Path, supplied_size: int = 0) -> ImageStream:
    lower = path.name.lower()
    if lower.endswith(".zip"):
        archive = zipfile.ZipFile(path, "r")
        members = [entry for entry in archive.infolist()
                   if not entry.is_dir() and entry.filename.lower().endswith((".img", ".iso", ".raw"))]
        if len(members) != 1:
            archive.close()
            raise RuntimeError("ZIP images must contain exactly one .img, .iso, or .raw file.")
        member = members[0]
        stream = archive.open(member, "r")
        return ImageStream(stream, member.file_size, archive=archive)
    if lower.endswith((".gz", ".gzip")):
        return ImageStream(gzip.open(path, "rb"), supplied_size)
    if lower.endswith(".bz2"):
        return ImageStream(bz2.open(path, "rb"), supplied_size)
    if lower.endswith((".xz", ".lzma")):
        return ImageStream(lzma.open(path, "rb"), supplied_size)
    if lower.endswith((".zst", ".zstd")):
        zstd = shutil.which("zstd")
        if not zstd:
            raise RuntimeError("zstd is required to decompress this image.")
        process = subprocess.Popen([zstd, "-dc", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if process.stdout is None:
            raise RuntimeError("Could not start zstd decompression.")
        return ImageStream(process.stdout, supplied_size, process=process)
    return ImageStream(open(path, "rb", buffering=0), path.stat().st_size)


def download(url: str, destination: pathlib.Path, expected_sha: str) -> pathlib.Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    part = destination.with_suffix(destination.suffix + ".part")
    offset = part.stat().st_size if part.exists() else 0
    headers = {"User-Agent": "NeutronOS-Storage-Flasher/1.0"}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    request = urllib.request.Request(url, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=45)
    except urllib.error.HTTPError as exc:
        if offset and exc.code == 416:
            part.replace(destination)
            response = None
        else:
            raise RuntimeError(f"Image download failed: {exc}") from exc
    if response is not None:
        status = getattr(response, "status", 200)
        if offset and status != 206:
            offset = 0
            part.unlink(missing_ok=True)
        content_length = int(response.headers.get("Content-Length") or 0)
        total = offset + content_length if content_length else 0
        mode = "ab" if offset else "wb"
        started = time.monotonic()
        downloaded = offset
        with open(part, mode) as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                downloaded += len(chunk)
                elapsed = max(0.001, time.monotonic() - started)
                speed = max(0.0, (downloaded - offset) / elapsed)
                percent = int(downloaded * 100 / total) if total else -1
                eta = int((total - downloaded) / speed) if total and speed > 0 else -1
                emit("downloading", "Downloading Raspberry Pi image", progress=percent,
                     bytesDone=downloaded, bytesTotal=total, speed=speed, eta=eta)
            output.flush()
            os.fsync(output.fileno())
        part.replace(destination)
    if expected_sha:
        emit("preparing", "Verifying downloaded image")
        digest = hashlib.sha256()
        with open(destination, "rb") as source:
            for chunk in iter(lambda: source.read(CHUNK), b""):
                digest.update(chunk)
        if digest.hexdigest().lower() != expected_sha.lower():
            destination.unlink(missing_ok=True)
            raise RuntimeError("The downloaded image checksum did not match the trusted catalog.")
    return destination


def write_image(source: pathlib.Path, target: str, target_size: int,
                expected_uncompressed: int) -> tuple[int, str]:
    image = open_image(source, expected_uncompressed)
    if image.expected_size and image.expected_size > target_size:
        image.close()
        raise RuntimeError("The image is larger than the selected storage device.")
    digest = hashlib.sha256()
    written = 0
    started = time.monotonic()
    emit("writing", "Writing image to storage", progress=0,
         bytesDone=0, bytesTotal=image.expected_size)
    try:
        with open(target, "wb", buffering=0) as output:
            while True:
                chunk = image.stream.read(CHUNK)
                if not chunk:
                    break
                output.write(chunk)
                digest.update(chunk)
                written += len(chunk)
                elapsed = max(0.001, time.monotonic() - started)
                speed = written / elapsed
                percent = int(written * 100 / image.expected_size) if image.expected_size else -1
                eta = int((image.expected_size - written) / speed) if image.expected_size and speed > 0 else -1
                emit("writing", "Writing image to storage", progress=percent,
                     bytesDone=written, bytesTotal=image.expected_size, speed=speed, eta=eta)
            output.flush()
            os.fsync(output.fileno())
    finally:
        image.close()
    if written <= 0:
        raise RuntimeError("The image contained no writable data.")
    emit("synchronizing", "Synchronizing device caches", progress=100,
         bytesDone=written, bytesTotal=written)
    os.sync()
    return written, digest.hexdigest()


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def password_hash(password: str) -> str:
    if not password:
        return ""
    openssl = shutil.which("openssl")
    if not openssl:
        raise RuntimeError("openssl is required to create the first-boot password hash.")
    # Supply the password only through stdin; do not place it in argv or logs.
    proc = subprocess.run([openssl, "passwd", "-6", "-stdin"], input=password + "\n",
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return proc.stdout.strip()


def partition_paths(target: str) -> list[dict]:
    run(["partprobe", target], check=False, timeout=30)
    if shutil.which("udevadm"):
        run(["udevadm", "settle"], check=False, timeout=30)
    time.sleep(1.0)
    tree = lsblk().get("blockdevices") or []
    return child_nodes(target, tree)


def mount_partition(path: str, directory: pathlib.Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    result = run(["mount", "-o", "rw,nosuid,nodev", path, str(directory)], check=False, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"Could not mount {path} for customization: {result.stdout.strip()}")


def customize_target(target: str, config: dict) -> None:
    if not config.get("raspberryPi"):
        return
    emit("customizing", "Applying Raspberry Pi first-boot settings", progress=-1)
    parts = partition_paths(target)
    boot = next((p for p in parts if str(p.get("fstype") or "").lower() in {"vfat", "fat", "fat32"}), None)
    root = next((p for p in parts if str(p.get("fstype") or "").lower() in {"ext4", "btrfs", "f2fs"}), None)
    if not boot:
        emit("customizing", "Selected image has no supported boot partition; custom settings were skipped.", warning=True)
        return
    work = pathlib.Path(tempfile.mkdtemp(prefix="neutronos-flash-customize-"))
    boot_mount = work / "boot"
    root_mount = work / "root"
    mounted: list[pathlib.Path] = []
    try:
        mount_partition(str(boot.get("path")), boot_mount)
        mounted.append(boot_mount)
        if root:
            mount_partition(str(root.get("path")), root_mount)
            mounted.append(root_mount)

        ssh = bool(config.get("sshEnabled"))
        if ssh:
            (boot_mount / "ssh").touch(mode=0o600, exist_ok=True)

        username = str(config.get("username") or "").strip()
        password = str(config.get("password") or "")
        if username and password:
            hashed = password_hash(password)
            (boot_mount / "userconf.txt").write_text(f"{username}:{hashed}\n", encoding="utf-8")
            os.chmod(boot_mount / "userconf.txt", 0o600)

        lines = ["#!/bin/bash", "set -e", "exec >/var/log/neutronos-firstboot.log 2>&1"]
        hostname = str(config.get("hostname") or "").strip()
        if hostname:
            lines += [f"hostnamectl set-hostname {shell_quote(hostname)}",
                      f"printf '%s\\n' {shell_quote(hostname)} > /etc/hostname",
                      f"sed -i 's/^127\\.0\\.1\\.1.*/127.0.1.1\\t{hostname}/' /etc/hosts || true"]
        timezone = str(config.get("timezone") or "").strip()
        if timezone:
            lines += [f"timedatectl set-timezone {shell_quote(timezone)} || true"]
        locale = str(config.get("locale") or "").strip()
        if locale:
            lines += [f"sed -i 's/^# *{locale} UTF-8/{locale} UTF-8/' /etc/locale.gen || true",
                      "locale-gen || true", f"update-locale LANG={shell_quote(locale)} || true"]
        keyboard = str(config.get("keyboard") or "").strip()
        if keyboard:
            lines += [f"sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT=\"{keyboard}\"/' /etc/default/keyboard || true"]
        country = str(config.get("wifiCountry") or "").strip().upper()
        ssid = str(config.get("wifiSsid") or "")
        wifi_password = str(config.get("wifiPassword") or "")
        hidden = bool(config.get("wifiHidden"))
        if country:
            lines += [f"raspi-config nonint do_wifi_country {shell_quote(country)} || iw reg set {shell_quote(country)} || true"]
        if ssid:
            command = (f"nmcli connection add type wifi ifname wlan0 con-name NeutronOS-WiFi "
                       f"ssid {shell_quote(ssid)}")
            lines += [command + " || true"]
            if hidden:
                lines += ["nmcli connection modify NeutronOS-WiFi 802-11-wireless.hidden yes || true"]
            if wifi_password:
                lines += [f"nmcli connection modify NeutronOS-WiFi wifi-sec.key-mgmt wpa-psk "
                          f"wifi-sec.psk {shell_quote(wifi_password)} || true"]
            lines += ["nmcli connection modify NeutronOS-WiFi connection.autoconnect yes || true"]
        if ssh:
            lines += ["systemctl enable ssh || true", "systemctl start ssh || true"]
        ssh_key = str(config.get("sshPublicKey") or "").strip()
        if username and ssh_key:
            lines += [f"install -d -m 0700 -o {shell_quote(username)} -g {shell_quote(username)} /home/{username}/.ssh",
                      f"printf '%s\\n' {shell_quote(ssh_key)} > /home/{username}/.ssh/authorized_keys",
                      f"chown {shell_quote(username)}:{shell_quote(username)} /home/{username}/.ssh/authorized_keys",
                      f"chmod 0600 /home/{username}/.ssh/authorized_keys"]
        if bool(config.get("piConnect")):
            lines += ["apt-get update || true", "DEBIAN_FRONTEND=noninteractive apt-get install -y rpi-connect-lite || true"]
        lines += ["systemctl disable neutronos-firstboot.service || true",
                  "rm -f /etc/systemd/system/neutronos-firstboot.service",
                  "rm -f /usr/local/sbin/neutronos-firstboot",
                  "systemctl daemon-reload || true"]
        script = "\n".join(lines) + "\n"

        if root:
            target_script = root_mount / "usr/local/sbin/neutronos-firstboot"
            target_script.parent.mkdir(parents=True, exist_ok=True)
            target_script.write_text(script, encoding="utf-8")
            os.chmod(target_script, 0o700)
            service = root_mount / "etc/systemd/system/neutronos-firstboot.service"
            service.parent.mkdir(parents=True, exist_ok=True)
            service.write_text(
                "[Unit]\nDescription=Apply NeutronOS Raspberry Pi image settings\n"
                "After=NetworkManager.service network-online.target\nWants=network-online.target\n"
                "[Service]\nType=oneshot\nExecStart=/usr/local/sbin/neutronos-firstboot\n"
                "[Install]\nWantedBy=multi-user.target\n", encoding="utf-8")
            wants = root_mount / "etc/systemd/system/multi-user.target.wants"
            wants.mkdir(parents=True, exist_ok=True)
            link = wants / "neutronos-firstboot.service"
            link.unlink(missing_ok=True)
            link.symlink_to("../neutronos-firstboot.service")
        else:
            first_run = boot_mount / "firstrun.sh"
            first_run.write_text(script, encoding="utf-8")
            os.chmod(first_run, 0o700)
            cmdline = next((p for p in (boot_mount / "cmdline.txt", boot_mount / "firmware/cmdline.txt") if p.exists()), None)
            if cmdline:
                text = cmdline.read_text(encoding="utf-8").strip()
                extras = " systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target"
                if "systemd.run=/boot/firstrun.sh" not in text:
                    cmdline.write_text(text + extras + "\n", encoding="utf-8")
        os.sync()
    finally:
        for directory in reversed(mounted):
            run(["umount", str(directory)], check=False, timeout=60)
        shutil.rmtree(work, ignore_errors=True)


def verify_target(target: str, byte_count: int, expected_digest: str) -> None:
    emit("verifying", "Reading the image back from storage", progress=0,
         bytesDone=0, bytesTotal=byte_count)
    digest = hashlib.sha256()
    read = 0
    started = time.monotonic()
    with open(target, "rb", buffering=0) as source:
        while read < byte_count:
            chunk = source.read(min(CHUNK, byte_count - read))
            if not chunk:
                raise RuntimeError("Verification ended before the complete image was read back.")
            digest.update(chunk)
            read += len(chunk)
            elapsed = max(0.001, time.monotonic() - started)
            speed = read / elapsed
            progress = int(read * 100 / byte_count)
            eta = int((byte_count - read) / speed) if speed > 0 else -1
            emit("verifying", "Reading the image back from storage", progress=progress,
                 bytesDone=read, bytesTotal=byte_count, speed=speed, eta=eta)
    if digest.hexdigest() != expected_digest:
        raise RuntimeError("Verification failed: data read from the device does not match the image that was written.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--expected-sha256", default="")
    parser.add_argument("--expected-size", default="0")
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    log_path = pathlib.Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = open(log_path, "a", encoding="utf-8")
    original_stdout = sys.stdout

    class Tee:
        def write(self, value: str) -> int:
            original_stdout.write(value)
            log_file.write(value)
            return len(value)
        def flush(self) -> None:
            original_stdout.flush()
            log_file.flush()

    sys.stdout = Tee()  # type: ignore[assignment]
    config_path = pathlib.Path(args.config)
    try:
        emit("preparing", "Rechecking source and target")
        target, target_size, tree = validate_target(args.target)
        config = json.loads(config_path.read_text(encoding="utf-8"))
        source_value = args.source
        if source_value.startswith(("https://", "http://")):
            filename = pathlib.Path(urllib.parse.urlparse(source_value).path).name or "raspberry-pi-image.img"
            source = download(source_value, pathlib.Path(args.cache_dir) / filename, args.expected_sha256)
        else:
            source = pathlib.Path(source_value).expanduser().resolve()
            if not source.is_file():
                raise RuntimeError("The selected image file does not exist or cannot be read.")
            if os.path.realpath(str(source)) == target:
                raise RuntimeError("The source image cannot be the target device.")
            source_disk = source_disk_for_file(source, tree)
            if source_disk and os.path.realpath(source_disk) == target:
                raise RuntimeError("The image file is stored on the target device. Move it elsewhere before flashing.")
        # Shared source-backed guard: never create an ambiguous Gemini clone
        # while a disk with the same boot identities remains connected.
        sys.path.insert(0, '/usr/local/lib/neutronos')
        from neutronos_recovery_image import inspect_boot_identities, reject_boot_identity_collisions
        image = open_image(source, int(args.expected_size or 0))
        try:
            identities = inspect_boot_identities(image.stream)
        finally:
            image.close()
        reject_boot_identity_collisions(identities, tree, target)
        unmount_target(target, tree)
        written, digest = write_image(source, target, target_size, int(args.expected_size or 0))
        customize_target(target, config)
        emit("synchronizing", "Final device synchronization", progress=100)
        os.sync()
        verify_target(target, written, digest)
        emit("finalizing", "Refreshing the partition table", progress=100)
        run(["partprobe", target], check=False, timeout=30)
        emit("complete", "Image written and verified successfully.", progress=100,
             bytesDone=written, bytesTotal=written, logPath=str(log_path))
        return 0
    except Exception as exc:
        emit("failed", str(exc), error=True, logPath=str(log_path))
        return 1
    finally:
        try:
            config_path.unlink(missing_ok=True)
        except Exception:
            pass
        log_file.close()


if __name__ == "__main__":
    raise SystemExit(main())
