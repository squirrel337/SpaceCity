// 암석·얼음 천체 하나의 높이·밝기 (data/surfaces.json → BodySurface가 유니폼을 넣는다).
// 구 굽기(body_bake), 도시 둘레 지역 굽기(body_bake, 지역), 지형 조각 굽기(body_patch_bake)가 같은 함수를 쓴다 —
// 조각과 구가 같은 땅을 그린다. noise.gdshaderinc 다음에 넣는다.
// 방향 d: 몸체 고정 단위 벡터 (x: 경도 0, y: 동경 90°, z: 북극). 거리·높이: km. 밝기: 팔레트 좌표 0..1.
// texel_km: 표본 간격 — 그보다 잔 무늬(크레이터 칸, 모래 언덕, 해안의 잔 굴곡)는 줄인다 (번지지 않게).

uniform float body_r = 1000.0;
uniform float fseed = 1.0;
uniform vec4 base_p = vec4(0.5, 0.08, 1.0, 4.0);   // x 바탕 밝기, y 밝기 잡음 폭, z 기복 km, w 기복 주파수
uniform vec4 cf_p = vec4(10.0, 0.5, 0.15, 0.1);    // 크레이터 무늬: x 첫 칸 주파수, y 밀도, z 깊이 ÷ 지름, w 젊은 몫
uniform vec4 cf_q = vec4(0.2, 0.0, 0.0, 0.0);      // x 젊은 크레이터 밝아짐, y 테두리 밝아짐, z 낮은 땅에서 줄어드는 몫
uniform int octaves = 8;
uniform vec4 keep[4];                              // 기지 자리: 방향, 반지름 km (무늬 크레이터·호수·바다를 두지 않는다)
uniform int keep_n = 0;
uniform vec4 reg_c[24];                            // 지역: 중심, 반지름(라디안)
uniform vec4 reg_p[24];                            // x 밝기 변화, y 높이 km, z 가장자리 흔들림, w 가장자리 폭
uniform int reg_n = 0;
uniform vec4 bas_c[20];                            // 분지·크레이터: 중심, 반지름 km
uniform vec4 bas_p[20];                            // x 깊이 km, y 테두리 km, z 바닥 비율, w 바닥 밝기 변화
uniform vec4 bas_e[20];                            // x 중앙봉 km, y 분출물 밝기, z 빛줄기 세기, w 빛줄기 길이(라디안)
uniform int bas_n = 0;
uniform vec4 mnt_c[8];                             // 산·화산: 중심, 반지름 km
uniform vec4 mnt_p[8];                             // x 높이 km, y 칼데라 반지름 km, z 칼데라 깊이 km, w 밝기 변화
uniform vec4 mnt_q[8];                             // x 모양 (0 방패 화산, 1 돔·메사)
uniform int mnt_n = 0;
uniform vec4 tro_a[4];                             // 협곡: 시작 방향, 반폭 km
uniform vec4 tro_b[4];                             // 끝 방향, 깊이 km
uniform vec4 tro_p[4];                             // x 밝기 변화
uniform int tro_n = 0;
uniform vec4 ring_c[4];                            // 여러 겹 고리 분지: 중심, 바깥 반지름 km
uniform vec4 ring_p[4];                            // x 안 반지름 km, y 고리 간격 km, z 밝기 폭, w 높이 폭 km
uniform int ring_n = 0;
uniform vec4 sea_c[16];                            // 액체 바다: 중심, 반지름(라디안) — 원을 합친다
uniform int sea_n = 0;
uniform vec4 sea_p = vec4(0.0, 0.35, 2.0, 0.0);    // x 해수면 km, y 가장자리 흔들림, z 호수가 시작하는 위도(라디안, 2 = 없다), w 호수 밀도
uniform float liq_a = 0.0;                         // 액체의 팔레트 경계 (0 = 액체가 없는 천체)
uniform vec4 pcap_n = vec4(0.0, 0.0, 1.0, -1.0);   // 북극관: 중심, 반지름(라디안, < 0 = 없다)
uniform vec4 pcap_s = vec4(0.0, 0.0, -1.0, -1.0);  // 남극관
uniform vec2 pcap_h = vec2(0.0);                   // 극관 두께 km (북, 남)
uniform vec4 dune_p = vec4(0.0, 0.0, 2.4, 0.0);    // x 띠 위도(라디안, 0 = 없다), y 높이 km, z 간격 km, w 띠의 밝기 변화

