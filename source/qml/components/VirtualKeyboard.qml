import QtQuick 2.15
import QtQuick.Controls 2.15
import NeutronOS.Managers 1.0

Item {
    id: keyboard

    signal keyPressed(string value)
    signal backspacePressed()
    signal enterPressed()
    signal closePressed()
    signal clearAllRequested()
    signal modeChanged(string mode)
    signal settingsRequested()
    signal languageRequested()

    property bool visibleMode: false
    property bool largeMode: true
    property bool specialMode: false
    property bool capsMode: false
    property bool shiftOnce: false
    property bool active: true
    property bool animationsEnabled: true
    property real sizeMultiplier: 1.0
    property bool resetOnOpen: false
    property string cancelBehavior: "close"
    property int selectedIndex: 0
    property string title: "NeutronOS Keyboard"

    // Compatibility properties used by existing Settings keyboard preferences.
    property string layout: "qwerty"
    property int spacing: 7
    property int keyScale: 100
    property string keyShape: "rounded"
    property string tint: "neutron"
    property string labels: "standard"
    property string focusStyle: "ring"
    property string armedStyle: "ring"

    readonly property color spaceBlack: "#010308"
    readonly property color navy: "#050A12"
    readonly property color navyRaised: "#0A1320"
    readonly property color navySelected: "#14131A"
    readonly property color blue: "#4BB8FF"
    readonly property color blueSoft: "#7CCBFF"
    readonly property color red: "#FF3048"
    readonly property color redDeep: "#3B0D16"
    readonly property color redKey: "#46111B"
    readonly property color redKeySelected: "#5A1421"
    readonly property color green: "#29E68B"
    readonly property color purple: "#9B7CFF"
    readonly property color purpleDeep: "#241C3E"
    readonly property color steel: "#6E8BA4"
    readonly property color steelDeep: "#111A26"
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: "#9EADC0"
    readonly property color divider: "#26384C"

    // Visual hierarchy: navy-black is the primary surface, Neutron red is a
    // restrained accent, and every key label stays white. Selection is always
    // communicated by a red focus glow. Backspace and Close remain explicitly
    // red even when they are not selected.

    property bool backspaceHeld: false
    property int lastNavigationMs: 0
    property int navigationRepeatMs: 135
    property int keyboardLayer: 0 // 0 ABC, 1 symbols, 2 special symbols

    readonly property bool remotePanelVisible: visibleMode && RemoteKeyboardManager.pairingPanelVisible
    readonly property bool remoteRunning: RemoteKeyboardManager.running
    readonly property bool remoteCodeActive: RemoteKeyboardManager.pairingCodeActive
    readonly property bool remoteConnected: RemoteKeyboardManager.authenticatedClientCount > 0
    readonly property var controllerHints: remotePanelVisible
        ? (remoteConnected
           ? ["SECURITY GUARD  •  ONE REMOTE DEVICE", "O / PS  BACK"]
           : ["X  GENERATE CODE", "O / PS  BACK"])
        : ["D-PAD  KEYS", "X  SELECT", "O  CLOSE", "△  SPACE",
           "□  BACKSPACE / HOLD DELETE", "START  ENTER", "L2  CAPS",
           "R3  SYMBOLS", "L3  SPECIAL", "PS  REMOTE"]

    implicitWidth: 1820
    implicitHeight: 432
    width: implicitWidth
    height: implicitHeight

    opacity: visibleMode ? 1.0 : 0.0
    visible: visibleMode || opacity > 0.0
    enabled: active
    focus: visibleMode

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Timer {
        id: backspaceHoldDelay
        interval: 360
        repeat: false
        onTriggered: {
            if (keyboard.backspaceHeld)
                backspaceRepeat.start()
        }
    }

    Timer {
        id: backspaceRepeat
        interval: 58
        repeat: true
        onTriggered: {
            if (keyboard.backspaceHeld)
                keyboard.backspacePressed()
            else
                stop()
        }
    }

    // The release signal is listened to directly so a parent app that forgets
    // to forward button-release events cannot leave backspace stuck on repeat.
    Connections {
        target: (typeof controllerManager !== "undefined" && controllerManager) ? controllerManager : null
        ignoreUnknownSignals: true
        function onButtonReleased(button) {
            if (!keyboard.visibleMode)
                return
            var action = keyboard.normalizeControllerButton(button)
            if (action === "SQUARE")
                keyboard.handleControllerReleased(button)
        }
    }

    Connections {
        target: RemoteKeyboardManager
        ignoreUnknownSignals: true

        function onTextSubmitted(text) {
            if (!keyboard.visibleMode || !keyboard.active)
                return
            keyboard.injectRemoteText(text)
        }

        function onBackspaceRequested(count) {
            if (!keyboard.visibleMode || !keyboard.active)
                return
            var total = Math.max(1, Math.min(128, Number(count || 1)))
            for (var i = 0; i < total; ++i)
                keyboard.backspacePressed()
        }

        function onEnterRequested() {
            if (keyboard.visibleMode && keyboard.active)
                keyboard.enterPressed()
        }
    }

    onVisibleModeChanged: {
        RemoteKeyboardManager.setKeyboardActive(visibleMode && active)
        if (!visibleMode)
            resetHeldInputState()
    }

    onActiveChanged: {
        RemoteKeyboardManager.setKeyboardActive(visibleMode && active)
    }

    Component.onCompleted: RemoteKeyboardManager.setKeyboardActive(visibleMode && active)

    Component.onDestruction: {
        if (visibleMode)
            RemoteKeyboardManager.setKeyboardActive(false)
    }

    // Full physical-keyboard geometry from the supplied NeutronOS reference:
    // number row, staggered QWERTY rows, full-size modifiers, and a real space
    // bar. No character key is reduced below the common full-size key unit.
    property var normalRows: [
        [
            {label:"1",value:"1",shifted:"!",type:"char",w:1}, {label:"2",value:"2",shifted:"@",type:"char",w:1},
            {label:"3",value:"3",shifted:"#",type:"char",w:1}, {label:"4",value:"4",shifted:"$",type:"char",w:1},
            {label:"5",value:"5",shifted:"%",type:"char",w:1}, {label:"6",value:"6",shifted:"^",type:"char",w:1},
            {label:"7",value:"7",shifted:"&",type:"char",w:1}, {label:"8",value:"8",shifted:"*",type:"char",w:1},
            {label:"9",value:"9",shifted:"(",type:"char",w:1}, {label:"0",value:"0",shifted:")",type:"char",w:1},
            {label:"-",value:"-",shifted:"_",type:"char",w:1}, {label:"=",value:"=",shifted:"+",type:"char",w:1},
            {label:"BACKSPACE",value:"BACK",type:"back",w:1.85}
        ],
        [
            {label:"TAB",value:"\t",type:"char",w:1.45},
            {label:"Q",value:"Q",type:"letter",w:1}, {label:"W",value:"W",type:"letter",w:1},
            {label:"E",value:"E",type:"letter",w:1}, {label:"R",value:"R",type:"letter",w:1},
            {label:"T",value:"T",type:"letter",w:1}, {label:"Y",value:"Y",type:"letter",w:1},
            {label:"U",value:"U",type:"letter",w:1}, {label:"I",value:"I",type:"letter",w:1},
            {label:"O",value:"O",type:"letter",w:1}, {label:"P",value:"P",type:"letter",w:1},
            {label:"[",value:"[",shifted:"{",type:"char",w:1}, {label:"]",value:"]",shifted:"}",type:"char",w:1},
            {label:"\\",value:"\\",shifted:"|",type:"char",w:1.35}
        ],
        [
            {label:"CAPS",value:"CAPS",type:"caps",w:1.8},
            {label:"A",value:"A",type:"letter",w:1}, {label:"S",value:"S",type:"letter",w:1},
            {label:"D",value:"D",type:"letter",w:1}, {label:"F",value:"F",type:"letter",w:1},
            {label:"G",value:"G",type:"letter",w:1}, {label:"H",value:"H",type:"letter",w:1},
            {label:"J",value:"J",type:"letter",w:1}, {label:"K",value:"K",type:"letter",w:1},
            {label:"L",value:"L",type:"letter",w:1}, {label:";",value:";",shifted:":",type:"char",w:1},
            {label:"'",value:"'",shifted:"\"",type:"char",w:1},
            {label:"ENTER",value:"ENTER",type:"enter",w:2.05}
        ],
        [
            {label:"SHIFT",value:"SHIFT",type:"shift",w:2.25},
            {label:"Z",value:"Z",type:"letter",w:1}, {label:"X",value:"X",type:"letter",w:1},
            {label:"C",value:"C",type:"letter",w:1}, {label:"V",value:"V",type:"letter",w:1},
            {label:"B",value:"B",type:"letter",w:1}, {label:"N",value:"N",type:"letter",w:1},
            {label:"M",value:"M",type:"letter",w:1}, {label:",",value:",",shifted:"<",type:"char",w:1},
            {label:".",value:".",shifted:">",type:"char",w:1}, {label:"/",value:"/",shifted:"?",type:"char",w:1},
            {label:"SHIFT",value:"SHIFT",type:"shift",w:2.55}
        ],
        [
            {label:"CLOSE",value:"CLOSE",type:"close",w:1.8},
            {label:"SPACE",value:"SPACE",type:"space",w:7.4},
            {label:"ENTER",value:"ENTER",type:"enter",w:2.0}
        ]
    ]

    property var symbolRows: [
        [
            {label:"!",value:"!",type:"char",w:1}, {label:"@",value:"@",type:"char",w:1},
            {label:"#",value:"#",type:"char",w:1}, {label:"$",value:"$",type:"char",w:1},
            {label:"%",value:"%",type:"char",w:1}, {label:"^",value:"^",type:"char",w:1},
            {label:"&",value:"&",type:"char",w:1}, {label:"*",value:"*",type:"char",w:1},
            {label:"(",value:"(",type:"char",w:1}, {label:")",value:")",type:"char",w:1},
            {label:"⌫",value:"BACK",type:"back",w:1.35}
        ],
        [
            {label:"-",value:"-",type:"char",w:1}, {label:"_",value:"_",type:"char",w:1},
            {label:"+",value:"+",type:"char",w:1}, {label:"=",value:"=",type:"char",w:1},
            {label:"/",value:"/",type:"char",w:1}, {label:"\\",value:"\\",type:"char",w:1},
            {label:"|",value:"|",type:"char",w:1}, {label:";",value:";",type:"char",w:1},
            {label:":",value:":",type:"char",w:1}, {label:"?",value:"?",type:"char",w:1},
            {label:"ENTER",value:"ENTER",type:"enter",w:1.35}
        ],
        [
            {label:"'",value:"'",type:"char",w:1}, {label:"\"",value:"\"",type:"char",w:1},
            {label:"<",value:"<",type:"char",w:1}, {label:">",value:">",type:"char",w:1},
            {label:"[",value:"[",type:"char",w:1}, {label:"]",value:"]",type:"char",w:1},
            {label:"{",value:"{",type:"char",w:1}, {label:"}",value:"}",type:"char",w:1},
            {label:"~",value:"~",type:"char",w:1}, {label:"`",value:"`",type:"char",w:1},
            {label:"@",value:"@",type:"char",w:1}
        ],
        [
            {label:"ABC",value:"ABC",type:"mode",w:1.3}, {label:".",value:".",type:"char",w:1},
            {label:",",value:",",type:"char",w:1}, {label:":",value:":",type:"char",w:1},
            {label:";",value:";",type:"char",w:1}, {label:"SPACE",value:"SPACE",type:"space",w:4.7},
            {label:"CLOSE",value:"CLOSE",type:"close",w:1.3}, {label:"ENTER",value:"ENTER",type:"enter",w:1.5}
        ]
    ]

    property var extendedRows: [
        [
            {label:"€",value:"€",type:"char",w:1}, {label:"£",value:"£",type:"char",w:1},
            {label:"¥",value:"¥",type:"char",w:1}, {label:"¢",value:"¢",type:"char",w:1},
            {label:"°",value:"°",type:"char",w:1}, {label:"±",value:"±",type:"char",w:1},
            {label:"×",value:"×",type:"char",w:1}, {label:"÷",value:"÷",type:"char",w:1},
            {label:"≈",value:"≈",type:"char",w:1}, {label:"≠",value:"≠",type:"char",w:1},
            {label:"⌫",value:"BACK",type:"back",w:1.35}
        ],
        [
            {label:"≤",value:"≤",type:"char",w:1}, {label:"≥",value:"≥",type:"char",w:1},
            {label:"∞",value:"∞",type:"char",w:1}, {label:"√",value:"√",type:"char",w:1},
            {label:"π",value:"π",type:"char",w:1}, {label:"µ",value:"µ",type:"char",w:1},
            {label:"©",value:"©",type:"char",w:1}, {label:"®",value:"®",type:"char",w:1},
            {label:"™",value:"™",type:"char",w:1}, {label:"•",value:"•",type:"char",w:1},
            {label:"ENTER",value:"ENTER",type:"enter",w:1.35}
        ],
        [
            {label:"←",value:"←",type:"char",w:1}, {label:"→",value:"→",type:"char",w:1},
            {label:"↑",value:"↑",type:"char",w:1}, {label:"↓",value:"↓",type:"char",w:1},
            {label:"✓",value:"✓",type:"char",w:1}, {label:"✕",value:"✕",type:"char",w:1},
            {label:"§",value:"§",type:"char",w:1}, {label:"¶",value:"¶",type:"char",w:1},
            {label:"…",value:"…",type:"char",w:1}, {label:"·",value:"·",type:"char",w:1},
            {label:"_",value:"_",type:"char",w:1}
        ],
        [
            {label:"ABC",value:"ABC",type:"mode",w:1.3}, {label:"(",value:"(",type:"char",w:1},
            {label:")",value:")",type:"char",w:1}, {label:"[",value:"[",type:"char",w:1},
            {label:"]",value:"]",type:"char",w:1}, {label:"SPACE",value:"SPACE",type:"space",w:4.7},
            {label:"CLOSE",value:"CLOSE",type:"close",w:1.3}, {label:"ENTER",value:"ENTER",type:"enter",w:1.5}
        ]
    ]

    readonly property var currentRows: keyboardLayer === 1 ? symbolRows : keyboardLayer === 2 ? extendedRows : normalRows

    function keyWeight(data) {
        var value = Number(data && data.w !== undefined ? data.w : 1)
        return isFinite(value) && value > 0 ? value : 1
    }

    function rowWeight(row) {
        var total = 0
        for (var i = 0; i < row.length; ++i)
            total += keyWeight(row[i])
        return Math.max(1, total)
    }

    function maximumRowWeight() {
        var maximum = 1
        for (var r = 0; r < currentRows.length; ++r)
            maximum = Math.max(maximum, rowWeight(currentRows[r] || []))
        return maximum
    }

    function maximumRowKeyCount() {
        var maximum = 1
        for (var r = 0; r < currentRows.length; ++r)
            maximum = Math.max(maximum, (currentRows[r] || []).length)
        return maximum
    }

    function flatCount() {
        var total = 0
        for (var r = 0; r < currentRows.length; ++r)
            total += currentRows[r].length
        return total
    }

    function globalIndex(row, col) {
        var value = 0
        for (var r = 0; r < row; ++r)
            value += currentRows[r].length
        return value + col
    }

    function keyAtIndex(indexValue) {
        var cursor = 0
        for (var r = 0; r < currentRows.length; ++r) {
            for (var c = 0; c < currentRows[r].length; ++c) {
                if (cursor === indexValue)
                    return { row:r, col:c, data:currentRows[r][c] }
                ++cursor
            }
        }
        return null
    }

    function keyCenter(row, col) {
        var data = currentRows[row]
        var total = rowWeight(data)
        var before = 0
        for (var i = 0; i < col; ++i)
            before += keyWeight(data[i])
        return (before + keyWeight(data[col]) / 2.0) / total
    }

    function bestIndexInRow(row, normalizedCenter) {
        var data = currentRows[row]
        var best = 0
        var bestDistance = 999
        for (var i = 0; i < data.length; ++i) {
            var distance = Math.abs(keyCenter(row, i) - normalizedCenter)
            if (distance < bestDistance) {
                bestDistance = distance
                best = i
            }
        }
        return globalIndex(row, best)
    }

    function clampSelected() {
        selectedIndex = Math.max(0, Math.min(Math.max(0, flatCount() - 1), selectedIndex))
    }

    function shiftedStateActive() {
        return keyboardLayer === 0 && (capsMode || shiftOnce)
    }

    function effectiveKeyValue(data) {
        if (!data)
            return ""
        if (data.type === "letter")
            return shiftedStateActive() ? String(data.value).toUpperCase() : String(data.value).toLowerCase()
        if (keyboardLayer === 0 && data.shifted !== undefined && shiftedStateActive())
            return String(data.shifted)
        return String(data.value === undefined ? "" : data.value)
    }

    function displayLabel(data) {
        if (!data)
            return ""
        if (data.type === "letter" || (keyboardLayer === 0 && data.shifted !== undefined))
            return effectiveKeyValue(data)
        return String(data.label || data.value || "")
    }

    function modeLabel() {
        if (keyboardLayer === 1) return "SYMBOLS"
        if (keyboardLayer === 2) return "SPECIAL"
        return capsMode ? "CAPS" : "ABC"
    }

    function openKeyboard(sizeMode) {
        largeMode = sizeMode !== "small" && sizeMode !== false
        capsMode = false
        shiftOnce = false
        keyboardLayer = 0
        specialMode = false
        if (resetOnOpen)
            resetKeyboard()
        visibleMode = true
        forceActiveFocus()
        clampSelected()
    }

    function closeKeyboard() {
        resetHeldInputState()
        RemoteKeyboardManager.hidePairingPanel()
        if (!visibleMode)
            return
        visibleMode = false
        closePressed()
    }

    function resetHeldInputState() {
        backspaceHeld = false
        backspaceHoldDelay.stop()
        backspaceRepeat.stop()
    }

    function resetKeyboard() {
        capsMode = false
        shiftOnce = false
        keyboardLayer = 0
        specialMode = false
        selectedIndex = 0
        modeChanged("normal")
    }

    function currentKey() {
        var item = keyAtIndex(selectedIndex)
        return item ? displayLabel(item.data) : ""
    }

    function selectedKeyData() {
        var item = keyAtIndex(selectedIndex)
        return item ? item.data : null
    }

    function move(direction) {
        if (!visibleMode || !enabled || !active || remotePanelVisible)
            return
        clampSelected()
        var current = keyAtIndex(selectedIndex)
        if (!current)
            return
        if (direction === "L" || direction === "LEFT") {
            selectedIndex = globalIndex(current.row, Math.max(0, current.col - 1))
        } else if (direction === "R" || direction === "RIGHT") {
            selectedIndex = globalIndex(current.row, Math.min(currentRows[current.row].length - 1, current.col + 1))
        } else if (direction === "U" || direction === "UP") {
            selectedIndex = bestIndexInRow(Math.max(0, current.row - 1), keyCenter(current.row, current.col))
        } else if (direction === "D" || direction === "DOWN") {
            selectedIndex = bestIndexInRow(Math.min(currentRows.length - 1, current.row + 1), keyCenter(current.row, current.col))
        }
    }

    function setLayer(newLayer) {
        keyboardLayer = newLayer
        specialMode = keyboardLayer !== 0
        shiftOnce = false
        clampSelected()
        modeChanged(keyboardLayer === 0 ? "normal" : keyboardLayer === 1 ? "symbols" : "special")
    }

    function toggleSymbols() {
        setLayer(keyboardLayer === 1 ? 0 : 1)
    }

    function toggleSpecialSymbols() {
        setLayer(keyboardLayer === 2 ? 0 : 2)
    }

    function cycleLayer(delta) {
        var nextLayer = (keyboardLayer + Number(delta || 0)) % 3
        if (nextLayer < 0)
            nextLayer += 3
        setLayer(nextLayer)
    }

    function pressSelected() {
        if (!visibleMode || !enabled || !active || remotePanelVisible)
            return
        clampSelected()
        var item = keyAtIndex(selectedIndex)
        if (!item || !item.data)
            return
        var data = item.data
        var type = String(data.type || "char")
        var value = String(data.value === undefined ? "" : data.value)

        if (type === "enter" || value === "ENTER") { enterPressed(); return }
        if (type === "back" || value === "BACK") { backspacePressed(); return }
        if (type === "close" || value === "CLOSE") { closeKeyboard(); return }
        if (type === "clear" || value === "CLEAR") { clearAllRequested(); return }
        if (type === "mode" || value === "SPEC" || value === "ABC") { setLayer(keyboardLayer === 0 ? 1 : 0); return }
        if (type === "caps" || value === "CAPS") {
            capsMode = !capsMode
            shiftOnce = false
            modeChanged(capsMode ? "caps" : "lower")
            return
        }
        if (type === "shift" || value === "SHIFT") {
            shiftOnce = !shiftOnce
            modeChanged(shiftOnce ? "shift" : "normal")
            return
        }
        if (type === "space" || value === "SPACE") {
            keyPressed(" ")
            shiftOnce = false
            return
        }
        if (type === "letter" || (keyboardLayer === 0 && data.shifted !== undefined)) {
            keyPressed(effectiveKeyValue(data))
            shiftOnce = false
            return
        }
        keyPressed(value)
        shiftOnce = false
    }

    function pressEnter() {
        if (!visibleMode || !enabled || !active)
            return false
        enterPressed()
        return true
    }

    function normalizeControllerButton(button) {
        var b = String(button || "").trim().toUpperCase().replace(/-/g, "_")
        if (b === "DPAD_UP") return "UP"
        if (b === "DPAD_DOWN") return "DOWN"
        if (b === "DPAD_LEFT") return "LEFT"
        if (b === "DPAD_RIGHT") return "RIGHT"
        if (b === "PRIMARY" || b === "CROSS" || b === "A" || b === "X" || b === "PS_CROSS") return "X"
        if (b === "CANCEL" || b === "CIRCLE" || b === "B" || b === "O" || b === "PS_CIRCLE") return "O"
        if (b === "SECONDARY" || b === "SQUARE" || b === "XBOX_X" || b === "PS_SQUARE") return "SQUARE"
        if (b === "CONTEXT" || b === "TRI" || b === "TRIANGLE" || b === "Y" || b === "PS_TRIANGLE") return "TRIANGLE"
        if (b === "SYSTEM" || b === "OPTIONS" || b === "OPTION" || b === "START" || b === "MENU") return "START"
        if (b === "HOME" || b === "PS" || b === "PLAYSTATION" || b === "GUIDE") return "HOME"
        if (b === "L1" || b === "LB") return "L1"
        if (b === "R1" || b === "RB") return "R1"
        if (b === "L2" || b === "LT" || b === "LEFTTRIGGER") return "L2"
        if (b === "R2" || b === "RT" || b === "RIGHTTRIGGER") return "R2"
        if (b === "L3" || b === "LS" || b === "LEFTSTICK" || b === "LEFT_STICK_BUTTON") return "L3"
        if (b === "R3" || b === "RS" || b === "RIGHTSTICK" || b === "RIGHT_STICK_BUTTON") return "R3"
        return b
    }

    function navigationAllowed() {
        var now = Date.now()
        if (now - lastNavigationMs < navigationRepeatMs)
            return false
        lastNavigationMs = now
        return true
    }

    function handleController(button) {
        if (!visibleMode || !enabled || !active)
            return false
        var action = normalizeControllerButton(button)

        if (remotePanelVisible) {
            // Circle and PS both leave Remote and return to the keyboard.
            if (action === "O" || action === "HOME") {
                RemoteKeyboardManager.hidePairingPanel()
                forceActiveFocus()
                return true
            }
            if (action === "X" && !remoteConnected) {
                RemoteKeyboardManager.generatePairingCode()
                return true
            }
            return true
        }

        if (action === "LEFT") { if (navigationAllowed()) move("L"); return true }
        if (action === "RIGHT") { if (navigationAllowed()) move("R"); return true }
        if (action === "UP") { if (navigationAllowed()) move("U"); return true }
        if (action === "DOWN") { if (navigationAllowed()) move("D"); return true }
        if (action === "X") { pressSelected(); return true }
        if (action === "O") { closeKeyboard(); return true }
        if (action === "TRIANGLE") { keyPressed(" "); shiftOnce = false; return true }
        if (action === "SQUARE") {
            if (!backspaceHeld) {
                backspaceHeld = true
                backspacePressed()
                backspaceHoldDelay.restart()
            }
            return true
        }
        if (action === "START") { enterPressed(); return true }
        if (action === "L2") {
            capsMode = !capsMode
            shiftOnce = false
            modeChanged(capsMode ? "caps" : "lower")
            return true
        }
        if (action === "R3") { toggleSymbols(); return true }
        if (action === "L3") { toggleSpecialSymbols(); return true }
        if (action === "HOME") { RemoteKeyboardManager.showPairingPanel(); return true }
        return true
    }

    function handleControllerPressed(button) {
        return handleController(button)
    }

    function handleControllerReleased(button) {
        var action = normalizeControllerButton(button)
        if (action === "SQUARE") {
            backspaceHeld = false
            backspaceHoldDelay.stop()
            backspaceRepeat.stop()
        }
        return visibleMode
    }

    function clearEnteredText() {
        clearAllRequested()
    }

    function injectRemoteText(text) {
        var value = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
        var parts = value.split("\n")
        for (var i = 0; i < parts.length; ++i) {
            if (parts[i].length > 0)
                keyPressed(parts[i])
            if (i < parts.length - 1)
                enterPressed()
        }
    }

    Rectangle {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.min(parent.height, keyboard.largeMode ? 432 : 416)
        radius: 22
        color: "#F2030710"
        border.width: 1
        border.color: keyboard.remotePanelVisible ? keyboard.red : "#30445B"
        clip: true

        // Near-black navy base. The red treatment is deliberately confined to
        // shallow edge washes instead of tinting the whole keyboard red.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#0A1320"
            opacity: 0.46
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 2
            color: keyboard.red
            opacity: 0.62
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width * 0.30
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#20B7293A" }
                GradientStop { position: 0.46; color: "#0CB7293A" }
                GradientStop { position: 1.0; color: "#00B7293A" }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: parent.width * 0.24
            height: parent.height * 0.72
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00B7293A" }
                GradientStop { position: 1.0; color: "#12B7293A" }
            }
        }

        Rectangle {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            height: 40
            radius: 12
            color: "#E3070D16"
            border.width: 1
            border.color: "#2A3D52"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 7
                    height: 22
                    radius: 3
                    color: keyboard.red
                }

                Text {
                    text: keyboard.remotePanelVisible ? "REMOTE KEYBOARD" : keyboard.title
                    color: keyboard.textPrimary
                    font.pixelSize: 15
                    font.bold: true
                    font.letterSpacing: 0.8
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    width: modeText.implicitWidth + 18
                    height: 24
                    radius: 12
                    color: keyboard.keyboardLayer !== 0 || keyboard.capsMode
                           ? keyboard.redDeep : "#0B1624"
                    border.width: 1
                    border.color: keyboard.keyboardLayer !== 0 || keyboard.capsMode
                                  ? keyboard.red : keyboard.divider
                    Text {
                        id: modeText
                        anchors.centerIn: parent
                        text: keyboard.modeLabel()
                        color: "#FFFFFF"
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                }

                Rectangle {
                    width: keyboard.remoteConnected ? 116 : 92
                    height: 24
                    radius: 12
                    color: keyboard.remoteConnected || RemoteKeyboardManager.running ? "#0A2A1D" : "#171C26"
                    border.width: 1
                    border.color: keyboard.remoteConnected || RemoteKeyboardManager.running ? keyboard.green : keyboard.divider
                    Text {
                        anchors.centerIn: parent
                        text: keyboard.remoteConnected ? "CONNECTED"
                              : RemoteKeyboardManager.running ? "REMOTE ON" : "LOCAL"
                        color: keyboard.remoteConnected || RemoteKeyboardManager.running ? keyboard.green : keyboard.textSecondary
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Item {
            id: keyDeck
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            opacity: keyboard.remotePanelVisible ? 0.0 : 1.0
            scale: keyboard.remotePanelVisible ? 0.96 : 1.0
            transformOrigin: Item.Center
            visible: opacity > 0.01

            readonly property real rowSpacing: 7
            readonly property real keySpacing: 8
            readonly property int rowCount: Math.max(1, keyboard.currentRows.length)
            readonly property int maximumKeyCount: keyboard.maximumRowKeyCount()
            readonly property real maximumWeight: keyboard.maximumRowWeight()
            readonly property real keyHeight: Math.max(34, Math.floor(
                (height - rowSpacing * Math.max(0, rowCount - 1)) / rowCount))
            readonly property real widthFitUnit: Math.max(34,
                (width - keySpacing * Math.max(0, maximumKeyCount - 1)) / maximumWeight)
            // The prior square-key rule let the five-row vertical constraint
            // shrink every key to roughly half the useful deck width. Keep the
            // rows professionally proportioned: use the model's key weights,
            // make ordinary keys comfortably wide, and retain the full-size
            // space/action keys without allowing an extreme aspect ratio.
            readonly property real keyUnitWidth: Math.max(34, Math.floor(
                Math.min(widthFitUnit, keyHeight * 2.05)))

            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }

            Column {
                anchors.centerIn: parent
                width: parent.width
                height: keyDeck.rowCount * keyDeck.keyHeight
                        + Math.max(0, keyDeck.rowCount - 1) * keyDeck.rowSpacing
                spacing: keyDeck.rowSpacing

                Repeater {
                    model: keyboard.currentRows.length

                    Item {
                        id: keyRowDelegate

                        property int rowNumber: index
                        property var rowData: keyboard.currentRows[rowNumber] || []
                        width: parent.width
                        height: keyDeck.keyHeight

                        Row {
                            id: keyRow

                            anchors.horizontalCenter: parent.horizontalCenter
                            width: keyboard.rowWeight(keyRowDelegate.rowData) * keyDeck.keyUnitWidth
                                   + Math.max(0, keyRowDelegate.rowData.length - 1) * keyDeck.keySpacing
                            height: keyDeck.keyHeight
                            spacing: keyDeck.keySpacing

                            Repeater {
                                model: keyRowDelegate.rowData.length

                                Rectangle {
                                    id: keyCap

                                    property int columnNumber: index
                                    property var keyData: keyRowDelegate.rowData[columnNumber] || ({})
                                    property int keyIndex: keyboard.globalIndex(keyRowDelegate.rowNumber, columnNumber)
                                    property bool selected: keyIndex === keyboard.selectedIndex
                                    property bool activeKey: selected || keyPointer.containsMouse
                                    property string keyType: String(keyData.type || "char")
                                    property bool dangerKey: keyType === "close" || keyType === "back"
                                    property bool enterKey: keyType === "enter"
                                    property bool modeKey: keyType === "mode" || keyType === "caps" || keyType === "shift"
                                    property bool latchedKey: (keyType === "caps" && keyboard.capsMode)
                                                              || (keyType === "shift" && keyboard.shiftOnce)

                                    width: keyDeck.keyUnitWidth * keyboard.keyWeight(keyData)
                                    height: keyDeck.keyHeight
                                    radius: Math.max(9, Math.min(14, height * 0.22))
                                    color: dangerKey
                                           ? (activeKey ? keyboard.redKeySelected : keyboard.redKey)
                                           : activeKey ? keyboard.navySelected
                                           : latchedKey ? "#17121A"
                                           : modeKey ? "#0D1724"
                                           : enterKey ? "#0B1721"
                                           : keyboard.navyRaised
                                    border.width: activeKey ? 2 : 1
                                    border.color: activeKey ? keyboard.red
                                                  : dangerKey ? "#C92D40"
                                                  : latchedKey ? "#7B2836"
                                                  : keyboard.divider

                                    // Every selected key uses the same Neutron red glow,
                                    // regardless of key type. This keeps focus language
                                    // consistent across letters, modifiers, Enter, etc.
                                    Rectangle {
                                        anchors.fill: keyCap
                                        anchors.margins: -8
                                        radius: keyCap.radius + 8
                                        color: "transparent"
                                        border.width: 3
                                        border.color: keyboard.red
                                        opacity: keyCap.activeKey ? 0.48 : 0.0
                                        z: -2

                                        Behavior on opacity { NumberAnimation { duration: 110 } }
                                    }

                                    Rectangle {
                                        anchors.fill: keyCap
                                        anchors.margins: -4
                                        radius: keyCap.radius + 4
                                        color: keyboard.red
                                        opacity: keyCap.activeKey ? 0.12 : 0.0
                                        z: -1

                                        Behavior on opacity { NumberAnimation { duration: 110 } }
                                    }

                                    Rectangle {
                                        anchors.left: keyCap.left
                                        anchors.right: keyCap.right
                                        anchors.bottom: keyCap.bottom
                                        height: keyCap.activeKey ? 3 : 1
                                        radius: 2
                                        color: keyboard.red
                                        opacity: keyCap.activeKey ? 1.0
                                                 : keyCap.dangerKey ? 0.72
                                                 : keyCap.latchedKey ? 0.40
                                                 : 0.12
                                    }

                                    Text {
                                        anchors.centerIn: keyCap
                                        width: keyCap.width - 8
                                        text: keyboard.displayLabel(keyCap.keyData)
                                        color: "#FFFFFF"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        font.pixelSize: Math.max(11, Math.min(18, keyCap.height * 0.34))
                                        font.bold: true
                                        font.letterSpacing: 0.3
                                    }

                                    MouseArea {
                                        id: keyPointer
                                        anchors.fill: keyCap
                                        hoverEnabled: true
                                        onEntered: keyboard.selectedIndex = keyCap.keyIndex
                                        onClicked: {
                                            keyboard.selectedIndex = keyCap.keyIndex
                                            keyboard.pressSelected()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: remotePanel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: footer.top
            anchors.margins: 12
            opacity: keyboard.remotePanelVisible ? 1.0 : 0.0
            scale: keyboard.remotePanelVisible ? 1.0 : 1.03
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 1080)
                spacing: 10
                visible: !keyboard.remoteConnected

                Text {
                    width: parent.width
                    text: "REMOTE KEYBOARD"
                    color: keyboard.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 24
                    font.bold: true
                    font.letterSpacing: 1.4
                }

                Text {
                    width: parent.width
                    text: "Open this address on another device, enter the temporary code, then use that device's keyboard and paste controls. Remote input is accepted only while this keyboard is open."
                    color: keyboard.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }

                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 10
                    color: "#081522"
                    border.width: 1
                    border.color: keyboard.divider
                    Text {
                        anchors.fill: parent
                        anchors.margins: 10
                        text: RemoteKeyboardManager.url.length > 0 ? RemoteKeyboardManager.url : "Preparing local address…"
                        color: keyboard.blueSoft
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        font.family: "monospace"
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Rectangle {
                        width: 190
                        height: 42
                        radius: 10
                        color: RemoteKeyboardManager.pairingCodeActive ? "#171018" : "#101621"
                        border.width: 1
                        border.color: RemoteKeyboardManager.pairingCodeActive ? keyboard.red : keyboard.divider
                        Text {
                            anchors.centerIn: parent
                            text: RemoteKeyboardManager.pairingCodeActive ? RemoteKeyboardManager.pairingCode : "---- ----"
                            color: RemoteKeyboardManager.pairingCodeActive ? "#FFFFFF" : keyboard.textSecondary
                            font.family: "monospace"
                            font.pixelSize: 20
                            font.bold: true
                            font.letterSpacing: 2.4
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: RemoteKeyboardManager.pairingCodeActive
                              ? RemoteKeyboardManager.pairingSecondsRemaining + "s"
                              : "Generate a code to pair"
                        color: RemoteKeyboardManager.pairingCodeActive ? keyboard.red : keyboard.textSecondary
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 260
                    height: 44
                    radius: 12
                    color: keyboard.navySelected
                    border.width: 2
                    border.color: keyboard.blue
                    Text {
                        anchors.centerIn: parent
                        text: "GENERATE CODE"
                        color: keyboard.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                }

                Text {
                    width: parent.width
                    text: RemoteKeyboardManager.status
                    color: String(RemoteKeyboardManager.status || "").toLowerCase().indexOf("lock") >= 0
                           ? "#FF7482" : keyboard.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    font.bold: String(RemoteKeyboardManager.status || "").toLowerCase().indexOf("lock") >= 0
                }
            }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 980)
                spacing: 14
                visible: keyboard.remoteConnected

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 78
                    height: 78
                    radius: 39
                    color: "#0A2A1D"
                    border.width: 2
                    border.color: keyboard.green

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        color: keyboard.green
                        font.pixelSize: 38
                        font.bold: true
                    }
                }

                Text {
                    width: parent.width
                    text: "Remote Keyboard Connected"
                    color: keyboard.green
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 28
                    font.bold: true
                    font.letterSpacing: 1.0
                }

                Text {
                    width: parent.width
                    text: "One authenticated device is secured. The security guard rejects every additional pairing request until this remote session closes."
                    color: keyboard.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: guardText.implicitWidth + 28
                    height: 34
                    radius: 17
                    color: "#0A2A1D"
                    border.width: 1
                    border.color: keyboard.green

                    Text {
                        id: guardText
                        anchors.centerIn: parent
                        text: "1 ACTIVE SESSION  •  NEW CONNECTIONS BLOCKED"
                        color: keyboard.green
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        Rectangle {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.bottomMargin: 10
            height: 36
            radius: 11
            color: "#E0060C14"
            border.width: 1
            border.color: "#24364A"

            Row {
                anchors.centerIn: parent
                spacing: 20

                Repeater {
                    model: keyboard.controllerHints.length

                    Text {
                        property string hintText: String(keyboard.controllerHints[index])
                        text: hintText
                        color: hintText.indexOf("O") === 0 ? keyboard.red
                               : hintText.indexOf("X") === 0 ? keyboard.blueSoft
                               : hintText.indexOf("PS") === 0 ? keyboard.green
                               : keyboard.textSecondary
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 0.5
                    }
                }
            }
        }
    }
}
