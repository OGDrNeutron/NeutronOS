#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path
from typing import Any

APP_ID = "neutronremotesystems"
BROKER_NAME = "neutronos-remote-service"
PROTOCOL_VERSION = 1
ADMIN_SOCKET_PATH = Path(os.environ.get("NEUTRONOS_REMOTE_ADMIN_SOCKET", "/run/neutronos/remote-service-admin.sock"))
PROVIDER_SOCKET_PATH = Path(os.environ.get("NEUTRONOS_REMOTE_PROVIDER_SOCKET", "/run/neutronos/remote-service-provider.sock"))
MAX_MESSAGE = 1024 * 1024


def emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    sys.stdout.flush()


def broker_request(payload: dict[str, Any]) -> dict[str, Any]:
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(data) > MAX_MESSAGE:
        raise RuntimeError("broker request exceeded message limit")
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3.0)
    try:
        client.connect(str(ADMIN_SOCKET_PATH))
        client.sendall(data)
        result = bytearray()
        while len(result) <= MAX_MESSAGE:
            chunk = client.recv(min(65536, MAX_MESSAGE + 1 - len(result)))
            if not chunk:
                break
            result.extend(chunk)
            if b"\n" in chunk:
                break
    finally:
        client.close()
    if len(result) > MAX_MESSAGE:
        raise RuntimeError("broker response exceeded message limit")
    line = bytes(result).split(b"\n", 1)[0].strip()
    parsed = json.loads(line.decode("utf-8")) if line else {}
    if not isinstance(parsed, dict):
        raise RuntimeError("broker returned invalid JSON")
    return parsed


def emit_broker_state(response: dict[str, Any] | None = None, error: str = "") -> None:
    response = response or {}
    emit({
        "type": "broker-state",
        "online": bool(response.get("ok", False)) and not error,
        "broker": str(response.get("broker") or BROKER_NAME),
        "protocolVersion": int(response.get("protocolVersion") or PROTOCOL_VERSION),
        "message": error or ("Remote service broker is ready" if response.get("ok") else str(response.get("error") or "Remote service broker is unavailable")),
    })


def refresh() -> None:
    try:
        hello = broker_request({"op": "hello"})
        if not hello.get("ok"):
            raise RuntimeError(str(hello.get("error") or "broker rejected gatekeeper client"))
        emit_broker_state(hello)
        web_controller = broker_request({"op": "web-controller-status"})
        if web_controller.get("ok"):
            emit({"type": "web-controller", **(web_controller.get("webController") or {})})
        else:
            emit({"type": "web-controller", "available": False, "enabled": False, "active": False,
                  "message": str(web_controller.get("error") or "Web controller status unavailable")})
        services = broker_request({"op": "system-services"})
        if services.get("ok"):
            emit({"type": "system-services", "services": services.get("services", [])})
        else:
            emit({"type": "system-services", "services": [], "message": str(services.get("error") or "System services unavailable")})
        discovered = broker_request({"op": "discover"})
        if not discovered.get("ok"):
            raise RuntimeError(str(discovered.get("error") or "provider discovery failed"))
        emit({
            "type": "providers",
            "protocol": BROKER_NAME,
            "protocolVersion": PROTOCOL_VERSION,
            "providers": discovered.get("providers", []),
        })
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        emit_broker_state(error=str(exc))
        emit({"type": "providers", "protocol": BROKER_NAME, "protocolVersion": PROTOCOL_VERSION, "providers": []})


def handle(message: dict[str, Any]) -> None:
    action = str(message.get("action") or "").strip().lower()
    if action in {"open", "refresh"}:
        refresh()
        return
    if action == "protocol":
        emit({
            "type": "protocol",
            "broker": BROKER_NAME,
            "protocolVersion": PROTOCOL_VERSION,
            "providerActions": ["remote.describe", "remote.refresh", "remote.set"],
            "leaseSocket": str(PROVIDER_SOCKET_PATH),
        })
        return
    if action == "grant":
        response = broker_request({
            "op": "grant",
            "appId": str(message.get("appId") or "").strip().lower(),
            "durationCode": str(message.get("durationCode") or "").strip().lower(),
        })
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "grant failed"))
        emit({"type": "grant-updated", "appId": response.get("appId", ""), "grant": response.get("grant", {})})
        refresh()
        return
    if action == "revoke":
        response = broker_request({
            "op": "revoke",
            "appId": str(message.get("appId") or "").strip().lower(),
            "reason": str(message.get("reason") or "manual"),
        })
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "revoke failed"))
        emit({"type": "grant-updated", "appId": response.get("appId", ""), "grant": response.get("grant", {})})
        refresh()
        return
    if action == "status":
        response = broker_request({"op": "status", "appId": str(message.get("appId") or "").strip().lower()})
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "status failed"))
        emit({"type": "grant-updated", "appId": response.get("appId", ""), "grant": response.get("grant", {})})
        return
    if action == "web-controller-set":
        requested = message.get("enabled")
        if not isinstance(requested, bool):
            raise RuntimeError("web controller enabled value must be boolean")
        response = broker_request({"op": "web-controller-set", "enabled": requested})
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "web controller update failed"))
        emit({"type": "web-controller", **(response.get("webController") or {})})
        services = broker_request({"op": "system-services"})
        if services.get("ok"):
            emit({"type": "system-services", "services": services.get("services", [])})
        return
    if action == "web-controller-status":
        response = broker_request({"op": "web-controller-status"})
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "web controller status failed"))
        emit({"type": "web-controller", **(response.get("webController") or {})})
        return
    if action == "web-controller-port-set":
        use_default = bool(message.get("systemDefault", False))
        payload = {"op": "web-controller-port-set", "systemDefault": use_default}
        if not use_default:
            payload["port"] = int(message.get("port") or 0)
        response = broker_request(payload)
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "web controller port update failed"))
        emit({"type": "web-controller", **(response.get("webController") or {})})
        emit({"type": "system-services", "services": response.get("services", [])})
        return
    if action == "audit":
        response = broker_request({"op": "audit", "limit": int(message.get("limit") or 100)})
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error") or "audit read failed"))
        emit({"type": "audit", "rows": response.get("audit", [])})
        return
    emit({"type": "error", "message": "Unsupported Remote Systems action"})


def main() -> int:
    emit({"type": "state", "stage": "READY", "message": "Neutron Remote Systems bridge started", "protocolVersion": PROTOCOL_VERSION})
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError("message must be a JSON object")
            handle(value)
        except Exception as exc:
            emit({"type": "error", "message": str(exc)})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
