class_name City3D
extends Node3D
## 3D 기지: 건물(자리마다 다섯 가지 모양), 공사 현장(비계), 길, 탈것, 밤의 불빛, 자리 고르기의 유령 건물.
## 좌표는 부모(땅 SiteGround.city_root)의 모형 좌표: 미터, Godot 축 (x, z, -y), 원점 = 기지 평지.
## 무엇을 어디에 둘지는 배치 계획(CityPlan)과 규칙(BaseScene, BaseTraffic)을 쓴다. 달이든 다른 천체든 같다.

signal module_tapped(mid: String)

const VIS_SPEED := [0.0, 1.0, 1.6, 2.4]
const HEADING_DEG := {"se": 0.0, "sw": 90.0, "nw": 180.0, "ne": 270.0}

var sim: CitySim
var ground: SiteGround
var layout: BaseLayout
var plan: CityPlan
var tool: PlaceTool
var traffic: BaseTraffic
var hovered := ""
var hovered_pos := Vector3.ZERO
var title := "섀클턴 시드 시티"     # 왼쪽 위 이름 (식민지 이름)

var _items: Array = []
var _sig := ""
var _groups := {}                 # "sprite/변형" → MultiMeshInstance3D
var _sites_root: Node3D
var _agents_root: Node3D
var _agent_nodes := {}            # uid → {node, plume, yaw}
var _uid := 0
var _roads: MeshInstance3D
var _road_mat: ShaderMaterial
var _ring: MeshInstance3D
var _floods: Array = []
var _night := 0.0
var _t := 0.0
var _boxes: Array = []            # [AABB(로컬), id, item]
var _road_rev := -1
var _ghost: MeshInstance3D
var _ghost_key := ""
var _ghost_mat: ShaderMaterial
var _pad: MeshInstance3D
var _pad_mat: ShaderMaterial
var _pen: MeshInstance3D
var _pen_mesh: ImmediateMesh
var _pen_mat: ShaderMaterial
var _zones: MeshInstance3D


func setup(p_ground: SiteGround) -> void:
	ground = p_ground
	layout = ground.layout
	traffic = BaseTraffic.new()
	_sites_root = Node3D.new()
	add_child(_sites_root)
	_agents_root = Node3D.new()
	add_child(_agents_root)
	ground.terrain_ready.connect(_on_terrain_ready)
	_make_tool_nodes()
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh()
	var rm := ShaderMaterial.new()
	rm.shader = load("res://ui/world/shaders/marker.gdshader")
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	for g in ["core", "pad", "industry", "life", "farm", "power"]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.52)
		l.omni_range = 70.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		var gp: Vector3 = layout.hub if g == "core" else layout.gates[g]
		l.position = _local(Vector2(gp.x, gp.y), 14.0)
		_floods.append(l)


## 지형 높이를 구운 뒤: 건물·길을 새 높이에 다시 놓는다
func _on_terrain_ready() -> void:
	_sig = ""
	_road_rev = -1
	if _zones:
		_zones.mesh = _zone_mesh()
	for i in _floods.size():
		var l: OmniLight3D = _floods[i]
		l.position = _local(Vector2(l.position.x, -l.position.z), 14.0)


func set_sim(new_sim: CitySim, p_plan: CityPlan, p_tool: PlaceTool) -> void:
	sim = new_sim
	plan = p_plan
	tool = p_tool
	traffic.plan = plan
	traffic.reset(sim)
	_sig = ""
	_road_rev = -1


func visible_now() -> bool:
	return is_visible_in_tree()


## 모형 좌표 (x, y)와 땅 위 높이 → 부모 로컬 좌표. 땅 높이와 달의 곡률을 넣는다
func _local(p: Vector2, above: float = 0.0) -> Vector3:
	var z := ground.local_height_m(p) - p.length_squared() / (2.0 * ground.radius_m()) + above
	return Vector3(p.x, z, -p.y)


