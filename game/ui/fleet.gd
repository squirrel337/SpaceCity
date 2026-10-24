class_name Fleet
extends RefCounted
## 함대 — 행성간 항로를 오가는 배 (Colonies.fleet, 자료 system_map.json). 시뮬레이션 밖의 규칙이다.
## 배마다 등급(화학·핵열·전기 추진)·항로(고향과 잇는 천체)·머무는 부두(천체의 저궤도 — 가는 중이면 "")가 있다.
## 행성간 수송선 노선(Transport — 발사 창마다)은 떠나는 부두에 그 항로의 배가 있어야 떠난다:
##   실을 것(받는 도시에 모자란 비축·정착민)이 있으면 싣고 떠나고, 없으면 쉰다. 저쪽 부두에 이 항로의 배가 하나도 없으면
##   (그리로 가는 배도 없으면) 이쪽에 배가 둘 이상일 때 빈 배로 건너가 양쪽에 배를 둔다. 배가 하나뿐인 항로는 고향 부두로 돌아온다.
##   떠날 때 보내는 도시가 추진제 값을 지원 점수로 낸다 — 추진제(t) = (빈 배 + 화물 + 정착민 × 0.5 t) × (e^(Δv/(Isp·g0)) − 1) × 1.1.
##   Δv는 항로 지도의 저궤도 ↔ 저궤도 (표면 ↔ 궤도는 착륙선이 맡는다). 1 t 값은 그 천체에서 사 온 값이고, 극저온 추진제 생산을 알고
##   만드는 계열(메탄·산소: 사바티에·전해조, 수소: 전해조)이 있으면 현지 값이다. 값이 모자라면 그 창은 놓친다.
##   전기 추진은 전이가 1.5배 걸리고 자리가 적다.
## 배는 지구 조선소에 주문한다 — 고향이 낸다 (궤도 조립을 알면 L1 조립장에서 지원 점수 절반에 금속으로). 핵열은 메가와트급 원자로가 있어야.
## 함대 자동 운영(처음엔 켜짐)은 항로마다 배를 둘로 맞춘다 — 고향 부두에 노는 배를 먼저 보내고, 없으면 그 항로에 가장 싼 등급을 주문한다.
## 상태 Colonies.fleet: {ships: [{id, name, cls, route, at, to, trips, since}], orders: [{id, name, cls, route, ready}], serial, auto,
##   status: {항로: [시, 글]} (지난 발사 창에 무슨 일이 있었나), log: [[시, 글]]} — 저장된다

const PATH := "res://data/system_map.json"
const LOG_KEEP := 40

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func cls(id: String) -> Dictionary:
	return data().get("classes", {}).get(id, {})


static func cls_name(id: String) -> String:
	return String(cls(id).get("name", id))


static func cls_short(id: String) -> String:
	return String(cls(id).get("short", id))


static func state(col: Colonies) -> Dictionary:
	if not col.fleet.get("ships") is Array:
		col.fleet = {"ships": [], "orders": [], "serial": 0, "auto": true, "status": {}, "log": []}
	return col.fleet


# ── 항로 지도 ───────────────────────────────────────────────────
static func node(id: String) -> Dictionary:
	for n in data().get("nodes", []):
		if String(n["id"]) == id:
			return n
	return {}


## 천체 → 함선이 머무는 궤도 노드
static func dock(body: String) -> String:
	return String(data().get("dock", {}).get(body, ""))


static func surface(body: String) -> String:
	return String(data().get("surface", {}).get(body, ""))


## 그 천체의 부두 이름 ("화성 저궤도")
static func dock_name(body: String) -> String:
	return String(node(dock(body)).get("name", body))


## 그 천체의 이름 ("화성") — 부두 이름에서
static func body_name(body: String) -> String:
	return dock_name(body).trim_suffix(" 저궤도")


## a에서 b로 가는 구간의 Δv (구간이 없으면 −1)
static func edge_dv(a: String, b: String) -> float:
	for e in data().get("edges", []):
		if String(e["a"]) == a and String(e["b"]) == b:
			return float(e["dv"])
		if String(e["b"]) == a and String(e["a"]) == b:
			return float(e.get("back", e["dv"]))
	return -1.0


