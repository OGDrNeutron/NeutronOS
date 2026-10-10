import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            QUICK ACTION TILE
        ============================================================

        Next-generation controller-first quick action tile.

        Purpose:
            - Console bottom quick actions dock
            - macOS-style dock row
            - controller navigation
            - armed destructive actions
            - launch-app quick actions
            - backend quick actions

        Compatibility:
            - Does NOT replace QuickActionCard.qml.
            - QuickActionCard.qml remains for older dashboard/quick action grids.
            - This tile is for QuickActionsDock.qml and next-gen Console.

        Rules:
            - Blue focus for navigation.
            - Red armed state before destructive actions.
            - X/primary activates.
            - O/cancel disarms.
            - No quickactions asset folder.
            - Icons come from themes/Default/apps/icons/.
            - Posters come from themes/Default/apps/posters/ only if needed.
            - No mouse dependency, but click stays for preview/testing.
    */

    property var actionData: null

    property int tileIndex: -1
    property int dockIndex: tileIndex

    property bool sectionFocused: false
    property bool selected: focused
    property bool disabled: boolFor(["disabled", "locked"], false)
    property bool busy: boolFor(["busy", "running"], false)

    property bool danger: boolFor(["danger", "destructive", "confirmRequired"], false)
    property bool destructive: danger
    property bool requiresConfirmation: boolFor(["confirmRequired", "requiresConfirmation"], danger)
    property bool launchApp: boolFor(["launchApp", "opensApp", "appShortcut"], false)

    property bool animationsEnabled: visible && enabled

    property string actionId: valueFor(["id", "actionId", "backendAction", "appId"], "")
    property string actionName: valueFor(["name", "title", "label"], "")
    property string subtitle: valueFor(["subtitle", "description", "hint", "type"], "")
    property string iconName: valueFor(["icon", "iconName", "iconPath", "iconSource"], "")
    property string posterName: valueFor(["poster", "posterName", "posterPath", "posterSource"], "")
    property string actionType: valueFor(["type", "runtimeType", "launchType"], "")
    property string backendAction: valueFor(["backendAction", "action", "commandId"], "")

    property color safeAccent: "#7df9ff"
    property color focusAccent: "#4da6ff"
    property color purpleAccent: "#a855f7"
    property color dangerAccent: "#ff3040"
    property color warningAccent: "#ff7040"
    property color busyAccent: "#f5c542"
    property color disabledAccent: "#66758a"

    property real dockScale: root.focused || root.armed ? 1.10 :
                             root.sectionFocused ? 1.02 :
                                                   1.0

    property real pulse: 0.55
    property real iconLift: 0.0
    property real sweep: -1.0

    signal actionRequested(var actionData, int index)
    signal armRequested(var actionData, int index)
    signal disarmRequested(var actionData, int index)
    signal detailsRequested(var actionData, int index)

    radius: 24

    accent: root.activeAccent()

    hoverEnabled: false

    implicitWidth: 128
    implicitHeight: 112

    opacity: disabled ? 0.48 :
             sectionFocused || focused || armed ? 1.0 :
                                                   0.78

    /*
        GlassCard already owns scale for focused/armed. To avoid fighting it,
        visual magnification is applied to the inner content instead.
    */

    onClicked: {
        root.activate()
    }

    /*
        ============================================================
                            DATA HELPERS
        ============================================================
    */

    function hasValue(value) {
        return value !== undefined &&
               value !== null &&
               String(value).trim().length > 0
    }

    function valueFor(keys, fallbackValue) {
        if (!actionData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                if (hasValue(actionData[key]))
                    return String(actionData[key])
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function boolFor(keys, fallbackValue) {
        if (!actionData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                var raw = actionData[key]

                if (raw === undefined || raw === null)
                    continue

                if (raw === true)
                    return true

                if (raw === false)
                    return false

                if (typeof raw === "number")
                    return raw !== 0

                var text = String(raw).trim().toLowerCase()

                if (text === "true" ||
                        text === "1" ||
                        text === "yes" ||
                        text === "danger" ||
                        text === "destructive" ||
                        text === "confirm" ||
                        text === "required" ||
                        text === "busy" ||
                        text === "running" ||
                        text === "locked") {
                    return true
                }

                if (text === "false" ||
                        text === "0" ||
                        text === "no" ||
                        text === "safe" ||
                        text === "normal" ||
                        text === "enabled" ||
                        text === "idle") {
                    return false
                }
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function isAbsoluteSource(value) {
        var text = String(value || "").trim().toLowerCase()

        return text.indexOf("file:") === 0 ||
               text.indexOf("qrc:") === 0 ||
               text.indexOf("http://") === 0 ||
               text.indexOf("https://") === 0 ||
               text.indexOf("image://") === 0
    }

    function hasImageExtension(value) {
        var text = String(value || "").trim().toLowerCase()

        return text.indexOf(".png") > 0 ||
               text.indexOf(".jpg") > 0 ||
               text.indexOf(".jpeg") > 0 ||
               text.indexOf(".webp") > 0 ||
               text.indexOf(".svg") > 0
    }

    function cleanAssetId(value) {
        var text = String(value || "").trim()

        if (text.length <= 0)
            return ""

        text = text.replace(/\\/g, "/")

        if (isAbsoluteSource(text))
            return text

        if (text.indexOf("/") >= 0)
            return text

        if (hasImageExtension(text))
            text = text.substring(0, text.lastIndexOf("."))

        return text
    }

    function themeFile(path) {
        var cleanPath = String(path || "").trim()

        if (cleanPath.length <= 0)
            return ""

        if (isAbsoluteSource(cleanPath))
            return cleanPath

        try {
            if (typeof assetManager !== "undefined" &&
                    assetManager &&
                    typeof assetManager.themeFile === "function") {
                return assetManager.themeFile(cleanPath)
            }
        } catch (e) {
        }

        /*
            Design-time fallback only.
            Production resolves through AssetManager:
                ~/NeutronOS/themes/Default/<path>
        */
        return "../themes/Default/" + cleanPath
    }

    function isLegacyUtilityIcon(value) {
        var text = cleanAssetId(value).toLowerCase()

        if (text.indexOf("/") >= 0)
            text = text.substring(text.lastIndexOf("/") + 1)

        return [
            "add",
            "controller-off",
            "help",
            "reboot",
            "restart",
            "screensaver",
            "script",
            "service",
            "shutdown",
            "ssh"
        ].indexOf(text) >= 0
    }

    function iconSource() {
        var raw = cleanAssetId(iconName)

        if (raw.length <= 0)
            raw = cleanAssetId(actionId)

        if (raw.length <= 0)
            raw = "terminal"

        if (isAbsoluteSource(raw))
            return raw

        if (isLegacyUtilityIcon(raw)) {
            var legacyName = raw

            if (legacyName.indexOf("/") >= 0)
                legacyName = legacyName.substring(legacyName.lastIndexOf("/") + 1)

            return themeFile(
                "apps/icons/legacy/" +
                legacyName +
                ".png"
            )
        }

        if (raw.indexOf("/") >= 0) {
            if (raw.indexOf("apps/") === 0)
                return themeFile(raw)

            if (raw.indexOf("icons/") === 0)
                return themeFile("apps/" + raw)

            return themeFile(raw)
        }

        return themeFile("apps/icons/" + raw + ".png")
    }

    function posterSource() {
        var raw = cleanAssetId(posterName)

        if (raw.length <= 0)
            raw = cleanAssetId(actionId)

        if (raw.length <= 0)
            return ""

        if (isAbsoluteSource(raw))
            return raw

        if (raw.indexOf("/") >= 0) {
            if (raw.indexOf("apps/posters/legacy/") === 0)
                return themeFile(raw)

            if (raw.indexOf("apps/posters/") === 0)
                return themeFile(
                    "apps/posters/legacy/" +
                    raw.substring("apps/posters/".length)
                )

            if (raw.indexOf("posters/legacy/") === 0)
                return themeFile("apps/" + raw)

            if (raw.indexOf("posters/") === 0)
                return themeFile(
                    "apps/posters/legacy/" +
                    raw.substring("posters/".length)
                )

            if (raw.indexOf("apps/") === 0)
                return themeFile(raw)

            return themeFile(raw)
        }

        return themeFile(
            "apps/posters/legacy/" +
            raw +
            ".png"
        )
    }

    function displayName() {
        if (actionName.length > 0)
            return actionName

        if (actionId.length > 0)
            return actionId

        return "Action"
    }

    function displaySubtitle() {
        if (root.armed)
            return "Press X to confirm"

        if (disabled)
            return "Unavailable"

        if (busy)
            return "Working"

        if (subtitle.length > 0)
            return subtitle

        if (launchApp)
            return "Open app"

        if (requiresConfirmation)
            return "Hold to arm"

        if (actionType.length > 0)
            return actionType

        if (backendAction.length > 0)
            return backendAction

        return ""
    }

    function activeAccent() {
        if (disabled)
            return disabledAccent

        if (armed)
            return dangerAccent

        if (busy)
            return busyAccent

        if (danger)
            return warningAccent

        if (focused)
            return focusAccent

        return safeAccent
    }

    function glyphForAction() {
        var id = actionId.toLowerCase()
        var name = actionName.toLowerCase()
        var combined = id + " " + name + " " + backendAction.toLowerCase()

        if (combined.indexOf("shutdown") >= 0 ||
                combined.indexOf("poweroff") >= 0) {
            return "⏻"
        }

        if (combined.indexOf("reboot") >= 0 ||
                combined.indexOf("restart") >= 0) {
            return "↻"
        }

        if (combined.indexOf("update") >= 0 ||
                combined.indexOf("upgrade") >= 0) {
            return "↑"
        }

        if (combined.indexOf("terminal") >= 0 ||
                combined.indexOf("shell") >= 0) {
            return ">_"
        }

        if (combined.indexOf("logs") >= 0 ||
                combined.indexOf("journal") >= 0) {
            return "≡"
        }

        if (combined.indexOf("storage") >= 0 ||
                combined.indexOf("disk") >= 0 ||
                combined.indexOf("files") >= 0) {
            return "▣"
        }

        if (combined.indexOf("network") >= 0 ||
                combined.indexOf("tailscale") >= 0 ||
                combined.indexOf("wifi") >= 0) {
            return "⌁"
        }

        if (combined.indexOf("docker") >= 0)
            return "◆"

        if (combined.indexOf("jellyfin") >= 0)
            return "J"

        if (combined.indexOf("qbit") >= 0 ||
                combined.indexOf("torrent") >= 0) {
            return "Q"
        }

        return "✦"
    }

    function activate() {
        if (disabled || !actionData)
            return false

        if (requiresConfirmation && !armed) {
            root.armRequested(root.actionData, root.tileIndex)
            return true
        }

        root.actionRequested(root.actionData, root.tileIndex)
        return true
    }

    function disarm() {
        if (!armed)
            return false

        root.disarmRequested(root.actionData, root.tileIndex)
        return true
    }

    function handleController(action) {
        if (action === "primary" || action === "x") {
            return root.activate()
        }

        if (action === "cancel" || action === "o") {
            return root.disarm()
        }

        if (action === "context" || action === "triangle" ||
                action === "system" || action === "start") {
            if (!disabled && actionData) {
                root.detailsRequested(root.actionData, root.tileIndex)
                return true
            }
        }

        return false
    }

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    Behavior on opacity {
        enabled: root.animationsEnabled

        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled &&
                 (root.focused || root.armed || root.danger || root.busy)

        loops: Animation.Infinite

        NumberAnimation {
            from: 0.40
            to: 1.0
            duration: root.armed ? 520 :
                      root.busy ? 820 :
                      root.danger ? 980 :
                                    1600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.40
            duration: root.armed ? 520 :
                      root.busy ? 820 :
                      root.danger ? 980 :
                                    1600
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on iconLift {
        running: root.animationsEnabled && root.focused && !root.armed && !root.busy
        loops: Animation.Infinite

        NumberAnimation {
            from: -2
            to: 2
            duration: 2100
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 2
            to: -2
            duration: 2100
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweep {
        running: root.animationsEnabled && (root.focused || root.armed || root.busy)
        loops: Animation.Infinite

        NumberAnimation {
            from: -1.0
            to: 1.0
            duration: root.armed ? 900 : 2400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: -1.0
            duration: root.armed ? 900 : 2400
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            TILE BACKDROP
        ============================================================
    */

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2

        radius: root.radius - 2

        color: root.armed ? "#26080CDD" :
               root.danger ? "#20110ADD" :
               root.focused ? "#071F3AEE" :
                              "#071426CC"

        opacity: root.disabled ? 0.72 : 1.0
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.focused || root.armed ? -3 : 0

        radius: root.radius + 3
        color: "transparent"

        border.width: root.armed ? 3 :
                      root.focused ? 2 :
                      root.danger ? 1 :
                                    0

        border.color: root.activeAccent()

        opacity: root.armed ? 0.45 + root.pulse * 0.35 :
                 root.focused ? 0.30 + root.pulse * 0.24 :
                 root.danger ? 0.24 + root.pulse * 0.18 :
                               0.0
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Item {
        id: contentRoot

        anchors.fill: parent
        anchors.margins: 8

        scale: root.dockScale

        Behavior on scale {
            enabled: root.animationsEnabled

            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.displaySubtitle().length > 0 ? 6 : 8

            Item {
                id: iconShell

                width: root.focused || root.armed ? 58 : 52
                height: width

                anchors.horizontalCenter: parent.horizontalCenter

                y: root.iconLift

                Rectangle {
                    anchors.fill: parent
                    radius: 18

                    color: root.armed ? "#3A0710DD" :
                           root.danger ? "#2A1207DD" :
                           root.busy ? "#2A2207DD" :
                                       "#071426EE"

                    border.width: root.focused || root.armed ? 2 : 1
                    border.color: root.activeAccent()
                }

                Rectangle {
                    anchors.centerIn: parent

                    width: parent.width + 18
                    height: width
                    radius: width / 2

                    color: "transparent"

                    border.width: root.focused || root.armed || root.busy ? 1 : 0
                    border.color: root.activeAccent()

                    opacity: root.armed ? 0.22 + root.pulse * 0.28 :
                             root.busy ? 0.16 + root.pulse * 0.20 :
                             root.focused ? 0.14 + root.pulse * 0.18 :
                                            0.0
                }

                Image {
                    id: iconImage

                    anchors.fill: parent
                    anchors.margins: 8

                    source: root.iconSource()

                    fillMode: Image.PreserveAspectFit

                    smooth: true
                    cache: true
                    asynchronous: true
                    sourceSize.width: 160
                    mipmap: false

                    opacity: status === Image.Ready ? 1.0 : 0.0
                }

                Text {
                    visible: iconImage.status !== Image.Ready

                    anchors.centerIn: parent

                    text: root.glyphForAction()

                    color: root.activeAccent()

                    font.pixelSize: root.glyphForAction().length > 2 ? 13 :
                                    root.glyphForAction() === ">_" ? 19 :
                                                                     27
                    font.bold: true
                    font.letterSpacing: 0.4

                    opacity: root.disabled ? 0.52 : 0.94
                }

                /*
                    Busy spinner ring.
                */
                Rectangle {
                    visible: root.busy

                    anchors.centerIn: parent

                    width: parent.width + 24
                    height: width
                    radius: width / 2

                    color: "transparent"

                    border.width: 2
                    border.color: root.busyAccent

                    opacity: 0.20 + root.pulse * 0.26

                    RotationAnimation on rotation {
                        running: root.animationsEnabled && root.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
            }

            Text {
                width: parent.width

                text: root.displayName()

                color: root.disabled ? "#8aa6c8" :
                       root.armed ? "#ffd1d1" :
                                    "white"

                font.pixelSize: root.focused || root.armed ? 15 : 14
                font.bold: true
                font.letterSpacing: 0.2

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1

                style: Text.Outline
                styleColor: "#99000000"
            }

            Text {
                visible: root.displaySubtitle().length > 0

                width: parent.width

                text: root.displaySubtitle()

                color: root.disabled ? "#66758a" :
                       root.armed ? "#ffd1d1" :
                       root.danger ? "#ffc2a8" :
                       root.busy ? "#ffe19a" :
                                   "#9fd8ff"

                font.pixelSize: 10
                font.bold: root.focused || root.armed || root.busy
                font.letterSpacing: 0.3

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1

                opacity: root.focused || root.armed || root.busy ? 0.98 : 0.78
            }
        }
    }

    /*
        ============================================================
                            ACTIVE / ARMED STRIPS
        ============================================================
    */

    Rectangle {
        visible: root.focused || root.armed || root.danger || root.busy

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: root.armed ? 6 :
                root.focused ? 4 :
                root.danger || root.busy ? 3 :
                                           0

        radius: height / 2

        color: root.activeAccent()

        opacity: root.armed ? 0.78 + root.pulse * 0.22 :
                 root.focused ? 0.60 + root.pulse * 0.22 :
                 root.busy ? 0.48 + root.pulse * 0.20 :
                             0.34 + root.pulse * 0.18
    }

    Rectangle {
        visible: root.armed

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 11

        width: armedText.width + 20
        height: 20
        radius: 10

        color: "#26080CEE"

        border.width: 1
        border.color: root.dangerAccent

        opacity: 0.72 + root.pulse * 0.28

        Text {
            id: armedText

            anchors.centerIn: parent

            text: "ARMED"

            color: "#ffd1d1"

            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 2.0
        }
    }

    /*
        ============================================================
                            TOP STATUS DOT
        ============================================================
    */

    Rectangle {
        visible: root.launchApp || root.danger || root.busy

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 9
        anchors.rightMargin: 9

        width: 11
        height: 11
        radius: 6

        color: root.busy ? root.busyAccent :
               root.danger ? root.warningAccent :
                             root.safeAccent

        opacity: root.busy || root.danger ? 0.65 + root.pulse * 0.30 : 0.72
    }
}
