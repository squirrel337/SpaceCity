class_name Colonies
extends RefCounted
## 여러 천체의 도시 — 함께 흐르는 시계, 새 도시 세우기(원정), 기술 공유, 저장.
##
## 도시마다 시뮬레이션(CitySim)과 배치 계획(CityPlan)이 하나씩이다. 모든 도시가 같은 시계로 한 시간씩 흐른다.
## 게임은 천체마다 기본 도시 하나로 시작한다 (부지 자료의 default_city — 달 섀클턴이 고향, 나머지는 시드의 자동 운영).
## 새 도시는 후보 부지로 원정대를 보내 세운다:
##   같은 천체에 도시가 있으면 그 도시(가장 큰 곳)에서 로버 행렬·호퍼·비행기로 간다 — 발사 창이 없고 며칠~몇 주.
##   없으면 고향에서 행성 사이를 건너간다. 발사 창은 지구와 목적지 행성의 실제 위치(천문력)로 정한다 — 호만 전이의 위상각
##     φ = 180° − (목적지 평균 운동) × 전이 일수
##   이 맞는 날을 가운데로 앞뒤 며칠(회합 주기의 4%, 6~21일)이 열린다.
## 비용은 떠나는 도시가 낸다. 새 도시는 시드가 자동 운영으로 세우고, 그 도시를 골라 '자동 운영'을 끄면 넘겨받는다.
## 기술은 하루에 한 번 모든 도시가 나눠 갖는다 (지식은 전파로 건너간다).
## 도시 사이 교통(Transport)이 같은 시계로 화물과 정착민을 실어 나른다 — 도시가 생기거나 없어지면 노선을 다시 짠다.

const SAVE_VERSION := 3
const ORIGIN := "earth"            # 행성 사이 원정이 떠나는 행성 (고향 달 기지는 지구 곁)
## 개척 탭과 도시 고르기에서 천체를 늘어놓는 순서
const BODY_ORDER := ["moon", "earth", "mars", "mercury", "ceres", "callisto", "titan"]

var list: Array = []               # 도시 [{name, short, site, body, sim, plan, founded}] — founded: 게임 시각(시)
var expeditions: Array = []        # 이동 중 [{site, depart, arrive, seed, mode, from}] — 게임 시각(시), from: 떠난 부지
var hour := 0                      # 게임 시작부터 흐른 시간 (= 고향의 시간)
var start_unix := 0                # 게임을 시작한 시각
const DEFAULT_STAGGER_H := 3         # 기본 도시마다 하루 끝이 이만큼씩 어긋난다 (하루 넘김의 계산을 여러 시간에 나눈다)

var seed_value := 2061
var _windows := {}                 # 부지 → {best, start, end} (게임 일) — 창이 지나면 다시 셈한다
var transport := Transport.new()   # 도시 사이 교통
var metro_fn := MetroFunctions.new()   # 지구 대도시의 우주 시설 (도시 기능)


## 새 게임: 고향 도시와 천체마다의 기본 도시로 시작한다
func start(sim: CitySim, plan: CityPlan) -> void:
	list = [_entry(sim, plan, 0)]
	expeditions = []
	hour = sim.hour
	start_unix = sim.start_unix
	seed_value = sim.seed_value
	_windows.clear()
	found_defaults()
	metro_fn.reset()
	metro_fn.econ.seed_value = seed_value
	transport.reset()
	transport.rebuild(self)


## 아직 없는 기본 도시를 세운다 (새 게임, 기본 도시가 없던 옛 저장). 도시마다 몇 시간씩 앞서 세운 것으로 해
## (DEFAULT_STAGGER_H × 순서 — 그만큼 미리 돌린다) 도시들의 하루 끝 계산이 같은 시간에 몰리지 않게 한다
func found_defaults() -> Array:
	var made := []
	for id in GameData.SITES:
		var s: Dictionary = GameData.SITES[id]
		if not s.get("default_city", false) or index_of_site(id) >= 0 or not in_transit(id).is_empty():
			continue
		var ahead := (DEFAULT_STAGGER_H * (made.size() + 1)) % 24
		var c := _found_at(String(id), hour - ahead, _seed_for(String(id)))
		for _h in ahead:
			(c["sim"] as CitySim).advance_hour()
		c["sim"].note("관리 기록 — %s 가동. 정착민 %d명. 시드가 자동 운영으로 돌본다." % [c["name"], int(c["sim"].population())], "info")
		made.append(list.size() - 1)
	return made


