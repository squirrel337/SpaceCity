class_name CityServices
extends RefCounted
## 도시 기능의 자리 — 시설 영향 범위·통근·도시 안 물류 (자료: data/city_layout.json의 services). 시뮬레이션 밖의 규칙이다:
## 배치 계획(자리)으로 셈해 시뮬레이션에 보정 세 가지를 건넨다 (CityExt의 services 몫 → CitySim.ext — 기본값이면 두 시뮬레이터가
## 같은 셈을 한다).
##   영향 범위: 집마다 (사는 사람 = 그 집 × 정착민 ÷ 집 수) 둘레 radius_m 안에 그 시설이 있나 — care 의료 · leisure 여가(사기를
##              주는 시설, 교신 계열 빼고) · shelter 대피. 닿지 않는 사람의 몫마다 penalty, 닿는 몫마다 bonus → 사기 (ext.morale)
##   통근: 일터(일손이 있는 건물)를 가장 가까운 길 꼭짓점마다 모아 일손이 많은 곳부터 JOB_K곳 — 집마다 그 일터들까지 가는 시간을
##         일손 몫으로 평균한다 (일자리가 큰 곳일수록 많이 간다). 길까지 걷고(walk_mps) 길을 따라 탈것으로(base_mps × 길의 속력 —
##         고가·궤도 노선이 빠르다). 환승 계열(build_boost가 있는 교통 시설)이 hub_m 안이면 ×0.75. 평균 분이 typical_min보다
##         짧으면 일하는 효율이 오르고 길면 내린다 — 1 + (typical − 분) ÷ per_min, [lo, hi] (ext.work_k — 연구원의 연구, 상업의 지원 점수)
##   물류: 만드는 건물(산업 분류)마다 가장 가까운 저장 시설(storage)까지 길을 따라 — 로버 차고지가 depot_m 안이면 ×0.8.
##         평균 km가 typical_km보다 짧으면 만드는 효율이 오른다 — 1 + (typical − km) × per_km, [lo, hi] (ext.make_k — 3순위 산업의
##         얼음·레골리스·금속·부품, 교역·첨단 제조의 부품)
## 엿새마다 (도시마다 다른 날에) 다시 잰다 — 자동 운영이 아니어도 (모든 도시)

const CARE_KEYS := {"care": "care", "leisure": "morale", "shelter": "shelter"}
const JOB_K := 8


static func data() -> Dictionary:
	LayoutData.load_all()
	return LayoutData.data.get("services", {})


## 그 도시의 하루가 끝난 뒤 (Colonies.step — 모든 도시): every_days마다 다시 재서 시뮬레이션에 건넨다
static func step(c: Dictionary, day: int, index: int) -> void:
	var sv := data()
	var every := int(sv.get("every_days", 6))
	if sv.is_empty() or every <= 0 or (posmod(day + index, every) != 3 and c.has("services")):
		return
	apply(c)


static func apply(c: Dictionary) -> void:
	var m := measure(c["plan"], c["sim"])
	c["services"] = m
	CityExt.set_part(c, "services", m["ext"])


