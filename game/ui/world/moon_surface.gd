class_name MoonSurface
extends SiteGround
## 달: 구(멀리서) + 기지 둘레의 지형 조각(가까이서) + 기지가 앉는 평지.
##
## 구의 겉모습(밝기·법선)은 시작할 때 GPU로 정육면체 지도에 한 번 굽는다 (바다, 큰 크레이터, 빛줄기,
## 남극의 크레이터, 작은 크레이터 무늬). 지형 조각은 같은 남극 크레이터 함수로 높이를 셈하고
## 그 위에 물결·작은 크레이터·기지 평지를 더한다. 조각이 있는 동안 구는 그 자리를 비운다.
##
## 기지는 섀클턴 크레이터 테두리에 있다: 2D 지도의 능선 마루(v = −214 m)가 크레이터 테두리이고,
## 그 너머는 깊이 4 km의 영구 그늘 크레이터다.

const R_KM := 1737.4
const PATCH_M := 60000.0
const BAKE_SIZE_HI := 1024
const BAKE_SIZE_LO := 512
const CAP_DEG := 12.0                   # 남극 둘레를 따로 곱게 굽는 반지름 (도)
const SHADER_DIR := "res://ui/world/shaders/"

var sphere: MeshInstance3D
var sphere_mat: ShaderMaterial
var patch: MeshInstance3D
var patch_mat: ShaderMaterial
var cube: Cubemap

var _pol_c := PackedVector4Array()
var _pol_p := PackedVector4Array()
var _loc := PackedVector4Array()
var _ice := Vector4.ZERO
var _base_rect := Vector4.ZERO
var _view: WorldView
var _segs := 192
var _rings := 0                         # 고리 수 (중심 포함)
var _grow := 1.0
var _hgrid := PackedFloat32Array()      # 구운 높이 (기지 평지 기준 m) [고리 × 둘레]


func _init() -> void:
	body = "moon"
	layout = BaseLayout.new("ridge")


func setup(sphere_node: MeshInstance3D) -> void:
	sphere = sphere_node
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere_mat = ShaderMaterial.new()
	sphere_mat.shader = load(SHADER_DIR + "moon_sphere.gdshader")
	sphere.material_override = sphere_mat
	_build_terrain_model()
	patch = MeshInstance3D.new()
	patch.mesh = _patch_mesh()
	patch_mat = ShaderMaterial.new()
	patch_mat.shader = load(SHADER_DIR + "moon_patch.gdshader")
	patch.material_override = patch_mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	patch.extra_cull_margin = 4000.0
	add_child(patch)
	city_root = Node3D.new()
	add_child(city_root)
	for m in [sphere_mat, patch_mat]:
		(m as ShaderMaterial).set_shader_parameter("pol_c", _pol_c)
		(m as ShaderMaterial).set_shader_parameter("pol_p", _pol_p)
		(m as ShaderMaterial).set_shader_parameter("pol_n", _pol_c.size())
	patch_mat.set_shader_parameter("site_dir", _site)
	patch_mat.set_shader_parameter("site_basis", _site_basis)
	patch_mat.set_shader_parameter("plateau_m", _plateau_m)
	patch_mat.set_shader_parameter("patch_m", PATCH_M)
	patch_mat.set_shader_parameter("base_rect", _base_rect)
	patch_mat.set_shader_parameter("ice", _ice)
	sphere_mat.set_shader_parameter("hole_dir", _site)
	if OS.has_environment("WORLD_DEBUG_PATCH"):
		patch_mat.set_shader_parameter("debug", 1)
	if DisplayServer.get_name() != "headless":
		_start_bake.call_deferred()


func radius_km() -> float:
	return R_KM


func patch_radius_m() -> float:
	return PATCH_M


