class_name CityProgress
extends RefCounted
## 도시의 시대·이정표·메가프로젝트 (자료: data/city_progress.json). 시뮬레이션 밖의 규칙이다 — 모든 도시(직접 운영도)에.
##   이정표: 날마다 조건(정착민·연구 수·땅·지은 건물·길 종류·무사고 날수·메가프로젝트 수)을 보고, 처음 이루면 상(지원 점수)을
##           받고 기록·알림에 남긴다 (c["progress"]["done"]: id → 이룬 날)
##   시대: 다음 시대의 needs 이정표를 다 이루면 오른다 (도시마다). 메가프로젝트의 era는 이 시대 번호다
##   메가프로젝트: 그 시대가 되고 기술이 있으면 빈 산 땅 구역(건물·길 공사가 없는 구역) 하나에 짓는다 — 그 구역 안의 길은 걷어 내고,
##           단계마다 값을 먼저 내고 days일씩. 자동 운영 도시는 부품이 넉넉하면(단계 값의 3배) 스스로 고르고, 직접 운영은
##           '개척' 탭의 단추로. 다 지으면 효과(집·사기·지원 점수·연구·로봇 작업량)가 그 도시의 시뮬레이션 보정(ext)에 남는다.
##           한 도시에 한 번에 하나, 같은 것은 한 번
## 공사 중인 메가프로젝트는 배치 계획의 mega에 있다 (자리·공정 — 함께 저장된다)

const RICH_K := 3.0


static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_progress.json"))
		_data = parsed if parsed is Dictionary else {"milestones": [], "eras": [], "megaprojects": []}
	return _data


static func state(c: Dictionary) -> Dictionary:
	if not c.get("progress") is Dictionary:
		c["progress"] = {"done": {}, "era": 0, "built": []}
	return c["progress"]


static func era_of(c: Dictionary) -> int:
	return int(state(c).get("era", 0))


static func era_name(i: int) -> String:
	var eras: Array = data()["eras"]
	return String(eras[clampi(i, 0, eras.size() - 1)]["name"]) if not eras.is_empty() else ""


static func milestone_name(id: String) -> String:
	for ms in data()["milestones"]:
		if String(ms["id"]) == id:
			return String(ms["name"])
	return id


static func mega(id: String) -> Dictionary:
	for m in data()["megaprojects"]:
		if String(m["id"]) == id:
			return m
	return {}


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시)
static func step(c: Dictionary, day: int) -> Array:
	var news: Array = check(c, day)
	advance(c)
	var sim: CitySim = c["sim"]
	if sim.autopilot != null and (c["plan"] as CityPlan).mega.is_empty() and posmod(day, 10) == 5:
		for m in data()["megaprojects"]:
			var why := can_start(c, String(m["id"]))
			if why.begins_with("빈 땅 구역이 없다") and _rich(sim, m) and _buy_site(c):
				why = can_start(c, String(m["id"]))
			if why == "" and _rich(sim, m):
				start(c, String(m["id"]))
				break
	return news


## 자동 운영: 메가프로젝트를 지을 빈 땅 구역을 하나 산다 (살 수 있는 구역 가운데 기지 가운데에서 가장 가까운 것, 모드의 여유분은 남기고)
static func _buy_site(c: Dictionary) -> bool:
	var plan: CityPlan = c["plan"]
	var sim: CitySim = c["sim"]
	var reserve: Dictionary = LayoutData.dev_mode(String(c.get("mode", ""))).get("reserve", LayoutData.land()["auto_reserve"])
	var best := {}
	var best_d := INF
	for st in plan.land_candidates():
		if not bool(st["ok"]) or not CityPlan.can_pay(st["cost"], sim, reserve):
			continue
		var d := (st["rect"] as Rect2).get_center().distance_to(plan.hub())
		if d < best_d:
			best_d = d
			best = st
	if best.is_empty() or not plan.buy_parcel(best["cell"], sim):
		return false
	sim.note("메가프로젝트 자리 — 땅 구역을 샀다 (%s)" % CityPlan.cost_text(best["cost"]), "info")
	return true


