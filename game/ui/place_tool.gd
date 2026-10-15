class_name PlaceTool
extends RefCounted
## 자리 고르기 도구 — 건물을 놓을 자리, 길 내기(종류·곡선·각도 맞춤), 길 지우기, 블록의 구획 정하기, 땅 고치기.
## 화면의 점을 땅 위의 점(모형 좌표, m)으로 바꾸는 일은 3D 보기가 하고, 도구는 그 점으로 판단한다.
## 마우스는 누르는 곳에 바로 짓고, 터치는 누른 곳으로 유령 건물을 옮긴 뒤 '여기에 짓기'로 짓는다.

signal changed
signal placed(kind: String, ok: bool, text: String)

const TERRAIN_OPS := ["dig", "raise", "flatten", "restore"]
const OP_NAMES := {"dig": "파기", "raise": "쌓기", "flatten": "평탄화", "restore": "되돌리기"}
const SNAP_DEG := 15.0             # 길 방향 맞춤 (기본 격자의 축 45°도 그 배수다)
const CURVE_PIECE_M := 10.0        # 굽은 길을 나누는 길이
const MAX_SWEEP_DEG := 200.0       # 한 번에 굽을 수 있는 각

var sim: CitySim
var plan: CityPlan
var ground: SiteGround             # 땅 높이·해수면 (평탄화·침수 안내)
var mode := ""                     # "" | "build" | "road" | "erase" | "zone" | "terrain"
var kind := ""
var rot := 0
var variant := 0
var at := Vector2.ZERO             # 유령 건물의 중심, 길의 끝점, 붓의 가운데 (모형 좌표)
var has_at := false
var reason := ""                   # 놓을 수 없는 까닭 ("" = 놓을 수 있다)
var note := ""                     # 막지는 않는 알림 (해수면 아래 …)
var tile := ""                     # 태양광 타워의 일조 구역
var road_from: Variant = null      # 길을 잇는 중이면 시작점 (Vector2)
var road_dir: Variant = null       # 이어 가던 길 끝의 방향 (곡선이 이어받는다)
var road_type := "street"
var curve := false                 # 곡선: 이어 가던 길에서 매끄럽게 굽는다
var angle_snap := true             # 방향을 15°마다 맞춘다
var preview := PackedVector2Array()   # 놓을 길의 점들 (곡선이면 여럿)
var road_len := 0.0
var road_cost := {}
var hover_edge := -1
var zone_kind := "core"            # 구획 칠하기: 칠할 용도 ("" = 비우기)
var hover_block := {}
var terrain_op := "dig"
var brush := 12.0


func bind(p_sim: CitySim, p_plan: CityPlan) -> void:
	sim = p_sim
	plan = p_plan
	stop()


func active() -> bool:
	return mode != ""


func body() -> String:
	return ground.body if ground != null else "moon"


func _reset(p_mode: String) -> void:
	mode = p_mode
	road_from = null
	road_dir = null
	preview = PackedVector2Array()
	has_at = false
	hover_edge = -1
	hover_block = {}
	reason = ""
	note = ""


func start_build(p_kind: String) -> void:
	_reset("build")
	kind = p_kind
	rot = 0
	variant = BaseScene.variant_of(kind, plan.count_of(kind)) if plan else 0
	tile = ""
	changed.emit()


func start_road(type: String = "") -> void:
	_reset("road")
	kind = ""
	if type != "":
		road_type = type
	if not road_type in LayoutData.road_types(body()):
		road_type = "street"
	changed.emit()


func start_erase() -> void:
	_reset("erase")
	kind = ""
	changed.emit()


func start_zone(district: String = "") -> void:
	_reset("zone")
	kind = ""
	if district != "" or zone_kind == "":
		zone_kind = district
	changed.emit()


func start_terrain(op: String = "") -> void:
	_reset("terrain")
	kind = ""
	if op in TERRAIN_OPS:
		terrain_op = op
	changed.emit()


func stop() -> void:
	_reset("")
	kind = ""
	changed.emit()


func set_road_type(type: String) -> void:
	road_type = type
	_recheck_road()
	changed.emit()


