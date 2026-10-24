extends SceneTree
## 튜토리얼 스크린숏 — 새 게임 카드, 지표·시간·짓기·항로 지도 단계 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/tutorial_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var _old: Variant


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_old = Settings.value("tutorial/done", false)
	Settings.set_value("tutorial/done", false)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		_steps = [
			["tutorial_start", func(): pass],
			["tutorial_chips", func():
				main.modal.visible = false
				main._on_modal_choice("start", "tutorial")
				main.tutorial._on_next()],
			["tutorial_time", func(): main.tutorial._on_next()],
			["tutorial_build", func():
				main.tutorial._enter(5)],
			["tutorial_map", func():
				main.tutorial._enter(9)],
		]
		_wait = 30
		return false
	if frame < 3 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		Settings.set_value("tutorial/done", _old)
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 20
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	_step += 1
	return false
