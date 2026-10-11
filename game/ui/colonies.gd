class_name Colonies
extends RefCounted
## 여러 천체의 식민지 — 함께 흐르는 시계, 원정(발사 창·전이·도착), 기술 공유, 저장.
##
## 식민지마다 도시 시뮬레이션(CitySim)과 배치 계획(CityPlan)이 하나씩이다. 모든 식민지가 같은 시계로 한 시간씩 흐른다.
## 첫 식민지(섀클턴)가 고향이다: 원정은 고향에서 떠나고, 비용(부품·금속·지구 지원 점수)도 고향이 낸다.
## 발사 창은 지구와 목적지 행성의 실제 위치(천문력)로 정한다 — 호만 전이의 위상각
##   φ = 180° − (목적지 평균 운동) × 전이 일수
## 이 맞는 날을 가운데로 앞뒤 며칠(회합 주기의 4%, 6~21일)이 열린다.
## 새 식민지는 시드가 자동 운영으로 세운다. 그 식민지를 골라 '자동 운영'을 끄면 넘겨받는다.
## 기술은 하루에 한 번 모든 식민지가 나눠 갖는다 (지식은 전파로 건너간다).

const SAVE_VERSION := 2
const ORIGIN := "earth"            # 원정이 떠나는 행성 (고향 달 기지는 지구 곁)

var list: Array = []               # 식민지 [{name, site, sim, plan, founded}] — founded: 게임 시각(시)
var expeditions: Array = []        # 이동 중 [{site, depart, arrive, seed}] — 게임 시각(시)
var hour := 0                      # 게임 시작부터 흐른 시간 (= 고향의 시간)
var start_unix := 0                # 게임을 시작한 시각
var seed_value := 2061
var _windows := {}                 # 부지 → {best, start, end} (게임 일) — 창이 지나면 다시 셈한다


## 새 게임: 고향 식민지 하나로 시작한다
func start(sim: CitySim, plan: CityPlan) -> void:
	list = [_entry(sim, plan, 0)]
	expeditions = []
	hour = sim.hour
	start_unix = sim.start_unix
	seed_value = sim.seed_value
	_windows.clear()


func _entry(sim: CitySim, plan: CityPlan, founded: int) -> Dictionary:
	var site := GameData.site(sim.site_id)
	return {"name": String(site.get("name", sim.site_id)), "short": String(site.get("short", site.get("name", ""))),
		"site": sim.site_id, "body": String(site.get("body", "moon")), "sim": sim, "plan": plan, "founded": founded}


func home() -> Dictionary:
	for c in list:
		if String(c["site"]) == GameData.HOME_SITE:
			return c
	return {}


func index_of_sim(sim: CitySim) -> int:
	for i in list.size():
		if list[i]["sim"] == sim:
			return i
	return -1


func index_of_site(site_id: String) -> int:
	for i in list.size():
		if String(list[i]["site"]) == site_id:
			return i
	return -1


func in_transit(site_id: String) -> Dictionary:
	for e in expeditions:
		if String(e["site"]) == site_id:
			return e
	return {}


func unix_at(game_hour: float) -> int:
	return start_unix + int(game_hour * 3600.0)


func date_text(game_hour: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_at(game_hour))
	return "%04d.%02d.%02d" % [dt["year"], dt["month"], dt["day"]]


# ── 시간 ────────────────────────────────────────────────────────
## 한 시간: 모든 식민지가 함께 흐른다. 도착한 원정대는 새 식민지가 된다 — 그 번호들을 돌려준다
func step() -> Array:
	hour += 1
	for c in list:
		(c["sim"] as CitySim).advance_hour()
	var arrived := []
	for e in expeditions.duplicate():
		if hour >= int(e["arrive"]):
			expeditions.erase(e)
			arrived.append(_found(e))
	if hour % 24 == 0:
		share_techs()
	return arrived


## 기술 나누기: 어느 식민지든 알아낸 기술은 모두가 안다
func share_techs() -> void:
	if list.size() < 2:
		return
	var known := {}
	for c in list:
		for t in (c["sim"] as CitySim).techs:
			known[t] = true
	for c in list:
		var s: CitySim = c["sim"]
		for t in known:
			s.techs[t] = true


func _found(e: Dictionary) -> int:
	var site_id := String(e["site"])
	var site := GameData.site(site_id)
	var s := CitySim.new(int(e["seed"]), 40.0, "good", site_id, unix_at(float(e["arrive"])))
	for t in known_techs():
		s.techs[t] = true
	var plan := CityPlan.create(s, BaseLayout.new(String(site.get("layout", "open"))))
	s.note("관리 기록 — %s 도착. 정착민 %d명이 내렸다. 시드가 자동 운영으로 기지를 세운다." % [
		String(site["name"]), int(s.population())], "info")
	list.append(_entry(s, plan, int(e["arrive"])))
	return list.size() - 1