func _seed_for(site_id: String) -> int:
	return seed_value * 31 + absi(site_id.hash()) % 9973 + list.size()


func _entry(sim: CitySim, plan: CityPlan, founded: int) -> Dictionary:
	var site := GameData.site(sim.site_id)
	return {"name": String(site.get("name", sim.site_id)), "short": String(site.get("short", site.get("name", ""))),
		"site": sim.site_id, "body": String(site.get("body", "moon")), "sim": sim, "plan": plan, "founded": founded}


func _found_at(site_id: String, at_hour: int, seed: int) -> Dictionary:
	var site := GameData.site(site_id)
	var s := CitySim.new(seed, 40.0, "good", site_id, unix_at(float(at_hour)))
	for t in known_techs():
		s.techs[t] = true
	var plan := CityPlan.create(s, BaseLayout.new(_layout_of(site_id)))
	var c := _entry(s, plan, at_hour)
	list.append(c)
	return c


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


## 그 천체에서 가장 큰 도시의 번호 (없으면 −1)
func largest_on(body: String) -> int:
	var best := -1
	var best_pop := -1.0
	for i in list.size():
		if String(list[i]["body"]) == body:
			var p := (list[i]["sim"] as CitySim).population()
			if p > best_pop:
				best_pop = p
				best = i
	return best


func count_on(body: String) -> int:
	var n := 0
	for c in list:
		if String(c["body"]) == body:
			n += 1
	return n


func unix_at(game_hour: float) -> int:
	return start_unix + int(game_hour * 3600.0)


func date_text(game_hour: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_at(game_hour))
	return "%04d.%02d.%02d" % [dt["year"], dt["month"], dt["day"]]


# ── 시간 ────────────────────────────────────────────────────────
## 한 시간: 모든 도시가 함께 흐른다. 도착한 원정대는 새 도시가 된다 — 그 번호들을 돌려준다.
## 교통은 도시가 흐른 뒤에 떠나고 닿는다
func step() -> Array:
	hour += 1
	for i in list.size():
		var s: CitySim = list[i]["sim"]
		s.advance_hour()
		if s.hour % 24 == 0:
			CityDev.step_day(list[i], i)          # 그 도시의 하루가 끝났다 — 발전 모드 (도시마다 다른 시간에)
			CityServices.step(list[i], s.current_day(), i)   # 시설 영향 범위·통근·물류 (모든 도시)
			CityProgress.step(list[i], s.current_day())      # 이정표·시대·메가프로젝트 (모든 도시)
			CityResearch.step(list[i])                       # 연구 갈림길·돌파 카드 (모든 도시)
	var arrived := []
	for e in expeditions.duplicate():
		if hour >= int(e["arrive"]):
			expeditions.erase(e)
			arrived.append(_found(e))
	if not arrived.is_empty():
		transport.rebuild(self)
	transport.step(self)
	metro_fn.step_hour(self)
	if hour % 24 == 0:
		share_techs()
		metro_fn.step_day(self)
	return arrived


## 기술 나누기: 어느 도시든 알아낸 기술은 모두가 안다
func share_techs() -> void:
	if list.size() < 2:
		return
	var known := known_techs()
	for c in list:
		var s: CitySim = c["sim"]
		for t in known:
			s.techs[t] = true


func _found(e: Dictionary) -> int:
	var c := _found_at(String(e["site"]), int(e["arrive"]), int(e["seed"]))
	var s: CitySim = c["sim"]
	s.note("관리 기록 — %s 도착. 정착민 %d명이 내렸다. 시드가 자동 운영으로 기지를 세운다." % [c["name"], int(s.population())],
		"info")
	return list.size() - 1


