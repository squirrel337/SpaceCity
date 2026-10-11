// 지구 도시 둘레의 지형 조각 높이 굽기 — 땅·바다는 구와 같은 해안 거리 지도(earth_surface), 땅은 해안에서 천천히 오른다.
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/earth_surface.gdshaderinc"

float site_field(vec3 d, float texel_km, out float liq) {
	return earth_h(d, texel_km, liq);
}

#include "res://ui/world/shaders/site_patch_bake.gdshaderinc"
