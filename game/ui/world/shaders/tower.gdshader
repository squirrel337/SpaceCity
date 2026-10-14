// 대도시의 건물: 단위 상자 하나를 MultiMesh로 늘려 쓴다. 셰이더가 층·창·유리 외벽·지붕을 그리고, 밤에는 창이 켜진다.
// 인스턴스 색 = 외벽 색 (a = 유리 몫), INSTANCE_CUSTOM = (높이 m, 너비 m, 깊이 m, 씨앗).
// UV = 면 안의 (가로 0~1, 세로 0~1), UV2.x = 면 (0 너비 쪽, 1 깊이 쪽, 2 지붕)
shader_type spatial;
render_mode cull_back;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform float night = 0.0;

varying vec4 v_col;
varying vec4 v_dim;
varying float v_face;

void vertex() {
	v_col = COLOR;
	v_dim = INSTANCE_CUSTOM;
	v_face = UV2.x;
}

void fragment() {
	float h = max(v_dim.x, 1.0);
	float fw = v_face < 0.5 ? v_dim.y : v_dim.z;
	float seed = v_dim.w;
	vec3 wall = v_col.rgb;
	float glass_k = v_col.a;
	if (v_face > 1.5) {
		// 지붕: 외벽보다 어둡고 설비가 얹힌 얼룩
		float n = vnoise(vec3(UV * 6.0, seed), 5.0);
		ALBEDO = wall * (0.55 + 0.2 * n);
		ROUGHNESS = 0.95;
		EMISSION = vec3(0.0);
	} else {
		vec2 cells = vec2(max(1.0, floor(fw / 3.3)), max(1.0, floor(h / 3.5)));
		vec2 g = UV * cells;
		vec2 f = fract(g);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.26, f.y) * step(f.y, 0.88);
		float aa = length(fwidth(g));
		float wm = mix(win, 0.42, smoothstep(0.3, 0.9, aa));      // 창이 화면에서 작으면 평균으로
		// 유리 외벽: 하늘빛이 비친 어두운 청회색, 위로 갈수록 밝게
		vec3 glass = mix(vec3(0.12, 0.16, 0.21), vec3(0.42, 0.52, 0.6), clamp(UV.y * 0.6 + 0.2, 0.0, 1.0));
		vec3 frame_c = mix(wall, vec3(0.2, 0.22, 0.25), glass_k * 0.7);
		ALBEDO = mix(frame_c, glass, clamp(wm * (0.45 + glass_k * 0.55) + glass_k * 0.25, 0.0, 1.0));
		ROUGHNESS = mix(0.85, 0.25, wm * glass_k);
		METALLIC = 0.0;
		// 밤: 창마다 켜졌나 (층·칸의 해시)
		float r = hash1(vec3(floor(g), seed * 131.0 + v_face * 17.0), 9.0);
		float lit = step(0.5 + 0.18 * (1.0 - glass_k), r) * win;
		float far_lit = 0.36 * smoothstep(0.3, 0.9, aa);
		vec3 lamp = mix(vec3(1.0, 0.74, 0.42), vec3(0.85, 0.92, 1.0), step(0.85, r));
		EMISSION = lamp * mix(lit, far_lit, smoothstep(0.3, 0.9, aa)) * night * 0.85;
	}
}
