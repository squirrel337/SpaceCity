// 기지 둘레의 지형 조각 (반지름 60 km). 메시는 평평한 극좌표 격자 (UV = 둘레 번호, 고리 번호; UV2.x = 1이면 치마).
// 높이·법선은 굽어 둔 지도(hmap)에서 꼭짓점마다 읽는다 — 달 전체를 그린 구와 같은 함수로 구웠다.
// 모형 좌표(m): x·y 수평, z 위, 원점 = 기지 평지. 메시 좌표 = (x, z, -y). 달의 곡률만큼 가장자리가 내려간다.
shader_type spatial;
render_mode cull_back;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/moon_surface.gdshaderinc"

uniform samplerCube surf : filter_linear_mipmap;
uniform bool has_surf = false;
uniform sampler2D cap : filter_linear_mipmap, repeat_disable;
uniform bool has_cap = false;
uniform float cap_rad = 0.2;
uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform bool has_hmap = false;
uniform vec3 site_dir = vec3(0.0, 0.0, -1.0);
uniform mat3 site_basis;
uniform float plateau_m = 0.0;
uniform float patch_m = 60000.0;
uniform vec4 base_rect = vec4(0.0, 3.0, 235.0, 265.0);
uniform vec4 ice = vec4(0.0, 0.0, 34.0, 4.5);
uniform float gain = 1.0;
uniform int debug = 0;
varying vec3 bdir;
varying vec2 mpos;
varying vec3 dbg_n;

const float R_M = 1737400.0;
const float SQ = 0.70710678118;

vec3 body_dir(vec2 p) {
	return normalize(site_dir * R_M + site_basis * vec3(p, 0.0));
}

float base_weight(vec2 p, float margin) {
	vec2 uv = vec2((p.x - p.y) * SQ, (p.x + p.y) * SQ);
	vec2 dq = max(abs(uv - base_rect.xy) - base_rect.zw, vec2(0.0));
	return 1.0 - smoothstep(0.0, margin, length(dq));
}

// 굽기 전(또는 굽지 못할 때): 남극 크레이터 + 평지만
float rough_m(vec2 p) {
	float h = polar_height(body_dir(p)) * 1000.0;
	h = mix(h, plateau_m, base_weight(p, 260.0));
	vec2 qi = p - ice.xy;
	float ri = length(qi);
	h += ri < ice.z ? (ri * ri / (ice.z * ice.z) - 1.0) * ice.w : 0.0;
	return (h * (1.0 - smoothstep(patch_m * 0.85, patch_m, length(p)))) - plateau_m;
}

void vertex() {
	vec2 p = vec2(VERTEX.x, -VERTEX.z);
	float h;
	vec3 n;
	if (has_hmap) {
		vec4 t = texelFetch(hmap, ivec2(int(UV.x + 0.5), int(UV.y + 0.5)), 0);
		h = (floor(t.r * 255.0 + 0.5) * 256.0 + floor(t.g * 255.0 + 0.5)) / 8.192 - 6000.0;
		vec2 nxy = t.ba * 2.0 - 1.0;
		n = vec3(nxy, sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	} else {
		float e = max(length(p) * 0.02, 2.0);
		h = rough_m(p);
		float hx = rough_m(p + vec2(e, 0.0));
		float hy = rough_m(p + vec2(0.0, e));
		n = normalize(vec3(-(hx - h) / e, -(hy - h) / e, 1.0));
	}
	float r2 = dot(p, p);
	float drop = r2 / (2.0 * R_M) + r2 * r2 / (8.0 * R_M * R_M * R_M);
	float shrink = 1.0 - r2 / (6.0 * R_M * R_M);
	vec3 m = vec3(p * shrink, h - drop - UV2.x * 450.0);
	VERTEX = vec3(m.x, m.z, -m.y);
	n = normalize(n + vec3(p / R_M, 0.0));
	NORMAL = vec3(n.x, n.z, -n.y);
	dbg_n = n;
	bdir = body_dir(p);
	mpos = p;
}

void fragment() {
	vec3 g = vec3(bdir.x, bdir.z, -bdir.y);
	float a = has_surf ? texture(surf, g).a : 0.56;
	if (has_cap) {
		float sr = length(bdir.xy);
		float rho = asin(clamp(sr, 0.0, 1.0));
		a = texture(cap, 0.5 + 0.5 * (sr > 1e-9 ? bdir.xy / sr : vec2(0.0)) * (rho / cap_rad)).a;
	}
	float mpp = length(dFdx(mpos)) + length(dFdy(mpos));
	float n1 = fbm(vec3(mpos * 0.0035, 1.0), 4, 3.0);
	float n2 = fbm(vec3(mpos * 0.06, 2.0), 3, 5.0);
	a *= 0.9 + 0.16 * (n1 - 0.5) + 0.1 * (n2 - 0.5) * (1.0 - smoothstep(4.0, 30.0, mpp));
	a *= 1.0 - 0.08 * base_weight(mpos, 180.0);
	vec3 tint = mix(vec3(0.86, 0.85, 0.88), vec3(1.0, 0.97, 0.92), smoothstep(0.3, 0.6, a));
	ALBEDO = tint * a * 0.62 * gain;
	// 가까이서 보이는 흙의 잔주름 (화면 미분으로 법선을 흔든다)
	float fade = 1.0 - smoothstep(0.4, 3.0, mpp);
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
		float edge = smoothstep(patch_m * 0.8, patch_m * 0.98, length(mpos));
		if (edge > 0.0) {
			vec3 nb = normalize(texture(surf, g).rgb * 2.0 - 1.0);       // 메시 좌표 = 몸체 (x, z, -y)
			vec3 nbody = vec3(nb.x, -nb.z, nb.y);
			vec3 nm = transpose(site_basis) * nbody;                     // 모형 좌표
			vec3 nl = vec3(nm.x, nm.z, -nm.y);                           // 조각 메시 좌표
			vec3 nv = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(nl, 0.0))).xyz);
			NORMAL = normalize(mix(NORMAL, nv, edge));
		}
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (debug == 1) {
		EMISSION = dbg_n * 0.5 + 0.5;
	}
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	DIFFUSE_LIGHT += mix(mu0, ls, 0.5) * ATTENUATION * LIGHT_COLOR / PI;
}