const float BF_PI = 3.14159265359;
const float BF_TAU = 6.28318530718;

float bf_ang(vec3 a, vec3 b) {
	return 2.0 * asin(clamp(length(a - b) * 0.5, 0.0, 1.0));
}

// 그릇 크레이터 단면: 바닥 → 코사인 벽 → 둥근 테두리 → 바깥으로 빠르게 낮아지는 분출물
float bf_bowl(float rho, float R, float depth, float rim, float floor_f) {
	if (rho < R) {
		float rf = R * floor_f;
		float t = clamp((rho - rf) / max(R - rf, 1e-4), 0.0, 1.0);
		return rim - depth * 0.5 * (1.0 + cos(BF_PI * t));
	}
	float q = R / rho;
	return rim * q * q * q * (1.0 - smoothstep(2.5 * R, 4.0 * R, rho));
}

// 정규화하지 않은 fBm (±0.5 언저리): 겹 수가 소수여도 이어진다 (표본 간격에 따라 잔 겹을 서서히 뺀다)
float bf_fbm(vec3 p, float oct, float s) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 14; i++) {
		float w = clamp(oct - float(i), 0.0, 1.0);
		if (w <= 0.0) {
			break;
		}
		sum += (vnoise(p, s + float(i) * 13.0) - 0.5) * amp * w;
		p = p * 2.03 + vec3(1.7, -3.1, 2.3);
		amp *= 0.5;
	}
	return sum;
}

// 기지 자리에서 떨어진 거리 (km, 반지름 밖으로) — 음수면 기지 자리 안
float bf_keep_km(vec3 c) {
	float k = 1e9;
	for (int i = 0; i < 4; i++) {
		if (i >= keep_n) {
			break;
		}
		k = min(k, length(c - keep[i].xyz) * body_r - keep[i].w);
	}
	return k;
}

// 작은 크레이터 무늬 (칸마다 하나씩, 여러 크기). 칸이 표본 간격에 비해 작아지면 서서히 뺀다
float bf_craters(vec3 d, float texel_km, out float fresh, out float rimv) {
	float h = 0.0;
	fresh = 0.0;
	rimv = 0.0;
	float f = cf_p.x;
	float dens = max(cf_p.y, 1e-3);
	for (int o = 0; o < 8; o++) {
		if (o >= octaves) {
			break;
		}
		float cell_km = body_r / f;
		float w = smoothstep(1.5, 3.0, cell_km / max(texel_km, 1e-4));
		if (w <= 0.0) {
			break;
		}
		vec3 p = d * f;
		vec3 ip = floor(p);
		for (int z = -1; z <= 1; z++) {
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec3 cell = ip + vec3(float(x), float(y), float(z));
					vec4 r = hash4(cell, float(o) * 31.0 + 7.0 + fseed);
					if (r.w > cf_p.y) {
						continue;
					}
					vec3 c = cell + r.xyz;
					// 영향 반지름(3 × rad)이 한 칸을 넘지 않아야 이웃 칸만 보고도 끊김이 없다
					float rad = 0.12 + 0.2 * r.w / dens;
					float dist = length(p - c);
					if (dist > rad * 3.0) {
						continue;
					}
					float rkm = rad / f * body_r;
					if (keep_n > 0 && bf_keep_km(normalize(c)) < rkm * 2.2) {
						continue;
					}
					float q = dist / rad;
					float depth = rkm * 2.0 * cf_p.z;
					float rim = depth * 0.19;
					float inner = q < 1.0 ? (q * q - 1.0) * depth : 0.0;
					float rimf = q < 1.0 ? pow(q, 6.0) : 1.0 / (q * q * q);
					h += (inner + rim * rimf * (1.0 - smoothstep(2.0, 3.0, q))) * w;
					if (cf_p.w > 0.0) {
						float young = smoothstep(1.0 - cf_p.w, 1.0 - cf_p.w * 0.3, hash1(cell, float(o) * 17.0 + 3.0 + fseed));
						fresh += young * (exp(-q * q * 0.7) * 0.8 + 0.25 * (1.0 - smoothstep(0.6, 1.0, q))) * w;
					}
					rimv += exp(-pow((q - 1.0) / 0.18, 2.0)) * w;
				}
			}
		}
		f *= 2.0;
	}
	return h;
}

