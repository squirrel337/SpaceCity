class_name CityPlan
extends RefCounted
## 기지 배치 계획 — 건물마다의 자리·방향·모양, 그리고 길. 2D 지도와 3D 도시가 함께 쓰고, 저장 파일에 함께 들어간다.
##
## 시뮬레이션은 건물 개수와 공사 대기열만 안다. 계획은 거기에 자리를 붙인다.
## 플레이어가 고른 자리는 그 공사(대기열의 seq)에 묶이고, 자리를 고르지 않은 건물 — 처음 기지, 자동 운영,
## 옛 저장 — 은 기본 배치(BaseLayout)의 빈자리에, 그것도 막혔으면 구역 둘레의 빈터에 놓는다.
## 좌표는 BaseLayout과 같은 모형 좌표: 미터, x는 화면 오른쪽 아래, y는 왼쪽 아래. 방향 rot은 90° 단위(0~3).

signal changed

const VERSION := 2                                   # 2: 길 종류, 블록의 구획, 땅 고치기 (1도 읽는다)
const SPECIAL := ["regolith_cover", "robot"]        # 자리가 없는 공사
const SNAP_M := 6.0                                  # 길 끝을 꼭짓점·길에 붙이는 거리
const ROAD_HALF := BaseLayout.ROAD_W * 0.5
const SIDEWALK := 1.5                                # 길과 블록 사이 보도
const PAD_CLEAR_M := 30.0                            # 착륙장 둘레: 다른 건물 금지 (착륙 분사가 레골리스를 날린다)
const REACTOR_CLEAR_M := 60.0                        # 원자로와 사람이 사는 건물 사이
const PEOPLE := ["habitat", "safety", "research", "social", "commerce"]   # 사람이 머무는 분류
const REACTORS := ["fission_40kw", "fission_1mw"]             # 원자로 계열
const REPOSE := 0.8                                  # 판 비탈·쌓은 비탈의 가장 가파른 기울기 (흙의 안식각 약 39°)
## 모듈 데이터의 clearance_m가 있으면 그 거리를 쓴다 (매립형 원자로 20 m, 방벽 착륙장 15 m …)
const TILE_NAMES := {"A": "A 100%", "B": "B 85%", "C": "C 70%"}
const IDX_CELL := 16.0                               # 자리 찾기 색인의 칸 (m) — check_spot은 둘레 칸의 건물·길만 본다
const SYNC_FRAME_US := 3000                          # 보이는 도시의 배치를 시뮬레이션에 맞출 때 한 프레임에 쓰는 시간 (μs)
const SYNC_CATCHUP_US := 9000                        # 세 프레임 넘게 밀려 있으면 (불러오기·오래 안 본 도시) 한 프레임 몫을 늘린다
const SYNC_SHOW_MS := 250                            # 따라잡는 동안 이만큼마다 놓은 데까지 보여 준다
const RUNWAY := {"earth": [2400.0, 45.0], "mars": [700.0, 24.0]}   # 활주로 길이·폭 (m) — 대기가 있는 천체의 비행기 기지

var layout: BaseLayout
var buildings: Array = []          # {uid, id, x, y, rot, variant, seq(대기열 번호, 지어졌으면 -1), tile}
var nodes: Array = []              # 길 꼭짓점 Vector2
var edges: Array = []              # 길 Vector2i(꼭짓점, 꼭짓점)
var etypes: Array = []             # 길마다의 종류 (data/city_layout.json의 roads: path·street·avenue·highway·tube·rail)
var district_seeds: Array = []     # [[Vector2, 구획]] — 그 점이 든 블록의 용도 (길이 바뀌어도 블록이 이어받는다)
var terrain := {}                  # 땅 고치기: Vector2i(칸) → 높이 차 m (칸 = LayoutData.terrain().cell_m)
var flood := {}                    # 물에 잠긴 칸: Vector2i(칸) → 물 깊이 m (해수면 아래로 판 칸 — 땅이 셈해 적는다)
var revision := 0                  # 건물·길이 바뀔 때마다 +1
var road_rev := 0                  # 길이 바뀔 때마다 +1
var zone_rev := 0                  # 블록의 구획이 바뀔 때마다 +1
var terrain_rev := 0               # 땅을 고칠 때마다 +1
var flood_rev := 0                 # 물에 잠긴 칸이 바뀔 때마다 +1
var land := {}                     # 사들인 땅 구역: Vector2i(구역 번호) → true (구역 = 길 격자의 블록 cells×cells)
var land_rev := 0                  # 땅을 살 때마다 +1
var works: Array = []              # 길 공사 (RoadWorks — 넓히기·노선): {kind, a, b, type, p 공정, days, len, cost …}
var works_rev := 0                 # 길 공사가 늘거나 끝날 때마다 +1
var mega: Array = []               # 짓는 메가프로젝트 (CityProgress): {id, cell: 땅 구역, stage: 단계, p: 그 단계의 공정}
var mega_done: Array = []          # 다 지은 메가프로젝트: {id, cell}
var mega_rev := 0                  # 메가프로젝트가 늘거나 단계가 바뀌거나 끝날 때마다 +1
var scars: Array = []              # 최근 재난 (CityHazards): {kind, a, b — 줄이면 끝, r, hour} — 열둘까지
var ground: SiteGround             # 이 도시의 땅 (높이·물 — 땅 구역의 비탈, 새 땅의 건물 비탈). 없으면 따지지 않는다
var body := ""                     # 이 도시가 선 천체 (활주로가 있나)
var site_id := ""                  # 이 도시의 부지 (방위 — north_dir)
var auto_land := false             # 땅을 시드가 맡았다 (위임 — CityAuto, Colonies가 정한다): 자리가 없으면 땅을 산다
var on_auto: Callable              # 스스로 한 땅 일을 운영 기록으로 (CityAuto.recorder — 없으면 적지 않는다)
var runway_at: Array = []          # 활주로 자리 [쪽("+x"·"-x"·"+y"·"-y"), 땅 구역 줄 번호] — 처음 정하면 저장한다 (땅을 사도 옮겨 가지 않게)
var _runway := {}
var _runway_key := ""
var _cands: Array = []
var _cands_sig := ""
var _blocks: Array = []
var _blocks_sig := ""
var _dblocks := {}                 # 구획 → 그 구획의 블록들 (기지 가운데에서 가까운 것부터 — 블록이 바뀔 때만 다시 고른다)
var _dblocks_sig := ""
var _next_uid := 1
var _sig := ""
var _adj: Array = []
var _adj_rev := -1
var _fixed := {}
var _fixed_rev := -1
var _bidx := {}                    # 색인 칸 → 건물 번호들 (자리 찾기)
var _bidx_n := -1                  # 색인에 넣은 건물 수 (-1: 다시 만든다 — 건물을 뺐을 때)
var _brect: Array = []             # 건물마다 바닥 사각형 · 계열 (색인과 함께)
var _bfam: Array = []
var _bspecial: Array = []          # 착륙장·원자로: [번호, 거리 규칙만큼 넓힌 사각형] (거리 규칙이 멀리까지 닿는다)
var _eidx := {}                    # 색인 칸 → 길 번호들
var _lv: Array = []                # 높은 길의 사슬 (levels — 길이 바뀌면 다시 셈한다)
var _lv_rev := -1
var _eidx_sig := ""
var _sync_frame := -1              # 배치 따라잡기의 프레임 예산 (여러 곳에서 불러도 한 프레임에 한 몫)
var _sync_spent := 0
var _sync_late_f := -1             # 몫을 다 쓰고도 못 맞춘 마지막 프레임
var _sync_behind := 0              # 그렇게 이어진 프레임 수
var _sync_shown := 0               # 따라잡는 동안 마지막으로 보여 준 때 (ms)
var _sync_new := 0                 # 그 뒤로 놓은 건물 수
## 자리 찾기 커서: "종류|목록" → 앞에서부터 막힌 후보 수 (-1: 다 막혔다). 건물은 늘기만 하므로 한 번 막힌 후보는
## 길·구획·땅·지형·물·땅 높이가 그대로이고 건물이 빠지지 않는 한 계속 막혀 있다 — 그동안은 다시 따지지 않는다 (결과는 같다)
var _seek := {}
var _seek_sig := ""
var _bgen := 0                     # 건물이 빠질 때마다 +1 (빈자리가 생길 수 있다 — 커서를 버린다)
var _fam_built := {}             # 계열 → 지어진 자리들 (built_of_family — 배치가 바뀌면 비운다)
var _fam_rev := -1


func _init(p_layout: BaseLayout = null) -> void:
	layout = p_layout if p_layout != null else BaseLayout.new()


## 새 게임: 기본 길과 처음 건물
static func create(sim: CitySim, p_layout: BaseLayout = null) -> CityPlan:
	var plan := CityPlan.new(p_layout)
	plan.body = _body_of(sim)
	plan.site_id = sim.site_id if sim != null else ""
	plan.default_roads()
	plan._ensure_taxiway()
	if sim != null:
		plan.sync(sim)
	return plan


static func _body_of(sim: CitySim) -> String:
	return String(GameData.site(sim.site_id).get("body", "moon")) if sim != null else ""


func default_roads() -> void:
	for sg in layout.segments:
		add_road(sg[0], sg[1], 0.6, String(sg[2]))
	district_seeds.clear()
	for b in layout.blocks:
		if String(b["district"]) != "":
			district_seeds.append([(b["cell"] as Rect2).get_center(), String(b["district"])])
	zone_rev += 1


func hub() -> Vector2:
	return Vector2(layout.hub.x, layout.hub.y)


# ── 시뮬레이션과 맞추기 ─────────────────────────────────────────
## 시뮬레이션의 개수·대기열이 바뀌었으면 계획을 맞춘다: 끝난 공사는 지어진 건물로,
## 취소된 공사는 지우고, 자리 없는 공사·건물(자동 운영, 처음 기지)은 빈자리에 놓는다
## budget_us > 0: 이 프레임에 그만큼만 쓰고 (모든 부르는 곳이 함께 나눈다) 남은 자리 찾기는 다음 프레임에 잇는다 —
## 오래 안 본 도시를 고르거나 불러왔을 때 수십 채를 한 프레임에 놓지 않게. 세 프레임 넘게 밀려 있으면 몫을
## SYNC_CATCHUP_US로 늘리고, 따라잡는 동안 SYNC_SHOW_MS마다 놓은 데까지 바뀌었다고 알린다 (도시가 차례로 채워진다)
func sync(sim: CitySim, budget_us: int = 0) -> void:
	if sim == null:
		return
	var sig := _signature(sim)
	if sig == _sig:
		return
	var deadline := 0
	if budget_us > 0:
		var f := Engine.get_process_frames()
		if f != _sync_frame:
			_sync_frame = f
			_sync_spent = 0
		if _sync_behind >= 3 and budget_us >= SYNC_FRAME_US:
			budget_us = SYNC_CATCHUP_US       # 보이는 도시만 (보이지 않는 도시의 작은 몫은 그대로)
		if _sync_spent >= budget_us:
			return
		deadline = Time.get_ticks_usec() + budget_us - _sync_spent
	var live := {}
	for item in sim.queue:
		if String(item["id"]) in SPECIAL:
			continue
		live[int(item["seq"])] = item
	var finished := {}
	var built_n := {}
	for e in buildings:
		var kind: String = e["id"]
		if int(e["seq"]) >= 0:
			if not live.has(int(e["seq"])):
				if not finished.has(kind):
					finished[kind] = []
				finished[kind].append(e)
		else:
			built_n[kind] = int(built_n.get(kind, 0)) + 1
	var kinds := {}
	for k in sim.counts:
		kinds[k] = true
	for k in built_n:
		kinds[k] = true
	for k in finished:
		kinds[k] = true
	for kind in kinds:
		var want := int(sim.counts.get(kind, 0))
		var have := int(built_n.get(kind, 0))
		var fin: Array = finished.get(kind, [])
		fin.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
		while have < want and not fin.is_empty():
			var e: Dictionary = fin.pop_front()
			e["seq"] = -1
			e.erase("was")
			have += 1
		for e in fin:
			buildings.erase(e)
			_bidx_n = -1
			_bgen += 1
		while have < want:
			_auto_place(kind, -1, _tile_for_built(sim, kind), sim)
			have += 1
			_sync_new += 1
			if deadline > 0 and Time.get_ticks_usec() > deadline:
				_sync_pause(budget_us)
				return
		while have > want:
			for i in range(buildings.size() - 1, -1, -1):
				if buildings[i]["id"] == kind and int(buildings[i]["seq"]) < 0:
					buildings.remove_at(i)
					_bidx_n = -1
					_bgen += 1
					break
			have -= 1
	var planned := {}
	for e in buildings:
		if int(e["seq"]) >= 0:
			planned[int(e["seq"])] = true
	for item in sim.queue:
		var seq := int(item["seq"])
		if live.has(seq) and not planned.has(seq):
			_auto_place(String(item["id"]), seq, String(item.get("tile", "")), sim)
			_sync_new += 1
			if deadline > 0 and Time.get_ticks_usec() > deadline:
				_sync_pause(budget_us)
				return
	if deadline > 0:
		_sync_spent = budget_us - maxi(0, deadline - Time.get_ticks_usec())
	_sig = sig
	_sync_behind = 0
	_sync_new = 0
	_touch()


## 이 프레임의 몫을 다 썼다: 밀린 프레임을 세고, 따라잡는 동안 이따금 놓은 데까지 보여 준다
func _sync_pause(budget_us: int) -> void:
	_sync_spent = budget_us
	var f := Engine.get_process_frames()
	var now := Time.get_ticks_msec()
	if _sync_late_f != f:
		if _sync_late_f == f - 1:
			_sync_behind += 1
		else:
			_sync_behind = 1
			_sync_shown = now         # 새로 밀리기 시작했다 — 보여 주기는 SYNC_SHOW_MS 뒤부터
		_sync_late_f = f
	if _sync_new > 0 and now - _sync_shown >= SYNC_SHOW_MS:
		_sync_shown = now
		_sync_new = 0
		_touch()


func _signature(sim: CitySim) -> String:
	var parts := PackedStringArray()
	for k in sim.counts:
		parts.append("%s%d" % [k, int(sim.counts[k])])
	parts.append("|")
	for item in sim.queue:
		parts.append(str(int(item["seq"])))
	return ",".join(parts)


