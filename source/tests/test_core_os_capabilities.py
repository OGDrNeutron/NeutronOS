import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
RECOVERY = ROOT / "scripts/neutronos-recovery-control"


class RecoveryContractTests(unittest.TestCase):
    def run_control(self, state, *arguments):
        env = dict(os.environ, NEUTRONOS_RECOVERY_TEST_ROOT=str(state))
        completed = subprocess.run(
            [str(RECOVERY), *arguments], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_one_shot_marker_is_consumed_and_normal_next_boot_remains(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            runtime = root / "run"
            prepared = self.run_control(root, "prepare", "test recovery")
            self.assertTrue(prepared["oneShot"])
            self.assertTrue((root / "next-boot.json").exists())
            consumed = self.run_control(root, "consume", str(runtime))
            self.assertTrue(consumed["active"])
            self.assertFalse((root / "next-boot.json").exists())
            self.assertTrue((runtime / "recovery-active.json").exists())
            self.assertFalse(self.run_control(root, "consume", str(runtime))["active"])

    def test_three_genuine_failures_trigger_safe_mode_and_stable_resets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for count in range(1, 4):
                state = self.run_control(root, "record-failure", "exit-code")
                self.assertEqual(state["consecutiveFailures"], count)
            self.assertTrue((root / "safe-mode-next-boot.json").exists())
            stable = self.run_control(root, "mark-stable")
            self.assertEqual(stable["consecutiveFailures"], 0)
            self.assertFalse((root / "safe-mode-next-boot.json").exists())

    def test_unknown_recovery_operation_is_default_denied(self):
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, NEUTRONOS_RECOVERY_TEST_ROOT=temporary)
            result = subprocess.run([str(RECOVERY), "erase"], env=env, check=False)
            self.assertNotEqual(result.returncode, 0)


class CoreCapabilityContractTests(unittest.TestCase):
    def text(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_canonical_release_identity(self):
        version = json.loads(self.text("config/version.json"))
        for field in ("version", "build", "channel", "releaseId", "releaseDate",
                      "baseDistribution", "minimumUpdaterVersion", "architecture"):
            self.assertIn(field, version)
        self.assertRegex(version["version"], r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
        self.assertEqual(version["architecture"], "arm64")

    def test_update_manifest_is_signed_before_artifact_hash_is_trusted(self):
        source = self.text("src/UpdateRecoveryManager.cpp")
        self.assertIn("neutronos.update-manifest.v2", source)
        self.assertIn("crypto_sign_verify_detached", source)
        self.assertIn("m_manifestVerified", source)
        self.assertIn("artifact is denied", source)
        self.assertIn("stage-update", source)
        self.assertNotIn('startDetachedRecoveryAction(QStringLiteral("install-update")', source)

    def test_atomic_state_is_explicit_and_not_faked(self):
        config = json.loads(self.text("config/update-recovery.json"))
        self.assertEqual(config["stateModel"], ["CURRENT", "CANDIDATE", "PREVIOUS_KNOWN_GOOD"])
        self.assertEqual(config["atomicBackend"], "unavailable-single-ext4-root")
        self.assertFalse(config["developmentLiveInstallAllowed"])

    def test_power_recovery_is_developer_only_and_diagnostics_shared(self):
        power = self.text("qml/modals/LogoutModal.qml")
        main = self.text("qml/Main.qml")
        settings = self.text("qml/apps/settings/Main.qml")
        self.assertIn("developerModeEnabled ?", power)
        self.assertIn('"id": "recovery"', power)
        self.assertIn('"id": "diagnostics"', power)
        self.assertIn("DiagnosticsCenter", main)
        self.assertIn("DiagnosticsCenter", settings)

    def test_diagnostic_domains_and_evidence(self):
        source = self.text("src/DiagnosticsManager.cpp")
        for domain in ("cpu", "ram", "temperature", "storage", "filesystem",
                       "network", "services", "controller", "display", "security", "app-runtime"):
            self.assertIn(f'StringLiteral("{domain}")', source)
        self.assertIn('StringLiteral("evidence")', source)
        self.assertIn('StringLiteral("suggestedAction")', source)

    def test_core_models_cover_remaining_os_surfaces(self):
        header = self.text("src/CoreCapabilitiesManager.h")
        for name in ("appPermissions", "bluetoothDevices", "audioOutputs", "displayModes",
                     "services", "helpSections", "searchResults", "networkDiagnostics",
                     "securityTimeline", "securityProfiles", "uiScale", "dndMode",
                     "adaptiveDashboard"):
            self.assertIn(name, header)
        source = self.text("src/CoreCapabilitiesManager.cpp")
        self.assertIn('permission=="Privileged Operations"', source)
        self.assertIn("kProtectedUnits.contains", source)
        self.assertIn("MAXIMUM must be armed", source)

    def test_local_help_has_every_required_section(self):
        sections = json.loads(self.text("config/help-center.json"))
        ids = {entry["id"] for entry in sections}
        required = {"getting-started", "controller", "dashboard", "applications", "settings",
                    "networking", "bluetooth", "audio", "storage", "security", "updates",
                    "recovery", "notifications", "troubleshooting", "keyboard", "developer"}
        self.assertTrue(required.issubset(ids))

    def test_backup_excludes_privileged_secrets_and_live_restore_is_gated(self):
        helper = self.text("scripts/neutronos-backup-restore.sh")
        self.assertIn("privileged-runtime-secrets-excluded", helper)
        self.assertIn("payload.sha256", helper)
        self.assertIn("NEUTRONOS_ALLOW_LIVE_RESTORE", helper)
        self.assertNotIn("copy_if_exists /var/lib/neutronos/security", helper)


if __name__ == "__main__":
    unittest.main()