func set_curve(on: bool) -> void:
	curve = on
	_recheck_road()
	changed.emit()


func set_angle_snap(on: bool) -> void:
	angle_snap = on
	changed.emit()


func set_zone_kind(district: String) -> void:
	zone_kind = district
	changed.emit()


func set_terrain_op(op: String) -> void:
	terrain_op = op
	_recheck_terrain()
	changed.emit()


func set_brush(r: float) -> void:
	brush = r
	_recheck_terrain()
	changed.emit()


## 땅 위의 점을 가리킨다 (마우스를 움직이거나, 터치로 누를 때)
func hover(p: Vector2) -> void:
	match mode:
		"build":
			at = CityPlan.snap_center(kind, p, rot)
			has_at = true
			_recheck()
		"road":
			at = _road_snap(p)
			has_at = true
			_recheck_road()
		"erase":
			hover_edge = plan.nearest_edge(p, 6.0)
			has_at = true
		"zone":
			at = p
			has_at = true
			hover_block = plan.block_at(p)
			reason = "" if not hover_block.is_empty() else "블록 밖이다 — 길로 둘러싸인 블록을 누른다"
		"terrain":
			at = p
			has_at = true
			_recheck_terrain()
		_:
			return
	changed.emit()


## 마우스 누르기: 건물은 바로 짓는다 (keep이면 같은 건물을 계속 놓는다)
func click(p: Vector2, keep: bool = false) -> void:
	hover(p)
	match mode:
		"build":
			commit(keep)
		"road":
			_road_point()
		"erase":
			erase_hovered()
		"zone":
			paint_zone()
		"terrain":
			edit_ground()


## 터치 누르기: 건물은 유령만 옮기고, 길은 점을 찍고, 구획·땅은 바로 고친다
func tap(p: Vector2) -> void:
	hover(p)
	match mode:
		"road":
			_road_point()
		"erase":
			erase_hovered()
		"zone":
			paint_zone()
		"terrain":
			edit_ground()


func commit(keep: bool = false) -> bool:
	if mode != "build" or not has_at:
		return false
	_recheck()
	if reason != "":
		placed.emit(kind, false, reason)
		return false
	if not sim.enqueue(kind, tile, 0.0):
		placed.emit(kind, false, sim.build_block_reason(kind, 0.0))
		return false
	plan.add_queued(kind, at, rot, variant, sim.seq, tile)
	var built_kind := kind
	if keep:
		variant = (variant + 1) % maxi(1, ArtLib.variants(kind))
		_recheck()
		changed.emit()
	else:
		stop()
	placed.emit(built_kind, true, "")
	return true


## 기본 배치의 빈자리에 바로 짓는다
func auto_place() -> bool:
	if mode != "build":
		return false
	var want_tile := sim.free_tile() if CityPlan.fam(kind) == "solar_tower" else ""
	var s := plan.suggest(kind, want_tile)
	if s.is_empty():
		placed.emit(kind, false, "빈자리를 찾지 못했다")
		return false
	at = s["at"]
	rot = int(s["rot"])
	variant = int(s["variant"])
	has_at = true
	return commit(false)


func rotate() -> void:
	if mode != "build":
		return
	rot = (rot + 1) % 4
	if has_at:
		at = CityPlan.snap_center(kind, at, rot)
		_recheck()
	changed.emit()


func next_variant() -> void:
	if mode != "build":
		return
	variant = (variant + 1) % maxi(1, ArtLib.variants(kind))
	changed.emit()


## 길: 이어 가던 줄을 끝낸다 (도구는 그대로)
func end_chain() -> void:
	road_from = null
	road_dir = null
	_recheck_road()
	changed.emit()


func erase_hovered() -> void:
	if hover_edge >= 0:
		plan.remove_edge(hover_edge)
		hover_edge = -1
		changed.emit()


