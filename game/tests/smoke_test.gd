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


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
