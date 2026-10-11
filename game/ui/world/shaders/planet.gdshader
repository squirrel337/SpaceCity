// 행성·위성: 스스로 계산하는 빛 (태양 방향 sun_dir, Godot 축). 겉모습은 kind로 고른다.
// 메시는 단위 구: 메시 좌표 (x, y, z) = 몸체 고정 (x, z, -y) — 몸체 z가 북극.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/planet_albedo.gdshaderinc"

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec4 atmo : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float bright = 1.0;
// 식민지의 지형 조각이 보이는 동안 그 자리를 비운다 (몸체 고정 방향, 단위 구의 현 길이)
uniform vec3 hole_dir = vec3(0.0, 0.0, 1.0);
uniform float hole_chord = 0.0;
// 식민지 가까이: 그 땅의 밤(시뮬레이션)이면 어둡게, 대기의 연무(rgb 색, a 렌더 단위당 밀도), 가장자리 빛 줄이기
uniform float lit_k = 1.0;
uniform vec4 air : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float rim_k = 1.0;
// 식민지 가까이: 장면의 주변광·반사광 (선형 색 × 세기) — 땅 조각이 받는 빛과 맞춘다
uniform vec3 sun_col = vec3(1.0);
uniform vec3 amb_light = vec3(0.0);
uniform vec3 fill_light = vec3(0.0);
uniform vec3 fill_dir = vec3(0.0, 1.0, 0.0);
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 o = normalize(obj);
	vec3 d = vec3(o.x, -o.z, o.y);
	if (hole_chord > 0.0 && length(d - hole_dir) < hole_chord) {
		discard;
	}
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
	diff *= lit_k;
	if (kind == 4 || kind == 5 || kind == 6 || kind == 7) {
		diff *= 0.55 + 0.45 * pow(mu, 0.35);
	}
	vec3 col = alb * diff * 1.75 * sun_col + alb * 0.008;
	col += alb * (amb_light + fill_light * max(dot(nw, normalize(fill_dir)), 0.0));
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
		float rim = pow(1.0 - mu, 2.6) * atmo.a * smoothstep(-0.3, 0.35, ndl) * rim_k * lit_k;
		col += atmo.rgb * rim * 1.6;
	}
	if (air.a > 0.0) {
		// 장면의 지수 연무와 같은 식 (이 셰이더는 장면 연무를 받지 않는다 — 하늘의 다른 천체까지 흐려지지 않게)
		col = mix(col, air.rgb, 1.0 - exp(-air.a * length(VERTEX)));
	}
	ALBEDO = col;
}
