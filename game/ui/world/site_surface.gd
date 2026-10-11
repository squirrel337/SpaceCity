class_name SiteSurface
extends SiteGround
## 다른 천체의 부지: 기지 둘레의 지형 조각(반지름 60 km)과 도시가 앉는 평지.
## 천체 구는 행성 셰이더가 그리고, 조각이 보이는 동안 그 자리를 비운다 (hole).
## 높이는 부지마다의 언덕·거칠기·크레이터·모래 언덕을 CPU에서 한 번 셈한다 (정해진 씨앗 — 늘 같은 모양).
## 능선형 부지(수성 극지)는 달처럼 기지 너머로 큰 크레이터 안이 내려가고, 기지 옆에 얼음 분화구가 있다.

const PATCH_M := 60000.0
const RIDGE_R := 12000.0         # 능선형 부지: 기지가 테두리에 앉은 극지 크레이터 (반지름·깊이 m)
const RIDGE_DEPTH := 2400.0
## 천체마다의 땅: 색(바탕·어두운 곳·밝은 곳·얼음), 언덕(높이 m, 크기 m), 거칠기 m, 크레이터 수, 모래 언덕(높이 m, 간격 m)
const LOOKS := {
	"mars": {"base": "#9c5a37", "dark": "#5e3424", "light": "#c98a5c", "ice": "#b39684",
		"hill_h": 28.0, "hill_m": 3200.0, "rough_h": 2.5, "craters": 26, "dune_h": 6.0, "dune_m": 420.0},
	"mercury": {"base": "#77736e", "dark": "#4a4744", "light": "#a19c95", "ice": "#5d6168",
		"hill_h": 40.0, "hill_m": 4000.0, "rough_h": 3.0, "craters": 70, "dune_h": 0.0, "dune_m": 1.0},
	"ceres": {"base": "#4f4c49", "dark": "#34322f", "light": "#706c66", "ice": "#b9bec4",
		"hill_h": 35.0, "hill_m": 3000.0, "rough_h": 2.5, "craters": 60, "dune_h": 0.0, "dune_m": 1.0},
	"callisto": {"base": "#4b443b", "dark": "#2b2621", "light": "#7d766b", "ice": "#c4c8cc",
		"hill_h": 45.0, "hill_m": 3500.0, "rough_h": 3.0, "craters": 90, "dune_h": 0.0, "dune_m": 1.0},
	"titan": {"base": "#6e4f2c", "dark": "#3a2915", "light": "#9a7647", "ice": "#b9b0a2",
		"hill_h": 18.0, "hill_m": 5000.0, "rough_h": 1.2, "craters": 4, "dune_h": 35.0, "dune_m": 2400.0},
}
## 대기의 하늘색 (낮, 땅 가까이). 대기가 없으면 없다
const SKY := {"mars": Color(0.78, 0.6, 0.43), "titan": Color(0.62, 0.43, 0.2)}

var patch: MeshInstance3D
var patch_mat: ShaderMaterial
var sphere: MeshInstance3D
var sphere_mat: ShaderMaterial
var site_data: Dictionary = {}
var _look: Dictionary = {}
var _r_km := 1000.0
var _craters: Array = []          # [Vector2 중심, 반지름 m, 깊이 m]
var _seed := 1
var _base_rect := Vector4.ZERO
var _ridge_c := Vector2.ZERO      # 극지 크레이터 중심 (모형 좌표)


func setup(p_body: String, p_site: Dictionary, sphere_node: MeshInstance3D, p_radius_km: float) -> void:
	body = p_body
	site_data = p_site
	_r_km = p_radius_km
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
	patch = MeshInstance3D.new()
	patch.mesh = _patch_mesh()
	patch_mat = ShaderMaterial.new()
	patch_mat.shader = load("res://ui/world/shaders/site_patch.gdshader")
	# 구와 같은 겉 색 (행성 셰이더의 값을 그대로)
	for k in ["kind", "col_a", "col_b", "col_c", "seed", "bright"]:
		if sphere_mat:
			patch_mat.set_shader_parameter(k, sphere_mat.get_shader_parameter(k))
	var cb := Color(String(_look["base"]))
	patch_mat.set_shader_parameter("base_srgb", Vector3(cb.r, cb.g, cb.b))
	patch_mat.set_shader_parameter("ice_color", Color(String(_look["ice"])))
	patch_mat.set_shader_parameter("site_dir", _site)
	patch_mat.set_shader_parameter("site_basis", _site_basis)
	patch_mat.set_shader_parameter("radius_m", _r_km * 1000.0)
	patch_mat.set_shader_parameter("patch_m", PATCH_M)
	patch.material_override = patch_mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	patch.extra_cull_margin = 4000.0
	add_child(patch)
	city_root = Node3D.new()
	add_child(city_root)
	terrain_ready.emit.call_deferred()


