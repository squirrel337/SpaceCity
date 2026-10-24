class_name City3D
extends Node3D
## 3D 기지: 건물(자리마다 다섯 가지 모양), 공사 현장(비계), 길, 탈것, 밤의 불빛, 자리 고르기의 유령 건물,
## 구역 판(다진 바닥·테두리·필지 금·보행로·광장)과 구역 이름표, 다른 도시로 가는 고속도로와 활주로(지구·화성).
## 좌표는 부모(땅 SiteGround.city_root)의 모형 좌표: 미터, Godot 축 (x, z, -y), 원점 = 기지 평지.
## 무엇을 어디에 둘지는 배치 계획(CityPlan)과 규칙(BaseScene, BaseTraffic)을 쓴다. 달이든 다른 천체든 같다.

signal module_tapped(mid: String)

const VIS_SPEED := [0.0, 1.0, 1.6, 2.4]
const MESH_US := 3000              # 길 그물·구획 판을 짓는 데 한 프레임에 쓰는 시간 (μs)
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
var _bsig := ""                   # 고장 수 (바뀌면 표시만 고친다 — 자리·모형은 그대로)
var _seats := {}                  # 건물 uid → [앉는 자리, 기초(없으면 null)] — 땅이 그대로인 동안 (땅 높이를 다섯 곳 읽는 셈을 한 번만)
var _seats_sig := ""
var _groups := {}                 # "sprite/변형" → MultiMeshInstance3D
var _sites_root: Node3D
var _growing: Array = []          # 공정에 따라 바뀌는 공사 현장: [MeshInstance3D, _items의 번호, 앉는 자리] (_grow_sites)
var _grow_t := 0.0
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
var _models_wait := false         # 다른 스레드가 아직 만드는 모형이 있다 (다 되면 다시 그린다)
var _wait_h := 0.0                # 땅의 높이 격자를 기다린 시간 (s) — 굽기가 안 되면 2초 뒤 그냥 깐다
var _road_job: RoadMesh           # 짓는 중인 길 그물 메시
var _structs: MultiMeshInstance3D  # 높은 길의 받침
var _struct_mat: ShaderMaterial
var _district_job: _Job           # 짓는 중인 구획 판 메시
var _road_rev := -1
var _ghost: MeshInstance3D
var _ghost_key := ""
var _ghost_mat: ShaderMaterial
var _pad: MeshInstance3D
var _pad_mat: ShaderMaterial
var _pen: MeshInstance3D
var _pen_mesh: ImmediateMesh
var _pen_mat: ShaderMaterial
var _pen_sig := "-"
var _zones: MeshInstance3D
var _districts: MeshInstance3D
var _district_mat: ShaderMaterial
var _district_n := {}             # 구획 → 그 블록 위에 지어진 건물 수
var _count_sig := ""
var _district_sig := ""
var transport: Transport          # 도시 사이 교통 (고속도로·활주로·오가는 탈것)
var site_key := ""                # 이 도시의 부지 id
var highways := {}                # 노선 id → {a: 시작(길 그물의 끝), b: 끝, dir, other, km}
var runway := {}                  # {a, b, w} — 대기가 있는 천체의 비행기 기지 (지구·화성)
var bearings := {}                # 노선 id → 그 노선의 다른 도시 쪽 (모형 좌표 수평 단위 벡터)
var _ways: MeshInstance3D
var _ways_sig := "-"
var _plinths: MultiMeshInstance3D   # 비탈에 선 건물 아래의 기초


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
	_make_districts()
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
	for e in _agent_nodes.values():
		(e as Dictionary).erase("at")          # 서 있는 탈것도 새 땅 높이에 다시 놓는다
	_sig = ""
	_seats.clear()
	_road_rev = -1
	_ways_sig = "-"
	_district_sig = ""
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
	_seats.clear()
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
	plan.sync(sim, CityPlan.SYNC_FRAME_US)          # 오래 안 본 도시는 프레임마다 조금씩 맞춘다
	ground.apply_terrain(plan)
	# 길·구획·바깥 길은 땅의 높이 격자를 구운 뒤에 깐다 (굽기 전 높이는 셈이 몇 배 느리고, 구운 뒤 다시 깔아야 한다).
	# 길 그물·구획 판은 몇 프레임에 나눠 짓고 다 지으면 바꾼다 (그동안 옛 것이 보인다)
	var heights_ok := ground.baked_heights() or not ground.will_bake() or _wait_h > 2.0
	if not heights_ok:
		_wait_h += delta
	else:
		if plan.road_rev != _road_rev:
			_road_rev = plan.road_rev
			_road_job = RoadMesh.start(plan, _local)
		var dsig := "%d|%d|%d" % [plan.road_rev, plan.zone_rev, plan.terrain_rev]
		if dsig != _district_sig and _districts:
			_district_sig = dsig
			_district_job = _district_mesh_job()
		if _road_job != null:
			if _road_job.step(MESH_US):
				_set_roads(_road_job.mesh())
				_set_structs(_road_job)
				_road_job = null
		elif _district_job != null and _district_job.run(MESH_US):
			_districts.mesh = _district_job.geo.mesh()
			_district_job = null
	var sig := _signature()
	var bsig := _broken_sig()
	if sig != _sig or (_models_wait and ModelLib.pending() == 0):
		_sig = sig
		_bsig = bsig
		_rebuild()
	elif bsig != _bsig:
		_bsig = bsig
		_restatus()
	_update_tool()
	if not visible_now():
		# 카메라가 멀어 도시가 보이지 않으면 (고도 400 km 위·다른 천체) 탈것·불빛은 두고, 그동안의 도시 사이
		# 사건은 다시 보일 때 한꺼번에 띄우지 않는다
		traffic.forget_events()
		return
	if heights_ok:
		_update_ways()
	_grow_t += delta
	if _grow_t >= 0.25:
		_grow_t = 0.0
		_grow_sites()
	var sites := BaseScene.sites(sim, plan)
	if transport != null:
		traffic.intercity(transport, site_key, {"highways": highways, "runway": runway, "bearings": bearings})
	traffic.update(delta * VIS_SPEED[clampi(speed_level, 0, 3)], sim, sites)
	_sync_agents(delta)
	_night = move_toward(_night, 1.0 if sim.is_dark() else 0.0, delta / 0.8)
	if _road_mat:
		_road_mat.set_shader_parameter("night", _night)
	if _struct_mat:
		_struct_mat.set_shader_parameter("night", _night)
	if _district_mat:
		_district_mat.set_shader_parameter("night", _night)
	var sc := global_transform.basis.get_scale().x
	for l in _floods:
		(l as OmniLight3D).light_energy = 1.6 * _night
		(l as OmniLight3D).omni_range = 70.0 * sc
	if hovered != "" and _ring and not (tool and tool.active()):
		_ring.visible = true
		_ring.position = hovered_pos + Vector3(0, 0.15, 0)
	elif _ring:
		_ring.visible = false