## 자리 없이 지어진 태양광 타워의 일조 칸: 시뮬레이션의 칸 수보다 계획에 모자란 칸
func _tile_for_built(sim: CitySim, kind: String) -> String:
	if fam(kind) != "solar_tower":
		return ""
	var have := {}
	for e in buildings:
		if fam(String(e["id"])) == "solar_tower":
			have[e["tile"]] = int(have.get(e["tile"], 0)) + 1
	var queued := {}
	for item in sim.queue:
		if fam(String(item["id"])) == "solar_tower":
			queued[item["tile"]] = int(queued.get(item["tile"], 0)) + 1
	for t in ["A", "B", "C"]:
		if int(have.get(t, 0)) < int(sim.tiles.get(t, 0)) - int(queued.get(t, 0)):
			return t
	return ""


func _touch() -> void:
	revision += 1
	changed.emit()


## 플레이어가 고른 자리의 공사
func add_queued(kind: String, at: Vector2, rot: int, variant: int, seq: int, tile: String = "") -> Dictionary:
	var e := {"uid": _next_uid, "id": kind, "x": at.x, "y": at.y, "rot": rot % 4, "variant": variant, "seq": seq,
		"tile": tile}
	_next_uid += 1
	buildings.append(e)
	_touch()
	return e


## 계열 (기본 모듈 id) — 배치 규칙과 기본 자리는 계열을 따른다
static func fam(kind: String) -> String:
	GameData.load_all()
	return GameData.FAM_OF.get(kind, kind)


static func _module(kind: String) -> Dictionary:
	GameData.load_all()
	return GameData.MODULES.get(kind, {})


## 이 건물이 지켜야 할 거리 (착륙장·원자로). 데이터에 없으면 계열의 기본값
static func clearance(kind: String) -> float:
	var m := _module(kind)
	if m.has("clearance_m"):
		return float(m["clearance_m"])
	var f := fam(kind)
	if f == "landing_pad":
		return PAD_CLEAR_M
	if f in REACTORS:
		return REACTOR_CLEAR_M
	return 0.0


static func _people(kind: String) -> bool:
	return String(_module(kind).get("category", "")) in PEOPLE


func count_of(kind: String) -> int:
	var n := 0
	for e in buildings:
		if e["id"] == kind:
			n += 1
	return n


func kind_of_uid(uid: int) -> String:
	for e in buildings:
		if int(e["uid"]) == uid:
			return String(e["id"])
	return ""


func entry_of_seq(seq: int) -> Dictionary:
	for e in buildings:
		if int(e["seq"]) == seq:
			return e
	return {}


# ── 자동 배치 ───────────────────────────────────────────────────
func _auto_place(kind: String, seq: int, tile: String, sim: CitySim = null) -> Dictionary:
	var auto := (auto_land or CityAuto.full(sim)) and fam(kind) != "solar_tower"
	# 자동 운영: 기본 자리와 그 구획의 블록이 다 찼으면 (구획을 가리지 않는 빈터 찾기 전에) 그 구획 가까이의 땅 구역을 산다
	var spot := suggest(kind, tile, not auto)
	if spot.is_empty() and auto and _auto_expand(kind, sim):
		spot = suggest(kind, tile, false)
	if spot.is_empty() and auto:
		spot = suggest(kind, tile)
	if spot.is_empty():
		# 놓을 곳이 없으면 구역 가운데에 겹쳐 둔다 (보이기만 하는 것이라 게임은 멈추지 않는다)
		var c := _anchor(kind)
		spot = {"at": c, "rot": 0, "variant": BaseScene.variant_of(kind, count_of(kind)), "tile": tile}
	var e := {"uid": _next_uid, "id": kind, "x": spot["at"].x, "y": spot["at"].y, "rot": int(spot["rot"]),
		"variant": int(spot["variant"]), "seq": seq, "tile": String(spot.get("tile", tile))}
	_next_uid += 1
	buildings.append(e)
	return e


## 이 종류를 놓기 좋은 빈자리: 기본 배치의 자리를 차례로, 그 구획의 블록, 다 막혔으면 구역 둘레를 나선으로 찾는다
## (spiral = false면 구획의 블록까지만 — 자동 운영은 그다음에 땅을 넓힌다).
## {at, rot, variant, tile} 또는 {}
func suggest(kind: String, tile: String = "", spiral: bool = true) -> Dictionary:
	if fam(kind) == "solar_tower":
		for i in layout.tower_slots.size():
			var ts: Array = layout.tower_slots[i]
			if tile != "" and ts[1] != tile:
				continue
			var p: Vector3 = ts[0]
			var at := Vector2(p.x, p.y)
			if check_spot(kind, at, 0).is_empty():
				return {"at": at, "rot": 0, "variant": BaseScene.variant_of(kind, i), "tile": zone_of(at)}
		return {}
	_seek_valid()
	var slots: Array = layout.slots.get(fam(kind), [])
	var sk := kind + "|slots"
	var from := int(_seek.get(sk, 0))
	if from >= 0:
		for i in range(from, slots.size()):
			var p: Vector3 = slots[i]
			var at := Vector2(p.x, p.y)
			if not _overlaps(rect_of(kind, at, 0)) and check_spot(kind, at, 0).is_empty():
				_seek[sk] = i
				return {"at": at, "rot": 0, "variant": BaseScene.variant_of(kind, i), "tile": ""}
		_seek[sk] = -1
	# 기본 자리가 다 찼으면: 그 구획으로 정한 블록 안 (플레이어가 새로 정한 블록도), 그다음 빈 블록
	var district: String = layout.district_of.get(fam(kind), "")
	if district != "" and not (district in BaseLayout.SPECIAL):
		var bs := _block_spot(kind, district)
		if not bs.is_empty():
			return bs
	if not spiral:
		return {}
	var spk := kind + "|spiral"
	var skip := int(_seek.get(spk, 0))
	if skip < 0:
		return {}
	var c := _anchor(kind)
	var f := ArtLib.footprint(kind)
	var step := clampf(minf(f.x, f.y) * 0.5, 2.0, 6.0)
	var variant := BaseScene.variant_of(kind, count_of(kind))
	var idx := 0                      # 나선의 후보 번호 (고리·방향·회전 순)
	var ring := 1
	while ring * step < 320.0:
		var r := ring * step
		var n := maxi(8, int(TAU * r / step))
		if idx + n * 2 <= skip:
			idx += n * 2              # 이 고리는 다 막혔다
			ring += 1
			continue
		for k in n:
			var a := TAU * k / n
			var at := (c + Vector2(cos(a), sin(a)) * r).snapped(Vector2.ONE)
			for rot in [0, 1]:
				if idx >= skip and not _overlaps(rect_of(kind, at, rot)) and check_spot(kind, at, rot).is_empty():
					_seek[spk] = idx
					return {"at": at, "rot": rot, "variant": variant, "tile": ""}
				idx += 1
		ring += 1
	_seek[spk] = -1
	return {}


## 그 구획의 블록들 — 기지 가운데에서 가까운 것부터 (블록이 바뀔 때만 다시 고른다)
func _district_blocks(district: String) -> Array:
	var all := blocks()
	if _dblocks_sig != _blocks_sig:
		_dblocks_sig = _blocks_sig
		_dblocks.clear()
	if not _dblocks.has(district):
		var hubp := hub()
		var list := all.filter(func(b): return String(b["district"]) == district)
		list.sort_custom(func(x, y): return (x["center"] as Vector2).distance_to(hubp) < (y["center"] as Vector2).distance_to(hubp))
		_dblocks[district] = list
	return _dblocks[district]


## 자리 찾기 커서를 쓸 수 있나: 길·구획·땅·지형·물·땅 높이 중 하나라도 바뀌었거나 건물이 빠졌으면 버린다
func _seek_valid() -> void:
	var sig := "%d|%d|%d|%d|%d|%d|%d|%s" % [road_rev, zone_rev, land_rev, terrain_rev, flood_rev, _bgen, works_rev,
		str(ground != null and ground.baked_heights()) if ground != null else "-"]
	if sig != _seek_sig:
		_seek_sig = sig
		_seek.clear()


## 다른 건물과 바닥이 겹치나 — 자리 찾기가 찬 자리를 check_spot 없이 넘긴다 (겹치면 check_spot도 막는다)
func _overlaps(r: Rect2) -> bool:
	_bindex()
	var inner := r.grow(-0.05)
	for c in _cells_of(r):
		for i in _bidx.get(c, []):
			if inner.intersects(_brect[i]):
				return true
	return false


func _anchor(kind: String) -> Vector2:
	var d: String = layout.district_of.get(fam(kind), "")
	if d != "" and layout.rects.has(d):
		return (layout.rects[d] as Rect2).get_center()
	return hub()


# ── 놓을 수 있나 ────────────────────────────────────────────────
static func foot_of(kind: String, rot: int) -> Vector2:
	var f := ArtLib.footprint(kind)
	return Vector2(f.y, f.x) if rot % 2 == 1 else f


static func rect_of(kind: String, at: Vector2, rot: int) -> Rect2:
	var f := foot_of(kind, rot)
	return Rect2(at - f * 0.5, f)


func entry_rect(e: Dictionary) -> Rect2:
	return rect_of(String(e["id"]), Vector2(e["x"], e["y"]), int(e["rot"]))


## 바닥 칸을 1 m 격자에 맞춘 중심 (가장자리가 격자 위에 온다)
static func snap_center(kind: String, p: Vector2, rot: int) -> Vector2:
	var f := foot_of(kind, rot)
	var lo := (p - f * 0.5).round()
	return lo + f * 0.5


## 일조 구역 (태양광 타워 자리) — "A"·"B"·"C" 또는 ""
func zone_of(at: Vector2) -> String:
	var uv := BaseLayout.xy_to_uv(at)
	for t in layout.zones:
		for r in layout.zones[t]:
			if (r as Rect2).has_point(uv):
				return t
	return ""


## 땅 모양과 다른 건물·길만 따진다 (자재·연구는 check에서). 놓을 수 있으면 "", 아니면 까닭
func check_spot(kind: String, at: Vector2, rot: int, ignore_uid: int = -1, ignore: Dictionary = {}) -> String:
	var r := rect_of(kind, at, rot)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if not in_land(corner, 2.0, 2.0):
			return "기지 밖이다 — '확장'으로 땅 구역을 산다"
	var zone := zone_of(at)
	var kfam := fam(kind)
	if kfam == "solar_tower":
		if zone == "":
			return "태양광 타워는 %s에만 세운다" % layout.zone_text()
	elif zone != "" or _touches_zone(r):
		return "%s은 태양광 타워 자리다" % layout.zone_text()
	var ice := Vector2(layout.ice_center.x, layout.ice_center.y)
	if kfam == "ice_miner":
		if at.distance_to(ice) > BaseLayout.ICE_CRATER_R:
			return "얼음 채굴기는 %s 안에 세운다" % layout.ice_text()
	elif _rect_point_dist(r, ice) < BaseLayout.ICE_CRATER_R:
		return "%s 안에는 지을 수 없다" % layout.ice_text().split("(")[0]
	var inner := r.grow(-0.05)
	var k_pad := kfam == "landing_pad"
	var k_reactor := kfam in REACTORS
	var k_clear := clearance(kind) if k_pad or k_reactor else 0.0
	var k_people := _people(kind)
	for bi in _near_buildings(r, k_clear):
		var e: Dictionary = buildings[bi]
		if int(e["uid"]) == ignore_uid or ignore.has(int(e["uid"])):
			continue
		var er: Rect2 = _brect[bi]
		if inner.intersects(er):
			return "다른 건물(%s)과 겹친다" % GameData.module_name(String(e["id"]))
		var other: String = e["id"]
		var ofam: String = _bfam[bi]
		if k_pad and ofam != "landing_pad" and _rect_dist(r, er) < k_clear:
			return "착륙장 둘레 %d m 안에 건물이 있다 (착륙 분사)" % int(k_clear)
		if ofam == "landing_pad" and not k_pad and _rect_dist(r, er) < clearance(other):
			return "착륙장에서 %d m 넘게 떨어져야 한다 (착륙 분사)" % int(clearance(other))
		if k_reactor and _people(other) and _rect_dist(r, er) < k_clear:
			return "이 원자로는 사람이 머무는 건물에서 %d m 넘게 떨어져야 한다" % int(k_clear)
		if ofam in REACTORS and k_people and _rect_dist(r, er) < clearance(other):
			return "원자로(%s)에서 %d m 넘게 떨어져야 한다" % [GameData.module_name(other), int(clearance(other))]
	for k in _near_edges(r):
		var ed: Vector2i = edges[k]
		if _seg_rect_dist(nodes[ed.x], nodes[ed.y], r) < edge_half(k) - 0.05:
			return "길 위에는 지을 수 없다"
	for w in works:
		if _seg_rect_dist(w["a"], w["b"], r) < LayoutData.road_half(String(w["type"])) + 0.5:
			return "길 공사 자리다 (%s)" % RoadWorks.title(w)
	for mr in mega_rects():
		if (mr as Rect2).intersects(r):
			return "메가프로젝트 자리다"
	if flooded_in(r) > 0:
		return "물에 잠긴 땅이다 — 먼저 메운다"
	return _ground_reason(r)


# ── 자리 찾기 색인 ──────────────────────────────────────────────
## 건물·길을 16 m 칸에 나눠 두고 check_spot은 둘레 칸의 것만 본다 (결과는 다 훑을 때와 같다 — 건물은 배열 순서대로).
## 건물은 늘기만 하면 새 것만 넣고, 빼면 다시 만든다. 길은 road_rev·개수가 바뀌면 다시 만든다
static func _cells_of(r: Rect2) -> Array:
	var out: Array = []
	var x1 := int(floor(r.end.x / IDX_CELL))
	var y1 := int(floor(r.end.y / IDX_CELL))
	for x in range(int(floor(r.position.x / IDX_CELL)), x1 + 1):
		for y in range(int(floor(r.position.y / IDX_CELL)), y1 + 1):
			out.append(Vector2i(x, y))
	return out


func _bindex() -> void:
	if _bidx_n < 0 or _bidx_n > buildings.size():
		_bidx = {}
		_brect = []
		_bfam = []
		_bspecial = []
		_bidx_n = 0
	while _bidx_n < buildings.size():
		var e: Dictionary = buildings[_bidx_n]
		var f := fam(String(e["id"]))
		var er := entry_rect(e)
		_brect.append(er)
		_bfam.append(f)
		if f == "landing_pad" or f in REACTORS:
			_bspecial.append([_bidx_n, er.grow(clearance(String(e["id"])))])
		for c in _cells_of(er):
			if _bidx.has(c):
				(_bidx[c] as Array).append(_bidx_n)
			else:
				_bidx[c] = [_bidx_n]
		_bidx_n += 1


## r(과 reach m 둘레)에 닿을 수 있는 건물의 번호 (배열 순서) — 착륙장·원자로는 그 거리 규칙만큼 넓혀 본다
func _near_buildings(r: Rect2, reach: float = 0.0) -> PackedInt32Array:
	_bindex()
	var seen := {}
	for sp in _bspecial:
		if (sp[1] as Rect2).intersects(r):
			seen[sp[0]] = true
	for c in _cells_of(r.grow(reach)):
		for i in _bidx.get(c, []):
			seen[i] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## r에 반폭만큼 닿을 수 있는 길의 번호
