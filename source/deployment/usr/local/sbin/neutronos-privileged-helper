#!/usr/bin/env python3
"""Stable Security boundary in front of the NeutronOS privileged App Store helper.

The real helper implements version-specific App Store transactions.
This guard validates Security-reserved package authority, stages the exact
package bytes root-owned, then delegates to the real helper for signature and
normal privileged transaction handling.
"""
from __future__ import annotations

import hashlib
import grp
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

MARKER = "NEUTRONOS_PRIVILEGED_HELPER_GUARD_V4"
REAL_HELPER = Path("/usr/local/libexec/neutronos-privileged-helper.real")
ROOT_REGISTRY = Path("/var/lib/neutronos/app-store/root-installed.json")
ROOT_ROLLBACK = Path("/var/lib/neutronos/app-store/root-rollback")
STAGE_ROOT = Path("/run/neutronos-appstore-guard")
SETUP_DIR = Path("/var/lib/neutronos/setup")
SETUP_STATE = SETUP_DIR / "setup.json"
SETUP_PREFERENCES = SETUP_DIR / "preferences.json"
ACCOUNT_HANDOFF_FINALIZED = Path("/var/lib/neutronos/security-core/account-handoff-finalized-v1")
IDENTITY_MARKER = Path("/var/lib/neutronos/security-core/identity-provisioned")
SECURITY_USERS = Path("/var/lib/neutronos/security/users")
RENAME_USER_CONF = Path("/etc/ssh/sshd_config.d/rename_user.conf")
RPI_SSH_BANNER = "/usr/share/userconf-pi/sshd_banner"
SSHD_NOT_TO_BE_RUN = Path("/etc/ssh/sshd_not_to_be_run")
SSH_SETUP_CONFIG = Path("/etc/ssh/sshd_config.d/99-neutronos-setup-ssh.conf")
SSH_HOSTKEY_DIAGNOSTIC = Path("/var/lib/neutronos/ssh-hostkeys-diagnostic.log")
SSH_HOSTKEY_SPECS = (
    ("rsa", ("-b", "3072")),
    ("ecdsa", ("-b", "256")),
    ("ed25519", ()),
)
NEUTRON_ROOT = Path("/opt/neutronos")
BACKUP_HELPER = NEUTRON_ROOT / "scripts/neutronos-backup-restore.sh"
UPDATE_RECOVERY_HELPER = Path("/usr/local/lib/neutronos/neutronos-update-recovery")
DEFAULT_BACKUP_DESTINATION = NEUTRON_ROOT / "backups/system"
BACKUP_DESTINATION_ROOTS = (
    DEFAULT_BACKUP_DESTINATION,
    Path("/srv/neutronos/user-data"),
    Path("/media"),
    Path("/run/media"),
    Path("/mnt"),
)

SECURITY_RESERVED_DEST_PREFIXES = (
    "/usr/local/lib/neutronos/appstore_dependencies.py",
    "/etc/systemd/system/neutron-security",
    "/etc/systemd/system/neutronos-firewall",
    "/etc/systemd/system/nftables.service",
    "/etc/systemd/system/neutron-remote-service.service.d/20-neutronos-security-isolation.conf",
    "/usr/local/lib/neutronos/neutron-security",
    "/usr/local/lib/neutronos/neutronos_firewall",
    "/usr/local/lib/neutronos/neutronos-firewall",
)

SECURITY_RESERVED_UNIT_PATTERNS = (
    re.compile(r"(?mi)^\s*RuntimeDirectory\s*=\s*neutronos(?:/security)?\s*$"),
    re.compile(r"(?mi)^\s*(?:ReadWritePaths|BindPaths|BindReadOnlyPaths)\s*=.*(?:/run/neutronos/security|/var/lib/neutronos/security-core)"),
    re.compile(r"(?mi)^\s*(?:CapabilityBoundingSet|AmbientCapabilities)\s*=.*CAP_NET_ADMIN"),
    re.compile(r"(?mi)^\s*Exec(?:Start|StartPre|StartPost|Reload|Stop|StopPost)\s*=.*(?:\bnft\b|iptables|ip6tables|firewalld)"),
)


def fail(message: str) -> "NoReturn":
    print(json.dumps({"success": False, "message": message}, separators=(",", ":")))
    raise SystemExit(1)


def _require_backup_caller() -> None:
    caller = os.environ.get("SUDO_USER", "root")
    if caller not in ("neutronos", "root"):
        fail("backup operation is restricted to the NeutronOS system session")


def _path_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _validated_backup_destination(raw: str) -> Path:
    candidate = Path(raw)
    if not candidate.is_absolute() or ".." in candidate.parts or candidate == Path("/"):
        fail("backup destination is unsafe")
    resolved = candidate.resolve(strict=False)
    allowed = tuple(root.resolve(strict=False) for root in BACKUP_DESTINATION_ROOTS)
    if not any(resolved == root or _path_within(resolved, root) for root in allowed):
        fail("backup destination is outside approved persistent storage")
    return resolved


def _validated_backup_archive(raw: str) -> Path:
    archive = _validated_backup_destination(raw)
    if not archive.name.endswith((".tar.zst", ".tar.gz", ".tar.xz")):
        fail("backup archive type is unsupported")
    try:
        info = archive.lstat()
        checksum_info = Path(str(archive) + ".sha256").lstat()
    except OSError as error:
        fail(f"backup archive is unavailable: {error}")
    if (not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode) or
            not stat.S_ISREG(checksum_info.st_mode) or stat.S_ISLNK(checksum_info.st_mode)):
        fail("backup archive and checksum must be regular files")
    return archive


def _run_backup_helper(arguments: list[str]) -> int:
    if not BACKUP_HELPER.is_file() or not os.access(BACKUP_HELPER, os.X_OK):
        fail("NeutronOS backup helper is unavailable")
    try:
        process = subprocess.Popen(
            [str(BACKUP_HELPER), *arguments], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            bufsize=1, env={**os.environ, "HOME": "/root", "NEUTRONOS_ROOT": str(NEUTRON_ROOT)},
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line.rstrip("\n"), flush=True)
        process.stdout.close()
        return int(process.wait())
    except OSError as error:
        fail(f"backup helper could not start: {error}")


