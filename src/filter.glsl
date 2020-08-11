#version 130
uniform sampler2D bgl_RenderedTexture;
uniform sampler2D bgl_DepthTexture;
uniform float bgl_RenderedTextureWidth;
uniform float bgl_RenderedTextureHeight;

// **** **** **** ****

// #ADD THESE PROPERTIES TO THE OWNER OF THIS FILTER

uniform float roughness;
uniform float reflectance;

// **** **** **** ****

// #MODIFY THESE TO CONFORM TO YOUR CAMERA

float znear = 0.1;
float zfar = 100.0;
float fov = 49.1;

// **** **** **** ****

// #TWEAK THESE TO YOUR LIKING

const float stepSize = 0.05; // stride of cast rays (in blender units)
const int sampleSteps = 128; // maxmimum amount of steps that a ray can take
const int samples = 4;       // amount of rays fired per pixel
/// replace with: vec4(R, G, B, 1.0)
const vec4 skyColor = vec4(0.3, 0.5, 0.9, 1.0);

// **** **** **** ****

float width = bgl_RenderedTextureWidth;
float height = bgl_RenderedTextureHeight;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

// **** **** **** ****
float aspectratio = width / height;
float fovratio = 90.0 / fov;

// **** **** **** ****

float sampleDepth (vec2 coord) {
    return texture2D(bgl_DepthTexture, coord).x;
}

float linearizeDepth (float zsample) {
	return -zfar * znear / (zsample * (zfar - znear) - zfar);
}

float getDepth(vec2 coord){
    return linearizeDepth(sampleDepth(coord));
}

vec4 gammaCompress(vec4 color){
	return pow(color, vec4(1.0/2.2));
}

vec4 gammaDecompress(vec4 color){
	return pow(color, vec4(2.2));
}

vec4 getColor(vec2 coord){
	return gammaDecompress(texture2D(bgl_RenderedTexture, coord));
}

void setColor(vec4 color){
	gl_FragColor = gammaCompress(color);
}

// **** **** **** ****

vec3 getViewPosition(vec2 coord) {
  vec3 pos = vec3((coord.s * 2.0 - 1.0) / fovratio, (coord.t * 2.0 - 1.0) / aspectratio / fovratio, 1.0);
  return (pos * getDepth(coord));
}

vec3 getViewNormal(vec2 coord) {
  float pW = 1.0 / width;
  float pH = 1.0 / height;

  vec3 p1  = getViewPosition(coord + vec2(pW, 0.0)).xyz;
  vec3 p2  = getViewPosition(coord + vec2(0.0, pH)).xyz;

  vec3 vP  = getViewPosition(coord);

  vec3 dx  = vP - p1;
  vec3 dy  = p2 - vP;
  
  vec3 p3  = getViewPosition(coord + vec2(-pW, 0.0)).xyz;
  vec3 p4  = getViewPosition(coord + vec2(0.0, -pH)).xyz;
  vec3 dx2 = p3 - vP;
  vec3 dy2 = vP - p4;

  if (dot(dx2,dx2) < dot(dx,dx) && coord.x - pW >= 0.0 || coord.x + pW > 1.0) {
    dx = dx2;
  }
  if (dot(dy2,dy2) < dot(dy,dy) && coord.y - pH >= 0.0 || coord.y + pH > 1.0) {
    dy = dy2;
  }

  return normalize(cross(dx, dy));
}

vec2 getCoord(vec3 pos) {
  vec3 norm = pos / pos.z;
  vec2 view = vec2((norm.x * fovratio + 1.0) / 2.0, (norm.y * fovratio * aspectratio + 1.0) / 2.0);
  return view;
}

// **** **** **** ****

struct ShaderData {
	vec4 direct;
	vec3 normal;
	vec3 view;
	vec3 position;

	float alpha;

	vec3 micronormal;
	vec3 light;

	float alpha2;

	float ndotv;
	float ndotl;

	// hdotl = hdotv = cos(theta_d)
	float hdotl;

	float fresnel;
	float brdf;

