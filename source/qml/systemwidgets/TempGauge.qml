import QtQuick 2.15

Item {
    id: root

    property real temperature: 0
    property real minTemp: 80
    property real maxTemp: 185

    width: 252
    height: 212

    readonly property real heat: safeHeat()
    readonly property bool animationsEnabled: visible && enabled
    readonly property bool unstableTemperature:
        root.safeTemperature() > 0 && root.heat >= 0.78

    property color neutronBlue: "#16DCFF"
    property color neutronRed: "#FF1C42"
    property color transitionCyan: "#7DF9FF"
    property color thermalPurple: "#BD4AFF"
    property color thermalRed: "#FF2434"

    property string activeWave: "none"

    readonly property bool purpleWaveActive: root.activeWave === "purple"
    readonly property bool redWaveActive: root.activeWave === "red"
    readonly property color statusColor:
        root.unstableTemperature ? root.thermalRed : root.transitionCyan

    readonly property int baseFrameDuration:
        root.unstableTemperature
        ? (root.heat >= 0.92 ? 29 : 34)
        : (root.heat >= 0.55 ? 40 : 47)

    readonly property url baseAtlasSource:
        Qt.resolvedUrl(
            "../../themes/Default/system/temp_helix_restored_dual_atlas.png"
        )

    readonly property url purpleWaveAtlasSource:
        Qt.resolvedUrl(
            "../../themes/Default/system/temp_helix_purple_wave_atlas_v2.png"
        )

    readonly property url redWaveAtlasSource:
        Qt.resolvedUrl(
            "../../themes/Default/system/temp_helix_red_warning_atlas_v2.png"
        )

    function safeHeat() {
        var temp = Number(root.temperature)
        var minT = Number(root.minTemp)
        var maxT = Number(root.maxTemp)

        if (isNaN(temp) || temp <= 0)
            return 0

        if (isNaN(minT))
            minT = 80
        if (isNaN(maxT))
            maxT = 185
        if (maxT <= minT)
            maxT = minT + 1

        return Math.max(0, Math.min(1, (temp - minT) / (maxT - minT)))
    }

    function safeTemperature() {
        var temp = Number(root.temperature)
        return isNaN(temp) ? 0 : temp
    }

    function tempStatus() {
        if (root.safeTemperature() <= 0)
            return "NO DATA"
        if (root.heat < 0.55)
            return "STABLE"
        if (root.heat < 0.78)
            return "WARMING"
        if (root.heat < 0.92)
            return "HOT"
        return "CRITICAL"
    }

    function stopWave() {
        waveStopTimer.stop()
        root.activeWave = "none"
    }

    function startWave(mode) {
        if (!root.animationsEnabled)
            return

        root.stopWave()
        root.activeWave = mode

        Qt.callLater(function() {
            if (root.activeWave !== mode)
                return

            try {
                if (mode === "red")
                    redWaveHelix.jumpTo("red")
                else
                    purpleWaveHelix.jumpTo("purple")
            } catch (error) {
            }

            /*
                A 32-frame pass at 40 ms is 1280 ms. Stop at 1240 ms so the
                SpriteSequence can never wrap and begin a partial second pass.
            */
            waveStopTimer.restart()
        })
    }

    function scheduleDecorativeWave() {
        decorativeWaveTimer.stop()
        if (!root.animationsEnabled || root.unstableTemperature)
            return

        decorativeWaveTimer.interval = 4800 + Math.floor(Math.random() * 6201)
        decorativeWaveTimer.restart()
    }

    onUnstableTemperatureChanged: {
        root.stopWave()
        decorativeWaveTimer.stop()

        if (root.unstableTemperature) {
            /* Show the first warning immediately, then every three seconds. */
            root.startWave("red")
            unstableWaveTimer.restart()
        } else {
            unstableWaveTimer.stop()
            root.scheduleDecorativeWave()
        }
    }

    onAnimationsEnabledChanged: {
        if (!root.animationsEnabled) {
            root.stopWave()
            decorativeWaveTimer.stop()
            unstableWaveTimer.stop()
        } else if (root.unstableTemperature) {
            root.startWave("red")
            unstableWaveTimer.restart()
        } else {
            root.scheduleDecorativeWave()
        }
    }

    Component.onCompleted: {
        if (root.unstableTemperature) {
            root.startWave("red")
            unstableWaveTimer.restart()
        } else {
            root.scheduleDecorativeWave()
        }
    }

    Timer {
        id: decorativeWaveTimer
        interval: 7000
        repeat: false
        onTriggered: {
            if (root.animationsEnabled && !root.unstableTemperature)
                root.startWave("purple")
            root.scheduleDecorativeWave()
        }
    }

    Timer {
        id: unstableWaveTimer
        interval: 3000
        repeat: true
        running: false
        onTriggered: {
            if (root.animationsEnabled && root.unstableTemperature)
                root.startWave("red")
        }
    }

    Timer {
        id: waveStopTimer
        interval: 1240
        repeat: false
        onTriggered: root.activeWave = "none"
    }

    Text {
        id: tempText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        text: root.safeTemperature() > 0
              ? root.safeTemperature().toFixed(0) + "°"
              : "--"
        color: "white"
        font.pixelSize: 38
        font.bold: true
    }

    Text {
        id: tempLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tempText.bottom
        anchors.topMargin: -2

        text: "CORE TEMP"
        color: root.statusColor
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 2.2
        opacity: 0.92

        Behavior on color {
            ColorAnimation { duration: 180 }
        }
    }

    Item {
        id: helixStage
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tempLabel.bottom
        anchors.topMargin: -1

        width: 192
        height: 130
        clip: true

        /*
            The original large-dot helix geometry is restored. One strand
            remains vivid neutron blue and the opposing strand is vivid red.
            Stable and unstable states change playback speed only, so the
            design returns without decoding a second permanent base atlas.
        */
        SpriteSequence {
            id: baseHelix
            anchors.fill: parent
            z: 2

            running: root.animationsEnabled
            interpolate: true

            sprites: [
                Sprite {
                    name: "base"
                    source: root.baseAtlasSource
                    frameCount: 72
                    frameWidth: 234
                    frameHeight: 159
                    frameDuration: root.baseFrameDuration
                }
            ]
        }

        SpriteSequence {
            id: purpleWaveHelix
            anchors.fill: parent
            z: 3

            visible: root.purpleWaveActive
            running: root.animationsEnabled && visible
            interpolate: true

            sprites: [
                Sprite {
                    name: "purple"
                    source: root.purpleWaveAtlasSource
                    frameCount: 32
                    frameWidth: 192
                    frameHeight: 130
                    frameDuration: 40
                }
            ]
        }

        SpriteSequence {
            id: redWaveHelix
            anchors.fill: parent
            z: 4

            visible: root.redWaveActive
            running: root.animationsEnabled && visible
            interpolate: true

            sprites: [
                Sprite {
                    name: "red"
                    source: root.redWaveAtlasSource
                    frameCount: 32
                    frameWidth: 192
                    frameHeight: 130
                    frameDuration: 40
                }
            ]
        }
    }

    Rectangle {
        id: statusStrip
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2

        width: Math.min(parent.width - 18, statusText.width + 42)
        height: 29
        radius: 15
        color: "#120616EE"
        border.width: 1
        border.color: root.statusColor

        Behavior on border.color {
            ColorAnimation { duration: 180 }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            width: 9
            height: 9
            radius: 5
            color: root.redWaveActive
                   ? root.thermalRed
                   : (root.purpleWaveActive
                      ? root.thermalPurple
                      : root.statusColor)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

        Text {
            id: statusText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 7
            text: root.tempStatus()
            color: root.redWaveActive
                   ? "#FF6B72"
                   : (root.purpleWaveActive
                      ? "#D7A0FF"
                      : root.statusColor)
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.4
        }
    }
}
