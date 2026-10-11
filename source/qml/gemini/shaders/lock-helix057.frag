#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
};
const float TAU=6.28318530718;
float beam(float distance,float depth) {
    float d2=distance*distance;
    return (3.2*exp(-d2/.0000011)+.95*exp(-d2/.00010)+.24*exp(-d2/.0009))*(.65+.35*depth);
}
void main() {
    vec2 p=qt_TexCoord0-.5;
    float radius=length(p);
    if(radius<.35||radius>.50){fragColor=vec4(0);return;}
    float angle=atan(p.y,p.x);
    // A closed six-turn double helix. Phase is periodic and advances clockwise.
    float flow=angle-phase*TAU;
    float twist=flow*6.;
    float wave=sin(twist),depth=cos(twist);
    float blueRadius=.425+.019*wave;
    float redRadius=.425-.019*wave;
    vec3 blue=vec3(.025,.55,1.0),red=vec3(1.0,.018,.10);
    vec3 energy=vec3(0);
    for(int i=0;i<3;i++) {
        float offset=(float(i)-1.)*.003;
        // Closely aligned filaments form each cohesive luminous strand bundle.
        float detail=.0007*sin(flow*72.+float(i)*2.094);
        float b=beam(radius-blueRadius-offset-detail,depth);
        float r=beam(radius-redRadius-offset+detail,-depth);
        float brightness=.78+.22*cos(flow*3.+float(i)*.55);
        energy+=(blue*b+red*r)*brightness;
        energy+=vec3(.55,.75,1.)*max(0.,b-1.7)*.28;
        energy+=vec3(1.,.5,.7)*max(0.,r-1.7)*.28;
    }
    // Gentle violet energy sits within the helix, with no additional particles.
    float violet=exp(-pow((radius-.425)/.025,2.))*.065*(.5+.5*cos(flow*12.));
    energy+=vec3(.55,.08,1.)*violet;
    vec3 light=1.-exp(-energy);
    float alpha=clamp(max(max(energy.r,energy.g),energy.b),0.,1.);
    fragColor=vec4(light*alpha,alpha)*qt_Opacity;
}
