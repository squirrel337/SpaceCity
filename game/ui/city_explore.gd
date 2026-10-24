class_name CityExplore
extends RefCounted
## 둘레 탐사 (자료: data/city_hazards.json의 explore). 시뮬레이션 밖의 규칙이다 — 모든 도시에.
## 도시마다 기지 가운데에서 min_m~max_m 떨어진 탐사지 sites곳이 있다 (자리와 숨은 발견은 도시로 정해진다 — 다시 해도 같다).
## 탐사대(가압 로버)가 cost를 내고 speed_m_day로 가서 survey_days 동안 조사하고 돌아온다 — 조사가 끝나면 발견이 드러나고
## 보상(비축·연구 점수·지원 점수, 용암 동굴 같은 것은 그 도시에 남는 보정 — CityExt의 explore 몫)을 받는다.
## 한 번에 한 탐사대. 직접 운영은 '개척' 탭에서, 자동 운영은 every_days마다 가장 가까운 곳으로 보낸다.
## 상태는 c["explore"]: {sites: [{at: [x, y], find, state: unknown·going·found}], trip: {site, depart, arrive, done, back} (시간)}

static func data() -> Dictionary:
	return CityHazards.data().get("explore", {})


static func find(id: String) -> Dictionary:
	for f in data().get("finds", []):
		if String(f["id"]) == id:
			return f
	return {}


static func state(c: Dictionary) -> Dictionary:
	if not c.get("explore") is Dictionary:
		c["explore"] = {"sites": _make_sites(c), "trip": {}}
	return c["explore"]