# ── 길 ──────────────────────────────────────────────────────────
## 길의 끝점: 가까운 꼭짓점·길에 먼저 붙고, 아니면 이어 가던 점에서 15°마다의 방향으로
func _road_snap(p: Vector2) -> Vector2:
	var s := plan.snap(p)
	if s.distance_to(p) > 0.01 or road_from == null or not angle_snap or (curve and road_dir != null):
		return s
	var from: Vector2 = road_from
	var d := p - from
	if d.length() < 1.0:
		return p
	var step := deg_to_rad(SNAP_DEG)
	var a := roundf(d.angle() / step) * step
	return from + Vector2(cos(a), sin(a)) * roundf(d.length())


## 놓을 길의 점들: 곧은 길이면 [시작, 끝], 곡선이면 이어 가던 방향에 닿는 원호를 나눈 점들
func _road_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if road_from == null:
		return out
	var a: Vector2 = road_from
	var b := at
	out.append(a)
	var d := b - a
	if curve and road_dir != null and d.length() > 3.0:
		var t: Vector2 = road_dir
		var n := Vector2(-t.y, t.x)
		var s := d.dot(n)
		if absf(s) > 0.02 * d.length():
			var r := d.length_squared() / (2.0 * s)        # 부호: + 왼쪽으로 굽는다
			var c := a + n * r
			var p0 := (a - c).angle()
			var p1 := (b - c).angle()
			var sweep := wrapf(p1 - p0, 0.0, TAU) if r > 0.0 else -wrapf(p0 - p1, 0.0, TAU)
			if absf(sweep) <= deg_to_rad(MAX_SWEEP_DEG):
				var arc := absf(sweep * r)
				var pieces := maxi(int(ceil(arc / CURVE_PIECE_M)), int(ceil(absf(sweep) / deg_to_rad(15.0))))
				pieces = clampi(pieces, 1, maxi(1, int(arc / 4.0)))
				for i in range(1, pieces):
					var ph := p0 + sweep * float(i) / pieces
					out.append(c + Vector2(cos(ph), sin(ph)) * absf(r))
	out.append(b)
	return out


## 곡선의 반지름 (곧으면 INF)
func curve_radius() -> float:
	if preview.size() < 3:
		return INF
	var a := preview[0]
	var b := preview[preview.size() - 1]
	var t: Vector2 = road_dir if road_dir != null else (b - a).normalized()
	var s := (b - a).dot(Vector2(-t.y, t.x))
	return absf((b - a).length_squared() / (2.0 * s)) if absf(s) > 1e-6 else INF


## 길의 끝 방향 (곡선이면 원호의 접선)
func _end_dir(pts: PackedVector2Array) -> Vector2:
	var n := pts.size()
	return (pts[n - 1] - pts[n - 2]).normalized() if n >= 2 else Vector2.RIGHT


## 막다른 꼭짓점에서 시작하면 그 길의 방향을 이어받는다
func _dead_end_dir(p: Vector2) -> Variant:
	for i in plan.nodes.size():
		if (plan.nodes[i] as Vector2).distance_to(p) > 0.6:
			continue
		if plan.degree(i) != 1:
			return null
		for e in plan.edges:
			if e.x == i:
				return (p - (plan.nodes[e.y] as Vector2)).normalized()
			if e.y == i:
				return (p - (plan.nodes[e.x] as Vector2)).normalized()
	return null


func _road_point() -> void:
	if road_from == null:
		if _in_bounds(at):
			road_from = at
			road_dir = _dead_end_dir(at)
			_recheck_road()
			changed.emit()
		return
	if reason != "" or preview.size() < 2 or road_len < 0.5:
		return
	var added := false
	for i in range(preview.size() - 1):
		if plan.add_road(preview[i], preview[i + 1], 0.6, road_type):
			added = true
	if added:
		for k in road_cost:
			sim.stock[k] = float(sim.stock.get(k, 0.0)) - float(road_cost[k])
	road_dir = _end_dir(preview)
	road_from = plan.snap(at, 0.6)
	_recheck_road()
	changed.emit()


