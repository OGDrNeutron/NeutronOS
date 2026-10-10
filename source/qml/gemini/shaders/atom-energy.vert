VARYING vec2 energyUv;
void MAIN() {
    energyUv=UV0;
    vec3 energyVertex=VERTEX;
    float crackle=sin(UV0.x*439.0+orbitPhase*.13)*sin(UV0.x*211.0-orbitPhase*.08);
    energyVertex.xy+=normalize(VERTEX.xy)*crackle*1.8;
    POSITION=MODELVIEWPROJECTION_MATRIX*vec4(energyVertex,1.0);
}
