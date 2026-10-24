extends SceneTree
## 화면이 실제로 도는지 확인하는 연기 시험 — 메인 씬을 띄우고, 자동 운영으로 60일을 돌리고,
## 탭을 모두 열어 보고, 저장·불러오기를 왕복한 뒤 3년 보고서까지 간다. 끝으로 화성에 원정대를 보내
## 두 번째 식민지를 세우고 고르고 저장을 왕복한다. 오류가 하나라도 나면 실패한다.
##   godot --headless --path game --script res://tests/smoke_test.gd

var main: Control
var frames := 0
var failures: Array[String] = []
var report_seen := false


func _initialize() -> void:
	var scene: PackedScene = load("res://ui/main.tscn")
	main = scene.instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		main._on_modal_choice("start", "auto")
		_check(main.sim != null, "새 게임이 만들어지지 않았다")
	elif frames > 2 and frames < 400:
		if main.modal.visible:
			if main.modal.context == "storm":
				main._on_modal_choice("storm", "lottery")
			elif main.modal.context == "death":
				main._on_modal_choice("death", "ok")
			else:
				main.modal.visible = false
		for _i in range(4):
			main._step()
		main._refresh_live()
		if frames % 40 == 0:
			main._select_tab(["life", "power", "build", "research", "colony", "transport", "log"][(frames / 40) % 7])
	elif frames == 400:
		_check(main.sim.current_day() >= 60, "60일을 돌지 못했다 (%d일)" % main.sim.current_day())
		_check(main.sim.population() > 0, "정착민이 모두 사라졌다")
		var built: int = main.sim.stats.get("built", 0)
		_check(built > 0, "자동 운영이 아무것도 짓지 않았다")
		_save_roundtrip()
		_stall_check()
		_map_check()
		_world_check()
		_plan_check()
		_types_check()
		_devmodes_check()
		_redevelop_check()
		_roadworks_check()
		_runway_check()
		_raised_check()
		_speed_check()
		main._on_module_tapped("hab_module")
		main._show_help()
		main._show_report()
		print("smoke: day %d, pop %d, built %d, notes %d" % [main.sim.current_day(), int(main.sim.population()), built, main.sim.notes.size()])
		main.modal.visible = false
	elif frames > 400:
		# 2단계: 자동 운영으로 3년 보고서까지 간다
		for _i in range(24 * 15):
			if main.modal.visible:
				if main.modal.context == "report":
					report_seen = true
				if main.modal.context == "storm":
					main.modal.visible = false
					main._on_modal_choice("storm", "lottery")
				else:
					main.modal.visible = false
			main._step()
		if main.sim.current_day() >= 1100 or frames > 1200:
			_check(report_seen or main.modal.context == "report", "3년 보고서가 뜨지 않았다")
			var s: Dictionary = main.sim.summary()
			print("smoke: 3y pop %d, trust %.1f, deaths %d, techs %d" % [int(s["population_end"]), s["trust_end"], int(s["deaths"]), s["techs"]])
			main.modal.visible = false
			_colony_check()
			if failures.is_empty():
				print("smoke: OK")
				quit(0)
			else:
				for f in failures:
					printerr("smoke: FAIL — " + f)
				quit(1)
	return false


func _save_roundtrip() -> void:
	var before: Dictionary = main.sim.to_save()
	var text := JSON.stringify(before, "", false, true)
	var restored := CitySim.from_save(JSON.parse_string(text))
	_check(restored.hour == main.sim.hour, "불러온 시각이 다르다")
	_check(absf(restored.population() - main.sim.population()) < 1e-9, "불러온 인구가 다르다")
	# 같은 상태에서 같은 결정이면 같은 결과가 나와야 한다 (같은 저장에서 두 번 되살려 나란히 돌린다)
	var twin := CitySim.from_save(JSON.parse_string(text))
	for _i in range(24 * 10):
		restored.advance_hour()
		twin.advance_hour()
	_check(absf(restored.stock["o2_kg"] - twin.stock["o2_kg"]) < 1e-9, "불러온 뒤 10일의 결과가 다르다")
	_check(restored.rng.random() == twin.rng.random(), "난수 상태가 이어지지 않았다")


## 멈춤 없애기 (1단계): 자리 찾기 색인은 다 훑을 때와 같은 답, 프레임 예산으로 나눠 맞춘 배치는 한 번에 맞춘 것과 같다
## (따라잡는 동안 이따금 놓은 데까지 알린다),
## 일별 기록을 작게 싼 저장이 되돌아온다, 날마다의 탭 새로 고침은 목록을 다시 만들지 않는다
func _stall_check() -> void:
	var sim: CitySim = main.sim
	var plan: CityPlan = main.plan
	plan.sync(sim)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var kinds := ["hab_module", "landing_pad", "fission_40kw", "greenhouse", "research_lab"]
	var diff := 0
	for _i in 600:
		var kind: String = kinds[rng.randi() % kinds.size()]
		var at := Vector2(rng.randf_range(-220, 220), rng.randf_range(-220, 220)).snapped(Vector2.ONE)
		var rot := rng.randi() % 2
		var got := plan.check_spot(kind, at, rot)
		var want := _scan_conflict(plan, kind, at, rot)
		var conflict := got.contains("겹친다") or got.contains("착륙") or got.contains("원자로") or got == "길 위에는 지을 수 없다"
		if (conflict and got != want) or (got == "" and want != ""):
			diff += 1
	_check(diff == 0, "자리 찾기 색인이 다 훑을 때와 다른 답을 냈다 (%d곳)" % diff)
	_index_check(plan, rng)
	# 배치 따라잡기: 저장에서 맞추지 않고 읽은 뒤 프레임 예산으로 나눠 맞춘다 — 한 번에 맞춘 것과 같은 자리
	var data: Dictionary = JSON.parse_string(JSON.stringify(plan.to_save()))
	for i in range(data["buildings"].size() - 1, -1, -1):
		if i % 3 == 0:
			data["buildings"].remove_at(i)                 # 오래 안 본 도시처럼 건물 셋에 하나를 뺀다
	var full := CityPlan.from_save(data, sim, plan.layout)
	var lazy := CityPlan.from_save(JSON.parse_string(JSON.stringify(data)), sim, plan.layout, false)
	var frames := 0
	var rev0 := lazy.revision
	while lazy._sig == "" and frames < 500:
		lazy._sync_frame = -1
		lazy.sync(sim, CityPlan.SYNC_FRAME_US)
		frames += 1
	var same := lazy.buildings.size() == full.buildings.size()
	for i in mini(lazy.buildings.size(), full.buildings.size()):
		var a: Dictionary = lazy.buildings[i]
		var b: Dictionary = full.buildings[i]
		same = same and a["id"] == b["id"] and is_equal_approx(float(a["x"]), float(b["x"])) \
			and is_equal_approx(float(a["y"]), float(b["y"])) and int(a["rot"]) == int(b["rot"])
	_check(same and lazy.revision > rev0, "나눠 맞춘 배치가 한 번에 맞춘 것과 다르다 (%d프레임, 건물 %d/%d)" % [frames,
		lazy.buildings.size(), full.buildings.size()])
	# 저장: 일별 기록을 열과 정수로
	var back := CitySim.from_save(JSON.parse_string(JSON.stringify(sim.to_save(), "", false, true)))
	var ok := back.daily.size() == sim.daily.size() and not sim.daily.is_empty()
	if ok:
		var a2: Dictionary = sim.daily[-1]
		var b2: Dictionary = back.daily[-1]
		for k in a2:
			ok = ok and absf(float(a2[k]) - float(b2[k])) <= 0.0006 + absf(float(a2[k])) * 1e-9
	_check(ok, "일별 기록이 저장에서 되돌아오지 않았다")
	# 탭: 날마다의 새로 고침은 목록을 다시 만들지 않는다 (같은 줄)
	main._select_tab("build")
	var bp: BuildPanel = main.tabs["build"]
	var first: Control = bp.catalog.get_child(0)
	bp.refresh()
	_check(bp.catalog.get_child(0) == first, "건설 탭이 날마다 목록을 다시 만든다")
	main._select_tab("life")
	print("smoke: stalls — 색인 600곳 같은 답, 배치 따라잡기 %d프레임, 일별 기록 %d줄 되돌림" % [frames, back.daily.size()])


## 건물이 많을 때의 지름길 (불러오기·도시 바꾸기): 자리 찾기 커서는 처음부터 찾은 것과 같은 자리, 가까운 길·깔릴 길의
## 건물 검사·구역의 빈 땅은 색인 없이 다 훑은 것과 같은 답
func _index_check(plan: CityPlan, rng: RandomNumberGenerator) -> void:
	var same_seek := true
	for kind in ["hab_module", "research_lab", "battery_bank", "parts_fab", "hydroponics", "radiator"]:
		var warm := plan.suggest(kind)
		plan._seek.clear()
		same_seek = same_seek and str(warm) == str(plan.suggest(kind))
	_check(same_seek, "자리 찾기 커서가 처음부터 찾은 것과 다른 자리를 냈다")
	var e_diff := 0
	var r_diff := 0
	var hw := LayoutData.road_half("street")
	plan._near_edges(Rect2())
	for _i in 300:
		var q := Vector2(rng.randf_range(-260, 260), rng.randf_range(-260, 260))
		var md := rng.randf_range(0.5, 12.0)
		var want_k := -1
		var best := md
		for k in plan.edges.size():
			var dd := CityPlan._seg_point(plan.nodes[plan.edges[k].x], plan.nodes[plan.edges[k].y], q).distance_to(q)
			if dd < best:
				best = dd
				want_k = k
		if plan.nearest_edge(q, md) != want_k:
			e_diff += 1
		var b := q + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var want_r := ""
		for e in plan.buildings:
			if CityPlan._seg_rect_dist(q, b, plan.entry_rect(e).grow(-0.3)) < hw:
				want_r = "건물"
				break
		if want_r == "" and plan.flooded_along(q, b, hw):
			want_r = "물"
		if plan.road_check_shape(q, b, "street") != want_r:
			r_diff += 1
	var p_diff := 0
	for k in plan.land:
		var r := plan.parcel_rect(k).grow(-0.5)
		var want_e := true
		for e in plan.buildings:
			var er := plan.entry_rect(e)
			if er.intersects(r):
				for c in [er.position, Vector2(er.end.x, er.position.y), er.end, Vector2(er.position.x, er.end.y)]:
					want_e = want_e and plan.layout.base_has(c)
		if plan.parcel_empty(k) != want_e:
			p_diff += 1
	_check(e_diff == 0 and r_diff == 0 and p_diff == 0, "색인이 다 훑을 때와 다른 답을 냈다 (가까운 길 %d, 깔릴 길 %d, 빈 구역 %d)" % [
		e_diff, r_diff, p_diff])


## 옛 check_spot의 건물·길 부분 (다 훑는다) — 색인과 견준다
func _scan_conflict(plan: CityPlan, kind: String, at: Vector2, rot: int) -> String:
	var r := CityPlan.rect_of(kind, at, rot)
	var kfam := CityPlan.fam(kind)
	var inner := r.grow(-0.05)
	for e in plan.buildings:
		var er := plan.entry_rect(e)
		if inner.intersects(er):
			return "다른 건물(%s)과 겹친다" % GameData.module_name(String(e["id"]))
		var other: String = e["id"]
		var ofam := CityPlan.fam(other)
		if kfam == "landing_pad" and ofam != "landing_pad" and CityPlan._rect_dist(r, er) < CityPlan.clearance(kind):
			return "착륙장 둘레 %d m 안에 건물이 있다 (착륙 분사)" % int(CityPlan.clearance(kind))
		if ofam == "landing_pad" and kfam != "landing_pad" and CityPlan._rect_dist(r, er) < CityPlan.clearance(other):
			return "착륙장에서 %d m 넘게 떨어져야 한다 (착륙 분사)" % int(CityPlan.clearance(other))
		if kfam in CityPlan.REACTORS and CityPlan._people(other) and CityPlan._rect_dist(r, er) < CityPlan.clearance(kind):
			return "이 원자로는 사람이 머무는 건물에서 %d m 넘게 떨어져야 한다" % int(CityPlan.clearance(kind))
		if ofam in CityPlan.REACTORS and CityPlan._people(kind) and CityPlan._rect_dist(r, er) < CityPlan.clearance(other):
			return "원자로(%s)에서 %d m 넘게 떨어져야 한다" % [GameData.module_name(other), int(CityPlan.clearance(other))]
	for k in plan.edges.size():
		var ed: Vector2i = plan.edges[k]
		if CityPlan._seg_rect_dist(plan.nodes[ed.x], plan.nodes[ed.y], r) < plan.edge_half(k) - 0.05:
			return "길 위에는 지을 수 없다"
	return ""


