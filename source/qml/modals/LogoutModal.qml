import QtQuick 2.15

Item {
    id: root

    /*
        Global controller-first session modal.

        The Console remains visible around the modal through the scrim, while
        the modal panel and every selectable surface are fully opaque.

        Stable controller order: Lock, Log Out, Restart NeutronOS,
        System Diagnostics, Recovery (Developer Mode only), Reboot, Shutdown.
    */

    property int selectedIndex: 0
    property bool pointerEnabled: true
    property var contextData: null
    property real focusPulse: 0.45
    property string armedActionId: ""
    readonly property bool developerModeEnabled: (typeof developerModeManager !== "undefined") &&
                                                   developerModeManager.developerModeEnabled === true

    readonly property color panelColor: "#071426"
    readonly property color cardColor: "#0A1729"
    readonly property color selectedCardColor: "#102A4A"
    readonly property color borderColor: "#315579"
    readonly property color focusColor: "#4DA6FF"
    readonly property color cyan: "#7DF9FF"
    readonly property color purple: "#C084FC"
    readonly property color yellow: "#FACC15"
    readonly property color red: "#FF3040"
    readonly property color textColor: "#FFFFFF"
    readonly property color mutedColor: "#91A9C5"

    readonly property var menuItems: [
        {
            "id": "lock",
            "name": "Lock",
            "subtitle": "Return to LoginScreen without ending the session",
            "accent": cyan,
            "danger": false
        },
        {
            "id": "logout",
            "name": "Log Out",
            "subtitle": "End the current user session and return to sign in",
            "accent": purple,
            "danger": false
        },
        {
            "id": "restart-shell",
            "name": "Restart NeutronOS",
            "subtitle": "Restart the shell without rebooting Linux",
            "accent": focusColor,
            "danger": true
        },
        {
            "id": "diagnostics",
            "name": "System Diagnostics",
            "subtitle": "Run the full controller-first health check without rebooting",
            "accent": "#74FF50",
            "danger": false
        }
    ].concat(developerModeEnabled ? [{
            "id": "recovery",
            "name": "Recovery Mode",
            "subtitle": "ONE BOOT ONLY • graphical shell disabled • local recovery terminal",
            "accent": yellow,
            "danger": true
        }] : []).concat([
        {
            "id": "reboot",
            "name": "Reboot System",
            "subtitle": "Restart Linux and all NeutronOS services",
            "accent": yellow,
            "danger": true
        },
        {
            "id": "shutdown",
            "name": "Shut Down / Power Off",
            "subtitle": "Safely stop Linux and power off the system",
            "accent": red,
            "danger": true
        }
    ])

    signal lockRequested()
    signal logoutRequested()
    signal restartShellRequested()
    signal diagnosticsRequested()
    signal recoveryRequested()
    signal rebootRequested()
    signal shutdownRequested()
    signal cancelled()
    signal closed()

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 9999

    SequentialAnimation on focusPulse {
        running: root.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.35
            to: 1.0
            duration: 1050
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.35
            duration: 1050
            easing.type: Easing.InOutSine
        }
    }

    function open(context) {
        contextData = context || null
        selectedIndex = 0
        armedActionId = ""
        visible = true
        forceActiveFocus()
    }

    function close() {
        if (!visible)
            return

        visible = false
        selectedIndex = 0
        contextData = null
        armedActionId = ""
        closed()
    }

    function moveSelection(delta) {
        var count = menuItems.length

        if (count <= 0)
            return false

        selectedIndex = (selectedIndex + delta + count) % count
        return true
    }

    function selectedItem() {
        if (selectedIndex < 0 || selectedIndex >= menuItems.length)
            selectedIndex = 0

        return menuItems[selectedIndex]
    }

    function activateSelected() {
        var item = selectedItem()

        if (!item)
            return false

        if (item.danger === true && armedActionId !== item.id) {
            armedActionId = item.id
            return true
        }

        close()

        if (item.id === "lock") { lockRequested(); return true }

        if (item.id === "logout") {
            logoutRequested()
            return true
        }

        if (item.id === "restart-shell") { restartShellRequested(); return true }
        if (item.id === "diagnostics") { diagnosticsRequested(); return true }
        if (item.id === "recovery") { recoveryRequested(); return true }
        if (item.id === "reboot") { rebootRequested(); return true }
        if (item.id === "shutdown") { shutdownRequested(); return true }

        cancelled()
        return true
    }

    function cancel() {
        if (armedActionId.length > 0) { armedActionId = ""; return true }
        close()
        cancelled()
        return true
    }

    function normalizeController(action) {
        var value = String(action || "").trim().toLowerCase()

        if (value === "dpad_left") return "left"
        if (value === "dpad_right") return "right"
        if (value === "dpad_up") return "up"
        if (value === "dpad_down") return "down"

        if (value === "x" || value === "cross" || value === "a" ||
                value === "ps_cross") return "primary"

        if (value === "o" || value === "circle" || value === "b" ||
                value === "ps_circle") return "cancel"

        if (value === "start" || value === "options" || value === "menu")
            return "system"

        if (value === "triangle" || value === "context")
            return "context"

        return value
    }

    function handleControllerPressed(action) {
        if (!visible)
            return false

        var clean = normalizeController(action)

        if (clean === "left" || clean === "up") { armedActionId=""; moveSelection(-1); return true }
        if (clean === "right" || clean === "down") { armedActionId=""; moveSelection(1); return true }

        if (clean === "primary" || clean === "system")
            return activateSelected()

        if (clean === "cancel" || clean === "context")
            return cancel()

        return true
    }

    function handleController(action) {
        return handleControllerPressed(action)
    }

    function handleControllerReleased(action) {
        return visible
    }

    function glyphFor(id) {
        if (id === "lock") return "▣"
        if (id === "logout") return "↪"
        if (id === "restart-shell") return "↻"
        if (id === "diagnostics") return "◇"
        if (id === "recovery") return "⌁"
        if (id === "reboot") return "⟳"
        if (id === "shutdown") return "⏻"
        return "•"
    }

    function shellModeText() {
        if (!contextData || contextData.shellMode === undefined)
            return "Session"

        var mode = String(contextData.shellMode)

        if (mode === "console") return "Console"
        if (mode === "app" || mode === "launchingApp") return "App active"
        if (mode === "lock") return "Lock screen"
        return "Session"
    }

    Keys.onLeftPressed: handleControllerPressed("left")
    Keys.onRightPressed: handleControllerPressed("right")
    Keys.onUpPressed: handleControllerPressed("up")
    Keys.onDownPressed: handleControllerPressed("down")
    Keys.onReturnPressed: activateSelected()
    Keys.onEnterPressed: activateSelected()
    Keys.onSpacePressed: activateSelected()
    Keys.onEscapePressed: cancel()
    Keys.onBackPressed: cancel()

    /* Translucent scrim only; the Console remains visible around the panel. */
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.56
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.pointerEnabled
        acceptedButtons: Qt.LeftButton
        onClicked: root.cancel()
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width * .82, 1180)
        height: Math.min(parent.height * .86, 880)
        radius: 34

        /* Fully opaque modal surface. */
        color: root.panelColor
        border.width: 2
        border.color: root.focusColor

        Rectangle {
            anchors.fill: parent
            anchors.margins: 9
            radius: parent.radius - 9
            color: "transparent"
            border.width: 1
            border.color: root.borderColor
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.pointerEnabled
            acceptedButtons: Qt.LeftButton
            onClicked: function(mouse) { mouse.accepted = true }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 34
            spacing: 18

            Text {
                width: parent.width
                text: "NEUTRONOS"
                color: root.cyan
                font.pixelSize: 17
                font.bold: true
                font.letterSpacing: 3.6
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: "Power & Session"
                color: root.textColor
                font.pixelSize: 39
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.shellModeText() + "  •  D-PAD choose  •  X select  •  O cancel"
                color: root.mutedColor
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 0.7
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.borderColor
            }

            Column {
                id: menuGrid
                width: parent.width
                spacing: 12

                Repeater {
                    model: root.menuItems

                    Rectangle {
                        id: optionCard

                        width: menuGrid.width
                        height: 70
                        radius: 25

                        property bool selected: root.selectedIndex === index
                        property color accent: modelData.accent

                        /* Fully opaque selectable surface. */
                        color: selected ? root.selectedCardColor : root.cardColor
                        border.width: selected ? 3 : 1
                        border.color: selected ? root.focusColor : root.borderColor

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: selected ? 7 : 4
                            radius: 3
                            color: optionCard.accent
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            width: 54
                            height: 46
                            radius: 23
                            color: "#111E31"
                            border.width: 2
                            border.color: optionCard.accent

                            Text {
                                anchors.centerIn: parent
                                text: root.glyphFor(modelData.id)
                                color: optionCard.accent
                                font.pixelSize: 23
                                font.bold: true
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 92
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                width: parent.width
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: 18
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modelData.subtitle
                                color: optionCard.selected ? "#C8F4FF" : root.mutedColor
                                font.pixelSize: 12
                                font.bold: true
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: optionCard.selected
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: parent.radius + 5
                            color: "transparent"
                            border.width: 2
                            border.color: root.focusColor
                            opacity: 0.50 + root.focusPulse * 0.35
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.pointerEnabled
                            hoverEnabled: root.pointerEnabled
                            acceptedButtons: Qt.LeftButton

                            onEntered: root.selectedIndex = index
                            onClicked: {
                                root.selectedIndex = index
                                root.activateSelected()
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 56
                radius: 20
                color: "#0A1729"
                border.width: 1
                border.color: root.borderColor

                Text {
                    anchors.centerIn: parent
                            text: root.armedActionId === "recovery"
                                  ? "CONFIRM: NEXT BOOT IS A LOCAL TERMINAL; A LATER REBOOT RETURNS TO NORMAL  •  X CONFIRM  •  O CANCEL"
                                  : root.armedActionId.length>0 ? "X AGAIN TO CONFIRM  •  O CANCELS CONFIRMATION" : "D-PAD NAVIGATE  •  X SELECT  •  O CLOSE"
                    color: root.mutedColor
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible)
            forceActiveFocus()
        else
            selectedIndex = 0
    }
}
