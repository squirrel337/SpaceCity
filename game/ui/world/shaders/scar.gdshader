// 땅에 깐 표시 (EventsView): 재난의 자국(분출물 광조·금·먼지 띠·그을음·서리)과 탐사지 고리.
// 색 = 꼭짓점 색 (a = 덮는 몫), fade로 옅어진다. 해가 낮게 뜬 극지에서도 보이도록 빛을 받지 않고 light(낮 1 · 밤 낮게)만 곱한다.
// 구역 판처럼 깊이를 쓰지 않고 땅 위에 섞는다
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float fade = 1.0;
uniform float light = 1.0;
uniform float glow = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb * max(light, glow);
	ALPHA = COLOR.a * fade;
}
