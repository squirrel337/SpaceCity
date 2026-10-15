class_name Transport
extends RefCounted
## 도시 사이 교통 — 같은 천체의 도시를 잇는 땅·하늘 노선, 지구 우주항과 달 고향 사이의 셔틀, 달 고향과 다른 천체의
## 가장 큰 도시 사이의 행성간 수송선(발사 창마다), 지구 대도시에서 가장 가까운 지구 도시로 가는 항공편, 대도시끼리의 국제선.
## 모든 도시가 함께 흐르는 시계(Colonies.hour)에 맞춰 떠나고 닿는다. 규칙과 탈것은 data/transport.json.
##
## 떠날 때 싣는다: 받는 도시에 모자란 비축(식량·산소·물·부품·금속 — cargo 순서대로)을 보내는 도시가 넉넉한 만큼.
##   시장이 채우는 도시(지구)는 시장에서 사서 보낸다. 받는 도시의 저장 한도는 넘기지 않는다.
##   정착민은 받는 도시에 주거·CO₂ 제거 여유가 있고 식량·산소가 넉넉할 때, 지구의 도시나 붐비는 도시에서 탄다.
##   지구에서 달로, 행성 사이로 실어 올리는 화물은 보내는 도시가 운임(지원 점수)을 낸다.
## 닿을 때 내린다: 비축에 더하고, 정착민은 지니고 온 선량과 함께 그 도시의 사람이 된다.
##   받을 도시가 그사이 없어졌으면 떠난 도시로 되돌아간다.
## 노선은 도시가 생기거나 없어질 때마다 다시 짠다 — 이어지는 노선은 일정·누계를 지킨다. 실은 짐은 가는 동안 탈것에 있다.

const PATH := "res://data/transport.json"
const SAVE_VERSION := 1
## 행성 사이 수송선의 발사 창을 셈할 때 쓰는 천체 (달은 지구 곁 — 나머지는 부지 자료의 window_from)
const WINDOW_OF := {"moon": "earth", "earth": "earth"}

static var D: Dictionary = {}

var enabled := true
var lines: Array = []      # [{id, a, b, mode, kind, role, body, km, trip_h, every_h, next: [a→b, b→a], on, stats, last}]
var trips: Array = []      # [{line, from, to, depart, arrive, cargo: {열쇠: 양}, people: [[명, 선량]], pax, mode, kind}]
var flow := {}             # 노드 → {in_t, out_t, in_p, out_p} — 이번 기록 기간 (note_days)
var totals := {"trips": 0, "t": 0.0, "settlers": 0, "pax": 0}
var events: Array = []     # 최근 출발·도착 [{n, hour, type: dep|arr, site, other, mode, kind, line}] — 3D 기지가 탈것을 띄운다
var _event_n := 0
var _off := {}             # 꺼 둔 노선 id → true
var _state := {}           # 노선 id → {next, stats, last} (다시 짤 때 이어 간다)
var _by_id := {}
var rev := 0               # 노선·켜짐이 바뀔 때마다 +1 (지도의 노선 메시를 그때만 다시 만든다)


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func mode(key: String) -> Dictionary:
	return data().get("modes", {}).get(key, {})


static func mode_name(key: String) -> String:
	return String(mode(key).get("name", key))


static func cargo_rule(key: String) -> Dictionary:
	for c in data().get("cargo", []):
		if String(c["key"]) == key:
			return c
	return {}


## 새 게임
func reset() -> void:
	rev += 1
	enabled = true
	lines = []
	trips = []
	flow = {}
	totals = {"trips": 0, "t": 0.0, "settlers": 0, "pax": 0}
	_off = {}
	_state = {}
	_by_id = {}


# ── 노드: 식민지(부지 id)와 대도시(metro_…) ─────────────────────
static func node_body(key: String) -> String:
	if Metros.is_metro(key):
		return "earth"
	return String(GameData.site(key).get("body", ""))


static func node_dir(key: String) -> Vector3:
	if Metros.is_metro(key):
		return Metros.of(key).get("dir", Vector3(0, 0, 1))
	var s := GameData.site(key)
	return Astro.latlon(float(s.get("lat", 0.0)), float(s.get("lon", 0.0)))


