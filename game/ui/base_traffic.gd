class_name BaseTraffic
extends RefCounted
## 지도의 탈것과 사람 — 시뮬레이션의 사건(착륙선 도착, 공사, 고장)에 맞춰 움직인다.
## 도시 사이 교통(Transport)의 출발·도착도 띄운다: 로버 화물 열차는 고속도로로 드나들고, 호퍼·회전익기는 착륙장으로
## 날아들고, 셔틀·수송선의 착륙선은 착륙장에 내리고 오르며, 비행기는 활주로에 내리고 뜬다.
## 길은 배치 계획(CityPlan)의 길 그물을 따라 찾는다. 보여 주기만 한다. 시뮬레이션 숫자에는 영향을 주지 않는다.

const LANDER_HIGH := 150.0        # 착륙선이 나타나는 높이 (m)
const DESCEND_S := 4.0
const LANDED_S := 7.0
const ASCEND_S := 3.5
const MAX_ROBOTS := 10
const WALKERS := 6
const MAX_TRANSIT := 8            # 한꺼번에 보이는 교통 탈것 (빠르게 흐를 때 넘치지 않게)
const COMMUTERS := 6              # 출퇴근 시간(7~9시 집 → 일터, 17~19시 일터 → 집)에 길을 다니는 통근 탈것
const FREIGHT := 2                # 일하는 시간(8~18시)에 만드는 건물과 저장 시설 사이를 오가는 화물 탈것
const TRANSIT_ROLES := ["convoy", "fly", "plane", "transit_lander"]
const ROLE_CAP := {"convoy": 6, "fly": 2, "plane": 2, "transit_lander": 1}    # 갈래마다 (열차는 세 대가 한 편)

var plan: CityPlan
var agents: Array = []
var _seen := {}
var _landers_waiting: Array = []
var _rng := RandomNumberGenerator.new()
var _ev_n := -1                   # 본 교통 사건 번호 (-1 = 아직 맞추지 않았다)
var _trips := {}                  # 통근·물류의 끝점: {rev, homes, works, makers, stores} (배치가 바뀔 때까지)
var _site := ""


func _init(p_plan: CityPlan = null) -> void:
	plan = p_plan
	_rng.seed = 2061


## 새 게임이나 불러오기: 지난 사건을 다시 보여 주지 않도록 기준을 맞춘다
func reset(sim: CitySim) -> void:
	agents.clear()
	_landers_waiting.clear()
	_ev_n = -1
	for key in ["cargo_delivered", "express", "arrived"]:
		_seen[key] = int(sim.stats.get(key, 0)) if sim else 0


func update(dt: float, sim: CitySim, sites: Array) -> void:
	if sim == null or plan == null:
		return
	_events(sim)
	_ensure(sim)
	if dt <= 0.0:
		return
	for a in agents.duplicate():
		_step(a, dt, sim, sites)
	agents = agents.filter(func(a): return not a.get("gone", false))


# ── 사건 ────────────────────────────────────────────────────────
func _events(sim: CitySim) -> void:
	for pair in [["cargo_delivered", "cargo_lander"], ["express", "cargo_lander"], ["arrived", "crew_lander"]]:
		var key: String = pair[0]
		var now := int(sim.stats.get(key, 0))
		if now > int(_seen.get(key, 0)):
			_landers_waiting.append(pair[1])
		_seen[key] = now
	if _landers_waiting.is_empty():
		return
	for a in agents:
		if a["role"] == "lander":
			return
	var kind: String = _landers_waiting.pop_front()
	var pad := _pad_spot()
	agents.append({"role": "lander", "id": kind, "pos": pad + Vector3(0, 0, LANDER_HIGH), "base": pad,
		"state": "descend", "t": 0.0, "thrust": true, "flying": true, "heading": "se", "path": [], "wait": 0.0})


func _pad_spot() -> Vector3:
	var pads := plan.built_of_family("landing_pad")
	if pads.is_empty():
		pads = plan.layout.slots.get("landing_pad", [])
	return pads[0] if pads.size() > 0 else Vector3.ZERO