	float diffuse_f_view;
	float diffuse_f_light;
};

// **** **** **** ****

float getSkyAmount(vec2 coord){
	coord *= 2.0;
	coord -= 1.0;
	return pow(1.0-(1.0-coord.x * coord.x) * (1.0-coord.y * coord.y), 5.0);
}

float fresnel(const ShaderData d){
	return reflectance + (1.0-reflectance) * pow(1.0-d.hdotl, 5.0);
}


float g1 (float ndotv, float alpha2) {
    float cos2 = ndotv * ndotv;
    float tan2 = (1.0f-cos2)/cos2;
    
    return 2.0f / (1.0f + sqrt(1.0f + alpha2 * tan2));
}

float brdf (const ShaderData d) {
	// D term is not computed because we are importance-sampling it exactly.

	float geometry_A = g1(d.ndotl, d.alpha2);
	float geometry_B = g1(d.ndotv, d.alpha2);

	// I'm not sure why, but it looks like we should not divide by this
	// float denom = 4.0 * d.ndotl * d.ndotv;
	// I get the ndotl, since it cancels out with the one in the rendering equation.
	// But the 4ndotv is a total mistery to me...
	// I need to go over the math again.

	return geometry_A * geometry_B;
}

// Random numbers generated in a roughly blue noise pattern
// We should offset them using the screen coordinate somehow too.
const float randomA[32] = float[](
	0.4089603577439599f, 0.0896500312892546f, 0.6591577972340148f, 0.0901822232642283f,
	0.6921296572717603f, 0.3216206881285436f, 0.4389636225233531f, 0.8684473781706337f,
	0.2153705165450234f, 0.6982811052424471f, 0.5100657509892909f, 0.5969037419749239f,
	0.2826421637434830f, 0.2704069270277116f, 0.0873047035801428f, 0.8949758675200112f,
	0.7261603311075456f, 0.7057593639689843f, 0.9194667339198013f, 0.1499367709685910f,
	0.2378494703557717f, 0.8382222073990692f, 0.8715069738124827f, 0.4633002657457567f,
	0.6253217355093506f, 0.9075575210336372f, 0.2155927354335262f, 0.0634106216410736f,
	0.4710479453603139f, 0.3797833814840630f, 0.0882737220335973f, 0.4858608023695249f
);

const float randomB[32] = float[](
	0.1975087128742691f, 0.4405716101214095f, 0.9156427590642274f, 0.9200501479117965f,
	0.6982629029626343f, 0.4382289145146980f, 0.5317940570208527f, 0.3982982871121937f,
	0.0916033464809752f, 0.1709175437251112f, 0.8882776771492672f, 0.5262574787690367f,
	0.7445798767371159f, 0.2679827983148667f, 0.7954851945416024f, 0.8845487120051808f,
	0.5677403489172201f, 0.3772120625497965f, 0.5563936974545356f, 0.5867492760166948f,
	0.5253957565511908f, 0.6377394716383505f, 0.1351919077676108f, 0.0881696515152218f,
	0.7911953140212018f, 0.2777270195798199f, 0.8909074535773583f, 0.6070434630706817f,
	0.3629028841433275f, 0.8552917189293238f, 0.3087955852440492f, 0.6980571771861915f
);

vec2 nth_random (int n) {
	// @@ This breaks if we ever want more than 32 samples
	return vec2(randomA[n], randomB[n]);
}

vec2 micronormal (const ShaderData d, vec2 r)  {
	float theta = acos(sqrt((1.0 - r.x) / ((d.alpha2 - 1.0) * r.x + 1.0)));
	float phi = r.y * TAU;

	return vec2(phi, theta);
}

//get a scalar random value from a 3d value
float rand(vec3 value){
    //make value smaller to avoid artefacts
    vec3 smallValue = sin(value);
    //get scalar value from 3d vector
    float random = dot(smallValue, vec3(12.9898, 78.233, 37.719));
    //make value more random by making it bigger and then taking teh factional part
    random = mod(sin(random) * 143758.5453, 1.0f);
    return random;
}

