import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE SIDEBAR
        ============================================================

        Left glass sidebar.

        Controller behavior:
        - UP / DOWN moves between selectable places.
        - Headers are skipped.
        - X activates selected place.
        - No mouse assumptions.

        Backend-ready:
        - Model can stay QML now.
        - Later C++ can inject places/devices/mounts into FilePlacesModel.
    */

    width: 250

    property var model: null

    property int selectedIndex: 0
    property bool focused: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35

    signal placeFocused(int index)
    signal placeRequested(int index, string path)

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
            duration: 1500
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1500
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function modelCount() {
        if (!model)
            return 0

        if (model.count === undefined)
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

    function isSelectable(index) {
        var item = itemAt(index)

        if (!item)
            return false

        return item.enabled === true && item.isHeader !== true
    }

    function firstSelectableIndex() {
        if (model && typeof model.firstSelectableIndex === "function")
            return model.firstSelectableIndex()

        for (var i = 0; i < modelCount(); i++) {
            if (isSelectable(i))
                return i
        }

        return 0
    }

    function lastSelectableIndex() {
        if (model && typeof model.lastSelectableIndex === "function")
            return model.lastSelectableIndex()

        for (var i = modelCount() - 1; i >= 0; i--) {
            if (isSelectable(i))
                return i
        }

        return Math.max(0, modelCount() - 1)
    }

    function ensureSelectable() {
        if (modelCount() <= 0)
            return

        if (isSelectable(selectedIndex))
            return

        placeFocused(firstSelectableIndex())
    }

    function moveUp() {
        if (modelCount() <= 0)
            return

        var nextIndex = selectedIndex

        if (model && typeof model.previousSelectableIndex === "function")
            nextIndex = model.previousSelectableIndex(selectedIndex)
        else {
            for (var i = selectedIndex - 1; i >= 0; i--) {
                if (isSelectable(i)) {
                    nextIndex = i
                    break
                }
            }
        }

        nextIndex = Math.max(0, Math.min(nextIndex, modelCount() - 1))

        if (!isSelectable(nextIndex))
            nextIndex = firstSelectableIndex()

        placeFocused(nextIndex)

        if (placesList)
            placesList.positionViewAtIndex(nextIndex, ListView.Contain)
    }

    function moveDown() {
        if (modelCount() <= 0)
            return

        var nextIndex = selectedIndex

        if (model && typeof model.nextSelectableIndex === "function")
            nextIndex = model.nextSelectableIndex(selectedIndex)
        else {
            for (var i = selectedIndex + 1; i < modelCount(); i++) {
                if (isSelectable(i)) {
                    nextIndex = i
                    break
                }
            }
        }

        nextIndex = Math.max(0, Math.min(nextIndex, modelCount() - 1))

        if (!isSelectable(nextIndex))
            nextIndex = lastSelectableIndex()

        placeFocused(nextIndex)

        if (placesList)
            placesList.positionViewAtIndex(nextIndex, ListView.Contain)
    }

    function activateSelected() {
        if (modelCount() <= 0)
            return

        var index = selectedIndex

        if (!isSelectable(index))
            index = firstSelectableIndex()

        var item = itemAt(index)

        if (!item)
            return

        if (model && typeof model.activate === "function")
            model.activate(index)

        placeRequested(index, String(item.path || "/home/echo"))
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 26

        color: "#061A2ED0"

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
            opacity: 0.034
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

            y: -90

            width: parent.width * 0.92
            height: 150
            radius: 75

            color: root.focusBlue
            opacity: root.focused ? 0.030 + root.glowPulse * 0.028 : 0.014
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: root.focused ? 4 : 2
            radius: width / 2

            color: root.focusBlue
            opacity: root.focused ? 0.62 + root.glowPulse * 0.26 : 0.24
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -88
            anchors.bottomMargin: -110

            width: 220
            height: 220
            radius: 110

            color: root.purpleGlow
            opacity: 0.018
        }
    }

    /*
        ============================================================
                            SIDEBAR TITLE
        ============================================================
    */

    Row {
        id: sidebarTitle

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        anchors.leftMargin: 18
        anchors.rightMargin: 16
        anchors.topMargin: 14

        height: 38

        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "◈"

            color: root.focused ? root.focusBlue : root.textSecondary

            font.pixelSize: 18
            font.bold: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter

            text: "PLACES"

            color: root.textPrimary

            font.pixelSize: 15
            font.bold: true
            font.letterSpacing: 1.6

            opacity: 0.94
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter

            width: parent.width - 98
            height: 1
            radius: 1

            color: root.focusBlue
            opacity: root.focused ? 0.28 + root.glowPulse * 0.20 : 0.14
        }
    }

    /*
        ============================================================
                            PLACES LIST
        ============================================================
    */

    ListView {
        id: placesList

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: sidebarTitle.bottom
        anchors.bottom: parent.bottom

        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 12

        model: root.model

        clip: true
        interactive: false

        boundsBehavior: Flickable.StopAtBounds

        currentIndex: root.selectedIndex

        spacing: 2

        delegate: FileSidebarItem {
            width: placesList.width

            title: model.title || ""
            subtitle: model.subtitle || ""
            iconText: model.iconText || "•"
            kind: model.kind || "place"

            headerItem: model.isHeader === true
            enabledItem: model.enabled === true
            danger: model.danger === true

            selected: index === root.selectedIndex && model.isHeader !== true
            focused: root.focused && index === root.selectedIndex && model.isHeader !== true
        }

        onCurrentIndexChanged: {
            if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)
        }
    }

    /*
        ============================================================
                            FOOT GLOW
        ============================================================
    */

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8

        width: parent.width * 0.54
        height: 2
        radius: 1

        color: root.focusBlue
        opacity: root.focused ? 0.30 + root.glowPulse * 0.22 : 0.12
    }

    /*
        ============================================================
                            STATE WATCHERS
        ============================================================
    */

    onFocusedChanged: {
        if (focused)
            ensureSelectable()
    }

    onSelectedIndexChanged: {
        if (placesList)
            placesList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    Component.onCompleted: {
        ensureSelectable()
    }
}