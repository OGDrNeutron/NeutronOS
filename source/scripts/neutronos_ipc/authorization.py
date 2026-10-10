"""Central server-side authorization policy for privileged NeutronOS IPC."""

from __future__ import annotations

import grp
import json
import os
import pwd
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .server import AuthorizationGrant, PeerCredentials


class AuthorizationError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    executable: str
    command: tuple[str, ...]
    start_time_ticks: int


def process_identity(pid: int) -> ProcessIdentity:
    try:
        executable = os.readlink(f"/proc/{pid}/exe")
        command_raw = Path(f"/proc/{pid}/cmdline").read_bytes()
        command = tuple(part.decode("utf-8", errors="replace") for part in command_raw.split(b"\0") if part)
        stat_text = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        command_end = stat_text.rfind(")")
        if command_end < 0:
            raise ValueError("invalid process stat")
        # Fields after the command name begin at proc(5) field 3; starttime is field 22.
        stat_fields = stat_text[command_end + 1:].split()
        start_time = int(stat_fields[19])
    except (OSError, ValueError, IndexError) as exc:
        raise AuthorizationError("process_unverified", "requesting process identity could not be verified") from exc
    return ProcessIdentity(pid=pid, executable=executable, command=command, start_time_ticks=start_time)


def _trusted_policy_file(path: Path, require_root_owner: bool) -> None:
    try:
        info = path.stat()
    except OSError as exc:
        raise AuthorizationError("policy_unavailable", "authorization policy is unavailable") from exc
    if not stat.S_ISREG(info.st_mode):
        raise AuthorizationError("policy_untrusted", "authorization policy must be a regular file")
    if require_root_owner and (info.st_uid != 0 or info.st_mode & 0o022):
        raise AuthorizationError("policy_untrusted", "authorization policy must be root-owned and not group/other writable")


def _groups_for_process(pid: int, expected_uid: int) -> set[str]:
    try:
        lines = Path(f"/proc/{pid}/status").read_text(encoding="ascii").splitlines()
    except OSError as exc:
        raise AuthorizationError("process_unverified", "requesting process groups could not be verified") from exc
    uid_values: list[int] = []
    group_ids: list[int] = []
    for line in lines:
        if line.startswith("Uid:"):
            uid_values = [int(value) for value in line.split()[1:]]
        elif line.startswith("Groups:"):
            group_ids = [int(value) for value in line.split()[1:]]
    if not uid_values or any(value != expected_uid for value in uid_values):
        raise AuthorizationError("process_unverified", "requesting process UID state changed")
    result = set()
    for group_id in group_ids:
        try:
            result.add(grp.getgrgid(group_id).gr_name)
        except KeyError:
            continue
    return result


def _control_groups_for_process(pid: int) -> set[str]:
    try:
        lines = Path(f"/proc/{pid}/cgroup").read_text(encoding="ascii").splitlines()
    except OSError as exc:
        raise AuthorizationError("process_unverified", "requesting process control group could not be verified") from exc
    return {line.split(":", 2)[2].rstrip("/") or "/" for line in lines if line.count(":") >= 2}


