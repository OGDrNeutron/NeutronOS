VARYING vec3 surfaceNormal;
VARYING vec3 viewNormal;
VARYING vec2 surfaceUv;
void MAIN() {
    vec3 n=normalize(surfaceNormal);
    vec3 light=normalize(vec3(-0.5,0.8,0.12));
    // Geographic normals use the equirectangular texture's IANA-map convention.
    // Decorative spin changes the view, never the UTC subsolar longitude.
    float longitude=(surfaceUv.x-0.5)*6.28318530718;
    float latitude=(0.5-surfaceUv.y)*3.14159265359;
    vec3 geographicNormal=vec3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude));
    float sunlight=mix(dot(n,light),dot(geographicNormal,normalize(solarDirection)),solarLighting);
    float day=smoothstep(-0.13,0.18,sunlight);
    vec3 land=texture(dayMap,surfaceUv).rgb;
    vec3 night=texture(nightMap,surfaceUv).rgb;
    float ocean=smoothstep(0.01,0.10,land.b-max(land.r,land.g));
    vec3 halfVector=normalize(light+vec3(0,0,1));
    float specular=pow(max(dot(n,halfVector),0.0),75.0)*ocean*day;
    float rim=pow(1.0-max(normalize(viewNormal).z,0.0),3.7);
    vec3 color=land*(0.08+0.92*max(sunlight,0.0))*day;
    // Separate warm city emissions from NASA Black Marble's blue terrain base.
    float cityMask=smoothstep(0.0,0.08,night.r-night.b*0.85);
    color+=night*vec3(3.8,2.9,1.8)*cityMask*(1.0-day);
    color+=vec3(0.005,0.035,0.11)*ocean*day;
    color+=vec3(0.02,0.28,0.65)*rim + vec3(0.45,0.63,0.8)*specular;
    if (solarLighting>0.5) {
        float nightVisibility=1.0-smoothstep(-0.10,0.06,sunlight);
        float artificial=smoothstep(0.015,0.10,night.r-night.b*0.85);
        color=land*(0.022+0.90*max(sunlight,0.0));
        color+=vec3(1.0,0.75,0.43)*night.r*artificial*3.4*nightVisibility;
        color+=vec3(0.008,0.035,0.09)*ocean*day;
        color+=vec3(0.015,0.12,0.32)*rim+vec3(0.25,0.42,0.62)*specular;
    }
    float border=texture(regionMap,surfaceUv).r;
    float halo=0.0;
    for(int i=0;i<4;i++) {
        vec2 offset=vec2(cos(float(i)*1.570796),sin(float(i)*1.570796))*.0018;
        halo+=texture(regionMap,surfaceUv+offset).r;
    }
    vec2 delta=surfaceUv-selectedPoint;
    delta.x*=cos((.5-selectedPoint.y)*3.141593);
    float distanceToPin=length(delta);
    float pin=exp(-distanceToPin*750.0)+exp(-abs(distanceToPin-.005)*1800.0);
    color+=vec3(.03,2.8,.28)*(border*.7+halo*.17+pin)*regionVisible;
    FRAGCOLOR=vec4(color,1.0);
}
