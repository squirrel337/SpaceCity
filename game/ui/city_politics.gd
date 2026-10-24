class_name CityPolitics
extends RefCounted
## 정착민 정치 (자료: data/city_politics.json). 시뮬레이션 밖의 규칙이다 — 모든 도시에.
##   모임 넷 (기술자 연합 · 과학 위원회 · 공유지 연합 · 지구 우호회): 지지(0~100)가 날마다 목표 쪽으로 drift만큼 다가간다.
##     목표 = 50 + 정책의 반응 + 도시 형편 (사기·신뢰, 부품이 바닥, 지난 180일의 기술·보낸 계약, 지난 365일의 사망, 짓는 일, 탐사 발견)
##   평의회 정책 넷 (근무 시간 · 연구 지원 · 지구 홍보 · 안전 규정): 세 칸 가운데 하나 — 고른 칸의 보정이 CityExt의 politics 몫으로
##   회기 (session_days마다): 평균 지지가 support_at 넘으면 사기·신뢰가 오르고 unrest_at 아래면 내린다. 지지가 strike_at 아래인 모임은
##     strike_days 동안 파업한다 (일하는 효율 strike_k)
## 직접 운영은 개척 탭의 '평의회'에서 정책을 고른다. 자동 운영(또는 정치를 맡긴 도시 — CityAuto)은 발전 모드로 고르고, 회기 앞에
## 가장 불만인 모임이 싫어하는 칸을 바꾼다.
## 상태는 c["politics"]: {policy: {정책: 칸}, approval: {모임: 지지}, next(날), strike: {faction, until}, events: {tech, contract, death:
##   [날…]}, seen: {techs, done, deaths}, last: {day, mean, result}}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_politics.json"))
		_data = parsed if parsed is Dictionary else {"factions": [], "policies": []}
	return _data


static func policy(id: String) -> Dictionary:
	for p in data()["policies"]:
		if String(p["id"]) == id:
			return p
	return {}


static func faction(id: String) -> Dictionary:
	for f in data()["factions"]:
		if String(f["id"]) == id:
			return f
	return {}


static func state(c: Dictionary) -> Dictionary:
	if not c.get("politics") is Dictionary:
		var sim: CitySim = c["sim"]
		var pol := {}
		for p in data()["policies"]:
			pol[String(p["id"])] = int(p.get("default", 1))
		var ap := {}
		for f in data()["factions"]:
			ap[String(f["id"])] = 50.0
		c["politics"] = {"policy": pol, "approval": ap, "next": sim.current_day() + int(data().get("session_days", 120)),
			"strike": {}, "events": {"tech": [], "contract": [], "death": []},
			"seen": {"techs": sim.techs.size(), "done": 0, "deaths": _deaths(sim)}, "last": {}}
		apply(c)
	return c["politics"]


static func _deaths(sim: CitySim) -> int:
	var n := 0
	for v in sim.deaths.values():
		n += int(v)
	return n


## 지난 n일 안의 일 수
static func _recent(st: Dictionary, key: String, day: int, within: int) -> int:
	return (st["events"][key] as Array).filter(func(d): return day - int(d) <= within).size()


## 모임의 지지 목표 (정책 반응 + 도시 형편)
static func target(c: Dictionary, fid: String, day: int) -> float:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var f := faction(fid)
	var t := 50.0
	for p in data()["policies"]:
		var opt: Dictionary = p["options"][int(st["policy"].get(String(p["id"]), 1))]
		t += float(opt.get("likes", {}).get(fid, 0.0))
	var terms: Dictionary = f.get("terms", {})
	t += float(terms.get("morale", 0.0)) * (sim.morale - 60.0)
	t += float(terms.get("trust", 0.0)) * (sim.trust - 60.0)
	if float(sim.stock.get("parts", 0.0)) < 60.0:
		t += float(terms.get("parts_low", 0.0))
	if not sim.queue.is_empty():
		t += float(terms.get("queue", 0.0))
	if sim.housing_cap > 0.0 and sim.population() > sim.housing_cap * 0.95:
		t += float(terms.get("crowded", 0.0))
	t += float(terms.get("tech", 0.0)) * _recent(st, "tech", day, 180)
	t += float(terms.get("contract", 0.0)) * mini(_recent(st, "contract", day, 180), 10)
	t += float(terms.get("death", 0.0)) * _recent(st, "death", day, 365)
	if terms.has("finds"):
		var n := 0
		for s in CityExplore.state(c)["sites"]:
			if String(s["state"]) == "found" and String(s["find"]) != "nothing":
				n += 1
		t += float(terms["finds"]) * mini(n, 10)
	return clampf(t, 0.0, 100.0)


