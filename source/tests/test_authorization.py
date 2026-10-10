from __future__ import annotations

import json
import os
import pwd
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from neutronos_ipc.authorization import (  # noqa: E402
    AuthorizationError,
    AuthorizationPolicy,
    ProcessIdentity,
)
from neutronos_ipc.server import PeerCredentials  # noqa: E402


class AuthorizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = AuthorizationPolicy.load(
            ROOT / "config" / "security-authorization.json",
            require_root_owner=False,
        )
        cls.account = pwd.getpwuid(os.getuid())
        cls.peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
        cls.session = {"id": "9", "user": cls.account.pw_name}
        cls.application = {"id": "neutronos.security", "instance": "unit-test"}

    def authorize(self, operation: str, arguments: dict):
        identity = ProcessIdentity(os.getpid(), "/usr/bin/python3", ("python3",), 123)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=identity), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value={"neutronos-shell"}):
            return self.policy.authorize(
                self.peer, self.session, self.application, operation, arguments
            )

    def test_known_operation_returns_server_side_permission_and_capability(self):
        grant = self.authorize("security.health", {})
        self.assertEqual(grant.permission, "security.read")
        self.assertEqual(grant.capability, "security.read")
        self.assertEqual(grant.principal, "authenticated-local-security-session")
        self.assertEqual(grant.application_identity_strength, "asserted-context")

    def test_unknown_operation_is_default_denied(self):
        with self.assertRaisesRegex(AuthorizationError, "not present"):
            self.authorize("security.make-root-shell-clean", {})

    def test_privileged_legacy_operation_is_explicitly_disabled(self):
        with self.assertRaisesRegex(AuthorizationError, "Patch 76"):
            self.authorize("apply_hardening", {})

    def test_unexpected_argument_is_rejected_before_handler(self):
        with self.assertRaisesRegex(AuthorizationError, "unknown argument"):
            self.authorize("security.health", {"apply": True})

    def test_permission_is_denied_when_required_group_is_absent(self):
        identity = ProcessIdentity(os.getpid(), "/usr/bin/python3", ("python3",), 123)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=identity), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value=set()):
            with self.assertRaisesRegex(AuthorizationError, "lacks"):
                self.policy.authorize(
                    self.peer, self.session, self.application, "security.health", {}
                )

    def test_peer_uid_must_equal_session_user(self):
        wrong_peer = PeerCredentials(os.getpid(), os.getuid() + 1, os.getgid())
        with self.assertRaisesRegex(AuthorizationError, "does not match"):
            self.policy.authorize(
                wrong_peer, self.session, self.application, "security.health", {}
            )

    def test_root_daemon_rejects_writable_policy_file(self):
        with tempfile.TemporaryDirectory(prefix="neutron-auth-policy-") as temporary:
            path = Path(temporary) / "policy.json"
            path.write_text(json.dumps({"schema": 1, "defaultDeny": True, "roles": {}, "operations": {}}))
            path.chmod(0o666)
            with self.assertRaisesRegex(AuthorizationError, "root-owned"):
                AuthorizationPolicy.load(path, require_root_owner=True)


if __name__ == "__main__":
    unittest.main()