// PRECONDITION: Coords is a rotation matrix
vec3 generateMicronormal(const ShaderData d, int index, mat3 coords){
	
	vec2 r = mod(nth_random(index) * rand(d.view), 1.0);
	vec2 n_polar = micronormal(d, r);

// INVARIANT: n_tangentSpace is a unit vector
	vec3 n_tangentSpace = vec3(
		sin(n_polar.y) * cos(n_polar.x),
		sin(n_polar.y) * sin(n_polar.x),
		cos(n_polar.y)
	);
	
    vec3 n_coordSpace = coords * n_tangentSpace;

	return n_coordSpace;
}

// **** **** **** ****

vec3 raymarch ( vec3 position, vec3 direction ) {
	direction = normalize(direction);
    
	for (int i = 0; i < sampleSteps; ++i) {
		vec2 screenCoord = getCoord(position);
		if (position.z > getDepth(screenCoord)) {
			return getColor(screenCoord).xyz;
		}
		position += direction * stepSize;
	}

    return skyColor.xyz;
}

// **** **** **** ****

ShaderData make_shader_data () {
	ShaderData result;

	vec2 fragCoord = gl_TexCoord[0].st;

	result.direct = getColor(fragCoord);
	result.position = getViewPosition(fragCoord);
	result.normal = getViewNormal(fragCoord);
	// position is the shift from the camera to the current fragment.
	// In particular, it points away from the camera. We want the direction
	// from current the fragment to the camera, so we change the sign (-).
	result.view = -normalize(result.position);

	result.alpha = roughness * roughness;
	result.alpha2 = result.alpha * result.alpha;

	result.ndotv = dot(result.view, result.normal);

	return result;
}

void update_shader_data (inout ShaderData result, vec3 micronormal) {
	result.micronormal = micronormal;

	// glsl reflects vectors across a plane.
	// We want to reflect *against* a plane
	result.light = -reflect(result.view, micronormal);

	result.ndotl = dot(result.normal, result.light);
	result.hdotl = dot(result.micronormal, result.light);

	result.fresnel = fresnel(result);
	result.brdf = brdf(result);

	// @@ Probably dont need to store all of these
	float diffuse_f90 = 0.5f + 2.0f * roughness * result.hdotl * result.hdotl; 
	float diffuse_f0 = 1.0f - reflectance;
	//setColor(result.diffuse_f90 >= 9.0 ? vec4(1.0,0.0,0.0,0.0) : vec4(0.0,1.0,0.0,0.0));
	result.diffuse_f_view = diffuse_f0 + (diffuse_f90 - diffuse_f0) * pow(1.0f - result.ndotv, 5.0f);
	result.diffuse_f_light = diffuse_f0 + (diffuse_f90 - diffuse_f0) * pow(1.0f - result.ndotl, 5.0f);
}

// Return a vec4, pack average fresnel into alpha channel
vec4 glossyReflection(ShaderData d){

	vec3 Z = d.normal;
	vec3 X = normalize(cross(d.normal, d.view));
	vec3 Y = cross(Z, X);

	mat3 coords = mat3(X, Y, Z);

	vec4 radiance = vec4(0.0);

	for(int i = 0; i < samples; i++){
		
		vec3 micronormal = generateMicronormal(d, i, coords);

		update_shader_data(d, micronormal);
		
		radiance += vec4(
			raymarch(d.position, d.light) * d.brdf * d.fresnel,
			d.diffuse_f_view * d.diffuse_f_light);
		
	}
	
	radiance /= float(samples);

	return radiance;
}

// **** **** **** ****

vec4 lerp(vec4 a, vec4 b, float t){
	return a + (b-a)*t;
}

void main(){
	ShaderData d = make_shader_data();

	vec4 reflection = glossyReflection(d);

	// setColor(lerp(d.direct, reflection, clamp(d.view.x*64.0, -1.0, 1.0)*0.5+0.5));
	setColor(reflection + d.direct * reflection.w);
}
