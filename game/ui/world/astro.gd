class_name Astro
extends RefCounted
## 천체의 위치·자세와 목록 (data/sky.json, data/nearby_stars.json).
## 위치: 태양 중심 J2000 황도 좌표, km, 배정밀도 — PackedFloat64Array [x, y, z]
## (Vector3는 32비트라 태양계 거리에서 수십 km씩 어긋난다).
## 시간: 율리우스일(JD). 행성은 JPL 근사 궤도 요소, 달은 간이 월면 이론(경도 0.3° 안팎).

const AU := 149597870.7
const LY := 9.4607304725808e12
const PC_LY := 3.26156
const J2000 := 2451545.0
const OBLIQ := 0.40909280422232897                 # 황도 경사 23.4393°
const MOON_MU := 0.012150584                       # 달 질량 / (지구 + 달)
const EARTH_RADIUS_EQ := 6378.14
const MOON_POLE_TILT := 0.026920                   # 1.5424°: 달 자전축과 황도 북극 사이
const SPIN_CAP_H := 1.5                            # 행성 자전을 보여 줄 때 실제 1초에 최대 몇 시간 (배속이 빨라도 팽이처럼 돌지 않게)

static var sky: Dictionary = {}
static var bodies: Dictionary = {}                 # id → 자료
static var order: Array = []                       # 태양계 천체 id (자료 순서)
static var systems: Array = []                     # 근처 항성계: {id, name, pos, teff, lum, dist_ly, category, planets}
static var bright: Array = []                      # 밝은 별: [이름, 황도 방향 PackedFloat64Array, 등급, 온도]


static func load_data() -> void:
	if not sky.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sky.json"))
	sky = parsed if parsed is Dictionary else {"bodies": [], "bright_stars": [], "moon": {}}
	for b in sky.get("bodies", []):
		var d: Dictionary = b
		if d.has("pole"):
			d["pole_ecl"] = radec_dir(float(d["pole"][0]), float(d["pole"][1]))
		bodies[d["id"]] = d
		order.append(d["id"])
	for s in sky.get("bright_stars", []):
		bright.append([String(s[0]), radec_dir(float(s[1]), float(s[2])), float(s[3]), float(s[4])])
	var ns: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/nearby_stars.json"))
	if ns is Dictionary:
		for sys in ns.get("systems", []):
			if not sys.has("ra_deg"):
				continue
			var dist: float = float(sys["distance_ly"])
			var dir := radec_dir(float(sys["ra_deg"]), float(sys["dec_deg"]))
			var first: Dictionary = sys["stars"][0]
			var lum := 0.0
			for st in sys["stars"]:
				var l: Variant = st.get("luminosity_sun")
				if l != null:
					lum += float(l)
				elif st.get("mass_sun") != null:
					lum += pow(float(st["mass_sun"]), 4.0)
			var teff: Variant = first.get("teff_k")
			systems.append({
				"id": sys["id"], "name": String(sys["name"]["ko"]), "dist_ly": dist,
				"pos": scale3(dir, dist * LY), "teff": float(teff) if teff != null else 3200.0,
				"lum": maxf(lum, 1e-5), "category": sys.get("category", "neighbor"),
				"spectral": String(first.get("spectral", "")), "planets": sys.get("planets", []),
				"hook": String(sys.get("game_hook", "")),
			})


# ── 배정밀도 벡터 ───────────────────────────────────────────────
static func v3(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func add3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


static func sub3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func scale3(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * k, a[1] * k, a[2] * k])


static func lerp3(a: PackedFloat64Array, b: PackedFloat64Array, t: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t])


static func len3(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


static func dot3(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func norm3(a: PackedFloat64Array) -> PackedFloat64Array:
	var l := len3(a)
	return scale3(a, 1.0 / l) if l > 0.0 else v3(0, 0, 1)


## 배정밀도 → 32비트 방향 (황도 좌표 그대로)
static func vec(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func dvec(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([v.x, v.y, v.z])


## 기저(열 = 축)를 배정밀도 벡터에 곱한다
static func bmul(b: Basis, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		b.x.x * v[0] + b.y.x * v[1] + b.z.x * v[2],
		b.x.y * v[0] + b.y.y * v[1] + b.z.y * v[2],
		b.x.z * v[0] + b.y.z * v[1] + b.z.z * v[2]])


## 적경·적위(J2000 적도, 도) → 황도 좌표 단위 벡터
static func radec_dir(ra_deg: float, dec_deg: float) -> PackedFloat64Array:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return eq_to_ecl(v3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)))


static func eq_to_ecl(v: PackedFloat64Array) -> PackedFloat64Array:
	var c := cos(OBLIQ)
	var s := sin(OBLIQ)
	return v3(v[0], v[1] * c + v[2] * s, -v[1] * s + v[2] * c)


## 위도·경도(도) → 천체 고정 좌표의 단위 벡터 (x: 경도 0, z: 북극)
static func latlon(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la))


