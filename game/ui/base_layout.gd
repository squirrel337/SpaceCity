class_name BaseLayout
extends RefCounted
## 기본 배치 — 길이 먼저, 블록이 그다음. 기지 평지에 길 격자(두 블록마다 대로, 그 사이 도로)를 깔고, 길이 둘러싼
## 블록마다 용도(구획: 거주·시민·생명유지·축전·농업·산업·원자로·돔)를 정한 뒤, 블록 안에 건물 자리를 길을 마주 보게
## 줄지어 둔다 (두 줄마다 뒷길). 우주항(착륙장 둘레 30 m를 비워야 한다)과 얼음 분화구는 따로 두고 길로 잇는다.
## 플레이어가 자리를 고르지 않은 건물(처음 기지, 자동 운영)은 CityPlan이 이 자리를 차례로 쓴다.
## 좌표는 미터. x는 화면 오른쪽 아래, y는 왼쪽 아래로 간다. 구획이 모이는 곳은 화면 기준(u: 오른쪽, v: 아래)으로 적는다.

const SQ := 0.7071067811865476
const ROAD_W := 7.0              # 도로의 폭 (길 종류는 data/city_layout.json)
const PLAZA_R := 12.0            # 거주 구역 한가운데 광장 (대로 둘이 만나는 곳)
const GAP := 3.0
const LANE := 3.5                # 블록 안 두 줄마다 뒷길
const WALK := 1.5                # 길과 블록 사이 보도
const BOUNDS_UV := Rect2(-235, -262, 470, 530)      # 지도 끝 (u, v)
const CREST_V := -214.0                               # 능선 마루 (그 위는 하늘)
const ICE_CRATER_R := 34.0
const SPECIAL := ["ice", "pad"]                       # 블록이 아니라 따로 두는 구획
const PAD_CLEAR := 30.0                               # 착륙장 둘레 (착륙 분사) — 우주항 땅이 이만큼 넉넉하다
## 능선의 일조 구역 (u, v 사각형). 태양광 타워는 여기에만 서고, 구역이 곧 시뮬레이션의 일조 칸이다:
## A 마루 한가운데(일조 100%), B 양옆(85%), C 낮은 비탈(70%). 왼쪽 C는 얼음 분화구를 비켜 바깥에 있다
const ZONES := {
	"A": [Rect2(-44, CREST_V + 4, 88, 13)],
	"B": [Rect2(-106, CREST_V + 8, 56, 14), Rect2(50, CREST_V + 8, 56, 14)],
	"C": [Rect2(-234, CREST_V + 18, 62, 22), Rect2(112, CREST_V + 18, 62, 22)],
}
## 구획을 채우는 차례 (가운데에 가까워야 하는 것부터)
const ORDER := ["core", "civic", "life", "domes", "farm", "power", "industry", "reactor", "commerce", "tech", "transit"]

var slots := {}            # 계열 → Array[Vector3] (자리 중심, 채우는 순서)
var district_of := {}      # 계열 → 구획 이름
var rects := {}            # 구획 → Rect2 (그 구획 블록들을 감싸는 사각형, 월드 x·y)
var lots := {}             # 구획 → Array[Rect2] 필지 (자리마다 칸 — 빈 필지도 구획으로 보인다)
var lanes := {}            # 구획 → Array[[Vector2, Vector2]] 블록 안 두 줄 사이 뒷길
var gates := {}            # 구획 → Vector3 (그 구획 블록에 닿는 길 위의 점)
var hub := Vector3.ZERO
var segments: Array = []   # [[Vector2 a, Vector2 b, 길 종류]] — 처음 길 (CityPlan이 길 그물로 바꾼다)
var blocks: Array = []     # [{cell: Rect2 (길 가운데선 사이), inner: Rect2 (보도 안쪽), district: String}]
var tower_slots: Array = []   # [Vector3, "A"|"B"|"C"]
## 길 격자 (땅 구역도 이 격자를 따른다): 원점(거주 구역 가운데의 교차로), 격자 간격, 몇 줄마다 대로,
## 기본 배치에서 블록이 된 칸 (원점에서 센 칸 번호 → true)
var grid_o := Vector2.ZERO
var pitch := 56.0
var every := 2
var open_cells := {}
var ice_center := Vector3.ZERO
var pad_rect := Rect2()    # 우주항 (착륙장 줄)
var pad_area := Rect2()    # 우주항 땅 — 길 격자의 블록 칸에 맞춘 사각형 (착륙장 줄과 둘레 30 m가 들고, 둘레로 격자 길이 지난다)
## 부지 종류: "ridge" — 능선의 일조 구역 A·B·C와 얼음 분화구 (달 남극·수성 극지),
## "open" — 능선이 없는 평지: 일조 구역이 한 덩어리의 태양광 단지(A)이고 얼음 분화구 자리는 얼음 매장지다
var kind := "ridge"
var zones := {}                # 일조 구역 이름 → [Rect2 (u, v)]
var crest_v := CREST_V         # 이 위(v가 더 작은 쪽)로는 지을 수 없다


