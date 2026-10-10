import QtQuick
import QtTest
import "../../qml/dashboard/v2" as Dashboard
import "../../qml/modals/system" as Modals
TestCase {
    name:"GeminiAuthoritativeSSID";when:windowShown;visible:true;width:1280;height:720
    QtObject {
        id:networkManager
        property string connectionState:"DISCONNECTED"
        property string connectedSsid:""
        property var availableNetworks:[]
        property var savedNetworks:[]
        property var diagnostics:[]
        property var offlineNetworkState:({})
        property bool available:true
        function refresh(){}
    }
    QtObject {id:staleMonitor;property string ssid:"Obsolete SSID";property bool wifiConnected:true}
    Dashboard.ModernDashboard{id:dashboard;anchors.fill:parent;networkBackend:networkManager;monitorBackend:staleMonitor;shellActive:false}
    Modals.NetworkManagerModal{id:modal;visible:false}
    function test_one_authoritative_source_updates_existing_header_binding(){
        var header=findChild(dashboard,"desktopWifiHeader")
        verify(header!==null)
        compare(header.primary,"Offline")
        networkManager.connectionState="CONNECTED"
        networkManager.connectedSsid="Prettypink"
        tryCompare(header,"primary","Prettypink")
        compare(modal.connectedSsid(),header.primary)
        staleMonitor.ssid="Another stale value"
        compare(header.primary,"Prettypink")
        networkManager.connectionState="DISCONNECTED"
        networkManager.connectedSsid=""
        tryCompare(header,"primary","Offline")
        networkManager.connectedSsid="Reconnected Network"
        networkManager.connectionState="CONNECTED"
        tryCompare(header,"primary","Reconnected Network")
        compare(modal.connectedSsid(),header.primary)
    }
}
