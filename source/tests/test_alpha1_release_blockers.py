import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Alpha1ReleaseBlockerContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_factory_owner_filter_excludes_root_and_system_accounts(self):
        user_manager = self.read("src/UserManager.cpp")
        setup = self.read("src/SetupWizardManager.cpp")
        policy = self.read("src/HumanAccountPolicy.h")
        self.assertIn("HumanAccountPolicy::isHuman", user_manager)
        self.assertIn("const auto hasHumanOwner", setup)
        self.assertIn("HumanAccountPolicy::namedUserIsHuman", setup)
        self.assertIn('username.trimmed() != QStringLiteral("root")', policy)
        self.assertIn("uid >= range.minimum", policy)
        self.assertIn("interactiveShell(shell)", policy)
        self.assertIn("existingInstallationIsConfigured", setup)

    def test_factory_route_does_not_use_generic_state_as_completion(self):
        setup = self.read("src/SetupWizardManager.cpp")
        self.assertIn("state/users", setup)
        self.assertNotIn('QStringLiteral("state/security")', setup)
        self.assertNotIn('QStringLiteral("state/quickactions")', setup)

    def test_square_release_reaches_shared_keyboard_on_login_and_setup(self):
        login = self.read("qml/LoginScreen.qml")
        wizard = self.read("qml/SetupWizard.qml")
        keyboard = self.read("qml/components/VirtualKeyboard.qml")
        self.assertIn("virtualKeyboard.handleControllerReleased(button)", login)
        self.assertIn("keyboard.handleControllerReleased(value)", wizard)
        self.assertIn("function resetHeldInputState()", keyboard)
        self.assertIn("backspaceHoldDelay.stop()", keyboard)
        self.assertIn("backspaceRepeat.stop()", keyboard)
        self.assertIn("onActiveChanged", keyboard)

    def test_release_builder_packages_new_boot_and_factory_contracts(self):
        builder = self.read("scripts/build-neutronos-alpha1-image.sh")
        for token in (
            "initramfs-tools",
            "unzip",
            "NeutronBootRenderer",
            "design-reference/Boot.zip",
            "53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f",
            "update-initramfs -u -k all",
            "quiet",
            "splash",
            "Setup Wizard completion marker",
            "neutronos-human-accounts",
            "--assert-none",
            "initramfs8",
            "RELEASE_INITRDS",
            'mount --bind "$BOOT" "$ROOT/boot/firmware"',
            "FIRMWARE_INITRD",
        ):
            self.assertIn(token, builder)
        self.assertNotIn("plymouth-set-default-theme", builder)
        self.assertNotIn("-j3", builder)


if __name__ == "__main__":
    unittest.main()
