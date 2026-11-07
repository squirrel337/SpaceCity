class_name Probes
extends RefCounted
## 성간 탐사선 (자료 system_probes.json, 별 nearby_stars.json). 시뮬레이션 밖의 규칙이다.
## 메가프로젝트 '레이저 돛 발사 시설'(시대 2, 레이저 돛 기술)을 다 지은 도시가 그램급 돛 탐사선을 12.5광년 안의 이웃 별로 쏜다 —
##   값(지원 1,500 · 부품 120)은 그 도시가 내고, 레이저가 몇 분 만에 광속의 20%로 민다. 한꺼번에 셋까지, 한 별에 한 척.
##   거리 ÷ 0.2년 뒤 닿고 (프록시마 4.25광년 → 21년), 그 뒤 거리만큼 더 지나 소식이 온다 (빛의 속도 — 4년).
##   소식이 오면 그 별의 행성 정보가 열리고 (3D 별 지도의 이름표, 개척 탭) 쏜 도시가 지원 점수·연구 점수를 받는다 (행성마다 더).
## 자동 운영: 그 도시의 메가프로젝트를 시드가 맡으면 나는 탐사선이 없고 넉넉할 때 아직 모르는 가장 가까운 별로 쏜다.
## 상태 Colonies.probes: {serial, probes: [{id, name, target, from(부지), launched, arrive, report(시), state: flying·arrived}],
##   known: {별 id: 소식이 온 시}, log: [[시, 글]]} — 저장된다

const PATH := "res://data/system_probes.json"
const LOG_KEEP := 20
const HOURS_PER_YEAR := 8766.0

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func state(col: Colonies) -> Dictionary:
	if not col.probes.get("probes") is Array:
		start(col)
	return col.probes


static func start(col: Colonies) -> void:
	col.probes = {"serial": 0, "probes": [], "known": {}, "log": []}


static func load_state(col: Colonies, d: Variant) -> void:
	start(col)
	if not (d is Dictionary and (d as Dictionary).get("probes") is Array):
		return
	var src: Dictionary = d
	var st := col.probes
	st["serial"] = int(src.get("serial", 0))
	for p in src["probes"]:
		if p is Dictionary and not system(String(p.get("target", ""))).is_empty():
			(st["probes"] as Array).append({"id": int(p.get("id", 0)), "name": String(p.get("name", "")),
				"target": String(p["target"]), "from": String(p.get("from", GameData.HOME_SITE)),
				"launched": int(p.get("launched", 0)), "arrive": int(p.get("arrive", 0)), "report": int(p.get("report", 0)),
				"state": String(p.get("state", "flying"))})
	if src.get("known") is Dictionary:
		for k in src["known"]:
			st["known"][String(k)] = int(src["known"][k])
	for e in src.get("log", []) if src.get("log") is Array else []:
		if e is Array and (e as Array).size() >= 2:
			(st["log"] as Array).append([int(e[0]), String(e[1])])


static func _log(col: Colonies, text: String) -> void:
	var lg: Array = state(col)["log"]
	lg.append([col.hour, text])
	while lg.size() > LOG_KEEP:
		lg.remove_at(0)


# ── 별 ──────────────────────────────────────────────────────────
static func system(id: String) -> Dictionary:
	Astro.load_data()
	for s in Astro.systems:
		if String(s["id"]) == id:
			return s
	return {}


## 갈 수 있는 이웃 별 (가까운 차례)
static func targets() -> Array:
	Astro.load_data()
	var max_ly := float(data().get("targets", {}).get("max_ly", 12.5))
	var out: Array = Astro.systems.filter(func(s): return String(s.get("category", "")) == "neighbor" and float(s["dist_ly"]) <= max_ly)
	out.sort_custom(func(a, b): return float(a["dist_ly"]) < float(b["dist_ly"]))
	return out


static func known(col: Colonies, star: String) -> bool:
	return (state(col)["known"] as Dictionary).has(star)


static func flying_to(col: Colonies, star: String) -> Dictionary:
	for p in state(col)["probes"]:
		if String(p["target"]) == star:
			return p
	return {}


## 레이저 돛 발사 시설을 다 지은 도시 (없으면 −1 — 고향이 먼저)
static func facility_city(col: Colonies) -> int:
	var fid := String(data().get("facility", "laser_array"))
	var best := -1
	for i in col.list.size():
		if (CityProgress.state(col.list[i])["built"] as Array).has(fid):
			if best < 0 or String(col.list[i]["site"]) == GameData.HOME_SITE:
				best = i
	return best


static func years(dist_ly: float) -> float:
	return dist_ly / maxf(float(data().get("probe", {}).get("speed_c", 0.2)), 1e-3)


