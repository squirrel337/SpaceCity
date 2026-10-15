// 다른 천체(달의 다른 부지 포함) 도시 둘레의 지형 조각 (반지름 patch_m). 메시는 평평한 극좌표 격자
// (UV = 둘레 번호, 고리 번호; UV2.x = 1이면 치마 — 구와의 틈을 가린다).
// 높이·액체 몫은 굽어 둔 격자(hmap)에서 꼭짓점마다 읽고, 법선은 이웃 꼭짓점으로 셈한다 —
// 그 천체 구와 같은 함수로 구웠다. 색은 구와 같은 지도(정육면체 + 도시 둘레 지역)의 밝기 → 팔레트.
// 모형 좌표(m): x·y 수평, z 위, 원점 = 기지 평지. 메시 좌표 = (x, z, -y). 천체의 곡률만큼 가장자리가 내려간다.
shader_type spatial;
render_mode cull_back;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/earth_surface.gdshaderinc"

uniform samplerCube surf : filter_linear_mipmap;
uniform bool has_surf = false;
uniform sampler2D cap : filter_linear_mipmap, repeat_disable;
uniform bool has_cap = false;
uniform float cap_rad = 0.1;
uniform vec3 cap_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 cap_e1 = vec3(1.0, 0.0, 0.0);
uniform vec3 cap_e2 = vec3(0.0, 1.0, 0.0);
uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform bool has_hmap = false;
uniform int segs = 192;
uniform int rings = 216;
uniform float grow = 1.0327;
uniform float patch_m = 60000.0;
uniform float r_m = 1000000.0;
uniform vec3 site_dir = vec3(0.0, 0.0, 1.0);
uniform mat3 site_basis;
uniform vec4 base_rect = vec4(0.0, 3.0, 235.0, 265.0);
uniform vec4 ice = vec4(0.0);                        // 얼음·서리 자리 (모형 x, y, 반지름 m)
uniform vec4 frost : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float frost_k = 0.0;                         // 서리 세기
uniform vec4 pal[8];                                 // 팔레트: rgb (sRGB), a = 좌표
uniform int pal_n = 0;
uniform vec3 liq_col = vec3(0.01);                   // 액체 색 (sRGB)
uniform int mode = 0;                                // 0 팔레트 (구운 지도의 밝기), 1 지구 (해안 거리 지도)
uniform float eseed = 1.0;                           // 지구 구와 같은 잡음 씨앗
uniform float ls_k = 0.5;                            // 대기 없는 땅의 빛 (로멜-젤리거) 몫
uniform float soft_k = 0.0;                          // 대기가 해 질 녘 빛을 퍼뜨리는 몫 (구의 행성 셰이더와 같은 값)
uniform float gain = 1.0;
uniform float night_glow = 0.0;                      // 지구: 그 자리의 밤 (시가지 불빛)
uniform int debug = 0;
uniform float flood_z = -1e9;                        // 판 땅에 차는 물의 높이 (해수면, 모형 좌표 m)
varying vec3 bdir;
varying vec2 mpos;
varying float wet_v;
varying float flood_v;                               // 해수면 아래로 판 땅의 꼭짓점 (물 몫 254로 적는다)
varying float mz;                                    // 모형 좌표의 높이 (m, 기지 평지 기준)
varying vec3 up_v;                                   // 이 자리의 천체 위쪽 (뷰 좌표) — 구와 같은 빛을 셈하려고

const float SQ = 0.70710678118;
const float TAU_P = 6.28318530718;

float ring_r(int k) {
	if (k <= 50) {
		return 6.0 * float(k);
	}
	return min(300.0 * pow(grow, float(k - 50)), patch_m);
}

float grid_h(int i, int k) {
	vec4 t = texelFetch(hmap, ivec2((i + segs) % segs, clamp(k, 0, rings - 1)), 0);
	return (floor(t.r * 255.0 + 0.5) * 65536.0 + floor(t.g * 255.0 + 0.5) * 256.0 + floor(t.b * 255.0 + 0.5)) / 256.0 - 32768.0;
}

vec3 grid_p(int i, int k) {
	int kk = clamp(k, 0, rings - 1);
	float a = TAU_P * float(i) / float(segs);
	float r = ring_r(kk);
	return vec3(cos(a) * r, sin(a) * r, grid_h(i, kk));
}

vec3 pal_color(float a) {
	vec3 c = pal[0].rgb;
	for (int i = 1; i < 8; i++) {
		if (i >= pal_n) {
			break;
		}
		c = mix(c, pal[i].rgb, clamp((a - pal[i - 1].a) / max(pal[i].a - pal[i - 1].a, 1e-4), 0.0, 1.0));
	}
	return c;
}