func _near_edges(r: Rect2) -> Array:
	var sig := "%d|%d|%d" % [road_rev, edges.size(), nodes.size()]
	if sig != _eidx_sig:
		_eidx_sig = sig
		_eidx = {}
		for k in edges.size():
			var ed: Vector2i = edges[k]
			for c in _cells_of(Rect2(nodes[ed.x], Vector2.ZERO).expand(nodes[ed.y]).grow(edge_half(k))):
				if _eidx.has(c):
					(_eidx[c] as Array).append(k)
				else:
					_eidx[c] = [k]
	var seen := {}
	for c in _cells_of(r):
		for k in _eidx.get(c, []):
			seen[k] = true
	return seen.keys()


## 새 땅(처음 기지 밖)의 땅 모양: 물 위, 또는 너무 가파른 곳 (그보다 덜 가파르면 기초를 쌓아 앉힌다)
func _ground_reason(r: Rect2) -> String:
	if ground == null or _rect_in_base(r):
		return ""
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center()]
	var lo := INF
	var hi := -INF
	for q in pts:
		if ground.water_at(q):
			return "물 위다 — '땅'(쌓기)으로 메운 뒤 짓는다"
		var h := ground.local_height_m(q)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var slope := (hi - lo) / maxf(maxf(r.size.x, r.size.y), 1.0)
	if slope > float(LayoutData.land()["build_slope_max"]):
		return "땅이 너무 가파르다 (%d%%) — '땅'(평탄화)으로 고른 뒤 짓는다" % int(slope * 100.0)
	return ""


func _rect_in_base(r: Rect2) -> bool:
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if not layout.base_has(q, 0.0, 0.0):
			return false
	return true


## 자재·연구·일조 칸까지 따진 결과: {reason, tile}
func check(kind: String, at: Vector2, rot: int, sim: CitySim) -> Dictionary:
	var tile := zone_of(at) if fam(kind) == "solar_tower" else ""
	if sim != null:
		var m: Dictionary = sim.M[kind]
		if m["tech"] != null and not sim.techs.has(m["tech"]):
			return {"reason": "연구 필요: " + String(sim.T[m["tech"]]["name"]), "tile": tile}
		if not sim.can_afford(m["cost"], 0.0):
			return {"reason": "자재 부족", "tile": tile}
		if tile != "" and int(sim.tiles.get(tile, 0)) >= int(sim.C["illumination"]["tiles"][tile]):
			return {"reason": "%s 구역이 다 찼다 (%d기)" % [layout.tile_name(tile), int(sim.C["illumination"]["tiles"][tile])],
				"tile": tile}
	return {"reason": check_spot(kind, at, rot), "tile": tile}


func _touches_zone(r: Rect2) -> bool:
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if zone_of(corner) != "":
			return true
	return false


static func _rect_dist(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)


static func _rect_point_dist(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


static func _seg_point(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var d := b - a
	var l2 := d.length_squared()
	if l2 < 1e-9:
		return a
	return a + d * clampf((p - a).dot(d) / l2, 0.0, 1.0)


## 선분과 축 정렬 사각형 사이의 거리 (만나면 0)
static func _seg_rect_dist(a: Vector2, b: Vector2, r: Rect2) -> float:
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return 0.0
	var best := minf(_rect_point_dist(r, a), _rect_point_dist(r, b))
	for q in c:
		best = minf(best, (q as Vector2).distance_to(_seg_point(a, b, q)))
	return best


# ── 길 ──────────────────────────────────────────────────────────
## 길 하나를 놓을 수 있나: "" 또는 까닭.
## 높은 길(고가·다리)은 물·잠긴 땅 위로도 지나고 땅 위의 길과 엇갈려 지나지만, 높은 길끼리는 겹치지 못하고,
## 엇갈리는 곳에서 덱이 CLEAR_M 넘게 떠 있어야 한다 (끝에서 오르는 비탈이 짧으면 막는다). 땅 위의 길은 물을 건너지 못한다
const CLEAR_M := 4.5
func road_check(a: Vector2, b: Vector2, type: String = "street", cross := true) -> String:
	if a.distance_to(b) < 3.0:
		return "길이 너무 짧다"
	for p in [a, b, a.lerp(b, 0.5)]:
		if not in_land(p, 1.0, -2.0):
			return "기지 밖이다 — '확장'으로 땅 구역을 산다"
	var hw := LayoutData.road_half(type)
	_bindex()
	var near := {}
	for c in _cells_of(Rect2(a, Vector2.ZERO).expand(b).grow(hw)):        # 길에서 반폭 안에 닿을 수 있는 건물만 (배열 순서로 — 다 훑을 때와 같은 답)
		for i in _bidx.get(c, []):
			near[i] = true
	var idx := PackedInt32Array(near.keys())
	idx.sort()
	for i in idx:
		if _seg_rect_dist(a, b, (_brect[i] as Rect2).grow(-0.3)) < hw:
			return "건물(%s)을 지나간다" % GameData.module_name(String(buildings[i]["id"]))
	for mr in mega_rects():
		if _seg_rect_dist(a, b, (mr as Rect2).grow(-1.0)) < hw:
			return "메가프로젝트 자리를 지나간다"
	var up := LayoutData.raised(type)
	if up:
		if ground != null and (ground.water_at(a) or ground.water_at(b)):
			return "다리의 두 끝은 뭍에 둔다"
	else:
		if flooded_along(a, b, hw):
			return "물에 잠긴 땅을 지나간다 — 먼저 메운다"
		if _water_along(a, b):
			return "물을 건넌다 — '다리' 종류로 건넌다"
	return _cross_check(PackedVector2Array([a, b]), type) if cross else ""


## 여러 토막(곡선)의 길 전체로 엇갈림을 따진다 — 덱은 길 전체의 두 끝에서 오른다
func cross_check_path(pts: PackedVector2Array, type: String) -> String:
	return _cross_check(pts, type)


## 물 (자연의 바다·호수)이 이 선분 위에 있나 — 4 m마다 (땅을 모르면 없다고 본다)
func _water_along(a: Vector2, b: Vector2) -> bool:
	if ground == null:
		return false
	var n := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
	for i in range(1, n):
		if ground.water_at(a.lerp(b, float(i) / n)):
			return true
	return false


## 높이가 다른 길과 엇갈리는 곳: 높은 길끼리는 막고, 높은 길이 땅 위의 길 위로 지나는 곳은 덱이 CLEAR_M 넘게 떠야 한다.
## 새 높은 길의 덱은 두 끝에서 오른다고 본다 (이미 있는 높은 길의 끝에 이어 붙이면 그쪽은 이미 높다)
func _cross_check(pts: PackedVector2Array, type: String) -> String:
	if pts.size() < 2:
		return ""
	var up := LayoutData.raised(type)
	var rd := LayoutData.road(type)
	var a := pts[0]
	var b := pts[-1]
	var length := 0.0
	for i in range(1, pts.size()):
		length += pts[i].distance_to(pts[i - 1])
	var lvn := _node_levels()
	var high_a := false
	var high_b := false
	if up:
		for i in nodes.size():
			if i < lvn.size() and lvn[i] == 1 and _raised_end(i):
				if (nodes[i] as Vector2).distance_to(a) < SNAP_M:
					high_a = true
				if (nodes[i] as Vector2).distance_to(b) < SNAP_M:
					high_b = true
	var s0 := 0.0
	for i in range(1, pts.size()):
		var q0 := pts[i - 1]
		var q1 := pts[i]
		for k in edges.size():
			var ek: Vector2i = edges[k]
			var p0: Vector2 = nodes[ek.x]
			var p1: Vector2 = nodes[ek.y]
			var other_up := LayoutData.raised(edge_type(k))
			if other_up == up and not up:
				continue                # 땅 위의 길끼리는 교차로가 된다
			var hit: Variant = Geometry2D.segment_intersects_segment(q0, q1, p0, p1)
			if hit == null:
				continue
			var hp: Vector2 = hit
			if hp.distance_to(a) < 1.0 or hp.distance_to(b) < 1.0:
				continue                # 끝에서 만난다 (이어진다)
			if up and other_up:
				return "다른 높은 길(%s)과 겹친다" % LayoutData.road_name(edge_type(k))
			var h := 0.0
			if up:
				var s := s0 + hp.distance_to(q0)
				var deck := float(rd.get("deck_m", 6.0))
				var g := float(rd.get("grade", 0.06))
				var from_a := deck if high_a else g * s
				var from_b := deck if high_b else g * (length - s)
				h = minf(deck, minf(from_a, from_b))
			else:
				h = lift(k, clampf(hp.distance_to(p0) / maxf(p0.distance_to(p1), 0.01), 0.0, 1.0))
			if h < CLEAR_M:
				return "고가 밑을 지나기엔 낮다 (%.1f m) — 오르는 비탈 밖에서 엇갈린다" % h
		s0 += q0.distance_to(q1)
	return ""


## 이 꼭짓점이 높은 길의 끝인가 (높은 길이 하나 닿는다)
func _raised_end(i: int) -> bool:
	var n := 0
	for k in edges.size():
		if (edges[k].x == i or edges[k].y == i) and LayoutData.raised(edge_type(k)):
			n += 1
	return n == 1


# ── 활주로 (지구·화성) ──────────────────────────────────────────
## 활주로: {a, b, w, rect, taxi: [a, b]} — 기지 밖, 길 격자의 땅 구역 한 줄(rect)에 격자 축을 따라 놓는다 (블록과 나란하다).
## 처음 정할 때 우주항에 가까운 쪽부터 가진 땅과 겹치지 않는 줄을 고른다. 유도로는 우주항 땅의 가운데 격자선을 따라 활주로까지
## 곧게 가는 대로 (길 그물의 길이다). 활주로 줄의 땅 구역은 살 수 없다
func runway() -> Dictionary:
	if not RUNWAY.has(body) or layout.pad_area.size == Vector2.ZERO:
		return {}
	if runway_at.size() != 2:
		runway_at = _pick_runway()
	var key := "%s|%s|%d" % [body, runway_at[0], int(runway_at[1])]
	if key != _runway_key:
		_runway_key = key
		_runway = _runway_on(String(runway_at[0]), int(runway_at[1]))
	return _runway


## 그 쪽의 활주로 줄 [쪽, 줄 번호]: 처음 기지의 끝에서 40 m 넘게 떨어진 첫 줄부터, 가진 땅과 겹치면 바깥으로
func _pick_runway() -> Array:
	var pc := layout.pad_area.get_center() - Vector2(layout.hub.x, layout.hub.y)
	var sides := ["+x", "+y", "-x", "-y"]
	sides.sort_custom(func(a: String, b: String) -> bool: return _side_dot(a, pc) > _side_dot(b, pc))
	for side in sides:
		var col := _runway_col0(side)
		var step := 1 if side.begins_with("+") else -1
		for k in 4:
			if _strip_free(side, col + k * step):
				return [side, col + k * step]
	return [sides[0], _runway_col0(sides[0])]


static func _side_dot(side: String, v: Vector2) -> float:
	var d := {"+x": Vector2(1, 0), "-x": Vector2(-1, 0), "+y": Vector2(0, 1), "-y": Vector2(0, -1)}[side] as Vector2
	return d.dot(v)


## 처음 기지(지도 끝)에서 그 쪽으로 40 m 넘게 떨어진 첫 땅 구역 줄
func _runway_col0(side: String) -> int:
	var b := BaseLayout.BOUNDS_UV
	var ext := -INF if side.begins_with("+") else INF
	var on_x := side.ends_with("x")
	for uv in [b.position, b.end, Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y)]:
		var q := BaseLayout.uv_to_xy(uv)
		var v := q.x if on_x else q.y
		ext = maxf(ext, v) if side.begins_with("+") else minf(ext, v)
	var o := layout.grid_o.x if on_x else layout.grid_o.y
	var s := parcel_size()
	if side.begins_with("+"):
		return ceili((ext + 40.0 - o) / s)
	return floori((ext - 40.0 - o) / s) - 1


## 그 줄의 땅 구역들 (활주로 길이만큼, 우주항 가운데를 가운데로)
func _strip_cells(side: String, col: int) -> Array:
	var s := parcel_size()
	var on_x := side.ends_with("x")
	var pc := layout.pad_area.get_center() - layout.grid_o
	var n := ceili(float(RUNWAY[body][0]) / s)
	var j0 := roundi((pc.y if on_x else pc.x) / s - n * 0.5)
	var out: Array = []
	for j in range(j0, j0 + n):
		out.append(Vector2i(col, j) if on_x else Vector2i(j, col))
	return out


func _strip_free(side: String, col: int) -> bool:
	for c in _strip_cells(side, col):
		if parcel_owned(c):
			return false
	return true


func _runway_on(side: String, col: int) -> Dictionary:
	var spec: Array = RUNWAY[body]
	var cells := _strip_cells(side, col)
	var rect := parcel_rect(cells[0]).merge(parcel_rect(cells[-1]))
	var on_x := side.ends_with("x")
	var c := rect.get_center()
	var half := float(spec[0]) * 0.5
	var a := c - (Vector2(0, half) if on_x else Vector2(half, 0))
	var b := c + (Vector2(0, half) if on_x else Vector2(half, 0))
	# 유도로: 우주항 땅의 그쪽 변에서 (그 변의 가운데에 가장 가까운 격자선을 따라) 활주로 가운데선까지
	var pa := layout.pad_area
	var pitch := layout.pitch
	var t0: Vector2
	var t1: Vector2
	if on_x:
		var y := layout.grid_o.y + roundf((pa.get_center().y - layout.grid_o.y) / pitch) * pitch
		t0 = Vector2(pa.end.x if side == "+x" else pa.position.x, y)
		t1 = Vector2(c.x, y)
	else:
		var x := layout.grid_o.x + roundf((pa.get_center().x - layout.grid_o.x) / pitch) * pitch
		t0 = Vector2(x, pa.end.y if side == "+y" else pa.position.y)
		t1 = Vector2(x, c.y)
	return {"a": a, "b": b, "w": float(spec[1]), "rect": rect, "taxi": [t0, t1]}


## 유도로가 길 그물에 없으면 깐다 (새 게임, 활주로가 없던 옛 저장)
func _ensure_taxiway() -> void:
	var rw := runway()
	if rw.is_empty():
		return
	var t: Array = rw["taxi"]
	var mid: Vector2 = ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5
	if nearest_edge(mid, 2.0) >= 0:
		return
	add_road(t[0], t[1], 0.6, "avenue")


# ── 땅 구역 (기지 넓히기) ───────────────────────────────────────
## 구역 한 변 (m) — 길 격자의 블록 cells개 (대로로 둘러싸인 블록 2×2)
func parcel_size() -> float:
	return layout.pitch * int(LayoutData.land()["cells"])


## 점이 든 구역 번호 (원점 = 거주 구역 가운데의 교차로)
func parcel_of(p: Vector2) -> Vector2i:
	var q := (p - layout.grid_o) / parcel_size()
	return Vector2i(int(floor(q.x)), int(floor(q.y)))


func parcel_rect(c: Vector2i) -> Rect2:
	var s := parcel_size()
	return Rect2(layout.grid_o + Vector2(c) * s, Vector2(s, s))


## 지을 수 있는 땅인가: 처음 기지(지도 끝에서 margin 안, 능선 마루에서 crest_off 아래) 또는 사들인 구역
func in_land(p: Vector2, margin: float = 0.0, crest_off: float = 0.0) -> bool:
	if layout.base_has(p, margin, crest_off):
		return true
	if land.is_empty() or not land.has(parcel_of(p)):
		return false
	return layout.kind != "ridge" or BaseLayout.xy_to_uv(p).y >= layout.crest_v + crest_off


## 구역이 처음 기지와 얼마나 겹치나: 0 (안 겹친다) · 1 (조금) · 2 (다 기지 안)
func _parcel_base(c: Vector2i) -> int:
	var r := parcel_rect(c)
	var n := 0
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center()]
	for q in pts:
		if layout.base_has(q, 0.0, 0.0):
			n += 1
	return 2 if n == pts.size() else (1 if n > 0 else 0)


