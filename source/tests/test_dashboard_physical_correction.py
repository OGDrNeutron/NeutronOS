import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DashboardPhysicalCorrectionContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_size_geometry_is_span_based_and_bounded(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertIn('gridColumns||15', overview)
        self.assertIn('gridRows||4', overview)
        self.assertIn('cellWidth:(width-layoutGap*(gridColumns-1))/gridColumns', overview)
        self.assertIn('cellHeight:(height-layoutGap*(gridRows-1))/gridRows', overview)
        self.assertIn('Number(modelData.columnSpan||2)*root.cellWidth', overview)
        self.assertIn('Number(modelData.rowSpan||2)*root.cellHeight', overview)
        self.assertIn('anchors.fill: root.contentItem', widget)

    def test_size_path_reflows_persists_and_preserves_focus(self):
        manager = self.read("src/DashboardLayoutManager.cpp")
        modal = self.read("qml/dashboard/v2/DashboardContextModal.qml")
        overview = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        for token in ("setWidgetSize", "normalizeAndReflow", "save()", "emit layoutChanged"):
            self.assertIn(token, manager)
        self.assertIn("setTabWidgetSize", modal)
        self.assertIn("selectedIndex", overview)

    def test_full_default_and_broken_layout_migration(self):
        manager = self.read("src/DashboardLayoutManager.cpp")
        for widget_id in ("cpu", "memory", "temperature", "storage", "media-storage", "user-clock", "network", "security", "uptime"):
            self.assertIn(f'QStringLiteral("{widget_id}")', manager)
        self.assertIn("isBrokenGeneratedLayout", manager)
        self.assertIn("enabled == 2 && cpu && memory", manager)

    def test_system_overview_manager_and_hold_start(self):
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        manager = self.read("qml/dashboard/v2/SystemOverviewManager.qml")
        registry = self.read("qml/common/ControllerFeatureRegistry.js")
        self.assertIn("systemHoldTimer.restart()", shell)
        self.assertIn("overviewManager.openManager()", shell)
        self.assertIn("dashboardManagerHoldMs", registry)
        for action in ("Enable", "Disable", "Move Earlier", "Move Later", "Size", "Reset Widget", "Restore Default Placement"):
            self.assertIn(action, manager)
        for variant in ("small", "medium", "large"):
            self.assertIn(variant, manager.lower())
        self.assertIn("availableSizeVariants", manager)
        self.assertIn("modelData.label", manager)

    def test_custom_tab_crud_layout_and_persistence(self):
        header = self.read("src/DashboardLayoutManager.h")
        source = self.read("src/DashboardLayoutManager.cpp")
        view = self.read("qml/dashboard/v2/CustomDashboardView.qml")
        for method in ("createCustomTab", "renameCustomTab", "deleteCustomTab", "setTabWidgetEnabled", "setTabWidgetSize", "moveTabWidget"):
            self.assertIn(method, header + source)
        self.assertIn('root.insert(QStringLiteral("customTabs")', source)
        self.assertIn("SystemOverviewView.qml", view)

    def test_running_app_tab_reuses_runtime(self):
        tray = self.read("qml/dashboard/v2/RunningAppsTray.qml")
        view = self.read("qml/dashboard/v2/CustomDashboardView.qml")
        source = self.read("src/DashboardLayoutManager.cpp")
        self.assertIn("Make App a Tab", tray)
        self.assertIn("ADD THIS RUNNING APPLICATION AS A DASHBOARD TAB?", tray)
        self.assertIn("focusRuntime", view)
        self.assertIn('value("appId").toString()==appId', source)

    def test_home_toggle_legacy_order_and_circle_five(self):
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        source = self.read("src/DashboardLayoutManager.cpp")
        registry = self.read("qml/common/ControllerFeatureRegistry.js")
        self.assertIn('if(selectorOpen){if(action==="home"||action==="cancel")closeSelector()', shell)
        self.assertIn("circleHomePressCount", shell)
        self.assertIn("circleHomePressCount = 5", registry)
        self.assertIn("returnHomeTab()", shell)
        order = [source.index(f'{{"id","{tab}"}}') for tab in ("system", "security", "storage", "apps")]
        self.assertEqual(order, sorted(order))
        self.assertIn('{"id","legacy"}', source)

    def test_home_tab_setting_and_fallback(self):
        settings = self.read("qml/apps/settings/Main.qml")
        source = self.read("src/DashboardLayoutManager.cpp")
        self.assertIn('"dashboard.homeTab", "Home Dashboard Tab"', settings)
        self.assertIn("setHomeTab", settings)
        self.assertIn('m_homeTab=QStringLiteral("system")', source.replace(" ", ""))

    def test_focus_treatment_is_explicit_not_color_only(self):
        card = self.read("qml/dashboard/v2/DashboardCard.qml")
        for token in ("scale:", "border.width", "glow", "corner"):
            self.assertIn(token.lower(), card.lower())
        self.assertIn("selected", card)

    def test_details_use_authoritative_premium_monitor_surfaces(self):
        cpu = self.read("qml/modals/system/CpuMonitorModal.qml")
        memory = self.read("qml/modals/system/MemoryMonitorModal.qml")
        monitor = self.read("qml/modals/system/ProcessMonitorModal.qml")
        for token in ("PID", "CPU", "MEMORY", "STATE", "RUNTIME", "perCore"):
            self.assertIn(token.lower(), monitor.lower())
        self.assertIn("ProcessMonitorModal", cpu)
        self.assertIn("ProcessMonitorModal", memory)

    def test_app_row_posters_and_nameplate(self):
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        apps = self.read("qml/dashboard/v2/AppsDashboardView.qml")
        self.assertIn("spacing:0", shell)
        self.assertIn("anchors.bottomMargin:-8*root.uiScale", shell)
        self.assertIn("height:108*root.uiScale", shell)
        for token in ("posterSource", "posterPath", "poster", "icon", "appNamePlate"):
            self.assertIn(token.lower(), apps.lower())
        self.assertIn("PreserveAspectCrop", apps)

    def test_fracture_waits_for_texture_and_only_renders_textured_shards(self):
        overlay = self.read("qml/UnlockFractureOverlay.qml")
        renderer = self.read("src/FractureEffect.cpp")
        header = self.read("src/FractureEffect.h")
        self.assertIn("fracture.textureReady", overlay)
        self.assertLess(overlay.index("captureCommitted()"), overlay.index("fractureAnimation.restart()"))
        self.assertIn("QSGTextureMaterial", renderer)
        self.assertNotIn("QSGFlatColorMaterial;material->setColor(QColor(8,20,34", renderer)
        self.assertIn("vertexDataAsTexturedPoint2D", renderer)
        self.assertIn("Q_PROPERTY(bool textureReady", header)
        self.assertIn("constexpr int rows = 7, columns = 7", renderer)
        for color in ("QColor(0,38,31", "QColor(35,255,124", "QColor(0,218,235", "QColor(151,239,255", "QColor(239,255,255", "QColor(131,103,255"):
            self.assertIn(color, renderer)

    def test_help_uses_shared_controller_registry(self):
        help_modal = self.read("qml/modals/HelpModal.qml")
        registry = self.read("qml/common/ControllerFeatureRegistry.js")
        local_help = self.read("config/help-center.json")
        self.assertIn("ControllerFeatureRegistry.js", help_modal)
        for mapping in ("PS / HOME", "HOLD START", "CIRCLE x5", "TRIANGLE", "SQUARE"):
            self.assertIn(mapping, registry)
        for feature in ("System Overview Manager", "Make App a Tab", "Legacy", "GLOBAL SEARCH", "NOTIFICATION CENTER"):
            self.assertIn(feature.lower(), (help_modal + local_help).lower())


if __name__ == "__main__":
    unittest.main()
