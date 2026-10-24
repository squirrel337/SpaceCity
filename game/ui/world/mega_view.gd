class_name MegaView
extends Node3D
## 메가프로젝트의 3D 모습 (CityPlan.mega — 짓는 것, mega_done — 다 지은 것). 땅 구역 가운데에 기본 도형으로 세운다:
##   dome 대형 돔 공원 · dish 심우주 전파 접시 · driver 질량 투사기 · ring 회전 거주 고리 · tether 궤도 승강기 지상국
## 짓는 동안은 단계마다 그 부분이 공정만큼 자라고 (앞 단계는 다 서 있다) 둘레에 크레인이 선다. 공정 5%마다 다시 세운다

const CONCRETE := Color(0.66, 0.66, 0.64)
const STEEL := Color(0.62, 0.66, 0.7)
const WHITE := Color(0.9, 0.91, 0.92)
const GLASS := Color(0.55, 0.75, 0.9, 0.35)
const GREEN := Color(0.3, 0.6, 0.32)
const WATER := Color(0.25, 0.45, 0.7)
const CRANE := Color(0.95, 0.76, 0.18)
const GLOW := Color(1.0, 0.85, 0.5)

var _sig := ""
var _mats := {}


func refresh(plan: CityPlan, local: Callable) -> void:
	var parts := PackedStringArray([str(plan.mega_rev), str(plan.terrain_rev), str(plan.mega_done.size())])
	for w in plan.mega:
		parts.append("%d:%d" % [int(w["stage"]), int(float(w["p"]) * 20.0)])
	var sig := ",".join(parts)
	if sig == _sig:
		return
	_sig = sig
	for ch in get_children():
		ch.queue_free()
	for w in plan.mega_done:
		_build(plan, local, String(w["id"]), w["cell"], 99, 1.0)
	for w in plan.mega:
		_build(plan, local, String(w["id"]), w["cell"], int(w["stage"]), float(w["p"]))


## 단계 stage의 공정 p까지 (stage 99 = 다 지었다)
func _build(plan: CityPlan, local: Callable, id: String, cell: Vector2i, stage: int, p: float) -> void:
	var m := CityProgress.mega(id)
	if m.is_empty():
		return
	var r := plan.parcel_rect(cell).grow(-CityPlan.MEGA_INSET - 4.0)
	var c2 := r.get_center()
	var base: Vector3 = local.call(c2, 0.0)
	var root := Node3D.new()
	root.position = base
	add_child(root)
	var size := minf(r.size.x, r.size.y)
	var k := func(s: int) -> float: return 1.0 if stage > s else (p if stage == s else 0.0)
	match String(m.get("look", "dome")):
		"dome":
			_dome(root, size, k)
		"dish":
			_dish(root, size, k)
		"driver":
			_driver(root, size, k)
		"ring":
			_ring(root, size, k)
		"tether":
			_tether(root, size, k)
	if stage < 99:
		for corner: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, 0.45)]:
			_crane(root, Vector3(corner.x * size, 0, corner.y * size), 34.0)


func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.8
	if col.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mat.metallic = 0.3
	_mats[key] = mat
	return mat


