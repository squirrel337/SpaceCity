// 행성·위성: 스스로 계산하는 빛 (태양 방향 sun_dir, Godot 축). 겉모습은 kind로 고른다.
// 암석·얼음 천체는 GPU로 구운 지도(정육면체: 법선 + 밝기, 고른 도시 둘레는 더 고운 지역 지도)가 있으면 그것으로
// 그린다 — 밝기는 팔레트로 색이 되고, 액체(타이탄의 바다)는 따로 칠한다. 지구는 해안 거리 지도로 땅·바다를 긋는다.
// 구운 지도로 그리는 천체와 지구는 빛을 선형 공간에서 셈한다 (Godot 빛을 받는 도시 둘레 지형 조각과 같은 밝기 —
// 호환 렌더러는 ALBEDO를 sRGB로 받으므로 선형으로 셈한 색을 sRGB로 돌려 넣는다).
// 메시는 단위 구: 메시 좌표 (x, y, z) = 몸체 고정 (x, z, -y) — 몸체 z가 북극.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/planet_albedo.gdshaderinc"
#include "res://ui/world/shaders/earth_surface.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec4 atmo : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float bright = 1.0;
// 식민지의 지형 조각이 보이는 동안 그 자리를 비운다 (몸체 고정 방향, 단위 구의 현 길이)
uniform vec3 hole_dir = vec3(0.0, 0.0, 1.0);
uniform float hole_chord = 0.0;
uniform vec3 hole2_dir = vec3(0.0, 0.0, 1.0);    // 지구: 가까이 간 대도시의 지형 조각 자리
uniform float hole2_chord = 0.0;
// 식민지 가까이: 그 땅의 밤(시뮬레이션)이면 어둡게, 대기의 연무(rgb 색, a 렌더 단위당 밀도), 가장자리 빛 줄이기
uniform float lit_k = 1.0;
uniform vec4 air : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float rim_k = 1.0;
// 식민지 가까이: 장면의 주변광·반사광 (선형 색 × 세기) — 땅 조각이 받는 빛과 맞춘다
uniform vec3 sun_col = vec3(1.0);
uniform vec3 amb_light = vec3(0.0);
uniform vec3 fill_light = vec3(0.0);
uniform vec3 fill_dir = vec3(0.0, 1.0, 0.0);
// 구운 지도 (BodyBaker)와 고른 도시 둘레의 지역 지도 (SiteSurface)
uniform samplerCube surf : filter_linear_mipmap;
uniform bool has_surf = false;
uniform sampler2D cap : filter_linear_mipmap, repeat_disable;
uniform bool has_cap = false;
uniform float cap_rad = 0.1;
uniform vec3 cap_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 cap_e1 = vec3(1.0, 0.0, 0.0);
uniform vec3 cap_e2 = vec3(0.0, 1.0, 0.0);
uniform vec4 pal[8];                      // 팔레트: rgb (sRGB), a = 좌표
uniform int pal_n = 0;
uniform float liq_th = 0.0;
uniform vec3 liq_col = vec3(0.01);
uniform float ls_k = 0.0;                 // 대기 없는 땅의 빛 (로멜-젤리거) 몫
uniform float r_km = 1000.0;
uniform vec4 veil = vec4(0.0);            // 짙은 대기(타이탄)가 땅을 가리는 연무: rgb 색(선형), a 가리는 몫
uniform float cloud_k = 1.0;              // 지구의 구름 (땅 가까이서는 옅어진다)
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
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

