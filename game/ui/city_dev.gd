class_name CityDev
extends RefCounted
## 도시 발전 모드 — 자동 운영 식민지가 무엇을 더 짓고, 무엇을 먼저 연구하고, 땅을 얼마나 넓히거나 줄일지
## (자료: data/city_layout.json의 dev_modes — '' 균형과 열 가지 방향). 시뮬레이션 밖의 규칙이다: 시드의 추천 운영(AutoPolicy)이
## 살림을 꾸리고, 발전 모드는 그 도시의 하루가 끝날 때마다 그 위에 얹힌다 —
##   건물: wants의 목표 수(기본 + 정착민 100명마다 더)에 못 미친 첫 건물을 하루 하나 대기열에 넣는다
##         (연구가 됐고, 대기열이 짧고, 넣어도 부품이 reserve만큼 남을 때). 목표를 다 채웠고 부품이 reserve의 3배 넘게
##         쌓였으면 20일마다 그 모드 구획(zones)의 건물을 하나 더 짓는다 (목표의 두 배 + 1까지, 쓸모가 있을 때만 —
##         집이 이미 넉넉하면 거주는, 연구원이 모자라면 연구동은 짓지 않는다). 정착민이 적은 도시도 남는 자재로 방향대로 자라고,
##         그 구획이 차면 땅이 넓어진다
##   연구: research의 기술을 연구 차례의 둘째 자리로 당긴다 (추천 운영이 고른 맨 앞 기술은 먼저 끝낸다 — 살림 연구와 번갈아)
##   땅: 사흘마다 — 그 방향의 구획(zones)이 grow_at만큼 차면(다른 구획은 95%) 그 구획 가까이의 땅 구역을 사서 그 구획으로
##       정한다 (max 구역까지). 넓게 퍼지는 방향(sprawl_days)은 도시가 30% 넘게 찼으면 그 날수마다 한 구역씩 더 산다.
##       도시 전체가 shrink_at 아래로 비었으면 30일 넘게 빈 산 구역을 (먼 것부터) 하나 돌려준다 — 돌려주면 그 구획이
##       넓히는 문턱만큼 다시 차는 구역은 남긴다 (사고 돌려주기를 되풀이하지 않게)
## 자동 운영을 끄면 아무것도 하지 않는다 (방향은 남아 있다가 다시 켜면 이어진다).

const LAND_EVERY := 3              # 땅을 따지는 간격 (일) — 도시마다 다른 날에
const IDLE_DAYS := 30              # 이만큼 빈 산 구역만 돌려준다
const QUEUE_MAX := 6               # 대기열이 이만큼 길면 방향 건물을 더 넣지 않는다 (살림 공사가 먼저)
const SPRAWL_FILL := 0.3           # 넓게 퍼지는 방향도 도시가 이만큼은 차야 더 산다 (작은 기지가 빈 땅만 늘리지 않게)
const EXTRA_EVERY := 20            # 남는 자재로 목표를 넘어 짓는 간격 (일)
const EXTRA_K := 3.0               # 부품이 reserve의 이만큼 넘게 쌓였을 때만


static func mode_name(id: String) -> String:
	return String(LayoutData.dev_mode(id).get("name", "균형"))


static func mode_color(id: String) -> Color:
	return Color(String(LayoutData.dev_mode(id).get("color", "aab3c8")))


## 도시의 하루가 끝난 뒤 (Colonies.step). index: 목록 순서 — 땅을 따지는 날을 도시마다 엇갈린다
static func step_day(c: Dictionary, index: int) -> void:
	var sim: CitySim = c["sim"]
	if sim.autopilot == null:
		return
	var id := String(c.get("mode", ""))
	var m := LayoutData.dev_mode(id)
	_research(sim, m)
	_build(c, sim, m, id)
	var day := sim.current_day()
	if posmod(day + index, LAND_EVERY) == 0:
		land_step(c, day)


static func _research(sim: CitySim, m: Dictionary) -> void:
	var want: Array = m.get("research", [])
	var q := sim.research_queue
	for i in range(want.size() - 1, -1, -1):
		var t := String(want[i])
		if sim.techs.has(t) or not GameData.TECHS.has(t):
			continue
		var at := q.find(t)
		if at == 0 or at == 1:
			continue
		if at > 0:
			q.remove_at(at)
		q.insert(mini(1, q.size()), t)


