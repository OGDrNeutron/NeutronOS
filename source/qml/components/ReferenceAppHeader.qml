import QtQuick 2.15

Rectangle {
    id: root

    property string appTitle: "NeutronOS"
    property string primaryStatus: "Secure"
    property string primaryTone: "success"
    property string secondaryStatus: ""
    property string secondaryTone: "success"
    property bool attention: false
    property bool menuFocused: false
    // NEUTRONOS_REFERENCE_HEADER_SECURITY_SCORE_V1
    property var securityBackend: (typeof securityCoreManager !== "undefined") ? securityCoreManager : null
    readonly property int securityScoreValue: securityBackend && securityBackend.daemonOnline===true && securityBackend.securityScore!==undefined ? Math.max(0,Math.min(100,Math.round(Number(securityBackend.securityScore)))) : -1
    readonly property bool primaryIsSecurityState: {
        var s=String(primaryStatus||"").toLowerCase()
        return s==="secure" || s==="attention" || s==="unsecure" || s==="weak" || s==="weak protection"
    }
    readonly property string effectivePrimaryStatus: primaryIsSecurityState && securityScoreValue>=0 ? (securityScoreValue>=80?"Secure":securityScoreValue>=55?"Weak":"Attention") : primaryStatus
    readonly property string effectivePrimaryTone: primaryIsSecurityState && securityScoreValue>=0 ? (securityScoreValue>=80?"success":securityScoreValue>=55?"warning":"danger") : primaryTone
    // Kept for source compatibility. The reference chrome intentionally uses the
    // same fixed dimensions as the approved Security app instead of scaling up/down.
    property real uiScale: 1.0

    signal menuRequested()

    function toneColor(tone) {
        if (tone === "danger") return "#FF4D63"
        if (tone === "warning") return "#FFD166"
        if (tone === "info") return "#33A7FF"
        return "#42E69C"
    }

    function toneFill(tone) {
        if (tone === "danger") return "#2A1015"
        if (tone === "warning") return "#2A2410"
        if (tone === "info") return "#0A1F2A"
        return "#0A241A"
    }

    height: 54
    color: "#030810F2"
    border.width: 0
    radius: 5
    clip: true

    // Match Security exactly: no top stroke, one-pixel side and bottom edges.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "#21303A"
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#21303A"
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#21303A"
    }


    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9

        Rectangle {
            height: 34
            width: primaryText.implicitWidth + 28
            radius: 17
            color: root.toneFill(root.effectivePrimaryTone)
            border.width: 1
            border.color: root.toneColor(root.effectivePrimaryTone)

            Text {
                id: primaryText
                anchors.centerIn: parent
                text: root.effectivePrimaryStatus.toUpperCase()
                color: root.toneColor(root.effectivePrimaryTone)
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 0.8
            }
        }

        Rectangle {
            visible: root.secondaryStatus.length > 0
            height: 34
            width: secondaryText.implicitWidth + 28
            radius: 17
            color: root.toneFill(root.secondaryTone)
            border.width: 1
            border.color: root.toneColor(root.secondaryTone)

            Text {
                id: secondaryText
                anchors.centerIn: parent
                text: root.secondaryStatus.toUpperCase()
                color: root.toneColor(root.secondaryTone)
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 0.8
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.appTitle.toUpperCase()
        color: "#33A7FF"
        font.pixelSize: 28
        font.bold: true
        font.letterSpacing: 1.6
    }

    Rectangle {
        id: menuButton
        objectName: "referenceAppThreeDotButton"
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        height: 38
        radius: 19
        color: root.menuFocused ? "#0A241A" : "transparent"
        border.width: root.menuFocused ? 2 : 0
        border.color: "#42E69C"

        Row {
            anchors.centerIn: parent
            spacing: 10
            Repeater {
                model: ["#1AA7FF", "#6E63FF", "#E432FF"]
                Rectangle { width: 11; height: 11; radius: 6; color: modelData }
            }
        }

        MouseArea { anchors.fill: parent; onClicked: root.menuRequested() }
    }
}