// 빛줄기 (젊은 큰 크레이터)
float bf_rays(vec3 d, vec3 c, float rc, float L, float th, float s) {
	vec3 t1 = normalize(cross(c, abs(c.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0)));
	vec3 t2 = cross(c, t1);
	float psi = atan(dot(d, t2), dot(d, t1));
	float rays = 0.0;
	for (int k = 0; k < 3; k++) {
		float fq = 7.0 + float(k) * 6.0;
		float jit = vnoise(vec3(cos(psi) * 3.0, sin(psi) * 3.0, th * 6.0 + float(k)), 4.0 + s) * 2.0;
		rays += pow(max(0.0, sin(psi * fq + float(k) * 1.7 + jit)), 22.0);
	}
	float fall = exp(-max(th - rc * 2.0, 0.0) / (L * 0.32));
	float blanket = exp(-pow(th / (rc * 2.8), 2.0));
	return 0.24 * blanket + 0.2 * rays * fall * smoothstep(rc, rc * 2.2, th);
}

// 바다의 부호 거리 (라디안, 안쪽 +). 원 여러 개를 합치고 가장자리를 같은 잡음으로 흔든다 (해안이 이어진다)
float bf_sea(vec3 d, float texel_km) {
	float s = -1e3;
	if (sea_n == 0 && sea_p.w <= 0.0) {
		return s;
	}
	// 해안의 잔 굴곡: 가장 큰 굴곡 약 반지름 / 12, 표본 간격의 3배까지 더 잘게
	float oct = clamp(log2(body_r / 12.0 / max(texel_km * 3.0, 1e-4)), 2.0, 12.0);
	float wob = bf_fbm(d * 12.0, oct, fseed + 40.0);
	for (int i = 0; i < 16; i++) {
		if (i >= sea_n) {
			break;
		}
		float r = sea_c[i].w;
		float th = bf_ang(d, sea_c[i].xyz);
		if (th > r * (1.0 + sea_p.y) + 0.02) {
			continue;
		}
		s = max(s, r * (1.0 + wob * 2.0 * sea_p.y) - th);
	}
	// 극지방의 작은 호수 (칸마다 하나)
	if (sea_p.w > 0.0 && abs(d.z) > sin(sea_p.z) - 0.05) {
		float f = body_r / 70.0;
		vec3 p = d * f;
		vec3 ip = floor(p);
		float lat_k = smoothstep(sin(sea_p.z) - 0.05, sin(sea_p.z) + 0.05, abs(d.z));
		for (int z = -1; z <= 1; z++) {
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec3 cell = ip + vec3(float(x), float(y), float(z));
					vec4 r = hash4(cell, 91.0 + fseed);
					if (r.w > sea_p.w * lat_k) {
						continue;
					}
					vec3 c = cell + r.xyz;
					float rad = 0.06 + 0.22 * r.w / max(sea_p.w, 1e-3);
					float dist = length(p - c);
					if (dist > rad * 2.0) {
						continue;
					}
					s = max(s, (rad * (1.0 + wob * 1.2) - dist) / f);
				}
			}
		}
	}
	// 기지 자리는 마른 땅
	if (keep_n > 0) {
		s = min(s, bf_keep_km(d) / body_r);
	}
	return s;
}