## 방향 건물의 목표 수: 기본 + 정착민 100명마다 더
static func target(w: Array, pop: float) -> int:
	return int(w[1]) + int(floor(pop * float(w[2]) / 100.0))


static func _build(c: Dictionary, sim: CitySim, m: Dictionary, id: String) -> void:
	var wants: Array = m.get("wants", [])
	if wants.is_empty() or sim.queue.size() >= QUEUE_MAX:
		return
	var pop := sim.population()
	var reserve := float(m.get("reserve", {}).get("parts", 60.0))
	for w in wants:
		var mid := String(w[0])
		if not GameData.MODULES.has(mid) or sim.planned(mid) >= target(w, pop):
			continue
		var tile := ""
		if sim.family(mid) == "solar_tower":
			tile = sim.free_tile()
			if tile == "":
				continue
		if sim.build_block_reason(mid, reserve) != "":
			continue                  # 연구가 안 됐거나 자재가 모자라다 — 다음 건물
		if sim.enqueue(mid, tile, reserve):
			sim.note("발전 모드(%s) — %s 착공" % [mode_name(id), GameData.module_name(mid)], "build")
		return
	_extra(c, sim, m, id, reserve)


## 목표를 다 채웠고 부품이 넉넉하면: EXTRA_EVERY일마다 그 모드 구획의 건물 중 목표에 견줘 가장 적은 것을 하나 더
static func _extra(c: Dictionary, sim: CitySim, m: Dictionary, id: String, reserve: float) -> void:
	var day := sim.current_day()
	if float(sim.stock["parts"]) < reserve * EXTRA_K or day - int(c.get("extra", -100000)) < EXTRA_EVERY:
		return
	var plan: CityPlan = c["plan"]
	var zones: Array = m.get("zones", [])
	var pop := sim.population()
	var best := ""
	var best_r := INF
	for w in m.get("wants", []):
		var mid := String(w[0])
		if not GameData.MODULES.has(mid) or sim.family(mid) == "solar_tower":
			continue
		if not zones.is_empty() and not String(plan.layout.district_of.get(sim.family(mid), "")) in zones:
			continue                  # 그 모드가 넓히는 구획의 건물만
		var goal := target(w, pop)
		if sim.planned(mid) >= goal * 2 + 1 or not _useful(sim, mid) or sim.build_block_reason(mid, reserve) != "":
			continue
		var r := float(sim.planned(mid)) / maxf(float(goal), 1.0)
		if r < best_r:
			best_r = r
			best = mid
	if best != "" and sim.enqueue(best, "", reserve):
		c["extra"] = day
		sim.note("발전 모드(%s) — 남는 자재로 %s 착공" % [mode_name(id), GameData.module_name(best)], "build")


## 더 지어도 쓸모가 있나: 집이 이미 넉넉하면(정착민의 두 배 + 다음 유인선) 거주는, 연구원이 모자라면 연구동은 그만
static func _useful(sim: CitySim, mid: String) -> bool:
	var pop := sim.population()
	if float(sim.prov(mid, "housing")) > 0.0 and sim.housing_cap >= pop * 2.0 + float(sim.C["earth"]["crewed_seats"]):
		return false
	if sim.family(mid) == "research_lab" and sim.fam_spec("research_lab", "crew") >= pop * float(sim.C["workforce_share"]) * 0.3:
		return false
	return true


