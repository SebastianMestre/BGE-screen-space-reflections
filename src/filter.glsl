uniform sampler2D bgl_RenderedTexture;
uniform sampler2D bgl_DepthTexture;

uniform float bgl_RenderedTextureWidth;
uniform float bgl_RenderedTextureHeight;

/**** **** **** ****/

float width = bgl_RenderedTextureWidth;
float height = bgl_RenderedTextureHeight;

const float e = 2.71828182846;
const float pi = 3.14159265359;

/**** **** **** ****/

// #ADD THESE PROPERTIES TO THE OWNER OF THIS FILTER

uniform float roughness;
uniform float reflectance;
uniform int samples;

/**** **** **** ****/

// #MODIFY THESE TO CONFORM TO YOUR CAMERA

float znear = 0.1;
float zfar = 100.0;
float fov = 49.1;

/**** **** **** ****/

// #TWEAK THESE TO YOUR LIKING

float stepSize = 0.1;
int sampleSteps = 100;
int refineSteps = 3;
/// replace with: vec4(vec3(R, G, B), 1.0) 
vec4 skyColor = vec4(vec3(0.1), 1.0);

/**** **** **** ****/

float aspectratio = width / height;
float fovratio = 90.0 / fov;

/**** **** **** ****/

float getDepth(vec2 coord){
	float zsample = texture2D(bgl_DepthTexture, coord).x;
	return -zfar * znear / (zsample * (zfar - znear) - zfar);
}

vec4 gammaCompress(vec4 color){
	return pow(color, vec4(1.0 / 2.2));
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

/**** **** **** ****/

vec3 getViewPosition(vec2 coord) {
  vec3 pos = vec3((coord.s * 2.0 - 1.0) / fovratio, (coord.t * 2.0 - 1.0) / aspectratio / fovratio, 1.0);
  return (pos * getDepth(coord));
}

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

vec2 getCoord(vec3 pos) {
  vec3 norm = pos / pos.z;
  vec2 view = vec2((norm.x * fovratio + 1.0) / 2.0, (norm.y * fovratio * aspectratio + 1.0) / 2.0);
  return view;
}

vec2 snapToPixel(vec2 coord) {
  coord.x = (floor(coord.x *  width) + 0.5) /  width;
  coord.y = (floor(coord.y * height) + 0.5) / height;
  return coord;
}

/**** **** **** ****/

vec2 fragCoord = gl_TexCoord[0].st;
vec2 pixelCoord = vec2(int(fragCoord.x*width),int(fragCoord.y*height));
vec3 fragPos = getViewPosition(fragCoord);
vec3 fragNorm = getViewNormal(fragCoord);
vec3 fragView = normalize(fragPos);

/**** **** **** ****/

float getSkyAmount(vec2 coord){
	coord *= 2;
	coord -= 1;
	return pow(1-(1-coord.x * coord.x) * (1-coord.y * coord.y), 5);
}

float fresnel(vec3 normal, vec3 incoming){
	return reflectance + (1-reflectance) * pow(1-dot(normal, incoming), 5.0);
}

float brdf(vec3 normal, vec3 incoming){
	float fresnel = reflectance + (1.0 - reflectance) * pow(1-dot(normal, incoming), 5);
	
	float k = roughness * roughness * 0.5;
	
	float geometry_A = dot(normal, fragView) / (dot(normal, fragView) * (1-k) + k);
	float geometry_B = dot(normal, incoming) / (dot(normal, incoming) * (1-k) + k);
	return geometry_A * geometry_B * 0.25;
}

/**** **** **** ****/

int RNG_state = 1337;
int hash(int a, int b){
	RNG_state = (RNG_state * 167) ^ a;
	RNG_state = (RNG_state * 113) ^ b;
	return RNG_state;
}

vec3 generateMicronormal(int index){
	vec3 Z = fragNorm;
	vec3 X = normalize(cross(fragNorm, fragView));
	vec3 Y = cross(X, Z);
	
	int xyHash = hash(int(pixelCoord.x), int(pixelCoord.y));
	float ran1 = float(hash(xyHash, hash(index, 167))) / 2147483648.0 * 0.5 + 0.5;
	float ran2 = float(hash(xyHash, hash(index, 113))) / 2147483648.0 * 0.5 + 0.5;
	
	float alpha = roughness * roughness;
	float aa = alpha * alpha;
	float theta = acos(sqrt((1.0 - ran2) / (( aa - 1.0) * (ran2) + 1.0)));
	
	float phi = ran1 * 2.0 * pi;
	
	return normalize(Z * cos(theta) + X * sin(theta) * cos(phi) + Y * sin(theta) * sin(phi));
}

/**** **** **** ****/

vec3 raymarchRefine(vec3 position, vec3 direction){
	for(int i = 0; i < refineSteps; i++){
		direction *= 0.5;
		position += direction * (position.z < getDepth(getCoord(position)) ? 1 : -1);
	}
	return position;
}

vec4 raymarch(vec3 position, vec3 direction){
	
	direction *= stepSize;
	
	position += direction;
	
	vec3 oldPosition = position;
	float oldDepth = position.z;
	float oldDelta = 0.0;
	
	float thickness = direction.z + 0.01;
	
	for(int i = 0; i < sampleSteps; i++){
		vec2 screenCoord = getCoord(position);
		
		float depth = getDepth(screenCoord);
		float delta = position.z - depth;
		
		if(screenCoord.x < 0.0 || screenCoord.x > 1.0
		|| screenCoord.y < 0.0 || screenCoord.y > 1.0
		|| position.z  < znear || position.z  >  zfar){
			return skyColor;
		}
		
		if(delta > 0.0){
			float skyAmount = getSkyAmount(screenCoord);
			vec4 color;
			
			if(delta < thickness){
				position = raymarchRefine(position, direction);
				color = getColor(getCoord(position));
			}else if(depth - oldDepth > thickness){
				float blend = (oldDelta - delta) / max(oldDelta, delta) * 0.5 + 0.5;
				color = mix(getColor(getCoord(oldPosition)), getColor(getCoord(position)), blend);
			}
			
			return mix(color, skyColor, skyAmount);
		}else{
			oldDelta = -delta;
			oldPosition = position;
		}
	oldDepth = depth;
	position += direction;
	}
	return skyColor;
	
}

/**** **** **** ****/

vec4 glossyReflection(){
	vec4 radiance = vec4(0.0);
	float fresnelSum = 0.0;
	for(int i = 0; i < samples; i++){
		
		vec3 micronormal = generateMicronormal(i);
		vec3 incoming = reflect(fragView, micronormal);
		
		float fresnelValue = fresnel(micronormal, incoming);
		fresnelSum += fresnelValue;
		
		radiance += raymarch(fragPos, incoming) * fresnelValue * brdf(micronormal, incoming) / float(samples);
		
	}
	
	radiance.w = fresnelSum;
	
	return radiance;
}

/**** **** **** ****/

void main(){
	
	vec4 direct = getColor(fragCoord);
	vec4 reflection = glossyReflection();
	
	setColor(reflection + direct * (1-reflection.w));
	setColor(reflection);
}