float base_weight(vec2 p, float margin) {
	vec2 uv = vec2((p.x - p.y) * SQ, (p.x + p.y) * SQ);
	vec2 dq = max(abs(uv - base_rect.xy) - base_rect.zw, vec2(0.0));
	return 1.0 - smoothstep(0.0, margin, length(dq));
}

// 구와 같은 지도: 정육면체 + 도시 둘레 지역 (몸체 고정 방향 d)
vec4 surf_at(vec3 d) {
	vec3 g = vec3(d.x, d.z, -d.y);
	vec4 s = has_surf ? texture(surf, g) : vec4(g * 0.5 + 0.5, 0.5);
	if (has_cap) {
		float rho = 2.0 * asin(clamp(length(d - cap_dir) * 0.5, 0.0, 1.0));
		if (rho < cap_rad) {
			vec3 t = d - cap_dir * dot(d, cap_dir);
			float tl = length(t);
			vec2 q = tl > 1e-9 ? vec2(dot(t, cap_e1), dot(t, cap_e2)) / tl : vec2(0.0);
			s = mix(texture(cap, 0.5 + 0.5 * q * (rho / cap_rad)), s, smoothstep(cap_rad * 0.85, cap_rad * 0.98, rho));
		}
	}
	return s;
}

void vertex() {
	vec2 p = vec2(VERTEX.x, -VERTEX.z);
	int i = int(UV.x + 0.5);
	int k = int(UV.y + 0.5);
	float h = 0.0;
	vec3 n = vec3(0.0, 0.0, 1.0);
	wet_v = 0.0;
	flood_v = 0.0;
	if (has_hmap) {
		h = grid_h(i, k);
		float a8 = floor(texelFetch(hmap, ivec2(i, k), 0).a * 255.0 + 0.5);
		flood_v = a8 == 254.0 ? 1.0 : 0.0;
		wet_v = a8 == 254.0 ? 0.0 : a8 / 255.0;
		if (k > 0) {
			vec3 ta = grid_p(i + 1, k) - grid_p(i - 1, k);
			vec3 tr = grid_p(i, k + 1) - grid_p(i, k - 1);
			n = normalize(cross(tr, ta));
		}
	}
	float r2 = dot(p, p);
	float drop = r2 / (2.0 * r_m) + r2 * r2 / (8.0 * r_m * r_m * r_m);
	float shrink = 1.0 - r2 / (6.0 * r_m * r_m);
	mz = h;
	vec3 m = vec3(p * shrink, h - drop - UV2.x * 450.0);
	VERTEX = vec3(m.x, m.z, -m.y);
	n = normalize(n + vec3(p / r_m, 0.0));
	NORMAL = vec3(n.x, n.z, -n.y);
	bdir = normalize(site_dir * r_m + site_basis * vec3(p, 0.0));
	mpos = p;
	vec3 um = normalize(vec3(p / r_m, 1.0));
	up_v = (MODELVIEW_MATRIX * vec4(um.x, um.z, -um.y, 0.0)).xyz;
}

