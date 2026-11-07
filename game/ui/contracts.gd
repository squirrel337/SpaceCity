class_name Contracts
extends RefCounted
## 항로 계약과 지구 협상 (자료 system_contracts.json). 시뮬레이션 밖의 규칙이다.
## 항로 계약: 30~50일마다 제안이 들어온다 (열린 제안은 셋까지, 45일 남는다) — "지구 우주청: 고향 → 화성 · 물 40 t, 발사 창 2번 안에".
##   고향 → 그 천체의 도시(6할) 또는 그 천체의 도시 → 고향 — 보내는 쪽에 남는 물건이 있는 방향이 네 배 잘 나온다. 물건은 보내는 도시에
##   남는 몫이 있는 것이 여섯 배 잘 나오고, 그때 양은 그 몫의 8할을 넘지 않는다. 받으면 그 방향의 행성간 수송선이 떠날 때 이미 실은 그
##   물건을 계약에 셈하고, 모자라면 보내는 도시의 남는 몫(정착민 몫의 1.5배 — 부품·금속은 2배 — 를 남긴 나머지)에서 더 싣는다. 마감(그 창에
##   떠나 가장 느린 배로 닿는 날 + 30일)까지 다 닿으면 보내는 도시가 보수(양 × 값 × (1 + Δv × 0.25) × 평판 배율 0.8~1.3)를 받고 평판 +4,
##   못 마치면 보수의 4할을 물고 신뢰 −2 · 평판 −6. 받는 도시의 저장 한도가 찬 물건은 나오지 않는다. 함대 자동 운영은 보내는 도시에
##   남는 몫이 계약 양을 넘고 받는 도시에 자리가 있고 보내는 부두에 그 항로의 배가 머물러 있고 마감이 1,000일 안이면 둘까지 받는다.
## 지구 협상: 100~160일마다 지구의 누군가가 거래를 내민다 (결정 카드 — 자동 운영이면 시드가 고른다). 예산 증액(조건: 1년에 계약 2건),
##   민간 투자(지금 돈 ↔ 2년 동안 계약 보수의 25%), 공동 연구, 물 독점권, 자치 요구. 기간이 있는 효과는 고향 보정의 deals 몫으로.
## 상태 Colonies.contracts: {rep, next, serial, offers: [제안], active: [계약], done, failed, earned, log: [[시, 글]],
##   deal_next, pending: {} (기다리는 협상), deals: [{id, title, until, support_day, rp_day, cut, cut_good, need, base, fail}], seen} — 저장된다
##   제안·계약: {id, client, route, from, to(천체), good, amount(보이는 단위), reward, penalty, deadline·expires(시), delivered, sent}

const PATH := "res://data/system_contracts.json"
const LOG_KEEP := 30

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {}
	return D


static func state(col: Colonies) -> Dictionary:
	if not col.contracts.get("offers") is Array:
		start(col)
	return col.contracts


## 새 게임 (계약이 없던 저장도): 첫 제안은 20일째, 첫 협상은 90일째
static func start(col: Colonies) -> void:
	col.contracts = {"rep": float(data().get("rep", {}).get("start", 50)), "next": col.hour / 24 + 20, "serial": 0, "offers": [],
		"active": [], "done": 0, "failed": 0, "earned": 0.0, "log": [], "deal_next": col.hour / 24 + 90, "pending": {}, "deals": [],
		"seen": {}}


static func load_state(col: Colonies, d: Variant) -> void:
	start(col)
	if not (d is Dictionary and (d as Dictionary).get("offers") is Array):
		return
	var src: Dictionary = d
	var st := col.contracts
	st["rep"] = clampf(float(src.get("rep", st["rep"])), 0.0, 100.0)
	for k in ["next", "serial", "done", "failed", "deal_next"]:
		st[k] = int(src.get(k, st[k]))
	st["earned"] = float(src.get("earned", 0.0))
	for key in ["offers", "active"]:
		for c in src[key] if src.get(key) is Array else []:
			if c is Dictionary and not good(String(c.get("good", ""))).is_empty():
				st[key].append(_clean(c))
	for e in src.get("log", []) if src.get("log") is Array else []:
		if e is Array and (e as Array).size() >= 2:
			st["log"].append([int(e[0]), String(e[1])])
	if src.get("pending") is Dictionary and (src["pending"] as Dictionary).get("choices") is Array:
		st["pending"] = src["pending"]
	for dl in src.get("deals", []) if src.get("deals") is Array else []:
		if dl is Dictionary:
			st["deals"].append({"id": String(dl.get("id", "")), "title": String(dl.get("title", "")), "until": int(dl.get("until", 0)),
				"support_day": float(dl.get("support_day", 0.0)), "rp_day": float(dl.get("rp_day", 0.0)), "cut": float(dl.get("cut", 0.0)),
				"cut_good": String(dl.get("cut_good", "")), "need": int(dl.get("need", 0)), "base": int(dl.get("base", 0)),
				"fail": dl.get("fail", {}) if dl.get("fail") is Dictionary else {}})
	if src.get("seen") is Dictionary:
		for k in src["seen"]:
			st["seen"][String(k)] = int(src["seen"][k])
	_apply_deals(col)