# ── 매 프레임 ───────────────────────────────────────────────────
func update(delta: float, speed_level: int) -> void:
	if sim == null or plan == null:
		return
	_t += delta
	plan.sync(sim)
	if plan.road_rev != _road_rev:
		_road_rev = plan.road_rev
		if _roads:
			_roads.queue_free()
			_roads = null
		_build_roads()
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	_update_tool()
	var sites := BaseScene.sites(sim, plan)
	traffic.update(delta * VIS_SPEED[clampi(speed_level, 0, 3)], sim, sites)
	_sync_agents(delta)
	_night = move_toward(_night, 1.0 if sim.is_dark() else 0.0, delta / 0.8)
	if _road_mat:
		_road_mat.set_shader_parameter("night", _night)
	var sc := global_transform.basis.get_scale().x
	for l in _floods:
		(l as OmniLight3D).light_energy = 1.6 * _night
		(l as OmniLight3D).omni_range = 70.0 * sc
	if hovered != "" and _ring and not (tool and tool.active()):
		_ring.visible = true
		_ring.position = hovered_pos + Vector3(0, 0.15, 0)
	elif _ring:
		_ring.visible = false


func _signature() -> String:
	var parts := PackedStringArray([str(plan.revision), str(sim.covered_habs)])
	for k in sim.broken:
		parts.append("%s:%d" % [k, int(sim.broken[k])])
	return ",".join(parts)


func _rebuild() -> void:
	_items = BaseScene.collect(sim, plan)
	var by_key := {}
	for it in _items:
		if it["building"]:
			continue
		var key := "%s/%d" % [it["sprite"], it["variant"]]
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(it)
	# 멀티메시: 모양마다 하나
	for key in _groups.keys():
		if not by_key.has(key):
			(_groups[key] as Node).queue_free()
			_groups.erase(key)
	for key in by_key:
		var list: Array = by_key[key]
		var mmi: MultiMeshInstance3D = _groups.get(key)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var parts := String(key).split("/")
			mm.mesh = ModelLib.mesh("buildings", parts[0], int(parts[1]))
			mmi.multimesh = mm
			add_child(mmi)
			_groups[key] = mmi
		var m := mmi.multimesh
		m.instance_count = list.size()
		for i in list.size():
			var p: Vector3 = list[i]["pos"]
			m.set_instance_transform(i, Transform3D(_yaw(int(list[i]["rot"])), _local(Vector2(p.x, p.y))))
	# 공사 현장 (비계): 따로
	for c in _sites_root.get_children():
		c.queue_free()
	for it in _items:
		if not it["building"]:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLib.mesh("buildings", it["sprite"], 0)
		var p2: Vector3 = it["pos"]
		mi.transform = Transform3D(_yaw(int(it["rot"])), _local(Vector2(p2.x, p2.y)))
		_sites_root.add_child(mi)
	# 누를 상자
	_boxes.clear()
	for it in _items:
		var mesh := ModelLib.mesh("buildings", it["sprite"], it["variant"])
		var p3: Vector3 = it["pos"]
		var box := Transform3D(_yaw(int(it["rot"])), _local(Vector2(p3.x, p3.y))) * mesh.get_aabb()
		_boxes.append([box, it["id"], it])


## 90° 단위 방향 (위에서 보아 시계 반대 방향)
static func _yaw(rot: int) -> Basis:
	return Basis(Vector3.UP, rot * PI * 0.5) if rot % 4 != 0 else Basis()


