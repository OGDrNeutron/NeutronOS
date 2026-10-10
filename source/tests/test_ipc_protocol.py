from __future__ import annotations

import json
import os
import pwd
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from neutronos_ipc.protocol import (  # noqa: E402
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    ProtocolError,
    decode_payload,
    encode_frame,
    make_request,
    validate_request,
)
from neutronos_ipc.server import IpcServer, PeerCredentials, ReplayCache  # noqa: E402
from neutronos_ipc.sessions import verify_active_session  # noqa: E402


IDENTITY = {
    "session_id": "test-session",
    "user": pwd.getpwuid(os.getuid()).pw_name,
    "application_id": "neutronos.test",
    "application_instance": "unit-test",
}


def receive_document(connection: socket.socket) -> dict:
    header = connection.recv(4)
    size = struct.unpack("!I", header)[0]
    payload = bytearray()
    while len(payload) < size:
        payload.extend(connection.recv(size - len(payload)))
    return json.loads(payload.decode("utf-8"))


class ProtocolTests(unittest.TestCase):
    def test_valid_request_has_strong_nonce_and_strict_schema(self):
        request = make_request("security", "security.health", {}, **IDENTITY)
        self.assertEqual(validate_request(request), request)
        self.assertEqual(len(request["nonce"]), 64)
        request["unexpected"] = True
        with self.assertRaisesRegex(ProtocolError, "fields"):
            validate_request(request)

    def test_session_identifier_cannot_be_an_option_or_path(self):
        for invalid in ("--machine=attacker", "../9", "9/../../x"):
            with self.assertRaisesRegex(ProtocolError, "session.id"):
                make_request("security", "security.health", {}, **{**IDENTITY, "session_id": invalid})

    def test_stale_timestamp_is_rejected(self):
        stale = (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat()
        with self.assertRaisesRegex(ProtocolError, "outside"):
            make_request("security", "security.health", {}, timestamp=stale, **IDENTITY)

    def test_request_size_limit_is_enforced_before_json_decode(self):
        with self.assertRaisesRegex(ProtocolError, "exceeds"):
            decode_payload(b"x" * (MAX_REQUEST_BYTES + 1), MAX_REQUEST_BYTES)

    def test_replay_cache_rejects_nonce_until_expiry(self):
        cache = ReplayCache(ttl_seconds=10, maximum_entries=2)
        self.assertTrue(cache.accept("a", now=1))
        self.assertFalse(cache.accept("a", now=2))
        self.assertTrue(cache.accept("a", now=12))

    def test_session_verification_binds_claim_to_peer_uid(self):
        peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
        properties = lambda _session: {
            "Active": "yes", "State": "active", "User": str(os.getuid()),
            "Name": IDENTITY["user"], "ControlGroup": "/user.slice/session-test.scope",
        }
        self.assertTrue(verify_active_session(
            peer, {"id": "s", "user": IDENTITY["user"]},
            property_loader=properties,
            cgroup_loader=lambda _pid: ["/user.slice/session-test.scope/app.slice"],
        ))
        wrong = PeerCredentials(os.getpid(), os.getuid() + 1, os.getgid())
        self.assertFalse(verify_active_session(
            wrong, {"id": "s", "user": IDENTITY["user"]},
            property_loader=properties,
            cgroup_loader=lambda _pid: ["/user.slice/session-test.scope"],
        ))

    def test_session_verification_rejects_same_uid_outside_claimed_session(self):
        peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
        properties = lambda _session: {
            "Active": "yes", "State": "active", "User": str(os.getuid()),
            "Name": IDENTITY["user"], "ControlGroup": "/user.slice/session-9.scope",
            "Leader": "999999",
        }
        self.assertFalse(verify_active_session(
            peer, {"id": "9", "user": IDENTITY["user"]},
            property_loader=properties,
            cgroup_loader=lambda _pid: ["/system.slice/unrelated.service"],
            parent_loader=lambda _pid: 1,
        ))


class ServerBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.audit = []
        self.server = IpcServer(
            Path("/unused"), "security",
            lambda operation, arguments, context: {"operation": operation, "peerUid": context.peer.uid},
            lambda peer, session: True,
            lambda peer, session, application, operation, arguments: "security.read" if operation == "security.health" else None,
            lambda event, detail: self.audit.append((event, detail)),
            socket_group=os.getgid(),
        )

    def exchange(self, request: dict) -> dict:
        client, server = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        thread = threading.Thread(target=self.server._serve_connection, args=(server,))
        thread.start()
        try:
            client.sendall(encode_frame(request, MAX_REQUEST_BYTES))
            response = receive_document(client)
        finally:
            client.close()
            thread.join(timeout=2)
            server.close()
        self.assertFalse(thread.is_alive())
        return response

    def test_kernel_peer_credentials_reach_handler(self):
        response = self.exchange(make_request("security", "security.health", {}, **IDENTITY))
        self.assertTrue(response["ok"])
        self.assertEqual(response["result"]["peerUid"], os.getuid())
        self.assertEqual(self.audit[-1][0], "ipc_request_accepted")

    def test_unknown_operation_is_default_denied(self):
        response = self.exchange(make_request("security", "security.destroy", {}, **IDENTITY))
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "not_authorized")
        self.assertEqual(self.audit[-1][1]["operation"], "security.destroy")
        self.assertEqual(self.audit[-1][1]["applicationIdentityStrength"], "asserted-context")

    def test_replayed_request_is_rejected(self):
        request = make_request("security", "security.health", {}, **IDENTITY)
        self.assertTrue(self.exchange(request)["ok"])
        response = self.exchange(request)
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "replay_rejected")

    def test_declared_oversize_frame_is_rejected_without_reading_body(self):
        client, server = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        thread = threading.Thread(target=self.server._serve_connection, args=(server,))
        thread.start()
        client.sendall(struct.pack("!I", MAX_REQUEST_BYTES + 1))
        response = receive_document(client)
        client.close()
        thread.join(timeout=2)
        server.close()
        self.assertEqual(response["error"]["code"], "message_too_large")

    def test_incomplete_client_does_not_block_another_request(self):
        with tempfile.TemporaryDirectory() as directory:
            server = IpcServer(
                Path(directory) / "control.sock", "security",
                lambda operation, arguments, context: {"responsive": True},
                lambda peer, session: True,
                lambda peer, session, application, operation, arguments: "security.read",
                lambda event, detail: None,
                socket_group=os.getgid(), request_timeout=0.5,
            )
            with mock.patch("neutronos_ipc.server.os.chown"):
                server.start()
            slow = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            valid = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                slow.connect(str(server.socket_path))
                slow.sendall(struct.pack("!I", 128) + b"{")
                valid.connect(str(server.socket_path))
                valid.sendall(encode_frame(
                    make_request("security", "security.health", {}, **IDENTITY),
                    MAX_REQUEST_BYTES))
                valid.setblocking(False)
                response = bytearray()
                deadline = time.monotonic() + 0.3
                loop_ticks = 0
                while time.monotonic() < deadline:
                    server.serve_ready(0.01)
                    loop_ticks += 1
                    try:
                        response.extend(valid.recv(MAX_RESPONSE_BYTES + 4))
                    except BlockingIOError:
                        pass
                    if len(response) >= 4:
                        size = struct.unpack("!I", response[:4])[0]
                        if len(response) >= size + 4:
                            break
                self.assertGreater(loop_ticks, 1)
                self.assertGreaterEqual(len(response), 4)
                size = struct.unpack("!I", response[:4])[0]
                document = decode_payload(bytes(response[4:4 + size]), MAX_RESPONSE_BYTES)
                self.assertTrue(document["ok"])
                self.assertTrue(document["result"]["responsive"])
                self.assertTrue(any(state.received.endswith(b"{") and not state.response
                                    for state in server._clients.values()))
            finally:
                slow.close()
                valid.close()
                server.close()


if __name__ == "__main__":
    unittest.main()
