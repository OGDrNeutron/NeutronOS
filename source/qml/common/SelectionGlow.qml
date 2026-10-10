import QtQuick 2.15

Rectangle {
    id: root

    /*
        ============================================================
                            SELECTION GLOW
        ============================================================

        Shared focus/armed outline for NeutronOS cards and tiles.

        Original API preserved:
            - focused
            - armed
            - glowRadius

        Original behavior preserved:
            - Blue ring when focused.
            - Red ring when armed.
            - Transparent when inactive.
            - Outer secondary glow ring.

        Next-gen updates:
            - QtQuick 2.15 explicit import.
            - Optional enabled state.
            - Optional animationsEnabled flag.
            - Safe parent radius fallback.
            - Customizable colors.
            - Customizable margins.
            - Pulse support for cards that want stronger armed/focus glow.
            - No backend dependency.
            - Lightweight rectangles only; no blur/shader.
    */

    property bool focused: false
    property bool armed: false
    property bool glowEnabled: true
    property bool animationsEnabled: visible && glowEnabled

    property real glowRadius: 26
    property real glowMargin: -8
    property real outerGlowMargin: -5
    property real pulse: 0.0

    property color focusedColor: "#4da6ff"
    property color armedColor: "#ff3040"

    property color focusedOuterColor: "#884da6ff"
    property color armedOuterColor: "#88ff3040"

    property int focusedWidth: 2
    property int armedWidth: 3
    property int focusedOuterWidth: 1
    property int armedOuterWidth: 2

    anchors.margins: glowMargin

    radius: parent ? parent.radius + Math.abs(glowMargin) : glowRadius

    color: "transparent"

    visible: glowEnabled && (focused || armed || opacity > 0.0)

    border.width: !glowEnabled ? 0 :
                  armed ? armedWidth :
                  focused ? focusedWidth :
                            0

    border.color: !glowEnabled ? "transparent" :
                  armed ? armedColor :
                  focused ? focusedColor :
                            "transparent"

    opacity: !glowEnabled ? 0.0 :
             armed ? Math.min(1.0, 0.90 + pulse * 0.10) :
             focused ? Math.min(1.0, 0.68 + pulse * 0.18) :
                       0.0

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: root.armed ? 110 : 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
        enabled: root.animationsEnabled

        ColorAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.width {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: outerRing

        anchors.fill: parent
        anchors.margins: root.outerGlowMargin

        radius: parent.radius + Math.abs(root.outerGlowMargin)
        color: "transparent"

        border.width: !root.glowEnabled ? 0 :
                      root.armed ? root.armedOuterWidth :
                      root.focused ? root.focusedOuterWidth :
                                     0

        border.color: !root.glowEnabled ? "transparent" :
                      root.armed ? root.armedOuterColor :
                      root.focused ? root.focusedOuterColor :
                                     "transparent"

        opacity: !root.glowEnabled ? 0.0 :
                 root.armed ? Math.min(1.0, 0.66 + root.pulse * 0.20) :
                 root.focused ? Math.min(1.0, 0.46 + root.pulse * 0.18) :
                                0.0

        Behavior on opacity {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: root.armed ? 110 : 160
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.width {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }
}