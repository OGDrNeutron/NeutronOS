import QtQuick
Canvas {
    onPaint: {
        var c=getContext("2d");c.reset();var s=Math.min(width/120,height/90);c.scale(s,s)
        c.lineWidth=3;c.strokeStyle="#35caff";c.shadowColor="#167fff";c.shadowBlur=10
        c.beginPath();c.moveTo(31,16);c.bezierCurveTo(14,14,6,55,8,70);c.bezierCurveTo(15,91,34,70,42,62);c.lineTo(79,62);c.bezierCurveTo(88,72,105,91,113,70);c.bezierCurveTo(116,56,104,15,89,16);c.closePath();c.stroke()
        c.strokeStyle="#ff386c";c.shadowColor="#ff1552";c.beginPath();c.moveTo(90,16);c.bezierCurveTo(104,15,116,56,113,70);c.bezierCurveTo(105,91,88,72,79,62);c.stroke()
        c.shadowBlur=0;c.strokeStyle="#b8eaff";c.lineWidth=2;c.beginPath();c.moveTo(32,31);c.lineTo(32,49);c.moveTo(23,40);c.lineTo(41,40);c.stroke()
        c.strokeStyle="#41cfff";[[88,31],[98,41],[88,50],[78,41]].forEach(function(p){c.beginPath();c.arc(p[0],p[1],2.5,0,Math.PI*2);c.stroke()})
        c.beginPath();c.moveTo(53,40);c.lineTo(65,40);c.stroke()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
