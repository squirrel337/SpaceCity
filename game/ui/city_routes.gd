class_name CityRoutes
extends RefCounted
## 정기 교역 — 플레이어가 정한 도시 사이의 정기 화물 (교통 탭). 시뮬레이션 밖의 규칙이다.
## 도시 사이 교통(Transport)이 모자란 것을 스스로 실어 나르는 것과 따로, "A에서 B로 물건 몇 단위를 며칠마다"를 정해 두면 그날마다
## 그 노선의 특별편(Transport.dispatch)으로 떠난다 — 같은 천체 안의 도시끼리(로버 화물 열차·호퍼·수송기·회전익기)와 지구–달 셔틀.
## 행성 사이는 수송선이 발사 창마다 모자란 것을 실어 나르므로 정기 교역은 없다.
##   보낼 양 = 정한 양과 남는 양(비축 − 남길 양 — CityTrade.keep) 가운데 작은 것, 탈것의 적재 한도(t)까지.
##   셔틀은 보내는 도시가 운임(지원 점수, t마다)을 낸다. 보낼 것이 없으면 그날은 건너뛴다.
## 상태는 Colonies.routes: [{id, from, to, key(비축 열쇠), amount, every, next(날), on, sent, moved, last}] — 저장된다

const GOODS := [["water_kg", "물", 1000.0, "t"], ["o2_kg", "산소", 1000.0, "t"], ["food_kg", "식량", 1000.0, "t"],
	["parts", "부품", 1.0, "개"], ["metal_t", "금속", 1.0, "t"]]       # [비축 열쇠, 이름, 보이는 단위 하나의 비축 값, 단위]


static func good_of(key: String) -> Array:
	for g in GOODS:
		if g[0] == key:
			return g
	return [key, key, 1.0, ""]


## 두 도시를 잇는 노선: [노선 id, 방향(0 = a에서), 받을 도시, 걸리는 시간(시 — −1이면 노선의 시간)]. 없으면 []
## 두 도시를 바로 잇는 노선(같은 천체·셔틀)이 먼저. 같은 천체인데 바로 잇는 노선이 없으면 보내는 도시에서 받을 도시 쪽으로
## 가는 노선의 탈것이 두 도시 사이 거리만큼 간다
static func link(col: Colonies, from: String, to: String) -> Array:
	if from == to or col.index_of_site(from) < 0 or col.index_of_site(to) < 0:
		return []
	var pair := Transport._pair(from, to)
	for id in ["local:" + pair, "shuttle:" + pair]:
		var l := col.transport.line_by_id(id)
		if not l.is_empty():
			return [id, 0 if String(l["a"]) == from else 1, to, -1]
	if Transport.node_body(from) != Transport.node_body(to):
		return []
	var best := {}
	var best_km := INF
	for l in col.transport.lines:
		if String(l["role"]) != "local" or (String(l["a"]) != from and String(l["b"]) != from):
			continue
		var other := String(l["b"] if String(l["a"]) == from else l["a"])
		var km := Transport.surface_km(other, to)
		if km < best_km:
			best_km = km
			best = l
	if best.is_empty():
		return []
	var md := Transport.mode(String(best["mode"]))
	var spd := float(md.get("speed_km_h", 0.0))
	var h := int(ceil(float(md.get("load_h", 1)) + Transport.surface_km(from, to) / spd)) if spd > 0.0 else int(best["trip_h"])
	return [String(best["id"]), 0 if String(best["a"]) == from else 1, to, maxi(1, h)]


## 정기 교역을 더할 수 없으면 까닭
static func check(col: Colonies, from: String, to: String, key: String, amount: float, every: int) -> String:
	if from == to:
		return "보내는 도시와 받는 도시가 같다"
	if col.index_of_site(from) < 0 or col.index_of_site(to) < 0:
		return "도시가 없다"
	if amount <= 0.0 or every < 1:
		return "양과 날수를 정한다"
	if link(col, from, to).is_empty():
		return "이어진 노선이 없다 — 같은 천체의 도시끼리, 또는 지구 우주항과 달 고향 사이 셔틀로만"
	return ""


