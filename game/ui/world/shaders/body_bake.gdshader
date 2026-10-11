// 암석·얼음 천체의 겉모습을 굽는다: RGB = 표면 법선(메시 좌표), A = 밝기(팔레트 좌표).
// mode 0: 정육면체 지도 한 면, mode 1: 도시 둘레 지역 (방위 등거리, 중심 cap_dir, 반지름 cap_rad — 더 곱게).
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/body_field.gdshaderinc"

uniform int face = 0;
uniform float texel = 0.0015;      // 한 칸의 각 크기 (라디안)
uniform int mode = 0;
uniform float cap_rad = 0.1;
uniform vec3 cap_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 cap_e1 = vec3(1.0, 0.0, 0.0);
uniform vec3 cap_e2 = vec3(0.0, 1.0, 0.0);

vec3 face_dir(int f, vec2 uv) {
	float s = uv.x * 2.0 - 1.0;
	float t = uv.y * 2.0 - 1.0;
	if (f == 0) return normalize(vec3(1.0, -t, -s));
	if (f == 1) return normalize(vec3(-1.0, -t, s));
	if (f == 2) return normalize(vec3(s, 1.0, t));
	if (f == 3) return normalize(vec3(s, -1.0, -t));
	if (f == 4) return normalize(vec3(s, -t, 1.0));
	return normalize(vec3(-s, -t, -1.0));
}

void fragment() {
	vec3 d;
	if (mode == 1) {
		vec2 q = (UV - 0.5) * 2.0;
		float rho = length(q) * cap_rad;
		float ph = atan(q.y, q.x);
		d = normalize(cap_dir * cos(rho) + (cap_e1 * cos(ph) + cap_e2 * sin(ph)) * sin(rho));
	} else {
		vec3 g = face_dir(face, UV);
		d = vec3(g.x, -g.z, g.y);
	}
	vec3 t1 = normalize(cross(abs(d.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0), d));
	vec3 t2 = cross(d, t1);
	float e = texel * 0.8;
	float tk = texel * body_r;
	float h0;
	float h1;
	float h2;
	float a0;
	float a1;
	float l0;
	float l1;
	body_eval(d, tk, h0, a0, l0);
	vec3 d1 = normalize(d + t1 * e);
	vec3 d2 = normalize(d + t2 * e);
	body_eval(d1, tk, h1, a1, l1);
	body_eval(d2, tk, h2, a1, l1);
	vec3 p0 = d * (body_r + h0);
	vec3 p1 = d1 * (body_r + h1);
	vec3 p2 = d2 * (body_r + h2);
	vec3 n = normalize(cross(p1 - p0, p2 - p0));
	if (dot(n, d) < 0.0) {
		n = -n;
	}
	vec3 ng = vec3(n.x, n.z, -n.y);
	COLOR = vec4(ng * 0.5 + 0.5, a0);
}
