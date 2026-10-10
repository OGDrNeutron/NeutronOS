import hashlib
import grp
import os
import pathlib
import struct
import subprocess
import tempfile
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOT_ZIP = ROOT / "design-reference/Boot.zip"
EXPECTED_ZIP_HASH = "53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f"
PERCENTS = list(range(0, 101, 5))


class ApprovedVisualTests(unittest.TestCase):
    def test_boot_zip_is_exact_and_complete(self):
        self.assertEqual(hashlib.sha256(BOOT_ZIP.read_bytes()).hexdigest(),
                         EXPECTED_ZIP_HASH)
        with zipfile.ZipFile(BOOT_ZIP) as archive:
            names = set(archive.namelist())
            for percent in PERCENTS:
                entry = f"AbootNew_fixed/neutronos_progress_{percent:03d}.png"
                self.assertIn(entry, names)
                data = archive.read(entry)
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                width, height = struct.unpack(">II", data[16:24])
                self.assertEqual((width, height), (1920, 1080))

    def test_renderer_reads_the_approved_archive_directly(self):
        source = (ROOT / "src/BootVisualSource.cpp").read_text()
        self.assertIn("/opt/neutronos/design-reference/Boot.zip", source)
        self.assertIn(EXPECTED_ZIP_HASH, source)
        self.assertIn('QStringLiteral("-p")', source)
        self.assertIn("Qt::KeepAspectRatio", source)
        self.assertIn("Qt::SmoothTransformation", source)


class ProgressAndHandoffTests(unittest.TestCase):
    def test_compiled_progress_authority_rejects_99_and_backward_updates(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(
                [str(ROOT / "build/NeutronBootRenderer"),
                 "--state-self-test", temporary],
                text=True, capture_output=True,
                env={**os.environ,
                     "NEUTRONOS_BOOT_STATE_GROUP":
                         grp.getgrgid(os.getgid()).gr_name})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((pathlib.Path(temporary) / "progress").read_text(),
                             "10\n")

    def test_progress_is_monotonic_and_has_no_99_state(self):
        state = (ROOT / "src/BootProgressState.cpp").read_text()
        renderer = (ROOT / "src/boot_renderer_main.cpp").read_text()
        shell = (ROOT / "qml/ShellWindow.qml").read_text()
        self.assertIn("percent % 5 != 0", state)
        self.assertIn("percent > previous", state)
        self.assertNotIn("progress_099", renderer + shell)
        for percent in (65, 70, 75, 80, 85, 90, 95, 100):
            self.assertIn(f"({percent},", shell)
        self.assertIn("m_externalProgressTimer", (ROOT / "src/main.cpp").read_text())
        self.assertIn("--probe-milestones", renderer)

    def test_final_readiness_follows_visible_login_frame(self):
        shell = (ROOT / "qml/ShellWindow.qml").read_text()
        destination = (ROOT / "qml/Main.qml").read_text()
        main = (ROOT / "src/main.cpp").read_text()
        self.assertLess(shell.index("bootCoverVisible = false"),
                        shell.index("shellReadiness.markDestinationPresented()"))
        self.assertIn("onFrameSwapped", shell)
        self.assertIn("destinationInputReady", shell)
        self.assertIn("destinationFocusReady", destination)
        self.assertIn("activeFocusItem", destination)
        self.assertIn('QStringLiteral("/run/neutronos/login-ready")', main)
        self.assertIn('QStringLiteral("/run/neutronos/shell-frame-ready")', main)

    def test_cover_and_framebuffer_share_one_compositor(self):
        cmake = (ROOT / "CMakeLists.txt").read_text()
        provider = (ROOT / "src/BootImageProvider.cpp").read_text()
        renderer = (ROOT / "src/boot_renderer_main.cpp").read_text()
        self.assertIn("BootVisualSource.cpp", cmake)
        self.assertIn("composedProgressFrame", provider)
        self.assertIn("composedProgressFrame", renderer)
        self.assertIn("sourceSize:", (ROOT / "qml/ShellWindow.qml").read_text())


class ServiceSafetyTests(unittest.TestCase):
    def test_renderer_failure_does_not_block_shell_or_restart_loop(self):
        renderer_unit = (ROOT / "systemd/neutronos-boot-renderer.service").read_text()
        shell_unit = (ROOT / "systemd/neutronos.service").read_text()
        self.assertIn("Restart=no", renderer_unit)
        self.assertIn("Wants=neutronos-boot-renderer.service", shell_unit)
        self.assertNotIn("Requires=neutronos-boot-renderer.service", shell_unit)
        self.assertNotIn("plymouth", renderer_unit.lower() + shell_unit.lower())

    def test_tty1_stays_reserved_without_resetting_scanout(self):
        shell_unit = (ROOT / "systemd/neutronos.service").read_text()
        for contract in ("Conflicts=getty@tty1.service", "TTYPath=/dev/tty1",
                         "TTYReset=no", "TTYVHangup=no", "TTYVTDisallocate=no"):
            self.assertIn(contract, shell_unit)

    def test_obsolete_plymouth_production_sources_are_absent(self):
        for path in (
            "scripts/neutronos-plymouth-controller",
            "scripts/neutronos-boot-failure",
            "systemd/neutronos-plymouth.service",
            "systemd/neutronos-boot-failure.service",
            "boot/initramfs/init-premount-plymouth",
            "boot/plymouth/neutronos.script",
        ):
            self.assertFalse((ROOT / path).exists(), path)
        builder = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text()
        self.assertNotIn("plymouth-set-default-theme", builder)
        self.assertNotIn("plymouth.ignore-serial-consoles", builder)


class CmdlineSafetyTests(unittest.TestCase):
    def test_stager_changes_only_visual_console_tokens(self):
        original = (
            "console=serial0,115200 console=tty1 root=PARTUUID=deadbeef-02 "
            "rootfstype=ext4 fsck.repair=yes rootwait "
            "cfg80211.ieee80211_regdom=US usb-storage.quirks=0bc2:2035:u "
            "splash systemd.unit=multi-user.target systemd.show_status=1 "
            "loglevel=7 ignore_loglevel custom.hardware=keep"
        )
        with tempfile.TemporaryDirectory() as temporary:
            source = pathlib.Path(temporary) / "cmdline.txt"
            staged = pathlib.Path(temporary) / "staged.txt"
            source.write_text(original)
            result = subprocess.run(
                [str(ROOT / "scripts/neutronos-stage-cmdline"), str(source), str(staged)],
                text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            tokens = staged.read_text().split()
        for preserved in (
            "console=serial0,115200", "root=PARTUUID=deadbeef-02",
            "rootfstype=ext4", "fsck.repair=yes", "rootwait",
            "cfg80211.ieee80211_regdom=US", "usb-storage.quirks=0bc2:2035:u",
            "splash", "systemd.unit=multi-user.target", "custom.hardware=keep",
        ):
            self.assertIn(preserved, tokens)
        for removed in ("console=tty1", "plymouth.ignore-serial-consoles",
                        "systemd.show_status=1", "loglevel=7", "ignore_loglevel"):
            self.assertNotIn(removed, tokens)
        for added in ("systemd.show_status=false", "loglevel=3", "quiet",
                      "vt.global_cursor_default=0"):
            self.assertEqual(tokens.count(added), 1)


if __name__ == "__main__":
    unittest.main()