static func uv_to_xy(uv: Vector2) -> Vector2:
	return Vector2((uv.x + uv.y) * SQ, (uv.y - uv.x) * SQ)


static func xy_to_uv(xy: Vector2) -> Vector2:
	return Vector2((xy.x - xy.y) * SQ, (xy.x + xy.y) * SQ)


## 구획의 이름과 색 (3D 기지의 블록 판·이름표)
static func district_info(name: String) -> Array:
	var z := LayoutData.zone(name)
	if z.is_empty():
		return ["빈 블록", Color(0.62, 0.64, 0.68)]
	return [String(z["name"]), Color(String(z["color"]))]


func _init(p_kind: String = "ridge") -> void:
	kind = p_kind
	if kind == "open":
		zones = {"A": ZONES["A"] + ZONES["B"] + ZONES["C"]}
		crest_v = BOUNDS_UV.position.y - 40.0
	else:
		zones = ZONES
		crest_v = CREST_V
	var zd := LayoutData.zones()
	var ic := uv_to_xy(Vector2(zd["ice"]["center_uv"][0], zd["ice"]["center_uv"][1]))
	ice_center = Vector3(ic.x, ic.y, 0)
	var core_c := uv_to_xy(Vector2(zd["core"]["center_uv"][0], zd["core"]["center_uv"][1]))
	_grid_setup(core_c)
	_place_specials(zd)
	_grid(core_c)
	_assign(zd)
	_connect_specials()
	_towers()


func _cell(kind_id: String) -> Vector2:
	if kind_id == "hab_module":
		return Vector2(14, 10)
	return ArtLib.footprint(kind_id) + Vector2(GAP, GAP)


# ── 길 격자와 블록 ──────────────────────────────────────────────
## 격자선 k(원점에서 센 번호)의 길 종류: 몇 줄마다 대로, 그 사이 도로
func line_type(k: int) -> String:
	return "avenue" if posmod(k, every) == 0 else "street"


## 칸 (원점에서 센 번호)의 사각형 (모형 좌표)
func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(grid_o + Vector2(c) * pitch, Vector2(pitch, pitch))


## 처음 땅(기지 지도) 안인가: 지도 끝에서 margin 안쪽, 능선 마루에서 crest_off 아래
func base_has(p: Vector2, margin: float = 0.0, crest_off: float = 0.0) -> bool:
	var uv := xy_to_uv(p)
	return BOUNDS_UV.grow(-margin).has_point(uv) and uv.y >= crest_v + crest_off


## 일조 구역·얼음 분화구·우주항 (길 격자를 깔지 않는 곳)
func special_at(p: Vector2, pad: float = 8.0) -> bool:
	var uv := xy_to_uv(p)
	for t in zones:
		for r in zones[t]:
			if (r as Rect2).grow(pad).has_point(uv):
				return true
	if p.distance_to(Vector2(ice_center.x, ice_center.y)) < ICE_CRATER_R + pad + 6.0:
		return true
	return pad_rect.grow(PAD_CLEAR).has_point(p)


## 이 점에 블록·길을 둘 수 있나 (지도 안, 능선 아래, 일조 구역·얼음 분화구·우주항 밖)
func _open_at(p: Vector2, margin: float) -> bool:
	var uv := xy_to_uv(p)
	if not BOUNDS_UV.grow(-margin).has_point(uv) or uv.y < crest_v + 8.0:
		return false
	for t in zones:
		for r in zones[t]:
			if (r as Rect2).grow(8.0).has_point(uv):
				return false
	if p.distance_to(Vector2(ice_center.x, ice_center.y)) < ICE_CRATER_R + 14.0:
		return false
	if pad_rect.grow(PAD_CLEAR).has_point(p):
		return false
	return true