static func node_name(key: String) -> String:
	if Metros.is_metro(key):
		return String(Metros.of(key).get("name", key))
	var s := GameData.site(key)
	return String(s.get("short", s.get("name", key)))


## 같은 천체의 두 노드 사이 (km, 대원)
static func surface_km(a: String, b: String) -> float:
	Astro.load_data()
	var r := float(Astro.bodies.get(node_body(a), {}).get("radius_km", 1737.4))
	return acos(clampf(node_dir(a).dot(node_dir(b)), -1.0, 1.0)) * r


static func _sim(col: Colonies, key: String) -> CitySim:
	if Metros.is_metro(key):
		return null
	var i := col.index_of_site(key)
	return col.list[i]["sim"] if i >= 0 else null


static func _pair(a: String, b: String) -> String:
	return "%s~%s" % [a, b] if a < b else "%s~%s" % [b, a]


# ── 노선 짜기 ────────────────────────────────────────────────────
## 노선을 다시 짠다 (도시가 생기거나 없어졌을 때, 새 게임, 불러오기)
func rebuild(col: Colonies) -> void:
	rev += 1
	data()
	Metros.load_all()
	for l in lines:
		_state[l["id"]] = {"next": l["next"], "stats": l["stats"], "last": l.get("last", "")}
	var on_body := {}
	for c in col.list:
		var b := String(c["body"])
		if not on_body.has(b):
			on_body[b] = []
		on_body[b].append(String(c["site"]))
	var want: Array = []
	# 같은 천체: 도시를 잇는 가장 짧은 그물
	var surf: Dictionary = D.get("surface", {})
	for body in on_body:
		var nodes: Array = on_body[body]
		if nodes.size() < 2 or not surf.has(body):
			continue
		var rule: Dictionary = surf[body]
		for e in _mst(nodes):
			var km := surface_km(e[0], e[1])
			var m := String(rule["near"]) if km < float(rule.get("far_km", 0.0)) else String(rule["far"])
			want.append(_line(e[0], e[1], m, "local", String(body), km))
	# 지구 우주항 ↔ 달 고향
	var e_hub := _hub(col, "earth")
	var port := _port(col)
	if e_hub != "" and port != "" and node_body(port) == "moon":
		want.append(_line(e_hub, port, "shuttle", "shuttle", "", 384400.0))
	# 행성 사이: 고향 ↔ 다른 천체의 가장 큰 도시
	if port == "":
		port = e_hub
	if port != "":
		for body in Colonies.BODY_ORDER:
			if body in ["moon", "earth"] or not on_body.has(body):
				continue
			var hub := _hub(col, body)
			var tdays := _transfer_days(body)
			if hub == "" or tdays <= 0.0:
				continue
			var l := _line(port, hub, "ship", "ship", "", 0.0)
			l["trip_h"] = int(round(tdays * 24.0))
			want.append(l)
	# 지구의 대도시 → 가장 가까운 지구 도시 (우주항)
	var earth_sites: Array = on_body.get("earth", [])
	var md: Dictionary = D.get("metro", {})
	if not earth_sites.is_empty():
		for m in Metros.list:
			var key := String(m["key"])
			var best := ""
			var best_km := INF
			for s in earth_sites:
				var km2 := surface_km(key, s)
				if km2 < best_km:
					best_km = km2
					best = s
			var lf := _line(key, best, String(md.get("mode", "airliner")), "feeder", "earth", best_km)
			lf["every_h"] = int(col.metro_fn.feeder(key, int(md.get("every_h", 24)))["every_h"])
			want.append(lf)
	# 대도시끼리: 가장 가까운 두 도시와 국제선
	var pairs := {}
	for m in Metros.list:
		var near: Array = []
		for o in Metros.list:
			if o != m:
				near.append([Metros.km_between(m["dir"], o["dir"]), String(o["key"])])
		near.sort_custom(func(x, y): return x[0] < y[0])
		for k in mini(2, near.size()):
			pairs[_pair(String(m["key"]), near[k][1])] = [String(m["key"]), near[k][1]]
	for r in Metros.routes:
		pairs[_pair(r[0], r[1])] = [r[0], r[1]]
	for pid in pairs:
		var p: Array = pairs[pid]
		want.append(_line(p[0], p[1], "airliner", "air", "earth", surface_km(p[0], p[1])))
	# 일정·누계를 잇는다
	lines = []
	_by_id = {}
	for l2 in want:
		var st: Dictionary = _state.get(l2["id"], {})
		if st.has("next"):
			l2["next"] = [int(st["next"][0]), int(st["next"][1])]
			l2["stats"] = st["stats"]
			l2["last"] = String(st.get("last", ""))
		else:
			_schedule_first(col, l2)
		l2["on"] = not _off.has(l2["id"])
		lines.append(l2)
		_by_id[l2["id"]] = l2