def _regular_file_digest(path: Path) -> tuple[str, os.stat_result] | None:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError:
        return None
    digest = hashlib.sha256()
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            return None
        while True:
            block = os.read(descriptor, 1024 * 1024)
            if not block:
                break
            digest.update(block)
        after = os.fstat(descriptor)
        if (before.st_dev, before.st_ino, before.st_size) != (after.st_dev, after.st_ino, after.st_size):
            return None
        return digest.hexdigest(), after
    finally:
        os.close(descriptor)


def _read_small_regular_file(path: Path, maximum: int = 4096) -> str | None:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError:
        return None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size > maximum:
            return None
        payload = os.read(descriptor, maximum + 1)
        return payload.decode("ascii") if len(payload) <= maximum else None
    except (OSError, UnicodeDecodeError):
        return None
    finally:
        os.close(descriptor)


def _list_backups(destination: Path) -> int:
    archive_pattern = re.compile(
        r"^(\d{8}T\d{6}Z)-(full|settings|apps|personal)-backup\.tar\.(zst|gz|xz)$")
    backups: list[dict[str, object]] = []
    invalid_count = 0
    try:
        entries = list(destination.iterdir()) if destination.is_dir() else []
    except OSError as error:
        fail(f"backup destination cannot be read: {error}")
    for archive in entries:
        match = archive_pattern.fullmatch(archive.name)
        if not match:
            continue
        checksum_path = Path(str(archive) + ".sha256")
        checksum_text = _read_small_regular_file(checksum_path)
        digest_result = _regular_file_digest(archive)
        checksum_match = re.fullmatch(
            r"([0-9a-fA-F]{64}) [ *]([^/\r\n]+)\s*", checksum_text or "")
        if (digest_result is None or checksum_match is None or
                checksum_match.group(2) != archive.name or
                checksum_match.group(1).lower() != digest_result[0]):
            invalid_count += 1
            continue
        info = digest_result[1]
        backups.append({
            "path": str(archive),
            "name": archive.name,
            "profile": match.group(2).upper(),
            "size": info.st_size,
            "modified": datetime.fromtimestamp(info.st_mtime, timezone.utc).isoformat().replace("+00:00", "Z"),
            "sha256": digest_result[0],
            "verified": True,
        })
    backups.sort(key=lambda row: str(row["name"]), reverse=True)
    print(json.dumps({"success": True, "backups": backups, "invalidCount": invalid_count},
                     separators=(",", ":")))
    return 0


def backup_operation(action: str, args: list[str]) -> int:
    _require_backup_caller()
    if action == "backup-create":
        if len(args) != 4:
            fail("backup-create requires profile, ROM option, label, and destination")
        profile, include_roms, label, raw_destination = args
        if profile not in ("full", "settings", "apps", "personal"):
            fail("unsupported backup profile")
        if include_roms not in ("0", "1"):
            fail("invalid backup ROM option")
        if len(label) > 40 or not re.fullmatch(r"[A-Za-z0-9._ -]*", label):
            fail("backup label is invalid")
        destination = _validated_backup_destination(raw_destination)
        destination.mkdir(parents=True, exist_ok=True, mode=0o755)
        return _run_backup_helper(["create-backup", profile, include_roms, label, str(destination)])
    if action == "backup-verify":
        if len(args) != 1:
            fail("backup-verify requires one archive")
        archive = _validated_backup_archive(args[0])
        return _run_backup_helper(["verify-backup", str(archive)])
    if action == "backup-list":
        if len(args) != 1:
            fail("backup-list requires one approved destination")
        destination = _validated_backup_destination(args[0])
        return _list_backups(destination)
    if action == "backup-restore-stage":
        if len(args) != 1:
            fail("backup-restore-stage requires one archive")
        archive = _validated_backup_archive(args[0])
        if not UPDATE_RECOVERY_HELPER.is_file() or not os.access(UPDATE_RECOVERY_HELPER, os.X_OK):
            fail("authenticated Recovery staging helper is unavailable")
        verified = _run_backup_helper(["verify-backup", str(archive)])
        if verified != 0:
            return verified
        completed = subprocess.run([str(UPDATE_RECOVERY_HELPER), "stage-backup-restore", str(archive)],
                                   check=False, stdin=subprocess.DEVNULL, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        if completed.stdout:
            print(completed.stdout.rstrip())
        return int(completed.returncode)
    if action == "backup-delete":
        if len(args) != 1:
            fail("backup-delete requires one archive")
        archive = _validated_backup_archive(args[0])
        checksum = Path(str(archive) + ".sha256")
        archive.unlink()
        checksum.unlink()
        print(json.dumps({"success": True, "deleted": archive.name}, separators=(",", ":")))
        return 0
    fail("unsupported backup operation")


def recovery_operation(action: str, args: list[str]) -> int:
    """Fixed graphical Recovery boundary; never accepts commands or destinations."""
    _require_backup_caller()
    if not UPDATE_RECOVERY_HELPER.is_file() or not os.access(UPDATE_RECOVERY_HELPER, os.X_OK):
        fail("authenticated Recovery service is unavailable")
    command = [str(UPDATE_RECOVERY_HELPER)]
    if action == "recovery-status" and not args:
        command.append("recovery-status")
    elif action == "recovery-apply-update" and not args:
        command.append("recovery-apply-update")
    elif action == "recovery-apply-backup" and len(args) == 1:
        archive = _validated_backup_archive(args[0])
        command.extend(("recovery-apply-backup", str(archive)))
    elif action == "recovery-cancel" and not args:
        command.append("recovery-cancel")
    elif action == "recovery-reboot" and not args:
        marker = Path("/run/neutronos/recovery-active.json")
        try:
            active = json.loads(marker.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            fail("reboot is restricted to an active Recovery session")
        if active.get("active") is not True:
            fail("reboot is restricted to an active Recovery session")
        return subprocess.run(["/usr/bin/systemctl", "reboot", "--no-block"],
                              check=False, stdin=subprocess.DEVNULL).returncode
    else:
        fail("unsupported graphical Recovery operation")
    try:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1,
                                   env={**os.environ, "HOME": "/root"})
        assert process.stdout is not None
        for line in process.stdout:
            print(line.rstrip("\n"), flush=True)
        process.stdout.close()
        return int(process.wait(timeout=900))
    except (OSError, subprocess.TimeoutExpired) as error:
        try:
            process.kill()
        except (NameError, OSError):
            pass
        fail(f"Recovery operation failed: {error}")


def reserved_destination(raw: object) -> bool:
    text = str(raw or "").strip()
    return any(text.startswith(prefix) for prefix in SECURITY_RESERVED_DEST_PREFIXES)


def validate_destination(raw: object) -> str:
    text = str(raw or "").strip()
    path = Path(text)
    if not text.startswith("/") or ".." in path.parts:
        fail("unsafe privileged system destination")
    if reserved_destination(text):
        fail("system destination is reserved for NeutronOS Security: " + text)
    return text


def validate_systemd_unit(destination: str, data: bytes) -> None:
    if not destination.startswith("/etc/systemd/system/"):
        return
    if not destination.endswith((".service", ".socket", ".timer", ".path")):
        return
    if len(data) > 1024 * 1024:
        fail("package systemd unit is unreasonably large")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        fail("package systemd units must be UTF-8 text")
    for pattern in SECURITY_RESERVED_UNIT_PATTERNS:
        if pattern.search(text):
            fail("package systemd unit requests Security-reserved authority: " + destination)


def validate_package(package: Path) -> None:
    try:
        with zipfile.ZipFile(package, "r") as archive:
            try:
                manifest = json.loads(archive.read("manifest.json").decode("utf-8"))
            except (KeyError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                fail("signed package manifest is unavailable to Security guard: " + str(exc))
            if not isinstance(manifest, dict):
                fail("signed package manifest is invalid")
            rows = manifest.get("systemFiles", [])
            if not isinstance(rows, list):
                fail("systemFiles must be an array")
            names = set(archive.namelist())
            for row in rows:
                if not isinstance(row, dict):
                    fail("systemFiles entry is invalid")
                destination = validate_destination(row.get("destination"))
                source = str(row.get("source") or "").strip()
                if destination.startswith("/etc/systemd/system/"):
                    if not source or source not in names:
                        fail("package systemd unit source is missing: " + source)
                    validate_systemd_unit(destination, archive.read(source))
    except zipfile.BadZipFile as exc:
        fail("invalid Napp archive: " + str(exc))


def copy_and_hash(source: Path, expected_sha: str) -> Path:
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha or ""):
        fail("invalid expected package SHA-256")
    try:
        STAGE_ROOT.mkdir(parents=True, exist_ok=True)
        os.chmod(STAGE_ROOT, 0o700)
    except OSError as exc:
        fail("cannot create privileged package staging area: " + str(exc))

    fd, name = tempfile.mkstemp(prefix="napp.", suffix=".Napp", dir=STAGE_ROOT)
    digest = hashlib.sha256()
    try:
        os.fchmod(fd, 0o600)
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        src_fd = os.open(source, flags)
        try:
            with os.fdopen(fd, "wb", closefd=False) as out:
                while True:
                    block = os.read(src_fd, 1024 * 1024)
                    if not block:
                        break
                    digest.update(block)
                    out.write(block)
                out.flush()
                os.fsync(out.fileno())
        finally:
            os.close(src_fd)
        os.close(fd)
        fd = -1
        if digest.hexdigest().lower() != expected_sha.lower():
            fail("privileged package SHA-256 mismatch before Security validation")
        staged = Path(name)
        validate_package(staged)
        return staged
    except BaseException:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass
        raise


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return {}


def require_root_owned(path: Path, *, directory: bool) -> os.stat_result:
    try:
        info = path.stat(follow_symlinks=False)
    except OSError as exc:
        fail(f"trusted App Store state is unavailable: {path}: {exc}")
    expected = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    if not expected or info.st_uid != 0 or info.st_mode & 0o022:
        fail(f"trusted App Store state has unsafe ownership, type, or mode: {path}")
    return info


def load_root_json(path: Path) -> dict:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        fail(f"trusted App Store state cannot be opened: {path}: {exc}")
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                info.st_mode & 0o022 or info.st_size > 1024 * 1024):
            fail(f"trusted App Store state has unsafe ownership, type, or mode: {path}")
        with os.fdopen(descriptor, "r", encoding="utf-8", closefd=False) as handle:
            value = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError) as exc:
        fail(f"trusted App Store state is invalid: {path}: {exc}")
    finally:
        os.close(descriptor)
    if not isinstance(value, dict):
        fail(f"trusted App Store state is not an object: {path}")
    return value