func _cell_open(r: Rect2, margin: float) -> bool:
	for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center(),
			(r.position + r.get_center()) * 0.5, (r.end + r.get_center()) * 0.5]:
		if not _open_at(q, margin):
			return false
	return true


## 길 격자의 원점(거주 구역 가운데 — 대로 둘이 만나는 곳)과 간격 (우주항 땅도 이 격자에 맞춘다)
func _grid_setup(core_c: Vector2) -> void:
	var g := LayoutData.grid()
	every = maxi(1, int(g["avenue_every"]))
	pitch = float(g["block_m"]) + (float(LayoutData.road("avenue")["width_m"]) + float(LayoutData.road("street")["width_m"])) * 0.5
	grid_o = core_c
	hub = Vector3(core_c.x, core_c.y, 0)


## 거주 구역 가운데를 원점으로 길 격자: 두 줄마다 대로, 그 사이 도로
func _grid(core_c: Vector2) -> void:
	var margin := float(LayoutData.grid()["margin_m"])
	var w_av := float(LayoutData.road("avenue")["width_m"])
	var w_st := float(LayoutData.road("street")["width_m"])
	var n := 9
	var xs: Array = []
	var ys: Array = []
	for k in range(-n, n + 1):
		xs.append(core_c.x + k * pitch)
		ys.append(core_c.y + k * pitch)
	var half := func(k: int) -> float: return (w_av if posmod(k, every) == 0 else w_st) * 0.5
	var open_idx := {}
	for i in range(xs.size() - 1):
		for j in range(ys.size() - 1):
			var r := Rect2(xs[i], ys[j], pitch, pitch)
			if not _cell_open(r, margin):
				continue
			var inner := Rect2(Vector2(xs[i] + half.call(i - n) + WALK, ys[j] + half.call(j - n) + WALK),
				Vector2(pitch - half.call(i - n) - half.call(i + 1 - n) - 2.0 * WALK,
					pitch - half.call(j - n) - half.call(j + 1 - n) - 2.0 * WALK))
			open_idx[Vector2i(i, j)] = blocks.size()
			blocks.append({"cell": r, "inner": inner, "district": "", "ij": Vector2i(i, j)})
	open_cells = {}
	for key in open_idx:
		open_cells[(key as Vector2i) - Vector2i(n, n)] = true
	# 길: 열린 블록에 닿는 격자선 토막만
	var seen := {}
	for key in open_idx:
		var c: Vector2i = key
		var corners := [Vector2i(c.x, c.y), Vector2i(c.x + 1, c.y), Vector2i(c.x + 1, c.y + 1), Vector2i(c.x, c.y + 1)]
		for s in 4:
			var a: Vector2i = corners[s]
			var b: Vector2i = corners[(s + 1) % 4]
			var k := Vector4i(mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y))
			if seen.has(k):
				continue
			seen[k] = true
			var horizontal := a.y == b.y
			var line_k := (a.y if horizontal else a.x) - n
			var t := line_type(line_k)
			segments.append([Vector2(xs[a.x], ys[a.y]), Vector2(xs[b.x], ys[b.y]), t])


## 우주항과 얼음 분화구: 블록이 아니라 따로 (착륙장 둘레 30 m, 얼음 채굴기는 분화구 안).
## 우주항 땅은 길 격자의 블록 칸에 맞춘다 — 착륙장 줄과 둘레 30 m가 드는 가장 작은 칸 묶음(3×2)을 바라는 자리에서 가장
## 가까운 격자에 놓고, 착륙장 줄은 그 가운데에. 둘레의 블록과 길이 격자 그대로 이어진다 (비스듬히 비켜 앉지 않는다)
func _place_specials(zd: Dictionary) -> void:
	for name in SPECIAL:
		var d: Dictionary = zd[name]
		var center := uv_to_xy(Vector2(d["center_uv"][0], d["center_uv"][1]))
		var items := []
		var row_w := 76.0 if name == "pad" else 46.0
		var y := 0.0
		for pair in d["families"]:
			var k: String = pair[0]
			var cap := int(pair[1])
			var cell := _cell(k)
			var per_row := maxi(1, int(floor((row_w + 0.01) / cell.x)))
			var x0 := (row_w - per_row * cell.x) * 0.5
			for i in cap:
				@warning_ignore("integer_division")
				var r := i / per_row
				var c := i % per_row
				items.append([k, Vector2(x0 + (c + 0.5) * cell.x, y + (r + 0.5) * cell.y), cell])
			y += ceili(float(cap) / per_row) * cell.y
		var origin := center - Vector2(row_w, y) * 0.5
		if name == "pad":
			var need := Vector2(row_w, y) + Vector2(PAD_CLEAR, PAD_CLEAR) * 2.0
			var size := Vector2(ceilf(need.x / pitch), ceilf(need.y / pitch)) * pitch
			pad_area = Rect2(grid_o + ((center - size * 0.5 - grid_o) / pitch).round() * pitch, size)
			origin = pad_area.get_center() - Vector2(row_w, y) * 0.5
		var rect := Rect2(origin, Vector2(row_w, y))
		rects[name] = rect
		lots[name] = []
		lanes[name] = []
		if name == "pad":
			pad_rect = rect
		for it in items:
			var p: Vector2 = origin + it[1]
			_add_slot(it[0], name, p, it[2])


