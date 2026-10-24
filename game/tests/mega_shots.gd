extends SceneTree
## 메가프로젝트 스크린숏 — 다 지은 대형 돔·전파 접시·회전 고리·궤도 승강기와 짓는 중인 질량 투사기 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/mega_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0


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


var _cells: Array = []


## 땅 구역 다섯을 사서 넷은 다 지은 메가프로젝트, 하나는 짓는 중(질량 투사기 2단계 반)으로 둔다
func _place() -> void:
	var sim: CitySim = main.sim
	var plan: CityPlan = main.plan
	var c: Dictionary = main.colonies.list[main.active]
	sim.stock["parts"] = 20000.0
	sim.support = 20000.0
	for id in ["grand_dome", "deep_array", "spin_ring", "space_lift", "mass_driver"]:
		if not CityProgress._buy_site(c):
			break
		var cell := CityProgress.site_for(plan)
		plan.clear_parcel_roads(cell)
		if id == "mass_driver":
			plan.mega.append({"id": id, "cell": cell, "stage": 1, "p": 0.5})
		else:
			plan.mega_done.append({"id": id, "cell": cell})
		_cells.append(cell)
	plan.mega_rev += 1
	plan._touch()
	print("mega sites ", _cells.size())


func _center() -> Vector2:
	var sum := Vector2.ZERO
	for cell in _cells:
		sum += main.plan.parcel_rect(cell).get_center()
	return sum / maxf(_cells.size(), 1)


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
		main._set_speed(0)
		main._set_view("world")
		_place()
		_steps = [
			["mega_all", func(): _look_at_xy(w, _center(), 0.55, 55.0)],
			["mega_dome", func(): _look_at_xy(w, main.plan.parcel_rect(_cells[0]).get_center(), 0.16, 45.0)],
			["mega_driver", func(): _look_at_xy(w, main.plan.parcel_rect(_cells[-1]).get_center(), 0.18, 45.0)],
			["mega_colony_tab", func():
				var c: Dictionary = main.colonies.list[main.active]
				CityServices.apply(c)
				CityProgress.check(c, main.sim.current_day())
				main._select_tab("colony")],
		]
		_wait = 60
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
		_wait = 40
	elif s[0] == "mega_colony_tab":
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	else:
		_shot(s[0])
	_step += 1
	return false