## {cover: {care, leisure, shelter — 사는 사람 가운데 닿는 몫}, commute_min, freight_km, ext: {morale, work_k, make_k}}
static func measure(plan: CityPlan, sim: CitySim) -> Dictionary:
	var sv := data()
	var out := {"cover": {}, "commute_min": 0.0, "freight_km": 0.0, "ext": {"morale": 0.0, "work_k": 1.0, "make_k": 1.0}}
	if sv.is_empty() or sim == null:
		return out
	var homes: Array = []          # [자리, 사는 사람]
	var works: Array = []          # [일터 자리, 일손]
	var makers: Array = []         # 만드는 건물 자리
	var stores: Array = []         # 저장 시설 자리
	var hubs: Array = []           # 환승 시설 자리
	var depots: Array = []         # 로버 차고지 자리
	var prov: Dictionary = {}      # 시설 갈래 → 자리들
	for key in CARE_KEYS:
		prov[key] = []
	var occ := sim.population() / maxf(sim.housing_cap, 1.0)
	for e in plan.buildings:
		if int(e["seq"]) >= 0:
			continue
		var mid := String(e["id"])
		var m: Dictionary = GameData.MODULES.get(mid, {})
		if m.is_empty():
			continue
		var p := Vector2(float(e["x"]), float(e["y"]))
		var pv: Dictionary = m.get("provides", {})
		if float(pv.get("housing", 0.0)) > 0.0:
			homes.append([p, float(pv["housing"]) * occ])
		if int(m.get("crew", 0)) > 0:
			works.append([p, float(m["crew"])])
		if String(m.get("category", "")) == "industry":
			makers.append(p)
		if pv.has("storage"):
			stores.append(p)
		if float(pv.get("build_boost", 0.0)) > 0.0:
			hubs.append(p)
		if GameData.family(mid) == "rover_depot" or mid == "rover_depot":
			depots.append(p)
		for key in CARE_KEYS:
			var pk := String(CARE_KEYS[key])
			if float(pv.get(pk, 0.0)) > 0.0 and not (key == "leisure" and GameData.family(mid) == "comms_center"):
				(prov[key] as Array).append(p)
	var people := 0.0
	for h in homes:
		people += float(h[1])
	if people <= 0.0:
		return out
	plan._near_edges(Rect2())              # 길 색인을 지금 길 그물로 (nearest_edge가 둘레 칸만 본다)
	# 영향 범위
	var cover := {}
	var morale := 0.0
	var cv: Dictionary = sv.get("cover", {})
	for key in CARE_KEYS:
		var cfg: Dictionary = cv.get(key, {})
		var r2 := pow(float(cfg.get("radius_m", 150.0)), 2.0)
		var near := 0.0
		for h in homes:
			for q: Vector2 in prov[key]:
				if (h[0] as Vector2).distance_squared_to(q) <= r2:
					near += float(h[1])
					break
		var share := near / people
		cover[key] = share
		morale += float(cfg.get("bonus", 0.0)) * share - float(cfg.get("penalty", 0.0)) * (1.0 - share)
	out["cover"] = cover
	# 통근: 일터 무리(가장 가까운 길 꼭짓점마다)에서 거꾸로 다익스트라 — 집마다 무리들까지의 시간을 일손 몫으로 평균
	var cm: Dictionary = sv.get("commute", {})
	var mps := float(cm.get("base_mps", 4.0))
	var walk := float(cm.get("walk_mps", 1.4))
	var groups := {}                       # 꼭짓점 → [일터 자리들, 일손]
	for w in works:
		var k := plan.nearest_edge(w[0], 60.0, true)
		if k < 0:
			continue
		var e: Vector2i = plan.edges[k]
		var at := e.x if (w[0] as Vector2).distance_squared_to(plan.nodes[e.x]) <= (w[0] as Vector2).distance_squared_to(plan.nodes[e.y]) else e.y
		if not groups.has(at):
			groups[at] = [[], 0.0]
		(groups[at][0] as Array).append(w[0])
		groups[at][1] = float(groups[at][1]) + float(w[1])
	var order: Array = groups.keys()
	order.sort_custom(func(x: int, y: int) -> bool: return float(groups[x][1]) > float(groups[y][1]) or (float(groups[x][1]) == float(groups[y][1]) and x < y))
	order = order.slice(0, JOB_K)
	var crew_sum := 0.0
	for g in order:
		crew_sum += float(groups[g][1])
	var trip := PackedFloat32Array()       # 집마다 일손 몫으로 평균한 시간 (초)
	trip.resize(homes.size())
	var reach := PackedFloat32Array()
	reach.resize(homes.size())
	var acc: Array = []                    # 집마다 길에 오르는 곳: [꼭짓점 a, a까지 초, 꼭짓점 b, b까지 초] (한 번만 찾는다)
	for h in homes:
		acc.append(_access(plan, h[0], walk, mps))
	for g in order:
		var best := _reach(plan, groups[g][0], mps, walk)
		var share := float(groups[g][1]) / maxf(crew_sum, 1.0)
		for hi in homes.size():
			var a: Array = acc[hi]
			if a.is_empty():
				continue
			var t := minf(best[int(a[0])] + float(a[1]), best[int(a[2])] + float(a[3]))
			if t < INF:
				trip[hi] += t * share
				reach[hi] += share
	var mins := 0.0
	var counted := 0.0
	for hi in homes.size():
		if reach[hi] <= 0.0:
			continue
		var t := trip[hi] / reach[hi]
		for q: Vector2 in hubs:
			if (homes[hi][0] as Vector2).distance_to(q) <= float(cm.get("hub_m", 150.0)):
				t *= 0.75
				break
		mins += t / 60.0 * float(homes[hi][1])
		counted += float(homes[hi][1])
	var commute := mins / counted if counted > 0.0 else 0.0
	out["commute_min"] = commute
	var work_k := clampf(1.0 + (float(cm.get("typical_min", 4.0)) - commute) / float(cm.get("per_min", 40.0)),
		float(cm.get("lo", 0.88)), float(cm.get("hi", 1.05)))
	# 물류: 저장 시설에서 거꾸로 — 만드는 건물마다 가장 가까운 저장 시설 (거리만, 걷지 않는다)
	var lg: Dictionary = sv.get("freight", {})
	var d_store := _reach(plan, stores, 1.0, 1.0, true)
	var km := 0.0
	var nm := 0
	for p: Vector2 in makers:
		var d := _time_from(plan, d_store, p, 1.0, 1.0, true)
		if d == INF:
			continue
		for q: Vector2 in depots:
			if p.distance_to(q) <= float(lg.get("depot_m", 200.0)):
				d *= 0.8
				break
		km += d / 1000.0
		nm += 1
	var freight := km / nm if nm > 0 else 0.0
	out["freight_km"] = freight
	var make_k := clampf(1.0 + (float(lg.get("typical_km", 0.4)) - freight) * float(lg.get("per_km", 0.1)),
		float(lg.get("lo", 0.9)), float(lg.get("hi", 1.04)))
	out["ext"] = {"morale": snappedf(morale, 0.01), "work_k": snappedf(work_k, 0.001), "make_k": snappedf(make_k, 0.001)}
	return out


