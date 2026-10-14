extends SceneTree
## 교통·대도시 스크린숏 — 기본 도시로 시작해 며칠 흐른 뒤: 지구의 항공편과 대도시, 지구-달 셔틀, 행성간 수송선,
## 교통 탭, 서울 위로 날아가기 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/transport_shots.gd -- --out /tmp/shots [--days 20]

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


## 대도시 위로 내려앉았고 시가지를 다 지었나
func _metro_done(w: WorldView, key: String) -> bool:
	if w.cam.flying() or not w._descent.is_empty() or not w.metro_grounds.has(key):
		return false
	return (w.metro_grounds[key]["city"] as MetroCity)._phase == 3


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
		var korea := Astro.latlon(36.0, 128.0)
		var atlantic := Astro.latlon(45.0, -30.0)
		_steps = [
			["earth_asia", func(): w.cam.look_at_surface("earth", korea, 6371.0 * 1.2, 0.0, Vector3(0, 0, 1))],
			["earth_atlantic", func(): w.cam.look_at_surface("earth", atlantic, 6371.0 * 1.4, 0.0, Vector3(0, 0, 1))],
			["earth_korea", func(): w.cam.look_at_surface("earth", korea, 1400.0, 0.5, Vector3(0, 0, 1))],
			["earth_moon", func(): w.show_earth_moon(), func(): return not w.cam.flying()],
			["inner_system", func(): w.cam.look_from_space("sun", 3.4e8, 0.9, 0.75)],
			["transport_tab", func(): main._select_tab("transport")],
			["seoul", func(): w.fly_to_metro("metro_seoul"), func(): return _metro_done(w, "metro_seoul")],
			["seoul_low", func(): w.cam.dist = 4.5; w.cam.tilt = deg_to_rad(72.0)],
			["newyork", func(): w.fly_to_metro("metro_newyork"), func(): return _metro_done(w, "metro_newyork")],
			["paris", func(): w.fly_to_metro("metro_paris"), func(): return _metro_done(w, "metro_paris")],
			["tokyo", func(): w.fly_to_metro("metro_tokyo"), func(): return _metro_done(w, "metro_tokyo")],
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
		_wait = 8
		if s.size() > 2:
			_until = s[2]
			_wait = 0
	else:
		_shot("transport_%02d_%s" % [_step / 2 + 1, s[0]], s[0] == "transport_tab")
	_step += 1
	return false
