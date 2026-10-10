import QtQuick
import QtQuick.Controls

Item {
    id: root
    visible: opened
    enabled: opened
    z: 50000

    property bool opened: false
    property var incident: ({})
    property var securityBackend: null
    property int selectedAction: 0
    property int armedAction: -1

    signal openSecurityRequested(var incident)
    signal auditRequested(var incident)
    signal lockdownRequested(var incident)
    signal approveRequested(var incident)

    signal reviewRequested(var incident)
    signal defensiveActionsRequested(var incident)

    function clean(value) {
        return String(value === undefined || value === null ? "" : value).trim()
    }

    function basename(path) {
        var value = clean(path).replace(/\\/g, "/")
        var parts = value.split("/")
        return parts.length ? parts[parts.length - 1] : value
    }

    function severityNumber() {
        var raw = incident ? incident.severity : 0
        var number = Number(raw)
        if (!isNaN(number) && number > 0)
            return Math.round(number)
        var text = clean(raw).toLowerCase()
        if (text.indexOf("critical") >= 0) return 5
        if (text.indexOf("high") >= 0 || text.indexOf("severe") >= 0) return 4
        if (text.indexOf("warning") >= 0 || text.indexOf("medium") >= 0) return 3
        return 4
    }

    function severityLabel() {
        var n = severityNumber()
        if (n >= 5) return "CRITICAL • LEVEL 5"
        if (n === 4) return "HIGH • LEVEL 4"
        if (n === 3) return "ELEVATED • LEVEL 3"
        return "SECURITY EVENT • LEVEL " + n
    }

    function eventBlob() {
        return (
            clean(incident && incident.title) + " " +
            clean(incident && incident.type) + " " +
            clean(incident && incident.eventType) + " " +
            clean(incident && incident.message) + " " +
            clean(incident && incident.description) + " " +
            clean(incident && incident.evidence) + " " +
            clean(incident && incident.reason) + " " +
            clean(incident && incident.attackPath)
        ).toLowerCase()
    }

    function affectedComponents() {
        var values = []

        function add(value) {
            if (value === undefined || value === null)
                return
            if (Array.isArray(value)) {
                for (var i = 0; i < value.length; ++i)
                    add(value[i])
                return
            }
            if (typeof value === "object") {
                add(value.name)
                add(value.path)
                add(value.file)
                add(value.component)
                add(value.app)
                return
            }

            var text = clean(value)
            if (!text.length)
                return
            var display = text.indexOf("/") >= 0 ? basename(text) : text
            if (values.indexOf(display) < 0)
                values.push(display)
        }

        if (incident) {
            add(incident.affectedComponents)
            add(incident.components)
            add(incident.component)
            add(incident.file)
            add(incident.filePath)
            add(incident.path)
            add(incident.application)
            add(incident.app)
            add(incident.source)
        }

        return values.length ? values.join(", ") : "Security Core"
    }

    function readableAttackPath() {
        var supplied = clean(incident && incident.attackPath)
        if (supplied.length && supplied.indexOf("/") < 0 && supplied.length < 220)
            return supplied

        var blob = eventBlob()
        var component = affectedComponents()

        if (blob.indexOf("hash") >= 0 || blob.indexOf("integrity") >= 0)
            return component + " changed → integrity verification failed → security event raised"
        if (blob.indexOf("password") >= 0 || blob.indexOf("login") >= 0 ||
            blob.indexOf("authentication") >= 0 || blob.indexOf("auth") >= 0)
            return "Login attempt → authentication rejected → security event recorded"
        if (blob.indexOf("malware") >= 0 || blob.indexOf("virus") >= 0 ||
            blob.indexOf("trojan") >= 0 || blob.indexOf("quarantine") >= 0)
            return component + " scanned → threat indicator matched → protection response triggered"
        if (blob.indexOf("ssh") >= 0 || blob.indexOf("port") >= 0 ||
            blob.indexOf("firewall") >= 0 || blob.indexOf("source") >= 0 ||
            blob.indexOf("network") >= 0 || blob.indexOf("intrusion") >= 0)
            return "Remote activity → network/security policy check → suspicious activity rejected"
        if (blob.indexOf("peripheral") >= 0 || blob.indexOf("usb") >= 0 ||
            blob.indexOf("device") >= 0)
            return "Peripheral connected → trust policy checked → untrusted activity detected"

        return "Security telemetry → policy verification → high-severity event detected"
    }

    function evidenceText() {
        var value = clean(incident && incident.evidence)
        if (!value.length) value = clean(incident && incident.description)
        if (!value.length) value = clean(incident && incident.message)
        if (!value.length) value = clean(incident && incident.reason)
        if (value.length)
            return value

        var blob = eventBlob()
        if (blob.indexOf("hash") >= 0)
            return affectedComponents() + " no longer matches its approved integrity hash."
        if (blob.indexOf("password") >= 0 || blob.indexOf("authentication") >= 0)
            return "An authentication attempt failed and was recorded by the security service."

        return "The security service raised this event from authoritative runtime telemetry."
    }

    function similarEventCount() {
        if (!securityBackend || !securityBackend.events)
            return 1

        var source = securityBackend.events || []
        var currentTitle = clean(incident && incident.title).toLowerCase()
        var currentType = clean(incident && (incident.eventType || incident.type)).toLowerCase()
        var currentComponent = affectedComponents().toLowerCase()
        var count = 0

        for (var i = 0; i < source.length; ++i) {
            var event = source[i] || ({})
            var title = clean(event.title).toLowerCase()
            var type = clean(event.eventType || event.type).toLowerCase()
            var component = clean(
                event.component || event.file || event.filePath ||
                event.application || event.source
            ).toLowerCase()

            var same =
                (currentType.length && type === currentType) ||
                (currentTitle.length && title === currentTitle) ||
                (currentComponent.length && component.indexOf(currentComponent) >= 0)

            if (same)
                count++
        }

        return Math.max(1, count)
    }

    function suggestedAction() {
        var blob = eventBlob()
        var repeated = similarEventCount()
        var component = affectedComponents()

        if (blob.indexOf("malware") >= 0 || blob.indexOf("virus") >= 0 ||
            blob.indexOf("trojan") >= 0)
            return "Lock down the system, open Security, quarantine the affected item and run a Security Audit. Do not approve unless you independently confirm a false positive."

        if (blob.indexOf("hash") >= 0 || blob.indexOf("integrity") >= 0)
            return repeated >= 3
                ? "This integrity change has appeared repeatedly. If you did not intentionally modify " + component + ", use Lockdown and run a Security Audit. If the change is expected and verified, Approve will acknowledge it and establish the new baseline."
                : "Verify that the change to " + component + " was intentional. If expected, Approve will acknowledge the event and establish the new integrity baseline. If not expected, use Lockdown and run a Security Audit."

        if (blob.indexOf("password") >= 0 || blob.indexOf("login") >= 0 ||
            blob.indexOf("authentication") >= 0 || blob.indexOf("auth") >= 0)
            return repeated >= 3
                ? "Multiple authentication failures are recorded. If you do not recognize them, use Lockdown, review the source/account in Security and run a Security Audit. Do not approve repeated unknown login attempts."
                : "Confirm whether this login attempt was yours. If it was not, open Security and review the source. Escalate to Lockdown if attempts continue."

        if (blob.indexOf("ssh") >= 0 || blob.indexOf("port") >= 0 ||
            blob.indexOf("firewall") >= 0 || blob.indexOf("source") >= 0 ||
            blob.indexOf("network") >= 0 || blob.indexOf("intrusion") >= 0)
            return repeated >= 3
                ? "Repeated suspicious network activity is present. Use Lockdown, inspect the source and listening service in Security, then run a Security Audit before returning to normal operation."
                : "Open Security and verify the source, port and affected service. Use Lockdown if the activity is unrecognized or repeats, then run a Security Audit."

        if (blob.indexOf("peripheral") >= 0 || blob.indexOf("usb") >= 0 ||
            blob.indexOf("device") >= 0)
            return "Verify the connected device before trusting it. If it is unknown, use Lockdown and block it from Security. Approve only after confirming the hardware is expected."

        if (repeated >= 3)
            return "This high-severity event has repeated " + repeated + " times. Use Lockdown and run a Security Audit before approving or returning to a lower security posture."

        return "Open Security and review the evidence. Run a Security Audit if the event is not immediately explained. Use Lockdown for unrecognized or continuing activity."
    }

    function openIncident(value) {
        incident = value || ({})
        selectedAction = 0
        armedAction = -1
        armTimer.stop()
        opened = true
    }

    function closeModal() {
        armedAction = -1
        armTimer.stop()
        opened = false
    }

    function moveSelection(delta) {
        selectedAction = (selectedAction + delta + 4) % 4
        armedAction = -1
        armTimer.stop()
    }

    function executeSelected() {
        if (selectedAction === 0) {
            openSecurityRequested(incident)
            closeModal()
            return
        }
        if (selectedAction === 1) {
            auditRequested(incident)
            closeModal()
            return
        }

        if (armedAction !== selectedAction) {
            armedAction = selectedAction
            armTimer.restart()
            return
        }

        if (selectedAction === 2)
            lockdownRequested(incident)
        else
            approveRequested(incident)

        closeModal()
    }

    function handleControllerPressed(button) {
        if (!opened)
            return false

        var b = String(button || "").toLowerCase()
        if (b === "left" || b === "dpad-left") { moveSelection(-1); return true }
        if (b === "right" || b === "dpad-right") { moveSelection(1); return true }
        if (b === "primary" || b === "x" || b === "cross") { executeSelected(); return true }
        if (b === "cancel" || b === "circle" || b === "o" || b === "back") { closeModal(); return true }
        return true
    }

    Timer {
        id: armTimer
        interval: 4500
        repeat: false
        onTriggered: root.armedAction = -1
    }

    Rectangle {
        anchors.fill: parent
        color: "#D6000207"
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.72, 1360)
        height: Math.min(parent.height * 0.78, 820)
        radius: 12
        color: "#F0060B14"
        border.width: 2
        border.color: "#FF314B"

        Column {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 14

            Text {
                width: parent.width
                text: "!  HIGH-SEVERITY SECURITY EVENT DETECTED  !"
                color: "#FF314B"
                font.pixelSize: 31
                font.bold: true
                font.letterSpacing: 1.2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.severityLabel()
                color: root.severityNumber() >= 5 ? "#FF314B" : "#FF875F"
                font.pixelSize: 19
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle { width: parent.width; height: 1; color: "#5630404D" }

            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 22
                rowSpacing: 12

                Text { width: parent.width * 0.23; text: "DETECTED ATTACK PATH"; color: "#98A9BD"; font.pixelSize: 15; font.bold: true }
                Text { width: parent.width * 0.73; text: root.readableAttackPath(); color: "#F2F6FB"; font.pixelSize: 17; font.bold: true; wrapMode: Text.WordWrap }

                Text { width: parent.width * 0.23; text: "AFFECTED COMPONENTS"; color: "#98A9BD"; font.pixelSize: 15; font.bold: true }
                Text { width: parent.width * 0.73; text: root.affectedComponents(); color: "#66D7FF"; font.pixelSize: 17; font.bold: true; wrapMode: Text.WordWrap }

                Text { width: parent.width * 0.23; text: "EVIDENCE"; color: "#98A9BD"; font.pixelSize: 15; font.bold: true }
                Text { width: parent.width * 0.73; text: root.evidenceText(); color: "#E2E8F0"; font.pixelSize: 16; wrapMode: Text.WordWrap }

                Text { width: parent.width * 0.23; text: "EVENT HISTORY"; color: "#98A9BD"; font.pixelSize: 15; font.bold: true }
                Text {
                    width: parent.width * 0.73
                    text: root.similarEventCount() > 1
                          ? String(root.similarEventCount()) + " similar events are currently recorded."
                          : "No repeated matching event is currently recorded."
                    color: root.similarEventCount() >= 3 ? "#FF875F" : "#B9C5D3"
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#5630404D" }

            Rectangle {
                width: parent.width
                height: 118
                radius: 7
                color: "#A00A111C"
                border.width: 1
                border.color: "#553A556B"

                Column {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 7

                    Text { text: "SUGGESTED ACTION"; color: "#FFCE63"; font.pixelSize: 15; font.bold: true }
                    Text {
                        width: parent.width
                        text: root.suggestedAction()
                        color: "#F0F4F8"
                        font.pixelSize: 16
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                }
            }

            Item { width: 1; height: Math.max(2, parent.height - y - 92) }

            Row {
                width: parent.width
                height: 70
                spacing: 12

                Repeater {
                    model: [
                        {label:"OPEN SECURITY", tone:"#168EFF", border:"#49B5FF"},
                        {label:"RUN SECURITY AUDIT", tone:"#156D85", border:"#40D6FF"},
                        {label:"LOCKDOWN", tone:"#922336", border:"#FF4056"},
                        {label:"APPROVE", tone:"#126438", border:"#43E89A"}
                    ]

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: (parent.width - parent.spacing * 3) / 4
                        height: parent.height
                        radius: 7
                        color: root.selectedAction === index
                               ? Qt.lighter(String(modelData.tone), 1.32)
                               : String(modelData.tone)
                        border.width: root.selectedAction === index ? 3 : 1
                        border.color: String(modelData.border)

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 16
                            spacing: 3

                            Text {
                                width: parent.width
                                text: String(modelData.label)
                                color: "#FFFFFF"
                                font.pixelSize: 16
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                visible: (index === 2 || index === 3) &&
                                         root.armedAction === index
                                text: "ARMED • PRESS X AGAIN"
                                color: index === 2 ? "#FFD0D6" : "#C8FFDD"
                                font.pixelSize: 11
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedAction = index
                                root.executeSelected()
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "LEFT / RIGHT  SELECT     X  ACTIVATE     O  CLOSE     •     LOCKDOWN AND APPROVE REQUIRE TWO X PRESSES"
                color: "#77879A"
                font.pixelSize: 12
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
