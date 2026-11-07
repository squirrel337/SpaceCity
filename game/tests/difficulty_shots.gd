extends SceneTree
## 난이도 스크린숏 — 새 게임의 난이도 창, 샌드박스로 시작한 판(3D 화면 왼쪽 위의 난이도·건설 탭), 메뉴의 난이도 바꾸기 창,
## 영어 난이도 창 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/difficulty_shots.gd -- --out /tmp/shots

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
		I18n.apply("ko")
		_steps = [
			["difficulty_pick", func():
				main._on_modal_choice("start", "new")],
			["difficulty_sandbox", func():
				main._on_modal_choice("difficulty", "sandbox")
				for _h in 24 * 20:
					if main.modal.visible:
						main.modal.visible = false
					main._step()
				main.modal.visible = false
				main._select_tab("build")
				main._refresh_live()],
			["difficulty_change", func():
				main._on_modal_choice("menu", "difficulty")],
			["difficulty_pick_en", func():
				main.modal.visible = false
				I18n.apply("en")
				main._on_modal_choice("start", "random")],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		I18n.apply("ko")
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 40
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0], " modal ", main.modal.visible, " ", main.modal.context, " difficulty ", main.colonies.difficulty)
	_step += 1
	return false
