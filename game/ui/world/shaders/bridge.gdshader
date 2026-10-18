// 대도시의 다리 (metro_city.gd) — 단위 상자의 MultiMesh. 인스턴스 색 그대로 (콘크리트 상판·교각·주탑, 아스팔트 길),
// INSTANCE_CUSTOM.r = 밤에 빛나는 몫 (다리 위 길: 가로등 빛)
shader_type spatial;
render_mode cull_back;

uniform float night = 0.0;
varying vec3 v_col;
varying float v_glow;

void vertex() {
	v_col = COLOR.rgb;
	v_glow = INSTANCE_CUSTOM.r;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	EMISSION = vec3(1.0, 0.68, 0.34) * v_glow * night * 0.5;
}
