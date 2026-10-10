import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                                TOOLBAR
        ============================================================

        Purpose:
            Reusable NeutronOS controller-first toolbar.

        Used for:
            - Full-screen apps.
            - Terminal toolbar.
            - Quick commands.
            - Storage app.
            - Logs app.
            - Settings app.
            - AppHost header/footer controls.
            - Service control bars.
            - Modal action bars.

        Design rules:
            - Controller-first.
            - X activates selected toolbar action.
            - O disarms first, then emits backRequested().
            - Triangle emits details/options for selected action.
            - START/OPTIONS activates selected action.
            - Blue focus means selected navigation focus.
            - Red armed means destructive confirmation.
            - Uses IconButton and StatusPill.
            - Uses apps/icons only through IconButton.
            - No quickactions paths.
            - No backend dependency.
            - No shader.
            - Lightweight rectangles/text only.
            - Pointer support is optional fallback only.
            - Animations pause when hidden/inactive.
            - No placeholder behavior.
    */

    property var actions: []
    property var statusItems: []

    property string title: ""
    property string subtitle: ""
    property string appName: ""
    property string appVersion: ""

    property int selectedIndex: 0
    property int armedIndex: -1
    property int scrollOffset: 0
    property int maxVisibleActions: 7

    property bool focused: false
    property bool active: true
    property bool compact: false
    property bool dense: false
    property bool disabled: false

    property bool showTitle: title.length > 0 || appName.length > 0
    property bool showSubtitle: subtitle.length > 0 || appVersion.length > 0
    property bool showStatusItems: statusItems && statusItems.length !== undefined && statusItems.length > 0
    property bool showBackAction: false
    property bool showOptionsAction: false
    property bool showScrollHints: actionCount() > maxVisibleActions
    property bool pointerEnabled: true
    property bool keyboardEnabled: true
    property bool animationsEnabled: visible && enabled && active

    property real radius: compact ? 20 : 26
    property real pulse: 0.42
    property real sweep: -1.0

    property color glassColor: "#06101fd8"
    property color borderColor: "#2b5d8f77"
    property color focusColor: "#4da6ff"
    property color accentColor: "#7df9ff"
    property color purpleColor: "#a855f7"
    property color dangerColor: "#ff3040"
    property color textColor: "white"
    property color subtextColor: "#8aa6c8"

    signal actionRequested(var actionData, string actionId, int actionIndex)
    signal actionArmed(var actionData, string actionId, int actionIndex)
    signal actionDisarmed(var actionData, string actionId, int actionIndex)
    signal selectedActionChanged(var actionData, string actionId, int actionIndex)
    signal detailsRequested(var actionData, string actionId, int actionIndex)
    signal backRequested()
    signal optionsRequested()
    signal focusedRequested()

    implicitHeight: compact ? 66 : 82
    height: implicitHeight

    opacity: disabled ? 0.52 : 1.0
    focus: focused
    activeFocusOnTab: keyboardEnabled

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || root.armedIndex >= 0)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.32
            to: 1.0
            duration: root.armedIndex >= 0 ? 560 : 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.32
            duration: root.armedIndex >= 0 ? 560 : 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && (root.focused || root.armedIndex >= 0)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armedIndex >= 0 ? 1300 : 3600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armedIndex >= 0 ? 1300 : 3600
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            GLASS BAR
        ============================================================
    */

    GlassPanel {
        id: barPanel

        anchors.fill: parent

        radius: root.radius
        padding: 0

        focused: root.focused && root.armedIndex < 0 && !root.disabled
        armed: root.armedIndex >= 0 && !root.disabled
        highlighted: root.showTitle
        disabled: root.disabled

        panelColor: root.glassColor
        borderColor: root.borderColor
        focusColor: root.focusColor
        accentColor: root.accentColor
        dangerColor: root.dangerColor

        sweepEnabled: true
        pulseEnabled: true
        showTopLine: true
        showInnerLine: true
        showOuterGlow: true
        showBottomLine: root.focused || root.armedIndex >= 0
    }

    /*
        ============================================================
                            LEFT ACTIONS
        ============================================================
    */

    Row {
        id: actionRow

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.compact ? 12 : 16

        spacing: root.compact ? 8 : 10

        IconButton {
            visible: root.showBackAction

            width: root.compact ? 54 : 62
            height: width
            compact: true

            actionData: {
                "id": "back",
                "name": "Back",
                "icon": "back"
            }

            buttonIndex: -1000
            focused: root.focused && root.selectedIndex === -1000
            armed: false
            danger: false

            pointerEnabled: root.pointerEnabled
            showLabel: false
            showSubtitle: false

            fallbackGlyph: "O"

            onFocusedRequested: {
                root.selectedIndex = -1000
                root.focusedRequested()
            }

            onActivated: {
                root.backRequested()
            }
        }

        Repeater {
            id: actionRepeater

            model: root.visibleActions()

            IconButton {
                width: root.compact ? 54 : root.dense ? 58 : 66
                height: width
                compact: true

                actionData: modelData.action
                buttonIndex: modelData.index

                focused: root.focused && root.selectedIndex === modelData.index
                selected: focused
                armed: root.armedIndex === modelData.index

                pointerEnabled: root.pointerEnabled
                showLabel: false
                showSubtitle: false
                showStatusDot: root.actionBusy(modelData.action)

                onFocusedRequested: {
                    root.selectedIndex = buttonIndex
                    root.ensureSelectedVisible()
                    root.focusedRequested()
                }

                onArmedRequested: {
                    root.armedIndex = buttonIndex
                    root.actionArmed(actionData, actionId, buttonIndex)
                }

                onDisarmedRequested: {
                    if (root.armedIndex === buttonIndex)
                        root.armedIndex = -1

                    root.actionDisarmed(actionData, actionId, buttonIndex)
                }

                onActivated: {
                    root.runAction(buttonIndex)
                }

                onDetailsRequested: {
                    root.detailsRequested(actionData, actionId, buttonIndex)
                }
            }
        }

        IconButton {
            visible: root.showOptionsAction

            width: root.compact ? 54 : 62
            height: width
            compact: true

            actionData: {
                "id": "options",
                "name": "Options",
                "icon": "settings"
            }

            buttonIndex: -1001
            focused: root.focused && root.selectedIndex === -1001
            armed: false
            danger: false

            pointerEnabled: root.pointerEnabled
            showLabel: false
            showSubtitle: false

            fallbackGlyph: "☰"

            onFocusedRequested: {
                root.selectedIndex = -1001
                root.focusedRequested()
            }

            onActivated: {
                root.optionsRequested()
            }
        }
    }

    /*
        ============================================================
                            CENTER TITLE
        ============================================================
    */

    Column {
        id: titleBlock

        visible: root.showTitle

        anchors.centerIn: parent

        width: Math.max(220, Math.min(parent.width * 0.38, 520))
        spacing: root.compact ? 0 : 2

        Text {
            width: parent.width

            text: root.titleText()

            color: root.textColor

            font.pixelSize: root.compact ? 16 : 20
            font.bold: true
            font.letterSpacing: 0.8

            horizontalAlignment: Text.AlignHCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            visible: root.showSubtitle

            width: parent.width

            text: root.subtitleText()

            color: root.subtextColor

            font.pixelSize: root.compact ? 10 : 12
            font.bold: true
            font.letterSpacing: 0.9

            horizontalAlignment: Text.AlignHCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /*
        ============================================================
                            RIGHT STATUS PILLS
        ============================================================
    */

    Row {
        id: statusRow

        visible: root.showStatusItems

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: root.compact ? 12 : 16

        spacing: root.compact ? 7 : 9

        Repeater {
            model: root.visibleStatusItems()

            StatusPill {
                statusData: modelData.status
                pillIndex: modelData.index

                compact: root.compact
                pointerEnabled: root.pointerEnabled

                focused: root.focused && root.selectedIndex === modelData.index + 10000

                onFocusedRequested: {
                    root.selectedIndex = pillIndex + 10000
                    root.focusedRequested()
                }

                onActivated: {
                    root.detailsRequested(statusData, "", pillIndex + 10000)
                }

                onDetailsRequested: {
                    root.detailsRequested(statusData, "", pillIndex + 10000)
                }
            }
        }
    }

    /*
        ============================================================
                            SCROLL HINTS
        ============================================================
    */

    Text {
        visible: root.showScrollHints && root.scrollOffset > 0

        anchors.left: actionRow.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter

        text: "‹"

        color: root.accentColor

        font.pixelSize: root.compact ? 18 : 22
        font.bold: true

        opacity: 0.45 + root.pulse * 0.20
    }

    Text {
        visible: root.showScrollHints &&
                 root.scrollOffset + root.maxVisibleActions < root.actionCount()

        anchors.left: actionRow.right
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter

        text: "›"

        color: root.accentColor

        font.pixelSize: root.compact ? 18 : 22
        font.bold: true

        opacity: 0.45 + root.pulse * 0.20
    }

    /*
        ============================================================
                            ARMED MESSAGE
        ============================================================
    */

    Rectangle {
        visible: root.armedIndex >= 0

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -10

        width: Math.min(parent.width * 0.46, 420)
        height: 24
        radius: 12

        color: "#26070cdd"

        border.width: 1
        border.color: root.dangerColor

        opacity: 0.94

        Text {
            anchors.centerIn: parent

            width: parent.width - 24

            text: "ARMED: Press X again to confirm • O cancels"

            color: "#ffd1d1"

            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 0.9

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /*
        ============================================================
                            KEYBOARD FALLBACK
        ============================================================
    */

    Keys.enabled: root.keyboardEnabled && root.focused && !root.disabled

    Keys.onLeftPressed: root.moveSelection(-1)
    Keys.onRightPressed: root.moveSelection(1)
    Keys.onReturnPressed: root.activateSelected()
    Keys.onEnterPressed: root.activateSelected()
    Keys.onSpacePressed: root.activateSelected()
    Keys.onEscapePressed: root.cancelOrBack()
    Keys.onBackPressed: root.cancelOrBack()

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function moveSelection(delta) {
        if (root.disabled)
            return false

        var indices = navigableIndices()

        if (indices.length <= 0)
            return false

        var current = indices.indexOf(root.selectedIndex)

        if (current < 0)
            current = 0

        var next = (current + delta + indices.length) % indices.length

        root.selectedIndex = indices[next]
        root.armedIndex = -1

        root.ensureSelectedVisible()
        root.emitSelectedChanged()

        return true
    }

    function activateSelected() {
        if (root.disabled)
            return false

        if (root.selectedIndex === -1000) {
            root.backRequested()
            return true
        }

        if (root.selectedIndex === -1001) {
            root.optionsRequested()
            return true
        }

        if (root.selectedIndex >= 10000) {
            var statusIndex = root.selectedIndex - 10000
            var status = root.statusAt(statusIndex)

            if (status)
                root.detailsRequested(status, "", root.selectedIndex)

            return true
        }

        var item = actionItemForIndex(root.selectedIndex)

        if (item)
            return item.activate()

        var action = actionAt(root.selectedIndex)

        if (!action)
            return false

        if (root.actionDanger(action) && root.armedIndex !== root.selectedIndex) {
            root.armedIndex = root.selectedIndex
            root.actionArmed(action, root.actionId(action), root.selectedIndex)
            return true
        }

        root.runAction(root.selectedIndex)
        return true
    }

    function cancelOrBack() {
        if (root.armedIndex >= 0) {
            var action = actionAt(root.armedIndex)
            var id = actionId(action)

            root.actionDisarmed(action, id, root.armedIndex)
            root.armedIndex = -1
            return true
        }

        root.backRequested()
        return true
    }

    function disarm() {
        if (root.armedIndex < 0)
            return false

        var action = actionAt(root.armedIndex)
        var id = actionId(action)

        root.actionDisarmed(action, id, root.armedIndex)
        root.armedIndex = -1
        return true
    }

    function runAction(index) {
        var action = actionAt(index)

        if (!action)
            return false

        var id = actionId(action)

        root.armedIndex = -1
        root.actionRequested(action, id, index)

        return true
    }

    function setFocused(value) {
        root.focused = !!value

        if (root.focused) {
            root.focusedRequested()
            clampSelected()
            ensureSelectedVisible()
            emitSelectedChanged()
        } else {
            root.armedIndex = -1
        }
    }

    function setActions(list) {
        root.actions = list || []
        root.scrollOffset = 0
        root.selectedIndex = firstNavigableIndex()
        root.armedIndex = -1
    }

    function handleController(action) {
        if (root.disabled)
            return false

        var normalized = normalizeController(action)

        if (normalized === "LEFT")
            return moveSelection(-1)

        if (normalized === "RIGHT")
            return moveSelection(1)

        if (normalized === "X" || normalized === "START")
            return activateSelected()

        if (normalized === "O")
            return cancelOrBack()

        if (normalized === "TRIANGLE") {
            if (root.selectedIndex === -1001) {
                root.optionsRequested()
                return true
            }

            if (root.selectedIndex >= 0) {
                var action = actionAt(root.selectedIndex)
                root.detailsRequested(action, actionId(action), root.selectedIndex)
                return true
            }

            root.optionsRequested()
            return true
        }

        return false
    }

    /*
        ============================================================
                            ACTION HELPERS
        ============================================================
    */

    function actionCount() {
        if (!actions || actions.length === undefined)
            return 0

        return actions.length
    }

    function statusCount() {
        if (!statusItems || statusItems.length === undefined)
            return 0

        return statusItems.length
    }

    function actionAt(index) {
        if (index < 0 || index >= actionCount())
            return null

        try {
            return actions[index]
        } catch (e) {
        }

        return null
    }

    function statusAt(index) {
        if (index < 0 || index >= statusCount())
            return null

        try {
            return statusItems[index]
        } catch (e) {
        }

        return null
    }

    function visibleActions() {
        var result = []

        var count = actionCount()
        var maxItems = Math.max(0, maxVisibleActions)
        var start = Math.max(0, Math.min(scrollOffset, Math.max(0, count - maxItems)))
        var end = Math.min(count, start + maxItems)

        for (var i = start; i < end; i++) {
            result.push({
                "action": actionAt(i),
                "index": i
            })
        }

        return result
    }

    function visibleStatusItems() {
        var result = []
        var maxItems = root.compact ? 2 : 3
        var count = Math.min(statusCount(), maxItems)

        for (var i = 0; i < count; i++) {
            result.push({
                "status": statusAt(i),
                "index": i
            })
        }

        return result
    }

    function navigableIndices() {
        var result = []

        if (showBackAction)
            result.push(-1000)

        for (var i = 0; i < actionCount(); i++)
            result.push(i)

        if (showOptionsAction)
            result.push(-1001)

        if (showStatusItems) {
            var maxStatus = Math.min(statusCount(), root.compact ? 2 : 3)

            for (var s = 0; s < maxStatus; s++)
                result.push(10000 + s)
        }

        return result
    }

    function firstNavigableIndex() {
        var list = navigableIndices()

        if (list.length <= 0)
            return 0

        return list[0]
    }

    function clampSelected() {
        var list = navigableIndices()

        if (list.length <= 0) {
            selectedIndex = 0
            armedIndex = -1
            return
        }

        if (list.indexOf(selectedIndex) < 0)
            selectedIndex = list[0]
    }

    function ensureSelectedVisible() {
        if (selectedIndex < 0 || selectedIndex >= actionCount())
            return

        var count = actionCount()
        var maxItems = Math.max(1, maxVisibleActions)

        if (selectedIndex < scrollOffset)
            scrollOffset = selectedIndex

        if (selectedIndex >= scrollOffset + maxItems)
            scrollOffset = selectedIndex - maxItems + 1

        scrollOffset = Math.max(0, Math.min(scrollOffset, Math.max(0, count - maxItems)))
    }

    function actionItemForIndex(index) {
        for (var i = 0; i < actionRepeater.count; i++) {
            var item = actionRepeater.itemAt(i)

            if (item && item.buttonIndex === index)
                return item
        }

        return null
    }

    function emitSelectedChanged() {
        if (selectedIndex >= 0 && selectedIndex < actionCount()) {
            var action = actionAt(selectedIndex)
            selectedActionChanged(action, actionId(action), selectedIndex)
        }
    }

    /*
        ============================================================
                            SAFE HELPERS
        ============================================================
    */

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var out = String(value).trim()

        if (out === "undefined" || out === "null")
            return ""

        return out
    }

    function valueFor(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var value = source[keys[i]]

                if (value !== undefined &&
                        value !== null &&
                        String(value).trim().length > 0) {
                    return String(value)
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function boolFor(source, keys, fallbackValue) {
        if (!source)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            try {
                var raw = source[keys[i]]

                if (raw === undefined || raw === null)
                    continue

                if (raw === true)
                    return true

                if (raw === false)
                    return false

                if (typeof raw === "number")
                    return raw !== 0

                var textValue = String(raw).trim().toLowerCase()

                if (textValue === "true" ||
                        textValue === "1" ||
                        textValue === "yes" ||
                        textValue === "running" ||
                        textValue === "active" ||
                        textValue === "busy" ||
                        textValue === "disabled" ||
                        textValue === "danger" ||
                        textValue === "destructive" ||
                        textValue === "required") {
                    return true
                }

                if (textValue === "false" ||
                        textValue === "0" ||
                        textValue === "no" ||
                        textValue === "stopped" ||
                        textValue === "inactive" ||
                        textValue === "idle" ||
                        textValue === "enabled" ||
                        textValue === "safe") {
                    return false
                }
            } catch (e2) {
            }
        }

        return fallbackValue
    }

    function actionId(action) {
        return valueFor(action, [
                            "id",
                            "actionId",
                            "backendAction",
                            "action",
                            "command"
                        ], "")
    }

    function actionBusy(action) {
        return boolFor(action, [
                           "busy",
                           "working",
                           "running",
                           "inProgress"
                       ], false)
    }

    function actionDanger(action) {
        if (boolFor(action, [
                    "danger",
                    "destructive",
                    "confirmRequired",
                    "requiresConfirmation"
                ], false)) {
            return true
        }

        var combined = (
            actionId(action) + " " +
            valueFor(action, ["name", "title", "label"], "")
        ).toLowerCase()

        return combined.indexOf("shutdown") >= 0 ||
               combined.indexOf("poweroff") >= 0 ||
               combined.indexOf("reboot") >= 0 ||
               combined.indexOf("restart") >= 0 ||
               combined.indexOf("stop") >= 0 ||
               combined.indexOf("kill") >= 0 ||
               combined.indexOf("delete") >= 0 ||
               combined.indexOf("remove") >= 0 ||
               combined.indexOf("uninstall") >= 0
    }

    function titleText() {
        var cleanTitle = cleanText(title)

        if (cleanTitle.length > 0)
            return cleanTitle

        var cleanApp = cleanText(appName)

        if (cleanApp.length > 0)
            return cleanApp

        return ""
    }

    function subtitleText() {
        var cleanSubtitle = cleanText(subtitle)

        if (cleanSubtitle.length > 0)
            return cleanSubtitle

        var cleanVersion = cleanText(appVersion)

        if (cleanVersion.length > 0)
            return "V" + cleanVersion

        return ""
    }

    function normalizeController(button) {
        var b = String(button || "").trim().toUpperCase()

        if (b === "DPAD_LEFT" || b === "LEFT")
            return "LEFT"

        if (b === "DPAD_RIGHT" || b === "RIGHT")
            return "RIGHT"

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

    onActionsChanged: {
        scrollOffset = 0
        clampSelected()
        ensureSelectedVisible()
    }

    onSelectedIndexChanged: {
        clampSelected()
        ensureSelectedVisible()
        emitSelectedChanged()
    }

    onMaxVisibleActionsChanged: {
        if (maxVisibleActions < 1)
            maxVisibleActions = 1

        ensureSelectedVisible()
    }

    onFocusedChanged: {
        if (focused) {
            focusedRequested()
            clampSelected()
            ensureSelectedVisible()
        } else {
            armedIndex = -1
        }
    }

    onVisibleChanged: {
        if (!visible) {
            pulse = 0.42
            sweep = -1.0
            armedIndex = -1
        }
    }
}