## 도시를 잃었다 (절멸·시드 정지) — 목록에서 뺀다. 그 부지는 다시 원정할 수 있다
func remove(index: int) -> Dictionary:
	var c: Dictionary = list[index]
	list.remove_at(index)
	transport.rebuild(self)
	metro_fn.on_colony_removed(String(c["site"]), self)
	return c


# ── 원정 ────────────────────────────────────────────────────────
## 새 도시를 세울 수 있는 부지 (원정 자료가 있는 곳) — 천체 순서대로
func candidates() -> Array:
	GameData.load_all()
	var out := []
	for body in BODY_ORDER:
		for id in GameData.SITES:
			var s: Dictionary = GameData.SITES[id]
			if String(s.get("body", "")) == body and s.has("expedition"):
				out.append(String(id))
	return out


func expedition(site_id: String) -> Dictionary:
	return GameData.site(site_id).get("expedition", {})


## 가는 길: {mode: "local"(같은 천체의 도시에서) | "space"(고향에서 행성 사이) | "", from: 떠나는 도시 번호}
func route(site_id: String) -> Dictionary:
	var site := GameData.site(site_id)
	var body := String(site.get("body", ""))
	var ex := expedition(site_id)
	var near := largest_on(body)
	if near >= 0 and ex.has("local"):
		return {"mode": "local", "from": near}
	var h := index_of_site(GameData.HOME_SITE)
	if h >= 0 and String(list[h]["body"]) != body and ex.has("transfer_days"):
		return {"mode": "space", "from": h}
	return {"mode": "", "from": -1}


## 그 길의 원정 자료 (local이면 local 칸, 행성 사이면 원정 자료 그대로)
func _route_data(site_id: String, r: Dictionary) -> Dictionary:
	var ex := expedition(site_id)
	return ex.get("local", {}) if r["mode"] == "local" else ex


## 두 부지 사이의 거리 (km, 같은 천체의 대원)
func surface_km(a_site: String, b_site: String) -> float:
	var a := GameData.site(a_site)
	var b := GameData.site(b_site)
	Astro.load_data()
	var r := float(Astro.bodies.get(String(a.get("body", "moon")), {}).get("radius_km", 1737.4))
	var da := Astro.latlon(float(a["lat"]), float(a["lon"]))
	var db := Astro.latlon(float(b["lat"]), float(b["lon"]))
	return acos(clampf(da.dot(db), -1.0, 1.0)) * r


## 가는 데 걸리는 날 (같은 천체: 준비 + 거리 ÷ 하루 이동, 행성 사이: 전이 일수)
func travel_days(site_id: String, r: Dictionary = {}) -> float:
	if r.is_empty():
		r = route(site_id)
	if r["mode"] == "local":
		var d := _route_data(site_id, r)
		var from_site := String(list[int(r["from"])]["site"])
		return float(d.get("prep_days", 3)) + surface_km(from_site, site_id) / maxf(1.0, float(d.get("speed_km_day", 400)))
	return float(expedition(site_id).get("transfer_days", 200))


func known_techs() -> Dictionary:
	var known := {}
	for c in list:
		for t in (c["sim"] as CitySim).techs:
			known[t] = true
	return known


func missing_techs(site_id: String, r: Dictionary = {}) -> Array:
	if r.is_empty():
		r = route(site_id)
	var known := known_techs()
	var out := []
	for t in _route_data(site_id, r).get("requires", []):
		if not known.has(t):
			out.append(String(t))
	return out


## 비용 항목: [[이름, 필요, 가진 것]] — 떠나는 도시가 낸다
func cost_rows(site_id: String, r: Dictionary = {}) -> Array:
	if r.is_empty():
		r = route(site_id)
	var s: CitySim = list[int(r["from"])]["sim"] if int(r["from"]) >= 0 else null
	var out := []
	var cost: Dictionary = _route_data(site_id, r).get("cost", {})
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
	if index_of_site(site_id) >= 0:
		return "이미 도시가 있다"
	if not in_transit(site_id).is_empty():
		return "원정대가 가는 중이다"
	var r := route(site_id)
	if r["mode"] == "":
		return "떠날 도시가 없다"
	var miss := missing_techs(site_id, r)
	if not miss.is_empty():
		var names := []
		for t in miss:
			names.append(String(GameData.TECHS[t]["name"]) if GameData.TECHS.has(t) else t)
		return "기술이 모자란다: " + ", ".join(names)
	for row in cost_rows(site_id, r):
		if float(row[2]) < float(row[1]):
			return "%s의 %s이 모자란다 (%s 필요, %s 있음)" % [list[int(r["from"])]["short"], cost_name(row[0]),
				Fmt.n(row[1]), Fmt.n(row[2])]
	if r["mode"] == "space":
		var w := window(site_id)
		if not w["open"]:
			return "발사 창이 닫혀 있다 — 다음 창 %s" % date_text(float(w["start"]) * 24.0)
	return ""


