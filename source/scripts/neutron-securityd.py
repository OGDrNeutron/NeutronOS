#!/usr/bin/env python3
"""NeutronOS Security Core daemon with Patch 70 authenticated local IPC.

Repairs normal-use false alarms by correlating identical integrity states,
recognizing expected Tailscale UDP transport listeners, and updating stale
authentication guidance while preserving all earlier protections. Patch 70
adds a root-owned, peer-credentialled Unix socket; it does not add application
integrity or launch blocking.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import ctypes.util
import hashlib
import hmac
import ipaddress
import json
import os
import pwd
import grp
import re
import signal
import secrets
import stat
import shutil
import subprocess
import tempfile
import time
import threading
import uuid
from collections import deque
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any

from neutronos_ipc import IpcServer, PeerCredentials, RequestContext
from neutronos_ipc.authorization import AuthorizationError, AuthorizationPolicy
from neutronos_ipc.protocol import PROTOCOL_NAME, PROTOCOL_VERSION
from neutronos_ipc.protocol import ProtocolError
from neutronos_ipc.sessions import verify_active_session

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except Exception:
    AESGCM = None

RUNNING = True
AUTH_PATTERNS = [
    re.compile(r"failed password", re.I),
    re.compile(r"authentication failure", re.I),
    re.compile(r"invalid user", re.I),
    re.compile(r"pam_unix\([^)]*:auth\).*failure", re.I),
]
PRIVILEGE_PATTERNS = [
    re.compile(r"sudo:.*authentication failure", re.I),
    re.compile(r"user not in sudoers", re.I),
    re.compile(r"incorrect password attempt", re.I),
]

IP_PATTERN = re.compile(r"(?:from\s+|rhost=)([0-9A-Fa-f:.]+)", re.I)
PORT_PATTERN = re.compile(r"\bport\s+(\d+)\b", re.I)
SOCKET_PROCESS_PATTERN = re.compile(r'users:\(\("([^"]+)"')
SOCKET_PID_PATTERN = re.compile(r'pid=(\d+)')
INVALID_USER_PATTERN = re.compile(r"invalid user\s+([^\s]+)", re.I)
FAILED_USER_PATTERN = re.compile(r"failed password for (?:invalid user )?([^\s]+)", re.I)
PAM_USER_PATTERN = re.compile(r"\buser=([^\s]+)", re.I)
AUTH_SUPPORT_PATTERNS = [
    re.compile(r"connection closed by (?:invalid user )?.*\[preauth\]", re.I),
    re.compile(r"disconnected from (?:invalid user )?.*\[preauth\]", re.I),
]
AUTH_SESSION_WINDOW_SECONDS = 35
AUTH_INCIDENT_WINDOW_SECONDS = 600
FIREWALL_STATE_PATH = Path("/var/lib/neutronos/security-core/firewall-state.json")
FIREWALL_STALE_SECONDS = 30


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_time(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def atomic_json(path: Path, data: Any, mode: int = 0o640) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def run(command: list[str], timeout: int = 8) -> str:
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        return completed.stdout
    except Exception:
        return ""


def stable_fingerprint(*parts: str) -> str:
    joined = "\x1f".join(parts)
    return hashlib.sha256(joined.encode("utf-8", errors="replace")).hexdigest()


class SecurityCore:
    def __init__(self, state_dir: Path, project_root: Path, owner: str, group: str,
                 authorization_policy: AuthorizationPolicy,
                 legacy_json_requests: bool = False) -> None:
        self.state_dir = state_dir
        self.project_root = project_root
        self.owner = owner
        self.group = group
        self.legacy_json_requests = legacy_json_requests
        self.authorization_policy = authorization_policy
        self.requests_dir = state_dir / "requests"
        self.state_path = state_dir / "state.json"
        self.config_path = state_dir / "config.json"
        self.audit_path = state_dir / "audit.jsonl"
        self.fingerprints_path = state_dir / "fingerprints.json"
        self.events_path = state_dir / "events.json"
        self.bans_path = state_dir / "bans.json"
        self.malware_findings_path = state_dir / "malware-findings.json"
        self.quarantine_index_path = state_dir / "quarantine.json"
        self.quarantine_dir = state_dir / "quarantine"
        self.integrity_baseline_path = state_dir / "integrity-baseline.json"
        self.package_state_path = state_dir / "package-state.json"
        self.response_state_path = state_dir / "response-state.json"
        self.response_history_path = state_dir / "response-history.json"
        self.hardening_state_path = state_dir / "hardening-state.json"
        self.hardening_backup_dir = state_dir / "hardening-backup"
        self.containment_state_path = state_dir / "containment-state.json"
        self.recovery_path = state_dir / "recovery.json"
        self.recovery_signing_key_path = state_dir / "recovery-signing.key"
        self.responses_dir = state_dir / "responses"
        self.watchdog_event_path = state_dir / "watchdog-event.json"
        self.vault_path = state_dir / "credentials.vault"
        self.vault_combo_path = state_dir / "vault-combo.json"
        self.vault_master_key_path = state_dir / "vault-master.key"
        self.vault_factor_state_path = state_dir / "vault-factor-state.json"
        self.defaults_path = project_root / "config" / "security-core-defaults.json"
        self.config: dict[str, Any] = {}
        self.events: deque[dict[str, Any]] = deque(maxlen=500)
        self.fingerprints: dict[str, str] = {}
        self.audit_head = "0" * 64
        self.audit_valid = True
        self.listening_ports: list[dict[str, Any]] = []
        self.failed_services: list[dict[str, Any]] = []
        self.peripherals: list[dict[str, Any]] = []
        self.bans: dict[str, dict[str, Any]] = {}
        self.firewall_health: dict[str, Any] = {
            "protectionState": "CRITICAL",
            "firewallActive": False,
            "lifelineActive": False,
            "baseTableActive": False,
            "securityTableActive": False,
            "reason": "Firewall health has not been verified",
        }
        self.previous_firewall_protection_state = ""
        self.malware_findings: list[dict[str, Any]] = []
        self.quarantined_items: list[dict[str, Any]] = []
        self.integrity_baseline: dict[str, dict[str, Any]] = {}
        self.integrity_changes: list[dict[str, Any]] = []
        self.integrity_status = "Not initialized"
        self.last_integrity_scan = ""
        self.last_malware_scan = ""
        self.scan_lock = threading.Lock()
        self.scan_running = False
        self.scan_target = ""
        self.scan_started_at = ""
        self.scan_finished_at = ""
        self.scan_started_monotonic = 0.0
        self.scan_elapsed_seconds = 0
        self.scan_threats_found = 0
        self.scan_last_result = ""
        self.scan_result_until = 0.0
        self.scan_current_file = ""
        self.scan_files_checked = 0
        self.scan_pid = 0
        self.scan_cancel_requested = False
        try:
            self.scan_memory_limit_mib = max(768, min(1536, int(os.environ.get("NEUTRONOS_SCAN_MEMORY_MIB", "1280"))))
        except ValueError:
            self.scan_memory_limit_mib = 1280
        try:
            self.scan_min_available_mib = max(256, min(1024, int(os.environ.get("NEUTRONOS_SCAN_MIN_AVAILABLE_MIB", "420"))))
        except ValueError:
            self.scan_min_available_mib = 420
        self.antivirus_status = "Checking antivirus"
        self.antivirus_version = ""
        self.package_changes: list[dict[str, Any]] = []
        self.package_state: dict[str, Any] = {}
        self.previous_peripheral_ids: set[str] = set()
        self.previous_external_ports: set[str] = set()
        self.port_baseline_ready = False
        self.previous_integrity_signature = ""
        self.previous_integrity_count = 0
        self._previous_integrity_changes: list[dict[str, Any]] = []
        self.last_scan = ""
        self.auth_failures = 0
        self.privilege_failures = 0
        self.failed_service_units: set[str] = set()
        self.response_history: list[dict[str, Any]] = []
        self.response_state: dict[str, Any] = {
            "currentLevel": 5,
            "suggestedLevel": 5,
            "lastTransition": "",
            "reason": "Normal monitoring",
            "containmentActive": False,
            "automatic": False,
        }
        self.hardening_state: dict[str, Any] = {
            "activeProfile": "none",
            "appliedAt": "",
            "rollbackAvailable": False,
            "lastPreview": {},
            "lastResult": "Not applied",
        }
        self.recovery: dict[str, Any] = {
            "configured": False,
            "primaryMethod": "none",
            "createdAt": "",
            "keyId": "",
        }
        self.recovery_usb_candidates: list[dict[str, Any]] = []
        self.last_recovery_verification: dict[str, Any] = {
            "success": False, "timestamp": "", "message": "Not verified"
        }
        self.vault_key: bytes | None = None
        self.vault_entries: list[dict[str, Any]] = []
        self.vault_unlocked_until = 0.0
        self.vault_last_error = "Locked"
        self.ensure_layout()
        self.load()
        self.load_protection_state()
        self.audit_valid, self.audit_head = self.verify_audit()
        self.migrate_existing_authentication_events()
        self.migrate_expected_listener_events()
        self.append_audit("daemon_started", {
            "learningMode": self.config.get("learningMode", True),
            "enforcementEnabled": self.config.get("enforcementEnabled", False),
            "incidentCorrelation": True,
            "patch": "61E1",
            "malwareProtection": True,
            "fileIntegrity": True,
            "peripheralAuthorization": True,
            "defconResponseEngine": True,
            "hardeningProfiles": True,
            "physicalRecovery": True,
            "encryptedVault": True,
            "selfProtection": True,
        })
        for address, record in list(self.bans.items()):
            expiry = parse_time(str(record.get("expiresAt", "")))
            if expiry is not None and expiry > datetime.now(timezone.utc):
                applied, backend = self.firewall_add(address)
                record["active"] = applied
                record["firewallBackend"] = backend
        self.save_bans()

    def ensure_layout(self) -> None:
        os.umask(0o027)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.quarantine_dir.mkdir(parents=True, exist_ok=True)
        self.hardening_backup_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.state_dir, 0o750)
        os.chmod(self.quarantine_dir, 0o700)
        os.chmod(self.hardening_backup_dir, 0o700)
        if self.legacy_json_requests:
            self.requests_dir.mkdir(parents=True, exist_ok=True)
            self.responses_dir.mkdir(parents=True, exist_ok=True)
            os.chmod(self.requests_dir, 0o770)
            os.chmod(self.responses_dir, 0o770)
            try:
                uid = pwd.getpwnam(self.owner).pw_uid
                gid = grp.getgrnam(self.group).gr_gid
                os.chown(self.requests_dir, uid, gid)
                os.chown(self.responses_dir, uid, gid)
            except Exception:
                pass

    def load(self) -> None:
        defaults: dict[str, Any] = {
            "schema": 1,
            "learningMode": True,
            "threatLevel": 5,
            "maximumEvents": 500,
            "scanIntervalSeconds": 60,
            "notificationMinimumSeverity": 3,
            "acknowledged": [],
            "recovery": {"configured": False, "primaryMethod": "none"},
            "enforcementEnabled": False,
            "automaticBanThreshold": 5,
            "automaticBanWindowSeconds": 600,
            "banDurationsMinutes": [10, 60, 1440],
            "trustedSources": ["127.0.0.1", "::1"],
            "offenseCounts": {},
            "antivirusEnabled": True,
            "backgroundScanEnabled": False,
            "backgroundScanIntervalSeconds": 21600,
            "autoCreateIntegrityBaseline": True,
            "integrityMaxFiles": 12000,
            "trustedPeripherals": [],
            "blockedPeripherals": [],
            "allowOncePeripherals": [],
            "peripheralEnforcementEnabled": False,
            "responseEngineEnabled": False,
            "automaticDefconFloor": 3,
            "manualContainmentEnabled": True,
            "defconCooldownSeconds": 900,
            "activeHardeningProfile": "none",
            "hardeningRollbackAvailable": False,
            "hardeningProfiles": ["balanced", "strict", "fortified"],
            "recoveryFailedAttempts": 0,
            "recoveryLockUntil": "",
            "vaultUnlockSeconds": 300,
        }
        if self.defaults_path.exists():
            try:
                defaults.update(json.loads(self.defaults_path.read_text(encoding="utf-8")))
            except Exception:
                pass
        if self.config_path.exists():
            try:
                defaults.update(json.loads(self.config_path.read_text(encoding="utf-8")))
            except Exception:
                pass
        self.config = defaults
        self.events = deque(maxlen=max(100, int(self.config.get("maximumEvents", 500))))
        if self.events_path.exists():
            try:
                values = json.loads(self.events_path.read_text(encoding="utf-8"))
                for event in values[-self.events.maxlen :]:
                    if isinstance(event, dict):
                        self.events.append(event)
            except Exception:
                pass
        if self.bans_path.exists():
            try:
                value = json.loads(self.bans_path.read_text(encoding="utf-8"))
                if isinstance(value, dict):
                    self.bans = {str(k): dict(v) for k, v in value.items() if isinstance(v, dict)}
            except Exception:
                self.bans = {}
        if self.fingerprints_path.exists():
            try:
                value = json.loads(self.fingerprints_path.read_text(encoding="utf-8"))
                if isinstance(value, dict):
                    self.fingerprints = {str(k): str(v) for k, v in value.items()}
            except Exception:
                pass
        if self.state_path.exists():
            try:
                previous_state = json.loads(self.state_path.read_text(encoding="utf-8"))
                for port in previous_state.get("listeningPorts", []):
                    if isinstance(port, dict) and port.get("scope") == "external":
                        self.previous_external_ports.add(self.listener_identity(port))
                self.port_baseline_ready = bool(previous_state.get("listeningPorts"))
                prior_changes = previous_state.get("integrityChanges", [])
                if isinstance(prior_changes, list):
                    self.integrity_changes = [dict(item) for item in prior_changes if isinstance(item, dict)][:500]
                self.previous_integrity_signature = str(previous_state.get("integrityChangeSignature", ""))
                if not self.previous_integrity_signature and self.integrity_changes:
                    self.previous_integrity_signature = self.integrity_change_signature(self.integrity_changes)
                self.previous_integrity_count = len(self.integrity_changes)
                self._previous_integrity_changes = [dict(item) for item in self.integrity_changes]
                for service in previous_state.get("failedServices", []):
                    if isinstance(service, dict) and service.get("unit"):
                        self.failed_service_units.add(str(service["unit"]))
            except Exception:
                pass
        self.save_config()

    def load_protection_state(self) -> None:
        def load_list(file_path: Path) -> list[dict[str, Any]]:
            try:
                value = json.loads(file_path.read_text(encoding="utf-8"))
                if isinstance(value, list):
                    return [dict(item) for item in value if isinstance(item, dict)]
            except Exception:
                pass
            return []

        self.malware_findings = load_list(self.malware_findings_path)
        self.quarantined_items = load_list(self.quarantine_index_path)
        try:
            value = json.loads(self.integrity_baseline_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.integrity_baseline = {
                    str(name): dict(record) for name, record in value.items()
                    if isinstance(record, dict)
                }
        except Exception:
            self.integrity_baseline = {}
        try:
            value = json.loads(self.package_state_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.package_state = value
        except Exception:
            self.package_state = {}
        try:
            previous_state = json.loads(self.state_path.read_text(encoding="utf-8"))
            self.last_malware_scan = str(previous_state.get("lastMalwareScan", ""))
            self.last_integrity_scan = str(previous_state.get("lastIntegrityScan", ""))
            self.integrity_status = str(previous_state.get("integrityStatus", self.integrity_status))
            values = previous_state.get("packageChanges", [])
            if isinstance(values, list):
                self.package_changes = [dict(item) for item in values if isinstance(item, dict)][:100]
        except Exception:
            pass
        self.update_antivirus_status()
        self.load_response_and_hardening_state()
        self.load_recovery_state()

    def load_response_and_hardening_state(self) -> None:
        try:
            value = json.loads(self.response_state_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.response_state.update(value)
        except Exception:
            pass
        try:
            value = json.loads(self.response_history_path.read_text(encoding="utf-8"))
            if isinstance(value, list):
                self.response_history = [dict(item) for item in value if isinstance(item, dict)][:100]
        except Exception:
            self.response_history = []
        try:
            value = json.loads(self.hardening_state_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.hardening_state.update(value)
        except Exception:
            pass
        if self.containment_state_path.exists():
            try:
                containment = json.loads(self.containment_state_path.read_text(encoding="utf-8"))
                self.response_state["containmentActive"] = bool(containment.get("active", False))
            except Exception:
                pass

    def save_response_and_hardening_state(self) -> None:
        atomic_json(self.response_state_path, self.response_state, 0o640)
        atomic_json(self.response_history_path, self.response_history[:100], 0o640)
        atomic_json(self.hardening_state_path, self.hardening_state, 0o640)

    def save_protection_state(self) -> None:
        atomic_json(self.malware_findings_path, self.malware_findings, 0o640)
        atomic_json(self.quarantine_index_path, self.quarantined_items, 0o640)
        atomic_json(self.package_state_path, self.package_state, 0o640)

    def owner_home(self) -> Path:
        try:
            return Path(pwd.getpwnam(self.owner).pw_dir)
        except Exception:
            return Path("/home") / self.owner

    def antivirus_backend(self) -> str:
        return shutil.which("clamscan") or ""

    def update_antivirus_status(self) -> None:
        backend = self.antivirus_backend()
        if not backend:
            self.antivirus_status = "ClamAV is not installed"
            self.antivirus_version = ""
            return
        version = run([backend, "--version"], timeout=8).strip()
        self.antivirus_version = version.splitlines()[0] if version else "ClamAV available"
        self.antivirus_status = "Ready"

    def safe_scan_target(self, raw: str) -> Path | None:
        if not raw:
            return None
        try:
            target = Path(raw).expanduser().resolve(strict=True)
        except Exception:
            return None
        forbidden = (Path("/proc"), Path("/sys"), Path("/dev"), Path("/run"))
        if any(target == item or item in target.parents for item in forbidden):
            return None
        if not target.is_file() and not target.is_dir():
            return None
        return target

    def file_digest(self, path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def available_memory_mib() -> int:
        try:
            for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
                if line.startswith("MemAvailable:"):
                    return max(0, int(line.split()[1]) // 1024)
        except Exception:
            pass
        return 0

    def start_malware_scan(
        self,
        raw_target: str,
        label: str,
        request_id: str = "",
    ) -> tuple[bool, str]:
        """Start exactly one malware scan at a time."""
        available_mib = self.available_memory_mib()
        if available_mib and available_mib < self.scan_min_available_mib:
            return False, (
                f"Scan not started — only {available_mib} MiB memory is available; "
                f"{self.scan_min_available_mib} MiB is required for a safe scan"
            )
        with self.scan_lock:
            if self.scan_running:
                return False, "A malware scan is already running"

            self.scan_running = True
            self.scan_target = label
            self.scan_started_at = utc_now()
            self.scan_finished_at = ""
            self.scan_started_monotonic = time.monotonic()
            self.scan_elapsed_seconds = 0
            self.scan_threats_found = 0
            self.scan_last_result = ""
            self.scan_result_until = 0.0
            self.scan_current_file = ""
            self.scan_files_checked = 0
            self.scan_pid = 0
            self.scan_cancel_requested = False

        self.antivirus_status = f"Scanning {label}"
        self.write_state()

        threading.Thread(
            target=self._malware_scan_worker,
            args=(raw_target, request_id),
            name="neutron-security-malware-scan",
            daemon=True,
        ).start()

        return True, f"{label} scan started"

    def _signal_scan_process_group(self, pid: int, sig: int) -> bool:
        """Signal only the active scan process group, never the daemon itself."""
        if pid <= 0:
            return False

        try:
            os.killpg(pid, sig)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return False
        except Exception:
            try:
                os.kill(pid, sig)
                return True
            except Exception:
                return False

    def cancel_malware_scan(self, request_id: str = "") -> tuple[bool, str]:
        """Cancel the current asynchronous malware scan without restarting securityd."""
        with self.scan_lock:
            if not self.scan_running:
                return False, "No security scan is running"

            self.scan_cancel_requested = True
            pid = int(self.scan_pid or 0)
            target = self.scan_target
            self.antivirus_status = "Stopping security scan"

        self.write_state()
        self.append_audit(
            "malware_scan_cancel_requested",
            {
                "target": target,
                "requestId": request_id,
                "pid": pid,
            },
        )

        if pid > 0:
            self._signal_scan_process_group(pid, signal.SIGTERM)

            # Escalate only if the exact same scan process group is still alive.
            def force_stop() -> None:
                time.sleep(1.5)
                with self.scan_lock:
                    still_active = (
                        self.scan_running
                        and self.scan_cancel_requested
                        and int(self.scan_pid or 0) == pid
                    )
                if still_active:
                    self._signal_scan_process_group(pid, signal.SIGKILL)

            threading.Thread(
                target=force_stop,
                name="neutron-security-scan-cancel",
                daemon=True,
            ).start()

        return True, "Security scan cancellation requested"

    def _malware_scan_worker(self, raw_target: str, request_id: str) -> None:
        try:
            self.run_malware_scan(raw_target, request_id)
        except Exception as exc:
            self.antivirus_status = "Scan failed"
            self.append_audit(
                "malware_scan_worker_error",
                {"target": raw_target, "error": str(exc)},
            )
        finally:
            with self.scan_lock:
                self.scan_elapsed_seconds = max(
                    0,
                    int(time.monotonic() - self.scan_started_monotonic),
                )
                # scan_threats_found is maintained by the active scan and is
                # intentionally not replaced with the lifetime finding count.
                self.scan_running = False
                self.scan_pid = 0
                self.scan_finished_at = utc_now()
                self.scan_last_result = (
                    self.antivirus_status or "Scan completed"
                )
                self.scan_cancel_requested = False
                # Keep the completed result on the Security panel for 5 minutes.
                self.scan_result_until = time.monotonic() + 300.0

            self.write_state()

    def run_malware_scan(self, raw_target: str, request_id: str = "") -> None:
        if self.scan_cancel_requested:
            self.antivirus_status = "Scan cancelled"
            self.append_audit(
                "malware_scan_cancelled",
                {"target": raw_target, "requestId": request_id, "filesChecked": self.scan_files_checked},
            )
            return

        target = self.safe_scan_target(raw_target)
        backend = self.antivirus_backend()
        if target is None:
            self.antivirus_status = "Scan rejected — invalid target"
            self.append_audit("malware_scan_rejected", {"target": raw_target, "reason": "invalid target"})
            return
        if not backend:
            self.antivirus_status = "ClamAV is unavailable"
            self.emit_event(
                category="malware",
                severity=2,
                title="Antivirus engine unavailable",
                message="ClamAV is not installed or could not be started.",
                source="security-core",
                evidence=str(target),
                confidence=100,
                recommended_action="Install or repair ClamAV before relying on malware scanning.",
                fingerprint=stable_fingerprint("clamav-unavailable", utc_now()[:10]),
            )
            return

        self.antivirus_status = f"Scanning {target.name or str(target)}"
        self.scan_current_file = str(target)
        self.write_state()

        # Do not use --infected here. Clean-file output is intentionally streamed
        # so the Security UI can show the exact file currently being inspected.
        command: list[str] = [
            backend,
            "--recursive",
            "--no-summary",
            "--stdout",
            "--max-filesize=256M",
            "--max-scansize=2G",
            str(target),
        ]

        # Full ClamAV signature loading is memory-heavy on the 2 GB Pi. Run the
        # scanner at low CPU/I/O priority and in its own address-space ceiling so
        # a scan failure cannot take the entire NeutronOS device down with it.
        nice = shutil.which("nice")
        ionice = shutil.which("ionice")
        stdbuf = shutil.which("stdbuf")
        prlimit = shutil.which("prlimit")
        if not prlimit:
            self.antivirus_status = "Scan unavailable — process memory limiter is missing"
            self.append_audit("malware_scan_rejected", {
                "target": str(target),
                "reason": "prlimit unavailable; refusing unbounded scan on low-memory hardware",
            })
            return
        if stdbuf:
            command = [stdbuf, "-oL", *command]
        if nice:
            command = [nice, "-n", "15", *command]
        if ionice:
            command = [ionice, "-c", "3", *command]
        memory_bytes = self.scan_memory_limit_mib * 1024 * 1024
        command = [prlimit, f"--as={memory_bytes}", "--", *command]

        existing = {
            (str(item.get("path", "")), str(item.get("signature", ""))): item
            for item in self.malware_findings
        }
        detected = 0
        output_tail: deque[str] = deque(maxlen=40)
        process: subprocess.Popen[str] | None = None
        last_state_write = 0.0

        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
            self.scan_pid = int(process.pid)

            if self.scan_cancel_requested:
                self._signal_scan_process_group(self.scan_pid, signal.SIGTERM)

            self.write_state()

            assert process.stdout is not None
            for raw_line in process.stdout:
                line = raw_line.rstrip("\n")
                if line:
                    output_tail.append(line)

                if ": " in line:
                    file_name, result = line.rsplit(": ", 1)
                    result = result.strip()
                    if file_name.startswith("/") or file_name.startswith(str(target)):
                        self.scan_current_file = file_name
                        if result == "OK" or result.endswith(" FOUND") or result.startswith("ERROR"):
                            self.scan_files_checked += 1

                    if result.endswith(" FOUND"):
                        signature = result[:-6].strip()
                        detected_path = Path(file_name)
                        key = (str(detected_path), signature)
                        record = existing.get(key)
                        if record is None:
                            record = {
                                "id": str(uuid.uuid4()),
                                "path": str(detected_path),
                                "signature": signature,
                                "detectedAt": utc_now(),
                                "status": "detected",
                                "sourceScan": str(target),
                            }
                            try:
                                record["size"] = detected_path.stat().st_size
                                record["sha256"] = self.file_digest(detected_path)
                            except Exception:
                                record["size"] = 0
                                record["sha256"] = ""
                            self.malware_findings.insert(0, record)
                            existing[key] = record
                            self.emit_event(
                                category="malware",
                                severity=4,
                                title="Malware detected",
                                message=f"{signature} was detected in {detected_path.name}.",
                                source="clamav",
                                evidence=str(detected_path),
                                confidence=98,
                                recommended_action="Review and quarantine the file. NeutronOS will never delete it automatically.",
                                fingerprint=stable_fingerprint("malware", str(detected_path), signature, record.get("sha256", "")),
                                extra={"findingId": record["id"], "signature": signature, "path": str(detected_path)},
                            )
                        detected += 1
                        self.scan_threats_found = detected

                now = time.monotonic()
                if now - last_state_write >= 0.75:
                    self.scan_elapsed_seconds = max(0, int(now - self.scan_started_monotonic))
                    self.write_state()
                    last_state_write = now

                if now - self.scan_started_monotonic >= 3600:
                    self._signal_scan_process_group(int(process.pid), signal.SIGKILL)
                    self.antivirus_status = "Scan timed out"
                    self.append_audit("malware_scan_timeout", {"target": str(target), "requestId": request_id})
                    return

            return_code = process.wait(timeout=15)

            if self.scan_cancel_requested:
                self.antivirus_status = "Scan cancelled"
                self.append_audit(
                    "malware_scan_cancelled",
                    {
                        "target": str(target),
                        "requestId": request_id,
                        "filesChecked": self.scan_files_checked,
                    },
                )
                return
        except subprocess.TimeoutExpired:
            if process is not None:
                self._signal_scan_process_group(int(process.pid), signal.SIGKILL)

            if self.scan_cancel_requested:
                self.antivirus_status = "Scan cancelled"
                self.append_audit(
                    "malware_scan_cancelled",
                    {
                        "target": str(target),
                        "requestId": request_id,
                        "filesChecked": self.scan_files_checked,
                    },
                )
                return

            self.antivirus_status = "Scan timed out"
            self.append_audit("malware_scan_timeout", {"target": str(target), "requestId": request_id})
            return
        except Exception as exc:
            if process is not None and process.poll() is None:
                self._signal_scan_process_group(int(process.pid), signal.SIGKILL)
            self.antivirus_status = "Scan failed"
            self.append_audit("malware_scan_error", {"target": str(target), "error": str(exc)})
            return

        self.last_malware_scan = utc_now()
        if return_code > 1:
            tail = "\n".join(output_tail)[-2000:]
            lowered = tail.lower()
            if return_code in (137, 134) or "memory" in lowered or "cannot allocate" in lowered:
                self.antivirus_status = f"Scan stopped by {self.scan_memory_limit_mib} MiB memory safety limit"
            else:
                self.antivirus_status = "Scan failed — ClamAV returned an error"
            self.append_audit("malware_scan_failed", {
                "target": str(target),
                "requestId": request_id,
                "returnCode": return_code,
                "memoryLimitMiB": self.scan_memory_limit_mib,
                "output": tail,
            })
            return

        self.scan_threats_found = detected
        self.antivirus_status = "Threats found" if detected else "Scan complete — no malware detected"
        self.malware_findings = self.malware_findings[:500]
        self.save_protection_state()
        self.append_audit("malware_scan_completed", {
            "target": str(target),
            "requestId": request_id,
            "detections": detected,
            "filesChecked": self.scan_files_checked,
            "memoryLimitMiB": self.scan_memory_limit_mib,
        })

    def quarantine_finding(self, finding_id: str) -> None:
        finding = next((item for item in self.malware_findings if str(item.get("id")) == finding_id), None)
        if finding is None:
            self.append_audit("quarantine_rejected", {"findingId": finding_id, "reason": "unknown finding"})
            return
        source = Path(str(finding.get("path", "")))
        if not source.is_file():
            finding["status"] = "missing"
            self.save_protection_state()
            self.append_audit("quarantine_rejected", {"findingId": finding_id, "reason": "source missing"})
            return
        item_id = str(uuid.uuid4())
        destination = self.quarantine_dir / f"{item_id}.quarantine"
        try:
            shutil.move(str(source), str(destination))
            os.chmod(destination, 0o600)
        except Exception as exc:
            self.append_audit("quarantine_error", {"findingId": finding_id, "error": str(exc)})
            return
        record = {
            "id": item_id,
            "findingId": finding_id,
            "originalPath": str(source),
            "quarantinePath": str(destination),
            "signature": str(finding.get("signature", "Unknown")),
            "sha256": str(finding.get("sha256", "")),
            "quarantinedAt": utc_now(),
            "status": "quarantined",
        }
        finding["status"] = "quarantined"
        finding["quarantineId"] = item_id
        self.quarantined_items.insert(0, record)
        self.save_protection_state()
        self.append_audit("file_quarantined", record)

    def restore_quarantined(self, item_id: str) -> None:
        item = next((entry for entry in self.quarantined_items if str(entry.get("id")) == item_id), None)
        if item is None:
            self.append_audit("restore_rejected", {"itemId": item_id, "reason": "unknown item"})
            return
        source = Path(str(item.get("quarantinePath", "")))
        destination = Path(str(item.get("originalPath", "")))
        if not source.is_file():
            item["status"] = "missing"
            self.save_protection_state()
            return
        try:
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                destination = destination.with_name(destination.name + ".restored")
            shutil.move(str(source), str(destination))
        except Exception as exc:
            self.append_audit("restore_error", {"itemId": item_id, "error": str(exc)})
            return
        item["status"] = "restored"
        item["restoredPath"] = str(destination)
        item["restoredAt"] = utc_now()
        self.save_protection_state()
        self.append_audit("quarantined_file_restored", {"itemId": item_id, "path": str(destination)})

    def integrity_target_roots(self) -> list[Path]:
        values = [
            self.project_root / "src",
            self.project_root / "qml",
            self.project_root / "scripts",
            self.project_root / "systemd",
            self.project_root / "config",
            Path("/etc/ssh/sshd_config"),
            Path("/etc/sudoers"),
            Path("/etc/pam.d"),
            Path("/etc/systemd/system/neutronos.service"),
            Path("/etc/systemd/system/neutron-securityd.service"),
            Path("/etc/default/grub"),
            Path("/boot/grub/grub.cfg"),
        ]
        result: list[Path] = []
        for value in values:
            try:
                if value.exists():
                    result.append(value.resolve())
            except Exception:
                continue
        return result

    def integrity_files(self) -> list[Path]:
        excluded_names = {"build", ".git", "state", "node_modules", "__pycache__"}
        maximum = max(1000, int(self.config.get("integrityMaxFiles", 12000)))
        files: list[Path] = []
        for root in self.integrity_target_roots():
            if root.is_file():
                files.append(root)
                continue
            for current, directories, names in os.walk(root):
                directories[:] = [name for name in directories if name not in excluded_names]
                for name in names:
                    candidate = Path(current) / name
                    try:
                        if candidate.is_file() and not candidate.is_symlink():
                            files.append(candidate)
                    except Exception:
                        continue
                    if len(files) >= maximum:
                        return files
        return files

    def snapshot_integrity(self) -> dict[str, dict[str, Any]]:
        snapshot: dict[str, dict[str, Any]] = {}
        for file_path in self.integrity_files():
            try:
                info = file_path.stat()
                snapshot[str(file_path)] = {
                    "sha256": self.file_digest(file_path),
                    "size": info.st_size,
                    "mtimeNs": info.st_mtime_ns,
                }
            except Exception:
                continue
        return snapshot

    @staticmethod
    def integrity_change_signature(changes: list[dict[str, Any]]) -> str:
        normalized = [
            {
                "path": str(change.get("path", "")),
                "change": str(change.get("change", "")),
                "expectedHash": str(change.get("expectedHash", "")),
                "actualHash": str(change.get("actualHash", "")),
            }
            for change in changes
        ]
        normalized.sort(key=lambda item: (item["path"], item["change"], item["actualHash"], item["expectedHash"]))
        return hashlib.sha256(canonical(normalized)).hexdigest() if normalized else ""

    def create_integrity_baseline(self, reason: str = "manual") -> None:
        self.integrity_status = "Creating trusted baseline"
        self.write_state()
        baseline = self.snapshot_integrity()
        self.integrity_baseline = baseline
        atomic_json(self.integrity_baseline_path, baseline, 0o640)
        self.integrity_changes = []
        self.previous_integrity_signature = ""
        self.previous_integrity_count = 0
        self.last_integrity_scan = utc_now()
        self.integrity_status = f"Trusted baseline ready — {len(baseline)} files"
        self.append_audit("integrity_baseline_created", {"reason": reason, "files": len(baseline)})

    def appstore_uninstall_authorization(self) -> dict[str, Any]:
        path = Path("/run/neutronos/appstore-integrity-uninstall.json")
        try:
            info = path.stat()
            if info.st_uid != 0 or (info.st_mode & 0o022):
                return {}
            value = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, OSError, json.JSONDecodeError, TypeError, ValueError):
            return {}
        if not isinstance(value, dict) or int(value.get("schema", 0)) != 1 or value.get("operation") != "uninstall":
            return {}
        try:
            if float(value.get("expiresAtEpoch", 0.0)) < time.time():
                return {}
        except (TypeError, ValueError):
            return {}
        package_id = str(value.get("packageId") or "").strip().lower()
        raw_paths = value.get("paths", [])
        if not package_id or not isinstance(raw_paths, list):
            return {}
        exact = []
        for raw in raw_paths:
            candidate = str(raw or "").strip()
            if candidate.startswith("/") and candidate not in exact:
                exact.append(candidate)
        return {"path": path, "packageId": package_id, "paths": exact}

    @staticmethod
    def appstore_registry_contains(path: Path, package_id: str) -> bool:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, OSError, json.JSONDecodeError, TypeError, ValueError):
            return False
        packages = value.get("packages") if isinstance(value, dict) else {}
        return isinstance(packages, dict) and package_id in packages

    def reconcile_authorized_appstore_uninstall(self, current: dict[str, dict[str, Any]]) -> set[str]:
        authorization = self.appstore_uninstall_authorization()
        if not authorization:
            return set()
        package_id = str(authorization["packageId"])
        exact = set(str(value) for value in authorization.get("paths", []))
        normal_present = self.appstore_registry_contains(Path("/var/lib/neutronos/app-store/installed.json"), package_id)
        root_present = self.appstore_registry_contains(Path("/var/lib/neutronos/app-store/root-installed.json"), package_id)

        if normal_present or root_present:
            return exact

        accepted = []
        for name in sorted(exact):
            if name in self.integrity_baseline and name not in current:
                self.integrity_baseline.pop(name, None)
                accepted.append(name)
        if accepted:
            atomic_json(self.integrity_baseline_path, self.integrity_baseline, 0o640)
            self.append_audit("appstore_uninstall_integrity_committed", {
                "packageId": package_id,
                "acceptedRemovedPaths": accepted,
                "count": len(accepted),
            })
        try:
            Path(authorization["path"]).unlink()
        except (FileNotFoundError, OSError):
            pass
        return set()

    def verify_integrity(self) -> None:
        if not self.integrity_baseline:
            if self.config.get("autoCreateIntegrityBaseline", True):
                self.create_integrity_baseline("automatic first run")
            else:
                self.integrity_status = "No trusted baseline"
            return
        current = self.snapshot_integrity()
        authorized_in_flight = self.reconcile_authorized_appstore_uninstall(current)
        changes: list[dict[str, Any]] = []
        for name, expected in self.integrity_baseline.items():
            actual = current.get(name)
            if actual is None:
                if name in authorized_in_flight:
                    continue
                changes.append({"path": name, "change": "removed", "expectedHash": expected.get("sha256", "")})
            elif actual.get("sha256") != expected.get("sha256"):
                changes.append({
                    "path": name,
                    "change": "modified",
                    "expectedHash": expected.get("sha256", ""),
                    "actualHash": actual.get("sha256", ""),
                })
        for name, actual in current.items():
            if name not in self.integrity_baseline:
                changes.append({"path": name, "change": "added", "actualHash": actual.get("sha256", "")})
        self.integrity_changes = changes[:500]
        self.last_integrity_scan = utc_now()
        self.integrity_status = "Verified — no changes" if not changes else f"{len(changes)} unapproved changes detected"
        for change in changes[:50]:
            path_name = str(change.get("path", ""))
            change_type = str(change.get("change", "changed"))
            self.emit_event(
                category="integrity",
                severity=4 if change_type in {"modified", "removed"} else 3,
                title="Protected file changed",
                message=f"A protected file was {change_type}: {path_name}",
                source="file-integrity",
                evidence=json.dumps(change, sort_keys=True),
                confidence=100,
                recommended_action="Review the change before accepting a new baseline.",
                fingerprint=stable_fingerprint("integrity", path_name, change_type, str(change.get("actualHash", ""))),
                extra={"path": path_name, "change": change_type},
            )

        current_signature = self.integrity_change_signature(self.integrity_changes)
        if current_signature != self.previous_integrity_signature:
            if self.integrity_changes:
                previous_paths = {
                    (str(item.get("path", "")), str(item.get("change", "")))
                    for item in getattr(self, "_previous_integrity_changes", [])
                    if isinstance(item, dict)
                }
                current_paths = {
                    (str(item.get("path", "")), str(item.get("change", "")))
                    for item in self.integrity_changes
                }
                self.append_audit("integrity_changes_detected", {
                    "count": len(self.integrity_changes),
                    "previousCount": self.previous_integrity_count,
                    "newEntries": len(current_paths - previous_paths),
                    "resolvedEntries": len(previous_paths - current_paths),
                    "changeSetHash": current_signature,
                })
            elif self.previous_integrity_signature:
                self.append_audit("integrity_restored", {
                    "previousCount": self.previous_integrity_count,
                })
        self._previous_integrity_changes = [dict(item) for item in self.integrity_changes]
        self.previous_integrity_signature = current_signature
        self.previous_integrity_count = len(self.integrity_changes)

    def scan_package_changes(self) -> None:
        watched = [Path("/var/lib/dpkg/status"), Path("/var/log/dpkg.log")]
        current: dict[str, Any] = {}
        for candidate in watched:
            try:
                info = candidate.stat()
                current[str(candidate)] = {"size": info.st_size, "mtimeNs": info.st_mtime_ns}
            except Exception:
                continue
        previous = self.package_state.get("files", {}) if isinstance(self.package_state.get("files", {}), dict) else {}
        if previous and current != previous:
            evidence = ""
            log_path = Path("/var/log/dpkg.log")
            try:
                evidence = "\n".join(log_path.read_text(encoding="utf-8", errors="ignore").splitlines()[-20:])
            except Exception:
                pass
            record = {"timestamp": utc_now(), "summary": "Debian package database changed", "evidence": evidence}
            self.package_changes.insert(0, record)
            self.package_changes = self.package_changes[:100]
            self.emit_event(
                category="package",
                severity=2,
                title="System packages changed",
                message="The Debian package database or installation log changed.",
                source="dpkg",
                evidence=evidence or json.dumps(current, sort_keys=True),
                confidence=95,
                recommended_action="Confirm the package installation or removal was authorized.",
                fingerprint=stable_fingerprint("dpkg-change", json.dumps(current, sort_keys=True)),
            )
        self.package_state["files"] = current
        self.package_state["checkedAt"] = utc_now()

    def peripheral_identity(self, device: dict[str, Any]) -> str:
        return stable_fingerprint(
            str(device.get("vendorId", "")),
            str(device.get("productId", "")),
            str(device.get("serial", "")),
            str(device.get("manufacturer", "")),
            str(device.get("product", "")),
        )

    def set_peripheral_authorized(self, sys_path: str, authorized: bool) -> bool:
        path = Path("/sys/bus/usb/devices") / sys_path / "authorized"
        try:
            path.write_text("1" if authorized else "0", encoding="ascii")
            return True
        except Exception:
            return False

    def trust_peripheral(self, device_id: str) -> None:
        trusted = list(dict.fromkeys([str(value) for value in self.config.get("trustedPeripherals", [])] + [device_id]))
        self.config["trustedPeripherals"] = trusted
        self.config["blockedPeripherals"] = [str(value) for value in self.config.get("blockedPeripherals", []) if str(value) != device_id]
        self.save_config()
        self.append_audit("peripheral_trusted", {"deviceId": device_id})

    def allow_peripheral_once(self, device_id: str) -> None:
        values = list(dict.fromkeys([str(value) for value in self.config.get("allowOncePeripherals", [])] + [device_id]))
        self.config["allowOncePeripherals"] = values
        self.save_config()
        for device in self.peripherals:
            if str(device.get("deviceId")) == device_id:
                self.set_peripheral_authorized(str(device.get("path", "")), True)
        self.append_audit("peripheral_allowed_once", {"deviceId": device_id})

    def block_peripheral(self, device_id: str) -> None:
        blocked = list(dict.fromkeys([str(value) for value in self.config.get("blockedPeripherals", [])] + [device_id]))
        self.config["blockedPeripherals"] = blocked
        self.config["trustedPeripherals"] = [str(value) for value in self.config.get("trustedPeripherals", []) if str(value) != device_id]
        self.save_config()
        applied = False
        for device in self.peripherals:
            if str(device.get("deviceId")) == device_id:
                applied = self.set_peripheral_authorized(str(device.get("path", "")), False) or applied
        self.append_audit("peripheral_blocked", {"deviceId": device_id, "applied": applied})

    def save_config(self) -> None:
        atomic_json(self.config_path, self.config, 0o640)

    def save_bans(self) -> None:
        atomic_json(self.bans_path, self.bans, 0o640)

    def save_events(self) -> None:
        atomic_json(self.events_path, list(self.events), 0o640)
        cutoff = datetime.now(timezone.utc) - timedelta(days=7)
        kept: dict[str, str] = {}
        for fingerprint, stamp in self.fingerprints.items():
            parsed = parse_time(stamp)
            if parsed is None or parsed >= cutoff:
                kept[fingerprint] = stamp
        self.fingerprints = kept
        atomic_json(self.fingerprints_path, self.fingerprints, 0o640)

    def verify_audit(self) -> tuple[bool, str]:
        previous = "0" * 64
        if not self.audit_path.exists():
            return True, previous
        try:
            with self.audit_path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    if not line.strip():
                        continue
                    record = json.loads(line)
                    supplied = str(record.pop("hash", ""))
                    if record.get("previousHash") != previous:
                        return False, previous
                    calculated = hashlib.sha256(previous.encode("ascii") + canonical(record)).hexdigest()
                    if supplied != calculated:
                        return False, previous
                    previous = supplied
            return True, previous
        except Exception:
            return False, previous

    def append_audit(self, action: str, details: dict[str, Any]) -> None:
        record = {
            "id": str(uuid.uuid4()),
            "timestamp": utc_now(),
            "action": action,
            "details": details,
            "previousHash": self.audit_head,
        }
        digest = hashlib.sha256(self.audit_head.encode("ascii") + canonical(record)).hexdigest()
        record["hash"] = digest
        self.audit_path.parent.mkdir(parents=True, exist_ok=True)
        with self.audit_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(self.audit_path, 0o640)
        self.audit_head = digest

    def trusted_source(self, address: str) -> bool:
        try:
            source = ipaddress.ip_address(address)
        except ValueError:
            return True
        for entry in self.config.get("trustedSources", []):
            try:
                if "/" in str(entry):
                    if source in ipaddress.ip_network(str(entry), strict=False):
                        return True
                elif source == ipaddress.ip_address(str(entry)):
                    return True
            except ValueError:
                continue
        return source.is_loopback

    def refresh_firewall_health(self, record_event: bool = False) -> dict[str, Any]:
        """Verify kernel protection independently of daemon availability.

        The guard's state file is useful telemetry, but it is not trusted as
        proof by itself.  The daemon verifies that the life-support table is
        present in the running kernel.  A stale/dead guard with a still-active
        lifeline is DEGRADED; a missing lifeline is CRITICAL.
        """
        raw: dict[str, Any] = {}
        try:
            value = json.loads(FIREWALL_STATE_PATH.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                raw = value
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            raw = {}

        lifeline_text = run(["nft", "list", "table", "inet", "neutronos_lifeline"], timeout=5).strip()
        base_text = run(["nft", "list", "table", "inet", "neutronos"], timeout=5).strip()
        security_text = run(["nft", "list", "table", "inet", "neutronos_security"], timeout=5).strip()

        def enforcing_drop_policy(text: str) -> bool:
            lowered = text.lower()
            return (
                "hook input" in lowered
                and "hook forward" in lowered
                and lowered.count("policy drop") >= 2
            )

        lifeline_live = bool(lifeline_text)
        lifeline_enforcing = enforcing_drop_policy(lifeline_text)
        base_live = enforcing_drop_policy(base_text)
        security_live = bool(security_text) and "@banned_v4" in security_text and "@banned_v6" in security_text
        firewall_active = bool(base_live or lifeline_enforcing)

        updated = parse_time(str(raw.get("updatedAt", "")))
        stale = True
        if updated is not None:
            stale = (datetime.now(timezone.utc) - updated.astimezone(timezone.utc)).total_seconds() > FIREWALL_STALE_SECONDS

        guard_state = str(raw.get("protectionState", "")).upper()
        if not firewall_active:
            protection = "CRITICAL"
            reason = "No fail-closed NeutronOS kernel firewall policy is currently enforcing traffic"
        elif stale:
            protection = "DEGRADED"
            reason = "Kernel firewall is active but the firewall guard heartbeat is stale"
        elif guard_state == "CRITICAL":
            # Direct kernel verification wins over stale pessimistic telemetry,
            # but a disagreement between guard and kernel remains degraded.
            protection = "DEGRADED"
            reason = str(raw.get("lastError") or "Firewall guard reports a critical recovery condition while kernel protection remains active")
        elif guard_state == "DEGRADED" or not base_live or not security_live:
            protection = "DEGRADED"
            reason = str(raw.get("lastError") or "Emergency firewall protection is active; full policy is being restored")
        else:
            protection = "SECURE"
            reason = "Kernel firewall, policy layer, and Security ban layer are active"

        health = dict(raw)
        health.update({
            "protectionState": protection,
            "firewallActive": firewall_active,
            "lifelineActive": lifeline_live,
            "lifelineEnforcing": lifeline_enforcing,
            "baseTableActive": base_live,
            "securityTableActive": security_live,
            "guardStateStale": stale,
            "reason": reason,
        })
        previous = self.previous_firewall_protection_state
        self.firewall_health = health
        self.previous_firewall_protection_state = protection

        if record_event and previous and previous != protection:
            severity = 5 if protection == "CRITICAL" else (3 if protection == "DEGRADED" else 1)
            title = (
                "Firewall protection critical" if protection == "CRITICAL"
                else ("Firewall protection degraded" if protection == "DEGRADED"
                      else "Firewall protection restored")
            )
            self.emit_event(
                category="firewall", severity=severity, title=title,
                message=reason, source="firewall-life-support",
                evidence=json.dumps({
                    "previous": previous, "current": protection,
                    "lifeline": lifeline_live, "lifelineEnforcing": lifeline_enforcing,
                    "base": base_live, "securityTable": security_live, "guardStale": stale,
                }, sort_keys=True),
                confidence=100,
                recommended_action=(
                    "Keep the system isolated until firewall life-support recovers."
                    if protection == "CRITICAL"
                    else ("Review the firewall guard and restore the normal policy layer."
                          if protection == "DEGRADED"
                          else "No action required; full firewall protection has recovered.")
                ),
                fingerprint=stable_fingerprint("firewall-protection", protection, utc_now()[:13]),
            )
            self.append_audit("firewall_protection_state_changed", {
                "previous": previous, "current": protection, "reason": reason,
            })
        return health

    def firewall_backend(self) -> str:
        if run(["sh", "-c", "command -v nft"], timeout=3).strip():
            return "nftables"
        if run(["sh", "-c", "command -v iptables"], timeout=3).strip():
            return "iptables"
        return "unavailable"

    def ensure_nftables(self) -> bool:
        if run(["nft", "list", "table", "inet", "neutronos_security"], timeout=5).strip():
            return True
        commands = [
            ["nft", "add", "table", "inet", "neutronos_security"],
            ["nft", "add", "set", "inet", "neutronos_security", "banned_v4", "{", "type", "ipv4_addr", ";", "}"],
            ["nft", "add", "set", "inet", "neutronos_security", "banned_v6", "{", "type", "ipv6_addr", ";", "}"],
            ["nft", "add", "chain", "inet", "neutronos_security", "input", "{", "type", "filter", "hook", "input", "priority", "-20", ";", "policy", "accept", ";", "}"],
            ["nft", "add", "rule", "inet", "neutronos_security", "input", "ip", "saddr", "@banned_v4", "drop"],
            ["nft", "add", "rule", "inet", "neutronos_security", "input", "ip6", "saddr", "@banned_v6", "drop"],
        ]
        # Repeated add operations are intentionally tolerated. Verify the table at the end.
        for command in commands:
            subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return bool(run(["nft", "list", "table", "inet", "neutronos_security"], timeout=5).strip())

    def firewall_add(self, address: str) -> tuple[bool, str]:
        backend = self.firewall_backend()
        try:
            source = ipaddress.ip_address(address)
        except ValueError:
            return False, "invalid address"
        if backend == "nftables":
            if not self.ensure_nftables():
                return False, "nftables table unavailable"
            set_name = "banned_v4" if source.version == 4 else "banned_v6"
            result = subprocess.run(
                ["nft", "add", "element", "inet", "neutronos_security", set_name, "{", address, "}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
            )
            # Existing elements also return failure; listing confirms actual state.
            listing = run(["nft", "list", "set", "inet", "neutronos_security", set_name], timeout=5)
            return address in listing, backend
        if backend == "iptables":
            binary = "iptables" if source.version == 4 else "ip6tables"
            check = subprocess.run([binary, "-C", "INPUT", "-s", address, "-j", "DROP"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if check.returncode != 0:
                subprocess.run([binary, "-I", "INPUT", "1", "-s", address, "-j", "DROP"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            check = subprocess.run([binary, "-C", "INPUT", "-s", address, "-j", "DROP"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            return check.returncode == 0, backend
        return False, backend

    def firewall_remove(self, address: str) -> tuple[bool, str]:
        backend = self.firewall_backend()
        try:
            source = ipaddress.ip_address(address)
        except ValueError:
            return False, "invalid address"
        if backend == "nftables":
            set_name = "banned_v4" if source.version == 4 else "banned_v6"
            subprocess.run(["nft", "delete", "element", "inet", "neutronos_security", set_name, "{", address, "}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            listing = run(["nft", "list", "set", "inet", "neutronos_security", set_name], timeout=5)
            return address not in listing, backend
        if backend == "iptables":
            binary = "iptables" if source.version == 4 else "ip6tables"
            while subprocess.run([binary, "-C", "INPUT", "-s", address, "-j", "DROP"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode == 0:
                subprocess.run([binary, "-D", "INPUT", "-s", address, "-j", "DROP"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            return True, backend
        return False, backend

    def ban_source(self, address: str, duration_minutes: int, reason: str, manual: bool = False) -> bool:
        try:
            normalized = str(ipaddress.ip_address(address))
        except ValueError:
            return False
        if self.trusted_source(normalized):
            self.append_audit("ban_skipped_trusted_source", {"address": normalized, "reason": reason})
            return False
        duration_minutes = max(1, min(10080, int(duration_minutes)))
        now = datetime.now(timezone.utc)
        expires = now + timedelta(minutes=duration_minutes)
        applied, backend = self.firewall_add(normalized)
        self.bans[normalized] = {
            "address": normalized,
            "createdAt": utc_now(),
            "expiresAt": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "durationMinutes": duration_minutes,
            "reason": reason[:400],
            "manual": bool(manual),
            "active": bool(applied),
            "firewallBackend": backend,
        }
        self.save_bans()
        self.append_audit("source_banned" if applied else "source_ban_failed", self.bans[normalized])
        return applied

    def unban_source(self, address: str, reason: str) -> bool:
        try:
            normalized = str(ipaddress.ip_address(address))
        except ValueError:
            return False
        removed, backend = self.firewall_remove(normalized)
        previous = self.bans.pop(normalized, None)
        self.save_bans()
        self.append_audit("source_unbanned", {"address": normalized, "reason": reason, "firewallBackend": backend, "previous": previous or {}})
        return removed

    def expire_bans(self) -> None:
        now = datetime.now(timezone.utc)
        expired = []
        for address, record in self.bans.items():
            expiry = parse_time(str(record.get("expiresAt", "")))
            if expiry is not None and expiry <= now:
                expired.append(address)
        for address in expired:
            self.unban_source(address, "Ban duration expired")

    def maybe_enforce_authentication(self, event: dict[str, Any]) -> None:
        address = str(event.get("sourceAddress", ""))
        if not address or address == "local" or self.trusted_source(address):
            return
        if self.config.get("learningMode", True) or not self.config.get("enforcementEnabled", False):
            event["actionTaken"] = "Observed only — Learning Mode"
            return
        threshold = max(3, int(self.config.get("automaticBanThreshold", 5)))
        attempts = int(event.get("attempts", 1))
        if attempts < threshold or address in self.bans:
            return
        counts = self.config.setdefault("offenseCounts", {})
        offense = int(counts.get(address, 0)) + 1
        counts[address] = offense
        durations = [max(1, int(value)) for value in self.config.get("banDurationsMinutes", [10, 60, 1440])]
        duration = durations[min(offense - 1, len(durations) - 1)]
        reason = f"{attempts} correlated failed authentication attempts within the active incident window"
        if self.ban_source(address, duration, reason, manual=False):
            event["enforced"] = True
            event["severity"] = max(4, int(event.get("severity", 3)))
            event["actionTaken"] = f"Source blocked for {duration} minutes"
            event["banDurationMinutes"] = duration
            event["recommendedAction"] = "Review the incident and unblock only if the source is verified as trusted."
            self.save_config()

    def emit_event(
        self,
        *,
        category: str,
        severity: int,
        title: str,
        message: str,
        source: str,
        evidence: str,
        confidence: int,
        recommended_action: str,
        fingerprint: str,
        extra: dict[str, Any] | None = None,
    ) -> None:
        if fingerprint in self.fingerprints:
            return
        stamp = utc_now()
        event = {
            "id": str(uuid.uuid4()),
            "timestamp": stamp,
            "category": category,
            "severity": max(1, min(5, int(severity))),
            "title": title[:160],
            "message": message[:1000],
            "source": source[:120],
            "evidence": evidence[:1800],
            "confidence": max(0, min(100, int(confidence))),
            "recommendedAction": recommended_action[:400],
            "actionTaken": "Observed only — Learning Mode",
            "acknowledged": False,
            "enforced": False,
        }
        if extra:
            event.update(extra)
        self.events.appendleft(event)
        self.fingerprints[fingerprint] = stamp
        self.append_audit("security_event", event)

    def migrate_expected_listener_events(self) -> None:
        changed_ids: list[str] = []
        for event in self.events:
            if event.get("acknowledged") or event.get("category") != "network":
                continue
            if str(event.get("title", "")) != "New external listening port":
                continue
            evidence_value = str(event.get("evidence", ""))
            try:
                evidence = json.loads(evidence_value)
            except Exception:
                evidence = {}
            protocol = str(event.get("protocol", evidence.get("protocol", ""))).lower()
            process_value = str(evidence.get("process", ""))
            process_name = str(evidence.get("processName", "")) or self.listener_process_name(process_value)
            if protocol == "udp" and process_name == "tailscaled":
                event["acknowledged"] = True
                event["expected"] = True
                event["expectedReason"] = "Expected Tailscale peer-to-peer UDP transport listener"
                changed_ids.append(str(event.get("id", "")))
        if changed_ids:
            self.save_events()
            self.append_audit("expected_listener_events_reclassified", {
                "count": len(changed_ids),
                "eventIds": changed_ids[:50],
                "process": "tailscaled",
                "protocol": "udp",
            })

    @staticmethod
    def journal_timestamp(entry: dict[str, Any]) -> datetime:
        raw = str(entry.get("__REALTIME_TIMESTAMP", ""))
        try:
            return datetime.fromtimestamp(int(raw) / 1_000_000, tz=timezone.utc)
        except Exception:
            return datetime.now(timezone.utc)

    @staticmethod
    def authentication_identity(message: str) -> tuple[str, str, str]:
        address_match = IP_PATTERN.search(message)
        port_match = PORT_PATTERN.search(message)
        user_match = FAILED_USER_PATTERN.search(message) or INVALID_USER_PATTERN.search(message) or PAM_USER_PATTERN.search(message)
        address = address_match.group(1) if address_match else "local"
        port = port_match.group(1) if port_match else ""
        username = user_match.group(1) if user_match else "unknown"
        return address, port, username

    @staticmethod
    def evidence_lines(value: str) -> list[str]:
        return [line.strip() for line in str(value).splitlines() if line.strip()]

    def migrate_existing_authentication_events(self) -> None:
        if int(self.config.get("incidentCorrelationVersion", 0)) >= 1:
            return

        original = list(self.events)
        auth_positions = [
            index for index, event in enumerate(original)
            if event.get("category") == "authentication"
            and not event.get("incidentKey")
        ]
        if not auth_positions:
            self.config["incidentCorrelationVersion"] = 1
            self.save_config()
            return

        clusters: list[dict[str, Any]] = []
        consumed: set[int] = set()
        for position in auth_positions:
            if position in consumed:
                continue
            seed = original[position]
            seed_time = parse_time(str(seed.get("timestamp", ""))) or datetime.now(timezone.utc)
            address, port, username = self.authentication_identity(str(seed.get("evidence", "")))
            unit = str(seed.get("source", "journal"))
            members = [position]
            consumed.add(position)
            for other_position in auth_positions:
                if other_position in consumed:
                    continue
                other = original[other_position]
                other_time = parse_time(str(other.get("timestamp", ""))) or seed_time
                if abs((other_time - seed_time).total_seconds()) > AUTH_SESSION_WINDOW_SECONDS:
                    continue
                other_address, other_port, other_username = self.authentication_identity(str(other.get("evidence", "")))
                if str(other.get("source", "journal")) != unit:
                    continue
                if address != "local" and other_address != "local" and address != other_address:
                    continue
                if port and other_port and port != other_port:
                    continue
                if username != "unknown" and other_username != "unknown" and username != other_username:
                    continue
                members.append(other_position)
                consumed.add(other_position)
                if address == "local":
                    address = other_address
                if not port:
                    port = other_port
                if username == "unknown":
                    username = other_username

            if len(members) == 1:
                continue
            events = [original[index] for index in members]
            times = [parse_time(str(event.get("timestamp", ""))) or seed_time for event in events]
            evidence: list[str] = []
            source_ports: set[str] = set()
            for event in events:
                ev_address, ev_port, ev_username = self.authentication_identity(str(event.get("evidence", "")))
                if address == "local" and ev_address != "local":
                    address = ev_address
                if username == "unknown" and ev_username != "unknown":
                    username = ev_username
                if ev_port:
                    source_ports.add(ev_port)
                for line in self.evidence_lines(str(event.get("evidence", ""))):
                    if line not in evidence:
                        evidence.append(line)
            attempts = max(1, len(source_ports))
            first = min(times)
            last = max(times)
            kept = dict(events[0])
            kept.update({
                "title": "SSH authentication incident" if "ssh" in unit.lower() else "Authentication incident",
                "message": f"{attempts} failed authentication attempt{'s' if attempts != 1 else ''} observed from {address}.",
                "evidence": "\n".join(evidence)[:6000],
                "sourceAddress": address,
                "sourcePort": next(iter(source_ports), port),
                "sourcePorts": sorted(source_ports),
                "username": username,
                "attempts": attempts,
                "evidenceRecords": len(evidence),
                "firstSeen": first.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                "lastSeen": last.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                "incidentKey": stable_fingerprint("auth-incident", unit, address, username),
                "correlated": True,
            })
            clusters.append({"positions": members, "event": kept})

        if clusters:
            replacements = {cluster["positions"][0]: cluster["event"] for cluster in clusters}
            removed = {position for cluster in clusters for position in cluster["positions"][1:]}
            merged = []
            for index, event in enumerate(original):
                if index in removed:
                    continue
                merged.append(replacements.get(index, event))
            self.events = deque(merged[: self.events.maxlen], maxlen=self.events.maxlen)
            self.save_events()
            self.append_audit("authentication_events_correlated", {
                "clusters": len(clusters),
                "recordsMerged": sum(len(cluster["positions"]) for cluster in clusters),
            })

        self.config["incidentCorrelationVersion"] = 1
        self.save_config()

    def correlate_authentication_records(self, records: list[dict[str, Any]]) -> list[dict[str, Any]]:
        groups: list[dict[str, Any]] = []
        for record in sorted(records, key=lambda item: item["time"]):
            selected: dict[str, Any] | None = None
            for group in reversed(groups):
                if group["category"] != record["category"] or group["unit"] != record["unit"]:
                    continue
                if (record["time"] - group["lastTime"]).total_seconds() > AUTH_SESSION_WINDOW_SECONDS:
                    break
                if group["address"] != "local" and record["address"] != "local" and group["address"] != record["address"]:
                    continue
                if group["port"] and record["port"] and group["port"] != record["port"]:
                    continue
                if group["username"] != "unknown" and record["username"] != "unknown" and group["username"] != record["username"]:
                    continue
                selected = group
                break
            if selected is None:
                selected = {
                    "category": record["category"],
                    "unit": record["unit"],
                    "address": record["address"],
                    "port": record["port"],
                    "username": record["username"],
                    "firstTime": record["time"],
                    "lastTime": record["time"],
                    "entries": [],
                    "hasPrimary": bool(record.get("primary", True)),
                }
                groups.append(selected)
            selected["lastTime"] = record["time"]
            if selected["address"] == "local" and record["address"] != "local":
                selected["address"] = record["address"]
            if not selected["port"] and record["port"]:
                selected["port"] = record["port"]
            if selected["username"] == "unknown" and record["username"] != "unknown":
                selected["username"] = record["username"]
            selected["hasPrimary"] = bool(selected.get("hasPrimary")) or bool(record.get("primary", True))
            selected["entries"].append(record)
        return groups

    def record_authentication_incident(self, group: dict[str, Any]) -> None:
        first = group["firstTime"]
        last = group["lastTime"]
        session_fingerprint = stable_fingerprint(
            "auth-session", group["category"], group["unit"], group["address"],
            group["port"], group["username"], str(int(first.timestamp()))
        )
        if session_fingerprint in self.fingerprints or not group.get("hasPrimary", True):
            return

        incident_key = stable_fingerprint(
            "auth-incident", group["category"], group["unit"],
            group["address"], group["username"]
        )
        evidence: list[str] = []
        for entry in group["entries"]:
            line = str(entry["message"]).strip()
            if line and line not in evidence:
                evidence.append(line)

        existing: dict[str, Any] | None = None
        for event in self.events:
            if event.get("incidentKey") != incident_key or event.get("acknowledged"):
                continue
            previous_last = parse_time(str(event.get("lastSeen", event.get("timestamp", ""))))
            if previous_last is not None and (first - previous_last).total_seconds() <= AUTH_INCIDENT_WINDOW_SECONDS:
                existing = event
                break

        stamp = utc_now()
        if existing is not None:
            existing_lines = self.evidence_lines(str(existing.get("evidence", "")))
            for line in evidence:
                if line not in existing_lines:
                    existing_lines.append(line)
            ports = {str(value) for value in existing.get("sourcePorts", []) if str(value)}
            if group["port"]:
                ports.add(group["port"])
            existing["attempts"] = int(existing.get("attempts", 1)) + 1
            existing["evidenceRecords"] = len(existing_lines)
            existing["evidence"] = "\n".join(existing_lines)[:6000]
            existing["lastSeen"] = last.isoformat(timespec="milliseconds").replace("+00:00", "Z")
            existing["timestamp"] = stamp
            existing["sourcePorts"] = sorted(ports)
            existing["sourcePort"] = group["port"] or existing.get("sourcePort", "")
            existing["message"] = (
                f"{existing['attempts']} failed authentication attempts observed "
                f"from {group['address']}."
            )
            self.maybe_enforce_authentication(existing)
            self.append_audit("security_event_updated", {
                "eventId": existing.get("id", ""),
                "incidentKey": incident_key,
                "attempts": existing["attempts"],
                "newEvidenceRecords": len(evidence),
                "sourceAddress": group["address"],
                "sourcePort": group["port"],
            })
        else:
            severity = 4 if group["category"] == "privilege" else 3
            title = "Privilege authentication incident" if group["category"] == "privilege" else (
                "SSH authentication incident" if "ssh" in group["unit"].lower() else "Authentication incident"
            )
            message = f"1 failed authentication attempt observed from {group['address']}."
            self.emit_event(
                category=group["category"],
                severity=severity,
                title=title,
                message=message,
                source=group["unit"],
                evidence="\n".join(evidence),
                confidence=92 if group["category"] == "privilege" else 90,
                recommended_action=(
                    "Confirm whether the privileged operation was expected and inspect the originating account."
                    if group["category"] == "privilege"
                    else "Review the source and correlated-attempt pattern. Network enforcement can rate-limit and ban the source after the configured threshold; trust it only after verifying the device."
                ),
                fingerprint=session_fingerprint,
                extra={
                    "sourceAddress": group["address"],
                    "sourcePort": group["port"],
                    "sourcePorts": [group["port"]] if group["port"] else [],
                    "username": group["username"],
                    "attempts": 1,
                    "evidenceRecords": len(evidence),
                    "firstSeen": first.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                    "lastSeen": last.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                    "incidentKey": incident_key,
                    "correlated": True,
                },
            )
            for emitted in self.events:
                if emitted.get("incidentKey") == incident_key:
                    self.maybe_enforce_authentication(emitted)
                    break
        self.fingerprints[session_fingerprint] = stamp

    def scan_journal(self) -> None:
        output = run(["journalctl", "-b", "--no-pager", "-n", "900", "-o", "json"], timeout=12)
        records: list[dict[str, Any]] = []
        for line in output.splitlines():
            try:
                entry = json.loads(line)
            except Exception:
                continue
            message = str(entry.get("MESSAGE", ""))
            if not message:
                continue
            privilege_match = any(pattern.search(message) for pattern in PRIVILEGE_PATTERNS)
            auth_match = any(pattern.search(message) for pattern in AUTH_PATTERNS)
            support_match = any(pattern.search(message) for pattern in AUTH_SUPPORT_PATTERNS)
            if not privilege_match and not auth_match and not support_match:
                continue
            address, port, username = self.authentication_identity(message)
            records.append({
                "category": "privilege" if privilege_match else "authentication",
                "unit": str(entry.get("_SYSTEMD_UNIT", entry.get("SYSLOG_IDENTIFIER", "journal"))),
                "message": message,
                "time": self.journal_timestamp(entry),
                "address": address,
                "port": port,
                "username": username,
                "primary": bool(privilege_match or auth_match),
            })

        groups = self.correlate_authentication_records(records)
        now = datetime.now(timezone.utc)
        for group in groups:
            if (now - group["lastTime"]).total_seconds() < 2:
                continue
            self.record_authentication_incident(group)

        self.auth_failures = sum(1 for group in groups if group["category"] == "authentication")
        self.privilege_failures = sum(1 for group in groups if group["category"] == "privilege")

    @staticmethod
    def listener_process_id(process_value: str) -> int:
        match = SOCKET_PID_PATTERN.search(str(process_value))
        try:
            return int(match.group(1)) if match else 0
        except (TypeError, ValueError):
            return 0

    @staticmethod
    def listener_purpose(process_name: str, port: str) -> tuple[str, str]:
        name = str(process_name or "").lower()
        known = {
            "sshd": ("SSH Remote Access", "Secure remote command-line access to this NeutronOS device."),
            "tailscaled": ("Tailscale Private Network", "Encrypted peer-to-peer connectivity for trusted Tailscale devices."),
            "jellyfin": ("Jellyfin Media Server", "Serves the local NeutronOS media library to approved clients."),
            "qbittorrent-nox": ("qBittorrent", "qBittorrent networking or its local management interface."),
            "docker-proxy": ("Docker Published Service", "A Docker container has published this port on the host."),
            "dockerd": ("Docker Engine", "Docker container networking or local engine communication."),
            "python3": ("NeutronOS Service", "A Python-backed NeutronOS or local service is listening on this port."),
            "neutronshell": ("NeutronOS Shell", "A NeutronOS shell component is exposing a local service endpoint."),
        }
        if name in known:
            return known[name]
        if str(port) == "22":
            return "SSH Remote Access", "Secure remote shell access. Verify that SSH exposure is intentional."
        return (process_name or "Unknown Service", "A local process is accepting network connections on this port.")

    @staticmethod
    def process_runtime(pid: int) -> tuple[int, str, str]:
        if pid <= 0:
            return 0, "", ""
        try:
            stat_fields = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace").split()
            start_ticks = int(stat_fields[21])
            hz = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
            uptime = float(Path("/proc/uptime").read_text().split()[0])
            elapsed = max(0, int(uptime - (start_ticks / hz)))
            started = datetime.now(timezone.utc) - timedelta(seconds=elapsed)
            uid = os.stat(f"/proc/{pid}").st_uid
            try:
                username = pwd.getpwuid(uid).pw_name
            except KeyError:
                username = str(uid)
            return elapsed, started.isoformat(timespec="seconds").replace("+00:00", "Z"), username
        except Exception:
            return 0, "", ""

    def service_status(self, unit: str, *, command: str = "") -> dict[str, Any]:
        active = subprocess.run(["systemctl", "is-active", "--quiet", unit], check=False).returncode == 0
        enabled = subprocess.run(["systemctl", "is-enabled", "--quiet", unit], check=False).returncode == 0
        result: dict[str, Any] = {"unit": unit, "active": active, "enabled": enabled}
        if command == "tailscale":
            result["ip"] = run(["tailscale", "ip", "-4"], timeout=3).strip() if shutil.which("tailscale") else ""
            result["status"] = "Connected" if active and bool(result["ip"]) else ("Running" if active else "Off")
        elif command == "ssh":
            result["status"] = "On" if active else "Off"
            result["listeners"] = sum(1 for item in self.listening_ports if str(item.get("port", "")) == "22" or "ssh" in str(item.get("processName", "")).lower())
        return result

    def set_service_enabled(self, unit: str, enabled: bool) -> bool:
        verb = "enable" if enabled else "disable"
        args = ["systemctl", verb, "--now", unit]
        return subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode == 0

    def recent_audit_entries(self, limit: int = 25) -> list[dict[str, Any]]:
        if not self.audit_path.exists():
            return []
        try:
            lines = self.audit_path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        entries: list[dict[str, Any]] = []
        for raw in reversed(lines[-max(limit * 4, limit):]):
            try:
                record = json.loads(raw)
            except Exception:
                continue
            if not isinstance(record, dict):
                continue
            action = str(record.get("action", ""))
            if action == "ipc_request_accepted" and str(record.get("details", {}).get("operation", "")) == "security.snapshot":
                continue
            entries.append({
                "id": str(record.get("id", "")),
                "timestamp": str(record.get("timestamp", "")),
                "action": action,
                "details": record.get("details", {}) if isinstance(record.get("details", {}), dict) else {},
                "hash": str(record.get("hash", "")),
            })
            if len(entries) >= limit:
                break
        return entries

    def installed_apps(self) -> list[dict[str, Any]]:
        apps: list[dict[str, Any]] = []
        root = self.project_root / "qml" / "apps"
        if not root.is_dir():
            return apps
        for manifest in sorted(root.glob("*/app.json")):
            try:
                data = json.loads(manifest.read_text(encoding="utf-8"))
            except Exception:
                continue
            if not isinstance(data, dict):
                continue
            permissions = data.get("permissions", [])
            if not isinstance(permissions, list):
                permissions = []
            apps.append({
                "id": str(data.get("id", manifest.parent.name)),
                "name": str(data.get("name", manifest.parent.name)),
                "description": str(data.get("description", "")),
                "category": str(data.get("category", "App")),
                "version": str(data.get("version", "")),
                "permissions": [str(value) for value in permissions],
                "hidden": bool(data.get("hidden", False)),
                "developerOnly": bool(data.get("developerOnly", False)),
            })
        return apps

    def rejected_activity(self) -> list[dict[str, Any]]:
        records: list[dict[str, Any]] = []
        for item in self.bans.values():
            records.append({
                "id": "ban:" + str(item.get("address", item.get("id", ""))),
                "type": "banned-source", "title": "Blocked network source",
                "subject": str(item.get("address", "Unknown address")),
                "reason": str(item.get("reason", "Blocked by network policy")),
                "timestamp": str(item.get("createdAt", item.get("bannedAt", ""))),
                "state": "BLOCKED", "address": str(item.get("address", "")),
            })
        for device in self.peripherals:
            if str(device.get("trustState", "")).lower() != "blocked":
                continue
            records.append({
                "id": "peripheral:" + str(device.get("deviceId", "")),
                "type": "blocked-peripheral", "title": "Blocked peripheral",
                "subject": f"{device.get('manufacturer', 'Unknown')} {device.get('product', 'USB Device')}",
                "reason": "Device is blocked by the peripheral trust policy.",
                "timestamp": "", "state": "BLOCKED", "deviceId": str(device.get("deviceId", "")),
            })
        for item in self.quarantined_items:
            records.append({
                "id": "quarantine:" + str(item.get("id", "")),
                "type": "quarantined-item", "title": "Quarantined item",
                "subject": str(item.get("path", item.get("name", "Quarantined item"))),
                "reason": str(item.get("reason", item.get("signature", "Isolated by malware protection"))),
                "timestamp": str(item.get("quarantinedAt", item.get("detectedAt", ""))),
                "state": "QUARANTINED",
            })
        for event in self.events:
            text = " ".join(str(event.get(k, "")) for k in ("title", "message", "actionTaken", "recommendedAction")).lower()
            if not event.get("flagged") and not any(word in text for word in ("blocked", "rejected", "denied", "quarantined", "prevented")):
                continue
            records.append({
                "id": "event:" + str(event.get("id", "")),
                "type": "flagged-event" if event.get("flagged") else "rejected-event",
                "title": str(event.get("title", "Security event")),
                "subject": str(event.get("sourceAddress", event.get("processName", event.get("source", "Security event")))),
                "reason": str(event.get("message", event.get("reason", "Security policy action"))),
                "timestamp": str(event.get("timestamp", "")),
                "state": "FLAGGED" if event.get("flagged") else "REJECTED",
                "eventId": str(event.get("id", "")),
            })
        return records[:250]

    def vault_combo_state(self) -> dict[str, Any]:
        try:
            value = json.loads(self.vault_combo_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                return value
        except Exception:
            pass
        return {"mode": "unset", "configured": False, "tokenCount": 0}

    @staticmethod
    def normalize_combo(value: str) -> str:
        return " ".join(token.strip().upper() for token in str(value).split() if token.strip())

    def set_vault_combo_mode(self, mode: str) -> bool:
        if mode not in {"login", "unset"}:
            return False
        atomic_json(self.vault_combo_path, {"schema": 1, "mode": mode, "configured": mode == "login", "tokenCount": 0}, 0o600)
        self.append_audit("vault_combo_mode_changed", {"mode": mode})
        return True

    def set_vault_combo(self, combo: str) -> bool:
        normalized = self.normalize_combo(combo)
        tokens = normalized.split()
        if len(tokens) < 4 or len(tokens) > 15:
            return False
        salt = secrets.token_bytes(16)
        verifier = hashlib.scrypt(normalized.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
        atomic_json(self.vault_combo_path, {
            "schema": 1, "mode": "custom", "configured": True,
            "salt": self.b64e(salt), "verifier": self.b64e(verifier), "tokenCount": len(tokens),
        }, 0o600)
        self.append_audit("vault_combo_configured", {"tokenCount": len(tokens)})
        return True

    def verify_vault_combo(self, combo: str) -> bool:
        state = self.vault_combo_state()
        if state.get("mode") != "custom":
            return False
        try:
            salt = self.b64d(str(state.get("salt", "")))
            expected = self.b64d(str(state.get("verifier", "")))
            actual = hashlib.scrypt(self.normalize_combo(combo).encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
            return hmac.compare_digest(actual, expected)
        except Exception:
            return False

    @staticmethod
    def canonical_login_combo(value: str) -> str:
        """Canonicalize a login combo exactly like SecurityManager's token rules."""
        text = str(value or "").strip().upper()
        if not text:
            return ""
        text = re.sub(r"[\[\]\(\)\{\}]", " ", text)
        aliases = (
            "LEFTSTICKCLICK", "RIGHTSTICKCLICK", "BUTTONTRIANGLE", "BUTTONSQUARE",
            "LEFTTRIGGER", "RIGHTTRIGGER", "LEFTBUMPER", "RIGHTBUMPER",
            "DPADDOWN", "DPADRIGHT", "DPADLEFT", "DPADUP", "TRIANGLE",
            "SECONDARY", "CONTEXT", "PRIMARY", "CANCEL", "CIRCLE", "SQUARE",
            "CROSS", "LEFTSTICK", "RIGHTSTICK", "BUTTONY", "BUTTONX", "BUTTONO",
            "DOWN", "RIGHT", "LEFT", "UP", "L1", "R1", "L2", "R2", "L3", "R3",
            "X", "O", "U", "D", "L", "R", "A", "B", "Y",
        )
        if re.search(r"[\s,;|>:/]", text):
            raw = [part for part in re.split(r"[\s,;|>:/]+", text) if part]
        else:
            raw = []
            remaining = text
            while remaining:
                matched = next((alias for alias in aliases if remaining.startswith(alias)), "")
                if not matched:
                    return ""
                raw.append(matched)
                remaining = remaining[len(matched):]
        if not raw or len(raw) > 15:
            return ""
        mapping = {
            "U": "UP", "D": "DOWN", "L": "LEFT", "R": "RIGHT",
            "UP": "UP", "DPADUP": "UP", "DOWN": "DOWN", "DPADDOWN": "DOWN",
            "LEFT": "LEFT", "DPADLEFT": "LEFT", "RIGHT": "RIGHT", "DPADRIGHT": "RIGHT",
            "X": "X", "A": "X", "CROSS": "X", "PRIMARY": "X", "BUTTONX": "X",
            "O": "O", "B": "O", "CIRCLE": "O", "CANCEL": "O", "BUTTONO": "O",
            "SQUARE": "SQUARE", "SECONDARY": "SQUARE", "BUTTONSQUARE": "SQUARE",
            "TRIANGLE": "TRIANGLE", "Y": "TRIANGLE", "CONTEXT": "TRIANGLE",
            "BUTTONY": "TRIANGLE", "BUTTONTRIANGLE": "TRIANGLE",
            "L1": "L1", "LEFTBUMPER": "L1", "R1": "R1", "RIGHTBUMPER": "R1",
            "L2": "L2", "LEFTTRIGGER": "L2", "R2": "R2", "RIGHTTRIGGER": "R2",
            "L3": "L3", "LEFTSTICK": "L3", "LEFTSTICKCLICK": "L3",
            "R3": "R3", "RIGHTSTICK": "R3", "RIGHTSTICKCLICK": "R3",
        }
        canonical = []
        for item in raw:
            key = re.sub(r"[\s_\-]", "", item.upper())
            token = mapping.get(key, "")
            if not token:
                return ""
            canonical.append(token)
        return "|".join(canonical)

    @staticmethod
    def _libsodium_argon_verify(secret: str, encoded: str) -> bool:
        if not secret or not encoded.startswith("$argon2"):
            return False
        try:
            library_name = ctypes.util.find_library("sodium") or "libsodium.so.23"
            sodium = ctypes.CDLL(library_name)
            sodium.sodium_init.restype = ctypes.c_int
            if sodium.sodium_init() < 0:
                return False
            verify = sodium.crypto_pwhash_str_verify
            verify.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_ulonglong]
            verify.restype = ctypes.c_int
            secret_bytes = secret.encode("utf-8")
            return verify(encoded.encode("utf-8"), secret_bytes, len(secret_bytes)) == 0
        except Exception:
            return False

    def verify_login_combo_server(self, username: str, combo: str) -> bool:
        username = str(username or "").strip().lower()
        if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
            return False
        record_path = Path("/var/lib/neutronos/security/users") / username / "combo.json"
        try:
            st = record_path.stat(follow_symlinks=False)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != 0 or (st.st_mode & 0o077):
                return False
            record = json.loads(record_path.read_text(encoding="utf-8"))
            if not isinstance(record, dict):
                return False
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            return False
        canonical_combo = self.canonical_login_combo(combo)
        token_count = int(record.get("tokenCount", record.get("comboLength", 0)) or 0)
        tokens = canonical_combo.split("|") if canonical_combo else []
        if token_count < 4 or token_count > 15 or len(tokens) < token_count:
            return False
        # SecurityManager verifies the final configured window from the rolling
        # controller buffer.  Mirror that exact behavior at the root boundary.
        canonical_combo = "|".join(tokens[-token_count:])
        kdf = str(record.get("kdf", "")).lower()
        if "argon" in kdf:
            encoded = str(record.get("hash", ""))
            if self._libsodium_argon_verify(canonical_combo, encoded):
                return True
            if int(record.get("version", 2) or 2) < 3:
                legacy = "|".join({"UP": "U", "DOWN": "D", "LEFT": "L", "RIGHT": "R"}.get(t, t) for t in canonical_combo.split("|"))
                return self._libsodium_argon_verify(legacy, encoded)
            return False
        if "pbkdf2" in kdf:
            try:
                iterations = int(record.get("iterations", 0))
                salt = self.b64d(str(record.get("salt", "")))
                expected_text = str(record.get("hash", record.get("digest", "")))
                expected = self.b64d(expected_text)
                if iterations < 100000 or iterations > 5000000 or len(salt) < 16 or not expected:
                    return False
                actual = hashlib.pbkdf2_hmac("sha256", canonical_combo.encode("utf-8"), salt, iterations, dklen=len(expected))
                return hmac.compare_digest(actual, expected)
            except Exception:
                return False
        return False

    def vault_factor_state(self) -> dict[str, Any]:
        try:
            value = json.loads(self.vault_factor_state_path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}

    def vault_factor_allowed(self, principal: str) -> tuple[bool, int]:
        state = self.vault_factor_state()
        row = state.get(principal, {}) if isinstance(state.get(principal, {}), dict) else {}
        locked_until = float(row.get("lockedUntil", 0.0) or 0.0)
        remaining = max(0, int(locked_until - time.time()))
        return remaining == 0, remaining

    def record_vault_factor_result(self, principal: str, success: bool) -> None:
        state = self.vault_factor_state()
        row = state.get(principal, {}) if isinstance(state.get(principal, {}), dict) else {}
        if success:
            state.pop(principal, None)
        else:
            now = time.time()
            window_started = float(row.get("windowStarted", now) or now)
            failures = int(row.get("failures", 0) or 0)
            if now - window_started > 300:
                failures = 0
                window_started = now
            failures += 1
            lock_seconds = 0
            if failures >= 5:
                lock_seconds = min(300, 30 * (2 ** min(3, failures - 5)))
            state[principal] = {
                "failures": failures,
                "windowStarted": window_started,
                "lockedUntil": now + lock_seconds if lock_seconds else 0,
            }
        atomic_json(self.vault_factor_state_path, state, 0o600)

    @staticmethod
    def listener_process_name(process_value: str) -> str:
        match = SOCKET_PROCESS_PATTERN.search(str(process_value))
        return match.group(1) if match else ""

    def listener_identity(self, item: dict[str, Any]) -> str:
        protocol = str(item.get("protocol", ""))
        port = str(item.get("port", ""))
        process_name = str(item.get("processName", "")) or self.listener_process_name(str(item.get("process", "")))
        return f"{protocol}:{port}:{process_name or 'unknown'}"

    @staticmethod
    def expected_listener(item: dict[str, Any]) -> tuple[bool, str]:
        process_name = str(item.get("processName", ""))
        protocol = str(item.get("protocol", "")).lower()
        if process_name == "tailscaled" and protocol == "udp":
            return True, "Expected Tailscale peer-to-peer UDP transport listener"
        return False, ""

    def scan_ports(self) -> None:
        output = run(["ss", "-H", "-lntup"], timeout=8)
        ports: list[dict[str, Any]] = []
        for line in output.splitlines():
            fields = line.split()
            if len(fields) < 5:
                continue
            protocol = fields[0].lower()
            local = fields[4]
            address, _, port = local.rpartition(":")
            process_value = " ".join(fields[6:])[:300] if len(fields) > 6 else ""
            process_name = self.listener_process_name(process_value)
            pid = self.listener_process_id(process_value)
            elapsed, started_at, process_user = self.process_runtime(pid)
            friendly_name, purpose = self.listener_purpose(process_name, port)
            item = {
                "protocol": protocol,
                "address": address.strip("[]") or "*",
                "port": port,
                "scope": "external" if address in {"0.0.0.0", "*", "::"} else "local",
                "process": process_value,
                "processName": process_name,
                "pid": pid,
                "processUser": process_user,
                "runningSeconds": elapsed,
                "startedAt": started_at,
                "friendlyName": friendly_name,
                "purpose": purpose,
            }
            expected, reason = self.expected_listener(item)
            item["expected"] = expected
            if reason:
                item["expectedReason"] = reason
            item["suspicious"] = bool(item["scope"] == "external" and not expected and not process_name)
            item["assessment"] = (
                "Expected NeutronOS/network service" if expected else
                "Needs review: externally reachable service with unknown owner" if item["suspicious"] else
                "Observed listening service"
            )
            ports.append(item)

        ports.sort(key=lambda item: (
            str(item.get("scope")), str(item.get("protocol")),
            str(item.get("processName")), str(item.get("port"))
        ))
        current_external = {
            self.listener_identity(item): item
            for item in ports if item.get("scope") == "external"
        }
        if self.port_baseline_ready:
            for identity in sorted(set(current_external) - self.previous_external_ports):
                item = current_external[identity]
                if item.get("expected"):
                    continue
                protocol = str(item.get("protocol", ""))
                port = str(item.get("port", ""))
                process_name = str(item.get("processName", "")) or "unknown process"
                self.emit_event(
                    category="network",
                    severity=2,
                    title="New external listening port",
                    message=f"A new {protocol.upper()} listener from {process_name} is reachable on port {port}.",
                    source="socket inventory",
                    evidence=json.dumps(item, sort_keys=True),
                    confidence=95,
                    recommended_action="Confirm that the process and service are expected. Close or restrict the listener if it is unnecessary.",
                    fingerprint=stable_fingerprint("external-listener", identity),
                    extra={
                        "targetPort": port,
                        "protocol": protocol,
                        "processName": process_name,
                        "stateTransition": "closed_to_listening",
                    },
                )
        self.previous_external_ports = set(current_external)
        self.port_baseline_ready = True
        self.listening_ports = ports[:256]

    def scan_failed_services(self) -> None:
        output = run(["systemctl", "--failed", "--no-legend", "--plain"], timeout=8)
        services: list[dict[str, Any]] = []
        current_units: set[str] = set()
        lines_by_unit: dict[str, str] = {}
        for line in output.splitlines():
            fields = line.split(None, 4)
            if not fields:
                continue
            unit = fields[0]
            current_units.add(unit)
            lines_by_unit[unit] = line
            services.append({
                "unit": unit,
                "state": "failed",
                "description": fields[-1] if len(fields) > 1 else unit,
            })

        newly_failed = current_units - self.failed_service_units
        recovered = self.failed_service_units - current_units
        for unit in sorted(newly_failed):
            self.emit_event(
                category="service",
                severity=2,
                title="System service entered failed state",
                message=f"{unit} entered a failed state.",
                source="systemd",
                evidence=lines_by_unit.get(unit, unit),
                confidence=100,
                recommended_action="Review the service log before restarting or changing configuration.",
                fingerprint=stable_fingerprint("service-transition", unit, utc_now()),
                extra={"stateTransition": "healthy_to_failed", "unit": unit},
            )
        for unit in sorted(recovered):
            self.append_audit("service_recovered", {"unit": unit})

        self.failed_service_units = current_units
        self.failed_services = services[:128]

    def scan_peripherals(self) -> None:
        base = Path("/sys/bus/usb/devices")
        devices: list[dict[str, Any]] = []
        trusted = {str(value) for value in self.config.get("trustedPeripherals", [])}
        blocked = {str(value) for value in self.config.get("blockedPeripherals", [])}
        allow_once = {str(value) for value in self.config.get("allowOncePeripherals", [])}
        current_ids: set[str] = set()
        if base.exists():
            for entry in sorted(base.iterdir()):
                vendor = entry / "idVendor"
                product = entry / "idProduct"
                if not vendor.exists() or not product.exists():
                    continue
                def text(name: str) -> str:
                    try:
                        return (entry / name).read_text(encoding="utf-8", errors="ignore").strip()
                    except Exception:
                        return ""
                device = {
                    "path": entry.name,
                    "vendorId": text("idVendor"),
                    "productId": text("idProduct"),
                    "manufacturer": text("manufacturer") or "Unknown",
                    "product": text("product") or "USB Device",
                    "serial": text("serial"),
                    "authorized": text("authorized") != "0",
                }
                device_id = self.peripheral_identity(device)
                device["deviceId"] = device_id
                device["id"] = device_id
                current_ids.add(device_id)
                if device_id in blocked:
                    device["trustState"] = "blocked"
                    if self.config.get("peripheralEnforcementEnabled", False) and device["authorized"]:
                        device["authorized"] = not self.set_peripheral_authorized(entry.name, False)
                elif device_id in trusted:
                    device["trustState"] = "trusted"
                elif device_id in allow_once:
                    device["trustState"] = "allowed_once"
                else:
                    device["trustState"] = "unknown"
                devices.append(device)
                if device_id not in self.previous_peripheral_ids and device["trustState"] == "unknown":
                    self.emit_event(
                        category="peripheral",
                        severity=2,
                        title="Unknown peripheral connected",
                        message=f"{device['manufacturer']} {device['product']} is not in the trusted-device policy.",
                        source="usb",
                        evidence=json.dumps(device, sort_keys=True),
                        confidence=100,
                        recommended_action="Inspect the device, then trust, allow once, or block it from the Devices tab.",
                        fingerprint=stable_fingerprint("usb-connect", device_id, utc_now()[:13]),
                        extra={"deviceId": device_id, "vendorId": device["vendorId"], "productId": device["productId"]},
                    )
        self.previous_peripheral_ids = current_ids
        self.peripherals = devices[:128]

    def recovery_configured(self) -> bool:
        recovery = self.config.get("recovery", {})
        return isinstance(recovery, dict) and bool(recovery.get("configured", False))

    def active_event_metrics(self) -> dict[str, int]:
        now = datetime.now(timezone.utc)
        hour = now - timedelta(hours=1)
        day = now - timedelta(hours=24)
        metrics = {
            "authAttemptsHour": 0,
            "hostileSourcesHour": 0,
            "highEventsDay": 0,
            "criticalEventsDay": 0,
            "malwareActive": 0,
            "integrityChanges": len(self.integrity_changes),
            "unknownPeripherals": sum(1 for item in self.peripherals if item.get("trustState") == "unknown"),
            "activeBans": sum(1 for item in self.bans.values() if item.get("active")),
        }
        sources: set[str] = set()
        for event in self.events:
            stamp = parse_time(str(event.get("timestamp", "")))
            if stamp is None:
                stamp = now
            severity = int(event.get("severity", 1))
            if stamp >= day and severity >= 4 and not event.get("acknowledged"):
                metrics["highEventsDay"] += 1
            if stamp >= day and severity >= 5 and not event.get("acknowledged"):
                metrics["criticalEventsDay"] += 1
            if stamp >= hour and event.get("category") == "authentication":
                metrics["authAttemptsHour"] += int(event.get("attempts", 1))
                address = str(event.get("address", ""))
                if address:
                    sources.add(address)
        metrics["hostileSourcesHour"] = len(sources)
        metrics["malwareActive"] = sum(1 for item in self.malware_findings if item.get("status") == "detected")
        return metrics

    def active_threat_count(self) -> int:
        metrics = self.active_event_metrics()
        return (
            int(metrics.get("highEventsDay", 0))
            + int(metrics.get("malwareActive", 0))
            + (1 if int(metrics.get("integrityChanges", 0)) > 0 else 0)
        )

    def set_manual_normal_override(self, reason: str) -> None:
        self.response_state["manualOverride"] = {
            "level": 5,
            "setAt": utc_now(),
            "reason": reason,
            "baselineMetrics": dict(self.active_event_metrics()),
        }

    def manual_normal_override_allows_hold(self, metrics: dict[str, int]) -> bool:
        override = self.response_state.get("manualOverride")
        if not isinstance(override, dict) or int(override.get("level", 0)) != 5:
            return False
        baseline = override.get("baselineMetrics")
        if not isinstance(baseline, dict):
            return False
        watched = (
            "authAttemptsHour", "hostileSourcesHour", "highEventsDay",
            "criticalEventsDay", "malwareActive", "integrityChanges",
            "unknownPeripherals", "activeBans",
        )
        for key in watched:
            if int(metrics.get(key, 0)) > int(baseline.get(key, 0)):
                return False
        return True

    def suggested_defcon_level(self) -> tuple[int, str, dict[str, int]]:
        metrics = self.active_event_metrics()
        categories = 0
        if metrics["authAttemptsHour"] >= 5 or metrics["activeBans"] > 0:
            categories += 1
        if metrics["malwareActive"] > 0:
            categories += 1
        if metrics["integrityChanges"] > 0:
            categories += 1
        if metrics["unknownPeripherals"] >= 2:
            categories += 1

        level = 5
        reason = "Normal monitoring"
        if metrics["authAttemptsHour"] >= 5 or metrics["highEventsDay"] > 0 or metrics["malwareActive"] > 0:
            level = 4
            reason = "Heightened monitoring recommended"
        if (metrics["authAttemptsHour"] >= 15 or metrics["activeBans"] >= 2 or
                metrics["malwareActive"] >= 1 or metrics["integrityChanges"] >= 3):
            level = 3
            reason = "Confirmed hostile or system-impacting activity"
        if categories >= 2 and (metrics["criticalEventsDay"] > 0 or metrics["authAttemptsHour"] >= 25):
            level = 2
            reason = "Multiple correlated threat categories require containment review"
        return level, reason, metrics

    def record_response_transition(self, level: int, reason: str, automatic: bool) -> None:
        previous = int(self.response_state.get("currentLevel", 5))
        if previous == level and self.response_state.get("reason") == reason:
            return
        record = {
            "id": str(uuid.uuid4()),
            "timestamp": utc_now(),
            "fromLevel": previous,
            "toLevel": level,
            "reason": reason,
            "automatic": automatic,
            "containmentActive": bool(self.response_state.get("containmentActive", False)),
        }
        self.response_history.insert(0, record)
        self.response_history = self.response_history[:100]
        self.response_state.update({
            "currentLevel": level,
            "lastTransition": record["timestamp"],
            "reason": reason,
            "automatic": automatic,
        })
        self.append_audit("defcon_transition", record)
        self.save_response_and_hardening_state()

    def evaluate_response_engine(self) -> None:
        suggested, reason, metrics = self.suggested_defcon_level()
        self.response_state["suggestedLevel"] = suggested
        self.response_state["suggestedReason"] = reason
        self.response_state["metrics"] = metrics

        # A locally authorized return to DEFCON 5 is sticky for the threat
        # conditions that already existed when the operator normalized the
        # system. The response engine is released automatically only if a new
        # or worsening threat metric appears after that point. This prevents a
        # cleared incident from immediately bouncing 5 -> 3 on the next scan.
        if self.manual_normal_override_allows_hold(metrics):
            self.save_response_and_hardening_state()
            return
        if "manualOverride" in self.response_state:
            previous = self.response_state.pop("manualOverride", None)
            if isinstance(previous, dict):
                self.append_audit("manual_defcon_override_released", {
                    "setAt": str(previous.get("setAt", "")),
                    "reason": "Threat metrics worsened after manual normalization",
                    "metrics": metrics,
                })

        if not self.config.get("responseEngineEnabled", False):
            self.save_response_and_hardening_state()
            return
        if self.config.get("learningMode", True):
            self.save_response_and_hardening_state()
            return
        # Automatic action is deliberately capped at DEFCON 3 until a recovery
        # key exists. DEFCON 2 and DEFCON 1 always require an armed local action.
        automatic_level = max(int(self.config.get("automaticDefconFloor", 3)), suggested)
        current = int(self.response_state.get("currentLevel", 5))
        if automatic_level < current:
            if automatic_level <= 3:
                self.config["enforcementEnabled"] = True
                self.save_config()
            self.record_response_transition(automatic_level, reason, True)

    def set_manual_defcon(self, level: int, reason: str = "Authorized local action") -> bool:
        if level < 1 or level > 5:
            self.append_audit("request_rejected", {"action": "set_manual_defcon", "reason": "invalid level", "level": level})
            return False
        if level == 1 and not self.recovery_configured():
            self.append_audit("request_rejected", {"action": "set_manual_defcon", "reason": "recovery key required", "level": level})
            self.emit_event(
                category="response",
                severity=3,
                title="DEFCON 1 unavailable",
                message="Emergency lockdown requires an enrolled physical recovery key.",
                source="security-response",
                evidence="Patch 61E recovery enrollment is not complete.",
                confidence=100,
                recommended_action="Enroll a recovery code or USB recovery key in Patch 61E.",
                fingerprint=stable_fingerprint("defcon1-rejected", utc_now()[:13]),
            )
            return False
        if level <= 2:
            if not self.config.get("manualContainmentEnabled", True):
                return False
            if not self.enter_containment():
                return False
        elif level >= 3 and self.response_state.get("containmentActive"):
            self.leave_containment("DEFCON de-escalation")
        if level <= 3:
            self.config["enforcementEnabled"] = True
            self.config["learningMode"] = False
            self.save_config()
        if level == 5:
            self.set_manual_normal_override(reason)
        else:
            self.response_state.pop("manualOverride", None)
        self.record_response_transition(level, reason, False)
        return True

    def remote_service_units(self) -> list[str]:
        return [
            "ssh.service", "ssh.socket", "xrdp.service",
            "vncserver-x11-serviced.service", "wayvnc.service",
            "tigervncserver.service", "cockpit.socket",
        ]

    def enter_containment(self) -> bool:
        if self.response_state.get("containmentActive"):
            return True
        active_units: list[str] = []
        for unit in self.remote_service_units():
            if subprocess.run(["systemctl", "is-active", "--quiet", unit], check=False).returncode == 0:
                active_units.append(unit)
                subprocess.run(["systemctl", "stop", unit], check=False)
        nft = shutil.which("nft")
        firewall_applied = False
        if nft:
            script = """
add table inet neutronos_containment
add chain inet neutronos_containment input { type filter hook input priority -25; policy drop; }
add rule inet neutronos_containment input iifname lo accept
add rule inet neutronos_containment input ct state established,related accept
add rule inet neutronos_containment input ip protocol icmp accept
add rule inet neutronos_containment input ip6 nexthdr icmpv6 accept
"""
            subprocess.run([nft, "delete", "table", "inet", "neutronos_containment"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            result = subprocess.run([nft, "-f", "-"], input=script, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            firewall_applied = result.returncode == 0
        state = {
            "active": True,
            "enteredAt": utc_now(),
            "previouslyActiveRemoteUnits": active_units,
            "firewallApplied": firewall_applied,
        }
        atomic_json(self.containment_state_path, state, 0o600)
        self.response_state["containmentActive"] = True
        self.append_audit("emergency_containment_entered", state)
        self.save_response_and_hardening_state()
        return True

    def leave_containment(self, reason: str) -> None:
        state: dict[str, Any] = {}
        try:
            value = json.loads(self.containment_state_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                state = value
        except Exception:
            pass
        nft = shutil.which("nft")
        if nft:
            subprocess.run([nft, "delete", "table", "inet", "neutronos_containment"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        for unit in state.get("previouslyActiveRemoteUnits", []):
            if isinstance(unit, str) and unit in self.remote_service_units():
                subprocess.run(["systemctl", "start", unit], check=False)
        try:
            self.containment_state_path.unlink()
        except FileNotFoundError:
            pass
        self.response_state["containmentActive"] = False
        self.append_audit("emergency_containment_released", {"reason": reason})
        self.save_response_and_hardening_state()

    def hardening_profile_definition(self, profile: str) -> dict[str, Any] | None:
        profiles: dict[str, dict[str, Any]] = {
            "balanced": {
                "name": "Balanced",
                "description": "Safe kernel protections, firewall readiness and Security service self-protection.",
                "changes": [
                    "Restrict kernel pointer and log exposure",
                    "Enable protected links, FIFOs and regular files",
                    "Enable ptrace restrictions",
                    "Keep current SSH authentication method",
                ],
            },
            "strict": {
                "name": "Strict",
                "description": "Balanced protections plus root-login denial and SSH key-only authentication when a key is enrolled.",
                "changes": [
                    "Apply Balanced profile",
                    "Disable direct SSH root login",
                    "Limit SSH authentication attempts",
                    "Require SSH keys only when authorized_keys exists",
                    "Protect Linux boot configuration permissions",
                ],
            },
            "fortified": {
                "name": "Fortified",
                "description": "Strict profile plus remote-forwarding restrictions and tighter session limits.",
                "changes": [
                    "Apply Strict profile",
                    "Disable SSH TCP and agent forwarding",
                    "Disable SSH X11 forwarding",
                    "Reduce SSH unauthenticated connection capacity",
                    "Protect boot configuration permissions",
                ],
            },
        }
        return profiles.get(profile)

    def hardening_profiles(self) -> list[dict[str, Any]]:
        result = []
        active = str(self.hardening_state.get("activeProfile", "none"))
        for key in ("balanced", "strict", "fortified"):
            record = dict(self.hardening_profile_definition(key) or {})
            record["id"] = key
            record["active"] = key == active
            record["requiresSshKey"] = key in ("strict", "fortified")
            result.append(record)
        return result

    def preview_hardening(self, profile: str) -> bool:
        definition = self.hardening_profile_definition(profile)
        if definition is None:
            return False
        has_key = (self.owner_home() / ".ssh" / "authorized_keys").is_file()
        preview = dict(definition)
        preview.update({
            "id": profile,
            "generatedAt": utc_now(),
            "canApply": profile == "balanced" or has_key,
            "blockingReason": "" if (profile == "balanced" or has_key) else "Enroll at least one SSH public key before applying this profile.",
            "rollbackAvailable": bool(self.hardening_state.get("rollbackAvailable", False)),
        })
        self.hardening_state["lastPreview"] = preview
        self.append_audit("hardening_previewed", {"profile": profile, "canApply": preview["canApply"]})
        self.save_response_and_hardening_state()
        return True

    def backup_hardening_target(self, target: Path) -> None:
        key = stable_fingerprint(str(target))[:16]
        record_path = self.hardening_backup_dir / f"{key}.json"
        if record_path.exists():
            return
        record: dict[str, Any] = {"path": str(target), "existed": target.exists()}
        if target.exists() and target.is_file():
            stat_result = target.stat()
            record["mode"] = stat_result.st_mode & 0o7777
            record["uid"] = stat_result.st_uid
            record["gid"] = stat_result.st_gid
            record["content"] = target.read_text(encoding="utf-8", errors="replace")
        atomic_json(record_path, record, 0o600)

    def apply_hardening(self, profile: str) -> bool:
        definition = self.hardening_profile_definition(profile)
        if definition is None:
            return False
        has_key = (self.owner_home() / ".ssh" / "authorized_keys").is_file()
        if profile in ("strict", "fortified") and not has_key:
            self.hardening_state["lastResult"] = "Refused: no SSH public key is enrolled."
            self.preview_hardening(profile)
            return False
        sysctl_path = Path("/etc/sysctl.d/99-neutronos-security.conf")
        ssh_path = Path("/etc/ssh/sshd_config.d/99-neutronos-security.conf")
        targets = [sysctl_path, ssh_path]
        boot_targets = [Path("/etc/default/grub"), Path("/boot/grub/grub.cfg")]
        for target in targets + boot_targets:
            self.backup_hardening_target(target)
        sysctl_content = """# Managed by NeutronOS Security Patch 61D
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
"""
        sysctl_path.parent.mkdir(parents=True, exist_ok=True)
        sysctl_path.write_text(sysctl_content, encoding="utf-8")
        os.chmod(sysctl_path, 0o600)
        ssh_content = "# Managed by NeutronOS Security Patch 61D\nPermitRootLogin no\nMaxAuthTries 3\nLoginGraceTime 30\n"
        if profile in ("strict", "fortified"):
            ssh_content += "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\n"
        if profile == "fortified":
            ssh_content += "AllowTcpForwarding no\nAllowAgentForwarding no\nX11Forwarding no\nMaxStartups 3:30:10\n"
        ssh_path.parent.mkdir(parents=True, exist_ok=True)
        ssh_path.write_text(ssh_content, encoding="utf-8")
        os.chmod(ssh_path, 0o600)
        sshd = shutil.which("sshd") or "/usr/sbin/sshd"
        if not Path(sshd).exists():
            self.hardening_state["lastResult"] = "Refused: OpenSSH server is not installed."
            self.rollback_hardening("OpenSSH validation unavailable")
            return False
        validation = subprocess.run([sshd, "-t"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if validation.returncode != 0:
            self.rollback_hardening("SSH configuration validation failed")
            return False
        subprocess.run(["sysctl", "--system"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        subprocess.run(["systemctl", "reload", "ssh.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if profile in ("strict", "fortified"):
            for target in boot_targets:
                if target.exists() and target.is_file():
                    try:
                        os.chown(target, 0, 0)
                        os.chmod(target, 0o600)
                    except OSError:
                        pass
        self.hardening_state.update({
            "activeProfile": profile,
            "appliedAt": utc_now(),
            "rollbackAvailable": True,
            "lastResult": f"{definition['name']} hardening applied successfully.",
        })
        self.config["activeHardeningProfile"] = profile
        self.config["hardeningRollbackAvailable"] = True
        self.save_config()
        self.append_audit("hardening_applied", {"profile": profile, "changes": definition["changes"]})
        self.save_response_and_hardening_state()
        return True

    def rollback_hardening(self, reason: str = "Authorized rollback") -> bool:
        records = list(self.hardening_backup_dir.glob("*.json"))
        if not records:
            self.hardening_state["lastResult"] = "No hardening backup is available."
            self.save_response_and_hardening_state()
            return False
        restored = []
        for record_path in records:
            try:
                record = json.loads(record_path.read_text(encoding="utf-8"))
                target = Path(str(record.get("path", "")))
                if not str(target).startswith(("/etc/", "/boot/")):
                    continue
                if record.get("existed"):
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(str(record.get("content", "")), encoding="utf-8")
                    os.chown(target, int(record.get("uid", 0)), int(record.get("gid", 0)))
                    os.chmod(target, int(record.get("mode", 0o644)))
                else:
                    try:
                        target.unlink()
                    except FileNotFoundError:
                        pass
                restored.append(str(target))
            except Exception as exc:
                self.append_audit("hardening_rollback_error", {"file": record_path.name, "error": str(exc)})
        subprocess.run(["sysctl", "--system"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        sshd = shutil.which("sshd") or "/usr/sbin/sshd"
        if Path(sshd).exists() and subprocess.run([sshd, "-t"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False).returncode == 0:
            subprocess.run(["systemctl", "reload", "ssh.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        self.hardening_state.update({
            "activeProfile": "none",
            "appliedAt": "",
            "rollbackAvailable": False,
            "lastResult": "Hardening changes rolled back.",
        })
        self.config["activeHardeningProfile"] = "none"
        self.config["hardeningRollbackAvailable"] = False
        self.save_config()
        self.append_audit("hardening_rolled_back", {"reason": reason, "restored": restored})
        for record_path in records:
            try:
                record_path.unlink()
            except OSError:
                pass
        self.save_response_and_hardening_state()
        return True

    def b64e(self, value: bytes) -> str:
        return base64.urlsafe_b64encode(value).decode("ascii")

    def b64d(self, value: str) -> bytes:
        return base64.urlsafe_b64decode(value.encode("ascii"))

    def derive_secret_verifier(self, secret: str, salt: bytes) -> bytes:
        return hashlib.scrypt(secret.encode("utf-8"), salt=salt, n=2**15, r=8, p=1, dklen=32)

    def load_recovery_state(self) -> None:
        try:
            value = json.loads(self.recovery_path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                self.recovery.update(value)
        except Exception:
            pass
        self.config["recovery"] = {
            "configured": bool(self.recovery.get("configured", False)),
            "primaryMethod": str(self.recovery.get("primaryMethod", "none")),
            "keyId": str(self.recovery.get("keyId", "")),
            "createdAt": str(self.recovery.get("createdAt", "")),
        }
        self.save_config()
        self.scan_recovery_usb_candidates()

    def save_recovery_state(self) -> None:
        atomic_json(self.recovery_path, self.recovery, 0o600)
        self.config["recovery"] = {
            "configured": bool(self.recovery.get("configured", False)),
            "primaryMethod": str(self.recovery.get("primaryMethod", "none")),
            "keyId": str(self.recovery.get("keyId", "")),
            "createdAt": str(self.recovery.get("createdAt", "")),
        }
        self.save_config()

    def recovery_public_state(self) -> dict[str, Any]:
        method = str(self.recovery.get("primaryMethod", "none"))
        result = {
            "configured": bool(self.recovery.get("configured", False)),
            "primaryMethod": method,
            "keyId": str(self.recovery.get("keyId", "")),
            "createdAt": str(self.recovery.get("createdAt", "")),
            "lastVerifiedAt": str(self.recovery.get("lastVerifiedAt", "")),
        }
        if method == "usb":
            device = self.recovery.get("device", {}) if isinstance(self.recovery.get("device"), dict) else {}
            result["device"] = {
                "path": str(device.get("path", "")),
                "label": str(device.get("label", "")),
                "uuid": str(device.get("uuid", "")),
                "partuuid": str(device.get("partuuid", "")),
                "serial": str(device.get("serial", "")),
            }
        return result

    def recovery_rate_limited(self) -> bool:
        until = parse_time(str(self.config.get("recoveryLockUntil", "")))
        return until is not None and until > datetime.now(timezone.utc)

    def record_recovery_failure(self, reason: str) -> None:
        count = int(self.config.get("recoveryFailedAttempts", 0)) + 1
        self.config["recoveryFailedAttempts"] = count
        delay = min(300, 2 ** min(count, 8))
        self.config["recoveryLockUntil"] = (datetime.now(timezone.utc) + timedelta(seconds=delay)).isoformat().replace("+00:00", "Z")
        self.save_config()
        self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": reason, "retryAfterSeconds": delay}
        self.append_audit("recovery_verification_failed", {"reason": reason, "failureCount": count, "retryAfterSeconds": delay})

    def record_recovery_success(self, method: str) -> None:
        self.config["recoveryFailedAttempts"] = 0
        self.config["recoveryLockUntil"] = ""
        self.recovery["lastVerifiedAt"] = utc_now()
        self.save_recovery_state()
        self.last_recovery_verification = {"success": True, "timestamp": utc_now(), "message": f"{method.upper()} recovery key verified"}
        self.append_audit("recovery_verified", {"method": method, "keyId": self.recovery.get("keyId", "")})
        if int(self.response_state.get("currentLevel", 5)) == 1 or self.response_state.get("containmentActive"):
            self.leave_containment("Authorized physical recovery")
            self.record_response_transition(5, "Authorized physical recovery", False)

    def enroll_recovery_code(self, code: str) -> bool:
        normalized = "".join(code.strip().split())
        if len(normalized) < 40:
            self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": "Recovery code is too short"}
            return False
        salt = secrets.token_bytes(16)
        verifier = self.derive_secret_verifier(normalized, salt)
        self.recovery = {
            "configured": True,
            "primaryMethod": "code",
            "createdAt": utc_now(),
            "keyId": secrets.token_hex(8),
            "salt": self.b64e(salt),
            "verifier": self.b64e(verifier),
            "lastVerifiedAt": "",
        }
        self.save_recovery_state()
        self.append_audit("recovery_enrolled", {"method": "code", "keyId": self.recovery["keyId"]})
        return True

    def verify_recovery_code(self, code: str) -> bool:
        if self.recovery_rate_limited():
            self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": "Recovery entry temporarily rate limited"}
            return False
        if self.recovery.get("primaryMethod") != "code":
            self.record_recovery_failure("Recovery code is not the enrolled method")
            return False
        try:
            normalized = "".join(code.strip().split())
            actual = self.derive_secret_verifier(normalized, self.b64d(str(self.recovery.get("salt", ""))))
            expected = self.b64d(str(self.recovery.get("verifier", "")))
        except Exception:
            self.record_recovery_failure("Recovery configuration is unreadable")
            return False
        if not hmac.compare_digest(actual, expected):
            self.record_recovery_failure("Recovery code rejected")
            return False
        self.record_recovery_success("code")
        return True

    def flatten_block_devices(self, nodes: list[dict[str, Any]], parent: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for node in nodes:
            inherited = dict(parent or {})
            for key in ("serial", "tran", "vendor", "model", "rm"):
                if node.get(key) not in (None, ""):
                    inherited[key] = node.get(key)
            mounts = node.get("mountpoints") or []
            if isinstance(mounts, str):
                mounts = [mounts]
            for mount in mounts:
                if mount and str(node.get("type", "")) in ("part", "crypt"):
                    result.append({
                        "path": str(node.get("path", "")),
                        "name": str(node.get("name", "")),
                        "mountpoint": str(mount),
                        "fstype": str(node.get("fstype", "")),
                        "label": str(node.get("label", "") or node.get("name", "USB Storage")),
                        "uuid": str(node.get("uuid", "")),
                        "partuuid": str(node.get("partuuid", "")),
                        "serial": str(inherited.get("serial", "")),
                        "removable": bool(inherited.get("rm", False)),
                        "transport": str(inherited.get("tran", "")),
                        "vendor": str(inherited.get("vendor", "")),
                        "model": str(inherited.get("model", "")),
                    })
            children = node.get("children") if isinstance(node.get("children"), list) else []
            result.extend(self.flatten_block_devices(children, inherited))
        return result

    def scan_recovery_usb_candidates(self) -> None:
        output = run(["lsblk", "-J", "-o", "NAME,PATH,TYPE,FSTYPE,LABEL,UUID,PARTUUID,SERIAL,MOUNTPOINTS,RM,RO,TRAN,VENDOR,MODEL"], timeout=8)
        try:
            root = json.loads(output)
            nodes = root.get("blockdevices", []) if isinstance(root, dict) else []
            candidates = self.flatten_block_devices(nodes if isinstance(nodes, list) else [])
        except Exception:
            candidates = []
        safe: list[dict[str, Any]] = []
        for item in candidates:
            mount = Path(str(item.get("mountpoint", "")))
            if not mount.is_dir():
                continue
            # Never offer the active root or boot filesystem as a removable key.
            if str(mount) in ("/", "/boot", "/boot/firmware"):
                continue
            if not item.get("removable") and str(item.get("transport", "")).lower() != "usb":
                continue
            item["id"] = stable_fingerprint(str(item.get("serial", "")), str(item.get("uuid", "")), str(item.get("partuuid", "")), str(item.get("path", "")))
            safe.append(item)
        self.recovery_usb_candidates = safe

    def recovery_signing_key(self) -> bytes:
        if self.recovery_signing_key_path.exists():
            value = self.recovery_signing_key_path.read_bytes()
            if len(value) >= 32:
                return value
        value = secrets.token_bytes(32)
        self.recovery_signing_key_path.write_bytes(value)
        os.chmod(self.recovery_signing_key_path, 0o600)
        return value

    def enroll_usb_recovery(self, selected_path: str) -> bool:
        self.scan_recovery_usb_candidates()
        candidate = next((item for item in self.recovery_usb_candidates if item.get("path") == selected_path or item.get("id") == selected_path), None)
        if candidate is None:
            self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": "Selected USB storage is not mounted or is not removable"}
            return False
        mount = Path(str(candidate.get("mountpoint", ""))).resolve()
        if not mount.is_dir():
            return False
        token = secrets.token_urlsafe(48)
        salt = secrets.token_bytes(16)
        key_id = secrets.token_hex(8)
        identity = {
            "path": str(candidate.get("path", "")),
            "label": str(candidate.get("label", "")),
            "uuid": str(candidate.get("uuid", "")),
            "partuuid": str(candidate.get("partuuid", "")),
            "serial": str(candidate.get("serial", "")),
        }
        payload = {"schema": 1, "product": "NeutronOS", "keyId": key_id, "createdAt": utc_now(), "device": identity, "token": token}
        signature = hmac.new(self.recovery_signing_key(), canonical(payload), hashlib.sha256).hexdigest()
        document = dict(payload)
        document["signature"] = signature
        target = mount / ".neutronos-recovery-key.json"
        try:
            target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
            try:
                os.chmod(target, 0o600)
            except OSError:
                pass
        except Exception as exc:
            self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": f"Could not write USB recovery key: {exc}"}
            return False
        self.recovery = {
            "configured": True,
            "primaryMethod": "usb",
            "createdAt": utc_now(),
            "keyId": key_id,
            "salt": self.b64e(salt),
            "verifier": self.b64e(self.derive_secret_verifier(token, salt)),
            "device": identity,
            "fileName": target.name,
            "lastVerifiedAt": "",
        }
        self.save_recovery_state()
        self.append_audit("recovery_enrolled", {"method": "usb", "keyId": key_id, "device": identity})
        return True

    def candidate_matches_enrolled_usb(self, candidate: dict[str, Any]) -> bool:
        enrolled = self.recovery.get("device", {}) if isinstance(self.recovery.get("device"), dict) else {}
        comparisons = []
        for field in ("serial", "uuid", "partuuid"):
            expected = str(enrolled.get(field, ""))
            if expected:
                comparisons.append(str(candidate.get(field, "")) == expected)
        return bool(comparisons) and all(comparisons)

    def verify_usb_recovery(self) -> bool:
        if self.recovery_rate_limited():
            self.last_recovery_verification = {"success": False, "timestamp": utc_now(), "message": "USB recovery temporarily rate limited"}
            return False
        if self.recovery.get("primaryMethod") != "usb":
            self.record_recovery_failure("USB is not the enrolled recovery method")
            return False
        self.scan_recovery_usb_candidates()
        candidate = next((item for item in self.recovery_usb_candidates if self.candidate_matches_enrolled_usb(item)), None)
        if candidate is None:
            self.record_recovery_failure("Enrolled USB device was not found")
            return False
        target = Path(str(candidate.get("mountpoint", ""))) / str(self.recovery.get("fileName", ".neutronos-recovery-key.json"))
        try:
            document = json.loads(target.read_text(encoding="utf-8"))
            signature = str(document.pop("signature", ""))
            expected_signature = hmac.new(self.recovery_signing_key(), canonical(document), hashlib.sha256).hexdigest()
            if not hmac.compare_digest(signature, expected_signature):
                raise ValueError("signature mismatch")
            if str(document.get("keyId", "")) != str(self.recovery.get("keyId", "")):
                raise ValueError("key identity mismatch")
            token = str(document.get("token", ""))
            actual = self.derive_secret_verifier(token, self.b64d(str(self.recovery.get("salt", ""))))
            expected = self.b64d(str(self.recovery.get("verifier", "")))
            if not hmac.compare_digest(actual, expected):
                raise ValueError("token mismatch")
        except Exception as exc:
            self.record_recovery_failure(f"USB recovery rejected: {exc}")
            return False
        self.record_recovery_success("usb")
        return True

    def clear_recovery(self) -> bool:
        previous = self.recovery_public_state()
        self.recovery = {"configured": False, "primaryMethod": "none", "createdAt": "", "keyId": ""}
        self.save_recovery_state()
        self.append_audit("recovery_removed", {"previous": previous})
        return True

    def vault_available(self) -> bool:
        return AESGCM is not None

    def vault_unlocked(self) -> bool:
        if self.vault_key is None or time.monotonic() >= self.vault_unlocked_until:
            self.vault_key = None
            self.vault_entries = []
            return False
        return True

    def vault_derive_key(self, password: str, salt: bytes) -> bytes:
        return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**15, r=8, p=1, dklen=32)

    def vault_encrypt(self, key: bytes, entries: list[dict[str, Any]], salt: bytes) -> None:
        nonce = secrets.token_bytes(12)
        plaintext = canonical({"schema": 1, "entries": entries})
        ciphertext = AESGCM(key).encrypt(nonce, plaintext, b"NeutronOS-Credential-Vault-v1")
        atomic_json(self.vault_path, {"schema": 1, "salt": self.b64e(salt), "nonce": self.b64e(nonce), "ciphertext": self.b64e(ciphertext)}, 0o600)

    def vault_master_key(self) -> bytes:
        try:
            existing = self.vault_master_key_path.read_bytes()
            if len(existing) == 32:
                return existing
        except FileNotFoundError:
            pass
        key = secrets.token_bytes(32)
        self.vault_master_key_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.vault_master_key_path.with_name(self.vault_master_key_path.name + ".tmp")
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            os.write(fd, key)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(temporary, self.vault_master_key_path)
        os.chmod(self.vault_master_key_path, 0o600)
        return key

    def vault_encrypt_controller(self, key: bytes, entries: list[dict[str, Any]]) -> None:
        nonce = secrets.token_bytes(12)
        plaintext = canonical({"schema": 2, "entries": entries})
        ciphertext = AESGCM(key).encrypt(nonce, plaintext, b"NeutronOS-Credential-Vault-v2")
        atomic_json(self.vault_path, {
            "schema": 2,
            "keyMode": "controller",
            "nonce": self.b64e(nonce),
            "ciphertext": self.b64e(ciphertext),
        }, 0o600)

    def unlock_vault_controller(self, combo: str, username: str = "") -> bool:
        if not self.vault_available():
            self.vault_last_error = "python3-cryptography is unavailable"
            return False
        combo_state = self.vault_combo_state()
        mode = str(combo_state.get("mode", "unset"))
        principal = (str(username or "").strip().lower() or "custom") + ":" + mode
        allowed, remaining = self.vault_factor_allowed(principal)
        if not allowed:
            self.vault_last_error = f"Vault controller authentication is locked for {remaining} seconds"
            self.append_audit("credential_vault_factor_rate_limited", {"mode": mode, "username": str(username or "")})
            return False
        if mode == "custom":
            factor_ok = self.verify_vault_combo(combo)
        elif mode == "login":
            factor_ok = self.verify_login_combo_server(username, combo)
        else:
            factor_ok = False
        self.record_vault_factor_result(principal, factor_ok)
        if not factor_ok:
            self.vault_last_error = "Controller combo rejected by Security daemon"
            self.append_audit("credential_vault_factor_rejected", {"mode": mode, "username": str(username or "")})
            return False
        self.append_audit("credential_vault_factor_verified", {"mode": mode, "username": str(username or "")})
        try:
            key = self.vault_master_key()
            if not self.vault_path.exists():
                self.vault_encrypt_controller(key, [])

            document = json.loads(self.vault_path.read_text(encoding="utf-8"))
            schema = int(document.get("schema", 1))

            if schema == 1:
                # A password-era vault cannot be decrypted without its original
                # password. An empty legacy vault can be identified by ciphertext
                # length and safely re-created under the controller-key format.
                legacy_ciphertext = self.b64d(str(document.get("ciphertext", "")))
                empty_v1_length = len(canonical({"schema": 1, "entries": []})) + 16
                if len(legacy_ciphertext) != empty_v1_length:
                    self.vault_last_error = "Legacy password vault contains data and requires one-time migration"
                    return False
                self.vault_encrypt_controller(key, [])
                document = json.loads(self.vault_path.read_text(encoding="utf-8"))
                schema = 2
                self.append_audit("credential_vault_empty_legacy_migrated", {"toSchema": 2})

            if schema != 2 or str(document.get("keyMode", "")) != "controller":
                self.vault_last_error = "Unsupported vault format"
                return False

            plaintext = AESGCM(key).decrypt(
                self.b64d(str(document.get("nonce", ""))),
                self.b64d(str(document.get("ciphertext", ""))),
                b"NeutronOS-Credential-Vault-v2",
            )
            decoded = json.loads(plaintext.decode("utf-8"))
            entries = decoded.get("entries", []) if isinstance(decoded, dict) else []
            self.vault_entries = [dict(item) for item in entries if isinstance(item, dict)]
            self.vault_key = key
            self.vault_unlocked_until = time.monotonic() + max(60, int(self.config.get("vaultUnlockSeconds", 300)))
            self.vault_last_error = "Unlocked with controller combo"
            self.append_audit("credential_vault_unlocked", {"entryCount": len(self.vault_entries), "keyMode": "controller"})
            return True
        except Exception as exc:
            self.vault_key = None
            self.vault_entries = []
            self.vault_last_error = "Controller vault unlock failed"
            self.append_audit("credential_vault_unlock_failed", {"keyMode": "controller", "error": str(exc)})
            return False

    def unlock_vault(self, password: str) -> bool:
        if not self.vault_available():
            self.vault_last_error = "python3-cryptography is unavailable"
            return False
        if not password:
            self.vault_last_error = "Account password was empty"
            return False
        try:
            if not self.vault_path.exists():
                salt = secrets.token_bytes(16)
                key = self.vault_derive_key(password, salt)
                entries: list[dict[str, Any]] = []
                self.vault_encrypt(key, entries, salt)
            document = json.loads(self.vault_path.read_text(encoding="utf-8"))
            salt = self.b64d(str(document.get("salt", "")))
            key = self.vault_derive_key(password, salt)
            plaintext = AESGCM(key).decrypt(self.b64d(str(document.get("nonce", ""))), self.b64d(str(document.get("ciphertext", ""))), b"NeutronOS-Credential-Vault-v1")
            decoded = json.loads(plaintext.decode("utf-8"))
            entries = decoded.get("entries", []) if isinstance(decoded, dict) else []
            self.vault_entries = [dict(item) for item in entries if isinstance(item, dict)]
            self.vault_key = key
            self.vault_unlocked_until = time.monotonic() + max(60, int(self.config.get("vaultUnlockSeconds", 300)))
            self.vault_last_error = "Unlocked"
            self.append_audit("credential_vault_unlocked", {"entryCount": len(self.vault_entries)})
            return True
        except Exception:
            self.vault_key = None
            self.vault_entries = []
            self.vault_last_error = "Vault password verification failed"
            self.append_audit("credential_vault_unlock_failed", {})
            return False

    def lock_vault(self) -> None:
        self.vault_key = None
        self.vault_entries = []
        self.vault_unlocked_until = 0.0
        self.vault_last_error = "Locked"
        self.append_audit("credential_vault_locked", {})

    def save_vault(self) -> bool:
        if not self.vault_unlocked() or self.vault_key is None:
            self.vault_last_error = "Vault is locked"
            return False
        try:
            document = json.loads(self.vault_path.read_text(encoding="utf-8"))
            if int(document.get("schema", 1)) == 2 and str(document.get("keyMode", "")) == "controller":
                self.vault_encrypt_controller(self.vault_key, self.vault_entries)
            else:
                salt = self.b64d(str(document.get("salt", "")))
                self.vault_encrypt(self.vault_key, self.vault_entries, salt)
            return True
        except Exception:
            self.vault_last_error = "Could not save encrypted vault"
            return False

    def save_vault_entry(self, entry_id: str, name: str, username: str, password: str) -> bool:
        if not self.vault_unlocked() or not password:
            self.vault_last_error = "Vault is locked or password is empty"
            return False
        entry_id = entry_id.strip() or str(uuid.uuid4())
        now = utc_now()
        found = False
        for entry in self.vault_entries:
            if str(entry.get("id", "")) == entry_id:
                entry.update({"name": name.strip() or "Credential", "username": username, "password": password, "updatedAt": now})
                found = True
                break
        if not found:
            self.vault_entries.append({"id": entry_id, "name": name.strip() or "Credential", "username": username, "password": password, "createdAt": now, "updatedAt": now})
        if not self.save_vault():
            return False
        self.append_audit("credential_vault_entry_saved", {"entryId": entry_id, "name": name.strip() or "Credential"})
        return True

    def delete_vault_entry(self, entry_id: str) -> bool:
        if not self.vault_unlocked():
            return False
        before = len(self.vault_entries)
        self.vault_entries = [entry for entry in self.vault_entries if str(entry.get("id", "")) != entry_id]
        if len(self.vault_entries) == before:
            return False
        if not self.save_vault():
            return False
        self.append_audit("credential_vault_entry_deleted", {"entryId": entry_id})
        return True

    def write_response(self, request_id: str, payload: dict[str, Any]) -> None:
        if not request_id:
            return
        atomic_json(self.responses_dir / f"{request_id}.json", payload, 0o640)
        try:
            uid = pwd.getpwnam(self.owner).pw_uid
            gid = grp.getgrnam(self.group).gr_gid
            os.chown(self.responses_dir / f"{request_id}.json", uid, gid)
        except Exception:
            pass

    def reveal_vault_entry(self, entry_id: str, request_id: str) -> bool:
        if not self.vault_unlocked():
            self.write_response(request_id, {"type": "vault_secret", "success": False, "message": "Vault is locked"})
            return False
        for entry in self.vault_entries:
            if str(entry.get("id", "")) == entry_id:
                self.write_response(request_id, {"type": "vault_secret", "success": True, "entryId": entry_id, "name": str(entry.get("name", "")), "username": str(entry.get("username", "")), "password": str(entry.get("password", "")), "expiresIn": 30})
                self.append_audit("credential_vault_entry_revealed", {"entryId": entry_id})
                return True
        self.write_response(request_id, {"type": "vault_secret", "success": False, "message": "Credential was not found"})
        return False

    def process_requests(self) -> bool:
        if not self.legacy_json_requests:
            return False
        processed = False
        for path in sorted(self.requests_dir.glob("*.json")):
            processed = True
            try:
                request = json.loads(path.read_text(encoding="utf-8"))
                action = str(request.get("action", ""))
                payload = request.get("payload", {}) if isinstance(request.get("payload", {}), dict) else {}
                if action == "set_learning_mode":
                    enabled = bool(payload.get("enabled", True))
                    self.config["learningMode"] = enabled
                    self.save_config()
                    self.append_audit("learning_mode_changed", {"enabled": enabled})
                elif action == "set_enforcement_enabled":
                    enabled = bool(payload.get("enabled", False))
                    self.config["enforcementEnabled"] = enabled
                    if enabled:
                        self.config["learningMode"] = False
                    self.save_config()
                    self.append_audit("network_enforcement_changed", {"enabled": enabled})
                elif action == "set_response_engine_enabled":
                    enabled = bool(payload.get("enabled", False))
                    self.config["responseEngineEnabled"] = enabled
                    self.save_config()
                    self.append_audit("response_engine_changed", {"enabled": enabled})
                elif action == "set_manual_defcon":
                    self.set_manual_defcon(int(payload.get("level", 5)), str(payload.get("reason", "Authorized local action")))
                elif action == "deescalate_normal":
                    if self.response_state.get("containmentActive"):
                        self.leave_containment("Authorized return to normal")
                    self.record_response_transition(5, "Authorized return to normal monitoring", False)
                elif action == "preview_hardening":
                    self.preview_hardening(str(payload.get("profile", "")))
                elif action == "apply_hardening":
                    self.apply_hardening(str(payload.get("profile", "")))
                elif action == "rollback_hardening":
                    self.rollback_hardening("Authorized Security app rollback")
                elif action == "block_source":
                    address = str(payload.get("address", "")).strip()
                    duration = int(payload.get("durationMinutes", 10))
                    self.ban_source(address, duration, "Manual block from Security app", manual=True)
                elif action == "unblock_source":
                    self.unban_source(str(payload.get("address", "")).strip(), "Manual unblock from Security app")
                elif action == "trust_source":
                    address = str(payload.get("address", "")).strip()
                    try:
                        normalized = str(ipaddress.ip_network(address, strict=False)) if "/" in address else str(ipaddress.ip_address(address))
                    except ValueError:
                        self.append_audit("request_rejected", {"action": action, "reason": "invalid address"})
                    else:
                        trusted = list(dict.fromkeys([str(value) for value in self.config.get("trustedSources", [])] + [normalized]))
                        self.config["trustedSources"] = trusted
                        self.save_config()
                        if address in self.bans:
                            self.unban_source(address, "Source added to trusted list")
                        self.append_audit("trusted_source_added", {"address": normalized})
                elif action == "untrust_source":
                    address = str(payload.get("address", "")).strip()
                    self.config["trustedSources"] = [str(value) for value in self.config.get("trustedSources", []) if str(value) != address]
                    self.save_config()
                    self.append_audit("trusted_source_removed", {"address": address})
                elif action == "acknowledge_event":
                    event_id = str(payload.get("eventId", ""))
                    changed = False
                    for event in self.events:
                        if str(event.get("id")) == event_id:
                            event["acknowledged"] = True
                            changed = True
                            break
                    if changed:
                        self.append_audit("event_acknowledged", {"eventId": event_id})
                        self.save_events()
                elif action == "scan_path":
                    self.run_malware_scan(str(payload.get("path", "")), str(request.get("id", "")))
                elif action == "scan_downloads":
                    self.run_malware_scan(str(self.owner_home() / "Downloads"), str(request.get("id", "")))
                elif action == "scan_neutronos":
                    self.run_malware_scan(str(self.project_root), str(request.get("id", "")))
                elif action == "cancel_scan":
                    self.cancel_malware_scan(str(request.get("id", "")))
                elif action == "update_definitions":
                    result = subprocess.run(["systemctl", "restart", "clamav-freshclam.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    self.update_antivirus_status()
                    self.append_audit("antivirus_definitions_update_requested", {"success": result.returncode == 0})
                elif action == "quarantine_finding":
                    self.quarantine_finding(str(payload.get("findingId", "")))
                elif action == "restore_quarantined":
                    self.restore_quarantined(str(payload.get("itemId", "")))
                elif action == "create_integrity_baseline":
                    self.create_integrity_baseline("authorized Security app request")
                elif action == "verify_integrity":
                    self.verify_integrity()
                elif action == "trust_peripheral":
                    self.trust_peripheral(str(payload.get("deviceId", "")))
                elif action == "allow_peripheral_once":
                    self.allow_peripheral_once(str(payload.get("deviceId", "")))
                elif action == "block_peripheral":
                    self.block_peripheral(str(payload.get("deviceId", "")))
                elif action == "enroll_recovery_code":
                    self.enroll_recovery_code(str(payload.get("code", "")))
                elif action == "enroll_usb_recovery":
                    self.enroll_usb_recovery(str(payload.get("device", "")))
                elif action == "verify_recovery_code":
                    self.verify_recovery_code(str(payload.get("code", "")))
                elif action == "verify_usb_recovery":
                    self.verify_usb_recovery()
                elif action == "clear_recovery":
                    self.clear_recovery()
                elif action == "unlock_vault":
                    self.unlock_vault(str(payload.get("password", "")))
                elif action == "lock_vault":
                    self.lock_vault()
                elif action == "save_vault_entry":
                    self.save_vault_entry(str(payload.get("entryId", "")), str(payload.get("name", "")), str(payload.get("username", "")), str(payload.get("password", "")))
                elif action == "delete_vault_entry":
                    self.delete_vault_entry(str(payload.get("entryId", "")))
                elif action == "reveal_vault_entry":
                    self.reveal_vault_entry(str(payload.get("entryId", "")), str(request.get("id", "")))
                elif action == "snapshot":
                    self.last_scan = ""
                    self.append_audit("snapshot_requested", {"requestId": request.get("id", "")})
                else:
                    self.append_audit("request_rejected", {"action": action})
            except Exception as exc:
                self.append_audit("request_error", {"file": path.name, "error": str(exc)})
            finally:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
        return processed

    def process_watchdog_event(self) -> bool:
        try:
            event = json.loads(self.watchdog_event_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return False
        except (OSError, json.JSONDecodeError):
            event = {"action": "watchdog_event_invalid", "details": {}}
        try:
            self.watchdog_event_path.unlink()
        except FileNotFoundError:
            pass
        action = str(event.get("action", "watchdog_event"))[:120]
        details = event.get("details", {}) if isinstance(event.get("details", {}), dict) else {}
        details["watchdogTimestamp"] = str(event.get("timestamp", ""))
        self.append_audit(action, details)
        return True

    def ipc_authenticate(self, peer: PeerCredentials, session: dict[str, str]) -> bool:
        return verify_active_session(
            peer, session,
            trusted_system_shell=(
                pwd.getpwnam(self.owner).pw_uid,
                self.owner,
                str(self.project_root / "build" / "NeutronShell"),
                "/system.slice/neutronos.service",
            ),
        )

    def ipc_authorize(self, peer: PeerCredentials, session: dict[str, str],
                      application: dict[str, str], operation: str,
                      arguments: dict[str, Any]):
        try:
            return self.authorization_policy.authorize(
                peer, session, application, operation, arguments
            )
        except AuthorizationError as exc:
            raise ProtocolError(exc.code, exc.message) from exc

    def ipc_audit(self, action: str, details: dict[str, Any]) -> None:
        # Successful cached-state reads are routine presentation traffic. They
        # carry no Security outcome and would otherwise grow the audit chain on
        # every UI refresh. Rejections and every mutating operation remain
        # audited by the transport and/or the authoritative operation handler.
        if action == "ipc_request_accepted" and details.get("operation") == "security.snapshot":
            return
        self.append_audit(action, details)

    def ipc_handle(self, operation: str, arguments: dict[str, Any],
                   context: RequestContext) -> dict[str, Any]:
        if operation == "protocol.info":
            if arguments:
                raise ValueError("this operation does not accept arguments")
            return {
                "protocol": PROTOCOL_NAME,
                "versions": [PROTOCOL_VERSION],
                "service": "security",
                "operations": self.authorization_policy.enabled_operations(),
                "identity": {
                    "peerCredentialsVerified": True,
                    "sessionVerified": True,
                    "applicationIdentityStrength": context.application_identity_strength,
                    "permission": context.permission,
                    "principal": context.principal,
                },
            }
        if operation == "security.health":
            if arguments:
                raise ValueError("this operation does not accept arguments")
            return {
                "online": True,
                "auditValid": bool(self.audit_valid),
                "heartbeat": utc_now(),
            }
        if operation == "security.request-snapshot":
            if arguments:
                raise ValueError("this operation does not accept arguments")
            self.last_scan = ""
            self.append_audit("snapshot_requested", {
                "transport": "unix-socket", "peerPid": context.peer.pid,
            })
            return {"accepted": True}
        if operation == "security.snapshot":
            if arguments:
                raise ValueError("this operation does not accept arguments")
            try:
                state = json.loads(self.state_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                state = {}
            # Vault secrets are never present in state.json; return a bounded
            # copy so an unexpectedly large state cannot bypass response limits.
            return {"state": state, "generatedAt": utc_now()}
        success = False
        message = "Security operation was rejected"
        extra: dict[str, Any] = {}
        if operation == "security.set-learning-mode":
            enabled = bool(arguments["enabled"])
            self.config["learningMode"] = enabled
            if enabled:
                self.config["enforcementEnabled"] = False
            self.save_config()
            self.append_audit("learning_mode_changed", {"enabled": enabled})
            success, message = True, "Learning mode updated"
        elif operation == "security.set-enforcement-enabled":
            enabled = bool(arguments["enabled"])
            self.config["enforcementEnabled"] = enabled
            if enabled:
                self.config["learningMode"] = False
            self.save_config()
            self.append_audit("network_enforcement_changed", {"enabled": enabled})
            success, message = True, "Network enforcement updated"
        elif operation == "security.set-response-engine-enabled":
            enabled = bool(arguments["enabled"])
            self.config["responseEngineEnabled"] = enabled
            self.save_config()
            self.append_audit("response_engine_changed", {"enabled": enabled})
            success, message = True, "Response engine updated"
        elif operation == "security.set-manual-defcon":
            success = self.set_manual_defcon(int(arguments["level"]))
            message = "Threat level updated" if success else "Threat level change was rejected"
        elif operation == "security.deescalate-normal":
            if self.response_state.get("containmentActive"):
                self.leave_containment("Authorized return to normal")
            self.set_manual_normal_override("Authorized return to normal monitoring")
            self.record_response_transition(5, "Authorized return to normal monitoring", False)
            success, message = True, "Returned to DEFCON 5"
        elif operation == "security.acknowledge-event":
            event_id = str(arguments["eventId"])
            for event in self.events:
                if str(event.get("id", "")) == event_id:
                    event["acknowledged"] = True
                    success = True
                    break
            if success:
                self.save_events()
                self.append_audit("event_acknowledged", {"eventId": event_id})
            message = "Event acknowledged" if success else "Security event was not found"
        elif operation == "security.acknowledge-all-events":
            count = 0
            for event in self.events:
                if not event.get("acknowledged"):
                    event["acknowledged"] = True
                    count += 1
            if count:
                self.save_events()
                self.append_audit("events_acknowledged_bulk", {"count": count})
            success = True
            message = (
                f"{count} security event{'s' if count != 1 else ''} acknowledged"
                if count else "All security events are already acknowledged"
            )
        elif operation == "security.preview-hardening":
            success = self.preview_hardening(str(arguments["profile"]))
            message = "Hardening preview prepared" if success else "Unknown hardening profile"
        elif operation == "security.apply-hardening":
            success = self.apply_hardening(str(arguments["profile"]))
            message = str(self.hardening_state.get("lastResult", "Hardening operation completed"))
        elif operation == "security.rollback-hardening":
            success = self.rollback_hardening("Authorized Security app rollback")
            message = str(self.hardening_state.get("lastResult", "Hardening rollback completed"))
        elif operation == "security.block-source":
            success = self.ban_source(str(arguments["address"]), int(arguments["durationMinutes"]),
                                      "Manual block from Security app", manual=True)
            message = "Source blocked" if success else "Source could not be blocked"
        elif operation == "security.unblock-source":
            success = self.unban_source(str(arguments["address"]), "Manual unblock from Security app")
            message = "Source unblocked" if success else "Source was not blocked"
        elif operation == "security.trust-peripheral":
            device_id = str(arguments["deviceId"])
            success = any(str(item.get("deviceId", item.get("id", ""))) == device_id for item in self.peripherals)
            if success:
                self.trust_peripheral(device_id)
            message = "Peripheral trusted" if success else "Peripheral was not found"
        elif operation == "security.allow-peripheral-once":
            device_id = str(arguments["deviceId"])
            success = any(str(item.get("deviceId", item.get("id", ""))) == device_id for item in self.peripherals)
            if success:
                self.allow_peripheral_once(device_id)
            message = "Peripheral allowed once" if success else "Peripheral was not found"
        elif operation == "security.block-peripheral":
            device_id = str(arguments["deviceId"])
            success = any(str(item.get("deviceId", item.get("id", ""))) == device_id for item in self.peripherals)
            if success:
                self.block_peripheral(device_id)
            message = "Peripheral blocked" if success else "Peripheral was not found"
        elif operation == "security.set-event-flagged":
            event_id = str(arguments["eventId"])
            flagged = bool(arguments["flagged"])
            for event in self.events:
                if str(event.get("id", "")) == event_id:
                    event["flagged"] = flagged
                    success = True
                    break
            if success:
                self.save_events()
                self.append_audit("event_flag_changed", {"eventId": event_id, "flagged": flagged})
            message = "Event flag updated" if success else "Security event was not found"
        elif operation == "security.neutralize-event":
            event_id = str(arguments.get("eventId", ""))
            if event_id:
                for event in self.events:
                    if str(event.get("id", "")) == event_id:
                        event["acknowledged"] = True
                        event["flagged"] = False
                        success = True
                        break
                if success:
                    self.save_events()
            else:
                success = True
            if self.response_state.get("containmentActive"):
                self.leave_containment("Threat acknowledged as neutralized")
            self.set_manual_normal_override("Threat acknowledged as neutralized")
            self.record_response_transition(5, "Threat acknowledged as neutralized", False)
            self.append_audit("threat_neutralized", {"eventId": event_id})
            message = "Threat neutralized and DEFCON returned to 5" if success else "Security event was not found"
        elif operation == "security.set-ssh-enabled":
            enabled = bool(arguments["enabled"])
            success = self.set_service_enabled("ssh.service", enabled)
            self.append_audit("ssh_service_changed", {"enabled": enabled, "success": success})
            message = "SSH enabled" if success and enabled else ("SSH disabled" if success else "SSH service change failed")
        elif operation == "security.set-tailscale-enabled":
            enabled = bool(arguments["enabled"])
            success = self.set_service_enabled("tailscaled.service", enabled)
            self.append_audit("tailscale_service_changed", {"enabled": enabled, "success": success})
            message = "Tailscale enabled" if success and enabled else ("Tailscale disabled" if success else "Tailscale service change failed")
        elif operation == "security.set-vault-combo-mode":
            prior = self.vault_combo_state()
            # Once a vault factor is configured, changing its mode requires the
            # vault to already be unlocked by the existing factor.  First-time
            # enrollment remains possible without weakening existing secrets.
            if bool(prior.get("configured", False)) and not self.vault_unlocked():
                success = False
                message = "Unlock the vault before changing its controller authentication mode"
            else:
                success = self.set_vault_combo_mode(str(arguments["mode"]))
                message = "Vault will use the NeutronOS login combo" if success else "Vault combo mode was rejected"
        elif operation == "security.set-vault-combo":
            combo_value = str(arguments["combo"])
            prior = self.vault_combo_state()
            existing_secrets_may_exist = self.vault_path.exists()
            if (bool(prior.get("configured", False)) or existing_secrets_may_exist) and not self.vault_unlocked():
                success = False
                message = "Unlock the existing vault before replacing its controller combo"
            else:
                success = self.set_vault_combo(combo_value)
                if success:
                    success = self.unlock_vault_controller(combo_value)
                message = "Custom vault combo saved and vault unlocked" if success else (self.vault_last_error or "Vault combo must contain 4 to 15 inputs")
        elif operation == "security.verify-vault-combo":
            success = self.verify_vault_combo(str(arguments["combo"]))
            message = "Vault combo verified" if success else "Vault combo rejected"
        elif operation == "security.scan-downloads":
            success, message = self.start_malware_scan(
                str(self.owner_home() / "Downloads"),
                "Downloads",
                context.application.get("instance", ""),
            )

        elif operation == "security.scan-neutronos":
            success, message = self.start_malware_scan(
                str(self.project_root),
                "NeutronOS",
                context.application.get("instance", ""),
            )

        elif operation == "security.cancel-scan":
            success, message = self.cancel_malware_scan(
                context.application.get("instance", "")
            )

        elif operation == "security.quarantine-finding":
            finding_id = str(arguments["findingId"])
            success = any(str(item.get("id", "")) == finding_id for item in self.malware_findings)
            if success:
                self.quarantine_finding(finding_id)
            message = "Finding quarantined" if success else "Finding was not found"
        elif operation == "security.verify-integrity":
            self.verify_integrity()
            success, message = True, "Integrity verification completed"
        elif operation == "security.create-integrity-baseline":
            self.create_integrity_baseline("authorized Security IPC request")
            success, message = True, "Integrity baseline created"
        elif operation == "security.enroll-recovery-code":
            raw = secrets.token_hex(24).upper()
            code = "-".join(raw[index:index + 4] for index in range(0, len(raw), 4))
            success = self.enroll_recovery_code(code)
            if success:
                extra["recoveryCode"] = code
            message = "Recovery code generated; store it offline now" if success else "Recovery code could not be enrolled"
        elif operation == "security.enroll-usb-recovery":
            success = self.enroll_usb_recovery(str(arguments["device"]))
            message = "USB recovery enrolled" if success else "USB recovery could not be enrolled"
        elif operation == "security.verify-recovery-code":
            success = self.verify_recovery_code(str(arguments["code"]))
            message = str(self.last_recovery_verification.get("message", "Recovery verification completed"))
        elif operation == "security.verify-usb-recovery":
            success = self.verify_usb_recovery()
            message = str(self.last_recovery_verification.get("message", "USB recovery verification completed"))
        elif operation == "security.unlock-vault":
            success = self.unlock_vault(str(arguments["password"]))
            message = self.vault_last_error
        elif operation == "security.unlock-vault-controller":
            success = self.unlock_vault_controller(
                str(arguments["combo"]), str(arguments.get("username", ""))
            )
            message = self.vault_last_error
        elif operation == "security.lock-vault":
            self.lock_vault()
            success, message = True, "Credential vault locked"
        elif operation == "security.save-vault-entry":
            success = self.save_vault_entry(str(arguments["entryId"]), str(arguments["name"]),
                                            str(arguments["username"]), str(arguments["password"]))
            message = "Credential saved" if success else self.vault_last_error
        elif operation == "security.delete-vault-entry":
            success = self.delete_vault_entry(str(arguments["entryId"]))
            message = "Credential deleted" if success else "Credential could not be deleted"
        elif operation == "security.reveal-vault-entry":
            entry_id = str(arguments["entryId"])
            if self.vault_unlocked():
                for entry in self.vault_entries:
                    if str(entry.get("id", "")) == entry_id:
                        extra["secret"] = {
                            "id": entry_id, "name": str(entry.get("name", "")),
                            "username": str(entry.get("username", "")),
                            "password": str(entry.get("password", "")), "expiresIn": 30,
                        }
                        self.append_audit("credential_vault_entry_revealed", {"entryId": entry_id})
                        success = True
                        break
            message = "Credential revealed" if success else "Vault is locked or credential was not found"
        else:
            raise ValueError("unsupported operation")
        self.write_state()
        return {"success": success, "message": message, **extra}

    def calculate_score(self) -> int:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
        penalty = 0
        for event in self.events:
            stamp = parse_time(str(event.get("timestamp", "")))
            if stamp is not None and stamp < cutoff:
                continue
            if event.get("acknowledged"):
                continue
            severity = int(event.get("severity", 1))
            penalty += {1: 0, 2: 2, 3: 5, 4: 12, 5: 25}.get(severity, 1)
        if self.failed_services:
            penalty += min(10, len(self.failed_services) * 2)
        firewall_state = str(self.firewall_health.get("protectionState", "CRITICAL")).upper()
        if firewall_state == "CRITICAL":
            penalty += 50
        elif firewall_state == "DEGRADED":
            penalty += 15
        return max(0, min(100, 100 - penalty))

    def write_state(self) -> None:
        self.refresh_firewall_health(record_event=False)
        now = datetime.now(timezone.utc)
        day_cutoff = now - timedelta(hours=24)
        recent = []
        high = 0
        acknowledged = 0
        for event in self.events:
            stamp = parse_time(str(event.get("timestamp", "")))
            if stamp is None or stamp >= day_cutoff:
                recent.append(event)
                if int(event.get("severity", 1)) >= 4:
                    high += 1
            if event.get("acknowledged"):
                acknowledged += 1
        score = self.calculate_score()
        authentication_failures = sum(
            int(event.get("attempts", 1)) for event in recent
            if event.get("category") == "authentication"
        )
        privilege_failures = sum(
            int(event.get("attempts", 1)) for event in recent
            if event.get("category") == "privilege"
        )
        firewall_state = str(self.firewall_health.get("protectionState", "CRITICAL"))
        if firewall_state == "CRITICAL":
            daemon_status = "CRITICAL — kernel firewall protection unavailable"
        elif firewall_state == "DEGRADED":
            daemon_status = "DEGRADED — emergency firewall protection active"
        elif self.response_state.get("containmentActive"):
            daemon_status = "Emergency containment active"
        elif self.config.get("learningMode", True):
            daemon_status = "Learning Mode — observing only"
        elif self.config.get("responseEngineEnabled", False):
            daemon_status = "DEFCON response engine active"
        elif self.config.get("enforcementEnabled", False):
            daemon_status = "Network enforcement active"
        else:
            daemon_status = "Manual monitoring"
        state = {
            "schema": 4,
            "heartbeat": utc_now(),
            "daemonStatus": daemon_status,
            "learningMode": bool(self.config.get("learningMode", True)),
            "enforcementEnabled": bool(self.config.get("enforcementEnabled", False)),
            "threatLevel": int(self.response_state.get("currentLevel", 5)),
            "threatLabel": f"DEFCON {int(self.response_state.get('currentLevel', 5))}",
            "suggestedThreatLevel": int(self.response_state.get("suggestedLevel", 5)),
            "suggestedThreatReason": str(self.response_state.get("suggestedReason", "Normal monitoring")),
            "responseEngineEnabled": bool(self.config.get("responseEngineEnabled", False)),
            "responseState": self.response_state,
            "responseHistory": self.response_history[:50],
            "hardeningState": self.hardening_state,
            "hardeningProfiles": self.hardening_profiles(),
            "activeHardeningProfile": str(self.hardening_state.get("activeProfile", "none")),
            "hardeningRollbackAvailable": bool(self.hardening_state.get("rollbackAvailable", False)),
            "recoveryConfigured": self.recovery_configured(),
            "recovery": self.recovery_public_state(),
            "recoveryUsbCandidates": self.recovery_usb_candidates,
            "lastRecoveryVerification": self.last_recovery_verification,
            "vaultAvailable": self.vault_available(),
            "vaultUnlocked": self.vault_unlocked(),
            "vaultUnlockRemaining": max(0, int(self.vault_unlocked_until - time.monotonic())) if self.vault_unlocked() else 0,
            "vaultLastError": self.vault_last_error,
            "vaultEntries": [{"id": str(item.get("id", "")), "name": str(item.get("name", "Credential")), "username": str(item.get("username", "")), "createdAt": str(item.get("createdAt", "")), "updatedAt": str(item.get("updatedAt", ""))} for item in self.vault_entries] if self.vault_unlocked() else [],
            "securityScore": score,
            "lastScan": self.last_scan,
            "auditValid": self.audit_valid,
            "auditHead": self.audit_head,
            "events": list(self.events)[:250],
            "listeningPorts": self.listening_ports,
            "failedServices": self.failed_services,
            "peripherals": self.peripherals,
            "trustedPeripherals": [item for item in self.peripherals if item.get("trustState") == "trusted"],
            "pendingPeripherals": [item for item in self.peripherals if item.get("trustState") == "unknown"],
            "rejectedActivity": self.rejected_activity(),
            "auditEntries": self.recent_audit_entries(25),
            "installedApps": self.installed_apps(),
            "sshStatus": self.service_status("ssh.service", command="ssh"),
            "tailscaleStatus": self.service_status("tailscaled.service", command="tailscale"),
            "vaultCombo": self.vault_combo_state(),
            "malwareFindings": self.malware_findings,
            "quarantinedItems": self.quarantined_items,
            "antivirusAvailable": bool(self.antivirus_backend()),
            "antivirusStatus": self.antivirus_status,
            "antivirusVersion": self.antivirus_version,
            "lastMalwareScan": self.last_malware_scan,
            "integrityBaselineReady": bool(self.integrity_baseline),
            "integrityStatus": self.integrity_status,
            "integrityChanges": self.integrity_changes,
            "integrityChangeSignature": self.previous_integrity_signature,
            "lastIntegrityScan": self.last_integrity_scan,
            "packageChanges": self.package_changes,
            "peripheralEnforcementEnabled": bool(self.config.get("peripheralEnforcementEnabled", False)),
            "bannedSources": sorted(self.bans.values(), key=lambda item: str(item.get("expiresAt", ""))),
            "trustedSources": [{"address": str(value)} for value in self.config.get("trustedSources", [])],
            "firewallBackend": self.firewall_backend(),
            "firewallProtection": dict(self.firewall_health),
            "stats": {
                "firewallProtectionState": str(self.firewall_health.get("protectionState", "CRITICAL")),
                "firewallActive": bool(self.firewall_health.get("firewallActive", False)),
                "firewallLifelineActive": bool(self.firewall_health.get("lifelineActive", False)),
                "firewallBaseTableActive": bool(self.firewall_health.get("baseTableActive", False)),
                "firewallSecurityTableActive": bool(self.firewall_health.get("securityTableActive", False)),
                "firewallGuardStateStale": bool(self.firewall_health.get("guardStateStale", True)),
                "firewallReason": str(self.firewall_health.get("reason", "Firewall health unavailable")),
                "events24h": len(recent),
                "highEvents24h": high,
                "authenticationFailures": authentication_failures,
                "privilegeFailures": privilege_failures,
                "listeningPorts": len(self.listening_ports),
                "failedServices": len(self.failed_services),
                "usbDevices": len(self.peripherals),
                "unknownPeripherals": sum(1 for item in self.peripherals if item.get("trustState") == "unknown"),
                "malwareFindings": sum(1 for item in self.malware_findings if item.get("status") == "detected"),
                "quarantinedItems": sum(1 for item in self.quarantined_items if item.get("status") == "quarantined"),
                "integrityChanges": len(self.integrity_changes),
                "packageChanges": len(self.package_changes),
                "acknowledgedEvents": acknowledged,
                "enforcementActions": sum(1 for item in self.bans.values() if item.get("active")),
                "bannedSources": len(self.bans),
                "scanRunning": self.scan_running,
                "scanTarget": self.scan_target,
                "scanStartedAt": self.scan_started_at,
                "scanFinishedAt": self.scan_finished_at,
                "scanElapsedSeconds": (
                    max(0, int(time.monotonic() - self.scan_started_monotonic))
                    if self.scan_running
                    else self.scan_elapsed_seconds
                ),
                "scanThreatsFound": self.scan_threats_found,
                "scanCurrentFile": self.scan_current_file,
                "scanFilesChecked": self.scan_files_checked,
                "scanPid": self.scan_pid,
                "scanMemoryLimitMiB": self.scan_memory_limit_mib,
                "scanMinimumAvailableMiB": self.scan_min_available_mib,
                "memoryAvailableMiB": self.available_memory_mib(),
                "scanStatus": (
                    self.antivirus_status
                    if self.scan_running
                    else self.scan_last_result
                ),
                "scanLastResult": self.scan_last_result,
                "scanResultVisible": (
                    self.scan_running
                    or (
                        bool(self.scan_finished_at)
                        and time.monotonic() < self.scan_result_until
                    )
                ),
                "activeThreats": self.active_threat_count(),
                "unacknowledgedEvents": sum(1 for event in self.events if not event.get("acknowledged")),
                "scorePenalty": max(0, 100 - score),
                "trustedSources": len(self.config.get("trustedSources", [])),
            },
        }
        atomic_json(self.state_path, state, 0o644)

    def scan(self) -> None:
        self.refresh_firewall_health(record_event=True)
        self.expire_bans()
        self.scan_journal()
        self.scan_ports()
        self.scan_failed_services()
        self.scan_peripherals()
        self.scan_recovery_usb_candidates()
        self.scan_package_changes()
        self.verify_integrity()
        self.evaluate_response_engine()
        self.save_protection_state()
        self.save_response_and_hardening_state()
        self.last_scan = utc_now()
        self.save_events()
        self.audit_valid, verified_head = self.verify_audit()
        if self.audit_valid:
            self.audit_head = verified_head
        self.write_state()

    def loop(self, ipc_server: IpcServer) -> None:
        configured = int(self.config.get("scanIntervalSeconds", 60))
        interval = max(60, configured)
        if configured != interval:
            self.config["scanIntervalSeconds"] = interval
            self.save_config()
        next_scan = 0.0
        next_heartbeat = 0.0
        while RUNNING:
            while ipc_server.serve_ready(0.0):
                pass
            processed = self.process_watchdog_event() or self.process_requests()
            now = time.monotonic()
            if now >= next_scan or not self.last_scan:
                self.scan()
                next_scan = now + interval
                next_heartbeat = now + 5.0
            elif processed or now >= next_heartbeat:
                self.write_state()
                next_heartbeat = now + 5.0
            time.sleep(0.1)
        self.append_audit("daemon_stopped", {})
        self.write_state()


def handle_signal(_signum: int, _frame: Any) -> None:
    global RUNNING
    RUNNING = False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", default="/var/lib/neutronos/security-core")
    parser.add_argument("--project-root", default=os.environ.get("NEUTRONOS_ROOT", "/opt/neutronos"))
    parser.add_argument("--owner", default=os.environ.get("NEUTRONOS_OWNER", "neutronos"))
    parser.add_argument("--group", default=os.environ.get("NEUTRONOS_GROUP", "neutronos"))
    parser.add_argument("--socket", default="/run/neutronos/security/control.sock")
    parser.add_argument("--socket-group", default="neutronos-shell")
    parser.add_argument("--authorization-policy",
                        default="/etc/neutronos/security-authorization.json")
    parser.add_argument("--legacy-json-requests", action="store_true",
                        help="temporarily accept the deprecated writable JSON request queue")
    parser.add_argument("--smoke-test", action="store_true")
    args = parser.parse_args()
    if args.smoke_test:
        policy = AuthorizationPolicy.load(Path(args.authorization_policy), require_root_owner=os.geteuid() == 0)
        core = SecurityCore(Path(args.state_dir), Path(args.project_root), args.owner, args.group,
                            policy, legacy_json_requests=args.legacy_json_requests)
        print(json.dumps({
            "ok": True, "stateDir": str(core.state_dir),
            "authorizationPolicyLoaded": True,
            "firewallHealthSchema": 1,
        }, sort_keys=True))
        return 0
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    policy = AuthorizationPolicy.load(Path(args.authorization_policy), require_root_owner=os.geteuid() == 0)
    core = SecurityCore(Path(args.state_dir), Path(args.project_root), args.owner, args.group,
                        policy,
                        legacy_json_requests=args.legacy_json_requests)
    server = IpcServer(
        Path(args.socket), "security", core.ipc_handle, core.ipc_authenticate,
        core.ipc_authorize, core.ipc_audit, socket_group=args.socket_group,
    )
    try:
        server.start()
        core.append_audit("ipc_endpoint_started", {
            "socket": str(args.socket), "protocol": PROTOCOL_NAME,
            "version": PROTOCOL_VERSION,
            "legacyJsonRequests": args.legacy_json_requests,
        })
        core.loop(server)
    finally:
        server.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
