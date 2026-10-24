class_name CityResearch
extends RefCounted
## 연구 갈림길과 돌파 카드 (자료: data/city_research.json). 시뮬레이션 밖의 규칙이다 — 모든 도시에 (직접 운영도).
##   갈림길: 연구한 기술이 at가지가 되면 두 방향 가운데 하나를 고른다 (한 번 고르면 그대로). 직접 운영은 연구 탭에서 고를 때까지
##           기다리고, 자동 운영은 발전 모드의 무게(mode_weights)로 셈해 스스로 고른다
##   돌파 카드: 기술 하나를 알아낼 때마다 chance의 확률로 (도시와 기술 수로 정해지는 난수 — 다시 해도 같다) 아직 없는 카드 셋을
##           뽑는다. 하나를 고를 때까지 다음 카드는 뽑지 않는다 (직접 운영은 연구 탭, 자동 운영은 스스로)
## 고른 방향·카드의 효과를 모아 CityExt의 research 몫으로 건넨다. 상태는 c["research"]에 있고 저장된다

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_research.json"))
		_data = parsed if parsed is Dictionary else {"branches": [], "cards": [], "mode_weights": {}}
	return _data


static func state(c: Dictionary) -> Dictionary:
	if not c.get("research") is Dictionary:
		c["research"] = {"branches": {}, "cards": [], "pending": [], "techs": (c["sim"] as CitySim).techs.size()}
	return c["research"]


static func card(id: String) -> Dictionary:
	for cd in data()["cards"]:
		if String(cd["id"]) == id:
			return cd
	return {}


static func option(id: String) -> Dictionary:
	for br in data()["branches"]:
		for o in br["options"]:
			if String(o["id"]) == id:
				return o
	return {}


## 고르기를 기다리는 갈림길의 번호 (없으면 -1)
static func branch_due(c: Dictionary) -> int:
	var st := state(c)
	var n := (c["sim"] as CitySim).techs.size()
	var brs: Array = data()["branches"]
	for i in brs.size():
		if n >= int(brs[i]["at"]) and not (st["branches"] as Dictionary).has(str(i)):
			return i
	return -1


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시): 새로 알아낸 기술마다 돌파 카드를 뽑아 보고, 자동 운영이면 고른다
static func step(c: Dictionary) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var auto := CityAuto.on(c, "research")
	var n := sim.techs.size()
	while int(st["techs"]) < n:
		st["techs"] = int(st["techs"]) + 1
		if (st["pending"] as Array).is_empty():
			_draw(c, int(st["techs"]))
		if auto and not (st["pending"] as Array).is_empty():
			var pick := String(st["pending"][0])
			for id in st["pending"]:
				if _score(c, card(String(id))["effect"]) > _score(c, card(pick)["effect"]):
					pick = String(id)
			choose_card(c, pick, true)
	var i := branch_due(c)
	if not auto:
		if i >= 0 and int(st.get("told", -1)) != i:
			st["told"] = i                  # 한 번만 알린다
			sim.note("연구 갈림길 — %s: 연구 탭에서 방향을 고른다" % String(data()["branches"][i]["name"]), "good")
		return
	while i >= 0:
		var opts: Array = data()["branches"][i]["options"]
		var best: Dictionary = opts[0]
		for o in opts:
			if _score(c, o["effect"]) > _score(c, best["effect"]):
				best = o
		choose_branch(c, i, String(best["id"]), true)
		i = branch_due(c)


## n번째 기술을 알아냈을 때: chance의 확률로 아직 없는 카드 셋을 뽑아 기다린다
static func _draw(c: Dictionary, n: int) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, String(c.get("site", sim.site_id)), n])
	if rng.randf() >= float(data().get("chance", 0.35)):
		return
	var pool: Array = []
	for cd in data()["cards"]:
		if not String(cd["id"]) in st["cards"]:
			pool.append(String(cd["id"]))
	var pick: Array = []
	while pick.size() < 3 and not pool.is_empty():
		pick.append(pool.pop_at(rng.randi() % pool.size()))
	if pick.is_empty():
		return
	st["pending"] = pick
	if not CityAuto.on(c, "research"):
		sim.note("돌파 — 연구에서 새 길이 셋 열렸다. 연구 탭에서 하나를 고른다", "good")


## 자동 운영이 고를 때의 점수: 발전 모드의 무게 × 효과 크기 (배율은 (배율 − 1) × 100)
static func _score(c: Dictionary, ef: Dictionary) -> float:
	var w: Dictionary = data()["mode_weights"].get(String(c.get("mode", "")), {})
	var s := 0.0
	for k in ef:
		var v := float(ef[k])
		var mag := (v - 1.0) * 100.0 if k in CityExt.MUL else (v * 0.02 if k == "housing_add" else v)
		s += mag * float(w.get(k, 1.0))
	return s


static func choose_branch(c: Dictionary, i: int, id: String, auto := false) -> bool:
	var st := state(c)
	if branch_due(c) != i or option(id).is_empty():
		return false
	(st["branches"] as Dictionary)[str(i)] = id
	apply(c)
	if auto:
		CityAuto.record(c, "research", "갈림길 — %s: %s (%s): 발전 모드에 가장 맞는 효과" % [String(data()["branches"][i]["name"]),
			String(option(id)["name"]), effect_text(option(id)["effect"])])
	(c["sim"] as CitySim).note("%s갈림길 — %s: %s (%s)" % ["자동 운영 · " if auto else "", String(data()["branches"][i]["name"]),
		String(option(id)["name"]), effect_text(option(id)["effect"])], "info" if auto else "good")
	return true


static func choose_card(c: Dictionary, id: String, auto := false) -> bool:
	var st := state(c)
	if not id in st["pending"]:
		return false
	(st["cards"] as Array).append(id)
	st["pending"] = []
	apply(c)
	if auto:
		CityAuto.record(c, "research", "돌파 카드 — %s (%s): 셋 가운데 발전 모드에 가장 맞는 것" % [String(card(id)["name"]),
			effect_text(card(id)["effect"])])
	(c["sim"] as CitySim).note("%s돌파 카드 — %s: %s" % ["자동 운영 · " if auto else "", String(card(id)["name"]), effect_text(card(id)["effect"])],
		"info" if auto else "good")
	return true


## 고른 방향·카드의 효과를 모아 시뮬레이션 보정의 research 몫으로
static func apply(c: Dictionary) -> void:
	var st := state(c)
	var sum := {}
	var efs: Array = []
	for k in st["branches"]:
		efs.append(option(String(st["branches"][k])).get("effect", {}))
	for id in st["cards"]:
		efs.append(card(String(id)).get("effect", {}))
	for ef in efs:
		for k in ef:
			if k in CityExt.MUL:
				sum[k] = float(sum.get(k, 1.0)) * float(ef[k])
			else:
				sum[k] = float(sum.get(k, 0.0)) + float(ef[k])
	CityExt.set_part(c, "research", sum)


static func effect_text(ef: Dictionary) -> String:
	var names := {"morale": "사기", "support_day": "지원 점수/일", "rp_day": "연구 RP/일", "housing_add": "집",
		"work_k": "일하는 효율", "make_k": "만드는 효율", "build_k": "로봇 작업량", "rp_k": "연구"}
	var parts := PackedStringArray()
	for k in ef:
		var v := float(ef[k])
		if k in CityExt.MUL:
			parts.append("%s ×%.2f" % [names.get(k, k), v])
		else:
			parts.append("%s %s%s" % [names.get(k, k), "+" if v >= 0.0 else "−", str(snappedf(absf(v), 0.1)).trim_suffix(".0")])
	return " · ".join(parts)
