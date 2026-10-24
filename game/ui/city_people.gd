class_name CityPeople
extends RefCounted
## 이름 있는 정착민과 이야기 이벤트 (자료: data/city_people.json). 시뮬레이션 밖의 규칙이다 — 모든 도시에.
##   사람: 도시마다 처음 start명, 정착민이 per_pop명 늘 때마다 한 명씩 (max까지). 이름·역할·성격은 도시와 순번으로 정해진다
##         (다시 해도 같다). 있는 동안 역할의 보정(기술자: 로봇 작업량, 과학자: 연구, 의사·예술가: 사기 …)이 CityExt의 people 몫으로
##   이벤트: every_days마다 한 번, 조건이 맞는 것 가운데 무게로 하나 (도시·날로 정해지는 난수, 같은 이벤트는 cooldown_days 안에 다시
##         오지 않는다). 그 역할의 사람이 주인공이다. 고르면 효과 — 사기·신뢰·지원 점수·부품·연구, 기간이 있는(또는 늘) 보정(boost),
##         사람이 떠나거나 다른 도시로 옮긴다. 직접 운영 도시는 결정 카드로 묻고 (고를 때까지 다음 이벤트는 오지 않는다),
##         자동 운영 도시는 시드가 효과를 셈해 고른다.
## 상태는 c["people"]: {people: [{id, name, role, trait, since}], serial, next(날), boosts: [{key, k|add, until(날, -1 = 늘), why}],
##                      seen: {이벤트: 날}, pending: {이벤트 — 고르기를 기다린다}, story: [[시간, 제목, 고른 것, 글]]}

const STORY_KEEP := 20

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_people.json"))
		_data = parsed if parsed is Dictionary else {"roles": [], "events": []}
	return _data


static func role(id: String) -> Dictionary:
	for r in data()["roles"]:
		if String(r["id"]) == id:
			return r
	return {}


static func event(id: String) -> Dictionary:
	for e in data()["events"]:
		if String(e["id"]) == id:
			return e
	return {}


static func state(c: Dictionary) -> Dictionary:
	if not c.get("people") is Dictionary:
		var sim: CitySim = c["sim"]
		c["people"] = {"people": [], "serial": 0, "next": sim.current_day() + 20, "boosts": [], "seen": {}, "pending": {},
			"story": []}
		_grow(c, true)
	return c["people"]


## 사람 하나: 도시와 순번으로 정해지는 난수 — 이름(열에 여섯은 한국 이름), 아직 없는 역할부터, 성격
static func _make(c: Dictionary, st: Dictionary) -> Dictionary:
	var sim: CitySim = c["sim"]
	var d := data()
	var n := int(st["serial"])
	st["serial"] = n + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, "person", n])
	var taken := {}
	for p in st["people"]:
		taken[String(p["name"])] = true
	var name := ""
	for _try in 8:                                 # 그 도시에 같은 이름이 없게
		if rng.randf() < 0.6:
			name = String(d["family"][rng.randi() % (d["family"] as Array).size()]) + String(d["given"][rng.randi() % (d["given"] as Array).size()])
		else:
			name = String(d["world"][rng.randi() % (d["world"] as Array).size()])
		if not taken.has(name):
			break
	var have := {}
	for p in st["people"]:
		have[String(p["role"])] = true
	var roles: Array = (d["roles"] as Array).map(func(r): return String(r["id"]))
	var free := roles.filter(func(r): return not have.has(r))
	var pool: Array = free if not free.is_empty() else roles
	return {"id": n, "name": name, "role": String(pool[rng.randi() % pool.size()]),
		"trait": String(d["traits"][rng.randi() % (d["traits"] as Array).size()]), "since": sim.current_day()}


## 정착민 수에 맞춰 사람을 더한다 (처음이 아니면 알린다)
static func _grow(c: Dictionary, first := false) -> void:
	var st: Dictionary = c["people"]
	var sim: CitySim = c["sim"]
	var d := data()
	var want := clampi(int(d.get("start", 3)) + int(floor(maxf(0.0, sim.population() - 120.0) / float(d.get("per_pop", 80)))),
		0, int(d.get("max", 8)))
	var added := false
	while (st["people"] as Array).size() < want:
		var p := _make(c, st)
		(st["people"] as Array).append(p)
		added = true
		if not first:
			sim.note("새 얼굴 — %s, %s %s (%s)" % [String(p["name"]), String(p["trait"]), role_name(p), effect_text(role(String(p["role"]))["effect"])],
				"good")
	if added:
		apply(c)


