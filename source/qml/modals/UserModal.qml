import QtQuick 2.15
import "../common"

Rectangle {
    id: root

    /*
        ============================================================
                              USER MODAL
        ============================================================

        Preserved from original:
            - Full-screen modal overlay.
            - userName property.
            - selectedTab / armedTab.
            - Log Out.
            - Sleep.
            - Restart.
            - Power Off.
            - Profile.
            - Close.
            - closed().
            - logoutRequested().
            - sleepRequested().
            - restartRequested().
            - powerOffRequested().
            - profileRequested().
            - Keyboard fallback.
            - Controller navigation.
            - ModalTabButton usage.
            - Background click closes.
            - Panel click does not close.

        Next-gen updates:
            - Explicit QtQuick 2.15 import.
            - Safe controllerManager access.
            - Safe assetManager access.
            - Optional activeUser/profile icon support.
            - Proper focus vs armed state.
            - Restart and Power Off require arming first.
            - O cancels armed state before closing.
            - START/OPTIONS confirms selected tab.
            - Expanded controller aliases.
            - Pointer fallback is optional.
            - Animations pause when hidden.
            - No placeholder behavior.
    */

    property string userName: "User"
    property var activeUser: null
    property string userIcon: ""

    property int armedTab: -1
    property int selectedTab: 0
    property int columns: 2

    property bool pointerEnabled: true
    property bool animationsEnabled: visible && enabled

    property color neutronBlue: "#7df9ff"
    property color focusBlue: "#4da6ff"
    property color dangerRed: "#ff3040"
    property color successGreen: "#22ff88"
    property color warningGold: "#f5c542"
    property color mutedBlue: "#8aa6c8"
    property color purpleAccent: "#c084fc"

    property real pulse: 0.48
    property real sweep: -1.0

    signal closed()
    signal logoutRequested()
    signal sleepRequested()
    signal restartRequested()
    signal powerOffRequested()
    signal profileRequested()

    anchors.fill: parent
    visible: false
    color: "#02040cf2"
    z: 999
    focus: visible
    Keys.enabled: visible

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
            duration: root.armedTab >= 0 ? 620 : 1700
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.35
            duration: root.armedTab >= 0 ? 620 : 1700
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armedTab >= 0 ? 1200 : 3600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armedTab >= 0 ? 1200 : 3600
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                API
        ============================================================
    */

    function open(name, userObject) {
        if (name !== undefined && name !== null && String(name).trim().length > 0)
            userName = String(name)
        else if (userObject)
            userName = userNameFromObject(userObject)
        else
            userName = "User"

        if (userObject !== undefined && userObject !== null)
            activeUser = userObject

        selectedTab = 0
        armedTab = -1
        visible = true
        root.forceActiveFocus()
        clampSelected()
    }

    function close() {
        visible = false
        selectedTab = 0
        armedTab = -1
        closed()
    }

    function tabCount() {
        return 6
    }

    function clampSelected() {
        var count = tabCount()

        if (count <= 0) {
            selectedTab = 0
            armedTab = -1
            return
        }

        if (selectedTab < 0)
            selectedTab = count - 1

        if (selectedTab >= count)
            selectedTab = 0

        if (armedTab >= count)
            armedTab = -1
    }

    function moveSelection(delta) {
        if (!visible || tabCount() <= 0)
            return false

        selectedTab = (selectedTab + delta + tabCount()) % tabCount()

        /*
            Moving selection cancels confirmation.
        */
        armedTab = -1

        return true
    }

    function activateSelected() {
        clampSelected()

        if (tabDanger(selectedTab) && armedTab !== selectedTab) {
            armedTab = selectedTab
            return true
        }

        runTab(selectedTab)
        return true
    }

    function cancelOrClose() {
        if (armedTab >= 0) {
            armedTab = -1
            return true
        }

        close()
        return true
    }

    function runTab(index) {
        armedTab = index

        if (index === 0) {
            logoutRequested()
            close()
            return
        }

        if (index === 1) {
            sleepRequested()
            close()
            return
        }

        if (index === 2) {
            restartRequested()
            return
        }

        if (index === 3) {
            powerOffRequested()
            return
        }

        if (index === 4) {
            profileRequested()
            close()
            return
        }

        if (index === 5) {
            close()
            return
        }
    }

    /*
        ============================================================
                            TAB HELPERS
        ============================================================
    */

    function tabTitle(index) {
        if (index === 0)
            return "Log Out"

        if (index === 1)
            return "Sleep"

        if (index === 2)
            return "Restart"

        if (index === 3)
            return "Power Off"

        if (index === 4)
            return "Profile"

        if (index === 5)
            return "Close"

        return "Action"
    }

    function tabSubtitle(index) {
        if (armedTab === index && tabDanger(index))
            return "Press X again to confirm"

        if (index === 0)
            return "Return to login"

        if (index === 1)
            return "Start screensaver"

        if (index === 2)
            return "Reboot system"

        if (index === 3)
            return "Shutdown safely"

        if (index === 4)
            return "User settings"

        if (index === 5)
            return "Back to console"

        return ""
    }

    function tabDanger(index) {
        return index === 2 || index === 3
    }

    function selectedTabName() {
        return tabTitle(selectedTab)
    }

    /*
        ============================================================
                            CONTROLLER INPUT
        ============================================================
    */

    function normalizeController(button) {
        var b = String(button || "").trim().toUpperCase()

        if (b === "DPAD_LEFT" || b === "LEFT")
            return "LEFT"

        if (b === "DPAD_RIGHT" || b === "RIGHT")
            return "RIGHT"

        if (b === "DPAD_UP" || b === "UP")
            return "UP"

        if (b === "DPAD_DOWN" || b === "DOWN")
            return "DOWN"

        if (b === "PRIMARY" ||
                b === "CROSS" ||
                b === "A" ||
                b === "X" ||
                b === "PS_CROSS") {
            return "X"
        }

        if (b === "CANCEL" ||
                b === "CIRCLE" ||
                b === "B" ||
                b === "O" ||
                b === "PS_CIRCLE") {
            return "O"
        }

        if (b === "CONTEXT" ||
                b === "TRI" ||
                b === "TRIANGLE" ||
                b === "Y" ||
                b === "PS_TRIANGLE") {
            return "TRIANGLE"
        }

        if (b === "SYSTEM" ||
                b === "START" ||
                b === "OPTIONS" ||
                b === "OPTION" ||
                b === "MENU") {
            return "START"
        }

        return b
    }

    function handleController(button) {
        if (!visible)
            return false

        var action = normalizeController(button)

        if (action === "LEFT") {
            return moveSelection(-1)
        }

        if (action === "RIGHT") {
            return moveSelection(1)
        }

        if (action === "UP") {
            return moveSelection(-columns)
        }

        if (action === "DOWN") {
            return moveSelection(columns)
        }

        if (action === "X" || action === "START") {
            return activateSelected()
        }

        if (action === "O") {
            return cancelOrClose()
        }

        if (action === "TRIANGLE") {
            selectedTab = 4
            profileRequested()
            close()
            return true
        }

        return true
    }

    function handleControllerPressed(button) {
        return handleController(button)
    }

    function handleControllerReleased(button) {
        return visible
    }

    /*
        ============================================================
                            SAFE HELPERS
        ============================================================
    */

    function controllerBackend() {
        try {
            if (typeof controllerManager !== "undefined" && controllerManager)
                return controllerManager
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

    function userNameFromObject(userObject) {
        if (!userObject)
            return "User"

        try {
            if (cleanText(userObject.displayName).length > 0)
                return String(userObject.displayName)
        } catch (e) {
        }

        try {
            if (cleanText(userObject.name).length > 0)
                return String(userObject.name)
        } catch (e2) {
        }

        try {
            if (cleanText(userObject.username).length > 0)
                return String(userObject.username)
        } catch (e3) {
        }

        return "User"
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

    function resolvedUserIcon() {
        var direct = cleanText(userIcon)

        if (direct.length > 0) {
            if (isAbsoluteSource(direct))
                return direct

            if (direct.indexOf("/") >= 0)
                return themeFile(direct)

            return themeFile("users/" + direct)
        }

        if (activeUser) {
            try {
                var icon = cleanText(activeUser.icon)

                if (icon.length > 0) {
                    if (isAbsoluteSource(icon))
                        return icon

                    if (icon.indexOf("/") >= 0)
                        return themeFile(icon)

                    return themeFile("users/" + icon)
                }
            } catch (e) {
            }

            try {
                var iconPath = cleanText(activeUser.iconPath)

                if (iconPath.length > 0)
                    return isAbsoluteSource(iconPath) ? iconPath : themeFile(iconPath)
            } catch (e2) {
            }
        }

        return themeFile("users/user_icon.png")
    }

    function userInitial() {
        var name = cleanText(userName)

        if (name.length <= 0)
            name = userNameFromObject(activeUser)

        if (name.length <= 0)
            return "U"

        return name.charAt(0).toUpperCase()
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.onLeftPressed: moveSelection(-1)
    Keys.onRightPressed: moveSelection(1)
    Keys.onUpPressed: moveSelection(-columns)
    Keys.onDownPressed: moveSelection(columns)
    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()
    Keys.onEscapePressed: cancelOrClose()
    Keys.onBackPressed: cancelOrClose()

    /*
        ============================================================
                            POINTER FALLBACK
        ============================================================
    */

    MouseArea {
        anchors.fill: parent

        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton

        onClicked: root.cancelOrClose()
    }

    /*
        ============================================================
                                PANEL
        ============================================================
    */

    Rectangle {
        id: modalBg

        width: Math.min(parent.width * 0.58, 940)
        height: Math.min(parent.height * 0.62, 660)

        anchors.centerIn: parent

        radius: 32

        color: "#071426f5"

        border.color: root.armedTab >= 0 ? root.dangerRed : root.purpleAccent
        border.width: root.armedTab >= 0 ? 4 : 3

        activeFocusOnTab: true

        scale: root.visible ? 1.0 : 0.94
        opacity: root.visible ? 1.0 : 0.0

        Behavior on scale {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            enabled: root.animationsEnabled

            ColorAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2

            radius: parent.radius - 2
            color: "#10172ad9"

            border.color: "#223d7dff"
            border.width: 1
            z: -1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.topMargin: 16

            height: 1

            color: root.armedTab >= 0 ? root.dangerRed : root.purpleAccent
            opacity: 0.65 + root.pulse * 0.20
        }

        Rectangle {
            visible: root.animationsEnabled

            width: Math.max(80, parent.width * 0.18)
            height: 2
            radius: 1

            x: 28 + (parent.width - 56 - width) * ((root.sweep + 1.0) / 2.0)
            y: 22

            color: root.armedTab >= 0 ? root.dangerRed : root.purpleAccent
            opacity: root.armedTab >= 0 ? 0.50 + root.pulse * 0.24 :
                                           0.28 + root.pulse * 0.18
        }

        Rectangle {
            visible: root.armedTab >= 0

            anchors.fill: parent
            anchors.margins: -16

            radius: parent.radius + 16
            color: root.dangerRed
            opacity: 0.035 + root.pulse * 0.030
            z: -2
        }

        MouseArea {
            anchors.fill: parent

            enabled: root.pointerEnabled
            acceptedButtons: Qt.LeftButton

            onClicked: function(mouse) {
                mouse.accepted = true
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 30

            spacing: 18

            /*
                Header
            */

            Row {
                width: parent.width
                height: 104

                spacing: 18

                Rectangle {
                    id: avatarShell

                    width: 92
                    height: 92
                    radius: 46

                    anchors.verticalCenter: parent.verticalCenter

                    color: "#101d42dd"

                    border.width: 3
                    border.color: root.purpleAccent

                    clip: true

                    Image {
                        id: avatarImage

                        anchors.fill: parent

                        source: root.resolvedUserIcon()
                        fillMode: Image.PreserveAspectCrop

                        smooth: true
                        cache: true
                        asynchronous: true
                        mipmap: true

                        opacity: status === Image.Ready ? 1.0 : 0.0
                    }

                    Text {
                        visible: avatarImage.status !== Image.Ready

                        anchors.centerIn: parent

                        text: root.userInitial()

                        color: "white"

                        font.pixelSize: 36
                        font.bold: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 5

                        radius: width / 2
                        color: "transparent"

                        border.width: 1
                        border.color: "#66ffffff"
                    }
                }

                Column {
                    width: parent.width - avatarShell.width - 22
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        width: parent.width

                        text: root.userName

                        color: "white"

                        font.pixelSize: 36
                        font.bold: true

                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width

                        text: "User session controls"

                        color: "#9fd8ff"

                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 1.1

                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Text {
                        width: parent.width

                        text: root.armedTab >= 0
                              ? "ARMED: " + root.selectedTabName() + "  •  Press X again to confirm  •  O cancels"
                              : "D-PAD move  •  X select  •  O close"

                        color: root.armedTab >= 0 ? "#ffb1b1" : "#b9eeff"

                        font.pixelSize: 13
                        font.bold: true
                        font.letterSpacing: 1.0

                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1

                color: root.armedTab >= 0 ? root.dangerRed : root.purpleAccent
                opacity: 0.30
            }

            /*
                Action grid.
            */

            Grid {
                id: tabGrid

                width: parent.width
                columns: root.columns
                spacing: 16

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Log Out"
                    subtext: root.tabSubtitle(0)

                    focused: root.selectedTab === 0
                    active: root.selectedTab === 0
                    armed: root.armedTab === 0
                    danger: false

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 0
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Sleep"
                    subtext: root.tabSubtitle(1)

                    focused: root.selectedTab === 1
                    active: root.selectedTab === 1
                    armed: root.armedTab === 1
                    danger: false

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 1
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Restart"
                    subtext: root.tabSubtitle(2)

                    focused: root.selectedTab === 2
                    active: root.selectedTab === 2
                    armed: root.armedTab === 2
                    danger: true

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 2
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Power Off"
                    subtext: root.tabSubtitle(3)

                    focused: root.selectedTab === 3
                    active: root.selectedTab === 3
                    armed: root.armedTab === 3
                    danger: true

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 3
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Profile"
                    subtext: root.tabSubtitle(4)

                    focused: root.selectedTab === 4
                    active: root.selectedTab === 4
                    armed: root.armedTab === 4
                    danger: false

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 4
                        root.activateSelected()
                    }
                }

                ModalTabButton {
                    width: (tabGrid.width - tabGrid.spacing) / 2
                    height: 76

                    text: "Close"
                    subtext: root.tabSubtitle(5)

                    focused: root.selectedTab === 5
                    active: root.selectedTab === 5
                    armed: root.armedTab === 5
                    danger: false

                    pointerEnabled: root.pointerEnabled
                    pointerFocusEnabled: false

                    onClicked: {
                        root.selectedTab = 5
                        root.close()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 54
                radius: 22

                color: root.armedTab >= 0 ? "#26080caa" : "#071426aa"

                border.width: 1
                border.color: root.armedTab >= 0 ? root.dangerRed : "#4da6ff66"

                Text {
                    anchors.centerIn: parent

                    width: parent.width - 28

                    text: root.armedTab >= 0
                          ? "Danger action armed. Press X again to continue."
                          : "Session actions are local to NeutronOS."

                    color: root.armedTab >= 0 ? "#ffd1d1" : "#9fd8ff"

                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.0

                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    /*
        ============================================================
                            CONTROLLER CONNECTION
        ============================================================
    */

    Connections {
        target: root.controllerBackend()
        enabled: root.visible
        ignoreUnknownSignals: true

        function onButtonPressed(button) {
            root.handleController(button)
        }

        function onStickMoved(stick, x, y) {
            if (!root.visible)
                return

            var threshold = 55

            if (x > threshold)
                root.handleController("RIGHT")
            else if (x < -threshold)
                root.handleController("LEFT")
            else if (y > threshold)
                root.handleController("DOWN")
            else if (y < -threshold)
                root.handleController("UP")
        }
    }

    onSelectedTabChanged: {
        clampSelected()
    }

    onVisibleChanged: {
        if (!visible)
            armedTab = -1
    }
}