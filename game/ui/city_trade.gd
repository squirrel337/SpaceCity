class_name CityTrade
extends RefCounted
## 수출 계약 (자료: data/city_trade.json). 시뮬레이션 밖의 규칙이다 — 모든 도시에.
## 도시마다 every_days마다 계약 제안이 offers건까지 들어온다 (도시·날로 정해지는 난수 — 다시 해도 같다): 그 도시가 만드는
## 물건(만드는 계열이 있거나 비축이 넉넉한 것)을, 지구의 사는 쪽이나 다른 도시가 산다. 제안은 offer_days 뒤에 사라진다.
## 받으면 deadline_days 안에 보내야 한다 — 보내면 지원 점수와 신뢰, 다른 도시가 샀으면 그 도시 비축에 더해진다
## (화물 착륙선이 내려와 싣고 간다). 못 보내면 신뢰와 사기를 잃는다.
## 직접 운영은 '개척' 탭에서 받고 보낸다. 자동 운영은 남는 양(비축 − 남길 양)을 보고 스스로 받고 보낸다.
## 상태는 c["trade"]: {offers: [제안], active: [받은 계약], next: 다음 제안 날, serial, done, failed, earned}
##   제안·계약: {id, good, amount(보이는 단위), reward, buyer(이름), to(산 도시의 부지 — 지구면 ""), expires·due(시간), days}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_trade.json"))
		_data = parsed if parsed is Dictionary else {"goods": [], "buyers": []}
	return _data


static func good(id: String) -> Dictionary:
	for g in data()["goods"]:
		if String(g["id"]) == id:
			return g
	return {}


static func state(c: Dictionary) -> Dictionary:
	if not c.get("trade") is Dictionary:
		c["trade"] = {"offers": [], "active": [], "next": 0, "serial": 0, "done": 0, "failed": 0, "earned": 0.0}
	return c["trade"]


## 그 물건의 비축 (보이는 단위)
static func have(sim: CitySim, g: Dictionary) -> float:
	return float(sim.stock.get(String(g["stock"]), 0.0)) / float(g.get("per_unit", 1.0))


## 남길 양 (보이는 단위): 사람이 쓰는 것은 정착민이 keep_days만큼 쓸 양, 그 밖에는 keep
static func keep(sim: CitySim, g: Dictionary) -> float:
	if g.has("keep_days"):
		var per := String(CitySim.SUPPLY_PER.get(String(g["stock"]), ""))
		var use := float(sim.PER.get(per, 0.0)) * sim.population()
		return use * float(g["keep_days"]) / float(g.get("per_unit", 1.0))
	return float(g.get("keep", 0.0))


static func spare(sim: CitySim, g: Dictionary) -> float:
	return have(sim, g) - keep(sim, g)


## 이 도시에 제안이 올 물건들: 그 천체에서 나고, 만드는 계열이 있거나 비축이 lots의 두 배를 넘는 것
static func goods_for(sim: CitySim) -> Array:
	var body := String(GameData.site(sim.site_id).get("body", "moon"))
	var out: Array = []
	for g in data()["goods"]:
		if body in g.get("skip_bodies", []):
			continue
		var made := false
		for mid in sim.counts:
			if int(sim.counts[mid]) > 0 and sim.family(mid) in g.get("makers", []):
				made = true
				break
		if made or have(sim, g) >= float(g["lots"][0]) * 2.0:
			out.append(g)
	return out


## 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시): 지난 제안을 지우고, 기한을 넘긴 계약은 놓치고,
## 제안 날이면 새 제안을 받고, 자동 운영이면 받고 보낸다
static func step(c: Dictionary, day: int, mgr: Colonies = null) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var d := data()
	st["offers"] = (st["offers"] as Array).filter(func(o): return int(o["expires"]) > sim.hour)
	for a in (st["active"] as Array).duplicate():
		if sim.hour >= int(a["due"]):
			(st["active"] as Array).erase(a)
			st["failed"] = int(st["failed"]) + 1
			sim.trust = maxf(0.0, sim.trust - float(d.get("trust_loss", 3.0)))
			sim.morale = maxf(0.0, sim.morale - float(d.get("morale_loss", 1.0)))
			sim.note("수출 계약을 놓쳤다 — %s에 %s. 신뢰 −%s" % [String(a["buyer"]), amount_text(a),
				str(d.get("trust_loss", 3.0))], "warn")
	if day >= int(st["next"]):
		st["next"] = day + int(d.get("every_days", 20))
		_offer(c, day, mgr)
	if sim.autopilot != null:
		_auto(c, mgr)


## 새 제안: offers건이 될 때까지 (이미 제안한 물건은 빼고)
static func _offer(c: Dictionary, day: int, mgr: Colonies) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed_value, sim.site_id, day, "trade"])
	var pool := goods_for(sim)
	var offered := {}
	for o in st["offers"]:
		offered[String(o["good"])] = true
	pool = pool.filter(func(g): return not offered.has(String(g["id"])))
	var others: Array = []
	if mgr != null:
		for o in mgr.list:
			if o != c:
				others.append(o)
	var size_k := clampf(sqrt(sim.population() / 120.0), 1.0, 3.0)
	while (st["offers"] as Array).size() < int(d.get("offers", 3)) and not pool.is_empty():
		var g: Dictionary = pool.pop_at(rng.randi() % pool.size())
		var lots: Array = g["lots"]
		var step := float(g.get("step", 1.0))
		var amount := maxf(step, snappedf(rng.randf_range(float(lots[0]), float(lots[1])) * size_k, step))
		var reward := snappedf(amount * float(g["price"]) * rng.randf_range(float(d["premium"][0]), float(d["premium"][1])), 5.0)
		var buyer := String(d["buyers"][rng.randi() % (d["buyers"] as Array).size()])
		var to := ""
		if not others.is_empty() and rng.randf() < float(d.get("colony_share", 0.35)):
			var oc: Dictionary = others[rng.randi() % others.size()]
			buyer = String(oc["name"])
			to = String(oc["site"])
		var dd: Array = d["deadline_days"]
		st["serial"] = int(st["serial"]) + 1
		(st["offers"] as Array).append({"id": int(st["serial"]), "good": String(g["id"]), "amount": amount,
			"reward": maxf(reward, 5.0), "buyer": buyer, "to": to, "expires": sim.hour + int(d.get("offer_days", 12)) * 24,
			"days": rng.randi_range(int(dd[0]), int(dd[1]))})


