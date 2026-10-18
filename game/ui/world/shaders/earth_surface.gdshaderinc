// 지구의 땅·바다 — Natural Earth 1:10m에서 만든 해안 거리 지도(tools/art/earth_coast.py)로 해안을 긋는다.
// 거리를 문턱으로 잘라 픽셀마다 또렷한 해안을 긋고, 지도 칸보다 잔 굴곡은 잡음으로 더한다 (표본 간격까지).
// 도시 가까이서는 그 부지의 고운 지역 지도(125 m 칸, 둘레 256 km)가 해안을 긋는다.
// 대도시(earth_cities.json) 둘레는 시가지: 지붕·포장의 회색, 가까이서는 블록 격자의 큰길·골목, 공원, 밤의 불빛.
// 대도시의 지형 조각은 강·공원을 넣은 시가지 지도(G = 공원)를 지역 지도로 쓴다.
// 구(planet.gdshader), 도시 둘레 지형 조각(body_patch), 조각 굽기(earth_patch_bake)가 같은 함수를 쓴다.
// noise.gdshaderinc 다음에 넣는다. 색은 sRGB (호환 렌더러는 ALBEDO를 sRGB로 받는다).

uniform sampler2D coast : filter_linear_mipmap, repeat_enable;        // 정거원통, 해안 거리 ±40 km
uniform bool has_coast = false;
uniform sampler2D coast_loc : filter_linear_mipmap, repeat_disable;   // 고른 지구 도시 둘레 (접평면, 위 = 북), ±8 km
uniform bool has_coast_loc = false;
uniform vec3 cl_c = vec3(1.0, 0.0, 0.0);
uniform vec3 cl_e = vec3(0.0, 1.0, 0.0);
uniform vec3 cl_n = vec3(0.0, 0.0, 1.0);
uniform float cl_half = 128.0;
uniform float cl_range = 8.0;                                         // 지역 지도의 거리 범위 (km) — 대도시 시가지 지도는 2
uniform sampler2D land : filter_linear_mipmap, repeat_enable;         // R 땅(옛 근사), G 얼음, B 메마른 땅
uniform bool has_land = false;
uniform vec4 ekeep[4];                                                // 기지 자리: 방향, 반지름 km (그 안은 땅)
uniform int ekeep_n = 0;
uniform vec4 metro[28];                                               // 대도시: 방향 xyz, 시가지 반지름 km
uniform vec4 metro_k[28];                                             // 대도시: 불빛 세기, 큰길 방향(rad), 블록(km), 0
uniform int metro_n = 0;
uniform bool cl_parks = false;                                        // 대도시 시가지 지도: G = 공원, B = 거리의 자투리

const float EARTH_R = 6371.0;
const float COAST_KM = 40.0;
const float COAST_LOC_KM = 8.0;

vec2 earth_uv(vec3 d) {
	return vec2(atan(d.y, d.x) / 6.28318530718 + 0.5, 0.5 - asin(clamp(d.z, -1.0, 1.0)) / 3.14159265359);
}

// 정규화하지 않은 fBm (±0.5 언저리), 겹 수가 소수여도 이어진다
float earth_fbm(vec3 p, float oct, float s) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 12; i++) {
		float w = clamp(oct - float(i), 0.0, 1.0);
		if (w <= 0.0) {
			break;
		}
		sum += (vnoise(p, s + float(i) * 13.0) - 0.5) * amp * w;
		p = p * 2.03 + vec3(1.7, -3.1, 2.3);
		amp *= 0.5;
	}
	return sum;
}

