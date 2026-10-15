// 노선의 띠: 점마다 두 꼭짓점(옆 −1·+1)을 화면에서 일정한 두께(px)로 벌린다. 천체 뒤편은 깊이로 가려진다.
// UV = 이웃 점의 x·y, UV2 = (이웃 점의 z, 옆 부호 × 반너비 px) — 마지막 점은 앞 점을 이웃으로 하고 부호를 뒤집는다.
// COLOR = 노선 색과 옅기. fade = 그 천체가 화면에서 보이는 정도 (가까이 내려가면 0).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float fade = 1.0;
uniform float px_scale = 1.0;      // 3D 화면의 픽셀 / 화면 위 픽셀 (해상도 단계)

varying vec4 v_col;

void vertex() {
	vec3 nb = vec3(UV, UV2.x);
	float sw = UV2.y;
	vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec4 c1 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(nb, 1.0));
	vec2 d = (c1.xy / max(abs(c1.w), 1e-9) - c0.xy / max(abs(c0.w), 1e-9)) * VIEWPORT_SIZE;
	float l = length(d);
	vec2 dir = l > 1e-6 ? d / l : vec2(1.0, 0.0);
	vec2 nrm = vec2(-dir.y, dir.x);
	c0.xy += nrm * sw * px_scale * 2.0 / VIEWPORT_SIZE * c0.w;
	POSITION = c0;
	v_col = COLOR;
}

void fragment() {
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * fade;
}