# ── 탈것 ────────────────────────────────────────────────────────
func _sync_agents(delta: float) -> void:
	var seen := {}
	for a in traffic.agents:
		if not a.has("uid"):
			_uid += 1
			a["uid"] = _uid
		var uid: int = a["uid"]
		seen[uid] = true
		var e: Dictionary = _agent_nodes.get(uid, {})
		if e.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = ModelLib.mesh("vehicles", a["id"])
			_agents_root.add_child(mi)
			var plume := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(2, 2)
			plume.mesh = q
			var pm := ShaderMaterial.new()
			pm.shader = load("res://ui/world/shaders/flame.gdshader")
			plume.material_override = pm
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plume.visible = false
			_agents_root.add_child(plume)
			e = {"node": mi, "plume": plume, "yaw": deg_to_rad(HEADING_DEG.get(a["heading"], 0.0)),
				"last": a["pos"]}
			_agent_nodes[uid] = e
		var p: Vector3 = a["pos"]
		var ground := _local(Vector2(p.x, p.y))
		var pos := ground + Vector3(0, p.z, 0)
		var last: Vector3 = e["last"]
		var mv := Vector2(p.x - last.x, p.y - last.y)
		var want: float = e["yaw"]
		if mv.length() > 0.02:
			want = atan2(mv.y, mv.x)
		elif not a.get("flying", false):
			want = deg_to_rad(HEADING_DEG.get(a["heading"], rad_to_deg(want)))
		var yaw := lerp_angle(float(e["yaw"]), want, clampf(delta * 6.0, 0.0, 1.0))
		e["yaw"] = yaw
		e["last"] = p
		var node: MeshInstance3D = e["node"]
		node.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		var plume: MeshInstance3D = e["plume"]
		var thrust: bool = a.get("thrust", false)
		plume.visible = thrust
		if thrust:
			var flick := 0.85 + 0.15 * sin(_t * 40.0 + float(uid))
			plume.transform = Transform3D(Basis().scaled(Vector3.ONE * 3.2 * flick), pos + Vector3(0, -0.6, 0))
	for uid in _agent_nodes.keys():
		if not seen.has(uid):
			var e2: Dictionary = _agent_nodes[uid]
			(e2["node"] as Node).queue_free()
			(e2["plume"] as Node).queue_free()
			_agent_nodes.erase(uid)


# ── 길 ──────────────────────────────────────────────────────────
func _build_roads() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var w := BaseLayout.ROAD_W * 0.5
	for e in plan.edges:
		var a: Vector2 = plan.nodes[e.x]
		var b: Vector2 = plan.nodes[e.y]
		var d := b - a
		var length := d.length()
		if length < 0.01:
			continue
		var dir := d / length
		var n := Vector2(-dir.y, dir.x) * w
		var steps := maxi(1, int(ceil(length / 8.0)))
		var base := verts.size()
		for k in steps + 1:
			var t := float(k) / steps
			var c := a.lerp(b, t)
			for side in [-1.0, 1.0]:
				var q: Vector2 = c + n * side
				verts.append(_local(q, 0.06))
				uvs.append(Vector2(0.5 + side * 0.5, t * length))
				nrm.append(Vector3.UP)
		for k in steps:
			var o := base + k * 2
			idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	# 꼭짓점의 둥근 이음 (꺾이거나 갈라지는 곳, 길 끝)
	for i in plan.nodes.size():
		var c2: Vector2 = plan.nodes[i]
		var center := verts.size()
		verts.append(_local(c2, 0.065))
		uvs.append(Vector2(0.5, 0.0))
		nrm.append(Vector3.UP)
		for k in 17:
			var a3 := TAU * k / 16.0
			verts.append(_local(c2 + Vector2(cos(a3), sin(a3)) * w, 0.065))
			uvs.append(Vector2(0.3, 0.0))
			nrm.append(Vector3.UP)
		for k in 16:
			idx.append_array(PackedInt32Array([center, center + 2 + k, center + 1 + k]))
	_roads = MeshInstance3D.new()
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_roads.mesh = mesh
	if _road_mat == null:
		_road_mat = ShaderMaterial.new()
		_road_mat.shader = load("res://ui/world/shaders/road.gdshader")
	_roads.material_override = _road_mat
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roads)


# ── 자리 고르기 ─────────────────────────────────────────────────
func _make_tool_nodes() -> void:
	_ghost = MeshInstance3D.new()
	_ghost_mat = ShaderMaterial.new()
	_ghost_mat.shader = load("res://ui/world/shaders/ghost.gdshader")
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	var overlay: Shader = load("res://ui/world/shaders/overlay.gdshader")
	_pad = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_pad.mesh = pm
	_pad_mat = ShaderMaterial.new()
	_pad_mat.shader = overlay
	_pad.material_override = _pad_mat
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pad.visible = false
	add_child(_pad)
	_pen_mesh = ImmediateMesh.new()
	_pen = MeshInstance3D.new()
	_pen.mesh = _pen_mesh
	_pen_mat = ShaderMaterial.new()
	_pen_mat.shader = overlay
	_pen.material_override = _pen_mat
	_pen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pen)
	_zones = MeshInstance3D.new()
	_zones.mesh = _zone_mesh()
	var zm := ShaderMaterial.new()
	zm.shader = overlay
	zm.set_shader_parameter("tint", Color(1, 1, 1, 0.3))
	_zones.material_override = zm
	_zones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zones.visible = false
	add_child(_zones)


