extends SceneTree
## 식민지 스크린숏 — 천체마다 기본 도시가 있는 세계에서: 화성 헬라스에서 예제로로 로버 행렬을 보내고(시험이라 하루 만에
## 도착), 타이탄 아디리에서 크라켄 해로 가는 행렬은 이동 중으로 둔다. 행성 단위의 도시 점, 화성 도시로 날아가 내려앉기,
## 화성 도시, 개척 탭, 세레스·지구 도시, 고향으로 돌아오기를 찍는다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/colony_shots.gd -- --out /tmp/shots [--days 120]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 120
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


## 시험: 떠나는 도시에 기술·비용을 채우고 (행성 사이면 발사 창을 지금 열어) 원정대를 보낸다. quick이면 하루 만에 도착
func _send(site_id: String, quick := true) -> void:
	var col: Colonies = main.colonies
	var r := col.route(site_id)
	if r["mode"] == "":
		return
	var src: CitySim = col.list[int(r["from"])]["sim"]
	for t in col.missing_techs(site_id, r):
		src.techs[t] = true
	src.support = maxf(src.support, 9000.0)
	src.stock["parts"] = maxf(src.stock["parts"], 3000.0)
	src.stock["metal_t"] = maxf(src.stock["metal_t"], 50.0)
	var now_d := col.hour / 24.0
	col._windows[site_id] = {"best": now_d, "start": now_d - 1.0, "end": now_d + 1.0, "half": 1.0}
	if col.launch(site_id) and quick:
		col.expeditions[-1]["arrive"] = col.hour + 24


func _to_light(s: CitySim) -> void:
	var guard := 0
	while s.is_dark() and guard < 24 * 40:
		main._step()
		guard += 1


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		_run_hours(days * 24)
		_send("mars_jezero")
		_run_hours(24 * 3)
		_send("titan_kraken", false)         # 이동 중인 로버 행렬
		_run_hours(24 * 2)
		main._set_speed(0)
		main.modal.visible = false
		main._set_view("world")
		var col: Colonies = main.colonies
		var mars_i := col.index_of_site("mars_hellas")
		var ceres_i := col.index_of_site("ceres_occator")
		var earth_i := col.index_of_site("earth_naro")
		var mars := func() -> CitySim: return col.list[mars_i]["sim"]
		_steps = [
			["inner_system", func(): w.cam.look_from_space("sun", 3.4e8, 0.9, 0.75)],
			["moon_globe", func(): w.cam.look_from_space("moon", 1737.4 * 3.2, 0.6, -0.9)],
			["mars_globe", func():
				_to_light(mars.call())
				w.cam.look_from_space("mars", 3389.5 * 3.0, deg_to_rad(70.5) + 0.3, -0.55)],
			["fly_mid", func(): main._on_colony_view(mars_i), func(): return w.cam._fly.get("t", 1.0) > 0.55],
			["landing", func(): pass, func(): return not w.cam.flying() and float(w._descent.get("t", 0.0)) > 0.5],
			["mars_city", func(): pass, func(): return not w.cam.flying() and w._descent.is_empty()],
			["colony_tab", func(): main._select_tab("colony")],
			["ceres_city", func(): main._on_colony_view(ceres_i), func(): return not w.cam.flying() and w._descent.is_empty()],
			["earth_city", func(): main._on_colony_view(earth_i), func(): return not w.cam.flying() and w._descent.is_empty()],
			["back_home", func(): main._on_colony_view(0), func(): return not w.cam.flying() and w._descent.is_empty()],
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
		_shot("colony_%02d_%s" % [_step / 2 + 1, s[0]], s[0] == "colony_tab")
	_step += 1
	return false