# ── 시간 ────────────────────────────────────────────────────────
static func jd_from_unix(unix: float) -> float:
	return unix / 86400.0 + 2440587.5


static func centuries(jd: float) -> float:
	return (jd - J2000) / 36525.0


# ── 위치 ────────────────────────────────────────────────────────
## 천체의 태양 중심 위치 (km)
static func position(id: String, jd: float) -> PackedFloat64Array:
	load_data()
	if id == "sun" or not bodies.has(id):
		return v3(0, 0, 0)
	var b: Dictionary = bodies[id]
	var t := centuries(jd)
	match id:
		"earth":
			var emb := _kepler(b["elements"], b["rates"], t)
			return sub3(emb, scale3(moon_geo(jd), MOON_MU))
		"moon":
			var emb2 := _kepler(bodies["earth"]["elements"], bodies["earth"]["rates"], t)
			var m := moon_geo(jd)
			return add3(sub3(emb2, scale3(m, MOON_MU)), m)
	if b.has("elements"):
		return _kepler(b["elements"], b["rates"], t)
	if b.has("parent"):
		return add3(position(b["parent"], jd), satellite_offset(id, jd))
	return v3(0, 0, 0)


## 모행성 중심에서 위성까지 (원 궤도, 모행성 적도면)
static func satellite_offset(id: String, jd: float) -> PackedFloat64Array:
	var b: Dictionary = bodies[id]
	if id == "moon":
		return moon_geo(jd)
	var parent: Dictionary = bodies[b["parent"]]
	var pole: PackedFloat64Array = parent.get("pole_ecl", v3(0, 0, 1))
	var node := norm3(v3(-pole[1], pole[0], 0.0))       # 황도 북극 × 자전축
	var other := v3(pole[1] * node[2] - pole[2] * node[1], pole[2] * node[0] - pole[0] * node[2],
		pole[0] * node[1] - pole[1] * node[0])
	var m := deg_to_rad(float(b.get("phase", 0.0)) + 360.0 * (jd - J2000) / float(b["period_d"]))
	var r: float = float(b["orbit_km"])
	return add3(scale3(node, r * cos(m)), scale3(other, r * sin(m)))


static func _kepler(el: Array, rate: Array, t: float) -> PackedFloat64Array:
	var a: float = float(el[0]) + float(rate[0]) * t
	var e: float = float(el[1]) + float(rate[1]) * t
	var inc := deg_to_rad(float(el[2]) + float(rate[2]) * t)
	var ml: float = float(el[3]) + float(rate[3]) * t
	var peri: float = float(el[4]) + float(rate[4]) * t
	var node_deg: float = float(el[5]) + float(rate[5]) * t
	var w := deg_to_rad(peri - node_deg)
	var node := deg_to_rad(node_deg)
	var mean := deg_to_rad(fposmod(ml - peri + 180.0, 360.0) - 180.0)
	var ecc := mean + e * sin(mean)
	for _i in 8:
		ecc -= (ecc - e * sin(ecc) - mean) / (1.0 - e * cos(ecc))
	var xp := a * (cos(ecc) - e)
	var yp := a * sqrt(1.0 - e * e) * sin(ecc)
	var cw := cos(w)
	var sw := sin(w)
	var cn := cos(node)
	var sn := sin(node)
	var ci := cos(inc)
	var si := sin(inc)
	var x := (cw * cn - sw * sn * ci) * xp + (-sw * cn - cw * sn * ci) * yp
	var y := (cw * sn + sw * cn * ci) * xp + (-sw * sn + cw * cn * ci) * yp
	var z := (sw * si) * xp + (cw * si) * yp
	return v3(x * AU, y * AU, z * AU)


## 지구 중심에서 달까지 (km). 천문력 부록의 간이식 — 경도 0.3°, 거리 0.2% 안팎
static func moon_geo(jd: float) -> PackedFloat64Array:
	var t := centuries(jd)
	var lon := 218.32 + 481267.881 * t \
		+ 6.29 * _sind(134.9 + 477198.85 * t) - 1.27 * _sind(259.2 - 413335.38 * t) \
		+ 0.66 * _sind(235.7 + 890534.23 * t) + 0.21 * _sind(269.9 + 954397.70 * t) \
		- 0.19 * _sind(357.5 + 35999.05 * t) - 0.11 * _sind(186.6 + 966404.05 * t)
	var lat := 5.13 * _sind(93.3 + 483202.03 * t) + 0.28 * _sind(228.2 + 960400.87 * t) \
		- 0.28 * _sind(318.3 + 6003.18 * t) - 0.17 * _sind(217.6 - 407332.20 * t)
	var par := 0.9508 + 0.0518 * _cosd(134.9 + 477198.85 * t) + 0.0095 * _cosd(259.2 - 413335.38 * t) \
		+ 0.0078 * _cosd(235.7 + 890534.23 * t) + 0.0028 * _cosd(269.9 + 954397.70 * t)
	var r := EARTH_RADIUS_EQ / sin(deg_to_rad(par))
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return v3(r * cos(la) * cos(lo), r * cos(la) * sin(lo), r * sin(la))


