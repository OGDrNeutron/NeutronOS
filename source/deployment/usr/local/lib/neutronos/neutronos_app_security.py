"""Shared Patch 72/73 package analysis, sandbox and quarantine primitives.

The unified Security daemon owns persistent quarantine state. This module is a
library used by that daemon and by read-only pre-install analysis tooling; it is
not a second security service.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

CLASSIFICATIONS = ("SAFE", "SUSPICIOUS", "DANGEROUS")
RISK_NOT_PROOF = "Static analysis is a risk assessment, not absolute proof of safety."
SAFE_PAYLOAD_PREFIXES = ("qml/apps/", "themes/Default/apps/", "config/apps/", "scripts/apps/")
DANGEROUS_PATTERNS = {
    "privilege-escalation": re.compile(r"\b(sudo|pkexec|setuid|cap_sys_admin)\b", re.I),
    "privileged-ipc": re.compile(r"/run/neutronos/(security|offline-network)|neutronos-securityctl", re.I),
    "persistence": re.compile(r"(/etc/systemd|systemctl\s+enable|/etc/cron|crontab)", re.I),
    "sensitive-filesystem": re.compile(r"(/etc/shadow|/root/|\.ssh/|/var/lib/neutronos/security)", re.I),
}
SUSPICIOUS_PATTERNS = {
    "shell-execution": re.compile(r"(\bsubprocess(?:\.|\b)|os\.system|child_process|QProcess|/bin/(ba)?sh)", re.I),
    "network-code": re.compile(r"(https?://|socket\.|requests\.|fetch\(|XMLHttpRequest)", re.I),
    "hardware-access": re.compile(r"/dev/(?!null|zero|urandom)", re.I),
}


def atomic_json(path: Path, value: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        try: os.unlink(name)
        except FileNotFoundError: pass


def safe_member(name: str) -> str:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise ValueError(f"unsafe package path: {name}")
    return str(path)


def finding(identifier: str, category: str, severity: str, description: str,
            evidence: str, path: str = "", permission: str = "",
            recommendation: str = "Review before installation") -> dict[str, str]:
    return {"id": identifier, "category": category, "severity": severity,
            "description": description, "evidence": evidence[:500], "path": path,
            "requestedPermission": permission, "recommendedAction": recommendation}


class PackageAnalyzer:
    def analyze(self, package: Path) -> dict[str, Any]:
        package = package.resolve(strict=True)
        if package.suffix.lower() not in {".napp", ".zip"}:
            raise ValueError("package must use .napp or .zip")
        digest_state = hashlib.sha256()
        with package.open("rb") as package_stream:
            for chunk in iter(lambda: package_stream.read(1024 * 1024), b""):
                digest_state.update(chunk)
        digest = digest_state.hexdigest()
        findings: list[dict[str, str]] = []
        inventory: list[dict[str, Any]] = []
        with zipfile.ZipFile(package) as archive:
            try:
                manifest = json.loads(archive.read("manifest.json"))
            except (KeyError, json.JSONDecodeError, UnicodeDecodeError) as exc:
                raise ValueError("valid manifest.json is required") from exc
            if not isinstance(manifest, dict):
                raise ValueError("manifest must be an object")
            permissions = manifest.get("permissions", [])
            if not isinstance(permissions, list) or not all(isinstance(p, str) for p in permissions):
                raise ValueError("permissions must be a string array")
            for info in archive.infolist():
                if info.is_dir():
                    continue
                name = safe_member(info.filename)
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError(f"symbolic links are prohibited: {name}")
                if name != "manifest.json" and not name.startswith("payload/"):
                    raise ValueError(f"unexpected package member: {name}")
                relative = name[8:] if name.startswith("payload/") else name
                if name.startswith("payload/") and not relative.startswith(SAFE_PAYLOAD_PREFIXES):
                    findings.append(finding("target-" + str(len(findings)), "installation-target", "critical",
                        "Package requests a prohibited installation target", relative, relative,
                        recommendation="Quarantine or remove"))
                executable = bool(mode & 0o111) or relative.endswith((".sh", ".py", ".js"))
                member_digest = hashlib.sha256()
                prefix = bytearray()
                with archive.open(info) as member_stream:
                    for chunk in iter(lambda: member_stream.read(1024 * 1024), b""):
                        member_digest.update(chunk)
                        if len(prefix) < 2 * 1024 * 1024:
                            prefix.extend(chunk[:2 * 1024 * 1024 - len(prefix)])
                data = bytes(prefix)
                file_digest = member_digest.hexdigest()
                interpreter = ""
                if data.startswith(b"#!"):
                    interpreter = data.splitlines()[0][2:256].decode("utf-8", errors="replace").strip()
                inventory.append({"path": relative, "size": info.file_size,
                                  "executable": executable, "elf": data.startswith(b"\x7fELF"),
                                  "interpreter": interpreter, "sha256": file_digest})
                if info.file_size > 2 * 1024 * 1024:
                    continue
                text = data.decode("utf-8", errors="ignore")
                for category, pattern in DANGEROUS_PATTERNS.items():
                    match = pattern.search(text)
                    if match:
                        findings.append(finding(category + "-" + str(len(findings)), category, "critical",
                            "High-risk behavior violates default third-party policy", match.group(0), relative,
                            recommendation="Quarantine or remove"))
                for category, pattern in SUSPICIOUS_PATTERNS.items():
                    match = pattern.search(text)
                    if match:
                        findings.append(finding(category + "-" + str(len(findings)), category, "warning",
                            "Behavior requires explicit review and isolation", match.group(0), relative))
        forbidden_permissions = {"root", "systemd-control", "docker-control", "privileged-ipc",
                                 "arbitrary-home", "raw-socket", "hardware-all"}
        for permission in permissions:
            if permission in forbidden_permissions:
                findings.append(finding("permission-" + permission, "permission", "critical",
                    "Requested permission is denied by default", permission,
                    permission=permission, recommendation="Quarantine or remove"))
        classification = "DANGEROUS" if any(f["severity"] == "critical" for f in findings) else (
            "SUSPICIOUS" if findings else "SAFE")
        score = min(100, sum(35 if f["severity"] == "critical" else 12 for f in findings))
        sandbox = SandboxCapabilities.detect()
        return {"schema": 1, "package": str(package), "packageId": str(manifest.get("id", "")),
                "name": str(manifest.get("name", manifest.get("id", package.stem))),
                "entrypoint": str(manifest.get("entrypoint", ""))[:512],
                "classification": classification, "riskScore": score, "findings": findings,
                "requestedPermissions": permissions, "inventory": inventory,
                "sha256": digest, "signatureStatus": str(manifest.get("signatureStatus", "Not available")),
                "observations": {"filesystem": "Static package inventory only",
                                 "network": "Not observed", "execution": "Not observed"},
                "sandboxAvailable": sandbox.bubblewrap,
                "disclaimer": RISK_NOT_PROOF}


@dataclass(frozen=True)
class SandboxCapabilities:
    bubblewrap: bool
    systemd_run: bool
    user_namespaces: bool
    network_namespaces: bool
    cgroups: bool
    seccomp: bool

    @classmethod
    def detect(cls) -> "SandboxCapabilities":
        userns = Path("/proc/sys/user/max_user_namespaces")
        try: userns_enabled = int(userns.read_text().strip()) > 0
        except (OSError, ValueError): userns_enabled = False
        return cls(bool(shutil.which("bwrap")), bool(shutil.which("systemd-run")),
                   userns_enabled, Path("/proc/self/ns/net").exists(),
                   Path("/sys/fs/cgroup/cgroup.controllers").exists(),
                   Path("/proc/self/status").exists())


class SandboxPolicy:
    def __init__(self, capabilities: SandboxCapabilities | None = None):
        self.capabilities = capabilities or SandboxCapabilities.detect()

    def command(self, executable: Path, app_id: str, data_root: Path,
                *, network: bool = False) -> list[str]:
        executable = executable.resolve(strict=True)
        data_root.mkdir(parents=True, exist_ok=True)
        if not self.capabilities.bubblewrap:
            raise RuntimeError("bubblewrap is required for third-party execution isolation")
        command = ["bwrap", "--die-with-parent", "--new-session", "--unshare-pid",
                   "--unshare-uts", "--unshare-ipc", "--unshare-cgroup-try",
                   "--unshare-user-try", "--cap-drop", "ALL", "--clearenv",
                   "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
                   "--ro-bind", "/usr", "/usr", "--ro-bind", "/lib", "/lib",
                   "--ro-bind-try", "/lib64", "/lib64", "--dir", "/app",
                   "--ro-bind", str(executable.parent), "/app/runtime",
                   "--bind", str(data_root), "/app/data", "--chdir", "/app/data",
                   "--setenv", "HOME", "/app/data", "--setenv", "PATH", "/usr/bin:/bin",
                   "--setenv", "NEUTRONOS_APP_ID", app_id]
        if not network:
            command.append("--unshare-net")
        command += ["/app/runtime/" + executable.name]
        return command

    def limits(self) -> dict[str, Any]:
        return {"memoryMaxBytes": 384 * 1024 * 1024, "tasksMax": 96,
                "cpuQuotaPercent": 80, "fileDescriptorsMax": 1024,
                "noNewPrivileges": True, "capabilities": [], "networkDefault": "denied"}


class QuarantineStore:
    def __init__(self, root: Path):
        self.root = root
        self.objects = root / "objects"
        self.audit_path = root / "audit.jsonl"
        self.lock_path = root / "execution.lock"
        self.objects.mkdir(parents=True, exist_ok=True, mode=0o700)

    def _object(self, object_id: str) -> Path:
        if not re.fullmatch(r"[a-f0-9]{32}", object_id):
            raise ValueError("invalid quarantine object id")
        path = self.objects / object_id
        if path.parent != self.objects:
            raise ValueError("quarantine path escaped")
        return path

    def _audit(self, action: str, detail: dict[str, Any]) -> None:
        record = {"timestamp": time.time(), "action": action, "detail": detail}
        with self.audit_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n")
        os.chmod(self.audit_path, 0o600)

    def quarantine(self, candidate: Path, analysis: dict[str, Any]) -> dict[str, Any]:
        candidate = candidate.resolve(strict=True)
        object_id = uuid.uuid4().hex
        target = self._object(object_id)
        target.mkdir(mode=0o700)
        payload = target / "candidate.napp"
        shutil.copy2(candidate, payload, follow_symlinks=False)
        payload.chmod(0o600)
        metadata = {"schema": 1, "id": object_id, "name": analysis.get("name", candidate.name),
                    "packageId": analysis.get("packageId", ""), "classification": analysis.get("classification", "SUSPICIOUS"),
                    "riskScore": int(analysis.get("riskScore", 0)), "findings": analysis.get("findings", []),
                    "requestedPermissions": analysis.get("requestedPermissions", []),
                    "entrypoint": analysis.get("entrypoint", ""),
                    "sha256": hashlib.sha256(payload.read_bytes()).hexdigest(),
                    "signatureStatus": analysis.get("signatureStatus", "Not available"),
                    "quarantinedAt": time.time(), "observations": analysis.get("observations", {}),
                    "originalName": candidate.name, "status": "quarantined"}
        atomic_json(target / "metadata.json", metadata)
        self._audit("quarantined", {"id": object_id, "sha256": metadata["sha256"]})
        return metadata

    def _metadata(self, object_id: str) -> tuple[Path, dict[str, Any]]:
        object_root = self._object(object_id)
        metadata_path = object_root / "metadata.json"
        if metadata_path.is_symlink() or not metadata_path.is_file():
            raise ValueError("quarantine metadata is missing or unsafe")
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if not isinstance(metadata, dict) or metadata.get("id") != object_id:
            raise ValueError("quarantine metadata identity mismatch")
        return object_root, metadata

    def prepare_runtime(self, object_id: str) -> Path:
        object_root, metadata = self._metadata(object_id)
        payload = object_root / "candidate.napp"
        if payload.is_symlink() or not payload.is_file():
            raise ValueError("quarantine payload is missing or unsafe")
        if hashlib.sha256(payload.read_bytes()).hexdigest() != metadata.get("sha256"):
            raise ValueError("quarantine payload integrity failure")
        runtime = object_root / "runtime"
        if runtime.exists():
            shutil.rmtree(runtime)
        runtime.mkdir(mode=0o700)
        with zipfile.ZipFile(payload) as archive:
            for info in archive.infolist():
                if info.is_dir() or not info.filename.startswith("payload/"):
                    continue
                relative = PurePosixPath(safe_member(info.filename)).relative_to("payload")
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError("symbolic links are prohibited in quarantine runtime")
                destination = runtime.joinpath(*relative.parts)
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                with archive.open(info) as source, destination.open("wb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                destination.chmod(0o700 if mode & 0o111 else 0o600)
        return runtime

    def list(self) -> list[dict[str, Any]]:
        result = []
        for path in sorted(self.objects.glob("*/metadata.json")):
            try:
                metadata = json.loads(path.read_text())
                if self._object(str(metadata["id"])) == path.parent:
                    result.append(metadata)
            except (OSError, ValueError, KeyError, json.JSONDecodeError):
                continue
        return result

    def restore(self, object_id: str, destination_root: Path) -> Path:
        source_root, metadata = self._metadata(object_id)
        payload = source_root / "candidate.napp"
        if hashlib.sha256(payload.read_bytes()).hexdigest() != metadata.get("sha256"):
            raise ValueError("quarantine payload integrity failure")
        destination_root = destination_root.resolve(strict=True)
        name = Path(str(metadata.get("originalName", "candidate.napp"))).name
        destination = (destination_root / name).resolve(strict=False)
        if destination.parent != destination_root:
            raise ValueError("restore destination escaped")
        shutil.copy2(payload, destination, follow_symlinks=False)
        self._audit("restored", {"id": object_id, "destination": name})
        return destination

    def delete(self, object_id: str) -> None:
        target, _metadata = self._metadata(object_id)
        if target.is_symlink():
            raise ValueError("quarantine object may not be a symlink")
        shutil.rmtree(target)
        self._audit("deleted", {"id": object_id})

    def run(self, object_id: str, executable: Path, data_root: Path,
            *, network: bool = False, timeout: int = 120,
            policy: SandboxPolicy | None = None) -> dict[str, Any]:
        target, _metadata = self._metadata(object_id)
        runtime = (target / "runtime").resolve(strict=True)
        executable = executable.resolve(strict=True)
        try:
            executable.relative_to(runtime)
        except ValueError as exc:
            raise ValueError("quarantine executable escaped its runtime") from exc
        if executable.is_symlink() or not executable.is_file():
            raise ValueError("quarantine executable is unsafe")
        lock = self.lock_path.open("a+")
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            lock.close()
            raise RuntimeError("another quarantined application is already running") from exc
        started = time.monotonic()
        try:
            command = (policy or SandboxPolicy()).command(executable, object_id, data_root, network=network)
            completed = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, text=True, timeout=timeout,
                                       env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, check=False)
            observation = {"exitCode": completed.returncode, "durationMs": int((time.monotonic() - started) * 1000),
                           "network": "granted" if network else "denied by namespace",
                           "filesystem": "isolated application data root", "terminationReason": "exited"}
        except subprocess.TimeoutExpired:
            observation = {"exitCode": None, "durationMs": int((time.monotonic() - started) * 1000),
                           "network": "granted" if network else "denied by namespace",
                           "filesystem": "isolated application data root", "terminationReason": "timeout"}
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()
        atomic_json(target / "last-observation.json", observation)
        self._audit("executed", {"id": object_id, "result": observation})
        return observation
