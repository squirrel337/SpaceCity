class_name RoadWorks
extends RefCounted
## 길 재건축 — 자동 운영 도시의 길이 도시와 함께 자란다 (자료: data/city_layout.json의 road_works). 시뮬레이션 밖의 규칙이다
## (발전 모드·재건축과 같다 — 두 시뮬레이터의 일치에 들어가지 않는다). 공사는 배치 계획의 works에 있고 함께 저장된다.
##   넓히기: every_days마다 길마다 통행량을 셈한다 — 건물마다 가장 가까운 길에서 기지 가운데까지 가장 빠른 길(다익스트라)을 따라
##           1 + 집 16명마다 1 + 일손 8명마다 1을 더한다. 문턱(load)을 넘는 길 가운데 가장 붐비는 것과, 그 길과 한 줄로 이어진
##           같은 종류의 붐비는 길(문턱의 60%)을 네 토막까지 한 단계 넓힌다 (흙길 → 도로 → 대로 → 고속도로 — 넓어진 폭이 건물에
##           닿지 않을 때)
##   노선: 정착민이 늘면 lines의 차례대로 (고가 대로 · 모노레일 · 고가 고속도로 · 자기부상 궤도) 기지 가운데 꼭짓점(다 쓰였으면
##         한두 칸 옆의 대로 줄)에서 격자를 따라 곧게 놓는다 — 가진 땅 안, 끝이 길 그물의 꼭짓점, 건물·다른 높은 길에 걸리지 않는
##         가장 긴 줄 (min_cells~max_cells칸). 그 종류의 길이 이미 있으면 다음 노선
##   공사: 한 도시에 한 번에 한 곳. 값(그 길의 100 m마다 자재 × 길이 — 금속이 모자라면 지구에서 들여온다)을 먼저 내고 날마다
##         1/days씩 나아간다. 노선의 값을 낼 수 없으면 그동안 넓히기를 한다. 공사 자리에는 건물을
##         놓지 않는다 (CityPlan.check_spot). 넓히는 길은 둘레에 차단막이 서고, 노선은 기둥이 앞에서부터 올라간 뒤 덱이 놓인다
##         (3D: WorksView). 다 되면 길 그물에 들어간다 — 그새 길이 막혔으면 공사를 접고 값의 절반을 돌려받는다

const AXES := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]

static var _edge_of := {}          # 배치 계획 → {sig, map: 건물 uid → 가장 가까운 길} (길 모양이 그대로인 동안 새 건물만 찾는다 —
                                   # 넓히기처럼 종류만 바뀌면 그대로)


static func data() -> Dictionary:
	LayoutData.load_all()
	return LayoutData.data.get("road_works", {})


## 도시의 하루가 끝난 뒤 (CityDev.step_day — 자동 운영 도시만): 공사를 하루만큼 나아가고, every_days마다 다음 공사를 고른다
static func step(c: Dictionary, day: int, index: int) -> void:
	var rw := data()
	if rw.is_empty():
		return
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	advance(plan, sim)
	var every := int(rw.get("every_days", 6))
	if every > 0 and posmod(day + index, every) == 2 and plan.works.is_empty():
		start_next(c)


## 공사를 하루만큼 (1/days). 다 된 것은 길 그물에 넣는다
static func advance(plan: CityPlan, sim: CitySim) -> void:
	var done: Array = []
	for w in plan.works:
		w["p"] = minf(1.0, float(w["p"]) + 1.0 / maxf(float(w["days"]), 1.0))
		if float(w["p"]) >= 1.0:
			done.append(w)
	for w in done:
		plan.works.erase(w)
		finish(plan, w, sim)
	if not done.is_empty():
		plan.works_rev += 1


