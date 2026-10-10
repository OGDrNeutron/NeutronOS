import QtQuick

Item {
    id: root
    property bool animationEnabled: visible
    property real systemActivity: 0
    property real phase: 0
    readonly property real activity: Math.max(0, Math.min(1, systemActivity / 100))

    // The atom body is deliberately stationary.  Only electrons advance.
    Timer {
        interval: 32
        repeat: true
        running: root.animationEnabled && root.visible
        onTriggered: root.phase = (root.phase + 1.25 + root.activity * 1.8) % 360
    }

    Repeater {
        model: 3
        delegate: Item {
            id: orbit
            required property int index
            anchors.centerIn: parent
            width: parent.width * (.92 - index * .09)
            height: parent.height * (.34 - index * .018)
            rotation: index * 60

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: index === 0 ? 2.2 : 1.6
                border.color: index === 0 ? "#35EDFF" : index === 1 ? "#B65DFF" : "#FF4F91"
                opacity: .60 + root.activity * .20
            }

            Item {
                id: electronCarrier
                anchors.fill: parent
                rotation: root.phase * (index === 0 ? .78 : index === 1 ? -1.03 : 1.25)
                Rectangle {
                    x: parent.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8 + root.activity * 3
                    height: width
                    radius: width / 2
                    color: orbit.index === 0 ? "#83FAFF" : orbit.index === 1 ? "#D989FF" : "#FF77B1"
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 3.2
                        height: width
                        radius: width / 2
                        color: parent.color
                        opacity: .16
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * (.20 + root.activity * .035)
        height: width
        radius: width / 2
        color: "#04101F"
        border.width: 3
        border.color: "#A7FAFF"
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * .66
            height: width
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "white" }
                GradientStop { position: .35; color: "#63EEFF" }
                GradientStop { position: 1; color: "#8B45FF" }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 2.5
            height: width
            radius: width / 2
            color: "#38E5FF"
            opacity: .12 + .12 * root.activity
        }
    }
}
