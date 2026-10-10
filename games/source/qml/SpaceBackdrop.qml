import QtQuick
Rectangle {
    color: "#02050b"
    Canvas {
        id: sky
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var c=getContext("2d");c.reset();var w=width,h=height
            var gradient=c.createLinearGradient(0,0,w,h);gradient.addColorStop(0,"#01040a");gradient.addColorStop(0.65,"#020a18");gradient.addColorStop(1,"#03050a");c.fillStyle=gradient;c.fillRect(0,0,w,h)
            var planet=c.createRadialGradient(w*0.88,h*0.10,0,w*0.88,h*0.10,w*0.22);planet.addColorStop(0,"#031023");planet.addColorStop(0.7,"#082443");planet.addColorStop(0.78,"#25a5ef");planet.addColorStop(0.8,"#023058");planet.addColorStop(1,"#020814");c.fillStyle=planet;c.beginPath();c.arc(w*0.88,h*0.10,w*0.22,0,Math.PI*2);c.fill()
            for(var i=0;i<55;i++){var x=((i*97)%997)/997*w,y=((i*173)%997)/997*h*0.4;c.fillStyle=i%3===0?"#227dab":"#203b63";c.fillRect(x,y,1.5,1.5)}
            for(var j=0;j<14;j++){var red=j%3===0;c.strokeStyle=red?"#cf164c":"#0676c7";c.lineWidth=j%4===0?3:1;c.globalAlpha=0.35+j%4*0.12;c.beginPath();c.moveTo(-w*0.08,h*(0.69+j*0.024));c.lineTo(w*0.38,h*0.99);c.lineTo(w*(0.52+j*0.034),h*(0.84+j*0.009));c.stroke();c.beginPath();c.moveTo(w*(0.36+j*0.05),0);c.lineTo(w*(0.42+j*0.04),h*0.07);c.stroke()}
            c.globalAlpha=1
        }
    }
}