# ── 지형 모형 ───────────────────────────────────────────────────
func _build_terrain_model() -> void:
	var m: Dictionary = Astro.sky.get("moon", {})
	var sh: Dictionary = m.get("shackleton", {"lat": -89.67, "lon": 129.78, "diameter_km": 21.0, "depth_km": 4.2,
		"floor_km": 6.6, "rim_m": 280})
	var sc := Astro.latlon(float(sh["lat"]), float(sh["lon"]))
	var rim_r := float(sh["diameter_km"]) * 0.5
	var site_cfg: Dictionary = m.get("site", {"lat": -89.9, "lon": 34.5})
	var nominal := Astro.latlon(float(site_cfg["lat"]), float(site_cfg["lon"]))
	# 기지 평지 중심: 섀클턴 중심에서 (테두리 반지름 + 능선 마루까지) 떨어진 점 — 마루가 2D 지도의 v = −214 m
	var gap_km := rim_r + absf(BaseLayout.CREST_V) / 1000.0
	var axis := sc.cross(nominal).normalized()
	_site = sc.rotated(axis, gap_km / R_KM).normalized()
	var up := _site
	var to_sc := (sc - up * sc.dot(up)).normalized()
	var q := up.cross(to_sc)
	# 모형 방향 (−1, −1)/√2 (2D 지도의 '위' = 능선 쪽)이 섀클턴 중심을 보도록
	var ax := (to_sc * -0.7071067811865476 + q * 0.7071067811865476).normalized()
	var ay := up.cross(ax)
	_site_basis = Basis(ax, ay, up)
	# 남극 크레이터·산 (섀클턴 포함)
	_pol_c.clear()
	_pol_p.clear()
	for c in m.get("polar", []):
		var dir := Astro.latlon(float(c[1]), float(c[2]))
		var diam := float(c[3])
		var depth := float(c[4])
		var rim := 0.02 * diam
		var floor_f := 0.38 if diam > 40.0 else 0.28
		if String(c[0]) == "섀클턴":
			dir = sc
			rim = float(sh.get("rim_m", 280)) / 1000.0
			floor_f = float(sh["floor_km"]) / float(sh["diameter_km"])
			depth = float(sh["depth_km"])
		_pol_c.append(Vector4(dir.x, dir.y, dir.z, diam * 0.5))
		_pol_p.append(Vector4(depth, rim, floor_f, 0.0))
	for mt in m.get("mountains", []):
		var dirm := Astro.latlon(float(mt[1]), float(mt[2]))
		_pol_c.append(Vector4(dirm.x, dirm.y, dirm.z, float(mt[3])))
		_pol_p.append(Vector4(float(mt[4]), 0.0, 0.0, 1.0))
	_plateau_m = polar_height_km(_site) * 1000.0
	# 기지 평지 (2D 지도의 경계, uv)
	var b := BaseLayout.BOUNDS_UV
	_base_rect = Vector4(b.get_center().x, b.get_center().y, b.size.x * 0.5, b.size.y * 0.5)
	_ice = Vector4(layout.ice_center.x, layout.ice_center.y, BaseLayout.ICE_CRATER_R, 4.5)
	# 둘레의 작은 크레이터 (정해진 씨앗)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7061
	_loc.clear()
	var tries := 0
	while _loc.size() < 48 and tries < 2000:
		tries += 1
		var rr := 600.0 + pow(rng.randf(), 0.8) * 11000.0
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rr
		var rad := 25.0 + pow(rng.randf(), 2.6) * 650.0
		if _base_dist(p) < rad * 2.5 + 160.0 or rad < rr * 0.035:
			continue
		_loc.append(Vector4(p.x, p.y, rad, rad * 0.38))


func _base_dist(p: Vector2) -> float:
	var uv := BaseLayout.xy_to_uv(p)
	var c := Vector2(_base_rect.x, _base_rect.y)
	var dq := ((uv - c).abs() - Vector2(_base_rect.z, _base_rect.w)).max(Vector2.ZERO)
	return dq.length()


## 남극 크레이터·산의 높이 (km, 기준 구 위) — 셰이더의 polar_height와 같다
func polar_height_km(d: Vector3) -> float:
	var h := 0.0
	for i in _pol_c.size():
		var c := _pol_c[i]
		var rho := (d - Vector3(c.x, c.y, c.z)).length() * R_KM
		var r := c.w
		if rho > r * 4.0:
			continue
		var p := _pol_p[i]
		if p.w > 0.5:
			var s := r * 0.5
			h += p.x * exp(-rho * rho / (s * s))
		else:
			h += _crater_shape(rho, r, p.x, p.y, p.z)
	return h


static func _crater_shape(rho: float, r: float, depth: float, rim: float, floor_f: float) -> float:
	if rho < r:
		var rf := r * floor_f
		var t := clampf((rho - rf) / maxf(r - rf, 1e-4), 0.0, 1.0)
		return rim - depth * 0.5 * (1.0 + cos(PI * t))
	var q := r / rho
	return rim * q * q * q * (1.0 - smoothstep(2.5 * r, 4.0 * r, rho))


## 기지 둘레의 높이 (m, 기지 평지 기준, 모형 좌표 x, y). 구운 격자가 있으면 그 값 (지형 조각과 같다)
func local_height_m(p: Vector2) -> float:
	if not _hgrid.is_empty():
		return _grid_height(p)
	return _rough_height(p)


func _grid_height(p: Vector2) -> float:
	var r := p.length()
	if r >= PATCH_M:
		r = PATCH_M
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