def read_root_bytes(path: Path, maximum: int = 64 * 1024 * 1024) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        fail(f"trusted rollback payload cannot be opened: {path}: {exc}")
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                info.st_mode & 0o022 or info.st_size > maximum):
            fail(f"trusted rollback payload has unsafe ownership, type, mode, or size: {path}")
        chunks = []
        remaining = maximum + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
    finally:
        os.close(descriptor)
    if len(data) > maximum:
        fail(f"trusted rollback payload is too large: {path}")
    return data


def validate_registered_uninstall(package_id: str) -> None:
    registry = load_root_json(ROOT_REGISTRY)
    packages = registry.get("packages", {})
    if not isinstance(packages, dict):
        fail("trusted App Store registry packages are invalid")
    current = packages.get(package_id, {}) if isinstance(packages, dict) else {}
    if not isinstance(current, dict):
        return
    for raw in current.get("ownedFiles", []):
        validate_destination(raw)


def validate_rollback(token: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", token or ""):
        fail("invalid App Store rollback token")
    require_root_owned(ROOT_ROLLBACK, directory=True)
    transaction = ROOT_ROLLBACK / token
    require_root_owned(transaction, directory=True)
    meta = load_root_json(transaction / "snapshot.json")
    if meta.get("schema") != 1 or meta.get("token") != token:
        fail("App Store rollback transaction identity does not match")
    rows = meta.get("files", [])
    services = meta.get("services", [])
    if not isinstance(rows, list) or not isinstance(services, list):
        fail("App Store rollback metadata has invalid collections")
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("existed"), bool):
            fail("App Store rollback file entry is invalid")
        destination = validate_destination(row.get("destination"))
        if row["existed"]:
            try:
                mode = int(str(row.get("mode", "0o644")), 8)
            except ValueError:
                fail("App Store rollback mode is invalid")
            if mode not in (0o644, 0o755):
                fail("App Store rollback mode is denied")
            backup = transaction / "files" / destination.lstrip("/")
            data = read_root_bytes(backup)
            validate_systemd_unit(destination, data)
    for service in services:
        if (not isinstance(service, dict) or
                not isinstance(service.get("enabled"), bool) or
                not isinstance(service.get("active"), bool)):
            fail("App Store rollback service entry is invalid")
        unit = str(service.get("unit") or "")
        if not re.fullmatch(r"[A-Za-z0-9_.:@-]+\.(?:service|socket|timer|path)", unit):
            fail("App Store rollback service name is invalid")
        validate_destination("/etc/systemd/system/" + unit)


