#version 330

uniform vec2 resolution;
uniform float currentTime;
uniform vec3 camPos;
uniform vec3 camDir;
uniform vec3 camUp;
uniform sampler2D tex;
uniform bool showStepDepth;

in vec3 pos;

out vec3 color;

#define PI 3.1415926535897932384626433832795
#define RENDER_DEPTH 800
#define CLOSE_ENOUGH 0.00001

#define BACKGROUND -1
#define BALL 0
#define BASE 1

#define GRADIENT(pt, func) vec3( \
    func(vec3(pt.x + 0.0001, pt.y, pt.z)) - func(vec3(pt.x - 0.0001, pt.y, pt.z)), \
    func(vec3(pt.x, pt.y + 0.0001, pt.z)) - func(vec3(pt.x, pt.y - 0.0001, pt.z)), \
    func(vec3(pt.x, pt.y, pt.z + 0.0001)) - func(vec3(pt.x, pt.y, pt.z - 0.0001)))

const vec3 LIGHT_POS[] = vec3[](vec3(5, 18, 10));

///////////////////////////////////////////////////////////////////////////////

vec3 getBackground(vec3 dir) {
  float u = 0.5 + atan(dir.z, -dir.x) / (2 * PI);
  float v = 0.5 - asin(dir.y) / PI;
  vec4 texColor = texture(tex, vec2(u, v));
  return texColor.rgb;
}

vec3 getRayDir() {
  vec3 xAxis = normalize(cross(camDir, camUp));
  return normalize(pos.x * (resolution.x / resolution.y) * xAxis + pos.y * camUp + 5 * camDir);
}

///////////////////////////////////////////////////////////////////////////////

float sphere(vec3 pt) {
  return length(pt) - 1;
}

float cube(vec3 pt){
	vec3 d = abs(pt) - 1;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float plane(vec3 pt, vec3 pos) {
	return dot(pt - pos, vec3(0,1,0));
}

float smin(float a, float b) {
 float k = 0.2;
 float h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1);
 return mix(b, a, h) - k * h * (1 - h);
}

float sphere_cube(vec3 pt, vec3 pos, int blending_mode){
	vec3 spherePos = pos + vec3(1, 0, 1);
	float c = cube(pt - pos);
	float s = sphere(pt - spherePos);

	switch(blending_mode){
	case 1: return min(c, s); break;
	case 2: return max(c, s); break;
	case 3: return smin(c, s); break;
	case 4: return max(c, -s);break;

	}
}

float torus(vec3 pt){
	vec2 q = vec2(length(pt.xz)-3.0,pt.y);
	return length(q)-0.5;
}

float flatTori(vec3 pt){
	mat4 T = mat4(
		 vec4(1, 0, 0, 0),
		 vec4(0, 1, 0, 0),
		 vec4(0, 0, 1, 4),
		 vec4(0, 0, 0, 1));

	vec3 pos = (vec4(pt, 1) * inverse(T)).xyz;
	return torus(vec3(mod(pos.x + 4, 8) - 4, pos.y, mod(pos.z + 4, 8) - 4));

}

float XYTori(vec3 pt){
	mat4 R = mat4(
	 vec4(cos(PI / 2), sin(PI / 2), 0, 0),
	 vec4(-sin(PI / 2), cos(PI / 2), 0, 0),
	 vec4(0, 0, 1, 0),
	 vec4(0, 0, 0, 1));
	 // Translate to (3, 3, 3)
	 mat4 T = mat4(
	 vec4(1, 0, 0, 0),
	 vec4(0, 1, 0, 0),
	 vec4(0, 0, 1, 0),
	 vec4(0, 0, 0, 1));

	 vec3 pos = (vec4(pt, 1) * inverse(R*T)).xyz;
	 return torus(vec3(pos.x, mod(pos.y + 4, 8) - 4, mod(pos.z + 4, 8) - 4));
}

