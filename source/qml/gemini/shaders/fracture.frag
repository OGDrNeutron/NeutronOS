VARYING vec2 fragmentUv;
VARYING float edgeCoordinate;
void MAIN(){
    vec4 surface=texture(surfaceMap,fragmentUv);
    float crack=smoothstep(0.01,0.13,elapsed)*(1.0-smoothstep(0.0,fwidth(edgeCoordinate)*1.4,edgeCoordinate));
    FRAGCOLOR=vec4(mix(surface.rgb,vec3(0.02,0.1,0.2),crack*0.85),surface.a);
}
