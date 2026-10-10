import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE GALLERY VIEW
        ============================================================

        Gallery/media-focused layout.

        Backend-ready:
        - Uses same normalized model roles.
        - Can display previews later when C++ backend generates thumbnails.
        - Controller movement helpers match FileGrid.qml.
    */

    property var model: null

    property int selectedIndex: 0
    property int armedIndex: -1

    property bool focused: false
    property bool actionSelected: false

    property int cardWidth: 238
    property int cardHeight: 206
    property int cellWidth: 270
    property int cellHeight: 238

    readonly property int itemCount: modelCount()
    readonly property int columns: Math.max(1, Math.floor(Math.max(1, galleryView.width - 10) / cellWidth))
    readonly property bool contentScrollable: galleryView.contentHeight > galleryView.height + 4
    readonly property real scrollPercent: contentScrollable
                                           ? Math.max(0, Math.min(1, galleryView.contentY / Math.max(1, galleryView.contentHeight - galleryView.height)))
                                           : 0.0
    readonly property real visibleAreaPercent: galleryView.contentHeight > 0
                                                ? Math.max(0.08, Math.min(1.0, galleryView.height / galleryView.contentHeight))
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

    function moveSelectionLeft() {
        if (modelCount() <= 0)
            return false

        var current = clampIndex(selectedIndex)

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

        galleryView.positionViewAtIndex(clampIndex(selectedIndex), GridView.Contain)
        scrolled()
    }

    function scrollBy(amount) {
        if (!contentScrollable)
            return

        var maxY = Math.max(0, galleryView.contentHeight - galleryView.height)
        galleryView.contentY = Math.max(0, Math.min(maxY, galleryView.contentY + amount))
        scrolled()
    }

    function scrollPageUp() {
        scrollBy(-Math.max(120, galleryView.height * 0.82))
    }

    function scrollPageDown() {
        scrollBy(Math.max(120, galleryView.height * 0.82))
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

            y: -160

            width: parent.width * 0.72
            height: 300
            radius: 150

            color: root.actionSelected ? root.dangerRed : root.focusBlue
            opacity: root.focused ? 0.024 + root.glowPulse * 0.024 : 0.010
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
                            GALLERY GRID
        ============================================================
    */

    GridView {
        id: galleryView

        anchors.fill: parent

        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 20
        anchors.bottomMargin: 20

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

        delegate: Item {
            width: root.cardWidth
            height: root.cardHeight

            x: Math.round((root.cellWidth - width) / 2)
            y: 8

            property bool tileFocused: root.focused && index === root.selectedIndex
            property bool tileArmed: index === root.armedIndex
            property color accent: root.accentForKind(model.kind || model.type || "file",
                                                      model.isDirectory === true,
                                                      tileArmed)

            scale: tileFocused ? 1.045 : 1.0

            Behavior on scale {
                NumberAnimation {
                    duration: 145
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent

                radius: 26

                color: tileArmed
                       ? "#2A0A10E8"
                       : tileFocused
                         ? "#104D86E8"
                         : "#071426AA"

                border.width: tileFocused || tileArmed ? 2 : 1
                border.color: tileArmed
                              ? root.dangerRed
                              : tileFocused
                                ? root.focusBlue
                                : "#244B66"

                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1

                    radius: parent.radius - 1
                    color: "#FFFFFF"
                    opacity: tileFocused || tileArmed ? 0.050 : 0.026
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    height: 124
                    radius: 24

                    color: "#061A2E"

                    border.width: 1
                    border.color: accent

                    opacity: 0.96

                    clip: true

                    Rectangle {
                        anchors.centerIn: parent

                        width: parent.width * 0.68
                        height: parent.height * 0.68
                        radius: height / 2

                        color: accent
                        opacity: tileFocused || tileArmed
                                 ? 0.055 + root.glowPulse * 0.050
                                 : 0.026
                    }

                    Text {
                        anchors.centerIn: parent

                        text: root.iconTextForKind(model.kind || model.type || "file",
                                                   model.extension || "",
                                                   model.isDirectory === true)

                        color: tileArmed ? "#FFD1D1" : "#FFFFFF"

                        font.pixelSize: text.length > 3 ? 22 : 42
                        font.bold: true

                        style: Text.Raised
                        styleColor: "#66000000"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10

                        width: parent.width * 0.36
                        height: 2
                        radius: 1

                        color: accent
                        opacity: tileFocused || tileArmed
                                 ? 0.44 + root.glowPulse * 0.28
                                 : 0.18
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 138

                    anchors.leftMargin: 14
                    anchors.rightMargin: 14

                    text: model.name || "Untitled"

                    color: tileArmed ? "#FFD1D1" : root.textPrimary

                    font.pixelSize: 15
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12

                    anchors.leftMargin: 14
                    anchors.rightMargin: 14

                    text: model.isDirectory === true
                          ? "FOLDER"
                          : String(model.kind || model.extension || "FILE").toUpperCase()

                    color: accent

                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.0

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                visible: tileFocused

                anchors.fill: parent
                anchors.margins: -5

                radius: 31

                color: "transparent"

                border.width: 1
                border.color: root.focusBlue

                opacity: 0.42 + root.glowPulse * 0.24
            }

            Rectangle {
                visible: tileArmed

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 10
                anchors.topMargin: 10

                width: 26
                height: 26
                radius: 13

                color: "#3A1116"

                border.width: 1
                border.color: root.dangerRed

                Text {
                    anchors.centerIn: parent

                    text: "!"

                    color: "#FFD1D1"

                    font.pixelSize: 15
                    font.bold: true
                }
            }
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
        spacing: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: "◫"

            color: root.focusBlue

            font.pixelSize: 58
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter

            text: "No gallery items"

            color: root.textPrimary

            font.pixelSize: 24
            font.bold: true
        }
    }

    onSelectedIndexChanged: ensureSelectedVisible()

    Component.onCompleted: {
        ensureSelectedVisible()
    }
}