# ── 쏘기 ────────────────────────────────────────────────────────
## 쏠 수 없으면 까닭
static func launch_reason(col: Colonies, star: String) -> String:
	var fi := facility_city(col)
	if fi < 0:
		var known_t := col.known_techs()
		var m := CityProgress.mega(String(data().get("facility", "laser_array")))
		if not known_t.has(String(m.get("tech", "laser_sail"))):
			return "%s 기술이 있어야 한다" % Fleet.tech_name(String(m.get("tech", "laser_sail")))
		return "메가프로젝트 '%s'를 먼저 지어야 한다 (%s부터)" % [String(m.get("name", "")), CityProgress.era_name(int(m.get("era", 2)))]
	var s := system(star)
	if s.is_empty() or float(s["dist_ly"]) > float(data().get("targets", {}).get("max_ly", 12.5)):
		return "갈 수 없는 별이다"
	if known(col, star):
		return "이미 소식이 왔다"
	if not flying_to(col, star).is_empty():
		return "그 별로 가는 탐사선이 있다"
	var pd: Dictionary = data().get("probe", {})
	if (state(col)["probes"] as Array).size() >= int(pd.get("max_flying", 3)):
		return "탐사선이 이미 %d척 날고 있다" % (state(col)["probes"] as Array).size()
	var sim: CitySim = col.list[fi]["sim"]
	var cost: Dictionary = pd.get("cost", {})
	if sim.support < float(cost.get("support", 0.0)):
		return "지원 점수가 모자란다 (%s / %s)" % [Fmt.n(sim.support), Fmt.n(float(cost["support"]))]
	if float(sim.stock["parts"]) < float(cost.get("parts", 0.0)):
		return "부품이 모자란다 (%s / %s)" % [Fmt.n(float(sim.stock["parts"])), Fmt.n(float(cost["parts"]))]
	return ""


static func launch(col: Colonies, star: String, auto := false) -> String:
	var why := launch_reason(col, star)
	if why != "":
		return why
	var st := state(col)
	var fi := facility_city(col)
	var c: Dictionary = col.list[fi]
	var sim: CitySim = c["sim"]
	var pd: Dictionary = data().get("probe", {})
	var cost: Dictionary = pd.get("cost", {})
	sim.support -= float(cost.get("support", 0.0))
	sim.stock["parts"] = float(sim.stock["parts"]) - float(cost.get("parts", 0.0))
	st["serial"] = int(st["serial"]) + 1
	var names: Array = pd.get("names", [])
	var name := String(names[(int(st["serial"]) - 1) % maxi(names.size(), 1)]) if not names.is_empty() else "탐사선 %d" % int(st["serial"])
	var s := system(star)
	var fly_h := int(round(years(float(s["dist_ly"])) * HOURS_PER_YEAR))
	var p := {"id": int(st["serial"]), "name": name, "target": star, "from": String(c["site"]), "launched": col.hour,
		"arrive": col.hour + fly_h, "report": col.hour + fly_h + int(round(float(s["dist_ly"]) * HOURS_PER_YEAR)), "state": "flying"}
	(st["probes"] as Array).append(p)
	c["probes_sent"] = int(c.get("probes_sent", 0)) + 1
	var text := "%s성간 탐사선 %s 발사 — %s (%s광년)로 광속의 20%%, %s 도착 · %s 소식 (값 %s)" % ["자동 운영: " if auto else "", name,
		String(s["name"]), Fmt.n(float(s["dist_ly"]), 2), col.date_text(float(p["arrive"])), col.date_text(float(p["report"])),
		Orbital.cost_text(cost)]
	_log(col, text)
	sim.note(text, "launch")
	return ""


# ── 하루 (Colonies.step) ────────────────────────────────────────
static func step_day(col: Colonies) -> void:
	var st := state(col)
	for p in (st["probes"] as Array).duplicate():
		if String(p["state"]) == "flying" and col.hour >= int(p["arrive"]):
			p["state"] = "arrived"
			var s := system(String(p["target"]))
			var text := "%s가 %s에 닿았다 — 소식은 %s광년을 건너 %s에 온다" % [String(p["name"]), String(s.get("name", p["target"])),
				Fmt.n(float(s.get("dist_ly", 0.0)), 2), col.date_text(float(p["report"]))]
			_log(col, text)
			var c := _from(col, p)
			if not c.is_empty():
				(c["sim"] as CitySim).note(text, "info")
		if col.hour >= int(p["report"]):
			_report(col, p)
	_auto(col)


static func _from(col: Colonies, p: Dictionary) -> Dictionary:
	var i := col.index_of_site(String(p.get("from", GameData.HOME_SITE)))
	if i < 0:
		return col.home()
	return col.list[i]


