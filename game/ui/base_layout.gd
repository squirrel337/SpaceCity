class_name BaseLayout
extends RefCounted
## 기지 배치 — 건물 종류마다 자리를 미리 정해 둔다.
## 좌표는 미터. x는 화면 오른쪽 아래, y는 왼쪽 아래로 간다. 구역 중심은 화면 기준(u: 오른쪽, v: 아래)으로 적는다.
## 개수가 늘어도 이미 선 건물이 움직이지 않도록 종류별 자리 수(용량)를 고정한다.

const SQ := 0.7071067811865476
const ROAD_W := 5.0

## 구역: uv 중심, 줄 너비(x 방향, m), [종류, 자리 수], 칸 크기를 바꿀 종류
const DISTRICTS := {
	"core": {"uv": Vector2(-20, -15), "row_w": 84.0, "types": [["hab_module", 36]], "cell": {"hab_module": Vector2(14, 10)}},
	"civic": {"uv": Vector2(92, -2), "row_w": 60.0, "types": [["green_commons", 3], ["research_lab", 8], ["medical_bay", 4], ["comms_center", 2]]},
	"domes": {"uv": Vector2(-108, -62), "row_w": 54.0, "types": [["regolith_dome", 6], ["storm_shelter", 6]]},
	"life": {"uv": Vector2(2, -122), "row_w": 46.0, "types": [["electrolyzer", 6], ["co2_scrubber", 8], ["sabatier", 3], ["water_recycler", 6], ["tank_farm", 6]]},
	"power": {"uv": Vector2(118, -112), "row_w": 60.0, "types": [["battery_bank", 16], ["rfc_unit", 40], ["radiator", 20]]},
	"farm": {"uv": Vector2(-122, 58), "row_w": 72.0, "types": [["hydroponics", 40], ["algae_reactor", 8], ["food_store", 6]]},
	"industry": {"uv": Vector2(88, 108), "row_w": 60.0, "types": [["robot_bay", 3], ["parts_fab", 4], ["excavator", 2], ["regolith_printer", 2], ["mre_plant", 3], ["propellant_plant", 2]]},
	"reactor": {"uv": Vector2(-112, 180), "row_w": 46.0, "types": [["fission_40kw", 12], ["fission_1mw", 3]]},
	"ice": {"uv": Vector2(-140, -152), "row_w": 46.0, "types": [["ice_miner", 3]]},
	"pad": {"uv": Vector2(142, 208), "row_w": 76.0, "types": [["landing_pad", 2]]},
}
const GAP := 3.0
const BOUNDS_UV := Rect2(-235, -262, 470, 530)      # 지도 끝 (u, v)
const CREST_V := -214.0                               # 능선 마루 (그 위는 하늘)
const ICE_CRATER_R := 34.0

var slots := {}            # 종류 → Array[Vector3] (자리 중심, 채우는 순서)
var district_of := {}      # 종류 → 구역 이름
var rects := {}            # 구역 → Rect2 (월드 x·y)
var gates := {}            # 구역 → Vector3 (길이 닿는 구역 가장자리)
var hub := Vector3.ZERO
var roads: Array = []      # Array[PackedVector3Array]
var tower_slots: Array = []   # [Vector3, "A"|"B"|"C"]
var ice_center := Vector3.ZERO


static func uv_to_xy(uv: Vector2) -> Vector2:
	return Vector2((uv.x + uv.y) * SQ, (uv.y - uv.x) * SQ)


static func xy_to_uv(xy: Vector2) -> Vector2:
	return Vector2((xy.x - xy.y) * SQ, (xy.x + xy.y) * SQ)


func _init() -> void:
	for d in DISTRICTS:
		_pack(d, DISTRICTS[d])
	var core: Rect2 = rects["core"]
	hub = Vector3(core.get_center().x, core.get_center().y, 0)
	for d in DISTRICTS:
		gates[d] = _gate(d)
	for d in DISTRICTS:
		if d == "core":
			continue
		var g: Vector3 = gates[d]
		roads.append(PackedVector3Array([hub, Vector3(g.x, hub.y, 0), g]))
	_towers()
	var ic := uv_to_xy(DISTRICTS["ice"]["uv"])
	ice_center = Vector3(ic.x, ic.y, 0)


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
	for item in local:
		var kind: String = item[0]
		var p: Vector2 = origin + item[1]
		if not slots.has(kind):
			slots[kind] = []
		slots[kind].append(Vector3(p.x, p.y, 0))
		district_of[kind] = name


func _gate(name: String) -> Vector3:
	## 큰길(y = hub.y)에서 구역으로 들어가는 자리: 구역의 가까운 가장자리 한가운데
	var r: Rect2 = rects[name]
	var cx := r.get_center().x
	if name == "core":
		return hub
	if hub.y < r.position.y:
		return Vector3(cx, r.position.y - 3.0, 0)
	if hub.y > r.end.y:
		return Vector3(cx, r.end.y + 3.0, 0)
	# 큰길이 구역을 지나면 x 쪽 가장자리에서 멈춘다
	var gx := r.position.x - 3.0 if hub.x < r.position.x else r.end.x + 3.0
	return Vector3(gx, hub.y, 0)


func _towers() -> void:
	## 능선의 태양광 타워 자리. A: 마루 한가운데(일조 100%), B: 양옆(85%), C: 낮은 비탈 두 줄(70%)
	var pts := []
	for i in range(8):
		pts.append([Vector2(-38.5 + i * 11.0, CREST_V + 10.0), "A"])
	for side in [-1, 1]:
		for i in range(5):
			pts.append([Vector2(side * (56.0 + i * 11.0), CREST_V + 15.0), "B"])
	for side in [-1, 1]:
		for row in range(2):
			for i in range(5):
				pts.append([Vector2(side * (118.0 + i * 11.0 + row * 5.5), CREST_V + 24.0 + row * 10.0), "C"])
	# 채우는 순서: A → B(가운데에서 바깥) → C
	var order := []
	for t in ["A", "B", "C"]:
		var group := pts.filter(func(p): return p[1] == t)
		group.sort_custom(func(a, b): return absf(a[0].x) < absf(b[0].x))
		order.append_array(group)
	for p in order:
		var xy := uv_to_xy(p[0])
		tower_slots.append([Vector3(xy.x, xy.y, 0), p[1]])


## A 구역 문에서 B 구역 문까지: 큰길을 따라 간다 (모든 꺾임이 x·y 축을 따른다)
func route(from: Vector3, to: Vector3) -> Array:
	var path := []
	if absf(from.y - hub.y) > 0.5:
		path.append(Vector3(from.x, hub.y, 0))
	if absf(to.x - from.x) > 0.5:
		path.append(Vector3(to.x, hub.y, 0))
	path.append(to)
	return path


## 구역 안의 한 자리까지: 문 → 자리 앞 (x 먼저, 그다음 y)
func route_into(gate: Vector3, spot: Vector3) -> Array:
	return [Vector3(spot.x, gate.y, 0), spot]


func capacity(kind: String) -> int:
	if kind == "solar_tower":
		return tower_slots.size()
	return slots.get(kind, []).size()


func slot(kind: String, i: int) -> Vector3:
	if kind == "solar_tower":
		return tower_slots[i][0]
	return slots[kind][i]
