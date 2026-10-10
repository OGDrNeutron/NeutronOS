import json
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReleaseHygieneTests(unittest.TestCase):
    def test_app_manifests_are_unique_and_entry_points_exist(self):
        seen = set()
        for path in sorted((ROOT / "qml/apps").glob("*/app.json")):
            manifest = json.loads(path.read_text())
            app_id = manifest["id"]
            self.assertNotIn(app_id, seen, f"duplicate app id: {app_id}")
            seen.add(app_id)
            source = manifest.get("qmlSource", f"{app_id}/Main.qml")
            self.assertTrue((ROOT / "qml/apps" / source).is_file(),
                            f"missing entry point for {app_id}: {source}")

    def test_transactional_registry_has_no_orphaned_payload(self):
        registry = json.loads((ROOT / "state/app-store/installed.json").read_text())
        for package_id, package in registry.get("packages", {}).items():
            self.assertEqual(package_id, package.get("id"))
            for relative in package.get("files", []):
                self.assertTrue((ROOT / relative).is_file(),
                                f"orphaned registration: {package_id}: {relative}")
        staging = ROOT / "state/app-store/staging"
        if staging.exists():
            self.assertEqual(list(staging.iterdir()), [], "abandoned App Store staging data")

    def test_codex_archive_contains_every_registered_app_file(self):
        artifact = ROOT / "dist/apps/Codex-1.0.0-alpha.1-arm64.napp"
        registry = json.loads((ROOT / "state/app-store/installed.json").read_text())
        registered = set(registry["packages"]["codex"]["files"])
        with zipfile.ZipFile(artifact) as archive:
            packaged = {
                name.removeprefix("payload/")
                for name in archive.namelist()
                if name.startswith("payload/") and not name.endswith("/")
            }
        self.assertEqual(packaged, registered)

    def test_inactive_app_resources_are_gated_or_unloaded(self):
        host = (ROOT / "qml/apps/AppHost.qml").read_text()
        music = (ROOT / "qml/apps/musicplayer/Main.qml").read_text()
        qbit = (ROOT / "qml/apps/qbittorrent/Main.qml").read_text()
        codex = (ROOT / "qml/apps/codex/CodexBackend.qml").read_text()
        self.assertIn("active: root.appRunning", host)
        self.assertIn('activeAppSource = ""', host)
        self.assertIn("running: root.visible && backend && backend.visualizationConsumerActive", music)
        self.assertIn("running: app.visible &&", qbit)
        self.assertIn("transport.stop(appId)", codex)

    def test_repository_has_no_broken_symbolic_links(self):
        broken = [str(path.relative_to(ROOT)) for path in ROOT.rglob("*")
                  if path.is_symlink() and not path.exists()]
        self.assertEqual(broken, [])


if __name__ == "__main__":
    unittest.main()