## 배치가 바뀌었나 (계획의 판, 덮은 거주 모듈 수 — 모형이 바뀐다). 고장 수는 따로 (_broken_sig)
func _signature() -> String:
	return "%d,%d" % [plan.revision, sim.covered_habs]


func _broken_sig() -> String:
	var parts := PackedStringArray()
	for k in sim.broken:
		parts.append("%s:%d" % [k, int(sim.broken[k])])
	return ",".join(parts)


## 건물마다 앉는 자리 (uid로 기억해 둔다 — 건물은 옮겨지지 않는다. 땅을 고치거나 높이를 다시 구우면 버린다)
func _seats_of(items: Array, plinths: Array) -> Array:
	var tsig := "%d|%s" % [plan.terrain_rev, str(ground.baked_heights())]
	if tsig != _seats_sig:
		_seats_sig = tsig
		_seats.clear()
	var keep := {}
	var out: Array = []
	for it in items:
		var uid := int(it["uid"])
		var s: Array = _seats.get(uid, [])
		if s.is_empty():
			var pl: Array = []
			s = [_seat(it, pl), pl[0] if not pl.is_empty() else null]
		keep[uid] = s
		out.append(s[0])
		if s[1] != null:
			plinths.append(s[1])
	_seats = keep
	return out


## 고장 수만 바뀌었다: 표시(이름표·고장 표지)와 누를 상자만 새로 — 멀티메시·공사 현장은 그대로
## (그새 재건축이 헌 건물을 다 헐어 목록의 길이가 달라졌으면 다시 그린다)
func _restatus() -> void:
	var items := BaseScene.collect(sim, plan)
	if items.size() != _items.size():
		_rebuild()
		return
	_items = items
	var seats := _seats_of(_items, [])
	_set_boxes(seats)
	_grow_sites()


func _rebuild() -> void:
	_items = BaseScene.collect(sim, plan)
	_models_wait = false
	var plinths: Array = []
	var seats := _seats_of(_items, plinths)
	var by_key := {}
	for i in _items.size():
		var it: Dictionary = _items[i]
		if it["building"]:
			continue
		var key := "%s/%d" % [it["sprite"], it["variant"]]
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(i)
	# 멀티메시: 모양마다 하나 (처음 보는 모형은 다른 스레드가 만드는 동안 빼 두었다가 다 되면 다시 그린다)
	for key in _groups.keys():
		if not by_key.has(key):
			(_groups[key] as Node).queue_free()
			_groups.erase(key)
	for key in by_key:
		var list: Array = by_key[key]
		var mmi: MultiMeshInstance3D = _groups.get(key)
		if mmi == null:
			var parts := String(key).split("/")
			if not ModelLib.ready("buildings", parts[0], int(parts[1])):
				_models_wait = true
				continue
			mmi = MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = ModelLib.mesh("buildings", parts[0], int(parts[1]))
			mmi.multimesh = mm
			add_child(mmi)
			_groups[key] = mmi
		var m := mmi.multimesh
		m.instance_count = list.size()
		for i in list.size():
			m.set_instance_transform(i, seats[list[i]])
	# 공사 현장 (비계 — 재건축이면 헐리는 헌 건물도): 따로
	for c in _sites_root.get_children():
		c.queue_free()
	_growing.clear()
	for i in _items.size():
		var it: Dictionary = _items[i]
		if not it["building"]:
			continue
		var v := int(it["variant"])
		if not ModelLib.ready("buildings", it["sprite"], v):
			_models_wait = true
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = ModelLib.mesh("buildings", it["sprite"], v)
		mi.transform = seats[i]
		_sites_root.add_child(mi)
		if it.get("redev", false) or it.get("demolish", false) or String(it["sprite"]) == "scaffold_tower":
			_growing.append([mi, i, seats[i]])
	_set_boxes(seats)
	_set_plinths(plinths)
	_grow_sites()