func _add_slot(kind_id: String, district: String, p: Vector2, cell: Vector2) -> void:
	if not slots.has(kind_id):
		slots[kind_id] = []
	slots[kind_id].append(Vector3(p.x, p.y, 0))
	district_of[kind_id] = district
	if not lots.has(district):
		lots[district] = []
	lots[district].append(Rect2(p - cell * 0.5 + Vector2(0.5, 0.5), cell - Vector2(1.0, 1.0)))


## 구획마다 그곳이 모이는 자리에서 가까운 블록부터 채운다 — 계열마다 자리를 줄지어 둔다
func _assign(zd: Dictionary) -> void:
	for name in ORDER:
		var d: Dictionary = zd[name]
		var want := uv_to_xy(Vector2(d["center_uv"][0], d["center_uv"][1]))
		var queue: Array = []
		for pair in d["families"]:
			queue.append([String(pair[0]), int(pair[1])])
		lots[name] = []
		lanes[name] = []
		var bound := Rect2()
		var first := true
		while not queue.is_empty():
			var best := -1
			var best_d := INF
			for i in blocks.size():
				if blocks[i]["district"] != "":
					continue
				var dd := (blocks[i]["cell"] as Rect2).get_center().distance_to(want)
				if dd < best_d:
					best_d = dd
					best = i
			if best < 0:
				break
			blocks[best]["district"] = name
			_fill_block(blocks[best], name, queue)
			var inner: Rect2 = blocks[best]["inner"]
			bound = inner if first else bound.merge(inner)
			first = false
		rects[name] = bound


## 블록 하나를 줄지어 채운다: 줄은 블록의 긴 쪽으로, 두 줄마다 뒷길 (바깥 두 줄은 길을 마주 본다)
func _fill_block(b: Dictionary, district: String, queue: Array) -> void:
	var inner: Rect2 = b["inner"]
	var y := inner.position.y
	var rows := 0
	while not queue.is_empty():
		var k: String = queue[0][0]
		var cell := _cell(k)
		var per_row := int(floor((inner.size.x + 0.01) / cell.x))
		if per_row < 1:
			queue.pop_front()         # 이 블록에 들어가지 않는 큰 건물은 기본 자리 없이 (빈자리 찾기가 맡는다)
			continue
		if y + cell.y > inner.end.y + 0.01:
			return
		var x0 := inner.position.x + (inner.size.x - per_row * cell.x) * 0.5
		for c in per_row:
			if int(queue[0][1]) <= 0:
				break
			var center := Vector2(x0 + (c + 0.5) * cell.x, y + cell.y * 0.5)
			if _near_plaza(Rect2(center - cell * 0.5, cell)):
				continue              # 거주 구역 가운데 광장 자리
			_add_slot(k, district, center, cell)
			queue[0][1] = int(queue[0][1]) - 1
		if int(queue[0][1]) <= 0:
			queue.pop_front()
		y += cell.y
		rows += 1
		if rows % 2 == 0 and y + LANE < inner.end.y:
			lanes[district].append([Vector2(inner.position.x, y + LANE * 0.5), Vector2(inner.end.x, y + LANE * 0.5)])
			y += LANE


func _near_plaza(r: Rect2) -> bool:
	var h := Vector2(hub.x, hub.y)
	var q := Vector2(clampf(h.x, r.position.x, r.end.x), clampf(h.y, r.position.y, r.end.y))
	return q.distance_to(h) < PLAZA_R + 1.5


