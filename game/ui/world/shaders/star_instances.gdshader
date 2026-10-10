// 이웃 항성계: 메시의 별 i(UV2.x)마다 위치·크기(spos: xyz 렌더 좌표, w 반지름 px)와 빛(scol: rgb, a 밝기)
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 spos[64];
uniform vec4 scol[64];
uniform int count = 0;
uniform float gain = 1.0;
varying float px;
varying vec4 col;

void vertex() {
	int i = int(UV2.x + 0.5);
	px = spos[i].w + 1.0;
	col = scol[i];
	vec4 c = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(spos[i].xyz, 1.0));
	c.xy += (UV * 2.0 - 1.0) * px * 2.0 / VIEWPORT_SIZE * c.w;
	if (i >= count) {
		c = vec4(2.0, 2.0, 2.0, 1.0);
	}
	POSITION = c;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0) * px;
	float r = max(px - 1.0, 0.6);
	float k = exp(-d * d / (0.5 * r * r)) + 0.25 * exp(-d / max(r, 1.0) * 1.6);
	ALBEDO = col.rgb * col.a * k * gain;
}
