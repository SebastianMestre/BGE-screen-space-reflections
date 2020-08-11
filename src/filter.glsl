uniform sampler2D bgl_DepthTexture;
uniform sampler2D bgl_RenderedTexture;

uniform float bgl_RenderedTextureWidth;
uniform float bgl_RenderedTextureHeight;

float width = bgl_RenderedTextureWidth;
float height = bgl_RenderedTextureHeight;

vec2 texCoord = gl_TexCoord[0].st;

//#######################################
//these MUST match your current settings
float znear = 1.0;                      //camera clipping start
float zfar = 50.0;                      //camera clipping end
float fov = 90.0 / 90.0;                //check your camera settings, set this to (90.0 / fov) (make sure you put a ".0" after your number)
float aspectratio = 16.0/9.0;           //width / height (make sure you put a ".0" after your number)
vec3 skycolor = vec3(0.01,0.03,0.07);   // use the horizon color under world properties, fallback when reflections fail

//tweak these to your liking
float reflectance = 0.04;    //reflectivity of surfaced that you face head-on
float stepSize = 0.03;      //reflection choppiness, the lower the better the quality, and worse the performance 
int samples = 100;          //reflection distance, the higher the better the quality, and worse the performance
float startScale = 4.0;     //first value for variable scale calculations, the higher this value is, the faster the filter runs but it gets you staircase edges, make sure it is a power of 2

//#######################################

float getDepth(vec2 coord){
    float zdepth = texture2D(bgl_DepthTexture,coord).x;
    return -zfar * znear / (zdepth * (zfar - znear) - zfar);
}

vec3 getViewPosition(vec2 coord){
    vec3 pos = vec3((coord.s * 2.0 - 1.0) / fov, (coord.t * 2.0 - 1.0) / aspectratio / fov, 1.0);
    return (pos * getDepth(coord));
}

vec3 getViewNormal(vec2 coord){
    
    vec3 p0 = getViewPosition(coord);
    vec3 p1 = getViewPosition(coord + vec2(1.0 / width, 0.0));
    vec3 p2 = getViewPosition(coord + vec2(0.0, 1.0 / height));
  
    vec3 dx = p1 - p0;
    vec3 dy = p2 - p0;
    return normalize(cross( dy , dx ));
}

vec2 getViewCoord(vec3 pos){
    vec3 norm = pos / pos.z;
    vec2 view = vec2((norm.x / fov + 1.0) / 2.0, (norm.y / fov * aspectratio + 1.0) / 2.0);
    return view;
}

float lenCo(vec3 vector){
    return pow(pow(vector.x,2.0) + pow(vector.y,2.0) + pow(vector.z,2.0), 0.5);
}

vec3 rayTrace(vec3 startpos, vec3 dir){
    vec3 pos = startpos;
    float olz = pos.z;      //previous z
    float scl = startScale; //step scale
    vec2 psc;               // Pixel Space Coordinate of the ray's' current viewspace position 
    vec3 ssg;               // Screen Space coordinate of the existing Geometry at that pixel coordinate
    
    for(int i = 0; i < samples; i++){
        olz = pos.z; //previous z
        pos = pos + dir * stepSize * pos.z * scl;
        psc = getViewCoord(pos); 
        ssg = getViewPosition(psc); 
        if(psc.x < 0.0 || psc.x > 1.0 || psc.y < 0.0 || psc.y > 1.0 || pos.z < 0.0 || pos.z >= zfar){
            //out of bounds
            break;
        }
        if(scl == 1 && lenCo(pos) > lenCo(ssg) && lenCo(pos) - lenCo(ssg) < stepSize * 40){
            //collided
            return pos;
        }
        if(scl > 1 && lenCo(pos) - lenCo(ssg) > stepSize * scl * -1){
            //lower step scale
            pos = pos - dir * stepSize * olz * scl;
            scl = scl * 0.5;
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
        reflection.rgb = pow(skycolor,vec3(1,1,1)*(0.455));
    }
    
    gl_FragColor = mix(direct, reflection, schlick(reflectance, normal, viewVec));
}
