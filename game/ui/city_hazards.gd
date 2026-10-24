class_name CityHazards
extends RefCounted
## 위치가 있는 재난 (자료: data/city_hazards.json의 hazards). 시뮬레이션 밖의 규칙이다 — 모든 도시에.
## 날마다 그 천체의 재난마다 per_year ÷ 365의 확률로 (도시·날로 정해지는 난수) 도시 어딘가에 일어난다:
##   점(운석·화재·압력 누출): 지어진 건물 하나를 가운데로 (운석은 열에 넷이 빈 땅) 반지름 안
##   줄(월진·먼지 회오리): 건물 하나를 지나는 아무 방향의 줄 — 그 폭 안
## 그 안의 건물마다 break_p의 확률로 고장 난다 (시뮬레이션의 고장 — 로봇이 부품을 들여 고친다). 부서진 건물은 그 종류의 맨 뒤로
## 옮겨 3D에 고장 표지가 그 건물에 붙는다. 운석은 땅에 구덩이를 남긴다. 흔적(scars)은 배치 계획에 남아 3D에 잠깐 보인다

const KEEP_SCARS := 12


static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_hazards.json"))
		_data = parsed if parsed is Dictionary else {"hazards": [], "explore": {}}
	return _data


static func hazard(id: String) -> Dictionary:
	for h in data()["hazards"]:
		if String(h["id"]) == id:
			return h
	return {}


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시). 일어난 재난의 id들
static func step(c: Dictionary, day: int) -> Array:
	var sim: CitySim = c["sim"]
	var body := String(GameData.site(sim.site_id).get("body", "moon"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, day, "hazard"])
	var out: Array = []
	for h in data()["hazards"]:
		var bodies: Array = h.get("bodies", ["*"])
		if not ("*" in bodies or body in bodies):
			continue
		if rng.randf() < float(h["per_year"]) / 365.0:
			if strike(c, String(h["id"]), rng):
				out.append(String(h["id"]))
	return out


## 재난 하나: 자리를 고르고, 그 안의 건물을 고장 내고, 흔적을 남긴다. 일어났으면 true (도시에 건물이 없으면 false)
static func strike(c: Dictionary, id: String, rng: RandomNumberGenerator) -> bool:
	var h := hazard(id)
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var built: Array = []
	for e in plan.buildings:
		if int(e["seq"]) < 0 and (not h.get("people", false) or CityPlan._people(String(e["id"]))):
			built.append(e)
	if h.is_empty() or built.is_empty():
		return false
	var target: Dictionary = built[rng.randi() % built.size()]
	var at := Vector2(float(target["x"]), float(target["y"]))
	var a := at
	var b := at
	var r := 0.0
	if String(h.get("shape", "point")) == "line":
		var ang := rng.randf() * TAU
		var half := float(h["length_m"]) * 0.5
		var d := Vector2(cos(ang), sin(ang))
		a = at - d * half
		b = at + d * half
		r = float(h["width_m"]) * 0.5
	else:
		var rr: Array = h.get("radius_m", [10, 20])
		r = rng.randf_range(float(rr[0]), float(rr[1]))
		if id == "meteor" and rng.randf() < 0.4:
			at += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * r * 3.0      # 빈 땅에 가깝게
		a = at
		b = at
	var hit: Array = []
	for e in built:
		var er := plan.entry_rect(e)
		if CityPlan._seg_rect_dist(a, b, er) <= r and rng.randf() < float(h.get("break_p", 1.0)):
			hit.append(e)
	var names := PackedStringArray()
	var broke := 0
	for e in hit:
		var mid := String(e["id"])
		if int(sim.broken.get(mid, 0)) >= int(sim.counts.get(mid, 0)):
			continue                                 # 그 종류가 이미 다 고장 났다
		sim.broken[mid] = int(sim.broken.get(mid, 0)) + 1
		plan.move_to_end(int(e["uid"]))
		broke += 1
		if names.size() < 3:
			names.append(GameData.module_name(mid))
	if broke > 0:
		sim.refresh()
	if h.get("crater", false):
		plan.crater(at, r * 0.6, float(h.get("crater_m", 2.0)))
	plan.scars.append({"kind": id, "a": a, "b": b, "r": r, "hour": sim.hour})
	while plan.scars.size() > KEEP_SCARS:
		plan.scars.pop_front()
	plan._touch()
	var what := ("건물 %d채가 부서졌다 (%s%s) — 로봇이 고친다" % [broke, ", ".join(names), " …" if broke > names.size() else ""]) \
		if broke > 0 else "부서진 건물은 없다"
	sim.note("재난 — %s (%s): %s. %s" % [String(h["name"]), plan.where_text(at), String(h.get("text", "")), what], "warn")
	return true