## 우주항·얼음 분화구로 가는 길, 구획마다 길 위의 문
func _connect_specials() -> void:
	var nodes := {}
	for s in segments:
		nodes[s[0]] = true
		nodes[s[1]] = true
	var near := func(p: Vector2) -> Vector2:
		var best: Vector2 = Vector2(hub.x, hub.y)
		var bd := INF
		for q in nodes:
			var dq := (q as Vector2).distance_to(p)
			if dq < bd:
				bd = dq
				best = q
		return best
	# 우주항: 가장 가까운 길 꼭짓점에서 착륙장 줄 가장자리까지 (직각으로 꺾어) 대로
	var pc := pad_rect.get_center()
	var s1: Vector2 = near.call(pc)
	var r := pad_rect.grow(LayoutData.road_half("avenue") + 2.5)      # 길 끝이 착륙장 자리에 걸리지 않게
	var to_pad := Vector2(clampf(s1.x, r.position.x, r.end.x), clampf(s1.y, r.position.y, r.end.y))
	_route_l(s1, to_pad, "avenue")
	gates["pad"] = Vector3(to_pad.x, to_pad.y, 0)
	# 얼음 분화구: 가장자리까지 흙길
	var ic := Vector2(ice_center.x, ice_center.y)
	var s2: Vector2 = near.call(ic)
	var edge := ic + (s2 - ic).normalized() * (ICE_CRATER_R + 4.0)
	_route_l(s2, edge, "path")
	gates["ice"] = Vector3(edge.x, edge.y, 0)
	# 블록 구획의 문: 그 구획 블록들의 가운데에서 가장 가까운 길 꼭짓점
	for name in ORDER:
		if rects.has(name):
			var g: Vector2 = near.call((rects[name] as Rect2).get_center())
			gates[name] = Vector3(g.x, g.y, 0)
	gates["core"] = hub


## 두 점을 직각으로 꺾어 잇는 길 (가로 먼저)
func _route_l(a: Vector2, b: Vector2, t: String) -> void:
	if absf(a.x - b.x) < 0.5 or absf(a.y - b.y) < 0.5:
		segments.append([a, b, t])
		return
	var mid := Vector2(b.x, a.y)
	if not _open_at(mid, 0.0) and _open_at(Vector2(a.x, b.y), 0.0):
		mid = Vector2(a.x, b.y)
	segments.append([a, mid, t])
	segments.append([mid, b, t])


# ── 능선의 태양광 타워 ──────────────────────────────────────────
func _towers() -> void:
	## 능선의 태양광 타워 자리 (일조 구역 안). A: 마루 한가운데, B: 양옆, C: 낮은 비탈 두 줄
	var pts := []
	for i in range(8):
		pts.append([Vector2(-38.5 + i * 11.0, CREST_V + 10.0), "A"])
	for side in [-1, 1]:
		for i in range(5):
			pts.append([Vector2(side * (56.0 + i * 11.0), CREST_V + 15.0), "B"])
	for side in [-1, 1]:
		var start := 178.0 if side < 0 else 118.0
		for row in range(2):
			for i in range(5):
				pts.append([Vector2(side * (start + i * 11.0 + row * 5.5), CREST_V + 24.0 + row * 10.0), "C"])
	# 채우는 순서: A → B(가운데에서 바깥) → C
	var order := []
	for t in ["A", "B", "C"]:
		var group := pts.filter(func(p): return p[1] == t)
		group.sort_custom(func(a, b): return absf(a[0].x) < absf(b[0].x))
		order.append_array(group)
	for p in order:
		var xy := uv_to_xy(p[0])
		tower_slots.append([Vector3(xy.x, xy.y, 0), p[1] if kind == "ridge" else "A"])


## 일조 구역의 이름 (화면 글)
func tile_name(t: String) -> String:
	if kind == "open":
		return "태양광 단지"
	return {"A": "A 100%", "B": "B 85%", "C": "C 70%"}.get(t, t)


func zone_text() -> String:
	return "태양광 단지" if kind == "open" else "능선의 일조 구역(A·B·C)"


func ice_text() -> String:
	return "얼음 매장지" if kind == "open" else "얼음 분화구(영구 그늘)"


func capacity(kind_id: String) -> int:
	if kind_id == "solar_tower":
		return tower_slots.size()
	return slots.get(kind_id, []).size()


func slot(kind_id: String, i: int) -> Vector3:
	if kind_id == "solar_tower":
		return tower_slots[i][0]
	return slots[kind_id][i]