## 가진 땅인가 (사들였거나 처음 기지와 겹친다) — 이웃 구역을 살 수 있게 하는 땅
func parcel_owned(c: Vector2i) -> bool:
	return land.has(c) or _parcel_base(c) > 0


## 이 구역을 하나 더 사는 값 (부품·지원) — 길 값은 따로
func parcel_price() -> Dictionary:
	var ld := LayoutData.land()
	var k := pow(float(ld["grow"]), land.size())
	var out := {}
	for key in ld["price"]:
		out[key] = snappedf(float(ld["price"][key]) * k, 0.1)
	return out


## 살 수 있는 구역 후보 (가진 땅에 붙은 구역): [{cell, rect, ok, reason, cost, slope, wet, roads, road_m}] — 가까운 것부터.
## 땅·길·건물이 바뀔 때만 다시 셈한다
func land_candidates() -> Array:
	var sig := "%d|%d|%d|%d|%s" % [land_rev, road_rev, terrain_rev, buildings.size(), str(ground != null and ground.baked_heights())]
	if sig == _cands_sig:
		return _cands
	_cands_sig = sig
	_near_edges(Rect2())              # 길 색인을 지금 것으로 (구역마다 깔릴 길의 끝이 가까운 길에 닿는지 볼 때 쓴다)
	var owned := {}
	var s := parcel_size()
	# 처음 기지를 덮는 구역들
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var b := BaseLayout.BOUNDS_UV
	for uv in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
		var xy := BaseLayout.uv_to_xy(uv)
		lo = lo.min(xy)
		hi = hi.max(xy)
	var c0 := parcel_of(lo)
	var c1 := parcel_of(hi)
	for i in range(c0.x, c1.x + 1):
		for j in range(c0.y, c1.y + 1):
			var c := Vector2i(i, j)
			if _parcel_base(c) > 0:
				owned[c] = true
	for c in land:
		owned[c] = true
	var seen := {}
	var out: Array = []
	for c in owned:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or land.has(n) or _parcel_base(n) == 2:
				continue
			seen[n] = true
			out.append(parcel_status(n))
	var hubp := hub()
	out.sort_custom(func(x, y): return (x["rect"] as Rect2).get_center().distance_to(hubp) < (y["rect"] as Rect2).get_center().distance_to(hubp))
	_cands = out
	return out


## 구역 하나를 살 수 있나: {cell, rect, ok, reason, cost, slope, wet, roads: [[a, b, 종류]], road_m}
func parcel_status(c: Vector2i) -> Dictionary:
	var ld := LayoutData.land()
	var r := parcel_rect(c)
	var st := {"cell": c, "rect": r, "ok": false, "reason": "", "cost": {}, "slope": 0.0, "wet": 0.0, "roads": [], "road_m": 0.0}
	if land.has(c) or _parcel_base(c) == 2:
		st["reason"] = "이미 가진 땅이다"
		return st
	var near := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if parcel_owned(c + d):
			near = true
			break
	if not near and _parcel_base(c) == 0:
		st["reason"] = "가진 땅에 붙은 구역만 산다"
		return st
	var dist := r.get_center().distance_to(hub())
	if dist > float(ld["max_r_m"]):
		st["reason"] = "기지에서 너무 멀다 (구역 가운데 %d m까지)" % int(ld["max_r_m"])
		return st
	if layout.kind == "ridge":
		for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if BaseLayout.xy_to_uv(q).y < layout.crest_v:
				st["reason"] = "능선 너머다 — 크레이터 안쪽 비탈은 지을 수 없다"
				return st
	var rw := runway()
	if not rw.is_empty() and r.grow(-1.0).intersects(rw["rect"]):
		st["reason"] = "활주로 자리다"
		return st
	# 땅 모양: 5×5 점의 자연 높이 (기울기), 물
	if ground != null:
		var hs: Array = []
		var wet := 0
		for j in 5:
			var row: Array = []
			for i in 5:
				var q := r.position + r.size * Vector2(i / 4.0, j / 4.0)
				row.append(ground.base_height_m(q))
				if ground.water_at(q):
					wet += 1
			hs.append(row)
		var step := s_div(r.size.x, 4.0)
		var slope := 0.0
		for j in 5:
			for i in 5:
				if i < 4:
					slope = maxf(slope, absf(float(hs[j][i + 1]) - float(hs[j][i])) / step)
				if j < 4:
					slope = maxf(slope, absf(float(hs[j + 1][i]) - float(hs[j][i])) / step)
		st["slope"] = slope
		st["wet"] = wet / 25.0
		if st["wet"] > float(ld["wet_max"]):
			st["reason"] = "구역의 %d%%가 물이다 — 살 수 없다" % int(float(st["wet"]) * 100.0)
			return st
		if slope > float(ld["slope_max"]):
			st["reason"] = "너무 가파르다 (비탈 %d%%, %d%%까지)" % [int(slope * 100.0), int(float(ld["slope_max"]) * 100.0)]
			return st
	# 깔릴 길: 구역의 블록마다 네 변 (이미 난 길·기지의 블록은 건너뛴다)
	var roads: Array = []
	var road_m := 0.0
	var cells := int(ld["cells"])
	var keyset := {}
	for di in cells:
		for dj in cells:
			var cell := c * cells + Vector2i(di, dj)
			if layout.open_cells.has(cell):
				continue
			var cr := layout.cell_rect(cell)
			var corners := [cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]
			var lines := [cell.y, cell.x + 1, cell.y + 1, cell.x]        # 위·오른쪽·아래·왼쪽 변이 놓인 격자선 번호
			for k in 4:
				var a: Vector2 = corners[k]
				var e: Vector2 = corners[(k + 1) % 4]
				var key := "%d,%d,%d,%d" % [int(round(minf(a.x, e.x))), int(round(minf(a.y, e.y))), int(round(maxf(a.x, e.x))),
					int(round(maxf(a.y, e.y)))]
				if keyset.has(key) or _has_road_between(a, e):
					continue
				keyset[key] = true
				var mid := a.lerp(e, 0.5)
				if layout.special_at(mid, 4.0) or road_check_shape(a, e, layout.line_type(int(lines[k]))) != "":
					continue
				roads.append([a, e, layout.line_type(int(lines[k]))])
				road_m += a.distance_to(e)
	# 길 그물과 이어지나: 깔 길의 끝이 기존 길에 닿거나 구역 변에 이미 길이 있으면 이어진다. 아니면 가장 가까운 길까지 연결로
	var touches := false
	var corners4 := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		if _has_road_between(corners4[k], corners4[(k + 1) % 4]) or _node_near(corners4[k]) >= 0:
			touches = true
	for seg in roads:
		for q in [seg[0], seg[1]]:
			if _node_near(q) >= 0 or nearest_edge(q, 0.6) >= 0:
				touches = true
	if not touches and not nodes.is_empty():
		var best_d := INF
		var link: Array = []
		for q in corners4:
			for i in nodes.size():
				var nd: Vector2 = nodes[i]
				var d := (q as Vector2).distance_to(nd)
				if d < best_d and d > 1.0 and road_check_shape(q, nd, "street") == "" and not layout.special_at(q.lerp(nd, 0.5), 4.0):
					best_d = d
					link = [q, nd, "street"]
		if link.is_empty() or best_d > parcel_size() * 1.5:
			st["reason"] = "길로 이을 수 없다 — 가까운 길이 없다"
			return st
		roads.append(link)
		road_m += best_d
	st["roads"] = roads
	st["road_m"] = road_m
	var cost := parcel_price()
	for seg in roads:
		var rc := LayoutData.road_cost(String(seg[2]), (seg[0] as Vector2).distance_to(seg[1]))
		for k2 in rc:
			cost[k2] = snappedf(float(cost.get(k2, 0.0)) + float(rc[k2]), 0.1)
	st["cost"] = cost
	st["ok"] = true
	return st


static func s_div(a: float, b: float) -> float:
	return a / b if b != 0.0 else 0.0


## 두 점 사이에 이미 길이 있나 (꼭짓점이 0.6 m 안에서 맞고 그 둘을 잇는 길)
func _has_road_between(a: Vector2, b: Vector2) -> bool:
	var ia := -1
	var ib := -1
	for i in nodes.size():
		var p: Vector2 = nodes[i]
		if ia < 0 and p.distance_to(a) < 0.6:
			ia = i
		elif ib < 0 and p.distance_to(b) < 0.6:
			ib = i
	if ia < 0 or ib < 0:
		return false
	return _edge_index(ia, ib) >= 0


## 이 점에 붙은 길 꼭짓점 (0.6 m 안, 없으면 -1)
func _node_near(p: Vector2) -> int:
	for i in nodes.size():
		if (nodes[i] as Vector2).distance_to(p) < 0.6:
			return i
	return -1


## 땅 구역에 깔 길이 건물·물에 막히나 (기지 경계는 따지지 않는다)
func road_check_shape(a: Vector2, b: Vector2, type: String) -> String:
	var hw := LayoutData.road_half(type)
	_bindex()
	for c in _cells_of(Rect2(a, Vector2.ZERO).expand(b).grow(hw)):        # 길에서 반폭 안에 닿을 수 있는 건물만
		for i in _bidx.get(c, []):
			if _seg_rect_dist(a, b, (_brect[i] as Rect2).grow(-0.3)) < hw:
				return "건물"
	if flooded_along(a, b, hw):
		return "물"
	return ""


## 구역을 산다: 고른 식민지가 값을 내고, 구역의 블록 둘레에 길(격자 그대로 — 대로·도로)이 깔린다. 산 구역의 블록은 빈 블록
func buy_parcel(c: Vector2i, sim: CitySim) -> bool:
	var st := parcel_status(c)
	if not bool(st["ok"]) or not can_pay(st["cost"], sim):
		return false
	pay(st["cost"], sim)
	land[c] = true
	land_rev += 1
	for seg in st["roads"]:
		add_road(seg[0], seg[1], 0.6, String(seg[2]))
	_cands_sig = ""
	_touch()
	return true


## 값을 낼 수 있나 (부품·금속은 비축, 지원은 지구 지원 점수). reserve: 남겨 둘 몫
static func can_pay(cost: Dictionary, sim: CitySim, reserve: Dictionary = {}) -> bool:
	if sim == null:
		return true
	for k in cost:
		var have := sim.support if k == "support" else float(sim.stock.get(k, 0.0))
		if have - float(cost[k]) < float(reserve.get(k, 0.0)) - 1e-6:
			return false
	return true


static func pay(cost: Dictionary, sim: CitySim) -> void:
	if sim == null:
		return
	for k in cost:
		if k == "support":
			sim.support -= float(cost[k])
		else:
			sim.stock[k] = float(sim.stock.get(k, 0.0)) - float(cost[k])


static func cost_text(cost: Dictionary) -> String:
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
			"support":
				parts.append("지원 %s" % Fmt.n(v, 0))
			_:
				parts.append("%s %s" % [k, Fmt.n(v, 1)])
	return " · ".join(parts) if not parts.is_empty() else "무료"


## 가진 땅의 가장 먼 곳까지 (m, 기지 가운데에서) — 땅 고치기가 닿는 반지름
func land_radius() -> float:
	var r := 0.0
	for c in land:
		var rect := parcel_rect(c)
		for q in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			r = maxf(r, (q as Vector2).distance_to(hub()))
	return r


## 땅 고치기가 닿는 반지름 (m): 자료의 반지름, 또는 사들인 땅의 끝 + 40 m
func edit_radius() -> float:
	return maxf(float(LayoutData.terrain()["edit_radius_m"]), land_radius() + 40.0)


## 자동 운영: 기본 자리와 그 구획 블록이 다 찼으면 그 구획 가까이의 구역을 사서 블록을 그 구획으로 정한다 (남길 몫은 남긴다)
func _auto_expand(kind: String, sim: CitySim) -> bool:
	var district: String = layout.district_of.get(fam(kind), "")
	if district == "" or district in BaseLayout.SPECIAL:
		return false
	if zone_free_block(district):
		if sim != null:
			sim.note("자동 운영 — 빈 블록을 %s 구획으로 정했다" % LayoutData.zone_name(district), "info")
			_rec("land", "빈 블록을 %s 구획으로 정했다: %s을(를) 놓을 자리가 없다" % [LayoutData.zone_name(district), GameData.module_name(kind)])
		return true
	return expand_zone(district, sim, LayoutData.land()["auto_reserve"], "자동 운영")


## 구획 넓히기 (땅을 사기 전에): 가진 땅 안의 빈 블록(구획이 없는 블록) 가운데 그 구획 블록들에 가장 가까운 것을
## 그 구획으로 정한다. 너무 작은 자투리 블록(600 m² 아래)은 두고. 정했으면 true
func zone_free_block(district: String) -> bool:
	var anchor := _zone_anchor(district)
	var best := {}
	var best_d := INF
	for b in blocks():
		if String(b["district"]) != "" or float(b["area"]) < 600.0:
			continue
		var c: Vector2 = b["center"]
		if not in_land(c) or layout.special_at(c, 4.0):
			continue
		var d := c.distance_to(anchor)
		if d < best_d:
			best_d = d
			best = b
	return not best.is_empty() and set_district(best["center"], district)


