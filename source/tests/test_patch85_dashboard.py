import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class Patch85DashboardTests(unittest.TestCase):
    def read(self, path): return (ROOT / path).read_text(encoding="utf-8")

    def test_temperature_uses_authoritative_fahrenheit_source_and_active_throttle(self):
        gauge = self.read("qml/dashboard/v2/TemperatureGauge.qml")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        monitor = self.read("src/SystemMonitor.cpp")
        self.assertIn('temperatureFahrenheit', gauge)
        self.assertIn('Math.round(root.temperatureFahrenheit) + "°F"', gauge)
        self.assertIn('cpuTemperature', widget)
        self.assertIn('property bool throttled', gauge)
        self.assertIn('"Unstable / Critical"', gauge)
        self.assertIn("thermalThrottled", dashboard)
        self.assertIn("activeRaspberryPiThrottle", monitor)

    def test_uptime_user_modal_network_modal_and_dock_contract(self):
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertNotIn('title:"◷  Uptime"', dashboard)
        self.assertIn('text:"Uptime  "+', dashboard)
        self.assertIn('"network","user","security"', dashboard)
        self.assertIn("DashboardDockIcon", dashboard)
        self.assertNotIn("DashboardAppTile {", dashboard)
        self.assertIn('"Open "+String', dashboard)
        dock = self.read("qml/dashboard/v2/DashboardDockIcon.qml")
        self.assertIn('themes/Default/apps/icons/', dock)

    def test_controller_names_and_background_safety(self):
        header = self.read("src/ControllerManager.h")
        source = self.read("src/ControllerManager.cpp")
        settings = self.read("src/SettingsManager.cpp")
        for name in ("DualShock 4", "DualSense", "Xbox Wireless Controller", "Switch Pro Controller"):
            self.assertIn(name, source)
        self.assertIn("controllerDisplayName", header)
        self.assertIn("display.userClockBackground", settings)
        self.assertIn("info.isSymLink()", settings)

    def test_animations_are_visibility_gated(self):
        for path in ("qml/dashboard/v2/TemperatureGauge.qml", "qml/dashboard/v2/AnimatedAtomPoster.qml"):
            text = self.read(path)
            self.assertIn("animationEnabled", text)
            self.assertIn("visible", text)
            self.assertIn("running: root.animationEnabled", text)

if __name__ == "__main__": unittest.main()