static func mean(c: Dictionary) -> float:
	var ap: Dictionary = state(c)["approval"]
	var s := 0.0
	for k in ap:
		s += float(ap[k])
	return s / maxf(ap.size(), 1.0)


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시): 일을 세고, 지지를 움직이고, 파업이 끝났는지, 회기 날이면 회기
static func step(c: Dictionary, day: int) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var d := data()
	var seen: Dictionary = st["seen"]
	# 일 세기 (기술·보낸 계약·사망 — 날짜만 남긴다)
	if sim.techs.size() > int(seen["techs"]):
		for _i in sim.techs.size() - int(seen["techs"]):
			(st["events"]["tech"] as Array).append(day)
		seen["techs"] = sim.techs.size()
	var done := int(CityTrade.state(c)["done"])
	if done > int(seen["done"]):
		for _i in mini(done - int(seen["done"]), 10):
			(st["events"]["contract"] as Array).append(day)
		seen["done"] = done
	var dn := _deaths(sim)
	if dn > int(seen["deaths"]):
		for _i in mini(dn - int(seen["deaths"]), 10):
			(st["events"]["death"] as Array).append(day)
		seen["deaths"] = dn
	for key in ["tech", "contract", "death"]:
		st["events"][key] = (st["events"][key] as Array).filter(func(x): return day - int(x) <= 365)
	# 지지
	var drift := float(d.get("drift", 0.08))
	for f in d["factions"]:
		var fid := String(f["id"])
		var a := float(st["approval"].get(fid, 50.0))
		st["approval"][fid] = snappedf(a + (target(c, fid, day) - a) * drift, 0.01)
	var stk: Dictionary = st["strike"]
	if not stk.is_empty() and day >= int(stk["until"]):
		st["strike"] = {}
		sim.note("파업이 끝났다 — %s이(가) 일터로 돌아왔다" % String(faction(String(stk["faction"])).get("name", "")), "info")
		apply(c)
	# 자동 운영(또는 맡긴 도시): 발전 모드의 정책, 회기 열흘 앞에 가장 불만인 모임을 달랜다
	if CityAuto.on(c, "politics"):
		_auto(c, day)
	if day >= int(st["next"]):
		session(c, day)


## 평의회 회기: 평균 지지로 사기·신뢰, 지지가 바닥인 모임은 파업
static func session(c: Dictionary, day: int) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var d := data()
	st["next"] = day + int(d.get("session_days", 120))
	var m := mean(c)
	var result := "보통"
	var eff: Dictionary = {}
	if m >= float(d.get("support_at", 60)):
		result = "지지"
		eff = d["session"]["good"]
	elif m < float(d.get("unrest_at", 40)):
		result = "불만"
		eff = d["session"]["bad"]
	sim.morale = clampf(sim.morale + float(eff.get("morale", 0.0)), 0.0, 100.0)
	sim.trust = clampf(sim.trust + float(eff.get("trust", 0.0)), 0.0, 100.0)
	var low := ""
	var low_a := INF
	for fid in st["approval"]:
		if float(st["approval"][fid]) < low_a:
			low_a = float(st["approval"][fid])
			low = String(fid)
	var text := "평의회 회기 — 평균 지지 %d: %s" % [int(round(m)), result]
	if result != "보통":
		text += " (사기 %s, 신뢰 %s)" % [_sign(float(eff.get("morale", 0.0))), _sign(float(eff.get("trust", 0.0)))]
	if low_a < float(d.get("strike_at", 25)) and (st["strike"] as Dictionary).is_empty():
		st["strike"] = {"faction": low, "until": day + int(d.get("strike_days", 15))}
		text += ". %s이(가) 파업에 들어갔다 — %d일 동안 일하는 효율 ×%s" % [String(faction(low)["name"]), int(d.get("strike_days", 15)),
			str(d.get("strike_k", 0.88))]
		apply(c)
	st["last"] = {"day": day, "mean": snappedf(m, 0.1), "result": result}
	sim.note(text, "good" if result == "지지" else ("warn" if result == "불만" or not (st["strike"] as Dictionary).is_empty() else "info"))


