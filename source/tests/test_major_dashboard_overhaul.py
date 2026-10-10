import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class MajorDashboardOverhaulContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_shared_dashboard_shell_and_modes(self):
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        for view in ("SystemOverviewView", "SecurityDashboardView",
                     "StorageManagerView", "AppsDashboardView"):
            self.assertIn(view, shell)
        self.assertIn('activeMode!=="apps"', shell)
        self.assertIn("openSelector", shell)
        self.assertIn('action==="home"', shell)

    def test_widgets_have_density_contract_and_temperature_is_fixed(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        layout = self.read("src/DashboardLayoutManager.cpp")
        for value in ('"small"', '"medium"', '"large"'):
            self.assertIn(value, widget)
        self.assertIn("detailCount", widget)
        self.assertIn("cpuProcesses", widget)
        self.assertIn("memoryProcesses", widget)
        self.assertIn('widgetId == QStringLiteral("temperature")', layout)
        self.assertIn('QStringLiteral("fixed")', layout)

    def test_details_actions_docker_and_security_safety(self):
        modal = self.read("qml/dashboard/v2/DashboardContextModal.qml")
        security = self.read("qml/dashboard/v2/SecurityDashboardView.qml")
        apps = self.read("src/AppManager.cpp")
        for action in ("Open", "Stop", "Kill", "Restart", "Move"):
            self.assertIn(action, modal)
        self.assertIn("dockerStopWarning", modal)
        self.assertIn("Press X again", modal)
        self.assertIn('QStringLiteral("service"), QStringLiteral("docker.service")', apps)
        self.assertIn("maxDefconArmed", security)
        self.assertIn("double", security.lower())

    def test_controller_keyboard_and_modal_priority(self):
        main = self.read("qml/Main.qml")
        keyboard = self.read("qml/components/VirtualKeyboard.qml")
        self.assertIn("pressedActionEdges", main)
        self.assertIn("acceptPressEdge", main)
        self.assertIn("releasePressEdge", main)
        self.assertIn("directionRepeatDelay", main)
        self.assertIn("fireDirectionalRepeat", main)
        self.assertIn("globalSecurityModal", main)
        for token in ("backspaceHoldDelay", "backspaceRepeat", "clearAllRequested",
                      'action === "TRIANGLE"', 'action === "R1"', 'action === "START"'):
            self.assertIn(token, keyboard)
        self.assertIn("l1Held && !clearChordConsumed", keyboard)
        self.assertIn("r3Held && !clearChordConsumed", keyboard)

    def test_multi_user_asset_and_fracture_contracts(self):
        login = self.read("qml/LoginScreen.qml")
        asset = self.read("src/AssetManager.cpp")
        fracture = self.read("src/FractureEffect.cpp")
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        self.assertIn("userBackend.users.length > 1", login)
        self.assertIn("setSelectedUser(selectedUser +", login)
        for suffix in ("atom.svg", "atom.png", "atom.jpeg", "atom.jpg"):
            self.assertIn(suffix, asset)
        self.assertIn("16 + int(random.unit() * 4)", fracture)
        self.assertIn("constexpr int rows = 7, columns = 7", fracture)
        self.assertIn("textureReady", overlay)
        self.assertIn("Math.min(2560", overlay)
        self.assertIn("anchors.fill: parent", overlay)
        self.assertIn("ShaderEffectSource", overlay)

    def test_setup_detection_and_per_user_default_tab(self):
        setup = self.read("src/SetupWizardManager.cpp")
        wizard = self.read("qml/SetupWizard.qml")
        layout = self.read("src/DashboardLayoutManager.cpp")
        for domain in ("account", "timezone", "locale", "keyboard", "network",
                       "controller", "preferences"):
            self.assertIn(f'QStringLiteral("{domain}")', setup)
        self.assertIn("firstIncompleteStep", wizard)
        self.assertIn("defaultDashboardTab", wizard)
        self.assertIn("state/users", layout)

    def test_storage_protects_system_devices(self):
        storage = self.read("src/StorageManager.cpp")
        view = self.read("qml/dashboard/v2/StorageManagerView.qml")
        self.assertIn("validateFormat", storage)
        self.assertIn("active system or boot device can never be formatted", storage)
        self.assertIn("SYSTEM • PROTECTED", view)
        self.assertIn("typed confirmation", view)

    def test_global_incident_modal_preserves_evidence_uncertainty(self):
        modal = self.read("qml/modals/GlobalSecurityEventModal.qml")
        console = self.read("qml/Console.qml")
        self.assertIn("Evidence unavailable", modal)
        self.assertIn("dismissible", modal)
        self.assertIn("openSecurityIncident", console)


if __name__ == "__main__":
    unittest.main()
