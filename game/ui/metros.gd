class_name Metros
extends RefCounted
## 지구의 대도시 (data/earth_cities.json) — 3D 지도의 점과 이름, 밤의 불빛, 가까이 가면 보이는 실제 축척의 시가지,
## 가장 가까운 우주항으로 가는 항공편. 시뮬레이션하는 식민지가 아니다: 정착민과 부품을 우주항에 보내는 곳이다.
## 교통 노선과 3D 지도에서 대도시의 id는 "metro_" + 데이터의 id (부지 id와 겹치지 않게).
## 같은 자료에 대도시 운영 방식(modes)·연구 동맹 기술(alliance)·상업과 금융(economy, cities[].districts)과
## 반도체·AI 데이터센터 지역(tech_regions — id는 "tech_" + 데이터의 id, 교통의 마디가 아니다)이 있다.

const PATH := "res://data/earth_cities.json"
const PREFIX := "metro_"
const REGION_PREFIX := "tech_"
const MODE_IDS := ["parts_capital", "research_alliance", "emergency_depot"]

static var list: Array = []          # [대도시] (데이터 순서) — 항목에 key(노선 id)와 dir(몸체 고정 단위 벡터)를 더한다
static var by_key := {}              # "metro_seoul" → 대도시
static var styles := {}
static var routes: Array = []        # 대도시 사이의 국제선 [[key, key]]
static var functions := {}           # 대도시의 우주 시설 (MetroFunctions가 쓴다)
static var modes := {}               # 운영 방식 (MetroModes가 쓴다)
static var mode_rules := {}
static var alliance := {}            # 연구 동맹만 여는 기술
static var economy := {}             # 상업·금융 (MetroEconomy가 쓴다)
static var tech_kinds := {}
static var tech_bonus := {}
static var regions: Array = []       # 반도체·AI 데이터센터 지역 — 항목에 key, dir, radius_km, near_key·near_km, in_metro를 더한다
static var region_by_key := {}
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
	modes = data.get("modes", {})
	mode_rules = data.get("mode_rules", {})
	alliance = data.get("alliance", {})
	economy = data.get("economy", {})
	tech_kinds = data.get("tech_kinds", {})
	tech_bonus = data.get("tech_bonus", {})
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
	# 첨단 산업 지역: 대도시 시가지처럼 3D 땅을 쓴다 (반지름 = 단지 지름의 반, 지역 지도의 반 폭 = 반지름 + 10 km).
	# 대도시 시가지 지도 안에 들면 (장장·싱가포르 북부) 그 대도시의 3D 땅에 단지를 짓는다
	for r in data.get("tech_regions", []):
		var e2: Dictionary = r
		e2["key"] = REGION_PREFIX + String(e2["id"])
		e2["dir"] = Astro.latlon(float(e2["lat"]), float(e2["lon"]))
		e2["radius_km"] = float(e2.get("size_km", 6.0)) * 0.5
		var near := nearest(e2["dir"])
		e2["near_key"] = String(near.get("key", ""))
		e2["near_km"] = km_between(e2["dir"], near["dir"]) if not near.is_empty() else INF
		e2["in_metro"] = ""
		if not near.is_empty() and float(e2["near_km"]) + float(e2["radius_km"]) < float(near["radius_km"]) + 9.0:
			e2["in_metro"] = String(near["key"])
		regions.append(e2)
		region_by_key[e2["key"]] = e2


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


## 도시권 인구의 배수: √(인구/1000만)을 0.6~1.8로 (시설·상권의 크기)
static func popscale(key: String) -> float:
	return clampf(sqrt(float(of(key).get("pop_m", 10.0)) / 10.0), 0.6, 1.8)


## 그 대도시의 실제 금융가·상권 [[이름, 종류(finance·commerce), 위도, 경도, 무게]]
static func districts_of(key: String, kind: String = "") -> Array:
	var out: Array = []
	for d in of(key).get("districts", []):
		if kind == "" or String(d[1]) == kind:
			out.append(d)
	return out


static func mode_def(id: String) -> Dictionary:
	load_all()
	return modes.get(id, {})


static func mode_name(id: String) -> String:
	return String(mode_def(id).get("name", "직접 운영")) if id != "" else "직접 운영"


static func mode_color(id: String) -> Color:
	return Color(String(mode_def(id).get("color", "aab3c8")))


# ── 첨단 산업 지역 ────────────────────────────────────────────────
static func is_region(key: String) -> bool:
	return key.begins_with(REGION_PREFIX)


static func region(key: String) -> Dictionary:
	load_all()
	return region_by_key.get(key, {})


## 이 방향에서 가장 가까운 지역 (standalone: 대도시 땅 안에 지어지는 지역은 빼고)
static func nearest_region(dir: Vector3, max_km: float = INF, standalone := true) -> Dictionary:
	load_all()
	var best := {}
	var best_km := max_km
	for r in regions:
		if standalone and String(r["in_metro"]) != "":
			continue
		var km := km_between(dir, r["dir"])
		if km < best_km:
			best_km = km
			best = r
	return best


## 그 대도시의 땅 안에 지어지는 지역들
static func regions_in(metro_key: String) -> Array:
	load_all()
	return regions.filter(func(r: Dictionary) -> bool: return String(r["in_metro"]) == metro_key)


static func kind_name(kind: String) -> String:
	load_all()
	return String(tech_kinds.get(kind, {}).get("name", kind))


static func kind_group(kind: String) -> String:
	load_all()
	return String(tech_kinds.get(kind, {}).get("group", ""))


## "메모리 · 파운드리"
static func kinds_text(r: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in r.get("kinds", []):
		bits.append(kind_name(String(k)))
	return " · ".join(bits)


## 지역의 대표 색 (첫 종류의 묶음 색: 반도체 하늘색 · 칩 설계 초록 · 데이터센터 보라)
static func region_color(r: Dictionary) -> Color:
	load_all()
	var ks: Array = r.get("kinds", [])
	if ks.is_empty():
		return Color("aab3c8")
	return Color(String(tech_kinds.get(String(ks[0]), {}).get("color", "aab3c8")))


static func has_group(r: Dictionary, group: String) -> bool:
	for k in r.get("kinds", []):
		if kind_group(String(k)) == group:
			return true
	return false