func _map_check() -> void:
	## 기지 배치·교통: 건물 자리, 공사 현장으로 가는 로봇, 착륙선 사건, 3D·목록 전환
	var layout: BaseLayout = main.plan.layout
	_check(layout.capacity("hab_module") >= 30, "거주 모듈 자리가 모자란다")
	_check(layout.capacity("solar_tower") == 38, "태양광 타워 자리가 능선 칸(8+10+20)과 다르다")
	_check(main.sim.M.size() == 174 and GameData.FAMILY.size() == 34, "건물이 34계열 174종이 아니다")
	for kind in main.sim.M:
		if GameData.family(kind) == kind:
			_check(layout.capacity(kind) > 0, "기본 자리가 없는 계열: " + kind)
		_check(ArtLib.variants(kind) == 5, "모양이 5가지가 아닌 건물: " + kind)
	_check(ModelLib.variants("hab_module_covered") == 5, "피복 거주 모듈 모형이 다섯 가지가 아니다")
	var seen := {}
	for i in range(5):
		seen[BaseScene.variant_of("hab_module", i)] = true
	_check(seen.size() == 5, "이웃한 자리 다섯 곳의 모양이 겹친다")
	main.sim.enqueue("medical_bay", "", 0.0)
	main.plan.sync(main.sim)
	if main.sim.robots - main.sim.robots_broken <= 0:
		main.sim.robots_broken = 0          # 시험의 전제: 일하는 로봇이 한 대는 있다 (고장은 운에 달렸다)
	var sites := BaseScene.sites(main.sim, main.plan)
	_check(not sites.is_empty(), "공사 현장이 없다")
	var traffic: BaseTraffic = main.world.city.traffic
	var working := 0
	for _i in range(6000):               # 공사 현장까지 길로 걸어간다 (최대 10분)
		traffic.update(0.1, main.sim, sites)
		if _i % 100 == 99:
			working = traffic.agents.filter(func(a): return a["role"] == "robot" and a["state"] == "work").size()
			if working > 0:
				break
	for a in traffic.agents:
		_check(ModelLib.has("vehicles", a["id"]), "3D 모형이 없는 탈것: " + a["id"])
	_check(working > 0, "로봇이 공사 현장에 가지 않았다")
	var before := int(main.sim.stats.get("arrived", 0))
	main.sim.stats["arrived"] = before + 1
	traffic.update(0.1, main.sim, sites)
	_check(traffic.agents.any(func(a): return a["role"] == "lander"), "유인 착륙선이 나타나지 않았다")
	for _i in range(200):
		traffic.update(0.1, main.sim, sites)
	_check(not traffic.agents.any(func(a): return a["role"] == "lander"), "착륙선이 떠나지 않았다")
	main.sim.stats["arrived"] = before
	traffic.reset(main.sim)
	var w: WorldView = main.world
	main._set_view("list")
	_check(main.city_view.visible and not w.visible, "목록으로 바뀌지 않았다")
	main._set_view("world")
	_check(w.visible and main.view_buttons.size() == 2, "보기가 3D·목록 둘이 아니다")
	print("smoke: base %d robots working, %d agents" % [working, traffic.agents.size()])


func _world_check() -> void:
	## 3D 우주 보기: 모형, 천체 위치, 구글 어스식 조작(끌기·휠·날기), 축척 공간, 3D 도시
	var w: WorldView = main.world
	main._set_view("world")
	_check(w.visible, "3D 보기로 바뀌지 않았다")
	for kind in main.sim.M:
		_check(ModelLib.variants(kind) == 5, "3D 모형 변형이 5가지가 아닌 건물: " + kind)
		for v in range(5):
			var mesh := ModelLib.mesh("buildings", kind, v)
			_check(mesh.get_surface_count() > 0 and mesh.get_aabb().size.length() > 1.0, "빈 3D 모형: %s v%d" % [kind, v])
	for vid in ["ltv", "pressurized_rover", "cargo_hauler", "hopper", "excavator_robot", "builder_robot", "astronaut",
			"crew_lander", "cargo_lander"]:
		_check(ModelLib.mesh("vehicles", vid).get_surface_count() > 0, "빈 탈것 모형: " + vid)
	# 천체 위치
	var jd := w.jd
	var earth := Astro.position("earth", jd)
	var r_au := Astro.len3(earth) / Astro.AU
	_check(r_au > 0.98 and r_au < 1.02, "지구-태양 거리가 이상하다: %.3f AU" % r_au)
	var md := Astro.len3(Astro.moon_geo(jd))
	_check(md > 355000.0 and md < 408000.0, "지구-달 거리가 이상하다: %d km" % int(md))
	_check(Astro.systems.size() >= 30, "이웃 항성계가 모자란다")
	# 기지 위 → 휠로 축소 → 달 전체 → 지구-달 → 태양계 → 별
	var cam := w.cam
	w.home(false)
	w._process(0.016)
	_check(cam.mode == "body" and cam.focus == "moon", "처음 시점이 달 표면이 아니다")
	_check(absf(w.moon.local_height_m(Vector2.ZERO)) < 0.01, "기지 평지 높이가 0이 아니다")
	var d0 := cam.dist
	var t0 := cam.t_dir.duplicate()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = w.size * 0.5
	w._gui_input(ev)
	var mv := InputEventMouseMotion.new()
	mv.position = w.size * 0.5 + Vector2(120, 40)
	mv.relative = Vector2(120, 40)
	w._gui_input(mv)
	ev.pressed = false
	w._gui_input(ev)
	w._process(0.016)
	_check(Astro.len3(Astro.sub3(cam.t_dir, t0)) > 1e-9, "끌어도 목표가 움직이지 않았다")
	for _i in range(12):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = w.size * 0.5
		w._gui_input(wheel)
	w._process(0.016)
	_check(cam.dist > d0 * 5.0, "휠로 멀어지지 않았다")
	cam.zoom(1.0e4)
	w._process(0.016)
	_check(cam.mode == "space", "멀리서도 지구본 모드다")
	# 고정점: 기본은 고른 천체에 머물고, '멀어지면 상위 천체로'를 켜면 태양계 거리에서 목표가 태양으로 옮겨 간다
	cam.dist = 3.0e9
	w._process(0.016)
	var focus_gap := Astro.len3(Astro.sub3(cam.target, w._info(cam.focus)["center"]))
	_check(cam.lock and focus_gap < 1.0, "고정점이 멀어져도 고른 천체에 머물지 않는다")
	cam.lock = false
	w._process(0.016)
	var sun_gap := Astro.len3(Astro.sub3(cam.target, w._info("sun")["center"]))
	_check(sun_gap < 1.0e8, "태양계 거리에서 목표가 태양으로 옮겨 가지 않았다 (자동)")
	cam.lock = true
	cam.dist = 20.0 * Astro.LY
	w._process(0.016)
	var star := w.to_render(Astro.systems[0]["pos"])
	_check(star.length() > 0.0 and star.length() < w._camera.far, "별이 카메라 범위 밖이다")
	# 화성으로 날아가기
	cam.fly_to("mars", 3389.5 * 3.2, 0.5)
	for _i in range(60):
		w._process(0.02)
	_check(not cam.flying() and cam.focus == "mars", "화성에 도착하지 못했다")
	var gap := Astro.len3(Astro.sub3(cam.pos, w._info("mars")["center"]))
	_check(gap > 3389.5 and gap < 3389.5 * 8.0, "화성에서의 거리가 이상하다: %d km" % int(gap))
	# 다시 기지: 3D 도시의 건물을 눌러 고른다
	w.home(false)
	for _i in range(3):
		w._process(0.05)
	var city := w.city
	_check(not city._boxes.is_empty(), "3D 도시에 건물이 없다")
	var picked := ""
	for b in city._boxes:
		var c: Vector3 = (b[0] as AABB).get_center()
		var sp: Variant = w.screen_of(city.global_transform * c)
		if sp != null and Rect2(Vector2.ZERO, w.size).has_point(sp):
			picked = city.pick(w, sp)
			if picked != "":
				break
	_check(picked != "", "3D 도시에서 건물을 고를 수 없다")
	print("smoke: world %d buildings, picked %s, earth %.3f AU, moon %d km" % [city._boxes.size(), picked, r_au, int(md)])


