import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class RunningAppsTrayTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_authoritative_registry_is_exposed_by_app_manager(self):
        header = self.read("src/AppManager.h")
        source = self.read("src/AppManager.cpp")
        self.assertIn("Q_PROPERTY(QVariantList runningApps", header)
        self.assertIn("void AppManager::rebuildRunningApps()", source)
        self.assertIn("QSet<QString> seen", source)
        self.assertIn("runtimeId", source)
        self.assertIn("isolationState", source)

    def test_launch_exit_background_and_crash_cleanup_feed_registry(self):
        manager = self.read("src/AppManager.cpp")
        host = self.read("qml/apps/AppHost.qml")
        self.assertIn("m_runtimeLaunchTimes.insert(cleanId", manager)
        self.assertIn("m_runtimeLaunchTimes.remove(cleanId)", manager)
        self.assertIn("m_backgroundApps.insert(cleanId)", manager)
        self.assertIn("appManager.appClosed(activeAppId)", host)

    def test_focus_and_close_route_through_manager_lifecycle(self):
        manager = self.read("src/AppManager.cpp")
        main = self.read("qml/Main.qml")
        self.assertIn("bool AppManager::focusRuntime", manager)
        self.assertIn("emit runtimeFocusRequested(app)", manager)
        self.assertIn("return closeApp(appById(appId))", manager)
        self.assertIn("onRuntimeFocusRequested(appData)", main)
        self.assertIn("root.beginLaunchApp(appData)", main)

    def test_browser_and_sanitized_tab_children_join_shared_model(self):
        manager = self.read("src/AppManager.cpp")
        self.assertIn("m_browserManager->runtimeActive()", manager)
        self.assertIn("m_browserManager->runtimeTabs()", manager)
        self.assertIn("url.host()", manager)
        self.assertNotIn('child.insert(QStringLiteral("url")', manager)
        self.assertIn("parentRuntimeId", manager)

    def test_browser_control_protocol_is_constrained_and_stale_safe(self):
        header = self.read("src/BrowserManager.h")
        source = self.read("src/BrowserManager.cpp")
        standalone = self.read("qml/apps/browser/Standalone.qml")
        for action in ("focus-runtime", "focus-tab", "close-tab", "close-runtime"):
            self.assertIn(action, source)
        self.assertIn("currentMSecsSinceEpoch() - created > 10000", source)
        self.assertIn("requestTabClose", header)
        self.assertIn("onRuntimeControlRequested", standalone)
        self.assertIn("browserLoader.item.closeTab(tabIndex)", standalone)

    def test_missing_browser_status_clears_shared_runtime(self):
        browser = self.read("src/BrowserManager.cpp")
        manager = self.read("src/AppManager.cpp")
        self.assertIn("markUnavailable();", browser)
        self.assertIn("updateAppStatus(QStringLiteral(\"browser\"), m_browserManager->runtimeActive())", manager)

    def test_tray_empty_state_and_controller_contract(self):
        tray = self.read("qml/dashboard/v2/RunningAppsTray.qml")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn("No active apps", tray)
        self.assertIn("anchors.bottom: parent.bottom", tray)
        self.assertIn("ListView.Contain", tray)
        for action in ("up", "down", "left", "right", "primary", "cancel"):
            self.assertIn(f'action === "{action}"', tray)
        self.assertIn("runningAppsTray.openTray()", dashboard)
        self.assertIn("footerIndex=5", dashboard)


if __name__ == "__main__":
    unittest.main()
