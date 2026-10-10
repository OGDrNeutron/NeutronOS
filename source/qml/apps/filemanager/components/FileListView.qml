import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE LIST VIEW
        ============================================================

        Alternate list layout for File Manager.

        Backend-ready:
        - Uses same model roles as FileGrid/FileTile.
        - Controller movement helpers are exposed.
        - Not mouse driven.

        Main integration:
        - FileGrid owns the primary icon view right now.
        - This component is ready for switching viewMode to "list".
    */

    property var model: null

    property int selectedIndex: 0
    property int armedIndex: -1

    property bool focused: false
    property bool actionSelected: false

    readonly property int itemCount: modelCount()
    readonly property bool contentScrollable: listView.contentHeight > listView.height + 4
    readonly property real scrollPercent: contentScrollable
                                           ? Math.max(0, Math.min(1, listView.contentY / Math.max(1, listView.contentHeight - listView.height)))
                                           : 0.0
    readonly property real visibleAreaPercent: listView.contentHeight > 0
                                                ? Math.max(0.08, Math.min(1.0, listView.height / listView.contentHeight))
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

    function ensureSelectedVisible() {
        if (modelCount() <= 0)
            return

        listView.positionViewAtIndex(clampIndex(selectedIndex), ListView.Contain)
        scrolled()
    }

    function activateSelected() {
        var index = clampIndex(selectedIndex)
        var fileData = itemAt(index)

        if (!fileData)
            return

        fileRequested(index, fileData)
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

        var maxY = Math.max(0, listView.contentHeight - listView.height)
        listView.contentY = Math.max(0, Math.min(maxY, listView.contentY + amount))
        scrolled()
    }

    function scrollPageUp() {
        scrollBy(-Math.max(120, listView.height * 0.82))
    }

    function scrollPageDown() {
        scrollBy(Math.max(120, listView.height * 0.82))
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

            y: -140

            width: parent.width * 0.64
            height: 260
            radius: 130

            color: root.actionSelected ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.022 + root.glowPulse * 0.024 : 0.010
        }
    }

    /*
        ============================================================
                            COLUMN HEADERS
        ============================================================
    */

    Rectangle {
        id: headerRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top

        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 14

        height: 42
        radius: 18

        color: "#071426C8"

        border.width: 1
        border.color: "#244B66"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 66
            anchors.verticalCenter: parent.verticalCenter

            text: "NAME"

            color: root.textMuted

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.4
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 300
            anchors.verticalCenter: parent.verticalCenter

            text: "TYPE"

            color: root.textMuted

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.4
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 172
            anchors.verticalCenter: parent.verticalCenter

            text: "SIZE"

            color: root.textMuted

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.4
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter

            text: "MODIFIED"

            color: root.textMuted

            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.4
        }
    }

    /*
        ============================================================
                            LIST VIEW
        ============================================================
    */

    ListView {
        id: listView

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerRow.bottom
        anchors.bottom: parent.bottom

        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 10
        anchors.bottomMargin: 18

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
            width: listView.width
            height: 58
            radius: 18

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
                       : "#07142688"

            border.width: rowFocused || rowArmed ? 2 : rowSelected ? 1 : 0
            border.color: rowArmed ? root.dangerRed : root.focusBlue

            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: rowFocused || rowArmed ? 0.044 : 0.020
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                visible: rowFocused || rowArmed

                width: rowArmed ? 5 : 3
                radius: width / 2

                color: rowAccent
                opacity: rowArmed ? 0.90 : 0.64
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter

                width: 36
                height: 36
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

                    font.pixelSize: text.length > 2 ? 11 : 18
                    font.bold: true
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 66
                anchors.right: parent.right
                anchors.rightMargin: 420
                anchors.verticalCenter: parent.verticalCenter

                text: model.name || "Untitled"

                color: rowArmed ? "#FFD1D1" : root.textPrimary

                font.pixelSize: 15
                font.bold: true

                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 268
                anchors.verticalCenter: parent.verticalCenter

                width: 94

                text: model.isDirectory === true
                      ? "FOLDER"
                      : String(model.kind || model.type || "FILE").toUpperCase()

                color: rowAccent

                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 0.8

                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 146
                anchors.verticalCenter: parent.verticalCenter

                width: 94

                text: model.isDirectory === true ? "—" : model.sizeText || "0 B"

                color: root.textSecondary

                font.pixelSize: 12
                font.bold: true

                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter

                width: 108

                text: model.modified || "—"

                color: root.textMuted

                font.pixelSize: 11
                font.bold: true

                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            Rectangle {
                visible: rowFocused

                anchors.fill: parent
                anchors.margins: -4

                radius: parent.radius + 4

                color: "transparent"

                border.width: 1
                border.color: root.focusBlue

                opacity: 0.42 + root.glowPulse * 0.24
            }
        }

        onContentYChanged: {
            root.scrolled()
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