## 새로 이룬 이정표 (이름들). 상을 주고 시대를 올린다
static func check(c: Dictionary, day: int) -> Array:
	var st := state(c)
	var done: Dictionary = st["done"]
	var sim: CitySim = c["sim"]
	var news: Array = []
	for ms in data()["milestones"]:
		var id := String(ms["id"])
		if done.has(id) or not _met(c, ms.get("when", {})):
			continue
		done[id] = day
		news.append(String(ms["name"]))
		var reward: Dictionary = ms.get("reward", {})
		sim.support += float(reward.get("support", 0.0))
		sim.note("이정표 — %s (%s) · 지원 점수 +%d" % [String(ms["name"]), String(ms.get("text", "")), int(reward.get("support", 0))], "good")
	var eras: Array = data()["eras"]
	while int(st["era"]) + 1 < eras.size():
		var nxt: Dictionary = eras[int(st["era"]) + 1]
		var ok := true
		for need in nxt.get("needs", []):
			if not done.has(String(need)):
				ok = false
		if not ok:
			break
		st["era"] = int(st["era"]) + 1
		sim.note("새 시대 — %s: %s" % [String(nxt["name"]), String(nxt.get("text", ""))], "good")
		news.append(String(nxt["name"]))
	return news


static func _met(c: Dictionary, when: Dictionary) -> bool:
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	if when.has("pop") and sim.population() < float(when["pop"]):
		return false
	if when.has("techs") and sim.techs.size() < int(when["techs"]):
		return false
	if when.has("land") and plan.land.size() < int(when["land"]):
		return false
	if when.has("days") and sim.current_day() < int(when["days"]):
		return false
	if when.has("deaths") and sim.deaths.size() > int(when["deaths"]):
		return false
	if when.has("mega") and (state(c)["built"] as Array).size() < int(when["mega"]):
		return false
	if when.has("built"):
		var any := false                  # 하나라도 (계열이면 그 계열 모두, 종류면 그 종류만)
		var b: Dictionary = when["built"]
		for k in b:
			var n := 0
			if GameData.FAMILY.has(k):
				for mid in GameData.FAMILY[k]:
					n += int(sim.counts.get(mid, 0))
			else:
				n = int(sim.counts.get(k, 0))
			if n >= int(b[k]):
				any = true
		if not any:
			return false
	if when.has("roads"):
		var any_r := false
		for t in plan.etypes:
			if String(t) in when["roads"]:
				any_r = true
				break
		if not any_r:
			return false
	return true


# ── 메가프로젝트 ────────────────────────────────────────────────
## 시작할 수 없으면 까닭, 할 수 있으면 ""
static func can_start(c: Dictionary, id: String) -> String:
	var m := mega(id)
	if m.is_empty():
		return "없는 메가프로젝트"
	var plan: CityPlan = c["plan"]
	var sim: CitySim = c["sim"]
	if id in (state(c)["built"] as Array):
		return "이미 지었다"
	if not plan.mega.is_empty():
		return "짓는 메가프로젝트가 있다"
	if era_of(c) < int(m.get("era", 0)):
		return "%s부터" % era_name(int(m.get("era", 0)))
	var tech: Variant = m.get("tech")
	if tech != null and not sim.techs.has(String(tech)):
		return "연구 필요: %s" % String(GameData.TECHS.get(String(tech), {}).get("name", tech))
	if site_for(plan).x == 2147483647:
		return "빈 땅 구역이 없다 — '확장'으로 땅을 산다"
	var cost: Dictionary = (m["stages"] as Array)[0]["cost"]
	if not sim.can_afford(cost, 40.0):
		return "자재 부족 (첫 단계 %s)" % CityPlan.cost_text(cost)
	return ""


static func _rich(sim: CitySim, m: Dictionary) -> bool:
	var cost: Dictionary = (m["stages"] as Array)[0]["cost"]
	return float(sim.stock["parts"]) >= float(cost.get("parts", 0.0)) * RICH_K \
		and float(sim.stock["metal_t"]) >= float(cost.get("metal_t", 0.0)) * RICH_K


## 지을 자리: 산 땅 구역 가운데 건물·길 공사가 없고 기지 가운데에서 가장 가까운 것. 없으면 Vector2i(INT_MAX, 0)
static func site_for(plan: CityPlan) -> Vector2i:
	var best := Vector2i(2147483647, 0)
	var best_d := INF
	var used := {}
	for w in plan.mega + plan.mega_done:
		used[w["cell"]] = true
	for cell: Vector2i in plan.land:
		if used.has(cell) or not plan.parcel_empty(cell):
			continue
		var r := plan.parcel_rect(cell)
		var busy := false
		for w in plan.works:
			if CityPlan._seg_rect_dist(w["a"], w["b"], r) < 1.0:
				busy = true
		if busy:
			continue
		var d := r.get_center().distance_to(plan.hub())
		if d < best_d:
			best_d = d
			best = cell
	return best


