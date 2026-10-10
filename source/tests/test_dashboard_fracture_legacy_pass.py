import json
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DashboardFractureLegacyPass(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_fracture_origin_is_mapped_from_current_user_card(self):
        login = self.read("qml/LoginScreen.qml")
        main = self.read("qml/Main.qml")
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        self.assertIn("userCard.mapToItem(login", login)
        self.assertIn("fractureOriginNormalized", main)
        self.assertIn("unlockFractureOverlay.originX", main)
        self.assertIn("originX: root.originX", overlay)
        self.assertIn("originY: root.originY", overlay)

    def test_fracture_has_no_single_starter_dash_and_uses_split_timing(self):
        source = self.read("src/FractureEffect.cpp")
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        self.assertIn("i == 0 ? .018", source)
        self.assertNotIn("branch*.006", source)
        self.assertIn("readonly property int crackDuration: 240", overlay)
        self.assertIn("readonly property int shardFallDuration: 2700", overlay)
        self.assertLess(240, 500)
        self.assertGreaterEqual(2700, 2 * 1330)
        self.assertIn("SequentialAnimation", overlay)

    def test_fracture_keeps_lock_texture_and_has_layered_glass_depth(self):
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        source = self.read("src/FractureEffect.cpp")
        self.assertIn("sourceItem: root.captureActive ? snapshot : null", overlay)
        self.assertIn("QSGTextureMaterial", source)
        self.assertIn("vertexDataAsTexturedPoint2D", source)
        for color in ("QColor(35,255,124", "QColor(0,218,235",
                      "QColor(151,239,255", "QColor(239,255,255",
                      "QColor(131,103,255"):
            self.assertIn(color, source)

    def test_full_default_inventory_and_exact_reference_packing(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        ids = ["cpu", "memory", "temperature", "storage", "media-storage",
               "user-clock", "network", "security", "uptime"]
        for widget_id in ids:
            self.assertIn(f'widgetEntry(QStringLiteral("{widget_id}")', source)
        self.assertIn('root.insert(QStringLiteral("schemaVersion"), 6)', source)
        self.assertIn("isSwappedSchemaFiveGeneratedLayout", source)
        for variant in ("small-square", "medium-wide", "large-wide", "large-tall"):
            self.assertIn(variant, source)
        self.assertIn("constexpr int DashboardColumns = 15", source)
        self.assertIn("constexpr int DashboardRows = 4", source)

    def test_geometry_scales_at_hd_and_uhd_and_large_area_is_reduced(self):
        for width, height, scale in ((1844, 710, 1.0), (3688, 1420, 1.8)):
            gap = max(14, width * .008)
            unit = max(120, (width - gap * 11) / 12)
            row = max(210, (height - gap * 2) / 3)
            small = unit * 2 + gap
            medium = unit * 4 + gap * 3
            large = unit * 5 + gap * 4
            self.assertLess(small, medium)
            self.assertLess(medium, large)
            self.assertLessEqual(large, width * .43)
            old_large_area = (width * .5) * ((height - gap) / 2)
            self.assertLess(large * row, old_large_area * .61)
            self.assertGreater(scale, 0)

    def test_schema_three_generated_default_has_targeted_migration(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        self.assertIn("isSixWidgetGeneratedDefault", source)
        self.assertIn("schema < 4 && isSixWidgetGeneratedDefault", source)
        self.assertIn("m_widgets = defaultWidgets()", source)

    def test_legacy_selector_is_routed_before_underlying_legacy_actions(self):
        console = self.read("qml/Console.qml")
        selector_route = console.index("modernDashboardView && modernDashboardView.selectorOpen")
        legacy_home = console.index('!consoleRoot.modernDashboard && action === "home"')
        notification = console.index('action === "up" && consoleRoot.selectedSection === 0', legacy_home)
        self.assertLess(selector_route, legacy_home)
        self.assertLess(selector_route, notification)
        self.assertIn("return modernDashboardView.handleControllerPressed(action)",
                      console[selector_route:legacy_home])
        self.assertIn("modernDashboardView.selectorOpen", console[console.index("function handleControllerReleased"):])

    def test_selector_modal_contract_and_legacy_order(self):
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        manager = self.read("src/DashboardLayoutManager.cpp")
        modal_branch = modern.index("if(selectorOpen){")
        home_branch = modern.index('if(action==="home")', modal_branch)
        self.assertLess(modal_branch, home_branch)
        for token in ('action==="up"', 'action==="down"',
                      'action==="primary"', 'action==="cancel"'):
            self.assertIn(token, modern[modal_branch:home_branch])
        positions = [manager.index(f'{{{{"id","{tab}"}}')
                     for tab in ("system", "security", "storage", "apps", "legacy")]
        self.assertEqual(positions, sorted(positions))

    def test_manager_custom_tabs_running_app_posters_and_home_shortcut(self):
        manager = self.read("qml/dashboard/v2/SystemOverviewManager.qml")
        tray = self.read("qml/dashboard/v2/RunningAppsTray.qml")
        apps = self.read("qml/dashboard/v2/AppsDashboardView.qml")
        modern = self.read("qml/dashboard/v2/ModernDashboard.qml")
        for token in ("Create Custom Tab", "Restore Default", "setWidgetEnabled",
                      "setWidgetSize"):
            self.assertIn(token.lower(), manager.lower())
        self.assertIn("ADD THIS RUNNING APPLICATION AS A DASHBOARD TAB?", tray)
        for token in ("posterSource", "posterPath", "usingIconFallback", "appNamePlate"):
            self.assertIn(token, apps)
        self.assertIn("circleHomePressCount", modern)
        self.assertIn("returnHomeTab()", modern)

    def test_help_is_backed_by_registry_and_documents_modal_legacy_flow(self):
        registry = self.read("qml/common/ControllerFeatureRegistry.js")
        help_modal = self.read("qml/modals/HelpModal.qml")
        help_data = json.loads(self.read("config/help-center.json"))
        combined = (registry + help_modal + json.dumps(help_data)).lower()
        for phrase in ("ps/home", "hold start", "circle x5", "make app a tab",
                       "legacy", "notification center", "poster artwork"):
            self.assertIn(phrase, combined)
        self.assertIn("underlying Dashboard, Legacy, and Notification actions are blocked", registry)


if __name__ == "__main__":
    unittest.main()
