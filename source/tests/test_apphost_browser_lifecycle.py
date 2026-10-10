import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AppHostBrowserLifecycleTests(unittest.TestCase):
    def test_browser_manifest_selects_isolated_apphost_runtime(self):
        manifest = json.loads((ROOT / "qml/apps/browser/app.json").read_text())
        self.assertEqual(manifest["id"], "browser")
        self.assertEqual(manifest["type"], "isolated")
        self.assertEqual(manifest["launchMode"], "apphost-isolated")

    def test_apphost_owns_external_runtime_launch(self):
        apphost = (ROOT / "qml/apps/AppHost.qml").read_text()
        self.assertIn('appType === "isolated"', apphost)
        self.assertIn("appManager.launchExternalRuntime(activeAppData)", apphost)

    def test_app_manager_preserves_isolated_runtime_type(self):
        source = (ROOT / "src/AppManager.cpp").read_text()
        self.assertIn('t == QStringLiteral("isolated")', source)

    def test_root_shell_uses_generic_apphost_return_contract(self):
        shell = (ROOT / "qml/Main.qml").read_text()
        self.assertIn("appManager.consumeExternalReturnSession()", shell)
        self.assertNotIn("browserManager.consumeReturnSession()", shell)
        self.assertIn("appHostReturnResolveAttempts", shell)
        self.assertIn("appHostSessionReturnTimer.restart()", shell)
        self.assertIn("appHostReturnCoverVisible", shell)
        self.assertNotIn("browserSessionReturnTimer", shell)

    def test_browser_runtime_exposes_tabs_for_running_apps_consumer(self):
        header = (ROOT / "src/BrowserManager.h").read_text()
        source = (ROOT / "src/BrowserManager.cpp").read_text()
        self.assertIn("Q_PROPERTY(QVariantMap runtimeState", header)
        self.assertIn("Q_PROPERTY(QVariantList runtimeTabs", header)
        self.assertIn("Q_PROPERTY(bool runtimeLaunchAllowed", header)
        self.assertIn('QStringLiteral("tabs"), m_runtimeTabs', source)
        self.assertIn('QStringLiteral("isolated"), true', source)

    def test_browser_prefers_fast_vt_park_and_keeps_restart_fallback(self):
        supervisor = (ROOT / "scripts/neutronos-browser-supervisor.py").read_text()
        self.assertIn("def park_shell", supervisor)
        self.assertIn("--signal=SIGSTOP", supervisor)
        self.assertIn("--signal=SIGCONT", supervisor)
        self.assertIn("if not shell_parked and not stop_shell()", supervisor)
        self.assertIn("resume_parked_shell(shell_vt)", supervisor)


if __name__ == "__main__":
    unittest.main()
