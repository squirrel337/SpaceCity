class_name SiteSurface
extends SiteGround
## 다른 천체의 부지 (달의 다른 부지 포함): 도시가 앉는 평지와 그 둘레의 지형 조각 (반지름 60 km).
## 천체 구는 행성 셰이더(달은 moon_sphere)가 그리고, 조각이 보이는 동안 그 자리를 비운다 (hole).
##
## 고른 도시가 되면 GPU로 굽는다 (달 남극과 같은 방식):
##   1. 조각 가장자리와 기지 자리의 높이 → 기준 높이 (조각은 가장자리의 평균 높이를 구의 높이로 본다)
##   2. 조각의 높이 격자 — 구를 굽는 함수(body_field, 달은 moon_field)와 같아 조각과 구가 같은 땅이다.
##      그 위에 둘레의 작은 크레이터·잔 기복·능선형 부지의 극지 크레이터·얼음 분화구·기지 평지를 더한다
##   3. 도시 둘레 지역 지도 (반지름 약 450 km, 구의 지도보다 곱게 — 구와 조각이 함께 쓴다)
## 화면이 없으면(헤드리스 시험) 굽지 않고 CPU 근사 높이를 쓴다 (기지 평지는 어느 쪽이든 0).

const PATCH_M := 60000.0
const RIDGE_R := 12000.0         # 능선형 부지: 기지가 테두리에 앉은 극지 크레이터 (반지름·깊이 m)
const RIDGE_DEPTH := 2400.0
const CAP_KM := 450.0            # 도시 둘레 지역 지도의 반지름
## 굽기 전(헤드리스)의 근사 높이: 언덕(높이 m, 크기 m), 거칠기 m, 크레이터 수, 모래 언덕(높이 m, 간격 m)
const LOOKS := {
	"mars": {"hill_h": 28.0, "hill_m": 3200.0, "rough_h": 2.5, "craters": 26, "dune_h": 6.0, "dune_m": 420.0},
	"mercury": {"hill_h": 40.0, "hill_m": 4000.0, "rough_h": 3.0, "craters": 70, "dune_h": 0.0, "dune_m": 1.0},
	"ceres": {"hill_h": 35.0, "hill_m": 3000.0, "rough_h": 2.5, "craters": 60, "dune_h": 0.0, "dune_m": 1.0},
	"callisto": {"hill_h": 45.0, "hill_m": 3500.0, "rough_h": 3.0, "craters": 90, "dune_h": 0.0, "dune_m": 1.0},
	"titan": {"hill_h": 18.0, "hill_m": 5000.0, "rough_h": 1.2, "craters": 4, "dune_h": 35.0, "dune_m": 2400.0},
	"moon": {"hill_h": 30.0, "hill_m": 3500.0, "rough_h": 2.5, "craters": 60, "dune_h": 0.0, "dune_m": 1.0},
}
## 얼음·서리의 색 (능선형은 영구 그늘 분화구, 평지형은 얼음 매장지의 서리 낀 땅)
const FROST := {"mars": "#a48a7a", "mercury": "#5d6168", "ceres": "#8e9399", "callisto": "#a3a7ab", "titan": "#a39b8f",
	"moon": "#8f949b"}
## 대기의 하늘색 (낮, 땅 가까이). 대기가 없으면 없다
const SKY := {"mars": Color(0.78, 0.6, 0.43), "titan": Color(0.5, 0.35, 0.17), "earth": Color(0.62, 0.75, 0.93)}

