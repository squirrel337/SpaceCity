class_name BaseLayout
extends RefCounted
## 기본 배치 — 건물 종류마다 구역과 자리를 미리 정해 둔다. 플레이어가 자리를 고르지 않은 건물
## (처음 기지, 자동 운영)은 CityPlan이 이 자리를 차례로 쓴다. 처음 길도 여기서 만든다.
## 좌표는 미터. x는 화면 오른쪽 아래, y는 왼쪽 아래로 간다. 구역 중심은 화면 기준(u: 오른쪽, v: 아래)으로 적는다.

const SQ := 0.7071067811865476
const ROAD_W := 5.0

## 구역: uv 중심, 줄 너비(x 방향, m), [종류, 자리 수], 칸 크기를 바꿀 종류
const DISTRICTS := {
	"core": {"uv": Vector2(-20, -15), "row_w": 84.0, "types": [["hab_module", 36]], "cell": {"hab_module": Vector2(14, 10)}},
	"civic": {"uv": Vector2(92, -2), "row_w": 60.0, "types": [["green_commons", 3], ["research_lab", 8], ["medical_bay", 4], ["comms_center", 2]]},
	"domes": {"uv": Vector2(-111, -59), "row_w": 54.0, "types": [["regolith_dome", 6], ["storm_shelter", 6]]},
	"life": {"uv": Vector2(2, -122), "row_w": 46.0, "types": [["electrolyzer", 6], ["co2_scrubber", 8], ["sabatier", 3], ["water_recycler", 6], ["tank_farm", 6]]},
	"power": {"uv": Vector2(118, -112), "row_w": 60.0, "types": [["battery_bank", 16], ["rfc_unit", 40], ["radiator", 20]]},
	"farm": {"uv": Vector2(-122, 58), "row_w": 72.0, "types": [["hydroponics", 40], ["algae_reactor", 8], ["food_store", 6]]},
	"industry": {"uv": Vector2(88, 108), "row_w": 60.0, "types": [["robot_bay", 3], ["parts_fab", 4], ["excavator", 2], ["regolith_printer", 2], ["mre_plant", 3], ["propellant_plant", 2]]},
	"reactor": {"uv": Vector2(-112, 180), "row_w": 46.0, "types": [["fission_40kw", 12], ["fission_1mw", 3]]},
	"ice": {"uv": Vector2(-140, -152), "row_w": 46.0, "types": [["ice_miner", 3]]},
	"pad": {"uv": Vector2(142, 208), "row_w": 76.0, "types": [["landing_pad", 2]]},
}
## 구역의 이름과 색 (3D 기지의 구역 판·테두리·이름표)
const DISTRICT_INFO := {
	"core": ["거주 구역", Color("7aa7f0")],
	"civic": ["시민 광장·연구 단지", Color("c86bfa")],
	"domes": ["돔·대피소", Color("f4a6c6")],
	"life": ["생명유지 단지", Color("3fb8af")],
	"power": ["축전·방열 단지", Color("f2c14e")],
	"farm": ["농업 구역", Color("8fcf6e")],
	"industry": ["산업 단지", Color("c9a77f")],
	"reactor": ["원자로 구역", Color("e9875a")],
	"ice": ["얼음 채굴장", Color("4cc9f0")],
	"pad": ["우주항", Color("aab3c8")],
}
const PLAZA_R := 13.0            # 거주 구역 한가운데 광장 (큰길이 만나는 곳)
const GAP := 3.0
const BOUNDS_UV := Rect2(-235, -262, 470, 530)      # 지도 끝 (u, v)
const CREST_V := -214.0                               # 능선 마루 (그 위는 하늘)
const ICE_CRATER_R := 34.0
## 능선의 일조 구역 (u, v 사각형). 태양광 타워는 여기에만 서고, 구역이 곧 시뮬레이션의 일조 칸이다:
## A 마루 한가운데(일조 100%), B 양옆(85%), C 낮은 비탈(70%). 왼쪽 C는 얼음 분화구를 비켜 바깥에 있다
const ZONES := {
	"A": [Rect2(-44, CREST_V + 4, 88, 13)],
	"B": [Rect2(-106, CREST_V + 8, 56, 14), Rect2(50, CREST_V + 8, 56, 14)],
	"C": [Rect2(-234, CREST_V + 18, 62, 22), Rect2(112, CREST_V + 18, 62, 22)],
}

