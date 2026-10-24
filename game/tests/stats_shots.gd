extends SceneTree
## 통계 스크린숏 — 자동 운영으로 여덟 달을 흘린 뒤 기록 탭의 통계 (가리킨 날의 세로선·값 읽기), 아래쪽의 모든 도시 정착민
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/stats_shots.gd -- --out /tmp/shots

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


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main.modal.visible = false
		main._set_speed(0)
		for _h in 24 * 240:
			if main.modal.visible:
				main.modal.visible = false
				if main.modal.context == "storm":
					main._on_modal_choice("storm", "lottery")
			main._step()
		main.modal.visible = false
		_steps = [
			["stats_top", func():
				main._select_tab("log")
				main.tabs["log"]._set_view("stats")
				main.tabs["log"].stats._on_hover(150)],
			["stats_bottom", func():
				main.panel_scroll.scroll_vertical = 100000],
		]
		_wait = 20
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
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	_step += 1
	return false
