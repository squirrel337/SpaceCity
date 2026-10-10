// 은하수: 하늘 구 안쪽 면. 은하 북극·중심 방향(Godot 축)으로 띠와 팽대부, 먼지 띠를 그린다
shader_type spatial;
render_mode blend_add, unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform vec3 gal_north = vec3(0.0, 1.0, 0.0);
uniform vec3 gal_center = vec3(1.0, 0.0, 0.0);
uniform float gain = 1.0;
varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 east = normalize(cross(gal_north, gal_center));
	float b = asin(clamp(dot(d, gal_north), -1.0, 1.0));
	float l = atan(dot(d, east), dot(d, gal_center));
	float width = 0.11 + 0.10 * exp(-l * l / 0.9);
	float n1 = fbm(d * 7.0, 5, 3.0);
	float n2 = fbm(d * 22.0, 3, 7.0);
	float band = exp(-pow(b / (width * (0.75 + 0.6 * n1)), 2.0));
	float bulge = exp(-l * l / 0.22 - b * b / 0.035);
	float rift = exp(-pow((b - 0.025 - 0.03 * (n2 - 0.5)) / 0.03, 2.0)) * smoothstep(1.6, 0.2, abs(l)) * smoothstep(0.35, 0.65, n2);
	float glow = band * (0.45 + 0.9 * n1 * n2) * (1.0 - 0.75 * rift) + bulge * 0.9;
	vec3 col = mix(vec3(0.62, 0.66, 0.78), vec3(0.95, 0.82, 0.62), clamp(bulge * 1.4 + band * 0.25, 0.0, 1.0));
	ALBEDO = col * glow * 0.075 * gain;
}
