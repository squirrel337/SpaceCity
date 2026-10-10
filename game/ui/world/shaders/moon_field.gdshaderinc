// 달 전체의 높이·밝기 (구 굽기와 지형 조각 굽기가 함께 쓴다 — 시작할 때 한 번 GPU로 굽는다)
// 바다(낮은 평원), 큰 크레이터, 빛줄기, 남극 크레이터(moon_surface), 여러 겹의 작은 크레이터 무늬
uniform int octaves = 5;
uniform vec4 mar_c[48];            // 바다: 중심 방향, 반지름(라디안)
uniform vec4 mar_p[48];            // x: 어두움, y: 깊이 km
uniform int mar_n = 0;
uniform vec4 big_c[16];            // 큰 크레이터: 중심 방향, 반지름 km
uniform vec4 big_p[16];            // x: 깊이 km, y: 테두리 km, z: 바닥 비율, w: 젊음(밝은 분출물)
uniform int big_n = 0;
uniform vec4 ray_c[8];             // 빛줄기 크레이터: 중심 방향, 반지름(라디안)
uniform vec4 ray_p[8];             // x: 밝기, y: 빛줄기 길이(라디안)
uniform int ray_n = 0;

vec3 face_dir(int f, vec2 uv) {
	float s = uv.x * 2.0 - 1.0;
	float t = uv.y * 2.0 - 1.0;
	if (f == 0) return normalize(vec3(1.0, -t, -s));
	if (f == 1) return normalize(vec3(-1.0, -t, s));
	if (f == 2) return normalize(vec3(s, 1.0, t));
	if (f == 3) return normalize(vec3(s, -1.0, -t));
	if (f == 4) return normalize(vec3(s, -t, 1.0));
	return normalize(vec3(-s, -t, -1.0));
}

float ang(vec3 a, vec3 b) {
	float c = length(a - b);
	return 2.0 * asin(clamp(c * 0.5, 0.0, 1.0));
}

uniform vec3 keep_dir = vec3(0.0, 0.0, -1.0);   // 기지 둘레: 무늬 크레이터를 두지 않는다
uniform float keep_km = 0.0;

// 작은 크레이터 무늬 (칸마다 하나씩, 여러 크기). fresh: 젊은 크레이터의 밝은 분출물
float crater_field(vec3 d, out float fresh) {
	float h = 0.0;
	fresh = 0.0;
	float f = 7.0;
	for (int o = 0; o < 6; o++) {
		if (o >= octaves) {
			break;
		}
		vec3 p = d * f;
		vec3 ip = floor(p);
		for (int z = -1; z <= 1; z++) {
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec3 cell = ip + vec3(float(x), float(y), float(z));
					vec4 r = hash4(cell, float(o) * 31.0 + 7.0);
					if (r.w > 0.6) {
						continue;
					}
					vec3 c = cell + r.xyz;
					// 영향 반지름(3 × rad)이 한 칸을 넘지 않아야 이웃 칸만 보고도 끊김이 없다
					float rad = 0.12 + 0.2 * r.w / 0.6;
					float dist = length(p - c);
					if (dist > rad * 3.0) {
						continue;
					}
					float rkm = rad / f * MOON_R;
					if (keep_km > 0.0 && length(normalize(c) - keep_dir) * MOON_R < rkm * 2.2 + keep_km) {
						continue;
					}
					float q = dist / rad;
					float depth = rkm * 0.32;
					float rim = rkm * 0.06;
					float inner = q < 1.0 ? (q * q - 1.0) * depth : 0.0;
					float rimf = q < 1.0 ? pow(q, 6.0) : 1.0 / (q * q * q);
					h += inner + rim * rimf * (1.0 - smoothstep(2.0, 3.0, q));
					float young = smoothstep(0.85, 0.97, hash1(cell, float(o) * 17.0 + 3.0));
					fresh += young * exp(-q * q * 0.7) * 0.8 + young * 0.25 * smoothstep(1.0, 0.6, q);
				}
			}
		}
		f *= 2.0;
	}
	return h;
}

float maria_mask(vec3 d) {
	float m = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= mar_n) {
			break;
		}
		float r = mar_c[i].w;
		float th = ang(d, mar_c[i].xyz);
		if (th > r * 1.4) {
			continue;
		}
		float wob = (fbm(d * 7.0 + vec3(float(i) * 1.7), 4, 11.0) - 0.5) * 0.9 * r
			+ (fbm(d * 23.0 + vec3(float(i)), 3, 13.0) - 0.5) * 0.25 * r;
		m = max(m, (1.0 - smoothstep(r * 0.62, r * 1.02, th + wob)) * mar_p[i].x);
	}
	return clamp(m, 0.0, 1.0);
}

float big_height(vec3 d, out float fresh) {
	float h = 0.0;
	fresh = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= big_n) {
			break;
		}
		float rho = length(d - big_c[i].xyz) * MOON_R;
		float R = big_c[i].w;
		if (rho > R * 4.0) {
			continue;
		}
		h += crater_shape(rho, R, big_p[i].x, big_p[i].y, big_p[i].z);
		fresh += big_p[i].w * exp(-pow(rho / (R * 1.8), 2.0)) * 0.5;
	}
	return h;
}

float height(vec3 d, out float fresh, out float mare) {
	float f1;
	float f2;
	mare = maria_mask(d);
	float h = -1.4 * mare + polar_height(d) + big_height(d, f1) + crater_field(d, f2) * (1.0 - 0.55 * mare);
	h += (fbm(d * 5.0, 4, 2.0) - 0.5) * 2.2 * (1.0 - mare);
	fresh = f1 + f2;
	return h;
}

float albedo(vec3 d, float fresh, float mare) {
	float a = 0.60 + 0.10 * (fbm(d * 6.0, 4, 3.0) - 0.5) + 0.05 * (fbm(d * 40.0, 3, 8.0) - 0.5);
	a = mix(a, 0.30 + 0.06 * (fbm(d * 16.0, 3, 5.0) - 0.5), mare);
	a += fresh * 0.22;
	for (int i = 0; i < 8; i++) {
		if (i >= ray_n) {
			break;
		}
		vec3 c = ray_c[i].xyz;
		float rc = ray_c[i].w;
		float L = ray_p[i].y;
		float th = ang(d, c);
		if (th > L * 1.3) {
			continue;
		}
		vec3 t1 = normalize(cross(c, abs(c.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0)));
		vec3 t2 = cross(c, t1);
		float psi = atan(dot(d, t2), dot(d, t1));
		float rays = 0.0;
		for (int k = 0; k < 3; k++) {
			float fq = 7.0 + float(k) * 6.0;
			float jit = vnoise(vec3(cos(psi) * 3.0, sin(psi) * 3.0, th * 6.0 + float(k)), 4.0 + float(i)) * 2.0;
			rays += pow(max(0.0, sin(psi * fq + float(k) * 1.7 + jit)), 22.0);
		}
		float fall = exp(-max(th - rc * 2.0, 0.0) / (L * 0.32));
		float blanket = exp(-pow(th / (rc * 2.8), 2.0));
		a += ray_p[i].x * (0.24 * blanket + 0.2 * rays * fall * smoothstep(rc, rc * 2.2, th));
	}
	return clamp(a, 0.04, 1.0);
}

