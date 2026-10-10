import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE COLUMNS VIEW
        ============================================================

        Finder-style column view placeholder.

        Backend-ready:
        - Uses the same file model roles.
        - Main.qml can switch to this later when viewMode === "columns".
        - Future C++ backend can load child columns per selected folder.

        Controller behavior:
        - UP / DOWN moves within the active column.
        - LEFT / RIGHT can later move between parent/child columns.
        - Right stick can scroll the active column.
    */

    property var model: null

    property int selectedIndex: 0
    property int armedIndex: -1

    property bool focused: false
    property bool actionSelected: false

    readonly property int itemCount: modelCount()
    readonly property bool contentScrollable: primaryColumn.contentHeight > primaryColumn.height + 4
    readonly property real scrollPercent: contentScrollable
                                           ? Math.max(0, Math.min(1, primaryColumn.contentY / Math.max(1, primaryColumn.contentHeight - primaryColumn.height)))
                                           : 0.0
    readonly property real visibleAreaPercent: primaryColumn.contentHeight > 0
                                                ? Math.max(0.08, Math.min(1.0, primaryColumn.height / primaryColumn.contentHeight))
                                                : 1.0

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

    signal fileFocused(int index)
    signal fileRequested(int index, var fileData)
    signal scrolled()

    SequentialAnimation on glowPulse {
        running: root.visible && root.focused
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.30
            to: 1.0
            duration: 1550
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.30
            duration: 1550
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

    function requestSelection(index) {
        if (modelCount() <= 0)
            return false

        var nextIndex = clampIndex(index)
        fileFocused(nextIndex)
        return nextIndex !== selectedIndex
    }

    function selectedFileData() {
        return itemAt(clampIndex(selectedIndex))
    }

    function activateSelected() {
        var index = clampIndex(selectedIndex)
        var fileData = itemAt(index)

        if (!fileData)
            return

        fileRequested(index, fileData)
    }

    function ensureSelectedVisible() {
        if (modelCount() <= 0)
            return

        primaryColumn.positionViewAtIndex(clampIndex(selectedIndex), ListView.Contain)
        scrolled()
    }

    function moveSelectionUp() {
        var current = clampIndex(selectedIndex)
        var next = Math.max(0, current - 1)

        requestSelection(next)
        ensureSelectedVisible()

        return next !== current
    }

    function moveSelectionDown() {
        var current = clampIndex(selectedIndex)
        var next = Math.min(modelCount() - 1, current + 1)

        requestSelection(next)
        ensureSelectedVisible()

        return next !== current
    }

    function moveSelectionLeft() {
        return false
    }

    function moveSelectionRight() {
        return false
    }

    function scrollBy(amount) {
        if (!contentScrollable)
            return

        var maxY = Math.max(0, primaryColumn.contentHeight - primaryColumn.height)
        primaryColumn.contentY = Math.max(0, Math.min(maxY, primaryColumn.contentY + amount))
        scrolled()
    }

    function scrollPageUp() {
        scrollBy(-Math.max(120, primaryColumn.height * 0.82))
    }

    function scrollPageDown() {
        scrollBy(Math.max(120, primaryColumn.height * 0.82))
    }

    function accentForKind(kind, isDirectory, armed) {
        if (armed)
            return dangerRed

        var k = String(kind || "").toLowerCase()

        if (isDirectory || k === "folder")
            return focusBlue

        if (k === "video")
            return purpleGlow

        if (k === "image")
            return "#38BDF8"

        if (k === "audio")
            return greenAccent

        if (k === "archive")
            return warningYellow

        if (k === "disk")
            return "#C084FC"

        if (k === "code")
            return "#4DA6FF"

        return textSecondary
    }

    function iconTextForKind(kind, extension, isDirectory) {
        var k = String(kind || "").toLowerCase()
        var ext = String(extension || "").toLowerCase()

        if (isDirectory || k === "folder")
            return "▰"

        if (k === "video")
            return "▶"

        if (k === "image")
            return "◫"

        if (k === "audio")
            return "♫"

        if (k === "archive")
            return "ZIP"

        if (k === "disk")
            return "ISO"

        if (k === "code")
            return "{ }"

        if (k === "document")
            return "≡"

        if (ext.length > 0)
            return ext.toUpperCase().substring(0, 4)

        return "•"
    }

    /*
        ============================================================
                            SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 28

        color: "#061A2EB8"

        border.width: root.focused ? 2 : 1
        border.color: root.actionSelected
                      ? root.dangerRed
                      : root.focused
                        ? root.focusBlue
                        : "#2A8DCC"

        clip: true

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

            y: -150

            width: parent.width * 0.70
            height: 280
            radius: 140

            color: root.actionSelected ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.022 + root.glowPulse * 0.024 : 0.010
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
                            COLUMNS
        ============================================================
    */

    Row {
        anchors.fill: parent
        anchors.margins: 18

        spacing: 12

        Rectangle {
            width: Math.min(430, parent.width * 0.38)
            height: parent.height
            radius: 24

            color: "#071426C8"

            border.width: 1
            border.color: "#244B66"

            clip: true

            Text {
                id: firstColumnTitle

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 14

                text: "CURRENT FOLDER"

                color: root.textMuted

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.5
            }

            ListView {
                id: primaryColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: firstColumnTitle.bottom
                anchors.bottom: parent.bottom

                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 12
                anchors.bottomMargin: 12

                model: root.model

                clip: true
                interactive: false

                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.selectedIndex
                spacing: 7
                cacheBuffer: 900

                Behavior on contentY {
                    NumberAnimation {
                        duration: 135
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Rectangle {
                    width: primaryColumn.width
                    height: 54
                    radius: 17

                    property bool rowSelected: index === root.selectedIndex
                    property bool rowFocused: root.focused && rowSelected
                    property bool rowArmed: index === root.armedIndex
                    property color rowAccent: root.accentForKind(model.kind || model.type || "file",
                                                                 model.isDirectory === true,
                                                                 rowArmed)

                    color: rowArmed
                           ? "#2A0A10E8"
                           : rowFocused
                             ? "#104D86E8"
                             : rowSelected
                               ? "#082B55CC"
                               : "#061A2E88"

                    border.width: rowFocused || rowArmed ? 2 : rowSelected ? 1 : 0
                    border.color: rowArmed ? root.dangerRed : root.focusBlue

                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom

                        visible: rowFocused || rowArmed

                        width: rowArmed ? 5 : 3
                        radius: width / 2

                        color: rowAccent
                        opacity: rowArmed ? 0.90 : 0.62
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter

                        width: 34
                        height: 34
                        radius: 12

                        color: "#061A2EDD"

                        border.width: 1
                        border.color: rowAccent

                        Text {
                            anchors.centerIn: parent

                            text: root.iconTextForKind(model.kind || model.type || "file",
                                                       model.extension || "",
                                                       model.isDirectory === true)

                            color: rowArmed ? "#FFD1D1" : "#FFFFFF"

                            font.pixelSize: text.length > 2 ? 10 : 17
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 60
                        anchors.right: arrowText.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter

                        text: model.name || "Untitled"

                        color: rowArmed ? "#FFD1D1" : root.textPrimary

                        font.pixelSize: 14
                        font.bold: true

                        elide: Text.ElideRight
                    }

                    Text {
                        id: arrowText

                        visible: model.isDirectory === true

                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter

                        text: "›"

                        color: rowAccent

                        font.pixelSize: 20
                        font.bold: true
                    }
                }

                onContentYChanged: {
                    root.scrolled()
                }
            }
        }

        Rectangle {
            width: Math.min(430, parent.width * 0.30)
            height: parent.height
            radius: 24

            color: "#071426A8"

            border.width: 1
            border.color: "#244B66"

            clip: true

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top

                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 14

                text: "PREVIEW COLUMN"

                color: root.textMuted

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.5
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 14

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "▥"

                    color: root.focusBlue

                    font.pixelSize: 48
                    font.bold: true
                }

                Text {
                    width: parent.width

                    text: "Column preview will load child folders after the native backend is connected."

                    color: root.textSecondary

                    font.pixelSize: 14
                    font.bold: true

                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter

                    opacity: 0.82
                }
            }
        }

        Rectangle {
            width: parent.width - Math.min(430, parent.width * 0.38) - Math.min(430, parent.width * 0.30) - 24
            height: parent.height
            radius: 24

            color: "#07142688"

            border.width: 1
            border.color: "#244B66"

            clip: true

            Column {
                anchors.centerIn: parent
                width: parent.width - 44
                spacing: 16

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "DETAILS"

                    color: root.textMuted

                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.6
                }

                Text {
                    width: parent.width

                    text: {
                        var item = root.selectedFileData()
                        return item ? String(item.name || "Selected Item") : "No item selected"
                    }

                    color: root.textPrimary

                    font.pixelSize: 22
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                Text {
                    width: parent.width

                    text: {
                        var item = root.selectedFileData()
                        if (!item)
                            return ""
                        return String(item.path || "")
                    }

                    color: root.textMuted

                    font.pixelSize: 12
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Column {
        visible: root.modelCount() <= 0

        anchors.centerIn: parent
        spacing: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: "∅"

            color: root.focusBlue

            font.pixelSize: 58
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: "No files to display"

            color: root.textPrimary

            font.pixelSize: 24
            font.bold: true
        }
    }

    onSelectedIndexChanged: ensureSelectedVisible()
}