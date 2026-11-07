class_name CityGens
extends RefCounted
## 정착민의 세대 (자료 city_generations.json) — 시뮬레이션 밖의 규칙이다 (모든 도시).
## 시대 1부터, 정착민 50명이 넘고 집에 빈자리가 있으면 아이가 태어난다: 한 해에 정착민 한 명당 1.4% — 사기 50에서 1점마다
##   1.2%씩 더하고 빼고, 의료실이 있으면 ×1.15, 집이 95% 넘게 차면 ×0.4. 태어난 아이는 그 도시의 정착민에 더한다 (선량 0).
## 나이: 0~5 아기·유아, 6~17 학생, 18부터 2세대 어른. 학생은 학교 자리(연구동 1기 30 · 이름 있는 교사 20 · 녹지 공원 1기 15)가
##   모자라면 사기 −3, 학생마다 연구 +0.03/일. 2세대 어른 몫 10%마다 사기 +1.2 (4까지), 일하는 효율 ×1.006 — CityExt의 gens 몫.
##   정치: 공유지 연합의 지지가 2세대 몫 × 40만큼 오르고 지구 우호회는 × 30만큼 내린다 (city_politics.json의 terms.native).
## 이름: 첫 아이와 첫 2세대 어른은 이름과 함께 알린다. 2세대가 생기면 새로 생기는 이름 있는 정착민 가운데 그 몫만큼이 토박이다.
## 인구가 줄면 (사망·이주) 아이와 2세대도 같은 비율로 준다.
## 상태 c["gens"]: {born: [[태어난 날, 수], …] (18세 전), adults, total, acc(쌓인 몫), first: [이름, 날], first_adult: [이름, 날], log}

const PATH := "res://data/city_generations.json"
const LOG_KEEP := 12

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func state(c: Dictionary) -> Dictionary:
	if not c.get("gens") is Dictionary or not (c["gens"] as Dictionary).has("born"):
		c["gens"] = {"born": [], "adults": 0.0, "total": 0, "acc": 0.0, "first": [], "first_adult": [], "log": []}
	return c["gens"]


static func load_state(c: Dictionary, d: Variant) -> void:
	c.erase("gens")
	var st := state(c)
	if not (d is Dictionary and (d as Dictionary).get("born") is Array):
		return
	var src: Dictionary = d
	for b in src["born"]:
		if b is Array and (b as Array).size() >= 2:
			(st["born"] as Array).append([int(b[0]), float(b[1])])
	st["adults"] = float(src.get("adults", 0.0))
	st["total"] = int(src.get("total", 0))
	st["acc"] = float(src.get("acc", 0.0))
	for k in ["first", "first_adult"]:
		if src.get(k) is Array and (src[k] as Array).size() >= 2:
			st[k] = [String(src[k][0]), int(src[k][1])]
	for e in src.get("log", []) if src.get("log") is Array else []:
		if e is Array and (e as Array).size() >= 2:
			(st["log"] as Array).append([int(e[0]), String(e[1])])
	apply(c)


# ── 셈 ──────────────────────────────────────────────────────────
static func children(c: Dictionary, day: int) -> Dictionary:
	var st := state(c)
	var ages: Dictionary = data().get("ages", {})
	var school_d := int(ages.get("school", 6)) * 365
	var kids := 0.0
	var students := 0.0
	for b in st["born"]:
		var age := day - int(b[0])
		if age < school_d:
			kids += float(b[1])
		else:
			students += float(b[1])
	return {"kids": kids, "students": students}


## 2세대 어른 몫 (어른 가운데, 0~1)
static func native_share(c: Dictionary) -> float:
	if not c.get("gens") is Dictionary:
		return 0.0
	var sim: CitySim = c["sim"]
	var st: Dictionary = c["gens"]
	var ch := children(c, sim.current_day())
	var adults := maxf(sim.population() - float(ch["kids"]) - float(ch["students"]), 1.0)
	return clampf(float(st["adults"]) / adults, 0.0, 1.0)


static func school_cap(c: Dictionary) -> float:
	var sim: CitySim = c["sim"]
	var sd: Dictionary = data().get("school", {})
	var labs := 0
	for mid in GameData.FAMILY.get("research_lab", []):
		labs += int(sim.counts.get(mid, 0))
	var commons := 0
	for mid in GameData.FAMILY.get("green_commons", []):
		commons += int(sim.counts.get(mid, 0))
	var teachers := 0
	if c.get("people") is Dictionary:
		for p in c["people"].get("people", []):
			if String(p.get("role", "")) == "teacher":
				teachers += 1
	return labs * float(sd.get("per_lab", 30)) + teachers * float(sd.get("per_teacher", 20)) + commons * float(sd.get("per_commons", 15))


## 한 해에 정착민 한 명당 태어나는 몫 (조건이 안 되면 0)
static func birth_rate(c: Dictionary) -> float:
	var sim: CitySim = c["sim"]
	var bd: Dictionary = data().get("births", {})
	if CityProgress.era_of(c) < int(bd.get("start_era", 1)) or sim.population() < float(bd.get("min_pop", 50)):
		return 0.0
	if sim.housing_cap - sim.population() < float(bd.get("room", 1)):
		return 0.0
	var r := float(bd.get("rate", 0.014)) * maxf(0.0, 1.0 + (sim.morale - 50.0) * float(bd.get("morale_k", 0.012)))
	var care := 0
	for mid in GameData.FAMILY.get("medical_bay", []):
		care += int(sim.counts.get(mid, 0))
	if care > 0:
		r *= float(bd.get("care_k", 1.15))
	if sim.population() > sim.housing_cap * 0.95:
		r *= float(bd.get("crowded_k", 0.4))
	return r