var patch: MeshInstance3D
var patch_mat: ShaderMaterial
var sphere: MeshInstance3D
var sphere_mat: ShaderMaterial
var site_data: Dictionary = {}
var surface: BodySurface          # 다른 천체의 겉모습 자료 (달의 부지면 null)
var moon_src: MoonSurface         # 달의 부지면 달 (굽는 함수와 지도를 빌린다)
var baker: BodyBaker
var _look: Dictionary = {}
var _r_km := 1000.0
var _craters: Array = []          # 굽기 전 근사 높이의 크레이터 [Vector2 중심, 반지름 m, 깊이 m]
var _loc := PackedVector4Array()  # 굽는 조각의 작은 크레이터 (모형 x, y, 반지름 m, 깊이 m)
var _seed := 1
var _base_rect := Vector4.ZERO
var _ridge_c := Vector2.ZERO      # 극지 크레이터 중심 (모형 좌표)
var _baked := false
var _baking := false
var _cap_tex: ImageTexture
var _cap_rad := 0.1
var _cube_set: Cubemap
var standalone := false           # 대도시의 땅: 고른 도시가 아니어도 가까이 가면 지형 조각을 그린다 (구의 두 번째 구멍)
var night_k := 0.0                # 그 자리의 밤 (해의 고도로, 0~1) — 시가지 불빛
var shown := true                 # 대도시의 땅: 카메라가 내려다보는 대도시만 (구의 두 번째 구멍은 하나다)


func setup(p_body: String, p_site: Dictionary, sphere_node: MeshInstance3D, p_radius_km: float,
		p_baker: BodyBaker = null, p_moon: MoonSurface = null) -> void:
	body = p_body
	site_data = p_site
	_r_km = p_radius_km
	baker = p_baker
	moon_src = p_moon if body == "moon" else null
	if body != "moon" and BodySurface.has_body(body):
		surface = BodySurface.of(body, _r_km)
	layout = BaseLayout.new(String(p_site.get("layout", "open")))
	_look = LOOKS.get(body, LOOKS["ceres"])
	_seed = absi(String(p_site.get("id", body)).hash()) % 100000 + 7
	sphere = sphere_node
	sphere_mat = sphere.material_override as ShaderMaterial
	# 기지 평지: 위도·경도. 모형 축은 (−1, −1)/√2(배치의 능선 쪽)이 북쪽을 보도록 둔다
	_site = Astro.latlon(float(p_site["lat"]), float(p_site["lon"]))
	var up := _site
	var north := Vector3(0, 0, 1) - up * up.z
	if north.length_squared() < 1e-8:
		north = Vector3(1, 0, 0) - up * up.x
	north = north.normalized()
	var east := north.cross(up)
	var ax := -(north + east).normalized()
	var ay := (east - north).normalized()
	_site_basis = Basis(ax, ay, up)
	_plateau_m = 0.0
	var b := BaseLayout.BOUNDS_UV
	_base_rect = Vector4(b.get_center().x, b.get_center().y, b.size.x * 0.5, b.size.y * 0.5)
	_ridge_c = BaseLayout.uv_to_xy(Vector2(b.get_center().x, BaseLayout.CREST_V - RIDGE_R))
	_make_craters()
	_make_local_craters()
	patch = MeshInstance3D.new()
	patch.mesh = _patch_mesh()
	patch_mat = ShaderMaterial.new()
	patch_mat.shader = load("res://ui/world/shaders/body_patch.gdshader")
	for k in ["segs", "rings", "grow"]:
		patch_mat.set_shader_parameter(k, {"segs": _segs, "rings": _rings, "grow": _grow}[k])
	patch_mat.set_shader_parameter("patch_m", PATCH_M)
	patch_mat.set_shader_parameter("r_m", _r_km * 1000.0)
	patch_mat.set_shader_parameter("site_dir", _site)
	patch_mat.set_shader_parameter("site_basis", _site_basis)
	patch_mat.set_shader_parameter("base_rect", _base_rect)
	var ic := layout.ice_center
	var ridge := layout.kind == "ridge"
	patch_mat.set_shader_parameter("ice", Vector4(ic.x, ic.y, BaseLayout.ICE_CRATER_R * (1.0 if ridge else 1.6), 0.0))
	patch_mat.set_shader_parameter("frost", Color(String(FROST.get(body, "#b9bec4"))))
	patch_mat.set_shader_parameter("frost_k", 0.55 if ridge else 0.35)
	var atmo: Color = PlanetLook.ATMO.get(body, Color(0, 0, 0, 0))
	patch_mat.set_shader_parameter("soft_k", minf(0.6, atmo.a))
	if surface != null:
		surface.apply_look(patch_mat)
	elif body == "earth":
		patch_mat.set_shader_parameter("mode", 1)
		patch_mat.set_shader_parameter("ls_k", 0.0)
		patch_mat.set_shader_parameter("frost_k", 0.0)
		if sphere_mat:
			patch_mat.set_shader_parameter("eseed", sphere_mat.get_shader_parameter("seed"))
		_earth_uniforms(patch_mat)
	else:
		patch_mat.set_shader_parameter("pal", BodySurface.moon_palette())
		patch_mat.set_shader_parameter("pal_n", BodySurface.moon_palette().size())
		patch_mat.set_shader_parameter("ls_k", 0.5)
	if OS.has_environment("WORLD_DEBUG_PATCH"):
		patch_mat.set_shader_parameter("debug", 1)
	patch.material_override = patch_mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	patch.extra_cull_margin = 4000.0
	patch.visible = false
	add_child(patch)
	city_root = Node3D.new()
	add_child(city_root)
	if baker != null:
		baker.cube_ready.connect(func(bd: String):
			if bd == body:
				_use_cube())
	terrain_ready.emit.call_deferred()
	if standalone:
		raise_sun = false
		_start_bake.call_deferred()


