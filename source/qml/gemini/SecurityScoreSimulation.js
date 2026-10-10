.pragma library
// Mirrors SecurityCore.calculate_score; parity is regression-tested against
// that actual daemon method. Profiles do not award invented bonus points.
function preview(profile, events, failedServices, firewallState) {
    var penalty=0,cutoff=Date.now()-24*60*60*1000
    ;(events||[]).forEach(function(event){
        var stamp=Date.parse(String(event.timestamp||""))
        if((isFinite(stamp)&&stamp<cutoff)||event.acknowledged)return
        var weight=({1:0,2:2,3:5,4:12,5:25})[Number(event.severity||1)]
        penalty+=weight===undefined?1:weight
    })
    penalty+=Math.min(10,Math.max(0,Number(failedServices)||0)*2)
    var firewall=String(firewallState||"CRITICAL").toUpperCase()
    penalty+=firewall==="CRITICAL"?50:firewall==="DEGRADED"?15:0
    return {score:Math.max(0,Math.min(100,100-penalty)),profile:profile,source:"Simulated · SecurityCore scoring rules",assumption:"Healthy firewall; no events or failed services. Profiles do not add score bonuses."}
}