static func _clean(c: Dictionary) -> Dictionary:
	return {"id": int(c.get("id", 0)), "client": String(c.get("client", "")), "route": String(c.get("route", "")),
		"from": String(c.get("from", "")), "to": String(c.get("to", "")), "good": String(c.get("good", "")),
		"amount": float(c.get("amount", 0.0)), "reward": float(c.get("reward", 0.0)), "penalty": float(c.get("penalty", 0.0)),
		"deadline": int(c.get("deadline", 0)), "expires": int(c.get("expires", 0)), "delivered": float(c.get("delivered", 0.0)),
		"sent": float(c.get("sent", 0.0)), "windows": int(c.get("windows", 1))}


static func good(key: String) -> Dictionary:
	for g in data().get("goods", []):
		if String(g["key"]) == key:
			return g
	return {}


## 보수 배율 (평판 0 → lo, 100 → hi)
static func rep_k(col: Colonies) -> float:
	var r: Dictionary = data().get("rep", {})
	return lerpf(float(r.get("lo", 0.8)), float(r.get("hi", 1.3)), clampf(float(state(col)["rep"]) / 100.0, 0.0, 1.0))


static func _log(col: Colonies, text: String) -> void:
	var lg: Array = state(col)["log"]
	lg.append([col.hour, text])
	while lg.size() > LOG_KEEP:
		lg.remove_at(0)


# ── 도시 · 물건 ─────────────────────────────────────────────────
## 그 천체 쪽 끝의 도시 (고향 부두의 천체면 고향, 아니면 그 항로 저쪽의 도시)
static func city_of(col: Colonies, ct: Dictionary, which: String) -> CitySim:
	var b := String(ct[which])
	if b == Fleet.port_body(col):
		return Fleet.port_sim(col)
	return Fleet.hub_sim(col, String(ct["route"]))


static func _cargo_spec(key: String) -> Dictionary:
	for c in Transport.data().get("cargo", []):
		if String(c["key"]) == key:
			return c
	return {}


## 보내는 도시가 내줄 수 있는 몫 (보이는 단위): 비축 − 정착민 몫 × keep_x (교통이 싣는 규칙과 같다), planned는 이미 실은 비축 단위
static func spare(sim: CitySim, key: String, planned := 0.0) -> float:
	if sim == null:
		return 0.0
	var c := _cargo_spec(key)
	var g := good(key)
	var give := float(sim.stock.get(key, 0.0)) - Transport._need(sim, c) * float(c.get("keep_x", 1.5)) - planned
	return maxf(0.0, give) / float(g.get("per_unit", 1.0))


static func unit_text(ct: Dictionary, units: float) -> String:
	var g := good(String(ct["good"]))
	return "%s %s %s" % [String(g.get("name", ct["good"])), Fmt.n(units, 1 if String(g.get("unit", "")) == "t" else 0), String(g.get("unit", ""))]


## "고향 → 화성" (천체 이름)
static func leg_text(col: Colonies, ct: Dictionary) -> String:
	var pb := Fleet.port_body(col)
	var a := "고향" if String(ct["from"]) == pb else Fleet.body_name(String(ct["from"]))
	var b := "고향" if String(ct["to"]) == pb else Fleet.body_name(String(ct["to"]))
	return "%s → %s" % [a, b]


# ── 제안 ────────────────────────────────────────────────────────
## 그 방향의 수송선이 windows번째 창에 떠나 가장 느린 배로 닿고 margin_days를 더한 때 (시). 노선이 없으면 −1
static func _deadline(col: Colonies, route: String, from_b: String, windows: int) -> int:
	var l := Fleet.line_of(col, route)
	if l.is_empty():
		return -1
	var dir := 0 if Transport.node_body(String(l["a"])) == from_b else 1
	var rw: Dictionary = data().get("reward", {})
	var dep := int(l["next"][dir])
	if dep <= col.hour:
		dep = col.transport._next_window_h(col, l, dir, col.hour)
	for _k in range(1, maxi(1, windows)):
		dep = col.transport._next_window_h(col, l, dir, dep + 24 * 30)
	return dep + int(float(l["trip_h"]) * float(rw.get("slow_k", 1.5))) + int(rw.get("margin_days", 30)) * 24