var slots := {}            # 종류 → Array[Vector3] (자리 중심, 채우는 순서)
var district_of := {}      # 종류 → 구역 이름
var rects := {}            # 구역 → Rect2 (월드 x·y)
var lots := {}             # 구역 → Array[Rect2] 필지 (자리마다 칸 — 빈 필지도 구획으로 보인다)
var lanes := {}            # 구역 → Array[[Vector2, Vector2]] 줄 사이 보행로
var gates := {}            # 구역 → Vector3 (길이 닿는 구역 가장자리)
var hub := Vector3.ZERO
var roads: Array = []      # Array[PackedVector3Array] — 처음 길 (CityPlan이 길 그물로 바꾼다)
var tower_slots: Array = []   # [Vector3, "A"|"B"|"C"]
var ice_center := Vector3.ZERO
## 부지 종류: "ridge" — 능선의 일조 구역 A·B·C와 얼음 분화구 (달 남극·수성 극지),
## "open" — 능선이 없는 평지: 일조 구역이 한 덩어리의 태양광 단지(A)이고 얼음 분화구 자리는 얼음 매장지다
var kind := "ridge"
var zones := {}                # 일조 구역 이름 → [Rect2 (u, v)]
var crest_v := CREST_V         # 이 위(v가 더 작은 쪽)로는 지을 수 없다

static var _road_cache: Array = []
static var _gate_cache: Dictionary = {}


static func uv_to_xy(uv: Vector2) -> Vector2:
	return Vector2((uv.x + uv.y) * SQ, (uv.y - uv.x) * SQ)


static func xy_to_uv(xy: Vector2) -> Vector2:
	return Vector2((xy.x - xy.y) * SQ, (xy.x + xy.y) * SQ)


func _init(p_kind: String = "ridge") -> void:
	kind = p_kind
	if kind == "open":
		zones = {"A": ZONES["A"] + ZONES["B"] + ZONES["C"]}
		crest_v = BOUNDS_UV.position.y - 40.0
	else:
		zones = ZONES
	for d in DISTRICTS:
		_pack(d, DISTRICTS[d])
	var core: Rect2 = rects["core"]
	hub = Vector3(core.get_center().x, core.get_center().y, 0)
	_towers()
	var ic := uv_to_xy(DISTRICTS["ice"]["uv"])
	ice_center = Vector3(ic.x, ic.y, 0)
	if _road_cache.is_empty():
		_route_roads()
	roads = _road_cache.duplicate(true)
	gates = _gate_cache.duplicate()


func _cell(d: Dictionary, kind: String) -> Vector2:
	if d.has("cell") and d["cell"].has(kind):
		return d["cell"][kind]
	return ArtLib.footprint(kind) + Vector2(GAP, GAP)


func _pack(name: String, d: Dictionary) -> void:
	var row_w: float = d["row_w"]
	var local := []      # [kind, Vector2 중심]
	var y := 0.0
	for pair in d["types"]:
		var kind: String = pair[0]
		var cap: int = pair[1]
		var cell := _cell(d, kind)
		var per_row := maxi(1, int(floor((row_w + 0.01) / cell.x)))
		var x0 := (row_w - per_row * cell.x) * 0.5
		for i in range(cap):
			@warning_ignore("integer_division")
			var r := i / per_row
			var c := i % per_row
			local.append([kind, Vector2(x0 + (c + 0.5) * cell.x, y + (r + 0.5) * cell.y)])
		y += ceili(float(cap) / per_row) * cell.y
	var center := uv_to_xy(d["uv"])
	var origin := center - Vector2(row_w, y) * 0.5
	rects[name] = Rect2(origin, Vector2(row_w, y))
	lots[name] = []
	lanes[name] = []
	for item in local:
		var kind: String = item[0]
		var p: Vector2 = origin + item[1]
		if not slots.has(kind):
			slots[kind] = []
		slots[kind].append(Vector3(p.x, p.y, 0))
		district_of[kind] = name
		var cell := _cell(d, kind)
		lots[name].append(Rect2(p - cell * 0.5 + Vector2(0.5, 0.5), cell - Vector2(1.0, 1.0)))
	# 줄 사이 보행로: 줄이 바뀌는 곳마다 구역을 가로지른다
	var ys := {}
	for r in lots[name]:
		ys[snappedf((r as Rect2).position.y - 0.5, 0.01)] = true
	for yy in ys:
		if yy > origin.y + 0.5:
			lanes[name].append([Vector2(origin.x, yy), Vector2(origin.x + row_w, yy)])


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


# ── 처음 길 ─────────────────────────────────────────────────────
## 가운데(거주구 한가운데 큰길)에서 구역마다의 문까지 직각으로 꺾이는 길을 낸다.
## 후보 선은 가운데·문·구역 가장자리(길 폭만큼 띄운 곳)를 지나는 가로·세로 선이고, 그 교차점 그물에서
## 꺾임이 적고 짧은 길을 찾는다. 먼저 낸 길은 싸게 쳐서 길이 줄기로 모인다. 구역과 능선의 일조 구역은 비켜 간다.
const _CLEAR := ROAD_W * 0.5 + 2.0
const _TURN_M := 30.0


