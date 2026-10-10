"""Timeout-bounded client for the NeutronOS local IPC protocol."""

from __future__ import annotations

import socket
import struct
from pathlib import Path
from typing import Any

from .protocol import MAX_RESPONSE_BYTES, ProtocolError, decode_payload, encode_frame, make_request


class IpcClient:
    def __init__(self, socket_path: Path, timeout: float = 5.0, expected_server_uid: int = 0):
        self.socket_path = socket_path
        self.timeout = timeout
        self.expected_server_uid = expected_server_uid

    def _authenticate_server(self, connection: socket.socket) -> None:
        if not hasattr(socket, "SO_PEERCRED"):
            raise ProtocolError("untrusted_server", "server peer credentials are unavailable")
        raw = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        _pid, uid, _gid = struct.unpack("3i", raw)
        if uid != self.expected_server_uid:
            raise ProtocolError("untrusted_server", "local IPC peer is not the expected root service")

    @staticmethod
    def _recv_exact(connection: socket.socket, size: int) -> bytes:
        data = bytearray()
        while len(data) < size:
            chunk = connection.recv(size - len(data))
            if not chunk:
                raise ProtocolError("incomplete_message", "service closed the connection early")
            data.extend(chunk)
        return bytes(data)

    def send(self, request: dict[str, Any]) -> dict[str, Any]:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(self.timeout)
        try:
            connection.connect(str(self.socket_path))
            self._authenticate_server(connection)
            connection.sendall(encode_frame(request, 64 * 1024))
            size = struct.unpack("!I", self._recv_exact(connection, 4))[0]
            if size <= 0 or size > MAX_RESPONSE_BYTES:
                raise ProtocolError("message_too_large", "service response exceeds the accepted limit")
            response = decode_payload(self._recv_exact(connection, size), MAX_RESPONSE_BYTES)
        finally:
            connection.close()
        if response.get("requestId") != request.get("requestId"):
            raise ProtocolError("response_mismatch", "response requestId does not match")
        return response

    def request(self, service: str, operation: str, arguments: dict[str, Any], **identity: str) -> dict[str, Any]:
        return self.send(make_request(service, operation, arguments, **identity))
