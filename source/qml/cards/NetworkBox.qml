import QtQuick 2.15
import "../common"

GlassCard {
    id: root

    /*
        ============================================================
                            NETWORK BOX
        ============================================================

        Used by SystemOverview for:
            - Network SSID / network name
            - Local IP
            - Tailscale IP
            - Upload speed
            - Download speed

        Preserved from original:
            - title
            - ip
            - tailscaleIp
            - upload
            - download
            - cyan network accent
            - upload/download strip

        Next-gen updates:
            - Title pinned to top.
            - Main network/IP value centered.
            - Tailscale IP shown clearly when available.
            - Upload/download row pinned near bottom.
            - Safe fallbacks when backend values are missing.
            - Optional SSID support.
            - Offline/warning color state.
            - Optional compact mode.
            - Animations pause when hidden.
            - No mouse assumptions.
    */

    property string title: ""
    property string ssid: ""
    property string ip: ""
    property string localIp: ip
    property string tailscaleIp: ""
    property string upload: ""
    property string download: ""

    property bool compact: false
    property bool showTailscale: true
    property bool showTraffic: true
    property bool animationsEnabled: visible && enabled

    property string offlineText: "Offline"
    property string unknownText: "--"

    property color onlineColor: "#22ff88"
    property color offlineColor: "#ff3040"
    property color warningColor: "#f5c542"
    property color downloadColor: "#66b3ff"
    property color uploadColor: "#22ff88"
    property color tailscaleColor: "#9fd8ff"
    property color mutedColor: "#8aa6c8"

    property real pulse: 0.55

    accent: "#22d3ee"

    implicitWidth: compact ? 170 : 210
    implicitHeight: compact ? 112 : 138

    /*
        Safe backend reference.
        This allows the card to either receive values from SystemOverview
        or pull directly from systemMonitor when used standalone.
    */
    property var systemBackend: {
        try {
            if (typeof systemMonitor !== "undefined" && systemMonitor)
                return systemMonitor
        } catch (e) {
        }

        return null
    }

    /*
        ============================================================
                            VALUE HELPERS
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

    function backendValue(keys, fallbackValue) {
        var backend = root.systemBackend

        if (!backend)
            return fallbackValue

        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]

            try {
                var value = cleanText(backend[key])

                if (value.length > 0)
                    return value
            } catch (e) {
            }
        }

        return fallbackValue
    }

    function shownTitle() {
        var t = cleanText(title)

        if (t.length > 0)
            return t

        return "NETWORK"
    }

    function shownSsid() {
        var direct = cleanText(ssid)

        if (direct.length > 0 && direct !== unknownText)
            return direct

        var fromBackend = backendValue([
                                           "ssid",
                                           "networkSsid",
                                           "wifiSsid",
                                           "networkName"
                                       ], "")

        if (fromBackend.length > 0 &&
                fromBackend !== "wlan0" &&
                fromBackend !== unknownText) {
            return fromBackend
        }

        return ""
    }

    function shownLocalIp() {
        var direct = cleanText(localIp)

        if (direct.length <= 0)
            direct = cleanText(ip)

        if (direct.length > 0 &&
                direct !== unknownText &&
                direct !== "0.0.0.0") {
            return direct
        }

        var fromBackend = backendValue([
                                           "localIp",
                                           "ip",
                                           "ipv4",
                                           "networkIp"
                                       ], "")

        if (fromBackend.length > 0 &&
                fromBackend !== unknownText &&
                fromBackend !== "0.0.0.0") {
            return fromBackend
        }

        return ""
    }

    function shownTailscaleIp() {
        var direct = cleanText(tailscaleIp)

        if (direct.length > 0 &&
                direct !== unknownText &&
                direct !== "0.0.0.0") {
            return direct
        }

        var fromBackend = backendValue([
                                           "tailscaleIp",
                                           "tailnetIp",
                                           "tsIp"
                                       ], "")

        if (fromBackend.length > 0 &&
                fromBackend !== unknownText &&
                fromBackend !== "0.0.0.0") {
            return fromBackend
        }

        return ""
    }

    function shownUpload() {
        var direct = cleanText(upload)

        if (direct.length > 0 && direct !== unknownText)
            return direct

        var fromBackend = backendValue([
                                           "upload",
                                           "uploadSpeed",
                                           "txSpeed",
                                           "networkUpload"
                                       ], "")

        if (fromBackend.length > 0)
            return fromBackend

        return "0 KB/s"
    }

    function shownDownload() {
        var direct = cleanText(download)

        if (direct.length > 0 && direct !== unknownText)
            return direct

        var fromBackend = backendValue([
                                           "download",
                                           "downloadSpeed",
                                           "rxSpeed",
                                           "networkDownload"
                                       ], "")

        if (fromBackend.length > 0)
            return fromBackend

        return "0 KB/s"
    }

    function isOnline() {
        return shownLocalIp().length > 0 || shownTailscaleIp().length > 0
    }

    function mainNetworkText() {
        var network = shownSsid()

        if (network.length > 0)
            return network

        var local = shownLocalIp()

        if (local.length > 0)
            return local

        return offlineText
    }

    function subNetworkText() {
        var network = shownSsid()
        var local = shownLocalIp()

        if (network.length > 0 && local.length > 0)
            return local

        if (shownTailscaleIp().length > 0)
            return "Tailscale ready"

        return isOnline() ? "Connected" : "No network link"
    }

    function titleColor() {
        if (!isOnline())
            return offlineColor

        if (root.focused)
            return "#7df9ff"

        return accent
    }

    function statusColor() {
        if (!isOnline())
            return offlineColor

        return onlineColor
    }

    function trafficAvailable() {
        return shownUpload().length > 0 || shownDownload().length > 0
    }

    SequentialAnimation on pulse {
        running: root.animationsEnabled && (root.focused || !root.isOnline())
        loops: Animation.Infinite

        NumberAnimation {
            from: 0.40
            to: 1.0
            duration: root.isOnline() ? 1700 : 720
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            from: 1.0
            to: 0.40
            duration: root.isOnline() ? 1700 : 720
            easing.type: Easing.InOutSine
        }
    }

    /*
        ============================================================
                                TITLE
        ============================================================
    */

    Text {
        id: titleText

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: compact ? 8 : 10

        width: parent.width - 18

        text: root.shownTitle()

        color: root.titleColor()

        font.pixelSize: compact ? 12 : 13
        font.bold: true
        font.letterSpacing: 0.9

        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1

        opacity: root.focused ? 1.0 : 0.90
    }

    /*
        ============================================================
                            CENTER NETWORK VALUE
        ============================================================
    */

    Column {
        id: centerContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: compact ? -2 : -4
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        spacing: compact ? 4 : 5

        Row {
            anchors.horizontalCenter: parent.horizontalCenter

            width: parent.width
            height: compact ? 21 : 24
            spacing: 8

            Rectangle {
                width: compact ? 9 : 10
                height: width
                radius: width / 2

                anchors.verticalCenter: parent.verticalCenter

                color: root.statusColor()
                opacity: root.isOnline() ? 0.76 + root.pulse * 0.24
                                         : 0.62 + root.pulse * 0.30
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                width: parent.width - 20

                text: root.mainNetworkText()

                color: root.isOnline() ? "white" : "#ffd1d1"

                font.pixelSize: compact ? 15 : 17
                font.bold: true
                font.letterSpacing: 0.2

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1

                style: Text.Outline
                styleColor: "#99000000"
            }
        }

        Text {
            width: parent.width

            text: root.subNetworkText()

            color: root.isOnline() ? root.mutedColor : "#ff9a9a"

            font.pixelSize: compact ? 10 : 11
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1

            opacity: 0.94
        }

        Rectangle {
            visible: root.showTailscale && root.shownTailscaleIp().length > 0

            anchors.horizontalCenter: parent.horizontalCenter

            width: Math.min(parent.width, tailscaleText.width + 22)
            height: compact ? 22 : 24
            radius: height / 2

            color: "#071426CC"

            border.width: 1
            border.color: "#2A79B788"

            Row {
                id: tailscaleText

                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text: "TS"

                    color: root.tailscaleColor

                    font.pixelSize: compact ? 9 : 10
                    font.bold: true
                    font.letterSpacing: 0.9
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.shownTailscaleIp()

                    color: "#d9f4ff"

                    font.pixelSize: compact ? 10 : 11
                    font.bold: true
                }
            }
        }
    }

    /*
        ============================================================
                            TRAFFIC STRIP
        ============================================================
    */

    Rectangle {
        id: trafficPanel

        visible: root.showTraffic

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: compact ? 12 : 14
        anchors.rightMargin: compact ? 12 : 14
        anchors.bottomMargin: compact ? 9 : 11

        height: compact ? 24 : 28
        radius: height / 2

        color: "#02060D99"

        border.width: 1
        border.color: root.focused ? "#2A79B7AA" : "#223355"

        opacity: root.isOnline() ? 0.96 : 0.64

        Row {
            anchors.centerIn: parent
            spacing: compact ? 11 : 14

            Row {
                spacing: 4

                Text {
                    text: "↑"

                    color: root.uploadColor

                    font.pixelSize: compact ? 11 : 12
                    font.bold: true
                }

                Text {
                    text: root.shownUpload()

                    color: "#b7ffd5"

                    font.pixelSize: compact ? 10 : 11
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: 1
                height: compact ? 12 : 14
                color: "#335577"
                opacity: 0.7
            }

            Row {
                spacing: 4

                Text {
                    text: "↓"

                    color: root.downloadColor

                    font.pixelSize: compact ? 11 : 12
                    font.bold: true
                }

                Text {
                    text: root.shownDownload()

                    color: "#cfe8ff"

                    font.pixelSize: compact ? 10 : 11
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }
    }

    /*
        ============================================================
                            OFFLINE / FOCUS RING
        ============================================================
    */

    Rectangle {
        visible: root.focused || !root.isOnline()

        anchors.fill: parent
        anchors.margins: root.focused ? -1 : 0

        radius: root.radius + 1
        color: "transparent"

        border.width: root.focused ? 2 : 1
        border.color: root.focused ? "#7df9ff" : root.offlineColor

        opacity: root.focused ? 0.22 + root.pulse * 0.18
                              : 0.16 + root.pulse * 0.22
    }
}