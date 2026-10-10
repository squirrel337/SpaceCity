class_name BaseTraffic
extends RefCounted
## 지도의 탈것과 사람 — 시뮬레이션의 사건(착륙선 도착, 공사, 고장)에 맞춰 움직인다.
## 길은 배치 계획(CityPlan)의 길 그물을 따라 찾는다. 보여 주기만 한다. 시뮬레이션 숫자에는 영향을 주지 않는다.

const LANDER_HIGH := 150.0        # 착륙선이 나타나는 높이 (m)
const DESCEND_S := 4.0
const LANDED_S := 7.0
const ASCEND_S := 3.5
const MAX_ROBOTS := 10
const WALKERS := 6

var plan: CityPlan
var agents: Array = []
var _seen := {}
var _landers_waiting: Array = []
var _rng := RandomNumberGenerator.new()


func _init(p_plan: CityPlan = null) -> void:
	plan = p_plan
	_rng.seed = 2061


## 새 게임이나 불러오기: 지난 사건을 다시 보여 주지 않도록 기준을 맞춘다
func reset(sim: CitySim) -> void:
	agents.clear()
	_landers_waiting.clear()
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
	var pads := plan.built_of("landing_pad")
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
		var list := plan.built_of(kind)
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
	if _count("rover") < 2:
		_spawn("rover", "ltv", _hub() + Vector3(_count("rover") * 6.0, 0, 0), 7.0)
	if _count("cruiser") < 1:
		_spawn("cruiser", "pressurized_rover", _hub() + Vector3(-8, 0, 0), 4.5)
	if _count("hauler") < 1:
		_spawn("hauler", "cargo_hauler", _road_point(_pad_spot()), 5.0, {"state": "parked"})
	if _count("hopper") < 1:
		var home: Vector3 = plan.layout.gates.get("life", _hub()) + Vector3(-6, 6, 0)
		_spawn("hopper", "hopper", home, 0.0, {"state": "parked", "wait": 12.0})
	var digs_at := plan.built_of("excavator")
	var digs := mini(digs_at.size(), 2)
	while _count("digger") < digs:
		var site: Vector3 = digs_at[_count("digger")]
		_spawn("digger", "excavator_robot", site + Vector3(-7, -3, 0), 1.6, {"site": site})
	while _count("digger") > digs:
		_remove_one("digger")
	var working := clampi(sim.robots - sim.robots_broken, 0, MAX_ROBOTS)
	var bay := _robot_home(sim)
	while _count("robot") < working:
		var k := _count("robot")
		_spawn("robot", "builder_robot", bay + Vector3((k % 4) * 3.0 - 4.5, 7.0 + floorf(k / 4.0) * 3.0, 0), 3.5,
			{"index": k, "state": "home"})
	while _count("robot") > working:
		_remove_one("robot")
	while _count("walker") < WALKERS:
		_spawn("walker", "astronaut", _random_core_spot(), 1.4)


func _remove_one(role: String) -> void:
	for i in range(agents.size() - 1, -1, -1):
		if agents[i]["role"] == role:
			agents.remove_at(i)
			return


func _robot_home(_sim: CitySim) -> Vector3:
	return _place_of(["robot_bay"], "industry")


func _random_core_spot() -> Vector3:
	## 거주 모듈 하나의 옆 (사람이 걸어 다니는 곳)
	var habs := plan.built_of("hab_module")
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
			var towers := plan.built_of("solar_tower")
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