func _line(a: String, b: String, mode_key: String, role: String, body: String, km: float) -> Dictionary:
	var md := mode(mode_key)
	var l := {"id": "%s:%s" % [role, _pair(a, b)], "a": a, "b": b, "mode": mode_key,
		"kind": String(md.get("kind", "ground")), "role": role, "body": body, "km": km,
		"every_h": int(md.get("every_h", 24)), "next": [0, 0], "on": true, "last": "",
		"stats": {"trips": 0, "t": 0.0, "settlers": 0, "pax": 0}}
	var travel := 0.0
	if md.has("trip_h"):
		travel = float(md["trip_h"])
	elif float(md.get("speed_km_h", 0.0)) > 0.0:
		travel = km / float(md["speed_km_h"])
	l["trip_h"] = maxi(1, int(ceil(float(md.get("load_h", 1)) + travel)))
	return l


## 최소 신장 나무 (프림) — [[a, b]]
static func _mst(nodes: Array) -> Array:
	var out := []
	var inside := {nodes[0]: true}
	while inside.size() < nodes.size():
		var best: Array = []
		var best_km := INF
		for a in inside:
			for b in nodes:
				if inside.has(b):
					continue
				var km := surface_km(a, b)
				if km < best_km:
					best_km = km
					best = [a, b]
		if best.is_empty():
			break
		inside[best[1]] = true
		out.append(best)
	return out


## 그 천체의 중심 도시: 기본 도시가 있으면 그것, 아니면 가장 큰 도시 ("" = 없다)
static func _hub(col: Colonies, body: String) -> String:
	for c in col.list:
		if String(c["body"]) == body and GameData.site(c["site"]).get("default_city", false):
			return String(c["site"])
	var i := col.largest_on(body)
	return String(col.list[i]["site"]) if i >= 0 else ""


## 우주로 나가는 문: 달의 고향 (없으면 달의 중심 도시)
static func _port(col: Colonies) -> String:
	if col.index_of_site(GameData.HOME_SITE) >= 0:
		return GameData.HOME_SITE
	return _hub(col, "moon")


static func _site_with_transfer(body: String) -> Dictionary:
	for id in GameData.SITES:
		var s: Dictionary = GameData.SITES[id]
		if String(s.get("body", "")) == body and s.get("expedition", {}).has("transfer_days"):
			return s
	return {}


static func _transfer_days(body: String) -> float:
	return float(_site_with_transfer(body).get("expedition", {}).get("transfer_days", 0.0))


static func window_body(body: String) -> String:
	if WINDOW_OF.has(body):
		return WINDOW_OF[body]
	return String(_site_with_transfer(body).get("expedition", {}).get("window_from", body))


func _schedule_first(col: Colonies, l: Dictionary) -> void:
	if l["kind"] == "ship":
		l["next"] = [_next_window_h(col, l, 0, col.hour), _next_window_h(col, l, 1, col.hour)]
		return
	var every: int = maxi(1, int(l["every_h"]))
	var off := absi(String(l["id"]).hash()) % every
	@warning_ignore("integer_division")
	l["next"] = [col.hour + 1 + off, col.hour + 1 + (off + every / 2) % every]


## 수송선의 다음 출발 시각 (게임 시): 발사 창의 가운데. dir 0 = a→b, 1 = b→a
func _next_window_h(col: Colonies, l: Dictionary, dir: int, after_h: int) -> int:
	var from_b := window_body(node_body(l["a"] if dir == 0 else l["b"]))
	var to_b := window_body(node_body(l["b"] if dir == 0 else l["a"]))
	var day := window_day(from_b, to_b, float(l["trip_h"]) / 24.0, after_h / 24.0, col.start_unix)
	return maxi(after_h + 1, int(round(day * 24.0)))


