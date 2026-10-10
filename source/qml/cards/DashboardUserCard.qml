import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                        DASHBOARD / CONSOLE USER CARD
        ============================================================

        Used by Console header/user area.

        Preserved from original:
            - userName
            - userIcon
            - centered user image
            - username text
            - Sleep • Logout text
            - purple accent

        Next-gen updates:
            - Safe UserManager fallback.
            - Safe AssetManager fallback.
            - Controller-first action handling.
            - X/primary opens user options by default.
            - Can request sleep/logout as signals.
            - User icon falls back to themes/Default/users/user_icon.png.
            - No hard crash if managers are missing.
            - Animations pause when hidden.
            - Focus/armed visual state supported through GlassCard.
    */

    property string userName: ""
    property string userIcon: ""

    property string roleText: ""
    property string statusText: "Sleep • Logout"

    property bool showRole: roleText.length > 0
    property bool showStatus: statusText.length > 0
    property bool animationsEnabled: visible && enabled

    property color userAccent: "#c084fc"
    property color focusAccent: "#7df9ff"
    property color armedAccent: "#ff3040"
    property color mutedText: "#8aa6c8"

    property real pulse: 0.55

    signal optionsRequested()
    signal sleepRequested()
    signal logoutRequested()
    signal userRequested()

    accent: armed ? armedAccent :
            focused ? focusAccent :
                      userAccent

    implicitWidth: 170
    implicitHeight: showRole ? 166 : 148

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function userBackend() {
        try {
            if (typeof userManager !== "undefined" && userManager)
                return userManager
        } catch (e) {
        }

        return null
    }

    function assetBackend() {
        try {
            if (typeof assetManager !== "undefined" && assetManager)
                return assetManager
        } catch (e) {
        }

        return null
    }

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var text = String(value).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function currentUserMap() {
        var backend = userBackend()

        if (!backend)
            return null

        try {
            if (backend.currentUser)
                return backend.currentUser
        } catch (e) {
        }

        try {
            if (backend.users && backend.users.length > 0)
                return backend.users[0]
        } catch (e2) {
        }

        return null
    }

    function backendUserName() {
        var user = currentUserMap()

        if (!user)
            return ""

        try {
            var display = cleanText(user.displayName)

            if (display.length > 0)
                return display
        } catch (e) {
        }

        try {
            var name = cleanText(user.username)

            if (name.length > 0)
                return name
        } catch (e2) {
        }

        return ""
    }

    function backendRoleText() {
        var user = currentUserMap()

        if (!user)
            return ""

        try {
            var role = cleanText(user.role)

            if (role.length > 0)
                return role
        } catch (e) {
        }

        return ""
    }

    function shownUserName() {
        var direct = cleanText(userName)

        if (direct.length > 0)
            return direct

        var backend = backendUserName()

        if (backend.length > 0)
            return backend

        return "User"
    }

    function shownRoleText() {
        var direct = cleanText(roleText)

        if (direct.length > 0)
            return direct

        return backendRoleText()
    }

    function isAbsoluteSource(value) {
        var text = String(value || "").trim().toLowerCase()

        return text.indexOf("file:") === 0 ||
               text.indexOf("qrc:") === 0 ||
               text.indexOf("http://") === 0 ||
               text.indexOf("https://") === 0 ||
               text.indexOf("image://") === 0
    }

    function themeFile(path) {
        var cleanPath = cleanText(path)

        if (cleanPath.length <= 0)
            return ""

        if (isAbsoluteSource(cleanPath))
            return cleanPath

        var assets = assetBackend()

        if (assets && typeof assets.themeFile === "function") {
            try {
                return assets.themeFile(cleanPath)
            } catch (e) {
            }
        }

        return "../themes/Default/" + cleanPath
    }

    function shownUserIcon() {
        var direct = cleanText(userIcon)

        if (direct.length > 0) {
            if (isAbsoluteSource(direct))
                return direct

            if (direct.indexOf("/") >= 0)
                return themeFile(direct)

            return themeFile("users/" + direct)
        }

        var assets = assetBackend()

        if (assets && typeof assets.userIcon === "function") {
            try {
                var icon = cleanText(assets.userIcon())

                if (icon.length > 0)
                    return icon
            } catch (e) {
            }
        }

        return themeFile("users/user_icon.png")
    }

    function handleController(action) {
        if (action === "primary" || action === "x") {
            root.optionsRequested()
            root.userRequested()
            return true
        }

        if (action === "cancel" || action === "o") {
            return false
        }

        if (action === "system" || action === "start") {
            root.optionsRequested()
            return true
        }

        return false
    }

    function activate() {
        root.optionsRequested()
        root.userRequested()
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || root.armed)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.42
            to: 1.0
            duration: root.armed ? 600 : 1700
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: root.armed ? 600 : 1700
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        id: content

        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10

        spacing: root.showRole || root.showStatus ? 7 : 9

        Item {
            id: avatarWrap

            width: root.focused || root.armed ? 64 : 58
            height: width

            anchors.horizontalCenter: parent.horizontalCenter

            Behavior on width {
                enabled: root.animationsEnabled

                NumberAnimation {
                    duration: 170
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent

                radius: width / 2

                color: root.armed ? "#26080CDD" :
                       root.focused ? "#071426EE" :
                                      "#071426CC"

                border.width: root.focused || root.armed ? 2 : 1
                border.color: root.accent

                opacity: 1.0
            }

            Rectangle {
                anchors.centerIn: parent

                width: parent.width + 14
                height: width
                radius: width / 2

                color: "transparent"

                border.width: root.focused || root.armed ? 1 : 0
                border.color: root.accent

                opacity: root.armed ? 0.22 + root.pulse * 0.26 :
                         root.focused ? 0.16 + root.pulse * 0.20 :
                                        0.0
            }

            Image {
                id: avatar

                anchors.fill: parent
                anchors.margins: 5

                source: root.shownUserIcon()

                fillMode: Image.PreserveAspectCrop

                smooth: true
                cache: true
                asynchronous: true
                sourceSize.width: 256
                sourceSize.height: 256
                mipmap: false

                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            Text {
                visible: avatar.status !== Image.Ready

                anchors.centerIn: parent

                text: root.shownUserName().length > 0
                      ? root.shownUserName().charAt(0).toUpperCase()
                      : "U"

                color: "white"

                font.pixelSize: 25
                font.bold: true
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 5

                radius: width / 2

                color: "transparent"

                border.width: 1
                border.color: "#55FFFFFF"

                opacity: 0.45
            }
        }

        Text {
            id: nameText

            width: parent.width

            text: root.shownUserName()

            color: "white"

            font.pixelSize: root.focused || root.armed ? 15 : 14
            font.bold: true
            font.letterSpacing: 0.2

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#99000000"
        }

        Text {
            visible: root.shownRoleText().length > 0

            width: parent.width

            text: root.shownRoleText().toUpperCase()

            color: root.focused || root.armed ? "#d8c7ff" : "#bda7f5"

            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.0

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.88
        }

        Text {
            visible: root.showStatus

            width: parent.width

            text: root.statusText

            color: root.armed ? "#ffd1d1" :
                   root.focused ? "#9fd8ff" :
                                  root.mutedText

            font.pixelSize: 10
            font.bold: root.focused || root.armed
            font.letterSpacing: 0.3

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /*
        ============================================================
                            FOCUS / ARMED STRIP
        ============================================================
    */

    Rectangle {
        visible: root.focused || root.armed

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: root.armed ? 5 : 3

        color: root.accent
        opacity: root.armed ? 0.72 + root.pulse * 0.28 :
                              0.52 + root.pulse * 0.22
    }

    /*
        ============================================================
                            TOUCH / TEST FALLBACK
        ============================================================

        Controller remains primary. This allows preview/touch testing only.
    */

    onClicked: root.activate()
}