## 두 노드 사이 Δv가 가장 작은 길: {dv, path: [노드 id]} (길이 없으면 dv = −1). 노드 스무 개 — 단순한 다익스트라
static func path(from: String, to: String) -> Dictionary:
	var dist := {from: 0.0}
	var prev := {}
	var open: Array = [from]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var u := String(open[bi])
		open.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		if u == to:
			break
		for e in data().get("edges", []):
			var v := ""
			var w := 0.0
			if String(e["a"]) == u:
				v = String(e["b"])
				w = float(e["dv"])
			elif String(e["b"]) == u:
				v = String(e["a"])
				w = float(e.get("back", e["dv"]))
			else:
				continue
			var nd := float(dist[u]) + w
			if not dist.has(v) or nd < float(dist[v]) - 1e-9:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	if not dist.has(to):
		return {"dv": -1.0, "path": []}
	var p: Array = [to]
	while String(p[0]) != from:
		p.push_front(prev[p[0]])
	return {"dv": float(dist[to]), "path": p}


## 저궤도 ↔ 저궤도 Δv (km/s, from 천체 → to 천체)
static func route_dv(from_body: String, to_body: String) -> float:
	return float(path(dock(from_body), dock(to_body))["dv"])


## 추진제 (t): 질량 mass_t를 Δv(km/s)만큼, 비추력 isp(s) — 구조 계수까지
static func prop_t(isp: float, dv: float, mass_t: float) -> float:
	var g0 := float(data().get("g0", 9.80665))
	return maxf(0.0, mass_t) * (exp(dv * 1000.0 / (isp * g0)) - 1.0) * float(data().get("structure", 1.1))


## 그 천체(그 도시)에서 그 등급의 추진제 1 t 값 (지원 점수): [값, 현지 생산인가]. sim이 없으면 사 온 값
static func price(col: Colonies, c_id: String, body: String, sim: CitySim = null, known: Dictionary = {}) -> Array:
	var p: Dictionary = data().get("prices", {}).get(c_id, {})
	var imp := float(p.get("import", {}).get(body, 10.0))
	if sim != null and p.has("local"):
		if known.is_empty():
			known = col.known_techs()
		var ok := known.has(String(data().get("local_tech", "")))
		for f in p.get("local_needs", []):
			if not sim.active.has(String(f)) or sim.fam_n(String(f)) <= 0:
				ok = false
		if ok:
			return [minf(imp, float(p["local"])), true]
	return [imp, false]


## 한 번 건너는 값: {dv, mass, prop_t, price, local, cost}
static func trip(col: Colonies, c_id: String, from_body: String, to_body: String, load_t: float, settlers: int,
		sim: CitySim = null, known: Dictionary = {}) -> Dictionary:
	var c := cls(c_id)
	var dv := route_dv(from_body, to_body)
	var mass := float(c.get("dry_t", 50.0)) + load_t + float(settlers) * float(data().get("person_t", 0.5))
	var pt := prop_t(float(c.get("isp", 360.0)), dv, mass)
	var pr := price(col, c_id, from_body, sim, known)
	return {"dv": dv, "mass": mass, "prop_t": pt, "price": float(pr[0]), "local": bool(pr[1]), "cost": pt * float(pr[0])}


## 그 항로의 전이 일수 (그 등급으로)
static func route_days(route: String, c_id: String) -> float:
	return Transport._transfer_days(route) * float(cls(c_id).get("time_k", 1.0))


static func requires_ok(c_id: String, known: Dictionary) -> bool:
	for t in cls(c_id).get("requires", []):
		if not known.has(String(t)):
			return false
	return true


static func tech_name(t: String) -> String:
	return String(GameData.TECHS[t]["name"]) if GameData.TECHS.has(t) else t


# ── 항로·배 찾기 ────────────────────────────────────────────────
## 수송선 노선의 항로 (고향이 아닌 쪽 천체)
static func route_of(l: Dictionary) -> String:
	return Transport.node_body(String(l["b"]))


## 행성간 항로들 (수송선 노선이 있는 천체, 천체 순서)
static func routes(col: Colonies) -> Array:
	var have := {}
	for l in col.transport.lines:
		if String(l["role"]) == "ship":
			have[route_of(l)] = true
	var out: Array = []
	for b in Colonies.BODY_ORDER:
		if have.has(b):
			out.append(b)
	return out


