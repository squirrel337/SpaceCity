extends SceneTree
## 화면 확인용 스크린숏 — 실제 메인 씬을 띄워 상태별로 PNG를 남긴다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/screenshots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_days(n: int) -> void:
	for _i in range(n * 24):
		main._step()
		if main.modal.visible:
			break
	main._refresh_live()


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name, " ", img.get_size())


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		6:
			_shot("01_start")
		7:
			main.modal.visible = false
			main._on_modal_choice("start", "new")
			main.sim.enqueue("co2_scrubber", "", 0.0)
			main.sim.enqueue_special("regolith_cover", 0.0)
			main.tabs["research"]._on_prioritize("sintered_construction")
			_run_days(12)
		10:
			_shot("02_life")
		11:
			main._select_tab("power")
			main._refresh_live()
		13:
			_shot("03_power")
		14:
			main._select_tab("build")
			main.tabs["build"]._open["hab_module"] = true     # 계열 하나를 펼쳐 보인다
			main.tabs["build"].rebuild()
			main.panel_scroll.scroll_vertical = 260
			main._refresh_live()
		16:
			_shot("04_build")
		17:
			main._select_tab("research")
			main._refresh_live()
		19:
			_shot("05_research")
		20:
			_run_days(40)
			main._refresh_live()
		23:
			_shot("06_storm")
		24:
			main.modal.visible = false
			main._on_modal_choice("storm", "lottery")
			main.auto_button.button_pressed = true
			_run_days(140)
			main._select_tab("life")
			main._refresh_live()
		27:
			_shot("07_autopilot_day190")
		28:
			main._on_module_tapped("hab_module")
		30:
			_shot("08_module")
		31:
			quit(0)
	return false