static func _sind(d: float) -> float:
	return sin(deg_to_rad(d))


static func _cosd(d: float) -> float:
	return cos(deg_to_rad(d))


# ── 자세 ────────────────────────────────────────────────────────
## 천체 고정 좌표 → 황도 좌표 (열: 경도 0 방향, 경도 90° 방향, 북극). spin_h: 자전에 쓸 시간(시)
static func frame(id: String, jd: float, spin_h: float = NAN) -> Basis:
	load_data()
	var t := centuries(jd)
	match id:
		"moon":
			var node := deg_to_rad(125.0445479 - 1934.1362891 * t)
			var pole := Vector3(-sin(MOON_POLE_TILT) * sin(node), sin(MOON_POLE_TILT) * cos(node), cos(MOON_POLE_TILT))
			# 평균 자전: 경도 0이 '평균' 지구 방향을 본다 (실제 지구 방향과의 차이가 칭동)
			var l0 := deg_to_rad(218.3164477 + 481267.88123421 * t + 180.0)
			return _frame_from(pole, Vector3(cos(l0), sin(l0), 0.0))
		"earth":
			var gmst := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - J2000), 360.0))
			if not is_nan(spin_h):
				gmst = deg_to_rad(fposmod(280.46061837 + 360.98564736629 * spin_h / 24.0, 360.0))
			var pole_e := vec(eq_to_ecl(v3(0, 0, 1)))
			var prime := vec(eq_to_ecl(v3(cos(gmst), sin(gmst), 0.0)))
			return _frame_from(pole_e, prime)
	var b: Dictionary = bodies.get(id, {})
	var pole_v := vec(b.get("pole_ecl", v3(0, 0, 1)))
	var hours := (jd - J2000) * 24.0 if is_nan(spin_h) else spin_h
	var rot: float = float(b.get("rot_h", 0.0))
	var w := TAU * fposmod(hours / rot, 1.0) if rot != 0.0 else 0.0
	var eq_node := Vector3(0, 0, 1).cross(pole_v)
	if eq_node.length_squared() < 1e-8:
		eq_node = Vector3(1, 0, 0)
	return _frame_from(pole_v, eq_node.normalized().rotated(pole_v, w))


static func _frame_from(pole: Vector3, prime: Vector3) -> Basis:
	var z := pole.normalized()
	var x := (prime - z * prime.dot(z)).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


# ── 궤도선 ──────────────────────────────────────────────────────
## 궤도 한 바퀴를 n점으로 (행성은 태양 중심, 위성은 모행성 중심), [x0, y0, z0, x1, ...]
static func orbit_points(id: String, jd: float, n: int = 192) -> PackedFloat64Array:
	load_data()
	var out := PackedFloat64Array()
	var b: Dictionary = bodies.get(id, {})
	if b.has("elements"):
		var el: Array = (b["elements"] as Array).duplicate()
		var t := centuries(jd)
		var rate: Array = b["rates"]
		var cur := []
		for i in 6:
			cur.append(float(el[i]) + float(rate[i]) * t)
		var zero := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for k in n:
			var c2: Array = cur.duplicate()
			c2[3] = float(cur[4]) + 360.0 * k / n          # 평균 이각을 0~360°로
			var p := _kepler(c2, zero, 0.0)
			out.append_array(p)
		return out
	if id == "moon":
		# 지금의 궤도면에서 원으로 근사: 지구 중심 위치와 속도 방향으로 평면을 잡는다
		var p0 := moon_geo(jd)
		var p1 := moon_geo(jd + 0.05)
		var r := len3(p0)
		var u := norm3(p0)
		var vv := sub3(p1, p0)
		var w := norm3(sub3(vv, scale3(u, dot3(vv, u))))
		for k in n:
			var a := TAU * k / n
			out.append_array(add3(scale3(u, r * cos(a)), scale3(w, r * sin(a))))
		return out
	if b.has("orbit_km"):
		var period: float = float(b["period_d"])
		for k in n:
			out.append_array(satellite_offset(id, jd + absf(period) * k / n))
		return out
	return out


# ── 별 ──────────────────────────────────────────────────────────
## 표면 온도 → 색 (흑체 근사, sRGB)
static func star_color(teff: float) -> Color:
	var t := clampf(teff, 1500.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float
	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
		b = 0.0 if t <= 19.0 else 138.5177312231 * log(t - 10.0) - 305.0447927307
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)
		b = 255.0
	return Color(clampf(r, 0, 255) / 255.0, clampf(g, 0, 255) / 255.0, clampf(b, 0, 255) / 255.0)


## 광도(태양=1)와 거리(km) → 겉보기 등급
static func apparent_mag(lum: float, dist_km: float) -> float:
	var abs_mag := 4.83 - 2.5 * log(maxf(lum, 1e-8)) / log(10.0)
	var pc := dist_km / LY / PC_LY
	return abs_mag + 5.0 * (log(maxf(pc, 1e-12)) / log(10.0) - 1.0)
