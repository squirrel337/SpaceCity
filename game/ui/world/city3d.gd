class_name City3D
extends Node3D
## 3D 기지: 건물(자리마다 다섯 가지 모양), 공사 현장(비계), 길, 탈것, 밤의 불빛.
## 좌표는 부모(MoonSurface.city_root)의 모형 좌표: 미터, Godot 축 (x, z, -y), 원점 = 기지 평지.
## 무엇을 어디에 둘지는 2D 지도와 같은 규칙(BaseScene, BaseLayout, BaseTraffic)을 쓴다.

signal module_tapped(mid: String)

const VIS_SPEED := [0.0, 1.0, 1.6, 2.4]
const R_M := 1737400.0
const HEADING_DEG := {"se": 0.0, "sw": 90.0, "nw": 180.0, "ne": 270.0}

var sim: CitySim
var moon: MoonSurface
var layout: BaseLayout
var traffic: BaseTraffic
var hovered := ""
var hovered_pos := Vector3.ZERO

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


func setup(p_moon: MoonSurface) -> void:
	moon = p_moon
	layout = moon.layout
	traffic = BaseTraffic.new(layout)
	_sites_root = Node3D.new()
	add_child(_sites_root)
	_agents_root = Node3D.new()
	add_child(_agents_root)
	_build_roads()
	moon.terrain_ready.connect(_on_terrain_ready)
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
	if _roads:
		_roads.queue_free()
		_roads = null
	_build_roads()
	for i in _floods.size():
		var l: OmniLight3D = _floods[i]
		l.position = _local(Vector2(l.position.x, -l.position.z), 14.0)


func set_sim(new_sim: CitySim) -> void:
	sim = new_sim
	traffic.reset(sim)
	_sig = ""


func visible_now() -> bool:
	return is_visible_in_tree()


## 모형 좌표 (x, y)와 땅 위 높이 → 부모 로컬 좌표. 땅 높이와 달의 곡률을 넣는다
func _local(p: Vector2, above: float = 0.0) -> Vector3:
	var z := moon.local_height_m(p) - p.length_squared() / (2.0 * R_M) + above
	return Vector3(p.x, z, -p.y)


# ── 매 프레임 ───────────────────────────────────────────────────
func update(delta: float, speed_level: int) -> void:
	if sim == null:
		return
	_t += delta
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	var sites := BaseScene.sites(sim, layout)
	traffic.update(delta * VIS_SPEED[clampi(speed_level, 0, 3)], sim, sites)
	_sync_agents(delta)
	_night = move_toward(_night, 1.0 if sim.is_dark() else 0.0, delta / 0.8)
	if _road_mat:
		_road_mat.set_shader_parameter("night", _night)
	var sc := global_transform.basis.get_scale().x
	for l in _floods:
		(l as OmniLight3D).light_energy = 1.6 * _night
		(l as OmniLight3D).omni_range = 70.0 * sc
	if hovered != "" and _ring:
		_ring.visible = true
		_ring.position = hovered_pos + Vector3(0, 0.15, 0)
	elif _ring:
		_ring.visible = false


func _signature() -> String:
	var parts := PackedStringArray()
	var keys := sim.counts.keys()
	keys.sort()
	for k in keys:
		parts.append("%s:%d:%d" % [k, int(sim.counts[k]), int(sim.broken.get(k, 0))])
	for item in sim.queue:
		parts.append(String(item["id"]))
	parts.append(str(sim.covered_habs))
	return ",".join(parts)


func _rebuild() -> void:
	_items = BaseScene.collect(sim, layout)
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
			m.set_instance_transform(i, Transform3D(Basis(), _local(Vector2(p.x, p.y))))
	# 공사 현장 (비계): 따로
	for c in _sites_root.get_children():
		c.queue_free()
	for it in _items:
		if not it["building"]:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLib.mesh("buildings", it["sprite"], 0)
		var p2: Vector3 = it["pos"]
		mi.position = _local(Vector2(p2.x, p2.y))
		_sites_root.add_child(mi)
	# 누를 상자
	_boxes.clear()
	for it in _items:
		var mesh := ModelLib.mesh("buildings", it["sprite"], it["variant"])
		var box := mesh.get_aabb()
		var p3: Vector3 = it["pos"]
		box.position += _local(Vector2(p3.x, p3.y))
		_boxes.append([box, it["id"], it])


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
	for road in layout.roads:
		var along := 0.0
		for i in range(road.size() - 1):
			var a: Vector3 = road[i]
			var b: Vector3 = road[i + 1]
			var d := Vector2(b.x - a.x, b.y - a.y)
			var length := d.length()
			if length < 0.01:
				continue
			var dir := d / length
			var n := Vector2(-dir.y, dir.x) * w
			var a2 := Vector2(a.x, a.y) - dir * w
			var b2 := Vector2(b.x, b.y) + dir * w
			var steps := maxi(1, int(ceil((length + 2.0 * w) / 8.0)))
			var base := verts.size()
			for k in steps + 1:
				var t := float(k) / steps
				var c := a2.lerp(b2, t)
				for side in [-1.0, 1.0]:
					var q: Vector2 = c + n * side
					verts.append(_local(q, 0.06))
					uvs.append(Vector2(0.5 + side * 0.5, along + t * (length + 2.0 * w)))
					nrm.append(Vector3.UP)
			for k in steps:
				var o := base + k * 2
				idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
			along += length
	# 가운데 원형 광장
	var hub := Vector2(layout.hub.x, layout.hub.y)
	var center := verts.size()
	verts.append(_local(hub, 0.07))
	uvs.append(Vector2(0.5, 0.0))
	nrm.append(Vector3.UP)
	for i in 33:
		var a3 := TAU * i / 32.0
		verts.append(_local(hub + Vector2(cos(a3), sin(a3)) * 7.0, 0.07))
		uvs.append(Vector2(0.2, 0.0))
		nrm.append(Vector3.UP)
	for i in 32:
		idx.append_array(PackedInt32Array([center, center + 2 + i, center + 1 + i]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_roads = MeshInstance3D.new()
	_roads.mesh = mesh
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://ui/world/shaders/road.gdshader")
	_roads.material_override = _road_mat
	_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_roads)


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
				ov.draw_rect(Rect2(r.position, Vector2(44.0 * float(it["progress"]), 5)), Palette.AMBER)
			if int(it["more"]) > 0:
				ov.draw_string(bold, s2 + Vector2(10, 0), "+%d" % int(it["more"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Palette.AMBER)
	# 상태 (왼쪽 위)
	var lit := not sim.is_dark()
	var state := "일조 — 태양광 %s kW" % Fmt.n(sim.solar_kw)
	if not lit:
		state = "능선 그늘 — 태양광 0 kW, 축전 %s" % Fmt.pct((sim.battery + sim.rfc) / maxf(1.0, sim.bat_cap + sim.rfc_cap))
	_shadow_text(ov, bold, Vector2(16, 28), "섀클턴 시드 시티", 17, Palette.TEXT)
	_shadow_text(ov, font, Vector2(16, 48), state, 13, Palette.AMBER if lit else Palette.BLUE)
	var warn := ""
	if not sim.pending_storm.is_empty():
		warn = "태양 양성자 폭풍 경보"
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


static func _shadow_text(ov: Control, font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	ov.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	ov.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
