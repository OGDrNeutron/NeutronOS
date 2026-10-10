import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE SIDEBAR ITEM
        ============================================================

        Sidebar row.

        Supports:
        - section headers
        - selectable places
        - focused blue state
        - danger/red places like Trash
        - no mouse assumptions
    */

    width: parent ? parent.width : 240
    height: headerItem ? 34 : 58

    property string title: ""
    property string subtitle: ""
    property string iconText: "•"
    property string kind: "place"

    property bool headerItem: false
    property bool enabledItem: true
    property bool selected: false
    property bool focused: false
    property bool danger: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color dangerRed: "#FF3040"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real pulse: 0.35

    SequentialAnimation on pulse {
        running: root.visible && root.enabledItem && root.focused && root.selected && !root.headerItem
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1200
            easing.type: Easing.InOutQuad
        }
    }

    /*
        ============================================================
                            HEADER ROW
        ============================================================
    */

    Text {
        visible: root.headerItem

        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: root.title

        color: root.textMuted

        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.7

        opacity: 0.78
    }

    /*
        ============================================================
                            PLACE ROW
        ============================================================
    */

    Rectangle {
        visible: !root.headerItem

        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        anchors.topMargin: 4
        anchors.bottomMargin: 4

        radius: 18

        color: root.selected
               ? (root.danger ? "#2A0A10E8" : "#104D86E8")
               : "transparent"

        border.width: root.focused && root.selected ? 2 : root.selected ? 1 : 0
        border.color: root.danger ? root.dangerRed : root.focusBlue

        opacity: root.enabledItem ? 1.0 : 0.36

        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 130
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            visible: root.selected

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.042
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            visible: root.selected

            height: 1

            color: "#FFFFFF"
            opacity: 0.20
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            visible: root.selected

            width: 4
            radius: 2

            color: root.danger ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.70 + root.pulse * 0.30 : 0.46
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            visible: root.selected

            y: -34

            width: parent.width * 0.70
            height: 62
            radius: 31

            color: root.danger ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.050 + root.pulse * 0.060 : 0.028
        }
    }

    Row {
        visible: !root.headerItem

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        anchors.leftMargin: 12
        anchors.rightMargin: 10

        spacing: 12

        Rectangle {
            width: 34
            height: 34
            radius: 12

            anchors.verticalCenter: parent.verticalCenter

            color: root.selected
                   ? (root.danger ? "#3A1116" : "#071426")
                   : "#071426AA"

            border.width: root.selected ? 1 : 0
            border.color: root.danger ? root.dangerRed : root.focusBlue

            opacity: root.enabledItem ? 1.0 : 0.42

            Text {
                anchors.centerIn: parent

                text: root.iconText

                color: root.danger
                       ? "#FFD1D1"
                       : root.selected
                         ? "#FFFFFF"
                         : root.textSecondary

                font.pixelSize: 17
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 54
            spacing: 1

            Text {
                width: parent.width

                text: root.title

                color: root.enabledItem
                       ? root.selected
                         ? "#FFFFFF"
                         : root.textPrimary
                       : root.textMuted

                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 0.3

                elide: Text.ElideRight

                opacity: root.enabledItem ? 1.0 : 0.52
            }

            Text {
                width: parent.width

                visible: root.subtitle.length > 0

                text: root.subtitle

                color: root.selected ? root.textSecondary : root.textMuted

                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.4

                elide: Text.ElideRight

                opacity: root.enabledItem ? 0.78 : 0.38
            }
        }
    }
}