func _plan_check() -> void:
	## 자리 고르기: 계획과 시뮬레이션의 개수, 겹침 규칙, 일조 구역, 길 잇기·지우기, 길 찾기, 저장, 3D 땅 고르기
	var sim: CitySim = main.sim
	var plan: CityPlan = main.plan
	var tool: PlaceTool = main.tool
	plan.sync(sim)
	for kind in sim.counts:
		var n := plan.built_of(kind).size()
		_check(n == int(sim.counts[kind]), "계획의 %s 개수(%d)가 시뮬레이션(%d)과 다르다" % [kind, n, int(sim.counts[kind])])
	for i in plan.buildings.size():
		for j in range(i + 1, plan.buildings.size()):
			if plan.entry_rect(plan.buildings[i]).grow(-0.05).intersects(plan.entry_rect(plan.buildings[j])):
				_check(false, "자동 배치한 건물이 겹친다: %s, %s" % [plan.buildings[i]["id"], plan.buildings[j]["id"]])
	sim.stock["parts"] += 2000.0
	sim.stock["regolith_t"] += 500.0
	sim.stock["metal_t"] += 50.0
	# 겹치는 자리 → 거절, 빈자리 → 대기열
	tool.start_build("hab_module")
	var hab: Vector3 = plan.built_of("hab_module")[0]
	tool.hover(Vector2(hab.x, hab.y))
	_check(tool.reason.contains("겹친다"), "건물 위에 겹쳐 놓을 수 있다: " + tool.reason)
	var spot := plan.suggest("hab_module")
	_check(not spot.is_empty(), "거주 모듈을 놓을 빈자리가 없다")
	tool.hover(spot["at"])
	_check(tool.reason == "", "빈자리에 놓을 수 없다: " + tool.reason)
	var q0 := sim.queue.size()
	tool.rotate()
	tool.rotate()
	tool.hover(spot["at"])
	var ok := tool.commit(false)
	_check(ok and sim.queue.size() == q0 + 1, "고른 자리에 공사가 들어가지 않았다: " + tool.reason)
	var e := plan.entry_of_seq(sim.seq)
	_check(not e.is_empty() and int(e["rot"]) == 2, "공사에 자리가 붙지 않았다")
	_check(not tool.active(), "지은 뒤에도 도구가 켜져 있다")
	# 태양광 타워: 일조 구역에만, 구역이 곧 일조 칸
	tool.start_build("solar_tower")
	tool.hover(Vector2(hab.x, hab.y) + Vector2(40, 40))
	_check(tool.reason.contains("일조 구역"), "태양광 타워를 능선 밖에 놓을 수 있다: " + tool.reason)
	var b_zone: Rect2 = BaseLayout.ZONES["B"][1]
	var bxy := BaseLayout.uv_to_xy(b_zone.get_center())
	var tiles_b := int(sim.tiles.get("B", 0))
	tool.hover(bxy)
	_check(tool.tile == "B", "B 구역이 B 칸이 아니다: " + tool.tile)
	if tool.reason == "":
		tool.commit(false)
		_check(int(sim.tiles.get("B", 0)) == tiles_b + 1, "B 구역 타워가 B 칸을 쓰지 않았다")
	tool.stop()
	# 길: 종류를 골라 두 점을 잇고 (자재가 든다), 이어서 곡선으로 굽히고, 지운다
	var e0 := plan.edges.size()
	var r0 := plan.road_rev
	var a := _free_road_spot(plan, 16.0)
	_check(a != Vector2.INF, "길을 낼 빈 땅을 찾지 못했다")
	if a != Vector2.INF:
		var b := a + Vector2(-16, 0)
		var parts0: float = sim.stock["parts"]
		tool.start_road("avenue")
		tool.click(a)
		tool.click(b)
		_check(plan.edges.size() > e0 and plan.road_rev > r0, "길이 생기지 않았다: " + tool.reason)
		_check(plan.etypes.has("avenue") and plan.edge_type(plan.nearest_edge(a.lerp(b, 0.5), 1.0)) == "avenue",
			"고른 길 종류(대로)가 아니다")
		_check(float(sim.stock["parts"]) < parts0, "길에 자재가 들지 않았다")
		_check(tool.road_dir != null, "이어 가던 길의 방향을 모른다")
		tool.set_curve(true)
		tool.hover(b + Vector2(-28, 16))
		_check(tool.preview.size() > 2, "곡선 길이 원호로 나뉘지 않았다 (%d점)" % tool.preview.size())
		_check(tool.curve_radius() > 12.0 and tool.curve_radius() < 200.0, "곡선 반지름이 이상하다: %s" % tool.curve_radius())
		var n_before := plan.edges.size()
		if tool.reason == "":
			tool.click(b + Vector2(-28, 16))
			_check(plan.edges.size() >= n_before + 2, "곡선 길이 여러 토막으로 놓이지 않았다")
		tool.hover(b + Vector2(-2, 1))
		tool.set_curve(false)
		tool.end_chain()
		tool.start_erase()
		tool.hover(a.lerp(b, 0.5))
		_check(tool.hover_edge >= 0, "지울 길을 찾지 못했다")
		tool.erase_hovered()
		# 급한 곡선은 막는다 (고속도로는 반지름 30 m 이상)
		tool.start_road("highway")
		tool.set_curve(true)
		tool.road_from = a
		tool.road_dir = Vector2(-1, 0)
		tool.hover(a + Vector2(-12, 8))
		_check(tool.reason.contains("급히 굽는다"), "고속도로의 급한 곡선을 막지 않았다: " + tool.reason)
		tool.set_curve(false)
		tool.end_chain()
	tool.stop()
	# 구획: 블록을 눌러 용도를 정한다
	var blk := {}
	for bl in plan.blocks():
		if Geometry2D.is_point_in_polygon(bl["center"], bl["poly"]) and String(bl["district"]) != "farm":
			blk = bl
			break
	_check(not blk.is_empty(), "구획을 정할 블록이 없다")
	if not blk.is_empty():
		tool.start_zone("farm")
		tool.click(blk["center"])
		_check(plan.district_at(blk["center"]) == "farm", "블록의 구획이 바뀌지 않았다: " + plan.district_at(blk["center"]))
		tool.stop()
	# 땅 고치기: 판 땅은 낮아지고, 되돌리면 처음으로
	var dig_at := Vector2.INF
	tool.start_terrain("dig")
	for ang in range(0, 360, 20):
		for rr in [150.0, 220.0, 300.0]:
			var cand: Vector2 = plan.hub() + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * rr
			tool.hover(cand)
			if dig_at == Vector2.INF and (tool.reason == "" or tool.reason.contains("굴착기")):
				dig_at = cand
	_check(dig_at != Vector2.INF, "땅을 고칠 빈 땅을 찾지 못했다")
	if dig_at != Vector2.INF:
		tool.hover(dig_at)
		if tool.reason == "":
			var nd := tool.edit_ground()
			_check(nd > 10 and plan.terrain_delta(dig_at) < -0.9, "파기가 땅을 낮추지 않았다 (%d칸)" % nd)
		else:
			plan.edit_terrain(dig_at, 12.0, "dig", 1.0)
		_check(plan.terrain_delta(dig_at) < -0.9, "판 땅이 낮아지지 않았다")
		for _i in 6:
			plan.edit_terrain(dig_at, 12.0, "restore", 1.0)
		_check(absf(plan.terrain_delta(dig_at)) < 0.05, "되돌리기가 땅을 처음으로 돌리지 않았다")
	tool.stop()
	_flood_check()
	var path := plan.route(plan.layout.gates["pad"], plan.layout.gates["ice"])
	_check(path.size() >= 3, "착륙장에서 얼음 분화구까지 길을 찾지 못했다")
	# 저장 왕복 (길 종류·구획·고친 땅까지)
	plan.edit_terrain(plan.hub() + Vector2(260, 260), 6.0, "raise", 1.0)
	var text := JSON.stringify(plan.to_save())
	var back := CityPlan.from_save(JSON.parse_string(text), sim)
	_check(back.buildings.size() == plan.buildings.size() and back.edges.size() == plan.edges.size(),
		"저장한 계획이 다르게 돌아왔다")
	_check(back.etypes == plan.etypes and back.terrain.size() == plan.terrain.size()
		and back.district_seeds.size() == plan.district_seeds.size(), "길 종류·고친 땅·구획이 저장되지 않았다")
	# 공사가 끝나면 지어진 건물이 된다
	var uid := int(e["uid"])
	for _i in range(24 * 40):
		main.colonies.step()          # 식민지 시계와 함께 (sim은 고향)
		if sim.queue.all(func(it): return int(it["seq"]) != int(e["seq"])):
			break
	plan.sync(sim)
	var done := false
	for be in plan.buildings:
		if int(be["uid"]) == uid:
			done = int(be["seq"]) < 0
	_check(done, "다 지은 거주 모듈이 계획에서 지어진 건물이 되지 않았다")
	# 3D: 화면 점 ↔ 땅 위의 점
	var w: WorldView = main.world
	main._set_view("world")
	w.home(false)
	for _i in range(3):
		w._process(0.05)
	var city := w.city
	var g0 := plan.hub() + Vector2(12, -8)
	var sp: Variant = w.screen_of(city.global_transform * city._local(g0))
	_check(sp != null, "기지 가운데가 화면 밖이다")
	if sp != null:
		var g1: Variant = city.ground_at(w, sp)
		_check(g1 != null and (g1 as Vector2).distance_to(g0) < 1.0, "3D 땅 고르기가 어긋난다: %s vs %s" % [str(g1), str(g0)])
	main._begin_place("research_lab")
	_check(tool.mode == "build" and main.place_bar.visible, "자리 고르기 막대가 뜨지 않았다")
	w._hover(w.size * 0.5)
	city.update(0.016, 0)
	_check(tool.has_at and city._ghost.visible, "3D 유령 건물이 보이지 않는다")
	tool.stop()
	print("smoke: plan %d buildings, %d roads, route %d points" % [plan.buildings.size(), plan.edges.size(), path.size()])
	_land_check()


func _types_check() -> void:
	## 건물 174종: 계열 규칙으로 도는 시뮬레이션, 자리 찾기, 거리 규칙
	var v := CitySim.new(2061, 1.0, "variety")
	for d in range(120):
		for _i in range(24):
			v.step_hour(v.population())
		v.step_day(d)
	var mixed := 0
	for mid in v.counts:
		if GameData.family(mid) != mid:
			mixed += int(v.counts[mid])
	_check(mixed > 0, "variety 운영이 새 종류를 짓지 않았다")
	_check(v.population() > 0 and v.deaths.is_empty(), "variety 운영 120일에 사망자가 났다")
	var plan: CityPlan = main.plan
	var placed := 0
	for mid in main.sim.M:
		if GameData.family(mid) == mid:
			continue
		var spot := plan.suggest(mid)
		if not spot.is_empty():
			placed += 1
	_check(placed >= 125, "빈자리를 찾은 새 종류가 모자란다: %d / 140" % placed)
	# 거리 규칙: 매립형 원자로는 거주 건물에 20 m까지, 100 kW 원자로는 60 m — 둘이 갈리는 자리가 있어야 한다
	var core: Rect2 = plan.layout.rects["core"]
	var split := false
	for k in range(0, 60):
		var at := Vector2(core.end.x + 10.0 + k * 2.0, core.get_center().y + 30.0)
		if plan.check_spot("buried_reactor", at, 0) == "":
			_check(plan.check_spot("fission_100kw", at, 0).contains("원자로"), "100 kW 원자로가 거주 건물 가까이 놓인다")
			split = true
			break
	_check(split, "매립형 원자로를 거주구 가까이 놓을 자리를 찾지 못했다")
	print("smoke: types %d mixed built, %d/140 placeable" % [mixed, placed])


## 새 건물의 효과(지원 점수·들여오는 부품·건설 속도)와 도시 발전 모드: 방향 건물 착공, 땅 구역 사기·돌려주기, 저장 왕복
func _devmodes_check() -> void:
	var a := CitySim.new(2061, 1.0, "")
	a.counts["space_bank"] = 2
	a.counts["trade_exchange"] = 1
	a.refresh()
	var sup := a.support
	var parts := float(a.stock["parts"])
	a.commerce()
	_check(is_equal_approx(a.support - sup, 2.0 * 1.5 + 0.4), "금융·교역 시설의 지원 점수가 들어오지 않았다")
	_check(is_equal_approx(float(a.stock["parts"]) - parts, 0.6), "교역소의 부품이 들어오지 않았다")
	var b0 := CitySim.new(2061, 1.0, "")
	var b1 := CitySim.new(2061, 1.0, "")
	b1.counts["rover_depot"] = 1
	b1.refresh()
	for b in [b0, b1]:
		(b as CitySim).queue = [{"id": "hab_module", "seq": 999, "rd": 1000.0, "print_t": 0.0}]
		(b as CitySim).work_robots()
	var done0 := 1000.0 - float(b0.queue[0]["rd"])
	var done1 := 1000.0 - float(b1.queue[0]["rd"])
	_check(done0 > 0.0 and is_equal_approx(done1, done0 * 1.08), "로버 차고지가 건설을 8%% 빠르게 하지 않는다 (%.2f → %.2f)" % [done0, done1])
	# 발전 모드: 교통 중심 — 방향 건물을 대기열에 넣고, 교통 지구 땅을 사서 블록을 정하고, 빈 구역을 돌려준다
	var home := CitySim.new(7, 40.0, "good")
	var col := Colonies.new()
	col.start(home, CityPlan.create(home, BaseLayout.new("ridge")))
	var c: Dictionary = col.list[0]
	c["mode"] = "transport"
	home.stock["parts"] = 3000.0
	home.support = 4000.0
	for d in 6:
		CityDev.step_day(c, d)
	_check(home.planned("transit_center") + home.planned("rover_depot") > 0, "교통 중심이 환승 센터·차고지를 짓지 않는다")
	var plan: CityPlan = c["plan"]
	var land0 := plan.land.size()
	_check(plan.expand_zone("transit", home, {}, "시험"), "교통 지구 땅 구역을 사지 못했다")
	var bought: Vector2i = plan.land.keys()[0]
	var zoned := 0
	for bl in plan.blocks():
		if String(bl["district"]) == "transit" and plan.parcel_rect(bought).has_point(bl["center"]):
			zoned += 1
	_check(plan.land.size() == land0 + 1 and zoned > 0, "산 땅 구역의 블록이 교통 지구가 되지 않았다")
	var p0 := float(home.stock["parts"])
	var e0 := plan.edges.size()
	_check(plan.release_parcel(bought, home, "시험"), "빈 땅 구역을 돌려주지 못했다")
	_check(plan.land.size() == land0 and float(home.stock["parts"]) > p0 and plan.edges.size() < e0,
		"돌려준 땅 구역의 길·값이 정리되지 않았다")
	var col2 := Colonies.new()
	col2.load_save(JSON.parse_string(JSON.stringify(col.to_save())))
	_check(String(col2.list[0].get("mode", "")) == "transport", "발전 모드가 저장되지 않았다")
	_check(LayoutData.dev_modes().size() == 11, "발전 모드가 균형 + 열 가지가 아니다")
	# 목표를 다 채운 작은 도시: 부품이 넉넉하면 그 모드 구획의 건물을 하나 더 (20일에 하나)
	var xs := CitySim.new(7, 40.0, "good")
	var xc := {"sim": xs, "plan": CityPlan.create(xs, BaseLayout.new("ridge")), "mode": "transport"}
	var xm := LayoutData.dev_mode("transport")
	for w in xm["wants"]:
		xs.counts[String(w[0])] = CityDev.target(w, xs.population())
	xs.refresh()
	xs.stock["parts"] = 3000.0
	xs.queue = []
	CityDev._build(xc, xs, xm, "transport")
	CityDev._build(xc, xs, xm, "transport")
	_check(xs.queue.size() == 1 and String(xs.queue[0]["id"]) in ["transit_center", "rover_depot", "maglev_terminal"],
		"목표를 채운 교통 중심 도시가 남는 자재로 교통 지구 건물을 (20일에 하나) 더 짓지 않는다")
	print("smoke: dev modes — bank/trade/boost ok, transport queued %d, parcel bought+released" % (home.planned("transit_center")
		+ home.planned("rover_depot")))