func radius_km() -> float:
	return _r_km


func patch_radius_m() -> float:
	return PATCH_M


## 대기의 하늘색 (없으면 투명)
func sky_color() -> Color:
	return SKY.get(body, Color(0, 0, 0, 0))


## 땅 가까이 연무의 짙기 (1 = 실제 거리 약 25 km에서 절반) — 화성은 맑고, 타이탄은 탁하다
func air_density() -> float:
	return float({"mars": 0.45, "titan": 0.45, "earth": 0.2}.get(body, 1.0))


## 구웠나 (조각의 높이 격자)
func baked() -> bool:
	return _baked


## 도시 둘레 지역 지도를 굽나 (지구는 해안 거리 지도를 그대로 쓴다)
func needs_cap() -> bool:
	return body != "earth"


func has_cap() -> bool:
	return _cap_tex != null


## 지구: 해안 거리 지도와 이 부지 둘레의 고운 해안 지도 (구·조각·굽기가 같은 값을 쓴다)
func _earth_uniforms(mat: ShaderMaterial, with_local := true) -> void:
	PlanetLook.earth_uniforms(mat)
	var loc := PlanetLook.coast_local(String(site_data.get("id", ""))) if with_local else null
	mat.set_shader_parameter("coast_loc", loc)
	mat.set_shader_parameter("has_coast_loc", loc != null)
	if loc != null:
		var c := _site
		var n := (Vector3(0, 0, 1) - c * c.z)
		n = n.normalized() if n.length_squared() > 1e-10 else Vector3(1, 0, 0)
		mat.set_shader_parameter("cl_c", c)
		mat.set_shader_parameter("cl_e", n.cross(c))
		mat.set_shader_parameter("cl_n", n)
		mat.set_shader_parameter("cl_half", float(site_data.get("map_half_km", 128.0)))
		mat.set_shader_parameter("cl_range", float(site_data.get("map_range_km", 8.0)))
	mat.set_shader_parameter("cl_parks", loc != null and bool(site_data.get("parks_map", false)))


# ── 높이 ────────────────────────────────────────────────────────
func local_height_m(p: Vector2) -> float:
	if not _hgrid.is_empty():
		return _grid_height(p)
	return _height(p)


func height_km(dir_b: Vector3) -> float:
	var d := dir_b.normalized()
	var r_m := _r_km * 1000.0
	var chord := (d - _site).length() * r_m
	if chord < PATCH_M:
		var rel := d * r_m - _site * r_m
		var p := Vector2(rel.dot(_site_basis.x), rel.dot(_site_basis.y))
		return (local_height_m(p) + _plateau_m) / 1000.0
	return 0.0


