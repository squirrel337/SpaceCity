// 우리 은하의 별 구름: 별 하나 = 한 점에 모인 네 꼭짓점 (UV = 모서리, UV2.x = 반지름 px, 색 알파 = 밝기).
// 꼭짓점은 은하 중심 기준 (광년, 황도 x·y·z). 렌더 좌표의 로그 축척은 여기서 셈한다 (WorldView._compress와 같다).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 origin_rel;          // 은하 중심 − 카메라 (km, 황도)
uniform float ly_km = 9.4607304725808e12;
uniform float local_km = 1.0;
uniform float shell_k = 0.32;
uniform float unit_km = 1.0;
uniform float gain = 1.0;
uniform float px_scale = 1.0;
varying float px;

vec3 to_render(vec3 rel) {
	float d = max(length(rel), 1e-9);
	float c = d <= local_km ? d : local_km * (1.0 + shell_k * log(d / local_km));
	float k = c / d / unit_km;
	return vec3(rel.x, rel.z, -rel.y) * k;
}

void vertex() {
	vec3 r = to_render(origin_rel + VERTEX * ly_km);
	px = UV2.x * px_scale + 1.0;
	vec4 c = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(r, 1.0));
	c.xy += (UV * 2.0 - 1.0) * px * 2.0 / VIEWPORT_SIZE * c.w;
	POSITION = c;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0) * px;
	float r = max(px - 1.0, 0.6);
	float k = exp(-d * d / (0.55 * r * r));
	ALBEDO = COLOR.rgb * COLOR.a * k * gain;
}
