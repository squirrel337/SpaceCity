// 달의 다른 부지(피어리·마리우스 …) 둘레의 지형 조각 높이 굽기 — 천체 높이는 달 구를 굽는 함수(moon_field)와 같다.
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/moon_surface.gdshaderinc"
#include "res://ui/world/shaders/moon_field.gdshaderinc"

float site_field(vec3 d, float texel_km, out float liq) {
	float fr;
	float mr;
	liq = 0.0;
	return height(d, fr, mr);
}

#include "res://ui/world/shaders/site_patch_bake.gdshaderinc"
