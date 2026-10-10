#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; };
layout(binding=1) uniform sampler2D source;
void main() {
    vec4 c=texture(source,qt_TexCoord0);
    float matte=smoothstep(0.015,0.075,max(c.r,max(c.g,c.b)));
    fragColor=c*matte*qt_Opacity;
}
