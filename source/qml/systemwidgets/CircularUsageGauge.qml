import QtQuick 2.15

Item {
    id: root

    /*
        Patch 16B resource gauge.

        Performance rules:
          - No Canvas.
          - No shader effects.
          - No continuous animation clock.
          - Forty static scene-graph segments.
          - Only the displayed value animates when telemetry changes.
          - Animation is disabled whenever the gauge is hidden or disabled.
    */

    property real value: 0
    property string label: "RESOURCE"
    property string detail: "LIVE TELEMETRY"
    property color primaryColor: "#7df9ff"
    property color secondaryColor: "#4da6ff"
    property color warningColor: "#f5c542"
    property color dangerColor: "#ff3040"
    property color trackColor: "#203047"
    property color textColor: "#ffffff"
    property color mutedTextColor: "#8aa6c8"
    property bool animationsEnabled: visible && enabled
    property int segmentCount: 40

    property real displayedValue: 0

    readonly property real safeValue: clampPercent(displayedValue)
    readonly property int activeSegments:
        Math.round((safeValue / 100.0) * segmentCount)
    readonly property color liveColor:
        safeValue >= 90 ? dangerColor
                        : (safeValue >= 70 ? warningColor : primaryColor)

    implicitWidth: 190
    implicitHeight: 190

    function clampPercent(inputValue) {
        var numeric = Number(inputValue)
        if (isNaN(numeric))
            numeric = 0
        return Math.max(0, Math.min(100, numeric))
    }

    function mixedColor(first, second, amount) {
        var ratio = Math.max(0, Math.min(1, Number(amount)))
        return Qt.rgba(
                    first.r + (second.r - first.r) * ratio,
                    first.g + (second.g - first.g) * ratio,
                    first.b + (second.b - first.b) * ratio,
                    1.0)
    }

    function segmentColor(segmentIndex) {
        if (safeValue >= 90)
            return mixedColor(warningColor, dangerColor,
                              segmentIndex / Math.max(1, segmentCount - 1))
        if (safeValue >= 70)
            return mixedColor(primaryColor, warningColor,
                              segmentIndex / Math.max(1, segmentCount - 1))
        return mixedColor(primaryColor, secondaryColor,
                          segmentIndex / Math.max(1, segmentCount - 1))
    }

    function statusText() {
        if (safeValue >= 90)
            return "CRITICAL"
        if (safeValue >= 70)
            return "ELEVATED"
        if (safeValue >= 45)
            return "ACTIVE"
        return "STABLE"
    }

    onValueChanged: displayedValue = clampPercent(value)

    Component.onCompleted: displayedValue = clampPercent(value)

    Behavior on displayedValue {
        enabled: root.animationsEnabled
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#071426"
        border.width: 1
        border.color: "#294d72"
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.77
        height: width
        radius: width / 2
        color: "#050d18"
        border.width: 1
        border.color: Qt.rgba(root.liveColor.r,
                              root.liveColor.g,
                              root.liveColor.b,
                              0.55)
    }

    Repeater {
        model: root.segmentCount

        delegate: Item {
            required property int index
            anchors.fill: parent
            rotation: index * (360.0 / root.segmentCount)
            transformOrigin: Item.Center

            readonly property bool segmentActive:
                index < root.activeSegments

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 5
                width: 7
                height: 17
                radius: 3.5
                color: parent.segmentActive
                       ? root.segmentColor(parent.index)
                       : root.trackColor
                opacity: parent.segmentActive ? 1.0 : 0.30
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 3
                width: 11
                height: 21
                radius: 5.5
                color: parent.segmentActive
                       ? root.segmentColor(parent.index)
                       : "transparent"
                opacity: parent.segmentActive ? 0.14 : 0.0
                z: -1
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.64
        spacing: 3

        Text {
            width: parent.width
            text: Math.round(root.safeValue) + "%"
            color: root.liveColor
            font.pixelSize: 36
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.label
            color: root.textColor
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 1.1
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.statusText()
            color: root.liveColor
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.8
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: root.detail
            color: root.mutedTextColor
            font.pixelSize: 9
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