static func max_active(c: Dictionary) -> int:
	var d := data()
	return int(d.get("max_active", 3)) + (int(d["auto"].get("trade_extra", 2)) if String(c.get("mode", "")) == "trade" else 0)


## 제안을 받는다: 받은 계약이 된다 (기한은 받은 때부터)
static func accept(c: Dictionary, id: int) -> bool:
	var st := state(c)
	var sim: CitySim = c["sim"]
	if (st["active"] as Array).size() >= max_active(c):
		return false
	for o in st["offers"]:
		if int(o["id"]) == id:
			(st["offers"] as Array).erase(o)
			var a: Dictionary = o.duplicate()
			a["due"] = sim.hour + int(o["days"]) * 24
			(st["active"] as Array).append(a)
			sim.note("수출 계약 — %s에 %s, %d일 안에 (지원 점수 +%d)" % [String(a["buyer"]), amount_text(a), int(a["days"]),
				int(a["reward"])], "info")
			return true
	return false


## 보낼 수 없으면 까닭, 보낼 수 있으면 ""
static func can_deliver(c: Dictionary, id: int) -> String:
	var sim: CitySim = c["sim"]
	for a in state(c)["active"]:
		if int(a["id"]) == id:
			var g := good(String(a["good"]))
			if have(sim, g) + 1e-6 < float(a["amount"]):
				return "%s 모자람 (%s / %s)" % [String(g["name"]), _num(have(sim, g), g), _num(float(a["amount"]), g)]
			return ""
	return "계약이 없다"


## 보낸다: 비축에서 빼고, 지원 점수·신뢰를 받고, 다른 도시가 샀으면 그 도시 비축에 더한다. 화물 착륙선이 싣고 간다
static func deliver(c: Dictionary, id: int, mgr: Colonies = null) -> bool:
	if can_deliver(c, id) != "":
		return false
	var st := state(c)
	var sim: CitySim = c["sim"]
	var d := data()
	for a in st["active"]:
		if int(a["id"]) != id:
			continue
		var g := good(String(a["good"]))
		var raw := float(a["amount"]) * float(g.get("per_unit", 1.0))
		var key := String(g["stock"])
		sim.stock[key] = float(sim.stock.get(key, 0.0)) - raw
		sim.support += float(a["reward"])
		sim.trust = minf(100.0, sim.trust + float(d.get("trust_win", 1.0)))
		sim.stats["exports"] = int(sim.stats.get("exports", 0)) + 1     # 3D: 화물 착륙선 (BaseTraffic)
		(st["active"] as Array).erase(a)
		st["done"] = int(st["done"]) + 1
		st["earned"] = float(st["earned"]) + float(a["reward"])
		var to := String(a.get("to", ""))
		if to != "" and mgr != null and mgr.index_of_site(to) >= 0:
			var other: CitySim = mgr.list[mgr.index_of_site(to)]["sim"]
			other.stock[key] = float(other.stock.get(key, 0.0)) + raw
			other.note("수입 — %s에서 %s가 왔다" % [String(c["name"]), amount_text(a)], "info")
		sim.note("수출 — %s에 %s를 보냈다 (지원 점수 +%d)" % [String(a["buyer"]), amount_text(a), int(a["reward"])], "good")
		return true
	return false


## 자동 운영: 남는 양이 넉넉한 제안은 받고, 남는 양으로 보낼 수 있는 계약은 보낸다 (기한이 이른 것부터 — 받은 날 바로 보내므로
## 남는 양이 줄어 놓치는 일이 없다. 무역 중심 도시는 모자라도 받아 두었다가 쌓이면 보낸다)
static func _auto(c: Dictionary, mgr: Colonies) -> void:
	var st := state(c)
	var sim: CitySim = c["sim"]
	var k := float(data()["auto"].get("trade_accept_k" if String(c.get("mode", "")) == "trade" else "accept_k", 1.0))
	for o in (st["offers"] as Array).duplicate():
		if (st["active"] as Array).size() >= max_active(c):
			break
		var g := good(String(o["good"]))
		var pending := 0.0                     # 같은 물건으로 이미 받은 계약
		for a in st["active"]:
			if String(a["good"]) == String(o["good"]):
				pending += float(a["amount"])
		if spare(sim, g) - pending >= float(o["amount"]) * k:
			accept(c, int(o["id"]))
	var act: Array = (st["active"] as Array).duplicate()
	act.sort_custom(func(x, y): return int(x["due"]) < int(y["due"]))
	for a in act:
		if spare(sim, good(String(a["good"]))) >= float(a["amount"]):
			deliver(c, int(a["id"]), mgr)


static func _num(v: float, g: Dictionary) -> String:
	return ("%d" % int(round(v))) if float(g.get("step", 1.0)) >= 1.0 else str(snappedf(v, 0.1))


static func amount_text(a: Dictionary) -> String:
	var g := good(String(a["good"]))
	return "%s %s %s" % [String(g.get("name", "?")), _num(float(a["amount"]), g), String(g.get("unit", ""))]
