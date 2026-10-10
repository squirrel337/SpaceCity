// 달 표면 높이 — 남극의 큰 크레이터와 산 (구 굽기와 지형 조각이 같은 함수를 쓴다)
// 방향 d: 달 고정 좌표 단위 벡터 (x: 경도 0, y: 경도 90°E, z: 북극). 거리·높이: km.

const float MOON_R = 1737.4;
const float PI_M = 3.14159265359;

uniform vec4 pol_c[16];   // xyz: 중심 방향, w: 반지름 km (산이면 너비)
uniform vec4 pol_p[16];   // x: 깊이(산: 높이) km, y: 테두리 높이 km, z: 바닥 반지름 비율, w: 1이면 산
uniform int pol_n = 0;

// 그릇 모양 크레이터 단면: 바닥 → 코사인 벽 → 둥근 테두리 → 바깥으로 빠르게 낮아지는 분출물
float crater_shape(float rho, float R, float depth, float rim, float floor_f) {
	if (rho < R) {
		float rf = R * floor_f;
		float t = clamp((rho - rf) / max(R - rf, 1e-4), 0.0, 1.0);
		return rim - depth * 0.5 * (1.0 + cos(PI_M * t));
	}
	float q = R / rho;
	return rim * q * q * q * (1.0 - smoothstep(2.5 * R, 4.0 * R, rho));
}

float polar_height(vec3 d) {
	float h = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= pol_n) {
			break;
		}
		float rho = length(d - pol_c[i].xyz) * MOON_R;
		float R = pol_c[i].w;
		if (rho > R * 4.0) {
			continue;
		}
		if (pol_p[i].w > 0.5) {
			float s = R * 0.5;
			h += pol_p[i].x * exp(-rho * rho / (s * s));
		} else {
			h += crater_shape(rho, R, pol_p[i].x, pol_p[i].y, pol_p[i].z);
		}
	}
	return h;
}