void fragment() {
	vec4 s = surf_at(bdir);
	float a = s.a;
	float mpp = length(dFdx(mpos)) + length(dFdy(mpos));
	float n1 = fbm(vec3(mpos * 0.0035, 1.0), 4, 3.0);
	float n2 = fbm(vec3(mpos * 0.06, 2.0), 3, 5.0);
	vec3 col;
	float sd = 0.0;
	float city_l = 0.0;
	if (mode == 1) {
		// 지구: 구와 같은 땅 색, 도시 둘레는 밭·숲·풀밭의 무늬
		sd = earth_sd(bdir, max(mpp, 0.5) / 1000.0);
		col = earth_ground(bdir, sd, eseed);
		float f1 = fbm(vec3(mpos * 0.0021, 11.0), 4, 12.0);
		float f2 = fbm(vec3(mpos * 0.017, 12.0), 3, 13.0);
		col = mix(col, col * vec3(0.72, 0.86, 0.7), smoothstep(0.5, 0.62, f1) * 0.8);
		col = mix(col, col * vec3(1.18, 1.12, 0.92), smoothstep(0.55, 0.7, f2) * 0.5 * (1.0 - smoothstep(4.0, 30.0, mpp)));
		col *= 0.92 + 0.16 * n1;
		col = earth_city(bdir, col, sd, max(mpp, 0.5) / 1000.0, city_l);
	} else {
		a += 0.05 * (n1 - 0.5) + 0.04 * (n2 - 0.5) * (1.0 - smoothstep(4.0, 30.0, mpp));
		col = pal_color(a);
	}
	col *= 1.0 - 0.08 * base_weight(mpos, 180.0);
	if (frost_k > 0.0 && ice.z > 0.0) {
		float fr = frost_k * (1.0 - smoothstep(ice.z * 0.35, ice.z, length(mpos - ice.xy))) * (0.75 + 0.25 * n2);
		col = mix(col, frost.rgb, fr);
	}
	// 액체: 꼭짓점의 액체 몫을 문턱으로 (해안이 지형과 맞는다). 꼭짓점 사이의 잔 굴곡은 잡음으로
	float shore_n = (fbm(vec3(mpos * 0.004, 7.0), 4, 9.0) - 0.5) * 0.5
		+ (fbm(vec3(mpos * 0.05, 8.0), 3, 10.0) - 0.5) * 0.3 * (1.0 - smoothstep(5.0, 40.0, mpp));
	float wet = step(0.5, wet_v + shore_n);
	// 판 땅에 찬 물: 해수면 높이에서 고른 물낯 (구덩이 벽을 타고 오르지 않는다)
	wet = max(wet, flood_v > 0.001 ? 1.0 - step(flood_z + 0.15, mz) : 0.0);
	if (mode == 1 && cl_parks) {
		// 대도시 지도(강을 그린 고운 지도) 안에서는 조각마다 해안 거리로 — 꼭짓점 사이보다 좁은 강도 끊기지 않는다
		// (시가지의 땅은 거의 해수면이다)
		wet = mix(wet, 1.0 - step(0.0, sd), step(0.5, earth_loc_k(bdir)));
	}
	col = mix(col, mode == 1 ? earth_sea(min(sd, -0.05)) : liq_col, wet);
	ALBEDO = col * gain;
	EMISSION = vec3(1.0, 0.6, 0.24) * city_l * (1.0 - wet) * night_glow * 0.45;
	ROUGHNESS = mix(1.0, 0.06, wet);
	SPECULAR = 0.0;
	// 가까이서 보이는 흙의 잔주름 (화면 미분으로 법선을 흔든다)
	float fade = (1.0 - smoothstep(0.4, 3.0, mpp)) * (1.0 - wet);
	if (fade > 0.0) {
		float b = (fbm(vec3(mpos * 0.45, 3.0), 3, 7.0) - 0.5) * 0.5 * fade;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		float mscale = mpp / max(length(dpdx) + length(dpdy), 1e-9);
		vec3 grad = sign(det) * (dFdx(b) * r1 + dFdy(b) * r2) / max(mscale, 1e-6);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}
	if (has_surf) {
		// 조각 가장자리: 구의 법선으로 (구와 같은 빛)
		float edge = smoothstep(patch_m * 0.8, patch_m * 0.98, length(mpos));
		if (edge > 0.0) {
			vec3 nb = normalize(s.rgb * 2.0 - 1.0);       // 메시 좌표 = 몸체 (x, z, -y)
			vec3 nbody = vec3(nb.x, -nb.z, nb.y);
			vec3 nm = transpose(site_basis) * nbody;      // 모형 좌표
			vec3 nl = vec3(nm.x, nm.z, -nm.y);            // 조각 메시 좌표
			vec3 nv = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nl, 0.0))).xyz);
			NORMAL = normalize(mix(NORMAL, nv, edge));
		}
	}
	if (debug == 1) {
		EMISSION = vec3(wet_v, a, 0.0);
	}
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	float wet = 1.0 - smoothstep(0.1, 0.4, ROUGHNESS);
	// 구(planet.gdshader)와 같은 빛: 대기가 해 질 녘 빛을 퍼뜨리고, 밤 쪽 깊숙이서는 지형이 빛을 새게 하지 않는다
	float ndl_g = dot(normalize(up_v), LIGHT);
	float diff = mix(mix(mu0, ls, ls_k), smoothstep(-0.08, 0.45, ndl_g), soft_k) * smoothstep(-0.25, 0.0, ndl_g);
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;
	if (wet > 0.0) {
		// 액체 면의 햇빛 반사
		vec3 hv = normalize(LIGHT + VIEW);
		float spec = pow(max(dot(NORMAL, hv), 0.0), 220.0) * 6.0 + pow(max(dot(NORMAL, hv), 0.0), 24.0) * 0.08;
		SPECULAR_LIGHT += wet * spec * step(0.0, dot(NORMAL, LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