## 굽기 전: 남극 크레이터 + 평지 + 얼음 크레이터 (셰이더의 rough_m과 같다)
func _rough_height(p: Vector2) -> float:
	var d := (_site * R_KM * 1000.0 + _site_basis * Vector3(p.x, p.y, 0.0)).normalized()
	var h := polar_height_km(d) * 1000.0
	h = lerpf(h, _plateau_m, 1.0 - smoothstep(0.0, 260.0, _base_dist(p)))
	var ri := Vector2(p.x - _ice.x, p.y - _ice.y).length()
	if ri < _ice.z:
		h += (ri * ri / (_ice.z * _ice.z) - 1.0) * _ice.w
	return h * (1.0 - smoothstep(PATCH_M * 0.72, PATCH_M, p.length())) - _plateau_m


## 달 고정 방향의 지형 높이 (km, 기준 구 위). 기지 둘레는 지형 조각과 같은 값
func height_km(dir_b: Vector3) -> float:
	var d := dir_b.normalized()
	var chord := (d - _site).length() * R_KM * 1000.0
	if chord < PATCH_M:
		var rel := d * (R_KM * 1000.0) - _site * (R_KM * 1000.0)
		var p := Vector2(rel.dot(_site_basis.x), rel.dot(_site_basis.y))
		return (local_height_m(p) + _plateau_m) / 1000.0
	return polar_height_km(d)


# ── 지형 조각 메시 ──────────────────────────────────────────────
## 극좌표 격자: 300 m까지는 6 m 간격, 그 바깥은 둘레 간격만큼 커진다.
## UV = (둘레 번호, 고리 번호) — 굽은 높이 지도의 칸, UV2.x = 1이면 치마 (구와의 틈을 가린다)
func ring_radius(k: int) -> float:
	if k <= 50:
		return 6.0 * k
	return minf(300.0 * pow(_grow, k - 50), PATCH_M)


func _patch_mesh() -> ArrayMesh:
	_segs = 144 if OS.has_feature("mobile") else 192
	_grow = 1.0 + TAU / _segs
	var k := 0
	while ring_radius(k) < PATCH_M:
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
		var rr := ring_radius(ring)
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
	mesh.custom_aabb = AABB(Vector3(-PATCH_M, -6000.0, -PATCH_M), Vector3(PATCH_M * 2.0, 8000.0, PATCH_M * 2.0))
	return mesh


# ── 매 프레임 배치 ──────────────────────────────────────────────
func update_frame(view: WorldView, info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	_view = view
	# 기지 평지의 실제 위치 (배정밀도)
	var t := _site_transform(view, info)
	city_root.global_transform = t
	patch.global_transform = t
	var show_patch := _cam_alt_km < 2500.0 and _near_site(view, info)
	patch.visible = show_patch
	city_root.visible = show_patch and _cam_alt_km < 400.0
	sphere_mat.set_shader_parameter("hole_km", PATCH_M / 1000.0 - 0.6 if show_patch else 0.0)
	# 기지 둘레의 어둠 (시뮬레이션의 그늘): 가까울 때만, 고른 식민지일 때만
	_follow_dark(view)


# ── 굽기 (GPU, 시작할 때 한 번) ─────────────────────────────────
func _start_bake() -> void:
	await _bake_patch()
	await _bake_cap()
	await _bake_cube()


func _bake_cap() -> void:
	var size := 2048 if not OS.has_feature("mobile") else 1024
	var rad := deg_to_rad(CAP_DEG)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_DIR + "moon_bake.gdshader")
	_fill_bake_uniforms(mat, 1024)
	mat.set_shader_parameter("mode", 1)
	mat.set_shader_parameter("cap_rad", rad)
	mat.set_shader_parameter("texel", 2.0 * rad / size)
	var img: Image = await _render(mat, Vector2i(size, size))
	if img == null:
		return
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	for mm in [sphere_mat, patch_mat]:
		(mm as ShaderMaterial).set_shader_parameter("cap", tex)
		(mm as ShaderMaterial).set_shader_parameter("cap_rad", rad)
		(mm as ShaderMaterial).set_shader_parameter("has_cap", true)


