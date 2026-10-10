import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    property var appData
    property int realIndex: -1
    property int slotIndex: -1
    property int displayNumber: 0
    // Patch 60K: poster frames are double-buffered. The previously resolved
    // theme poster remains visible until the replacement is completely ready.
    property bool posterHasPresentedFrame: false
    property int activePosterLayer: -1
    property string resolvedPosterSource: ""
    property string requestedPosterSource: String(posterSource || "")
    property int posterGeneration: 0
    property string posterIdentity: appId + "|" + String(realIndex) + "|" + String(posterSource || "")

    function resetPosterForIdentity() {
        // A poster from another app must never survive slot recycling. Local
        // poster files load synchronously, so briefly showing the branded
        // fallback is safer than presenting the wrong app artwork.
        posterGeneration += 1
        requestedPosterSource = String(posterSource || "")
        posterHasPresentedFrame = false
        activePosterLayer = -1
        resolvedPosterSource = ""
        posterA.source = ""
        posterB.source = ""
        Qt.callLater(requestPosterFrame)
    }

    function requestPosterFrame() {
        var requested = String(posterSource || "")
        requestedPosterSource = requested
        var target = activePosterLayer === 0 ? posterB : posterA
        target.requestGeneration = posterGeneration
        target.requestedSource = requested
        target.source = requested
    }

    function commitPosterFrame(layer, sourceText, generation) {
        if (generation !== posterGeneration || sourceText !== requestedPosterSource)
            return
        activePosterLayer = layer
        resolvedPosterSource = sourceText
        posterHasPresentedFrame = true
    }

    function commitPosterFallback(sourceText, generation) {
        if (generation !== posterGeneration || sourceText !== requestedPosterSource)
            return
        activePosterLayer = -1
        resolvedPosterSource = sourceText
        posterHasPresentedFrame = false
        posterA.source = ""
        posterB.source = ""
    }

    onPosterIdentityChanged: resetPosterForIdentity()
    Component.onCompleted: resetPosterForIdentity()

    property color focusColor: "#7DF9FF"
    property color armedColor: "#FF3040"
    property color runningColor: "#22FF88"
    property color stoppedColor: "#FF4055"

    readonly property string appId: valueFor(["id", "appId", "desktopId"], "")
    readonly property string appName: valueFor(["name", "title", "displayName"], "Unknown App")
    readonly property string appSubtitle: valueFor(["subtitle", "tagline"], "")
    readonly property string appDescription: valueFor(["description", "summary"], "")
    readonly property string appCategory: valueFor(["category", "group"], "Apps")
    readonly property bool isBackground: appData ? boolValue(appData.backgroundRunning) : false
    readonly property bool isRunning: isBackground || computeRunning()
    readonly property string statusText: isBackground ? "Background" : (isRunning ? "Active" : "Inactive")
    readonly property string platformText: applicationPlatform()
    readonly property url posterSource: resolveAsset("poster", ["poster", "posterPath", "cover"], appId)
    readonly property url iconSource: resolveAsset("icon", ["icon", "iconPath"], appId)

    signal openRequested(var appData, int realIndex)

    radius: 42
    accent: armed ? armedColor : focusColor
    normalScale: 1.0
    focusedScale: 1.0
    armedScale: 1.0
    pressedScale: 1.0
    pointerEnabled: false
    color: "#050A14"
    clip: true

    border.width: armed ? 4 : focused ? 3 : 1
    border.color: armed ? armedColor : focused ? focusColor : "#36516F"

    function open() {
        openRequested(appData, realIndex)
    }

    function clean(value) {
        if (value === undefined || value === null)
            return ""
        var text = String(value).trim()
        return text === "undefined" || text === "null" ? "" : text
    }

    function valueFor(keys, fallbackValue) {
        if (!appData)
            return fallbackValue
        for (var i = 0; i < keys.length; ++i) {
            try {
                var value = appData[keys[i]]
                if (clean(value).length > 0)
                    return clean(value)
            } catch (error) {
            }
        }
        return fallbackValue
    }

    function boolValue(value) {
        if (value === true)
            return true
        if (value === false || value === undefined || value === null)
            return false
        var text = String(value).toLowerCase()
        return text === "true" || text === "1" || text === "running" ||
               text === "active" || text === "online" || text.indexOf("up ") === 0
    }

    function computeRunning() {
        if (!appData)
            return false
        var keys = ["running", "isRunning", "active", "serviceRunning", "uiRunning"]
        for (var i = 0; i < keys.length; ++i) {
            try {
                if (boolValue(appData[keys[i]]))
                    return true
            } catch (error) {
            }
        }
        var state = valueFor(["status", "state", "serviceStatus", "containerStatus"], "").toLowerCase()
        return state === "running" || state === "active" || state === "online" ||
               state.indexOf("running") >= 0 || state.indexOf("up ") === 0
    }

    function applicationPlatform() {
        var source = valueFor(["source"], "").toLowerCase()
        var category = valueFor(["category", "group"], "").toLowerCase()
        var id = appId.toLowerCase()
        var systemIds = [
            "terminal", "settings", "logs", "storage", "filemanager", "docker",
            "controller", "network", "system", "screensaver"
        ]
        if (source === "builtin" || source === "system" || category === "system" ||
                systemIds.indexOf(id) >= 0)
            return "NeutronOS"
        return "Apps"
    }

    function absoluteSource(value) {
        var text = clean(value).toLowerCase()
        return text.indexOf("file:") === 0 || text.indexOf("qrc:") === 0 ||
               text.indexOf("http://") === 0 || text.indexOf("https://") === 0 ||
               text.indexOf("image://") === 0
    }

    function hasExtension(value) {
        var text = clean(value).toLowerCase()
        return /\.(png|jpg|jpeg|webp|svg)$/.test(text)
    }

    function themeFile(path) {
        try {
            if (typeof assetManager !== "undefined" && assetManager &&
                    typeof assetManager.themeFile === "function")
                return assetManager.themeFile(path)
        } catch (error) {
        }
        return "../../themes/Default/" + path
    }

    function fallbackHash() {
        var source = (appId.length > 0 ? appId : appName) + ":" + appCategory
        var value = 7
        for (var i = 0; i < source.length; ++i)
            value = ((value * 31) + source.charCodeAt(i)) & 0x7fffffff
        return value
    }

    function fallbackColor(offset) {
        var palette = [
            "#FF4E9C", "#B56AFF", "#6B7CFF", "#26C6FF",
            "#35E6C1", "#79E85A", "#FFD34D", "#FF7B4D"
        ]
        return palette[(fallbackHash() + offset) % palette.length]
    }

    function fallbackInitials() {
        var words = appName.trim().split(/\\s+/)
        if (words.length === 0 || words[0].length === 0)
            return "APP"
        if (words.length === 1)
            return words[0].substring(0, 2).toUpperCase()
        return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase()
    }

    function fallbackDetail() {
        if (appSubtitle.length > 0)
            return appSubtitle
        if (appDescription.length > 0)
            return appDescription
        return appCategory + " for NeutronOS"
    }

    function legacyUtilityIconName(value) {
        var text = clean(value).replace(/\\/g, "/").toLowerCase()

        if (text.indexOf("/") >= 0)
            text = text.substring(text.lastIndexOf("/") + 1)

        if (hasExtension(text))
            text = text.substring(0, text.lastIndexOf("."))

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

    function legacyIconFile(value) {
        var text = clean(value).replace(/\\/g, "/")

        if (text.indexOf("/") >= 0)
            text = text.substring(text.lastIndexOf("/") + 1)

        if (!hasExtension(text))
            text += ".png"

        return text
    }

    function resolveAsset(kind, keys, fallbackId) {
        var raw = valueFor(keys, fallbackId)

        if (absoluteSource(raw))
            return raw

        var text = clean(raw).replace(/\\/g, "/")

        if (kind === "poster") {
            // Legacy Dashboard owns the portrait poster set. Modern Apps uses
            // the normal apps/posters/ root for its new 1:1 artwork.
            if (text.indexOf("apps/posters/legacy/") === 0)
                return themeFile(text)

            if (text.indexOf("apps/posters/") === 0)
                return themeFile(
                    "apps/posters/legacy/" +
                    text.substring("apps/posters/".length)
                )

            if (text.indexOf("posters/legacy/") === 0)
                return themeFile("apps/" + text)

            if (text.indexOf("posters/") === 0)
                return themeFile(
                    "apps/posters/legacy/" +
                    text.substring("posters/".length)
                )

            if (text.indexOf("apps/") === 0)
                return themeFile(text)

            if (text.indexOf("/") >= 0)
                return text

            if (!hasExtension(text))
                text += ".png"

            return themeFile("apps/posters/legacy/" + text)
        }

        if (legacyUtilityIconName(text))
            return themeFile(
                "apps/icons/legacy/" +
                legacyIconFile(text)
            )

        if (text.indexOf("apps/") === 0)
            return themeFile(text)

        if (text.indexOf("icons/") === 0)
            return themeFile("apps/" + text)

        if (text.indexOf("/") >= 0)
            return text

        if (!hasExtension(text))
            text += ".png"

        return themeFile("apps/icons/" + text)
    }

    Item {
        id: fallbackPoster
        anchors.fill: parent
        visible: !root.posterHasPresentedFrame

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#11142B" }
                GradientStop { position: 0.42; color: "#08172A" }
                GradientStop { position: 1.0; color: "#030711" }
            }
        }

        Rectangle {
            width: parent.width * 1.20
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -width * 0.58
            color: "transparent"
            border.width: Math.max(7, parent.width * 0.025)
            border.color: root.fallbackColor(0)
            opacity: 0.34
            rotation: -18
        }

        Rectangle {
            width: parent.width * 0.92
            height: width * 0.42
            radius: height / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -parent.height * 0.13
            color: "transparent"
            border.width: Math.max(5, parent.width * 0.017)
            border.color: root.fallbackColor(2)
            opacity: 0.55
            rotation: 28
        }

        Rectangle {
            width: parent.width * 0.78
            height: width * 0.42
            radius: height / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -parent.height * 0.13
            color: "transparent"
            border.width: Math.max(4, parent.width * 0.014)
            border.color: root.fallbackColor(4)
            opacity: 0.50
            rotation: -34
        }

        Text {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 76
            text: "NEUTRONOS  •  " + root.appCategory.toUpperCase()
            color: root.fallbackColor(2)
            font.pixelSize: Math.max(12, parent.width * 0.042)
            font.bold: true
            font.letterSpacing: 1.8
        }

        Rectangle {
            id: fallbackCore
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -parent.height * 0.13
            width: parent.width * 0.36
            height: width
            radius: width / 2
            color: "#D9071120"
            border.width: Math.max(4, width * 0.04)
            border.color: root.fallbackColor(0)

            Image {
                id: fallbackIcon
                anchors.fill: parent
                anchors.margins: parent.width * 0.12
                source: root.iconSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: fallbackIcon.status !== Image.Ready
                text: root.fallbackInitials()
                color: "#F4FBFF"
                font.pixelSize: parent.width * 0.29
                font.bold: true
                font.letterSpacing: 1.2
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: fallbackCore.bottom
            anchors.topMargin: 28
            anchors.leftMargin: 34
            anchors.rightMargin: 34
            spacing: 10

            Text {
                width: parent.width
                text: root.appName
                color: "#FFFFFF"
                font.pixelSize: Math.max(24, root.width * 0.085)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                style: Text.Outline
                styleColor: "#B0000000"
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.72, 250)
                height: 4
                radius: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.fallbackColor(0) }
                    GradientStop { position: 0.5; color: root.fallbackColor(2) }
                    GradientStop { position: 1.0; color: root.fallbackColor(4) }
                }
            }

            Text {
                width: parent.width
                text: root.fallbackDetail()
                color: "#B8D1E8"
                font.pixelSize: Math.max(13, root.width * 0.043)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.25
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00030711" }
                GradientStop { position: 1.0; color: "#F8030711" }
            }
        }
    }

    Image {
        id: posterA
        property string requestedSource: ""
        property int requestGeneration: -1
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        // Theme posters are local files. Synchronous cached loading prevents
        // a reused carousel slot from showing another app or the fallback for
        // several animation frames.
        asynchronous: false
        cache: true
        smooth: true
        sourceSize.width: 500
        sourceSize.height: 750
        mipmap: false
        opacity: root.activePosterLayer === 0 && status === Image.Ready ? 1.0 : 0.0
        onStatusChanged: {
            if (status === Image.Ready)
                root.commitPosterFrame(0, requestedSource, requestGeneration)
            else if (status === Image.Error && requestedSource === root.requestedPosterSource)
                root.commitPosterFallback(requestedSource, requestGeneration)
        }
        Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    Image {
        id: posterB
        property string requestedSource: ""
        property int requestGeneration: -1
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        // Theme posters are local files. Synchronous cached loading prevents
        // a reused carousel slot from showing another app or the fallback for
        // several animation frames.
        asynchronous: false
        cache: true
        smooth: true
        sourceSize.width: 500
        sourceSize.height: 750
        mipmap: false
        opacity: root.activePosterLayer === 1 && status === Image.Ready ? 1.0 : 0.0
        onStatusChanged: {
            if (status === Image.Ready)
                root.commitPosterFrame(1, requestedSource, requestGeneration)
            else if (status === Image.Error && requestedSource === root.requestedPosterSource)
                root.commitPosterFallback(requestedSource, requestGeneration)
        }
        Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#16000000" }
            GradientStop { position: 0.42; color: "#26000000" }
            GradientStop { position: 0.70; color: "#B8050A14" }
            GradientStop { position: 1.0; color: "#FC050A14" }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.armed ? "#20FF3040" : root.focused ? "#0A7DF9FF" : "transparent"
    }

    Rectangle {
        id: numberPill
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 18
        width: Math.max(64, numberText.implicitWidth + 30)
        height: 32
        radius: 16
        color: "#E307101D"
        border.width: 1
        border.color: root.armed ? root.armedColor : root.focused ? root.focusColor : "#5C7898"

        Text {
            id: numberText
            anchors.centerIn: parent
            text: root.displayNumber > 0 ? (root.displayNumber < 10 ? "0" + root.displayNumber : String(root.displayNumber)) : "--"
            color: "#F4FBFF"
            font.pixelSize: 14
            font.bold: true
            font.letterSpacing: 1.6
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        anchors.bottomMargin: 28
        spacing: 10

        Rectangle {
            id: appIconFrame
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.focused || root.armed ? 138 : 124
            height: width
            radius: Math.round(width * 0.235)
            color: "#E90B1524"
            border.width: root.focused || root.armed ? 2 : 1
            border.color: root.armed ? root.armedColor : root.focused ? root.focusColor : "#577392"
            clip: true

            Behavior on width {
                enabled: root.animationsEnabled
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Image {
                id: icon
                anchors.fill: parent
                anchors.margins: 0
                source: root.iconSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                sourceSize.width: 500
                sourceSize.height: 500
                mipmap: false
                opacity: status === Image.Ready ? 1.0 : 0.0
            }

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.58
                height: width
                source: root.themeFile("atom.svg")
                fillMode: Image.PreserveAspectFit
                visible: icon.status !== Image.Ready
                opacity: 0.72
                smooth: true
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height * 0.42
                color: "#FFFFFF"
                opacity: 0.09
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: "#66FFFFFF"
            }
        }

        Text {
            width: parent.width
            text: root.appName
            color: "#FFFFFF"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: root.focused || root.armed ? 30 : 27
            font.bold: true
            style: Text.Outline
            styleColor: "#D8000000"
        }

        Text {
            width: parent.width
            text: root.platformText
            color: root.focused || root.armed ? "#BDF7FF" : "#9EB7CF"
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 14
            font.bold: true
            font.letterSpacing: 1.4
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(118, statusLabel.implicitWidth + 44)
            height: 38
            radius: 19
            color: root.isRunning ? "#D50A2A20" : "#D52A0A12"
            border.width: 1
            border.color: root.isRunning ? root.runningColor : root.stoppedColor

            Row {
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    width: 11
                    height: 11
                    radius: 6
                    color: root.isRunning ? root.runningColor : root.stoppedColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: statusLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusText
                    color: root.isRunning ? "#A9FFD1" : "#FFB2BC"
                    font.pixelSize: 15
                    font.bold: true
                }
            }
        }
    }

    Rectangle {
        visible: root.armed
        anchors.fill: parent
        anchors.margins: 8
        radius: root.radius - 8
        color: "transparent"
        border.width: 3
        border.color: root.armedColor
        opacity: 0.9
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.open()
    }
}
