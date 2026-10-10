// 유리 돔·볼트, 도는 로터: 정점 색 알파 = 기본 투명도, 비스듬히 볼수록 진해진다
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALPHA = clamp(COLOR.a + f * 0.45, 0.0, 0.85);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = vec3(1.0, 0.8, 0.55) * night * 0.05;
}
