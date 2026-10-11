import QtQuick
import "../../components/SecurityIndicator.js" as SecurityIndicator

Item {
    id: root

    property var backend: null
    property var networkBackend: null
    property var notificationBackend: null
    property var settingsBackend: null
    property int selectedIndex: 0
    property int focusZone: 0       // 0 = top scan, 1 = alerts View All, 2 = activity View All, 3 = quick actions, 4 = Active Protections
    property real animatedScore: securityScore()

    // Internal controller-driven action/review surfaces. ModernDashboard checks
    // controllerModalOpen and forwards all controller input here while one is open.
    property bool actionModalOpen: false
    property int actionModalIndex: -1
    property int actionModalSelection: 0
    property bool reviewModalOpen: false
    property int reviewTab: 0            // 0 = notifications, 1 = integrity, 2 = activity
    property int reviewIndex: 0
    property bool reviewBaselineArmed: false
    property bool protectionModalOpen: false
    property int protectionModalSelection: 0
    property bool protectionErrorOpen: false
    property string protectionErrorTitle: ""
    property string protectionErrorMessage: ""
    property string operationMessage: ""
    property bool operationSuccess: true
    readonly property bool controllerModalOpen: actionModalOpen || reviewModalOpen || protectionModalOpen || protectionErrorOpen

    // Public-IP-derived local position used by the live threat map. The last
    // successful state-level fix is cached so the green local marker remains
    // stable instead of wandering when an ISP rotates addresses. A new fix only
    // replaces it when the resolved region changes materially.
    property real userLatitude: NaN
    property real userLongitude: NaN
    property real userLocationAccuracy: -1
    property string userLocationSource: "Securing Local Location"
    property string userLocationRegion: ""
    property string userLocationCity: ""
    property bool locationRequestRunning: false
    property real mapPhase: 0.0
    property real trendPhase: 0.0
    property double scanUiNowMs: Date.now()
    property var scoreHistory: []
    property var blockedHistory: []
    property var suspiciousHistory: []
    property var scanHistory: []
    property int historyLimit: 28

    // Security Trends is an authoritative rolling 72-hour window. It uses
    // timestamped Security Core events/rejected activity/audit records only.
    // No synthetic history is generated for this panel.
    property int trendWindowHours: 72
    property int trendBucketHours: 3
    property int trendBucketCount: 24
    property var threat72History: []
    property var blocked72History: []
    property var audit72History: []
    property var scan72History: []
    property int threat72Total: 0
    property int blocked72Total: 0
    property int audit72Total: 0
    property int scan72Total: 0

    readonly property real uiScale: Math.max(0.86, Math.min(1.20, Math.min(width / 1580, height / 820)))
    readonly property real textBoost: 1.13
    readonly property real gap: 12 * uiScale
    readonly property color panel: "#E8071425"
    readonly property color panelRaised: "#F20A1829"
    readonly property color panelInset: "#D9081322"
    readonly property color border: "#2A4563"
    readonly property color borderSoft: "#1B314A"
    readonly property color textPrimary: "#F4F8FF"
    readonly property color textSecondary: "#B6C5D8"
    readonly property color textMuted: "#7F93AA"
    readonly property color blue: "#58A7FF"
    readonly property color cyan: "#51DFFF"
    readonly property color purple: "#B453FF"
    readonly property color green: "#72F05B"
    readonly property color yellow: "#FFD84A"
    readonly property color orange: "#FF9B2F"
    readonly property color red: "#FF3F4E"

    signal detailsRequested(string kind, var context)
    signal actionsRequested(string kind, var context)

    Behavior on animatedScore {
        NumberAnimation { duration: 720; easing.type: Easing.OutCubic }
    }

    onBackendChanged: {
        animatedScore = securityScore()
        primeHistory()
        rebuild72HourTrends()
    }

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    function securityStats() {
        return backend && backend.stats ? backend.stats : ({})
    }

    function securityScore() { return SecurityIndicator.score(backend) }
    function securityScoreAvailable() { return securityScore() >= 0 }

    function events() {
        return backend && backend.events ? backend.events : []
    }

    function unresolvedEvents() {
        var source = events()
        var out = []
        for (var i = 0; i < source.length; ++i) {
            var e = source[i] || ({})
            if (e.acknowledged !== true)
                out.push(e)
        }
        return out
    }

    function activeThreatCount() {
        var stats = securityStats()
        if (stats.activeThreats !== undefined)
            return Number(stats.activeThreats || 0)
        return unresolvedEvents().length
    }

    function malwareFindingCount() {
        var stats = securityStats()
        if (stats.malwareFindings !== undefined)
            return Number(stats.malwareFindings || 0)
        return backend && backend.malwareFindings ? backend.malwareFindings.length : 0
    }

    function quarantinedCount() {
        var stats = securityStats()
        if (stats.quarantinedItems !== undefined)
            return Number(stats.quarantinedItems || 0)
        return backend && backend.quarantinedItems ? backend.quarantinedItems.length : 0
    }

    function integrityChangeCount() {
        var stats = securityStats()
        if (stats.integrityChanges !== undefined)
            return Number(stats.integrityChanges || 0)
        return backend && backend.integrityChanges ? backend.integrityChanges.length : 0
    }

    function blockedCount() {
        var stats = securityStats()
        if (stats.blockedConnections !== undefined)
            return Number(stats.blockedConnections || 0)
        if (stats.rejectedActivity !== undefined)
            return Number(stats.rejectedActivity || 0)
        return backend && backend.rejectedActivity ? backend.rejectedActivity.length : 0
    }

    function listeningPortCount() {
        var stats = securityStats()
        if (stats.listeningPorts !== undefined)
            return Number(stats.listeningPorts || 0)
        return backend && backend.listeningPorts ? backend.listeningPorts.length : 0
    }

    function bannedSourceCount() {
        var stats = securityStats()
        if (stats.bannedSources !== undefined)
            return Number(stats.bannedSources || 0)
        return backend && backend.bannedSources ? backend.bannedSources.length : 0
    }

    function scanRunning() {
        return Boolean(securityStats().scanRunning === true)
    }

    function wifiProtectionOn() {
        if (!networkBackend)
            return false

        // A disabled Wi-Fi radio has no active wireless link to expose.
        if (networkBackend.wifiEnabled === false)
            return true

        var ssid = String(
            networkBackend.connectedSsid ||
            networkBackend.currentSsid ||
            networkBackend.ssid ||
            ""
        )

        if (!ssid.length)
            return true

        var security = String(
            networkBackend.currentSecurity ||
            networkBackend.securityType ||
            networkBackend.wifiSecurity ||
            ""
        ).toLowerCase()

        return security.length > 0 &&
               security.indexOf("open") < 0 &&
               security.indexOf("none") < 0
    }

    function activeProtectionRows() {
        var online = backend && backend.daemonOnline === true
        var integrityAvailable = backend &&
                                 String(backend.integrityStatus || "")
                                 .toUpperCase()
                                 .indexOf("UNAVAILABLE") < 0
        var peripheralTelemetry = backend &&
                                  backend.peripherals !== undefined
        var tailscaleActive = backend &&
                              backend.tailscaleStatus &&
                              backend.tailscaleStatus.active === true
        var recoveryActive = backend &&
                             backend.recoveryConfigured === true

        return [
            {key:"core",       name:"Core Monitoring",      on:online,                                      group:"SYSTEM",   control:"core"},
            {key:"malware",    name:"Malware Defense",      on:online,                                      group:"MALWARE",  control:"core"},
            {key:"ransomware", name:"Ransomware Shield",    on:online && backend.responseEngineEnabled && backend.enforcementEnabled, group:"FILES", control:"ransomware"},
            {key:"response",   name:"Automatic Response",   on:online && backend.responseEngineEnabled,      group:"RESPONSE", control:"response"},
            {key:"policy",     name:"Policy Enforcement",   on:online && backend.enforcementEnabled,         group:"POLICY",   control:"enforcement"},
            {key:"wifi",       name:"Wi-Fi Link Security",  on:wifiProtectionOn(),                          group:"WIFI",     control:"link"},
            {key:"firewall",   name:"Firewall Monitoring",  on:online,                                      group:"NETWORK",  control:"core"},
            {key:"blocked",    name:"Blocked Source Guard", on:online && backend.enforcementEnabled,         group:"NETWORK",  control:"enforcement"},
            {key:"integrity",  name:"Integrity Protection", on:online && integrityAvailable,                 group:"FILES",    control:"core"},
            {key:"audit",      name:"Audit Chain",          on:online && backend.auditValid,                 group:"AUDIT",    control:"core"},
            {key:"peripheral", name:"Peripheral Monitor",   on:online && peripheralTelemetry,                group:"DEVICE",   control:"core"},
            {key:"intel",      name:"Threat Intelligence",  on:online,                                      group:"INTEL",    control:"core"},
            {key:"tailscale",  name:"Tailscale Privacy",    on:online && tailscaleActive,                    group:"PRIVACY",  control:"tailscale"},
            {key:"recovery",   name:"Recovery Protection",  on:online && recoveryActive,                     group:"RECOVERY", control:"recovery"}
        ]
    }

    function protectionEnabledCount() {
        var rows = activeProtectionRows()
        var count = 0
        for (var i = 0; i < rows.length; ++i)
            if (rows[i].on === true) ++count
        return count
    }

    function protectionTotalCount() {
        return activeProtectionRows().length
    }

    function protectionPercent() {
        var total = protectionTotalCount()
        return total > 0
                ? clamp((protectionEnabledCount() / total) * 100, 0, 100)
                : 0
    }

    function protectionControlText(row) {
        if (!row) return ""
        if (row.control === "core") return "CORE MANAGED"
        if (row.control === "link") return "LINK MANAGED"
        if (row.control === "recovery") return row.on ? "CONFIGURED" : "SETUP REQUIRED"
        return row.on ? "ENABLED" : "DISABLED"
    }

    function showProtectionError(title, message) {
        protectionErrorTitle = String(title || "PROTECTION CONTROL")
        protectionErrorMessage = String(message || "This protection cannot be changed from the dashboard.")
        protectionErrorOpen = true
    }

    function toggleProtectionAt(index) {
        var rows = activeProtectionRows()
        if (index < 0 || index >= rows.length)
            return

        var row = rows[index]
        if (!backend) {
            showProtectionError("SECURITY CORE OFFLINE", "Security Core must be online before protection settings can be changed.")
            return
        }

        if (row.control === "response") {
            if (typeof backend.setResponseEngineEnabled === "function")
                backend.setResponseEngineEnabled(row.on !== true)
            return
        }

        if (row.control === "enforcement") {
            if (typeof backend.setEnforcementEnabled === "function")
                backend.setEnforcementEnabled(row.on !== true)
            return
        }

        if (row.control === "ransomware") {
            if (row.on === true) {
                if (typeof backend.setResponseEngineEnabled === "function")
                    backend.setResponseEngineEnabled(false)
            } else {
                if (typeof backend.setEnforcementEnabled === "function")
                    backend.setEnforcementEnabled(true)
                if (typeof backend.setResponseEngineEnabled === "function")
                    backend.setResponseEngineEnabled(true)
            }
            return
        }

        if (row.control === "tailscale") {
            if (typeof backend.setTailscaleEnabled === "function")
                backend.setTailscaleEnabled(row.on !== true)
            return
        }

        if (row.control === "recovery") {
            if (backend.recoveryConfigured !== true) {
                showProtectionError(
                    "RECOVERY NOT CONFIGURED",
                    "Recovery Protection cannot be enabled until a recovery method is configured first. Open Security > Recovery and enroll a recovery code or USB recovery device."
                )
            } else {
                showProtectionError(
                    "RECOVERY IS ENROLLED",
                    "Recovery enrollment is persistent protection. Change or remove recovery configuration from Security > Recovery rather than disabling it from the dashboard."
                )
            }
            return
        }

        if (row.control === "link") {
            showProtectionError(
                "WI-FI SECURITY IS LINK MANAGED",
                "Wi-Fi Link Security reflects the encryption of the currently connected network. Connect to a secured Wi-Fi network to change this protection state."
            )
            return
        }

        showProtectionError(
            "CORE-MANAGED PROTECTION",
            row.name + " is enforced directly by Security Core and is not independently disabled from the dashboard."
        )
    }

    function scanProgressPercent() {
        var st = securityStats()
        var directKeys = [
            "scanProgressPercent",
            "scanPercent",
            "scanProgress",
            "progressPercent"
        ]

        for (var i = 0; i < directKeys.length; ++i) {
            var raw = Number(st[directKeys[i]])
            if (!isNaN(raw)) {
                if (raw >= 0 && raw <= 1.0)
                    raw *= 100.0
                if (raw >= 0 && raw <= 100)
                    return clamp(raw, 0, 100)
            }
        }

        var pairs = [
            ["scanFilesScanned", "scanFilesTotal"],
            ["scanCurrentIndex", "scanTotalFiles"],
            ["scanProcessed", "scanTotal"],
            ["scanProcessedFiles", "scanTotalFiles"],
            ["scanCompletedFiles", "scanTotalFiles"],
            ["scanFilesProcessed", "scanFilesTotal"],
            ["scanCurrent", "scanCount"],
            ["filesScanned", "filesTotal"],
            ["filesProcessed", "totalFiles"],
            ["scanned", "total"]
        ]

        for (var p = 0; p < pairs.length; ++p) {
            var done = Number(st[pairs[p][0]])
            var total = Number(st[pairs[p][1]])
            if (!isNaN(done) && !isNaN(total) && total > 0)
                return clamp((done / total) * 100, 0, 100)
        }

        var status = String(st.scanStatus || "")
        var percentMatch = /([0-9]{1,3}(?:\.[0-9]+)?)\s*%/.exec(status)
        if (percentMatch)
            return clamp(Number(percentMatch[1]), 0, 100)

        var ratioMatch = /([0-9]+)\s*(?:\/|of)\s*([0-9]+)/i.exec(status)
        if (ratioMatch && Number(ratioMatch[2]) > 0)
            return clamp(
                (Number(ratioMatch[1]) / Number(ratioMatch[2])) * 100,
                0,
                100
            )

        return -1
    }

    function scanProgressKnown() {
        return scanProgressPercent() >= 0
    }

    function scanProgressLabel() {
        var value = scanProgressPercent()
        return value >= 0 ? String(Math.round(value)) + "%" : "--%"
    }

    function modalAccent(index) {
        if (index === 0) return green
        if (index === 4) return purple
        return red
    }

    function secureState() {
        return backend && backend.daemonOnline === true &&
               backend.auditValid === true &&
               integrityChangeCount() === 0 &&
               malwareFindingCount() === 0 &&
               activeThreatCount() === 0 &&
               Number(backend.threatLevel || 5) >= 4
    }

    function threatWord() {
        var level = Number(backend ? backend.threatLevel : 0)
        if (!backend || backend.daemonOnline !== true) return "OFFLINE"
        if (level >= 4) return "LOW"
        if (level === 3) return "ELEVATED"
        if (level === 2) return "HIGH"
        return "CRITICAL"
    }

    function threatColor() {
        var level = Number(backend ? backend.threatLevel : 0)
        if (!backend || backend.daemonOnline !== true) return textMuted
        if (level >= 4) return green
        if (level === 3) return orange
        return red
    }

    function scoreLabel() {
        var score = securityScore()
        if (score >= 95) return "EXCELLENT"
        if (score >= 85) return "STRONG"
        if (score >= 70) return "GOOD"
        if (score >= 50) return "ATTENTION"
        return "CRITICAL"
    }

    function securityStrength() { return SecurityIndicator.label(backend) }

    function scoreColor() {
        // NEUTRONOS_SECURITY_SCORE_COLOR_THRESHOLDS_V2
        var score = securityScore()
        if (score >= 80) return green
        if (score >= 55) return yellow
        return red
    }

    function moduleScoreColor(value) {
        var score = clamp(Number(value || 0), 0, 100)
        if (score >= 80) return green
        if (score <= 50) return red
        return yellow
    }

    function moduleScoreLabel(value) {
        var score = clamp(Number(value || 0), 0, 100)
        if (score >= 80) return "ACTIVE"
        if (score <= 50) return "CRITICAL"
        return "ATTENTION"
    }

    function threatFaceStep() {
        if (!backend || backend.daemonOnline !== true) return 9
        var level = clamp(Number(backend.threatLevel || 5), 1, 5)
        var base = ((5 - level) / 4) * 8.0
        var eventBoost = Math.min(1.0, Math.max(0, activeThreatCount()))
        return Math.max(0, Math.min(9, Math.round(base + eventBoost)))
    }

    function threatFaceColor() {
        var palette = [
            "#72F05B", "#8EF05A", "#B5EA50", "#D8E544", "#F4DA3F",
            "#FFC33D", "#FF9B2F", "#FF7437", "#FF5543", "#FF3F4E"
        ]
        return palette[threatFaceStep()]
    }

    function eventIconGlyph(event) {
        var e = event || ({})
        var text = (String(e.category || "") + " " + eventTitle(e)).toLowerCase()
        if (text.indexOf("malware") >= 0 || text.indexOf("trojan") >= 0 || text.indexOf("virus") >= 0) return "✹"
        if (text.indexOf("firewall") >= 0 || text.indexOf("network") >= 0 || text.indexOf("port") >= 0) return "⌁"
        if (text.indexOf("login") >= 0 || text.indexOf("auth") >= 0 || text.indexOf("ssh") >= 0) return "◎"
        if (text.indexOf("integrity") >= 0 || text.indexOf("change") >= 0 || text.indexOf("file") >= 0) return "◇"
        return "◆"
    }

    function activityIconGlyph(row) {
        var r = row || ({})
        var text = (String(r.title || "") + " " + String(r.detail || "")).toLowerCase()
        if (text.indexOf("scan") >= 0) return "⌕"
        if (text.indexOf("firewall") >= 0 || text.indexOf("network") >= 0) return "⌁"
        if (text.indexOf("integrity") >= 0 || text.indexOf("baseline") >= 0) return "◇"
        if (text.indexOf("update") >= 0 || text.indexOf("definition") >= 0) return "↻"
        return r.ok ? "✓" : "!"
    }

    function severityNumber(event) {
        var value = event ? (event.severity !== undefined ? event.severity : event.level) : 0
        var number = Number(value)
        if (!isNaN(number)) return number
        var text = String(value || "").toLowerCase()
        if (text.indexOf("critical") >= 0 || text.indexOf("severe") >= 0) return 5
        if (text.indexOf("high") >= 0) return 4
        if (text.indexOf("medium") >= 0 || text.indexOf("warning") >= 0) return 3
        if (text.indexOf("low") >= 0) return 2
        return 1
    }

    function severityColor(event) {
        var severity = severityNumber(event)
        if (severity >= 4) return red
        if (severity >= 3) return orange
        if (severity >= 2) return blue
        return green
    }

    function severityLabel(event) {
        var severity = severityNumber(event)
        if (severity >= 5) return "Critical"
        if (severity === 4) return "High"
        if (severity === 3) return "Medium"
        if (severity === 2) return "Low"
        return "Info"
    }

    function eventTitle(event) {
        var e = event || ({})
        var title = String(e.title || e.eventType || e.type || "").trim()
        if (title.length) return title
        var category = String(e.category || "").toLowerCase()
        if (category.indexOf("malware") >= 0) return "Malware Event"
        if (category.indexOf("firewall") >= 0 || category.indexOf("network") >= 0) return "Firewall Activity"
        if (category.indexOf("integrity") >= 0) return "Integrity Change"
        if (category.indexOf("auth") >= 0 || category.indexOf("login") >= 0) return "Authentication Event"
        return "Security Event"
    }

    function eventDetail(event) {
        var e = event || ({})
        var detail = String(e.description || e.message || e.reason || e.evidence || "").trim()
        return detail.length ? detail : "Review authoritative event details"
    }

    function shortWhen(value) {
        if (!value) return "now"
        var d = new Date(value)
        if (isNaN(d.getTime())) return String(value)
        var seconds = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000))
        if (seconds < 60) return seconds + "s ago"
        var minutes = Math.floor(seconds / 60)
        if (minutes < 60) return minutes + "m ago"
        var hours = Math.floor(minutes / 60)
        if (hours < 24) return hours + "h ago"
        return Math.floor(hours / 24) + "d ago"
    }

    function alertModel() {
        var source = unresolvedEvents()
        source.sort(function(a, b) {
            var severityDiff = severityNumber(b) - severityNumber(a)
            if (severityDiff !== 0) return severityDiff
            return String(b.timestamp || b.time || "").localeCompare(String(a.timestamp || a.time || ""))
        })
        return source.slice(0, 4)
    }

    function activityModel() {
        var source = backend && backend.auditEntries ? backend.auditEntries : []
        if (!source.length) source = events()
        var out = []
        for (var i = 0; i < Math.min(5, source.length); ++i) {
            var item = source[i] || ({})
            out.push({
                title: String(item.title || item.action || item.eventType || item.type || "Security activity"),
                detail: String(item.detail || item.description || item.message || item.evidence || "Authoritative security record"),
                time: item.timestamp || item.time || "",
                ok: severityNumber(item) < 4
            })
        }
        return out
    }

    function allActivityModel() {
        var source = backend && backend.auditEntries ? backend.auditEntries : []
        if (!source.length) source = events()
        var out = []
        for (var i = 0; i < source.length; ++i) {
            var item = source[i] || ({})
            out.push({
                title: String(item.title || item.action || item.eventType || item.type || "Security activity"),
                detail: String(item.detail || item.description || item.message || item.evidence || "Authoritative security record"),
                time: item.timestamp || item.time || "",
                ok: severityNumber(item) < 4,
                source: item
            })
        }
        return out
    }

    function appendHistory(list, value) {
        var next = list.slice(Math.max(0, list.length - historyLimit + 1))
        next.push(Number(value || 0))
        return next
    }

    function primeHistory() {
        if (scoreHistory.length) return
        var score = securityScore()
        var blocked = blockedCount()
        var suspicious = activeThreatCount()
        var scans = scanRunning() ? 1 : 0
        var a = [], b = [], c = [], d = []
        for (var i = 0; i < historyLimit; ++i) {
            a.push(score)
            b.push(blocked)
            c.push(suspicious)
            d.push(scans)
        }
        scoreHistory = a
        blockedHistory = b
        suspiciousHistory = c
        scanHistory = d
    }

    function sampleHistory() {
        animatedScore = securityScore()
        scoreHistory = appendHistory(scoreHistory, securityScore())
        blockedHistory = appendHistory(blockedHistory, blockedCount())
        suspiciousHistory = appendHistory(suspiciousHistory, activeThreatCount())
        scanHistory = appendHistory(scanHistory, scanRunning() ? 1 : 0)
    }

    function recordTimestampMs(record) {
        var row = record || ({})
        var keys = [
            "timestamp", "time", "createdAt", "created_at",
            "occurredAt", "occurred_at", "date"
        ]

        for (var i = 0; i < keys.length; ++i) {
            var raw = row[keys[i]]
            if (raw === undefined || raw === null || raw === "")
                continue

            if (typeof raw === "number") {
                var numeric = Number(raw)
                if (!isNaN(numeric)) {
                    // Accept either Unix seconds or Unix milliseconds.
                    if (numeric > 0 && numeric < 100000000000)
                        numeric *= 1000
                    return numeric
                }
            }

            var parsed = new Date(String(raw)).getTime()
            if (!isNaN(parsed))
                return parsed
        }

        return NaN
    }

    function recordSearchText(record) {
        var row = record || ({})
        return (
            String(row.title || "") + " " +
            String(row.action || "") + " " +
            String(row.eventType || "") + " " +
            String(row.type || "") + " " +
            String(row.category || "") + " " +
            String(row.description || "") + " " +
            String(row.message || "") + " " +
            String(row.reason || "") + " " +
            String(row.detail || "")
        ).toLowerCase()
    }

    function isBlockedTrendRecord(record) {
        var text = recordSearchText(record)
        return text.indexOf("block") >= 0 ||
               text.indexOf("reject") >= 0 ||
               text.indexOf("denied") >= 0 ||
               text.indexOf("deny") >= 0 ||
               text.indexOf("drop") >= 0 ||
               text.indexOf("banned") >= 0
    }

    function isScanTrendRecord(record) {
        return recordSearchText(record).indexOf("scan") >= 0
    }

    function build72HourSeries(source, predicate) {
        var buckets = []
        for (var i = 0; i < trendBucketCount; ++i)
            buckets.push(0)

        var rows = source || []
        var now = Date.now()
        var hourMs = 60 * 60 * 1000
        var windowStart = now - trendWindowHours * hourMs
        var bucketMs = trendBucketHours * hourMs

        for (var j = 0; j < rows.length; ++j) {
            var row = rows[j] || ({})
            if (predicate && predicate(row) !== true)
                continue

            var timestamp = recordTimestampMs(row)
            if (isNaN(timestamp))
                continue

            // A small future tolerance handles clock-skewed daemon records.
            if (timestamp < windowStart || timestamp > now + 5 * 60 * 1000)
                continue

            var bucket = Math.floor((timestamp - windowStart) / bucketMs)
            bucket = Math.max(0, Math.min(trendBucketCount - 1, bucket))
            buckets[bucket] += 1
        }

        return buckets
    }

    function seriesTotal(series) {
        var total = 0
        var values = series || []
        for (var i = 0; i < values.length; ++i)
            total += Number(values[i] || 0)
        return total
    }

    function rebuild72HourTrends() {
        var eventRows = events()
        var rejectedRows = backend && backend.rejectedActivity
                         ? backend.rejectedActivity : []
        var auditRows = backend && backend.auditEntries
                      ? backend.auditEntries : []

        var threats = build72HourSeries(
            eventRows,
            function(row) { return severityNumber(row) >= 2 }
        )

        // Rejected activity is already authoritative blocked activity. If that
        // list is unavailable, fall back to blocked/rejected event semantics.
        var blocked = rejectedRows.length
                    ? build72HourSeries(rejectedRows, null)
                    : build72HourSeries(eventRows, isBlockedTrendRecord)

        var audits = build72HourSeries(auditRows, null)

        // Security scan history normally lives in the audit chain. Fall back to
        // timestamped event records only if the audit feed is empty.
        var scanSource = auditRows.length ? auditRows : eventRows
        var scans = build72HourSeries(scanSource, isScanTrendRecord)

        threat72History = threats
        blocked72History = blocked
        audit72History = audits
        scan72History = scans

        threat72Total = seriesTotal(threats)
        blocked72Total = seriesTotal(blocked)
        audit72Total = seriesTotal(audits)
        scan72Total = seriesTotal(scans)
    }

    function graphPoint(values, index, widthValue, heightValue, pad) {
        if (!values || !values.length) return ({x: pad, y: heightValue / 2})
        var minValue = values[0]
        var maxValue = values[0]
        for (var i = 1; i < values.length; ++i) {
            minValue = Math.min(minValue, Number(values[i]))
            maxValue = Math.max(maxValue, Number(values[i]))
        }
        if (maxValue - minValue < 0.001) {
            minValue -= 1
            maxValue += 1
        }
        var x = pad + (widthValue - pad * 2) * (index / Math.max(1, values.length - 1))
        var normalized = (Number(values[index]) - minValue) / (maxValue - minValue)
        var y = heightValue - pad - normalized * (heightValue - pad * 2)
        return ({x:x, y:y})
    }

    function drawSpark(canvas, values, color, fillAlpha) {
        var ctx = canvas.getContext("2d")
        ctx.reset()
        if (!values || values.length < 2) return
        var pad = 4 * uiScale
        var first = graphPoint(values, 0, canvas.width, canvas.height, pad)

        ctx.beginPath()
        ctx.moveTo(first.x, first.y)
        for (var i = 1; i < values.length; ++i) {
            var point = graphPoint(values, i, canvas.width, canvas.height, pad)
            ctx.lineTo(point.x, point.y)
        }
        ctx.lineWidth = 1.8 * uiScale
        ctx.strokeStyle = color
        ctx.stroke()

        if (fillAlpha > 0) {
            var last = graphPoint(values, values.length - 1, canvas.width, canvas.height, pad)
            ctx.lineTo(last.x, canvas.height - pad)
            ctx.lineTo(first.x, canvas.height - pad)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, fillAlpha)
            ctx.fill()
        }
    }


    function trendSeriesFlat(values) {
        if (!values || values.length < 2) return true
        var first = Number(values[0] || 0)
        for (var i = 1; i < values.length; ++i)
            if (Math.abs(Number(values[i] || 0) - first) > 0.0001)
                return false
        return true
    }

    function drawTrendSpark(canvas, values, color, fillAlpha) {
        drawSpark(canvas, values, color, fillAlpha)

        if (!values || values.length < 2 || !trendSeriesFlat(values))
            return

        var ctx = canvas.getContext("2d")
        var pad = 4 * uiScale
        var linePoint = graphPoint(
            values,
            0,
            canvas.width,
            canvas.height,
            pad
        )
        var x = pad +
                ((canvas.width - pad * 2) * trendPhase)

        // Keep the real data flat. The animated bead/glow is presentation only,
        // so a quiet 72-hour period still looks alive without inventing events.
        var glow = 5.5 * uiScale
        var gradient = ctx.createRadialGradient(
            x, linePoint.y, 0,
            x, linePoint.y, glow
        )
        gradient.addColorStop(
            0,
            Qt.rgba(color.r, color.g, color.b, 0.72)
        )
        gradient.addColorStop(
            1,
            Qt.rgba(color.r, color.g, color.b, 0.0)
        )

        ctx.beginPath()
        ctx.arc(x, linePoint.y, glow, 0, Math.PI * 2)
        ctx.fillStyle = gradient
        ctx.fill()

        ctx.beginPath()
        ctx.arc(
            x,
            linePoint.y,
            1.9 * uiScale,
            0,
            Math.PI * 2
        )
        ctx.fillStyle = color
        ctx.fill()
    }


    function normalizeAction(action) {
        var a = String(action || "").toLowerCase()
        if (a === "x" || a === "accept") return "primary"
        if (a === "o" || a === "circle" || a === "back") return "cancel"
        if (a === "triangle") return "context"
        if (a === "square") return "secondary"
        return a
    }

    function quickActionRows() {
        var level = Math.max(1, Math.min(5, Number(backend ? backend.threatLevel : 5)))
        return [
            {key:"scan",       title:scanRunning()?"SECURITY SCAN RUNNING":"RUN SECURITY SCAN", detail:scanRunning()?"Authoritative malware scan is active • SQUARE stops scan":"Scan NeutronOS protected paths for malware and suspicious files", tone:cyan},
            {key:"refresh",    title:"REFRESH SECURITY CORE", detail:"Request a fresh authoritative security snapshot", tone:blue},
            {key:"firewall",   title:"FIREWALL & NETWORK", detail:(backend&&backend.enforcementEnabled?"Enforcement active":"Monitoring mode")+" • "+String(listeningPortCount())+" ports • "+String(bannedSourceCount())+" banned", tone:cyan},
            {key:"lock",       title:level<=1?"MAXIMUM SECURITY":"INCREASE SECURITY", detail:level<=1?"System is already at DEFCON 1":"Move from DEFCON "+level+" to DEFCON "+Math.max(1,level-1), tone:red},
            {key:"quarantine", title:"VIEW QUARANTINE", detail:String(quarantinedCount())+" quarantined item"+(quarantinedCount()===1?"":"s")+" awaiting review", tone:red},
            {key:"report",     title:"LOGS & REPORT", detail:String(unresolvedEvents().length)+" notifications • "+String(integrityChangeCount())+" integrity changes", tone:purple}
        ]
    }

    function drawQuickActionIcon(ctx, key, tone, w, h) {
        ctx.reset()
        ctx.lineWidth = Math.max(1.4, 1.65 * uiScale)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = tone
        ctx.fillStyle = "transparent"

        var cx = w / 2
        var cy = h / 2
        var r = Math.min(w, h) * 0.29

        if (key === "scan") {
            ctx.beginPath()
            ctx.moveTo(cx, cy - r * 1.12)
            ctx.lineTo(cx + r * 0.92, cy - r * 0.70)
            ctx.lineTo(cx + r * 0.78, cy + r * 0.36)
            ctx.quadraticCurveTo(cx, cy + r * 1.18, cx, cy + r * 1.18)
            ctx.quadraticCurveTo(cx, cy + r * 1.18, cx - r * 0.78, cy + r * 0.36)
            ctx.lineTo(cx - r * 0.92, cy - r * 0.70)
            ctx.closePath()
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(cx - r * 0.36, cy + r * 0.02)
            ctx.lineTo(cx - r * 0.08, cy + r * 0.30)
            ctx.lineTo(cx + r * 0.48, cy - r * 0.34)
            ctx.stroke()
            return
        }

        if (key === "refresh") {
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.82, -0.55, Math.PI * 1.38)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(cx + r * 0.58, cy - r * 0.67)
            ctx.lineTo(cx + r * 0.92, cy - r * 0.62)
            ctx.lineTo(cx + r * 0.78, cy - r * 0.28)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.82, Math.PI - 0.55, Math.PI * 2.38)
            ctx.stroke()
            return
        }

        if (key === "firewall") {
            var bw = r * 1.62
            var bh = r * 1.26
            var x = cx - bw / 2
            var y = cy - bh / 2
            ctx.strokeRect(x, y, bw, bh)
            ctx.beginPath()
            ctx.moveTo(x, y + bh * 0.34); ctx.lineTo(x + bw, y + bh * 0.34)
            ctx.moveTo(x, y + bh * 0.68); ctx.lineTo(x + bw, y + bh * 0.68)
            ctx.moveTo(x + bw * 0.34, y); ctx.lineTo(x + bw * 0.34, y + bh * 0.34)
            ctx.moveTo(x + bw * 0.68, y + bh * 0.34); ctx.lineTo(x + bw * 0.68, y + bh * 0.68)
            ctx.moveTo(x + bw * 0.34, y + bh * 0.68); ctx.lineTo(x + bw * 0.34, y + bh)
            ctx.stroke()
            return
        }

        if (key === "lock") {
            ctx.beginPath()
            ctx.arc(cx, cy - r * 0.36, r * 0.50, Math.PI, 0)
            ctx.stroke()
            ctx.beginPath()
            ctx.rect(cx - r * 0.72, cy - r * 0.10, r * 1.44, r * 1.02)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx, cy + r * 0.30, r * 0.10, 0, Math.PI * 2)
            ctx.fillStyle = tone
            ctx.fill()
            return
        }

        if (key === "quarantine") {
            ctx.beginPath()
            ctx.arc(cx, cy, r * 0.95, 0, Math.PI * 2)
            ctx.fillStyle = red
            ctx.fill()
            ctx.strokeStyle = "#FFB8BF"
            ctx.stroke()
            ctx.strokeStyle = "#FFFFFF"
            ctx.lineWidth = Math.max(2.1, 2.5 * uiScale)
            ctx.beginPath()
            ctx.moveTo(cx - r * 0.48, cy)
            ctx.lineTo(cx + r * 0.48, cy)
            ctx.moveTo(cx, cy - r * 0.48)
            ctx.lineTo(cx, cy + r * 0.48)
            ctx.stroke()
            return
        }

        // report
        ctx.beginPath()
        ctx.rect(cx - r * 0.66, cy - r * 0.92, r * 1.32, r * 1.84)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx - r * 0.34, cy - r * 0.38); ctx.lineTo(cx + r * 0.36, cy - r * 0.38)
        ctx.moveTo(cx - r * 0.34, cy); ctx.lineTo(cx + r * 0.36, cy)
        ctx.moveTo(cx - r * 0.34, cy + r * 0.38); ctx.lineTo(cx + r * 0.18, cy + r * 0.38)
        ctx.stroke()
    }

    function quickActionTitle(index) {
        var rows = quickActionRows()
        return index >= 0 && index < rows.length ? rows[index].title : "SECURITY ACTION"
    }

    function quickActionDetail(index) {
        var rows = quickActionRows()
        return index >= 0 && index < rows.length ? rows[index].detail : ""
    }

    function openQuickAction(index) {
        selectedIndex = Math.max(0, Math.min(5, index))
        if (selectedIndex === 5) {
            reviewModalOpen = true
            reviewTab = 0
            reviewIndex = 0
            reviewBaselineArmed = false
            return
        }
        actionModalIndex = selectedIndex
        actionModalSelection = 0
        actionModalOpen = true
    }

    function closeActionModal() {
        actionModalOpen = false
        actionModalIndex = -1
        actionModalSelection = 0
    }

    function executeActionModal() {
        if (!backend || actionModalIndex < 0) {
            closeActionModal()
            return
        }
        var idx = actionModalIndex
        if (idx === 0) {
            if (!scanRunning() && typeof backend.scanNeutronOS === "function") {
                backend.scanNeutronOS()
                operationMessage = "Security scan started"
            } else {
                operationMessage = "A security scan is already running"
            }
        } else if (idx === 1) {
            if (typeof backend.requestSnapshot === "function") backend.requestSnapshot()
            else if (typeof backend.refresh === "function") backend.refresh()
            operationMessage = "Security Core refresh requested"
        } else if (idx === 2) {
            if (typeof backend.setEnforcementEnabled === "function")
                backend.setEnforcementEnabled(backend.enforcementEnabled !== true)
            operationMessage = backend.enforcementEnabled === true ? "Disabling enforcement" : "Enabling enforcement"
        } else if (idx === 3) {
            var current = Math.max(1, Math.min(5, Number(backend.threatLevel || 5)))
            var target = Math.max(1, current - 1)
            if (target < current && typeof backend.setManualThreatLevel === "function") {
                backend.setManualThreatLevel(target)
                operationMessage = "Increasing security to DEFCON " + target
            } else {
                operationMessage = "System is already at DEFCON 1"
            }
        }
        closeActionModal()
    }

    function actionModalMetrics(index) {
        if (index === 0) return [
            {l:"MALWARE",v:String(malwareFindingCount()),c:malwareFindingCount()?red:green},
            {l:"INTEGRITY",v:String(integrityChangeCount()),c:integrityChangeCount()?orange:green},
            {l:"EVENTS",v:String(unresolvedEvents().length),c:unresolvedEvents().length?yellow:green}
        ]
        if (index === 1) return [
            {l:"SCORE",v:String(securityScore())+" / 100",c:scoreColor()},
            {l:"AUDIT",v:backend&&backend.auditValid?"VERIFIED":"ATTENTION",c:backend&&backend.auditValid?green:red},
            {l:"CORE",v:backend&&backend.daemonOnline?"ONLINE":"OFFLINE",c:backend&&backend.daemonOnline?green:red}
        ]
        if (index === 2) return [
            {l:"ENFORCEMENT",v:backend&&backend.enforcementEnabled?"ACTIVE":"MONITOR",c:backend&&backend.enforcementEnabled?green:yellow},
            {l:"LISTENING PORTS",v:String(listeningPortCount()),c:blue},
            {l:"BANNED SOURCES",v:String(bannedSourceCount()),c:bannedSourceCount()?orange:green}
        ]
        if (index === 3) {
            var current=Math.max(1,Math.min(5,Number(backend?backend.threatLevel:5)))
            return [
                {l:"CURRENT",v:"DEFCON "+current,c:threatColor()},
                {l:"NEXT",v:"DEFCON "+Math.max(1,current-1),c:orange},
                {l:"RECOVERY",v:backend&&backend.recoveryConfigured?"READY":"NOT ENROLLED",c:backend&&backend.recoveryConfigured?green:yellow}
            ]
        }
        return []
    }

    function quarantineRows() {
        var out = []
        var items = backend && backend.quarantinedItems ? backend.quarantinedItems : []
        var apps = backend && backend.quarantinedApps ? backend.quarantinedApps : []
        for (var i=0; i<items.length; ++i) out.push(items[i])
        for (var j=0; j<apps.length; ++j) out.push(apps[j])
        return out
    }

    function securityNotificationCount() {
        var count = 0
        var notes = notificationBackend && notificationBackend.notifications ? notificationBackend.notifications : []
        for (var i=0; i<notes.length; ++i) if (String((notes[i]||({})).category||"").toLowerCase()==="security" && (notes[i]||({})).read!==true) ++count
        return Math.max(count, unresolvedEvents().length)
    }

    function reviewRows() {
        var out = []
        if (reviewTab === 0) {
            var represented = ({})
            var notes = notificationBackend && notificationBackend.notifications ? notificationBackend.notifications : []
            for (var n=0; n<notes.length; ++n) {
                var note = notes[n] || ({})
                if (String(note.category || "").toLowerCase() !== "security") continue
                var payload = note.payload || ({})
                var linkedId = String(payload.id || payload.eventId || "")
                if (linkedId.length) represented[linkedId] = true
                out.push({kind:"notification", payload:note, securityPayload:payload})
            }
            var ev = backend && backend.events ? backend.events : []
            for (var i=0; i<ev.length; ++i) {
                var e = ev[i] || ({})
                var eventId = String(e.id || e.eventId || "")
                if (e.acknowledged === true || (eventId.length && represented[eventId])) continue
                out.push({kind:"event", payload:e})
            }
        } else if (reviewTab === 1) {
            var changes = backend && backend.integrityChanges ? backend.integrityChanges : []
            for (var j=0; j<changes.length; ++j)
                out.push({kind:"integrity", payload:changes[j] || ({})})
        } else {
            var activity = allActivityModel()
            for (var k=0; k<activity.length; ++k)
                out.push({kind:"activity", payload:activity[k] || ({})})
        }
        return out
    }

    function reviewPayload(row) {
        if (!row) return ({})
        if (row.kind === "notification") {
            var payload = row.securityPayload || ({})
            var linkedId = String(payload.id || payload.eventId || "")
            if (linkedId.length) {
                var ev = backend && backend.events ? backend.events : []
                for (var i=0; i<ev.length; ++i) {
                    var candidate = ev[i] || ({})
                    if (String(candidate.id || candidate.eventId || "") === linkedId) return candidate
                }
            }
            return payload
        }
        return row.payload || ({})
    }

    function integrityKey(change) {
        var c = change || ({})
        return String(c.id || c.eventId || c.path || c.file || c.target || c.name || c.component || "")
    }

    function reviewTitle(row) {
        if (row && row.kind === "notification") return String((row.payload||({})).title || "Security notification")
        var item = reviewPayload(row)
        if (row && row.kind === "integrity")
            return String(item.path || item.file || item.target || item.name || "Protected filesystem change")
        if (row && row.kind === "activity")
            return String(item.title || "Security activity")
        return eventTitle(item)
    }

    function reviewDetail(row) {
        if (row && row.kind === "notification") return String((row.payload||({})).message || "Security notification")
        var item = reviewPayload(row)
        if (row && row.kind === "integrity") {
            var state = String(item.status || item.changeType || item.type || "Changed")
            var detail = String(item.detail || item.description || item.reason || item.hash || item.currentHash || "")
            return state + (detail.length ? " • " + detail : "")
        }
        if (row && row.kind === "activity")
            return String(item.detail || "Authoritative security record")
        return eventDetail(item)
    }

    function reviewFlagged(row) {
        if (row && row.kind === "activity") return false
        var item = reviewPayload(row)
        return item.flagged === true
    }

    function toggleReviewFlag() {
        var rows = reviewRows()
        if (!rows.length) return
        reviewIndex = Math.max(0, Math.min(reviewIndex, rows.length - 1))
        var row = rows[reviewIndex]
        if (row.kind === "activity") return
        var item = reviewPayload(row)
        var flagged = !reviewFlagged(row)
        if (row.kind === "event" || row.kind === "notification") {
            var id = String(item.id || item.eventId || "")
            if (id.length && backend && typeof backend.setEventFlagged === "function")
                backend.setEventFlagged(id, flagged)
        } else {
            var key = integrityKey(item)
            if (key.length && backend && typeof backend.setIntegrityChangeFlagged === "function")
                backend.setIntegrityChangeFlagged(key, flagged)
        }
    }

    function approveReviewRow() {
        var rows = reviewRows()
        if (!rows.length || !backend) return
        reviewIndex = Math.max(0, Math.min(reviewIndex, rows.length - 1))
        var row = rows[reviewIndex]
        var item = reviewPayload(row)
        if (row.kind === "activity") {
            detailsRequested("security", {incident:(item.source || item), section:"activity"})
            return
        }
        if (row.kind === "event" || row.kind === "notification") {
            var id = String(item.id || item.eventId || "")
            if (id.length && typeof backend.acknowledgeEvent === "function")
                backend.acknowledgeEvent(id)
            if (row.kind === "notification" && notificationBackend && typeof notificationBackend.markRead === "function") {
                var noteId = String((row.payload||({})).id || "")
                if (noteId.length) notificationBackend.markRead(noteId, true)
            }
            reviewIndex = Math.max(0, reviewIndex - 1)
            return
        }
        // securityd exposes baseline replacement as the authoritative approval
        // operation. It intentionally applies to the current integrity set as a
        // whole rather than silently hiding one path in presentation code.
        if (!reviewBaselineArmed) {
            reviewBaselineArmed = true
            reviewArmTimer.restart()
            return
        }
        reviewArmTimer.stop()
        reviewBaselineArmed = false
        if (typeof backend.createIntegrityBaseline === "function")
            backend.createIntegrityBaseline()
        operationMessage = "Approving current filesystem state and rebuilding the trusted baseline"
    }

    function handleReviewController(action) {
        var a = normalizeAction(action)
        var rows = reviewRows()
        if (a === "cancel") {
            reviewModalOpen = false
            reviewBaselineArmed = false
            return true
        }
        if (a === "left") {
            reviewTab = (reviewTab + 2) % 3
            reviewIndex = 0
            reviewBaselineArmed = false
            return true
        }
        if (a === "right") {
            reviewTab = (reviewTab + 1) % 3
            reviewIndex = 0
            reviewBaselineArmed = false
            return true
        }
        if (a === "up") reviewIndex = Math.max(0, reviewIndex - 1)
        else if (a === "down") reviewIndex = Math.min(Math.max(0, rows.length - 1), reviewIndex + 1)
        else if (a === "secondary") toggleReviewFlag()
        else if (a === "primary") approveReviewRow()
        return true
    }

    function handleActionModalController(action) {
        var a = normalizeAction(action)
        if (a === "cancel") { closeActionModal(); return true }
        if (actionModalIndex === 4) {
            var q = quarantineRows()
            if (a === "up") actionModalSelection = Math.max(0, actionModalSelection - 1)
            else if (a === "down") actionModalSelection = Math.min(Math.max(0, q.length - 1), actionModalSelection + 1)
            else if (a === "primary") detailsRequested("security", {incident:q.length ? q[actionModalSelection] : ({})})
            return true
        }
        if (a === "left" || a === "right") actionModalSelection = actionModalSelection === 0 ? 1 : 0
        else if (a === "primary") {
            if (actionModalSelection === 0) executeActionModal()
            else closeActionModal()
        }
        return true
    }

    function loadCachedLocation() {
        if (!settingsBackend || typeof settingsBackend.value !== "function") return
        var lat = Number(settingsBackend.value("ui.security.map.latitude", NaN))
        var lon = Number(settingsBackend.value("ui.security.map.longitude", NaN))
        var cachedSource = String(settingsBackend.value("ui.security.map.source", ""))

        // Do not reuse a fix produced by the removed Wi-Fi/BSSID method. Force
        // the first public-IP lookup to replace it instead.
        if (cachedSource.toLowerCase().indexOf("wi-fi") >= 0 ||
                cachedSource.toLowerCase().indexOf("wifi") >= 0)
            return

        if (!isNaN(lat) && !isNaN(lon)) {
            userLatitude = lat
            userLongitude = lon
            userLocationAccuracy = Number(settingsBackend.value("ui.security.map.accuracy", -1))
            userLocationSource = cachedSource.length ? cachedSource : "Cached public-IP fix"
            userLocationRegion = String(settingsBackend.value("ui.security.map.region", ""))
            userLocationCity = String(settingsBackend.value("ui.security.map.city", ""))
        }
    }

    function persistLocation(lat, lon, accuracy, source, region, city) {
        if (!settingsBackend || typeof settingsBackend.setUiPreference !== "function") return
        settingsBackend.setUiPreference("ui.security.map.latitude", lat)
        settingsBackend.setUiPreference("ui.security.map.longitude", lon)
        settingsBackend.setUiPreference("ui.security.map.accuracy", accuracy)
        settingsBackend.setUiPreference("ui.security.map.source", source)
        settingsBackend.setUiPreference("ui.security.map.region", region || "")
        settingsBackend.setUiPreference("ui.security.map.city", city || "")
    }

    function applyLocationFix(lat, lon, accuracy, source, region, city) {
        lat = Number(lat); lon = Number(lon); accuracy = Number(accuracy)
        region = String(region || "").trim()
        city = String(city || "").trim()
        if (isNaN(lat) || isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) return false

        var haveFix = !isNaN(userLatitude) && !isNaN(userLongitude)
        var currentRegion = String(userLocationRegion || "").trim().toLowerCase()
        var nextRegion = region.toLowerCase()
        var regionChanged = currentRegion.length && nextRegion.length && currentRegion !== nextRegion
        var delta = haveFix ? Math.max(Math.abs(userLatitude-lat), Math.abs(userLongitude-lon)) : 999

        // Keep a stable dot while the public-IP provider still resolves us to the
        // same state/region. Only move the marker when the region changes, or when
        // no region metadata exists and the returned fix moves a long distance.
        if (!haveFix || regionChanged || ((!currentRegion.length || !nextRegion.length) && delta > 1.25)) {
            userLatitude = lat
            userLongitude = lon
        }

        userLocationAccuracy = isNaN(accuracy) ? -1 : accuracy
        userLocationSource = source
        if (region.length) userLocationRegion = region
        if (city.length) userLocationCity = city
        persistLocation(userLatitude, userLongitude, userLocationAccuracy, userLocationSource, userLocationRegion, userLocationCity)
        threatOverlay.requestPaint()
        return true
    }

    function requestIpLocationFallback() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            locationRequestRunning = false
            if (xhr.status < 200 || xhr.status >= 300) return
            try {
                var obj = JSON.parse(xhr.responseText)
                if (obj && obj.success !== false) {
                    applyLocationFix(Number(obj.latitude), Number(obj.longitude), -1,
                                     "Public IP geolocation", String(obj.region || ""), String(obj.city || ""))
                }
            } catch(e) {}
        }
        xhr.open("GET", "https://ipwho.is/")
        xhr.send()
    }

    function requestIpLocation() {
        if (locationRequestRunning) return
        locationRequestRunning = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var obj = JSON.parse(xhr.responseText)
                    if (obj && applyLocationFix(Number(obj.latitude), Number(obj.longitude), -1,
                                                "Public IP geolocation", String(obj.region || ""), String(obj.city || ""))) {
                        locationRequestRunning = false
                        return
                    }
                } catch(e) {}
            }
            requestIpLocationFallback()
        }
        xhr.open("GET", "https://ipapi.co/json/")
        xhr.send()
    }

    function locationAccuracyText() {
        var accuracy = Number(userLocationAccuracy)
        if (isNaN(accuracy) || accuracy <= 0) return ""
        if (accuracy >= 1000) return " ±" + String(Math.max(1, Math.round(accuracy / 1000))) + " km"
        return " ±" + String(Math.max(10, Math.round(accuracy / 10) * 10)) + " m"
    }

    function mapPoint(lat, lon, w, h) {
        return ({x:((Number(lon)+180)/360)*w, y:((90-Number(lat))/180)*h})
    }

    function threatCoordinates(event) {
        var e = event || ({})
        var geo = e.geo || e.location || e.sourceGeo || ({})
        var lat = Number(e.sourceLatitude !== undefined ? e.sourceLatitude : (e.latitude !== undefined ? e.latitude : (e.lat !== undefined ? e.lat : geo.latitude !== undefined ? geo.latitude : geo.lat)))
        var lon = Number(e.sourceLongitude !== undefined ? e.sourceLongitude : (e.longitude !== undefined ? e.longitude : (e.lon !== undefined ? e.lon : (e.lng !== undefined ? e.lng : geo.longitude !== undefined ? geo.longitude : (geo.lon !== undefined ? geo.lon : geo.lng)))))
        return ({valid:!isNaN(lat)&&!isNaN(lon)&&lat>=-90&&lat<=90&&lon>=-180&&lon<=180,lat:lat,lon:lon})
    }

    function mapThreatColor(event) {
        var severity = severityNumber(event)
        if (severity >= 4) return red
        if (severity >= 3) return "#FFD84A"
        return blue
    }

    function ambientHotspotClusters() {
        // Decorative ambient network activity, intentionally separate from real
        // threat telemetry. Dense clusters make major world activity hubs obvious
        // without pretending each white point is an actual attack.
        return [
            {lat:40.7,lon:-74.0,count:52,spread:18,energy:1.00}, // US east coast
            {lat:37.6,lon:-122.2,count:36,spread:15,energy:0.86}, // US west coast
            {lat:41.9,lon:-87.6,count:20,spread:11,energy:0.62},
            {lat:43.7,lon:-79.4,count:18,spread:10,energy:0.58},
            {lat:-23.6,lon:-46.6,count:25,spread:13,energy:0.68},
            {lat:51.2,lon:1.0,count:46,spread:18,energy:0.96},   // London / western Europe
            {lat:50.2,lon:8.0,count:42,spread:18,energy:0.90},  // central Europe
            {lat:55.8,lon:37.6,count:25,spread:13,energy:0.66},
            {lat:25.2,lon:55.3,count:24,spread:12,energy:0.64},
            {lat:19.1,lon:72.9,count:34,spread:15,energy:0.80},
            {lat:1.35,lon:103.8,count:42,spread:16,energy:0.92}, // Singapore
            {lat:22.5,lon:114.1,count:45,spread:17,energy:0.95}, // HK / Shenzhen
            {lat:35.7,lon:139.7,count:50,spread:17,energy:1.00}, // Tokyo
            {lat:37.6,lon:127.0,count:36,spread:14,energy:0.82},
            {lat:31.2,lon:121.5,count:46,spread:17,energy:0.94},
            {lat:-6.2,lon:106.8,count:23,spread:12,energy:0.61},
            {lat:-33.9,lon:151.2,count:27,spread:13,energy:0.70}
        ]
    }

    function seededUnit(seed) {
        var x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    function executeQuickAction() {
        openQuickAction(selectedIndex)
    }

    function openAlertsReview() {
        reviewModalOpen = true
        reviewTab = 0
        reviewIndex = 0
        reviewBaselineArmed = false
    }

    function openActivityReview() {
        reviewModalOpen = true
        reviewTab = 2
        reviewIndex = 0
        reviewBaselineArmed = false
    }

    function openProtectionModal() {
        protectionModalSelection = 0
        protectionModalOpen = true
    }

    function closeProtectionModal() {
        protectionModalOpen = false
        protectionModalSelection = 0
    }

    function handleProtectionErrorController(action) {
        var a = normalizeAction(action)
        if (a === "primary" || a === "cancel" || a === "secondary" || a === "context")
            protectionErrorOpen = false
        return true
    }

    function handleProtectionModalController(action) {
        var a = normalizeAction(action)
        var rows = activeProtectionRows()
        var count = rows.length
        var column = protectionModalSelection % 2
        var row = Math.floor(protectionModalSelection / 2)
        var maxRow = Math.max(0, Math.ceil(count / 2) - 1)

        if (a === "cancel") {
            closeProtectionModal()
        } else if (a === "primary") {
            toggleProtectionAt(protectionModalSelection)
        } else if (a === "left") {
            if (column === 1) protectionModalSelection -= 1
        } else if (a === "right") {
            if (column === 0 && protectionModalSelection + 1 < count)
                protectionModalSelection += 1
        } else if (a === "up") {
            if (row > 0) protectionModalSelection = Math.max(0, protectionModalSelection - 2)
        } else if (a === "down") {
            if (row < maxRow && protectionModalSelection + 2 < count)
                protectionModalSelection += 2
        }
        return true
    }

    function handleControllerPressed(action) {
        if (protectionErrorOpen) return handleProtectionErrorController(action)
        if (protectionModalOpen) return handleProtectionModalController(action)
        if (reviewModalOpen) return handleReviewController(action)
        if (actionModalOpen) return handleActionModalController(action)
        var a = normalizeAction(action)

        if (focusZone === 0) {
            if (a === "primary") {
                if (!scanRunning() && backend && typeof backend.scanNeutronOS === "function")
                    backend.scanNeutronOS()
            } else if (a === "right") {
                focusZone = 4
            } else if (a === "left" || a === "up") {
                focusZone = 1
            } else if (a === "down") {
                focusZone = 3
                selectedIndex = 0
            } else if (a === "context") {
                detailsRequested("security", { incident: alertModel().length ? alertModel()[0] : ({}) })
            } else if (a === "secondary") {
                openAlertsReview()
            }
            return true
        }

        if (focusZone === 4) {
            if (a === "primary") openProtectionModal()
            else if (a === "left" || a === "up") focusZone = 0
            else if (a === "right") focusZone = 1
            else if (a === "down") {
                focusZone = 3
                selectedIndex = 0
            }
            return true
        }

        if (focusZone === 1) {
            if (a === "primary") openAlertsReview()
            else if (a === "left") focusZone = 4
            else if (a === "up") focusZone = 0
            else if (a === "right" || a === "down") focusZone = 2
            else if (a === "secondary") openAlertsReview()
            return true
        }

        if (focusZone === 2) {
            if (a === "primary") openActivityReview()
            else if (a === "up") focusZone = 1
            else if (a === "left") focusZone = 4
            else if (a === "right" || a === "down") {
                focusZone = 3
                selectedIndex = 0
            } else if (a === "secondary") openActivityReview()
            return true
        }

        // Quick Actions: normal spatial movement with adjacent anchors at edges.
        var column = selectedIndex % 2
        var row = Math.floor(selectedIndex / 2)
        if (a === "left") {
            if (column === 1) selectedIndex -= 1
            else focusZone = 2
        } else if (a === "right") {
            if (column === 0) selectedIndex += 1
            else focusZone = 1
        } else if (a === "up") {
            if (row > 0) selectedIndex -= 2
            else focusZone = column === 0 ? 4 : 2
        } else if (a === "down") {
            if (row < 2) selectedIndex += 2
            else focusZone = 0
        } else if (a === "primary") {
            openQuickAction(selectedIndex)
        } else if (a === "context") {
            detailsRequested("security", { incident: alertModel().length ? alertModel()[0] : ({}) })
        } else if (a === "secondary") {
            if (
                selectedIndex === 0 &&
                scanRunning() &&
                backend &&
                typeof backend.cancelMalwareScan === "function"
            ) {
                backend.cancelMalwareScan()
                operationMessage = "Stopping active security scan"
            } else {
                openAlertsReview()
            }
        }
        return true
    }

    Timer {
        id: sampleTimer
        interval: 2400
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sampleHistory()
    }

    Timer {
        id: trend72RefreshTimer
        interval: 60000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.rebuild72HourTrends()
    }

    Timer {
        interval: 90
        running: root.visible
        repeat: true
        onTriggered: root.trendPhase = (root.trendPhase + 0.018) % 1.0
    }

    Timer {
        interval: 250
        running: root.visible && root.scanRunning()
        repeat: true
        onTriggered: root.scanUiNowMs = Date.now()
    }

    Timer {
        id: reviewArmTimer
        interval: 3200
        repeat: false
        onTriggered: root.reviewBaselineArmed = false
    }

    Timer {
        interval: 1800000
        running: root.visible
        repeat: true
        triggeredOnStart: false
        onTriggered: root.requestIpLocation()
    }

    Timer {
        id: initialLocationTimer
        interval: 1200
        repeat: false
        onTriggered: root.requestIpLocation()
    }

    Timer {
        interval: 80
        running: root.visible
        repeat: true
        onTriggered: {
            root.mapPhase = (root.mapPhase + 0.025) % 1.0
            threatOverlay.requestPaint()
        }
    }

    Connections {
        target: root.backend
        function onStateChanged() {
            root.animatedScore = root.securityScore()
            root.rebuild72HourTrends()
            scoreGauge.requestPaint()
            threatFace.requestPaint()
            threatOverlay.requestPaint()
            if (reviewModalOpen) {
                var rows = root.reviewRows()
                root.reviewIndex = Math.max(0, Math.min(root.reviewIndex, Math.max(0, rows.length-1)))
            }
        }
        function onOperationFinished(success, message) {
            root.operationSuccess = success
            root.operationMessage = String(message || (success ? "Security operation completed" : "Security operation failed"))
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -7 * root.uiScale
        anchors.bottomMargin: -7 * root.uiScale
        color: "#020914"
        radius: 18 * root.uiScale
        border.width: 1
        border.color: "#102B45"
        clip: true

        // Extremely restrained ambient glow so the information, not the wallpaper,
        // remains the visual priority.
        Rectangle {
            width: parent.width * 0.46
            height: parent.height * 0.72
            x: -width * 0.25
            y: -height * 0.18
            radius: width / 2
            color: "#0D18376B"
            opacity: 0.35
        }
        Rectangle {
            width: parent.width * 0.38
            height: parent.height * 0.68
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            radius: width / 2
            color: "#1D2B091D"
            opacity: 0.22
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.gap

            readonly property real rightWidth: width * 0.285
            readonly property real leftWidth: width - rightWidth - root.gap
            readonly property real topHeight: height * 0.292
            readonly property real middleHeight: height * 0.352
            readonly property real bottomHeight: height - topHeight - middleHeight - root.gap * 2

            // -----------------------------------------------------------------
            // TOP LEFT: SCORE + STATUS
            // -----------------------------------------------------------------
            Rectangle {
                id: statusCard
                x: 0
                y: 0
                width: content.leftWidth * 0.54
                height: content.topHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.secureState() ? "#274D42" : "#5C2D37"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: root.secureState() ? "#153F30" : "#421B24"
                    opacity: 0.8
                }

                Item {
                    id: gaugeArea
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.50
                    anchors.margins: 12 * root.uiScale

                    Canvas {
                        id: scoreGauge
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.96
                        height: width

                        property real value: root.animatedScore
                        onValueChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2
                            var cy = height / 2
                            var radiusValue = Math.min(width, height) * 0.40
                            var segments = 44
                            var active = Math.round(segments * root.clamp(value, 0, 100) / 100)
                            var start = Math.PI * 0.62
                            var sweep = Math.PI * 1.76
                            var segmentAngle = sweep / segments

                            for (var i = 0; i < segments; ++i) {
                                var a0 = start + i * segmentAngle
                                var a1 = a0 + segmentAngle * 0.68
                                ctx.beginPath()
                                ctx.arc(cx, cy, radiusValue, a0, a1)
                                ctx.lineWidth = 10 * root.uiScale
                                if (i < active) {
                                    var ratio = i / Math.max(1, segments - 1)
                                    ctx.strokeStyle = ratio < 0.70 ? root.green : ratio < 0.88 ? "#A8F45B" : "#DAFF72"
                                } else {
                                    ctx.strokeStyle = "#16312B"
                                }
                                ctx.stroke()
                            }

                            ctx.beginPath()
                            ctx.arc(cx, cy, radiusValue - 18 * root.uiScale, 0, Math.PI * 2)
                            ctx.lineWidth = 1
                            ctx.strokeStyle = "#244B45"
                            ctx.stroke()
                        }
                    }

                    Rectangle {
                        anchors.centerIn: scoreGauge
                        width: scoreGauge.width * 0.54
                        height: width
                        radius: width / 2
                        color: "#090F18"
                        border.width: 1
                        border.color: "#1F394C"

                        SequentialAnimation on opacity {
                            running: root.visible && root.secureState()
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.90; duration: 1200 }
                            NumberAnimation { to: 1.00; duration: 1200 }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: -2 * root.uiScale
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(root.animatedScore)
                                color: root.textPrimary
                                font.pixelSize: root.textBoost * 50 * root.uiScale
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "/100"
                                color: root.textSecondary
                                font.pixelSize: root.textBoost * 18 * root.uiScale
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.scoreLabel()
                                color: root.scoreColor()
                                font.pixelSize: root.textBoost * 14 * root.uiScale
                                font.bold: true
                                font.letterSpacing: 0.8
                            }
                        }
                    }
                }

                Column {
                    anchors.left: gaugeArea.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 20 * root.uiScale
                    spacing: 9 * root.uiScale

                    Text {
                        width: parent.width
                        text: root.secureState() ? "SYSTEM SECURE" : "SECURITY ATTENTION"
                        color: root.secureState() ? root.green : root.red
                        font.pixelSize: root.textBoost * 22 * root.uiScale
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.secureState() ? "Your system is protected and monitored" : "Review active security findings"
                        color: root.textSecondary
                        font.pixelSize: root.textBoost * 13 * root.uiScale
                        elide: Text.ElideRight
                    }

                    Repeater {
                        model: [
                            { text: root.activeThreatCount() === 0 ? "No active threats detected" : String(root.activeThreatCount()) + " active event(s) require review", ok: root.activeThreatCount() === 0 },
                            { text: root.backend && root.backend.enforcementEnabled ? "Enforcement protection is active" : "Enforcement is monitoring only", ok: root.backend && root.backend.enforcementEnabled },
                            { text: root.backend && root.backend.auditValid ? "Audit chain verified" : "Audit chain requires attention", ok: root.backend && root.backend.auditValid },
                            { text: root.integrityChangeCount() === 0 ? "System integrity verified" : String(root.integrityChangeCount()) + " integrity change(s) pending", ok: root.integrityChangeCount() === 0 }
                        ]
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            spacing: 9 * root.uiScale
                            Rectangle {
                                width: 9 * root.uiScale
                                height: width
                                radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.ok ? root.green : root.orange
                            }
                            Text {
                                width: parent.width - 18 * root.uiScale
                                text: modelData.text
                                color: root.textSecondary
                                font.pixelSize: root.textBoost * 12 * root.uiScale
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        id: topScanButton
                        width: parent.width * 0.86
                        height: 40 * root.uiScale
                        radius: 10 * root.uiScale
                        color: root.focusZone===0 ? "#17334A" : "#0C1D30"
                        border.width: root.focusZone===0 ? 2 : 1
                        border.color: root.focusZone===0
                                      ? root.cyan
                                      : (root.scanRunning() ? "#4FE66A" : "#2C5578")
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            visible: root.scanRunning()

                            Rectangle {
                                id: scanProgressFill
                                y: 0
                                height: parent.height
                                width: root.scanProgressKnown()
                                       ? parent.width *
                                         (root.scanProgressPercent() / 100.0)
                                       : parent.width * 0.28
                                x: root.scanProgressKnown()
                                   ? 0
                                   : (parent.width + width) *
                                     ((root.scanUiNowMs / 1600.0) % 1.0) -
                                     width
                                color: "#244EAD5F"
                            }

                            Rectangle {
                                anchors.left: scanProgressFill.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18 * root.uiScale
                                height: parent.height * 1.7
                                rotation: 18
                                color: "#2D82FF8A"
                                visible: root.scanProgressKnown()
                                opacity: 0.36
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3 * root.uiScale
                            radius: parent.radius + 3 * root.uiScale
                            color: "transparent"
                            border.width: 1
                            border.color: root.scanRunning() ? root.green : root.cyan
                            opacity: root.focusZone===0 ? 0.30 : 0
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8 * root.uiScale

                            Text {
                                text: root.scanRunning()
                                      ? "SECURITY SCAN RUNNING"
                                      : "RUN SECURITY SCAN"
                                color: root.scanRunning()
                                       ? "#E8FFF0"
                                       : root.textPrimary
                                font.pixelSize: root.textBoost * 11.8 * root.uiScale
                                font.bold: true
                                font.letterSpacing: 0.5
                            }

                            Text {
                                visible: root.scanRunning()
                                text: root.scanProgressLabel()
                                color: root.green
                                font.pixelSize: root.textBoost * 11.8 * root.uiScale
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.focusZone = 0
                            onClicked: {
                                root.focusZone = 0
                                if (!root.scanRunning() &&
                                    root.backend &&
                                    typeof root.backend.scanNeutronOS === "function")
                                    root.backend.scanNeutronOS()
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // TOP CENTER: ACTIVE PROTECTIONS
            // -----------------------------------------------------------------
            Rectangle {
                id: protectionsCard
                x: statusCard.width + root.gap
                y: 0
                width: content.leftWidth * 0.205
                height: content.topHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: root.focusZone === 4 ? 2 : 1
                border.color: root.focusZone === 4 ? root.blue : root.border

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2 * root.uiScale
                    radius: parent.radius + 2 * root.uiScale
                    color: "transparent"
                    border.width: 1
                    border.color: "#3658A8FF"
                    visible: root.focusZone === 4
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 14 * root.uiScale
                    spacing: 7 * root.uiScale

                    Item {
                        width: parent.width
                        height: 27 * root.uiScale

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ACTIVE PROTECTIONS"
                            color: root.blue
                            font.pixelSize: root.textBoost * 14 * root.uiScale
                            font.bold: true
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62 * root.uiScale
                            height: 25 * root.uiScale
                            radius: 8 * root.uiScale
                            color: "#0B1D2B"
                            border.width: 1
                            border.color: root.protectionEnabledCount() === root.protectionTotalCount()
                                          ? "#5572F05B"
                                          : "#55FFD84A"

                            Text {
                                anchors.centerIn: parent
                                text: String(root.protectionEnabledCount()) + " / " + String(root.protectionTotalCount())
                                color: root.protectionEnabledCount() === root.protectionTotalCount()
                                       ? root.green
                                       : root.yellow
                                font.pixelSize: root.textBoost * Math.max(12, 11.2 * root.uiScale)
                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 12 * root.uiScale
                        radius: height / 2
                        color: "#081522"
                        border.width: 1
                        border.color: root.borderSoft
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (root.protectionPercent() / 100.0)
                            radius: parent.radius
                            color: root.protectionPercent() >= 80
                                   ? root.green
                                   : (root.protectionPercent() <= 50 ? root.red : root.yellow)

                            Behavior on width {
                                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 17 * root.uiScale

                        Text {
                            text: String(Math.round(root.protectionPercent())) + "% COVERAGE"
                            color: root.textMuted
                            font.pixelSize: root.textBoost * Math.max(10.6, 9.6 * root.uiScale)
                            font.bold: true
                        }

                        Item { width: Math.max(1, parent.width - 190 * root.uiScale); height: 1 }

                        Text {
                            text: "X  MANAGE"
                            color: root.focusZone === 4 ? root.blue : root.textMuted
                            font.pixelSize: root.textBoost * Math.max(10.5, 9.5 * root.uiScale)
                            font.bold: true
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 7 * root.uiScale
                        rowSpacing: 3 * root.uiScale

                        Repeater {
                            model: root.activeProtectionRows()

                            delegate: Row {
                                required property var modelData
                                width: (protectionsCard.width - 35 * root.uiScale) / 2
                                height: 18 * root.uiScale
                                spacing: 5 * root.uiScale

                                Rectangle {
                                    width: 6 * root.uiScale
                                    height: width
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.on ? root.green : root.red
                                }

                                Text {
                                    width: parent.width - 11 * root.uiScale
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    color: modelData.on ? root.textSecondary : root.textMuted
                                    font.pixelSize: root.textBoost * Math.max(10.4, 9.5 * root.uiScale)
                                    font.bold: modelData.on
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.focusZone = 4
                    onClicked: {
                        root.focusZone = 4
                        root.openProtectionModal()
                    }
                }
            }

            // -----------------------------------------------------------------
            // TOP CENTER RIGHT: THREAT LEVEL
            // -----------------------------------------------------------------
            Rectangle {
                id: threatCard
                x: protectionsCard.x + protectionsCard.width + root.gap
                y: 0
                width: content.leftWidth - x
                height: content.topHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 17 * root.uiScale
                    spacing: 10 * root.uiScale
                    Text { text: "THREAT LEVEL"; color: root.blue; font.pixelSize: root.textBoost * 14 * root.uiScale; font.bold: true }
                    Row {
                        spacing: 12 * root.uiScale
                        Item {
                            width: 42 * root.uiScale
                            height: 42 * root.uiScale
                            Canvas {
                                id: threatFace
                                anchors.fill: parent
                                property int step: root.threatFaceStep()
                                property color faceColor: root.threatFaceColor()
                                onStepChanged: requestPaint()
                                onFaceColorChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cx = width / 2
                                    var cy = height / 2
                                    var r = Math.min(width, height) * 0.39
                                    var risk = root.clamp(step / 9.0, 0, 1)

                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r * 1.18, 0, Math.PI * 2)
                                    ctx.fillStyle = Qt.rgba(faceColor.r, faceColor.g, faceColor.b, 0.10)
                                    ctx.fill()

                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                    ctx.lineWidth = 2.3 * root.uiScale
                                    ctx.strokeStyle = faceColor
                                    ctx.stroke()

                                    var eyeY = cy - r * 0.22
                                    var eyeDX = r * 0.34
                                    ctx.fillStyle = faceColor
                                    ctx.beginPath(); ctx.arc(cx-eyeDX, eyeY, 1.75*root.uiScale, 0, Math.PI*2); ctx.fill()
                                    ctx.beginPath(); ctx.arc(cx+eyeDX, eyeY, 1.75*root.uiScale, 0, Math.PI*2); ctx.fill()

                                    var mouthY = cy + r * 0.24
                                    var mouthHalf = r * 0.42
                                    var curve = (0.5 - risk) * r * 0.70
                                    ctx.beginPath()
                                    ctx.moveTo(cx-mouthHalf, mouthY)
                                    ctx.quadraticCurveTo(cx, mouthY + curve, cx+mouthHalf, mouthY)
                                    ctx.lineWidth = 2.1 * root.uiScale
                                    ctx.lineCap = "round"
                                    ctx.strokeStyle = faceColor
                                    ctx.stroke()
                                }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: root.threatWord(); color: root.textPrimary; font.pixelSize: root.textBoost * 27 * root.uiScale; font.bold: true }
                            Text { text: root.activeThreatCount() === 0 ? "No active threats" : String(root.activeThreatCount()) + " active"; color: root.threatColor(); font.pixelSize: root.textBoost * Math.max(12.0, 10.8 * root.uiScale); font.bold: true }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 25 * root.uiScale
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 7 * root.uiScale
                            radius: height / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: root.green }
                                GradientStop { position: 0.42; color: "#EAF54C" }
                                GradientStop { position: 0.66; color: root.orange }
                                GradientStop { position: 1.00; color: root.red }
                            }
                        }
                        Rectangle {
                            width: 4 * root.uiScale
                            height: 18 * root.uiScale
                            radius: width / 2
                            y: (parent.height - height) / 2
                            x: {
                                var level = Number(root.backend ? root.backend.threatLevel : 5)
                                var risk = root.clamp((5 - level) / 4, 0, 1)
                                return risk * (parent.width - width)
                            }
                            color: "white"
                            border.width: 1
                            border.color: root.threatColor()
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.borderSoft }
                    Text { text: root.backend ? String(root.backend.threatLabel || "DEFCON --") : "SECURITY CORE OFFLINE"; color: root.textSecondary; font.pixelSize: root.textBoost * Math.max(11.5, 11 * root.uiScale); font.bold: true }
                }
            }

            // -----------------------------------------------------------------
            // TOP RIGHT: RECENT ALERTS
            // -----------------------------------------------------------------
            Rectangle {
                id: alertsCard
                x: content.leftWidth + root.gap
                y: 0
                width: content.rightWidth
                height: content.topHeight + content.middleHeight * 0.18
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Rectangle {
                    id: liveScoreBar
                    anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top
                    anchors.leftMargin:17*root.uiScale;anchors.rightMargin:17*root.uiScale;anchors.topMargin:10*root.uiScale
                    height:30*root.uiScale;radius:9*root.uiScale;color:"#0C1726";border.width:1;border.color:root.borderSoft
                    Text { anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.topMargin:3*root.uiScale;text:root.securityScoreAvailable()?root.securityStrength()+" "+String(Math.round(root.securityScore()))+"%":"Unavailable";horizontalAlignment:Text.AlignHCenter;color:root.securityScoreAvailable()?root.scoreColor():root.textMuted;font.pixelSize:root.textBoost*10.5*root.uiScale;font.bold:true }
                    Rectangle {
                        anchors.left:parent.left;anchors.leftMargin:10*root.uiScale;anchors.right:parent.right;anchors.rightMargin:10*root.uiScale;anchors.bottom:parent.bottom;anchors.bottomMargin:4*root.uiScale
                        height:7*root.uiScale;radius:height/2;color:"#26384A";clip:true
                        Rectangle { width:root.securityScoreAvailable()?parent.width*root.securityScore()/100:0;height:parent.height;radius:height/2;color:root.scoreColor();Behavior on width{NumberAnimation{duration:450;easing.type:Easing.OutCubic}} }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 17 * root.uiScale
                    anchors.topMargin: 51 * root.uiScale
                    text: "RECENT ALERTS"
                    color: root.blue
                    font.pixelSize: root.textBoost * 15 * root.uiScale
                    font.bold: true
                }
                Rectangle {
                    id: alertsViewAllButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 14 * root.uiScale
                    anchors.topMargin: 46 * root.uiScale
                    width: 82 * root.uiScale
                    height: 30 * root.uiScale
                    radius: 8 * root.uiScale
                    color: root.focusZone === 1 ? "#173149" : "#0C1726"
                    border.width: root.focusZone === 1 ? 2 : 1
                    border.color: root.focusZone === 1 ? root.cyan : root.borderSoft
                    Rectangle { anchors.fill: parent; anchors.margins: -2*root.uiScale; radius: parent.radius+2*root.uiScale; color: "transparent"; border.width: 1; border.color: root.cyan; opacity: root.focusZone===1 ? 0.20 : 0 }
                    Text { anchors.centerIn: parent; text: "VIEW ALL"; color: root.focusZone===1 ? root.textPrimary : root.textSecondary; font.pixelSize: root.textBoost * Math.max(12.0, 10.8 * root.uiScale); font.bold: true }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.focusZone = 1
                        onClicked: { root.focusZone = 1; root.openAlertsReview() }
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 86 * root.uiScale
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 9 * root.uiScale

                    Repeater {
                        model: root.alertModel()
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: (alertsCard.height - 95 * root.uiScale) / 4
                            color: "transparent"
                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.borderSoft; opacity: 0.62 }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16 * root.uiScale
                                anchors.rightMargin: 15 * root.uiScale
                                spacing: 11 * root.uiScale
                                Rectangle {
                                    width: 34 * root.uiScale
                                    height: width
                                    radius: 9 * root.uiScale
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Qt.rgba(root.severityColor(modelData).r, root.severityColor(modelData).g, root.severityColor(modelData).b, 0.09)
                                    border.width: 1
                                    border.color: Qt.rgba(root.severityColor(modelData).r, root.severityColor(modelData).g, root.severityColor(modelData).b, 0.58)
                                    Rectangle { anchors.centerIn: parent; width: parent.width*0.72; height: width; radius: width/2; color: "transparent"; border.width: 1; border.color: Qt.rgba(root.severityColor(modelData).r,root.severityColor(modelData).g,root.severityColor(modelData).b,0.20) }
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.eventIconGlyph(modelData)
                                        color: root.severityColor(modelData)
                                        font.pixelSize: root.textBoost * 18 * root.uiScale
                                        font.bold: true
                                    }
                                }
                                Column {
                                    width: parent.width - 120 * root.uiScale
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3 * root.uiScale
                                    Text { width: parent.width; text: root.eventTitle(modelData); color: root.textPrimary; font.pixelSize: root.textBoost * 12.5 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: root.eventDetail(modelData); color: root.textMuted; font.pixelSize: root.textBoost * Math.max(12.0, 10.8 * root.uiScale); elide: Text.ElideRight }
                                }
                                Column {
                                    width: 64 * root.uiScale
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4 * root.uiScale
                                    Text { width: parent.width; text: root.shortWhen(modelData.timestamp || modelData.time); color: root.textMuted; font.pixelSize: root.textBoost * Math.max(11.8, 10.4 * root.uiScale); horizontalAlignment: Text.AlignRight }
                                    Text { width: parent.width; text: root.severityLabel(modelData); color: root.severityColor(modelData); font.pixelSize: root.textBoost * Math.max(11.8, 10.4 * root.uiScale); font.bold: true; horizontalAlignment: Text.AlignRight }
                                }
                            }
                        }
                    }

                    Item {
                        visible: root.alertModel().length === 0
                        width: parent.width
                        height: parent.height
                        Column {
                            anchors.centerIn: parent
                            spacing: 6 * root.uiScale
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "✓"; color: root.green; font.pixelSize: root.textBoost * 32 * root.uiScale; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NO ACTIVE ALERTS"; color: root.textPrimary; font.pixelSize: root.textBoost * 12 * root.uiScale; font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Security event queue is clear"; color: root.textMuted; font.pixelSize: root.textBoost * Math.max(12.0, 10.8 * root.uiScale) }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // MIDDLE LEFT: PROTECTION MODULES
            // -----------------------------------------------------------------
            Rectangle {
                id: modulesPanel
                x: 0
                y: content.topHeight + root.gap
                width: content.leftWidth
                height: content.middleHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 17 * root.uiScale
                    anchors.topMargin: 13 * root.uiScale
                    text: "PROTECTION MODULES"
                    color: root.blue
                    font.pixelSize: root.textBoost * 15 * root.uiScale
                    font.bold: true
                }

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 13 * root.uiScale
                    anchors.topMargin: 45 * root.uiScale
                    spacing: 11 * root.uiScale

                    Repeater {
                        model: [
                            {
                                title: "MALWARE DEFENSE",
                                subtitle: "Real-time malware detection and removal",
                                accent: root.purple,
                                percent: root.malwareFindingCount() === 0 ? 100 : Math.max(0, 100 - root.malwareFindingCount() * 8),
                                center: root.scanRunning() ? "SCAN" : (root.malwareFindingCount() === 0 ? "CLEAR" : String(root.malwareFindingCount()) + " FOUND"),
                                rows: [
                                    {l:"Findings",v:String(root.malwareFindingCount())},
                                    {l:"Quarantined",v:String(root.quarantinedCount())},
                                    {l:"Scan State",v:root.scanRunning()?"Running":"Ready"},
                                    {l:"Daemon",v:root.backend&&root.backend.daemonOnline?"Online":"Offline"}
                                ]
                            },
                            {
                                title: "FIREWALL & NETWORK",
                                subtitle: "Network traffic monitoring and filtering",
                                accent: root.red,
                                percent: root.backend&&root.backend.enforcementEnabled?100:72,
                                center: root.backend&&root.backend.enforcementEnabled?"SECURE":"MONITOR",
                                rows: [
                                    {l:"Blocked",v:String(root.blockedCount())},
                                    {l:"Banned Sources",v:String(root.bannedSourceCount())},
                                    {l:"Ports Monitored",v:String(root.listeningPortCount())},
                                    {l:"Enforcement",v:root.backend&&root.backend.enforcementEnabled?"On":"Off"}
                                ]
                            },
                            {
                                title: "INTEGRITY PROTECTION",
                                subtitle: "System integrity and tamper protection",
                                accent: root.orange,
                                percent: root.integrityChangeCount()===0&&root.backend&&root.backend.auditValid?100:68,
                                center: root.integrityChangeCount()===0?"SECURE":String(root.integrityChangeCount())+" CHANGE",
                                rows: [
                                    {l:"Integrity",v:String(root.backend?root.backend.integrityStatus:"Unavailable")},
                                    {l:"Changes",v:String(root.integrityChangeCount())},
                                    {l:"Audit Chain",v:root.backend&&root.backend.auditValid?"Verified":"Attention"},
                                    {l:"Audit Records",v:String(root.backend&&root.backend.auditEntries?root.backend.auditEntries.length:0)}
                                ]
                            }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - parent.spacing * 2) / 3
                            height: parent.height
                            radius: 15 * root.uiScale
                            color: root.panelRaised
                            border.width: 1
                            border.color: root.borderSoft

                            Column {
                                anchors.fill: parent
                                anchors.margins: 14 * root.uiScale
                                spacing: 6 * root.uiScale

                                Row {
                                    width: parent.width
                                    spacing: 10 * root.uiScale
                                    Text { text: "⬡"; color: modelData.accent; font.pixelSize: root.textBoost * 29 * root.uiScale; font.bold: true }
                                    Column {
                                        width: parent.width - 42 * root.uiScale
                                        Text { width: parent.width; text: modelData.title; color: modelData.accent; font.pixelSize: root.textBoost * 13.5 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                                        Text { width: parent.width; text: modelData.subtitle; color: root.textSecondary; font.pixelSize: root.textBoost * Math.max(11.2, 10.3 * root.uiScale); elide: Text.ElideRight }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: parent.height - 91 * root.uiScale
                                    spacing: 10 * root.uiScale

                                    Item {
                                        width: parent.width * 0.42
                                        height: parent.height
                                        Canvas {
                                            id: moduleGauge
                                            anchors.centerIn: parent
                                            width: Math.min(parent.width, parent.height) * 0.92
                                            height: width
                                            property real value: modelData.percent
                                            property color accent: root.moduleScoreColor(modelData.percent)
                                            onValueChanged: requestPaint()
                                            onAccentChanged: requestPaint()
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.reset()
                                                var cx = width/2, cy = height/2, radiusValue = Math.min(width,height)*0.38
                                                ctx.beginPath(); ctx.arc(cx,cy,radiusValue,0,Math.PI*2); ctx.lineWidth=8*root.uiScale; ctx.strokeStyle="#152638"; ctx.stroke()
                                                ctx.beginPath(); ctx.arc(cx,cy,radiusValue,-Math.PI/2,-Math.PI/2+Math.PI*2*root.clamp(value,0,100)/100); ctx.lineWidth=8*root.uiScale; ctx.lineCap="round"; ctx.strokeStyle=accent; ctx.stroke()
                                            }
                                        }
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(Math.round(modelData.percent)) + "%"; color: root.textPrimary; font.pixelSize: root.textBoost * 22 * root.uiScale; font.bold: true }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.center; color: root.moduleScoreColor(modelData.percent); font.pixelSize: root.textBoost * Math.max(10.8, 8.8 * root.uiScale); font.bold: true }
                                        }
                                    }

                                    Column {
                                        width: parent.width * 0.58 - 10 * root.uiScale
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8 * root.uiScale
                                        Repeater {
                                            model: modelData.rows
                                            delegate: Row {
                                                required property var modelData
                                                width: parent.width
                                                Text { width: parent.width * 0.58; text: modelData.l; color: root.textMuted; font.pixelSize: root.textBoost * Math.max(12.0, 10.8 * root.uiScale); elide: Text.ElideRight }
                                                Text { width: parent.width * 0.42; text: modelData.v; color: root.textPrimary; font.pixelSize: root.textBoost * Math.max(11.5, 10.8 * root.uiScale); font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                                            }
                                        }
                                    }
                                }

                                Rectangle { width: parent.width; height: 1; color: root.borderSoft }
                                Row {
                                    width: parent.width
                                    spacing: 7 * root.uiScale
                                    Text { text: "Status"; color: root.textMuted; font.pixelSize: root.textBoost * Math.max(11.2, 10 * root.uiScale) }
                                    Rectangle { width: 8 * root.uiScale; height: width; radius: width/2; color: root.moduleScoreColor(modelData.percent); anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: root.moduleScoreLabel(modelData.percent); color: root.moduleScoreColor(modelData.percent); font.pixelSize: root.textBoost * Math.max(11.2, 10 * root.uiScale); font.bold: true }
                                }
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT MIDDLE: ACTIVITY
            // -----------------------------------------------------------------
            Rectangle {
                id: activityCard
                x: content.leftWidth + root.gap
                y: alertsCard.height + root.gap
                width: content.rightWidth
                height: content.middleHeight * 0.82 - root.gap
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Text { anchors.left: parent.left; anchors.top: parent.top; anchors.leftMargin: 17*root.uiScale; anchors.topMargin: 14*root.uiScale; text: "RECENT ACTIVITY"; color: root.blue; font.pixelSize: root.textBoost * 15*root.uiScale; font.bold: true }
                Rectangle {
                    id: activityViewAllButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 14*root.uiScale
                    anchors.topMargin: 9*root.uiScale
                    width: 82*root.uiScale
                    height: 30*root.uiScale
                    radius: 8*root.uiScale
                    color: root.focusZone===2 ? "#173149" : "#0C1726"
                    border.width: root.focusZone===2 ? 2 : 1
                    border.color: root.focusZone===2 ? root.cyan : root.borderSoft
                    Rectangle { anchors.fill: parent; anchors.margins: -2*root.uiScale; radius: parent.radius+2*root.uiScale; color:"transparent"; border.width:1; border.color:root.cyan; opacity:root.focusZone===2?0.20:0 }
                    Text { anchors.centerIn: parent; text:"VIEW ALL"; color:root.focusZone===2?root.textPrimary:root.textSecondary; font.pixelSize: root.textBoost *Math.max(12.0,10.8*root.uiScale); font.bold:true }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.focusZone = 2
                        onClicked: { root.focusZone = 2; root.openActivityReview() }
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 47 * root.uiScale
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8 * root.uiScale
                    Repeater {
                        model: root.activityModel()
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            height: (activityCard.height - 55*root.uiScale) / 5
                            spacing: 10*root.uiScale
                            Rectangle {
                                width: 30*root.uiScale
                                height: width
                                radius: 8*root.uiScale
                                anchors.verticalCenter: parent.verticalCenter
                                property color iconTone: modelData.ok ? root.green : root.orange
                                color: Qt.rgba(iconTone.r,iconTone.g,iconTone.b,0.08)
                                border.width: 1
                                border.color: Qt.rgba(iconTone.r,iconTone.g,iconTone.b,0.48)
                                Text { anchors.centerIn: parent; text: root.activityIconGlyph(modelData); color: parent.iconTone; font.pixelSize: root.textBoost * 16*root.uiScale; font.bold: true }
                            }
                            Column {
                                width: parent.width - 106*root.uiScale
                                anchors.verticalCenter: parent.verticalCenter
                                Text { width: parent.width; text: modelData.title; color: root.textPrimary; font.pixelSize: root.textBoost * 11.5*root.uiScale; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.detail; color: root.textMuted; font.pixelSize: root.textBoost * Math.max(11.0, 9.7*root.uiScale); elide: Text.ElideRight }
                            }
                            Text { width: 56*root.uiScale; anchors.verticalCenter: parent.verticalCenter; text: root.shortWhen(modelData.time); color: root.textMuted; font.pixelSize: root.textBoost * Math.max(10.8, 9.4*root.uiScale); horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // BOTTOM LEFT: LIVE THREAT MAP
            // -----------------------------------------------------------------
            Rectangle {
                id: mapCard
                x: 0
                y: content.topHeight + content.middleHeight + root.gap * 2
                width: content.leftWidth * 0.58
                height: content.bottomHeight
                radius: 18 * root.uiScale
                color: "#F0081524"
                border.width: 1
                border.color: root.border
                clip: true

                Row {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 17*root.uiScale
                    anchors.topMargin: 13*root.uiScale
                    spacing: 5*root.uiScale
                    Text { text: "THREAT MAP"; color: root.red; font.pixelSize: root.textBoost * Math.max(14,15*root.uiScale); font.bold: true }
                    Text { text: "•"; color: root.textMuted; font.pixelSize: root.textBoost * Math.max(14,15*root.uiScale); font.bold: true }
                    Text { text: "LIVE"; color: root.green; font.pixelSize: root.textBoost * Math.max(14,15*root.uiScale); font.bold: true }
                }
                Text {
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.rightMargin: 17*root.uiScale; anchors.topMargin: 14*root.uiScale
                    text: isNaN(root.userLatitude) || isNaN(root.userLongitude)
                          ? "Securing Local Location"
                          : (root.activeThreatCount() === 0 ? "Local Secured" : "Actively Monitoring")
                    color: isNaN(root.userLatitude) || isNaN(root.userLongitude)
                           ? root.textMuted
                           : root.green
                    font.pixelSize: root.textBoost * Math.max(13.0, 11.6*root.uiScale); font.bold: true
                }

                Item {
                    id: worldViewport
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: legendRow.top
                    anchors.leftMargin: 13*root.uiScale; anchors.rightMargin: 13*root.uiScale
                    anchors.topMargin: 43*root.uiScale; anchors.bottomMargin: 5*root.uiScale
                    clip: true

                    Rectangle { anchors.fill: parent; radius: 12*root.uiScale; color: "#07111D"; border.width: 1; border.color: "#18334A" }

                    // Natural Earth country polygons rendered as an SVG asset.
                    // This replaces the old five-blob silhouette with clear,
                    // individual country boundaries while keeping rendering cheap
                    // enough for the Pi dashboard.
                    Item {
                        id: mapSurface
                        anchors.fill: parent
                        anchors.margins: 5*root.uiScale
                        transform: Scale {
                            origin.x: mapSurface.width / 2
                            origin.y: 0
                            xScale: 1.0
                            yScale: 1.16
                        }

                        Image {
                            id: worldOutline
                            anchors.fill: parent
                            source: "assets/world-countries.svg"
                            fillMode: Image.Stretch
                            smooth: true
                            mipmap: true
                            opacity: 0.98
                        }

                        Canvas {
                            id: threatOverlay
                            anchors.fill: parent
                        property var liveEvents: root.backend&&root.backend.threatMapPoints&&root.backend.threatMapPoints.length?root.backend.threatMapPoints:root.unresolvedEvents()
                        onLiveEventsChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var w = width, h = height

                            // Dense ambient activity clusters. White points are
                            // decorative network activity only; colored points below
                            // remain the authoritative threat telemetry.
                            var clusters = root.ambientHotspotClusters()
                            for (var c=0; c<clusters.length; ++c) {
                                var cluster = clusters[c]
                                var hp = root.mapPoint(cluster.lat, cluster.lon, w, h)
                                var pulse = 0.55 + 0.45*Math.abs(Math.sin((root.mapPhase+c*0.071)*Math.PI*2))

                                // Low-alpha bloom makes the cluster read as a hotspot
                                // before individual points are even noticed.
                                for (var halo=3; halo>=1; --halo) {
                                    ctx.beginPath()
                                    ctx.arc(hp.x, hp.y, cluster.spread*root.uiScale*(0.42 + halo*0.26), 0, Math.PI*2)
                                    ctx.fillStyle = Qt.rgba(0.72,0.88,1.0,0.010*cluster.energy*halo*pulse)
                                    ctx.fill()
                                }

                                for (var j=0; j<cluster.count; ++j) {
                                    var angle = root.seededUnit(c*911 + j*37 + 3) * Math.PI * 2
                                    var radiusUnit = Math.pow(root.seededUnit(c*577 + j*53 + 11), 0.62)
                                    var radius = radiusUnit * cluster.spread * root.uiScale
                                    var px = hp.x + Math.cos(angle) * radius
                                    var py = hp.y + Math.sin(angle) * radius * 0.58
                                    var twinkle = 0.34 + 0.58*Math.abs(Math.sin((root.mapPhase*1.15 + c*0.083 + j*0.019)*Math.PI*2))
                                    var core = (j % 11 === 0) ? 1.45 : ((j % 5 === 0) ? 1.15 : 0.82)

                                    if (j % 9 === 0) {
                                        ctx.beginPath(); ctx.arc(px,py,2.6*root.uiScale,0,Math.PI*2)
                                        ctx.fillStyle = Qt.rgba(0.72,0.88,1.0,0.07*twinkle*cluster.energy); ctx.fill()
                                    }
                                    ctx.beginPath(); ctx.arc(px,py,core*root.uiScale,0,Math.PI*2)
                                    ctx.fillStyle = Qt.rgba(0.92,0.97,1.0,twinkle*cluster.energy); ctx.fill()
                                }
                            }

                            var homeValid = !isNaN(root.userLatitude) && !isNaN(root.userLongitude)
                            var home = homeValid ? root.mapPoint(root.userLatitude, root.userLongitude, w, h) : ({x:w*0.5,y:h*0.5})
                            var source = root.backend&&root.backend.threatMapPoints&&root.backend.threatMapPoints.length?root.backend.threatMapPoints:root.unresolvedEvents()
                            var geolocated = 0
                            for (var i=0; i<source.length; ++i) {
                                var e = source[i] || ({})
                                var geo = root.threatCoordinates(e)
                                if (!geo.valid || !homeValid) continue
                                var origin = root.mapPoint(geo.lat, geo.lon, w, h)
                                var color = root.mapThreatColor(e)
                                var dx = home.x-origin.x, dy = home.y-origin.y
                                var distance = Math.sqrt(dx*dx+dy*dy)
                                var lift = Math.min(h*0.28, Math.max(18*root.uiScale, distance*0.30))
                                var midX = (origin.x+home.x)/2
                                var midY = Math.max(8*root.uiScale, Math.min(origin.y,home.y)-lift)

                                ctx.beginPath(); ctx.moveTo(origin.x,origin.y); ctx.quadraticCurveTo(midX,midY,home.x,home.y)
                                ctx.lineWidth = 1.45*root.uiScale
                                ctx.strokeStyle = Qt.rgba(color.r,color.g,color.b,0.72)
                                ctx.stroke()

                                // Moving pulse along the quadratic curve.
                                var t = (root.mapPhase + i*0.17) % 1.0
                                var omt = 1-t
                                var px = omt*omt*origin.x + 2*omt*t*midX + t*t*home.x
                                var py = omt*omt*origin.y + 2*omt*t*midY + t*t*home.y
                                ctx.beginPath(); ctx.arc(px,py,2.0*root.uiScale,0,Math.PI*2)
                                ctx.fillStyle = color; ctx.fill()

                                ctx.beginPath(); ctx.arc(origin.x,origin.y,7*root.uiScale,0,Math.PI*2)
                                ctx.fillStyle = Qt.rgba(color.r,color.g,color.b,0.12); ctx.fill()
                                ctx.beginPath(); ctx.arc(origin.x,origin.y,3.0*root.uiScale,0,Math.PI*2)
                                ctx.fillStyle = color; ctx.fill()
                                geolocated++
                            }

                            if (homeValid) {
                                // Persistent home position with small radiating ripples.
                                for (var r=0; r<3; ++r) {
                                    var phase = (root.mapPhase + r/3) % 1.0
                                    var radius = (5 + phase*18)*root.uiScale
                                    ctx.beginPath(); ctx.arc(home.x,home.y,radius,0,Math.PI*2)
                                    ctx.lineWidth = 1.15*root.uiScale
                                    ctx.strokeStyle = Qt.rgba(root.green.r,root.green.g,root.green.b,0.42*(1-phase))
                                    ctx.stroke()
                                }
                                ctx.beginPath(); ctx.arc(home.x,home.y,6.5*root.uiScale,0,Math.PI*2)
                                ctx.fillStyle = Qt.rgba(root.green.r,root.green.g,root.green.b,0.14); ctx.fill()
                                ctx.beginPath(); ctx.arc(home.x,home.y,3.2*root.uiScale,0,Math.PI*2)
                                ctx.fillStyle = root.green; ctx.fill()
                            }

                            if (!homeValid) {
                                ctx.fillStyle = root.textSecondary
                                ctx.font = "600 " + Math.round(11.8*root.uiScale) + "px sans-serif"
                                ctx.textAlign = "center"
                                ctx.fillText("Securing Local Location • Fortifying Defenses",w/2,h-14*root.uiScale)
                            }
                        }
                    }
                    }

                    Rectangle {
                        id: sweepLine
                        width: 2*root.uiScale
                        height: parent.height
                        y: 0
                        color: root.cyan
                        opacity: 0.13
                        NumberAnimation on x {
                            from: 0
                            to: worldViewport.width
                            duration: 4200
                            loops: Animation.Infinite
                        }
                    }
                }

                Row {
                    id: legendRow
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.leftMargin: 17*root.uiScale; anchors.rightMargin: 17*root.uiScale; anchors.bottomMargin: 10*root.uiScale
                    height: 23*root.uiScale
                    spacing: 13*root.uiScale
                    Repeater {
                        model:[{t:"HOME",c:root.green},{t:"LOW",c:root.blue},{t:"MEDIUM",c:"#FFD84A"},{t:"HIGH",c:root.red},{t:"ACTIVITY",c:"#F2F7FF"}]
                        delegate:Row {
                            required property var modelData
                            spacing:5*root.uiScale
                            Rectangle { width:7*root.uiScale; height:width; radius:width/2; color:modelData.c; anchors.verticalCenter:parent.verticalCenter }
                            Text { text:modelData.t; color:root.textSecondary; font.pixelSize: root.textBoost *Math.max(10.8,9.5*root.uiScale); font.bold:true }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // BOTTOM CENTER: LIVE SECURITY TRENDS
            // -----------------------------------------------------------------
            Rectangle {
                id: trendsCard
                x: mapCard.width + root.gap
                y: mapCard.y
                width: content.leftWidth - mapCard.width - root.gap
                height: content.bottomHeight
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.leftMargin: 17 * root.uiScale
                    anchors.topMargin: 13 * root.uiScale
                    text: "SECURITY TRENDS (LAST 72 HOURS)"
                    color: root.blue
                    font.pixelSize: root.textBoost * 15 * root.uiScale
                    font.bold: true
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 15 * root.uiScale
                    anchors.topMargin: 45 * root.uiScale
                    spacing: 7 * root.uiScale

                    Repeater {
                        model: [
                            {
                                label: "Threat Events",
                                value: String(root.threat72Total),
                                suffix: "",
                                color: root.orange,
                                canvas: 0
                            },
                            {
                                label: "Blocked Activity",
                                value: String(root.blocked72Total),
                                suffix: "",
                                color: root.red,
                                canvas: 1
                            },
                            {
                                label: "Audit Activity",
                                value: String(root.audit72Total),
                                suffix: "",
                                color: root.green,
                                canvas: 2
                            },
                            {
                                label: "Security Scans",
                                value: String(root.scan72Total),
                                suffix: "",
                                color: root.blue,
                                canvas: 3
                            }
                        ]

                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            height: (
                                trendsCard.height -
                                75 * root.uiScale
                            ) / 4
                            spacing: 10 * root.uiScale

                            Column {
                                width: parent.width * 0.30
                                anchors.verticalCenter:
                                    parent.verticalCenter

                                Text {
                                    width: parent.width
                                    text: modelData.label
                                    color: root.textSecondary
                                    font.pixelSize: root.textBoost * Math.max(
                                        11.2,
                                        10.4 * root.uiScale
                                    )
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text:
                                        modelData.value +
                                        modelData.suffix
                                    color: root.textPrimary
                                    font.pixelSize: root.textBoost *
                                        17 * root.uiScale
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                width:
                                    parent.width * 0.70 -
                                    10 * root.uiScale
                                height: parent.height

                                Canvas {
                                    id: trendThreats72
                                    anchors.fill: parent
                                    visible:
                                        modelData.canvas === 0
                                    property var series:
                                        root.threat72History
                                    property real phase:
                                        root.trendPhase
                                    onSeriesChanged:
                                        requestPaint()
                                    onPhaseChanged:
                                        requestPaint()
                                    onPaint:
                                        root.drawTrendSpark(
                                            trendThreats72,
                                            series,
                                            root.orange,
                                            0.06
                                        )
                                }

                                Canvas {
                                    id: trendBlocked72
                                    anchors.fill: parent
                                    visible:
                                        modelData.canvas === 1
                                    property var series:
                                        root.blocked72History
                                    property real phase:
                                        root.trendPhase
                                    onSeriesChanged:
                                        requestPaint()
                                    onPhaseChanged:
                                        requestPaint()
                                    onPaint:
                                        root.drawTrendSpark(
                                            trendBlocked72,
                                            series,
                                            root.red,
                                            0.06
                                        )
                                }

                                Canvas {
                                    id: trendAudit72
                                    anchors.fill: parent
                                    visible:
                                        modelData.canvas === 2
                                    property var series:
                                        root.audit72History
                                    property real phase:
                                        root.trendPhase
                                    onSeriesChanged:
                                        requestPaint()
                                    onPhaseChanged:
                                        requestPaint()
                                    onPaint:
                                        root.drawTrendSpark(
                                            trendAudit72,
                                            series,
                                            root.green,
                                            0.05
                                        )
                                }

                                Canvas {
                                    id: trendScans72
                                    anchors.fill: parent
                                    visible:
                                        modelData.canvas === 3
                                    property var series:
                                        root.scan72History
                                    property real phase:
                                        root.trendPhase
                                    onSeriesChanged:
                                        requestPaint()
                                    onPhaseChanged:
                                        requestPaint()
                                    onPaint:
                                        root.drawTrendSpark(
                                            trendScans72,
                                            series,
                                            root.blue,
                                            0.05
                                        )
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    text: "72H AGO"
                                    color: root.textMuted
                                    opacity: 0.66
                                    font.pixelSize: root.textBoost * Math.max(
                                        8.8,
                                        8.0 * root.uiScale
                                    )
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    text: "NOW"
                                    color: root.textMuted
                                    opacity: 0.66
                                    font.pixelSize: root.textBoost * Math.max(
                                        8.8,
                                        8.0 * root.uiScale
                                    )
                                }
                            }
                        }
                    }
                }

            }

            // -----------------------------------------------------------------
            // BOTTOM RIGHT: QUICK ACTIONS
            // -----------------------------------------------------------------
            Rectangle {
                id: quickCard
                x: content.leftWidth + root.gap
                y: activityCard.y + activityCard.height + root.gap
                width: content.rightWidth
                height: content.height - y
                radius: 18 * root.uiScale
                color: root.panel
                border.width: 1
                border.color: root.border

                Row {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: 17*root.uiScale; anchors.rightMargin: 17*root.uiScale; anchors.topMargin: 12*root.uiScale
                    height: 25*root.uiScale
                    Text { text:"QUICK ACTIONS"; color:root.blue; font.pixelSize: root.textBoost *Math.max(14,15*root.uiScale); font.bold:true }
                    Item { width: parent.width - 230*root.uiScale; height:1 }
                    Text { text:(root.scanRunning()&&root.selectedIndex===0)?"SQUARE  STOP SCAN":"D-PAD  SELECT   X  OPEN"; color:(root.scanRunning()&&root.selectedIndex===0)?root.red:root.textMuted; font.pixelSize: root.textBoost *Math.max(11.8,10.5*root.uiScale); font.bold:true }
                }

                Grid {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.margins: 13*root.uiScale; anchors.topMargin: 43*root.uiScale
                    columns: 2; rows: 3
                    columnSpacing: 9*root.uiScale; rowSpacing: 9*root.uiScale

                    Repeater {
                        model: root.quickActionRows()

                        delegate: Rectangle {
                            required property int index
                            required property var modelData

                            width: (
                                quickCard.width -
                                35 * root.uiScale
                            ) / 2

                            height: (
                                quickCard.height -
                                72 * root.uiScale
                            ) / 3

                            radius: 13 * root.uiScale
                            color:
                                root.focusZone===3 &&
                                index===root.selectedIndex
                                ? "#132638"
                                : "#081521"

                            border.width:
                                root.focusZone===3 &&
                                index===root.selectedIndex
                                ? 2 : 1

                            border.color:
                                root.focusZone===3 &&
                                index===root.selectedIndex
                                ? modelData.tone
                                : "#23394C"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 3 * root.uiScale
                                radius: height / 2
                                color: modelData.tone
                                opacity:
                                    root.focusZone===3 &&
                                    index===root.selectedIndex
                                    ? 0.95 : 0.42
                            }

                            Rectangle {
                                width: 36 * root.uiScale
                                height: width
                                radius: 10 * root.uiScale
                                anchors.left: parent.left
                                anchors.leftMargin: 12 * root.uiScale
                                anchors.verticalCenter:
                                    parent.verticalCenter

                                color:
                                    Qt.rgba(
                                        modelData.tone.r,
                                        modelData.tone.g,
                                        modelData.tone.b,
                                        0.12
                                    )

                                border.width: 1
                                border.color:
                                    Qt.rgba(
                                        modelData.tone.r,
                                        modelData.tone.g,
                                        modelData.tone.b,
                                        0.50
                                    )

                                Canvas {
                                    anchors.fill: parent
                                    anchors.margins: 6 * root.uiScale

                                    onPaint: {
                                        root.drawQuickActionIcon(
                                            getContext("2d"),
                                            modelData.key,
                                            modelData.tone,
                                            width,
                                            height
                                        )
                                    }

                                    Connections {
                                        target: root
                                        function onBackendChanged() { parent.requestPaint() }
                                    }
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin:
                                    58 * root.uiScale
                                anchors.right: parent.right
                                anchors.rightMargin:
                                    12 * root.uiScale
                                anchors.verticalCenter:
                                    parent.verticalCenter
                                spacing: 2 * root.uiScale

                                Text {
                                    width: parent.width
                                    text: modelData.title
                                    color: root.textPrimary
                                    font.pixelSize: root.textBoost * Math.max(
                                        12.4,
                                        11.4 * root.uiScale
                                    )
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.detail
                                    color:
                                        root.focusZone===3 &&
                                        index===root.selectedIndex
                                        ? root.textSecondary
                                        : root.textMuted
                                    font.pixelSize: root.textBoost * Math.max(
                                        10.9,
                                        9.9 * root.uiScale
                                    )
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin:
                                    8 * root.uiScale
                                anchors.top: parent.top
                                anchors.topMargin:
                                    8 * root.uiScale
                                width: 6 * root.uiScale
                                height: width
                                radius: width / 2
                                color: modelData.tone
                                opacity:
                                    root.focusZone===3 &&
                                    index===root.selectedIndex
                                    ? 1.0 : 0.45
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins:
                                    -2 * root.uiScale
                                radius:
                                    parent.radius +
                                    2 * root.uiScale
                                color: "transparent"
                                border.width: 1
                                border.color:
                                    Qt.rgba(
                                        modelData.tone.r,
                                        modelData.tone.g,
                                        modelData.tone.b,
                                        0.18
                                    )
                                visible:
                                    root.focusZone===3 &&
                                    index===root.selectedIndex
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                onEntered: {
                                    root.focusZone = 3
                                    root.selectedIndex = index
                                }

                                onClicked: {
                                    root.focusZone = 3
                                    root.openQuickAction(index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }


    // -------------------------------------------------------------------------
    // PREMIUM QUICK-ACTION MODALS
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        z: 500
        visible: root.controllerModalOpen
        color: "#B900050D"

        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
            id: actionModal
            visible: root.actionModalOpen
            width: Math.min(parent.width * 0.70, 960 * root.uiScale)
            height: root.actionModalIndex === 1
                    ? Math.min(parent.height * 0.60, 525 * root.uiScale)
                    : (
                        root.actionModalIndex === 2 ||
                        root.actionModalIndex === 3
                        ? Math.min(parent.height * 0.64, 555 * root.uiScale)
                        : Math.min(parent.height * 0.69, 595 * root.uiScale)
                      )
            anchors.centerIn: parent
            radius: 24*root.uiScale
            color: "#F6081524"
            border.width: 1.5
            border.color: root.actionModalIndex>=0
                          ? root.modalAccent(root.actionModalIndex)
                          : root.border

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 5 * root.uiScale
                radius: height / 2
                color: root.actionModalIndex>=0
                       ? root.modalAccent(root.actionModalIndex)
                       : root.red
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: "#352B465E"
            }

            Column {
                anchors.fill: parent
                anchors.margins: 24 * root.uiScale
                spacing: 12 * root.uiScale

                Text {
                    width: parent.width
                    text: root.quickActionTitle(root.actionModalIndex)
                    color: root.textPrimary
                    font.pixelSize: root.textBoost * Math.max(23, 26 * root.uiScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.quickActionDetail(root.actionModalIndex)
                    color: root.textSecondary
                    font.pixelSize: root.textBoost * Math.max(14, 14.5 * root.uiScale)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle { width:parent.width; height:1; color:root.borderSoft }

                Item {
                    width:parent.width
                    height: parent.height - 180 * root.uiScale

                    Column {
                        visible: root.actionModalIndex!==4
                        anchors.centerIn: parent; width:parent.width*0.80; spacing:18*root.uiScale
                        Rectangle {
                            width: parent.width
                            height: 112 * root.uiScale
                            radius: 17 * root.uiScale
                            color: "#0A1723"
                            border.width: 1
                            border.color: Qt.rgba(
                                root.modalAccent(root.actionModalIndex).r,
                                root.modalAccent(root.actionModalIndex).g,
                                root.modalAccent(root.actionModalIndex).b,
                                0.42
                            )
                            Column { anchors.centerIn:parent; spacing:7*root.uiScale
                                Text { anchors.horizontalCenter:parent.horizontalCenter; text:root.actionModalIndex===0?(root.scanRunning()?"SCAN ACTIVE":"READY TO SCAN"):root.actionModalIndex===1?"AUTHORITATIVE SNAPSHOT":root.actionModalIndex===2?(root.backend&&root.backend.enforcementEnabled?"FIREWALL ENFORCEMENT ACTIVE":"FIREWALL MONITORING MODE"):root.actionModalIndex===3?("DEFCON "+String(root.backend?root.backend.threatLevel:5)+"  →  DEFCON "+String(Math.max(1,Number(root.backend?root.backend.threatLevel:5)-1))):"READY"; color:root.actionModalIndex>=0?root.modalAccent(root.actionModalIndex):root.cyan; font.pixelSize: root.textBoost *Math.max(20,22*root.uiScale); font.bold:true }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width * 0.88
                                    text:
                                        root.actionModalIndex===1
                                        ? "Refreshes authoritative Security Core state without changing policy."
                                        : (
                                            root.actionModalIndex===2
                                            ? "Review and change active network-policy enforcement."
                                            : (
                                                root.actionModalIndex===3
                                                ? "Lower DEFCON number means a stricter security posture."
                                                : "Changes are executed through Security Core."
                                              )
                                          )
                                    color: root.textMuted
                                    font.pixelSize: root.textBoost * Math.max(12,12.5*root.uiScale)
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                        Row {
                            anchors.horizontalCenter:parent.horizontalCenter; spacing:10*root.uiScale
                            Repeater {
                                model:root.actionModalMetrics(root.actionModalIndex)
                                delegate:Rectangle {
                                    required property var modelData
                                    width:190*root.uiScale; height:72*root.uiScale; radius:13*root.uiScale
                                    color:"#091723"
                                    border.width:1
                                    border.color:Qt.rgba(root.red.r,root.red.g,root.red.b,0.28)
                                    Rectangle {
                                        anchors.left:parent.left
                                        anchors.right:parent.right
                                        anchors.top:parent.top
                                        height:2*root.uiScale
                                        color:modelData.c
                                        opacity:0.72
                                    }
                                    Column { anchors.centerIn:parent; spacing:4*root.uiScale
                                        Text { anchors.horizontalCenter:parent.horizontalCenter; text:modelData.l; color:root.textMuted; font.pixelSize: root.textBoost *Math.max(11.5,10.5*root.uiScale); font.bold:true }
                                        Text { anchors.horizontalCenter:parent.horizontalCenter; text:modelData.v; color:modelData.c; font.pixelSize: root.textBoost *15*root.uiScale; font.bold:true }
                                    }
                                }
                            }
                        }
                        Row { anchors.horizontalCenter:parent.horizontalCenter; spacing:14*root.uiScale
                            Repeater { model:["CONFIRM","CANCEL"]; delegate:Rectangle { required property int index; required property string modelData; width:185*root.uiScale; height:54*root.uiScale; radius:13*root.uiScale; color:root.actionModalSelection===index?"#173149":"#0A1826"; border.width:root.actionModalSelection===index?2:1; border.color:root.actionModalSelection===index?(root.actionModalIndex>=0?root.modalAccent(root.actionModalIndex):root.cyan):root.borderSoft; Text{anchors.centerIn:parent;text:modelData;color:root.textPrimary;font.pixelSize: root.textBoost *14*root.uiScale;font.bold:true} MouseArea{anchors.fill:parent;onClicked:{root.actionModalSelection=index;if(index===0)root.executeActionModal();else root.closeActionModal()}} } }
                        }
                    }

                    Column {
                        visible: root.actionModalIndex===4
                        anchors.fill:parent; spacing:8*root.uiScale
                        Text { width:parent.width; text:String(root.quarantineRows().length)+" QUARANTINED ITEM"+(root.quarantineRows().length===1?"":"S"); color:root.purple; font.pixelSize: root.textBoost *14*root.uiScale; font.bold:true }
                        ListView {
                            id: quarantineList
                            width:parent.width; height:parent.height-40*root.uiScale; clip:true; spacing:7*root.uiScale
                            model:root.quarantineRows(); currentIndex:root.actionModalSelection
                            delegate:Rectangle {
                                required property int index; required property var modelData
                                width:quarantineList.width; height:72*root.uiScale; radius:12*root.uiScale
                                color:index===root.actionModalSelection?"#14283A":"#091725"; border.width:index===root.actionModalSelection?2:1; border.color:index===root.actionModalSelection?root.purple:root.borderSoft
                                Column { anchors.left:parent.left; anchors.right:parent.right; anchors.leftMargin:14*root.uiScale; anchors.rightMargin:14*root.uiScale; anchors.verticalCenter:parent.verticalCenter; spacing:3*root.uiScale
                                    Text { width:parent.width; text:String(modelData.name||modelData.path||modelData.file||modelData.id||"Quarantined item"); color:root.textPrimary; font.pixelSize: root.textBoost *14*root.uiScale; font.bold:true; elide:Text.ElideMiddle }
                                    Text { width:parent.width; text:String(modelData.reason||modelData.detail||modelData.status||"Contained by Security Core"); color:root.textMuted; font.pixelSize: root.textBoost *11.5*root.uiScale; elide:Text.ElideRight }
                                }
                                MouseArea { anchors.fill:parent; onClicked:{root.actionModalSelection=index;root.detailsRequested("security",{incident:modelData})} }
                            }
                            Text { anchors.centerIn:parent; visible:quarantineList.count===0; text:"QUARANTINE IS CLEAR"; color:root.green; font.pixelSize: root.textBoost *19*root.uiScale; font.bold:true }
                        }
                    }
                }
                Text { width:parent.width; text:root.actionModalIndex===4?"D-PAD  REVIEW    X  DETAILS    O  CLOSE":"LEFT/RIGHT  CHOOSE    X  CONFIRM    O  CLOSE"; color:root.red; font.pixelSize: root.textBoost *12*root.uiScale; font.bold:true; horizontalAlignment:Text.AlignHCenter }
            }
        }

        Rectangle {
            id: reviewModal
            visible: root.reviewModalOpen
            width: Math.min(parent.width*0.86, 1320*root.uiScale)
            height: Math.min(parent.height*0.82, 720*root.uiScale)
            anchors.centerIn: parent
            radius: 24*root.uiScale
            color: "#FA07131F"
            border.width: 1.5
            border.color: root.red

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 5 * root.uiScale
                radius: height / 2
                color: root.red
            }

            Column {
                anchors.fill:parent; anchors.margins:24*root.uiScale; spacing:12*root.uiScale
                Row {
                    width:parent.width; height:45*root.uiScale; spacing:12*root.uiScale
                    Text { anchors.verticalCenter:parent.verticalCenter; text:"LOGS & REPORT"; color:root.red; font.pixelSize: root.textBoost *Math.max(25,28*root.uiScale); font.bold:true }
                    Item { width:parent.width-520*root.uiScale; height:1 }
                    Text { anchors.verticalCenter:parent.verticalCenter; text:"SCORE  "+String(root.securityScore())+" / 100"; color:root.scoreColor(); font.pixelSize: root.textBoost *17*root.uiScale; font.bold:true }
                }
                Row {
                    width:parent.width; height:42*root.uiScale; spacing:10*root.uiScale
                    Repeater {
                        model:[
                            {t:"NOTIFICATIONS",n:root.securityNotificationCount()},
                            {t:"INTEGRITY CHANGES",n:root.integrityChangeCount()},
                            {t:"ACTIVITY",n:root.allActivityModel().length}
                        ]
                        delegate:Rectangle {
                            required property int index; required property var modelData
                            width:205*root.uiScale; height:38*root.uiScale; radius:10*root.uiScale
                            color:root.reviewTab===index?"#2A1219":"#091725"; border.width:root.reviewTab===index?2:1; border.color:root.reviewTab===index?root.red:root.borderSoft
                            Text { anchors.centerIn:parent; text:modelData.t+"  "+String(modelData.n); color:root.reviewTab===index?root.textPrimary:root.textSecondary; font.pixelSize: root.textBoost *12.5*root.uiScale; font.bold:true }
                            MouseArea { anchors.fill:parent; onClicked:{root.reviewTab=index;root.reviewIndex=0;root.reviewBaselineArmed=false} }
                        }
                    }
                }
                Rectangle { width:parent.width; height:1; color:root.borderSoft }

                ListView {
                    id: reviewList
                    width:parent.width; height:parent.height-190*root.uiScale; clip:true; spacing:8*root.uiScale
                    model:root.reviewRows(); currentIndex:root.reviewIndex
                    delegate:Rectangle {
                        required property int index; required property var modelData
                        width:reviewList.width; height:92*root.uiScale; radius:13*root.uiScale
                        color:index===root.reviewIndex?"#11283B":"#081622"; border.width:index===root.reviewIndex?2:1
                        border.color:root.reviewFlagged(modelData)?"#FFD84A":(index===root.reviewIndex?root.red:root.borderSoft)
                        Rectangle { anchors.left:parent.left; anchors.leftMargin:8*root.uiScale; anchors.verticalCenter:parent.verticalCenter; width:5*root.uiScale; height:parent.height-20*root.uiScale; radius:3*root.uiScale; color:modelData.kind==="integrity"?root.orange:(modelData.kind==="activity"?(root.reviewPayload(modelData).ok?root.green:root.orange):root.severityColor(root.reviewPayload(modelData))) }
                        Column { anchors.left:parent.left; anchors.leftMargin:24*root.uiScale; anchors.right:statusColumn.left; anchors.rightMargin:16*root.uiScale; anchors.verticalCenter:parent.verticalCenter; spacing:5*root.uiScale
                            Row { spacing:8*root.uiScale
                                Text { text:modelData.kind==="integrity"?"INTEGRITY":(modelData.kind==="activity"?"SECURITY ACTIVITY":(modelData.kind==="notification"?"SECURITY NOTIFICATION":"SECURITY EVENT")); color:modelData.kind==="integrity"?root.orange:(modelData.kind==="activity"?root.green:root.blue); font.pixelSize: root.textBoost *Math.max(11.5,10.5*root.uiScale); font.bold:true }
                                Text { visible:root.reviewFlagged(modelData); text:"FLAGGED"; color:"#FFD84A"; font.pixelSize: root.textBoost *Math.max(11.5,10.5*root.uiScale); font.bold:true }
                            }
                            Text { width:parent.width; text:root.reviewTitle(modelData); color:root.textPrimary; font.pixelSize: root.textBoost *15*root.uiScale; font.bold:true; elide:Text.ElideMiddle }
                            Text { width:parent.width; text:root.reviewDetail(modelData); color:root.textMuted; font.pixelSize: root.textBoost *11.5*root.uiScale; elide:Text.ElideRight }
                        }
                        Column { id:statusColumn; anchors.right:parent.right; anchors.rightMargin:15*root.uiScale; anchors.verticalCenter:parent.verticalCenter; width:150*root.uiScale; spacing:6*root.uiScale
                            Text { width:parent.width; text:modelData.kind==="integrity"?"BASELINE REVIEW":(modelData.kind==="activity"?"ACTIVITY RECORD":root.severityLabel(root.reviewPayload(modelData)).toUpperCase()); color:modelData.kind==="integrity"?root.orange:(modelData.kind==="activity"?root.green:root.severityColor(root.reviewPayload(modelData))); font.pixelSize: root.textBoost *Math.max(11.5,10.5*root.uiScale); font.bold:true; horizontalAlignment:Text.AlignRight }
                            Text { visible:modelData.kind!=="activity"; width:parent.width; text:"□  FLAG / UNFLAG"; color:"#FFD84A"; font.pixelSize: root.textBoost *Math.max(11.2,10*root.uiScale); font.bold:true; horizontalAlignment:Text.AlignRight }
                            Text { width:parent.width; text:modelData.kind==="integrity"?(root.reviewBaselineArmed&&index===root.reviewIndex?"X AGAIN • APPROVE":"X  APPROVE BASELINE"):(modelData.kind==="activity"?"X  DETAILS":"X  APPROVE"); color:root.green; font.pixelSize: root.textBoost *Math.max(11.2,10*root.uiScale); font.bold:true; horizontalAlignment:Text.AlignRight }
                        }
                        MouseArea { anchors.fill:parent; onClicked:root.reviewIndex=index }
                    }
                    Text { anchors.centerIn:parent; visible:reviewList.count===0; text:root.reviewTab===0?"NO UNACKNOWLEDGED SECURITY NOTIFICATIONS":(root.reviewTab===1?"NO UNAPPROVED INTEGRITY CHANGES":"NO RECENT SECURITY ACTIVITY"); color:root.green; font.pixelSize: root.textBoost *18*root.uiScale; font.bold:true }
                }

                Rectangle {
                    visible: root.reviewTab===1 && root.reviewBaselineArmed
                    width:parent.width; height:42*root.uiScale; radius:10*root.uiScale; color:"#2B230C"; border.width:1; border.color:"#FFD84A"
                    Text { anchors.centerIn:parent; text:"CONFIRM BASELINE REPLACEMENT: X AGAIN approves the CURRENT filesystem state for ALL listed integrity changes."; color:"#FFE77A"; font.pixelSize: root.textBoost *11.5*root.uiScale; font.bold:true }
                }
                Text { width:parent.width; text:root.reviewTab===2?"LEFT/RIGHT  SWITCH LIST    D-PAD  REVIEW    X  DETAILS    O  CLOSE":"LEFT/RIGHT  SWITCH LIST    D-PAD  REVIEW    □  FLAG    X  APPROVE    O  CLOSE"; color:root.red; font.pixelSize: root.textBoost *12*root.uiScale; font.bold:true; horizontalAlignment:Text.AlignHCenter }
            }
        }

        Rectangle {
            id: protectionModal
            visible: root.protectionModalOpen
            z: 30
            width: Math.min(parent.width * 0.84, 1240 * root.uiScale)
            height: Math.min(parent.height * 0.82, 700 * root.uiScale)
            anchors.centerIn: parent
            radius: 24 * root.uiScale
            color: "#FB07131F"
            border.width: 1.5
            border.color: root.blue

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 5 * root.uiScale
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.blue }
                    GradientStop { position: 0.62; color: root.cyan }
                    GradientStop { position: 1.0; color: root.red }
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 24 * root.uiScale
                spacing: 13 * root.uiScale

                Row {
                    width: parent.width
                    height: 54 * root.uiScale

                    Column {
                        width: parent.width - 230 * root.uiScale
                        spacing: 3 * root.uiScale
                        Text {
                            text: "ACTIVE PROTECTIONS"
                            color: root.textPrimary
                            font.pixelSize: root.textBoost * Math.max(25, 27 * root.uiScale)
                            font.bold: true
                        }
                        Text {
                            text: "Live Security Core protection controls • " + String(root.protectionEnabledCount()) + " of " + String(root.protectionTotalCount()) + " currently active"
                            color: root.textMuted
                            font.pixelSize: root.textBoost * Math.max(11.5, 10.8 * root.uiScale)
                        }
                    }

                    Rectangle {
                        width: 210 * root.uiScale
                        height: 50 * root.uiScale
                        radius: 13 * root.uiScale
                        color: "#0B1A28"
                        border.width: 1
                        border.color: root.protectionPercent() >= 80 ? "#5572F05B" : (root.protectionPercent() <= 50 ? "#55FF3F4E" : "#55FFD84A")
                        Column {
                            anchors.centerIn: parent
                            spacing: 1 * root.uiScale
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String(Math.round(root.protectionPercent())) + "% PROTECTED"
                                color: root.protectionPercent() >= 80 ? root.green : (root.protectionPercent() <= 50 ? root.red : root.yellow)
                                font.pixelSize: root.textBoost * 15 * root.uiScale
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String(root.protectionEnabledCount()) + " / " + String(root.protectionTotalCount()) + " ACTIVE"
                                color: root.textMuted
                                font.pixelSize: root.textBoost * 10.5 * root.uiScale
                                font.bold: true
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 12 * root.uiScale
                    radius: height / 2
                    color: "#081522"
                    border.width: 1
                    border.color: root.borderSoft
                    clip: true
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * (root.protectionPercent() / 100.0)
                        radius: parent.radius
                        color: root.protectionPercent() >= 80 ? root.green : (root.protectionPercent() <= 50 ? root.red : root.yellow)
                        Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                    }
                }

                Grid {
                    id: protectionGrid
                    width: parent.width
                    height: parent.height - 150 * root.uiScale
                    columns: 2
                    rows: 7
                    columnSpacing: 12 * root.uiScale
                    rowSpacing: 9 * root.uiScale

                    Repeater {
                        model: root.activeProtectionRows()

                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: (protectionGrid.width - 12 * root.uiScale) / 2
                            height: (protectionGrid.height - 54 * root.uiScale) / 7
                            radius: 13 * root.uiScale
                            color: index === root.protectionModalSelection ? "#112A3E" : "#091725"
                            border.width: index === root.protectionModalSelection ? 2 : 1
                            border.color: index === root.protectionModalSelection ? root.blue : root.borderSoft

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.uiScale
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7 * root.uiScale
                                height: parent.height - 20 * root.uiScale
                                radius: width / 2
                                color: modelData.on ? root.green : root.red
                                opacity: 0.88
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 28 * root.uiScale
                                anchors.right: protectionSwitch.left
                                anchors.rightMargin: 13 * root.uiScale
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3 * root.uiScale
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: root.textPrimary
                                    font.pixelSize: root.textBoost * Math.max(13, 12 * root.uiScale)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.group + "  •  " + root.protectionControlText(modelData)
                                    color: modelData.on ? root.green : (modelData.control === "recovery" ? root.yellow : root.textMuted)
                                    font.pixelSize: root.textBoost * Math.max(10.5, 9.7 * root.uiScale)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                id: protectionSwitch
                                anchors.right: parent.right
                                anchors.rightMargin: 14 * root.uiScale
                                anchors.verticalCenter: parent.verticalCenter
                                width: 56 * root.uiScale
                                height: 29 * root.uiScale
                                radius: height / 2
                                color: modelData.on ? "#193E2B" : "#32131A"
                                border.width: 1.3
                                border.color: modelData.on ? root.green : root.red
                                opacity: modelData.control === "core" || modelData.control === "link" ? 0.72 : 1.0

                                Rectangle {
                                    width: 21 * root.uiScale
                                    height: width
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: modelData.on
                                       ? parent.width - width - 4 * root.uiScale
                                       : 4 * root.uiScale
                                    color: modelData.on ? root.green : root.red
                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: modelData.control === "core" || modelData.control === "link"
                                    text: ""
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.protectionModalSelection = index
                                onClicked: {
                                    root.protectionModalSelection = index
                                    root.toggleProtectionAt(index)
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "D-PAD  SELECT    X  TOGGLE / DETAILS    O  CLOSE    •    CORE-MANAGED CONTROLS CANNOT BE FAKED OFF"
                    color: root.textMuted
                    font.pixelSize: root.textBoost * Math.max(10.7, 9.8 * root.uiScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Rectangle {
            id: protectionErrorModal
            visible: root.protectionErrorOpen
            z: 60
            width: Math.min(parent.width * 0.58, 760 * root.uiScale)
            height: Math.min(parent.height * 0.38, 330 * root.uiScale)
            anchors.centerIn: parent
            radius: 22 * root.uiScale
            color: "#FD0A131E"
            border.width: 1.5
            border.color: root.red

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 5 * root.uiScale
                radius: height / 2
                color: root.red
            }

            Column {
                anchors.fill: parent
                anchors.margins: 28 * root.uiScale
                spacing: 15 * root.uiScale

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 58 * root.uiScale
                    height: width
                    radius: width / 2
                    color: "#35141B"
                    border.width: 1.5
                    border.color: root.red
                    Text {
                        anchors.centerIn: parent
                        text: "!"
                        color: root.red
                        font.pixelSize: root.textBoost * 28 * root.uiScale
                        font.bold: true
                    }
                }

                Text {
                    width: parent.width
                    text: root.protectionErrorTitle
                    color: root.textPrimary
                    font.pixelSize: root.textBoost * Math.max(22, 24 * root.uiScale)
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width
                    text: root.protectionErrorMessage
                    color: root.textSecondary
                    font.pixelSize: root.textBoost * Math.max(12.2, 11.5 * root.uiScale)
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 190 * root.uiScale
                    height: 48 * root.uiScale
                    radius: 13 * root.uiScale
                    color: "#28141A"
                    border.width: 1.5
                    border.color: root.red
                    Text {
                        anchors.centerIn: parent
                        text: "CLOSE"
                        color: root.textPrimary
                        font.pixelSize: root.textBoost * 13.5 * root.uiScale
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.protectionErrorOpen = false
                    }
                }
            }
        }

    }

    Component.onCompleted: {
        animatedScore = securityScore()
        primeHistory()
        loadCachedLocation()
        initialLocationTimer.restart()
    }
}
