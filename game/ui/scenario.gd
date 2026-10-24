class_name Scenario
extends RefCounted
## 시나리오·도전 모드 (자료: data/scenarios.json). 시뮬레이션 밖의 규칙이다.
## 새 게임에서 고르면 그 시드로 시작하고 규칙(rules)을 건다. 날마다 목표(goals)를 살핀다 —
##   이룰 목표(pop·city_pop·total_pop·era·contracts·finds·mega·cities·techs): 한 번 이루면 이룬 것으로 남는다
##   지킬 목표(deaths 최대 · trust 최소): 어기면 그 자리에서 진다
## 이룰 목표를 다 이루면 이기고 (점수·날수를 기록 — user://records.json에 시나리오마다 가장 좋은 것), 기한이 지나면 진다.
## 상태는 Colonies.scenario: {id, start(시간), done: {목표 번호: 이룬 시간}, result: ""·won·lost, why, score, end} — 저장된다

static var records_path := "user://records.json"   # 이긴 기록 (시험은 다른 파일을 쓴다)
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios.json"))
		_data = parsed if parsed is Dictionary else {"scenarios": [], "score": {}}
	return _data


static func find(id: String) -> Dictionary:
	for s in data()["scenarios"]:
		if String(s["id"]) == id:
			return s
	return {}


static func active(col: Colonies) -> Dictionary:
	return find(String(col.scenario.get("id", ""))) if not col.scenario.is_empty() else {}


## 진행 중인 시나리오의 규칙 (없으면 기본값)
static func rule(col: Colonies, key: String, default: Variant = null) -> Variant:
	if col == null or String(col.scenario.get("result", "")) != "":
		return default
	return active(col).get("rules", {}).get(key, default)


## 새 게임에 시나리오를 건다 (Colonies.start 뒤): 고향의 처음 값을 고치고 규칙을 건다
static func begin(col: Colonies, id: String) -> void:
	var s := find(id)
	if s.is_empty():
		return
	col.scenario = {"id": id, "start": col.hour, "done": {}, "result": "", "why": "", "score": 0, "end": -1}
	var home: CitySim = col.list[0]["sim"]
	var rules: Dictionary = s.get("rules", {})
	home.stock["parts"] = float(home.stock["parts"]) * float(rules.get("start_parts_k", 1.0))
	home.support *= float(rules.get("start_support_k", 1.0))
	apply_rules(col)
	home.note("시나리오 — %s: %s" % [String(s["name"]), String(s.get("text", ""))], "good")


## 규칙 가운데 다른 규칙이 읽는 것을 건다 (새 게임·불러오기 — 시나리오가 없으면 기본으로 돌린다)
static func apply_rules(col: Colonies) -> void:
	CityHazards.rate_k = float(rule(col, "hazard_k", 1.0))


## 날마다 (Colonies.step): 목표를 살피고 이기거나 지면 result를 정한다. 막 정해졌으면 그 결과
static func step(col: Colonies) -> String:
	var s := active(col)
	if s.is_empty() or String(col.scenario.get("result", "")) != "":
		return ""
	var done: Dictionary = col.scenario["done"]
	var goals: Array = s["goals"]
	var all_done := true
	for i in goals.size():
		var g: Dictionary = goals[i]
		var p := _progress(col, g)
		if g.has("max") or g.has("min"):
			if not bool(p["ok"]):
				return _end(col, "lost", "%s — 지킬 목표를 어겼다" % goal_text(g))
			continue
		if done.has(str(i)):
			continue
		if bool(p["ok"]):
			done[str(i)] = col.hour
			(col.list[0]["sim"] as CitySim).note("시나리오 목표 — %s 이뤘다" % goal_text(g), "good")
		else:
			all_done = false
	if all_done:
		return _end(col, "won", "목표를 다 이뤘다")
	if col.hour - int(col.scenario["start"]) >= int(s["days"]) * 24:
		return _end(col, "lost", "기한 %d일이 지났다" % int(s["days"]))
	return ""


static func _end(col: Colonies, result: String, why: String) -> String:
	col.scenario["result"] = result
	col.scenario["why"] = why
	col.scenario["end"] = col.hour
	if result == "won":
		col.scenario["score"] = score(col)
		_record(col)
	apply_rules(col)                          # 끝나면 규칙을 푼다 (계속 자유롭게)
	return result


## 남은 날 (기한까지)
static func days_left(col: Colonies) -> int:
	var s := active(col)
	if s.is_empty():
		return 0
	var end := int(col.scenario.get("end", -1)) if int(col.scenario.get("end", -1)) >= 0 else col.hour
	return maxi(0, int(s["days"]) - int(floor((end - int(col.scenario["start"])) / 24.0)))


static func deaths(col: Colonies) -> int:
	var n := 0
	for c in col.list:
		for v in (c["sim"] as CitySim).deaths.values():
			n += int(v)
	return n


static func score(col: Colonies) -> int:
	var k: Dictionary = data().get("score", {})
	var home: CitySim = col.list[0]["sim"]
	return int(float(k.get("base", 1000)) + days_left(col) * float(k.get("per_day_left", 2)) + home.population() * float(k.get("per_pop", 1))
		+ home.trust * float(k.get("per_trust", 3)) - deaths(col) * float(k.get("per_death", 150)))


