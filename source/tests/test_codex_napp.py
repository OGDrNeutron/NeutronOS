import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/build-codex-napp.py"
INSTALLER = ROOT / "scripts/neutronos-appstore-package.py"


class CodexNappTests(unittest.TestCase):
    def test_frozen_catalog_signature_installs_and_tampering_is_rejected(self):
        artifact = ROOT / "dist/apps/Codex-1.0.0-alpha.1-arm64.napp"
        catalog = json.loads((ROOT / "dist/apps/codex-repository-index.json").read_text())
        item = catalog["packages"][0]
        keys = json.loads((ROOT / "config/app-store/trusted-keys.json").read_text())["keys"]
        key = next(entry for entry in keys if entry["id"] == item["keyId"])
        self.assertEqual(key["packageIds"], ["codex"])
        self.assertEqual(hashlib.sha256(artifact.read_bytes()).hexdigest(), item["sha256"])
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "root"
            state = Path(directory) / "state"
            command = [
                "python3", str(INSTALLER), "install", "--root", str(target),
                "--state-root", str(state),
                "--package", str(artifact), "--expected-id", "codex",
                "--expected-version", item["version"], "--source", "signed-test",
                "--expected-sha256", item["sha256"],
                "--signature-base64", item["signature"],
                "--public-key-base64", key["publicKey"],
            ]
            valid = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
            self.assertEqual(valid.returncode, 0, valid.stdout + valid.stderr)
            invalid = subprocess.run(command[:-6] + [
                "--expected-sha256", "0" * 64,
                "--signature-base64", item["signature"],
                "--public-key-base64", key["publicKey"],
            ], cwd=ROOT, text=True, capture_output=True)
            self.assertNotEqual(invalid.returncode, 0)
            self.assertIn("checksum verification failed", invalid.stdout)

    def test_package_is_deterministic_complete_and_transactional(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            name = "Codex-1.0.0-alpha.1-arm64.napp"
            first, second = temp / "one" / name, temp / "two" / name
            for output in (first, second):
                subprocess.run(["python3", str(BUILDER), "--output", str(output)],
                               cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertEqual(first.read_bytes(), second.read_bytes())

            with zipfile.ZipFile(first) as archive:
                names = set(archive.namelist())
                manifest = json.loads(archive.read("manifest.json"))
                required = {
                    "payload/qml/apps/codex/Main.qml",
                    "payload/qml/apps/codex/CodexBackend.qml",
                    "payload/qml/apps/codex/app.json",
                    "payload/scripts/apps/codex/codex-bridge.py",
                    "payload/config/apps/codex-bridge.schema.json",
                    "payload/themes/Default/apps/icons/codex.svg",
                    "payload/themes/Default/apps/posters/codex.svg",
                }
                self.assertTrue(required <= names)
                self.assertEqual(manifest["id"], "codex")
                self.assertEqual(manifest["version"], "1.0.0-alpha.1")
                self.assertIn("codex-cli >= 0.147.0", manifest["dependencies"])
                self.assertFalse(any("__pycache__" in name or name.endswith(".pyc") for name in names))
                schema = json.loads(archive.read("payload/config/apps/codex-bridge.schema.json"))
                self.assertIn("install-runtime", schema["properties"]["action"]["enum"])

            install_root = temp / "installed-root"
            state_root = temp / "state"
            result = subprocess.run(
                ["python3", str(INSTALLER), "install", "--root", str(install_root),
                 "--state-root", str(state_root),
                 "--package", str(first), "--expected-id", "codex",
                 "--expected-version", "1.0.0-alpha.1", "--source", "test-catalog"],
                cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertTrue(json.loads(result.stdout)["success"])
            payload_root = state_root / "app-store/payload"
            registry = json.loads((state_root / "app-store/installed.json").read_text())
            managed = registry["packages"]["codex"]["files"]
            self.assertIn("scripts/apps/codex/codex-bridge.py", managed)
            helper = payload_root / "scripts/apps/codex/codex-bridge.py"
            self.assertTrue(os.access(helper, os.X_OK))

            # Run only the installed helper with an isolated official runtime
            # home. No Codex app source path is present in cwd/PYTHONPATH.
            env = os.environ.copy()
            env["CODEX_HOME"] = str(temp / "official-codex-state")
            Path(env["CODEX_HOME"]).mkdir()
            env["PYTHONPATH"] = ""
            probe = subprocess.run([str(helper)], input='{"action":"open"}\n',
                                   cwd=temp, env=env, text=True, capture_output=True,
                                   timeout=12, check=True)
            messages = [json.loads(line) for line in probe.stdout.splitlines() if line.strip()]
            self.assertEqual(messages[0]["stage"], "CHECKING CODEX")
            self.assertTrue(any(message.get("stage") == "CHECKING APP-SERVER" for message in messages))

            subprocess.run(["python3", str(INSTALLER), "uninstall", "--root", str(install_root),
                            "--state-root", str(state_root),
                            "--package-id", "codex"], cwd=ROOT, check=True,
                           capture_output=True, text=True)
            self.assertFalse((payload_root / "qml/apps/codex").exists())
            self.assertFalse((payload_root / "scripts/apps/codex").exists())
            # External official Codex state is not under the NeutronOS root.
            self.assertTrue(Path(env["CODEX_HOME"]).exists())

            subprocess.run(["python3", str(INSTALLER), "install", "--root", str(install_root),
                            "--state-root", str(state_root),
                            "--package", str(first), "--expected-id", "codex",
                            "--expected-version", "1.0.0-alpha.1", "--source", "test-catalog"],
                           cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertTrue((payload_root / "qml/apps/codex/Main.qml").is_file())

    def test_no_password_collection_and_bridge_is_package_owned(self):
        qml = (ROOT / "appstore/test-packages/codex/payload/qml/apps/codex/Main.qml").read_text()
        backend = (ROOT / "appstore/test-packages/codex/payload/qml/apps/codex/CodexBackend.qml").read_text()
        helper = (ROOT / "appstore/test-packages/codex/payload/scripts/apps/codex/codex-bridge.py").read_text()
        main = (ROOT / "src/main.cpp").read_text()
        self.assertNotIn("ChatGPT password", qml)
        self.assertNotIn("password", backend.lower())
        self.assertIn('"chatgptDeviceCode"', helper)
        self.assertIn('"apiKey"', helper)
        turn_start = helper.split('self.request("turn/start"', 1)[1].split('}, "turn-start")', 1)[0]
        self.assertNotIn('"sandbox"', turn_start)
        self.assertIn('"approvalPolicy"', turn_start)
        self.assertNotIn("CodexManager", main)
        self.assertIn("packageAppBridgeManager", main)


if __name__ == "__main__":
    unittest.main()
