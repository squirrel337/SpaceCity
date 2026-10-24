extends SceneTree
## 항로 지도 스크린숏 — 기본 도시로 시작해 며칠 흐른 뒤: 화성 항로를 고른 항로 지도, 달 표면, 칼리스토 항로, 교통 탭의 함대
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/dvmap_shots.gd -- --out /tmp/shots [--days 40]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 40
var _steps: Array = []
var _step := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
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
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main.modal.visible = false
		main._set_speed(0)
		_run_hours(days * 24)
		main._set_speed(0)
		main.modal.visible = false
		var m: DvMapView = main.dv_map
		_steps = [
			["dvmap_mars", func():
				main._set_view("map")
				m.selected = "mars"
				m.refresh(true)],
			["dvmap_moon", func():
				m.selected = "n:moon_s"
				m.refresh(true)],
			["dvmap_callisto", func():
				m.selected = "callisto"
				m.refresh(true)],
			["fleet_tab", func():
				main._set_view("world")
				main._select_tab("transport")
				var l := _find_label(main, "함대 · 배", true)
				if l != null:
					main.panel_scroll.scroll_vertical = int(l.global_position.y - main.panel_scroll.global_position.y) \
						+ main.panel_scroll.scroll_vertical - 8],
		]
		_wait = 10
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
		_wait = 12
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0])
	_step += 1
	return false


func _find_label(n: Node, text: String, prefix := false) -> Control:
	if n is Label and ((n as Label).text == text or (prefix and (n as Label).text.begins_with(text))):
		return n
	for ch in n.get_children():
		var f := _find_label(ch, text, prefix)
		if f != null:
			return f
	return null
