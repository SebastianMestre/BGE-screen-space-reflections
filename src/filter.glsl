uniform sampler2D bgl_DepthTexture;
uniform sampler2D bgl_RenderedTexture;

uniform float roughness;
uniform float reflectance;
uniform int rays;

uniform float bgl_RenderedTextureWidth;
uniform float bgl_RenderedTextureHeight;

float width = bgl_RenderedTextureWidth;
float height = bgl_RenderedTextureHeight;

vec2 texCoord = gl_TexCoord[0].st;

const float pi = 3.14159265359;

//#######################################

//these MUST match your current settings
float znear = 1.0;                    // camera clipping start
float zfar  = 20.0;                   // camera clipping end
float fov   = 50.0;                   // check your camera settings (make sure you put a ".0" after the number)
vec3 skycolor = vec3(0.1, 0.2, 0.2);  // use the horizon color under world properties, fallback when reflections fail
vec3 grncolor = vec3(0.9, 0.9, 0.9);  // fake floor color, fallback when reflections fail

//tweak these to your liking -- each comes with advantages and disadvantages
float stepSize   = 0.01; // step size for raymarching
int   maxsteps   = 100;  // maximum amount of steps for raymarching
float startScale = 4.0;  // initial scale of step size for raymarching
float depth      = 0.5;  // thickness of the world

//#######################################

float aspectratio = width / height;
float fovratio    = 90.0  / fov;

//#######################################

float getDepth(vec2 coord) {
  float zdepth = texture2D(bgl_DepthTexture, coord).x;
  return -zfar * znear / (zdepth * (zfar - znear) - zfar);
}

vec3 getViewPosition(vec2 coord) {
  vec3 pos = vec3((coord.s * 2.0 - 1.0) / fovratio, (coord.t * 2.0 - 1.0) / aspectratio / fovratio, 1.0);
  return (pos * getDepth(coord));
}

/// Is this even worth the performance?
vec3 getViewNormal(vec2 coord) {
  float pW = 1.0 / width;
  float pH = 1.0 / height;

  vec3 p1  = getViewPosition(coord + vec2(pW, 0.0)).xyz;
  vec3 p2  = getViewPosition(coord + vec2(0.0, pH)).xyz;
  vec3 p3  = getViewPosition(coord + vec2(-pW, 0.0)).xyz;
  vec3 p4  = getViewPosition(coord + vec2(0.0, -pH)).xyz;

  vec3 vP  = getViewPosition(coord);

  vec3 dx  = vP - p1;
  vec3 dy  = p2 - vP;
  vec3 dx2 = p3 - vP;
  vec3 dy2 = vP - p4;

  if (length(dx2) < length(dx) && coord.x - pW >= 0.0 || coord.x + pW > 1.0) {
    dx = dx2;
  }
  if (length(dy2) < length(dy) && coord.y - pH >= 0.0 || coord.y + pH > 1.0) {
    dy = dy2;
  }

  return normalize(cross(dx, dy));
}

vec2 getScreenCoord(vec3 pos) {
  vec3 norm = pos / pos.z;
  vec2 view = vec2((norm.x * fovratio + 1.0) / 2.0, (norm.y * fovratio * aspectratio + 1.0) / 2.0);
  return view;
}

vec2 snapToPixel(vec2 coord) {
  coord.x = (floor(coord.x *  width) + 0.5) /  width;
  coord.y = (floor(coord.y * height) + 0.5) / height;
  return coord;
}

/* ------------------------------------------------------------------ */

/// Halton low discrepancy series generator. maybe replace with something more efficient later?
float halton(int i, int b) {
  float f = 1.0;
  float r = 0.0;
  while (i > 0) {
    f /= float(b);
    r += f * mod(float(i), float(b));
    i /= b;
  }
  return r;
}

