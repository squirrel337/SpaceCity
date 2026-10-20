class_name PlanetLook
extends RefCounted
## 행성·위성의 겉모습 (planet.gdshader의 kind와 색). 지구는 해안 거리 지도(art/planets/earth_coast*.png, Natural Earth)와
## 얼음·메마른 땅 지도(art/planets/earth_land.png), 대도시의 시가지(data/earth_cities.json)를 쓴다.

const KINDS := {
	"mercury": [0, "#8f8a84", "#5e5953", "#b9b3aa", 1.0],
	"venus": [1, "#e9dcc0", "#c9b48c", "#f4ead7", 1.0],
	"earth": [2, "#1a3d6e", "#2c5a2a", "#ffffff", 1.0],
	"mars": [3, "#b5643c", "#5c3424", "#d8a06a", 1.0],
	"jupiter": [4, "#d9c7a6", "#a8754f", "#efe4cf", 1.0],
	"saturn": [5, "#e3d1a2", "#bfa06a", "#f3e7c8", 1.0],
	"uranus": [6, "#a9dcdf", "#8cc6cc", "#d9f2f2", 1.0],
	"neptune": [7, "#3d68c9", "#2b4a9c", "#d8e6ff", 1.0],
	"pluto": [8, "#c9b49a", "#6b3d2c", "#f2ead8", 1.0],
	"io": [9, "#e6d26a", "#c0753a", "#3b2c22", 1.0],
	"europa": [10, "#e8e0d0", "#c9b9a0", "#8c5a3a", 1.0],
	"ganymede": [11, "#7d756b", "#b8b0a2", "#e6e0d6", 1.0],
	"callisto": [12, "#4c463f", "#5f574d", "#c9c2b6", 1.0],
	"titan": [13, "#d39a4a", "#b8782e", "#e8b870", 1.0],
	"triton": [14, "#d8c4bf", "#9d8a86", "#eee4e0", 1.0],
	"ceres": [0, "#5d5a56", "#4a4743", "#6e6a65", 1.0],
	"rock": [0, "#77706a", "#4f4a45", "#a39c94", 1.0],
}
const ATMO := {
	"venus": Color(0.95, 0.85, 0.6, 0.55),
	"earth": Color(0.35, 0.6, 1.0, 0.85),
	"mars": Color(0.9, 0.55, 0.4, 0.25),
	"jupiter": Color(0.8, 0.75, 0.65, 0.25),
	"saturn": Color(0.85, 0.8, 0.6, 0.25),
	"uranus": Color(0.6, 0.9, 0.95, 0.45),
	"neptune": Color(0.45, 0.6, 1.0, 0.5),
	"titan": Color(0.9, 0.65, 0.3, 0.8),
}
const DOT := {
	"sun": Color("ffd27a"), "mercury": Color("b9b3aa"), "venus": Color("eedfc0"), "earth": Color("6fa8ff"),
	"moon": Color("cfcac2"), "mars": Color("e07b4a"), "jupiter": Color("e3c9a0"), "saturn": Color("e9d6a0"),
	"uranus": Color("a9e0e4"), "neptune": Color("6f8ff0"), "pluto": Color("d8c2a2"), "ceres": Color("bdb8ae"),
}

static var _land: Texture2D
static var _coast: Texture2D


static func _shader(file: String) -> Shader:
	return load("res://ui/world/shaders/" + file)


static func land_texture() -> Texture2D:
	if _land == null and ResourceLoader.exists("res://art/planets/earth_land.png"):
		_land = load("res://art/planets/earth_land.png")
	return _land


## 지구 해안 거리 지도 (Natural Earth 1:10m — tools/art/earth_coast.py)
static func coast_texture() -> Texture2D:
	if _coast == null and ResourceLoader.exists("res://art/planets/earth_coast.png"):
		_coast = load("res://art/planets/earth_coast.png")
	return _coast


## 지구 부지 둘레의 고운 해안 지도 (없으면 null). 미리 읽기 시작한 것은 그 결과를 받는다 (다 읽혔으면 바로)
static func coast_local(site_id: String) -> Texture2D:
	var path := "res://art/planets/earth_coast_%s.png" % site_id
	var i := _coast_wait.find(path)
	if i >= 0:
		_coast_wait.remove_at(i)
		var tex := ResourceLoader.load_threaded_get(path) as Texture2D
		if tex != null:
			return tex
	return load(path) if ResourceLoader.exists(path) else null


## 미리 읽는 중이 아니거나 다 읽혔나 (땅은 그다음에 만든다 — 몇 프레임 늦어도 보이지 않는다)
static func coast_ready(site_id: String) -> bool:
	var path := "res://art/planets/earth_coast_%s.png" % site_id
	return not _coast_wait.has(path) or \
		ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS


