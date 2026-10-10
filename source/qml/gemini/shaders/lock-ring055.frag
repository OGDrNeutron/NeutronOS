VARYING vec2 energyUv;
float wave(float u,float age,float origin) {
    if(age>=1.0 || age<0.0)return 0.0;
    float d=fract(u+age*1.22+origin);
    float head=exp(-pow(min(d,1.0-d)*85.0,2.0));
    float wake=exp(-d*28.0)*smoothstep(.0,.065,age);
    return (head+wake*.42)*smoothstep(0.0,.055,age)*(1.0-smoothstep(.65,1.0,age));
}
void MAIN() {
    // Positive UV phase travels clockwise in the front-facing XY torus.
    float u=fract(energyUv.x+motion/360.0);
    float count=rail>2.5?120.0:72.0;
    float block=fract(u*count);
    float segment=smoothstep(.05,.14,block)*(1.0-smoothstep(.87,.96,block));
    float red=smoothstep(.6,.96,cos(u*18.84956+rail*.35));
    vec3 blue=vec3(.008,.55,2.5), crimson=vec3(3.0,.012,.05);
    vec3 tint=mix(blue,crimson,red);
    float glow=.55+.45*pow(.5+.5*cos(u*12.56637-rail*.45),3.0);
    float breathe=.88+.12*sin(motion*.10472);
    float pulse=0.0;
    for(int i=0;i<4;i++) {
        pulse+=wave(energyUv.x,wavesA[i],float(i)*.117);
        pulse+=wave(energyUv.x,wavesB[i],float(i+4)*.117);
        pulse+=wave(energyUv.x,wavesC[i],float(i+8)*.117);
        pulse+=wave(energyUv.x,wavesD[i],float(i+12)*.117);
    }
    if(mode>1.5)tint=vec3(.008,3.0,.55);
    else if(mode>.5)tint=vec3(3.5,.008,.035);
    float ridge=.62+.38*pow(.5+.5*cos(energyUv.y*6.283185),2.0);
    vec3 color=tint*glow*breathe+vec3(.04,1.0,3.6)*min(pulse,2.4);
    FRAGCOLOR=vec4(color*ridge,segment*.92);
}
