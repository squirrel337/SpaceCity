class_name HabitatView
extends Node3D
## 궤도 도시(L5 아일랜드)의 3D 모습 — 그 천체 노드의 자식 (모형 좌표: 반지름 단위, 몸체 축. x = 원통 축(해 쪽),
## 축 가운데 hub = (0, 0, 2), 바닥 = (x, 0, 1) — 카메라의 가상 구 꼭대기). 단계마다 자란다 (Orbital):
##   1 질량 포획기: 해 쪽 끝 너머의 그물 깔때기와 작은 정거장 · 2 차폐 껍질: 레골리스 판을 두른 원통이 길이로 자란다 ·
##   3 회전 원통: 안벽(땅 셋·창 셋)과 끝 마개 · 4 거울과 첫 마을: 창마다 긴 거울이 열리고 땅이 푸르러진다, 끝의 농장 고리.
## 원통·껍질은 habitat.gdshader가 바깥에서 보면 가까운 쪽 벽을 그리지 않아 단면 그림처럼 안이 보인다.

const N_AROUND := 384           # 둘레 조각 — 바닥의 휨을 0.1 m 안으로 (도시의 길·건물이 뜨지 않게)

var hub := Vector3(0, 0, 2)
var half_len := 2.5
var city_on := false             # 고른 도시가 이 원통이면 안벽의 도시 자리를 고른 땅으로 (HabitatGround가 정한다)
var _hull: MeshInstance3D
var _caps: MeshInstance3D
var _shell: MeshInstance3D
var _mirrors: Array[MeshInstance3D] = []
var _farm: Node3D
var _catcher: Node3D
var _spine: MeshInstance3D
var _hull_mat: ShaderMaterial
var _cap_mat: ShaderMaterial
var _shell_mat: ShaderMaterial
var _mirror_mat: StandardMaterial3D
var _sig := ""


func setup(length_r: float) -> void:
	half_len = length_r * 0.5
	var sh: Shader = load("res://ui/world/shaders/habitat.gdshader")
	_hull_mat = _mat(sh, 0)
	_cap_mat = _mat(sh, 1)
	_shell_mat = _mat(sh, 2)
	_hull = _mi(_tube(1.0, half_len, N_AROUND), _hull_mat)
	_caps = _mi(_discs(1.0, half_len, 128), _cap_mat)
	_shell = _mi(_tube(1.06, half_len + 0.04, 160), _shell_mat)
	_mirror_mat = StandardMaterial3D.new()
	_mirror_mat.albedo_color = Color(0.78, 0.82, 0.88)
	_mirror_mat.metallic = 0.55
	_mirror_mat.roughness = 0.22
	_mirror_mat.emission_enabled = true
	_mirror_mat.emission = Color(0.3, 0.33, 0.38)              # 반사한 햇빛 — 그늘 쪽에서도 은박으로 보이게
	_mirror_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 3:
		var m := MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = _mirror_mat
		add_child(m)
		_mirrors.append(m)
	_farm = _make_farm()
	_catcher = _make_catcher()
	_spine = _mi(_spines(0.06, 16), _std(Color(0.55, 0.57, 0.6), 0.6))
	sync(0, false, 0.0)