class AuthorizationPolicy:
    def __init__(self, document: dict[str, Any], source: Path):
        if document.get("schema") != 1 or document.get("defaultDeny") is not True:
            raise AuthorizationError("policy_invalid", "authorization policy must use schema 1 and default deny")
        roles = document.get("roles")
        operations = document.get("operations")
        disabled = document.get("disabledOperations", {})
        if not isinstance(roles, dict) or not isinstance(operations, dict) or not isinstance(disabled, dict):
            raise AuthorizationError("policy_invalid", "authorization policy tables are invalid")
        self.source = source
        self.roles = roles
        self.operations = operations
        self.disabled_operations = disabled

    def enabled_operations(self) -> list[str]:
        return sorted(name for name, rule in self.operations.items()
                      if isinstance(rule, dict) and rule.get("enabled") is True)

    @classmethod
    def load(cls, path: Path, *, require_root_owner: bool = True) -> "AuthorizationPolicy":
        _trusted_policy_file(path, require_root_owner)
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise AuthorizationError("policy_invalid", "authorization policy is not valid JSON") from exc
        if not isinstance(document, dict):
            raise AuthorizationError("policy_invalid", "authorization policy must be an object")
        return cls(document, path)

    @staticmethod
    def _validate_arguments(operation: str, arguments: dict[str, Any], schema: dict[str, Any]) -> None:
        if not isinstance(arguments, dict):
            raise AuthorizationError("invalid_arguments", "operation arguments must be an object")
        properties = schema.get("properties", {})
        required = schema.get("required", [])
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise AuthorizationError("policy_invalid", f"argument policy for {operation} is invalid")
        unknown = set(arguments) - set(properties)
        if unknown:
            raise AuthorizationError("invalid_arguments", f"unknown argument for {operation}: {sorted(unknown)[0]}")
        missing = [name for name in required if name not in arguments]
        if missing:
            raise AuthorizationError("invalid_arguments", f"missing required argument for {operation}: {missing[0]}")
        for name, value in arguments.items():
            rule = properties[name]
            expected = rule.get("type")
            valid = (
                (expected == "boolean" and type(value) is bool) or
                (expected == "integer" and type(value) is int) or
                (expected == "string" and isinstance(value, str)) or
                (expected == "object" and isinstance(value, dict)) or
                (expected == "array" and isinstance(value, list))
            )
            if not valid:
                raise AuthorizationError("invalid_arguments", f"argument {name} has the wrong type")
            if isinstance(value, str):
                if len(value) < int(rule.get("minLength", 0)) or len(value) > int(rule.get("maxLength", 4096)):
                    raise AuthorizationError("invalid_arguments", f"argument {name} has an invalid length")
                if "enum" in rule and value not in rule["enum"]:
                    raise AuthorizationError("invalid_arguments", f"argument {name} is not an allowed value")
            if type(value) is int:
                if value < int(rule.get("minimum", value)) or value > int(rule.get("maximum", value)):
                    raise AuthorizationError("invalid_arguments", f"argument {name} is outside the allowed range")

    def authorize(self, peer: PeerCredentials, session: dict[str, str],
                  application: dict[str, str], operation: str,
                  arguments: dict[str, Any]) -> AuthorizationGrant:
        if operation in self.disabled_operations:
            raise AuthorizationError("operation_disabled", str(self.disabled_operations[operation]))
        rule = self.operations.get(operation)
        if not isinstance(rule, dict):
            raise AuthorizationError("unknown_operation", "operation is not present in the authorization table")
        if rule.get("enabled") is not True:
            raise AuthorizationError("operation_disabled", "operation is disabled by policy")
        try:
            account = pwd.getpwnam(session["user"])
        except KeyError as exc:
            raise AuthorizationError("user_unverified", "session user does not exist") from exc
        potential_system_role = any(
            isinstance(role, dict) and type(role.get("peerUid")) is int and
            role.get("peerUid") == peer.uid
            for role in self.roles.values()
        )
        if account.pw_uid != peer.uid and not potential_system_role:
            raise AuthorizationError("user_mismatch", "peer UID does not match the authenticated session user")
        identity = process_identity(peer.pid)
        groups = _groups_for_process(peer.pid, peer.uid)
        control_groups = _control_groups_for_process(peer.pid)
        permission = str(rule.get("permission", ""))
        capability = str(rule.get("capability", ""))
        if not permission or not capability:
            raise AuthorizationError("policy_invalid", "operation has no permission or capability")
        matched_role = ""
        capability_denied = False
        for role_name, role in self.roles.items():
            if not isinstance(role, dict):
                continue
            required_groups = set(str(value) for value in role.get("groups", []))
            permissions = set(str(value) for value in role.get("permissions", []))
            capabilities = set(str(value) for value in role.get("capabilities", []))
            trusted_executables = set(str(value) for value in role.get("executables", []))
            trusted_units = set(str(value) for value in role.get("controlGroups", []))
            peer_uid = role.get("peerUid")
            ordinary_session = peer_uid is None and account.pw_uid == peer.uid and required_groups.issubset(groups)
            system_shell = (
                type(peer_uid) is int and peer.uid == peer_uid and
                identity.executable in trusted_executables and
                bool(trusted_units.intersection(control_groups))
            )
            if ordinary_session or system_shell:
                if permission not in permissions:
                    continue
                if capability not in capabilities:
                    capability_denied = True
                    continue
                matched_role = str(role_name)
                break
        if not matched_role:
            if account.pw_uid != peer.uid:
                raise AuthorizationError("user_mismatch", "peer UID does not match the authenticated session user")
            if capability_denied:
                raise AuthorizationError("capability_denied", "session role lacks the required server-side capability")
            raise AuthorizationError("permission_denied", "session user lacks the required server-side permission")
        self._validate_arguments(operation, arguments, rule.get("arguments", {}))
        return AuthorizationGrant(
            capability=capability,
            permission=permission,
            principal=matched_role,
            process_executable=identity.executable,
            process_start_time=identity.start_time_ticks,
            application_identity_strength="asserted-context",
        )