## 공사가 끝났다: 넓히기는 그 줄의 길 종류를 바꾸고, 노선은 길을 깐다. 그새 막혔으면 값의 절반을 돌려받는다
static func finish(plan: CityPlan, w: Dictionary, sim: CitySim) -> bool:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var type := String(w["type"])
	var ok := false
	if String(w["kind"]) == "widen":
		for k in plan.edges.size():
			var e: Vector2i = plan.edges[k]
			if plan.edge_type(k) == String(w["from"]) and _on_seg(a, b, plan.nodes[e.x]) and _on_seg(a, b, plan.nodes[e.y]):
				plan.etypes[k] = type
				ok = true
		if ok:
			plan._roads_changed()
	else:
		var why := plan.road_check(a, b, type)
		ok = why == "" and plan.add_road(a, b, CityPlan.SNAP_M, type)
	if sim != null:
		if ok:
			sim.note("완공 — %s %d m" % [title(w), int(round(float(w["len"])))], "build")
		else:
			for key in w.get("cost", {}):
				sim.stock[key] = float(sim.stock.get(key, 0.0)) + float(w["cost"][key]) * 0.5
			sim.note("길 공사를 접었다 — %s (그새 자리가 막혔다, 값의 절반을 돌려받았다)" % title(w), "warn")
	return ok


static func title(w: Dictionary) -> String:
	if String(w["kind"]) == "widen":
		return "%s → %s 넓히기" % [LayoutData.road_name(String(w["from"])), LayoutData.road_name(String(w["type"]))]
	return String(w.get("name", LayoutData.road_name(String(w["type"]))))


## 다음 공사: 정착민이 문턱을 넘은 노선 가운데 아직 없는 첫 것, 없으면 가장 붐비는 길 넓히기. 값을 내고 시작했으면 true
static func start_next(c: Dictionary) -> bool:
	var rw := data()
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var m := LayoutData.dev_mode(String(c.get("mode", "")))
	var reserve := float(m.get("reserve", {}).get("parts", 60.0))
	var keep := float(m.get("reserve", {}).get("support", 250.0))
	var pop := sim.population()
	var fail: Dictionary = c.get("line_fail", {})
	var sig := "%d|%d|%d" % [plan.road_rev, plan.land_rev, plan._bgen]
	for line in rw.get("lines", []):
		var type := String(line["type"])
		if pop < float(line.get("min_pop", 0)) or _has_type(plan, type) or String(fail.get(type, "")) == sig:
			continue
		var tech: Variant = line.get("tech")
		if tech != null and not sim.techs.has(String(tech)):
			continue
		var seg := plan_line(plan, type)
		if seg.is_empty():
			fail[type] = sig              # 길·땅·건물이 그대로인 동안 다시 찾지 않는다
			c["line_fail"] = fail
			continue
		var len_m := seg[0].distance_to(seg[1])
		var cost := cost_of(type, len_m)
		if not _ready(sim, cost, reserve, keep):
			break                         # 자재가 모이면 다음에 (그동안 넓히기는 한다)
		_pay(sim, cost)
		var w := {"kind": "line", "a": seg[0], "b": seg[1], "type": type, "name": String(line.get("name", "")),
			"p": 0.0, "days": maxf(4.0, len_m / 100.0 * float(rw.get("line_days_per_100m", 9.0))), "len": len_m, "cost": cost}
		plan.works.append(w)
		plan.works_rev += 1
		sim.note("길 공사 — %s %d m를 놓는다 (%d일)" % [title(w), int(round(len_m)), int(ceil(float(w["days"])))], "build")
		CityAuto.record(c, "land", "길 공사 — %s %d m: 정착민 %d명이 넘었다" % [title(w), int(round(len_m)), int(line.get("min_pop", 0))])
		return true
	var wd: Dictionary = rw.get("widen", {})
	if wd.is_empty() or pop < float(wd.get("min_pop", 150)):
		return false
	var run := widen_run(plan, wd)
	if run.is_empty():
		return false
	var len_w: float = (run["a"] as Vector2).distance_to(run["b"])
	var cost_w := cost_of(String(run["type"]), len_w)
	if not _ready(sim, cost_w, reserve, keep):
		return false
	_pay(sim, cost_w)
	var ww := {"kind": "widen", "a": run["a"], "b": run["b"], "from": run["from"], "type": run["type"], "p": 0.0,
		"days": maxf(float(wd.get("min_days", 3)), len_w / 100.0 * float(wd.get("days_per_100m", 5.0))), "len": len_w,
		"cost": cost_w, "load": run["load"]}
	plan.works.append(ww)
	plan.works_rev += 1
	sim.note("길 공사 — %s %d m (통행량 %d)" % [title(ww), int(round(len_w)), int(run["load"])], "build")
	CityAuto.record(c, "land", "길 공사 — %s %d m: 통행량 %d이 그 길이 감당할 만큼을 넘었다" % [title(ww), int(round(len_w)), int(run["load"])])
	return true


