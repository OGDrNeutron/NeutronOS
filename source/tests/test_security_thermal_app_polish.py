import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class SecurityThermalAppPolishContracts(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_security_incidents_are_authoritative_and_size_aware(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        for token in ("collectUnresolvedIncidents", "event.acknowledged===true",
                      "notificationBackend.notifications", "currentIncident",
                      'root.widgetSize!=="large"', 'root.widgetSize==="large"&&incidentCount>0'):
            self.assertIn(token, widget)
        self.assertIn("visible:parent.incidentOnly", widget)
        self.assertIn("visible:!parent.incidentOnly", widget)

    def test_notification_dismissal_does_not_resolve_linked_security_event(self):
        header = self.read("src/NotificationManager.h")
        source = self.read("src/NotificationManager.cpp")
        main = self.read("src/main.cpp")
        self.assertNotIn("notificationDismissed(const QVariantMap &notification)", header)
        self.assertNotIn("emit notificationDismissed(dismissed)", source)
        self.assertNotIn("securityCoreManager.acknowledgeEvent(eventId)", main)

    def test_temperature_internal_flow_random_packets_and_status_only(self):
        gauge = self.read("qml/dashboard/v2/TemperatureGauge.qml")
        for token in ("NumberAnimation on phase", "drawPacket", "pulseStrand",
                      "Math.random()", "purplePulseTimer.interval", "pulseOpacity"):
            self.assertIn(token, gauge)
        self.assertNotIn('text: "MIN "', gauge)
        self.assertIn("text:root.statusLabel", gauge)
        self.assertNotIn("rotation:", gauge)

    def test_cpu_and_ram_process_rows_have_matching_usage_bars(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        for token in ("processFraction", "processBarColor", "modelData.memoryBytes",
                      "modelData.cpu", "width:parent.width*parent.parent.fraction"):
            self.assertIn(token, widget)

    def test_portrait_posters_are_not_stretched(self):
        apps = self.read("qml/dashboard/v2/AppsDashboardView.qml")
        self.assertIn("id:posterBackdrop", apps)
        self.assertIn("fillMode:Image.PreserveAspectFit", apps)
        self.assertIn("id: appNamePlate", apps)

    def test_installed_apps_feed_per_user_row_without_hardcoding_codex(self):
        manager = self.read("src/AppManager.cpp")
        header = self.read("src/AppManager.h")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        for token in ("loadManagedPackageIds", "m_managedPackageIds.contains(id)",
                      "setActiveUser", "moveFavorite"):
            self.assertIn(token, manager + header)
        self.assertIn("appsBackend.favoriteApps", dashboard)
        self.assertNotIn('id:"codex"', dashboard.lower())

    def test_app_move_has_visible_preview_commit_cancel(self):
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        dock = self.read("qml/dashboard/v2/DashboardDockIcon.qml")
        for token in ("previewAppList", "appMoveCandidateIndex", "finishAppMove(true)",
                      "finishAppMove(false)", "appsBackend.moveFavorite"):
            self.assertIn(token, dashboard)
        self.assertIn('text:"MOVE"', dock)

    def test_redundant_corner_heading_is_disabled_but_content_titles_remain(self):
        widget = self.read("qml/dashboard/v2/AdaptiveWidget.qml")
        card = self.read("qml/dashboard/v2/DashboardCard.qml")
        self.assertIn("showHeading:false", widget)
        self.assertIn("property bool showHeading", card)
        self.assertIn('label: memoryMetric?"RAM":"CPU"', widget)

    def test_semantic_lock_and_user_icons(self):
        icon = self.read("qml/dashboard/v2/SemanticStatusIcon.qml")
        dashboard = self.read("qml/dashboard/v2/ModernDashboard.qml")
        self.assertIn('kind === "unlocked"', icon)
        self.assertIn('property string kind: "locked"', icon)
        self.assertIn("deliberately lifted and offset", icon)
        self.assertIn('iconKind:"user"', dashboard)
        self.assertIn('iconKind:root.securityAttention?"unlocked":"locked"', dashboard)


if __name__ == "__main__":
    unittest.main()
