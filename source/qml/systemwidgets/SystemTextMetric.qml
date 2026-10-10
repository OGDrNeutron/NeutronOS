import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            SYSTEM TEXT METRIC
        ============================================================

        Preserved from original:
            - title property.
            - value property.
            - subtitle property.
            - accent property.
            - Compact text-only metric.
            - Title at top.
            - Main value in middle.
            - Optional subtitle.
            - No MouseArea.
            - No Button.
            - No Canvas.
            - Very lightweight.

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Safe text cleaning.
            - Optional center alignment.
            - Optional compact mode.
            - Optional warning/critical color support.
            - Animation gating for color/opacity only.
            - Better eliding and maximum line counts.
            - Maintains original 220x90 default footprint.
            - No placeholder data.
    */

    property string title: ""
    property string value: "--"
    property string subtitle: ""

    property color accent: "#7df9ff"
    property color valueColor: "white"
    property color subtitleColor: "#8aa6c8"
    property color warningColor: "#facc15"
    property color criticalColor: "#ff3040"

    property bool animationsEnabled: visible && enabled
    property bool centerAligned: false
    property bool compact: false
    property bool warning: false
    property bool critical: false

    property int titleSize: compact ? 12 : 15
    property int valueSize: compact ? 18 : 22
    property int subtitleSize: compact ? 10 : 12

    property color effectiveAccent: critical ? criticalColor :
                                    warning ? warningColor :
                                              accent

    width: 220
    height: compact ? 76 : 90

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        anchors.fill: parent

        spacing: root.compact ? 4 : 6

        Text {
            id: titleText

            width: parent.width

            text: root.displayTitle()

            color: root.effectiveAccent

            horizontalAlignment: root.centerAligned ? Text.AlignHCenter : Text.AlignLeft

            font.pixelSize: root.titleSize
            font.bold: true
            font.letterSpacing: 1

            elide: Text.ElideRight
            maximumLineCount: 1

            Behavior on color {
                enabled: root.animationsEnabled

                ColorAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            id: valueText

            width: parent.width

            text: root.displayValue()

            color: root.critical ? root.criticalColor : root.valueColor

            horizontalAlignment: root.centerAligned ? Text.AlignHCenter : Text.AlignLeft

            font.pixelSize: root.valueSize
            font.bold: true

            elide: Text.ElideRight
            maximumLineCount: 1

            Behavior on color {
                enabled: root.animationsEnabled

                ColorAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            id: subtitleText

            visible: root.displaySubtitle().length > 0

            width: parent.width

            text: root.displaySubtitle()

            color: root.warning || root.critical ? root.effectiveAccent : root.subtitleColor

            horizontalAlignment: root.centerAligned ? Text.AlignHCenter : Text.AlignLeft

            font.pixelSize: root.subtitleSize
            font.bold: root.warning || root.critical

            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: root.enabled ? 1.0 : 0.55

            Behavior on color {
                enabled: root.animationsEnabled

                ColorAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                enabled: root.animationsEnabled

                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function cleanText(input) {
        if (input === undefined || input === null)
            return ""

        var text = String(input).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function displayTitle() {
        return cleanText(title)
    }

    function displayValue() {
        var text = cleanText(value)

        if (text.length <= 0)
            return "--"

        return text
    }

    function displaySubtitle() {
        return cleanText(subtitle)
    }
}