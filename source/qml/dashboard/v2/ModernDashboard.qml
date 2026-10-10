import QtQuick
import QtQuick.Controls
import "../../components"
import "../../common/ControllerFeatureRegistry.js" as ControllerFeatures

Item {
    id:root
    property var appsBackend:null; property var monitorBackend:null; property var storageBackend:null; property var networkBackend:null; property var securityBackend:null; property var controllerBackend:null; property var notificationBackend:null; property var settingsBackend:null; property var clockBackend:null; property var activeUser:null; property bool shellActive:false
    property var layoutBackend:(typeof dashboardLayoutManager!=="undefined")?dashboardLayoutManager:null
    property string activeMode:"desktop"
    property bool selectorOnly:false
    // The mini footer is a discrete control: one move per actual press.
    // Never inherit a held stick/D-pad repeat from the Desktop grid or a
    // previously selected footer action. System Overview is unaffected.
    readonly property bool suppressDirectionalRepeat:
        activeMode === "desktop" && commandTarget === "footer" &&
        footerIndex === 1 && desktopCenterMode === "carousel"
    readonly property real uiScale:Math.max(1,Math.min(2,Math.min(width/1920,height/1080)))
    property bool selectorOpen:false; property int selectorIndex:0; property int zone:0; property int headerIndex:0; property int appIndex:6; property string selectedAppId:""; property int footerIndex:0; property date now:new Date(); property int clockHeaderIconIndex:0

    // Desktop foundation: scan the current screen once per shell session, then
    // freeze the geometry. Desktop v2.4 uses 20 cells across and 10 down.
    property bool desktopGridInitialized:false
    property int desktopScreenWidth:0
    property int desktopScreenHeight:0
    property int desktopGridColumns:20
    property int desktopGridRows:10
    property real desktopGridCellSize:0
    property var desktopItems:[]
    property bool desktopDefaultsInitialized:false
    property bool controllerWelcomeOpen:false
    property int controllerGuideSelection:0
    property bool controllerWelcomeChecked:false
    property string desktopCenterMode:"controller"
    property bool desktopCenterMenuOpen:false
    property int desktopCenterMenuIndex:0
    property int desktopCarouselIndex:0
    property bool desktopCarouselMoveMode:false
    property var desktopCarouselMoveOriginal:[]
    property int desktopCarouselMoveOriginalIndex:-1
    // Reorder mode additionally keeps a direction latch for releases routed
    // through the modal; normal browsing relies on Main.qml physical press edges.
    property string desktopCarouselHeldDirection:""
    property bool desktopCarouselRemoveModalOpen:false
    property bool desktopCarouselSettingsOpen:false
    property int desktopCarouselSettingsRow:0
    property int desktopCarouselPickerIndex:0
    property int desktopCarouselCapacity:9
    property var desktopCarouselIds:[]
    // Stable delegates: never reconstruct the app model for every key press.
    property var desktopCarouselResolvedApps:[]
    property bool controllerRegistrationNeeded:false
    property bool controllerTabAcknowledged:false
    readonly property bool controllerRegistrationAttention:controllerRegistrationNeeded&&!controllerTabAcknowledged
    property bool controllerGuideSeen:false
    property bool appCarouselSeen:false
    readonly property bool controllerGuideNeedsAttention:!controllerGuideSeen
    readonly property bool appCarouselNeedsAttention:controllerGuideSeen&&!appCarouselSeen
    property real onboardingPulse:0.15
    SequentialAnimation on onboardingPulse {
        // Draw attention briefly, then retain the highlight without an idle render loop.
        running:root.shellActive&&root.activeMode==="desktop"&&(root.controllerGuideNeedsAttention||root.appCarouselNeedsAttention)
        loops:3
        NumberAnimation{from:0.15;to:0.95;duration:500;easing.type:Easing.InOutSine}
        NumberAnimation{from:0.95;to:0.15;duration:500;easing.type:Easing.InOutSine}
    }
    property bool controllerRegistrationPollPending:false
    // Valid only after the read-only bridge returns a registered controller's
    // current USB/BlueZ state. C++ battery state is not a transport indicator.
    property bool controllerLiveKnown:false
    property string controllerLiveTransport:"unknown"
    property bool controllerLivePollPending:false
    property bool desktopLayoutLoaded:false
    property bool desktopLayoutPersistBusy:false
    property string desktopLayoutPending:""
    property int desktopBootstrapAttempts:0
    property bool desktopBootstrapComplete:false
    property string desktopIconSizeMode:"large"
    readonly property real desktopChromeHeight:36*root.uiScale
    readonly property real desktopSafeInset:10
    property bool appMoveMode:false; property string movingAppId:""; property int appMoveOriginalIndex:-1; property int appMoveCandidateIndex:-1
    property bool systemHoldConsumed:false
    property bool securityCompactScoreView:false
    property int cancelTapCount:0
    signal appLaunchRequested(var appData); signal notificationCenterRequested(); signal quickActionRequested(string action); signal systemDetailRequested(string modalId,var context); signal dashboardModeRequested(string mode); signal searchRequested()
    DashboardTheme{id:theme}
    readonly property var baseAppList: appsBackend && appsBackend.dashboardApps ? appsBackend.dashboardApps : filteredDashboardApps()
    readonly property var appList:previewAppList()
    readonly property var modes:{
        var source=layoutBackend&&layoutBackend.availableTabs?layoutBackend.availableTabs:[{id:"system",label:"System Overview"},{id:"security",label:"Security"},{id:"storage",label:"Storage"},{id:"apps",label:"Apps"},{id:"legacy",label:"Legacy"}]
        var out=[{id:"desktop",label:"Desktop"}]
        for(var i=0;i<source.length;++i){
            var entry=source[i]||({})
            if(String(entry.id||"")!=="desktop")out.push(entry)
        }
        return out
    }
    readonly property var quickNames:["Power","Help","Lock","Wi-Fi","Bluetooth","Notifications","Running Apps"]
    function validManifestIds(){return ["appstore","docker","filemanager","logs","neutronremotesystems","security","settings","storage","terminal"]}
    function appHasValidJson(app){
        app=app||({})
        var id=String(app.id||app.appId||app.name||"").trim()
        if(!id.length)return false
        try{if(appsBackend&&typeof appsBackend.hasValidDashboardManifest==="function")return appsBackend.hasValidDashboardManifest(app)===true}catch(e){}
        var manifestPath=String(app.manifestPath||app.appJsonPath||app.manifest||app.dashboardManifest||"").trim().toLowerCase()
        if(manifestPath.indexOf("app.json")>=0)return true
        return validManifestIds().indexOf(id)>=0
    }
    function filteredDashboardApps(){
        if(!appsBackend)return []
        try{
            // AppManager::dashboardApps() is already backed by
            // hasValidDashboardManifest(), so it is the authoritative list.
            if(appsBackend.dashboardApps)return appsBackend.dashboardApps||[]
        }catch(e){}
        var source=appsBackend.apps?appsBackend.apps:[]
        var out=[]
        for(var i=0;i<source.length;++i){
            var entry=source[i]||({})
            if(appHasValidJson(entry))out.push(entry)
        }
        return out
    }
    readonly property real majorTabContentLift:(activeMode==="system"||activeMode==="apps"||activeMode==="security"||activeMode==="storage")?25*root.uiScale:0
    // Exact dashboard mirror of qml/apps/security/Main.qml state logic.
    function securityAppSuspiciousEvents() {
        var source = securityBackend && securityBackend.events
                   ? securityBackend.events : []
        var out = []

        for (var i = 0; i < source.length; ++i) {
            var event = source[i] || ({})
            var severity = String(
                event.severityLabel || event.severity || event.status || ""
            ).toLowerCase()
            var text = (
                String(event.title || event.type || event.eventType || "") + " " +
                String(event.message || event.description || event.detail || event.reason || "")
            ).toLowerCase()

            var suspicious =
                severity.indexOf("critical") >= 0 ||
                severity.indexOf("high") >= 0 ||
                severity.indexOf("severe") >= 0 ||
                severity.indexOf("warning") >= 0 ||
                severity.indexOf("attention") >= 0 ||
                text.indexOf("suspicious") >= 0 ||
                text.indexOf("blocked") >= 0 ||
                text.indexOf("malware") >= 0 ||
                text.indexOf("attack") >= 0 ||
                text.indexOf("intrusion") >= 0

            if (suspicious && event.acknowledged !== true)
                out.push(event)
        }

        return out
    }

    function securityNeedsAttention() {
        // NEUTRONOS_SECURITY_ATTENTION_TELEMETRY_V2
        if (!securityBackend || securityBackend.auditValid !== true)
            return true

        var stats = securityBackend.stats || ({})
        var firewallState = String(stats.firewallProtectionState || "").toUpperCase()
        if (firewallState.length > 0) {
            if (firewallState !== "SECURE")
                return true
        } else if (securityBackend.daemonOnline !== true) {
            return true
        }

        if (securityBackend.integrityChanges &&
            securityBackend.integrityChanges.length > 0)
            return true

        if (securityBackend.malwareFindings &&
            securityBackend.malwareFindings.length > 0)
            return true

        if (securityAppSuspiciousEvents().length > 0)
            return true

        if (Number(securityBackend.threatLevel || 5) <= 2)
            return true

        return false
    }
    readonly property bool securityAttention: securityNeedsAttention()
    // NEUTRONOS_HEADER_SECURITY_SCORE_STATE_V1
    function headerSecurityScore(){
        if(!securityBackend || securityBackend.daemonOnline!==true || securityBackend.securityScore===undefined)return -1
        var n=Number(securityBackend.securityScore)
        return isNaN(n)?-1:Math.max(0,Math.min(100,Math.round(n)))
    }
    function headerSecurityLabel(){var n=headerSecurityScore();return n<0?"Unavailable":n>=80?"Secure":n>=55?"Weak Protection":"Unsecure"}
    function headerSecurityStrength(){var n=headerSecurityScore();return n<0?"Unavailable":n>=80?"Secure":n>=55?"Weak":"Unsecure"}
    function headerSecurityColor(){var n=headerSecurityScore();return n<0?theme.red:n>=80?theme.green:n>=55?"#F7D85B":theme.red}
    function headerSecurityIcon(){return headerSecurityScore()>=55?"locked":"unlocked"}
    readonly property string commandTarget: zone===0 ? "dashboard" : zone===1 ? "application" : zone===2 ? "footer" : "header"
    function syncControllerContext(){
        if(activeView.item&&"controllerActive" in activeView.item)
            activeView.item.controllerActive=zone===0
    }
    readonly property color electricBlue: "#00A8FF"
    readonly property color cobaltBlue: "#0047AB"
    readonly property var clockHeaderIcons: ["clockClassic", "clockDigital", "clockMinimal", "clockRing", "clockDot"]
    function readClockHeaderIconIndex(){
        try {
            if(settingsBackend&&typeof settingsBackend.value==="function"){
                var value=Number(settingsBackend.value("ui.dashboard.header.clockIcon",0))
                if(!isNaN(value))return Math.max(0,Math.min(clockHeaderIcons.length-1,Math.round(value)))
            }
        } catch(e) {}
        return 0
    }
    function refreshHeaderClockIcon(){clockHeaderIconIndex=readClockHeaderIconIndex()}
    function clockHeaderIconKind(){return String(clockHeaderIcons[Math.max(0,Math.min(clockHeaderIcons.length-1,clockHeaderIconIndex))])}
    function readDesktopIconSizeMode(){
        try{
            if(settingsBackend&&typeof settingsBackend.value==="function"){
                var mode=String(settingsBackend.value("ui.desktop.iconSize","large")||"large").toLowerCase()
                return mode==="small"?"small":"large"
            }
        }catch(e){}
        return "large"
    }
    function refreshDesktopIconSizeMode(){desktopIconSizeMode=readDesktopIconSizeMode()}
    function desktopUserSuffix(){
        var raw="default"
        try{raw=String(activeUser&&activeUser.username?activeUser.username:"default")}catch(e){}
        return raw.replace(/[^A-Za-z0-9_-]/g,"_")||"default"
    }
    function desktopLayoutKey(){return "ui.desktop.layout."+desktopUserSuffix()}
    function desktopLayoutFallbackKey(){return "ui.desktop.layout"}
    function desktopCarouselIdsKey(){return "ui.desktop.carousel.apps."+desktopUserSuffix()}
    function desktopCarouselCapacityKey(){return "ui.desktop.carousel.capacity."+desktopUserSuffix()}
    function appIdValue(app){return String(app&&(app.id||app.appId||app.name)||"").trim()}
    function findBaseAppById(id){
        id=String(id||"")
        for(var i=0;i<baseAppList.length;++i){var app=baseAppList[i]||({});if(appIdValue(app)===id)return app}
        return null
    }
    function findWidgetById(id){
        id=String(id||"")
        var source=[]
        try{source=layoutBackend&&layoutBackend.widgets?layoutBackend.widgets:[]}catch(e){source=[]}
        if((!source||source.length===0)&&layoutBackend&&typeof layoutBackend.widgetsForTab==="function"){
            try{source=layoutBackend.widgetsForTab("system")||[]}catch(e2){source=[]}
        }
        for(var i=0;i<source.length;++i){var widget=source[i]||({});if(String(widget.id||"")===id)return widget}
        return null
    }
    function serializeDesktopLayout(items){
        var out=[];items=items||[]
        for(var i=0;i<items.length;++i){
            var item=items[i]||({}),type=String(item.type||""),id=String(item.sourceId||"")
            if((type!=="app"&&type!=="widget")||!id.length)continue
            out.push({type:type,sourceId:id,title:String(item.title||""),gridColumn:Math.max(0,Math.round(Number(item.gridColumn||0))),gridRow:Math.max(0,Math.round(Number(item.gridRow||0))),columnSpan:Math.max(1,Math.round(Number(item.columnSpan||1))),rowSpan:Math.max(1,Math.round(Number(item.rowSpan||1)))})
        }
        return out
    }
    function hydrateDesktopLayout(saved){
        var out=[];saved=saved||[]
        for(var i=0;i<saved.length;++i){
            var entry=saved[i]||({}),type=String(entry.type||""),id=String(entry.sourceId||"")
            var cols=Math.max(1,Math.round(Number(entry.columnSpan||1))),rows=Math.max(1,Math.round(Number(entry.rowSpan||1)))
            var col=Math.max(0,Math.min(desktopGridColumns-cols,Math.round(Number(entry.gridColumn||0))))
            var row=Math.max(0,Math.min(desktopGridRows-rows,Math.round(Number(entry.gridRow||0))))
            if(type==="app"){
                var app=findBaseAppById(id);if(!app)continue
                out.push({type:"app",sourceId:id,title:String(entry.title||app.name||app.displayName||id),gridColumn:col,gridRow:row,columnSpan:1,rowSpan:1,appData:app})
            }else if(type==="widget"){
                var widget=findWidgetById(id)||({id:id,title:String(entry.title||id)})
                out.push({type:"widget",sourceId:id,title:String(entry.title||widget.title||widget.name||id),gridColumn:col,gridRow:row,columnSpan:cols,rowSpan:rows,widgetData:widget})
            }
        }
        return out
    }
    function syncDesktopViewLayout(){
        if(activeMode==="desktop"&&activeView.item){
            if("desktopItems" in activeView.item)activeView.item.desktopItems=desktopItems
            if("defaultsSeeded" in activeView.item)activeView.item.defaultsSeeded=desktopDefaultsInitialized
        }
    }
    function persistDesktopLayout(items){
        if(!settingsBackend||typeof settingsBackend.queueChange!=="function")return
        desktopLayoutPending=JSON.stringify(serializeDesktopLayout(items||[]))
        desktopLayoutPersistTimer.restart()
    }
    function flushDesktopLayout(){
        if(desktopLayoutPersistBusy||!desktopLayoutPending.length||!settingsBackend||typeof settingsBackend.queueChange!=="function")return
        desktopLayoutPersistBusy=true
        var payload=desktopLayoutPending
        desktopLayoutPending=""
        try{
            // Keep the per-user key and a non-suffixed fallback. Some older
            // SettingsManager builds reject dynamic preference suffixes during
            // early session startup, while accepting the stable UI key.
            settingsBackend.queueChange(desktopLayoutKey(),payload,"immediate")
            settingsBackend.queueChange(desktopLayoutFallbackKey(),payload,"immediate")
            if(typeof settingsBackend.setUiPreference==="function"){
                try{settingsBackend.setUiPreference(desktopLayoutFallbackKey(),payload)}catch(prefError){}
            }
            if(typeof settingsBackend.applyPending==="function")settingsBackend.applyPending()
        }catch(e){desktopLayoutPending=payload}
        desktopLayoutPersistBusy=false
    }
    function acceptDesktopLayout(items){
        desktopItems=items||[]
        desktopDefaultsInitialized=true
        desktopLayoutLoaded=true
        persistDesktopLayout(desktopItems)
    }
    function restoreDesktopLayout(){
        if(!settingsBackend||typeof settingsBackend.value!=="function"||baseAppList.length===0)return false
        try{
            var raw=settingsBackend.value(desktopLayoutKey(),"")
            if(raw===undefined||raw===null||String(raw).length===0)
                raw=settingsBackend.value(desktopLayoutFallbackKey(),"")
            if(raw===undefined||raw===null||String(raw).length===0)return false
            var parsed=Array.isArray(raw)?raw:JSON.parse(String(raw))
            if(!Array.isArray(parsed))return false
            var hydrated=hydrateDesktopLayout(parsed)
            if(parsed.length>0&&hydrated.length===0)return false
            desktopItems=hydrated
            desktopDefaultsInitialized=true
            desktopLayoutLoaded=true
            desktopBootstrapComplete=true
            syncDesktopViewLayout()
            if(activeView.item&&"autoSeedEnabled" in activeView.item)activeView.item.autoSeedEnabled=true
            return true
        }catch(e){return false}
    }
    function restoreOrSeedDesktopLayout(){
        // Nothing in Desktop persistence is allowed to delay Console first
        // paint. Bootstrap only after the authenticated Console is active.
        if(desktopLayoutLoaded||!shellActive||!activeUser||baseAppList.length===0||!settingsBackend)return
        if(restoreDesktopLayout())return
        desktopBootstrapAttempts++
        // SettingsManager finishes hydrating asynchronously during login. Give
        // it a bounded post-paint window before deciding this is a first-use
        // Desktop. This avoids overwriting a saved layout with defaults.
        if(desktopBootstrapAttempts<6){desktopBootstrapTimer.restart();return}
        if(activeMode==="desktop"&&activeView.item&&typeof activeView.item.seedDefaultSystemApps==="function"){
            if("autoSeedEnabled" in activeView.item)activeView.item.autoSeedEnabled=true
            activeView.item.defaultsSeeded=false
            activeView.item.desktopItems=[]
            activeView.item.seedDefaultSystemApps()
            desktopBootstrapComplete=true
        }
    }
    function normalizeCarouselIds(source){
        var out=[],ids=source||[]
        for(var i=0;i<ids.length;++i){var id=String(ids[i]||"");if(!id.length||out.indexOf(id)>=0||!findBaseAppById(id))continue;out.push(id);if(out.length>=desktopCarouselCapacity)break}
        return out
    }
    function defaultCarouselIds(){
        var out=[]
        for(var i=0;i<baseAppList.length&&out.length<desktopCarouselCapacity;++i){var id=appIdValue(baseAppList[i]);if(id.length)out.push(id)}
        return out
    }
    function restoreDesktopCarouselConfig(){
        if(baseAppList.length===0)return
        try{
            var cap=Number(settingsBackend&&typeof settingsBackend.value==="function"?settingsBackend.value(desktopCarouselCapacityKey(),9):9)
            desktopCarouselCapacity=Math.max(1,Math.min(12,isNaN(cap)?9:Math.round(cap)))
            var raw=settingsBackend&&typeof settingsBackend.value==="function"?settingsBackend.value(desktopCarouselIdsKey(),""):""
            var ids=[]
            if(raw!==undefined&&raw!==null&&String(raw).length)ids=Array.isArray(raw)?raw:JSON.parse(String(raw))
            desktopCarouselIds=normalizeCarouselIds(ids.length?ids:defaultCarouselIds())
            desktopCarouselIndex=Math.max(0,Math.min(desktopCarouselIndex,Math.max(0,desktopCarouselIds.length-1)))
        }catch(e){desktopCarouselIds=defaultCarouselIds()}
    }
    function persistDesktopCarouselConfig(){
        desktopCarouselIds=normalizeCarouselIds(desktopCarouselIds)
        desktopCarouselIndex=Math.max(0,Math.min(desktopCarouselIndex,Math.max(0,desktopCarouselIds.length-1)))
        try{
            if(settingsBackend&&typeof settingsBackend.queueChange==="function"){
                settingsBackend.queueChange(desktopCarouselCapacityKey(),desktopCarouselCapacity,"immediate")
                settingsBackend.queueChange(desktopCarouselIdsKey(),JSON.stringify(desktopCarouselIds),"immediate")
                if(typeof settingsBackend.applyPending==="function")settingsBackend.applyPending()
            }
        }catch(e){}
    }
    function refreshDesktopCarouselResolvedApps(){
        var out=[]
        for(var i=0;i<desktopCarouselIds.length&&out.length<desktopCarouselCapacity;++i){
            var app=findBaseAppById(desktopCarouselIds[i]);if(app)out.push(app)
        }
        desktopCarouselResolvedApps=out
    }
    function desktopCarouselApps(){return desktopCarouselResolvedApps}
    function selectedDesktopCarouselApp(){
        var list=desktopCarouselResolvedApps
        return list.length?list[Math.max(0,Math.min(desktopCarouselIndex,list.length-1))]:null
    }
    onDesktopCarouselIdsChanged:refreshDesktopCarouselResolvedApps()
    onDesktopCarouselCapacityChanged:refreshDesktopCarouselResolvedApps()
    onBaseAppListChanged:refreshDesktopCarouselResolvedApps()
    function isDesktopCarouselDirection(action){return action==="left"||action==="right"||action==="up"||action==="down"}
    function acceptDesktopCarouselDirection(action){
        if(!desktopCarouselMoveMode || !isDesktopCarouselDirection(action))return true
        if(desktopCarouselHeldDirection===action)return false
        desktopCarouselHeldDirection=action
        return true
    }
    function releaseDesktopCarouselDirection(action){if(desktopCarouselHeldDirection===action)desktopCarouselHeldDirection=""}
    function beginDesktopCarouselMove(){if(!selectedDesktopCarouselApp()||desktopCarouselIds.length<2)return;desktopCarouselHeldDirection="";desktopCarouselMoveOriginal=desktopCarouselIds.slice(0);desktopCarouselMoveOriginalIndex=desktopCarouselIndex;desktopCarouselMoveMode=true;desktopCarouselRemoveModalOpen=false}
    function moveDesktopCarousel(delta){
        if(!desktopCarouselMoveMode||desktopCarouselIds.length<2)return
        var from=Math.max(0,Math.min(desktopCarouselIndex,desktopCarouselIds.length-1)),to=Math.max(0,Math.min(desktopCarouselIds.length-1,from+Number(delta||0)))
        if(from===to)return
        var copy=desktopCarouselIds.slice(0),moved=copy.splice(from,1)[0];copy.splice(to,0,moved);desktopCarouselIds=copy;desktopCarouselIndex=to
    }
    function finishDesktopCarouselMove(commit){
        if(!desktopCarouselMoveMode)return
        if(!commit){desktopCarouselIds=desktopCarouselMoveOriginal.slice(0);desktopCarouselIndex=Math.max(0,desktopCarouselMoveOriginalIndex)}
        else persistDesktopCarouselConfig()
        desktopCarouselMoveMode=false;desktopCarouselHeldDirection="";desktopCarouselMoveOriginal=[];desktopCarouselMoveOriginalIndex=-1;desktopCarouselIndex=Math.max(0,Math.min(desktopCarouselIndex,Math.max(0,desktopCarouselIds.length-1)))
    }
    function removeSelectedDesktopCarouselApp(){
        if(!selectedDesktopCarouselApp())return
        var copy=desktopCarouselIds.slice(0);copy.splice(Math.max(0,Math.min(desktopCarouselIndex,copy.length-1)),1);desktopCarouselIds=copy;desktopCarouselIndex=Math.max(0,Math.min(desktopCarouselIndex,Math.max(0,copy.length-1)));desktopCarouselRemoveModalOpen=false;persistDesktopCarouselConfig()
    }
    function openDesktopCarouselSettings(){desktopCarouselSettingsOpen=true;desktopCarouselSettingsRow=0;desktopCarouselPickerIndex=0;desktopCarouselRemoveModalOpen=false;forceActiveFocus()}
    function closeDesktopCarouselSettings(){desktopCarouselSettingsOpen=false;forceActiveFocus()}
    function toggleCarouselPickerApp(){
        if(!baseAppList.length)return
        var app=baseAppList[Math.max(0,Math.min(desktopCarouselPickerIndex,baseAppList.length-1))]||({}),id=appIdValue(app);if(!id.length)return
        var copy=desktopCarouselIds.slice(0),existing=copy.indexOf(id)
        if(existing>=0)copy.splice(existing,1);else if(copy.length<desktopCarouselCapacity)copy.push(id);else return
        desktopCarouselIds=copy;persistDesktopCarouselConfig()
    }
    function adjustCarouselCapacity(delta){
        desktopCarouselCapacity=Math.max(1,Math.min(12,desktopCarouselCapacity+Number(delta||0)))
        if(desktopCarouselIds.length>desktopCarouselCapacity)desktopCarouselIds=desktopCarouselIds.slice(0,desktopCarouselCapacity)
        persistDesktopCarouselConfig()
    }
    function desktopHotspotActive(){
        try{var state=networkBackend&&networkBackend.offlineNetworkState?networkBackend.offlineNetworkState:({}),mode=String(state.mode||state.networkMode||"").toLowerCase();return state.hotspotEnabled===true||state.wifiHotspotEnabled===true||mode.indexOf("wifi-hotspot")>=0||mode.indexOf("hotspot-wifi")>=0}catch(e){return false}
    }
    function desktopWifiConnected(){
        if(desktopHotspotActive())return true
        return networkBackend && String(networkBackend.connectionState || "").toUpperCase() === "CONNECTED"
    }
    function desktopWifiColor(){return desktopHotspotActive()?cobaltBlue:(desktopWifiConnected()?"#22FF88":"#FF4057")}
    function desktopWifiSsid(){
        if(desktopHotspotActive()){
            var state=networkBackend.offlineNetworkState || ({})
            return String(state.hotspotSsid || state.ssid || "NeutronOS Hotspot")
        }
        if(!desktopWifiConnected())return "Offline"
        return String(networkBackend.connectedSsid || "Connected")
    }
    function controllerIdentityBlob(){var blob="";try{blob=(String(controllerBackend.controllerType||"")+" "+String(controllerBackend.controllerName||"")).toLowerCase()}catch(e){}return blob}
    function controllerFamily(){var blob=controllerIdentityBlob();if(blob.indexOf("playstation")>=0||blob.indexOf("dualshock")>=0||blob.indexOf("dualsense")>=0||blob.indexOf("sony")>=0)return"playstation";if(blob.indexOf("xbox")>=0)return"xbox";if(blob.indexOf("nintendo")>=0||blob.indexOf("switch")>=0||blob.indexOf("joy-con")>=0||blob.indexOf("joycon")>=0)return"nintendo";return"generic"}
    // NEUTRONOS_HEADER_DIRECT_CONTROL_CENTERS_V2
    // Clock/User header tabs now open their full control centers directly.
    // NEUTRONOS_CONTROLLER_COBALT_CENTERED_V3
    // Header icons are semantic vector glyphs; User and controller identity use classic cobalt blue.
    // NEUTRONOS_HEADER_CONTROLLER_PREMIUM_V3
    function controllerBadge(){var family=controllerFamily();if(family==="playstation")return"PS";if(family==="xbox")return"XB";if(family==="nintendo")return"NS";return"GC"}
    function controllerBadgeColor(){var family=controllerFamily();if(family==="playstation")return cobaltBlue;if(family==="xbox")return"#22D45B";if(family==="nintendo")return"#FF3048";return"#FFD23F"}
    function controllerDisplayName(){
        var blob=controllerIdentityBlob()
        if(blob.indexOf("dualsense")>=0)return"DualSense"
        if(blob.indexOf("dualshock")>=0)return"DualShock"
        if(blob.indexOf("sony interactive")>=0||blob.indexOf("playstation")>=0)return"DualShock"
        if(blob.indexOf("xbox")>=0&&blob.indexOf("elite")>=0)return"Xbox Elite"
        if(blob.indexOf("xbox")>=0)return"Xbox"
        if(blob.indexOf("joy-con")>=0||blob.indexOf("joycon")>=0)return"Joy-Cons"
        if(blob.indexOf("switch pro")>=0||(blob.indexOf("nintendo")>=0&&blob.indexOf("pro controller")>=0))return"Switch Pro"
        return"Speciality"
    }
    function controllerBatteryPercent(){try{if(!controllerBackend||controllerBackend.controllerBatteryAvailable===false)return-1;var value=Number(controllerBackend.controllerBatteryPercent);return isNaN(value)?-1:Math.max(0,Math.min(100,Math.round(value)))}catch(e){return-1}}
    function controllerBatteryState(){try{return String(controllerBackend&&controllerBackend.controllerBatteryState!==undefined?controllerBackend.controllerBatteryState:"").trim().toLowerCase()}catch(e){return""}}
    function controllerCharging(){try{if(controllerBackend&&controllerBackend.controllerCharging===true)return true;var state=controllerBatteryState();return state==="charging"||state==="full"}catch(e){return false}}
    function controllerDischarging(){return controllerBatteryState()==="discharging"}
    function controllerConnected(){
        if(controllerLiveKnown)return controllerLiveTransport==="usb"||controllerLiveTransport==="bluetooth"
        try{return!!(controllerBackend&&controllerBackend.controllerConnected===true)}catch(e){return false}
    }
    function controllerBluetooth(){
        if(controllerLiveKnown)return controllerLiveTransport==="bluetooth"
        try{return controllerConnected()&&!controllerCharging()&&String(controllerBackend.controllerAddress||"").trim().length>0}catch(e){return false}
    }
    function controllerLowBattery(){var value=controllerBatteryPercent();return value>=0&&value<=30&&!controllerCharging()}
    function controllerBatteryTone(){if(controllerCharging())return"#22FF88";if(controllerLowBattery())return"#FF3048";return electricBlue}
    function controllerSegmentFill(index){var value=controllerBatteryPercent();if(value<0)return 0;return Math.max(0,Math.min(1,(value-index*20)/20))}
    function controllerIconSource(){if(controllerCharging())return"../../components/controller-premium-green.png";if(controllerLowBattery())return"../../components/controller-premium-red.png";return"../../components/controller-premium-blue.png"}
    function controllerUsbPowered(){return controllerLiveKnown?controllerLiveTransport==="usb":controllerConnected()&&controllerCharging()}
    function desktopCenterChoices(){return [{id:"controller",label:"Controller Guide",detail:"Show the controller hint strip in the Desktop footer."},{id:"carousel",label:"App Carousel",detail:"Replace the center footer module with a mini app carousel preview."},{id:"hidden",label:"Remove Module",detail:"Hide the center footer module and leave the space open."}]}
    function readDesktopCenterMode(){
        try {
            if(settingsBackend&&typeof settingsBackend.value==="function"){
                var value=String(settingsBackend.value("ui.desktop.centerModule","controller")||"controller")
                if(value==="controller"||value==="carousel"||value==="hidden")return value
            }
        } catch(e) {}
        return "controller"
    }
    function refreshDesktopCenterMode(){desktopCenterMode=readDesktopCenterMode()}
    function persistDesktopCenterMode(mode){
        desktopCenterMode=mode
        try{
            if(settingsBackend&&typeof settingsBackend.queueChange==="function"){
                settingsBackend.queueChange("ui.desktop.centerModule",mode,"immediate")
                if(typeof settingsBackend.applyPending==="function")settingsBackend.applyPending()
            }
        }catch(e){}
    }
    function refreshOnboardingState(){
        try{
            controllerGuideSeen=settingsBackend&&settingsBackend.value("ui.desktop.controllerGuideSeen",false)===true
            appCarouselSeen=settingsBackend&&settingsBackend.value("ui.desktop.appCarouselSeen",false)===true
        }catch(e){controllerGuideSeen=false;appCarouselSeen=false}
    }
    function recordOnboarding(key){
        try{if(settingsBackend&&settingsBackend.setUiPreference(key,true))return true}catch(e){}
        return false
    }
    function applyDesktopCenterChoice(mode){
        persistDesktopCenterMode(mode)
        if(mode==="carousel"&&controllerGuideSeen&&recordOnboarding("ui.desktop.appCarouselSeen"))appCarouselSeen=true
        desktopCenterMenuOpen=false;forceActiveFocus()
    }
    function openDesktopCenterMenu(){
        desktopCenterMenuIndex=Math.max(0,desktopCenterChoices().map(function(choice){return choice.id}).indexOf(desktopCenterMode))
        desktopCenterMenuOpen=true
        forceActiveFocus()
    }
    function openControllerGuide(){
        desktopCenterMenuOpen=false
        controllerGuideSelection=0
        controllerWelcomeOpen=true
        if(!controllerGuideSeen&&recordOnboarding("ui.desktop.controllerGuideSeen"))controllerGuideSeen=true
        forceActiveFocus()
    }
    function openControllerSetup(){
        if(activeMode==="desktop"&&controllerRegistrationNeeded){
            controllerTabAcknowledged=true
            systemDetailRequested("controllerSettings",{source:"desktop-header",transport:"usb"})
        }else systemDetailRequested("controllerSettings",{source:activeMode==="desktop"?"desktop-header":"header",transport:controllerBluetooth()?"bluetooth":controllerConnected()?"usb":"offline"})
    }
    function refreshControllerLiveTransport(){
        if(!shellActive||selectorOnly||controllerLivePollPending)return
        controllerLivePollPending=true
        var xhr=new XMLHttpRequest()
        xhr.timeout=2500
        xhr.onreadystatechange=function(){
            if(xhr.readyState!==4)return
            root.controllerLivePollPending=false
            if(!root.shellActive)return
            if(xhr.status!==200){root.controllerLiveKnown=false;root.controllerLiveTransport="unknown";return}
            try{
                var state=JSON.parse(String(xhr.responseText||"{}"))
                root.controllerLiveKnown=state.registered===true
                root.controllerLiveTransport=root.controllerLiveKnown&&
                    (state.transport==="usb"||state.transport==="bluetooth"||state.transport==="offline")
                    ?state.transport:"unknown"
            }catch(e){root.controllerLiveKnown=false;root.controllerLiveTransport="unknown"}
        }
        xhr.onerror=function(){root.controllerLivePollPending=false;root.controllerLiveKnown=false}
        xhr.ontimeout=function(){root.controllerLivePollPending=false;root.controllerLiveKnown=false}
        xhr.open("GET","http://127.0.0.1:48173/live",true)
        xhr.send()
    }
    function controllerEventName(){
        try{
            var path=String(controllerBackend&&controllerBackend.controllerDevicePath||"")
            var found=/(?:^|\/)event([0-9]{1,5})$/.exec(path)
            return found?"event"+found[1]:""
        }catch(e){return""}
    }
    function refreshControllerRegistrationAttention(){
        if(!shellActive||activeMode!=="desktop"){
            controllerRegistrationNeeded=false
            return
        }
        var event=controllerEventName()
        if(!event.length){controllerRegistrationNeeded=false;return}
        if(controllerRegistrationPollPending)return
        controllerRegistrationPollPending=true
        var request=new XMLHttpRequest()
        request.timeout=1600
        request.onreadystatechange=function(){
            if(request.readyState!==4)return
            root.controllerRegistrationPollPending=false
            if(!root.shellActive||root.activeMode!=="desktop"||root.controllerEventName()!==event){
                root.controllerRegistrationNeeded=false;return
            }
            if(request.status!==200){root.controllerRegistrationNeeded=false;return}
            try{
                var status=JSON.parse(String(request.responseText||"{}"))
                root.controllerRegistrationNeeded=status.transport==="usb"&&status.registration_needed===true
            }catch(e){root.controllerRegistrationNeeded=false}
        }
        request.onerror=function(){root.controllerRegistrationPollPending=false;root.controllerRegistrationNeeded=false}
        request.ontimeout=function(){root.controllerRegistrationPollPending=false;root.controllerRegistrationNeeded=false}
        request.open("GET","http://127.0.0.1:48173/status?device="+encodeURIComponent(event),true)
        request.send()
    }
    function desktopCenterPreviewApps(){return desktopCarouselApps()}
    function runningDesktopApps(){
        var source=appsBackend&&appsBackend.runningApps?appsBackend.runningApps:[]
        var out=[]
        for(var i=0;i<source.length;++i){
            var entry=source[i]||({})
            if(entry.isBrowserTab===true)continue
            var id=String(entry.appId||entry.id||"")
            if(!id.length)continue
            var installed=false
            try{installed=appsBackend&&typeof appsBackend.hasApp==="function"?appsBackend.hasApp(id):true}catch(e){installed=true}
            if(installed)out.push(entry)
        }
        return out
    }
    function appIconSource(app){
        app=app||({})
        var raw=String(app.iconSource||app.iconPath||app.icon||"").trim()
        if(!raw.length)return ""
        if(raw.indexOf(":")>=0||raw.indexOf("/")>=0)return raw
        return Qt.resolvedUrl("../../../themes/Default/apps/icons/"+raw+".png")
    }
    function runtimeIcon(runtime){
        runtime=runtime||({})
        var raw=String(runtime.icon||runtime.poster||"").trim()
        if(raw.length)return raw
        var id=String(runtime.appId||runtime.id||"")
        try{
            if(appsBackend&&typeof appsBackend.appById==="function"){
                var app=appsBackend.appById(id)||({})
                raw=String(app.iconSource||app.iconPath||app.icon||"").trim()
                if(raw.length){if(raw.indexOf(":")>=0||raw.indexOf("/")>=0)return raw;return Qt.resolvedUrl("../../../themes/Default/apps/icons/"+raw+".png")}
            }
        }catch(e){}
        return ""
    }
    function focusRuntime(runtime){
        try{if(appsBackend&&runtime&&runtime.canFocus===true&&typeof appsBackend.focusRuntime==="function")appsBackend.focusRuntime(String(runtime.runtimeId||""))}catch(e){}
    }
    function activateHeaderTab(index){
        headerIndex=Math.max(0,Math.min(4,Number(index)))
        zone=3
        syncControllerContext()
        forceActiveFocus()
        if(activeMode==="desktop"){
            if(headerIndex===0)systemDetailRequested("network",{source:"desktop-header",wifiOnly:true})
            else if(headerIndex===1)notificationCenterRequested()
            else if(headerIndex===2)systemDetailRequested("headerSecurity",{source:"desktop-header"})
            else if(headerIndex===3)systemDetailRequested("user",{source:"desktop-header",user:activeUser})
            else {controllerTabAcknowledged=true;systemDetailRequested("controllerPromo",{source:"desktop-header"})}
            return
        }
        if(headerIndex===0)systemDetailRequested("clock",{source:"header"})
        else if(headerIndex===1)systemDetailRequested("network",{source:"header",wifiOnly:true})
        else if(headerIndex===2)systemDetailRequested("headerSecurity",{source:"header"})
        else if(headerIndex===3)systemDetailRequested("user",{source:"header",user:activeUser})
        else systemDetailRequested("controllerPromo",{source:"header"})
    }
    function glyph(action){var family=controllerFamily();if(family==="playstation")return action==="primary"?"×":action==="cancel"?"○":action==="context"?"△":"□";if(family==="xbox")return action==="primary"?"A":action==="cancel"?"B":action==="context"?"Y":"X";if(family==="nintendo")return action==="primary"?"B":action==="cancel"?"A":action==="context"?"X":"Y";return action==="primary"?"1":action==="cancel"?"2":action==="context"?"3":"4"}
    function ensureDesktopGridMetrics(){
        if(desktopGridInitialized||width<=0||height<=0)return
        desktopScreenWidth=Math.round(width)
        desktopScreenHeight=Math.round(height)
        desktopGridColumns=20
        desktopGridRows=10
        var workspaceHeight=Math.max(1,height-desktopChromeHeight*2)
        var safeWidth=Math.max(1,width-desktopSafeInset*2)
        desktopGridCellSize=Math.floor(Math.min(safeWidth/desktopGridColumns,workspaceHeight/desktopGridRows))
        desktopGridInitialized=desktopGridCellSize>0
    }
    function controllerWelcomeSeen(){
        try{return settingsBackend&&typeof settingsBackend.value==="function"&&settingsBackend.value("ui.desktop.controllerGuideSeen",false)===true}catch(e){return false}
    }
    function maybeOpenControllerWelcome(){
        if(controllerWelcomeChecked||!shellActive||!activeUser)return
        controllerWelcomeChecked=true
        if(!controllerWelcomeSeen())controllerWelcomeDelay.restart()
    }
    function dismissControllerWelcome(){
        controllerWelcomeOpen=false
        forceActiveFocus()
    }
    function currentApp(){return appList.length?appList[Math.max(0,Math.min(appIndex,appList.length-1))]:null}
    function wrapAppIndex(index){var count=appList.length;if(count<=0)return 0;return ((index%count)+count)%count}
    function selectAppIndex(index){appIndex=wrapAppIndex(index);var a=currentApp();selectedAppId=a?String(a.id||""):""}
    function selectAppById(appId){var id=String(appId||"");for(var i=0;i<appList.length;++i)if(String(appList[i].id||"")===id){selectAppIndex(i);return true}return false}
    function previewAppList(){
        var output=[];for(var i=0;i<baseAppList.length;++i)output.push(baseAppList[i])
        if(!appMoveMode||appMoveOriginalIndex<0||appMoveCandidateIndex<0||appMoveOriginalIndex>=output.length)return output
        var moved=output.splice(appMoveOriginalIndex,1)[0];output.splice(Math.max(0,Math.min(output.length,appMoveCandidateIndex)),0,moved);return output
    }
    function beginAppMove(app){
        if(!app)return false
        movingAppId=String(app.id||"");appMoveOriginalIndex=-1
        for(var i=0;i<baseAppList.length;++i)if(String(baseAppList[i].id||"")===movingAppId){appMoveOriginalIndex=i;break}
        if(appMoveOriginalIndex<0)return false
        appMoveCandidateIndex=appMoveOriginalIndex;appMoveMode=true;appIndex=appMoveCandidateIndex;zone=1;forceActiveFocus();return true
    }
    function finishAppMove(commit){
        if(!appMoveMode)return false
        var id=movingAppId,target=appMoveCandidateIndex
        appMoveMode=false;movingAppId="";appMoveOriginalIndex=-1;appMoveCandidateIndex=-1
        if(commit&&appsBackend&&appsBackend.moveFavorite)appsBackend.moveFavorite(id,target)
        appIndex=Math.max(0,Math.min(Math.max(0,baseAppList.length-1),target));return true
    }
    function selectMode(index){
        var nextIndex=Math.max(0,Math.min(modes.length-1,index))
        var nextMode=modes[nextIndex].id
        if(activeMode==="desktop"&&activeView.item&&typeof activeView.item.resetInteractionState==="function")activeView.item.resetInteractionState()
        selectorIndex=nextIndex;activeMode=nextMode;selectorOpen=false;selectorOnly=false;zone=0;headerIndex=0;footerIndex=0;syncControllerContext();dashboardModeRequested(activeMode);forceActiveFocus()
    }
    function openSelector(){selectorIndex=Math.max(0,modes.map(function(m){return m.id}).indexOf(activeMode));selectorOpen=true;forceActiveFocus()}
    function closeSelector(){selectorOpen=false;selectorOnly=false;dashboardModeRequested(activeMode);forceActiveFocus()}
    function returnHomeTab(){var target=layoutBackend?String(layoutBackend.homeTab||"system"):"system";var found=modes.map(function(m){return String(m.id)}).indexOf(target)>=0;activeMode=found?target:"system";selectorOpen=false;selectorOnly=false;zone=0;dashboardModeRequested(activeMode);forceActiveFocus()}
    function registerCancelTap(){cancelTapCount++;cancelTapReset.restart();if(cancelTapCount>=ControllerFeatures.circleHomePressCount){cancelTapReset.stop();cancelTapCount=0;returnHomeTab()}return true}
    function openSecurityIncident(incident){activeMode="security";selectorOpen=false;zone=0;Qt.callLater(function(){contextModal.openModal("details","security",{incident:incident||({})})})}
    function showDetails(kind,data){
        if(kind==="security-summary")contextModal.openModal("security-summary",kind,data)
        else if(kind==="security-threat")contextModal.openModal("security-threat",kind,data)
        else if(kind==="application"||kind==="security")contextModal.openModal("details",kind,data)
        else if(kind==="media-storage"){
            var storageContext=data||({});storageContext.storageSlot=1
            systemDetailRequested("storage",storageContext)
        }
        else if(kind==="user-clock")systemDetailRequested("clock",data||({}))
        else if(kind==="uptime")systemDetailRequested("controllerSettings",data||({}))
        else systemDetailRequested(kind,data||({}))
    }
    function showActions(kind,data){
        // Storage operations belong to the established Storage Manager, which
        // owns device validation, authorization and deliberate confirmations.
        if(kind==="storage"||kind==="media-storage")systemDetailRequested("storage",data||({}))
        else contextModal.openModal("actions",kind,data)
    }
    function launchApp(app){
        if(!app)return
        // X always opens the selected application UI. Runtime/service actions
        // belong in the app itself or the Square actions menu, not in launch.
        appLaunchRequested(app)
    }
    function handleControllerPressed(action){
        if(controllerWelcomeOpen){
            if(action==="up"||action==="down"){controllerGuideSelection=1-controllerGuideSelection;return true}
            if(action==="secondary"){dismissControllerWelcome();openDesktopCenterMenu();return true}
            if(action==="primary"){
                if(controllerGuideSelection===1){applyDesktopCenterChoice("carousel");dismissControllerWelcome()}
                else dismissControllerWelcome()
                return true
            }
            if(action==="cancel"||action==="home"){dismissControllerWelcome();return true}
            return true
        }
        if(desktopCarouselRemoveModalOpen){
            if(action==="cancel"){removeSelectedDesktopCarouselApp();return true}
            return true
        }
        if(desktopCarouselSettingsOpen){
            if(action==="cancel"){closeDesktopCarouselSettings();return true}
            if(action==="up"){desktopCarouselSettingsRow=Math.max(0,desktopCarouselSettingsRow-1);return true}
            if(action==="down"){desktopCarouselSettingsRow=Math.min(1,desktopCarouselSettingsRow+1);return true}
            if(action==="left"){
                if(desktopCarouselSettingsRow===0)adjustCarouselCapacity(-1)
                else desktopCarouselPickerIndex=Math.max(0,desktopCarouselPickerIndex-1)
                return true
            }
            if(action==="right"){
                if(desktopCarouselSettingsRow===0)adjustCarouselCapacity(1)
                else desktopCarouselPickerIndex=Math.min(Math.max(0,baseAppList.length-1),desktopCarouselPickerIndex+1)
                return true
            }
            if(action==="primary"&&desktopCarouselSettingsRow===1){toggleCarouselPickerApp();return true}
            return true
        }
        if(desktopCarouselMoveMode){
            // Carousel move is deliberately one step per physical press. Main
            // suppresses directional repeat while this state is active.
            if(action==="left"){if(acceptDesktopCarouselDirection(action))moveDesktopCarousel(-1);return true}
            if(action==="right"){if(acceptDesktopCarouselDirection(action))moveDesktopCarousel(1);return true}
            if(action==="primary"||action==="context"){finishDesktopCarouselMove(true);return true}
            if(action==="cancel"){finishDesktopCarouselMove(false);return true}
            return true
        }
        if(desktopCenterMenuOpen){
            if(action==="cancel"){desktopCenterMenuOpen=false;forceActiveFocus();return true}
            if(action==="up"||action==="left"){desktopCenterMenuIndex=(desktopCenterMenuIndex+desktopCenterChoices().length-1)%desktopCenterChoices().length;return true}
            if(action==="down"||action==="right"){desktopCenterMenuIndex=(desktopCenterMenuIndex+1)%desktopCenterChoices().length;return true}
            if(action==="primary"){applyDesktopCenterChoice(desktopCenterChoices()[desktopCenterMenuIndex].id);return true}
            return true
        }
        if(appMoveMode){if(action==="left"){appMoveCandidateIndex=Math.max(0,appMoveCandidateIndex-1);appIndex=appMoveCandidateIndex}else if(action==="right"){appMoveCandidateIndex=Math.min(Math.max(0,baseAppList.length-1),appMoveCandidateIndex+1);appIndex=appMoveCandidateIndex}else if(action==="primary")finishAppMove(true);else if(action==="cancel")finishAppMove(false);return true}
        if(overviewManager.opened)return overviewManager.handleControllerPressed(action)
        if(contextModal.opened)return contextModal.handleControllerPressed(action)
        if(runningAppsTray.opened)return runningAppsTray.handleControllerPressed(action)
        if(selectorOpen){if(action==="home"||action==="cancel")closeSelector();else if(action==="up")selectorIndex=Math.max(0,selectorIndex-1);else if(action==="down")selectorIndex=Math.min(modes.length-1,selectorIndex+1);else if(action==="primary")selectMode(selectorIndex);return true}
        if(activeView.item&&activeView.item.controllerModalOpen===true){
            if(activeView.item.handleControllerPressed)return activeView.item.handleControllerPressed(action)
            return true
        }
        if(action==="home"){openSelector();return true}
        if(action==="system"||action==="options"||action==="menu"){
            if(activeMode==="desktop"&&commandTarget==="footer"&&footerIndex===1){
                if(!controllerGuideSeen||!appCarouselSeen)openControllerGuide()
                else openDesktopCenterMenu()
                return true
            }
            if(activeMode==="desktop"&&commandTarget==="dashboard"&&activeView.item&&activeView.item.handleControllerPressed)
                return activeView.item.handleControllerPressed(action)
            systemHoldConsumed=false;systemHoldTimer.restart();return true
        }
        if(action==="cancel"){
            if(activeMode==="desktop"&&commandTarget==="footer"&&footerIndex===1){
                if(desktopCenterMode==="carousel"&&selectedDesktopCarouselApp())desktopCarouselRemoveModalOpen=true
                return true
            }
            return registerCancelTap()
        }
        if(commandTarget==="header"){
            if(action==="left")headerIndex=(headerIndex+4)%5
            else if(action==="right")headerIndex=(headerIndex+1)%5
            else if(action==="down"){zone=0;syncControllerContext()}
            else if(action==="up")notificationCenterRequested()
            else if(action==="context"&&headerIndex===4)openControllerSetup()
            else if(action==="secondary"&&headerIndex===2)securityCompactScoreView=!securityCompactScoreView
            else if(action==="primary")activateHeaderTab(headerIndex)
            return true
        }
        if(commandTarget==="dashboard"){return activeView.item&&activeView.item.handleControllerPressed?actionHandled(activeView.item,action):true}
        if(commandTarget==="application"){if(action==="left")selectAppIndex(appIndex-1);else if(action==="right")selectAppIndex(appIndex+1);else if(action==="up")zone=0;else if(action==="down")zone=2;else if(action==="primary")launchApp(currentApp());else if(action==="context"&&currentApp())contextModal.openModal("details","application",{app:currentApp()});else if(action==="secondary"&&currentApp())contextModal.openModal("actions","application",{app:currentApp()});return true}
        if(commandTarget==="footer"){
            var footerCount=activeMode==="desktop"?9:7
            if(activeMode==="desktop"&&footerIndex===1){
                if(desktopCenterMode==="carousel"){
                    var carouselCount=desktopCarouselResolvedApps.length
                    if(action==="left"){
                        if(!acceptDesktopCarouselDirection(action))return true
                        if(desktopCarouselIndex>0)desktopCarouselIndex--
                        else footerIndex=0
                    }else if(action==="right"){
                        if(!acceptDesktopCarouselDirection(action))return true
                        if(desktopCarouselIndex<carouselCount-1)desktopCarouselIndex++
                        else footerIndex=2
                    }else if(action==="up"){
                        if(!acceptDesktopCarouselDirection(action))return true
                        zone=0;syncControllerContext()
                    }else if(action==="primary"){
                        var selectedCarouselApp=selectedDesktopCarouselApp();if(selectedCarouselApp)launchApp(selectedCarouselApp)
                    }else if(action==="context"){
                        beginDesktopCarouselMove()
                    }else if(action==="secondary"){
                        openDesktopCarouselSettings()
                    }
                    return true
                }
                if(action==="left")footerIndex=0
                else if(action==="right")footerIndex=2
                else if(action==="up"){zone=0;syncControllerContext()}
                // Controller Guide and Hidden are passive. Start/Menu is the
                // only action that changes this center module.
                return true
            }
            if(action==="left")footerIndex=(footerIndex+footerCount-1)%footerCount
            else if(action==="right")footerIndex=(footerIndex+1)%footerCount
            else if(action==="up"){zone=0;syncControllerContext()}
            else if(action==="primary")activateFooter()
            return true
        }
        return true
    }
    function handleSharedCarouselPressed(action) {
        var oldZone=zone, oldFooter=footerIndex, oldMode=desktopCenterMode
        zone=2; footerIndex=1; desktopCenterMode="carousel"
        try { return handleControllerPressed(action) }
        finally { zone=oldZone; footerIndex=oldFooter; desktopCenterMode=oldMode }
    }
    function handleControllerReleased(action){
        releaseDesktopCarouselDirection(action)
        if(overviewManager.opened)return overviewManager.handleControllerReleased(action)
        if(action==="system"){if(systemHoldTimer.running)systemHoldTimer.stop();systemHoldConsumed=false;return true}
        return true
    }
    function actionHandled(item,action){return item.handleControllerPressed(action)}
    function activateFooter(){
        if(activeMode==="desktop"){
            if(footerIndex===0){searchRequested();return}
            if(footerIndex===1){
                if(desktopCenterMode==="carousel"){
                    var app=selectedDesktopCarouselApp();if(app)launchApp(app)
                }
                return
            }
            if(footerIndex===8){runningAppsTray.openTray();return}
            quickActionRequested(["power","help","lock","network","bluetooth","notifications"][footerIndex-2])
            return
        }
        if(footerIndex===6)runningAppsTray.openTray();else quickActionRequested(["power","help","lock","network","bluetooth","notifications"][footerIndex])
    }
    function userName(){try{return String(activeUser.displayName||activeUser.username||"User")}catch(e){return"User"}}
    // NEUTRONOS_HEADER_CONTROLLER_ROLE_V1
    function userRole(){
        try {
            var role=String(activeUser.role||activeUser.accountRole||activeUser.userRole||"").trim().toLowerCase()
            if(role.indexOf("admin")>=0)return"Admin"
            if(role.length>0)return"User"
        } catch(e) {}
        return"User"
    }
    function userAvatarSource(){try{return String(activeUser.resolvedAvatarSource||activeUser.avatarSource||activeUser.avatar||activeUser.profileIcon||"")}catch(e){return""}}
    onActiveUserChanged:{
        var username=activeUser&&activeUser.username?String(activeUser.username):"default"
        if(layoutBackend&&layoutBackend.setActiveUser)layoutBackend.setActiveUser(username)
        if(appsBackend&&appsBackend.setActiveUser)appsBackend.setActiveUser(username)
        var destination=layoutBackend?String(layoutBackend.defaultTab||"desktop"):"desktop"
        activeMode=modes.map(function(m){return String(m.id)}).indexOf(destination)>=0?destination:"desktop"
        controllerTabAcknowledged=false;refreshOnboardingState();zone=0;desktopLayoutLoaded=false;desktopDefaultsInitialized=false;desktopItems=[];desktopBootstrapAttempts=0;desktopBootstrapComplete=false
        if(shellActive)desktopBootstrapTimer.restart()
    }
    onSettingsBackendChanged:{
        refreshHeaderClockIcon();refreshDesktopCenterMode();refreshDesktopIconSizeMode();refreshOnboardingState()
        if(shellActive)desktopBootstrapTimer.restart()
    }
    onDesktopIconSizeModeChanged:{if(activeView.item&&"iconSizeMode" in activeView.item)activeView.item.iconSizeMode=desktopIconSizeMode}
    onShellActiveChanged:{
        if(shellActive){
            var destination=layoutBackend?String(layoutBackend.defaultTab||"desktop"):"desktop"
            activeMode=modes.map(function(m){return String(m.id)}).indexOf(destination)>=0?destination:"desktop"
            refreshOnboardingState()
            // Post-login initialization is intentionally deferred so Console
            // can paint before manifest/layout/carousel work begins.
            desktopBootstrapAttempts=0
            desktopBootstrapTimer.restart()
        }else{
            controllerTabAcknowledged=false
            desktopBootstrapTimer.stop()
            if(desktopLayoutPending.length)flushDesktopLayout()
        }
    }
    onWidthChanged: ensureDesktopGridMetrics()
    onHeightChanged: ensureDesktopGridMetrics()
    Component.onCompleted:{refreshHeaderClockIcon();refreshDesktopCenterMode();refreshDesktopIconSizeMode();refreshOnboardingState();ensureDesktopGridMetrics()}
    onAppListChanged:{
        if(shellActive){restoreDesktopCarouselConfig();if(!desktopLayoutLoaded)desktopBootstrapTimer.restart()}
        if(appMoveMode)return
        if(selectedAppId.length>0&&selectAppById(selectedAppId))return
        selectAppIndex(Math.max(0,Math.min(appIndex,Math.max(0,appList.length-1))))
    }
    onZoneChanged:syncControllerContext()
    Connections{
        target:root.settingsBackend
        enabled:target!==null
        ignoreUnknownSignals:true
        function onOperationFinished(){root.refreshDesktopIconSizeMode();root.refreshDesktopCenterMode()}
    }
    Timer{id:desktopBootstrapTimer;interval:160;repeat:false;onTriggered:{if(!root.shellActive)return;root.restoreDesktopCarouselConfig();root.restoreOrSeedDesktopLayout()}}
    Timer{id:desktopLayoutPersistTimer;interval:240;repeat:false;onTriggered:root.flushDesktopLayout()}
    Timer{id:controllerRegistrationAttentionTimer;interval:2300;running:root.shellActive&&root.activeMode==="desktop"&&!root.selectorOnly;repeat:true;triggeredOnStart:true;onTriggered:root.refreshControllerRegistrationAttention()}
    Timer{id:controllerLiveTransportTimer;interval:750;running:root.shellActive&&!root.selectorOnly;repeat:true;triggeredOnStart:true;onTriggered:root.refreshControllerLiveTransport()}
    Timer{interval:1000;running:root.visible&&root.shellActive&&!root.clockBackend;repeat:true;onTriggered:root.now=new Date()}
    Timer{id:systemHoldTimer;interval:ControllerFeatures.dashboardManagerHoldMs;repeat:false;onTriggered:{root.systemHoldConsumed=true;overviewManager.openManager()}}
    Timer{id:cancelTapReset;interval:ControllerFeatures.circleHomeWindowMs;repeat:false;onTriggered:root.cancelTapCount=0}
    Timer{id:controllerWelcomeDelay;interval:650;repeat:false;onTriggered:root.controllerWelcomeOpen=true}
    Image{anchors.fill:parent;visible:!root.selectorOnly;source:"../../../themes/Default/screensavers/Nebula.png";fillMode:Image.PreserveAspectCrop;cache:true}
    Rectangle{anchors.fill:parent;visible:!root.selectorOnly;color:"#B8000410"}

    Item{id:header;visible:!root.selectorOnly&&root.activeMode!=="desktop";anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:150*root.uiScale
        Rectangle{x:38;y:42;width:270;height:58;radius:14;color:"#A20A1727";border.width:selectorOpen?2:1;border.color:selectorOpen?theme.cyan:"#29405A";Row{anchors.centerIn:parent;spacing:13;Text{text:"▦";color:theme.cyan;font.pixelSize:24}Text{text:root.modes[Math.max(0,root.modes.map(function(m){return m.id}).indexOf(root.activeMode))].label;color:"white";font.pixelSize:17}}}
        Row{anchors.right:parent.right;anchors.rightMargin:34;anchors.top:parent.top;anchors.topMargin:25;spacing:8
            HeaderStatusItem{id:clockHeaderTab;width:170;height:62;selected:root.zone===3&&root.headerIndex===0;iconKind:root.clockHeaderIconKind();primary:clockBackend?String(clockBackend.currentTimeText||"--:--"):Qt.formatTime(root.now,"h:mm AP");secondary:Qt.formatDate(root.now,"MMM d, yyyy");statusColor:theme.muted;onActivated:root.activateHeaderTab(0)}
            HeaderStatusItem{id:wifiHeaderTab;objectName:"desktopWifiHeader";width:170;height:62;selected:root.zone===3&&root.headerIndex===1;iconKind:"wifi";primary:root.desktopWifiSsid();secondary:root.desktopWifiConnected()?"Connected":"Offline";statusColor:root.desktopWifiColor();onActivated:root.activateHeaderTab(1)}
            HeaderStatusItem{id:securityHeaderTab;width:170;height:62;selected:root.zone===3&&root.headerIndex===2;iconKind:root.headerSecurityIcon();primary:"Security";secondary:root.headerSecurityLabel();statusColor:root.headerSecurityColor();attention:root.headerSecurityScore()>=0&&root.headerSecurityScore()<55;onActivated:root.activateHeaderTab(2)}
            HeaderStatusItem{id:userHeaderTab;width:170;height:62;selected:root.zone===3&&root.headerIndex===3;imageSource:root.userAvatarSource();iconKind:root.userAvatarSource().length>0?"":"user";primary:root.userName();secondary:root.userRole();statusColor:root.cobaltBlue;selectionColor:root.cobaltBlue;onActivated:root.activateHeaderTab(3)}
            Rectangle {
                id: controllerHeaderTile
                width: 170
                height: 62
                radius: 12
                color: root.zone===3&&root.headerIndex===4 ? "#B00A1C32" : "#A0070D19"
                border.width: root.zone===3&&root.headerIndex===4 ? 2 : 1
                border.color: root.zone===3&&root.headerIndex===4 ? root.cobaltBlue : "#30415D72"

                property real blinkLevel: 0.20
                SequentialAnimation on blinkLevel {
                    running: controllerHeaderTile.visible && root.controllerConnected() &&
                             ((root.controllerCharging() && root.controllerBatteryPercent()<100) || root.controllerLowBattery())
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.18; to: 0.92; duration: 430; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.92; to: 0.18; duration: 430; easing.type: Easing.InOutQuad }
                }

                Rectangle { anchors.fill:parent;anchors.margins:-6;radius:18;color:"transparent";border.width:root.zone===3&&root.headerIndex===4?2:0;border.color:"#660047AB";visible:root.zone===3&&root.headerIndex===4;z:-1 }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    height: 29
                    spacing: 5
                    visible: root.controllerConnected()

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.controllerBadgeColor()
                        border.width: 1
                        border.color: "#E8F8FF"
                        Text { anchors.centerIn:parent;text:root.controllerBadge();color:"white";font.pixelSize:9;font.bold:true }
                    }

                    Item {
                        width: 34; height: 26
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.centerIn: parent
                            width: 38; height: 38
                            source: root.controllerIconSource()
                            sourceSize.width: 192; sourceSize.height: 192
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: false; cache: true
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: 5
                            Item {
                                width: 7; height: 18
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                readonly property real segmentFill: root.controllerSegmentFill(index)
                                readonly property bool pendingCharge: root.controllerCharging() && segmentFill<1
                                readonly property bool pendingLow: root.controllerLowBattery() && segmentFill<1
                                Rectangle {
                                    anchors.fill: parent; radius: 2
                                    color: parent.pendingCharge || parent.pendingLow ? root.controllerBatteryTone() : "#142434"
                                    opacity: parent.pendingCharge || parent.pendingLow ? controllerHeaderTile.blinkLevel : 0.62
                                    border.width: 1
                                    border.color: root.controllerBatteryTone()
                                }
                                Rectangle {
                                    anchors.left: parent.left; anchors.bottom: parent.bottom
                                    width: parent.width * parent.segmentFill; height: parent.height; radius: 2
                                    color: root.controllerBatteryTone()
                                    opacity: parent.segmentFill>0 ? 1.0 : 0.0
                                }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.controllerBatteryPercent()>=0 ? String(root.controllerBatteryPercent())+"%" : "--%"
                        color: root.controllerBatteryTone()
                        font.pixelSize: 11; font.bold: true
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                    width: parent.width - 16
                    visible: root.controllerConnected()
                    text: root.controllerDisplayName()
                    color: root.cobaltBlue
                    font.pixelSize: 11; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text { anchors.centerIn:parent;visible:!root.controllerConnected();text:"Controller  •  Offline";color:theme.muted;font.pixelSize:12;font.bold:true }
                MouseArea { anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.activateHeaderTab(4) }
            }
        }
    }
    Item {
        id: desktopHeader
        visible: !root.selectorOnly && root.activeMode === "desktop"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.desktopChromeHeight
        z: 35

        Rectangle {
            id: desktopSelectionNameplate
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: 27*root.uiScale
            width: Math.min(parent.width*0.34, Math.max(150*root.uiScale, desktopSelectionText.implicitWidth+34*root.uiScale))
            radius: height/2
            visible: desktopSelectionText.text.length>0
            color: root.controllerRegistrationAttention&&root.zone===3&&root.headerIndex===4 ? "#B3443100" : "#B33A0B16"
            border.width: 1
            border.color: root.controllerRegistrationAttention&&root.zone===3&&root.headerIndex===4 ? "#FFD45A" : "#A8FF4057"
            Rectangle{anchors.fill:parent;anchors.margins:2*root.uiScale;radius:parent.radius-2*root.uiScale;color:"#360F1628"}
            Text {
                id: desktopSelectionText
                anchors.centerIn: parent
                width: parent.width-24*root.uiScale
                text: root.controllerRegistrationAttention&&root.zone===3&&root.headerIndex===4 ? "Press Triangle" : (root.controllerGuideNeedsAttention&&root.zone===2&&root.footerIndex===1 ? "Press Options" : (activeView.item && ("currentHighlightTitle" in activeView.item) ? String(activeView.item.currentHighlightTitle || "") : ""))
                color: (root.controllerRegistrationAttention&&root.zone===3&&root.headerIndex===4)||(root.controllerGuideNeedsAttention&&root.zone===2&&root.footerIndex===1) ? "#FFD45A" : "#FFFFFF"
                font.pixelSize: 9.5*root.uiScale
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.uiScale
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.uiScale

            Rectangle {
                width:112*root.uiScale;height:28*root.uiScale;radius:9*root.uiScale
                color:root.zone===3&&root.headerIndex===0?"#14304A":"#A0070D19";border.width:root.zone===3&&root.headerIndex===0?2:1;border.color:root.zone===3&&root.headerIndex===0?"#4DA6FF":"#294866"
                Row {
                    anchors.left:parent.left;anchors.leftMargin:8*root.uiScale
                    anchors.verticalCenter:parent.verticalCenter;spacing:6*root.uiScale
                    Item {
                        width:18*root.uiScale;height:18*root.uiScale
                        // NEUTRONOS_DESKTOP_WIFI_GLYPH_REPAINT_V271
                        Canvas {
                            anchors.fill:parent
                            antialiasing:true
                            property color glyphColor:root.desktopWifiColor()
                            onGlyphColorChanged:requestPaint()
                            onWidthChanged:requestPaint()
                            onHeightChanged:requestPaint()
                            onVisibleChanged:requestPaint()
                            Component.onCompleted:requestPaint()
                            onPaint:{
                                var ctx=getContext("2d")
                                ctx.clearRect(0,0,width,height)
                                ctx.strokeStyle=glyphColor
                                ctx.fillStyle=glyphColor
                                ctx.lineCap="round"
                                ctx.lineJoin="round"
                                ctx.lineWidth=Math.max(1.5,width*.10)
                                var cx=width*.50,base=height*.76
                                var radii=[width*.38,width*.27,width*.16]
                                for(var wi=0;wi<radii.length;++wi){
                                    ctx.beginPath()
                                    ctx.arc(cx,base,radii[wi],Math.PI*1.22,Math.PI*1.78)
                                    ctx.stroke()
                                }
                                ctx.beginPath()
                                ctx.arc(cx,base,width*.055,0,Math.PI*2)
                                ctx.fill()
                            }
                        }
                    }
                    Column{anchors.verticalCenter:parent.verticalCenter;spacing:0
                        Text{text:"Wi-Fi";color:"#F4FBFF";font.pixelSize:9*root.uiScale;font.bold:true}
                        Text{text:root.desktopWifiSsid();color:root.desktopWifiColor();font.pixelSize:6.5*root.uiScale;font.bold:true;elide:Text.ElideRight;width:72*root.uiScale}
                    }
                }
                MouseArea{anchors.fill:parent;onClicked:root.activateHeaderTab(0)}
            }
            Rectangle {
                width:126*root.uiScale;height:28*root.uiScale;radius:9*root.uiScale
                color:root.zone===3&&root.headerIndex===1?"#14304A":"#A0070D19";border.width:root.zone===3&&root.headerIndex===1?2:1;border.color:root.zone===3&&root.headerIndex===1?"#4DA6FF":"#294866"
                Row{anchors.left:parent.left;anchors.leftMargin:8*root.uiScale;anchors.verticalCenter:parent.verticalCenter;spacing:7*root.uiScale;Rectangle{width:18*root.uiScale;height:18*root.uiScale;radius:9*root.uiScale;color:notificationBackend&&Number(notificationBackend.unreadCount||0)>0?"#3A101A":"#0B1A30";border.width:1;border.color:notificationBackend&&Number(notificationBackend.unreadCount||0)>0?"#FF4057":"#315D86";Text{anchors.centerIn:parent;text:"!";color:notificationBackend&&Number(notificationBackend.unreadCount||0)>0?"#FF6577":"#7DF9FF";font.pixelSize:10*root.uiScale;font.bold:true}}Column{anchors.verticalCenter:parent.verticalCenter;spacing:0;Text{text:"Notifications";color:"#F4FBFF";font.pixelSize:7.8*root.uiScale;font.bold:true}Text{text:String(notificationBackend?Number(notificationBackend.unreadCount||0):0)+" unread";color:"#8AA6C8";font.pixelSize:6.5*root.uiScale}}}
                MouseArea{anchors.fill:parent;onClicked:root.activateHeaderTab(1)}
            }
            Rectangle {
                id: desktopSecurityTab
                width:116*root.uiScale;height:28*root.uiScale;radius:9*root.uiScale
                color:root.zone===3&&root.headerIndex===2?"#14304A":"#A0070D19"
                border.width:root.zone===3&&root.headerIndex===2?2:1
                border.color:root.zone===3&&root.headerIndex===2?"#4DA6FF":root.headerSecurityColor()
                property real alertPulse: .22
                readonly property bool unsecure: root.headerSecurityScore()>=0 && root.headerSecurityScore()<55
                SequentialAnimation on alertPulse {
                    running: desktopSecurityTab.visible && desktopSecurityTab.unsecure
                    loops: Animation.Infinite
                    NumberAnimation { from:.18;to:.95;duration:520;easing.type:Easing.InOutQuad }
                    NumberAnimation { from:.95;to:.18;duration:520;easing.type:Easing.InOutQuad }
                }
                Rectangle {
                    anchors.fill:parent;anchors.margins:-5*root.uiScale;radius:14*root.uiScale
                    visible:desktopSecurityTab.unsecure;color:"transparent";border.width:2*root.uiScale
                    border.color:"#FF3048";opacity:desktopSecurityTab.alertPulse;z:-1
                }
                Row {
                    anchors.left:parent.left;anchors.leftMargin:8*root.uiScale
                    anchors.verticalCenter:parent.verticalCenter;spacing:7*root.uiScale
                    visible:!root.securityCompactScoreView
                    SemanticStatusIcon {
                        width:18*root.uiScale
                        height:18*root.uiScale
                        anchors.verticalCenter:parent.verticalCenter
                        // One shared icon for both headers; all three states are explicit.
                        kind:root.headerSecurityIcon()
                        accent:root.headerSecurityColor()
                    }
                    Column{anchors.verticalCenter:parent.verticalCenter;spacing:0
                        Text{text:"Security";color:"#F4FBFF";font.pixelSize:9*root.uiScale;font.bold:true}
                        Text{text:root.headerSecurityLabel();color:root.headerSecurityColor();font.pixelSize:6.5*root.uiScale;font.bold:true}
                    }
                }
                SecurityScorePresentation {
                    visible:root.securityCompactScoreView
                    anchors.fill:parent
                    anchors.leftMargin:8*root.uiScale
                    anchors.rightMargin:8*root.uiScale
                    anchors.topMargin:4*root.uiScale
                    anchors.bottomMargin:4*root.uiScale
                    backend:root.securityBackend
                    uiScale:root.uiScale
                    labelPixelSize:8.4
                    barHeight:5
                }
                MouseArea{anchors.fill:parent;onClicked:root.activateHeaderTab(2)}
            }
            Rectangle {
                width:108*root.uiScale;height:28*root.uiScale;radius:9*root.uiScale
                color:root.zone===3&&root.headerIndex===3?"#102653":"#A0070D19";border.width:root.zone===3&&root.headerIndex===3?2:1;border.color:root.zone===3&&root.headerIndex===3?root.cobaltBlue:"#294866"
                Row{anchors.left:parent.left;anchors.leftMargin:8*root.uiScale;anchors.verticalCenter:parent.verticalCenter;spacing:6*root.uiScale;Rectangle{width:20*root.uiScale;height:20*root.uiScale;radius:10*root.uiScale;color:"#071426";clip:true;Image{anchors.fill:parent;visible:root.userAvatarSource().length>0;source:root.userAvatarSource();fillMode:Image.PreserveAspectCrop}Text{anchors.centerIn:parent;visible:root.userAvatarSource().length===0;text:"U";color:"#7DF9FF";font.pixelSize:10*root.uiScale;font.bold:true}}Column{anchors.verticalCenter:parent.verticalCenter;spacing:0;Text{text:root.userName();color:"#F4FBFF";font.pixelSize:8.5*root.uiScale;font.bold:true;elide:Text.ElideRight;width:70*root.uiScale}Text{text:root.userRole();color:"#8AA6C8";font.pixelSize:6.5*root.uiScale}}}
                MouseArea{anchors.fill:parent;onClicked:root.activateHeaderTab(3)}
            }
            Rectangle {
                width:184*root.uiScale;height:28*root.uiScale;radius:9*root.uiScale
                color:root.controllerRegistrationAttention?"#3F3008":root.zone===3&&root.headerIndex===4?"#102653":"#A0070D19"
                border.width:root.controllerRegistrationAttention?2:root.zone===3&&root.headerIndex===4?2:1
                border.color:root.controllerRegistrationAttention?"#FFD45A":root.zone===3&&root.headerIndex===4?root.cobaltBlue:"#294866"
                Rectangle {
                    anchors.fill:parent;radius:parent.radius;color:"#44FFD45A";border.width:2;border.color:"#FFD45A"
                    visible:root.controllerRegistrationAttention
                    SequentialAnimation on opacity {
                        running:root.controllerRegistrationAttention&&root.shellActive&&root.activeMode==="desktop"
                        loops:Animation.Infinite
                        NumberAnimation{from:0.08;to:0.92;duration:490;easing.type:Easing.InOutSine}
                        NumberAnimation{from:0.92;to:0.08;duration:490;easing.type:Easing.InOutSine}
                    }
                }
                Row {
                    anchors.fill:parent
                    anchors.leftMargin:8*root.uiScale
                    anchors.rightMargin:8*root.uiScale
                    spacing:4*root.uiScale
                    Item {
                        width:18*root.uiScale;height:18*root.uiScale
                        anchors.verticalCenter:parent.verticalCenter
                        visible:root.controllerBluetooth()||root.controllerUsbPowered()

                        Canvas {
                            anchors.fill:parent
                            visible:root.controllerUsbPowered()
                            antialiasing:true
                            onVisibleChanged:requestPaint()
                            onWidthChanged:requestPaint()
                            onHeightChanged:requestPaint()
                            Component.onCompleted:requestPaint()
                            onPaint:{
                                var ctx=getContext("2d");ctx.clearRect(0,0,width,height);ctx.strokeStyle=root.cobaltBlue;ctx.fillStyle=root.cobaltBlue
                                ctx.lineWidth=Math.max(1.55,width*.11);ctx.lineCap="round";ctx.lineJoin="round"
                                var w=width,h=height
                                // Standard USB trident: straight stem, arrow top,
                                // circular left endpoint, square right endpoint.
                                ctx.beginPath();ctx.moveTo(w*.50,h*.84);ctx.lineTo(w*.50,h*.18);ctx.stroke()
                                ctx.beginPath();ctx.moveTo(w*.50,h*.62);ctx.lineTo(w*.27,h*.46);ctx.lineTo(w*.27,h*.31);ctx.stroke()
                                ctx.beginPath();ctx.moveTo(w*.50,h*.52);ctx.lineTo(w*.73,h*.36);ctx.lineTo(w*.73,h*.24);ctx.stroke()
                                ctx.beginPath();ctx.moveTo(w*.50,h*.05);ctx.lineTo(w*.36,h*.22);ctx.lineTo(w*.64,h*.22);ctx.closePath();ctx.fill()
                                ctx.beginPath();ctx.arc(w*.27,h*.25,w*.075,0,Math.PI*2);ctx.fill()
                                ctx.fillRect(w*.66,h*.17,w*.14,h*.14)
                                ctx.beginPath();ctx.arc(w*.50,h*.87,w*.085,0,Math.PI*2);ctx.fill()
                            }
                        }

                        Canvas {
                            anchors.fill:parent
                            visible:root.controllerBluetooth()
                            antialiasing:true
                            onVisibleChanged:requestPaint()
                            onWidthChanged:requestPaint()
                            onHeightChanged:requestPaint()
                            Component.onCompleted:requestPaint()
                            onPaint:{
                                var ctx=getContext("2d");ctx.clearRect(0,0,width,height);ctx.strokeStyle="#39FF88";ctx.lineWidth=Math.max(1.5,width*.105);ctx.lineCap="round";ctx.lineJoin="round"
                                var w=width,h=height
                                ctx.beginPath();ctx.moveTo(w*.48,h*.08);ctx.lineTo(w*.48,h*.92);ctx.stroke()
                                ctx.beginPath();ctx.moveTo(w*.48,h*.08);ctx.lineTo(w*.76,h*.28);ctx.lineTo(w*.48,h*.50);ctx.lineTo(w*.76,h*.72);ctx.lineTo(w*.48,h*.92);ctx.stroke()
                                ctx.beginPath();ctx.moveTo(w*.24,h*.29);ctx.lineTo(w*.48,h*.50);ctx.lineTo(w*.24,h*.71);ctx.stroke()
                            }
                        }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text:root.controllerDisplayName();color:root.controllerRegistrationAttention?"#FFD45A":"#F4FBFF";font.pixelSize:8.5*root.uiScale;font.bold:true }
                    Text { anchors.verticalCenter: parent.verticalCenter; text:root.controllerConnected()?(root.controllerUsbPowered()?"Wired":root.controllerBluetooth()?"Bluetooth":"Connected"):"Offline";color:root.controllerConnected()?root.controllerBatteryTone():theme.red;font.pixelSize:6.5*root.uiScale;font.bold:true }
                    Row { anchors.verticalCenter: parent.verticalCenter; spacing:1*root.uiScale;Repeater { model:8; Rectangle { width:3.5*root.uiScale;height:11*root.uiScale;radius:1.5*root.uiScale;color:(root.controllerBatteryPercent()>=0&&index<Math.ceil(root.controllerBatteryPercent()/12.5))?root.controllerBatteryTone():"#1B2B3B";border.width:1;border.color:"#31506B" } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text:root.controllerBatteryPercent()>=0?String(root.controllerBatteryPercent())+"%":"--%";color:root.controllerBatteryTone();font.pixelSize:7.5*root.uiScale;font.bold:true }
                }
                MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.activateHeaderTab(4)}
            }
        }
    }

    Loader{id:activeView;asynchronous:true;visible:!root.selectorOnly;anchors.left:parent.left;anchors.right:parent.right;anchors.top:root.activeMode==="desktop"?parent.top:header.bottom;anchors.bottom:root.activeMode==="desktop"?desktopFooter.top:(launcher.visible?launcher.top:footer.top);anchors.leftMargin:root.activeMode==="desktop"?0:38;anchors.rightMargin:root.activeMode==="desktop"?0:38;anchors.topMargin:root.activeMode==="desktop"?root.desktopChromeHeight:-root.majorTabContentLift;anchors.bottomMargin:root.activeMode==="desktop"?0:12
        source:activeMode==="desktop"?"DesktopView.qml":activeMode==="system"?"SystemOverviewView.qml":activeMode==="security"?"SecurityDashboardView.qml":activeMode==="storage"?"StorageManagerView.qml":activeMode==="apps"?"AppsDashboardView.qml":activeMode.indexOf("custom-")===0?"CustomDashboardView.qml":"AppsDashboardView.qml"
        onLoaded:{root.ensureDesktopGridMetrics();if("monitorBackend" in item)item.monitorBackend=root.monitorBackend;if("networkBackend" in item)item.networkBackend=root.networkBackend;if("storageBackend" in item)item.storageBackend=root.storageBackend;if("securityBackend" in item)item.securityBackend=root.securityBackend;if("notificationBackend" in item)item.notificationBackend=root.notificationBackend;if("clockBackend" in item)item.clockBackend=root.clockBackend;if("controllerBackend" in item)item.controllerBackend=root.controllerBackend;if("activeUser" in item){/* NEUTRONOS_LIVE_ACTIVE_USER_BINDING_V3 */item.activeUser=Qt.binding(function(){return root.activeUser})}if("appsBackend" in item)item.appsBackend=root.appsBackend;if("backend" in item)item.backend=activeMode==="security"?root.securityBackend:activeMode==="storage"?root.storageBackend:activeMode==="apps"?root.appsBackend:null;if("layoutBackend" in item)item.layoutBackend=root.layoutBackend;if("tabId" in item)item.tabId=root.activeMode;if("shellActive" in item)item.shellActive=Qt.binding(function(){return root.shellActive});if("controllerActive" in item)item.controllerActive=root.zone===0;if("iconSizeMode" in item)item.iconSizeMode=root.desktopIconSizeMode;if("autoSeedEnabled" in item)item.autoSeedEnabled=false;if("desktopItems" in item)item.desktopItems=root.desktopItems;if("defaultsSeeded" in item)item.defaultsSeeded=root.desktopDefaultsInitialized;if("gridColumns" in item)item.gridColumns=root.desktopGridColumns;if("gridRows" in item)item.gridRows=root.desktopGridRows;if("fixedCellSize" in item)item.fixedCellSize=root.desktopGridCellSize;if("gridHorizontalInset" in item)item.gridHorizontalInset=root.desktopSafeInset;if("scannedScreenWidth" in item)item.scannedScreenWidth=root.desktopScreenWidth;if("scannedScreenHeight" in item)item.scannedScreenHeight=root.desktopScreenHeight;if(item.desktopLayoutChanged)item.desktopLayoutChanged.connect(function(items){root.desktopItems=items||[]});if(item.desktopLayoutCommitted)item.desktopLayoutCommitted.connect(function(items){root.acceptDesktopLayout(items)});if(item.defaultSeedCompleted)item.defaultSeedCompleted.connect(function(){root.desktopDefaultsInitialized=true});if(item.detailsRequested)item.detailsRequested.connect(root.showDetails);if(item.actionsRequested)item.actionsRequested.connect(root.showActions);if(item.appLaunchRequested)item.appLaunchRequested.connect(root.launchApp);if(item.topBoundaryRequested)item.topBoundaryRequested.connect(function(){root.zone=3;root.headerIndex=0;root.syncControllerContext();root.forceActiveFocus()});if(item.rightBoundaryRequested)item.rightBoundaryRequested.connect(function(){root.zone=3;root.headerIndex=0;root.syncControllerContext();root.forceActiveFocus()});if(item.bottomBoundaryRequested)item.bottomBoundaryRequested.connect(function(){root.zone=root.activeMode==="desktop"?2:1;root.footerIndex=0;root.syncControllerContext();root.forceActiveFocus()});if(root.activeMode==="desktop")Qt.callLater(root.restoreOrSeedDesktopLayout)}
    }
    Item{id:launcher;visible:!root.selectorOnly&&activeMode!=="apps"&&activeMode!=="desktop";anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:footer.top;anchors.bottomMargin:-8*root.uiScale;height:118*root.uiScale
        PathView{
            id:appRow
            width:Math.min(parent.width-80*root.uiScale,13*96*root.uiScale)
            height:112*root.uiScale
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.bottom:parent.bottom
            clip:true
            model:root.appList
            currentIndex:root.appIndex
            pathItemCount:Math.min(13,Math.max(1,root.appList.length))
            preferredHighlightBegin:.5
            preferredHighlightEnd:.5
            highlightRangeMode:PathView.StrictlyEnforceRange
            snapMode:PathView.SnapOneItem
            interactive:false
            path:Path{
                startX:48*root.uiScale;startY:56*root.uiScale
                PathLine{x:appRow.width-48*root.uiScale;y:56*root.uiScale}
            }
            delegate:DashboardDockIcon{
                required property int index
                required property var modelData
                width:96*root.uiScale;height:108*root.uiScale
                appData:modelData
                sectionActive:root.zone===1
                selected:root.zone===1&&root.appIndex===index
                moving:root.appMoveMode&&String(modelData.id||"")===root.movingAppId
                onActivated:{
                    root.selectAppIndex(index)
                    if(!root.appMoveMode)root.launchApp(modelData)
                }
            }
        }
    }
    Item{id:footer;visible:!root.selectorOnly&&root.activeMode!=="desktop";anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:86*root.uiScale
        Row{anchors.left:parent.left;anchors.leftMargin:30;anchors.verticalCenter:parent.verticalCenter;spacing:22;ControllerHint{family:root.controllerFamily();action:"primary";glyph:root.glyph("primary");label:"Select";accent:theme.cyan}ControllerHint{family:root.controllerFamily();action:"cancel";glyph:root.glyph("cancel");label:"Back";accent:theme.red}ControllerHint{family:root.controllerFamily();action:"context";glyph:root.glyph("context");label:"Details";accent:"#6DFF3B"}ControllerHint{family:root.controllerFamily();action:"secondary";glyph:root.glyph("secondary");label:"Actions";accent:theme.pink}}
        Row{anchors.horizontalCenter:parent.horizontalCenter;anchors.verticalCenter:parent.verticalCenter;spacing:9
            visible:root.zone!==1&&root.zone!==2
            Text{text:"Secure";color:"white";font.pixelSize:14;font.bold:true}
            Text{text:"|";color:theme.cyan;font.pixelSize:14;font.bold:true;opacity:.72}
            Text{text:"Intelligent";color:"white";font.pixelSize:14;font.bold:true}
            Text{text:"|";color:theme.cyan;font.pixelSize:14;font.bold:true;opacity:.72}
            Text{text:"Unstoppable";color:theme.red;font.pixelSize:14;font.bold:true}
        }
        Text{anchors.horizontalCenter:parent.horizontalCenter;anchors.verticalCenter:parent.verticalCenter;visible:root.zone===1||root.zone===2;text:root.zone===1&&root.currentApp()?"Open "+String(root.currentApp().name||root.currentApp().displayName||""):root.quickNames[root.footerIndex];color:theme.cyan;font.pixelSize:14}
        Row{anchors.right:parent.right;anchors.rightMargin:26;anchors.verticalCenter:parent.verticalCenter;spacing:12;Repeater{model:[{s:"⏻",b:0},{s:"?",b:0},{s:"▣",b:0},{s:"⌁",b:0},{s:"ᛒ",b:0}];delegate:QuickActionIcon{required property int index;required property var modelData;symbol:modelData.s;badge:modelData.b;selected:root.zone===2&&root.footerIndex===index;onActivated:{root.footerIndex=index;root.activateFooter()}}}QuickActionIcon{symbol:"♧";badge:notificationBackend?Number(notificationBackend.unreadCount||0):0;selected:root.zone===2&&root.footerIndex===5;onActivated: root.notificationCenterRequested()}Rectangle{width:1;height:50;color:"#56657A"}QuickActionIcon{width:70;height:62;symbol:"▤";selected:root.zone===2&&root.footerIndex===6;onActivated:{root.footerIndex=6;root.activateFooter()}}}
    }
    Item {
        id: desktopFooter
        visible: !root.selectorOnly && root.activeMode === "desktop"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.desktopChromeHeight
        z: 40

        Rectangle {
            anchors.fill:parent
            gradient:Gradient{
                GradientStop{position:0.0;color:"#F20B0812"}
                GradientStop{position:0.38;color:"#F2081320"}
                GradientStop{position:1.0;color:"#F2031627"}
            }
            border.width:0
        }
        Rectangle { anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:1;color:"#9B35506A";opacity:.9 }
        Rectangle { anchors.left:parent.left;anchors.leftMargin:12*root.uiScale;anchors.bottom:parent.bottom;width:230*root.uiScale;height:2*root.uiScale;color:"#FF3048";opacity:.72 }
        Rectangle { anchors.left:parent.left;anchors.top:parent.top;anchors.bottom:parent.bottom;width:parent.width*.34;color:"#5A0A16";opacity:.10 }
        Rectangle { anchors.right:parent.right;anchors.top:parent.top;anchors.bottom:parent.bottom;width:parent.width*.20;color:"#3C0711";opacity:.08 }

        Rectangle {
            id: desktopSearchBar
            anchors.left:parent.left;anchors.leftMargin:14*root.uiScale;anchors.verticalCenter:parent.verticalCenter
            width:242*root.uiScale;height:26*root.uiScale;radius:13*root.uiScale
            color:root.zone===2&&root.footerIndex===0?"#14304A":"#081522"
            border.width:root.zone===2&&root.footerIndex===0?2:1
            border.color:root.zone===2&&root.footerIndex===0?"#4DA6FF":"#294866"
            Row{anchors.fill:parent;anchors.leftMargin:12*root.uiScale;spacing:8*root.uiScale
                Text{anchors.verticalCenter:parent.verticalCenter;text:"⌕";color:"#7DF9FF";font.pixelSize:13*root.uiScale;font.bold:true}
                Row{anchors.verticalCenter:parent.verticalCenter;spacing:0
                    Text{text:"Search Neutron";color:"#DCEBFA";font.pixelSize:10*root.uiScale;font.bold:true}
                    Text{text:"OS";color:"#FF4057";font.pixelSize:10*root.uiScale;font.bold:true}
                }
            }
            MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{root.zone=2;root.footerIndex=0;root.searchRequested()}}
        }

        Item {
            id: desktopCenterModule
            anchors.horizontalCenter:parent.horizontalCenter
            anchors.verticalCenter:parent.verticalCenter
            width: desktopCenterMode==="carousel"
                   ? Math.min(560*root.uiScale,Math.max(160*root.uiScale,(root.desktopCarouselResolvedApps.length*44+24)*root.uiScale))
                   : desktopCenterMode==="hidden" ? 154*root.uiScale : 298*root.uiScale
            height: desktopCenterMode==="carousel" ? 40*root.uiScale : 28*root.uiScale

            Rectangle {
                anchors.fill:parent
                visible:desktopCenterMode==="controller"
                radius:14*root.uiScale
                color:root.zone===2&&root.footerIndex===1?"#14304A":"#081522"
                border.width:root.zone===2&&root.footerIndex===1?2:1
                border.color:root.controllerGuideNeedsAttention?"#FFD45A":root.zone===2&&root.footerIndex===1?"#4DA6FF":"#294866"
                Rectangle{anchors.fill:parent;radius:parent.radius;color:"#55FFD45A";visible:root.controllerGuideNeedsAttention;opacity:root.onboardingPulse}
                Row {
                    anchors.centerIn:parent;spacing:11*root.uiScale
                    ControllerHint{family:root.controllerFamily();action:"primary";glyph:root.glyph("primary");label:"Select";accent:theme.cyan;scale:.58}
                    ControllerHint{family:root.controllerFamily();action:"cancel";glyph:root.glyph("cancel");label:"Back";accent:theme.red;scale:.58}
                    ControllerHint{family:root.controllerFamily();action:"secondary";glyph:root.glyph("secondary");label:"Details";accent:theme.pink;scale:.58}
                    ControllerHint{family:root.controllerFamily();action:"context";glyph:root.glyph("context");label:"Move";accent:"#6DFF3B";scale:.58}
                }
            }

            DesktopAppCarousel {
                visible:root.desktopCenterMode==="carousel"
                anchors.fill:parent
                host:root
                focused:root.zone===2&&root.footerIndex===1
                onAppRequested:function(app){root.zone=2;root.footerIndex=1;root.syncControllerContext();root.launchApp(app)}
            }

            Rectangle {
                anchors.fill:parent
                visible:desktopCenterMode==="hidden"
                radius:14*root.uiScale
                color:root.zone===2&&root.footerIndex===1?"#261019":"#081522"
                border.width:root.zone===2&&root.footerIndex===1?2:1
                border.color:root.zone===2&&root.footerIndex===1?"#FF4057":"#492B3A"
                Row{anchors.centerIn:parent;spacing:6*root.uiScale;Text{text:"⊕";color:"#FF6577";font.pixelSize:12*root.uiScale;font.bold:true}Text{text:"Center Hidden";color:"#AFC5DB";font.pixelSize:8*root.uiScale;font.bold:true}}
            }

            MouseArea {
                anchors.fill:parent
                enabled:desktopCenterMode!=="carousel"
                cursorShape:Qt.PointingHandCursor
                onClicked:{root.zone=2;root.footerIndex=1;root.syncControllerContext()}
            }
        }

        Row {
            anchors.right:parent.right;anchors.rightMargin:12*root.uiScale;anchors.verticalCenter:parent.verticalCenter;spacing:8*root.uiScale
            Repeater {
                model:[{s:"⏻",i:2},{s:"?",i:3},{s:"▣",i:4},{s:"⌁",i:5},{s:"ᛒ",i:6},{s:"♧",i:7},{s:"▤",i:8}]
                delegate:QuickActionIcon {
                    required property int index;required property var modelData
                    width:28*root.uiScale;height:28*root.uiScale;radius:14*root.uiScale
                    symbol:modelData.s
                    badge:index===5&&root.notificationBackend?Number(root.notificationBackend.unreadCount||0):0
                    selected:root.zone===2&&root.footerIndex===modelData.i
                    onActivated:{root.zone=2;root.footerIndex=modelData.i;root.activateFooter()}
                }
            }
            Rectangle {
                width: 96*root.uiScale
                height: 28*root.uiScale
                radius: 14*root.uiScale
                color: "#081522"
                border.width: 1
                border.color: "#294866"
                Row {
                    anchors.centerIn: parent
                    spacing: 6*root.uiScale
                    Text { text: "◷"; color: "#7DF9FF"; font.pixelSize: 11*root.uiScale; font.bold: true }
                    Text { text: clockBackend ? String(clockBackend.currentTimeText || "--:--") : Qt.formatTime(root.now, "h:mm AP"); color: "#F4FBFF"; font.pixelSize: 8.8*root.uiScale; font.bold: true }
                }
            }
        }
    }

    Row {
        id: desktopRunningApps
        visible: !root.selectorOnly && root.activeMode === "desktop" && root.runningDesktopApps().length>0
        anchors.left:parent.left;anchors.leftMargin:310*root.uiScale
        anchors.bottom:desktopFooter.top;anchors.bottomMargin:5*root.uiScale
        spacing:5*root.uiScale;z:41
        Repeater {
            model:root.runningDesktopApps()
            delegate:Rectangle {
                required property int index;required property var modelData
                width:30*root.uiScale;height:30*root.uiScale;radius:8*root.uiScale
                color:"#D8071426";border.width:1;border.color:"#315D86"
                Image{anchors.fill:parent;anchors.margins:3*root.uiScale;source:root.appIconSource(modelData);fillMode:Image.PreserveAspectFit;smooth:true;mipmap:false;visible:String(source).length>0}
                Text{anchors.centerIn:parent;visible:root.runtimeIcon(modelData).length===0;text:String(modelData.displayName||modelData.appId||"A").slice(0,1).toUpperCase();color:"#7DF9FF";font.pixelSize:11*root.uiScale;font.bold:true}
                Rectangle{width:6*root.uiScale;height:6*root.uiScale;radius:3*root.uiScale;color:"#22FF88";anchors.right:parent.right;anchors.bottom:parent.bottom}
                MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.focusRuntime(modelData)}
            }
        }
    }

    Rectangle {
        visible: root.desktopCenterMenuOpen && !root.selectorOnly && root.activeMode === "desktop"
        anchors.horizontalCenter: desktopCenterModule.horizontalCenter
        anchors.bottom: desktopFooter.top
        anchors.bottomMargin: 10*root.uiScale
        width: 264*root.uiScale
        height: 154*root.uiScale
        radius: 18*root.uiScale
        color: "#F4071426"
        border.width: 2
        border.color: "#4DA6FF"
        z: 92

        Column {
            anchors.fill: parent
            anchors.margins: 12*root.uiScale
            spacing: 8*root.uiScale

            Text { text: "Controller Guide"; color: "#F4FBFF"; font.pixelSize: 14*root.uiScale; font.bold: true; horizontalAlignment: Text.AlignHCenter; width: parent.width }

            Repeater {
                model: root.desktopCenterChoices()
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: parent ? parent.width : 220*root.uiScale
                    height: 34*root.uiScale
                    radius: 11*root.uiScale
                    color: root.desktopCenterMenuIndex===index ? "#17365D" : "#081522"
                    border.width: root.desktopCenterMenuIndex===index ? 2 : 1
                    border.color: modelData.id==="carousel"&&root.appCarouselNeedsAttention ? "#FFD45A" : root.desktopCenterMenuIndex===index ? "#4DA6FF" : "#294866"
                    Rectangle{anchors.fill:parent;radius:parent.radius;color:"#55FFD45A";visible:modelData.id==="carousel"&&root.appCarouselNeedsAttention;opacity:root.onboardingPulse}
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 11*root.uiScale
                        spacing: 1*root.uiScale
                        Text { text: modelData.label; color: "#F4FBFF"; font.pixelSize: 10*root.uiScale; font.bold: true }
                        Text { text: modelData.detail; color: "#8AA6C8"; font.pixelSize: 7.2*root.uiScale; elide: Text.ElideRight; width: parent.width-22*root.uiScale }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.applyDesktopCenterChoice(modelData.id) }
                }
            }
        }
    }

    DesktopCarouselDialogs {anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:desktopFooter.top;host:root;z:98}

    Rectangle {
        anchors.fill:parent;visible:root.controllerWelcomeOpen;z:700;color:"#C9000309"
        Rectangle {
            anchors.centerIn:parent;width:Math.min(parent.width*.70,1120);height:Math.min(parent.height*.68,760);radius:30;color:"#F5071426";border.width:2;border.color:"#4DA6FF"
            Column {
                anchors.fill:parent;anchors.margins:34;spacing:18
                Text{width:parent.width;text:root.controllerFamily()==="xbox"?"YOUR XBOX BUTTON IS YOUR NEUTRONOS HOME":"YOUR PS BUTTON IS YOUR NEUTRONOS HOME";color:"#F4FBFF";font.pixelSize:28;font.bold:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap}
                Text{width:parent.width;text:"NeutronOS is controller-first. The center system button opens the Desktop selector from anywhere in Console, while the face buttons stay consistent across the interface.";color:"#AFC5DB";font.pixelSize:16;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap}
                Rectangle{width:parent.width;height:1;color:"#24425E"}
                Grid{columns:2;columnSpacing:18;rowSpacing:12;width:parent.width
                    Repeater{model:[
                        {g:"↕",t:"D-Pad / Left Stick",d:"Navigate the Desktop and menus"},
                        {g:root.glyph("primary"),t:root.controllerFamily()==="xbox"?"A • Select":"X • Select",d:"Open apps and confirm choices"},
                        {g:root.glyph("cancel"),t:root.controllerFamily()==="xbox"?"B • Back":"Circle • Back",d:"Resume, cancel, or go back"},
                        {g:root.glyph("secondary"),t:root.controllerFamily()==="xbox"?"X • Details":"Square • Details",d:"Open app/widget details and actions"},
                        {g:root.glyph("context"),t:root.controllerFamily()==="xbox"?"Y • Move":"Triangle • Move",d:"Quickly reposition Desktop items"},
                        {g:"≡",t:root.controllerFamily()==="xbox"?"Menu • Add":"Options • Add",d:"Open Apps and Widgets drawer"},
                        {g:root.controllerFamily()==="xbox"?"XB":"PS",t:"System Button",d:"Open Desktop / System Overview / Security / Storage / Apps / Legacy"},
                        {g:"⌕",t:"Search NeutronOS",d:"Search apps, settings, files and actions"}
                    ];delegate:Rectangle{required property var modelData;width:(parent.width-18)/2;height:82;radius:16;color:"#081522";border.width:1;border.color:"#294866";Row{anchors.fill:parent;anchors.margins:13;spacing:13;Rectangle{width:48;height:48;radius:14;color:"#0B1A30";border.width:1;border.color:"#4DA6FF";Text{anchors.centerIn:parent;text:modelData.g;color:"#7DF9FF";font.pixelSize:18;font.bold:true}}Column{width:parent.width-70;anchors.verticalCenter:parent.verticalCenter;spacing:3;Text{width:parent.width;text:modelData.t;color:"#F4FBFF";font.pixelSize:14;font.bold:true;elide:Text.ElideRight}Text{width:parent.width;text:modelData.d;color:"#8AA6C8";font.pixelSize:11;wrapMode:Text.WordWrap}}}}}
                }
                Rectangle {
                    width:parent.width;height:52;radius:15
                    color:root.controllerGuideSelection===1?"#17365D":"#081522"
                    border.width:root.controllerGuideSelection===1||root.appCarouselNeedsAttention?2:1
                    border.color:root.appCarouselNeedsAttention?"#FFD45A":root.controllerGuideSelection===1?"#4DA6FF":"#294866"
                    Rectangle{anchors.fill:parent;radius:parent.radius;color:"#55FFD45A";visible:root.appCarouselNeedsAttention;opacity:root.onboardingPulse}
                    Text{anchors.centerIn:parent;text:"APP CAROUSEL  •  X / A TO OPEN";color:"#F4FBFF";font.pixelSize:15;font.bold:true}
                    MouseArea{anchors.fill:parent;onClicked:{root.applyDesktopCenterChoice("carousel");root.dismissControllerWelcome()}}
                }
                Text{width:parent.width;text:"UP / DOWN SELECT  •  X / A OPEN  •  SQUARE FOOTER MODULES  •  CIRCLE CLOSE";color:"#7DF9FF";font.pixelSize:12;font.bold:true;horizontalAlignment:Text.AlignHCenter;font.letterSpacing:1}
            }
        }
    }

    Rectangle{id:selector;visible:root.selectorOpen;z:400;x:38;y:105;width:340;height:Math.min(parent.height-y-90,24+root.modes.length*68);radius:18;color:"#F2071424";border.width:2;border.color:theme.cyan
        Column{anchors.fill:parent;anchors.margins:12;spacing:8;Repeater{model:root.modes;delegate:Rectangle{required property int index;required property var modelData;width:parent.width;height:60;radius:12;color:root.selectorIndex===index?"#1B4263":"transparent";border.width:root.selectorIndex===index?1:0;border.color:theme.cyan;Text{anchors.centerIn:parent;text:modelData.label;color:"white";font.pixelSize:16;font.bold:root.selectorIndex===index}}}}
    }
    DashboardContextModal {
        id: contextModal
        anchors.fill: parent
        monitorBackend: root.monitorBackend
        appBackend: root.appsBackend
        layoutBackend: root.layoutBackend
        storageBackend: root.storageBackend
        securityBackend: root.securityBackend
        notificationBackend: root.notificationBackend
        onClosed: root.forceActiveFocus()
        onAppLaunchRequested: function(app) {
            root.launchApp(app)
        }
        onWidgetMoveRequested: function(widgetId) {
            if (activeView.item && activeView.item.beginMove)
                activeView.item.beginMove(widgetId)
        }
        onAppMoveRequested: function(app) { root.beginAppMove(app) }
        onAppPinned: function(appId) { Qt.callLater(function(){ root.selectAppById(appId) }) }
    }
    SystemOverviewManager {
        id: overviewManager
        anchors.fill: parent
        backend: root.layoutBackend
        onClosed: root.forceActiveFocus()
    }
    RunningAppsTray {
        id: runningAppsTray
        backend: root.appsBackend
        onClosed: {
            root.zone = 2
            root.footerIndex=5
            root.forceActiveFocus()
        }
        onMakeAppTabRequested: function(runtime) {
            if (root.layoutBackend)
                root.layoutBackend.makeRunningAppTab(runtime)
        }
    }
    // Compatibility contracts: cpuValid memoryValid temperatureCelsius temperatureValid thermalThrottled rxBytesPerSecond txBytesPerSecond activeInterface
    // "network","user","security"; text:"Uptime  "+
    // System Overview Up now enters the five header tabs; one more Up opens Notification Center.
}
