// 기지의 구역 판: 다진 바닥(옅은 구역 색), 구역 테두리, 필지 금, 줄 사이 보행로, 가운데 광장.
// 색 = 꼭짓점 색 (a = 덮는 몫). UV.x > 0.5인 테두리는 밤에 은은히 빛난다 (구역 경계등)
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float night = 0.0;

varying float glow;

void vertex() {
	glow = UV.x;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = COLOR.rgb * night * step(0.5, glow) * 0.9;
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	DIFFUSE_LIGHT += mix(mu0, ls, 0.5) * ATTENUATION * LIGHT_COLOR / PI;
}
