#!/usr/bin/env python3
"""Focused contracts for the reference-driven NeutronOS application shell."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReferenceAppUiContracts(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_reference_inventory_maps_only_existing_apps(self):
        names = {path.name.lower() for path in (ROOT / "design-reference").glob("*.png")}
        for expected in (
            "qbittorrent app reference.png", "security app reference.png",
            "music player app reference.png", "file manager app reference.png",
            "gallery app reference.png", "terminal app reference.png",
            "games app reference.png", "settings tile app reference.png",
            "setting list app reference.png", "modal reference.png",
        ):
            self.assertIn(expected, names)
        self.assertNotIn("app store app reference.png", names)

    def test_shared_shell_has_required_status_menu_footer_and_exit_contract(self):
        header = self.read("qml/components/ReferenceAppHeader.qml")
        footer = self.read("qml/components/ReferenceAppFooter.qml")
        modal = self.read("qml/components/ReferenceExitModal.qml")
        self.assertIn('objectName: "referenceAppThreeDotButton"', header)
        self.assertIn("menuFocused", header)
        self.assertIn('text: "Secure."; color: "white"', footer)
        self.assertIn('text: "Intelligent."; color: "white"', footer)
        self.assertIn('text: "Unstoppable."; color: "#FF334E"', footer)
        for label in ('label: "EXIT"', 'label: "LEAVE RUNNING"', 'label: "CLOSE"'):
            self.assertIn(label, modal)
        self.assertIn("forceActiveFocus()", modal)
        self.assertIn("returnFocusItem.forceActiveFocus()", modal)

    def test_dashboard_slogan_and_security_widget_use_live_state(self):
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        self.assertIn('text:"Secure.";color:"white"', dashboard)
        self.assertIn('text:"Intelligent.";color:"white"', dashboard)
        self.assertIn('text:"Unstoppable.";color:theme.red', dashboard)
        self.assertIn("securityBackend.auditValid", widget)
        self.assertIn("securityBackend.securityScore", widget)
        self.assertIn("ACTIVE ALERTS", widget)

    def test_qbittorrent_native_backend_and_real_files_are_wired(self):
        cmake = self.read("CMakeLists.txt")
        main_cpp = self.read("src/main.cpp")
        manager = self.read("src/QBitTorrentManager.cpp")
        qml = self.read("qml/apps/qbittorrent/Main.qml")
        self.assertIn("src/QBitTorrentManager.cpp", cmake)
        self.assertIn('setContextProperty(QStringLiteral("qbitManager")', main_cpp)
        for endpoint in ("/api/v2/torrents/files", "/api/v2/torrents/recheck", "/api/v2/torrents/setForceStart"):
            self.assertIn(endpoint, manager)
        self.assertIn('["GENERAL", "TRACKERS", "PEERS", "FILES", "SPEED", "LOGGER"]', qml)
        self.assertIn("qbitManager.loadTorrentFiles", qml)
        self.assertIn("qbitManager.deleteTorrent", qml)
        self.assertIn("selectedTorrentHashValue", qml)

    def test_settings_tile_list_modes_share_one_backend_and_persist(self):
        qml = self.read("qml/apps/settings/Main.qml")
        manager_h = self.read("src/SettingsManager.h")
        manager_cpp = self.read("src/SettingsManager.cpp")
        self.assertIn('objectName: "settingsTileMode"', qml)
        self.assertIn('displayMode === "tiles" ? "list" : "tiles"', qml)
        self.assertIn('setUiPreference("ui.settingsDisplayMode"', qml)
        self.assertIn("model: root.categories", qml)
        self.assertIn("model: pageModel", qml)
        self.assertIn("setUiPreference", manager_h)
        self.assertIn('^ui\\\\.[A-Za-z0-9_.-]', manager_cpp)

    def test_reference_defined_apps_use_live_models_and_shared_shell(self):
        app_contracts = {
            "security": "securityCoreManager",
            "musicplayer": "musicPlayerManager",
            "filemanager": "fileManager",
            "gallery": "galleryManager",
            "games": "gamesManager",
        }
        for app, backend in app_contracts.items():
            qml = self.read(f"qml/apps/{app}/Main.qml")
            self.assertIn(backend, qml, app)
            self.assertIn("Shared.ReferenceAppHeader", qml, app)
            self.assertIn("Shared.ReferenceAppFooter", qml, app)
            self.assertIn("Shared.ReferenceExitModal", qml, app)
            self.assertIn("menuFocused", qml, app)

    def test_terminal_connected_pill_requires_real_remote_client(self):
        header = self.read("qml/apps/terminal/components/TerminalHeader.qml")
        self.assertIn('secondaryStatus: webClientCount > 0 ? "Connected" : ""', header)
        self.assertNotIn('secondaryStatus: "Connected"', header)

    def test_responsive_shell_uses_logical_scale(self):
        header = self.read("qml/components/ReferenceAppHeader.qml")
        footer = self.read("qml/components/ReferenceAppFooter.qml")
        self.assertIn("width / 1920.0", header)
        self.assertIn("width / 1920.0", footer)
        self.assertIn("clip: true", header)


if __name__ == "__main__":
    unittest.main()
