"""Root-owned Unix socket server with peer credentials and replay rejection."""

from __future__ import annotations

import grp
import os
import selectors
import socket
import struct
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .protocol import (
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    PROTOCOL_NAME,
    PROTOCOL_VERSION,
    ProtocolError,
    decode_payload,
    encode_frame,
    error_response,
    success_response,
    validate_request,
)


@dataclass(frozen=True)
class PeerCredentials:
    pid: int
    uid: int
    gid: int


@dataclass(frozen=True)
class RequestContext:
    peer: PeerCredentials
    session: dict[str, str]
    application: dict[str, str]
    capability: str
    permission: str = ""
    principal: str = ""
    process_executable: str = ""
    process_start_time: int = 0
    application_identity_strength: str = "asserted-context"


@dataclass(frozen=True)
class AuthorizationGrant:
    capability: str
    permission: str
    principal: str
    process_executable: str
    process_start_time: int
    application_identity_strength: str = "asserted-context"


@dataclass
class _ClientState:
    received: bytearray
    response: bytes
    response_offset: int
    deadline: float


class ReplayCache:
    def __init__(self, ttl_seconds: int = 60, maximum_entries: int = 4096):
        self.ttl_seconds = ttl_seconds
        self.maximum_entries = maximum_entries
        self._entries: OrderedDict[str, float] = OrderedDict()

    def accept(self, nonce: str, now: float | None = None) -> bool:
        current = time.monotonic() if now is None else now
        cutoff = current - self.ttl_seconds
        while self._entries and next(iter(self._entries.values())) < cutoff:
            self._entries.popitem(last=False)
        if nonce in self._entries:
            return False
        self._entries[nonce] = current
        while len(self._entries) > self.maximum_entries:
            self._entries.popitem(last=False)
        return True


