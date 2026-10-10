import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../../components" as Shared
import "../../modals/system"
import "../../modals" as Modals
import "../../dashboard/v2" as DashboardV2

Item {
    id: root
    anchors.fill: parent
    focus: true

    property string appId: "settings"
    property string appName: "Settings"
    property var appData: ({})
    property var activeUser: null
    property bool developerModeEnabled: settingsBackend ? settingsBackend.developerModeEnabled : false
    property bool hostActive: true

    signal exitRequested()
    signal backgroundRequested()
    signal launchAppRequested(var appData)
    onExitRequested: {
        if (securityBackend && typeof securityBackend.clearHighPriorityAuthorization === "function")
            securityBackend.clearHighPriorityAuthorization()
    }

    property var settingsBackend: (typeof settingsManager !== "undefined") ? settingsManager : null
    property var userBackend: (typeof userManager !== "undefined") ? userManager : null
    property var storageBackend: (typeof storageManager !== "undefined") ? storageManager : null
    property var networkBackend: (typeof networkManager !== "undefined") ? networkManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var developerBackend: (typeof developerModeManager !== "undefined") ? developerModeManager : null
    property var securityBackend: (typeof securityManager !== "undefined") ? securityManager : null
    property var securityCoreBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    property var appBackend: (typeof appManager !== "undefined") ? appManager : null
    property var updateRecoveryBackend: (typeof updateRecoveryManager !== "undefined") ? updateRecoveryManager : null
    property var backupRestoreBackend: (typeof backupRestoreManager !== "undefined") ? backupRestoreManager : null
    property var diagnosticsBackend: (typeof diagnosticsManager !== "undefined") ? diagnosticsManager : null
    property var coreBackend: (typeof coreCapabilitiesManager !== "undefined") ? coreCapabilitiesManager : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property var performanceBackend: (typeof performanceManager !== "undefined") ? performanceManager : null
    property var personalizationBackend: (typeof personalizationManager !== "undefined") ? personalizationManager : null
    property var dashboardLayoutBackend: (typeof dashboardLayoutManager !== "undefined") ? dashboardLayoutManager : null

    property bool lightMode: settingsBackend ? settingsBackend.themeMode === "light" : false
    property color windowColor: lightMode ? "#F4F6F8" : "#02060D"
    property color chromeColor: lightMode ? "#EEF2F6" : "#030810"
    property color sidebarColor: lightMode ? "#EEF2F6" : root.chromeColor
    property color panelColor: lightMode ? "#FFFFFF" : "#071426"
    property color panelRaised: lightMode ? "#F7F9FB" : "#0B1A30"
    property color panelInset: lightMode ? "#E9EEF4" : "#06101F"
    property color textPrimary: lightMode ? "#080B10" : "#F4FBFF"
    property color textSecondary: lightMode ? "#2F3945" : "#C8D5DF"
    property color textMuted: lightMode ? "#65717E" : "#8AA6C8"
    property color divider: lightMode ? "#CFD6DE" : "#1D3958"
    property color focusBlue: "#4DA6FF"
    property color cyan: "#7DF9FF"
    property color success: "#22FF88"
    property color warning: "#F5C542"
    property color danger: "#FF3040"
    property color purple: "#B75CFF"

    property int sidebarIndex: 0
    property int focusZone: 0       // 0 sidebar/tiles, 1 content, 2 pending footer, 3 header menu
    property string displayMode: settingsBackend
                                 ? String(settingsBackend.value("ui.settingsDisplayMode", "list"))
                                 : "list"
    property int tileIndex: 0
    readonly property bool securityAttention: !securityCoreBackend || !securityCoreBackend.daemonOnline
                                                    || !securityCoreBackend.auditValid
                                                    || Number(securityCoreBackend.threatLevel || 5) <= 2
    property int armedRow: -1
    property string searchText: ""
    property bool searchActive: searchText.trim().length > 0
    property bool keyboardOpen: false
    property string keyboardTarget: ""
    property string keyboardBuffer: ""
    property string statusMessage: ""
    property bool statusError: false
    property bool rebootPromptVisible: false
    property string rebootReason: ""
    property int rebootChoice: 0
    property bool detailsVisible: false
    property bool dashboardLayoutVisible: false
    property int dashboardLayoutIndex: 0
    property int dashboardLayoutPhase: 0 // widget, action, proposed change
    property int dashboardLayoutAction: 0
    property int dashboardMoveDelta: 0
    property string dashboardProposedSize: "small"
    property var detailsData: ({})
    property string wifiSsidDraft: ""
    property string newUserNameDraft: ""
    property string newUserDisplayDraft: ""
    property string newUserPasswordDraft: ""
    property bool exitModalVisible: false
    property int exitChoice: 0
    property bool editionModalVisible: false
    property bool piModalVisible: false
    property bool easterEggVisible: false
    property bool systemReportVisible: false
    property bool buttonTestVisible: false
    property bool buttonTestFinished: false
    property int buttonTestReceivedTotal: 0
    property int aboutTapCount: 0
    property double lastAboutTapMs: 0
    property double buttonTestLastSystemMs: 0
    property string pendingProtectedKind: ""
    property bool phase1RecoveryPending: false
    property string pendingProtectedAction: ""
    property var pendingProtectedData: ({})
    // Patch 37: developer pages use a real ListModel and the same proven
    // SettingDelegate used by every working Settings category. This avoids
    // the JavaScript-array/required-property delegate path that rendered no
    // delegates on Qt 6.
    property int developerPageIndex: 0
    readonly property string activeCategoryId: categories[Math.max(0, Math.min(categories.length - 1, sidebarIndex))].id
    // Patch 38: Performance and Advanced deliberately use the same proven
    // pageModel + SettingDelegate path as every working Settings category.
    // The separate developer-page renderer is disabled because it repeatedly
    // produced an empty right panel on the target Qt 6/Raspberry Pi runtime.
    readonly property bool developerPageActive: false
    readonly property bool performancePageActive: !searchActive && activeCategoryId === "performance"

    readonly property var categories: [
        { id: "user", title: userDisplayName(), detail: "USER SETTINGS", icon: "●" },
        { id: "system", title: "System", detail: "IDENTITY & STARTUP", icon: "N" },
        { id: "display", title: "Display", detail: "SCREEN & HDMI", icon: "▣" },
        { id: "interfaces", title: "Interfaces", detail: "HARDWARE & REMOTE", icon: "⌁" },
        { id: "network", title: "Network", detail: "WI-FI & ETHERNET", icon: "WIFI" },
        { id: "controllers", title: "Controller Center", detail: "PROFILES, TEST & FEEDBACK", icon: "✣" },
        { id: "audio", title: "Audio", detail: "OUTPUT & VOLUME", icon: "♪" },
        { id: "bluetooth", title: "Bluetooth", detail: "DEVICES & PAIRING", icon: "BT" },
        { id: "appearance", title: "Appearance", detail: "THEME & WALLPAPER", icon: "✦" },
        { id: "localization", title: "Localization", detail: "LANGUAGE & REGION", icon: "◎" },
        { id: "accessibility", title: "Accessibility", detail: "VISION & INPUT", icon: "◈" },
        { id: "apps", title: "Apps & Services", detail: "RUNTIME & DEFAULTS", icon: "▦" },
        { id: "storage", title: "Storage", detail: "USAGE BY DEVICE", icon: "▤" },
        { id: "security", title: "Security & Privacy", detail: "ACCESS & HISTORY", icon: "◆" },
        { id: "update-recovery", title: "Update & Recovery", detail: "SIGNED UPDATES & REPAIR", icon: "↻" },
        { id: "backup-restore", title: "Backup & Restore", detail: "BACKUP, WIPE & REINSTALL", icon: "⇄" },
        { id: "notifications", title: "Notifications", detail: "ALERTS & SOUNDS", icon: "◍" },
        { id: "power", title: "Power", detail: "ENERGY & COOLING", icon: "ϟ" },
        { id: "performance", title: "Performance", detail: "DEVELOPER MODE", icon: "speedometer" },
        { id: "advanced", title: "Advanced", detail: "DEVELOPER MODE", icon: "⚙" },
        { id: "diagnostics", title: "Diagnostics", detail: "HEALTH & SUPPORT", icon: "◇" },
        { id: "services", title: "Services", detail: "SYSTEMD & STARTUP", icon: "⚙" },
        { id: "help", title: "Help", detail: "GUIDES & TROUBLESHOOTING", icon: "?" },
        { id: "about", title: "About", detail: "DEVICE INFORMATION", icon: "i" }
    ]

    ListModel { id: pageModel; dynamicRoles: true }
    ListModel { id: developerPageModel; dynamicRoles: true }
    ListModel { id: buttonTestModel; dynamicRoles: true }

    component AtomAnimation: Item {
        id: atomRoot
        property bool specialMode: false
        property bool running: visible
        property color blueColor: "#18BFFF"
        property color redColor: "#FF355D"
        property color pulseColor: "#B75CFF"

        Rectangle {
            id: atomPulse
            anchors.centerIn: parent
            width: parent.width * 0.58
            height: width
            radius: width / 2
            color: "transparent"
            border.width: atomRoot.specialMode ? 6 : 3
            border.color: atomRoot.pulseColor
            opacity: 0.12
            scale: 0.72

            SequentialAnimation on scale {
                running: atomRoot.running
                loops: Animation.Infinite
                NumberAnimation { from: 0.72; to: atomRoot.specialMode ? 1.18 : 1.02; duration: atomRoot.specialMode ? 900 : 1500; easing.type: Easing.OutCubic }
                NumberAnimation { from: atomRoot.specialMode ? 1.18 : 1.02; to: 0.72; duration: atomRoot.specialMode ? 900 : 1500; easing.type: Easing.InCubic }
            }
            SequentialAnimation on opacity {
                running: atomRoot.running
                loops: Animation.Infinite
                NumberAnimation { from: 0.08; to: atomRoot.specialMode ? 0.54 : 0.28; duration: atomRoot.specialMode ? 900 : 1500 }
                NumberAnimation { from: atomRoot.specialMode ? 0.54 : 0.28; to: 0.08; duration: atomRoot.specialMode ? 900 : 1500 }
            }
        }

        Image {
            id: atomImage
            anchors.centerIn: parent
            width: parent.width * 0.86
            height: width
            source: root.themeFile("atom.png")
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            cache: true
            opacity: root.lightMode ? 0.82 : 0.96
            RotationAnimation on rotation {
                running: atomRoot.running
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: atomRoot.specialMode ? 3600 : 7600
            }
        }

        Item {
            anchors.centerIn: parent
            width: parent.width * 0.86
            height: width
            RotationAnimation on rotation {
                running: atomRoot.running
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: atomRoot.specialMode ? 2100 : 4700
            }
            Rectangle {
                width: atomRoot.specialMode ? 18 : 12
                height: width
                radius: width / 2
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: atomRoot.blueColor
                border.width: 2
                border.color: "#D8F7FF"
            }
            Rectangle {
                width: atomRoot.specialMode ? 18 : 12
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: atomRoot.redColor
                border.width: 2
                border.color: "#FFE2E8"
            }
        }

        Item {
            anchors.centerIn: parent
            width: parent.width * 0.66
            height: width
            rotation: 58
            RotationAnimation on rotation {
                running: atomRoot.running
                loops: Animation.Infinite
                from: 58
                to: -302
                duration: atomRoot.specialMode ? 2700 : 6200
            }
            Rectangle {
                width: atomRoot.specialMode ? 14 : 9
                height: width
                radius: width / 2
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                color: atomRoot.pulseColor
            }
        }
    }

    component SpeedometerGlyph: Canvas {
        id: gaugeGlyph
        property color glyphColor: root.cyan
        onGlyphColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var w = width
            var h = height
            var cx = w * 0.5
            var cy = h * 0.58
            var r = Math.min(w, h) * 0.38
            ctx.strokeStyle = String(glyphColor)
            ctx.fillStyle = String(glyphColor)
            ctx.lineWidth = Math.max(2, Math.min(w, h) * 0.085)
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.PI * 0.82, Math.PI * 2.18, false)
            ctx.stroke()

            var angle = Math.PI * 1.78
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + Math.cos(angle) * r * 0.78, cy + Math.sin(angle) * r * 0.78)
            ctx.stroke()

            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(2.2, r * 0.13), 0, Math.PI * 2, false)
            ctx.fill()
        }
    }

    component CategoryGlyph: Item {
        id: categoryGlyph
        property string categoryId: ""
        property string fallbackText: ""
        property color glyphColor: root.cyan
        property color systemColor: root.danger

        Text {
            anchors.centerIn: parent
            visible: categoryGlyph.categoryId !== "network" && categoryGlyph.categoryId !== "bluetooth" && categoryGlyph.categoryId !== "performance"
            text: categoryGlyph.categoryId === "system" ? "N" : categoryGlyph.fallbackText
            color: categoryGlyph.categoryId === "system" ? categoryGlyph.systemColor : categoryGlyph.glyphColor
            font.pixelSize: Math.max(16, Math.min(parent.width, parent.height) * 0.52)
            font.bold: true
        }

        SpeedometerGlyph {
            anchors.centerIn: parent
            width: parent.width * 0.68
            height: width
            visible: categoryGlyph.categoryId === "performance"
            glyphColor: categoryGlyph.glyphColor
        }

        Canvas {
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: parent.height * 0.72
            visible: categoryGlyph.categoryId === "network" || categoryGlyph.categoryId === "bluetooth"
            onVisibleChanged: if (visible) requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.strokeStyle = String(categoryGlyph.glyphColor)
                c.fillStyle = String(categoryGlyph.glyphColor)
                c.lineWidth = Math.max(2.3, width * 0.085)
                c.lineCap = "round"
                c.lineJoin = "round"
                if (categoryGlyph.categoryId === "network") {
                    var cx = width / 2
                    var baseY = height * 0.76
                    var radii = [width * 0.17, width * 0.34, width * 0.51]
                    for (var i = 0; i < radii.length; ++i) {
                        c.beginPath()
                        c.arc(cx, baseY, radii[i], Math.PI * 1.18, Math.PI * 1.82, false)
                        c.stroke()
                    }
                    c.beginPath()
                    c.arc(cx, baseY, width * 0.055, 0, Math.PI * 2, false)
                    c.fill()
                } else {
                    c.beginPath()
                    c.moveTo(width * 0.48, height * 0.06)
                    c.lineTo(width * 0.48, height * 0.94)
                    c.moveTo(width * 0.48, height * 0.06)
                    c.lineTo(width * 0.80, height * 0.29)
                    c.lineTo(width * 0.22, height * 0.71)
                    c.moveTo(width * 0.48, height * 0.94)
                    c.lineTo(width * 0.80, height * 0.71)
                    c.lineTo(width * 0.22, height * 0.29)
                    c.stroke()
                }
            }
        }
    }

    component SidebarItem: Rectangle {
        property string titleText: ""
        property string detailText: ""
        property string iconText: ""
        property string categoryId: ""
        property bool speedometerIcon: false
        property bool selected: false
        property bool activePage: false
        property bool locked: false
        width: ListView.view ? ListView.view.width : 300
        height: titleText === root.userDisplayName() ? 116 : 76
        radius: 18
        color: selected ? (root.lightMode ? "#DCEEFF" : "#17365D")
                        : activePage ? (root.lightMode ? "#EAF4FF" : "#102943")
                                     : "transparent"
        border.width: selected ? 2 : 0
        border.color: root.focusBlue
        opacity: locked ? 0.58 : 1.0

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height > 90 ? 64 : 44
            height: width
            radius: parent.height > 90 ? 22 : 14
            color: selected ? root.focusBlue : root.panelInset
            border.width: 1
            border.color: selected ? "#BDEBFF" : root.divider

            Image {
                anchors.fill: parent
                anchors.margins: 4
                visible: parent.parent.height > 90 && root.userAvatar().length > 0
                source: root.userAvatar()
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }

            CategoryGlyph {
                anchors.centerIn: parent
                width: parent.width * 0.72
                height: width
                visible: !(parent.parent.height > 90 && root.userAvatar().length > 0)
                categoryId: parent.parent.categoryId
                fallbackText: parent.parent.iconText
                glyphColor: parent.parent.selected ? "#04111F" : root.cyan
                systemColor: root.danger
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: parent.height > 90 ? 88 : 68
            anchors.right: lockLabel.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                width: parent.width
                text: titleText
                color: root.textPrimary
                font.pixelSize: parent.parent.height > 90 ? 20 : 17
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: detailText
                color: selected ? root.focusBlue : root.textMuted
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.9
                elide: Text.ElideRight
            }
        }

        Text {
            id: lockLabel
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            visible: locked
            text: "LOCKED"
            color: root.warning
            font.pixelSize: 10
            font.bold: true
        }
    }

    component SettingDelegate: Item {
        id: row
        property bool selected: ListView.isCurrentItem && root.focusZone === 1
        property var rowData: model
        property var deviceValue: (model && model.deviceData) ? model.deviceData : ({})
        width: ListView.view ? ListView.view.width : 900
        height: model.kind === "section" ? 56 : model.kind === "storage" ? 230 : model.kind === "warning" ? 120 : 94
        opacity: model.locked === true ? 0.48 : 1.0

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            radius: model.kind === "section" ? 0 : 18
            color: model.kind === "section" ? "transparent"
                  : row.selected ? (model.danger === true ? (root.lightMode ? "#FFE5E9" : "#4A1720")
                                                           : (root.lightMode ? "#DFEFFF" : "#17365D"))
                                 : root.panelRaised
            border.width: model.kind === "section" ? 0 : row.selected ? 2 : 1
            border.color: row.selected ? (model.danger === true ? root.danger : root.focusBlue) : root.divider

            Text {
                visible: model.kind === "section"
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: String(model.title || "").toUpperCase()
                color: root.focusBlue
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 1.5
            }

            Item {
                anchors.fill: parent
                visible: model.kind !== "section" && model.kind !== "storage"

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: parent.height - 30
                    radius: 3
                    color: row.selected ? (model.danger === true ? root.danger : root.focusBlue) : root.divider
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 36
                    anchors.right: valueText.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Text {
                        width: parent.width
                        text: model.title || ""
                        color: root.textPrimary
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: model.detail || ""
                        color: model.kind === "warning" ? root.warning : root.textSecondary
                        font.pixelSize: 13
                        wrapMode: model.kind === "warning" ? Text.WordWrap : Text.NoWrap
                        elide: model.kind === "warning" ? Text.ElideNone : Text.ElideRight
                    }
                }

                Text {
                    id: valueText
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(300, implicitWidth)
                    text: root.rowValueText(model)
                    color: model.locked === true ? root.warning
                           : model.danger === true ? root.danger
                           : model.kind === "toggle" && root.rowCurrentValue(model) === true ? root.success
                           : root.cyan
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 20
                visible: model.kind === "storage"
                
                Column {
                    anchors.fill: parent
                    spacing: 12
                    Row {
                        width: parent.width
                        height: 50
                        spacing: 14
                        Rectangle {
                            width: 48; height: 48; radius: 15
                            color: root.panelInset
                            border.width: 1; border.color: root.divider
                            Text { anchors.centerIn: parent; text: row.deviceValue.system === true ? "BOOT" : "DRV"; color: root.cyan; font.pixelSize: 11; font.bold: true }
                        }
                        Column {
                            width: parent.width - 300
                            spacing: 3
                            Text { width: parent.width; text: String(row.deviceValue.name || "Storage Device"); color: root.textPrimary; font.pixelSize: 19; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: String(row.deviceValue.mount || "") + "  •  " + String(row.deviceValue.filesystem || "Unknown"); color: root.textMuted; font.pixelSize: 12; elide: Text.ElideMiddle }
                        }
                        Column {
                            width: 210
                            spacing: 3
                            Text { width: parent.width; text: String(row.deviceValue.used || "0 B") + " used"; color: root.textPrimary; font.pixelSize: 16; font.bold: true; horizontalAlignment: Text.AlignRight }
                            Text { width: parent.width; text: String(row.deviceValue.free || "0 B") + " available"; color: root.textMuted; font.pixelSize: 12; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 20
                        radius: 10
                        color: root.panelInset
                        clip: true
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: row.deviceValue && row.deviceValue.categories ? row.deviceValue.categories : []
                                Rectangle {
                                    height: parent.height
                                    width: Math.max(2, parent.width * Number(modelData.percent || 0) / 100)
                                    color: String(modelData.color || "#64748B")
                                }
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: row.deviceValue && row.deviceValue.categories ? row.deviceValue.categories : []
                            Row {
                                spacing: 5
                                Rectangle { width: 9; height: 9; radius: 3; color: String(modelData.color || "#64748B") }
                                Text { text: String(modelData.name || "Other") + " " + String(modelData.formatted || ""); color: root.textSecondary; font.pixelSize: 11; font.bold: true }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: (row.deviceValue && row.deviceValue.scanComplete === false) ? "Partial analysis — select Analyze Storage to continue." : String(row.deviceValue.status || "Analyzed")
                        color: row.deviceValue && row.deviceValue.scanComplete === false ? root.warning : root.success
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }
        }

        // Settings is controller-first, but rows should still behave as real
        // clickable controls for touch/mouse users instead of being decorative
        // cards. Section headings remain non-interactive.
        MouseArea {
            anchors.fill: parent
            enabled: model.kind !== "section" && model.selectable !== false
            onClicked: {
                root.focusZone = 1
                if (row.ListView.view)
                    row.ListView.view.currentIndex = index
                root.activateRow(model, index)
            }
        }
    }

    component DeveloperSettingDelegate: Item {
        id: devRow
        required property var entry
        required property int entryIndex
        property bool selected: root.focusZone === 1 && root.developerPageIndex === entryIndex
        property bool locked: root.developerRowLocked(entry)

        width: ListView.view ? ListView.view.width : 900
        height: entry.kind === "section" ? 58 : entry.kind === "warning" ? 126 : 98
        opacity: locked ? 0.52 : 1.0

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 8
            radius: devRow.entry.kind === "section" ? 0 : 18
            color: devRow.entry.kind === "section" ? "transparent"
                  : devRow.selected ? (root.lightMode ? "#DFEFFF" : "#17365D")
                                    : root.panelRaised
            border.width: devRow.entry.kind === "section" ? 0 : devRow.selected ? 3 : 1
            border.color: devRow.selected ? root.focusBlue : root.divider

            Text {
                visible: devRow.entry.kind === "section"
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: String(devRow.entry.title || "").toUpperCase()
                color: root.focusBlue
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 1.5
            }

            Item {
                anchors.fill: parent
                visible: devRow.entry.kind !== "section"

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: parent.height - 30
                    radius: 3
                    color: devRow.entry.kind === "warning" ? root.warning
                          : devRow.selected ? root.focusBlue : root.divider
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 36
                    anchors.right: valueText.left
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Text {
                        width: parent.width
                        text: String(devRow.entry.title || "")
                        color: root.textPrimary
                        font.pixelSize: 19
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: String(devRow.entry.detail || "")
                        color: devRow.entry.kind === "warning" ? root.warning : root.textSecondary
                        font.pixelSize: 13
                        wrapMode: devRow.entry.kind === "warning" ? Text.WordWrap : Text.NoWrap
                        elide: devRow.entry.kind === "warning" ? Text.ElideNone : Text.ElideRight
                    }
                }

                Text {
                    id: valueText
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(330, implicitWidth)
                    text: devRow.locked ? "LOCKED" : root.rowValueText(devRow.entry)
                    color: devRow.locked ? root.warning
                           : devRow.entry.danger === true ? root.danger
                           : devRow.entry.kind === "toggle" && root.rowCurrentValue(devRow.entry) === true ? root.success
                           : root.cyan
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.windowColor
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.lightMode ? "#F5F7FA" : root.chromeColor }
            GradientStop { position: 0.34; color: root.lightMode ? "#EEF2F6" : "#04101F" }
            GradientStop { position: 0.72; color: root.windowColor }
            GradientStop { position: 1.0; color: root.lightMode ? "#E7EDF5" : root.chromeColor }
        }
    }

    Rectangle {
        id: settingsChromeBody
        visible: root.displayMode === "list"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: pendingBar.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        color: root.chromeColor
        border.width: 0
        z: 0
    }

    Rectangle {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        height: 54
        // Match the shared footer/header surface so the chrome reads as one
        // continuous frame instead of isolated dark bars.
        color: root.chromeColor
        radius: 5
        border.width: 0
        clip: true
        z: 5

        Shared.ReferenceAppHeader {
            anchors.fill: parent
            anchors.margins: -2
            appTitle: "Settings"
            primaryStatus: root.securityAttention ? "Unsecure" : "Secure"
            primaryTone: root.securityAttention ? "danger" : "success"
            attention: root.securityAttention
            menuFocused: root.focusZone === 3 && !root.exitModalVisible
            onMenuRequested: root.openExitPrompt()
        }

        Text {
            visible: false
            anchors.left: parent.left
            anchors.leftMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: root.textPrimary
            font.pixelSize: 32
            font.bold: true
        }

        Rectangle {
            id: searchBar
            visible: false
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(720, parent.width * 0.40)
            height: 58
            radius: 20
            color: root.panelRaised
            border.width: root.searchActive ? 2 : 1
            border.color: root.searchActive ? root.focusBlue : root.divider
            Row {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 12
                Text { text: "⌕"; color: root.focusBlue; font.pixelSize: 24; font.bold: true }
                Text {
                    width: parent.width - 110
                    text: root.searchText.length > 0 ? root.searchText : "Search all settings…"
                    color: root.searchText.length > 0 ? root.textPrimary : root.textMuted
                    font.pixelSize: 16
                    elide: Text.ElideRight
                }
                Text { text: "△"; color: root.textMuted; font.pixelSize: 15; font.bold: true }
            }
        }

        Rectangle {
            visible: false
            anchors.right: parent.right
            anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            width: 184
            height: 52
            radius: 18
            color: root.panelRaised
            border.width: 1
            border.color: root.divider
            Row {
                anchors.centerIn: parent
                spacing: 10
                Text { text: root.focusZone === 1 ? "✓" : (root.lightMode ? "☀" : "◐"); color: root.focusZone === 1 ? root.success : (root.lightMode ? root.warning : root.cyan); font.pixelSize: 20 }
                Text { text: root.focusZone === 1 ? "APPLY" : (root.lightMode ? "DARK MODE" : "LIGHT MODE"); color: root.textPrimary; font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.0 }
                Text { text: "□"; color: root.focusBlue; font.pixelSize: 15; font.bold: true }
            }
        }
    }

    Rectangle {
        id: sidebar
        visible: root.displayMode === "list"
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.top: topBar.bottom
        anchors.bottom: pendingBar.top
        width: 336
        color: root.sidebarColor
        border.width: 0

        ListView {
            id: sidebarList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: sidebarBrand.top
            anchors.margins: 14
            anchors.bottomMargin: 8
            spacing: 4
            clip: true
            model: root.categories
            currentIndex: root.sidebarIndex
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 130
            delegate: SidebarItem {
                titleText: modelData.title
                detailText: modelData.detail
                iconText: modelData.icon
                categoryId: modelData.id
                speedometerIcon: modelData.id === "performance"
                selected: index === root.sidebarIndex && root.focusZone === 0
                activePage: index === root.sidebarIndex
                locked: root.categoryLocked(modelData.id)
            }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }

        Rectangle {
            id: sidebarBrand
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            height: 138
            radius: 22
            color: root.panelRaised
            border.width: 1
            border.color: root.divider
            clip: true

            AtomAnimation {
                width: 96
                height: 96
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                running: root.hostActive
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 120
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    width: parent.width
                    text: "NeutronOS"
                    color: root.lightMode ? "#071A33" : "#FFFFFF"
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: "GEMINI"
                    color: root.cyan
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 2.0
                }
                Text {
                    width: parent.width
                    text: "GEMINI EDITION"
                    color: root.purple
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.0
                }
            }
        }
    }

    Item {
        id: contentHost
        visible: root.displayMode === "list"
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.top: topBar.bottom
        anchors.bottom: pendingBar.top

        Rectangle {
            anchors.fill: parent
            anchors.margins: 18
            id: rightSettingsPanel
            radius: 24
            color: root.panelColor
            border.width: 0
            clip: true

            Canvas {
                anchors.fill: parent
                z: 20
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    var c = getContext("2d")
                    c.clearRect(0, 0, width, height)
                    var inset = 1.0
                    var r = 23
                    c.strokeStyle = String(root.divider)
                    c.lineWidth = 1.5
                    c.beginPath()
                    c.moveTo(inset + r, inset)
                    c.lineTo(width - inset - r, inset)
                    c.quadraticCurveTo(width - inset, inset, width - inset, inset + r)
                    c.lineTo(width - inset, height - inset - r)
                    c.quadraticCurveTo(width - inset, height - inset, width - inset - r, height - inset)
                    c.lineTo(inset + r, height - inset)
                    c.quadraticCurveTo(inset, height - inset, inset, height - inset - r)
                    c.lineTo(inset, inset + r)
                    c.quadraticCurveTo(inset, inset, inset + r, inset)
                    c.stroke()
                }
            }

            Column {
                z: 1
                anchors.fill: parent
                anchors.margins: 26
                spacing: 18

                Row {
                    width: parent.width
                    height: 66
                    spacing: 16
                    Rectangle {
                        width: 54; height: 54; radius: root.activeCategoryId === "user" ? 27 : 17
                        color: root.activeCategoryId === "user" ? root.panelInset : root.focusBlue
                        border.width: root.activeCategoryId === "user" ? 2 : 0
                        border.color: root.activeCategoryId === "user" ? root.focusBlue : "transparent"
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: root.activeCategoryId === "user" ? 3 : 0
                            visible: root.activeCategoryId === "user" && source !== ""
                            source: root.activeCategoryId === "user" ? root.userAvatar() : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            asynchronous: true
                        }

                        CategoryGlyph {
                            anchors.centerIn: parent
                            width: parent.width * 0.64
                            height: width
                            visible: root.activeCategoryId !== "user"
                            categoryId: root.activeCategoryId
                            fallbackText: root.categories[root.sidebarIndex].icon
                            glyphColor: "#04111F"
                            systemColor: root.danger
                        }
                    }
                    Column {
                        width: parent.width - 360
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            width: parent.width
                            text: root.searchActive ? "Search Results" : root.categories[root.sidebarIndex].title
                            color: root.textPrimary
                            font.pixelSize: 27
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.searchActive ? pageModel.count + " matching settings"
                                                    : root.categoryDescription(root.categories[root.sidebarIndex].id)
                            color: root.textMuted
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        width: 260; height: 44; radius: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: settingsBackend && settingsBackend.pendingCount > 0
                               ? (root.lightMode ? "#FFF4D8" : "#3A2A0E")
                               : root.developerModeEnabled
                                 ? (root.lightMode ? "#DDFCEB" : "#0B3A28")
                                 : root.panelInset
                        border.width: 1
                        border.color: settingsBackend && settingsBackend.pendingCount > 0
                                      ? root.warning
                                      : root.developerModeEnabled ? root.success : root.divider
                        Text {
                            anchors.centerIn: parent
                            text: settingsBackend && settingsBackend.pendingCount > 0
                                  ? String(settingsBackend.pendingCount) + " STAGED • X APPLY"
                                  : root.developerModeEnabled ? "DEVELOPER MODE ON" : "STANDARD MODE"
                            color: settingsBackend && settingsBackend.pendingCount > 0
                                   ? root.warning
                                   : root.developerModeEnabled ? root.success : root.textMuted
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }
                }

                ListView {
                    id: contentList
                    width: parent.width
                    height: parent.height - 84
                    visible: !root.developerPageActive && !root.performancePageActive
                    model: pageModel
                    clip: true
                    spacing: 10
                    currentIndex: 0
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 120
                    delegate: SettingDelegate { }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }

                ListView {
                    id: developerContentList
                    width: parent.width
                    height: parent.height - 84
                    visible: root.developerPageActive && !root.performancePageActive
                    model: developerPageModel
                    clip: true
                    spacing: 10
                    currentIndex: root.developerPageIndex
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 120
                    delegate: SettingDelegate { }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }

                PerformancePage {
                    id: performancePage
                    width: parent.width
                    height: parent.height - 84
                    visible: root.performancePageActive
                    backend: root.performanceBackend
                    developerModeEnabled: root.developerModeEnabled
                    activeFocusMode: root.focusZone === 1
                    lightMode: root.lightMode
                    panelColor: root.panelColor
                    raisedColor: root.panelRaised
                    insetColor: root.panelInset
                    textPrimary: root.textPrimary
                    textSecondary: root.textSecondary
                    textMuted: root.textMuted
                    divider: root.divider
                    focusBlue: root.focusBlue
                    success: root.success
                    warning: root.warning
                    danger: root.danger
                    purple: root.purple
                    onStatusChanged: function(message, error) {
                        root.statusMessage = message
                        root.statusError = error
                    }
                }
            }
        }
    }

    Rectangle {
        id: pendingBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        height: 72
        color: root.chromeColor
        border.width: 0
        clip: true
        z: 6

        Shared.ReferenceAppFooter {
            anchors.fill: parent
            anchors.margins: -2
            // NEUTRONOS_SETTINGS_FINAL_UX_V1
            hintText: settingsBackend && settingsBackend.pendingCount > 0
                      ? "STAGED CHANGE • X APPLY • O BACK"
                      : "X SELECT/APPLY • O BACK"
            controllerBackend: root.controllerBackend
        }
    }

    GridView {
        id: tileView
        objectName: "settingsTileMode"
        visible: root.displayMode === "tiles"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.bottom: pendingBar.top
        anchors.margins: 30
        cellWidth: width / 4
        cellHeight: height / 3
        clip: true
        interactive: false
        model: root.categories
        currentIndex: root.tileIndex

        delegate: Item {
            required property var modelData
            required property int index
            width: tileView.cellWidth
            height: tileView.cellHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 9
                radius: 20
                color: index === root.tileIndex && root.focusZone === 0 ? root.panelRaised : root.panelColor
                border.width: index === root.tileIndex && root.focusZone === 0 ? 3 : 1
                border.color: index === root.tileIndex && root.focusZone === 0 ? root.focusBlue : root.divider
                scale: index === root.tileIndex && root.focusZone === 0 ? 1.025 : 1
                Behavior on scale { NumberAnimation { duration: 110 } }

                Column {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10
                    Row {
                        width: parent.width
                        spacing: 14
                        Rectangle {
                            width: 48; height: 48; radius: 14
                            color: root.focusBlue
                            Text { anchors.centerIn: parent; text: modelData.icon; color: "#04111F"; font.pixelSize: 23; font.bold: true }
                        }
                        Column {
                            width: parent.width - 62
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; text: modelData.title; color: root.textPrimary; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.detail; color: root.textMuted; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.8; elide: Text.ElideRight }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: root.divider }
                    Text {
                        width: parent.width
                        text: root.categoryDescription(modelData.id)
                        color: root.textSecondary
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Item { width: 1; height: 1 }
                    Text { text: index === root.tileIndex && root.focusZone === 0 ? "X  OPEN" : ""; color: root.focusBlue; font.pixelSize: 11; font.bold: true }
                }
            }
        }
    }

    DashboardV2.SystemOverviewManager {
        id: systemOverviewManager
        anchors.fill: parent
        backend: root.dashboardLayoutBackend
        onClosed: root.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        visible: root.dashboardLayoutVisible
        color: "#C8000000"
        z: 42
        Rectangle {
            anchors.centerIn: parent; width: 1120; height: 760; radius: 32
            color: root.panelColor; border.width: 2; border.color: root.focusBlue
            Column {
                anchors.fill: parent; anchors.margins: 30; spacing: 16
                Text { text: "DASHBOARD LAYOUT"; color: root.textPrimary; font.pixelSize: 30; font.bold: true }
                Text { width: parent.width; text: "Select a widget, choose Move / Size / Enable, preview the change, then press X to commit. O always cancels the current stage."; color: root.textSecondary; font.pixelSize: 15; wrapMode: Text.WordWrap }
                Row {
                    width: parent.width; height: 540; spacing: 18
                    ListView {
                        width: parent.width * .55; height: parent.height; spacing: 8; clip: true
                        model: root.dashboardWidgets(); currentIndex: root.dashboardLayoutIndex
                        delegate: Rectangle {
                            required property int index; required property var modelData
                            width: ListView.view.width; height: 72; radius: 16
                            color: root.dashboardLayoutIndex === index ? root.panelRaised : root.panelInset
                            border.width: root.dashboardLayoutIndex === index ? 2 : 1
                            border.color: root.dashboardLayoutIndex === index ? root.focusBlue : root.divider
                            Row { anchors.fill: parent; anchors.margins: 17
                                Text { width: parent.width * .48; text: String(modelData.title || modelData.id); color: root.textPrimary; font.pixelSize: 18; font.bold: true }
                                Text { width: parent.width * .25; text: String(modelData.size || "fixed").toUpperCase(); color: root.focusBlue; font.pixelSize: 14 }
                                Text { width: parent.width * .27; text: modelData.enabled === false ? "DISABLED" : "ENABLED"; color: modelData.enabled === false ? root.danger : root.success; font.pixelSize: 14; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width * .45 - 18; height: parent.height; radius: 20; color: root.panelInset; border.width: 1; border.color: root.divider
                        Column { anchors.fill: parent; anchors.margins: 24; spacing: 18
                            Text { width: parent.width; text: root.dashboardCurrentWidget() ? String(root.dashboardCurrentWidget().title) : "No widget"; color: root.textPrimary; font.pixelSize: 24; font.bold: true }
                            Text { width: parent.width; text: root.dashboardLayoutPhase === 0 ? "X  SELECT WIDGET" : root.dashboardLayoutPhase === 1 ? "LEFT / RIGHT  CHOOSE ACTION" : "LEFT / RIGHT  CHANGE • X  CONFIRM"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; wrapMode: Text.WordWrap }
                            Row { spacing: 8; Repeater { model: root.dashboardLayoutActions(); delegate: Rectangle { required property int index; required property string modelData; width: 106; height: 52; radius: 12; color: root.dashboardLayoutPhase > 0 && root.dashboardLayoutAction === index ? root.focusBlue : root.panelRaised; Text { anchors.centerIn: parent; text: modelData; color: root.dashboardLayoutPhase > 0 && root.dashboardLayoutAction === index ? "#03101C" : root.textPrimary; font.pixelSize: 13; font.bold: true } } } }
                            Text { visible: root.dashboardLayoutPhase === 2; width: parent.width; text: root.dashboardLayoutActions()[root.dashboardLayoutAction] === "Move" ? "Proposed movement: " + (root.dashboardMoveDelta < 0 ? "LEFT" : root.dashboardMoveDelta > 0 ? "RIGHT" : "UNCHANGED") : root.dashboardLayoutActions()[root.dashboardLayoutAction] === "Size" ? "Proposed size: " + root.dashboardProposedSize.toUpperCase() : "Press X to " + root.dashboardLayoutActions()[root.dashboardLayoutAction].toLowerCase(); color: root.warning; font.pixelSize: 17; font.bold: true; wrapMode: Text.WordWrap }
                            Text { width: parent.width; text: "Temperature has one fixed size. Reflow is deterministic and stored only in the authenticated user profile."; color: root.textMuted; font.pixelSize: 14; wrapMode: Text.WordWrap }
                        }
                    }
                }
                Text { width: parent.width; text: "D-PAD  NAVIGATE     X  SELECT / CONFIRM     O  CANCEL / CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.detailsVisible
        color: "#B0000000"
        z: 40

        Rectangle {
            id: detailsPanel
            anchors.centerIn: parent
            width: 980
            height: 680
            radius: 32
            color: root.panelColor
            border.width: 2
            border.color: root.focusBlue
            clip: true
            readonly property string visualType: String(root.detailsData.visualType || "")

            Column {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 16
                visible: detailsPanel.visualType === ""

                Rectangle {
                    width: parent.width
                    height: 112
                    radius: 22
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider
                    Rectangle { width: 5; height: parent.height - 28; radius: 3; anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter; color: root.focusBlue }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 38; anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                        Text { width: parent.width; text: String(root.detailsData.title || "Details"); color: root.textPrimary; font.pixelSize: 28; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: String(root.detailsData.detail || ""); color: root.cyan; font.pixelSize: 13; font.bold: true; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 452
                    radius: 22
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider
                    Text {
                        anchors.fill: parent
                        anchors.margins: 24
                        text: String(root.detailsData.body || "No additional information.")
                        color: root.textSecondary
                        font.pixelSize: 15
                        lineHeight: 1.28
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignTop
                    }
                }

                Text { width: parent.width; text: "O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }

            Item {
                id: roleVisual
                anchors.fill: parent
                anchors.margins: 30
                visible: detailsPanel.visualType === "role"
                readonly property bool adminRole: String(root.detailsData.detail || "").toLowerCase().indexOf("admin") >= 0

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: roleVisual.adminRole ? "ADMIN" : "USER"
                    color: roleVisual.adminRole ? "#1E5BFF" : root.textPrimary
                    font.pixelSize: 38
                    font.bold: true
                    font.letterSpacing: 2.2
                }

                Canvas {
                    id: roleCanvas
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 76
                    width: 300
                    height: 300
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.lineWidth = 8
                        ctx.lineJoin = "round"
                        ctx.lineCap = "round"
                        if (roleVisual.adminRole) {
                            var cobalt = "#1E5BFF"
                            ctx.fillStyle = "#08182E"
                            ctx.strokeStyle = cobalt
                            ctx.lineWidth = 9
                            ctx.beginPath()
                            ctx.moveTo(150, 18)
                            ctx.lineTo(250, 60)
                            ctx.lineTo(232, 190)
                            ctx.quadraticCurveTo(218, 248, 150, 282)
                            ctx.quadraticCurveTo(82, 248, 68, 190)
                            ctx.lineTo(50, 60)
                            ctx.closePath()
                            ctx.fill()
                            ctx.stroke()
                            ctx.strokeStyle = "#7DF9FF"
                            ctx.lineWidth = 6
                            ctx.beginPath()
                            ctx.arc(150, 137, 54, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.fillStyle = cobalt
                            ctx.font = "bold 70px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText("N", 150, 139)
                            ctx.fillStyle = "#F4FBFF"
                            ctx.beginPath()
                            ctx.moveTo(104, 72)
                            ctx.lineTo(124, 44)
                            ctx.lineTo(150, 68)
                            ctx.lineTo(176, 44)
                            ctx.lineTo(196, 72)
                            ctx.closePath()
                            ctx.fill()
                        } else {
                            ctx.fillStyle = "#0B1A30"
                            ctx.strokeStyle = "#7DF9FF"
                            ctx.lineWidth = 7
                            ctx.beginPath()
                            ctx.arc(150, 104, 62, 0, Math.PI * 2)
                            ctx.fill()
                            ctx.stroke()
                            ctx.fillStyle = "#0B1A30"
                            ctx.strokeStyle = "#4DA6FF"
                            ctx.beginPath()
                            ctx.moveTo(54, 264)
                            ctx.quadraticCurveTo(68, 175, 150, 175)
                            ctx.quadraticCurveTo(232, 175, 246, 264)
                            ctx.closePath()
                            ctx.fill()
                            ctx.stroke()
                            ctx.fillStyle = "#B75CFF"
                            ctx.beginPath()
                            ctx.arc(150, 104, 18, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: roleCanvas.bottom
                    anchors.topMargin: 18
                    width: 620
                    height: 146
                    radius: 20
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 44
                        spacing: 8
                        Text {
                            width: parent.width
                            text: roleVisual.adminRole ? "SYSTEM AUTHORITY" : "LOCAL ACCOUNT"
                            color: roleVisual.adminRole ? "#1E5BFF" : root.focusBlue
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            font.letterSpacing: 1.2
                        }
                        Text {
                            width: parent.width
                            text: roleVisual.adminRole
                                  ? "Administrator privileges are available when NeutronOS requests authenticated elevation."
                                  : "Standard local-user privileges keep routine activity isolated from administrative changes."
                            color: root.textSecondary
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            Text { text: "Developer Mode:"; color: root.textMuted; font.pixelSize: 13; font.bold: true }
                            Text { text: root.developerModeEnabled ? "ENABLED" : "DISABLED"; color: root.developerModeEnabled ? root.success : root.danger; font.pixelSize: 13; font.bold: true; font.letterSpacing: .8 }
                        }
                    }
                }

                Text { anchors.bottom: parent.bottom; width: parent.width; text: "O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }

            Item {
                id: homeDirectoryVisual
                anchors.fill: parent
                anchors.margins: 30
                visible: detailsPanel.visualType === "homeDirectory"
                readonly property string pathText: String(root.detailsData.detail || "")

                Text {
                    anchors.top: parent.top
                    width: parent.width
                    text: "Home Directory"
                    color: root.textPrimary
                    font.pixelSize: 34
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 70
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 760
                    height: 438
                    radius: 24
                    color: root.panelInset
                    border.width: 1
                    border.color: root.divider

                    Column {
                        id: directoryTree
                        anchors.fill: parent
                        anchors.margins: 30
                        spacing: 8

                        Repeater {
                            model: root.directoryTreeSegments(homeDirectoryVisual.pathText)
                            delegate: Item {
                                required property var modelData
                                required property int index
                                width: directoryTree.width
                                height: 82

                                Rectangle {
                                    visible: modelData.depth > 0
                                    x: 36 + (modelData.depth - 1) * 58
                                    y: -20
                                    width: 2
                                    height: 62
                                    color: root.divider
                                }
                                Rectangle {
                                    visible: modelData.depth > 0
                                    x: 36 + (modelData.depth - 1) * 58
                                    y: 40
                                    width: 30
                                    height: 2
                                    color: root.divider
                                }
                                Rectangle {
                                    x: 66 + modelData.depth * 58
                                    y: 7
                                    width: Math.max(300, parent.width - x - 10)
                                    height: 68
                                    radius: 16
                                    color: index === root.directoryTreeSegments(homeDirectoryVisual.pathText).length - 1 ? root.panelRaised : "#081522"
                                    border.width: index === root.directoryTreeSegments(homeDirectoryVisual.pathText).length - 1 ? 2 : 1
                                    border.color: index === root.directoryTreeSegments(homeDirectoryVisual.pathText).length - 1 ? root.focusBlue : root.divider

                                    Item {
                                        id: folderGlyph
                                        anchors.left: parent.left
                                        anchors.leftMargin: 20
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 44
                                        height: 34
                                        Rectangle { x: 2; y: 7; width: 40; height: 25; radius: 5; color: index === root.directoryTreeSegments(homeDirectoryVisual.pathText).length - 1 ? root.cyan : root.focusBlue; opacity: 0.86 }
                                        Rectangle { x: 5; y: 2; width: 18; height: 11; radius: 4; color: index === root.directoryTreeSegments(homeDirectoryVisual.pathText).length - 1 ? root.cyan : root.focusBlue; opacity: 0.86 }
                                    }
                                    Text {
                                        anchors.left: folderGlyph.right
                                        anchors.leftMargin: 18
                                        anchors.right: parent.right
                                        anchors.rightMargin: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.name || "/")
                                        color: root.textPrimary
                                        font.pixelSize: 20
                                        font.bold: true
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 34
                    width: parent.width
                    text: homeDirectoryVisual.pathText.length > 0 ? homeDirectoryVisual.pathText : "HOME DIRECTORY UNAVAILABLE"
                    color: root.cyan
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }
                Text { anchors.bottom: parent.bottom; width: parent.width; text: "O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.rebootPromptVisible
        color: "#B8000000"
        z: 50
        Rectangle {
            anchors.centerIn: parent
            width: 940; height: 420; radius: 32
            color: root.panelColor
            border.width: 2; border.color: root.warning
            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 18
                Text { width: parent.width; text: "RESTART REQUIRED"; color: root.warning; font.pixelSize: 28; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: root.rebootReason; color: root.textSecondary; font.pixelSize: 16; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18
                    Repeater {
                        model: ["LATER", "RESTART SHELL", "REBOOT PI"]
                        Rectangle {
                            width: 240; height: 72; radius: 20
                            color: root.rebootChoice === index ? (index === 2 ? root.danger : root.focusBlue) : root.panelRaised
                            border.width: root.rebootChoice === index ? 2 : 1
                            border.color: root.rebootChoice === index ? "#D9F4FF" : root.divider
                            Text { anchors.centerIn: parent; text: modelData; color: root.rebootChoice === index ? "#04111F" : root.textPrimary; font.pixelSize: 14; font.bold: true }
                        }
                    }
                }
                Text { width: parent.width; text: "LEFT/RIGHT  CHOOSE   X  CONFIRM   O  LATER"; color: root.textMuted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        id: exitOverlay
        anchors.fill: parent
        visible: false
        color: "#C2000000"
        z: 80

        Rectangle {
            anchors.centerIn: parent
            width: 980
            height: 440
            radius: 34
            color: root.panelColor
            border.width: 2
            border.color: root.exitChoice === 2 ? root.danger : (root.exitChoice === 1 ? root.purple : root.success)

            Column {
                anchors.fill: parent
                anchors.margins: 36
                spacing: 24
                Text {
                    width: parent.width
                    text: "EXIT SETTINGS"
                    color: root.textPrimary
                    font.pixelSize: 32
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: settingsBackend && settingsBackend.pendingCount > 0
                          ? "You have " + settingsBackend.pendingCount + " pending change(s). Resume to apply or discard them before leaving."
                          : "Return to the NeutronOS Console?"
                    color: root.textSecondary
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18
                    Repeater {
                        model: [
                            { label: "RESUME", tone: root.success },
                            { label: "LEAVE RUNNING", tone: root.purple },
                            { label: "EXIT", tone: root.danger }
                        ]
                        Rectangle {
                            required property var modelData; required property int index
                            width: 270; height: 92; radius: 28
                            color: root.exitChoice === index ? Qt.rgba(modelData.tone.r, modelData.tone.g, modelData.tone.b, 0.34) : root.panelRaised
                            border.width: root.exitChoice === index ? 3 : 1
                            border.color: modelData.tone
                            Text { anchors.centerIn: parent; text: modelData.label; color: modelData.tone; font.pixelSize: 18; font.bold: true }
                        }
                    }
                }
                Text { width: parent.width; text: "LEFT / RIGHT  CHOOSE     X  CONFIRM     O  RESUME"; color: root.textMuted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Shared.ReferenceExitModal {
        id: referenceExitModal
        appName: "Settings"
        onExitRequested: root.exitRequested()
        onLeaveRunningRequested: root.backgroundRequested()
        onDismissed: { root.exitModalVisible = false; root.forceActiveFocus() }
    }

    Rectangle {
        id: editionOverlay
        anchors.fill: parent
        visible: root.editionModalVisible
        color: "#E602060D"
        z: 81

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 1040)
            height: Math.min(parent.height - 110, 700)
            radius: 30
            color: "#06101F"
            border.width: 0
            clip: true

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 22

                Row {
                    width: parent.width
                    height: 74
                    spacing: 20

                    Column {
                        width: parent.width - 184
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text {
                            width: parent.width
                            text: "NEUTRONOS EDITION"
                            color: root.textPrimary
                            font.pixelSize: 27
                            font.bold: true
                            font.letterSpacing: 1.1
                        }
                        Text {
                            width: parent.width
                            text: "Installed operating-system identity"
                            color: root.textMuted
                            font.pixelSize: 14
                        }
                    }

                    Rectangle {
                        width: 164
                        height: 48
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 12
                        color: "#081522"
                        border.width: 1
                        border.color: root.purple
                        Text {
                            anchors.centerIn: parent
                            text: "GEMINI"
                            color: root.purple
                            font.pixelSize: 14
                            font.bold: true
                            font.letterSpacing: 1.2
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: parent.height - 164
                    spacing: 36

                    Item {
                        width: 380
                        height: parent.height
                        AtomAnimation {
                            anchors.centerIn: parent
                            width: 330
                            height: 330
                            running: root.editionModalVisible
                        }
                    }

                    Column {
                        width: parent.width - 416
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        Text {
                            width: parent.width
                            text: "NeutronOS"
                            color: root.textPrimary
                            font.pixelSize: 48
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "GEMINI"
                            color: root.cyan
                            font.pixelSize: 34
                            font.bold: true
                            font.letterSpacing: 2.0
                        }
                        Text {
                            width: parent.width
                            text: String(settingsBackend && settingsBackend.systemInfo
                                         ? settingsBackend.systemInfo.neutronVersion || "0.5 candidate"
                                         : "0.5 candidate")
                            color: root.textPrimary
                            font.pixelSize: 20
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: "Controller-first Debian Linux distribution built around the NeutronOS shell, local accounts and integrated system services."
                            color: root.textSecondary
                            font.pixelSize: 15
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            spacing: 8
                            Text { text: "SECURE"; color: root.textSecondary; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.0 }
                            Text { text: "|"; color: root.textMuted; font.pixelSize: 13; font.bold: true }
                            Text { text: "INTELLIGENT"; color: root.textSecondary; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.0 }
                            Text { text: "|"; color: root.textMuted; font.pixelSize: 13; font.bold: true }
                            Text { text: "UNSTOPPABLE"; color: root.danger; font.pixelSize: 13; font.bold: true; font.letterSpacing: 1.0 }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "O  CLOSE"
                    color: root.cyan
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.0
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        id: piOverlay
        anchors.fill: parent
        visible: root.piModalVisible
        color: "#C8000000"
        z: 82

        Rectangle {
            anchors.centerIn: parent
            width: 980
            height: 780
            radius: 38
            color: root.panelColor
            border.width: 2
            border.color: "#E83E52"

            Column {
                anchors.fill: parent
                anchors.margins: 36
                spacing: 18
                Text { width: parent.width; text: "RASPBERRY PI"; color: root.textPrimary; font.pixelSize: 34; font.bold: true; horizontalAlignment: Text.AlignHCenter }

                Item {
                    width: 370
                    height: 390
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle { x: 95; y: 40; width: 92; height: 56; radius: 28; rotation: -34; color: "#57A847" }
                    Rectangle { x: 180; y: 35; width: 92; height: 56; radius: 28; rotation: 34; color: "#57A847" }
                    Rectangle { x: 139; y: 15; width: 92; height: 58; radius: 29; color: "#78BE57" }

                    Repeater {
                        model: [
                            {x:112,y:112},{x:184,y:112},{x:76,y:178},{x:148,y:178},{x:220,y:178},
                            {x:94,y:246},{x:166,y:246},{x:202,y:310},{x:130,y:310}
                        ]
                        Rectangle {
                            x: modelData.x
                            y: modelData.y
                            width: 78
                            height: 78
                            radius: 39
                            color: index % 2 === 0 ? "#D52F4A" : "#F0445E"
                            border.width: 3
                            border.color: "#FF8EA0"
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: String(settingsBackend && settingsBackend.systemInfo ? settingsBackend.systemInfo.model || "Raspberry Pi" : "Raspberry Pi")
                    color: root.textPrimary
                    font.pixelSize: 27
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: "Revision " + String(settingsBackend && settingsBackend.systemInfo ? settingsBackend.systemInfo.boardRevision || "Unknown" : "Unknown") +
                          "  •  " + String(settingsBackend && settingsBackend.systemInfo ? settingsBackend.systemInfo.memory || "" : "")
                    color: root.textSecondary
                    font.pixelSize: 15
                    horizontalAlignment: Text.AlignHCenter
                }
                Text { width: parent.width; text: "O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        id: easterEggOverlay
        anchors.fill: parent
        visible: root.easterEggVisible
        color: "#E0000000"
        z: 90

        Item {
            id: atomSprayLayer
            anchors.fill: parent
            clip: true
            visible: root.easterEggVisible

            Repeater {
                model: 30
                delegate: Item {
                    id: sprayAtom
                    property real destinationX: ((index * 193 + 71) % 997) / 997 * Math.max(1, atomSprayLayer.width - width)
                    property real destinationY: ((index * 307 + 43) % 991) / 991 * Math.max(1, atomSprayLayer.height - height)
                    property real originX: atomSprayLayer.width / 2 - width / 2
                    property real originY: atomSprayLayer.height / 2 - height / 2
                    width: 54 + (index % 6) * 14
                    height: width
                    x: originX
                    y: originY
                    opacity: 0
                    scale: 0.2
                    rotation: index * 27

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.72
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: index % 3 === 0 ? root.cyan : (index % 3 === 1 ? "#FF355D" : root.purple)
                        opacity: 0.34
                    }

                    Image {
                        anchors.fill: parent
                        source: root.themeFile("atom.png")
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        cache: true
                    }

                    RotationAnimation on rotation {
                        running: root.easterEggVisible
                        loops: Animation.Infinite
                        from: index * 27
                        to: index % 2 === 0 ? index * 27 + 720 : index * 27 - 720
                        duration: 2600 + (index % 7) * 280
                    }

                    SequentialAnimation {
                        running: root.easterEggVisible
                        loops: Animation.Infinite
                        PauseAnimation { duration: (index % 15) * 105 }
                        ParallelAnimation {
                            NumberAnimation { target: sprayAtom; property: "x"; from: sprayAtom.originX; to: sprayAtom.destinationX; duration: 1700 + (index % 5) * 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sprayAtom; property: "y"; from: sprayAtom.originY; to: sprayAtom.destinationY; duration: 1700 + (index % 5) * 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sprayAtom; property: "scale"; from: 0.18; to: 0.95 + (index % 4) * 0.12; duration: 1450 + (index % 5) * 180; easing.type: Easing.OutBack }
                            SequentialAnimation {
                                NumberAnimation { target: sprayAtom; property: "opacity"; from: 0; to: 0.92; duration: 280 }
                                PauseAnimation { duration: 820 + (index % 6) * 100 }
                                NumberAnimation { target: sprayAtom; property: "opacity"; from: 0.92; to: 0; duration: 540 }
                            }
                        }
                        PauseAnimation { duration: 260 + (index % 4) * 90 }
                    }
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 1160
            height: 900
            radius: 44
            color: root.lightMode ? "#FFFFFF" : "#050914"
            border.width: 3
            border.color: root.purple
            clip: true

            Rectangle {
                anchors.centerIn: parent
                width: 780
                height: 780
                radius: 390
                color: "transparent"
                border.width: 2
                border.color: root.cyan
                opacity: 0.12
                RotationAnimation on rotation { running: root.easterEggVisible; loops: Animation.Infinite; from: 0; to: 360; duration: 7200 }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 8
                AtomAnimation {
                    width: 390
                    height: 390
                    anchors.horizontalCenter: parent.horizontalCenter
                    specialMode: true
                    running: root.easterEggVisible
                }
                Text { width: parent.width; text: "NeutronOS"; color: root.lightMode ? "#071A33" : "#FFFFFF"; font.pixelSize: 58; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "Gemini 0.5 candidate"; color: root.cyan; font.pixelSize: 34; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "Mercury Founders Edition"; color: root.purple; font.pixelSize: 30; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "Date created: 07-04-2026"; color: "#FF5570"; font.pixelSize: 19; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "Developer: DrNeutron"; color: root.warning; font.pixelSize: 21; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "This founder sequence closes automatically after 10 seconds."; color: root.textMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                Text { width: parent.width; text: "O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        id: reportOverlay
        anchors.fill: parent
        visible: root.systemReportVisible
        color: "#C8000000"
        z: 84
        property var reportData: settingsBackend ? settingsBackend.integrityReport : ({})

        Rectangle {
            anchors.centerIn: parent
            width: 1080
            height: 790
            radius: 38
            color: root.panelColor
            border.width: 2
            border.color: settingsBackend && settingsBackend.integrityCheckBusy ? root.focusBlue
                         : reportOverlay.reportData.valid === true ? root.success : root.danger

            Column {
                anchors.fill: parent
                anchors.margins: 34
                spacing: 18
                Text {
                    width: parent.width
                    text: settingsBackend && settingsBackend.integrityCheckBusy ? "VERIFYING SYSTEM INTEGRITY"
                          : String(reportOverlay.reportData.title || "SYSTEM REPORT")
                    color: settingsBackend && settingsBackend.integrityCheckBusy ? root.focusBlue
                         : reportOverlay.reportData.valid === true ? root.success : root.danger
                    font.pixelSize: 31
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: settingsBackend && settingsBackend.integrityCheckBusy
                          ? "Checking CPU, RAM, storage, peripherals and security…"
                          : String(reportOverlay.reportData.summary || "Waiting for the backend integrity report.")
                    color: root.textSecondary
                    font.pixelSize: 15
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle { width: parent.width; height: 1; color: root.divider }
                Column {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: reportOverlay.reportData && reportOverlay.reportData.checks ? reportOverlay.reportData.checks : []
                        Rectangle {
                            width: parent.width
                            height: 82
                            radius: 18
                            color: root.panelRaised
                            border.width: 1
                            border.color: modelData.ok === true ? root.success : root.danger
                            Row {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 18
                                Text { width: 190; anchors.verticalCenter: parent.verticalCenter; text: String(modelData.name || "Check"); color: root.textPrimary; font.pixelSize: 18; font.bold: true }
                                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: String(modelData.status || ""); color: modelData.ok === true ? root.success : root.danger; font.pixelSize: 16; font.bold: true }
                                Text { width: parent.width - 316; anchors.verticalCenter: parent.verticalCenter; text: String(modelData.detail || ""); color: root.textSecondary; font.pixelSize: 13; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                }
                Item { width: 1; height: 4 }
                Text { width: parent.width; text: "X  RUN AGAIN     O  CLOSE"; color: root.focusBlue; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    Rectangle {
        id: buttonTestOverlay
        anchors.fill: parent
        visible: root.buttonTestVisible
        color: "#D0000000"
        z: 86

        Rectangle {
            anchors.centerIn: parent
            width: 1480
            height: 880
            radius: 38
            color: root.panelColor
            border.width: 2
            border.color: root.buttonTestFinished ? (root.buttonTestReceivedTotal === buttonTestModel.count ? root.success : root.warning) : root.focusBlue

            Column {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 16
                Text { width: parent.width; text: "CONTROLLER BUTTON TEST"; color: root.textPrimary; font.pixelSize: 31; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                Text {
                    width: parent.width
                    text: root.buttonTestFinished
                          ? root.buttonTestReceivedTotal + " of " + buttonTestModel.count + " inputs received"
                          : "Press every button, trigger, stick and touchpad control"
                    color: root.buttonTestFinished && root.buttonTestReceivedTotal === buttonTestModel.count ? root.success : root.textSecondary
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: parent.width
                    height: 14
                    radius: 7
                    color: root.panelInset
                    Rectangle {
                        height: parent.height
                        width: parent.width * (buttonTestModel.count > 0 ? root.buttonTestReceivedTotal / buttonTestModel.count : 0)
                        radius: 7
                        color: root.buttonTestReceivedTotal === buttonTestModel.count ? root.success : root.focusBlue
                    }
                }
                GridView {
                    id: buttonGrid
                    width: parent.width
                    height: 620
                    model: buttonTestModel
                    cellWidth: width / 4
                    cellHeight: 112
                    interactive: false
                    clip: true
                    delegate: Rectangle {
                        width: buttonGrid.cellWidth - 12
                        height: buttonGrid.cellHeight - 12
                        radius: 20
                        color: received === true ? (root.lightMode ? "#DDF8EA" : "#0B3A28")
                              : missed === true ? (root.lightMode ? "#FFE3E8" : "#45141D")
                                                : root.panelRaised
                        border.width: 2
                        border.color: received === true ? root.success : missed === true ? root.danger : root.divider
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: received === true ? "✓" : missed === true ? "×" : "○"; color: received === true ? root.success : missed === true ? root.danger : root.textMuted; font.pixelSize: 25; font.bold: true }
                            Text { width: buttonGrid.cellWidth - 30; text: label; color: root.textPrimary; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: received === true ? "RECEIVED" : missed === true ? "MISSED" : "WAITING"; color: received === true ? root.success : missed === true ? root.danger : root.textMuted; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.0 }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: root.buttonTestFinished ? "O  CLOSE     X  RETEST" : "PRESS OPTIONS TWICE TO FINISH EARLY • TEST COMPLETES AUTOMATICALLY"
                    color: root.focusBlue
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    AppManagerModal {
        id: installedAppsModal
        appBackend: root.appBackend
        securityBackend: root.securityBackend
        activeUsername: root.activeUsernameValue()
        automaticLoginEnabled: root.settingValue("user.autoLogin", false) === true
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        panelInset: root.panelInset
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        cyan: root.cyan
        success: root.success
        warning: root.warning
        danger: root.danger
        onCloseRequested: root.forceActiveFocus()
        onLaunchRequested: function(appData) { root.launchAppRequested(appData) }
    }

    AutoLoginWarningModal {
        id: autoLoginWarningModal
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        warning: root.warning
        danger: root.danger
        onEnableConfirmed: {
            if (root.settingsBackend)
                root.settingsBackend.queueChange("user.autoLogin", true, "reboot")
            root.statusMessage = "Automatic Login is pending. High-priority actions will require the login password."
            root.statusError = false
            root.refreshPage()
            root.forceActiveFocus()
        }
        onCancelled: root.forceActiveFocus()
    }

    BackupRestorePointsModal {
        id: backupRestorePointsModal
        backend: root.backupRestoreBackend
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        success: root.success
        warning: root.warning
        danger: root.danger
        onCloseRequested: root.forceActiveFocus()
    }

    UpdateInstallConfirmationModal {
        id: updateInstallConfirmationModal
        panelColor: root.panelColor
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        focusBlue: root.focusBlue
        warning: root.warning
        onConfirmed: {
            var started = root.updateRecoveryBackend && root.updateRecoveryBackend.installDownloadedUpdate()
            root.statusMessage = String(root.updateRecoveryBackend ? root.updateRecoveryBackend.lastMessage : "Update backend unavailable.")
            root.statusError = !started
            root.refreshPage()
            root.forceActiveFocus()
        }
        onCloseRequested: root.forceActiveFocus()
    }

    UpdateRecoveryTextModal {
        id: updateRecoveryTextModal
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        onCloseRequested: root.forceActiveFocus()
    }

    SecurityPrivacyModal {
        id: securityPrivacyModal
        coreBackend: root.coreBackend
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        panelInset: root.panelInset
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        success: root.success
        warning: root.warning
        danger: root.danger
        purple: root.purple
        onStatusChanged: function(message, error) {
            root.statusMessage = message
            root.statusError = error
        }
        onOpenSecurityAppRequested: {
            securityPrivacyModal.closeModal()
            root.launchApp("security")
        }
        onCloseRequested: root.forceActiveFocus()
    }

    HotspotManagerModal {
        id: hotspotManagerModal
        anchors.fill: parent
        visible: visibleMode && !root.keyboardOpen
        enabled: visible
        z: 190
        networkBackend: root.networkBackend
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        panelInset: root.panelInset
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        cyan: root.cyan
        success: root.success
        warning: root.warning
        danger: root.danger
        onKeyboardRequested: function(target, initialValue, title) { root.openKeyboard(target, initialValue, title) }
        onStatusChanged: function(message, error) { root.statusMessage = message; root.statusError = error }
        onClosed: { root.refreshPage(); root.forceActiveFocus() }
    }

    BluetoothManagerModal {
        id: bluetoothManagerModal
        anchors.fill: parent
        visible: visibleMode
        enabled: visible
        z: 190
        coreBackend: root.coreBackend
        panelColor: root.panelColor
        panelRaised: root.panelRaised
        panelInset: root.panelInset
        textPrimary: root.textPrimary
        textSecondary: root.textSecondary
        textMuted: root.textMuted
        divider: root.divider
        focusBlue: root.focusBlue
        cyan: root.cyan
        success: root.success
        warning: root.warning
        danger: root.danger
        onStatusChanged: function(message, error) { root.statusMessage = message; root.statusError = error }
        onClosed: { root.refreshPage(); root.forceActiveFocus() }
    }

    Modals.DiagnosticsCenter {
        id: diagnosticsCenter
        anchors.fill: parent
        backend: root.diagnosticsBackend
        z: 20000
        onClosed: root.forceActiveFocus()
    }

    SettingsPhase1Modal {
        id: phase1SettingsModal
        anchors.fill: parent
        visible: visibleMode && (!root.keyboardOpen || mode === "addUser")
        enabled: visible
        z: 90
        activeUsername: root.activeUsernameValue()
        recoveryConfigured: root.securityCoreBackend ? root.securityCoreBackend.recoveryConfigured === true : false
        recoveryMethod: root.securityCoreBackend ? String(root.securityCoreBackend.recoveryMethod || "none") : "none"
        loginComboConfigured: root.securityBackend ? root.securityBackend.loginComboConfigured === true : true
        minimumComboLength: root.securityBackend ? Number(root.securityBackend.minimumComboLength || 4) : 4
        maximumComboLength: root.securityBackend ? Number(root.securityBackend.maximumComboLength || 15) : 15
        maximumRollingInputs: 15
        recoveryUsbPresent: root.securityCoreBackend && root.securityCoreBackend.recoveryUsbCandidates
                            ? root.securityCoreBackend.recoveryUsbCandidates.length > 0 : false

        onKeyboardRequested: function(target, initialValue, title) {
            root.openKeyboard(target, initialValue, title)
        }
        onCreateUserRequested: function(username, displayName, password, administrator) {
            if (!root.settingsBackend) {
                phase1SettingsModal.setUserCreateResult(false, "Settings backend is unavailable.")
                return
            }
            var ok = root.settingsBackend.createUser(username, displayName, password, administrator)
            var message = String(root.settingsBackend.lastMessage || (ok ? "User account created." : "User account could not be created."))
            phase1SettingsModal.setUserCreateResult(ok, message)
            root.statusMessage = message
            root.statusError = !ok
            if (ok && root.userBackend && typeof root.userBackend.refreshUsers === "function")
                root.userBackend.refreshUsers()
            root.refreshPage()
        }
        onComboVerificationRequested: function(combo) {
            if (!root.securityBackend) {
                phase1SettingsModal.comboVerificationResult(false, "Security backend is unavailable.")
                return
            }
            var started = root.securityBackend.beginLoginComboVerification(root.activeUsernameValue(), combo)
            if (!started)
                phase1SettingsModal.comboVerificationResult(false, String(root.securityBackend.lastError || "Current controller passcode could not be verified."))
        }
        onComboCreationRequested: function(newCombo, confirmation) {
            if (!root.securityBackend) {
                phase1SettingsModal.comboCreationResult(false, "Security backend is unavailable.")
                return
            }
            var started = root.securityBackend.beginLoginComboCreation(root.activeUsernameValue(),
                                                                       newCombo,
                                                                       confirmation)
            if (!started)
                phase1SettingsModal.comboCreationResult(false, String(root.securityBackend.lastError || "Controller passcode creation could not be started."))
        }
        onComboChangeRequested: function(currentCombo, newCombo, confirmation, recovery) {
            if (!root.securityBackend) {
                phase1SettingsModal.comboChangeResult(false, "Security backend is unavailable.")
                return
            }
            var started = root.securityBackend.beginLoginComboChange(root.activeUsernameValue(),
                                                                     recovery ? "" : currentCombo,
                                                                     newCombo,
                                                                     confirmation)
            if (!started)
                phase1SettingsModal.comboChangeResult(false, String(root.securityBackend.lastError || "Controller passcode change could not be started."))
        }
        onUsbRecoveryRequested: {
            if (!root.securityCoreBackend) {
                phase1SettingsModal.recoveryVerificationResult(false, "Recovery backend is unavailable.")
                return
            }
            root.phase1RecoveryPending = true
            var started = root.securityCoreBackend.verifyUsbRecovery()
            if (!started) {
                root.phase1RecoveryPending = false
                phase1SettingsModal.recoveryVerificationResult(false, "Recovery-drive verification could not be started.")
            }
        }
        onClosed: {
            root.phase1RecoveryPending = false
            root.forceActiveFocus()
        }
    }

    UserProfileSettingsModal {
        id: userProfileSettingsModal
        anchors.fill: parent
        visible: false
        z: 185
        activeUser: root.userBackend ? root.userBackend.activeUser : root.activeUser
        profileOnly: true
        onActionRequested: function(action, payload) {
            if (action === "personalization") {
                userProfileSettingsModal.closeModal()
                personalizationModal.open(payload || { "username": root.activeUsernameValue(), "tab": 0 })
            }
        }
        onClosed: {
            root.refreshPage()
            root.forceActiveFocus()
        }
    }

    PersonalizationModal {
        id: personalizationModal
        anchors.fill: parent
        z: 180
        onClosed: {
            root.refreshPage()
            root.forceActiveFocus()
        }
    }

    Rectangle {
        id: settingsKeyboardOverlay
        anchors.fill: parent
        visible: root.keyboardOpen
        enabled: visible
        color: "#E602060D"
        z: 100

        Rectangle {
            id: settingsKeyboardShell
            anchors.centerIn: parent
            width: Math.min(parent.width - 100, 1540)
            height: 516
            radius: 24
            color: root.chromeColor
            border.width: 1
            border.color: root.divider
            clip: true

            Rectangle {
                id: settingsKeyboardField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 14
                height: 102
                radius: 16
                color: root.panelInset
                border.width: 2
                border.color: root.focusBlue

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    anchors.topMargin: 14
                    anchors.bottomMargin: 12
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.keyboardTitle().toUpperCase()
                        color: root.focusBlue
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 1.1
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.keyboardDisplayValue()
                        color: root.keyboardBuffer.length > 0 ? root.textPrimary : root.textMuted
                        font.pixelSize: 25
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                id: settingsKeyboardViewport
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 14
                height: 376
                clip: true

                Shared.VirtualKeyboard {
                    id: virtualKeyboard
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 432
                    visibleMode: root.keyboardOpen
                    visible: visibleMode
                    enabled: visibleMode
                    active: visibleMode
                    title: ""
                    largeMode: true
                    cancelBehavior: "close"

                    onKeyPressed: function(value) {
                        root.keyboardBuffer += value
                        if (phase1SettingsModal.visibleMode)
                            phase1SettingsModal.updateKeyboardPreview(root.keyboardTarget, root.keyboardBuffer)
                    }
                    onBackspacePressed: {
                        if (root.keyboardBuffer.length > 0)
                            root.keyboardBuffer = root.keyboardBuffer.substring(0, root.keyboardBuffer.length - 1)
                        if (phase1SettingsModal.visibleMode)
                            phase1SettingsModal.updateKeyboardPreview(root.keyboardTarget, root.keyboardBuffer)
                    }
                    onEnterPressed: root.commitKeyboard()
                    onClosePressed: root.closeKeyboard()
                }

                // The viewport begins at the key deck, cropping the shared
                // keyboard's standalone title strip without changing the
                // global keyboard component used by other apps.
            }
        }
    }

    Connections {
        target: settingsBackend
        ignoreUnknownSignals: true
        function onThemeChanged() { root.refreshPage() }
        function onValuesChanged() { root.refreshPage() }
        function onDeveloperModeChanged() { root.refreshPage() }
        function onIntegrityReportChanged() { if (root.systemReportVisible) root.forceActiveFocus() }
        function onStorageUsageChanged() { if (root.currentCategoryId() === "storage") root.refreshPage() }
        function onOperationChanged() {
            root.statusMessage = settingsBackend.lastMessage || settingsBackend.operationStatus || ""
            root.statusError = false
        }
        function onOperationFinished(action, success, message) {
            root.statusMessage = message
            root.statusError = !success
        }
        function onRebootRequired(reason) {
            root.rebootReason = reason
            root.rebootChoice = 0
            root.rebootPromptVisible = true
        }
    }

    Connections {
        target: securityBackend
        ignoreUnknownSignals: true
        function onLoginComboVerificationFinished(success, message, failedAttempts, secondsRemaining) {
            if (phase1SettingsModal.visibleMode && phase1SettingsModal.mode === "combo" &&
                    phase1SettingsModal.comboStage === 1 && phase1SettingsModal.comboBusy) {
                phase1SettingsModal.comboVerificationResult(success, message)
            }
        }
        function onLoginComboCreationFinished(success, message) {
            if (phase1SettingsModal.visibleMode && phase1SettingsModal.mode === "combo" &&
                    phase1SettingsModal.comboBusy && phase1SettingsModal.initialComboCreation) {
                phase1SettingsModal.comboCreationResult(success, message)
                root.statusMessage = String(message || (success ? "Controller passcode created." : "Controller passcode was not created."))
                root.statusError = !success
                root.refreshPage()
            }
        }
        function onLoginComboChangeFinished(success, message) {
            if (phase1SettingsModal.visibleMode && phase1SettingsModal.mode === "combo" &&
                    phase1SettingsModal.comboBusy) {
                phase1SettingsModal.comboChangeResult(success, message)
                root.statusMessage = String(message || (success ? "Controller passcode replaced." : "Controller passcode was not changed."))
                root.statusError = !success
            }
        }
    }

    Connections {
        target: securityCoreBackend
        ignoreUnknownSignals: true
        function onOperationFinished(success, message) {
            if (!root.phase1RecoveryPending)
                return
            root.phase1RecoveryPending = false
            if (phase1SettingsModal.visibleMode && phase1SettingsModal.mode === "combo")
                phase1SettingsModal.recoveryVerificationResult(success, message)
        }
    }

    Connections {
        target: updateRecoveryBackend
        ignoreUnknownSignals: true
        function onInstallCandidateReady(version, size, releaseNotes) {
            updateInstallConfirmationModal.openModal(version, size, releaseNotes)
        }
        function onStateChanged() {
            if (root.currentCategoryId() === "update-recovery")
                root.refreshPage()
        }
        function onHistoryChanged() {
            if (root.currentCategoryId() === "update-recovery")
                root.refreshPage()
        }
        function onIntegrityChanged() {
            if (root.currentCategoryId() === "update-recovery")
                root.refreshPage()
        }
        function onRecoveryChanged() {
            if (root.currentCategoryId() === "update-recovery")
                root.refreshPage()
        }
        function onOperationFinished(operation, success, message) {
            root.statusMessage = String(message || operation || "Update operation finished.")
            root.statusError = !success
            if (root.currentCategoryId() === "update-recovery")
                root.refreshPage()
        }
        function onRestartScheduled(reason) {
            root.statusMessage = String(reason || "System operation scheduled.") + " NeutronOS may restart automatically."
            root.statusError = false
        }
    }

    Connections {
        target: backupRestoreBackend
        ignoreUnknownSignals: true
        function onStateChanged() {
            if (root.currentCategoryId() === "backup-restore")
                root.refreshPage()
        }
        function onBackupsChanged() {
            if (root.currentCategoryId() === "backup-restore")
                root.refreshPage()
            if (updateRecoveryTextModal.visibleMode &&
                    updateRecoveryTextModal.modalTitle === "BACKUP ARCHIVES") {
                updateRecoveryTextModal.modalSubtitle = String(backupRestoreBackend.backupCount || 0) + " STORED BACKUP(S)"
                updateRecoveryTextModal.modalBody = String(backupRestoreBackend.backupDetailsText())
            }
        }
        function onHistoryChanged() {
            if (root.currentCategoryId() === "backup-restore")
                root.refreshPage()
        }
        function onOperationFinished(operation, success, message) {
            root.statusMessage = String(message || operation || "Backup operation finished.")
            root.statusError = !success
            if (root.currentCategoryId() === "backup-restore")
                root.refreshPage()
        }
        function onRestartScheduled(reason) {
            root.statusMessage = String(reason || "Backup/restore system operation scheduled.")
            root.statusError = false
        }
    }

    Connections {
        target: controllerBackend
        ignoreUnknownSignals: true
        function onButtonPressed(button) { if (root.buttonTestVisible) root.markButtonTest(button) }
        function onActionPressed(action) { if (root.buttonTestVisible) root.markButtonTest(action) }
        function onStickMoved(stick, x, y) { if (root.buttonTestVisible) root.markStickTest(stick, x, y) }
        function onControllerInputProfileChanged() { if (root.currentCategoryId() === "controllers") root.refreshPage() }
        function onControllerBatteryChanged() { if (root.currentCategoryId() === "controllers" || root.currentCategoryId() === "diagnostics") root.refreshPage() }
        function onControllerIdentityChanged() { if (root.currentCategoryId() === "controllers" || root.currentCategoryId() === "diagnostics") root.refreshPage() }
    }

    Connections {
        target: networkBackend
        ignoreUnknownSignals: true
        function onOfflineNetworkStateChanged() {
            if (root.currentCategoryId() === "network") root.refreshPage()
            if (hotspotManagerModal.visibleMode) hotspotManagerModal.syncFromState()
        }
        function onOfflineNetworkOperationFinished(success, message) {
            root.statusMessage = String(message || (success ? "Network operation completed." : "Network operation failed."))
            root.statusError = !success
            if (hotspotManagerModal.visibleMode) hotspotManagerModal.syncFromState()
        }
    }

    Connections {
        target: coreBackend
        ignoreUnknownSignals: true
        function onChanged() {
            if (root.currentCategoryId() === "bluetooth") root.refreshPage()
        }
    }

    Connections {
        target: diagnosticsBackend
        ignoreUnknownSignals: true
        function onDiagnosticsChanged() { if (root.currentCategoryId() === "diagnostics") root.refreshPage() }
        function onBusyChanged() { if (root.currentCategoryId() === "diagnostics") root.refreshPage() }
        function onBundleChanged() { if (root.currentCategoryId() === "diagnostics") root.refreshPage() }
        function onLastMessageChanged() { root.statusMessage = String(diagnosticsBackend.lastMessage || ""); root.statusError = false }
    }

    Connections {
        target: developerBackend
        ignoreUnknownSignals: true
        function onDeveloperModeChanged() { root.refreshPage() }
    }

    onSidebarIndexChanged: Qt.callLater(refreshPage)
    onSearchActiveChanged: Qt.callLater(refreshPage)

    Component.onCompleted: {
        if (settingsBackend)
            settingsBackend.refresh()
        if (updateRecoveryBackend)
            updateRecoveryBackend.refresh()
        if (backupRestoreBackend)
            backupRestoreBackend.refresh()
        Qt.callLater(refreshPage)
        forceActiveFocus()
    }

    Component.onDestruction: {
        if (securityBackend && typeof securityBackend.clearHighPriorityAuthorization === "function")
            securityBackend.clearHighPriorityAuthorization()
    }

    function userDisplayName() {
        try {
            if (userBackend && String(userBackend.displayName || "").trim().length > 0)
                return String(userBackend.displayName)
        } catch (error) {}
        return "User"
    }

    function activeUsernameValue() {
        try {
            if (securityBackend && String(securityBackend.activeUsername || "").length > 0)
                return String(securityBackend.activeUsername)
            if (userBackend && String(userBackend.username || "").length > 0)
                return String(userBackend.username)
            if (activeUser && String(activeUser.username || activeUser.name || "").length > 0)
                return String(activeUser.username || activeUser.name)
        } catch (error) {}
        return "neutronos"
    }

    function themeFile(path) {
        try {
            if (assetBackend && typeof assetBackend.themeFile === "function")
                return String(assetBackend.themeFile(path) || "")
        } catch (error) {}
        return ""
    }

    function userAvatar() {
        var source = ""
        try { source = userBackend ? String(userBackend.avatarSource || userBackend.avatar || userBackend.icon || "") : "" } catch (error) {}
        if (source.length === 0)
            source = "users/user_icon.png"
        if (source.indexOf("file:") === 0 || source.indexOf("qrc:") === 0 || source.indexOf("image:") === 0 || source.indexOf("http://") === 0 || source.indexOf("https://") === 0)
            return source
        try {
            if (userBackend && typeof userBackend.resolveAvatarSource === "function") {
                var resolved = userBackend.resolveAvatarSource(source)
                if (resolved && String(resolved).length > 0)
                    return String(resolved)
            }
        } catch (error2) {}
        if (source.indexOf("/") < 0)
            source = "users/" + source
        return themeFile(source)
    }

    function categoryLocked(id) {
        // Patch 60K: all four formerly gated pages render for every user.
        // Developer restrictions will be reintroduced only after field testing.
        return false
    }

    function currentCategoryId() {
        return categories[Math.max(0, Math.min(categories.length - 1, sidebarIndex))].id
    }

    function categoryDescription(id) {
        var descriptions = {
            user: "Profile, accounts, password and authentication",
            system: "Device identity, startup behavior, accounts and updates",
            display: "Resolution, HDMI, remote display and graphics memory",
            interfaces: "Hardware buses, camera and remote-access services",
            network: "Wi-Fi, Ethernet, Bluetooth, proxy and diagnostics",
            controllers: "Controller identity, input profiles, calibration, feedback, testing and pairing",
            audio: "Output device, volume, input and interface sounds",
            appearance: "Theme, wallpaper, fonts, scaling and screensaver",
            localization: "Language, timezone, keyboard and regional formats",
            accessibility: "Vision, motion, audio and input assistance",
            apps: "Installed applications, services, defaults and permissions",
            storage: "iOS-style categorized usage for every mounted storage device",
            security: "Authentication, remote access, privacy and security status",
            "update-recovery": "Signed NeutronOS updates, Debian packages, integrity verification, recovery points and rollback",
            "backup-restore": "Verified backups, restore points, secure data reset and clean NeutronOS reinstall",
            notifications: "System alerts, sounds, haptics and Do Not Disturb",
            power: "Power modes, cooling, timeouts and maintenance schedules",
            performance: "CPU, memory, thermal and power-profile controls",
            advanced: "Boot configuration, diagnostics, logs and recovery",
            diagnostics: "Real hardware, service, storage and network checks with exportable support bundles",
            help: "Controller-first guides for Console, apps, security, storage, networking and recovery",
            about: "NeutronOS, Debian, Qt and Raspberry Pi information"
        }
        return descriptions[id] || "NeutronOS settings"
    }

    function settingValue(key, fallbackValue) {
        if (!settingsBackend || !key || key.length === 0)
            return fallbackValue
        try { return settingsBackend.value(key, fallbackValue) } catch (error) { return fallbackValue }
    }

    function neutronOSBootEnabled() {
        if (!coreBackend)
            return false
        var services = []
        try { services = coreBackend.services || [] } catch (error) { services = [] }
        for (var i = 0; i < services.length; ++i) {
            var item = services[i] || ({})
            var unit = String(item.unit || item.path || "").toLowerCase()
            if (unit !== "neutronos.service" && unit.indexOf("/neutronos.service") < 0)
                continue
            var state = String(item.state || "").toLowerCase()
            var startup = String(item.startup || "").toLowerCase()
            if (state === "active" || state === "running" || state === "activating" ||
                    startup === "enabled" || startup === "enabled-runtime")
                return true
        }
        return false
    }

    function bootDestinationValue() {
        if (neutronOSBootEnabled())
            return "neutronos"
        var configured = String(settingValue("system.bootTarget", "neutronos") || "neutronos").toLowerCase()
        if (configured === "console" || configured === "commandline" || configured === "command-line" ||
                configured === "multi-user.target")
            return "cli"
        if (configured === "graphical.target")
            return "desktop"
        if (configured !== "desktop" && configured !== "cli")
            return "neutronos"
        return configured
    }

    function rowCurrentValue(row) {
        if (!row || !row.key)
            return row ? row.value : ""
        if (row.key === "system.bootTarget")
            return bootDestinationValue()
        if (row.key === "update.channel" && updateRecoveryBackend)
            return String(updateRecoveryBackend.channel || "stable")
        if (row.key === "backup.profile" && backupRestoreBackend)
            return String(backupRestoreBackend.profile || "full")
        if (row.key === "backup.includeRoms" && backupRestoreBackend)
            return backupRestoreBackend.includeRoms === true
        if (row.key === "backup.preserveUserData" && backupRestoreBackend)
            return backupRestoreBackend.preserveUserData === true
        if (row.key === "controller.inputProfile" && controllerBackend)
            return String(controllerBackend.inputProfile || "balanced")
        if (row.key === "controller.deadzone" && controllerBackend)
            return Number(controllerBackend.stickDeadZonePercent || 0)
        if (row.key === "controller.triggerThreshold" && controllerBackend)
            return Number(controllerBackend.triggerThresholdPercent || 0)
        if (row.key === "dashboard.defaultTab" && dashboardLayoutBackend)
            return String(dashboardLayoutBackend.defaultTab || "system")
        if (row.key === "dashboard.homeTab" && dashboardLayoutBackend)
            return String(dashboardLayoutBackend.homeTab || "system")
        if (row.key === "dashboard.legacyAvailable" && dashboardLayoutBackend)
            return dashboardLayoutBackend.legacyAvailable === true
        return settingValue(row.key, row.value)
    }

    function rowValueText(row) {
        if (!row)
            return ""
        if (row.locked === true)
            return "DEVELOPER MODE"
        if (row.kind === "toggle")
            return rowCurrentValue(row) === true ? "ON" : "OFF"
        if (row.kind === "action" || row.kind === "link" || row.kind === "edit" || row.kind === "special")
            return row.valueText || "X  OPEN"
        if (row.kind === "slider")
            return String(rowCurrentValue(row)) + String(row.suffix || "")
        if (row.kind === "choice") {
            var value = String(rowCurrentValue(row))
            if (row.key === "system.bootTarget") {
                if (value === "neutronos") return "NEUTRONOS"
                if (value === "cli") return "COMMAND LINE"
                if (value === "desktop") return "DESKTOP"
            }
            return value.toUpperCase()
        }
        return row.valueText !== undefined ? String(row.valueText) : String(rowCurrentValue(row) || "")
    }

    function dashboardTabOptions() {
        var result = []
        var tabs = dashboardLayoutBackend && dashboardLayoutBackend.availableTabs
                ? dashboardLayoutBackend.availableTabs : []
        for (var index = 0; index < tabs.length; ++index)
            result.push(String(tabs[index].id))
        return result.length ? result : ["desktop", "system", "security", "storage", "apps"]
    }

    // Patch 60B: every ListModel row begins with the same complete role
    // schema. Qt 6 otherwise inferred an incomplete schema when a page began
    // with a warning row, leaving Update & Recovery, Backup & Restore,
    // Performance and Advanced visually empty.
    function baseRow(kind, title, detail) {
        return {
            kind: String(kind || "info"),
            title: String(title || ""),
            detail: String(detail || ""),
            valueText: "",
            selectable: false,
            key: "",
            action: "",
            appId: "",
            target: "",
            value: "",
            options: [],
            applyMode: "apply",
            danger: false,
            locked: false,
            minimum: 0,
            maximum: 100,
            step: 1,
            suffix: "",
            deviceData: ({})
        }
    }

    function normalizedPageEntry(sourceRow) {
        var source = sourceRow || ({})
        var row = baseRow(source.kind, source.title, source.detail)
        row.valueText = source.valueText !== undefined ? String(source.valueText) : ""
        row.selectable = source.selectable === true
        row.key = source.key !== undefined ? String(source.key) : ""
        row.action = source.action !== undefined ? String(source.action) : ""
        row.appId = source.appId !== undefined ? String(source.appId) : ""
        row.target = source.target !== undefined ? String(source.target) : ""
        row.value = source.value !== undefined ? source.value : ""
        row.options = source.options || []
        row.applyMode = source.applyMode !== undefined ? String(source.applyMode) : "apply"
        row.danger = source.danger === true
        row.locked = source.locked === true
        row.minimum = source.minimum !== undefined ? Number(source.minimum) : 0
        row.maximum = source.maximum !== undefined ? Number(source.maximum) : 100
        row.step = source.step !== undefined ? Number(source.step) : 1
        row.suffix = source.suffix !== undefined ? String(source.suffix) : ""
        row.deviceData = source.deviceData || ({})
        return row
    }

    function section(title) {
        return baseRow("section", title, "")
    }
    function info(title, detail, valueText) {
        var row = baseRow("info", title, detail)
        row.valueText = valueText !== undefined ? String(valueText) : ""
        row.selectable = true
        return row
    }
    function special(actionId, title, detail, valueText) {
        var row = baseRow("special", title, detail)
        row.action = String(actionId || "")
        row.valueText = valueText !== undefined ? String(valueText) : "X  OPEN"
        row.selectable = true
        return row
    }
    function toggle(key, title, detail, fallback, mode) {
        var row = baseRow("toggle", title, detail)
        row.key = String(key || "")
        row.value = fallback
        row.applyMode = String(mode || "apply")
        row.selectable = true
        return row
    }
    function choice(key, title, detail, fallback, options, mode) {
        var row = baseRow("choice", title, detail)
        row.key = String(key || "")
        row.value = fallback
        row.options = options || []
        row.applyMode = String(mode || "apply")
        row.selectable = true
        return row
    }
    function slider(key, title, detail, fallback, minimum, maximum, step, suffix, mode) {
        var row = baseRow("slider", title, detail)
        row.key = String(key || "")
        row.value = fallback
        row.minimum = Number(minimum)
        row.maximum = Number(maximum)
        row.step = Number(step)
        row.suffix = String(suffix || "")
        row.applyMode = String(mode || "apply")
        row.selectable = true
        return row
    }
    function action(actionId, title, detail, valueText, danger, locked) {
        var row = baseRow("action", title, detail)
        row.action = String(actionId || "")
        row.valueText = valueText !== undefined ? String(valueText) : "X  RUN"
        row.danger = danger === true
        row.locked = locked === true
        row.selectable = true
        return row
    }
    function edit(target, key, title, detail, valueText, mode) {
        var row = baseRow("edit", title, detail)
        row.target = String(target || "")
        row.key = String(key || "")
        row.valueText = valueText !== undefined ? String(valueText) : "X  EDIT"
        row.applyMode = String(mode || "apply")
        row.selectable = true
        return row
    }
    function link(appId, title, detail) {
        var row = baseRow("link", title, detail)
        row.appId = String(appId || "")
        row.valueText = "X  OPEN"
        row.selectable = true
        return row
    }
    function warning(title, detail) {
        var row = baseRow("warning", title, detail)
        row.valueText = "X  DETAILS"
        row.selectable = true
        return row
    }

    function stableCriticalRows(id) {
        if (id === "update-recovery") {
            var updateStatus = updateRecoveryBackend ? String(updateRecoveryBackend.status || "Ready") : "Backend unavailable"
            var updateDetail = updateRecoveryBackend ? String(updateRecoveryBackend.lastMessage || updateRecoveryBackend.status || "Ready") : "Update & Recovery backend is unavailable."
            var updateChannel = updateRecoveryBackend ? String(updateRecoveryBackend.channel || "stable") : String(settingValue("update.channel", "stable"))
            return [
                section("Signed Update Service"),
                info("Update Status", updateDetail, updateStatus.toUpperCase()),
                choice("update.channel", "Release Channel", "Choose Alpha, Beta, Stable, or Developer packages", updateChannel, ["alpha","beta","stable","developer"], "immediate"),
                action("update-check", "Check for Updates", "Refresh the signed NeutronOS and Debian package catalogs", "X  CHECK"),
                action("update-install", "Install Available Update", "Verify signatures, create a recovery point, then install", "X  INSTALL", true),
                section("Recovery"),
                action("update-history", "Update History", "Review installed releases and verification results", "X  OPEN"),
                info("Recovery Restore", "Verified recovery points are restored from the one-shot authenticated Recovery environment.", "RECOVERY BOOT"),
                info("Installation Repair", "No compiler-based repair is exposed on production installations. Install an authenticated prebuilt package through Update & Recovery.", "SIGNED PACKAGE REQUIRED"),
                action("update-safe-mode", "Start Safe Mode", "Boot NeutronOS with optional services and custom apps disabled", "X  ENABLE", true),
                action("update-cancel-safe-mode", "Cancel Safe Mode", "Return the next boot to the normal shell", "X  CANCEL"),
                section("Repository"),
                edit("updateManifestUrl", "update.manifestUrl", "Manifest URL", "Signed NeutronOS repository manifest", updateRecoveryBackend ? String(updateRecoveryBackend.manifestUrl || "") : "", "immediate"),
                action("validate-boot", "Validate Boot Files", "Check service, executable, QML and boot configuration integrity", "X  VALIDATE")
            ]
        }
        if (id === "backup-restore") {
            var destination = backupRestoreBackend ? String(backupRestoreBackend.destinationPath || "") : String(settingValue("backup.destination", ""))
            var backupStatus = backupRestoreBackend ? String(backupRestoreBackend.status || "Ready") : "Backend unavailable"
            return [
                section("Backup"),
                info("Backup Status", "Current backup and restore state", backupStatus.toUpperCase()),
                edit("backupDestination", "backup.destination", "Backup Destination", "Choose a mounted drive or protected local folder", destination, "immediate"),
                choice("backup.profile", "Backup Profile", "System, user data, apps, or complete image", String(settingValue("backup.profile", "complete")), ["system","user","apps","complete"], "immediate"),
                toggle("backup.includeRoms", "Include Game ROMs", "Include configured game-library files", false, "immediate"),
                action("backup-create", "Create Verified Backup", "Create a checksummed archive using the selected profile", "X  CREATE"),
                action("backup-verify", "Verify Existing Backups", "Recheck archive manifests and checksums", "X  VERIFY"),
                section("Restore"),
                action("backup-list", "Browse Restore Points", "Review available verified archives", "X  OPEN"),
                info("Backup Restore", "Full backup restoration is available only through the authenticated Recovery environment; the production shell does not rebuild source.", "RECOVERY BOOT"),
                action("backup-delete", "Delete Backup", "Remove a selected archive after confirmation", "X  DELETE", true),
                section("Reset & Reinstall"),
                toggle("backup.preserveUserData", "Preserve User Data", "Keep user media during a clean NeutronOS reinstall", true, "immediate"),
                action("backup-wipe-data", "Secure Data Reset", "Securely remove NeutronOS user state and personal configuration", "X  RESET", true),
                info("Clean NeutronOS Reinstall", "Requires an authenticated complete full-system Recovery package. Overlay updates are not eligible.", "FULL-SYSTEM PACKAGE REQUIRED")
            ]
        }
        if (id === "performance") {
            return [
                section("Power Profile"),
                choice("performance.mode", "CPU Profile", "Normal, Eco, or Performance power behavior", String(settingValue("performance.mode", "normal")), ["normal","eco","performance"], "apply"),
                choice("performance.governor", "CPU Governor", "Frequency scaling policy", String(settingValue("performance.governor", "ondemand")), ["ondemand","performance","powersave"], "apply"),
                slider("performance.maxFrequency", "Maximum Frequency", "Upper CPU frequency limit", Number(settingValue("performance.maxFrequency", 0)), Number(settingValue("performance.minSupportedFrequency", 0)), Number(settingValue("performance.maxSupportedFrequency", 0)), 100, " MHz", "apply"),
                section("Memory & Scheduling"),
                slider("performance.zram", "zram Size", "Compressed memory-backed swap", Number(settingValue("performance.zram", 256)), 0, 1024, 128, " MB", "apply"),
                choice("performance.priority", "Shell Priority", "Balanced, responsive, or background-friendly scheduling", String(settingValue("performance.priority", "responsive")), ["balanced","responsive","background"], "apply"),
                toggle("performance.pauseConsoleAnimations", "Pause Console While Apps Run", "Fully unload Console animations while a full-screen app is active", true, "immediate"),
                section("Thermals"),
                choice("performance.fanCurve", "Fan Curve", "Cooling response profile", String(settingValue("performance.fanCurve", "balanced")), ["quiet","balanced","aggressive"], "apply"),
                slider("performance.temperatureTarget", "Temperature Target", "Preferred sustained CPU temperature", Number(settingValue("performance.temperatureTarget", 70)), 55, 80, 1, " °C", "apply"),
                action("system-report", "Live Performance Report", "Inspect CPU, RAM, temperature, throttling and top processes", "X  OPEN")
            ]
        }
        if (id === "advanced") {
            return [
                section("Shell & Boot"),
                choice("system.bootTarget", "Boot Target", "Start NeutronOS, desktop, or console login", String(settingValue("system.bootTarget", "neutronos")), ["neutronos","desktop","console"], "reboot"),
                action("restart-shell", "Restart NeutronOS Shell", "Restart the QML shell without rebooting Linux", "X  RESTART", true),
                action("validate-boot", "Validate Boot Configuration", "Check systemd, executable permissions, QML paths and boot files", "X  VALIDATE"),
                action("safe-mode", "Safe Mode", "Disable optional apps and services for the next launch", "X  CONFIGURE"),
                section("Maintenance"),
                action("clear-cache", "Clear Rebuildable Caches", "Remove thumbnails, web cache and generated temporary files", "X  CLEAR", true),
                action("clear-history", "Clear Local Activity History", "Remove nonessential locally stored history", "X  CLEAR", true),
                action("service-manager", "Service and Log Manager", "Open Logs for systemd services, apps and containers", "X  OPEN"),
                section("Diagnostics"),
                action("diagnostics-run", "Run Full Diagnostics", "Test hardware, services, storage, network and controller state", "X  RUN"),
                action("diagnostics-export", "Export Support Bundle", "Create a local diagnostic ZIP without credentials or personal media", "X  EXPORT"),
                action("system-report", "System Integrity Report", "Verify source, installed files and runtime state", "X  VERIFY"),
                action("help-update-recovery", "Advanced Recovery Guide", "Open the NeutronOS update, backup and recovery guide", "X  OPEN")
            ]
        }
        return []
    }

    function allRowsForCategory(id) {
        var rows = []
        if (id === "user") {
            rows = [section("Profile"),
                    edit("displayName", "user.name", "Display Name", "Name shown on Login and throughout NeutronOS", userDisplayName(), "immediate"),
                    edit("tagline", "user.tagline", "Profile Tagline", "Short status shown with your profile", String(settingValue("user.tagline", "Local Account")), "immediate"),
                    action("profile-avatar", "Profile Icon", "Choose an icon, frame, tint and glow", "X  CUSTOMIZE"),
                    action("console-personalization", "Console Personalization", "Rearrange or hide System Overview cards, switch launcher style and configure screensavers", "X  OPEN"),
                    section("Authentication"),
                    edit("password", "", "Change Password", "Change the active Linux account password", "X  CHANGE"),
                    action("controller-combo", "Controller Unlock Combination", "Change the secure controller-first login combination", "X  MANAGE"),
                    toggle("user.autoLogin", "Automatic Login", "Skip LoginScreen for the selected local account", false, "reboot"),
                    toggle("user.requireAfterScreensaver", "Require Login After Screensaver", "Lock the session when the screensaver ends", true, "immediate"),
                    section("Accounts"),
                    action("add-user", "Add Local User", "Create another local NeutronOS/Linux account", "X  ADD"),
                    info("Current Role", "Account privilege and security context", String(settingValue("user.role", "User"))),
                    info("Home Directory", "Linux home for the active account", userBackend ? String(userBackend.homeDirectory || "") : "")]
        } else if (id === "system") {
            rows = [section("Identity"),
                    edit("hostname", "system.hostname", "Hostname", "Name used on your local network", String(settingValue("system.hostname", "neutronos")), "reboot"),
                    edit("deviceName", "system.deviceName", "Device Display Name", "Friendly name shown in NeutronOS", String(settingValue("system.deviceName", "NeutronOS")), "immediate"),
                    special("edition", "NeutronOS Edition", "Installed operating-system identity", "GEMINI"),
                    section("Startup"),
                    choice("system.bootTarget", "Boot Destination", "NeutronOS is shown while the NeutronOS shell boot path is enabled; Desktop or Command Line are shown only when NeutronOS is disabled", "neutronos", ["neutronos", "desktop", "cli"], "reboot"),
                    toggle("system.splash", "Splash Screen", "Show the NeutronOS boot animation", true, "reboot"),
                    toggle("system.verboseBoot", "Verbose Boot", "Show Linux startup messages for troubleshooting", false, "reboot"),
                    action("expand-filesystem", "Expand Root Storage", "Use all available space on the active boot device", "X  EXPAND", false, !developerModeEnabled),
                    section("Updates"),
                    action("open-update-recovery", "Update & Recovery", "Signed releases, Debian packages, integrity verification, Safe Mode and rollback", "X  OPEN")]
        } else if (id === "display") {
            rows = [section("Screen"),
                    choice("display.uiScale", "UI Scale", "Automatic, Small, Normal, Large or Extra Large across every shell surface", coreBackend ? String(coreBackend.uiScale) : "automatic", ["automatic","small","normal","large","extra large"], "logout"),
                    choice("display.adaptiveDashboard", "Adaptive Dashboard", "Transient activity promotion without rewriting the saved layout", coreBackend ? String(coreBackend.adaptiveDashboard) : "subtle", ["off","subtle","full"], "immediate"),
                    choice("ui.desktop.iconSize", "Desktop Icon Size", "Large restores the full-size Desktop icons; Small uses the compact v2.3 footprint", String(settingValue("ui.desktop.iconSize", "large")), ["large","small"], "immediate"),
                    toggle("dashboard.legacyAvailable", "Enable Legacy Dashboard Option", "Show the original application-carousel Dashboard in this user's Home selector", false, "immediate"),
                    choice("dashboard.defaultTab", "Default Dashboard View", "Per-user view opened after authentication", "desktop", dashboardTabOptions(), "immediate"),
                    choice("dashboard.homeTab", "Home Dashboard Tab", "Destination for the intentional Circle x5 Dashboard shortcut", "system", dashboardTabOptions(), "immediate"),
                    action("dashboard-layout", "Dashboard Layout & Custom Tabs", "Open the same System Overview Manager used by holding Start on Dashboard", "X  MANAGE"),
                    edit("userClockBackground", "display.userClockBackground", "User / Clock Background", "PNG, JPEG or WebP path from Home or mounted media; blank restores default", String(settingValue("display.userClockBackground", "")), "apply"),
                    choice("display.resolution", "Resolution", "Preferred HDMI output resolution", "auto", ["auto", "1920x1080", "2560x1440", "3840x2160"], "reboot"),
                    choice("display.rotation", "Rotation", "Rotate the HDMI output", "normal", ["normal", "90", "180", "270"], "reboot"),
                    slider("display.scale", "Interface Scale", "Scale NeutronOS text and controls", 100, 80, 140, 5, "%", "logout"),
                    toggle("display.overscan", "Overscan Compensation", "Adjust edges for televisions that crop the image", false, "reboot"),
                    section("HDMI"),
                    toggle("display.forceHdmi", "Force HDMI Detection", "Keep HDMI active when detection is unreliable", false, "reboot"),
                    choice("display.colorRange", "HDMI Color Range", "Automatic, Limited or Full RGB", "auto", ["auto", "limited", "full"], "reboot"),
                    toggle("display.cec", "HDMI-CEC", "Allow compatible televisions to exchange power and input controls", true, "reboot"),
                    section("Remote Display & Graphics"),
                    toggle("interfaces.vnc", "VNC Remote Display", "Allow approved remote desktop clients", false, "apply"),
                    slider("display.gpuMemory", "GPU Memory Split", "Reserved graphics memory on Raspberry Pi", 128, 64, 512, 32, " MB", "reboot"),
                    info("Current Renderer", "Qt Quick graphics backend", "EGLFS / OpenGL")]
        } else if (id === "interfaces") {
            rows = [section("Remote Access"),
                    toggle("interfaces.ssh", "SSH", "Secure shell access over the network • verified from systemd", settingValue("interfaces.ssh", false), "apply"),
                    toggle("interfaces.vnc", "VNC", "Remote graphical access • verified from systemd", settingValue("interfaces.vnc", false), "apply"),
                    toggle("interfaces.bluetooth", "Bluetooth", "Controller, audio and accessory support • verified from BlueZ", settingValue("interfaces.bluetooth", false), "apply"),
                    section("Raspberry Pi Interfaces"),
                    toggle("interfaces.camera", "Camera", "Enable Raspberry Pi camera auto-detection", true, "reboot"),
                    toggle("interfaces.spi", "SPI", "Enable the Serial Peripheral Interface", false, "reboot"),
                    toggle("interfaces.i2c", "I²C", "Enable the Inter-Integrated Circuit bus", false, "reboot"),
                    toggle("interfaces.serial", "Serial Port", "Enable the hardware UART", false, "reboot"),
                    toggle("interfaces.onewire", "1-Wire", "Enable 1-Wire sensor support", false, "reboot"),
                    toggle("interfaces.gpio", "GPIO User Access", "Allow approved applications to use GPIO", false, "reboot"),
                    toggle("interfaces.infrared", "Infrared", "Enable IR receiver/transmitter overlays", false, "reboot")]
        } else if (id === "network") {
            rows = [section("Wi-Fi"),
                    toggle("network.wifiEnabled", "Wi-Fi", "Enable the wireless radio", networkBackend ? networkBackend.wifiEnabled : true, "apply"),
                    info("Connected Network", "Current wireless connection", networkBackend ? String(networkBackend.connectedSsid || "Not connected") : "Unavailable"),
                    action("wifi-scan-join", "Scan & Join Wi-Fi", "Automatically discover nearby wireless networks", "X  SCAN"),
                    edit("wifiSsid", "", "Join Hidden Wi-Fi", "Manually enter an SSID for a hidden network", "X  SET UP"),
                    edit("wifiCountry", "network.wifiCountry", "Wi-Fi Country", "Regulatory domain used by the radio", String(settingValue("network.wifiCountry", "US")), "apply"),
                    section("Hotspot & Sharing"),
                    action("hotspot-manager", "Hotspot", "Broadcast over Wi-Fi or share upstream Wi-Fi internet through Ethernet", "X  MANAGE"),
                    section("Ethernet"),
                    info("Local IP Address", "Current preferred network address", networkBackend ? String(networkBackend.localIp || "Unavailable") : "Unavailable"),
                    section("Proxy & Diagnostics"),
                    edit("proxy", "network.proxyUrl", "Network Proxy", "HTTP/HTTPS proxy URL or leave blank", String(settingValue("network.proxyUrl", "Off")), "apply"),
                    action("network-speed-test", "Run Speed Test", "Measure download, upload and latency", "X  TEST"),
                    action("network-repair", "Repair Connection", "Restart and revalidate the active connection", "X  REPAIR"),
                    action("network-details", "Advanced Network Details", "DNS, routes, saved Wi-Fi and Tailscale status", "X  VIEW")]
        } else if (id === "controllers") {
            var batteryText = "Unavailable"
            if (controllerBackend && controllerBackend.controllerBatteryAvailable === true)
                batteryText = String(controllerBackend.controllerBatteryPercent) + "% • " + String(controllerBackend.controllerBatteryState || "Unknown")
            rows = [section("Connected Controller"),
                    info("Controller", "Detected controller identity", controllerBackend ? String(controllerBackend.controllerType || "Controller") + " • " + String(controllerBackend.controllerName || "Unknown") : "Unavailable"),
                    info("Address", "Verified Bluetooth address or wired profile key", controllerBackend ? String(controllerBackend.controllerAddress || controllerBackend.controllerSettingsKey || "Unavailable") : "Unavailable"),
                    info("Battery", "Current charge and charging state", batteryText),
                    info("Input Device", "Linux evdev path used by NeutronOS", controllerBackend ? String(controllerBackend.controllerDevicePath || "Unavailable") : "Unavailable"),
                    info("Backend", "Live controller backend state", controllerBackend ? String(controllerBackend.controllerBackendStatus || "Unavailable") : "Unavailable"),
                    section("Input Profile"),
                    choice("controller.inputProfile", "Input Profile", "Precision uses smaller dead zones; Relaxed filters more drift", "balanced", ["precision", "balanced", "relaxed"], "immediate"),
                    slider("controller.deadzone", "Stick Dead Zone", "Applied immediately to physical and web-controller stick navigation", 12, 0, 35, 1, "%", "immediate"),
                    slider("controller.triggerThreshold", "Trigger Threshold", "Minimum L2/R2 travel required before an action is emitted", 16, 1, 80, 1, "%", "immediate"),
                    slider("controller.repeat", "Navigation Repeat", "Controller navigation repeat delay", 155, 80, 300, 10, " ms", "apply"),
                    action("controller-reset-input", "Reset Input Tuning", "Restore the Balanced profile and release any held inputs", "X  RESET"),
                    section("Test & Feedback"),
                    action("button-test", "Complete Button Test", "Walk through every expected button, trigger, D-pad direction and stick", "X  TEST"),
                    action("controller-haptic-test", "Haptic Test", "Play the configured vibration pattern at the current intensity", "X  TEST"),
                    action("controller-refresh", "Refresh Controller Hardware", "Rescan identity, input nodes, battery, lightbar and haptics", "X  REFRESH"),
                    section("Lightbar & Reconnect"),
                    info("Lightbar", "Detected Linux LED backend", controllerBackend ? String(controllerBackend.controllerLightBackend || "Unavailable") : "Unavailable"),
                    info("Vibration", "Current haptic profile", controllerBackend ? String(controllerBackend.controllerVibrationLevel || "medium").toUpperCase() + " • " + String(controllerBackend.controllerVibrationPattern || "soft-pulse") : "Unavailable"),
                    action("controller-settings", "Lightbar and Haptics Details", "View the active light, vibration, reconnect and charging configuration", "X  VIEW"),
                    section("Management"),
                    action("controller-off", "Power Off Controller", "Disconnect and power down the active controller", "X  POWER OFF", true),
                    action("controller-pair", "Pair New Controller", "Open Bluetooth discovery and pairing", "X  PAIR")]
        } else if (id === "audio") {
            rows = [section("Output"),
                    choice("audio.output", "Output Device", "Automatic, HDMI, analog, USB or Bluetooth", "automatic", ["automatic", "hdmi", "analog", "usb", "bluetooth"], "apply"),
                    slider("audio.volume", "Master Volume", "Overall output volume", 70, 0, 100, 5, "%", "apply"),
                    toggle("audio.muted", "Mute", "Silence all output", false, "immediate"),
                    section("Interface Sounds"),
                    toggle("audio.navigation", "Navigation Sounds", "Play subtle sounds while moving focus", true, "immediate"),
                    toggle("audio.warnings", "Warning Sounds", "Play alerts for thermal, storage and security events", true, "immediate"),
                    slider("audio.uiVolume", "Interface Sound Volume", "Volume for NeutronOS effects", 55, 0, 100, 5, "%", "immediate"),
                    section("Input"),
                    choice("audio.input", "Microphone", "Select the default input device", "automatic", ["automatic", "usb", "bluetooth", "none"], "apply"),
                    toggle("audio.inputMuted", "Mute Microphone", "Disable microphone capture", true, "immediate")]
            rows.push(section("Detected Outputs"))
            var outputs = coreBackend ? coreBackend.audioOutputs : []
            for (var ao=0; ao<outputs.length; ++ao)
                rows.push(info(String(outputs[ao].name || "Unavailable"), "Authoritative PipeWire output", outputs[ao].default === true ? "DEFAULT" : "AVAILABLE"))
            rows.push(action("audio-test-left", "Test Left", "Play a safe local channel test", "X  TEST"))
            rows.push(action("audio-test-right", "Test Right", "Play a safe local channel test", "X  TEST"))
            rows.push(action("audio-test-stereo", "Test Stereo", "Play a safe local stereo test", "X  TEST"))
        } else if (id === "bluetooth") {
            var devices = coreBackend ? coreBackend.bluetoothDevices : []
            var connectedCount = 0
            var trustedCount = 0
            for (var bdCount=0; bdCount<devices.length; ++bdCount) {
                if (devices[bdCount].connected === true) connectedCount++
                if (devices[bdCount].trusted === true) trustedCount++
            }
            rows = [section("Bluetooth Manager"),
                    action("bluetooth-manager", "Manage Bluetooth Devices", "Connect, disconnect, pair, trust, remove trust and forget devices", "X  MANAGE"),
                    info("Connected", "Devices with an active BlueZ connection", String(connectedCount)),
                    info("Trusted", "Devices allowed to reconnect without a new trust decision", String(trustedCount)),
                    action("bluetooth-refresh", "Scan / Refresh", "Refresh connected, paired and available device state", "X  REFRESH"),
                    section("Devices")]
            if (!devices.length)
                rows.push(info("No Devices", "No BlueZ devices were returned", "NONE"))
            for (var bd=0; bd<devices.length; ++bd) {
                var bt = devices[bd]
                var btState = bt.connected === true ? "CONNECTED" : bt.paired === true ? "PAIRED" : "AVAILABLE"
                var btTrust = bt.trusted === true ? "TRUSTED" : "UNTRUSTED"
                rows.push(action("bluetooth-manage|" + String(bt.address || ""),
                                 String(bt.name || "Unknown Device"),
                                 btState + " • " + String(bt.type || "Bluetooth") + " • " + String(bt.address || "Unavailable"),
                                 btTrust))
            }
        } else if (id === "appearance") {
            rows = [section("Theme"),
                    choice("theme.mode", "Appearance", "Switch the entire semantic NeutronOS palette", settingsBackend ? settingsBackend.themeMode : "dark", ["dark", "light"], "immediate"),
                    choice("appearance.contrast", "Contrast", "Standard or high-contrast controls", "standard", ["standard", "high"], "immediate"),
                    toggle("appearance.reduceTransparency", "Reduce Transparency", "Use fully opaque surfaces throughout NeutronOS", false, "immediate"),
                    section("Wallpaper & Interface"),
                    edit("wallpaper", "appearance.wallpaper", "Wallpaper", "Choose a theme wallpaper file", "X  CHOOSE", "immediate"),
                    slider("appearance.panelOpacity", "Panel Opacity", "Adjust shared panel opacity", 94, 70, 100, 2, "%", "immediate"),
                    slider("appearance.textScale", "Text Scale", "Scale interface typography", 100, 80, 140, 5, "%", "logout"),
                    choice("appearance.font", "Interface Font", "Choose the NeutronOS UI typeface", "inter", ["inter", "noto sans", "dejavu sans"], "logout"),
                    section("Screensaver"),
                    action("console-personalization-screensaver", "Screensaver Studio", "Choose pictures or animated screensavers, speed, intensity and rotation", "X  OPEN"),
                    slider("appearance.screensaverMinutes", "Screensaver Delay", "Minutes before the moving screensaver starts", 5, 3, 30, 1, " min", "apply"),
                    toggle("appearance.requireUnlock", "Require Unlock", "Return to Login after the screensaver", false, "immediate"),
                    action("screensaver-preview", "Preview Screensaver", "Start the active pan-and-zoom screensaver", "X  PREVIEW"),
                    section("Virtual Keyboard"),
                    choice("keyboard.layout", "Keyboard Layout", "Choose QWERTY, alphabetical, or compact page arrangement", "qwerty", ["qwerty", "alphabetical", "compact"], "immediate"),
                    slider("keyboard.keyScale", "Key Size", "Scale every virtual keyboard key", 100, 75, 140, 5, "%", "immediate"),
                    slider("keyboard.spacing", "Key Spacing", "Adjust space between keys", 8, 2, 20, 1, " px", "immediate"),
                    slider("keyboard.opacity", "Keyboard Opacity", "Adjust keyboard panel and key transparency", 96, 55, 100, 5, "%", "immediate"),
                    choice("keyboard.keyShape", "Key Shape", "Rounded, pill, square, or glass key geometry", "rounded", ["rounded", "pill", "square", "glass"], "immediate"),
                    choice("keyboard.tint", "Keyboard Tint", "Choose the keyboard accent family", "neutron", ["neutron", "cyan", "purple", "pink", "green", "neutral"], "immediate"),
                    choice("keyboard.labels", "Key Labels", "Standard, compact, or large labels", "standard", ["standard", "compact", "large"], "immediate"),
                    choice("keyboard.focusStyle", "Focus Appearance", "Ring, glow, fill, or pulse selection", "ring", ["ring", "glow", "fill", "pulse"], "immediate"),
                    choice("keyboard.armedStyle", "Armed Appearance", "Red ring, red fill, or pulse", "ring", ["ring", "fill", "pulse"], "immediate"),
                    action("keyboard-preview", "Preview Keyboard", "Open a live keyboard preview using the current pending settings", "X  PREVIEW"),
                    action("keyboard-reset", "Reset Keyboard", "Restore the default NeutronOS controller-first keyboard", "X  RESET")]
        } else if (id === "localization") {
            rows = [section("Language & Region"),
                    choice("localization.language", "NeutronOS Language", "Language used by the shell", "english", ["english", "spanish", "french", "german", "japanese"], "logout"),
                    edit("locale", "localization.locale", "System Locale", "Linux locale such as en_US.UTF-8", String(settingValue("localization.locale", "en_US.UTF-8")), "logout"),
                    special("timezone-browser", "Timezone", "Continent → country → timezone", currentTimezoneForPicker()),
                    edit("wifiCountry", "network.wifiCountry", "Wi-Fi Country", "Two-letter regulatory country code", String(settingValue("network.wifiCountry", "US")), "apply"),
                    section("Keyboard & Formats"),
                    edit("keyboardLayout", "localization.keyboard", "Keyboard Layout", "Linux keymap such as us or uk", String(settingValue("localization.keyboard", "us")), "logout"),
                    choice("localization.units", "Measurement System", "US customary or metric", "us", ["us", "metric"], "immediate"),
                    choice("localization.firstDay", "First Day of Week", "Sunday or Monday", "sunday", ["sunday", "monday"], "immediate")]
        } else if (id === "accessibility") {
            rows = [section("Vision"),
                    toggle("accessibility.highContrast", "High Contrast", "Increase text and border contrast", false, "immediate"),
                    slider("accessibility.textScale", "Large Text", "Increase text across NeutronOS", 100, 100, 160, 5, "%", "logout"),
                    toggle("accessibility.colorSafe", "Color-Safe Status", "Add shapes and labels beyond color alone", false, "immediate"),
                    slider("accessibility.focusWidth", "Focus Ring Thickness", "Increase the selected-item outline", 2, 1, 6, 1, " px", "immediate"),
                    section("Motion"),
                    toggle("accessibility.reduceMotion", "Reduce Motion", "Shorten or remove decorative movement", false, "immediate"),
                    toggle("accessibility.disableBackgroundMotion", "Disable Background Motion", "Stop ambient background animation", false, "immediate"),
                    section("Input & Audio"),
                    slider("accessibility.holdDuration", "Button Hold Duration", "Require a longer press before activation", 0, 0, 800, 50, " ms", "immediate"),
                    toggle("accessibility.monoAudio", "Mono Audio", "Combine left and right audio channels", false, "apply"),
                    toggle("accessibility.soundCues", "Navigation Sound Cues", "Use sounds to reinforce focus changes", false, "immediate")]
        } else if (id === "apps") {
            rows = [section("App Manager"),
                    special("app-manager", "Installed Applications", "View all discovered apps, storage, cache, last used and uninstall controls", appBackend ? String(appBackend.appCount) + " APPS • X  OPEN" : "X  OPEN"),
                    section("Application Shortcuts"),
                    link("filemanager", "Open Filesystem", "Browse files and folders in the dedicated Filesystem app"),
                    link("terminal", "Open Terminal", "Use the shared PTY terminal and phone mirror"),
                    section("Services"),
                    action("service-manager", "Service Manager", "Start, stop, restart and enable systemd or Docker services", "X  OPEN"),
                    toggle("apps.autoStartServices", "Start Required Services", "Automatically start an app's backend before opening it", true, "immediate"),
                    section("Defaults & Permissions"),
                    choice("apps.defaultTerminal", "Default Terminal", "Terminal used for command applications", "terminal", ["terminal"], "immediate"),
                    choice("apps.defaultBrowser", "Default Browser", "Browser used for external links", "system", ["system", "chromium", "firefox"], "apply"),
                    action("app-permissions", "Application Permissions", "Network, storage, terminal and background privileges", "X  MANAGE")]
        } else if (id === "storage") {
            rows = [section("Storage Overview"),
                    action("scan-storage", "Analyze Storage", "Scan mounted devices and classify Media, Apps, System, Documents, Downloads, Backups and Other", settingsBackend && settingsBackend.storageScanBusy ? "SCANNING…" : "X  ANALYZE"),
                    link("storage", "Open Storage Utility", "Formatting, SMART checks, boot cloning, mounts and filesystem details"),
                    link("filemanager", "Open Filesystem", "Browse and manage files in the dedicated Filesystem app")]
            var usage = settingsBackend ? settingsBackend.storageUsage : []
            if (!usage || usage.length === 0)
                rows.push(info("No Analysis Yet", "Select Analyze Storage to classify each mounted device", "NOT SCANNED"))
            else {
                rows.push(section("Connected Devices"))
                for (var su = 0; su < usage.length; su++)
                    rows.push({ kind: "storage", title: String(usage[su].name || "Storage"), deviceData: usage[su], selectable: true })
            }
        } else if (id === "security") {
            rows = [section("Authentication"),
                    edit("password", "", "Linux Password", "Change the active account password", "X  CHANGE"),
                    action("controller-combo", "Controller Unlock Combination", "Manage the controller-first login credential", "X  MANAGE"),
                    section("Security Core"),
                    action("core-security-profiles", "Security Profiles", "NORMAL, TRAVEL, OFFLINE, RESTRICTED, LOCKDOWN and MAXIMUM mapped above DEFCON", "X  OPEN"),
                    action("core-security-timeline", "Security Timeline", "Authoritative authentication, app, network, storage, system and threat history", "X  OPEN"),
                    action("core-app-permissions", "App Permissions", "Per-app capabilities; privileged scopes remain policy-controlled", "X  OPEN"),
                    toggle("user.autoLogin", "Automatic Login", "Skip LoginScreen on startup", false, "reboot"),
                    section("Remote Access"),
                    toggle("interfaces.ssh", "SSH", "Secure terminal access", false, "apply"),
                    toggle("interfaces.vnc", "VNC", "Remote desktop access", false, "apply"),
                    info("Web Terminal", "Temporary token-protected terminal mirror", "OPEN FROM TERMINAL"),
                    section("Privacy"),
                    toggle("security.commandHistory", "Terminal History", "Retain recent commands locally", true, "immediate"),
                    toggle("security.diagnostics", "Diagnostic Data", "Store local performance and error diagnostics", true, "immediate"),
                    action("clear-history", "Clear Recent Activity", "Remove local recent-command and activity history", "X  CLEAR", true),
                    info("Developer Mode", "Advanced privileges and root shell access", developerModeEnabled ? "ON" : "OFF")]
        } else if (id === "update-recovery") {
            var ur = updateRecoveryBackend
            var urBusy = ur ? ur.busy === true : false
            var urProgress = urBusy && ur && Number(ur.progress) >= 0 ? String(ur.progress) + "%" : String(ur ? ur.status || "Ready" : "BACKEND UNAVAILABLE")
            var urAvailable = ur ? String(ur.availableVersion || "") : ""
            var urRepository = ur && ur.repositoryConfigured === true
                    ? (String(ur.manifestUrl || "").indexOf("file:") === 0 ? "PRIVATE MAINLINE" : "HTTPS")
                    : "NOT CONFIGURED"
            var urTrust = ur && ur.trustedKeyAvailable === true ? "PINNED KEY" : "KEY REQUIRED"
            var urManifest = ur && ur.releaseManifestAvailable === true ? "INSTALLED" : "MISSING"
            var urLatestRecovery = ur ? String(ur.latestRecoveryPoint || "None") : "None"
            rows = [warning("Signed Update Safety", "NeutronOS installs only LIVE Mainline packages whose authenticated metadata verifies with the pinned NeutronOS OpenPGP release public key and whose bytes match its signed SHA-256 and size."),
                    section("Status"),
                    info("Installed Version", "Current NeutronOS release", ur ? String(ur.currentVersion || "0.5 candidate") : "UNAVAILABLE"),
                    choice("update.channel", "Update Channel", "Mainline offers signed LIVE NeutronOS OS releases", ur ? String(ur.channel || "mainline") : "mainline", ["mainline"], "immediate"),
                    info("Update Repository", "Authenticated read-only mirror of private OGDrNeutron/NeutronOS-Mainline", urRepository),
                    info("Signing Trust", "Pinned OpenPGP release public key required before download and again before Recovery applies an update", urTrust),
                    info("Release Manifest", "Local integrity baseline used by Verify Installation", urManifest),
                    action("update-trust-details", "Update Trust & Offline Inbox", "View trusted-key and local update package requirements", "X  VIEW"),
                    info("Last Checked", "Last completed NeutronOS update check", ur ? String(ur.lastCheckedText || "Never") : "Never"),
                    info("Current Operation", ur ? String(ur.lastMessage || ur.status || "Ready") : "Update backend unavailable", urProgress),
                    section("NeutronOS Updates"),
                    action("update-check", "Check for NeutronOS Update", "Refresh private Mainline, then authenticate metadata for the newest LIVE release", urBusy ? "WORKING…" : "X  CHECK")]
            if (ur && ur.updateAvailable === true) {
                rows.push(info("Available Release", "Signed release discovered for this channel", urAvailable + " • " + String(ur.updateSizeText || "Unknown")))
                rows.push(action("update-release-notes", "Release Notes", "Review the changes before downloading", "X  VIEW"))
                if (ur.packageDownloaded !== true)
                    rows.push(action("update-download", "Download Update", "Download and verify the update package without installing it", urBusy ? "WORKING…" : "X  DOWNLOAD"))
            }
            if (ur && ur.packageDownloaded === true) {
                rows.push(info("Downloaded Package", "Local package state", ur.packageVerified === true ? "SIGNATURE VERIFIED" : "NOT VERIFIED"))
                rows.push(action("update-install", "Install NeutronOS Update", "Re-verify at the privileged boundary and apply atomically during one-shot Recovery", "X  INSTALL", true))
            }
            if (urBusy)
                rows.push(action("update-cancel", "Cancel Current Operation", "Stop the active check, download, integrity scan or recovery-point creation", "X  CANCEL", true))
            rows.push(section("Debian Packages"))
            rows.push(info("Available Package Updates", "Result of the latest Debian package check", ur ? String(ur.debianUpdatesAvailable || 0) : "0"))
            rows.push(action("debian-check", "Check Debian Updates", "Inspect available Debian package upgrades", urBusy ? "WORKING…" : "X  CHECK"))
            rows.push(action("debian-install", "Install Debian Updates", "Refresh package indexes and install available upgrades", "X  INSTALL", true))
            rows.push(section("Integrity & Recovery"))
            rows.push(info("Installation Integrity", "Comparison with config/release-manifest.sha256", ur ? String(ur.integritySummary || "Not verified") : "Unavailable"))
            rows.push(action("update-verify", "Verify Installation", "Hash the installed NeutronOS release files and report missing or modified files", urBusy ? "WORKING…" : "X  VERIFY"))
            rows.push(action("update-integrity-details", "View Integrity Report", "Open the complete result from the last verification", "X  VIEW"))
            rows.push(info("Recovery Points", "Verified local rollback archives", ur ? String(ur.recoveryPointCount || 0) + " • " + urLatestRecovery : "0"))
            rows.push(action("update-create-recovery", "Create Recovery Point", "Archive the current source, configuration and app state before risky changes", urBusy ? "WORKING…" : "X  CREATE"))
            rows.push(info("Restore Recovery Point", "Verified recovery points are selected and restored from the one-shot authenticated Recovery environment while user data remains preserved.", "RECOVERY BOOT"))
            rows.push(info("Repair NeutronOS Installation", "Production Gemini does not include a compiler. Repair requires an authenticated prebuilt Mainline or full-system Recovery package.", "SIGNED PACKAGE REQUIRED"))
            rows.push(action(ur && ur.safeModePrepared === true ? "update-cancel-safe-mode" : "update-safe-mode",
                             ur && ur.safeModePrepared === true ? "Cancel Safe Mode" : "Prepare Safe Mode",
                             ur && ur.safeModePrepared === true ? "Remove the Safe Mode flag before the next NeutronOS start" : "Use the basic Qt render loop on the next NeutronOS start for display and animation recovery",
                             ur && ur.safeModePrepared === true ? "X  CANCEL" : "X  PREPARE", true))
            rows.push(section("History & Maintenance"))
            rows.push(action("update-history", "Update & Recovery History", "Review checks, downloads, scheduled system operations and results", "X  VIEW"))
            rows.push(info("Update Cache", "Downloaded update packages and partial files", ur ? String(ur.updateCacheSizeText || "0 B") : "0 B"))
            rows.push(action("update-clear-cache", "Clear Update Cache", "Remove downloaded and partial update files without changing the installed OS", "X  CLEAR", true))
            rows.push(info("Local Update Inbox", "Offline manifest and package staging directory", ur ? String(ur.localInboxPath || "~/NeutronOS/updates/inbox") : "~/NeutronOS/updates/inbox"))
            rows.push(info("Recovery Directory", "Local verified rollback archives", ur ? String(ur.recoveryDirectory || "~/NeutronOS/backups/recovery") : "~/NeutronOS/backups/recovery"))
        } else if (id === "backup-restore") {
            var br = backupRestoreBackend
            var brBusy = br ? br.busy === true : false
            var brProgress = brBusy && br && Number(br.progress) >= 0 ? String(br.progress) + "%" : String(br ? br.status || "Ready" : "BACKEND UNAVAILABLE")
            var latestName = br ? String(br.latestBackupName || "None") : "None"
            var packageState = br && br.cleanReinstallReady === true ? "VERIFIED PACKAGE READY" : "VERIFY FULL PACKAGE IN UPDATE & RECOVERY"
            rows = [warning("Backup Before Destructive Changes", "Restore, secure reset and clean reinstall can replace configuration or user data. Store an additional backup on removable storage before continuing."),
                    section("Backup Profile"),
                    choice("backup.profile", "Backup Profile", "Full system, Settings, Apps or Personal data", br ? String(br.profile || "full") : "full", ["full", "settings", "apps", "personal"], "immediate"),
                    toggle("backup.includeRoms", "Include Game ROMs", "ROM libraries may make backups substantially larger", br ? br.includeRoms === true : false, "immediate"),
                    info("Backup Destination", "Absolute local or mounted-storage directory", br ? String(br.destinationPath || "~/NeutronOS/backups/system") : "UNAVAILABLE"),
                    action("backup-configure-destination", "Change Backup Destination", "Choose an internal or mounted external-storage directory", "X  CONFIGURE"),
                    info("Current Operation", br ? String(br.currentItem || br.lastMessage || br.status || "Ready") : "Backup backend unavailable", brProgress),
                    section("Create & Review"),
                    action("backup-create", "Create Backup", "Build a categorized archive, manifest and SHA-256 checksum", brBusy ? "WORKING…" : "X  CREATE"),
                    action("backup-details", "View Available Backups", "Review backup profiles, sizes, dates and checksum state", "X  VIEW"),
                    info("Stored Backups", "Archives in the selected destination", br ? String(br.backupCount || 0) + " • " + String(br.totalBackupSizeText || "0 B") : "0"),
                    section("Restore"),
                    info("Latest Backup", br ? String(br.latestBackupProfile || "Unknown") + " profile" : "No backup backend", latestName),
                    action("backup-verify", "Verify Latest Backup", "Validate checksum, archive paths, manifest and payload", brBusy ? "WORKING…" : "X  VERIFY"),
                    info("Restore Latest Backup", "Full backup restoration is performed only in the authenticated Recovery environment; production Gemini does not compile source archives.", "RECOVERY BOOT"),
                    action("backup-delete", "Delete Latest Backup", "Permanently remove the newest archive and checksum", "X  DELETE", true),
                    section("Clean NeutronOS Reinstall"),
                    toggle("backup.preserveUserData", "Preserve User Data", "Keep profiles, settings, backups, game ROMs/cards and app state during clean reinstall", br ? br.preserveUserData === true : true, "immediate"),
                    info("Full-Install Package", "Must be downloaded and signature-verified in Update & Recovery and declare fullInstall=true", packageState),
                    action("backup-reinstall-details", "Clean Reinstall Requirements", "Review exactly what is replaced and what can be preserved", "X  VIEW"),
                    info("Clean Reinstall NeutronOS", "Available only when Recovery has a signed complete full-system package. Overlay updates cannot be used for clean reinstall.", "FULL-SYSTEM PACKAGE REQUIRED"),
                    section("Secure Data Reset"),
                    warning("Flash Storage Limitation", "NeutronOS overwrites small sensitive files before removal, but SD-card and SSD wear-leveling prevents a forensic-erasure guarantee. A full offline device reimage is required for that guarantee."),
                    action("backup-wipe-details", "Secure Reset Details", "Review which data is removed and the full-device recovery requirement", "X  VIEW"),
                    action("backup-wipe-data", "Wipe NeutronOS User Data", "Remove profiles, app state, configuration, backup archives and security credentials; ROM removal follows Include Game ROMs", "X  WIPE", true),
                    info("Offline Recovery Environment", "Required for a complete boot-drive wipe and reimage", br && br.recoveryEnvironmentReady === true ? "READY" : "NOT INSTALLED"),
                    section("History"),
                    action("backup-history", "Backup & Restore History", "Review completed and scheduled operations", "X  VIEW")]
            if (brBusy)
                rows.push(action("backup-cancel", "Cancel Current Backup Operation", "Stop an active create or verification operation", "X  CANCEL", true))
        } else if (id === "notifications") {
            rows = [section("General"),
                    toggle("notifications.enabled", "Notifications", "Show NeutronOS alerts", true, "immediate"),
                    toggle("notifications.sound", "Notification Sounds", "Play a sound for alerts", true, "immediate"),
                    toggle("notifications.haptics", "Haptic Notifications", "Pulse the controller for important alerts", true, "immediate"),
                    choice("notifications.dndMode", "Do Not Disturb", "Off, On, or Schedule; security-critical events bypass", coreBackend ? String(coreBackend.dndMode) : "off", ["off","on","schedule"], "immediate"),
                    section("System Alerts"),
                    toggle("notifications.thermal", "Temperature Warnings", "Alert when temperature becomes unstable", true, "immediate"),
                    toggle("notifications.storage", "Storage Warnings", "Alert when a device is low on space or unhealthy", true, "immediate"),
                    toggle("notifications.network", "Network Disconnects", "Alert when connectivity is lost", true, "immediate"),
                    toggle("notifications.controller", "Controller Battery", "Alert when battery is low or charging completes", true, "immediate"),
                    toggle("notifications.updates", "Update Alerts", "Notify when updates are available", true, "immediate")]
        } else if (id === "services") {
            var serviceRows = coreBackend ? coreBackend.services : []
            rows = [
                action("refresh-services", "Refresh Service Inventory", "Re-read systemd unit files, loaded runtime units and NeutronOS helpers from the local system", "X  REFRESH"),
                info("Discovered Entries", "Systemd services, timers, sockets, paths, targets and installed NeutronOS helpers", String(serviceRows ? serviceRows.length : 0) + " ITEMS"),
                warning("Protected Services", "Critical NeutronOS, security, networking and boot services are inventory-only here. Selecting any entry opens its exact state and startup details.")
            ]

            var systemdKinds = ["service", "timer", "socket", "path", "target"]
            for (var sk = 0; sk < systemdKinds.length; ++sk) {
                var sectionAdded = false
                for (var sv = 0; sv < serviceRows.length; ++sv) {
                    var serviceEntry = serviceRows[sv] || ({})
                    if (String(serviceEntry.kind || "service") !== systemdKinds[sk])
                        continue
                    if (!sectionAdded) {
                        rows.push(section(systemdKinds[sk].toUpperCase() + " UNITS"))
                        sectionAdded = true
                    }
                    var serviceId = String(serviceEntry.unit || serviceEntry.path || "")
                    var serviceDetail = serviceId
                    if (serviceEntry.protected === true)
                        serviceDetail += "  •  PROTECTED"
                    var serviceState = String(serviceEntry.state || "Unavailable").toUpperCase()
                    var serviceStartup = String(serviceEntry.startup || "Unavailable").toUpperCase()
                    rows.push(action("service-details|" + serviceId,
                                     String(serviceEntry.name || serviceId || "Unknown"),
                                     serviceDetail,
                                     serviceState + "  •  " + serviceStartup))
                }
            }

            var helperSectionAdded = false
            for (var sh = 0; sh < serviceRows.length; ++sh) {
                var helperEntry = serviceRows[sh] || ({})
                if (String(helperEntry.kind || "") !== "helper")
                    continue
                if (!helperSectionAdded) {
                    rows.push(section("NEUTRONOS HELPERS"))
                    helperSectionAdded = true
                }
                var helperId = String(helperEntry.path || helperEntry.unit || "")
                rows.push(action("service-details|" + helperId,
                                 String(helperEntry.name || helperId || "Helper"),
                                 helperId,
                                 String(helperEntry.state || "Available").toUpperCase() + "  •  " + String(helperEntry.startup || "On demand").toUpperCase()))
            }

            if (!serviceRows || serviceRows.length === 0)
                rows.push(warning("Service Inventory Unavailable", "The system service backend returned no entries. Refresh the inventory to retry."))
        } else if (id === "power") {
            rows = [section("Power Mode"),
                    choice("power.mode", "Power Mode", "Normal, Eco or Performance", "normal", ["normal", "eco", "performance"], "apply"),
                    toggle("power.blankDisplay", "Display Blanking", "Turn off the display after extended inactivity", true, "immediate"),
                    slider("power.displayMinutes", "Display Timeout", "Minutes before HDMI output is blanked", 30, 5, 120, 5, " min", "immediate"),
                    section("Cooling"),
                    choice("power.fanMode", "Fan Control", "Automatic, Quiet or Maximum", "automatic", ["automatic", "quiet", "maximum"], "apply"),
                    slider("power.fanStart", "Fan Start Temperature", "Temperature that begins active cooling", 60, 40, 80, 2, "°C", "apply"),
                    info("Thermal Status", "Current Raspberry Pi temperature state", "OPEN SYSTEM OVERVIEW"),
                    section("System Actions"),
                    action("restart-shell", "Restart NeutronOS", "Restart only the QML shell service", "X  RESTART", true),
                    action("reboot", "Reboot Pi", "Restart Linux and NeutronOS", "X  REBOOT", true),
                    action("shutdown", "Shut Down Pi", "Safely power off the device", "X  SHUT DOWN", true)]
        } else if (id === "performance") {
            var psi = settingsBackend ? settingsBackend.systemInfo : ({})
            rows = [warning(developerModeEnabled ? "Developer Controls Active" : "Developer Mode Required", developerModeEnabled ? "Performance controls are unlocked. Cooling and stability safeguards still apply." : "Performance controls remain fully visible for reference and unlock when Developer Mode is enabled."),
                    section("Live Status"),
                    info("CPU Architecture", "Detected processor architecture", String(psi.architecture || "x86_64")),
                    info("Installed Memory", "Physical memory available to Linux", String(psi.memory || "Unavailable")),
                    info("Thermal Policy", "Current cooling and throttling safeguards", String(settingValue("performance.fanCurve", "balanced")).toUpperCase()),
                    section("CPU"),
                    choice("performance.mode", "CPU Profile", "Normal or Performance up to hardware maximum", "normal", ["normal", "performance"], "apply"),
                    choice("performance.governor", "CPU Governor", "Frequency-scaling policy", "ondemand", ["ondemand", "performance", "powersave"], "reboot"),
                    slider("performance.maxFrequency", "Maximum Frequency", "Upper CPU frequency limit", Number(settingValue("performance.maxFrequency", 0)), Number(settingValue("performance.minSupportedFrequency", 0)), Number(settingValue("performance.maxSupportedFrequency", 0)), 100, " MHz", "reboot"),
                    section("Memory"),
                    slider("performance.zram", "zram Size", "Compressed memory-backed swap", 256, 0, 1024, 128, " MB", "reboot"),
                    slider("display.gpuMemory", "GPU Memory Split", "Memory reserved for graphics", 128, 64, 512, 32, " MB", "reboot"),
                    section("Thermal"),
                    choice("performance.fanCurve", "Fan Curve", "Cooling response profile", "balanced", ["quiet", "balanced", "aggressive"], "apply"),
                    action("diagnostics", "Run Stability Diagnostics", "CPU, memory, temperature and throttling checks", "X  RUN")]
        } else if (id === "advanced") {
            var asi = settingsBackend ? settingsBackend.systemInfo : ({})
            rows = [warning(developerModeEnabled ? "Developer Controls Active" : "Developer Mode Required", developerModeEnabled ? "Advanced controls are unlocked. Changes are validated before they are written." : "Advanced controls remain fully visible for reference and unlock when Developer Mode is enabled."),
                    section("System Context"),
                    info("Kernel", "Currently running Linux kernel", String(asi.kernel || "Unavailable")),
                    info("Boot Device", "Root filesystem capacity", String(asi.rootTotal || "Unknown") + " total • " + String(asi.rootFree || "Unknown") + " available"),
                    info("Build Identity", "Current NeutronOS machine identifier", String(asi.machineId || "Unavailable")),
                    section("Boot Configuration"),
                    link("terminal", "config.txt Editor", "Open Terminal with the Raspberry Pi boot configuration"),
                    action("validate-boot", "Validate Boot Configuration", "Check supported keys and syntax before reboot", "X  VALIDATE"),
                    section("Diagnostics & Logs"),
                    action("diagnostics", "Generate System Diagnostics", "Run the NeutronOS health audit", "X  RUN"),
                    link("logs", "Open Logs", "NeutronOS, kernel, NetworkManager, Bluetooth and app logs"),
                    action("network-details", "D-Bus and Network Diagnostics", "Inspect services, routes, DNS and backend health", "X  VIEW"),
                    section("Recovery"),
                    action("clear-cache", "Clear NeutronOS Cache", "Remove disposable caches without deleting profiles", "X  CLEAR", true),
                    action("restart-shell", "Restart NeutronOS Shell", "Restart the shell without rebooting Linux", "X  RESTART", true),
                    action("safe-mode", "Prepare Safe Mode", "Disable optional visual features on next boot", "X  PREPARE", true)]
        } else if (id === "diagnostics") {
            var db = diagnosticsBackend
            rows = [section("System Health"),
                    info("Status", "Current diagnostics backend state", db ? String(db.stage || "Ready") : "Unavailable"),
                    info("Last Run", "Most recent completed diagnostic pass", db ? String(db.lastRun || "Never") : "Never"),
                    info("Summary", "Detected device and kernel", db ? String(db.systemSummary || "Waiting for diagnostics") : "Unavailable"),
                    info("Results", "Passed • warnings • failures", db ? String(db.passedCount || 0) + " passed • " + String(db.warningCount || 0) + " warnings • " + String(db.failedCount || 0) + " failed" : "Unavailable"),
                    action("diagnostics-run-full", "Run Full Diagnostics", "Check shell, memory, temperature, throttling, storage, network, DNS, failed services and persistent state", db && db.busy ? "WORKING…" : "X  RUN"),
                    action("diagnostics-view-report", "View Diagnostic Report", "Open the complete results with explanations for every check", "X  VIEW"),
                    section("Support"),
                    action("diagnostics-export", "Export Support Bundle", "Create a redacted archive with diagnostics, NeutronOS journal, kernel warnings, services, storage and network state", db && db.busy ? "WORKING…" : "X  EXPORT"),
                    info("Latest Bundle", "Saved locally for troubleshooting", db && String(db.lastBundlePath || "").length > 0 ? String(db.lastBundlePath) : "None"),
                    section("Live Controller Context"),
                    info("Controller", "Current input device", controllerBackend && controllerBackend.controllerConnected ? String(controllerBackend.controllerName || "Controller") : "Not connected"),
                    info("Last Input Event", "Most recent event observed by the backend", controllerBackend ? String(controllerBackend.lastControllerEvent || "None") : "Unavailable"),
                    action("button-test", "Controller Button Test", "Verify every expected controller input and show missed controls", "X  TEST"),
                    section("Related Tools"),
                    link("logs", "Open Logs", "Review live or historical service, container, script and system logs"),
                    link("storage", "Open Storage", "Inspect SMART data, filesystems, mounts, encryption and optimization") ]
            if (db && db.checks) {
                var diagnosticChecks = db.checks
                for (var diagnosticIndex = 0; diagnosticIndex < diagnosticChecks.length; diagnosticIndex++) {
                    var diagnosticCheck = diagnosticChecks[diagnosticIndex]
                    if (!diagnosticCheck) continue
                    if (String(diagnosticCheck.status || "warn") === "fail")
                        rows.push(warning(String(diagnosticCheck.title || "Diagnostic failure"), String(diagnosticCheck.value || "") + " • " + String(diagnosticCheck.detail || "")))
                    else
                        rows.push(info(String(diagnosticCheck.title || "Diagnostic check"), String(diagnosticCheck.detail || ""), String(diagnosticCheck.value || "")))
                }
            }
        } else if (id === "help") {
            rows = [section("Getting Started"),
                    action("help-controller-map", "Controller Map", "Every global NeutronOS controller action and keyboard fallback", "X  OPEN"),
                    action("help-console", "Console Guide", "System Overview, App Carousel, Quick Actions, Hidden Dock and Notification Center", "X  OPEN"),
                    action("help-login", "Login & Security", "Controller combinations, password fallback, lockouts and Automatic Login protection", "X  OPEN"),
                    section("Apps"),
                    action("help-apps", "App Controls", "Open, resume, Leave Running, exit and controller-first navigation", "X  OPEN"),
                    action("help-terminal", "Terminal Guide", "Shared PTY, Virtual Keyboard, snippets, web mirror and Developer Mode", "X  OPEN"),
                    action("help-files-storage", "Files & Storage", "File Manager operations, Storage safety, encryption, formatting and backups", "X  OPEN"),
                    action("help-games", "Games Guide", "ROM cards, emulator installation, controller passthrough and the three-second exit hold", "X  OPEN"),
                    action("help-services", "Docker, Logs & Media", "Manage containers, inspect logs and optimize compatible media", "X  OPEN"),
                    section("System & Recovery"),
                    action("help-developer", "Developer Mode", "What it unlocks, why it is dangerous and which controls remain protected", "X  OPEN"),
                    action("help-network", "Network Troubleshooting", "Wi-Fi, Ethernet, DNS, Tailscale and remote-service checks", "X  OPEN"),
                    action("help-update-recovery", "Updates, Backup & Recovery", "Signed updates, recovery points, backups, secure reset and clean reinstall", "X  OPEN"),
                    action("help-troubleshooting", "Troubleshooting Checklist", "A controller-first checklist for app, service, storage, display and power problems", "X  OPEN"),
                    section("Support"),
                    action("diagnostics-run-full", "Run Diagnostics", "Run real system checks before exporting a support bundle", "X  RUN"),
                    action("diagnostics-export", "Export Support Bundle", "Create a redacted support archive for troubleshooting", "X  EXPORT")]
        } else if (id === "about") {
            var si = settingsBackend ? settingsBackend.systemInfo : ({})
            rows = [section("NeutronOS"),
                    special("about-neutron", "NeutronOS", "Controller-first Linux operating environment", "Gemini 0.5 candidate"),
                    info("Edition", "Installed release edition", "Gemini"),
                    info("Debian", "Linux distribution base", String(si.prettyProductName || "Debian")),
                    info("Qt", "Application framework", String(si.qtVersion || "Qt 6")),
                    section("Hardware")]
            if (si.isRaspberryPi === true)
                rows.push(special("pi-device", "Device", "Detected Raspberry Pi hardware", String(si.model || "Raspberry Pi")))
            else
                rows.push(info("Device", "Detected hardware", String(si.model || "Linux device")))
            rows.push(info("Architecture", "CPU architecture", String(si.architecture || "x86_64")))
            rows.push(info("Memory", "Installed system memory", String(si.memory || "Unavailable")))
            rows.push(info("Kernel", "Running Linux kernel", String(si.kernel || "")))
            rows.push(info("Boot Storage", "Root filesystem capacity", String(si.rootTotal || "") + " total • " + String(si.rootFree || "") + " available"))
            rows.push(section("Support"))
            rows.push(action("system-report", "System Report", "Verify CPU, RAM, storage, peripherals and security integrity", "X  VERIFY"))
            rows.push(action("help", "Help Center", "Open the full NeutronOS guide", "X  OPEN"))
            rows.push(info("Build Identity", "Local machine identifier", String(si.machineId || "Unavailable")))
        }
        return rows
    }

    function refreshPage() {
        pageModel.clear()
        // Patch 37: clear both concrete ListModels before rebuilding the
        // selected page. Performance and Advanced no longer use a JS array.
        developerPageModel.clear()
        var source = []
        if (searchActive) {
            var query = searchText.trim().toLowerCase()
            for (var c = 0; c < categories.length; c++) {
                var categoryRows = allRowsForCategory(categories[c].id)
                for (var r = 0; r < categoryRows.length; r++) {
                    var candidate = categoryRows[r]
                    if (candidate.kind === "section" || candidate.kind === "storage")
                        continue
                    var haystack = (String(candidate.title || "") + " " + String(candidate.detail || "") + " " + categories[c].title + " " + String(candidate.key || "") + " " + String(candidate.action || "")).toLowerCase()
                    if (haystack.indexOf(query) >= 0) {
                        var copy = normalizedPageEntry(candidate)
                        copy.detail = categories[c].title + " › " + String(candidate.detail || "")
                        if (categoryLocked(categories[c].id))
                            copy.locked = true
                        pageModel.append(copy)
                    }
                }
            }
        } else {
            try {
                var criticalId = currentCategoryId()
                if (criticalId === "update-recovery" || criticalId === "backup-restore" ||
                        criticalId === "performance" || criticalId === "advanced")
                    source = stableCriticalRows(criticalId)
                else
                    source = allRowsForCategory(criticalId)
            } catch (pageError) {
                console.error("[Settings] Failed to build " + currentCategoryId() + ": " + pageError)
                source = [warning("Settings Page Error", "This page could not be generated. Return to the category list and try again."),
                          info("Category", "Failed settings category", currentCategoryId().toUpperCase())]
            }
            if (developerPageActive) {
                var developerLocked = categoryLocked(activeCategoryId)
                for (var developerIndex = 0; developerIndex < source.length; developerIndex++) {
                    var developerEntry = normalizedPageEntry(source[developerIndex])
                    if (developerLocked && developerEntry.kind !== "section" && developerEntry.kind !== "warning" && developerEntry.kind !== "info")
                        developerEntry.locked = true
                    developerPageModel.append(developerEntry)
                }
            } else {
                var pageIsLocked = categoryLocked(categories[sidebarIndex].id)
                for (var i = 0; i < source.length; i++) {
                    var pageEntry = normalizedPageEntry(source[i])
                    if (pageIsLocked && pageEntry.kind !== "section" && pageEntry.kind !== "warning")
                        pageEntry.locked = true
                    pageModel.append(pageEntry)
                }
            }
        }
        if (!developerPageActive && pageModel.count === 0)
            pageModel.append(normalizedPageEntry(warning("No Settings Rows", "The selected category returned no visible settings.")))
        contentList.currentIndex = firstSelectableIndex(0)
        if (contentList.currentIndex >= 0)
            contentList.positionViewAtIndex(contentList.currentIndex, ListView.Contain)
        if (developerPageActive) {
            developerPageIndex = firstSelectableDeveloperIndex(0)
            developerContentList.currentIndex = developerPageIndex
            if (developerPageIndex >= 0)
                developerContentList.positionViewAtIndex(developerPageIndex, ListView.Contain)
        }
    }

    function developerRowAt(index) {
        if (index < 0 || index >= developerPageModel.count)
            return null
        return developerPageModel.get(index)
    }

    function developerRowLocked(row) {
        if (!row || developerModeEnabled)
            return false
        return row.kind !== "section" && row.kind !== "warning" && row.kind !== "info"
    }

    function isDeveloperSelectable(index) {
        var row = developerRowAt(index)
        return row && row.selectable !== false && row.kind !== "section"
    }

    function firstSelectableDeveloperIndex(preferred) {
        if (developerPageModel.count <= 0)
            return -1
        var start = Math.max(0, Math.min(developerPageModel.count - 1, preferred < 0 ? 0 : preferred))
        if (isDeveloperSelectable(start))
            return start
        for (var i = start + 1; i < developerPageModel.count; i++) if (isDeveloperSelectable(i)) return i
        for (var j = start - 1; j >= 0; j--) if (isDeveloperSelectable(j)) return j
        return -1
    }

    function isSelectable(index) {
        if (index < 0 || index >= pageModel.count)
            return false
        var item = pageModel.get(index)
        return item.selectable !== false && item.kind !== "section"
    }

    function firstSelectableIndex(preferred) {
        if (pageModel.count <= 0)
            return -1
        var start = Math.max(0, Math.min(pageModel.count - 1, preferred < 0 ? 0 : preferred))
        if (isSelectable(start))
            return start
        for (var i = start + 1; i < pageModel.count; i++) if (isSelectable(i)) return i
        for (var j = start - 1; j >= 0; j--) if (isSelectable(j)) return j
        return -1
    }

    function moveContent(delta) {
        if (developerPageActive) {
            if (developerPageModel.count <= 0)
                return
            var devIndex = developerPageIndex < 0 ? 0 : developerPageIndex
            for (var devCount = 0; devCount < developerPageModel.count; devCount++) {
                devIndex = (devIndex + delta + developerPageModel.count) % developerPageModel.count
                if (isDeveloperSelectable(devIndex)) {
                    developerPageIndex = devIndex
                    developerContentList.currentIndex = devIndex
                    developerContentList.positionViewAtIndex(devIndex, ListView.Contain)
                    return
                }
            }
            return
        }
        if (pageModel.count <= 0)
            return
        var index = contentList.currentIndex
        if (index < 0)
            index = 0
        for (var count = 0; count < pageModel.count; count++) {
            index = (index + delta + pageModel.count) % pageModel.count
            if (isSelectable(index)) {
                contentList.currentIndex = index
                contentList.positionViewAtIndex(index, ListView.Contain)
                return
            }
        }
    }

    function changeCategory(delta) {
        sidebarIndex = (sidebarIndex + delta + categories.length) % categories.length
        sidebarList.currentIndex = sidebarIndex
        sidebarList.positionViewAtIndex(sidebarIndex, ListView.Contain)
        searchText = ""
        refreshPage()
    }

    function cycleRow(row, delta) {
        var options = row.options || []
        if (options.length <= 0)
            return
        var current = String(rowCurrentValue(row)).toLowerCase()
        var index = 0
        for (var i = 0; i < options.length; i++) {
            if (String(options[i]).toLowerCase() === current) { index = i; break }
        }
        index = (index + delta + options.length) % options.length
        var next = options[index]
        if (row.key === "theme.mode") {
            settingsBackend.setThemeMode(String(next))
        } else if (row.key === "dashboard.defaultTab" && dashboardLayoutBackend) {
            dashboardLayoutBackend.setDefaultTab(String(next))
            statusMessage = "Default Dashboard tab changed for this user."
            statusError = false
        } else if (row.key === "dashboard.homeTab" && dashboardLayoutBackend) {
            dashboardLayoutBackend.setHomeTab(String(next))
            statusMessage = "Circle x5 Home Dashboard destination changed."
            statusError = false
        } else if (row.key === "controller.inputProfile" && controllerBackend) {
            controllerBackend.setInputProfile(String(next))
            statusMessage = "Controller input profile changed to " + String(next).toUpperCase() + "."
            statusError = false
        } else if (row.key === "backup.profile") {
            if (!backupRestoreBackend) {
                statusMessage = "Backup & Restore backend is unavailable."
                statusError = true
                return
            }
            backupRestoreBackend.setProfile(String(next))
            statusMessage = "Backup profile changed to " + String(next).toUpperCase() + "."
            statusError = false
        } else if (row.key === "update.channel") {
            if (!updateRecoveryBackend) {
                statusMessage = "Update & Recovery backend is unavailable."
                statusError = true
                return
            }
            if (String(next) === "developer" && !developerModeEnabled) {
                statusMessage = "Enable Developer Mode before selecting the Developer update channel."
                statusError = true
                return
            }
            updateRecoveryBackend.setChannel(String(next))
            statusMessage = "Update channel changed to " + String(next).toUpperCase() + ". Run Check for NeutronOS Update to refresh availability."
            statusError = false
        } else if (row.key === "display.uiScale" && coreBackend) {
            statusError = !coreBackend.setUiScale(String(next))
            statusMessage = statusError ? "UI Scale change was rejected." : "UI Scale saved; it applies consistently after logout."
        } else if (row.key === "display.adaptiveDashboard" && coreBackend) {
            statusError = !coreBackend.setAdaptiveDashboard(String(next))
            statusMessage = statusError ? "Adaptive Dashboard change was rejected." : "Adaptive Dashboard changed without rewriting the saved layout."
        } else if (row.key === "notifications.dndMode" && coreBackend) {
            statusError = !coreBackend.setDndMode(String(next))
            if (!statusError && typeof notificationManager !== "undefined") notificationManager.setDndMode(String(next))
            statusMessage = statusError ? "DND mode was rejected." : "Do Not Disturb changed; critical security events still bypass it."
        } else {
            settingsBackend.queueChange(row.key, next, row.applyMode || "apply")
        }
        refreshPage()
    }

    function adjustSlider(row, delta) {
        var current = Number(rowCurrentValue(row))
        if (isNaN(current)) current = Number(row.value || 0)
        var step = Number(row.step || 1)
        var next = Math.max(Number(row.minimum || 0), Math.min(Number(row.maximum || 100), current + delta * step))
        if (row.key === "controller.deadzone" && controllerBackend) {
            controllerBackend.setStickDeadZonePercent(next)
            statusMessage = "Stick dead zone set to " + next + "%."
            statusError = false
        } else if (row.key === "controller.triggerThreshold" && controllerBackend) {
            controllerBackend.setTriggerThresholdPercent(next)
            statusMessage = "Trigger threshold set to " + next + "%."
            statusError = false
        } else {
            settingsBackend.queueChange(row.key, next, row.applyMode || "apply")
        }
        refreshPage()
    }

    function automaticLoginEnabled() {
        return settingValue("user.autoLogin", false) === true
    }

    function highPriorityAuthorized() {
        return !automaticLoginEnabled() || (securityBackend &&
               typeof securityBackend.highPriorityAuthorizationValidFor === "function" &&
               securityBackend.highPriorityAuthorizationValidFor("settings"))
    }

    function highPrioritySettingKey(key) {
        var value = String(key || "")
        return value.indexOf("performance.") === 0 || value.indexOf("advanced.") === 0 ||
               value === "display.gpuMemory" || value === "system.bootTarget" ||
               value === "interfaces.ssh" || value === "interfaces.vnc" ||
               value === "interfaces.spi" || value === "interfaces.i2c" ||
               value === "interfaces.serial"
    }

    function highPriorityActionId(actionId) {
        var id = String(actionId || "")
        return id === "restart-shell" || id === "reboot" || id === "shutdown" ||
               id === "install-updates" || id === "expand-filesystem" ||
               id === "clear-cache" || id === "clear-history" ||
               id === "validate-boot" || id === "safe-mode" ||
               id === "update-install" || id === "debian-install" ||
               id === "update-rollback" || id === "update-repair" ||
               id === "update-safe-mode" || id === "update-cancel-safe-mode" ||
               id === "backup-restore" || id === "backup-delete" ||
               id === "backup-wipe-data" || id === "backup-clean-reinstall"
    }

    function requestProtected(kind, actionName, data) {
        pendingProtectedKind = kind
        pendingProtectedAction = actionName || ""
        pendingProtectedData = data || ({})
        if (highPriorityAuthorized()) {
            executeProtectedPending()
            return
        }
        openKeyboard("highPriorityPassword", "", "Confirm Login Password")
        statusMessage = "Enter the active Linux login password to continue."
        statusError = false
    }

    function executeProtectedPending() {
        var kind = pendingProtectedKind
        var actionName = pendingProtectedAction
        var data = pendingProtectedData
        pendingProtectedKind = ""
        pendingProtectedAction = ""
        pendingProtectedData = ({})
        if (kind === "rowAction") { runRowAction(actionName, true); return }
        if (kind === "toggle") {
            settingsBackend.queueChange(String(data.key || ""), data.value, String(data.applyMode || "apply"))
            // NEUTRONOS_X_APPLY_SETTINGS_V1
            applyPendingWithAuthorization()
            refreshPage()
            return
        }
        if (kind === "apply") {
            var applied = settingsBackend.applyPending()
            statusMessage = settingsBackend.lastMessage
            statusError = !applied
            refreshPage()
        }
    }

    function applyPendingWithAuthorization() {
        if (!settingsBackend || settingsBackend.pendingCount <= 0)
            return
        var changes = settingsBackend.pendingChanges || ({})
        var protectedChange = false
        for (var key in changes) {
            if (highPrioritySettingKey(key)) { protectedChange = true; break }
        }
        if (protectedChange) {
            requestProtected("apply", "", {})
            return
        }
        var applied = settingsBackend.applyPending()
        statusMessage = settingsBackend.lastMessage
        statusError = !applied
        refreshPage()
    }

    function activateCurrent() {
        if (developerPageActive) {
            var devRow = developerRowAt(developerPageIndex)
            if (!devRow)
                return
            if (developerRowLocked(devRow)) {
                statusMessage = "Enable Developer Mode to unlock this control. The page remains visible for reference."
                statusError = true
                return
            }
            activateRow(devRow, developerPageIndex)
            return
        }
        if (contentList.currentIndex < 0 || contentList.currentIndex >= pageModel.count)
            return
        activateRow(pageModel.get(contentList.currentIndex), contentList.currentIndex)
    }

    function openPhase1Edit(row) {
        if (!row)
            return false
        var target = String(row.target || row.key || "")
        var field = ""
        var title = String(row.title || "Edit Setting")
        var subtitle = String(row.detail || "")
        var initial = String(rowCurrentValue(row) || "")
        var secret = false

        if (target === "displayName") field = "phase1DisplayName"
        else if (target === "tagline") field = "phase1Tagline"
        else if (target === "password") { field = "phase1Password"; initial = ""; secret = true }
        else if (target === "hostname") field = "phase1Hostname"
        else if (target === "deviceName") field = "phase1DeviceName"
        else return false

        // Simple text edits use the unified keyboard/text-entry panel directly.
        // The Phase 1 form remains reserved for multi-step flows such as Add User.
        openKeyboard(field, initial, title)
        return true
    }

    function directoryTreeSegments(pathValue) {
        var raw = String(pathValue || "").trim()
        var result = [{ name: "/", depth: 0 }]
        if (raw.length <= 0 || raw === "/")
            return result
        var parts = raw.split("/")
        var depth = 1
        for (var i = 0; i < parts.length; ++i) {
            var part = String(parts[i] || "").trim()
            if (part.length <= 0)
                continue
            result.push({ name: part, depth: depth })
            depth += 1
        }
        return result
    }

    function activateRow(row, index) {
        if (!row || row.locked === true) {
            statusMessage = "Enable Developer Mode to access this setting."
            statusError = true
            return
        }
        if (row.kind === "toggle") {
            var nextToggleValue = !(rowCurrentValue(row) === true)
            if (row.key === "dashboard.legacyAvailable" && dashboardLayoutBackend) {
                dashboardLayoutBackend.setLegacyAvailable(nextToggleValue)
                statusMessage = nextToggleValue ? "Legacy Dashboard is available for this user." : "Legacy Dashboard hidden; saved carousel state was preserved."
                statusError = false
                refreshPage()
                return
            }
            if (row.key === "backup.includeRoms" && backupRestoreBackend) {
                backupRestoreBackend.setIncludeRoms(nextToggleValue)
                statusMessage = nextToggleValue ? "Game ROMs will be included in new backups and secure reset." : "Game ROMs will be excluded from new backups and preserved during secure reset."
                statusError = false
                refreshPage()
                return
            }
            if (row.key === "backup.preserveUserData" && backupRestoreBackend) {
                backupRestoreBackend.setPreserveUserData(nextToggleValue)
                statusMessage = nextToggleValue ? "Clean reinstall will preserve user data." : "Clean reinstall will remove user data."
                statusError = !nextToggleValue
                refreshPage()
                return
            }
            if (row.key === "user.autoLogin" && nextToggleValue === true) {
                autoLoginWarningModal.open()
                return
            }
            if (row.key === "user.autoLogin" && nextToggleValue === false && securityBackend &&
                    typeof securityBackend.clearHighPriorityAuthorization === "function")
                securityBackend.clearHighPriorityAuthorization()
            if (highPrioritySettingKey(row.key)) {
                requestProtected("toggle", "", { key: row.key, value: nextToggleValue, applyMode: row.applyMode || "apply" })
                return
            }
            settingsBackend.queueChange(row.key, nextToggleValue, row.applyMode || "apply")
            applyPendingWithAuthorization()
            refreshPage()
            return
        }
        if (row.kind === "choice") {
            cycleRow(row, 1)
            if (settingsBackend && settingsBackend.pendingCount > 0)
                applyPendingWithAuthorization()
            return
        }
        if (row.kind === "slider") {
            adjustSlider(row, 1)
            if (settingsBackend && settingsBackend.pendingCount > 0)
                applyPendingWithAuthorization()
            return
        }
        if (row.kind === "edit") {
            if (openPhase1Edit(row))
                return
            openKeyboard(row.target || row.key, String(rowCurrentValue(row) || ""), row.title)
            return
        }
        if (row.kind === "link") { launchApp(row.appId); return }
        if (row.kind === "storage") {
            detailsData = { title: String(row.deviceData.name || "Storage Device"), detail: String(row.deviceData.mount || ""), body: "Used: " + String(row.deviceData.used || "") + "\nAvailable: " + String(row.deviceData.free || "") + "\nFilesystem: " + String(row.deviceData.filesystem || "Unknown") + "\nFiles analyzed: " + String(row.deviceData.fileCount || 0) + "\n\nFormatting, SMART diagnostics, repair and boot-drive cloning live in the separate Storage Utility app." }
            detailsVisible = true
            return
        }
        if (row.kind === "info" || row.kind === "warning") {
            var visualType = row.title === "Current Role" ? "role"
                           : row.title === "Home Directory" ? "homeDirectory" : ""
            detailsData = {
                title: String(row.title || "Setting Details"),
                detail: String(row.valueText || ""),
                body: String(row.detail || "No additional details are available for this setting."),
                visualType: visualType
            }
            detailsVisible = true
            forceActiveFocus()
            return
        }
        if (row.kind === "special") {
            runRowAction(row.action)
            return
        }
        if (row.kind === "action") {
            if (row.danger === true && armedRow !== index) {
                armedRow = index
                statusMessage = "Press X again to confirm " + row.title + "."
                statusError = true
                armTimer.restart()
                return
            }
            armedRow = -1
            runRowAction(row.action)
        }
    }

    Timer { id: armTimer; interval: 4000; repeat: false; onTriggered: root.armedRow = -1 }
    Timer { id: aboutTapResetTimer; interval: 1300; repeat: false; onTriggered: root.aboutTapCount = 0 }
    Timer { id: easterEggTimer; interval: 10000; repeat: false; onTriggered: { root.easterEggVisible = false; root.forceActiveFocus() } }

    function toggleThemeFromSquare() {
        if (!settingsBackend)
            return
        settingsBackend.setThemeMode(lightMode ? "dark" : "light")
        statusMessage = lightMode ? "Dark mode enabled." : "Light mode enabled."
        statusError = false
        refreshPage()
    }

    function registerAboutTap() {
        var now = Date.now()
        if (now - lastAboutTapMs > 1300)
            aboutTapCount = 0
        lastAboutTapMs = now
        aboutTapCount++
        aboutTapResetTimer.restart()
        statusMessage = aboutTapCount < 5 ? "NeutronOS • " + aboutTapCount + "/5" : "Mercury Founders Edition unlocked."
        statusError = false
        if (aboutTapCount >= 5) {
            aboutTapCount = 0
            aboutTapResetTimer.stop()
            easterEggVisible = true
            easterEggTimer.restart()
            if (controllerBackend && typeof controllerBackend.hapticSuccess === "function")
                controllerBackend.hapticSuccess()
        }
    }

    function buttonTestDefinitions() {
        return [
            { id: "up", label: "D-Pad Up" }, { id: "down", label: "D-Pad Down" },
            { id: "left", label: "D-Pad Left" }, { id: "right", label: "D-Pad Right" },
            { id: "primary", label: "X / Cross" }, { id: "cancel", label: "O / Circle" },
            { id: "secondary", label: "Square" }, { id: "context", label: "Triangle" },
            { id: "l1", label: "L1" }, { id: "r1", label: "R1" },
            { id: "l2", label: "L2" }, { id: "r2", label: "R2" },
            { id: "l3", label: "L3" }, { id: "r3", label: "R3" },
            { id: "system", label: "Options / Start" }, { id: "quick", label: "Share / Select" },
            { id: "home", label: "PS / Home" }, { id: "touchpad", label: "Touchpad Click" },
            { id: "left_stick", label: "Left Stick Motion" }, { id: "right_stick", label: "Right Stick Motion" }
        ]
    }

    function startButtonTest() {
        buttonTestModel.clear()
        var definitions = buttonTestDefinitions()
        for (var i = 0; i < definitions.length; i++)
            buttonTestModel.append({ inputId: definitions[i].id, label: definitions[i].label, received: false, missed: false })
        buttonTestFinished = false
        buttonTestReceivedTotal = 0
        buttonTestLastSystemMs = 0
        buttonTestVisible = true
        statusMessage = "Press every controller input. Press Options twice to finish early."
        statusError = false
        forceActiveFocus()
    }

    function normalizeTestButton(button) {
        var value = normalizeAction(button)
        var raw = String(button || "").toLowerCase()
        if (raw.indexOf("touchpad") >= 0 || raw === "touch") return "touchpad"
        if (raw === "select" || raw === "share" || raw === "create") return "quick"
        if (raw === "ps" || raw === "guide" || raw === "playstation") return "home"
        return value
    }

    function buttonTestIndex(inputId) {
        for (var i = 0; i < buttonTestModel.count; i++) {
            if (buttonTestModel.get(i).inputId === inputId)
                return i
        }
        return -1
    }

    function buttonTestReceivedCount() {
        var count = 0
        for (var i = 0; i < buttonTestModel.count; i++)
            if (buttonTestModel.get(i).received === true) count++
        return count
    }

    function markButtonTest(button) {
        if (!buttonTestVisible || buttonTestFinished)
            return false
        var inputId = normalizeTestButton(button)
        var index = buttonTestIndex(inputId)
        if (index < 0)
            return false
        if (buttonTestModel.get(index).received !== true) {
            buttonTestModel.setProperty(index, "received", true)
            buttonTestModel.setProperty(index, "missed", false)
            buttonTestReceivedTotal++
            if (controllerBackend && typeof controllerBackend.hapticNavigation === "function")
                controllerBackend.hapticNavigation()
        }
        if (buttonTestReceivedCount() >= buttonTestModel.count)
            buttonTestFinished = true
        return true
    }

    function markStickTest(stick, x, y) {
        if (!buttonTestVisible || buttonTestFinished)
            return
        if (Math.max(Math.abs(Number(x)), Math.abs(Number(y))) < 45)
            return
        var name = String(stick || "").toLowerCase()
        markButtonTest(name.indexOf("right") >= 0 ? "right_stick" : "left_stick")
    }

    function finishButtonTest() {
        for (var i = 0; i < buttonTestModel.count; i++) {
            if (buttonTestModel.get(i).received !== true)
                buttonTestModel.setProperty(i, "missed", true)
        }
        buttonTestFinished = true
    }

    function closeButtonTest() {
        buttonTestVisible = false
        buttonTestFinished = false
        buttonTestReceivedTotal = 0
        forceActiveFocus()
    }

    function openCategoryById(categoryId) {
        for (var index = 0; index < categories.length; index++) {
            if (categories[index].id === categoryId) {
                sidebarIndex = index
                focusZone = 1
                Qt.callLater(function() {
                    refreshPage()
                    contentList.currentIndex = firstSelectableIndex(0)
                    contentList.positionViewAtIndex(contentList.currentIndex, ListView.Contain)
                    forceActiveFocus()
                })
                return true
            }
        }
        return false
    }

    function showUpdateRecoveryText(title, subtitle, body) {
        updateRecoveryTextModal.openModal(title, subtitle, body)
    }

    function runUpdateRecoveryAction(actionId) {
        var updateAction = actionId === "update-configure-repository" ||
                           actionId === "update-release-notes" ||
                           actionId === "update-trust-details" ||
                           actionId === "update-integrity-details" ||
                           actionId === "update-history" ||
                           actionId === "update-check" || actionId === "check-updates" ||
                           actionId === "update-download" || actionId === "update-install" ||
                           actionId === "update-cancel" || actionId === "debian-check" ||
                           actionId === "debian-install" || actionId === "install-updates" ||
                           actionId === "update-verify" || actionId === "update-create-recovery" ||
                           actionId === "update-rollback" || actionId === "update-repair" ||
                           actionId === "update-safe-mode" || actionId === "safe-mode" ||
                           actionId === "update-cancel-safe-mode" || actionId === "update-clear-cache"
        if (!updateAction)
            return false
        if (!updateRecoveryBackend) {
            statusMessage = "Update & Recovery backend is unavailable."
            statusError = true
            return true
        }

        var started = false
        if (actionId === "update-configure-repository") {
            if (!developerModeEnabled) {
                statusMessage = "Enable Developer Mode to change the update repository."
                statusError = true
                return true
            }
            openKeyboard("updateManifestUrl", String(updateRecoveryBackend.manifestUrl || ""), "Update Repository Manifest URL")
            return true
        }
        if (actionId === "update-release-notes") {
            showUpdateRecoveryText("NEUTRONOS RELEASE NOTES",
                                   String(updateRecoveryBackend.availableVersion || "No update selected"),
                                   String(updateRecoveryBackend.releaseNotes || "No release notes were provided by the selected update manifest."))
            return true
        }
        if (actionId === "update-trust-details") {
            showUpdateRecoveryText("UPDATE TRUST & OFFLINE INBOX",
                                   updateRecoveryBackend.trustedKeyInstalled === true ? "TRUSTED GEMINI KEY INSTALLED" : "TRUSTED GEMINI KEY REQUIRED",
                                   "NeutronOS accepts update manifests only through HTTPS or the local update inbox.\n\n" +
                                   "Trusted public key:\n/etc/neutronos/keys/neutronos-release.gpg\nPinned NeutronOS release identity\n\n" +
                                   "Local inbox:\n" + String(updateRecoveryBackend.localInboxPath || "~/NeutronOS/updates/inbox") + "\n\n" +
                                   "A manifest must identify NeutronOS Gemini, the selected channel, version, package URL, SHA-256 digest and an OpenPGP release signature. The private signing key must never be stored on the NeutronOS device.")
            return true
        }
        if (actionId === "update-integrity-details") {
            showUpdateRecoveryText("INSTALLATION INTEGRITY",
                                   String(updateRecoveryBackend.integritySummary || "Not verified"),
                                   String(updateRecoveryBackend.integrityReportText()))
            return true
        }
        if (actionId === "update-history") {
            showUpdateRecoveryText("UPDATE & RECOVERY HISTORY",
                                   "MOST RECENT OPERATIONS",
                                   String(updateRecoveryBackend.historyText()))
            return true
        }

        if (actionId === "update-check" || actionId === "check-updates")
            started = updateRecoveryBackend.checkForUpdates(String(updateRecoveryBackend.channel || "stable"))
        else if (actionId === "update-download")
            started = updateRecoveryBackend.downloadAvailableUpdate()
        else if (actionId === "update-install")
            started = updateRecoveryBackend.prepareAvailableUpdateForInstall()
        else if (actionId === "update-cancel")
            started = updateRecoveryBackend.cancelCurrentOperation()
        else if (actionId === "debian-check")
            started = updateRecoveryBackend.checkDebianUpdates()
        else if (actionId === "debian-install" || actionId === "install-updates")
            started = updateRecoveryBackend.installDebianUpdates()
        else if (actionId === "update-verify")
            started = updateRecoveryBackend.verifyInstallation()
        else if (actionId === "update-create-recovery")
            started = updateRecoveryBackend.createRecoveryPoint("manual")
        else if (actionId === "update-rollback")
            started = updateRecoveryBackend.rollbackLastUpdate()
        else if (actionId === "update-repair")
            started = updateRecoveryBackend.repairInstallation()
        else if (actionId === "update-safe-mode" || actionId === "safe-mode")
            started = updateRecoveryBackend.prepareSafeMode()
        else if (actionId === "update-cancel-safe-mode")
            started = updateRecoveryBackend.cancelSafeMode()
        else if (actionId === "update-clear-cache")
            started = updateRecoveryBackend.clearUpdateCache()
        else
            return false

        statusMessage = String(updateRecoveryBackend.lastMessage || updateRecoveryBackend.status ||
                               (started ? "Operation started." : "The operation could not start."))
        statusError = !started
        refreshPage()
        return true
    }

    function runBackupRestoreAction(actionId) {
        var backupAction = actionId === "backup-configure-destination" ||
                           actionId === "backup-create" || actionId === "backup-list" || actionId === "backup-details" ||
                           actionId === "backup-verify" || actionId === "backup-restore" ||
                           actionId === "backup-delete" || actionId === "backup-reinstall-details" ||
                           actionId === "backup-clean-reinstall" || actionId === "backup-wipe-details" ||
                           actionId === "backup-wipe-data" || actionId === "backup-history" ||
                           actionId === "backup-cancel"
        if (!backupAction)
            return false
        if (!backupRestoreBackend) {
            statusMessage = "Backup & Restore backend is unavailable."
            statusError = true
            return true
        }
        var started = false
        if (actionId === "backup-configure-destination") {
            openKeyboard("backupDestination", String(backupRestoreBackend.destinationPath || ""), "Backup Destination")
            return true
        }
        if (actionId === "backup-list" || actionId === "backup-details") {
            backupRestorePointsModal.openModal()
            return true
        }
        if (actionId === "backup-history") {
            showUpdateRecoveryText("BACKUP & RESTORE HISTORY", "MOST RECENT OPERATIONS", String(backupRestoreBackend.historyText()))
            return true
        }
        if (actionId === "backup-reinstall-details") {
            showUpdateRecoveryText("CLEAN NEUTRONOS REINSTALL", backupRestoreBackend.cleanReinstallReady === true ? "VERIFIED FULL PACKAGE READY" : "FULL-INSTALL PACKAGE REQUIRED",
                                   "Clean reinstall replaces the NeutronOS application source, QML shell, services, scripts and compiled binary. It does not reinstall the Debian base system or repartition the boot drive.\n\nThe package must first be downloaded and signature-verified in Update & Recovery and its manifest must declare fullInstall=true.\n\nPreserve User Data keeps profiles, app state, backups, game ROMs/cards and user artwork. Turn it off for a clean first-run state.\n\nTo continue, NeutronOS will require the exact phrase: REINSTALL NEUTRONOS GEMINI")
            return true
        }
        if (actionId === "backup-wipe-details") {
            showUpdateRecoveryText("SECURE DATA RESET", "BEST-EFFORT FLASH STORAGE WIPE",
                                   "This removes NeutronOS profiles, app state, settings, backup archives, user artwork and security credentials. When Include Game ROMs is enabled, ROMs are removed too.\n\nSmall sensitive files are overwritten before deletion where supported. SD cards and SSDs use wear-leveling, so offline full-device discard/reimage is required for a forensic-erasure guarantee.\n\nTo continue, NeutronOS will require the exact phrase: WIPE MY NEUTRONOS DATA")
            return true
        }
        if (actionId === "backup-wipe-data") {
            openKeyboard("backupWipePhrase", "", "Type WIPE MY NEUTRONOS DATA")
            return true
        }
        if (actionId === "backup-clean-reinstall") {
            if (backupRestoreBackend.cleanReinstallReady !== true) {
                statusMessage = "Download and signature-verify a full-install Gemini package in Update & Recovery first."
                statusError = true
                return true
            }
            openKeyboard("backupReinstallPhrase", "", "Type REINSTALL NEUTRONOS GEMINI")
            return true
        }
        if (actionId === "backup-create")
            started = backupRestoreBackend.createBackup("manual")
        else if (actionId === "backup-verify")
            started = backupRestoreBackend.verifyLatestBackup()
        else if (actionId === "backup-restore")
            started = backupRestoreBackend.restoreLatestBackup()
        else if (actionId === "backup-delete")
            started = backupRestoreBackend.deleteLatestBackup()
        else if (actionId === "backup-cancel")
            started = backupRestoreBackend.cancelCurrentOperation()
        statusMessage = String(backupRestoreBackend.lastMessage || backupRestoreBackend.status || (started ? "Operation started." : "Operation could not start."))
        statusError = !started
        refreshPage()
        return true
    }

    function helpTopic(actionId) {
        var topics = {
            "help-controller-map": { title: "Controller Map", detail: "Controller First", body: "D-pad / Left Stick: navigate\nRight Stick: scroll or move secondary selection\nX: primary action or arm/confirm\nO: back or open the app exit modal\nTriangle: context/details\nSquare: secondary action, theme or reorder depending on the app\nStart/Settings: app options; hold three seconds during games to return\nPS/Home: global logout from Console or apps\nL1 + R1: Developer Mode\nR2/L2: app-specific shortcuts and Virtual Keyboard Caps/ABC-Symbol controls." },
            "help-console": { title: "Console Guide", detail: "Home after login", body: "System Overview shows real CPU, memory, temperature, storage and network state. Move between System Overview, Apps and Quick Actions with the D-pad. Apps open full-screen through AppHost. Hidden Dock contains protected or secondary apps. Notification Center will be added in Patch 55 and will pull down from System Overview with Up." },
            "help-login": { title: "Login & Security", detail: "Local and controller-first", body: "First login verifies the local Linux password, then creates a controller combination stored only as a salted hash. Future unlocks use the combination. Repeated failures trigger lockout. Automatic Login reduces physical-access security, so high-priority actions require the Linux password and grant a 15-minute app-scoped authorization window." },
            "help-apps": { title: "App Controls", detail: "Open, resume and leave running", body: "X opens the selected app. O opens its exit modal. Resume stays in the app. Leave Running unloads visible QML and animations while a persistent backend operation continues. Exit stops app-owned work when safe and returns to Console. Reopening an app reconnects to supported background work." },
            "help-terminal": { title: "Terminal Guide", detail: "Shared PTY", body: "Terminal uses one native PTY shared by HDMI and its authenticated web mirror. The Virtual Keyboard does not dim the terminal. R2 toggles Caps Lock and L2 switches ABC/Symbols. Developer Mode changes the shell privilege context; Terminal cannot enable Developer Mode itself." },
            "help-files-storage": { title: "Files & Storage", detail: "Safe data management", body: "File Manager supports browsing, search, Quick Look, metadata, editing, copy, move, rename, archives and authenticated encryption. Storage displays real devices, mounts, SMART data, formatting and optimization. Boot/system devices are protected from formatting. Always review deletion and formatting targets before confirming." },
            "help-games": { title: "Games Guide", detail: "ROMs and emulators", body: "Games scans qml/apps/games/roms and matches artwork from qml/apps/games/cards. X launches. Triangle opens details/settings. Square reorders. When an emulator is missing, choose a compatible runtime and confirm installation. During gameplay the controller passes to the emulator; hold Settings/Start for three seconds to return to Resume or Exit." },
            "help-services": { title: "Docker, Logs & Media", detail: "Services and media", body: "Docker starts/stops armed containers and creates containers from editable presets. Logs follows active services/containers with X or loads recent history with Triangle. Media Optimizer scans selected storage, caches FFprobe results, reports current versus recommended codecs and uses FFmpeg without overwriting the source." },
            "help-developer": { title: "Developer Mode", detail: "Use with care", body: "Developer Mode unlocks Performance, Advanced, video transcoding and other protected controls. It can bypass normal safety restrictions and can damage the system. The credential is controller-first with keyboard fallback and is stored only as a salted hash. High-priority actions can still require login-password authorization." },
            "help-network": { title: "Network Troubleshooting", detail: "Local-first checks", body: "Confirm Wi-Fi/Ethernet is enabled, inspect SSID/interface/IP/gateway, verify DNS and check Tailscale separately. Use Diagnostics for real interface and resolver checks. Logs can follow NetworkManager, Bluetooth and remote-service output. Undervoltage can also cause unstable wireless behavior." },
            "help-update-recovery": { title: "Updates, Backup & Recovery", detail: "Verified and reversible", body: "Update & Recovery accepts signed packages, verifies SHA-256 and OpenPGP release signatures, creates recovery points and supports rollback/repair. Backup & Restore creates checksummed archives, restores selected data, and provides guarded secure reset and clean NeutronOS reinstall workflows." },
            "help-troubleshooting": { title: "Troubleshooting Checklist", detail: "Start here", body: "1. Run Diagnostics.\n2. Check the red Console warning and Logs.\n3. Confirm power/throttle state.\n4. Verify storage space and mount health.\n5. Refresh controller/network hardware.\n6. Restart only the affected service or app.\n7. Create a support bundle before repair.\n8. Use Update & Recovery repair or rollback only after preserving data." }
        }
        return topics[actionId] || null
    }

    function runDiagnosticsAction(actionId) {
        if (actionId !== "diagnostics-run" && actionId !== "diagnostics-run-full" && actionId !== "diagnostics-view-report" && actionId !== "diagnostics-export")
            return false
        if (!diagnosticsBackend) { statusMessage = "Diagnostics backend is unavailable."; statusError = true; return true }
        if (actionId === "diagnostics-run" || actionId === "diagnostics-run-full") {
            diagnosticsCenter.openCenter()
            return true
        }
        if (actionId === "diagnostics-view-report") {
            showUpdateRecoveryText("SYSTEM DIAGNOSTICS", String(diagnosticsBackend.lastRun || "NOT RUN"), String(diagnosticsBackend.reportText()))
            return true
        }
        var started = actionId === "diagnostics-export" ? diagnosticsBackend.exportSupportBundle() : diagnosticsBackend.runFullDiagnostics()
        statusMessage = String(diagnosticsBackend.lastMessage || (started ? "Diagnostics started." : "Diagnostics are already running."))
        statusError = !started
        refreshPage()
        return true
    }

    function openWifiScanner() {
        // NEUTRONOS_SETTINGS_WIFI_SCAN_V1
        var scanner = wifiScanLoader.item
        if (!scanner) {
            statusMessage = "Wi-Fi scanner is still loading."
            statusError = true
            return false
        }
        scanner.networkBackend = root.networkBackend
        scanner.openModal()
        return true
    }

    function runRowAction(actionId, securityAlreadyChecked) {
        if (actionId === "timezone-browser") {
            openTimezoneBrowser()
            return
        }
        if (actionId === "wifi-scan-join") {
            openWifiScanner()
            return
        }
        if (securityAlreadyChecked !== true && highPriorityActionId(actionId)) {
            requestProtected("rowAction", actionId, {})
            return
        }
        if (actionId === "refresh-services" && coreBackend) {
            coreBackend.refresh()
            statusMessage = String(coreBackend.lastMessage || "Service inventory refreshed.")
            statusError = false
            refreshPage()
            return
        }
        if (actionId.indexOf("service-details|") === 0 && coreBackend) {
            var serviceTarget = actionId.substring(String("service-details|").length)
            var serviceList = coreBackend.services || []
            var serviceInfo = null
            for (var serviceIndex = 0; serviceIndex < serviceList.length; ++serviceIndex) {
                var candidateService = serviceList[serviceIndex] || ({})
                if (String(candidateService.unit || candidateService.path || "") === serviceTarget) {
                    serviceInfo = candidateService
                    break
                }
            }
            if (serviceInfo) {
                var serviceBody =
                    "Type: " + String(serviceInfo.kind || "service").toUpperCase() +
                    "\nIdentifier: " + String(serviceInfo.unit || serviceInfo.path || "Unavailable") +
                    "\nRuntime: " + String(serviceInfo.state || "Unavailable") +
                    "\nStartup: " + String(serviceInfo.startup || "Unavailable") +
                    "\nProtected: " + (serviceInfo.protected === true ? "YES" : "NO")
                if (String(serviceInfo.description || "").length > 0)
                    serviceBody += "\n\n" + String(serviceInfo.description)
                if (String(serviceInfo.source || "").length > 0)
                    serviceBody += "\n\nSource: " + String(serviceInfo.source)
                detailsData = {
                    title: String(serviceInfo.name || serviceTarget || "Service"),
                    detail: String(serviceInfo.kind || "service").toUpperCase() + " DETAILS",
                    body: serviceBody
                }
                detailsVisible = true
                forceActiveFocus()
            } else {
                statusMessage = "That service entry is no longer present. Refresh the inventory."
                statusError = true
            }
            return
        }
        if (actionId === "hotspot-manager") {
            hotspotManagerModal.openModal()
            return
        }
        if (actionId === "bluetooth-manager") {
            bluetoothManagerModal.openModal()
            return
        }
        if (actionId.indexOf("bluetooth-manage|") === 0) {
            bluetoothManagerModal.openModal(actionId.substring(String("bluetooth-manage|").length))
            return
        }
        if (actionId === "bluetooth-refresh" && coreBackend) {
            coreBackend.refresh(); statusMessage = String(coreBackend.lastMessage); refreshPage(); return
        }
        if (actionId.indexOf("audio-test-") === 0 && coreBackend) {
            var channel = actionId.substring(11)
            statusError = !coreBackend.testAudio(channel)
            statusMessage = statusError ? "Audio test unavailable." : "Audio " + channel + " test completed."
            return
        }
        if (actionId === "core-security-profiles" && coreBackend) {
            securityPrivacyModal.openProfiles()
            return
        }
        if (actionId === "core-security-timeline" && coreBackend) {
            securityPrivacyModal.openTimeline()
            return
        }
        if ((actionId === "core-app-permissions" || actionId === "app-permissions") && coreBackend) {
            securityPrivacyModal.openPermissions()
            return
        }
        if (actionId === "open-update-recovery") { openCategoryById("update-recovery"); return }
        if (runDiagnosticsAction(actionId)) return
        var helpData = helpTopic(actionId)
        if (helpData) { detailsData = helpData; detailsVisible = true; forceActiveFocus(); return }
        if (actionId === "controller-refresh") {
            if (controllerBackend) { controllerBackend.refreshDevices(); controllerBackend.refreshBattery(); controllerBackend.refreshControllerIdentity(); controllerBackend.refreshControllerCapabilities(); statusMessage = "Controller hardware refreshed."; statusError = false; refreshPage() }
            return
        }
        if (actionId === "controller-haptic-test") { if (controllerBackend) controllerBackend.previewVibrationPattern(String(controllerBackend.controllerVibrationPattern || "soft-pulse"), String(controllerBackend.controllerVibrationLevel || "medium")); return }
        if (actionId === "controller-reset-input") { if (controllerBackend) { controllerBackend.resetInputTuning(); statusMessage = "Controller input tuning reset to Balanced."; statusError = false; refreshPage() } return }
        if (runUpdateRecoveryAction(actionId))
            return
        if (runBackupRestoreAction(actionId))
            return
        if (actionId === "app-manager") { installedAppsModal.open(); return }
        if (actionId === "dashboard-layout") { systemOverviewManager.openManager(); return }
        if (actionId === "scan-storage") { settingsBackend.scanStorageUsage(); return }
        if (actionId === "edition") { editionModalVisible = true; forceActiveFocus(); return }
        if (actionId === "pi-device") { piModalVisible = true; forceActiveFocus(); return }
        if (actionId === "about-neutron") { registerAboutTap(); return }
        if (actionId === "system-report") {
            systemReportVisible = true
            settingsBackend.runSystemIntegrityCheck()
            forceActiveFocus()
            return
        }
        if (actionId === "button-test") { startButtonTest(); return }
        if (actionId === "console-personalization") {
            personalizationModal.open({ "username": activeUsernameValue(), "tab": 0 })
            return
        }
        if (actionId === "console-personalization-screensaver") {
            personalizationModal.open({ "username": activeUsernameValue(), "tab": 2 })
            return
        }
        if (actionId === "profile-avatar") {
            userProfileSettingsModal.open({
                "user": userBackend ? userBackend.activeUser : root.activeUser,
                "focusSection": "icon"
            })
            return
        }
        if (actionId === "controller-settings") { detailsData = { title: "Controller Center", detail: controllerBackend ? String(controllerBackend.controllerName || "Controller") : "Unavailable", body: controllerBackend ? "Profile: " + String(controllerBackend.inputProfile || "balanced").toUpperCase() + "\nStick dead zone: " + String(controllerBackend.stickDeadZonePercent || 0) + "%\nTrigger threshold: " + String(controllerBackend.triggerThresholdPercent || 0) + "%\nLightbar: " + String(controllerBackend.controllerLightBackend || "Unavailable") + " • " + String(controllerBackend.controllerLightColor || "") + "\nHaptics: " + String(controllerBackend.controllerVibrationLevel || "medium") + " • " + String(controllerBackend.controllerVibrationPattern || "soft-pulse") + "\nForce reconnect: " + (controllerBackend.forceReconnectEnabled ? "ON" : "OFF") + "\nBattery: " + (controllerBackend.controllerBatteryAvailable ? String(controllerBackend.controllerBatteryPercent) + "% " + String(controllerBackend.controllerBatteryState || "") : "Unavailable") : "Controller backend unavailable." }; detailsVisible = true; return }
        if (actionId === "controller-combo") {
            phase1SettingsModal.openCombo(
                securityCoreBackend ? securityCoreBackend.recoveryConfigured === true : false,
                securityCoreBackend ? String(securityCoreBackend.recoveryMethod || "none") : "none",
                securityBackend ? Number(securityBackend.minimumComboLength || 4) : 4,
                securityBackend ? Number(securityBackend.maximumComboLength || 15) : 15,
                15
            )
            return
        }
        if (actionId === "add-user") { phase1SettingsModal.openAddUser(); return }
        if (actionId === "screensaver-preview") { if (typeof screensaverManager !== "undefined" && screensaverManager) screensaverManager.activate(); return }
        if (actionId === "keyboard-preview") { openKeyboard("keyboardPreview", "", "Virtual Keyboard Preview"); return }
        if (actionId === "keyboard-reset") {
            var keyboardDefaults = {
                "keyboard.layout":"qwerty", "keyboard.keyScale":100, "keyboard.spacing":8,
                "keyboard.opacity":96, "keyboard.keyShape":"rounded", "keyboard.tint":"neutron",
                "keyboard.labels":"standard", "keyboard.focusStyle":"ring", "keyboard.armedStyle":"ring"
            }
            for (var keyboardKey in keyboardDefaults)
                settingsBackend.queueChange(keyboardKey, keyboardDefaults[keyboardKey], "immediate")
            var resetApplied = settingsBackend.applyPending()
            statusMessage = resetApplied ? "Virtual Keyboard defaults restored." : String(settingsBackend.lastMessage || "Keyboard reset failed.")
            statusError = !resetApplied
            refreshPage()
            return
        }
        if (actionId === "network-details") { detailsData = { title: "Network Details", detail: networkBackend ? String(networkBackend.connectionState || "Unknown") : "Unavailable", body: networkBackend ? "SSID: " + String(networkBackend.connectedSsid || "None") + "\nInterface: " + String(networkBackend.interfaceName || "") + "\nIP: " + String(networkBackend.localIp || "") + "\nGateway: " + String(networkBackend.gateway || "") + "\nTailscale: " + String(networkBackend.tailscaleIp || "") : "Network backend unavailable." }; detailsVisible = true; return }
        if (actionId === "help") { detailsData = { title: "NeutronOS Help", detail: "Controller-first operating guide", body: "Use the Help Quick Action on the Console to open the complete Help Center with Login, Console, Apps, Network, Storage, Terminal, Developer Mode and troubleshooting sections." }; detailsVisible = true; return }
        if (actionId === "service-manager") { launchApp("logs"); return }
        if (actionId === "app-permissions") {
            if (coreBackend) securityPrivacyModal.openPermissions()
            else { statusMessage = "App permissions backend is unavailable."; statusError = true }
            return
        }
        settingsBackend.runAction(actionId, {})
    }

    function launchApp(id) {
        if (!appBackend)
            return
        var data = appBackend.appById(id)
        if (!data || String(data.id || "").length === 0) {
            statusMessage = "The " + id + " app is not installed."
            statusError = true
            return
        }
        launchAppRequested(data)
    }

    function openKeyboard(target, value, title) {
        keyboardTarget = target
        keyboardBuffer = value || ""
        keyboardOpen = true
        virtualKeyboard.title = ""
        virtualKeyboard.openKeyboard(true)
        virtualKeyboard.forceActiveFocus()
    }

    function keyboardIsSecretTarget() {
        var t = String(keyboardTarget || "")
        return t === "password" || t === "wifiPassword" || t === "newUserPassword"
            || t === "highPriorityPassword" || t === "phase1Password"
            || t === "phase1UserPassword" || t === "hotspotPassword" || t === "hotspotPasswordConfirm"
    }

    function keyboardDisplayValue() {
        if (keyboardBuffer.length <= 0)
            return "TYPE HERE…"
        if (!keyboardIsSecretTarget())
            return keyboardBuffer
        var dots = ""
        for (var i = 0; i < keyboardBuffer.length; ++i)
            dots += "•"
        return dots
    }

    function keyboardTitle() {
        if (keyboardTarget === "search") return "Search Settings"
        if (keyboardTarget === "password") return "New Password"
        if (keyboardTarget === "wifiSsid") return "Wi-Fi Network Name"
        if (keyboardTarget === "wifiPassword") return "Wi-Fi Password"
        if (keyboardTarget === "newUserName") return "New Username"
        if (keyboardTarget === "newUserDisplay") return "New Display Name"
        if (keyboardTarget === "newUserPassword") return "New User Password"
        if (keyboardTarget === "highPriorityPassword") return "Confirm Login Password"
        if (keyboardTarget === "phase1DisplayName") return "Display Name"
        if (keyboardTarget === "phase1Tagline") return "Profile Tagline"
        if (keyboardTarget === "phase1Password") return "New Password"
        if (keyboardTarget === "phase1Hostname") return "Hostname"
        if (keyboardTarget === "phase1DeviceName") return "Device Display Name"
        if (keyboardTarget === "phase1RecoveryCode") return "Recovery Code"
        if (keyboardTarget === "phase1UserName") return "New Username"
        if (keyboardTarget === "phase1UserPassword") return "New User Password"
        if (keyboardTarget === "phase1UserDisplay") return "New User Display Name"
        if (keyboardTarget === "hotspotSsid") return "Hotspot SSID"
        if (keyboardTarget === "hotspotPassword") return "Hotspot Password"
        if (keyboardTarget === "hotspotPasswordConfirm") return "Confirm Hotspot Password"
        if (keyboardTarget === "updateManifestUrl") return "Update Repository Manifest URL"
        if (keyboardTarget === "backupDestination") return "Backup Destination"
        if (keyboardTarget === "backupWipePhrase") return "Confirm Secure Data Reset"
        if (keyboardTarget === "backupReinstallPhrase") return "Confirm Clean Reinstall"
        return "Edit Setting"
    }

    function closeKeyboard() {
        keyboardOpen = false
        virtualKeyboard.visibleMode = false
        forceActiveFocus()
    }

    function commitKeyboard() {
        var value = keyboardBuffer.trim()
        var target = keyboardTarget
        closeKeyboard()
        if (target === "keyboardPreview") {
            statusMessage = "Virtual Keyboard preview closed."
            statusError = false
            return
        }
        if (target === "search") {
            searchText = value
            refreshPage()
            return
        }

        if (target === "hotspotSsid" || target === "hotspotPassword" || target === "hotspotPasswordConfirm") {
            hotspotManagerModal.acceptKeyboard(target, (target === "hotspotPassword" || target === "hotspotPasswordConfirm") ? keyboardBuffer : value)
            keyboardBuffer = ""
            return
        }

        if (target === "phase1RecoveryCode") {
            if (!securityCoreBackend) {
                phase1SettingsModal.recoveryVerificationResult(false, "Recovery backend is unavailable.")
                keyboardBuffer = ""
                return
            }
            if (value.length <= 0) {
                phase1SettingsModal.recoveryVerificationResult(false, "Recovery code is required.")
                keyboardBuffer = ""
                return
            }
            phase1RecoveryPending = true
            phase1SettingsModal.comboBusy = true
            phase1SettingsModal.statusText = "VERIFYING THE ENROLLED RECOVERY CODE…"
            var recoveryStarted = securityCoreBackend.verifyRecoveryCode(value)
            keyboardBuffer = ""
            if (!recoveryStarted) {
                phase1RecoveryPending = false
                phase1SettingsModal.recoveryVerificationResult(false, "Recovery-code verification could not be started.")
            }
            return
        }

        if (target === "phase1UserName" || target === "phase1UserPassword" || target === "phase1UserDisplay") {
            phase1SettingsModal.acceptKeyboard(target, target === "phase1UserPassword" ? keyboardBuffer : value)
            keyboardBuffer = ""
            return
        }

        if (target === "phase1DisplayName") {
            if (!userBackend) {
                phase1SettingsModal.setTextResult(false, "User profile backend is unavailable.")
                return
            }
            var profilePayload = {
                displayName: value,
                profileTagline: userBackend.profileTagline,
                nameTint: userBackend.nameTint,
                accentColor: userBackend.accentColor,
                avatarFrame: userBackend.avatarFrame,
                glowStrength: userBackend.glowStrength,
                avatarId: userBackend.avatarId
            }
            var profileOk = userBackend.applyProfile(profilePayload)
            var profileMessage = profileOk ? "Display name updated." : String(userBackend.lastError || "Could not update display name.")
            phase1SettingsModal.setTextResult(profileOk, profileMessage, value)
            statusMessage = profileMessage
            statusError = !profileOk
            refreshPage()
            return
        }

        if (target === "phase1Tagline") {
            if (!userBackend) {
                phase1SettingsModal.setTextResult(false, "User profile backend is unavailable.")
                return
            }
            var taglinePayload = {
                displayName: userBackend.displayName,
                profileTagline: value,
                nameTint: userBackend.nameTint,
                accentColor: userBackend.accentColor,
                avatarFrame: userBackend.avatarFrame,
                glowStrength: userBackend.glowStrength,
                avatarId: userBackend.avatarId
            }
            var taglineOk = userBackend.applyProfile(taglinePayload)
            var taglineMessage = taglineOk ? "Profile tagline updated." : String(userBackend.lastError || "Could not update profile tagline.")
            phase1SettingsModal.setTextResult(taglineOk, taglineMessage, value)
            statusMessage = taglineMessage
            statusError = !taglineOk
            refreshPage()
            return
        }

        if (target === "phase1Password") {
            var passwordOk = settingsBackend && settingsBackend.changePassword(keyboardBuffer)
            var passwordMessage = settingsBackend
                                  ? String(settingsBackend.lastMessage || (passwordOk ? "Password changed successfully." : "Password change failed."))
                                  : "Settings backend is unavailable."
            keyboardBuffer = ""
            phase1SettingsModal.setTextResult(passwordOk, passwordMessage, "")
            statusMessage = passwordMessage
            statusError = !passwordOk
            return
        }

        if (target === "phase1Hostname" || target === "phase1DeviceName") {
            if (!settingsBackend) {
                phase1SettingsModal.setTextResult(false, "Settings backend is unavailable.")
                return
            }
            var phaseKey = target === "phase1Hostname" ? "system.hostname" : "system.deviceName"
            var phaseMode = target === "phase1Hostname" ? "reboot" : "apply"
            settingsBackend.queueChange(phaseKey, value, phaseMode)
            var phaseOk = settingsBackend.applyPending()
            var phaseMessage = String(settingsBackend.lastMessage || (phaseOk ? "Setting updated." : "Setting could not be updated."))
            phase1SettingsModal.setTextResult(phaseOk, phaseMessage, value)
            statusMessage = phaseMessage
            statusError = !phaseOk
            refreshPage()
            return
        }
        if (target === "highPriorityPassword") {
            var authOk = securityBackend &&
                         securityBackend.authorizeHighPriorityAction(activeUsernameValue(), keyboardBuffer, "settings")
            keyboardBuffer = ""
            if (!authOk) {
                statusMessage = securityBackend ? String(securityBackend.lastError || "Login password was not accepted.")
                                                : "Security backend unavailable."
                statusError = true
                pendingProtectedKind = ""
                pendingProtectedAction = ""
                pendingProtectedData = ({})
                return
            }
            statusMessage = "High-priority actions authorized for 15 minutes while Settings remains open."
            statusError = false
            executeProtectedPending()
            return
        }
        if (target === "password") {
            var ok = settingsBackend.changePassword(keyboardBuffer)
            statusMessage = settingsBackend.lastMessage
            statusError = !ok
            return
        }
        if (target === "displayName") {
            if (userBackend) {
                var payload = { displayName: value, profileTagline: userBackend.profileTagline, nameTint: userBackend.nameTint, accentColor: userBackend.accentColor, avatarFrame: userBackend.avatarFrame, glowStrength: userBackend.glowStrength, avatarId: userBackend.avatarId }
                var okProfile = userBackend.applyProfile(payload)
                statusMessage = okProfile ? "Display name updated." : String(userBackend.lastError || "Could not update display name.")
                statusError = !okProfile
                refreshPage()
            }
            return
        }
        if (target === "tagline") {
            if (userBackend) {
                var tagPayload = { displayName: userBackend.displayName, profileTagline: value, nameTint: userBackend.nameTint, accentColor: userBackend.accentColor, avatarFrame: userBackend.avatarFrame, glowStrength: userBackend.glowStrength, avatarId: userBackend.avatarId }
                var okTag = userBackend.applyProfile(tagPayload)
                statusMessage = okTag ? "Tagline updated." : String(userBackend.lastError || "Could not update tagline.")
                statusError = !okTag
                refreshPage()
            }
            return
        }
        if (target === "wifiSsid") {
            wifiSsidDraft = value
            openKeyboard("wifiPassword", "", "Wi-Fi Password")
            return
        }
        if (target === "wifiPassword") {
            var wifiOk = settingsBackend.connectWifi(wifiSsidDraft, keyboardBuffer, String(settingValue("network.wifiCountry", "US")))
            statusMessage = settingsBackend.lastMessage
            statusError = !wifiOk
            return
        }
        if (target === "newUserName") {
            newUserNameDraft = value
            openKeyboard("newUserDisplay", "", "Display Name")
            return
        }
        if (target === "newUserDisplay") {
            newUserDisplayDraft = value
            openKeyboard("newUserPassword", "", "New User Password")
            return
        }
        if (target === "newUserPassword") {
            var userOk = settingsBackend.createUser(newUserNameDraft, newUserDisplayDraft, keyboardBuffer, false)
            statusMessage = settingsBackend.lastMessage
            statusError = !userOk
            return
        }
        if (target === "updateManifestUrl") {
            if (!updateRecoveryBackend) {
                statusMessage = "Update & Recovery backend is unavailable."
                statusError = true
                return
            }
            updateRecoveryBackend.setManifestUrl(value)
            statusMessage = String(updateRecoveryBackend.lastMessage || "Update repository saved.")
            statusError = String(updateRecoveryBackend.status || "").toLowerCase().indexOf("rejected") >= 0
            refreshPage()
            return
        }

        if (target === "backupDestination") {
            if (!backupRestoreBackend) {
                statusMessage = "Backup & Restore backend is unavailable."
                statusError = true
                return
            }
            backupRestoreBackend.setDestinationPath(value)
            statusMessage = String(backupRestoreBackend.lastMessage || "Backup destination updated.")
            statusError = String(backupRestoreBackend.destinationPath || "") !== value
            refreshPage()
            return
        }
        if (target === "backupWipePhrase") {
            var wipeStarted = backupRestoreBackend && backupRestoreBackend.secureWipeUserData(keyboardBuffer)
            keyboardBuffer = ""
            statusMessage = backupRestoreBackend ? String(backupRestoreBackend.lastMessage || "Secure reset scheduled.") : "Backup & Restore backend unavailable."
            statusError = !wipeStarted
            refreshPage()
            return
        }
        if (target === "backupReinstallPhrase") {
            var reinstallStarted = backupRestoreBackend && backupRestoreBackend.cleanReinstall(keyboardBuffer)
            keyboardBuffer = ""
            statusMessage = backupRestoreBackend ? String(backupRestoreBackend.lastMessage || "Clean reinstall scheduled.") : "Backup & Restore backend unavailable."
            statusError = !reinstallStarted
            refreshPage()
            return
        }

        var keyMap = {
            hostname: "system.hostname", deviceName: "system.deviceName", locale: "localization.locale",
            timezone: "localization.timezone", wifiCountry: "network.wifiCountry", keyboardLayout: "localization.keyboard",
            proxy: "network.proxyUrl", wallpaper: "appearance.wallpaper"
        }
        var key = keyMap[target] || target
        settingsBackend.queueChange(key, value, target === "hostname" ? "reboot" : "apply")
        applyPendingWithAuthorization()
        refreshPage()
    }

    function normalizeAction(button) {
        var b = String(button || "").toLowerCase()
        if (b === "cross" || b === "x" || b === "ps_cross") return "primary"
        if (b === "circle" || b === "o" || b === "ps_circle") return "cancel"
        if (b === "triangle" || b === "ps_triangle") return "context"
        if (b === "square" || b === "ps_square") return "secondary"
        if (b === "options" || b === "settings" || b === "start" || b === "menu") return "system"
        if (b === "dpad_up") return "up"
        if (b === "dpad_down") return "down"
        if (b === "dpad_left") return "left"
        if (b === "dpad_right") return "right"
        if (b === "lb") return "l1"
        if (b === "rb") return "r1"
        return b
    }

    function openExitPrompt() {
        exitChoice = 0
        exitModalVisible = true
        referenceExitModal.openModal(root)
    }

    function closeTransientModal(name) {
        if (name === "edition") editionModalVisible = false
        else if (name === "pi") piModalVisible = false
        else if (name === "easter") { easterEggVisible = false; easterEggTimer.stop() }
        else if (name === "report") systemReportVisible = false
        forceActiveFocus()
    }

    function dashboardWidgets() {
        return dashboardLayoutBackend && dashboardLayoutBackend.widgets
                ? dashboardLayoutBackend.widgets : []
    }
    function dashboardCurrentWidget() {
        var rows = dashboardWidgets()
        return rows.length ? rows[Math.max(0, Math.min(rows.length - 1, dashboardLayoutIndex))] : null
    }
    function dashboardLayoutActions() {
        var widget = dashboardCurrentWidget()
        return widget && String(widget.id) === "temperature"
                ? ["Move", widget.enabled === false ? "Enable" : "Disable"]
                : ["Move", "Size", widget && widget.enabled === false ? "Enable" : "Disable"]
    }
    function dashboardBeginProposal() {
        var widget = dashboardCurrentWidget()
        if (!widget) return
        dashboardMoveDelta = 0
        dashboardProposedSize = String(widget.size || "small")
        dashboardLayoutPhase = 2
    }
    function dashboardCommitProposal() {
        var widget = dashboardCurrentWidget(), actions = dashboardLayoutActions()
        if (!widget || !dashboardLayoutBackend || dashboardLayoutAction >= actions.length) return
        var action = actions[dashboardLayoutAction]
        if (action === "Move" && dashboardMoveDelta !== 0)
            dashboardLayoutBackend.moveWidget(String(widget.id), dashboardMoveDelta)
        else if (action === "Size")
            dashboardLayoutBackend.setWidgetSize(String(widget.id), dashboardProposedSize)
        else if (action === "Enable" || action === "Disable")
            dashboardLayoutBackend.setWidgetEnabled(String(widget.id), action === "Enable")
        dashboardLayoutPhase = 0
        dashboardLayoutAction = 0
        dashboardLayoutIndex = Math.max(0, Math.min(dashboardWidgets().length - 1, dashboardLayoutIndex + dashboardMoveDelta))
        dashboardMoveDelta = 0
        statusMessage = "Dashboard layout saved for this user."
        statusError = false
    }
    function handleDashboardLayout(action) {
        var rows = dashboardWidgets(), actions = dashboardLayoutActions()
        if (action === "cancel") {
            if (dashboardLayoutPhase === 0) dashboardLayoutVisible = false
            else dashboardLayoutPhase = Math.max(0, dashboardLayoutPhase - 1)
            dashboardMoveDelta = 0
            return true
        }
        if (dashboardLayoutPhase === 0) {
            if (action === "up") dashboardLayoutIndex = Math.max(0, dashboardLayoutIndex - 1)
            else if (action === "down") dashboardLayoutIndex = Math.min(Math.max(0, rows.length - 1), dashboardLayoutIndex + 1)
            else if (action === "primary") { dashboardLayoutAction = 0; dashboardLayoutPhase = 1 }
        } else if (dashboardLayoutPhase === 1) {
            if (action === "left") dashboardLayoutAction = Math.max(0, dashboardLayoutAction - 1)
            else if (action === "right") dashboardLayoutAction = Math.min(Math.max(0, actions.length - 1), dashboardLayoutAction + 1)
            else if (action === "primary") dashboardBeginProposal()
        } else {
            var selectedAction = actions[dashboardLayoutAction]
            if (selectedAction === "Move" && (action === "left" || action === "right"))
                dashboardMoveDelta = action === "left" ? -1 : 1
            else if (selectedAction === "Size" && (action === "left" || action === "right")) {
                var sizes = ["small", "medium", "large"], current = sizes.indexOf(dashboardProposedSize)
                dashboardProposedSize = sizes[(Math.max(0, current) + (action === "left" ? 2 : 1)) % 3]
            } else if (action === "primary") dashboardCommitProposal()
        }
        return true
    }

    Loader {
        id: wifiScanLoader
        anchors.fill: parent
        z: 20000
        active: true
        source: "../../dashboard/v2/NetworkScanModal.qml"
        onLoaded: {
            if (item) {
                item.networkBackend = root.networkBackend
                item.opened = false
            }
        }
    }

    Loader {
        id: timezoneModalLoader
        anchors.fill: parent
        z: 21000
        active: false
        source: "../../modals/system/TimezonePickerModal.qml"
        onLoaded: { if (item) item.visible = false }
    }

    // NEUTRONOS_HIERARCHICAL_TIMEZONE_SETTINGS_V2
    function currentTimezoneForPicker() {
        try {
            if (typeof clockSettingsManager !== "undefined" && clockSettingsManager && clockSettingsManager.timezone)
                return String(clockSettingsManager.timezone)
        } catch (error) {}
        return String(settingValue("localization.timezone", "America/New_York"))
    }

    function openTimezoneBrowser() {
        timezoneModalLoader.active = true
        Qt.callLater(function() {
            var modal = timezoneModalLoader.item
            if (!modal) {
                statusMessage = "Timezone browser is still loading."
                statusError = true
                return
            }
            modal.openModal({ "currentTimezone": currentTimezoneForPicker() })
            statusMessage = "Choose continent, country, then timezone. X applies immediately."
            statusError = false
        })
    }

    Connections {
        target: timezoneModalLoader.item
        enabled: timezoneModalLoader.item !== null
        ignoreUnknownSignals: true
        function onTimezoneSelected(zoneId) {
            statusMessage = "Timezone applied: " + String(zoneId)
            statusError = false
            refreshPage()
        }
    }

    function handleController(button) { return handleControllerPressed(button) }
    function handleControllerPressed(button) {
        var action = normalizeAction(button)

        if (timezoneModalLoader.item && timezoneModalLoader.item.visible)
            return timezoneModalLoader.item.handleControllerPressed(action)
        if (wifiScanLoader.item && wifiScanLoader.item.opened)
            return wifiScanLoader.item.handleControllerPressed(action)
        if (diagnosticsCenter.visible)
            return diagnosticsCenter.handleControllerPressed(action)
        if (hotspotManagerModal.visibleMode && !keyboardOpen)
            return hotspotManagerModal.handleControllerPressed(action)
        if (bluetoothManagerModal.visibleMode)
            return bluetoothManagerModal.handleControllerPressed(action)
        if (keyboardOpen)
            return virtualKeyboard.handleControllerPressed(action)
        if (phase1SettingsModal.visibleMode)
            return phase1SettingsModal.handleControllerPressed(action)
        if (userProfileSettingsModal.visible)
            return userProfileSettingsModal.handleControllerPressed(action)
        if (personalizationModal.visible)
            return personalizationModal.handleControllerPressed(action)
        if (installedAppsModal.visibleMode)
            return installedAppsModal.handleControllerPressed(action)
        if (autoLoginWarningModal.visibleMode)
            return autoLoginWarningModal.handleControllerPressed(action)
        if (securityPrivacyModal.visibleMode)
            return securityPrivacyModal.handleControllerPressed(action)
        if (updateInstallConfirmationModal.visibleMode)
            return updateInstallConfirmationModal.handleControllerPressed(action)
        if (backupRestorePointsModal.visibleMode)
            return backupRestorePointsModal.handleControllerPressed(action)
        if (updateRecoveryTextModal.visibleMode)
            return updateRecoveryTextModal.handleControllerPressed(action)
        if (systemOverviewManager.opened)
            return systemOverviewManager.handleControllerPressed(action)
        if (dashboardLayoutVisible)
            return handleDashboardLayout(action)

        if (exitModalVisible) {
            referenceExitModal.handleController(action)
            return true
        }

        if (easterEggVisible) {
            if (action === "cancel" || action === "primary" || action === "system")
                closeTransientModal("easter")
            return true
        }
        if (editionModalVisible) {
            if (action === "cancel" || action === "primary" || action === "system")
                closeTransientModal("edition")
            return true
        }
        if (piModalVisible) {
            if (action === "cancel" || action === "primary" || action === "system")
                closeTransientModal("pi")
            return true
        }
        if (systemReportVisible) {
            if (action === "cancel" || action === "system")
                closeTransientModal("report")
            else if (action === "primary" && settingsBackend)
                settingsBackend.runSystemIntegrityCheck()
            return true
        }
        if (buttonTestVisible) {
            if (buttonTestFinished) {
                if (action === "primary") startButtonTest()
                else if (action === "cancel" || action === "system") closeButtonTest()
                return true
            }

            if (action === "system") {
                var now = Date.now()
                if (buttonTestLastSystemMs > 0 && now - buttonTestLastSystemMs > 700) {
                    finishButtonTest()
                } else {
                    markButtonTest("system")
                    buttonTestLastSystemMs = now
                }
            } else {
                markButtonTest(action)
            }
            return true
        }

        if (detailsVisible) {
            if (action === "cancel" || action === "primary") {
                detailsVisible = false
                forceActiveFocus()
            }
            return true
        }
        if (rebootPromptVisible) {
            if (action === "left") rebootChoice = Math.max(0, rebootChoice - 1)
            else if (action === "right") rebootChoice = Math.min(2, rebootChoice + 1)
            else if (action === "cancel") rebootPromptVisible = false
            else if (action === "primary") {
                var choice = rebootChoice
                rebootPromptVisible = false
                if (choice === 1) runRowAction("restart-shell")
                else if (choice === 2) runRowAction("reboot")
            }
            return true
        }

        /* When the Performance warning/apply modal is open it owns every
           controller action, including O/cancel. The previous routing blocked
           cancel before it reached PerformancePage and trapped the modal. */
        if (performancePageActive && focusZone === 1 && performancePage.modalVisible)
            return performancePage.handleControllerPressed(action)

        if (performancePageActive && focusZone === 1 &&
                action !== "cancel" && action !== "l1" && action !== "r1" &&
                action !== "system" && action !== "context" &&
                !(action === "left" && performancePage.tabIndex === 0 && performancePage.focusIndex === 0)) {
            return performancePage.handleControllerPressed(action)
        }

        if (action === "context") {
            openKeyboard("search", searchText, "Search Settings")
            return true
        }
        if (action === "l1") { changeCategory(-1); return true }
        if (action === "r1") { changeCategory(1); return true }

        if (action === "cancel") {
            if (displayMode === "tiles") { openExitPrompt(); return true }
            if (focusZone === 1 || focusZone === 2) {
                focusZone = 0
                sidebarList.currentIndex = sidebarIndex
                sidebarList.positionViewAtIndex(sidebarIndex, ListView.Contain)
                statusMessage = "Returned to the Settings category list."
                statusError = false
            } else {
                openExitPrompt()
            }
            return true
        }

        if (action === "up") {
            if (focusZone === 3) return true
            if (displayMode === "tiles") {
                if (tileIndex < 4) focusZone = 3
                else tileIndex = Math.max(0, tileIndex - 4)
                return true
            }
            if (focusZone === 0) {
                sidebarIndex = (sidebarIndex - 1 + categories.length) % categories.length
                sidebarList.positionViewAtIndex(sidebarIndex, ListView.Contain)
                refreshPage()
            } else if (focusZone === 1) {
                moveContent(-1)
            } else {
                focusZone = 1
                if (developerPageActive) {
                    developerPageIndex = firstSelectableDeveloperIndex(developerPageIndex)
                    developerContentList.currentIndex = developerPageIndex
                } else {
                    contentList.currentIndex = firstSelectableIndex(contentList.currentIndex)
                }
            }
            return true
        }
        if (action === "down") {
            if (focusZone === 3) { focusZone = 0; return true }
            if (displayMode === "tiles") { tileIndex = Math.min(categories.length - 1, tileIndex + 4); return true }
            if (focusZone === 0) {
                sidebarIndex = (sidebarIndex + 1) % categories.length
                sidebarList.positionViewAtIndex(sidebarIndex, ListView.Contain)
                refreshPage()
            } else if (focusZone === 1) {
                moveContent(1)
            } else {
                focusZone = 1
                if (developerPageActive) {
                    developerPageIndex = firstSelectableDeveloperIndex(developerPageIndex)
                    developerContentList.currentIndex = developerPageIndex
                } else {
                    contentList.currentIndex = firstSelectableIndex(contentList.currentIndex)
                }
            }
            return true
        }
        if (action === "left") {
            if (displayMode === "tiles") { tileIndex = Math.max(0, tileIndex - 1); return true }
            if (focusZone === 1 || focusZone === 2) {
                focusZone = 0
                sidebarList.currentIndex = sidebarIndex
                sidebarList.positionViewAtIndex(sidebarIndex, ListView.Contain)
                statusMessage = "Returned to the Settings category list."
                statusError = false
            }
            return true
        }
        if (action === "right") {
            if (displayMode === "tiles") { tileIndex = Math.min(categories.length - 1, tileIndex + 1); return true }
            if (focusZone === 0) {
                focusZone = 1
                if (performancePageActive) {
                    performancePage.focusIndex = 0
                } else if (developerPageActive) {
                    developerPageIndex = firstSelectableDeveloperIndex(developerPageIndex)
                    developerContentList.currentIndex = developerPageIndex
                } else {
                    contentList.currentIndex = firstSelectableIndex(contentList.currentIndex)
                }
            } else if (focusZone === 1) {
                var rightRow = developerPageActive ? developerRowAt(developerPageIndex) : pageModel.get(contentList.currentIndex)
                if (developerPageActive && developerRowLocked(rightRow)) {
                    statusMessage = "Enable Developer Mode to change this setting."
                    statusError = true
                } else if (rightRow && rightRow.kind === "choice") cycleRow(rightRow, 1)
                else if (rightRow && rightRow.kind === "slider") adjustSlider(rightRow, 1)
            } else if (focusZone === 2) {
                rebootChoice = Math.min(1, rebootChoice + 1)
            }
            return true
        }
        if (action === "primary") {
            if (focusZone === 3) { openExitPrompt(); return true }
            if (displayMode === "tiles") {
                sidebarIndex = tileIndex
                refreshPage()
                displayMode = "list"
                if (settingsBackend) settingsBackend.setUiPreference("ui.settingsDisplayMode", displayMode)
                focusZone = 1
                return true
            }
            if (focusZone === 0) {
                focusZone = 1
                if (performancePageActive) {
                    performancePage.focusIndex = 0
                } else if (developerPageActive) {
                    developerPageIndex = firstSelectableDeveloperIndex(0)
                    developerContentList.currentIndex = developerPageIndex
                } else {
                    contentList.currentIndex = firstSelectableIndex(0)
                }
            } else if (focusZone === 1) {
                activateCurrent()
            } else if (focusZone === 2) {
                if (rebootChoice === 0) settingsBackend.discardPending()
                else applyPendingWithAuthorization()
                focusZone = 1
                refreshPage()
            }
            return true
        }
        if (action === "secondary") {
            // Square is never the Settings Apply button. X owns select/apply.
            if (focusZone === 0)
                toggleThemeFromSquare()
            else {
                statusMessage = "Use X to apply the selected setting."
                statusError = false
            }
            return true
        }
        if (action === "system") {
            displayMode = displayMode === "tiles" ? "list" : "tiles"
            if (displayMode === "tiles") { tileIndex = sidebarIndex; focusZone = 0 }
            else { sidebarIndex = tileIndex; refreshPage(); focusZone = 0 }
            if (settingsBackend) settingsBackend.setUiPreference("ui.settingsDisplayMode", displayMode)
            return true
        }
        return true
    }

    function handleControllerReleased(button) { return true }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) { handleControllerPressed("up"); event.accepted = true }
        else if (event.key === Qt.Key_Down) { handleControllerPressed("down"); event.accepted = true }
        else if (event.key === Qt.Key_Left) { handleControllerPressed("left"); event.accepted = true }
        else if (event.key === Qt.Key_Right) { handleControllerPressed("right"); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { handleControllerPressed("primary"); event.accepted = true }
        else if (event.key === Qt.Key_Escape) { handleControllerPressed("cancel"); event.accepted = true }
        else if (event.key === Qt.Key_F1) { handleControllerPressed("context"); event.accepted = true }
        else if (event.key === Qt.Key_F2) { handleControllerPressed("secondary"); event.accepted = true }
    }
}