func _add(root: Node3D, mesh: Mesh, xf: Transform3D, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = _mat(col)
	root.add_child(mi)
	return mi


func _box(root: Node3D, center: Vector3, size: Vector3, col: Color, yaw := 0.0) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(root, b, Transform3D(Basis(Vector3.UP, yaw), center), col)


func _cyl(root: Node3D, center: Vector3, r_top: float, r_bot: float, h: float, col: Color, basis := Basis()) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 32
	_add(root, cm, Transform3D(basis, center), col)


func _crane(root: Node3D, at: Vector3, h: float) -> void:
	_box(root, at + Vector3(0, h * 0.5, 0), Vector3(1.2, h, 1.2), CRANE)
	_box(root, at + Vector3(8, h, 0), Vector3(22, 0.8, 0.8), CRANE)
	_box(root, at + Vector3(-6, h - 1.0, 0), Vector3(3, 2.2, 2.2), CRANE.darkened(0.4))


## 대형 돔 공원: 기초 링 → 돔 껍질(아래에서부터 자란다) → 숲과 호수
func _dome(root: Node3D, size: float, k: Callable) -> void:
	var r := size * 0.48
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var k2: float = k.call(2)
	if k0 > 0.0:
		_cyl(root, Vector3(0, 0.6, 0), r, r, 1.2 * k0, CONCRETE)
		var ring := TorusMesh.new()
		ring.inner_radius = r - 1.5
		ring.outer_radius = r + 0.5
		_add(root, ring, Transform3D(Basis().scaled(Vector3(1, maxf(k0, 0.05), 1)), Vector3(0, 1.4, 0)), STEEL)
	if k2 > 0.0:
		_cyl(root, Vector3(-r * 0.25, 1.3, r * 0.2), r * 0.3, r * 0.3, 0.2, WATER)
		var n := int(18 * k2)
		for i in n:
			var a := float(i) * 2.4
			var d := r * (0.25 + 0.6 * fmod(float(i) * 0.37, 1.0))
			_cyl(root, Vector3(cos(a) * d, 5.5, sin(a) * d), 0.0, 2.6, 9.0, GREEN)
	if k1 > 0.0:
		var sph := SphereMesh.new()
		sph.radius = r
		sph.height = r * 2.0
		sph.is_hemisphere = true
		sph.radial_segments = 40
		sph.rings = 16
		_add(root, sph, Transform3D(Basis().scaled(Vector3(1, maxf(k1, 0.04), 1)), Vector3(0, 1.2, 0)), GLASS if k1 >= 1.0 else Color(STEEL, 0.6))


## 심우주 전파 접시: 받침과 회전대 → 접시 판 → 수신기
func _dish(root: Node3D, size: float, k: Callable) -> void:
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var k2: float = k.call(2)
	var R := size * 0.42
	if k0 > 0.0:
		_cyl(root, Vector3(0, 9.0 * k0, 0), 5.0, 7.0, 18.0 * k0, CONCRETE)
		_box(root, Vector3(0, 18.0 * k0 + 1.5, 0), Vector3(18, 3, 10) * Vector3(1, k0, 1), STEEL)
	if k1 > 0.0:
		var tilt := Basis(Vector3(1, 0, 0), deg_to_rad(-35.0))
		var dish := CylinderMesh.new()
		dish.top_radius = R * k1
		dish.bottom_radius = R * 0.15 * k1
		dish.height = R * 0.28
		dish.radial_segments = 40
		_add(root, dish, Transform3D(tilt, Vector3(0, 24.0 + R * 0.3, -R * 0.15)), WHITE)
		if k2 > 0.0:
			_cyl(root, Vector3(0, 24.0 + R * 0.95, R * 0.3), 1.2, 1.8, 6.0 * k2, STEEL, tilt)


## 질량 투사기: 레일 기초 → 코일과 축전 → 시험 발사 (끝이 빛난다). 구역의 대각선을 따라 오른다
func _driver(root: Node3D, size: float, k: Callable) -> void:
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var k2: float = k.call(2)
	var L := size * 1.3
	var rise := deg_to_rad(9.0)
	var yaw := PI * 0.25
	var dir := Vector3(cos(yaw), 0, -sin(yaw))
	var n := 14
	for i in n:
		var f := (float(i) + 0.5) / n
		if f > k0 and k0 < 1.0:
			break
		var s := (f - 0.5) * L
		var h := (f * L) * tan(rise) + 1.0
		var at := dir * s + Vector3(0, h, 0)
		_box(root, Vector3(at.x, h * 0.5, at.z), Vector3(2.0, h, 2.0), CONCRETE)
		_box(root, at + Vector3(0, 0.8, 0), Vector3(L / n + 0.4, 1.2, 4.0), STEEL, yaw)
		if k1 > float(i) / n:
			var coil := TorusMesh.new()
			coil.inner_radius = 2.2
			coil.outer_radius = 3.2
			_add(root, coil, Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).rotated(Vector3.UP, yaw), at + Vector3(0, 2.6, 0)),
				GLOW if k2 > 0.0 else STEEL.darkened(0.2))
	if k1 > 0.0:
		_box(root, Vector3(-size * 0.3, 5.0 * k1, size * 0.3), Vector3(30, 10, 18) * Vector3(1, k1, 1), STEEL.darkened(0.15))


## 회전 거주 고리: 중심축 → 고리 마디(차례로) → 회전 시험. 받침 위에 누운 고리, 바큇살 넷
func _ring(root: Node3D, size: float, k: Callable) -> void:
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var R := size * 0.42
	var h := 14.0
	if k0 > 0.0:
		_cyl(root, Vector3(0, (h + 6.0) * 0.5 * k0, 0), 7.0, 8.0, (h + 6.0) * k0, WHITE)
	var n := 24
	for i in int(n * k1):
		var a := TAU * i / n
		var at := Vector3(cos(a) * R, h, sin(a) * R)
		_box(root, at, Vector3(2.0 * PI * R / n + 0.5, 9.0, 10.0), WHITE, -a + PI * 0.5)
		if i % 6 == 0:
			_box(root, Vector3(at.x, h * 0.5, at.z), Vector3(2.5, h, 2.5), CONCRETE)
			_box(root, at * Vector3(0.5, 1, 0.5), Vector3(R, 1.6, 1.6), STEEL, -a)
	if k1 >= 1.0:
		var band := TorusMesh.new()
		band.inner_radius = R - 5.2
		band.outer_radius = R + 5.2
		_add(root, band, Transform3D(Basis().scaled(Vector3(1, 0.12, 1)), Vector3(0, h + 4.7, 0)), GLASS)


## 궤도 승강기 지상국: 닻 기초 → 승강 탑 → 줄 (하늘 끝까지)
func _tether(root: Node3D, size: float, k: Callable) -> void:
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var k2: float = k.call(2)
	if k0 > 0.0:
		_box(root, Vector3(0, 3.0 * k0, 0), Vector3(size * 0.5, 6.0, size * 0.5) * Vector3(1, k0, 1), CONCRETE)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_box(root, Vector3(c.x * size * 0.32, 6.0 * k0, c.y * size * 0.32), Vector3(10, 12, 10) * Vector3(1, k0, 1), STEEL)
	var tower := 90.0
	if k1 > 0.0:
		_cyl(root, Vector3(0, 6.0 + tower * 0.5 * k1, 0), 3.0, 7.0, tower * k1, WHITE)
	if k2 > 0.0:
		var line := 3000.0 * k2
		_cyl(root, Vector3(0, 6.0 + tower + line * 0.5, 0), 0.35, 0.35, line, GLOW)
		_box(root, Vector3(0, 6.0 + tower + minf(line, 300.0) * 0.4, 0), Vector3(4, 6, 4), STEEL)
