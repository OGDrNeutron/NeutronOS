import QtQuick

DashboardCard {
    id: root
    property string widgetId: ""
    property string widgetSize: "small"
    property string widgetVariant: "small-square"
    property string shapeVariant: "square"
    property var monitorBackend: null
    property var networkBackend: null
    property var securityBackend: null
    property var notificationBackend: null
    property var clockBackend: null
    property var activeUser: null
    property var controllerBackend: null
    property var appsBackend: null
    property var storageBackend: null
    property var storageData: ({})
    property int storageSlot: 0
    property bool securityPanelActive:false
    property int securityActionIndex:0
    property bool networkPanelActive:false
    property int networkActionIndex:0
    property bool maxDefconArmed:false
    property bool animationEnabled: visible
    property bool moving:false
    property real viewportWidth:1920
    signal networkActionRequested(int requestedIndex)
    readonly property real uiScale:Math.max(1,Math.min(1.8,viewportWidth/1844))
    readonly property int detailCount: widgetSize === "large" ? 7 : widgetSize === "medium" ? 3 : 0
    readonly property bool wideShape:shapeVariant==="wide"
    readonly property bool tallShape:shapeVariant==="tall"
    readonly property var unresolvedIncidents: collectUnresolvedIncidents()
    readonly property var currentIncident: unresolvedIncidents.length ? unresolvedIncidents[0] : ({})
    accent:moving?"#FF4FCE":"#35DFFF"
    showHeading:false
    menuText:""

    // This intentionally mirrors qml/apps/security/Main.qml::overallNeedsAttention()
    // and the Security app header's additional DEFCON > 2 requirement.
    // Dashboard Security state must never invent its own stricter policy.
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
        if (!securityBackend ||
            securityBackend.daemonOnline !== true ||
            securityBackend.auditValid !== true)
            return true

        if (securityBackend.integrityChanges &&
            securityBackend.integrityChanges.length > 0)
            return true

        if (securityBackend.malwareFindings &&
            securityBackend.malwareFindings.length > 0)
            return true

        if (securityAppSuspiciousEvents().length > 0)
            return true

        // Security/Main.qml Header.secure also requires DEFCON > 2.
        if (Number(securityBackend.threatLevel || 5) <= 2)
            return true

        return false
    }

    function rate(bytes) {
        var n=Number(bytes||0); return n>=1000000?(n/1000000).toFixed(1)+" MB/s":n>=1000?(n/1000).toFixed(1)+" KB/s":Math.round(n)+" B/s"
    }
    function bytesText(bytes) {
        var n=Number(bytes||0); return n>=1073741824?(n/1073741824).toFixed(1)+" GB":n>=1048576?(n/1048576).toFixed(1)+" MB":n>=1024?(n/1024).toFixed(1)+" KB":Math.round(n)+" B"
    }
    function processRows(memory) {
        if (!monitorBackend) return []
        var source=memory?monitorBackend.memoryProcesses:monitorBackend.cpuProcesses
        return source ? source.slice(0,detailCount) : []
    }
    function processFraction(process, memory) {
        if(memory){var total=Number(monitorBackend&&monitorBackend.ramTotalBytes||0);return total>0?Math.max(0,Math.min(1,Number(process.memoryBytes||0)/total)):0}
        return Math.max(0,Math.min(1,Number(process.cpu||0)/100))
    }
    function processBarColor(fraction) {
        return fraction>=.85?"#FF354F":fraction>=.60?"#FF7A3D":fraction>=.35?"#B768FF":fraction>=.15?"#248DFF":"#25DFA8"
    }
    function localModeEnabled() {
        var state=networkBackend&&networkBackend.offlineNetworkState?networkBackend.offlineNetworkState:({})
        return Boolean(state.hotspotEnabled||state.lanModeEnabled||state.localModeEnabled)
    }
    function cleanValue(value) {
        var text=String(value===undefined||value===null?"":value).trim()
        return text==="--"||text==="0.0.0.0"||text.toLowerCase()==="unknown"?"":text
    }
    function networkValue(primary, fallback) {
        var value=cleanValue(primary)
        return value.length?value:cleanValue(fallback)
    }
    function localServiceIp() {
        var state=networkBackend&&networkBackend.offlineNetworkState?networkBackend.offlineNetworkState:({})
        return networkValue(state.hotspotIp||state.hotspotAddress||state.lanIp||state.localIp, "")
    }
    function networkFields() {
        var fields=[]
        var ip=networkValue(networkBackend?networkBackend.localIp:"",monitorBackend?monitorBackend.localIp:"")
        var tail=networkValue(networkBackend?networkBackend.tailscaleIp:"",monitorBackend?monitorBackend.tailscaleIp:"")
        fields.push({label:"IP",value:ip||"Unavailable"})
        if(localModeEnabled()&&localServiceIp().length)fields.push({label:"LOCAL IP",value:localServiceIp()})
        if(tail.length)fields.push({label:"TAILSCALE",value:tail})
        if(widgetSize!=="small"){
            fields.push({label:"INTERFACE",value:networkValue(networkBackend?networkBackend.interfaceName:"",monitorBackend?monitorBackend.activeInterface:"")||"Unavailable"})
            fields.push({label:"LINK",value:networkValue(networkBackend?networkBackend.connectionState:"",monitorBackend&&monitorBackend.networkConnected?"Connected":"Offline")})
            var signal=Number(networkBackend?networkBackend.signalPercent:-1)
            if(signal>=0)fields.push({label:"SIGNAL",value:Math.round(signal)+"%"})
            var gateway=networkValue(networkBackend?networkBackend.gateway:"","")
            if(gateway.length)fields.push({label:"GATEWAY",value:gateway})
        }
        if(widgetSize==="large"){
            var dns=networkBackend&&networkBackend.dnsServers?networkBackend.dnsServers:[]
            if(dns&&dns.length)fields.push({label:"DNS",value:dns.join(", ")})
            var security=networkValue(networkBackend?networkBackend.currentSecurity:"","")
            if(security.length)fields.push({label:"SECURITY",value:security})
            var band=networkValue(networkBackend?networkBackend.band:"","")
            if(band.length)fields.push({label:"BAND",value:band})
            var latency=Number(networkBackend?networkBackend.latencyMs:-1)
            if(latency>=0)fields.push({label:"LATENCY",value:Math.round(latency)+" ms"})
        }
        return fields
    }
    function storageMountName(data) {
        var mount = cleanValue(data && (data.mountPoint || data.mount || data.path))

        // The system/root storage card is the NeutronOS boot volume.
        // External storage continues to use its real mounted/display name.
        if (mount === "/" || storageSlot === 0)
            return "NeutronOS"

        if (mount.length) {
            var parts = mount.split("/")
            for (var i = parts.length - 1; i >= 0; --i)
                if (String(parts[i]).length) return String(parts[i])
        }

        return cleanValue(data && (data.volumeLabel || data.label || data.displayName || data.name)) ||
               "Expansion"
    }
    function storageDeviceRecord(path, list, inherited) {
        var target = cleanValue(path)
        var devices = list || []
        var inheritedMeta = inherited || ({})
        for (var i = 0; i < devices.length; ++i) {
            var device = devices[i] || ({})
            var meta = {
                vendor: cleanValue(device.vendor) || cleanValue(inheritedMeta.vendor),
                model: cleanValue(device.model) || cleanValue(inheritedMeta.model),
                path: cleanValue(device.path),
                transport: cleanValue(device.transport) || cleanValue(inheritedMeta.transport)
            }
            if (target.length && meta.path === target)
                return meta
            var children = device.children || []
            var found = storageDeviceRecord(target, children, meta)
            if (found && (cleanValue(found.path).length || cleanValue(found.vendor).length || cleanValue(found.model).length))
                return found
        }
        return ({})
    }
    function storageDeviceMeta() {
        var devices = storageBackend && storageBackend.devices ? storageBackend.devices : []
        var path = cleanValue(storageData && (storageData.devicePath || storageData.device))
        var found = storageDeviceRecord(path, devices, ({}))
        if ((!found || (!cleanValue(found.vendor).length && !cleanValue(found.model).length)) && path.length) {
            // A partition such as /dev/sdc1 may carry vendor/model only on its
            // parent disk. Find the parent by checking child paths.
            function findParent(list) {
                for (var i = 0; i < list.length; ++i) {
                    var device = list[i] || ({})
                    var children = device.children || []
                    for (var j = 0; j < children.length; ++j) {
                        if (cleanValue(children[j] && children[j].path) === path)
                            return device
                    }
                    var nested = findParent(children)
                    if (nested) return nested
                }
                return null
            }
            var parent = findParent(devices)
            if (parent) found = parent
        }
        return found || ({})
    }
    function storageManufacturer() {
        var meta = storageDeviceMeta()
        var vendor = cleanValue(meta.vendor || (storageData && storageData.vendor))
        var model = cleanValue(meta.model || (storageData && storageData.model))
        if (vendor.length) return vendor
        if (model.length) {
            var normalized = model.replace(/[_-]+/g, " ").trim()
            var first = normalized.split(/\s+/)[0]
            return first.length ? first : model
        }
        return "Unknown manufacturer"
    }
    function storageModelText() {
        var meta = storageDeviceMeta()
        return cleanValue(meta.model || (storageData && storageData.model)) || "--"
    }
    function storageUsedPercent() {
        return Math.max(0, Math.min(100, Number(storageData && (storageData.usedPercent !== undefined ?
               storageData.usedPercent : storageData.percent) || 0)))
    }
    function storageFreePercent() {
        return Math.max(0, 100 - storageUsedPercent())
    }
    function storageMountPoint() {
        var mount = cleanValue(storageData && (storageData.mountPoint || storageData.mount || storageData.path))
        return mount.length ? mount : (storageSlot === 0 ? "/" : "")
    }
    function storageBreakdown() {
        if (!storageBackend || !storageBackend.usageBreakdowns)
            return ({})
        var mount = storageMountPoint()
        if (!mount.length)
            return ({})
        var all = storageBackend.usageBreakdowns
        return all[mount] || ({})
    }
    function storageBreakdownRows() {
        var breakdown = storageBreakdown()
        var entries = breakdown && breakdown.entries ? breakdown.entries : []
        if (entries && entries.length)
            return entries

        var used = cleanValue(storageData && storageData.used) || "--"
        var free = cleanValue(storageData && (storageData.available || storageData.free)) || "--"
        return [
            {name:"Used", value:used, percent:storageUsedPercent(), color:"#14BFFF", free:false},
            {name:"Free", value:free, percent:storageFreePercent(), color:"#8193FF", free:true}
        ]
    }
    function requestStorageBreakdown(force) {
        if (!storageBackend || typeof storageBackend.requestUsageBreakdown !== "function")
            return
        var mount = storageMountPoint()
        if (mount.length)
            storageBackend.requestUsageBreakdown(mount, force === true)
    }
    function authoritativeUser() {
        // NEUTRONOS_DASHBOARD_SECURITY_TELEMETRY_V2
        // The authenticated user passed through Main -> Console -> Dashboard
        // wins. The global backend is only a fallback for non-session views.
        try {
            if (activeUser &&
                    cleanValue(activeUser.username || activeUser.accountName || activeUser.loginName).length)
                return activeUser
        } catch (activeUserError) {}
        try {
            if (typeof userManager !== "undefined" && userManager && userManager.activeUser &&
                    cleanValue(userManager.activeUser.username || userManager.activeUser.accountName || userManager.activeUser.loginName).length)
                return userManager.activeUser
        } catch (error) {}
        return ({})
    }
    function userName() { var profile=authoritativeUser(); return cleanValue(profile.username||profile.accountName||profile.loginName) || "unknown" }
    function userDisplayName() { var profile=authoritativeUser(); return cleanValue(profile.displayName||profile.fullName||profile.name) || userName() }
    function userAvatarSource() {
        var profile=authoritativeUser()
        var value=cleanValue(profile&&(profile.resolvedAvatarSource||profile.avatarSource||profile.icon||profile.avatar))
        if(!value.length)return Qt.resolvedUrl("../../../themes/Default/users/user_icon.png")
        if(value.indexOf(":")>=0||value.charAt(0)==="/")return value
        return Qt.resolvedUrl("../../../themes/Default/"+value)
    }
    function severityRank(value) {
        var text=String(value||"").toLowerCase()
        if(text==="critical"||Number(value)>=4)return 4
        if(text==="high"||Number(value)===3)return 3
        if(text==="medium"||text==="warning"||Number(value)===2)return 2
        return 1
    }
    function collectUnresolvedIncidents() {
        var out=[], acknowledged={}
        var events=securityBackend&&securityBackend.events?securityBackend.events:[]
        for(var i=0;i<events.length;++i){
            var event=events[i]||({}), eventId=String(event.id||event.eventId||"")
            if(event.acknowledged===true){if(eventId.length)acknowledged[eventId]=true;continue}
            var entry={id:"event:"+eventId,eventId:eventId,notificationId:"",title:String(event.title||event.message||"Security event"),message:String(event.evidence||event.description||event.message||"Review in Security"),evidence:String(event.evidence||event.description||event.message||"No additional evidence supplied"),recommendedAction:String(event.recommendedAction||event.action||"Review the event and acknowledge it when resolved"),severity:event.severity||event.level||"warning",time:event.timestamp||event.time||"",component:String(event.component||event.source||"Security Core"),category:String(event.category||""),flagged:event.flagged===true,dismissible:severityRank(event.severity||event.level)<4}
            entry.displayTitle=friendlyIncidentTitle(entry)
            entry.displayDetail=friendlyIncidentDetail(entry)
            out.push(entry)
        }
        var notes=notificationBackend&&notificationBackend.notifications?notificationBackend.notifications:[]
        for(var n=0;n<notes.length;++n){
            var note=notes[n]||({}), payload=note.payload||({}), linked=String(payload.eventId||payload.id||"")
            if(String(note.category||"").toLowerCase()!=="security"||note.dismissed===true||note.resolved===true||acknowledged[linked])continue
            var duplicate=false
            for(var d=0;d<out.length;++d)if(linked.length&&out[d].eventId===linked){out[d].notificationId=String(note.id||"");duplicate=true;break}
            if(!duplicate){
                var noteEntry={id:"notification:"+String(note.id||n),eventId:linked,notificationId:String(note.id||""),title:String(note.title||"Security event"),message:String(note.message||note.body||"Review in Security"),evidence:String(payload.evidence||note.message||note.body||"No additional evidence supplied"),recommendedAction:String(payload.recommendedAction||"Review the event and acknowledge it when resolved"),severity:note.severity||note.priority||"warning",time:note.timestamp||note.time||"",component:String(payload.component||note.source||"Security"),category:String(payload.category||""),flagged:false,dismissible:String(note.priority||"").toLowerCase()!=="critical"}
                noteEntry.displayTitle=friendlyIncidentTitle(noteEntry)
                noteEntry.displayDetail=friendlyIncidentDetail(noteEntry)
                out.push(noteEntry)
            }
        }
        out.sort(function(a,b){var rank=severityRank(b.severity)-severityRank(a.severity);if(rank)return rank;return String(b.time).localeCompare(String(a.time))})
        return out
    }

    function evidenceObject(incident) {
        if(!incident)return ({})
        var raw=incident.evidence
        if(raw && typeof raw === "object")return raw
        var text=String(raw||"").trim()
        if(!text.length)return ({})
        try { var parsed=JSON.parse(text); return parsed&&typeof parsed==="object"?parsed:({}) } catch(error) { return ({}) }
    }
    function incidentWhen(value) {
        var raw=String(value||"").trim()
        if(!raw.length)return ""
        var d=new Date(raw)
        if(isNaN(d.getTime()))return raw
        return Qt.formatDateTime(d,"MMM d • h:mm AP")
    }
    function incidentFilePath(incident) {
        var ev=evidenceObject(incident)
        var path=String(ev.path||ev.filePath||ev.file||ev.target||incident&&incident.path||"").trim()
        if(path.length)return path
        // Integrity daemon messages are formatted as:
        // "A protected file was modified: relative/or/absolute/path"
        var message=String(incident&&incident.message||"")
        var match=message.match(/(?:modified|removed|added)\s*:\s*(.+)$/i)
        return match&&match.length>1?String(match[1]).trim():""
    }
    function incidentFileName(incident) {
        var path=incidentFilePath(incident).replace(/\\/g,"/")
        if(!path.length)return ""
        var parts=path.split("/")
        return parts.length?String(parts[parts.length-1]||path):path
    }
    function friendlyIncidentTitle(incident) {
        var title=String(incident&&incident.title||"")
        var category=String(incident&&incident.category||"").toLowerCase()
        var source=String(incident&&incident.component||incident&&incident.source||"").toLowerCase()
        var combined=(title+" "+category+" "+source+" "+String(incident&&incident.message||"")).toLowerCase()
        var ev=evidenceObject(incident)
        var change=String(ev.change||"").toLowerCase()
        if(combined.indexOf("integrity")>=0||combined.indexOf("protected file")>=0||source.indexOf("file-integrity")>=0){
            var fileName=incidentFileName(incident)
            var subject=fileName.length?fileName:"Protected File"
            if(change==="removed")return subject+" Removed"
            if(change==="added")return subject+" Added"
            return subject+" Changed"
        }
        if(combined.indexOf("ssh")>=0&&combined.indexOf("auth")>=0)return "SSH Login Rejected"
        // NEUTRONOS_SECURITY_EVENT_TRUTH_V1
        // Never invent an "incorrect password" incident from generic auth words.
        // The daemon's actual event title is authoritative.
        if(combined.indexOf("authentication")>=0||combined.indexOf("password")>=0||combined.indexOf("login")>=0||combined.indexOf("pam")>=0)
            return title.length?title:"Authentication Event"
        if(combined.indexOf("malware")>=0||combined.indexOf("virus")>=0||combined.indexOf("clam")>=0)return "Malware Detected"
        if(combined.indexOf("peripheral")>=0||combined.indexOf("usb")>=0)return "Unknown Device Detected"
        if(combined.indexOf("firewall")>=0||combined.indexOf("blocked source")>=0||combined.indexOf("network")>=0)return "Blocked Connection"
        return title.length?title:"Security Event"
    }
    function friendlyIncidentDetail(incident) {
        var title=String(incident&&incident.title||"")
        var message=String(incident&&incident.message||"")
        var category=String(incident&&incident.category||"").toLowerCase()
        var source=String(incident&&incident.component||incident&&incident.source||"").toLowerCase()
        var combined=(title+" "+category+" "+source+" "+message).toLowerCase()
        var ev=evidenceObject(incident), change=String(ev.change||"").toLowerCase()
        if(combined.indexOf("integrity")>=0||combined.indexOf("protected file")>=0||source.indexOf("file-integrity")>=0){
            if(change==="removed")return "File Is Missing"
            if(change==="added")return "New Protected File Detected"
            if(String(ev.expectedHash||"").length||String(ev.actualHash||"").length)return "Hash Did NOT Match"
            return change.length?change.charAt(0).toUpperCase()+change.slice(1)+" Integrity State Detected":"Integrity Verification Failed"
        }
        if(combined.indexOf("ssh")>=0&&combined.indexOf("auth")>=0)return "remote login authentication failed"+(incidentWhen(incident.time||incident.timestamp).length?" • "+incidentWhen(incident.time||incident.timestamp):"")
        if(combined.indexOf("authentication")>=0||combined.indexOf("password")>=0||combined.indexOf("login")>=0||combined.indexOf("pam")>=0){
            var authDetail=message.length?message:String(incident&&incident.evidence||"Authentication event")
            return authDetail+(incidentWhen(incident.time||incident.timestamp).length?" • "+incidentWhen(incident.time||incident.timestamp):"")
        }
        if(combined.indexOf("malware")>=0||combined.indexOf("virus")>=0||combined.indexOf("clam")>=0)return "suspicious file requires review"
        if(combined.indexOf("peripheral")>=0||combined.indexOf("usb")>=0)return "connected device is not trusted"
        if(combined.indexOf("firewall")>=0||combined.indexOf("blocked source")>=0||combined.indexOf("network")>=0)return "network activity was rejected by policy"
        var detail=message.length?message:String(incident&&incident.evidence||"Review in Security")
        return detail
    }
    function auditActionPresentation(entry) {
        var action=String(entry&&entry.action||"")
        var d=entry&&entry.details&&typeof entry.details==="object"?entry.details:({})
        var title="Security Action", detail=""
        if(action==="defcon_transition"){
            title="DEFCON "+String(d.fromLevel===undefined?"?":d.fromLevel)+" → DEFCON "+String(d.toLevel===undefined?"?":d.toLevel)
            detail=String(d.reason||((d.automatic===true)?"Automatic security response":"Authorized security change"))
        }else if(action==="events_acknowledged_bulk"){
            title="Security Notifications Acknowledged"; detail=String(Number(d.count||0))+" event"+(Number(d.count||0)===1?"":"s")+" cleared"
        }else if(action==="event_acknowledged"){
            title="Security Notification Acknowledged"; detail="Reviewed event marked acknowledged"
        }else if(action==="event_flag_changed"){
            title=d.flagged===true?"Security Event Flagged":"Security Event Unflagged"; detail=d.flagged===true?"Marked for follow-up review":"Review flag removed"
        }else if(action==="threat_neutralized"){
            title="Threat Neutralized"; detail="Threat acknowledged and normal readiness requested"
        }else if(action==="integrity_changes_detected"){
            title="Protected File Change Detected"; detail=String(Number(d.count||0))+" integrity change"+(Number(d.count||0)===1?"":"s")+" require review"
        }else if(action==="integrity_baseline_created"){
            title="Integrity Changes Approved"; detail=String(Number(d.files||0))+" protected files recorded in trusted baseline"
        }else if(action==="integrity_restored"){
            title="System Integrity Restored"; detail="Previous integrity condition cleared"
        }else if(action==="response_engine_changed"){
            title="Response Engine "+(d.enabled===true?"Enabled":"Disabled"); detail="Automated threat response setting changed"
        }else if(action==="network_enforcement_changed"){
            title="Enforcement "+(d.enabled===true?"Enabled":"Disabled"); detail="Network enforcement policy changed"
        }else if(action==="learning_mode_changed"){
            title="Learning Mode "+(d.enabled===true?"Enabled":"Disabled"); detail="Security learning behavior changed"
        }else if(action==="source_banned"){
            title="Source Blocked"; detail=String(d.address||d.source||"Network source added to block list")
        }else if(action==="source_unbanned"){
            title="Source Unblocked"; detail=String(d.address||d.source||"Network source removed from block list")
        }else if(action==="peripheral_blocked"){
            title="Peripheral Blocked"; detail=String(d.name||d.deviceId||"Device rejected")
        }else if(action==="peripheral_trusted"){
            title="Peripheral Trusted"; detail=String(d.name||d.deviceId||"Device added to trusted list")
        }else if(action==="malware_scan_completed"){
            title="Malware Scan Completed"; detail=String(Number(d.findings||d.threats||0))+" threat"+(Number(d.findings||d.threats||0)===1?"":"s")+" found"
        }else if(action==="hardening_applied"){
            title="System Hardening Applied"; detail=String(d.profile||"Security hardening profile changed")
        }else if(action==="ssh_service_changed"){
            title="SSH Access "+(d.enabled===true?"Enabled":"Disabled"); detail=d.success===false?"Service change failed":"Remote shell access changed"
        }else if(action==="tailscale_service_changed"){
            title="Tailscale "+(d.enabled===true?"Enabled":"Disabled"); detail=d.success===false?"Service change failed":"Private network access changed"
        }else{
            var pretty=action.replace(/_/g," ").replace(/\b\w/g,function(c){return c.toUpperCase()})
            title=pretty.length?pretty:"Security Action"
            detail=String(d.reason||d.message||d.result||"Security state updated")
        }
        return {title:title,detail:detail,time:incidentWhen(entry&&entry.timestamp||"")}
    }
    function recentSecurityActions() {
        var rows=[], source=securityBackend&&securityBackend.auditEntries?securityBackend.auditEntries:[]
        var skip={"snapshot_requested":true,"ipc_request_accepted":true,"ipc_endpoint_started":true}
        for(var i=0;i<source.length&&rows.length<5;++i){
            var entry=source[i]||({}), action=String(entry.action||"")
            if(skip[action]===true)continue
            rows.push(auditActionPresentation(entry))
        }
        while(rows.length<5)rows.push({title:"No additional security action",detail:"Waiting for new security activity",time:""})
        return rows
    }

    Loader {
        anchors.fill: root.contentItem
        sourceComponent: root.widgetId === "cpu" || root.widgetId === "memory" ? metricComponent
                       : root.widgetId === "temperature" ? temperatureComponent
                       : root.widgetId === "storage" || root.widgetId === "media-storage" ? storageComponent
                       : root.widgetId === "network" ? networkComponent
                       : root.widgetId === "uptime" ? uptimeComponent
                       : root.widgetId === "user-clock" ? userClockComponent
                       : securityComponent
    }

    Component {
        id: metricComponent
        Item {
            readonly property bool memoryMetric: root.widgetId === "memory"
            CircularMetricGauge {
                id: gauge
                anchors.left: root.tallShape ? undefined : parent.left
                anchors.leftMargin: root.tallShape ? 0 : root.detailCount > 0 ? 8 : (parent.width - width) / 2
                anchors.horizontalCenter: root.tallShape ? parent.horizontalCenter : undefined
                anchors.top: root.tallShape ? parent.top : undefined
                anchors.verticalCenter: root.tallShape ? undefined : parent.verticalCenter
                width: root.tallShape ? Math.min(parent.width*.78,parent.height*.43) : Math.min(parent.height*.90, root.detailCount>0 ? parent.width*.34 : parent.width*.72)
                height:width
                value: root.monitorBackend ? Number(memoryMetric?root.monitorBackend.ramPercent:root.monitorBackend.cpuPercent) : 0
                valid: root.monitorBackend ? Boolean(memoryMetric?root.monitorBackend.memoryValid:root.monitorBackend.cpuValid) : false
                label: memoryMetric?"RAM":"CPU"; startColor:memoryMetric?"#8B45FF":"#11DCFF"; endColor:memoryMetric?"#FF4DA0":"#2687FF"
            }
            Column {
                visible: root.detailCount>0
                anchors.left:root.tallShape?parent.left:gauge.right; anchors.leftMargin:root.tallShape?0:16; anchors.right:parent.right
                anchors.top:root.tallShape?gauge.bottom:undefined;anchors.topMargin:root.tallShape?8:0
                anchors.verticalCenter:root.tallShape?undefined:parent.verticalCenter; spacing:4
                Text { width:parent.width; text:memoryMetric
                            ? "USED  "+String(root.monitorBackend?root.monitorBackend.ramUsed||"--":"--")+" / "+String(root.monitorBackend?root.monitorBackend.ramTotal||"--":"--")
                            : String(root.monitorBackend?root.monitorBackend.cpuModel||"CPU unavailable":"CPU unavailable"); color:"#F4F8FF"; font.pixelSize:13*root.uiScale; font.bold:true; elide:Text.ElideRight }
                Text { width:parent.width; text:memoryMetric ? "TOP MEMORY CONSUMERS"
                            : "CORES  "+String(root.monitorBackend&&root.monitorBackend.cpuCores?root.monitorBackend.cpuCores.length:"--")+"   CLOCK  "+String(root.monitorBackend?root.monitorBackend.cpuFrequency||"--":"--")+"   LOAD  "+String(root.monitorBackend?root.monitorBackend.loadAverage||"--":"--"); color:"#7FDFF4"; font.pixelSize:10*root.uiScale; font.bold:true; elide:Text.ElideRight }
                Repeater { model:root.processRows(memoryMetric)
                    delegate: Item { required property var modelData; width:parent.width; height:29*root.uiScale
                        readonly property real fraction:root.processFraction(modelData,memoryMetric)
                        Text { anchors.left:parent.left; anchors.right:usageValue.left; anchors.rightMargin:8; text:String(modelData.name||"Unknown"); color:"#DDE8F6"; font.pixelSize:10.5*root.uiScale; elide:Text.ElideRight }
                        Text { id:usageValue; anchors.right:parent.right; width:parent.width*.30; text:memoryMetric?root.bytesText(modelData.memoryBytes):Number(modelData.cpu||0).toFixed(1)+"%"; color:root.processBarColor(parent.fraction); font.pixelSize:10.5*root.uiScale; font.bold:true; horizontalAlignment:Text.AlignRight }
                        Rectangle { anchors.left:parent.left; anchors.right:parent.right; anchors.bottom:parent.bottom; height:7*root.uiScale; radius:height/2; color:"#15263A"; border.width:1; border.color:"#2C4964"
                            Rectangle { width:parent.width*parent.parent.fraction; height:parent.height; radius:height/2; color:root.processBarColor(parent.parent.fraction) }
                        }
                    }
                }
            }
        }
    }
    Component { id:temperatureComponent; TemperatureGauge { temperatureFahrenheit:root.monitorBackend?Number(root.monitorBackend.cpuTemperature||0):0; history:root.monitorBackend&&root.monitorBackend.temperatureHistory?root.monitorBackend.temperatureHistory:[]; valid:root.monitorBackend?root.monitorBackend.temperatureValid:false; throttled:root.monitorBackend?root.monitorBackend.thermalThrottled:false; learnedBaseline:root.monitorBackend?Number(root.monitorBackend.learnedTemperatureBaseline||0):0; adaptiveStatus:root.monitorBackend?String(root.monitorBackend.adaptiveThermalStatus||"Stable"):"Unavailable"; criticalThreshold:root.monitorBackend?Number(root.monitorBackend.temperatureCriticalThreshold||160):160; animationEnabled:root.animationEnabled } }
    Component {
        id:storageComponent
        Item {
            id: storagePanel
            readonly property bool available: root.storageData && root.storageData.connected !== false &&
                                              root.storageData.mounted !== false
            readonly property real usedPercent: root.storageUsedPercent()
            readonly property var breakdown: root.storageBreakdown()
            readonly property var infoRows: root.storageBreakdownRows()
            readonly property bool breakdownScanning: Boolean(breakdown && breakdown.scanning)

            Component.onCompleted: root.requestStorageBreakdown(false)

            Connections {
                target: root.storageBackend
                enabled: target !== null
                function onDevicesChanged() {
                    root.requestStorageBreakdown(false)
                }
            }

            Timer {
                interval: 1800000
                repeat: true
                running: root.animationEnabled && storagePanel.visible
                onTriggered: root.requestStorageBreakdown(false)
            }

            Column {
                anchors.fill: parent
                anchors.margins: 5 * root.uiScale
                spacing: 6 * root.uiScale

                Item {
                    width: parent.width
                    height: 63 * root.uiScale

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.uiScale

                        Text {
                            width: parent.width
                            text: root.storageMountName(root.storageData)
                            color: storagePanel.available ? "#F8FAFF" : "#9AA6BA"
                            font.pixelSize: 22 * root.uiScale
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: storagePanel.available
                                  ? String(root.storageData.filesystem || root.storageData.fsType || root.storageData.fs || "--").toUpperCase()
                                  : "UNAVAILABLE"
                            color: storagePanel.available ? "#B6C2E8" : "#FF647D"
                            font.pixelSize: 10.5 * root.uiScale
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.storageManufacturer()
                            color: "#7F91B8"
                            font.pixelSize: 9 * root.uiScale
                            elide: Text.ElideRight
                        }
                    }

                }

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 7 * root.uiScale
                    rowSpacing: 4 * root.uiScale

                    Repeater {
                        model: [
                            {label:"USED", value:String(root.storageData.used || "--"), accent:"#E9EDF8"},
                            {label:"CAPACITY", value:String(root.storageData.total || root.storageData.capacity || "--"), accent:"#E9EDF8"},
                            {label:"FREE", value:String(root.storageData.available || root.storageData.free || "--"), accent:"#E9EDF8"},
                            {label:"USAGE", value:Math.round(storagePanel.usedPercent) + "%", accent:"#64B6FF"}
                        ]

                        delegate: Row {
                            required property var modelData
                            width: (parent.width - parent.columnSpacing) / 2
                            height: 22 * root.uiScale
                            spacing: 6 * root.uiScale

                            Text {
                                width: parent.width * .40
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.label)
                                color: "#6FA7FF"
                                font.pixelSize: 9.5 * root.uiScale
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width * .60 - parent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.value)
                                color: String(modelData.accent)
                                font.pixelSize: 10.5 * root.uiScale
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rectangle {
                    id: segmentedStorageBar
                    width: parent.width
                    height: 23 * root.uiScale
                    radius: 6 * root.uiScale
                    color: "#09152A"
                    border.width: 1
                    border.color: "#5F79EC"
                    clip: true

                    Row {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: storagePanel.infoRows

                            delegate: Rectangle {
                                required property var modelData
                                height: parent.height
                                width: Math.max(0,
                                    segmentedStorageBar.width *
                                    Math.max(0, Number(modelData.percent || 0)) / 100.0)
                                color: modelData.free === true
                                       ? "#101B35"
                                       : String(modelData.color || "#14BFFF")
                                border.width: modelData.free === true ? 0 : 0.5
                                border.color: Qt.lighter(color, 1.18)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: storagePanel.breakdownScanning &&
                                 (!storagePanel.breakdown.entries ||
                                  !storagePanel.breakdown.entries.length)
                        text: "ANALYZING STORAGE…"
                        color: "#D7E2FF"
                        font.pixelSize: 7.5 * root.uiScale
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#26395F"
                }

                Column {
                    width: parent.width
                    spacing: 4 * root.uiScale

                    Repeater {
                        model: storagePanel.infoRows

                        delegate: Row {
                            required property int index
                            required property var modelData
                            width: parent.width
                            height: 22 * root.uiScale
                            spacing: 7 * root.uiScale

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10 * root.uiScale
                                height: width
                                radius: 2 * root.uiScale
                                color: String(modelData.color)
                                border.width: 1
                                border.color: Qt.lighter(String(modelData.color), 1.35)
                            }
                            Text {
                                width: parent.width * .34
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.name)
                                color: "#E7EAF4"
                                font.pixelSize: 9.5 * root.uiScale
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width * .43
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(modelData.value)
                                color: "#E7EAF4"
                                font.pixelSize: 9 * root.uiScale
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideMiddle
                            }
                            Text {
                                width: parent.width * .16
                                anchors.verticalCenter: parent.verticalCenter
                                text: Number(modelData.percent) >= 0 ? Number(modelData.percent).toFixed(1) + "%" : ""
                                color: "#AAB7DC"
                                font.pixelSize: 8.5 * root.uiScale
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id:networkComponent
        Item {
            id: networkPanel
            property var downloadHistory: []
            property var uploadHistory: []
            property real currentDownload: 0
            property real currentUpload: 0
            property double lastHistorySampleMs: 0
            readonly property bool networkEnabled: {
                if (!root.networkBackend) return root.monitorBackend ? Boolean(root.monitorBackend.networkConnected) : false
                if (root.networkBackend.networkingEnabled !== undefined) return root.networkBackend.networkingEnabled === true
                return root.monitorBackend ? Boolean(root.monitorBackend.networkConnected) : true
            }
            readonly property bool connected: root.monitorBackend ? Boolean(root.monitorBackend.networkConnected) :
                                             String(root.networkBackend ? root.networkBackend.connectionState : "").toLowerCase().indexOf("connect") >= 0
            readonly property bool hotspotEnabled: root.localModeEnabled()
            readonly property bool tailscaleEnabled: networkPanel.boolValue(
                root.securityBackend && root.securityBackend.tailscaleStatus ?
                    (root.securityBackend.tailscaleStatus.enabled !== undefined ? root.securityBackend.tailscaleStatus.enabled :
                     root.securityBackend.tailscaleStatus.active !== undefined ? root.securityBackend.tailscaleStatus.active :
                     root.securityBackend.tailscaleStatus.running !== undefined ? root.securityBackend.tailscaleStatus.running :
                     root.securityBackend.tailscaleStatus.connected) : false)
            readonly property string ssidText: root.networkValue(root.networkBackend ? root.networkBackend.connectedSsid : "",
                                                                  root.monitorBackend ? root.monitorBackend.ssid : "") || "Network"
            readonly property string localIpText: root.networkValue(root.networkBackend ? root.networkBackend.localIp : "",
                                                                     root.monitorBackend ? root.monitorBackend.localIp : "") || "--"
            readonly property string interfaceText: root.networkValue(root.networkBackend ? root.networkBackend.interfaceName : "",
                                                                       root.monitorBackend ? root.monitorBackend.activeInterface : "") || "--"
            readonly property int signalValue: Math.max(0, Math.min(100, Number(root.networkBackend ? root.networkBackend.signalPercent : 0) || 0))
            readonly property string gatewayText: root.networkValue(root.networkBackend ? root.networkBackend.gateway : "", "") || "--"
            readonly property string tailscaleText: root.networkValue(root.networkBackend ? root.networkBackend.tailscaleIp : "",
                                                                       root.monitorBackend ? root.monitorBackend.tailscaleIp : "") || "--"
            function activeInterfaceName() {
                var monitorName = root.networkValue(root.monitorBackend ? root.monitorBackend.activeInterface : "", "")
                var backendName = root.networkValue(root.networkBackend ? root.networkBackend.interfaceName : "", "")
                return monitorName.length ? monitorName : backendName
            }
            function interfaceTypeText() {
                var name = activeInterfaceName().toLowerCase()
                if (name.indexOf("wl") === 0 || name.indexOf("wifi") >= 0 || name.indexOf("wireless") >= 0)
                    return "WI-FI"
                if (name.indexOf("eth") === 0 || name.indexOf("en") === 0 || name.indexOf("ether") >= 0)
                    return "Ethernet"
                return name.length ? activeInterfaceName() : "--"
            }
            function parseRateText(value) {
                var text = String(value === undefined || value === null ? "" : value).trim()
                if (!text.length || text === "--") return 0
                var match = text.match(/([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB)\/s/i)
                if (!match) return 0
                var number = Number(match[1]) || 0
                var unit = String(match[2]).toUpperCase()
                if (unit === "GB") return number * 1000000000
                if (unit === "MB") return number * 1000000
                if (unit === "KB") return number * 1000
                return number
            }
            // The graph uses megabits/second end-to-end. NetworkManager's
            // speed-test API already reports Mbps, while SystemMonitor reports
            // live interface traffic in bytes/second. Convert the live counters
            // here so the graph, axis labels, and displayed speed all use the
            // same unit instead of showing 27.8 Mbps as roughly 3.5 MB/s.
            function bytesPerSecondToMbps(bytesPerSecond) {
                return Math.max(0, Number(bytesPerSecond || 0)) * 8.0 / 1000000.0
            }
            function testedDownloadRate() {
                return root.networkBackend ? Math.max(0, Number(root.networkBackend.downloadMbps || 0)) : 0
            }
            function testedUploadRate() {
                return root.networkBackend ? Math.max(0, Number(root.networkBackend.uploadMbps || 0)) : 0
            }
            function liveDownloadRate() {
                if (!root.monitorBackend) return 0
                var raw = Number(root.monitorBackend.rxBytesPerSecond || 0)
                if (raw > 0) return bytesPerSecondToMbps(raw)
                return bytesPerSecondToMbps(parseRateText(root.monitorBackend.download))
            }
            function liveUploadRate() {
                if (!root.monitorBackend) return 0
                var raw = Number(root.monitorBackend.txBytesPerSecond || 0)
                if (raw > 0) return bytesPerSecondToMbps(raw)
                return bytesPerSecondToMbps(parseRateText(root.monitorBackend.upload))
            }
            function readDownloadRate() {
                var estimate = testedDownloadRate()
                return estimate > 0 ? estimate : liveDownloadRate()
            }
            function readUploadRate() {
                var estimate = testedUploadRate()
                return estimate > 0 ? estimate : liveUploadRate()
            }
            function mbpsText(value) {
                var n = Math.max(0, Number(value || 0))
                if (n >= 100) return n.toFixed(0) + " Mbps"
                if (n >= 10) return n.toFixed(1) + " Mbps"
                if (n >= 1) return n.toFixed(2) + " Mbps"
                if (n > 0) return Math.round(n * 1000) + " Kbps"
                return "0 Mbps"
            }
            function downloadText() {
                return mbpsText(currentDownload)
            }
            function uploadText() {
                return mbpsText(currentUpload)
            }
            function niceGraphScale(peakValue) {
                var peak = Math.max(0.1, Number(peakValue || 0))
                var levels = [
                    0.5, 1, 2.5, 5, 10, 20, 40, 60,
                    100, 200, 400, 600, 1000, 2500, 5000, 10000
                ]
                var wanted = peak * 1.15
                for (var k = 0; k < levels.length; ++k)
                    if (levels[k] >= wanted) return levels[k]
                return Math.ceil(wanted / 1000.0) * 1000.0
            }
            function downloadScaleMax() {
                var peak = Math.max(currentDownload, 0.1)
                for (var i = 0; i < downloadHistory.length; ++i)
                    peak = Math.max(peak, Number(downloadHistory[i] || 0))
                return niceGraphScale(peak)
            }
            function uploadScaleMax() {
                var peak = Math.max(currentUpload, 0.1)
                for (var i = 0; i < uploadHistory.length; ++i)
                    peak = Math.max(peak, Number(uploadHistory[i] || 0))
                return niceGraphScale(peak)
            }
            function graphAxisText(mbps) {
                var n = Math.max(0, Number(mbps || 0))
                if (n >= 1000) {
                    var gbps = n / 1000.0
                    return (gbps >= 10 ? gbps.toFixed(0) : gbps.toFixed(1)) + " Gbps"
                }
                if (n >= 10) return n.toFixed(0) + " Mbps"
                if (n >= 1) return n.toFixed(n % 1 === 0 ? 0 : 1) + " Mbps"
                if (n > 0) return Math.round(n * 1000) + " Kbps"
                return "0 Mbps"
            }
            function refreshLiveRates(addHistory) {
                currentDownload = readDownloadRate()
                currentUpload = readUploadRate()

                if (addHistory === false) {
                    trafficCanvas.requestPaint()
                    return
                }

                var now = Date.now()
                if (now - lastHistorySampleMs >= 750) {
                    lastHistorySampleMs = now
                    appendSample()
                } else {
                    trafficCanvas.requestPaint()
                }
            }

            function boolValue(value) {
                if (value === true || value === 1) return true
                var text = String(value === undefined || value === null ? "" : value).toLowerCase()
                return text === "true" || text === "1" || text === "yes" || text === "enabled" ||
                       text === "active" || text === "running" || text === "connected" || text === "on"
            }
            function appendSample() {
                var down = downloadHistory.slice(0)
                var up = uploadHistory.slice(0)
                down.push(currentDownload)
                up.push(currentUpload)
                while (down.length > 24) down.shift()
                while (up.length > 24) up.shift()
                downloadHistory = down
                uploadHistory = up
                trafficCanvas.requestPaint()
            }
            function toggleHotspot() {
                if (!root.networkBackend || typeof root.networkBackend.setOfflineNetworkMode !== "function") return
                root.networkBackend.setOfflineNetworkMode(hotspotEnabled ? "normal-wifi" : "wifi-hotspot")
            }
            function toggleTailscale() {
                if (root.securityBackend && typeof root.securityBackend.setTailscaleEnabled === "function")
                    root.securityBackend.setTailscaleEnabled(!tailscaleEnabled)
            }
            function runScan() {
                root.networkActionRequested(2)
            }
            function runSpeed() {
                root.networkActionRequested(3)
            }
            function runDiagnostics() {
                root.networkActionRequested(4)
            }

            Component.onCompleted: {
                for (var i = 0; i < 24; ++i) {
                    downloadHistory.push(0)
                    uploadHistory.push(0)
                }
                refreshLiveRates(false)
                appendSample()
            }

            // SystemMonitor already calculates authoritative interface throughput.
            // Read it explicitly whenever its shared telemetry signal fires instead
            // of depending on an indirect nested binding inside the loaded component.
            Connections {
                target: root.monitorBackend
                enabled: target !== null
                function onSystemChanged() {
                    networkPanel.refreshLiveRates(true)
                }
            }
            Connections {
                target: root.networkBackend
                enabled: target !== null
                function onSpeedTestResultsChanged() {
                    networkPanel.refreshLiveRates(true)
                }
                function onSpeedTestRunningChanged() {
                    networkPanel.refreshLiveRates(true)
                }
            }

            // Low-cost fallback for a missed/coalesced telemetry signal. This only
            // reads existing properties; it does not perform another network sample.
            Timer {
                interval: 2000
                running: root.animationEnabled && networkPanel.visible
                repeat: true
                onTriggered: networkPanel.refreshLiveRates(true)
            }

            Timer {
                interval: 20000
                running: root.animationEnabled && networkPanel.visible && networkPanel.networkEnabled
                repeat: true
                triggeredOnStart: false
                onTriggered: {
                    if (root.networkBackend &&
                            typeof root.networkBackend.runQuickSpeedProbe === "function" &&
                            !(root.networkBackend.speedTestRunning === true))
                        root.networkBackend.runQuickSpeedProbe()
                }
            }

            Column {
                anchors.fill: parent
                spacing: 7 * root.uiScale

                Item {
                    width: parent.width
                    height: 42 * root.uiScale
                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * root.uiScale
                        Text {
                            // Hotspot mode intentionally uses the NeutronOS SSID as
                            // a red visual warning that this is only the local AP,
                            // not an active upstream Wi-Fi connection.
                            text: networkPanel.hotspotEnabled ? "NeutronOS" : networkPanel.ssidText
                            color: networkPanel.hotspotEnabled ? "#FF4058" : "#F7FAFF"
                            font.pixelSize: 21 * root.uiScale
                            font.bold: true
                            elide: Text.ElideRight
                            width: Math.max(100, networkPanel.width * .55)
                        }
                        Rectangle {
                            width: statusText.implicitWidth + 15 * root.uiScale
                            height: 17 * root.uiScale
                            radius: height / 2
                            color: networkPanel.networkEnabled ? "#183F34" : "#451D29"
                            border.width: 1
                            border.color: networkPanel.networkEnabled ? "#49E7A2" : "#FF5273"
                            Text {
                                id: statusText
                                anchors.centerIn: parent
                                text: networkPanel.networkEnabled ? (networkPanel.connected ? "CONNECTED" : "ENABLED") : "DISABLED"
                                color: networkPanel.networkEnabled ? "#6CFFBA" : "#FF607E"
                                font.pixelSize: 9.5 * root.uiScale
                                font.bold: true
                                font.letterSpacing: 1.0
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 44 * root.uiScale
                    spacing: 12 * root.uiScale
                    Repeater {
                        model: [
                            {label:"LOCAL IP", value:networkPanel.localIpText, sub:"LOCAL NETWORK"},
                            {label:"INTERFACE", value:networkPanel.interfaceTypeText(), sub:networkPanel.activeInterfaceName()},
                            {label:"SIGNAL", value:networkPanel.signalValue + "%", sub:"GATEWAY  " + networkPanel.gatewayText},
                            {label:"TAILSCALE IP", value:networkPanel.tailscaleText, sub:"TAILSCALE"}
                        ]
                        delegate: Column {
                            required property var modelData
                            width: (parent.width - parent.spacing * 3) / 4
                            spacing: 1 * root.uiScale
                            Text { width:parent.width; text:String(modelData.label); color:"#8F9DD8"; font.pixelSize:8.5*root.uiScale; font.bold:true; font.letterSpacing:.8; elide:Text.ElideRight }
                            Text { width:parent.width; text:String(modelData.value); color:"#F7FAFF"; font.pixelSize:11*root.uiScale; font.bold:true; elide:Text.ElideMiddle }
                            Text { width:parent.width; text:String(modelData.sub); color:"#7585BF"; font.pixelSize:7.5*root.uiScale; font.bold:true; elide:Text.ElideRight }
                        }
                    }
                }

                Item {
                    id: graphArea
                    width: parent.width
                    height: Math.max(92 * root.uiScale, parent.height - (42 + 44 + 48 + 54) * root.uiScale - parent.spacing * 4)

                    Text { x:0; y:1*root.uiScale; text:networkPanel.graphAxisText(networkPanel.downloadScaleMax()); color:"#8493C4"; font.pixelSize:7.5*root.uiScale }
                    Text { x:7*root.uiScale; y:graphArea.height*.24; text:networkPanel.graphAxisText(networkPanel.downloadScaleMax()/2); color:"#8493C4"; font.pixelSize:7.5*root.uiScale }
                    Text { x:13*root.uiScale; y:graphArea.height*.48-5*root.uiScale; text:"0 Mbps"; color:"#8493C4"; font.pixelSize:7.5*root.uiScale }
                    Text { x:7*root.uiScale; y:graphArea.height*.72-4*root.uiScale; text:networkPanel.graphAxisText(networkPanel.uploadScaleMax()/2); color:"#8493C4"; font.pixelSize:7.5*root.uiScale }
                    Text { x:0; y:graphArea.height-12*root.uiScale; text:networkPanel.graphAxisText(networkPanel.uploadScaleMax()); color:"#8493C4"; font.pixelSize:7.5*root.uiScale }

                    Canvas {
                        id: trafficCanvas
                        x: 43 * root.uiScale
                        y: 3 * root.uiScale
                        width: graphArea.width - 43 * root.uiScale - 75 * root.uiScale
                        height: graphArea.height - 7 * root.uiScale
                        antialiasing: true
                        onPaint: {
                            var ctx = getContext("2d")
                            var w = width, h = height, mid = h / 2
                            ctx.clearRect(0, 0, w, h)
                            ctx.lineWidth = 1
                            ctx.setLineDash([4, 4])
                            ctx.strokeStyle = "#33456A"
                            for (var g = 0; g <= 4; ++g) {
                                var gy = h * g / 4
                                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                            }
                            ctx.setLineDash([])
                            ctx.strokeStyle = "#6377A8"
                            ctx.beginPath(); ctx.moveTo(0, mid); ctx.lineTo(w, mid); ctx.stroke()

                            function drawSeries(values, upper, lineColor, fillTop, fillBottom, scaleMax) {
                                if (!values || values.length < 2) return
                                var maxRate = Math.max(0.1, Number(scaleMax || 0.1))
                                var step = w / Math.max(1, values.length - 1)
                                var points = []
                                for (var i = 0; i < values.length; ++i) {
                                    var normalized = Math.min(1, Math.max(0, Number(values[i] || 0) / maxRate))
                                    var y = upper ? mid - normalized * (mid - 3) : mid + normalized * (mid - 3)
                                    points.push({x:i*step,y:y})
                                }
                                var grad = ctx.createLinearGradient(0, upper ? 0 : mid, 0, upper ? mid : h)
                                grad.addColorStop(0, fillTop)
                                grad.addColorStop(1, fillBottom)
                                ctx.beginPath(); ctx.moveTo(points[0].x, mid); ctx.lineTo(points[0].x, points[0].y)
                                for (var p = 1; p < points.length; ++p) {
                                    var prev = points[p-1], cur = points[p]
                                    var mx = (prev.x + cur.x) / 2
                                    ctx.quadraticCurveTo(prev.x, prev.y, mx, (prev.y + cur.y) / 2)
                                }
                                ctx.lineTo(points[points.length-1].x, points[points.length-1].y)
                                ctx.lineTo(points[points.length-1].x, mid); ctx.closePath()
                                ctx.fillStyle = grad; ctx.fill()
                                ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y)
                                for (var q = 1; q < points.length; ++q) {
                                    var a = points[q-1], b = points[q]
                                    var mx2 = (a.x + b.x) / 2
                                    ctx.quadraticCurveTo(a.x, a.y, mx2, (a.y + b.y) / 2)
                                }
                                ctx.lineTo(points[points.length-1].x, points[points.length-1].y)
                                ctx.strokeStyle = lineColor; ctx.lineWidth = 2 * root.uiScale; ctx.stroke()
                            }
                            drawSeries(networkPanel.downloadHistory, true, "#38A8FF", "rgba(46,127,224,0.34)", "rgba(46,127,224,0.0)", networkPanel.downloadScaleMax())
                            drawSeries(networkPanel.uploadHistory, false, "#FF526E", "rgba(255,70,109,0.0)", "rgba(255,70,109,0.34)", networkPanel.uploadScaleMax())
                        }
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70 * root.uiScale
                        spacing: 15 * root.uiScale
                        Column {
                            spacing:1
                            Text { text:"▼  "+networkPanel.downloadText(); color:"#48AFFF"; font.pixelSize:9.5*root.uiScale; font.bold:true }
                            Text { text:"DOWNLOAD"; color:"#8998C7"; font.pixelSize:7.5*root.uiScale; font.bold:true }
                        }
                        Column {
                            spacing:1
                            Text { text:"▲  "+networkPanel.uploadText(); color:"#FF5A75"; font.pixelSize:9.5*root.uiScale; font.bold:true }
                            Text { text:"UPLOAD"; color:"#8998C7"; font.pixelSize:7.5*root.uiScale; font.bold:true }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 48 * root.uiScale
                    spacing: 10 * root.uiScale
                    Rectangle {
                        width:(parent.width-parent.spacing)/2; height:parent.height; radius:16*root.uiScale
                        color: root.networkPanelActive && root.networkActionIndex===0 ? "#1A3151" : "#101C36"
                        border.width: root.networkPanelActive && root.networkActionIndex===0 ? 2 : 1
                        border.color: root.networkPanelActive && root.networkActionIndex===0 ? "#4EE8FF" : "#48547C"
                        Row { anchors.fill:parent; anchors.margins:10*root.uiScale; spacing:10*root.uiScale
                            Text { anchors.verticalCenter:parent.verticalCenter; text:"((•))"; color:"#F5F8FF"; font.pixelSize:14*root.uiScale; font.bold:true }
                            Column { anchors.verticalCenter:parent.verticalCenter; width:parent.width-86*root.uiScale; spacing:1
                                Text { text:"Hotspot"; color:"#B8C4EE"; font.pixelSize:9*root.uiScale }
                                Text { text:networkPanel.hotspotEnabled?"ON":"OFF"; color:networkPanel.hotspotEnabled?"#53F0B0":"#FF5876"; font.pixelSize:10.5*root.uiScale; font.bold:true }
                            }
                            Rectangle { anchors.verticalCenter:parent.verticalCenter; width:42*root.uiScale; height:22*root.uiScale; radius:height/2; color:networkPanel.hotspotEnabled?"#1E986E":"#9B2940"; border.width:1; border.color:networkPanel.hotspotEnabled?"#5CFFC0":"#FF6480"
                                Rectangle { width:16*root.uiScale; height:16*root.uiScale; radius:width/2; color:"white"; anchors.verticalCenter:parent.verticalCenter; x:networkPanel.hotspotEnabled?parent.width-width-3*root.uiScale:3*root.uiScale; Behavior on x{NumberAnimation{duration:120}} }
                            }
                        }
                        MouseArea { anchors.fill:parent; onClicked:networkPanel.toggleHotspot() }
                    }
                    Rectangle {
                        width:(parent.width-parent.spacing)/2; height:parent.height; radius:16*root.uiScale
                        color: root.networkPanelActive && root.networkActionIndex===1 ? "#1A3151" : "#101C36"
                        border.width: root.networkPanelActive && root.networkActionIndex===1 ? 2 : 1
                        border.color: root.networkPanelActive && root.networkActionIndex===1 ? "#4EE8FF" : "#48547C"
                        Row { anchors.fill:parent; anchors.margins:10*root.uiScale; spacing:10*root.uiScale
                            Text { anchors.verticalCenter:parent.verticalCenter; text:"⠿"; color:"#A6A9D7"; font.pixelSize:20*root.uiScale }
                            Column { anchors.verticalCenter:parent.verticalCenter; width:parent.width-86*root.uiScale; spacing:1
                                Text { text:"Tailscale"; color:"#B8C4EE"; font.pixelSize:9*root.uiScale }
                                Text { text:networkPanel.tailscaleEnabled?"ON":"OFF"; color:networkPanel.tailscaleEnabled?"#53F0B0":"#FF5876"; font.pixelSize:10.5*root.uiScale; font.bold:true }
                            }
                            Rectangle { anchors.verticalCenter:parent.verticalCenter; width:42*root.uiScale; height:22*root.uiScale; radius:height/2; color:networkPanel.tailscaleEnabled?"#1E986E":"#9B2940"; border.width:1; border.color:networkPanel.tailscaleEnabled?"#5CFFC0":"#FF6480"
                                Rectangle { width:16*root.uiScale; height:16*root.uiScale; radius:width/2; color:"white"; anchors.verticalCenter:parent.verticalCenter; x:networkPanel.tailscaleEnabled?parent.width-width-3*root.uiScale:3*root.uiScale; Behavior on x{NumberAnimation{duration:120}} }
                            }
                        }
                        MouseArea { anchors.fill:parent; onClicked:networkPanel.toggleTailscale() }
                    }
                }

                Row {
                    width: parent.width
                    height: 54 * root.uiScale
                    spacing: 8 * root.uiScale
                    Repeater {
                        model: [
                            {icon:"⌕", title:"Scan", sub:(root.networkBackend&&root.networkBackend.scanning)?"Scanning…":"Scan Networks"},
                            {icon:"◴", title:"Speed Check", sub:(root.networkBackend&&root.networkBackend.speedTestRunning)?"Testing…":
                                (root.networkBackend&&Number(root.networkBackend.downloadMbps||0)>0 ?
                                 Number(root.networkBackend.downloadMbps||0).toFixed(1)+"↓  "+Number(root.networkBackend.uploadMbps||0).toFixed(1)+"↑ Mbps" :
                                 "Run Speed Test")},
                            {icon:"⌁", title:"Network Diagnostic", sub:(root.networkBackend&&root.networkBackend.diagnosticsRunning)?"Running…":
                                (root.networkBackend&&String(root.networkBackend.diagnosticsSummary||"").length ?
                                 String(root.networkBackend.diagnosticsSummary) : "Run Diagnostics")}
                        ]
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width:(parent.width-parent.spacing*2)/3; height:parent.height; radius:14*root.uiScale
                            color:root.networkPanelActive&&root.networkActionIndex===index+2?"#1A3151":"#101C36"
                            border.width:root.networkPanelActive&&root.networkActionIndex===index+2?2:1
                            border.color:root.networkPanelActive&&root.networkActionIndex===index+2?"#4EE8FF":"#48547C"
                            Row { anchors.fill:parent; anchors.margins:8*root.uiScale; spacing:7*root.uiScale
                                Text { anchors.verticalCenter:parent.verticalCenter; text:String(modelData.icon); color:"#F7FAFF"; font.pixelSize:19*root.uiScale }
                                Column { anchors.verticalCenter:parent.verticalCenter; width:parent.width-42*root.uiScale; spacing:1
                                    Text { width:parent.width; text:String(modelData.title); color:"#C2CBEF"; font.pixelSize:9*root.uiScale; elide:Text.ElideRight }
                                    Text { width:parent.width; text:String(modelData.sub); color:"#7F8DBE"; font.pixelSize:7*root.uiScale; elide:Text.ElideRight }
                                }
                            }
                            MouseArea { anchors.fill:parent; onClicked:{ if(index===0)networkPanel.runScan(); else if(index===1)networkPanel.runSpeed(); else networkPanel.runDiagnostics() } }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: uptimeComponent
        Item {
            Column { anchors.centerIn:parent; width:parent.width; spacing:7
                Text { width:parent.width; text:root.monitorBackend&&root.monitorBackend.uptimeValid?String(root.monitorBackend.uptime||"Unknown"):"Unavailable"; color:"white"; font.pixelSize:23*root.uiScale; font.weight:Font.DemiBold; horizontalAlignment:Text.AlignHCenter; elide:Text.ElideRight }
                Text { width:parent.width; text:"SYSTEM UPTIME"; color:"#61E8FF"; font.pixelSize:10*root.uiScale; font.bold:true; font.letterSpacing:1.6; horizontalAlignment:Text.AlignHCenter }
                Text { visible:root.widgetSize!=="small"; width:parent.width; text:"BOOT  "+String(root.monitorBackend&&root.monitorBackend.bootDateTime?Qt.formatDateTime(root.monitorBackend.bootDateTime,"MMM d  h:mm AP"):"Unknown"); color:"#8FA8C2"; font.pixelSize:10*root.uiScale; horizontalAlignment:Text.AlignHCenter }
            }
        }
    }
    Component {
        id: userClockComponent
        Item {
            id: userCard
            clip: true

            readonly property var profile: root.authoritativeUser()
            readonly property string roleText:
                root.cleanValue(profile.role || profile.accountRole || profile.userRole) || "Administrator"
            // NEUTRONOS_PROFILE_CONTROLLER_BATTERY_V1
            readonly property bool controllerConnected: {
                try {
                    return root.controllerBackend &&
                           root.controllerBackend.controllerConnected === true
                } catch (error) {
                    return false
                }
            }
            readonly property int controllerBatteryPercent: {
                try {
                    if (!controllerConnected ||
                            (root.controllerBackend.controllerBatteryAvailable !== undefined &&
                             !root.controllerBackend.controllerBatteryAvailable))
                        return -1
                    var value = Number(root.controllerBackend.controllerBatteryPercent)
                    if (isNaN(value))
                        return -1
                    return Math.max(0, Math.min(100, Math.round(value)))
                } catch (error) {
                    return -1
                }
            }
            readonly property bool controllerCharging: {
                try {
                    return controllerConnected &&
                           root.controllerBackend.controllerCharging === true
                } catch (error) {
                    return false
                }
            }
            readonly property color controllerBatteryColor:
                controllerCharging ? "#52F0A7" :
                (controllerBatteryPercent >= 0 && controllerBatteryPercent < 25
                 ? "#FF4058" :
                   (controllerBatteryPercent >= 0 ? "#E8ECFF" : "#8396C3"))
            readonly property bool connected:
                Boolean((root.monitorBackend && root.monitorBackend.networkConnected) ||
                        (root.networkBackend && String(root.networkBackend.connectionState || "").toLowerCase() === "connected"))
            readonly property bool secure: !root.securityNeedsAttention()
            readonly property string tailscaleIp:
                root.networkValue(root.networkBackend ? root.networkBackend.tailscaleIp : "",
                                  root.monitorBackend ? root.monitorBackend.tailscaleIp : "")
            readonly property string networkText:
                tailscaleIp.length ? "Tailscale Online" :
                connected ? (root.networkValue(root.networkBackend ? root.networkBackend.connectedSsid : "",
                                               root.monitorBackend ? root.monitorBackend.ssid : "") || "Connected") :
                            "Offline"
            readonly property int cpuLoad:
                Math.max(0, Math.min(100, Number(root.monitorBackend ?
                    (root.monitorBackend.cpuPercent !== undefined ? root.monitorBackend.cpuPercent :
                     root.monitorBackend.cpuUsagePercent || 0) : 0)))
            readonly property real tempC:
                root.monitorBackend && root.monitorBackend.temperatureValid
                    ? Number(root.monitorBackend.temperatureCelsius || 0) : 0
            readonly property string thermalState: {
                if (!root.monitorBackend || !root.monitorBackend.temperatureValid)
                    return "UNAVAILABLE"
                var state = String(root.monitorBackend.adaptiveThermalStatus || "").toUpperCase()
                if (state === "COOL") return "COOL"
                if (state === "WARM") return "WARM"
                if (state === "HOT") return "HOT"
                return "NOMINAL"
            }
            readonly property string loadState:
                cpuLoad >= 85 ? "HIGH" : cpuLoad >= 65 ? "ELEVATED" : "OPTIMAL"
            readonly property color loadStateColor:
                cpuLoad >= 85 ? "#FF5B72" : cpuLoad >= 65 ? "#FFD25A" : "#49EF9E"
            readonly property color tempStateColor:
                thermalState === "HOT" ? "#FF526E" :
                thermalState === "WARM" ? "#FFB64A" :
                thermalState === "COOL" ? "#45DFFF" : "#49EF9E"

            Image {
                anchors.fill: parent
                source: Qt.resolvedUrl("../../../themes/Default/usercardbackground.png")
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                cache: true
            }

            // Dark glass veil keeps live text readable without hiding the custom background.
            Rectangle {
                anchors.fill: parent
                color: "#24030A1C"
                radius: Math.max(12, 18 * root.uiScale)
            }

            // Profile title and divider.
            Row {
                id: profileHeader
                anchors.top: parent.top
                anchors.topMargin: 8 * root.uiScale
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.62
                height: 18 * root.uiScale
                spacing: 8 * root.uiScale

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: (parent.width - titleLabel.implicitWidth - parent.spacing * 2) / 2
                    height: 1
                    color: "#35548D"
                }
                Text {
                    id: titleLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NEUTRONOS PROFILE"
                    color: "#63DFFF"
                    font.pixelSize: Math.max(7, 8.5 * root.uiScale)
                    font.bold: true
                    font.letterSpacing: 3.0
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: (parent.width - titleLabel.implicitWidth - parent.spacing * 2) / 2
                    height: 1
                    color: "#7B367E"
                }
            }

            // Top profile area.
            Item {
                id: topArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: profileHeader.bottom
                anchors.topMargin: 5 * root.uiScale
                height: parent.height * 0.39

                // Avatar with cyan->magenta neon ring.
                Rectangle {
                    id: avatarOuter
                    anchors.left: parent.left
                    anchors.leftMargin: 18 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(topArea.height * 0.82, parent.width * 0.18)
                    height: width
                    radius: width / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#1CCBFF" }
                        GradientStop { position: 0.48; color: "#6658FF" }
                        GradientStop { position: 1.0; color: "#FF45CE" }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Math.max(3, parent.width * 0.035)
                        radius: width / 2
                        color: "#07132A"

                        Image {
                            id: userAvatar
                            anchors.fill: parent
                            anchors.margins: Math.max(3, parent.width * 0.035)
                            source: failed
                                ? Qt.resolvedUrl("../../../themes/Default/users/user_icon.png")
                                : root.userAvatarSource()
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            cache: true
                            property bool failed: false
                            onStatusChanged: if (status === Image.Error && !failed) failed = true
                        }
                    }
                }

                Column {
                    id: identityColumn
                    anchors.left: avatarOuter.right
                    anchors.leftMargin: 13 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.29
                    spacing: 1 * root.uiScale

                    Text {
                        width: parent.width
                        text: root.userDisplayName()
                        color: "#F6F8FF"
                        font.pixelSize: Math.max(15, 19 * root.uiScale)
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: "@" + root.userName()
                        color: "#51DFFF"
                        font.pixelSize: Math.max(9, 10 * root.uiScale)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.clockBackend
                              ? String(root.clockBackend.currentTimeText || "--:--")
                              : Qt.formatTime(new Date(), "h:mm AP")
                        color: "#FFFFFF"
                        font.pixelSize: Math.max(21, 27 * root.uiScale)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.clockBackend
                              ? String(root.clockBackend.currentDateText || "")
                              : Qt.formatDate(new Date(), "dddd, MMMM d")
                        color: "#67AFFF"
                        font.pixelSize: Math.max(8, 9.5 * root.uiScale)
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: profileInfo
                    anchors.right: parent.right
                    anchors.rightMargin: 18 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.43
                    height: parent.height * 0.86
                    radius: 9 * root.uiScale
                    color: "#75061022"
                    border.width: 1
                    border.color: "#385287"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 7 * root.uiScale
                        spacing: 0

                        Repeater {
                            model: [
                                {icon:"♙", label:"ROLE", value:userCard.roleText,
                                 color:"#E8ECFF"},
                                {icon:"●", label:"STATUS", value:userCard.connected ? "Connected" : "Offline",
                                 color:userCard.connected ? "#52F0A7" : "#FF6078"},
                                {icon:"◇", label:"SECURITY", value:userCard.secure ? "Secure" : "Attention",
                                 color:userCard.secure ? "#52F0A7" : "#FF6078",
                                 labelColor:userCard.secure ? "#8396C3" : "#FF526E"},
                                {icon:"▣", label:"HOST", value:"Gemini",
                                 color:"#E8ECFF"},
                                {icon:"⌁", label:"NETWORK", value:userCard.networkText,
                                 color:userCard.connected ? "#E8ECFF" : "#FF6078"},
                                {icon:"∿", label:"SESSION", value:"Local Console",
                                 color:"#E8ECFF"},
                                {icon:"", controllerIcon:true, label:"BATTERY",
                                 value:userCard.controllerBatteryPercent >= 0
                                       ? userCard.controllerBatteryPercent + "%" : "--%",
                                 color:userCard.controllerBatteryColor}
                            ]

                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: profileInfo.height / 7.45

                                Row {
                                    anchors.fill: parent
                                    spacing: 5 * root.uiScale

                                    Item {
                                        width: 14 * root.uiScale
                                        height: parent.height
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            visible: modelData.controllerIcon !== true
                                            text: String(modelData.icon || "")
                                            color: "#34DFFF"
                                            font.pixelSize: 10 * root.uiScale
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        Item {
                                            anchors.centerIn: parent
                                            width: 14 * root.uiScale
                                            height: 10 * root.uiScale
                                            visible: modelData.controllerIcon === true

                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.top: parent.top
                                                anchors.topMargin: 1 * root.uiScale
                                                width: 11 * root.uiScale
                                                height: 6 * root.uiScale
                                                radius: 2.5 * root.uiScale
                                                color: "#08111F"
                                                border.width: 1
                                                border.color: "#34DFFF"
                                            }
                                            Rectangle {
                                                x: 0.7 * root.uiScale
                                                y: 4.2 * root.uiScale
                                                width: 4.6 * root.uiScale
                                                height: 5 * root.uiScale
                                                radius: 2 * root.uiScale
                                                rotation: 18
                                                color: "#08111F"
                                                border.width: 1
                                                border.color: "#34DFFF"
                                            }
                                            Rectangle {
                                                x: 8.7 * root.uiScale
                                                y: 4.2 * root.uiScale
                                                width: 4.6 * root.uiScale
                                                height: 5 * root.uiScale
                                                radius: 2 * root.uiScale
                                                rotation: -18
                                                color: "#08111F"
                                                border.width: 1
                                                border.color: "#34DFFF"
                                            }
                                            Rectangle {
                                                x: 3.1 * root.uiScale
                                                y: 3.1 * root.uiScale
                                                width: 3.3 * root.uiScale
                                                height: 1 * root.uiScale
                                                radius: .5 * root.uiScale
                                                color: "#34DFFF"
                                            }
                                            Rectangle {
                                                x: 4.25 * root.uiScale
                                                y: 1.95 * root.uiScale
                                                width: 1 * root.uiScale
                                                height: 3.3 * root.uiScale
                                                radius: .5 * root.uiScale
                                                color: "#34DFFF"
                                            }
                                            Rectangle {
                                                x: 9.2 * root.uiScale
                                                y: 2.7 * root.uiScale
                                                width: 1.4 * root.uiScale
                                                height: 1.4 * root.uiScale
                                                radius: .7 * root.uiScale
                                                color: userCard.controllerCharging
                                                       ? "#52F0A7"
                                                       : (userCard.controllerBatteryPercent >= 0 &&
                                                          userCard.controllerBatteryPercent < 25
                                                          ? "#FF4058" : "#E8ECFF")
                                            }
                                        }
                                    }
                                    Text {
                                        width: parent.width * 0.35
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.label)
                                        color: modelData.labelColor !== undefined
                                               ? String(modelData.labelColor)
                                               : "#8396C3"
                                        font.pixelSize: 7.6 * root.uiScale
                                        font.bold: true
                                        font.letterSpacing: 1.1
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width -
                                               14 * root.uiScale -
                                               parent.spacing * 2 -
                                               parent.width * 0.35
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(modelData.value)
                                        color: String(modelData.color)
                                        font.pixelSize: 8.6 * root.uiScale
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: "#18315B"
                                    visible: index < 6
                                }
                            }
                        }
                    }
                }
            }

            // Three live status cells.
            Rectangle {
                id: metricsPanel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18 * root.uiScale
                anchors.rightMargin: 18 * root.uiScale
                anchors.top: topArea.bottom
                anchors.topMargin: 3 * root.uiScale
                height: parent.height * 0.18
                radius: 9 * root.uiScale
                color: "#77071121"
                border.width: 1
                border.color: "#54326C"

                Row {
                    anchors.fill: parent

                    Repeater {
                        model: [
                            {
                                icon:"◴",
                                label:"UPTIME",
                                value:root.monitorBackend && root.monitorBackend.uptimeValid
                                      ? String(root.monitorBackend.uptime || "--") : "--",
                                state:root.monitorBackend && root.monitorBackend.uptimeValid
                                      ? "SESSION STABLE" : "UNAVAILABLE",
                                stateColor:root.monitorBackend && root.monitorBackend.uptimeValid
                                           ? "#45EFA0" : "#8C9AB8"
                            },
                            {
                                icon:"ϟ",
                                label:"SYSTEM LOAD",
                                value:userCard.cpuLoad + "%",
                                state:userCard.loadState,
                                stateColor:userCard.loadStateColor
                            },
                            {
                                icon:"♨",
                                label:"TEMP",
                                value:root.monitorBackend && root.monitorBackend.temperatureValid
                                      ? Math.round(userCard.tempC) + "°C" : "--",
                                state:userCard.thermalState,
                                stateColor:userCard.tempStateColor
                            }
                        ]

                        delegate: Item {
                            required property int index
                            required property var modelData
                            width: parent.width / 3
                            height: parent.height

                            Row {
                                anchors.centerIn: parent
                                spacing: 7 * root.uiScale

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 28 * root.uiScale
                                    height: width
                                    radius: width / 2
                                    color: "#35071222"
                                    border.width: 1.2
                                    border.color: index === 0 ? "#28D8FF" :
                                                  index === 1 ? "#8D5BFF" : "#F542D0"

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(modelData.icon)
                                        color: index === 0 ? "#28D8FF" :
                                               index === 1 ? "#A56AFF" : "#F750D7"
                                        font.pixelSize: 14 * root.uiScale
                                        font.bold: true
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    Text {
                                        text: String(modelData.label)
                                        color: "#7F90BA"
                                        font.pixelSize: 7.2 * root.uiScale
                                        font.bold: true
                                        font.letterSpacing: 1.2
                                    }
                                    Text {
                                        text: String(modelData.value)
                                        color: "#F4F7FF"
                                        font.pixelSize: 12.5 * root.uiScale
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: String(modelData.state)
                                        color: String(modelData.stateColor)
                                        font.pixelSize: 6.8 * root.uiScale
                                        font.bold: true
                                        font.letterSpacing: .6
                                    }
                                }
                            }

                            Rectangle {
                                visible: index > 0
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: parent.height * .55
                                color: "#26345E"
                            }
                        }
                    }
                }
            }

            // Motto block.
            Rectangle {
                id: mottoPanel
                anchors.left: metricsPanel.left
                anchors.right: metricsPanel.right
                anchors.top: metricsPanel.bottom
                anchors.topMargin: 6 * root.uiScale
                height: parent.height * 0.14
                radius: 8 * root.uiScale
                color: "#71081120"
                border.width: 1
                border.color: "#5A2B72"

                Row {
                    anchors.centerIn: parent
                    spacing: 6 * root.uiScale

                    Text {
                        text: "“"
                        color: "#2CCBFF"
                        font.pixelSize: 22 * root.uiScale
                        font.bold: true
                    }
                    Text {
                        text: "SECURE  ·  INTELLIGENT  ·  "
                        color: "#DCE5FA"
                        font.pixelSize: 8.5 * root.uiScale
                        font.bold: true
                        font.letterSpacing: 2.0
                    }
                    Text {
                        text: "UNSTOPPABLE."
                        color: "#FF4058"
                        font.pixelSize: 8.5 * root.uiScale
                        font.bold: true
                        font.letterSpacing: 2.0
                    }
                    Text {
                        text: "”"
                        color: "#B15AFF"
                        font.pixelSize: 22 * root.uiScale
                        font.bold: true
                    }
                }
            }

            // NeutronOS footer branding.
            Rectangle {
                anchors.left: mottoPanel.left
                anchors.right: mottoPanel.right
                anchors.top: mottoPanel.bottom
                anchors.topMargin: 6 * root.uiScale
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 7 * root.uiScale
                radius: 8 * root.uiScale
                color: "#72070E1C"
                border.width: 1
                border.color: "#4B3569"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.uiScale

                    Rectangle {
                        width: 28 * root.uiScale
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: "#2AD8FF"

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * .48
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: "#FF4FC9"
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * .18
                            height: width
                            radius: width / 2
                            color: "#6C5CFF"
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            text: "N E U T R O N O S"
                            color: "#F2F5FF"
                            font.pixelSize: 9.5 * root.uiScale
                            font.bold: true
                            font.letterSpacing: 2.5
                        }
                        Text {
                            text: "BUILT FOR THE FUTURE"
                            color: "#68CFFF"
                            font.pixelSize: 6.5 * root.uiScale
                            font.bold: true
                            font.letterSpacing: 2.7
                        }
                    }
                }

                // Reference-style dot matrix ornament at the far right.
                Grid {
                    anchors.right: parent.right
                    anchors.rightMargin: 13 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    columns: 5
                    spacing: 4 * root.uiScale

                    Repeater {
                        // NEUTRONOS_FUTURE_DOTS_5X5_V1
                        // Exact 5x5 NeutronOS future mark:
                        // GBBGB / BRBRG / BRRRB / GRBRB / BBGBG
                        model: [
                            "g","b","b","g","b",
                            "b","r","b","r","g",
                            "b","r","r","r","b",
                            "g","r","b","r","b",
                            "b","b","g","b","g"
                        ]
                        Rectangle {
                            required property var modelData
                            width: 3 * root.uiScale
                            height: width
                            radius: width / 2
                            color: String(modelData) === "r" ? "#FF4058" :
                                   String(modelData) === "g" ? "#45EFA0" : "#3D83FF"
                            opacity: 0.82
                        }
                    }
                }
            }
        }
    }
    Component {
        id:securityComponent
        Item {
            readonly property var securityStats: root.securityBackend && root.securityBackend.stats ? root.securityBackend.stats : ({})
            readonly property int threatLevel: root.securityBackend ? Number(root.securityBackend.threatLevel || 5) : 0
            readonly property int incidentCount: root.unresolvedIncidents.length
            readonly property int integrityCount: Number(securityStats.integrityChanges !== undefined
                                                        ? securityStats.integrityChanges
                                                        : (root.securityBackend && root.securityBackend.integrityChanges
                                                           ? root.securityBackend.integrityChanges.length : 0))
            readonly property int activeThreatCount: Number(securityStats.activeThreats !== undefined
                                                           ? securityStats.activeThreats : incidentCount)
            // NEUTRONOS_SECURITY_WIDGET_AUTHORITATIVE_V2
            readonly property bool securityReady: root.securityBackend && root.securityBackend.daemonOnline === true &&
                                                 root.securityBackend.auditValid !== undefined &&
                                                 root.securityBackend.securityScore !== undefined
            readonly property int score: securityReady ? Math.max(0, Math.min(100, Number(root.securityBackend.securityScore))) : -1
            // NEUTRONOS_SECURITY_WEAK_PROTECTION_V1
            // The visible protection state follows the authoritative score bands.
            // 80-100 = protected, 55-79 = weak protection, 0-54 = unprotected.
            readonly property bool weakProtection: securityReady && score >= 55 && score < 80
            readonly property bool unprotected: securityReady && score < 55
            readonly property color stateColor: !securityReady ? "#7DF9FF" : score >= 80 ? "#43F0A0" : score >= 55 ? "#F7D85B" : "#FF405D"
            readonly property string protectionLabel: !securityReady ? "INITIALIZING" : score >= 80 ? "PROTECTED" : score >= 55 ? "WEAK PROTECTION" : "UNPROTECTED"
            // NEUTRONOS_SECURITY_SCORE_BAR_SOLID_V3
            readonly property color scoreColor: score < 0 ? "#7DF9FF" : score >= 80 ? "#43F0A0" : score >= 55 ? "#F7D85B" : "#FF405D"
            readonly property color scoreTracerColor: score < 0 ? "#C7FBFF" : score >= 80 ? "#C8FFE3" : score >= 55 ? "#FFF7A6" : "#FFC0CA"

            function enabledText(value) { return value === true ? "ON" : "OFF" }
            function enabledColor(value) { return value === true ? "#43F0A0" : "#FF6577" }
            function firewallState() {
                if (!securityReady) return "INITIALIZING"
                var state=String(securityStats.firewallProtectionState || "").toUpperCase()
                if (state==="SECURE" || state==="DEGRADED" || state==="CRITICAL") return state
                if (securityStats.firewallActive===true) return "SECURE"
                return root.securityBackend.daemonOnline===true ? "UNKNOWN" : "OFFLINE"
            }
            function firewallText() { return firewallState() }
            function firewallColor() {
                var state=firewallState()
                if (state==="INITIALIZING") return "#7DF9FF"
                if (state==="SECURE") return "#43F0A0"
                if (state==="DEGRADED" || state==="UNKNOWN") return "#F7D85B"
                return "#FF6577"
            }
            function malwareText() {
                if (securityStats.scanRunning === true) return "SCANNING"
                var findings=Number(securityStats.malwareFindings || 0)
                return findings > 0 ? findings + " FOUND" : "CLEAR"
            }
            function trustedPeripheralCount() {
                var devices=root.securityBackend&&root.securityBackend.peripherals?root.securityBackend.peripherals:[]
                var count=0
                for(var i=0;i<devices.length;++i){
                    var state=String((devices[i]||({})).trustState||"").toLowerCase()
                    if(state==="trusted"||state==="allow"||state==="approved")++count
                }
                return count
            }
            function unknownPeripheralCount() {
                if(securityStats.unknownPeripherals!==undefined)return Number(securityStats.unknownPeripherals||0)
                var devices=root.securityBackend&&root.securityBackend.peripherals?root.securityBackend.peripherals:[]
                var count=0
                for(var i=0;i<devices.length;++i){
                    var state=String((devices[i]||({})).trustState||"unknown").toLowerCase()
                    if(state==="unknown"||state==="untrusted")++count
                }
                return count
            }
            function listeningPortCount() {
                if(securityStats.listeningPorts!==undefined)return Number(securityStats.listeningPorts||0)
                return root.securityBackend&&root.securityBackend.listeningPorts?root.securityBackend.listeningPorts.length:0
            }
            function bannedSourceCount() {
                if(securityStats.bannedSources!==undefined)return Number(securityStats.bannedSources||0)
                return root.securityBackend&&root.securityBackend.bannedSources?root.securityBackend.bannedSources.length:0
            }
            function sshText() {
                var s=root.securityBackend&&root.securityBackend.sshStatus?root.securityBackend.sshStatus:({})
                var on=s.enabled===true||s.active===true||String(s.state||"").toLowerCase()==="active"
                var port=String(s.port||"")
                return on ? "ON"+(port.length?"  •  PORT "+port:"") : "OFF"
            }
            function tailscaleText() {
                var s=root.securityBackend&&root.securityBackend.tailscaleStatus?root.securityBackend.tailscaleStatus:({})
                var on=s.enabled===true||s.active===true||s.connected===true||String(s.state||"").toLowerCase()==="active"
                var ip=String(s.ip||s.address||s.ipv4||"")
                return on ? "CONNECTED"+(ip.length?"  •  "+ip:"") : "OFFLINE"
            }
            function overviewModel() {
                return [
                    {l:"Response Engine",v:enabledText(root.securityBackend && root.securityBackend.responseEngineEnabled),c:enabledColor(root.securityBackend && root.securityBackend.responseEngineEnabled),action:"response",toggle:true},
                    {l:"Enforcement",v:enabledText(root.securityBackend && root.securityBackend.enforcementEnabled),c:enabledColor(root.securityBackend && root.securityBackend.enforcementEnabled),action:"enforcement",toggle:true},
                    {l:"Learning Mode",v:enabledText(root.securityBackend && root.securityBackend.learningMode),c:root.securityBackend && root.securityBackend.learningMode ? "#F7D85B" : "#43F0A0",action:"learning",toggle:true},
                    {l:"Integrity",v:integrityCount>0 ? String(integrityCount)+" NOTICE"+(integrityCount===1?"":"S") : "VERIFIED",c:integrityCount>0 ? "#F7D85B" : "#43F0A0",action:"security-app",toggle:false},
                    {l:"Firewall",v:firewallText(),c:firewallColor(),action:"security-app",toggle:false},
                    {l:"Audit",v:!securityReady ? "INITIALIZING" : (root.securityBackend.auditValid ? "VERIFIED" : "ATTENTION"),c:!securityReady ? "#7DF9FF" : (root.securityBackend.auditValid ? "#43F0A0" : "#FF6577"),action:"security-app",toggle:false},
                    {l:"Malware",v:malwareText(),c:Number(securityStats.malwareFindings||0)>0 ? "#FF6577" : (securityStats.scanRunning===true ? "#5BDFFF" : "#43F0A0"),action:"security-app",toggle:false},
                    {l:"Quarantine",v:String(Number(securityStats.quarantinedItems||0)),c:Number(securityStats.quarantinedItems||0)>0 ? "#F7D85B" : "#43F0A0",action:"security-app",toggle:false}
                ]
            }
            function liveInfoModel() {
                return [
                    {l:"BLOCKED SOURCES",v:String(bannedSourceCount())+" ACTIVE",c:bannedSourceCount()>0?"#F7D85B":"#43F0A0"},
                    {l:"LISTENING PORTS",v:String(listeningPortCount())+" OPEN",c:"#DDE8F5"},
                    {l:"TRUSTED DEVICES",v:String(trustedPeripheralCount())+" TRUSTED  •  "+String(unknownPeripheralCount())+" UNKNOWN",c:unknownPeripheralCount()>0?"#F7D85B":"#43F0A0"},
                    {l:"SSH ACCESS",v:sshText(),c:sshText().indexOf("ON")===0?"#43F0A0":"#A7B8C8"},
                    {l:"TAILSCALE",v:tailscaleText(),c:tailscaleText().indexOf("CONNECTED")===0?"#43F0A0":"#A7B8C8"}
                ]
            }

            Column {
                anchors.fill:parent
                spacing:Math.max(4,6*root.uiScale)

                Column {
                    width:parent.width
                    spacing:1
                    SemanticStatusIcon {
                        anchors.horizontalCenter:parent.horizontalCenter
                        width:Math.min(54*root.uiScale, parent.width*.23)
                        height:width
                        kind:unprotected ? "unlocked" : "locked"
                        accent:stateColor
                    }
                    Text {
                        width:parent.width
                        text:protectionLabel
                        color:stateColor
                        font.pixelSize:Math.max(14,18*root.uiScale)
                        font.bold:true
                        horizontalAlignment:Text.AlignHCenter
                        elide:Text.ElideRight
                    }
                    Text {
                        width:parent.width
                        text:root.securityBackend ? String(root.securityBackend.threatLabel || "DEFCON --") : "SECURITY UNAVAILABLE"
                        color:"#F4F9FF"
                        font.pixelSize:11.5*root.uiScale
                        font.bold:true
                        horizontalAlignment:Text.AlignHCenter
                        elide:Text.ElideRight
                    }
                }

                Rectangle { width:parent.width; height:1; color:!securityReady ? "#294658" : (score >= 80 ? "#24533F" : score >= 55 ? "#6D5D24" : "#713040") }

                Column {
                    width:parent.width
                    spacing:2
                    Text {
                        width:parent.width
                        text:"SECURITY SCORE"
                        color:"#AFC3D6"
                        font.pixelSize:9.5*root.uiScale
                        font.bold:true
                        horizontalAlignment:Text.AlignHCenter
                        font.letterSpacing:1.0
                    }
                    Row {
                        anchors.horizontalCenter:parent.horizontalCenter
                        spacing:4
                        Text { id:securityScoreNumber; text:score < 0 ? "--" : String(score); color:scoreColor; font.pixelSize:25*root.uiScale; font.bold:true }
                        Text { anchors.baseline:securityScoreNumber.baseline; text:"/ 100"; color:"#D8E4F1"; font.pixelSize:10*root.uiScale; font.bold:true }
                    }
                    Item {
                        width:parent.width
                        height:12*root.uiScale

                        // NEUTRONOS_SECURITY_SCORE_TRACER_V1
                        // Two cheap rectangles plus one tiny tracer provide a stronger
                        // glow without blur/shader effects on the Pi 4.
                        Rectangle {
                            id: securityScoreGlowOuter
                            x: securityScoreFill.x - 5*root.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            width: securityScoreFill.width + 10*root.uiScale
                            height: 18*root.uiScale
                            radius: height/2
                            color: scoreColor
                            property real pulseOpacity: 0.10
                            opacity: securityReady && score >= 0 && securityScoreFill.width > 0 ? pulseOpacity : 0.0
                            SequentialAnimation on pulseOpacity {
                                running: securityScoreGlowOuter.visible && securityReady && score >= 0
                                loops: Animation.Infinite
                                NumberAnimation { from:0.08; to:0.26; duration:820; easing.type:Easing.InOutSine }
                                NumberAnimation { from:0.26; to:0.08; duration:820; easing.type:Easing.InOutSine }
                            }
                        }

                        Rectangle {
                            id: securityScoreGlowInner
                            x: securityScoreFill.x - 2*root.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            width: securityScoreFill.width + 4*root.uiScale
                            height: 13*root.uiScale
                            radius: height/2
                            color: scoreColor
                            opacity: securityReady && score >= 0 && securityScoreFill.width > 0 ? 0.22 : 0.0
                        }

                        Rectangle {
                            id: securityScoreTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 8*root.uiScale
                            radius: height/2
                            color:"#102235"
                            border.width:1
                            border.color:"#31516C"
                        }

                        Rectangle {
                            id: securityScoreFill
                            x: securityScoreTrack.x
                            anchors.verticalCenter: securityScoreTrack.verticalCenter
                            width: securityScoreTrack.width*Math.max(0,Math.min(1,(score < 0 ? 0 : score)/100))
                            height: securityScoreTrack.height
                            radius: height/2
                            color: scoreColor
                            Behavior on width { NumberAnimation { duration:240; easing.type:Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration:180 } }
                        }

                        Rectangle {
                            id: securityScoreTracer
                            property real phase: 0.0
                            readonly property real barW: Math.max(0, securityScoreFill.width)
                            readonly property real barH: Math.max(1, securityScoreFill.height)
                            readonly property real perimeter: Math.max(1, 2*(barW+barH))
                            readonly property real distance: phase*perimeter
                            width: 5.5*root.uiScale
                            height: width
                            radius: width/2
                            color: scoreTracerColor
                            border.width: 1
                            border.color: "#FFFFFF"
                            opacity: securityReady && score >= 0 && barW > 12*root.uiScale ? 0.98 : 0.0
                            x: {
                                var d=distance, w=barW, h=barH
                                if(d<w) return securityScoreFill.x+d-width/2
                                if(d<w+h) return securityScoreFill.x+w-width/2
                                if(d<2*w+h) return securityScoreFill.x+w-(d-w-h)-width/2
                                return securityScoreFill.x-width/2
                            }
                            y: {
                                var d=distance, w=barW, h=barH
                                var top=securityScoreFill.y
                                if(d<w) return top-height/2
                                if(d<w+h) return top+(d-w)-height/2
                                if(d<2*w+h) return top+h-height/2
                                return top+h-(d-2*w-h)-height/2
                            }
                            NumberAnimation on phase {
                                from:0.0; to:1.0; duration:1900; loops:Animation.Infinite
                                running: securityScoreTracer.visible && securityReady && score >= 0
                            }
                        }
                    }
                }

                Text {
                    width:parent.width
                    text:"SUSPICIOUS ACTIVITY"
                    color:"#DDE8F5"
                    font.pixelSize:9.5*root.uiScale
                    font.bold:true
                    font.letterSpacing:.8
                }
                Rectangle {
                    width:parent.width
                    height:38*root.uiScale
                    radius:8
                    color:root.securityPanelActive&&root.securityActionIndex===0 ? "#15354C" : (activeThreatCount>0 ? "#35101B" : "#0C2C25")
                    border.width:root.securityPanelActive&&root.securityActionIndex===0 ? 2 : 1
                    border.color:root.securityPanelActive&&root.securityActionIndex===0 ? "#42E4FF" : (activeThreatCount>0 ? "#FF405D" : "#35D88C")
                    Row {
                        anchors.fill:parent
                        anchors.margins:7*root.uiScale
                        spacing:7
                        Text {
                            anchors.verticalCenter:parent.verticalCenter
                            text:activeThreatCount>0 ? "!" : "✓"
                            color:activeThreatCount>0 ? "#FF6577" : "#55E8A1"
                            font.pixelSize:12*root.uiScale
                            font.bold:true
                        }
                        Text {
                            anchors.verticalCenter:parent.verticalCenter
                            width:parent.width-52*root.uiScale
                            text:activeThreatCount>0 && root.currentIncident && String(root.currentIncident.id||"").length
                                 ? String(root.currentIncident.displayTitle||root.friendlyIncidentTitle(root.currentIncident))+" - "+String(root.currentIncident.displayDetail||root.friendlyIncidentDetail(root.currentIncident))
                                 : (activeThreatCount>0 ? "Security condition requires review" : "No suspicious activity detected")
                            color:activeThreatCount>0 ? "#FFD5DB" : "#D8FFF0"
                            font.pixelSize:9.5*root.uiScale
                            font.bold:true
                            elide:Text.ElideRight
                        }
                        Text {
                            anchors.verticalCenter:parent.verticalCenter
                            text:activeThreatCount>0 ? "REVIEW" : "CLEAR"
                            color:activeThreatCount>0 ? "#FF6577" : "#55E8A1"
                            font.pixelSize:8.5*root.uiScale
                            font.bold:true
                        }
                    }
                }

                Text {
                    width:parent.width
                    text:"SECURITY OVERVIEW"
                    color:"#DDE8F5"
                    font.pixelSize:9.5*root.uiScale
                    font.bold:true
                    font.letterSpacing:.8
                }
                Grid {
                    id:securityOverviewGrid
                    width:parent.width
                    columns:2
                    columnSpacing:5*root.uiScale
                    rowSpacing:4*root.uiScale
                    Repeater {
                        model:overviewModel()
                        delegate:Rectangle {
                            required property int index
                            required property var modelData
                            readonly property int controlIndex:index+1
                            width:(securityOverviewGrid.width-securityOverviewGrid.columnSpacing)/2
                            height:31*root.uiScale
                            radius:6
                            color:root.securityPanelActive&&root.securityActionIndex===controlIndex ? "#15354C" : "#091A2A"
                            border.width:root.securityPanelActive&&root.securityActionIndex===controlIndex ? 2 : 1
                            border.color:root.securityPanelActive&&root.securityActionIndex===controlIndex ? "#42E4FF" : "#29465D"
                            Column {
                                anchors.fill:parent
                                anchors.margins:4
                                spacing:0
                                Row {
                                    width:parent.width
                                    Text { width:parent.width-18*root.uiScale; text:String(modelData.l); color:"#AABDD0"; font.pixelSize:7.8*root.uiScale; font.bold:true; elide:Text.ElideRight }
                                    Text { width:18*root.uiScale; text:modelData.toggle?"↕":"›"; color:root.securityPanelActive&&root.securityActionIndex===controlIndex?"#42E4FF":"#536E83"; font.pixelSize:8*root.uiScale; font.bold:true; horizontalAlignment:Text.AlignRight }
                                }
                                Text { width:parent.width; text:String(modelData.v); color:modelData.c; font.pixelSize:8.5*root.uiScale; font.bold:true; elide:Text.ElideRight }
                            }
                        }
                    }
                }

                // Strong spacer between interactive security controls and the
                // chronological activity feed below.
                Item {
                    width:parent.width
                    height:13*root.uiScale
                    Rectangle {
                        anchors.left:parent.left
                        anchors.right:parent.right
                        anchors.verticalCenter:parent.verticalCenter
                        height:1
                        color:"#3A5B73"
                    }
                }

                Text {
                    width:parent.width
                    text:"RECENT SECURITY ACTIONS"
                    color:"#DDE8F5"
                    font.pixelSize:9.5*root.uiScale
                    font.bold:true
                    font.letterSpacing:.8
                }
                Column {
                    id:securityRecentActions
                    width:parent.width
                    spacing:0
                    Repeater {
                        model:root.recentSecurityActions()
                        delegate:Item {
                            required property var modelData
                            width:securityRecentActions.width
                            height:30*root.uiScale
                            Row {
                                anchors.fill:parent
                                anchors.leftMargin:4*root.uiScale
                                anchors.rightMargin:4*root.uiScale
                                spacing:8*root.uiScale
                                Column {
                                    anchors.verticalCenter:parent.verticalCenter
                                    width:parent.width-(timeText.width+10*root.uiScale)
                                    spacing:0
                                    Text { width:parent.width; text:String(modelData.title); color:"#E3EDF7"; font.pixelSize:8.4*root.uiScale; font.bold:true; elide:Text.ElideRight }
                                    Text { width:parent.width; text:String(modelData.detail); color:"#839CB0"; font.pixelSize:7.3*root.uiScale; elide:Text.ElideRight }
                                }
                                Text {
                                    id:timeText
                                    anchors.verticalCenter:parent.verticalCenter
                                    width:74*root.uiScale
                                    text:String(modelData.time||"")
                                    color:"#61DDF6"
                                    font.pixelSize:7.2*root.uiScale
                                    font.bold:true
                                    horizontalAlignment:Text.AlignRight
                                    elide:Text.ElideRight
                                }
                            }
                            Rectangle { anchors.left:parent.left; anchors.right:parent.right; anchors.bottom:parent.bottom; height:1; color:"#1D394C" }
                        }
                    }
                }

                Item { width:1; height:Math.max(0,parent.height-y-securityActions.height-2) }

                Row {
                    id:securityActions
                    visible:root.widgetSize==="large"
                    width:parent.width
                    spacing:5*root.uiScale
                    Repeater {
                        model:["AUDIT","DEFCON ↓","SUMMARY"]
                        delegate:Rectangle {
                            required property int index
                            required property string modelData
                            readonly property int controlIndex:index+9
                            width:(securityActions.width-securityActions.spacing*2)/3
                            height:41*root.uiScale
                            radius:8
                            color:root.securityPanelActive&&root.securityActionIndex===controlIndex ? "#184466" : "#0A1B2B"
                            border.width:root.securityPanelActive&&root.securityActionIndex===controlIndex ? 2 : 1
                            border.color:index===2&&incidentCount>0 ? "#FF536C" : (root.securityPanelActive&&root.securityActionIndex===controlIndex ? "#42E4FF" : "#2A435B")
                            Text {
                                anchors.fill:parent
                                anchors.margins:3
                                text:modelData
                                color:index===2&&incidentCount>0 ? "#FF8797" : "white"
                                font.pixelSize:8.4*root.uiScale
                                font.bold:true
                                horizontalAlignment:Text.AlignHCenter
                                verticalAlignment:Text.AlignVCenter
                                elide:Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle{anchors.fill:parent;anchors.margins:-5;radius:root.radius+5;color:"transparent";border.width:root.moving?4:0;border.color:"#FF4FCE";visible:root.moving
        SequentialAnimation on opacity{running:root.moving;loops:Animation.Infinite;NumberAnimation{from:.35;to:1;duration:420}NumberAnimation{from:1;to:.35;duration:420}}
        Text{anchors.centerIn:parent;text:"MOVE MODE  •  D-PAD REPOSITION  •  X COMMIT  •  O CANCEL";color:"white";font.pixelSize:18*root.uiScale;font.bold:true;style:Text.Outline;styleColor:"#28001F"}
    }
}