## 받는 도시의 저장 한도까지 남은 자리 (보이는 단위 — 한도가 없으면 아주 크다)
static func room(sim: CitySim, key: String) -> float:
	if sim == null:
		return 0.0
	if not sim.caps.has(key):
		return 1e9
	return maxf(0.0, float(sim.caps[key]) * 0.98 - float(sim.stock.get(key, 0.0))) / float(good(key).get("per_unit", 1.0))


## 그 방향으로 보낼 물건이 있나 (받는 쪽이 시장에서 채우지 않고 자리가 있는 물건 가운데 남는 몫이 가장 작은 양을 넘는 것)
static func _has_spare(col: Colonies, ct: Dictionary) -> bool:
	var src := city_of(col, ct, "from")
	var dst := city_of(col, ct, "to")
	if src == null or dst == null:
		return false
	for g in data().get("goods", []):
		var k := String(g["key"])
		if not dst.supply.has(k) and spare(src, k) >= float(g["lots"][0]) and room(dst, k) >= float(g["lots"][0]):
			return true
	return false


static func _make_offer(col: Colonies, rng: RandomNumberGenerator) -> Dictionary:
	var routes := Fleet.routes(col)
	if routes.is_empty():
		return {}
	var route := String(routes[rng.randi() % routes.size()])
	var od: Dictionary = data().get("offers", {})
	var pb := Fleet.port_body(col)
	# 방향: 고향 → 그 천체가 out_share — 보내는 쪽에 남는 물건이 있는 방향은 네 배
	var ct_out := {"route": route, "from": pb, "to": route}
	var ct_in := {"route": route, "from": route, "to": pb}
	var w_out := float(od.get("out_share", 0.6)) * (4.0 if _has_spare(col, ct_out) else 1.0)
	var w_in := (1.0 - float(od.get("out_share", 0.6))) * (4.0 if _has_spare(col, ct_in) else 1.0)
	var ct := ct_out if rng.randf() * (w_out + w_in) < w_out else ct_in
	var src := city_of(col, ct, "from")
	var dst := city_of(col, ct, "to")
	if src == null or dst == null:
		return {}
	# 물건: 보내는 도시에 남는 몫이 있는 것을 여섯 배로, 양은 그 몫의 8할을 넘지 않게 (남는 몫이 있으면) — 받는 도시에 자리가 없는 물건은 빼고
	var pool: Array = []
	var total := 0.0
	for g in data().get("goods", []):
		var w := 6.0 if spare(src, String(g["key"])) >= float(g["lots"][0]) else 1.0
		if dst.supply.has(String(g["key"])) or room(dst, String(g["key"])) < float(g["lots"][0]):
			continue                                  # 받는 쪽이 시장에서 채우거나 (지구) 저장 한도가 찼다
		pool.append([g, w])
		total += w
	if pool.is_empty():
		return {}
	var pick := rng.randf() * total
	var gd: Dictionary = pool[-1][0]
	for pr in pool:
		pick -= float(pr[1])
		if pick <= 0.0:
			gd = pr[0]
			break
	var stp := float(gd.get("step", 1))
	var amount := rng.randf_range(float(gd["lots"][0]), float(gd["lots"][1]))
	var have := spare(src, String(gd["key"]))
	if have >= float(gd["lots"][0]):
		amount = minf(amount, maxf(float(gd["lots"][0]), have * 0.8))
	amount = minf(amount, maxf(float(gd["lots"][0]), room(dst, String(gd["key"])) * 0.8))
	amount = maxf(stp, snappedf(amount, stp))
	var clients: Array = (data().get("clients", []) as Array).filter(func(c): return not c.has("routes") or route in c["routes"])
	var client: Dictionary = clients[rng.randi() % clients.size()] if not clients.is_empty() else {"name": "지구 우주청"}
	var rw: Dictionary = data().get("reward", {})
	var wins := rng.randi_range(int(rw.get("windows", [1, 2])[0]), int(rw.get("windows", [1, 2])[1]))
	var deadline := _deadline(col, route, String(ct["from"]), wins)
	if deadline < 0:
		return {}
	var dv := Fleet.route_dv(String(ct["from"]), String(ct["to"]))
	var reward := roundf(amount * float(gd["price"]) * (1.0 + maxf(0.0, dv) * float(rw.get("dv_k", 0.25))) * rep_k(col))
	var st := state(col)
	st["serial"] = int(st["serial"]) + 1
	ct.merge({"id": int(st["serial"]), "client": String(client["name"]), "good": String(gd["key"]), "amount": amount, "reward": reward,
		"penalty": roundf(reward * float(rw.get("penalty_k", 0.4))), "deadline": deadline,
		"expires": col.hour + int(od.get("valid_days", 45)) * 24, "delivered": 0.0, "sent": 0.0, "windows": wins})
	return ct