## 공사 현장을 공정에 맞춘다: 재건축이면 앞부분(BaseScene.DEMOLISH)에는 헌 건물이 위에서부터 낮아지고 새 건물의 비계는
## 그 뒤에 선다. 높은 비계(scaffold_tower)는 바닥을 그 건물 크기에 맞추고 다 지은 높이의 12%부터 공정만큼 올라간다.
## 누를 상자도 따라간다 (다 헐린 건물은 상자를 비운다)
func _grow_sites() -> void:
	if _growing.is_empty():
		return
	var prog := {}
	for item in sim.queue:
		prog[int(item["seq"])] = clampf(1.0 - float(item["rd"]) / maxf(1e-6, float(item["rd_total"])), 0.0, 1.0)
	var demo := BaseScene.DEMOLISH
	for g in _growing:
		var mi: MeshInstance3D = g[0]
		var i := int(g[1])
		if i >= _items.size():
			continue
		var it: Dictionary = _items[i]
		var seat: Transform3D = g[2]
		var p := float(prog.get(int(it.get("seq", -1)), 1.0))
		var k := Vector3.ONE
		if it.get("demolish", false):
			mi.visible = p < demo
			k.y = maxf(1.0 - p / demo, 0.04)
		else:
			var q := p
			if it.get("redev", false):
				mi.visible = p >= demo
				q = (p - demo) / (1.0 - demo)
			if String(it["sprite"]) == "scaffold_tower":
				var f := ArtLib.footprint(String(it["id"]))
				var sf := ArtLib.footprint("scaffold_tower")
				k = Vector3(f.x / sf.x, ArtLib.height(String(it["id"])) * clampf(q, 0.12, 1.0)
					/ maxf(ArtLib.height("scaffold_tower"), 1.0), f.y / sf.y)
		var xf := Transform3D(seat.basis * Basis.from_scale(k), seat.origin)
		mi.transform = xf
		if i < _boxes.size():
			_boxes[i][0] = xf * mi.mesh.get_aabb() if mi.visible else AABB(xf.origin, Vector3.ZERO)


## 누를 상자 (모형이 아직이면 바닥 크기의 낮은 상자)
func _set_boxes(seats: Array) -> void:
	_boxes.clear()
	for i in _items.size():
		var it: Dictionary = _items[i]
		var aabb: AABB
		if ModelLib.ready("buildings", it["sprite"], it["variant"]):
			aabb = ModelLib.mesh("buildings", it["sprite"], it["variant"]).get_aabb()
		else:
			var f := CityPlan.foot_of(String(it["id"]), 0) * 0.5
			aabb = AABB(Vector3(-f.x, 0.0, -f.y), Vector3(f.x * 2.0, 4.0, f.y * 2.0))
		_boxes.append([(seats[i] as Transform3D) * aabb, it["id"], it])


## 건물이 앉는 자리: 바닥 네 귀와 가운데의 땅 높이 가운데 가장 높은 곳 (처음 기지는 평평해 가운데 높이와 같다).
## 땅이 0.25 m 넘게 기울었으면 그 아래에 기초(바닥보다 조금 넓은 판)를 쌓는다 — plinths에 더한다
func _seat(it: Dictionary, plinths: Array) -> Transform3D:
	var p3: Vector3 = it["pos"]
	var c := Vector2(p3.x, p3.y)
	var f := CityPlan.foot_of(String(it["id"]), int(it["rot"])) * 0.5
	var pos := _local(c)
	var top := pos.y
	var low := pos.y
	for q in [Vector2(-f.x, -f.y), Vector2(f.x, -f.y), Vector2(f.x, f.y), Vector2(-f.x, f.y)]:
		var h := _local(c + q).y
		top = maxf(top, h)
		low = minf(low, h)
	pos.y = top
	if top - low > 0.25:
		var hgt := top - low + 0.8
		plinths.append(Transform3D(Basis().scaled(Vector3(f.x * 2.0 + 0.8, hgt, f.y * 2.0 + 0.8)),
			Vector3(pos.x, top - hgt * 0.5 + 0.05, pos.z)))
	return Transform3D(_yaw(int(it["rot"])), pos)


func _set_plinths(list: Array) -> void:
	if _plinths == null:
		if list.is_empty():
			return
		_plinths = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = BoxMesh.new()
		_plinths.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.46, 0.45, 0.43)
		mat.roughness = 1.0
		_plinths.material_override = mat
		add_child(_plinths)
	_plinths.multimesh.instance_count = list.size()
	for i in list.size():
		_plinths.multimesh.set_instance_transform(i, list[i])


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
		var last: Vector3 = e["last"]
		var mv := Vector2(p.x - last.x, p.y - last.y)
		var want: float = e["yaw"]
		if mv.length() > 0.02:
			want = atan2(mv.y, mv.x)
		elif not a.get("flying", false):
			want = deg_to_rad(HEADING_DEG.get(a["heading"], rad_to_deg(want)))
		var thrust: bool = a.get("thrust", false)
		if p == last and not thrust and e.has("at") and absf(angle_difference(float(e["yaw"]), want)) < 0.0005:
			continue                             # 서서 다 돈 탈것: 그대로 둔다 (땅 높이를 다시 재지 않는다)
		var ground := _local(Vector2(p.x, p.y))
		var pos := ground + Vector3(0, p.z, 0)
		var yaw := lerp_angle(float(e["yaw"]), want, clampf(delta * 6.0, 0.0, 1.0))
		e["yaw"] = yaw
		e["last"] = p
		e["at"] = true
		var node: MeshInstance3D = e["node"]
		node.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		var plume: MeshInstance3D = e["plume"]
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
## 길 그물: 종류마다의 폭·무늬, 교차로 판, 굽은 곳, 막다른 곳 (RoadMesh). 땅을 따라가고 깊이에서 땅보다 앞선다
func _set_roads(mesh: ArrayMesh) -> void:
	if _roads == null:
		_roads = MeshInstance3D.new()
		if _road_mat == null:
			_road_mat = ShaderMaterial.new()
			_road_mat.shader = load("res://ui/world/shaders/road.gdshader")
		_roads.material_override = _road_mat
		_roads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_roads)
	_roads.mesh = mesh


