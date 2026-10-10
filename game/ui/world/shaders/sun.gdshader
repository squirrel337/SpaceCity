// 태양 원반: 스스로 빛나고 가장자리가 어둡다 (주연 감광), 쌀알 무늬
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float spin_h = 0.0;
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 o = normalize(obj);
	vec3 n = normalize((MODEL_MATRIX * vec4(o, 0.0)).xyz);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 v = normalize(CAMERA_POSITION_WORLD - wp);
	float mu = clamp(dot(n, v), 0.0, 1.0);
	float limb = 0.3 + 0.7 * pow(mu, 0.6);
	float gran = fbm(o * 40.0, 3, 5.0);
	float spots = smoothstep(0.78, 0.86, fbm(o * 6.0 + vec3(spin_h * 0.001), 3, 9.0));
	vec3 col = mix(vec3(1.0, 0.62, 0.30), vec3(1.0, 0.93, 0.80), pow(mu, 0.5));
	col *= limb * (0.9 + 0.2 * gran) * (1.0 - 0.55 * spots);
	ALBEDO = col * 3.2;
}
