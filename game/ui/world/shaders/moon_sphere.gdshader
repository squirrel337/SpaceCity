// 달 구: 구운 정육면체 지도(법선 + 밝기)로 그린다. 기지 둘레(지형 조각이 있는 곳)는 비운다.
shader_type spatial;
render_mode cull_back;

uniform samplerCube surf : filter_linear_mipmap;
uniform bool has_surf = false;
uniform sampler2D cap : filter_linear_mipmap, repeat_disable;   // 남극 둘레를 더 곱게 구운 것
uniform bool has_cap = false;
uniform float cap_rad = 0.2;
uniform vec3 hole_dir = vec3(0.0, 0.0, -1.0);
uniform float hole_km = 0.0;
uniform float gain = 1.0;
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 g = normalize(obj);
	vec3 d = vec3(g.x, -g.z, g.y);
	if (hole_km > 0.0 && length(d - hole_dir) * 1737.4 < hole_km) {
		discard;
	}
	vec4 s = has_surf ? texture(surf, g) : vec4(g * 0.5 + 0.5, 0.56);
	if (has_cap && d.z < -0.5) {
		float sr = length(d.xy);
		float rho = asin(clamp(sr, 0.0, 1.0));
		if (rho < cap_rad) {
			vec2 uv = 0.5 + 0.5 * (sr > 1e-9 ? d.xy / sr : vec2(0.0)) * (rho / cap_rad);
			vec4 c = texture(cap, uv);
			s = mix(c, s, smoothstep(cap_rad * 0.85, cap_rad * 0.98, rho));
		}
	}
	vec3 n = has_surf ? normalize(s.rgb * 2.0 - 1.0) : g;
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n, 0.0))).xyz);
	float a = s.a;
	vec3 tint = mix(vec3(0.86, 0.85, 0.88), vec3(1.0, 0.97, 0.92), smoothstep(0.3, 0.6, a));
	ALBEDO = tint * a * 0.62 * gain;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float mu0 = max(dot(NORMAL, LIGHT), 0.0);
	float mu = max(dot(NORMAL, VIEW), 0.0);
	float ls = 2.0 * mu0 / max(mu0 + mu, 1e-3);
	DIFFUSE_LIGHT += mix(mu0, ls, 0.55) * ATTENUATION * LIGHT_COLOR / PI;
}
