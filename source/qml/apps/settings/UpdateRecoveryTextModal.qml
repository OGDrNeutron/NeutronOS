import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    focus: visibleMode
    z: 120

    property bool visibleMode: false
    property string modalTitle: "DETAILS"
    property string modalSubtitle: ""
    property string modalBody: ""

    property color panelColor: "#071426"
    property color panelRaised: "#0B1A30"
    property color textPrimary: "#F4FBFF"
    property color textSecondary: "#A8C2DE"
    property color textMuted: "#7895B5"
    property color divider: "#1D3958"
    property color focusBlue: "#4DA6FF"

    signal closeRequested()

    function normalizeAction(action) {
        var value = String(action || "").trim().toLowerCase()
        if (value === "x" || value === "cross" || value === "primary" || value === "accept") return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back") return "cancel"
        if (value === "options" || value === "start" || value === "system") return "system"
        if (value === "dpad_up") return "up"
        if (value === "dpad_down") return "down"
        if (value === "l2") return "page_up"
        if (value === "r2") return "page_down"
        return value
    }

    function openModal(title, subtitle, body) {
        modalTitle = String(title || "DETAILS")
        modalSubtitle = String(subtitle || "")
        modalBody = String(body || "")
        bodyFlick.contentY = 0
        visibleMode = true
        forceActiveFocus()
    }

    function closeModal() {
        visibleMode = false
        closeRequested()
    }

    function handleControllerPressed(action) {
        var value = normalizeAction(action)
        if (!visibleMode)
            return false
        if (value === "cancel" || value === "primary" || value === "system") {
            closeModal()
            return true
        }
        if (value === "up") {
            bodyFlick.contentY = Math.max(0, bodyFlick.contentY - 64)
            return true
        }
        if (value === "down") {
            bodyFlick.contentY = Math.min(Math.max(0, bodyFlick.contentHeight - bodyFlick.height), bodyFlick.contentY + 64)
            return true
        }
        if (value === "page_up") {
            bodyFlick.contentY = Math.max(0, bodyFlick.contentY - bodyFlick.height * 0.72)
            return true
        }
        if (value === "page_down") {
            bodyFlick.contentY = Math.min(Math.max(0, bodyFlick.contentHeight - bodyFlick.height), bodyFlick.contentY + bodyFlick.height * 0.72)
            return true
        }
        return true
    }

    function handleController(action) { return handleControllerPressed(action) }
    function handleControllerReleased(action) { return visibleMode }

    Rectangle {
        anchors.fill: parent
        color: "#B0000000"
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1180)
        height: Math.min(parent.height - 100, 820)
        radius: 34
        color: root.panelColor
        border.width: 2
        border.color: root.focusBlue

        Column {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 15

            Text {
                width: parent.width
                text: root.modalTitle
                color: root.textPrimary
                font.pixelSize: 30
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: root.modalSubtitle
                color: root.focusBlue
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 1.1
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.divider
            }

            Flickable {
                id: bodyFlick
                width: parent.width
                height: parent.height - 164
                clip: true
                contentWidth: width
                contentHeight: bodyText.implicitHeight + 20
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: bodyText
                    width: bodyFlick.width - 30
                    x: 8
                    y: 8
                    text: root.modalBody
                    color: root.textSecondary
                    font.pixelSize: 18
                    lineHeight: 1.28
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }

                ScrollBar.vertical: ScrollBar {
                    policy: bodyFlick.contentHeight > bodyFlick.height
                            ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                }
            }

            Text {
                width: parent.width
                text: "UP / DOWN  SCROLL     L2 / R2  PAGE     X / O  CLOSE"
                color: root.textMuted
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!visibleMode)
            return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
            handleControllerPressed("cancel")
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            handleControllerPressed("primary")
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            handleControllerPressed("up")
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            handleControllerPressed("down")
            event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
            handleControllerPressed("page_up")
            event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
            handleControllerPressed("page_down")
            event.accepted = true
        }
    }
}