func _grid_height(p: Vector2) -> float:
	var r := minf(p.length(), PATCH_M)
	var rk: float
	if r <= 300.0:
		rk = r / 6.0
	else:
		rk = 50.0 + log(r / 300.0) / log(_grow)
	rk = clampf(rk, 0.0, _rings - 1.0)
	var k0 := int(floor(rk))
	var k1 := mini(k0 + 1, _rings - 1)
	var fk := rk - k0
	var a := fposmod(atan2(p.y, p.x), TAU) / TAU * _segs
	var i0 := int(floor(a)) % _segs
	var i1 := (i0 + 1) % _segs
	var fi: float = a - floor(a)
	var h00 := _hgrid[k0 * _segs + i0]
	var h01 := _hgrid[k0 * _segs + i1]
	var h10 := _hgrid[k1 * _segs + i0]
	var h11 := _hgrid[k1 * _segs + i1]
	return lerpf(lerpf(h00, h01, fi), lerpf(h10, h11, fi), fk)


func _base_dist(p: Vector2) -> float:
	var uv := BaseLayout.xy_to_uv(p)
	var c := Vector2(_base_rect.x, _base_rect.y)
	var dq := ((uv - c).abs() - Vector2(_base_rect.z, _base_rect.w)).max(Vector2.ZERO)
	return dq.length()


## 굽기 전(헤드리스)의 근사 높이 (m, 기지 평지 기준)
func _height(p: Vector2) -> float:
	var hill_h: float = _look["hill_h"]
	var h := (_fbm(p / float(_look["hill_m"]), 4, _seed) - 0.5) * 2.0 * hill_h
	h += (_fbm(p / 90.0 + Vector2(17.3, 5.1), 2, _seed + 11) - 0.5) * 2.0 * float(_look["rough_h"])
	var dune_h: float = _look["dune_h"]
	if dune_h > 0.0:
		h += _dune(p) * dune_h
	for c in _craters:
		var cc: Vector2 = c[0]
		var r: float = c[1]
		var dd := p.distance_to(cc)
		if dd < r * 1.6:
			h += _crater_shape(dd, r, c[2])
	if layout.kind == "ridge":
		var x := p.distance_to(_ridge_c) / RIDGE_R
		if x < 1.0:
			h += RIDGE_DEPTH * (x * x - 1.0)
		else:
			h -= 260.0 * (1.0 - exp(-(x - 1.0) * 3.0))
	h = lerpf(h, 0.0, 1.0 - smoothstep(0.0, 260.0, _base_dist(p)))
	if layout.kind == "ridge":
		var ri := Vector2(p.x - layout.ice_center.x, p.y - layout.ice_center.y).length()
		if ri < BaseLayout.ICE_CRATER_R:
			h += (ri * ri / (BaseLayout.ICE_CRATER_R * BaseLayout.ICE_CRATER_R) - 1.0) * 4.5
	return h * (1.0 - smoothstep(PATCH_M * 0.72, PATCH_M, p.length()))


func _dune(p: Vector2) -> float:
	var q := p.rotated(0.35)
	var wob := (_fbm(p / 6000.0, 2, _seed + 3) - _fbm(Vector2.ZERO, 2, _seed + 3)) * 5.0
	return 0.5 + 0.5 * sin(q.x / float(_look["dune_m"]) * TAU + wob - PI * 0.5)


static func _crater_shape(d: float, r: float, depth: float) -> float:
	var x := d / r
	if x < 1.0:
		return depth * (x * x - 1.0) + depth * 0.12 * smoothstep(0.7, 1.0, x)
	return depth * 0.12 * exp(-pow((x - 1.0) / 0.25, 2.0))


