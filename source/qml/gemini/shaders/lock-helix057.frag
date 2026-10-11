#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float phase; };
const float TAU=6.28318530718;
void main() {
    vec2 p=qt_TexCoord0-.5;
    float radius=length(p);
    if(radius<.33||radius>.49){fragColor=vec4(0);return;}
    float angle=atan(p.y,p.x), flow=angle-phase*TAU, twist=flow*10.;
    float blueTwist=(angle-phase*TAU)*10., redTwist=(angle+phase*TAU)*10.;
    float db=radius-(260.+28.*cos(blueTwist))/660.,dr=radius-(260.-28.*cos(redTwist))/660.;
    float blue=exp(-db*db/.00015)*.85+exp(-db*db/.0006)*.26;
    float red=exp(-dr*dr/.00015)*.85+exp(-dr*dr/.0006)*.26;
    vec3 energy=vec3(.015,.38,1.)*blue*(.8-.2*sin(blueTwist))+vec3(1.,.008,.06)*red*(.8+.2*sin(redTwist));
    // A continuous low-energy electrical thread stays inside the molecular ladder.
    float violetRadius=(260.+19.*sin(twist+sin(flow*30.)*.2))/660.;
    float violet=exp(-pow((radius-violetRadius)/.0018,2.))*(.11+.07*cos(flow*40.));
    energy+=vec3(.45,.035,.8)*violet;
    vec3 light=1.-exp(-energy);
    float alpha=clamp(max(max(energy.r,energy.g),energy.b),0.,1.);
    fragColor=vec4(light*alpha,alpha)*qt_Opacity;
}
