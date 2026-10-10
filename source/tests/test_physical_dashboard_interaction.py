import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PhysicalDashboardInteractionContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_console_preload_is_not_cancelled_by_card_arming(self):
        main = self.read("qml/Main.qml")
        timer = main[main.index("id: consolePreloadTimer"):main.index("id: consoleReadinessWatchdog")]
        armed = main[main.index("function onCardArmedChanged"):main.index("function onConsoleWarmupRequested")]
        self.assertIn("interval: 16", timer)
        self.assertNotIn("cardArmed === true", timer)
        self.assertNotIn("consolePreloadTimer.stop()", armed)
        self.assertIn('logUnlock("CONSOLE_PRELOAD_REQUESTED")', main)
        self.assertIn("unlockStartedAtMs", main)
        self.assertIn("consoleLoader.status !== Loader.Ready", main)

    def test_command_target_tracks_actual_dashboard_zone(self):
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertIn('commandTarget: zone===0 ? "dashboard"', shell)
        self.assertIn('if(commandTarget==="dashboard")', shell)
        self.assertIn('if(commandTarget==="application")', shell)
        self.assertIn("onZoneChanged:syncControllerContext()", shell)
        self.assertIn("property bool controllerActive:true", overview)
        self.assertIn("selected:root.controllerActive&&root.selectedIndex===index", overview)

    def test_temperature_is_fixed_to_small_geometry_and_clipped(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        thermal = self.read("qml/dashboard/v2/TemperatureGauge.qml")
        layout = self.read("src/DashboardLayoutManager.cpp")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertIn('widgetVariant:String(modelData.variant||modelData.size||"small-square")', overview)
        self.assertIn('variant == QStringLiteral("fixed")', layout)
        self.assertIn('widgetId == QStringLiteral("temperature")', layout)
        self.assertIn('return QStringLiteral("fixed")', layout)
        self.assertGreaterEqual(thermal.count("clip: true"), 2)
        self.assertIn("Math.min(width, height) * .355", thermal)
        self.assertIn("pulsePhase", thermal)
        self.assertIn("motionDuration", thermal)

    def test_move_mode_reorders_before_normalization_and_supports_cancel(self):
        layout = self.read("src/DashboardLayoutManager.cpp")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        move = layout[layout.index("bool DashboardLayoutManager::moveWidgetInMemory"):
                      layout.index("bool DashboardLayoutManager::beginWidgetMove")]
        self.assertIn('entry[QStringLiteral("order")] = index;', move)
        self.assertIn('entry[QStringLiteral("gridColumn")] = -1;', move)
        self.assertIn("if (!normalizeAndReflow())", move)
        self.assertIn("layoutBackend.previewWidgetMove(delta)", overview)
        self.assertIn("finishMove(true)", overview)
        self.assertIn("finishMove(false)", overview)

    def test_user_uses_authoritative_profile_and_fallback_avatar(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        for token in ("resolvedAvatarSource", "avatarSource", "userDisplayName", "@"+"\"+root.userName()"):
            self.assertIn(token, widget)
        self.assertIn("currentTimeText", widget)
        self.assertIn("currentDateText", widget)
        self.assertIn("users/user_icon.png", widget)
        self.assertIn("Image.Error", widget)

    def test_network_uses_structured_conditional_field_model(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        self.assertIn("function networkFields()", widget)
        self.assertIn('label:"IP"', widget)
        self.assertIn('if(localModeEnabled()&&localServiceIp().length)', widget)
        self.assertIn('if(widgetSize!=="small")', widget)
        self.assertIn('if(widgetSize==="large")', widget)
        self.assertIn("Grid { id:networkGrid", widget)
        self.assertNotIn('text:"Interface: "+', widget)


if __name__ == "__main__":
    unittest.main()
