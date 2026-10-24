extends SceneTree
## 재건축 스크린숏 — 거주 구획의 낮은 건물을 헐고 고층 타워를 짓는 과정 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/redev_shots.gd -- --out /tmp/shots
## 재건축 세 곳을 함께 열고 공정을 철거 중 · 반 · 거의 다로 맞춘 장면, 다 지은 뒤의 장면

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var _sites: Array = []          # [seq, 자리]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	img.get_region(Rect2i(Vector2i(g.position * k), Vector2i(g.size * k))).save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _look_at_xy(w: WorldView, g: Vector2, alt_km: float, tilt_deg: float, heading := Vector3(-0.2, -1.0, 0.0)) -> void:
	var r_m := MoonSurface.R_KM * 1000.0
	var dir := (w.moon.site_dir() * r_m + w.moon.site_frame() * Vector3(g.x, g.y, 0.0)).normalized()
	w.cam.look_at_surface("moon", dir, alt_km, deg_to_rad(tilt_deg), w.moon.site_frame() * heading)


func _center() -> Vector2:
	var sum := Vector2.ZERO
	for s in _sites:
		sum += s[1]
	return sum / maxf(_sites.size(), 1)


## 재건축 세 곳: 한 도시에 한 곳씩이라 사이마다 진행 표시를 비운다. 공정을 0.1 · 0.55 · 0.9로
func _open_sites() -> void:
	var sim: CitySim = main.sim
	var c: Dictionary = main.colonies.list[main.active]
	var rd := LayoutData.redevelop()
	var p0: float = rd["pressure"]
	rd["pressure"] = 0.0
	for p: float in [0.1, 0.55, 0.9]:
		c["redev"] = -1
		if not CityDev.redevelop(c):
			break
		var e: Dictionary = main.plan.entry_of_seq(int(c["redev"]))
		_sites.append([int(c["redev"]), Vector2(e["x"], e["y"])])
		for item in sim.queue:
			if int(item["seq"]) == int(c["redev"]):
				item["rd"] = float(item["rd_total"]) * (1.0 - p)
	rd["pressure"] = p0
	print("redev sites ", _sites.size())


func _finish() -> void:
	var sim: CitySim = main.sim
	for item in sim.queue:
		item["rd"] = 0.0
		item["print_t"] = 0.0
	sim.work_robots()
	main.plan.sync(sim)


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "new")
		main.modal.visible = false
		var sim: CitySim = main.sim
		var guard := 0
		while sim.is_dark() and guard < 24 * 20:
			sim.advance_hour()
			guard += 1
		sim.techs["local_manufacturing"] = true
		sim.stock["parts"] = 5000.0
		sim.stock["metal_t"] = 200.0
		sim.counts["apartment_block"] = int(sim.counts.get("apartment_block", 0)) + 3
		sim.refresh()
		main.plan.sync(sim)
		main._set_speed(0)
		main._set_view("world")
		_open_sites()
		_steps = [
			["redev_sites", func(): _look_at_xy(w, _center(), 0.16, 52.0)],
			["redev_close", func(): _look_at_xy(w, _sites[1][1] if _sites.size() > 1 else _center(), 0.07, 48.0)],
			["redev_done", func():
				_finish()
				_look_at_xy(w, _center(), 0.16, 52.0)],
		]
		_wait = 40
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
		_wait = 14
	else:
		_shot(s[0])
	_step += 1
	return false
