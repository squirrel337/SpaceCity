extends SceneTree
## 3D 우주 보기 스크린숏 — 기지(낮·밤·낮은 시점), 달 전체, 지구-달, 태양계, 이웃 별 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/world_shots.gd -- --out /tmp/shots [--days 200] [--only 이름,이름]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 200
var only := PackedStringArray()
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
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
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
	if not only.is_empty() and not name in only:
		return
	var img := root.get_texture().get_image()
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k))
	img.get_region(r).save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _to_day(dark: bool) -> void:
	var guard := 0
	while main.sim.is_dark() != dark and guard < 24 * 40:
		main.sim.advance_hour()
		guard += 1


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		_run_days(days)
		_to_day(false)
		main._set_speed(0)
		main.sim.enqueue("research_lab", "", 0.0)
		main.sim.enqueue("hydroponics", "", 0.0)
		main.modal.visible = false
		main._set_view("world")
		w.speed_level = 2
		_steps = [
			["home", func(): w.home(false)],
			["city_low", func(): w.cam.look_at_surface("moon", w.moon.site_dir(), 0.45, deg_to_rad(78.0),
				w.moon.site_frame() * Vector3(-0.2, -1.0, 0.0))],
			["city_wide", func(): w.cam.look_at_surface("moon", w.moon.site_dir(), 4.5, deg_to_rad(62.0),
				w.moon.site_frame() * Vector3(-1.0, -1.0, 0.0))],
			["shackleton", func(): w.cam.look_at_surface("moon", w.moon.site_dir(), 38.0, deg_to_rad(55.0),
				w.moon.site_frame() * Vector3(-1.0, -1.0, 0.0))],
			["south_pole", func(): w.cam.look_at_surface("moon", w.moon.site_dir(), 420.0, deg_to_rad(30.0),
				w.moon.site_frame() * Vector3(-1.0, -1.0, 0.0))],
			["moon_globe", func(): w.cam.look_from_space("moon", 1737.4 * 3.4, 0.8, -0.35)],
			["earth_moon", func(): w.cam.look_from_space("earth", 1.1e6, -0.6, 0.45)],
			["earth_close", func(): w.cam.look_from_space("earth", 6371.0 * 3.2, 2.0, 0.3)],
			["solar_inner", func(): w.cam.look_from_space("sun", 4.5e8, 0.4, 0.9)],
			["solar_outer", func(): w.cam.look_from_space("sun", 1.4e10, 0.4, 0.7)],
			["saturn", func(): w.cam.look_from_space("saturn", 58232.0 * 7.0, 1.1, 0.35)],
			["jupiter", func(): w.cam.look_from_space("jupiter", 69911.0 * 4.0, 0.3, 0.1)],
			["neighbors", func(): w.cam.look_from_space("sun", 26.0 * Astro.LY, 0.7, 0.5)],
			["night", func():
				_to_day(true)
				main._refresh_live()
				w.home(false)],
		]
		_wait = 30           # 달 표면을 굽는 동안
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
		_wait = 8
	else:
		_shot("world_%02d_%s" % [_step / 2 + 1, s[0]])
	_step += 1
	return false
