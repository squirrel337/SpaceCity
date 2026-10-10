extends SceneTree
## 기지 지도 스크린숏 — 자동 운영으로 기지를 키운 뒤 전체·거주구·밤·착륙 장면을 남긴다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/map_shots.gd -- --out /tmp/shots [--days 300]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 300
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_days(n: int) -> void:
	for _i in range(n * 24):
		if main.modal.visible:
			if main.modal.context == "storm":
				main.modal.visible = false
				main._on_modal_choice("storm", "lottery")
			else:
				main.modal.visible = false
		main._step()
	main._refresh_live()


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	# 지도 부분만 잘라 둔 것 (디자인 문서용)
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k))
	img.get_region(r).save_png(out_dir.path_join(name + "_map.png"))
	print("shot ", name, " ", img.get_size())


func _process(_delta: float) -> bool:
	frame += 1
	var m: BaseMap = main.base_map if main else null
	match frame:
		4:
			main._on_modal_choice("start", "auto")
			_run_days(days)
			# 낮인 시각으로 옮긴다
			var guard := 0
			while main.sim.is_dark() and guard < 24 * 20:
				main.sim.advance_hour()
				guard += 1
			m.night_k = 0.0
			main._set_speed(0)          # 시뮬레이션은 멈추고 탈것만 움직인다
			m.speed_level = 2
			# 공사 현장을 만든다 (로봇이 일하는 장면)
			main.sim.enqueue("research_lab", "", 0.0)
			main.sim.enqueue("hydroponics", "", 0.0)
			main.modal.visible = false
			main._set_view("map")
		40:
			m.fit()
		44:
			_shot("map_01_overview")
		45:
			m.focus_core()
		80:
			_shot("map_02_core")
		81:
			m.zoom = 1.2
			m.center = ArtLib.project(m.layout.slot("research_lab", int(main.sim.counts.get("research_lab", 0))))
			m._clamp()
		120:
			_shot("map_03_construction")
		121:
			m.zoom = 1.0
			m.center = ArtLib.project(m.layout.slots["landing_pad"][0] + Vector3(0, 0, 12))
			m._clamp()
			m.traffic.agents = m.traffic.agents.filter(func(a): return a["role"] != "lander")
			m.traffic._landers_waiting.clear()
			m.traffic._landers_waiting.append("crew_lander")
		124:
			for a in m.traffic.agents:
				if a["role"] == "lander":
					a["t"] = BaseTraffic.DESCEND_S * 0.6
			m.speed_level = 0
		130:
			for a in m.traffic.agents:
				if a["role"] == "lander":
					a["t"] = BaseTraffic.DESCEND_S * 0.6
					m.traffic._lander(a, 0.0)
		150:
			_shot("map_04_lander")
		151:
			var guard := 0
			while not main.sim.is_dark() and guard < 24 * 40:
				main.sim.advance_hour()
				guard += 1
			m.night_k = 1.0
			m.focus_core()
			m.speed_level = 0
		170:
			_shot("map_05_night")
		171:
			m.speed_level = 2
			m.night_k = 0.0
			while main.sim.is_dark():
				main.sim.advance_hour()
			m.zoom = 0.75
			m.center = ArtLib.project(m.layout.tower_slots[0][0] + Vector3(10, 10, 0))
			m._clamp()
		200:
			_shot("map_06_ridge")
		201:
			main._set_view("list")
		205:
			_shot("map_07_list")
			quit(0)
	return false
