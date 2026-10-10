#!/usr/bin/env python3
"""Diagnostic client for the authenticated NeutronOS Security IPC endpoint."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import sys
from pathlib import Path

# Installed clients live in /usr/local/sbin while the shared package lives in
# /usr/local/lib/neutronos. Source-tree execution continues to resolve the
# sibling package without relying on this fallback.
installed_library = Path("/usr/local/lib/neutronos")
if installed_library.is_dir():
    sys.path.insert(0, str(installed_library))

from neutronos_ipc import IpcClient, ProtocolError


def current_session() -> str:
    explicit = os.environ.get("XDG_SESSION_ID", "").strip()
    if explicit:
        return explicit
    try:
        value = Path(f"/proc/{os.getpid()}/sessionid").read_text(encoding="ascii").strip()
        if value and value != "4294967295":
            return value
    except OSError:
        pass
    raise RuntimeError("No authenticated logind session is associated with this process; set XDG_SESSION_ID only to the actual current session")


def main() -> int:
    parser = argparse.ArgumentParser(description="Query the NeutronOS Security daemon over authenticated local IPC")
    parser.add_argument("operation", help="Versioned Security service operation name")
    parser.add_argument("--arguments-json", default="{}",
                        help="JSON object passed as operation arguments (default: {})")
    parser.add_argument("--socket", default="/run/neutronos/security/control.sock")
    parser.add_argument("--session")
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()
    try:
        arguments = json.loads(args.arguments_json)
        if not isinstance(arguments, dict):
            raise ValueError("--arguments-json must decode to an object")
        user = pwd.getpwuid(os.getuid()).pw_name
        response = IpcClient(Path(args.socket), timeout=max(0.1, min(args.timeout, 30.0))).request(
            "security", args.operation, arguments,
            session_id=args.session or current_session(), user=user,
            application_id="neutronos.securityctl",
            application_instance=f"pid:{os.getpid()}",
        )
    except (OSError, RuntimeError, ProtocolError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        return 1
    print(json.dumps(response, indent=2, sort_keys=True))
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