## 시작: 첫 단계 값을 내고, 구역 안의 길을 걷어 내고, 자리를 잡는다
static func start(c: Dictionary, id: String) -> bool:
	if can_start(c, id) != "":
		return false
	var m := mega(id)
	var plan: CityPlan = c["plan"]
	var sim: CitySim = c["sim"]
	var cell := site_for(plan)
	var stage0: Dictionary = (m["stages"] as Array)[0]
	_pay(sim, stage0["cost"])
	plan.clear_parcel_roads(cell)
	plan.mega.append({"id": id, "cell": cell, "stage": 0, "p": 0.0})
	plan.mega_rev += 1
	plan._touch()
	sim.note("메가프로젝트 — %s를 짓기 시작했다 (%s, %d단계)" % [String(m["name"]), String(stage0["name"]), (m["stages"] as Array).size()], "build")
	return true


## 하루만큼: 단계의 공정이 다 되면 다음 단계 값을 낸다 (모자라면 기다린다). 다 지으면 효과를 남긴다
static func advance(c: Dictionary) -> void:
	var plan: CityPlan = c["plan"]
	var sim: CitySim = c["sim"]
	for w in plan.mega.duplicate():
		var m := mega(String(w["id"]))
		if m.is_empty():
			plan.mega.erase(w)
			continue
		var stages: Array = m["stages"]
		var st: Dictionary = stages[int(w["stage"])]
		if float(w["p"]) < 1.0:
			w["p"] = minf(1.0, float(w["p"]) + 1.0 / maxf(float(st["days"]), 1.0))
			continue
		if int(w["stage"]) + 1 < stages.size():
			var nxt: Dictionary = stages[int(w["stage"]) + 1]
			if not sim.can_afford(nxt["cost"], 40.0):
				continue                  # 자재를 기다린다
			_pay(sim, nxt["cost"])
			w["stage"] = int(w["stage"]) + 1
			w["p"] = 0.0
			plan.mega_rev += 1
			sim.note("메가프로젝트 — %s: %s" % [String(m["name"]), String(nxt["name"])], "build")
			continue
		plan.mega.erase(w)
		plan.mega_rev += 1
		(state(c)["built"] as Array).append(String(w["id"]))
		plan.mega_done.append({"id": String(w["id"]), "cell": w["cell"]})
		plan._touch()
		apply_effects(c)
		sim.note("완공 — 메가프로젝트 %s (%s)" % [String(m["name"]), effect_text(m.get("effect", {}))], "good")


## 다 지은 메가프로젝트의 효과를 모아 시뮬레이션 보정의 mega 몫으로
static func apply_effects(c: Dictionary) -> void:
	var sum := {"housing_add": 0.0, "morale": 0.0, "support_day": 0.0, "rp_day": 0.0, "build_k": 1.0}
	for id in state(c)["built"]:
		var ef: Dictionary = mega(String(id)).get("effect", {})
		sum["housing_add"] += float(ef.get("housing", 0.0))
		sum["morale"] += float(ef.get("morale", 0.0))
		sum["support_day"] += float(ef.get("support_day", 0.0))
		sum["rp_day"] += float(ef.get("rp_day", 0.0))
		sum["build_k"] *= float(ef.get("build_k", 1.0))
	CityExt.set_part(c, "mega", sum)


static func effect_text(ef: Dictionary) -> String:
	var parts := PackedStringArray()
	if ef.has("housing"):
		parts.append("집 +%d" % int(ef["housing"]))
	if ef.has("morale"):
		parts.append("사기 +%d" % int(ef["morale"]))
	if ef.has("support_day"):
		parts.append("지원 점수 +%d/일" % int(ef["support_day"]))
	if ef.has("rp_day"):
		parts.append("연구 +%d RP/일" % int(ef["rp_day"]))
	if ef.has("build_k"):
		parts.append("로봇 작업량 ×%.2f" % float(ef["build_k"]))
	return " · ".join(parts)


static func _pay(sim: CitySim, cost: Dictionary) -> void:
	for key in cost:
		sim.stock[key] = float(sim.stock.get(key, 0.0)) - float(cost[key])
