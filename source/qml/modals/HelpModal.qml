import QtQuick 2.15
import QtQuick.Controls 2.15
import "../common/ControllerFeatureRegistry.js" as ControllerFeatures

Rectangle {
    id: root

    property int selectedSection: 0
    property int focusPane: 0 // 0 category rail, 1 article
    property int articleScrollStep: 92

    signal closed()
    signal loginInstructionsRequested()

    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 24000
    color: "#F0030710"
    Keys.enabled: visible

    readonly property var sections: [
        {
            title: "WELCOME",
            subtitle: "What NeutronOS is",
            body: "NeutronOS is a controller-first Linux console shell. The main flow is Login → Console → AppHost → Console. The Console remains the home for system status, applications, Quick Actions, settings, security, and service controls.\n\nThe interface is designed so every important action can be completed without a mouse. Blue indicates normal focus, red indicates an armed or destructive action, green indicates success or charging, and dim elements are inactive or unavailable.\n\nUse this Help Center as the complete on-device guide. Choose a section on the left with the D-pad and press X to open its article."
        },
        {
            title: "CONTROLLER",
            subtitle: "Global button map",
            body: ControllerFeatures.dashboardHelpText() + "\n\nNOTIFICATION CENTER\nUse D-pad to select, X to open or mark read, Triangle for details/actions, Square for group actions, and O to close.\n\nGLOBAL SEARCH\nOpen the displayed global shortcut, type with the virtual keyboard, use D-pad to select, X to execute, Triangle for details, and O to close."
        },
        {
            title: "LOGIN & SECURITY",
            subtitle: "Unlocking the system",
            body: "The Login screen displays the selected user, saved profile appearance, controller identity, security state, and controller battery.\n\nNORMAL UNLOCK\nPress X to arm the user card, then enter the saved controller combo. The rolling input window accepts the valid sequence without a separate submit button. O cancels and clears the current attempt.\n\nFAILED ATTEMPTS\nThe 15-input rolling window verifies after 220 ms of quiet. Lockouts are 5 seconds, 30 seconds, 5 minutes, 15 minutes, then one hour for later failures.\n\nPress Triangle on this article to reopen the complete Controller Login instructions.\n\nLOGIN EASTER EGG\nWhile the user card is armed, pressing the PS/Home button five times opens the Gemini Mercury Edition panel. It does not affect authentication."
        },
        {
            title: "CONSOLE",
            subtitle: "Home-screen navigation",
            body: "The Console has four controller sections. Move vertically to change sections and horizontally to move within the active section.\n\n1. SYSTEM OVERVIEW\nCPU, RAM, temperature, storage, network, controller/uptime, clock/date, user profile, and active-app status.\n\n2. APP CAROUSEL\nFavorite applications discovered by the backend. The center card is selected. X launches it. Triangle arms App Controls.\n\n3. QUICK ACTIONS\nA persistent dock of system commands, apps, services, and scripts. X runs the selected shortcut. Triangle opens customization.\n\n4. HIDDEN APP DOCK\nProtected additional apps and advanced controls. It appears only when unlocked.\n\nThe footer changes to show the controls available in the current section or modal."
        },
        {
            title: "SYSTEM OVERVIEW",
            subtitle: "Status cards and details",
            body: "Each System Overview card shows live summary data. A luminous outline, lift, glow and corner accent make controller focus unmistakable. Triangle opens the premium details monitor and Square opens widget actions.\n\nTAB SELECTOR\nPS/Home opens or closes the selector from every Dashboard surface, including Legacy and custom tabs. While open it is modal: Up/Down changes only the highlighted tab, X activates it, and Circle or PS/Home closes it. Notification Center and the page underneath do not receive those presses.\n\nSYSTEM OVERVIEW MANAGER\nHold Start on Dashboard. Enable or disable widgets, resize Small / Medium / Large, move items, reset placement, or create, rename and delete per-user custom tabs. Temperature remains fixed-size.\n\nCUSTOM TABS\nCustom pages reuse the Dashboard layout and focus system. From Running Apps, focus a runtime, press Square, choose Make App a Tab, and confirm. The existing runtime is reused rather than launched again.\n\nLEGACY\nWhen enabled in Settings > Display, Legacy appears after Apps in the PS/Home selector; hiding it preserves its state. PS/Home always opens the modal selector above Legacy so Up can reach Apps, Storage, Security, and System Overview.\n\nAPPS\nThe Apps tab prefers each app's poster artwork and falls back to its icon or the NeutronOS placeholder. Its dynamic glass name plate identifies the app without modifying the artwork.\n\nCPU / RAM\nDetailed graphical monitor panels show live history, per-core data and an aligned process table. Network, Storage, Temperature and Security use their native detailed surfaces."
        },
        {
            title: "APPLICATIONS",
            subtitle: "Launching and controlling apps",
            body: "The carousel is populated by AppManager rather than a fixed QML list. NeutronOS can discover native QML apps, web apps, command apps, desktop entries, services, and configured scripts.\n\nX\nLaunches the selected app. Service-backed apps first request their required Docker container or systemd service, wait for readiness, and then open AppHost.\n\nTRIANGLE\nFirst press arms the selected app red. A second press opens App Controls.\n\nAPP CONTROLS\nStart, Stop, Restart, and Kill are shown according to backend capability. Destructive actions require confirmation. Critical system processes are protected.\n\nAPPHOST\nApps run full-screen. Console interaction is suspended until the app exits. O is the normal back/exit control unless the app displays its own confirmation modal."
        },
        {
            title: "QUICK ACTIONS",
            subtitle: "Persistent shortcut dock",
            body: "Quick Actions can contain from one shortcut to an unlimited number. The dock grows while it fits the display and becomes a continuously scrolling horizontal list when it is wider than the screen.\n\nX\nRuns or opens the highlighted shortcut. Destructive actions open an armed confirmation panel.\n\nTRIANGLE\nArms the dock red and opens customization.\n\nCUSTOMIZATION\nX replaces the selected slot. Square adds the highlighted catalogue action or removes a dock slot. L1/R1 reorders the selected slot. Triangle restores defaults. O returns or closes.\n\nACTION SOURCES\nSystem commands, installed apps, services, Docker containers, and approved scripts. Services and scripts reuse their shared theme icons. Apps reuse their normal icons.\n\nThe selected highlight must follow the action that will actually run."
        },
        {
            title: "NETWORK",
            subtitle: "Wi-Fi, traffic, and testing",
            body: "The Network panel uses the native NetworkManager backend.\n\nOVERVIEW\nCurrent SSID, signal, security, frequency band, IP address, gateway, DNS, interface, Tailscale address, live receive/transmit activity, and benchmark results.\n\nAVAILABLE NETWORKS\nScan and connect to open or secured Wi-Fi. Hidden networks can be entered with the on-screen virtual keyboard.\n\nSAVED NETWORKS\nReconnect or forget a saved connection. Forget is an armed destructive action.\n\nSPEED TEST\nRuns an asynchronous lightweight benchmark and reports download, upload, latency, status, completion time, and cached result age.\n\nDIAGNOSTICS\nChecks NetworkManager, interface, route, gateway, Internet reachability, and DNS. Repair can renew the connection. Restart NetworkManager requires confirmation."
        },
        {
            title: "USER PROFILE",
            subtitle: "Identity and appearance",
            body: "User Settings is organized into controller-friendly categories with a left rail and scrollable right page.\n\nPROFILE\nChange display name and tagline using the shared virtual keyboard.\n\nICON\nChoose an avatar from the theme user directory, refresh the icon library, and select the frame shape.\n\nNAME COLOR\nChoose broad presets or adjust full hue, saturation, and lightness.\n\nAPPEARANCE\nSet the profile accent, frame styling, and glow strength.\n\nACCOUNT\nLock the Console, log out with confirmation, reload the persistent profile, or reset customization.\n\nSaved profile colors and icons are shared by the Login screen and System Overview user card."
        },
        {
            title: "CLOCK & DATE",
            subtitle: "Time presentation",
            body: "Clock & Date settings apply immediately and persist across restarts.\n\nTIME\nChoose 12-hour or 24-hour format, seconds visibility, and AM/PM case.\n\nDATE\nShow or hide the date and weekday. Choose long, medium, US numeric, international numeric, or ISO formatting.\n\nREGION\nSelect the timezone and choose whether its abbreviation is displayed.\n\nAPPEARANCE\nChoose standard, compact, or wide presentation; adjust size; and set separate clock, date, and timezone colors.\n\nPREVIEW\nShows the result before leaving the panel. Reset restores NeutronOS defaults."
        },
        {
            title: "CONTROLLER SETTINGS",
            subtitle: "Identity, battery, and feedback",
            body: "The Controller panel identifies the connected controller family and model, displays battery bars and percentage, and exposes supported controller features.\n\nBATTERY\nNormal bars show remaining charge. Critical battery pulses red. Charging state uses green bars and a lightning indicator.\n\nCOLOR / LIGHTBAR\nSupported controllers can use a persistent custom color. The full color interface provides broad range selection and exact hexadecimal entry through the virtual keyboard.\n\nHAPTICS\nFeedback confirms navigation, arming, success, failure, and selected system events.\n\nCONTROLLER OFF\nAvailable as a Quick Action. It cleanly disconnects the active controller without powering down the Pi."
        },
        {
            title: "SCREENSAVER",
            subtitle: "Motion and wake behavior",
            body: "The screensaver continuously pans and zooms across each image, then crossfades into the preloaded next image. It uses GPU-friendly transforms rather than continuous Canvas drawing.\n\nSTARTING\nLaunch it from Quick Actions or allow the configured inactivity deadline to expire.\n\nWAKING\nAny approved controller, keyboard, mouse, or web-controller input immediately closes the screensaver. The wake input is consumed so it cannot also move or activate the hidden Console.\n\nRETURN STATE\nA normal screensaver returns to the exact Console section and selection that was active before it opened. Sleep/lock behavior returns to Login.\n\nRESOURCE CLEANUP\nPan, zoom, crossfade timers, and image textures are released when the screensaver closes."
        },
        {
            title: "TERMINAL & DEV MODE",
            subtitle: "Advanced system access",
            body: "Terminal is a full-screen NeutronOS app backed by a shared PTY session. HDMI/controller input and the optional web mirror operate the same session.\n\nNORMAL MODE\nRuns the standard user shell. Sudo follows normal Linux security.\n\nDEVELOPER MODE\nA separate global Console-owned security state. It uses its own hashed credential and warning flow. When enabled, Terminal can expose advanced/root workflows and NeutronOS can unlock high-level controls.\n\nSAFETY\nDeveloper Mode overrides normal safeguards and can damage the installation if misused. It is not the same as the Login combo or web-mirror token.\n\nTERMINAL CONTROLS\nUse the bottom type bar, toolbar, quick commands, clipboard panel, and Exit modal. O backs out of overlays; exiting returns to Console."
        },
        {
            title: "SAFETY & ARMING",
            subtitle: "Destructive-action rules",
            body: "Red means an action is armed or destructive. NeutronOS intentionally separates navigation from dangerous execution.\n\nARMED FLOW\nThe first action highlights or opens confirmation. A second explicit confirmation performs the operation. O cancels and clears the armed state.\n\nPROTECTED OPERATIONS\nShutdown, reboot, service restart, network restart, saved-network deletion, logout, process Kill, and other high-impact actions require confirmation according to backend policy.\n\nBACKEND OWNERSHIP\nQML does not directly run arbitrary shell commands. C++ managers validate the request and execute supported systemd, Docker, script, or application actions.\n\nDEVELOPER MODE\nSome advanced operations remain blocked until Developer Mode is enabled."
        },
        {
            title: "TROUBLESHOOTING",
            subtitle: "Common recovery steps",
            body: "APP OPENS WITH EMPTY DATA\nOpen App Controls and confirm its service/container is running. Service-aware launch should start it before AppHost opens.\n\nNETWORK RESULT DOES NOT UPDATE\nOpen Network, run Speed Test, and check its status. Confirm NetworkManager is active and diagnostics pass.\n\nMODAL INPUT WORKS BUT PANEL IS INVISIBLE\nPress O to close it. Check the service log for QML load errors and verify the modal source exists.\n\nCONTROLLER CONNECTED BUT HIGH CPU\nRun the controller CPU measurement script and compare NeutronShell with bluetoothd. High-rate Bluetooth HID traffic may remain controller-dependent.\n\nSHELL DOES NOT LOAD\nUse journalctl for neutronos.service and look for the first QML or C++ error, not repeated secondary warnings.\n\nHEALTH CHECK\nRun scripts/neutronos-health-check.sh after release-candidate patches.\n\nREBUILD\nFrom ~/NeutronOS: stop neutronos.service, remove build, configure with CMake, build with all cores, make NeutronShell executable, and restart the service."
        }
    ]

    function currentSection() {
        if (sections.length <= 0)
            return { title: "HELP", subtitle: "", body: "" }
        return sections[Math.max(0, Math.min(sections.length - 1, selectedSection))]
    }

    function open(sectionIndex) {
        selectedSection = Math.max(0, Math.min(sections.length - 1, Number(sectionIndex) || 0))
        focusPane = 0
        articleFlick.contentY = 0
        visible = true
        forceActiveFocus()
        Qt.callLater(ensureCategoryVisible)
    }

    function close() {
        if (!visible)
            return
        visible = false
        focusPane = 0
        articleFlick.contentY = 0
        closed()
    }

    function ensureCategoryVisible() {
        if (categoryList.count > 0)
            categoryList.positionViewAtIndex(selectedSection, ListView.Contain)
    }

    function chooseSection(index, enterArticle) {
        selectedSection = Math.max(0, Math.min(sections.length - 1, index))
        articleFlick.contentY = 0
        focusPane = enterArticle ? 1 : 0
        ensureCategoryVisible()
    }

    function moveCategory(delta) {
        if (sections.length <= 0)
            return true
        selectedSection = (selectedSection + delta + sections.length) % sections.length
        articleFlick.contentY = 0
        ensureCategoryVisible()
        return true
    }

    function scrollArticle(delta) {
        var maximum = Math.max(0, articleFlick.contentHeight - articleFlick.height)
        articleFlick.contentY = Math.max(0, Math.min(maximum,
                                                    articleFlick.contentY + delta * articleScrollStep))
        return true
    }

    function normalize(value) {
        var action = String(value || "").trim().toLowerCase()
        if (action === "cross" || action === "x" || action === "primary" || action === "confirm") return "primary"
        if (action === "circle" || action === "o" || action === "cancel" || action === "back") return "cancel"
        if (action === "lb" || action === "l1") return "l1"
        if (action === "rb" || action === "r1") return "r1"
        if (action === "dpad_up") return "up"
        if (action === "dpad_down") return "down"
        if (action === "dpad_left") return "left"
        if (action === "dpad_right") return "right"
        return action
    }

    function handleControllerPressed(value) {
        if (!visible)
            return false

        var action = normalize(value)
        if (action === "cancel") {
            if (focusPane === 1) {
                focusPane = 0
                ensureCategoryVisible()
            } else {
                close()
            }
            return true
        }
        if ((action === "context" || action === "triangle" || action === "y") && selectedSection === 2) {
            loginInstructionsRequested()
            return true
        }
        if (action === "left") {
            focusPane = 0
            ensureCategoryVisible()
            return true
        }
        if (action === "right" || action === "primary") {
            focusPane = 1
            return true
        }
        if (action === "l1") return moveCategory(-1)
        if (action === "r1") return moveCategory(1)
        if (action === "up") return focusPane === 0 ? moveCategory(-1) : scrollArticle(-1)
        if (action === "down") return focusPane === 0 ? moveCategory(1) : scrollArticle(1)
        return true
    }

    Keys.onPressed: function(event) {
        var action = ""
        if (event.key === Qt.Key_Left) action = "left"
        else if (event.key === Qt.Key_Right) action = "right"
        else if (event.key === Qt.Key_Up) action = "up"
        else if (event.key === Qt.Key_Down) action = "down"
        else if (event.key === Qt.Key_PageUp) action = "l1"
        else if (event.key === Qt.Key_PageDown) action = "r1"
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) action = "primary"
        else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) action = "cancel"
        if (action.length > 0) {
            event.accepted = true
            handleControllerPressed(action)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#C0000000"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 96, 1660)
        height: Math.min(parent.height - 80, 950)
        radius: 34
        color: "#06111F"
        border.width: 2
        border.color: "#5BCFF5"
        clip: true

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 100
            color: "#0A1B2E"
            border.width: 1
            border.color: "#2D506E"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20

                Rectangle {
                    width: 58
                    height: 58
                    radius: 18
                    color: "#102C45"
                    border.width: 2
                    border.color: "#7DF9FF"

                    Text {
                        anchors.centerIn: parent
                        text: "?"
                        color: "#FFFFFF"
                        font.pixelSize: 36
                        font.bold: true
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        text: "NEUTRONOS HELP CENTER"
                        color: "#FFFFFF"
                        font.pixelSize: 29
                        font.bold: true
                        font.letterSpacing: 1.4
                    }

                    Text {
                        text: "Complete controller-first guide to Gemini"
                        color: "#9FD8FF"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                width: 184
                height: 40
                radius: 20
                color: focusPane === 0 ? "#153A56" : "#0C2438"
                border.width: 1
                border.color: focusPane === 0 ? "#7DF9FF" : "#3D6888"

                Text {
                    anchors.centerIn: parent
                    text: focusPane === 0 ? "SECTION RAIL" : "ARTICLE"
                    color: "#D9FAFF"
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.6
                }
            }
        }

        Rectangle {
            id: categoryRail
            anchors.left: parent.left
            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: 360
            color: "#081726"
            border.width: 1
            border.color: "#25435D"

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 24
                anchors.topMargin: 18
                text: "GUIDE SECTIONS"
                color: "#7199BA"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2.0
            }

            ListView {
                id: categoryList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 52
                anchors.bottomMargin: 16
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 7
                clip: true
                model: root.sections
                currentIndex: root.selectedSection
                interactive: true

                delegate: Rectangle {
                    width: categoryList.width
                    height: 62
                    radius: 16
                    color: root.selectedSection === index
                           ? root.focusPane === 0 ? "#123650" : "#0D293F"
                           : "#091929"
                    border.width: root.selectedSection === index ? 2 : 1
                    border.color: root.selectedSection === index
                                  ? root.focusPane === 0 ? "#7DF9FF" : "#477B9D"
                                  : "#203A50"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: parent.height - 18
                        radius: 4
                        color: root.selectedSection === index ? "#7DF9FF" : "#2A506B"
                        opacity: root.selectedSection === index ? 1.0 : 0.45
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            text: modelData.title
                            color: root.selectedSection === index ? "#FFFFFF" : "#C1D7E8"
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.subtitle
                            color: root.selectedSection === index ? "#9FE8FF" : "#6E91AC"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.chooseSection(index, true)
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 7
                }
            }
        }

        Rectangle {
            id: articlePanel
            anchors.left: categoryRail.right
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            color: "#06111F"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 96
                color: "#081928"
                border.width: 1
                border.color: "#203E57"

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: root.currentSection().title
                        color: "#FFFFFF"
                        font.pixelSize: 27
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    Text {
                        text: root.currentSection().subtitle
                        color: "#8CDCF8"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.selectedSection + 1) + " / " + root.sections.length
                    color: "#6F9DBB"
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            Flickable {
                id: articleFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 96
                anchors.leftMargin: 34
                anchors.rightMargin: 22
                anchors.bottomMargin: 18
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, articleText.implicitHeight + 54)
                interactive: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: articleText
                    width: articleFlick.width - 34
                    x: 4
                    y: 26
                    text: root.currentSection().body
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: "#D5E8F5"
                    font.pixelSize: 18
                    lineHeight: 1.32
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 8
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: root.focusPane === 1 ? 2 : 0
                border.color: "#7DF9FF"
                opacity: 0.72
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 72
            color: "#071522"
            border.width: 1
            border.color: "#29475F"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedSection === 2
                      ? "D-PAD  Navigate     X  Open/scroll     TRIANGLE  Controller Login instructions     O  Back"
                      : (root.focusPane === 0
                         ? "D-PAD  Select section     X  Open article     L1/R1  Previous/next     O  Close"
                         : "D-PAD ↑↓  Scroll     L1/R1  Previous/next article     O  Return to sections")
                color: "#A8CDE3"
                font.pixelSize: 14
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                text: "NEUTRONOS  •  GEMINI"
                color: "#5F88A5"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.5
            }
        }
    }
}
