"""Verification of a claimed local session against logind and kernel peer data."""

from __future__ import annotations

import os
import pwd
import subprocess
from pathlib import Path
from typing import Callable

from .server import PeerCredentials


def _loginctl_properties(session_id: str) -> dict[str, str]:
    if not session_id or any(character.isspace() for character in session_id):
        return {}
    try:
        completed = subprocess.run(
            [
                "loginctl", "show-session", session_id,
                "--property=Active", "--property=State", "--property=User",
                "--property=Name", "--property=Remote", "--property=Leader",
                "--property=ControlGroup", "--property=Seat", "--property=Type",
                "--property=Class", "--no-pager",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if completed.returncode != 0:
        return {}
    result: dict[str, str] = {}
    for line in completed.stdout.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            result[key] = value
    return result


def _process_control_groups(pid: int) -> list[str]:
    try:
        lines = Path(f"/proc/{pid}/cgroup").read_text(encoding="ascii").splitlines()
    except OSError:
        return []
    groups = []
    for line in lines:
        parts = line.split(":", 2)
        if len(parts) == 3 and parts[2]:
            groups.append(parts[2].rstrip("/") or "/")
    return groups


def _parent_pid(pid: int) -> int:
    try:
        fields = Path(f"/proc/{pid}/stat").read_text(encoding="ascii").split()
        return int(fields[3]) if len(fields) > 3 else 0
    except (OSError, ValueError):
        return 0


def _descends_from(pid: int, leader: int, parent_loader: Callable[[int], int]) -> bool:
    seen = set()
    current = pid
    while current > 1 and current not in seen:
        if current == leader:
            return True
        seen.add(current)
        current = parent_loader(current)
    return current == leader


def verify_active_session(
    peer: PeerCredentials,
    session: dict[str, str],
    *,
    property_loader: Callable[[str], dict[str, str]] = _loginctl_properties,
    cgroup_loader: Callable[[int], list[str]] = _process_control_groups,
    parent_loader: Callable[[int], int] = _parent_pid,
    trusted_system_shell: tuple[int, str, str, str] | None = None,
) -> bool:
    """Return true only when logind confirms an active session for the peer UID.

    Application identity is intentionally not considered here. A QML manifest is
    not proof of identity while built-in apps share the NeutronShell process.
    """
    try:
        account = pwd.getpwnam(session["user"])
    except (KeyError, TypeError):
        return False
    system_shell = False
    if account.pw_uid != peer.uid:
        if trusted_system_shell is None:
            return False
        trusted_uid, trusted_user, executable, unit = trusted_system_shell
        if peer.uid != trusted_uid:
            return False
        # NeutronShell runs as its service account, while its PAM session is
        # the signed-in human. Bind this exception to the exact executable and
        # systemd unit below; a caller-supplied username alone grants nothing.
        if session.get("user") != trusted_user and not (
            1000 <= account.pw_uid <= 60000
            and account.pw_dir == "/NeutronOS/" + session.get("user", "")
            and account.pw_shell.startswith("/")
            and not account.pw_shell.endswith(("/nologin", "/false"))
        ):
            return False
        try:
            actual_executable = os.readlink(f"/proc/{peer.pid}/exe")
        except OSError:
            return False
        groups = cgroup_loader(peer.pid)
        if actual_executable != executable or not any(
            group == unit or group.endswith("/" + unit.lstrip("/"))
            for group in groups
        ):
            return False
        system_shell = True
    properties = property_loader(session["id"])
    if properties.get("Active") != "yes" or properties.get("State") not in {"active", "online"}:
        return False
    # Controller-combo authentication belongs to the verified shell; it does
    # not open a human PAM/password session. In that case use the existing
    # active local display session, never a synthetic ID or an SSH session.
    display_session = system_shell and (
        properties.get("User") == str(trusted_uid)
        and properties.get("Name") == trusted_user
        and properties.get("Remote") == "no"
        and bool(properties.get("Seat"))
        and properties.get("Type") in {"tty", "wayland", "x11"}
        and properties.get("Class") in {"user", "user-early"}
    )
    if not display_session:
        if properties.get("User") and properties["User"] != str(account.pw_uid):
            return False
        if properties.get("Name") and properties["Name"] != session["user"]:
            return False
    try:
        process_stat = os.stat(f"/proc/{peer.pid}")
    except OSError:
        return False
    if process_stat.st_uid != peer.uid:
        return False
    if system_shell:
        # The shell cannot adopt somebody's SSH login as a local PAM session.
        if session.get("user") != trusted_user and properties.get("Remote") != "no":
            return False
        return True
    control_group = properties.get("ControlGroup", "").rstrip("/")
    if control_group:
        if any(group == control_group or group.startswith(control_group + "/")
               for group in cgroup_loader(peer.pid)):
            return True
    try:
        leader = int(properties.get("Leader", "0"))
    except ValueError:
        leader = 0
    return leader > 0 and _descends_from(peer.pid, leader, parent_loader)
