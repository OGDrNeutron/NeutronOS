import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: open
    enabled: visible
    focus: visible
    z: 2200

    property bool open: false
    property var backend: (typeof storageImageFlasher !== "undefined") ? storageImageFlasher : null
    property string stage: "type"
    property int selectedIndex: 0
    property bool raspberryPi: false
    property bool recommended: false
    property string modelId: ""
    property var selectedOs: ({})
    property string sourcePath: ""
    property var target: ({})
    property var targets: []
    property bool armed: false
    property bool filePickerOpen: false
    property string pickerPath: ""
    property var pickerEntries: []
    property int pickerIndex: 0
    property bool keyboardOpen: false
    property string keyboardField: ""
    property string keyboardTitle: "TEXT ENTRY"
    property string keyboardDraft: ""
    property string keyboardOriginalValue: ""
    property int keyboardOriginIndex: 0
    property string hostname: "raspberrypi"
    property string username: "pi"
    property string password: ""
    property string locale: "en_US.UTF-8"
    property string timezone: "America/New_York"
    property string keyboardLayout: "us"
    property string wifiCountry: "US"
    property string wifiSsid: ""
    property string wifiPassword: ""
    property bool wifiHidden: false
    property bool sshEnabled: false
    property bool sshPasswordAuth: true
    property string sshPublicKey: ""
    property bool piConnect: false
    property bool telemetry: false
    property string statusMessage: ""
    property bool statusError: false
    property color panel: "#061426"
    property color raised: "#0B2038"
    property color inset: "#07101D"
    property color cyan: "#73E6FF"
    property color blue: "#4DA6FF"
    property color green: "#32E889"
    property color gold: "#F5C542"
    property color red: "#FF4055"
    property color purple: "#B56AFF"
    property color white: "#F4FBFF"
    property color muted: "#8AA8C3"

    signal closed()
    signal devicesRefreshRequested()

    readonly property var typeChoices: [
        { title: "NON-RASPBERRY PI IMAGE", detail: "Flash a local IMG, ISO, RAW, or supported compressed image.", icon: "▣" },
        { title: "RASPBERRY PI IMAGE", detail: "Recommended downloads or a custom Raspberry Pi image with first-boot setup.", icon: "●" }
    ]
    readonly property var piModeChoices: [
        { title: "RECOMMENDED INSTALL", detail: "Choose your Pi and download a compatible image from the official Raspberry Pi catalog." },
        { title: "CUSTOM INSTALL", detail: "Choose a Raspberry Pi image already stored on this system." }
    ]
    readonly property var customizationRows: [
        { key: "hostname", title: "HOSTNAME", detail: "Name used on the local network", kind: "text" },
        { key: "username", title: "USER ACCOUNT", detail: "Initial Linux username", kind: "text" },
        { key: "password", title: "PASSWORD", detail: "Stored only in the temporary flash request and converted to a hash", kind: "password" },
        { key: "locale", title: "LOCALE", detail: "System language and character format", kind: "text" },
        { key: "timezone", title: "TIME ZONE", detail: "IANA time zone such as America/New_York", kind: "text" },
        { key: "keyboardLayout", title: "KEYBOARD LAYOUT", detail: "Linux keyboard code such as us or gb", kind: "text" },
        { key: "wifiCountry", title: "WI-FI COUNTRY", detail: "Two-letter regulatory country code", kind: "text" },
        { key: "wifiSsid", title: "WIRELESS LAN", detail: "Optional Wi-Fi network name", kind: "text" },
        { key: "wifiPassword", title: "WI-FI PASSWORD", detail: "Required only when the selected network is secured", kind: "password" },
        { key: "wifiHidden", title: "HIDDEN SSID", detail: "Connect even when the network name is not broadcast", kind: "toggle" },
        { key: "sshEnabled", title: "ENABLE SSH", detail: "Enable remote shell access on first boot", kind: "toggle" },
        { key: "sshPasswordAuth", title: "SSH PASSWORD AUTH", detail: "Allow password login in addition to public keys", kind: "toggle" },
        { key: "sshPublicKey", title: "SSH PUBLIC KEY", detail: "Optional authorized key for the first user", kind: "text" },
        { key: "piConnect", title: "RASPBERRY PI CONNECT", detail: "Install Raspberry Pi Connect Lite where the image supports it", kind: "toggle" },
        { key: "telemetry", title: "ANONYMOUS TELEMETRY", detail: "Preference recorded for supported images; NeutronOS sends no flash telemetry", kind: "toggle" },
        { key: "continue", title: "CONTINUE", detail: "Review the image, target and destructive write warning", kind: "action" }
    ]

    function clean(value) { return String(value === undefined || value === null ? "" : value).trim() }
    function setStatus(message, error) { statusMessage = String(message || ""); statusError = error === true }
    function reset() {
        stage = "type"; selectedIndex = 0; raspberryPi = false; recommended = false
        modelId = ""; selectedOs = ({}); sourcePath = ""; target = ({}); targets = []
        armed = false; filePickerOpen = false; keyboardOpen = false
        keyboardDraft = ""; keyboardOriginalValue = ""; keyboardOriginIndex = 0
        hostname = "raspberrypi"; username = "pi"; password = ""; locale = "en_US.UTF-8"
        timezone = "America/New_York"; keyboardLayout = "us"; wifiCountry = "US"
        wifiSsid = ""; wifiPassword = ""; wifiHidden = false; sshEnabled = false
        sshPasswordAuth = true; sshPublicKey = ""; piConnect = false; telemetry = false
        setStatus("Choose the kind of image you want to flash.", false)
    }
    function openWizard() { reset(); open = true; forceActiveFocus() }
    function closeWizard() {
        if (backend && backend.busy) { setStatus("A write is running. The wizard cannot close until verification finishes.", true); return }
        open = false; closed()
    }
    function stageTitle() {
        if (stage === "type") return "FLASH IMAGE"
        if (stage === "piMode") return "RASPBERRY PI IMAGE"
        if (stage === "model") return "CHOOSE RASPBERRY PI"
        if (stage === "os") return "CHOOSE OPERATING SYSTEM"
        if (stage === "file") return raspberryPi ? "CHOOSE RASPBERRY PI IMAGE" : "CHOOSE IMAGE"
        if (stage === "target") return "CHOOSE STORAGE"
        if (stage === "customize") return "CUSTOMIZE FIRST BOOT"
        if (stage === "summary") return "WRITE & VERIFY"
        if (stage === "progress") return "FLASHING STORAGE"
        if (stage === "complete") return backend && backend.succeeded ? "FLASH COMPLETE" : "FLASH FAILED"
        return "STORAGE IMAGE FLASHER"
    }
    function stageSubtitle() {
        if (stage === "type") return "Flash images only to eligible non-boot storage devices."
        if (stage === "piMode") return "Use the official compatible catalog or choose a local image."
        if (stage === "model") return "Only compatible operating systems are shown after the device is selected."
        if (stage === "os") return backend && backend.catalogBusy ? backend.catalogMessage : clean(backend ? backend.catalogMessage : "")
        if (stage === "file") return "Browse folders with the controller and select a supported image file."
        if (stage === "target") return "The active NeutronOS boot drive is excluded. The selected target will be completely erased."
        if (stage === "customize") return "Settings are applied where the chosen Raspberry Pi image supports them."
        if (stage === "summary") return armed ? "FINAL CONFIRMATION — press X again to erase the target and begin." : "Review every detail before arming the destructive write."
        if (stage === "progress") return clean(backend ? backend.status : "Preparing image writer")
        if (stage === "complete") return clean(backend ? backend.status : "Operation finished")
        return ""
    }
    function currentModel() {
        if (!backend || !backend.raspberryModels) return ({})
        return backend.raspberryModels[selectedIndex] || ({})
    }
    function currentOs() {
        if (!backend || !backend.raspberryImages) return ({})
        return backend.raspberryImages[selectedIndex] || ({})
    }
    function refreshTargets() {
        targets = backend && typeof backend.eligibleTargets === "function" ? backend.eligibleTargets() : []
        selectedIndex = Math.max(0, Math.min(selectedIndex, Math.max(0, targets.length - 1)))
    }
    function openFilePicker() {
        pickerPath = backend ? backend.canonicalUserHome() : "/"
        pickerIndex = 0; filePickerOpen = true; refreshPicker(); forceActiveFocus()
    }
    function refreshPicker() {
        pickerEntries = backend && typeof backend.imagePickerEntries === "function"
                ? backend.imagePickerEntries(pickerPath, ["img","iso","raw","img.xz","img.gz","img.bz2","img.zst","zip","xz","gz","bz2","zst"]) : []
        pickerIndex = Math.max(0, Math.min(pickerIndex, Math.max(0, pickerEntries.length - 1)))
        pickerList.positionViewAtIndex(pickerIndex, ListView.Contain)
    }
    function choosePickerEntry() {
        var item = pickerEntries[pickerIndex]
        if (!item) return
        if (item.directory) { pickerPath = item.path; pickerIndex = 0; refreshPicker(); return }
        var check = backend.inspectImage(item.path)
        if (!check.ok) { setStatus(check.message, true); return }
        sourcePath = item.path; filePickerOpen = false; selectedIndex = 0; enterTargetStage()
    }
    function enterTargetStage() { stage = "target"; selectedIndex = 0; armed = false; refreshTargets(); setStatus("Choose the whole storage device to erase and flash.", false) }
    function enterCustomization() { stage = "customize"; selectedIndex = 0; setStatus("Configure supported first-boot options, then choose Continue.", false) }
    function enterSummary() { stage = "summary"; selectedIndex = 0; armed = false; setStatus("Review the source and target. Press X once to arm, then X again to write.", false) }
    function fieldValue(key) {
        if (key === "hostname") return hostname
        if (key === "username") return username
        if (key === "password") return password.length > 0 ? "••••••••" : "NOT SET"
        if (key === "locale") return locale
        if (key === "timezone") return timezone
        if (key === "keyboardLayout") return keyboardLayout
        if (key === "wifiCountry") return wifiCountry
        if (key === "wifiSsid") return wifiSsid.length > 0 ? wifiSsid : "SKIP"
        if (key === "wifiPassword") return wifiPassword.length > 0 ? "••••••••" : "NOT SET"
        if (key === "wifiHidden") return wifiHidden ? "ON" : "OFF"
        if (key === "sshEnabled") return sshEnabled ? "ON" : "OFF"
        if (key === "sshPasswordAuth") return sshPasswordAuth ? "ON" : "OFF"
        if (key === "sshPublicKey") return sshPublicKey.length > 0 ? "CONFIGURED" : "NOT SET"
        if (key === "piConnect") return piConnect ? "ON" : "OFF"
        if (key === "telemetry") return telemetry ? "ON" : "OFF"
        return "X  CONTINUE"
    }
    function rawFieldValue(key) {
        if (key === "hostname") return hostname
        if (key === "username") return username
        if (key === "password") return password
        if (key === "locale") return locale
        if (key === "timezone") return timezone
        if (key === "keyboardLayout") return keyboardLayout
        if (key === "wifiCountry") return wifiCountry
        if (key === "wifiSsid") return wifiSsid
        if (key === "wifiPassword") return wifiPassword
        if (key === "sshPublicKey") return sshPublicKey
        return ""
    }
    function setFieldValue(key, value) {
        var text = String(value || "")
        if (key === "hostname") hostname = text.slice(0, 63)
        else if (key === "username") username = text.toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32)
        else if (key === "password") password = text.slice(0, 256)
        else if (key === "locale") locale = text.slice(0, 64)
        else if (key === "timezone") timezone = text.slice(0, 96)
        else if (key === "keyboardLayout") keyboardLayout = text.toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 24)
        else if (key === "wifiCountry") wifiCountry = text.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 2)
        else if (key === "wifiSsid") wifiSsid = text.slice(0, 64)
        else if (key === "wifiPassword") wifiPassword = text.slice(0, 128)
        else if (key === "sshPublicKey") sshPublicKey = text.slice(0, 4096)
    }
    function openKeyboardFor(key, title) {
        keyboardField = key
        keyboardTitle = title
        keyboardOriginIndex = selectedIndex
        keyboardOriginalValue = rawFieldValue(key)
        keyboardDraft = keyboardOriginalValue
        keyboardOpen = true
        flashKeyboard.title = title
        flashKeyboard.active = true
        flashKeyboard.enabled = true
        Qt.callLater(function() {
            flashKeyboard.openKeyboard("large")
            flashKeyboard.forceActiveFocus()
            keyboardFocusWatchdog.restart()
        })
    }
    function closeKeyboard(commitValue) {
        if (!keyboardOpen) return
        if (commitValue) setFieldValue(keyboardField, keyboardDraft)
        keyboardOpen = false
        flashKeyboard.closeKeyboard()
        selectedIndex = Math.max(0, keyboardOriginIndex)
        Qt.callLater(function() {
            root.forceActiveFocus()
            if (stage === "customize") customizeList.positionViewAtIndex(selectedIndex, ListView.Contain)
        })
    }
    function appendKeyboardText(value) {
        var text = String(value === undefined || value === null ? "" : value)
        if (text === "CLEAR") keyboardDraft = ""
        else if (text !== "CAPS" && text !== "SHIFT" && text !== "SPEC" && text !== "ABC") keyboardDraft += (text === "SPACE" ? " " : text)
    }
    function toggleField(key) {
        if (key === "wifiHidden") wifiHidden = !wifiHidden
        else if (key === "sshEnabled") sshEnabled = !sshEnabled
        else if (key === "sshPasswordAuth") sshPasswordAuth = !sshPasswordAuth
        else if (key === "piConnect") piConnect = !piConnect
        else if (key === "telemetry") telemetry = !telemetry
    }
    function startFlash() {
        var request = {
            source: recommended ? clean(selectedOs.url) : sourcePath,
            target: clean(target.path),
            raspberryPi: raspberryPi,
            sha256: recommended ? clean(selectedOs.sha256) : "",
            extractSize: recommended ? Number(selectedOs.extractSize || 0) : 0,
            customization: {
                hostname: hostname, username: username, password: password,
                locale: locale, timezone: timezone, keyboard: keyboardLayout,
                wifiCountry: wifiCountry, wifiSsid: wifiSsid, wifiPassword: wifiPassword,
                wifiHidden: wifiHidden, sshEnabled: sshEnabled,
                sshPasswordAuth: sshPasswordAuth, sshPublicKey: sshPublicKey,
                piConnect: piConnect, telemetry: telemetry
            }
        }
        if (!backend || !backend.startFlash(request)) {
            setStatus(backend ? backend.lastError : "Image flasher backend unavailable.", true); return
        }
        password = ""; wifiPassword = ""; armed = false; stage = "progress"; selectedIndex = 0
    }
    function goBack() {
        armed = false
        if (stage === "type") { closeWizard(); return }
        if (stage === "piMode") stage = "type"
        else if (stage === "model") stage = "piMode"
        else if (stage === "os") stage = "model"
        else if (stage === "file") stage = raspberryPi ? "piMode" : "type"
        else if (stage === "target") stage = recommended ? "os" : "file"
        else if (stage === "customize") stage = "target"
        else if (stage === "summary") stage = raspberryPi ? "customize" : "target"
        else if (stage === "complete") { devicesRefreshRequested(); closeWizard() }
        selectedIndex = 0
    }
    function itemCount() {
        if (stage === "type") return typeChoices.length
        if (stage === "piMode") return piModeChoices.length
        if (stage === "model") return backend && backend.raspberryModels ? backend.raspberryModels.length : 0
        if (stage === "os") return backend && backend.raspberryImages ? backend.raspberryImages.length : 0
        if (stage === "target") return targets.length
        if (stage === "customize") return customizationRows.length
        if (stage === "summary") return 1
        if (stage === "complete") return backend && backend.succeeded ? 3 : 2
        return 0
    }
    function move(delta) {
        var count = itemCount(); if (count <= 0) return
        selectedIndex = (selectedIndex + delta + count) % count
        if (stage === "os") osList.positionViewAtIndex(selectedIndex, ListView.Contain)
        else if (stage === "target") targetList.positionViewAtIndex(selectedIndex, ListView.Contain)
        else if (stage === "customize") customizeList.positionViewAtIndex(selectedIndex, ListView.Contain)
    }
    function activate() {
        armed = false
        if (stage === "type") {
            raspberryPi = selectedIndex === 1
            if (raspberryPi) { stage = "piMode"; selectedIndex = 0 }
            else { recommended = false; stage = "file"; selectedIndex = 0; openFilePicker() }
        } else if (stage === "piMode") {
            recommended = selectedIndex === 0
            if (recommended) { stage = "model"; selectedIndex = 0 }
            else { stage = "file"; selectedIndex = 0; openFilePicker() }
        } else if (stage === "model") {
            var model = currentModel(); modelId = clean(model.id); selectedIndex = 0; stage = "os"
            backend.fetchRaspberryCatalog(modelId)
        } else if (stage === "os") {
            if (!backend || backend.catalogBusy) return
            selectedOs = currentOs()
            if (selectedOs.available === false || !selectedOs.url) {
                setStatus(selectedOs.unavailableReason || "That image is not currently available for download.", true)
                return
            }
            sourcePath = selectedOs.url; enterTargetStage()
        } else if (stage === "file") openFilePicker()
        else if (stage === "target") {
            if (targets.length === 0) { setStatus("No eligible non-boot storage device is connected.", true); return }
            target = targets[selectedIndex]
            var check = backend.inspectTarget(target.path)
            if (!check.ok) { setStatus(check.message, true); refreshTargets(); return }
            if (raspberryPi) enterCustomization(); else enterSummary()
        } else if (stage === "customize") {
            var row = customizationRows[selectedIndex]
            if (row.kind === "toggle") toggleField(row.key)
            else if (row.kind === "action") enterSummary()
            else openKeyboardFor(row.key, row.title)
        } else if (stage === "summary") {
            if (!armed) { armed = true; setStatus("FLASH ARMED — press X again to permanently erase " + clean(target.path) + ".", true) }
            else startFlash()
        } else if (stage === "complete") {
            if (selectedIndex === 0 && backend && backend.succeeded) { backend.ejectTarget(target.path); setStatus("Eject requested. Wait until the device disappears before removing it.", false) }
            else if ((selectedIndex === 1 && backend && backend.succeeded) || (selectedIndex === 0 && backend && !backend.succeeded)) { armed = false; enterSummary() }
            else { devicesRefreshRequested(); closeWizard() }
        }
    }
    function handleControllerPressed(action) {
        if (!open) return false
        var a = String(action || "").toLowerCase().replace(/-/g, "_")
        if (a === "x" || a === "cross" || a === "primary") a = "primary"
        else if (a === "o" || a === "circle" || a === "cancel") a = "cancel"
        else if (a === "dpad_up") a = "up"
        else if (a === "dpad_down") a = "down"
        else if (a === "dpad_left") a = "left"
        else if (a === "dpad_right") a = "right"
        if (keyboardOpen) {
            flashKeyboard.forceActiveFocus()
            return flashKeyboard.handleControllerPressed(action)
        }
        if (filePickerOpen) {
            if (a === "cancel") { filePickerOpen = false; return true }
            if (a === "up") pickerIndex = Math.max(0, pickerIndex - 1)
            else if (a === "down") pickerIndex = Math.min(Math.max(0, pickerEntries.length - 1), pickerIndex + 1)
            else if (a === "left" || a === "triangle") { pickerPath = backend.parentDirectory(pickerPath); pickerIndex = 0; refreshPicker() }
            else if (a === "primary") choosePickerEntry()
            pickerList.positionViewAtIndex(pickerIndex, ListView.Contain)
            return true
        }
        if (stage === "progress") {
            if (a === "cancel" && backend && backend.canCancel) backend.cancel()
            return true
        }
        if (a === "cancel" || a === "left") { goBack(); return true }
        if (a === "up") move(-1)
        else if (a === "down") move(1)
        else if (a === "primary") activate()
        else if ((a === "right" || a === "left") && stage === "customize") {
            var row = customizationRows[selectedIndex]; if (row.kind === "toggle") toggleField(row.key)
        }
        return true
    }

    Connections {
        target: root.backend
        function onOperationFinished(success, message) {
            root.stage = "complete"; root.selectedIndex = 0; root.armed = false
            root.setStatus(message, !success); root.devicesRefreshRequested()
        }
    }

    Rectangle { anchors.fill: parent; color: "#F002060D" }
    Rectangle {
        anchors.fill: parent; anchors.margins: 34; radius: 34; color: root.panel
        border.width: 3; border.color: root.stage === "summary" && root.armed ? root.red : root.cyan
        Column {
            anchors.fill: parent; anchors.margins: 30; spacing: 14
            Row {
                width: parent.width; height: 78; spacing: 18
                Rectangle {
                    width: 64; height: 64; radius: root.raspberryPi ? 32 : 18
                    color: root.raspberryPi ? "#B51F49" : "#0D2B47"; border.width: 2; border.color: root.raspberryPi ? "#6EDB68" : root.cyan
                    Text { anchors.centerIn: parent; text: root.raspberryPi ? "π" : "▣"; color: root.white; font.pixelSize: 34; font.bold: true }
                }
                Column {
                    width: parent.width - 190; spacing: 5
                    Text { width: parent.width; text: root.stageTitle(); color: root.white; font.pixelSize: 31; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.stageSubtitle(); color: root.muted; font.pixelSize: 14; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                }
                Text { width: 90; text: root.raspberryPi ? "RASPBERRY\nPI" : "NEUTRONOS"; color: root.raspberryPi ? "#6EDB68" : root.cyan; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight }
            }
            Rectangle { width: parent.width; height: 1; color: "#29445F" }

            Item {
                width: parent.width; height: parent.height - 165

                ListView {
                    id: genericList
                    anchors.fill: parent; clip: true; spacing: 12
                    visible: root.stage === "type" || root.stage === "piMode" || root.stage === "model"
                    model: root.stage === "type" ? root.typeChoices : (root.stage === "piMode" ? root.piModeChoices : (root.backend ? root.backend.raspberryModels : []))
                    delegate: Rectangle {
                        required property int index; required property var modelData
                        width: genericList.width; height: 112; radius: 22
                        color: root.selectedIndex === index ? "#173D61" : root.raised
                        border.width: root.selectedIndex === index ? 3 : 1
                        border.color: root.selectedIndex === index ? root.cyan : "#29445F"
                        Row {
                            anchors.fill: parent; anchors.margins: 20; spacing: 20
                            Rectangle { width: 60; height: 60; radius: 18; color: "#102B48"; Text { anchors.centerIn: parent; text: modelData.icon || (root.stage === "model" ? "π" : "▣"); color: root.cyan; font.pixelSize: 28; font.bold: true } }
                            Column { width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                Text { width: parent.width; text: modelData.title || modelData.name; color: root.white; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.detail || modelData.description; color: root.muted; font.pixelSize: 14; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                ListView {
                    id: osList
                    anchors.fill: parent; clip: true; spacing: 10; visible: root.stage === "os"
                    model: root.backend ? root.backend.raspberryImages : []
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property bool neutronCard: String(modelData.source || "") === "github" || String(modelData.name || "").toLowerCase() === "neutronos"
                        readonly property bool availableCard: modelData.available !== false && String(modelData.url || "").length > 0
                        width: osList.width
                        height: 142
                        radius: 20
                        opacity: availableCard ? 1.0 : 0.62
                        color: neutronCard
                               ? (root.selectedIndex === index ? "#15553A" : "#0D3528")
                               : (root.selectedIndex === index ? "#173D61" : root.raised)
                        border.width: root.selectedIndex === index ? 3 : (neutronCard ? 2 : 1)
                        border.color: neutronCard ? root.green : (root.selectedIndex === index ? root.cyan : "#29445F")
                        Column {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 7
                            Row {
                                width: parent.width
                                spacing: 12
                                Text {
                                    width: parent.width - (neutronCard ? 330 : 190)
                                    text: modelData.name
                                    color: neutronCard ? root.green : root.white
                                    font.pixelSize: 20
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: neutronCard
                                    width: 126
                                    height: 28
                                    radius: 14
                                    color: "#174B35"
                                    border.width: 1
                                    border.color: root.green
                                    Text { anchors.centerIn: parent; text: "RECOMMENDED"; color: root.green; font.pixelSize: 11; font.bold: true }
                                }
                                Text {
                                    width: 170
                                    text: (modelData.architecture || "") + "  " + (modelData.releaseDate || "")
                                    color: neutronCard ? root.green : root.cyan
                                    font.pixelSize: 13
                                    font.bold: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                            Text { width: parent.width; text: (modelData.version ? modelData.version + " · " : "") + (modelData.group || "Raspberry Pi"); color: neutronCard ? "#9DFFC7" : root.gold; font.pixelSize: 13; font.bold: true }
                            Text { width: parent.width; text: modelData.description || "Compatible Raspberry Pi operating-system image"; color: root.muted; font.pixelSize: 14; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Text {
                                width: parent.width
                                text: availableCard
                                      ? "Download " + (root.backend ? root.backend.humanBytes(Number(modelData.downloadSize || 0)) : "—") + "  ·  Written size " + (root.backend ? root.backend.humanBytes(Number(modelData.extractSize || 0)) : "—")
                                      : (modelData.unavailableReason || "IMAGE NOT CURRENTLY AVAILABLE")
                                color: availableCard ? root.green : root.red
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: osList.count === 0; text: root.backend && root.backend.catalogBusy ? "LOADING OFFICIAL IMAGE CATALOG…" : "NO COMPATIBLE IMAGES FOUND"; color: root.muted; font.pixelSize: 20; font.bold: true }
                }

                ListView {
                    id: targetList
                    anchors.fill: parent; clip: true; spacing: 12; visible: root.stage === "target"
                    model: root.targets
                    delegate: Rectangle {
                        required property int index; required property var modelData
                        width: targetList.width; height: 118; radius: 22
                        color: root.selectedIndex === index ? "#4A202B" : root.raised
                        border.width: root.selectedIndex === index ? 3 : 1; border.color: root.selectedIndex === index ? root.red : "#29445F"
                        Row { anchors.fill: parent; anchors.margins: 20; spacing: 18
                            Text { text: "▣"; color: root.selectedIndex === index ? root.red : root.cyan; font.pixelSize: 38; anchors.verticalCenter: parent.verticalCenter }
                            Column { width: parent.width - 250; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                                Text { width: parent.width; text: modelData.model || modelData.path; color: root.white; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.path + "  ·  " + modelData.size; color: root.cyan; font.pixelSize: 15; font.bold: true }
                                Text { width: parent.width; text: (modelData.transport || "storage").toUpperCase() + (modelData.serial ? "  ·  " + modelData.serial : ""); color: root.muted; font.pixelSize: 13; elide: Text.ElideRight }
                            }
                            Text { width: 170; text: "ALL DATA\nWILL BE ERASED"; color: root.red; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: targetList.count === 0; text: "NO ELIGIBLE NON-BOOT STORAGE DEVICE FOUND\nConnect an SD card, USB drive, or external disk and reopen this page."; color: root.muted; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                }

                ListView {
                    id: customizeList
                    anchors.fill: parent; clip: true; spacing: 8; visible: root.stage === "customize"
                    model: root.customizationRows
                    delegate: Rectangle {
                        required property int index; required property var modelData
                        width: customizeList.width; height: 78; radius: 17
                        color: root.selectedIndex === index ? "#173D61" : root.raised
                        border.width: root.selectedIndex === index ? 2 : 1; border.color: root.selectedIndex === index ? root.cyan : "#29445F"
                        Row { anchors.fill: parent; anchors.margins: 16; spacing: 14
                            Column { width: parent.width - 290; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                                Text { width: parent.width; text: modelData.title; color: root.white; font.pixelSize: 17; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: modelData.detail; color: root.muted; font.pixelSize: 12; elide: Text.ElideRight }
                            }
                            Text { width: 250; text: root.fieldValue(modelData.key); color: modelData.kind === "action" ? root.green : root.cyan; font.pixelSize: 16; font.bold: true; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle }
                        }
                    }
                }

                Flickable {
                    anchors.fill: parent; visible: root.stage === "summary"; contentWidth: width; contentHeight: summaryColumn.height; clip: true
                    Column { id: summaryColumn; width: parent.width; spacing: 12
                        Rectangle { width: parent.width; height: 105; radius: 20; color: root.raised; border.width: 1; border.color: "#29445F"
                            Column { anchors.fill: parent; anchors.margins: 18; spacing: 7
                                Text { width: parent.width; text: "SOURCE IMAGE"; color: root.cyan; font.pixelSize: 14; font.bold: true }
                                Text { width: parent.width; text: root.recommended ? (root.selectedOs.name + " " + (root.selectedOs.version || "")) : root.sourcePath; color: root.white; font.pixelSize: 18; font.bold: true; elide: Text.ElideMiddle }
                                Text { width: parent.width; text: root.recommended ? (root.selectedOs.description || "Official Raspberry Pi image") : "Local disk image"; color: root.muted; font.pixelSize: 13; elide: Text.ElideRight }
                            }
                        }
                        Rectangle { width: parent.width; height: 105; radius: 20; color: "#33131B"; border.width: 2; border.color: root.red
                            Column { anchors.fill: parent; anchors.margins: 18; spacing: 7
                                Text { width: parent.width; text: "TARGET — ALL EXISTING DATA WILL BE ERASED"; color: root.red; font.pixelSize: 14; font.bold: true }
                                Text { width: parent.width; text: (root.target.model || root.target.path) + "  ·  " + root.target.path; color: root.white; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight }
                                Text { width: parent.width; text: root.target.size + "  ·  " + (root.target.transport || "storage").toUpperCase(); color: root.muted; font.pixelSize: 13 }
                            }
                        }
                        Rectangle { visible: root.raspberryPi; width: parent.width; height: 105; radius: 20; color: root.raised; border.width: 1; border.color: "#29445F"
                            Column { anchors.fill: parent; anchors.margins: 18; spacing: 7
                                Text { text: "FIRST-BOOT CUSTOMIZATION"; color: root.purple; font.pixelSize: 14; font.bold: true }
                                Text { width: parent.width; text: "Host " + root.hostname + "  ·  User " + root.username + "  ·  Wi-Fi " + (root.wifiSsid.length > 0 ? root.wifiSsid : "not configured") + "  ·  SSH " + (root.sshEnabled ? "enabled" : "disabled"); color: root.white; font.pixelSize: 15; elide: Text.ElideRight }
                                Text { width: parent.width; text: "Secrets are removed from NeutronOS memory and temporary request storage after the writer starts."; color: root.muted; font.pixelSize: 12; wrapMode: Text.WordWrap }
                            }
                        }
                        Rectangle { width: parent.width; height: 116; radius: 24; color: root.armed ? "#5A1B28" : "#0D2A23"; border.width: 3; border.color: root.armed ? root.red : root.green
                            Column { anchors.centerIn: parent; spacing: 8
                                Text { text: root.armed ? "PRESS X AGAIN — ERASE AND FLASH" : "X  ARM FLASH"; color: root.armed ? root.white : root.green; font.pixelSize: 24; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                Text { text: "Write, synchronize, customize, then read back and verify every written byte"; color: root.muted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                            }
                        }
                    }
                }

                Column {
                    anchors.fill: parent; visible: root.stage === "progress"; spacing: 22
                    Text { width: parent.width; text: (root.backend ? root.backend.stage : "PREPARING").toUpperCase(); color: root.gold; font.pixelSize: 27; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Text { width: parent.width; text: root.backend ? root.backend.status : "Starting image writer"; color: root.white; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                    Rectangle { width: parent.width; height: 32; radius: 16; color: root.inset; border.width: 1; border.color: "#29445F"
                        Rectangle { height: parent.height; radius: 16; width: root.backend && root.backend.progress >= 0 ? parent.width * Math.max(0, Math.min(100, root.backend.progress)) / 100 : parent.width * 0.16; color: root.backend && root.backend.stage === "verifying" ? root.green : root.gold }
                    }
                    Text { width: parent.width; text: root.backend && root.backend.progress >= 0 ? root.backend.progress + "%" : "WORKING"; color: root.cyan; font.pixelSize: 22; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Grid { width: parent.width; columns: 2; columnSpacing: 14; rowSpacing: 14
                        Repeater { model: [
                            {t:"WRITTEN",v:root.backend ? root.backend.humanBytes(root.backend.bytesDone) : "—"},
                            {t:"TOTAL",v:root.backend ? root.backend.humanBytes(root.backend.bytesTotal) : "—"},
                            {t:"SPEED",v:root.backend && root.backend.bytesPerSecond > 0 ? root.backend.humanBytes(root.backend.bytesPerSecond)+"/s" : "—"},
                            {t:"ETA",v:root.backend ? root.backend.formatDuration(root.backend.etaSeconds) : "—"}
                        ]; delegate: Rectangle { width: (parent.width - 14) / 2; height: 82; radius: 18; color: root.raised; border.width: 1; border.color: "#29445F"
                            Column { anchors.centerIn: parent; spacing: 6; Text { text: modelData.t; color: root.muted; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter } Text { text: modelData.v; color: root.white; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignHCenter } }
                        }}
                    }
                    Text { width: parent.width; text: root.backend && root.backend.canCancel ? "O cancels only before destructive writing begins" : "Do not disconnect or power off the target device"; color: root.backend && root.backend.canCancel ? root.cyan : root.red; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                }

                Column {
                    anchors.centerIn: parent; width: parent.width; visible: root.stage === "complete"; spacing: 20
                    Text { width: parent.width; text: root.backend && root.backend.succeeded ? "✓" : "!"; color: root.backend && root.backend.succeeded ? root.green : root.red; font.pixelSize: 76; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Text { width: parent.width; text: root.backend ? root.backend.status : root.statusMessage; color: root.white; font.pixelSize: 21; font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                    Text { width: parent.width; text: "Log: " + (root.backend ? root.backend.logPath : "—"); color: root.muted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 14
                        Repeater { model: root.backend && root.backend.succeeded ? ["EJECT","RETRY","DONE"] : ["RETRY","DONE"]
                            delegate: Rectangle { required property int index; required property var modelData; width: 210; height: 74; radius: 37; color: root.selectedIndex === index ? (modelData === "EJECT" ? root.green : root.blue) : root.raised; border.width: root.selectedIndex === index ? 3 : 1; border.color: modelData === "EJECT" ? root.green : root.blue
                                Text { anchors.centerIn: parent; text: modelData; color: root.selectedIndex === index ? "#FFFFFF" : (modelData === "EJECT" ? root.green : root.blue); font.pixelSize: 17; font.bold: true }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 54; radius: 18; color: root.statusError ? "#451923" : root.inset; border.width: 1; border.color: root.statusError ? root.red : "#29445F"
                Text { anchors.fill: parent; anchors.margins: 12; text: root.statusMessage.length > 0 ? root.statusMessage : "↑/↓ Navigate   X Select   O Back"; color: root.statusError ? "#FF9CAA" : root.muted; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
            }
        }
    }

    Rectangle {
        anchors.fill: parent; visible: root.filePickerOpen; color: "#F002060D"; z: 2300
        Rectangle { anchors.centerIn: parent; width: Math.min(parent.width - 100, 1050); height: Math.min(parent.height - 90, 760); radius: 30; color: "#FC081729"; border.width: 3; border.color: root.cyan
            Column { anchors.fill: parent; anchors.margins: 28; spacing: 13
                Text { text: "CHOOSE IMAGE FILE"; color: root.white; font.pixelSize: 29; font.bold: true }
                Text { width: parent.width; text: root.pickerPath; color: root.cyan; font.pixelSize: 14; elide: Text.ElideMiddle }
                Rectangle { width: parent.width; height: 1; color: "#29445F" }
                ListView { id: pickerList; width: parent.width; height: parent.height - 145; clip: true; spacing: 7; model: root.pickerEntries
                    delegate: Rectangle { required property int index; required property var modelData; width: pickerList.width; height: 60; radius: 15; color: root.pickerIndex === index ? "#173D61" : root.raised; border.width: root.pickerIndex === index ? 2 : 1; border.color: root.pickerIndex === index ? root.cyan : "#29445F"
                        Row { anchors.fill: parent; anchors.margins: 14; spacing: 14
                            Text { text: modelData.directory ? "▣" : "≡"; color: modelData.directory ? root.purple : root.green; font.pixelSize: 22 }
                            Text { width: parent.width - 175; text: modelData.name; color: root.white; font.pixelSize: 16; font.bold: root.pickerIndex === index; elide: Text.ElideMiddle }
                            Text { width: 130; text: modelData.size || ""; color: root.muted; font.pixelSize: 13; horizontalAlignment: Text.AlignRight }
                        }
                    }
                    Text { anchors.centerIn: parent; visible: pickerList.count === 0; text: "No supported image files in this folder"; color: root.muted; font.pixelSize: 17 }
                }
                Text { text: "X Open / Select   △ or ← Parent   O Cancel"; color: root.muted; font.pixelSize: 13 }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.keyboardOpen
        enabled: visible
        color: "#F202060D"
        z: 2400
        focus: visible

        Timer {
            id: keyboardFocusWatchdog
            interval: 180
            repeat: true
            running: root.keyboardOpen
            onTriggered: {
                if (root.keyboardOpen && !flashKeyboard.activeFocus)
                    flashKeyboard.forceActiveFocus()
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                width: flashKeyboard.width
                height: 68
                radius: 18
                color: "#FC081729"
                border.width: 2
                border.color: root.cyan
                Row {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 16
                    Text { width: 210; text: root.keyboardTitle; color: root.white; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width - 470; text: root.keyboardField.indexOf("password") >= 0 ? (root.keyboardDraft.length > 0 ? "••••••••" : "") : root.keyboardDraft; color: root.cyan; font.pixelSize: 18; font.bold: true; elide: Text.ElideMiddle }
                    Text { width: 105; text: "O  CANCEL"; color: root.red; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight }
                    Text { width: 105; text: "R2  APPLY"; color: root.green; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight }
                }
            }

            VirtualKeyboard {
                id: flashKeyboard
                visibleMode: false
                title: root.keyboardTitle
                cancelBehavior: "close"
                active: root.keyboardOpen
                enabled: root.keyboardOpen
                focus: root.keyboardOpen
                onKeyPressed: function(value) { root.appendKeyboardText(value) }
                onBackspacePressed: { root.keyboardDraft = root.keyboardDraft.slice(0, -1) }
                onEnterPressed: root.closeKeyboard(true)
                onClosePressed: root.closeKeyboard(false)
            }

            Rectangle {
                width: flashKeyboard.width
                height: 58
                radius: 18
                color: "#FC081729"
                border.width: 1
                border.color: "#29445F"
                Text {
                    anchors.centerIn: parent
                    text: "D-PAD / STICK  MOVE    X  SELECT KEY    TRIANGLE  CAPS    R3  SYMBOLS    L3  TAB    O  CANCEL    R2  APPLY"
                    color: root.muted
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }
    }
}
