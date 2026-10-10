import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CLASSIFIER = ROOT / "scripts/neutronos-human-accounts"


class HumanAccountPolicyTests(unittest.TestCase):
    def make_root(self, passwd: str, login_defs: str = "UID_MIN 1000\nUID_MAX 60000\n"):
        temporary = tempfile.TemporaryDirectory()
        root = pathlib.Path(temporary.name)
        (root / "etc").mkdir()
        (root / "etc/passwd").write_text(textwrap.dedent(passwd).lstrip())
        (root / "etc/login.defs").write_text(login_defs)
        for home in ("home/alice", "home/echo"):
            (root / home).mkdir(parents=True)
        return temporary, root

    def classify(self, root: pathlib.Path):
        result = subprocess.run(
            [str(CLASSIFIER), "--root", str(root)],
            text=True, capture_output=True, check=True,
        )
        return [line.split("\t")[0] for line in result.stdout.splitlines() if line]

    def test_root_only_and_system_accounts_are_factory_valid(self):
        temporary, root = self.make_root("""
            root:x:0:0:root:/root:/bin/bash
            messagebus:x:990:990::/nonexistent:/usr/sbin/nologin
            echo:!:999:985:NeutronOS display:/home/echo:/usr/sbin/nologin
        """)
        with temporary:
            self.assertEqual(self.classify(root), [])

    def test_normal_interactive_user_fails_factory_contract(self):
        temporary, root = self.make_root("""
            root:x:0:0:root:/root:/bin/bash
            alice:x:1000:1000:Alice:/home/alice:/bin/bash
        """)
        with temporary:
            self.assertEqual(self.classify(root), ["alice"])
            failed = subprocess.run(
                [str(CLASSIFIER), "--root", str(root), "--assert-none"],
                text=True, capture_output=True,
            )
            self.assertNotEqual(failed.returncode, 0)

    def test_echo_named_development_user_is_semantically_human(self):
        temporary, root = self.make_root("""
            echo:x:1000:1000:Developer:/home/echo:/bin/bash
        """)
        with temporary:
            self.assertEqual(self.classify(root), ["neutronos"])

    def test_service_accounts_and_root_never_count_as_human(self):
        temporary, root = self.make_root("""
            root:x:0:0:root:/root:/bin/bash
            daemon:x:1:1::/usr/sbin:/usr/sbin/nologin
            service:x:1100:1100::/nonexistent:/usr/sbin/nologin
            sync:x:4:65534::/bin:/bin/sync
        """)
        with temporary:
            self.assertEqual(self.classify(root), [])


class Alpha1FinalReleaseContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text()
        cls.service = (ROOT / "systemd/neutronos.service").read_text()
        cls.main = (ROOT / "src/main.cpp").read_text()
        cls.user_manager = (ROOT / "src/UserManager.cpp").read_text()
        cls.wizard_manager = (ROOT / "src/SetupWizardManager.cpp").read_text()
        cls.security_manager = (ROOT / "src/SecurityManager.cpp").read_text()

    def test_factory_contract_uses_authoritative_human_policy_and_profile_state(self):
        self.assertIn("neutronos-human-accounts", self.builder)
        self.assertIn("--assert-none", self.builder)
        self.assertIn("factory_profile_entries", self.builder)
        self.assertIn("HumanAccountPolicy.h", self.user_manager)
        self.assertIn("HumanAccountPolicy.h", self.wizard_manager)
        self.assertIn("HumanAccountPolicy.h", self.security_manager)

    def test_zero_owner_remains_setup_wizard_destination(self):
        qml = (ROOT / "qml/Main.qml").read_text()
        self.assertIn("SetupWizard.qml", qml)
        self.assertIn("setupWizardManager.setupRequired", qml)

    def test_svg_runtime_package_and_real_decode_are_contracted(self):
        self.assertRegex(self.builder, r"\bqt6-svg-plugins\b")
        self.assertIn("libqsvg.so", self.builder)
        self.assertIn("--svg-smoke-test", self.builder)
        self.assertIn("QImageReader", self.main)
        atom = ROOT / "themes/Default/atom.svg"
        self.assertTrue(atom.is_file())
        self.assertTrue(atom.read_text().lstrip().startswith("<?xml"))

    def test_sanitizer_never_uses_system_wide_secret_name_deletion(self):
        self.assertIn("RELEASE_SECRET_SEARCH_ROOTS", self.builder)
        self.assertNotIn('find "$ROOT" -xdev -type f', self.builder)
        self.assertNotIn('find "$ROOT/usr"', self.builder)

    def test_production_and_smoke_shell_are_unprivileged(self):
        self.assertRegex(self.service, r"(?m)^User=neutronos$")
        self.assertRegex(self.service, r"(?m)^Group=neutronos$")
        self.assertIn("SupplementaryGroups=", self.service)
        self.assertNotRegex(self.service, r"(?m)^ExecStart=\+")
        self.assertIn("runuser -u echo", self.builder)
        self.assertIn("env -i", self.builder)
        self.assertIn("SECURITY WARNING", self.main)

    def test_privileged_setup_actions_remain_behind_narrow_helper(self):
        sudoers = (ROOT / "release/neutronos-privileged-helper.sudoers").read_text()
        self.assertEqual(
            sudoers.strip(),
            "neutronos ALL=(root) NOPASSWD: /usr/local/sbin/neutronos-privileged-helper",
        )
        self.assertIn("neutronos-privileged-helper.sudoers", self.builder)

    def test_smoke_precedes_final_factory_contract_and_nothing_mutates_after(self):
        smoke = self.builder.index("--smoke-test")
        final = self.builder.index("Final factory sterility contract")
        offline = self.builder.index("Unmounting and final offline checks")
        self.assertLess(smoke, final)
        self.assertLess(final, offline)


if __name__ == "__main__":
    unittest.main()