## from에서 to로 전이 일수 t_days가 맞는 첫 날 (게임 일, after_day부터). 호만 전이의 위상각:
## 떠날 때 (to의 황경) − (from의 황경) = 180° − (to의 평균 운동) × t_days
static func window_day(from_b: String, to_b: String, t_days: float, after_day: float, start_unix: int) -> float:
	var p_to := Colonies._period_days(to_b)
	var syn := 1.0 / maxf(absf(1.0 / p_to - 1.0 / Colonies._period_days(from_b)), 1e-6)
	var phi := 180.0 - 360.0 / p_to * t_days
	var step := 2.0
	var d := after_day
	var prev := _phase(from_b, to_b, d, start_unix, phi)
	var limit := after_day + syn * 1.3 + 30.0
	while d < limit:
		var d1 := d + step
		var e1 := _phase(from_b, to_b, d1, start_unix, phi)
		if signf(prev) != signf(e1) and absf(prev - e1) < 90.0:
			return d + step * absf(prev) / maxf(absf(prev - e1), 1e-9)
		prev = e1
		d = d1
	return after_day + syn


static func _phase(from_b: String, to_b: String, day: float, start_unix: int, phi: float) -> float:
	var jd := Astro.jd_from_unix(float(start_unix) + day * 86400.0)
	return wrapf(Colonies._lon(to_b, jd) - Colonies._lon(from_b, jd) - phi, -180.0, 180.0)


func line_by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


# ── 한 시간 ─────────────────────────────────────────────────────
func step(col: Colonies) -> void:
	for t in trips.duplicate():
		if col.hour >= int(t["arrive"]):
			trips.erase(t)
			_arrive(col, t)
	if enabled:
		for l in lines:
			if not l["on"]:
				continue
			for dir in 2:
				if col.hour >= int(l["next"][dir]):
					_depart(col, l, dir)
	var nd := maxi(1, int(D.get("note_days", 7)))
	if col.hour % (24 * nd) == 0:
		_period_notes(col, nd)


## 교통 전체를 켜고 끈다. 다시 켜면 지난 출발 시각을 지금부터 다시 센다 (한꺼번에 떠나지 않게)
func set_enabled(col: Colonies, on: bool) -> void:
	enabled = on
	rev += 1
	if on:
		for l in lines:
			_catch_up(col, l)


## 노선 하나를 켜고 끈다
func set_line_on(col: Colonies, id: String, on: bool) -> void:
	var l := line_by_id(id)
	if l.is_empty():
		return
	l["on"] = on
	rev += 1
	if on:
		_off.erase(id)
		_catch_up(col, l)
	else:
		_off[id] = true


func _catch_up(col: Colonies, l: Dictionary) -> void:
	for dir in 2:
		if int(l["next"][dir]) <= col.hour:
			if l["kind"] == "ship":
				l["next"][dir] = _next_window_h(col, l, dir, col.hour)
			else:
				var every: int = maxi(1, int(l["every_h"]))
				l["next"][dir] = col.hour + 1 + (absi(String(l["id"]).hash()) + dir * 7) % every


