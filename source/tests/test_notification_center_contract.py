import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class NotificationCenterContractTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_modern_bell_and_top_boundary_open_canonical_overlay(self):
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        console = self.read("qml/Console.qml")
        main = self.read("qml/Main.qml")
        self.assertIn("onActivated: root.notificationCenterRequested()", dashboard)
        self.assertIn("else if(headerIndex===1)notificationCenterRequested()", dashboard)
        self.assertIn("onNotificationCenterRequested: consoleRoot.notificationCenterRequested()", console)
        self.assertIn("notificationCenterOverlay.openCenter()", main)
        self.assertIn("notificationManager", main)

    def test_controller_navigation_close_and_focus_restore_are_explicit(self):
        overlay = self.read("qml/modals/NotificationCenterOverlay.qml")
        main = self.read("qml/Main.qml")
        for action in ("up", "down", "primary", "cancel"):
            self.assertIn(f'action === "{action}"', overlay)
        self.assertIn("positionViewAtIndex", overlay)
        self.assertIn("notificationCenterOverlay.handleControllerPressed(clean)", main)
        self.assertIn("consoleLoader.item.forceActiveFocus()", main)

    def test_backend_capabilities_and_signal_driven_updates_are_exposed(self):
        backend = self.read("src/NotificationManager.h")
        overlay = self.read("qml/modals/NotificationCenterOverlay.qml")
        for capability in ("unreadCount", "notifications", "markRead", "markAllRead",
                           "dismiss", "clearAll", "clearOrdinary", "clearSecurity"):
            self.assertIn(capability, backend)
        self.assertIn("onNotificationsChanged()", overlay)
        self.assertIn("root.refreshNotifications()", overlay)
        self.assertIn("NO NOTIFICATIONS", overlay)
        self.assertIn("modelData.timestampMs", overlay)
        self.assertIn("modelData.priority", overlay)

    def test_r3_and_authenticated_l3_contract(self):
        overlay = self.read("qml/modals/NotificationCenterOverlay.qml")
        backend = self.read("src/SecurityManager.cpp")
        manager = self.read("src/NotificationManager.h")
        self.assertIn("backend.clearAll()", overlay)
        self.assertIn("beginAuthenticatedNotificationClear", overlay)
        self.assertIn("onAuthenticatedNotificationClearFinished", overlay)
        self.assertNotIn("backend.clearSecurity()", overlay)
        self.assertIn("beginLoginComboVerification(username, rollingBuffer)", backend)
        self.assertIn("clearAllSecurityAuthenticated()", backend)
        self.assertIn("friend class SecurityManager", manager)
        self.assertNotIn("Q_INVOKABLE QVariantMap clearAllSecurityAuthenticated", manager)
        self.assertIn("clearArmTimer", overlay)
        self.assertIn("r3Pressed", overlay)

    def test_overlay_uses_bounded_event_driven_effects(self):
        overlay = self.read("qml/modals/NotificationCenterOverlay.qml")
        self.assertNotIn("Animation.Infinite", overlay)
        self.assertNotIn("repeat: true", overlay)
        self.assertIn("visible: opened || closeSignalTimer.running", overlay)
        self.assertIn("enabled: opened", overlay)


if __name__ == "__main__":
    unittest.main()
