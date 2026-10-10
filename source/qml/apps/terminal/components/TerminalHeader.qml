import QtQuick 2.15
import "../../../components" as Shared

Shared.ReferenceAppHeader {
    id: root

    property string title: "NeutronOS"
    property string subtitle: "TERMINAL"
    property string modeLabel: "REGULAR"
    property string statusText: "Ready"
    property bool developerMode: false
    property bool ptyAlive: false
    property bool remoteRunning: false
    property int remoteClientCount: 0
    property url atomSource: ""
    property color accentColor: "#68D8FF"
    property color textColor: "#F3FCFF"

    appTitle: "Terminal"
    primaryStatus: "Secure"
    primaryTone: "success"
    secondaryStatus: remoteRunning
                     ? (remoteClientCount > 0
                        ? "Remote Connected: " + remoteClientCount
                        : "Remote On")
                     : ""
    secondaryTone: "success"
}
