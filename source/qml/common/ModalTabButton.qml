import QtQuick 2.15

Rectangle {
    id: root

    /*
        ============================================================
                            MODAL TAB BUTTON
        ============================================================

        Shared button used inside:
            - AppModal.qml
            - QuickActionModal.qml
            - SystemModal.qml
            - UserModal.qml

        Original API preserved:
            - text
            - subtext
            - focused
            - armed
            - danger
            - accent
            - clicked()

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Controller-first safe activate()/handleController().
            - Mouse/touch remains optional for preview/testing.
            - Does not force mouse assumptions.
            - Disabled state.
            - Pressed state.
            - Selected/active alias-style support without breaking armed.
            - Animations pause when hidden.
            - Danger remains red.
            - Focus remains blue.
            - Armed remains red.
            - No backend dependency.
    */

    property string text: ""
    property string subtext: ""

    property bool focused: false
    property bool armed: false
    property bool danger: false
    property bool active: false
    property bool selected: armed || active

    property bool hoverEnabled: true
    property bool pointerEnabled: true
    property bool pointerFocusEnabled: true
    property bool pressFeedbackEnabled: true

    /*
        Kept off by default so externally-bound `armed:` expressions from
        modals are not overwritten by pointer clicks.
        Set true only for standalone preview buttons if needed.
    */
    property bool autoArmOnClick: false

    property bool pressed: false
    property bool animationsEnabled: visible && enabled

    property color accent: danger ? "#ff3040" : "#7df9ff"
    property color focusedAccent: "#4da6ff"
    property color armedAccent: "#ff3040"
    property color disabledAccent: "#66758a"

    property color normalColor: "#111d3add"
    property color focusedColor: "#132957ee"
    property color armedColor: "#2a1016ee"
    property color disabledColor: "#07101faa"

    property real pulse: 0.55

    signal clicked()

    width: 260
    height: 64
    radius: 18

    color: !enabled ? disabledColor :
           armed ? armedColor :
           focused || active ? focusedColor :
                                normalColor

    opacity: enabled ? 1.0 : 0.52

    border.width: !enabled ? 1 :
                  armed ? 3 :
                  focused || active ? 2 :
                                      1

    border.color: !enabled ? disabledAccent :
                  armed ? armedAccent :
                  focused || active ? focusedAccent :
                                      accent

    scale: pressed && pressFeedbackEnabled ? 0.985 :
           armed ? 1.04 :
           focused || active ? 1.02 :
                               1.0

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    Behavior on scale {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on color {
        enabled: root.animationsEnabled

        ColorAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
        enabled: root.animationsEnabled

        ColorAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || root.armed || root.active)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: root.armed ? 620 : 1500
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: root.armed ? 620 : 1500
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            VISUAL LAYERS
        ============================================================
    */

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.armed ? -4 : root.focused || root.active ? -3 : 0

        radius: root.radius + 4
        color: "transparent"

        border.width: root.armed ? 2 :
                      root.focused || root.active ? 1 :
                                                    0

        border.color: root.armed ? root.armedAccent :
                      root.focused || root.active ? root.focusedAccent :
                                                    "transparent"

        opacity: root.armed ? 0.28 + root.pulse * 0.24 :
                 root.focused || root.active ? 0.18 + root.pulse * 0.18 :
                                                0.0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        height: Math.max(1, parent.height * 0.38)
        radius: root.radius

        color: "#ffffff"
        opacity: root.enabled ? 0.035 : 0.012
    }

    Rectangle {
        visible: root.danger || root.armed

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: root.armed ? 5 : 3
        radius: height / 2

        color: root.armedAccent
        opacity: root.armed ? 0.68 + root.pulse * 0.28 :
                              0.40 + root.pulse * 0.18
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14

        spacing: root.subtext.length > 0 ? 3 : 0

        Text {
            width: parent.width

            text: root.text

            color: root.enabled ? "white" : "#8aa6c8"

            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#99000000"
        }

        Text {
            visible: root.subtext.length > 0

            width: parent.width

            text: root.subtext

            color: !root.enabled ? "#66758a" :
                   root.armed ? "#ffd1d1" :
                   root.danger ? "#ffc2a8" :
                   root.focused || root.active ? "#9fd8ff" :
                                                  "#8aa6c8"

            font.pixelSize: 11
            font.bold: root.focused || root.armed || root.active
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: root.focused || root.armed || root.active ? 0.96 : 0.86
        }
    }

    /*
        ============================================================
                            POINTER FALLBACK
        ============================================================

        Controller-first screens do not rely on this.
        It remains for desktop preview, touch testing, and compatibility.
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
            root.activate()
        }
    }

    /*
        ============================================================
                            CONTROLLER HELPERS
        ============================================================
    */

    function activate() {
        if (!root.enabled)
            return false

        if (root.autoArmOnClick && !root.armed)
            root.armed = true

        root.clicked()
        return true
    }

    function handleController(action) {
        if (!root.enabled)
            return false

        if (action === "primary" ||
                action === "x" ||
                action === "confirm" ||
                action === "cross") {
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