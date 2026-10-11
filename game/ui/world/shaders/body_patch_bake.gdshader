// 암석·얼음 천체 도시 둘레의 지형 조각 높이 굽기 — 천체 높이는 구를 굽는 함수(body_field)와 같다.
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/body_field.gdshaderinc"

float site_field(vec3 d, float texel_km, out float liq) {
	float h;
	float a;
	body_eval(d, texel_km, h, a, liq);
	return h;
}

#include "res://ui/world/shaders/site_patch_bake.gdshaderinc"