def _setup_identity_state_allows(marker_exists: bool, completed: bool, configured_user_evidence: bool) -> bool:
    """Pure policy helper used by the self-test and live one-shot gate."""
    return not marker_exists and not completed and not configured_user_evidence


def _configured_identity_evidence() -> bool:
    """Return True once NeutronOS has evidence that onboarding created a human identity.

    A clean image intentionally has no setup.json, no marker and no per-user
    Security records.  Once any of those appear, arbitrary passwordless account
    creation must never be available again.
    """
    completed = False
    state = load_json(SETUP_STATE)
    if state:
        completed = bool(state.get("completed", False))
    if completed:
        return True
    if SECURITY_USERS.is_dir():
        try:
            for entry in SECURITY_USERS.iterdir():
                if not entry.is_dir():
                    continue
                # combo.json is root-owned evidence that a real interactive
                # identity reached Security enrollment, including deployments
                # whose historical setup.json was not preserved.
                if (entry / "combo.json").is_file():
                    return True
        except OSError:
            # Failure to prove pristine first boot must fail closed.
            return True
    return False


def setup_identity_allowed() -> bool:
    return _setup_identity_state_allows(
        IDENTITY_MARKER.exists(),
        bool(load_json(SETUP_STATE).get("completed", False)),
        _configured_identity_evidence(),
    )


def mark_identity_provisioned(username: str) -> None:
    # The marker is an integrity attestation, not a secret.  NeutronShell runs
    # as the unprivileged display account and must be able to READ it during
    # the one narrow first-boot authorization step, while only root may write
    # or replace it.  The directory is traverse-only for neutronos-shell and
    # the marker itself is group-read-only.
    try:
        shell_gid = grp.getgrnam("neutronos-shell").gr_gid
    except KeyError:
        fail("neutronos-shell group is unavailable")

    marker_dir = IDENTITY_MARKER.parent
    marker_dir.mkdir(parents=True, exist_ok=True, mode=0o710)
    os.chown(marker_dir, 0, shell_gid)
    os.chmod(marker_dir, 0o710)

    fd, temporary = tempfile.mkstemp(prefix="identity-provisioned.", dir=str(marker_dir))
    try:
        os.fchmod(fd, 0o640)
        os.fchown(fd, 0, shell_gid)
        with os.fdopen(fd, "w", encoding="utf-8", closefd=True) as handle:
            json.dump({"schema": 2, "provisioned": True, "username": username},
                      handle, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, IDENTITY_MARKER)
        os.chown(IDENTITY_MARKER, 0, shell_gid)
        os.chmod(IDENTITY_MARKER, 0o640)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass



def _run_command(arguments: list[str], description: str, timeout: int = 30) -> subprocess.CompletedProcess:
    try:
        result = subprocess.run(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"{description} failed: {exc}")
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        fail(f"{description} failed" + (f": {detail}" if detail else ""))
    return result