func _recheck_road() -> void:
	note = ""
	preview = _road_points() if has_at else PackedVector2Array()
	road_len = 0.0
	for i in range(preview.size() - 1):
		road_len += preview[i].distance_to(preview[i + 1])
	road_cost = LayoutData.road_cost(road_type, road_len)
	if not has_at:
		reason = ""
		return
	if road_from == null:
		reason = "" if _in_bounds(at) else "기지 밖이다"
		return
	if (road_from as Vector2).distance_to(at) < 0.5:
		reason = ""             # 방금 찍은 점 — 다음 점을 기다린다
		return
	reason = ""
	var rmin := float(LayoutData.road(road_type)["turn_r_m"])
	var r := curve_radius()
	if r < rmin:
		reason = "너무 급히 굽는다 — %s은 반지름 %d m 이상 (지금 %d m)" % [LayoutData.road_name(road_type), int(rmin), int(r)]
		return
	for i in range(preview.size() - 1):
		var why := plan.road_check(preview[i], preview[i + 1], road_type)
		if why != "":
			reason = why
			return
	if sim != null and not road_cost.is_empty() and not sim.can_afford(road_cost, 0.0):
		reason = "자재 부족 — %s" % _cost_text(road_cost)
		return
	var slope := _max_slope()
	if slope > float(LayoutData.road(road_type)["grade"]) * 1.05:
		note = "비탈 %d%% — 땅을 깎고 메워 %d%%로 고른다" % [int(slope * 100.0), int(float(LayoutData.road(road_type)["grade"]) * 100.0)]


## 놓을 길을 따라 땅의 가장 가파른 기울기
func _max_slope() -> float:
	if ground == null or preview.size() < 2:
		return 0.0
	var best := 0.0
	for i in range(preview.size() - 1):
		var a := preview[i]
		var b := preview[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 6.0))
		var h0 := ground.local_height_m(a)
		for j in range(1, steps + 1):
			var p := a.lerp(b, float(j) / steps)
			var h1 := ground.local_height_m(p)
			best = maxf(best, absf(h1 - h0) / maxf(a.distance_to(b) / steps, 0.1))
			h0 = h1
	return best


static func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		var v := float(cost[k])
		if v <= 0.0:
			continue
		match k:
			"parts":
				parts.append("부품 %s" % Fmt.n(v, 1))
			"metal_t":
				parts.append("금속 %s t" % Fmt.n(v, 2))
			_:
				parts.append("%s %s" % [k, Fmt.n(v, 1)])
	return " · ".join(parts) if not parts.is_empty() else "무료"


# ── 구획 ────────────────────────────────────────────────────────
func paint_zone() -> void:
	if hover_block.is_empty():
		return
	if String(hover_block.get("district", "")) == zone_kind:
		return
	plan.set_district(at, zone_kind)
	hover_block = plan.block_at(at)
	changed.emit()


# ── 땅 고치기 ───────────────────────────────────────────────────
func _has_digger() -> bool:
	if sim == null:
		return true
	var need: Array = LayoutData.terrain()["need"]
	for k in sim.counts:
		if int(sim.counts[k]) > 0 and CityPlan.fam(String(k)) in need:
			return true
	return false


func _recheck_terrain() -> void:
	reason = ""
	note = ""
	if not has_at or plan == null:
		return
	var t := LayoutData.terrain()
	if not _has_digger():
		reason = "굴착기나 로봇 정비고가 있어야 땅을 고친다"
		return
	if at.distance_to(plan.hub()) > float(t["edit_radius_m"]):
		reason = "기지에서 %d m 안만 고친다" % int(t["edit_radius_m"])
		return
	var core := brush * 0.55
	for e in plan.buildings:
		if CityPlan._rect_point_dist(plan.entry_rect(e), at) < core:
			reason = "건물(%s) 밑은 고칠 수 없다" % GameData.module_name(String(e["id"]))
			return
	for k in plan.edges.size():
		var ed: Vector2i = plan.edges[k]
		var q := CityPlan._seg_point(plan.nodes[ed.x], plan.nodes[ed.y], at)
		if q.distance_to(at) < plan.edge_half(k) + core:
			reason = "길 밑은 고칠 수 없다 — 길을 지우고 고친다 (길 둘레는 길이 스스로 고른다)"
			return
	var now := plan.terrain_delta(at)
	reason = plan.terrain_block(at, brush, terrain_op, float(t["step_m"]))
	if reason != "":
		return
	if ground != null and not is_nan(ground.sea_z):
		var h := ground.base_height_m(at) + now - (float(t["step_m"]) if terrain_op == "dig" else 0.0)
		if h < ground.sea_z:
			note = "해수면 아래 %s m — 물이 찬다 (그 위의 건물은 멈춘다)" % Fmt.n(ground.sea_z - h, 1)