static func line_of(col: Colonies, route: String) -> Dictionary:
	for l in col.transport.lines:
		if String(l["role"]) == "ship" and route_of(l) == route:
			return l
	return {}


## 고향 부두의 천체 (수송선 노선의 a쪽 — 보통 달)
static func port_body(col: Colonies) -> String:
	for l in col.transport.lines:
		if String(l["role"]) == "ship":
			return Transport.node_body(String(l["a"]))
	var h := col.index_of_site(GameData.HOME_SITE)
	return String(col.list[h]["body"]) if h >= 0 else "moon"


## 주문 값을 내는 도시 (고향)
static func port_sim(col: Colonies) -> CitySim:
	var h := col.index_of_site(GameData.HOME_SITE)
	if h < 0:
		for l in col.transport.lines:
			if String(l["role"]) == "ship":
				h = col.index_of_site(String(l["a"]))
				break
	return col.list[h]["sim"] if h >= 0 else null


## 그 항로 저쪽 끝의 도시 (노선의 b)
static func hub_sim(col: Colonies, route: String) -> CitySim:
	var l := line_of(col, route)
	if l.is_empty():
		return null
	var i := col.index_of_site(String(l["b"]))
	return col.list[i]["sim"] if i >= 0 else null


static func ship(col: Colonies, id: int) -> Dictionary:
	for sh in state(col)["ships"]:
		if int(sh["id"]) == id:
			return sh
	return {}


static func ships_of(col: Colonies, route: String) -> Array:
	return (state(col)["ships"] as Array).filter(func(sh): return String(sh["route"]) == route)


## 그 천체 부두에 머무는 그 항로의 배 (번호 순)
static func docked(col: Colonies, route: String, body: String) -> Array:
	return (state(col)["ships"] as Array).filter(func(sh): return String(sh["route"]) == route and String(sh["at"]) == body)


## 그 배가 탄 편 ({} = 부두에 있다)
static func trip_of(col: Colonies, id: int) -> Dictionary:
	for t in col.transport.trips:
		if t.has("ship") and int(t["ship"]) == id:
			return t
	return {}


## 그 천체 부두에 이 항로의 배가 없고 그리로 가는 배도 없나
static func needs_ship(col: Colonies, route: String, body: String) -> bool:
	for sh in state(col)["ships"]:
		if String(sh["route"]) == route and (String(sh["at"]) == body or String(sh.get("to", "")) == body):
			return false
	return true


static func _name(n: int) -> String:
	var names: Array = data().get("names", [])
	if names.is_empty():
		return "%d호" % n
	var base := String(names[(n - 1) % names.size()])
	@warning_ignore("integer_division")
	var round_n := (n - 1) / names.size()
	return base if round_n == 0 else "%s %d호" % [base, round_n + 1]


static func _add_ship(col: Colonies, c_id: String, route: String, at: String) -> Dictionary:
	var st := state(col)
	st["serial"] = int(st["serial"]) + 1
	var sh := {"id": int(st["serial"]), "name": _name(int(st["serial"])), "cls": c_id, "route": route, "at": at, "to": "",
		"trips": 0, "since": col.hour}
	(st["ships"] as Array).append(sh)
	return sh


static func _log(col: Colonies, text: String) -> void:
	var lg: Array = state(col)["log"]
	lg.append([col.hour, text])
	if lg.size() > LOG_KEEP:
		lg.remove_at(0)


static func set_status(col: Colonies, route: String, text: String) -> void:
	(state(col)["status"] as Dictionary)[route] = [col.hour, text]


# ── 새 게임 · 저장 ──────────────────────────────────────────────
## 새 게임 (함대가 없던 저장도): 항로마다 시작 등급의 배 둘 — 고향 부두에 하나, 저쪽 부두에 하나 (지구 우주청이 빌려준 배)
static func start(col: Colonies) -> void:
	col.fleet = {}
	state(col)
	var pb := port_body(col)
	for r in routes(col):
		var c_id := String(data().get("start", {}).get(r, "chem"))
		_add_ship(col, c_id, r, pb)
		_add_ship(col, c_id, r, r)


