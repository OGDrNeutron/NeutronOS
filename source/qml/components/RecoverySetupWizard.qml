import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: wizard
    anchors.fill: parent
    focus: true

    property var backend: null
    property bool open: false
    property int page: 0 // 0 method, 1 code, 2 usb
    property int methodIndex: 0
    property int usbIndex: 0
    property bool enrollmentSubmitted: false
    property string operationMessage: ""
    property bool operationError: false

    signal completed(bool skipped)

    readonly property var usbCandidates: backend && backend.recoveryUsbCandidates ? backend.recoveryUsbCandidates : []
    readonly property color bg: "#F2020710"
    readonly property color panel: "#F20A1728"
    readonly property color cyan: "#6BEAFF"
    readonly property color green: "#37E89B"
    readonly property color yellow: "#FFD166"
    readonly property color red: "#FF4B5F"
    readonly property color textMain: "#F4FBFF"
    readonly property color textMuted: "#9CB9D1"

    function normalizeAction(action) {
        var value = String(action || "").toLowerCase().replace(/-/g, "_")
        if (value === "x" || value === "cross" || value === "primary") return "primary"
        if (value === "o" || value === "circle" || value === "cancel" || value === "back") return "cancel"
        if (value === "triangle" || value === "context") return "context"
        if (value === "square" || value === "secondary") return "secondary"
        if (value === "dpad_up" || value === "leftstick_up") return "up"
        if (value === "dpad_down" || value === "leftstick_down") return "down"
        if (value === "dpad_left" || value === "leftstick_left") return "left"
        if (value === "dpad_right" || value === "leftstick_right") return "right"
        return value
    }

    function resetWizard() {
        page = 0
        methodIndex = 0
        usbIndex = 0
        enrollmentSubmitted = false
        operationMessage = ""
        operationError = false
    }

    onOpenChanged: {
        if (open)
            resetWizard()
    }

    function finishEnrollment(skipped) {
        enrollmentSubmitted = false
        open = false
        completed(skipped === true)
    }

    function handleControllerPressed(action) {
        if (!open) return false
        var value = normalizeAction(action)

        if (page === 0) {
            if (value === "left" || value === "up")
                methodIndex = Math.max(0, methodIndex - 1)
            else if (value === "right" || value === "down")
                methodIndex = Math.min(2, methodIndex + 1)
            else if (value === "primary") {
                operationMessage = ""
                operationError = false
                if (methodIndex === 0) {
                    page = 1
                } else if (methodIndex === 1) {
                    page = 2
                    if (backend) backend.refresh()
                } else if (backend && typeof backend.deferRecoverySetup === "function") {
                    if (backend.deferRecoverySetup())
                        finishEnrollment(true)
                }
            }
            return true
        }

        if (page === 1) {
            if (value === "cancel" && !enrollmentSubmitted) {
                page = 0
            } else if (value === "primary" && backend && !backend.generatedRecoveryCode) {
                backend.generateRecoveryCode()
            } else if (value === "secondary" && backend && backend.generatedRecoveryCode) {
                enrollmentSubmitted = true
                if (typeof backend.confirmGeneratedRecoveryCode === "function" &&
                        backend.confirmGeneratedRecoveryCode()) {
                    finishEnrollment(false)
                } else {
                    enrollmentSubmitted = false
                }
            }
            return true
        }

        if (page === 2) {
            if (value === "cancel" && !enrollmentSubmitted) {
                page = 0
            } else if (value === "up") {
                usbIndex = Math.max(0, usbIndex - 1)
            } else if (value === "down") {
                usbIndex = Math.min(Math.max(0, usbCandidates.length - 1), usbIndex + 1)
            } else if (value === "context" && backend) {
                backend.refresh()
            } else if (value === "primary" && backend && usbCandidates.length > 0) {
                var candidate = usbCandidates[Math.max(0, Math.min(usbIndex, usbCandidates.length - 1))] || ({})
                enrollmentSubmitted = true
                if (backend.enrollUsbRecovery(String(candidate.path || candidate.id || "")))
                    finishEnrollment(false)
                else
                    enrollmentSubmitted = false
            }
            return true
        }

        return true
    }

    Connections {
        target: backend
        ignoreUnknownSignals: true

        function onOperationFinished(success, message) {
            if (!wizard.open)
                return
            wizard.operationMessage = String(message || "")
            wizard.operationError = success !== true
        }
    }

    visible: open
    z: 950

    Rectangle { anchors.fill: parent; color: bg }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1280)
        height: Math.min(parent.height - 100, 820)
        radius: 34
        color: panel
        border.width: 3
        border.color: page === 1 ? green : (methodIndex === 2 && page === 0 ? yellow : cyan)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 42
            spacing: 20

            Text {
                text: "NeutronOS Physical Recovery Key"
                color: textMain
                font.pixelSize: 34
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                text: "Create an offline recovery method now, or skip temporarily. Skipping keeps NeutronOS in minimum observe-only security until a recovery code or USB key is generated."
                color: textMuted
                font.pixelSize: 16
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                visible: page === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                Repeater {
                    model: [
                        {title: "Recovery Code", body: "Generate a long one-time code. Save it outside the Pi. NeutronOS stores only a salted verifier.", accent: green},
                        {title: "USB Recovery Key", body: "Bind a signed recovery file to one exact removable storage device.", accent: cyan},
                        {title: "Skip For Now", body: "Continue to Console with Learning Mode on, enforcement off, active response off, and DEFCON locked at 5 until recovery is enrolled.", accent: yellow}
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 24
                        color: methodIndex === index ? "#173C54" : "#0B2034"
                        border.width: methodIndex === index ? 4 : 1
                        border.color: methodIndex === index ? modelData.accent : "#24506C"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 24
                            spacing: 16

                            Text {
                                width: parent.width
                                text: modelData.title
                                color: modelData.accent
                                font.pixelSize: 24
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                text: modelData.body
                                color: textMuted
                                font.pixelSize: 15
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                visible: page === 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                Text {
                    text: backend && backend.generatedRecoveryCode ? "Save this code now" : "Generate your recovery code"
                    color: green
                    font.pixelSize: 25
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    radius: 24
                    color: "#06111F"
                    border.width: 2
                    border.color: green

                    Text {
                        anchors.fill: parent
                        anchors.margins: 24
                        text: backend && backend.generatedRecoveryCode ? backend.generatedRecoveryCode : "Press X to generate"
                        color: textMain
                        font.family: "monospace"
                        font.pixelSize: backend && backend.generatedRecoveryCode ? 22 : 18
                        font.bold: true
                        wrapMode: Text.WrapAnywhere
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: backend && backend.generatedRecoveryCode
                          ? "The code will stay visible until you press Square to confirm that it has been saved."
                          : "The original code cannot be revealed later. Generate it only when you are ready to save it offline."
                    color: yellow
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                visible: page === 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Text {
                    text: "Choose the exact USB storage device"
                    color: cyan
                    font.pixelSize: 25
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                ListView {
                    id: usbList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 10
                    model: usbCandidates
                    currentIndex: usbIndex

                    delegate: Rectangle {
                        width: usbList.width
                        height: 92
                        radius: 18
                        color: usbIndex === index ? "#173C54" : "#0B2034"
                        border.width: usbIndex === index ? 3 : 1
                        border.color: usbIndex === index ? cyan : "#24506C"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6
                            Text { text: String(modelData.label || modelData.name || "USB Storage"); color: textMain; font.pixelSize: 18; font.bold: true }
                            Text { width: parent.width; text: String(modelData.path || "") + " · " + String(modelData.uuid || modelData.partuuid || "No UUID"); color: textMuted; font.pixelSize: 12; elide: Text.ElideMiddle }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: usbCandidates.length === 0
                        text: "Insert and mount a removable USB drive, then press Triangle to refresh."
                        color: yellow
                        font.pixelSize: 15
                        wrapMode: Text.WordWrap
                        width: parent.width - 80
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Text {
                visible: operationMessage.length > 0
                Layout.fillWidth: true
                text: operationMessage
                color: operationError ? red : green
                font.pixelSize: 14
                font.bold: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: page === 0 ? "← →  Choose" : "O  Back"; color: textMuted; font.pixelSize: 14 }
                Item { Layout.fillWidth: true }
                Text {
                    text: page === 0
                          ? "X  Select"
                          : page === 1
                            ? (backend && backend.generatedRecoveryCode ? "□  I saved it — Continue" : "X  Generate")
                            : "X  Enroll USB   △ Refresh"
                    color: page === 1 && backend && backend.generatedRecoveryCode ? green : (page === 0 && methodIndex === 2 ? yellow : cyan)
                    font.pixelSize: 14
                    font.bold: true
                }
            }
        }
    }
}
