import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE GRID
        ============================================================

        Main file content area.

        Controller behavior:
        - D-pad / left stick moves selection normally.
        - Selection movement auto-scrolls when reaching top/bottom edge.
        - Right stick scrolls the page up/down only.
        - Scroll rail is visual only and reads scrollPercent.
        - X behavior is owned by Main.qml:
              X arms/selects the file for action.
              X again opens action modal.
              O cancels armed file.
    */

    property var model: null

    property string currentPath: "/home/echo"
    property string viewMode: "icons"
    property string searchQuery: ""

    property int selectedIndex: 0
    property int armedIndex: -1

    property bool focused: false
    property bool actionSelected: false

    property int tileWidth: 142
    property int tileHeight: 162
    property int cellWidth: 176
    property int cellHeight: 196

    readonly property int itemCount: modelCount()
    readonly property int columns: Math.max(1, Math.floor(Math.max(1, fileView.width - 10) / cellWidth))
    readonly property bool contentScrollable: fileView.contentHeight > fileView.height + 4
    readonly property real scrollPercent: contentScrollable
                                           ? Math.max(0, Math.min(1, fileView.contentY / Math.max(1, fileView.contentHeight - fileView.height)))
                                           : 0.0
    readonly property real visibleAreaPercent: fileView.contentHeight > 0
                                                ? Math.max(0.08, Math.min(1.0, fileView.height / fileView.contentHeight))
                                                : 1.0

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

    signal fileFocused(int index)
    signal fileRequested(int index, var fileData)
    signal scrolled()

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
            duration: 1650
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1650
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.visible && root.focused
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3400
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            MODEL HELPERS
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

    function clampIndex(index) {
        var count = modelCount()

        if (count <= 0)
            return 0

        return Math.max(0, Math.min(Number(index || 0), count - 1))
    }

    function requestSelection(index) {
        var count = modelCount()

        if (count <= 0)
            return false

        var nextIndex = clampIndex(index)

        fileFocused(nextIndex)
        return nextIndex !== selectedIndex
    }

    function activateSelected() {
        if (modelCount() <= 0)
            return

        var index = clampIndex(selectedIndex)
        var fileData = itemAt(index)

        if (!fileData)
            return

        fileRequested(index, fileData)
    }

    function selectedFileData() {
        return itemAt(clampIndex(selectedIndex))
    }

    /*
        ============================================================
                        SELECTION MOVEMENT
        ============================================================
    */

    function moveSelectionLeft() {
        if (modelCount() <= 0)
            return false

        var current = clampIndex(selectedIndex)

        /*
            If already at the first column, let Main move to sidebar.
        */
        if (current % columns === 0) {
            ensureSelectedVisible()
            return false
        }

        requestSelection(current - 1)
        ensureSelectedVisible()
        return true
    }

    function moveSelectionRight() {
        if (modelCount() <= 0)
            return false

        var current = clampIndex(selectedIndex)
        var next = Math.min(modelCount() - 1, current + 1)

        requestSelection(next)
        ensureSelectedVisible()
        return next !== current
    }

    function moveSelectionUp() {
        if (modelCount() <= 0)
            return false

        var current = clampIndex(selectedIndex)
        var next = Math.max(0, current - columns)

        requestSelection(next)
        ensureSelectedVisible()
        return next !== current
    }

    function moveSelectionDown() {
        if (modelCount() <= 0)
            return false

        var current = clampIndex(selectedIndex)
        var next = Math.min(modelCount() - 1, current + columns)

        requestSelection(next)
        ensureSelectedVisible()
        return next !== current
    }

    function ensureSelectedVisible() {
        if (modelCount() <= 0)
            return

        var index = clampIndex(selectedIndex)

        if (fileView && index >= 0)
            fileView.positionViewAtIndex(index, GridView.Contain)

        scrolled()
    }

    /*
        ============================================================
                            RIGHT STICK SCROLL
        ============================================================
    */

    function scrollBy(amount) {
        if (!contentScrollable)
            return

        var maxY = Math.max(0, fileView.contentHeight - fileView.height)
        var nextY = Math.max(0, Math.min(maxY, fileView.contentY + amount))

        fileView.contentY = nextY
        scrolled()
    }

    function scrollPageUp() {
        scrollBy(-Math.max(120, fileView.height * 0.82))
    }

    function scrollPageDown() {
        scrollBy(Math.max(120, fileView.height * 0.82))
    }

    function scrollToTop() {
        fileView.contentY = 0
        scrolled()
    }

    function scrollToBottom() {
        fileView.contentY = Math.max(0, fileView.contentHeight - fileView.height)
        scrolled()
    }

    /*
        ============================================================
                            GLASS CONTENT SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 28

        color: "#061A2EB8"

        border.width: root.focused ? 2 : 1
        border.color: root.focused
                      ? root.actionSelected
                        ? root.dangerRed
                        : root.focusBlue
                      : "#2A8DCC"

        clip: true

        Behavior on border.color {
            ColorAnimation {
                duration: 160
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1

            radius: parent.radius - 1
            color: "#FFFFFF"
            opacity: 0.026
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: "#FFFFFF"
            opacity: 0.16
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -160

            width: parent.width * 0.72
            height: 300
            radius: 150

            color: root.actionSelected ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.024 + root.glowPulse * 0.024 : 0.010
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -140
            anchors.bottomMargin: -170

            width: 360
            height: 360
            radius: 180

            color: root.purpleGlow
            opacity: 0.016
        }

        Rectangle {
            width: 150
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.actionSelected ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.24 + root.glowPulse * 0.16 : 0.08
        }
    }

    /*
        ============================================================
                            GRID VIEW
        ============================================================
    */

    GridView {
        id: fileView

        anchors.fill: parent

        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 18
        anchors.bottomMargin: 18

        model: root.model

        cellWidth: root.cellWidth
        cellHeight: root.cellHeight

        clip: true
        interactive: false

        boundsBehavior: Flickable.StopAtBounds

        currentIndex: root.selectedIndex

        cacheBuffer: 900

        Behavior on contentY {
            NumberAnimation {
                duration: 135
                easing.type: Easing.OutCubic
            }
        }

        delegate: FileTile {
            width: root.tileWidth
            height: root.tileHeight

            name: model.name || "Untitled"
            path: model.path || ""
            kind: model.kind || model.type || "file"
            extension: model.extension || ""
            sizeText: model.sizeText || ""
            modified: model.modified || ""
            preview: model.preview || ""
            icon: model.icon || ""
            isDirectory: model.isDirectory === true

            selected: index === root.selectedIndex
            focused: root.focused && index === root.selectedIndex
            armed: index === root.armedIndex

            opacity: fileView.moving ? 0.90 : 1.0

            x: Math.round((root.cellWidth - width) / 2)
            y: 6
        }

        onContentYChanged: {
            root.scrolled()
        }
    }

    /*
        ============================================================
                            EMPTY STATE
        ============================================================
    */

    Column {
        visible: root.modelCount() <= 0

        anchors.centerIn: parent

        spacing: 18

        Rectangle {
            width: 96
            height: 96
            radius: 48

            anchors.horizontalCenter: parent.horizontalCenter

            color: "#071426DD"

            border.width: 2
            border.color: root.focusBlue

            opacity: 0.96

            Text {
                anchors.centerIn: parent

                text: root.searchQuery.length > 0 ? "⌕" : "∅"

                color: root.focusBlue

                font.pixelSize: 42
                font.bold: true
            }
        }

        Text {
            width: 520

            anchors.horizontalCenter: parent.horizontalCenter

            text: root.searchQuery.length > 0
                  ? "No matching files"
                  : "This folder is empty"

            color: root.textPrimary

            font.pixelSize: 28
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: 560

            anchors.horizontalCenter: parent.horizontalCenter

            text: root.searchQuery.length > 0
                  ? "Try a different search or clear the search bar."
                  : root.currentPath

            color: root.textMuted

            font.pixelSize: 15
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
        }
    }

    /*
        ============================================================
                            STATUS HINT
        ============================================================
    */

    Rectangle {
        visible: root.focused && root.modelCount() > 0

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.bottomMargin: 14

        width: hintText.implicitWidth + 28
        height: 28
        radius: 14

        color: root.actionSelected ? "#2A0A10DD" : "#071426DD"

        border.width: 1
        border.color: root.actionSelected ? root.dangerRed : root.focusBlue

        opacity: 0.86

        Text {
            id: hintText

            anchors.centerIn: parent

            text: root.actionSelected
                  ? "O CANCEL  •  X ACTIONS"
                  : "X SELECT FILE  •  RIGHT STICK SCROLL"

            color: root.actionSelected ? "#FFD1D1" : root.textSecondary

            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.1
        }
    }

    /*
        ============================================================
                            STATE WATCHERS
        ============================================================
    */

    onSelectedIndexChanged: {
        ensureSelectedVisible()
    }

    onModelChanged: {
        scrollToTop()
    }

    Component.onCompleted: {
        ensureSelectedVisible()
    }
}