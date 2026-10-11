class_name BodySurface
extends RefCounted
## 암석·얼음 천체 하나의 겉모습 자료 (data/surfaces.json) → 굽기 셰이더(body_field)의 유니폼과 팔레트.
## 구 굽기·도시 둘레 지역 굽기·지형 조각 굽기가 모두 같은 값을 넣는다 (조각과 구가 같은 땅을 그린다).
## 그 천체의 모든 부지(city_sites.json)는 '기지 자리'로 넣는다 — 무늬 크레이터·호수·바다가 기지를 덮지 않고,
## 어느 도시가 있든 같은 땅이 구워진다.

const PATH := "res://data/surfaces.json"
const KEEP_KM := 3.0
const MAX := {"reg": 24, "bas": 20, "mnt": 8, "tro": 4, "ring": 4, "sea": 16, "keep": 4, "pal": 8}

static var _data: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}

var body := ""
var radius_km := 1000.0
var u := {}                             # 굽기 유니폼 이름 → 값
var palette := PackedVector4Array()     # rgb (sRGB) + 좌표
var liquid := 0.0                       # 액체의 팔레트 경계 (0 = 없다)
var liquid_color := Vector3(0.01, 0.01, 0.01)
var veil := Color(0, 0, 0, 0)           # 짙은 대기의 연무 색 (타이탄)
var airless := true


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = null
		if FileAccess.file_exists(PATH):
			parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed.get("bodies", {}) if parsed is Dictionary else {}
	return _data


static func has_body(id: String) -> bool:
	return data().has(id)


static func of(id: String, p_radius_km: float) -> BodySurface:
	if not _cache.has(id):
		_cache[id] = BodySurface.new(id, p_radius_km)
	return _cache[id]


func _init(p_body: String, p_radius_km: float) -> void:
	body = p_body
	radius_km = p_radius_km
	var d: Dictionary = data().get(body, {})
	airless = not PlanetLook.ATMO.has(body)
	u["body_r"] = radius_km
	u["fseed"] = float(absi(body.hash()) % 89) + 3.0
	var b: Dictionary = d.get("base", {})
	u["base_p"] = Vector4(b.get("albedo", 0.5), b.get("albedo_noise", 0.08), b.get("relief_km", 1.0), b.get("relief_freq", 4.0))
	var c: Dictionary = d.get("craters", {})
	u["cf_p"] = Vector4(c.get("freq", 10.0), c.get("density", 0.5), c.get("depth", 0.15), c.get("fresh", 0.1))
	u["cf_q"] = Vector4(c.get("fresh_albedo", 0.2), c.get("rim_albedo", 0.0), c.get("lowland_fade", 0.0), 0.0)
	u["octaves"] = 8
	var rc := PackedVector4Array()
	var rp := PackedVector4Array()
	for e in _rows(d, "regions", "reg"):
		rc.append(_dir4(e[1], e[2], deg_to_rad(float(e[3]))))
		rp.append(Vector4(e[4], e[5], e[6], e[7]))
	_set_arrays("reg", {"reg_c": rc, "reg_p": rp})
	var bc := PackedVector4Array()
	var bp := PackedVector4Array()
	var be := PackedVector4Array()
	for e in _rows(d, "basins", "bas"):
		bc.append(_dir4(e[1], e[2], float(e[3])))
		bp.append(Vector4(e[4], e[5], e[6], e[7]))
		be.append(Vector4(e[8], e[9], e[10], deg_to_rad(float(e[11]))))
	_set_arrays("bas", {"bas_c": bc, "bas_p": bp, "bas_e": be})
	var mc := PackedVector4Array()
	var mp := PackedVector4Array()
	var mq := PackedVector4Array()
	for e in _rows(d, "mounts", "mnt"):
		mc.append(_dir4(e[1], e[2], float(e[3])))
		mp.append(Vector4(e[4], e[5], e[6], e[7]))
		mq.append(Vector4(e[8], 0, 0, 0))
	_set_arrays("mnt", {"mnt_c": mc, "mnt_p": mp, "mnt_q": mq})
	var ta := PackedVector4Array()
	var tb := PackedVector4Array()
	var tp := PackedVector4Array()
	for e in _rows(d, "troughs", "tro"):
		ta.append(_dir4(e[1], e[2], float(e[5])))
		tb.append(_dir4(e[3], e[4], float(e[6])))
		tp.append(Vector4(e[7], 0, 0, 0))
	_set_arrays("tro", {"tro_a": ta, "tro_b": tb, "tro_p": tp})
	var gc := PackedVector4Array()
	var gp := PackedVector4Array()
	for e in _rows(d, "rings", "ring"):
		gc.append(_dir4(e[1], e[2], float(e[4])))
		gp.append(Vector4(e[3], e[5], e[6], e[7]))
	_set_arrays("ring", {"ring_c": gc, "ring_p": gp})
	var sc := PackedVector4Array()
	for e in _rows(d, "seas", "sea"):
		sc.append(_dir4(e[1], e[2], deg_to_rad(float(e[3]))))
	_set_arrays("sea", {"sea_c": sc})
	var sea: Dictionary = d.get("sea", {})
	var lakes: Array = sea.get("lakes", [])
	u["sea_p"] = Vector4(sea.get("level_km", 0.0), sea.get("wobble", 0.3),
		deg_to_rad(float(lakes[0])) if lakes.size() > 0 else 2.0, float(lakes[1]) if lakes.size() > 1 else 0.0)
	liquid = float(d.get("liquid", 0.0))
	u["liq_a"] = liquid
	var caps: Dictionary = d.get("caps", {})
	var hn := 0.0
	var hs := 0.0
	u["pcap_n"] = Vector4(0, 0, 1, -1)
	u["pcap_s"] = Vector4(0, 0, -1, -1)
	if caps.has("north"):
		var cn: Array = caps["north"]
		u["pcap_n"] = _dir4(cn[0], cn[1], deg_to_rad(float(cn[2])))
		hn = float(cn[3])
	if caps.has("south"):
		var cs: Array = caps["south"]
		u["pcap_s"] = _dir4(cs[0], cs[1], deg_to_rad(float(cs[2])))
		hs = float(cs[3])
	u["pcap_h"] = Vector2(hn, hs)
	var du: Dictionary = d.get("dunes", {})
	u["dune_p"] = Vector4(deg_to_rad(float(du.get("band_deg", 0.0))), du.get("height_km", 0.0), du.get("spacing_km", 2.4),
		du.get("albedo", 0.0))
	# 기지 자리: 이 천체의 모든 부지
	var kp := PackedVector4Array()
	GameData.load_all()
	for sid in GameData.SITES:
		var s: Dictionary = GameData.SITES[sid]
		if String(s.get("body", "")) == body and s.has("lat") and kp.size() < MAX["keep"]:
			kp.append(_dir4(s["lat"], s["lon"], KEEP_KM))
	_set_arrays("keep", {"keep": kp})
	# 팔레트 (sRGB — 호환 렌더러는 ALBEDO를 sRGB로 받는다)
	for st in d.get("palette", [[0.0, "#555555"], [1.0, "#aaaaaa"]]).slice(0, MAX["pal"]):
		var col := Color(String(st[1]))
		palette.append(Vector4(col.r, col.g, col.b, float(st[0])))
	if palette.size() > 0:
		liquid_color = Vector3(palette[0].x, palette[0].y, palette[0].z)
	if d.has("veil"):
		var vc := Color(String(d["veil"])).srgb_to_linear()
		veil = Color(vc.r, vc.g, vc.b, 0.0)