## 길 그물 위에서 이 점과 가장 가까운 곳 (길이 없으면 그 점)
func _road_point(p: Vector3) -> Vector3:
	var k := plan.nearest_edge(Vector2(p.x, p.y))
	if k < 0:
		return p
	var q := CityPlan._seg_point(plan.nodes[plan.edges[k].x], plan.nodes[plan.edges[k].y], Vector2(p.x, p.y))
	return Vector3(q.x, q.y, 0)


func _hub() -> Vector3:
	var h := plan.hub()
	return Vector3(h.x, h.y, 0)


## 이 종류 중 하나가 서 있는 곳 (없으면 기본 배치의 구역 문)
func _place_of(kinds: Array, gate: String) -> Vector3:
	for kind in kinds:
		var list := plan.built_of_family(kind)
		if not list.is_empty():
			return list[0]
	return plan.layout.gates.get(gate, _hub())


# ── 항상 있는 탈것 ──────────────────────────────────────────────
func _count(role: String) -> int:
	var n := 0
	for a in agents:
		if a["role"] == role:
			n += 1
	return n


func _spawn(role: String, id: String, pos: Vector3, speed: float, extra: Dictionary = {}) -> Dictionary:
	var a := {"role": role, "id": id, "pos": pos, "heading": "se", "path": [], "speed": speed,
		"state": "idle", "wait": _rng.randf_range(0.0, 2.0), "home": pos, "flying": false, "thrust": false}
	a.merge(extra, true)
	agents.append(a)
	return a


func _ensure(sim: CitySim) -> void:
	var n := {}                          # 갈래마다 몇 대 (프레임마다 한 번만 센다)
	for a in agents:
		n[a["role"]] = int(n.get(a["role"], 0)) + 1
	var rovers := int(n.get("rover", 0))
	if rovers < 2:
		_spawn("rover", "ltv", _hub() + Vector3(rovers * 6.0, 0, 0), 7.0)
	if int(n.get("cruiser", 0)) < 1:
		_spawn("cruiser", "pressurized_rover", _hub() + Vector3(-8, 0, 0), 4.5)
	if int(n.get("hauler", 0)) < 1:
		_spawn("hauler", "cargo_hauler", _road_point(_pad_spot()), 5.0, {"state": "parked"})
	if int(n.get("hopper", 0)) < 1:
		var home: Vector3 = plan.layout.gates.get("life", _hub()) + Vector3(-6, 6, 0)
		_spawn("hopper", "hopper", home, 0.0, {"state": "parked", "wait": 12.0})
	var digs_at := plan.built_of_family("excavator")
	var digs := mini(digs_at.size(), 2)
	var dn := int(n.get("digger", 0))
	while dn < digs:
		var site: Vector3 = digs_at[dn]
		_spawn("digger", "excavator_robot", site + Vector3(-7, -3, 0), 1.6, {"site": site})
		dn += 1
	while dn > digs:
		_remove_one("digger")
		dn -= 1
	var working := clampi(sim.robots - sim.robots_broken, 0, MAX_ROBOTS)
	var rn := int(n.get("robot", 0))
	if rn != working:
		var bay := _robot_home(sim)
		while rn < working:
			var k := rn
			_spawn("robot", "builder_robot", bay + Vector3((k % 4) * 3.0 - 4.5, 7.0 + floorf(k / 4.0) * 3.0, 0), 3.5,
				{"index": k, "state": "home"})
			rn += 1
		while rn > working:
			_remove_one("robot")
			rn -= 1
	var wn := int(n.get("walker", 0))
	while wn < WALKERS:
		_spawn("walker", "astronaut", _random_core_spot(), 1.4)
		wn += 1
	# 통근 (CityServices의 통근 시간이 그 길을 따른다): 출근은 집 → 일터, 퇴근은 일터 → 집. 닿으면 사라진다
	var hod := sim.hour % 24
	var ends := _trip_ends()
	var rush := 1 if hod >= 7 and hod < 10 else (-1 if hod >= 17 and hod < 20 else 0)
	if rush != 0 and not ends["homes"].is_empty() and not ends["works"].is_empty():
		var cn := int(n.get("commuter", 0))
		while cn < COMMUTERS:
			var h: Vector3 = ends["homes"][_rng.randi() % ends["homes"].size()]
			var w: Vector3 = ends["works"][_rng.randi() % ends["works"].size()]
			var from := h if rush > 0 else w
			var to := w if rush > 0 else h
			var c := _spawn("commuter", "ltv" if _rng.randf() < 0.7 else "pressurized_rover", _road_point(from), 7.0,
				{"state": "go", "wait": _rng.randf_range(0.0, 3.0)})
			c["path"] = plan.route(c["pos"], _road_point(to))
			cn += 1
	if hod >= 8 and hod < 18 and not ends["makers"].is_empty() and not ends["stores"].is_empty():
		var fn := int(n.get("freight", 0))
		while fn < FREIGHT:
			var m: Vector3 = ends["makers"][_rng.randi() % ends["makers"].size()]
			var s: Vector3 = ends["stores"][_rng.randi() % ends["stores"].size()]
			var f := _spawn("freight", "cargo_hauler", _road_point(m), 5.0, {"state": "go"})
			f["path"] = plan.route(f["pos"], _road_point(s))
			fn += 1


