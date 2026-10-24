extends SceneTree
## 시나리오 스크린숏 — 시나리오 고르기 창, 진행 중인 판(3D 화면의 목표 줄·개척 탭의 시나리오 카드), 이긴 판의 결과 창
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/scenario_shots.gd -- --out /tmp/shots

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
	Scenario.records_path = "user://records_shots.json"
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		_steps = [
			["scenario_pick", func():
				main._on_modal_choice("start", "scenario")],
			["scenario_running", func():
				main._on_modal_choice("scenarios", "first_year")
				for _h in 24 * 50:
					if main.modal.visible:
						main.modal.visible = false
						if main.modal.context == "storm":
							main._on_modal_choice("storm", "lottery")
					main._step()
				main.modal.visible = false
				main._select_tab("colony")
				main._refresh_live()],
			["scenario_won", func():
				(main.colonies.list[0]["sim"] as CitySim).cohorts.append([120.0, 0.0, false])
				for _h in 24:
					if main.modal.visible and main.modal.context != "scenario_end":
						main.modal.visible = false
					main._step()],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Scenario.records_path))
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 40
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0], " modal ", main.modal.visible, " ", main.modal.context)
	_step += 1
	return false