## 받을 수 없으면 까닭
static func accept_reason(col: Colonies, id: int) -> String:
	var st := state(col)
	var ct := _find(st["offers"], id)
	if ct.is_empty():
		return "그런 제안이 없다"
	if (st["active"] as Array).size() >= int(data().get("offers", {}).get("max_active", 4)):
		return "받은 계약이 이미 %d건이다" % (st["active"] as Array).size()
	if Fleet.line_of(col, String(ct["route"])).is_empty():
		return "그 항로의 수송선 노선이 없다"
	return ""


static func accept(col: Colonies, id: int, auto := false) -> String:
	var why := accept_reason(col, id)
	if why != "":
		return why
	var st := state(col)
	var ct := _find(st["offers"], id)
	(st["offers"] as Array).erase(ct)
	(st["active"] as Array).append(ct)
	var text := "%s항로 계약을 받았다 — %s: %s · %s, %s까지 (보수 지원 %s)" % ["자동 운영: " if auto else "", String(ct["client"]), leg_text(col, ct),
		unit_text(ct, float(ct["amount"])), col.date_text(float(ct["deadline"])), Fmt.n(float(ct["reward"]))]
	_log(col, text)
	var s := city_of(col, ct, "from")
	if s != null:
		s.note(text, "info")
	return ""


static func decline(col: Colonies, id: int) -> void:
	var st := state(col)
	var ct := _find(st["offers"], id)
	if not ct.is_empty():
		(st["offers"] as Array).erase(ct)
		_log(col, "제안을 사양했다 — %s: %s · %s" % [String(ct["client"]), leg_text(col, ct), unit_text(ct, float(ct["amount"]))])


static func _find(list: Array, id: int) -> Dictionary:
	for c in list:
		if int(c["id"]) == id:
			return c
	return {}


# ── 싣기 · 닿기 (Fleet.launch · Transport) ──────────────────────
## 그 방향으로 떠나는 수송선의 짐을 받은 계약에 셈한다 (cargo를 바꾸고 {계약 id: 보이는 단위}를 돌려준다).
## 이미 실은 그 물건(교통이 정한 짐 — 다른 계약에 셈하지 않은 몫)을 먼저 셈하고, 모자라면 보내는 도시의 남는 몫(이미 실은 몫을 뺀)에서
## 배의 남은 자리와 받는 도시의 저장 한도 안에서 더 싣는다
static func add_cargo(col: Colonies, from_b: String, to_b: String, s_sim: CitySim, d_sim: CitySim, inc: Dictionary, cargo: Dictionary,
		cap_t: float) -> Dictionary:
	var alloc := {}
	if col.contracts.is_empty():
		return alloc
	var used := {}                                     # 물건 → 이 짐에서 이미 계약에 셈한 몫 (보이는 단위)
	for ct in state(col)["active"]:
		if String(ct["from"]) != from_b or String(ct["to"]) != to_b:
			continue
		var g := good(String(ct["good"]))
		var k := String(ct["good"])
		var per := float(g.get("per_unit", 1.0))
		var t_unit := String(g.get("unit", "")) == "t"
		var left := float(ct["amount"]) - float(ct["delivered"]) - float(ct["sent"])
		if left <= 0.0:
			continue
		var aboard := maxf(0.0, float(cargo.get(k, 0.0)) / per - float(used.get(k, 0.0)))
		var extra := 0.0
		if aboard < left:
			var room := (cap_t - Transport.cargo_t(cargo)) / maxf(float(g.get("t_per_unit", 1.0)), 1e-6)
			extra = minf(minf(left - aboard, spare(s_sim, k, float(cargo.get(k, 0.0)))), room)
			if d_sim != null and d_sim.caps.has(k):
				var have := float(d_sim.stock.get(k, 0.0)) + float(inc.get(k, 0.0)) + float(cargo.get(k, 0.0))
				extra = minf(extra, maxf(0.0, float(d_sim.caps[k]) * 0.98 - have) / per)
			extra = maxf(0.0, floorf(extra * 10.0) / 10.0 if t_unit else floorf(extra))
			if extra > 0.0:
				cargo[k] = float(cargo.get(k, 0.0)) + extra * per
		var units := minf(left, aboard + extra)
		units = floorf(units * 10.0 + 1e-6) / 10.0 if t_unit else floorf(units + 1e-6)
		if units <= 0.0:
			continue
		used[k] = float(used.get(k, 0.0)) + units
		alloc[int(ct["id"])] = units
	return alloc


