// 기지 둘레 지형 조각의 높이를 굽는다 (시작할 때 한 번). 칸 (i, k) = 극좌표 격자의 꼭짓점 (둘레 i, 고리 k).
// RG: 기지 평지 기준 높이 (16비트, (h + 6000) × 8.192), BA: 법선 x·y (모형 좌표).
// 맨 아래 한 줄은 기지 평지의 높이(기준 구 위)를 담는다: RG = (H + 10000) / 20000 × 65535.
// 높이 = 달 전체의 높이(구 굽기와 같은 함수) + 작은 크레이터 + 기지 평지 + 얼음 크레이터.
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/moon_surface.gdshaderinc"
#include "res://ui/world/shaders/moon_field.gdshaderinc"

uniform int segs = 192;
uniform int rings = 216;
uniform float grow = 1.0327;
uniform float patch_m = 60000.0;
uniform vec3 site_dir = vec3(0.0, 0.0, -1.0);
uniform mat3 site_basis;
uniform vec4 base_rect = vec4(0.0, 3.0, 235.0, 265.0);
uniform vec4 ice = vec4(0.0, 0.0, 34.0, 4.5);
uniform vec4 loc_c[48];
uniform int loc_n = 0;

const float R_M = 1737400.0;
const float SQ = 0.70710678118;
const float TAU_M = 6.28318530718;

float ring_r(int k) {
	if (k <= 50) {
		return 6.0 * float(k);
	}
	return min(300.0 * pow(grow, float(k - 50)), patch_m);
}

vec3 body_dir(vec2 p) {
	return normalize(site_dir * R_M + site_basis * vec3(p, 0.0));
}

float base_dist(vec2 p) {
	vec2 uv = vec2((p.x - p.y) * SQ, (p.x + p.y) * SQ);
	vec2 dq = max(abs(uv - base_rect.xy) - base_rect.zw, vec2(0.0));
	return length(dq);
}

float global_m(vec2 p) {
	float fr;
	float mr;
	return height(body_dir(p), fr, mr) * 1000.0;
}

float total_m(vec2 p, float hsite) {
	float r = length(p);
	float h = global_m(p);
	float cr = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= loc_n) {
			break;
		}
		vec2 q = p - loc_c[i].xy;
		float R = loc_c[i].z;
		float dd = dot(q, q);
		if (dd > R * R * 9.0) {
			continue;
		}
		float rho = sqrt(dd);
		float depth = loc_c[i].w;
		float rim = depth * 0.2;
		cr += rho < R ? (rho * rho / (R * R) - 1.0) * depth + rim : rim * pow(R / rho, 3.0) * (1.0 - smoothstep(2.0 * R, 3.0 * R, rho));
	}
	h += cr;
	// 잔 기복 (기지 가까이는 잦아든다)
	h += (fbm(vec3(p * 0.0011, 4.0), 4, 21.0) - 0.5) * 36.0 * smoothstep(400.0, 3000.0, base_dist(p));
	h = mix(h, hsite, 1.0 - smoothstep(0.0, 260.0, base_dist(p)));
	vec2 qi = p - ice.xy;
	float ri = length(qi);
	float qi2 = ri * ri / (ice.z * ice.z);
	h += ri < ice.z ? (qi2 - 1.0 + 0.15 * qi2 * qi2) * ice.w : ice.w * 0.15 * exp(-pow((ri - ice.z) / (ice.z * 0.3), 2.0));
	// 가장자리에서는 기준 구로 (조각 밖의 구와 이어지게)
	return h * (1.0 - smoothstep(patch_m * 0.85, patch_m, r));
}

vec2 code16(float v) {
	float c = floor(clamp(v, 0.0, 65535.0) + 0.5);
	float hi = floor(c / 256.0);
	return vec2(hi, c - hi * 256.0) / 255.0;
}

void fragment() {
	int i = int(UV.x * float(segs));
	int k = int(UV.y * float(rings + 1));
	float hsite = global_m(vec2(0.0));
	if (k >= rings) {
		COLOR = vec4(code16((hsite + 10000.0) / 20000.0 * 65535.0), 0.0, 1.0);
	} else {
		float a = TAU_M * float(i) / float(segs);
		float r = ring_r(k);
		vec2 p = vec2(cos(a), sin(a)) * r;
		float sp = k == 0 ? 3.0 : max(r - ring_r(k - 1), TAU_M * r / float(segs));
		float e = max(sp * 0.5, 1.0);
		float h0 = total_m(p, hsite);
		float hx = total_m(p + vec2(e, 0.0), hsite);
		float hy = total_m(p + vec2(0.0, e), hsite);
		vec3 n = normalize(vec3(-(hx - h0) / e, -(hy - h0) / e, 1.0));
		COLOR = vec4(code16((h0 - hsite + 6000.0) * 8.192), n.x * 0.5 + 0.5, n.y * 0.5 + 0.5);
	}
}
