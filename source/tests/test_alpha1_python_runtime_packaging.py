import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Alpha1PythonRuntimePackagingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text(
            encoding="utf-8"
        )

    def test_debian_python_runtime_is_explicit_and_repaired_by_apt(self):
        for package in (
            "python3",
            "python3.13",
            "python3.13-minimal",
            "libpython3.13-minimal",
            "libpython3.13-stdlib",
        ):
            self.assertRegex(self.builder, rf"\b{re.escape(package)}\b")
        self.assertIn("--reinstall", self.builder)
        self.assertIn(
            "python3.13-minimal libpython3.13-minimal libpython3.13-stdlib",
            self.builder,
        )
        self.assertNotIn("python3-full", self.builder)
        self.assertNotRegex(self.builder, r"\bcp\b[^\n]*tokenize\.py")

    def test_secret_sanitization_cannot_delete_package_runtime_files(self):
        self.assertIn("RELEASE_SECRET_SEARCH_ROOTS", self.builder)
        self.assertNotRegex(
            self.builder,
            r'find\s+"\$ROOT"\s+-type f\s+\\\n\s*\\\(.*\*token\*',
        )
        for mutable_root in (
            '"$ROOT/root"',
            '"$ROOT/etc/neutronos"',
            '"$ROOT/var/lib/neutronos"',
        ):
            self.assertIn(mutable_root, self.builder)
        sanitizer = self.builder.split("RELEASE_SECRET_SEARCH_ROOTS=(", 1)[1].split(")", 1)[0]
        self.assertNotIn('"$ROOT/home"', sanitizer)
        self.assertNotIn('"$ROOT/opt/neutronos"', sanitizer)

    def test_post_sanitization_python_contract_is_complete(self):
        validation = self.builder.index(
            'log "Verifying release boot and factory contracts before unmount"'
        )
        sanitization = self.builder.index("RELEASE_SECRET_SEARCH_ROOTS")
        self.assertLess(sanitization, validation)
        for contract in (
            '[[ -x "$ROOT/usr/bin/python3" ]]',
            'PYTHON_RELEASE_VERSION',
            '[[ "$PYTHON_RELEASE_VERSION" == "3.13" ]]',
            'libpython3.13-stdlib',
            '/usr/lib/python3.13/tokenize.py',
            'dpkg-query -S /usr/lib/python3.13/tokenize.py',
            'dpkg --verify',
            'python3 python3.13 python3.13-minimal libpython3.13-minimal libpython3.13-stdlib',
            'import dataclasses, inspect, tokenize',
            'import neutronos_ipc, neutronos_ipc.authorization',
        ):
            self.assertIn(contract, self.builder[validation:])

    def test_service_entrypoints_are_compiled_and_imported(self):
        for entrypoint in (
            "/usr/local/lib/neutronos/neutron-securityd.py",
            "/usr/local/lib/neutronos/neutron-security-watchdog.py",
            "/usr/local/libexec/neutronos-offline-networkd.py",
        ):
            self.assertIn(entrypoint, self.builder)
        self.assertIn("runpy.run_path(path)", self.builder)
        self.assertIn("systemd-analyze --root=\"$ROOT\" verify", self.builder)

    def test_focused_service_stdlib_modules_are_smoke_tested(self):
        smoke = (
            "os", "sys", "json", "socket", "struct", "pathlib", "dataclasses",
            "inspect", "tokenize", "threading", "subprocess", "selectors",
            "logging", "hashlib", "hmac", "secrets", "time", "datetime",
            "typing", "enum", "re", "collections", "contextlib", "signal",
        )
        for module in smoke:
            self.assertRegex(
                self.builder,
                rf"import [^\n]*\b{re.escape(module)}\b",
                module,
            )


if __name__ == "__main__":
    unittest.main()