static func cost_of(type: String, len_m: float) -> Dictionary:
	var out := {}
	var per: Dictionary = LayoutData.road(type).get("cost_per_100m", {})
	for key in per:
		out[key] = snappedf(float(per[key]) * len_m / 100.0, 0.01)
	return out


## 값을 낼 수 있게 한다: 금속이 모자라면 지구에서 들여오고 (CityDev.import_metal), 부품이 reserve만큼 남는지
static func _ready(sim: CitySim, cost: Dictionary, reserve: float, keep: float) -> bool:
	var rest := cost.duplicate()
	rest.erase("metal_t")
	if not sim.can_afford(rest, reserve):
		return false
	return CityDev.import_metal(sim, float(cost.get("metal_t", 0.0)), keep)


static func _pay(sim: CitySim, cost: Dictionary) -> void:
	for key in cost:
		sim.stock[key] = float(sim.stock.get(key, 0.0)) - float(cost[key])


static func _has_type(plan: CityPlan, type: String) -> bool:
	for t in plan.etypes:
		if String(t) == type:
			return true
	for w in plan.works:
		if String(w["type"]) == type:
			return true
	return false


static func _on_seg(a: Vector2, b: Vector2, p: Vector2) -> bool:
	return CityPlan._seg_point(a, b, p).distance_to(p) < 0.5


# ── 통행량 ─────────────────────────────────────────────────────
## 길마다 통행량: 건물마다 (1 + 집/16 + 일손/8)을 그 건물에 가장 가까운 길과, 그 길에서 기지 가운데까지 가장 빠른 길의 토막마다 더한다
static func loads(plan: CityPlan) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(plan.edges.size())
	if plan.edges.is_empty():
		return out
	var adj := plan._adjacency()
	var n := plan.nodes.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var parent := PackedInt32Array()          # 기지 가운데 쪽으로 가는 길 번호
	parent.resize(n)
	parent.fill(-1)
	var src := _nearest_node(plan, plan.hub())
	dist[src] = 0.0
	var heap: Array = [[0.0, src]]
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var u := int(top[1])
		if float(top[0]) > dist[u]:
			continue
		for pair in adj[u]:
			var v := int(pair[0])
			var k := int(pair[2])
			var nd := dist[u] + float(pair[1]) / maxf(float(LayoutData.road(plan.edge_type(k)).get("speed", 1.0)), 0.1)
			if nd < dist[v]:
				dist[v] = nd
				parent[v] = k
				_push(heap, [nd, v])
	var node_w := PackedFloat32Array()
	node_w.resize(n)
	if _edge_of.size() > 32:
		_edge_of.clear()
	var raised := 0
	for t in plan.etypes:
		if LayoutData.raised(String(t)):
			raised += 1
	var sig := "%d|%d|%d" % [plan.nodes.size(), plan.edges.size(), raised]
	var cache: Dictionary = _edge_of.get(plan.get_instance_id(), {})
	if String(cache.get("sig", "")) != sig:
		cache = {"sig": sig, "map": {}}
		_edge_of[plan.get_instance_id()] = cache
	var map: Dictionary = cache["map"]
	var indexed := false
	for e in plan.buildings:
		if int(e["seq"]) >= 0:
			continue
		var uid := int(e["uid"])
		var k := int(map.get(uid, -2))
		if k == -2:
			if not indexed:
				plan._near_edges(Rect2())         # 길 색인을 지금 길 그물로 (nearest_edge가 둘레 칸만 본다)
				indexed = true
			k = plan.nearest_edge(Vector2(float(e["x"]), float(e["y"])), 48.0, true)
			map[uid] = k
		if k < 0:
			continue
		var m: Dictionary = GameData.MODULES.get(String(e["id"]), {})
		var wgt := 1.0 + float(m.get("provides", {}).get("housing", 0.0)) / 16.0 + float(m.get("crew", 0)) / 8.0
		out[k] += wgt
		var ed: Vector2i = plan.edges[k]
		node_w[ed.x if dist[ed.x] <= dist[ed.y] else ed.y] += wgt
	# 먼 꼭짓점부터 기지 가운데 쪽으로 모은다
	var order: Array = range(n)
	order.sort_custom(func(x: int, y: int) -> bool: return dist[x] > dist[y])
	for u: int in order:
		var k2 := parent[u]
		if k2 < 0 or dist[u] == INF:
			continue
		out[k2] += node_w[u]
		var ed2: Vector2i = plan.edges[k2]
		node_w[ed2.x if ed2.y == u else ed2.y] += node_w[u]
	return out


