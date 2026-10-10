// 행성·위성: 스스로 계산하는 빛 (태양 방향 sun_dir, Godot 축). 겉모습은 kind로 고른다.
// 메시는 단위 구: 메시 좌표 (x, y, z) = 몸체 고정 (x, z, -y) — 몸체 z가 북극.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform int kind = 0;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float spin_h = 0.0;
uniform vec4 col_a : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 col_b : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 col_c : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 atmo : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float seed = 1.0;
uniform float bright = 1.0;
uniform sampler2D land : filter_linear_mipmap, repeat_enable;
uniform bool has_land = false;
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

vec3 dir_ll(float lat_deg, float lon_deg) {
	float la = radians(lat_deg);
	float lo = radians(lon_deg);
	return vec3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la));
}

float blob(vec3 d, vec3 c, float r) {
	return 1.0 - smoothstep(r * 0.6, r, length(d - c));
}

float craters(vec3 d, float freq, float s) {
	// 값 잡음의 날카로운 골로 크레이터 테두리 느낌을 낸다 (싼 근사)
	float a = vnoise(d * freq, s);
	float b = vnoise(d * freq * 2.7, s + 5.0);
	return smoothstep(0.62, 0.9, a) * 0.6 + smoothstep(0.7, 0.95, b) * 0.4;
}