## 원정대를 보낸다: 떠나는 도시가 비용을 내고, 가는 날만큼 뒤에 도착한다
func launch(site_id: String) -> bool:
	if block_reason(site_id) != "":
		return false
	var r := route(site_id)
	var src: Dictionary = list[int(r["from"])]
	var s: CitySim = src["sim"]
	var cost: Dictionary = _route_data(site_id, r).get("cost", {})
	for k in cost:
		if k == "support":
			s.support -= float(cost[k])
		else:
			s.stock[k] = float(s.stock.get(k, 0.0)) - float(cost[k])
	var days := travel_days(site_id, r)
	var e := {"site": site_id, "depart": hour, "arrive": hour + maxi(24, int(round(days * 24.0))),
		"seed": _seed_for(site_id) + expeditions.size(), "mode": r["mode"], "from": String(src["site"])}
	expeditions.append(e)
	var site := GameData.site(site_id)
	var how := "로버 행렬" if r["mode"] == "local" else "원정선"
	if r["mode"] == "local" and String(site.get("body", "")) == "earth":
		how = "비행편"
	s.note("%s 출발 — %s (%s). %d일 뒤 %s 도착 예정" % [how, String(site["name"]),
		String(Astro.bodies.get(site["body"], {}).get("name", site["body"])), ceili(days), date_text(float(e["arrive"]))], "good")
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
## [{name, site, body, dir, pop, active, id?, sub?, transit?, candidate?}]
## 도시, 이동 중인 원정대(목적지에 '도착 D-n'), 아직 비어 있는 후보 부지(속이 빈 점)
func markers(active_index: int, site_dirs: Dictionary = {}) -> Array:
	var out := []
	for i in list.size():
		var c: Dictionary = list[i]
		var site := GameData.site(c["site"])
		out.append({"name": c["name"], "site": c["site"], "body": c["body"],
			"dir": site_dirs.get(c["site"], Astro.latlon(float(site["lat"]), float(site["lon"]))),
			"pop": (c["sim"] as CitySim).population(), "active": i == active_index})
	for e in expeditions:
		var site2 := GameData.site(e["site"])
		var left := ceili((float(e["arrive"]) - hour) / 24.0)
		out.append({"name": String(site2.get("short", site2["name"])), "site": e["site"], "body": site2["body"],
			"dir": Astro.latlon(float(site2["lat"]), float(site2["lon"])), "pop": 0, "active": false,
			"id": "site:" + String(e["site"]), "sub": "원정대 이동 중 · 도착 D-%d" % left, "transit": true})
	for id in candidates():
		if index_of_site(id) >= 0 or not in_transit(id).is_empty():
			continue
		var site3 := GameData.site(id)
		out.append({"name": String(site3.get("short", site3["name"])), "site": id, "body": site3["body"],
			"dir": Astro.latlon(float(site3["lat"]), float(site3["lon"])), "pop": 0, "active": false,
			"id": "site:" + id, "sub": "후보지", "candidate": true})
	return out


# ── 저장 ───────────────────────────────────────────────────────
func to_save() -> Dictionary:
	var cols := []
	for c in list:
		cols.append({"name": c["name"], "site": c["site"], "founded": c["founded"],
			"sim": (c["sim"] as CitySim).to_save(), "plan": (c["plan"] as CityPlan).to_save(),
			"mode": String(c.get("mode", "")), "idle": c.get("idle", {}), "bought": int(c.get("bought", -100000)),
			"extra": int(c.get("extra", -100000)), "redev": int(c.get("redev", -1)), "redev_txt": String(c.get("redev_txt", "")),
			"progress": c.get("progress", {}), "research": c.get("research", {})})
	return {"version": SAVE_VERSION, "hour": hour, "start_unix": start_unix, "seed": seed_value,
		"colonies": cols, "expeditions": expeditions, "defaults": 1, "transport": transport.to_save(),
		"metro_fn": metro_fn.to_save()}