static func role_name(p: Dictionary) -> String:
	return String(role(String(p["role"])).get("name", p["role"]))


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시): 사람을 늘리고, 끝난 보정을 빼고, 이벤트 날이면 이벤트를 고른다.
## 자동 운영이면 시드가 고르고, 아니면 고르기를 기다린다 (pending — main이 결정 카드로 묻는다)
static func step(c: Dictionary, day: int, mgr: Colonies = null) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	_grow(c)
	var before := (st["boosts"] as Array).size()
	st["boosts"] = (st["boosts"] as Array).filter(func(b): return int(b["until"]) < 0 or int(b["until"]) > day)
	if (st["boosts"] as Array).size() != before:
		apply(c)
	if not (st["pending"] as Dictionary).is_empty():
		if CityAuto.full(sim):                    # 기다리는 사이 자동 운영을 켰다 — 시드가 고른다
			resolve(c, best_choice(st["pending"]), mgr, true)
		return
	if day < int(st["next"]):
		return
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, day, "story"])
	var ed: Array = d.get("every_days", [24, 40])
	st["next"] = day + rng.randi_range(int(ed[0]), int(ed[1]))
	var inst := _pick(c, day, rng, mgr)
	if inst.is_empty():
		return
	(st["seen"] as Dictionary)[String(inst["id"])] = day
	if CityAuto.full(sim):
		resolve(c, best_choice(inst), mgr, true, inst)
	else:
		st["pending"] = inst


## 조건이 맞는 이벤트 가운데 무게로 하나 — 주인공(그 역할의 사람, 없으면 아무나)과 글을 채운 것
static func _pick(c: Dictionary, day: int, rng: RandomNumberGenerator, mgr: Colonies) -> Dictionary:
	var st: Dictionary = c["people"]
	var sim: CitySim = c["sim"]
	var people: Array = st["people"]
	if people.is_empty():
		return {}
	var d := data()
	var seen: Dictionary = st["seen"]
	var others: Array = []
	if mgr != null:
		others = mgr.list.filter(func(o): return o != c)
	var pool: Array = []
	var total := 0.0
	for e in d["events"]:
		var id := String(e["id"])
		if seen.has(id) and (bool(e.get("once", false)) or day - int(seen[id]) < int(d.get("cooldown_days", 150))):
			continue
		var w: Dictionary = e.get("when", {})
		if w.has("min_pop") and sim.population() < float(w["min_pop"]):
			continue
		if w.has("max_morale") and sim.morale > float(w["max_morale"]):
			continue
		if w.has("min_trust") and sim.trust < float(w["min_trust"]):
			continue
		if w.has("max_support") and sim.support > float(w["max_support"]):
			continue
		if w.has("min_robots") and sim.robots < int(w["min_robots"]):
			continue
		if w.has("min_era") and CityProgress.era_of(c) < int(w["min_era"]):
			continue
		if w.has("colonies") and others.size() + 1 < int(w["colonies"]):
			continue
		if e.has("role") and not people.any(func(p): return String(p["role"]) == String(e["role"])):
			continue
		pool.append(e)
		total += float(e.get("weight", 1.0))
	if pool.is_empty():
		return {}
	var pick := rng.randf() * total
	var ev: Dictionary = pool[-1]
	for e in pool:
		pick -= float(e.get("weight", 1.0))
		if pick <= 0.0:
			ev = e
			break
	var cast: Array = people.filter(func(p): return not ev.has("role") or String(p["role"]) == String(ev["role"]))
	var hero: Dictionary = cast[rng.randi() % cast.size()]
	var colony := ""
	var to_site := ""
	if not others.is_empty():
		var oc: Dictionary = others[rng.randi() % others.size()]
		colony = String(oc.get("short", oc["name"]))
		to_site = String(oc["site"])
	var fill := func(t: String) -> String:
		return t.replace("{name}", String(hero["name"])).replace("{role}", role_name(hero)).replace("{colony}", colony)
	var choices: Array = []
	for ch in ev["choices"]:
		choices.append({"label": fill.call(String(ch["label"])), "text": fill.call(String(ch.get("text", ""))), "effect": ch.get("effect", {})})
	return {"id": String(ev["id"]), "title": fill.call(String(ev["title"])), "text": fill.call(String(ev["text"])), "person": int(hero["id"]),
		"to": to_site, "choices": choices}