## 통근·물류의 끝점 (배치의 판이 바뀔 때까지 같은 답): 집(집이 있는 건물), 일터(일손이 있는 건물), 만드는 건물(산업), 저장 시설
func _trip_ends() -> Dictionary:
	if int(_trips.get("rev", -1)) == plan.revision:
		return _trips
	_trips = {"rev": plan.revision, "homes": [], "works": [], "makers": [], "stores": []}
	for e in plan.buildings:
		if int(e["seq"]) >= 0:
			continue
		var m: Dictionary = GameData.MODULES.get(String(e["id"]), {})
		var pv: Dictionary = m.get("provides", {})
		var p := Vector3(float(e["x"]), float(e["y"]), 0)
		if float(pv.get("housing", 0.0)) > 0.0:
			_trips["homes"].append(p)
		if int(m.get("crew", 0)) > 0:
			_trips["works"].append(p)
		if String(m.get("category", "")) == "industry":
			_trips["makers"].append(p)
		if pv.has("storage"):
			_trips["stores"].append(p)
	return _trips


func _remove_one(role: String) -> void:
	for i in range(agents.size() - 1, -1, -1):
		if agents[i]["role"] == role:
			agents.remove_at(i)
			return


func _robot_home(_sim: CitySim) -> Vector3:
	return _place_of(["robot_bay"], "industry")


func _random_core_spot() -> Vector3:
	## 거주 모듈 하나의 옆 (사람이 걸어 다니는 곳)
	var habs := plan.built_of_family("hab_module")
	if habs.is_empty():
		return _hub()
	var h: Vector3 = habs[_rng.randi() % habs.size()]
	var f := ArtLib.footprint("hab_module")
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	return h + Vector3(_rng.randf_range(-f.x, f.x) * 0.5, side * (f.y * 0.5 + 1.5), 0)


# ── 움직임 ──────────────────────────────────────────────────────
func _step(a: Dictionary, dt: float, sim: CitySim, sites: Array) -> void:
	match a["role"]:
		"lander":
			_lander(a, dt)
			return
		"hopper":
			_hopper(a, dt, sim)
			return
		"convoy":
			_convoy(a, dt)
			return
		"fly":
			_fly(a, dt)
			return
		"plane":
			_plane(a, dt)
			return
		"transit_lander":
			_transit_lander(a, dt)
			return
	if not a["path"].is_empty():
		_move(a, dt)
		return
	if a["wait"] > 0.0:
		a["wait"] -= dt
		return
	match a["role"]:
		"rover":
			var n := plan.random_node(_rng)
			a["path"] = plan.route(a["pos"], Vector3(n.x, n.y, 0))
			a["wait"] = _rng.randf_range(1.5, 4.0)
		"cruiser":
			var out: bool = a["state"] != "out"
			a["state"] = "out" if out else "idle"
			var dest := _road_point(_place_of(["ice_miner"], "ice")) if out else _hub()
			a["path"] = plan.route(a["pos"], dest)
			a["wait"] = _rng.randf_range(4.0, 8.0)
		"hauler":
			_hauler(a)
		"digger":
			var site: Vector3 = a["site"]
			var other := site + Vector3(-7, 3, 0) if a["pos"].y < site.y else site + Vector3(-7, -3, 0)
			a["path"] = [other]
			a["wait"] = 1.0
		"robot":
			_robot(a, sim, sites)
		"walker":
			var dest := _random_core_spot()
			a["path"] = [Vector3(dest.x, a["pos"].y, 0), dest]
			a["wait"] = _rng.randf_range(1.0, 5.0)
		"commuter", "freight":
			a["gone"] = true                # 닿았다


