import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                        FILE MANAGER HEADER
        ============================================================

        Layout target:
        - Glass back / forward arrows on the left.
        - Premium centered title:
              NeutronOS File Manager
          NeutronOS uses the brand color treatment.
          File Manager uses a complementary icy blue scheme.
        - Search bar on the right.
        - Controller-only. No MouseArea.
    */

    height: 78

    property bool connected: true
    property string version: "v1.0.0"

    property string titleBrand: "NeutronOS"
    property string titleSuffix: "File Manager"

    property bool focused: false
    property int selectedAction: 0

    property bool canGoBack: false
    property bool canGoForward: false

    property string searchText: ""
    property bool searchFocused: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color brandPurple: "#A855F7"
    property color brandViolet: "#8B5CF6"
    property color brandBlue: "#38BDF8"
    property color successGreen: "#22FF88"
    property color dangerRed: "#FF3040"

    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35
    property real sweep: -1.0

    signal backRequested()
    signal forwardRequested()
    signal searchRequested()
    signal searchCommitted(string query)
    signal actionRequested(string actionId)

    SequentialAnimation on glowPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 2400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 2400
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3600
            easing.type: Easing.InOutSine
        }
    }

    function actionCount() {
        return 3
    }

    function normalizeActionIndex(index) {
        var count = actionCount()

        if (count <= 0)
            return 0

        var value = index % count

        if (value < 0)
            value += count

        return value
    }

    function moveLeft() {
        selectedAction = normalizeActionIndex(selectedAction - 1)
    }

    function moveRight() {
        selectedAction = normalizeActionIndex(selectedAction + 1)
    }

    function activateSelected() {
        if (selectedAction === 0) {
            actionRequested("back")
            backRequested()
            return
        }

        if (selectedAction === 1) {
            actionRequested("forward")
            forwardRequested()
            return
        }

        actionRequested("search")
        searchRequested()
    }

    /*
        ============================================================
                            HEADER GLASS
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 24

        color: "#061A2ED8"

        border.width: root.focused ? 2 : 1
        border.color: root.focused ? root.focusBlue : "#2A8DCC"

        opacity: 0.98

        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.032
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

            y: -92

            width: 720
            height: 160
            radius: 80

            color: root.focusBlue
            opacity: 0.026 + root.glowPulse * 0.018
        }

        Rectangle {
            width: 170
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.connected ? root.focusBlue : root.dangerRed
            opacity: root.focused ? 0.26 + root.glowPulse * 0.16 : 0.16
        }
    }

    /*
        ============================================================
                            LEFT ARROWS
        ============================================================
    */

    Row {
        id: navButtons

        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter

        spacing: 12

        GlassIconButton {
            width: 54
            height: 54

            iconText: "‹"
            label: ""
            compact: true

            focused: root.focused && root.selectedAction === 0
            selected: root.focused && root.selectedAction === 0

            enabledButton: root.canGoBack

            onActivated: {
                root.actionRequested("back")
                root.backRequested()
            }
        }

        GlassIconButton {
            width: 54
            height: 54

            iconText: "›"
            label: ""
            compact: true

            focused: root.focused && root.selectedAction === 1
            selected: root.focused && root.selectedAction === 1

            enabledButton: root.canGoForward

            onActivated: {
                root.actionRequested("forward")
                root.forwardRequested()
            }
        }
    }

    /*
        ============================================================
                            CENTER TITLE
        ============================================================
    */

    Item {
        id: titleBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        width: Math.min(690, parent.width - 780)
        height: parent.height

        Rectangle {
            anchors.horizontalCenter: titleRow.horizontalCenter
            anchors.verticalCenter: titleRow.verticalCenter

            width: titleRow.width + 92
            height: 54
            radius: 27

            color: root.focusBlue
            opacity: 0.018 + root.glowPulse * 0.016
        }

        Row {
            id: titleRow

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -3

            spacing: 12

            Row {
                id: brandRow

                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                /*
                    NeutronOS brand color treatment.
                    This matches the login-screen direction: purple/violet
                    into electric cyan/blue.
                */

                Repeater {
                    model: [
                        { "t": "N", "c": "#A855F7" },
                        { "t": "e", "c": "#9B5CF6" },
                        { "t": "u", "c": "#8B5CF6" },
                        { "t": "t", "c": "#7C6CFA" },
                        { "t": "r", "c": "#637BFF" },
                        { "t": "o", "c": "#4DA6FF" },
                        { "t": "n", "c": "#38BDF8" },
                        { "t": "O", "c": "#68D8FF" },
                        { "t": "S", "c": "#A7EEFF" }
                    ]

                    Text {
                        text: modelData.t
                        color: modelData.c

                        font.pixelSize: 33
                        font.bold: true
                        font.letterSpacing: 0.2

                        style: Text.Raised
                        styleColor: "#77000000"
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: root.titleSuffix

                color: "#DDFBFF"

                font.pixelSize: 30
                font.bold: true
                font.letterSpacing: 0.8

                style: Text.Raised
                styleColor: "#66000000"
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: titleRow.bottom
            anchors.topMargin: 4

            spacing: 10

            Rectangle {
                width: 82
                height: 2
                radius: 1

                anchors.verticalCenter: subtitle.verticalCenter

                color: root.brandPurple
                opacity: 0.46
            }

            Text {
                id: subtitle

                text: "LOCAL FILE CONTROL"

                color: root.textSecondary

                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 2.3

                opacity: 0.82
            }

            Rectangle {
                width: 82
                height: 2
                radius: 1

                anchors.verticalCenter: subtitle.verticalCenter

                color: root.focusBlue
                opacity: 0.46
            }
        }
    }

    /*
        ============================================================
                            RIGHT SEARCH
        ============================================================
    */

    FileSearchBar {
        id: searchBar

        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter

        width: 330
        height: 54

        text: root.searchText
        focused: root.searchFocused || (root.focused && root.selectedAction === 2)
        selected: root.focused && root.selectedAction === 2

        placeholderText: "Search"

        onSearchRequested: {
            root.actionRequested("search")
            root.searchRequested()
        }

        onSearchCommitted: function(query) {
            root.searchCommitted(query)
        }
    }

    /*
        ============================================================
                            STATUS DOT
        ============================================================
    */

    Rectangle {
        anchors.right: searchBar.left
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter

        width: 10
        height: 10
        radius: 5

        color: root.connected ? root.successGreen : root.dangerRed

        opacity: root.connected ? 0.60 + root.glowPulse * 0.40 : 1.0
    }

    Text {
        anchors.right: searchBar.left
        anchors.rightMargin: 34
        anchors.verticalCenter: parent.verticalCenter

        text: root.connected ? "LOCAL" : "OFFLINE"

        color: root.connected ? root.successGreen : "#FFB8B8"

        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.4

        opacity: 0.86
    }
}