func edit_ground() -> int:
	if mode != "terrain" or not has_at:
		return 0
	_recheck_terrain()
	if reason != "":
		return 0
	var base_h := Callable()
	if ground != null:
		base_h = ground.base_height_m
	var n := plan.edit_terrain(at, brush, terrain_op, float(LayoutData.terrain()["step_m"]), base_h)
	_recheck_terrain()
	changed.emit()
	return n


func _in_bounds(p: Vector2) -> bool:
	var uv := BaseLayout.xy_to_uv(p)
	var crest := plan.layout.crest_v if plan else BaseLayout.CREST_V
	return BaseLayout.BOUNDS_UV.grow(-1.0).has_point(uv) and uv.y >= crest - 2.0


func _recheck() -> void:
	var r := plan.check(kind, at, rot, sim)
	reason = r["reason"]
	tile = r["tile"]


## 도구 막대에 쓸 글
func status() -> String:
	match mode:
		"build":
			var name := GameData.module_name(kind)
			var extra := ""
			if CityPlan.fam(kind) == "solar_tower":
				extra = " · 능선의 일조 구역에만 (A 100% · B 85% · C 70%)" if plan == null or plan.layout.kind == "ridge" \
					else " · 태양광 단지에만"
				if tile != "":
					extra = " · %s" % plan.layout.tile_name(tile)
			if not has_at:
				return "%s — 지을 자리를 고른다%s" % [name, extra]
			var dist := plan.district_at(at) if plan else ""
			if dist != "":
				extra += " · %s 블록" % LayoutData.zone_name(dist)
			return "%s%s" % [name, extra]
		"road":
			var rd := LayoutData.road(road_type)
			var head := "%s (폭 %s m)" % [String(rd["name"]), Fmt.n(float(rd["width_m"]), 0)]
			if road_from == null:
				return "%s — 시작점을 누른다. 길 끝은 가까운 길·꼭짓점에 붙는다" % head
			var more := " · 곡선" if curve and road_dir != null else ""
			if road_len > 0.5:
				return "%s — %d m · %s%s (끝내려면 '끝' 또는 오른쪽 클릭)" % [head, int(road_len), _cost_text(road_cost), more]
			return "%s — 다음 점을 누른다%s" % [head, more]
		"erase":
			if hover_edge >= 0:
				return "길 지우기 — %s를 지운다" % LayoutData.road_name(plan.edge_type(hover_edge))
			return "길 지우기 — 지울 길을 누른다"
		"zone":
			var what := LayoutData.zone_name(zone_kind) if zone_kind != "" else "빈 블록"
			if hover_block.is_empty():
				return "구획 — 블록을 눌러 '%s'(으)로 정한다" % what
			var cur := String(hover_block.get("district", ""))
			return "구획 — 이 블록: %s · %s m² → '%s'" % [LayoutData.zone_name(cur) if cur != "" else "빈 블록",
				Fmt.n(float(hover_block["area"]), 0), what]
		"terrain":
			var vol := plan.terrain_volume() if plan else Vector2.ZERO
			var here := plan.terrain_delta(at) if plan and has_at else 0.0
			return "땅 — %s · 붓 %d m · 누를 때마다 %s m · 이 자리 %s m · 판 흙 %s m³ · 쌓은 흙 %s m³" % [
				OP_NAMES.get(terrain_op, terrain_op), int(brush), Fmt.n(float(LayoutData.terrain()["step_m"]), 0),
				("+" if here >= 0.0 else "") + Fmt.n(here, 1), Fmt.n(vol.x, 0), Fmt.n(vol.y, 0)]
	return ""