# ── 재난의 흔적 ────────────────────────────────────────────────
## 운석 구덩이: 반지름 r 안은 깊이 depth까지 오목하게, r~1.35r은 둘레 둔덕 (건물·길 밑 칸은 그대로). 고친 칸 수
func crater(center: Vector2, r: float, depth: float) -> int:
	var c := cell_m()
	var keep := _fixed_cells()
	var lo := -float(LayoutData.terrain()["max_depth_m"])
	var n := 0
	var reach := int(ceil(r * 1.35 / c)) + 1
	var ci := Vector2i(int(round(center.x / c)), int(round(center.y / c)))
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var key := Vector2i(ci.x + di, ci.y + dj)
			if keep.has(key):
				continue
			var d := (Vector2(key) * c).distance_to(center) / maxf(r, 0.1)
			var dh := 0.0
			if d < 1.0:
				dh = -depth * (1.0 - d * d)
			elif d < 1.35:
				dh = depth * 0.22 * (1.0 - absf(d - 1.15) / 0.2)
			if absf(dh) < 0.02:
				continue
			terrain[key] = snappedf(clampf(float(terrain.get(key, 0.0)) + dh, lo, 30.0), 0.01)
			n += 1
	if n > 0:
		terrain_rev += 1
		_touch()
	return n


static var _home_north := Vector2.ZERO


## 배치 좌표에서 그 부지의 북쪽 (단위 벡터): 3D 땅의 모형 축대로 — 다른 부지(SiteSurface)는 (−1, −1) 쪽,
## 시작 부지 섀클턴(MoonSurface)은 능선 쪽이 크레이터 가운데를 보도록 돌아가 있다 (남극 가까이라 북쪽은 극에서 멀어지는 쪽)
static func north_dir(id: String) -> Vector2:
	if id != GameData.HOME_SITE:
		return Vector2(-1, -1).normalized()
	if _home_north == Vector2.ZERO:
		var b := MoonSurface.home_frame()
		var nb := Vector3(0, 0, 1) - b.z * b.z.z
		var v := Vector2(nb.dot(b.x), nb.dot(b.y))
		_home_north = v.normalized() if v.length_squared() > 1e-12 else Vector2(-1, -1).normalized()
	return _home_north


## 배치 좌표의 방향 → 여덟 방위 이름 (north: 배치 좌표의 북쪽 — 동쪽은 그 시계 방향 90°)
static func direction_name(rel: Vector2, north: Vector2) -> String:
	var n := rel.dot(north)
	var e := rel.dot(Vector2(north.y, -north.x))
	return ["동", "북동", "북", "북서", "서", "남서", "남", "남동"][posmod(int(round(atan2(n, e) / (PI / 4.0))), 8)]


## 기지 가운데에서 본 자리: "북동쪽 320 m" (가까우면 "기지 가운데")
func where_text(p: Vector2) -> String:
	var rel := p - hub()
	if rel.length() < 40.0:
		return "기지 가운데"
	var dir := direction_name(rel, north_dir(site_id))
	if rel.length() >= 1000.0:
		return "%s쪽 %.1f km" % [dir, rel.length() / 1000.0]
	return "%s쪽 %d m" % [dir, int(round(rel.length() / 10.0)) * 10]


## 플레이어가 헌 건물: 배치에서 뺀다 (시뮬레이션의 수는 부른 쪽이 줄인다 — 맞추기가 다른 건물을 빼지 않게)
func remove_entry(uid: int) -> bool:
	for i in buildings.size():
		if int(buildings[i]["uid"]) == uid:
			buildings.remove_at(i)
			_bidx_n = -1
			_bgen += 1
			_touch()
			return true
	return false


## 플레이어가 옮긴 건물: 새 자리·방향으로, 새 번호를 받아 맨 뒤에 (3D의 앉는 자리를 새로 잰다 — 고장 표지가 그 건물에 붙는다).
## 새 번호
func relocate(uid: int, at: Vector2, rot: int, tile: String) -> int:
	for i in buildings.size():
		if int(buildings[i]["uid"]) == uid:
			var e: Dictionary = buildings[i]
			buildings.remove_at(i)
			e["x"] = at.x
			e["y"] = at.y
			e["rot"] = rot
			e["tile"] = tile
			e["uid"] = _next_uid
			_next_uid += 1
			buildings.append(e)
			_bidx_n = -1
			_bgen += 1
			_touch()
			return int(e["uid"])
	return -1


## 스스로 한 일을 운영 기록으로 (on_auto가 있으면)
func _rec(domain: String, text: String) -> void:
	if on_auto.is_valid():
		on_auto.call(domain, text)


## 지어진 건물 uid를 그 종류의 맨 뒤로 (재난에 부서진 건물이 고장 표시를 받는다 — 고장은 그 종류의 뒤쪽 건물에 붙는다)
func move_to_end(uid: int) -> void:
	for i in buildings.size():
		if int(buildings[i]["uid"]) == uid:
			var e: Dictionary = buildings[i]
			buildings.remove_at(i)
			buildings.append(e)
			_bidx_n = -1
			_bgen += 1
			_touch()
			return


# ── 메가프로젝트 자리 ──────────────────────────────────────────
const MEGA_INSET := 6.0            # 메가프로젝트는 땅 구역의 둘레 길 안쪽에 선다


## 메가프로젝트 자리 (짓는 것과 다 지은 것): 땅 구역에서 둘레 길을 뺀 사각형
func mega_rects() -> Array:
	var out := []
	for w in mega + mega_done:
		out.append(parcel_rect(w["cell"]).grow(-MEGA_INSET))
	return out


## 메가프로젝트 자리: 구역 안쪽의 길(구역을 네 블록으로 나누는 길)을 걷어 낸다 — 둘레 길은 이웃 땅과 나눠 쓰므로 남긴다
func clear_parcel_roads(c: Vector2i) -> void:
	var r := parcel_rect(c).grow(-2.0)
	var gone: Array = []
	for k in edges.size():
		if r.has_point(((nodes[edges[k].x] as Vector2) + (nodes[edges[k].y] as Vector2)) * 0.5):
			gone.append(k)
	gone.reverse()
	for k in gone:
		edges.remove_at(k)
		etypes.remove_at(k)
	if not gone.is_empty():
		_tidy()
		_roads_changed()


# ── 재건축 ─────────────────────────────────────────────────────
## 지어진 건물 uid의 자리에 kind가 들어가나 (그 건물을 빼고 따진다 — 다른 건물·길·땅 밖에 걸리지 않게): 그 자리 그대로,
## 돌려서, 넓어진 만큼 네 쪽으로 밀어서 본다. 겹치는 이웃이 absorb의 종류(지어진 것)면 둘까지 함께 헐어 자리를 낸다.
## 들어가면 {at, rot, also: 함께 헐 uid들}, 아니면 {}
func rebuild_spot(uid: int, kind: String, absorb: Dictionary = {}) -> Dictionary:
	var old := {}
	for e in buildings:
		if int(e["uid"]) == uid and int(e["seq"]) < 0:
			old = e
			break
	if old.is_empty():
		return {}
	var at0 := Vector2(float(old["x"]), float(old["y"]))
	var of := foot_of(String(old["id"]), int(old["rot"]))
	for rot: int in [int(old["rot"]), (int(old["rot"]) + 1) % 4]:
		var d := ((foot_of(kind, rot) - of) * 0.5).max(Vector2.ZERO)
		var offs: Array = [Vector2.ZERO]
		for o: Vector2 in [Vector2(d.x, 0), Vector2(-d.x, 0), Vector2(0, d.y), Vector2(0, -d.y)]:
			if o != Vector2.ZERO:
				offs.append(o)
		for o: Vector2 in offs:
			var at := at0 + o
			var r := rect_of(kind, at, rot).grow(-0.05)
			var also := {}
			var ok := true
			for bi in _near_buildings(r):
				var e: Dictionary = buildings[bi]
				if int(e["uid"]) == uid or not r.intersects(_brect[bi]):
					continue
				if int(e["seq"]) < 0 and absorb.has(String(e["id"])) and also.size() < 2:
					also[int(e["uid"])] = true
				else:
					ok = false
					break
			if ok and check_spot(kind, at, rot, uid, also).is_empty():
				return {"at": at, "rot": rot, "also": also.keys()}
	return {}


## 재건축: 건물 uid(와 spot.also)를 헐고 그 자리(spot — rebuild_spot)에 kind를 짓는 공사(시뮬레이션 대기열의 seq)를 둔다.
## 공사 자리는 헌 건물들을 was = [[종류, 모양, 방향, x, y] …]로 기억한다 (공사 앞부분에 헐리는 모습을 보인다)
func rebuild(uid: int, kind: String, seq: int, spot: Dictionary) -> Dictionary:
	var gone := {uid: true}
	for u in spot.get("also", []):
		gone[int(u)] = true
	var was: Array = []
	for i in range(buildings.size() - 1, -1, -1):
		var old: Dictionary = buildings[i]
		if gone.has(int(old["uid"])):
			was.push_front([String(old["id"]), int(old["variant"]), int(old["rot"]), float(old["x"]), float(old["y"])])
			buildings.remove_at(i)
	_bidx_n = -1
	_bgen += 1
	var e := add_queued(kind, spot["at"], int(spot["rot"]), BaseScene.variant_of(kind, count_of(kind)), seq)
	if not was.is_empty():
		e["was"] = was
	return e


# ── 발전 모드의 땅 (넓히기·줄이기) ───────────────────────────────
## 구획마다 얼마나 찼나: {구획: [건물이 차지할 땅 m², 그 구획 블록의 땅 m²]}. 지은 건물과 대기열을 그 계열의 구획에 센다 —
## 자리를 아직 붙이지 않은 건물도 세므로 보지 않는 도시도 셈한다. 건물 하나는 바닥 + 둘레 3 m, 블록 땅은 70%만 쓴다고 본다
func zone_use(sim: CitySim) -> Dictionary:
	var out := {}
	for b in blocks():
		var d := String(b["district"])
		if d == "":
			continue
		if not out.has(d):
			out[d] = [0.0, 0.0]
		out[d][1] += float(b["area"]) * 0.7
	if sim == null:
		return out
	for mid in sim.counts:
		_use_add(out, String(mid), int(sim.counts[mid]))
	for item in sim.queue:
		if not String(item["id"]) in SPECIAL:
			_use_add(out, String(item["id"]), 1)
	return out


func _use_add(out: Dictionary, mid: String, n: int) -> void:
	var d: String = layout.district_of.get(fam(mid), "")
	if n <= 0 or d == "" or d in BaseLayout.SPECIAL or fam(mid) == "solar_tower":
		return
	var f := ArtLib.footprint(mid) + Vector2(BaseLayout.GAP, BaseLayout.GAP)
	if not out.has(d):
		out[d] = [0.0, 0.0]
	out[d][0] += n * f.x * f.y


## 그 구획을 넓힌다: 그 구획 블록들에 가장 가까운 살 수 있는 땅 구역을 사서 (reserve만큼은 남기고) 새 빈 블록을 그 구획으로 정한다.
## why: 기록의 말머리
func expand_zone(district: String, sim: CitySim, reserve: Dictionary, why: String) -> bool:
	var anchor := _zone_anchor(district)
	var best := {}
	var best_d := INF
	for st in land_candidates():
		if not bool(st["ok"]) or not can_pay(st["cost"], sim, reserve):
			continue
		var d := (st["rect"] as Rect2).get_center().distance_to(anchor)
		if d < best_d:
			best_d = d
			best = st
	if best.is_empty() or not buy_parcel(best["cell"], sim):
		return false
	var rect: Rect2 = best["rect"]
	var n := 0
	for b in blocks():
		if String(b["district"]) == "" and rect.has_point(b["center"]):
			district_seeds.append([b["center"], district])
			n += 1
	zone_rev += 1
	_touch()
	if sim != null:
		sim.note("%s — 땅 구역을 사서 %s 블록 %d개를 늘렸다 (%s)" % [why, LayoutData.zone_name(district), n,
			cost_text(best["cost"])], "info")
		_rec("land", "%s — 땅 구역을 사서 %s 블록 %d개를 늘렸다 (%s): 그 구획에 빈 블록이 없다" % [why, LayoutData.zone_name(district), n,
			cost_text(best["cost"])])
	return true


## 그 구획이 모이는 곳: 그 구획 블록들의 가운데 (블록이 없으면 기본 배치의 문)
func _zone_anchor(district: String) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for b in blocks():
		if String(b["district"]) == district:
			sum += b["center"]
			n += 1
	if n > 0:
		return sum / n
	var g: Vector3 = layout.gates.get(district, layout.hub)
	return Vector2(g.x, g.y)


## 산 땅 구역이 비었나 (처음 기지 밖 몫에 건물이 하나도 없다 — 길만 있다)
func parcel_empty(c: Vector2i) -> bool:
	var r := parcel_rect(c).grow(-0.5)
	_bindex()
	for cell in _cells_of(r):                 # 그 구역에 걸친 건물만 (건물 색인)
		for i in _bidx.get(cell, []):
			var er: Rect2 = _brect[i]
			if not er.intersects(r):
				continue
			for q in [er.position, Vector2(er.end.x, er.position.y), er.end, Vector2(er.position.x, er.end.y)]:
				if not layout.base_has(q):
					return false
	return true


## 돌려줄 수 있나: 산 구역이고 비었고, 빼도 남은 산 구역이 모두 처음 기지에 (변으로 붙은 구역을 따라) 이어진다
func can_release(c: Vector2i) -> bool:
	if not land.has(c) or not parcel_empty(c):
		return false
	for w in mega + mega_done:
		if w["cell"] == c:
			return false                # 메가프로젝트 자리
	var seen := {}
	var todo: Array = []
	for k in land:
		if k == c:
			continue
		if _parcel_base(k) > 0 or _touches_base(k):
			seen[k] = true
			todo.append(k)
	while not todo.is_empty():
		var k: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = k + d
			if nb != c and land.has(nb) and not seen.has(nb):
				seen[nb] = true
				todo.append(nb)
	return seen.size() == land.size() - 1


