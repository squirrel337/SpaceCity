extends SceneTree
## 기지 평면도 스크린숏 — 자동 운영으로 기지를 키운 뒤 전체·거주구·공사·착륙·밤·능선 장면을 남긴다 (디스플레이가 필요하다).
## 평면도는 3D 장면을 바로 위에서 직교 투영으로 내려다본 것이다.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/map_shots.gd -- --out /tmp/shots [--days 300]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 300


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
	# 도시 화면 부분만 잘라 둔 것 (디자인 문서용)
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k))
	img.get_region(r).save_png(out_dir.path_join(name + "_map.png"))
	print("shot ", name, " ", img.get_size())


## 기지 배치의 자리(모형 좌표 m) — 레이아웃의 자리 목록에서
func _slot_xy(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	var traffic: BaseTraffic = w.city.traffic if w else null
	match frame:
		4:
			main._on_modal_choice("start", "auto")
			_run_days(days)
			# 낮인 시각으로 옮긴다
			var guard := 0
			while main.sim.is_dark() and guard < 24 * 20:
				main.sim.advance_hour()
				guard += 1
			main._set_speed(0)          # 시뮬레이션은 멈추고 탈것만 움직인다
			w.speed_level = 2
			# 공사 현장을 만든다 (로봇이 일하는 장면)
			main.sim.enqueue("research_lab", "", 0.0)
			main.sim.enqueue("hydroponics", "", 0.0)
			main.modal.visible = false
			main._set_view("map")
		40:
			w.plan_fit()
		50:
			_shot("map_01_overview")
		51:
			w.plan_core()
		80:
			_shot("map_02_core")
		81:
			var lab: Vector3 = w.city.layout.slot("research_lab", int(main.sim.counts.get("research_lab", 0)))
			w.plan_look(_slot_xy(lab), 0.14)
		120:
			_shot("map_03_construction")
		121:
			w.plan_look(_slot_xy(w.city.layout.slots["landing_pad"][0]), 0.16)
			traffic.agents = traffic.agents.filter(func(a): return a["role"] != "lander")
			traffic._landers_waiting.clear()
			traffic._landers_waiting.append("crew_lander")
		124:
			for a in traffic.agents:
				if a["role"] == "lander":
					a["t"] = BaseTraffic.DESCEND_S * 0.6
			w.speed_level = 0
		130:
			for a in traffic.agents:
				if a["role"] == "lander":
					a["t"] = BaseTraffic.DESCEND_S * 0.6
					traffic._lander(a, 0.0)
		150:
			_shot("map_04_lander")
		151:
			var guard := 0
			while not main.sim.is_dark() and guard < 24 * 40:
				main.sim.advance_hour()
				guard += 1
			w.plan_core()
			w.speed_level = 0
		175:
			_shot("map_05_night")
		176:
			w.speed_level = 2
			while main.sim.is_dark():
				main.sim.advance_hour()
			var tower: Vector3 = w.city.layout.tower_slots[0][0]
			w.plan_look(_slot_xy(tower) + Vector2(10, 10), 0.3)
		205:
			_shot("map_06_ridge")
		206:
			main._set_view("list")
		210:
			_shot("map_07_list")
			quit(0)
	return false