static func _sign(v: float) -> String:
	return ("+" if v >= 0.0 else "−") + str(snappedf(absf(v), 0.1)).trim_suffix(".0")


## 정책 칸을 바꾼다 (직접 운영 — 개척 탭, 자동 운영). 바꿨으면 true
static func set_policy(c: Dictionary, id: String, option: int, auto := false) -> bool:
	var st := state(c)
	var p := policy(id)
	if p.is_empty() or option < 0 or option >= (p["options"] as Array).size() or int(st["policy"].get(id, 1)) == option:
		return false
	st["policy"][id] = option
	apply(c)
	var text := "평의회 정책 — %s: %s (%s)" % [String(p["name"]), String(p["options"][option]["name"]),
		CityResearch.effect_text(p["options"][option]["effect"]) if not (p["options"][option]["effect"] as Dictionary).is_empty() else "보정 없음"]
	(c["sim"] as CitySim).note(("자동 운영 · " if auto else "") + text, "info")
	if auto:
		CityAuto.record(c, "politics", text)
	return true


## 자동 운영: 발전 모드의 정책 (mode_policy — 없으면 보통), 회기 열흘 앞에 가장 불만인 모임이 가장 싫어하는 칸을 보통으로
static func _auto(c: Dictionary, day: int) -> void:
	var st := state(c)
	var want: Dictionary = data().get("mode_policy", {}).get(String(c.get("mode", "")), {})
	if int(st["next"]) - day == 10:
		var low := ""
		var low_a := INF
		for fid in st["approval"]:
			if float(st["approval"][fid]) < low_a:
				low_a = float(st["approval"][fid])
				low = String(fid)
		if low_a < float(data().get("unrest_at", 40)):
			var worst := ""
			var worst_v := 0.0
			for p in data()["policies"]:
				var opt: Dictionary = p["options"][int(st["policy"].get(String(p["id"]), 1))]
				var v := float(opt.get("likes", {}).get(low, 0.0))
				if v < worst_v:
					worst_v = v
					worst = String(p["id"])
			if worst != "" and set_policy(c, worst, 1, true):
				st["calm"] = {"policy": worst, "until": day + int(data().get("session_days", 120))}
				CityAuto.record(c, "politics", "%s의 불만을 달랬다 (지지 %d)" % [String(faction(low)["name"]), int(round(low_a))])
		return
	var calm: Dictionary = st.get("calm", {})
	for p in data()["policies"]:
		var id := String(p["id"])
		if not calm.is_empty() and String(calm["policy"]) == id and day < int(calm["until"]):
			continue                                  # 달랜 정책은 다음 회기까지 그대로
		set_policy(c, id, int(want.get(id, int(p.get("default", 1)))), true)


## 결정이 모임의 지지를 바로 움직인다 (대피소 추첨 같은 결정 카드)
static func nudge(c: Dictionary, fid: String, delta: float) -> void:
	var st := state(c)
	if st["approval"].has(fid):
		st["approval"][fid] = clampf(float(st["approval"][fid]) + delta, 0.0, 100.0)


## 고른 칸의 보정과 파업을 모아 시뮬레이션 보정의 politics 몫으로
static func apply(c: Dictionary) -> void:
	var st: Dictionary = c["politics"]
	var sum := {}
	for p in data()["policies"]:
		var ef: Dictionary = p["options"][int(st["policy"].get(String(p["id"]), 1))]["effect"]
		for k in ef:
			if k in CityExt.MUL:
				sum[k] = float(sum.get(k, 1.0)) * float(ef[k])
			else:
				sum[k] = float(sum.get(k, 0.0)) + float(ef[k])
	if not (st["strike"] as Dictionary).is_empty():
		sum["work_k"] = float(sum.get("work_k", 1.0)) * float(data().get("strike_k", 0.88))
	CityExt.set_part(c, "politics", sum)
