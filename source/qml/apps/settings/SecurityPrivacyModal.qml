import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root

    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 220

    property bool visibleMode: false
    property string mode: "profiles"
    property var coreBackend: null

    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color panelInset: "#06101F"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#A8C2DE"
    property color textMuted: "#7895B5"
    property color divider: "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color success: "#16C784"
    property color warning: "#F5B942"
    property color danger: "#FF4055"
    property color purple: "#A855F7"

    property int profileIndex: 0
    property int timelineIndex: 0
    property int appIndex: 0
    property int permissionIndex: 0
    property int permissionPane: 0
    property bool profileArmed: false
    property string localStatus: ""
    property bool localStatusError: false

    signal closeRequested()
    signal statusChanged(string message, bool error)
    signal openSecurityAppRequested()

    function normalizeAction(action) {
        var value = String(action || "").trim().toLowerCase().replace(/-/g, "_")
        if (value === "x" || value === "cross" || value === "primary" || value === "accept") return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back") return "cancel"
        if (value === "triangle" || value === "context") return "context"
        if (value === "square" || value === "secondary") return "secondary"
        if (value === "l2") return "page_up"
        if (value === "r2") return "page_down"
        return value
    }

    function profileList() {
        return coreBackend && coreBackend.securityProfiles ? coreBackend.securityProfiles : []
    }

    function timelineList() {
        return coreBackend && coreBackend.securityTimeline ? coreBackend.securityTimeline : []
    }

    function appList() {
        return coreBackend && coreBackend.appPermissions ? coreBackend.appPermissions : []
    }

    function currentProfile() {
        var list = profileList()
        return list.length > 0 && profileIndex >= 0 && profileIndex < list.length ? list[profileIndex] : ({})
    }

    function currentEvent() {
        var list = timelineList()
        return list.length > 0 && timelineIndex >= 0 && timelineIndex < list.length ? list[timelineIndex] : ({})
    }

    function currentApp() {
        var list = appList()
        return list.length > 0 && appIndex >= 0 && appIndex < list.length ? list[appIndex] : ({})
    }

    function currentPermission() {
        var app = currentApp()
        var list = app && app.permissions ? app.permissions : []
        return list.length > 0 && permissionIndex >= 0 && permissionIndex < list.length ? list[permissionIndex] : ({})
    }

    function humanAppName(value) {
        var text = String(value || "App").replace(/[-_]+/g, " ")
        var words = text.split(" ")
        for (var i = 0; i < words.length; ++i) {
            if (words[i].length > 0)
                words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
        }
        return words.join(" ")
    }

    function profileDescription(name) {
        var n = String(name || "NORMAL").toUpperCase()
        if (n === "NORMAL") return "Balanced everyday protection with normal local access and standard monitoring."
        if (n === "TRAVEL") return "Hardens NeutronOS for untrusted networks while keeping normal apps and local workflows available."
        if (n === "OFFLINE") return "Restricts network access for disconnected or local-only operation while keeping local services usable."
        if (n === "RESTRICTED") return "Constrains app and network access. Use when you want a smaller attack surface without full lockdown."
        if (n === "LOCKDOWN") return "Allows only essential services and sharply reduces optional access. Intended for elevated-risk situations."
        if (n === "MAXIMUM") return "Highest defensive posture. MAXIMUM is intentionally armed through the Security app's DEFCON double-confirmation flow."
        return "NeutronOS security profile managed by the Security Core."
    }

    function profileColor(name) {
        var n = String(name || "NORMAL").toUpperCase()
        if (n === "MAXIMUM" || n === "LOCKDOWN") return danger
        if (n === "RESTRICTED") return warning
        if (n === "TRAVEL" || n === "OFFLINE") return focusBlue
        return success
    }

    function severityLabel(value) {
        var level = Number(value || 1)
        if (level >= 5) return "CRITICAL"
        if (level >= 4) return "HIGH"
        if (level >= 3) return "MEDIUM"
        if (level >= 2) return "NOTICE"
        return "INFO"
    }

    function severityColor(value) {
        var level = Number(value || 1)
        if (level >= 4) return danger
        if (level === 3) return warning
        if (level === 2) return purple
        return focusBlue
    }

    function eventEvidence(eventData) {
        var evidence = eventData && eventData.evidence ? eventData.evidence : ({})
        var keys = [
            ["message", "Message"], ["summary", "Summary"], ["reason", "Reason"],
            ["result", "Result"], ["action", "Action"], ["status", "Status"],
            ["appId", "App"], ["username", "User"], ["user", "User"],
            ["service", "Service"], ["unit", "Unit"], ["address", "Address"],
            ["device", "Device"], ["path", "Path"], ["source", "Source"]
        ]
        var lines = []
        var seen = ({})
        for (var i = 0; i < keys.length; ++i) {
            var key = keys[i][0]
            var label = keys[i][1]
            var value = evidence ? evidence[key] : undefined
            if (value === undefined || value === null || typeof value === "object")
                continue
            var text = String(value).trim()
            if (text.length === 0 || seen[label + text])
                continue
            seen[label + text] = true
            lines.push(label + ": " + text)
            if (lines.length >= 7)
                break
        }
        if (lines.length === 0)
            return "This event was recorded by the NeutronOS Security Core. No additional human-readable evidence was attached."
        return lines.join("\n")
    }

    function permissionDescription(name) {
        var n = String(name || "")
        if (n === "Network") return "Access internet-facing network connections."
        if (n === "Media") return "Read or manage media-library content."
        if (n === "Documents") return "Read or manage user document locations."
        if (n === "Removable Storage") return "Access mounted USB and removable drives."
        if (n === "Microphone") return "Use an attached microphone or audio-capture device."
        if (n === "Bluetooth") return "Discover or communicate with Bluetooth devices."
        if (n === "Local Network") return "Communicate with devices and services on the local network."
        if (n === "System Telemetry") return "Read system health and performance information."
        if (n === "Notifications") return "Post notifications through NeutronOS."
        if (n === "Background Execution") return "Continue approved work while the app is not visible."
        if (n === "Privileged Operations") return "Protected system operations. These require approved scopes and cannot be granted from this screen."
        return "Application capability controlled by NeutronOS policy."
    }

    function permissionColor(state) {
        var s = String(state || "Denied")
        if (s.indexOf("Allowed") === 0) return success
        if (s.indexOf("Ask") === 0) return warning
        return danger
    }

    function setStatus(message, error) {
        localStatus = String(message || "")
        localStatusError = error === true
        statusChanged(localStatus, localStatusError)
    }

    function openBase(nextMode) {
        mode = nextMode
        profileArmed = false
        localStatus = ""
        localStatusError = false
        permissionPane = 0
        visibleMode = true
        forceActiveFocus()
    }

    function openProfiles() {
        openBase("profiles")
        var active = coreBackend ? String(coreBackend.activeSecurityProfile || "NORMAL") : "NORMAL"
        var list = profileList()
        profileIndex = 0
        for (var i = 0; i < list.length; ++i) {
            if (String(list[i].name || "").toUpperCase() === active.toUpperCase()) {
                profileIndex = i
                break
            }
        }
        Qt.callLater(function() { if (profileListView) profileListView.positionViewAtIndex(profileIndex, ListView.Contain) })
    }

    function openTimeline() {
        openBase("timeline")
        timelineIndex = 0
        Qt.callLater(function() { if (timelineListView) timelineListView.positionViewAtBeginning() })
    }

    function openPermissions() {
        openBase("permissions")
        appIndex = 0
        permissionIndex = 0
        Qt.callLater(function() {
            if (appListView) appListView.positionViewAtBeginning()
            if (permissionListView) permissionListView.positionViewAtBeginning()
        })
    }

    function closeModal() {
        if (!visibleMode)
            return
        visibleMode = false
        profileArmed = false
        closeRequested()
    }

    function applySelectedProfile() {
        var profile = currentProfile()
        var name = String(profile.name || "NORMAL").toUpperCase()
        if (!coreBackend) {
            setStatus("Security Core is unavailable.", true)
            return
        }
        if (name === "MAXIMUM") {
            setStatus("MAXIMUM uses the Security app's protected DEFCON double-confirmation flow.", false)
            openSecurityAppRequested()
            return
        }
        var restrictive = name === "RESTRICTED" || name === "LOCKDOWN"
        if (restrictive && !profileArmed) {
            profileArmed = true
            setStatus("Press X again to confirm the " + name + " security profile.", true)
            return
        }
        var ok = coreBackend.applySecurityProfile(name, restrictive)
        profileArmed = false
        setStatus(ok ? name + " security profile applied." : String(coreBackend.lastMessage || "Security profile could not be applied."), !ok)
    }

    function cyclePermission() {
        var app = currentApp()
        var permission = currentPermission()
        if (!coreBackend || !app || !permission)
            return
        var permissionName = String(permission.name || "")
        if (permissionName === "Privileged Operations") {
            setStatus("Privileged Operations are scope-controlled by NeutronOS security policy and cannot be enabled here.", true)
            return
        }
        var state = String(permission.state || "Denied")
        var next = state.indexOf("Denied") === 0 ? "Ask / Conditional"
                 : state.indexOf("Ask") === 0 ? "Allowed"
                 : "Denied"
        var ok = coreBackend.setAppPermission(String(app.appId || ""), permissionName, next)
        setStatus(ok ? permissionName + " set to " + next + " for " + humanAppName(app.name || app.appId) + "."
                     : String(coreBackend.lastMessage || "Permission change was rejected."), !ok)
    }

    function moveProfile(delta) {
        var count = profileList().length
        if (count <= 0) return
        profileArmed = false
        profileIndex = Math.max(0, Math.min(count - 1, profileIndex + delta))
        profileListView.positionViewAtIndex(profileIndex, ListView.Contain)
    }

    function moveTimeline(delta) {
        var count = timelineList().length
        if (count <= 0) return
        timelineIndex = Math.max(0, Math.min(count - 1, timelineIndex + delta))
        timelineListView.positionViewAtIndex(timelineIndex, ListView.Contain)
    }

    function moveApp(delta) {
        var count = appList().length
        if (count <= 0) return
        appIndex = Math.max(0, Math.min(count - 1, appIndex + delta))
        permissionIndex = 0
        appListView.positionViewAtIndex(appIndex, ListView.Contain)
        permissionListView.positionViewAtBeginning()
    }

    function movePermission(delta) {
        var app = currentApp()
        var count = app && app.permissions ? app.permissions.length : 0
        if (count <= 0) return
        permissionIndex = Math.max(0, Math.min(count - 1, permissionIndex + delta))
        permissionListView.positionViewAtIndex(permissionIndex, ListView.Contain)
    }

    function handleControllerPressed(action) {
        var value = normalizeAction(action)
        if (!visibleMode)
            return false
        if (value === "cancel" || value === "system") {
            closeModal()
            return true
        }
        if (value === "context") {
            if (coreBackend) {
                coreBackend.refresh()
                setStatus("Security information refreshed from local authoritative sources.", false)
            }
            return true
        }

        if (mode === "profiles") {
            if (value === "up") moveProfile(-1)
            else if (value === "down") moveProfile(1)
            else if (value === "primary") applySelectedProfile()
            return true
        }

        if (mode === "timeline") {
            if (value === "up") moveTimeline(-1)
            else if (value === "down") moveTimeline(1)
            else if (value === "page_up") moveTimeline(-5)
            else if (value === "page_down") moveTimeline(5)
            return true
        }

        if (mode === "permissions") {
            if (value === "left") permissionPane = 0
            else if (value === "right") permissionPane = 1
            else if (value === "up") permissionPane === 0 ? moveApp(-1) : movePermission(-1)
            else if (value === "down") permissionPane === 0 ? moveApp(1) : movePermission(1)
            else if (value === "primary") {
                if (permissionPane === 0) permissionPane = 1
                else cyclePermission()
            }
            return true
        }
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visibleMode }

    Rectangle {
        anchors.fill: parent
        color: "#B8000000"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 100, 1480)
        height: Math.min(parent.height - 70, 900)
        radius: 30
        color: root.panelColor
        border.width: 2
        border.color: root.mode === "profiles" ? root.success : root.focusBlue
        clip: true

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 104
            color: root.panelRaised

            Row {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 18

                Rectangle {
                    width: 58
                    height: 58
                    radius: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.mode === "profiles" ? "#123D36" : "#102943"
                    border.width: 1
                    border.color: root.mode === "profiles" ? root.success : root.focusBlue
                    Text {
                        anchors.centerIn: parent
                        text: root.mode === "profiles" ? "◆" : root.mode === "timeline" ? "◈" : "▦"
                        color: root.mode === "profiles" ? root.success : root.focusBlue
                        font.pixelSize: 27
                        font.bold: true
                    }
                }

                Column {
                    width: parent.width - 330
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        width: parent.width
                        text: root.mode === "profiles" ? "SECURITY PROFILES"
                              : root.mode === "timeline" ? "SECURITY TIMELINE"
                              : "APP PERMISSIONS"
                        color: root.textPrimary
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: root.mode === "profiles" ? "Choose the defensive posture NeutronOS should enforce."
                              : root.mode === "timeline" ? "Human-readable events reported by the NeutronOS Security Core."
                              : "Review and change ordinary app capabilities without exposing raw policy data."
                        color: root.textSecondary
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 205
                    height: 44
                    radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.mode === "profiles" ? "#123D36" : root.panelInset
                    border.width: 1
                    border.color: root.mode === "profiles" ? root.success : root.divider
                    Text {
                        anchors.centerIn: parent
                        text: root.mode === "profiles"
                              ? "ACTIVE  •  " + String(root.coreBackend ? root.coreBackend.activeSecurityProfile || "NORMAL" : "UNAVAILABLE")
                              : root.mode === "timeline"
                                ? String(root.timelineList().length) + " EVENTS"
                                : String(root.appList().length) + " APPS"
                        color: root.mode === "profiles" ? root.success : root.textSecondary
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }

        Item {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.margins: 20

            Row {
                anchors.fill: parent
                spacing: 16
                visible: root.mode === "profiles"

                Rectangle {
                    width: parent.width * 0.58
                    height: parent.height
                    radius: 20
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider

                    ListView {
                        id: profileListView
                        anchors.fill: parent
                        anchors.margins: 12
                        model: root.profileList()
                        spacing: 8
                        clip: true
                        currentIndex: root.profileIndex
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: profileRow
                            width: profileListView.width
                            height: 84
                            radius: 16
                            property var profileData: modelData || ({})
                            property bool chosen: index === root.profileIndex
                            property bool activeProfile: String(profileData.name || "").toUpperCase() === String(root.coreBackend ? root.coreBackend.activeSecurityProfile || "" : "").toUpperCase()
                            color: chosen ? "#17365D" : root.panelRaised
                            border.width: chosen ? 2 : 1
                            border.color: chosen ? root.focusBlue : activeProfile ? root.success : root.divider

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                Rectangle {
                                    width: 7
                                    height: parent.height
                                    radius: 4
                                    color: root.profileColor(profileRow.profileData.name)
                                }
                                Column {
                                    width: parent.width - 170
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Row {
                                        spacing: 9
                                        Text { text: String(profileRow.profileData.name || "Profile"); color: root.textPrimary; font.pixelSize: 17; font.bold: true }
                                        Text { visible: profileRow.activeProfile; text: "ACTIVE"; color: root.success; font.pixelSize: 10; font.bold: true }
                                    }
                                    Text {
                                        width: parent.width
                                        text: String(profileRow.profileData.impact || root.profileDescription(profileRow.profileData.name))
                                        color: root.textMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                Rectangle {
                                    width: 120
                                    height: 38
                                    radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.profileColor(profileRow.profileData.name)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "DEFCON " + String(profileRow.profileData.defcon || "—")
                                        color: root.profileColor(profileRow.profileData.name)
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.profileIndex = index
                                    root.profileArmed = false
                                }
                                onDoubleClicked: {
                                    root.profileIndex = index
                                    root.applySelectedProfile()
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }

                Rectangle {
                    width: parent.width * 0.42 - 16
                    height: parent.height
                    radius: 20
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 14
                        Text { text: "SELECTED PROFILE"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                        Text { width: parent.width; text: String(root.currentProfile().name || "No profile"); color: root.textPrimary; font.pixelSize: 30; font.bold: true }
                        Rectangle {
                            width: 108
                            height: 108
                            radius: 54
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: "transparent"
                            border.width: 6
                            border.color: root.profileColor(root.currentProfile().name)
                            Text {
                                anchors.centerIn: parent
                                text: String(root.currentProfile().defcon || "—")
                                color: root.profileColor(root.currentProfile().name)
                                font.pixelSize: 42
                                font.bold: true
                            }
                        }
                        Text { width: parent.width; text: "DEFCON LEVEL"; color: root.textMuted; font.pixelSize: 11; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                        Text {
                            width: parent.width
                            height: 118
                            text: root.profileDescription(root.currentProfile().name)
                            color: root.textSecondary
                            font.pixelSize: 14
                            lineHeight: 1.22
                            wrapMode: Text.WordWrap
                        }
                        Rectangle { width: parent.width; height: 1; color: root.divider }
                        Text {
                            width: parent.width
                            text: "Impact: " + String(root.currentProfile().impact || "Security Core managed protection")
                            color: root.textPrimary
                            font.pixelSize: 13
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                        Item { width: 1; height: Math.max(0, parent.height - 430) }
                        Rectangle {
                            width: parent.width
                            height: 56
                            radius: 17
                            color: String(root.currentProfile().name || "").toUpperCase() === "MAXIMUM" ? root.danger : root.success
                            Text {
                                anchors.centerIn: parent
                                text: String(root.currentProfile().name || "").toUpperCase() === "MAXIMUM"
                                      ? "OPEN SECURITY • ARM MAXIMUM"
                                      : root.profileArmed ? "PRESS X AGAIN TO CONFIRM" : "APPLY PROFILE"
                                color: "#04110B"
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.applySelectedProfile() }
                        }
                    }
                }
            }

            Row {
                anchors.fill: parent
                spacing: 16
                visible: root.mode === "timeline"

                Rectangle {
                    width: parent.width * 0.56
                    height: parent.height
                    radius: 20
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider

                    ListView {
                        id: timelineListView
                        anchors.fill: parent
                        anchors.margins: 12
                        model: root.timelineList()
                        spacing: 8
                        clip: true
                        currentIndex: root.timelineIndex
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: eventRow
                            width: timelineListView.width
                            height: 82
                            radius: 15
                            property var eventData: modelData || ({})
                            property bool chosen: index === root.timelineIndex
                            color: chosen ? "#17365D" : root.panelRaised
                            border.width: chosen ? 2 : 1
                            border.color: chosen ? root.focusBlue : root.divider
                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                Rectangle { width: 7; height: parent.height; radius: 4; color: root.severityColor(eventRow.eventData.severity) }
                                Column {
                                    width: parent.width - 166
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Text { width: parent.width; text: String(eventRow.eventData.title || "Security event"); color: root.textPrimary; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: String(eventRow.eventData.category || "System") + "  •  " + String(eventRow.eventData.timestamp || "Unknown time"); color: root.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                                Rectangle {
                                    width: 116
                                    height: 36
                                    radius: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.severityColor(eventRow.eventData.severity)
                                    Text { anchors.centerIn: parent; text: root.severityLabel(eventRow.eventData.severity); color: root.severityColor(eventRow.eventData.severity); font.pixelSize: 10; font.bold: true }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.timelineIndex = index }
                        }

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }

                Rectangle {
                    width: parent.width * 0.44 - 16
                    height: parent.height
                    radius: 20
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.divider
                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 13
                        Row {
                            width: parent.width
                            height: 40
                            Text { width: parent.width - 150; text: "EVENT DETAILS"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                            Rectangle {
                                width: 145; height: 36; radius: 12; color: "transparent"; border.width: 1; border.color: root.severityColor(root.currentEvent().severity)
                                Text { anchors.centerIn: parent; text: root.severityLabel(root.currentEvent().severity); color: root.severityColor(root.currentEvent().severity); font.pixelSize: 10; font.bold: true }
                            }
                        }
                        Text { width: parent.width; text: String(root.currentEvent().title || "No security event selected"); color: root.textPrimary; font.pixelSize: 24; font.bold: true; wrapMode: Text.WordWrap }
                        Text { width: parent.width; text: String(root.currentEvent().category || "System"); color: root.focusBlue; font.pixelSize: 13; font.bold: true }
                        Text { width: parent.width; text: String(root.currentEvent().timestamp || "Unknown time"); color: root.textMuted; font.pixelSize: 12 }
                        Rectangle { width: parent.width; height: 1; color: root.divider }
                        Text { width: parent.width; text: "WHAT NEUTRONOS RECORDED"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.0 }
                        Text {
                            width: parent.width
                            height: parent.height - 200
                            text: root.eventEvidence(root.currentEvent())
                            color: root.textSecondary
                            font.pixelSize: 14
                            lineHeight: 1.28
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignTop
                        }
                    }
                }
            }

            Row {
                anchors.fill: parent
                spacing: 16
                visible: root.mode === "permissions"

                Rectangle {
                    width: parent.width * 0.34
                    height: parent.height
                    radius: 20
                    color: root.panelInset
                    border.width: root.permissionPane === 0 ? 2 : 1
                    border.color: root.permissionPane === 0 ? root.focusBlue : root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9
                        Text { width: parent.width; height: 32; text: "APPLICATIONS"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                        ListView {
                            id: appListView
                            width: parent.width
                            height: parent.height - 42
                            model: root.appList()
                            spacing: 7
                            clip: true
                            currentIndex: root.appIndex
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Rectangle {
                                id: appRow
                                width: appListView.width
                                height: 64
                                radius: 14
                                property var appData: modelData || ({})
                                property bool chosen: index === root.appIndex
                                color: chosen ? "#17365D" : root.panelRaised
                                border.width: chosen ? 2 : 1
                                border.color: chosen ? root.focusBlue : root.divider
                                Column {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 13; spacing: 3
                                    Text { width: parent.width; text: root.humanAppName(appRow.appData.name || appRow.appData.appId); color: root.textPrimary; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                                    Text { width: parent.width; text: String(appRow.appData.appId || ""); color: root.textMuted; font.pixelSize: 10; elide: Text.ElideRight }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { root.appIndex = index; root.permissionIndex = 0; root.permissionPane = 0 } }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 0.66 - 16
                    height: parent.height
                    radius: 20
                    color: root.panelRaised
                    border.width: root.permissionPane === 1 ? 2 : 1
                    border.color: root.permissionPane === 1 ? root.focusBlue : root.divider

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9
                        Row {
                            width: parent.width
                            height: 32
                            Text { width: parent.width - 220; text: root.humanAppName(root.currentApp().name || root.currentApp().appId) + " PERMISSIONS"; color: root.textMuted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.0; elide: Text.ElideRight }
                            Text { width: 220; text: "X  CHANGE STATE"; color: root.focusBlue; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight }
                        }
                        ListView {
                            id: permissionListView
                            width: parent.width
                            height: parent.height - 42
                            model: root.currentApp() && root.currentApp().permissions ? root.currentApp().permissions : []
                            spacing: 7
                            clip: true
                            currentIndex: root.permissionIndex
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Rectangle {
                                id: permissionRow
                                width: permissionListView.width
                                height: 70
                                radius: 14
                                property var permissionData: modelData || ({})
                                property bool chosen: index === root.permissionIndex
                                color: chosen ? "#17365D" : root.panelInset
                                border.width: chosen ? 2 : 1
                                border.color: chosen ? root.focusBlue : root.divider
                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12
                                    Column {
                                        width: parent.width - 230
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Text { width: parent.width; text: String(permissionRow.permissionData.name || "Permission"); color: root.textPrimary; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight }
                                        Text { width: parent.width; text: root.permissionDescription(permissionRow.permissionData.name); color: root.textMuted; font.pixelSize: 10; elide: Text.ElideRight }
                                    }
                                    Rectangle {
                                        width: 205
                                        height: 38
                                        radius: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "transparent"
                                        border.width: 1
                                        border.color: root.permissionColor(permissionRow.permissionData.state)
                                        Text { anchors.centerIn: parent; text: String(permissionRow.permissionData.state || "Denied").toUpperCase(); color: root.permissionColor(permissionRow.permissionData.state); font.pixelSize: 10; font.bold: true; elide: Text.ElideRight }
                                    }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { root.permissionIndex = index; root.permissionPane = 1; root.cyclePermission() } }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 66
            color: root.panelRaised
            border.width: 0

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18
                Text {
                    width: parent.width * 0.58
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.localStatus.length > 0
                          ? root.localStatus
                          : root.mode === "profiles" ? "UP / DOWN  SELECT    X  APPLY    △  REFRESH    O  CLOSE"
                          : root.mode === "timeline" ? "UP / DOWN  EVENTS    L2 / R2  PAGE    △  REFRESH    O  CLOSE"
                          : "LEFT / RIGHT  PANE    UP / DOWN  SELECT    X  CHANGE    O  CLOSE"
                    color: root.localStatus.length > 0 ? (root.localStatusError ? root.warning : root.success) : root.textMuted
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width * 0.42 - 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "permissions" ? "PRIVILEGED OPERATIONS REMAIN POLICY-CONTROLLED" : "NEUTRONOS SECURITY CORE"
                    color: root.focusBlue
                    font.pixelSize: 10
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!visibleMode)
            return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) { handleControllerPressed("cancel"); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { handleControllerPressed("primary"); event.accepted = true }
        else if (event.key === Qt.Key_Up) { handleControllerPressed("up"); event.accepted = true }
        else if (event.key === Qt.Key_Down) { handleControllerPressed("down"); event.accepted = true }
        else if (event.key === Qt.Key_Left) { handleControllerPressed("left"); event.accepted = true }
        else if (event.key === Qt.Key_Right) { handleControllerPressed("right"); event.accepted = true }
        else if (event.key === Qt.Key_PageUp) { handleControllerPressed("page_up"); event.accepted = true }
        else if (event.key === Qt.Key_PageDown) { handleControllerPressed("page_down"); event.accepted = true }
        else if (event.key === Qt.Key_F1) { handleControllerPressed("context"); event.accepted = true }
    }
}
