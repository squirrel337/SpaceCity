extends SceneTree
## 위임·운영 기록·수출 계약 스크린숏 — 직접 운영하며 살림 건설·연구·땅·계약을 맡기고 두 달을 흘린 뒤:
## 개척 탭의 위임 카드, 수출 계약 카드, 기록 탭의 운영 기록 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/ops_shots.gd -- --out /tmp/shots

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


## 직접 운영 도시에 분야 넷을 맡기고 두 달 흘린다 (결정 카드는 추첨으로)
func _run() -> void:
	var c: Dictionary = main.colonies.list[main.active]
	for d in ["build", "research", "land", "trade"]:
		CityAuto.set_delegate(c, d, true)
	for _h in 24 * 60:
		if main.modal.visible:
			main.modal.visible = false
			if main.modal.context == "storm":
				main._on_modal_choice("storm", "lottery")
		main._step()
	main.modal.visible = false
	print("oplog ", (c.get("oplog", []) as Array).size(), " trade ", CityTrade.state(c))


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		main._on_modal_choice("start", "new")
		main.modal.visible = false
		main._set_speed(0)
		_run()
		_steps = [
			["ops_delegate", func():
				main._select_tab("colony")
				_scroll_to = "위임 — 시드에게 맡길 분야"],
			["ops_trade", func():
				main._select_tab("colony")
				_scroll_to = "수출 계약"],
			["ops_log", func():
				main._select_tab("log")
				main.tabs["log"]._set_view("ops")],
		]
		_wait = 30
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
