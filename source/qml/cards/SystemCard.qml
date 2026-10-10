import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            SYSTEM CARD
        ============================================================

        Next-generation universal system metric card.

        Purpose:
            - CPU
            - RAM
            - Temperature
            - Boot storage
            - Media storage
            - SSID
            - Local IP
            - Tailscale IP
            - Download
            - Upload
            - Uptime
            - User/status cards

        Compatibility:
            - Does NOT replace SystemBox.qml.
            - Does NOT replace StorageBox.qml.
            - Does NOT replace NetworkBox.qml.
            - This is the newer universal card for Console/SystemOverview.

        Layout rule:
            - Title pinned to top.
            - Main value centered.
            - Secondary text below value.
            - Usage/progress bar near bottom.
            - Optional circular gauge mode.
            - Optional icon/glyph.
            - Warning/critical state supported.
            - Controller focus is blue.
            - Armed/destructive state is red.
    */

    /*
        Data can be passed directly through individual properties or as a map.
        Supported data keys:
            id, title, label, name,
            value, text, displayValue,
            subtitle, subvalue, description,
            percent, usage, progress,
            unit,
            icon, glyph,
            status, state,
            warning, critical,
            color, accent
    */
    property var cardData: null

    property string cardId: valueFor(["id", "key", "metricId"], "")
    property string title: valueFor(["title", "label", "name"], "")
    property string value: valueFor(["value", "text", "displayValue"], "")
    property string subvalue: valueFor(["subvalue", "subtitle", "description"], "")
    property string unit: valueFor(["unit"], "")
    property string glyph: valueFor(["glyph", "iconGlyph"], "")

    property int percent: numberFor(["percent", "usage", "progress"], 0)

    property bool circular: boolFor(["circular", "ring", "gauge"], false)
    property bool showIcon: boolFor(["showIcon"], glyph.length > 0 || cardId.length > 0)
    property bool showPercentText: boolFor(["showPercentText"], percent > 0 || circular)
    property bool showBar: boolFor(["showBar"], !circular)
    property bool compact: boolFor(["compact"], false)
    property bool animationsEnabled: visible && enabled

    property bool warning: boolFor(["warning"], false)
    property bool critical: boolFor(["critical"], false)

    property int warningPercent: 78
    property int criticalPercent: 90

    property color normalAccent: "#7df9ff"
    property color goodAccent: "#22ff88"
    property color warningAccent: "#f5c542"
    property color criticalAccent: "#ff3040"
    property color purpleAccent: "#a855f7"
    property color mutedAccent: "#8aa6c8"
    property color trackColor: "#223355"

    property real pulse: 0.55

    signal activated(var cardData, string cardId)

    accent: activeAccent()

    implicitWidth: compact ? 158 : 184
    implicitHeight: compact ? 116 : 136

    hoverEnabled: false

    onClicked: {
        root.activated(root.cardData, root.cardId)
    }

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function hasValue(v) {
        return v !== undefined &&
               v !== null &&
               String(v).trim().length > 0
    }

    function valueFor(keys, fallbackValue) {
        if (!cardData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                if (hasValue(cardData[key]))
                    return String(cardData[key])
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function numberFor(keys, fallbackValue) {
        if (!cardData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                var raw = cardData[key]

                if (raw === undefined || raw === null)
                    continue

                var n = Number(raw)

                if (!isNaN(n))
                    return n
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function boolFor(keys, fallbackValue) {
        if (!cardData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                var raw = cardData[key]

                if (raw === undefined || raw === null)
                    continue

                if (raw === true)
                    return true

                if (raw === false)
                    return false

                if (typeof raw === "number")
                    return raw !== 0

                var text = String(raw).trim().toLowerCase()

                if (text === "true" ||
                        text === "1" ||
                        text === "yes" ||
                        text === "warning" ||
                        text === "critical" ||
                        text === "active") {
                    return true
                }

                if (text === "false" ||
                        text === "0" ||
                        text === "no" ||
                        text === "normal" ||
                        text === "inactive") {
                    return false
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function clampedPercent() {
        var p = Number(percent)

        if (isNaN(p))
            return 0

        return Math.max(0, Math.min(100, p))
    }

    function statusText() {
        return valueFor(["status", "state"], "")
    }

    function isWarning() {
        return warning || clampedPercent() >= warningPercent
    }

    function isCritical() {
        return critical || armed || clampedPercent() >= criticalPercent
    }

    function activeAccent() {
        if (isCritical())
            return criticalAccent

        if (isWarning())
            return warningAccent

        var custom = valueFor(["accent", "color"], "")

        if (custom.length > 0)
            return custom

        var id = cardId.toLowerCase()

        if (id.indexOf("ram") >= 0)
            return "#9fd8ff"

        if (id.indexOf("temp") >= 0)
            return "#ff8a40"

        if (id.indexOf("storage") >= 0 ||
                id.indexOf("boot") >= 0 ||
                id.indexOf("media") >= 0) {
            return "#c084fc"
        }

        if (id.indexOf("network") >= 0 ||
                id.indexOf("ssid") >= 0 ||
                id.indexOf("ip") >= 0 ||
                id.indexOf("download") >= 0 ||
                id.indexOf("upload") >= 0) {
            return "#22d3ee"
        }

        if (focused)
            return "#4da6ff"

        return normalAccent
    }

    function shownTitle() {
        if (title.length > 0)
            return title.toUpperCase()

        if (cardId.length > 0)
            return cardId.toUpperCase()

        return "SYSTEM"
    }

    function shownValue() {
        if (value.length > 0) {
            if (unit.length > 0 && value.indexOf(unit) < 0)
                return value + " " + unit

            return value
        }

        if (showPercentText)
            return Math.round(clampedPercent()) + "%"

        return "--"
    }

    function shownSubvalue() {
        if (subvalue.length > 0)
            return subvalue

        var state = statusText()

        if (state.length > 0)
            return state

        if (showPercentText && value.length > 0)
            return Math.round(clampedPercent()) + "%"

        return ""
    }

    function glyphForCard() {
        if (glyph.length > 0)
            return glyph

        var id = cardId.toLowerCase()
        var t = title.toLowerCase()

        if (id.indexOf("cpu") >= 0 || t.indexOf("cpu") >= 0)
            return "CPU"

        if (id.indexOf("ram") >= 0 || t.indexOf("ram") >= 0)
            return "RAM"

        if (id.indexOf("temp") >= 0 || t.indexOf("temp") >= 0)
            return "°"

        if (id.indexOf("storage") >= 0 ||
                id.indexOf("boot") >= 0 ||
                id.indexOf("media") >= 0 ||
                t.indexOf("storage") >= 0) {
            return "▣"
        }

        if (id.indexOf("ssid") >= 0 ||
                id.indexOf("network") >= 0 ||
                t.indexOf("network") >= 0) {
            return "⌁"
        }

        if (id.indexOf("download") >= 0)
            return "↓"

        if (id.indexOf("upload") >= 0)
            return "↑"

        if (id.indexOf("ip") >= 0)
            return "IP"

        if (id.indexOf("uptime") >= 0)
            return "⏱"

        if (id.indexOf("user") >= 0)
            return "●"

        return "✦"
    }

    function barWidth() {
        return barTrack.width * clampedPercent() / 100.0
    }

    function handleController(action) {
        if (action === "primary" || action === "x") {
            root.activated(root.cardData, root.cardId)
            return true
        }

        return false
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled &&
                 (root.focused || root.armed || root.isWarning() || root.isCritical())

        loops: Animation.Infinite

        NumberAnimation {
            from: 0.40
            to: 1.0
            duration: root.isCritical() ? 620 : root.isWarning() ? 900 : 1650
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.40
            duration: root.isCritical() ? 620 : root.isWarning() ? 900 : 1650
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            TITLE ROW
        ============================================================
    */

    Row {
        id: titleRow

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: compact ? 8 : 10
        anchors.leftMargin: compact ? 9 : 11
        anchors.rightMargin: compact ? 9 : 11

        height: compact ? 18 : 20
        spacing: 7

        Text {
            visible: root.showIcon

            anchors.verticalCenter: parent.verticalCenter

            width: compact ? 28 : 32

            text: root.glyphForCard()

            color: root.activeAccent()

            font.pixelSize: root.glyphForCard().length > 2 ? 9 : compact ? 14 : 16
            font.bold: true
            font.letterSpacing: 0.5

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight

            opacity: root.focused || root.armed ? 1.0 : 0.86
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width - (root.showIcon ? 39 : 0)

            text: root.shownTitle()

            color: root.activeAccent()

            font.pixelSize: compact ? 11 : 12
            font.bold: true
            font.letterSpacing: 0.9

            horizontalAlignment: root.showIcon ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: root.focused || root.armed ? 1.0 : 0.88
        }
    }

    /*
        ============================================================
                            CIRCULAR GAUGE
        ============================================================
    */

    Canvas {
        id: ring

        visible: root.circular

        anchors.centerIn: parent
        anchors.verticalCenterOffset: compact ? 0 : 2

        width: compact ? 66 : 78
        height: width

        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            var p = root.clampedPercent() / 100.0
            var center = width / 2
            var radius = width * 0.34
            var line = compact ? 6 : 7

            ctx.clearRect(0, 0, width, height)

            ctx.lineWidth = line
            ctx.lineCap = "round"

            ctx.strokeStyle = root.trackColor
            ctx.globalAlpha = 0.88
            ctx.beginPath()
            ctx.arc(center, center, radius, 0, Math.PI * 2)
            ctx.stroke()

            ctx.strokeStyle = root.activeAccent()
            ctx.globalAlpha =
                    root.focused || root.armed || root.isWarning()
                    ? 0.72 + root.pulse * 0.28
                    : 0.92

            ctx.beginPath()
            ctx.arc(center,
                    center,
                    radius,
                    -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * p)
            ctx.stroke()

            if (root.focused || root.armed || root.isCritical()) {
                ctx.lineWidth = 1
                ctx.strokeStyle = root.activeAccent()
                ctx.globalAlpha = root.armed || root.isCritical()
                                  ? 0.36 + root.pulse * 0.26
                                  : 0.22 + root.pulse * 0.20
                ctx.beginPath()
                ctx.arc(center, center, radius + 10, 0, Math.PI * 2)
                ctx.stroke()
            }

            ctx.globalAlpha = 1.0
        }

        Connections {
            target: root

            function onPercentChanged() {
                ring.requestPaint()
            }

            function onFocusedChanged() {
                ring.requestPaint()
            }

            function onArmedChanged() {
                ring.requestPaint()
            }

            function onPulseChanged() {
                if (root.circular)
                    ring.requestPaint()
            }

            function onCircularChanged() {
                ring.requestPaint()
            }

            function onVisibleChanged() {
                if (root.visible)
                    ring.requestPaint()
            }
        }
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
        anchors.verticalCenterOffset: root.circular ? 2 : -3
        anchors.leftMargin: compact ? 10 : 12
        anchors.rightMargin: compact ? 10 : 12

        spacing: compact ? 3 : 5

        Text {
            id: valueText

            width: parent.width

            text: root.shownValue()

            color: root.isCritical() ? "#ffd1d1" : "white"

            font.pixelSize: root.circular
                            ? compact ? 15 : 17
                            : compact ? 17 : 21
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#99000000"
        }

        Text {
            visible: root.shownSubvalue().length > 0 && !root.circular

            width: parent.width

            text: root.shownSubvalue()

            color: root.isCritical() ? "#ffb1b1" :
                   root.isWarning() ? "#ffe19a" :
                                      "#8aa6c8"

            font.pixelSize: compact ? 10 : 11
            font.bold: root.focused || root.armed || root.isWarning()
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.94
        }
    }

    Text {
        visible: root.shownSubvalue().length > 0 && root.circular

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: compact ? 9 : 11

        width: parent.width - 18

        text: root.shownSubvalue()

        color: root.isCritical() ? "#ffb1b1" :
               root.isWarning() ? "#ffe19a" :
                                  "#8aa6c8"

        font.pixelSize: compact ? 10 : 11
        font.bold: root.focused || root.armed || root.isWarning()

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        opacity: 0.94
    }

    /*
        ============================================================
                            LINEAR BAR
        ============================================================
    */

    Item {
        id: barArea

        visible: root.showBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: compact ? 13 : 16
        anchors.rightMargin: compact ? 13 : 16
        anchors.bottomMargin: compact ? 9 : 11

        height: compact ? 16 : 18

        Rectangle {
            id: barTrack

            anchors.left: parent.left
            anchors.right: root.showPercentText ? percentText.left : parent.right
            anchors.rightMargin: root.showPercentText ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter

            height: compact ? 6 : 7
            radius: height / 2

            color: root.trackColor
            opacity: 0.86

            Rectangle {
                id: barFill

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                width: root.barWidth()
                radius: parent.radius

                color: root.activeAccent()

                opacity: root.focused || root.armed || root.isWarning()
                         ? 0.72 + root.pulse * 0.28
                         : 0.92

                Behavior on width {
                    enabled: root.animationsEnabled

                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    enabled: root.animationsEnabled

                    ColorAnimation {
                        duration: 160
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
                border.color: root.activeAccent()

                opacity: root.armed ? 0.58 : 0.34
            }
        }

        Text {
            id: percentText

            visible: root.showPercentText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: Math.round(root.clampedPercent()) + "%"

            color: root.activeAccent()

            font.pixelSize: compact ? 10 : 11
            font.bold: true

            opacity: root.focused || root.armed || root.isWarning()
                     ? 1.0
                     : 0.80
        }
    }

    /*
        ============================================================
                            WARNING / FOCUS OUTLINE
        ============================================================
    */

    Rectangle {
        visible: root.focused || root.armed || root.isWarning() || root.isCritical()

        anchors.fill: parent
        anchors.margins: root.armed || root.isCritical() ? -2 : 0

        radius: root.radius + 2
        color: "transparent"

        border.width: root.armed || root.isCritical() ? 2 : 1
        border.color: root.activeAccent()

        opacity: root.armed || root.isCritical()
                 ? 0.22 + root.pulse * 0.28
                 : root.focused
                   ? 0.16 + root.pulse * 0.20
                   : 0.12 + root.pulse * 0.16
    }

    Component.onCompleted: {
        if (root.circular)
            ring.requestPaint()
    }
}