class_name GameData
## 시대 0 데이터. docs/design/data/*.json의 사본을 읽는다 — 사본이 같은지는 tools/sync_data.py가 확인한다.
## JSON의 숫자는 모두 실수로 읽힌다.

const MODULES_PATH := "res://data/city_modules.json"
const TECHS_PATH := "res://data/city_techs.json"

static var C: Dictionary = {}
static var MODULES: Dictionary = {}   # id -> 모듈 (JSON 순서 유지)
static var TECHS: Dictionary = {}     # id -> 기술 (JSON 순서 유지)
static var FAMILY: Dictionary = {}    # 계열(기본 모듈 id) -> [모듈 id] (데이터 순서, 기본 모듈이 맨 앞)
static var FAM_OF: Dictionary = {}    # 모듈 id -> 계열
static var WITH: Dictionary = {}      # provides 열쇠 -> 그 값이 0이 아닌 모듈 id (데이터 순서) — 시뮬레이션의 합을 빨리
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	var modules_json: Dictionary = _read(MODULES_PATH)
	C = modules_json["constants"]
	for m in modules_json["modules"]:
		MODULES[m["id"]] = m
	for mid in MODULES:
		var fam := family(mid)
		FAM_OF[mid] = fam
		if not FAMILY.has(fam):
			FAMILY[fam] = []
		FAMILY[fam].append(mid)
		var pv: Dictionary = MODULES[mid].get("provides", {})
		for key in pv:
			if pv[key]:
				if not WITH.has(key):
					WITH[key] = []
				WITH[key].append(mid)
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


## 모듈의 계열 (기본 모듈 29종의 id). 계열이 같으면 같은 규칙에 들어가고, 수치는 저마다 다르다
static func family(mid: String) -> String:
	if MODULES.has(mid):
		return String(MODULES[mid].get("family", mid))
	return mid


static func module_name(mid: String) -> String:
	if mid == "regolith_cover":
		return "레골리스 피복"
	if mid == "robot":
		return "건설 로봇"
	return MODULES[mid]["name"]
