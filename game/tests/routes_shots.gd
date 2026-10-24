extends SceneTree
## 정기 교역 스크린숏 — 헬라스에서 예제로를 세우고 헬라스 → 예제로 식량, 나로 → 섀클턴 부품을 정해 며칠 흘린 뒤의 교통 탭
## (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/routes_shots.gd -- --out /tmp/shots

var main: Control
var frame := 0
var out_dir := "user://shots"
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
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
		var col: Colonies = main.colonies
		var hel: CitySim = col.list[col.index_of_site("mars_hellas")]["sim"]
		hel.stock["parts"] = maxf(hel.stock["parts"], 2000.0)
		hel.support = maxf(hel.support, 3000.0)
		col.launch("mars_jezero")
		col.in_transit("mars_jezero")["arrive"] = col.hour + 24
		_run_hours(48)
		hel.stock["food_kg"] = float(hel.caps.get("food_kg", 20000.0)) * 0.9
		print("route: ", CityRoutes.add(col, "mars_hellas", "mars_jezero", "food_kg", 2.0, 3))
		var naro: CitySim = col.list[col.index_of_site("earth_naro")]["sim"]
		naro.stock["parts"] = maxf(float(naro.stock.get("parts", 0.0)), 1500.0)
		print("route: ", CityRoutes.add(col, "earth_naro", GameData.HOME_SITE, "parts", 40.0, 7))
		_run_hours(24 * 8)
		main._set_speed(0)
		main.modal.visible = false
		main._select_tab("transport")
		_wait = 30
		return false
	if frame < 4:
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 20:
			var l := _find_label(main, "정기 교역 · 2")
			if l != null:
				main.panel_scroll.scroll_vertical = int(l.global_position.y - main.panel_scroll.global_position.y) + main.panel_scroll.scroll_vertical - 8
		return false
	root.get_texture().get_image().save_png(out_dir.path_join("routes_tab.png"))
	print("shot routes_tab")
	quit(0)
	return true


func _find_label(n: Node, text: String) -> Control:
	if n is Label and (n as Label).text == text:
		return n
	for ch in n.get_children():
		var f := _find_label(ch, text)
		if f != null:
			return f
	return null
