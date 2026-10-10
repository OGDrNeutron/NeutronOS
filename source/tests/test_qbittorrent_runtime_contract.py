import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class QBittorrentRuntimeContractTests(unittest.TestCase):
    def test_connected_requires_api_reachability_not_container_state(self):
        qml = (ROOT / "qml/apps/qbittorrent/Main.qml").read_text()
        backend = (ROOT / "src/QBitTorrentManager.cpp").read_text()
        self.assertIn("qbitManager.authenticated", qml)
        self.assertIn("qbitManager.error.length <= 0", qml)
        self.assertIn('/api/v2/app/version', backend)
        self.assertIn("result.status == 200", backend)
        self.assertIn("result.status == 204", backend)

    def test_endpoint_is_configurable_and_errors_name_it(self):
        backend = (ROOT / "src/QBitTorrentManager.cpp").read_text()
        self.assertIn("NEUTRONOS_QBIT_URL", backend)
        self.assertIn('object.value(QStringLiteral("url"))', backend)
        self.assertIn("m_baseUrl.toString()", backend)

    def test_neutronos_preserves_docker_restart_policy(self):
        app_manager = (ROOT / "src/AppManager.cpp").read_text()
        docker_manager = (ROOT / "src/DockerManager.cpp").read_text()
        self.assertNotIn('QStringLiteral("update"), QStringLiteral("--restart=no")', app_manager)
        self.assertNotIn('QStringLiteral("update"), QStringLiteral("--restart=no")', docker_manager)
        self.assertIn('QStringLiteral("unless-stopped")', docker_manager)


if __name__ == "__main__":
    unittest.main()