const ZONE_COLORS := {"A": Color(1.0, 0.86, 0.35), "B": Color(1.0, 0.66, 0.3), "C": Color(0.85, 0.5, 0.32)}


## 능선의 일조 구역 (태양광 타워를 놓을 때만 보인다): 땅을 따라가는 격자 판
func _zone_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for t in layout.zones:
		for r in layout.zones[t]:
			var rect: Rect2 = r
			var nu := maxi(2, int(rect.size.x / 6.0))
			var nv := maxi(2, int(rect.size.y / 6.0))
			var base := verts.size()
			for j in nv + 1:
				for i in nu + 1:
					var uv := rect.position + rect.size * Vector2(float(i) / nu, float(j) / nv)
					verts.append(_local(BaseLayout.uv_to_xy(uv), 0.2))
					var edge := i == 0 or j == 0 or i == nu or j == nv
					var c: Color = ZONE_COLORS[t]
					c.a = 1.0 if edge else 0.55
					cols.append(c)
			for j in nv:
				for i in nu:
					var o := base + j * (nu + 1) + i
					idx.append_array(PackedInt32Array([o, o + 1, o + nu + 2, o, o + nu + 2, o + nu + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _update_tool() -> void:
	var building := tool != null and tool.mode == "build" and tool.has_at
	_ghost.visible = building
	_pad.visible = building
	_zones.visible = tool != null and tool.mode == "build" and CityPlan.fam(tool.kind) == "solar_tower"
	var ok := tool == null or tool.reason == ""
	var good := Color(0.35, 0.95, 0.55)
	var bad := Color(1.0, 0.32, 0.22)
	if building:
		var key := "%s/%d" % [tool.kind, tool.variant]
		if key != _ghost_key:
			_ghost.mesh = ModelLib.mesh("buildings", tool.kind, tool.variant)
			_ghost_key = key
		var c := good if ok else bad
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		_ghost_mat.set_shader_parameter("tint", Color(c, 0.62 + 0.18 * pulse))
		_ghost.transform = Transform3D(_yaw(tool.rot), _local(tool.at, 0.04))
		var f := CityPlan.foot_of(tool.kind, tool.rot)
		_pad.transform = Transform3D(Basis().scaled(Vector3(f.x + 2.0, 1.0, f.y + 2.0)), _local(tool.at, 0.15))
		_pad_mat.set_shader_parameter("tint", Color(c, 0.4 + 0.15 * pulse))
	_pen_mesh.clear_surfaces()
	if tool == null:
		return
	if tool.mode == "road" and tool.has_at:
		_pen_mat.set_shader_parameter("tint", Color(good if ok else bad, 0.6))
		_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if tool.road_from != null:
			_strip(tool.road_from, tool.at, BaseLayout.ROAD_W * 0.5)
			_disc(tool.road_from, 2.2)
		_disc(tool.at, 2.2)
		_pen_mesh.surface_end()
	elif tool.mode == "erase" and tool.hover_edge >= 0 and tool.hover_edge < plan.edges.size():
		_pen_mat.set_shader_parameter("tint", Color(bad, 0.65))
		var e: Vector2i = plan.edges[tool.hover_edge]
		_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_strip(plan.nodes[e.x], plan.nodes[e.y], BaseLayout.ROAD_W * 0.5 + 0.6)
		_pen_mesh.surface_end()


func _strip(a: Vector2, b: Vector2, w: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var n := Vector2(-d.y, d.x) / length * w
	var steps := maxi(1, int(ceil(length / 6.0)))
	for k in steps:
		var c0 := a.lerp(b, float(k) / steps)
		var c1 := a.lerp(b, float(k + 1) / steps)
		var q := [_local(c0 - n, 0.25), _local(c0 + n, 0.25), _local(c1 + n, 0.25), _local(c1 - n, 0.25)]
		for i in [0, 1, 2, 0, 2, 3]:
			_pen_mesh.surface_add_vertex(q[i])


func _disc(c: Vector2, r: float) -> void:
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		_pen_mesh.surface_add_vertex(_local(c, 0.3))
		_pen_mesh.surface_add_vertex(_local(c + Vector2(cos(a0), sin(a0)) * r, 0.3))
		_pen_mesh.surface_add_vertex(_local(c + Vector2(cos(a1), sin(a1)) * r, 0.3))


## 화면 점 → 땅 위의 점 (모형 좌표 m). 땅을 맞히지 않으면 null
func ground_at(view: WorldView, p: Vector2) -> Variant:
	var vp_pos := p * view.px_scale()
	var cam3 := view._camera
	var o := cam3.project_ray_origin(vp_pos)
	var dir := cam3.project_ray_normal(vp_pos)
	var inv := global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * dir).normalized()
	if ld.y > -1e-4:
		return null
	var t := -lo.y / ld.y
	for _i in 4:
		var q := lo + ld * t
		var g := _local(Vector2(q.x, -q.z)).y
		t += (q.y - g) / -ld.y
	if t <= 0.0:
		return null
	var hit := lo + ld * t
	return Vector2(hit.x, -hit.z)


func _ring_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in 65:
		var a := TAU * i / 64.0
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d * 0.9)
		verts.append(d * 1.1)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
	for i in 64:
		var k := i * 2
		idx.append_array(PackedInt32Array([k, k + 1, k + 3, k, k + 3, k + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# ── 고르기 ──────────────────────────────────────────────────────
## 화면 점 → 건물 (모듈 id, 없으면 "")
func pick(view: WorldView, p: Vector2) -> String:
	var hit := _pick_item(view, p)
	return hit[1] if not hit.is_empty() else ""


func _pick_item(view: WorldView, p: Vector2) -> Array:
	var vp_pos := p * view.px_scale()
	var cam3 := view._camera
	var o := cam3.project_ray_origin(vp_pos)
	var dir := cam3.project_ray_normal(vp_pos)
	var inv := global_transform.affine_inverse()
	var lo := inv * o
	var ld := (inv.basis * dir).normalized()
	var best: Array = []
	var best_t := INF
	for b in _boxes:
		var box: AABB = b[0]
		var hit: Variant = box.intersects_ray(lo, ld)
		if hit == null:
			continue
		var t := ((hit as Vector3) - lo).length()
		if t < best_t:
			best_t = t
			best = b
	return best


func hover(view: WorldView, p: Vector2) -> void:
	if tool and tool.active():
		hovered = ""
		return
	var hit := _pick_item(view, p)
	if hit.is_empty():
		hovered = ""
		return
	hovered = hit[1]
	var box: AABB = hit[0]
	hovered_pos = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var r := maxf(box.size.x, box.size.z) * 0.62
	_ring.scale = Vector3(r, 1.0, r)


# ── 화면 위 표시 ────────────────────────────────────────────────
func draw_overlay(view: WorldView, ov: Control, font: Font) -> void:
	if sim == null:
		return
	var bold: Font = ThemeFactory.bold if ThemeFactory.bold else font
	var dist_ok := view.cam.dist < 6.0
	if dist_ok:
		for b in _boxes:
			var it: Dictionary = b[2]
			var box: AABB = b[0]
			var top := global_transform * Vector3(box.get_center().x, box.end.y + 1.5, box.get_center().z)
			var sp: Variant = view.screen_of(top)
			if sp == null:
				continue
			var s2: Vector2 = sp
			if it["broken"]:
				var blink := 0.55 + 0.45 * sin(_t * 6.0)
				ov.draw_circle(s2, 10.0, Color(0.89, 0.34, 0.18, blink))
				ov.draw_string(bold, s2 + Vector2(-3.5, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			elif it["building"]:
				var r := Rect2(s2 - Vector2(22, 0), Vector2(44, 5))
				ov.draw_rect(r, Color(0, 0, 0, 0.6))
				ov.draw_rect(Rect2(r.position, Vector2(44.0 * _progress_of(it), 5)), Palette.AMBER)
	_draw_tool_overlay(view, ov, font, bold)
	# 상태 (왼쪽 위)
	var lit := not sim.is_dark()
	var ridge := layout.kind == "ridge"
	var state := "일조" if ridge else "낮"
	if sim.solar_kw > 0.0:
		state += " — 태양광 %s kW" % Fmt.n(sim.solar_kw)
	if not lit:
		state = "능선 그늘" if ridge else "밤"
		if sim.bat_cap + sim.rfc_cap > 0.0:
			state += " — 태양광 0 kW, 축전 %s" % Fmt.pct((sim.battery + sim.rfc) / maxf(1.0, sim.bat_cap + sim.rfc_cap))
	_shadow_text(ov, bold, Vector2(16, 28), title, 17, Palette.TEXT)
	_shadow_text(ov, font, Vector2(16, 48), state, 13, Palette.AMBER if lit else Palette.BLUE)
	var warn := ""
	if not sim.pending_storm.is_empty():
		warn = "태양 양성자 폭풍 경보"
	elif sim.in_dust_storm():
		warn = "먼지 폭풍 — 햇빛 %s" % Fmt.pct(sim.dust_factor)
	elif sim.rationing:
		warn = "식량 배급 중"
	var brown: float = sim.last_power.get("frac1", 1.0)
	if brown < 1.0:
		warn = "생명유지 감전 %d%%" % int(round(brown * 100))
	if warn != "":
		_shadow_text(ov, bold, Vector2(16, 70), warn, 14, Palette.RED)
	if hovered != "":
		var label := String(sim.M[hovered]["name"]) if sim.M.has(hovered) else hovered
		var mp := view.get_local_mouse_position()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		ov.draw_rect(Rect2(mp + Vector2(14, 6), Vector2(w + 14, 22)), Color(0.06, 0.07, 0.1, 0.88))
		ov.draw_string(font, mp + Vector2(21, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)


func _progress_of(it: Dictionary) -> float:
	var e := {}
	for b in plan.buildings:
		if int(b["uid"]) == int(it["uid"]):
			e = b
			break
	if e.is_empty():
		return float(it["progress"])
	for item in sim.queue:
		if int(item["seq"]) == int(e["seq"]):
			return clampf(1.0 - float(item["rd"]) / maxf(1e-6, float(item["rd_total"])), 0.0, 1.0)
	return 1.0


## 자리 고르기: 놓을 수 없는 까닭(유령 옆), 일조 구역 이름
func _draw_tool_overlay(view: WorldView, ov: Control, font: Font, bold: Font) -> void:
	if tool == null or not tool.active():
		return
	if tool.mode == "build" and CityPlan.fam(tool.kind) == "solar_tower":
		for t in layout.zones:
			var used := int(sim.tiles.get(t, 0))
			var cap := int(sim.C["illumination"]["tiles"][t])
			for r in layout.zones[t]:
				var c := BaseLayout.uv_to_xy((r as Rect2).get_center())
				var sp: Variant = view.screen_of(global_transform * _local(c, 6.0))
				if sp != null:
					_shadow_text(ov, bold, (sp as Vector2) - Vector2(40, 0), "%s · %d/%d" % [layout.tile_name(t), used, cap],
						13, ZONE_COLORS[t])
	if tool.has_at and tool.mode in ["build", "road"]:
		var sp1: Variant = view.screen_of(global_transform * _local(tool.at, 0.0))
		if sp1 != null:
			var c := Color(0.35, 0.95, 0.55) if tool.reason == "" else Color(1.0, 0.32, 0.22)
			ov.draw_arc(sp1, 16.0, 0.0, TAU, 32, Color(c, 0.9), 2.0)
			ov.draw_arc(sp1, 24.0 + 4.0 * sin(_t * 5.0), 0.0, TAU, 32, Color(c, 0.45), 1.5)
	if tool.has_at and tool.reason != "" and tool.mode in ["build", "road"]:
		var sp2: Variant = view.screen_of(global_transform * _local(tool.at, 2.0))
		if sp2 != null:
			var w := font.get_string_size(tool.reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at2 := (sp2 as Vector2) + Vector2(16, 10)
			ov.draw_rect(Rect2(at2 - Vector2(6, 16), Vector2(w + 12, 22)), Color(0.12, 0.03, 0.02, 0.85))
			ov.draw_string(font, at2, tool.reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.62, 0.5))


static func _shadow_text(ov: Control, font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	ov.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	ov.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
