class_name Orbital
extends RefCounted
## 매스 드라이버와 L5 궤도 도시 (자료 system_l5.json). 시뮬레이션 밖의 규칙이다.
## 매스 드라이버: 고향이 메가프로젝트 '질량 투사기'를 다 지었으면 날마다 고향의 레골리스(남길 500 t을 빼고)를 300 t까지
##   추진제 없이 쏘아 올린다 — 포획기가 있어야 쏘고, 98%가 L5에 잡힌다. 도시가 서기 전에는 L5의 더미(stock_t)에 모으고
##   (남은 단계가 쓸 만큼까지), 선 뒤에는 L5 도시의 레골리스 비축을 4,000 t까지 채운다 (L5에는 팔 땅이 없다 — dig_k 0).
## L5 사업: 매스 드라이버·회전 거주구 기술을 알고 질량 투사기를 다 지었으면 네 단계 — 질량 포획기 → 차폐 껍질 → 회전 원통 →
##   거울과 첫 마을. 단계마다 L5에 모은 레골리스를 쓰고 고향이 값(지원 점수·부품·금속)을 내고 days일 짓는다. 고향의 메가프로젝트를
##   시드가 맡으면(자동 운영) 값 + 남길 몫이 있을 때 스스로 시작한다. 마지막 단계가 끝나면 L5 부지(l5_island)에 도시가 서고,
##   고향 ↔ L5 셔틀 노선이 생긴다 (Transport.rebuild).
## 상태 Colonies.orbital: {stage(다음에 지을·짓는 단계), building, ready(시), stock_t, sent_t, caught_t, fed_t, last_t(오늘 쏜 양),
##   days_fired, founded(도시를 세운 시 — 아니면 −1), why(쏘지 못한 까닭), log: [[시, 글]]} — 저장된다

const PATH := "res://data/system_l5.json"
const LOG_KEEP := 20

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func stages() -> Array:
	return data().get("project", {}).get("stages", [])


static func site_id() -> String:
	return String(data().get("project", {}).get("site", "l5_island"))


static func state(col: Colonies) -> Dictionary:
	if not col.orbital.has("stage"):
		start(col)
	return col.orbital


static func start(col: Colonies) -> void:
	col.orbital = {"stage": 0, "building": false, "ready": 0, "stock_t": 0.0, "sent_t": 0.0, "caught_t": 0.0, "fed_t": 0.0,
		"last_t": 0.0, "days_fired": 0, "founded": -1, "why": "", "log": []}


static func load_state(col: Colonies, d: Variant) -> void:
	start(col)
	if not (d is Dictionary and (d as Dictionary).has("stage")):
		# 옛 저장: L5 도시가 이미 있으면 다 지은 것으로
		if col.index_of_site(site_id()) >= 0:
			col.orbital["stage"] = stages().size()
			col.orbital["founded"] = 0
		return
	var src: Dictionary = d
	var st := col.orbital
	st["stage"] = clampi(int(src.get("stage", 0)), 0, stages().size())
	st["building"] = bool(src.get("building", false)) and int(st["stage"]) < stages().size()
	st["ready"] = int(src.get("ready", 0))
	for k in ["stock_t", "sent_t", "caught_t", "fed_t", "last_t"]:
		st[k] = float(src.get(k, 0.0))
	st["days_fired"] = int(src.get("days_fired", 0))
	st["founded"] = int(src.get("founded", -1))
	st["why"] = String(src.get("why", ""))
	for e in src.get("log", []) if src.get("log") is Array else []:
		if e is Array and (e as Array).size() >= 2:
			(st["log"] as Array).append([int(e[0]), String(e[1])])


static func _log(col: Colonies, text: String) -> void:
	var lg: Array = state(col)["log"]
	lg.append([col.hour, text])
	while lg.size() > LOG_KEEP:
		lg.remove_at(0)


# ── 조건 ────────────────────────────────────────────────────────
## 고향이 질량 투사기를 다 지었나
static func driver_built(col: Colonies) -> bool:
	var h := col.home()
	if h.is_empty():
		return false
	return (CityProgress.state(h)["built"] as Array).has(String(data().get("driver", {}).get("mega", "mass_driver")))


static func done(col: Colonies) -> bool:
	return int(state(col)["stage"]) >= stages().size()


## L5 도시 (없으면 −1)
static func city_index(col: Colonies) -> int:
	return col.index_of_site(site_id())


