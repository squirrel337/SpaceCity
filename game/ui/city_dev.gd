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
##   땅: 사흘마다 — 그 방향의 구획(zones)이 grow_at만큼 차면(다른 구획은 95%) 먼저 가진 땅 안의 빈 블록을 그 구획으로
##       정하고, 빈 블록이 없으면 그 구획 가까이의 땅 구역을 사서 그 구획으로 정한다 (max 구역까지).
##       넓게 퍼지는 방향(sprawl_days)은 도시가 30% 넘게 찼으면 그 날수마다 한 구역씩 더 산다.
##       도시 전체가 shrink_at 아래로 비었으면 30일 넘게 빈 산 구역을 (먼 것부터) 하나 돌려준다 — 돌려주면 그 구획이
##       넓히는 문턱만큼 다시 차는 구역은 남긴다 (사고 돌려주기를 되풀이하지 않게)
##   재건축 (모드와 상관없이 자동 운영 도시 모두): 도시가 커지면(redevelop.min_pop) every_days마다, 계열에서 촘촘한 건물의
##       몫이 정착민에 따른 목표에 못 미치거나 그 구획이 붐비면 땅 넓이당 값이 낮은 건물을 헐고 그 자리에 값이 가장 높은
##       종류(고층 타워 …)를 짓는다 — 한 도시에 한 번에 한 곳 (redevelop)
## 자동 운영을 끄면 아무것도 하지 않는다 (방향은 남아 있다가 다시 켜면 이어진다).

const LAND_EVERY := 3              # 땅을 따지는 간격 (일) — 도시마다 다른 날에
const IDLE_DAYS := 30              # 이만큼 빈 산 구역만 돌려준다
const QUEUE_MAX := 6               # 대기열이 이만큼 길면 방향 건물을 더 넣지 않는다 (살림 공사가 먼저)
const SPRAWL_FILL := 0.3           # 넓게 퍼지는 방향도 도시가 이만큼은 차야 더 산다 (작은 기지가 빈 땅만 늘리지 않게)
const EXTRA_EVERY := 20            # 남는 자재로 목표를 넘어 짓는 간격 (일)
const EXTRA_K := 3.0               # 부품이 reserve의 이만큼 넘게 쌓였을 때만
const REDEV_TRIES := 24            # 재건축 자리를 계열마다 이만큼의 건물에서만 찾는다 (큰 도시의 하루가 길어지지 않게)


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
	var every := int(LayoutData.redevelop().get("every_days", 0))
	if every > 0 and posmod(day + index, every) == 1:
		redevelop(c)


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
	if best != "":
		# 구획 넓히기: 가진 땅 안의 빈 블록부터 (땅을 사지 않는다), 없으면 땅 구역을 산다
		if plan.zone_free_block(best):
			sim.note("%s — 빈 블록을 %s 구획으로 정했다" % [why, LayoutData.zone_name(best)], "info")
			return false
		if plan.land.size() < int(ld.get("max", 8)) and plan.expand_zone(best, sim, reserve, why):
			c["bought"] = day
			return false
	if plan.land.size() < int(ld.get("max", 8)):
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


