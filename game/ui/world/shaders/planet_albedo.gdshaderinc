// 행성·위성의 겉 색 (몸체 고정 단위 방향 d → 알베도) — 구운 지도가 없는 천체(가스 행성 등)와 굽기 전의 planet.gdshader가 쓴다.
// noise.gdshaderinc 다음에 넣는다. 지구(kind 2)는 earth_surface.gdshaderinc가 그린다.
uniform int kind = 0;
uniform float spin_h = 0.0;
uniform vec4 col_a : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform vec4 col_b : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 col_c : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float seed = 1.0;

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