vec3 distort(vec3 vec, vec3 ref, int i, float n) {
  vec3 z = vec;
  vec3 y = cross(z, ref);
  vec3 x = cross(z, y);

  float ran1 = mod(halton(i, 2) + ref.x * 167.0, 1.0);
  float ran2 = mod(halton(i, 3) + ref.y * 167.0, 1.0);

  // assumes isotropic surface
  float phi = ran2 * pi * 2.0;
  
  // Blinn
  //float theta = acos(pow(ran1, 1.0 / (n + 2.0)));
  
  // Mestre
  //float theta = log(ran1 / (1.0-ran1)) / n;
  
  // GGX
  float theta =  acos(sqrt((1.0 - ran1) / (( roughness*roughness*roughness*roughness - 1.0) * (ran1) + 1.0)));
  // the the standard form of GGX uses roughness^2, and not roughness^4, but a cuadratic scale is prefered by many
    
  float xc = sin(theta) * cos(phi);
  float yc = sin(theta) * sin(phi);
  float zc = cos(theta);

  vec3 mod = xc * x + yc * y + zc * z;

  if (dot(mod, vec) < 0.0) {
    mod = reflect(mod, vec);
  }

  return mod;
}

vec4 LINEARtoSRGB(vec4 c) {
  return pow(c, vec4(2.2));
}

vec4 SRGBtoLINEAR(vec4 c) {
  return pow(c, vec4(1.0 / 2.2));
}

/* ------------------------------------------------------------------ */

float schlick(float r0, vec3 n, vec3 i) {
  return r0 + (1.0 - r0) * pow(1.0 - dot(-i, n), 5.0);
}

/* ------------------------------------------------------------------ */

vec3 raymarch(vec3 position, vec3 direction) {
  direction = normalize(direction) * stepSize;
  float stepScale = startScale;

  for (int steps = 0; steps < maxsteps; steps++) {

    vec3 deltapos = direction * stepScale * position.z;
    position += deltapos;
    vec2 screencoord = getScreenCoord(position);

    bool OOB = false; // OUT OF BOUNDS
    OOB = OOB || (screencoord.x < 0.0) || (screencoord.x > 1.0); // X
    OOB = OOB || (screencoord.y < 0.0) || (screencoord.y > 1.0); // Y
    OOB = OOB || (position.z >  zfar ) || (position.z <  znear); // Z
    if (OOB) {
      return vec3(0.0);
    }

    screencoord = snapToPixel(screencoord);
    float penetration = length(position) - length(getViewPosition(screencoord));

    if (penetration > 0.0) {
      if (stepScale > 1.0) {
        position -= deltapos;
        stepScale *= 0.5;
      } else if (penetration < depth) {
        return position;
      }
    }
  }
  return vec3(0.0);
}

/* ------------------------------------------------------------------ */

vec4 glossyReflection(vec3 Position, vec3 Normal, vec3 View, int rays) {
  vec4 radiance = vec4(0.0);
  vec4 irradiance = vec4(0.0);

  float blinnExponent = pow(2.0, 15.0 * (1.0 - roughness));

  for (int i = 0; i < rays; i++) {

    vec3 middle      = distort(Normal, View, i + 1, blinnExponent);
    vec3 omega       = reflect(View, middle);
    vec3 collision   = raymarch(Position, omega);
    vec2 screenCoord = getScreenCoord(collision);

    irradiance = SRGBtoLINEAR(texture2D(bgl_RenderedTexture, screenCoord));

    float backamount = max(abs(screenCoord.x - 0.5), abs(screenCoord.y - 0.5));
    backamount = pow(backamount * 2.0, 5.0) * 1.5 - 0.25;

    if (collision.z == 0.0) {
      backamount = 1.0;
    }

    radiance += mix(irradiance, SRGBtoLINEAR(vec4(skycolor, 1.0)) * (pi/2.0), backamount) / float(rays);
  }
  
  return radiance;
}

/* ------------------------------------------------------------------ */

void main() {
  //fragment geometry data
  vec3 position = getViewPosition(texCoord);
  vec3 normal = getViewNormal(texCoord);
  vec3 view = normalize(position);

  //fragment shading data
  float reflectivity = schlick(reflectance, normal, view);

  //fragment color data
  vec4 image = texture2D(bgl_RenderedTexture, texCoord);

  vec4 direct = SRGBtoLINEAR(image);
  vec4 reflection = glossyReflection(position, normal, view, rays);

  gl_FragColor = LINEARtoSRGB(mix(dir
