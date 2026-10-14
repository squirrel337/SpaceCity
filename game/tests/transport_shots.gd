extends SceneTree
## 교통·대도시 스크린숏 — 기본 도시로 시작해 며칠 흐른 뒤: 지구의 항공편과 대도시, 지구-달 셔틀, 행성간 수송선,
## 교통 탭, 서울 위로 날아가기 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/transport_shots.gd -- --out /tmp/shots [--days 20] [--only seoul,naro_runway]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 20
var only := PackedStringArray()
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
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
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


## 그 대도시가 밤이 될 때까지 시간을 흘린다
func _until_night(key: String) -> void:
	var w: WorldView = main.world
	for _i in 30:
		if w.metro_grounds.has(key) and (w.metro_grounds[key]["ground"] as SiteSurface).night_k > 0.95:
			break
		_run_hours(1)
		w._process(0.0)


func _go_base(key: String) -> void:
	main._on_colony_view(main.colonies.index_of_site(key))


## 시험: 이 도시에 그 노선의 탈것이 닿았다고 알린다 (기지에 탈것이 뜬다), 시간을 흘려 움직이게
func _arrive(site: String, line_id: String) -> void:
	var tr: Transport = main.colonies.transport
	var l := tr.line_by_id(line_id)
	if l.is_empty():
		print("no line ", line_id)
		return
	tr._event("arr", site, String(l["a"]) if String(l["b"]) == site else String(l["b"]), l)
	main._set_speed(1)


## 카메라: 활주로 가운데 또는 교통 착륙장을 비스듬히
func _aim(w: WorldView, what: String) -> void:
	var city: City3D = w.city
	var g: SiteGround = w.ground
	var p := Vector2.ZERO
	var dist := 0.45
	if what == "runway" and not city.runway.is_empty():
		p = ((city.runway["a"] as Vector2) + (city.runway["b"] as Vector2)) * 0.5 - (city.runway["b"] - city.runway["a"]).normalized() * 500.0
		dist = 1.6
	else:
		var pad: Vector3 = city.traffic._transit_pad()
		p = Vector2(pad.x, pad.y)
	var r_m := g.radius_m()
	var dir := (g.site_dir() * r_m + g.site_frame().x * p.x + g.site_frame().y * p.y).normalized()
	w._descent.clear()
	w.cam.look_at_surface(g.body, dir, dist, deg_to_rad(64.0), g.site_frame() * Vector3(-1, -1, 0).normalized())


## 그 갈래의 탈것이 땅에 (max_z m 아래로) 내려오면 시간을 멈추고 카메라를 그 탈것 가까이에 (dist km, 기울기 °)
func _agent_close(w: WorldView, role: String, max_z: float, dist: float, tilt_deg: float) -> bool:
	for a in w.city.traffic.agents:
		var p: Vector3 = a["pos"]
		if a["role"] == role and p.z < max_z:
			main._set_speed(0)
			var g: SiteGround = w.ground
			var dir := (g.site_dir() * g.radius_m() + g.site_frame().x * p.x + g.site_frame().y * p.y).normalized()
			w._descent.clear()
			w.cam.look_at_surface(g.body, dir, dist, deg_to_rad(tilt_deg), g.site_frame() * Vector3(-1, -1, 0).normalized())
			return true
	return false


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
			["seoul_night", func(): _until_night("metro_seoul")],
			["newyork", func(): w.fly_to_metro("metro_newyork"), func(): return _metro_done(w, "metro_newyork")],
			["paris", func(): w.fly_to_metro("metro_paris"), func(): return _metro_done(w, "metro_paris")],
			["tokyo", func(): w.fly_to_metro("metro_tokyo"), func(): return _metro_done(w, "metro_tokyo")],
			["naro", func(): _go_base("earth_naro"), func(): return not w.cam.flying() and w._descent.is_empty()],
			["naro_runway", func(): _arrive("earth_naro", "feeder:earth_naro~metro_seoul"); _aim(w, "runway"),
				func(): return _agent_close(w, "plane", 0.5, 0.35, 66.0)],
			["moon", func(): main._set_speed(0); _go_base("moon_shackleton"), func(): return not w.cam.flying() and w._descent.is_empty()],
			["moon_shuttle", func(): _arrive("moon_shackleton", "shuttle:earth_naro~moon_shackleton"); _aim(w, "pad"),
				func(): return _agent_close(w, "transit_lander", 12.0, 0.22, 62.0)],
		]
		if not only.is_empty():
			_steps = _steps.filter(func(st: Array) -> bool: return String(st[0]) in only)
			if _steps.is_empty():
				push_error("no such step: " + ",".join(only))
				quit(1)
				return true
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