## 높은 길의 받침 (교각·주탑·케이블·아치·트러스 — RoadStructs): 단위 상자 MultiMesh 하나
func _set_structs(rm: RoadMesh) -> void:
	if rm.sx.is_empty():
		if _structs != null:
			_structs.visible = false
		return
	if _structs == null:
		_structs = MultiMeshInstance3D.new()
		_struct_mat = ShaderMaterial.new()
		_struct_mat.shader = load("res://ui/world/shaders/bridge.gdshader")
		_structs.material_override = _struct_mat
		add_child(_structs)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = rm.sx.size()
	mm.buffer = rm.struct_buffer()
	_structs.multimesh = mm
	_structs.visible = true
	_structs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if int(Settings.q("shadow_splits")) > 0 \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	var psig := ""
	if tool != null and tool.mode == "land":
		psig = "land|%s|%s|%d|%d|%d|%s" % [str(tool.hover_parcel), str(ok), plan.land_rev, plan.road_rev, plan.terrain_rev,
			str(tool.has_at)]
	elif tool != null and tool.has_at:
		psig = "%s|%s|%s|%d|%s|%s|%s|%s|%d|%d|%s" % [tool.mode, str(tool.at), str(ok), tool.hover_edge, tool.road_type,
			tool.zone_kind, tool.terrain_op, str(tool.brush), plan.road_rev, plan.terrain_rev, str(tool.preview)]
		if tool.mode == "zone" and not tool.hover_block.is_empty():
			psig += str(tool.hover_block["center"])
	if psig == _pen_sig:
		return
	_pen_sig = psig
	_pen_mesh.clear_surfaces()
	if tool != null and tool.mode == "land":
		_draw_land(ok, good, bad)
		return
	if tool == null or not tool.has_at:
		return
	_pen_mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	match tool.mode:
		"road":
			# 놓을 길: 종류의 폭으로, 곡선이면 원호를 따라. 꺾이는 점은 둥글게
			var hw := LayoutData.road_half(tool.road_type)
			var rd := LayoutData.road(tool.road_type)
			_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			_pen_mesh.surface_set_color(Color(good if ok else bad, 0.6))
			if LayoutData.raised(tool.road_type):
				_ribbon(tool.preview, hw, float(rd.get("deck_m", 6.0)), float(rd.get("grade", 0.06)))      # 덱 높이로 (끝에서 오른다)
			else:
				_ribbon(tool.preview, hw)
			_pen_mesh.surface_set_color(Color(good if ok else bad, 0.95))
			if tool.road_from != null:
				_disc(tool.road_from, 2.2)
			_disc(tool.at, 2.2)
			_pen_mesh.surface_end()
		"erase":
			if tool.hover_edge >= 0 and tool.hover_edge < plan.edges.size():
				var e: Vector2i = plan.edges[tool.hover_edge]
				_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				_pen_mesh.surface_set_color(Color(bad, 0.65))
				_strip(plan.nodes[e.x], plan.nodes[e.y], plan.edge_half(tool.hover_edge) + 0.6)
				_pen_mesh.surface_end()
		"zone":
			# 고를 블록: 칠할 구획의 색으로 채우고 테두리
			if tool.hover_block.is_empty():
				return
			var col := LayoutData.zone_color(tool.zone_kind) if tool.zone_kind != "" else Color(0.82, 0.84, 0.88)
			var poly: PackedVector2Array = tool.hover_block["poly"]
			_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			_pen_mesh.surface_set_color(Color(col, 0.42))
			_fill_poly(poly)
			_pen_mesh.surface_set_color(Color(col.lightened(0.25), 0.95))
			for i in poly.size():
				_strip(poly[i], poly[(i + 1) % poly.size()], 0.45)
			_pen_mesh.surface_end()
		"terrain":
			# 붓: 바깥 고리(비탈이 끝나는 곳)와 안쪽 고리(다 고치는 곳)
			var oc := {"dig": Color(1.0, 0.62, 0.3), "raise": Color(0.5, 0.92, 0.45), "flatten": Color(0.45, 0.75, 1.0),
				"restore": Color(0.85, 0.85, 0.85)}
			var c: Color = oc.get(tool.terrain_op, Color.WHITE) if ok else bad
			_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			_pen_mesh.surface_set_color(Color(c, 0.9))
			_ring_strip(tool.at, tool.brush, 0.6)
			_pen_mesh.surface_set_color(Color(c, 0.55))
			_ring_strip(tool.at, tool.brush * 0.55, 0.35)
			_pen_mesh.surface_set_color(Color(c, 0.18))
			_disc(tool.at, tool.brush * 0.55)
			_pen_mesh.surface_end()


