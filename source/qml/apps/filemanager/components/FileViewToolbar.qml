import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                        FILE VIEW TOOLBAR
        ============================================================

        Controller-only toolbar.

        Layout:
        - Left: Icons / List / Columns / Gallery
        - Right: New Folder / Quick Actions / Sort

        Behavior:
        - LEFT / RIGHT moves selected toolbar action.
        - X activates selected action.
        - View buttons switch view mode.
        - Sort opens sort menu.
        - Quick Actions works with armed file or selected file.
    */

    height: 58

    property bool focused: false

    property string viewMode: "icons"
    property int selectedAction: 0

    property bool sortMenuOpen: false
    property bool hasArmedFile: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35
    property real sweep: -1.0

    property var actions: [
        {
            "id": "icons",
            "text": "ICONS",
            "icon": "▦",
            "type": "view",
            "mode": "icons",
            "width": 118
        },
        {
            "id": "list",
            "text": "LIST",
            "icon": "☰",
            "type": "view",
            "mode": "list",
            "width": 108
        },
        {
            "id": "columns",
            "text": "COLUMNS",
            "icon": "▥",
            "type": "view",
            "mode": "columns",
            "width": 142
        },
        {
            "id": "gallery",
            "text": "GALLERY",
            "icon": "◫",
            "type": "view",
            "mode": "gallery",
            "width": 136
        },
        {
            "id": "newFolder",
            "text": "NEW FOLDER",
            "icon": "+",
            "type": "action",
            "width": 168
        },
        {
            "id": "actions",
            "text": "ACTIONS",
            "icon": "⚙",
            "type": "action",
            "width": 142
        },
        {
            "id": "sort",
            "text": "SORT",
            "icon": "⇅",
            "type": "action",
            "width": 116
        }
    ]

    signal viewModeRequested(string mode)
    signal newFolderRequested()
    signal quickActionsRequested()
    signal sortRequested()

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on glowPulse {
        running: root.visible && root.focused
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1450
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1450
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.visible && root.focused
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3000
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3000
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function actionCount() {
        return actions.length
    }

    function normalizeIndex(index) {
        var count = actionCount()

        if (count <= 0)
            return 0

        var value = index % count

        if (value < 0)
            value += count

        return value
    }

    function actionAt(index) {
        if (actionCount() <= 0)
            return null

        return actions[normalizeIndex(index)]
    }

    function moveLeft() {
        selectedAction = normalizeIndex(selectedAction - 1)
    }

    function moveRight() {
        selectedAction = normalizeIndex(selectedAction + 1)
    }

    function activateSelected() {
        var action = actionAt(selectedAction)

        if (!action)
            return

        if (action.id === "icons" ||
                action.id === "list" ||
                action.id === "columns" ||
                action.id === "gallery") {
            viewModeRequested(String(action.mode || "icons"))
            return
        }

        if (action.id === "newFolder") {
            newFolderRequested()
            return
        }

        if (action.id === "actions") {
            quickActionsRequested()
            return
        }

        if (action.id === "sort") {
            sortRequested()
            return
        }
    }

    function isActionActive(action) {
        if (!action)
            return false

        if (action.type === "view")
            return String(root.viewMode || "icons") === String(action.mode || "")

        if (action.id === "sort")
            return root.sortMenuOpen

        if (action.id === "actions")
            return root.hasArmedFile

        return false
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 24

        color: "#061A2ED2"

        border.width: root.focused ? 2 : 1
        border.color: root.focused ? root.focusBlue : "#2A8DCC"

        clip: true

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

            y: -70

            width: parent.width * 0.42
            height: 122
            radius: 61

            color: root.focusBlue
            opacity: root.focused ? 0.024 + root.glowPulse * 0.024 : 0.010
        }

        Rectangle {
            width: 130
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.focusBlue
            opacity: root.focused ? 0.26 + root.glowPulse * 0.18 : 0.10
        }
    }

    /*
        ============================================================
                            LEFT VIEW MODES
        ============================================================
    */

    Row {
        id: viewButtons

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter

        spacing: 10

        Repeater {
            model: 4

            GlassPillButton {
                property var actionData: root.actions[index]

                width: actionData.width
                height: 42

                text: actionData.text
                iconText: actionData.icon

                focused: root.focused && root.selectedAction === index
                selected: root.focused && root.selectedAction === index
                active: root.isActionActive(actionData)

                enabledButton: true

                onActivated: {
                    root.selectedAction = index
                    root.activateSelected()
                }
            }
        }
    }

    /*
        ============================================================
                            RIGHT ACTIONS
        ============================================================
    */

    Row {
        id: rightButtons

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter

        spacing: 10

        Repeater {
            model: 3

            GlassPillButton {
                property int actionIndex: index + 4
                property var actionData: root.actions[actionIndex]

                width: actionData.width
                height: 42

                text: actionData.text
                iconText: actionData.icon

                focused: root.focused && root.selectedAction === actionIndex
                selected: root.focused && root.selectedAction === actionIndex
                active: root.isActionActive(actionData)

                armed: actionData.id === "actions" && root.hasArmedFile
                danger: false

                enabledButton: true

                onActivated: {
                    root.selectedAction = actionIndex
                    root.activateSelected()
                }
            }
        }
    }

    /*
        ============================================================
                            CENTER STATUS
        ============================================================
    */

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        visible: root.width > 1040

        text: root.focused
              ? "X SELECT  •  O BACK"
              : "VIEW"

        color: root.focused ? root.textSecondary : root.textMuted

        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.4

        opacity: root.focused ? 0.76 : 0.42
    }

    /*
        ============================================================
                            STATE WATCHERS
        ============================================================
    */

    onSelectedActionChanged: {
        selectedAction = normalizeIndex(selectedAction)
    }
}