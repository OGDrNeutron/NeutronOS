#!/usr/bin/env python3
"""NeutronOS offline Wi-Fi/LAN network controller for Roku + Jellyfin.

The daemon owns only the two NeutronOS-created NetworkManager profiles and its
own dnsmasq child processes. It does not restart NetworkManager, tailscaled, or
modify routes belonging to normal infrastructure connections.
"""
from __future__ import annotations

import argparse
import copy
import fcntl
import grp
import ipaddress
import json
import os
import pwd
import re
import selectors
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

installed_library = Path("/usr/local/lib/neutronos")
if installed_library.is_dir():
    sys.path.insert(0, str(installed_library))

from neutronos_ipc import IpcServer, PeerCredentials, ProtocolError, RequestContext
from neutronos_ipc.authorization import AuthorizationError, AuthorizationPolicy
from neutronos_ipc.sessions import verify_active_session
from neutronos_firewall import FirewallActivator, FirewallPolicyError, generate as generate_firewall
from neutronos_ipc.protocol import PROTOCOL_NAME, PROTOCOL_VERSION

CONFIG_PATH = Path(os.environ.get("NEUTRONOS_OFFLINE_NETWORK_CONFIG", "/etc/neutronos/offline-network.json"))
RUNTIME_DIR = Path(os.environ.get("NEUTRONOS_OFFLINE_NETWORK_RUNTIME", "/run/neutronos/offline-network"))
SOCKET_PATH = RUNTIME_DIR / "control.sock"
STATE_PATH = RUNTIME_DIR / "state.json"
LOCK_PATH = RUNTIME_DIR / "controller.lock"
AUTHORIZATION_PATH = Path(os.environ.get(
    "NEUTRONOS_OFFLINE_NETWORK_AUTHORIZATION",
    "/etc/neutronos/offline-network-authorization.json",
))
CREDENTIAL_PATH = Path(os.environ.get(
    "NEUTRONOS_OFFLINE_NETWORK_CREDENTIAL",
    "/var/lib/neutronos/network/hotspot.psk",
))

DEFAULT_CONFIG: dict[str, Any] = {
    "version": 3,
    "mode": "normal-wifi",
    "offline_roku_enabled": False,
    "auto_fallback_enabled": False,
    "check_interval_seconds": 30,
    "startup_grace_seconds": 20,
    "socket_group": "neutronos",
    "wifi": {
        "manual_enabled": False,
        "dnsmasq_enabled": True,
        "interface": "",
        "connection_name": "NeutronOS Local Hotspot",
        "ssid": "NeutronOS",
        "security": "wpa2",
        "max_connections": 8,
        "credential_path": str(CREDENTIAL_PATH),
        "address": "10.42.1.1/24",
        "gateway": "10.42.1.1",
        "dhcp_start": "10.42.1.20",
        "dhcp_end": "10.42.1.200",
        "lease_hours": 12,
    },
    "lan": {
        "manual_enabled": False,
        "dnsmasq_enabled": True,
        "interface": "",
        "connection_name": "NeutronOS LAN Hotspot",
        "address": "10.42.2.1/24",
        "gateway": "10.42.2.1",
        "dhcp_start": "10.42.2.20",
        "dhcp_end": "10.42.2.200",
        "lease_hours": 12,
        "max_connections": 8,
    },
    "dnsmasq": {
        "wildcard_dns_to_gateway": True,
        "domain": "neutronos.local",
    },
}

STOP = False
WAKE = False