## 구획 자동 확장과 재건축: 자동 운영은 땅을 사기 전에 가진 땅 안의 빈 블록부터 그 구획으로 정한다. 도시가 커지고 구획이
## 붐비면 땅 넓이당 값이 낮은 건물을 헐고 그 자리에 고층 타워를 짓는다 — 공사 앞부분은 헐리는 헌 건물, 뒤는 공정만큼
## 올라가는 높은 비계. 저장 왕복, 공사가 끝나면 그 자리에 타워가 선다
func _redevelop_check() -> void:
	var rs := CitySim.new(7, 40.0, "good")
	var rp := CityPlan.create(rs, BaseLayout.new("ridge"))
	var res: String = rp.layout.district_of["hab_module"]
	var z0 := _zoned(rp, res)
	var land0 := rp.land.size()
	_check(rp._auto_expand("hab_module", rs) and rp.land.size() == land0, "자동 운영이 빈 블록보다 땅을 먼저 산다")
	_check(_zoned(rp, res) == z0 + 1, "가진 땅 안의 빈 블록이 %s 구획이 되지 않았다" % res)
	rs.techs["local_manufacturing"] = true
	rs.stock["parts"] = 5000.0
	rs.stock["metal_t"] = 100.0
	rs.counts["apartment_block"] = 2          # 집이 넉넉해야 헌다
	rs.refresh()
	rp.sync(rs)
	var rd := LayoutData.redevelop()
	var p0: float = rd["pressure"]
	rd["pressure"] = 0.0                      # 구획이 붐빈 것으로
	var c := {"sim": rs, "plan": rp, "mode": ""}
	var habs := int(rs.counts["hab_module"])
	var started := CityDev.redevelop(c)
	var twice := CityDev.redevelop(c)
	rd["pressure"] = p0
	_check(started and not twice, "붐비는 거주 구획에서 재건축을 (한 번에 한 곳) 시작하지 않았다")
	var e := rp.entry_of_seq(int(c.get("redev", -1)))
	var was: Array = e.get("was", [])
	_check(String(e.get("id", "")) == "hab_tower" and not was.is_empty() and String(was[0][0]) == "hab_module"
		and int(rs.counts["hab_module"]) == habs - was.size(), "거주 모듈을 헐고 그 자리에 고층 주거 타워를 짓지 않는다")
	var demo := 0
	var tall := 0
	for it in BaseScene.collect(rs, rp):
		demo += 1 if it.get("demolish", false) else 0
		tall += 1 if String(it["sprite"]) == "scaffold_tower" else 0
	_check(demo == was.size() and tall == 1, "재건축 현장에 헐리는 건물·높은 비계가 없다 (%d, %d)" % [demo, tall])
	_check(String(CityDev.status(c)["redev"]).contains("철거 중"), "개척 탭에 재건축이 보이지 않는다")
	var back := CityPlan.from_save(JSON.parse_string(JSON.stringify(rp.to_save())), rs, BaseLayout.new("ridge"))
	_check((back.entry_of_seq(int(c["redev"])).get("was", []) as Array).size() == was.size(), "재건축 자리가 저장 왕복에서 헌 건물을 잊었다")
	for item in rs.queue:
		item["rd"] = 0.0
		item["print_t"] = 0.0
	rs.work_robots()
	rp.sync(rs)
	var at := rp.entry_of_seq(int(c["redev"]))
	var tower := 0
	for b in rp.buildings:
		if String(b["id"]) == "hab_tower" and int(b["seq"]) < 0 and is_equal_approx(float(b["x"]), float(e["x"])):
			tower += 1
	_check(at.is_empty() and tower == 1 and int(rs.counts.get("hab_tower", 0)) == 1, "재건축이 끝났는데 그 자리에 타워가 서지 않았다")
	print("smoke: redevelop %s, %d demolished, auto-zoned a free %s block" % [String(c["redev_txt"]), was.size(), res])


func _zoned(plan: CityPlan, district: String) -> int:
	var n := 0
	for bl in plan.blocks():
		if String(bl["district"]) == district:
			n += 1
	return n


## 길 재건축: 통행량이 많은 길을 넓히고(차단막), 정착민이 늘면 고가 대로 노선을 놓는다(기둥 → 덱). 공사 자리에는 건물을 놓지 않고,
## 다 되면 길 그물에 들어간다. 저장 왕복
func _roadworks_check() -> void:
	var ws := CitySim.new(7, 40.0, "good")
	var wp := CityPlan.create(ws, BaseLayout.new("ridge"))
	ws.stock["parts"] = 5000.0
	ws.stock["metal_t"] = 100.0
	var ld := RoadWorks.loads(wp)
	var top := 0.0
	for x in ld:
		top = maxf(top, x)
	_check(top > 0.0, "길의 통행량을 셈하지 못했다")
	var c := {"sim": ws, "plan": wp, "mode": ""}
	var rw := RoadWorks.data()
	var lines: Array = rw["lines"]
	var p0: float = lines[0]["min_pop"]
	lines[0]["min_pop"] = 0.0
	var started := RoadWorks.start_next(c)
	lines[0]["min_pop"] = p0
	_check(started and wp.works.size() == 1 and String(wp.works[0]["kind"]) == "line", "고가 대로 노선 공사를 시작하지 않았다")
	var w: Dictionary = wp.works[0]
	var side := ((w["b"] as Vector2) - (w["a"] as Vector2)).normalized().orthogonal()
	var reserved := false
	for i in range(1, 20):
		for sg: float in [1.0, -1.0]:
			var at: Vector2 = (w["a"] as Vector2).lerp(w["b"], i / 20.0) + side * sg * 9.4
			if wp.check_spot("crew_capsule", at, 0).begins_with("길 공사"):
				reserved = true
	_check(reserved, "노선 공사 자리(넓어질 폭)에 건물을 놓을 수 있다")
	var back := CityPlan.from_save(JSON.parse_string(JSON.stringify(wp.to_save())), ws, BaseLayout.new("ridge"))
	_check(back.works.size() == 1 and (back.works[0]["b"] as Vector2).distance_to(w["b"]) < 0.05, "길 공사가 저장 왕복에서 달라졌다")
	var view := WorksView.new()
	w["p"] = 0.5
	view.refresh(wp, func(p: Vector2, above: float) -> Vector3: return Vector3(p.x, above, -p.y))
	_check(view.multimesh.instance_count > 3, "노선 공사의 기둥·크레인이 보이지 않는다")
	view.free()
	var e0 := wp.edges.size()
	for d in 200:
		RoadWorks.advance(wp, ws)
		if wp.works.is_empty():
			break
	_check(wp.works.is_empty() and wp.edges.size() > e0 and wp.etypes.has(String(w["type"])), "노선 공사가 끝났는데 길 그물에 없다")
	# 궤도 노선의 열차: 모노레일 한 줄에 한 편 (3량 × 상자 3)
	var mono := RoadWorks.plan_line(wp, "monorail")
	_check(not mono.is_empty() and wp.add_road(mono[0], mono[1], CityPlan.SNAP_M, "monorail"), "모노레일 노선을 놓지 못했다")
	var trains := LineTrains.new()
	trains.refresh(wp)
	trains.step(wp, func(p: Vector2, above: float) -> Vector3: return Vector3(p.x, above, -p.y), 1.0)
	_check(trains.multimesh.instance_count == 9, "모노레일에 열차가 다니지 않는다 (%d)" % trains.multimesh.instance_count)
	trains.free()
	# 넓히기: 가장 붐비는 도로를 대로로
	var wd: Dictionary = rw["widen"]
	var run := RoadWorks.widen_run(wp, {"steps": wd["steps"], "load": {"path": 0.0, "street": 0.0}})
	_check(not run.is_empty() and String(run["type"]) == "avenue", "넓힐 길을 고르지 못했다")
	print("smoke: road works line %s %d m, widen %s → %s (load %d)" % [String(w["type"]), int(w["len"]), String(run.get("from", "")),
		String(run.get("type", "")), int(run.get("load", 0))])


## 활주로·우주항이 길 격자와 나란하다 (지구·화성): 활주로는 격자 축을 따라 땅 구역 한 줄에, 그 줄은 살 수 없다.
## 우주항 땅은 블록 칸에 맞는다
func _runway_check() -> void:
	var ns := CitySim.new(2061, 1.0, "good", "earth_naro")
	var np := CityPlan.create(ns, BaseLayout.new("open"))
	var rw := np.runway()
	_check(not rw.is_empty(), "지구 도시에 활주로가 없다")
	var d: Vector2 = (rw["b"] as Vector2) - (rw["a"] as Vector2)
	_check(absf(d.x) < 0.01 or absf(d.y) < 0.01, "활주로가 길 격자와 나란하지 않다")
	var t: Array = rw["taxi"]
	_check(np.nearest_edge(((t[0] as Vector2) + (t[1] as Vector2)) * 0.5, 2.0) >= 0, "유도로가 길 그물에 없다")
	var refused := false
	for cell in np._strip_cells(String(np.runway_at[0]), int(np.runway_at[1])):
		if String(np.parcel_status(cell)["reason"]) == "활주로 자리다":
			refused = true
	_check(refused, "활주로 줄의 땅 구역을 살 수 있다")
	var pa := np.layout.pad_area
	var pt := np.layout.pitch
	var g := np.layout.grid_o
	_check(absf(fposmod(pa.position.x - g.x + pt * 0.5, pt) - pt * 0.5) < 0.01
		and absf(fposmod(pa.position.y - g.y + pt * 0.5, pt) - pt * 0.5) < 0.01, "우주항 땅이 블록 칸에 맞지 않는다")
	var moon := CityPlan.create(CitySim.new(2061, 1.0, "good"), BaseLayout.new("ridge"))
	_check(moon.runway().is_empty(), "달 도시에 활주로가 있다")
	print("smoke: runway %s along the grid, pad area on blocks" % [np.runway_at])


