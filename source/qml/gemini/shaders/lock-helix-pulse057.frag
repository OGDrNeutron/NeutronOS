#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float flowAngle; float strandPhase; vec2 extent; };
const float TAU=6.28318530718;
void main() {
    vec2 p=(qt_TexCoord0-.5)*extent+vec2(260./660.,0.);
    float angle=atan(p.y,p.x),radius=length(p),flow=flowAngle+angle;
    float blueRadius=(260.+28.*cos((flow-strandPhase)*10.))/660.;
    float redRadius=(260.-28.*cos((flow+strandPhase)*10.))/660.;
    float db=radius-blueRadius,dr=radius-redRadius;
    float arc=exp(-angle*angle/.0064);
    float beams=exp(-db*db/.000018)+exp(-dr*dr/.000018);
    float halo=exp(-db*db/.00024)+exp(-dr*dr/.00024);
    // Rungs stay at fixed orbital angles while their endpoints follow the backbones.
    float rungAngle=abs(fract(flow*160./TAU+.5)-.5)*TAU/160.;
    float low=min(blueRadius,redRadius), high=max(blueRadius,redRadius);
    float inside=smoothstep(low-.005,low,radius)*(1.-smoothstep(high,high+.005,radius));
    float rungs=exp(-rungAngle*rungAngle/.000012)*inside;
    float intensity=(beams*3.+halo*.55+rungs*1.8)*arc;
    vec3 color=1.-exp(-vec3(.78,.20,1.)*intensity);
    float alpha=clamp(intensity,0.,1.);
    fragColor=vec4(color*alpha,alpha)*qt_Opacity;
}
