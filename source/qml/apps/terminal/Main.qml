import QtQuick 2.15
import QtQuick.Controls 2.15

import "components"
import "models"
import "modals"
import "../../components" as Shared

Item {
    id: app

    anchors.fill: parent
    focus: true

    property string appId: "terminal"
    property string appName: "NeutronOS Terminal"
    property string version: "v1.2.0"

    signal exitRequested()
    signal backgroundRequested()

    property var terminalBackend: (typeof terminalManager !== "undefined") ? terminalManager : null
    property var assistBackend: (typeof terminalAssistManager !== "undefined") ? terminalAssistManager : null
    property var assetBackend: (typeof assetManager !== "undefined") ? assetManager : null
    property var controllerBackend: (typeof controllerManager !== "undefined") ? controllerManager : null
    property var settingsBackend: (typeof settingsManager !== "undefined") ? settingsManager : null

    // Terminal-specific UI preferences use the existing SettingsManager UI
    // preference store, so they persist without changing the Terminal C++ ABI.
    property int terminalViewportFontSize: 16
    property int terminalTypebarFontSize: 18
    property real terminalPanelOpacity: 1.0
    property bool terminalTimestampVisible: true

    property string keyboardTarget: "draft"
    property bool viewportPrimaryPending: false
    property string keyboardBuffer: ""
    readonly property var correctionSuggestion: assistBackend ? assistBackend.correctionSuggestion : ({})
    readonly property bool correctionVisible: correctionSuggestion && correctionSuggestion.visible === true && String(correctionSuggestion.corrected || "").length > 0
    property bool correctionArmed: false
    property string terminalActionMessage: ""
    property bool terminalActionError: false

    property url backgroundSource: assetBackend
                                   ? assetBackend.themeFile("background.png")
                                   : ""

    property color spaceBlack: "#02050A"
    property color textPrimary: ui.backendAvailable ? app.terminalBackend.terminalTextColor : "#F3FCFF"
    property color textSecondary: "#B9EEFF"
    property color textMuted: "#77A9C8"
    property color neutronBlue: ui.backendAvailable ? app.terminalBackend.tintColor : "#68D8FF"
    property color successGreen: "#27FF9A"
    property color dangerRed: "#FF3048"

    function terminalSettingValue(key, fallbackValue) {
        try {
            return app.settingsBackend ? app.settingsBackend.value(key, fallbackValue) : fallbackValue
        } catch (error) {
            return fallbackValue
        }
    }

    function clampTerminalNumber(value, minimum, maximum, fallbackValue) {
        var number = Number(value)
        if (!isFinite(number))
            number = Number(fallbackValue)
        return Math.max(minimum, Math.min(maximum, number))
    }

    function loadTerminalUiPreferences() {
        app.terminalViewportFontSize = Math.round(app.clampTerminalNumber(
            app.terminalSettingValue("ui.terminal.viewportFontSize", 16), 13, 22, 16))
        app.terminalTypebarFontSize = Math.round(app.clampTerminalNumber(
            app.terminalSettingValue("ui.terminal.typebarFontSize", 18), 14, 22, 18))
        var opacityPercent = app.clampTerminalNumber(
            app.terminalSettingValue("ui.terminal.panelOpacityPercent", 100), 65, 100, 100)
        app.terminalPanelOpacity = opacityPercent / 100.0
        app.terminalTimestampVisible = app.terminalSettingValue(
            "ui.terminal.timestampsVisible", true) !== false
    }

    function saveTerminalUiPreferences(viewportFontSize, typebarFontSize, panelOpacityPercent, timestampsVisible) {
        app.terminalViewportFontSize = Math.round(app.clampTerminalNumber(viewportFontSize, 13, 22, 16))
        app.terminalTypebarFontSize = Math.round(app.clampTerminalNumber(typebarFontSize, 14, 22, 18))
        var cleanOpacity = Math.round(app.clampTerminalNumber(panelOpacityPercent, 65, 100, 100) / 5) * 5
        app.terminalPanelOpacity = cleanOpacity / 100.0
        app.terminalTimestampVisible = timestampsVisible !== false

        if (app.settingsBackend && typeof app.settingsBackend.setUiPreference === "function") {
            app.settingsBackend.setUiPreference("ui.terminal.viewportFontSize", app.terminalViewportFontSize)
            app.settingsBackend.setUiPreference("ui.terminal.typebarFontSize", app.terminalTypebarFontSize)
            app.settingsBackend.setUiPreference("ui.terminal.panelOpacityPercent", cleanOpacity)
            app.settingsBackend.setUiPreference("ui.terminal.timestampsVisible", app.terminalTimestampVisible)
        }
    }

    function resetTerminalUiPreferences() {
        app.saveTerminalUiPreferences(16, 18, 100, true)
    }

    TerminalUiModel {
        id: ui
        terminalBackend: app.terminalBackend

        onToolbarActionRequested: function(actionId) {
            app.activateToolbar(actionId)
        }
    }

    QuickCommandModel {
        id: quickModel
        terminalBackend: app.terminalBackend

        onCommandArmRequested: function(commandId) {
            quickModel.arm(commandId)
        }

        onCommandRunRequested: function(commandId, requiresArmed) {
            quickModel.run(commandId, requiresArmed, "qml")
            quickModal.close()
            ui.navigationArea = "viewport"
            app.forceActiveFocus()
        }
    }

    Connections {
        target: ui.backendAvailable ? app.terminalBackend : null
        ignoreUnknownSignals: true

        function onOutputChanged() {
            viewport.scrollToBottom()
        }

        function onOutputAppended(text) {
            viewport.scrollToBottom()
        }

        function onInputDraftChanged(text, source) {
            typeBar.setDraft(text)
        }

        function onModeChanged() {
            modePulse.restart()
            quickModel.refresh()
        }

        function onErrorChanged() {
            if (app.terminalBackend.error && app.terminalBackend.error.length > 0)
                errorPulse.restart()
        }
    }

    Connections {
        target: app.assistBackend
        ignoreUnknownSignals: true

        function onSnippetsChanged() {
            snippetsModal.snippets = app.assistBackend ? app.assistBackend.snippets : []
        }

        function onCorrectionSuggestionChanged() {
            app.correctionArmed = false
            correctionArmTimer.stop()
            correctionPulse.restart()
        }
    }

    Component.onCompleted: {
        loadTerminalUiPreferences()
        forceActiveFocus()
        // Let the app shell become interactive before PTY/session discovery and
        // the optional web mirror perform their comparatively expensive setup.
        Qt.callLater(function() {
            ui.startBackend()
            // Remote Terminal Mirror is intentionally local-opt-in. It starts only
            // when the user enables it or generates a 60-second connection code.
            quickModel.refresh()
            if (app.assistBackend) {
                app.assistBackend.observeDraft(ui.inputDraft)
                snippetsModal.snippets = app.assistBackend.snippets
            }
        })
    }

    Rectangle {
        anchors.fill: parent
        color: app.spaceBlack
    }

    Image {
        anchors.fill: parent
        source: app.backgroundSource
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: true
        asynchronous: true
        opacity: status === Image.Ready ? 0.20 : 0.0
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.54
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#000000F0" }
            GradientStop { position: 0.36; color: "#02050A88" }
            GradientStop { position: 0.74; color: "#02050AD8" }
            GradientStop { position: 1.00; color: "#02050AFF" }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: app.neutronBlue
        opacity: 0.035
    }

    TerminalViewport {
        id: viewport

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: correctionPanel.top
        anchors.leftMargin: 42
        anchors.rightMargin: 42
        anchors.topMargin: 16
        anchors.bottomMargin: 16

        outputText: ui.outputText
        promptLabel: ui.promptLabel
        viewportFocused: ui.navigationArea === "viewport" && !ui.modalOpen
        textColor: app.textPrimary
        accentColor: app.neutronBlue
        fontPixelSize: app.terminalViewportFontSize
        timestampVisible: app.terminalTimestampVisible
        surfaceOpacity: app.terminalPanelOpacity
        actionMessage: app.terminalActionMessage
        actionError: app.terminalActionError

        onSelectionCaptured: function(text) {
            if (ui.backendAvailable)
                app.terminalBackend.setSelectionText(text, "qml")
        }

        onCopyRequested: function(text) {
            if (!ui.backendAvailable)
                return
            app.terminalBackend.setSelectionText(text, "qml")
            app.terminalBackend.copySelection("qml")
        }
    }

    TerminalHeader {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 0
        z: 50

        title: "NeutronOS"
        subtitle: "TERMINAL"
        atomSource: app.assetBackend ? app.assetBackend.themeFile("atom.png") : ""
        modeLabel: ui.modeLabel
        statusText: ui.errorText && ui.errorText.length > 0 ? ui.errorText : ui.statusText
        developerMode: ui.developerMode
        ptyAlive: ui.ptyAlive
        remoteRunning: ui.webMirrorRunning
        remoteClientCount: ui.authenticatedWebClientCount
        menuFocused: ui.navigationArea === "headerMenu" && !ui.modalOpen
        accentColor: app.neutronBlue
        textColor: app.textPrimary

        onMenuRequested: app.showModal("quick")
    }

    Rectangle {
        id: correctionPanel

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: typeBar.top
        anchors.leftMargin: 42
        anchors.rightMargin: 42
        anchors.bottomMargin: app.correctionVisible ? 8 : 0

        height: app.correctionVisible ? 54 : 0
        radius: 18
        visible: height > 0
        opacity: visible ? 1.0 : 0.0
        color: app.correctionArmed || app.correctionSuggestion.dangerous === true ? "#3B1018EE" : "#3A2C08EE"
        border.width: app.correctionArmed ? 3 : 2
        border.color: app.correctionArmed || app.correctionSuggestion.dangerous === true ? "#FF5067" : "#FFD34D"
        clip: true

        Row {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 18

            Text {
                width: parent.width - 330
                text: String(app.correctionSuggestion.message || "Smart correction available") + "  →  " + String(app.correctionSuggestion.corrected || "")
                color: app.correctionSuggestion.dangerous === true ? "#FF98A6" : "#FFE781"
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                font.pixelSize: 15
                font.bold: true
                font.family: "monospace"
            }

            Text {
                width: 300
                text: app.correctionArmed ? "X CONFIRM  •  O CANCEL" : (app.correctionSuggestion.requiresConfirmation === true ? "X ARM  •  O DISMISS" : "X ACCEPT  •  O DISMISS")
                color: "#F3FCFF"
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.1
            }
        }
    }

    TerminalTypeBar {
        id: typeBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: virtualKeyboard.visibleMode && app.keyboardTarget === "draft" ? virtualKeyboard.top : toolbar.top
        anchors.leftMargin: 42
        anchors.rightMargin: 42
        anchors.bottomMargin: virtualKeyboard.visibleMode && app.keyboardTarget === "draft" ? 10 : 12

        promptLabel: ui.promptLabel
        draftText: ui.inputDraft
        developerMode: ui.developerMode
        typebarFocused: ui.navigationArea === "typebar" && !ui.modalOpen
        textColor: app.textPrimary
        accentColor: app.neutronBlue
        fontPixelSize: app.terminalTypebarFontSize
        timestampVisible: app.terminalTimestampVisible
        surfaceOpacity: app.terminalPanelOpacity
        actionMessage: app.terminalActionMessage
        actionError: app.terminalActionError
        remoteMirrorRunning: ui.webMirrorRunning

        onDraftEdited: function(text) {
            if (ui.backendAvailable)
                app.terminalBackend.setInputDraft(text, "qml")
        }

        onCommitRequested: app.commitCommand()
        onCancelRequested: app.pressCancel()
        onMoveUpRequested: app.moveUp()
        onMoveDownRequested: app.moveDown()
        onMoveLeftRequested: app.moveLeft()
        onMoveRightRequested: app.moveRight()
    }

    TerminalToolbar {
        id: toolbar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: referenceFooter.top
        visible: !virtualKeyboard.visibleMode

        actions: ui.toolbarActions
        selectedIndex: ui.toolbarIndex
        toolbarFocused: ui.navigationArea === "toolbar" && !ui.modalOpen
        textPrimary: app.textPrimary
        neutronBlue: app.neutronBlue

        onSelectedIndexChanged: ui.toolbarIndex = selectedIndex
        onActionRequested: function(actionId) { app.activateToolbar(actionId) }
    }

    QuickCommandsModal {
        id: quickModal

        commands: quickModel.commands
        selectedIndex: quickModel.selectedIndex
        armedQuickActionId: quickModel.armedQuickActionId

        onSelectedIndexChanged: quickModel.selectedIndex = selectedIndex

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "toolbar"
            app.forceActiveFocus()
        }

        onCommandRequested: function(commandId, requiresArmed) {
            quickModel.run(commandId, requiresArmed, "qml")
            close()
            ui.navigationArea = "viewport"
        }

        onArmRequested: function(commandId) {
            quickModel.arm(commandId)
            armedQuickActionId = quickModel.armedQuickActionId
        }
    }

    ClipboardModal {
        id: clipboardModal

        clipboardText: ui.clipboardText
        selectionText: ui.selectionText

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "toolbar"
            app.forceActiveFocus()
        }

        onCopySelectionRequested: {
            if (ui.backendAvailable)
                app.terminalBackend.copySelection("qml")
        }

        onPasteToDraftRequested: {
            if (ui.backendAvailable)
                app.terminalBackend.pasteText(app.terminalBackend.clipboardText, "draft", "qml")
            close()
        }

        onPasteToPtyRequested: {
            if (ui.backendAvailable)
                app.terminalBackend.pasteText(app.terminalBackend.clipboardText, "pty", "qml")
            close()
        }

        onClearSelectionRequested: {
            if (ui.backendAvailable)
                app.terminalBackend.clearSelection("qml")
        }
    }

    WebMirrorModal {
        id: webMirrorModal

        webUrl: ui.webUrl
        pairingCode: ui.webPairingCode
        pairingSecondsRemaining: ui.webPairingCodeSecondsRemaining
        webClientCount: ui.authenticatedWebClientCount
        webMirrorRunning: ui.webMirrorRunning
        webMirrorEnabled: ui.webMirrorEnabled

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "toolbar"
            app.forceActiveFocus()
        }

        onToggleWebMirrorRequested: {
            if (!ui.backendAvailable) {
                webMirrorModal.showActionResult(false, "Terminal backend unavailable")
                return
            }

            var shouldEnable = !(app.terminalBackend.webMirrorRunning || app.terminalBackend.webMirrorEnabled)
            var result = app.terminalBackend.setRemoteMirrorActive(shouldEnable)
            webMirrorModal.showActionResult(result.ok === true,
                                            result.ok === true ? String(result.message || "Remote mirror updated")
                                                               : String(result.error || "Remote mirror action failed"))
        }

        onGenerateCodeRequested: {
            if (!ui.backendAvailable) {
                webMirrorModal.showActionResult(false, "Terminal backend unavailable")
                return
            }

            var result = app.terminalBackend.generateRemoteMirrorCode()
            webMirrorModal.showActionResult(result.ok === true,
                                            result.ok === true ? String(result.message || "Connection code generated")
                                                               : String(result.error || "Unable to generate connection code"))
        }
    }
    DeveloperModeModal {
        id: developerModeModal

        developerMode: ui.developerMode
        modeLabel: ui.modeLabel
        statusText: ui.statusText

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "toolbar"
            app.forceActiveFocus()
        }

        onRestartRequested: {
            if (ui.backendAvailable)
                app.terminalBackend.restart()
            close()
        }
    }

    TerminalCustomizeModal {
        id: customizeModal

        tintColor: ui.backendAvailable ? app.terminalBackend.tintColor : "#68D8FF"
        textColor: ui.backendAvailable ? app.terminalBackend.terminalTextColor : "#F3FCFF"
        startupMessage: ui.backendAvailable ? app.terminalBackend.startupMessage : "Welcome to NeutronOS Gemini."
        viewportFontSize: app.terminalViewportFontSize
        typebarFontSize: app.terminalTypebarFontSize
        panelOpacityPercent: Math.round(app.terminalPanelOpacity * 100)
        timestampsVisible: app.terminalTimestampVisible

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "toolbar"
            app.forceActiveFocus()
        }

        onKeyboardRequested: function(fieldId, value, title) {
            app.openVirtualKeyboard("custom:" + fieldId, value, title)
        }

        onSaveRequested: function(tint, text, startup, viewportFont, typebarFont, panelOpacity, timestamps) {
            if (!ui.backendAvailable)
                return
            var result = app.terminalBackend.saveAppearance(tint, text, startup)
            statusText = result && result.ok === true
                       ? "Terminal customization saved."
                       : String(result && result.error ? result.error : "Unable to save customization")
            if (result && result.ok === true) {
                app.saveTerminalUiPreferences(viewportFont, typebarFont, panelOpacity, timestamps)
                tintColor = app.terminalBackend.tintColor
                textColor = app.terminalBackend.terminalTextColor
                startupMessage = app.terminalBackend.startupMessage
                viewportFontSize = app.terminalViewportFontSize
                typebarFontSize = app.terminalTypebarFontSize
                panelOpacityPercent = Math.round(app.terminalPanelOpacity * 100)
                timestampsVisible = app.terminalTimestampVisible
                syncPresetFromColors()
            }
        }

        onResetRequested: {
            if (!ui.backendAvailable)
                return
            var result = app.terminalBackend.resetAppearance()
            if (result && result.ok === true)
                app.resetTerminalUiPreferences()
            statusText = result && result.ok === true
                       ? "NeutronOS Terminal defaults restored."
                       : String(result && result.error ? result.error : "Unable to reset customization")
            tintColor = app.terminalBackend.tintColor
            textColor = app.terminalBackend.terminalTextColor
            startupMessage = app.terminalBackend.startupMessage
            viewportFontSize = app.terminalViewportFontSize
            typebarFontSize = app.terminalTypebarFontSize
            panelOpacityPercent = Math.round(app.terminalPanelOpacity * 100)
            timestampsVisible = app.terminalTimestampVisible
            syncPresetFromColors()
        }
    }

    Shared.ReferenceExitModal {
        id: exitModal
        appName: "Terminal"
        onDismissed: {
            ui.clearModal()
            app.forceActiveFocus()
        }
        onExitRequested: {
            ui.clearModal()
            app.exitRequested()
        }
        onLeaveRunningRequested: {
            ui.clearModal()
            app.backgroundRequested()
        }
    }

    Shared.ReferenceAppFooter {
        id: referenceFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 80
        controllerBackend: app.controllerBackend
        hintText: "D-PAD  NAVIGATE     X  SELECT     □  BACKSPACE     O  EXIT"
    }

    SnippetsModal {
        id: snippetsModal
        snippets: app.assistBackend ? app.assistBackend.snippets : []

        onCloseRequested: {
            ui.clearModal()
            ui.navigationArea = "typebar"
            app.forceActiveFocus()
        }

        onInsertRequested: function(snippetId) {
            if (app.assistBackend && app.terminalBackend) {
                var text = app.assistBackend.snippetText(snippetId)
                if (text.length > 0)
                    app.terminalBackend.setInputDraft(text, "snippet:qml")
            }
            close()
            ui.navigationArea = "typebar"
        }

        onAddRequested: {
            snippetEditor.openForAdd()
            ui.setModal("snippet-editor")
        }

        onEditRequested: function(snippetData) {
            snippetEditor.openForEdit(snippetData)
            ui.setModal("snippet-editor")
        }

        onRemoveRequested: function(snippetId) {
            if (app.assistBackend)
                app.assistBackend.removeSnippet(snippetId)
        }

        onMoveRequested: function(snippetId, offset) {
            if (app.assistBackend)
                app.assistBackend.moveSnippet(snippetId, offset)
        }
    }

    SnippetEditorModal {
        id: snippetEditor

        onCloseRequested: {
            ui.setModal("snippets")
            snippetsModal.visible = true
            snippetsModal.forceActiveFocus()
        }

        onKeyboardRequested: function(fieldId, value, title) {
            app.openVirtualKeyboard("snippet:" + fieldId, value, title)
        }

        onSaveRequested: function(snippetId, label, command, category) {
            if (!app.assistBackend)
                return

            var result = snippetId.length > 0
                         ? app.assistBackend.updateSnippet(snippetId, label, command, category)
                         : app.assistBackend.addSnippet(label, command, category)

            if (result && result.ok === true) {
                close()
            } else {
                errorText = result && result.error ? String(result.error) : "Unable to save snippet"
            }
        }
    }

    Rectangle {
        id: keyboardPreview
        z: 1505
        visible: virtualKeyboard.visibleMode && app.keyboardTarget !== "draft"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: virtualKeyboard.top
        anchors.bottomMargin: 14
        width: Math.min(parent.width - 180, 1280)
        height: 112
        radius: 24
        color: "#071727F4"
        border.width: 2
        border.color: app.neutronBlue

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 7
            Text {
                width: parent.width
                text: app.keyboardTarget.indexOf("snippet:") === 0
                      ? "EDITING " + app.keyboardTarget.substring(8).toUpperCase()
                      : app.keyboardTarget.indexOf("custom:") === 0
                        ? "CUSTOMIZING " + app.keyboardTarget.substring(7).toUpperCase()
                        : "TERMINAL COMMAND"
                color: "#77A9C8"
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.5
            }
            Text {
                width: parent.width
                height: 62
                text: app.keyboardTarget === "draft" ? ui.inputDraft : app.keyboardBuffer
                color: app.textPrimary
                font.family: "monospace"
                font.pixelSize: 17
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideLeft
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Shared.VirtualKeyboard {
        id: virtualKeyboard
        z: 1510
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: referenceFooter.top
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.bottomMargin: 10
        height: 416
        active: visibleMode
        largeMode: false
        sizeMultiplier: 0.70
        cancelBehavior: "close"
        title: app.keyboardTarget.indexOf("snippet:") === 0
               ? "Edit Snippet"
               : app.keyboardTarget.indexOf("custom:") === 0
                 ? "Customize Terminal"
                 : "Terminal Command"

        onKeyPressed: function(value) {
            app.keyboardAppend(value)
        }

        onBackspacePressed: app.keyboardBackspace()

        onEnterPressed: {
            if (app.keyboardTarget === "draft") {
                // Commit while the PTY and keyboard still own a valid focus/input path.
                app.commitCommand()
                visibleMode = false
                ui.clearModal()
                ui.navigationArea = "viewport"
                app.forceActiveFocus()
            } else {
                app.finishKeyboardEdit()
            }
        }

        onClosePressed: {
            app.cancelKeyboardEdit()
        }
    }

    Timer {
        id: viewportPrimaryTimer
        interval: 280
        repeat: false
        onTriggered: {
            if (!app.viewportPrimaryPending)
                return
            app.viewportPrimaryPending = false
            if (ui.navigationArea === "viewport" && !ui.modalOpen && !viewport.selectionMode)
                app.openVirtualKeyboard("draft", ui.inputDraft, "Terminal Command")
        }
    }

    Timer {
        id: correctionArmTimer
        interval: 4500
        repeat: false
        onTriggered: app.correctionArmed = false
    }

    Timer {
        id: terminalActionMessageTimer
        interval: 3200
        repeat: false
        onTriggered: {
            app.terminalActionMessage = ""
            app.terminalActionError = false
        }
    }

    SequentialAnimation {
        id: correctionPulse
        running: false
        PropertyAnimation { target: correctionPanel; property: "scale"; to: 1.012; duration: 80 }
        PropertyAnimation { target: correctionPanel; property: "scale"; to: 1.0; duration: 140 }
    }

    SequentialAnimation {
        id: modePulse
        running: false
        PropertyAnimation { target: header; property: "opacity"; to: 0.58; duration: 90 }
        PropertyAnimation { target: header; property: "opacity"; to: 1.0; duration: 180 }
    }

    SequentialAnimation {
        id: errorPulse
        running: false
        PropertyAnimation { target: header; property: "scale"; to: 1.012; duration: 80 }
        PropertyAnimation { target: header; property: "scale"; to: 1.0; duration: 160 }
    }

    function showModal(modalId) {
        ui.setModal(modalId)

        if (modalId === "quick") {
            quickModel.refresh()
            quickModal.open()
        } else if (modalId === "snippets") {
            snippetsModal.snippets = app.assistBackend ? app.assistBackend.snippets : []
            snippetsModal.open()
        } else if (modalId === "clipboard") {
            clipboardModal.open()
        } else if (modalId === "web") {
            webMirrorModal.open()
        } else if (modalId === "dev") {
            developerModeModal.open()
        } else if (modalId === "customize") {
            customizeModal.tintColor = ui.backendAvailable ? app.terminalBackend.tintColor : "#68D8FF"
            customizeModal.textColor = ui.backendAvailable ? app.terminalBackend.terminalTextColor : "#F3FCFF"
            customizeModal.startupMessage = ui.backendAvailable ? app.terminalBackend.startupMessage : "Welcome to NeutronOS Gemini."
            customizeModal.viewportFontSize = app.terminalViewportFontSize
            customizeModal.typebarFontSize = app.terminalTypebarFontSize
            customizeModal.panelOpacityPercent = Math.round(app.terminalPanelOpacity * 100)
            customizeModal.timestampsVisible = app.terminalTimestampVisible
            customizeModal.open()
        } else if (modalId === "exit") {
            exitModal.openModal(app)
        }
    }

    function closeActiveModal() {
        if (virtualKeyboard.visibleMode) app.cancelKeyboardEdit()
        else if (snippetEditor.visible) snippetEditor.close()
        else if (snippetsModal.visible) snippetsModal.close()
        else if (quickModal.visible) quickModal.close()
        else if (clipboardModal.visible) clipboardModal.close()
        else if (webMirrorModal.visible) webMirrorModal.close()
        else if (developerModeModal.visible) developerModeModal.close()
        else if (customizeModal.visible) customizeModal.close()
        else if (exitModal.visible) exitModal.closeModal()
        else ui.clearModal()
    }

    function dispatchModalController(action) {
        if (virtualKeyboard.visibleMode) return virtualKeyboard.handleControllerPressed(action)
        if (snippetEditor.visible) return snippetEditor.handleControllerPressed(action)
        if (snippetsModal.visible) return snippetsModal.handleControllerPressed(action)
        if (quickModal.visible) return quickModal.handleControllerPressed(action)
        if (clipboardModal.visible) return clipboardModal.handleControllerPressed(action)
        if (webMirrorModal.visible) return webMirrorModal.handleControllerPressed(action)
        if (developerModeModal.visible) return developerModeModal.handleControllerPressed(action)
        if (customizeModal.visible) return customizeModal.handleControllerPressed(action)
        if (exitModal.visible) return exitModal.handleController(action)
        return false
    }

    function openVirtualKeyboard(target, initialValue, titleText) {
        keyboardTarget = target || "draft"
        keyboardBuffer = String(initialValue || "")
        virtualKeyboard.title = titleText || "Terminal Keyboard"
        virtualKeyboard.openKeyboard("small")
        virtualKeyboard.forceActiveFocus()
    }

    function keyboardAppend(value) {
        if (keyboardTarget === "draft") {
            if (ui.backendAvailable)
                app.terminalBackend.appendToDraft(String(value || ""), "keyboard:qml")
        } else {
            keyboardBuffer += String(value || "")
        }
    }

    function keyboardBackspace() {
        if (keyboardTarget === "draft") {
            if (ui.backendAvailable)
                app.terminalBackend.backspaceDraft("keyboard:qml")
        } else if (keyboardBuffer.length > 0) {
            keyboardBuffer = keyboardBuffer.substring(0, keyboardBuffer.length - 1)
        }
    }

    function finishKeyboardEdit() {
        if (keyboardTarget.indexOf("snippet:") === 0) {
            snippetEditor.setField(keyboardTarget.substring(8), keyboardBuffer)
            virtualKeyboard.visibleMode = false
            ui.setModal("snippet-editor")
            snippetEditor.forceActiveFocus()
            return
        }

        if (keyboardTarget.indexOf("custom:") === 0) {
            customizeModal.setField(keyboardTarget.substring(7), keyboardBuffer)
            virtualKeyboard.visibleMode = false
            ui.setModal("customize")
            customizeModal.visible = true
            customizeModal.forceActiveFocus()
            return
        }

        virtualKeyboard.visibleMode = false
        app.forceActiveFocus()
    }

    function cancelKeyboardEdit() {
        virtualKeyboard.visibleMode = false
        if (keyboardTarget.indexOf("snippet:") === 0) {
            ui.setModal("snippet-editor")
            snippetEditor.forceActiveFocus()
        } else if (keyboardTarget.indexOf("custom:") === 0) {
            ui.setModal("customize")
            customizeModal.visible = true
            customizeModal.forceActiveFocus()
        } else {
            ui.clearModal()
            ui.navigationArea = "typebar"
            app.forceActiveFocus()
        }
    }

    function acceptCorrection() {
        if (!app.assistBackend || !app.correctionVisible)
            return false

        if (app.correctionSuggestion.requiresConfirmation === true && !app.correctionArmed) {
            app.correctionArmed = true
            correctionArmTimer.restart()
            correctionPulse.restart()
            return true
        }

        app.correctionArmed = false
        correctionArmTimer.stop()
        var corrected = app.assistBackend.acceptSuggestionText()
        if (corrected.length > 0 && ui.backendAvailable)
            app.terminalBackend.setInputDraft(corrected, "correction:qml")
        return corrected.length > 0
    }

    function dismissCorrection() {
        app.correctionArmed = false
        correctionArmTimer.stop()
        if (app.assistBackend)
            app.assistBackend.dismissSuggestion()
    }

    function cancelPendingViewportPrimary() {
        if (app.viewportPrimaryPending) {
            app.viewportPrimaryPending = false
            viewportPrimaryTimer.stop()
        }
    }

    function moveUp() {
        cancelPendingViewportPrimary()
        if (ui.navigationArea === "toolbar") {
            ui.navigationArea = "typebar"
        } else if (ui.navigationArea === "typebar") {
            ui.navigationArea = "viewport"
        } else if (ui.navigationArea === "viewport") {
            if (viewport.selectionMode)
                viewport.moveIndicator("up")
            else
                ui.navigationArea = "headerMenu"
        }
    }

    function moveDown() {
        cancelPendingViewportPrimary()
        if (ui.navigationArea === "headerMenu") {
            ui.navigationArea = "viewport"
        } else if (ui.navigationArea === "viewport") {
            if (viewport.selectionMode)
                viewport.moveIndicator("down")
            else
                ui.navigationArea = "typebar"
        } else if (ui.navigationArea === "typebar") {
            ui.navigationArea = "toolbar"
        }
    }

    function moveLeft() {
        cancelPendingViewportPrimary()
        if (ui.navigationArea === "toolbar") {
            ui.moveToolbarLeft()
            toolbar.selectedIndex = ui.toolbarIndex
        } else if (ui.navigationArea === "viewport") {
            viewport.moveIndicator("left")
        } else if (ui.backendAvailable && ui.navigationArea === "typebar") {
            app.terminalBackend.sendKey("left", "qml")
        }
    }

    function moveRight() {
        cancelPendingViewportPrimary()
        if (ui.navigationArea === "toolbar") {
            ui.moveToolbarRight()
            toolbar.selectedIndex = ui.toolbarIndex
        } else if (ui.navigationArea === "viewport") {
            viewport.moveIndicator("right")
        } else if (ui.backendAvailable && ui.navigationArea === "typebar") {
            app.terminalBackend.sendKey("right", "qml")
        }
    }

    function handleViewportPrimary() {
        if (viewport.selectionMode) {
            viewport.copyActiveSelection()
            if (ui.backendAvailable)
                app.terminalBackend.clearSelection("qml")
            return
        }
        if (app.viewportPrimaryPending) {
            app.viewportPrimaryPending = false
            viewportPrimaryTimer.stop()
            viewport.beginSelection()
            return
        }
        app.viewportPrimaryPending = true
        viewportPrimaryTimer.restart()
    }

    function showTerminalActionResult(ok, message) {
        terminalActionError = !ok
        terminalActionMessage = String(message || "")
        terminalActionMessageTimer.restart()
    }

    function commitCommand() {
        cancelPendingViewportPrimary()
        if (!ui.backendAvailable) {
            showTerminalActionResult(false, "Terminal backend unavailable")
            return
        }

        var result = app.terminalBackend.submitCommand(typeBar.currentText(), "qml")
        if (result.ok !== true) {
            showTerminalActionResult(false, String(result.error || "Command was not sent"))
            ui.navigationArea = "typebar"
            return
        }

        showTerminalActionResult(true, "COMMAND SENT")
        ui.navigationArea = "viewport"
        Qt.callLater(function() { viewport.scrollToBottom() })
    }

    function pressCancel() {
        cancelPendingViewportPrimary()
        if (viewport.selectionMode) {
            viewport.cancelSelection()
            if (ui.backendAvailable)
                app.terminalBackend.clearSelection("qml")
            return
        }
        if (app.correctionVisible) {
            dismissCorrection()
            return
        }
        if (ui.inputDraft.length > 0) {
            ui.clearDraft()
            return
        }
        showModal("exit")
    }

    function activateToolbar(actionId) {
        if (actionId === "send") {
            commitCommand()
            return
        }

        if (actionId === "keyboard") {
            openVirtualKeyboard("draft", ui.inputDraft, "Terminal Command")
            return
        }

        if (actionId === "snippets") {
            showModal("snippets")
            return
        }

        if (actionId === "quick") {
            showModal("quick")
            return
        }

        if (actionId === "copy") {
            if (ui.backendAvailable && String(ui.clipboardText || "").length > 0) {
                app.terminalBackend.pasteText(String(ui.clipboardText), "draft", "qml")
                ui.navigationArea = "typebar"
                app.showTerminalActionResult(true, "PASTED TO TYPE BAR")
            } else {
                showModal("clipboard")
            }
            return
        }

        if (actionId === "web") {
            showModal("web")
            return
        }

        if (actionId === "customize") {
            showModal("customize")
            return
        }

        if (actionId === "dev") {
            showModal("dev")
            return
        }

        if (actionId === "clear") {
            ui.clearScreen()
            ui.navigationArea = "viewport"
            return
        }

        if (actionId === "ctrlc") {
            ui.sendCtrlC()
            ui.navigationArea = "viewport"
            return
        }

        if (actionId === "exit") {
            showModal("exit")
            return
        }
    }

    function handleController(button) {
        return handleControllerPressed(button)
    }

    function handleControllerPressed(button) {
        var action = ui.normalizeControllerAction(button)

        if (virtualKeyboard.visibleMode) {
            if (action === "system" && app.keyboardTarget === "draft") {
                app.commitCommand()
                virtualKeyboard.visibleMode = false
                ui.clearModal()
                ui.navigationArea = "viewport"
                app.forceActiveFocus()
                return true
            }
            return virtualKeyboard.handleControllerPressed(action)
        }

        if (ui.modalOpen)
            return dispatchModalController(action)

        if (action !== "primary")
            cancelPendingViewportPrimary()

        if (action === "up") { moveUp(); return true }
        if (action === "down") { moveDown(); return true }
        if (action === "left") { moveLeft(); return true }
        if (action === "right") { moveRight(); return true }

        if (action === "primary") {
            if (ui.navigationArea === "headerMenu") {
                showModal("quick")
            } else if (ui.navigationArea === "toolbar") {
                ui.activateToolbar()
            } else if (ui.navigationArea === "typebar") {
                if (!acceptCorrection())
                    openVirtualKeyboard("draft", ui.inputDraft, "Terminal Command")
            } else if (ui.navigationArea === "viewport") {
                handleViewportPrimary()
            }
            return true
        }

        if (action === "cancel") { pressCancel(); return true }
        if (action === "secondary") {
            if (ui.backendAvailable)
                app.terminalBackend.backspaceDraft("controller:qml")
            return true
        }
        if (action === "system") { commitCommand(); return true }
        if (action === "context") { showModal("snippets"); return true }
        if (action === "quick") { showModal("web"); return true }
        return false
    }
    function handleControllerReleased(button) {
        return true
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) { handleControllerPressed("up"); event.accepted = true; return }
        if (event.key === Qt.Key_Down) { handleControllerPressed("down"); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { handleControllerPressed("left"); event.accepted = true; return }
        if (event.key === Qt.Key_Right) { handleControllerPressed("right"); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { app.commitCommand(); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) { handleControllerPressed("cancel"); event.accepted = true; return }
        if (event.key === Qt.Key_F1) { showModal("snippets"); event.accepted = true; return }
        if (event.key === Qt.Key_F2) { showModal("quick"); event.accepted = true; return }
    }
}
