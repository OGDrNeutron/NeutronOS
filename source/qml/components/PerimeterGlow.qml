import QtQuick 2.15

Item {
    id: root

    /*
        ============================================================
                            PERIMETER GLOW
        ============================================================

        Modes:
        - circular: false = rectangular premium perimeter glow
        - circular: true  = circular lock-card energy helix

        Original behavior preserved:
        - Rectangular premium perimeter sweep.
        - Circular blue/pink helix wave.
        - Red danger mode.
        - Corner brackets.
        - Inner/outer guide rings.
        - Display only.
        - No Button.
        - No MouseArea.
        - No shader.

        Next-gen updates:
        - Animations pause when hidden, disabled, inactive, or not running.
        - Circular mode uses scene-graph orbital segments, not a paint timer.
        - Added bounds-safe helper math.
        - Kept the original production visual system intact.
    */

    property bool running: true
    property bool active: true
    property bool danger: false
    property bool circular: false
    property bool unstable: !danger

    property bool animationsEnabled: visible && enabled && active && running

    property color glowColor: danger ? "#ff3040" : "#7df9ff"
    property color secondaryGlowColor: "#ff4ea8"
    property color successGlowColor: "#22ff88"

    property real progress: 0.0
    property real reverseProgress: 1.0

    property real dashLength: circular ? 118 : 132
    property real dashThickness: circular ? 5 : 4

    property real pulse: 0.55
    property real ringPulse: 0.45
    property real sweepPulse: 0.0
    property real cornerPulse: 0.35
    property real dangerFlash: 0.35
    property real unstablePulse: 0.35
    property real helixWave: 0.0

    property real circularMargin: 8
    property real rectangularRadius: Math.max(28, width * 0.045)

    anchors.fill: parent
    anchors.margins: circular ? 0 : -18
    z: 50

    /*
        ============================================================
                            ANIMATIONS
        ============================================================
    */

    NumberAnimation on progress {
        running: root.animationsEnabled

        from: 0.0
        to: 1.0

        duration: root.danger ? 6800 : 8600
        loops: Animation.Infinite

        easing.type: Easing.Linear
    }

    NumberAnimation on reverseProgress {
        running: root.animationsEnabled &&
                 root.circular &&
                 root.unstable &&
                 !root.danger

        from: 1.0
        to: 0.0

        duration: 11800
        loops: Animation.Infinite

        easing.type: Easing.Linear
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: root.danger ? 0.48 : 0.32
            to: 1.0
            duration: root.danger ? 980 : 1450
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: root.danger ? 0.48 : 0.32
            duration: root.danger ? 980 : 1450
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on ringPulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: root.danger ? 0.56 : 0.28
            to: 1.0
            duration: root.danger ? 1100 : 2200
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: root.danger ? 0.56 : 0.28
            duration: root.danger ? 1100 : 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on sweepPulse {
        running: root.animationsEnabled
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: 2400
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: 2400
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on cornerPulse {
        running: root.animationsEnabled && !root.circular
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.22
            to: 1.0
            duration: root.danger ? 620 : 1800
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.22
            duration: root.danger ? 620 : 1800
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation on dangerFlash {
        running: root.animationsEnabled && root.danger
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.25
            to: 1.0
            duration: root.circular ? 900 : 260
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            from: 1.0
            to: 0.25
            duration: root.circular ? 900 : 520
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation on unstablePulse {
        running: root.animationsEnabled &&
                 root.circular &&
                 root.unstable &&
                 !root.danger

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
        running: root.animationsEnabled && root.circular
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.0
            to: 1.0
            duration: root.danger ? 780 : 1300
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.0
            duration: root.danger ? 780 : 1300
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                            CIRCULAR MODE
        ============================================================
    */

    Item {
        id: circleMode

        anchors.fill: parent
        visible: root.circular

        property real sizeValue: Math.max(
                                     0,
                                     Math.min(width, height) -
                                     root.circularMargin * 2
                                 )

        /*
            Soft aura only.
            No floating line pieces.
        */
        Rectangle {
            anchors.centerIn: parent

            width: circleMode.sizeValue + 38 + root.ringPulse * 30
            height: width
            radius: width / 2

            color: root.glowColor

            opacity: root.danger
                     ? 0.040 + root.dangerFlash * 0.045
                     : 0.016 + root.unstablePulse * 0.038
        }

        /*
            Contained outer guide.
        */
        Rectangle {
            anchors.centerIn: parent

            width: circleMode.sizeValue
            height: width
            radius: width / 2

            color: "transparent"

            border.width: root.danger ? 2 : 1
            border.color: root.glowColor

            opacity: root.danger
                     ? 0.46 + root.dangerFlash * 0.24
                     : 0.24 + root.unstablePulse * 0.20
        }

        /*
            Lightweight orbital lattice.

            This replaces the continuously repainted Canvas with static
            scene-graph segments. The two segment rings rotate as complete
            layers, preserving the premium energy motion without a 16 ms
            JavaScript paint timer.
        */
        Item {
            id: orbitalLattice

            anchors.centerIn: parent
            width: circleMode.sizeValue + 42
            height: width

            opacity: root.danger
                     ? 0.84 + root.dangerFlash * 0.12
                     : 0.74 + root.unstablePulse * 0.18

            Item {
                id: outerOrbit

                anchors.fill: parent
                rotation: root.progress * 360

                Repeater {
                    model: 32

                    Rectangle {
                        required property int index

                        readonly property real angle:
                            index * (Math.PI * 2.0 / 32.0)
                        readonly property real orbitRadius:
                            outerOrbit.width * 0.445
                        readonly property bool beacon:
                            index % 8 === 0

                        width: beacon ? 34 : (index % 2 === 0 ? 19 : 12)
                        height: beacon ? 4.8 : 3.2
                        radius: height / 2

                        x: outerOrbit.width / 2 +
                           Math.cos(angle) * orbitRadius - width / 2
                        y: outerOrbit.height / 2 +
                           Math.sin(angle) * orbitRadius - height / 2
                        rotation: angle * 180 / Math.PI + 90

                        color: root.danger
                               ? root.glowColor
                               : index % 2 === 0
                                 ? root.glowColor
                                 : root.secondaryGlowColor

                        opacity: beacon
                                 ? 0.70 + root.ringPulse * 0.26
                                 : 0.34 + root.pulse * 0.30
                    }
                }
            }

            Item {
                id: innerOrbit

                anchors.fill: parent
                rotation: root.reverseProgress * -360

                Repeater {
                    model: 24

                    Rectangle {
                        required property int index

                        readonly property real angle:
                            index * (Math.PI * 2.0 / 24.0) +
                            Math.PI / 24.0
                        readonly property real orbitRadius:
                            innerOrbit.width * 0.382
                        readonly property bool beacon:
                            index % 6 === 0

                        width: beacon ? 25 : (index % 2 === 0 ? 14 : 9)
                        height: beacon ? 3.8 : 2.4
                        radius: height / 2

                        x: innerOrbit.width / 2 +
                           Math.cos(angle) * orbitRadius - width / 2
                        y: innerOrbit.height / 2 +
                           Math.sin(angle) * orbitRadius - height / 2
                        rotation: angle * 180 / Math.PI + 90

                        color: root.danger
                               ? root.glowColor
                               : index % 2 === 0
                                 ? root.secondaryGlowColor
                                 : root.glowColor

                        opacity: beacon
                                 ? 0.52 + root.helixWave * 0.28
                                 : 0.24 + root.helixWave * 0.24
                    }
                }
            }

            /* Contained guide rings keep the energy field cohesive. */
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.94
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: root.glowColor
                opacity: root.danger ? 0.26 : 0.20
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.69
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: root.danger
                              ? root.glowColor
                              : root.secondaryGlowColor
                opacity: root.danger ? 0.19 : 0.17
            }

            /* Four restrained energy nodes add depth without extra timers. */
            Repeater {
                model: 4

                Rectangle {
                    required property int index

                    readonly property real angle:
                        index * Math.PI / 2 + root.progress * Math.PI * 2
                    readonly property real orbitRadius:
                        orbitalLattice.width * 0.414

                    width: 9 + root.ringPulse * 3
                    height: width
                    radius: width / 2

                    x: orbitalLattice.width / 2 +
                       Math.cos(angle) * orbitRadius - width / 2
                    y: orbitalLattice.height / 2 +
                       Math.sin(angle) * orbitRadius - height / 2

                    color: root.danger
                           ? root.glowColor
                           : index % 2 === 0
                             ? root.glowColor
                             : root.secondaryGlowColor
                    opacity: 0.52 + root.ringPulse * 0.32
                }
            }
        }

        /*
            Inner glass ring.
        */
        Rectangle {
            anchors.centerIn: parent

            width: Math.max(0, circleMode.sizeValue - 34)
            height: width
            radius: width / 2

            color: "transparent"

            border.width: 1
            border.color: "#ffffff"

            opacity: root.danger ? 0.08 : 0.10
        }
    }

    /*
        ============================================================
                            RECTANGULAR MODE
        ============================================================
    */

    Item {
        id: rectMode

        anchors.fill: parent
        visible: !root.circular

        Rectangle {
            anchors.fill: parent
            anchors.margins: -20

            radius: root.rectangularRadius

            color: root.glowColor

            opacity: root.danger
                     ? 0.030 + root.dangerFlash * 0.060
                     : 0.016 + root.ringPulse * 0.034
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -8

            radius: Math.max(26, parent.width * 0.040)

            color: "transparent"

            border.width: root.danger ? 3 : 2
            border.color: root.glowColor

            opacity: root.danger
                     ? 0.34 + root.dangerFlash * 0.46
                     : 0.16 + root.ringPulse * 0.30
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3

            radius: Math.max(22, parent.width * 0.034)

            color: "transparent"

            border.width: 1
            border.color: "#ffffff"

            opacity: root.danger ? 0.10 : 0.13
        }

        /*
            Premium perimeter sweep.
        */
        Rectangle {
            id: movingSweep

            visible: root.animationsEnabled && !root.circular

            width: horizontalSide() ? root.dashLength : root.dashThickness
            height: horizontalSide() ? root.dashThickness : root.dashLength
            radius: root.dashThickness / 2

            x: dashX()
            y: dashY()

            color: root.glowColor

            opacity: root.danger
                     ? 0.74 + root.dangerFlash * 0.24
                     : 0.42 + root.pulse * 0.34

            Rectangle {
                anchors.centerIn: parent

                width: parent.width + (horizontalSide() ? 88 : 28)
                height: parent.height + (horizontalSide() ? 28 : 88)

                radius: Math.max(width, height) / 2

                color: root.glowColor

                opacity: root.danger
                         ? 0.16 + root.dangerFlash * 0.18
                         : 0.050 + root.pulse * 0.12
            }

            Behavior on color {
                enabled: root.animationsEnabled

                ColorAnimation {
                    duration: 180
                }
            }
        }

        Rectangle {
            id: trailingSweep

            visible: root.animationsEnabled && !root.circular

            property real trailingProgress: {
                var p = root.progress - 0.055

                if (p < 0)
                    p += 1.0

                return p
            }

            width: trailingHorizontalSide() ? root.dashLength * 0.68 : root.dashThickness
            height: trailingHorizontalSide() ? root.dashThickness : root.dashLength * 0.68
            radius: root.dashThickness / 2

            x: trailingDashX()
            y: trailingDashY()

            color: root.glowColor

            opacity: root.danger
                     ? 0.28 + root.dangerFlash * 0.18
                     : 0.16 + root.pulse * 0.12
        }

        /*
            Constant premium glow rails.
        */
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            anchors.leftMargin: 54
            anchors.rightMargin: 54

            height: 2
            radius: 1

            color: root.glowColor

            opacity: root.danger
                     ? 0.18 + root.dangerFlash * 0.22
                     : 0.10 + root.ringPulse * 0.16
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            anchors.leftMargin: 54
            anchors.rightMargin: 54

            height: 2
            radius: 1

            color: root.glowColor

            opacity: root.danger
                     ? 0.18 + root.dangerFlash * 0.22
                     : 0.10 + root.ringPulse * 0.16
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left

            anchors.topMargin: 72
            anchors.bottomMargin: 72

            width: 2
            radius: 1

            color: root.glowColor

            opacity: root.danger
                     ? 0.12 + root.dangerFlash * 0.18
                     : 0.07 + root.ringPulse * 0.12
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right

            anchors.topMargin: 72
            anchors.bottomMargin: 72

            width: 2
            radius: 1

            color: root.glowColor

            opacity: root.danger
                     ? 0.12 + root.dangerFlash * 0.18
                     : 0.07 + root.ringPulse * 0.12
        }

        /*
            Premium corner brackets.
        */
        Item {
            anchors.fill: parent

            opacity: root.danger
                     ? 0.62 + root.dangerFlash * 0.34
                     : 0.28 + root.cornerPulse * 0.40

            CornerBracket {
                anchors.left: parent.left
                anchors.top: parent.top

                bracketColor: root.glowColor

                mirroredX: false
                mirroredY: false
            }

            CornerBracket {
                anchors.right: parent.right
                anchors.top: parent.top

                bracketColor: root.glowColor

                mirroredX: true
                mirroredY: false
            }

            CornerBracket {
                anchors.left: parent.left
                anchors.bottom: parent.bottom

                bracketColor: root.glowColor

                mirroredX: false
                mirroredY: true
            }

            CornerBracket {
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                bracketColor: root.glowColor

                mirroredX: true
                mirroredY: true
            }
        }

        /*
            Inner breathing glass stroke.
        */
        Rectangle {
            anchors.fill: parent
            anchors.margins: 16

            radius: Math.max(20, parent.width * 0.030)

            color: "transparent"

            border.width: 1
            border.color: root.glowColor

            opacity: root.danger
                     ? 0.12 + root.dangerFlash * 0.18
                     : 0.050 + root.ringPulse * 0.10
        }
    }

    /*
        ============================================================
                            CORNER BRACKET
        ============================================================
    */

    component CornerBracket: Item {
        id: bracket

        property color bracketColor: "#7df9ff"
        property bool mirroredX: false
        property bool mirroredY: false

        width: 96
        height: 96

        transform: [
            Scale {
                origin.x: bracket.width / 2
                origin.y: bracket.height / 2

                xScale: bracket.mirroredX ? -1 : 1
                yScale: bracket.mirroredY ? -1 : 1
            }
        ]

        Rectangle {
            x: 0
            y: 0

            width: 78
            height: 4
            radius: 2

            color: bracket.bracketColor
        }

        Rectangle {
            x: 0
            y: 0

            width: 4
            height: 78
            radius: 2

            color: bracket.bracketColor
        }

        Rectangle {
            x: 10
            y: 10

            width: 48
            height: 2
            radius: 1

            color: "#ffffff"
            opacity: 0.36
        }

        Rectangle {
            x: 10
            y: 10

            width: 2
            height: 48
            radius: 1

            color: "#ffffff"
            opacity: 0.28
        }
    }

    /*
        ============================================================
                        RECTANGULAR SWEEP HELPERS
        ============================================================
    */

    function safeWidth() {
        return Math.max(0, root.width)
    }

    function safeHeight() {
        return Math.max(0, root.height)
    }

    function sideFor(p) {
        if (p < 0.25)
            return 0

        if (p < 0.50)
            return 1

        if (p < 0.75)
            return 2

        return 3
    }

    function side() {
        return sideFor(progress)
    }

    function horizontalSide() {
        return side() === 0 || side() === 2
    }

    function dashXFor(p, length, thickness) {
        var w = safeWidth()
        var safeLength = Math.max(0, length)
        var safeThickness = Math.max(0, thickness)

        if (p < 0.25)
            return (p / 0.25) * Math.max(0, w - safeLength)

        if (p < 0.50)
            return Math.max(0, w - safeThickness)

        if (p < 0.75)
            return Math.max(0, w - safeLength) -
                   (((p - 0.50) / 0.25) * Math.max(0, w - safeLength))

        return 0
    }

    function dashYFor(p, length, thickness) {
        var h = safeHeight()
        var safeLength = Math.max(0, length)
        var safeThickness = Math.max(0, thickness)

        if (p < 0.25)
            return 0

        if (p < 0.50)
            return ((p - 0.25) / 0.25) * Math.max(0, h - safeLength)

        if (p < 0.75)
            return Math.max(0, h - safeThickness)

        return Math.max(0, h - safeLength) -
               (((p - 0.75) / 0.25) * Math.max(0, h - safeLength))
    }

    function dashX() {
        return dashXFor(root.progress, root.dashLength, root.dashThickness)
    }

    function dashY() {
        return dashYFor(root.progress, root.dashLength, root.dashThickness)
    }

    function trailingSide() {
        return sideFor(trailingSweep.trailingProgress)
    }

    function trailingHorizontalSide() {
        return trailingSide() === 0 || trailingSide() === 2
    }

    function trailingDashX() {
        return dashXFor(
                    trailingSweep.trailingProgress,
                    root.dashLength * 0.68,
                    root.dashThickness
                )
    }

    function trailingDashY() {
        return dashYFor(
                    trailingSweep.trailingProgress,
                    root.dashLength * 0.68,
                    root.dashThickness
                )
    }


}
