uniform sampler2D bgl_DepthTexture;
uniform sampler2D bgl_RenderedTexture;

uniform float bgl_RenderedTextureWidth;
uniform float bgl_RenderedTextureHeight;

float width = bgl_RenderedTextureWidth;
float height = bgl_RenderedTextureHeight;

vec2 texCoord = gl_TexCoord[0].st;

//#######################################
//these MUST match your current settings
float znear = 1;            //camera clipping start
float zfar = 35;            //camera clipping end
float fov = 40;             //check your camera settings
float aspectratio = 16/9;   //width / height
vec3 skycolor = vec3(0.5,0.5,0.5); // horizon color under world properties, fallback when reflections fail

//tweak these to your liking
float reflectance = 0.04;
float stepSize = 0.005;
int samples = 300;

//#######################################

float getDepth(vec2 coord){
    float zdepth = texture2D(bgl_DepthTexture,coord).x;
    return -zfar * znear / (zdepth * (zfar - znear) - zfar);
}

vec3 getViewPosition(vec2 coord){
    vec3 pos;
    pos =  vec3((coord.s * 2.0 - 1.0) / (90.0 / fov), (coord.t * 2.0 - 1.0) / aspectratio / (90.0 / fov), 1.0);
    return (pos * getDepth(coord));
}

vec3 getViewNormal(vec2 coord){
    
    vec3 p0 = getViewPosition(coord);
    vec3 p1 = getViewPosition(coord + vec2(1.0 / width, 0.0)).xyz;
    vec3 p2 = getViewPosition(coord + vec2(0.0, 1.0 / height)).xyz;
  
    vec3 dx = p1 - p0;
    vec3 dy = p2 - p0;
    return normalize(cross( dy , dx ));
}

vec2 getViewCoord(vec3 pos){
    vec3 norm = pos / pos.z;
    vec2 view = vec2((norm.x * (90.0 / fov) + 1.0) / 2.0, (norm.y * (90.0 / fov) * aspectratio + 1.0) / 2.0);
    return view;
}

float lenCo(vec3 vector){
    return pow(pow(vector.x,2.0) + pow(vector.y,2.0) + pow(vector.z,2.0), 0.5);
}

vec3 rayTrace(vec3 startpos, vec3 dir){
    vec3 pos = startpos;
    vec2 psc;
    vec3 ssg;
    
    for(int i = 0; i < samples; i++){
        pos = pos + dir * stepSize * pos.z;
        psc = getViewCoord(pos); // Pixel Space Coordinate of the ray's' current viewspace position 
        ssg = getViewPosition(psc); // Screen Space coordinate of the existing Geometry at that pixel coordinate
        if(psc.x < 0.0 || psc.x > 1.0 || psc.y < 0.0 || psc.y > 1.0 || pos.z < 0.0 || pos.z >= zfar){
            //out of bounds
            break;
        }
        if(lenCo(pos) > lenCo(ssg) && lenCo(pos) - lenCo(ssg) < stepSize * 40){
            //colided
            return pos;
        }
    }
    // this will only run if loop ends before return or after break statement
    return vec3(0.0, 0.0, 0.0);
}
float schlick(float r0, vec3 n, vec3 i){
    return r0 + (1.0 - r0) * pow(1.0 - dot(-i,n),5.0);
}

void main(){
    
    //fragment color data
    vec4 direct = texture2D(bgl_RenderedTexture, texCoord);
    vec4 reflection;
    
    //fragment geometry data
    vec3 position = getViewPosition(texCoord);
    vec3 normal   = getViewNormal(texCoord);
    vec3 viewVec  = normalize(position);
    vec3 reflect  = reflect(viewVec,normal);
    
    //raytrace collision
    vec3 collision = rayTrace(position, reflect);
    
    //choose method
    if(collision.z != 0.0){
        vec2 sample = getViewCoord(collision);
        reflection  = texture2D(bgl_RenderedTexture,sample);
    }else{
        reflection = vec4(skycolor,1.0);
    }
    
    gl_FragColor = mix(direct, reflection, schlick(reflectance, normal, viewVec));
}
