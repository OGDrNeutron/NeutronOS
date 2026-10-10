VARYING vec2 energyUv;
void MAIN(){
    float u=fract(energyUv.x+motion/360.0);
    float segment=fract(u*(rail>1.5?72.0:24.0));
    float segmentVisible=step(.12,segment)*step(segment,.88);
    float lane=floor(u*24.0);
    float energized=step(mod(lane+rail*3.0,7.0),1.0);
    vec3 tint=mod(lane,7.0)<1.0?vec3(3,.01,.035):vec3(.005,.35,3.2);
    tint=mix(vec3(.002,.035,.1),tint,energized);
    if(rail>2.5)tint=vec3(.002,.45,.8);
    if(mode>1.5)tint=vec3(.005,3.5,.8);
    else if(mode>.5)tint=vec3(4,.008,.02);
    if(segmentVisible<.1)discard;
    float ridge=.45+.55*pow(.5+.5*cos(energyUv.y*6.28318),2.0);
    FRAGCOLOR=vec4(tint*ridge,.8);
}
