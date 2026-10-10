VARYING vec3 surfaceNormal;
VARYING vec3 viewNormal;
VARYING vec2 surfaceUv;
void MAIN() {
    surfaceUv = UV0;
    surfaceNormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
    viewNormal = normalize(mat3(VIEW_MATRIX) * surfaceNormal);
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
