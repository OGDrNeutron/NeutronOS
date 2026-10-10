import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DashboardV2ContractTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_legacy_is_a_per_user_available_dashboard_mode(self):
        header = self.read("src/DashboardLayoutManager.h")
        source = self.read("src/DashboardLayoutManager.cpp")
        settings_qml = self.read("qml/apps/settings/Main.qml")
        console = self.read("qml/Console.qml")
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn("Q_PROPERTY(bool legacyAvailable", header)
        self.assertIn('root.insert(QStringLiteral("legacyAvailable")', source)
        self.assertIn('QStringLiteral("legacy")', source)
        self.assertIn('"dashboard.legacyAvailable", "Enable Legacy Dashboard Option"', settings_qml)
        self.assertIn('{id:"legacy",label:"Legacy"}', modern)
        self.assertIn("consoleRoot.legacyDashboardActive", console)
        self.assertIn("id: apps", console)

    def test_console_keeps_apphost_launch_and_notification_boundary_contracts(self):
        console = self.read("qml/Console.qml")
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn("consoleRoot.appLaunchRequested(appData)", console)
        self.assertIn("onNotificationCenterRequested: consoleRoot.notificationCenterRequested()", console)
        self.assertIn("if(zone===0) notificationCenterRequested()", modern)
        self.assertIn("RunningAppsTray", modern)
        self.assertIn("runningAppsTray.openTray()", modern)

    def test_controller_glyphs_cover_required_families(self):
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        for family in ("playstation", "xbox", "nintendo", "generic"):
            self.assertIn(f'"{family}"', modern)
        for action in ("primary", "cancel", "context", "secondary"):
            self.assertIn(f'root.glyph("{action}")', modern)

    def test_dashboard_uses_canonical_assets_and_live_backends(self):
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertNotIn("AnimatedAtomPoster", modern)
        self.assertNotIn("themes/Default/atom.png", modern)
        self.assertIn("themes/Default/screensavers/Nebula.png", modern)
        for backend in ("monitorBackend", "networkBackend", "securityBackend",
                        "controllerBackend", "notificationBackend", "appsBackend",
                        "settingsBackend"):
            self.assertIn(backend, modern)
        self.assertNotIn("12,847", modern)


if __name__ == "__main__":
    unittest.main()