func _depart(col: Colonies, l: Dictionary, dir: int) -> void:
	var src := String(l["a"] if dir == 0 else l["b"])
	var dst := String(l["b"] if dir == 0 else l["a"])
	var md := mode(l["mode"])
	var s_sim := _sim(col, src)
	var d_sim := _sim(col, dst)
	var cargo := {}
	var people: Array = []
	var pax := 0
	match String(l["role"]):
		"air":
			pax = _pax(l, md, col.hour)
		"feeder":
			if d_sim != null:
				# 대도시 → 우주항: 빈 주거만큼 정착민, 부품이 모자라면 부품. 대도시의 우주 시설이 더 싣는다
				# (이주 지원 센터: 정착민, 우주 산업 단지: 부품 — 모자라지 않아도)
				var mt: Dictionary = D.get("metro", {})
				var fb: Dictionary = col.metro_fn.feeder(src, int(mt.get("every_h", 24)))
				var inc := incoming(dst)
				var n := mini(int(mt.get("settlers", 40)) + int(fb["settlers"]), _room(d_sim) - int(inc.get("people", 0)))
				if n > 0:
					people.append([float(n), 0.0])
				var want_p := minf(float(mt.get("parts", 30)), _need(d_sim, cargo_rule("parts")) - float(d_sim.stock.get("parts", 0.0))
					- float(inc.get("parts", 0.0)))
				var extra := float(fb["parts"])
				if maxf(want_p, 0.0) + extra >= 1.0:
					cargo["parts"] = floorf(maxf(want_p, 0.0) + extra)
				col.metro_fn.note_flight(src, extra, maxi(0, mini(n, int(fb["settlers"]))))
			pax = _pax(l, md, col.hour)
		_:
			if s_sim != null and d_sim != null:
				var freight := 0.0
				if String(l["kind"]) in ["ferry", "ship"]:
					freight = float(D.get("freight", {}).get("support_per_t", 0.0))
				var inc2 := incoming(dst)
				cargo = _plan_cargo(s_sim, d_sim, float(md.get("cap_t", 0.0)), freight, inc2)
				_load(s_sim, cargo, freight)
				var n2 := _plan_people(s_sim, d_sim, int(md.get("seats", 0)), int(inc2.get("people", 0)))
				if n2 > 0:
					people = _take_people(s_sim, n2)
	var settlers := count_people(people)
	var t := {"line": l["id"], "from": src, "to": dst, "depart": col.hour, "arrive": col.hour + int(l["trip_h"]),
		"cargo": cargo, "people": people, "pax": maxi(pax, settlers), "mode": l["mode"], "kind": l["kind"]}
	trips.append(t)
	var tons := cargo_t(cargo)
	if s_sim != null and (tons > 0.0 or settlers > 0):
		_flow(src, "out_t", tons)
		_flow(src, "out_p", settlers)
	if s_sim != null:
		_event("dep", src, dst, l)
	if l["kind"] == "ship" and s_sim != null:
		s_sim.note("행성간 수송선 출발 — %s행 (%s). %s 도착 예정" % [node_name(dst), load_text(cargo, settlers),
			col.date_text(float(t["arrive"]))], "info")
	# 다음 출발
	if l["kind"] == "ship":
		l["next"][dir] = _next_window_h(col, l, dir, col.hour + 24 * 30)
	else:
		l["next"][dir] = col.hour + maxi(1, int(l["every_h"]))


func _arrive(col: Colonies, t: Dictionary) -> void:
	var dst := String(t["to"])
	var d_sim := _sim(col, dst)
	var cargo: Dictionary = t["cargo"]
	var tons := cargo_t(cargo)
	var settlers := count_people(t["people"])
	if d_sim == null and not Metros.is_metro(dst):
		# 받을 도시가 없어졌다 — 떠난 도시로 되돌아간다
		d_sim = _sim(col, String(t["from"]))
		dst = String(t["from"])
		if d_sim != null and (tons > 0.0 or settlers > 0):
			d_sim.note("교통 — %s에 닿지 못한 %s이 되돌아왔다" % [node_name(String(t["to"])), mode_name(t["mode"])], "warn")
	if d_sim != null:
		var l0 := line_by_id(String(t["line"]))
		if not l0.is_empty():
			_event("arr", dst, String(t["from"]) if dst != String(t["from"]) else String(t["to"]), l0)
		for k in cargo:
			d_sim.stock[k] = float(d_sim.stock.get(k, 0.0)) + float(cargo[k])
		for g in t["people"]:
			d_sim.cohorts.append([float(g[0]), float(g[1]), false])
		if tons > 0.0 or settlers > 0:
			_flow(dst, "in_t", tons)
			_flow(dst, "in_p", settlers)
			CitySim._add(d_sim.stats, "transport_in", 1)
		if t["kind"] == "ship":
			d_sim.note("행성간 수송선 도착 — %s에서 (%s)" % [node_name(String(t["from"])), load_text(cargo, settlers)], "good")
	var l := line_by_id(String(t["line"]))
	if not l.is_empty():
		var st: Dictionary = l["stats"]
		st["trips"] = int(st.get("trips", 0)) + 1
		st["t"] = float(st.get("t", 0.0)) + tons
		st["settlers"] = int(st.get("settlers", 0)) + settlers
		st["pax"] = int(st.get("pax", 0)) + int(t.get("pax", 0))
		var what := cargo_text(cargo)
		if settlers > 0:
			what += (" · " if what != "" else "") + "정착민 %d명" % settlers
		if what == "" and int(t.get("pax", 0)) > 0:
			what = "승객 %s명" % Fmt.n(float(t["pax"]))
		l["last"] = "%s → %s%s" % [node_name(String(t["from"])), node_name(String(t["to"])), (" · " + what) if what != "" else " · 빈 차"]
	totals["trips"] = int(totals.get("trips", 0)) + 1
	totals["t"] = float(totals.get("t", 0.0)) + tons
	totals["settlers"] = int(totals.get("settlers", 0)) + settlers
	totals["pax"] = int(totals.get("pax", 0)) + int(t.get("pax", 0))


