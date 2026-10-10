import QtQuick 2.15
import QtQuick.Controls 2.15
import "../../components" as Shared

Item {
    id: root
    anchors.fill: parent
    focus: true

    property string appId: "logs"
    property string appName: "Logs"
    property var appData: ({})
    property bool developerModeEnabled: false
    property bool hostActive: true
    property var backend: (typeof logsManager !== "undefined") ? logsManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var securityBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null

    signal exitRequested()
    signal backgroundRequested()

    // 0 = source rail, 1 = log viewport, 2 = header menu.
    property int focusZone: 0
    property int selectedIndex: 0
    property string searchText: ""
    property string filterMode: "ALL"
    property string sortMode: "NEUTRONOS_FIRST"
    property var visibleSources: []
    property bool keyboardOpen: false
    property bool exitVisible: false
    property int exitChoice: 0
    property string toastText: ""
    property bool toastError: false

    readonly property var sources: backend && backend.sources ? backend.sources : []
    readonly property bool securityProtected: securityBackend &&
                                                securityBackend.daemonOnline &&
                                                securityBackend.auditValid &&
                                                Number(securityBackend.threatLevel || 5) > 2
    readonly property color bg: "#02060D"
    readonly property color panel: "#07101AEE"
    readonly property color raised: "#0B1B2A"
    readonly property color inset: "#030A11"
    readonly property color border: "#253A4B"
    readonly property color textMain: "#F4FBFF"
    readonly property color textMuted: "#91AEC5"
    readonly property color cyan: "#63E8FF"
    readonly property color blue: "#4C9EFF"
    readonly property color green: "#42E69C"
    readonly property color yellow: "#FFD166"
    readonly property color red: "#FF4D63"
    readonly property color purple: "#B47AFF"

    function normalizeAction(action) {
        var v = String(action || "").toLowerCase().replace(/-/g, "_")
        if (v === "x" || v === "cross" || v === "primary" || v === "enter") return "primary"
        if (v === "o" || v === "circle" || v === "cancel" || v === "back") return "cancel"
        if (v === "triangle" || v === "context") return "context"
        if (v === "square" || v === "secondary") return "secondary"
        if (v === "start" || v === "settings" || v === "options" || v === "system") return "system"
        if (v === "r3" || v === "right_stick_button") return "r3"
        if (v === "l1" || v === "leftshoulder") return "l1"
        if (v === "r1" || v === "rightshoulder") return "r1"
        if (v === "l2" || v === "lefttrigger") return "l2"
        if (v === "r2" || v === "righttrigger") return "r2"
        if (v === "dpad_up" || v === "leftstick_up" || v === "rightstick_up") return "up"
        if (v === "dpad_down" || v === "leftstick_down" || v === "rightstick_down") return "down"
        if (v === "dpad_left" || v === "leftstick_left" || v === "rightstick_left") return "left"
        if (v === "dpad_right" || v === "leftstick_right" || v === "rightstick_right") return "right"
        return v
    }

    function sourceTone(source) {
        if (!source || !source.id) return textMuted
        if (String(source.type || "") === "service" || String(source.type || "") === "docker")
            return source.running ? green : yellow
        if (String(source.type || "") === "file") return cyan
        return purple
    }

    function typeLabel(source) {
        var type = String(source && source.type ? source.type : "source").toLowerCase()
        if (type === "service") return "SYSTEMD"
        if (type === "docker") return "CONTAINER"
        if (type === "file") return "LOG FILE"
        if (type === "script") return "SCRIPT"
        return type.toUpperCase()
    }

    function filterLabel() {
        if (filterMode === "ACTIVE") return "ACTIVE"
        if (filterMode === "INACTIVE") return "INACTIVE"
        if (filterMode === "SYSTEMD") return "SYSTEMD"
        if (filterMode === "DOCKER") return "DOCKER"
        if (filterMode === "FILES") return "FILES"
        return "ALL"
    }

    function sortLabel() {
        if (sortMode === "ALPHA") return "A–Z"
        if (sortMode === "ACTIVE") return "ACTIVE FIRST"
        if (sortMode === "TYPE") return "TYPE"
        return "NEUTRONOS FIRST"
    }

    function cycleSort() {
        var modes = ["NEUTRONOS_FIRST", "ALPHA", "ACTIVE", "TYPE"]
        var index = modes.indexOf(sortMode)
        sortMode = modes[(index + 1) % modes.length]
        rebuildVisibleSources()
        toastText = "Log source sort: " + sortLabel()
        toastError = false
        toastTimer.restart()
    }

    function sourceGroupRank(source) {
        if (!source) return 3
        if (String(source.type || "").toLowerCase() !== "service") return 3
        var origin = String(source.origin || "").toLowerCase()
        var name = String(source.name || "").toLowerCase()
        if (origin === "neutronos" || name.indexOf("neutron") === 0) return 0
        if (origin === "user") return 1
        return 2
    }

    function cycleFilter() {
        var modes = ["ALL", "ACTIVE", "INACTIVE", "SYSTEMD", "DOCKER", "FILES"]
        var index = modes.indexOf(filterMode)
        filterMode = modes[(index + 1) % modes.length]
        rebuildVisibleSources()
    }

    function rebuildVisibleSources() {
        var query = String(searchText || "").trim().toLowerCase()
        var next = []
        for (var i = 0; i < sources.length; ++i) {
            var source = sources[i] || ({})
            var type = String(source.type || "").toLowerCase()
            var include = true
            if (filterMode === "ACTIVE") include = source.running === true
            else if (filterMode === "INACTIVE") include = source.running !== true
            else if (filterMode === "SYSTEMD") include = type === "service"
            else if (filterMode === "DOCKER") include = type === "docker"
            else if (filterMode === "FILES") include = type === "file" || type === "script"
            if (!include) continue
            var haystack = [source.name, source.type, source.status, source.description, source.target].join(" ").toLowerCase()
            if (query.length > 0 && haystack.indexOf(query) < 0) continue
            next.push(source)
        }
        next.sort(function(a, b) {
            if (sortMode === "NEUTRONOS_FIRST") {
                var ag = sourceGroupRank(a)
                var bg = sourceGroupRank(b)
                if (ag !== bg) return ag - bg
            } else if (sortMode === "ACTIVE") {
                var ar = a.running === true ? 0 : 1
                var br = b.running === true ? 0 : 1
                if (ar !== br) return ar - br
            } else if (sortMode === "TYPE") {
                var at = String(a.type || "")
                var bt = String(b.type || "")
                var typeCompare = at.localeCompare(bt)
                if (typeCompare !== 0) return typeCompare
            }
            return String(a.name || "").localeCompare(String(b.name || ""))
        })
        visibleSources = next
        selectedIndex = next.length > 0 ? Math.max(0, Math.min(selectedIndex, next.length - 1)) : 0
        Qt.callLater(function() {
            sourceList.currentIndex = selectedIndex
            if (next.length > 0) sourceList.positionViewAtIndex(selectedIndex, ListView.Contain)
        })
    }

    function currentSource() {
        if (!visibleSources || visibleSources.length === 0) return ({})
        return visibleSources[Math.max(0, Math.min(selectedIndex, visibleSources.length - 1))] || ({})
    }

    function moveSelection(delta) {
        if (!visibleSources || visibleSources.length === 0) return
        selectedIndex = Math.max(0, Math.min(visibleSources.length - 1, selectedIndex + delta))
        sourceList.currentIndex = selectedIndex
        sourceList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function loadSelected(liveMode) {
        var source = currentSource()
        if (!backend || !source.id) return
        var ok = liveMode ? backend.loadLive(String(source.id))
                          : backend.loadHistory(String(source.id), 700)
        toastText = String(backend.lastMessage || (ok ? "Log source loaded." : "Unable to load log source."))
        toastError = !ok
        toastTimer.restart()
        if (ok) {
            focusZone = 1
            Qt.callLater(function() {
                logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)
            })
        }
    }

    function scrollLog(delta) {
        var maxY = Math.max(0, logFlick.contentHeight - logFlick.height)
        logFlick.contentY = Math.max(0, Math.min(maxY, logFlick.contentY + delta))
    }

    function openSearch() {
        keyboardOpen = true
        keyboardBuffer.text = searchText
        keyboardBuffer.cursorPosition = keyboardBuffer.text.length
        keyboard.openKeyboard(true)
        keyboard.forceActiveFocus()
    }

    function closeSearch() {
        searchText = keyboardBuffer.text
        keyboardOpen = false
        keyboard.visibleMode = false
        rebuildVisibleSources()
        forceActiveFocus()
    }

    function handleControllerPressed(action) {
        if (!hostActive) return false
        var value = normalizeAction(action)

        if (keyboard.visibleMode || keyboardOpen) {
            keyboard.handleControllerPressed(value)
            return true
        }

        if (exitVisible) {
            referenceExitModal.handleController(value)
            return true
        }

        if (focusZone === 2) {
            if (value === "primary") { exitVisible = true; referenceExitModal.openModal(root) }
            else if (value === "down" || value === "cancel") focusZone = 0
            return true
        }

        if (value === "cancel") { exitVisible = true; referenceExitModal.openModal(root); return true }
        if (value === "r3") { cycleFilter(); return true }
        if (value === "r1") { cycleSort(); return true }
        if (value === "system") { if (backend) backend.refreshSources(); return true }
        if (value === "secondary") {
            if (backend) backend.clearOutput()
            toastText = "Log viewport cleared."
            toastError = false
            toastTimer.restart()
            return true
        }

        if (focusZone === 0) {
            if (value === "up") {
                if (selectedIndex <= 0) focusZone = 2
                else moveSelection(-1)
            } else if (value === "down") moveSelection(1)
            else if (value === "right") focusZone = 1
            else if (value === "primary") loadSelected(true)
            else if (value === "context") loadSelected(false)
            else if (value === "l1") openSearch()
            return true
        }

        if (focusZone === 1) {
            if (value === "left") focusZone = 0
            else if (value === "up") scrollLog(-100)
            else if (value === "down") scrollLog(100)
            else if (value === "l2") scrollLog(-Math.max(240, logFlick.height * 0.82))
            else if (value === "r2") scrollLog(Math.max(240, logFlick.height * 0.82))
            else if (value === "primary") loadSelected(true)
            else if (value === "context") loadSelected(false)
            return true
        }
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return true }

    onSearchTextChanged: rebuildVisibleSources()
    onFilterModeChanged: rebuildVisibleSources()
    onSortModeChanged: rebuildVisibleSources()

    Connections {
        target: backend
        ignoreUnknownSignals: true
        function onSourcesChanged() { root.rebuildVisibleSources() }
        function onOutputChanged() {
            if (backend && backend.live)
                Qt.callLater(function() {
                    logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)
                })
        }
        function onStateChanged() {
            root.toastText = backend ? String(backend.lastMessage || "") : ""
            root.toastError = root.toastText.toLowerCase().indexOf("unable") >= 0 ||
                              root.toastText.toLowerCase().indexOf("failed") >= 0 ||
                              root.toastText.toLowerCase().indexOf("error") >= 0
            if (root.toastText.length) toastTimer.restart()
        }
    }

    Rectangle { anchors.fill: parent; color: bg }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#030812" }
            GradientStop { position: 0.55; color: "#02070D" }
            GradientStop { position: 1.0; color: "#061018" }
        }
    }

    Shared.ReferenceAppHeader {
        id: header
        x: 18
        width: parent.width - 36
        anchors.top: parent.top
        z: 50
        appTitle: "Logs"
        primaryStatus: root.securityProtected ? "Secure" : "Attention"
        primaryTone: root.securityProtected ? "success" : "danger"
        secondaryStatus: ""
        attention: !root.securityProtected
        menuFocused: root.focusZone === 2 && !root.exitVisible
        onMenuRequested: { root.exitVisible = true; referenceExitModal.openModal(root) }
    }

    Shared.ReferenceAppFooter {
        id: footer
        x: 18
        width: parent.width - 36
        anchors.bottom: parent.bottom
        z: 50
        hintText: ""
        controllerBackend: root.controllerBackend
    }

    Row {
        id: workspace
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 14

        Rectangle {
            id: sourcePanel
            width: Math.max(360, Math.min(500, parent.width * 0.31))
            height: parent.height
            radius: 9
            color: panel
            border.width: root.focusZone === 0 ? 2 : 1
            border.color: root.focusZone === 0 ? blue : border

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    height: 42
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "LOG SOURCES"
                        color: textMain
                        font.pixelSize: 24
                        font.bold: true
                        font.letterSpacing: 1.8
                    }
                    Item { width: Math.max(0, parent.width - 250); height: 1 }
                    Rectangle {
                        width: countText.implicitWidth + 20
                        height: 30
                        radius: 15
                        color: "#0B1F2D"
                        border.width: 1
                        border.color: cyan
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: visibleSources.length + " / " + sources.length
                            color: cyan
                            font.pixelSize: 15
                            font.bold: true
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 7
                    color: inset
                    border.width: 1
                    border.color: border
                    Row {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 9
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: cyan; font.pixelSize: 28; font.bold: true }
                        Text {
                            width: parent.width - 150
                            anchors.verticalCenter: parent.verticalCenter
                            text: searchText.length ? searchText : "L1  SEARCH SOURCES"
                            color: searchText.length ? textMain : textMuted
                            font.pixelSize: 17
                            font.bold: searchText.length > 0
                            elide: Text.ElideRight
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: root.filterLabel(); color: purple; font.pixelSize: 16; font.bold: true; horizontalAlignment: Text.AlignRight }
                            Text { text: "R1  " + root.sortLabel(); color: cyan; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }

                ListView {
                    id: sourceList
                    width: parent.width
                    height: parent.height - 126
                    model: visibleSources
                    currentIndex: selectedIndex
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sourceList.width
                        height: 104
                        radius: 8
                        property bool selected: root.focusZone === 0 && index === root.selectedIndex
                        color: selected ? "#0D2A43" : raised
                        border.width: selected ? 2 : 1
                        border.color: selected ? blue : border

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Rectangle {
                                width: 5
                                height: 68
                                radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.sourceTone(modelData)
                            }

                            Column {
                                width: parent.width - 122
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5
                                Text {
                                    width: parent.width
                                    text: String(modelData.name || "Unknown Source")
                                    color: textMain
                                    font.pixelSize: 22
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Row {
                                    spacing: 8
                                    Text { text: root.typeLabel(modelData); color: root.sourceTone(modelData); font.pixelSize: 17; font.bold: true }
                                    Text { visible: String(modelData.originLabel || "").length > 0; text: "•  " + String(modelData.originLabel || ""); color: modelData.origin === "neutronos" ? cyan : (modelData.origin === "user" ? purple : textMuted); font.pixelSize: 15; font.bold: modelData.origin === "neutronos" }
                                    Text { text: "•"; color: textMuted; font.pixelSize: 15 }
                                    Text {
                                        width: Math.max(0, parent.parent.width - 125)
                                        text: String(modelData.status || "available")
                                        color: textMuted
                                        font.pixelSize: 14
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: String(modelData.description || "")
                                    color: textMuted
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 78
                                height: 28
                                radius: 14
                                anchors.verticalCenter: parent.verticalCenter
                                color: modelData.liveSupported ? "#0A261C" : "#221A31"
                                border.width: 1
                                border.color: modelData.liveSupported ? green : purple
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.liveSupported ? "LIVE" : "READ"
                                    color: modelData.liveSupported ? green : purple
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = index
                                sourceList.currentIndex = index
                                root.focusZone = 0
                            }
                            onDoubleClicked: root.loadSelected(true)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: outputPanel
            width: parent.width - sourcePanel.width - parent.spacing
            height: parent.height
            radius: 9
            color: panel
            border.width: root.focusZone === 1 ? 2 : 1
            border.color: root.focusZone === 1 ? blue : border

            property var selectedSource: root.currentSource()

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 92
                    radius: 8
                    color: raised
                    border.width: 1
                    border.color: border

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 16

                        Column {
                            width: parent.width - 340
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                width: parent.width
                                text: backend && backend.activeSourceName
                                      ? String(backend.activeSourceName)
                                      : String(outputPanel.selectedSource.name || "SELECT A LOG SOURCE")
                                color: textMain
                                font.pixelSize: 27
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: backend && backend.activeSourceName
                                      ? String(backend.lastMessage || "")
                                      : String(outputPanel.selectedSource.description || "Choose a source on the left. X follows live output; Triangle loads recent history.")
                                color: textMuted
                                font.pixelSize: 16
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            width: 320
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                width: 150
                                height: 40
                                radius: 20
                                color: backend && backend.live ? "#0A2B1E" : "#111A24"
                                border.width: 1
                                border.color: backend && backend.live ? green : border
                                Text {
                                    anchors.centerIn: parent
                                    text: backend && backend.live ? "● LIVE STREAM" : "HISTORY"
                                    color: backend && backend.live ? green : textMuted
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }

                            Rectangle {
                                width: 150
                                height: 40
                                radius: 20
                                color: "#0A1824"
                                border.width: 1
                                border.color: root.sourceTone(outputPanel.selectedSource)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.typeLabel(outputPanel.selectedSource)
                                    color: root.sourceTone(outputPanel.selectedSource)
                                    font.pixelSize: 14
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: logFlick
                    width: parent.width
                    height: parent.height - 142
                    clip: true
                    contentWidth: width
                    contentHeight: Math.max(height, logText.implicitHeight + 36)
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 8
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: root.focusZone === 1 ? cyan : "#526676"
                        }
                    }

                    Rectangle {
                        x: 0
                        y: 0
                        width: logFlick.width
                        height: Math.max(logFlick.height, logText.implicitHeight + 36)
                        radius: 8
                        color: inset
                        border.width: 1
                        border.color: border
                    }

                    Text {
                        id: logText
                        x: 18
                        y: 18
                        width: logFlick.width - 42
                        text: backend && backend.output && String(backend.output).length
                              ? String(backend.output)
                              : "No log output loaded.\n\nX  Follow selected source live\n△  Load recent history\nR3  Change source filter\nL1  Search\n□  Clear viewport\nOPTIONS  Refresh sources"
                        color: "#C9F4FF"
                        font.family: "monospace"
                        font.pixelSize: 19
                        lineHeight: 1.18
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                    }
                }

                Text {
                    width: parent.width
                    height: 28
                    text: root.focusZone === 1
                          ? "↑ / ↓ SCROLL     L2 / R2 PAGE     ← SOURCES     X LIVE     △ HISTORY"
                          : "X LIVE     △ HISTORY     → VIEWPORT     R3 FILTER     R1 SORT     L1 SEARCH"
                    color: root.focusZone === 1 ? cyan : textMuted
                    font.pixelSize: 14
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Rectangle {
        id: toast
        visible: toastText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: footer.top
        anchors.bottomMargin: 18
        width: Math.min(parent.width - 160, 900)
        height: 52
        radius: 26
        color: toastError ? "#37141B" : "#0B241B"
        border.width: 1
        border.color: toastError ? red : green
        z: 80
        Text {
            anchors.fill: parent
            anchors.margins: 10
            text: toastText
            color: toastError ? red : green
            font.pixelSize: 16
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "Logs"
        descriptionText: "A live stream can keep running in the background, or Logs can stop it before closing."
        exitLabel: "EXIT + STOP"
        onExitRequested: {
            root.exitVisible = false
            if (backend) backend.stopLive()
            root.exitRequested()
        }
        onLeaveRunningRequested: {
            root.exitVisible = false
            root.backgroundRequested()
        }
        onDismissed: {
            root.exitVisible = false
            root.forceActiveFocus()
        }
    }

    TextEdit { id: keyboardBuffer; visible: false }

    Shared.VirtualKeyboard {
        id: keyboard
        z: 120
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        active: visibleMode
        largeMode: false
        cancelBehavior: "close"
        title: "Search Log Sources"
        onKeyPressed: function(value) {
            keyboardBuffer.insert(keyboardBuffer.cursorPosition, String(value || ""))
        }
        onBackspacePressed: {
            if (keyboardBuffer.cursorPosition > 0)
                keyboardBuffer.remove(keyboardBuffer.cursorPosition - 1, keyboardBuffer.cursorPosition)
        }
        onEnterPressed: root.closeSearch()
        onClosePressed: root.closeSearch()
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false
        onTriggered: root.toastText = ""
    }

    Component.onCompleted: {
        if (backend) backend.refreshSources()
        rebuildVisibleSources()
        forceActiveFocus()
    }

    Component.onDestruction: {
        if (backend) backend.stopLive()
    }
}
