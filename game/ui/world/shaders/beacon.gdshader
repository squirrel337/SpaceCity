// 대도시의 우주 시설 위로 솟는 빛기둥 — 멀리서도 시설 자리가 보이게. 위로 갈수록 옅어지고, 밤에 더 밝다.
// 메시는 원뿔대 (CylinderMesh, 가운데가 원점, 높이 height). 짓는 중이면 깜박인다.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float height = 700.0;
uniform float night = 0.0;
uniform float blink = 0.0;
varying float v_up;

void vertex() {
	v_up = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float k = (1.0 - v_up) * (1.0 - v_up) * edge * mix(0.35, 1.0, night);
	k *= 1.0 - blink * (0.5 + 0.5 * sin(TIME * 4.0));
	ALBEDO = color.rgb * k * 1.6;
	ALPHA = k;
}
