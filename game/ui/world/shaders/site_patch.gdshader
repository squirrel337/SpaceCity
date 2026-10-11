// 다른 천체 식민지 둘레의 지형 조각 (반지름 60 km). 높이는 CPU가 꼭짓점에 넣었다 (SiteSurface).
// 색 = 그 천체 구와 같은 알베도(planet_albedo) × 꼭짓점 색의 상대 무늬 — 가장자리로 갈수록 무늬가 옅어져 구와 이어진다.
// 메시 좌표 = 모형 (x, z, -y): x·y 수평, z 위, 원점 = 기지 평지. 햇빛은 장면의 빛을 받는다 (건물 그림자).
shader_type spatial;
render_mode cull_back, diffuse_lambert;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/planet_albedo.gdshaderinc"

uniform float bright = 1.0;
uniform vec3 site_dir = vec3(0.0, 0.0, -1.0);   // 기지 평지 (몸체 고정 단위 벡터)
uniform mat3 site_basis;                         // 모형 x, y, z → 몸체 고정
uniform float radius_m = 1000000.0;
uniform vec3 base_srgb = vec3(0.5);              // 꼭짓점 색의 바탕 (sRGB) — 상대 무늬의 1
uniform vec4 ice_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);   // 얼음·서리 (꼭짓점 색 a가 그 몫)
uniform float patch_m = 60000.0;
varying vec3 bdir;
varying float rr;

void vertex() {
	vec2 p = vec2(VERTEX.x, -VERTEX.z);
	bdir = normalize(site_dir * radius_m + site_basis * vec3(p, 0.0));
	rr = length(p);
}

void fragment() {
	vec3 planet = albedo(bdir) * bright;
	// 무늬는 밝기 비 위주로 (색 비는 조금만) — 어두운 바탕에서 밝은 색이 하얗게 타지 않게 0.45..1.35로 묶는다
	vec3 c = max(COLOR.rgb, vec3(0.0));
	vec3 w = vec3(0.299, 0.587, 0.114);
	float lum = dot(c, w) / max(dot(base_srgb, w), 0.02);
	vec3 ratio = c / max(base_srgb, vec3(0.02));
	vec3 rel = pow(clamp(mix(vec3(lum), ratio, 0.35), vec3(0.45), vec3(1.35)), vec3(2.2));
	float far = smoothstep(patch_m * 0.3, patch_m * 0.9, rr);
	vec3 alb = planet * mix(rel, vec3(1.0), far);
	alb = mix(alb, ice_color.rgb, clamp(COLOR.a, 0.0, 1.0) * (1.0 - far));
	ALBEDO = clamp(alb, vec3(0.0), vec3(1.0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
