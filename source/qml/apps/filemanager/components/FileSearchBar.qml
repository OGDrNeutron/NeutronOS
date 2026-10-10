import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE SEARCH BAR
        ============================================================

        Controller-ready search field.

        Current:
        - Visual glass search bar.
        - Can accept keyboard input when focused.
        - X/search action requests search mode.
        - Enter commits query.

        Future:
        - Can open NeutronOS on-screen keyboard.
        - Can route query to C++ backend search.
    */

    width: 330
    height: 54

    property string text: ""
    property string placeholderText: "Search"

    property bool focused: false
    property bool selected: false
    property bool enabledBar: true

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real pulse: 0.35

    signal searchRequested()
    signal searchCommitted(string query)

    function activate() {
        if (!enabledBar)
            return

        searchRequested()
        input.forceActiveFocus()
        input.cursorPosition = input.text.length
    }

    function commit() {
        root.text = input.text
        searchCommitted(input.text)
        root.forceActiveFocus()
    }

    function clearSearch() {
        input.text = ""
        root.text = ""
        searchCommitted("")
    }

    SequentialAnimation on pulse {
        running: root.visible && root.enabledBar && (root.focused || root.selected || input.activeFocus)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1350
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1350
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: shell

        anchors.fill: parent

        radius: height / 2

        color: root.focused || root.selected || input.activeFocus
               ? "#104D86EE"
               : "#071426DD"

        border.width: root.focused || root.selected || input.activeFocus ? 2 : 1
        border.color: root.focused || root.selected || input.activeFocus
                      ? root.focusBlue
                      : "#2A8DCC"

        opacity: root.enabledBar ? 1.0 : 0.42

        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 150
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.040
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: 0.18
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -parent.height * 0.60

            width: parent.width * 0.72
            height: parent.height

            radius: height / 2

            color: root.focusBlue
            opacity: root.focused || root.selected || input.activeFocus
                     ? 0.055 + root.pulse * 0.070
                     : 0.020
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 48
            anchors.bottomMargin: 5

            width: parent.width - 96
            height: 2
            radius: 1

            color: root.focusBlue
            opacity: root.focused || root.selected || input.activeFocus
                     ? 0.28 + root.pulse * 0.26
                     : 0.10
        }
    }

    Text {
        id: icon

        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.verticalCenter: parent.verticalCenter

        text: "⌕"

        color: root.focused || root.selected || input.activeFocus
               ? "#FFFFFF"
               : root.textSecondary

        font.pixelSize: 24
        font.bold: true

        opacity: root.enabledBar ? 1.0 : 0.44

        style: Text.Raised
        styleColor: "#66000000"
    }

    TextInput {
        id: input

        anchors.left: icon.right
        anchors.right: clearIndicator.left
        anchors.verticalCenter: parent.verticalCenter

        anchors.leftMargin: 10
        anchors.rightMargin: 8

        height: parent.height - 12

        text: root.text

        color: root.textPrimary
        selectionColor: root.focusBlue
        selectedTextColor: "#02101C"

        font.pixelSize: 17
        font.bold: true

        verticalAlignment: TextInput.AlignVCenter

        clip: true
        focus: false

        activeFocusOnTab: false

        opacity: root.enabledBar ? 1.0 : 0.46

        onTextEdited: {
            root.text = text
        }

        onAccepted: {
            root.commit()
        }

        Keys.onEscapePressed: {
            root.forceActiveFocus()
        }
    }

    Text {
        visible: input.text.length <= 0 && !input.activeFocus

        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter

        text: root.placeholderText

        color: root.textMuted

        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 0.4

        opacity: 0.76
    }

    Text {
        id: clearIndicator

        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter

        width: 18

        visible: input.text.length > 0

        text: "×"

        color: root.focused || input.activeFocus ? root.focusBlue : root.textMuted

        font.pixelSize: 22
        font.bold: true

        horizontalAlignment: Text.AlignHCenter

        opacity: 0.82
    }

    Rectangle {
        visible: root.focused && root.enabledBar

        anchors.fill: parent
        anchors.margins: -4

        radius: height / 2

        color: "transparent"

        border.width: 1
        border.color: root.focusBlue

        opacity: 0.36 + root.pulse * 0.26
    }
}