func _event(type: String, site: String, other: String, l: Dictionary) -> void:
	_event_n += 1
	events.append({"n": _event_n, "type": type, "site": site, "other": other, "mode": l["mode"], "kind": l["kind"],
		"line": l["id"]})
	if events.size() > 96:
		events.pop_front()


## 이 도시의 n번 뒤 사건들
func events_after(site: String, n: int) -> Array:
	var out := []
	for e in events:
		if int(e["n"]) > n and e["site"] == site:
			out.append(e)
	return out


func last_event_n() -> int:
	return _event_n


func _flow(key: String, what: String, v: float) -> void:
	if v <= 0.0:
		return
	if not flow.has(key):
		flow[key] = {"in_t": 0.0, "out_t": 0.0, "in_p": 0.0, "out_p": 0.0}
	flow[key][what] = float(flow[key][what]) + v


## 기록 기간마다 도시의 기록에 남긴다: 들고 난 화물과 정착민
func _period_notes(col: Colonies, days: int) -> void:
	for c in col.list:
		var f: Dictionary = flow.get(String(c["site"]), {})
		if f.is_empty():
			continue
		var bits := []
		for side in [["in", "들어옴"], ["out", "나감"]]:
			var got := _amount_text(float(f[side[0] + "_t"]), int(f[side[0] + "_p"]))
			if got != "":
				bits.append("%s %s" % [side[1], got])
		if not bits.is_empty():
			(c["sim"] as CitySim).note("교통 — 지난 %d일 %s" % [days, ", ".join(bits)], "info")
	flow = {}


# ── 싣는 규칙 ────────────────────────────────────────────────────
## 비축 하나의 바람 (사람 수 × 하루 쓰는 양 × 일수, 또는 고정량). 바깥 공기를 마시는 도시는 산소가 필요 없다
static func _need(sim: CitySim, c: Dictionary) -> float:
	if c.is_empty():
		return 0.0
	if c.has("need_days"):
		var per := String(c.get("per", c["key"]))
		if per == "o2_kg" and sim.open_air:
			return 0.0
		return float(c["need_days"]) * sim.population() * float(sim.PER.get(per, 0.0))
	return float(c.get("need", 0.0))


## 이미 그 도시로 가는 중인 짐과 사람 {열쇠: 양, people: 명}
func incoming(key: String) -> Dictionary:
	var out := {}
	for t in trips:
		if t["to"] != key:
			continue
		var c: Dictionary = t["cargo"]
		for k in c:
			out[k] = float(out.get(k, 0.0)) + float(c[k])
		out["people"] = int(out.get("people", 0)) + count_people(t["people"])
	return out


func _plan_cargo(src: CitySim, dst: CitySim, cap_t: float, freight: float, inc: Dictionary = {}) -> Dictionary:
	var out := {}
	var room := cap_t
	if freight > 0.0:
		room = minf(room, maxf(0.0, src.support) / freight)
	for c in D.get("cargo", []):
		if room < 0.05:
			break
		var k := String(c["key"])
		var tp := float(c["t_per"])
		if dst.supply.has(k):
			continue                                  # 받는 도시는 시장이 채운다
		var have := float(dst.stock.get(k, 0.0)) + float(inc.get(k, 0.0))
		var want := _need(dst, c) - have
		if dst.caps.has(k):
			want = minf(want, float(dst.caps[k]) * 0.98 - have)
		if want <= 0.0:
			continue
		var give := want if src.supply.has(k) else float(src.stock.get(k, 0.0)) - _need(src, c) * float(c.get("keep_x", 1.5))
		var amt := minf(minf(want, give), room / tp)
		if tp >= 0.1:
			amt = floorf(amt)
		if amt * tp < 0.05:
			continue
		out[k] = amt
		room -= amt * tp
	return out


