import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ResponsiveSystemOverviewContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_named_default_uses_exact_modal_reference_composition(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        placements = (
            ("cpu", "CPU", "small-square", "0, 0, 0"),
            ("memory", "RAM", "small-square", "1, 2, 0"),
            ("storage", "Boot Storage", "medium-wide", "2, 4, 0"),
            ("media-storage", "Extra Storage", "medium-wide", "3, 8, 0"),
            ("uptime", "Uptime", "medium-wide", "4, 8, 0"),
            ("user-clock", "User / Clock", "large-wide", "5, 0, 2"),
            ("temperature", "Temperature", "fixed", "6, 6, 2"),
            ("network", "Network", "medium-wide", "7, 8, 2"),
            ("security", "Security Status", "large-tall", "8, 12, 0"),
        )
        for widget_id, title, variant, placement in placements:
            self.assertIn(
                f'widgetEntry(QStringLiteral("{widget_id}"), QStringLiteral("{title}"), '
                f'QStringLiteral("{variant}"), {placement}', source)

    def test_grid_is_responsive_and_never_uses_persisted_pixels(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        view = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertIn("constexpr int DashboardColumns = 15", source)
        self.assertIn("constexpr int DashboardRows = 4", source)
        self.assertIn("column + columnSpan > DashboardColumns", source)
        self.assertIn("row + rowSpan > DashboardRows", source)
        self.assertIn("packWidgets(normalized, true)", source)
        self.assertIn("packWidgets(normalized, false)", source)
        self.assertIn("cellWidth:(width-layoutGap*(gridColumns-1))/gridColumns", view)
        self.assertIn("cellHeight:(height-layoutGap*(gridRows-1))/gridRows", view)
        self.assertNotIn('"pixelX"', source)
        self.assertNotIn('"pixelY"', source)

    def test_two_stage_size_choice_and_disabled_variants(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        modal = self.read("qml/dashboard/v2/DashboardContextModal.qml")
        manager = self.read("qml/dashboard/v2/SystemOverviewManager.qml")
        for variant in (
            "small-square", "medium-square", "medium-wide", "medium-tall",
            "large-square", "large-wide", "large-tall",
        ):
            self.assertIn(variant, source)
        for surface in (modal, manager):
            self.assertIn("sizeStage===1", surface)
            self.assertIn("sizeStage===2", surface)
            self.assertIn("availableSizeVariants", surface)
            self.assertIn("available===false", surface)
        self.assertIn('widgetId == QStringLiteral("temperature")', source)
        self.assertIn('return QStringLiteral("fixed")', source)

    def test_extra_storage_fallback_shares_the_named_slot(self):
        source = self.read("src/DashboardLayoutManager.cpp")
        view = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertGreaterEqual(source.count('QStringLiteral("secondary-storage")'), 2)
        self.assertIn('id==="media-storage"&&!extraStorageAvailable', view)
        self.assertIn('id==="uptime"&&extraStorageAvailable', view)
        self.assertIn("storageBackend.devices", view)

    def test_security_attention_animates_the_whole_header_tile(self):
        header = self.read("qml/dashboard/v2/HeaderStatusItem.qml")
        shell = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn("property bool attention", header)
        self.assertIn('color: attention ? "#DD3A0710"', header)
        self.assertIn("SequentialAnimation on opacity", header)
        self.assertIn("running: root.attention", header)
        self.assertIn("onAttentionChanged: if (!attention) opacity = 1", header)
        self.assertIn("securityBackend", shell)
        self.assertIn("attention:root.securityAttention", shell)

    def test_content_is_clipped_inside_each_card(self):
        card = self.read("qml/dashboard/v2/DashboardCard.qml")
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        viewport = self.read("qml/dashboard/v2/SystemOverviewView.qml")
        self.assertIn("clip: true", card)
        self.assertIn("anchors.fill: root.contentItem", widget)
        self.assertIn("shapeVariant", widget)
        self.assertIn("wideShape", widget)
        self.assertIn("tallShape", widget)
        self.assertIn("clip:true", viewport)


if __name__ == "__main__":
    unittest.main()