// 천체의 높이(km, 기준 구 위)·밝기(팔레트 좌표)·액체 몫
void body_eval(vec3 d, float texel_km, out float h, out float a, out float liq) {
	a = base_p.x + (fbm(d * 5.0, 4, fseed + 1.0) - 0.5) * 2.0 * base_p.y + (fbm(d * 24.0, 3, fseed + 2.0) - 0.5) * base_p.y;
	h = (fbm(d * base_p.w, 5, fseed + 3.0) - 0.5) * 2.0 * base_p.z;
	float low = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= reg_n) {
			break;
		}
		float r = reg_c[i].w;
		float th = bf_ang(d, reg_c[i].xyz);
		if (th > r * (1.0 + reg_p[i].z)) {
			continue;
		}
		// 가장자리 흔들림: 큰 굴곡 + 잔 굴곡 (값 잡음의 격자가 각지게 보이지 않게 두 방향을 섞는다)
		vec3 q = d * (3.0 / max(r, 0.03));
		float wob = (fbm(q, 4, fseed + 11.0 + float(i) * 1.7) - 0.5) * 1.4
			+ (fbm(q.yzx * 3.1 + vec3(5.2), 4, fseed + 17.0 + float(i)) - 0.5) * 0.6;
		wob *= 2.0 * reg_p[i].z * r;
		float m = 1.0 - smoothstep(r * (1.0 - max(reg_p[i].w, 0.02)), r, th + wob);
		a += reg_p[i].x * m;
		h += reg_p[i].y * m;
		if (reg_p[i].y < 0.0) {
			low = max(low, m);
		}
	}
	for (int i = 0; i < 20; i++) {
		if (i >= bas_n) {
			break;
		}
		float R = bas_c[i].w;
		float rho = length(d - bas_c[i].xyz) * body_r;
		float reach = max(R * 4.0, bas_e[i].z > 0.0 ? bas_e[i].w * body_r * 1.3 : 0.0);
		if (rho > reach) {
			continue;
		}
		// 큰 분지는 가장자리가 둥글지 않게
		float wob = (vnoise(d * (body_r / R) * 2.5, fseed + 50.0 + float(i)) - 0.5) * 0.16 * R;
		float rr = max(rho + wob * smoothstep(0.0, 0.3 * R, rho), 0.0);
		h += bf_bowl(rr, R, bas_p[i].x, bas_p[i].y, bas_p[i].z);
		if (bas_e[i].x > 0.0) {
			h += bas_e[i].x * exp(-pow(rho / (R * 0.18), 2.0));
		}
		a += bas_p[i].w * (1.0 - smoothstep(R * 0.75, R, rr));
		a += bas_e[i].y * exp(-pow(rho / (R * 1.8), 2.0)) * smoothstep(R * 0.8, R * 1.1, rho);
		if (bas_e[i].z > 0.0) {
			a += bas_e[i].z * bf_rays(d, bas_c[i].xyz, R / body_r, bas_e[i].w, rho / body_r, float(i));
		}
	}
	for (int i = 0; i < 8; i++) {
		if (i >= mnt_n) {
			break;
		}
		float R = mnt_c[i].w;
		float rho = length(d - mnt_c[i].xyz) * body_r;
		if (rho > R * 1.2) {
			continue;
		}
		float x = rho / R;
		float prof = mnt_q[i].x > 0.5 ? 1.0 - smoothstep(0.55, 1.0, x) : pow(max(1.0 - x * x, 0.0), 1.3);
		h += mnt_p[i].x * prof;
		if (mnt_p[i].y > 0.0) {
			h -= mnt_p[i].z * (1.0 - smoothstep(0.85, 1.05, rho / mnt_p[i].y));
		}
		a += mnt_p[i].w * prof;
	}
	for (int i = 0; i < 4; i++) {
		if (i >= tro_n) {
			break;
		}
		vec3 A = tro_a[i].xyz;
		vec3 B = tro_b[i].xyz;
		vec3 n = normalize(cross(A, B));
		float hw = tro_a[i].w;
		vec3 pp = normalize(d - n * dot(d, n));
		bool inside = dot(cross(A, pp), n) >= 0.0 && dot(cross(pp, B), n) >= 0.0;
		float dist = inside ? abs(dot(d, n)) * body_r : min(length(d - A), length(d - B)) * body_r;
		if (dist > hw * 2.0) {
			continue;
		}
		float wob = (fbm(d * (body_r / hw) * 0.6, 4, fseed + 70.0 + float(i)) - 0.5) * hw * 0.8;
		float x = (dist + wob) / hw;
		h -= tro_b[i].w * (1.0 - smoothstep(0.55, 1.0, x));
		a += tro_p[i].x * (1.0 - smoothstep(0.7, 1.1, x));
	}
	for (int i = 0; i < 4; i++) {
		if (i >= ring_n) {
			break;
		}
		float outer = ring_c[i].w;
		float rho = length(d - ring_c[i].xyz) * body_r;
		float inner = ring_p[i].x;
		if (rho > outer || rho < inner * 0.8) {
			continue;
		}
		float sp = ring_p[i].y;
		float u = (rho - inner) / sp + (fbm(d * (body_r / sp) * 0.15, 3, fseed + 80.0 + float(i)) - 0.5) * 1.5;
		float pat = pow(0.5 + 0.5 * cos(BF_TAU * u), 6.0) * smoothstep(1.0, 2.5, sp / max(texel_km, 1e-4));
		float fade = smoothstep(inner * 0.8, inner * 1.1, rho) * (1.0 - smoothstep(outer * 0.6, outer, rho));
		a += ring_p[i].z * pat * fade;
		h += ring_p[i].w * pat * fade;
	}
	if (dune_p.x > 0.0) {
		// 바람에 늘어선 모래 언덕: 적도 둘레 띠, 밝은 고원에는 없다. 등성이는 동서로 (위도를 따라 되풀이)
		float lat = asin(clamp(d.z, -1.0, 1.0));
		float band = 1.0 - smoothstep(dune_p.x * 0.75, dune_p.x, abs(lat) + (fbm(d * 8.0, 3, fseed + 95.0) - 0.5) * 0.25);
		band *= smoothstep(0.42, 0.55, fbm(d * 6.0, 4, fseed + 96.0) + 0.1);
		band *= 1.0 - smoothstep(0.0, 0.15, a - base_p.x - 0.1);
		a += dune_p.w * band;
		float sp = dune_p.z;
		float k = 1.0 - smoothstep(0.35, 0.7, texel_km / sp);
		if (k > 0.0 && band > 0.0) {
			float y = lat * body_r / sp;
			float warp = (fbm(d * (body_r / (sp * 15.0)), 3, fseed + 97.0) - 0.5) * 3.0;
			float ridge = pow(0.5 + 0.5 * sin(BF_TAU * y + warp), 2.0);
			h += dune_p.y * ridge * band * k;
			a += 0.05 * (ridge - 0.5) * band * k;
		}
	}
	float fr;
	float rv;
	h += bf_craters(d, texel_km, fr, rv) * (1.0 - cf_q.z * low);
	a += fr * cf_q.x + rv * cf_q.y;
	for (int c = 0; c < 2; c++) {
		vec4 pc = c == 0 ? pcap_n : pcap_s;
		if (pc.w <= 0.0) {
			continue;
		}
		float th = bf_ang(d, pc.xyz);
		if (th > pc.w * 1.4) {
			continue;
		}
		float wob = (fbm(d * 18.0, 5, fseed + 90.0 + float(c)) - 0.5) * 0.5 * pc.w;
		float m = 1.0 - smoothstep(pc.w * 0.85, pc.w, th + wob);
		float lanes = smoothstep(0.6, 0.78, fbm(d * 40.0, 3, fseed + 92.0)) * smoothstep(0.15, 0.5, th / pc.w);
		a = mix(a, 1.0 - 0.14 * lanes, m);
		h += (c == 0 ? pcap_h.x : pcap_h.y) * m * (1.0 - smoothstep(0.0, pc.w, th) * 0.5);
	}
	liq = 0.0;
	if (liq_a > 0.0) {
		a = max(a, liq_a + 0.03);
		float s = bf_sea(d, texel_km);
		float tr = max(texel_km, 1e-3) / body_r;
		liq = smoothstep(-tr, tr, s);
		// 물가의 땅은 해수면에서 천천히 오른다 (약 25 km)
		float shore = smoothstep(0.0, 25.0 / body_r, -s);
		float hl = sea_p.x + 0.01 + max(h - sea_p.x - 0.01, 0.0) * shore;
		h = mix(hl, sea_p.x, liq);
		a = mix(a, liq_a * 0.3, liq);
	}
	a = clamp(a, 0.0, 1.0);
}
