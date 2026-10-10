class_name PlaceTool
extends RefCounted
## 자리 고르기 도구 — 건물을 놓을 자리, 길 내기, 길 지우기. 3D 세계와 2D 지도가 같은 도구를 쓴다.
## 화면의 점을 땅 위의 점(모형 좌표, m)으로 바꾸는 일은 각 보기가 하고, 도구는 그 점으로 판단한다.
## 마우스는 누르는 곳에 바로 짓고, 터치는 누른 곳으로 유령 건물을 옮긴 뒤 '여기에 짓기'로 짓는다.

signal changed
signal placed(kind: String, ok: bool, text: String)

var sim: CitySim
var plan: CityPlan
var mode := ""                 # "" | "build" | "road" | "erase"
var kind := ""
var rot := 0
var variant := 0
var at := Vector2.ZERO         # 유령 건물의 중심, 또는 길의 끝점 (모형 좌표)
var has_at := false
var reason := ""               # 놓을 수 없는 까닭 ("" = 놓을 수 있다)
var tile := ""                 # 태양광 타워의 일조 구역
var road_from: Variant = null  # 길을 잇는 중이면 시작점 (Vector2)
var hover_edge := -1


func bind(p_sim: CitySim, p_plan: CityPlan) -> void:
	sim = p_sim
	plan = p_plan
	stop()


func active() -> bool:
	return mode != ""


func start_build(p_kind: String) -> void:
	mode = "build"
	kind = p_kind
	rot = 0
	variant = BaseScene.variant_of(kind, plan.count_of(kind)) if plan else 0
	has_at = false
	road_from = null
	hover_edge = -1
	reason = ""
	tile = ""
	changed.emit()


func start_road() -> void:
	mode = "road"
	kind = ""
	road_from = null
	has_at = false
	hover_edge = -1
	reason = ""
	changed.emit()


func start_erase() -> void:
	mode = "erase"
	kind = ""
	road_from = null
	has_at = false
	hover_edge = -1
	reason = ""
	changed.emit()


func stop() -> void:
	mode = ""
	kind = ""
	road_from = null
	has_at = false
	hover_edge = -1
	reason = ""
	changed.emit()


## 땅 위의 점을 가리킨다 (마우스를 움직이거나, 터치로 누를 때)
func hover(p: Vector2) -> void:
	match mode:
		"build":
			at = CityPlan.snap_center(kind, p, rot)
			has_at = true
			_recheck()
		"road":
			at = plan.snap(p)
			has_at = true
			_recheck_road()
		"erase":
			hover_edge = plan.nearest_edge(p, 6.0)
			has_at = true
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


## 터치 누르기: 건물은 유령만 옮기고, 길은 점을 찍는다
func tap(p: Vector2) -> void:
	hover(p)
	match mode:
		"road":
			_road_point()
		"erase":
			erase_hovered()


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
	_recheck_road()
	changed.emit()


func erase_hovered() -> void:
	if hover_edge >= 0:
		plan.remove_edge(hover_edge)
		hover_edge = -1
		changed.emit()


func _road_point() -> void:
	if road_from == null:
		if _in_bounds(at):
			road_from = at
			_recheck_road()
			changed.emit()
		return
	if reason != "":
		return
	if plan.add_road(road_from, at):
		road_from = plan.snap(at, 0.6)
	_recheck_road()
	changed.emit()


func _recheck() -> void:
	var r := plan.check(kind, at, rot, sim)
	reason = r["reason"]
	tile = r["tile"]


func _recheck_road() -> void:
	if not has_at:
		reason = ""
	elif road_from == null:
		reason = "" if _in_bounds(at) else "기지 밖이다"
	elif (road_from as Vector2).distance_to(at) < 0.5:
		reason = ""             # 방금 찍은 점 — 다음 점을 기다린다
	else:
		reason = plan.road_check(road_from, at)


static func _in_bounds(p: Vector2) -> bool:
	var uv := BaseLayout.xy_to_uv(p)
	return BaseLayout.BOUNDS_UV.grow(-1.0).has_point(uv) and uv.y >= BaseLayout.CREST_V - 2.0


## 도구 막대에 쓸 글
func status() -> String:
	match mode:
		"build":
			var name := GameData.module_name(kind)
			var extra := ""
			if CityPlan.fam(kind) == "solar_tower":
				extra = " · 능선의 일조 구역에만 (A 100% · B 85% · C 70%)"
				if tile != "":
					extra = " · %s 구역" % CityPlan.TILE_NAMES[tile]
			if not has_at:
				return "%s — 지을 자리를 고른다%s" % [name, extra]
			return "%s%s" % [name, extra]
		"road":
			return "길 — 점을 차례로 누른다. 길 끝은 가까운 길·꼭짓점에 붙는다" if road_from == null \
				else "길 — 다음 점을 누른다 (끝내려면 '끝' 또는 오른쪽 클릭)"
		"erase":
			return "길 지우기 — 지울 길을 누른다"
	return ""
