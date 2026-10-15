class_name OrbitLines
extends Node3D
## 행성·위성의 궤도선을 GPU로 그린다: 궤도마다 중심(태양·모행성) 기준 점(km)의 띠 메시 하나.
## 렌더 좌표의 로그 축척은 꼭짓점 셰이더(orbit_line)가 셈하므로, 매 프레임 CPU는 궤도마다 중심의 위치와 옅기만 넣는다.
## 궤도 모양은 5일마다 다시 셈한다. 행성 궤도는 태양계를 볼 때, 달의 궤도는 지구-달을 볼 때, 다른 위성은 그 행성 둘레를 볼 때.

const PLANETS := ["mercury", "venus", "earth", "mars", "ceres", "jupiter", "saturn", "uranus", "neptune", "pluto"]
const MOONS := ["io", "europa", "ganymede", "callisto", "titan", "triton", "phobos", "deimos", "charon"]

var view: WorldView
var _orbits := {}              # id → {mi: MeshInstance3D, mat: ShaderMaterial, jd: float}
var _shader: Shader


func _init(p_view: WorldView) -> void:
	view = p_view
	name = "orbits"
	_shader = load("res://ui/world/shaders/orbit_line.gdshader")


func _entry(id: String) -> Dictionary:
	if _orbits.has(id):
		return _orbits[id]
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))   # 셰이더가 자리를 정한다 — 잘라내지 않게
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mi.material_override = mat
	add_child(mi)
	var e := {"mi": mi, "mat": mat, "jd": -1e9}
	_orbits[id] = e
	return e


func update() -> void:
	if not Settings.show_orbits():
		visible = false
		return
	visible = true
	var cam := view.cam
	var jd := view.jd
	var shown := {}
	var a_sys := smoothstep(1.5e7, 1.2e8, cam.dist)
	for id in PLANETS:
		var col: Color = PlanetLook.dot_color(id)
		var aa := a_sys
		if id in ["uranus", "neptune", "pluto"]:
			aa *= 1.0 - smoothstep(Astro.LY * 0.05, Astro.LY * 0.5, cam.dist)
		else:
			aa *= 1.0 - smoothstep(Astro.LY * 0.002, Astro.LY * 0.05, cam.dist)
		if aa > 0.02:
			_show(id, Astro.v3(0, 0, 0), Color(col.r, col.g, col.b, 0.42 * aa), jd)
			shown[id] = true
	var a_moon := smoothstep(1.5e4, 1.2e5, cam.dist) * (1.0 - smoothstep(2.0e7, 2.0e8, cam.dist))
	if a_moon > 0.02:
		_show("moon", view._info("earth")["center"], Color(0.8, 0.8, 0.78, 0.4 * a_moon), jd)
		shown["moon"] = true
	for id in MOONS:
		var b: Dictionary = Astro.bodies[id]
		var pc: PackedFloat64Array = view._info(b["parent"])["center"]
		var pd := Astro.len3(Astro.sub3(pc, cam.pos))
		var orb := float(b["orbit_km"])
		var am := smoothstep(orb * 0.2, orb * 1.2, pd) * (1.0 - smoothstep(orb * 25.0, orb * 80.0, pd))
		# 그 위성 가까이에서는 제 궤도선이 화면을 가로지르지 않게
		var md := Astro.len3(Astro.sub3(view._info(id)["center"], cam.pos))
		am *= smoothstep(orb * 0.02, orb * 0.12, md)
		if am > 0.02:
			_show(id, pc, Color(0.75, 0.78, 0.82, 0.32 * am), jd)
			shown[id] = true
	for id in _orbits:
		if not shown.has(id):
			(_orbits[id]["mi"] as Node3D).visible = false


func _show(id: String, origin: PackedFloat64Array, col: Color, jd: float) -> void:
	var e := _entry(id)
	if absf(jd - float(e["jd"])) > 5.0:
		e["jd"] = jd
		(e["mi"] as MeshInstance3D).mesh = _mesh(Astro.orbit_points(id, jd, 160 if id == "moon" else 256))
	var mat: ShaderMaterial = e["mat"]
	var rel := Astro.sub3(origin, view.cam.pos)
	mat.set_shader_parameter("origin_rel", Vector3(rel[0], rel[1], rel[2]))
	mat.set_shader_parameter("local_km", view._local)
	mat.set_shader_parameter("shell_k", WorldView.SHELL_K)
	mat.set_shader_parameter("unit_km", view._unit)
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("px_scale", view.px_scale())
	(e["mi"] as Node3D).visible = true


## 닫힌 궤도의 띠 메시: 점마다 두 꼭짓점 (이웃 점, 옆 부호 × 반너비 0.6 px)
static func _mesh(pts: PackedFloat64Array) -> ArrayMesh:
	var n := pts.size() / 3
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in n + 1:
		var i := (k % n) * 3
		var j := ((k + 1) % n) * 3
		var p := Vector3(pts[i], pts[i + 1], pts[i + 2])
		var q := Vector3(pts[j], pts[j + 1], pts[j + 2])
		for side in [-1.0, 1.0]:
			verts.append(p)
			uv.append(Vector2(q.x, q.y))
			uv2.append(Vector2(q.z, side * 0.6))
	for k in n:
		var o := k * 2
		idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
