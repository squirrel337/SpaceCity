extends SceneTree
## 화면이 실제로 도는지 확인하는 연기 시험 — 메인 씬을 띄우고, 자동 운영으로 60일을 돌리고,
## 탭을 모두 열어 보고, 저장·불러오기를 왕복한 뒤 3년 보고서까지 간다. 오류가 하나라도 나면 실패한다.
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
			main._select_tab(["life", "power", "build", "research", "log"][(frames / 40) % 5])
	elif frames == 400:
		_check(main.sim.current_day() >= 60, "60일을 돌지 못했다 (%d일)" % main.sim.current_day())
		_check(main.sim.population() > 0, "정착민이 모두 사라졌다")
		var built: int = main.sim.stats.get("built", 0)
		_check(built > 0, "자동 운영이 아무것도 짓지 않았다")
		_save_roundtrip()
		_map_check()
		_world_check()
		_plan_check()
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
	# 같은 상태에서 같은 결정이면 같은 결과가 나와야 한다
	for _i in range(24 * 10):
		restored.advance_hour()
		main.sim.advance_hour()
	_check(absf(restored.stock["o2_kg"] - main.sim.stock["o2_kg"]) < 1e-6, "불러온 뒤 10일의 결과가 다르다")
	_check(restored.rng.random() == main.sim.rng.random(), "난수 상태가 이어지지 않았다")


func _map_check() -> void:
	## 기지 지도: 건물 자리, 공사 현장으로 가는 로봇, 착륙선 사건, 지도·목록 전환
	var m: BaseMap = main.base_map
	_check(m.layout.capacity("hab_module") >= 30, "거주 모듈 자리가 모자란다")
	_check(m.layout.capacity("solar_tower") == 38, "태양광 타워 자리가 능선 칸(8+10+20)과 다르다")
	for kind in main.sim.M:
		_check(m.layout.capacity(kind) > 0, "지도에 자리가 없는 건물: " + kind)
		_check(ArtLib.variants(kind) == 5, "변형이 5가지가 아닌 건물: " + kind)
		for v in range(ArtLib.variants(kind)):
			_check(ArtLib.texture(ArtLib.building(kind, v)["file"]) != null, "그림이 없는 건물: %s v%d" % [kind, v])
	for v in range(5):
		_check(ArtLib.texture(ArtLib.building("hab_module_covered", v)["file"]) != null, "피복 거주 모듈 그림이 없다")
	var seen := {}
	for i in range(5):
		seen[BaseMap.variant_of("hab_module", i)] = true
	_check(seen.size() == 5, "이웃한 자리 다섯 곳의 변형이 겹친다")
	main.sim.enqueue("medical_bay", "", 0.0)
	var sites := m._sites()
	_check(not sites.is_empty(), "공사 현장이 지도에 없다")
	for _i in range(900):
		m.traffic.update(0.1, main.sim, sites)
	var working := 0
	for a in m.traffic.agents:
		if a["role"] == "robot" and a["state"] == "work":
			working += 1
		var info := ArtLib.info("vehicles", a["id"], a["heading"])
		_check(not info.is_empty() and ArtLib.texture(info["file"]) != null, "그림이 없는 탈것: " + a["id"])
	_check(working > 0, "로봇이 공사 현장에 가지 않았다")
	var before := int(main.sim.stats.get("arrived", 0))
	main.sim.stats["arrived"] = before + 1
	m.traffic.update(0.1, main.sim, sites)
	_check(m.traffic.agents.any(func(a): return a["role"] == "lander"), "유인 착륙선이 나타나지 않았다")
	for _i in range(200):
		m.traffic.update(0.1, main.sim, sites)
	_check(not m.traffic.agents.any(func(a): return a["role"] == "lander"), "착륙선이 떠나지 않았다")
	main.sim.stats["arrived"] = before
	m.traffic.reset(main.sim)
	main._set_view("list")
	_check(main.city_view.visible and not m.visible, "목록으로 바뀌지 않았다")
	main._set_view("map")
	m.zoom_by(1.5)
	m.fit()
	print("smoke: map %d robots working, %d agents" % [working, m.traffic.agents.size()])


func _world_check() -> void:
	## 3D 우주 보기: 모형, 천체 위치, 구글 어스식 조작(끌기·휠·날기), 축척 공간, 3D 도시
	var w: WorldView = main.world
	main._set_view("world")
	_check(w.visible and not main.base_map.visible, "3D 보기로 바뀌지 않았다")
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
	cam.dist = 3.0e9
	w._process(0.016)
	var sun_gap := Astro.len3(Astro.sub3(cam.target, w._info("sun")["center"]))
	_check(sun_gap < 1.0e8, "태양계 거리에서 목표가 태양으로 옮겨 가지 않았다")
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
	# 길: 두 점을 이어 길을 내고, 지운다
	var e0 := plan.edges.size()
	var r0 := plan.road_rev
	tool.start_road()
	var a := plan.hub() + Vector2(0, -60)
	var b := a + Vector2(-30, 0)
	var free_a := plan.road_check(a, b) == ""
	if free_a:
		tool.click(a)
		tool.click(b)
		_check(plan.edges.size() > e0 and plan.road_rev > r0, "길이 생기지 않았다")
		tool.start_erase()
		tool.hover(a.lerp(b, 0.5))
		_check(tool.hover_edge >= 0, "지울 길을 찾지 못했다")
		tool.erase_hovered()
	tool.stop()
	var path := plan.route(plan.layout.gates["pad"], plan.layout.gates["ice"])
	_check(path.size() >= 3, "착륙장에서 얼음 분화구까지 길을 찾지 못했다")
	# 저장 왕복
	var text := JSON.stringify(plan.to_save())
	var back := CityPlan.from_save(JSON.parse_string(text), sim)
	_check(back.buildings.size() == plan.buildings.size() and back.edges.size() == plan.edges.size(),
		"저장한 계획이 다르게 돌아왔다")
	# 공사가 끝나면 지어진 건물이 된다
	var uid := int(e["uid"])
	for _i in range(24 * 40):
		sim.advance_hour()
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


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
