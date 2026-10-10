// 달 표면을 정육면체 지도 한 면에 굽는다 (시작할 때 한 번). RGB = 표면 법선(메시 좌표), A = 밝기.
// 높이: 바다(낮은 평원), 큰 크레이터, 남극 크레이터·산, 여러 겹의 작은 크레이터 무늬.
shader_type canvas_item;
render_mode blend_disabled, unshaded;
#include "res://ui/world/shaders/noise.gdshaderinc"
#include "res://ui/world/shaders/moon_surface.gdshaderinc"

uniform int face = 0;
uniform float texel = 0.0015;      // 한 칸의 각 크기 (라디안)
uniform int mode = 0;              // 0: 정육면체 한 면, 1: 남극 둘레 (방위 등거리, 반지름 cap_rad)
uniform float cap_rad = 0.2;
#include "res://ui/world/shaders/moon_field.gdshaderinc"

void fragment() {
	vec3 g;
	vec3 d;
	if (mode == 1) {
		vec2 q = (UV - 0.5) * 2.0;
		float rho = length(q) * cap_rad;
		float ph = atan(q.y, q.x);
		d = vec3(sin(rho) * cos(ph), sin(rho) * sin(ph), -cos(rho));
	} else {
		g = face_dir(face, UV);
		d = vec3(g.x, -g.z, g.y);
	}
	vec3 t1 = normalize(cross(abs(d.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0), d));
	vec3 t2 = cross(d, t1);
	float e = texel * 0.8;
	float fr;
	float mr;
	float fr1;
	float mr1;
	float h0 = height(d, fr, mr);
	vec3 d1 = normalize(d + t1 * e);
	vec3 d2 = normalize(d + t2 * e);
	float h1 = height(d1, fr1, mr1);
	float h2 = height(d2, fr1, mr1);
	vec3 p0 = d * (MOON_R + h0);
	vec3 p1 = d1 * (MOON_R + h1);
	vec3 p2 = d2 * (MOON_R + h2);
	vec3 n = normalize(cross(p1 - p0, p2 - p0));
	if (dot(n, d) < 0.0) {
		n = -n;
	}
	float a = albedo(d, fr, mr);
	vec3 ng = vec3(n.x, n.z, -n.y);
	COLOR = vec4(ng * 0.5 + 0.5, a);
}
