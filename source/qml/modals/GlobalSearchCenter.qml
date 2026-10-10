import QtQuick 2.15
import "../components" as Components

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 12500

    property var backend: (typeof coreCapabilitiesManager !== "undefined")
                          ? coreCapabilitiesManager : null
    property var appsBackend: (typeof appManager !== "undefined") ? appManager : null
    property string query: ""
    property int selectedIndex: 0
    property bool keyboardOpen: true
    property bool shellActive: true
    property int presetIndex: 0
    property string focusArea: "keyboard"
    readonly property var presetLabels: ["ALL", "APPS", "SETTINGS", "FILES", "ACTIONS"]
    readonly property real uiScale: Math.max(1, Math.min(2, Math.min(width / 1920, height / 1080)))
    readonly property real footerClearance: 36 * uiScale

    signal closed()
    signal actionRequested(string action)

    onShellActiveChanged: if (!shellActive && visible) closeCenter()

    function safe(value) {
        return String(value === undefined || value === null ? "" : value)
    }

    function openCenter() {
        query = ""
        selectedIndex = 0
        presetIndex = 0
        focusArea = "keyboard"
        visible = true
        keyboardOpen = true
        keyboard.active = true
        keyboard.openKeyboard(false)
        if (backend)
            backend.search("")
        forceActiveFocus()
    }

    function closeCenter() {
        visible = false
        keyboard.closeKeyboard()
        closed()
    }

    function rawResults() {
        return backend && backend.searchResults ? backend.searchResults : []
    }

    function matchScore(row) {
        var q = query.trim().toLowerCase()
        if (!q.length)
            return 0
        row = row || ({})
        var title = safe(row.title).toLowerCase()
        var description = safe(row.description).toLowerCase()
        var category = safe(row.category).toLowerCase()
        if (title === q) return 0
        if (title.indexOf(q) === 0) return 2 + Math.max(0, title.length - q.length) * 0.01
        var titleAt = title.indexOf(q)
        if (titleAt >= 0) return 10 + titleAt
        var descriptionAt = description.indexOf(q)
        if (descriptionAt >= 0) return 40 + descriptionAt
        var categoryAt = category.indexOf(q)
        if (categoryAt >= 0) return 70 + categoryAt
        return 1000
    }

    function results() {
        var source = rawResults()
        var sorted = []
        for (var i = 0; i < source.length; ++i)
            sorted.push(source[i])
        sorted.sort(function(a, b) { return root.matchScore(a) - root.matchScore(b) })
        if (presetIndex === 0)
            return sorted
        var wanted = String(presetLabels[presetIndex] || "").toLowerCase()
        var out = []
        for (var j = 0; j < sorted.length; ++j) {
            var row = sorted[j] || ({})
            var category = safe(row.category).toLowerCase()
            if ((wanted === "apps" && category.indexOf("app") >= 0) ||
                    (wanted === "settings" && category.indexOf("setting") >= 0) ||
                    (wanted === "files" && (category.indexOf("file") >= 0 || category.indexOf("storage") >= 0)) ||
                    (wanted === "actions" && category.indexOf("action") >= 0))
                out.push(row)
        }
        return out
    }

    function refreshSearch() {
        selectedIndex = 0
        if (backend)
            backend.search(query)
        Qt.callLater(function() {
            if (resultList && resultList.count > 0)
                resultList.positionViewAtBeginning()
        })
    }

    function keyboardOnTopRow() {
        try {
            var item = keyboard.keyAtIndex(keyboard.selectedIndex)
            return item && Number(item.row || 0) <= 0
        } catch (error) {
            return keyboard.selectedIndex <= 0
        }
    }

    function enterKeyboardFromPresets() {
        focusArea = "keyboard"
        keyboard.active = true
        keyboard.forceActiveFocus()
    }

    function isAppResult(row) {
        return safe(row && row.category).toLowerCase().indexOf("app") >= 0 ||
               safe(row && row.action).toLowerCase().indexOf("open-app:") === 0
    }

    function isGuideResult(row) {
        var c = safe(row && row.category).toLowerCase()
        return c.indexOf("guide") >= 0 || c.indexOf("help") >= 0 ||
               c.indexOf("doc") >= 0 || c.indexOf("manual") >= 0
    }

    function isSystemResult(row) {
        var c = safe(row && row.category).toLowerCase()
        return c.indexOf("system") >= 0
    }

    function appForResult(row) {
        if (!appsBackend || !row)
            return null
        var id = safe(row.appId || row.id)
        var action = safe(row.action)
        if (!id.length && action.indexOf("open-app:") === 0)
            id = action.substring(9)
        var source = appsBackend.dashboardApps ? appsBackend.dashboardApps : (appsBackend.apps ? appsBackend.apps : [])
        for (var i = 0; i < source.length; ++i) {
            var app = source[i] || ({})
            if ((id.length && safe(app.id || app.appId) === id) ||
                    (!id.length && safe(app.name || app.displayName).toLowerCase() === safe(row.title).toLowerCase()))
                return app
        }
        return null
    }

    function appIconSource(row) {
        var app = appForResult(row)
        if (!app)
            return ""
        var raw = safe(app.iconSource || app.iconPath || app.icon)
        if (!raw.length)
            return ""
        if (raw.indexOf(":") >= 0 || raw.indexOf("/") >= 0)
            return raw
        return Qt.resolvedUrl("../../themes/Default/apps/icons/" + raw + ".png")
    }

    function categoryGlyph(category) {
        var c = safe(category).toLowerCase()
        if (c.indexOf("app") >= 0) return "▦"
        if (c.indexOf("setting") >= 0) return "⚙"
        if (c.indexOf("file") >= 0) return "▤"
        if (c.indexOf("storage") >= 0) return "▱"
        if (c.indexOf("network") >= 0) return "⌁"
        if (c.indexOf("security") >= 0) return "🔒"
        if (c.indexOf("notification") >= 0) return "!"
        if (c.indexOf("action") >= 0) return "▶"
        return "⌕"
    }

    function categoryColor(category) {
        var c = safe(category).toLowerCase()
        if (c.indexOf("security") >= 0) return "#FF4057"
        if (c.indexOf("setting") >= 0) return "#B75CFF"
        if (c.indexOf("network") >= 0) return "#22D8FF"
        if (c.indexOf("file") >= 0 || c.indexOf("storage") >= 0) return "#F5C542"
        if (c.indexOf("app") >= 0) return "#4DA6FF"
        return "#7DF9FF"
    }

    function handleControllerPressed(action) {
        if (!visible)
            return false

        var currentAction = safe(action).toLowerCase()

        // With a nonempty query, Circle first dismisses only the keyboard.
        // The search, text, filters and result selection stay intact. A second
        // Circle (or Circle on an empty query) closes the whole search modal.
        if (currentAction === "cancel") {
            if (keyboardOpen && query.length > 0) {
                keyboardOpen = false
                keyboard.closeKeyboard()
                focusArea = results().length > 0 ? "results" : "presets"
                forceActiveFocus()
            } else {
                closeCenter()
            }
            return true
        }

        if (keyboardOpen && focusArea === "keyboard") {
            if (currentAction === "up" && keyboardOnTopRow()) {
                focusArea = "presets"
                keyboard.active = false
                forceActiveFocus()
                return true
            }
            return keyboard.handleControllerPressed(action)
        }

        if (focusArea === "presets") {
            if (currentAction === "left") {
                presetIndex = Math.max(0, presetIndex - 1)
                selectedIndex = 0
            } else if (currentAction === "right") {
                presetIndex = Math.min(presetLabels.length - 1, presetIndex + 1)
                selectedIndex = 0
            } else if (currentAction === "down") {
                if (results().length > 0) {
                    focusArea = "results"
                    selectedIndex = 0
                    resultList.positionViewAtBeginning()
                } else {
                    enterKeyboardFromPresets()
                }
            } else if (currentAction === "up") {
                enterKeyboardFromPresets()
            } else if (currentAction === "context" || currentAction === "system") {
                enterKeyboardFromPresets()
            }
            return true
        }

        if (focusArea === "results") {
            if (currentAction === "up") {
                if (selectedIndex <= 0) {
                    focusArea = "presets"
                    selectedIndex = 0
                } else {
                    selectedIndex = Math.max(0, selectedIndex - 1)
                    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
                }
            } else if (currentAction === "down") {
                selectedIndex = Math.min(Math.max(0, results().length - 1), selectedIndex + 1)
                resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
            } else if (currentAction === "primary" && results().length) {
                actionRequested(safe(results()[selectedIndex].action || ""))
                closeCenter()
            } else if (currentAction === "context" || currentAction === "system") {
                enterKeyboardFromPresets()
            }
            return true
        }

        focusArea = "keyboard"
        keyboard.active = true
        return true
    }

    function handleControllerReleased(action) {
        if (keyboardOpen && focusArea === "keyboard" && keyboard.handleControllerReleased)
            return keyboard.handleControllerReleased(action)
        return visible
    }

    Rectangle {
        anchors.fill: parent
        color: "#8C000309"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeCenter()
    }

    Rectangle {
        id: panel
        width: Math.min(root.width * 0.29, 470 * root.uiScale)
        height: Math.min(root.height - root.footerClearance - 18 * root.uiScale,
                         520 * root.uiScale)
        anchors.left: parent.left
        anchors.leftMargin: 14 * root.uiScale
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.footerClearance + 4 * root.uiScale
        radius: 24 * root.uiScale
        color: "#F4071426"
        border.width: 2
        border.color: "#315D86"
        clip: true

        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 4 * root.uiScale
            color: "#4DA6FF"
        }
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3 * root.uiScale
            color: "#FF3048"
            opacity: 0.74
        }

        Column {
            anchors.fill: parent
            anchors.margins: 22 * root.uiScale
            spacing: 12 * root.uiScale

            Row {
                width: parent.width
                height: 48 * root.uiScale
                spacing: 12 * root.uiScale

                Rectangle {
                    width: 44 * root.uiScale
                    height: 44 * root.uiScale
                    radius: 14 * root.uiScale
                    color: "#0B1A30"
                    border.width: 1
                    border.color: "#4DA6FF"
                    Text { anchors.centerIn: parent; text: "⌕"; color: "#7DF9FF"; font.pixelSize: 22 * root.uiScale; font.bold: true }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.uiScale
                    Row {
                        spacing: 0
                        Text { text: "Search Neutron"; color: "#F4FBFF"; font.pixelSize: 22 * root.uiScale; font.bold: true }
                        Text { text: "OS"; color: "#FF4057"; font.pixelSize: 22 * root.uiScale; font.bold: true }
                    }
                    Text { text: "Apps • Settings • Files • Actions"; color: "#8AA6C8"; font.pixelSize: 10 * root.uiScale }
                }
            }

            Row {
                width: parent.width
                height: 28 * root.uiScale
                spacing: 7 * root.uiScale
                Repeater {
                    model: root.presetLabels
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: label.implicitWidth + 20 * root.uiScale
                        height: 25 * root.uiScale
                        radius: 12 * root.uiScale
                        color: root.focusArea === "presets" && root.presetIndex === index ? "#43101A" : "#081522"
                        border.width: root.presetIndex === index ? 2 : 1
                        border.color: root.focusArea === "presets" && root.presetIndex === index ? "#FF4057" : (root.presetIndex === index ? "#7A3040" : "#294866")
                        Text { id: label; anchors.centerIn: parent; text: modelData; color: root.presetIndex === index ? "#FFFFFF" : "#AFC5DB"; font.pixelSize: 9 * root.uiScale; font.bold: true }
                    }
                }
            }

            ListView {
                id: resultList
                width: parent.width
                height: Math.max(160 * root.uiScale, parent.height - 148 * root.uiScale - parent.spacing * 4)
                model: root.results()
                spacing: 7 * root.uiScale
                clip: true
                currentIndex: root.selectedIndex

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: resultList.width
                    height: 68 * root.uiScale
                    radius: 16 * root.uiScale
                    color: root.focusArea === "results" && index === root.selectedIndex ? "#123555" : "#081522"
                    border.width: root.focusArea === "results" && index === root.selectedIndex ? 2 : 1
                    border.color: root.focusArea === "results" && index === root.selectedIndex ? "#4DA6FF" : "#203847"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 11 * root.uiScale
                        spacing: 12 * root.uiScale

                        Rectangle {
                            width: 42 * root.uiScale
                            height: 42 * root.uiScale
                            radius: 13 * root.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.isGuideResult(modelData) ? "#39FF88" : "#0B1A30"
                            border.width: 1
                            border.color: root.isGuideResult(modelData) ? "#7CFFB0" : root.categoryColor(modelData.category)
                            clip: true

                            Image {
                                id: resultIconImage
                                anchors.fill: parent
                                anchors.margins: root.isAppResult(modelData) ? 2 * root.uiScale : 7 * root.uiScale
                                visible: (root.isAppResult(modelData) && String(source).length > 0) || root.isSystemResult(modelData)
                                source: root.isSystemResult(modelData)
                                        ? Qt.resolvedUrl("../../themes/Default/atom.svg")
                                        : root.appIconSource(modelData)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.isGuideResult(modelData) || resultIconImage.status === Image.Error ||
                                         (!root.isSystemResult(modelData) &&
                                          (!root.isAppResult(modelData) || root.appIconSource(modelData).length === 0))
                                text: root.isGuideResult(modelData) ? "?" : root.categoryGlyph(modelData.category)
                                color: root.isGuideResult(modelData) ? "#FFFFFF" : root.categoryColor(modelData.category)
                                font.pixelSize: 18 * root.uiScale
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width - 60 * root.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * root.uiScale
                            Text { width: parent.width; text: root.safe(modelData.title || "Unknown"); color: "#F4FBFF"; font.pixelSize: 13 * root.uiScale; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: root.safe(modelData.description || modelData.category || ""); color: "#8AA6C8"; font.pixelSize: 9.5 * root.uiScale; elide: Text.ElideRight }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 52 * root.uiScale
                radius: 18 * root.uiScale
                color: "#030810"
                border.width: 2
                border.color: root.keyboardOpen && root.focusArea === "keyboard" ? "#4DA6FF" : "#315D86"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 18 * root.uiScale
                    anchors.rightMargin: 18 * root.uiScale
                    spacing: 10 * root.uiScale
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: "#7DF9FF"; font.pixelSize: 18 * root.uiScale; font.bold: true }
                    Text {
                        width: parent.width - 70 * root.uiScale
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query.length ? root.query : "Type to search NeutronOS"
                        color: root.query.length ? "#F4FBFF" : "#7895B5"
                        font.pixelSize: 14 * root.uiScale
                        elide: Text.ElideRight
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: { root.keyboardOpen = true; root.focusArea = "keyboard"; keyboard.active = true; keyboard.openKeyboard(false) } }
            }

        }
    }

    Rectangle {
        id: keyboardFrame
        visible: root.visible && root.keyboardOpen
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.footerClearance + 6 * root.uiScale
        width: Math.min(root.width * 0.43, 720 * root.uiScale)
        height: 172 * root.uiScale
        radius: 22 * root.uiScale
        color: "#F4071426"
        border.width: 2
        border.color: "#315D86"
        clip: true

        Components.VirtualKeyboard {
            id: keyboard
            anchors.fill: parent
            anchors.margins: 8 * root.uiScale
            visible: root.keyboardOpen
            active: root.focusArea === "keyboard"
            largeMode: false
            cancelBehavior: "close"

            onKeyPressed: function(value) {
                root.query += value
                root.refreshSearch()
            }
            onBackspacePressed: {
                root.query = root.query.slice(0, -1)
                root.refreshSearch()
            }
            onClearAllRequested: {
                root.query = ""
                root.refreshSearch()
            }
            onEnterPressed: {
                root.keyboardOpen = false
                root.focusArea = "results"
                closeKeyboard()
                root.selectedIndex = 0
                root.forceActiveFocus()
            }
            onClosePressed: {
                root.keyboardOpen = false
                root.focusArea = "results"
                closeKeyboard()
                root.forceActiveFocus()
            }
        }
    }

    Text {
        visible: root.visible && !root.keyboardOpen
        anchors.left: panel.left
        anchors.bottom: panel.top
        anchors.bottomMargin: 6 * root.uiScale
        text: "X OPEN   •   △ / OPTIONS EDIT SEARCH   •   O CLOSE"
        color: "#91A9C5"
        font.pixelSize: 10 * root.uiScale
        font.bold: true
    }
}
