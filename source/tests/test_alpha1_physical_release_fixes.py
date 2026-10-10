import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Alpha1PhysicalReleaseFixContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text()
        cls.wizard = (ROOT / "qml/SetupWizard.qml").read_text()
        cls.keyboard = (ROOT / "qml/components/VirtualKeyboard.qml").read_text()
        cls.helper = (ROOT / "release/neutronos-privileged-helper").read_text()

    def test_firmware_rainbow_is_suppressed_and_contracted(self):
        self.assertIn('neutronos-configure-boot-root', self.builder)
        installer = (ROOT / "scripts/neutronos-configure-boot-root").read_text()
        self.assertIn("disable_splash=1", installer)
        self.assertIn("firmware rainbow splash is not disabled", self.builder)

    def test_boot_completion_uses_real_login_rendering_without_99_hold(self):
        progress = (ROOT / "src/BootProgressState.cpp").read_text()
        shell = (ROOT / "qml/ShellWindow.qml").read_text()
        self.assertIn("percent > previous", progress)
        self.assertIn("destinationInputReady", shell)
        self.assertIn("bootCoverVisible = false", shell)
        self.assertIn("markDestinationPresented()", shell)
        self.assertNotIn("(99,", shell)
        self.assertNotIn("Timer {", shell)

    def test_welcome_title_is_exact_and_only_os_is_red(self):
        self.assertIn('welcomeTitle: "Welcome To NeutronOS"', self.wizard)
        rich = 'Welcome To Neutron<span style=\\"color:#FF3040\\">OS</span>'
        self.assertIn(rich, self.wizard)
        self.assertNotIn("WELCOME TO NEUTRONOS", self.wizard)

    def test_setup_keyboard_options_is_single_edge_enter(self):
        self.assertIn('if (action === "system")', self.wizard)
        self.assertIn("if (!optionsHeld)", self.wizard)
        self.assertIn("keyboard.pressEnter()", self.wizard)
        self.assertIn('if (normalize(value) === "system")', self.wizard)
        self.assertIn("optionsHeld = false", self.wizard)
        self.assertIn("function pressEnter()", self.keyboard)
        self.assertIn("enterPressed()", self.keyboard)
        self.assertIn('if (action === "SQUARE")', self.keyboard)
        self.assertIn("backspaceRepeat.stop()", self.keyboard)

    def test_password_visibility_is_shared_hidden_and_value_preserving(self):
        self.assertIn("property bool passwordVisible: false", self.wizard)
        self.assertIn('property string confirmPassword: ""', self.wizard)
        self.assertIn('passwordVisible ? "Hide Password" : "Show Password"', self.wizard)
        self.assertIn('passwordVisible = !passwordVisible', self.wizard)
        self.assertIn('accountPassword !== confirmPassword', self.wizard)
        self.assertNotRegex(self.wizard, r'passwordVisible\s*=.*accountPassword\s*=')

    def test_account_helper_is_packaged_with_clean_image_toolchain(self):
        self.assertIn('install -m 0755 "$PROJECT/release/neutronos-privileged-helper"', self.builder)
        for package in ("passwd", "libpam-modules", "python3", "sudo"):
            self.assertRegex(self.builder, rf"\b{re.escape(package)}\b")
        for tool in ("useradd", "usermod", "userdel", "chpasswd", "hostnamectl"):
            self.assertIn(tool, self.helper)
            self.assertIn(tool, self.builder)
        self.assertIn("input_text=f'{user}:{password}\\n'", self.helper)
        self.assertNotIn("password]", self.helper)

    def test_account_creation_rolls_back_new_user_and_never_completes_on_failure(self):
        manager = (ROOT / "src/SetupWizardManager.cpp").read_text()
        self.assertIn("Setup account helper missing or not executable", manager)
        self.assertIn("if created:", self.helper)
        self.assertIn("run(['userdel','-r',user],check=False)", self.helper)
        self.assertIn("m_setupComplete = true", manager)
        self.assertIn("m_setupComplete = false", manager)
        complete = manager[manager.index("bool SetupWizardManager::completeSetup()"):]
        self.assertLess(complete.index("m_setupDomains = detectSetupDomains()"),
                        complete.index("m_setupComplete = true"))

    def test_three_physical_service_executables_are_explicitly_packaged(self):
        expected = {
            "neutron-securityd.service": "neutron-securityd.py",
            "neutron-security-watchdog.service": "neutron-security-watchdog.py",
            "neutronos-offline-network.service": "neutronos-offline-networkd.py",
        }
        for unit, executable in expected.items():
            self.assertIn(unit, self.builder)
            self.assertIn(executable, self.builder)
        self.assertIn("RELEASE_SERVICE_EXECUTABLES", self.builder)
        self.assertIn('"$ROOT/usr/local/lib/neutronos/neutronos_ipc"', self.builder)
        self.assertIn("import neutronos_ipc, neutronos_ipc.authorization", self.builder)
        self.assertIn('systemd-analyze --root="$ROOT" verify', self.builder)

    def test_wizard_polish_is_lightweight_and_focus_safe(self):
        self.assertIn("id: contentPanel", self.wizard)
        self.assertIn("id: pageEnter", self.wizard)
        self.assertIn("stepTransitionRunning", self.wizard)
        self.assertIn("Behavior on scale", self.wizard)
        for expensive in ("ShaderEffect", "GaussianBlur", "ParticleSystem"):
            self.assertNotIn(expensive, self.wizard)


if __name__ == "__main__":
    unittest.main()
