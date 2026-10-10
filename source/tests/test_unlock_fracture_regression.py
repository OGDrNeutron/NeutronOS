import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class UnlockFractureRegressionContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_login_success_has_one_pulse_and_no_legacy_ripple_controller(self):
        login = self.read("qml/LoginScreen.qml")
        for forbidden in ("successBurstAnimation.restart", "unlockVisualReadyTimer",
                          "unlockHandoffTimer", "unlockFallbackTimer", "unlockVisualFinished"):
            self.assertNotIn(forbidden, login)
        self.assertIn("id: successBurstAnimation", login)
        self.assertIn("onFinished: {}", login)
        self.assertIn("signal unlockPulseFinished()", login)
        self.assertIn("authenticationPulseAnimation.restart()", login)
        self.assertIn("finishUnlock()", login)

    def test_main_owns_explicit_single_forward_state_machine(self):
        main = self.read("qml/Main.qml")
        self.assertIn('property string unlockState: "LOCKED"', main)
        for state in ("AUTH_SUCCESS", "CAPTURING", "CRACKING", "FRACTURING", "HANDOFF", "COMPLETE"):
            self.assertIn(state, main)
        for forbidden in ("revealRipple", "revealLayer", "unlockRevealAnimation", "unlockVisualComplete"):
            self.assertNotIn(forbidden, main)
        self.assertIn("onUnlockPulseFinished", main)
        self.assertIn('root.logUnlock("AUTH_SUCCESS")', main)

    def test_capture_and_fracture_have_bounded_success_and_fallback_paths(self):
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        for token in ("CAPTURE_REQUESTED", "CAPTURE_READY", "FRACTURE_STARTED",
                      "FRACTURE_COMPLETE", "CAPTURE_INVALID", "ANIMATION_TICK/STATE"):
            self.assertIn(token, overlay)
        self.assertIn("captureTimeout", overlay)
        self.assertIn("startFallback", overlay)
        self.assertIn("fallbackRenderer=true", overlay.replace(" ", ""))
        self.assertIn("transitionFailed", overlay)
        self.assertIn("captureActive=false", overlay.replace(" ", ""))

    def test_native_renderer_exposes_geometry_and_animated_fallback(self):
        header = self.read("src/FractureEffect.h")
        source = self.read("src/FractureEffect.cpp")
        self.assertIn("Q_PROPERTY(int shardCount", header)
        self.assertIn("WRITE setFallbackRenderer", header)
        self.assertIn("constexpr int rows = 7, columns = 7", source)
        self.assertIn("vertexDataAsTexturedPoint2D", source)
        self.assertIn("QSGFlatColorMaterial", source)
        self.assertIn("QPointF(0,1.38*t*t)", source)
        self.assertIn("shard.spin*t*t", source)

    def test_failure_cannot_dead_end_and_focus_only_follows_handoff(self):
        main = self.read("qml/Main.qml")
        self.assertIn("unlockTransitionWatchdog", main)
        self.assertIn("finishUnlockFailSafe", main)
        self.assertIn("onTransitionFailed", main)
        self.assertIn('root.logUnlock("LOGIN_HIDDEN")', main)
        self.assertIn('root.logUnlock("DASHBOARD_FOCUSED")', main)
        self.assertIn('root.logUnlock("HANDOFF_COMPLETE")', main)
        self.assertLess(main.index('root.logUnlock("LOGIN_HIDDEN")'),
                        main.index('root.logUnlock("DASHBOARD_FOCUSED")'))

    def test_duplicate_authentication_is_ignored(self):
        login = self.read("qml/LoginScreen.qml")
        main = self.read("qml/Main.qml")
        self.assertIn("if (loginSuccess)", login)
        self.assertIn('if (root.shellMode !== "lock")', main)
        self.assertIn("duplicate authentication ignored", main)


if __name__ == "__main__":
    unittest.main()
