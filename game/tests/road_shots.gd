extends SceneTree
## 길 재건축 스크린숏 — 고가 대로 노선 공사(기둥 → 덱, 크레인), 길 넓히기(차단막), 다 지은 고가·모노레일과 열차
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/road_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var _line: Dictionary = {}
var _widen: Dictionary = {}
var _mono := PackedVector2Array()


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


## 고가 대로 노선 공사(공정 70%)와 가장 붐비는 도로 넓히기를 함께 연다
func _open_works() -> void:
	var sim: CitySim = main.sim
	var plan: CityPlan = main.plan
	var c: Dictionary = main.colonies.list[main.active]
	var lines: Array = RoadWorks.data()["lines"]
	var p0: float = lines[0]["min_pop"]
	lines[0]["min_pop"] = 0.0
	RoadWorks.start_next(c)
	lines[0]["min_pop"] = p0
	if not plan.works.is_empty():
		_line = plan.works[0]
		_line["p"] = 0.72
	var wd: Dictionary = RoadWorks.data()["widen"]
	var run := RoadWorks.widen_run(plan, {"steps": wd["steps"], "load": {"path": 0.0, "street": 0.0}})
	if not run.is_empty():
		_widen = {"kind": "widen", "a": run["a"], "b": run["b"], "from": run["from"], "type": run["type"], "p": 0.4,
			"days": 6.0, "len": (run["a"] as Vector2).distance_to(run["b"]), "cost": {}}
		plan.works.append(_widen)
	plan.works_rev += 1
	print("works ", plan.works.size(), " sim pop ", int(sim.population()))


## 공사를 다 끝내고 모노레일 노선을 하나 더 놓는다 (열차가 다닌다)
func _finish_works() -> void:
	var sim: CitySim = main.sim
	var plan: CityPlan = main.plan
	for _i in 400:
		RoadWorks.advance(plan, sim)
		if plan.works.is_empty():
			break
	_mono = RoadWorks.plan_line(plan, "monorail")
	if not _mono.is_empty():
		plan.add_road(_mono[0], _mono[1], CityPlan.SNAP_M, "monorail")


func _mid(w: Dictionary) -> Vector2:
	return (w["a"] as Vector2).lerp(w["b"], 0.5) if not w.is_empty() else main.plan.hub()


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
		sim.stock["parts"] = 5000.0
		sim.stock["metal_t"] = 200.0
		main._set_speed(0)
		main._set_view("world")
		_open_works()
		_steps = [
			["roadworks_line", func(): _look_at_xy(w, _mid(_line), 0.12, 50.0)],
			["roadworks_widen", func(): _look_at_xy(w, _mid(_widen), 0.08, 50.0)],
			["roadworks_done", func():
				_finish_works()
				_look_at_xy(w, _mid(_line), 0.16, 55.0)],
			["roadworks_monorail", func():
				var at: Vector2 = _mono[0].lerp(_mono[1], 0.12) if not _mono.is_empty() else _mid(_line)
				_look_at_xy(w, at, 0.05, 40.0)],
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
		_wait = 30
	else:
		_shot(s[0])
	_step += 1
	return false