static func add(col: Colonies, from: String, to: String, key: String, amount: float, every: int) -> String:
	var why := check(col, from, to, key, amount, every)
	if why != "":
		return why
	var serial := 1
	for r in col.routes:
		serial = maxi(serial, int(r["id"]) + 1)
	col.routes.append({"id": serial, "from": from, "to": to, "key": key, "amount": amount, "every": every,
		"next": int(floor(col.hour / 24.0)), "on": true, "sent": 0, "moved": 0.0, "last": ""})
	return ""


static func remove(col: Colonies, id: int) -> void:
	col.routes = col.routes.filter(func(r): return int(r["id"]) != id)


## 하루에 한 번 (Colonies.step — 교통 뒤): 날이 된 정기 교역을 보낸다
static func step(col: Colonies) -> void:
	var day := int(floor(col.hour / 24.0))
	for r in col.routes:
		if not bool(r["on"]) or day < int(r["next"]):
			continue
		r["next"] = day + maxi(1, int(r["every"]))
		send(col, r)


## 한 번 보낸다. 보냈으면 true
static func send(col: Colonies, r: Dictionary) -> bool:
	var lk := link(col, String(r["from"]), String(r["to"]))
	var si := col.index_of_site(String(r["from"]))
	if lk.is_empty() or si < 0:
		r["last"] = "노선이 끊겼다"
		return false
	var c: Dictionary = col.list[si]
	var src: CitySim = c["sim"]
	var key := String(r["key"])
	var g := good_of(key)
	var tg := {"stock": key, "per_unit": g[2], "keep": 0.0}
	# 남길 양: 수출 계약과 같은 셈 (사람이 쓰는 것은 정착민의 날수, 부품 200, 금속 20)
	for cg in CityTrade.data()["goods"]:
		if String(cg["stock"]) == key:
			tg = cg
	var spare := CityTrade.spare(src, tg) * float(tg.get("per_unit", 1.0))          # 비축 값으로
	var l := col.transport.line_by_id(String(lk[0]))
	var cap := float(Transport.mode(String(l["mode"])).get("cap_t", 0.0))
	var t_per := float(Transport.cargo_rule(key).get("t_per", 0.001))
	var raw := minf(float(r["amount"]) * float(g[2]), spare)
	raw = minf(raw, cap / maxf(t_per, 1e-9))
	if raw * t_per < 0.05 or raw < float(r["amount"]) * float(g[2]) * 0.1:
		r["last"] = "보낼 것이 모자라 건너뛰었다"
		return false
	raw = floorf(raw) if g[2] <= 1.0 else floorf(raw / 100.0) * 100.0      # 0.1 t 단위로 (남는 몫을 넘지 않게 내림)
	var fee := 0.0
	if String(l["role"]) == "shuttle":
		fee = raw * t_per * Transport.freight_per_t() * col.metro_fn.modes.freight_k()
		if src.support < fee:
			r["last"] = "운임(지원 점수 %d)이 모자라 건너뛰었다" % int(ceil(fee))
			return false
		src.support -= fee
	src.stock[key] = float(src.stock.get(key, 0.0)) - raw
	var trip := col.transport.dispatch(col, String(lk[0]), int(lk[1]), {key: raw}, "route", int(lk[3]), String(lk[2]))
	if trip.is_empty():
		src.stock[key] = float(src.stock.get(key, 0.0)) + raw         # 노선이 꺼져 있다 — 되돌린다
		src.support += fee
		r["last"] = "노선이 꺼져 있다"
		return false
	r["sent"] = int(r["sent"]) + 1
	r["moved"] = float(r["moved"]) + raw / float(g[2])
	var what := "%s %s %s" % [g[1], Fmt.n(raw / float(g[2]), 1 if g[2] > 1.0 else 0), g[3]]
	r["last"] = "%s 보냄 — %s 도착" % [what, col.date_text(float(trip["arrive"]))]
	src.note("정기 교역 — %s로 %s%s" % [Transport.node_name(String(r["to"])), what, (" (운임 %d)" % int(round(fee))) if fee > 0.0 else ""], "info")
	return true


static func text(r: Dictionary) -> String:
	var g := good_of(String(r["key"]))
	return "%s → %s · %s %s %s · %d일마다" % [Transport.node_name(String(r["from"])), Transport.node_name(String(r["to"])), g[1],
		Fmt.n(float(r["amount"]), 1 if g[2] > 1.0 else 0), g[3], int(r["every"])]
