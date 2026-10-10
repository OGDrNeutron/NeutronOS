import QtQuick 2.15

Item {
    id: card

    signal clicked()
    signal successAnimationFinished()

    /*
        ============================================================
                            CIRCULAR USER CARD
        ============================================================

        Preserved from original:
            - Circular login card.
            - Large clear avatar.
            - Blue/pink helix ring.
            - Red armed/locked/error mode.
            - Green success burst.
            - Motion tilt is visual only.
            - Nudge animation for controller input.
            - Error shake animation.
            - Lockout animation.
            - Success animation signal.
            - No MouseArea.
            - No Button.

        Next-gen updates:
            - Animations pause when hidden/disabled/inactive.
            - Canvas repaint timer pauses when hidden.
            - Safe icon resolution through AssetManager when available.
            - Fallback user icon path uses themes/Default/users/user_icon.png.
            - Added handleController() helper for controller-first login flow.
            - Added safe numeric motion handling.
            - Canvas repaints on state/size/source changes.
            - Does not emit login input from motion.
            - Does not fight LoginScreen success/singularity animation.
    */

    property bool selected: false
    property bool successMode: false
    property bool armedMode: false
    property bool lockedMode: false
    property bool errorMode: false
    property bool active: true

    property bool animationsEnabled: visible && enabled && active
    property bool canvasRunning: animationsEnabled

    property string displayName: "User"
    property string username: ""
    property string role: "Local Profile"
    property string iconSource: ""
    property string lockoutText: "LOCKED"

    // Patch 19: persistent appearance shared with the Console user card.
    property color nameTint: "#FFFFFF"
    property color accentColor: neutronBlue
    property string frameStyle: "circle"
    property real glowStrength: 0.65

    function profileRadius(size) {
        var style = String(frameStyle || "circle").toLowerCase()
        if (style === "square")
            return Math.max(10, size * 0.10)
        if (style === "rounded")
            return Math.max(18, size * 0.24)
        return size / 2
    }

    /*
        Kept from original. Some login designs may bind this later.
    */
    property var backdropSource: null

    property color neutronBlue: "#7DF9FF"
    property color neutronBlueDeep: "#47C8FF"
    property color neutronPink: "#FF4EA8"
    property color neutronPurple: "#C084FC"
    property color neutronRed: "#FF3040"
    property color secureGreen: "#22FF88"
    property color darkShell: "#02060D"
    property color deepGlass: "#071426"

    property real pulseOpacity: 0.0

    /* Dedicated per-press acknowledgement, independent of armed pulse loops. */
    property real inputAckPulse: 0.0
    property real inputAckScale: 1.0

    property real ringPulse: 0.45
    property real unstablePulse: 0.35
    property real ringRotation: 0.0
    property real secondaryRingRotation: 0.0
    property real helixWave: 0.0

    property real successScale: 1.0
    property real tiltX: 0
    property real tiltY: 0
    property real motionTiltX: 0
    property real motionTiltY: 0

    property real shakeOffsetX: 0
    property real shakeOffsetY: 0

    property real diameter: Math.min(width, height)

    /*
        Bigger avatar.
        The icon fills almost the whole circular card.
    */
    property real avatarDiameter: Math.max(128, diameter - 28)

    width: 445
    height: 445
    focus: true

    opacity: 1.0

    /*
        LoginScreen owns the unlock singularity scale.
        During successMode, this card must not fight the parent reveal animation.
    */
    scale: armedMode && !successMode ? 1.012 : 1.0

    Behavior on scale {
        enabled: card.animationsEnabled && !card.successMode

        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on tiltX {
        enabled: card.animationsEnabled

        NumberAnimation {
            duration: 62
            easing.type: Easing.OutCubic
        }
    }

    Behavior on tiltY {
        enabled: card.animationsEnabled

        NumberAnimation {
            duration: 62
            easing.type: Easing.OutCubic
        }
    }

    Behavior on motionTiltX {
        enabled: card.animationsEnabled

        NumberAnimation {
            duration: 58
            easing.type: Easing.OutCubic
        }
    }

    Behavior on motionTiltY {
        enabled: card.animationsEnabled

        NumberAnimation {
            duration: 58
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ASSET HELPERS
        ============================================================
    */

    function cleanText(value) {
        if (value === undefined || value === null)
            return ""

        var text = String(value).trim()

        if (text === "undefined" || text === "null")
            return ""

        return text
    }

    function isAbsoluteSource(value) {
        var text = String(value || "").trim()
        var lower = text.toLowerCase()

        return text.charAt(0) === "/" ||
               lower.indexOf("file:") === 0 ||
               lower.indexOf("qrc:") === 0 ||
               lower.indexOf("http://") === 0 ||
               lower.indexOf("https://") === 0 ||
               lower.indexOf("image://") === 0
    }

    function themeFile(path) {
        var cleanPath = cleanText(path)

        if (cleanPath.length <= 0)
            return ""

        if (cleanPath.charAt(0) === "/")
            return "file://" + cleanPath

        if (isAbsoluteSource(cleanPath))
            return cleanPath

        cleanPath = cleanPath.replace(/^\.\//, "")
        cleanPath = cleanPath.replace(/^themes\/Default\//, "")
        cleanPath = cleanPath.replace(/^Default\//, "")

        try {
            if (typeof assetManager !== "undefined" &&
                    assetManager &&
                    typeof assetManager.themeFile === "function") {
                var managedSource = cleanText(assetManager.themeFile(cleanPath))

                if (managedSource.length > 0)
                    return managedSource
            }
        } catch (e) {
        }

        /*
            UserCard.qml lives in qml/components/. The canonical theme folder
            is therefore two levels above this file, not inside qml/.
        */
        return Qt.resolvedUrl(
            "../../themes/Default/" + cleanPath
        )
    }

    function resolvedIconSource() {
        var direct = cleanText(iconSource)

        if (direct.length > 0) {
            if (direct.charAt(0) === "/")
                return "file://" + direct

            if (isAbsoluteSource(direct))
                return direct

            direct = direct.replace(/^\.\//, "")

            if (direct.indexOf("/") >= 0)
                return themeFile(direct)

            return themeFile("users/" + direct)
        }

        try {
            if (typeof assetManager !== "undefined" &&
                    assetManager &&
                    typeof assetManager.userIcon === "function") {
                var managedIcon = cleanText(assetManager.userIcon())

                if (managedIcon.length > 0)
                    return managedIcon
            }
        } catch (e) {
        }

        return Qt.resolvedUrl(
            "../../themes/Default/users/user_icon.png"
        )
    }

    function shownInitial() {
        var name = cleanText(displayName)

        if (name.length <= 0)
            name = cleanText(username)

        if (name.length <= 0)
            return "?"

        return name.charAt(0).toUpperCase()
    }

    /*
        ============================================================
                            ANIMATION VALUES
        ============================================================
    */

    SequentialAnimation on ringPulse {
        running: card.animationsEnabled && !card.successMode
        loops: Animation.Infinite

        NumberAnimation {
            from: card.armedMode || card.lockedMode ? 0.56 : 0.28
            to: 1.0
            duration: card.armedMode || card.lockedMode ? 1100 : 2200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: card.armedMode || card.lockedMode ? 0.56 : 0.28
            duration: card.armedMode || card.lockedMode ? 1100 : 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on unstablePulse {
        running: card.animationsEnabled &&
                 !card.armedMode &&
                 !card.lockedMode &&
                 !card.successMode

        loops: Animation.Infinite

        NumberAnimation {
            from: 0.20
            to: 1.0
            duration: 620
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.42
            duration: 1040
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 0.42
            to: 0.78
            duration: 390
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            from: 0.78
            to: 0.20
            duration: 920
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on helixWave {
        running: card.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: card.armedMode || card.lockedMode ? 760 : 1300
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: card.armedMode || card.lockedMode ? 760 : 1300
            easing.type: Easing.InOutSine
        }
    }

    NumberAnimation on ringRotation {
        running: card.animationsEnabled
        from: 0
        to: 360
        duration: card.armedMode || card.lockedMode ? 6600 : 8500
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    NumberAnimation on secondaryRingRotation {
        running: card.animationsEnabled && !card.armedMode && !card.lockedMode
        from: 360
        to: 0
        duration: 11800
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    /*
        ============================================================
                            VISUAL GROUP
        ============================================================
    */

    Item {
        id: visualGroup

        width: card.diameter
        height: card.diameter

        x: (card.width - width) / 2 + card.shakeOffsetX
        y: (card.height - height) / 2 + card.shakeOffsetY
        scale: card.inputAckScale

        property color stateColor: card.successMode
                                   ? card.secureGreen
                                   : card.lockedMode
                                     ? card.neutronRed
                                     : card.armedMode || card.errorMode
                                       ? card.neutronRed
                                       : card.neutronBlue

        transform: [
            Rotation {
                origin.x: visualGroup.width / 2
                origin.y: visualGroup.height / 2
                axis.x: 1
                angle: card.tiltX + card.motionTiltX
            },
            Rotation {
                origin.x: visualGroup.width / 2
                origin.y: visualGroup.height / 2
                axis.y: 1
                angle: card.tiltY + card.motionTiltY
            }
        ]

        /*
            Soft contained glow.
            No floating loose line pieces.
        */
        Rectangle {
            anchors.centerIn: parent

            width: parent.width - 4 + card.ringPulse * 34
            height: width
            radius: width / 2

            color: visualGroup.stateColor

            opacity: card.successMode
                     ? 0.050 + card.ringPulse * 0.055
                     : card.lockedMode
                       ? 0.048 + card.ringPulse * 0.046
                       : card.armedMode
                         ? 0.040 + card.ringPulse * 0.038
                         : 0.022 + card.unstablePulse * 0.036
        }

        /*
            Vivid helix wave ring.
            This replaces the old blue line segment ring.
        */
        Canvas {
            id: helixRing

            /* Keep the expensive Context2D paint work off the GUI/input thread. */
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Threaded

            anchors.centerIn: parent

            width: parent.width
            height: parent.height

            rotation: card.ringRotation
            opacity: card.lockedMode ? 0.84 :
                     card.armedMode ? 0.90 :
                     card.successMode ? 0.96 :
                                        0.88

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                if (width <= 2 || height <= 2)
                    return

                var cx = width / 2
                var cy = height / 2

                var phase = card.ringRotation * Math.PI / 180.0
                var wave = card.helixWave
                var unstable = card.unstablePulse

                var outerRadius = width * 0.472
                var innerRadius = width * 0.414

                ctx.lineCap = "round"

                /*
                    Main double-helix arcs.
                */
                for (var i = 0; i < 72; i++) {
                    var t = i / 72.0
                    var angle = t * Math.PI * 2.0

                    var waveA = Math.sin(angle * 3.0 + phase * 2.35)
                    var waveB = Math.sin(angle * 5.0 - phase * 1.45)

                    var arcSize = 0.082 + unstable * 0.040 + Math.abs(waveA) * 0.016

                    var radiusA = outerRadius + waveA * 12.0 + waveB * 5.0
                    var radiusB = innerRadius - waveA * 10.0 + waveB * 5.0

                    var startA = angle + phase * 0.18
                    var endA = startA + arcSize

                    var startB = -angle - phase * 0.20
                    var endB = startB - arcSize

                    var alphaA = 0.34 + wave * 0.34 + Math.abs(waveA) * 0.18
                    var alphaB = 0.30 + wave * 0.30 + Math.abs(waveB) * 0.15

                    var blue = "rgba(125,249,255," + alphaA + ")"
                    var pink = "rgba(255,78,168," + alphaB + ")"
                    var red = "rgba(255,48,64," + (0.42 + card.ringPulse * 0.38) + ")"
                    var green = "rgba(34,255,136," + (0.42 + card.ringPulse * 0.42) + ")"

                    ctx.beginPath()

                    if (card.successMode)
                        ctx.strokeStyle = i % 2 === 0 ? green : blue
                    else if (card.armedMode || card.lockedMode || card.errorMode)
                        ctx.strokeStyle = red
                    else
                        ctx.strokeStyle = i % 2 === 0 ? blue : pink

                    ctx.lineWidth = card.armedMode || card.lockedMode
                                    ? 4.8
                                    : 4.0 + Math.abs(waveA) * 1.5

                    ctx.arc(cx, cy, radiusA, startA, endA, false)
                    ctx.stroke()

                    ctx.beginPath()

                    if (card.successMode)
                        ctx.strokeStyle = i % 2 === 0 ? blue : green
                    else if (card.armedMode || card.lockedMode || card.errorMode)
                        ctx.strokeStyle = "rgba(255,48,64,0.36)"
                    else
                        ctx.strokeStyle = i % 2 === 0 ? pink : blue

                    ctx.lineWidth = card.armedMode || card.lockedMode
                                    ? 2.8
                                    : 2.4 + Math.abs(waveB) * 1.2

                    ctx.arc(cx, cy, radiusB, startB, endB, true)
                    ctx.stroke()
                }

                /*
                    Thin contained inner/outer guides.
                    These make it look premium without loose line artifacts.
                */
                ctx.beginPath()
                ctx.strokeStyle = card.successMode
                                  ? "rgba(34,255,136,0.62)"
                                  : card.armedMode || card.lockedMode || card.errorMode
                                    ? "rgba(255,48,64,0.44)"
                                    : "rgba(125,249,255,0.36)"
                ctx.lineWidth = 1.2
                ctx.arc(cx, cy, outerRadius + 22, 0, Math.PI * 2.0, false)
                ctx.stroke()

                ctx.beginPath()
                ctx.strokeStyle = card.successMode
                                  ? "rgba(34,255,136,0.44)"
                                  : card.armedMode || card.lockedMode || card.errorMode
                                    ? "rgba(255,48,64,0.32)"
                                    : "rgba(255,78,168,0.34)"
                ctx.lineWidth = 1.1
                ctx.arc(cx, cy, innerRadius - 25, 0, Math.PI * 2.0, false)
                ctx.stroke()
            }

            Timer {
                /*
                    Texture repaints are intentionally slower while armed. The
                    Canvas item itself still rotates smoothly in the scene graph.
                */
                interval: card.armedMode ? 33 : 24
                repeat: true

                running: card.canvasRunning

                onTriggered: helixRing.requestPaint()
            }

            Connections {
                target: card

                function onSuccessModeChanged() {
                    helixRing.requestPaint()
                }

                function onArmedModeChanged() {
                    helixRing.requestPaint()
                }

                function onLockedModeChanged() {
                    helixRing.requestPaint()
                }

                function onErrorModeChanged() {
                    helixRing.requestPaint()
                }

                function onVisibleChanged() {
                    if (card.visible)
                        helixRing.requestPaint()
                }

                function onEnabledChanged() {
                    if (card.enabled)
                        helixRing.requestPaint()
                }

                function onWidthChanged() {
                    helixRing.requestPaint()
                }

                function onHeightChanged() {
                    helixRing.requestPaint()
                }
            }
        }

        /*
            Main circular user icon.
            Clean and clear. No yellow tint.
        */
        Rectangle {
            id: profileAppearanceGlow
            anchors.centerIn: parent
            width: card.avatarDiameter + 20
            height: width
            radius: card.profileRadius(width)
            color: "transparent"
            border.width: 5
            border.color: card.accentColor
            opacity: card.lockedMode || card.armedMode
                     ? 0.0
                     : Math.max(0.0, Math.min(0.62, Number(card.glowStrength) * 0.62))
        }

        Rectangle {
            id: avatarClip

            anchors.centerIn: parent

            width: card.avatarDiameter
            height: card.avatarDiameter
            radius: card.profileRadius(width)

            color: "#02060D"
            clip: true

            border.width: 0

            /*
                Deep base behind transparent PNGs.
            */
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "#02060D"
                opacity: 1.0
            }

            Image {
                id: avatarImage

                anchors.fill: parent
                anchors.margins: 0

                source: card.resolvedIconSource()
                fillMode: Image.PreserveAspectCrop

                smooth: true
                asynchronous: false
                cache: true
                sourceSize.width: 320
                sourceSize.height: 320
                mipmap: false

                visible: !card.lockedMode
                opacity: card.successMode ? 0.92 : 1.0
            }

            /*
                Minimal dark protection only.
                No yellow, green, or heavy blue tint.
            */
            Rectangle {
                anchors.fill: parent

                color: "#000000"
                opacity: card.lockedMode ? 0.68 :
                         card.armedMode ? 0.045 :
                         card.successMode ? 0.020 :
                                            0.000
            }

            Text {
                anchors.centerIn: parent

                visible: avatarImage.status !== Image.Ready && !card.lockedMode

                text: card.shownInitial()

                color: "white"

                font.pixelSize: avatarClip.width * 0.36
                font.bold: true
            }

            Column {
                anchors.centerIn: parent

                visible: card.lockedMode
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: card.lockoutText

                    color: card.neutronRed

                    font.pixelSize: 28
                    font.bold: true
                    font.letterSpacing: 4
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: "SECURITY"

                    color: "#ff9a9a"

                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 3
                }
            }
        }

        /*
            Thin clean border around the icon.
        */
        Rectangle {
            anchors.centerIn: avatarClip

            width: avatarClip.width
            height: avatarClip.height
            radius: card.profileRadius(width)

            color: "transparent"

            border.width: card.armedMode || card.lockedMode ? 3 : 2
            border.color: card.armedMode || card.lockedMode || card.errorMode
                          ? visualGroup.stateColor
                          : card.accentColor

            opacity: card.successMode
                     ? 0.96
                     : card.lockedMode
                       ? 0.92
                       : card.armedMode
                         ? 0.92
                         : 0.70 + card.unstablePulse * 0.18

            Behavior on border.color {
                enabled: card.animationsEnabled

                ColorAnimation {
                    duration: 170
                }
            }
        }

        /*
            Inner glass outline.
        */
        Rectangle {
            anchors.centerIn: avatarClip

            width: avatarClip.width - 18
            height: avatarClip.height - 18
            radius: card.profileRadius(width)

            color: "transparent"

            border.width: 1
            border.color: "#FFFFFF"

            opacity: card.lockedMode ? 0.04 : 0.13
        }

        /*
            Success pulse ring.
        */
        Rectangle {
            anchors.centerIn: avatarClip

            width: avatarClip.width + 18 + card.pulseOpacity * 26
            height: width
            radius: card.profileRadius(width)

            color: "transparent"

            border.width: 3
            border.color: card.secureGreen

            opacity: card.successMode ? card.pulseOpacity : 0
        }

        /*
            Error / armed pulse ring.
        */
        Rectangle {
            anchors.centerIn: avatarClip

            width: avatarClip.width + 20 + card.pulseOpacity * 20
            height: width
            radius: card.profileRadius(width)

            color: "transparent"

            border.width: card.lockedMode ? 4 : 3
            border.color: card.lockedMode ? "#ff0000" : card.neutronRed

            opacity: card.errorMode || card.lockedMode || card.armedMode
                     ? card.pulseOpacity
                     : 0
        }
    }

    /*
        Guaranteed acknowledgement for every captured token, including repeated
        presses of the same direction and non-direction buttons.
    */
    Rectangle {
        anchors.centerIn: parent
        width: card.avatarDiameter + 30 + card.inputAckPulse * 22
        height: width
        radius: card.profileRadius(width)
        color: "transparent"
        border.width: 2
        border.color: card.armedMode ? "#FFFFFF" : card.neutronBlue
        opacity: card.inputAckPulse * 0.78
        z: 20
    }

    ParallelAnimation {
        id: inputAckAnimation

        NumberAnimation {
            target: card
            property: "inputAckPulse"
            from: 1.0
            to: 0.0
            duration: 115
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: card
            property: "inputAckScale"
            from: 0.986
            to: 1.0
            duration: 95
            easing.type: Easing.OutCubic
        }
    }

    /*
        ============================================================
                            ANIMATION BLOCKS
        ============================================================
    */

    SequentialAnimation {
        running: card.animationsEnabled &&
                 card.armedMode &&
                 !card.successMode &&
                 !card.errorMode &&
                 !card.lockedMode

        loops: Animation.Infinite

        NumberAnimation {
            target: card
            property: "pulseOpacity"
            from: 0.18
            to: 0.74
            duration: 820
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: card
            property: "pulseOpacity"
            from: 0.74
            to: 0.18
            duration: 820
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        id: errorAnimation
        running: false

        ScriptAction {
            script: {
                card.errorMode = true
                card.pulseOpacity = 1.0
            }
        }

        NumberAnimation { target: card; property: "shakeOffsetX"; from: 0; to: -18; duration: 42; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "shakeOffsetX"; from: -18; to: 18; duration: 42; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "shakeOffsetX"; from: 18; to: -14; duration: 42; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "shakeOffsetX"; from: -14; to: 14; duration: 42; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "shakeOffsetX"; from: 14; to: 0; duration: 42; easing.type: Easing.OutQuad }

        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.18; duration: 70 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.18; to: 1.0; duration: 70 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.18; duration: 70 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.18; to: 1.0; duration: 70 }

        ScriptAction {
            script: {
                card.errorMode = false
                card.pulseOpacity = card.armedMode ? 0.45 : 0.0
                card.shakeOffsetX = 0
                card.shakeOffsetY = 0
            }
        }
    }

    SequentialAnimation {
        id: lockoutAnimation
        running: false

        ScriptAction {
            script: {
                card.pulseOpacity = 1.0
                card.tiltX = 0
                card.tiltY = 0
                card.motionTiltX = 0
                card.motionTiltY = 0
            }
        }

        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.25; duration: 80 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.25; to: 1.0; duration: 80 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.25; duration: 80 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.25; to: 1.0; duration: 80 }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.85; duration: 180 }
    }

    SequentialAnimation {
        id: successAnimation
        running: false

        /*
            Legacy-safe success pulse only.

            LoginScreen owns:
                - double green pulse
                - singularity shrink
                - ripple reveal
                - final unlock timing

            This animation no longer fades or shrinks the card by itself.
        */

        ScriptAction {
            script: {
                card.successMode = true
                card.pulseOpacity = 1.0
                card.successScale = 1.0
                card.tiltX = 0
                card.tiltY = 0
                card.motionTiltX = 0
                card.motionTiltY = 0
                card.shakeOffsetX = 0
                card.shakeOffsetY = 0
                card.opacity = 1.0
            }
        }

        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.25; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.25; to: 1.0; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 1.0; to: 0.25; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "pulseOpacity"; from: 0.25; to: 1.0; duration: 90; easing.type: Easing.OutCubic }

        ScriptAction {
            script: card.successAnimationFinished()
        }
    }

    Timer {
        id: resetTilt

        interval: 86
        repeat: false

        onTriggered: {
            card.tiltX = 0
            card.tiltY = 0
        }
    }

    /*
        ============================================================
                            PUBLIC API
        ============================================================
    */

    function activate() {
        if (!card.active || !card.enabled || card.successMode || card.lockedMode)
            return false

        card.clicked()
        return true
    }

    function handleController(action) {
        if (action === "primary" ||
                action === "x" ||
                action === "confirm" ||
                action === "cross") {
            return card.activate()
        }

        if (action === "cancel" ||
                action === "o" ||
                action === "circle") {
            if (card.armedMode && !card.successMode && !card.lockedMode) {
                card.armedMode = false
                card.pulseOpacity = 0.0
                return true
            }
        }

        return false
    }

    function nudge(key) {
        if (!card.enabled || !card.active)
            return

        /* Every press gets an independent pulse, even U,U or D,D. */
        inputAckAnimation.stop()
        inputAckPulse = 1.0
        inputAckScale = 0.986

        if (key === "U")
            tiltX = -3.6
        else if (key === "D")
            tiltX = 3.6
        else if (key === "L")
            tiltY = -3.6
        else if (key === "R")
            tiltY = 3.6

        inputAckAnimation.restart()
        resetTilt.restart()
    }

    /*
        Motion is visual telemetry only.
        It must never emit clicked(), directions, login input, or failures.
    */
    function setMotionTilt(xValue, yValue) {
        if (!card.enabled || !card.active) {
            clearMotionTilt()
            return
        }

        var x = Number(xValue)
        var y = Number(yValue)

        if (isNaN(x))
            x = 0

        if (isNaN(y))
            y = 0

        motionTiltY = Math.max(-6, Math.min(6, x * 6))
        motionTiltX = Math.max(-6, Math.min(6, y * 6))
    }

    function clearMotionTilt() {
        motionTiltX = 0
        motionTiltY = 0
    }

    function startErrorAnimation() {
        if (!card.enabled)
            return

        errorAnimation.restart()
    }

    function startLockoutAnimation() {
        if (!card.enabled)
            return

        lockoutAnimation.restart()
    }

    function startSuccessAnimation() {
        if (!card.enabled)
            return

        successAnimation.restart()
    }

    onVisibleChanged: {
        if (!visible)
            clearMotionTilt()
    }

    onEnabledChanged: {
        if (!enabled) {
            clearMotionTilt()
            resetTilt.stop()
        }
    }

    Component.onCompleted: {
        helixRing.requestPaint()
    }
}