# ── 하루 (Colonies.step) ────────────────────────────────────────
static func step(c: Dictionary, day: int) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	# 인구가 줄었으면 아이·2세대도 같은 비율로
	var ch := children(c, day)
	var tracked := float(ch["kids"]) + float(ch["students"]) + float(st["adults"])
	var pop := sim.population()
	if tracked > pop and tracked > 0.0:
		var k := pop / tracked
		for b in st["born"]:
			b[1] = float(b[1]) * k
		st["adults"] = float(st["adults"]) * k
	# 어른이 된다
	var adult_d := int(data().get("ages", {}).get("adult", 18)) * 365
	for b in (st["born"] as Array).duplicate():
		if day - int(b[0]) >= adult_d:
			(st["born"] as Array).erase(b)
			st["adults"] = float(st["adults"]) + float(b[1])
			if (st["first_adult"] as Array).is_empty() and float(b[1]) > 0.0 and not (st["first"] as Array).is_empty():
				st["first_adult"] = [String(st["first"][0]), day]
				_say(c, "첫 2세대 어른 — %s에서 태어난 %s이(가) 열여덟 살이 되었다. 이 도시에서 나고 자란 사람들이 일터와 평의회에 들어선다" % [
					String(c.get("name", "")), String(st["first"][0])], "milestone")
	# 태어난다
	var r := birth_rate(c)
	if r > 0.0:
		st["acc"] = float(st["acc"]) + pop * r / 365.0
		var n := int(floor(float(st["acc"])))
		if n > 0:
			st["acc"] = float(st["acc"]) - n
			sim.cohorts.append([float(n), 0.0, false])
			(st["born"] as Array).append([day, float(n)])
			st["total"] = int(st["total"]) + n
			if (st["first"] as Array).is_empty():
				var name := child_name(c, 0)
				st["first"] = [name, day]
				var on_earth := String(c.get("body", "")) == "earth"
				_say(c, ("첫 아이 — %s이(가) %s에서 태어났다. 이 도시에서 태어난 첫 사람이다" if on_earth
					else "첫 아이 — %s이(가) %s에서 태어났다. 지구 밖에서 태어난 이 도시의 첫 사람이다") % [name, String(c.get("name", ""))], "milestone")
	apply(c)


static func _say(c: Dictionary, text: String, kind: String) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	(st["log"] as Array).append([sim.hour, text])
	while (st["log"] as Array).size() > LOG_KEEP:
		(st["log"] as Array).remove_at(0)
	sim.note(text, kind)


## 아이 이름: 그 도시의 성·이름 차례로 (정해진다)
static func child_name(c: Dictionary, n: int) -> String:
	var pd := CityPeople.data()
	var sim: CitySim = c["sim"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, "child", n])
	var fam: Array = pd.get("family", ["김"])
	var giv: Array = pd.get("given", ["하늘"])
	return String(fam[rng.randi() % fam.size()]) + String(giv[rng.randi() % giv.size()])


## 보정 (CityExt의 gens 몫): 2세대 몫에 따라 사기·일하는 효율, 학교가 모자라면 사기, 학생마다 연구
static func apply(c: Dictionary) -> void:
	if not c.has("sim"):
		return
	var sim: CitySim = c["sim"]
	var ef: Dictionary = data().get("effects", {})
	var share := native_share(c)
	var ch := children(c, sim.current_day())
	var morale := minf(share * 10.0 * float(ef.get("morale", 1.2)), float(ef.get("max_morale", 4.0)))
	var students := float(ch["students"])
	if students > school_cap(c) + 0.5:
		morale += float(data().get("school", {}).get("short_morale", -3.0))
	var values := {"morale": morale, "work_k": pow(float(ef.get("work_k", 1.006)), share * 10.0),
		"rp_day": students * float(ef.get("rp_day", 0.03))}
	var old: Dictionary = c.get("ext_parts", {}).get("gens", {}) if c.get("ext_parts") is Dictionary else {}
	for k in values:
		if absf(float(old.get(k, 0.0 if k != "work_k" else 1.0)) - float(values[k])) > 1e-4:
			CityExt.set_part(c, "gens", values)
			return


## "아기·유아 12 · 학생 30 (학교 자리 40) · 2세대 어른 8명 (6%) · 이 도시에서 태어난 사람 50"
static func summary(c: Dictionary) -> String:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var ch := children(c, sim.current_day())
	if int(st["total"]) == 0:
		var r := birth_rate(c)
		return "아직 이 도시에서 태어난 아이가 없다 — %s" % ("한 해에 %s명쯤 태어날 것이다" % Fmt.n(sim.population() * r, 1) if r > 0.0
			else "시대 1, 정착민 50명, 집의 빈자리가 있어야 태어난다")
	return "아기·유아 %d · 학생 %d (학교 자리 %d) · 2세대 어른 %d명 (%d%%) · 이 도시에서 태어난 사람 %d" % [int(round(float(ch["kids"]))),
		int(round(float(ch["students"]))), int(school_cap(c)), int(round(float(st["adults"]))), int(round(native_share(c) * 100.0)), int(st["total"])]
