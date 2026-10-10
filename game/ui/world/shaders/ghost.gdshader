// 자리 고르기의 유령 건물: 모형의 색을 반쯤 살린 반투명. 놓을 수 있으면 초록, 없으면 빨강 (tint)
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled, depth_draw_always, blend_mix;

uniform vec4 tint : source_color = vec4(0.35, 0.95, 0.55, 0.55);

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	vec3 c = mix(COLOR.rgb, tint.rgb, 0.62);
	ALBEDO = c * (0.8 + 0.6 * rim);
	ALPHA = tint.a;
}
