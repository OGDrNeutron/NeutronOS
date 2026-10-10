VARYING vec3 surfaceNormal;
VARYING vec3 viewNormal;
VARYING vec2 surfaceUv;
void MAIN() {
    float edge=pow(1.0-abs(normalize(viewNormal).z),3.5);
    float longitude=(surfaceUv.x-0.5)*6.28318530718;
    float latitude=(0.5-surfaceUv.y)*3.14159265359;
    vec3 geographicNormal=vec3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude));
    float solar=max(dot(geographicNormal,normalize(solarDirection)),0.0);
    float strength=mix(1.0,0.22+0.78*smoothstep(-0.08,0.28,solar),solarLighting);
    FRAGCOLOR=vec4(0.08,0.85,2.4,edge*0.62*strength);
}
