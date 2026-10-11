class_name ArtLib
extends RefCounted
## 건물·탈것의 크기 정보 (art/art.json): 바닥 크기, 높이, 모양(변형) 수, 이름.
## 모양 자체는 tools/art/make_art.py가 같은 그림 코드로 적은 3D 모형(art/models.json, ModelLib)이다.

const ROOT := "res://art/"

static var _meta: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "art.json"))
		_meta = parsed if parsed is Dictionary else {"buildings": {}, "vehicles": {}}
	return _meta


static func has(group: String, id: String) -> bool:
	return meta().get(group, {}).has(id)


## 모양 수 (건물마다 다섯 가지)
static func variants(id: String) -> int:
	var m: Dictionary = meta().get("buildings", {}).get(id, {})
	return m["variants"].size() if m.has("variants") else 1


## 건물 바닥 크기 [가로(x), 세로(y)] m
static func footprint(id: String) -> Vector2:
	var m: Dictionary = meta().get("buildings", {}).get(id, {})
	if m.has("foot"):
		return Vector2(m["foot"][0], m["foot"][1])
	return Vector2(6, 6)


## 대표 높이 (m). v를 주면 그 모양의 높이
static func height(id: String, v: int = -1) -> float:
	var m: Dictionary = meta().get("buildings", {}).get(id, {})
	if v >= 0 and m.has("variants"):
		var vs: Array = m["variants"]
		return float(vs[clampi(v, 0, vs.size() - 1)].get("height", m.get("height", 4.0)))
	return float(m.get("height", 4.0))


static func title(group: String, id: String) -> String:
	return String(meta().get(group, {}).get(id, {}).get("title", id))
