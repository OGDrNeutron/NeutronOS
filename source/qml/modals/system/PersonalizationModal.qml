import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 32000

    signal closed()

    property string activeUsername: "default"
    property int selectedTab: 0
    property int selectedRow: 0
    property var overviewItems: []
    property bool overviewEnabledDraft: true
    property string launcherModeDraft: "carousel"
    property int gridCardSizeDraft: 100
    property int gridSpacingDraft: 100
    property string screensaverModeDraft: "pictures"
    property string animationDraft: "starfield"
    property int speedDraft: 100
    property int intensityDraft: 100
    property int timeoutDraft: 5
    property bool randomDraft: false
    property string statusText: "PREVIEW CHANGES BEFORE APPLYING"
    property bool statusError: false

    readonly property var tabNames: ["SYSTEM OVERVIEW", "LAUNCHER", "SCREENSAVER"]
    readonly property var timeoutOptions: [0, 3, 5, 15, 30]
    readonly property var animationIds: ["pipes", "dvd", "atom", "starfield", "plasma", "tunnel"]
    readonly property var animationNames: ["CLASSIC PIPES", "NEUTRONOS DVD BOUNCE", "ATOM FIELD", "STARFIELD", "PLASMA", "PARTICLE TUNNEL"]

    function personalization() {
        try { return (typeof personalizationManager !== "undefined" && personalizationManager) ? personalizationManager : null }
        catch (error) { return null }
    }

    function screensaver() {
        try { return (typeof screensaverManager !== "undefined" && screensaverManager) ? screensaverManager : null }
        catch (error) { return null }
    }

    function normalizedUser(value) {
        var text = String(value || "default").trim()
        return text.length > 0 ? text : "default"
    }

    function open(context) {
        var data = context || ({})
        activeUsername = normalizedUser(data.username || data.user || "default")
        var manager = personalization()
        if (manager && typeof manager.setActiveUser === "function")
            manager.setActiveUser(activeUsername)
        loadDraft()
        selectedTab = Number(data.tab || 0)
        selectedTab = Math.max(0, Math.min(2, selectedTab))
        selectedRow = 0
        statusText = "PREVIEW CHANGES BEFORE APPLYING"
        statusError = false
        visible = true
        forceActiveFocus()
    }

    function openModal(context) { open(context) }

    function close() {
        visible = false
        closed()
    }

    function closeModal() { close() }

    function loadDraft() {
        var manager = personalization()
        overviewEnabledDraft = manager ? manager.systemOverviewEnabled !== false : true
        launcherModeDraft = manager ? String(manager.launcherMode || "carousel") : "carousel"
        gridCardSizeDraft = manager ? Number(manager.gridCardSize || 100) : 100
        gridSpacingDraft = manager ? Number(manager.gridSpacing || 100) : 100

        var available = manager ? manager.availableSystemCards : []
        var layout = manager ? manager.systemOverviewLayout : []
        var result = []
        var seen = ({})
        for (var i = 0; layout && i < layout.length; ++i) {
            var id = String(layout[i])
            result.push({ "id": id, "title": cardTitle(id), "visible": true })
            seen[id] = true
        }
        for (var j = 0; available && j < available.length; ++j) {
            var item = available[j]
            var aid = String(item.id || "")
            if (aid.length <= 0 || seen[aid])
                continue
            result.push({ "id": aid, "title": String(item.title || cardTitle(aid)), "visible": false })
        }
        overviewItems = result

        var saver = screensaver()
        screensaverModeDraft = saver ? String(saver.contentMode || "pictures") : "pictures"
        animationDraft = saver ? String(saver.animationId || "starfield") : "starfield"
        speedDraft = saver ? Number(saver.animationSpeed || 100) : 100
        intensityDraft = saver ? Number(saver.animationIntensity || 100) : 100
        timeoutDraft = saver ? Number(saver.timeoutMinutes || 5) : 5
        randomDraft = saver ? saver.randomRotation === true : false
    }

    function cardTitle(id) {
        var map = {
            "cpu": "CPU", "memory": "MEMORY", "storage": "STORAGE",
            "active": "ACTIVE APPS", "temperature": "TEMPERATURE",
            "network": "NETWORK", "uptime": "CONTROLLER / UPTIME",
            "clock": "CLOCK", "user": "USER"
        }
        return map[id] || String(id || "CARD").toUpperCase()
    }

    function visibleLayout() {
        var result = []
        for (var i = 0; i < overviewItems.length; ++i) {
            if (overviewItems[i].visible)
                result.push(overviewItems[i].id)
        }
        return result
    }

    function overviewRowCount() { return Math.max(1, overviewItems.length + 1) }
    function launcherRowCount() { return 3 }
    function screensaverRowCount() { return 6 }
    function rowCount() {
        if (selectedTab === 0) return overviewRowCount()
        if (selectedTab === 1) return launcherRowCount()
        return screensaverRowCount()
    }

    function setOverviewItems(copy) {
        overviewItems = copy
    }

    function moveOverviewItem(delta) {
        if (selectedRow <= 0 || selectedRow - 1 >= overviewItems.length)
            return
        var index = selectedRow - 1
        var target = Math.max(0, Math.min(overviewItems.length - 1, index + delta))
        if (target === index)
            return
        var copy = overviewItems.slice(0)
        var item = copy.splice(index, 1)[0]
        copy.splice(target, 0, item)
        setOverviewItems(copy)
        selectedRow = target + 1
    }

    function toggleOverviewItem() {
        if (selectedRow === 0) {
            overviewEnabledDraft = !overviewEnabledDraft
            return
        }
        var index = selectedRow - 1
        if (index < 0 || index >= overviewItems.length)
            return
        var copy = overviewItems.slice(0)
        var item = copy[index]
        item = { "id": item.id, "title": item.title, "visible": !item.visible }
        copy[index] = item
        setOverviewItems(copy)
    }

    function cycle(value, values, delta) {
        var index = values.indexOf(value)
        if (index < 0) index = 0
        return values[(index + delta + values.length) % values.length]
    }

    function adjust(delta) {
        if (selectedTab === 0) {
            if (selectedRow === 0) overviewEnabledDraft = !overviewEnabledDraft
            else moveOverviewItem(delta)
            return
        }
        if (selectedTab === 1) {
            if (selectedRow === 0)
                launcherModeDraft = launcherModeDraft === "carousel" ? "grid" : "carousel"
            else if (selectedRow === 1)
                gridCardSizeDraft = Math.max(70, Math.min(140, gridCardSizeDraft + delta * 5))
            else
                gridSpacingDraft = Math.max(70, Math.min(140, gridSpacingDraft + delta * 5))
            return
        }
        if (selectedRow === 0)
            screensaverModeDraft = screensaverModeDraft === "pictures" ? "animations" : "pictures"
        else if (selectedRow === 1)
            animationDraft = cycle(animationDraft, animationIds, delta)
        else if (selectedRow === 2)
            speedDraft = Math.max(40, Math.min(180, speedDraft + delta * 10))
        else if (selectedRow === 3)
            intensityDraft = Math.max(30, Math.min(160, intensityDraft + delta * 10))
        else if (selectedRow === 4)
            timeoutDraft = cycle(timeoutDraft, timeoutOptions, delta)
        else
            randomDraft = !randomDraft
    }

    function applyCurrent() {
        var ok = true
        var manager = personalization()
        if (selectedTab === 0) {
            var layout = visibleLayout()
            if (overviewEnabledDraft && layout.length <= 0) {
                statusText = "KEEP AT LEAST ONE CARD OR DISABLE SYSTEM OVERVIEW"
                statusError = true
                return
            }
            ok = manager && manager.applySystemOverview(layout, overviewEnabledDraft)
        } else if (selectedTab === 1) {
            ok = manager && manager.applyLauncher(launcherModeDraft, gridCardSizeDraft, gridSpacingDraft)
        } else {
            var saver = screensaver()
            ok = saver && saver.applyPresentation(screensaverModeDraft, animationDraft,
                                                   speedDraft, intensityDraft, randomDraft)
            if (ok && typeof saver.applyTimeoutMinutes === "function")
                ok = saver.applyTimeoutMinutes(timeoutDraft)
        }
        statusError = !ok
        statusText = ok ? "APPLIED FOR " + activeUsername.toUpperCase() : "SETTINGS COULD NOT BE SAVED"
    }

    function resetCurrent() {
        var manager = personalization()
        if (selectedTab === 0 && manager) manager.resetSystemOverview()
        else if (selectedTab === 1 && manager) manager.resetLauncher()
        else {
            var saver = screensaver()
            if (saver) {
                saver.applyPresentation("pictures", "starfield", 100, 100, false)
                saver.applyTimeoutMinutes(5)
            }
        }
        loadDraft()
        selectedRow = 0
        statusText = "DEFAULTS RESTORED"
        statusError = false
    }

    function previewScreensaver() {
        var saver = screensaver()
        if (!saver) return
        saver.applyPresentation(screensaverModeDraft, animationDraft, speedDraft, intensityDraft, randomDraft)
        saver.applyTimeoutMinutes(timeoutDraft)
        saver.activate()
    }

    function handleControllerPressed(action) {
        if (!visible) return false
        var a = String(action || "").toLowerCase()
        if (a === "cancel" || a === "o" || a === "back") { close(); return true }
        if (a === "l1") { selectedTab = (selectedTab + 2) % 3; selectedRow = 0; return true }
        if (a === "r1") { selectedTab = (selectedTab + 1) % 3; selectedRow = 0; return true }
        if (a === "up") selectedRow = Math.max(0, selectedRow - 1)
        else if (a === "down") selectedRow = Math.min(rowCount() - 1, selectedRow + 1)
        else if (a === "left") adjust(-1)
        else if (a === "right") adjust(1)
        else if (a === "secondary" || a === "square") {
            if (selectedTab === 0) toggleOverviewItem()
            else resetCurrent()
        }
        else if (a === "tertiary" || a === "triangle") {
            if (selectedTab === 0) overviewEnabledDraft = !overviewEnabledDraft
            else if (selectedTab === 2) previewScreensaver()
        }
        else if (a === "primary" || a === "x" || a === "confirm") applyCurrent()
        return true
    }

    Keys.onPressed: function(event) {
        var map = ({})
        map[Qt.Key_Up] = "up"; map[Qt.Key_Down] = "down"
        map[Qt.Key_Left] = "left"; map[Qt.Key_Right] = "right"
        map[Qt.Key_Return] = "primary"; map[Qt.Key_Enter] = "primary"
        map[Qt.Key_Escape] = "cancel"; map[Qt.Key_Backspace] = "cancel"
        if (map[event.key]) { event.accepted = true; handleControllerPressed(map[event.key]) }
    }

    Rectangle { anchors.fill: parent; color: "#E602060D" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 110, 1380)
        height: Math.min(parent.height - 90, 850)
        radius: 30
        color: "#071426"
        border.width: 2
        border.color: "#4DA6FF"

        Column {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 16

            Text {
                width: parent.width
                text: "PERSONALIZE CONSOLE"
                color: "#F4FBFF"
                font.pixelSize: 34
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Repeater {
                    model: root.tabNames
                    Rectangle {
                        width: 250; height: 50; radius: 25
                        color: index === root.selectedTab ? "#0D263A" : "#0B1A30"
                        border.width: index === root.selectedTab ? 2 : 1
                        border.color: index === root.selectedTab ? "#7DF9FF" : "#203847"
                        Text { anchors.centerIn: parent; text: modelData; color: "#F4FBFF"; font.pixelSize: 16; font.bold: true }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 150
                radius: 22
                color: "#06101F"
                border.width: 1
                border.color: "#315A80"

                Row {
                    visible: root.selectedTab === 0
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: root.overviewItems
                        Rectangle {
                            visible: modelData.visible && root.overviewEnabledDraft
                            width: Math.max(80, Math.min(130, (parent.parent.width - 80) / Math.max(1, root.visibleLayout().length)))
                            height: 82; radius: 14
                            color: "#081522"; border.width: 1; border.color: "#4DA6FF"
                            Text { anchors.centerIn: parent; width: parent.width - 8; text: modelData.title; color: "#F4FBFF"; font.pixelSize: 12; font.bold: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                        }
                    }
                    Text { visible: !root.overviewEnabledDraft; text: "SYSTEM OVERVIEW DISABLED"; color: "#F5C542"; font.pixelSize: 22; font.bold: true }
                }

                Grid {
                    visible: root.selectedTab === 1
                    anchors.centerIn: parent
                    columns: root.launcherModeDraft === "grid" ? 4 : 5
                    spacing: 12 * root.gridSpacingDraft / 100
                    Repeater {
                        model: root.launcherModeDraft === "grid" ? 8 : 5
                        Rectangle {
                            width: (root.launcherModeDraft === "grid" ? 92 : (index === 2 ? 105 : 72)) * root.gridCardSizeDraft / 100
                            height: width * 1.12; radius: 13; color: "#081522"; border.width: 1; border.color: index === 2 ? "#7DF9FF" : "#203847"
                        }
                    }
                }

                Item {
                    visible: root.selectedTab === 2
                    anchors.fill: parent
                    Text { anchors.centerIn: parent; text: root.screensaverModeDraft === "pictures" ? "PICTURE PAN & ZOOM" : root.animationNames[root.animationIds.indexOf(root.animationDraft)]; color: "#7DF9FF"; font.pixelSize: 25; font.bold: true }
                }
            }

            ListView {
                id: settingsList
                width: parent.width
                height: parent.height - 310
                clip: true
                spacing: 8
                model: root.rowCount()
                delegate: Rectangle {
                    width: settingsList.width
                    height: 62
                    radius: 15
                    color: index === root.selectedRow ? "#0D263A" : "#0B1A30"
                    border.width: index === root.selectedRow ? 2 : 1
                    border.color: index === root.selectedRow ? "#7DF9FF" : "#203847"

                    property string rowTitle: {
                        if (root.selectedTab === 0) {
                            if (index === 0) return "SYSTEM OVERVIEW"
                            var item = root.overviewItems[index - 1]
                            return (item.visible ? "SHOW  " : "HIDE  ") + item.title
                        }
                        if (root.selectedTab === 1) return ["LAUNCHER MODE", "GRID CARD SIZE", "GRID SPACING"][index]
                        return ["CONTENT", "ANIMATION", "SPEED", "INTENSITY", "IDLE TIMEOUT", "RANDOM ROTATION"][index]
                    }
                    property string rowValue: {
                        if (root.selectedTab === 0) {
                            if (index === 0) return root.overviewEnabledDraft ? "ENABLED" : "DISABLED"
                            return root.overviewItems[index - 1].visible ? "VISIBLE" : "HIDDEN"
                        }
                        if (root.selectedTab === 1) return [root.launcherModeDraft.toUpperCase(), root.gridCardSizeDraft + "%", root.gridSpacingDraft + "%"][index]
                        if (index === 0) return root.screensaverModeDraft.toUpperCase()
                        if (index === 1) return root.animationNames[root.animationIds.indexOf(root.animationDraft)]
                        if (index === 2) return root.speedDraft + "%"
                        if (index === 3) return root.intensityDraft + "%"
                        if (index === 4) return root.timeoutDraft === 0 ? "OFF" : root.timeoutDraft + " MIN"
                        return root.randomDraft ? "ON" : "OFF"
                    }

                    Text { anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: parent.rowTitle; color: "#F4FBFF"; font.pixelSize: 17; font.bold: true }
                    Text { anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; text: parent.rowValue; color: index === root.selectedRow ? "#7DF9FF" : "#8AA6C8"; font.pixelSize: 16; font.bold: true }
                }
            }

            Row {
                width: parent.width
                spacing: 18
                Text { width: parent.width * 0.62; text: root.statusText; color: root.statusError ? "#FF3040" : "#22FF88"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                Text { text: "L1/R1 TAB  •  ←/→ CHANGE  •  □ HIDE/RESET  •  △ PREVIEW  •  X APPLY  •  O CLOSE"; color: "#8AA6C8"; font.pixelSize: 12; font.bold: true }
            }
        }
    }
}
