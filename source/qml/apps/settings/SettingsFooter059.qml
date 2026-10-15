import QtQuick
import QtQuick.Shapes
import "../../components/SecurityIndicator.js" as SecurityStatus

Item {
    id: root
    objectName: "SettingsFooter059"
    property var controllerBackend: null
    property var securityBackend: null
    property var networkBackend: null
    property var clockBackend: null
    property bool hostActive: true
    property real uiScale: 1
    property string contextText: "SECURE. INTELLIGENT. UNSTOPPABLE."
    property date localNow: new Date()
    readonly property int securityScore: SecurityStatus.score(securityBackend)
    readonly property string securityLabel: SecurityStatus.label(securityBackend)
    readonly property color securityColor: securityScore < 0 ? "#829ab0" : SecurityStatus.color(securityBackend)
    readonly property bool wifiConnected: !!networkBackend && networkBackend.connectionState === "CONNECTED"
    readonly property color wifiColor: !networkBackend ? "#829ab0" : !wifiConnected ? "#ff4057" : networkBackend.connectivity === 4 ? "#22ff88" : "#ffd45a"
    readonly property int battery: controllerBackend && controllerBackend.controllerConnected === true && controllerBackend.controllerBatteryAvailable === true && isFinite(Number(controllerBackend.controllerBatteryPercent)) && Number(controllerBackend.controllerBatteryPercent) >= 0 && Number(controllerBackend.controllerBatteryPercent) <= 100 ? Math.round(Number(controllerBackend.controllerBatteryPercent)) : -1
    height: 72 * uiScale
    Rectangle { anchors.fill: parent; color: "#f2081320" }
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeColor: "#00cfff"; strokeWidth: 1; fillColor: "#d9000711"
            startX: 0; startY: 1
            PathLine { x: 230 * root.uiScale; y: 1 }
            PathLine { x: 264 * root.uiScale; y: 30 * root.uiScale }
            PathLine { x: root.width * .32; y: 30 * root.uiScale }
            PathLine { x: root.width * .34; y: 40 * root.uiScale }
            PathLine { x: root.width * .72; y: 40 * root.uiScale }
            PathLine { x: root.width * .76; y: 1 }
            PathLine { x: root.width; y: 1 }
        }
    }
    Row {
        x: 26 * root.uiScale; anchors.verticalCenter: parent.verticalCenter; spacing: 9 * root.uiScale
        Item {
            width: 45 * root.uiScale; height: width; anchors.verticalCenter: parent.verticalCenter
            Image { id: atom; anchors.fill: parent; source: Qt.resolvedUrl("../../../themes/Default/atom.svg"); fillMode: Image.PreserveAspectFit; smooth: true }
            NumberAnimation on rotation { from: 0; to: 360; duration: 10000; loops: Animation.Infinite; running: root.visible && root.hostActive && atom.status === Image.Ready }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Neutron<font color='#ff4057'>OS</font>"; textFormat: Text.RichText; color: "#f4fbff"; font.pixelSize: 24 * root.uiScale; font.bold: true }
    }
    Text {
        objectName: "SettingsFooterContext"; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 11 * root.uiScale
        width: parent.width * .42; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        textFormat: Text.RichText
        text: root.contextText === "SECURE. INTELLIGENT. UNSTOPPABLE." ? "SECURE. INTELLIGENT. <font color='#ff4057'>UNSTOPPABLE.</font>" : root.contextText.replace(/&/g,"&amp;").replace(/</g,"&lt;")
        color: "#94ebff"; font.pixelSize: 11 * root.uiScale; font.letterSpacing: 3 * root.uiScale
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 28 * root.uiScale; anchors.verticalCenter: parent.verticalCenter; spacing: 18 * root.uiScale
        WifiSignal059 { objectName: "SettingsFooterWifi"; tint: root.wifiColor; anchors.verticalCenter: parent.verticalCenter; scale: root.uiScale }
        Item {
            objectName: "SettingsFooterSecurity"; width: 30 * root.uiScale; height: 32 * root.uiScale; anchors.verticalCenter: parent.verticalCenter
            Canvas {
                anchors.fill: parent
                property int score: root.securityScore
                onScoreChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var c=getContext("2d");c.clearRect(0,0,width,height);c.save();c.scale(width/30,height/32);c.strokeStyle=String(root.securityColor);c.lineWidth=2.2;c.lineJoin="round";c.lineCap="round"
                    c.beginPath()
                    if (root.securityLabel === "Secure" || score < 0) { c.moveTo(15,2);c.lineTo(27,6);c.lineTo(25,20);c.quadraticCurveTo(21,27,15,30);c.quadraticCurveTo(9,27,5,20);c.lineTo(3,6);c.closePath();c.stroke();c.beginPath();if(root.securityLabel === "Secure"){c.moveTo(9,15);c.lineTo(13,19);c.lineTo(21,10)}else{c.moveTo(10,16);c.lineTo(20,16)} }
                    else { c.moveTo(15,3);c.lineTo(29,28);c.lineTo(1,28);c.closePath();c.stroke();c.beginPath();c.moveTo(15,11);c.lineTo(15,19);c.moveTo(15,23);c.lineTo(15,24) }
                    c.stroke();c.restore()
                }
            }
        }
        Row {
            objectName: "SettingsFooterBattery"; spacing: 7 * root.uiScale; anchors.verticalCenter: parent.verticalCenter
            Image { width: 30*root.uiScale; height: 24*root.uiScale; anchors.verticalCenter: parent.verticalCenter; source: Qt.resolvedUrl("../../gemini/assets/Controller.png"); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
            Text { anchors.verticalCenter: parent.verticalCenter; text: root.battery >= 0 ? root.battery + "%" : "—%"; color: root.battery >= 0 ? "#dceaff" : "#829ab0"; font.pixelSize: 18 * root.uiScale }
            Rectangle {
                width: 44 * root.uiScale; height: 19 * root.uiScale; radius: 3; color: "transparent"; border.color: "#627880"; anchors.verticalCenter: parent.verticalCenter
                Row { x: 3 * root.uiScale; y: 3 * root.uiScale; spacing: root.uiScale
                    Repeater { model: 5; Rectangle { width: 7 * root.uiScale; height: 13 * root.uiScale; radius: 1; color: root.battery >= 0 && index < Math.ceil(root.battery / 20) ? "#22ff88" : "#294052" } }
                }
                Rectangle { anchors.left: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 3 * root.uiScale; height: 8 * root.uiScale; color: "#627880" }
            }
        }
        Rectangle { width: 1; height: 24 * root.uiScale; color: "#627880"; anchors.verticalCenter: parent.verticalCenter }
        Text { objectName: "SettingsFooterClock"; anchors.verticalCenter: parent.verticalCenter; text: root.clockBackend ? String(root.clockBackend.currentTimeText || "—:—") : Qt.formatTime(root.localNow,"h:mm AP"); color: "#dceaff"; font.pixelSize: 18 * root.uiScale }
    }
    Timer { interval: 1000; repeat: true; running: root.visible && root.hostActive && !root.clockBackend; onTriggered: root.localNow = new Date() }
}
