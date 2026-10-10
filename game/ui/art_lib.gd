class_name ArtLib
extends RefCounted
## game/art의 건물·탈것 그림과 크기 정보(art.json).
## 그림은 tools/art/make_art.py가 1 m = 8 px로 그린 SVG를 Godot가 2배로 래스터화한 것이다.
## 텍스처는 처음 쓸 때 불러 둔다.

const ROOT := "res://art/"
const PX_PER_M := 8.0
const C1 := 0.7071067811865476 * PX_PER_M     # x·y → 화면 가로
const C2 := 0.35355339059327373 * PX_PER_M    # x·y → 화면 세로 (바닥 2:1)
const C3 := 0.8660254037844386 * PX_PER_M     # 높이 → 화면 세로

static var _meta: Dictionary = {}
static var _tex: Dictionary = {}


static func meta() -> Dictionary:
	if _meta.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "art.json"))
		_meta = parsed if parsed is Dictionary else {"buildings": {}, "vehicles": {}}
	return _meta


## 월드 좌표(m) → 지도 좌표(SVG 1배 px)
static func project(p: Vector3) -> Vector2:
	return Vector2((p.x - p.y) * C1, (p.x + p.y) * C2 - p.z * C3)


## 지도 좌표 → 바닥(z=0) 월드 좌표
static func unproject(mp: Vector2) -> Vector3:
	var a := mp.x / C1          # x - y
	var b := mp.y / C2          # x + y
	return Vector3((a + b) * 0.5, (b - a) * 0.5, 0.0)


static func has(group: String, id: String) -> bool:
	return meta().get(group, {}).has(id)


## 그림 정보: file(확장자 없는 상대 경로), px(1배 크기), anchor(원점의 위치), lights
static func info(group: String, id: String, heading: String = "se") -> Dictionary:
	var m: Dictionary = meta().get(group, {}).get(id, {})
	if m.is_empty():
		return {}
	var v: Dictionary = m
	var file := "%s/%s" % [group, id]
	if m.has("views"):
		var views: Dictionary = m["views"]
		var hd := heading if views.has(heading) else "se"
		v = views[hd]
		file = "%s/%s_%s" % [group, id, hd]
	return {
		"file": file,
		"px": Vector2(v["px"][0], v["px"][1]),
		"anchor": Vector2(v["anchor"][0], v["anchor"][1]),
		"lights": bool(v.get("lights", false)),
	}


## 건물 바닥 크기 [가로(x), 세로(y)] m와 대표 높이
static func footprint(id: String) -> Vector2:
	var m: Dictionary = meta().get("buildings", {}).get(id, {})
	if m.has("foot"):
		return Vector2(m["foot"][0], m["foot"][1])
	return Vector2(6, 6)


static func height(id: String) -> float:
	return float(meta().get("buildings", {}).get(id, {}).get("height", 4.0))


static func title(group: String, id: String) -> String:
	return String(meta().get(group, {}).get(id, {}).get("title", id))


static func texture(file: String, lights: bool = false) -> Texture2D:
	var key := file + ("_lights" if lights else "")
	if not _tex.has(key):
		var path := ROOT + key + ".svg"
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]
