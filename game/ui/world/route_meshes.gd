class_name RouteMeshes
extends Node3D
## 천체 위의 노선(땅길·호퍼·하늘길·대도시 항공편)과 그 위를 가는 탈것을 GPU로 그린다.
## 노선은 천체 고정 좌표(반지름 1)의 띠 메시라 천체 구와 같은 변환으로 놓는다 — 천체 뒤편은 깊이로 가려지고,
## 매 프레임 CPU가 하는 일은 천체마다 변환·옅기 몇 개뿐이다. 노선·켜짐·강조가 바뀔 때만 메시를 다시 만든다.
## 탈것 표시는 천체마다 멀티메시 하나: 자리만 매 프레임 넣고, 화면 크기·모양·가는 쪽은 셰이더가 정한다.
## (지구-달 셔틀과 행성 사이 수송선은 두 천체에 걸치고 몇 개뿐이라 RouteOverlay가 화면 위에 그린다.)

const MARKER_CAP := 512
const KIND_SHAPE := {"air": 0.0, "ground": 1.0, "hop": 2.0}

var view: WorldView
var _per := {}                 # 천체 → {lines: MeshInstance3D, lmat, mm: MultiMeshInstance3D, mmat, sig}
var _line_shader: Shader
var _marker_shader: Shader


func _init(p_view: WorldView) -> void:
	view = p_view
	name = "routes3d"
	_line_shader = load("res://ui/world/shaders/route_line.gdshader")
	_marker_shader = load("res://ui/world/shaders/route_marker.gdshader")


func _entry(body: String) -> Dictionary:
	if _per.has(body):
		return _per[body]
	var lines := MeshInstance3D.new()
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lmat := ShaderMaterial.new()
	lmat.shader = _line_shader
	lmat.render_priority = 1
	lines.material_override = lmat
	add_child(lines)
	var mmi := MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mm.mesh = q
	mm.instance_count = MARKER_CAP
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-1.2, -1.2, -1.2), Vector3(2.4, 2.4, 2.4))
	var mmat := ShaderMaterial.new()
	mmat.shader = _marker_shader
	mmat.render_priority = 2
	mmi.material_override = mmat
	add_child(mmi)
	var e := {"lines": lines, "lmat": lmat, "mm": mmi, "mmat": mmat, "sig": ""}
	_per[body] = e
	return e


## 매 프레임 (천체 자리가 정해진 뒤): 노선 메시를 맞추고, 천체 구와 같은 변환에 놓고, 탈것 자리를 넣는다
func update() -> void:
	var mgr := view.mgr
	if mgr == null:
		visible = false
		return
	visible = true
	var tr := mgr.transport
	var ov := view.routes
	var by_body := {}
	for l in tr.lines:
		if String(l["kind"]) in ["ferry", "ship"]:
			continue
		var body := String(l["body"])
		if not by_body.has(body):
			by_body[body] = []
		by_body[body].append(l)
	var px := view.px_scale()
	var alphas := {}
	for body in _per:
		if not by_body.has(body):
			(_per[body]["lines"] as Node3D).visible = false
			(_per[body]["mm"] as Node3D).visible = false
	for body in by_body:
		var lines: Array = by_body[body]
		var e := _entry(body)
		var any_hot := false
		var hot_id := ov.hi_line if ov._hi(ov.hi_line) else ""
		if hot_id != "":
			for l in lines:
				if l["id"] == hot_id:
					any_hot = true
					break
		var sig := "%d|%s|%s" % [tr.rev, ov.show, hot_id]
		if sig != e["sig"]:
			e["sig"] = sig
			(e["lines"] as MeshInstance3D).mesh = _line_mesh(body, lines, tr, ov)
		var a := ov._body_alpha(body)
		var fade := maxf(a, 0.6 if any_hot else 0.0)
		alphas[body] = fade
		var node: MeshInstance3D = view._bodies[body]["node"]
		var on := fade > 0.02 and (ov.show or any_hot)
		var ln: MeshInstance3D = e["lines"]
		ln.visible = on
		(e["mm"] as Node3D).visible = on
		if not on:
			continue
		ln.transform = node.transform
		(e["mm"] as Node3D).transform = node.transform
		(e["lmat"] as ShaderMaterial).set_shader_parameter("fade", fade)
		(e["lmat"] as ShaderMaterial).set_shader_parameter("px_scale", px)
		(e["mmat"] as ShaderMaterial).set_shader_parameter("fade", fade)
		(e["mmat"] as ShaderMaterial).set_shader_parameter("px_scale", px)
	_place_vehicles(tr, ov, alphas)