NETWORK_MODES = {
    "normal-wifi", "ethernet", "wifi-hotspot", "lan-hotspot", "offline-roku",
}
LEGAL_TRANSITIONS = {
    "normal-wifi": NETWORK_MODES,
    "ethernet": {"ethernet", "normal-wifi", "lan-hotspot", "offline-roku"},
    "wifi-hotspot": {"wifi-hotspot", "normal-wifi"},
    "lan-hotspot": {"lan-hotspot", "normal-wifi", "ethernet"},
    "offline-roku": {"offline-roku", "normal-wifi"},
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log(message: str) -> None:
    print(f"[neutron-offline-network] {message}", flush=True)


def deep_merge(base: Any, override: Any) -> Any:
    if isinstance(base, dict) and isinstance(override, dict):
        result = copy.deepcopy(base)
        for key, value in override.items():
            result[key] = deep_merge(result[key], value) if key in result else copy.deepcopy(value)
        return result
    return copy.deepcopy(override)


def atomic_json(path: Path, data: dict[str, Any], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, mode)
    os.replace(temporary, path)


def load_config() -> dict[str, Any]:
    raw: dict[str, Any] = {}
    try:
        raw = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        pass
    except (OSError, json.JSONDecodeError) as exc:
        log(f"Ignoring invalid config: {exc}")
    config = deep_merge(DEFAULT_CONFIG, raw)
    # Legacy Patch 68 configurations had an implicit automatic fallback. Patch
    # 71 is explicit/default-off: migration observes existing manual state but
    # never silently starts a hotspot.
    mode = str(config.get("mode", "")).strip().lower()
    if mode not in NETWORK_MODES:
        if bool(config.get("offline_roku_enabled", False)):
            mode = "offline-roku"
        elif bool(config.get("wifi", {}).get("manual_enabled", False)):
            mode = "wifi-hotspot"
        elif bool(config.get("lan", {}).get("manual_enabled", False)):
            mode = "lan-hotspot"
        else:
            mode = "normal-wifi"
    config["version"] = 3
    config["mode"] = mode
    config["offline_roku_enabled"] = mode == "offline-roku"
    config["auto_fallback_enabled"] = False
    config["check_interval_seconds"] = max(15, min(900, int(config.get("check_interval_seconds", 30))))
    config["startup_grace_seconds"] = max(0, min(180, int(config.get("startup_grace_seconds", 20))))
    for kind in ("wifi", "lan"):
        config[kind]["manual_enabled"] = (
            mode in {"wifi-hotspot", "offline-roku"} if kind == "wifi"
            else mode in {"lan-hotspot", "offline-roku"}
        )
        config[kind]["dnsmasq_enabled"] = bool(config[kind].get("dnsmasq_enabled", True))
        try:
            limit = int(config[kind].get("max_connections", 8))
        except (TypeError, ValueError):
            limit = 8
        config[kind]["max_connections"] = max(1, min(64, limit))
    ssid = str(config["wifi"].get("ssid", "NeutronOS")).strip()
    if not ssid or len(ssid.encode("utf-8")) > 32:
        ssid = "NeutronOS"
    config["wifi"]["ssid"] = ssid
    security = str(config["wifi"].get("security", "wpa2")).strip().lower()
    config["wifi"]["security"] = security if security in {"wpa2", "wpa3"} else "wpa2"
    return config


def credential_path(config: dict[str, Any]) -> Path:
    configured = str(config.get("wifi", {}).get("credential_path", CREDENTIAL_PATH))
    path = Path(configured)
    if path != CREDENTIAL_PATH:
        raise ValueError("hotspot credential path is not permitted")
    return path


def read_wifi_password(config: dict[str, Any]) -> str:
    try:
        value = credential_path(config).read_text(encoding="utf-8").strip()
    except OSError:
        return ""
    return value if 8 <= len(value) <= 63 else ""


def save_wifi_password(config: dict[str, Any], password: str) -> None:
    if not 8 <= len(password) <= 63:
        raise ValueError("hotspot password must contain 8 to 63 characters")
    path = credential_path(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(password + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def save_config(config: dict[str, Any]) -> None:
    atomic_json(CONFIG_PATH, config, 0o600)


def dhcp_range_for_limit(config: dict[str, Any]) -> tuple[str, str]:
    """Return a bounded DHCP range honoring the configured client limit."""
    start_text = str(config.get("dhcp_start", "10.42.1.20"))
    address_text = str(config.get("address", "10.42.1.1/24"))
    try:
        start = ipaddress.ip_address(start_text)
        network = ipaddress.ip_interface(address_text).network
        last = network.broadcast_address - 1
        limit = max(1, min(64, int(config.get("max_connections", 8))))
        end = min(start + (limit - 1), last)
        return str(start), str(end)
    except (ValueError, TypeError):
        return start_text, str(config.get("dhcp_end", start_text))


def split_nmcli(line: str) -> list[str]:
    fields: list[str] = []
    buffer: list[str] = []
    escaped = False
    for character in line:
        if escaped:
            buffer.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            fields.append("".join(buffer))
            buffer = []
        else:
            buffer.append(character)
    if escaped:
        buffer.append("\\")
    fields.append("".join(buffer))
    return fields


@dataclass
class Result:
    code: int
    stdout: str
    stderr: str


class Nmcli:
    WIFI_TYPES = {"wifi", "802-11-wireless"}

    def run(self, arguments: Iterable[str], timeout: int = 30) -> Result:
        command = ["nmcli", *list(arguments)]
        try:
            completed = subprocess.run(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
                check=False,
                env={**os.environ, "LC_ALL": "C"},
            )
            return Result(completed.returncode, completed.stdout.strip(), completed.stderr.strip())
        except subprocess.TimeoutExpired as exc:
            return Result(124, exc.stdout or "", f"nmcli timed out after {timeout}s")
        except OSError as exc:
            return Result(127, "", str(exc))

    def devices(self) -> list[dict[str, str]]:
        result = self.run(["-t", "--escape", "yes", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"], 12)
        devices: list[dict[str, str]] = []
        if result.code != 0:
            return devices
        for line in result.stdout.splitlines():
            fields = split_nmcli(line)
            if len(fields) >= 4:
                devices.append({"device": fields[0], "type": fields[1].lower(), "state": fields[2].lower(), "connection": fields[3]})
        return devices

    def wifi_device(self, configured: str = "") -> str:
        if configured and any(item["device"] == configured and item["type"] in self.WIFI_TYPES for item in self.devices()):
            return configured
        for item in self.devices():
            if item["type"] in self.WIFI_TYPES and item["device"]:
                return item["device"]
        return ""

    def lan_device(self, configured: str = "") -> str:
        devices = self.devices()
        if configured and any(item["device"] == configured and item["type"] == "ethernet" for item in devices):
            return configured
        # Prefer an unplugged/disconnected wired interface so an active uplink is not silently taken over.
        for item in devices:
            if item["type"] == "ethernet" and item["state"] not in {"connected", "connecting"}:
                return item["device"]
        for item in devices:
            if item["type"] == "ethernet":
                return item["device"]
        return ""

    def wifi_radio_enabled(self) -> bool:
        result = self.run(["-t", "-f", "WIFI", "radio"], 8)
        return result.code == 0 and result.stdout.strip().lower() == "enabled"

    def set_wifi_radio(self, enabled: bool) -> bool:
        return self.run(["radio", "wifi", "on" if enabled else "off"], 12).code == 0

    def connection_exists(self, name: str) -> bool:
        result = self.run(["-t", "--escape", "yes", "-f", "NAME", "connection", "show"], 12)
        return result.code == 0 and name in [split_nmcli(line)[0] for line in result.stdout.splitlines() if line]

    def connection_mode(self, name: str) -> str:
        result = self.run(["-g", "802-11-wireless.mode", "connection", "show", "id", name], 10)
        return result.stdout.strip().lower() if result.code == 0 else ""

    def active_connection(self, device: str) -> str:
        for item in self.devices():
            if item["device"] == device and item["state"].startswith("connected"):
                return item["connection"]
        return ""

    def active_is_profile(self, device: str, profile: str) -> bool:
        return self.active_connection(device) == profile

    def active_infrastructure(self, device: str, hotspot_profile: str) -> tuple[bool, str]:
        active = self.active_connection(device)
        if not active:
            return False, ""
        if active == hotspot_profile or self.connection_mode(active) == "ap":
            return False, active
        return True, active

    def ensure_wifi_profile(self, config: dict[str, Any], device: str, *, shared: bool) -> Result:
        name = str(config["connection_name"])
        if not self.connection_exists(name):
            created = self.run(["connection", "add", "type", "wifi", "ifname", device, "con-name", name, "ssid", str(config["ssid"])], 25)
            if created.code != 0:
                return created
        password = read_wifi_password({"wifi": config})
        if not password:
            return Result(2, "", "A hotspot password must be configured first")
        security = str(config.get("security", "wpa2")).lower()
        start, end = dhcp_range_for_limit(config)
        arguments = [
            "connection", "modify", "id", name,
            "connection.interface-name", device,
            "connection.autoconnect", "no",
            "802-11-wireless.mode", "ap",
            "802-11-wireless.band", "bg",
            "802-11-wireless.ssid", str(config["ssid"]),
            "802-11-wireless-security.key-mgmt", "sae" if security == "wpa3" else "wpa-psk",
            "802-11-wireless-security.pmf", "3" if security == "wpa3" else "2",
            "802-11-wireless-security.psk", password,
            "ipv4.method", "shared" if shared else "manual",
            "ipv4.addresses", str(config["address"]),
            "ipv4.never-default", "yes",
            "ipv6.method", "disabled",
        ]
        if shared:
            arguments += ["ipv4.shared-dhcp-range", f"{start},{end}"]
        else:
            arguments += ["ipv4.gateway", "", "ipv4.dns", ""]
        return self.run(arguments, 25)

    def ensure_lan_profile(self, config: dict[str, Any], device: str, *, shared: bool) -> Result:
        name = str(config["connection_name"])
        if not self.connection_exists(name):
            created = self.run(["connection", "add", "type", "ethernet", "ifname", device, "con-name", name], 25)
            if created.code != 0:
                return created
        start, end = dhcp_range_for_limit(config)
        arguments = [
            "connection", "modify", "id", name,
            "connection.interface-name", device,
            "connection.autoconnect", "no",
            "ipv4.method", "shared" if shared else "manual",
            "ipv4.addresses", str(config["address"]),
            "ipv4.never-default", "yes",
            "ipv6.method", "disabled",
        ]
        if shared:
            arguments += ["ipv4.shared-dhcp-range", f"{start},{end}"]
        else:
            arguments += ["ipv4.gateway", "", "ipv4.dns", ""]
        return self.run(arguments, 25)

    def profile_up(self, name: str, device: str, timeout: int = 40) -> Result:
        return self.run(["connection", "up", "id", name, "ifname", device], timeout)

    def profile_down(self, name: str) -> Result:
        result = self.run(["connection", "down", "id", name], 25)
        text = (result.stdout + " " + result.stderr).lower()
        if result.code != 0 and ("not active" in text or "is not an active" in text or "unknown connection" in text):
            return Result(0, result.stdout, result.stderr)
        return result

    def known_wifi_profiles(self, hotspot: dict[str, Any]) -> list[dict[str, str]]:
        result = self.run(["-t", "--escape", "yes", "-f", "NAME,UUID,TYPE", "connection", "show"], 15)
        if result.code != 0:
            return []
        profiles: list[dict[str, str]] = []
        for line in result.stdout.splitlines():
            fields = split_nmcli(line)
            if len(fields) < 3 or fields[2].lower() not in self.WIFI_TYPES:
                continue
            name, uuid = fields[0], fields[1]
            if not name or not uuid or name == hotspot["connection_name"]:
                continue
            details = self.run(["-g", "802-11-wireless.ssid,802-11-wireless.mode", "connection", "show", "uuid", uuid], 10)
            if details.code != 0:
                continue
            values = details.stdout.splitlines()
            ssid = values[0].strip() if values else ""
            mode = values[1].strip().lower() if len(values) > 1 else ""
            if ssid and ssid != hotspot["ssid"] and mode != "ap":
                profiles.append({"name": name, "uuid": uuid, "ssid": ssid})
        return profiles

    def visible_networks(self, device: str) -> dict[str, int]:
        result = self.run(["-t", "--escape", "yes", "-f", "SSID,SIGNAL", "device", "wifi", "list", "ifname", device, "--rescan", "yes"], 30)
        if result.code != 0:
            return {}
        visible: dict[str, int] = {}
        for line in result.stdout.splitlines():
            fields = split_nmcli(line)
            if len(fields) < 2 or not fields[0]:
                continue
            try:
                strength = max(0, min(100, int(fields[1])))
            except ValueError:
                strength = 0
            visible[fields[0]] = max(visible.get(fields[0], 0), strength)
        return visible

    def best_known_visible(self, hotspot: dict[str, Any], device: str) -> dict[str, str] | None:
        visible = self.visible_networks(device)
        candidates = [dict(profile, signal=str(visible.get(profile["ssid"], -1))) for profile in self.known_wifi_profiles(hotspot) if profile["ssid"] in visible]
        return max(candidates, key=lambda item: int(item["signal"])) if candidates else None

    def connect_profile(self, profile: dict[str, str], device: str) -> Result:
        return self.run(["connection", "up", "uuid", profile["uuid"], "ifname", device], 45)


class DnsmasqManager:
    def __init__(self) -> None:
        self.processes: dict[str, subprocess.Popen[str]] = {}

    @staticmethod
    def binary() -> str:
        return shutil.which("dnsmasq") or "/usr/sbin/dnsmasq"

    def config_path(self, kind: str) -> Path:
        return RUNTIME_DIR / f"dnsmasq-{kind}.conf"

    def lease_path(self, kind: str) -> Path:
        return RUNTIME_DIR / f"dnsmasq-{kind}.leases"

    def running(self, kind: str) -> bool:
        process = self.processes.get(kind)
        return process is not None and process.poll() is None

    def stop(self, kind: str) -> None:
        process = self.processes.pop(kind, None)
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)

    def start(self, kind: str, interface: str, config: dict[str, Any], global_config: dict[str, Any]) -> tuple[bool, str]:
        if self.running(kind):
            return True, "dnsmasq is already running"
        binary = self.binary()
        if not Path(binary).exists():
            return False, "dnsmasq is not installed"
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        gateway = str(config["gateway"])
        lines = [
            "port=53",
            "domain-needed",
            "bogus-priv",
            "no-resolv",
            f"interface={interface}",
            "bind-dynamic",
            "except-interface=lo",
            "dhcp-authoritative",
            f"dhcp-range={dhcp_range_for_limit(config)[0]},{dhcp_range_for_limit(config)[1]},255.255.255.0,{int(config.get('lease_hours', 12))}h",
            f"dhcp-option=3,{gateway}",
            f"dhcp-option=6,{gateway}",
            f"dhcp-option=15,{global_config.get('domain', 'neutronos.local')}",
            f"dhcp-leasefile={self.lease_path(kind)}",
            f"pid-file={RUNTIME_DIR / ('dnsmasq-' + kind + '.pid')}",
            "log-dhcp",
        ]
        if bool(global_config.get("wildcard_dns_to_gateway", True)):
            lines.append(f"address=/#/{gateway}")
        else:
            lines.extend(["server=1.1.1.1", "server=8.8.8.8"])
        self.config_path(kind).write_text("\n".join(lines) + "\n", encoding="utf-8")
        validation = subprocess.run(
            [binary, "--test", f"--conf-file={self.config_path(kind)}"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=5, check=False, env={**os.environ, "LC_ALL": "C"})
        if validation.returncode != 0:
            return False, (validation.stderr or validation.stdout).strip() or "dnsmasq configuration validation failed"
        try:
            process = subprocess.Popen(
                [binary, "--keep-in-foreground", f"--conf-file={self.config_path(kind)}"],
                text=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                env={**os.environ, "LC_ALL": "C"},
            )
            time.sleep(0.35)
            if process.poll() is not None:
                error = (process.stderr.read() if process.stderr else "").strip()
                return False, error or f"dnsmasq exited {process.returncode}"
            self.processes[kind] = process
            return True, "dnsmasq started"
        except OSError as exc:
            return False, str(exc)

    def leases(self, kind: str) -> list[dict[str, str]]:
        path = self.lease_path(kind)
        leases: list[dict[str, str]] = []
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return leases
        now = int(time.time())
        for line in lines:
            parts = line.split()
            if len(parts) < 5:
                continue
            try:
                expires = int(parts[0])
            except ValueError:
                expires = 0
            leases.append({
                "ip": parts[2], "mac": parts[1].lower(), "name": "" if parts[3] == "*" else parts[3],
                "expires": datetime.fromtimestamp(expires, timezone.utc).isoformat(timespec="seconds") if expires else "",
                "leaseRemainingSeconds": max(0, expires - now) if expires else 0,
                "active": expires == 0 or expires > now,
            })
        return leases

    def close(self) -> None:
        for kind in list(self.processes):
            self.stop(kind)


class Controller:
    def __init__(self) -> None:
        self.nm = Nmcli()
        self.dnsmasq = DnsmasqManager()
        self.last_action = "starting"
        self.message = "Starting offline network controller"
        self.last_error = ""
        self.started_at = time.monotonic()

    def set_message(self, action: str, message: str, error: str = "") -> None:
        self.last_action = action
        self.message = message
        self.last_error = error
        log(message if not error else f"{message}: {error}")

    def wifi_active(self, config: dict[str, Any], device: str) -> bool:
        return bool(device and self.nm.active_is_profile(device, config["wifi"]["connection_name"]))

    def lan_active(self, config: dict[str, Any], device: str) -> bool:
        return bool(device and self.nm.active_is_profile(device, config["lan"]["connection_name"]))

    def ensure_wifi(self, config: dict[str, Any], device: str, *, shared: bool) -> tuple[bool, str]:
        if not device:
            return False, "No NetworkManager Wi-Fi interface is available"
        if not self.nm.wifi_radio_enabled() and not self.nm.set_wifi_radio(True):
            return False, "Unable to enable the Wi-Fi radio"
        profile = self.nm.ensure_wifi_profile(config["wifi"], device, shared=shared)
        if profile.code != 0:
            return False, profile.stderr or profile.stdout
        infrastructure, active = self.nm.active_infrastructure(device, config["wifi"]["connection_name"])
        if infrastructure and active:
            self.nm.profile_down(active)
        result = self.nm.profile_up(config["wifi"]["connection_name"], device)
        if result.code != 0:
            return False, result.stderr or result.stdout
        return True, "Wi-Fi hotspot is active"

    def ensure_lan(self, config: dict[str, Any], device: str, *, shared: bool) -> tuple[bool, str]:
        if not device:
            return False, "No NetworkManager Ethernet interface is available"
        profile = self.nm.ensure_lan_profile(config["lan"], device, shared=shared)
        if profile.code != 0:
            return False, profile.stderr or profile.stdout
        active = self.nm.active_connection(device)
        if active and active != config["lan"]["connection_name"]:
            # A manual LAN request is explicit; only then may the dedicated interface be reassigned.
            self.nm.profile_down(active)
        result = self.nm.profile_up(config["lan"]["connection_name"], device)
        if result.code != 0:
            return False, result.stderr or result.stdout
        return True, "LAN hotspot is active"

    def client_snapshot(self, kind: str, device: str) -> list[dict[str, Any]]:
        leases = [dict(item) for item in self.dnsmasq.leases(kind)]
        by_mac = {str(item.get("mac", "")).lower(): item for item in leases if item.get("mac")}
        if device:
            try:
                result = subprocess.run(["ip", "-j", "neigh", "show", "dev", device], text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        timeout=4, check=False)
            except (OSError, subprocess.TimeoutExpired):
                result = None
            if result is not None and result.returncode == 0:
                try:
                    neighbors = json.loads(result.stdout or "[]")
                except json.JSONDecodeError:
                    neighbors = []
                for neighbor in neighbors:
                    mac = str(neighbor.get("lladdr", "")).lower()
                    ip = str(neighbor.get("dst", ""))
                    if not mac or not ip:
                        continue
                    states = neighbor.get("state", [])
                    if isinstance(states, str):
                        states = [states]
                    neighbor_state = ",".join(str(value) for value in states) or "UNKNOWN"
                    item = by_mac.get(mac)
                    if item is None:
                        item = {"ip": ip, "mac": mac, "name": "", "expires": "",
                                "leaseRemainingSeconds": 0, "active": True}
                        leases.append(item)
                        by_mac[mac] = item
                    item["ip"] = ip or item.get("ip", "")
                    item["neighborState"] = neighbor_state
                    item["active"] = neighbor_state.upper() not in {"FAILED", "INCOMPLETE"}
        for item in leases:
            item["interface"] = device
            item["connectionType"] = "Wi-Fi" if kind == "wifi" else "Ethernet"
            item.setdefault("neighborState", "LEASED" if item.get("active", False) else "EXPIRED")
        leases.sort(key=lambda item: (not bool(item.get("active", False)), str(item.get("name", "")), str(item.get("ip", ""))))
        return leases

    def sync_dnsmasq(self, kind: str, enabled: bool, active: bool, device: str, config: dict[str, Any]) -> tuple[bool, str]:
        if not enabled or not active:
            self.dnsmasq.stop(kind)
            return True, "dnsmasq stopped" if not enabled else "Network is inactive"
        return self.dnsmasq.start(kind, device, config[kind], config["dnsmasq"])

    def reconcile(self, *, automatic: bool = True) -> bool:
        config = load_config()
        wifi_device = self.nm.wifi_device(str(config["wifi"].get("interface", "")))
        lan_device = self.nm.lan_device(str(config["lan"].get("interface", "")))
        ok = True

        # Manual Wi-Fi is authoritative and never scans or switches away.
        if config["wifi"]["manual_enabled"]:
            wifi_shared = config["mode"] == "wifi-hotspot"
            wifi_ok, detail = self.ensure_wifi(config, wifi_device, shared=wifi_shared)
            ok = ok and wifi_ok
            if not wifi_ok:
                self.set_message("wifi-manual-error", "Unable to enable manual Wi-Fi hotspot", detail)
            if wifi_shared:
                self.dnsmasq.stop("wifi")
            else:
                dns_ok, dns_detail = self.sync_dnsmasq("wifi", config["wifi"]["dnsmasq_enabled"], wifi_ok, wifi_device, config)
                ok = ok and dns_ok
                if not dns_ok:
                    self.set_message("wifi-dnsmasq-error", "Wi-Fi hotspot is active but dnsmasq failed", dns_detail)
        else:
            if self.wifi_active(config, wifi_device):
                self.dnsmasq.stop("wifi")
                self.nm.profile_down(config["wifi"]["connection_name"])

        # LAN is always manual and independent of normal Wi-Fi/Tailscale.
        lan_active = self.lan_active(config, lan_device)
        if config["lan"]["manual_enabled"]:
            if not lan_active:
                lan_shared = config["mode"] == "lan-hotspot"
                lan_ok, detail = self.ensure_lan(config, lan_device, shared=lan_shared)
                lan_active = lan_ok
                ok = ok and lan_ok
                if not lan_ok:
                    self.set_message("lan-error", "Unable to enable LAN hotspot", detail)
            lan_shared = config["mode"] == "lan-hotspot"
            if lan_shared:
                self.dnsmasq.stop("lan")
            else:
                dns_ok, dns_detail = self.sync_dnsmasq("lan", config["lan"]["dnsmasq_enabled"], lan_active, lan_device, config)
                ok = ok and dns_ok
                if not dns_ok:
                    self.set_message("lan-dnsmasq-error", "LAN hotspot is active but dnsmasq failed", dns_detail)
        else:
            self.dnsmasq.stop("lan")
            if lan_active:
                self.nm.profile_down(config["lan"]["connection_name"])

        self.write_state(config)
        return ok

    def write_state(self, config: dict[str, Any]) -> dict[str, Any]:
        state = self.status(config)
        atomic_json(STATE_PATH, state, 0o644)
        return state

    def status(self, config: dict[str, Any] | None = None) -> dict[str, Any]:
        config = config or load_config()
        wifi_device = self.nm.wifi_device(str(config["wifi"].get("interface", "")))
        lan_device = self.nm.lan_device(str(config["lan"].get("interface", "")))
        wifi_active = self.wifi_active(config, wifi_device)
        lan_active = self.lan_active(config, lan_device)
        infrastructure, infrastructure_name = self.nm.active_infrastructure(wifi_device, config["wifi"]["connection_name"]) if wifi_device else (False, "")
        return {
            "success": True,
            "version": 3,
            "mode": config["mode"],
            "offlineRokuEnabled": config["offline_roku_enabled"],
            "passwordConfigured": bool(read_wifi_password(config)),
            "wildcardDnsEnabled": bool(config["dnsmasq"].get("wildcard_dns_to_gateway", False)),
            "checkedAt": utc_now(),
            "autoFallbackEnabled": config["auto_fallback_enabled"],
            "lastAction": self.last_action,
            "message": self.message,
            "lastError": self.last_error,
            "normalWifiConnected": infrastructure,
            "normalWifiConnection": infrastructure_name,
            "wifi": {
                "enabled": config["wifi"]["manual_enabled"],
                "active": wifi_active,
                "dnsmasqEnabled": config["wifi"]["dnsmasq_enabled"],
                "dnsmasqRunning": self.dnsmasq.running("wifi"),
                "interface": wifi_device,
                "connectionName": config["wifi"]["connection_name"],
                "ssid": config["wifi"]["ssid"],
                "security": config["wifi"].get("security", "wpa2"),
                "maxConnections": config["wifi"].get("max_connections", 8),
                "gateway": config["wifi"]["gateway"],
                "address": config["wifi"]["address"],
                "leases": self.client_snapshot("wifi", wifi_device),
            },
            "lan": {
                "enabled": config["lan"]["manual_enabled"],
                "active": lan_active,
                "dnsmasqEnabled": config["lan"]["dnsmasq_enabled"],
                "dnsmasqRunning": self.dnsmasq.running("lan"),
                "interface": lan_device,
                "connectionName": config["lan"]["connection_name"],
                "maxConnections": config["lan"].get("max_connections", 8),
                "gateway": config["lan"]["gateway"],
                "address": config["lan"]["address"],
                "leases": self.client_snapshot("lan", lan_device),
            },
        }

    def apply(self, action: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
        config = load_config()
        previous = copy.deepcopy(config)
        arguments = arguments or {}
        reconfigure_target = ""
        mapping = {
            "wifi-enable": ("wifi", "manual_enabled", True),
            "wifi-disable": ("wifi", "manual_enabled", False),
            "wifi-dnsmasq-enable": ("wifi", "dnsmasq_enabled", True),
            "wifi-dnsmasq-disable": ("wifi", "dnsmasq_enabled", False),
            "lan-enable": ("lan", "manual_enabled", True),
            "lan-disable": ("lan", "manual_enabled", False),
            "lan-dnsmasq-enable": ("lan", "dnsmasq_enabled", True),
            "lan-dnsmasq-disable": ("lan", "dnsmasq_enabled", False),
        }
        if action == "set-mode":
            mode = str(arguments.get("mode", ""))
            if mode not in NETWORK_MODES:
                return {"success": False, "error": "Unsupported network mode"}
            current_mode = str(config.get("mode", "normal-wifi"))
            if mode not in LEGAL_TRANSITIONS.get(current_mode, set()):
                return {"success": False, "error": f"Illegal transition: {current_mode} to {mode}"}
            if mode in {"wifi-hotspot", "offline-roku"} and not read_wifi_password(config):
                return {"success": False, "error": "A hotspot password must be configured first", "passwordRequired": True}
            config["mode"] = mode
            config["offline_roku_enabled"] = mode == "offline-roku"
            config["wifi"]["manual_enabled"] = mode in {"wifi-hotspot", "offline-roku"}
            config["lan"]["manual_enabled"] = mode in {"lan-hotspot", "offline-roku"}
        elif action == "configure-hotspot":
            target = str(arguments.get("target", "")).strip().lower()
            if target not in {"wifi", "lan"}:
                return {"success": False, "error": "Hotspot target must be wifi or lan"}
            try:
                limit = int(arguments.get("maxConnections", config[target].get("max_connections", 8)))
            except (TypeError, ValueError):
                return {"success": False, "error": "Maximum connections must be a number"}
            if limit < 1 or limit > 64:
                return {"success": False, "error": "Maximum connections must be between 1 and 64"}
            config[target]["max_connections"] = limit
            if target == "wifi":
                ssid = str(arguments.get("ssid", config["wifi"].get("ssid", "NeutronOS"))).strip()
                if not ssid or len(ssid.encode("utf-8")) > 32:
                    return {"success": False, "error": "SSID must contain 1 to 32 UTF-8 bytes"}
                security = str(arguments.get("security", config["wifi"].get("security", "wpa2"))).strip().lower()
                if security not in {"wpa2", "wpa3"}:
                    return {"success": False, "error": "Security must be wpa2 or wpa3"}
                config["wifi"]["ssid"] = ssid
                config["wifi"]["security"] = security
            if "enable" in arguments:
                enable = bool(arguments.get("enable", False))
                if enable and target == "wifi" and not read_wifi_password(config):
                    return {"success": False, "error": "A hotspot password must be configured first", "passwordRequired": True}
                desired_mode = ("wifi-hotspot" if target == "wifi" else "lan-hotspot") if enable else "normal-wifi"
                current_mode = str(config.get("mode", "normal-wifi"))
                if desired_mode not in LEGAL_TRANSITIONS.get(current_mode, set()):
                    return {"success": False, "error": f"Illegal transition: {current_mode} to {desired_mode}"}
                config["mode"] = desired_mode
                config["offline_roku_enabled"] = False
                config["wifi"]["manual_enabled"] = desired_mode == "wifi-hotspot"
                config["lan"]["manual_enabled"] = desired_mode == "lan-hotspot"
            reconfigure_target = target
        elif action == "set-credential":
            password = str(arguments.get("password", ""))
            confirmation = str(arguments.get("confirmation", ""))
            if password != confirmation:
                return {"success": False, "error": "Hotspot passwords do not match"}
            save_wifi_password(config, password)
        elif action == "set-dns":
            target = str(arguments.get("target", ""))
            if target not in {"wifi", "lan"}:
                return {"success": False, "error": "DNS target must be wifi or lan"}
            config[target]["dnsmasq_enabled"] = bool(arguments.get("enabled", False))
            config["dnsmasq"]["wildcard_dns_to_gateway"] = bool(arguments.get("wildcard", False))
        elif action in {"auto-enable", "auto-disable"}:
            return {"success": False, "error": "Automatic hotspot fallback is disabled by Patch 71 policy"}
        elif action in mapping:
            section, key, value = mapping[action]
            config[section][key] = value
            if key == "manual_enabled":
                if section == "wifi":
                    config["mode"] = "wifi-hotspot" if value else "normal-wifi"
                else:
                    config["mode"] = "lan-hotspot" if value else "normal-wifi"
        elif action == "refresh":
            pass
        elif action == "status":
            return self.status(config)
        else:
            return {"success": False, "error": f"Unsupported action: {action}"}
        if reconfigure_target and config[reconfigure_target].get("manual_enabled", False):
            if reconfigure_target == "wifi":
                device = self.nm.wifi_device(str(config["wifi"].get("interface", "")))
            else:
                device = self.nm.lan_device(str(config["lan"].get("interface", "")))
            if device and self.nm.active_is_profile(device, config[reconfigure_target]["connection_name"]):
                self.nm.profile_down(config[reconfigure_target]["connection_name"])
        save_config(config)
        result = self.reconcile(automatic=False)
        if not result:
            save_config(previous)
            self.reconcile(automatic=False)
            state = self.status(load_config())
            state.update({"success": False, "rolledBack": True,
                          "lastError": state.get("lastError") or "Transition failed and previous network state was restored"})
            return state
        state = self.status(load_config())
        state["success"] = result
        if not result and not state.get("lastError"):
            state["lastError"] = "The requested network state could not be applied"
        return state

    def close(self) -> None:
        self.dnsmasq.close()


def socket_owner_group(config: dict[str, Any]) -> tuple[int, int]:
    uid = 0
    gid = 0
    try:
        group_name = str(config.get("socket_group", "neutronos"))
        gid = grp.getgrnam(group_name).gr_gid
    except KeyError:
        try:
            gid = pwd.getpwnam("neutronos").pw_gid
        except KeyError:
            gid = 0
    return uid, gid


def ipc_authenticate(peer: PeerCredentials, session: dict[str, str]) -> bool:
    return verify_active_session(peer, session)


def make_ipc_authorizer(policy: AuthorizationPolicy):
    def authorize(peer: PeerCredentials, session: dict[str, str],
                  application: dict[str, str], operation: str,
                  arguments: dict[str, Any]):
        try:
            return policy.authorize(peer, session, application, operation, arguments)
        except AuthorizationError as exc:
            raise ProtocolError(exc.code, exc.message) from exc
    return authorize


def append_audit(action: str, details: dict[str, Any]) -> None:
    safe = {key: value for key, value in details.items()
            if key not in {"arguments", "password", "confirmation"}}
    record = {"timestamp": utc_now(), "action": action, "details": safe}
    path = Path("/var/lib/neutronos/network/audit.jsonl")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n")
        os.chmod(path, 0o600)
    except OSError:
        pass


def make_ipc_handler(controller: Controller, policy: AuthorizationPolicy):
    def handle(operation: str, arguments: dict[str, Any],
               context: RequestContext) -> dict[str, Any]:
        if operation == "protocol.info":
            return {"protocol": PROTOCOL_NAME, "versions": [PROTOCOL_VERSION],
                    "service": "network", "operations": policy.enabled_operations(),
                    "identity": {"peerCredentialsVerified": True,
                                 "sessionVerified": True,
                                 "applicationIdentityStrength": context.application_identity_strength,
                                 "permission": context.permission,
                                 "principal": context.principal}}
        if operation in {"firewall.generate", "firewall.activate"}:
            try:
                rules = generate_firewall(arguments["policy"])
            except FirewallPolicyError as exc:
                raise ProtocolError("invalid_request", str(exc)) from exc
            if operation == "firewall.generate":
                append_audit("firewall_generation", {"success": True, "peerUid": context.peer.uid})
                return {"success": True, "ruleset": rules}
            result = FirewallActivator(Path("/var/lib/neutronos/network/firewall")).activate(rules)
            append_audit("firewall_activation", {"success": bool(result.get("success")),
                                                  "peerUid": context.peer.uid,
                                                  "knownGoodRetained": result.get("knownGoodRetained", False)})
            return result
        mapping = {"network.status": "status", "network.refresh": "refresh",
                   "network.set-mode": "set-mode", "network.set-dns": "set-dns",
                   "network.set-wifi-credential": "set-credential",
                   "network.configure-hotspot": "configure-hotspot"}
        action = mapping.get(operation)
        if action is None:
            raise ProtocolError("unknown_operation", "network operation is not supported")
        result = controller.apply(action, arguments)
        if operation != "network.status":
            append_audit("network_operation", {
                "operation": operation, "peerUid": context.peer.uid,
                "peerPid": context.peer.pid, "session": context.session.get("id", ""),
                "application": context.application.get("id", ""),
                "success": bool(result.get("success", False))})
        return result
    return handle


def serve() -> int:
    global STOP, WAKE
    if shutil.which("nmcli") is None:
        log("nmcli is required")
        return 2
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    try:
        shell_group = grp.getgrnam("neutronos-shell").gr_gid
        os.chown(RUNTIME_DIR.parent, 0, shell_group)
        os.chmod(RUNTIME_DIR.parent, 0o3770)
        runtime_info = RUNTIME_DIR.stat(follow_symlinks=False)
        if (not stat.S_ISDIR(runtime_info.st_mode) or runtime_info.st_uid != 0 or
                runtime_info.st_mode & 0o022):
            raise OSError("offline-network runtime directory is not root-owned and protected")
        os.chmod(RUNTIME_DIR, 0o755)
    except (KeyError, OSError) as exc:
        log(f"unsafe shared runtime ownership: {exc}")
        return 2
    lock = LOCK_PATH.open("w")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("Another offline network controller is already running")
        return 3

    try:
        policy = AuthorizationPolicy.load(AUTHORIZATION_PATH,
                                          require_root_owner=os.geteuid() == 0)
    except (OSError, AuthorizationError, ValueError) as exc:
        log(f"Authorization policy unavailable: {exc}")
        return 4
    controller = Controller()
    server = IpcServer(
        SOCKET_PATH, "network", make_ipc_handler(controller, policy),
        ipc_authenticate, make_ipc_authorizer(policy), append_audit,
        socket_group=str(load_config().get("socket_group", "neutronos-shell")),
        request_timeout=5.0)
    server.start()
    last_reconcile = 0.0
    grace_until = time.monotonic() + load_config()["startup_grace_seconds"]
    log(f"Authenticated control socket ready at {SOCKET_PATH}")

    try:
        while not STOP:
            now = time.monotonic()
            config = load_config()
            interval = config["check_interval_seconds"]
            if WAKE or (now >= grace_until and now - last_reconcile >= interval):
                WAKE = False
                controller.reconcile(automatic=False)
                last_reconcile = now
            server.serve_ready(timeout=1.0)
    finally:
        controller.close()
        server.close()
    return 0


def signal_stop(_signum: int, _frame: Any) -> None:
    global STOP
    STOP = True


def signal_wake(_signum: int, _frame: Any) -> None:
    global WAKE
    WAKE = True


def self_test() -> int:
    import tempfile

    merged = deep_merge(DEFAULT_CONFIG, {"wifi": {"manual_enabled": True}, "lan": {"dnsmasq_enabled": False}})
    assert merged["wifi"]["manual_enabled"] is True
    assert merged["wifi"]["dnsmasq_enabled"] is True
    assert merged["lan"]["dnsmasq_enabled"] is False
    assert split_nmcli(r"Home\:Network:wifi") == ["Home:Network", "wifi"]
    assert dhcp_range_for_limit({"dhcp_start": "10.42.1.20", "address": "10.42.1.1/24", "max_connections": 8}) == ("10.42.1.20", "10.42.1.27")
    for kind in ("wifi", "lan"):
        gateway = DEFAULT_CONFIG[kind]["gateway"]
        assert re.fullmatch(r"10\.42\.[12]\.1", gateway)

    class FakeNm:
        def __init__(self) -> None:
            self.active: dict[str, str] = {"wlan0": "", "eth0": ""}
        def wifi_device(self, configured: str = "") -> str: return "wlan0"
        def lan_device(self, configured: str = "") -> str: return "eth0"
        def active_is_profile(self, device: str, profile: str) -> bool: return self.active.get(device) == profile
        def active_infrastructure(self, device: str, hotspot: str) -> tuple[bool, str]:
            active = self.active.get(device, "")
            return (bool(active and active != hotspot), active)
        def wifi_radio_enabled(self) -> bool: return True
        def set_wifi_radio(self, enabled: bool) -> bool: return True
        def ensure_wifi_profile(self, config: dict[str, Any], device: str, *, shared: bool) -> Result: return Result(0, "", "")
        def ensure_lan_profile(self, config: dict[str, Any], device: str, *, shared: bool) -> Result: return Result(0, "", "")
        def active_connection(self, device: str) -> str: return self.active.get(device, "")
        def profile_down(self, name: str) -> Result:
            for device, active in list(self.active.items()):
                if active == name: self.active[device] = ""
            return Result(0, "", "")
        def profile_up(self, name: str, device: str, timeout: int = 40) -> Result:
            self.active[device] = name
            return Result(0, "", "")
        def best_known_visible(self, hotspot: dict[str, Any], device: str) -> dict[str, str] | None: return None
        def connect_profile(self, profile: dict[str, str], device: str) -> Result: return Result(0, "", "")

    class FakeDns:
        def __init__(self) -> None: self.active: set[str] = set()
        def running(self, kind: str) -> bool: return kind in self.active
        def stop(self, kind: str) -> None: self.active.discard(kind)
        def start(self, kind: str, interface: str, config: dict[str, Any], global_config: dict[str, Any]) -> tuple[bool, str]:
            self.active.add(kind); return True, "started"
        def leases(self, kind: str) -> list[dict[str, str]]: return []
        def close(self) -> None: self.active.clear()

    global CONFIG_PATH, STATE_PATH, RUNTIME_DIR, CREDENTIAL_PATH
    old_config, old_state, old_runtime, old_credential = CONFIG_PATH, STATE_PATH, RUNTIME_DIR, CREDENTIAL_PATH
    try:
        with tempfile.TemporaryDirectory(prefix="neutron-offline-selftest-") as temporary:
            base = Path(temporary)
            CONFIG_PATH = base / "offline-network.json"
            RUNTIME_DIR = base / "run"
            STATE_PATH = RUNTIME_DIR / "state.json"
            CREDENTIAL_PATH = base / "hotspot.psk"
            config = deep_merge(DEFAULT_CONFIG, {
                "mode": "normal-wifi", "auto_fallback_enabled": False,
                "wifi": {"credential_path": str(CREDENTIAL_PATH)}})
            save_config(config)
            save_wifi_password(config, "self-test-password")
            controller = Controller()
            controller.nm = FakeNm()  # type: ignore[assignment]
            controller.dnsmasq = FakeDns()  # type: ignore[assignment]
            response = controller.apply("wifi-enable")
            assert response["success"] is True and response["wifi"]["active"] is True
            assert response["wifi"]["dnsmasqRunning"] is True
            response = controller.apply("lan-enable")
            assert response["success"] is True and response["lan"]["active"] is True
            response = controller.apply("wifi-dnsmasq-disable")
            assert response["wifi"]["dnsmasqEnabled"] is False
            assert response["wifi"]["dnsmasqRunning"] is False
            response = controller.apply("lan-disable")
            assert response["lan"]["active"] is False
    finally:
        CONFIG_PATH, STATE_PATH, RUNTIME_DIR, CREDENTIAL_PATH = old_config, old_state, old_runtime, old_credential

    print("offline network controller self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not args.daemon:
        parser.error("choose --daemon or --self-test")
    signal.signal(signal.SIGTERM, signal_stop)
    signal.signal(signal.SIGINT, signal_stop)
    signal.signal(signal.SIGHUP, signal_wake)
    return serve()


if __name__ == "__main__":
    raise SystemExit(main())