## 높은 길: 고가는 지나는 길과 만나지 않고(교차로·블록이 그대로), 엇갈리는 곳은 4.5 m 넘게 뜬다. 높은 길끼리 겹치면 막는다.
## 높은 길만으로 이어진 곳을 지나는 탈것은 떠서 간다. 저장 왕복, 받침 24가지가 다 지어진다
func _raised_check() -> void:
	var rp := CityPlan.create(null, BaseLayout.new("ridge"))
	var hub := rp.hub()
	var pt := rp.layout.pitch
	var a := hub + Vector2(-pt * 2.0, pt * 0.5)
	var b := hub + Vector2(pt * 2.0, pt * 0.5)
	_check(rp.road_check(a, b, "elevated_street") == "", "고가 도로를 놓지 못한다: " + rp.road_check(a, b, "elevated_street"))
	var n0 := rp.nodes.size()
	var bl0 := rp.blocks().size()
	rp.add_road(a, b, CityPlan.SNAP_M, "elevated_street")
	_check(rp.nodes.size() == n0 + 2 and rp.blocks().size() == bl0, "고가가 지나는 길과 이어졌다 (꼭짓점 %d → %d)" % [n0, rp.nodes.size()])
	var k := rp.etypes.find("elevated_street")
	_check(k >= 0 and is_equal_approx(rp.lift(k, 0.5), 7.0), "고가 가운데가 덱 높이에 닿지 않는다")
	var m0 := hub + Vector2(pt * 0.5, -pt)
	var m1 := hub + Vector2(pt * 0.5, pt * 2.0)
	_check(rp.road_check(m0, m1, "monorail").begins_with("다른 높은 길"), "높은 길끼리 겹치는데 막지 않는다")
	_check(rp.road_check(hub + Vector2(-pt, -10), hub + Vector2(-pt, pt + 10), "street") == "",
		"고가 밑으로 지나는 땅 위의 길을 막는다")
	_check(rp.road_check(hub + Vector2(-pt * 1.5, -10), hub + Vector2(-pt * 1.5, pt + 10), "street").begins_with("고가 밑을"),
		"오르는 비탈(2.8 m)과 엇갈리는 길을 막지 않는다")
	var back := CityPlan.from_save(rp.to_save(), null, BaseLayout.new("ridge"))
	_check(back.etypes == rp.etypes and back.levels().size() == rp.edges.size(), "높은 길이 저장 왕복에서 달라졌다")
	# 높은 길만으로 이어진 두 길: 경로가 덱 위로 간다
	var iso := CityPlan.new(BaseLayout.new("ridge"))
	iso.add_road(Vector2(1000, 1000), Vector2(1060, 1000), 0.6, "street")
	iso.add_road(Vector2(1260, 1000), Vector2(1320, 1000), 0.6, "street")
	iso.add_road(Vector2(1060, 1000), Vector2(1260, 1000), 0.6, "girder_bridge")
	var high := 0.0
	for q in iso.route(Vector3(1010, 1004, 0), Vector3(1310, 1004, 0)):
		high = maxf(high, (q as Vector3).z)
	_check(high > 5.0, "다리를 지나는 경로가 뜨지 않는다 (%.1f m)" % high)
	var raised := 0
	for t in LayoutData.data["roads"]:
		if not LayoutData.raised(t):
			continue
		raised += 1
		var pl := CityPlan.new(BaseLayout.new("ridge"))
		pl.add_road(Vector2(0, 0), Vector2(240, 0), 0.6, t)
		var rm := RoadMesh.start(pl, func(p: Vector2, above: float) -> Vector3: return Vector3(p.x, above, -p.y))
		rm.step(0)
		_check(not rm.v.is_empty(), "덱을 짓지 못한 높은 길: " + t)
		_check(rm.sx.size() > 0 or t == "pontoon_bridge", "받침이 없는 높은 길: " + t)
	_check(raised >= 20 and LayoutData.data["roads"].size() >= 26, "높은 길 종류가 20가지가 안 된다 (%d)" % raised)
	print("smoke: raised roads %d kinds, viaduct over streets, bridge route %.1f m up" % [raised, high])


## 여러 천체의 도시: 천체마다 기본 도시, 같은 천체 원정(로버 행렬)·도착·함께 흐르는 시간·기술 나누기,
## 도시가 없는 천체로의 행성 사이 원정(발사 창), 고르기(도시마다의 3D 땅과 도시), 지구 도시(바깥 공기), 저장 왕복
func _colony_check() -> void:
	var col: Colonies = main.colonies
	var home: CitySim = main.sim
	var bodies := {}
	for c in col.list:
		bodies[String(c["body"])] = true
		var cs: CitySim = c["sim"]
		_check(cs.population() > 0, "%s 도시가 3년을 버티지 못했다" % c["name"])
		_check(cs.hour == col.hour - int(c["founded"]), "%s의 시계가 맞지 않다" % c["name"])
	_check(col.list.size() == 7 and bodies.size() == 7, "천체마다 기본 도시가 있어야 한다 (%d곳, 천체 %d)" % [col.list.size(), bodies.size()])
	_check(String(col.list[0]["site"]) == GameData.HOME_SITE and home == col.list[0]["sim"], "고향이 섀클턴이 아니다")
	# 지구 도시: 바깥 공기를 마시고(CO₂가 쌓이지 않는다) 시장이 물·식량을 채운다, 3년 동안 자란다
	var ei := col.index_of_site("earth_naro")
	_check(ei >= 0, "지구 기본 도시가 없다")
	if ei >= 0:
		var es: CitySim = col.list[ei]["sim"]
		_check(es.open_air and es.co2_ppm() < 850.0, "지구 도시의 공기가 바깥 공기가 아니다 (%.0f ppm)" % es.co2_ppm())
		_check(es.population() > 400.0, "지구 도시가 자라지 않았다 (%d명)" % int(es.population()))
		# 보급은 시간마다 그때 인구의 30일치를 채운다 — 방금 정착민이 내렸으면(한 번에 40명) 조금 모자랄 수 있다
		_check(es.stock["water_kg"] >= es.population() * es.PER["water_use_kg"] * 25.0, "지구 도시의 물을 시장이 채우지 않았다")
	# 천문력으로 찾은 화성 창의 가장 좋은 날: 화성이 지구보다 호만 위상각(약 44°)만큼 앞서야 한다
	var w: Dictionary = col.window("mars_hellas")
	var jd := col._jd(float(w["best"]))
	var phase := wrapf(Colonies._lon("mars", jd) - Colonies._lon("earth", jd), -180.0, 180.0)
	_check(absf(phase - 44.3) < 1.5, "화성 발사 창의 위상각이 맞지 않다 (%.1f°)" % phase)
	_check(float(w["end"]) >= col.hour / 24.0 and float(w["best"]) - col.hour / 24.0 < 800.0, "다음 화성 창이 회합 주기 안에 없다")
	var window_text := col.date_text(float(w["best"]) * 24.0)
	# 도시가 없는 천체로는 고향에서 행성 사이로 (타이탄 도시를 잠시 빼고 본다)
	var ti := col.index_of_site("titan_adiri")
	var titan_c: Dictionary = col.list[ti]
	col.list.remove_at(ti)
	var rs := col.route("titan_kraken")
	_check(rs["mode"] == "space" and String(col.list[int(rs["from"])]["site"]) == GameData.HOME_SITE, "도시 없는 천체로 가는 길이 고향이 아니다")
	_check(col.travel_days("titan_kraken", rs) == 2228.0, "타이탄 전이가 2228일이 아니다")
	col.list.insert(ti, titan_c)
	# 같은 천체의 원정: 헬라스에서 예제로로 로버 행렬 — 발사 창 없이
	var r := col.route("mars_jezero")
	_check(r["mode"] == "local" and String(col.list[int(r["from"])]["site"]) == "mars_hellas", "예제로로 가는 길이 헬라스 로버 행렬이 아니다")
	var hellas: CitySim = col.list[int(r["from"])]["sim"]
	hellas.stock["parts"] = maxf(hellas.stock["parts"], 2000.0)
	hellas.support = maxf(hellas.support, 3000.0)
	var why := col.block_reason("mars_jezero")
	_check(why == "", "예제로로 떠날 수 없다: " + why)
	var days := col.travel_days("mars_jezero", r)
	_check(days > 3.0 and days < 30.0, "헬라스→예제로가 %.1f일이다" % days)
	var parts_before: float = hellas.stock["parts"]
	_check(col.launch("mars_jezero"), "원정대가 떠나지 못했다")
	_check(absf(parts_before - hellas.stock["parts"] - 180.0) < 1e-6, "원정 비용을 헬라스가 내지 않았다")
	_check(col.block_reason("mars_jezero") != "", "같은 부지로 두 번 떠날 수 있다")
	var e: Dictionary = col.in_transit("mars_jezero")
	_check(String(e.get("mode", "")) == "local" and int(e["arrive"]) - col.hour == maxi(24, int(round(days * 24.0))),
		"원정 도착 시각이 거리와 맞지 않다")
	e["arrive"] = col.hour + 24          # 시험: 하루 만에 도착
	main._update_colony_ui()
	main._select_tab("colony")
	for _i in range(31 * 24):
		if main.modal.visible:
			if main.modal.context == "storm":
				main.modal.visible = false
				main._on_modal_choice("storm", "lottery")
			else:
				main.modal.visible = false
		main._step()
	var ji := col.index_of_site("mars_jezero")
	_check(col.list.size() == 8 and ji >= 0, "원정대가 도착해 도시가 서지 않았다")
	if ji < 0:
		return
	var jez: CitySim = col.list[ji]["sim"]
	_check(jez.site_id == "mars_jezero" and jez.hour == col.hour - int(col.list[ji]["founded"]), "예제로의 시계가 맞지 않다")
	_check(jez.date_text() == home.date_text(), "두 도시의 날짜가 다르다")
	_check(jez.population() > 0, "예제로가 첫 달을 버티지 못했다")
	_check(jez.techs.size() == home.techs.size(), "기술이 나눠지지 않았다")
	# 고르기: 같은 화성의 두 도시는 땅이 따로다. 자세한 도시는 고른 도시 하나만
	main._on_colony_view(ji)
	var wv: WorldView = main.world
	_check(main.sim == jez and wv.ground == wv.grounds.get("mars_jezero") and wv.ground.body == "mars", "예제로를 고르지 못했다")
	_check(wv.city != null and wv.city.get_parent() == wv.ground.city_root, "예제로에 3D 도시가 서지 않았다")
	_check(wv.moon.city_root.get_child_count() == 0, "고르지 않은 달 도시가 남아 있다")
	_check(main.plan.layout.kind == "open" and main.tool.sim == jez, "예제로의 배치·도구가 맞지 않다")
	_check(not home.interactive and jez.interactive, "고른 도시만 결정 카드를 띄워야 한다")
	var hi := col.index_of_site("mars_hellas")
	main._on_colony_view(hi)
	_check(wv.ground == wv.grounds.get("mars_hellas") and wv.ground != wv.grounds.get("mars_jezero"), "헬라스와 예제로가 땅을 같이 쓴다")
	_check(not (wv.grounds["mars_jezero"] as SiteGround).active, "고르지 않은 예제로 땅이 아직 고른 땅이다")
	var marks: Array = wv.colonies
	var cities := marks.filter(func(m): return not m.get("candidate", false) and not m.get("transit", false))
	var cands := marks.filter(func(m): return m.get("candidate", false))
	_check(cities.size() == col.list.size() and bool(cities[hi]["active"]), "3D 지도의 도시 점이 맞지 않다")
	_check(cands.size() == col.candidates().size() - col.list.size(), "3D 지도의 후보지 점이 맞지 않다 (%d)" % cands.size())
	_world_surface_check(wv)
	_transport_check(col)
	for _i in range(24):
		main._step()
	main._refresh_live()
	# 저장 왕복 (판 2: 도시 여덟)
	var text := JSON.stringify(col.to_save(), "", false, true)
	var back := Colonies.new()
	_check(back.load_save(JSON.parse_string(text)), "도시 저장을 읽지 못했다")
	_check(back.list.size() == col.list.size() and back.hour == col.hour, "불러온 도시·시각이 다르다")
	_check(back.transport.lines.size() == col.transport.lines.size() and back.transport.trips.size() == col.transport.trips.size(),
		"불러온 교통(노선·가는 편)이 다르다")
	_check(back.metro_fn.modes.mode_of("metro_busan") == "parts_capital" and back.metro_fn.econ.commerce.has("metro_seoul")
		and back.metro_fn.econ.seed_value == col.seed_value, "불러온 대도시 운영 방식·경제가 다르다")
	# 판 2 저장(교통이 없던 저장)도 읽고 노선을 새로 짠다
	var v2: Dictionary = JSON.parse_string(text)
	v2["version"] = 2
	v2.erase("transport")
	var back2 := Colonies.new()
	_check(back2.load_save(v2) and back2.transport.lines.size() == col.transport.lines.size(), "판 2 저장을 읽지 못했다")
	if back.list.size() == col.list.size():
		var jb: CitySim = back.list[ji]["sim"]
		_check(jb.site_id == "mars_jezero" and absf(jb.population() - jez.population()) < 1e-9, "불러온 예제로가 다르다")
	# 판 1 저장(도시 하나)은 기본 도시를 채워 읽는다
	var v1 := home.to_save()
	v1["plan"] = (col.list[0]["plan"] as CityPlan).to_save()
	var old := Colonies.new()
	_check(old.load_save(JSON.parse_string(JSON.stringify(v1, "", false, true))) and old.list.size() == 7, "판 1 저장을 읽지 못했다")
	# 고향으로
	main._on_colony_view(0)
	_check(main.sim == home and wv.ground.body == "moon", "고향으로 돌아오지 못했다")
	# 직접 줌인: 고르지 않은 화성 헬라스 위로 내려가면 카메라는 그대로, 그 도시를 고른다
	wv._descent.clear()
	wv._enter_cool = 0.0
	wv.cam.look_at_surface("mars", Astro.latlon(-42.4, 70.5), 5.0, 0.5, Vector3(0, 0, 1))
	wv._check_enter(0.0)
	_check(main.sim == hellas and wv.ground.body == "mars" and wv.cam.focus == "mars", "헬라스로 줌인해도 그 도시를 고르지 않았다")
	main._on_colony_view(0)
	_check(main.sim == home, "고향으로 돌아오지 못했다 (줌인 뒤)")
	var pops := []
	for c in col.list:
		pops.append("%s %d" % [c["short"], int((c["sim"] as CitySim).population())])
	print("smoke: cities %d (%s), next mars window %s (phase %.1f°)" % [col.list.size(), ", ".join(pops), window_text, phase])