## 탐사지: 도시마다 정해진 방향·거리, 그 천체의 발견 가운데 weight 비율로 하나씩
static func _make_sites(c: Dictionary) -> Array:
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var ex := data()
	var body := String(GameData.site(sim.site_id).get("body", "moon"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, "explore"])
	var finds: Array = []
	var total := 0.0
	for f in ex.get("finds", []):
		var bodies: Array = f.get("bodies", ["*"])
		if "*" in bodies or body in bodies:
			finds.append(f)
			total += float(f.get("weight", 1.0))
	var out: Array = []
	var hub := plan.hub()
	var n := int(ex.get("sites", 6))
	for i in n:
		var ang := (float(i) + rng.randf_range(0.15, 0.85)) / n * TAU
		var dist := rng.randf_range(float(ex.get("min_m", 700)), float(ex.get("max_m", 2600)))
		var at := hub + Vector2(cos(ang), sin(ang)) * dist
		var pick := rng.randf() * total
		var kind := "nothing"
		for f in finds:
			pick -= float(f.get("weight", 1.0))
			if pick <= 0.0:
				kind = String(f["id"])
				break
		out.append({"at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1)], "find": kind, "state": "unknown"})
	return out


static func site_pos(s: Dictionary) -> Vector2:
	return Vector2(float(s["at"][0]), float(s["at"][1]))


## 탐사대를 보낼 수 없으면 까닭, 보낼 수 있으면 ""
static func can_send(c: Dictionary, i: int) -> String:
	var st := state(c)
	var sim: CitySim = c["sim"]
	if not (st["trip"] as Dictionary).is_empty():
		return "탐사대가 나가 있다"
	if i < 0 or i >= (st["sites"] as Array).size() or String(st["sites"][i]["state"]) != "unknown":
		return "이미 조사한 곳이다"
	if not sim.can_afford(data().get("cost", {}), 40.0):
		return "자재 부족 (%s)" % CityPlan.cost_text(data().get("cost", {}))
	return ""


## 탐사대를 보낸다: 값을 내고, 가는 날·조사 끝·돌아오는 날(시간)을 정한다
static func send(c: Dictionary, i: int) -> bool:
	if can_send(c, i) != "":
		return false
	var st := state(c)
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var cost: Dictionary = data().get("cost", {})
	for key in cost:
		sim.stock[key] = float(sim.stock.get(key, 0.0)) - float(cost[key])
	var s: Dictionary = st["sites"][i]
	var dist := site_pos(s).distance_to(plan.hub())
	var go_h := int(ceil(dist / float(data().get("speed_m_day", 1200)) * 24.0))
	var survey_h := int(data().get("survey_days", 4)) * 24
	st["trip"] = {"site": i, "depart": sim.hour, "arrive": sim.hour + go_h, "done": sim.hour + go_h + survey_h,
		"back": sim.hour + go_h * 2 + survey_h}
	s["state"] = "going"
	sim.note("탐사대 출발 — %d km 떨어진 곳으로 (조사 %d일, 돌아오기까지 %d일)" % [int(round(dist / 1000.0)),
		int(data().get("survey_days", 4)), int(ceil((go_h * 2 + survey_h) / 24.0))], "info")
	return true


## 날마다 (Colonies.step — 모든 도시): 조사가 끝났으면 발견을 드러내고 보상을 준다, 돌아왔으면 탐사대를 비운다.
## 자동 운영(또는 탐사를 맡긴 도시 — CityAuto)은 every_days마다 가장 가까운 탐사지로 보낸다
static func step(c: Dictionary, day: int) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var trip: Dictionary = st["trip"]
	if not trip.is_empty():
		var s: Dictionary = st["sites"][int(trip["site"])]
		if String(s["state"]) == "going" and sim.hour >= int(trip["done"]):
			s["state"] = "found"
			_reward(c, s)
		if sim.hour >= int(trip["back"]):
			st["trip"] = {}
	if CityAuto.on(c, "explore") and (st["trip"] as Dictionary).is_empty() and posmod(day, int(data().get("every_days", 15))) == 7:
		var best := -1
		var best_d := INF
		for i in (st["sites"] as Array).size():
			var d := site_pos(st["sites"][i]).distance_to((c["plan"] as CityPlan).hub())
			if String(st["sites"][i]["state"]) == "unknown" and d < best_d:
				best_d = d
				best = i
		if best >= 0 and sim.can_afford(data().get("cost", {}), 200.0) and send(c, best):
			CityAuto.record(c, "explore", "탐사대 — %s의 탐사지로 보냈다: 아직 모르는 곳 가운데 가장 가깝다" %
				(c["plan"] as CityPlan).where_text(site_pos(st["sites"][best])))


static func _reward(c: Dictionary, s: Dictionary) -> void:
	var sim: CitySim = c["sim"]
	var f := find(String(s["find"]))
	var rw: Dictionary = f.get("reward", {})
	if rw.has("water_kg"):
		sim.stock["water_kg"] = float(sim.stock["water_kg"]) + float(rw["water_kg"])
	if rw.has("metal_t"):
		sim.stock["metal_t"] = float(sim.stock["metal_t"]) + float(rw["metal_t"])
	if rw.has("rp"):
		sim.rp_bank += float(rw["rp"])
	if rw.has("support"):
		sim.support += float(rw["support"])
	if rw.has("housing_add") or rw.has("morale"):
		apply(c)
	sim.note("탐사 — %s: %s%s" % [String(f.get("name", "?")), String(f.get("text", "")),
		(" (" + reward_text(rw) + ")") if not rw.is_empty() else ""], "good")


## 드러난 발견의 남는 보정(집·사기)을 모아 CityExt의 explore 몫으로
static func apply(c: Dictionary) -> void:
	var sum := {}
	for s in state(c)["sites"]:
		if String(s["state"]) != "found":
			continue
		var rw: Dictionary = find(String(s["find"])).get("reward", {})
		for k in ["housing_add", "morale"]:
			if rw.has(k):
				sum[k] = float(sum.get(k, 0.0)) + float(rw[k])
	CityExt.set_part(c, "explore", sum)


static func reward_text(rw: Dictionary) -> String:
	var parts := PackedStringArray()
	if rw.has("water_kg"):
		parts.append("물 %s t" % Fmt.n(float(rw["water_kg"]) / 1000.0))
	if rw.has("metal_t"):
		parts.append("금속 %d t" % int(rw["metal_t"]))
	if rw.has("rp"):
		parts.append("연구 %d RP" % int(rw["rp"]))
	if rw.has("support"):
		parts.append("지원 점수 %d" % int(rw["support"]))
	if rw.has("housing_add"):
		parts.append("집 +%d" % int(rw["housing_add"]))
	if rw.has("morale"):
		parts.append("사기 +%d" % int(rw["morale"]))
	return " · ".join(parts)


## 탐사대가 지금 있는 곳 (기지 가운데 → 탐사지 → 기지 가운데). 나가 있지 않으면 {}
static func rover_at(c: Dictionary) -> Dictionary:
	var st := state(c)
	var trip: Dictionary = st["trip"]
	if trip.is_empty():
		return {}
	var sim: CitySim = c["sim"]
	var hub := (c["plan"] as CityPlan).hub()
	var site := site_pos(st["sites"][int(trip["site"])])
	var h := float(sim.hour)
	var p := hub
	var heading := site - hub
	if h < float(trip["arrive"]):
		p = hub.lerp(site, clampf((h - float(trip["depart"])) / maxf(float(trip["arrive"]) - float(trip["depart"]), 1.0), 0.0, 1.0))
	elif h < float(trip["done"]):
		p = site
	else:
		p = site.lerp(hub, clampf((h - float(trip["done"])) / maxf(float(trip["back"]) - float(trip["done"]), 1.0), 0.0, 1.0))
		heading = hub - site
	return {"at": p, "heading": heading}
