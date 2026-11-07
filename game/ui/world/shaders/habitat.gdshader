shader_type spatial;
render_mode unshaded, cull_disabled;
// 궤도 도시(L5 아일랜드)의 회전 원통 — 모형 좌표는 반지름 단위, 축은 x, 축 가운데 hub (바닥 = hub 아래 1)
// part 0: 원통 안벽 (땅 셋·창 셋이 번갈아 길게), 1: 끝 마개 (가장자리 산), 2: 차폐 껍질 (레골리스)
// 바깥에서 보면 가까운 쪽 벽은 그리지 않는다 — 먼 쪽 안벽만 남아 단면 그림처럼 안이 보인다.
// 햇빛은 거울이 창으로 늘 들인다: 땅은 그림자 없이 고르게 밝고, 먼 곳일수록 안의 공기로 옅게 푸르다.

uniform vec3 cam_local = vec3(0.0, 0.0, 8.0);    // 카메라 (모형 좌표)
uniform int part = 0;
uniform float grow = 1.0;                         // 짓는 몫 — x가 −half_len에서 +half_len으로 자란다
uniform float half_len = 2.5;
uniform vec3 hub = vec3(0.0, 0.0, 2.0);
uniform float green = 1.0;                        // 땅의 푸르름 (0 = 막 깐 흙, 1 = 마을과 숲)
uniform vec4 city = vec4(0.0);                    // 도시 자리: x 반길이, 가로 각 반폭(라디안), 켬

varying vec3 p;

float hash(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	p = VERTEX;
}

vec3 land(vec2 q, float th) {
	// q = (x, 둘레 거리) 반지름 단위. 밭 (길쭉한 조각) · 숲 · 마을 · 강
	vec2 cell = floor(q * vec2(9.0, 14.0));
	float h = hash(cell);
	vec3 soil = vec3(0.47, 0.38, 0.27);
	vec3 field = mix(vec3(0.36, 0.52, 0.25), vec3(0.62, 0.6, 0.3), h);
	vec3 forest = vec3(0.18, 0.34, 0.17);
	float n = noise(q * 6.0) * 0.6 + noise(q * 23.0) * 0.4;
	vec3 c = mix(field, forest, smoothstep(0.58, 0.72, n));
	// 밭 사이 둑
	vec2 g = fract(q * vec2(9.0, 14.0));
	float edge = smoothstep(0.0, 0.05, g.x) * smoothstep(0.0, 0.05, g.y) * smoothstep(1.0, 0.95, g.x) * smoothstep(1.0, 0.95, g.y);
	c *= mix(0.82, 1.0, edge);
	// 마을: 작은 지붕 무리 (밭 사이에 드문드문)
	float town = step(0.975, hash(floor(q * vec2(70.0, 104.0)) + 7.0)) * step(0.55, noise(q * 3.0));
	c = mix(c, vec3(0.74, 0.7, 0.64), town * 0.7);
	// 강: 땅 가운데를 굽이치며 길게
	float river = abs(fract(th / 1.0471976) - 0.5 + 0.06 * sin(q.x * 3.1) + 0.03 * sin(q.x * 9.7));
	c = mix(c, vec3(0.24, 0.42, 0.58), smoothstep(0.012, 0.004, river));
	return mix(soil, c, green);
}

void fragment() {
	vec3 n_in;
	if (part == 1) {
		n_in = vec3(-sign(p.x), 0.0, 0.0);
	} else {
		n_in = normalize(vec3(0.0, hub.y - p.y, hub.z - p.z));
	}
	vec3 to_cam = cam_local - p;
	if (dot(n_in, to_cam) < 0.0) {
		discard;                      // 카메라 쪽 벽 (바깥에서 보면 가까운 반) — 먼 쪽 안벽만 남는다
	}
	if (part != 1 && (p.x + half_len) / (2.0 * half_len) > grow) {
		discard;
	}
	float th = atan(p.z - hub.z, p.y - hub.y);            // 바닥 = −π/2
	float u = (th + 1.5707963) / 1.0471976;               // 60°마다 한 띠 (바닥 띠 가운데 0)
	vec3 col;
	if (part == 2) {
		float n = noise(vec2(p.x * 8.0, th * 20.0)) * 0.5 + noise(vec2(p.x * 40.0, th * 90.0)) * 0.5;
		col = vec3(0.42, 0.41, 0.39) * (0.7 + 0.4 * n);
		// 다진 레골리스 판의 이음매
		vec2 g = fract(vec2(p.x * 6.0, th * 9.5493));
		col *= mix(0.75, 1.0, smoothstep(0.0, 0.04, g.x) * smoothstep(0.0, 0.04, g.y));
	} else if (part == 1) {
		float r = length(p.yz - hub.yz);
		float a = atan(p.z - hub.z, p.y - hub.y);
		float m = noise(vec2(a * 12.0, r * 9.0));
		vec3 rock = mix(vec3(0.5, 0.47, 0.43), vec3(0.72, 0.7, 0.66), m);
		col = mix(vec3(0.3, 0.42, 0.26) * (0.8 + 0.3 * m), rock, smoothstep(0.55, 0.85, r));   // 가장자리는 산
		col = mix(col, vec3(0.25, 0.27, 0.3), smoothstep(0.12, 0.08, r));                    // 가운데 축
		col = mix(col * 0.75, col, green);
	} else {
		float band = mod(u + 0.5, 2.0);
		if (band < 1.0) {
			vec2 q = vec2(p.x, th);
			col = land(q, th);
			// 도시 자리: 밭 대신 깎은 잔디 (가장자리는 부드럽게)
			if (city.z > 0.5) {
				float dx = abs(p.x) / max(city.x, 1e-4);
				float dy = abs(th + 1.5707963) / max(city.y, 1e-4);
				float inside = 1.0 - smoothstep(0.6, 1.0, length(vec2(dx, dy)));
				vec3 lawn = mix(vec3(0.42, 0.55, 0.33), vec3(0.5, 0.58, 0.38), noise(q * 60.0));
				col = mix(col, lawn, inside);
			}
			// 창 쪽 가장자리는 조금 어둡게
			col *= 0.82 + 0.18 * smoothstep(0.0, 0.25, min(band, 1.0 - band));
		} else {
			// 창: 짙은 유리와 창살 — 거울이 비춘 해가 줄무늬로
			float b2 = band - 1.0;
			vec3 glass = mix(vec3(0.02, 0.03, 0.06), vec3(0.08, 0.12, 0.2), b2);
			float mull = step(0.965, fract(p.x * 6.0)) + step(0.95, fract(b2 * 4.0));
			col = mix(glass, vec3(0.4, 0.43, 0.47), clamp(mull, 0.0, 1.0) * 0.45);
			col += vec3(1.0, 0.95, 0.8) * 0.18 * smoothstep(0.42, 0.5, b2) * smoothstep(0.58, 0.5, b2);
		}
	}
	// 안의 공기: 먼 벽은 옅게 푸르다 (지름만큼까지)
	if (part != 2) {
		float d = min(length(to_cam), 2.2);
		col = mix(col, vec3(0.74, 0.8, 0.88), (1.0 - exp(-d * 0.42)) * 0.62);
	}
	ALBEDO = col;
}