// 지역 지도 읽기. 대도시 시가지 지도를 가까이서 볼 때는 이웃 네 칸을 직접 섞는다 — 8비트 텍스처 거르기는
// 결과를 칸 값 단위로 반올림하기도 해서 (R + B 자투리로 읽는 거리가 어긋나) 물가 띠가 계단진다
vec4 earth_loc_texel(vec2 luv, float texel_km) {
	ivec2 sz = textureSize(coast_loc, 0);
	if (!cl_parks || texel_km > 2.0 * cl_half / float(sz.x)) {
		return texture(coast_loc, luv);
	}
	vec2 p = luv * vec2(sz) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = p - vec2(i);
	ivec2 hi = sz - 1;
	vec4 a = texelFetch(coast_loc, clamp(i, ivec2(0), hi), 0);
	vec4 b = texelFetch(coast_loc, clamp(i + ivec2(1, 0), ivec2(0), hi), 0);
	vec4 c = texelFetch(coast_loc, clamp(i + ivec2(0, 1), ivec2(0), hi), 0);
	vec4 e = texelFetch(coast_loc, clamp(i + ivec2(1, 1), ivec2(0), hi), 0);
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

// 지도에서 읽은 해안 거리 (km, 땅 +, 바다 −) — 잔 굴곡을 더하기 전. src_km: 그 지도의 칸 폭, texel_km: 표본 간격
float earth_sd_map(vec3 d, float texel_km, out float src_km, out float sd_glob) {
	vec2 uv = earth_uv(d);
	float sd;
	src_km = 9.8;
	if (has_coast) {
		sd = (texture(coast, uv).r - 0.5) * 2.0 * COAST_KM;
	} else if (has_land) {
		sd = (texture(land, uv).r - 0.5) * 60.0;
		src_km = 40.0;
	} else {
		sd = (fbm(d * 2.5, 5, 7.0) - 0.54) * 400.0;
		src_km = 200.0;
	}
	sd_glob = sd;
	if (has_coast_loc) {
		float w = dot(d, cl_c);
		if (w > 0.9) {
			vec2 q = vec2(dot(d, cl_e), dot(d, cl_n)) * EARTH_R / w;
			vec2 luv = vec2(0.5 + q.x / (2.0 * cl_half), 0.5 - q.y / (2.0 * cl_half));
			float m = max(abs(luv.x - 0.5), abs(luv.y - 0.5));
			if (m < 0.5) {
				vec4 lt = earth_loc_texel(luv, texel_km);
				// 대도시 시가지 지도: B = R의 자투리 (둘 다 선형이라 걸러 읽어도 맞다 — 물가 띠가 m 단위로 곧다)
				float sl = (lt.r + (cl_parks ? (lt.b - 0.5) / 255.0 : 0.0) - 0.5) * 2.0 * cl_range;
				// 지역 지도는 ±cl_range에서 끝난다 — 그 너머는 같은 쪽에서 전체 지도의 거리를 쓴다
				if (abs(sl) > cl_range * 0.95) {
					sl = sign(sl) * max(abs(sd), cl_range * 0.95);
				}
				float k = 1.0 - smoothstep(0.42, 0.49, m);
				sd = mix(sd, sl, k);
				src_km = mix(src_km, 0.125, k);
			}
		}
	}
	return sd;
}

// 잔 굴곡: 지도 칸 폭에서 시작해 표본 간격까지 (멀리서도 가까이서도 또렷하고 들쭉날쭉한 해안). 기지 자리는 땅
float earth_sd_fine(vec3 d, float sd, float src_km, float texel_km) {
	float oct = clamp(log2(src_km / max(texel_km, 1e-4)), 0.0, 11.0);
	sd += earth_fbm(d * (EARTH_R / (src_km * 3.0)), oct + 1.0, 61.0) * src_km * 0.9;
	for (int i = 0; i < 4; i++) {
		if (i >= ekeep_n) {
			break;
		}
		sd = max(sd, ekeep[i].w - length(d - ekeep[i].xyz) * EARTH_R);
	}
	return sd;
}

// 가장 가까운 해안까지의 거리 (km, 땅 +, 바다 −). texel_km: 표본(픽셀) 간격
float earth_sd(vec3 d, float texel_km) {
	float src_km;
	float sd_glob;
	float sd = earth_sd_map(d, texel_km, src_km, sd_glob);
	return earth_sd_fine(d, sd, src_km, texel_km);
}

// 땅의 색 (위도대·메마른 땅·얼음). sd: 해안 거리 km
vec3 earth_ground(vec3 d, float sd, float s) {
	float lat = asin(clamp(d.z, -1.0, 1.0));
	vec4 lm = has_land ? texture(land, earth_uv(d)) : vec4(1.0, 0.0, 0.0, 1.0);
	float n = fbm(d * 9.0, 4, s + 2.0);
	float n2 = fbm(d * 30.0, 3, s + 6.0);
	// 위도대: 열대 숲 → 온대 숲·초원 → 북방 침엽수림 → 툰드라
	float al = abs(lat);
	vec3 tropic = mix(vec3(0.10, 0.25, 0.08), vec3(0.18, 0.33, 0.11), n);
	vec3 temperate = mix(vec3(0.20, 0.33, 0.13), vec3(0.42, 0.44, 0.25), smoothstep(0.4, 0.7, n));
	vec3 boreal = mix(vec3(0.11, 0.21, 0.12), vec3(0.20, 0.27, 0.16), n);
	vec3 tundra = mix(vec3(0.42, 0.40, 0.32), vec3(0.55, 0.53, 0.45), n2);
	vec3 ground = mix(tropic, temperate, smoothstep(0.3, 0.6, al));
	ground = mix(ground, boreal, smoothstep(0.85, 1.0, al));
	ground = mix(ground, tundra, smoothstep(1.08, 1.2, al));
	vec3 desert = mix(vec3(0.74, 0.60, 0.40), vec3(0.86, 0.74, 0.53), n2);
	float arid = smoothstep(0.25, 0.75, lm.b + (n - 0.5) * 0.35);
	ground = mix(ground, mix(vec3(0.52, 0.47, 0.32), desert, smoothstep(0.45, 0.85, lm.b)), arid);
	// 해안 가까이는 모래·낮은 풀밭
	ground = mix(ground, vec3(0.62, 0.58, 0.44), (1.0 - smoothstep(0.0, 0.25, sd)) * 0.35 * (1.0 - lm.g));
	return mix(ground, vec3(0.94, 0.96, 0.98), max(lm.g, smoothstep(1.22, 1.3, abs(lat))));
}

// 바다의 색: 먼 바다는 짙은 남색, 대륙붕(해안 가까이)은 밝은 청록
vec3 earth_sea(float sd) {
	vec3 deep = vec3(0.04, 0.12, 0.30);
	vec3 shelf = vec3(0.07, 0.30, 0.40);
	return mix(deep, shelf, smoothstep(-14.0, -0.3, sd) * 0.75);
}

// 가장 가까운 대도시의 시가지 몫 (0~1)과 그 번호 — 가장자리는 잡음으로 들쭉날쭉
float earth_urban(vec3 d, out int which) {
	float u = 0.0;
	which = -1;
	for (int i = 0; i < 28; i++) {
		if (i >= metro_n) {
			break;
		}
		float r = metro[i].w;
		float dk = length(d - metro[i].xyz) * EARTH_R;
		if (dk > r * 1.5) {
			continue;
		}
		float edge = r * (0.92 + 0.55 * (vnoise(d * (EARTH_R / 6.0), 41.0 + float(i)) - 0.5)
			+ 0.25 * (vnoise(d * (EARTH_R / 1.5), 43.0 + float(i)) - 0.5));
		float v = 1.0 - smoothstep(edge * 0.5, edge, dk);
		if (v > u) {
			u = v;
			which = i;
		}
	}
	return u;
}

// 이 방향이 부지 둘레의 고운 지역 지도 안인가 (0~1 — 가장자리에서 전체 지도로 넘어간다)
float earth_loc_k(vec3 d) {
	if (!has_coast_loc) {
		return 0.0;
	}
	float w = dot(d, cl_c);
	if (w < 0.9) {
		return 0.0;
	}
	vec2 q = vec2(dot(d, cl_e), dot(d, cl_n)) * EARTH_R / w;
	vec2 luv = vec2(0.5 + q.x / (2.0 * cl_half), 0.5 - q.y / (2.0 * cl_half));
	return 1.0 - smoothstep(0.42, 0.49, max(abs(luv.x - 0.5), abs(luv.y - 0.5)));
}

// 지역 지도의 공원 (대도시 시가지 지도의 G)
float earth_park(vec3 d) {
	if (!has_coast_loc || !cl_parks) {
		return 0.0;
	}
	float w = dot(d, cl_c);
	if (w < 0.9) {
		return 0.0;
	}
	vec2 q = vec2(dot(d, cl_e), dot(d, cl_n)) * EARTH_R / w;
	vec2 luv = vec2(0.5 + q.x / (2.0 * cl_half), 0.5 - q.y / (2.0 * cl_half));
	if (max(abs(luv.x - 0.5), abs(luv.y - 0.5)) > 0.49) {
		return 0.0;
	}
	return texture(coast_loc, luv).g;
}

// 안티에일리어싱한 선: 가운데에서 dist, 반폭 hw, 픽셀 폭 aa (같은 단위). 픽셀보다 가늘면 덮는 몫만큼 흐리게
float earth_line(float dist, float hw, float aa) {
	return min(hw * 2.0 / max(aa, 1e-6), 1.0) * (1.0 - smoothstep(hw, hw + aa, dist));
}

// x가 a~b 안인 몫 (가장자리를 w만큼 부드럽게)
float earth_band(float x, float a, float b, float w) {
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

// 바다 쪽 물가의 모양 (대도시): 곳에 따라 모래사장·부두, 나머지 바다와 강·운하는 호안과 강변 공원.
// sea: 바다 해안의 몫 (전체 지도에도 해안이 가까우면 바다 — 강·운하는 0)
void earth_shore_kind(vec3 d, float sea, out float beach, out float quay) {
	beach = sea * smoothstep(0.45, 0.6, vnoise(d * (EARTH_R / 2.5), 81.0));
	quay = sea * (1.0 - beach) * smoothstep(0.5, 0.62, vnoise(d * (EARTH_R / 1.8), 82.0));
}

// 시가지의 물가 띠 (물에서 땅 쪽으로, m): 호안 5 · 강변 공원 22~56 (곳에 따라 광장) · 덤불 3 ·
// 강변 도로 24 (왕복 6차로, 가운데 분리대) · 보도와 가로수 8. 바다 쪽은 공원 자리가 모래사장이나 부두가 되기도 한다.
// 3D 건물은 그 너머(metro_city.gd의 SHORE_M)에 선다
const float WF_REV = 5.0;
const float WF_ROAD = 24.0;
const float WF_VERGE = 8.0;

// earth_city의 본체. u0·which: earth_urban의 값. bank: 대도시 지도 안 (0~1) — 물가를 다듬는다 (sea: 바다 해안 몫):
// 시가지는 호안·강변 공원·강변 도로·가로수의 띠, 시가지 밖은 모래·자갈. 가까이서는 차선·횡단보도·보도·골목,
// 공원은 숲 가장자리처럼 흔들린 경계 안에 잔디·숲·산책로
vec3 earth_city_u(vec3 d, vec3 col, float sd, float texel_km, float u0, int which, float bank, float sea, out float lights) {
	lights = 0.0;
	float aa = max(texel_km, 1e-4);
	float aam = aa * 1000.0;
	float em = sd * 1000.0;                                          // 물가에서 (m, 땅 +)
	float bvis = bank * (1.0 - smoothstep(0.02, 0.06, aa));
	if (bvis > 0.0) {
		// 시가지 밖의 물가: 좁은 모래·자갈
		float nat = bvis * (1.0 - smoothstep(0.1, 0.5, u0));
		col = mix(col, vec3(0.55, 0.52, 0.42), nat * (1.0 - smoothstep(4.0, 14.0 + aam, em)) * 0.8);
	}
	if (u0 <= 0.0 || which < 0) {
		return col;
	}
	float u = u0 * smoothstep(-0.02, 0.05, sd);
	vec4 mk = metro_k[which];
	vec3 c = metro[which].xyz;
	vec3 e = normalize(vec3(-c.y, c.x, 0.0) + vec3(1e-7, 0.0, 0.0));
	vec3 n = cross(c, e);
	vec2 q = vec2(dot(d - c, e), dot(d - c, n)) * EARTH_R;           // 도심에서 동·북 (km)
	vec2 uu = vec2(sin(mk.y), cos(mk.y));
	vec2 vv = vec2(cos(mk.y), -sin(mk.y));
	float bk = max(mk.z, 0.02);
	vec2 g = vec2(dot(q, vv), dot(q, uu)) / bk;                       // 블록 단위 (길은 정수 자리)
	float vis = 1.0 - smoothstep(bk * 0.12, bk * 0.5, aa);           // 블록이 화면에서 작으면 무늬는 평균으로
	float near = 1.0 - smoothstep(0.0015, 0.005, aa);                // 차선·횡단보도·골목이 보이는 거리
	vec2 cell = floor(g);
	vec2 fr = g - cell;
	// 공원: 지도의 가장자리를 잡음으로 흔들어 숲 가장자리처럼 (픽셀 폭만큼 부드럽게)
	float park = earth_park(d);
	if (park > 0.0 && park < 1.0) {
		float mt = 2.0 * cl_half / float(textureSize(coast_loc, 0).x);    // 지도 한 칸 (km)
		float soft = clamp(aa / mt, 0.03, 0.5);
		float wob = vnoise(vec3(q / 0.09, 1.5), 97.0) * 0.65 + vnoise(vec3(q / 0.03, 2.5), 98.0) * 0.35;
		park = smoothstep(0.5 - soft, 0.5 + soft, park + (wob - 0.5) * 0.8);
	}
	// 지붕: 블록마다 3~6줄의 필지, 필지마다 가장자리에서 들어앉은 건물 지붕 (회색 콘크리트에 따뜻한·찬 기운,
	// 드물게 짙은·붉은 지붕), 둘레는 포장한 마당이나 풀. 필지가 화면에서 작으면 평균 색으로
	vec4 hb = hash4(vec3(cell, 7.0), 31.0);
	vec2 nl = vec2(3.0) + floor(hb.xy * 3.99);
	vec2 lot = floor(fr * nl);
	vec4 hl = hash4(vec3(cell * 8.0 + lot, 9.0), 37.0);
	vec3 roof = vec3(0.40 + 0.2 * hl.x) * mix(vec3(0.96, 0.99, 1.03), vec3(1.04, 1.0, 0.94), hl.y);
	roof = mix(roof, vec3(0.31, 0.31, 0.33), step(0.9, hl.z));
	roof = mix(roof, vec3(0.50, 0.41, 0.36), step(0.97, hl.w));
	vec2 lsz = bk * 1000.0 / nl;                                     // 필지 크기 (m)
	vec2 dm = min(fract(fr * nl), 1.0 - fract(fr * nl)) * lsz;        // 필지 가장자리까지 (m)
	float ins = 2.0 + 5.0 * hl.z;
	float bld = smoothstep(ins - aam * 0.5, ins + aam * 0.5, min(dm.x, dm.y));
	vec3 yard = mix(vec3(0.47, 0.47, 0.45), vec3(0.33, 0.39, 0.26), step(0.72, hl.w) * 0.8);
	vec3 lotc = mix(yard, roof, bld);
	float lvis = 1.0 - smoothstep(min(lsz.x, lsz.y) * 0.0002, min(lsz.x, lsz.y) * 0.0006, aa);
	roof = mix(vec3(0.46, 0.46, 0.44), lotc, lvis * vis);
	// 골목 (블록마다) · 큰길 (다섯 블록마다, 반폭 15 m) — 축마다
	vec2 f = abs(fract(g + 0.5) - 0.5) * bk;
	vec2 big = abs(fract(g / 5.0 + 0.5) - 0.5) * bk * 5.0;
	vec2 st2 = 1.0 - smoothstep(vec2(0.006 - aa * 0.5), vec2(0.006 + aa * 0.5), f);
	vec2 av2 = 1.0 - smoothstep(vec2(0.015 - aa * 0.5), vec2(0.015 + aa * 0.5), big);
	float street = max(st2.x, st2.y);
	float avenue = max(av2.x, av2.y);
	// 블록 안의 좁은 길 (절반쯤의 블록, 가까이서만)
	vec4 hc = hash4(vec3(cell, 5.0), 23.0);
	float alley = 0.0;
	if (near > 0.0) {
		float am = (hc.x < 0.5 ? abs(fr.x - 0.5) : abs(fr.y - 0.5)) * bk * 1000.0;
		alley = earth_line(am, 1.8, aam) * step(hc.y, 0.55) * near * (1.0 - park);
	}
	// 물가 띠 (시가지): 격자의 길은 강변 도로에서 끝난다
	float wk = bvis * smoothstep(0.1, 0.5, u0);
	float pw = 22.0 + 34.0 * vnoise(vec3(q / 1.6, 0.5), 77.0);       // 강변 공원 폭 (m)
	float e2 = WF_REV + pw;
	float e3 = e2 + 3.0;
	float e4 = e3 + WF_ROAD;
	float e5 = e4 + WF_VERGE;
	float past = mix(1.0, smoothstep(e4 - 0.5 - aam * 0.5, e4 + 0.5 + aam * 0.5, em), wk);
	float road = max(max(street * 0.8, avenue), alley * 0.7) * vis * past;
	// 길 바닥: 큰길은 짙게, 가까이서는 보도·차선·횡단보도
	vec3 asph = mix(vec3(0.24, 0.24, 0.25), vec3(0.18, 0.18, 0.19), avenue);
	if (near > 0.0) {
		bool on_x = big.x < big.y;                                    // 어느 축의 큰길인가
		float da = min(big.x, big.y) * 1000.0;                        // 큰길 가운데에서 (m)
		float other = max(big.x, big.y) * 1000.0;
		float along = (on_x ? g.y : g.x) * bk * 1000.0;
		float boul = step(0.5, mod(floor((on_x ? g.x : g.y) / 5.0 + 0.5), 2.0));   // 하나 걸러 가운데 화단
		vec3 mark = vec3(0.82, 0.82, 0.78);
		vec3 m = asph;
		m = mix(m, vec3(0.86, 0.70, 0.26), earth_line(abs(da - 0.3), 0.12, aam) * (1.0 - boul));
		m = mix(m, vec3(0.22, 0.33, 0.16), (1.0 - smoothstep(2.0, 2.0 + aam, da)) * boul);
		float lane = earth_line(abs(fract(da / 3.4 + 0.5) - 0.5) * 3.4, 0.09, aam) * step(2.6, da) * step(da, 11.0)
			* step(0.45, fract(along / 10.0));
		m = mix(m, mark, lane * 0.8);
		m = mix(m, mark, earth_line(abs(da - 12.4), 0.1, aam));
		m = mix(m, vec3(0.55, 0.54, 0.50), smoothstep(13.0, 13.4 + aam, da));     // 보도
		// 횡단보도: 건너는 큰길의 가장자리 바로 밖
		float zebra = earth_band(other, 15.5, 19.5, aam * 0.5) * step(0.5, fract(da / 1.1)) * step(da, 12.0);
		m = mix(m, mark, zebra * 0.85);
		// 골목: 가운데 점선, 가장자리 보도
		float sd2 = min(f.x, f.y) * 1000.0;
		float s_along = (f.x < f.y ? g.y : g.x) * bk * 1000.0;
		vec3 sm = mix(vec3(0.24, 0.24, 0.25), mark, earth_line(sd2, 0.08, aam) * step(0.5, fract(s_along / 8.0)) * 0.7);
		sm = mix(sm, vec3(0.55, 0.54, 0.50), smoothstep(4.6, 5.0 + aam, sd2));
		asph = mix(asph, mix(sm, m, avenue), near);
	}
	vec3 urb = mix(roof, asph, road);
	urb = mix(urb, vec3(0.30, 0.31, 0.30), (1.0 - vis) * 0.3);
	float k = u * (1.0 - park);
	vec3 out_c = mix(col, urb, k * 0.9);
	// 공원: 잔디와 숲, 구불구불한 산책로
	float pn = vnoise(vec3(q / 0.04, 0.5), 91.0) * 0.6 + vnoise(vec3(q / 0.012, 0.5), 93.0) * 0.4;
	vec3 pcol = mix(vec3(0.27, 0.40, 0.17), vec3(0.12, 0.23, 0.09), smoothstep(0.42, 0.6, pn));
	pcol = mix(vec3(0.17, 0.30, 0.13), pcol, vis);
	float trail = earth_line(abs(vnoise(vec3(q / 0.3, 0.5), 95.0) - 0.5) * 160.0, 1.2, aam) * near;
	pcol = mix(pcol, vec3(0.62, 0.58, 0.48), trail * 0.8);
	out_c = mix(out_c, mix(col, pcol, 0.85), park * u);
	// 밤 불빛: 가까이서는 길을 따라, 멀리서는 시가지 전체가 (도심일수록 밝게)
	float core = 1.0 - smoothstep(0.0, metro[which].w * 0.7, length(q));
	float glow = mix(0.5 + 0.35 * vnoise(d * (EARTH_R / 0.9), 9.0), 0.25 + 1.1 * road, vis);
	lights = k * mk.x * glow * (0.55 + 0.45 * core);
	if (wk > 0.0 && em < e5 + aam + 1.0) {
		float n1 = vnoise(vec3(q / 0.03, 0.5), 87.0);
		float n2 = vnoise(vec3(q / 0.011, 0.5), 89.0);
		float aw = aam * 0.5 + 0.3;
		// 강변 공원: 잔디·나무숲, 자전거길과 물가 산책길. 곳에 따라 포장한 광장
		vec3 lawn = mix(vec3(0.30, 0.42, 0.19), vec3(0.38, 0.47, 0.24), n2);
		float trees = smoothstep(0.52, 0.64, n1 * 0.7 + n2 * 0.3);
		vec3 bc = mix(lawn, vec3(0.15, 0.25, 0.11), trees);
		float plaza = smoothstep(0.66, 0.74, vnoise(vec3(q / 0.9, 0.5), 79.0));
		bc = mix(bc, mix(vec3(0.60, 0.58, 0.53), vec3(0.18, 0.28, 0.12), trees * 0.6), plaza);
		bc = mix(bc, vec3(0.50, 0.36, 0.32), earth_line(abs(em - (WF_REV + pw * 0.42)), 1.5, aam) * (1.0 - plaza));
		bc = mix(bc, vec3(0.66, 0.64, 0.58), earth_line(abs(em - (WF_REV + 2.5)), 1.1, aam));
		// 호안: 콘크리트 블록, 물에 닿는 곳은 젖어 어둡다
		vec3 rev = mix(vec3(0.33, 0.33, 0.31), vec3(0.58, 0.57, 0.53), smoothstep(0.5, 2.0, em));
		bc = mix(rev, bc, smoothstep(WF_REV - aw, WF_REV + aw, em));
		// 바다 쪽: 모래사장 (젖은 모래 → 마른 모래, 끝에 해변 산책로) · 부두 (콘크리트 안벽, 물가에 노란 선)
		float beach;
		float quay;
		earth_shore_kind(d, sea, beach, quay);
		float front = 1.0 - smoothstep(e2 - aw, e2 + aw, em);
		vec3 sand = mix(vec3(0.60, 0.55, 0.45), vec3(0.80, 0.75, 0.62), smoothstep(2.0, 12.0, em)) * (0.95 + 0.08 * n2);
		sand = mix(sand, vec3(0.64, 0.62, 0.57), earth_band(em, e2 - 6.0, e2, aw));
		vec3 qc = vec3(0.58, 0.58, 0.56) * (0.94 + 0.08 * n1);
		qc = mix(qc, vec3(0.34, 0.34, 0.33), 1.0 - smoothstep(0.5, 1.5 + aam, em));
		qc = mix(qc, vec3(0.85, 0.72, 0.28), earth_line(abs(em - 3.0), 0.15, aam));
		bc = mix(bc, sand, beach * front);
		bc = mix(bc, qc, quay * front);
		// 공원과 도로 사이의 덤불
		bc = mix(bc, vec3(0.20, 0.31, 0.15), earth_band(em, e2, e3, aw));
		// 강변 도로: 가운데 분리대, 차선, 가장자리 선
		float onroad = earth_band(em, e3, e4, aw);
		float mid = abs(em - e3 - WF_ROAD * 0.5);
		vec3 ra = vec3(0.19, 0.19, 0.20) * (0.94 + 0.1 * n2);
		ra = mix(ra, vec3(0.62, 0.61, 0.57), earth_line(mid, 0.6, aam));
		ra = mix(ra, vec3(0.80, 0.80, 0.77), earth_line(abs(fract((mid - 0.6) / 3.6 + 0.5) - 0.5) * 3.6, 0.09, aam)
			* step(2.0, mid) * step(mid, 10.0) * 0.7);
		ra = mix(ra, vec3(0.80, 0.80, 0.77), earth_line(abs(mid - 10.8), 0.1, aam));
		bc = mix(bc, ra, onroad);
		// 보도와 가로수
		float verge = earth_band(em, e4, e5, aw);
		bc = mix(bc, mix(vec3(0.55, 0.53, 0.49), vec3(0.17, 0.27, 0.12), smoothstep(0.55, 0.7, n2) * 0.8), verge);
		float inb = wk * (1.0 - smoothstep(e5 - aw, e5 + aw, em));
		out_c = mix(out_c, bc, inb);
		lights = mix(lights, mk.x * (onroad * 1.1 + verge * 0.35 + plaza * 0.2) * (0.55 + 0.45 * core), inb);
	}
	return out_c;
}

// 시가지의 땅 색: 지붕·포장의 회색, 가까이서는 블록 격자의 골목과 다섯 블록마다 큰길 (대도시마다 방향·블록 크기 —
// 3D 건물과 같은 격자), 공원은 푸르게. lights: 밤 불빛 세기 (0~1)
vec3 earth_city(vec3 d, vec3 col, float sd, float texel_km, out float lights) {
	int which;
	float u = earth_urban(d, which);
	return earth_city_u(d, col, sd, texel_km, u, which, 0.0, 0.0, lights);
}

// 도시 둘레의 물 (대도시 지도 안): 강·항만은 짙은 청록 회색 — 둑 가까이는 흙물이 섞여 밝고, 벽 바로 앞은 그늘이 진다.
// 잔물결 얼룩. 넓은 바다는 구와 같은 색으로. near_k: 대도시 지도 안 (0~1), aam: 픽셀 폭 (m)
vec3 earth_water(vec3 d, float sd, float near_k, float aam, float sea) {
	vec3 ocean = earth_sea(min(sd, -0.05));
	if (near_k <= 0.0) {
		return ocean;
	}
	float w = -sd * 1000.0;                                          // 물가에서 (m)
	vec3 c = mix(vec3(0.20, 0.27, 0.26), vec3(0.10, 0.18, 0.22), smoothstep(4.0, 140.0, w));
	float m1 = vnoise(d * (EARTH_R / 0.35), 83.0);
	float m2 = vnoise(d * (EARTH_R / 0.06), 85.0);
	c *= 0.9 + 0.12 * m1 + 0.08 * m2 * (1.0 - smoothstep(2.0, 8.0, aam));
	// 모래사장 앞: 얕은 물은 맑은 청록, 물가에 흰 파도 (호안·부두 앞은 벽 그늘)
	float beach;
	float quay;
	earth_shore_kind(d, sea, beach, quay);
	c = mix(c, mix(vec3(0.24, 0.45, 0.46), c, smoothstep(6.0, 70.0, w)), beach);
	c *= mix(0.72 + 0.28 * smoothstep(0.0, 3.0 + aam, w), 1.0, beach);
	float foam = (1.0 - smoothstep(1.0, 7.0 + aam, w)) * (0.55 + 0.45 * vnoise(d * (EARTH_R / 0.02), 86.0));
	c = mix(c, vec3(0.86, 0.89, 0.88), foam * beach * 0.8);
	return mix(ocean, c, near_k * (1.0 - smoothstep(700.0, 2600.0, w)));
}

// 땅의 높이 (km, 해수면 위)와 바다 몫 — 조각 굽기용
float earth_h(vec3 d, float texel_km, out float liq) {
	float sd = earth_sd(d, texel_km);
	float tk = max(texel_km, 0.002);
	liq = 1.0 - smoothstep(-tk * 0.5, tk * 0.5, sd);
	// 해안에서 천천히 오르는 땅과 구릉 (나로도·쿠루 둘레의 낮은 산 수준)
	float inland = clamp(sd, 0.0, 40.0);
	float hills = max(fbm(d * (EARTH_R / 8.0), 5, 31.0) - 0.42, 0.0) * 0.9 * smoothstep(0.2, 4.0, sd);
	// 대도시는 평평하게 (강가를 따라 골짜기가 패지 않게)
	int which;
	float u = earth_urban(d, which);
	hills *= 1.0 - 0.92 * u;
	inland *= 1.0 - 0.6 * u;
	float h = 0.003 + inland * 0.004 + hills;
	return mix(h, 0.0, liq);
}
