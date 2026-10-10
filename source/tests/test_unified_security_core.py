from __future__ import annotations

import importlib.util
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
SPEC = importlib.util.spec_from_file_location("neutron_securityd_patch76", ROOT / "scripts" / "neutron-securityd.py")
assert SPEC and SPEC.loader
SECURITYD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SECURITYD)

from neutronos_ipc.authorization import AuthorizationError, AuthorizationPolicy, ProcessIdentity  # noqa: E402
from neutronos_ipc.server import PeerCredentials, RequestContext  # noqa: E402
from neutronos_ipc.sessions import verify_active_session  # noqa: E402


class UnifiedSecurityCoreTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def make_core(self, state: Path, legacy: bool = False):
        account = pwd.getpwuid(os.getuid())
        policy = AuthorizationPolicy.load(ROOT / "config/security-authorization.json", require_root_owner=False)
        return SECURITYD.SecurityCore(state, ROOT, account.pw_name, account.pw_name,
                                      policy, legacy_json_requests=legacy)

    def context(self):
        return RequestContext(
            peer=PeerCredentials(os.getpid(), os.getuid(), os.getgid()),
            session={"id": "test", "user": pwd.getpwuid(os.getuid()).pw_name},
            application={"id": "security", "instance": "unit"},
            capability="security.mode.write", permission="security.control",
            principal="authenticated-local-security-session",
        )

    def test_cpp_adapter_has_no_duplicate_privileged_authority(self):
        header = self.read("src/SecurityCoreManager.h")
        source = self.read("src/SecurityCoreManager.cpp")
        self.assertIn("SecureIpcClient::request", source)
        self.assertIn("/run/neutronos/security/control.sock", header)
        for forbidden in ("#include <QProcess>", "QSaveFile", "sodium", "nft", "writeJsonObject",
                          "/var/lib/neutronos/security/core", "audit.jsonl"):
            self.assertNotIn(forbidden, source)
        self.assertNotIn("writeJsonObject", header)

    def test_daemon_is_single_writer_and_action_is_audited_once(self):
        with tempfile.TemporaryDirectory(prefix="patch76-core-") as temporary:
            core = self.make_core(Path(temporary) / "state")
            before = sum(1 for line in core.audit_path.read_text().splitlines()
                         if json.loads(line).get("action") == "learning_mode_changed")
            result = core.ipc_handle("security.set-learning-mode", {"enabled": True}, self.context())
            after = sum(1 for line in core.audit_path.read_text().splitlines()
                        if json.loads(line).get("action") == "learning_mode_changed")
            self.assertTrue(result["success"])
            self.assertEqual(after - before, 1)
            self.assertTrue(json.loads(core.config_path.read_text())["learningMode"])

    def test_policy_exposes_typed_migrated_operations_and_denies_old_shim(self):
        policy = AuthorizationPolicy.load(ROOT / "config/security-authorization.json", require_root_owner=False)
        for operation in ("security.set-learning-mode", "security.apply-hardening",
                          "security.block-source", "security.unlock-vault",
                          "security.create-integrity-baseline"):
            self.assertIn(operation, policy.enabled_operations())
        peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
        session = {"id": "test", "user": pwd.getpwuid(os.getuid()).pw_name}
        identity = ProcessIdentity(os.getpid(), "/usr/bin/python3", ("python3",), 1)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=identity), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value={"neutronos-shell"}):
            with self.assertRaises(AuthorizationError):
                policy.authorize(peer, session, {"id": "security", "instance": "test"},
                                 "set_learning_mode", {"enabled": True})
            with self.assertRaisesRegex(AuthorizationError, "wrong type"):
                policy.authorize(peer, session, {"id": "security", "instance": "test"},
                                 "security.set-learning-mode", {"enabled": "yes"})

    def test_capability_denial_is_distinct_from_permission_denial(self):
        document = json.loads((ROOT / "config/security-authorization.json").read_text())
        document["roles"]["authenticated-local-security-session"]["capabilities"].remove(
            "security.mode.write")
        policy = AuthorizationPolicy(document, Path("/unit/policy.json"))
        account = pwd.getpwuid(os.getuid())
        peer = PeerCredentials(os.getpid(), os.getuid(), os.getgid())
        identity = ProcessIdentity(os.getpid(), "/usr/bin/python3", ("python3",), 1)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=identity), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value={"neutronos-shell"}):
            with self.assertRaisesRegex(AuthorizationError, "capability") as raised:
                policy.authorize(peer, {"id": "test", "user": account.pw_name},
                                 {"id": "security", "instance": "test"},
                                 "security.set-learning-mode", {"enabled": True})
            self.assertEqual(raised.exception.code, "capability_denied")

    def test_stale_json_queue_is_inert_without_explicit_compatibility_flag(self):
        with tempfile.TemporaryDirectory(prefix="patch76-queue-") as temporary:
            state = Path(temporary) / "state"
            core = self.make_core(state)
            stale = state / "requests" / "stale.json"
            stale.parent.mkdir()
            stale.write_text(json.dumps({"action": "set_learning_mode", "payload": {"enabled": False}}))
            before = bool(core.config.get("learningMode"))
            self.assertFalse(core.process_requests())
            self.assertEqual(bool(core.config.get("learningMode")), before)
            self.assertTrue(stale.exists())

    def test_watchdog_events_join_daemon_audit_once(self):
        with tempfile.TemporaryDirectory(prefix="patch76-watchdog-") as temporary:
            core = self.make_core(Path(temporary) / "state")
            core.watchdog_event_path.write_text(json.dumps({
                "timestamp": "2026-08-08T00:00:00Z", "action": "watchdog_test",
                "details": {"safe": True},
            }))
            self.assertTrue(core.process_watchdog_event())
            self.assertFalse(core.process_watchdog_event())
            matches = [json.loads(line) for line in core.audit_path.read_text().splitlines()
                       if json.loads(line).get("action") == "watchdog_test"]
            self.assertEqual(len(matches), 1)
            self.assertFalse(core.watchdog_event_path.exists())

    def test_trusted_system_shell_is_narrow_and_session_is_still_validated(self):
        account = pwd.getpwuid(os.getuid())
        peer = PeerCredentials(4242, 0, 0)
        properties = lambda _sid: {
            "Active": "yes", "State": "active", "User": str(account.pw_uid),
            "Name": account.pw_name, "ControlGroup": "/user.slice/session-test.scope",
        }
        with mock.patch("neutronos_ipc.sessions.os.readlink", return_value="/opt/NeutronOS/build/NeutronShell"), \
             mock.patch("neutronos_ipc.sessions.os.stat") as process_stat:
            process_stat.return_value.st_uid = 0
            self.assertTrue(verify_active_session(
                peer, {"id": "test", "user": account.pw_name},
                property_loader=properties,
                cgroup_loader=lambda _pid: ["/system.slice/neutronos.service"],
                trusted_system_shell=(0, account.pw_name, "/opt/NeutronOS/build/NeutronShell",
                                      "/system.slice/neutronos.service"),
            ))
            self.assertFalse(verify_active_session(
                peer, {"id": "test", "user": account.pw_name},
                property_loader=properties,
                cgroup_loader=lambda _pid: ["/system.slice/attacker.service"],
                trusted_system_shell=(0, account.pw_name, "/opt/NeutronOS/build/NeutronShell",
                                      "/system.slice/neutronos.service"),
            ))

    def test_policy_accepts_only_declared_system_shell_process(self):
        policy = AuthorizationPolicy.load(ROOT / "deployment/etc/neutronos/security-authorization.json", require_root_owner=False)
        account = pwd.getpwuid(os.getuid())
        shell_peer = PeerCredentials(4242, 999, 985)
        identity = ProcessIdentity(4242, "/opt/neutronos/build/NeutronShell",
                                   ("/opt/neutronos/build/NeutronShell",), 9)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=identity), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value=set()), \
             mock.patch("neutronos_ipc.authorization._control_groups_for_process",
                        return_value={"/system.slice/neutronos.service"}):
            grant = policy.authorize(
                shell_peer, {"id": "test", "user": account.pw_name},
                {"id": "security", "instance": "test"}, "security.snapshot", {})
            self.assertEqual(grant.principal, "neutronos-system-shell")
        wrong = ProcessIdentity(4242, "/tmp/NeutronShell", ("/tmp/NeutronShell",), 9)
        with mock.patch("neutronos_ipc.authorization.process_identity", return_value=wrong), \
             mock.patch("neutronos_ipc.authorization._groups_for_process", return_value=set()), \
             mock.patch("neutronos_ipc.authorization._control_groups_for_process",
                        return_value={"/system.slice/neutronos.service"}):
            with self.assertRaisesRegex(AuthorizationError, "does not match"):
                policy.authorize(
                    shell_peer, {"id": "test", "user": account.pw_name},
                    {"id": "security", "instance": "test"}, "security.snapshot", {})

    def test_adapter_fails_closed_and_retries_after_daemon_restart(self):
        header = self.read("src/SecurityCoreManager.h")
        source = self.read("src/SecurityCoreManager.cpp")
        self.assertIn("markUnavailable", source)
        self.assertIn("m_daemonOnline = false", source)
        self.assertIn("m_vaultUnlocked = false", source)
        self.assertIn("m_healthTimer.setInterval(5000)", source)
        self.assertIn("leader.toLongLong() == QCoreApplication::applicationPid()", source)
        self.assertIn('if (remote == QStringLiteral("1"))\n            continue;', source)
        self.assertIn("!m_authManager->pamSessionOpen()", source)
        self.assertIn("m_shellSessionAuthenticated", source)
        self.assertIn("setShellSessionAuthenticated", header)
        self.assertIn("connect(&m_healthTimer", source)
        self.assertIn("security.snapshot", source)

    def test_read_only_snapshot_poll_does_not_grow_audit(self):
        with tempfile.TemporaryDirectory(prefix="patch76-audit-poll-") as temporary:
            core = self.make_core(Path(temporary) / "state")
            before = core.audit_path.read_text()
            core.ipc_audit("ipc_request_accepted", {"operation": "security.snapshot"})
            self.assertEqual(core.audit_path.read_text(), before)
            core.ipc_audit("ipc_request_rejected", {
                "operation": "security.snapshot", "code": "session_rejected"})
            self.assertNotEqual(core.audit_path.read_text(), before)


if __name__ == "__main__":
    unittest.main()
