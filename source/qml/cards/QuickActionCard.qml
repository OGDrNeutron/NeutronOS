import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            QUICK ACTION CARD
        ============================================================

        Used by:
            - dashboard/QuickActions.qml
            - dashboard/QuickActionsDock.qml if present later
            - Console quick action row/dock

        Preserved from original:
            - actionData input
            - danger styling
            - actionRequested(actionData)
            - icon + label layout
            - GlassCard focus/armed behavior

        Next-gen updates:
            - Uses corrected asset locations:
                themes/Default/apps/icons/
                themes/Default/apps/posters/

              No actions/icons path.
              No quickactions folder.

            - Supports QuickActionManager fields:
                id
                name
                title
                subtitle
                icon
                poster
                danger
                destructive
                confirmRequired
                launchApp
                backendAction
                type

            - Supports armed state.
            - Supports disabled/missing actionData safely.
            - Supports icon names, filenames, relative paths, qrc/file/http URLs.
            - No hard crash if assetManager is missing.
            - No mouse assumption required for controller use, but keeps
              GlassCard click signal for preview/touch testing.
    */

    property var actionData

    property bool danger: boolValueFor(["danger", "destructive", "confirmRequired"], false)
    property bool destructive: danger
    property bool disabled: boolValueFor(["disabled"], false)

    property bool animationsEnabled: visible && enabled

    property string actionId: valueFor(["id", "actionId", "backendAction"], "")
    property string actionName: valueFor(["name", "title", "label"], "")
    property string actionSubtitle: valueFor(["subtitle", "description", "type"], "")
    property string actionIcon: valueFor(["icon", "iconName", "iconPath", "iconSource"], "")
    property string actionType: valueFor(["type", "runtimeType", "launchType"], "")

    property color safeAccent: "#7df9ff"
    property color dangerAccent: "#ff3040"
    property color warningAccent: "#ff7040"
    property color disabledAccent: "#66758a"

    property real pulse: 0.55

    signal actionRequested(var actionData)

    radius: 26
    accent: disabled ? disabledAccent :
            armed ? dangerAccent :
            danger ? warningAccent :
                     safeAccent

    opacity: disabled ? 0.48 : 1.0

    hoverEnabled: false

    onClicked: {
        if (!root.disabled && root.actionData)
            root.actionRequested(root.actionData)
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

    function boolValueFor(keys, fallbackValue) {
        if (!actionData)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                var value = actionData[key]

                if (value === undefined || value === null)
                    continue

                if (value === true)
                    return true

                if (value === false)
                    return false

                if (typeof value === "number")
                    return value !== 0

                var text = String(value).trim().toLowerCase()

                if (text === "true" ||
                        text === "1" ||
                        text === "yes" ||
                        text === "danger" ||
                        text === "destructive" ||
                        text === "armed" ||
                        text === "disabled") {
                    return true
                }

                if (text === "false" ||
                        text === "0" ||
                        text === "no" ||
                        text === "safe" ||
                        text === "enabled") {
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
            Design-time fallback only. Production should resolve through
            AssetManager into ~/NeutronOS/themes/Default/.
        */
        return "../themes/Default/" + cleanPath
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
        var raw = cleanAssetId(actionIcon)

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

        /*
            Already a relative theme path.
        */
        if (raw.indexOf("/") >= 0) {
            if (raw.indexOf("apps/") === 0)
                return themeFile(raw)

            if (raw.indexOf("icons/") === 0)
                return themeFile("apps/" + raw)

            return themeFile(raw)
        }

        return themeFile("apps/icons/" + raw + ".png")
    }

    function displayName() {
        if (actionName.length > 0)
            return actionName

        if (actionId.length > 0)
            return actionId

        return "Action"
    }

    function displaySubtitle() {
        if (actionSubtitle.length > 0)
            return actionSubtitle

        if (danger)
            return "Requires confirmation"

        if (actionType.length > 0)
            return actionType

        return ""
    }

    function iconGlyph() {
        var id = actionId.toLowerCase()
        var name = actionName.toLowerCase()

        if (id.indexOf("shutdown") >= 0 || name.indexOf("shutdown") >= 0)
            return "⏻"

        if (id.indexOf("reboot") >= 0 || name.indexOf("reboot") >= 0)
            return "↻"

        if (id.indexOf("restart") >= 0 || name.indexOf("restart") >= 0)
            return "↻"

        if (id.indexOf("update") >= 0 || name.indexOf("update") >= 0)
            return "↑"

        if (id.indexOf("terminal") >= 0 || name.indexOf("terminal") >= 0)
            return ">_"

        if (id.indexOf("logs") >= 0 || name.indexOf("logs") >= 0)
            return "≡"

        if (id.indexOf("storage") >= 0 || name.indexOf("storage") >= 0)
            return "▣"

        return "✦"
    }

    function displayColor() {
        if (disabled)
            return disabledAccent

        if (armed)
            return dangerAccent

        if (danger)
            return warningAccent

        if (focused)
            return safeAccent

        return accent
    }

    /*
        ============================================================
                            ANIMATION
        ============================================================
    */

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || root.armed || root.danger)
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.40
            to: 1.0
            duration: root.armed ? 560 : root.danger ? 900 : 1500
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.40
            duration: root.armed ? 560 : root.danger ? 900 : 1500
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            CONTENT
        ============================================================
    */

    Column {
        id: content

        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10

        spacing: root.displaySubtitle().length > 0 ? 7 : 9

        Item {
            id: iconShell

            width: root.focused || root.armed ? 58 : 52
            height: width

            anchors.horizontalCenter: parent.horizontalCenter

            Behavior on width {
                enabled: root.animationsEnabled

                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent

                radius: 18

                color: root.armed ? "#26080CDD" :
                       root.danger ? "#24120BDD" :
                                     "#071426DD"

                border.width: root.focused || root.armed ? 2 : 1
                border.color: root.displayColor()

                opacity: root.disabled ? 0.75 : 1.0
            }

            Rectangle {
                anchors.centerIn: parent

                width: parent.width + 16
                height: width
                radius: width / 2

                color: "transparent"

                border.width: root.focused || root.armed ? 1 : 0
                border.color: root.displayColor()

                opacity: root.armed ? 0.24 + root.pulse * 0.22 :
                         root.focused ? 0.16 + root.pulse * 0.16 :
                                        0.0
            }

            Image {
                id: actionIconImage

                anchors.fill: parent
                anchors.margins: 8

                source: root.iconSource()

                fillMode: Image.PreserveAspectFit

                smooth: true
                cache: true
                asynchronous: true
                sourceSize.width: 128
                mipmap: false

                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            Text {
                visible: actionIconImage.status !== Image.Ready

                anchors.centerIn: parent

                text: root.iconGlyph()

                color: root.displayColor()

                font.pixelSize: root.iconGlyph() === ">_" ? 19 : 26
                font.bold: true

                opacity: root.disabled ? 0.52 : 0.92
            }
        }

        Text {
            width: parent.width

            horizontalAlignment: Text.AlignHCenter

            text: root.displayName()

            color: root.disabled ? "#8aa6c8" : "white"

            font.pixelSize: root.focused || root.armed ? 16 : 15
            font.bold: true
            font.letterSpacing: 0.2

            elide: Text.ElideRight
            maximumLineCount: 1

            style: Text.Outline
            styleColor: "#99000000"
        }

        Text {
            visible: root.displaySubtitle().length > 0

            width: parent.width

            horizontalAlignment: Text.AlignHCenter

            text: root.displaySubtitle()

            color: root.disabled ? "#66758a" :
                   root.armed ? "#ffd1d1" :
                   root.danger ? "#ffc2a8" :
                                 "#9fd8ff"

            font.pixelSize: 10
            font.bold: root.focused || root.armed
            font.letterSpacing: 0.3

            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: root.focused || root.armed ? 0.96 : 0.78
        }
    }

    /*
        ============================================================
                            DANGER / ARMED INDICATORS
        ============================================================
    */

    Rectangle {
        visible: root.danger || root.armed

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        height: root.armed ? 5 : 3

        color: root.armed ? root.dangerAccent : root.warningAccent

        opacity: root.armed ? 0.72 + root.pulse * 0.28 :
                              0.50 + root.pulse * 0.20
    }

    Text {
        visible: root.armed

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 9

        text: "ARMED"

        color: "#ffd1d1"

        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 2.0

        opacity: 0.72 + root.pulse * 0.28
    }
}