func _route_roads() -> void:
	var h := Vector2(hub.x, hub.y)
	var xs := [h.x]
	var ys := [h.y]
	for d in rects:
		var r: Rect2 = rects[d]
		xs.append_array([r.position.x - _CLEAR, r.end.x + _CLEAR, r.get_center().x])
		ys.append_array([r.position.y - _CLEAR, r.end.y + _CLEAR, r.get_center().y])
	xs = _uniq(xs)
	ys = _uniq(ys)
	var pts: Array = []
	var index := {}
	for iy in ys.size():
		for ix in xs.size():
			var p := Vector2(xs[ix], ys[iy])
			if not _road_blocked(p, h):
				index[Vector2i(ix, iy)] = pts.size()
				pts.append(p)
	var nb: Array = []
	nb.resize(pts.size())
	for i in pts.size():
		nb[i] = []
	for key in index:
		var k: Vector2i = key
		var a: int = index[k]
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var m: Vector2i = k + dir
			while m.x < xs.size() and m.y < ys.size() and not index.has(m):
				m += dir
			if m.x >= xs.size() or m.y >= ys.size():
				continue
			var b: int = index[m]
			if _segment_clear(pts[a], pts[b], h):
				var d := 0 if dir.x == 1 else 1
				nb[a].append([b, d, pts[a].distance_to(pts[b])])
				nb[b].append([a, d + 2, pts[a].distance_to(pts[b])])
	var hub_i: int = index.get(Vector2i(xs.find(h.x), ys.find(h.y)), -1)
	var order := []
	for d in DISTRICTS:
		if d != "core":
			order.append([h.distance_to((rects[d] as Rect2).get_center()), d])
	order.sort_custom(func(a, c): return a[0] < c[0])
	var used := {}
	_gate_cache = {"core": hub}
	_road_cache = []
	for item in order:
		var name: String = item[1]
		var goals := _goal_nodes(rects[name], pts)
		var path: Array = _cheapest(hub_i, goals, pts, nb, used) if hub_i >= 0 else []
		if path.is_empty():
			var g := _gate_fallback(name, h)
			_gate_cache[name] = g
			_road_cache.append(PackedVector3Array([hub, Vector3(g.x, hub.y, 0), g]))
			continue
		for i in range(path.size() - 1):
			used[Vector2i(mini(path[i], path[i + 1]), maxi(path[i], path[i + 1]))] = true
		var end_p: Vector2 = pts[path[-1]]
		_gate_cache[name] = Vector3(end_p.x, end_p.y, 0)
		var line := PackedVector3Array()
		for i in path.size():
			var p: Vector2 = pts[path[i]]
			if i > 0 and i < path.size() - 1:
				var a: Vector2 = pts[path[i - 1]]
				var c: Vector2 = pts[path[i + 1]]
				if (is_equal_approx(a.x, p.x) and is_equal_approx(p.x, c.x)) or (is_equal_approx(a.y, p.y) and is_equal_approx(p.y, c.y)):
					continue
			line.append(Vector3(p.x, p.y, 0))
		if line.size() >= 2:
			_road_cache.append(line)


## 구역의 네 면 바로 바깥(길 폭만큼)에 있는 꼭짓점 중, 면의 가운데쪽(모서리에서 4 m 안쪽)에 있는 것
static func _goal_nodes(r: Rect2, pts: Array) -> Dictionary:
	var goals := {}
	var inner := r.grow(-4.0)
	for i in pts.size():
		var p: Vector2 = pts[i]
		var on_y := is_equal_approx(p.y, r.position.y - _CLEAR) or is_equal_approx(p.y, r.end.y + _CLEAR)
		var on_x := is_equal_approx(p.x, r.position.x - _CLEAR) or is_equal_approx(p.x, r.end.x + _CLEAR)
		if (on_y and p.x >= inner.position.x and p.x <= inner.end.x) or (on_x and p.y >= inner.position.y and p.y <= inner.end.y):
			goals[i] = true
	return goals


static func _uniq(vals: Array) -> Array:
	vals.sort()
	var out := []
	for v in vals:
		if out.is_empty() or absf(float(v) - float(out[-1])) > 0.5:
			out.append(float(v))
	return out


