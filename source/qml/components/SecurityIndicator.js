.pragma library
// The desktop header's existing status vocabulary, thresholds, colors and icons.
function score(backend) {
    if(!backend)return -1
    var online=backend.indicatorOnline!==undefined?backend.indicatorOnline:backend.daemonOnline
    var value=backend.indicatorScore!==undefined?backend.indicatorScore:backend.securityScore
    if(online!==true||value===undefined)return -1
    var n=Number(value)
    return isNaN(n)?-1:Math.max(0,Math.min(100,Math.round(n)))
}
function label(backend){var n=score(backend);return n<0?"Unavailable":n>=80?"Secure":n>=55?"Weak Protection":"Unsecure"}
function strength(backend){var n=score(backend);return n<0?"Unavailable":n>=80?"Secure":n>=55?"Weak":"Unsecure"}
function color(backend){var n=score(backend);return n<0?"#FF3157":n>=80?"#20F58B":n>=55?"#F7D85B":"#FF3157"}
function icon(backend){return score(backend)>=55?"locked":"unlocked"}
