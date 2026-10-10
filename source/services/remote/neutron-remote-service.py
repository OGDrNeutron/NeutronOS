#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import grp
import hashlib
import hmac
import json
import os
import pwd
import stat
import secrets
import signal
import socket
import re
import time
import struct
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import Any

BROKER_NAME = "neutronos-remote-service"
PROTOCOL_VERSION = 1
GATEKEEPER_ID = "neutronremotesystems"
ADMIN_BRIDGE_RELATIVE = "scripts/apps/neutronremotesystems/remote-systems-bridge.py"
SYSTEM_ADMIN_HELPER = Path(os.environ.get("NEUTRONOS_REMOTE_SYSTEM_ADMIN_HELPER", "/usr/local/lib/neutronos/remote-systems-bridge.py"))
MAX_MESSAGE = 1024 * 1024
DURATION_SECONDS = {
    "1h": 3600,
    "3h": 10800,
    "6h": 21600,
    "12h": 43200,
    "24h": 86400,
}

STATE_ROOT = Path(os.environ.get("NEUTRONOS_STATE_DIR", "/var/lib/neutronos"))
ROOT_REGISTRY_PATH = STATE_ROOT / "app-store" / "root-installed.json"
APP_STATE_DIR = STATE_ROOT / "apps" / GATEKEEPER_ID
BROKER_PRIVATE_DIR = APP_STATE_DIR / "broker"
BROKER_STATE_PATH = BROKER_PRIVATE_DIR / "broker-state.json"
LEGACY_BROKER_STATE_PATH = APP_STATE_DIR / "broker-state.json"
ADMIN_SOCKET_PATH = Path(os.environ.get("NEUTRONOS_REMOTE_ADMIN_SOCKET", "/run/neutronos/remote-service-admin.sock"))
PROVIDER_SOCKET_PATH = Path(os.environ.get("NEUTRONOS_REMOTE_PROVIDER_SOCKET", "/run/neutronos/remote-service-provider.sock"))
SOCKET_GROUP = os.environ.get("NEUTRONOS_REMOTE_SOCKET_GROUP", "neutronos-shell")
OWNER_NAME = os.environ.get("NEUTRONOS_OWNER", "neutronos")
SYSTEMCTL = "/usr/bin/systemctl"
WEB_CONTROLLER_URL = "https://remote.neutronos"
WEB_CONTROLLER_UNITS = [
    "neutronos-remote-pam-agent.service",
    "neutronos-remote-controller.service",
    "neutronos-remote-controller-fallback.service",
    "neutronos-remote-ui-bridge.service",
    "neutronos-remote-input.service",
    "neutronos-remote-dns.service",
    "neutronos-remote-edge.service",
]
WEB_CONTROLLER_REQUIRED = {
    "neutronos-remote-pam-agent.service",
    "neutronos-remote-controller.service",
    "neutronos-remote-controller-fallback.service",
    "neutronos-remote-dns.service",
    "neutronos-remote-edge.service",
}
REMOTE_EDGE_STATUS = Path("/run/neutronos/remote-edge.json")
WEB_CONTROLLER_FLAG = Path("/var/lib/neutronos/remote/web-controller.enabled")
WEB_CONTROLLER_PORT_CONFIG = Path("/var/lib/neutronos/remote/web-controller-port.json")
FIREWALL_FACTORY_POLICY = Path("/etc/neutronos/firewall-normal.nft")
SYSTEM_DEFAULT_WEB_PORT = 443

_lock = threading.RLock()
_stop = threading.Event()




def prepare_state_dirs() -> None:
    """Keep the package-helper cwd traversable while protecting broker state.

    PackageAppBridgeManager launches the app-owned bridge with
    /var/lib/neutronos/apps/<app-id> as its working directory.  The 1.0.0
    broker made that directory root-only (0700), which caused QProcess to
    fail before exec with "chdir: Permission denied".  The parent is now
    traversal-safe while broker secrets live in a root-only child directory.
    """
    APP_STATE_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(APP_STATE_DIR, 0o755)
    BROKER_PRIVATE_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(BROKER_PRIVATE_DIR, 0o700)

    if LEGACY_BROKER_STATE_PATH.exists() and not BROKER_STATE_PATH.exists():
        os.replace(LEGACY_BROKER_STATE_PATH, BROKER_STATE_PATH)
        os.chmod(BROKER_STATE_PATH, 0o600)

def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso(value: dt.datetime | None) -> str:
    return value.isoformat() if value else ""


def parse_iso(value: Any) -> dt.datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def load_json(path: Path, fallback: Any) -> Any:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return fallback