## 재건축 — 도시가 자라면 계열마다 촘촘한 건물의 몫을 늘린다: 그 계열에서 지을 수 있는 가장 촘촘한 종류(땅 넓이당 값 metric이
## 가장 높은 것)를 to로 두고, 촘촘한 종류가 계열 값에서 차지하는 몫이 정착민에 따른 목표(share_per_100, max_share까지)에 못 미치거나
## 그 계열의 구획이 붐비면(pressure) to의 1/gain보다 성긴 건물 하나를 헐고 그 자리에 to를 짓는다. 모드의 구획이면 먼저.
## 새 건물이 넓으면 자리를 밀어 보고, 겹치는 이웃이 같은 계열의 성긴 건물이면 둘까지 함께 헌다. 헐면 정착민이 다 살 수 없는 거주,
## 연구할 사람이 남지 않는 연구동은 두고, 들어가지 않으면 다른 건물을 본다 (계열마다 오래된 것부터 REDEV_TRIES곳까지).
## 한 도시에 한 번에 한 곳 (공사가 끝나야 다음). 시작했으면 true
static func redevelop(c: Dictionary) -> bool:
	var rd := LayoutData.redevelop()
	var sim: CitySim = c["sim"]
	var plan: CityPlan = c["plan"]
	var pop := sim.population()
	var min_pop := float(rd.get("min_pop", 120))
	if rd.is_empty() or pop < min_pop:
		return false
	var busy := int(c.get("redev", -1))
	if busy >= 0:
		for item in sim.queue:
			if int(item["seq"]) == busy:
				return false
		c["redev"] = -1
	var m := LayoutData.dev_mode(String(c.get("mode", "")))
	var reserve := float(m.get("reserve", {}).get("parts", 60.0))
	var zones: Array = m.get("zones", [])
	var use := plan.zone_use(sim)
	var fams: Dictionary = rd.get("families", {})
	var gain := float(rd.get("gain", 1.5))
	var want_share := minf(float(rd.get("max_share", 0.85)), (pop - min_pop) / 100.0 * float(rd.get("share_per_100", 0.08)))
	var cands: Array = []                 # [이득, 헐 종류, 지을 종류, 함께 헐 수 있는 종류]
	for fam in fams:
		var metric := String(fams[fam])
		if metric == "crew" and sim.fam_spec(fam, "crew") >= pop * float(sim.C["workforce_share"]) * 0.3:
			continue                      # 연구할 사람이 남지 않는다 — 자리를 늘려도 쓸모가 없다
		var district: String = plan.layout.district_of.get(fam, "")
		var u: Array = use.get(district, [0.0, 0.0])
		var crowded := float(u[1]) > 0.0 and float(u[0]) / float(u[1]) >= float(rd.get("pressure", 0.85))
		var to := ""
		var to_d := 0.0
		for mid in GameData.FAMILY[fam]:
			var dd := density(mid, metric)
			if dd > to_d and sim.build_block_reason(mid, reserve) == "":
				to_d = dd
				to = mid
		if to == "":
			continue
		var low := {}
		var dense := 0.0
		var total := 0.0
		for mid in GameData.FAMILY[fam]:
			var n := int(sim.counts.get(mid, 0))
			var dm := density(mid, metric)
			var val := n * value(mid, metric)
			total += val
			if dm > 0.0 and to_d >= dm * gain:
				if n > 0 and mid != to:
					low[mid] = dm
			else:
				dense += val
		if low.is_empty() or (not crowded and (total <= 0.0 or dense / total >= want_share)):
			continue                      # 촘촘한 몫이 목표만큼 됐고 구획도 붐비지 않는다
		for mid in low:
			cands.append([to_d / float(low[mid]) * (1.5 if district in zones else 1.0) * (2.0 if crowded else 1.0), mid, to, low])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var refund := float(rd.get("refund", 0.3))
	for cand in cands:
		var from := String(cand[1])
		var to := String(cand[2])
		var tries := 0
		for e in plan.buildings:          # 오래된 것부터 (놓은 차례)
			if String(e["id"]) != from or int(e["seq"]) >= 0:
				continue
			tries += 1
			if tries > REDEV_TRIES:
				break
			var spot := plan.rebuild_spot(int(e["uid"]), to, cand[3])
			if spot.is_empty():
				continue
			var gone: Array = [from]
			for u in spot["also"]:
				gone.append(plan.kind_of_uid(int(u)))
			var lost := 0.0
			for g in gone:
				lost += float(sim.prov(String(g), "housing"))
			if lost > 0.0 and sim.housing_cap - lost < pop:
				continue                  # 헐면 정착민이 다 살 수 없다
			if not sim.enqueue(to, "", reserve):
				return false
			for g in gone:
				sim.demolish(String(g), refund)
			plan.rebuild(int(e["uid"]), to, sim.seq, spot)
			var names := GameData.module_name(from) + (" 등 %d채" % gone.size() if gone.size() > 1 else "")
			c["redev"] = sim.seq
			c["redev_txt"] = "%s → %s" % [names, GameData.module_name(to)]
			sim.note("재건축 — %s을(를) 헐고 그 자리에 %s을(를) 짓는다" % [names, GameData.module_name(to)], "build")
			return true
	return false


## 건물 하나의 값: metric이 crew면 인원, 아니면 provides의 그 값
static func value(mid: String, metric: String) -> float:
	var m: Dictionary = GameData.MODULES[mid]
	return float(m.get("crew", 0)) if metric == "crew" else float(m.get("provides", {}).get(metric, 0.0))


## 땅 넓이당 값: value / 바닥 넓이 (m²)
static func density(mid: String, metric: String) -> float:
	var f := ArtLib.footprint(mid)
	return value(mid, metric) / maxf(f.x * f.y, 1.0)


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
	var redev := ""
	var busy := int(c.get("redev", -1))
	for item in sim.queue:
		if busy >= 0 and int(item["seq"]) == busy:
			var p := clampf(1.0 - float(item["rd"]) / maxf(1e-6, float(item["rd_total"])), 0.0, 1.0)
			redev = "%s (%s)" % [String(c.get("redev_txt", "")), "철거 중" if p < BaseScene.DEMOLISH else "공정 " + Fmt.pct(p)]
	return {"rows": rows, "land": plan.land.size(), "max": int(m.get("land", {}).get("max", 8)), "fill": _fill(use), "use": use,
		"redev": redev}
