// 공용 잡음: 3차원 값 잡음, fbm, 정수 해시 (GLSL ES 3.0)

uvec4 pcg4(uvec4 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
	v ^= v >> 16u;
	v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
	return v;
}

// 격자 칸 c(정수 좌표) + 씨앗 s → 0~1 네 개
vec4 hash4(vec3 c, float s) {
	uvec4 v = uvec4(ivec4(ivec3(floor(c)), int(s)));
	return vec4(pcg4(v)) * (1.0 / 4294967295.0);
}

float hash1(vec3 c, float s) {
	return hash4(c, s).x;
}

float vnoise(vec3 p, float s) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = hash1(i, s);
	float b = hash1(i + vec3(1.0, 0.0, 0.0), s);
	float c = hash1(i + vec3(0.0, 1.0, 0.0), s);
	float d = hash1(i + vec3(1.0, 1.0, 0.0), s);
	float e = hash1(i + vec3(0.0, 0.0, 1.0), s);
	float f1 = hash1(i + vec3(1.0, 0.0, 1.0), s);
	float g = hash1(i + vec3(0.0, 1.0, 1.0), s);
	float h = hash1(i + vec3(1.0, 1.0, 1.0), s);
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, f1, u.x), mix(g, h, u.x), u.y), u.z);
}

float fbm(vec3 p, int oct, float s) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < oct; i++) {
		sum += vnoise(p, s + float(i) * 13.0) * amp;
		norm += amp;
		p = p * 2.03 + vec3(1.7, -3.1, 2.3);
		amp *= 0.5;
	}
	return sum / norm;
}
