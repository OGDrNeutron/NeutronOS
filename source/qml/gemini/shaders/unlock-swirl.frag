VARYING vec2 fragmentUv;
VARYING float edgeCoordinate;
VARYING float fragmentOpacity;
void MAIN(){
    vec4 surface=texture(surfaceMap,fragmentUv);
    float edge=1.0-smoothstep(0.0,fwidth(edgeCoordinate)*1.6,edgeCoordinate);
    float crack=smoothstep(.04,.3,elapsed)*edge;
    vec3 green=vec3(.01,1.1,.42);
    FRAGCOLOR=vec4(mix(surface.rgb,green,crack*.85),surface.a*fragmentOpacity);
}
