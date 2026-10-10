class_name GameData
## 시대 0 데이터. docs/design/data/*.json의 사본을 읽는다 — 사본이 같은지는 tools/sync_data.py가 확인한다.
## JSON의 숫자는 모두 실수로 읽힌다.

const MODULES_PATH := "res://data/city_modules.json"
const TECHS_PATH := "res://data/city_techs.json"

static var C: Dictionary = {}
static var MODULES: Dictionary = {}   # id -> 모듈 (JSON 순서 유지)
static var TECHS: Dictionary = {}     # id -> 기술 (JSON 순서 유지)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	var modules_json: Dictionary = _read(MODULES_PATH)
	C = modules_json["constants"]
	for m in modules_json["modules"]:
		MODULES[m["id"]] = m
	var techs_json: Dictionary = _read(TECHS_PATH)
	for t in techs_json["techs"]:
		TECHS[t["id"]] = t
	_loaded = true


static func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("데이터를 읽지 못했다: " + path)
		return {}
	return data


static func module_name(mid: String) -> String:
	if mid == "regolith_cover":
		return "레골리스 피복"
	if mid == "robot":
		return "건설 로봇"
	return MODULES[mid]["name"]