## 사업이 열리지 않았으면 그 까닭 (기술 · 질량 투사기)
static func lock_reason(col: Colonies) -> String:
	var known := col.known_techs()
	var miss := PackedStringArray()
	for t in data().get("project", {}).get("requires", []):
		if not known.has(String(t)):
			miss.append(Fleet.tech_name(String(t)))
	if not miss.is_empty():
		return "%s 기술이 있어야 한다" % " · ".join(miss)
	if not driver_built(col):
		return "고향에 메가프로젝트 '%s'를 먼저 지어야 한다" % String(CityProgress.mega(String(data()["driver"]["mega"])).get("name", "질량 투사기"))
	return ""


static func _stock_cost(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		if String(k) != "support":
			out[k] = float(cost[k])
	return out


## 다음 단계를 시작할 수 없으면 그 까닭 ("" = 시작할 수 있다)
static func build_reason(col: Colonies) -> String:
	var st := state(col)
	if done(col):
		return "다 지었다"
	if bool(st["building"]):
		return "%s 짓는 중" % String(stages()[int(st["stage"])]["name"])
	var lock := lock_reason(col)
	if lock != "":
		return lock
	var sg: Dictionary = stages()[int(st["stage"])]
	var need := float(sg.get("regolith_t", 0.0))
	if float(st["stock_t"]) + 0.5 < need:
		return "L5에 모은 레골리스가 모자란다 (%s / %s t)" % [Fmt.n(float(st["stock_t"])), Fmt.n(need)]
	var h := col.home()
	var sim: CitySim = h["sim"]
	var cost: Dictionary = sg.get("cost", {})
	if sim.support < float(cost.get("support", 0.0)):
		return "고향의 지원 점수가 모자란다 (%s / %s)" % [Fmt.n(sim.support), Fmt.n(float(cost["support"]))]
	if not sim.can_afford(_stock_cost(cost), 0.0):
		return "고향의 자재가 모자란다 (%s)" % cost_text(cost)
	return ""


static func cost_text(cost: Dictionary) -> String:
	var bits := PackedStringArray()
	if float(cost.get("support", 0.0)) > 0.0:
		bits.append("지원 %s" % Fmt.n(float(cost["support"])))
	if float(cost.get("parts", 0.0)) > 0.0:
		bits.append("부품 %s" % Fmt.n(float(cost["parts"])))
	if float(cost.get("metal_t", 0.0)) > 0.0:
		bits.append("금속 %s t" % Fmt.n(float(cost["metal_t"])))
	return " · ".join(bits)


## 다음 단계를 시작한다 (값을 낸다). 못 하면 까닭
static func build(col: Colonies, auto := false) -> String:
	var why := build_reason(col)
	if why != "":
		return why
	var st := state(col)
	var sg: Dictionary = stages()[int(st["stage"])]
	var sim: CitySim = col.home()["sim"]
	var cost: Dictionary = sg.get("cost", {})
	sim.support -= float(cost.get("support", 0.0))
	for k in _stock_cost(cost):
		sim.stock[k] = float(sim.stock.get(k, 0.0)) - float(cost[k])
	st["stock_t"] = maxf(0.0, float(st["stock_t"]) - float(sg.get("regolith_t", 0.0)))
	st["building"] = true
	st["ready"] = col.hour + int(sg.get("days", 30)) * 24
	var text := "%sL5 사업 — %d단계 %s 짓기 시작 (%s%s), %s 완공" % ["자동 운영: " if auto else "", int(st["stage"]) + 1, String(sg["name"]),
		cost_text(cost), (" · 레골리스 %s t" % Fmt.n(float(sg["regolith_t"]))) if float(sg.get("regolith_t", 0.0)) > 0.0 else "",
		col.date_text(float(st["ready"]))]
	_log(col, text)
	sim.note(text, "build")
	return ""


# ── 하루 (Colonies.step) ────────────────────────────────────────
static func step_day(col: Colonies) -> void:
	var st := state(col)
	var h := col.home()
	if h.is_empty():
		return
	_fire(col, h["sim"])
	if bool(st["building"]) and col.hour >= int(st["ready"]):
		var sg: Dictionary = stages()[int(st["stage"])]
		st["building"] = false
		st["stage"] = int(st["stage"]) + 1
		var text := "L5 사업 — %d단계 %s 완공" % [int(st["stage"]), String(sg["name"])]
		_log(col, text)
		(h["sim"] as CitySim).note(text, "good")
		if done(col) and city_index(col) < 0:
			_found(col)
	if not bool(st["building"]) and not done(col) and CityAuto.on(h, "mega") and _rich(col):
		build(col, true)


## 자동 운영이 단계를 시작할 만큼 넉넉한가 (값 + 남길 몫)
static func _rich(col: Colonies) -> bool:
	if build_reason(col) != "":
		return false
	var sim: CitySim = col.home()["sim"]
	var sg: Dictionary = stages()[int(state(col)["stage"])]
	var cost: Dictionary = sg.get("cost", {})
	var res: Dictionary = data().get("project", {}).get("auto_reserve", {})
	return sim.support >= float(cost.get("support", 0.0)) + float(res.get("support", 600.0)) \
		and float(sim.stock["parts"]) >= float(cost.get("parts", 0.0)) + float(res.get("parts", 200.0))


## 오늘 쏠 수 있는 양과 받을 곳: 포획기가 있고 고향에 남길 몫 넘는 레골리스가 있으면 — 도시 전에는 남은 단계가 쓸 만큼까지,
## 뒤에는 L5 도시의 비축이 feed_t가 될 때까지
static func _fire(col: Colonies, home: CitySim) -> void:
	var st := state(col)
	st["last_t"] = 0.0
	if not driver_built(col):
		st["why"] = "질량 투사기가 없다"
		return
	if int(st["stage"]) < 1:
		st["why"] = "L5에 질량 포획기가 아직 없다"
		return
	var dv: Dictionary = data().get("driver", {})
	var room := 0.0
	var ci := city_index(col)
	var catch_k := float(dv.get("catch_k", 0.98))
	if ci >= 0:
		var l5: CitySim = col.list[ci]["sim"]
		room = maxf(0.0, float(dv.get("feed_t", 4000.0)) - float(l5.stock["regolith_t"]))
	else:
		var left := 0.0
		for i in range(int(st["stage"]), stages().size()):
			if i == int(st["stage"]) and bool(st["building"]):
				continue                                  # 짓는 단계의 몫은 이미 썼다
			left += float(stages()[i].get("regolith_t", 0.0))
		room = maxf(0.0, left - float(st["stock_t"]))
	var have := maxf(0.0, float(home.stock["regolith_t"]) - float(dv.get("keep_t", 500.0)))
	var shot := minf(minf(float(dv.get("rate_t", 300.0)), have), room / maxf(catch_k, 1e-6))
	shot = floorf(shot)
	if shot <= 0.0:
		st["why"] = "쏠 레골리스가 없다 (고향 %s t, 남길 몫 %s t)" % [Fmt.n(float(home.stock["regolith_t"])), Fmt.n(float(dv.get("keep_t", 500.0)))] \
			if room >= 1.0 else ("L5 도시의 레골리스가 넉넉하다" if ci >= 0 else "남은 단계가 쓸 레골리스를 다 모았다")
		return
	home.stock["regolith_t"] = float(home.stock["regolith_t"]) - shot
	var caught := shot * catch_k
	st["sent_t"] = float(st["sent_t"]) + shot
	st["caught_t"] = float(st["caught_t"]) + caught
	st["last_t"] = shot
	st["days_fired"] = int(st["days_fired"]) + 1
	st["why"] = ""
	if ci >= 0:
		var l5b: CitySim = col.list[ci]["sim"]
		l5b.stock["regolith_t"] = float(l5b.stock["regolith_t"]) + caught
		st["fed_t"] = float(st["fed_t"]) + caught
	else:
		st["stock_t"] = float(st["stock_t"]) + caught


## 마지막 단계가 끝났다: L5 부지에 도시를 세우고 노선을 다시 짠다
static func _found(col: Colonies) -> void:
	var st := state(col)
	var sid := site_id()
	var c := col._found_at(sid, col.hour, col._seed_for(sid))
	var s: CitySim = c["sim"]
	st["founded"] = col.hour
	s.note("관리 기록 — %s 완공. 천체 밖의 첫 도시 — 지구와 달에서 온 첫 주민 %d명이 회전 원통의 1 g 바닥에 내렸다. 시드가 자동 운영으로 돌본다." % [
		c["name"], int(s.population())], "milestone")
	var text := "L5 사업 완공 — %s에 첫 궤도 도시가 섰다 (주민 %d명). 매스 드라이버가 이제 그 도시에 레골리스를 보낸다" % [c["name"], int(s.population())]
	_log(col, text)
	(col.home()["sim"] as CitySim).note(text, "milestone")
	col.transport.rebuild(col)


# ── 글 ──────────────────────────────────────────────────────────
## "2단계 차폐 껍질 짓는 중 (45%) · 2068.03.02 완공" / "다음: 3단계 회전 원통" / "다 지었다"
static func status_text(col: Colonies) -> String:
	var st := state(col)
	if done(col):
		return "다 지었다 — %s" % String(GameData.site(site_id()).get("name", "L5"))
	var sg: Dictionary = stages()[int(st["stage"])]
	if bool(st["building"]):
		var total := float(sg.get("days", 30)) * 24.0
		var pct := clampf(1.0 - float(int(st["ready"]) - col.hour) / maxf(total, 1.0), 0.0, 1.0)
		return "%d단계 %s 짓는 중 (%d%%) · %s 완공" % [int(st["stage"]) + 1, String(sg["name"]), int(pct * 100.0), col.date_text(float(st["ready"]))]
	return "다음: %d단계 %s" % [int(st["stage"]) + 1, String(sg["name"])]


## 항로 지도의 짧은 글: "2단계 짓는 중 45%" / "다음: 3단계" / "도시 120명"
static func short_text(col: Colonies) -> String:
	var st := state(col)
	var ci := city_index(col)
	if ci >= 0:
		return "%s %s명" % [String(col.list[ci].get("short", "L5")), Fmt.n((col.list[ci]["sim"] as CitySim).population())]
	if bool(st["building"]):
		var sg: Dictionary = stages()[int(st["stage"])]
		var pct := clampf(1.0 - float(int(st["ready"]) - col.hour) / maxf(float(sg.get("days", 30)) * 24.0, 1.0), 0.0, 1.0)
		return "%d단계 짓는 중 %d%%" % [int(st["stage"]) + 1, int(pct * 100.0)]
	return "다음: %d단계 %s" % [int(st["stage"]) + 1, String(stages()[mini(int(st["stage"]), stages().size() - 1)]["name"])]


## 매스 드라이버: "오늘 300 t 쏨 · L5에 모은 레골리스 12,300 t · 모두 18,200 t" / 쉬는 까닭
static func driver_text(col: Colonies) -> String:
	var st := state(col)
	if float(st["last_t"]) > 0.0:
		var where := ("L5 도시 비축으로 — 보낸 %s t" % Fmt.n(float(st["fed_t"]))) if city_index(col) >= 0 else \
			("L5에 모은 레골리스 %s t" % Fmt.n(float(st["stock_t"])))
		return "매스 드라이버 — 오늘 %s t 쏨 · %s · 모두 %s t" % [Fmt.n(float(st["last_t"])), where, Fmt.n(float(st["sent_t"]))]
	var why := String(st["why"])
	if not driver_built(col):
		why = "질량 투사기가 없다"
	elif int(st["stage"]) < 1:
		why = "L5에 질량 포획기가 아직 없다"
	elif why == "질량 투사기가 없다" or why == "L5에 질량 포획기가 아직 없다":
		why = ""                                         # 어제의 까닭 — 오늘은 아직 셈하지 않았다
	return "매스 드라이버 — 쉰다: %s%s" % [why if why != "" else "아직 쏘지 않았다",
		(" · L5에 모은 레골리스 %s t" % Fmt.n(float(st["stock_t"]))) if float(st["stock_t"]) > 0.0 and city_index(col) < 0 else ""]


## 단계 줄: "✔ 1 질량 포획기" / "▸ 2 차폐 껍질 — 레골리스 15,000 t · 부품 300 · 금속 20 t · 120일" / "○ 3 …"
static func stage_line(col: Colonies, i: int) -> String:
	var st := state(col)
	var sg: Dictionary = stages()[i]
	var mark := "✔" if i < int(st["stage"]) else ("▸" if i == int(st["stage"]) else "○")
	if i < int(st["stage"]):
		return "%s %d · %s" % [mark, i + 1, String(sg["name"])]          # " · " — 번역기가 이름을 따로 옮긴다
	var bits := PackedStringArray()
	if float(sg.get("regolith_t", 0.0)) > 0.0:
		bits.append("레골리스 %s t" % Fmt.n(float(sg["regolith_t"])))
	var ct := cost_text(sg.get("cost", {}))
	if ct != "":
		bits.append(ct)
	bits.append("%d일" % int(sg.get("days", 30)))
	return "%s %d · %s — %s" % [mark, i + 1, String(sg["name"]), " · ".join(bits)]
