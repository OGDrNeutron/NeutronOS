VARYING vec2 fragmentUv;
VARYING float edgeCoordinate;
VARYING float fragmentOpacity;
float rnd(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void MAIN(){
    fragmentUv=UV0;edgeCoordinate=COLOR.x;
    vec3 center=vec3((UV1.x-.5)*1672.0,(.5-UV1.y)*941.0,0.0);
    vec3 target=vec3((impact.x-.5)*1672.0,(.5-impact.y)*941.0,0.0);
    vec3 local=VERTEX-center;
    float seed=rnd(UV1);
    float t=max(0.0,elapsed-.35-seed*.16);
    float separate=smoothstep(0.0,.4,t);
    float inward=smoothstep(.4,2.0,t);
    float angle=inward*(6.28318+seed*2.5);
    vec2 radial=center.xy-target.xy;
    radial=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*radial;
    radial*=mix(1.0+separate*.08,.015,inward);
    float tumble=t*(seed-.5)*5.0;
    local.xy=mat2(cos(tumble),sin(tumble),-sin(tumble),cos(tumble))*local.xy;
    float tilt=t*(.4+seed)*4.0;
    local.yz=mat2(cos(tilt),sin(tilt),-sin(tilt),cos(tilt))*local.yz;
    local.xz=mat2(cos(tilt*.7),sin(tilt*.7),-sin(tilt*.7),cos(tilt*.7))*local.xz;
    local*=mix(1.0,.18,inward);
    float explode=max(0.0,elapsed-2.95);
    vec2 direction=normalize(center.xy-target.xy+vec2(.01));
    radial+=direction*explode*explode*(3000.0+1500.0*seed);
    VERTEX=vec3(target.xy+radial,0.0)+local;
    VERTEX.z+=separate*sin(t*3.0+seed*6.0)*50.0*(1.0-inward);
    fragmentOpacity=1.0-smoothstep(3.05,3.65,elapsed);
    POSITION=MODELVIEWPROJECTION_MATRIX*vec4(VERTEX,1.0);
}
