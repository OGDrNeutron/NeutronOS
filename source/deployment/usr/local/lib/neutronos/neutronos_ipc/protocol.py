"""Wire format and strict schema validation for NeutronOS privileged IPC."""

from __future__ import annotations

import json
import re
import secrets
import struct
import time
import uuid
from datetime import datetime, timezone
from typing import Any

PROTOCOL_NAME = "neutronos.ipc"
PROTOCOL_VERSION = 1
SUPPORTED_VERSIONS = (PROTOCOL_VERSION,)
MAX_REQUEST_BYTES = 64 * 1024
MAX_RESPONSE_BYTES = 1024 * 1024
DEFAULT_CLOCK_SKEW_SECONDS = 30
NONCE_BYTES = 32

_TOKEN = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")
_SESSION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
_NONCE = re.compile(r"^[0-9a-f]{64}$")
_REQUEST_KEYS = {
    "protocol", "version", "requestId", "service", "operation", "arguments",
    "nonce", "timestamp", "session", "application",
}
_SESSION_KEYS = {"id", "user"}
_APPLICATION_KEYS = {"id", "instance"}


class ProtocolError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_timestamp(value: Any) -> float:
    if not isinstance(value, str) or len(value) > 40:
        raise ProtocolError("invalid_timestamp", "timestamp must be an RFC 3339 string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ProtocolError("invalid_timestamp", "timestamp is not valid RFC 3339") from exc
    if parsed.tzinfo is None:
        raise ProtocolError("invalid_timestamp", "timestamp must include a timezone")
    return parsed.timestamp()


def _string(value: Any, field: str, maximum: int, token: bool = False) -> str:
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise ProtocolError("invalid_schema", f"{field} must be a non-empty string of at most {maximum} characters")
    if token and not _TOKEN.fullmatch(value):
        raise ProtocolError("invalid_schema", f"{field} contains unsupported characters")
    return value


def validate_request(
    request: Any,
    *,
    now: float | None = None,
    clock_skew_seconds: int = DEFAULT_CLOCK_SKEW_SECONDS,
) -> dict[str, Any]:
    if not isinstance(request, dict) or set(request) != _REQUEST_KEYS:
        raise ProtocolError("invalid_schema", "request fields do not match protocol version 1")
    if request.get("protocol") != PROTOCOL_NAME:
        raise ProtocolError("unsupported_protocol", "unsupported IPC protocol")
    version = request.get("version")
    if type(version) is not int or version not in SUPPORTED_VERSIONS:
        raise ProtocolError("unsupported_version", f"supported versions: {list(SUPPORTED_VERSIONS)}")
    try:
        uuid.UUID(_string(request.get("requestId"), "requestId", 36))
    except ValueError as exc:
        raise ProtocolError("invalid_schema", "requestId must be a UUID") from exc
    _string(request.get("service"), "service", 64, token=True)
    _string(request.get("operation"), "operation", 64, token=True)
    arguments = request.get("arguments")
    if not isinstance(arguments, dict):
        raise ProtocolError("invalid_schema", "arguments must be an object")
    nonce = request.get("nonce")
    if not isinstance(nonce, str) or not _NONCE.fullmatch(nonce):
        raise ProtocolError("invalid_nonce", "nonce must contain 32 random bytes encoded as lowercase hexadecimal")
    stamp = parse_timestamp(request.get("timestamp"))
    current = time.time() if now is None else now
    if abs(current - stamp) > clock_skew_seconds:
        raise ProtocolError("stale_request", "request timestamp is outside the accepted window")
    session = request.get("session")
    if not isinstance(session, dict) or set(session) != _SESSION_KEYS:
        raise ProtocolError("invalid_schema", "session must contain exactly id and user")
    session_id = _string(session.get("id"), "session.id", 128)
    if not _SESSION_ID.fullmatch(session_id):
        raise ProtocolError("invalid_schema", "session.id contains unsupported characters")
    _string(session.get("user"), "session.user", 64)
    application = request.get("application")
    if not isinstance(application, dict) or set(application) != _APPLICATION_KEYS:
        raise ProtocolError("invalid_schema", "application must contain exactly id and instance")
    _string(application.get("id"), "application.id", 64, token=True)
    _string(application.get("instance"), "application.instance", 128)
    return request


def make_request(
    service: str,
    operation: str,
    arguments: dict[str, Any] | None,
    *,
    session_id: str,
    user: str,
    application_id: str,
    application_instance: str = "local",
    request_id: str | None = None,
    nonce: str | None = None,
    timestamp: str | None = None,
    version: int = PROTOCOL_VERSION,
) -> dict[str, Any]:
    request = {
        "protocol": PROTOCOL_NAME,
        "version": version,
        "requestId": request_id or str(uuid.uuid4()),
        "service": service,
        "operation": operation,
        "arguments": arguments or {},
        "nonce": nonce or secrets.token_hex(NONCE_BYTES),
        "timestamp": timestamp or utc_timestamp(),
        "session": {"id": session_id, "user": user},
        "application": {"id": application_id, "instance": application_instance},
    }
    validate_request(request)
    return request


def encode_frame(document: dict[str, Any], maximum: int) -> bytes:
    try:
        payload = json.dumps(document, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise ProtocolError("invalid_json", "document is not JSON serializable") from exc
    if not payload or len(payload) > maximum:
        raise ProtocolError("message_too_large", f"message exceeds {maximum} bytes")
    return struct.pack("!I", len(payload)) + payload


def decode_payload(payload: bytes, maximum: int) -> dict[str, Any]:
    if not payload or len(payload) > maximum:
        raise ProtocolError("message_too_large", f"message exceeds {maximum} bytes")
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtocolError("invalid_json", "message is not valid UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise ProtocolError("invalid_schema", "message must be a JSON object")
    return value


def success_response(request_id: str, result: dict[str, Any]) -> dict[str, Any]:
    return {
        "protocol": PROTOCOL_NAME,
        "version": PROTOCOL_VERSION,
        "requestId": request_id,
        "ok": True,
        "result": result,
        "error": None,
        "timestamp": utc_timestamp(),
    }


def error_response(request_id: str, code: str, message: str) -> dict[str, Any]:
    return {
        "protocol": PROTOCOL_NAME,
        "version": PROTOCOL_VERSION,
        "requestId": request_id,
        "ok": False,
        "result": None,
        "error": {"code": code, "message": message},
        "timestamp": utc_timestamp(),
    }