## 식민지를 잃었다 (절멸·시드 정지) — 목록에서 뺀다. 그 부지는 다시 원정할 수 있다
func remove(index: int) -> Dictionary:
	var c: Dictionary = list[index]
	list.remove_at(index)
	return c


# ── 원정 ────────────────────────────────────────────────────────
func candidates() -> Array:
	GameData.load_all()
	var out := []
	for id in GameData.SITES:
		if (GameData.SITES[id] as Dictionary).has("expedition"):
			out.append(String(id))
	return out


func expedition(site_id: String) -> Dictionary:
	return GameData.site(site_id).get("expedition", {})


func known_techs() -> Dictionary:
	var known := {}
	for c in list:
		for t in (c["sim"] as CitySim).techs:
			known[t] = true
	return known


func missing_techs(site_id: String) -> Array:
	var known := known_techs()
	var out := []
	for t in expedition(site_id).get("requires", []):
		if not known.has(t):
			out.append(String(t))
	return out


## 비용 항목: [[이름, 필요, 가진 것]] — 고향이 낸다
func cost_rows(site_id: String) -> Array:
	var h := home()
	var s: CitySim = h.get("sim") if not h.is_empty() else null
	var out := []
	var cost: Dictionary = expedition(site_id).get("cost", {})
	for k in cost:
		var have := 0.0
		if s != null:
			have = s.support if k == "support" else float(s.stock.get(k, 0.0))
		out.append([String(k), float(cost[k]), have])
	return out


static func cost_name(k: String) -> String:
	match k:
		"parts":
			return "부품"
		"metal_t":
			return "금속(t)"
		"support":
			return "지구 지원"
	return k


## 출발할 수 없는 까닭 ("" = 지금 떠날 수 있다)
func block_reason(site_id: String) -> String:
	if home().is_empty():
		return "고향 기지가 없다"
	if index_of_site(site_id) >= 0:
		return "이미 식민지가 있다"
	if not in_transit(site_id).is_empty():
		return "원정대가 가는 중이다"
	var miss := missing_techs(site_id)
	if not miss.is_empty():
		var names := []
		for t in miss:
			names.append(String(GameData.TECHS[t]["name"]) if GameData.TECHS.has(t) else t)
		return "기술이 모자란다: " + ", ".join(names)
	for row in cost_rows(site_id):
		if float(row[2]) < float(row[1]):
			return "%s이 모자란다 (%s 필요, %s 있음)" % [cost_name(row[0]), Fmt.n(row[1]), Fmt.n(row[2])]
	var w := window(site_id)
	if not w["open"]:
		return "발사 창이 닫혀 있다 — 다음 창 %s" % date_text(float(w["start"]) * 24.0)
	return ""


## 원정대를 보낸다: 고향이 비용을 내고, 전이 일수 뒤에 도착한다
func launch(site_id: String) -> bool:
	if block_reason(site_id) != "":
		return false
	var h := home()
	var s: CitySim = h["sim"]
	var ex := expedition(site_id)
	var cost: Dictionary = ex.get("cost", {})
	for k in cost:
		if k == "support":
			s.support -= float(cost[k])
		else:
			s.stock[k] = float(s.stock.get(k, 0.0)) - float(cost[k])
	var days := float(ex.get("transfer_days", 200))
	var e := {"site": site_id, "depart": hour, "arrive": hour + int(round(days * 24.0)),
		"seed": seed_value * 31 + absi(site_id.hash()) % 9973 + list.size()}
	expeditions.append(e)
	var site := GameData.site(site_id)
	s.note("원정대 출발 — %s (%s). %d일 뒤 %s 도착 예정" % [String(site["name"]),
		String(Astro.bodies.get(site["body"], {}).get("name", site["body"])), int(days), date_text(float(e["arrive"]))], "good")
	return true


# ── 발사 창 (천문력) ────────────────────────────────────────────
static func _period_days(id: String) -> float:
	Astro.load_data()
	var b: Dictionary = Astro.bodies.get(id, {})
	if b.has("elements"):
		return 365.25 * pow(float(b["elements"][0]), 1.5)
	return 365.25


static func _lon(id: String, jd: float) -> float:
	var p := Astro.position(id, jd)
	return rad_to_deg(atan2(p[1], p[0]))


func _jd(game_day: float) -> float:
	return Astro.jd_from_unix(float(start_unix) + game_day * 86400.0)


## 발사 창 {open, best, start, end} — 게임 일. 지금 열려 있거나 다음에 열릴 창
func window(site_id: String) -> Dictionary:
	var now_d := hour / 24.0
	var w: Dictionary = _windows.get(site_id, {})
	if w.is_empty() or now_d > float(w["end"]):
		w = _find_window(site_id, now_d)
		_windows[site_id] = w
	var out := w.duplicate()
	out["open"] = now_d >= float(w["start"]) and now_d <= float(w["end"])
	return out