func _move(a: Dictionary, dt: float) -> void:
	var left: float = a["speed"] * dt
	while left > 0.0 and not a["path"].is_empty():
		var target: Vector3 = a["path"][0]
		var d: Vector3 = target - a["pos"]
		var dist := d.length()
		if dist > 0.01:
			a["heading"] = heading_of(d)
		if dist <= left:
			a["pos"] = target
			a["path"].pop_front()
			left -= dist
		else:
			a["pos"] += d / dist * left
			left = 0.0


static func heading_of(d: Vector3) -> String:
	if absf(d.x) >= absf(d.y):
		return "se" if d.x > 0 else "nw"
	return "sw" if d.y > 0 else "ne"


func _hauler(a: Dictionary) -> void:
	match a["state"]:
		"parked":
			pass
		"loaded":
			a["state"] = "delivering"
			a["path"] = plan.route(a["pos"], _road_point(_place_of(["tank_farm", "electrolyzer", "food_store"], "life")))
		"delivering":
			a["state"] = "returning"
			a["wait"] = 3.0
		"returning":
			a["state"] = "home"
			a["path"] = plan.route(a["pos"], _road_point(_pad_spot()))
		"home":
			a["state"] = "parked"


func _robot(a: Dictionary, sim: CitySim, sites: Array) -> void:
	if sites.is_empty():
		if a["state"] != "home":
			a["state"] = "home"
			var home := _robot_home(sim) + Vector3((a["index"] % 4) * 3.0 - 4.5, 7.0 + (a["index"] / 4) * 3.0, 0)
			a["path"] = plan.route(a["pos"], home)
		return
	var site: Dictionary = sites[a["index"] % sites.size()]
	var spot: Vector3 = site["pos"] + Vector3(site["foot"].x * 0.5 + 2.5, (a["index"] % 3 - 1) * 2.0, 0)
	if a["state"] == "work" and a.get("site_key", "") == site["key"]:
		a["wait"] = 0.5
		return
	if a["pos"].distance_to(spot) < 1.0:
		a["state"] = "work"
		a["site_key"] = site["key"]
		a["heading"] = "nw"
		return
	a["state"] = "going"
	a["site_key"] = site["key"]
	a["path"] = plan.route(a["pos"], spot)


