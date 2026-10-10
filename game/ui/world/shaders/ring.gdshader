// 토성 고리: UV.x = 행성 반지름 단위의 거리. 행성 그림자를 받는다
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
varying vec3 wpos;
varying vec3 pc;
varying float pr;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pc = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	pr = length(MODEL_MATRIX[0].xyz);
}

float density(float r) {
	float d = 0.0;
	d += smoothstep(1.28, 1.30, r) * (1.0 - smoothstep(1.565, 1.585, r)) * 0.2;
	d += smoothstep(1.575, 1.60, r) * (1.0 - smoothstep(2.012, 2.025, r)) * (0.78 + 0.16 * sin(r * 95.0));
	d += smoothstep(2.09, 2.105, r) * (1.0 - smoothstep(2.335, 2.35, r)) * 0.55;
	d *= 1.0 - (smoothstep(2.286, 2.289, r) - smoothstep(2.295, 2.298, r));
	d *= 0.86 + 0.14 * sin(r * 340.0) * sin(r * 77.0);
	return clamp(d, 0.0, 1.0);
}

void fragment() {
	float r = UV.x;
	float dens = density(r);
	vec3 col = mix(vec3(0.55, 0.50, 0.43), vec3(0.88, 0.82, 0.70), smoothstep(1.5, 1.95, r));
	vec3 l = normalize(sun_dir);
	vec3 rel = wpos - pc;
	float along = dot(rel, l);
	float perp = length(rel - l * along);
	float lit = (along < 0.0 && perp < pr) ? 0.06 : 1.0;
	ALBEDO = col * (0.2 + 1.35 * lit);
	ALPHA = dens * 0.92;
}