## 확장 도구: 처음 기지의 끝(흰 선), 산 구역(청록), 살 수 있는 구역(초록)·없는 구역(옅은 빨강), 가리키는 구역(채움)
func _draw_land(ok: bool, good: Color, bad: Color) -> void:
	_pen_mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	_pen_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := BaseLayout.BOUNDS_UV
	var corners: Array = []
	for uv in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
		corners.append(BaseLayout.uv_to_xy(uv))
	_pen_mesh.surface_set_color(Color(1, 1, 1, 0.4))
	for i in 4:
		_strip(corners[i], corners[(i + 1) % 4], 0.5)
	_pen_mesh.surface_set_color(Color(0.45, 0.85, 0.95, 0.7))
	for c in plan.land:
		_rect_outline(plan.parcel_rect(c), 0.9)
	for st in plan.land_candidates():
		var can: bool = st["ok"]
		_pen_mesh.surface_set_color(Color(0.4, 0.95, 0.55, 0.8) if can else Color(1.0, 0.42, 0.32, 0.35))
		_rect_outline((st["rect"] as Rect2).grow(-1.5), 0.7 if can else 0.45)
	if tool.has_at and not tool.parcel_info.is_empty() and not plan.land.has(tool.hover_parcel):
		var hr: Rect2 = tool.parcel_info["rect"]
		var c := good if ok else bad
		_pen_mesh.surface_set_color(Color(c, 0.28))
		_fill_poly(PackedVector2Array([hr.position, Vector2(hr.end.x, hr.position.y), hr.end, Vector2(hr.position.x, hr.end.y)]))
		_pen_mesh.surface_set_color(Color(c, 0.95))
		_rect_outline(hr.grow(-1.5), 1.1)
		for seg in tool.parcel_info.get("roads", []):
			_pen_mesh.surface_set_color(Color(1.0, 0.86, 0.45, 0.75))
			_strip(seg[0], seg[1], LayoutData.road_half(String(seg[2])))
	_pen_mesh.surface_end()


func _rect_outline(r: Rect2, w: float) -> void:
	var q := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		_strip(q[i], q[(i + 1) % 4], w)


## 길 미리보기: 점들을 잇는 띠 하나 — 꺾이는 점은 두 방향의 평균 법선으로 (토막이 겹쳐 진해지지 않게), 6 m마다 땅을 따라간다
func _ribbon(pts: PackedVector2Array, w: float, deck := 0.0, grade := 1.0) -> void:
	var n := pts.size()
	if n < 2:
		return
	var total := 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
		acc.append(total)
	var side: Array = []
	for i in n:
		var d := Vector2.ZERO
		if i > 0:
			d += (pts[i] - pts[i - 1]).normalized()
		if i < n - 1:
			d += (pts[i + 1] - pts[i]).normalized()
		d = d.normalized() if d.length_squared() > 1e-8 else Vector2.RIGHT
		var nn := Vector2(-d.y, d.x)
		var k := 1.0
		if i > 0 and i < n - 1:
			var d0 := (pts[i] - pts[i - 1]).normalized()
			k = 1.0 / maxf(0.5, nn.dot(Vector2(-d0.y, d0.x)))       # 꺾인 만큼 넓혀 폭을 지킨다
		side.append(nn * w * k)
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var na: Vector2 = side[i]
		var nb: Vector2 = side[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(b) / 6.0)))
		for s in steps:
			var t0 := float(s) / steps
			var t1 := float(s + 1) / steps
			var c0 := a.lerp(b, t0)
			var c1 := a.lerp(b, t1)
			var n0 := na.lerp(nb, t0)
			var n1 := na.lerp(nb, t1)
			var s0 := lerpf(acc[i], acc[i + 1], t0)
			var s1 := lerpf(acc[i], acc[i + 1], t1)
			var u0 := 0.3 + minf(deck, grade * minf(s0, total - s0))
			var u1 := 0.3 + minf(deck, grade * minf(s1, total - s1))
			var q := [_local(c0 - n0, u0), _local(c0 + n0, u0), _local(c1 + n1, u1), _local(c1 - n1, u1)]
			for j in [0, 1, 2, 0, 2, 3]:
				_pen_mesh.surface_add_vertex(q[j])


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
		var q := [_local(c0 - n, 0.3), _local(c0 + n, 0.3), _local(c1 + n, 0.3), _local(c1 - n, 0.3)]
		for i in [0, 1, 2, 0, 2, 3]:
			_pen_mesh.surface_add_vertex(q[i])


func _disc(c: Vector2, r: float) -> void:
	var segs := clampi(int(r * 1.5), 12, 40)
	var rings := maxi(1, int(ceil(r / 6.0)))
	for j in rings:
		var r0 := r * j / rings
		var r1 := r * (j + 1) / rings
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p00 := _local(c + Vector2(cos(a0), sin(a0)) * r0, 0.35)
			var p01 := _local(c + Vector2(cos(a1), sin(a1)) * r0, 0.35)
			var p10 := _local(c + Vector2(cos(a0), sin(a0)) * r1, 0.35)
			var p11 := _local(c + Vector2(cos(a1), sin(a1)) * r1, 0.35)
			for q in [p00, p10, p11, p00, p11, p01]:
				_pen_mesh.surface_add_vertex(q)


## 땅을 따라가는 고리 (반지름 r, 폭 w)
func _ring_strip(c: Vector2, r: float, w: float) -> void:
	var segs := clampi(int(r * 2.0), 24, 96)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var q := [_local(c + d0 * (r - w), 0.35), _local(c + d0 * (r + w), 0.35), _local(c + d1 * (r + w), 0.35),
			_local(c + d1 * (r - w), 0.35)]
		for i in [0, 1, 2, 0, 2, 3]:
			_pen_mesh.surface_add_vertex(q[i])


