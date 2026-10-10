import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE SORT MENU
        ============================================================

        Floating glass sort menu.

        Controller behavior:
        - UP / DOWN moves through sort options.
        - X activates selected sort.
        - O closes menu through Main.qml.
        - No mouse assumptions.

        Backend-ready:
        - Uses FileSortModel.qml now.
        - Later backend can add filesystem-specific sort modes.
    */

    width: 300
    height: 360

    property var model: null

    property int selectedIndex: 0
    property string currentSortKey: "name"
    property bool ascending: true
    property bool focused: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color greenAccent: "#22FF88"
    property color dangerRed: "#FF3040"
    property color warningYellow: "#FFD166"

    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35
    property real sweep: -1.0

    signal sortFocused(int index)
    signal sortRequested(string sortKey, bool ascending)
    signal closeRequested()

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
            duration: 1200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1200
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 2800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 2800
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function modelCount() {
        if (!model || model.count === undefined)
            return 0

        return Number(model.count || 0)
    }

    function itemAt(index) {
        if (!model || index < 0 || index >= modelCount())
            return null

        if (typeof model.get === "function")
            return model.get(index)

        return null
    }

    function clampIndex(index) {
        var count = modelCount()

        if (count <= 0)
            return 0

        return Math.max(0, Math.min(Number(index || 0), count - 1))
    }

    function moveUp() {
        if (modelCount() <= 0)
            return

        var nextIndex = clampIndex(selectedIndex - 1)

        sortFocused(nextIndex)
        sortList.positionViewAtIndex(nextIndex, ListView.Contain)
    }

    function moveDown() {
        if (modelCount() <= 0)
            return

        var nextIndex = clampIndex(selectedIndex + 1)

        sortFocused(nextIndex)
        sortList.positionViewAtIndex(nextIndex, ListView.Contain)
    }

    function moveRight() {
        /*
            Keep this harmless for Main.qml compatibility.
            Sort menu is vertical, so RIGHT activates the selected sort.
        */
        activateSelected()
    }

    function activateSelected() {
        if (modelCount() <= 0)
            return

        var index = clampIndex(selectedIndex)
        var item = itemAt(index)

        if (!item || item.enabled !== true)
            return

        sortRequested(String(item.sortKey || "name"), item.ascending === true)
    }

    function isCurrentSort(item) {
        if (!item)
            return false

        return String(item.sortKey || "") === String(root.currentSortKey || "") &&
               item.ascending === root.ascending
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 26

        color: "#061A2EF2"

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
            opacity: 0.040
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: 0.22
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -84

            width: parent.width * 0.86
            height: 154
            radius: 77

            color: root.focusBlue
            opacity: root.focused ? 0.034 + root.glowPulse * 0.036 : 0.016
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -74
            anchors.bottomMargin: -88

            width: 190
            height: 190
            radius: 95

            color: root.purpleGlow
            opacity: 0.022
        }

        Rectangle {
            width: 92
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.focusBlue
            opacity: 0.26 + root.glowPulse * 0.16
        }
    }

    /*
        ============================================================
                            TITLE
        ============================================================
    */

    Row {
        id: menuTitle

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 16

        height: 34

        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "⇅"

            color: root.focusBlue

            font.pixelSize: 18
            font.bold: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "SORT"

            color: root.textPrimary

            font.pixelSize: 16
            font.bold: true
            font.letterSpacing: 1.6
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width - 96
            height: 1
            radius: 1

            color: root.focusBlue
            opacity: 0.24 + root.glowPulse * 0.12
        }
    }

    /*
        ============================================================
                            OPTIONS
        ============================================================
    */

    ListView {
        id: sortList

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: menuTitle.bottom
        anchors.bottom: parent.bottom

        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 14

        model: root.model

        clip: true
        interactive: false

        spacing: 8

        boundsBehavior: Flickable.StopAtBounds
        currentIndex: root.selectedIndex

        delegate: Rectangle {
            width: sortList.width
            height: 54
            radius: 18

            property bool rowSelected: index === root.selectedIndex
            property bool rowFocused: root.focused && rowSelected
            property bool rowCurrent: root.isCurrentSort(model)
            property color rowAccent: rowCurrent ? root.greenAccent : root.focusBlue

            color: rowFocused
                   ? "#104D86E8"
                   : rowCurrent
                     ? "#0C3325D8"
                     : "#071426B8"

            border.width: rowFocused || rowCurrent ? 2 : 1
            border.color: rowFocused
                          ? root.focusBlue
                          : rowCurrent
                            ? root.greenAccent
                            : "#244B66"

            clip: true

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 140
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1

                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: rowFocused || rowCurrent ? 0.045 : 0.022
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                visible: rowFocused || rowCurrent

                width: rowFocused ? 4 : 3
                radius: width / 2

                color: rowAccent
                opacity: rowFocused ? 0.72 + root.glowPulse * 0.24 : 0.54
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter

                width: 32
                height: 32
                radius: 11

                color: "#061A2EDD"

                border.width: 1
                border.color: rowAccent

                Text {
                    anchors.centerIn: parent

                    text: model.iconText || "•"

                    color: rowCurrent ? "#D5FFE8" : "#FFFFFF"

                    font.pixelSize: 15
                    font.bold: true
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 58
                anchors.right: checkIcon.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                spacing: 1

                Text {
                    width: parent.width

                    text: model.title || "Sort"

                    color: rowCurrent ? "#D5FFE8" : root.textPrimary

                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 0.4

                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width

                    text: model.subtitle || ""

                    color: root.textMuted

                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.3

                    elide: Text.ElideRight

                    opacity: 0.78
                }
            }

            Text {
                id: checkIcon

                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter

                width: 22

                text: rowCurrent ? "✓" : "›"

                color: rowCurrent ? root.greenAccent : root.textMuted

                font.pixelSize: rowCurrent ? 18 : 20
                font.bold: true

                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                visible: rowFocused

                anchors.fill: parent
                anchors.margins: -4

                radius: parent.radius + 4

                color: "transparent"

                border.width: 1
                border.color: root.focusBlue

                opacity: 0.36 + root.glowPulse * 0.26
            }
        }

        onCurrentIndexChanged: {
            if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)
        }
    }

    /*
        ============================================================
                            FOOTER HINT
        ============================================================
    */

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7

        text: "X APPLY  •  O CLOSE"

        color: root.textMuted

        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 1.1

        opacity: root.focused ? 0.82 : 0.44
    }

    /*
        ============================================================
                            STATE WATCHERS
        ============================================================
    */

    onSelectedIndexChanged: {
        selectedIndex = clampIndex(selectedIndex)

        if (sortList)
            sortList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    Component.onCompleted: {
        selectedIndex = clampIndex(selectedIndex)
    }
}