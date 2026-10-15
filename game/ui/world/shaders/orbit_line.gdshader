// 행성·위성의 궤도선: 꼭짓점 = 궤도 중심(태양·모행성) 기준 점 (km, 황도 x·y·z). 렌더 좌표의 축척 —
// 가까우면 그대로, local_km보다 멀면 거리의 로그로 줄인 껍질 (WorldView._compress) — 을 여기서 셈한다.
// UV·UV2.x = 이웃 점, UV2.y = 옆 부호 × 반너비 px (띠를 화면에서 일정한 두께로).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 origin_rel;          // 궤도 중심 − 카메라 (km, 황도)
uniform float local_km = 1.0;
uniform float shell_k = 0.32;
uniform float unit_km = 1.0;
uniform vec4 color : source_color = vec4(1.0);
uniform float px_scale = 1.0;

vec3 to_render(vec3 rel) {
	float d = max(length(rel), 1e-9);
	float c = d <= local_km ? d : local_km * (1.0 + shell_k * log(d / local_km));
	float k = c / d / unit_km;
	return vec3(rel.x, rel.z, -rel.y) * k;
}

void vertex() {
	vec3 r0 = to_render(origin_rel + VERTEX);
	vec3 r1 = to_render(origin_rel + vec3(UV, UV2.x));
	vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(r0, 1.0));
	vec4 c1 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(r1, 1.0));
	vec2 d = (c1.xy / max(abs(c1.w), 1e-9) - c0.xy / max(abs(c0.w), 1e-9)) * VIEWPORT_SIZE;
	float l = length(d);
	vec2 dir = l > 1e-6 ? d / l : vec2(1.0, 0.0);
	vec2 nrm = vec2(-dir.y, dir.x);
	c0.xy += nrm * UV2.y * px_scale * 2.0 / VIEWPORT_SIZE * c0.w;
	POSITION = c0;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
