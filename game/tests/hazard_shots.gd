extends SceneTree
## 재난·탐사 스크린숏 — 막 일어난 재난 다섯(운석·월진·먼지 회오리·화재·압력 누출)의 흔적, 탐사지 표지와 나간 탐사대,
## 개척 탭의 둘레 탐사 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/hazard_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var _scroll_to := ""


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


## 재난 다섯을 일으키고 (몇 시간 전에 일어난 것처럼) 탐사대를 가장 가까운 탐사지로 보내 가는 길의 가운데쯤에 둔다
func _place() -> void:
	var sim: CitySim = main.sim
	var c: Dictionary = main.colonies.list[main.active]
	var plan: CityPlan = c["plan"]
	var ages := {"meteor": 3, "quake": 2, "dust_devil": 5, "fire": 6, "blowout": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for id in ages:
		if CityHazards.strike(c, id, rng):
			plan.scars[-1]["hour"] = sim.hour - int(ages[id])
	var st := CityExplore.state(c)
	sim.stock["parts"] = maxf(float(sim.stock["parts"]), 500.0)
	var best := 0
	for k in (st["sites"] as Array).size():
		if CityExplore.site_pos(st["sites"][k]).distance_to(plan.hub()) < CityExplore.site_pos(st["sites"][best]).distance_to(plan.hub()):
			best = k
	st["sites"][(best + 3) % 6]["state"] = "found"
	CityExplore.send(c, best)
	var trip: Dictionary = st["trip"]
	trip["depart"] = int(trip["depart"]) - int((int(trip["arrive"]) - int(trip["depart"])) * 0.55)
	print("scars ", plan.scars.size(), " trip ", trip)


func _scar_center() -> Vector2:
	var sum := Vector2.ZERO
	var plan: CityPlan = main.plan
	for w in plan.scars:
		sum += ((w["a"] as Vector2) + (w["b"] as Vector2)) * 0.5
	return sum / maxf(plan.scars.size(), 1)


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
			["hazards_city", func(): _look_at_xy(w, _scar_center(), 0.5, 50.0)],
			["hazards_meteor", func():
				var m: Dictionary = main.plan.scars[0]
				_look_at_xy(w, m["a"], 0.14, 50.0)],
			["explore_sites", func(): _look_at_xy(w, main.plan.hub(), 4.2, 35.0)],
			["explore_colony_tab", func():
				main._select_tab("colony")
				_scroll_to = "둘레 탐사"],
		]
		_wait = 60
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		if _scroll_to != "" and _wait == 20:
			var l := _find_label(main, _scroll_to)
			if l != null:
				main.panel_scroll.ensure_control_visible(l.get_parent().get_parent())
			_scroll_to = ""
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 40
	elif s[0] == "explore_colony_tab":
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	else:
		_shot(s[0])
	_step += 1
	return false


func _find_label(n: Node, text: String) -> Control:
	if n is Label and (n as Label).text == text:
		return n
	for ch in n.get_children():
		var f := _find_label(ch, text)
		if f != null:
			return f
	return null
