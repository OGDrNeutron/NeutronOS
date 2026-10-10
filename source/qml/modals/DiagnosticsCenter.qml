import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    enabled: visible
    focus: visible
    z: 12000

    property var backend: (typeof diagnosticsManager !== "undefined") ? diagnosticsManager : null
    property int selectedIndex: 0
    property bool detailsVisible: false
    signal closed()

    function openCenter() {
        selectedIndex = 0
        detailsVisible = false
        visible = true
        forceActiveFocus()
        if (backend && !backend.busy) backend.runFullDiagnostics()
    }
    function closeCenter() { visible = false; detailsVisible = false; closed() }
    function count() { return backend && backend.checks ? backend.checks.length : 0 }
    function selected() { return count() > 0 ? backend.checks[Math.max(0, Math.min(count()-1, selectedIndex))] : null }
    function move(delta) {
        if (count() < 1) return
        selectedIndex = (selectedIndex + delta + count()) % count()
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
        detailsVisible = false
    }
    function normalize(action) {
        var a=String(action||"").toLowerCase()
        if(a==="dpad_up")return "up";if(a==="dpad_down")return "down"
        if(a==="x"||a==="cross"||a==="primary")return "primary"
        if(a==="o"||a==="circle"||a==="cancel")return "cancel"
        if(a==="triangle"||a==="context")return "context"
        if(a==="square"||a==="secondary")return "secondary"
        if(a==="start"||a==="options"||a==="system")return "system"
        return a
    }
    function handleControllerPressed(action) {
        if(!visible)return false
        var a=normalize(action)
        if(a==="up"){move(-1);return true} if(a==="down"){move(1);return true}
        if(a==="primary"||a==="context"){detailsVisible=!detailsVisible;return true}
        if(a==="secondary"){var item=selected();if(item&&backend)backend.rerunCheck(String(item.id));return true}
        if(a==="system"){if(backend)backend.runFullDiagnostics();return true}
        if(a==="cancel"){if(detailsVisible)detailsVisible=false;else closeCenter();return true}
        return true
    }
    function handleControllerReleased(action) { return visible }
    function statusColor(status) {
        var s=String(status||"").toLowerCase(); return s==="pass"?"#74FF50":s==="fail"?"#FF445B":"#FACC15"
    }
    function statusText(status) { var s=String(status||"").toLowerCase();return s==="pass"?"PASS":s==="fail"?"FAIL":"WARNING" }

    Rectangle { anchors.fill: parent; color: "#02060D" }
    Rectangle { anchors.fill: parent; color: "#071426"; opacity:.93 }

    Column {
        // Derive the inset from the containing surface. Using this Column's
        // own anchored width/height made margins depend on the geometry that
        // those same margins determine, producing a binding loop.
        anchors.fill: parent
        anchors.margins: Math.max(34, Math.min(root.width, root.height) * .045)
        spacing: 18
        Row {
            width: parent.width; height: 92; spacing: 24
            Column { width: parent.width-330; spacing: 7
                Text { text:"SYSTEM DIAGNOSTICS";color:"#7DF9FF";font.pixelSize:18;font.bold:true;font.letterSpacing:3 }
                Text { text:"Overall Health  " + (root.backend?String(root.backend.overallHealth):"UNAVAILABLE");color:root.statusColor(root.backend?root.backend.overallHealth:"warn");font.pixelSize:36;font.bold:true }
                Text { text:root.backend?String(root.backend.systemSummary):"Diagnostics backend unavailable";color:"#91A9C5";font.pixelSize:15 }
            }
            Rectangle { width:290;height:76;radius:20;color:"#06101F";border.width:2;border.color:root.backend&&root.backend.busy?"#FACC15":"#1D3958"
                Text { anchors.centerIn:parent;text:root.backend&&root.backend.busy?"RUNNING  "+root.backend.progress+"%":"LAST RUN  "+(root.backend?root.backend.lastRun:"Never");color:"white";font.pixelSize:15;font.bold:true }
            }
        }
        Rectangle { width:parent.width;height:1;color:"#1D3958" }
        ListView {
            id:list;width:parent.width;height:parent.height-210;clip:true;spacing:12
            model:root.backend?root.backend.checks:[];currentIndex:root.selectedIndex
            delegate: Rectangle {
                width:list.width;height:root.detailsVisible&&index===root.selectedIndex?190:92;radius:24
                color:index===root.selectedIndex?"#12335A":"#06101F";border.width:index===root.selectedIndex?3:1;border.color:index===root.selectedIndex?"#4DA6FF":"#1D3958"
                Behavior on height { NumberAnimation { duration:160 } }
                Rectangle { x:18;y:18;width:56;height:56;radius:28;color:"#071426";border.width:2;border.color:root.statusColor(modelData.status)
                    Text { anchors.centerIn:parent;text:root.statusText(modelData.status)==="PASS"?"✓":root.statusText(modelData.status)==="FAIL"?"!":"△";color:root.statusColor(modelData.status);font.pixelSize:28;font.bold:true }
                }
                Column { x:94;y:16;width:parent.width-270;spacing:5
                    Text { text:String(modelData.title||"Unknown test");color:"white";font.pixelSize:21;font.bold:true }
                    Text { text:String(modelData.value||"Unavailable");color:root.statusColor(modelData.status);font.pixelSize:15;font.bold:true }
                    Text { visible:root.detailsVisible&&index===root.selectedIndex;width:parent.width;text:String(modelData.detail||"No details available")+"\nEVIDENCE  "+String(modelData.evidence||"Unavailable")+(modelData.hasSuggestedAction?"\nSUGGESTED  "+String(modelData.suggestedAction):"");color:"#C8D5DF";font.pixelSize:13;wrapMode:Text.WordWrap;maximumLineCount:5;elide:Text.ElideRight }
                }
                Text { anchors.right:parent.right;anchors.rightMargin:24;anchors.verticalCenter:parent.verticalCenter;text:root.statusText(modelData.status);color:root.statusColor(modelData.status);font.pixelSize:17;font.bold:true }
            }
        }
        Text { width:parent.width;text:"X DETAILS  •  △ SUGGESTED ACTION  •  □ RERUN SELECTED  •  START RERUN ALL  •  O CLOSE";color:"#91A9C5";font.pixelSize:14;font.bold:true;horizontalAlignment:Text.AlignHCenter }
    }

    Keys.onPressed:function(event){event.accepted=root.handleControllerPressed(event.text||event.key)}
}
