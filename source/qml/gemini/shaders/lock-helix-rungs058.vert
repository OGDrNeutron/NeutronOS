// Move each rung endpoint with its backbone without rebuilding CPU meshes.
void MAIN() {
    float theta = UV0.x * 6.28318530718;
    vec2 radial = vec2(cos(theta), sin(theta));
    vec2 tangent = vec2(-radial.y, radial.x);
    float phi = theta * 10.0;
    vec2 initial = vec2(cos(phi), sin(phi));
    vec2 crossSection = vec2(dot(VERTEX.xy, radial) - 260.0, VERTEX.z);
    float along = dot(crossSection, initial);
    float blend = (1.0 - along / 28.0) * 0.5;
    vec2 blue = 28.0 * vec2(cos(phi + turnRadians * 10.0), sin(phi + turnRadians * 10.0));
    vec2 red = -28.0 * vec2(cos(phi - turnRadians * 10.0), sin(phi - turnRadians * 10.0));
    vec2 section = mix(blue, red, blend) + crossSection - initial * along;
    VERTEX = vec3(radial * (260.0 + section.x) + tangent * dot(VERTEX.xy, tangent), section.y);
}