func _find_window(site_id: String, now_d: float) -> Dictionary:
	var ex := expedition(site_id)
	var target := String(ex.get("window_from", GameData.site(site_id).get("body", "mars")))
	var p_t := _period_days(target)
	var syn := 1.0 / maxf(absf(1.0 / p_t - 1.0 / 365.25), 1e-6)
	var half := clampf(syn * 0.04, 6.0, 21.0)
	var phi := 180.0 - 360.0 / p_t * float(ex.get("transfer_days", 200))
	var step := 2.0
	var d := now_d - half
	var prev := wrapf(_lon(target, _jd(d)) - _lon(ORIGIN, _jd(d)) - phi, -180.0, 180.0)
	var limit := now_d + syn * 1.3 + 30.0
	while d < limit:
		var d1 := d + step
		var e1 := wrapf(_lon(target, _jd(d1)) - _lon(ORIGIN, _jd(d1)) - phi, -180.0, 180.0)
		if signf(prev) != signf(e1) and absf(prev - e1) < 90.0:
			var best := d + step * absf(prev) / maxf(absf(prev - e1), 1e-9)
			if best + half >= now_d:
				return {"best": best, "start": best - half, "end": best + half, "half": half}
		prev = e1
		d = d1
	# 찾지 못하면 (자료가 없을 때) 회합 주기 뒤로
	return {"best": now_d + syn, "start": now_d + syn - half, "end": now_d + syn + half, "half": half}


# ── 3D 지도의 점 ─────────────────────────────────────────────────
## [{name, site, body, dir, pop, active, id?, sub?}] — 이동 중인 원정대는 목적지에 '도착 D-n'으로
func markers(active_index: int, site_dirs: Dictionary = {}) -> Array:
	var out := []
	for i in list.size():
		var c: Dictionary = list[i]
		var site := GameData.site(c["site"])
		out.append({"name": c["name"], "site": c["site"], "body": c["body"],
			"dir": site_dirs.get(c["body"], Astro.latlon(float(site["lat"]), float(site["lon"]))),
			"pop": (c["sim"] as CitySim).population(), "active": i == active_index})
	for e in expeditions:
		var site2 := GameData.site(e["site"])
		var left := ceili((float(e["arrive"]) - hour) / 24.0)
		out.append({"name": String(site2.get("short", site2["name"])), "site": e["site"], "body": site2["body"],
			"dir": Astro.latlon(float(site2["lat"]), float(site2["lon"])), "pop": 0, "active": false,
			"id": String(site2["body"]), "sub": "원정대 이동 중 · 도착 D-%d" % left, "transit": true})
	return out


# ── 저장 ───────────────────────────────────────────────────────
func to_save() -> Dictionary:
	var cols := []
	for c in list:
		cols.append({"name": c["name"], "site": c["site"], "founded": c["founded"],
			"sim": (c["sim"] as CitySim).to_save(), "plan": (c["plan"] as CityPlan).to_save()})
	return {"version": SAVE_VERSION, "hour": hour, "start_unix": start_unix, "seed": seed_value,
		"colonies": cols, "expeditions": expeditions}


## 저장을 읽는다 (판 1 = 식민지 하나뿐이던 저장). 실패하면 false
func load_save(data: Dictionary) -> bool:
	var v := int(data.get("version", 0))
	if v == 1:
		var s := CitySim.from_save(data)
		var plan := CityPlan.from_save(data.get("plan"), s, BaseLayout.new(_layout_of(s.site_id)))
		start(s, plan)
		return true
	if v != SAVE_VERSION or not data.get("colonies") is Array or (data["colonies"] as Array).is_empty():
		return false
	list = []
	for cd in data["colonies"]:
		var sd: Dictionary = cd["sim"]
		var s2 := CitySim.from_save(sd)
		var plan2 := CityPlan.from_save(cd.get("plan"), s2, BaseLayout.new(_layout_of(s2.site_id)))
		var entry := _entry(s2, plan2, int(cd.get("founded", 0)))
		if cd.has("name"):
			entry["name"] = String(cd["name"])
		list.append(entry)
	expeditions = []
	for e in data.get("expeditions", []):
		expeditions.append({"site": String(e["site"]), "depart": int(e["depart"]), "arrive": int(e["arrive"]),
			"seed": int(e["seed"])})
	hour = int(data.get("hour", 0))
	start_unix = int(data.get("start_unix", (list[0]["sim"] as CitySim).start_unix))
	seed_value = int(data.get("seed", 2061))
	_windows.clear()
	return true


static func _layout_of(site_id: String) -> String:
	return String(GameData.site(site_id).get("layout", "ridge" if site_id == GameData.HOME_SITE else "open"))
