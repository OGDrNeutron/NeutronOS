#!/usr/bin/env python3
"""Transactional NeutronOS .napp package installer.

The AppStoreManager authenticates the catalog and signed NAPP before invoking
this helper. The helper independently verifies the pinned NeutronOS release
signature and all payload hashes. Unsigned installation is rejected on Gemini.
This helper never executes package-provided lifecycle code.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import posixpath
import re
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA = 1
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,95}$")
ALLOWED_PREFIXES = (
    "qml/apps/",
    "themes/Default/apps/icons/",
    "themes/Default/apps/posters/",
    "config/apps/",
    "scripts/apps/",
)
SYSTEM_MEMBER_PREFIXES = ("system/owned/", "system/shared/")
BUILD_MEMBER_PREFIX = "build/owned/"
DEBIAN_PACKAGE_RE = re.compile(r"^[a-z0-9][a-z0-9+.-]*(?::[a-z0-9][a-z0-9-]*)?$")
SYSTEM_DESTINATION_PREFIXES = (
    "/etc/systemd/system/",
    "/usr/local/lib/neutronos/",
)
SECURITY_RESERVED_DESTINATION_PREFIXES = (
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
PRIVILEGED_HELPER = "/usr/local/sbin/neutronos-privileged-helper"


def emit(success: bool, message: str, **extra: Any) -> None:
    payload = {"success": success, "message": message, **extra}
    print(json.dumps(payload, separators=(",", ":"), sort_keys=True), flush=True)


def emit_progress(progress: float, stage: str, detail: str = "", items: list[str] | None = None) -> None:
    payload = {
        "event": "progress",
        "progress": max(0.0, min(1.0, float(progress))),
        "stage": str(stage or "").strip(),
        "detail": str(detail or "").strip(),
        "items": [str(item) for item in (items or []) if str(item).strip()],
    }
    print(json.dumps(payload, separators=(",", ":"), sort_keys=True), flush=True)


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def normalize_member(name: str) -> str:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe archive path: {name}")
    normalized = str(path)
    if normalized in (".", ""):
        raise ValueError("empty archive path")
    return normalized


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    if int(manifest.get("schema", 1)) != SCHEMA:
        raise ValueError("unsupported package schema")
    package_id = str(manifest.get("id", "")).strip().lower()
    if not ID_RE.fullmatch(package_id):
        raise ValueError("invalid package id")
    version = str(manifest.get("version", "")).strip()
    if not version:
        raise ValueError("package version is missing")
    manifest["id"] = package_id
    manifest["version"] = version
    manifest.setdefault("name", package_id)
    permissions = manifest.setdefault("permissions", [])
    if not isinstance(permissions, list):
        raise ValueError("permissions must be an array")
    normalized_permissions: list[str] = []
    for raw_permission in permissions:
        if not isinstance(raw_permission, str):
            raise ValueError("permissions entries must be strings")
        permission = raw_permission.strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", permission):
            raise ValueError(f"invalid package permission: {raw_permission}")
        if permission not in normalized_permissions:
            normalized_permissions.append(permission)
    manifest["permissions"] = normalized_permissions
    platforms = manifest.get("platforms")
    architectures = manifest.get("architectures")
    if not isinstance(platforms, list) or not platforms or any(p not in ("gemini", "apollo") for p in platforms):
        raise ValueError("signed package platforms are required")
    if not isinstance(architectures, list) or not architectures or any(a not in ("amd64", "x86_64", "aarch64", "arm64") for a in architectures):
        raise ValueError("signed package architectures are required")
    uninstall_state = manifest.setdefault("uninstallState", [])
    if not isinstance(uninstall_state, list):
        raise ValueError("uninstallState must be an array")
    allowed_state = f"state/apps/{package_id}"
    for entry in uninstall_state:
        normalized = normalize_member(str(entry))
        if normalized != allowed_state and not normalized.startswith(allowed_state + "/"):
            raise ValueError("uninstallState may only target package-owned app state")

    dependencies = manifest.setdefault("debianDependencies", [])
    if not isinstance(dependencies, list):
        raise ValueError("debianDependencies must be an array")
    normalized_dependencies: list[str] = []
    for dependency in dependencies:
        package = str(dependency).strip().lower()
        if not DEBIAN_PACKAGE_RE.fullmatch(package):
            raise ValueError(f"invalid Debian dependency: {dependency}")
        if package not in normalized_dependencies:
            normalized_dependencies.append(package)
    manifest["debianDependencies"] = normalized_dependencies

    system_files = manifest.setdefault("systemFiles", [])
    if not isinstance(system_files, list):
        raise ValueError("systemFiles must be an array")
    seen_sources: set[str] = set()
    seen_destinations: set[str] = set()
    normalized_system_files: list[dict[str, Any]] = []
    for raw in system_files:
        if not isinstance(raw, dict):
            raise ValueError("systemFiles entries must be objects")
        source = normalize_member(str(raw.get("source", "")))
        ownership = str(raw.get("ownership", "")).strip().lower()
        destination = str(raw.get("destination", "")).strip()
        mode_text = str(raw.get("mode", "0644")).strip()
        enable_now = bool(raw.get("enableNow", False))

        expected_prefix = "system/owned/" if ownership == "package" else             ("system/shared/" if ownership == "shared" else "")
        if not expected_prefix or not source.startswith(expected_prefix):
            raise ValueError("systemFiles ownership/source prefix mismatch")
        if not destination.startswith(SYSTEM_DESTINATION_PREFIXES):
            raise ValueError(f"system destination is not permitted: {destination}")
        if destination.startswith(SECURITY_RESERVED_DESTINATION_PREFIXES):
            raise ValueError(f"system destination is reserved for NeutronOS Security: {destination}")
        if ".." in Path(destination).parts:
            raise ValueError(f"unsafe system destination: {destination}")
        if mode_text not in {"0644", "0755"}:
            raise ValueError("systemFiles mode must be 0644 or 0755")
        if source in seen_sources or destination in seen_destinations:
            raise ValueError("duplicate system file source or destination")
        if enable_now and not destination.startswith("/etc/systemd/system/"):
            raise ValueError("enableNow is only valid for systemd unit files")

        seen_sources.add(source)
        seen_destinations.add(destination)
        normalized_system_files.append({
            "source": source,
            "destination": destination,
            "ownership": ownership,
            "mode": mode_text,
            "enableNow": enable_now,
        })
    manifest["systemFiles"] = normalized_system_files

    rebuild_required = bool(manifest.get("rebuildRequired", False))
    if rebuild_required or manifest.get("buildFiles"):
        raise ValueError("OS rebuild packages are unsupported; publish precompiled application-owned components and declare required OS capabilities")
    build_files = manifest.setdefault("buildFiles", [])
    if not isinstance(build_files, list):
        raise ValueError("buildFiles must be an array")
    normalized_build_files: list[dict[str, Any]] = []
    seen_build_sources: set[str] = set()
    seen_build_destinations: set[str] = set()
    allowed_build_prefix = f"src/package_apps/{package_id}/"
    for raw in build_files:
        if not isinstance(raw, dict):
            raise ValueError("buildFiles entries must be objects")
        source = normalize_member(str(raw.get("source", "")))
        destination = normalize_member(str(raw.get("destination", "")))
        mode_text = str(raw.get("mode", "0644")).strip()
        if not source.startswith(BUILD_MEMBER_PREFIX):
            raise ValueError("buildFiles source must live under build/owned/")
        if not destination.startswith(allowed_build_prefix):
            raise ValueError(f"buildFiles may only target {allowed_build_prefix}")
        if source in seen_build_sources or destination in seen_build_destinations:
            raise ValueError("duplicate build file source or destination")
        if mode_text not in {"0644", "0755"}:
            raise ValueError("buildFiles mode must be 0644 or 0755")
        seen_build_sources.add(source)
        seen_build_destinations.add(destination)
        normalized_build_files.append({"source": source, "destination": destination, "mode": mode_text})
    if normalized_build_files and not rebuild_required:
        raise ValueError("packages with buildFiles must declare rebuildRequired")
    if rebuild_required and not normalized_build_files:
        raise ValueError("rebuildRequired packages must declare package-owned buildFiles")
    manifest["rebuildRequired"] = rebuild_required
    manifest["buildFiles"] = normalized_build_files

    # Package-owned backends are the normal app extension model. They run out
    # of process through the OS-owned PackageAppBridgeManager and therefore do
    # never require a NeutronShell rebuild. OS changes are delivered by authenticated OS releases.
    # Legacy
    # package-owned buildFiles above.
    backend = manifest.get("backend")
    if backend is None:
        backend = {}
    if not isinstance(backend, dict):
        raise ValueError("backend must be an object")
    normalized_backend: dict[str, Any] = {}
    if backend:
        backend_type = str(backend.get("type", "")).strip().lower()
        if backend_type != "package-helper":
            raise ValueError("unsupported backend type")
        entrypoint = normalize_member(str(backend.get("entrypoint", "")))
        expected_prefix = f"scripts/apps/{package_id}/"
        if not entrypoint.startswith(expected_prefix):
            raise ValueError(f"package-helper entrypoint must live under {expected_prefix}")
        protocol = str(backend.get("protocol", "neutron-json-v1")).strip().lower()
        if protocol != "neutron-json-v1":
            raise ValueError("unsupported package-helper protocol")
        if rebuild_required:
            raise ValueError("package-helper backends must not also request a NeutronShell rebuild")
        normalized_backend = {
            "type": "package-helper",
            "entrypoint": entrypoint,
            "protocol": protocol,
            "persistent": bool(backend.get("persistent", False)),
        }
    manifest["backend"] = normalized_backend

    remote_capabilities = manifest.get("remoteCapabilities", [])
    if not isinstance(remote_capabilities, list):
        raise ValueError("remoteCapabilities must be an array")
    normalized_remote: list[dict[str, Any]] = []
    seen_remote_ids: set[str] = set()
    for raw in remote_capabilities:
        if not isinstance(raw, dict):
            raise ValueError("remoteCapabilities entries must be objects")
        capability_id = str(raw.get("id", "")).strip().lower()
        if not ID_RE.fullmatch(capability_id):
            raise ValueError("invalid remote capability id")
        if capability_id in seen_remote_ids:
            raise ValueError("duplicate remote capability id")
        provider = normalize_member(str(raw.get("provider", "")))
        expected_prefix = f"scripts/apps/{package_id}/"
        if not provider.startswith(expected_prefix):
            raise ValueError(f"remote capability provider must live under {expected_prefix}")
        broker = str(raw.get("broker", "neutronos-remote-service")).strip().lower()
        if broker != "neutronos-remote-service":
            raise ValueError("unsupported remote capability broker")
        normalized_remote.append({
            "id": capability_id,
            "provider": provider,
            "broker": broker,
            "defaultAllowed": bool(raw.get("defaultAllowed", False)),
        })
        seen_remote_ids.add(capability_id)
    manifest["remoteCapabilities"] = normalized_remote

    runtime_requirements = manifest.setdefault("runtimeRequirements", [])
    if not isinstance(runtime_requirements, list):
        raise ValueError("runtimeRequirements must be an array")
    normalized_runtime: list[dict[str, Any]] = []
    for raw in runtime_requirements:
        if not isinstance(raw, dict):
            raise ValueError("runtimeRequirements entries must be objects")
        requirement_type = str(raw.get("type", "")).strip().lower()
        if requirement_type != "jellyfin-server" or package_id != "jellyfin":
            raise ValueError("unsupported runtime requirement")
        expected = {
            "systemUnit": "jellyfin.service",
            "containerName": "jellyfin",
            "dockerUnit": "docker.service",
            "image": "jellyfin/jellyfin:10.11.11",
            "imageDigest": "sha256:aefb67e6a7ff1debdd154a78a7bbb780fd0c873d8639210a7f6a2016ad2b35db",
            "networkMode": "host",
            "restartPolicy": "unless-stopped",
            "configVolume": "neutron-jellyfin-config",
            "cacheVolume": "neutron-jellyfin-cache",
        }
        docker_packages = raw.get("dockerPackages", ["docker.io", "docker-cli"])
        if docker_packages != ["docker.io", "docker-cli"]:
            raise ValueError("unsupported jellyfin-server dockerPackages")
        normalized = {"type": requirement_type, "dockerPackages": ["docker.io", "docker-cli"]}
        for key, value in expected.items():
            actual = str(raw.get(key, value)).strip()
            if actual != value:
                raise ValueError(f"unsupported jellyfin-server {key}")
            normalized[key] = value
        roots = raw.get("mediaRoots", ["/media", "/mnt", "/srv"])
        if not isinstance(roots, list):
            raise ValueError("jellyfin-server mediaRoots must be an array")
        allowed_roots = ["/media", "/mnt", "/srv"]
        normalized_roots = []
        for root in roots:
            value = str(root).strip()
            if value not in allowed_roots:
                raise ValueError(f"unsupported Jellyfin media root: {value}")
            if value not in normalized_roots:
                normalized_roots.append(value)
        normalized["mediaRoots"] = normalized_roots
        normalized["autoDeviceDri"] = bool(raw.get("autoDeviceDri", True))
        normalized_runtime.append(normalized)
    if len(normalized_runtime) > 1:
        raise ValueError("only one runtime requirement is currently supported")
    manifest["runtimeRequirements"] = normalized_runtime
    return manifest


def validate_package_systemd_unit(package_id: str, destination: str, data: bytes) -> None:
    if not destination.startswith("/etc/systemd/system/") or not destination.endswith((".service", ".socket", ".timer", ".path")):
        return
    if len(data) > 1024 * 1024:
        raise ValueError("package systemd unit is unreasonably large")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("package systemd units must be UTF-8 text") from exc
    for pattern in SECURITY_RESERVED_UNIT_PATTERNS:
        if pattern.search(text):
            raise ValueError(
                f"package systemd unit requests Security-reserved authority: {destination}"
            )


def inspect_archive(package_path: Path) -> tuple[dict[str, Any], list[str]]:
    if not package_path.is_file():
        raise ValueError("package file does not exist")
    if package_path.suffix.lower() not in (".napp", ".zip"):
        raise ValueError("package must use .napp or .zip")

    with zipfile.ZipFile(package_path, "r") as archive:
        try:
            manifest = json.loads(archive.read("manifest.json").decode("utf-8"))
        except KeyError as exc:
            raise ValueError("manifest.json is missing") from exc
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("manifest.json is invalid") from exc

        if not isinstance(manifest, dict):
            raise ValueError("manifest.json must be an object")
        manifest = validate_manifest(manifest)

        members: list[str] = []
        system_members: set[str] = set()
        build_members: set[str] = set()
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = normalize_member(info.filename)
            if name in ("manifest.json", "manifest.json.sig"):
                continue
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ValueError(f"symbolic links are not permitted: {name}")
            if name.startswith("payload/"):
                relative = name[len("payload/") :]
                if not relative.startswith(ALLOWED_PREFIXES):
                    raise ValueError(f"package path is not permitted: {relative}")
                members.append(relative)
                continue
            if name.startswith(SYSTEM_MEMBER_PREFIXES):
                system_members.add(name)
                continue
            if name.startswith(BUILD_MEMBER_PREFIX):
                build_members.add(name)
                continue
            raise ValueError(f"unexpected archive member: {name}")

        backend = manifest.get("backend") or {}
        if backend:
            entrypoint = str(backend.get("entrypoint") or "")
            if entrypoint not in members:
                raise ValueError("package-helper entrypoint is missing from payload")
            info = archive.getinfo("payload/" + entrypoint)
            mode = info.external_attr >> 16
            if not (mode & stat.S_IXUSR):
                raise ValueError("package-helper entrypoint must be executable")

        for capability in manifest.get("remoteCapabilities", []):
            provider = str(capability.get("provider") or "")
            if provider not in members:
                raise ValueError(f"remote capability provider is missing from payload: {provider}")

        declared_build_members = {entry["source"] for entry in manifest.get("buildFiles", [])}
        if build_members != declared_build_members:
            missing = sorted(declared_build_members - build_members)
            undeclared = sorted(build_members - declared_build_members)
            details = []
            if missing:
                details.append("missing: " + ", ".join(missing))
            if undeclared:
                details.append("undeclared: " + ", ".join(undeclared))
            raise ValueError("buildFiles/archive mismatch (" + "; ".join(details) + ")")

        declared_system_members = {entry["source"] for entry in manifest.get("systemFiles", [])}
        if system_members != declared_system_members:
            missing = sorted(declared_system_members - system_members)
            undeclared = sorted(system_members - declared_system_members)
            details = []
            if missing:
                details.append("missing: " + ", ".join(missing))
            if undeclared:
                details.append("undeclared: " + ", ".join(undeclared))
            raise ValueError("systemFiles/archive mismatch (" + "; ".join(details) + ")")

        for entry in manifest.get("systemFiles", []):
            destination = str(entry.get("destination") or "")
            if destination.startswith("/etc/systemd/system/"):
                validate_package_systemd_unit(
                    manifest["id"], destination, archive.read(str(entry["source"]))
                )

    expected_app_prefix = f"qml/apps/{manifest['id']}/"
    if not any(member == expected_app_prefix + "Main.qml" for member in members):
        raise ValueError(f"payload must contain {expected_app_prefix}Main.qml")
    if not any(member == expected_app_prefix + "app.json" for member in members):
        raise ValueError(f"payload must contain {expected_app_prefix}app.json")
    return manifest, members


def safe_target(root: Path, relative: str) -> Path:
    target = (root / relative).resolve(strict=False)
    root_resolved = root.resolve()
    if target != root_resolved and root_resolved not in target.parents:
        raise ValueError(f"target escapes NeutronOS root: {relative}")
    return target


def app_store_paths(state_root: Path) -> tuple[Path, Path, Path]:
    """Return transaction state, registry, and writable installed payload."""
    state = state_root / "apps"
    return state, state / "installed.json", state / "payload"


def load_registry(state_root: Path) -> dict[str, Any]:
    _, path, _ = app_store_paths(state_root)
    data = load_json(path, {"schema": SCHEMA, "packages": {}})
    if not isinstance(data, dict):
        data = {"schema": SCHEMA, "packages": {}}
    if not isinstance(data.get("packages"), dict):
        data["packages"] = {}
    data["schema"] = SCHEMA
    return data


def snapshot_path(state_root: Path, package_id: str) -> Path:
    state, _, _ = app_store_paths(state_root)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    return state / "rollback" / package_id / stamp


def managed_target(payload_root: Path, state_root: Path, relative: str) -> Path:
    if relative == "state" or relative.startswith("state/"):
        suffix = relative.removeprefix("state/") if relative != "state" else ""
        return safe_target(state_root, suffix)
    return safe_target(payload_root, relative)


def backup_paths(payload_root: Path, state_root: Path,
                 relatives: list[str], snapshot: Path) -> list[str]:
    backed_up: list[str] = []
    for relative in sorted(set(relatives)):
        source = managed_target(payload_root, state_root, relative)
        if not source.exists() and not source.is_symlink():
            continue
        destination = snapshot / "files" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination, symlinks=False)
        else:
            shutil.copy2(source, destination)
        backed_up.append(relative)
    return backed_up


def restore_snapshot(payload_root: Path, state_root: Path,
                     snapshot: Path, remove_relatives: list[str]) -> None:
    for relative in sorted(set(remove_relatives), reverse=True):
        target = managed_target(payload_root, state_root, relative)
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target, ignore_errors=True)
        else:
            try:
                target.unlink()
            except FileNotFoundError:
                pass

    files_root = snapshot / "files"
    if files_root.exists():
        for source in sorted(files_root.rglob("*")):
            if source.is_dir():
                continue
            relative = source.relative_to(files_root).as_posix()
            destination = managed_target(payload_root, state_root, relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)


def cleanup_empty_parents(payload_root: Path, state_root: Path,
                          relatives: list[str]) -> None:
    for relative in sorted(set(relatives), key=lambda item: item.count("/"), reverse=True):
        base = state_root.resolve() if relative.startswith("state/") else payload_root.resolve()
        current = managed_target(payload_root, state_root, relative).parent
        while current != base and base in current.parents:
            try:
                current.rmdir()
            except OSError:
                break
            current = current.parent


# APP_STORE_QML_RUNTIME_GENERATIONS_V3
#
# QQmlEngine caches imported QML components by URL. Cache-busting only Main.qml
# is insufficient because relative imports keep stable payload URLs between
# package versions. Each successful App Store transaction therefore creates an
# immutable, generation-specific mirror of the verified payload and records the
# generation-specific Main.qml path in installed.json. Relative imports inherit
# that unique directory and cannot collide with an older compiled generation.


def runtime_package_root(state_root: Path, package_id: str) -> Path:
    package_id = str(package_id or "").strip().lower()
    if not ID_RE.fullmatch(package_id):
        raise ValueError("invalid runtime package id")
    state, _, _ = app_store_paths(state_root)
    return state / "runtime" / package_id


def _runtime_generation_name(version: str, package_sha256: str = "") -> str:
    clean_version = re.sub(r"[^A-Za-z0-9._-]+", "_", str(version or "unknown").strip())[:80]
    digest = re.sub(r"[^a-fA-F0-9]", "", str(package_sha256 or ""))[:16].lower()
    nonce = f"{time.time_ns():x}"
    return f"{clean_version}-{digest or 'local'}-{nonce}"


def _link_or_copy_verified(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


# APP_STORE_SHARED_QML_RUNTIME_DEPS_V4
#
# Official App Store QML apps are allowed to import OS-owned shared QML via
# relative quoted imports (for example qml/apps/games/Main.qml importing
# "../../components"). Runtime generations must preserve that path topology.
# Package-owned bytes remain hash-verified from installed.json; OS-owned shared
# QML is snapshotted from <NeutronOS root>/qml into the same immutable runtime
# generation. Only dependencies that resolve inside the OS qml tree are copied,
# and cross-app imports are rejected.

_QML_LOCAL_IMPORT_RE = re.compile(
    r'^\s*import\s+(["\'])([^"\']+)\1(?:\s+as\s+[A-Za-z_][A-Za-z0-9_]*)?\s*(?://.*)?$')


def _copy_os_qml_dependency(root: Path, temporary_payload: Path,
                            relative: str) -> list[str]:
    clean = posixpath.normpath(str(relative or '').replace('\\', '/')).lstrip('/')
    if clean == 'qml' or not clean.startswith('qml/'):
        raise ValueError(f"shared QML dependency escapes qml root: {relative}")
    qml_relative = clean[len('qml/'):]
    if qml_relative == 'apps' or qml_relative.startswith('apps/'):
        raise ValueError(f"cross-app QML dependency is not allowed: {relative}")

    os_qml_root = (root / 'qml').resolve()
    source = (root / clean).resolve()
    try:
        source.relative_to(os_qml_root)
    except ValueError as exc:
        raise ValueError(f"shared QML dependency escapes OS qml root: {relative}") from exc
    if not source.exists():
        raise ValueError(f"shared QML dependency is missing from NeutronOS: {clean}")

    destination = safe_target(temporary_payload, clean)
    copied: list[str] = []

    def copy_one(src: Path, dst: Path) -> None:
        resolved = src.resolve()
        try:
            resolved.relative_to(os_qml_root)
        except ValueError as exc:
            raise ValueError(f"shared QML source escapes OS qml root: {src}") from exc
        if not resolved.is_file():
            return
        dst.parent.mkdir(parents=True, exist_ok=True)
        # Package-owned runtime files always win if a shared directory happens
        # to overlap an already materialized package path.
        if not dst.exists():
            shutil.copy2(resolved, dst)
        copied.append(dst.relative_to(temporary_payload).as_posix())

    if source.is_file():
        copy_one(source, destination)
    elif source.is_dir():
        for child in sorted(source.rglob('*')):
            if child.is_dir():
                continue
            relative_child = child.relative_to(source)
            copy_one(child, destination / relative_child)
    else:
        raise ValueError(f"unsupported shared QML dependency type: {clean}")
    return copied


def materialize_shared_qml_dependencies(root: Path, temporary_payload: Path,
                                        package_id: str) -> dict[str, str]:
    runtime_qml = temporary_payload / 'qml'
    package_qml_root = runtime_qml / 'apps' / package_id
    if not package_qml_root.is_dir():
        return {}

    scanned: set[str] = set()
    shared_hashes: dict[str, str] = {}
    # Re-scan until no new QML files appear. Copying a shared component directory
    # can expose another relative import to a sibling shared directory.
    while True:
        candidates = sorted(runtime_qml.rglob('*.qml'))
        pending = [path for path in candidates
                   if path.relative_to(temporary_payload).as_posix() not in scanned]
        if not pending:
            break
        for qml_file in pending:
            qml_rel = qml_file.relative_to(temporary_payload).as_posix()
            scanned.add(qml_rel)
            try:
                text = qml_file.read_text(encoding='utf-8')
            except UnicodeDecodeError as exc:
                raise ValueError(f"QML dependency is not UTF-8: {qml_rel}") from exc
            parent_rel = posixpath.dirname(qml_rel)
            for raw_line in text.splitlines():
                match = _QML_LOCAL_IMPORT_RE.match(raw_line)
                if not match:
                    continue
                import_path = match.group(2).strip()
                if not import_path:
                    continue
                target_rel = posixpath.normpath(posixpath.join(parent_rel, import_path))
                if target_rel == '..' or target_rel.startswith('../'):
                    raise ValueError(
                        f"local QML import escapes runtime payload: {qml_rel}: {import_path}")
                runtime_target = safe_target(temporary_payload, target_rel)
                if runtime_target.exists():
                    continue
                copied = _copy_os_qml_dependency(root, temporary_payload, target_rel)
                for copied_rel in copied:
                    copied_path = safe_target(temporary_payload, copied_rel)
                    if copied_path.is_file():
                        shared_hashes[copied_rel] = hashlib.sha256(
                            copied_path.read_bytes()).hexdigest()

    return dict(sorted(shared_hashes.items()))


def create_runtime_generation(root: Path, state_root: Path, payload_root: Path,
                              package_id: str, version: str,
                              files: list[str], file_hashes: dict[str, str],
                              package_sha256: str = "") -> dict[str, Any]:
    package_root = runtime_package_root(state_root, package_id)
    package_root.mkdir(parents=True, exist_ok=True)
    generation = _runtime_generation_name(version, package_sha256)
    generation_root = package_root / generation
    temporary_root = package_root / ("." + generation + ".staging")
    temporary_payload = temporary_root / "payload"
    shutil.rmtree(temporary_root, ignore_errors=True)
    shutil.rmtree(generation_root, ignore_errors=True)

    try:
        for relative in sorted(set(str(value) for value in files)):
            if relative == "state" or relative.startswith("state/"):
                continue
            expected = str(file_hashes.get(relative, "")).strip().lower()
            if not re.fullmatch(r"[0-9a-f]{64}", expected):
                raise ValueError(f"runtime generation is missing a trusted hash: {relative}")
            source = safe_target(payload_root, relative)
            if not source.is_file():
                raise ValueError(f"runtime source file is missing: {relative}")
            actual = hashlib.sha256(source.read_bytes()).hexdigest()
            if actual != expected:
                raise ValueError(f"runtime source hash mismatch: {relative}")
            destination = safe_target(temporary_payload, relative)
            _link_or_copy_verified(source, destination)
            runtime_hash = hashlib.sha256(destination.read_bytes()).hexdigest()
            if runtime_hash != expected:
                raise ValueError(f"runtime generation hash mismatch: {relative}")

        shared_qml_hashes = materialize_shared_qml_dependencies(
            root, temporary_payload, package_id)

        main_relative = f"qml/apps/{package_id}/Main.qml"
        manifest_relative = f"qml/apps/{package_id}/app.json"
        runtime_main = safe_target(temporary_payload, main_relative)
        runtime_manifest = safe_target(temporary_payload, manifest_relative)
        if not runtime_main.is_file() or not runtime_manifest.is_file():
            raise ValueError("runtime generation is missing Main.qml or app.json")
        manifest = load_json(runtime_manifest, {})
        if not isinstance(manifest, dict):
            raise ValueError("runtime app manifest is invalid")
        if str(manifest.get("id", "")).strip().lower() != package_id:
            raise ValueError("runtime app manifest id mismatch")
        if str(manifest.get("version", "")).strip() != str(version).strip():
            raise ValueError("runtime app manifest version mismatch")

        os.replace(temporary_root, generation_root)
    except Exception:
        shutil.rmtree(temporary_root, ignore_errors=True)
        shutil.rmtree(generation_root, ignore_errors=True)
        raise

    return {
        "runtimeGeneration": generation,
        "runtimeRoot": str(generation_root),
        "runtimeQmlSource": str(generation_root / "payload" / main_relative),
        "runtimeActivatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "runtimeSharedQmlSha256": shared_qml_hashes,
    }


def prune_runtime_generations(state_root: Path, package_id: str,
                              keep_roots: list[str]) -> None:
    package_root = runtime_package_root(state_root, package_id)
    if not package_root.exists():
        return
    package_root_resolved = package_root.resolve()
    keep: set[Path] = set()
    for raw in keep_roots:
        text = str(raw or "").strip()
        if not text:
            continue
        candidate = Path(text).expanduser().resolve(strict=False)
        if candidate.parent == package_root_resolved:
            keep.add(candidate)
    for child in package_root.iterdir():
        if child.name.startswith("."):
            shutil.rmtree(child, ignore_errors=True)
            continue
        resolved = child.resolve(strict=False)
        if resolved not in keep:
            shutil.rmtree(child, ignore_errors=True)
    try:
        package_root.rmdir()
    except OSError:
        pass


def verify_registered_payload(payload_root: Path,
                              package: dict[str, Any]) -> tuple[list[str], dict[str, str]]:
    files = [str(value) for value in package.get("files", [])]
    hashes_raw = package.get("fileSha256", {})
    if not isinstance(hashes_raw, dict):
        raise ValueError("installed package has no file hash registry")
    hashes = {str(key): str(value).strip().lower() for key, value in hashes_raw.items()}
    for relative in files:
        if relative == "state" or relative.startswith("state/"):
            continue
        expected = hashes.get(relative, "")
        if not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError(f"installed package hash registry is incomplete: {relative}")
        source = safe_target(payload_root, relative)
        if not source.is_file():
            raise ValueError(f"installed package file is missing: {relative}")
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"installed package file hash mismatch: {relative}")
    return files, hashes


def refresh_runtime_for_registered_package(root: Path, state_root: Path, payload_root: Path,
                                           package_id: str,
                                           package: dict[str, Any]) -> dict[str, Any]:
    files, hashes = verify_registered_payload(payload_root, package)
    version = str(package.get("version", "")).strip()
    if not version:
        raise ValueError(f"installed package version is missing: {package_id}")
    package_sha = str(package.get("packageSha256", "")).strip().lower()
    return create_runtime_generation(
        root, state_root, payload_root, package_id, version, files, hashes, package_sha)


def repair_runtime_command(args: argparse.Namespace) -> None:
    root = Path(args.root).expanduser().resolve()
    state_root = Path(args.state_root).expanduser().resolve()
    _, registry_path, payload_root = app_store_paths(state_root)
    registry = load_registry(state_root)
    requested = str(args.package_id or "").strip().lower()
    if requested and not ID_RE.fullmatch(requested):
        raise ValueError("invalid package id")

    package_ids = [requested] if requested else sorted(registry["packages"])
    updated: list[str] = []
    for package_id in package_ids:
        package = registry["packages"].get(package_id)
        if not isinstance(package, dict):
            if requested:
                raise ValueError("package is not managed by the App Store")
            continue
        old_root = str(package.get("runtimeRoot", "")).strip()
        runtime = refresh_runtime_for_registered_package(
            root, state_root, payload_root, package_id, package)
        package.update(runtime)
        registry["packages"][package_id] = package
        # Each package repair is independently committed only after its payload
        # hashes and new runtime generation verify. If a later package is
        # unhealthy, already-repaired packages remain valid and referenced.
        atomic_json(registry_path, registry)
        prune_runtime_generations(
            state_root, package_id, [runtime["runtimeRoot"], old_root])
        updated.append(package_id)

    emit(True, "Rebuilt App Store QML runtime generations",
         packages=updated, count=len(updated))


def legacy_source_candidates(package_id: str) -> list[str]:
    return [
        f"qml/apps/{package_id}",
        f"themes/Default/apps/icons/{package_id}.png",
        f"themes/Default/apps/posters/{package_id}.png",
    ]


def backup_legacy_source(root: Path, relatives: list[str], snapshot: Path) -> list[str]:
    backed_up: list[str] = []
    legacy_root = snapshot / "legacy-source"
    for relative in relatives:
        source = safe_target(root, relative)
        if not source.exists() and not source.is_symlink():
            continue
        destination = legacy_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir() and not source.is_symlink():
            shutil.copytree(source, destination, symlinks=False)
        else:
            shutil.copy2(source, destination)
        backed_up.append(relative)
    return backed_up


def remove_legacy_source(root: Path, relatives: list[str]) -> list[str]:
    removed: list[str] = []
    for relative in sorted(set(relatives), key=lambda item: item.count("/"), reverse=True):
        target = safe_target(root, relative)
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            try:
                target.unlink()
            except FileNotFoundError:
                continue
        removed.append(relative)
    return removed


def restore_legacy_source(root: Path, snapshot: Path, relatives: list[str]) -> None:
    if root.resolve() == Path("/opt/neutronos"):
        return
    legacy_root = snapshot / "legacy-source"
    for relative in relatives:
        source = legacy_root / relative
        if not source.exists() and not source.is_symlink():
            continue
        destination = safe_target(root, relative)
        if destination.is_dir() and not destination.is_symlink():
            shutil.rmtree(destination)
        else:
            try:
                destination.unlink()
            except FileNotFoundError:
                pass
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir() and not source.is_symlink():
            shutil.copytree(source, destination, symlinks=False)
        else:
            shutil.copy2(source, destination)


def parse_version(value: str) -> tuple[list[int], str]:
    text = str(value or "").strip()
    core, sep, suffix = text.partition("-")
    numbers: list[int] = []
    for part in core.split("."):
        if not part.isdigit():
            raise ValueError(f"unsupported version for adoption: {text}")
        numbers.append(int(part))
    while len(numbers) < 3:
        numbers.append(0)
    return numbers, suffix if sep else ""


def version_is_newer(available: str, installed: str) -> bool:
    left_numbers, left_suffix = parse_version(available)
    right_numbers, right_suffix = parse_version(installed)
    width = max(len(left_numbers), len(right_numbers))
    left_numbers += [0] * (width - len(left_numbers))
    right_numbers += [0] * (width - len(right_numbers))
    if left_numbers != right_numbers:
        return left_numbers > right_numbers
    if left_suffix == right_suffix:
        return False
    if not left_suffix:
        return True
    if not right_suffix:
        return False
    return left_suffix > right_suffix


def backup_build_files(root: Path, relatives: list[str], snapshot: Path) -> list[str]:
    if root.resolve() == Path("/opt/neutronos"):
        return []  # Signed native archives are snapshotted by the root transaction.
    backed_up: list[str] = []
    backup_root = snapshot / "build-source"
    for relative in relatives:
        source = safe_target(root, relative)
        if not source.exists() and not source.is_symlink():
            continue
        if not source.is_file() or source.is_symlink():
            raise ValueError(f"unsupported existing build destination: {relative}")
        destination = backup_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        backed_up.append(relative)
    return backed_up


def restore_build_files(root: Path, snapshot: Path, affected: list[str], backed_up: list[str]) -> None:
    if root.resolve() == Path("/opt/neutronos"):
        return  # The existing privileged rollback restores the signed archive.
    backup_root = snapshot / "build-source"
    backed = set(backed_up)
    for relative in affected:
        destination = safe_target(root, relative)
        if relative in backed:
            source = backup_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".appstore-restore")
            shutil.copy2(source, temporary)
            os.replace(temporary, destination)
        else:
            try:
                destination.unlink()
            except FileNotFoundError:
                pass
    for relative in sorted(affected, key=lambda value: value.count("/"), reverse=True):
        current = safe_target(root, relative).parent
        stop = safe_target(root, "src/package_apps")
        while current != stop and stop in current.parents:
            try:
                current.rmdir()
            except OSError:
                break
            current = current.parent


def extract_build_files(package_path: Path, manifest: dict[str, Any], staging: Path) -> list[tuple[str, Path, int]]:
    rows: list[tuple[str, Path, int]] = []
    with zipfile.ZipFile(package_path, "r") as archive:
        for entry in manifest.get("buildFiles", []):
            source_name = entry["source"]
            destination_relative = entry["destination"]
            destination = staging / destination_relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(source_name, "r") as source, destination.open("wb") as target:
                shutil.copyfileobj(source, target)
            mode = int(str(entry.get("mode", "0644")), 8)
            destination.chmod(mode)
            rows.append((destination_relative, destination, mode))
    return rows


def apply_build_files(root: Path, extracted: list[tuple[str, Path, int]], stale: list[str]) -> list[str]:
    if root.resolve() == Path("/opt/neutronos"):
        return [relative for relative, _, _ in extracted]  # SYSTEM remains root-owned.
    installed: list[str] = []
    for relative, source, mode in extracted:
        destination = safe_target(root, relative)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".appstore-new")
        shutil.copy2(source, temporary)
        temporary.chmod(mode)
        os.replace(temporary, destination)
        installed.append(relative)
    for relative in stale:
        target = safe_target(root, relative)
        try:
            target.unlink()
        except FileNotFoundError:
            pass
    return installed


def extract_payload(package_path: Path, staging: Path) -> list[str]:
    written: list[str] = []
    with zipfile.ZipFile(package_path, "r") as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = normalize_member(info.filename)
            if name == "manifest.json" or not name.startswith("payload/"):
                continue
            relative = name[len("payload/") :]
            destination = staging / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as source, destination.open("wb") as target:
                shutil.copyfileobj(source, target)
            mode = info.external_attr >> 16
            if relative.startswith("scripts/apps/"):
                destination.chmod(0o755)
            else:
                destination.chmod(0o644 if not mode else mode & 0o777)
            written.append(relative)
    return written


def parse_json_output(output: str) -> dict[str, Any]:
    for raw in reversed(output.splitlines()):
        line = raw.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return {}


def run_privileged(arguments: list[str]) -> dict[str, Any]:
    command = ["sudo", "-n", PRIVILEGED_HELPER] + arguments
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output: list[str] = []
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 1800.0
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(command, 1800)
            events = selector.select(timeout=min(1.0, remaining))
            for key, _ in events:
                line = key.fileobj.readline()
                if not line:
                    continue
                output.append(line)
                # Forward structured root-side progress immediately so the Qt
                # manager can move the transaction modal through real stages.
                try:
                    value = json.loads(line.strip())
                except (json.JSONDecodeError, ValueError):
                    value = None
                if isinstance(value, dict) and value.get("event") == "progress":
                    print(json.dumps(value, separators=(",", ":"), sort_keys=True), flush=True)
            if process.poll() is not None:
                tail = process.stdout.read()
                if tail:
                    output.append(tail)
                    for line in tail.splitlines():
                        try:
                            value = json.loads(line.strip())
                        except (json.JSONDecodeError, ValueError):
                            value = None
                        if isinstance(value, dict) and value.get("event") == "progress":
                            print(json.dumps(value, separators=(",", ":"), sort_keys=True), flush=True)
                break
        return_code = process.wait(timeout=5)
    except BaseException:
        process.kill()
        process.wait(timeout=5)
        raise
    finally:
        selector.close()
    text = "".join(output)
    payload = parse_json_output(text)
    if return_code != 0 or not payload.get("success", False):
        message = str(payload.get("message") or text.strip() or
                      "privileged App Store operation failed")
        raise ValueError(message)
    return payload


def package_needs_privileged_install(manifest: dict[str, Any]) -> bool:
    return bool(manifest.get("debianDependencies") or manifest.get("systemFiles") or manifest.get("runtimeRequirements") or manifest.get("rebuildRequired") or manifest.get("remoteCapabilities"))


def privileged_install(args: argparse.Namespace, package_id: str) -> dict[str, Any]:
    payload = run_privileged([
        "appstore-install-signed",
        str(Path(args.package).expanduser().resolve()),
        args.expected_sha256.strip().lower(),
        package_id,
    ])
    return payload


def privileged_uninstall(package_id: str) -> dict[str, Any]:
    return run_privileged(["appstore-uninstall", package_id])


def privileged_rollback(token: str) -> None:
    if not token:
        return
    run_privileged(["appstore-root-rollback", token])


def transactional_install(args: argparse.Namespace) -> None:
    # Inspect, verify and extract one snapshot of the downloaded bytes. Root
    # operations make a second immutable snapshot through the Security guard.
    with tempfile.TemporaryDirectory(prefix="neutronos-napp-transaction-") as temporary:
        original = args.package
        snapshot = Path(temporary) / "package.napp"
        snapshot.write_bytes(Path(original).expanduser().resolve().read_bytes())
        snapshot.chmod(0o400)
        args.package = str(snapshot)
        try:
            _transactional_install_snapshot(args)
        finally:
            args.package = original


def _transactional_install_snapshot(args: argparse.Namespace) -> None:
    emit_progress(0.32, "INSPECT PACKAGE", "Reading package manifest and signed transaction metadata")
    root = Path(args.root).expanduser().resolve()
    state_root = Path(args.state_root).expanduser().resolve()
    state, registry_path, payload_root = app_store_paths(state_root)
    package_path = Path(args.package).expanduser().resolve()
    package_bytes = package_path.read_bytes()
    actual_package_sha256 = hashlib.sha256(package_bytes).hexdigest()
    if not args.expected_sha256 or args.allow_unsigned:
        raise ValueError("Gemini requires a signed package from a verified catalog")
    verified = subprocess.run([
        "/usr/local/libexec/neutronos-napp-verify", "verify", str(package_path),
        "--expected-sha", args.expected_sha256.strip().lower(),
        "--expected-id", args.expected_id.strip().lower(),
        "--expected-version", args.expected_version.strip()
    ], capture_output=True, text=True, timeout=30)
    if verified.returncode:
        raise ValueError("NAPP release verification failed: " + verified.stderr.strip()[:400])
    manifest, members = inspect_archive(package_path)
    package_id = manifest["id"]
    emit_progress(0.36, "PACKAGE PLAN", "Validated package manifest", sorted(members)[:24])
    version = manifest["version"]

    if args.expected_id and package_id != args.expected_id:
        raise ValueError("package id does not match catalog")
    if args.expected_version and version != args.expected_version:
        raise ValueError("package version does not match catalog")
    if manifest.get("rebuildRequired") and args.allow_unsigned:
        raise ValueError("unsigned Developer Mode packages cannot modify rebuild-owned NeutronOS source")
    if manifest.get("rebuildRequired") and (not args.expected_sha256):
        raise ValueError("rebuild-required packages must come from a trusted signed repository")

    legacy_paths: list[str] = []
    legacy_version = ""
    if args.adopt_legacy_source:
        if args.allow_unsigned:
            raise ValueError("unsigned packages cannot adopt a source-tree app")
        if args.source != "neutronos-official":
            raise ValueError("only the official repository may adopt a source-tree app")
        if not args.expected_sha256:
            raise ValueError("source-tree adoption requires a trusted signed package")
        legacy_manifest_path = safe_target(root, f"qml/apps/{package_id}/app.json")
        legacy_main_path = safe_target(root, f"qml/apps/{package_id}/Main.qml")
        if not legacy_manifest_path.is_file() or not legacy_main_path.is_file():
            raise ValueError("legacy source app is not present for adoption")
        legacy_manifest = load_json(legacy_manifest_path, {})
        if not isinstance(legacy_manifest, dict) or str(legacy_manifest.get("id", "")).strip().lower() != package_id:
            raise ValueError("legacy source app id does not match package")
        legacy_version = str(legacy_manifest.get("version", "")).strip()
        if args.legacy_version and legacy_version != args.legacy_version.strip():
            raise ValueError("legacy source app version changed before adoption")
        if not legacy_version or not version_is_newer(version, legacy_version):
            raise ValueError("package is not newer than the legacy source app")
        legacy_paths = [
            relative for relative in legacy_source_candidates(package_id)
            if safe_target(root, relative).exists() or safe_target(root, relative).is_symlink()
        ]
        if f"qml/apps/{package_id}" not in legacy_paths:
            raise ValueError("legacy source app directory is missing")

    state.mkdir(parents=True, exist_ok=True)
    payload_root.mkdir(parents=True, exist_ok=True)
    registry = load_registry(state_root)
    previous = registry["packages"].get(package_id, {})
    if previous and "gemini" not in previous.get("platforms", []):
        raise ValueError("installed package identity belongs to an unknown or different platform")

    # If this package is already App Store-managed, an older source-tree copy
    # with the same id must never continue shadowing the writable package
    # payload. Retire that duplicate as part of the same signed transaction.
    # This applies only to official signed, non-rebuild packages that are
    # already present in the App Store registry.
    if (not legacy_paths and isinstance(previous, dict) and previous and
            args.source == "neutronos-official" and
            args.expected_sha256 and
            not manifest.get("rebuildRequired") and not manifest.get("buildFiles")):
        legacy_manifest_path = safe_target(root, f"qml/apps/{package_id}/app.json")
        legacy_main_path = safe_target(root, f"qml/apps/{package_id}/Main.qml")
        if legacy_main_path.is_file():
            legacy_manifest = load_json(legacy_manifest_path, {})
            if (isinstance(legacy_manifest, dict) and
                    str(legacy_manifest.get("id", "")).strip().lower() == package_id):
                legacy_version = str(legacy_manifest.get("version", "")).strip()
                legacy_paths = [
                    relative for relative in legacy_source_candidates(package_id)
                    if safe_target(root, relative).exists() or safe_target(root, relative).is_symlink()
                ]

    if root.resolve() == Path("/opt/neutronos"):
        legacy_paths = []  # Canonical managed payload wins over immutable SYSTEM QML.

    previous_files = list(previous.get("files", [])) if isinstance(previous, dict) else []
    previous_build_files = [str(value) for value in previous.get("buildFiles", [])] if isinstance(previous, dict) else []
    new_build_files = [str(entry["destination"]) for entry in manifest.get("buildFiles", [])]
    affected_build_files = sorted(set(previous_build_files + new_build_files))
    affected = sorted(set(previous_files + members))

    emit_progress(0.40, "CREATE ROLLBACK POINT", "Snapshotting the current package-owned files before changes")
    snapshot = snapshot_path(state_root, package_id)
    snapshot.mkdir(parents=True, exist_ok=False)
    atomic_json(snapshot / "registry-before.json", registry)
    backed_up = backup_paths(payload_root, state_root, affected, snapshot)
    build_backed_up = backup_build_files(root, affected_build_files, snapshot)
    legacy_backed_up = backup_legacy_source(root, legacy_paths, snapshot) if legacy_paths else []
    atomic_json(snapshot / "snapshot.json", {
        "schema": SCHEMA,
        "packageId": package_id,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "backedUp": backed_up,
        "affected": affected,
        "affectedBuildFiles": affected_build_files,
        "buildFilesBackedUp": build_backed_up,
        "legacySourceAdoption": bool(legacy_paths),
        "legacySourceBackedUp": legacy_backed_up,
        "legacyVersion": legacy_version,
    })

    staging = state / "staging" / f"{package_id}-{os.getpid()}"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    installed_now: list[str] = []
    installed_build_now: list[str] = []
    removed_legacy: list[str] = []
    root_rollback_token = ""
    rebuild_ticket = ""
    runtime_metadata: dict[str, str] = {}
    previous_runtime_root = ""
    try:
        emit_progress(0.44, "EXTRACT PAYLOAD", "Extracting verified application files into transaction staging")
        extracted = extract_payload(package_path, staging)
        emit_progress(0.48, "INSTALL APP FILES", "Replacing App Store-managed application files", sorted(extracted)[:32])
        for relative in extracted:
            source = staging / relative
            if hashlib.sha256(source.read_bytes()).hexdigest() != manifest["fileHashes"].get("payload/" + relative):
                raise ValueError("extracted payload disagrees with its signed file digest: " + relative)
            destination = managed_target(payload_root, state_root, relative)
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".appstore-new")
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
            shutil.copy2(source, temporary)
            os.replace(temporary, destination)
            installed_now.append(relative)

        emit_progress(0.54, "VERIFY INSTALLED FILES", "Hash-checking every installed application file")

        # APP_STORE_PAYLOAD_VERIFY_V2:
        # Do not advance installed.json until bytes actually placed in writable
        # App Store storage match the already-verified archive.
        payload_hashes: dict[str, str] = {}
        for relative in extracted:
            source = staging / relative
            destination = managed_target(payload_root, state_root, relative)
            if not destination.is_file():
                raise ValueError(f"installed payload file is missing after replacement: {relative}")
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            destination_hash = hashlib.sha256(destination.read_bytes()).hexdigest()
            if source_hash != destination_hash or destination_hash != manifest["fileHashes"].get("payload/" + relative):
                raise ValueError(f"installed payload verification failed: {relative}")
            payload_hashes[relative] = destination_hash

        runtime_main_relative = f"qml/apps/{package_id}/Main.qml"
        runtime_manifest_relative = f"qml/apps/{package_id}/app.json"
        if runtime_main_relative in extracted:
            runtime_main = managed_target(payload_root, state_root, runtime_main_relative)
            if not runtime_main.is_file():
                raise ValueError("installed app Main.qml is missing after replacement")
        if runtime_manifest_relative in extracted:
            runtime_manifest_path = managed_target(
                payload_root, state_root, runtime_manifest_relative)
            runtime_manifest = load_json(runtime_manifest_path, {})
            if not isinstance(runtime_manifest, dict):
                raise ValueError("installed app manifest is invalid after replacement")
            if str(runtime_manifest.get("id", "")).strip().lower() != package_id:
                raise ValueError("installed app manifest id does not match package")
            if str(runtime_manifest.get("version", "")).strip() != version:
                raise ValueError("installed app manifest version does not match package")

        stale_payload = sorted(set(previous_files) - set(extracted))
        if stale_payload:
            emit_progress(0.58, "REMOVE STALE FILES", "Removing files no longer owned by this package version", stale_payload[:32])
        for relative in stale_payload:
            target = managed_target(payload_root, state_root, relative)
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                try:
                    target.unlink()
                except FileNotFoundError:
                    pass
        cleanup_empty_parents(payload_root, state_root, stale_payload)

        emit_progress(0.60, "ACTIVATE QML GENERATION", "Building a cache-isolated runtime from verified package bytes")
        previous_runtime_root = str(previous.get("runtimeRoot", "")).strip() if isinstance(previous, dict) else ""
        runtime_metadata = create_runtime_generation(
            root, state_root, payload_root, package_id, version,
            sorted(extracted), payload_hashes, actual_package_sha256)

        # Old package-owned source is retired on migration; new NAPPs contain
        # only verified precompiled app payloads. No OS source is staged/built.
        if previous_build_files:
            apply_build_files(root, [], sorted(set(previous_build_files)))

        if package_needs_privileged_install(manifest):
            emit_progress(0.68, "SYSTEM DEPENDENCIES", "Handing verified system changes to the privileged App Store transaction")
            if args.allow_unsigned:
                raise ValueError("unsigned Developer Mode packages cannot install system files or Debian dependencies")
            if not args.expected_sha256:
                raise ValueError("privileged package content requires a trusted signed repository package")
            privileged_payload = privileged_install(args, package_id)
            root_rollback_token = str(privileged_payload.get("rollbackToken") or "")
            rebuild_ticket = str(privileged_payload.get("rebuildTicket") or "")

        if legacy_paths:
            removed_legacy = remove_legacy_source(root, legacy_paths)
            if sorted(removed_legacy) != sorted(legacy_paths):
                raise ValueError("legacy source app could not be retired completely")

        snapshot_info = load_json(snapshot / "snapshot.json", {})
        if isinstance(snapshot_info, dict):
            snapshot_info["rootRollbackToken"] = root_rollback_token
            atomic_json(snapshot / "snapshot.json", snapshot_info)

        emit_progress(0.94, "COMMIT APP STORE STATE", "Recording the completed package transaction")
        registry["packages"][package_id] = {
            "id": package_id,
            "name": manifest.get("name", package_id),
            "version": version,
            "source": args.source or "unknown",
            "installedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "files": sorted(extracted),
            "fileSha256": payload_hashes,
            "permissions": manifest.get("permissions", []),
            "uninstallState": manifest.get("uninstallState", []),
            "rollbackPath": str(snapshot),
            "rollbackAvailable": True,
            "developerModePackage": False,
            "platforms": manifest["platforms"],
            "architectures": manifest["architectures"],
            "systemManaged": package_needs_privileged_install(manifest),
            "debianDependencies": manifest.get("debianDependencies", []),
            "systemFiles": manifest.get("systemFiles", []),
            "runtimeRequirements": manifest.get("runtimeRequirements", []),
            "rebuildRequired": bool(manifest.get("rebuildRequired", False)),
            "buildFiles": sorted(new_build_files),
            "backend": manifest.get("backend", {}),
            "remoteCapabilities": manifest.get("remoteCapabilities", []),
            "adoptedLegacySource": bool(legacy_paths),
            "legacyVersion": legacy_version,
            "legacySourcePaths": sorted(legacy_paths),
            "packageSha256": actual_package_sha256,
            **runtime_metadata,
        }
        atomic_json(registry_path, registry)
        prune_runtime_generations(
            state_root, package_id,
            [runtime_metadata.get("runtimeRoot", ""), previous_runtime_root])
    except Exception:
        runtime_root = str(runtime_metadata.get("runtimeRoot", "")).strip()
        if runtime_root:
            shutil.rmtree(runtime_root, ignore_errors=True)
        if root_rollback_token:
            try:
                privileged_rollback(root_rollback_token)
            except Exception as rollback_error:
                print(f"WARNING: privileged rollback failed: {rollback_error}", file=sys.stderr)
        restore_snapshot(payload_root, state_root, snapshot, installed_now + previous_files)
        restore_build_files(root, snapshot, affected_build_files, build_backed_up)
        if legacy_paths:
            restore_legacy_source(root, snapshot, legacy_backed_up)
        previous_registry = load_json(snapshot / "registry-before.json", registry)
        atomic_json(registry_path, previous_registry)
        raise
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    emit_progress(0.99, "FINALIZE", "Package transaction complete")
    emit(True, f"Installed {manifest.get('name', package_id)} {version}",
         packageId=package_id, version=version, rollbackPath=str(snapshot),
         requiresRebuild=bool(manifest.get("rebuildRequired", False)), rebuildTicket=rebuild_ticket)


def transactional_uninstall(args: argparse.Namespace) -> None:
    emit_progress(0.06, "LOAD REMOVAL PLAN", "Loading exact App Store ownership metadata")
    root = Path(args.root).expanduser().resolve()
    state_root = Path(args.state_root).expanduser().resolve()
    _, registry_path, payload_root = app_store_paths(state_root)
    package_id = args.package_id.strip().lower()
    registry = load_registry(state_root)
    current = registry["packages"].get(package_id)
    if not isinstance(current, dict):
        raise ValueError("package is not managed by the App Store")
    files = list(current.get("files", []))
    uninstall_state = list(current.get("uninstallState", []))
    build_files = [str(value) for value in current.get("buildFiles", [])]
    rebuild_required = False  # Removal never builds or replaces OS components.
    affected = files + uninstall_state
    removal_preview = sorted(set(files + uninstall_state + build_files))
    emit_progress(0.10, "REMOVAL PLAN", "Only package-owned files will be removed; shared dependencies are preserved", removal_preview[:40])
    emit_progress(0.14, "CREATE ROLLBACK POINT", "Snapshotting package-owned files before removal")
    snapshot = snapshot_path(state_root, package_id)
    snapshot.mkdir(parents=True, exist_ok=False)
    atomic_json(snapshot / "registry-before.json", registry)
    backed_up = backup_paths(payload_root, state_root, affected, snapshot)
    build_backed_up = backup_build_files(root, build_files, snapshot)
    atomic_json(snapshot / "snapshot.json", {
        "schema": SCHEMA,
        "packageId": package_id,
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "backedUp": backed_up,
        "affected": affected,
        "affectedBuildFiles": build_files,
        "buildFilesBackedUp": build_backed_up,
        "operation": "uninstall",
    })

    removed: list[str] = []
    dependency_eligibility: dict[str, Any] = {}
    root_rollback_token = ""
    rebuild_ticket = ""
    try:
        if bool(current.get("systemManaged", False)):
            emit_progress(0.18, "REMOVE SYSTEM COMPONENTS", "Removing package-owned privileged files and services")
            privileged_payload = privileged_uninstall(package_id)
            dependency_eligibility = privileged_payload.get("dependencyEligibility", {})
            root_rollback_token = str(privileged_payload.get("rollbackToken") or "")
            rebuild_ticket = str(privileged_payload.get("rebuildTicket") or "")
            snapshot_info = load_json(snapshot / "snapshot.json", {})
            if isinstance(snapshot_info, dict):
                snapshot_info["rootRollbackToken"] = root_rollback_token
                atomic_json(snapshot / "snapshot.json", snapshot_info)

        emit_progress(0.52, "REMOVE APP FILES", "Removing App Store payload and package-owned state", sorted(affected)[:40])
        for relative in affected:
            target = managed_target(payload_root, state_root, relative)
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                try:
                    target.unlink()
                except FileNotFoundError:
                    pass
            removed.append(relative)
        cleanup_empty_parents(payload_root, state_root, affected)
        if build_files:
            emit_progress(0.70, "REMOVE SOURCE COMPONENTS", "Removing signed package-owned source files", sorted(build_files)[:40])
        for relative in ([] if root.resolve() == Path("/opt/neutronos") else build_files):
            target = safe_target(root, relative)
            try:
                target.unlink()
            except FileNotFoundError:
                pass
        emit_progress(0.86, "COMMIT UNINSTALL", "Retiring App Store ownership after all removals succeeded")
        del registry["packages"][package_id]
        atomic_json(registry_path, registry)
        shutil.rmtree(runtime_package_root(state_root, package_id), ignore_errors=True)
    except Exception:
        if root_rollback_token:
            try:
                privileged_rollback(root_rollback_token)
            except Exception as rollback_error:
                print(f"WARNING: privileged rollback failed: {rollback_error}", file=sys.stderr)
        restore_snapshot(payload_root, state_root, snapshot, removed)
        restore_build_files(root, snapshot, build_files, build_backed_up)
        atomic_json(registry_path, load_json(snapshot / "registry-before.json", registry))
        raise

    eligible=dependency_eligibility.get("eligible", [])
    emit_progress(0.99, "FINALIZE", "Application removed. Dependencies retained; APT removal eligibility is available for separate review.", eligible)
    emit(True, f"Uninstalled {current.get('name', package_id)}",
         packageId=package_id, version=str(current.get("version") or ""), rollbackPath=str(snapshot),
         requiresRebuild=rebuild_required, rebuildTicket=rebuild_ticket, dependencyEligibility=dependency_eligibility)


def transactional_rollback(args: argparse.Namespace) -> None:
    root = Path(args.root).expanduser().resolve()
    state_root = Path(args.state_root).expanduser().resolve()
    state, registry_path, payload_root = app_store_paths(state_root)
    package_id = args.package_id.strip().lower()
    registry = load_registry(state_root)
    current = registry["packages"].get(package_id, {})
    snapshot_text = current.get("rollbackPath", "") if isinstance(current, dict) else ""

    if snapshot_text:
        snapshot = Path(snapshot_text)
    else:
        rollback_root = state / "rollback" / package_id
        candidates = sorted((p for p in rollback_root.iterdir() if p.is_dir()), reverse=True) \
            if rollback_root.exists() else []
        if not candidates:
            raise ValueError("no rollback snapshot is available")
        snapshot = candidates[0]

    snapshot_info = load_json(snapshot / "snapshot.json", {})
    previous_registry = load_json(snapshot / "registry-before.json", None)
    if not isinstance(snapshot_info, dict) or not isinstance(previous_registry, dict):
        raise ValueError("rollback snapshot is incomplete")

    affected = list(snapshot_info.get("affected", []))
    root_rollback_token = str(snapshot_info.get("rootRollbackToken") or "")
    if root_rollback_token:
        privileged_rollback(root_rollback_token)
    restore_snapshot(payload_root, state_root, snapshot, affected)
    cleanup_empty_parents(payload_root, state_root, affected)
    restore_build_files(root, snapshot, list(snapshot_info.get("affectedBuildFiles", [])),
                        list(snapshot_info.get("buildFilesBackedUp", [])))
    if snapshot_info.get("legacySourceAdoption", False):
        restore_legacy_source(root, snapshot, list(snapshot_info.get("legacySourceBackedUp", [])))

    previous_package = previous_registry.get("packages", {}).get(package_id)
    if isinstance(previous_package, dict):
        old_root = str(previous_package.get("runtimeRoot", "")).strip()
        runtime = refresh_runtime_for_registered_package(
            root, state_root, payload_root, package_id, previous_package)
        previous_package.update(runtime)
        previous_registry["packages"][package_id] = previous_package
        atomic_json(registry_path, previous_registry)
        prune_runtime_generations(
            state_root, package_id, [runtime.get("runtimeRoot", ""), old_root])
    else:
        atomic_json(registry_path, previous_registry)
        shutil.rmtree(runtime_package_root(state_root, package_id), ignore_errors=True)
    emit(True, f"Rolled back {package_id}", packageId=package_id)


def inspect_command(args: argparse.Namespace) -> None:
    manifest, members = inspect_archive(Path(args.package).expanduser().resolve())
    print(json.dumps({"success": True, "message": "Package is valid",
                      "manifest": manifest, "files": members},
                     separators=(",", ":"), sort_keys=True))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)

    inspect = sub.add_parser("inspect")
    inspect.add_argument("--root", required=True)
    inspect.add_argument("--package", required=True)

    install = sub.add_parser("install")
    install.add_argument("--root", required=True)
    install.add_argument("--state-root", required=True)
    install.add_argument("--package", required=True)
    install.add_argument("--expected-id", default="")
    install.add_argument("--expected-version", default="")
    install.add_argument("--source", default="")
    install.add_argument("--expected-sha256", default="")
    install.add_argument("--allow-unsigned", action="store_true")
    install.add_argument("--adopt-legacy-source", action="store_true")
    install.add_argument("--legacy-version", default="")

    uninstall = sub.add_parser("uninstall")
    uninstall.add_argument("--root", required=True)
    uninstall.add_argument("--state-root", required=True)
    uninstall.add_argument("--package-id", required=True)

    rollback = sub.add_parser("rollback")
    rollback.add_argument("--root", required=True)
    rollback.add_argument("--state-root", required=True)
    rollback.add_argument("--package-id", required=True)

    repair_runtime = sub.add_parser("repair-runtime")
    repair_runtime.add_argument("--root", required=True)
    repair_runtime.add_argument("--state-root", required=True)
    repair_runtime.add_argument("--package-id", default="")
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "inspect":
            inspect_command(args)
        elif args.command == "install":
            transactional_install(args)
        elif args.command == "uninstall":
            transactional_uninstall(args)
        elif args.command == "rollback":
            transactional_rollback(args)
        elif args.command == "repair-runtime":
            repair_runtime_command(args)
        else:
            raise ValueError("unknown operation")
        return 0
    except (ValueError, OSError, zipfile.BadZipFile, shutil.Error) as exc:
        emit(False, str(exc))
        return 1
    except Exception as exc:  # defensive transaction boundary
        emit(False, f"unexpected package transaction failure: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
