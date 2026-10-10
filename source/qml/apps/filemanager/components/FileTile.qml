import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE TILE
        ============================================================

        Icon/grid tile.

        Controller behavior:
        - Visual only.
        - FileGrid owns selection.
        - Main.qml owns X/O action flow.

        States:
        - focused = blue navigation focus
        - selected = current cursor item
        - armed = X-selected item for action
    */

    width: 142
    height: 162

    property string name: "Untitled"
    property string path: ""
    property string kind: "file"
    property string extension: ""
    property string sizeText: ""
    property string modified: ""
    property string preview: ""
    property string icon: ""

    property bool isDirectory: false
    property bool selected: false
    property bool focused: false
    property bool armed: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"
    property color warningYellow: "#FFD166"

    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real pulse: 0.35
    property real floatOffset: 0

    SequentialAnimation on pulse {
        running: root.visible && (root.focused || root.armed)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: root.armed ? 850 : 1250
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: root.armed ? 850 : 1250
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on floatOffset {
        running: root.visible && root.focused
        loops: Animation.Infinite

        NumberAnimation {
            from: -2
            to: 2
            duration: 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 2
            to: -2
            duration: 1800
            easing.type: Easing.InOutSine
        }
    }

    function iconTextForKind() {
        if (root.icon.length > 0)
            return root.icon

        var k = String(root.kind || "").toLowerCase()
        var ext = String(root.extension || "").toLowerCase()

        if (root.isDirectory || k === "folder")
            return "▰"

        if (k === "video")
            return "▶"

        if (k === "image")
            return "◫"

        if (k === "audio")
            return "♫"

        if (k === "archive")
            return "ZIP"

        if (k === "disk")
            return "ISO"

        if (k === "code")
            return "{ }"

        if (k === "document")
            return "≡"

        if (ext.length > 0)
            return ext.toUpperCase().substring(0, 4)

        return "•"
    }

    function accentForKind() {
        var k = String(root.kind || "").toLowerCase()

        if (root.armed)
            return root.dangerRed

        if (root.isDirectory || k === "folder")
            return root.focusBlue

        if (k === "video")
            return root.purpleGlow

        if (k === "image")
            return "#38BDF8"

        if (k === "audio")
            return root.greenAccent

        if (k === "archive")
            return root.warningYellow

        if (k === "disk")
            return "#C084FC"

        if (k === "code")
            return "#4DA6FF"

        if (k === "document")
            return "#A7EEFF"

        return root.textSecondary
    }

    function kindLabel() {
        var k = String(root.kind || "file").toUpperCase()

        if (root.isDirectory || k === "FOLDER")
            return "FOLDER"

        if (root.extension.length > 0)
            return root.extension.toUpperCase()

        return k
    }

    scale: root.focused ? 1.055 : 1.0
    y: root.focused ? floatOffset : 0

    Behavior on scale {
        NumberAnimation {
            duration: 145
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            SHADOW / GLOW
        ============================================================
    */

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2

        width: root.focused ? 112 : 92
        height: root.focused ? 18 : 12
        radius: height / 2

        color: root.armed ? root.dangerRed : root.focusBlue

        opacity: root.focused || root.armed
                 ? 0.070 + root.pulse * 0.070
                 : 0.018
    }

    Rectangle {
        visible: root.focused || root.armed

        anchors.centerIn: iconShell

        width: iconShell.width + 28
        height: iconShell.height + 28
        radius: 28

        color: root.armed ? root.dangerRed : accentForKind()

        opacity: root.armed
                 ? 0.080 + root.pulse * 0.080
                 : 0.050 + root.pulse * 0.050
    }

    /*
        ============================================================
                            TILE SHELL
        ============================================================
    */

    Rectangle {
        id: tileShell

        anchors.fill: parent

        radius: 24

        color: root.armed
               ? "#2A0A10E8"
               : root.focused
                 ? "#104D86E8"
                 : root.selected
                   ? "#082B55CC"
                   : "#071426AA"

        border.width: root.armed || root.focused ? 2 : root.selected ? 1 : 0
        border.color: root.armed
                      ? root.dangerRed
                      : root.focused
                        ? root.focusBlue
                        : "#2A8DCC"

        opacity: 0.98

        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: root.focused || root.armed ? 0.052 : 0.028
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: root.focused || root.armed ? 0.24 : 0.12
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -48

            width: parent.width * 0.82
            height: 84
            radius: 42

            color: root.armed ? root.dangerRed : accentForKind()

            opacity: root.focused || root.armed
                     ? 0.060 + root.pulse * 0.060
                     : 0.020
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            visible: root.armed || root.focused

            width: root.armed ? 5 : 3
            radius: width / 2

            color: root.armed ? root.dangerRed : root.focusBlue
            opacity: root.armed ? 0.90 : 0.62
        }
    }

    /*
        ============================================================
                            ICON / PREVIEW
        ============================================================
    */

    Rectangle {
        id: iconShell

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16

        width: 86
        height: 76
        radius: 22

        color: root.isDirectory || String(root.kind).toLowerCase() === "folder"
               ? "#0E3D66E8"
               : "#061A2EE0"

        border.width: 1
        border.color: root.armed ? root.dangerRed : accentForKind()

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.040
        }

        Rectangle {
            visible: root.isDirectory || String(root.kind).toLowerCase() === "folder"

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 13
            anchors.topMargin: 10

            width: 34
            height: 12
            radius: 6

            color: accentForKind()
            opacity: 0.74
        }

        Rectangle {
            visible: root.isDirectory || String(root.kind).toLowerCase() === "folder"

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            anchors.bottomMargin: 11

            height: 42
            radius: 12

            color: accentForKind()
            opacity: 0.42
        }

        Text {
            anchors.centerIn: parent

            anchors.verticalCenterOffset: root.isDirectory || String(root.kind).toLowerCase() === "folder"
                                   ? 8
                                   : 0

            text: iconTextForKind()

            color: root.armed ? "#FFD1D1" : "#FFFFFF"

            font.pixelSize: {
                var value = iconTextForKind()
                if (value.length >= 4)
                    return 18
                if (value.length >= 3)
                    return 20
                return root.isDirectory ? 32 : 30
            }

            font.bold: true
            font.letterSpacing: iconTextForKind().length > 2 ? 0.5 : 0

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            style: Text.Raised
            styleColor: "#66000000"
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6

            width: parent.width * 0.40
            height: 2
            radius: 1

            color: root.armed ? root.dangerRed : accentForKind()

            opacity: root.focused || root.armed
                     ? 0.44 + root.pulse * 0.32
                     : 0.18
        }
    }

    /*
        ============================================================
                            LABELS
        ============================================================
    */

    Text {
        id: nameText

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: iconShell.bottom
        anchors.topMargin: 12

        anchors.leftMargin: 10
        anchors.rightMargin: 10

        text: root.name

        color: root.armed ? "#FFD1D1" : root.textPrimary

        font.pixelSize: 14
        font.bold: true

        horizontalAlignment: Text.AlignHCenter

        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: nameText.bottom
        anchors.topMargin: 6

        spacing: 6

        Rectangle {
            width: Math.max(38, kindText.implicitWidth + 14)
            height: 20
            radius: 10

            color: root.armed ? "#3A1116" : "#061A2EDD"

            border.width: 1
            border.color: root.armed ? root.dangerRed : accentForKind()

            opacity: 0.90

            Text {
                id: kindText

                anchors.centerIn: parent

                text: kindLabel()

                color: root.armed ? "#FFD1D1" : root.textSecondary

                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.7
            }
        }

        Text {
            visible: root.sizeText.length > 0 && !root.isDirectory

            anchors.verticalCenter: parent.verticalCenter

            text: root.sizeText

            color: root.textMuted

            font.pixelSize: 9
            font.bold: true

            opacity: 0.78
        }
    }

    /*
        ============================================================
                            FOCUS RING
        ============================================================
    */

    Rectangle {
        visible: root.focused

        anchors.fill: parent
        anchors.margins: -5

        radius: tileShell.radius + 5

        color: "transparent"

        border.width: 1
        border.color: root.armed ? root.dangerRed : root.focusBlue

        opacity: 0.40 + root.pulse * 0.30
    }

    Rectangle {
        visible: root.armed

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 8
        anchors.topMargin: 8

        width: 24
        height: 24
        radius: 12

        color: "#3A1116"

        border.width: 1
        border.color: root.dangerRed

        Text {
            anchors.centerIn: parent

            text: "!"

            color: "#FFD1D1"

            font.pixelSize: 15
            font.bold: true
        }
    }
}