import QtQuick

Item {
    id:root
    property bool opened:false
    property string mode:"details"
    property string kind:""
    property var contextData:({})
    property var cachedAppDetails:({})
    property var cachedAppCardInfo:({})
    property int runtimeTick:0
    property var monitorBackend:null
    property var appBackend:null
    property var layoutBackend:null
    property var storageBackend:null
    property var securityBackend:null
    property var notificationBackend:null
    property int selectedIndex:0
    property int confirmationStage:0
    property int sizeStage:0
    property int pinStage:0
    property string pendingSizeFamily:""
    signal closed()
    signal appLaunchRequested(var appData)
    signal appMoveRequested(var appData)
    signal appPinned(string appId)
    signal widgetMoveRequested(string widgetId)
    visible:opened; enabled:opened; z:500

    Timer {
        interval: 1000
        repeat: true
        running: root.opened && root.mode==="details" && root.kind==="application" && root.appRunning()
        onTriggered: root.runtimeTick++
    }

    function app(){return contextData&&contextData.app?contextData.app:null}
    function appAsset(value,kind){
        var text=String(value||"").trim()
        if(!text)return ""
        if(text.indexOf(":")>=0||text.indexOf("/")>=0)return text
        return Qt.resolvedUrl("../../../themes/Default/apps/"+kind+"/"+text+".png")
    }
    function appIconSource(){
        var a=app()||({})
        return appAsset(a.iconSource||a.icon,"icons")
    }
    function appDetails(){
        var cached=cachedAppDetails||({})
        if(Object.keys(cached).length>0)return cached
        return app()||({})
    }
    function appCardInfo(){
        var cached=cachedAppCardInfo||({})
        if(Object.keys(cached).length>0)return cached
        if(appBackend&&typeof appBackend.appCardInfo==="function")return appBackend.appCardInfo(app()||({}))||({})
        return ({})
    }
    function appOwnershipText(){return String(appCardInfo().typeText||appDetails().ownershipText||"Unknown")}
    function appLastOpenedText(){return String(appCardInfo().lastOpenedText||appDetails().lastUsedText||"Never opened")}
    function appServiceRunning(){var a=app()||({});return a.serviceRunning===true}
    function appUiRunning(){var a=app()||({});return a.appRunning===true||a.uiRunning===true||a.backgroundRunning===true}
    function appHasService(){var a=app()||({});return String(a.service||a.docker||"").trim().length>0}
    function appPermissions(){
        var a=app()||({}), details=appDetails()||({}), out=[]
        var source=a.permissions||details.permissions||[]
        if(source&&source.length!==undefined){
            for(var i=0;i<source.length;++i){
                var value=String(source[i]||"").trim()
                if(value.length)out.push(value)
            }
        }
        if(!out.length&&String(details.permissionsText||"").length&&String(details.permissionsText)!=="No declared permissions")
            out=String(details.permissionsText).split(",")
        return out
    }
    function appRunning(){
        return appUiRunning()
    }
    function appStatusText(){return appRunning()?"RUNNING":"STOPPED"}
    function appStatusTone(){return appRunning()?"#43F0A0":"#FF6577"}
    function appSizeText(){var d=appDetails()||({});return String(d.installText||d.storageText||"Unknown")}
    function appVersionText(){var a=app()||({}),d=appDetails()||({});return String(d.version||a.version||"Unknown")}
    function appRuntimeLabel(){var d=appDetails()||({});return String(d.runtimeLabel||(appRunning()?"Runtime":"Last ran"))}
    function humanDuration(seconds){
        var total=Math.max(0,Math.floor(Number(seconds||0)))
        var days=Math.floor(total/86400);total%=86400
        var hours=Math.floor(total/3600);total%=3600
        var minutes=Math.floor(total/60);var secs=total%60
        if(days>0)return days+"d "+hours+"h "+minutes+"m"
        if(hours>0)return hours+"h "+minutes+"m"
        if(minutes>0)return minutes+"m "+secs+"s"
        return secs+"s"
    }
    function appRuntimeText(){
        var a=app()||({}),d=appDetails()||({});runtimeTick
        if(appRunning()&&String(d.runtimeStartUtc||"").length){
            var start=Date.parse(String(d.runtimeStartUtc))
            if(!isNaN(start))return humanDuration((Date.now()-start)/1000)
        }
        return String(d.runtimeText||(appRunning()?a.sessionText:d.lastUsedText)||"Unknown")
    }
    function widget(){return contextData&&contextData.widget?contextData.widget:null}
    function securitySummaryRows(){
        var rows=[]
        var events=securityBackend&&securityBackend.events?securityBackend.events:[]
        for(var i=0;i<events.length;++i){
            var event=events[i]||({})
            if(event.acknowledged===true)continue
            var category=String(event.category||"security").toLowerCase()
            var eventId=String(event.id||event.eventId||"")
            var integrity=category==="integrity"
            var detail=String(event.message||event.evidence||"Review this security event")
            if(integrity&&String(event.path||"").length)
                detail=String(event.change||"changed").toUpperCase()+"  •  "+String(event.path)
            rows.push({
                id:eventId,
                eventId:eventId,
                type:integrity?"INTEGRITY CHECK":String(category||"SECURITY").toUpperCase(),
                title:String(event.title||event.message||"Security event"),
                detail:detail,
                severity:Number(event.severity||1),
                timestamp:String(event.timestamp||event.time||""),
                flagged:event.flagged===true,
                integrity:integrity
            })
        }
        return rows
    }
    function summaryIntegrityCount(){
        if(!securityBackend)return 0
        if(securityBackend.stats&&securityBackend.stats.integrityChanges!==undefined)
            return Number(securityBackend.stats.integrityChanges||0)
        return securityBackend.integrityChanges?securityBackend.integrityChanges.length:0
    }
    function summaryActiveCount(){
        if(securityBackend&&securityBackend.stats&&securityBackend.stats.activeThreats!==undefined)
            return Number(securityBackend.stats.activeThreats||0)
        return securitySummaryRows().length
    }
    function clampSummarySelection(){
        var count=securitySummaryRows().length
        selectedIndex=Math.max(0,Math.min(selectedIndex,Math.max(0,count-1)))
        if(summaryList&&count>0)summaryList.positionViewAtIndex(selectedIndex,ListView.Contain)
    }
    function acknowledgeSummaryItem(){
        var rows=securitySummaryRows()
        if(!rows.length||!securityBackend)return
        selectedIndex=Math.max(0,Math.min(selectedIndex,rows.length-1))
        var item=rows[selectedIndex]
        if(item.eventId&&typeof securityBackend.acknowledgeEvent==="function")
            securityBackend.acknowledgeEvent(String(item.eventId))
        Qt.callLater(clampSummarySelection)
    }
    function toggleSummaryFlag(){
        var rows=securitySummaryRows()
        if(!rows.length||!securityBackend)return
        selectedIndex=Math.max(0,Math.min(selectedIndex,rows.length-1))
        var item=rows[selectedIndex]
        if(item.eventId&&typeof securityBackend.setEventFlagged==="function")
            securityBackend.setEventFlagged(String(item.eventId),item.flagged!==true)
    }
    function acknowledgeAllSummary(){
        if(securityBackend&&typeof securityBackend.acknowledgeAllEvents==="function")
            securityBackend.acknowledgeAllEvents()
        selectedIndex=0
    }
    function threatIncident(){
        var incident=contextData&&contextData.incident?contextData.incident:({})
        var eventId=String(incident.eventId||incident.id||"").replace(/^event:/,"")
        var events=securityBackend&&securityBackend.events?securityBackend.events:[]
        for(var i=0;i<events.length;++i){
            var event=events[i]||({})
            var id=String(event.id||event.eventId||"")
            if(eventId.length&&id===eventId)return event
        }
        return incident
    }
    function threatEventId(){
        var incident=contextData&&contextData.incident?contextData.incident:({})
        var id=String(incident.eventId||"")
        if(id.length)return id
        var raw=String(incident.id||"")
        return raw.indexOf("event:")===0?raw.substring(6):raw
    }
    function threatFlagged(){
        var event=threatIncident()
        return event&&event.flagged===true
    }
    function threatSeverity(){
        var event=threatIncident(), raw=event?event.severity||event.level||"warning":"warning"
        var text=String(raw).toLowerCase()
        if(text==="critical"||Number(raw)>=4)return 4
        if(text==="high"||Number(raw)===3)return 3
        if(text==="medium"||text==="warning"||Number(raw)===2)return 2
        return 1
    }
    function acknowledgeThreat(){
        if(!securityBackend)return
        var id=threatEventId()
        if(id.length&&typeof securityBackend.acknowledgeEvent==="function"){
            securityBackend.acknowledgeEvent(id)
            closeModal()
            return
        }
        var incident=contextData&&contextData.incident?contextData.incident:({})
        if(incident.notificationId&&notificationBackend&&typeof notificationBackend.dismiss==="function"){
            notificationBackend.dismiss(String(incident.notificationId))
            closeModal()
        }
    }
    function toggleThreatFlag(){
        if(!securityBackend)return
        var id=threatEventId()
        if(id.length&&typeof securityBackend.setEventFlagged==="function")
            securityBackend.setEventFlagged(id,!threatFlagged())
    }
    function pinSlotLabel(slot){
        if(!appBackend||typeof appBackend.pinnedAppAt!=="function")return "Slot "+String(slot)
        var existing=appBackend.pinnedAppAt(slot)
        var name=existing&&String(existing.id||"").length>0?String(existing.name||existing.displayName||existing.id):"Empty"
        return "Slot "+String(slot)+"  •  "+name
    }
    function sizeVariants(){return widget()&&layoutBackend&&layoutBackend.availableSizeVariants?layoutBackend.availableSizeVariants(String(widget().id)):[]}
    function familyRows(){
        var rows=[],families=[{id:"small",label:"Small"},{id:"medium",label:"Medium"},{id:"large",label:"Large"}],variants=sizeVariants()
        for(var i=0;i<families.length;++i){var available=false;for(var j=0;j<variants.length;++j)if(String(variants[j].family)===families[i].id&&variants[j].available!==false)available=true;rows.push({id:families[i].id,label:families[i].label,available:available})}
        return rows
    }
    function variantRows(){var out=[],variants=sizeVariants();for(var i=0;i<variants.length;++i)if(String(variants[i].family)===pendingSizeFamily)out.push(variants[i]);return out}
    function actionRows(){
        if(kind==="application"){
            var a=app(), rows=[]; if(!a)return rows
            if(contextData.dockerStopWarning===true)
                return [{id:"stop",label:"Turn Docker Off",description:"Stops Docker and may interrupt dependent containers.",glyph:"■",danger:true}]
            if(pinStage===1)
                return [{id:"pin-1",label:pinSlotLabel(1),description:"Assign this app to launcher slot 1.",glyph:"1",danger:false},
                        {id:"pin-2",label:pinSlotLabel(2),description:"Assign this app to launcher slot 2.",glyph:"2",danger:false},
                        {id:"pin-3",label:pinSlotLabel(3),description:"Assign this app to launcher slot 3.",glyph:"3",danger:false}]
            rows.push({id:"open",label:"Open App",description:"Launch or focus the application interface.",glyph:"▶",danger:false})
            if(root.appUiRunning())
                rows.push({id:"close",label:"Close App",description:"Close the application interface without stopping its service.",glyph:"×",danger:false})
            if(root.appHasService()){
                if(root.appServiceRunning()){
                    rows.push({id:"restart",label:"Restart Service",description:"Restart the managed backend service/container.",glyph:"↻",danger:false})
                    rows.push({id:"stop",label:"Stop Service",description:"Stop the managed backend service/container.",glyph:"■",danger:true})
                } else {
                    rows.push({id:"start",label:"Start Service",description:"Start the managed backend service/container.",glyph:"●",danger:false})
                }
            }
            var pinned=appBackend&&typeof appBackend.pinnedSlotForApp==="function"?Number(appBackend.pinnedSlotForApp(String(a.id||""))):0
            rows.push({id:"pin",label:pinned>0?"Change Pin  •  Slot "+String(pinned):"Pin App",description:"Choose a launcher slot for this app.",glyph:"◆",danger:false})
            if(pinned>0)rows.push({id:"unpin",label:"Unpin App",description:"Remove this app from its launcher slot.",glyph:"◇",danger:false})
            return rows
        }
        if(widget()){
            if(sizeStage===1)return familyRows()
            if(sizeStage===2)return variantRows()
            var widgetRows=[{id:"move",label:"Move / Reposition"}]
            if(String(widget().id)!=="temperature")widgetRows.push({id:"size",label:"Size"})
            widgetRows.push({id:"disable",label:"Disable widget"});return widgetRows
        }
        return []
    }
    function actionPrompt(){
        if(confirmationStage)
            return contextData.dockerStopWarning===true
                    ? "Docker is currently running. Turning it off can stop Jellyfin, qBittorrent, and every active container. Press X again to confirm."
                    : "Press X again to confirm the dangerous action."
        if(contextData.dockerStopWarning===true)
            return "Docker is currently running. Turn Docker off? Active containers and dependent services may be interrupted."
        if(kind==="application"&&pinStage===1)
            return "Choose launcher slot 1, 2, or 3. If the slot is already pinned, this app replaces it."
        return "Choose a valid action for the current state."
    }
    function openModal(newMode,newKind,data){
        mode=newMode;kind=newKind;contextData=data||({});cachedAppDetails=({});cachedAppCardInfo=({});selectedIndex=0;confirmationStage=0;sizeStage=0;pinStage=0;pendingSizeFamily=""
        if(newKind==="application"&&appBackend){
            if(typeof appBackend.appManagementDetails==="function")cachedAppDetails=appBackend.appManagementDetails(app())||({})
            if(typeof appBackend.appCardInfo==="function")cachedAppCardInfo=appBackend.appCardInfo(app())||({})
        }
        opened=true;forceActiveFocus()
    }
    function closeModal(){opened=false;cachedAppDetails=({});cachedAppCardInfo=({});confirmationStage=0;sizeStage=0;pinStage=0;pendingSizeFamily="";closed()}
    function commitVariant(variant){
        if(!variant||variant.available===false)return false
        var system=String(contextData.tabId||"system")==="system"
        return system?layoutBackend.setWidgetSize(String(widget().id),String(variant.id)):layoutBackend.setTabWidgetSize(String(contextData.tabId),String(widget().id),String(variant.id))
    }
    function execute(){
        var rows=actionRows();if(selectedIndex<0||selectedIndex>=rows.length)return
        var item=rows[selectedIndex]
        if(item.danger&&confirmationStage===0){confirmationStage=1;return}
        if(kind==="application"){
            var a=app()
            if(pinStage===1){
                var slot=Number(String(item.id).split("-")[1]||0)
                if(appBackend&&typeof appBackend.pinApp==="function"&&slot>=1&&slot<=3){
                    if(appBackend.pinApp(String(a.id||""),slot)){
                        appPinned(String(a.id||""))
                        closeModal()
                    }
                }
                return
            }
            if(item.id==="open")appLaunchRequested(a)
            else if(item.id==="pin"){pinStage=1;selectedIndex=0;return}
            else if(item.id==="unpin"){
                if(appBackend&&typeof appBackend.unpinApp==="function"&&appBackend.unpinApp(String(a.id||"")))
                    appPinned(String(a.id||""))
            }
            else if(item.id==="move"){closeModal();appMoveRequested(a);return}
            else if(appBackend&&appBackend.executeAppAction)appBackend.executeAppAction(a,item.id)
        } else if(widget()&&layoutBackend){
            if(sizeStage===1){
                if(item.available===false)return
                pendingSizeFamily=String(item.id)
                if(pendingSizeFamily==="small"){
                    var variants=sizeVariants();for(var v=0;v<variants.length;++v)if(String(variants[v].id)==="small-square"&&commitVariant(variants[v])){closeModal();return}
                    return
                }
                sizeStage=2;selectedIndex=0;return
            }
            if(sizeStage===2){if(commitVariant(item))closeModal();return}
            if(item.id==="move"){
                var movingId=String(widget().id)
                closeModal()
                widgetMoveRequested(movingId)
                return
            }
            else if(item.id==="size"){sizeStage=1;selectedIndex=0;return}
            else if(item.id==="move-right")layoutBackend.moveWidget(String(widget().id),1)
            else if(item.id==="disable"){
                if(String(contextData.tabId||"system")==="system")layoutBackend.setWidgetEnabled(String(widget().id),false)
                else layoutBackend.setTabWidgetEnabled(String(contextData.tabId),String(widget().id),false)
            }
            else {
                if(String(contextData.tabId||"system")==="system")layoutBackend.setWidgetSize(String(widget().id),item.id)
                else layoutBackend.setTabWidgetSize(String(contextData.tabId),String(widget().id),item.id)
            }
        }
        closeModal()
    }
    function handleControllerPressed(action){
        if(mode==="security-summary"){
            if(action==="cancel"){closeModal();return true}
            var rows=securitySummaryRows()
            if(action==="up"){selectedIndex=Math.max(0,selectedIndex-1);clampSummarySelection()}
            else if(action==="down"){selectedIndex=Math.min(Math.max(0,rows.length-1),selectedIndex+1);clampSummarySelection()}
            else if(action==="primary")acknowledgeSummaryItem()
            else if(action==="secondary")toggleSummaryFlag()
            else if(action==="r3")acknowledgeAllSummary()
            return true
        }
        if(mode==="security-threat"){
            if(action==="cancel"){closeModal();return true}
            if(action==="primary")acknowledgeThreat()
            else if(action==="secondary")toggleThreatFlag()
            return true
        }
        if(action==="cancel"){
            if(pinStage===1){pinStage=0;selectedIndex=0;return true}
            if(sizeStage===2){sizeStage=1;pendingSizeFamily="";selectedIndex=0;return true}
            if(sizeStage===1){sizeStage=0;selectedIndex=0;return true}
            closeModal();return true
        }
        if(mode==="actions"){
            if(action==="up")selectedIndex=Math.max(0,selectedIndex-1)
            else if(action==="down")selectedIndex=Math.min(Math.max(0,actionRows().length-1),selectedIndex+1)
            else if(action==="primary")execute()
        }
        return true
    }

    Rectangle{anchors.fill:parent;color:"#C9000309"}
    Rectangle{anchors.centerIn:parent;width:Math.min(parent.width*.78,1280);height:Math.min(parent.height*.78,800);radius:32;color:"#071321";border.width:2;border.color:mode==="actions"?"#C55CFF":"#27DFFF"
        Item {
            visible: root.mode==="details" && root.kind==="application"
            anchors.fill: parent
            anchors.margins: 28

            Row {
                anchors.fill: parent
                spacing: 22

                Rectangle {
                    width: 330
                    height: parent.height
                    radius: 24
                    color: "#091827"
                    border.width: 1.5
                    border.color: "#28506A"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 14

                        Item {
                            width: parent.width
                            height: 170
                            Image {
                                id: appDetailIcon
                                anchors.centerIn: parent
                                width: 154
                                height: 154
                                source: root.appIconSource()
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: root.appIconSource().length===0 || appDetailIcon.status===Image.Error
                                text: "▦"
                                color: "#5BDFFF"
                                font.pixelSize: 72
                                font.bold: true
                            }
                        }

                        Text {
                            width: parent.width
                            text: String((root.app()||({})).name||(root.app()||({})).displayName||(root.app()||({})).id||"Application")
                            color: "white"
                            font.pixelSize: 27
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: ownershipDetail.implicitWidth + 30
                            height: 34
                            radius: 12
                            color: "#182B4056"
                            border.width: 1
                            border.color: root.appOwnershipText()==="App Store"?"#A95BFF":root.appOwnershipText()==="System"?"#38DFFF":"#FF5E91"
                            Text {
                                id: ownershipDetail
                                anchors.centerIn: parent
                                text: root.appOwnershipText().toUpperCase()
                                color: root.appOwnershipText()==="App Store"?"#DBB1FF":root.appOwnershipText()==="System"?"#83EFFF":"#FF93B5"
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: .8
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: "#29495F" }

                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text:"CURRENT STATE"; color:"#7792A9"; font.pixelSize:11; font.bold:true; font.letterSpacing:1.0 }
                            Row {
                                spacing: 8
                                Rectangle {
                                    visible: root.appUiRunning()
                                    width: 126; height: 31; radius: 10
                                    color: "#D3154629"; border.width:1; border.color:"#72EE78"
                                    Text { anchors.centerIn:parent; text:"APP RUNNING"; color:"#72EE78"; font.pixelSize:10; font.bold:true }
                                }
                                Rectangle {
                                    visible: root.appServiceRunning()
                                    width: 144; height: 31; radius: 10
                                    color: "#D3154629"; border.width:1; border.color:"#72EE78"
                                    Text { anchors.centerIn:parent; text:"SERVICE RUNNING"; color:"#72EE78"; font.pixelSize:10; font.bold:true }
                                }
                                Text {
                                    visible: !root.appUiRunning()&&!root.appServiceRunning()
                                    text:"IDLE"; color:"#7890A5"; font.pixelSize:12; font.bold:true
                                }
                            }
                        }

                        Item { width:1; height:Math.max(0,parent.height-y-36) }
                        Text { width:parent.width; text:"O  CLOSE"; color:"#41DFFF"; font.pixelSize:13; font.bold:true; horizontalAlignment:Text.AlignHCenter }
                    }
                }

                Column {
                    width: parent.width - 352
                    height: parent.height
                    spacing: 15

                    Row {
                        width: parent.width
                        height: 96
                        spacing: 12
                        Repeater {
                            model: [
                                {label:"INSTALLED SIZE",value:root.appSizeText(),tone:"#5BDFFF"},
                                {label:"VERSION",value:root.appVersionText(),tone:"#C36BFF"},
                                {label:"LAST OPENED",value:root.appLastOpenedText(),tone:"#72EE78"}
                            ]
                            Rectangle {
                                required property var modelData
                                width:(parent.width-24)/3; height:parent.height; radius:16
                                color:"#0C2032"; border.width:1; border.color:"#2D5068"
                                Rectangle { anchors.left:parent.left; anchors.top:parent.top; anchors.bottom:parent.bottom; width:3; radius:2; color:modelData.tone }
                                Column { anchors.fill:parent; anchors.margins:15; spacing:7
                                    Text { text:modelData.label; color:"#7894AB"; font.pixelSize:10; font.bold:true; font.letterSpacing:.8 }
                                    Text { width:parent.width; text:modelData.value; color:"#F5FBFF"; font.pixelSize:17; font.bold:true; elide:Text.ElideRight }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 136
                        radius: 18
                        color: "#0A1D2E"
                        border.width: 1
                        border.color: "#294B63"
                        Column {
                            anchors.fill: parent
                            anchors.margins:18
                            spacing:8
                            Text { text:"APPLICATION PROFILE"; color:"#5BDFFF"; font.pixelSize:11; font.bold:true; font.letterSpacing:1.0 }
                            Text { width:parent.width; text:String((root.app()||({})).description||(root.app()||({})).subtitle||"No description supplied."); color:"#D7E4EF"; font.pixelSize:13; wrapMode:Text.WordWrap; maximumLineCount:3; elide:Text.ElideRight }
                            Row {
                                spacing:20
                                Text { text:"Category  "+String((root.app()||({})).category||"Apps"); color:"#9FB4C8"; font.pixelSize:11 }
                                Text { text:"Runtime  "+root.appRuntimeText(); color:"#9FB4C8"; font.pixelSize:11 }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 188
                        radius: 18
                        color: "#091A29"
                        border.width: 1
                        border.color: "#29485F"
                        Column {
                            anchors.fill:parent
                            anchors.margins:18
                            spacing:11
                            Text { text:"PERMISSIONS"; color:"#5BDFFF"; font.pixelSize:11; font.bold:true; font.letterSpacing:1.0 }
                            Flow {
                                width:parent.width
                                height:118
                                spacing:8
                                Repeater {
                                    model: root.appPermissions().length?root.appPermissions():["No special permissions declared"]
                                    Rectangle {
                                        required property var modelData
                                        height:32
                                        width:Math.min(260,Math.max(108,permissionText.implicitWidth+24))
                                        radius:11
                                        color:"#10283D"
                                        border.width:1
                                        border.color:"#365D78"
                                        Text { id:permissionText; anchors.centerIn:parent; text:String(modelData).trim(); color:"#DCEBFA"; font.pixelSize:11; font.bold:true }
                                    }
                                }
                            }
                        }
                    }

                    Text { width:parent.width; text:"Triangle  DETAILS     X  OPEN     Square  ACTIONS"; color:"#7F9AB0"; font.pixelSize:11; font.bold:true; horizontalAlignment:Text.AlignHCenter }
                }
            }
        }

        Item {
            visible: root.mode==="actions" && root.kind==="application"
            anchors.fill: parent
            anchors.margins: 28

            Column {
                anchors.fill: parent
                spacing: 16

                Row {
                    width: parent.width
                    height: 92
                    spacing: 18

                    Image {
                        width: 84
                        height:84
                        source: root.appIconSource()
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache:true
                    }
                    Column {
                        width: parent.width - 220
                        anchors.verticalCenter: parent.verticalCenter
                        spacing:5
                        Text { width:parent.width; text:String((root.app()||({})).name||(root.app()||({})).id||"Application"); color:"white"; font.pixelSize:27; font.bold:true; elide:Text.ElideRight }
                        Row {
                            spacing:8
                            Rectangle {
                                width:ownershipAction.implicitWidth+22
                                height:28
                                radius:9
                                color:"#19294155"
                                border.width:1
                                border.color:root.appOwnershipText()==="App Store"?"#A95BFF":root.appOwnershipText()==="System"?"#38DFFF":"#FF5E91"
                                Text { id:ownershipAction; anchors.centerIn:parent; text:root.appOwnershipText().toUpperCase(); color:"#D7E9F6"; font.pixelSize:10; font.bold:true }
                            }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:root.appSizeText()+"  •  "+root.appLastOpenedText(); color:"#8EA8BD"; font.pixelSize:11 }
                        }
                    }
                    Text { anchors.verticalCenter:parent.verticalCenter; text:"APP ACTIONS"; color:"#D876FF"; font.pixelSize:14; font.bold:true; font.letterSpacing:1.2 }
                }

                Rectangle { width:parent.width; height:1; color:"#304A60" }

                Text { width:parent.width; text:root.actionPrompt(); color:root.confirmationStage?"#FF7184":"#AFC4DA"; font.pixelSize:13; wrapMode:Text.WordWrap }

                ListView {
                    id: appActionList
                    width: parent.width
                    height: parent.height - 185
                    model: root.actionRows()
                    spacing: 9
                    clip: true
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: parent.width
                        height: 68
                        radius: 15
                        opacity: modelData.available===false?.42:1
                        color: root.selectedIndex===index&&modelData.available!==false ? (modelData.danger?"#3B1824":"#142F47") : "#0B1B2A"
                        border.width: root.selectedIndex===index?2:1
                        border.color: modelData.available===false?"#4B5665":modelData.danger?"#FF536C":root.selectedIndex===index?"#42DFFF":"#29485F"

                        Rectangle {
                            anchors.left:parent.left
                            anchors.leftMargin:12
                            anchors.verticalCenter:parent.verticalCenter
                            width:42
                            height:42
                            radius:12
                            color:modelData.danger?"#34131D":"#102B40"
                            border.width:1
                            border.color:modelData.danger?"#D8475C":"#37617D"
                            Text { anchors.centerIn:parent; text:String(modelData.glyph||"•"); color:modelData.danger?"#FF7184":"#69E7FF"; font.pixelSize:18; font.bold:true }
                        }
                        Column {
                            anchors.left:parent.left
                            anchors.leftMargin:68
                            anchors.right:parent.right
                            anchors.rightMargin:18
                            anchors.verticalCenter:parent.verticalCenter
                            spacing:3
                            Text { width:parent.width; text:String(modelData.label)+(modelData.available===false?"  •  UNAVAILABLE":""); color:modelData.available===false?"#758395":modelData.danger?"#FF8293":"#F4FAFF"; font.pixelSize:15; font.bold:true; elide:Text.ElideRight }
                            Text { width:parent.width; text:String(modelData.description||""); color:"#879FB3"; font.pixelSize:11; elide:Text.ElideRight }
                        }
                    }
                }

                Text { width:parent.width; text:"D-PAD  CHOOSE     X  EXECUTE     O  CANCEL"; color:"#D876FF"; font.pixelSize:12; font.bold:true; horizontalAlignment:Text.AlignHCenter }
            }
        }

        Column{visible:root.mode!=="security-summary"&&root.mode!=="security-threat"&&!(root.kind==="application"&&(root.mode==="details"||root.mode==="actions"));anchors.fill:parent;anchors.margins:30;spacing:14
            Text{width:parent.width;text:(mode==="actions"?"ACTIONS • ":"DETAILS • ")+root.kind.toUpperCase();color:"white";font.pixelSize:28;font.bold:true}
            Text{width:parent.width;text:root.mode==="details"?root.detailsText():root.actionPrompt();color:root.confirmationStage?"#FF6577":"#AFC4DA";font.pixelSize:14;wrapMode:Text.WordWrap}
            ListView{visible:root.mode==="actions";width:parent.width;height:parent.height-120;model:root.actionRows();spacing:8
                delegate:Rectangle{required property int index;required property var modelData;width:parent.width;height:62;radius:13;opacity:modelData.available===false?.42:1;color:root.selectedIndex===index&&modelData.available!==false?"#173B59":"#0A1A2A";border.width:root.selectedIndex===index?2:1;border.color:modelData.available===false?"#4B5665":modelData.danger?"#FF4A63":root.selectedIndex===index?"#36DFFF":"#27415B";Text{anchors.centerIn:parent;text:String(modelData.label)+(modelData.available===false?"  •  UNAVAILABLE":"");color:modelData.available===false?"#758395":modelData.danger?"#FF7184":"white";font.pixelSize:16;font.bold:true}}
            }
            Text{width:parent.width;text:root.mode==="actions"?"D-PAD  CHOOSE     X  EXECUTE     O  CANCEL":"O  CLOSE";color:"#41DFFF";font.pixelSize:13;font.bold:true;horizontalAlignment:Text.AlignHCenter}
        }
        Column {
            visible:root.mode==="security-summary"
            anchors.fill:parent
            anchors.margins:30
            spacing:12
            Text { width:parent.width; text:"SECURITY SUMMARY"; color:"white"; font.pixelSize:28; font.bold:true }
            Row {
                width:parent.width
                height:30
                spacing:18
                Text { text:"ACTIVE THREATS  "+String(root.summaryActiveCount()); color:root.summaryActiveCount()>0?"#FF6577":"#43F0A0"; font.pixelSize:13; font.bold:true }
                Text { text:"INTEGRITY CHANGES  "+String(root.summaryIntegrityCount()); color:root.summaryIntegrityCount()>0?"#F7D85B":"#43F0A0"; font.pixelSize:13; font.bold:true }
                Text { text:root.securityBackend?String(root.securityBackend.threatLabel||"DEFCON --"):"SECURITY UNAVAILABLE"; color:"#5BDFFF"; font.pixelSize:13; font.bold:true }
            }
            Rectangle { width:parent.width; height:1; color:"#2B526D" }
            ListView {
                id:summaryList
                width:parent.width
                height:parent.height-140
                clip:true
                spacing:8
                model:root.securitySummaryRows()
                currentIndex:root.selectedIndex
                delegate:Rectangle {
                    required property int index
                    required property var modelData
                    width:summaryList.width
                    height:76
                    radius:12
                    color:root.selectedIndex===index?"#173B59":"#091927"
                    border.width:root.selectedIndex===index?2:1
                    border.color:modelData.flagged?"#F7D85B":(Number(modelData.severity||0)>=4?"#FF536C":(root.selectedIndex===index?"#36DFFF":"#29465D"))
                    Row {
                        anchors.fill:parent
                        anchors.margins:10
                        spacing:12
                        Rectangle {
                            anchors.verticalCenter:parent.verticalCenter
                            width:8
                            height:parent.height-6
                            radius:4
                            color:Number(modelData.severity||0)>=4?"#FF405D":Number(modelData.severity||0)>=3?"#F7D85B":"#43DFFF"
                        }
                        Column {
                            width:parent.width-142
                            anchors.verticalCenter:parent.verticalCenter
                            spacing:2
                            Row {
                                width:parent.width
                                spacing:8
                                Text { text:String(modelData.type); color:modelData.integrity?"#F7D85B":"#5BDFFF"; font.pixelSize:10; font.bold:true }
                                Text { visible:modelData.flagged; text:"FLAGGED"; color:"#F7D85B"; font.pixelSize:10; font.bold:true }
                            }
                            Text { width:parent.width; text:String(modelData.title); color:"white"; font.pixelSize:15; font.bold:true; elide:Text.ElideRight }
                            Text { width:parent.width; text:String(modelData.detail); color:"#AFC4D8"; font.pixelSize:11; elide:Text.ElideMiddle }
                        }
                        Column {
                            width:110
                            anchors.verticalCenter:parent.verticalCenter
                            spacing:3
                            Text { width:parent.width; text:"SEV "+String(modelData.severity||"-"); color:Number(modelData.severity||0)>=4?"#FF6577":"#F7D85B"; font.pixelSize:10; font.bold:true; horizontalAlignment:Text.AlignRight }
                            Text { width:parent.width; text:modelData.flagged?"□ UNFLAG":"□ FLAG"; color:modelData.flagged?"#F7D85B":"#8EA7BD"; font.pixelSize:9; font.bold:true; horizontalAlignment:Text.AlignRight }
                            Text { width:parent.width; text:"X ACK"; color:"#43F0A0"; font.pixelSize:9; font.bold:true; horizontalAlignment:Text.AlignRight }
                        }
                    }
                }
                Text {
                    anchors.centerIn:parent
                    visible:summaryList.count===0
                    text:"No unacknowledged security notifications or integrity events."
                    color:"#8FA8BF"
                    font.pixelSize:16
                    font.bold:true
                    horizontalAlignment:Text.AlignHCenter
                }
            }
            Text {
                width:parent.width
                text:"D-PAD  SELECT    X  ACKNOWLEDGE    □  FLAG    R3  ACKNOWLEDGE ALL    O  CLOSE"
                color:"#41DFFF"
                font.pixelSize:12
                font.bold:true
                horizontalAlignment:Text.AlignHCenter
                elide:Text.ElideRight
            }
        }
        Column {
            id:threatPanel
            visible:root.mode==="security-threat"
            anchors.fill:parent
            anchors.margins:34
            spacing:14
            readonly property var incident:root.threatIncident()
            readonly property int severity:root.threatSeverity()

            Row {
                width:parent.width
                height:40
                spacing:12
                Text { anchors.verticalCenter:parent.verticalCenter; text:"ACTIVE SECURITY THREAT"; color:"white"; font.pixelSize:27; font.bold:true }
                Rectangle {
                    anchors.verticalCenter:parent.verticalCenter
                    width:96; height:28; radius:14
                    color:threatPanel.severity>=4?"#45131C":threatPanel.severity>=3?"#44330E":"#12344A"
                    border.width:1
                    border.color:threatPanel.severity>=4?"#FF536C":threatPanel.severity>=3?"#F7D85B":"#42DFFF"
                    Text { anchors.centerIn:parent; text:"SEVERITY "+String(threatPanel.severity); color:parent.border.color; font.pixelSize:10; font.bold:true }
                }
                Rectangle {
                    visible:root.threatFlagged()
                    anchors.verticalCenter:parent.verticalCenter
                    width:78; height:28; radius:14
                    color:"#3B320C"; border.width:1; border.color:"#F7D85B"
                    Text { anchors.centerIn:parent; text:"FLAGGED"; color:"#F7D85B"; font.pixelSize:10; font.bold:true }
                }
            }
            Rectangle { width:parent.width; height:1; color:"#34546C" }
            Text {
                width:parent.width
                text:String((root.contextData&&root.contextData.incident&&root.contextData.incident.displayTitle)||threatPanel.incident.displayTitle||threatPanel.incident.title||threatPanel.incident.message||"Security event")
                color:threatPanel.severity>=4?"#FF7184":"#F4F9FF"
                font.pixelSize:23
                font.bold:true
                wrapMode:Text.WordWrap
            }
            Grid {
                width:parent.width
                columns:2
                columnSpacing:18
                rowSpacing:8
                Repeater {
                    model:[
                        {l:"COMPONENT",v:String(threatPanel.incident.component||threatPanel.incident.source||"Security Core")},
                        {l:"TIME",v:String(threatPanel.incident.timestamp||threatPanel.incident.time||"Current session")},
                        {l:"EVENT ID",v:String(root.threatEventId()||"Notification")},
                        {l:"STATE",v:root.threatFlagged()?"Flagged for review":"Requires review"}
                    ]
                    delegate:Column {
                        required property var modelData
                        width:(parent.width-parent.columnSpacing)/2
                        spacing:2
                        Text { width:parent.width; text:String(modelData.l); color:"#7895AD"; font.pixelSize:10; font.bold:true }
                        Text { width:parent.width; text:String(modelData.v); color:"#E6F0FA"; font.pixelSize:13; font.bold:true; elide:Text.ElideMiddle }
                    }
                }
            }
            Rectangle {
                width:parent.width
                height:Math.max(160,parent.height-300)
                radius:14
                color:"#091927"
                border.width:1
                border.color:"#29465D"
                Column {
                    anchors.fill:parent
                    anchors.margins:16
                    spacing:10
                    Text { text:"WHAT HAPPENED"; color:"#5BDFFF"; font.pixelSize:11; font.bold:true }
                    Text { width:parent.width; text:String((root.contextData&&root.contextData.incident&&root.contextData.incident.displayDetail)||threatPanel.incident.displayDetail||threatPanel.incident.message||threatPanel.incident.evidence||threatPanel.incident.description||"No additional evidence supplied."); color:"#D6E3EF"; font.pixelSize:14; wrapMode:Text.WordWrap }
                    Rectangle { width:parent.width; height:1; color:"#203E53" }
                    Text { text:"RECOMMENDED ACTION"; color:"#F7D85B"; font.pixelSize:11; font.bold:true }
                    Text { width:parent.width; text:String(threatPanel.incident.recommendedAction||threatPanel.incident.action||"Review the event. Acknowledge it only after you are satisfied the condition is understood or resolved."); color:"#C9D7E5"; font.pixelSize:13; wrapMode:Text.WordWrap }
                }
            }
            Item { width:1; height:Math.max(0,parent.height-y-34) }
            Text {
                width:parent.width
                text:"X  ACKNOWLEDGE      □  "+(root.threatFlagged()?"UNFLAG":"FLAG")+"      O  CLOSE"
                color:"#41DFFF"
                font.pixelSize:13
                font.bold:true
                horizontalAlignment:Text.AlignHCenter
            }
        }
    }
    function detailsText(){
        if(kind==="cpu"||kind==="memory"){
            var rows=monitorBackend?(kind==="cpu"?monitorBackend.cpuProcesses:monitorBackend.memoryProcesses):[];var out="PID     PROCESS                         CPU       RAM       STATE       RUNTIME\n"
            for(var i=0;i<Math.min(14,rows.length);i++){var p=rows[i];out+=String(p.pid||"--")+"     "+String(p.name||"Unknown")+"     "+String(p.cpu||0)+"%     "+String(p.memory||"--")+"     "+String(p.state||"--")+"     "+String(p.runtime||"--")+"\n"}return out
        }
        if(kind==="temperature")return "Current: "+String(monitorBackend?monitorBackend.temperatureCelsius:"--")+"°C\nState: "+String(monitorBackend?monitorBackend.thermalStatus:"Unavailable")+"\nThrottling events: "+String(monitorBackend?monitorBackend.throttlingEvents:0)+"\nRecent min/max/average and bounded thermal history use the shared SystemMonitor cache."
        if(kind==="network")return "Interface: "+String(monitorBackend?monitorBackend.activeInterface:"--")+"\nSSID: "+String(monitorBackend?monitorBackend.ssid:"--")+"\nAddress: "+String(monitorBackend?monitorBackend.localIp:"--")+"\nTailscale: "+String(monitorBackend?monitorBackend.tailscaleIp:"--")+"\nDownload: "+String(monitorBackend?monitorBackend.rxBytesPerSecond:0)+" B/s\nUpload: "+String(monitorBackend?monitorBackend.txBytesPerSecond:0)+" B/s"
        if(kind==="storage"){var d=contextData.device||{};return "Device: "+String(d.path||"--")+"\nModel: "+String(d.model||d.label||"--")+"\nCapacity: "+String(d.sizeText||d.size||"--")+"\nFilesystem: "+String(d.filesystem||d.fstype||"--")+"\nMount: "+String(d.mountText||"Not mounted")+"\nProtection: "+(d.protected||d.containsRoot?"ROOT / BOOT PROTECTED":"Eligible only after backend validation and deliberate confirmation")}
        if(kind==="security"){var e=contextData.incident||{};return "Severity: "+String(e.severity||"Unknown")+"\nAttack path: "+String(e.attackPath||"Evidence unavailable — no path is claimed")+"\nAffected components: "+String(e.components||e.affectedComponents||"Unknown")+"\nEvidence: "+String(e.evidence||e.message||"No structured evidence supplied")+"\nCurrent state: "+String(securityBackend?securityBackend.threatLabel:"Unavailable")+"\nSuggested action: "+String(e.recommendedAction||"Open Security and review authoritative evidence")}
        if(kind==="application"){
            var a=app()||{}, runtime=appBackend&&appBackend.runtimeState?appBackend.runtimeState(String(a.id||"")):({})
            var management=appBackend&&appBackend.appManagementDetails?appBackend.appManagementDetails(a):({})
            return "Name: "+String(a.name||a.id||"Unknown")+"\nStatus: "+(a.running?"Running":"Stopped")+
                    "\nPID: "+String(runtime.pid||management.pid||"--")+"\nCPU: "+String(runtime.cpuPercent||management.cpuPercent||"--")+
                    "%\nMemory: "+String(runtime.memoryText||management.memoryText||"--")+"\nVersion: "+String(a.version||management.version||"Unknown")+
                    "\nPermissions: "+String(a.permissions||management.permissions||"None declared")+"\nRuntime: "+String(a.sessionText||runtime.runtime||"--")+
                    "\nSecurity: "+String(a.securityStatus||management.securityStatus||"No app-specific finding")
        }
        return "Live details are unavailable for this item."
    }
}