vec4 surf_at(vec3 o, vec3 d) {
	vec4 s = texture(surf, o);
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

void fragment() {
	vec3 o = normalize(obj);
	vec3 d = vec3(o.x, -o.z, o.y);
	if (hole_chord > 0.0 && length(d - hole_dir) < hole_chord) {
		discard;
	}
	if (hole2_chord > 0.0 && length(d - hole2_dir) < hole2_chord) {
		discard;
	}
	vec3 nw = normalize((MODEL_MATRIX * vec4(o, 0.0)).xyz);
	vec3 l = normalize(sun_dir);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize(CAMERA_POSITION_WORLD - wp);
	float ndl_g = dot(nw, l);
	float mu_g = clamp(dot(nw, v), 0.0, 1.0);
	bool lin = has_surf || kind == 2;
	vec3 alb;
	vec3 ns = nw;
	float wet = 0.0;
	float landm = 1.0;
	float cl = 0.0;
	float city_l = 0.0;
	if (has_surf) {
		vec4 s = surf_at(o, d);
		ns = normalize((MODEL_MATRIX * vec4(normalize(s.rgb * 2.0 - 1.0), 0.0)).xyz);
		float a = s.a;
		// 가까이서: 지도 한 칸보다 잔 밝기 무늬
		float kmpp = length(fwidth(d)) * r_km;
		float k = 1.0 - smoothstep(0.4, 4.0, kmpp);
		if (k > 0.0) {
			a += (fbm(d * (r_km / 1.5), 3, seed + 21.0) - 0.5) * 0.08 * k;
		}
		alb = pal_color(a) * bright;
		if (liq_th > 0.0) {
			wet = 1.0 - step(liq_th, s.a);
			alb = mix(alb, liq_col, wet);
			ns = mix(ns, nw, wet);
		}
	} else if (kind == 2) {
		// 지구: 해안 거리를 문턱으로 (픽셀마다 또렷한 해안), 바다는 대륙붕이 밝다
		float tk = max(length(fwidth(d)) * r_km, 1e-4);
		float sd = earth_sd(d, tk);
		landm = smoothstep(-tk * 0.5, tk * 0.5, sd);
		alb = mix(earth_sea(sd), earth_city(d, earth_ground(d, sd, seed), sd, tk, city_l), landm);
		wet = 1.0 - landm;
		float lat = asin(clamp(d.z, -1.0, 1.0));
		cl = fbm(d * vec3(4.0, 4.0, 6.0) + vec3(spin_h * 0.004, 0.0, 0.0), 5, seed + 9.0);
		cl = smoothstep(0.5, 0.75, cl + 0.12 * cos(lat * 6.0)) * 0.85 * cloud_k;
		alb = mix(alb, vec3(0.95), cl);
		wet *= 1.0 - cl;
	} else {
		alb = albedo(d) * bright;
	}
	float ndl = dot(ns, l);
	float mu = clamp(dot(ns, v), 0.0, 1.0);
	float diff = max(ndl, 0.0);
	if (has_surf && ls_k > 0.0) {
		diff = mix(diff, 2.0 * diff / max(diff + mu, 1e-3), ls_k);
	}
	if (has_surf) {
		// 밤 쪽 깊숙이서는 법선 지도가 빛을 새게 하지 않게
		diff *= smoothstep(-0.25, 0.0, ndl_g);
	}
	if (atmo.a > 0.0) {
		diff = mix(diff, smoothstep(-0.08, 0.45, ndl_g), lin ? min(0.6, atmo.a) : 0.6);
	}
	diff *= lit_k;
	if (kind == 4 || kind == 5 || kind == 6 || kind == 7) {
		diff *= 0.55 + 0.45 * pow(mu_g, 0.35);
	}
	vec3 col;
	if (lin) {
		// 선형 공간: 땅 조각이 받는 Godot 빛과 같은 식 (알베도 × (햇빛 + 주변광 + 반사광))
		vec3 al = to_lin(alb);
		vec3 c = al * (diff * 1.75 * sun_col + amb_light + fill_light * max(dot(ns, normalize(fill_dir)), 0.0)) + al * 0.002;
		if (wet > 0.0) {
			// 액체 면의 햇빛 반사
			vec3 h = normalize(l + v);
			float sp = pow(max(dot(nw, h), 0.0), 160.0) * 1.2 + pow(max(dot(nw, h), 0.0), 18.0) * 0.03;
			c += sun_col * lit_k * sp * wet * step(0.0, ndl_g);
		}
		if (kind == 2) {
			// 밤의 불빛: 대도시의 시가지 (도심일수록 밝게)와 잔 마을들
			float town = landm * smoothstep(0.78, 0.9, fbm(d * 70.0, 3, 4.0))
				* (1.0 - smoothstep(0.45, 1.15, abs(asin(clamp(d.z, -1.0, 1.0))))) * 0.12;
			float night = 1.0 - smoothstep(-0.2, 0.05, ndl_g);
			c += vec3(1.0, 0.6, 0.24) * (city_l * landm * 0.55 + town) * (1.0 - cl * 0.7) * night;
		}
		if (veil.a > 0.0) {
			// 짙은 대기: 멀리서는 땅이 연무 뒤로 흐릿하다
			vec3 haze = veil.rgb * (smoothstep(-0.1, 0.4, ndl_g) * 1.75 * lit_k * sun_col + amb_light);
			c = mix(c, haze, veil.a);
		}
		if (atmo.a > 0.0) {
			float rim = pow(1.0 - mu_g, 2.6) * atmo.a * smoothstep(-0.3, 0.35, ndl_g) * rim_k * lit_k;
			c += to_lin(atmo.rgb) * rim * 1.6;
		}
		if (air.a > 0.0) {
			// 장면의 지수 연무와 같은 식 (이 셰이더는 장면 연무를 받지 않는다 — 하늘의 다른 천체까지 흐려지지 않게)
			c = mix(c, to_lin(air.rgb), 1.0 - exp(-air.a * length(VERTEX)));
		}
		col = to_srgb(c);
	} else {
		col = alb * diff * 1.75 * sun_col + alb * 0.008;
		col += alb * (amb_light + fill_light * max(dot(ns, normalize(fill_dir)), 0.0));
		if (atmo.a > 0.0) {
			float rim = pow(1.0 - mu_g, 2.6) * atmo.a * smoothstep(-0.3, 0.35, ndl_g) * rim_k * lit_k;
			col += atmo.rgb * rim * 1.6;
		}
		if (air.a > 0.0) {
			col = mix(col, air.rgb, 1.0 - exp(-air.a * length(VERTEX)));
		}
	}
	ALBEDO = col;
}
