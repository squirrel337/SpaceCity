extends SceneTree
## 성간 탐사선 스크린숏 — 고향에 레이저 돛 발사 시설을 지은 것으로 하고 탐사선 셋을 쏜 뒤 몇 해를 앞당겨 찍는다:
## 이웃 별 지도의 탐사선 길·자리, 프록시마의 소식이 온 뒤 이름표, 개척 탭의 성간 탐사 칸, 고향의 레이저 시설과 빛줄기 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/probe_shots.gd -- --out /tmp/shots [--days 20]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 20
var _steps: Array = []
var _step := 0
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
		var hc: Dictionary = col.home()
		var home: CitySim = hc["sim"]
		for t in ["laser_sail", "megawatt_fission", "space_weather_forecast", "local_manufacturing", "molten_regolith_electrolysis"]:
			home.techs[t] = true
		CityProgress.state(hc)["era"] = 2
		home.stock["parts"] = maxf(home.stock["parts"], 6000.0)
		home.stock["metal_t"] = maxf(home.stock["metal_t"], 600.0)
		home.support = maxf(home.support, 20000.0)
		CityProgress._buy_site(hc)
		if CityProgress.start(hc, "laser_array"):
			var wk: Dictionary = (hc["plan"] as CityPlan).mega[0]
			wk["stage"] = (CityProgress.mega("laser_array")["stages"] as Array).size() - 1
			wk["p"] = 1.0
			CityProgress.advance(hc)
		if not (CityProgress.state(hc)["built"] as Array).has("laser_array"):
			(CityProgress.state(hc)["built"] as Array).append("laser_array")
			print("  (레이저 시설 3D 없이)")
		for star in ["proxima_centauri", "alpha_centauri", "barnards_star"]:
			var why := Probes.launch(col, star)
			if why != "":
				print("  launch ", star, ": ", why)
		var st := Probes.state(col)
		var ks := [0.62, 0.35, 0.15]
		for j in (st["probes"] as Array).size():
			var p: Dictionary = st["probes"][j]
			var span := int(p["arrive"]) - int(p["launched"])
			var back := int(span * float(ks[j]))
			p["launched"] = int(p["launched"]) - back
			p["arrive"] = int(p["arrive"]) - back
			p["report"] = int(p["report"]) - back
		_steps = [
			["home_laser", func():
				w.home(false)
				w.cam.dist = 1.2
				w.cam.tilt = deg_to_rad(55.0)],
			["star_map", func(): w.cam.look_from_space("sun", Astro.LY * 9.0, 4.0, 0.42)],
			["star_map_near", func(): w.cam.look_from_space("sun", Astro.LY * 4.2, 3.9, 0.3)],
			["proxima_news", func():
				var p0: Dictionary = st["probes"][0]
				Probes._report(col, p0)
				w.cam.look_from_space("proxima_centauri", Astro.LY * 2.2, 3.9, 0.45)],
			["colony_tab", func():
				main._select_tab("colony")
				main.tabs["colony"].rebuild()],
			["probe_card", func():                        # 앞 단계에서 다시 만든 칸이 자리를 잡은 뒤에 내린다
				var l := _find_label(main, "성간 탐사 · ", true)
				if l != null:
					main.panel_scroll.scroll_vertical = int(l.global_position.y - main.panel_scroll.global_position.y) \
						+ main.panel_scroll.scroll_vertical - 8],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 12
	else:
		_shot("probe_%02d_%s" % [_step / 2 + 1, s[0]], s[0] == "colony_tab" or s[0] == "probe_card")
	_step += 1
	return false


func _find_label(n: Node, text: String, prefix := false) -> Control:
	if n is Label and ((n as Label).text == text or (prefix and (n as Label).text.begins_with(text))):
		return n
	for ch in n.get_children():
		var f := _find_label(ch, text, prefix)
		if f != null:
			return f
	return null