## 다각형 채우기: 세모로 나눈 뒤 6 m보다 큰 세모는 잘게 (땅을 따라가게)
func _fill_poly(poly: PackedVector2Array) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tri.size() - 2, 3):
		var a := poly[tri[i]]
		var b := poly[tri[i + 1]]
		var c := poly[tri[i + 2]]
		var n := clampi(int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / 6.0)), 1, 24)
		for u in n:
			for v in n - u:
				var p0 := a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n)
				var p1 := a + (b - a) * (float(u + 1) / n) + (c - a) * (float(v) / n)
				var p2 := a + (b - a) * (float(u) / n) + (c - a) * (float(v + 1) / n)
				for q in [p0, p1, p2]:
					_pen_mesh.surface_add_vertex(_local(q, 0.3))
				if u + v < n - 1:
					var p3 := a + (b - a) * (float(u + 1) / n) + (c - a) * (float(v + 1) / n)
					for q in [p1, p3, p2]:
						_pen_mesh.surface_add_vertex(_local(q, 0.3))


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
			if not (it["broken"] or it["building"]) or it.get("demolish", false):
				continue                         # 표시가 없는 건물은 화면 자리를 셈하지 않는다 (헐리는 건물은 새 건물의 공사 현장이 보인다)
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
	_draw_district_labels(view, ov, font, bold)
	_draw_way_signs(view, ov, font, bold)
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
	_shadow_text(ov, bold, Vector2(16, 76), title, 17, Palette.TEXT)        # 위쪽은 고정점 경로 막대
	_shadow_text(ov, font, Vector2(16, 96), state, 13, Palette.AMBER if lit else Palette.BLUE)
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
		_shadow_text(ov, bold, Vector2(16, 118), warn, 14, Palette.RED)
	if hovered != "":
		var label := String(sim.M[hovered]["name"]) if sim.M.has(hovered) else hovered
		var mp := view.get_local_mouse_position()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		ov.draw_rect(Rect2(mp + Vector2(14, 6), Vector2(w + 14, 22)), Color(0.06, 0.07, 0.1, 0.88))
		ov.draw_string(font, mp + Vector2(21, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)


func _progress_of(it: Dictionary) -> float:
	for item in sim.queue:
		if int(item["seq"]) == int(it.get("seq", -1)):
			return clampf(1.0 - float(item["rd"]) / maxf(1e-6, float(item["rd_total"])), 0.0, 1.0)
	return float(it["progress"]) if not it.has("seq") else 1.0


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


# ── 구역 판 ─────────────────────────────────────────────────────
## 땅에 깔리는 판의 정점·색·띠 (구역 판, 고속도로, 활주로가 함께 쓴다). 높이는 땅과 곡률을 따른다
class _Geo:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var city: City3D

	func _init(p_city: City3D) -> void:
		city = p_city

	func vert(p: Vector2, h: float, col: Color, u: Vector2) -> int:
		v.append(city._local(p, h))
		c.append(col)
		uv.append(u)
		n.append(Vector3.UP)
		return v.size() - 1

	## a → b 띠 (반너비 hw). UV.x = 가로 0~1 (glow > 0이면 UV.x 대신 그 값), UV.y = 길이 (m)
	func strip(a: Vector2, b: Vector2, hw: float, h: float, col: Color, glow := -1.0, step := 6.0) -> void:
		var d := b - a
		var length := d.length()
		if length < 0.01:
			return
		var nn := Vector2(-d.y, d.x) / length * hw
		var steps := maxi(1, int(ceil(length / step)))
		var base := v.size()
		for k in steps + 1:
			var t := float(k) / steps
			var q := a.lerp(b, t)
			for side in [-1.0, 1.0]:
				vert(q + nn * side, h, col, Vector2(glow if glow >= 0.0 else 0.5 + side * 0.5, t * length))
		for k in steps:
			var o := base + k * 2
			idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))

	func outline(r: Rect2, w: float, h: float, col: Color, glow := 0.0) -> void:
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			var a: Vector2 = p[i]
			var b: Vector2 = p[(i + 1) % 4]
			var e := (b - a).normalized() * w * 0.5
			strip(a - e, b + e, w * 0.5, h, col, glow)

	func grid(r: Rect2, h: float, col: Color, cell := 8.0) -> void:
		var nu := maxi(1, int(ceil(r.size.x / cell)))
		var nv := maxi(1, int(ceil(r.size.y / cell)))
		var base := v.size()
		for j in nv + 1:
			for i in nu + 1:
				vert(r.position + r.size * Vector2(float(i) / nu, float(j) / nv), h, col, Vector2.ZERO)
		for j in nv:
			for i in nu:
				var o := base + j * (nu + 1) + i
				idx.append_array(PackedInt32Array([o, o + 1, o + nu + 2, o, o + nu + 2, o + nu + 1]))

	## 다각형 판 (삼각형으로 나눠 땅을 따라)
	func poly(pts: PackedVector2Array, h: float, col: Color) -> void:
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			return
		var base := v.size()
		for p in pts:
			vert(p, h, col, Vector2.ZERO)
		for i in tri:
			idx.append(base + i)

	func outline_poly(pts: PackedVector2Array, w: float, h: float, col: Color, glow := 0.0) -> void:
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var e := (b - a).normalized() * w * 0.5
			strip(a - e, b + e, w * 0.5, h, col, glow)

	func disc(center: Vector2, rad: float, h: float, col: Color, segs := 32) -> void:
		var cidx := vert(center, h, col, Vector2.ZERO)
		for k in segs + 1:
			var a := TAU * k / segs
			vert(center + Vector2(cos(a), sin(a)) * rad, h, col, Vector2.ZERO)
		for k in segs:
			idx.append_array(PackedInt32Array([cidx, cidx + 2 + k, cidx + 1 + k]))

	func ring(center: Vector2, rad: float, w: float, h: float, col: Color, glow := 0.0, segs := 40) -> void:
		var base := v.size()
		for k in segs + 1:
			var a := TAU * k / segs
			var d := Vector2(cos(a), sin(a))
			vert(center + d * (rad - w * 0.5), h, col, Vector2(glow, 0.0))
			vert(center + d * (rad + w * 0.5), h, col, Vector2(glow, 0.0))
		for k in segs:
			var o := base + k * 2
			idx.append_array(PackedInt32Array([o, o + 1, o + 3, o, o + 3, o + 2]))

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if idx.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