## 떠났다 — 실은 계약 몫을 "가는 중"으로
static func mark_sent(col: Colonies, alloc: Dictionary) -> void:
	for id in alloc:
		var ct := _find(state(col)["active"], int(id))
		if not ct.is_empty():
			ct["sent"] = float(ct["sent"]) + float(alloc[id])


## 닿았다 (Transport._arrive): 처음 가던 곳에 닿았으면 계약에 셈하고, 다 닿으면 마친다
static func on_arrive(col: Colonies, t: Dictionary, at_site: String) -> void:
	if not t.get("contract") is Dictionary or col.contracts.is_empty():
		return
	var ok := at_site == String(t["to"])
	for id in t["contract"]:
		var ct := _find(state(col)["active"], int(id))
		if ct.is_empty():
			continue
		var units := float(t["contract"][id])
		ct["sent"] = maxf(0.0, float(ct["sent"]) - units)
		if ok:
			ct["delivered"] = float(ct["delivered"]) + units
			if float(ct["delivered"]) >= float(ct["amount"]) - 0.05:
				_finish(col, ct, true)


## 마친다 (ok) 또는 마감이 지났다
static func _finish(col: Colonies, ct: Dictionary, ok: bool) -> void:
	var st := state(col)
	(st["active"] as Array).erase(ct)
	var rw: Dictionary = data().get("reward", {})
	var s := city_of(col, ct, "from")
	if ok:
		var keep := 1.0 - cut(col, String(ct["good"]))
		var pay := roundf(float(ct["reward"]) * keep)
		if s != null:
			s.support += pay
		st["rep"] = clampf(float(st["rep"]) + float(rw.get("rep_done", 4)), 0.0, 100.0)
		st["done"] = int(st["done"]) + 1
		st["earned"] = float(st["earned"]) + pay
		var text := "항로 계약 완료 — %s: %s · %s, 지원 +%s%s (평판 %d)" % [String(ct["client"]), leg_text(col, ct), unit_text(ct, float(ct["amount"])),
			Fmt.n(pay), (" — %s%%는 거래 상대에게" % int(round((1.0 - keep) * 100.0))) if keep < 0.999 else "", int(st["rep"])]
		_log(col, text)
		if s != null:
			s.note(text, "good")
	else:
		if s != null:
			s.support = maxf(0.0, s.support - float(ct["penalty"]))
			s.trust = clampf(s.trust + float(rw.get("trust_fail", -2)), 0.0, 100.0)
		st["rep"] = clampf(float(st["rep"]) + float(rw.get("rep_fail", -6)), 0.0, 100.0)
		st["failed"] = int(st["failed"]) + 1
		var text2 := "항로 계약 실패 — %s: %s · %s 가운데 %s만 닿았다, 위약금 지원 %s (평판 %d)" % [String(ct["client"]), leg_text(col, ct),
			unit_text(ct, float(ct["amount"])), unit_text(ct, float(ct["delivered"])), Fmt.n(float(ct["penalty"])), int(st["rep"])]
		_log(col, text2)
		if s != null:
			s.note(text2, "warn")