## 시드가 고를 때의 점수: 사기 1 · 신뢰 1.5 · 지원 점수 0.02 · 부품 0.03 · 연구 0.004, 보정은 크기 × 날수, 사람이 떠나면 −1
static func _score(ef: Dictionary) -> float:
	var s := float(ef.get("morale", 0.0)) + float(ef.get("trust", 0.0)) * 1.5 + float(ef.get("support", 0.0)) * 0.02 \
		+ float(ef.get("parts", 0.0)) * 0.03 + float(ef.get("rp", 0.0)) * 0.004
	if ef.get("boost") is Dictionary:
		var b: Dictionary = ef["boost"]
		var days := float(b.get("days", 0)) if int(b.get("days", 0)) > 0 else 365.0
		var mag := (float(b["k"]) - 1.0) * 100.0 if b.has("k") else float(b.get("add", 0.0)) * 2.0
		s += mag * days / 60.0
	if String(ef.get("person", "")) == "leave":
		s -= 1.0
	elif String(ef.get("person", "")) == "move":
		s -= 0.5
	return s


static func best_choice(inst: Dictionary) -> int:
	var best := 0
	var choices: Array = inst["choices"]
	for i in choices.size():
		if _score(choices[i]["effect"]) > _score(choices[best]["effect"]):
			best = i
	return best


## 고른 것의 효과를 낸다 (inst가 없으면 기다리던 이벤트). 냈으면 true
static func resolve(c: Dictionary, index: int, mgr: Colonies = null, auto := false, inst: Dictionary = {}) -> bool:
	var st := state(c)
	if inst.is_empty():
		inst = st["pending"]
	if inst.is_empty() or index < 0 or index >= (inst["choices"] as Array).size():
		return false
	st["pending"] = {}
	var sim: CitySim = c["sim"]
	var ch: Dictionary = inst["choices"][index]
	var ef: Dictionary = ch["effect"]
	sim.morale = clampf(sim.morale + float(ef.get("morale", 0.0)), 0.0, 100.0)
	sim.trust = clampf(sim.trust + float(ef.get("trust", 0.0)), 0.0, 100.0)
	sim.support += float(ef.get("support", 0.0))
	sim.stock["parts"] = maxf(0.0, float(sim.stock["parts"]) + float(ef.get("parts", 0.0)))
	sim.rp_bank += float(ef.get("rp", 0.0))
	if ef.get("boost") is Dictionary:
		var b: Dictionary = (ef["boost"] as Dictionary).duplicate()
		b["until"] = sim.current_day() + int(b["days"]) if int(b.get("days", 0)) > 0 else -1
		b["why"] = String(inst["title"])
		(st["boosts"] as Array).append(b)
	var who := {}
	for p in st["people"]:
		if int(p["id"]) == int(inst["person"]):
			who = p
	match String(ef.get("person", "")):
		"leave":
			(st["people"] as Array).erase(who)
		"move":
			(st["people"] as Array).erase(who)
			if mgr != null and mgr.index_of_site(String(inst.get("to", ""))) >= 0:
				var oc: Dictionary = mgr.list[mgr.index_of_site(String(inst["to"]))]
				var ost := state(oc)
				var moved: Dictionary = who.duplicate()
				moved["id"] = int(ost["serial"]) + 1000 * (1 + int(moved["id"]))      # 그 도시의 번호와 겹치지 않게
				moved["since"] = (oc["sim"] as CitySim).current_day()
				(ost["people"] as Array).append(moved)
				(oc["sim"] as CitySim).note("새 얼굴 — %s, %s에서 옮겨 왔다 (%s)" % [String(who.get("name", "")), String(c["name"]), role_name(who)], "good")
				apply(oc)
	apply(c)
	var story: Array = st["story"]
	story.append([sim.hour, String(inst["title"]), String(ch["label"]), String(ch["text"])])
	while story.size() > STORY_KEEP:
		story.pop_front()
	sim.note("%s이야기 — %s: %s (%s)" % ["자동 운영 · " if auto else "", String(inst["title"]), String(ch["label"]), String(ch["text"])],
		"info" if auto else "good")
	return true


## 고르기를 기다리는 이벤트 ({}이면 없다)
static func pending(c: Dictionary) -> Dictionary:
	return state(c)["pending"]


## 있는 사람들의 역할 보정과 남은 보정을 모아 시뮬레이션 보정의 people 몫으로
static func apply(c: Dictionary) -> void:
	var st: Dictionary = c["people"]
	var sum := {}
	var effs: Array = []
	for p in st["people"]:
		effs.append(role(String(p["role"])).get("effect", {}))
	for b in st["boosts"]:
		effs.append({String(b["key"]): float(b["k"]) if b.has("k") else float(b.get("add", 0.0))})
	for ef in effs:
		for k in ef:
			if k in CityExt.MUL:
				sum[k] = float(sum.get(k, 1.0)) * float(ef[k])
			else:
				sum[k] = float(sum.get(k, 0.0)) + float(ef[k])
	CityExt.set_part(c, "people", sum)


static func effect_text(ef: Dictionary) -> String:
	return CityResearch.effect_text(ef)
