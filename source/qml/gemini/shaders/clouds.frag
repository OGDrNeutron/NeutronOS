VARYING vec3 surfaceNormal;
VARYING vec3 viewNormal;
VARYING vec2 surfaceUv;
void MAIN() {
    float illumination=max(dot(normalize(surfaceNormal),normalize(vec3(-0.65,0.28,0.8))),0.0);
    float longitude=(surfaceUv.x-0.5)*6.28318530718;
    float latitude=(0.5-surfaceUv.y)*3.14159265359;
    vec3 geographicNormal=vec3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude));
    illumination=mix(illumination,max(dot(geographicNormal,normalize(solarDirection)),0.0),solarLighting);
    float alpha=texture(cloudMap,surfaceUv).a*0.38;
    FRAGCOLOR=vec4(vec3(mix(0.12,0.025,solarLighting)+0.88*illumination),alpha);
}