## 소식이 왔다: 행성 정보가 열리고 쏜 도시가 보상을 받는다
static func _report(col: Colonies, p: Dictionary) -> void:
	var st := state(col)
	(st["probes"] as Array).erase(p)
	var star := String(p["target"])
	st["known"][star] = col.hour
	var s := system(star)
	var planets: Array = s.get("planets", [])
	var rd: Dictionary = data().get("report", {})
	var rw: Dictionary = rd.get("reward", {})
	var pp: Dictionary = rd.get("per_planet", {})
	var sup := float(rw.get("support", 0.0)) + float(pp.get("support", 0.0)) * planets.size()
	var rp := float(rw.get("rp", 0.0)) + float(pp.get("rp", 0.0)) * planets.size()
	var c := _from(col, p)
	if not c.is_empty():
		var sim: CitySim = c["sim"]
		sim.support += sup
		sim.rp_bank += rp
	var what := "알려진 행성이 없다 — 별빛과 둘레의 먼지를 쟀다"
	if not planets.is_empty():
		var names := PackedStringArray()
		for pl in planets:
			names.append(String(pl.get("name", "")))
		what = "행성 %d — %s" % [planets.size(), ", ".join(names)]
	var text := "%s의 소식 — %s: %s (지원 +%s · 연구 +%s)" % [String(p["name"]), String(s.get("name", star)), what, Fmt.n(sup), Fmt.n(rp)]
	_log(col, text)
	if not c.is_empty():
		(c["sim"] as CitySim).note(text, "milestone")


static func _auto(col: Colonies) -> void:
	var st := state(col)
	if not (st["probes"] as Array).is_empty():
		return
	var fi := facility_city(col)
	if fi < 0 or not CityAuto.on(col.list[fi], "mega"):
		return
	var sim: CitySim = col.list[fi]["sim"]
	var pd: Dictionary = data().get("probe", {})
	var cost: Dictionary = pd.get("cost", {})
	var ad: Dictionary = data().get("auto", {})
	if sim.support < float(cost.get("support", 0.0)) + float(ad.get("reserve_support", 1500.0)) \
			or float(sim.stock["parts"]) < float(cost.get("parts", 0.0)) + float(ad.get("reserve_parts", 200.0)):
		return
	for s in targets():
		if launch_reason(col, String(s["id"])) == "":
			launch(col, String(s["id"]), true)
			return


# ── 3D · 글 ─────────────────────────────────────────────────────
## 그 부지의 도시가 이틀 안에 탐사선을 쏘았나 (레이저 돛 발사 시설의 빛줄기)
static func recent_launch(col: Colonies, site: String) -> bool:
	if col.probes.is_empty():
		return false
	for p in state(col)["probes"]:
		if String(p["from"]) == site and col.hour - int(p["launched"]) < 48:
			return true
	return false


## 날고 있는 탐사선의 자리 (km, 태양 중심): 해에서 그 별까지 간 몫. 닿았으면 그 별 곁
static func position(col: Colonies, p: Dictionary, hour: float) -> PackedFloat64Array:
	var s := system(String(p["target"]))
	if s.is_empty():
		return Astro.v3(0, 0, 0)
	var k := clampf((hour - float(p["launched"])) / maxf(float(p["arrive"]) - float(p["launched"]), 1.0), 0.0, 1.0)
	return Astro.scale3(s["pos"], k * (1.0 if k < 1.0 else 0.999))


## "별빛 1호 → 프록시마 센타우리 · 47% · 2082.03 도착 · 2086.06 소식" / "… 닿았다 · 소식 2086.06"
static func probe_text(col: Colonies, p: Dictionary) -> String:
	var s := system(String(p["target"]))
	if String(p["state"]) == "arrived":
		return "%s → %s · 닿았다 · %s 소식" % [String(p["name"]), String(s.get("name", "")), col.date_text(float(p["report"]))]
	var k := clampf(float(col.hour - int(p["launched"])) / maxf(float(int(p["arrive"]) - int(p["launched"])), 1.0), 0.0, 1.0)
	return "%s → %s · %s광년의 %d%% · %s 도착 · %s 소식" % [String(p["name"]), String(s.get("name", "")),
		Fmt.n(float(s.get("dist_ly", 0.0)), 2), int(k * 100.0), col.date_text(float(p["arrive"])), col.date_text(float(p["report"]))]


## 행성 한 줄: "프록시마 b — 지구 질량 1.07배 · 11.2일 · 0.049 AU — 거주가능영역 안, … (확인됨)"
static func planet_text(pl: Dictionary) -> String:
	var bits := PackedStringArray()
	if pl.get("mass_earth") != null:
		bits.append("지구 질량 %s배" % Fmt.n(float(pl["mass_earth"]), 2))
	if pl.get("period_d") != null:
		bits.append("%s일" % Fmt.n(float(pl["period_d"]), 1 if float(pl["period_d"]) < 100.0 else 0))
	if pl.get("a_au") != null:
		bits.append("%s AU" % Fmt.n(float(pl["a_au"]), 3))
	var st := String({"confirmed": "확인됨", "candidate": "후보", "disputed": "논쟁 중"}.get(String(pl.get("status", "")), ""))
	var note := String(pl.get("note", ""))
	return "%s%s%s%s" % [String(pl.get("name", "")), (" — " + " · ".join(bits)) if not bits.is_empty() else "",
		(" — " + note) if note != "" else "", (" (%s)" % st) if st != "" and not note.contains(st) else ""]