## 저장을 읽는다 (판 1 = 도시 하나뿐이던 저장, 판 2 = 교통이 없던 저장). 기본 도시가 없던 저장이면 지금 시각에 세운다.
## 실패하면 false
func load_save(data: Dictionary) -> bool:
	var v := int(data.get("version", 0))
	if v == 1:
		var s := CitySim.from_save(data)
		var plan := CityPlan.from_save(data.get("plan"), s, BaseLayout.new(_layout_of(s.site_id)))
		list = [_entry(s, plan, 0)]
		expeditions = []
		hour = s.hour
		start_unix = s.start_unix
		seed_value = s.seed_value
		_windows.clear()
		found_defaults()
		metro_fn.reset()
		metro_fn.econ.seed_value = seed_value
		transport.load_save({}, self)
		return true
	if (v != SAVE_VERSION and v != 2) or not data.get("colonies") is Array or (data["colonies"] as Array).is_empty():
		return false
	list = []
	for cd in data["colonies"]:
		var sd: Dictionary = cd["sim"]
		var s2 := CitySim.from_save(sd)
		var plan2 := CityPlan.from_save(cd.get("plan"), s2, BaseLayout.new(_layout_of(s2.site_id)), false)
		var entry := _entry(s2, plan2, int(cd.get("founded", 0)))
		if cd.has("name"):
			entry["name"] = String(cd["name"])
		if LayoutData.dev_modes().has(String(cd.get("mode", ""))):
			entry["mode"] = String(cd.get("mode", ""))
		if cd.get("idle") is Dictionary:
			entry["idle"] = cd["idle"]
		entry["bought"] = int(cd.get("bought", -100000))
		entry["extra"] = int(cd.get("extra", -100000))
		entry["redev"] = int(cd.get("redev", -1))
		entry["redev_txt"] = String(cd.get("redev_txt", ""))
		if cd.get("progress") is Dictionary:
			var pg: Dictionary = cd["progress"]
			entry["progress"] = {"done": pg.get("done", {}) if pg.get("done") is Dictionary else {}, "era": int(pg.get("era", 0)),
				"built": pg.get("built", []) if pg.get("built") is Array else []}
			CityProgress.apply_effects(entry)
		if cd.get("research") is Dictionary:
			var rs: Dictionary = cd["research"]
			entry["research"] = {"branches": rs.get("branches", {}) if rs.get("branches") is Dictionary else {},
				"cards": rs.get("cards", []) if rs.get("cards") is Array else [],
				"pending": rs.get("pending", []) if rs.get("pending") is Array else [], "techs": int(rs.get("techs", 0)),
				"told": int(rs.get("told", -1))}
			CityResearch.apply(entry)
		list.append(entry)
	expeditions = []
	for e in data.get("expeditions", []):
		expeditions.append({"site": String(e["site"]), "depart": int(e["depart"]), "arrive": int(e["arrive"]),
			"seed": int(e["seed"]), "mode": String(e.get("mode", "space")), "from": String(e.get("from", GameData.HOME_SITE))})
	hour = int(data.get("hour", 0))
	start_unix = int(data.get("start_unix", (list[0]["sim"] as CitySim).start_unix))
	seed_value = int(data.get("seed", 2061))
	_windows.clear()
	if not data.has("defaults"):
		found_defaults()
	metro_fn.load_save(data.get("metro_fn", {}) if data.get("metro_fn") is Dictionary else {})
	metro_fn.econ.seed_value = seed_value
	transport.load_save(data.get("transport", {}) if data.get("transport") is Dictionary else {}, self)
	return true


static func _layout_of(site_id: String) -> String:
	return String(GameData.site(site_id).get("layout", "ridge" if site_id == GameData.HOME_SITE else "open"))