## 천체 하나의 노선 띠: 점마다 두 꼭짓점, 이웃 점(UV·UV2.x)과 옆 부호 × 반너비(UV2.y)
func _line_mesh(body: String, lines: Array, tr: Transport, ov: RouteOverlay) -> ArrayMesh:
	var r := float(Astro.bodies[body]["radius_km"])
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for l in lines:
		var st := ov.line_style(l, tr)
		if not ov.show and not st["hot"]:
			continue
		var col := Color(st["col"], float(st["alpha"]))
		var hw := float(st["width"]) * 0.5
		var n := clampi(int(float(l["km"]) / 120.0) + 8, 8, 64)
		var pts := PackedVector3Array()
		for i in n + 1:
			pts.append(point(l, r, float(i) / n))
		var base := verts.size()
		for i in pts.size():
			var p := pts[i]
			var nb := pts[i + 1] if i + 1 < pts.size() else pts[i - 1]
			var flip := -1.0 if i + 1 >= pts.size() else 1.0
			for side in [-1.0, 1.0]:
				verts.append(p)
				uv.append(Vector2(nb.x, nb.y))
				uv2.append(Vector2(nb.z, side * flip * hw))
				cols.append(col)
		for i in pts.size() - 1:
			var o := base + i * 2
			idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## 노선 위의 점 (천체 메시 좌표 — 반지름 1, 몸체 고정 (x, y, z) → (x, z, −y)), t = 0(a) ~ 1(b)
static func point(l: Dictionary, r: float, t: float) -> Vector3:
	var d := RouteOverlay._slerp(Transport.node_dir(l["a"]), Transport.node_dir(l["b"]), t)
	var h := RouteOverlay.arc_height(l, r) * 4.0 * t * (1.0 - t) + r * 0.0006
	var v := d * (1.0 + h / r)
	return Vector3(v.x, v.z, -v.y)


## 가는 중인 편의 표: 천체마다 멀티메시에 자리(원점)·조금 뒤의 자리(쪽)·모양·색을 넣는다
func _place_vehicles(tr: Transport, ov: RouteOverlay, alphas: Dictionary) -> void:
	var hour_f := float(view.mgr.hour) + view.hour_frac
	var counts := {}
	for t_rec in tr.trips:
		var l := tr.line_by_id(String(t_rec["line"]))
		if l.is_empty() or String(l["kind"]) in ["ferry", "ship"]:
			continue
		var body := String(l["body"])
		if float(alphas.get(body, 0.0)) <= 0.02:
			continue
		var hot: bool = ov._hi(l["id"])
		if not ov.show and not hot:
			continue
		var n := int(counts.get(body, 0))
		if n >= MARKER_CAP:
			continue
		var e: Dictionary = _per[body]
		var mm: MultiMesh = (e["mm"] as MultiMeshInstance3D).multimesh
		var r := float(Astro.bodies[body]["radius_km"])
		var k := RouteOverlay.progress(l, t_rec, hour_f)
		if k <= 0.0005 or k >= 0.9995:
			continue            # 싣고 내리는 중 (도시에 서 있다 — 도시 점과 겹치지 않게)
		var fwd := String(t_rec["from"]) == String(l["a"])
		var kk := k if fwd else 1.0 - k
		var step := 0.01 if fwd else -0.01
		var p := point(l, r, kk)
		var p2 := point(l, r, clampf(kk + step, 0.0, 1.0))
		if p2.distance_squared_to(p) < 1e-14:
			p2 = p + (p - point(l, r, clampf(kk - step, 0.0, 1.0)))
		var kind := String(l["kind"])
		var col: Color = RouteOverlay.COLORS.get(kind, Color.WHITE)
		mm.set_instance_transform(n, Transform3D(Basis(), p))
		var dlt := p2 - p
		mm.set_instance_custom_data(n, Color(dlt.x, dlt.y, dlt.z, float(KIND_SHAPE.get(kind, 0.0))))
		mm.set_instance_color(n, Color(col, 1.0 if l["role"] == "local" else 0.75))
		counts[body] = n + 1
	for body in _per:
		var mm2: MultiMesh = (_per[body]["mm"] as MultiMeshInstance3D).multimesh
		mm2.visible_instance_count = int(counts.get(body, 0))