static func load_state(col: Colonies, d: Variant) -> void:
	if not (d is Dictionary and (d as Dictionary).get("ships") is Array):
		start(col)
		return
	var src: Dictionary = d
	var st := {"ships": [], "orders": [], "serial": int(src.get("serial", 0)), "auto": bool(src.get("auto", true)),
		"status": {}, "log": []}
	for s in src["ships"]:
		if s is Dictionary and cls(String(s.get("cls", ""))).size() > 0:
			st["ships"].append({"id": int(s.get("id", 0)), "name": String(s.get("name", "")), "cls": String(s["cls"]),
				"route": String(s.get("route", "")), "at": String(s.get("at", "")), "to": String(s.get("to", "")),
				"trips": int(s.get("trips", 0)), "since": int(s.get("since", 0))})
			st["serial"] = maxi(int(st["serial"]), int(s.get("id", 0)))
	for o in src.get("orders", []) if src.get("orders") is Array else []:
		if o is Dictionary and cls(String(o.get("cls", ""))).size() > 0:
			st["orders"].append({"id": int(o.get("id", 0)), "name": String(o.get("name", "")), "cls": String(o["cls"]),
				"route": String(o.get("route", "")), "ready": int(o.get("ready", 0))})
			st["serial"] = maxi(int(st["serial"]), int(o.get("id", 0)))
	if src.get("status") is Dictionary:
		for k in src["status"]:
			var v: Variant = src["status"][k]
			if v is Array and (v as Array).size() >= 2:
				st["status"][String(k)] = [int(v[0]), String(v[1])]
	if src.get("log") is Array:
		for e in src["log"]:
			if e is Array and (e as Array).size() >= 2:
				st["log"].append([int(e[0]), String(e[1])])
	col.fleet = st
	# 가는 중이라 적혀 있는데 탄 편이 없으면 (옛 저장·지운 편) 가던 곳의 부두에 둔다
	for sh in st["ships"]:
		if String(sh["at"]) == "" and trip_of(col, int(sh["id"])).is_empty():
			sh["at"] = String(sh["to"]) if String(sh["to"]) != "" else port_body(col)
			sh["to"] = ""


# ── 떠나고 닿기 (Transport) ─────────────────────────────────────
## 수송선 노선이 떠날 차례 (발사 창): 떠나는 부두의 이 항로 배 가운데 하나를 고르고 실을 것을 정한다.
## 떠나면 {ship, cargo, people, cost, prop_t, local, time_k}, 아니면 {why} (실을 것이 없어 쉰 것은 why = "")
static func launch(col: Colonies, l: Dictionary, dir: int, s_sim: CitySim, d_sim: CitySim, inc: Dictionary) -> Dictionary:
	var tr := col.transport
	var route := route_of(l)
	var from_b := Transport.node_body(String(l["a"] if dir == 0 else l["b"]))
	var to_b := Transport.node_body(String(l["b"] if dir == 0 else l["a"]))
	var md := Transport.mode(String(l["mode"]))
	var here := docked(col, route, from_b)
	if here.is_empty():
		var cargo0 := tr._plan_cargo(s_sim, d_sim, float(md.get("cap_t", 300.0)), 0.0, inc)
		var n0 := tr._plan_people(s_sim, d_sim, int(md.get("seats", 0)), int(inc.get("people", 0)))
		if Transport.cargo_t(cargo0) >= 0.05 or n0 > 0:
			return {"why": "이 부두에 %s 항로의 배가 없어 이번 창을 놓쳤다" % body_name(route)}
		return {"why": ""}
	# 빈 배로 건너가기: 저쪽에 배가 없고 이쪽에 둘 이상일 때, 또는 배가 하나뿐인 항로가 고향으로 돌아올 때
	var move_empty := (needs_ship(col, route, to_b) and here.size() >= 2) \
		or (ships_of(col, route).size() == 1 and from_b != port_body(col))
	var known := col.known_techs()
	var best := {}
	var why := ""
	for sh in here:
		var c := cls(String(sh["cls"]))
		var cap := minf(float(md.get("cap_t", 300.0)), float(c.get("cap_t", 300.0)))
		var cargo := tr._plan_cargo(s_sim, d_sim, cap, 0.0, inc)
		var n := tr._plan_people(s_sim, d_sim, int(c.get("seats", 0)), int(inc.get("people", 0)))
		var load_t := Transport.cargo_t(cargo)
		var empty := load_t < 0.05 and n <= 0
		if empty and not move_empty:
			continue
		var tp := trip(col, String(sh["cls"]), from_b, to_b, load_t, n, s_sim, known)
		if float(tp["cost"]) > s_sim.support:
			why = "추진제 %s t 값(지원 %d)이 모자라 이번 창을 놓쳤다" % [Fmt.n(float(tp["prop_t"]), 1), int(ceil(float(tp["cost"])))]
			continue
		if best.is_empty() or n > int(best["people"]) or (n == int(best["people"]) and float(tp["cost"]) < float(best["cost"])):
			best = {"ship": sh, "cargo": cargo, "people": n, "cost": float(tp["cost"]), "prop_t": float(tp["prop_t"]),
				"local": bool(tp["local"]), "time_k": float(c.get("time_k", 1.0))}
	if best.is_empty():
		return {"why": why}
	return best


