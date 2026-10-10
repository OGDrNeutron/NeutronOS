import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    visible: visibleMode
    enabled: visibleMode
    z: 980
    property bool visibleMode: false
    property bool armed: false
    property string version: ""
    property string sizeText: ""
    property string releaseNotes: ""
    property color panelColor: "#101722"
    property color textPrimary: "#ffffff"
    property color textSecondary: "#b8c5d5"
    property color focusBlue: "#36a9ff"
    property color warning: "#ffd24a"
    signal confirmed()
    signal closeRequested()

    function openModal(candidateVersion, candidateSize, notes) {
        version = String(candidateVersion || "")
        sizeText = String(candidateSize || "")
        releaseNotes = String(notes || "")
        armed = false
        visibleMode = true
        forceActiveFocus()
    }
    function closeModal() {
        visibleMode = false
        armed = false
        closeRequested()
    }
    function handleControllerPressed(action) {
        if (!visibleMode) return false
        if (action === "cancel") { closeModal(); return true }
        if (action === "primary") {
            if (!armed) armed = true
            else { visibleMode = false; armed = false; confirmed() }
            return true
        }
        return true
    }

    Rectangle { anchors.fill: parent; color: "#b0000000" }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 850)
        height: Math.min(parent.height - 110, 610)
        radius: 24
        color: root.panelColor
        border.width: root.armed ? 2 : 1
        border.color: root.armed ? root.warning : "#40516a"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 34
            spacing: 18
            Text { text: "INSTALL NEUTRONOS UPDATE"; color: root.textPrimary; font.pixelSize: 31; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text { text: "NeutronOS Gemini " + root.version; color: root.focusBlue; font.pixelSize: 26; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text { text: root.sizeText; color: root.textSecondary; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#334155" }
            Text { text: root.releaseNotes.length ? root.releaseNotes : "This package passed Ed25519 metadata, compatibility, size and SHA-256 verification."; color: root.textSecondary; font.pixelSize: 19; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.fillHeight: true }
            Text {
                text: root.armed ? "UPDATE ARMED\nPress X again to stage this update for Recovery." : "Press X to review and arm installation. Press O to cancel."
                color: root.armed ? root.warning : root.textPrimary
                font.pixelSize: 21
                font.bold: root.armed
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
    }
}
