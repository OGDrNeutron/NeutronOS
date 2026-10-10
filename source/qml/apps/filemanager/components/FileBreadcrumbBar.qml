import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            FILE BREADCRUMB BAR
        ============================================================

        Path display below the view toolbar.

        Current:
        - Visual breadcrumb path.
        - Shows each path segment as a small glass chip.
        - Not part of the main controller focus loop yet.

        Future:
        - Can become controller-selectable for jumping to parent paths.
        - Already emits pathRequested(path).
    */

    height: 42

    property string currentPath: "/home/echo"
    property bool focused: false

    property color focusBlue: "#7DF9FF"
    property color electricBlue: "#1A8CFF"
    property color purpleGlow: "#A855F7"
    property color textPrimary: "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"

    property real glowPulse: 0.35

    signal pathRequested(string path)

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

    function cleanPath() {
        var path = String(currentPath || "/home/echo")

        while (path.length > 1 && path.endsWith("/"))
            path = path.substring(0, path.length - 1)

        if (path.length <= 0)
            path = "/"

        return path
    }

    function pathParts() {
        var path = cleanPath()

        if (path === "/")
            return [
                {
                    "label": "Root",
                    "path": "/",
                    "root": true
                }
            ]

        var split = path.split("/")
        var result = []
        var built = ""

        result.push({
            "label": "Root",
            "path": "/",
            "root": true
        })

        for (var i = 0; i < split.length; i++) {
            var part = String(split[i] || "")

            if (part.length <= 0)
                continue

            built += "/" + part

            result.push({
                "label": part,
                "path": built,
                "root": false
            })
        }

        return result
    }

    function parentPath() {
        var path = cleanPath()

        if (path === "/")
            return "/"

        var idx = path.lastIndexOf("/")

        if (idx <= 0)
            return "/"

        return path.substring(0, idx)
    }

    /*
        ============================================================
                            GLASS SHELL
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        radius: 18

        color: "#061A2EB8"

        border.width: root.focused ? 2 : 1
        border.color: root.focused ? root.focusBlue : "#2A8DCC"

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
            opacity: 0.14
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top

            y: -46

            width: parent.width * 0.42
            height: 82
            radius: 41

            color: root.focusBlue
            opacity: root.focused ? 0.024 + root.glowPulse * 0.020 : 0.010
        }
    }

    /*
        ============================================================
                            PATH ICON
        ============================================================
    */

    Rectangle {
        id: pathBadge

        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter

        width: 30
        height: 30
        radius: 11

        color: "#071426E8"

        border.width: 1
        border.color: root.focused ? root.focusBlue : "#2A8DCC"

        Text {
            anchors.centerIn: parent

            text: "⌁"

            color: root.focused ? "#FFFFFF" : root.textSecondary

            font.pixelSize: 17
            font.bold: true
        }
    }

    /*
        ============================================================
                            BREADCRUMBS
        ============================================================
    */

    Flickable {
        id: pathFlick

        anchors.left: pathBadge.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        anchors.leftMargin: 10
        anchors.rightMargin: 14

        contentWidth: pathRow.width
        contentHeight: height

        interactive: false
        clip: true

        Row {
            id: pathRow

            anchors.verticalCenter: parent.verticalCenter

            spacing: 7

            Repeater {
                model: root.pathParts()

                Row {
                    spacing: 7

                    Rectangle {
                        width: Math.max(52, labelText.implicitWidth + 24)
                        height: 28
                        radius: 14

                        color: index === root.pathParts().length - 1
                               ? "#104D86D8"
                               : "#071426B8"

                        border.width: index === root.pathParts().length - 1 ? 1 : 0
                        border.color: root.focusBlue

                        Text {
                            id: labelText

                            anchors.centerIn: parent

                            text: modelData.label

                            color: index === root.pathParts().length - 1
                                   ? "#FFFFFF"
                                   : root.textSecondary

                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 0.4

                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        visible: index < root.pathParts().length - 1

                        anchors.verticalCenter: parent.verticalCenter

                        text: "›"

                        color: root.textMuted

                        font.pixelSize: 18
                        font.bold: true

                        opacity: 0.78
                    }
                }
            }
        }
    }

    /*
        ============================================================
                            RIGHT FADE
        ============================================================
    */

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        width: 44

        color: "#061A2E"
        opacity: 0.74
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter

        text: "PATH"

        color: root.textMuted

        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.4

        opacity: 0.62
    }

    onCurrentPathChanged: {
        pathFlick.contentX = Math.max(0, pathFlick.contentWidth - pathFlick.width)
    }

    Component.onCompleted: {
        pathFlick.contentX = Math.max(0, pathFlick.contentWidth - pathFlick.width)
    }
}