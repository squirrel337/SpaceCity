// 기지의 길: 다진 레골리스, 가장자리 띠, 가운데 점선. UV.x = 가로(0~1), UV.y = 길이(m). 밤에는 가장자리 등
shader_type spatial;
render_mode cull_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform float night = 0.0;

void fragment() {
	float x = abs(UV.x - 0.5);
	float edge = smoothstep(0.40, 0.45, x) * (1.0 - smoothstep(0.48, 0.5, x));
	float dash = step(0.55, fract(UV.y / 7.0)) * (1.0 - smoothstep(0.015, 0.03, x));
	float n = vnoise(vec3(UV.x * 6.0, UV.y * 0.8, 0.0), 3.0);
	vec3 base = vec3(0.24, 0.235, 0.225) * (0.9 + 0.2 * n);
	ALBEDO = mix(base, vec3(0.62, 0.58, 0.5), edge * 0.6 + dash * 0.55);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	float lamp = edge * (1.0 - smoothstep(0.0, 0.08, abs(fract(UV.y / 12.0) - 0.5)));
	EMISSION = vec3(1.0, 0.68, 0.32) * night * lamp * 3.0;
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	DIFFUSE_LIGHT += mix(mu0, ls, 0.5) * ATTENUATION * LIGHT_COLOR / PI;
}
