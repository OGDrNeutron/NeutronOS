import QtQuick 2.15
import QtQuick.Controls 2.15

TerminalGlassPanel {
    id: root

    property string promptLabel: "echo@neutronos:~$"
    property string draftText: ""
    property bool developerMode: false
    property bool typebarFocused: false
    property color textColor: "#F3FCFF"
    property string actionMessage: ""
    property bool actionError: false
    property bool remoteMirrorRunning: false
    property int fontPixelSize: 18
    property bool timestampVisible: true

    signal draftEdited(string text)
    signal commitRequested()
    signal cancelRequested()
    signal moveUpRequested()
    signal moveDownRequested()
    signal moveLeftRequested()
    signal moveRightRequested()

    property string clockText: Qt.formatTime(new Date(), "hh:mm:ss AP")

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.clockText = Qt.formatTime(new Date(), "hh:mm:ss AP")
    }

    height: 74
    padding: 12
    radius: 24
    focused: typebarFocused
    danger: developerMode
    accentColor: root.accentColor

    function setDraft(text) {
        if (input.text !== text)
            input.text = text
    }

    function currentText() {
        return input.text
    }

    Item {
        anchors.fill: parent
        anchors.margins: 12

        Text {
            id: promptText

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(440, Math.max(210, parent.width * 0.34))
            text: (root.timestampVisible ? "[" + root.clockText + "] " : "") + root.promptLabel
            color: root.developerMode ? "#FFD166" : "#27FF9A"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideLeft
            font.family: "monospace"
            font.pixelSize: Math.max(13, root.fontPixelSize - 2)
            font.bold: true
        }

        Rectangle {
            id: promptDivider

            anchors.left: promptText.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height
            color: root.accentColor
            opacity: 0.7
        }

        TextInput {
            id: input

            anchors.left: promptDivider.right
            anchors.leftMargin: 12
            anchors.right: remoteMirrorPill.left
            anchors.rightMargin: 14
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            text: root.draftText
            color: root.textColor
            selectedTextColor: "#02050A"
            selectionColor: root.accentColor
            clip: true
            focus: root.typebarFocused
            font.family: "monospace"
            font.pixelSize: root.fontPixelSize
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Normal
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onTextEdited: root.draftEdited(text)

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitRequested()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Escape) {
                    root.cancelRequested()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Up) {
                    root.moveUpRequested()
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Down) {
                    root.moveDownRequested()
                    event.accepted = true
                    return
                }
            }
        }

        Rectangle {
            id: remoteMirrorPill

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 176
            height: 36
            radius: 18
            color: root.remoteMirrorRunning ? "#0A2A1D" : "#351017"
            border.width: 1
            border.color: root.remoteMirrorRunning ? "#27FF9A" : "#FF3048"

            Text {
                anchors.centerIn: parent
                text: root.remoteMirrorRunning ? "REMOTE MIRROR ON" : "REMOTE MIRROR OFF"
                color: root.remoteMirrorRunning ? "#27FF9A" : "#FF6B78"
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.7
            }
        }
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.bottom: parent.top
        anchors.bottomMargin: 5
        visible: root.actionMessage.length > 0
        text: root.actionMessage
        color: root.actionError ? "#FF6B78" : "#27FF9A"
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.7
        horizontalAlignment: Text.AlignRight
    }
}
