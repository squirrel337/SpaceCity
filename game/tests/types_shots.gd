extends SceneTree
## 건물 145종 스크린숏 — 새 종류를 한 기씩 세운 기지를 3D와 지도로 찍는다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/types_shots.gd -- --out /tmp/shots

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


## 기지의 한 점(모형 좌표)을 내려다보는 시점
func _look_at_xy(w: WorldView, g: Vector2, alt_km: float, tilt_deg: float, heading := Vector3(-0.2, -1.0, 0.0)) -> void:
	var r_m := MoonSurface.R_KM * 1000.0
	var dir := (w.moon.site_dir() * r_m + w.moon.site_frame() * Vector3(g.x, g.y, 0.0)).normalized()
	w.cam.look_at_surface("moon", dir, alt_km, deg_to_rad(tilt_deg), w.moon.site_frame() * heading)


func _center_of(fams: Array) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for e in main.plan.buildings:
		if GameData.family(String(e["id"])) in fams:
			sum += Vector2(e["x"], e["y"])
			n += 1
	return sum / maxi(n, 1)


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "new")
		main.modal.visible = false
		var sim: CitySim = main.sim
		# 해가 드는 낮으로
		var guard := 0
		while sim.is_dark() and guard < 24 * 20:
			sim.advance_hour()
			guard += 1
		for mid in sim.M:
			if GameData.family(mid) != mid:
				sim.counts[mid] = 1
				if GameData.family(mid) == "solar_tower":
					var t := sim.free_tile()
					if t != "":
						sim.tiles[t] = int(sim.tiles.get(t, 0)) + 1
		sim.refresh()
		main.plan.sync(sim)
		main._set_speed(0)
		main._set_view("world")
		_steps = [
			["types_core", func(): _look_at_xy(w, _center_of(["hab_module", "regolith_dome", "storm_shelter"]), 0.15, 55.0)],
			["types_life", func(): _look_at_xy(w, _center_of(["electrolyzer", "co2_scrubber", "sabatier", "water_recycler", "tank_farm"]), 0.13, 55.0)],
			["types_farm", func(): _look_at_xy(w, _center_of(["hydroponics", "algae_reactor", "food_store"]), 0.13, 55.0)],
			["types_power", func(): _look_at_xy(w, _center_of(["fission_40kw", "fission_1mw", "battery_bank", "rfc_unit", "radiator"]), 0.2, 55.0)],
			["types_industry", func(): _look_at_xy(w, _center_of(["excavator", "regolith_printer", "mre_plant", "parts_fab", "robot_bay", "propellant_plant"]), 0.16, 55.0)],
			["types_civic", func(): _look_at_xy(w, _center_of(["research_lab", "green_commons", "comms_center", "medical_bay"]), 0.15, 55.0)],
			["types_ridge", func(): _look_at_xy(w, _center_of(["solar_tower"]) + Vector2(70, 70), 0.3, 60.0, Vector3(-1.0, -1.0, 0.0))],
			["types_map", func():
				main._set_view("map")
				w.plan_fit()],
			["types_map_core", func():
				w.plan_look(main.plan.hub(), 0.22)],
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
		_wait = 10
	else:
		_shot(s[0])
	_step += 1
	return false