func _lander(a: Dictionary, dt: float) -> void:
	a["t"] += dt
	var base: Vector3 = a["base"]
	match a["state"]:
		"descend":
			var k := clampf(a["t"] / DESCEND_S, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			a["pos"] = base + Vector3(0, 0, LANDER_HIGH * (1.0 - e))
			a["thrust"] = true
			if k >= 1.0:
				a["state"] = "landed"
				a["t"] = 0.0
				a["thrust"] = false
				if a["id"] == "cargo_lander":
					for h in agents:
						if h["role"] == "hauler" and h["state"] == "parked":
							h["state"] = "loaded"
							h["wait"] = 2.0
		"landed":
			if a["t"] >= LANDED_S:
				a["state"] = "ascend"
				a["t"] = 0.0
		"ascend":
			var k := clampf(a["t"] / ASCEND_S, 0.0, 1.0)
			a["pos"] = base + Vector3(0, 0, LANDER_HIGH * 1.3 * k * k)
			a["thrust"] = true
			if k >= 1.0:
				a["gone"] = true


func _hopper(a: Dictionary, dt: float, sim: CitySim) -> void:
	match a["state"]:
		"parked", "at_tower":
			a["thrust"] = false
			a["wait"] -= dt
			if a["wait"] > 0.0:
				return
			var towers := plan.built_of_family("solar_tower")
			if a["state"] == "parked":
				if towers.is_empty():
					a["wait"] = 10.0
					return
				var t: Vector3 = towers[_rng.randi() % towers.size()] + Vector3(6, 6, 0)
				_start_hop(a, t, "to_tower")
			else:
				_start_hop(a, a["home"], "to_home")
		"to_tower", "to_home":
			a["t"] += dt
			var k := clampf(a["t"] / a["dur"], 0.0, 1.0)
			var p: Vector3 = a["from"].lerp(a["to"], k)
			p.z = 4.0 * a["apex"] * k * (1.0 - k)
			a["pos"] = p
			a["thrust"] = k < 0.3 or k > 0.75
			a["flying"] = true
			if k >= 1.0:
				a["flying"] = false
				a["thrust"] = false
				a["state"] = "at_tower" if a["state"] == "to_tower" else "parked"
				a["wait"] = 5.0 if a["state"] == "at_tower" else _rng.randf_range(18.0, 30.0)


func _start_hop(a: Dictionary, to: Vector3, state: String) -> void:
	a["from"] = a["pos"]
	a["to"] = to
	a["t"] = 0.0
	var dist: float = a["from"].distance_to(to)
	a["dur"] = clampf(dist / 30.0, 3.0, 7.0)
	a["apex"] = clampf(dist * 0.35, 20.0, 60.0)
	a["state"] = state


# ── 도시 사이 교통 ─────────────────────────────────────────────
## 교통의 새 사건(이 도시의 출발·도착)을 탈것으로 띄운다. ways: City3D의 고속도로·활주로·방향
## 도시가 보이지 않는 동안: 그동안의 도시 사이 사건은 탈것으로 띄우지 않는다 (다시 보일 때 지난 일이 한꺼번에 뜨지 않게)
func forget_events() -> void:
	_ev_n = -1


func intercity(tr: Transport, site: String, ways: Dictionary) -> void:
	if plan == null:
		return
	if site != _site or _ev_n < 0:
		_site = site
		_ev_n = tr.last_event_n()            # 처음에는 지난 일을 다시 보이지 않는다
		return
	var evs := tr.events_after(site, _ev_n)
	if evs.is_empty():
		return
	_ev_n = int(evs[-1]["n"])
	for e in evs:
		var n := 0
		var by_role := {}
		for a in agents:
			if a["role"] in TRANSIT_ROLES:
				n += 1
				by_role[a["role"]] = int(by_role.get(a["role"], 0)) + 1
		if n >= MAX_TRANSIT:
			break
		var role := _transit_role(e, ways)
		if int(by_role.get(role, 0)) >= int(ROLE_CAP.get(role, 2)):
			continue
		_spawn_transit(e, ways)


## 그 사건이 띄울 탈것의 갈래
func _transit_role(e: Dictionary, ways: Dictionary) -> String:
	match String(e["kind"]):
		"ground":
			return "convoy"
		"air":
			var vehicle := String(Transport.mode(e["mode"]).get("vehicle", ""))
			if vehicle in ["airliner", "mars_plane"] and not ways.get("runway", {}).is_empty():
				return "plane"
			return "fly"
		"hop":
			return "fly"
	return "transit_lander"


func _spawn_transit(e: Dictionary, ways: Dictionary) -> void:
	var arr := String(e["type"]) == "arr"
	var vehicle := String(Transport.mode(e["mode"]).get("vehicle", "cargo_hauler"))
	var bearing: Vector2 = ways.get("bearings", {}).get(e["line"], Vector2(1, 0))
	var dir3 := Vector3(bearing.x, bearing.y, 0.0)
	var pad := _transit_pad()
	match String(e["kind"]):
		"ground":
			var h: Dictionary = ways.get("highways", {}).get(e["line"], {})
			if h.is_empty():
				return
			var a3 := Vector3(h["a"].x, h["a"].y, 0)
			var b3 := Vector3(h["b"].x, h["b"].y, 0)
			var far := a3.lerp(b3, 0.4)
			var depot := _road_point(_place_of(["food_store", "tank_farm", "parts_fab"], "industry"))
			for k in 3:
				if arr:
					var start := far + (b3 - a3).normalized() * (k * 16.0)
					var path := [a3]
					path.append_array(plan.route(a3, depot))
					_spawn("convoy", vehicle, start, 12.0, {"path": path, "wait": k * 1.3, "state": "arr"})
				else:
					var path2 := plan.route(depot, a3)
					path2.append(far)
					_spawn("convoy", vehicle, depot, 12.0, {"path": path2, "wait": k * 1.3, "state": "dep"})
		"air":
			var rw: Dictionary = ways.get("runway", {})
			if vehicle in ["airliner", "mars_plane"] and not rw.is_empty():
				_spawn_plane(vehicle, rw, arr)
			else:
				_spawn_fly(vehicle, pad, dir3, arr, 160.0)
		"hop":
			_spawn_fly(vehicle, pad, dir3, arr, 240.0)
		"ferry", "ship":
			var id := vehicle if String(e["kind"]) == "ferry" else "cargo_lander"
			var high := 420.0 if String(e["kind"]) == "ferry" else LANDER_HIGH * 1.6
			_spawn("transit_lander", id, pad + Vector3(0, 0, high if arr else 0.0), 0.0,
				{"base": pad, "state": "descend" if arr else "landed", "t": 0.0, "high": high, "flying": true,
				"thrust": arr, "stay": 6.0 if arr else 3.0})


## 교통 착륙선이 내리는 착륙장: 두 번째 착륙장이 있으면 그것 (화물선 착륙선과 겹치지 않게)
func _transit_pad() -> Vector3:
	var pads := plan.built_of_family("landing_pad")
	if pads.size() >= 2:
		return pads[1]
	if pads.size() == 1:
		return pads[0] + Vector3(0, 26, 0)
	var slots: Array = plan.layout.slots.get("landing_pad", [])
	return slots[1] if slots.size() >= 2 else _pad_spot()


## 호퍼·회전익기: 다른 도시 쪽 하늘에서 날아들어 착륙장에 내리거나, 거기서 떠올라 그쪽으로 사라진다
func _spawn_fly(vehicle: String, pad: Vector3, dir3: Vector3, arr: bool, high: float) -> void:
	var far := pad + dir3 * 900.0 + Vector3(0, 0, high)
	if arr:
		_spawn("fly", vehicle, far, 0.0, {"from": far, "to": pad, "t": 0.0, "dur": 7.0, "apex": 60.0, "flying": true,
			"thrust": true, "land": true})
	else:
		_spawn("fly", vehicle, pad, 0.0, {"from": pad, "to": far, "t": 0.0, "dur": 7.0, "apex": 60.0, "flying": true,
			"thrust": true, "land": false, "wait": 2.0})


func _fly(a: Dictionary, dt: float) -> void:
	if a["wait"] > 0.0:
		a["wait"] -= dt
		return
	if a.get("parked", false):
		a["gone"] = true
		return
	a["t"] += dt
	var k := clampf(a["t"] / a["dur"], 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var p: Vector3 = (a["from"] as Vector3).lerp(a["to"], e)
	p.z += 4.0 * float(a["apex"]) * e * (1.0 - e)
	a["pos"] = p
	a["thrust"] = k < 0.3 or k > 0.7
	if k >= 1.0:
		a["thrust"] = false
		if a["land"]:
			a["flying"] = false
			a["parked"] = true
			a["wait"] = 5.0
		else:
			a["gone"] = true


## 비행기: 활주로 a→b 방향으로 내려앉아 달리다 멈추거나, 달려서 떠올라 사라진다
func _spawn_plane(vehicle: String, rw: Dictionary, arr: bool) -> void:
	var a2: Vector2 = rw["a"]
	var b2: Vector2 = rw["b"]
	var length := a2.distance_to(b2)
	var d := (b2 - a2) / length
	var a3 := Vector3(a2.x, a2.y, 0)
	var d3 := Vector3(d.x, d.y, 0)
	var big := vehicle == "airliner"
	var speed := 140.0 if big else 60.0
	# 같은 쪽(내리기·뜨기)의 비행기가 이미 있으면 줄을 선다 — 같은 길을 겹쳐 날지 않게
	var queue := 0
	for o in agents:
		if o["role"] == "plane" and String(o["state"]) == ("arr" if arr else "dep"):
			queue += 1
	if arr:
		var back := (3200.0 if big else 900.0) + queue * (2600.0 if big else 700.0)
		var start := a3 - d3 * back + Vector3(0, 0, back * (0.053 if big else 0.078))     # 같은 활공각
		var touch := a3 + d3 * (260.0 if big else 80.0)
		var stop := a3 + d3 * length * 0.72
		_spawn("plane", vehicle, start, speed, {"legs": [[touch, speed], [stop, 14.0]], "flying": true, "state": "arr"})
	else:
		var s3 := a3 + d3 * (150.0 if big else 60.0)
		var lift := a3 + d3 * length * 0.62
		var out := a3 + d3 * (length + (2600.0 if big else 900.0)) + Vector3(0, 0, 320.0 if big else 120.0)
		_spawn("plane", vehicle, s3, 16.0, {"legs": [[lift, speed], [out, speed * 1.1]], "flying": false, "state": "dep",
			"wait": 1.5 + queue * 30.0})


func _plane(a: Dictionary, dt: float) -> void:
	if a["wait"] > 0.0:
		a["wait"] -= dt
		return
	var legs: Array = a["legs"]
	if legs.is_empty():
		a["gone"] = true
		return
	var target: Vector3 = legs[0][0]
	var want: float = legs[0][1]
	a["speed"] = move_toward(float(a["speed"]), want, dt * 40.0)
	var d: Vector3 = target - a["pos"]
	var dist := d.length()
	var stepm := float(a["speed"]) * dt
	if dist <= stepm:
		a["pos"] = target
		legs.pop_front()
		if a["state"] == "arr" and legs.size() == 1:
			a["flying"] = false               # 바퀴가 닿았다
		elif a["state"] == "dep" and legs.size() == 1:
			a["flying"] = true                # 떠올랐다
		if legs.is_empty() and a["state"] == "arr":
			a["wait"] = 2.5
	else:
		a["pos"] += d / dist * stepm
	a["heading"] = heading_of(d)


## 셔틀·수송선 착륙선: 높이 high에서 내려와 머물다 다시 오르거나 (도착), 착륙장에 서 있다 오른다 (출발)
func _transit_lander(a: Dictionary, dt: float) -> void:
	a["t"] += dt
	var base: Vector3 = a["base"]
	var high: float = a["high"]
	match a["state"]:
		"descend":
			var k := clampf(a["t"] / 5.0, 0.0, 1.0)
			a["pos"] = base + Vector3(0, 0, high * (1.0 - (1.0 - pow(1.0 - k, 3.0))))
			a["thrust"] = true
			if k >= 1.0:
				a["state"] = "landed"
				a["t"] = 0.0
				a["thrust"] = false
		"landed":
			a["pos"] = base
			a["thrust"] = false
			if a["t"] >= float(a["stay"]):
				a["state"] = "ascend"
				a["t"] = 0.0
		"ascend":
			var k2 := clampf(a["t"] / 4.0, 0.0, 1.0)
			a["pos"] = base + Vector3(0, 0, high * 1.2 * k2 * k2)
			a["thrust"] = true
			if k2 >= 1.0:
				a["gone"] = true


func _convoy(a: Dictionary, dt: float) -> void:
	if a["wait"] > 0.0:
		a["wait"] -= dt
		return
	if not a["path"].is_empty():
		_move(a, dt)
		return
	if a["state"] == "arr":
		a["state"] = "parked"
		a["wait"] = 4.0
	else:
		a["gone"] = true
