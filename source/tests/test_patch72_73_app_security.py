import json
import os
import stat
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from scripts.neutronos_app_security import (
    PackageAnalyzer, QuarantineStore, SandboxCapabilities, SandboxPolicy,
    RISK_NOT_PROOF,
)


def package(path: Path, body: str = "Item {}", permissions=None, member="qml/apps/demo/Main.qml"):
    manifest = {"id": "demo", "name": "Demo", "permissions": permissions or []}
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("manifest.json", json.dumps(manifest))
        info = zipfile.ZipInfo("payload/" + member)
        info.external_attr = (0o755 if member.endswith((".sh", ".py")) else 0o644) << 16
        archive.writestr(info, body)


class PackageAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self): self.temp.cleanup()

    def test_safe_suspicious_dangerous_are_deterministic(self):
        safe = self.root / "safe.napp"; package(safe)
        suspicious = self.root / "suspicious.napp"; package(suspicious, "import subprocess")
        dangerous = self.root / "dangerous.napp"; package(dangerous, "sudo cat /etc/shadow", ["root"])
        analyzer = PackageAnalyzer()
        self.assertEqual(analyzer.analyze(safe)["classification"], "SAFE")
        self.assertEqual(analyzer.analyze(suspicious)["classification"], "SUSPICIOUS")
        report = analyzer.analyze(dangerous)
        self.assertEqual(report["classification"], "DANGEROUS")
        self.assertEqual(report["disclaimer"], RISK_NOT_PROOF)
        self.assertTrue(all(set(("id", "category", "severity", "description", "evidence",
                                 "path", "requestedPermission", "recommendedAction")) <= set(f)
                            for f in report["findings"]))

    def test_malformed_traversal_and_symlink_are_rejected(self):
        bad = self.root / "bad.napp"
        with zipfile.ZipFile(bad, "w") as archive:
            archive.writestr("manifest.json", "{}")
            archive.writestr("../escape", "x")
        with self.assertRaises(ValueError): PackageAnalyzer().analyze(bad)
        link = self.root / "link.napp"
        with zipfile.ZipFile(link, "w") as archive:
            archive.writestr("manifest.json", "{}")
            info = zipfile.ZipInfo("payload/qml/apps/demo/link")
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, "/etc/shadow")
        with self.assertRaises(ValueError): PackageAnalyzer().analyze(link)

    def test_policy_denies_network_home_devices_and_privilege(self):
        exe = self.root / "run.sh"; exe.write_text("#!/bin/sh\n"); exe.chmod(0o700)
        caps = SandboxCapabilities(True, True, True, True, True, True)
        command = SandboxPolicy(caps).command(exe, "demo", self.root / "data")
        self.assertIn("--unshare-net", command)
        self.assertEqual(command[command.index("--cap-drop") + 1], "ALL")
        self.assertNotIn(str(Path.home()), command)
        self.assertEqual(SandboxPolicy(caps).limits()["noNewPrivileges"], True)


class QuarantineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.candidate = self.root / "demo.napp"; package(self.candidate, "#!/bin/sh\nexit 0", member="scripts/apps/demo/run.sh")
        self.store = QuarantineStore(self.root / "quarantine")
        self.analysis = PackageAnalyzer().analyze(self.candidate)

    def tearDown(self): self.temp.cleanup()

    def test_inventory_restore_delete_and_corrupt_rejection(self):
        item = self.store.quarantine(self.candidate, self.analysis)
        self.assertEqual(self.store.list()[0]["sha256"], item["sha256"])
        destination = self.root / "restore"; destination.mkdir()
        self.assertTrue(self.store.restore(item["id"], destination).is_file())
        (self.store.objects / item["id"] / "metadata.json").write_text("{}")
        with self.assertRaises(ValueError): self.store.restore(item["id"], destination)

    def test_traversal_and_symlink_object_are_rejected(self):
        with self.assertRaises(ValueError): self.store.delete("../escape")
        object_id = "a" * 32
        (self.store.objects / object_id).symlink_to(self.root)
        with self.assertRaises(ValueError): self.store.delete(object_id)

    def test_runtime_is_inside_quarantine_and_network_defaults_denied(self):
        item = self.store.quarantine(self.candidate, self.analysis)
        runtime = self.store.prepare_runtime(item["id"])
        executable = runtime / "scripts/apps/demo/run.sh"
        policy = mock.Mock()
        policy.command.return_value = ["/bin/true"]
        result = self.store.run(item["id"], executable, self.root / "data", policy=policy)
        self.assertEqual(result["network"], "denied by namespace")
        with self.assertRaises(ValueError):
            self.store.run(item["id"], Path("/bin/true"), self.root / "data", policy=policy)

    def test_single_execution_lock_is_race_safe(self):
        item = self.store.quarantine(self.candidate, self.analysis)
        executable = self.store.prepare_runtime(item["id"]) / "scripts/apps/demo/run.sh"
        policy = mock.Mock(); policy.command.return_value = ["/bin/sleep", "0.25"]
        results = []
        first = threading.Thread(target=lambda: results.append(self.store.run(item["id"], executable, self.root / "data", policy=policy)))
        first.start()
        threading.Event().wait(0.05)
        with self.assertRaises(RuntimeError):
            self.store.run(item["id"], executable, self.root / "data2", policy=policy)
        first.join()
        self.assertEqual(len(results), 1)


class IntegrationContractTests(unittest.TestCase):
    def test_developer_mode_and_security_core_contracts(self):
        cpp = Path("src/AppStoreManager.cpp").read_text()
        daemon = Path("scripts/neutron-securityd.py").read_text()
        policy = json.loads(Path("config/security-authorization.json").read_text())
        self.assertIn("if (!developerModeEnabled())", cpp)
        self.assertIn("DANGEROUS", cpp)
        for operation in ("security.analyze-app-package", "security.quarantine-app-package",
                          "security.list-quarantined-apps", "security.restore-quarantined-app",
                          "security.delete-quarantined-app"):
            self.assertIn(operation, daemon)
            self.assertIn(operation, policy["operations"])


if __name__ == "__main__": unittest.main()
