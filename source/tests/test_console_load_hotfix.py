import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ConsoleLoadHotfixContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_authoritative_qt_parser_accepts_shell_dependency_entry_points(self):
        qmllint = shutil.which("qmllint") or "/usr/lib/qt6/bin/qmllint"
        if not pathlib.Path(qmllint).is_file():
            self.skipTest("Qt qmllint is not installed")
        result = subprocess.run(
            [qmllint, "-I", "qml", "-I", "qml/dashboard/v2",
             "qml/dashboard/v2/ModernDashboard.qml", "qml/Console.qml", "qml/Main.qml"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=45,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("Unexpected token", result.stdout)
        self.assertNotIn("Type ModernDashboard unavailable", result.stdout)

    def test_console_resolves_modern_dashboard_and_main_tracks_ready_state(self):
        console = self.read("qml/Console.qml")
        main = self.read("qml/Main.qml")
        self.assertIn("ModernDashboard {", console)
        self.assertIn('source: "Console.qml"', main)
        self.assertIn('console.log("Main.qml: Console.qml loaded")', main)
        self.assertIn('console.log("Main.qml: consoleLoader ready")', main)
        self.assertIn("root.consoleReady = true", main)

    def test_console_readiness_is_fail_closed_during_unlock(self):
        main = self.read("qml/Main.qml")
        self.assertIn("consoleLoader.status !== Loader.Ready", main)
        self.assertIn("refused to finish unlock because Console.qml is not ready", main)
        self.assertIn("remainAtLoginAfterConsoleFailure", main)
        self.assertNotIn("finishUnlockFailSafe(\"console unavailable\")", main)

    def test_console_loading_and_fracture_have_independent_watchdogs(self):
        main = self.read("qml/Main.qml")
        begin = main[main.index("function beginUnlockToConsole"):
                     main.index("function finishUnlockToConsole")]
        reveal = main[main.index("function startUnlockRevealWhenConsoleReady"):
                      main.index("function beginUnlockToConsole")]
        self.assertIn("id: consoleReadinessWatchdog", main)
        self.assertIn("interval: 30000", main)
        self.assertIn("consoleReadinessWatchdog.restart()", begin)
        self.assertIn("unlockTransitionWatchdog.stop()", begin)
        self.assertIn('root.logUnlock("CONSOLE_READY")', reveal)
        self.assertIn("consoleReadinessWatchdog.stop()", reveal)
        self.assertIn("unlockTransitionWatchdog.restart()", reveal)
        self.assertLess(reveal.index('root.logUnlock("CONSOLE_READY")'),
                        reveal.index("unlockFractureOverlay.start()"))

    def test_real_loader_error_fails_closed_immediately(self):
        main = self.read("qml/Main.qml")
        status_handler = main[main.index("onStatusChanged:"):
                              main.index("Connections {", main.index("onStatusChanged:"))]
        self.assertIn("status === Loader.Error", status_handler)
        self.assertIn("remainAtLoginAfterConsoleFailure", status_handler)

    def test_one_authentication_generates_one_fracture_topology(self):
        header = self.read("src/FractureEffect.h")
        source = self.read("src/FractureEffect.cpp")
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        constructor = source[source.index("FractureEffect::FractureEffect"):
                             source.index("void FractureEffect::setProgress")]
        self.assertNotIn("regenerate()", constructor)
        self.assertIn("bool m_geometryDirty = true", header)
        self.assertIn("if (value > 0 && m_geometryDirty)", source)
        self.assertIn("m_geometryDirty=true", source)
        self.assertEqual(overlay.count("fracture.seed ="), 1)
        self.assertEqual(overlay.count("FractureEffect {"), 1)
        self.assertEqual(overlay.count("fractureAnimation.restart()"), 2)

    def test_legacy_full_screen_ripple_cannot_start(self):
        login = self.read("qml/LoginScreen.qml")
        self.assertNotIn("successBurstAnimation.restart", login)
        self.assertIn("authenticationPulseAnimation.restart()", login)
        self.assertIn("onFinished: {}", login)

    def test_diagnostics_margin_uses_parent_surface_not_anchored_column(self):
        diagnostics = self.read("qml/modals/DiagnosticsCenter.qml")
        self.assertIn("Math.min(root.width, root.height) * .045", diagnostics)
        self.assertNotIn("Math.min(width,height)*.045", diagnostics.replace(" ", ""))


if __name__ == "__main__":
    unittest.main()