vec3 albedo(vec3 d) {
	float lat = asin(clamp(d.z, -1.0, 1.0));
	vec3 a = col_a.rgb;
	vec3 b = col_b.rgb;
	vec3 c = col_c.rgb;
	if (kind == 4 || kind == 5) {
		// 가스 행성: 위도 띠 + 소용돌이
		float warp = fbm(d * 3.0 + vec3(seed), 4, seed) - 0.5;
		float swirl = fbm(d * vec3(10.0, 10.0, 2.2) + vec3(seed * 2.0), 4, seed + 3.0) - 0.5;
		float y = lat + warp * 0.07 + swirl * 0.035;
		float bands = 0.5 + 0.5 * sin(y * (kind == 4 ? 15.0 : 11.0) + sin(y * 3.7) * 1.8);
		float fine = 0.5 + 0.5 * sin(y * 52.0 + warp * 5.0);
		vec3 col = mix(a, b, bands);
		col = mix(col, c, fine * 0.22);
		if (kind == 4) {
			vec3 grs = dir_ll(-22.0, 60.0);
			float e = length((d - grs) * vec3(1.0, 1.0, 2.1));
			col = mix(col, vec3(0.78, 0.40, 0.26), smoothstep(0.12, 0.06, e) * 0.85);
		}
		return col * (0.82 + 0.18 * (1.0 - abs(d.z)));
	}
	if (kind == 6 || kind == 7) {
		// 얼음 거인: 희미한 띠
		float n = fbm(d * vec3(6.0, 6.0, 1.6) + vec3(seed), 4, seed);
		float bands = 0.5 + 0.5 * sin(lat * 9.0 + n * 2.0);
		vec3 col = mix(a, b, bands * 0.35);
		if (kind == 7) {
			col = mix(col, c, smoothstep(0.66, 0.78, fbm(d * vec3(14.0, 14.0, 3.0), 3, seed + 4.0)) * 0.7);
			col = mix(col, b * 0.55, blob(d, dir_ll(-20.0, 140.0), 0.13) * 0.8);
		}
		return col * (0.9 + 0.12 * abs(d.z));
	}
	if (kind == 1) {
		// 금성: 두꺼운 구름의 Y자 무늬
		float sh = fbm(vec3(d.x * 3.0 + lat * 2.5, d.y * 3.0, d.z * 1.2) + vec3(spin_h * 0.002, 0.0, 0.0), 5, seed);
		return mix(a, b, smoothstep(0.35, 0.7, sh)) * (0.92 + 0.08 * cos(lat * 2.0));
	}
	if (kind == 2) {
		// 지구: 땅 지도(있으면) + 구름
		float lon = atan(d.y, d.x);
		vec2 uv = vec2(lon / 6.28318530718 + 0.5, 0.5 - lat / 3.14159265359);
		vec4 lm = has_land ? texture(land, uv) : vec4(smoothstep(0.52, 0.56, fbm(d * 2.5, 5, seed)), 0.0, 0.0, 1.0);
		float n = fbm(d * 9.0, 4, seed + 2.0);
		float n2 = fbm(d * 30.0, 3, seed + 6.0);
		// 해안선을 조금 흔들어 다각형 티를 줄인다
		float landm = smoothstep(0.35, 0.65, lm.r + (n2 - 0.5) * 0.35);
		// 위도대: 열대 숲 → 온대 숲·초원 → 북방 침엽수림 → 툰드라
		float al = abs(lat);
		vec3 tropic = mix(vec3(0.07, 0.20, 0.06), vec3(0.14, 0.27, 0.08), n);
		vec3 temperate = mix(vec3(0.16, 0.28, 0.10), vec3(0.36, 0.38, 0.20), smoothstep(0.4, 0.7, n));
		vec3 boreal = mix(vec3(0.08, 0.17, 0.09), vec3(0.16, 0.22, 0.12), n);
		vec3 tundra = mix(vec3(0.38, 0.36, 0.28), vec3(0.5, 0.48, 0.4), n2);
		vec3 ground = mix(tropic, temperate, smoothstep(0.3, 0.6, al));
		ground = mix(ground, boreal, smoothstep(0.85, 1.0, al));
		ground = mix(ground, tundra, smoothstep(1.08, 1.2, al));
		vec3 desert = mix(vec3(0.72, 0.58, 0.38), vec3(0.84, 0.72, 0.5), n2);
		float arid = smoothstep(0.25, 0.75, lm.b + (n - 0.5) * 0.35);
		ground = mix(ground, mix(vec3(0.5, 0.45, 0.3), desert, smoothstep(0.45, 0.85, lm.b)), arid);
		ground = mix(ground, vec3(0.94, 0.96, 0.98), max(lm.g, smoothstep(1.22, 1.3, abs(lat))));
		vec3 sea = vec3(0.03, 0.10, 0.24);
		vec3 col = mix(sea, ground, landm);
		float cl = fbm(d * vec3(4.0, 4.0, 6.0) + vec3(spin_h * 0.004, 0.0, 0.0), 5, seed + 9.0);
		cl = smoothstep(0.5, 0.75, cl + 0.12 * cos(lat * 6.0));
		return mix(col, vec3(0.95), cl * 0.85);
	}
	if (kind == 3) {
		// 화성: 녹슨 흙, 어두운 지대, 극관
		float n = fbm(d * 3.2, 5, seed);
		float dark = smoothstep(0.5, 0.62, n);
		dark = max(dark, blob(d, dir_ll(8.0, 69.0), 0.32) * 0.9);      // 시르티스 대평원
		dark = max(dark, blob(d, dir_ll(47.0, -30.0), 0.3) * 0.75);    // 아키달리아
		dark = max(dark, blob(d, dir_ll(-25.0, -55.0), 0.35) * 0.7);   // 에리트라에움
		dark = max(dark, blob(d, dir_ll(-20.0, 140.0), 0.35) * 0.65);  // 킴메리움
		float brightz = blob(d, dir_ll(-42.0, 70.0), 0.32);            // 헬라스
		vec3 col = mix(a, b, dark * 0.85);
		col = mix(col, c, brightz * 0.6);
		col *= 0.88 + 0.24 * fbm(d * 18.0, 3, seed + 1.0);
		float cap = smoothstep(1.28, 1.36, lat) + smoothstep(1.36, 1.44, -lat);
		return mix(col, vec3(0.94, 0.93, 0.92), clamp(cap, 0.0, 1.0));
	}
	if (kind == 8) {
		// 명왕성: 하트 모양 밝은 평원, 어두운 적도 띠
		float n = fbm(d * 4.0, 4, seed);
		vec3 col = mix(a, b, smoothstep(0.35, 0.05, abs(lat + 0.1)) * smoothstep(0.4, 0.6, n + 0.2));
		float heart = max(blob(d, dir_ll(25.0, 175.0), 0.42), blob(d, dir_ll(5.0, 160.0), 0.3));
		return mix(col, c, heart * 0.85);
	}
	if (kind == 9) {
		// 이오: 황 평원과 화산
		float n = fbm(d * 5.0, 4, seed);
		vec3 col = mix(a, b, smoothstep(0.45, 0.7, n));
		float spots = smoothstep(0.82, 0.9, vnoise(d * 11.0, seed + 3.0));
		return mix(col, c, spots);
	}
	if (kind == 10) {
		// 유로파: 얼음과 갈색 줄무늬
		float r1 = 1.0 - abs(vnoise(d * 7.0, seed) * 2.0 - 1.0);
		float r2 = 1.0 - abs(vnoise(d * 15.0, seed + 2.0) * 2.0 - 1.0);
		float lines = pow(r1, 14.0) + pow(r2, 18.0) * 0.7;
		vec3 col = mix(a, b, smoothstep(0.45, 0.75, fbm(d * 3.0, 3, seed + 5.0)) * 0.5);
		return mix(col, c, clamp(lines, 0.0, 1.0) * 0.8);
	}
	if (kind == 13) {
		// 타이탄: 주황 연무
		float n = fbm(d * vec3(3.0, 3.0, 1.2), 3, seed);
		return mix(a, b, 0.3 * n + 0.2 * smoothstep(0.6, 1.2, abs(lat)));
	}
	// 바위 위성·수성·가니메데·칼리스토·트리톤
	float n = fbm(d * 4.0, 5, seed);
	vec3 col = mix(a, b, smoothstep(0.35, 0.7, n));
	float cr = craters(d, kind == 12 ? 40.0 : 22.0, seed + 7.0);
	col = mix(col, c, cr * (kind == 12 ? 0.9 : 0.5));
	if (kind == 14) {
		col = mix(col, b, smoothstep(0.2, -0.3, lat) * 0.5);
	}
	return col;
}

