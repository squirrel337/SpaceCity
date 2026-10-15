class_name LayoutData
extends RefCounted
## 도시의 길과 구획 자료 (data/city_layout.json): 길 종류, 블록의 용도(구획), 기본 길 격자, 땅 고치기.

static var data := {}


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
