import QtQuick

// Presentation-free client for the existing exact-USB-identity / BlueZ bridge.
Item {
    id: session
    visible: false
    property bool active: false
    property bool registrationEnabled: true
    property var controller: null
    property var state: ({})
    property string transport: "unknown"
    property int statusGeneration:0
    property bool polling: false
    property bool registering: false
    property string requestIssue: ""
    readonly property string eventName: {
        var match=/(?:^|\/)event([0-9]{1,5})$/.exec(controller?String(controller.controllerDevicePath||""):"")
        return match?"event"+match[1]:""
    }
    readonly property bool verified: !!state.address && state.paired===true && state.trusted===true && state.connected===true && state.usb_present!==true
    readonly property string phase: {
        if(verified)return "connected"
        var current=String(state.phase||"")
        if(current&&current!=="idle")return current
        return registering?"registering":transport==="usb"?"wired":"idle"
    }
    readonly property string connectionLabel: !controller||controller.controllerConnected!==true?"Disconnected":transport==="bluetooth"?"Bluetooth":transport==="usb"?"Wired":"Verifying connection"
    readonly property string instructions: verified?"Bluetooth connection verified. Press X to continue.":phase==="waiting_disconnect"?"Unplug the USB cable, then hold SHARE + PS / Create + PS until the controller flashes.":phase==="scanning"?"Scanning for this controller's saved hardware address…":["bonding","trusting","connecting"].indexOf(phase)>=0?String(state.message||"Pairing and verifying the Bluetooth connection…"):phase==="error"?String(state.message||"Bluetooth registration failed. Reconnect USB and retry."):registering?"Reading the wired controller's identity…":requestIssue.length?requestIssue:"Connect your controller with a USB data cable, then select Pair Controller."
    function applyRegistration(value) {
        if(!value||typeof value!=="object")return
        state=value
        if(verified)requestIssue=""
    }
    function refresh() {
        if(!active||polling)return
        polling=true
        var generation=statusGeneration
        var device=eventName
        var status=new XMLHttpRequest()
        status.timeout=4000
        status.onreadystatechange=function(){
            if(status.readyState!==4)return
            if(generation!==statusGeneration||device!==eventName)return
            polling=false
            if(!active)return
            if(status.status===200){try{var v=JSON.parse(status.responseText);transport=v.transport==="usb"?"usb":v.transport==="bluetooth"?"bluetooth":"unknown"}catch(e){transport="unknown"}}
            else transport="unknown"
        }
        status.open("GET","http://127.0.0.1:48173/status?device="+encodeURIComponent(eventName),true);status.send()
        if(!registrationEnabled)return
        var registration=new XMLHttpRequest()
        registration.timeout=4000
        registration.onreadystatechange=function(){if(registration.readyState===4&&active&&registration.status===200){try{applyRegistration(JSON.parse(registration.responseText))}catch(e){}}}
        registration.open("GET","http://127.0.0.1:48173/registration",true);registration.send()
    }
    function begin() {
        if(registering||["waiting_disconnect","scanning","bonding","trusting","connecting"].indexOf(phase)>=0)return
        if(!eventName.length||transport!=="usb"){requestIssue="Connect a supported controller using a USB data cable first.";refresh();return}
        registering=true;requestIssue=""
        var xhr=new XMLHttpRequest();xhr.timeout=23000
        xhr.onreadystatechange=function(){
            if(xhr.readyState!==4)return
            registering=false
            if(!active)return
            if(xhr.status===200){try{applyRegistration(JSON.parse(xhr.responseText))}catch(e){requestIssue="Registration response unavailable; checking live BlueZ state…"}}
            else if(!verified)requestIssue="Registration request was interrupted; checking live Bluetooth state. Reconnect USB to retry if it remains disconnected."
            // An HTTP timeout cannot override a subsequently verified connection.
            refresh()
        }
        xhr.open("POST","http://127.0.0.1:48173/register",true)
        xhr.setRequestHeader("Content-Type","application/json")
        xhr.setRequestHeader("X-Neutron-Controller","register-usb-v1")
        xhr.send(JSON.stringify({event:eventName}))
    }
    function invalidateConnectionStatus(){statusGeneration++;transport="unknown";polling=false;if(active)refresh()}
    Connections {
        target:session.controller;ignoreUnknownSignals:true
        function onControllerDevicePathChanged(){session.invalidateConnectionStatus()}
        function onControllerConnectedChanged(){session.invalidateConnectionStatus()}
    }
    onActiveChanged: invalidateConnectionStatus()
    Timer{interval:1500;repeat:true;running:session.active;onTriggered:session.refresh()}
}
