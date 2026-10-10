#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float strength; float readyScene; };
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void main() {
 vec2 uv=qt_TexCoord0;
 float haze=noise(uv*7.0)*.6+noise(uv*21.0)*.3+noise(uv*57.0)*.1;
 float top=exp(-length((uv-vec2(.52,-.10))*vec2(1.3,1.0))*3.5);
 float side=exp(-length((uv-vec2(.80,.82))*vec2(1.7,3.0))*4.0);
 vec3 blue=vec3(.01,.12,.36)*top*(.3+haze)*strength;
 vec3 red=vec3(.18,.006,.022)*side*haze*strength;
 float arc=exp(-abs(length((uv-vec2(.5,.42))*vec2(1.7,1.0))-.44)*100.0)*readyScene;
 vec3 color=blue+red+vec3(.008,.055,.20)*arc*(.5+haze);
 fragColor=vec4(color,clamp(top*.3+side*.12+arc*.3,0.0,.55))*qt_Opacity;
}