## 출발점들(건물 자리)에서 꼭짓점마다 가장 짧은 시간(초 — mps × 길의 속력으로 달린다, 길까지는 walk로 걷는다).
## by_len이면 길이(m)만 (속력을 보지 않는다)
static func _reach(plan: CityPlan, from: Array, mps: float, walk: float, by_len := false) -> PackedFloat32Array:
	var n := plan.nodes.size()
	var best := PackedFloat32Array()
	best.resize(n)
	best.fill(INF)
	if n == 0 or from.is_empty():
		return best
	var heap: Array = []
	for p: Vector2 in from:
		var k := plan.nearest_edge(p, 60.0, true)
		if k < 0:
			continue
		var e: Vector2i = plan.edges[k]
		var q := CityPlan._seg_point(plan.nodes[e.x], plan.nodes[e.y], p)
		var access := p.distance_to(q) / walk
		for end in [e.x, e.y]:
			var t := access + q.distance_to(plan.nodes[end]) / _speed(plan, k, mps, by_len)
			if t < best[end]:
				best[end] = t
				RoadWorks._push(heap, [t, end])
	var adj := plan._adjacency()
	while not heap.is_empty():
		var top: Array = RoadWorks._pop(heap)
		var u := int(top[1])
		if float(top[0]) > best[u]:
			continue
		for pair in adj[u]:
			var v := int(pair[0])
			var nt := best[u] + float(pair[1]) / _speed(plan, int(pair[2]), mps, by_len)
			if nt < best[v]:
				best[v] = nt
				RoadWorks._push(heap, [nt, v])
	return best


static func _speed(plan: CityPlan, k: int, mps: float, by_len: bool) -> float:
	if by_len:
		return 1.0
	return mps * maxf(float(LayoutData.road(plan.edge_type(k)).get("speed", 1.0)), 0.3)


## 자리 p에서 길에 오르는 곳: [꼭짓점 a, 걸어서 길까지 + 길을 따라 a까지 (초), 꼭짓점 b, … b까지] — 길이 없으면 []
static func _access(plan: CityPlan, p: Vector2, walk: float, mps: float) -> Array:
	var k := plan.nearest_edge(p, 60.0, true)
	if k < 0:
		return []
	var e: Vector2i = plan.edges[k]
	var q := CityPlan._seg_point(plan.nodes[e.x], plan.nodes[e.y], p)
	var access := p.distance_to(q) / walk
	var v := _speed(plan, k, mps, false)
	return [e.x, access + q.distance_to(plan.nodes[e.x]) / v, e.y, access + q.distance_to(plan.nodes[e.y]) / v]


## 자리 p에서 가장 가까운 길로 걸어 올라 그 길을 따라 끝까지 가서 그 끝의 시간(best)을 더한다 — 두 끝 가운데 짧은 쪽
static func _time_from(plan: CityPlan, best: PackedFloat32Array, p: Vector2, walk: float, mps: float, by_len := false) -> float:
	var k := plan.nearest_edge(p, 60.0, true)
	if k < 0:
		return INF
	var e: Vector2i = plan.edges[k]
	var q := CityPlan._seg_point(plan.nodes[e.x], plan.nodes[e.y], p)
	var access := p.distance_to(q) / walk
	var t := INF
	for end in [e.x, e.y]:
		if best[end] < INF:
			t = minf(t, best[end] + q.distance_to(plan.nodes[end]) / _speed(plan, k, mps, by_len) + access)
	return t