## 도시 사이 교통: 노선 짜기, 3년 동안 오간 짐·사람, 화물이 실제로 옮겨지나, 끄고 켜기, 교통 탭. 대도시와 구획 자료
func _transport_check(col: Colonies) -> void:
	var tr := col.transport
	var roles := {}
	for l in tr.lines:
		roles[l["role"]] = int(roles.get(l["role"], 0)) + 1
	Metros.load_all()
	_check(Metros.list.size() == 26, "대도시가 26곳이 아니다 (%d)" % Metros.list.size())
	_check(int(roles.get("shuttle", 0)) == 1 and int(roles.get("ship", 0)) == 5, "셔틀·수송선 노선이 맞지 않다 %s" % str(roles))
	_check(int(roles.get("feeder", 0)) == Metros.list.size() and int(roles.get("air", 0)) >= Metros.list.size(),
		"대도시 항공편이 맞지 않다 %s" % str(roles))
	var mars := tr.line_by_id("local:mars_hellas~mars_jezero")
	_check(not mars.is_empty() and mars["mode"] == "mars_plane", "헬라스–예제로 노선이 없다 (화성 수송기)")
	_check(int(tr.totals["trips"]) > 1000 and float(tr.totals["t"]) > 10.0 and int(tr.totals["settlers"]) > 0,
		"3년 동안 교통이 거의 오가지 않았다 %s" % str(tr.totals))
	for m in Metros.list:
		_check(PlanetLook.coast_local(String(m["key"])) != null, "%s의 시가지 지도가 없다" % m["name"])
	# 화물: 헬라스의 넉넉한 식량을 굶주린 예제로로
	if not mars.is_empty():
		var hel: CitySim = col.list[col.index_of_site("mars_hellas")]["sim"]
		var jez: CitySim = col.list[col.index_of_site("mars_jezero")]["sim"]
		hel.stock["food_kg"] = float(hel.caps.get("food_kg", 20000.0)) * 0.95      # 저장 한도 안에서 넉넉하게
		jez.stock["food_kg"] = 100.0
		var dir := 0 if mars["a"] == "mars_hellas" else 1
		mars["next"][dir] = col.hour
		mars["next"][1 - dir] = col.hour + 1000
		var before_h: float = hel.stock["food_kg"]
		var before_j: float = jez.stock["food_kg"]
		col.step()
		var trip := {}
		for t in tr.trips:
			if t["line"] == mars["id"] and t["from"] == "mars_hellas":
				trip = t
		_check(not trip.is_empty() and float(trip["cargo"].get("food_kg", 0.0)) > 0.0, "헬라스에서 예제로로 식량을 싣지 않았다")
		if not trip.is_empty():
			var load_kg := float(trip["cargo"]["food_kg"])
			_check(absf(before_h - hel.stock["food_kg"] - load_kg) < 50.0, "보낸 식량이 헬라스 비축에서 빠지지 않았다")
			for _i in range(int(trip["arrive"]) - col.hour):
				col.step()
			_check(jez.stock["food_kg"] > before_j + load_kg * 0.5, "예제로에 식량이 닿지 않았다")
	# 끄면 새로 떠나지 않는다
	var n0 := int(tr.totals["trips"]) + tr.trips.size()
	tr.set_enabled(col, false)
	var leaving := tr.trips.size()
	for _i in 48:
		col.step()
	_check(tr.trips.size() <= leaving, "교통을 껐는데 새 편이 떠났다")
	tr.set_enabled(col, true)
	for _i in 48:
		col.step()
	_check(int(tr.totals["trips"]) + tr.trips.size() > n0, "교통을 다시 켰는데 움직이지 않는다")
	main._select_tab("transport")
	main.tabs["transport"].rebuild()
	main.tabs["transport"].update_view()
	main.world.show_route(String(tr.lines[0]["id"]))
	# 카메라의 고정점: 기지 위에서는 우주 › 태양계 › (행성 ›) 천체 › 도시, 아래로 고를 것들, 수송선을 따라가기
	var wv: WorldView = main.world
	wv.home(false)
	wv._process(0.016)
	var path := wv.anchors.path()
	_check(path.size() >= 4 and String(path[0]["kind"]) == "galaxy" and String(path[-1]["kind"]) == "colony",
		"고정점 경로가 기지까지 이어지지 않는다 %s" % str(path.map(func(x): return x["name"])))
	_check(wv.anchors.children(CamAnchors.system()).size() >= 11, "태양계 아래 고를 것이 모자란다")
	_check(wv.anchors.children(CamAnchors.body("earth")).filter(func(x): return x["kind"] == "metro").size() == 26,
		"지구 아래 대도시가 26곳이 아니다")
	var ships := wv.anchors.ships()
	if not ships.is_empty():
		wv.anchors.go(ships[0])
		_check(wv.cam.track.is_valid(), "수송선을 고정점으로 골랐는데 따라가지 않는다")
	wv.anchors.go({"kind": "galaxy", "id": "galaxy", "name": "우주"})
	_check(wv.cam.focus == "galaxy" and not wv.cam.track.is_valid(), "우리 은하를 고정점으로 고르지 못했다")
	wv.home(false)
	# 기지의 교통 탈것: 한꺼번에 닿은 여객기 두 대는 진입로에 줄을 선다 (같은 길을 겹쳐 날지 않게)
	var traffic: BaseTraffic = main.world.city.traffic
	var feeder := tr.line_by_id("feeder:earth_naro~metro_seoul")
	var ways := {"runway": {"a": Vector2(0, -1200), "b": Vector2(0, 1200)}, "highways": {}, "bearings": {}}
	traffic.reset(main.sim)
	traffic.intercity(tr, "earth_naro", ways)            # 처음에는 지난 사건을 건너뛴다
	for _k in 2:
		tr._event("arr", "earth_naro", "metro_seoul", feeder)
	traffic.intercity(tr, "earth_naro", ways)
	var planes := traffic.agents.filter(func(a): return a["role"] == "plane")
	_check(planes.size() == 2 and (planes[0]["pos"] as Vector3).distance_to(planes[1]["pos"]) > 1000.0,
		"한꺼번에 닿은 여객기가 진입로에 줄을 서지 않았다 (%d대)" % planes.size())
	traffic.reset(main.sim)
	# 구획: 필지는 자리마다 하나
	var lay := BaseLayout.new("open")
	var lots := 0
	var slots := 0
	for d in lay.lots:
		lots += (lay.lots[d] as Array).size()
	for k in lay.slots:
		slots += (lay.slots[k] as Array).size()
	_check(lots == slots and lots > 200, "구역의 필지 수가 자리 수와 다르다 (%d/%d)" % [lots, slots])
	print("smoke: transport %d lines %s, trips %d, %.1f t, settlers %d, metros %d" % [tr.lines.size(), str(roles),
		int(tr.totals["trips"]), float(tr.totals["t"]), int(tr.totals["settlers"]), Metros.list.size()])
	_metro_fn_check(col)
	_metro_map_check()
	_metro_mode_check(col)
	_economy_check(col)
	_region_check(col)
	_metro_ui_check(col)


## 대도시의 우주 시설: 지원을 내고 짓고, 다 지으면 항공편이 더 싣고 더 자주 뜨며, 연구·지원이 들어온다. 저장 왕복
## 대도시 시가지 지도: 거리의 자투리(B)가 있고 (물가 띠가 m 단위로 곧다), 서울은 도심이 땅이고 남쪽으로 한강(폭 ~1 km)이
## 가로지른다 (MetroCity가 이웃 네 칸을 섞어 읽는 거리로)
func _metro_map_check() -> void:
	for m in Metros.list:
		var img := PlanetLook.coast_local(String(m["key"])).get_image()
		if img.is_compressed():
			img.decompress()
		# 물가 ±2 km 안 (R이 끝에 닿지 않은 칸)에서만 자투리가 있다 — 물이 없는 도시(베이징·멕시코시티)는 건너뛴다
		var fine := {}
		var near := 0
		for y in range(3, img.get_height(), 29):
			for x in range(3, img.get_width(), 29):
				var px := img.get_pixel(x, y)
				if px.r8 > 2 and px.r8 < 253:
					near += 1
					fine[px.b8] = true
		_check(near < 10 or fine.size() > 8, "%s 시가지 지도에 거리의 자투리(B)가 없다 — earth_coast.py로 다시 만들 것" % m["name"])
	var mc := MetroCity.new()
	var seoul := Metros.of("metro_seoul")
	mc._map = PlanetLook.coast_local("metro_seoul").get_image()
	mc._half_km = float(seoul["radius_km"]) + 10.0
	_check(mc._sample(Vector2.ZERO).x > 0.3, "서울 도심이 물가에 있다")
	var wet_from := INF
	var width := 0.0
	var prev := mc._sample(Vector2(1600.0, -3000.0)).x
	for i in range(1, 300):
		var y := -3000.0 - i * 20.0
		var s := mc._sample(Vector2(1600.0, y)).x
		if prev >= 0.0 and s < 0.0:
			wet_from = y
		elif prev < 0.0 and s >= 0.0 and wet_from < INF:
			width = wet_from - y
			break
		prev = s
	_check(width > 500.0 and width < 1800.0, "서울 도심 남쪽에 한강이 없다 (폭 %.0f m)" % width)
	mc.free()
	print("smoke: metro maps fine, 한강 폭 %.0f m (도심 남쪽 1.6 km 동쪽)" % width)


func _metro_fn_check(col: Colonies) -> void:
	var fn := col.metro_fn
	var tr := col.transport
	var payer: CitySim = col.list[0]["sim"]
	payer.support = 5000.0
	var key := "metro_seoul"
	_check(MetroFunctions.defs().size() == 5, "대도시의 우주 시설이 다섯이 아니다")
	_check(MetroFunctions.scale(key, "space_park") > MetroFunctions.scale(key, "research"), "서울의 강점(우주 산업)이 몫을 키우지 않는다")
	var s0 := payer.support
	_check(fn.build(key, "space_park", col, 0) and fn.building(key, "space_park"), "우주 산업 단지를 짓기 시작하지 못했다")
	_check(absf(s0 - payer.support - 150.0) < 0.01, "짓는 데 지원 150이 빠지지 않았다")
	_check(not fn.build(key, "space_park", col, 0), "짓는 중인 시설을 또 지었다")
	_check(fn.build(key, "cargo_hub", col, 0) and fn.build(key, "research", col, 0) and fn.build(key, "outreach", col, 0)
		and fn.build(key, "emigration", col, 0), "다른 시설을 짓기 시작하지 못했다")
	for _i in 24 * 31:
		col.step()
	for fac in MetroFunctions.ORDER:
		_check(fn.level(key, fac) == 1 and not fn.building(key, fac), "%s이(가) 1단계가 되지 않았다" % MetroFunctions.fac_name(fac))
	var feeder := tr.line_by_id("feeder:earth_naro~metro_seoul")
	_check(not feeder.is_empty() and int(feeder["every_h"]) == 16, "공항 화물 터미널이 항공편을 앞당기지 않았다 (%s)" %
		str(feeder.get("every_h", "-")))
	var fb := fn.feeder(key, 24)
	_check(int(fb["settlers"]) > 20 and float(fb["parts"]) > 1.0, "항공편이 더 싣지 않는다 %s" % str(fb))
	for _i in 24:
		col.step()
		if col.hour % 24 == 0:
			break
	var y: Dictionary = fn.last.get(key, {})
	_check(float(y.get("rp", 0.0)) > 0.0 and float(y.get("support", 0.0)) > 0.0, "연구소·홍보관의 몫이 들어오지 않았다 %s" % str(y))
	var back := MetroFunctions.new()
	back.load_save(JSON.parse_string(JSON.stringify(fn.to_save())))
	_check(back.level(key, "research") == 1 and back.active_keys() == [key], "대도시 시설이 저장되지 않았다")
	print("smoke: metro functions %s — feeder every %dh, +%d settlers, +%.1f parts/flight" % [key, int(feeder.get("every_h", 0)),
		int(fb["settlers"]), float(fb["parts"])])


