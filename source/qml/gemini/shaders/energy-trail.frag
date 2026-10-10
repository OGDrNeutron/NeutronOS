VARYING vec2 energyUv;
void MAIN(){
    // Positive angular motion: samples behind each head have positive age.
    float age=fract(orbitPhase/360.0-energyUv.x);
    age=min(age,fract(age+0.5));
    float wake=pow(max(0.0,1.0-age/wakeLength),2.5);
    float filament=.94+.06*sin(energyUv.x*80.0-orbitPhase*.07);
    float alpha=wake*halo*filament;
    if(alpha<0.008)discard;
    FRAGCOLOR=vec4(energyColor*(.6+1.8*wake),alpha);
}
