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
		_map_check()
		_world_check()
		_plan_check()
		_types_check()
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


func _map_check() -> void:
	## 기지 배치·교통: 건물 자리, 공사 현장으로 가는 로봇, 착륙선 사건, 3D·목록 전환
	var layout: BaseLayout = main.plan.layout
	_check(layout.capacity("hab_module") >= 30, "거주 모듈 자리가 모자란다")
	_check(layout.capacity("solar_tower") == 38, "태양광 타워 자리가 능선 칸(8+10+20)과 다르다")
	_check(main.sim.M.size() == 145 and GameData.FAMILY.size() == 29, "건물이 29계열 145종이 아니다")
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


func _types_check() -> void:
	## 건물 145종: 계열 규칙으로 도는 시뮬레이션, 자리 찾기, 거리 규칙
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
	_check(placed >= 110, "빈자리를 찾은 새 종류가 모자란다: %d / 116" % placed)
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
	print("smoke: types %d mixed built, %d/116 placeable" % [mixed, placed])


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