# ── 하루 (Colonies.step) ────────────────────────────────────────
static func step_day(col: Colonies) -> void:
	var st := state(col)
	var day := col.hour / 24
	st["offers"] = (st["offers"] as Array).filter(func(c): return int(c["expires"]) > col.hour)
	for ct in (st["active"] as Array).duplicate():
		if col.hour > int(ct["deadline"]):
			_finish(col, ct, false)
	var od: Dictionary = data().get("offers", {})
	if day >= int(st["next"]):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([col.seed_value, day, "contracts"])
		var ed: Array = od.get("every_days", [30, 50])
		st["next"] = day + rng.randi_range(int(ed[0]), int(ed[1]))
		while (st["offers"] as Array).size() < int(od.get("max_open", 3)):
			var o := _make_offer(col, rng)
			if o.is_empty():
				break
			(st["offers"] as Array).append(o)
	# 협상: 끝난 거래의 조건을 보고 보정을 다시, 날이 되면 새 거래
	var changed := false
	for dl in (st["deals"] as Array).duplicate():
		if col.hour >= int(dl["until"]):
			(st["deals"] as Array).erase(dl)
			changed = true
			if int(dl.get("need", 0)) > 0 and int(st["done"]) - int(dl.get("base", 0)) < int(dl["need"]):
				var why := "지구 협상 — %s의 조건(계약 %d건)을 지키지 못했다: %s" % [String(dl["title"]), int(dl["need"]),
					_ef_text(dl.get("fail", {}))]
				_effects(col, dl.get("fail", {}), why)
				var hs := col.home()
				if not hs.is_empty():
					(hs["sim"] as CitySim).note(why, "warn")
	if changed:
		_apply_deals(col)
	if day >= int(st["deal_next"]) and (st["pending"] as Dictionary).is_empty():
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([col.seed_value, day, "deals"])
		var ed2: Array = data().get("deals", {}).get("every_days", [100, 160])
		st["deal_next"] = day + rng2.randi_range(int(ed2[0]), int(ed2[1]))
		var inst := _pick_deal(col, rng2)
		if not inst.is_empty():
			(st["seen"] as Dictionary)[String(inst["id"])] = day
			var h := col.home()
			if not h.is_empty() and CityAuto.full(h["sim"]):
				resolve(col, best_choice(col, inst), true, inst)
			else:
				st["pending"] = inst
	if not (st["pending"] as Dictionary).is_empty():
		var h2 := col.home()
		if not h2.is_empty() and CityAuto.full(h2["sim"]):              # 기다리는 사이 자동 운영을 켰다
			resolve(col, best_choice(col, st["pending"]), true)
	if bool(Fleet.state(col).get("auto", true)):
		_auto(col)


## 함대 자동 운영: 남는 몫이 계약의 auto_spare를 넘고, 받는 도시에 다 들일 자리가 있고, 보내는 부두에 그 항로의 배가 머물러 있고,
## 마감이 auto_days 안이면 auto_active건까지 받는다 (배가 저쪽에 있거나 오가는 중이면 다음 창에 실을 배가 없을 수 있고,
## 목성·토성 항로는 몇 해를 묶인다 — 그런 계약은 사람이 고른다)
static func _auto(col: Colonies) -> void:
	var st := state(col)
	var od: Dictionary = data().get("offers", {})
	for ct in (st["offers"] as Array).duplicate():
		if (st["active"] as Array).size() >= int(od.get("auto_active", 2)):
			return
		if Fleet.docked(col, String(ct["route"]), String(ct["from"])).is_empty():
			continue
		if int(ct["deadline"]) - col.hour > int(od.get("auto_days", 1000)) * 24:
			continue
		if spare(city_of(col, ct, "from"), String(ct["good"])) < float(ct["amount"]) * float(od.get("auto_spare", 0.5)) \
				or room(city_of(col, ct, "to"), String(ct["good"])) < float(ct["amount"]):
			continue
		accept(col, int(ct["id"]), true)


# ── 지구 협상 ───────────────────────────────────────────────────
static func pending(col: Colonies) -> Dictionary:
	return state(col)["pending"] if not col.contracts.is_empty() else {}


static func _pick_deal(col: Colonies, rng: RandomNumberGenerator) -> Dictionary:
	var st := state(col)
	var day := col.hour / 24
	var pool: Array = []
	var total := 0.0
	for dl in data().get("deals", {}).get("list", []):
		var id := String(dl["id"])
		if (st["seen"] as Dictionary).has(id) and day - int(st["seen"][id]) < 300:
			continue
		if (st["deals"] as Array).any(func(x): return String(x["id"]) == id):
			continue
		var nd: Dictionary = dl.get("needs", {})
		var routes := Fleet.routes(col)
		if nd.has("routes") and not (nd["routes"] as Array).all(func(r): return routes.has(r)):
			continue
		if nd.has("min_rep") and float(st["rep"]) < float(nd["min_rep"]):
			continue
		pool.append(dl)
		total += float(dl.get("weight", 1.0))
	if pool.is_empty():
		return {}
	var pick := rng.randf() * total
	var d: Dictionary = pool[-1]
	for dl in pool:
		pick -= float(dl.get("weight", 1.0))
		if pick <= 0.0:
			d = dl
			break
	return {"id": String(d["id"]), "client": String(d.get("client", "")), "title": String(d["title"]), "text": String(d["text"]),
		"choices": (d["choices"] as Array).duplicate(true)}