func radius_km() -> float:
	return _r_km


## 대기의 하늘색 (없으면 투명)
func sky_color() -> Color:
	return SKY.get(body, Color(0, 0, 0, 0))


# ── 높이 ────────────────────────────────────────────────────────
func local_height_m(p: Vector2) -> float:
	return _height(p)


func height_km(dir_b: Vector3) -> float:
	var d := dir_b.normalized()
	var r_m := _r_km * 1000.0
	var chord := (d - _site).length() * r_m
	if chord < PATCH_M:
		var rel := d * r_m - _site * r_m
		var p := Vector2(rel.dot(_site_basis.x), rel.dot(_site_basis.y))
		return (_height(p) + _plateau_m) / 1000.0
	return 0.0


func _base_dist(p: Vector2) -> float:
	var uv := BaseLayout.xy_to_uv(p)
	var c := Vector2(_base_rect.x, _base_rect.y)
	var dq := ((uv - c).abs() - Vector2(_base_rect.z, _base_rect.w)).max(Vector2.ZERO)
	return dq.length()


func _height(p: Vector2) -> float:
	var hill_h: float = _look["hill_h"]
	var h := (_fbm(p / float(_look["hill_m"]), 4, _seed) - 0.5) * 2.0 * hill_h
	h += (_fbm(p / 90.0 + Vector2(17.3, 5.1), 2, _seed + 11) - 0.5) * 2.0 * float(_look["rough_h"])
	var dune_h: float = _look["dune_h"]
	if dune_h > 0.0:
		# 바람에 늘어선 모래 언덕 (타이탄은 동서로 수백 km, 화성은 작은 물결)
		h += _dune(p) * dune_h
	for c in _craters:
		var cc: Vector2 = c[0]
		var r: float = c[1]
		var dd := p.distance_to(cc)
		if dd < r * 1.6:
			h += _crater_shape(dd, r, c[2])
	if layout.kind == "ridge":
		# 능선 너머는 극지 크레이터 안으로 내려간다 (기지는 테두리 마루에, 바깥은 완만히 내려간다)
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


## 모래 언덕 0..1 (0 = 골). 기지는 골 한가운데에 앉는다 (원점에서 0)
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
## 극좌표 격자: 300 m까지는 6 m 간격, 그 바깥은 둘레 간격만큼 커진다. 높이·곡률·색을 꼭짓점에 넣는다
func _patch_mesh() -> ArrayMesh:
	var segs := 96 if OS.has_feature("mobile") else 128
	var grow := 1.0 + TAU / segs
	var radii := PackedFloat32Array([0.0])
	var k := 1
	while true:
		var rr := 6.0 * k if k <= 50 else 300.0 * pow(grow, k - 50)
		if rr >= PATCH_M:
			radii.append(PATCH_M)
			break
		radii.append(rr)
		k += 1
	var r_m := _r_km * 1000.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_base := Color(String(_look["base"]))
	var c_dark := Color(String(_look["dark"]))
	var c_light := Color(String(_look["light"]))
	var ice := Vector2(layout.ice_center.x, layout.ice_center.y)
	for ring in radii.size():
		var n := 1 if ring == 0 else segs
		for i in n:
			var a := TAU * i / segs
			var p := Vector2(cos(a), sin(a)) * radii[ring]
			var h := _height(p)
			# 구의 곡률: 평지에서 멀어질수록 내려간다
			var drop := p.length_squared() / (2.0 * r_m)
			var spacing := maxf(6.0, radii[ring] * TAU / segs)
			st.set_color(_ground_color(p, h, c_base, c_dark, c_light, ice, spacing))
			st.add_vertex(Vector3(p.x, h - drop, -p.y))
	for i in segs:
		var j := (i + 1) % segs
		st.add_index(0)
		st.add_index(1 + j)
		st.add_index(1 + i)
	for ring in range(1, radii.size() - 1):
		var a0 := 1 + (ring - 1) * segs
		var a1 := 1 + ring * segs
		for i in segs:
			var j := (i + 1) % segs
			for v in [a0 + i, a0 + j, a1 + j, a0 + i, a1 + j, a1 + i]:
				st.add_index(v)
	st.generate_normals()
	var mesh := st.commit()
	mesh.custom_aabb = AABB(Vector3(-PATCH_M, -6000.0, -PATCH_M), Vector3(PATCH_M * 2.0, 8000.0, PATCH_M * 2.0))
	return mesh


