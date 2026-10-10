// 가리킨 건물 아래의 고리
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never, blend_add;

uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.3, 1.0);

void fragment() {
	float d = abs(UV.x - 0.5) * 2.0;
	ALBEDO = tint.rgb * (1.0 - d) * 0.9;
}
