extends SceneTree
## 영어 빈틈 찾기 — 영어로 놓고 자동 운영으로 며칠씩 흘리며 탭·보기·카드·창을 차례로 열고, 화면에 왔는데 한글이 남은 글을 모은다
## (I18n.record). 디스플레이가 있으면 직접 그리는 글(3D 지도·그래프)까지 모인다.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/i18n_misses.gd -- --out /tmp/misses.json [--days 120]

var main: Control
var frame := 0
var out_path := "user://i18n_misses.json"
var days := 120
var _plan: Array = []
var _i := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_path = args[i + 1]
	i = args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_hours(n: int) -> void:
	for _k in range(n):
		if main.modal.visible:
			main.modal.visible = false
		main._step()
	main._refresh_live()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		I18n.apply("en")
		I18n.record = true
		I18n.misses.clear()
		_plan = [
			func(): main._show_start(),
			func():
				main.modal.visible = false
				main._on_modal_choice("start", "auto")
				main._set_speed(0),
			func(): main._show_scenarios(),
			func():
				main.modal.visible = false
				main._show_help(),
			func():
				main.modal.visible = false
				main._show_menu(),
			func():
				main.modal.visible = false
				main._on_module_tapped("hab_module"),
			func(): main.modal.visible = false,
		]
		var tabs := ["life", "power", "build", "research", "colony", "transport", "log"]
		var chunk := maxi(1, days / 10)
		for d in 10:
			var tab: String = tabs[d % tabs.size()]
			_plan.append(func():
				_run_hours(24 * chunk)
				main.modal.visible = false
				main._select_tab(tab))
		_plan.append(func(): main._select_tab("log"))
		_plan.append(func(): main.tabs["log"]._set_view("stats") if main.tabs["log"].has_method("_set_view") else null)
		_plan.append(func(): main.tabs["log"]._set_view("ops") if main.tabs["log"].has_method("_set_view") else null)
		_plan.append(func():
			main._set_view("map")
			main.dv_map.selected = "mars"
			main.dv_map.refresh(true))
		_plan.append(func():
			main.dv_map.selected = "n:moon_s"
			main.dv_map.refresh(true))
		_plan.append(func():
			main._set_view("list"))
		_plan.append(func():
			main._set_view("world")
			main.tutorial.start())
		for st in range(1, 11):
			var k: int = st
			_plan.append(func(): main.tutorial._enter(k))
		_plan.append(func():
			main.tutorial.cancel()
			main.settings_panel.open())
		_plan.append(func():
			main.settings_panel.close()
			for c in main.colonies.list.size():
				main._on_colony_view(c)
				_run_hours(2)
				main._select_tab("colony"))
		_wait = 5
		return false
	if frame < 3 or _plan.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= _plan.size():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(I18n.misses, "\t"))
		f.close()
		# 번역한 글 모두 (원문 → 영어) — 틀이 엉뚱하게 맞은 것을 눈으로 찾을 때
		var all_path := out_path.get_basename() + "_seen.json"
		var f2 := FileAccess.open(all_path, FileAccess.WRITE)
		f2.store_string(JSON.stringify(I18n.seen, "\t"))
		f2.close()
		print("misses %d · seen %d → %s" % [I18n.misses.size(), I18n.seen.size(), out_path])
		quit(0)
		return true
	(_plan[_i] as Callable).call()
	_i += 1
	_wait = 6
	return false
