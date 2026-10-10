VARYING vec2 energyUv;
void MAIN() {
    float u=fract(energyUv.x-orbitPhase/360.0);
    float tail=exp(-u*13.0);
    float flicker=.45+.55*pow(.5+.5*sin(energyUv.x*710.0+orbitPhase*.2),3.0);
    FRAGCOLOR=vec4(energyColor*(.3+tail*1.8),(.10+.90*tail)*flicker);
}
