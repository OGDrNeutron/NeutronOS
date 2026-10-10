import QtQuick

Item {
    id:root
    property var layoutBackend:null
    property var monitorBackend:null
    property var networkBackend:null
    property var storageBackend:null
    property var securityBackend:null
    property var notificationBackend:null
    property var clockBackend:null
    property var activeUser:null
    // NEUTRONOS_CONTROLLER_BACKEND_BINDING_V1
    property var controllerBackend:null
    property var appsBackend:null
    property bool shellActive:false
    property bool controllerActive:true
    readonly property bool controllerModalOpen: moveMode || securityPanelActive || networkPanelActive ||
                                                  networkScanModal.opened || networkDiagnosticsModal.opened
    property string tabId:"system"
    property int selectedIndex:0
    property bool securityPanelActive:false
    property int securityActionIndex:0
    property bool networkPanelActive:false
    property int networkActionIndex:0
    property bool securityMaxArmed:false
    property bool moveMode:false
    property string movingWidgetId:""
    readonly property int gridColumns:layoutBackend?Number(layoutBackend.gridColumns||15):15
    readonly property int gridRows:layoutBackend?Number(layoutBackend.gridRows||4):4
    readonly property real layoutGap:Math.max(10,Math.min(22,width*.007))
    readonly property real cellWidth:(width-layoutGap*(gridColumns-1))/gridColumns
    readonly property real cellHeight:(height-layoutGap*(gridRows-1))/gridRows
    Timer{id:securityArmTimer;interval:2600;repeat:false;onTriggered:root.securityMaxArmed=false}
    signal detailsRequested(string kind,var context)
    signal actionsRequested(string kind,var context)
    signal appLaunchRequested(var appData)
    signal topBoundaryRequested()
    signal bottomBoundaryRequested()
    function hasExtraStorage(){
        var devices=storageBackend&&storageBackend.devices?storageBackend.devices:[]
        var systemDisk=storageBackend?String(storageBackend.systemDisk||""):""
        for(var i=0;i<devices.length;++i){
            var device=devices[i]||({}), path=String(device.path||"")
            if(path.length&&path!==systemDisk&&device.containsRoot!==true&&Number(device.sizeBytes||1)>0)
                return true
        }
        var slots=monitorBackend&&monitorBackend.storageDisplaySlots?monitorBackend.storageDisplaySlots:[]
        return slots.length>1&&slots[1]&&slots[1].connected!==false
    }
    readonly property bool extraStorageAvailable:hasExtraStorage()
    readonly property var enabledWidgets: {
        var out=[]
        var source=layoutBackend?(tabId==="system"?layoutBackend.widgets:layoutBackend.widgetsForTab(tabId)):[]
        for(var i=0;i<source.length;i++){
            var item=source[i], id=String(item.id||"")
            if(item.enabled===false)continue
            if(tabId==="system"&&id==="media-storage"&&!extraStorageAvailable)continue
            if(tabId==="system"&&id==="uptime"&&extraStorageAvailable)continue
            out.push(item)
        }
        return out
    }
    function currentWidget(){return enabledWidgets.length?enabledWidgets[Math.max(0,Math.min(selectedIndex,enabledWidgets.length-1))]:null}
    function currentWidgetItem(){return gridRepeater.itemAt(Math.max(0,Math.min(selectedIndex,enabledWidgets.length-1)))}
    function rangesOverlap(a0,a1,b0,b1){return Math.min(a1,b1)>Math.max(a0,b0)}
    function spatialNeighbor(direction){
        var current=currentWidget()
        if(!current)return -1
        var cLeft=Number(current.gridColumn||0),cTop=Number(current.gridRow||0)
        var cRight=cLeft+Number(current.columnSpan||2),cBottom=cTop+Number(current.rowSpan||2)
        var cX=(cLeft+cRight)/2,cY=(cTop+cBottom)/2
        var best=-1,bestScore=Number.POSITIVE_INFINITY
        for(var i=0;i<enabledWidgets.length;++i){
            if(i===selectedIndex)continue
            var candidate=enabledWidgets[i]
            var left=Number(candidate.gridColumn||0),top=Number(candidate.gridRow||0)
            var right=left+Number(candidate.columnSpan||2),bottom=top+Number(candidate.rowSpan||2)
            var x=(left+right)/2,y=(top+bottom)/2
            var primary=0,perpendicular=0,aligned=false,eligible=false
            if(direction==="right"){eligible=x>cX;primary=Math.max(0,left-cRight);perpendicular=Math.abs(y-cY);aligned=rangesOverlap(cTop,cBottom,top,bottom)}
            else if(direction==="left"){eligible=x<cX;primary=Math.max(0,cLeft-right);perpendicular=Math.abs(y-cY);aligned=rangesOverlap(cTop,cBottom,top,bottom)}
            else if(direction==="down"){eligible=y>cY;primary=Math.max(0,top-cBottom);perpendicular=Math.abs(x-cX);aligned=rangesOverlap(cLeft,cRight,left,right)}
            else if(direction==="up"){eligible=y<cY;primary=Math.max(0,cTop-bottom);perpendicular=Math.abs(x-cX);aligned=rangesOverlap(cLeft,cRight,left,right)}
            if(!eligible)continue
            // Directional distance dominates, aligned cards beat diagonals,
            // and model index is the stable final tie breaker.
            var score=primary*1000+perpendicular*20+(aligned?0:250)+i*.001
            if(score<bestScore){bestScore=score;best=i}
        }
        return best
    }
    function navigateSpatial(direction){
        var next=spatialNeighbor(direction)
        if(next>=0){selectedIndex=next;return true}
        if(direction==="up")topBoundaryRequested()
        else if(direction==="down")bottomBoundaryRequested()
        return true
    }
    function beginMove(widgetId){
        if(!layoutBackend)return false
        movingWidgetId=String(widgetId);moveMode=true
        var began=tabId==="system"?layoutBackend.beginWidgetMove(movingWidgetId):layoutBackend.beginTabWidgetMove(tabId,movingWidgetId)
        if(!began){movingWidgetId="";moveMode=false;return false}
        var current=null, source=tabId==="system"?layoutBackend.widgets:layoutBackend.widgetsForTab(tabId)
        for(var index=0;index<source.length;++index)if(String(source[index].id)===movingWidgetId){current=source[index];break}
        selectedIndex=Math.max(0,Number(current&&current.position>=0?current.position:current&&current.order||0));forceActiveFocus();return true
    }
    function finishMove(commit){
        if(!moveMode)return false
        if(layoutBackend){
            if(tabId==="system"){if(commit)layoutBackend.commitWidgetMove();else layoutBackend.cancelWidgetMove()}
            else {if(commit)layoutBackend.commitTabWidgetMove();else layoutBackend.cancelTabWidgetMove()}
        }
        moveMode=false;movingWidgetId="";return true
    }
    function launchSecurityApp(){
        if(!appsBackend)return false
        var app=typeof appsBackend.appById==="function"?appsBackend.appById("security"):null
        if(app&&String(app.id||"").length){appLaunchRequested(app);return true}
        return false
    }
    function executeSecurityAction(){
        if(!securityBackend)return
        var index=securityActionIndex
        if(index===0){
            var item=currentWidgetItem()
            if(item&&item.currentIncident&&String(item.currentIncident.id||"").length)
                detailsRequested("security-threat",{incident:item.currentIncident,widget:currentWidget(),tabId:root.tabId})
            else
                detailsRequested("security-summary",{widget:currentWidget(),tabId:root.tabId})
        }
        else if(index===1&&typeof securityBackend.setResponseEngineEnabled==="function")
            securityBackend.setResponseEngineEnabled(securityBackend.responseEngineEnabled!==true)
        else if(index===2&&typeof securityBackend.setEnforcementEnabled==="function")
            securityBackend.setEnforcementEnabled(securityBackend.enforcementEnabled!==true)
        else if(index===3&&typeof securityBackend.setLearningMode==="function")
            securityBackend.setLearningMode(securityBackend.learningMode!==true)
        else if(index>=4&&index<=8)
            launchSecurityApp()
        else if(index===9){
            if(typeof securityBackend.verifyIntegrity==="function")securityBackend.verifyIntegrity()
        }
        else if(index===10){
            securityBackend.setManualThreatLevel(Math.max(1,Number(securityBackend.threatLevel||5)-1))
        }
        else if(index===11){
            detailsRequested("security-summary",{widget:currentWidget(),tabId:root.tabId})
        }
    }
    function navigateSecurityControls(direction){
        var index=securityActionIndex
        if(index===0){
            if(direction==="down")securityActionIndex=1
            else if(direction==="up"){securityPanelActive=false;return navigateSpatial("up")}
            return true
        }
        if(index>=1&&index<=8){
            var local=index-1,row=Math.floor(local/2),column=local%2
            if(direction==="left"&&column===1)securityActionIndex=index-1
            else if(direction==="right"&&column===0)securityActionIndex=index+1
            else if(direction==="up")securityActionIndex=row===0?0:index-2
            else if(direction==="down"){
                if(row<3)securityActionIndex=index+2
                else securityActionIndex=column===0?9:11
            }
            return true
        }
        if(index>=9&&index<=11){
            if(direction==="left")securityActionIndex=Math.max(9,index-1)
            else if(direction==="right")securityActionIndex=Math.min(11,index+1)
            else if(direction==="up")securityActionIndex=index===9?7:8
            else if(direction==="down"){securityPanelActive=false;return navigateSpatial("down")}
            return true
        }
        securityActionIndex=0
        return true
    }
    function boolNetworkValue(value){
        if(value===true||value===1)return true
        var text=String(value===undefined||value===null?"":value).toLowerCase()
        return text==="true"||text==="1"||text==="yes"||text==="enabled"||text==="active"||text==="running"||text==="connected"||text==="on"
    }
    function hotspotEnabled(){
        var state=networkBackend&&networkBackend.offlineNetworkState?networkBackend.offlineNetworkState:({})
        return Boolean(state.hotspotEnabled||state.lanModeEnabled||state.localModeEnabled)
    }
    function tailscaleEnabled(){
        var state=securityBackend&&securityBackend.tailscaleStatus?securityBackend.tailscaleStatus:({})
        var value=state.enabled!==undefined?state.enabled:state.active!==undefined?state.active:state.running!==undefined?state.running:state.connected
        return boolNetworkValue(value)
    }
    function executeNetworkAction(requestedIndex){
        var index=requestedIndex===undefined||requestedIndex===null?networkActionIndex:Number(requestedIndex)
        networkActionIndex=index
        if(index===0){
            if(networkBackend&&typeof networkBackend.setOfflineNetworkMode==="function")
                networkBackend.setOfflineNetworkMode(hotspotEnabled()?"normal-wifi":"wifi-hotspot")
            return
        }
        if(index===1){
            if(securityBackend&&typeof securityBackend.setTailscaleEnabled==="function")
                securityBackend.setTailscaleEnabled(!tailscaleEnabled())
            return
        }
        if(index===2){
            networkScanModal.openModal()
            return
        }
        if(index===3){
            if(networkBackend&&typeof networkBackend.runSpeedTest==="function")
                networkBackend.runSpeedTest()
            return
        }
        if(index===4){
            networkDiagnosticsModal.openModal()
            return
        }
    }
    function navigateNetworkControls(direction){
        var index=networkActionIndex
        if(index<=1){
            if(direction==="left")networkActionIndex=0
            else if(direction==="right")networkActionIndex=1
            else if(direction==="down")networkActionIndex=index===0?2:4
            else if(direction==="up"){networkPanelActive=false;return navigateSpatial("up")}
            return true
        }
        if(direction==="left")networkActionIndex=Math.max(2,index-1)
        else if(direction==="right")networkActionIndex=Math.min(4,index+1)
        else if(direction==="up")networkActionIndex=index===4?1:0
        else if(direction==="down"){networkPanelActive=false;return navigateSpatial("down")}
        return true
    }
    function handleControllerPressed(action){
        if(networkScanModal.opened){
            var scanAction=String(action===undefined||action===null?"":action).toLowerCase()

            if(scanAction==="cancel"||scanAction==="back"||
               scanAction==="circle"||scanAction==="o"){
                networkScanModal.dismissModal()
                forceActiveFocus()
                return true
            }

            return networkScanModal.handleControllerPressed(action)
        }
        if(networkDiagnosticsModal.opened){
            if(action==="cancel"||action==="back"){networkDiagnosticsModal.closeModal();forceActiveFocus();return true}
            return networkDiagnosticsModal.handleControllerPressed(action)
        }
        if(moveMode){
            if(action==="primary")return finishMove(true)
            if(action==="cancel")return finishMove(false)
            var delta=action==="left"?-1:action==="right"?1:action==="up"?-3:action==="down"?3:0
            if(delta!==0&&layoutBackend){
                if(tabId==="system")layoutBackend.previewWidgetMove(delta);else layoutBackend.previewTabWidgetMove(delta)
                var movedItems=tabId==="system"?layoutBackend.widgets:layoutBackend.widgetsForTab(tabId)
                for(var movedIndex=0;movedIndex<movedItems.length;++movedIndex)if(String(movedItems[movedIndex].id)===movingWidgetId){selectedIndex=Math.max(0,Number(movedItems[movedIndex].position>=0?movedItems[movedIndex].position:movedItems[movedIndex].order||0));break}
            }
            return true
        }
        if(securityPanelActive){
            if(action==="cancel"){securityPanelActive=false;return true}
            if(action==="left"||action==="right"||action==="up"||action==="down")return navigateSecurityControls(action)
            if(action==="primary"){executeSecurityAction();return true}
            if(action==="context")detailsRequested("security",{incident:securityBackend&&securityBackend.events&&securityBackend.events.length?securityBackend.events[0]:{}})
            return true
        }
        if(networkPanelActive){
            if(action==="cancel"){networkPanelActive=false;return true}
            if(action==="left"||action==="right"||action==="up"||action==="down")return navigateNetworkControls(action)
            if(action==="primary"){executeNetworkAction();return true}
            if(action==="context")detailsRequested("network",{widget:currentWidget(),tabId:root.tabId})
            return true
        }
        if(action==="left"||action==="right"||action==="up"||action==="down")navigateSpatial(action)
        else if(action==="context"&&currentWidget())detailsRequested(currentWidget().id,{widget:currentWidget(),tabId:root.tabId})
        else if(action==="secondary"&&currentWidget()){
            var item=currentWidgetItem()
            if(String(currentWidget().id)==="security"&&item&&item.currentIncident&&item.currentIncident.id&&item.currentIncident.dismissible!==false){
                if(item.currentIncident.notificationId&&notificationBackend&&notificationBackend.dismiss)notificationBackend.dismiss(item.currentIncident.notificationId)
                else if(item.currentIncident.eventId&&securityBackend&&securityBackend.acknowledgeEvent)securityBackend.acknowledgeEvent(item.currentIncident.eventId)
            }else actionsRequested(currentWidget().id,{widget:currentWidget(),tabId:root.tabId})
        }
        else if(action==="primary"&&currentWidget()){
            if(String(currentWidget().id)==="security"&&String(currentWidget().sizeFamily)==="large"){securityPanelActive=true;securityActionIndex=0}
            else if(String(currentWidget().id)==="network"){networkPanelActive=true;networkActionIndex=0}
            else detailsRequested(currentWidget().id,{widget:currentWidget()})
        }
        return true
    }
    onEnabledWidgetsChanged:selectedIndex=Math.max(0,Math.min(selectedIndex,Math.max(0,enabledWidgets.length-1)))
    NetworkScanModal {
        id: networkScanModal
        anchors.fill: parent
        networkBackend: root.networkBackend
        z: 500
    }
    NetworkDiagnosticsModal {
        id: networkDiagnosticsModal
        anchors.fill: parent
        networkBackend: root.networkBackend
        z: 510
    }
    Item { id:gridViewport;anchors.fill:parent;clip:true
        Repeater { id:gridRepeater; model:root.enabledWidgets
            delegate: AdaptiveWidget {
                required property int index
                required property var modelData
                widgetId:String(modelData.id)
                widgetVariant:String(modelData.variant||modelData.size||"small-square")
                widgetSize:String(modelData.sizeFamily||widgetVariant.split("-")[0])
                shapeVariant:String(modelData.shape||widgetVariant.split("-")[1]||"square")
                title:String(modelData.title)
                x:Number(modelData.gridColumn||0)*(root.cellWidth+root.layoutGap)
                y:Number(modelData.gridRow||0)*(root.cellHeight+root.layoutGap)
                width:Number(modelData.columnSpan||2)*root.cellWidth+(Number(modelData.columnSpan||2)-1)*root.layoutGap
                height:Number(modelData.rowSpan||2)*root.cellHeight+(Number(modelData.rowSpan||2)-1)*root.layoutGap
                selected:root.controllerActive&&root.selectedIndex===index
                moving:root.moveMode&&root.movingWidgetId===widgetId
                viewportWidth:root.width
                monitorBackend:root.monitorBackend
                networkBackend:root.networkBackend
                securityBackend:root.securityBackend
                notificationBackend:root.notificationBackend
                clockBackend:root.clockBackend
                activeUser:root.activeUser
                controllerBackend:root.controllerBackend
                appsBackend:root.appsBackend
                storageBackend:root.storageBackend
                securityPanelActive:root.securityPanelActive&&root.selectedIndex===index
                securityActionIndex:root.securityActionIndex
                networkPanelActive:root.networkPanelActive&&root.selectedIndex===index
                networkActionIndex:root.networkActionIndex
                onNetworkActionRequested:function(requestedIndex){root.executeNetworkAction(requestedIndex)}
                maxDefconArmed:root.securityMaxArmed
                storageData:root.monitorBackend&&root.monitorBackend.storageDisplaySlots&&root.monitorBackend.storageDisplaySlots.length>storageSlot?root.monitorBackend.storageDisplaySlots[storageSlot]:({})
                storageSlot:widgetId==="media-storage"?1:0
                animationEnabled:root.visible&&root.shellActive
            }
        }
    }
}
