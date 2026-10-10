import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PhysicalUiRegressionContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_fracture_is_dormant_has_capture_geometry_and_cleans_up(self):
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        renderer = self.read("src/FractureEffect.cpp")
        self.assertIn("visible: running", overlay)
        self.assertIn("anchors.fill: parent", overlay)
        self.assertIn("captureActive = false", overlay)
        self.assertIn("constexpr int rows = 7, columns = 7", renderer)
        self.assertIn("QPointF(0,1.38*t*t)", renderer)
        self.assertIn("QSGOpacityNode", renderer)

    def test_overview_uses_bounded_logical_grid_and_move_transaction(self):
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        layout = self.read("src/DashboardLayoutManager.cpp")
        self.assertIn("gridColumns||15", overview)
        self.assertIn("gridRows||4", overview)
        self.assertIn("columnSpan", overview)
        self.assertIn("rowSpan", overview)
        self.assertIn("shapeVariant", widget)
        for token in ("beginWidgetMove", "previewWidgetMove", "commitWidgetMove", "cancelWidgetMove"):
            self.assertIn(token, overview + layout)

    def test_home_short_hold_and_emergency_chord_coexist(self):
        main = self.read("qml/Main.qml")
        self.assertIn("homePowerHoldTimer.restart()", main)
        self.assertIn("homePowerHoldTriggered", main)
        self.assertIn("root.dispatchControllerPressed(\"home\")", main)
        self.assertIn("root.openLogoutModal()", main)
        self.assertIn("updateEmergencyChord", main)

    def test_power_and_fullscreen_notification_surfaces(self):
        power = self.read("qml/modals/LogoutModal.qml")
        notifications = self.read("qml/modals/NotificationCenterOverlay.qml")
        for label in ("Lock", "Log Out", "Restart NeutronOS", "Reboot System", "Shut Down / Power Off"):
            self.assertIn(label, power)
        self.assertIn("armedActionId", power)
        self.assertIn("anchors.fill: parent", notifications)
        self.assertIn("width: parent.width", notifications)
        self.assertIn("height: parent.height", notifications)
        self.assertIn("ModalActionButton", notifications)
        self.assertIn("Critical security notifications are protected", notifications)

    def test_temperature_has_richer_bounded_motion_and_header_atom_is_removed(self):
        thermal = self.read("qml/dashboard/v2/TemperatureGauge.qml")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        for color in ("#31E8FF", "#FF4A65", "#D65BFF"):
            self.assertIn(color, thermal)
        self.assertIn("schedulePulse", thermal)
        self.assertIn("clip: true", thermal)
        self.assertIn("temperatureFahrenheit", thermal)
        self.assertNotIn("AnimatedAtomPoster", dashboard)

    def test_polish_pass_shared_shell_and_spatial_navigation(self):
        pill = self.read("qml/components/StatusPill.qml")
        exit_modal = self.read("qml/components/ReferenceExitModal.qml")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        dock = self.read("qml/dashboard/v2/DashboardDockIcon.qml")
        self.assertIn('glassSuccessColor: "#16472fe8"', pill)
        for fill in ('fill: "#173E5AEF"', 'fill: "#16452FEF"', 'fill: "#501824EF"'):
            self.assertIn(fill, exit_modal)
        for token in ("spatialNeighbor", "primary*1000", "perpendicular*20", "aligned?0:250"):
            self.assertIn(token, overview)
        self.assertIn("width:92", dock)
        self.assertIn("height:92", dock)

    def test_thermal_baseline_and_identity_are_authoritative(self):
        monitor_h = self.read("src/SystemMonitor.h")
        monitor_cpp = self.read("src/SystemMonitor.cpp")
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        gauge = self.read("qml/dashboard/v2/TemperatureGauge.qml")
        self.assertIn("learnedTemperatureBaseline", monitor_h)
        self.assertIn("adaptiveThermalStatusChanged", monitor_h)
        for label in ("Stable", "Cooler Than Usual", "Warmer Than Usual", "Unstable / Critical"):
            self.assertIn(label, monitor_cpp + gauge)
        self.assertIn("userManager.activeUser.username", widget)
        self.assertNotIn('return "Local"', widget)

    def test_terminal_and_security_physical_geometry_contracts(self):
        terminal = self.read("qml/apps/terminal/Main.qml")
        security = self.read("qml/apps/security/Main.qml")
        self.assertIn("anchors.top: header.bottom", terminal)
        self.assertIn("anchors.bottom: referenceFooter.top", terminal)
        self.assertIn("Shared.ReferenceAppFooter", terminal)
        self.assertIn("Shared.ReferenceExitModal", terminal)
        self.assertIn("Qt.callLater(function()", terminal)
        self.assertIn("height: 56", security)
        self.assertIn("font.pixelSize: 16", security)

    def test_unlock_preload_and_app_return_reuse_console(self):
        main = self.read("qml/Main.qml")
        self.assertIn("if (root.consoleResident)\n                return", main)
        self.assertIn("root.consoleResident = true", main)
        self.assertIn('root.logUnlock("CAPTURE_REQUESTED")', main)
        self.assertIn('root.logUnlock("CONSOLE_READY")', main)
        self.assertIn("Date.now() - root.unlockStartedAtMs", main)

    def test_legacy_selector_availability_and_fallback(self):
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        console = self.read("qml/Console.qml")
        settings = self.read("qml/apps/settings/Main.qml")
        layout = self.read("src/DashboardLayoutManager.cpp")
        self.assertIn('System Overview"},{id:"security",label:"Security"},{id:"storage",label:"Storage"},{id:"apps",label:"Apps"},{id:"legacy",label:"Legacy', modern)
        self.assertIn("selectorOnly", modern)
        self.assertIn("modernDashboardView.activeMode = \"legacy\"", console)
        self.assertIn("!consoleRoot.dashboardLayoutBackend.legacyAvailable", console)
        self.assertIn("dashboardTabOptions()", settings)
        self.assertIn('"dashboard.legacyAvailable"', settings)
        self.assertIn('m_defaultTab = QStringLiteral("system")', layout)


if __name__ == "__main__":
    unittest.main()