float ZYTori(vec3 pt){
	mat4 R = mat4(
	vec4(1, 0, 0, 0),
	 vec4(0, cos(PI / 2), sin(PI / 2), 0),
	 vec4(0, -sin(PI / 2), cos(PI / 2), 0),
	 vec4(0, 0, 0, 1));
	 // Translate to (3, 3, 3)
	 mat4 T = mat4(
	 vec4(1, 0, 0, 4),
	 vec4(0, 1, 0, 0),
	 vec4(0, 0, 1, 4s),
	 vec4(0, 0, 0, 1));

	 vec3 pos = (vec4(pt, 1) * inverse(R*T)).xyz;
	 return torus(vec3(mod(pos.x + 4, 8) - 4, mod(pos.y + 4, 8) - 4, pos.z));
}


float planelessScene(vec3 pt){

	float flatTorus = flatTori(pt);
	float XYTorus = XYTori(pt);
	float ZYTorus = ZYTori(pt);

	return min(min(flatTorus, XYTorus), ZYTorus);
}

float scene(vec3 pt){
	float objects = planelessScene(pt);

	float plane = plane(pt, vec3(0.0, -1.0, 0.0));

	return min(objects, plane);
}



vec3 getNormal(vec3 pt) {
  return normalize(GRADIENT(pt, scene));
}

vec3 getColor(vec3 pt) {
	if (abs(plane(pt, vec3(0.0, -1.0, 0.0))) < CLOSE_ENOUGH){
		float d = planelessScene(pt);
		float mixValue = d;
		vec3 color = vec3(0);
		vec3 stripe = mix(vec3(0.4, 1, 0.4), vec3(0.4, 0.4, 1), mixValue - int(mixValue));
		if (mod(int(d) + 1, 5) == 0 && d - int(d) > 0.75 && d > 1){
			return color;
		}
		return color + stripe;
	}else{
		  return vec3(1);
	}

}

///////////////////////////////////////////////////////////////////////////////
float shadow(vec3 pt, vec3 lightPos) {
	vec3 lightDir = normalize(lightPos - pt);
	float kd = 1;
	int step = 0;
	for (float t = 0.1; t < length(lightPos - pt) && step < RENDER_DEPTH && kd > 0.001; ) {
		float d = abs(scene(pt + t * lightDir));
		if (d < 0.001) {
			kd = 0;
		} else {
			kd = min(kd, 16 * d / t);
		}
		t += d;
		step++;
	}
	return kd;
}



float shade(vec3 eye, vec3 pt, vec3 n) {
  float val = 0;
  
  val += 0.1;  // Ambient
  vec3 v = normalize(eye - pt);
  for (int i = 0; i < LIGHT_POS.length(); i++) {
    vec3 l = normalize(LIGHT_POS[i] - pt);


    val += shadow(pt, LIGHT_POS[i]) * max(dot(n, l), 0);
    if (dot(n, l) > 0) {
    	vec3 r = normalize(reflect(-l, normalize(n)));
    	 val += shadow(pt, LIGHT_POS[i]) *max(pow(dot(v, r), 256), 0);
    }

  }
  return val;
}



vec3 illuminate(vec3 camPos, vec3 rayDir, vec3 pt) {
  vec3 c, n;
  n = getNormal(pt);
  c = getColor(pt);
  return shade(camPos, pt, n) * c;
}

///////////////////////////////////////////////////////////////////////////////

vec3 raymarch(vec3 camPos, vec3 rayDir) {
  int step = 0;
  float t = 0;

  for (float d = 1000; step < RENDER_DEPTH && abs(d) > CLOSE_ENOUGH; t += abs(d)) {
	  d = scene(camPos + t * rayDir);
    step++;
  }

  if (step == RENDER_DEPTH) {
    return getBackground(rayDir);
  } else if (showStepDepth) {
    return vec3(float(step) / RENDER_DEPTH);
  } else {
    return illuminate(camPos, rayDir, camPos + t * rayDir);
  }
}

///////////////////////////////////////////////////////////////////////////////

void main() {
  color = raymarch(camPos, getRayDir());
}
