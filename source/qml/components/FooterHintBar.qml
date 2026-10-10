import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                              FOOTER HINT BAR
        ============================================================

        Production behavior:
            - Footer hint bar exists only during:
                1) First login.
                2) First app open.
                3) Normal app footer while an app is active.

            - After first login:
                Lock screen shows NO footer.

            - After first app open:
                Console shows NO footer.
                Lock screen shows NO footer.
                Apps show the app footer only.

        App footer layout:
            Left:   app name Vx.xx
            Center: Secure.Local.Yours
            Right:  PoweredByNeutronOS

        Important:
            - Right side is exactly one word:
                PoweredByNeutronOS

            - Center text is exactly:
                Secure.Local.Yours

            - No MouseArea.
            - No Button.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text only.
            - Controller-first visual language.
    */

    /*
        Recommended mode values:
            "auto"
            "none"
            "firstLogin"
            "firstAppOpen"
            "app"
    */
    property string mode: "auto"

    /*
        Scene state passed by Main.qml / Console.qml / AppHost.qml.
    */
    property bool lockScreenActive: false
    property bool consoleActive: false
    property bool appActive: false

    /*
        These should be controlled by the real backend/state manager later.
        The component does not persist them by itself.
    */
    property bool firstLoginHintAvailable: false
    property bool firstAppOpenHintAvailable: false

    /*
        App footer data.
    */
    property string appName: "App"
    property string appVersion: "0.1.0"
    property string appVersionPrefix: "V"

    property string centerText: "Secure.Local.Yours"
    property string poweredText: "PoweredByNeutronOS"

    /*
        First-run hint text.
        These are only used during first login or first app open.
    */
    property string firstLoginLeftText: "X Select"
    property string firstLoginCenterText: "Secure.Local.Yours"
    property string firstLoginRightText: "O Back"

    property string firstAppLeftText: "X Select"
    property string firstAppCenterText: "App controls active"
    property string firstAppRightText: "O Exit App"

    property bool animationsEnabled: visible && enabled
    property bool glassVisible: true

    property color glassColor: "#06101fcc"
    property color borderColor: "#335d8f88"
    property color topLineColor: "#7df9ff"
    property color textColor: "#cfeaff"
    property color centerColor: "#ffffff"
    property color mutedColor: "#8aa6c8"

    property real pulse: 0.45
    property real sweep: -1.0

    implicitHeight: 46
    height: implicitHeight

    visible: resolvedMode() !== "none"
    opacity: visible ? 1.0 : 0.0

    Behavior on opacity {
        enabled: true

        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.35
            to: 1.0
            duration: 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.35
            duration: 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled
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

    /*
        ============================================================
                            BACKGROUND
        ============================================================
    */

    Rectangle {
        anchors.fill: parent

        visible: root.glassVisible

        color: root.glassColor

        border.width: 1
        border.color: root.borderColor

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            height: 1

            color: root.topLineColor
            opacity: 0.24 + root.pulse * 0.08
        }

        Rectangle {
            width: Math.max(90, parent.width * 0.16)
            height: 1
            radius: 1

            x: (parent.width - width) * ((root.sweep + 1.0) / 2.0)
            y: 0

            color: root.topLineColor
            opacity: 0.22 + root.pulse * 0.14
        }
    }

    /*
        ============================================================
                            FOOTER TEXT
        ============================================================
    */

    Item {
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 26

        Text {
            id: leftText

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            width: Math.max(120, parent.width * 0.30)

            text: root.leftLabel()

            color: root.textColor

            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 0.8

            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            id: centerLabel

            anchors.centerIn: parent

            width: Math.max(180, parent.width * 0.34)

            text: root.centerLabel()

            color: root.centerColor

            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 1.1

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            id: rightText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            width: Math.max(160, parent.width * 0.30)

            text: root.rightLabel()

            color: root.textColor

            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 0.8

            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /*
        ============================================================
                            MODE RESOLUTION
        ============================================================
    */

    function resolvedMode() {
        var requested = String(mode || "auto")

        if (requested === "none")
            return "none"

        if (requested === "firstLogin")
            return firstLoginHintAvailable ? "firstLogin" : "none"

        if (requested === "firstAppOpen")
            return firstAppOpenHintAvailable ? "firstAppOpen" : "none"

        if (requested === "app")
            return appActive ? "app" : "none"

        /*
            Auto mode rules:
                - First login footer only while lock screen/login is active.
                - First app-open footer only while an app is active.
                - Normal app footer only while an app is active.
                - Console gets no footer.
                - Lock screen after first login gets no footer.
        */
        if (lockScreenActive && firstLoginHintAvailable)
            return "firstLogin"

        if (appActive && firstAppOpenHintAvailable)
            return "firstAppOpen"

        if (appActive)
            return "app"

        /*
            Explicitly no footer on Console or normal LockScreen.
        */
        if (consoleActive || lockScreenActive)
            return "none"

        return "none"
    }

    function leftLabel() {
        var current = resolvedMode()

        if (current === "firstLogin")
            return firstLoginLeftText

        if (current === "firstAppOpen")
            return firstAppLeftText

        if (current === "app")
            return appFooterLeftText()

        return ""
    }

    function centerLabel() {
        var current = resolvedMode()

        if (current === "firstLogin")
            return firstLoginCenterText

        if (current === "firstAppOpen")
            return firstAppCenterText

        if (current === "app")
            return centerText

        return ""
    }

    function rightLabel() {
        var current = resolvedMode()

        if (current === "firstLogin")
            return firstLoginRightText

        if (current === "firstAppOpen")
            return firstAppRightText

        if (current === "app")
            return poweredText

        return ""
    }

    function appFooterLeftText() {
        var cleanName = cleanText(appName)
        var cleanVersion = cleanText(appVersion)

        if (cleanName.length <= 0)
            cleanName = "App"

        if (cleanVersion.length <= 0)
            return cleanName

        return cleanName + " " + appVersionPrefix + cleanVersion
    }

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var text = String(value).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.45
            sweep = -1.0
        }
    }
}