## 꼭짓점 색: rgb = 바탕색 둘레의 무늬 (셰이더가 바탕에 대한 비로 쓴다), a = 얼음(서리)의 몫.
## spacing: 이 자리의 꼭짓점 간격 (m) — 간격보다 잔 무늬는 줄인다 (먼 고리에서 줄무늬로 번지지 않게)
func _ground_color(p: Vector2, h: float, c_base: Color, c_dark: Color, c_light: Color, ice: Vector2, spacing: float) -> Color:
	var k1 := 1.0 - smoothstep(250.0, 900.0, spacing)
	var k2 := 1.0 - smoothstep(20.0, 80.0, spacing)
	var n1 := lerpf(0.5, _fbm(p / 700.0 + Vector2(3.1, 7.7), 3, _seed + 21), k1)
	var n2 := lerpf(0.5, _fbm(p / 60.0, 2, _seed + 29), k2)
	var col := c_base.lerp(c_dark, clampf((0.5 - n1) * 1.0, 0.0, 0.4))
	col = col.lerp(c_light, clampf((n1 - 0.6) * 1.6, 0.0, 0.35))
	col = col.lerp(c_dark, clampf(-h / 120.0, 0.0, 0.35))            # 낮은 곳은 조금 어둡게
	col *= 0.92 + n2 * 0.16
	if body == "titan" and float(_look["dune_h"]) > 0.0:
		col = col.lerp(c_dark, (1.0 - _dune(p)) * 0.35)                   # 언덕 사이 골은 어둡다
	if body in ["ceres", "callisto"]:
		for c in _craters:
			var dd := p.distance_to(c[0])
			var r: float = c[1]
			if dd < r * 1.25 and dd > r * 0.8 and r > spacing * 1.5:
				col = col.lerp(c_light, 0.5 * (1.0 - absf(dd - r) / (r * 0.25)))    # 밝은 테두리 (얼음·염류)
	# 얼음: 능선형은 영구 그늘 분화구, 평지형은 얼음 매장지 (서리 낀 땅)
	var di := p.distance_to(ice)
	var ice_r := BaseLayout.ICE_CRATER_R * (1.0 if layout.kind == "ridge" else 1.6)
	var frost := 0.0
	if di < ice_r:
		frost = 0.6 if (layout.kind == "ridge" or body in ["ceres", "callisto"]) else 0.4
		frost *= (1.0 - smoothstep(ice_r * 0.35, ice_r, di)) * (0.75 + 0.25 * n2)
	col.a = frost
	return col


# ── 매 프레임 ───────────────────────────────────────────────────
func update_frame(view: WorldView, info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	var t := _site_transform(view, info)
	city_root.global_transform = t
	patch.global_transform = t
	var show_patch := _cam_alt_km < 2500.0 and _near_site(view, info)
	patch.visible = show_patch
	city_root.visible = show_patch and _cam_alt_km < 400.0
	if sphere_mat:
		sphere_mat.set_shader_parameter("hole_dir", _site)
		sphere_mat.set_shader_parameter("hole_chord", (PATCH_M - 600.0) / (_r_km * 1000.0) if show_patch else 0.0)
	_follow_dark(view)
