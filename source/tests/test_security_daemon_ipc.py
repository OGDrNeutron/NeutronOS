from __future__ import annotations

import importlib.util
import os
import pwd
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("neutron_securityd", ROOT / "scripts" / "neutron-securityd.py")
assert SPEC and SPEC.loader
SECURITYD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SECURITYD)

from neutronos_ipc.server import PeerCredentials, RequestContext  # noqa: E402
from neutronos_ipc.authorization import AuthorizationPolicy  # noqa: E402


class SecurityDaemonIpcTests(unittest.TestCase):
    def make_core(self, state: Path, legacy: bool = False):
        account = pwd.getpwuid(os.getuid())
        policy = AuthorizationPolicy.load(
            ROOT / "config" / "security-authorization.json",
            require_root_owner=False,
        )
        return SECURITYD.SecurityCore(
            state, ROOT, account.pw_name, account.pw_name, policy,
            legacy_json_requests=legacy,
        )

    def test_writable_json_queues_are_not_created_by_default(self):
        with tempfile.TemporaryDirectory(prefix="neutron-securityd-test-") as temporary:
            state = Path(temporary) / "state"
            self.make_core(state)
            self.assertFalse((state / "requests").exists())
            self.assertFalse((state / "responses").exists())

    def test_legacy_queue_requires_explicit_compatibility_flag(self):
        with tempfile.TemporaryDirectory(prefix="neutron-securityd-test-") as temporary:
            state = Path(temporary) / "state"
            self.make_core(state, legacy=True)
            self.assertTrue((state / "requests").is_dir())
            self.assertTrue((state / "responses").is_dir())

    def test_bootstrap_endpoint_exposes_no_privileged_mutation(self):
        with tempfile.TemporaryDirectory(prefix="neutron-securityd-test-") as temporary:
            core = self.make_core(Path(temporary) / "state")
            peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
            context = RequestContext(
                peer=peer,
                session={"id": "test", "user": pwd.getpwuid(os.getuid()).pw_name},
                application={"id": "neutronos.test", "instance": "unit"},
                capability="ipc.negotiate",
            )
            info = core.ipc_handle("protocol.info", {}, context)
            self.assertEqual(info["identity"]["applicationIdentityStrength"], "asserted-context")
            self.assertNotIn("apply_hardening", info["operations"])
            with self.assertRaises(Exception):
                core.ipc_authorize(peer, context.session, context.application, "apply_hardening", {})


if __name__ == "__main__":
    unittest.main()
