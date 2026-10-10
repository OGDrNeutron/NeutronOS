import QtQuick 2.15
import QtQuick.Controls 2.15
import "../components" as Shared

Item {
    id: modal
    anchors.fill: parent
    readonly property var backend: typeof privilegeManager !== "undefined" ? privilegeManager : null
    visible: backend !== null && backend.pending
    enabled: visible
    focus: visible
    z: 100000

    property string password: ""
    property bool keyboardVisible: false

    function appendPasswordCharacter(value) {
        if (value === "SPACE")
            password += " "
        else if (value === "CLEAR")
            password = ""
        else if (value !== "ENTER" && value !== "CLOSE" &&
                 value !== "BACK" && value !== "CAPS" &&
                 value !== "SHIFT" && value !== "SPEC")
            password += value
    }

    function submit() {
        if (!backend || backend.running)
            return
        if (password.length === 0) {
            keyboardVisible = true
            passwordKeyboard.visibleMode = true
            passwordKeyboard.active = true
            passwordKeyboard.forceActiveFocus()
            return
        }
        backend.proceed(password)
        password = ""
        keyboardVisible = false
        passwordKeyboard.visibleMode = false
        passwordKeyboard.active = false
        modal.forceActiveFocus()
    }

    function closeModal() {
        password = ""
        keyboardVisible = false
        passwordKeyboard.visibleMode = false
        passwordKeyboard.active = false
        if (backend)
            backend.cancel()
    }

    Rectangle {
        anchors.fill: parent
        color: "#C0000208"
    }

    Rectangle {
        width: Math.min(parent.width * 0.62, 920)
        height: modal.backend && modal.backend.developerMode ? 680 : 600
        anchors.centerIn: parent
        radius: 30
        color: "#F20A1020"
        border.width: 2
        border.color: modal.backend && modal.backend.developerMode ? "#9B72FF" : "#42D7FF"

        Column {
            anchors.fill: parent
            anchors.margins: 40
            spacing: 20

            Text {
                width: parent.width
                text: "RUN AS SUDO"
                color: "#FFFFFF"
                font.pixelSize: 40
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: modal.backend ? modal.backend.title : ""
                color: "#D9F7FF"
                font.pixelSize: 27
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: modal.backend ? modal.backend.description : ""
                color: "#AFC5D8"
                font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 60
                radius: 16
                color: "#101A2B"
                border.width: 1
                border.color: "#37506B"

                Text {
                    anchors.fill: parent
                    anchors.margins: 14
                    text: modal.backend ? modal.backend.command : ""
                    color: "#8199AD"
                    font.pixelSize: 16
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                visible: modal.backend && modal.backend.developerMode
                width: parent.width
                height: 62
                radius: 16
                color: "#241947"
                border.width: 1
                border.color: "#9B72FF"

                Text {
                    anchors.centerIn: parent
                    text: "DEVELOPER MODE — LOCAL PASSWORD STILL REQUIRED"
                    color: "#DCCFFF"
                    font.pixelSize: 18
                    font.bold: true
                }
            }

            Rectangle {
                visible: true
                width: parent.width
                height: 76
                radius: 18
                color: "#101A2B"
                border.width: keyboardVisible ? 2 : 1
                border.color: keyboardVisible ? "#42D7FF" : "#37506B"

                Text {
                    anchors.fill: parent
                    anchors.margins: 18
                    text: password.length > 0 ? "•".repeat(password.length)
                                              : "Press X to enter local password"
                    color: password.length > 0 ? "#FFFFFF" : "#7890A5"
                    font.pixelSize: 23
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Text {
                visible: modal.backend && modal.backend.lastError.length > 0
                width: parent.width
                text: modal.backend ? modal.backend.lastError : ""
                color: "#FF6A7A"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24

                Button {
                    width: 220
                    height: 64
                    text: "CANCEL"
                    onClicked: modal.closeModal()
                }

                Button {
                    width: 280
                    height: 64
                    text: modal.backend && modal.backend.running ? "RUNNING…" : "PROCEED"
                    enabled: modal.backend && !modal.backend.running &&
                             modal.password.length > 0
                    onClicked: modal.submit()
                }
            }
        }
    }

    Shared.VirtualKeyboard {
        id: passwordKeyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.66
        z: modal.z + 10

        visibleMode: modal.visible && modal.keyboardVisible
        visible: visibleMode
        enabled: visibleMode
        active: visibleMode
        largeMode: true
        title: "Local Password"
        cancelBehavior: "close"

        onKeyPressed: function(value) {
            modal.appendPasswordCharacter(value)
        }

        onBackspacePressed: {
            if (modal.password.length > 0)
                modal.password = modal.password.slice(0, -1)
        }

        onEnterPressed: {
            modal.submit()
        }

        onClosePressed: {
            modal.keyboardVisible = false
            passwordKeyboard.visibleMode = false
            passwordKeyboard.active = false
            modal.forceActiveFocus()
        }
    }

    Keys.onPressed: function(event) {
        if (!modal.visible || modal.keyboardVisible)
            return

        if (event.key === Qt.Key_Escape ||
            event.key === Qt.Key_B ||
            event.key === Qt.Key_Back) {
            modal.closeModal()
            event.accepted = true
        } else if (event.key === Qt.Key_X || event.key === Qt.Key_F2) {
            modal.keyboardVisible = true
            passwordKeyboard.visibleMode = true
            passwordKeyboard.active = true
            passwordKeyboard.forceActiveFocus()
            event.accepted = true
        } else if (event.key === Qt.Key_Return ||
                   event.key === Qt.Key_Enter ||
                   event.key === Qt.Key_A) {
            modal.submit()
            event.accepted = true
        }
    }

    Connections {
        target: modal.backend

        function onChanged() {
            if (modal.backend && modal.backend.pending) {
                modal.password = ""
                modal.keyboardVisible = false
                passwordKeyboard.visibleMode = false
                passwordKeyboard.active = false
                modal.forceActiveFocus()
            } else {
                modal.password = ""
                modal.keyboardVisible = false
                passwordKeyboard.visibleMode = false
                passwordKeyboard.active = false
            }
        }
    }
}
