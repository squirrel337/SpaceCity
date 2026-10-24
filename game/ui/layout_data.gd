class_name LayoutData
extends RefCounted
## 도시의 길과 구획 자료 (data/city_layout.json): 길 종류, 블록의 용도(구획), 기본 길 격자, 땅 고치기.

static var data := {}
static var _up: Array = []           # 높은 길 종류 (raised_types)
static var _up_ready := false


static func load_all() -> void:
	if not data.is_empty():
		return
	var f := FileAccess.open("res://data/city_layout.json", FileAccess.READ)
	if f == null:
		push_error("city_layout.json을 읽지 못했다")
		return
	data = JSON.parse_string(f.get_as_text())


## 길 종류 하나 (없는 이름이면 도로)
static func road(type: String) -> Dictionary:
	load_all()
	var r: Dictionary = data["roads"]
	return r.get(type, r["street"])


static func road_name(type: String) -> String:
	return String(road(type)["name"])


static func road_half(type: String) -> float:
	return float(road(type)["width_m"]) * 0.5


## 높은 길의 갈래: "" 땅 위의 길, "viaduct" 고가 (땅을 따라 덱 높이로 뜬다), "bridge" 다리 (두 끝 사이를 곧게 건넌다)
static func level(type: String) -> String:
	return String(road(type).get("level", ""))


static func raised(type: String) -> bool:
	return raised_types().has(type)


## 높은 길 종류들 (자료 순서) — 길마다 자주 묻는 것이라 처음 한 번만 모은다
static func raised_types() -> Array:
	if not _up_ready:
		load_all()
		_up_ready = true
		_up.clear()
		for t in data["roads"]:
			if String(data["roads"][t].get("level", "")) != "":
				_up.append(t)
	return _up


## 덱의 겉모습 (셰이더의 길 무늬) — 땅 위의 길은 그 이름 그대로
static func look(type: String) -> String:
	return String(road(type).get("look", type))


## 길 종류의 묶음 (길 도구의 단추 줄): ground · viaduct · bridge
static func road_group(type: String) -> String:
	var lv := level(type)
	return "ground" if lv == "" else lv


## 이 천체에서 낼 수 있는 길 종류 (자료 순서)
static func road_types(body: String) -> Array:
	load_all()
	var out := []
	for k in data["roads"]:
		var bodies: Array = data["roads"][k].get("bodies", [])
		if bodies.is_empty() or body in bodies:
			out.append(k)
	return out


## 길 하나의 자재 (길이 m)
static func road_cost(type: String, length_m: float) -> Dictionary:
	var out := {}
	var c: Dictionary = road(type).get("cost_per_100m", {})
	for k in c:
		out[k] = float(c[k]) * length_m / 100.0
	return out


static func zones() -> Dictionary:
	load_all()
	return data["zones"]


static func zone(key: String) -> Dictionary:
	return zones().get(key, {})


static func zone_color(key: String) -> Color:
	var z := zone(key)
	return Color(String(z.get("color", "aab3c8")))


static func zone_name(key: String) -> String:
	return String(zone(key).get("name", "빈 블록"))


static func grid() -> Dictionary:
	load_all()
	return data["grid"]


static func terrain() -> Dictionary:
	load_all()
	return data["terrain"]


## 땅 구역 사기 (기지 넓히기)
static func land() -> Dictionary:
	load_all()
	return data["land"]


## 재건축 규칙 (자동 운영 식민지)
static func redevelop() -> Dictionary:
	load_all()
	return data.get("redevelop", {})


## 도시 발전 모드 (자동 운영 식민지): '' = 균형, 그다음 열 가지 (자료 순서)
static func dev_modes() -> Dictionary:
	load_all()
	return data.get("dev_modes", {})


## 방향 하나 (없는 이름이면 균형)
static func dev_mode(id: String) -> Dictionary:
	var m := dev_modes()
	return m.get(id, m.get("", {}))
