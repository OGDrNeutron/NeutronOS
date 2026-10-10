import QtQuick 2.15

/* NEUTRONOS_CONTROL_CENTER_VECTOR_ICONS_V1
   Small semantic icons for control-center rails and action rows. */
Item {
    id: root
    property string kind: "profile"
    property color accent: "#7DF9FF"

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        function circle(ctx, x, y, r, fill) {
            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2)
            if (fill) ctx.fill(); else ctx.stroke()
        }
        function rr(ctx, x, y, w, h, r, fill) {
            ctx.beginPath(); ctx.roundedRect(x, y, w, h, r, r)
            if (fill) ctx.fill(); else ctx.stroke()
        }
        function line(ctx, x1, y1, x2, y2) {
            ctx.beginPath(); ctx.moveTo(x1,y1); ctx.lineTo(x2,y2); ctx.stroke()
        }

        function drawClock(ctx) {
            circle(ctx, width*.5, height*.5, width*.34, false)
            line(ctx,width*.5,height*.5,width*.5,height*.29)
            line(ctx,width*.5,height*.5,width*.67,height*.59)
            circle(ctx,width*.5,height*.5,width*.035,true)
        }
        function drawCalendar(ctx) {
            rr(ctx,width*.17,height*.2,width*.66,height*.61,width*.08,false)
            line(ctx,width*.17,height*.36,width*.83,height*.36)
            line(ctx,width*.32,height*.14,width*.32,height*.28)
            line(ctx,width*.68,height*.14,width*.68,height*.28)
            circle(ctx,width*.36,height*.51,width*.035,true)
            circle(ctx,width*.52,height*.51,width*.035,true)
            circle(ctx,width*.68,height*.51,width*.035,true)
            circle(ctx,width*.36,height*.66,width*.035,true)
            circle(ctx,width*.52,height*.66,width*.035,true)
        }
        function drawGlobe(ctx) {
            circle(ctx,width*.5,height*.5,width*.34,false)
            circle(ctx,width*.5,height*.5,width*.16,false)
            line(ctx,width*.18,height*.5,width*.82,height*.5)
            ctx.beginPath();ctx.moveTo(width*.5,height*.16);ctx.bezierCurveTo(width*.34,height*.32,width*.34,height*.68,width*.5,height*.84);ctx.stroke()
            ctx.beginPath();ctx.moveTo(width*.5,height*.16);ctx.bezierCurveTo(width*.66,height*.32,width*.66,height*.68,width*.5,height*.84);ctx.stroke()
        }
        function drawEye(ctx) {
            ctx.beginPath();ctx.moveTo(width*.12,height*.5);ctx.quadraticCurveTo(width*.5,height*.18,width*.88,height*.5);ctx.quadraticCurveTo(width*.5,height*.82,width*.12,height*.5);ctx.stroke()
            circle(ctx,width*.5,height*.5,width*.11,true)
        }
        function drawUser(ctx) {
            circle(ctx,width*.5,height*.32,width*.16,true)
            ctx.beginPath();ctx.moveTo(width*.2,height*.82);ctx.quadraticCurveTo(width*.24,height*.55,width*.5,height*.55);ctx.quadraticCurveTo(width*.76,height*.55,width*.8,height*.82);ctx.closePath();ctx.fill()
        }
        function drawAvatar(ctx) {
            rr(ctx,width*.16,height*.16,width*.68,height*.68,width*.12,false)
            circle(ctx,width*.5,height*.39,width*.12,true)
            ctx.beginPath();ctx.moveTo(width*.29,height*.72);ctx.quadraticCurveTo(width*.33,height*.53,width*.5,height*.53);ctx.quadraticCurveTo(width*.67,height*.53,width*.71,height*.72);ctx.stroke()
        }
        function drawPalette(ctx) {
            ctx.beginPath();ctx.arc(width*.48,height*.52,width*.33,Math.PI*.18,Math.PI*1.82);ctx.bezierCurveTo(width*.83,height*.78,width*.61,height*.86,width*.52,height*.72);ctx.bezierCurveTo(width*.45,height*.62,width*.29,height*.86,width*.18,height*.63);ctx.closePath();ctx.stroke()
            circle(ctx,width*.34,height*.38,width*.045,true);circle(ctx,width*.5,height*.31,width*.045,true);circle(ctx,width*.65,height*.4,width*.045,true)
        }
        function drawSpark(ctx) {
            var cx=width*.5, cy=height*.5, r1=width*.34, r2=width*.11
            ctx.beginPath();
            for(var i=0;i<8;i++){var a=-Math.PI/2+i*Math.PI/4;var r=i%2===0?r1:r2;var x=cx+Math.cos(a)*r,y=cy+Math.sin(a)*r;if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)}
            ctx.closePath();ctx.fill()
        }
        function drawConsole(ctx) {
            rr(ctx,width*.12,height*.22,width*.76,height*.48,width*.06,false)
            line(ctx,width*.39,height*.78,width*.61,height*.78)
            line(ctx,width*.5,height*.7,width*.5,height*.78)
            circle(ctx,width*.26,height*.46,width*.035,true);circle(ctx,width*.74,height*.46,width*.035,true)
        }
        function drawPower(ctx) {
            ctx.beginPath();ctx.arc(width*.5,height*.52,width*.28,-Math.PI*.28,Math.PI*1.28);ctx.stroke()
            line(ctx,width*.5,height*.13,width*.5,height*.49)
        }
        function drawRestart(ctx) {
            ctx.beginPath();ctx.arc(width*.5,height*.52,width*.28,Math.PI*.15,Math.PI*1.8);ctx.stroke()
            ctx.beginPath();ctx.moveTo(width*.27,height*.22);ctx.lineTo(width*.48,height*.2);ctx.lineTo(width*.37,height*.38);ctx.closePath();ctx.fill()
        }
        function drawLogout(ctx) {
            rr(ctx,width*.16,height*.2,width*.38,height*.6,width*.05,false)
            line(ctx,width*.43,height*.5,width*.84,height*.5)
            line(ctx,width*.69,height*.36,width*.84,height*.5)
            line(ctx,width*.69,height*.64,width*.84,height*.5)
        }
        function drawLock(ctx) {
            rr(ctx,width*.2,height*.43,width*.6,height*.4,width*.07,true)
            ctx.beginPath();ctx.arc(width*.5,height*.43,width*.21,Math.PI,0);ctx.stroke()
            ctx.fillStyle="#071426";circle(ctx,width*.5,height*.62,width*.045,true)
        }

        onPaint: {
            var ctx=getContext("2d")
            ctx.clearRect(0,0,width,height)
            ctx.strokeStyle=root.accent;ctx.fillStyle=root.accent
            ctx.lineWidth=Math.max(2,width*.065);ctx.lineCap="round";ctx.lineJoin="round"
            var k=String(root.kind||"").toLowerCase()
            if(k==="time"||k==="clock")drawClock(ctx)
            else if(k==="date"||k==="calendar")drawCalendar(ctx)
            else if(k==="region"||k==="globe")drawGlobe(ctx)
            else if(k==="preview"||k==="eye")drawEye(ctx)
            else if(k==="profile"||k==="user")drawUser(ctx)
            else if(k==="avatar"||k==="icon")drawAvatar(ctx)
            else if(k==="color"||k==="palette")drawPalette(ctx)
            else if(k==="appearance"||k==="spark")drawSpark(ctx)
            else if(k==="console"||k==="display")drawConsole(ctx)
            else if(k==="restart"||k==="reboot")drawRestart(ctx)
            else if(k==="logout")drawLogout(ctx)
            else if(k==="lock")drawLock(ctx)
            else drawPower(ctx)
        }

        Connections { target:root; function onKindChanged(){canvas.requestPaint()} function onAccentChanged(){canvas.requestPaint()} }
        onWidthChanged:requestPaint(); onHeightChanged:requestPaint(); Component.onCompleted:requestPaint()
    }
}