## 다익스트라 — 상태는 (꼭짓점, 들어온 방향). 꺾이면 _TURN_M만큼 더 들고, 이미 난 길(used)은 0.3배.
## 가운데에서 출발해 goals 중 아무 데나 닿으면 끝 (그래서 어느 구역이든 가운데까지 가깝다)
func _cheapest(start: int, goals: Dictionary, pts: Array, nb: Array, used: Dictionary) -> Array:
	var n := pts.size() * 4
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var heap_k := PackedFloat64Array()
	var heap_v := PackedInt32Array()
	for d in 4:
		dist[start * 4 + d] = 0.0
		_push(heap_k, heap_v, 0.0, start * 4 + d)
	var found := -1
	while heap_k.size() > 0:
		var key := heap_k[0]
		var s := _pop(heap_k, heap_v)
		if key > dist[s] + 1e-9:
			continue
		@warning_ignore("integer_division")
		var node := s / 4
		var dir := s % 4
		if goals.has(node):
			found = s
			break
		var fresh := node == start
		for e in nb[node]:
			var m: int = e[0]
			var nd: int = e[1]
			if not fresh and nd == (dir + 2) % 4:
				continue
			var w: float = e[2]
			if used.has(Vector2i(mini(node, m), maxi(node, m))):
				w *= 0.3
			if not fresh and nd != dir:
				w += _TURN_M
			var t := m * 4 + nd
			if dist[s] + w < dist[t]:
				dist[t] = dist[s] + w
				prev[t] = s
				_push(heap_k, heap_v, dist[t], t)
	if found < 0:
		return []
	var path := []
	var cur := found
	while cur >= 0:
		@warning_ignore("integer_division")
		var node_i := cur / 4
		if path.is_empty() or path[0] != node_i:
			path.push_front(node_i)
		cur = prev[cur]
	return path


static func _push(keys: PackedFloat64Array, vals: PackedInt32Array, k: float, v: int) -> void:
	keys.append(k)
	vals.append(v)
	var i := keys.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var p := (i - 1) / 2
		if keys[p] <= keys[i]:
			break
		var tk := keys[p]
		keys[p] = keys[i]
		keys[i] = tk
		var tv := vals[p]
		vals[p] = vals[i]
		vals[i] = tv
		i = p


static func _pop(keys: PackedFloat64Array, vals: PackedInt32Array) -> int:
	var top := vals[0]
	var last := keys.size() - 1
	keys[0] = keys[last]
	vals[0] = vals[last]
	keys.resize(last)
	vals.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and keys[l] < keys[m]:
			m = l
		if r < last and keys[r] < keys[m]:
			m = r
		if m == i:
			break
		var tk := keys[m]
		keys[m] = keys[i]
		keys[i] = tk
		var tv := vals[m]
		vals[m] = vals[i]
		vals[i] = tv
		i = m
	return top


func _road_blocked(p: Vector2, h: Vector2) -> bool:
	var uv := xy_to_uv(p)
	if not BOUNDS_UV.grow(-4.0).has_point(uv) or uv.y < CREST_V + 3.0:
		return true
	for t in ZONES:
		for r in ZONES[t]:
			if (r as Rect2).grow(3.0).has_point(uv):
				return true
	for d in rects:
		if (rects[d] as Rect2).grow(ROAD_W * 0.5 + 0.6).has_point(p):
			if d == "core" and absf(p.y - h.y) < 0.1:
				continue        # 거주구 한가운데를 지나는 큰길 (모듈 두 줄 사이)
			return true
	return false


func _segment_clear(a: Vector2, b: Vector2, h: Vector2) -> bool:
	var n := maxi(1, int(ceil(a.distance_to(b))))
	for i in range(n + 1):
		if _road_blocked(a.lerp(b, float(i) / n), h):
			return false
	return true


## 길을 찾지 못한 구역의 문: 가운데를 향한 가장자리 한가운데에서 길 폭만큼 바깥
func _gate_fallback(name: String, h: Vector2) -> Vector3:
	var r: Rect2 = rects[name]
	var g: Vector2
	if h.y < r.position.y:
		g = Vector2(r.get_center().x, r.position.y - _CLEAR)
	elif h.y > r.end.y:
		g = Vector2(r.get_center().x, r.end.y + _CLEAR)
	elif h.x < r.position.x:
		g = Vector2(r.position.x - _CLEAR, h.y)
	else:
		g = Vector2(r.end.x + _CLEAR, h.y)
	return Vector3(g.x, g.y, 0)


func capacity(kind: String) -> int:
	if kind == "solar_tower":
		return tower_slots.size()
	return slots.get(kind, []).size()


func slot(kind: String, i: int) -> Vector3:
	if kind == "solar_tower":
		return tower_slots[i][0]
	return slots[kind][i]