## 캔버스 셰이더 하나를 size 크기로 한 번 그려 이미지로 받는다
func _render(mat: ShaderMaterial, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _bake_patch() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_DIR + "moon_patch_bake.gdshader")
	_fill_bake_uniforms(mat, 1024)
	mat.set_shader_parameter("segs", _segs)
	mat.set_shader_parameter("rings", _rings)
	mat.set_shader_parameter("grow", _grow)
	mat.set_shader_parameter("patch_m", PATCH_M)
	mat.set_shader_parameter("site_dir", _site)
	mat.set_shader_parameter("site_basis", _site_basis)
	mat.set_shader_parameter("base_rect", _base_rect)
	mat.set_shader_parameter("ice", _ice)
	mat.set_shader_parameter("loc_c", _loc)
	mat.set_shader_parameter("loc_n", _loc.size())
	var img: Image = await _render(mat, Vector2i(_segs, _rings + 1))
	if img == null:
		return
	if OS.has_environment("WORLD_SAVE_BAKE"):
		img.save_png(OS.get_environment("WORLD_SAVE_BAKE").path_join("patch_bake.png"))
	var data := img.get_data()
	var grid := PackedFloat32Array()
	grid.resize(_rings * _segs)
	for k in _rings:
		for i in _segs:
			var o := (k * _segs + i) * 4
			grid[k * _segs + i] = (data[o] * 256 + data[o + 1]) / 8.192 - 6000.0
	var m := _rings * _segs * 4
	_plateau_m = (data[m] * 256 + data[m + 1]) / 65535.0 * 20000.0 - 10000.0
	_hgrid = grid
	var tex := ImageTexture.create_from_image(img)
	patch_mat.set_shader_parameter("hmap", tex)
	patch_mat.set_shader_parameter("has_hmap", true)
	patch_mat.set_shader_parameter("plateau_m", _plateau_m)
	terrain_ready.emit()


func _bake_cube() -> void:
	var size := BAKE_SIZE_HI if not OS.has_feature("mobile") else BAKE_SIZE_LO
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_DIR + "moon_bake.gdshader")
	_fill_bake_uniforms(mat, size)
	var images: Array[Image] = []
	for face in 6:
		var m := mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("face", face)
		var img: Image = await _render(m, Vector2i(size, size))
		if img == null:
			return
		if OS.has_environment("WORLD_SAVE_BAKE"):
			img.save_png(OS.get_environment("WORLD_SAVE_BAKE").path_join("cube_%d.png" % face))
		img.generate_mipmaps()
		images.append(img)
	cube = Cubemap.new()
	cube.create_from_images(images)
	for mm in [sphere_mat, patch_mat]:
		(mm as ShaderMaterial).set_shader_parameter("surf", cube)
		(mm as ShaderMaterial).set_shader_parameter("has_surf", true)


## 달 전체의 높이·밝기 함수(moon_field)에 넣는 값 — 다른 달 부지(SiteSurface)의 굽기도 같은 값을 쓴다
func fill_field_uniforms(mat: ShaderMaterial, size: int) -> void:
	_fill_bake_uniforms(mat, size)
	mat.set_shader_parameter("pol_c", _pol_c)
	mat.set_shader_parameter("pol_p", _pol_p)
	mat.set_shader_parameter("pol_n", _pol_c.size())


func _fill_bake_uniforms(mat: ShaderMaterial, size: int) -> void:
	var m: Dictionary = Astro.sky.get("moon", {})
	mat.set_shader_parameter("pol_c", _pol_c)
	mat.set_shader_parameter("pol_p", _pol_p)
	mat.set_shader_parameter("pol_n", _pol_c.size())
	mat.set_shader_parameter("texel", (PI * 0.5) / size)
	mat.set_shader_parameter("octaves", 5 if size >= 1024 else 4)
	mat.set_shader_parameter("keep_dir", _site)
	mat.set_shader_parameter("keep_km", 3.0)
	var mc := PackedVector4Array()
	var mp := PackedVector4Array()
	for e in m.get("maria", []):
		var d := Astro.latlon(float(e[1]), float(e[2]))
		mc.append(Vector4(d.x, d.y, d.z, deg_to_rad(float(e[3]))))
		mp.append(Vector4(float(e[4]), 1.4, 0, 0))
	mat.set_shader_parameter("mar_c", mc)
	mat.set_shader_parameter("mar_p", mp)
	mat.set_shader_parameter("mar_n", mc.size())
	var bc := PackedVector4Array()
	var bp := PackedVector4Array()
	for e in m.get("craters", []):
		var d2 := Astro.latlon(float(e[1]), float(e[2]))
		var r_km := deg_to_rad(float(e[3])) * R_KM
		var young := 1.0 if String(e[0]) in ["티코", "코페르니쿠스"] else 0.0
		bc.append(Vector4(d2.x, d2.y, d2.z, r_km))
		bp.append(Vector4(float(e[4]), r_km * 0.03, 0.45 if r_km > 30.0 else 0.3, young))
	mat.set_shader_parameter("big_c", bc)
	mat.set_shader_parameter("big_p", bp)
	mat.set_shader_parameter("big_n", bc.size())
	var rc := PackedVector4Array()
	var rp := PackedVector4Array()
	for e in m.get("rays", []):
		var d3 := Astro.latlon(float(e[1]), float(e[2]))
		rc.append(Vector4(d3.x, d3.y, d3.z, float(e[3]) * 0.5))
		rp.append(Vector4(float(e[4]), deg_to_rad(float(e[5])), 0, 0))
	mat.set_shader_parameter("ray_c", rc)
	mat.set_shader_parameter("ray_p", rp)
	mat.set_shader_parameter("ray_n", rc.size())