## 대도시 운영 방식: 준비 기간 뒤에 운영비로 시설을 올린다 (①부산 · ③서울·런던 · ⑤도쿄). ①은 협력 지역과 함께 부품을 더 싣고,
## ③은 회원(연구소가 있는 도시)의 연구를 과제에 모아 동맹 기술·식민지 기술을 마치며, ⑤는 창고를 채워 위급한 달 식민지에
## 비상편을 띄운다. 운영비가 바닥나면 쉬고, 멈추면 남은 운영비가 돌아온다. 저장 왕복
func _metro_mode_check(col: Colonies) -> void:
	var fn := col.metro_fn
	var m := fn.modes
	var home: CitySim = col.list[0]["sim"]
	home.support = 30000.0
	_check(Metros.MODE_IDS.size() == 3 and Metros.modes.size() == 3, "운영 방식이 셋이 아니다")
	var ok := m.set_mode("metro_busan", "parts_capital", col, 0) == "" and m.set_mode("metro_seoul", "research_alliance", col, 0) == "" \
		and m.set_mode("metro_london", "research_alliance", col, 0) == "" and m.set_mode("metro_tokyo", "emergency_depot", col, 0) == ""
	_check(ok, "운영 방식을 고르지 못했다")
	for k in ["metro_busan", "metro_seoul", "metro_london", "metro_tokyo"]:
		_check(m.deposit(k, 2000.0, col, fn) == "", "%s에 운영비를 맡기지 못했다" % k)
	_check(m.deposit("metro_paris", 100.0, col, fn) != "", "운영 방식이 없는 도시에 운영비를 맡겼다")
	var b0 := m.budget("metro_busan")
	_check(m.set_partner("metro_busan", "tech_pyeongtaek", col) == "" and m.budget("metro_busan") < b0,
		"협력 지역 계약이 운영비에서 빠지지 않았다")
	_check(not m.working("metro_busan", col.hour), "준비 기간 없이 움직인다")
	for _i in 24 * 4:
		col.step()
	_check(m.working("metro_busan", col.hour, "parts_capital") and m.parts_k("metro_busan", col.hour) > 1.5,
		"우주 산업 수도가 부품을 더 싣지 않는다 (×%.2f)" % m.parts_k("metro_busan", col.hour))
	_check(fn.building("metro_busan", "space_park") or fn.building("metro_busan", "cargo_hub"), "우주 산업 수도가 운영비로 짓지 않았다")
	_check(fn.building("metro_london", "research"), "연구 동맹이 연구소를 짓지 않았다")
	_check(m.ally_member("metro_seoul", col.hour, fn) and not m.ally_member("metro_london", col.hour, fn), "동맹 회원이 맞지 않다")
	_check(float(m.alliance["pool"]) > 0.0 or m.last_gain > 0.0, "동맹이 연구 점수를 모으지 않았다")
	var dep := m.depot("metro_tokyo")
	_check(float(dep.get("o2_kg", 0.0)) > 0.0 and float(dep.get("parts", 0.0)) > 0.0, "비상 창고가 차지 않았다 %s" % str(dep))
	# 동맹 기술: 위기 예측망 — 비상 경보를 이틀 일찍
	var plus0 := m.alarm_plus(col.hour)
	_check(m.set_project("crisis_forecast", col) == "", "동맹 과제를 고르지 못했다")
	m.alliance["pool"] = float(Metros.alliance["crisis_forecast"]["cost"])
	_day(col)
	_check(m.done("crisis_forecast") and m.alarm_plus(col.hour) == plus0 + 2, "동맹 기술(위기 예측망)이 완성되지 않았다")
	# 식민지 기술 (남아 있으면): 동맹이 마치면 모든 식민지가 안다
	var tech := ""
	for p in m.projects(col):
		if not bool(p[3]):
			tech = String(p[0])
			break
	if tech != "":
		m.set_project(tech, col)
		m.alliance["pool"] = m.project_cost(tech, col)
		_day(col)
		_check(col.list.all(func(c): return bool((c["sim"] as CitySim).techs.get(tech, false))), "동맹이 마친 기술을 모든 식민지가 알지 못한다")
	# 비상 보급: 고향(달)의 산소를 사흘치로 — 3시간 안에 비상 셔틀이 뜬다
	home.stock["o2_kg"] = home.population() * float(home.PER["o2_kg"]) * 3.0
	for _i in 4:
		col.step()
	_check(col.transport.has_tagged(String(col.list[0]["site"]), "emergency"), "산소가 위급한데 비상편이 뜨지 않았다")
	# 운영비가 바닥나면 쉰다 — 맡기면 다시 움직인다
	m.metros["metro_busan"]["budget"] = 0.0
	_day(col)
	_check(m.paused("metro_busan") and not m.working("metro_busan", col.hour), "운영비가 바닥났는데 쉬지 않는다")
	_check(m.deposit("metro_busan", 50.0, col, fn) == "" and not m.paused("metro_busan"), "운영비를 맡겼는데 다시 움직이지 않는다")
	# 저장 왕복
	var back := MetroFunctions.new()
	back.load_save(JSON.parse_string(JSON.stringify(fn.to_save())))
	_check(back.modes.mode_of("metro_busan") == "parts_capital" and back.modes.partner_of("metro_busan") == "tech_pyeongtaek"
		and back.modes.done("crisis_forecast") and absf(back.modes.budget("metro_tokyo") - m.budget("metro_tokyo")) < 1e-6
		and back.modes.depot("metro_tokyo").size() == m.depot("metro_tokyo").size(), "운영 방식이 저장되지 않았다")
	var tokyo := m.status_short("metro_tokyo", col, fn)
	# 멈추면 남은 운영비(비상 창고는 반값에 판다)가 후원 식민지로 돌아온다
	var s0 := home.support
	var refund := m.budget("metro_tokyo")
	_check(m.set_mode("metro_tokyo", "", col, 0) == "" and m.mode_of("metro_tokyo") == "" and home.support >= s0 + refund - 1e-6,
		"운영 방식을 멈췄는데 운영비가 돌아오지 않았다")
	print("smoke: metro modes — 부산 ×%.2f (%s), 동맹 %s · 기술 %d, 도쿄 %s, 비상편 있음" % [m.parts_k("metro_busan", col.hour),
		m.status_short("metro_busan", col, fn), m.status_short("metro_seoul", col, fn), m.alliance["done"].size(), tokyo])


## 상업·금융: 우주 상점가는 계약 비용을 내고 날마다 수입, 채권은 빌린 만큼 받고 날마다 갚는다, 펀드는 지수를 따라 오르내리고
## 찾으면 돌아온다. 펀드의 기대 수익(폭락까지 셈한)은 가장 싼 채권 이자보다 낮다 (빌려서 굴려 벌 수 없다). 저장 왕복
func _economy_check(col: Colonies) -> void:
	var fn := col.metro_fn
	var e := fn.econ
	var home: CitySim = col.list[0]["sim"]
	home.support = 30000.0
	var s0 := home.support
	_check(e.open_commerce("metro_seoul", col, 0) == "" and absf(s0 - home.support - MetroEconomy.commerce_cost("metro_seoul")) < 1e-6,
		"우주 상점가 계약 비용이 빠지지 않았다")
	_check(e.open_commerce("metro_seoul", col, 0) != "", "같은 도시에 상점가를 두 번 열었다")
	var t := MetroEconomy.loan_terms("metro_london")
	var s1 := home.support
	_check(e.borrow("metro_london", col, 0) == "" and absf(home.support - s1 - float(t["amount"])) < 1e-6, "채권으로 빌린 돈이 들어오지 않았다")
	_check(e.invest("metro_newyork", 250.0, col, 0) == "", "펀드에 넣지 못했다")
	var v0 := float(e.funds["metro_newyork"]["value"])
	var left0 := int(e.loans["metro_london"]["days_left"])
	_day(col)
	_day(col)
	var y: Dictionary = fn.last.get("metro_seoul", {})
	_check(float(y.get("commerce", 0.0)) > 0.0, "상점가 수입이 들어오지 않았다 %s" % str(y))
	_check(int(e.loans["metro_london"]["days_left"]) == left0 - 2, "채권을 날마다 갚지 않는다")
	_check(float(e.funds["metro_newyork"]["value"]) != v0, "펀드가 오르내리지 않는다")
	# 빌려서 굴려 벌 수 없다: 180일 기대 수익(폭락 포함) − 수수료 < 가장 싼 채권 이자
	var fc := MetroEconomy.cfg("fund")
	var cr: Dictionary = fc["crash"]
	var net := float(fc["mu_day"]) - float(cr["chance"]) * float(cr["days"]) * float(cr["day_drop"])
	var lc := MetroEconomy.cfg("loan")
	var fund_k := pow(1.0 + net, float(lc["days"])) - 1.0 - float(fc["fee"])
	_check(net > 0.0 and fund_k < float(lc["rate_min"]), "펀드 기대 수익이 맞지 않다 (하루 %.5f, 180일 %.3f)" % [net, fund_k])
	var back := MetroEconomy.new()
	back.load_save(JSON.parse_string(JSON.stringify(e.to_save())))
	_check(back.commerce.has("metro_seoul") and back.loans.has("metro_london") and back.funds.has("metro_newyork")
		and absf(back.index - e.index) < 1e-6, "상업·금융이 저장되지 않았다")
	var s2 := home.support
	_check(e.withdraw("metro_newyork", col) == "" and home.support > s2 and not e.funds.has("metro_newyork"), "펀드를 찾지 못했다")
	print("smoke: economy — 지수 %.0f, 화제 %.2f, 서울 상권 %.1f/일, 런던 채권 %d (이자 %.0f%%), 펀드 180일 기대 %.1f%%" % [e.index, e.buzz,
		float(y.get("commerce", 0.0)), int(t["amount"]), float(t["rate"]) * 100.0, fund_k * 100.0])


## 반도체·AI 데이터센터 지역 24곳: 둘은 대도시 시가지 안 (상하이 장장·싱가포르 북부), 나머지는 해안 지도가 있다. 지구의 고정점,
## 처음 찾아가면 견학 연구 점수 (한 번만), 지역마다 운영 방식에 주는 몫
func _region_check(col: Colonies) -> void:
	_check(Metros.regions.size() == 24, "첨단 산업 지역이 24곳이 아니다 (%d)" % Metros.regions.size())
	var inside: Array = Metros.regions.filter(func(r): return String(r["in_metro"]) != "").map(func(r): return String(r["key"]))
	inside.sort()
	_check(inside == ["tech_singapore_north", "tech_zhangjiang"], "대도시 시가지 안의 지역이 맞지 않다 %s" % str(inside))
	for r in Metros.regions:
		if String(r["in_metro"]) == "":
			_check(PlanetLook.coast_local(String(r["key"])) != null, "%s의 해안 지도가 없다" % r["name"])
	var wv: WorldView = main.world
	var tech := wv.anchors.children(CamAnchors.body("earth")).filter(func(x): return x["kind"] == "tech")
	_check(tech.size() == 24, "지구 아래 첨단 산업 지역이 24곳이 아니다 (%d)" % tech.size())
	var home: CitySim = col.list[0]["sim"]
	var m := col.metro_fn.modes
	var rp0 := home.rp_bank
	_check(m.visit("tech_hsinchu", home) and not m.visit("tech_hsinchu", home) and absf(home.rp_bank - rp0 - 30.0) < 1e-6,
		"견학 연구 점수가 한 번만 들어오지 않는다")
	var hs := Metros.region("tech_hsinchu")
	_check(MetroModes.bonus_for("parts_capital", hs) > 0.0 and MetroModes.bonus_for("research_alliance", hs) > 0.0,
		"신주가 운영 방식에 주는 몫이 없다")
	_check(MetroModes.alarm_days_for(Metros.region("tech_ashburn")) >= 1, "애슈번 데이터센터가 비상 경보를 앞당기지 않는다")
	var near := Metros.nearest_region(Metros.of("metro_seoul")["dir"], 80.0)
	_check(not near.is_empty() and String(near["country"]) == "대한민국", "서울 가까이에 반도체 지역이 없다")
	print("smoke: regions %d (시가지 안 %d), 서울에서 가장 가까운 곳 %s" % [Metros.regions.size(), inside.size(), String(near.get("name", "-"))])