## 보내는 도시가 싣는다 (시장에서 사는 것은 비축에서 빼지 않는다), 운임은 지원 점수로
static func _load(src: CitySim, cargo: Dictionary, freight: float) -> void:
	for k in cargo:
		if not src.supply.has(k):
			src.stock[k] = float(src.stock.get(k, 0.0)) - float(cargo[k])
	if freight > 0.0:
		src.support -= cargo_t(cargo) * freight


## 받을 수 있는 사람 (주거의 keep_free를 비워 두고, 바깥 공기를 마시지 않으면 CO₂ 제거 여유까지)
static func _room(sim: CitySim) -> int:
	var p: Dictionary = data().get("people", {})
	var pop := sim.population()
	var free := sim.housing_cap * (1.0 - float(p.get("keep_free", 0.05))) - pop
	if sim.seat_limit_by_scrubbers and not sim.open_air:
		free = minf(free, sim.fam_prov("co2_scrubber", "co2_kg_day") / float(sim.PER["co2_kg"]) / 1.1 - pop)
	return maxi(0, int(floor(free)))


## 식량(과 바깥 공기를 마시지 않으면 산소)이 days일 넘게 있나
static func _fed(sim: CitySim, days: float) -> bool:
	var pop := maxf(sim.population(), 1.0)
	if float(sim.stock.get("food_kg", 0.0)) / (pop * float(sim.PER["food_kg"])) < days:
		return false
	return sim.open_air or float(sim.stock.get("o2_kg", 0.0)) / (pop * float(sim.PER["o2_kg"])) >= days


func _plan_people(src: CitySim, dst: CitySim, seats: int, coming: int = 0) -> int:
	if seats <= 0:
		return 0
	var p: Dictionary = D.get("people", {})
	var room := _room(dst) - coming
	if room <= 0 or not _fed(dst, float(p.get("min_days", 30))):
		return 0
	var pop := src.population()
	var spare: float
	if src.open_air:
		spare = minf(pop * float(p.get("earth_share", 0.15)), pop - float(p.get("min_pop", 20)))
	else:
		spare = pop - float(p.get("crowded", 0.95)) * src.housing_cap
	var cap := maxf(5.0, dst.population() * float(p.get("max_frac", 0.1)))
	return maxi(0, int(floor(minf(minf(float(seats), float(room)), minf(spare, cap)))))


## 사람을 태운다: 새로 온 무리부터 (선량 한도에 닿아 귀환을 기다리는 사람은 남는다) — [[명, 선량]]
static func _take_people(sim: CitySim, n: int) -> Array:
	var out := []
	var left := float(n)
	for i in range(sim.cohorts.size() - 1, -1, -1):
		if left <= 0.0:
			break
		var c: Array = sim.cohorts[i]
		if c[2]:
			continue
		var take := minf(float(c[0]), left)
		if take <= 0.0:
			continue
		c[0] = float(c[0]) - take
		left -= take
		out.append([take, float(c[1])])
	sim.cohorts = sim.cohorts.filter(func(c): return c[0] > 0)
	return out


static func _pax(l: Dictionary, md: Dictionary, hour: int) -> int:
	var k := 0.68 + 0.27 * float(absi(("%s/%d" % [l["id"], hour]).hash()) % 1000) / 1000.0
	return int(float(md.get("seats", 0)) * k)


# ── 보여 주기 ───────────────────────────────────────────────────
static func count_people(people: Array) -> int:
	var n := 0.0
	for g in people:
		n += float(g[0])
	return int(round(n))


static func cargo_t(cargo: Dictionary) -> float:
	var t := 0.0
	for k in cargo:
		t += float(cargo[k]) * float(cargo_rule(String(k)).get("t_per", 0.001))
	return t


## "12.0 t · 정착민 5명" (없으면 "")
static func _amount_text(tons: float, people: int) -> String:
	var bits := []
	if tons >= 0.05:
		bits.append("%s t" % Fmt.n(tons, 1))
	if people > 0:
		bits.append("정착민 %d명" % people)
	return " · ".join(bits)


## 배에 실은 것: "화물 12.0 t · 정착민 5명" / "빈 배"
static func load_text(cargo: Dictionary, settlers: int) -> String:
	var bits := []
	var tons := cargo_t(cargo)
	if tons > 0.0:
		bits.append("화물 %s t" % Fmt.n(tons, 1))
	if settlers > 0:
		bits.append("정착민 %d명" % settlers)
	return " · ".join(bits) if not bits.is_empty() else "빈 배"