func _rows(d: Dictionary, key: String, cap: String) -> Array:
	var rows: Array = d.get(key, [])
	return rows.slice(0, MAX[cap])


static func _dir4(lat: Variant, lon: Variant, w: float) -> Vector4:
	var v := Astro.latlon(float(lat), float(lon))
	return Vector4(v.x, v.y, v.z, w)


## 배열 유니폼과 개수 (빈 배열은 하나를 채워 넣는다 — 개수가 0이라 쓰이지 않는다)
func _set_arrays(prefix: String, arrays: Dictionary) -> void:
	var n := 0
	for k in arrays:
		var a: PackedVector4Array = arrays[k]
		n = a.size()
		if a.is_empty():
			a.append(Vector4.ZERO)
		u[k] = a
	u[prefix + "_n"] = n


## 굽기 셰이더(body_field를 넣은 셰이더)에 천체 자료를 넣는다
func apply(mat: ShaderMaterial) -> void:
	for k in u:
		mat.set_shader_parameter(k, u[k])


## 그리는 셰이더(구·지형 조각)에 팔레트와 액체 색을 넣는다
func apply_look(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("pal", palette)
	mat.set_shader_parameter("pal_n", palette.size())
	mat.set_shader_parameter("liq_th", liquid)
	mat.set_shader_parameter("liq_col", liquid_color)
	mat.set_shader_parameter("ls_k", 0.55 if airless else 0.0)


## 달 표면의 밝기(0..1)를 달 구와 같은 색으로 바꾸는 팔레트 (moon_sphere: 색조 × 밝기 × 0.62)
static func moon_palette() -> PackedVector4Array:
	var p := PackedVector4Array()
	for a: float in [0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]:
		var t := smoothstep(0.3, 0.6, a)
		var tint: Vector3 = Vector3(0.86, 0.85, 0.88).lerp(Vector3(1.0, 0.97, 0.92), t) * a * 0.62
		p.append(Vector4(tint.x, tint.y, tint.z, a))
	return p