static func depart(sh: Dictionary, to_body: String) -> void:
	sh["at"] = ""
	sh["to"] = to_body
	sh["trips"] = int(sh.get("trips", 0)) + 1


## 수송선이 닿았다 (Transport._arrive): 그 배를 닿은 도시가 있는 천체의 부두에 둔다
static func arrive(col: Colonies, t: Dictionary, at_site: String) -> void:
	if not t.has("ship"):
		return
	var sh := ship(col, int(t["ship"]))
	if sh.is_empty():
		return
	sh["at"] = Transport.node_body(at_site)
	sh["to"] = ""


# ── 주문 · 배정 · 퇴역 ──────────────────────────────────────────
## 주문 값: {support, parts, metal_t, days, yard} — 궤도 조립을 알면 L1 조립장 (지원 절반, 금속 더, 날 70%)
static func order_cost(col: Colonies, c_id: String, known: Dictionary = {}) -> Dictionary:
	var o: Dictionary = cls(c_id).get("order", {})
	var out := {"support": float(o.get("support", 0)), "parts": float(o.get("parts", 0)), "metal_t": float(o.get("metal_t", 0)),
		"days": float(o.get("days", 60)), "yard": "지구 조선소"}
	if known.is_empty():
		known = col.known_techs()
	var asm: Dictionary = data().get("assembly", {})
	var ok := not asm.is_empty()
	for t in asm.get("requires", []):
		if not known.has(String(t)):
			ok = false
	if ok:
		out["support"] = float(out["support"]) * float(asm.get("support_k", 0.5))
		out["metal_t"] = float(out["metal_t"]) + float(asm.get("metal_t", 30))
		out["days"] = ceil(float(out["days"]) * float(asm.get("days_k", 0.7)))
		out["yard"] = "L1 조립장"
	return out


static func cost_text(cost: Dictionary) -> String:
	var bits := PackedStringArray(["지원 %s" % Fmt.n(float(cost["support"]))])
	if float(cost["parts"]) > 0.0:
		bits.append("부품 %s" % Fmt.n(float(cost["parts"])))
	if float(cost["metal_t"]) > 0.0:
		bits.append("금속 %s t" % Fmt.n(float(cost["metal_t"])))
	return "%s · %d일 (%s)" % [" · ".join(bits), int(cost["days"]), String(cost["yard"])]


## 주문할 수 없으면 까닭 (route ""는 노는 배로)
static func order_reason(col: Colonies, c_id: String, route: String) -> String:
	var c := cls(c_id)
	if c.is_empty():
		return "그런 등급이 없다"
	var known := col.known_techs()
	for t in c.get("requires", []):
		if not known.has(String(t)):
			return "%s 기술이 있어야 한다" % tech_name(String(t))
	if route != "" and not routes(col).has(route):
		return "그 항로가 없다"
	var ps := port_sim(col)
	if ps == null:
		return "고향이 없다"
	var cost := order_cost(col, c_id, known)
	if ps.support < float(cost["support"]):
		return "고향의 지원 점수가 모자란다 (%s 필요)" % Fmt.n(float(cost["support"]))
	if float(ps.stock.get("parts", 0.0)) < float(cost["parts"]):
		return "고향의 부품이 모자란다 (%s 필요)" % Fmt.n(float(cost["parts"]))
	if float(ps.stock.get("metal_t", 0.0)) < float(cost["metal_t"]):
		return "고향의 금속이 모자란다 (%s t 필요)" % Fmt.n(float(cost["metal_t"]))
	return ""


