// 태양 빛무리: 화면을 향하는 판, 더하기 혼합
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float a = atan(q.y, q.x);
	float rays = 0.5 + 0.5 * cos(a * 6.0) * cos(a * 2.0 + 1.3);
	float halo = exp(-d * 9.0) * 0.9 + exp(-d * 3.2) * 0.16 * (0.75 + 0.25 * rays);
	float core = exp(-d * d * 220.0) * 3.0;
	vec3 col = vec3(1.0, 0.86, 0.66) * halo * strength + vec3(1.0, 0.97, 0.92) * core;
	ALBEDO = col * (1.0 - smoothstep(0.8, 1.0, d));
}
