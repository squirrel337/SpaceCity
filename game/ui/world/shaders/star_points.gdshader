// 하늘의 별: 네 꼭짓점이 한 방향에 모여 있고 화면에서 UV2.x px 반지름으로 펼친다. 색 알파 = 밝기
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float gain = 1.0;
varying float px;

void vertex() {
	px = UV2.x + 1.0;
	vec4 c = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	c.xy += (UV * 2.0 - 1.0) * px * 2.0 / VIEWPORT_SIZE * c.w;
	POSITION = c;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0) * px;
	float r = max(px - 1.0, 0.6);
	float k = exp(-d * d / (0.55 * r * r));
	ALBEDO = COLOR.rgb * COLOR.a * k * gain;
}
