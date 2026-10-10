VARYING vec2 fragmentUv;
VARYING float edgeCoordinate;
float randomValue(vec2 seed){return fract(sin(dot(seed,vec2(127.1,311.7)))*43758.5453);}
void MAIN(){
    fragmentUv=UV0;edgeCoordinate=COLOR.x;
    float random=randomValue(UV1);
    float delay=0.11+0.32*random;
    float t=max(0.0,elapsed-delay);
    vec3 center=vec3((UV1.x-0.5)*1672.0,(0.5-UV1.y)*941.0,0.0);
    vec3 local=VERTEX-center;
    float a=t*(randomValue(UV1+1.0)-0.5)*7.0;
    float b=t*(randomValue(UV1+2.0)-0.5)*5.0;
    local=vec3(local.x,cos(b)*local.y-sin(b)*local.z,sin(b)*local.y+cos(b)*local.z);
    local=vec3(cos(a)*local.x-sin(a)*local.y,sin(a)*local.x+cos(a)*local.y,local.z);
    vec3 velocity=vec3((randomValue(UV1+3.0)-0.5)*250.0,120.0*random,200.0*(randomValue(UV1+4.0)-0.5));
    VERTEX=center+local+velocity*t+vec3(0.0,-800.0*t*t,0.0);
    VERTEX.z+=0.02*random;
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
