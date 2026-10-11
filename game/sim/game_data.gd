class_name GameData
## 시대 0 데이터. docs/design/data/*.json의 사본을 읽는다 — 사본이 같은지는 tools/sync_data.py가 확인한다.
## JSON의 숫자는 모두 실수로 읽힌다.

const MODULES_PATH := "res://data/city_modules.json"
const TECHS_PATH := "res://data/city_techs.json"
const SITES_PATH := "res://data/city_sites.json"
const HOME_SITE := "moon_shackleton"           # 시대 0의 시작 부지

static var C: Dictionary = {}
static var MODULES: Dictionary = {}   # id -> 모듈 (JSON 순서 유지)
static var TECHS: Dictionary = {}     # id -> 기술 (JSON 순서 유지)
static var FAMILY: Dictionary = {}    # 계열(기본 모듈 id) -> [모듈 id] (데이터 순서, 기본 모듈이 맨 앞)
static var FAM_OF: Dictionary = {}    # 모듈 id -> 계열
static var WITH: Dictionary = {}      # provides 열쇠 -> 그 값이 0이 아닌 모듈 id (데이터 순서) — 시뮬레이션의 합을 빨리
static var SITES: Dictionary = {}     # 부지 id -> 부지 (JSON 순서: 달 시드 시티가 맨 앞)
static var _site_c: Dictionary = {}   # 부지 id -> 합친 도시 상수
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
	var sites_json: Dictionary = _read(SITES_PATH)
	for s in sites_json.get("sites", []):
		SITES[s["id"]] = s
	_loaded = true


## 부지의 도시 상수: 기본 상수에 부지 값을 깊게 덮어쓴 것 (달 시드 시티는 기본 상수 그대로) — 파이썬 site_constants와 같다
static func site_constants(site_id: String) -> Dictionary:
	load_all()
	var over: Dictionary = SITES.get(site_id, {}).get("constants", {})
	if over.is_empty():
		return C
	if not _site_c.has(site_id):
		_site_c[site_id] = merged(C, over)
	return _site_c[site_id]


## 사전을 깊게 합친다 (over가 이긴다, 열쇠 순서는 base 다음 새 열쇠) — 파이썬 merged와 같다
static func merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		if over[k] is Dictionary and base.get(k) is Dictionary:
			out[k] = merged(base[k], over[k])
		else:
			out[k] = over[k]
	return out


static func site(site_id: String) -> Dictionary:
	load_all()
	return SITES.get(site_id, {})


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