## 대도시 카드의 세 탭과 단추, 지역 카드, 교통 탭의 요약이 오류 없이 그려진다
func _metro_ui_check(col: Colonies) -> void:
	var fn := col.metro_fn
	var mc: MetroCard = main.metro_card
	mc.payer_index = 0
	mc.show_metro("metro_busan")
	for t in ["ops", "econ", "fac"]:
		mc.set_tab(t)
	mc.set_tab("ops")
	_check(mc._ops_rows.get_child_count() > 0 and mc._partner_pick.item_count > 1, "운영 탭이 비었다")
	mc.set_tab("econ")
	_check(mc._econ_box.get_child_count() > 0, "경제 탭이 비었다")
	mc.set_tab("fac")
	main._on_metro_ops("metro_busan", "auto_fill", true)
	_check(bool(fn.modes.entry("metro_busan").get("auto_fill", false)), "자동 채움 단추가 듣지 않는다")
	main._on_metro_mode("metro_paris", "research_alliance")
	_check(fn.modes.mode_of("metro_paris") == "research_alliance", "운영 방식 단추가 듣지 않는다")
	main._on_metro_ops("metro_paris", "deposit", 100.0)
	_check(fn.modes.budget("metro_paris") >= 100.0, "운영비 단추가 듣지 않는다")
	var rc: RegionCard = main.region_card
	rc.show_region("tech_ashburn")
	_check(rc._rows.get_child_count() > 0, "지역 카드가 비었다")
	main._on_region_ops("tech_ashburn", "partner", "metro_london")
	_check(fn.modes.partner_of("metro_london") == "tech_ashburn", "지역 카드의 협력 단추가 듣지 않는다")
	main._select_tab("transport")
	main.tabs["transport"].rebuild()
	main.tabs["transport"].update_view()


func _day(col: Colonies) -> void:
	for _i in 24:
		col.step()
		if col.hour % 24 == 0:
			return


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


## 천체의 겉모습: 암석·얼음 천체 다섯의 굽기 자료, 타이탄의 바다, 지구의 해안 지도와 지구 도시의 땅 (헤드리스라 굽지는 않는다)
func _world_surface_check(wv: WorldView) -> void:
	var col: Colonies = main.colonies
	for b in ["mercury", "mars", "ceres", "callisto", "titan"]:
		_check(BodySurface.has_body(b) and wv.body_baker.has(b), "%s의 겉모습 자료가 없다" % b)
		var m: ShaderMaterial = wv._bodies[b]["mat"]
		_check(int(m.get_shader_parameter("pal_n")) >= 4, "%s 구에 팔레트가 없다" % b)
	var titan := BodySurface.of("titan", 2574.7)
	_check(titan.liquid > 0.0 and int(titan.u["sea_n"]) >= 10 and int(titan.u["keep_n"]) == 3, "타이탄의 바다·기지 자리가 맞지 않다")
	var mars := BodySurface.of("mars", 3389.5)
	_check(int(mars.u["mnt_n"]) >= 5 and int(mars.u["tro_n"]) >= 3 and int(mars.u["bas_n"]) >= 10, "화성의 지형 자료가 모자란다")
	var earth_mat: ShaderMaterial = wv._bodies["earth"]["mat"]
	_check(bool(earth_mat.get_shader_parameter("has_coast")) and int(earth_mat.get_shader_parameter("ekeep_n")) == 3,
		"지구의 해안 지도·기지 자리가 없다")
	_check(PlanetLook.coast_local("earth_naro") != null, "나로 둘레의 고운 해안 지도가 없다")
	var kr := wv.ground_for("titan_kraken") as SiteSurface
	_check(kr != null and kr.surface != null and kr.surface.liquid > 0.0 and kr.needs_cap(), "크라켄 해 땅이 타이탄 자료를 쓰지 않는다")
	var ni := col.index_of_site("earth_naro")
	var keep: CitySim = main.sim
	main._on_colony_view(ni)
	var eg := wv.ground as SiteSurface
	_check(eg != null and eg.body == "earth" and not eg.needs_cap() and eg.sky_color().a > 0.0, "나로의 땅이 지구 땅이 아니다")
	_check(absf(eg.local_height_m(Vector2.ZERO)) < 0.01, "나로 기지 평지가 평평하지 않다")
	main._on_colony_view(col.index_of_sim(keep))
	print("smoke: worlds — 굽는 천체 %d, 타이탄 바다 %d, 화성 산 %d·협곡 %d, 지구 해안 %s" % [wv.body_baker.surfaces.size(),
		int(titan.u["sea_n"]), int(mars.u["mnt_n"]), int(mars.u["tro_n"]), "있음" if bool(earth_mat.get_shader_parameter("has_coast")) else "없음"])


## 침수: 평평한 땅(해수면 3 m 아래)을 5 m 파면 물이 차고, 그 위에는 지을 수 없고, 메우면 물이 빠진다 (굽지 않은 격자로)
func _flood_check() -> void:
	var sg := SiteGround.new()
	sg._segs = 48
	sg._grow = 1.0 + TAU / 48.0
	var k := 0
	while sg.ring_m(k) < 2000.0:
		k += 1
	sg._rings = k + 1
	sg._hgrid = PackedFloat32Array()
	sg._hgrid.resize(sg._rings * sg._segs)
	sg._keep_baked(null, null, false)
	sg.sea_z = -3.0
	var lay := BaseLayout.new()
	var p2 := CityPlan.new(lay)
	var spot := Vector2(240, 30)
	for _i in 5:
		p2.edit_terrain(spot, 12.0, "dig", 1.0)
	sg.apply_terrain(p2)
	_check(not p2.flood.is_empty() and not sg.flooded.is_empty(), "해수면 아래로 판 땅에 물이 차지 않았다")
	_check(sg._sample(sg._hgrid, spot, sg._rings - 1) < -4.0, "판 땅의 높이가 격자에 들어가지 않았다")
	_check(p2.check_spot("hab_module", spot, 0).contains("물에 잠긴"), "물에 잠긴 땅에 지을 수 있다")
	_check(p2.road_check(spot + Vector2(-20, 0), spot + Vector2(20, 0)).contains("물에 잠긴"), "물에 잠긴 땅으로 길을 낼 수 있다")
	for _i in 8:
		p2.edit_terrain(spot, 12.0, "restore", 1.0)
	sg.apply_terrain(p2)
	_check(p2.flood.is_empty() and sg.flooded.is_empty(), "메운 땅에서 물이 빠지지 않았다")
	sg.free()
	print("smoke: terrain dug %d cells, flood ok" % p2.terrain.size())


## 길 시험에 쓸 빈 땅: 블록 안에서 (길·건물과 떨어져) 동쪽에서 서쪽으로 length m를 낼 수 있는 시작점
func _free_road_spot(plan: CityPlan, length: float) -> Vector2:
	for bl in plan.blocks():
		var poly: PackedVector2Array = bl["poly"]
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		var y := bb.position.y + 2.0
		while y < bb.end.y - 2.0:
			var x := bb.end.x - 2.0
			while x > bb.position.x + length + 2.0:
				var ca := Vector2(x, y)
				var cb := ca + Vector2(-length, 0)
				if Geometry2D.is_point_in_polygon(ca, poly) and Geometry2D.is_point_in_polygon(cb, poly) \
						and plan.nearest_edge(ca, 7.5) < 0 and plan.nearest_edge(cb, 7.5) < 0 \
						and plan.road_check(ca, cb, "avenue") == "":
					return ca
				x -= 3.0
			y += 3.0
	return Vector2.INF


## 땅 구역: 기지에 붙은 구역을 사면 길이 깔리고 빈 블록이 생기고, 그 땅이 기지가 된다. 자동 운영은 스스로 넓힌다. 저장 왕복
func _land_check() -> void:
	var plan: CityPlan = main.plan
	var sim: CitySim = main.sim
	var cands := plan.land_candidates()
	_check(not cands.is_empty(), "살 수 있는 땅 구역 후보가 없다")
	var pick := {}
	for st in cands:
		if bool(st["ok"]):
			pick = st
			break
	_check(not pick.is_empty(), "살 수 있는 땅 구역이 하나도 없다: %s" % str(cands.map(func(x): return x["reason"])))
	if pick.is_empty():
		return
	_check(not plan.in_land((pick["rect"] as Rect2).get_center() + Vector2(0.1, 0.1)) or plan._parcel_base(pick["cell"]) > 0,
		"사기 전에 구역이 땅이다")
	sim.stock["parts"] = float(sim.stock["parts"]) + 500.0
	sim.support += 1000.0
	var e0 := plan.edges.size()
	var b0 := plan.blocks().size()
	var tool: PlaceTool = main.tool
	main._begin_tool("land")
	var rect: Rect2 = pick["rect"]
	tool.click(rect.get_center())
	_check(plan.land.has(pick["cell"]), "땅 구역을 사지 못했다: " + tool.reason)
	_check(plan.edges.size() > e0 and plan.blocks().size() > b0, "산 구역에 길·블록이 생기지 않았다 (길 %d→%d, 블록 %d→%d)" % [
		e0, plan.edges.size(), b0, plan.blocks().size()])
	_check(plan.in_land(rect.get_center()), "산 구역이 땅이 아니다")
	tool.click(rect.get_center())
	_check(tool.reason.contains("이미 가진"), "가진 구역을 또 살 수 있다: " + tool.reason)
	main.world.city.update(0.016, 0)
	tool.stop()
	var nb := plan.blocks().filter(func(b): return rect.has_point(b["center"]))
	_check(not nb.is_empty(), "산 구역 안에 블록이 없다")
	# 자동 운영: 자리가 모자라면 먼저 가진 땅 안의 빈 블록을 그 구획으로, 빈 블록을 다 쓰면 구획 가까이의 구역을 사서 그 구획 블록으로
	var n_land := plan.land.size()
	if sim.autopilot == null:
		sim.autopilot = AutoPolicy.new("good")
		sim.autopilot.configure(sim)
	var ok := false
	var zoned := 0
	for _i in 40:
		ok = plan._auto_expand("hab_module", sim)
		if not ok or plan.land.size() > n_land:
			break
		zoned += 1
	_check(ok and plan.land.size() == n_land + 1, "자동 운영이 빈 블록(%d곳)을 다 쓴 뒤 땅을 넓히지 않았다" % zoned)
	var back := CityPlan.from_save(JSON.parse_string(JSON.stringify(plan.to_save())), sim, plan.layout)
	_check(back.land.size() == plan.land.size(), "산 땅 구역이 저장되지 않았다")
	print("smoke: land %d parcels, %d candidates (%d open), roads %d, %d free blocks zoned before buying" % [plan.land.size(),
		cands.size(), cands.filter(func(x): return bool(x["ok"])).size(), plan.edges.size(), zoned])


## 시간: 최고 속도는 한 프레임에 여러 시간을 흘리고, 다음 사건 계속 넘기기는 사건을 지나서도 이어 간다
func _speed_check() -> void:
	var col: Colonies = main.colonies
	main.modal.visible = false
	var h0 := col.hour
	main._on_speed_button(main.MAX_SPEED)
	for _i in 5:
		main._process(0.016)
	var fast := col.hour - h0
	_check(fast >= 10, "최고 속도가 빠르지 않다 (5프레임에 %d시간)" % fast)
	main._on_speed_button(0)
	var h1 := col.hour
	main._begin_auto_jump()
	for _i in 80:
		if main.modal.visible:
			if main.modal.context == "storm":
				main._on_modal_choice("storm", "lottery")
			main.modal.visible = false
		main._process(0.5)
	var jumped := col.hour - h1
	_check(jumped >= 24 * 5, "다음 사건 계속 넘기기가 이어 가지 않았다 (%d시간)" % jumped)
	main._stop_auto_jump()
	main._set_speed(0)
	print("smoke: speed — max %d h in 5 frames, auto-jump %d h" % [fast, jumped])
