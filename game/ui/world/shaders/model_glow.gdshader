// 밤의 불빛: 더하기 혼합. UV2.x > 0이면 한 점에 모인 네 꼭짓점을 화면 쪽으로 펼친 번짐(반지름 UV2.x m)
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float night : hint_range(0.0, 1.0) = 0.0;
varying float bb;

void vertex() {
	bb = UV2.x;
	if (UV2.x > 0.0) {
		vec4 vc = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float sc = length(MODELVIEW_MATRIX[0].xyz);
		vc.xy += (UV * 2.0 - 1.0) * UV2.x * sc;
		vc.z += UV2.x * sc * 0.6;
		POSITION = PROJECTION_MATRIX * vc;
	}
}

void fragment() {
	float k = 1.0;
	if (bb > 0.0) {
		float d = length(UV * 2.0 - 1.0);
		k = exp(-d * d * 3.5) * (1.0 - smoothstep(0.75, 1.0, d));
	}
	ALBEDO = COLOR.rgb * COLOR.a * k * night;
}