func _make_craters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_craters.clear()
	var want: int = _look["craters"]
	var tries := 0
	while _craters.size() < want and tries < want * 40:
		tries += 1
		var rr := 700.0 + pow(rng.randf(), 0.7) * 30000.0
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rr
		var rad := 30.0 + pow(rng.randf(), 2.4) * 2200.0
		if _base_dist(c) < rad * 2.2 + 200.0:
			continue
		_craters.append([c, rad, rad * 0.2])


## 굽는 조각에 더하는 작은 크레이터 (천체 함수의 크레이터 무늬보다 잔 것 — 수 m ~ 수백 m)
func _make_local_craters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 1
	_loc.clear()
	var n := 48
	if body == "titan":
		n = 6
	elif body == "mars":
		n = 30
	var deep := 0.38 if body in ["moon", "mercury"] else (0.25 if body != "titan" else 0.12)
	var tries := 0
	while _loc.size() < n and tries < 2000:
		tries += 1
		var rr := 600.0 + pow(rng.randf(), 0.8) * 11000.0
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rr
		var rad := 25.0 + pow(rng.randf(), 2.6) * 650.0
		if _base_dist(p) < rad * 2.5 + 160.0 or rad < rr * 0.035:
			continue
		_loc.append(Vector4(p.x, p.y, rad, rad * deep))


