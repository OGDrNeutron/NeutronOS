import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            STORAGE BOX
        ============================================================

        Used by SystemOverview for:
            - Boot storage
            - Media/HDD storage
            - Mount cards

        Preserved from original:
            - title
            - value
            - percent bar
            - GlassCard focus/armed styling

        Next-gen updates:
            - Title stays pinned to top of box.
            - Main value stays centered.
            - Usage bar stays below value.
            - Warning color when storage is high.
            - Critical color when storage is very high.
            - Safe clamping for bad backend values.
            - Optional subtitle/mount label.
            - Optional compact mode.
            - Animation pauses when hidden.
            - No placeholder behavior.
    */

    property string title: ""
    property string value: ""
    property string subvalue: ""

    /*
        percent is expected as 0..100.
        Bad backend values are clamped safely.
    */
    property int percent: 0

    property bool compact: false
    property bool showPercentText: true
    property bool showSubvalue: subvalue.length > 0
    property bool animationsEnabled: visible && enabled

    property int warningPercent: 78
    property int criticalPercent: 90

    property color normalColor: root.accent
    property color focusedColor: "#4da6ff"
    property color warningColor: "#f5c542"
    property color criticalColor: "#ff3040"
    property color trackColor: "#223355"

    property real pulse: 0.55

    implicitWidth: compact ? 150 : 180
    implicitHeight: compact ? 104 : 126

    function clampedPercent() {
        var p = Number(percent)

        if (isNaN(p))
            return 0

        return Math.max(0, Math.min(100, p))
    }

    function usageColor() {
        var p = clampedPercent()

        if (root.armed || p >= criticalPercent)
            return criticalColor

        if (p >= warningPercent)
            return warningColor

        if (root.focused)
            return focusedColor

        return normalColor
    }

    function percentText() {
        return Math.round(clampedPercent()) + "%"
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled &&
                 (root.focused || root.armed || root.clampedPercent() >= root.warningPercent)

        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: root.armed || root.clampedPercent() >= root.criticalPercent ? 650 : 1600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: root.armed || root.clampedPercent() >= root.criticalPercent ? 650 : 1600
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            TITLE
        ============================================================
    */

    Text {
        id: titleText

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: compact ? 8 : 10

        width: parent.width - 18

        text: root.title

        color: root.usageColor()

        font.pixelSize: compact ? 12 : 13
        font.bold: true
        font.letterSpacing: 0.7

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        opacity: root.focused || root.armed ? 1.0 : 0.88
    }

    /*
        ============================================================
                            CENTER VALUE
        ============================================================
    */

    Column {
        id: centerContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: compact ? 0 : -2
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        spacing: compact ? 3 : 5

        Text {
            width: parent.width

            text: root.value.length > 0 ? root.value : "--"

            color: "white"

            font.pixelSize: compact ? 15 : 17
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#90000000"
        }

        Text {
            visible: root.showSubvalue

            width: parent.width

            text: root.subvalue

            color: "#8aa6c8"

            font.pixelSize: compact ? 10 : 11
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.92
        }
    }

    /*
        ============================================================
                            USAGE BAR
        ============================================================
    */

    Item {
        id: barArea

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: compact ? 14 : 16
        anchors.rightMargin: compact ? 14 : 16
        anchors.bottomMargin: compact ? 10 : 12

        height: compact ? 18 : 22

        Rectangle {
            id: barTrack

            anchors.left: parent.left
            anchors.right: root.showPercentText ? percentLabel.left : parent.right
            anchors.rightMargin: root.showPercentText ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter

            height: compact ? 6 : 7
            radius: height / 2

            color: root.trackColor
            opacity: 0.88

            Rectangle {
                id: barFill

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                width: parent.width * root.clampedPercent() / 100.0
                radius: parent.radius

                color: root.usageColor()

                opacity: root.armed ||
                         root.focused ||
                         root.clampedPercent() >= root.warningPercent
                         ? 0.72 + root.pulse * 0.28
                         : 0.92

                Behavior on width {
                    enabled: root.animationsEnabled

                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    enabled: root.animationsEnabled

                    ColorAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                visible: root.focused || root.armed

                anchors.fill: parent
                radius: parent.radius
                color: "transparent"

                border.width: 1
                border.color: root.usageColor()

                opacity: root.armed ? 0.58 : 0.38
            }
        }

        Text {
            id: percentLabel

            visible: root.showPercentText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: root.percentText()

            color: root.usageColor()

            font.pixelSize: compact ? 10 : 11
            font.bold: true

            opacity: root.focused ||
                     root.armed ||
                     root.clampedPercent() >= root.warningPercent
                     ? 1.0
                     : 0.82
        }
    }

    /*
        ============================================================
                            WARNING GLOW
        ============================================================
    */

    Rectangle {
        visible: root.clampedPercent() >= root.warningPercent || root.armed

        anchors.fill: parent
        anchors.margins: root.armed ? -2 : 0

        radius: root.radius + 2

        color: "transparent"

        border.width: root.armed || root.clampedPercent() >= root.criticalPercent ? 2 : 1
        border.color: root.usageColor()

        opacity: root.armed ||
                 root.clampedPercent() >= root.criticalPercent
                 ? 0.22 + root.pulse * 0.28
                 : 0.16 + root.pulse * 0.18
    }
}