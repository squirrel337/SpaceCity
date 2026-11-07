extends SceneTree
## L5 궤도 도시 스크린숏 — 고향에 질량 투사기를 지은 것으로 하고 L5 사업을 단계마다 앞당겨 찍는다:
## 질량 포획기(우주에서), 차폐 껍질을 두르는 중, 회전 원통 (단면), 다 지은 원통과 거울, 도시로 내려앉기, 원통 안의 도시,
## 개척 탭의 L5 사업 칸, 항로 지도의 L5 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/l5_shots.gd -- --out /tmp/shots [--days 20]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 20
var _steps: Array = []
var _step := 0
var _wait := 0
var _until: Callable


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


func _run_hours(n: int) -> void:
	for _i in range(n):
		if main.modal.visible:
			if main.modal.context == "storm":
				main.modal.visible = false
				main._on_modal_choice("storm", "lottery")
			else:
				main.modal.visible = false
		main._step()
	main._refresh_live()


func _shot(name: String, full := false) -> void:
	var img := root.get_texture().get_image()
	if not full:
		var k := Vector2(img.get_size()) / root.get_visible_rect().size
		var g: Rect2 = main.city_area.get_global_rect()
		img = img.get_region(Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)))
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


## 시험: L5 사업을 단계 stage까지 앞당긴다 (building이면 그 단계를 p만큼 짓는 중)
func _to_stage(stage: int, building: bool, p: float) -> void:
	var col: Colonies = main.colonies
	var st := Orbital.state(col)
	st["stage"] = stage
	st["building"] = building
	if building:
		var sg: Dictionary = Orbital.stages()[stage]
		st["ready"] = col.hour + int(float(sg["days"]) * 24.0 * (1.0 - p))


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		_run_hours(days * 24)
		main._set_speed(0)
		main.modal.visible = false
		main._set_view("world")
		var col: Colonies = main.colonies
		var home: CitySim = col.home()["sim"]
		for t in ["mass_driver", "rotating_habitat", "orbital_assembly", "megawatt_fission", "local_manufacturing",
				"molten_regolith_electrolysis"]:
			home.techs[t] = true
		# 고향에 질량 투사기를 정말로 짓는다 (3D 모형이 서게): 시대 2, 땅 구역 하나, 마지막 단계까지
		var hc: Dictionary = col.home()
		CityProgress.state(hc)["era"] = 2
		home.stock["parts"] = maxf(home.stock["parts"], 6000.0)
		home.stock["metal_t"] = maxf(home.stock["metal_t"], 600.0)
		home.support = maxf(home.support, 9000.0)
		CityProgress._buy_site(hc)
		if CityProgress.start(hc, "mass_driver"):
			var wk: Dictionary = (hc["plan"] as CityPlan).mega[0]
			wk["stage"] = (CityProgress.mega("mass_driver")["stages"] as Array).size() - 1
			wk["p"] = 1.0
			CityProgress.advance(hc)
		if not (CityProgress.state(hc)["built"] as Array).has("mass_driver"):
			(CityProgress.state(hc)["built"] as Array).append("mass_driver")
			print("  (질량 투사기 3D 없이)")
		var view_l5 := func(dist: float, yaw: float, pitch: float): w.cam.look_from_space("l5", dist, yaw, pitch)
		_steps = [
			["catcher", func():
				_to_stage(0, true, 0.8)
				view_l5.call(14.0, 0.9, 0.35)],
			["shell", func():
				_to_stage(1, true, 0.55)
				view_l5.call(30.0, 0.7, 0.45)],
			["hull", func():
				_to_stage(2, true, 0.7)
				view_l5.call(30.0, 2.4, 0.5)],
			["mirrors", func():
				_to_stage(3, true, 0.9)
				view_l5.call(38.0, 2.0, 0.6)],
			["from_earth", func():
				_to_stage(4, false, 0.0)
				Orbital._found(col)
				main._update_colony_ui()
				w.cam.look_from_space("earth", 6.0e5, 1.2, 0.3)],
			["fly_mid", func(): main._on_colony_view(Orbital.city_index(col)), func(): return w.cam._fly.get("t", 1.0) > 0.6],
			["landing", func(): pass, func(): return not w.cam.flying() and float(w._descent.get("t", 0.0)) > 0.45],
			["l5_city", func(): pass, func(): return not w.cam.flying() and w._descent.is_empty()],
			["l5_city_up", func():
				w.cam.tilt = deg_to_rad(78.0)
				w.cam.dist = 1.6],
			["l5_city_far", func(): w.cam.dist = 7.5],
			["l5_outside", func(): view_l5.call(26.0, 2.3, -0.35)],
			["colony_tab", func():
				main._on_colony_view(0)
				main._select_tab("colony")],
			["dvmap_l5", func():
				home.stock["regolith_t"] = 40000.0
				Orbital._fire(col, home)
				main._set_view("map")
				main.dv_map.selected = "n:l5"
				main.dv_map._sig = ""
				main.dv_map.refresh(true)],
			["home_driver", func():
				main._set_view("world")
				w.home(false)
				w.cam.dist = 1.4
				w.cam.tilt = deg_to_rad(58.0)],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _until.is_valid():
		if not _until.call() and _wait > -2000:
			_wait -= 1
			return false
		_until = Callable()
		_wait = 6
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 10
		if s.size() > 2:
			_until = s[2]
			_wait = 0
	else:
		_shot("l5_%02d_%s" % [_step / 2 + 1, s[0]], s[0] == "colony_tab" or s[0] == "dvmap_l5")
		if OS.has_environment("L5_DEBUG"):
			var hv: HabitatView = w._bodies["l5"]["hab"]
			print("  cam_local ", hv._hull_mat.get_shader_parameter("cam_local"), " cam ", w.cam.mode, " dist ", w.cam.dist,
				" tilt ", rad_to_deg(w.cam.tilt), " focus ", w.cam.focus)
	_step += 1
	return false
