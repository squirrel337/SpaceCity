extends SceneTree
## 이름 있는 정착민·이야기 스크린숏 — 이야기 결정 카드, 개척 탭의 '사람들' (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/people_shots.gd -- --out /tmp/shots

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


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		main._on_modal_choice("start", "new")
		main.modal.visible = false
		main._set_speed(0)
		var c: Dictionary = main.colonies.list[main.active]
		_steps = [
			["people_event", func():
				CityPeople.state(c)["next"] = 0
				for _h in 30:
					main._step()
					if main.modal.visible and main.modal.context == "event":
						break],
			["people_card", func():
				main.modal.visible = false              # 단추를 누른 것처럼 (창을 닫고 고른다)
				main._on_modal_choice("event", "0")
				main._select_tab("colony")
				_scroll_to = "사람들 — 이름 있는 정착민"],
		]
		_wait = 20
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
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
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
