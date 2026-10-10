import QtQuick

DashboardCard {
    id: root
    property var storage: ({})
    property real percentage: Number(storage.usedPercent !== undefined ? storage.usedPercent : storage.percent || 0)
    readonly property bool available: storage.connected !== false && storage.mounted !== false
    property real animatedPercentage: 0
    property color barStart: "#087CFF"
    property color barEnd: "#19E9FF"
    onPercentageChanged: progressMotion.restart()
    NumberAnimation { id: progressMotion; target: root; property: "animatedPercentage"; to: Math.max(0,Math.min(100,root.percentage)); duration: 600; easing.type: Easing.OutCubic }
    Column {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        anchors.topMargin: 43
        anchors.bottomMargin: 15
        spacing: 10
        Row { width: parent.width; height: 55; spacing: 12
            Text { text: "▰"; color: root.barEnd; font.pixelSize: 36; anchors.verticalCenter: parent.verticalCenter }
            Column { anchors.verticalCenter: parent.verticalCenter
                Text { text: String(root.storage.label || root.storage.name || root.storage.device || "Storage"); color: root.available ? "#F5F8FF" : "#8E9AAF"; font.pixelSize: 15; elide: Text.ElideRight; width: 150 }
                Text { text: root.available ? String(root.storage.total || root.storage.capacity || "--") : "Unavailable"; color: root.available ? "white" : "#FF6A88"; font.pixelSize: 15 }
            }
        }
        Rectangle { width: parent.width; height: 18; radius: 9; color: "#06101E"; border.width: 1; border.color: root.barEnd
            Rectangle { width: Math.max(0,parent.width*root.animatedPercentage/100); height: parent.height; radius: parent.radius
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: root.barStart } GradientStop { position: 1; color: root.barEnd } }
            }
        }
        Row { width: parent.width
            Column { width: parent.width/2; Text { text: "Used"; color: "#B5C1D3"; font.pixelSize: 13 } Text { text: String(root.storage.used || "--"); color: "white"; font.pixelSize: 15 } }
            Column { width: parent.width/2; Text { anchors.right: parent.right; text: "Free"; color: "#B5C1D3"; font.pixelSize: 13 } Text { anchors.right: parent.right; text: String(root.storage.free || root.storage.available || "--"); color: "white"; font.pixelSize: 15 } }
        }
        Rectangle { width: parent.width; height: 1; color: "#203047" }
        Text { text: "File System  " + String(root.storage.fileSystem || root.storage.filesystem || "--"); color: "#D9E2F1"; font.pixelSize: 13 }
    }
}
