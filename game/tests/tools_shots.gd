extends SceneTree
## 철거·옮기기 도구 스크린숏 — 철거할 건물을 고른 모습(빨간 표시·'헐기'), 집어 든 건물을 새 자리로 옮기는 모습(호박색 옛 자리·유령)
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/tools_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var _target := {}


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


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "new")
		main.modal.visible = false
		main._set_speed(0)
		main._set_view("world")
		for e in main.plan.buildings:
			if int(e["seq"]) < 0 and String(e["id"]) == "research_lab":
				_target = e
		if _target.is_empty():
			_target = main.plan.buildings[0]
		var at := Vector2(float(_target["x"]), float(_target["y"]))
		_steps = [
			["tool_demolish", func():
				_look_at_xy(w, at, 0.16, 50.0)
				main._begin_tool("demolish")
				main.tool.click(at)],
			["tool_move", func():
				main._begin_tool("move")
				main.tool.click(at)
				main.tool.hover(at + Vector2(-30, 25))],
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
	else:
		_shot(s[0])
	_step += 1
	return false