static var _coast_wait: Array = []       # 다른 스레드에서 미리 읽는 부지 해안 지도의 경로 (몇 장까지만)


## 카메라가 다가가는 대도시·지역의 해안 지도를 다른 스레드에서 미리 읽는다 — 땅을 만드는 프레임이 파일을 풀며 기다리지 않게.
## 목록에서 빠진 것은 다 읽혔으면 놓는다
static func coast_prefetch(site_ids: PackedStringArray) -> void:
	var want := PackedStringArray()
	for id in site_ids:
		want.append("res://art/planets/earth_coast_%s.png" % id)
	for i in range(_coast_wait.size() - 1, -1, -1):
		var p: String = _coast_wait[i]
		if not want.has(p) and ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(p)
			_coast_wait.remove_at(i)
	for p in want:
		if _coast_wait.size() >= 6 or _coast_wait.has(p) or ResourceLoader.has_cached(p) or not ResourceLoader.exists(p):
			continue
		if ResourceLoader.load_threaded_request(p) == OK:
			_coast_wait.append(p)


## 미리 읽은 지도를 모두 받아 놓는다 (끝낼 때 — 읽는 스레드가 들고 있던 것이 남지 않게)
static func coast_release() -> void:
	for p in _coast_wait:
		ResourceLoader.load_threaded_get(p)
	_coast_wait.clear()


## 지구의 기지 자리 (방향, 반지름 km) — 해안 지도가 기지를 바다에 두더라도 그 둘레는 땅이다
static func earth_keep() -> PackedVector4Array:
	var keep := PackedVector4Array()
	GameData.load_all()
	for sid in GameData.SITES:
		var s: Dictionary = GameData.SITES[sid]
		if String(s.get("body", "")) == "earth" and s.has("lat") and keep.size() < 4:
			var v := Astro.latlon(float(s["lat"]), float(s["lon"]))
			keep.append(Vector4(v.x, v.y, v.z, 1.6))
	return keep


## 지구 셰이더(earth_surface)에 넣는 지도들 — 구, 지형 조각, 조각 굽기가 함께 쓴다
static func earth_uniforms(m: ShaderMaterial) -> void:
	var tex := land_texture()
	m.set_shader_parameter("land", tex)
	m.set_shader_parameter("has_land", tex != null)
	var ct := coast_texture()
	m.set_shader_parameter("coast", ct)
	m.set_shader_parameter("has_coast", ct != null)
	var keep := earth_keep()
	m.set_shader_parameter("ekeep_n", keep.size())
	if keep.is_empty():
		keep.append(Vector4.ZERO)
	m.set_shader_parameter("ekeep", keep)
	# 대도시: 시가지 (방향, 반지름 km)와 불빛 세기(인구)·큰길 방향·블록 크기 — 3D 건물과 같은 격자
	Metros.load_all()
	var mv := PackedVector4Array()
	var mk := PackedVector4Array()
	for c in Metros.list:
		var dir: Vector3 = c["dir"]
		mv.append(Vector4(dir.x, dir.y, dir.z, float(c["radius_km"])))
		var st := Metros.style_of(c)
		mk.append(Vector4(0.45 + 0.22 * log(float(c["pop_m"]) + 1.0), deg_to_rad(float(c.get("grid_deg", 0.0))),
			float(st.get("block_m", 120.0)) / 1000.0, 0.0))
	m.set_shader_parameter("metro_n", mini(mv.size(), 28))
	if mv.is_empty():
		mv.append(Vector4.ZERO)
		mk.append(Vector4.ZERO)
	m.set_shader_parameter("metro", mv)
	m.set_shader_parameter("metro_k", mk)


static func material(id: String, look: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("planet.gdshader")
	var k: Array = KINDS.get(look, KINDS.get(id, KINDS["rock"]))
	m.set_shader_parameter("kind", int(k[0]))
	m.set_shader_parameter("col_a", Color(k[1]))
	m.set_shader_parameter("col_b", Color(k[2]))
	m.set_shader_parameter("col_c", Color(k[3]))
	m.set_shader_parameter("bright", float(k[4]))
	m.set_shader_parameter("seed", float(absi(id.hash()) % 97) + 1.0)
	m.set_shader_parameter("atmo", ATMO.get(look, Color(0, 0, 0, 0)))
	if look == "earth":
		m.set_shader_parameter("r_km", 6371.0)
		earth_uniforms(m)
	return m


static func sun_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("sun.gdshader")
	return m


static func ring_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("ring.gdshader")
	return m


static func dot_color(id: String) -> Color:
	return DOT.get(id, Color(0.8, 0.8, 0.82))
