// 땅에 깔리는 표시: 건물 바닥 칸, 길 미리보기, 태양광 타워의 일조 구역. 색 = tint × 꼭짓점 색
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = tint.a * COLOR.a;
}
