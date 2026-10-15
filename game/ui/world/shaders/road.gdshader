// 기지의 길: 종류마다 겉모습이 다르다 — 흙길(다진 흙·바퀴 자국), 도로(가운데 노란 점선·흰 가장자리선),
// 대로(차로 넷·가운데 분리대), 고속도로(넓은 갓길), 철도(자갈·침목·레일), 가압 통로(굽은 판·창의 불빛).
// UV.x = 가로(0~1), UV.y = 길이(m). UV2.x = 종류 + 10 × 부분 (0 길 띠, 1 교차로 판, 2 옆면, 3 통로 껍질),
// UV2.y = 그 띠의 길이 (끝에서 3 m 안은 건널목). 밤에는 가로등.
// 꼭짓점을 카메라 쪽으로 조금 당겨(화면 위치는 그대로) 깊이에서 땅보다 앞서게 한다 — 길이 지형에 묻히지 않게.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;
#include "res://ui/world/shaders/noise.gdshaderinc"

uniform float night = 0.0;
uniform float pull = 0.0012;           // 카메라 쪽으로 당기는 몫 (거리의 비율)

varying float v_type;
varying float v_part;
varying float v_len;

void vertex() {
	float code = UV2.x + 0.5;
	v_part = floor(code / 10.0);
	v_type = floor(code - v_part * 10.0);
	v_len = UV2.y;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX *= 1.0 - pull;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float line(float x, float c, float w) {
	float aa = fwidth(x) * 1.2 + 1e-4;
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - c));
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float n = vnoise(vec3(x * 6.0, y * 0.8, v_type), 3.0);
	float n2 = vnoise(vec3(x * 40.0, y * 6.0, v_type + 7.0), 5.0);
	vec3 col;
	float lamp = 0.0;
	float glow = 0.0;
	int t = int(v_type);
	if (v_part > 1.5 && v_part < 2.5) {
		// 옆면 (길의 두께, 둔덕)
		col = (t == 0 ? vec3(0.27, 0.24, 0.2) : vec3(0.3, 0.3, 0.31)) * (0.8 + 0.2 * n);
	} else if (t == 0) {
		// 흙길: 다진 흙, 바퀴 자국 두 줄
		vec3 dirt = mix(vec3(0.36, 0.32, 0.27), vec3(0.44, 0.4, 0.33), n);
		float ruts = (line(x, 0.3, 0.06) + line(x, 0.7, 0.06)) * (0.6 + 0.4 * n2);
		col = mix(dirt, dirt * 0.7, ruts * (1.0 - v_part));
	} else if (t == 5) {
		// 철도: 자갈, 침목(0.7 m마다), 레일 둘
		vec3 ballast = mix(vec3(0.3, 0.29, 0.27), vec3(0.46, 0.44, 0.4), n2);
		float sleeper = step(0.55, fract(y / 0.7)) * step(0.18, x) * step(x, 0.82);
		col = mix(ballast, vec3(0.24, 0.2, 0.17), sleeper);
		float rail = line(x, 0.36, 0.022) + line(x, 0.64, 0.022);
		col = mix(col, vec3(0.72, 0.72, 0.74), clamp(rail, 0.0, 1.0) * (1.0 - v_part));
	} else if (t == 4) {
		// 가압 통로의 바닥 (껍질 안쪽이라 거의 보이지 않는다)
		col = vec3(0.5, 0.52, 0.55);
	} else if (t == 6) {
		// 활주로: 밝은 포장, 가장자리 실선, 가운데 긴 점선, 양 끝 문턱 줄무늬
		vec3 conc = vec3(0.34, 0.34, 0.35) * (0.9 + 0.2 * n) + vec3(0.03) * n2;
		col = conc;
		vec3 white = vec3(0.9, 0.9, 0.88);
		float edge = line(x, 0.03, 0.008) + line(x, 0.97, 0.008);
		float center = line(x, 0.5, 0.006) * step(0.45, fract(y / 50.0));
		float to_end = min(y, v_len - y);
		float thr = step(0.5, fract(x * 16.0)) * step(8.0, to_end) * (1.0 - step(38.0, to_end)) * step(0.06, x) * step(x, 0.94);
		col = mix(col, white, clamp(edge + center + thr, 0.0, 1.0));
		lamp = (1.0 - smoothstep(0.0, 0.05, abs(fract(y / 30.0) - 0.5))) * (1.0 - smoothstep(0.01, 0.03, min(x, 1.0 - x)));
	} else {
		// 포장길: 도로(1)·대로(2)·고속도로(3)
		vec3 asphalt = vec3(0.17, 0.17, 0.18) * (0.88 + 0.24 * n) + vec3(0.04) * n2;
		col = asphalt;
		if (v_part < 0.5) {
			float edge = line(x, 0.05, 0.012) + line(x, 0.95, 0.012);
			vec3 white = vec3(0.86, 0.86, 0.82);
			vec3 yellow = vec3(0.92, 0.72, 0.22);
			col = mix(col, white, clamp(edge, 0.0, 1.0));
			if (t == 1) {
				float dash = step(0.5, fract(y / 6.0));
				col = mix(col, yellow, line(x, 0.5, 0.014) * dash);
			} else {
				// 차로 넷: 가운데 겹 노란 선(대로) 또는 분리대(고속도로), 차로 사이 흰 점선
				float lanes = (line(x, 0.275, 0.008) + line(x, 0.725, 0.008)) * step(0.55, fract(y / 9.0));
				col = mix(col, white, clamp(lanes, 0.0, 1.0));
				if (t == 2) {
					col = mix(col, yellow, clamp(line(x, 0.488, 0.006) + line(x, 0.512, 0.006), 0.0, 1.0));
				} else {
					float median = line(x, 0.5, 0.03);
					col = mix(col, vec3(0.42, 0.42, 0.4), median);
					float shoulder = 1.0 - smoothstep(0.08, 0.1, min(x, 1.0 - x));
					col = mix(col, asphalt * 1.25, shoulder * 0.6);
				}
			}
			// 교차로에 닿는 끝: 건널목 (흰 줄무늬)
			float to_end = min(y, v_len - y);
			float zebra = step(0.5, fract(x * 9.0)) * (1.0 - smoothstep(2.6, 3.0, to_end)) * step(0.6, to_end)
				* step(0.08, x) * step(x, 0.92);
			col = mix(col, white, zebra * 0.85);
		}
		// 가로등: 가장자리에 15 m마다
		lamp = (1.0 - smoothstep(0.0, 0.07, abs(fract(y / 15.0) - 0.5))) * (1.0 - smoothstep(0.04, 0.09, min(x, 1.0 - x)));
	}
	if (v_part > 2.5) {
		// 가압 통로 껍질: 흰 판, 4 m마다 이음 고리, 옆구리 창 띠 (밤에 켜진다)
		float ring = line(fract(y / 4.0), 0.5, 0.04);
		float win = line(x, 0.3, 0.035) + line(x, 0.7, 0.035);
		float pane = step(0.25, fract(y / 1.6));
		col = mix(vec3(0.78, 0.79, 0.8), vec3(0.55, 0.56, 0.58), ring) * (0.92 + 0.08 * n);
		col = mix(col, vec3(0.16, 0.2, 0.26), clamp(win, 0.0, 1.0) * pane);
		glow = clamp(win, 0.0, 1.0) * pane;
	}
	ALBEDO = col;
	ROUGHNESS = v_part > 2.5 ? 0.45 : 1.0;
	SPECULAR = v_part > 2.5 ? 0.35 : 0.1;
	EMISSION = vec3(1.0, 0.68, 0.32) * night * lamp * 3.0 + vec3(0.9, 0.85, 0.7) * night * glow * 1.4;
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	DIFFUSE_LIGHT += mix(mu0, ls, 0.5) * ATTENUATION * LIGHT_COLOR / PI;
}