def _atomic_install(source: Path, destination: Path, mode: int) -> None:
    """Install one root-owned file without exposing a partial destination."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=destination.name + ".setup-", dir=str(destination.parent))
    try:
        with source.open("rb") as input_file, os.fdopen(descriptor, "wb") as output_file:
            shutil.copyfileobj(input_file, output_file)
            output_file.flush()
            os.fsync(output_file.fileno())
        os.chmod(temporary, mode)
        os.chown(temporary, 0, 0)
        os.replace(temporary, destination)
        directory_fd = os.open(str(destination.parent), os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _valid_ssh_host_key(private_key: Path) -> bool:
    """Validate a complete, unencrypted OpenSSH host identity."""
    public_key = Path(str(private_key) + ".pub")
    if (not private_key.is_file() or private_key.stat().st_size == 0 or
            not public_key.is_file() or public_key.stat().st_size == 0):
        return False
    try:
        derived = subprocess.run(
            ["/usr/bin/ssh-keygen", "-y", "-f", str(private_key)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, check=False, timeout=30)
        declared = public_key.read_text(encoding="ascii").strip().split()
        actual = derived.stdout.strip().split()
    except (OSError, UnicodeError, subprocess.TimeoutExpired):
        return False
    return derived.returncode == 0 and len(declared) >= 2 and len(actual) >= 2 and declared[:2] == actual[:2]


def _ssh_hostkey_diagnostic(event: str, *, reset: bool = False) -> None:
    """Persist one non-secret host-key stage for physical first-boot diagnosis."""
    clean = re.sub(r"[\r\n\x00-\x1f]+", " ", str(event)).strip()[:400]
    SSH_HOSTKEY_DIAGNOSTIC.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | getattr(os, "O_CLOEXEC", 0)
    flags |= os.O_TRUNC if reset else os.O_APPEND
    descriptor = os.open(SSH_HOSTKEY_DIAGNOSTIC, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        os.fchown(descriptor, 0, 0)
        os.write(descriptor, (clean + "\n").encode("utf-8"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _clean_ssh_host_keys(ssh_dir: Path = Path("/etc/ssh")) -> tuple[Path, ...]:
    """Create the key directory and remove only incomplete or invalid pairs.

    Valid identities from an interrupted attempt are retained; incomplete or
    invalid pairs are removed before one deterministic retry.
    """
    ssh_dir.mkdir(parents=True, exist_ok=True)
    os.chown(ssh_dir, 0, 0)
    os.chmod(ssh_dir, 0o755)
    required = tuple(ssh_dir / f"ssh_host_{algorithm}_key"
                     for algorithm in ("rsa", "ecdsa", "ed25519"))

    for private_key in required:
        public_key = Path(str(private_key) + ".pub")
        if private_key.exists() or public_key.exists():
            if _valid_ssh_host_key(private_key):
                continue
            for path in (private_key, public_key):
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass

    return required


def _generate_ssh_host_keys(ssh_dir: Path = Path("/etc/ssh"), *, diagnose: bool = False) -> None:
    """Generate each required host identity noninteractively and atomically.

    The physical release repeatedly failed before creating any file while the
    packaged aggregate ``ssh-keygen -A`` path was running.  Generate the same
    required algorithms individually so one algorithm has a deterministic
    command, result and retry boundary.  A temporary directory prevents a
    killed command from exposing a partial destination pair.
    """
    required = _clean_ssh_host_keys(ssh_dir)
    by_name = {path.name: path for path in required}
    if diagnose:
        _ssh_hostkey_diagnostic("GENERATION_STARTED")

    for algorithm, options in SSH_HOSTKEY_SPECS:
        destination = by_name[f"ssh_host_{algorithm}_key"]
        if _valid_ssh_host_key(destination):
            if diagnose:
                _ssh_hostkey_diagnostic(f"ALGORITHM_PRESERVED={algorithm}")
            continue

        if diagnose:
            _ssh_hostkey_diagnostic(f"ALGORITHM_STARTED={algorithm}")
        temporary_dir = Path(tempfile.mkdtemp(prefix=f".neutronos-{algorithm}-", dir=ssh_dir))
        temporary_key = temporary_dir / destination.name
        command = [
            "/usr/bin/ssh-keygen", "-q", "-t", algorithm, *options,
            "-N", "", "-C", f"NeutronOS {algorithm} host key",
            "-f", str(temporary_key),
        ]
        try:
            result = subprocess.run(
                command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, check=False, timeout=120)
            if result.returncode != 0:
                detail = (result.stderr or result.stdout or "no output").strip().splitlines()
                message = detail[-1][:180] if detail else "no output"
                if diagnose:
                    _ssh_hostkey_diagnostic(
                        f"ALGORITHM_FAILED={algorithm} returncode={result.returncode} error={message}")
                fail(f"OpenSSH {algorithm} host-key generation failed: {message}")
            if not _valid_ssh_host_key(temporary_key):
                if diagnose:
                    _ssh_hostkey_diagnostic(f"ALGORITHM_FAILED={algorithm} verification failed")
                fail(f"OpenSSH {algorithm} host-key generation did not produce a valid pair")

            temporary_public = Path(str(temporary_key) + ".pub")
            os.chown(temporary_key, 0, 0)
            os.chmod(temporary_key, 0o600)
            os.chown(temporary_public, 0, 0)
            os.chmod(temporary_public, 0o644)
            os.replace(temporary_public, Path(str(destination) + ".pub"))
            os.replace(temporary_key, destination)
            directory_fd = os.open(ssh_dir, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
            if diagnose:
                _ssh_hostkey_diagnostic(f"ALGORITHM_VERIFIED={algorithm}")
        except subprocess.TimeoutExpired:
            if diagnose:
                _ssh_hostkey_diagnostic(f"ALGORITHM_FAILED={algorithm} timeout")
            fail(f"OpenSSH {algorithm} host-key generation timed out")
        finally:
            shutil.rmtree(temporary_dir, ignore_errors=True)

    _verify_ssh_host_keys(ssh_dir)
    if diagnose:
        _ssh_hostkey_diagnostic("GENERATION_VERIFIED")


def _verify_ssh_host_keys(ssh_dir: Path = Path("/etc/ssh")) -> None:
    required = tuple(ssh_dir / f"ssh_host_{algorithm}_key"
                     for algorithm in ("rsa", "ecdsa", "ed25519"))

    invalid = [path.name for path in required if not _valid_ssh_host_key(path)]
    if invalid:
        fail("OpenSSH host-key verification failed: " + ", ".join(invalid))
    for private_key in required:
        os.chown(private_key, 0, 0)
        os.chmod(private_key, 0o600)
        public_key = Path(str(private_key) + ".pub")
        os.chown(public_key, 0, 0)
        os.chmod(public_key, 0o644)


def prepare_ssh_host_keys(args: list[str]) -> int:
    """Systemd ExecStartPre: clean only incomplete or invalid key pairs."""
    if args:
        fail("prepare-ssh-hostkeys accepts no arguments")
    _ssh_hostkey_diagnostic("PREPARE_STARTED", reset=True)
    required = _clean_ssh_host_keys()
    preserved = sum(1 for key in required if _valid_ssh_host_key(key))
    _ssh_hostkey_diagnostic(f"PREPARE_COMPLETE preserved={preserved}")
    return 0


def generate_ssh_host_keys(args: list[str]) -> int:
    """Systemd ExecStart: create the required identities one algorithm at a time."""
    if args:
        fail("generate-ssh-hostkeys accepts no arguments")
    _generate_ssh_host_keys(diagnose=True)
    return 0


def verify_ssh_host_keys(args: list[str]) -> int:
    """Systemd ExecStartPost: reject a generator run that did not make valid pairs."""
    if args:
        fail("verify-ssh-hostkeys accepts no arguments")
    _verify_ssh_host_keys()
    _ssh_hostkey_diagnostic("SUCCESS")
    print(json.dumps({"success": True, "hostKeys": "verified"}, separators=(",", ":")))
    return 0


def _ensure_ssh_host_keys(ssh_dir: Path = Path("/etc/ssh")) -> None:
    """Ask the authoritative unit to prepare keys, then independently verify."""
    if ssh_dir != Path("/etc/ssh"):
        _generate_ssh_host_keys(ssh_dir)
        return
    if _unit_load_state("neutronos-ssh-hostkeys.service") != "loaded":
        fail("NeutronOS OpenSSH host-key service is not installed")
    _run_command(
        ["/usr/bin/systemctl", "restart", "neutronos-ssh-hostkeys.service"],
        "OpenSSH host-key service", timeout=120)
    _verify_ssh_host_keys(ssh_dir)


def _unit_load_state(unit: str) -> str:
    result = subprocess.run(
        ["/usr/bin/systemctl", "show", unit, "-p", "LoadState", "--value"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
        timeout=10,
    )
    return result.stdout.strip().lower() if result.returncode == 0 else "not-found"


def _read_setup_preferences(raw_path: str) -> dict:
    if raw_path != str(SETUP_PREFERENCES):
        fail("apply-preferences must use the authoritative NeutronOS setup preferences path")

    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(SETUP_PREFERENCES, flags)
    except OSError as exc:
        fail(f"setup preferences cannot be opened: {exc}")

    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_mode & 0o022 or
                info.st_size <= 0 or info.st_size > 128 * 1024):
            fail("setup preferences have unsafe type, mode, or size")
        with os.fdopen(descriptor, "r", encoding="utf-8", closefd=False) as handle:
            payload = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError) as exc:
        fail(f"setup preferences are invalid: {exc}")
    finally:
        os.close(descriptor)

    if not isinstance(payload, dict):
        fail("setup preferences must be a JSON object")
    if not isinstance(payload.get("sshEnabled"), bool):
        fail("setup preferences are missing the authoritative sshEnabled boolean")
    return payload


def _prepare_ssh_account_authentication() -> None:
    """Allow the account password explicitly provisioned by Setup.

    Debian cloud images disable password authentication in their base config.
    Include files precede that config. The Security Core's earlier-sorted
    99-neutronos-security.conf can still enforce enrolled-key-only hardening.
    """
    SSH_SETUP_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    content = ("# Managed by Gemini Setup SSH preference.\n"
               "PermitRootLogin no\nPermitEmptyPasswords no\n"
               "PasswordAuthentication yes\nKbdInteractiveAuthentication no\n")
    if SSH_SETUP_CONFIG.is_symlink():
        fail("Setup SSH authentication configuration must not be a symbolic link")
    descriptor, staged = tempfile.mkstemp(prefix=".neutronos-ssh-", dir=SSH_SETUP_CONFIG.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staged, SSH_SETUP_CONFIG)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)


def _verify_ssh_listener() -> None:
    """Require a non-loopback TCP/22 listener and a real OpenSSH greeting."""
    external = False
    for table in (Path("/proc/net/tcp"), Path("/proc/net/tcp6")):
        try:
            rows = table.read_text().splitlines()[1:]
        except FileNotFoundError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) < 4 or fields[3] != "0A":
                continue
            address, port = fields[1].split(":")
            if port.upper() != "0016":
                continue
            loopback = address.upper() == "00000000000000000000000001000000" if len(address) == 32 else address.upper().endswith("7F")
            if not loopback:
                external = True
    if not external:
        fail("SSH service is active but no non-loopback TCP/22 listener exists; inspect sshd -T listenaddress and journalctl -b -u ssh.service")
    details = []
    for host in ("127.0.0.1", "::1"):
        try:
            with socket.create_connection((host, 22), timeout=3) as connection:
                greeting = connection.recv(256)
            if greeting.startswith(b"SSH-2.0-"):
                return
            details.append("invalid SSH greeting")
        except OSError as exc:
            details.append(str(exc))
    fail("TCP/22 listener did not answer an SSH handshake: " + "; ".join(details)[:200])


def _apply_ssh_enabled(enabled: bool) -> None:
    if _unit_load_state("ssh.service") != "loaded":
        fail("OpenSSH ssh.service is not installed")

    if enabled:
        try:
            SSHD_NOT_TO_BE_RUN.unlink()
        except FileNotFoundError:
            pass
        except OSError as exc:
            fail(f"cannot clear OpenSSH disabled marker: {exc}")

        _ensure_ssh_host_keys()
        _prepare_ssh_account_authentication()
        # Debian removes ssh.service RuntimeDirectory when SSH is stopped.
        # Restore its vendor tmpfiles declaration before the preflight check.
        _run_command(["/usr/bin/systemd-tmpfiles", "--create", "--prefix=/run/sshd"],
                     "OpenSSH runtime directory preparation")
        _run_command(["/usr/sbin/sshd", "-t"], "OpenSSH configuration validation")
        _run_command(["/usr/bin/systemctl", "enable", "ssh.service"],
                     "persistent SSH service enablement")
        _run_command(["/usr/bin/systemctl", "start", "ssh.service"],
                     "SSH service start")
        _run_command(["/usr/bin/systemctl", "reload", "ssh.service"],
                     "SSH authentication configuration reload")

        enabled_state = subprocess.run(
            ["/usr/bin/systemctl", "is-enabled", "ssh.service"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        ).stdout.strip().lower()
        active_state = subprocess.run(
            ["/usr/bin/systemctl", "is-active", "ssh.service"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        ).stdout.strip().lower()

        if enabled_state not in ("enabled", "enabled-runtime"):
            fail(f"SSH service did not become persistently enabled: {enabled_state or 'unknown'}")
        if active_state != "active":
            fail(f"SSH service did not become active: {active_state or 'unknown'}")
        _verify_ssh_listener()
        return

    if _unit_load_state("ssh.socket") == "loaded":
        _run_command(["/usr/bin/systemctl", "disable", "--now", "ssh.socket"],
                     "SSH socket disablement")
    _run_command(["/usr/bin/systemctl", "disable", "--now", "ssh.service"],
                 "persistent SSH service disablement")

    enabled_state = subprocess.run(
        ["/usr/bin/systemctl", "is-enabled", "ssh.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
        timeout=10,
    ).stdout.strip().lower()
    active_state = subprocess.run(
        ["/usr/bin/systemctl", "is-active", "ssh.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
        timeout=10,
    ).stdout.strip().lower()

    if enabled_state in ("enabled", "enabled-runtime"):
        fail("SSH service remained enabled after Setup requested disabled")
    if active_state == "active":
        fail("SSH service remained active after Setup requested disabled")


def prepare_controller_bluetooth(args: list[str]) -> int:
    """Restore only the BlueZ prerequisites required by controller registration."""
    if args:
        fail("controller Bluetooth preparation accepts no arguments")
    _run_command(["/usr/bin/systemctl", "start", "bluetooth.service"],
                 "Bluetooth service activation", timeout=30)
    _run_command(["/usr/sbin/rfkill", "unblock", "bluetooth"],
                 "Bluetooth rfkill unblock", timeout=10)
    last_detail = "adapter did not appear"
    for _attempt in range(20):
        query = subprocess.run(
            ["/usr/bin/busctl", "--system", "--timeout=3", "get-property",
             "org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "Powered"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, check=False, timeout=5)
        if query.returncode == 0:
            if query.stdout.strip() == "b true":
                break
            power = subprocess.run(
                ["/usr/bin/busctl", "--system", "--timeout=3", "set-property",
                 "org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1",
                 "Powered", "b", "true"], stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                check=False, timeout=5)
            last_detail = (power.stderr or power.stdout or "power request failed").strip()
        else:
            last_detail = (query.stderr or query.stdout or "adapter query failed").strip()
        import time
        time.sleep(0.25)
    else:
        fail("Bluetooth adapter preparation failed: " + last_detail[:180])
    print(json.dumps({"success": True, "bluetooth": "ready"}, separators=(",", ":")))
    return 0


def apply_ssh_preferences(args: list[str]) -> int:
    if len(args) != 1:
        fail("apply-preferences SSH persistence requires exactly one preferences path")
    preferences = _read_setup_preferences(args[0])
    enabled = bool(preferences["sshEnabled"])
    _apply_ssh_enabled(enabled)
    print(json.dumps({
        "success": True,
        "sshEnabled": enabled,
        "sshService": "enabled" if enabled else "disabled",
    }, separators=(",", ":")))
    return 0


def prepare_ssh_preferences(args: list[str]) -> None:
    """Prepare per-installation keys before delegated Security finalization.

    The real preference helper stops, finalizes, and restarts Security Core.
    Generating keys only after that transaction reproduced the physical-only
    timeout even though the same generator succeeds before Security is
    commissioned.  Preparation creates no listener and does not enable SSH;
    service activation still happens only after the delegated preferences
    transaction succeeds.
    """
    if len(args) != 1:
        fail("apply-preferences SSH persistence requires exactly one preferences path")
    preferences = _read_setup_preferences(args[0])
    if bool(preferences["sshEnabled"]):
        _ensure_ssh_host_keys()


def power_action(args: list[str]) -> int:
    if len(args) != 1:
        fail("power-action requires exactly one supported action")
    action = args[0].strip().lower()
    commands = {
        "shutdown": ["/usr/sbin/poweroff"],
        "restart": ["/usr/bin/systemctl", "--no-block", "restart", "neutronos.service"],
        "reboot": ["/usr/sbin/reboot"],
    }
    command = commands.get(action)
    if command is None:
        fail("unsupported power action")
    _run_command(command, f"NeutronOS {action}", timeout=20)
    print(json.dumps({"success": True, "action": action}, separators=(",", ":")))
    return 0


def finalize_setup_if_complete(args: list[str]) -> int:
    if args:
        fail("finalize-setup does not accept arguments")

    request = SETUP_DIR / "finalize-request"
    if not SETUP_STATE.exists():
        if request.exists():
            fail("finalization requested but Setup state is missing")
        state = {}
    else:
        try:
            state = json.loads(SETUP_STATE.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as exc:
            fail(f"Setup state cannot be read for finalization: {exc}")
        if not isinstance(state, dict):
            fail("Setup state is not an object")
    if state.get("completed") is not True:
        if request.exists():
            fail("finalization requested before Setup is complete")
        print(json.dumps({"success": True, "finalized": False,
                          "reason": "setup incomplete"}, separators=(",", ":")))
        return 0

    finalized = ACCOUNT_HANDOFF_FINALIZED
    require_root_owned(finalized.parent, directory=True)
    if finalized.exists() or finalized.is_symlink():
        require_root_owned(finalized, directory=False)
        if finalized.read_bytes() != b"account-handoff-finalized-v1\n":
            fail("account handoff finalization stamp is invalid")
        request.unlink(missing_ok=True)
        print(json.dumps({"success": True, "finalized": True, "alreadyFinalized": True}))
        return 0

    removed_banner = False
    if RENAME_USER_CONF.exists():
        try:
            info = RENAME_USER_CONF.stat(follow_symlinks=False)
            text = RENAME_USER_CONF.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            fail(f"obsolete Raspberry Pi SSH banner configuration cannot be inspected: {exc}")

        lines = [
            line.strip() for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        expected = f"Banner {RPI_SSH_BANNER}"
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
                info.st_mode & 0o022 or lines != [expected]):
            fail("refusing to remove an unexpected rename_user.conf")

        try:
            RENAME_USER_CONF.unlink()
            removed_banner = True
        except OSError as exc:
            fail(f"obsolete Raspberry Pi SSH banner configuration cannot be removed: {exc}")

    if _unit_load_state("userconfig.service") == "loaded":
        active = subprocess.run(
            ["/usr/bin/systemctl", "is-active", "userconfig.service"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        ).stdout.strip().lower()
        enabled = subprocess.run(
            ["/usr/bin/systemctl", "is-enabled", "userconfig.service"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=10,
        ).stdout.strip().lower()

        if active == "active":
            _run_command(["/usr/bin/systemctl", "stop", "userconfig.service"],
                         "Raspberry Pi user configuration service stop")
        if enabled in ("enabled", "enabled-runtime"):
            _run_command(["/usr/bin/systemctl", "disable", "userconfig.service"],
                         "Raspberry Pi user configuration service disablement")

    ssh_active = subprocess.run(
        ["/usr/bin/systemctl", "is-active", "ssh.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
        timeout=10,
    ).stdout.strip().lower()
    if ssh_active == "active":
        _run_command(["/usr/sbin/sshd", "-t"],
                     "OpenSSH validation after Setup banner retirement")
        _run_command(["/usr/bin/systemctl", "reload", "ssh.service"],
                     "OpenSSH reload after Setup banner retirement")

    descriptor, temporary = tempfile.mkstemp(prefix=".account-handoff-", dir=str(finalized.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(b"account-handoff-finalized-v1\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, finalized)
        directory_fd = os.open(str(finalized.parent), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        Path(temporary).unlink(missing_ok=True)
    request.unlink(missing_ok=True)
    print(json.dumps({
        "success": True,
        "finalized": True,
        "rpiSshBannerRetired": not RENAME_USER_CONF.exists(),
    }, separators=(",", ":")))
    return 0


def delegate(argv: list[str], input_text: str | None = None) -> int:
    if not REAL_HELPER.is_file() or not os.access(REAL_HELPER, os.X_OK):
        fail("real NeutronOS privileged helper is missing")
    result = subprocess.run([str(REAL_HELPER), *argv], input=input_text, text=True, check=False)
    return int(result.returncode)


def self_test() -> int:
    checks = {
        "securityDestinationReserved": reserved_destination("/etc/systemd/system/neutron-securityd.service"),
        "firewallDestinationReserved": reserved_destination("/etc/systemd/system/neutronos-firewall-guard.service"),
        "normalDestinationAllowed": not reserved_destination("/etc/systemd/system/torrentlab-remote.service"),
        "sharedRuntimeRejected": bool(SECURITY_RESERVED_UNIT_PATTERNS[0].search("RuntimeDirectory=neutronos\n")),
        "netAdminRejected": bool(SECURITY_RESERVED_UNIT_PATTERNS[2].search("CapabilityBoundingSet=CAP_NET_ADMIN\n")),
        "nftInvocationRejected": bool(SECURITY_RESERVED_UNIT_PATTERNS[3].search("ExecStart=/usr/sbin/nft list ruleset\n")),
        "identityPristineAllowed": _setup_identity_state_allows(False, False, False),
        "identityMarkerRejected": not _setup_identity_state_allows(True, False, False),
        "identityCompletedRejected": not _setup_identity_state_allows(False, True, False),
        "identityEvidenceRejected": not _setup_identity_state_allows(False, False, True),
    }
    ok = all(checks.values())
    print(json.dumps({"ok": ok, "checks": checks}, sort_keys=True))
    return 0 if ok else 1


def set_system_timezone(args: list[str]) -> int:
    if len(args) != 1:
        fail("set-timezone requires one timezone identifier")
    zone = args[0]
    if (not zone or zone.startswith("/") or ".." in Path(zone).parts or
            not re.fullmatch(r"[A-Za-z0-9_+./-]{1,100}", zone)):
        fail("invalid timezone identifier")
    zone_root = Path("/usr/share/zoneinfo").resolve()
    target = (zone_root / zone).resolve()
    if zone_root not in target.parents or not target.is_file():
        fail("timezone is not installed")
    _run_command(["/usr/bin/timedatectl", "set-timezone", zone],
                 "system timezone update")
    actual = _run_command(["/usr/bin/timedatectl", "show", "-p", "Timezone", "--value"],
                          "system timezone verification").stdout.strip()
    if actual != zone:
        fail("system timezone verification failed")
    print(json.dumps({"success": True, "timezone": actual}, separators=(",", ":")))
    return 0


def storage_setup(args: list[str]) -> int:
    if not args or args[0] not in ("inspect", "provision"):
        fail("unsupported storage action")
    if (args[0] == "inspect" and len(args) != 1) or (args[0] == "provision" and len(args) != 2):
        fail("invalid storage request")
    if args[0] == "provision":
        if load_json(SETUP_STATE).get("completed") is True:
            fail("storage setup is closed after first boot completion")
        if not IDENTITY_MARKER.is_file():
            fail("create the first-boot account before provisioning storage")
        identity = load_json(IDENTITY_MARKER)
        username = str(identity.get("username") or "")
        if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
            fail("first-boot account identity is invalid")
        args = [*args, username]
    script = Path("/usr/local/libexec/neutronos-storage-setup.py")
    if not script.is_file():
        fail("storage setup helper is missing")
    try:
        process = subprocess.Popen(["/usr/bin/python3", str(script), *args],
                                   text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, bufsize=1)
        assert process.stdout is not None
        for line in process.stdout:
            print(line.rstrip("\n"), flush=True)
        return int(process.wait(timeout=210))
    except (OSError, subprocess.TimeoutExpired) as exc:
        try:
            process.kill()
        except (NameError, OSError):
            pass
        fail(f"storage setup failed: {exc}")


def provision_before_identity(username: str) -> None:
    # Never create a human account on SYSTEM and later hide its home by mounting DATA.
    script = Path("/usr/local/libexec/neutronos-storage-setup.py")
    if not script.is_file():
        fail("Gemini DATA provisioning helper is unavailable")
    try:
        inspected = subprocess.run(["/usr/bin/python3", str(script), "inspect"],
                                   capture_output=True, text=True, timeout=30, check=True)
        plan = json.loads(inspected.stdout)
        fingerprint = str(plan.get("fingerprint") or "")
        if not fingerprint:
            fail("Gemini installation drive could not be verified")
        subprocess.run(["/usr/bin/python3", str(script), "provision", fingerprint, username],
                       capture_output=True, text=True, timeout=240, check=True)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        fail(f"DATA must be provisioned before account creation: {exc}")


def prepare_human_storage(username: str) -> None:
    _run_command(["/usr/bin/python3", "/usr/local/libexec/neutronos-storage-setup.py", "prepare-user", username],
                 "canonical human storage preparation")
    _run_command(["/usr/bin/python3", "/usr/local/libexec/neutronos-human-storage-owner.py"],
                 "human storage ownership preparation")


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    if os.geteuid() != 0:
        fail("root required")
    if len(sys.argv) < 2:
        fail("action required")

    action = sys.argv[1]
    args = sys.argv[2:]

    if action in ("backup-create", "backup-list", "backup-verify", "backup-restore-stage", "backup-delete"):
        return backup_operation(action, args)

    if action in ("recovery-status", "recovery-apply-update", "recovery-apply-backup",
                  "recovery-cancel", "recovery-reboot"):
        return recovery_operation(action, args)

    if action == "set-timezone":
        return set_system_timezone(args)

    if action == "storage-setup":
        return storage_setup(args)

    if action == "power-action":
        return power_action(args)

    if action == "prepare-controller-bluetooth":
        return prepare_controller_bluetooth(args)

    if action == "prepare-ssh-hostkeys":
        return prepare_ssh_host_keys(args)

    if action == "generate-ssh-hostkeys":
        return generate_ssh_host_keys(args)

    if action == "verify-ssh-hostkeys":
        return verify_ssh_host_keys(args)

    if action == "apply-preferences":
        prepare_ssh_preferences(args)
        rc = delegate([action, *args])
        if rc != 0:
            return rc
        return apply_ssh_preferences(args)

    if action == "sync-ssh-preference":
        return apply_ssh_preferences(args)

    if action == "finalize-setup":
        return finalize_setup_if_complete(args)

    if action == "setup-identity":
        if not setup_identity_allowed():
            fail("identity provisioning is sealed; setup-identity is first-boot one-shot only")
        if (len(args) != 3 or not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", args[1]) or
                args[1] in ("root", "neutronos", "neutronos", "nobody")):
            fail("invalid Gemini human identity")
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", args[0]):
            fail("invalid hostname")
        password = sys.stdin.readline().rstrip("\n")
        if len(password) < 8 or "\r" in password or ":" in password:
            fail("invalid account password")
        provision_before_identity(args[1])
        rc = delegate([action, *args], password + "\n")
        if rc == 0:
            prepare_human_storage(args[1])
            mark_identity_provisioned(args[1])
        return rc

    if action == "appstore-install-signed":
        if len(args) != 3:
            fail("invalid appstore signed install request")
        package_path, expected_sha, package_id = args
        staged = copy_and_hash(Path(package_path), expected_sha)
        try:
            return delegate([action, str(staged), expected_sha, package_id])
        finally:
            try:
                staged.unlink()
            except FileNotFoundError:
                pass

    if action == "appstore-uninstall" and len(args) == 1:
        validate_registered_uninstall(str(args[0]).strip().lower())
    elif action == "appstore-root-rollback" and len(args) == 1:
        validate_rollback(str(args[0]).strip())

    return delegate([action, *args])


if __name__ == "__main__":
    raise SystemExit(main())
