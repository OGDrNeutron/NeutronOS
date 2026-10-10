import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class TelemetryCoreContractTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_dashboard_consumes_typed_canonical_properties(self):
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        console = self.read("qml/Console.qml")
        for prop in ("cpuValid", "memoryValid", "temperatureCelsius",
                     "temperatureValid", "rxBytesPerSecond",
                     "txBytesPerSecond", "activeInterface"):
            self.assertIn(prop, dashboard)
        self.assertIn("setDashboardActive", console)
        self.assertIn("clockBackend: consoleRoot.clockExperienceBackend", console)

    def test_backend_uses_kernel_sources_and_typed_validity(self):
        header = self.read("src/SystemMonitor.h")
        source = self.read("src/SystemMonitor.cpp")
        for prop in ("cpuFrequencyHz", "cpuModel", "cpuValid", "memoryValid",
                     "temperatureCelsius", "temperatureValid", "networkValid",
                     "rxBytesPerSecond", "txBytesPerSecond", "uptimeSeconds",
                     "uptimeValid"):
            self.assertIn(prop, header)
        for source_path in ("/proc/stat", "/proc/meminfo", "/proc/net/dev",
                            "/proc/uptime", "/sys/class/thermal"):
            self.assertIn(source_path, source)

    def test_disappearing_sources_clear_or_reset_state(self):
        source = self.read("src/SystemMonitor.cpp")
        self.assertIn("m_temperatureValid = false", source)
        self.assertIn("m_memoryValid = false", source)
        self.assertIn("m_networkValid = false", source)
        self.assertIn("m_lastNetworkInterface.clear()", source)
        self.assertIn('[QStringLiteral("connected")] = false', source)

    def test_sampling_is_centralized_and_visibility_aware(self):
        source = self.read("src/SystemMonitor.cpp")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn("m_fastTimer.setInterval(2000)", source)
        self.assertIn("m_cacheTimer.setInterval(15000)", source)
        self.assertIn("active ? 2000 : 6000", source)
        self.assertIn("active ? 15000 : 30000", source)
        self.assertNotIn("/proc/", dashboard)
        self.assertNotIn("QProcess", dashboard)


if __name__ == "__main__":
    unittest.main()