static func order(col: Colonies, c_id: String, route: String, auto := false) -> String:
	var why := order_reason(col, c_id, route)
	if why != "":
		return why
	var st := state(col)
	var ps := port_sim(col)
	var cost := order_cost(col, c_id)
	ps.support -= float(cost["support"])
	ps.stock["parts"] = float(ps.stock.get("parts", 0.0)) - float(cost["parts"])
	ps.stock["metal_t"] = float(ps.stock.get("metal_t", 0.0)) - float(cost["metal_t"])
	st["serial"] = int(st["serial"]) + 1
	var o := {"id": int(st["serial"]), "name": _name(int(st["serial"])), "cls": c_id, "route": route,
		"ready": col.hour + int(float(cost["days"]) * 24.0)}
	(st["orders"] as Array).append(o)
	var where := ("%s 항로" % body_name(route)) if route != "" else "고향 부두"
	_log(col, "%s%s(%s)를 주문했다 — %s, %s 완성" % ["자동 운영: " if auto else "", String(o["name"]), cls_name(c_id), where,
		col.date_text(float(o["ready"]))])
	ps.note("함대 — %s(%s) 주문, %s에서 %s 완성 (%s)" % [String(o["name"]), cls_name(c_id), String(cost["yard"]),
		col.date_text(float(o["ready"])), where], "info")
	return ""


## 고향 부두의 배를 다른 항로로 (route ""는 놀게 둔다)
static func assign(col: Colonies, id: int, route: String) -> String:
	var sh := ship(col, id)
	if sh.is_empty():
		return "그런 배가 없다"
	if String(sh["at"]) != port_body(col):
		return "고향 부두에 있을 때만 항로를 바꾼다"
	if route != "" and not routes(col).has(route):
		return "그 항로가 없다"
	sh["route"] = route
	_log(col, "%s(%s)를 %s" % [String(sh["name"]), cls_short(String(sh["cls"])),
		("%s 항로에 보냈다" % body_name(route)) if route != "" else "고향 부두에 쉬게 했다"])
	return ""


## 퇴역: 고향 부두의 배를 해체한다 (주문 부품의 30%를 돌려받는다)
static func retire(col: Colonies, id: int) -> String:
	var sh := ship(col, id)
	if sh.is_empty():
		return "그런 배가 없다"
	if String(sh["at"]) != port_body(col):
		return "고향 부두에 있을 때만 퇴역시킨다"
	var back := floorf(float(cls(String(sh["cls"])).get("order", {}).get("parts", 0)) * 0.3)
	var ps := port_sim(col)
	if ps != null:
		ps.stock["parts"] = float(ps.stock.get("parts", 0.0)) + back
	(state(col)["ships"] as Array).erase(sh)
	_log(col, "%s(%s)를 퇴역시켰다 — 부품 %s 회수" % [String(sh["name"]), cls_short(String(sh["cls"])), Fmt.n(back)])
	return ""


# ── 하루 ────────────────────────────────────────────────────────
## 하루에 한 번 (Colonies.step): 다 지은 배를 고향 부두에, 항로가 없어진 배는 쉬게, 함대 자동 운영
static func step_day(col: Colonies) -> void:
	var st := state(col)
	var pb := port_body(col)
	for o in (st["orders"] as Array).duplicate():
		if col.hour >= int(o["ready"]):
			(st["orders"] as Array).erase(o)
			(st["ships"] as Array).append({"id": int(o["id"]), "name": String(o["name"]), "cls": String(o["cls"]),
				"route": String(o["route"]) if routes(col).has(String(o["route"])) else "", "at": pb, "to": "", "trips": 0,
				"since": col.hour})
			_log(col, "%s(%s)가 나왔다 — 고향 부두" % [String(o["name"]), cls_name(String(o["cls"]))])
			var ps := port_sim(col)
			if ps != null:
				ps.note("함대 — 새 배 %s(%s)가 고향 부두에 들어왔다%s" % [String(o["name"]), cls_name(String(o["cls"])),
					(" · %s 항로" % body_name(String(o["route"]))) if String(o["route"]) != "" else ""], "good")
	var rs := routes(col)
	for sh in st["ships"]:
		if String(sh["route"]) != "" and not rs.has(String(sh["route"])) and String(sh["at"]) == pb:
			sh["route"] = ""
	if bool(st.get("auto", true)):
		_auto(col)