func _mat(sh: Shader, part: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("half_len", half_len)
	m.set_shader_parameter("hub", hub)
	return m


func _std(c: Color, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = c * 0.12                                    # 그늘 쪽도 윤곽이 보이게
	return m


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 4.0
	add_child(m)
	return m


## 축이 x인 원통 겉면 (반지름 r, x ∈ [−h, h]) — 삼각형 둘레 n조각. 면의 앞뒤는 셰이더가 가린다
func _tube(r: float, h: float, n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var a := TAU * i / n
		var y := hub.y + cos(a) * r
		var z := hub.z + sin(a) * r
		v.append(Vector3(-h, y, z))
		v.append(Vector3(h, y, z))
	for i in n:
		var a0 := i * 2
		idx.append_array([a0, a0 + 1, a0 + 2, a0 + 1, a0 + 3, a0 + 2])
	return _arrays(v, idx)


## 끝 마개 둘 (x = ±h의 원판)
func _discs(r: float, h: float, n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for sx in [-1.0, 1.0]:
		var c := v.size()
		v.append(Vector3(sx * h, hub.y, hub.z))
		for i in n + 1:
			var a := TAU * i / n
			v.append(Vector3(sx * h, hub.y + cos(a) * r, hub.z + sin(a) * r))
		for i in n:
			idx.append_array([c, c + 1 + i, c + 2 + i])
	return _arrays(v, idx)


## 축이 x인 가는 원통 (등뼈·바큇살 축)
func _cyl_x(r: float, x0: float, x1: float, n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var nn := PackedVector3Array()
	for i in n + 1:
		var a := TAU * i / n
		var d := Vector3(0, cos(a), sin(a))
		v.append(Vector3(x0, hub.y, hub.z) + d * r)
		v.append(Vector3(x1, hub.y, hub.z) + d * r)
		nn.append(d)
		nn.append(d)
	for i in n:
		var a0 := i * 2
		idx.append_array([a0, a0 + 2, a0 + 1, a0 + 1, a0 + 2, a0 + 3])
	return _arrays(v, idx, nn)


## 등뼈: 끝 마개 바깥으로만 — 농장 고리 쪽과 포획기 쪽 (안에는 축이 없다)
func _spines(r: float, n: int) -> ArrayMesh:
	var a := _cyl_x(r, -half_len - 0.75, -half_len, n)
	var b := _cyl_x(r, half_len, half_len + 1.35, n)
	var arr := a.surface_get_arrays(0)
	var arr_b := b.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var off := v.size()
	v.append_array(arr_b[Mesh.ARRAY_VERTEX])
	nn.append_array(arr_b[Mesh.ARRAY_NORMAL])
	for i in (arr_b[Mesh.ARRAY_INDEX] as PackedInt32Array):
		idx.append(i + off)
	return _arrays(v, idx, nn)


func _arrays(v: PackedVector3Array, idx: PackedInt32Array, nn := PackedVector3Array()) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	if not nn.is_empty():
		arr[Mesh.ARRAY_NORMAL] = nn
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 그늘 쪽 끝(−x)의 농장 고리: 바큇살 여섯으로 등뼈에 매달린 고리와 작은 농장 꼬투리
func _make_farm() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var x := -half_len - 0.45
	var ring := TorusMesh.new()
	ring.inner_radius = 1.38
	ring.outer_radius = 1.52
	ring.rings = 96
	ring.ring_segments = 12
	var rm := MeshInstance3D.new()
	rm.mesh = ring
	rm.material_override = _std(Color(0.86, 0.87, 0.85), 0.3)
	rm.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(x, hub.y, hub.z))
	root.add_child(rm)
	for i in 6:
		var a := TAU * i / 6.0
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.05, 1.42, 0.05)
		var sm := MeshInstance3D.new()
		sm.mesh = spoke
		sm.material_override = _std(Color(0.6, 0.62, 0.65), 0.6)
		sm.transform = Transform3D(Basis(Vector3(1, 0, 0), a), Vector3(x, hub.y, hub.z) + Vector3(0, -sin(a), cos(a)) * 0.71)
		root.add_child(sm)
	for i in 24:
		var a2 := TAU * (i + 0.5) / 24.0
		var pod := BoxMesh.new()
		pod.size = Vector3(0.22, 0.12, 0.2)
		var pm := MeshInstance3D.new()
		pm.mesh = pod
		pm.material_override = _std(Color(0.44, 0.62, 0.36) if i % 2 == 0 else Color(0.8, 0.82, 0.78), 0.2)
		pm.transform = Transform3D(Basis(Vector3(1, 0, 0), a2), Vector3(x, hub.y, hub.z) + Vector3(0, cos(a2), sin(a2)) * 1.62)
		root.add_child(pm)
	for root_c in root.get_children():
		(root_c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## 해 쪽 끝(+x) 너머의 질량 포획기: 금박 그물 깔때기, 잇는 뼈대, 태양 전지판 둘
func _make_catcher() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var x := half_len + 1.05
	var cone := CylinderMesh.new()
	cone.top_radius = 0.62
	cone.bottom_radius = 0.07
	cone.height = 0.7
	cone.radial_segments = 48
	cone.cap_top = false
	var cm := MeshInstance3D.new()
	cm.mesh = cone
	var gold := _std(Color(0.86, 0.68, 0.3), 0.8)
	gold.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material_override = gold
	cm.transform = Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5), Vector3(x + 0.1, hub.y, hub.z))
	root.add_child(cm)
	var truss := BoxMesh.new()
	truss.size = Vector3(0.9, 0.05, 0.05)
	var tm := MeshInstance3D.new()
	tm.mesh = truss
	tm.material_override = _std(Color(0.6, 0.62, 0.66), 0.6)
	tm.position = Vector3(half_len + 0.4, hub.y, hub.z)
	root.add_child(tm)
	for s in [-1.0, 1.0]:
		var panel := BoxMesh.new()
		panel.size = Vector3(0.28, 0.01, 0.7)
		var pm := MeshInstance3D.new()
		pm.mesh = panel
		pm.material_override = _std(Color(0.12, 0.16, 0.32), 0.4)
		pm.position = Vector3(half_len + 0.45, hub.y + s * 0.42, hub.z)
		root.add_child(pm)
	for c in root.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## 거울 하나: 창(가운데 각 aw)의 한 가장자리에 매달려 바깥으로 open 라디안 열린 긴 판
func _mirror_mesh(aw: float, open: float) -> ArrayMesh:
	var ah := aw - PI / 6.0
	var o := Vector3(0, cos(ah), sin(ah))
	var t := Vector3(0, -sin(ah), cos(ah))
	var d := (t * cos(open) + o * sin(open)).normalized()
	var base := hub + o * 1.01
	var w := 1.08
	var v := PackedVector3Array([base + Vector3(-half_len, 0, 0), base + Vector3(half_len, 0, 0),
		base + Vector3(-half_len, 0, 0) + d * w, base + Vector3(half_len, 0, 0) + d * w])
	var n := t.cross(Vector3(1, 0, 0)).normalized()
	n = d.cross(Vector3(1, 0, 0)).normalized()
	var nn := PackedVector3Array([n, n, n, n])
	return _arrays(v, PackedInt32Array([0, 1, 2, 1, 3, 2]), nn)


## 단계 (Orbital): done = 다 지은 단계 수, building = 짓는 중, p = 그 단계의 공정 (0~1)
func sync(done: int, building: bool, p: float) -> void:
	var sig := "%d|%s|%d|%s" % [done, str(building), int(p * 40.0), str(city_on)]
	if sig == _sig:
		return
	_sig = sig
	var k := func(stage: int) -> float:
		return 1.0 if done > stage else (clampf(p, 0.0, 1.0) if building and done == stage else 0.0)
	var k0: float = k.call(0)
	var k1: float = k.call(1)
	var k2: float = k.call(2)
	var k3: float = k.call(3)
	visible = k0 > 0.0
	_catcher.visible = k0 > 0.0
	_catcher.scale = Vector3.ONE * maxf(0.15, k0)
	_spine.visible = k0 >= 1.0
	_shell.visible = k1 > 0.0
	_shell_mat.set_shader_parameter("grow", k1)
	_hull.visible = k2 > 0.0
	_hull_mat.set_shader_parameter("grow", k2)
	_caps.visible = k2 >= 1.0
	_hull_mat.set_shader_parameter("green", k3)
	_cap_mat.set_shader_parameter("green", k3)
	_farm.visible = k3 > 0.0
	_farm.scale = Vector3(1, 1, 1) * maxf(0.2, k3)
	for i in 3:
		var m := _mirrors[i]
		m.visible = k3 > 0.0
		if m.visible:
			m.mesh = _mirror_mesh(deg_to_rad(-30.0 + 120.0 * i), deg_to_rad(8.0 + 27.0 * k3))
	_hull_mat.set_shader_parameter("city", Vector4(0.2, 0.2, 1.0 if city_on else 0.0, 0.0))


## 원통 안벽을 다 지었나 (안에 들어가면 벽 너머의 이름표를 감춘다)
func hull_done() -> bool:
	return _caps.visible


## 매 프레임: 카메라의 자리 (모형 좌표 — 가까운 쪽 벽을 걷어 낸다)
func update_frame() -> void:
	if not visible:
		return
	var cam_local := global_transform.affine_inverse() * Vector3.ZERO
	for m in [_hull_mat, _cap_mat, _shell_mat]:
		(m as ShaderMaterial).set_shader_parameter("cam_local", cam_local)