## 목표 하나의 지금: {have, need, ok}
static func _progress(col: Colonies, g: Dictionary) -> Dictionary:
	var home: Dictionary = col.list[0]
	var hs: CitySim = home["sim"]
	var have := 0.0
	match String(g["type"]):
		"pop":
			have = hs.population()
		"city_pop":
			var i := col.index_of_site(String(g.get("site", "")))
			have = (col.list[i]["sim"] as CitySim).population() if i >= 0 else 0.0
		"total_pop":
			for c in col.list:
				have += (c["sim"] as CitySim).population()
		"era":
			have = CityProgress.era_of(home)
		"contracts":
			have = int(CityTrade.state(home)["done"])
		"finds":
			for site in CityExplore.state(home)["sites"]:
				if String(site["state"]) == "found" and String(site["find"]) != "nothing":
					have += 1
		"mega":
			have = 1.0 if (home["plan"] as CityPlan).mega_done.any(func(w): return String(w["id"]) == String(g["id"])) else 0.0
		"cities":
			have = col.list.size()
		"techs":
			have = hs.techs.size()
		"deaths":
			have = deaths(col)
			return {"have": have, "need": float(g["max"]), "ok": have <= float(g["max"])}
		"trust":
			have = hs.trust
			return {"have": have, "need": float(g["min"]), "ok": have >= float(g["min"])}
	var need := float(g.get("value", 1))
	return {"have": have, "need": need, "ok": have >= need}


## 목표의 글: "섀클턴 정착민 200명", "사망 0명까지" …
static func goal_text(g: Dictionary) -> String:
	match String(g["type"]):
		"pop":
			return "고향 정착민 %d명" % int(g["value"])
		"city_pop":
			return "%s 정착민 %d명" % [String(GameData.site(String(g["site"])).get("short", g["site"])), int(g["value"])]
		"total_pop":
			return "모든 도시 정착민 %d명" % int(g["value"])
		"era":
			return CityProgress.era_name(int(g["value"]))
		"contracts":
			return "수출 계약 %d건" % int(g["value"])
		"finds":
			return "탐사 발견 %d" % int(g["value"])
		"mega":
			return String(CityProgress.mega(String(g["id"])).get("name", g["id"])) + " 완공"
		"cities":
			return "도시 %d곳" % int(g["value"])
		"techs":
			return "기술 %d가지" % int(g["value"])
		"deaths":
			return "사망 %d명까지" % int(g["max"])
		"trust":
			return "신뢰 %d 넘게" % int(g["min"])
	return String(g["type"])


## 화면에 보일 목표 줄들: [글, 이뤘나(true)·어겼나(false)·아직(null), 진행 글]
static func lines(col: Colonies) -> Array:
	var s := active(col)
	var out: Array = []
	if s.is_empty():
		return out
	var done: Dictionary = col.scenario.get("done", {})
	var goals: Array = s["goals"]
	for i in goals.size():
		var g: Dictionary = goals[i]
		var p := _progress(col, g)
		var keep := g.has("max") or g.has("min")
		var state: Variant = null
		if keep:
			state = bool(p["ok"])
		elif done.has(str(i)):
			state = true
		var prog := "%s / %s" % [Fmt.n(float(p["have"])), Fmt.n(float(p["need"]))]
		out.append([goal_text(g), state, prog])
	return out


## 한 줄 요약 (3D 화면 왼쪽 위): "첫 해 · 고향 정착민 152/200 · 남은 213일"
static func summary(col: Colonies) -> String:
	var s := active(col)
	if s.is_empty():
		return ""
	var r := String(col.scenario.get("result", ""))
	if r == "won":
		return "%s — 이겼다 (점수 %d)" % [String(s["name"]), int(col.scenario.get("score", 0))]
	if r == "lost":
		return "%s — 졌다 (%s)" % [String(s["name"]), String(col.scenario.get("why", ""))]
	var parts := PackedStringArray([String(s["name"])])
	for l in lines(col):
		if l[1] == null:
			parts.append("%s %s" % [String(l[0]), String(l[2])])
	parts.append("남은 %d일" % days_left(col))
	return " · ".join(parts)


# ── 기록 ────────────────────────────────────────────────────────
static func records() -> Dictionary:
	if not FileAccess.file_exists(records_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(records_path))
	return parsed if parsed is Dictionary else {}


## 이긴 판을 기록에 (시나리오마다 점수가 가장 높은 것)
static func _record(col: Colonies) -> void:
	var id := String(col.scenario["id"])
	var all := records()
	var best: Dictionary = all.get(id, {})
	var sc := int(col.scenario["score"])
	if best.is_empty() or sc > int(best.get("score", 0)):
		var used := int(floor((int(col.scenario["end"]) - int(col.scenario["start"])) / 24.0))
		all[id] = {"score": sc, "days": used, "deaths": deaths(col), "date": Time.get_date_string_from_system()}
		var f := FileAccess.open(records_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(all))


static func record_text(id: String) -> String:
	var r: Dictionary = records().get(id, {})
	return "" if r.is_empty() else "최고 기록 %d점 (%d일)" % [int(r["score"]), int(r["days"])]
