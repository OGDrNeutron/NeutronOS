import QtQuick 2.15

Item {
    id: root
    property var activeUser
    property var layout: []
    property bool sectionFocused: false
    property int selectedSystem: 0
    property int armedIndex: -1
    property string currentTime: ""
    property string currentDate: ""
    property string currentTimezoneLabel: ""

    signal cardClicked(string cardType, int index)
    signal modalRequested(string modalId, var context)

    readonly property var monitor: (typeof systemMonitor !== "undefined") ? systemMonitor : null
    readonly property var network: (typeof networkManager !== "undefined") ? networkManager : null
    readonly property var controller: (typeof controllerManager !== "undefined") ? controllerManager : null

    function count() { return layout ? layout.length : 0 }
    function moveSelection(delta) {
        if (count() <= 0) return
        selectedSystem = Math.max(0, Math.min(count() - 1, selectedSystem + delta))
    }
    function disarmSelected() {
        if (armedIndex < 0) return false
        armedIndex = -1
        return true
    }
    function idAt(index) { return index >= 0 && index < count() ? String(layout[index]) : "" }
    function modalId(id) {
        if (id === "memory") return "memory"
        if (id === "active") return "activeApp"
        if (id === "uptime") return "controllerSettings"
        return id
    }
    function activateSelected() {
        var id = idAt(selectedSystem)
        if (!id) return
        modalRequested(modalId(id), contextFor(id))
    }
    function titleFor(id) {
        var map = { cpu:"CPU", memory:"MEMORY", storage:"STORAGE", active:"ACTIVE APPS", temperature:"TEMPERATURE", network:"NETWORK", uptime:"CONTROLLER", clock:"CLOCK", user:"USER" }
        return map[id] || id.toUpperCase()
    }
    function valueFor(id) {
        try {
            if (id === "cpu") return String(monitor.cpu || monitor.cpuPercent + "%")
            if (id === "memory") return String(monitor.ram || monitor.ramPercent + "%")
            if (id === "storage") return String(monitor.bootStorage || monitor.storage || "--")
            if (id === "active") return String(monitor.activeAppCount || 0) + " RUNNING"
            if (id === "temperature") return String(monitor.temperature || monitor.cpuTemperature || "--")
            if (id === "network") return String(network.connectedSsid || monitor.ssid || "OFFLINE")
            if (id === "uptime") return controller && controller.connected ? String(controller.controllerName || "CONNECTED") : String(monitor.uptime || "--")
            if (id === "clock") return currentTime || "--:--"
            if (id === "user") return String(activeUser && (activeUser.displayName || activeUser.name || activeUser.username) || "USER")
        } catch (error) {}
        return "--"
    }
    function detailFor(id) {
        try {
            if (id === "cpu") return String(monitor.governor || "NORMAL")
            if (id === "memory") return String(monitor.ramUsed || "USED")
            if (id === "storage") return "BOOT / MEDIA"
            if (id === "active") return "FULL-SCREEN SERVICES"
            if (id === "temperature") return String(monitor.thermalStatus || "NO THROTTLE")
            if (id === "network") return String(network.localIp || monitor.localIp || "")
            if (id === "uptime") return String(monitor.uptime || "UPTIME")
            if (id === "clock") return currentDate
            if (id === "user") return "PROFILE & LAYOUT"
        } catch (error) {}
        return ""
    }
    function contextFor(id) {
        if (id === "user") return { user: activeUser, username: activeUser && (activeUser.username || activeUser.name) || "default" }
        return ({})
    }

    Row {
        anchors.fill: parent
        spacing: 10
        Repeater {
            model: root.layout || []
            Rectangle {
                width: Math.max(100, (root.width - Math.max(0, root.count() - 1) * 10) / Math.max(1, root.count()))
                height: root.height
                radius: 20
                color: index === root.selectedSystem && root.sectionFocused ? "#173963" : "#081426"
                border.width: index === root.selectedSystem && root.sectionFocused ? 3 : 1
                border.color: root.armedIndex === index ? "#FF3040" : (index === root.selectedSystem && root.sectionFocused ? "#7DF9FF" : "#29435F")

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 5
                    Text { width: parent.width; text: root.titleFor(String(modelData)); color: "#8AA6C8"; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.valueFor(String(modelData)); color: "#F4FBFF"; font.pixelSize: 20; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.detailFor(String(modelData)); color: "#7DF9FF"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                }
            }
        }
    }
}
