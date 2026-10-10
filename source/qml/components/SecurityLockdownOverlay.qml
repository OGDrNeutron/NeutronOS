import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "." as Shared

Item {
    id: overlay
    anchors.fill: parent
    focus: true
    property var backend: null
    property string codeBuffer: ""
    property bool keyboardOpen: false

    readonly property string method: backend ? String(backend.recoveryMethod || "none") : "none"
    readonly property var verification: backend && backend.lastRecoveryVerification ? backend.lastRecoveryVerification : ({})

    function normalizeAction(action) {
        var value = String(action || "").toLowerCase().replace(/-/g, "_")
        if (value === "x" || value === "cross" || value === "primary") return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back") return "cancel"
        if (value === "triangle" || value === "context") return "context"
        if (value === "square" || value === "secondary") return "secondary"
        return value
    }

    function handleControllerPressed(action) {
        var value = normalizeAction(action)
        if (method === "code") {
            if (!keyboardOpen) { keyboardOpen = true; keyboard.openKeyboard(true) }
            return keyboard.handleControllerPressed(value)
        }
        if (method === "usb") {
            if ((value === "primary" || value === "context") && backend) backend.verifyUsbRecovery()
            return true
        }
        return true
    }
    function handleControllerReleased(action) { return true }

    Component.onCompleted: {
        forceActiveFocus()
        if (method === "code") { keyboardOpen = true; keyboard.openKeyboard(true) }
        else if (method === "usb" && backend) backend.verifyUsbRecovery()
    }

    Rectangle { anchors.fill: parent; color: "#FF010308" }
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 160, 1040)
        spacing: 24
        Text { text: "DEFCON 1 — SYSTEM LOCKDOWN"; color: "#FF4157"; font.pixelSize: 42; font.bold: true; Layout.alignment: Qt.AlignHCenter }
        Text { Layout.fillWidth: true; text: "Remote access and normal NeutronOS controls are disabled. Only the enrolled physical recovery method is accepted."; color: "#D7E6F2"; font.pixelSize: 18; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: method === "code" ? 150 : 190; radius: 24
            color: "#FF091423"; border.width: 3; border.color: method === "code" ? "#37E89B" : "#6BEAFF"
            Column {
                anchors.fill: parent; anchors.margins: 22; spacing: 14
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: method === "code" ? "ENTER RECOVERY CODE" : method === "usb" ? "INSERT ENROLLED USB RECOVERY KEY" : "RECOVERY KEY NOT CONFIGURED"; color: method === "none" ? "#FF4157" : "#F4FBFF"; font.pixelSize: 23; font.bold: true }
                Text { width: parent.width; visible: method === "code"; text: codeBuffer.length ? Array(codeBuffer.length + 1).join("•") : "Use the Virtual Keyboard. All other input is ignored."; color: "#9CB9D1"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere }
                Text { width: parent.width; visible: method === "usb"; text: "Only the enrolled device identity and .neutronos-recovery-key.json are inspected. Other removable devices remain ignored."; color: "#9CB9D1"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                Text { width: parent.width; text: String(verification.message || "Awaiting recovery verification"); color: verification.success ? "#37E89B" : "#FFD166"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
            }
        }
        Text { visible: method === "usb"; text: "X  Verify Again"; color: "#6BEAFF"; font.pixelSize: 15; Layout.alignment: Qt.AlignHCenter }
    }

    Shared.VirtualKeyboard {
        id: keyboard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 20
        active: method === "code" && keyboardOpen
        largeMode: true
        cancelBehavior: "backspace"
        title: "Emergency Recovery Code"
        onKeyPressed: function(value) { codeBuffer += value === "SPACE" ? "" : value }
        onBackspacePressed: { if (codeBuffer.length) codeBuffer = codeBuffer.substring(0, codeBuffer.length - 1) }
        onEnterPressed: {
            if (backend && codeBuffer.length) backend.verifyRecoveryCode(codeBuffer)
            codeBuffer = ""
        }
        onClosePressed: { keyboardOpen = true; keyboard.openKeyboard(true) }
    }
}
