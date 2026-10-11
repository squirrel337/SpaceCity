// 도시 둘레 지형 조각(반지름 patch_m)의 높이를 굽는다 — 꼭짓점 (둘레 i, 고리 k)마다 한 칸.
// 이 파일을 넣기 전에 정의할 것: float site_field(vec3 d, float texel_km, out float liq)
//   — 천체 고정 방향 d의 높이 (km, 기준 구 위)와 액체 몫 (구를 굽는 함수와 같아야 조각과 구가 이어진다).
// pass 0 (한 줄, 너비 64): 칸 0..62 = 조각 가장자리 (r = patch_m)의 높이, 칸 63 = 기지 평지 자리의 높이.
// pass 1 (격자 segs × rings): 기지 평지 기준 높이. 높이는 RGB 24비트 ((m + 32768) × 256), A = 액체 몫.
// 조각은 가장자리의 평균 높이(ref_m)를 구의 높이로 본다 — 가장자리에서 높이가 ref_m으로 잦아들어 구와 이어지고,
// 기지 평지는 기준 구에서 site_m − ref_m 위에 앉는다 (분지 바닥의 도시는 둘레보다 낮게, 산 위의 도시는 높게).

uniform int pass_mode = 1;
uniform int segs = 192;
uniform int rings = 216;
uniform float grow = 1.0327;
uniform float patch_m = 60000.0;
uniform float r_m = 1000000.0;
uniform vec3 site_dir = vec3(0.0, 0.0, 1.0);
uniform mat3 site_basis;
uniform vec4 base_rect = vec4(0.0, 3.0, 235.0, 265.0);
uniform vec4 ice = vec4(0.0);             // 얼음 분화구 (모형 x, y, 반지름 m, 깊이 m) — 반지름 0이면 없다
uniform vec4 ridge = vec4(0.0);           // 능선형 부지: 기지가 테두리에 앉은 크레이터 (모형 x, y, 반지름 m, 깊이 m)
uniform vec4 loc_c[48];                   // 둘레의 작은 크레이터 (모형 x, y, 반지름 m, 깊이 m)
uniform int loc_n = 0;
uniform vec2 rough = vec2(36.0, 0.0011);  // 잔 기복 (폭 m, 주파수 1/m)
uniform float ref_m = 0.0;
uniform float site_m = 0.0;

const float SQ_P = 0.70710678118;
const float TAU_P = 6.28318530718;

float ring_r(int k) {
	if (k <= 50) {
		return 6.0 * float(k);
	}
	return min(300.0 * pow(grow, float(k - 50)), patch_m);
}

vec3 pdir(vec2 p) {
	return normalize(site_dir * r_m + site_basis * vec3(p, 0.0));
}

float base_dist(vec2 p) {
	vec2 uv = vec2((p.x - p.y) * SQ_P, (p.x + p.y) * SQ_P);
	vec2 dq = max(abs(uv - base_rect.xy) - base_rect.zw, vec2(0.0));
	return length(dq);
}

// 기준 구 위의 높이 (m)와 액체 몫. sp: 이 자리의 꼭짓점 간격 (m)
float total_m(vec2 p, float sp, out float liq) {
	float h = site_field(pdir(p), max(sp, 1.0) / 1000.0, liq) * 1000.0;
	float dry = 1.0 - liq;
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
	h += cr * dry;
	// 잔 기복 (기지 가까이는 잦아든다)
	h += (fbm(vec3(p * rough.y, 4.0), 4, 21.0) - 0.5) * rough.x * smoothstep(400.0, 3000.0, base_dist(p)) * dry;
	if (ridge.z > 0.0) {
		// 능선 너머는 크레이터 안으로 내려가고 (영구 그늘), 바깥은 완만히 내려간다
		float x = length(p - ridge.xy) / ridge.z;
		h += x < 1.0 ? ridge.w * (x * x - 1.0) : -ridge.w * 0.11 * (1.0 - exp(-(x - 1.0) * 3.0));
	}
	return h;
}

vec3 code24(float v) {
	float c = floor(clamp((v + 32768.0) * 256.0, 0.0, 16777215.0) + 0.5);
	float r = floor(c / 65536.0);
	float g = floor((c - r * 65536.0) / 256.0);
	float b = c - r * 65536.0 - g * 256.0;
	return vec3(r, g, b) / 255.0;
}

void fragment() {
	float liq = 0.0;
	if (pass_mode == 0) {
		int i = int(UV.x * 64.0);
		float h;
		if (i >= 63) {
			h = site_field(site_dir, 0.001, liq) * 1000.0;
		} else {
			float a = TAU_P * float(i) / 63.0;
			h = site_field(pdir(vec2(cos(a), sin(a)) * patch_m), 1.0, liq) * 1000.0;
		}
		COLOR = vec4(code24(h), 1.0);
	} else {
		int i = int(UV.x * float(segs));
		int k = int(UV.y * float(rings));
		float a = TAU_P * float(i) / float(segs);
		float r = ring_r(k);
		vec2 p = vec2(cos(a), sin(a)) * r;
		float sp = k == 0 ? 3.0 : max(r - ring_r(k - 1), TAU_P * r / float(segs));
		float h = total_m(p, sp, liq);
		float bw = 1.0 - smoothstep(0.0, 260.0, base_dist(p));
		h = mix(h, site_m, bw);
		liq *= 1.0 - bw;
		if (ice.z > 0.0) {
			float ri = length(p - ice.xy);
			float qi2 = ri * ri / (ice.z * ice.z);
			h += ri < ice.z ? (qi2 - 1.0 + 0.15 * qi2 * qi2) * ice.w : ice.w * 0.15 * exp(-pow((ri - ice.z) / (ice.z * 0.3), 2.0));
		}
		// 가장자리에서는 구의 높이로 (조각 밖의 구와 이어지게)
		float fade = smoothstep(patch_m * 0.85, patch_m, r);
		float hrel = (h - ref_m) * (1.0 - fade);
		COLOR = vec4(code24(hrel - (site_m - ref_m)), liq);
	}
}