## "식량 2.1 t · 부품 40"
static func cargo_text(cargo: Dictionary) -> String:
	var bits := []
	for c in data().get("cargo", []):
		var k := String(c["key"])
		if not cargo.has(k):
			continue
		var v := float(cargo[k])
		if k == "parts":
			bits.append("%s %s" % [c["name"], Fmt.n(v)])
		elif k == "metal_t":
			bits.append("%s %s t" % [c["name"], Fmt.n(v, 1)])
		else:
			bits.append("%s %s t" % [c["name"], Fmt.n(v / 1000.0, 1)])
	return " · ".join(bits)


## 이동 중인 탈것: 노선마다 [{trip, k(0~1)}] — 3D 지도가 점으로 그린다
func moving(hour_f: float) -> Array:
	var out := []
	for t in trips:
		var span := maxf(1.0, float(t["arrive"]) - float(t["depart"]))
		out.append({"trip": t, "k": clampf((hour_f - float(t["depart"])) / span, 0.0, 1.0)})
	return out


## 노선의 다음 출발까지 (시)
func next_in(col: Colonies, l: Dictionary) -> int:
	return maxi(0, mini(int(l["next"][0]), int(l["next"][1])) - col.hour)


## 지금 그 노선을 달리는 탈것 수
func running(id: String) -> int:
	var n := 0
	for t in trips:
		if t["line"] == id:
			n += 1
	return n


## 이 노드에 닿는 노선들
func lines_of(key: String) -> Array:
	var out := []
	for l in lines:
		if l["a"] == key or l["b"] == key:
			out.append(l)
	return out


# ── 저장 ───────────────────────────────────────────────────────
func to_save() -> Dictionary:
	var ls := []
	for l in lines:
		ls.append({"id": l["id"], "next": l["next"], "stats": l["stats"], "last": l.get("last", "")})
	return {"version": SAVE_VERSION, "enabled": enabled, "off": _off.keys(), "lines": ls, "trips": trips,
		"flow": flow, "totals": totals}


## 저장을 읽고 노선을 다시 짠다 (교통이 없던 저장이면 새로)
func load_save(data_in: Dictionary, col: Colonies) -> void:
	rev += 1
	reset()
	if not data_in.is_empty():
		enabled = bool(data_in.get("enabled", true))
		for id in data_in.get("off", []):
			_off[String(id)] = true
		for l in data_in.get("lines", []):
			var st: Dictionary = l.get("stats", {})
			_state[String(l["id"])] = {"next": [int(l["next"][0]), int(l["next"][1])],
				"stats": {"trips": int(st.get("trips", 0)), "t": float(st.get("t", 0.0)),
					"settlers": int(st.get("settlers", 0)), "pax": int(st.get("pax", 0))},
				"last": String(l.get("last", ""))}
		for t in data_in.get("trips", []):
			var people := []
			for g in t.get("people", []):
				people.append([float(g[0]), float(g[1])])
			var cargo := {}
			var cd: Dictionary = t.get("cargo", {})
			for k in cd:
				cargo[String(k)] = float(cd[k])
			trips.append({"line": String(t["line"]), "from": String(t["from"]), "to": String(t["to"]),
				"depart": int(t["depart"]), "arrive": int(t["arrive"]), "cargo": cargo, "people": people,
				"pax": int(t.get("pax", 0)), "mode": String(t.get("mode", "")), "kind": String(t.get("kind", "ground"))})
		var fl: Dictionary = data_in.get("flow", {})
		for k in fl:
			var f: Dictionary = fl[k]
			flow[String(k)] = {"in_t": float(f.get("in_t", 0.0)), "out_t": float(f.get("out_t", 0.0)),
				"in_p": float(f.get("in_p", 0.0)), "out_p": float(f.get("out_p", 0.0))}
		var tt: Dictionary = data_in.get("totals", {})
		totals = {"trips": int(tt.get("trips", 0)), "t": float(tt.get("t", 0.0)), "settlers": int(tt.get("settlers", 0)),
			"pax": int(tt.get("pax", 0))}
	rebuild(col)