void fragment() {
	vec3 o = normalize(obj);
	vec3 d = vec3(o.x, -o.z, o.y);
	vec3 alb = albedo(d) * bright;
	vec3 nw = normalize((MODEL_MATRIX * vec4(o, 0.0)).xyz);
	vec3 l = normalize(sun_dir);
	float ndl = dot(nw, l);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize(CAMERA_POSITION_WORLD - wp);
	float mu = clamp(dot(nw, v), 0.0, 1.0);
	float diff = max(ndl, 0.0);
	if (atmo.a > 0.0) {
		diff = mix(diff, smoothstep(-0.08, 0.45, ndl), 0.6);
	}
	if (kind == 4 || kind == 5 || kind == 6 || kind == 7) {
		diff *= 0.55 + 0.45 * pow(mu, 0.35);
	}
	vec3 col = alb * diff * 1.75 + alb * 0.008;
	if (kind == 2) {
		// 바다의 햇빛 반사와 밤의 도시 불빛
		float lon = atan(d.y, d.x);
		vec2 uv = vec2(lon / 6.28318530718 + 0.5, 0.5 - asin(clamp(d.z, -1.0, 1.0)) / 3.14159265359);
		float landm = has_land ? texture(land, uv).r : 0.0;
		vec3 h = normalize(l + v);
		col += vec3(1.0, 0.95, 0.85) * pow(max(dot(nw, h), 0.0), 60.0) * 0.6 * (1.0 - landm) * step(0.0, ndl);
		float city = landm * smoothstep(0.62, 0.8, fbm(d * 30.0, 3, 4.0)) * smoothstep(1.2, 0.5, abs(asin(clamp(d.z, -1.0, 1.0))));
		col += vec3(1.0, 0.72, 0.35) * city * smoothstep(0.05, -0.2, ndl) * 0.5;
	}
	if (atmo.a > 0.0) {
		float rim = pow(1.0 - mu, 2.6) * atmo.a * smoothstep(-0.3, 0.35, ndl);
		col += atmo.rgb * rim * 1.6;
	}
	ALBEDO = col;
}