## 시드가 고를 때의 점수: 지원 점수 0.02 · 기간 보정은 날수만큼 · 평판 1 · 신뢰 1.5 · 사기 1, 보수 떼기는 날마다 cut × 0.03,
## 조건이 있으면 못 지킬 때 잃는 것의 절반
static func _score(col: Colonies, ef: Dictionary) -> float:
	if ef.has("haggle"):
		var h: Dictionary = ef["haggle"]
		return _score(col, h.get("then", {}) if float(state(col)["rep"]) >= float(h.get("min_rep", 60)) else h.get("else", {}))
	var days := float(ef.get("days", 0))
	var s := float(ef.get("support", 0.0)) * 0.02 + float(ef.get("support_day", 0.0)) * days * 0.02 \
		+ float(ef.get("rp_day", 0.0)) * days * 0.004 + float(ef.get("rep", 0.0)) + float(ef.get("trust", 0.0)) * 1.5 \
		+ float(ef.get("morale", 0.0)) - float(ef.get("cut", 0.0)) * days * 0.03
	if int(ef.get("need_contracts", 0)) > 0:
		var f: Dictionary = ef.get("fail", {})
		s -= (absf(float(f.get("rep", 0.0))) + absf(float(f.get("trust", 0.0))) * 1.5) * 0.5
	return s


static func best_choice(col: Colonies, inst: Dictionary) -> int:
	var best := 0
	var choices: Array = inst["choices"]
	for i in choices.size():
		if _score(col, choices[i]["effect"]) > _score(col, choices[best]["effect"]):
			best = i
	return best


## 고른 것을 낸다 (inst가 없으면 기다리던 협상). 냈으면 true
static func resolve(col: Colonies, index: int, auto := false, inst: Dictionary = {}) -> bool:
	var st := state(col)
	if inst.is_empty():
		inst = st["pending"]
	if inst.is_empty() or index < 0 or index >= (inst["choices"] as Array).size():
		return false
	st["pending"] = {}
	var ch: Dictionary = inst["choices"][index]
	var ef: Dictionary = ch["effect"]
	var told := String(ch["label"])
	if ef.has("haggle"):
		var hg: Dictionary = ef["haggle"]
		var won := float(st["rep"]) >= float(hg.get("min_rep", 60))
		ef = hg.get("then", {}) if won else hg.get("else", {})
		told += " — 받아들여졌다" if won else " — 거절당했다"
	_effects(col, ef, "")
	var days := int(ef.get("days", 0))
	if days > 0 and (ef.has("support_day") or ef.has("rp_day") or ef.has("cut") or ef.has("need_contracts")):
		(st["deals"] as Array).append({"id": String(inst["id"]), "title": String(inst["title"]), "until": col.hour + days * 24,
			"support_day": float(ef.get("support_day", 0.0)), "rp_day": float(ef.get("rp_day", 0.0)), "cut": float(ef.get("cut", 0.0)),
			"cut_good": String(ef.get("cut_good", "")), "need": int(ef.get("need_contracts", 0)), "base": int(st["done"]),
			"fail": ef.get("fail", {})})
		_apply_deals(col)
	var text := "%s지구 협상 — %s (%s): %s (%s)" % ["자동 운영 · " if auto else "", String(inst["title"]), String(inst["client"]), told,
		String(ch.get("text", ""))]
	_log(col, text)
	var h := col.home()
	if not h.is_empty():
		(h["sim"] as CitySim).note(text, "info" if auto else "good")
	return true


## 바로 나는 효과: 고향 지원 점수 · 신뢰 · 사기, 평판
static func _effects(col: Colonies, ef: Dictionary, why: String) -> void:
	var st := state(col)
	var h := col.home()
	if ef.is_empty():
		return
	st["rep"] = clampf(float(st["rep"]) + float(ef.get("rep", 0.0)), 0.0, 100.0)
	if not h.is_empty():
		var sim: CitySim = h["sim"]
		sim.support += float(ef.get("support", 0.0))
		sim.trust = clampf(sim.trust + float(ef.get("trust", 0.0)), 0.0, 100.0)
		sim.morale = clampf(sim.morale + float(ef.get("morale", 0.0)), 0.0, 100.0)
	if why != "":
		_log(col, why)


