import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class LiveDevelopmentRecoveryContracts(unittest.TestCase):
    def test_development_shell_uses_proven_non_notify_service_contract(self):
        service = (ROOT / "systemd/neutronos.service").read_text()
        self.assertIn("Type=simple", service)
        self.assertNotIn("Type=notify", service)
        self.assertNotIn("NotifyAccess=", service)
        self.assertIn("TimeoutStartSec=0", service)
        self.assertIn("TimeoutStopSec=15", service)
        self.assertIn("User=neutronos", service)
        self.assertIn("Group=neutronos", service)
        self.assertIn("SupplementaryGroups=", service)
        for group in ("audio", "video", "render", "input", "tty",
                      "bluetooth", "neutronos-shell"):
            self.assertIn(group, service)

    def test_manual_shell_start_uses_fail_soft_renderer_ordering(self):
        service = (ROOT / "systemd/neutronos.service").read_text()
        self.assertIn("Wants=neutronos-boot-renderer.service", service)
        self.assertIn("After=neutronos-boot-renderer.service", service)
        self.assertNotIn("Requires=neutronos-boot-renderer.service", service)
        self.assertNotIn("plymouth", service.lower())

    def test_graphical_readiness_uses_a_privileged_systemd_path_boundary(self):
        service = (ROOT / "systemd/neutronos.service").read_text()
        watcher = (ROOT / "systemd/neutronos-shell-stability.path").read_text()
        main = (ROOT / "src/main.cpp").read_text()
        self.assertIn("neutronos-shell-stability.path", service)
        self.assertIn("PathChanged=/run/neutronos/login-ready", watcher)
        self.assertNotIn("MakeDirectory=yes", watcher)
        self.assertIn("Unit=neutronos-shell-stability.service", watcher)
        self.assertNotIn('QStringLiteral("/usr/bin/systemctl")', main)

    def test_shell_owns_tty1_without_exposing_a_healthy_boot_console(self):
        service = (ROOT / "systemd/neutronos.service").read_text()
        for contract in (
                "Before=getty@tty1.service", "Conflicts=getty@tty1.service",
                "StandardInput=tty", "TTYPath=/dev/tty1", "TTYReset=no",
                "TTYVHangup=no", "TTYVTDisallocate=no"):
            self.assertIn(contract, service)

    def test_matching_cover_takes_display_only_after_first_swap(self):
        main = (ROOT / "src/main.cpp").read_text()
        shell = (ROOT / "qml/ShellWindow.qml").read_text()
        self.assertIn("onFrameSwapped", shell)
        self.assertIn("markDisplayTaken()", shell)
        self.assertIn("BootImageProvider", main)
        self.assertLess(shell.index("markDisplayTaken()"),
                        shell.index("bootCoverVisible = false"))

    def test_stale_completed_handoff_cannot_replay_on_manual_start(self):
        main = (ROOT / "src/main.cpp").read_text()
        self.assertIn('hasMarker(QStringLiteral("active"))', main)
        self.assertIn('!m_bootState.hasMarker(QStringLiteral("completed"))', main)

    def test_development_payload_paths_exist(self):
        for path in (
                ROOT / "build/NeutronShell", ROOT / "qml/Main.qml",
                ROOT / "qml/ShellWindow.qml", ROOT / "themes/Default"):
            self.assertTrue(path.exists(), str(path))
        self.assertTrue((ROOT / "build/NeutronShell").stat().st_mode & 0o111)

    def test_release_boot_helper_has_no_live_root_override(self):
        helper = (ROOT / "scripts/neutronos-configure-boot-root").read_text()
        self.assertIn('[[ "$ROOT_ARG" != / ]]', helper)
        self.assertIn('[[ "$BOOT" != /boot && "$BOOT" != /boot/firmware ]]', helper)
        self.assertIn('mountpoint -q "$ROOT"', helper)
        self.assertIn('"$ROOT_SOURCE" == /dev/loop*p2', helper)
        self.assertIn('"$BOOT_SOURCE" == /dev/loop*p1', helper)
        self.assertNotIn("--force", helper)

    def test_terminal_manager_preserves_private_state_root(self):
        source = (ROOT / "src/TerminalManager.cpp").read_text()
        self.assertRegex(
            source,
            re.compile(r"secureBase\(\s*stateRoot,\s*"
                       r"static_cast<mode_t>\(0700\)\)"))
        self.assertNotRegex(
            source,
            re.compile(r"secureBase\(\s*stateRoot,\s*"
                       r"static_cast<mode_t>\(0755\)\)"))


if __name__ == "__main__":
    unittest.main()