# ── 값 잡음 (정해진 해시) ────────────────────────────────────────
static func _hash(ix: int, iy: int, s: int) -> float:
	var h := (ix * 374761393 + iy * 668265263 + s * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _vnoise(p: Vector2, s: int) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(ix, iy, s)
	var b := _hash(ix + 1, iy, s)
	var c := _hash(ix, iy + 1, s)
	var d := _hash(ix + 1, iy + 1, s)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


static func _fbm(p: Vector2, octaves: int, s: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var norm := 0.0
	var q := p
	for i in octaves:
		sum += _vnoise(q, s + i * 31) * amp
		norm += amp
		amp *= 0.5
		q = q * 2.03 + Vector2(1.7, 9.2)
	return sum / norm


# ── 지형 조각 메시 ──────────────────────────────────────────────
## 극좌표 격자: 300 m까지는 6 m 간격, 그 바깥은 둘레 간격만큼 커진다.
## UV = (둘레 번호, 고리 번호) — 굽은 높이 격자의 칸, UV2.x = 1이면 치마 (구와의 틈을 가린다)
func _ring_radius(k: int) -> float:
	if k <= 50:
		return 6.0 * k
	return minf(300.0 * pow(_grow, k - 50), PATCH_M)


func _patch_mesh() -> ArrayMesh:
	_segs = int(Settings.q("patch_segs"))
	_grow = 1.0 + TAU / _segs
	var k := 0
	while _ring_radius(k) < PATCH_M:
		k += 1
	_rings = k + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	uvs.append(Vector2.ZERO)
	uv2s.append(Vector2.ZERO)
	for ring in range(1, _rings):
		var rr := _ring_radius(ring)
		for i in _segs:
			var a := TAU * i / _segs
			verts.append(Vector3(cos(a) * rr, 0.0, -sin(a) * rr))
			uvs.append(Vector2(i, ring))
			uv2s.append(Vector2.ZERO)
	var rim_start := verts.size()
	for i in _segs:
		var a := TAU * i / _segs
		verts.append(Vector3(cos(a) * PATCH_M, 0.0, -sin(a) * PATCH_M))
		uvs.append(Vector2(i, _rings - 1))
		uv2s.append(Vector2(1.0, 0.0))
	for i in _segs:
		var j := (i + 1) % _segs
		idx.append_array(PackedInt32Array([0, 1 + j, 1 + i]))
	for ring in range(1, _rings - 1):
		var a0 := 1 + (ring - 1) * _segs
		var a1 := 1 + ring * _segs
		for i in _segs:
			var j := (i + 1) % _segs
			idx.append_array(PackedInt32Array([a0 + i, a0 + j, a1 + j, a0 + i, a1 + j, a1 + i]))
	var last := 1 + (_rings - 2) * _segs
	for i in _segs:
		var j := (i + 1) % _segs
		idx.append_array(PackedInt32Array([last + i, last + j, rim_start + j, last + i, rim_start + j, rim_start + i]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-PATCH_M, -9000.0, -PATCH_M), Vector3(PATCH_M * 2.0, 18000.0, PATCH_M * 2.0))
	return mesh


# ── 굽기 (GPU, 고른 도시가 될 때) ───────────────────────────────
func _active_changed() -> void:
	if patch_mat == null:
		return
	if active:
		_use_cube()
		if body == "earth" and sphere_mat != null:
			_earth_uniforms(sphere_mat)
		if not _baked or (_cap_tex == null and needs_cap()):
			_start_bake.call_deferred()
		else:
			_apply_cap()
	else:
		_release()


## 대도시의 땅을 치울 때: 구의 두 번째 구멍을 닫는다
func dispose() -> void:
	if standalone and sphere_mat != null:
		sphere_mat.set_shader_parameter("hole2_chord", 0.0)
	queue_free()


## 고른 도시를 그만두면: 구의 구멍과 고운 지역 지도를 내려놓는다 (높이 격자는 둔다 — 작다)
func _release() -> void:
	if sphere_mat != null:
		if body == "earth":
			sphere_mat.set_shader_parameter("has_coast_loc", false)
			sphere_mat.set_shader_parameter("hole_chord", 0.0)
		elif moon_src != null:
			sphere_mat.set_shader_parameter("hole2_km", 0.0)
			if sphere_mat.get_shader_parameter("cap2") == _cap_tex:
				sphere_mat.set_shader_parameter("has_cap2", false)
				sphere_mat.set_shader_parameter("cap2", null)
		elif sphere_mat.get_shader_parameter("cap") == _cap_tex:
			sphere_mat.set_shader_parameter("has_cap", false)
			sphere_mat.set_shader_parameter("cap", null)
	_cap_tex = null
	patch_mat.set_shader_parameter("has_cap", false)
	patch_mat.set_shader_parameter("cap", null)


func _current_cube() -> Cubemap:
	if moon_src != null:
		return moon_src.cube
	if baker != null:
		return baker.cube(body)
	return null


func _use_cube() -> void:
	var cm := _current_cube()
	if cm == _cube_set:
		return
	_cube_set = cm
	patch_mat.set_shader_parameter("surf", cm)
	patch_mat.set_shader_parameter("has_surf", cm != null)


func _field_material(shader_file: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/world/shaders/" + shader_file)
	if surface != null:
		surface.apply(mat)
	elif moon_src != null:
		moon_src.fill_field_uniforms(mat, 1024)
	elif body == "earth":
		_earth_uniforms(mat)
	return mat


func _start_bake() -> void:
	if _baking or not Baker.can_bake() or not is_inside_tree():
		return
	if surface == null and moon_src == null and body != "earth":
		return
	_baking = true
	if not _baked:
		await _bake_patch()
	if active and _cap_tex == null and needs_cap():
		await _bake_cap()
	_baking = false
	# 굽는 동안 다른 도시로 갔다가 돌아왔으면 다시
	if active and _cap_tex == null and needs_cap() and is_inside_tree():
		_start_bake.call_deferred()


func _bake_patch() -> void:
	var shader := "body_patch_bake.gdshader"
	if moon_src != null:
		shader = "moon_site_bake.gdshader"
	elif body == "earth":
		shader = "earth_patch_bake.gdshader"
	var mat := _field_material(shader)
	mat.set_shader_parameter("segs", _segs)
	mat.set_shader_parameter("rings", _rings)
	mat.set_shader_parameter("grow", _grow)
	mat.set_shader_parameter("patch_m", PATCH_M)
	mat.set_shader_parameter("r_m", _r_km * 1000.0)
	mat.set_shader_parameter("site_dir", _site)
	mat.set_shader_parameter("site_basis", _site_basis)
	mat.set_shader_parameter("base_rect", _base_rect)
	var loc := _loc.duplicate()
	if loc.is_empty():
		loc.append(Vector4.ZERO)
	mat.set_shader_parameter("loc_c", loc)
	mat.set_shader_parameter("loc_n", _loc.size())
	var rough_h := 36.0 if body in ["moon", "mercury", "callisto"] else (12.0 if body in ["titan", "earth"] else 24.0)
	if body == "earth":
		mat.set_shader_parameter("loc_n", 0)
	mat.set_shader_parameter("rough", Vector2(rough_h, 0.0011))
	if layout.kind == "ridge":
		mat.set_shader_parameter("ridge", Vector4(_ridge_c.x, _ridge_c.y, RIDGE_R, RIDGE_DEPTH))
		mat.set_shader_parameter("ice", Vector4(layout.ice_center.x, layout.ice_center.y, BaseLayout.ICE_CRATER_R, 4.5))
	# 1. 가장자리와 기지 자리의 높이
	mat.set_shader_parameter("pass_mode", 0)
	var strip: Image = await Baker.render(self, mat, Vector2i(64, 1))
	if strip == null:
		return
	var sd := strip.get_data()
	var ref := 0.0
	for i in 63:
		ref += Baker.h24(sd, i * 4)
	ref /= 63.0
	var site_m := Baker.h24(sd, 63 * 4)
	# 2. 높이 격자
	var m2 := mat.duplicate() as ShaderMaterial
	m2.set_shader_parameter("pass_mode", 1)
	m2.set_shader_parameter("ref_m", ref)
	m2.set_shader_parameter("site_m", site_m)
	var img: Image = await Baker.render(self, m2, Vector2i(_segs, _rings))
	if img == null:
		return
	if OS.has_environment("WORLD_SAVE_BAKE"):
		img.save_png(OS.get_environment("WORLD_SAVE_BAKE").path_join("patch_%s.png" % site_data.get("id", body)))
	var data := img.get_data()
	var grid := PackedFloat32Array()
	grid.resize(_rings * _segs)
	for k in _rings:
		for i in _segs:
			grid[k * _segs + i] = Baker.h24(data, (k * _segs + i) * 4)
	_hgrid = grid
	_plateau_m = site_m - ref
	var tex := ImageTexture.create_from_image(img)
	_keep_baked(img, tex, body in LayoutData.terrain()["flood"]["bodies"])
	if body == "earth" and is_nan(sea_z):
		sea_z = -site_m           # 조각 안에 바다가 없으면 해발 0 m (지구의 기준 구 = 해수면)
	patch_mat.set_shader_parameter("hmap", tex)
	patch_mat.set_shader_parameter("has_hmap", true)
	_baked = true
	terrain_ready.emit()


## 고친 꼭짓점의 높이(RGB 24비트)와 물 몫(A)을 높이 지도에 다시 쓴다 (법선은 셰이더가 이웃 꼭짓점으로 셈한다).
## 물에 잠긴 땅은 물낯을 해수면에 그린다 (땅은 그 아래). 바다를 해수면 위로 메우면 뭍이 된다 (간척)
func _encode_heights(changed: PackedInt32Array) -> void:
	if _himg == null:
		return
	var data := _himg.get_data()
	for idx in changed:
		var o := idx * 4
		var h := _hgrid[idx]
		var wet: int = _hbytes[o + 3]
		if flooded.has(idx):
			h = maxf(h, sea_z)
			wet = 255
		elif not is_nan(sea_z) and wet > 127 and h > sea_z + 0.25 and h > _hbase[idx] + 0.1:
			wet = 0
		var c := clampi(int(round((h + 32768.0) * 256.0)), 0, 16777215)
		data[o] = c >> 16
		data[o + 1] = (c >> 8) & 255
		data[o + 2] = c & 255
		data[o + 3] = wet
	_himg.set_data(_himg.get_width(), _himg.get_height(), false, _himg.get_format(), data)


func _bake_cap() -> void:
	var size := int(Settings.bake_sizes()["cap"])
	if OS.has_environment("WORLD_BAKE_SMALL"):
		size = 512
	_cap_rad = clampf(CAP_KM / _r_km, 0.02, 0.3)
	var mat := _field_material("moon_bake.gdshader" if moon_src != null else "body_bake.gdshader")
	mat.set_shader_parameter("mode", 1)
	mat.set_shader_parameter("cap_rad", _cap_rad)
	mat.set_shader_parameter("cap_dir", _site)
	mat.set_shader_parameter("cap_e1", _site_basis.x)
	mat.set_shader_parameter("cap_e2", _site_basis.y)
	mat.set_shader_parameter("texel", 2.0 * _cap_rad / size)
	var img: Image = await Baker.render(self, mat, Vector2i(size, size))
	if img == null or not active:
		return
	if OS.has_environment("WORLD_SAVE_BAKE"):
		img.save_png(OS.get_environment("WORLD_SAVE_BAKE").path_join("cap_%s.png" % site_data.get("id", body)))
	img.generate_mipmaps()
	_cap_tex = ImageTexture.create_from_image(img)
	_apply_cap()


## 지역 지도를 조각과 (고른 도시면) 구에 넣는다
func _apply_cap() -> void:
	if _cap_tex == null:
		return
	var mats: Array = [patch_mat]
	if active and sphere_mat != null:
		mats.append(sphere_mat)
	for m in mats:
		var mm := m as ShaderMaterial
		var pre := "cap2" if (mm == sphere_mat and moon_src != null) else "cap"
		mm.set_shader_parameter(pre, _cap_tex)
		mm.set_shader_parameter("has_" + pre, true)
		mm.set_shader_parameter(pre + "_rad", _cap_rad)
		mm.set_shader_parameter(pre + "_dir", _site)
		mm.set_shader_parameter(pre + "_e1", _site_basis.x)
		mm.set_shader_parameter(pre + "_e2", _site_basis.y)


# ── 매 프레임 ───────────────────────────────────────────────────
func update_frame(view: WorldView, info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	var t := _site_transform(view, info)
	city_root.global_transform = t
	patch.global_transform = t
	# 자세한 지형 조각은 고른 도시의 것만 (다른 도시는 행성 단위의 점뿐) — 대도시는 가까이 가면. 구운 뒤에만
	var near := (active or (standalone and shown)) and _cam_alt_km < 2500.0 and _near_site(view, info)
	var show_patch := near and _baked
	patch.visible = show_patch
	city_root.visible = near and _cam_alt_km < 400.0
	if body == "earth":
		var to_sun := Astro.vec(Astro.norm3(Astro.sub3(view._info("sun")["center"], info["center"])))
		var sin_el := ((info["frame"] as Basis).inverse() * to_sun).dot(_site)
		night_k = 1.0 - smoothstep(-0.1, 0.04, sin_el)
		patch_mat.set_shader_parameter("night_glow", night_k)
	if standalone:
		if sphere_mat and shown:
			sphere_mat.set_shader_parameter("hole2_dir", _site)
			sphere_mat.set_shader_parameter("hole2_chord", (PATCH_M - 600.0) / (_r_km * 1000.0) if show_patch else 0.0)
		return
	if active:
		_use_cube()
	if sphere_mat and active:
		if moon_src != null:
			sphere_mat.set_shader_parameter("hole2_dir", _site)
			sphere_mat.set_shader_parameter("hole2_km", PATCH_M / 1000.0 - 0.6 if show_patch else 0.0)
		else:
			sphere_mat.set_shader_parameter("hole_dir", _site)
			sphere_mat.set_shader_parameter("hole_chord", (PATCH_M - 600.0) / (_r_km * 1000.0) if show_patch else 0.0)
	_follow_dark(view)