class IpcServer:
    def __init__(
        self,
        socket_path: Path,
        service: str,
        handler: Callable[[str, dict[str, Any], RequestContext], dict[str, Any]],
        authenticate: Callable[[PeerCredentials, dict[str, str]], bool],
        authorize: Callable[[PeerCredentials, dict[str, str], dict[str, str], str, dict[str, Any]], AuthorizationGrant | str | None],
        audit: Callable[[str, dict[str, Any]], None],
        *,
        socket_group: str | int,
        socket_mode: int = 0o660,
        request_timeout: float = 5.0,
    ):
        self.socket_path = socket_path
        self.service = service
        self.handler = handler
        self.authenticate = authenticate
        self.authorize = authorize
        self.audit = audit
        self.socket_group = socket_group
        self.socket_mode = socket_mode
        self.request_timeout = request_timeout
        self.replays = ReplayCache()
        self._server: socket.socket | None = None
        self._selector: selectors.BaseSelector | None = None
        self._clients: dict[socket.socket, _ClientState] = {}

    def _audit(self, event: str, detail: dict[str, Any]) -> None:
        try:
            self.audit(event, detail)
        except Exception:
            # Audit failure must not disclose request data or crash the service
            # boundary. The daemon's heartbeat exposes audit validity separately.
            pass

    def start(self) -> None:
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        os.chown(self.socket_path.parent, 0, 0)
        os.chmod(self.socket_path.parent, 0o755)
        try:
            self.socket_path.unlink()
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.setblocking(False)
        server.bind(str(self.socket_path))
        group_id = self.socket_group if isinstance(self.socket_group, int) else grp.getgrnam(self.socket_group).gr_gid
        os.chown(self.socket_path, 0, group_id)
        os.chmod(self.socket_path, self.socket_mode)
        server.listen(16)
        self._server = server
        self._selector = selectors.DefaultSelector()
        self._selector.register(server, selectors.EVENT_READ, None)

    def close(self) -> None:
        for connection in list(self._clients):
            self._close_client(connection)
        if self._selector is not None:
            self._selector.close()
            self._selector = None
        if self._server is not None:
            self._server.close()
            self._server = None
        try:
            self.socket_path.unlink()
        except FileNotFoundError:
            pass

    def serve_ready(self, timeout: float = 0.0) -> bool:
        if self._server is None or self._selector is None:
            raise RuntimeError("IPC server is not started")
        self._expire_clients()
        events = self._selector.select(timeout)
        if not events:
            return False
        for key, mask in events:
            if key.data is None:
                self._accept_ready()
            else:
                connection = key.fileobj
                if mask & selectors.EVENT_READ:
                    self._read_ready(connection)
                if connection in self._clients and mask & selectors.EVENT_WRITE:
                    self._write_ready(connection)
        return True

    def _accept_ready(self) -> None:
        assert self._server is not None and self._selector is not None
        while True:
            try:
                connection, _ = self._server.accept()
            except BlockingIOError:
                return
            if len(self._clients) >= 64:
                self._audit("ipc_request_rejected", {
                    "requestId": "00000000-0000-0000-0000-000000000000",
                    "code": "server_busy",
                })
                connection.close()
                continue
            connection.setblocking(False)
            state = _ClientState(bytearray(), b"", 0,
                                 time.monotonic() + self.request_timeout)
            self._clients[connection] = state
            self._selector.register(connection, selectors.EVENT_READ, state)

    def _close_client(self, connection: socket.socket) -> None:
        if self._selector is not None:
            try:
                self._selector.unregister(connection)
            except (KeyError, ValueError):
                pass
        self._clients.pop(connection, None)
        try:
            connection.close()
        except OSError:
            pass

    def _queue_response(self, connection: socket.socket,
                        document: dict[str, Any]) -> None:
        state = self._clients.get(connection)
        if state is None or self._selector is None:
            return
        state.response = encode_frame(document, MAX_RESPONSE_BYTES)
        state.response_offset = 0
        state.deadline = time.monotonic() + self.request_timeout
        self._selector.modify(connection, selectors.EVENT_WRITE, state)

    def _read_ready(self, connection: socket.socket) -> None:
        state = self._clients.get(connection)
        if state is None:
            return
        try:
            chunk = connection.recv(MAX_REQUEST_BYTES + 4 - len(state.received))
        except BlockingIOError:
            return
        except OSError:
            self._close_client(connection)
            return
        if not chunk:
            self._close_client(connection)
            return
        state.received.extend(chunk)
        if len(state.received) < 4:
            return
        size = struct.unpack("!I", state.received[:4])[0]
        if size <= 0 or size > MAX_REQUEST_BYTES:
            self._reject_partial(connection, "message_too_large",
                                 f"request exceeds {MAX_REQUEST_BYTES} bytes")
            return
        if len(state.received) < size + 4:
            return
        try:
            request = decode_payload(bytes(state.received[4:size + 4]), MAX_REQUEST_BYTES)
            response = self._process_request(connection, request)
        except ProtocolError as exc:
            self._reject_partial(connection, exc.code, exc.message)
            return
        self._queue_response(connection, response)

    def _reject_partial(self, connection: socket.socket, code: str,
                        message: str) -> None:
        detail: dict[str, Any] = {
            "requestId": "00000000-0000-0000-0000-000000000000",
            "code": code,
        }
        try:
            peer = self._peer_credentials(connection)
            detail.update({"peerPid": peer.pid, "peerUid": peer.uid,
                           "peerGid": peer.gid})
        except ProtocolError:
            pass
        self._audit("ipc_request_rejected", detail)
        self._queue_response(connection, error_response(
            detail["requestId"], code, message))

    def _write_ready(self, connection: socket.socket) -> None:
        state = self._clients.get(connection)
        if state is None:
            return
        try:
            sent = connection.send(state.response[state.response_offset:])
        except BlockingIOError:
            return
        except OSError:
            self._close_client(connection)
            return
        state.response_offset += sent
        if state.response_offset >= len(state.response):
            self._close_client(connection)

    def _expire_clients(self) -> None:
        now = time.monotonic()
        for connection, state in list(self._clients.items()):
            if state.deadline > now:
                continue
            if state.response:
                self._close_client(connection)
            else:
                self._reject_partial(connection, "timeout", "IPC request timed out")

    @staticmethod
    def _peer_credentials(connection: socket.socket) -> PeerCredentials:
        if not hasattr(socket, "SO_PEERCRED"):
            raise ProtocolError("peer_credentials_unavailable", "SO_PEERCRED is unavailable")
        raw = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
        pid, uid, gid = struct.unpack("3i", raw)
        if pid <= 0 or uid < 0 or gid < 0:
            raise ProtocolError("invalid_peer", "kernel returned invalid peer credentials")
        return PeerCredentials(pid=pid, uid=uid, gid=gid)

    @staticmethod
    def _recv_exact(connection: socket.socket, size: int) -> bytes:
        data = bytearray()
        while len(data) < size:
            chunk = connection.recv(size - len(data))
            if not chunk:
                raise ProtocolError("incomplete_message", "client closed the connection early")
            data.extend(chunk)
        return bytes(data)

    def _receive(self, connection: socket.socket) -> dict[str, Any]:
        header = self._recv_exact(connection, 4)
        size = struct.unpack("!I", header)[0]
        if size <= 0 or size > MAX_REQUEST_BYTES:
            raise ProtocolError("message_too_large", f"request exceeds {MAX_REQUEST_BYTES} bytes")
        return decode_payload(self._recv_exact(connection, size), MAX_REQUEST_BYTES)

    def _send(self, connection: socket.socket, document: dict[str, Any]) -> None:
        connection.sendall(encode_frame(document, MAX_RESPONSE_BYTES))

    def _serve_connection(self, connection: socket.socket) -> None:
        connection.settimeout(self.request_timeout)
        try:
            request = self._receive(connection)
            response = self._process_request(connection, request)
        except (ProtocolError, TimeoutError, socket.timeout) as exc:
            code = exc.code if isinstance(exc, ProtocolError) else "timeout"
            message = exc.message if isinstance(exc, ProtocolError) else "IPC request timed out"
            detail: dict[str, Any] = {
                "requestId": "00000000-0000-0000-0000-000000000000",
                "code": code,
            }
            try:
                peer = self._peer_credentials(connection)
                detail.update({"peerPid": peer.pid, "peerUid": peer.uid,
                               "peerGid": peer.gid})
            except ProtocolError:
                pass
            self._audit("ipc_request_rejected", detail)
            response = error_response("00000000-0000-0000-0000-000000000000", code, message)
        self._send(connection, response)

    def _process_request(self, connection: socket.socket,
                         document: dict[str, Any]) -> dict[str, Any]:
        request_id = "00000000-0000-0000-0000-000000000000"
        peer: PeerCredentials | None = None
        request_meta: dict[str, Any] = {}
        try:
            peer = self._peer_credentials(connection)
            request = validate_request(document)
            request_id = request["requestId"]
            request_meta = {
                "operation": request["operation"],
                "sessionId": request["session"]["id"],
                "sessionUser": request["session"]["user"],
                "application": request["application"]["id"],
                "applicationIdentityStrength": "asserted-context",
            }
            if request["service"] != self.service:
                raise ProtocolError("wrong_service", "request was sent to the wrong service endpoint")
            if not self.replays.accept(request["nonce"]):
                raise ProtocolError("replay_rejected", "request nonce has already been used")
            session = request["session"]
            application = request["application"]
            if not self.authenticate(peer, session):
                raise ProtocolError("session_rejected", "request is not bound to an active authenticated session")
            grant = self.authorize(peer, session, application, request["operation"], request["arguments"])
            if not grant:
                raise ProtocolError("not_authorized", "peer is not authorized for this operation")
            if isinstance(grant, str):
                grant = AuthorizationGrant(grant, "", "", "", 0)
            context = RequestContext(
                peer=peer, session=session, application=application,
                capability=grant.capability, permission=grant.permission,
                principal=grant.principal, process_executable=grant.process_executable,
                process_start_time=grant.process_start_time,
                application_identity_strength=grant.application_identity_strength,
            )
            result = self.handler(request["operation"], request["arguments"], context)
            if not isinstance(result, dict):
                raise ProtocolError("internal_error", "service handler returned an invalid response")
            self._audit("ipc_request_accepted", {
                "requestId": request_id, "operation": request["operation"],
                "peerPid": peer.pid, "peerUid": peer.uid, "peerGid": peer.gid,
                "sessionId": session["id"], "sessionUser": session["user"],
                "application": application["id"],
                "applicationIdentityStrength": grant.application_identity_strength,
                "capability": grant.capability, "permission": grant.permission,
                "principal": grant.principal,
                "processExecutable": grant.process_executable,
                "processStartTime": grant.process_start_time,
                "protocol": PROTOCOL_NAME, "version": PROTOCOL_VERSION,
            })
            return success_response(request_id, result)
        except (ProtocolError, TimeoutError, socket.timeout) as exc:
            code = exc.code if isinstance(exc, ProtocolError) else "timeout"
            message = exc.message if isinstance(exc, ProtocolError) else "IPC request timed out"
            detail = {"requestId": request_id, "code": code, **request_meta}
            if peer is not None:
                detail.update({"peerPid": peer.pid, "peerUid": peer.uid, "peerGid": peer.gid})
            self._audit("ipc_request_rejected", detail)
            return error_response(request_id, code, message)
        except Exception:
            self._audit("ipc_request_error", {"requestId": request_id, "code": "internal_error"})
            return error_response(request_id, "internal_error", "service could not process the request")
