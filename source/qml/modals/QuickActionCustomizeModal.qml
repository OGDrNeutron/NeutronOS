import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root

    property var backend:
        (typeof quickActionManager !== "undefined" && quickActionManager)
        ? quickActionManager
        : null

    property int selectedSlot: 0
    property int selectedActionIndex: 0
    property int focusPane: 0 // 0 = slots, 1 = catalogue
    property string statusMessage: ""
    property bool statusError: false

    signal closed()
    signal layoutChanged()

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 20000
    color: "#FA02060D"
    Keys.enabled: visible

    function dockActions() {
        if (!backend)
            return []
        try { return backend.dockActions || [] } catch (error) { return [] }
    }

    function allActions() {
        if (!backend)
            return []
        try { return backend.actions || [] } catch (error) { return [] }
    }

    function open(slot) {
        var count = Math.max(1, dockActions().length)
        selectedSlot = Math.max(0, Math.min(count - 1, Number(slot) || 0))
        selectedActionIndex = matchingActionIndex(selectedSlot)
        focusPane = 0
        statusMessage = "X replaces  •  □ adds/removes  •  L1/R1 reorders  •  no slot limit."
        statusError = false
        visible = true
        forceActiveFocus()
        Qt.callLater(ensureCurrentVisible)
    }

    function close() {
        if (!visible)
            return
        visible = false
        statusMessage = ""
        statusError = false
        closed()
    }

    function actionId(data) {
        if (!data)
            return ""
        try { return String(data.id || data.actionId || "") } catch (error) { return "" }
    }

    function actionName(data) {
        if (!data)
            return "Unknown"
        try { return String(data.name || data.title || data.id || "Unknown") } catch (error) { return "Unknown" }
    }

    function actionType(data) {
        if (!data)
            return "ACTION"
        var type = ""
        try { type = String(data.type || "").toLowerCase() } catch (error) { type = "" }
        if (type === "qml" || type === "app" || type === "web" || type === "service-web")
            return "APP"
        if (type.indexOf("service") >= 0)
            return "SERVICE"
        if (type === "script")
            return "SCRIPT"
        return "SYSTEM"
    }

    function matchingActionIndex(slot) {
        var dock = dockActions()
        var actions = allActions()
        if (slot < 0 || slot >= dock.length)
            return 0
        var id = actionId(dock[slot])
        for (var i = 0; i < actions.length; ++i) {
            if (actionId(actions[i]) === id)
                return i
        }
        return 0
    }

    function move(delta) {
        if (focusPane === 0) {
            var slotCount = dockActions().length
            if (slotCount <= 0)
                return false
            selectedSlot = (selectedSlot + delta + slotCount) % slotCount
            selectedActionIndex = matchingActionIndex(selectedSlot)
        } else {
            var count = allActions().length
            if (count > 0)
                selectedActionIndex = (selectedActionIndex + delta + count) % count
        }
        statusMessage = ""
        statusError = false
        ensureCurrentVisible()
        return true
    }

    function ensureCurrentVisible() {
        if (focusPane === 0)
            slotList.positionViewAtIndex(selectedSlot, ListView.Contain)
        else
            actionList.positionViewAtIndex(selectedActionIndex, ListView.Contain)
    }

    function activateSelected() {
        if (focusPane === 0) {
            focusPane = 1
            selectedActionIndex = matchingActionIndex(selectedSlot)
            ensureCurrentVisible()
            return true
        }

        var actions = allActions()
        if (!backend || selectedActionIndex < 0 || selectedActionIndex >= actions.length)
            return true

        var id = actionId(actions[selectedActionIndex])
        var saved = false
        try {
            if (typeof backend.setDockAction === "function")
                saved = backend.setDockAction(selectedSlot, id) === true
        } catch (error) {
            statusMessage = String(error)
            statusError = true
            return true
        }

        statusMessage = saved
                        ? "Slot " + (selectedSlot + 1) + " now uses " + actionName(actions[selectedActionIndex]) + "."
                        : "The Quick Action layout could not be saved."
        statusError = !saved
        if (saved) {
            layoutChanged()
            selectedActionIndex = matchingActionIndex(selectedSlot)
        }
        return true
    }

    function appendSelectedAction() {
        var actions = allActions()
        if (!backend || selectedActionIndex < 0 || selectedActionIndex >= actions.length)
            return true

        var saved = false
        try {
            if (typeof backend.appendDockAction === "function")
                saved = backend.appendDockAction(actionId(actions[selectedActionIndex])) === true
        } catch (error) {
            statusMessage = String(error)
            statusError = true
            return true
        }

        statusMessage = saved
                        ? actionName(actions[selectedActionIndex]) + " added to the dock."
                        : "That action is already present or could not be added."
        statusError = !saved
        if (saved) {
            selectedSlot = Math.max(0, dockActions().length - 1)
            layoutChanged()
            focusPane = 0
            ensureCurrentVisible()
        }
        return true
    }

    function removeSelectedSlot() {
        if (!backend || dockActions().length <= 1) {
            statusMessage = "The dock must keep at least one shortcut."
            statusError = true
            return true
        }

        var saved = false
        try {
            if (typeof backend.removeDockAction === "function")
                saved = backend.removeDockAction(selectedSlot) === true
        } catch (error) {
            statusMessage = String(error)
            statusError = true
            return true
        }

        statusMessage = saved ? "Shortcut removed." : "The shortcut could not be removed."
        statusError = !saved
        if (saved) {
            selectedSlot = Math.max(0, Math.min(dockActions().length - 1, selectedSlot))
            selectedActionIndex = matchingActionIndex(selectedSlot)
            layoutChanged()
            ensureCurrentVisible()
        }
        return true
    }

    function reorderSelected(delta) {
        var count = dockActions().length
        if (!backend || count <= 1)
            return true

        var destination = Math.max(0, Math.min(count - 1, selectedSlot + delta))
        if (destination === selectedSlot)
            return true

        var saved = false
        try {
            if (typeof backend.moveDockAction === "function")
                saved = backend.moveDockAction(selectedSlot, destination) === true
        } catch (error) {
            statusMessage = String(error)
            statusError = true
            return true
        }

        statusMessage = saved ? "Shortcut reordered." : "The shortcut could not be moved."
        statusError = !saved
        if (saved) {
            selectedSlot = destination
            selectedActionIndex = matchingActionIndex(selectedSlot)
            layoutChanged()
            ensureCurrentVisible()
        }
        return true
    }

    function resetLayout() {
        var saved = false
        try {
            if (backend && typeof backend.resetDockActions === "function")
                saved = backend.resetDockActions() === true
        } catch (error) {
            statusMessage = String(error)
            statusError = true
            return true
        }
        statusMessage = saved ? "The default Quick Actions were restored." : "Defaults could not be restored."
        statusError = !saved
        if (saved) {
            selectedSlot = 0
            selectedActionIndex = matchingActionIndex(0)
            layoutChanged()
            ensureCurrentVisible()
        }
        return true
    }

    function normalize(value) {
        var action = String(value || "").trim().toLowerCase()
        if (action === "cross" || action === "x" || action === "primary" || action === "confirm") return "primary"
        if (action === "circle" || action === "o" || action === "cancel" || action === "back") return "cancel"
        if (action === "triangle" || action === "context") return "context"
        if (action === "square" || action === "secondary") return "secondary"
        if (action === "lb" || action === "l1") return "l1"
        if (action === "rb" || action === "r1") return "r1"
        if (action === "dpad_up") return "up"
        if (action === "dpad_down") return "down"
        if (action === "dpad_left") return "left"
        if (action === "dpad_right") return "right"
        return action
    }

    function handleControllerPressed(value) {
        if (!visible)
            return false
        var action = normalize(value)
        if (action === "cancel") {
            if (focusPane === 1) {
                focusPane = 0
                ensureCurrentVisible()
            } else {
                close()
            }
            return true
        }
        if (action === "left") {
            focusPane = 0
            ensureCurrentVisible()
            return true
        }
        if (action === "right") {
            focusPane = 1
            ensureCurrentVisible()
            return true
        }
        if (action === "up") return move(-1)
        if (action === "down") return move(1)
        if (action === "primary") return activateSelected()
        if (action === "secondary")
            return focusPane === 0 ? removeSelectedSlot() : appendSelectedAction()
        if (action === "l1") return focusPane === 0 ? reorderSelected(-1) : true
        if (action === "r1") return focusPane === 0 ? reorderSelected(1) : true
        if (action === "context") return resetLayout()
        return true
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Left) action = "left"
        else if (event.key === Qt.Key_Right) action = "right"
        else if (event.key === Qt.Key_Up) action = "up"
        else if (event.key === Qt.Key_Down) action = "down"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        else if (event.key === Qt.Key_T) action = "context"
        else if (event.key === Qt.Key_Q) action = "secondary"
        else if (event.key === Qt.Key_PageUp) action = "l1"
        else if (event.key === Qt.Key_PageDown) action = "r1"
        if (action.length > 0) {
            event.accepted = true
            handleControllerPressed(action)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#F0000000"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1540)
        height: Math.min(parent.height - 96, 900)
        radius: 34
        color: "#020814"
        opacity: 1.0
        border.width: 2
        border.color: "#FF3040"
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 94
            color: "#071426"
            border.width: 1
            border.color: "#375875"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 34
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    text: "CUSTOMIZE QUICK ACTIONS"
                    color: "#FFFFFF"
                    font.pixelSize: 28
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    text: "One to unlimited persistent Console shortcuts"
                    color: "#9FD8FF"
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                width: 128
                height: 38
                radius: 19
                color: "#301018"
                border.width: 1
                border.color: "#FF3040"

                Text {
                    anchors.centerIn: parent
                    text: "ARMED"
                    color: "#FFB2BC"
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 2.2
                }
            }
        }

        Rectangle {
            id: slotRail
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: footer.top
            anchors.topMargin: 94
            width: 330
            color: "#09182A"
            border.width: 1
            border.color: "#29445E"

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 24
                anchors.topMargin: 20
                text: "DOCK SLOTS"
                color: "#7598BA"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2.0
            }

            ListView {
                id: slotList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 56
                anchors.bottomMargin: 20
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 9
                clip: true
                model: root.dockActions()

                delegate: Rectangle {
                    width: slotList.width
                    height: 78
                    radius: 18
                    color: root.selectedSlot === index
                           ? root.focusPane === 0 ? "#12334F" : "#10263C"
                           : "#0A1727"
                    border.width: root.selectedSlot === index ? 2 : 1
                    border.color: root.selectedSlot === index
                                  ? root.focusPane === 0 ? "#7DF9FF" : "#4B82AA"
                                  : "#29445E"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 14

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 14
                            color: "#10243A"
                            border.width: 1
                            border.color: "#496A8A"

                            Text {
                                anchors.centerIn: parent
                                text: index + 1
                                color: "#FFFFFF"
                                font.pixelSize: 18
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width - 72
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                width: parent.width
                                text: root.actionName(modelData)
                                color: "#FFFFFF"
                                font.pixelSize: 17
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.actionType(modelData)
                                color: "#8FB6D7"
                                font.pixelSize: 12
                                font.bold: true
                                font.letterSpacing: 1.2
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedSlot = index
                            root.focusPane = 0
                        }
                        onDoubleClicked: {
                            root.selectedSlot = index
                            root.focusPane = 1
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 7
                }
            }
        }

        Rectangle {
            anchors.left: slotRail.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: footer.top
            anchors.topMargin: 94
            color: "#07111F"

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 28
                anchors.topMargin: 20
                text: "AVAILABLE ACTIONS"
                color: "#7598BA"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2.0
            }

            ListView {
                id: actionList
                anchors.fill: parent
                anchors.topMargin: 56
                anchors.leftMargin: 22
                anchors.rightMargin: 20
                anchors.bottomMargin: 20
                spacing: 10
                clip: true
                model: root.allActions()

                delegate: Rectangle {
                    width: actionList.width - 10
                    height: 86
                    radius: 19
                    color: root.selectedActionIndex === index
                           ? root.focusPane === 1 ? "#12334F" : "#10263C"
                           : "#0A1727"
                    border.width: root.selectedActionIndex === index ? 2 : 1
                    border.color: root.selectedActionIndex === index
                                  ? root.focusPane === 1 ? "#7DF9FF" : "#4B82AA"
                                  : "#29445E"

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 16

                        Rectangle {
                            width: 56
                            height: 56
                            radius: 16
                            color: "#10243A"
                            border.width: 1
                            border.color: "#496A8A"

                            Text {
                                anchors.centerIn: parent
                                text: root.actionType(modelData).substring(0, 1)
                                color: "#BDF7FF"
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width - 170
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Text {
                                width: parent.width
                                text: root.actionName(modelData)
                                color: "#FFFFFF"
                                font.pixelSize: 19
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: String(modelData.subtitle || "Quick action")
                                color: "#91ABC3"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 92
                            height: 32
                            radius: 16
                            color: "#0D2637"
                            border.width: 1
                            border.color: "#4A7897"

                            Text {
                                anchors.centerIn: parent
                                text: root.actionType(modelData)
                                color: "#A9DDF7"
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 1.0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selectedActionIndex = index
                            root.focusPane = 1
                        }
                        onDoubleClicked: {
                            root.selectedActionIndex = index
                            root.focusPane = 1
                            root.activateSelected()
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    width: 8
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 76
            color: "#08182A"
            border.width: 1
            border.color: "#29445E"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.55
                text: root.statusMessage
                color: root.statusError ? "#FF9CA8" : "#9FD8FF"
                font.pixelSize: 14
                font.bold: root.statusMessage.length > 0
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: "◀▶ PANEL   ▲▼ MOVE   X REPLACE   □ ADD/REMOVE   L1/R1 REORDER   △ DEFAULTS   O BACK"
                color: "#7895B1"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 0.8
            }
        }
    }
}
