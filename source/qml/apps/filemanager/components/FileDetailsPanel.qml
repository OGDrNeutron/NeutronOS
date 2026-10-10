import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE DETAILS PANEL
        ============================================================

        Right-side details panel.

        Current:
        - Shows armed/selected file metadata.
        - Visual only.
        - Main.qml owns controller routing.

        Backend-ready:
        - Uses normalized fileData roles now.
        - Later C++ can add checksum, owner, MIME type, permissions,
          preview thumbnails, media info, and mount details.
    */

    width: 330

    property var fileData: null
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
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: 3200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: 3200
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            HELPERS
        ============================================================
    */

    function value(keys, fallbackValue) {
        if (!fileData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            if (fileData[key] !== undefined && fileData[key] !== null)
                return fileData[key]
        }

        return fallbackValue
    }

    function fileName() {
        return String(value(["name", "fileName", "displayName"], "No item selected"))
    }

    function filePath() {
        return String(value(["path", "filePath", "absolutePath"], ""))
    }

    function fileKind() {
        return String(value(["kind", "type"], "file")).toLowerCase()
    }

    function fileExtension() {
        return String(value(["extension", "ext"], "")).toUpperCase()
    }

    function fileSizeText() {
        return String(value(["sizeText"], "0 B"))
    }

    function fileModified() {
        return String(value(["modified", "modifiedTime", "lastModified"], "—"))
    }

    function filePermissions() {
        return String(value(["permissions", "mode"], "—"))
    }

    function isDirectory() {
        return value(["isDirectory", "directory", "folder"], false) === true ||
               fileKind() === "folder"
    }

    function kindLabel() {
        if (isDirectory())
            return "FOLDER"

        if (fileExtension().length > 0)
            return fileExtension()

        return fileKind().toUpperCase()
    }

    function accentForKind() {
        var k = fileKind()

        if (isDirectory() || k === "folder")
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

        if (k === "document")
            return "#A7EEFF"

        return textSecondary
    }

    function iconTextForKind() {
        var k = fileKind()
        var ext = fileExtension()

        if (isDirectory() || k === "folder")
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
            return ext.substring(0, 4)

        return "•"
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 28

        color: "#061A2EF0"

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

            y: -110

            width: parent.width * 0.96
            height: 190
            radius: 95

            color: root.fileData ? root.accentForKind() : root.focusBlue
            opacity: root.focused ? 0.034 + root.glowPulse * 0.034 : 0.016
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -90
            anchors.bottomMargin: -110

            width: 220
            height: 220
            radius: 110

            color: root.purpleGlow
            opacity: 0.020
        }

        Rectangle {
            width: 92
            height: 2
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)

            anchors.bottom: parent.bottom

            color: root.fileData ? root.accentForKind() : root.focusBlue
            opacity: 0.24 + root.glowPulse * 0.14
        }
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        anchors.fill: parent
        anchors.margins: 22

        spacing: 18

        Row {
            width: parent.width
            height: 36

            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: "◈"

                color: root.fileData ? root.accentForKind() : root.focusBlue

                font.pixelSize: 18
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: "DETAILS"

                color: root.textPrimary

                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 1.6
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width - 108
                height: 1
                radius: 1

                color: root.fileData ? root.accentForKind() : root.focusBlue
                opacity: 0.28 + root.glowPulse * 0.12
            }
        }

        Rectangle {
            width: parent.width
            height: 150
            radius: 28

            color: "#071426D8"

            border.width: 1
            border.color: root.fileData ? root.accentForKind() : "#244B66"

            clip: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1

                radius: parent.radius - 1
                color: "#FFFFFF"
                opacity: 0.034
            }

            Rectangle {
                anchors.centerIn: parent

                width: 108
                height: 108
                radius: 32

                color: "#061A2EDD"

                border.width: 2
                border.color: root.fileData ? root.accentForKind() : "#2A8DCC"

                Rectangle {
                    anchors.centerIn: parent

                    width: parent.width * 0.70
                    height: parent.height * 0.70
                    radius: height / 2

                    color: root.fileData ? root.accentForKind() : root.focusBlue
                    opacity: 0.040 + root.glowPulse * 0.040
                }

                Text {
                    anchors.centerIn: parent

                    text: root.fileData ? root.iconTextForKind() : "?"

                    color: "#FFFFFF"

                    font.pixelSize: text.length > 3 ? 26 : 46
                    font.bold: true

                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    style: Text.Raised
                    styleColor: "#66000000"
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14

                width: parent.width * 0.34
                height: 2
                radius: 1

                color: root.fileData ? root.accentForKind() : root.focusBlue
                opacity: 0.30 + root.glowPulse * 0.20
            }
        }

        Text {
            width: parent.width

            text: root.fileName()

            color: root.textPrimary

            font.pixelSize: 23
            font.bold: true

            horizontalAlignment: Text.AlignHCenter

            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
        }

        Rectangle {
            width: Math.max(84, kindText.implicitWidth + 28)
            height: 30
            radius: 15

            anchors.horizontalCenter: parent.horizontalCenter

            color: "#071426D8"

            border.width: 1
            border.color: root.fileData ? root.accentForKind() : "#2A8DCC"

            Text {
                id: kindText

                anchors.centerIn: parent

                text: root.fileData ? root.kindLabel() : "NONE"

                color: root.fileData ? root.accentForKind() : root.textMuted

                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.0
            }
        }

        DetailsRow {
            label: "SIZE"
            value: root.isDirectory() ? "Folder" : root.fileSizeText()
            accent: root.fileData ? root.accentForKind() : root.focusBlue
        }

        DetailsRow {
            label: "MODIFIED"
            value: root.fileModified()
            accent: root.fileData ? root.accentForKind() : root.focusBlue
        }

        DetailsRow {
            label: "PERMISSIONS"
            value: root.filePermissions()
            accent: root.fileData ? root.accentForKind() : root.focusBlue
        }

        DetailsRow {
            label: "PATH"
            value: root.filePath().length > 0 ? root.filePath() : "—"
            accent: root.fileData ? root.accentForKind() : root.focusBlue
            tall: true
        }

        Item {
            width: 1
            height: 1
        }

        Text {
            width: parent.width

            text: root.fileData
                  ? "X ACTIONS  •  O CLOSE"
                  : "NO FILE SELECTED"

            color: root.textMuted

            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.1

            horizontalAlignment: Text.AlignHCenter

            opacity: 0.78
        }
    }

    /*
        ============================================================
                            COMPONENTS
        ============================================================
    */

    component DetailsRow: Rectangle {
        id: rowRoot

        property string label: ""
        property string value: ""
        property color accent: "#7DF9FF"
        property bool tall: false

        width: parent ? parent.width : 280
        height: tall ? 74 : 48
        radius: 18

        color: "#071426B8"

        border.width: 1
        border.color: "#244B66"

        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: 3
            radius: 2

            color: rowRoot.accent
            opacity: 0.54
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            anchors.leftMargin: 16
            anchors.rightMargin: 14

            spacing: 2

            Text {
                width: parent.width

                text: rowRoot.label

                color: rowRoot.accent

                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.2

                elide: Text.ElideRight
            }

            Text {
                width: parent.width

                text: rowRoot.value

                color: "#F3FCFF"

                font.pixelSize: rowRoot.tall ? 11 : 13
                font.bold: true

                maximumLineCount: rowRoot.tall ? 3 : 1
                wrapMode: rowRoot.tall ? Text.Wrap : Text.NoWrap
                elide: rowRoot.tall ? Text.ElideNone : Text.ElideRight
            }
        }
    }
}