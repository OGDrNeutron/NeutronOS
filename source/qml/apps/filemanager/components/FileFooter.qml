import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE FOOTER
        ============================================================

        Bottom status strip.

        Required layout:
        - Bottom left:   FileManager V1.0
        - Center:        Secure.Local.Yours
        - Bottom right:  PoweredByNeutronOS

        Extra live status:
        - Current path
        - Item count
        - Armed/selected file name
        - Busy/error state

        Controller:
        - Visual only.
        - No focus target.
        - No mouse assumptions.
    */

    height: 58

    property string currentPath: "/home/echo"
    property int itemCount: 0
    property string selectedFileName: ""
    property string secureText: "Secure.Local.Yours"
    property bool busy: false
    property string errorText: ""
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

    property real glowPulse: 0.35
    property real busyPulse: 0.0
    property real sweep: -1.0

    SequentialAnimation on glowPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 2600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 2600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on busyPulse {
        running: root.busy
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: 700
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: 700
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3800
            easing.type: Easing.InOutSine
        }
    }

    function statusText() {
        if (errorText.length > 0)
            return errorText

        if (busy)
            return "Working..."

        if (armed && selectedFileName.length > 0)
            return "Armed: " + selectedFileName

        if (selectedFileName.length > 0)
            return selectedFileName

        return itemCount + " items"
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 24

        color: "#061A2ED2"

        border.width: 1
        border.color: root.errorText.length > 0
                      ? root.dangerRed
                      : root.armed
                        ? root.dangerRed
                        : "#2A8DCC"

        clip: true

        Behavior on border.color {
            ColorAnimation {
                duration: 160
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.030
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: 0.16
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            y: parent.height - 18

            width: parent.width * 0.58
            height: 70
            radius: 35

            color: root.armed ? root.dangerRed : root.focusBlue
            opacity: root.armed
                     ? 0.024 + root.glowPulse * 0.026
                     : 0.018 + root.glowPulse * 0.020
        }

        Rectangle {
            width: 160
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.top: parent.top

            color: root.errorText.length > 0
                   ? root.dangerRed
                   : root.armed
                     ? root.dangerRed
                     : root.focusBlue

            opacity: root.busy ? 0.34 + root.busyPulse * 0.30
                               : 0.18 + root.glowPulse * 0.12
        }
    }

    /*
        ============================================================
                            LEFT BRAND
        ============================================================
    */

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter

        spacing: 10

        Rectangle {
            width: 10
            height: 10
            radius: 5

            anchors.verticalCenter: parent.verticalCenter

            color: root.errorText.length > 0
                   ? root.dangerRed
                   : root.busy
                     ? root.warningYellow
                     : root.greenAccent

            opacity: root.busy ? 0.60 + root.busyPulse * 0.40
                               : 0.74 + root.glowPulse * 0.20
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "FileManager V1.0"

            color: root.textPrimary

            font.pixelSize: 14
            font.bold: true
            font.letterSpacing: 1.1
        }
    }

    /*
        ============================================================
                            CENTER BRAND STATEMENT
        ============================================================
    */

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        width: centerText.implicitWidth + 44
        height: 32
        radius: 16

        color: "#071426CC"

        border.width: 1
        border.color: root.focusBlue

        opacity: 0.92

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.026
        }

        Text {
            id: centerText

            anchors.centerIn: parent

            text: "Secure.Local.Yours"

            color: root.textSecondary

            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 1.5
        }
    }

    /*
        ============================================================
                            RIGHT POWERED BY
        ============================================================
    */

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter

        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "PoweredByNeutronOS"

            color: root.textSecondary

            font.pixelSize: 14
            font.bold: true
            font.letterSpacing: 1.0
        }

        Rectangle {
            width: 34
            height: 22
            radius: 11

            anchors.verticalCenter: parent.verticalCenter

            color: "#071426CC"

            border.width: 1
            border.color: root.focusBlue

            Text {
                anchors.centerIn: parent

                text: "OS"

                color: root.focusBlue

                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.0
            }
        }
    }

    /*
        ============================================================
                            LIVE STATUS FLOAT
        ============================================================
    */

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -20

        width: Math.min(parent.width * 0.42, liveStatusText.implicitWidth + 42)
        height: 30
        radius: 15

        visible: root.busy ||
                 root.errorText.length > 0 ||
                 root.armed ||
                 root.selectedFileName.length > 0

        color: root.errorText.length > 0
               ? "#2A0A10E8"
               : root.armed
                 ? "#2A0A10E8"
                 : "#071426E8"

        border.width: 1
        border.color: root.errorText.length > 0
                      ? root.dangerRed
                      : root.armed
                        ? root.dangerRed
                        : root.focusBlue

        opacity: 0.96

        clip: true

        Text {
            id: liveStatusText

            anchors.centerIn: parent

            width: parent.width - 24

            text: root.statusText()

            color: root.errorText.length > 0 || root.armed
                   ? "#FFD1D1"
                   : root.textSecondary

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 0.8

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
        }
    }
}