func _make_districts() -> void:
	_districts = MeshInstance3D.new()
	_district_mat = ShaderMaterial.new()
	_district_mat.shader = load("res://ui/world/shaders/district.gdshader")
	_districts.material_override = _district_mat
	_districts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_districts)


## 블록 판: 길이 둘러싼 블록마다 (보도 안쪽) 구획 색이 옅게 섞인 다진 바닥과 빛나는 테두리 — 빈 블록은 옅은 회색.
## 기본 자리의 필지 금과 두 줄 사이 뒷길 (지금 같은 구획 블록 안의 것만), 우주항·얼음 분화구, 거주 구역 가운데 광장
## 조각(블록 하나, 구획 하나의 필지 금…)으로 나눠 몇 프레임에 짓는다
func _district_mesh_job() -> _Job:
	var g := _Geo.new(self)
	var job := _Job.new(g)
	for b in plan.blocks():
		job.steps.append(func() -> void:
			var d := String(b["district"])
			var col: Color = BaseLayout.district_info(d)[1]
			var poly: PackedVector2Array = b["poly"]
			var on := d != ""
			g.poly(poly, 0.035, Color(Color(0.14, 0.14, 0.15).lerp(col, 0.22 if on else 0.04), 0.3 if on else 0.16))
			g.outline_poly(poly, 1.0 if on else 0.45, 0.05, Color(col, 0.85 if on else 0.3), 1.0 if on else 0.0))
	for name in layout.lots:
		job.steps.append(func() -> void:
			for lot in layout.lots[name]:
				var c := (lot as Rect2).get_center()
				if name in BaseLayout.SPECIAL or plan.district_at(c) == name:
					g.outline(lot, 0.3, 0.045, Color(0.85, 0.86, 0.88, 0.3)))
	for name in layout.lanes:
		job.steps.append(func() -> void:
			for ln in layout.lanes[name]:
				if plan.district_at((ln[0] + ln[1]) * 0.5) == name:
					g.strip(ln[0], ln[1], 1.0, 0.04, Color(0.66, 0.64, 0.6, 0.28)))
	for name in BaseLayout.SPECIAL:
		var r: Rect2 = layout.rects.get(name, Rect2())
		if r.size != Vector2.ZERO:
			job.steps.append(func() -> void:
				var col2: Color = BaseLayout.district_info(name)[1]
				g.grid(r.grow(4.0), 0.035, Color(Color(0.14, 0.14, 0.15).lerp(col2, 0.22), 0.3))
				g.outline(r.grow(4.0), 1.1, 0.05, Color(col2, 0.85), 1.0))
	job.steps.append(func() -> void:
		var hub := Vector2(layout.hub.x, layout.hub.y)
		g.disc(hub, BaseLayout.PLAZA_R, 0.26, Color(0.62, 0.6, 0.56, 0.75))
		g.ring(hub, BaseLayout.PLAZA_R, 0.8, 0.27, Color(1.0, 0.78, 0.45, 0.8), 1.0)
		g.ring(hub, BaseLayout.PLAZA_R * 0.45, 0.5, 0.27, Color(0.85, 0.86, 0.88, 0.45)))
	return job


## 몇 프레임에 나눠 짓는 메시: 조각을 차례로 budget_us까지 (0이면 끝까지). 다 했으면 true
class _Job:
	var geo: _Geo
	var steps: Array = []
	var i := 0

	func _init(g: _Geo) -> void:
		geo = g

	func run(budget_us: int) -> bool:
		var t0 := Time.get_ticks_usec()
		while i < steps.size():
			(steps[i] as Callable).call()
			i += 1
			if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
				break
		return i >= steps.size()


## 구획마다 그 블록 위에 지어진 건물 수 (배치가 바뀔 때만 다시 센다)
func _count_districts() -> void:
	var sig := "%d|%d|%d" % [plan.revision, plan.road_rev, plan.zone_rev]
	if sig == _count_sig:
		return
	_count_sig = sig
	_district_n.clear()
	for e in plan.buildings:
		if int(e["seq"]) >= 0:
			continue
		var p := Vector2(float(e["x"]), float(e["y"]))
		var d := plan.district_at(p)
		if d == "":
			for name in BaseLayout.SPECIAL:
				if (layout.rects.get(name, Rect2()) as Rect2).grow(8.0).has_point(p):
					d = name
		if d != "":
			_district_n[d] = int(_district_n.get(d, 0)) + 1


