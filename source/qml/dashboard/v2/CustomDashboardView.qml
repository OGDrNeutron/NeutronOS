import QtQuick

Item {
    id: root
    property var layoutBackend: null
    property var appsBackend: null
    property var monitorBackend: null
    property var storageBackend: null
    property var networkBackend: null
    property var securityBackend: null
    property var clockBackend: null
    property var activeUser: null
    property bool shellActive: false
    property bool controllerActive: false
    property string tabId: ""
    readonly property var tab: layoutBackend ? layoutBackend.customTab(tabId) : ({})
    readonly property bool appTab: String(tab.type || "widgets") === "app"
    signal appLaunchRequested(var appData)
    signal detailsRequested(string kind, var context)
    signal actionsRequested(string kind, var context)
    signal topBoundaryRequested()

    function runningEntry() {
        var entries = appsBackend && appsBackend.runningApps ? appsBackend.runningApps : []
        for (var i=0; i<entries.length; ++i)
            if (String(entries[i].appId || "") === String(tab.appId || "")) return entries[i]
        return null
    }
    function appRecord() {
        var apps = appsBackend && appsBackend.apps ? appsBackend.apps : []
        for (var i=0; i<apps.length; ++i)
            if (String(apps[i].id || "") === String(tab.appId || "")) return apps[i]
        return ({ id: tab.appId, name: tab.name, poster: tab.poster })
    }
    function handleControllerPressed(action) {
        if (!appTab && widgetView.item) return widgetView.item.handleControllerPressed(action)
        if (action === "up") { topBoundaryRequested(); return true }
        if (action === "primary") {
            var runtime = runningEntry()
            if (runtime && runtime.canFocus === true && appsBackend && appsBackend.focusRuntime)
                appsBackend.focusRuntime(String(runtime.runtimeId || ""))
            else appLaunchRequested(appRecord())
        } else if (action === "context") detailsRequested("application", {app: appRecord()})
        else if (action === "secondary") actionsRequested("application", {app: appRecord()})
        return true
    }

    Loader {
        id: widgetView
        anchors.fill: parent
        active: !root.appTab
        source: active ? "SystemOverviewView.qml" : ""
        onLoaded: {
            item.layoutBackend = root.layoutBackend
            item.monitorBackend = root.monitorBackend
            item.storageBackend = root.storageBackend
            item.networkBackend = root.networkBackend
            item.securityBackend = root.securityBackend
            item.clockBackend = root.clockBackend
            item.activeUser = root.activeUser
            item.shellActive = Qt.binding(function() { return root.shellActive })
            item.controllerActive = root.controllerActive
            item.tabId = root.tabId
            item.detailsRequested.connect(root.detailsRequested)
            item.actionsRequested.connect(root.actionsRequested)
            item.topBoundaryRequested.connect(root.topBoundaryRequested)
        }
    }

    onControllerActiveChanged: {
        if (widgetView.item)
            widgetView.item.controllerActive = root.controllerActive
    }

    Rectangle {
        anchors.fill: parent
        visible: root.appTab
        radius: 26
        color: "#E5071120"
        border.width: 3
        border.color: "#32DFFF"
        clip: true

        Image {
            anchors.fill: parent
            source: {
                var value=String(root.tab.poster || root.appRecord().poster || root.tab.appId || "")
                if (value.indexOf(":")>=0 || value.indexOf("/")>=0) return value
                return Qt.resolvedUrl("../../../themes/Default/apps/posters/"+value+".png")
            }
            fillMode: Image.PreserveAspectCrop
            opacity: .62
        }
        Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop{position:0;color:"#15000818"} GradientStop{position:1;color:"#E0060C17"} } }
        Column {
            anchors.centerIn: parent; spacing: 16
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(root.tab.name || root.tab.appId || "Application"); color:"white"; font.pixelSize:42; font.bold:true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.runningEntry() ? "RUNNING • X FOCUS EXISTING SESSION" : "NOT RUNNING • X OPEN"; color:root.runningEntry()?"#44F0A2":"#AFC2D8"; font.pixelSize:18; font.bold:true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text:"Dashboard keeps the shared header visible; NeutronOS reuses the authoritative runtime instead of creating a duplicate process."; color:"#B7CCE1"; font.pixelSize:15; width:760; wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter }
        }
    }
}