func _touches_base(k: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _parcel_base(k + d) > 0:
			return true
	return false


## 빈 땅 구역을 돌려준다: 그 구역 안의 길(이웃 땅에 닿지 않는 것)과 구획을 거두고, 다시 산다면 낼 값의 절반을 돌려받는다
func release_parcel(c: Vector2i, sim: CitySim, why: String) -> bool:
	if not can_release(c):
		return false
	var r := parcel_rect(c)
	land.erase(c)
	var gone: Array = []
	for k in edges.size():
		var a: Vector2 = nodes[edges[k].x]
		var b: Vector2 = nodes[edges[k].y]
		var m := (a + b) * 0.5
		if not r.grow(0.5).has_point(m):
			continue
		var side := (b - a).normalized().orthogonal() * (layout.pitch * 0.25)
		if in_land(m + side) or in_land(m - side):
			continue                # 이웃 땅의 길이기도 하다
		gone.append(k)
	gone.reverse()
	for k in gone:
		edges.remove_at(k)
		etypes.remove_at(k)
	if not gone.is_empty():
		_tidy()
		_roads_changed()
	district_seeds = district_seeds.filter(func(sd: Array) -> bool: return in_land(sd[0]))
	zone_rev += 1
	land_rev += 1
	_cands_sig = ""
	var back := parcel_price()
	for k in back:
		back[k] = snappedf(float(back[k]) * 0.5, 0.1)
	if sim != null:
		for k in back:
			if k == "support":
				sim.support += float(back[k])
			else:
				sim.stock[k] = float(sim.stock.get(k, 0.0)) + float(back[k])
		sim.note("%s — 빈 땅 구역을 돌려주었다 (%s 돌려받음)" % [why, cost_text(back)], "info")
		_rec("land", "%s — 빈 땅 구역을 돌려주었다 (%s 돌려받음): 도시가 비었고 그 구역은 오래 비어 있었다" % [why, cost_text(back)])
	_touch()
	return true


# ── 블록과 구획 ─────────────────────────────────────────────────
## 길이 둘러싼 블록: [{poly: 보도 안쪽 다각형, face: 길 가운데선의 면, center, area, district}]. 길·구획이 바뀔 때만 다시 셈한다
func blocks() -> Array:
	var sig := "%d|%d" % [road_rev, zone_rev]
	if sig == _blocks_sig:
		return _blocks
	_blocks_sig = sig
	_blocks = []
	var widest := 0.0
	for k in edges.size():
		widest = maxf(widest, edge_half(k))
	var flat: Array = []            # 블록은 땅 위의 길이 나눈다 (높은 길은 그 위로 지나갈 뿐)
	for k in edges.size():
		if not LayoutData.raised(edge_type(k)):
			flat.append(edges[k])
	var at := {}                    # 꼭짓점 자리 → 번호, 꼭짓점 둘 → 그 사이의 첫 길 (면의 변이 어느 길인지 바로 찾는다)
	for i in nodes.size():
		if not at.has(nodes[i]):
			at[nodes[i]] = i
	var pair := {}
	for k in edges.size():
		var e: Vector2i = edges[k]
		var key := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
		if not pair.has(key):
			pair[key] = k
	for face in RoadNet.faces(nodes, flat):
		var f: PackedVector2Array = face
		if RoadNet.area(f) > 120000.0:
			continue                # 기지를 다 감싸는 큰 면 (바깥 길로 둘러싸인 빈 땅) — 블록으로 보지 않는다
		var d := _face_inset(f, at, pair)
		for poly in RoadNet.inset(f, d):
			var c := RoadNet.centroid(poly)
			_blocks.append({"poly": poly, "face": f, "center": c, "area": RoadNet.area(poly), "district": _seed_in(poly)})
	return _blocks


## 면을 줄일 거리: 그 면을 이루는 길 가운데 가장 넓은 것의 반폭 + 보도.
## 변의 길은 꼭짓점 둘로 찾는다 (at·pair — 꼭짓점은 0.5 m 안에 둘이 없다). 못 찾으면 다 훑는다
func _face_inset(f: PackedVector2Array, at: Dictionary, pair: Dictionary) -> float:
	var d := ROAD_HALF
	for i in f.size():
		var a := f[i]
		var b := f[(i + 1) % f.size()]
		var k := -1
		if at.has(a) and at.has(b):
			var ia: int = at[a]
			var ib: int = at[b]
			k = int(pair.get(Vector2i(mini(ia, ib), maxi(ia, ib)), -1))
		if k < 0:
			for j in edges.size():
				var e: Vector2i = edges[j]
				var p: Vector2 = nodes[e.x]
				var q: Vector2 = nodes[e.y]
				if (p.distance_to(a) < 0.01 and q.distance_to(b) < 0.01) or (p.distance_to(b) < 0.01 and q.distance_to(a) < 0.01):
					k = j
					break
		if k >= 0:
			d = maxf(d, edge_half(k))
	return d + SIDEWALK


func _seed_in(poly: PackedVector2Array) -> String:
	var best := ""
	var best_d := INF
	var c := RoadNet.centroid(poly)
	for sd in district_seeds:
		var p: Vector2 = sd[0]
		if Geometry2D.is_point_in_polygon(p, poly):
			var dd := p.distance_to(c)
			if dd < best_d:
				best_d = dd
				best = String(sd[1])
	return best


## 이 점이 든 블록 (없으면 {})
func block_at(p: Vector2) -> Dictionary:
	for b in blocks():
		if Geometry2D.is_point_in_polygon(p, b["poly"]):
			return b
	return {}


func district_at(p: Vector2) -> String:
	var b := block_at(p)
	return String(b.get("district", "")) if not b.is_empty() else ""


## 블록의 용도를 정한다 ("" = 비운다). 그 블록 안의 옛 씨앗은 지운다
func set_district(p: Vector2, district: String) -> bool:
	var b := block_at(p)
	if b.is_empty():
		return false
	var poly: PackedVector2Array = b["poly"]
	for i in range(district_seeds.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(district_seeds[i][0], poly):
			district_seeds.remove_at(i)
	if district != "":
		district_seeds.append([b["center"], district])
	zone_rev += 1
	_touch()
	return true


## 구획 블록 안에서 이 종류를 놓을 빈자리: 블록 가장자리(길 쪽)부터 줄지어 찾는다
func _block_spot(kind: String, district: String) -> Dictionary:
	_seek_valid()
	var f := ArtLib.footprint(kind) + Vector2(BaseLayout.GAP, BaseLayout.GAP)
	for b in _district_blocks(district):
		var bc: Vector2 = b["center"]
		var key := "%s|%d,%d" % [kind, roundi(bc.x * 10.0), roundi(bc.y * 10.0)]
		var skip := int(_seek.get(key, 0))
		if skip < 0:
			continue                  # 이 종류로는 꽉 찬 블록
		var poly: PackedVector2Array = b["poly"]
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		var idx := 0
		var y := bb.position.y + f.y * 0.5
		while y <= bb.end.y - f.y * 0.5 + 0.01:
			var x := bb.position.x + f.x * 0.5
			while x <= bb.end.x - f.x * 0.5 + 0.01:
				if idx >= skip:
					var at := snap_center(kind, Vector2(x, y), 0)
					var rr := rect_of(kind, at, 0)
					if RoadNet.rect_inside(rr, poly) and not _overlaps(rr) and check_spot(kind, at, 0).is_empty():
						_seek[key] = idx
						return {"at": at, "rot": 0, "variant": BaseScene.variant_of(kind, count_of(kind)), "tile": ""}
				idx += 1
				x += f.x
			y += f.y
		_seek[key] = -1
	return {}


# ── 땅 고치기 ───────────────────────────────────────────────────
## 칸 크기 (m)
static func cell_m() -> float:
	return float(LayoutData.terrain()["cell_m"])


## 이 점의 높이 차 (m, 칸 사이는 이어지게)
func terrain_delta(p: Vector2) -> float:
	if terrain.is_empty():
		return 0.0
	var c := cell_m()
	var q := p / c
	var i0 := int(floor(q.x))
	var j0 := int(floor(q.y))
	var fx := q.x - i0
	var fy := q.y - j0
	var h00 := float(terrain.get(Vector2i(i0, j0), 0.0))
	var h10 := float(terrain.get(Vector2i(i0 + 1, j0), 0.0))
	var h01 := float(terrain.get(Vector2i(i0, j0 + 1), 0.0))
	var h11 := float(terrain.get(Vector2i(i0 + 1, j0 + 1), 0.0))
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


## 땅을 고친다: mode "dig"(파기)·"raise"(쌓기)·"flatten"(평탄화 — 붓 가운데 높이로)·"restore"(되돌리기).
## 파기·쌓기는 붓 가운데(반지름의 55%)를 한 걸음(step m) 더 깊게·높게 하고, 둘레는 비탈로 — 깊어질수록 비탈이
## 안식각(REPOSE)보다 가파르지 않게 넓어진다 (깊이 판 구덩이는 넓은 노천 구덩이가 된다).
## 비탈이 건물·길 밑에 닿으면 고치지 않는다 (terrain_block이 까닭을 말한다). 평탄화·되돌리기는 건물·길 밑 칸을 건너뛴다.
## base_h(p)는 고치기 전 땅 높이 (평탄화가 쓴다). 고친 칸 수를 돌려준다
func edit_terrain(center: Vector2, radius: float, mode: String, step: float, base_h: Callable = Callable()) -> int:
	var plan_e := _terrain_plan(center, radius, mode, step, base_h)
	if plan_e.is_empty():
		return 0
	var changes: Dictionary = plan_e["changes"]
	var keep := _fixed_cells()
	if mode in ["dig", "raise"]:
		for key in changes:
			if keep.has(key):
				return 0
	var n := 0
	for key in changes:
		if keep.has(key):
			continue
		var v := float(changes[key])
		if absf(v) < 0.01:
			terrain.erase(key)
		else:
			terrain[key] = snappedf(v, 0.01)
		n += 1
	if n > 0:
		terrain_rev += 1
		_touch()
	return n


## 파기·쌓기를 막는 까닭 ("" = 고칠 수 있다): 비탈이 건물·길 밑에 닿거나, 한도에 닿았다
func terrain_block(center: Vector2, radius: float, mode: String, step: float) -> String:
	if not mode in ["dig", "raise"]:
		return ""
	var plan_e := _terrain_plan(center, radius, mode, step)
	if plan_e.is_empty():
		return "더 팔 수 없다 (%d m까지)" % int(LayoutData.terrain()["max_depth_m"]) if mode == "dig" \
			else "더 쌓을 수 없다 (%d m까지)" % int(LayoutData.terrain()["max_raise_m"])
	var keep := _fixed_cells()
	for key in plan_e["changes"]:
		if keep.has(key):
			return "비탈(폭 %d m)이 건물·길에 닿는다 — 깊이 %d m까지 파려면 둘레를 비운다" % [
				int(float(plan_e["reach"]) - radius * 0.55), int(ceil(float(plan_e["depth"])))] if mode == "dig" \
				else "비탈(폭 %d m)이 건물·길에 닿는다" % int(float(plan_e["reach"]) - radius * 0.55)
	return ""


## 한 번 고칠 때 바뀌는 칸들: {changes: Vector2i → 새 높이 차, depth, reach}. 바뀌는 것이 없으면 {}
func _terrain_plan(center: Vector2, radius: float, mode: String, step: float, base_h: Callable = Callable()) -> Dictionary:
	var t := LayoutData.terrain()
	var c := cell_m()
	var lo := -float(t["max_depth_m"])
	var hi := float(t["max_raise_m"])
	var core := radius * 0.55
	var ci := Vector2i(int(round(center.x / c)), int(round(center.y / c)))
	var depth := 0.0
	var reach := radius
	var target := 0.0
	if mode in ["dig", "raise"]:
		# 붓 가운데의 지금 깊이·높이 → 한 걸음 더
		var r_core := int(ceil(core / c))
		var cur := 0.0
		for dj in range(-r_core, r_core + 1):
			for di in range(-r_core, r_core + 1):
				var key := Vector2i(ci.x + di, ci.y + dj)
				if (Vector2(key) * c).distance_to(center) <= core:
					var v0 := float(terrain.get(key, 0.0))
					cur = minf(cur, v0) if mode == "dig" else maxf(cur, v0)
		depth = clampf(absf(cur) + step, 0.0, -lo if mode == "dig" else hi)
		reach = core + maxf(radius - core, 1.5 * depth / REPOSE)
	elif mode == "flatten":
		target = terrain_delta(center) + (float(base_h.call(center)) if base_h.is_valid() else 0.0)
	var changes := {}
	var r_cells := int(ceil(reach / c)) + 1
	for dj in range(-r_cells, r_cells + 1):
		for di in range(-r_cells, r_cells + 1):
			var key := Vector2i(ci.x + di, ci.y + dj)
			var p := Vector2(key) * c
			var d := p.distance_to(center)
			if d > reach:
				continue
			var old := float(terrain.get(key, 0.0))
			var v := old
			match mode:
				"dig":
					v = minf(old, -depth * (1.0 - smoothstep(core, reach, d)))
				"raise":
					v = maxf(old, depth * (1.0 - smoothstep(core, reach, d)))
				"flatten":
					var bh := float(base_h.call(p)) if base_h.is_valid() else 0.0
					v = lerpf(old, target - bh, 1.0 - smoothstep(core, radius, d))
				"restore":
					v = lerpf(old, 0.0, 1.0 - smoothstep(core, radius, d))
			v = clampf(v, lo, hi)
			if absf(v - old) >= 0.005:
				changes[key] = v
	if changes.is_empty():
		return {}
	return {"changes": changes, "depth": depth, "reach": reach}


## 고치지 않는 칸: 건물 밑과 길 밑 (건물·길이 바뀔 때만 다시 셈한다 — 땅·물·구획만 바뀐 것은 revision에서 뺀다)
func _fixed_cells() -> Dictionary:
	var key := revision - terrain_rev - flood_rev - zone_rev + road_rev * 100003
	if _fixed_rev == key:
		return _fixed
	_fixed_rev = key
	var c := cell_m()
	var out := {}
	for e in buildings:
		var r := entry_rect(e).grow(1.0)
		for i in range(int(floor(r.position.x / c)), int(ceil(r.end.x / c)) + 1):
			for j in range(int(floor(r.position.y / c)), int(ceil(r.end.y / c)) + 1):
				out[Vector2i(i, j)] = true
	for k in edges.size():
		var a: Vector2 = nodes[edges[k].x]
		var b: Vector2 = nodes[edges[k].y]
		var hw := edge_half(k) + 1.0
		var bb := Rect2(a, Vector2.ZERO).expand(b).grow(hw)
		for i in range(int(floor(bb.position.x / c)), int(ceil(bb.end.x / c)) + 1):
			for j in range(int(floor(bb.position.y / c)), int(ceil(bb.end.y / c)) + 1):
				var p := Vector2(i, j) * c
				if _seg_point(a, b, p).distance_to(p) < hw:
					out[Vector2i(i, j)] = true
	_fixed = out
	return out


## 물에 잠긴 칸을 적는다 (땅이 해수면과 견주어 셈한 것). 바뀌면 true
func set_flood(cells: Dictionary) -> bool:
	if cells.size() == flood.size() and cells.keys().all(func(k): return flood.has(k)):
		flood = cells
		return false
	flood = cells
	flood_rev += 1
	_touch()
	return true


## 이 점(칸)이 물에 잠겼나
func flooded_at(p: Vector2) -> bool:
	if flood.is_empty():
		return false
	var c := cell_m()
	return flood.has(Vector2i(int(round(p.x / c)), int(round(p.y / c))))


## 사각형 안의 물에 잠긴 칸 수
func flooded_in(r: Rect2) -> int:
	if flood.is_empty():
		return 0
	var c := cell_m()
	var n := 0
	for i in range(int(floor(r.position.x / c)), int(ceil(r.end.x / c)) + 1):
		for j in range(int(floor(r.position.y / c)), int(ceil(r.end.y / c)) + 1):
			if flood.has(Vector2i(i, j)) and r.has_point(Vector2(i, j) * c):
				n += 1
	return n


## 선분(폭 hw)이 지나는 물에 잠긴 칸이 있나
func flooded_along(a: Vector2, b: Vector2, hw: float) -> bool:
	if flood.is_empty():
		return false
	var c := cell_m()
	for k in flood:
		var p := Vector2(k) * c
		if _seg_point(a, b, p).distance_to(p) < hw + c * 0.5:
			return true
	return false


## 지어진 건물 가운데 물에 잠긴 것: 종류 → 수
func flooded_built() -> Dictionary:
	var out := {}
	if flood.is_empty():
		return out
	for e in buildings:
		if int(e["seq"]) != -1:
			continue
		if flooded_in(entry_rect(e)) > 0:
			var k := String(e["id"])
			out[k] = int(out.get(k, 0)) + 1
	return out


## 고친 땅의 부피 (m³, 판 것·쌓은 것)
func terrain_volume() -> Vector2:
	var c2 := cell_m() * cell_m()
	var dug := 0.0
	var raised := 0.0
	for k in terrain:
		var v := float(terrain[k])
		if v < 0.0:
			dug -= v * c2
		else:
			raised += v * c2
	return Vector2(dug, raised)


## 가까운 꼭짓점이나 길 위의 점으로 붙인다
func snap(p: Vector2, radius: float = SNAP_M) -> Vector2:
	var best := -1
	var best_d := radius
	for i in nodes.size():
		var d := (nodes[i] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return nodes[best]
	var k := nearest_edge(p, radius)
	if k >= 0:
		return _seg_point(nodes[edges[k].x], nodes[edges[k].y], p)
	return p


func nearest_edge(p: Vector2, max_d: float = INF, ground_only: bool = false) -> int:
	var best := -1
	var best_d := max_d
	var ks: Variant = edges.size()
	if max_d < 64.0 and _eidx_sig == "%d|%d|%d" % [road_rev, edges.size(), nodes.size()]:
		# 가까운 길만: 길 색인이 지금 길 그물의 것이면 그 칸들의 길만 본다 (번호 순 — 다 훑을 때와 같은 답)
		var near := _near_edges(Rect2(p, Vector2.ZERO).grow(max_d))
		near.sort()
		ks = near
	for k: int in ks:
		if ground_only and LayoutData.raised(edge_type(k)):
			continue
		var q := _seg_point(nodes[edges[k].x], nodes[edges[k].y], p)
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = k
	return best


## 길 하나를 깐다: 끝은 가까운 꼭짓점·길에 붙고, 지나가며 만나는 같은 높이의 길과는 교차로가 된다.
## 높은 길(고가·다리)은 땅 위의 길 위로 지나가 만나지 않는다 — 끝만 땅 위의 길에 내려앉는다
func add_road(a: Vector2, b: Vector2, snap_r: float = SNAP_M, type: String = "street") -> bool:
	var up := LayoutData.raised(type)
	var ia := _attach(a, snap_r, up)
	var ib := _attach(b, snap_r, up)
	if ia == ib:
		return false
	var pa: Vector2 = nodes[ia]
	var pb: Vector2 = nodes[ib]
	var cuts := []
	var lv := _node_levels()
	for n in nodes.size():
		if n == ia or n == ib or up or (n < lv.size() and lv[n] == 2):
			continue                # 높은 길은 지나는 꼭짓점과 이어지지 않는다 (땅 위의 길은 높은 길만의 꼭짓점과)
		var q := _seg_point(pa, pb, nodes[n])
		if q.distance_to(nodes[n]) < 0.5:
			var t := (q - pa).length() / pa.distance_to(pb)
			if t > 1e-4 and t < 1.0 - 1e-4:
				cuts.append([t, n])
	var count := edges.size()
	var any_up := not lv.is_empty()
	for k in count:
		var e: Vector2i = edges[k]
		if e.x in [ia, ib] or e.y in [ia, ib] or up or (any_up and LayoutData.raised(edge_type(k))):
			continue                # 높이가 다른 길은 엇갈려 지난다
		var hit: Variant = Geometry2D.segment_intersects_segment(pa, pb, nodes[e.x], nodes[e.y])
		if hit == null:
			continue
		var hp: Vector2 = hit
		if hp.distance_to(nodes[e.x]) < 0.5 or hp.distance_to(nodes[e.y]) < 0.5:
			continue        # 꼭짓점을 지나는 경우는 위에서 셌다
		var n := _split_edge(k, hp)
		cuts.append([(hp - pa).length() / pa.distance_to(pb), n])
	cuts.sort_custom(func(x, y): return x[0] < y[0])
	var chain := [ia]
	for c in cuts:
		if c[1] != chain[-1]:
			chain.append(c[1])
	if chain[-1] != ib:
		chain.append(ib)
	var added := false
	for i in range(chain.size() - 1):
		var k := _edge_index(chain[i], chain[i + 1])
		if k < 0:
			edges.append(Vector2i(chain[i], chain[i + 1]))
			etypes.append(type)
			added = true
		elif String(etypes[k]) != type:
			etypes[k] = type          # 이미 난 길 위에 다른 종류로 다시 내면 그 종류로 바꾼다
			added = true
	if added:
		_roads_changed()
	return added


func remove_edge(k: int) -> void:
	if k < 0 or k >= edges.size():
		return
	edges.remove_at(k)
	etypes.remove_at(k)
	_tidy()
	_roads_changed()


func edge_type(k: int) -> String:
	return String(etypes[k]) if k >= 0 and k < etypes.size() else "street"


## 꼭짓점마다: 0 땅 위의 길만 (또는 길 없음), 1 땅 위의 길과 높은 길이 만나는 곳 (높은 길의 끝 — 오르내리는 곳),
## 2 높은 길만 둘 이상 (높은 길의 가운데 — 다른 길이 붙지 않는다). 높은 길만 하나인 막다른 곳은 1
func _node_levels() -> PackedByteArray:
	if not has_raised():
		return PackedByteArray()    # 높은 길이 없으면 모두 0 — 빈 배열 (부르는 쪽은 크기를 본다)
	var g := PackedInt32Array()
	var r := PackedInt32Array()
	g.resize(nodes.size())
	r.resize(nodes.size())
	for k in edges.size():
		var e: Vector2i = edges[k]
		if LayoutData.raised(edge_type(k)):
			r[e.x] += 1
			r[e.y] += 1
		else:
			g[e.x] += 1
			g[e.y] += 1
	var out := PackedByteArray()
	out.resize(nodes.size())
	for i in nodes.size():
		out[i] = 0 if r[i] == 0 else (2 if g[i] == 0 and r[i] >= 2 else 1)
	return out


# ── 높은 길 (고가·다리) ─────────────────────────────────────────
## 높은 길이 하나라도 있나 — 없으면 높이를 따지는 일(꼭짓점 높이, 덱 위의 경로)을 건너뛴다
func has_raised() -> bool:
	for t in LayoutData.raised_types():
		if etypes.has(t):
			return true
	return false


## 높은 길의 사슬: 길마다 {s0, s1, len, deck, grade, bridge, ends: [꼭짓점, 꼭짓점]} (땅 위의 길은 {}).
## 사슬은 높은 길만 둘 잇는 꼭짓점을 따라 이어진 높은 길들이고, 두 끝(땅 위의 길과 만나거나 막다른 곳)에서 grade로 오르내린다.
## s0·s1은 그 길의 앞 끝·뒤 끝(edges의 x·y)이 사슬 앞 끝에서 떨어진 거리. 사슬의 덱은 가장 높은 것, 기울기는 가장 완만한 것
func levels() -> Array:
	if _lv_rev == road_rev and _lv.size() == edges.size():
		return _lv
	_lv = []
	_lv.resize(edges.size())
	for k in edges.size():
		_lv[k] = {}
	var lvn := _node_levels()
	var inc := {}                   # 꼭짓점 → 그 꼭짓점의 높은 길들
	for k in edges.size():
		if LayoutData.raised(edge_type(k)):
			for nd in [edges[k].x, edges[k].y]:
				if not inc.has(nd):
					inc[nd] = []
				inc[nd].append(k)
	var seen := {}
	for k0 in edges.size():
		if seen.has(k0) or not LayoutData.raised(edge_type(k0)):
			continue
		# 사슬의 한 끝까지 거슬러 간다
		var start: int = edges[k0].x
		var cur_k := k0
		var guard := 0
		while lvn[start] == 2 and (inc[start] as Array).size() == 2 and guard < edges.size():
			var nk: int = inc[start][0] if inc[start][0] != cur_k else inc[start][1]
			if nk == k0:
				break                       # 고리
			cur_k = nk
			start = edges[nk].y if edges[nk].x == start else edges[nk].x
			guard += 1
		# 그 끝에서 다른 끝까지 따라가며 거리를 적는다
		var order: Array = []
		var nd := start
		var k := cur_k
		var s := 0.0
		guard = 0
		while guard <= edges.size():
			seen[k] = true
			var e: Vector2i = edges[k]
			var other := e.y if e.x == nd else e.x
			var length := (nodes[e.x] as Vector2).distance_to(nodes[e.y])
			order.append([k, s, s + length, e.x == nd])
			s += length
			nd = other
			guard += 1
			if lvn[nd] != 2 or (inc[nd] as Array).size() != 2:
				break
			var nk2: int = inc[nd][0] if inc[nd][0] != k else inc[nd][1]
			if seen.has(nk2):
				break
			k = nk2
		var deck := 0.0
		var grade := INF
		var bridge := false
		for it in order:
			var t := edge_type(it[0])
			var rd := LayoutData.road(t)
			deck = maxf(deck, float(rd.get("deck_m", 6.0)))
			grade = minf(grade, float(rd.get("grade", 0.06)))
			bridge = bridge or LayoutData.level(t) == "bridge"
		for it in order:
			var fwd: bool = it[3]
			_lv[it[0]] = {"s0": it[1] if fwd else it[2], "s1": it[2] if fwd else it[1], "len": s, "deck": deck,
				"grade": maxf(grade, 0.01), "bridge": bridge, "ends": [start, nd]}
	_lv_rev = road_rev
	return _lv


## 높은 길 k의 덱이 오른 높이 (m) — 앞 끝(edges[k].x)에서 t(0~1)만큼 간 곳. 사슬 끝에서 grade로 오르고 deck에서 멈춘다.
## 고가는 그 땅 위로, 다리는 사슬 두 끝의 땅 높이를 잇는 곧은 선 위로 이만큼. 땅 위의 길은 0
func lift(k: int, t: float) -> float:
	var lv := levels()
	if k < 0 or k >= lv.size() or (lv[k] as Dictionary).is_empty():
		return 0.0
	var d: Dictionary = lv[k]
	var s := lerpf(float(d["s0"]), float(d["s1"]), t)
	return minf(float(d["deck"]), float(d["grade"]) * minf(s, float(d["len"]) - s))


## 높은 길 k 위의 점이 그 자리 땅에서 뜬 높이 (탈것). 다리는 땅을 알면 두 끝을 잇는 선으로 (모르면 고가처럼)
func deck_offset(k: int, t: float) -> float:
	var up := lift(k, t)
	var lv := levels()
	if up <= 0.0 or ground == null or not bool((lv[k] as Dictionary).get("bridge", false)):
		return up
	var d: Dictionary = lv[k]
	var ends: Array = d["ends"]
	var p: Vector2 = (nodes[edges[k].x] as Vector2).lerp(nodes[edges[k].y], t)
	var s := lerpf(float(d["s0"]), float(d["s1"]), t)
	var ha := ground.local_height_m(nodes[ends[0]])
	var hb := ground.local_height_m(nodes[ends[1]])
	var hp := ground.local_height_m(p)
	return maxf(lerpf(ha, hb, s / maxf(float(d["len"]), 0.01)) + up, hp + 0.5) - hp


## 그 길의 반폭 (m)
func edge_half(k: int) -> float:
	return LayoutData.road_half(edge_type(k))


func _roads_changed() -> void:
	road_rev += 1
	_touch()


## 점을 꼭짓점으로: 가까운 꼭짓점, 아니면 가까운 땅 위의 길을 나눈 점, 아니면 새 꼭짓점.
## 높은 길의 가운데 꼭짓점(높은 길만 둘 잇는 곳)에는 붙지 않는다 — 높은 길은 끝에서만 다른 길과 이어진다
func _attach(p: Vector2, snap_r: float, _up: bool = false) -> int:
	var best := -1
	var best_d := snap_r
	var lv := _node_levels()
	for i in nodes.size():
		var d := (nodes[i] as Vector2).distance_to(p)
		if d < best_d and not (i < lv.size() and lv[i] == 2):
			best_d = d
			best = i
	if best >= 0:
		return best
	var k := nearest_edge(p, maxf(snap_r, 0.5), not lv.is_empty())
	if k >= 0:
		return _split_edge(k, _seg_point(nodes[edges[k].x], nodes[edges[k].y], p))
	nodes.append(p)
	return nodes.size() - 1


func _split_edge(k: int, p: Vector2) -> int:
	var e: Vector2i = edges[k]
	if p.distance_to(nodes[e.x]) < 0.5:
		return e.x
	if p.distance_to(nodes[e.y]) < 0.5:
		return e.y
	nodes.append(p)
	var n := nodes.size() - 1
	edges[k] = Vector2i(e.x, n)
	edges.append(Vector2i(n, e.y))
	etypes.append(edge_type(k))
	return n


func _has_edge(i: int, j: int) -> bool:
	return _edge_index(i, j) >= 0


func _edge_index(i: int, j: int) -> int:
	for k in edges.size():
		var e: Vector2i = edges[k]
		if (e.x == i and e.y == j) or (e.x == j and e.y == i):
			return k
	return -1


## 길을 지운 뒤: 홀로 남은 꼭짓점을 없애고, 곧게 이어지는 꼭짓점(둘만 잇는)은 합친다
func _tidy() -> void:
	var changed_any := true
	while changed_any:
		changed_any = false
		var deg := []
		deg.resize(nodes.size())
		deg.fill(0)
		for e in edges:
			deg[e.x] += 1
			deg[e.y] += 1
		for n in nodes.size():
			if deg[n] != 2:
				continue
			var ks := []
			for k in edges.size():
				if edges[k].x == n or edges[k].y == n:
					ks.append(k)
			var e0: Vector2i = edges[ks[0]]
			var e1: Vector2i = edges[ks[1]]
			var o0 := e0.y if e0.x == n else e0.x
			var o1 := e1.y if e1.x == n else e1.x
			var d0 := (nodes[o0] - nodes[n]) as Vector2
			var d1 := (nodes[o1] - nodes[n]) as Vector2
			var t0 := edge_type(ks[0])
			if d0.normalized().dot(d1.normalized()) < -0.9998 and not _has_edge(o0, o1) and t0 == edge_type(ks[1]):
				edges.remove_at(maxi(ks[0], ks[1]))
				etypes.remove_at(maxi(ks[0], ks[1]))
				edges.remove_at(mini(ks[0], ks[1]))
				etypes.remove_at(mini(ks[0], ks[1]))
				edges.append(Vector2i(o0, o1))
				etypes.append(t0)
				changed_any = true
				break
	# 쓰지 않는 꼭짓점 지우기
	var used := {}
	for e in edges:
		used[e.x] = true
		used[e.y] = true
	var remap := {}
	var kept := []
	for i in nodes.size():
		if used.has(i):
			remap[i] = kept.size()
			kept.append(nodes[i])
	nodes = kept
	for k in edges.size():
		edges[k] = Vector2i(remap[edges[k].x], remap[edges[k].y])


func degree(n: int) -> int:
	var d := 0
	for e in edges:
		if e.x == n or e.y == n:
			d += 1
	return d


# ── 길 찾기 (탈것) ──────────────────────────────────────────────
func _adjacency() -> Array:
	if _adj_rev == road_rev:
		return _adj
	_adj = []
	_adj.resize(nodes.size())
	for i in nodes.size():
		_adj[i] = []
	for k in edges.size():
		var e: Vector2i = edges[k]
		var l := (nodes[e.x] as Vector2).distance_to(nodes[e.y])
		_adj[e.x].append([e.y, l, k])
		_adj[e.y].append([e.x, l, k])
	_adj_rev = road_rev
	return _adj


## 길을 따라가는 경로: 가까운 길로 올라가 → 꼭짓점들 → 목적지에 가까운 길에서 내려간다. Vector3(z = 0)의 배열
func route(from: Vector3, to: Vector3) -> Array:
	var a := Vector2(from.x, from.y)
	var b := Vector2(to.x, to.y)
	var up := has_raised()
	var ka := nearest_edge(a, INF, up)          # 땅 위의 길로 올라가고 내린다 (높은 길에 바로 오르지 않는다)
	var kb := nearest_edge(b, INF, up)
	if ka < 0 or kb < 0 or a.distance_to(b) < 12.0:
		return [Vector3(b.x, b.y, 0)]
	var ea: Vector2i = edges[ka]
	var eb: Vector2i = edges[kb]
	var pa := _seg_point(nodes[ea.x], nodes[ea.y], a)
	var pb := _seg_point(nodes[eb.x], nodes[eb.y], b)
	var pts: Array = []
	if pa.distance_to(a) > 0.5:
		pts.append(pa)
	if ka == kb:
		pts.append(pb)
	else:
		var path := _shortest(ea, pa, eb, pb)
		pts.append_array(path)
		pts.append(pb)
	pts.append(b)
	var out := []
	for p in pts:
		var q: Vector2 = p
		if up and not out.is_empty():
			_raised_between(out, Vector2(out[-1].x, out[-1].y), q)
		if out.is_empty() or Vector2(out[-1].x, out[-1].y).distance_to(q) > 0.05:
			out.append(Vector3(q.x, q.y, 0))
	return out


## 경로의 두 꼭짓점 사이가 높은 길이면 덱 높이(z)의 점을 8 m마다 넣는다
func _raised_between(out: Array, p: Vector2, q: Vector2) -> void:
	var adj := _adjacency()
	var ip := _node_at(p)
	if ip < 0:
		return
	for pair in adj[ip]:
		var k: int = pair[2]
		if not LayoutData.raised(edge_type(k)) or (nodes[pair[0]] as Vector2).distance_to(q) > 0.05:
			continue
		var fwd: bool = edges[k].x == ip
		var n := maxi(2, int(ceil(p.distance_to(q) / 8.0)))
		for i in range(1, n):
			var f := float(i) / n
			var t := f if fwd else 1.0 - f
			var at := p.lerp(q, f)
			out.append(Vector3(at.x, at.y, deck_offset(k, t)))
		return


func _node_at(p: Vector2) -> int:
	for i in nodes.size():
		if (nodes[i] as Vector2).distance_to(p) < 0.05:
			return i
	return -1


## 길 ea 위의 pa에서 길 eb 위의 pb까지 지나는 꼭짓점 위치들 (다익스트라)
func _shortest(ea: Vector2i, pa: Vector2, eb: Vector2i, pb: Vector2) -> Array:
	var adj := _adjacency()
	var n := nodes.size()
	var dist := []
	dist.resize(n)
	dist.fill(INF)
	var prev := []
	prev.resize(n)
	prev.fill(-1)
	var done := []
	done.resize(n)
	done.fill(false)
	dist[ea.x] = pa.distance_to(nodes[ea.x])
	dist[ea.y] = pa.distance_to(nodes[ea.y])
	while true:
		var u := -1
		var best := INF
		for i in n:
			if not done[i] and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = true
		for pair in adj[u]:
			var v: int = pair[0]
			var nd: float = dist[u] + float(pair[1])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	var end_x: float = dist[eb.x] + pb.distance_to(nodes[eb.x])
	var end_y: float = dist[eb.y] + pb.distance_to(nodes[eb.y])
	var last := eb.x if end_x <= end_y else eb.y
	if dist[last] == INF:
		return []
	var chain := []
	var cur := last
	while cur >= 0:
		chain.push_front(nodes[cur])
		cur = prev[cur]
	return chain


func random_node(rng: RandomNumberGenerator) -> Vector2:
	if nodes.is_empty():
		return hub()
	return nodes[rng.randi() % nodes.size()]


# ── 찾기 ────────────────────────────────────────────────────────
## 지어진 건물 중 이 계열(종류 모두)의 자리들 (지은 순서)
func built_of_family(f: String) -> Array:
	# 기지의 탈것이 프레임마다 묻는다 (굴착기·로봇 정비소·착륙장…) — 배치가 바뀔 때까지 같은 답 (받는 쪽은 고치지 않는다)
	var rev := revision * 100000 + buildings.size()
	if rev != _fam_rev:
		_fam_rev = rev
		_fam_built.clear()
	if not _fam_built.has(f):
		var out := []
		for e in buildings:
			if fam(String(e["id"])) == f and int(e["seq"]) < 0:
				out.append(Vector3(e["x"], e["y"], 0))
		_fam_built[f] = out
	return _fam_built[f]


## 지어진 건물 중 이 종류의 자리들 (지은 순서)
func built_of(kind: String) -> Array:
	var out := []
	for e in buildings:
		if e["id"] == kind and int(e["seq"]) < 0:
			out.append(Vector3(e["x"], e["y"], 0))
	return out


## 모형 좌표의 점에 서 있는 건물 (없으면 {})
func entry_at(p: Vector2) -> Dictionary:
	for i in range(buildings.size() - 1, -1, -1):
		if entry_rect(buildings[i]).has_point(p):
			return buildings[i]
	return {}


# ── 저장 ────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	var bs := []
	for e in buildings:
		var b := [int(e["uid"]), e["id"], snappedf(e["x"], 0.01), snappedf(e["y"], 0.01), int(e["rot"]),
			int(e["variant"]), int(e["seq"]), e["tile"]]
		if e.has("was") and int(e["seq"]) >= 0:
			b.append(e["was"])
		bs.append(b)
	var ns := []
	for p in nodes:
		ns.append(snappedf(p.x, 0.01))
		ns.append(snappedf(p.y, 0.01))
	var es := []
	for e in edges:
		es.append(e.x)
		es.append(e.y)
	var zs := []
	for sd in district_seeds:
		zs.append([snappedf((sd[0] as Vector2).x, 0.1), snappedf((sd[0] as Vector2).y, 0.1), sd[1]])
	var ts := []
	for k in terrain:
		ts.append_array([(k as Vector2i).x, (k as Vector2i).y, int(round(float(terrain[k]) * 100.0))])
	var fs := []
	for k in flood:
		fs.append_array([(k as Vector2i).x, (k as Vector2i).y, int(round(float(flood[k]) * 10.0))])
	var ls := []
	for k in land:
		ls.append([(k as Vector2i).x, (k as Vector2i).y])
	var out := {"version": VERSION, "next_uid": _next_uid, "buildings": bs, "nodes": ns, "edges": es, "types": etypes.duplicate(),
		"districts": zs, "terrain": ts, "flood": fs, "land": ls}
	if runway_at.size() == 2:
		out["runway"] = runway_at.duplicate()
	if not works.is_empty():
		out["works"] = RoadWorks.to_save(works)
	if not scars.is_empty():
		out["scars"] = scars.map(func(w): return [w["kind"], snappedf(w["a"].x, 0.1), snappedf(w["a"].y, 0.1), snappedf(w["b"].x, 0.1),
			snappedf(w["b"].y, 0.1), snappedf(float(w["r"]), 0.1), int(w["hour"])])
	if not mega.is_empty() or not mega_done.is_empty():
		out["mega"] = mega.map(func(w): return [w["id"], w["cell"].x, w["cell"].y, int(w["stage"]), snappedf(float(w["p"]), 0.0001)])
		out["mega_done"] = mega_done.map(func(w): return [w["id"], w["cell"].x, w["cell"].y])
	return out


## 저장한 계획을 되살리고 시뮬레이션과 맞춘다. 없거나 읽을 수 없으면 새 계획
## sync_now = false: 시뮬레이션에 맞추는 자리 찾기를 미룬다 (불러오기 — 그 도시를 볼 때 프레임마다 조금씩 맞춘다)
static func from_save(data: Variant, sim: CitySim, p_layout: BaseLayout = null, sync_now: bool = true) -> CityPlan:
	if not data is Dictionary or not int(data.get("version", 0)) in [1, VERSION]:
		return create(sim, p_layout)
	var plan := CityPlan.new(p_layout)
	plan.body = _body_of(sim)
	plan.site_id = sim.site_id if sim != null else ""
	for b in data.get("buildings", []):
		if not b is Array or b.size() < 8 or not ArtLib.has("buildings", String(b[1])):
			continue
		plan.buildings.append({"uid": int(b[0]), "id": String(b[1]), "x": float(b[2]), "y": float(b[3]),
			"rot": int(b[4]) % 4, "variant": int(b[5]), "seq": int(b[6]), "tile": String(b[7])})
		if b.size() >= 9 and b[8] is Array and int(b[6]) >= 0:
			var was: Array = []
			for w in b[8]:
				if w is Array and w.size() >= 5 and ArtLib.has("buildings", String(w[0])):
					was.append([String(w[0]), int(w[1]), int(w[2]) % 4, float(w[3]), float(w[4])])
			if not was.is_empty():
				plan.buildings[-1]["was"] = was
	var ns: Array = data.get("nodes", [])
	for i in range(0, ns.size() - 1, 2):
		plan.nodes.append(Vector2(float(ns[i]), float(ns[i + 1])))
	var es: Array = data.get("edges", [])
	var ts: Array = data.get("types", [])
	for i in range(0, es.size() - 1, 2):
		var a := int(es[i])
		var b := int(es[i + 1])
		if a >= 0 and b >= 0 and a < plan.nodes.size() and b < plan.nodes.size() and a != b:
			plan.edges.append(Vector2i(a, b))
			@warning_ignore("integer_division")
			var ti := i / 2
			var t := String(ts[ti]) if ti < ts.size() else "street"
			LayoutData.load_all()
			plan.etypes.append(t if (LayoutData.data["roads"] as Dictionary).has(t) else "street")
	for z in data.get("districts", []):
		if z is Array and z.size() >= 3:
			plan.district_seeds.append([Vector2(float(z[0]), float(z[1])), String(z[2])])
	if not data.has("districts"):
		# 옛 저장 (1판): 기본 배치의 블록 용도를 씨앗으로
		for bl in plan.layout.blocks:
			if String(bl["district"]) != "":
				plan.district_seeds.append([(bl["cell"] as Rect2).get_center(), String(bl["district"])])
	var tr: Array = data.get("terrain", [])
	for i in range(0, tr.size() - 2, 3):
		plan.terrain[Vector2i(int(tr[i]), int(tr[i + 1]))] = float(tr[i + 2]) / 100.0
	for l in data.get("land", []):
		if l is Array and l.size() >= 2:
			plan.land[Vector2i(int(l[0]), int(l[1]))] = true
	var fl: Array = data.get("flood", [])
	for i in range(0, fl.size() - 2, 3):
		plan.flood[Vector2i(int(fl[i]), int(fl[i + 1]))] = float(fl[i + 2]) / 10.0
	plan._next_uid = maxi(int(data.get("next_uid", 1)), 1)
	for e in plan.buildings:
		plan._next_uid = maxi(plan._next_uid, int(e["uid"]) + 1)
	var rs: Variant = data.get("runway")
	if rs is Array and rs.size() == 2 and String(rs[0]) in ["+x", "-x", "+y", "-y"]:
		plan.runway_at = [String(rs[0]), int(rs[1])]
	plan.works = RoadWorks.from_save(data.get("works"))
	for w in data.get("mega", []):
		if w is Array and w.size() >= 5 and not CityProgress.mega(String(w[0])).is_empty():
			plan.mega.append({"id": String(w[0]), "cell": Vector2i(int(w[1]), int(w[2])), "stage": int(w[3]), "p": float(w[4])})
	for w in data.get("scars", []):
		if w is Array and w.size() >= 7:
			plan.scars.append({"kind": String(w[0]), "a": Vector2(float(w[1]), float(w[2])), "b": Vector2(float(w[3]), float(w[4])),
				"r": float(w[5]), "hour": int(w[6])})
	for w in data.get("mega_done", []):
		if w is Array and w.size() >= 3 and not CityProgress.mega(String(w[0])).is_empty():
			plan.mega_done.append({"id": String(w[0]), "cell": Vector2i(int(w[1]), int(w[2]))})
	plan.road_rev += 1
	plan._ensure_taxiway()
	if sim != null and sync_now:
		plan.sync(sim)
	return plan