## 그 항로에 알맞은 차례의 등급들: 만들 수 있는 것 가운데 화물 typical_t로 한 번 오가는 추진제 값 + 늘어난 전이 날마다 slow_per_day가
## 작은 것부터 (전기 추진은 싸지만 느리다 — 먼 항로일수록 손해)
static func ranked_classes(col: Colonies, route: String, known: Dictionary = {}) -> Array:
	if known.is_empty():
		known = col.known_techs()
	var a: Dictionary = data().get("auto", {})
	var pb := port_body(col)
	var ps := port_sim(col)
	var hub := hub_sim(col, route)
	var typ := float(a.get("typical_t", 10))
	var scored: Array = []
	for c_id in data().get("classes", {}):
		if not requires_ok(String(c_id), known):
			continue
		var v := float(trip(col, String(c_id), pb, route, typ, 0, ps, known)["cost"]) \
			+ float(trip(col, String(c_id), route, pb, typ, 0, hub, known)["cost"]) \
			+ (float(cls(String(c_id)).get("time_k", 1.0)) - 1.0) * Transport._transfer_days(route) * float(a.get("slow_per_day", 1.5))
		scored.append([v, String(c_id)])
	scored.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	return scored.map(func(x): return String(x[1]))


static func best_class(col: Colonies, route: String, known: Dictionary = {}) -> String:
	var r := ranked_classes(col, route, known)
	return String(r[0]) if not r.is_empty() else ""


static func _auto(col: Colonies) -> void:
	var st := state(col)
	var a: Dictionary = data().get("auto", {})
	var target := int(a.get("target", 2))
	var pb := port_body(col)
	var ps := port_sim(col)
	var known := col.known_techs()
	for r in routes(col):
		var have := ships_of(col, r).size()
		for o in st["orders"]:
			if String(o["route"]) == r:
				have += 1
		var guard := 0
		while have < target and guard < 4:
			guard += 1
			var best_c := best_class(col, r, known)
			var spare := {}
			for sh in st["ships"]:
				if String(sh["route"]) == "" and String(sh["at"]) == pb and (spare.is_empty() or String(sh["cls"]) == best_c):
					spare = sh
			if not spare.is_empty():
				spare["route"] = r
				_log(col, "자동 운영: %s(%s)를 %s 항로에 보냈다" % [String(spare["name"]), cls_short(String(spare["cls"])), body_name(r)])
				have += 1
				continue
			if ps == null:
				break
			# 알맞은 차례로 주문할 수 있는 등급 (핵열에 금속이 모자라면 그다음)
			var ordered := false
			for c_id in ranked_classes(col, r, known):
				if order_reason(col, c_id, r) != "" \
						or ps.support < float(order_cost(col, c_id, known)["support"]) + float(a.get("reserve", 400)):
					continue
				ordered = order(col, c_id, r, true) == ""
				if ordered:
					break
			if not ordered:
				break
			have += 1


# ── 글 ──────────────────────────────────────────────────────────
## "화성 부두" / "고향 부두" / "화성행 · 2063.05.01 도착"
static func place_text(col: Colonies, sh: Dictionary) -> String:
	var at := String(sh["at"])
	if at != "":
		return "고향 부두" if at == port_body(col) else "%s 부두" % body_name(at)
	var t := trip_of(col, int(sh["id"]))
	if t.is_empty():
		return "가는 중"
	return "%s행 · %s 도착" % [body_name(String(sh.get("to", ""))), col.date_text(float(t["arrive"]))]


static func ship_text(col: Colonies, sh: Dictionary) -> String:
	return "%s · %s · %s · %d번 건넘" % [String(sh["name"]), cls_name(String(sh["cls"])), place_text(col, sh), int(sh.get("trips", 0))]
