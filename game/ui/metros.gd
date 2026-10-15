class_name Metros
extends RefCounted
## 지구의 대도시 (data/earth_cities.json) — 3D 지도의 점과 이름, 밤의 불빛, 가까이 가면 보이는 실제 축척의 시가지,
## 가장 가까운 우주항으로 가는 항공편. 시뮬레이션하는 식민지가 아니다: 정착민과 부품을 우주항에 보내는 곳이다.
## 교통 노선과 3D 지도에서 대도시의 id는 "metro_" + 데이터의 id (부지 id와 겹치지 않게).

const PATH := "res://data/earth_cities.json"
const PREFIX := "metro_"

static var list: Array = []          # [대도시] (데이터 순서) — 항목에 key(노선 id)와 dir(몸체 고정 단위 벡터)를 더한다
static var by_key := {}              # "metro_seoul" → 대도시
static var styles := {}
static var routes: Array = []        # 대도시 사이의 국제선 [[key, key]]
static var functions := {}           # 대도시의 우주 시설 (MetroFunctions가 쓴다)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("대도시 자료를 읽지 못했다: " + PATH)
		return
	styles = data.get("styles", {})
	functions = data.get("functions", {})
	for m in data.get("cities", []):
		var e: Dictionary = m
		e["key"] = PREFIX + String(e["id"])
		e["dir"] = Astro.latlon(float(e["lat"]), float(e["lon"]))
		list.append(e)
		by_key[e["key"]] = e
	for pair in data.get("air_routes", []):
		var a := PREFIX + String(pair[0])
		var b := PREFIX + String(pair[1])
		if by_key.has(a) and by_key.has(b):
			routes.append([a, b])


static func is_metro(key: String) -> bool:
	return key.begins_with(PREFIX)


static func of(key: String) -> Dictionary:
	load_all()
	return by_key.get(key, {})


static func style_of(m: Dictionary) -> Dictionary:
	load_all()
	return styles.get(String(m.get("style", "dense")), styles.get("dense", {}))


## 그 도시의 강점 시설 이름 ("" = 없음)
static func strength_name(m: Dictionary) -> String:
	load_all()
	return String(functions.get(String(m.get("strength", "")), {}).get("name", ""))


## "도시권 2,600만"
static func pop_text(m: Dictionary) -> String:
	return "도시권 %s만" % Fmt.n(roundf(float(m.get("pop_m", 0.0)) * 100.0))


## 두 방향 사이의 지구 표면 거리 (km)
static func km_between(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)) * 6371.0


## 이 방향에서 가장 가까운 대도시 (없으면 {})
static func nearest(dir: Vector3, max_km: float = INF) -> Dictionary:
	load_all()
	var best := {}
	var best_km := max_km
	for m in list:
		var km := km_between(dir, m["dir"])
		if km < best_km:
			best_km = km
			best = m
	return best