## 땅 넓히기·줄이기 (사흘마다). 돌려준 산 구역이 있으면 true
static func land_step(c: Dictionary, day: int) -> bool:
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var id := String(c.get("mode", ""))
	var m := LayoutData.dev_mode(id)
	var ld: Dictionary = m.get("land", {})
	var reserve: Dictionary = m.get("reserve", LayoutData.land()["auto_reserve"])
	var why := "발전 모드(%s)" % mode_name(id)
	var use := plan.zone_use(sim)
	var zones: Array = m.get("zones", [])
	var grow_at := float(ld.get("grow_at", 0.8))
	if plan.land.size() < int(ld.get("max", 8)):
		var best := ""
		var best_over := -1.0
		for d in use:
			var u: Array = use[d]
			if float(u[0]) <= 0.0:
				continue
			var fill := float(u[0]) / maxf(float(u[1]), 1.0)
			var at := grow_at if (zones.is_empty() or d in zones) else maxf(grow_at, 0.95)
			if fill >= at and fill - at > best_over:
				best_over = fill - at
				best = d
		if best != "" and plan.expand_zone(best, sim, reserve, why):
			c["bought"] = day
			return false
		# 넓게 퍼지는 방향: 도시가 어느 만큼 찼으면 그 날수마다 그 방향의 첫 구획을 한 구역씩
		var sprawl := int(ld.get("sprawl_days", 0))
		if sprawl > 0 and not zones.is_empty() and day - int(c.get("bought", -100000)) >= sprawl and _fill(use) >= SPRAWL_FILL:
			if plan.expand_zone(String(zones[0]), sim, reserve, why):
				c["bought"] = day
				return false
	# 줄이기: 30일 넘게 빈 산 구역을 적고, 도시 전체가 많이 비었으면 먼 것부터 하나 돌려준다
	var idle: Dictionary = c.get("idle", {})
	var keep := {}
	for k in plan.land:
		var key := "%d,%d" % [(k as Vector2i).x, (k as Vector2i).y]
		if plan.parcel_empty(k):
			keep[key] = int(idle.get(key, day))
	c["idle"] = keep
	var shrink_at := float(ld.get("shrink_at", 0.0))
	if shrink_at <= 0.0 or keep.is_empty() or _fill(use) >= shrink_at:
		return false
	var far := Vector2i.ZERO
	var far_d := -1.0
	for key in keep:
		if day - int(keep[key]) < IDLE_DAYS:
			continue
		var xy := String(key).split(",")
		var cell := Vector2i(int(xy[0]), int(xy[1]))
		var dd := plan.parcel_rect(cell).get_center().distance_to(plan.hub())
		if dd > far_d and plan.can_release(cell) and not _regrows(plan, cell, use, zones, grow_at):
			far_d = dd
			far = cell
	if far_d < 0.0:
		return false
	if plan.release_parcel(far, sim, why):
		keep.erase("%d,%d" % [far.x, far.y])
		return true
	return false


## 그 구역을 돌려주면 그 안 블록의 구획이 넓히는 문턱만큼 차는가 — 그러면 사흘 뒤 다시 산다 (값의 절반을 잃는 되풀이). 돌려주지 않는다
static func _regrows(plan: CityPlan, cell: Vector2i, use: Dictionary, zones: Array, grow_at: float) -> bool:
	var r := plan.parcel_rect(cell)
	var lost := {}
	for b in plan.blocks():
		var d := String(b["district"])
		if d != "" and use.has(d) and r.has_point(b["center"]):
			lost[d] = float(lost.get(d, 0.0)) + float(b["area"]) * 0.7
	for d in lost:
		var u: Array = use[d]
		var at := grow_at if (zones.is_empty() or d in zones) else maxf(grow_at, 0.95)
		if float(u[0]) > 0.0 and float(u[0]) / maxf(float(u[1]) - float(lost[d]), 1.0) >= at:
			return true
	return false


## 도시 전체가 찬 정도 (구획 블록 땅에 대한 건물 땅)
static func _fill(use: Dictionary) -> float:
	var need := 0.0
	var have := 0.0
	for d in use:
		need += float(use[d][0])
		have += float(use[d][1])
	return need / have if have > 0.0 else 0.0


## 방향의 지금 모습 (개척 탭): 건물 목표, 땅
static func status(c: Dictionary) -> Dictionary:
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var m := LayoutData.dev_mode(String(c.get("mode", "")))
	var pop := sim.population()
	var rows: Array = []
	for w in m.get("wants", []):
		var mid := String(w[0])
		if GameData.MODULES.has(mid):
			rows.append([mid, int(sim.counts.get(mid, 0)), sim.queued(mid), target(w, pop)])
	var use := plan.zone_use(sim)
	return {"rows": rows, "land": plan.land.size(), "max": int(m.get("land", {}).get("max", 8)), "fill": _fill(use), "use": use}