## 구획 이름표: 기지를 내려다볼 때 (0.12~3.4 km) 구획마다 이름 · 지어진 건물 · 블록 · 필지 (가장 큰 블록 위)
func _draw_district_labels(view: WorldView, ov: Control, font: Font, bold: Font) -> void:
	var d := view.cam.dist
	var a := smoothstep(0.12, 0.2, d) * (1.0 - smoothstep(2.2, 3.4, d))
	if a < 0.03 or (tool != null and tool.active() and tool.mode != "zone"):
		return
	_count_districts()
	var where := {}
	var nblocks := {}
	for b in plan.blocks():
		var name := String(b["district"])
		if name == "":
			continue
		nblocks[name] = int(nblocks.get(name, 0)) + 1
		if not where.has(name) or float(b["area"]) > float(where[name][1]):
			where[name] = [b["center"], b["area"]]
	for name in BaseLayout.SPECIAL:
		var r: Rect2 = layout.rects.get(name, Rect2())
		if r.size != Vector2.ZERO:
			where[name] = [r.get_center(), 0.0]
	var placed: Array = []
	for name in where:
		var info: Array = BaseLayout.district_info(name)
		var sp: Variant = view.screen_of(global_transform * _local(where[name][0], 10.0))
		if sp == null:
			continue
		var s2: Vector2 = sp
		var text: String = info[0]
		var col: Color = info[1]
		var sub := "건물 %d · 필지 %d" % [int(_district_n.get(name, 0)), (layout.lots.get(name, []) as Array).size()]
		if nblocks.has(name):
			sub = "건물 %d · 블록 %d · 필지 %d" % [int(_district_n.get(name, 0)), int(nblocks[name]),
				(layout.lots.get(name, []) as Array).size()]
		var w := maxf(bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x,
			font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) + 22.0
		var rect := Rect2(s2 - Vector2(w * 0.5, 16.0), Vector2(w, 32.0))
		if not Rect2(Vector2.ZERO, view.size).intersects(rect):
			continue
		var clash := false
		for o in placed:
			if (o as Rect2).intersects(rect):
				clash = true
				break
		if clash:
			continue
		placed.append(rect)
		ov.draw_rect(rect, Color(0.04, 0.05, 0.08, 0.45 * a))
		ov.draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), Color(col, 0.95 * a))
		ov.draw_string(bold, rect.position + Vector2(10, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(col.lightened(0.45), a))
		ov.draw_string(font, rect.position + Vector2(10, 27), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.82, 0.84, 0.88, 0.85 * a))


# ── 다른 도시로 가는 길 ─────────────────────────────────────────
## 고속도로(땅길 노선마다)와 활주로(대기가 있는 천체): 노선이나 길 그물이 바뀌면 다시 놓는다
func _update_ways() -> void:
	var ids := PackedStringArray()
	if transport != null:
		for l in transport.lines_of(site_key):
			ids.append(String(l["id"]))
	var sig := "%s|%d|%s" % [",".join(ids), plan.road_rev, ground.body]
	if sig == _ways_sig:
		return
	_ways_sig = sig
	highways.clear()
	runway.clear()
	bearings.clear()
	var g := RoadMesh.new(_local)
	var hub := Vector2(layout.hub.x, layout.hub.y)
	if transport != null:
		for l in transport.lines_of(site_key):
			var other := String(l["b"]) if String(l["a"]) == site_key else String(l["a"])
			var dir := _bearing(Transport.node_dir(other))
			bearings[l["id"]] = dir
			if l["kind"] != "ground":
				continue
			# 그 방향으로 가장 바깥에 있는 길 그물의 꼭짓점에서 나간다
			var start := hub
			var best := -INF
			for q in plan.nodes:
				var rel: Vector2 = (q as Vector2) - hub
				var score := rel.dot(dir) - 0.5 * absf(rel.cross(dir))
				if score > best:
					best = score
					start = q
			var end_p := start + dir * 3200.0
			highways[l["id"]] = {"a": start, "b": end_p, "dir": dir, "other": other, "km": float(l["km"]), "mode": l["mode"]}
			g.ribbon(start, end_p, LayoutData.road_half("highway"), "highway")
	var rw := plan.runway()
	if not rw.is_empty():
		# 활주로: 기지 밖 격자의 땅 구역 한 줄에 블록과 나란히 (유도로는 길 그물의 대로 — 우주항 땅에서 곧게 온다)
		runway = {"a": rw["a"], "b": rw["b"], "w": rw["w"]}
		g.ribbon(rw["a"], rw["b"], float(rw["w"]) * 0.5, "runway")
	if _ways == null:
		_ways = MeshInstance3D.new()
		_ways.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ways)
	if _road_mat == null:
		_road_mat = ShaderMaterial.new()
		_road_mat.shader = load("res://ui/world/shaders/road.gdshader")
	_ways.material_override = _road_mat
	_ways.mesh = g.mesh()


## 다른 노드(천체 고정 방향)로 가는 방향 — 기지 모형 좌표의 수평 단위 벡터
func _bearing(other_dir: Vector3) -> Vector2:
	var up := ground.site_dir()
	var t := other_dir - up * up.dot(other_dir)
	var f := ground.site_frame()
	var d := Vector2(t.dot(f.x), t.dot(f.y))
	return d.normalized() if d.length_squared() > 1e-12 else Vector2(1, 0)


## 고속도로 들머리의 표지: "→ 마리우스 · 3,157 km"
func _draw_way_signs(view: WorldView, ov: Control, font: Font, bold: Font) -> void:
	var d := view.cam.dist
	var a := smoothstep(0.1, 0.18, d) * (1.0 - smoothstep(3.0, 5.0, d))
	if a < 0.03:
		return
	for id in highways:
		var h: Dictionary = highways[id]
		var at: Vector2 = (h["a"] as Vector2) + (h["dir"] as Vector2) * 60.0
		var sp: Variant = view.screen_of(global_transform * _local(at, 6.0))
		if sp == null:
			continue
		var text := "→ %s · %s km" % [Transport.node_name(h["other"]), Fmt.n(float(h["km"]))]
		var sub := Transport.mode_name(h["mode"])
		var w := maxf(bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x,
			font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 18.0
		var p: Vector2 = sp
		var rect := Rect2(p - Vector2(w * 0.5, 18), Vector2(w, 36))
		ov.draw_rect(rect, Color(0.12, 0.09, 0.03, 0.72 * a))
		ov.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)), Color(1.0, 0.72, 0.35, 0.9 * a))
		ov.draw_string(bold, rect.position + Vector2(9, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.82, 0.55, a))
		ov.draw_string(font, rect.position + Vector2(9, 31), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.86, 0.84, 0.8, 0.85 * a))
