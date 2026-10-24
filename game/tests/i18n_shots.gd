extends SceneTree
## 영어 화면 스크린숏 — 언어를 영어로 (설정은 바꾸지 않는다) 놓고 새 게임 카드, 3D 도시, 개척·교통 탭, 항로 지도, 튜토리얼, 설정
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/i18n_shots.gd -- --out /tmp/shots [--lang en]

var main: Control
var frame := 0
var out_dir := "user://shots"
var lang := "en"
var _steps: Array = []
var _step := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--lang")
	if i >= 0 and i + 1 < args.size():
		lang = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	I18n.apply(lang)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_hours(n: int) -> void:
	for _i in range(n):
		if main.modal.visible:
			main.modal.visible = false
		main._step()
	main._refresh_live()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		I18n.apply(lang)              # main._ready가 설정의 언어로 되돌렸다
		_steps = [
			["%s_start" % lang, func(): main._show_start()],
			["%s_city" % lang, func():
				main.modal.visible = false
				main._on_modal_choice("start", "auto")
				main._set_speed(0)
				_run_hours(24 * 20)
				main.modal.visible = false],
			["%s_colony" % lang, func(): main._select_tab("colony")],
			["%s_transport" % lang, func(): main._select_tab("transport")],
			["%s_map" % lang, func():
				main._set_view("map")
				main.dv_map.selected = "mars"
				main.dv_map.refresh(true)],
			["%s_tutorial" % lang, func():
				main._set_view("world")
				main._select_tab("life")
				main.tutorial.start()
				main.tutorial._enter(5)],
			["%s_settings" % lang, func():
				main.tutorial.cancel()
				main.settings_panel.open()],
		]
		_wait = 20
		return false
	if frame < 3 or _steps.is_empty():
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
		_wait = 24
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	_step += 1
	return false
