// 노선 위를 가는 탈것 표시 (멀티메시 하나에 여럿): 인스턴스 자리에 화면 크기가 일정한 표를 세우고, 가는 쪽으로 돌린다.
// INSTANCE_CUSTOM.xyz = 조금 뒤의 자리 − 지금 자리 (천체 메시 좌표), .w = 모양 (0 세모 비행기, 1 네모 열차, 2 동그라미 호퍼)
// COLOR = 색과 옅기. 메시는 2×2 사각형 (VERTEX.xy = −1~1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float fade = 1.0;
uniform float size_px = 5.0;
uniform float px_scale = 1.0;

varying vec4 v_col;
varying vec2 v_q;
varying float v_kind;

void vertex() {
	vec4 c0 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vec4 c1 = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 1.0));
	vec2 d = (c1.xy / max(abs(c1.w), 1e-9) - c0.xy / max(abs(c0.w), 1e-9)) * VIEWPORT_SIZE;
	float l = length(d);
	vec2 dir = l > 1e-6 ? d / l : vec2(1.0, 0.0);
	vec2 nrm = vec2(-dir.y, dir.x);
	vec2 off = (dir * VERTEX.x + nrm * VERTEX.y) * size_px * px_scale;
	c0.xy += off * 2.0 / VIEWPORT_SIZE * c0.w;
	POSITION = c0;
	v_col = COLOR;
	v_q = VERTEX.xy;
	v_kind = INSTANCE_CUSTOM.w;
}

// 모양의 부호 거리 (안 < 0): 세모(앞이 +x), 네모, 동그라미
float shape(vec2 q, float kind) {
	if (kind < 0.5) {
		vec2 a = vec2(1.0, 0.0);
		vec2 b = vec2(-0.8, 0.72);
		vec2 c = vec2(-0.8, -0.72);
		float e0 = dot(q - a, normalize(vec2(b.y - a.y, a.x - b.x)));
		float e1 = dot(q - b, normalize(vec2(c.y - b.y, b.x - c.x)));
		float e2 = dot(q - c, normalize(vec2(a.y - c.y, c.x - a.x)));
		return max(max(e0, e1), e2);
	}
	if (kind < 1.5) {
		vec2 dq = abs(q) - vec2(0.62);
		return max(dq.x, dq.y);
	}
	return length(q) - 0.7;
}

void fragment() {
	float s = shape(v_q, v_kind);
	float aa = fwidth(s);
	float body = 1.0 - smoothstep(-aa, aa, s);
	float ring = 1.0 - smoothstep(-aa, aa, s - 0.22);
	vec3 col = mix(vec3(0.03, 0.04, 0.06), v_col.rgb, body);
	ALBEDO = col;
	ALPHA = ring * v_col.a * fade;
}
