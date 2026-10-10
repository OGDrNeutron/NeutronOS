import QtQuick 2.15
import "."

Rectangle {
    id: root

    /*
        ============================================================
                            GLASS CARD
        ============================================================

        Shared base card for NeutronOS.

        Original API preserved:
            property accent
            property focused
            property armed
            property hoverEnabled
            signal clicked()
            SelectionGlow child

        Next-gen updates:
            - Controller-first safe base.
            - Mouse/touch remains optional for preview/testing.
            - No forced mouse assumptions.
            - Disabled state support.
            - Pressed visual state.
            - Hover focus can be disabled independently.
            - Animation pauses when hidden/disabled.
            - Safe colors for focus/armed/disabled.
            - Shared radius/border/scale behavior for cards, tiles, widgets.
            - Does not replace SelectionGlow.
            - Does not require any backend manager.
    */

    property color accent: "#7df9ff"

    /*
        These are intentionally custom properties.
        Do not rename them to focus/focusScope because many cards already bind:
            focused: ...
            armed: ...
    */
    property bool focused: false
    property bool armed: false

    /*
        Original property preserved.
        Existing files can still do:
            hoverEnabled: false
    */
    property bool hoverEnabled: true

    /*
        Controller-first rule:
        Mouse/touch is only for preview/testing or optional touch use.
        It must never be required.
    */
    property bool pointerEnabled: true

    /*
        If true, hover changes root.focused.
        Kept true for compatibility with the original GlassCard behavior.
        Controller-first screens can set:
            hoverEnabled: false
        or:
            pointerFocusEnabled: false
    */
    property bool pointerFocusEnabled: true

    property bool pressFeedbackEnabled: true
    property bool animationsEnabled: visible && enabled

    property bool pressed: false

    property color normalColor: "#111d3aaa"
    property color focusedColor: "#132957dd"
    property color armedColor: "#201020dd"
    property color disabledColor: "#07101faa"

    property color normalBorderColor: accent
    property color focusedBorderColor: "#4da6ff"
    property color armedBorderColor: "#ff3040"
    property color disabledBorderColor: "#334155"

    property real normalScale: 1.0
    property real focusedScale: 1.025
    property real armedScale: 1.045
    property real pressedScale: 0.985

    property int normalBorderWidth: 1
    property int focusedBorderWidth: 2
    property int armedBorderWidth: 3

    property real disabledOpacity: 0.52
    property real normalOpacity: 1.0

    signal clicked()

    radius: 20
    clip: false

    color: !enabled ? disabledColor :
           armed ? armedColor :
           focused ? focusedColor :
                     normalColor

    opacity: enabled ? normalOpacity : disabledOpacity

    border.width: !enabled ? normalBorderWidth :
                  armed ? armedBorderWidth :
                  focused ? focusedBorderWidth :
                            normalBorderWidth

    border.color: !enabled ? disabledBorderColor :
                  armed ? armedBorderColor :
                  focused ? focusedBorderColor :
                            normalBorderColor

    scale: pressed && pressFeedbackEnabled ? pressedScale :
           armed ? armedScale :
           focused ? focusedScale :
                     normalScale

    /*
        Smooth shared transitions.
        Behaviors are disabled when hidden/unloaded so inactive screens do not
        waste resources.
    */
    Behavior on scale {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 160
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

    Behavior on border.color {
        enabled: root.animationsEnabled

        ColorAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    /*
        Original SelectionGlow preserved.
        This is the shared blue focus / red armed glow.
    */
    SelectionGlow {
        id: selectionGlow

        anchors.fill: parent

        focused: root.enabled && root.focused
        armed: root.enabled && root.armed

        visible: root.visible && root.enabled && (root.focused || root.armed)
    }

    /*
        Subtle glass highlight.
        Kept lightweight: simple rectangles only, no expensive blur/shader.
    */
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: Math.max(1, parent.height * 0.34)
        radius: root.radius

        color: "#ffffff"
        opacity: root.enabled
                 ? root.armed
                   ? 0.035
                   : root.focused
                     ? 0.050
                     : 0.030
                 : 0.012

        visible: root.visible
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: 1

        color: "#ffffff"
        opacity: root.enabled ? 0.18 : 0.06
    }

    /*
        Optional pointer/touch support.

        Controller-first screens do not rely on this.
        This remains for:
            - desktop previews
            - quick testing
            - optional touch
            - old dashboard compatibility
    */
    MouseArea {
        id: pointerArea

        anchors.fill: parent

        enabled: root.enabled && root.pointerEnabled
        hoverEnabled: root.hoverEnabled

        acceptedButtons: Qt.LeftButton

        onEntered: {
            if (root.pointerFocusEnabled && root.hoverEnabled)
                root.focused = true
        }

        onExited: {
            if (root.pointerFocusEnabled && root.hoverEnabled)
                root.focused = false

            root.pressed = false
        }

        onPressed: {
            root.pressed = true
        }

        onReleased: {
            root.pressed = false
        }

        onCanceled: {
            root.pressed = false
        }

        onClicked: {
            if (root.enabled)
                root.clicked()
        }
    }

    /*
        Shared controller helper.
        Child cards can override or ignore this.
    */
    function activate() {
        if (!root.enabled)
            return false

        root.clicked()
        return true
    }

    function handleController(action) {
        if (!root.enabled)
            return false

        if (action === "primary" || action === "x") {
            return root.activate()
        }

        return false
    }

    onEnabledChanged: {
        if (!enabled)
            pressed = false
    }

    onVisibleChanged: {
        if (!visible)
            pressed = false
    }
}