def atomic_json(path: Path, value: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def human_payload_roots() -> list[Path]:
    roots=[]
    if not os.path.ismount('/NeutronOS'): return roots
    for account in pwd.getpwall():
        home=Path('/NeutronOS')/account.pw_name
        if (account.pw_uid>=1000 and account.pw_dir==str(home) and
                not account.pw_shell.endswith(('nologin','false')) and home.is_dir() and not home.is_symlink()):
            apps=home/'apps'
            payload=apps/'payload'
            if not apps.is_symlink() and not payload.is_symlink(): roots.append(payload)
    return roots


def trusted_registry() -> dict[str, Any]:
    # Capability authority remains root-owned after normal payload moves to DATA.
    try:
        descriptor=os.open(ROOT_REGISTRY_PATH,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
        with os.fdopen(descriptor,'r',encoding='utf-8') as handle:
            info=os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or info.st_mode&0o022 or info.st_size>1024*1024:
                return {'schema':1,'packages':{}}
            value=json.load(handle)
        return value if isinstance(value,dict) and isinstance(value.get('packages'),dict) else {'schema':1,'packages':{}}
    except (OSError,ValueError):
        return {'schema':1,'packages':{}}


def load_registry() -> dict[str, Any]:
    # Human manifests contribute display metadata only, never privileged authority.
    trusted=trusted_registry()
    local={}
    for payload in human_payload_roots():
        try:
            descriptor=os.open(payload.parent/'installed.json',os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
            with os.fdopen(descriptor,'r',encoding='utf-8') as handle:
                info=os.fstat(handle.fileno())
                home_account=pwd.getpwnam(payload.parts[2])
                if not stat.S_ISREG(info.st_mode) or info.st_size>1024*1024 or info.st_uid not in (home_account.pw_uid,pwd.getpwnam(OWNER_NAME).pw_uid): continue
                local_value=json.load(handle)
            records=local_value.get('packages',{}) if isinstance(local_value,dict) else {}
        except (OSError,ValueError,KeyError):
            continue
        if isinstance(records,dict):
            for app_id,record in records.items():
                if isinstance(record,dict): local.setdefault(app_id,record)
    packages={}
    for app_id,authority in trusted.get('packages',{}).items():
        if not isinstance(authority,dict): continue
        record=dict(authority)
        metadata=local.get(app_id,{})
        if metadata: record['name']=str(metadata.get('name') or record.get('name') or app_id)
        packages[app_id]=record
    return {'schema':1,'packages':packages}


def default_state() -> dict[str, Any]:
    return {"schema": 1, "protocolVersion": PROTOCOL_VERSION, "grants": {}, "audit": []}


def load_state() -> dict[str, Any]:
    value = load_json(BROKER_STATE_PATH, default_state())
    if not isinstance(value, dict):
        value = default_state()
    if not isinstance(value.get("grants"), dict):
        value["grants"] = {}
    if not isinstance(value.get("audit"), list):
        value["audit"] = []
    value["schema"] = 1
    value["protocolVersion"] = PROTOCOL_VERSION
    return value


def save_state(value: dict[str, Any]) -> None:
    atomic_json(BROKER_STATE_PATH, value, 0o600)


def audit(state: dict[str, Any], event: str, **fields: Any) -> None:
    rows = state.setdefault("audit", [])
    row = {"timestamp": iso(utcnow()), "event": event}
    row.update(fields)
    rows.append(row)
    if len(rows) > 1000:
        del rows[: len(rows) - 1000]


def normalized_remote_capabilities(package: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    raw = package.get("remoteCapabilities")
    if not isinstance(raw, list):
        return result
    app_id = str(package.get("id") or "").strip().lower()
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        if str(entry.get("broker") or BROKER_NAME).strip().lower() != BROKER_NAME:
            continue
        capability_id = str(entry.get("id") or "").strip().lower()
        provider = str(entry.get("provider") or "").strip()
        prefix = f"scripts/apps/{app_id}/"
        if not capability_id or not provider.startswith(prefix):
            continue
        result.append({
            "id": capability_id,
            "provider": provider,
            "broker": BROKER_NAME,
            "defaultAllowed": bool(entry.get("defaultAllowed", False)),
        })
    return result


def provider_apps() -> list[dict[str, Any]]:
    registry = load_registry()
    packages = registry.get("packages", {})
    rows: list[dict[str, Any]] = []
    for app_id in sorted(packages):
        package = packages.get(app_id)
        if not isinstance(package, dict):
            continue
        capabilities = normalized_remote_capabilities(package)
        if not capabilities:
            continue
        services: list[dict[str, Any]] = []
        backend = package.get("backend") if isinstance(package.get("backend"), dict) else {}
        backend_entrypoint = str(backend.get("entrypoint") or "")
        for capability in capabilities:
            provider = capability["provider"]
            helper_name = Path(provider).name
            direct_expected = f"scripts/apps/{app_id}/{helper_name}"
            direct = provider == direct_expected
            same_as_backend = not backend_entrypoint or backend_entrypoint == provider
            bridge_compatible = direct and same_as_backend
            services.append({
                "id": capability["id"],
                "provider": provider,
                "helperName": helper_name if bridge_compatible else "",
                "bridgeCompatible": bridge_compatible,
                "bridgeReason": "" if bridge_compatible else (
                    "provider must be the package backend entrypoint" if direct and not same_as_backend
                    else "provider must be a direct package helper"
                ),
                "defaultAllowed": capability["defaultAllowed"],
            })
        rows.append({
            "appId": app_id,
            "name": str(package.get("name") or app_id),
            "version": str(package.get("version") or ""),
            "iconKey": app_id,
            "services": services,
        })
    return rows


def package_for(app_id: str) -> dict[str, Any]:
    packages = trusted_registry().get("packages", {})
    package = packages.get(app_id)
    return package if isinstance(package, dict) else {}


def capability_for(app_id: str, capability_id: str) -> dict[str, Any]:
    package = package_for(app_id)
    for entry in normalized_remote_capabilities(package):
        if entry["id"] == capability_id:
            return entry
    return {}


def peer_credentials(conn: socket.socket) -> tuple[int, int, int]:
    raw = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", raw)
    return pid, uid, gid


def package_owns(app_id: str, relative: str) -> bool:
    package = package_for(app_id)
    files = package.get("files")
    return isinstance(files, list) and relative in {str(value) for value in files}


def peer_in_neutronos_service(pid: int) -> bool:
    try:
        lines = Path(f"/proc/{pid}/cgroup").read_text(encoding="utf-8").splitlines()
    except OSError:
        return False
    return any("neutronos.service" in line.rsplit(":", 1)[-1].split("/") for line in lines)


def exact_script_invocation(pid: int, expected: Path, *, verified_payload_hash: bool = False) -> bool:
    """Bind identity to the actual executable/script position, never spare argv."""
    try:
        expected = expected.resolve(strict=True)
        info = expected.stat()
        if not stat.S_ISREG(info.st_mode) or (info.st_mode & (stat.S_IWGRP | stat.S_IWOTH) and not verified_payload_hash):
            return False
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
        argv = [token.decode("utf-8") for token in raw.split(b"\0") if token]
        executable = Path(f"/proc/{pid}/exe").resolve(strict=True)
        executable_info = executable.stat()
        if executable_info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            return False
    except (OSError, UnicodeDecodeError):
        return False
    if not argv:
        return False
    # Native helper: executable itself must be the registered helper.
    if executable == expected:
        return True
    # Script helper: the registered script must be argv[1], which is where the
    # kernel places a shebang script.  argv[2+] is attacker-controlled data and
    # is deliberately ignored for identity purposes.
    if len(argv) < 2:
        return False
    try:
        actual_script = Path(argv[1]).resolve(strict=True)
    except OSError:
        return False
    return actual_script == expected and executable.name.startswith("python")


def verify_owned_peer(pid: int, uid: int, app_id: str, relative: str) -> bool:
    if not package_owns(app_id, relative) or not peer_in_neutronos_service(pid):
        return False
    try:
        owner_uid = pwd.getpwnam(OWNER_NAME).pw_uid
    except KeyError:
        return False
    if uid != owner_uid:
        return False
    hashes=package_for(app_id).get('fileSha256',{})
    expected_hash=str(hashes.get(relative) or '').lower() if isinstance(hashes,dict) else ''
    if not re.fullmatch(r'[0-9a-f]{64}',expected_hash): return False
    for payload in human_payload_roots():
        try:
            expected=(payload/relative).resolve(strict=True)
            if payload.resolve() not in expected.parents: continue
            actual_hash=hashlib.sha256(expected.read_bytes()).hexdigest()
            if not hmac.compare_digest(actual_hash,expected_hash): continue
            # ACLs give the display service access to human-owned files. Hash
            # authority is from the trusted root registry, not human metadata.
            if exact_script_invocation(pid,expected,verified_payload_hash=True): return True
        except OSError:
            continue
    return False


def verify_admin_peer(pid: int, uid: int) -> bool:
    # Neutron Remote Systems is an OS-owned system app. Its administrative
    # bridge is root-owned outside writable App Store payload storage. Provider
    # apps remain registry/hash-bound through verify_owned_peer().
    if not peer_in_neutronos_service(pid):
        return False
    try:
        owner_uid = pwd.getpwnam(OWNER_NAME).pw_uid
        expected = SYSTEM_ADMIN_HELPER.resolve(strict=True)
        info = expected.stat()
    except (KeyError, OSError):
        return False
    if uid != owner_uid or info.st_uid != 0 or not stat.S_ISREG(info.st_mode):
        return False
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return False
    return exact_script_invocation(pid, expected)


def verify_provider_peer(pid: int, uid: int, app_id: str, capability_id: str) -> bool:
    capability = capability_for(app_id, capability_id)
    provider = str(capability.get("provider") or "")
    return bool(provider) and verify_owned_peer(pid, uid, app_id, provider)

def grant_view(app_id: str, state: dict[str, Any] | None = None) -> dict[str, Any]:
    state = state or load_state()
    raw = state.get("grants", {}).get(app_id, {})
    if not isinstance(raw, dict):
        raw = {}
    enabled = bool(raw.get("enabled", False))
    duration = str(raw.get("durationCode") or "")
    expires = parse_iso(raw.get("expiresAt"))
    now = utcnow()
    active = enabled and (duration == "indefinite" or (expires is not None and expires > now))
    remaining = -1 if active and duration == "indefinite" else 0
    if active and expires is not None:
        remaining = max(0, int((expires - now).total_seconds()))
    return {
        "enabled": enabled,
        "active": active,
        "durationCode": duration,
        "expiresAt": str(raw.get("expiresAt") or ""),
        "updatedAt": str(raw.get("updatedAt") or ""),
        "remainingSeconds": remaining,
    }


def prune_expired(state: dict[str, Any]) -> bool:
    changed = False
    grants = state.get("grants", {})
    if not isinstance(grants, dict):
        return False
    for app_id, raw in list(grants.items()):
        if not isinstance(raw, dict) or not raw.get("enabled"):
            continue
        view = grant_view(app_id, state)
        if not view["active"] and str(raw.get("durationCode") or "") != "indefinite":
            raw["enabled"] = False
            raw["expiredAt"] = iso(utcnow())
            audit(state, "grant-expired", appId=app_id)
            changed = True
    return changed


def set_grant(app_id: str, duration_code: str) -> dict[str, Any]:
    if app_id not in {row["appId"] for row in provider_apps()}:
        raise ValueError("app does not advertise a NeutronOS remote service")
    if duration_code != "indefinite" and duration_code not in DURATION_SECONDS:
        raise ValueError("unsupported remote grant duration")
    with _lock:
        state = load_state()
        now = utcnow()
        expires = None if duration_code == "indefinite" else now + dt.timedelta(seconds=DURATION_SECONDS[duration_code])
        state["grants"][app_id] = {
            "enabled": True,
            "durationCode": duration_code,
            "expiresAt": iso(expires),
            "updatedAt": iso(now),
            "grantId": secrets.token_urlsafe(18),
        }
        audit(state, "grant-created", appId=app_id, durationCode=duration_code, expiresAt=iso(expires))
        save_state(state)
        return grant_view(app_id, state)


def revoke_grant(app_id: str, reason: str = "manual") -> dict[str, Any]:
    with _lock:
        state = load_state()
        current = state.get("grants", {}).get(app_id)
        if isinstance(current, dict):
            current["enabled"] = False
            current["revokedAt"] = iso(utcnow())
            current["revokeReason"] = reason
        audit(state, "grant-revoked", appId=app_id, reason=reason)
        save_state(state)
        return grant_view(app_id, state)


def discover_payload() -> list[dict[str, Any]]:
    with _lock:
        state = load_state()
        if prune_expired(state):
            save_state(state)
        rows = provider_apps()
        for row in rows:
            row["grant"] = grant_view(row["appId"], state)
        return rows


def systemctl_result(*args: str, timeout: int = 20) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [SYSTEMCTL, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )


def unit_load_state(unit: str) -> str:
    try:
        result = systemctl_result("show", unit, "--property=LoadState", "--value", timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def unit_exists(unit: str) -> bool:
    return unit_load_state(unit) == "loaded"


def unit_active(unit: str) -> bool:
    try:
        return systemctl_result("is-active", "--quiet", unit, timeout=5).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def configured_web_port() -> tuple[str, int]:
    value = load_json(WEB_CONTROLLER_PORT_CONFIG, {})
    if isinstance(value, dict) and str(value.get("mode") or "").lower() == "custom":
        try:
            port = int(value.get("port") or 0)
        except (TypeError, ValueError):
            port = 0
        if 1 <= port <= 65535:
            return "custom", port
    return "system-default", SYSTEM_DEFAULT_WEB_PORT


def firewall_private_tcp_ports() -> list[int]:
    try:
        text = FIREWALL_FACTORY_POLICY.read_text(encoding="utf-8")
    except OSError:
        return [SYSTEM_DEFAULT_WEB_PORT]
    found: set[int] = set()
    for line in text.splitlines():
        lowered = line.lower()
        if "tcp dport" not in lowered or ("ip saddr" not in lowered and "ip6 saddr" not in lowered):
            continue
        after = lowered.split("tcp dport", 1)[1]
        for raw in re.findall(r"\b\d{1,5}\b", after.split("accept", 1)[0]):
            value = int(raw)
            if 1 <= value <= 65535:
                found.add(value)
    found.add(SYSTEM_DEFAULT_WEB_PORT)
    return sorted(found)


def proc_listeners() -> list[dict[str, Any]]:
    sockets: list[tuple[str, int, str]] = []
    for source, protocol in ((Path("/proc/net/tcp"), "tcp"), (Path("/proc/net/tcp6"), "tcp6")):
        try:
            lines = source.read_text(encoding="utf-8").splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            local = fields[1]
            address_hex, port_hex = local.rsplit(":", 1)
            # /proc represents IPv4 127.0.0.1 as 0100007F and IPv6 ::1 in
            # 32-bit little-endian words. Exclude loopback listeners here.
            if address_hex.upper() in {"0100007F", "00000000000000000000000001000000"}:
                continue
            try:
                port = int(port_hex, 16)
            except ValueError:
                continue
            sockets.append((fields[9], port, protocol))
    if not sockets:
        return []
    wanted = {inode for inode, _port, _proto in sockets}
    owners: dict[str, tuple[int, str]] = {}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_root = proc / "fd"
        try:
            entries = list(fd_root.iterdir())
        except (OSError, PermissionError):
            continue
        matched = False
        for fd in entries:
            try:
                link = os.readlink(fd)
            except OSError:
                continue
            if link.startswith("socket:[") and link.endswith("]"):
                inode = link[8:-1]
                if inode in wanted:
                    try:
                        name = (proc / "comm").read_text(encoding="utf-8").strip()
                    except OSError:
                        name = "process"
                    owners[inode] = (int(proc.name), name)
                    matched = True
        if matched and len(owners) >= len(wanted):
            break
    rows = []
    for inode, port, protocol in sockets:
        pid, process = owners.get(inode, (0, "unknown"))
        rows.append({"port": port, "protocol": "tcp", "pid": pid, "process": process})
    return rows


def process_active_seconds(pid: int) -> int:
    if pid <= 0:
        return 0
    try:
        fields = (Path("/proc") / str(pid) / "stat").read_text(encoding="utf-8").split()
        start_ticks = int(fields[21])
        ticks = int(os.sysconf(os.sysconf_names["SC_CLK_TCK"]))
        uptime = float(Path("/proc/uptime").read_text().split()[0])
        return max(0, int(uptime - (start_ticks / ticks)))
    except (OSError, ValueError, IndexError, KeyError):
        return 0


def web_controller_active_seconds() -> int:
    starts = []
    try:
        uptime = float(Path("/proc/uptime").read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return 0
    for unit in WEB_CONTROLLER_REQUIRED:
        if not unit_active(unit):
            continue
        try:
            result = systemctl_result("show", unit, "--property=ActiveEnterTimestampMonotonic", "--value", timeout=5)
            micros = int(result.stdout.strip() or "0")
        except (OSError, ValueError, subprocess.TimeoutExpired):
            continue
        if micros > 0:
            starts.append(micros / 1_000_000.0)
    return max(0, int(uptime - min(starts))) if starts else 0


def friendly_service_name(process: str, ports: list[int]) -> str:
    p = process.lower()
    if "jellyfin" in p or 8096 in ports:
        return "Jellyfin Service"
    if "qbittorrent" in p or 8080 in ports or 6881 in ports:
        return "qBittorrent Service"
    if "sshd" in p or 22 in ports:
        return "SSH Service"
    if "smbd" in p or 139 in ports or 445 in ports:
        return "Samba Service"
    if "freeradius" in p or 1812 in ports or 1813 in ports:
        return "RADIUS Service"
    if 8787 in ports:
        return "Media Optimizer Service"
    return f"{process or 'System'} Service"


def system_service_inventory() -> list[dict[str, Any]]:
    web = web_controller_status()
    mode, port = configured_web_port()
    rows: list[dict[str, Any]] = [{
        "id": "web-controller",
        "name": "Web Controller Service",
        "online": bool(web.get("active")),
        "enabled": bool(web.get("enabled")),
        "activeSeconds": web_controller_active_seconds() if web.get("active") else 0,
        "ports": [port],
        "port": port,
        "portMode": mode,
        "portWritable": True,
        "allowedPorts": firewall_private_tcp_ports(),
        "source": "Neutron Remote Systems",
        "detail": str(web.get("mode") or "offline").upper(),
    }]
    listeners = proc_listeners()
    grouped: dict[tuple[int, str], dict[str, Any]] = {}
    for item in listeners:
        port_value = int(item.get("port") or 0)
        if port_value == port and str(item.get("process") or "") in {"python3", "python"}:
            # The edge itself is represented by Web Controller Service above.
            continue
        pid = int(item.get("pid") or 0)
        process = str(item.get("process") or "unknown")
        key = (pid, process)
        row = grouped.setdefault(key, {"pid": pid, "process": process, "ports": []})
        if port_value and port_value not in row["ports"]:
            row["ports"].append(port_value)
    seen_signatures = set()
    for row in sorted(grouped.values(), key=lambda v: (min(v["ports"]) if v["ports"] else 65536, v["process"])):
        ports = sorted(set(int(v) for v in row["ports"]))
        if not ports:
            continue
        name = friendly_service_name(str(row["process"]), ports)
        signature = (name, tuple(ports))
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        rows.append({
            "id": f"listener-{row['pid']}-{ports[0]}",
            "name": name,
            "online": True,
            "enabled": True,
            "activeSeconds": process_active_seconds(int(row["pid"])),
            "ports": ports,
            "port": ports[0],
            "portMode": "system-default",
            "portWritable": False,
            "source": str(row["process"]),
            "detail": "External listener" if len(ports) == 1 else f"{len(ports)} external ports",
        })
    return rows


def port_in_use_externally(port: int, current_web_port: int) -> bool:
    if port == current_web_port:
        return False
    return any(int(row.get("port") or 0) == port for row in proc_listeners())


def set_web_controller_port(port: int | None, system_default: bool = False) -> dict[str, Any]:
    mode, current = configured_web_port()
    target = SYSTEM_DEFAULT_WEB_PORT if system_default else int(port or 0)
    if target < 1 or target > 65535:
        raise RuntimeError("web controller port must be between 1 and 65535")
    allowed = firewall_private_tcp_ports()
    if target not in allowed:
        raise RuntimeError("selected port is not permitted by the current NeutronOS private-service firewall policy")
    if port_in_use_externally(target, current):
        raise RuntimeError("selected port is already used by another external service")
    if system_default or target == SYSTEM_DEFAULT_WEB_PORT:
        try:
            WEB_CONTROLLER_PORT_CONFIG.unlink()
        except FileNotFoundError:
            pass
    else:
        atomic_json(WEB_CONTROLLER_PORT_CONFIG, {"schema": 1, "mode": "custom", "port": target}, 0o640)
    if unit_exists("neutronos-remote-edge.service") and unit_active("neutronos-remote-edge.service"):
        result = systemctl_result("restart", "neutronos-remote-edge.service", timeout=20)
        if result.returncode != 0:
            raise RuntimeError("failed to restart Web Controller edge after port change")
    with _lock:
        state = load_state()
        audit(state, "web-controller-port-changed", port=target, mode="system-default" if system_default or target == SYSTEM_DEFAULT_WEB_PORT else "custom")
        save_state(state)
    return web_controller_status()


def web_controller_status() -> dict[str, Any]:
    present = [unit for unit in WEB_CONTROLLER_UNITS if unit_exists(unit)]
    required_present = [unit for unit in present if unit in WEB_CONTROLLER_REQUIRED]
    active = [unit for unit in present if unit_active(unit)]
    missing_required = sorted(WEB_CONTROLLER_REQUIRED.difference(present))
    mode = "offline"
    listeners: list[dict[str, Any]] = []
    edge = load_json(REMOTE_EDGE_STATUS, {})
    if isinstance(edge, dict):
        mode = str(edge.get("mode") or mode)
        raw_listeners = edge.get("listeners")
        if isinstance(raw_listeners, list):
            listeners = [row for row in raw_listeners if isinstance(row, dict)]
    desired_enabled = WEB_CONTROLLER_FLAG.exists()
    running = bool(required_present) and all(unit in active for unit in required_present)
    port_mode, configured_port = configured_web_port()
    return {
        "available": not missing_required,
        "enabled": desired_enabled,
        "active": running,
        "url": WEB_CONTROLLER_URL,
        "mode": mode,
        "listeners": listeners,
        "port": configured_port,
        "portMode": port_mode,
        "allowedPorts": firewall_private_tcp_ports(),
        "activeSeconds": web_controller_active_seconds() if running else 0,
        "presentUnits": present,
        "activeUnits": active,
        "policyFlag": str(WEB_CONTROLLER_FLAG),
        "missingRequiredUnits": missing_required,
    }


def set_web_controller(enabled: bool) -> dict[str, Any]:
    present = [unit for unit in WEB_CONTROLLER_UNITS if unit_exists(unit)]
    missing_required = sorted(WEB_CONTROLLER_REQUIRED.difference(present))
    if missing_required:
        raise RuntimeError("web controller runtime is incomplete: " + ", ".join(missing_required))
    WEB_CONTROLLER_FLAG.parent.mkdir(parents=True, exist_ok=True)
    if enabled:
        fd, temporary = tempfile.mkstemp(prefix=".web-controller.", dir=str(WEB_CONTROLLER_FLAG.parent))
        try:
            os.fchmod(fd, 0o640)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write("enabled\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, WEB_CONTROLLER_FLAG)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
    else:
        try:
            WEB_CONTROLLER_FLAG.unlink()
        except FileNotFoundError:
            pass

    ordered = present if enabled else list(reversed(present))
    failures: list[str] = []
    for unit in ordered:
        action = ["reset-failed", unit] if enabled else None
        if action:
            try:
                systemctl_result(*action, timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                pass
        command = ["start", unit] if enabled else ["stop", unit]
        try:
            result = systemctl_result(*command)
        except (OSError, subprocess.TimeoutExpired) as exc:
            failures.append(f"{unit}: {exc}")
            continue
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip().replace("\n", " ")
            failures.append(f"{unit}: {detail or 'systemctl failed'}")
    status = web_controller_status()
    status["requestedEnabled"] = enabled
    status["failures"] = failures
    if enabled and not status.get("active"):
        raise RuntimeError("web controller did not become fully active" + (": " + "; ".join(failures) if failures else ""))
    if not enabled and any(unit_active(unit) for unit in present):
        raise RuntimeError("web controller did not stop completely" + (": " + "; ".join(failures) if failures else ""))
    with _lock:
        state = load_state()
        audit(state, "web-controller-enabled" if enabled else "web-controller-disabled", url=WEB_CONTROLLER_URL)
        save_state(state)
    return status


def lease_payload(app_id: str, capability_id: str, app_remote_enabled: bool) -> dict[str, Any]:
    with _lock:
        state = load_state()
        if prune_expired(state):
            save_state(state)
        grant = grant_view(app_id, state)
        if not app_remote_enabled:
            return {"ok": True, "active": False, "reason": "app-remote-disabled", "grant": grant}
        if not grant["active"]:
            return {"ok": True, "active": False, "reason": "remote-systems-grant-inactive", "grant": grant}
        lease_id = secrets.token_urlsafe(18)
        audit(state, "lease-issued", appId=app_id, capabilityId=capability_id, leaseId=lease_id,
              expiresAt=grant["expiresAt"])
        save_state(state)
        return {
            "ok": True,
            "active": True,
            "leaseId": lease_id,
            "appId": app_id,
            "capabilityId": capability_id,
            "durationCode": grant["durationCode"],
            "expiresAt": grant["expiresAt"],
            "recheckWithinSeconds": 30,
        }


def handle_request(conn: socket.socket, request: dict[str, Any], role: str) -> dict[str, Any]:
    pid, uid, gid = peer_credentials(conn)
    op = str(request.get("op") or "").strip().lower()
    if op in {"hello", "discover", "grant", "revoke", "status", "audit", "web-controller-status", "web-controller-set", "web-controller-port-set", "system-services"}:
        if role != "admin" or not verify_admin_peer(pid, uid):
            return {"ok": False, "error": "unauthorized gatekeeper client"}
        if op == "hello":
            return {"ok": True, "broker": BROKER_NAME, "protocolVersion": PROTOCOL_VERSION,
                    "pid": os.getpid()}
        if op == "discover":
            return {"ok": True, "broker": BROKER_NAME, "protocolVersion": PROTOCOL_VERSION,
                    "providers": discover_payload()}
        if op == "web-controller-status":
            return {"ok": True, "webController": web_controller_status()}
        if op == "system-services":
            return {"ok": True, "services": system_service_inventory()}
        if op == "web-controller-port-set":
            try:
                use_default = bool(request.get("systemDefault", False))
                requested_port = None if use_default else int(request.get("port") or 0)
                status = set_web_controller_port(requested_port, use_default)
            except (RuntimeError, ValueError, TypeError) as exc:
                return {"ok": False, "error": str(exc), "webController": web_controller_status()}
            return {"ok": True, "webController": status, "services": system_service_inventory()}
        if op == "web-controller-set":
            requested = request.get("enabled")
            if not isinstance(requested, bool):
                return {"ok": False, "error": "web controller enabled value must be boolean"}
            try:
                status = set_web_controller(requested)
            except RuntimeError as exc:
                return {"ok": False, "error": str(exc), "webController": web_controller_status()}
            return {"ok": True, "webController": status}
        app_id = str(request.get("appId") or "").strip().lower()
        if op == "grant":
            try:
                grant = set_grant(app_id, str(request.get("durationCode") or ""))
            except ValueError as exc:
                return {"ok": False, "error": str(exc)}
            return {"ok": True, "appId": app_id, "grant": grant}
        if op == "revoke":
            return {"ok": True, "appId": app_id,
                    "grant": revoke_grant(app_id, str(request.get("reason") or "manual"))}
        if op == "status":
            return {"ok": True, "appId": app_id, "grant": grant_view(app_id)}
        if op == "audit":
            state = load_state()
            rows = state.get("audit", [])
            limit = max(1, min(500, int(request.get("limit") or 100)))
            return {"ok": True, "audit": rows[-limit:] if isinstance(rows, list) else []}

    if op == "lease":
        app_id = str(request.get("appId") or "").strip().lower()
        capability_id = str(request.get("capabilityId") or "").strip().lower()
        if role != "provider" or not app_id or not capability_id or not verify_provider_peer(pid, uid, app_id, capability_id):
            return {"ok": False, "active": False, "error": "unauthorized remote provider"}
        return lease_payload(app_id, capability_id, bool(request.get("appRemoteEnabled", False)))

    return {"ok": False, "error": "unsupported broker operation"}


def read_message(conn: socket.socket) -> dict[str, Any]:
    data = bytearray()
    while len(data) <= MAX_MESSAGE:
        chunk = conn.recv(min(65536, MAX_MESSAGE + 1 - len(data)))
        if not chunk:
            break
        data.extend(chunk)
        if b"\n" in chunk:
            break
    if len(data) > MAX_MESSAGE:
        raise ValueError("broker request exceeded message limit")
    line = bytes(data).split(b"\n", 1)[0].strip()
    value = json.loads(line.decode("utf-8")) if line else {}
    if not isinstance(value, dict):
        raise ValueError("broker request must be a JSON object")
    return value


def serve_client(conn: socket.socket, role: str) -> None:
    with conn:
        try:
            request = read_message(conn)
            response = handle_request(conn, request, role)
        except Exception as exc:
            response = {"ok": False, "error": f"broker request failed: {exc}"}
        payload = json.dumps(response, separators=(",", ":"), sort_keys=True).encode("utf-8") + b"\n"
        try:
            conn.sendall(payload)
        except OSError:
            pass


def socket_gid() -> int:
    try:
        return grp.getgrnam(SOCKET_GROUP).gr_gid
    except KeyError as exc:
        raise RuntimeError(f"required socket group {SOCKET_GROUP!r} does not exist") from exc


def cleanup_sockets() -> None:
    for path in (ADMIN_SOCKET_PATH, PROVIDER_SOCKET_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def create_server(path: Path) -> socket.socket:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    os.chown(path, 0, socket_gid())
    os.chmod(path, 0o660)
    server.listen(32)
    server.settimeout(1.0)
    return server


def accept_loop(server: socket.socket, role: str) -> None:
    while not _stop.is_set():
        try:
            conn, _ = server.accept()
        except socket.timeout:
            continue
        except OSError:
            if _stop.is_set():
                return
            raise
        threading.Thread(target=serve_client, args=(conn, role), daemon=True).start()


def run_server() -> None:
    prepare_state_dirs()
    cleanup_sockets()
    admin_server = create_server(ADMIN_SOCKET_PATH)
    provider_server = create_server(PROVIDER_SOCKET_PATH)

    def stop_handler(signum: int, frame: Any) -> None:
        _stop.set()
        for server in (admin_server, provider_server):
            try:
                server.close()
            except OSError:
                pass

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)
    threads = [
        threading.Thread(target=accept_loop, args=(admin_server, "admin"), daemon=True),
        threading.Thread(target=accept_loop, args=(provider_server, "provider"), daemon=True),
    ]
    for thread in threads:
        thread.start()
    try:
        while not _stop.wait(1.0):
            with _lock:
                state = load_state()
                if prune_expired(state):
                    save_state(state)
    finally:
        for server in (admin_server, provider_server):
            try:
                server.close()
            except OSError:
                pass
        cleanup_sockets()


def self_check() -> int:
    prepare_state_dirs()
    registry = load_registry()
    state = load_state()
    print(json.dumps({
        "ok": True,
        "broker": BROKER_NAME,
        "protocolVersion": PROTOCOL_VERSION,
        "registryReadable": isinstance(registry.get("packages"), dict),
        "providerCount": len(provider_apps()),
        "grantCount": len(state.get("grants", {})),
        "adminSocketPath": str(ADMIN_SOCKET_PATH),
        "providerSocketPath": str(PROVIDER_SOCKET_PATH),
        "statePath": str(BROKER_STATE_PATH),
        "webController": web_controller_status(),
    }, sort_keys=True))
    return 0

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return self_check()
    run_server()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