static func _nearest_node(plan: CityPlan, p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in plan.nodes.size():
		var d := (plan.nodes[i] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var up := (i - 1) >> 1
		if float(heap[up][0]) <= float(item[0]):
			break
		heap[i] = heap[up]
		i = up
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var size := heap.size()
	while true:
		var l := i * 2 + 1
		if l >= size:
			break
		var r := l + 1
		var c := r if r < size and float(heap[r][0]) < float(heap[l][0]) else l
		if float(heap[c][0]) >= float(last[0]):
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


## 넓힐 줄: 문턱을 넘는 가장 붐비는 땅 위의 길과, 그 길과 한 줄로 이어진 같은 종류의 붐비는 길 (네 토막까지).
## 넓어진 폭이 건물에 닿으면 다음 길. {a, b, from, type, load} 또는 {}
static func widen_run(plan: CityPlan, wd: Dictionary) -> Dictionary:
	var steps: Dictionary = wd.get("steps", {})
	var limit: Dictionary = wd.get("load", {})
	var ld := loads(plan)
	var order: Array = []
	for k in plan.edges.size():
		var t := plan.edge_type(k)
		if steps.has(t) and ld[k] >= float(limit.get(t, INF)) and not _busy(plan, k):
			order.append(k)
	order.sort_custom(func(x: int, y: int) -> bool: return ld[x] > ld[y])
	var adj := plan._adjacency()
	for k: int in order:
		var t := plan.edge_type(k)
		var to := String(steps[t])
		var e: Vector2i = plan.edges[k]
		var a: Vector2 = plan.nodes[e.x]
		var b: Vector2 = plan.nodes[e.y]
		var dir := (b - a).normalized()
		var ends := [e.x, e.y]
		var count := 1
		for side in 2:
			var at: int = ends[side]
			var sgn := -1.0 if side == 0 else 1.0
			while count < 4:
				var next := -1
				for pair in adj[at]:
					var k2 := int(pair[2])
					var q: Vector2 = plan.nodes[int(pair[0])]
					if k2 != k and plan.edge_type(k2) == t and ld[k2] >= float(limit.get(t, INF)) * 0.6 \
							and ((q - plan.nodes[at]).normalized() * sgn).dot(dir) > 0.999 and not _busy(plan, k2):
						next = int(pair[0])
						break
				if next < 0:
					break
				at = next
				count += 1
			ends[side] = at
		var ra: Vector2 = plan.nodes[ends[0]]
		var rb: Vector2 = plan.nodes[ends[1]]
		if plan.road_check(ra, rb, to, false) == "":
			return {"a": ra, "b": rb, "from": t, "type": to, "load": ld[k]}
	return {}


## 그 길이 공사 중인 줄 위에 있나
static func _busy(plan: CityPlan, k: int) -> bool:
	var e: Vector2i = plan.edges[k]
	for w in plan.works:
		if _on_seg(w["a"], w["b"], plan.nodes[e.x]) and _on_seg(w["a"], w["b"], plan.nodes[e.y]):
			return true
	return false


# ── 노선 ───────────────────────────────────────────────────────
## 노선 자리: 기지 가운데 꼭짓점에서 (그 줄이 다 쓰였으면 한두 칸 옆 줄에서) 격자 네 방향으로 max_cells칸부터 줄여 가며 —
## 끝이 길 그물의 꼭짓점이고, 가진 땅 안이고, 다른 높은 길과 한 줄로 겹치지 않고, road_check를 지나는 가장 긴 것.
## 같은 길이면 산 땅이 많은 쪽. [a, b] 또는 []
static func plan_line(plan: CityPlan, type: String) -> PackedVector2Array:
	var rw := data()
	var pitch := plan.layout.pitch
	var hub := plan.hub()
	var o := plan.nodes[_nearest_node(plan, hub)] as Vector2
	var best := PackedVector2Array()
	var best_score := -INF
	for shift: int in [0, 1, -1, 2, -2]:
		for dir: Vector2 in AXES:
			var side := Vector2(-dir.y, dir.x)
			var a := o + side * pitch * shift
			var ia := _node_near(plan, a)
			if ia < 0:
				continue
			a = plan.nodes[ia]
			for cells in range(int(rw.get("max_cells", 6)), int(rw.get("min_cells", 2)) - 1, -1):
				var b := a + dir * pitch * cells
				var ib := _node_near(plan, b)
				if ib < 0 or not plan.in_land(b, 2.0) or _along_raised(plan, a, b):
					continue
				if plan.road_check(a, b, type) != "":
					continue
				var score := cells * 10.0 + _land_toward(plan, a, dir) - absf(shift) * 5.0
				if score > best_score:
					best_score = score
					best = PackedVector2Array([a, plan.nodes[ib]])
				break
		if not best.is_empty():
			return best                   # 가운데에 가까운 줄부터
	return best


static func _node_near(plan: CityPlan, p: Vector2) -> int:
	for i in plan.nodes.size():
		if (plan.nodes[i] as Vector2).distance_to(p) < 1.0:
			return i
	return -1


## a→b 줄이 이미 있는 높은 길(또는 공사 중인 노선)과 한 줄로 겹치나 (10 m마다 3 m 안)
static func _along_raised(plan: CityPlan, a: Vector2, b: Vector2) -> bool:
	var segs: Array = []
	for k in plan.edges.size():
		if LayoutData.raised(plan.edge_type(k)):
			segs.append([plan.nodes[plan.edges[k].x], plan.nodes[plan.edges[k].y]])
	for w in plan.works:
		if String(w["kind"]) == "line":
			segs.append([w["a"], w["b"]])
	var n := maxi(2, int(a.distance_to(b) / 10.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		for s in segs:
			if CityPlan._seg_point(s[0], s[1], p).distance_to(p) < 3.0:
				return true
	return false


## 그 방향 반쪽에 있는 산 땅 구역 수
static func _land_toward(plan: CityPlan, a: Vector2, dir: Vector2) -> float:
	var n := 0.0
	for cell in plan.land:
		if (plan.parcel_rect(cell).get_center() - a).dot(dir) > 0.0:
			n += 1.0
	return n


# ── 저장 ───────────────────────────────────────────────────────
static func to_save(works: Array) -> Array:
	var out := []
	for w in works:
		var d: Dictionary = (w as Dictionary).duplicate()
		d["a"] = [snappedf((w["a"] as Vector2).x, 0.01), snappedf((w["a"] as Vector2).y, 0.01)]
		d["b"] = [snappedf((w["b"] as Vector2).x, 0.01), snappedf((w["b"] as Vector2).y, 0.01)]
		out.append(d)
	return out


static func from_save(list: Variant) -> Array:
	var out := []
	if not list is Array:
		return out
	for d in list:
		if not d is Dictionary or not d.get("a") is Array or not d.get("b") is Array or not String(d.get("kind", "")) in ["widen", "line"]:
			continue
		LayoutData.load_all()
		if not (LayoutData.data["roads"] as Dictionary).has(String(d.get("type", ""))):
			continue
		var w: Dictionary = d.duplicate()
		w["a"] = Vector2(float(d["a"][0]), float(d["a"][1]))
		w["b"] = Vector2(float(d["b"][0]), float(d["b"][1]))
		w["p"] = clampf(float(d.get("p", 0.0)), 0.0, 1.0)
		w["days"] = maxf(float(d.get("days", 1.0)), 1.0)
		w["len"] = (w["a"] as Vector2).distance_to(w["b"])
		out.append(w)
	return out
