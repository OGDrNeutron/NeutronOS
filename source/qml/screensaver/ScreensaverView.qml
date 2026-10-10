import QtQuick 2.15

Item {
    id: root
    property var manager: null
    property bool active: false
    property var assetSnapshot: []
    property int pictureIndex: 0
    property int nextPictureIndex: 0
    property bool frontA: true
    property real phase: 0
    property string activeAnimation: manager ? String(manager.animationId || "starfield") : "starfield"
    property int randomIndex: 0
    readonly property bool animationMode: manager && String(manager.contentMode || "pictures") === "animations"
    readonly property real speedFactor: manager ? Math.max(0.4, Math.min(1.8, Number(manager.animationSpeed || 100) / 100)) : 1
    readonly property real intensityFactor: manager ? Math.max(0.3, Math.min(1.6, Number(manager.animationIntensity || 100) / 100)) : 1
    readonly property var animationIds: ["pipes", "dvd", "atom", "starfield", "plasma", "tunnel"]

    signal ready()
    signal wakeRequested()

    anchors.fill: parent
    visible: active
    enabled: active
    focus: active
    activeFocusOnTab: true
    clip: true

    Keys.onPressed: function(event) {
        if (!root.active || event.isAutoRepeat) return
        event.accepted = true
        root.wakeRequested()
    }
    MouseArea { anchors.fill: parent; enabled: root.active; onPressed: root.wakeRequested() }

    function refreshAssets() {
        var list = []
        try {
            var raw = manager ? manager.assets : []
            for (var i = 0; raw && i < raw.length; ++i) list.push(raw[i])
        } catch (error) {}
        assetSnapshot = list
    }
    function assetUrl(index) {
        if (index < 0 || index >= assetSnapshot.length) return ""
        try { return String(assetSnapshot[index].url || assetSnapshot[index].path || "") } catch (e) { return "" }
    }
    function startScene() {
        refreshAssets()
        pictureIndex = 0
        nextPictureIndex = assetSnapshot.length > 1 ? 1 : 0
        frontA = true
        imageA.source = assetUrl(pictureIndex)
        imageB.source = assetUrl(nextPictureIndex)
        imageA.opacity = 1
        imageB.opacity = 0
        phase = 0
        activeAnimation = manager ? String(manager.animationId || "starfield") : "starfield"
        frameClock.restart()
        pictureTimer.restart()
        randomTimer.restart()
        canvas.requestPaint()
        ready()
        forceActiveFocus()
    }
    function nextPicture() {
        if (!active || animationMode || assetSnapshot.length <= 1) return
        nextPictureIndex = (pictureIndex + 1) % assetSnapshot.length
        var incoming = frontA ? imageB : imageA
        incoming.source = assetUrl(nextPictureIndex)
        crossfade.restart()
    }
    function finishPicture() {
        frontA = !frontA
        pictureIndex = nextPictureIndex
        pictureTimer.restart()
    }
    function rotateAnimation() {
        if (!active || !animationMode || !manager || manager.randomRotation !== true) return
        randomIndex = (randomIndex + 1) % animationIds.length
        activeAnimation = animationIds[randomIndex]
        phase = 0
        canvas.requestPaint()
        randomTimer.restart()
    }

    onActiveChanged: {
        if (active) Qt.callLater(startScene)
        else {
            frameClock.stop(); pictureTimer.stop(); randomTimer.stop(); crossfade.stop()
            imageA.source = ""; imageB.source = ""; assetSnapshot = []
        }
    }
    onManagerChanged: if (active) Qt.callLater(startScene)

    Connections {
        target: root.manager
        enabled: target !== null
        ignoreUnknownSignals: true
        function onAssetsChanged() { if (root.active) root.startScene() }
        function onSettingsChanged() { if (root.active) root.startScene() }
    }

    Rectangle { anchors.fill: parent; color: "#02050B" }

    Item {
        anchors.fill: parent
        visible: !root.animationMode

        Image {
            id: imageA
            anchors.centerIn: parent
            width: parent.width * 1.13; height: parent.height * 1.13
            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
            scale: 1.03 + 0.05 * Math.sin(root.phase * 0.22)
            x: (parent.width - width) / 2 + Math.sin(root.phase * 0.15) * parent.width * 0.025
            y: (parent.height - height) / 2 + Math.cos(root.phase * 0.12) * parent.height * 0.025
        }
        Image {
            id: imageB
            anchors.centerIn: parent
            width: parent.width * 1.13; height: parent.height * 1.13
            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
            scale: 1.04 + 0.05 * Math.cos(root.phase * 0.20)
            x: (parent.width - width) / 2 + Math.cos(root.phase * 0.14) * parent.width * 0.025
            y: (parent.height - height) / 2 + Math.sin(root.phase * 0.13) * parent.height * 0.025
        }
        Rectangle { anchors.fill: parent; color: "#24000000" }
        Column {
            visible: root.assetSnapshot.length === 0
            anchors.centerIn: parent; spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NeutronOS"; color: "white"; font.pixelSize: 44; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add images to themes/Default/screensavers"; color: "#8AA6C8"; font.pixelSize: 17 }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        visible: root.animationMode
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        function color(alpha, offset) {
            var palette = [[125,249,255],[77,166,255],[192,132,252],[255,78,168],[34,255,136],[255,211,77]]
            var c = palette[Math.abs(offset) % palette.length]
            return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + alpha + ")"
        }
        function starNoise(i, axis) {
            var value = Math.sin(i * 91.73 + axis * 37.11) * 43758.5453
            return value - Math.floor(value)
        }
        function drawStarfield(ctx, w, h) {
            var count = Math.round(90 * root.intensityFactor)
            var cx = w / 2, cy = h / 2
            for (var i = 0; i < count; ++i) {
                var depth = (root.phase * 0.09 + starNoise(i, 1)) % 1
                var angle = starNoise(i, 2) * Math.PI * 2
                var radius = Math.pow(depth, 1.8) * Math.max(w, h) * 0.72
                var x = cx + Math.cos(angle) * radius
                var y = cy + Math.sin(angle) * radius * 0.62
                var size = 0.8 + depth * 4.2
                ctx.fillStyle = color(0.25 + depth * 0.75, i)
                ctx.beginPath(); ctx.arc(x, y, size, 0, Math.PI * 2); ctx.fill()
            }
        }
        function drawAtom(ctx, w, h) {
            var cx = w / 2, cy = h / 2
            var count = Math.round(14 * root.intensityFactor)
            ctx.lineWidth = 2
            for (var ring = 0; ring < 5; ++ring) {
                ctx.strokeStyle = color(0.38, ring)
                ctx.save(); ctx.translate(cx, cy); ctx.rotate(root.phase * 0.12 + ring * Math.PI / 5)
                ctx.scale(1, 0.38 + ring * 0.05)
                ctx.beginPath(); ctx.arc(0, 0, Math.min(w,h) * (0.18 + ring * 0.028), 0, Math.PI * 2); ctx.stroke(); ctx.restore()
            }
            for (var i = 0; i < count; ++i) {
                var orbit = i % 5
                var a = root.phase * (0.7 + orbit * 0.08) + i * 1.73
                var r = Math.min(w,h) * (0.18 + orbit * 0.028)
                var x = cx + Math.cos(a) * r
                var y = cy + Math.sin(a) * r * (0.38 + orbit * 0.05)
                ctx.fillStyle = color(0.9, i)
                ctx.beginPath(); ctx.arc(x, y, 3 + (i % 3), 0, Math.PI * 2); ctx.fill()
            }
            var glow = ctx.createRadialGradient(cx,cy,0,cx,cy,70)
            glow.addColorStop(0,"rgba(255,78,168,0.95)"); glow.addColorStop(0.4,"rgba(168,85,247,0.5)"); glow.addColorStop(1,"rgba(125,249,255,0)")
            ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(cx,cy,70,0,Math.PI*2); ctx.fill()
        }
        function drawDvd(ctx, w, h) {
            var boxW = 310, boxH = 130
            var x = (Math.sin(root.phase * 0.43) * 0.5 + 0.5) * Math.max(1, w - boxW)
            var y = (Math.sin(root.phase * 0.31 + 1.4) * 0.5 + 0.5) * Math.max(1, h - boxH)
            ctx.fillStyle = color(0.18, Math.floor(root.phase / 3)); ctx.strokeStyle = color(0.95, Math.floor(root.phase / 3)); ctx.lineWidth = 4
            ctx.beginPath(); ctx.rect(x,y,boxW,boxH); ctx.fill(); ctx.stroke()
            ctx.fillStyle = "white"; ctx.font = "bold 42px sans-serif"; ctx.textAlign = "center"; ctx.fillText("NeutronOS", x + boxW/2, y + 63)
            ctx.font = "bold 17px sans-serif"; ctx.fillStyle = color(1, 2); ctx.fillText("GEMINI", x + boxW/2, y + 96)
        }
        function drawPipes(ctx, w, h) {
            var count = Math.round(16 * root.intensityFactor)
            ctx.lineCap = "round"; ctx.lineJoin = "round"
            for (var i=0;i<count;++i) {
                var x0 = starNoise(i,1)*w, y0=starNoise(i,2)*h
                var step = 80 + starNoise(i,3)*120
                var t = root.phase * (0.18 + starNoise(i,4)*0.18)
                ctx.strokeStyle=color(0.28+starNoise(i,5)*0.45,i); ctx.lineWidth=5+starNoise(i,6)*10
                ctx.beginPath(); ctx.moveTo(x0,y0)
                for(var k=1;k<7;++k){
                    var horizontal=(k+i)%2===0
                    var direction=Math.sin(t+i*2.1+k)>0?1:-1
                    if(horizontal)x0=(x0+direction*step+w)%w; else y0=(y0+direction*step+h)%h
                    ctx.lineTo(x0,y0)
                }
                ctx.stroke()
            }
        }
        function drawPlasma(ctx,w,h){
            var bands=Math.round(26*root.intensityFactor)
            for(var i=0;i<bands;++i){
                var y=i*h/bands
                var v=(Math.sin(i*0.72+root.phase*0.8)+Math.sin(i*0.31-root.phase*0.55)+2)/4
                var grad=ctx.createLinearGradient(0,y,w,y+h/bands+2)
                grad.addColorStop(0,color(0.25+0.55*v,i)); grad.addColorStop(0.5,color(0.3+0.6*(1-v),i+2)); grad.addColorStop(1,color(0.2+0.5*v,i+4))
                ctx.fillStyle=grad; ctx.fillRect(0,y,w,h/bands+2)
            }
        }
        function drawTunnel(ctx,w,h){
            var cx=w/2,cy=h/2; var rings=Math.round(26*root.intensityFactor)
            ctx.lineWidth=2.5
            for(var i=0;i<rings;++i){
                var p=(i/rings+root.phase*0.08)%1
                var r=Math.pow(p,2.1)*Math.max(w,h)*0.72
                ctx.strokeStyle=color(0.15+p*0.75,i); ctx.beginPath(); ctx.arc(cx+Math.sin(root.phase*0.3)*w*0.06,cy+Math.cos(root.phase*0.24)*h*0.06,r,0,Math.PI*2); ctx.stroke()
            }
        }
        onPaint: {
            var ctx=getContext("2d"), w=width, h=height
            ctx.clearRect(0,0,w,h); ctx.fillStyle="#02050B"; ctx.fillRect(0,0,w,h)
            if(root.activeAnimation==="pipes")drawPipes(ctx,w,h)
            else if(root.activeAnimation==="dvd")drawDvd(ctx,w,h)
            else if(root.activeAnimation==="atom")drawAtom(ctx,w,h)
            else if(root.activeAnimation==="plasma")drawPlasma(ctx,w,h)
            else if(root.activeAnimation==="tunnel")drawTunnel(ctx,w,h)
            else drawStarfield(ctx,w,h)
        }
    }

    Timer {
        id: frameClock
        interval: root.animationMode ? Math.max(20, Math.round(42 / root.speedFactor)) : 66
        repeat: true
        running: root.active
        onTriggered: {
            root.phase += 0.055 * root.speedFactor
            if (root.animationMode) canvas.requestPaint()
        }
    }
    Timer { id: pictureTimer; interval: 15000; repeat: false; onTriggered: root.nextPicture() }
    Timer { id: randomTimer; interval: 20000; repeat: false; onTriggered: root.rotateAnimation() }
    ParallelAnimation {
        id: crossfade
        NumberAnimation { target: root.frontA ? imageA : imageB; property: "opacity"; from: 1; to: 0; duration: 1200 }
        NumberAnimation { target: root.frontA ? imageB : imageA; property: "opacity"; from: 0; to: 1; duration: 1200 }
        onFinished: root.finishPicture()
    }

    Text {
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 24
        text: root.animationMode ? root.activeAnimation.toUpperCase() : "PICTURE SCREENSAVER"
        color: "#668AA6C8"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 2
    }
}
