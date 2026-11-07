extends SceneTree
## 보기·접근성 스크린숏 — 설정 카드의 '보기 · 접근성', 녹색약 팔레트의 도시 화면(경고·위험 지표의 표시), 크게 · 영어의 옆 패널,
## 끝나면 설정을 기본으로 돌린다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/access_shots.gd -- --out /tmp/shots

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
			["access_settings", func():
				main._on_modal_choice("start", "auto")
				main._set_speed(0)
				for _h in 24 * 45:
					if main.modal.visible:
						main.modal.visible = false
						if main.modal.context == "storm":
							main._on_modal_choice("storm", "lottery")
					main._step()
				main.modal.visible = false
				main._refresh_live()
				main.settings_panel.open()],
			["access_deutan", func():
				main.settings_panel.close()
				main._on_access_changed("cvd", "deutan")
				var s: CitySim = main.sim
				s.stock["food_kg"] = s.population() * float(s.PER["food_kg"]) * 2.0      # 위험 (식량 2일)
				s.stock["o2_kg"] = s.population() * float(s.PER["o2_kg"]) * 9.0         # 경고 (산소 9일)
				main._refresh_live()
				main._select_tab("life")],
			["access_large_en", func():
				main._on_access_changed("cvd", "")
				main._on_access_changed("font", "large")
				I18n.apply("en")
				main._on_lang_changed()
				main._select_tab("colony")
				main._refresh_live()],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		main._on_access_changed("font", "normal")
		I18n.apply("ko")
		Settings.set_value("ui/cvd", "")
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 40
	else:
		root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
		print("shot ", s[0], " font ", Access.font_k, " cvd ", Palette.kind, " two rows ", main._two_rows)
	_step += 1
	return false
