import os
import pathlib
import stat
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class RuntimePathContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text()
        cls.main = (ROOT / "src/main.cpp").read_text()
        cls.assets = (ROOT / "src/AssetManager.cpp").read_text()
        cls.app_store = (ROOT / "src/AppStoreManager.cpp").read_text()
        cls.app_manager = (ROOT / "src/AppManager.cpp").read_text()
        cls.package_helper = (ROOT / "scripts/neutronos-appstore-package.py").read_text()
        cls.state_setup = (ROOT / "scripts/neutronos-state-setup").read_text()
        cls.service = (ROOT / "systemd/neutronos.service").read_text()
        cls.update_recovery = (ROOT / "src/UpdateRecoveryManager.cpp").read_text()
        cls.backup_restore = (ROOT / "src/BackupRestoreManager.cpp").read_text()
        cls.terminal = (ROOT / "src/TerminalManager.cpp").read_text()

    def test_startup_validates_but_does_not_create_immutable_payload(self):
        startup = self.main.split("static void ensureRuntimeDirectories", 1)[1]
        startup = startup.split("static void exposeSystemContext", 1)[0]
        self.assertIn("Required immutable payload directory is unavailable", startup)
        self.assertNotIn("mkpath", startup)
        asset_setup = self.assets.split("void AssetManager::ensureThemeDirectories", 1)[1]
        self.assertNotIn("mkpath", asset_setup)
        self.assertIn("required packaged directory is unavailable", asset_setup)

    def test_app_store_config_is_static_and_runtime_state_is_under_var_lib(self):
        self.assertIn('QStringLiteral("config/app-store")', self.app_store)
        self.assertIn('QStringLiteral("app-store")', self.app_store)
        self.assertIn('"NEUTRONOS_STATE_DIR"', self.app_store)
        self.assertNotIn(
            'QDir(configDirectory()).filePath(QStringLiteral("repository"))',
            self.app_store,
        )
        self.assertIn('QStringLiteral("repositories.json")', self.app_store)

    def test_other_mutable_settings_do_not_write_packaged_config(self):
        self.assertIn('settings/update-recovery.json', self.update_recovery)
        self.assertIn('settings/backup-restore.json', self.backup_restore)
        resolve = self.terminal.split("void TerminalManager::resolvePaths()", 1)[1]
        resolve = resolve.split("bool TerminalManager::ensureDirectories()", 1)[0]
        self.assertIn("QDir(m_stateDir)", resolve)
        self.assertNotIn("QDir(m_repoRoot)", resolve)

    def test_dynamic_app_payload_and_assets_are_state_scoped(self):
        self.assertIn("app-store/payload", self.assets)
        self.assertIn("app-store/payload", self.app_manager)
        self.assertIn("Installed/state-backed apps", self.app_manager)
        self.assertIn('state / "payload"', self.package_helper)
        self.assertIn("--state-root", self.package_helper)
        self.assertIn("managed_target(payload_root, state_root", self.package_helper)

    def test_state_setup_owns_only_explicit_mutable_app_store_paths(self):
        for suffix in (
            '"$STATE/app-store"',
            '"$STATE/app-store/downloads"',
            '"$STATE/app-store/payload"',
            '"$STATE/app-store/packages"',
        ):
            self.assertIn(suffix, self.state_setup)
        self.assertNotIn("chmod -R 777", self.state_setup)

    def test_release_payload_is_root_owned_readable_and_not_world_writable(self):
        self.assertIn('chown -hR root:root "$ROOT/opt/neutronos"', self.builder)
        self.assertIn("immutable NeutronOS payload contains world-writable content", self.builder)
        self.assertIn("display account can write immutable payload directory", self.builder)
        self.assertNotIn('chmod -R 777 "$ROOT/opt/neutronos"', self.builder)

    def test_legacy_state_alias_cannot_redirect_host_side_cleanup(self):
        alias = self.builder.index('neutronos-prepare-state-alias')
        last_legacy_cleanup = self.builder.index(
            "release_rm home/echo/NeutronOS/state\n"
        )
        self.assertGreater(alias, last_legacy_cleanup)
        self.assertNotIn(
            "release_rm home/echo/NeutronOS/state",
            self.builder[alias:],
        )
        self.assertIn('! -L "$legacy_state"', self.builder)

    def test_legacy_state_directory_is_replaced_by_staging_safe_idempotent_alias(self):
        helper = ROOT / "scripts/neutronos-prepare-state-alias"
        with tempfile.TemporaryDirectory() as directory:
            image = pathlib.Path(directory) / "image-root"
            payload = image / "home/echo/NeutronOS"
            legacy = payload / "state"
            canonical = image / "var/lib/neutronos"
            legacy.mkdir(parents=True)
            canonical.mkdir(parents=True)
            (legacy / "stale-development-state").write_text("must disappear")

            subprocess.run(["bash", str(helper), str(image)], check=True)
            self.assertTrue(legacy.is_symlink())
            self.assertEqual(os.readlink(legacy), "../../../var/lib/neutronos")
            self.assertEqual(legacy.resolve(), canonical.resolve())
            self.assertFalse(str(image) in os.readlink(legacy))
            self.assertFalse((legacy / "stale-development-state").exists())
            self.assertFalse(legacy.resolve().is_relative_to(payload.resolve()))

            # Writes through the compatibility spelling land in canonical
            # mutable state even when the payload itself is read-only.
            payload.chmod(0o555)
            (legacy / "alias-write-probe").write_text("state")
            self.assertEqual((canonical / "alias-write-probe").read_text(), "state")

            # Repeated preparation replaces only the link; canonical state and
            # the alias semantics survive later unrelated sanitization.
            payload.chmod(0o755)
            subprocess.run(["bash", str(helper), str(image)], check=True)
            self.assertTrue(legacy.is_symlink())
            self.assertEqual(legacy.resolve(), canonical.resolve())
            self.assertTrue((canonical / "alias-write-probe").is_file())

    def test_static_asset_directories_are_packaged_before_runtime(self):
        for path in (
            "themes/Default/apps/icons",
            "themes/Default/apps/posters",
            "themes/Default/users",
            "config/app-store/repository",
        ):
            self.assertIn(path, self.builder)

    def test_smoke_is_unprivileged_utf8_and_rejects_permission_diagnostics(self):
        self.assertIn("runuser -u echo", self.builder)
        self.assertIn("LANG=C.UTF-8 LC_ALL=C.UTF-8", self.builder)
        self.assertIn("Permission denied|Failed to create directory", self.builder)
        self.assertRegex(self.service, r"(?m)^User=neutronos$")
        self.assertRegex(self.service, r"(?m)^Group=neutronos$")
        self.assertRegex(self.service, r"(?m)^Environment=LANG=C\.UTF-8$")
        self.assertRegex(self.service, r"(?m)^Environment=LC_ALL=C\.UTF-8$")

    def test_transactional_package_never_writes_immutable_root(self):
        # A minimal invalid package reaches argument/path initialization but
        # cannot mutate either tree; this also contracts the separate roots.
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            immutable = base / "payload"
            state_root = base / "state"
            immutable.mkdir(mode=0o555)
            archive = base / "invalid.napp"
            archive.write_bytes(b"not-a-zip")
            result = subprocess.run(
                [
                    "python3", str(ROOT / "scripts/neutronos-appstore-package.py"),
                    "install", "--root", str(immutable),
                    "--state-root", str(state_root), "--package", str(archive),
                ],
                text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(immutable.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