## "평판 −10 · 신뢰 −3"
static func _ef_text(ef: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in [["rep", "평판"], ["trust", "신뢰"], ["morale", "사기"], ["support", "지원 점수"]]:
		if absf(float(ef.get(k[0], 0.0))) > 0.0:
			bits.append("%s %s%s" % [k[1], "+" if float(ef[k[0]]) > 0.0 else "−", Fmt.n(absf(float(ef[k[0]])))])
	return " · ".join(bits) if not bits.is_empty() else "효과 없음"


## 기간이 남은 거래의 보정을 고향의 deals 몫으로 (지원 점수/일 · 연구/일)
static func _apply_deals(col: Colonies) -> void:
	var h := col.home()
	if h.is_empty():
		return
	var sup := 0.0
	var rp := 0.0
	for dl in state(col)["deals"]:
		sup += float(dl.get("support_day", 0.0))
		rp += float(dl.get("rp_day", 0.0))
	CityExt.set_part(h, "deals", {"support_day": sup, "rp_day": rp})


## 지금 항로 계약 보수에서 떼는 몫 (그 물건에) — 0.9까지
static func cut(col: Colonies, key: String) -> float:
	var c := 0.0
	for dl in state(col)["deals"]:
		if String(dl.get("cut_good", "")) == "" or String(dl["cut_good"]) == key:
			c += float(dl.get("cut", 0.0))
	return minf(c, 0.9)


# ── 글 ──────────────────────────────────────────────────────────
## 제안: "지구 우주청 · 고향 → 화성 · 물 40 t — 발사 창 2번 안에 (2063.04.02까지) · 보수 지원 420, 위약금 168"
static func offer_text(col: Colonies, ct: Dictionary) -> String:
	return "%s · %s · %s — 발사 창 %d번 안에 (%s까지) · 보수 지원 %s, 못 마치면 위약금 %s" % [String(ct["client"]), leg_text(col, ct),
		unit_text(ct, float(ct["amount"])), int(ct.get("windows", 1)), col.date_text(float(ct["deadline"])), Fmt.n(float(ct["reward"])),
		Fmt.n(float(ct["penalty"]))]


## 계약: "지구 우주청 · 고향 → 화성 · 물 12 / 40 t (가는 중 12) · D-310 · 보수 420"
static func active_text(col: Colonies, ct: Dictionary) -> String:
	var g := good(String(ct["good"]))
	var dig := 1 if String(g.get("unit", "")) == "t" else 0
	var left := int(ceil((float(ct["deadline"]) - col.hour) / 24.0))
	return "%s · %s · %s %s / %s %s%s · D-%d · 보수 %s" % [String(ct["client"]), leg_text(col, ct), String(g.get("name", ct["good"])),
		Fmt.n(float(ct["delivered"]), dig), Fmt.n(float(ct["amount"]), dig), String(g.get("unit", "")),
		(" (가는 중 %s)" % Fmt.n(float(ct["sent"]), dig)) if float(ct["sent"]) > 0.0 else "", maxi(left, 0), Fmt.n(float(ct["reward"]))]


## 거래: "우주청 예산 증액 — 지원 +6/일 · 남은 210일 · 계약 1/2건"
static func deal_text(col: Colonies, dl: Dictionary) -> String:
	var bits := PackedStringArray()
	if float(dl.get("support_day", 0.0)) > 0.0:
		bits.append("지원 +%s/일" % Fmt.n(float(dl["support_day"])))
	if float(dl.get("rp_day", 0.0)) > 0.0:
		bits.append("연구 +%s/일" % Fmt.n(float(dl["rp_day"])))
	if float(dl.get("cut", 0.0)) > 0.0:
		bits.append("%s계약 보수 −%d%%" % [("%s " % String(good(String(dl["cut_good"])).get("name", ""))) if String(dl.get("cut_good", "")) != "" else "",
			int(round(float(dl["cut"]) * 100.0))])
	bits.append("남은 %d일" % maxi(0, int(ceil((float(dl["until"]) - col.hour) / 24.0))))
	if int(dl.get("need", 0)) > 0:
		bits.append("계약 %d/%d건" % [mini(int(state(col)["done"]) - int(dl.get("base", 0)), int(dl["need"])), int(dl["need"])])
	return "%s — %s" % [String(dl["title"]), " · ".join(bits)]
