// 건물·탈것 몸체: 정점 색(선형) = 바탕색, UV.x = 광택, UV2 = 밤에 빛나는 색(r·g, b·세기를 0~255 정수로 묶음)
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;
varying flat vec4 emis;

void vertex() {
	float r = floor(UV2.x / 256.0);
	float g = UV2.x - r * 256.0;
	float b = floor(UV2.y / 256.0);
	float s = UV2.y - b * 256.0;
	emis = vec4(r, g, b, s) / 255.0;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	float gl = UV.x;
	ROUGHNESS = mix(0.92, 0.3, gl);
	METALLIC = gl * 0.2;
	SPECULAR = 0.3 + 0.35 * gl;
	EMISSION = emis.rgb * emis.a * (0.04 + 0.96 * night) * 2.2;
}
