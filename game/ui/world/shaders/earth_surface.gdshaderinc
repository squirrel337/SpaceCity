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
uniform bool cl_parks = false;                                        // 지역 지도의 G = 공원 (대도시 시가지 지도)

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

// 가장 가까운 해안까지의 거리 (km, 땅 +, 바다 −). texel_km: 표본(픽셀) 간격
float earth_sd(vec3 d, float texel_km) {
	vec2 uv = earth_uv(d);
	float sd;
	float src_km = 9.8;
	if (has_coast) {
		sd = (texture(coast, uv).r - 0.5) * 2.0 * COAST_KM;
	} else if (has_land) {
		sd = (texture(land, uv).r - 0.5) * 60.0;
		src_km = 40.0;
	} else {
		sd = (fbm(d * 2.5, 5, 7.0) - 0.54) * 400.0;
		src_km = 200.0;
	}
	if (has_coast_loc) {
		float w = dot(d, cl_c);
		if (w > 0.9) {
			vec2 q = vec2(dot(d, cl_e), dot(d, cl_n)) * EARTH_R / w;
			vec2 luv = vec2(0.5 + q.x / (2.0 * cl_half), 0.5 - q.y / (2.0 * cl_half));
			float m = max(abs(luv.x - 0.5), abs(luv.y - 0.5));
			if (m < 0.5) {
				float sl = (texture(coast_loc, luv).r - 0.5) * 2.0 * cl_range;
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
	// 잔 굴곡: 지도 칸 폭에서 시작해 표본 간격까지 (멀리서도 가까이서도 또렷하고 들쭉날쭉한 해안)
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

// 시가지의 땅 색: 지붕·포장의 회색, 가까이서는 블록 격자의 골목과 다섯 블록마다 큰길 (대도시마다 방향·블록 크기 —
// 3D 건물과 같은 격자), 공원은 푸르게. lights: 밤 불빛 세기 (0~1)
vec3 earth_city(vec3 d, vec3 col, float sd, float texel_km, out float lights) {
	lights = 0.0;
	int which;
	float u = earth_urban(d, which);
	if (u <= 0.0 || which < 0) {
		return col;
	}
	u *= smoothstep(-0.02, 0.05, sd);
	float park = earth_park(d);
	vec4 mk = metro_k[which];
	vec3 c = metro[which].xyz;
	vec3 e = normalize(vec3(-c.y, c.x, 0.0) + vec3(1e-7, 0.0, 0.0));
	vec3 n = cross(c, e);
	vec2 q = vec2(dot(d - c, e), dot(d - c, n)) * EARTH_R;           // 도심에서 동·북 (km)
	vec2 uu = vec2(sin(mk.y), cos(mk.y));
	vec2 vv = vec2(cos(mk.y), -sin(mk.y));
	float bk = max(mk.z, 0.02);
	vec2 g = vec2(dot(q, vv), dot(q, uu)) / bk;                       // 블록 단위 (길은 정수 자리)
	float aa = max(texel_km, 1e-4);
	float vis = 1.0 - smoothstep(bk * 0.12, bk * 0.5, aa);           // 블록이 화면에서 작으면 무늬는 평균으로
	float r1 = hash1(vec3(floor(g * 2.0), 3.0), 17.0);
	vec3 roof = mix(vec3(0.34, 0.33, 0.33), vec3(0.54, 0.52, 0.49), r1);
	roof = mix(roof, vec3(0.42, 0.41, 0.40), 1.0 - vis);
	vec2 f = abs(fract(g + 0.5) - 0.5) * bk;
	vec2 big = abs(fract(g / 5.0 + 0.5) - 0.5) * bk * 5.0;
	float street = 1.0 - smoothstep(0.006 - aa * 0.5, 0.006 + aa * 0.5, min(f.x, f.y));
	float avenue = 1.0 - smoothstep(0.015 - aa * 0.5, 0.015 + aa * 0.5, min(big.x, big.y));
	float road = max(street * 0.8, avenue) * vis;
	vec3 urb = mix(roof, vec3(0.21, 0.21, 0.22), road);
	urb = mix(urb, vec3(0.30, 0.31, 0.30), (1.0 - vis) * 0.3);
	float k = u * (1.0 - park);
	vec3 out_c = mix(col, urb, k * 0.9);
	out_c = mix(out_c, mix(col, vec3(0.15, 0.29, 0.12), 0.55), park * u);
	// 밤 불빛: 가까이서는 길을 따라, 멀리서는 시가지 전체가 (도심일수록 밝게)
	float core = 1.0 - smoothstep(0.0, metro[which].w * 0.7, length(q));
	float glow = mix(0.5 + 0.35 * vnoise(d * (EARTH_R / 0.9), 9.0), 0.25 + 1.1 * road, vis);
	lights = k * mk.x * glow * (0.55 + 0.45 * core);
	return out_c;
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
