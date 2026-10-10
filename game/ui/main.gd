extends Control
## SpaceCity 시대 0 프로토타입 — 화면 구성과 게임 루프.
## 규칙은 sim/의 CitySim이 맡고, 여기서는 시간을 흘리고 보여 주고 결정을 받는다.

const SAVE_PATH := "user://spacecity_save.json"
const HOURS_PER_SECOND := [0.0, 3.0, 9.0, 30.0]   # 정지 · 1×(하루 8초) · 3×(2.7초) · 10×(0.8초)
const SPEED_LABELS := ["정지", "1×", "3×", "10×"]
const REPORT_DAY := 1096                            # 3년 보고서
const JUMP_LIMIT_H := 24 * 30
const TABS := [["life", "생명유지"], ["power", "전력"], ["build", "건설"], ["research", "연구"], ["log", "기록"]]

var sim: CitySim
var speed := 0
var _last_speed := 1
var _acc := 0.0
var _jumping := false
var _jump_start := 0
var _last_day := -1
var _ui_clock := 0.0
var _report_shown := false
var _game_over := false
var _alarm_day := -100
var _dirty := true

var city_view: CityView
var base_map: BaseMap
var world: WorldView
var plan: CityPlan
var tool := PlaceTool.new()
var place_bar: PanelContainer
var place_text: Label
var place_reason: Label
var place_buttons := {}
var road_button: Button
var city_area: Control
var view_buttons := {}
var zoom_row: HBoxContainer
var world_row: HBoxContainer
var view_mode := "world"
var forecast: ForecastBar
var modal: Modal
var toasts: VBoxContainer
var speed_buttons: Array[Button] = []
var auto_button: Button
var date_label: Label
var chips := {}
var tabs := {}
var tab_buttons := {}
var current_tab := "life"
var panel_scroll: ScrollContainer


func _ready() -> void:
	theme = ThemeFactory.build()
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	_fit_window()
	_build()
	_show_start()


func _fit_window() -> void:
	## PC: 기본 창(1600×900)이 화면보다 크면 화면의 92%로 줄여 가운데에 둔다
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	var win := window.size
	if win.x <= screen.size.x and win.y <= screen.size.y:
		return
	var k := minf(screen.size.x * 0.92 / win.x, screen.size.y * 0.92 / win.y)
	window.size = Vector2i(int(win.x * k), int(win.y * k))
	window.move_to_center()


# ── 화면 구성 ───────────────────────────────────────────────────
func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_build_top_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	city_area = Control.new()
	city_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	city_area.clip_contents = true
	left.add_child(city_area)
	base_map = BaseMap.new()
	base_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_map.module_tapped.connect(_on_module_tapped)
	city_area.add_child(base_map)
	city_view = CityView.new()
	city_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city_view.module_tapped.connect(_on_module_tapped)
	city_view.visible = false
	city_area.add_child(city_view)
	world = WorldView.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.module_tapped.connect(_on_module_tapped)
	city_area.add_child(world)
	base_map.visible = false
	city_area.add_child(_build_view_switch())
	city_area.add_child(_build_place_bar())
	tool.changed.connect(_update_place_bar)
	tool.placed.connect(_on_placed)
	forecast = ForecastBar.new()
	forecast.custom_minimum_size.y = 46
	left.add_child(forecast)
	body.add_child(_build_side())
	toasts = VBoxContainer.new()
	toasts.custom_minimum_size.x = 420
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	toasts.alignment = BoxContainer.ALIGNMENT_END
	city_area.add_child(toasts)
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.offset_right = -12
	toasts.offset_bottom = -62          # 왼쪽 아래 단추 줄 위로
	modal = Modal.new()
	modal.chosen.connect(_on_modal_choice)
	add_child(modal)


func _build_view_switch() -> Control:
	## 왼쪽 아래: 3D·지도·목록 전환과 확대 단추
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for pair in [["world", "3D"], ["map", "지도"], ["list", "목록"]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(58, 40)
		b.pressed.connect(_set_view.bind(pair[0]))
		row.add_child(b)
		view_buttons[pair[0]] = b
	road_button = Button.new()
	road_button.text = "도로"
	road_button.toggle_mode = true
	road_button.tooltip_text = "길 내기 — 점을 차례로 눌러 길을 잇는다 (G)"
	road_button.custom_minimum_size = Vector2(58, 40)
	road_button.toggled.connect(func(on: bool):
		if on:
			_begin_road()
		elif tool.mode in ["road", "erase"]:
			tool.stop())
	row.add_child(road_button)
	view_buttons["world"].tooltip_text = "달 위의 도시 — 끌어서 돌리고, 휠·두 손가락으로 확대해 행성과 별까지 (M)"
	view_buttons["map"].tooltip_text = "기지 평면 지도 — 끌어서 옮기고 휠·두 손가락으로 확대 (M)"
	view_buttons["list"].tooltip_text = "모듈 목록 (M)"
	world_row = HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 4)
	row.add_child(world_row)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	world_row.add_child(gap)
	for spec in [["−", "축소", func(): world.zoom_by(1.6)], ["+", "확대", func(): world.zoom_by(1.0 / 1.6)],
			["기지", "기지 위로 (H)", func(): world.home()], ["달", "달 전체", func(): world.show_moon()],
			["지구·달", "지구와 달", func(): world.show_earth_moon()], ["태양계", "태양계", func(): world.show_solar_system()],
			["별", "이웃 별 (25광년)", func(): world.show_neighbors()]]:
		var wb := Button.new()
		wb.text = spec[0]
		wb.tooltip_text = spec[1]
		wb.custom_minimum_size = Vector2(42 if spec[0].length() == 1 else 54, 40)
		wb.pressed.connect(spec[2])
		world_row.add_child(wb)
	zoom_row = HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 4)
	row.add_child(zoom_row)
	var sep := Control.new()
	sep.custom_minimum_size.x = 8
	zoom_row.add_child(sep)
	for pair in [["−", 1.0 / 1.25, "축소"], ["+", 1.25, "확대"]]:
		var z := Button.new()
		z.text = pair[0]
		z.tooltip_text = pair[2]
		z.custom_minimum_size = Vector2(42, 40)
		z.pressed.connect(func(): base_map.zoom_by(pair[1]))
		zoom_row.add_child(z)
	var fit := Button.new()
	fit.text = "전체"
	fit.tooltip_text = "기지 전체 보기"
	fit.custom_minimum_size = Vector2(54, 40)
	fit.pressed.connect(func(): base_map.fit())
	zoom_row.add_child(fit)
	var core := Button.new()
	core.text = "거주구"
	core.tooltip_text = "거주 구역으로"
	core.custom_minimum_size = Vector2(64, 40)
	core.pressed.connect(func(): base_map.focus_core())
	zoom_row.add_child(core)
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = 10
	row.offset_bottom = -10
	view_buttons["world"].set_pressed_no_signal(true)
	zoom_row.visible = false
	return row


## 자리 고르기 막대 (도시 화면 위쪽 가운데): 무엇을 하는 중인지, 놓을 수 없는 까닭, 단추들
func _build_place_bar() -> Control:
	place_bar = PanelContainer.new()
	place_bar.add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.94), Palette.AMBER.darkened(0.3), 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	place_bar.add_child(v)
	place_text = Label.new()
	place_text.add_theme_font_size_override("font_size", 15)
	place_text.add_theme_color_override("font_color", Palette.TEXT)
	v.add_child(place_text)
	place_reason = Label.new()
	place_reason.add_theme_font_size_override("font_size", 13)
	place_reason.add_theme_color_override("font_color", Color(1.0, 0.62, 0.5))
	v.add_child(place_reason)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	for spec in [["here", "여기에 짓기", "고른 자리에 짓는다 (Enter). 마우스는 누르는 곳에 바로 짓는다 — Shift를 누르고 있으면 계속 놓는다"],
			["rotate", "돌리기", "90° 돌린다 (R)"], ["variant", "모양", "같은 기능의 다른 설계 (V)"],
			["auto", "빈자리에", "기본 배치의 빈자리에 바로 짓는다"], ["end", "끝", "이어 가던 길을 끝낸다 (오른쪽 클릭)"],
			["erase", "지우기", "길을 눌러 지운다"], ["close", "닫기", "그만둔다 (Esc)"]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(_on_place_button.bind(spec[0]))
		row.add_child(b)
		place_buttons[spec[0]] = b
	place_buttons["erase"].toggle_mode = true
	place_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	place_bar.offset_top = 8
	place_bar.visible = false
	return place_bar


func _on_place_button(which: String) -> void:
	match which:
		"here":
			tool.commit(false)
		"rotate":
			tool.rotate()
		"variant":
			tool.next_variant()
		"auto":
			tool.auto_place()
		"end":
			tool.end_chain()
		"erase":
			if tool.mode == "erase":
				tool.start_road()
			else:
				tool.start_erase()
		"close":
			tool.stop()


func _update_place_bar() -> void:
	if place_bar == null:
		return
	place_bar.visible = tool.active()
	road_button.set_pressed_no_signal(tool.mode in ["road", "erase"])
	if not tool.active():
		return
	var building := tool.mode == "build"
	place_text.text = tool.status()
	place_reason.text = tool.reason if tool.has_at else ""
	place_reason.visible = place_reason.text != ""
	place_buttons["here"].visible = building
	place_buttons["here"].disabled = not tool.has_at or tool.reason != ""
	place_buttons["rotate"].visible = building
	place_buttons["variant"].visible = building
	place_buttons["auto"].visible = building
	place_buttons["end"].visible = tool.mode == "road"
	place_buttons["end"].disabled = tool.road_from == null
	place_buttons["erase"].visible = not building
	place_buttons["erase"].set_pressed_no_signal(tool.mode == "erase")
	place_bar.reset_size()


## 건물 자리 고르기를 시작한다 (건설 탭의 '짓기', 모듈 카드의 '1기 더 짓기')
func _begin_place(mid: String) -> void:
	if sim == null:
		return
	var reason := sim.build_block_reason(mid, 0.0)
	if reason != "":
		_toast("%s — 지을 수 없다 (%s)" % [sim.M[mid]["name"], reason], "warn")
		return
	if view_mode == "list":
		_set_view("world")
	if view_mode == "world":
		world.ensure_near_base()
	tool.start_build(mid)


func _begin_road() -> void:
	if sim == null:
		return
	if view_mode == "list":
		_set_view("world")
	if view_mode == "world":
		world.ensure_near_base()
	tool.start_road()


func _on_placed(kind: String, ok: bool, text: String) -> void:
	var msg := ""
	if ok:
		msg = "%s — 고른 자리에 공사를 시작한다" % GameData.module_name(kind)
		if sim.stock["parts"] < 40:
			msg += ". 부품 비축이 40 아래다 — 고장 수리가 막힐 수 있다"
		_toast(msg, "good")
	else:
		msg = "%s — 지을 수 없다 (%s)" % [GameData.module_name(kind), text]
		_toast(msg, "warn")
	tabs["build"].message.text = msg
	if tabs[current_tab].has_method("rebuild"):
		tabs[current_tab].rebuild()
	_dirty = true


func _set_view(mode: String) -> void:
	view_mode = mode
	world.visible = mode == "world"
	base_map.visible = mode == "map"
	city_view.visible = mode == "list"
	zoom_row.visible = mode == "map"
	world_row.visible = mode == "world"
	for k in view_buttons:
		view_buttons[k].set_pressed_no_signal(k == mode)
	road_button.visible = mode != "list"
	if mode == "list" and tool.active():
		tool.stop()
	city_view.queue_redraw()


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, Palette.LINE, 10, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	date_label = ThemeFactory.heading("", 18)
	date_label.custom_minimum_size.x = 150
	row.add_child(date_label)
	for i in range(4):
		var b := Button.new()
		b.text = SPEED_LABELS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(48, 42)
		b.pressed.connect(_set_speed.bind(i))
		row.add_child(b)
		speed_buttons.append(b)
	var jump := Button.new()
	jump.text = "다음 사건"
	jump.tooltip_text = "결정할 일이 생길 때까지 시간을 건너뛴다 (최대 30일)"
	jump.custom_minimum_size.y = 42
	jump.pressed.connect(_start_jump)
	row.add_child(jump)
	auto_button = Button.new()
	auto_button.text = "자동 운영"
	auto_button.tooltip_text = "시드가 문서의 추천 운영대로 짓고 연구한다"
	auto_button.toggle_mode = true
	auto_button.custom_minimum_size.y = 42
	auto_button.toggled.connect(_on_auto)
	row.add_child(auto_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 12)
	row.add_child(chip_row)
	for key in ["o2", "co2", "soc", "food", "pop", "morale", "trust"]:
		var chip := _chip()
		chip_row.add_child(chip["box"])
		chips[key] = chip
	var menu := Button.new()
	menu.text = "메뉴"
	menu.custom_minimum_size = Vector2(58, 42)
	menu.pressed.connect(_show_menu)
	row.add_child(menu)
	return bar


func _chip() -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size.x = 58
	var value := Label.new()
	value.add_theme_font_override("font", ThemeFactory.bold)
	value.add_theme_font_size_override("font_size", 16)
	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Palette.MUTED)
	box.add_child(value)
	box.add_child(caption)
	return {"box": box, "value": value, "caption": caption}


func _build_side() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 410
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	side.add_child(v)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	v.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 42
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_select_tab.bind(t[0]))
		tab_row.add_child(b)
		tab_buttons[t[0]] = b
	panel_scroll = ScrollContainer.new()
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(panel_scroll)
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_scroll.add_child(host)
	tabs = {"life": LifePanel.new(), "power": PowerPanel.new(), "build": BuildPanel.new(),
		"research": ResearchPanel.new(), "log": LogPanel.new()}
	for key in tabs:
		tabs[key].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs[key].visible = false
		host.add_child(tabs[key])
	tabs["build"].changed.connect(_on_player_change)
	tabs["build"].place_requested.connect(_begin_place)
	tabs["research"].changed.connect(_on_player_change)
	return side


# ── 새 게임·저장 ─────────────────────────────────────────────────
func _new_game(seed_value: int, autopilot: bool) -> void:
	_attach(CitySim.new(seed_value, 40.0, "good" if autopilot else ""))
	sim.note("관리 기록 — 가동 확인. 정착민 120명. 시드 %d." % seed_value, "info")
	if autopilot:
		sim.note("자동 운영 — 시드가 추천 운영 방침으로 짓고 연구한다", "info")


func _attach(new_sim: CitySim, plan_data: Variant = null) -> void:
	sim = new_sim
	plan = CityPlan.from_save(plan_data, sim)
	tool.bind(sim, plan)
	sim.interactive = true
	sim.noted.connect(_on_note)
	for key in tabs:
		tabs[key].bind(sim)
	city_view.sim = sim
	base_map.set_sim(sim, plan, tool)
	world.set_sim(sim, plan, tool)
	forecast.sim = sim
	auto_button.set_pressed_no_signal(sim.autopilot != null)
	_last_day = sim.current_day()
	_report_shown = sim.current_day() >= REPORT_DAY
	_game_over = false
	_acc = 0.0
	_jumping = false
	for c in toasts.get_children():
		c.queue_free()
	_select_tab("life")
	_set_speed(0)
	_dirty = true
	_refresh_live()


func _save() -> void:
	if sim == null or _game_over:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		var data := sim.to_save()
		data["plan"] = plan.to_save()
		f.store_string(JSON.stringify(data, "", false, true))
		f.close()


func _load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary or int(data.get("version", 0)) != 1:
		return false
	_attach(CitySim.from_save(data), data.get("plan"))
	sim.note("관리 기록 — 저장한 지점에서 다시 가동했다", "info")
	return true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_save()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if modal.visible and modal.context == "menu":
				modal.visible = false
			else:
				_show_menu()


# ── 시간 ───────────────────────────────────────────────────────
func _set_speed(i: int) -> void:
	if speed > 0:
		_last_speed = speed
	speed = i
	base_map.speed_level = i
	world.speed_level = i
	_jumping = false
	for k in range(speed_buttons.size()):
		speed_buttons[k].set_pressed_no_signal(k == i)


func _unhandled_input(event: InputEvent) -> void:
	## PC 단축키 (디자인 08 §5)
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and tool.active() and not modal.visible:
		if tool.mode == "road" and tool.road_from != null:
			tool.end_chain()
		else:
			tool.stop()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if modal.visible and modal.context in ["menu", "help", "module"]:
			modal.visible = false
		elif not modal.visible:
			_show_menu()
		get_viewport().set_input_as_handled()
		return
	if sim == null or modal.visible:
		return
	if tool.active():
		match event.keycode:
			KEY_R:
				tool.rotate()
				get_viewport().set_input_as_handled()
				return
			KEY_V:
				tool.next_variant()
				get_viewport().set_input_as_handled()
				return
			KEY_ENTER, KEY_KP_ENTER:
				if tool.mode == "build":
					tool.commit(event.shift_pressed)
				else:
					tool.end_chain()
				get_viewport().set_input_as_handled()
				return
	match event.keycode:
		KEY_G:
			if tool.mode in ["road", "erase"]:
				tool.stop()
			else:
				_begin_road()
		KEY_SPACE:
			_set_speed(0 if speed > 0 else maxi(1, _last_speed))
		KEY_1:
			_set_speed(1)
		KEY_2:
			_set_speed(2)
		KEY_3:
			_set_speed(3)
		KEY_F:
			_start_jump()
		KEY_B:
			_select_tab("build")
		KEY_R:
			_select_tab("research")
		KEY_L:
			_select_tab("log")
		KEY_M:
			_set_view({"world": "map", "map": "list", "list": "world"}[view_mode])
		_:
			return
	get_viewport().set_input_as_handled()


func _start_jump() -> void:
	if sim == null or modal.visible:
		return
	_set_speed(0)
	_jumping = true
	_jump_start = sim.hour


func _process(delta: float) -> void:
	if sim == null or modal.visible or _game_over:
		return
	var stepped := false
	if _jumping:
		for _i in range(24 * 4):
			_step()
			stepped = true
			if not _jumping or modal.visible:
				break
			if sim.hour - _jump_start >= JUMP_LIMIT_H:
				_jumping = false
				break
	elif speed > 0:
		_acc += delta * HOURS_PER_SECOND[speed]
		var steps := 0
		while _acc >= 1.0 and steps < 64:
			_acc -= 1.0
			_step()
			stepped = true
			steps += 1
			if speed == 0 or modal.visible:
				_acc = 0.0
				break
	_ui_clock += delta
	if stepped:
		_dirty = true
	if _dirty and _ui_clock >= 0.1:
		_ui_clock = 0.0
		_refresh_live()


func _step() -> void:
	sim.advance_hour()
	if not sim.pending_storm.is_empty():
		_jumping = false
		_set_speed(0)
		_show_storm()
		return
	var day := sim.current_day()
	if day != _last_day:
		_last_day = day
		_on_new_day(day)


func _on_new_day(day: int) -> void:
	if tabs[current_tab] is BuildPanel or tabs[current_tab] is ResearchPanel:
		tabs[current_tab].rebuild()
	var pop := sim.population()
	if pop <= 0:
		_end_game("절멸", "시드가 돌보던 정착민이 모두 사라졌다.")
		return
	if sim.trust_low_days >= 365:
		_end_game("시드 정지", "신뢰가 10 아래로 1년이 지났다. 평의회가 시드를 끄기로 했다.")
		return
	var o2_days: float = sim.stock["o2_kg"] / (pop * sim.PER["o2_kg"])
	var food_days: float = sim.stock["food_kg"] / (pop * sim.PER["food_kg"])
	if (o2_days < 3 or food_days < 3) and day - _alarm_day > 2:
		_alarm_day = day
		_set_speed(0)
		_toast("위급 — %s 비축이 3일 아래다" % ("산소" if o2_days < 3 else "식량"), "critical")
	if day >= REPORT_DAY and not _report_shown:
		_report_shown = true
		_set_speed(0)
		_show_report()


# ── 화면 갱신 ───────────────────────────────────────────────────
func _refresh_live() -> void:
	if sim == null:
		return
	_dirty = false
	date_label.text = sim.date_text()
	var pop := sim.population()
	var per := sim.PER
	var o2_days: float = sim.stock["o2_kg"] / (pop * per["o2_kg"]) if pop > 0 else 0.0
	var food_need: float = pop * per["food_kg"]
	var food_days: float = sim.stock["food_kg"] / food_need if food_need > 0 else 0.0
	var made: float = (sim.wk["hydroponics"] * sim.recipe("hydroponics", "out", "food_kg") if sim.crops_alive() else 0.0) \
		+ sim.wk["algae_reactor"] * sim.recipe("algae_reactor", "out", "food_kg")
	var cap := sim.bat_cap + sim.rfc_cap
	var soc := (sim.battery + sim.rfc) / cap if cap > 0 else 0.0
	var ppm := sim.co2_ppm()
	_set_chip("o2", Fmt.days(o2_days), "산소 비축", Palette.level_color(o2_days, 10, 5))
	_set_chip("co2", "%s ppm" % Fmt.n(ppm), "CO₂", Palette.RED if ppm > 5000 else (Palette.AMBER if ppm > 2500 else Palette.TEXT))
	_set_chip("soc", Fmt.pct(soc), "축전" + (" · 그림자" if sim.is_dark() else ""), Palette.level_color(soc, 0.4, 0.15))
	_set_chip("food", Fmt.days(food_days), "식량 · 자급 %s" % Fmt.pct(made / food_need if food_need > 0 else 0.0),
		Palette.level_color(food_days, 20, 7))
	_set_chip("pop", "%d명" % int(pop), "인구 · 주거 %d" % int(sim.housing_cap), Palette.AMBER if pop > sim.housing_cap else Palette.TEXT)
	_set_chip("morale", str(int(round(sim.morale))), "사기", Palette.level_color(sim.morale, 50, 35))
	_set_chip("trust", str(int(round(sim.trust))), "신뢰", Palette.level_color(sim.trust, 40, 30))
	city_view.queue_redraw()
	forecast.queue_redraw()
	tabs[current_tab].update_view()


func _set_chip(key: String, value: String, caption: String, color: Color) -> void:
	chips[key]["value"].text = value
	chips[key]["value"].add_theme_color_override("font_color", color if color != Palette.TEAL else Palette.TEXT)
	chips[key]["caption"].text = caption


func _select_tab(key: String) -> void:
	current_tab = key
	for k in tabs:
		tabs[k].visible = k == key
		tab_buttons[k].set_pressed_no_signal(k == key)
	if sim != null:
		if tabs[key].has_method("rebuild"):
			tabs[key].rebuild()
		tabs[key].update_view()
	panel_scroll.scroll_vertical = 0


func _on_player_change() -> void:
	_dirty = true
	_refresh_live()


func _toast(text: String, kind: String) -> void:
	var color: Color = LogPanel.KIND_COLOR.get(kind, Palette.TEXT)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL_2, 0.94), color.darkened(0.2), 8, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color.lightened(0.15))
	p.add_child(l)
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tween := p.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(p, "modulate:a", 0.0, 0.6)
	tween.tween_callback(p.queue_free)


func _on_note(_hour: int, text: String, kind: String) -> void:
	if kind in ["good", "warn", "critical", "death"]:
		_toast(text, kind)
	if _jumping and kind in ["good", "warn", "critical", "death"]:
		_jumping = false
	if kind == "death":
		_set_speed(0)
		modal.open("death", "사망 사고", "정착민이 죽었다",
			text + "\n\n첫 사망은 캠페인의 큰 사건이다. 신뢰가 크게 떨어지고, 사기는 오래 회복되지 않는다.",
			[["ok", "확인", ""]], Palette.RED)
	_dirty = true


# ── 결정 카드 ───────────────────────────────────────────────────
func _show_start() -> void:
	var choices := []
	if FileAccess.file_exists(SAVE_PATH):
		choices.append(["continue", "이어하기", "저장한 지점에서 계속한다"])
	choices.append(["new", "새로 시작 — 시드 2061", "디자인 문서·밸런스 시뮬레이터와 같은 운으로 시작한다"])
	choices.append(["random", "다른 운으로 시작", "그림자·고장·폭풍·화물선의 운이 달라진다"])
	choices.append(["auto", "시드 자동 운영으로 보기", "추천 운영대로 3년을 돌려 본다. 언제든 '자동 운영'을 꺼서 넘겨받는다"])
	modal.open("start", "시대 0 · 씨앗 — 프로토타입", "섀클턴 시드 시티, 2061년 1월 1일",
		"당신은 달 남극 기지를 돌보도록 만들어진 관리 AI, 시드다. 정착민 120명의 공기와 전력, 식량과 방사선을 책임진다.\n\n" +
		"첫날의 숙제: CO₂ 제거기는 1기뿐이라 농장이 꺼지면 여유가 없다. 41일째에 대형 태양 양성자 폭풍이 오는데 대피소는 80석이다. " +
		"남극 겨울(150~240일째)에는 그림자가 최대 90시간 이어진다. 건설 탭에서 짓고, 연구 탭에서 연구를 고르고, 1×로 시간을 흘린다.",
		choices)


func _show_menu() -> void:
	if sim == null:
		_show_start()
		return
	_set_speed(0)
	modal.open("menu", "메뉴", "일시정지", "저장은 앱을 닫거나 내릴 때 자동으로 된다.", [
		["resume", "계속", ""],
		["save", "지금 저장", ""],
		["help", "도움말", ""],
		["restart", "처음부터 다시", "저장한 게임을 덮어쓴다"],
		["quit", "저장하고 끝내기", ""],
	])


func _show_help() -> void:
	modal.open("help", "도움말", "읽는 법",
		"· 위쪽 숫자는 '여유'다 — 비축 일수와 %. 주황은 주의, 빨강은 위험.\n" +
		"· 일조 예보 막대의 파란 칸이 그림자다. 그림자 속에서는 태양광이 0이 되고 축전으로 버틴다.\n" +
		"· 전력 탭의 절전 문턱: 어두울 때 축전량이 문턱 아래면 4순위(연구) → 3순위(산업) → 2순위(농장) 순으로 끈다. " +
		"농장이 72시간 넘게 꺼지면 작물이 죽는다.\n" +
		"· 대피소가 인구보다 적으면 대형 폭풍 때 대피소 추첨을 해야 한다. 거주 모듈에 레골리스를 덮으면 평소 선량이 준다.\n" +
		"· 누적 선량 600 mSv에 닿은 사람은 다음 유인선으로 귀환한다.\n" +
		"· 신뢰가 30 아래면 위임이 줄고, 10 아래로 1년이 지나면 시드가 정지된다.",
		[["ok", "닫기", ""]])


func _show_storm() -> void:
	var st: Dictionary = sim.pending_storm
	var outside := maxf(0.0, st["pop"] - st["seats"])
	var warning := "8" if sim.techs.has("space_weather_forecast") else "2"
	modal.open("storm", "위급 · 게임 정지  ·  헌장 충돌: 생명 vs 동의", "대피소 추첨",
		"태양 표면에서 큰 플레어. 고에너지 양성자가 약 %s시간 뒤 도착한다.\n대피소 %d석에 정착민 %d명 — 밖에 남는 %d명은 약 %d mSv를 받는다 (지구 자연방사선의 약 %d년치). 평의회를 소집하려면 3시간이 걸린다." % [
			warning, int(st["seats"]), int(st["pop"]), int(outside), int(st["dose"]), int(st["dose"] / 2.4)],
		[["essential", "필수 인력부터 들여보낸다", "생명유지 기술자·의료진 우선. 공유지 연합이 반발한다 (신뢰 −2)"],
		["lottery", "추첨한다", "공정하다. 피폭은 운에 맡긴다"],
		["council", "평의회에 맡긴다", "동의를 지킨다 (신뢰 +3). 결정이 늦어 대피소 안 선량이 2%에서 10%로 늘어난다"]],
		Palette.RED)


func _show_report() -> void:
	var s := sim.summary()
	var body := "인구 %d명 · 신뢰 %d · 평균 사기 %d\n사망 %d명 · 작물 고사 %d회 · 폭풍 때 대피소 밖 연인원 %d명 · 생명유지 감전 %d시간 · 완료한 기술 %d개\n\n" % [
		int(s["population_end"]), int(round(s["trust_end"])), int(round(s["morale_avg"])), int(s["deaths"]), s["crop_losses"],
		int(round(s["exposed_person_events"])), s["brownout_hours"], s["techs"]]
	body += "밸런스 시뮬레이터 200판 평균 — 추천 운영: 인구 313명 · 신뢰 87 / 준비 없는 운영: 인구 201명 · 신뢰 40."
	modal.open("report", "2063년 말 · 3년 보고서", "첫 3년을 버텼다", body,
		[["continue", "계속한다", "시대 0은 2095년 아일랜드 원 점등까지 이어진다 (프로토타입은 숫자만 계속 돈다)"],
		["restart", "처음부터 다시", ""]])


func _end_game(title: String, text: String) -> void:
	_game_over = true
	_set_speed(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	modal.open("over", "패배", title, text + "\n\n패배도 이야기로 남는다.", [["restart", "처음부터 다시", ""]], Palette.RED)


func _on_module_tapped(mid: String) -> void:
	if sim == null:
		return
	var m: Dictionary = sim.M[mid]
	var count := int(sim.counts.get(mid, 0))
	var fam := GameData.family(mid)
	var kin := []
	for other in GameData.FAMILY[fam]:
		if other != mid:
			kin.append(String(sim.M[other]["name"]) + (" ×%d" % int(sim.counts[other]) if int(sim.counts.get(other, 0)) else ""))
	var body := "%s · %d기 (고장 %d · 건설 중 %d)\n%s\n\n전력 %s kW · 운영 인원 %d명 · 고장 간격 %s일 · 수리 부품 %d · %s 로봇·일\n\n%s\n\n같은 계열: %s" % [
		Palette.CATEGORY_KO[m["category"]], count, int(sim.broken.get(mid, 0)), sim.queued(mid), BuildPanel.describe(m),
		Fmt.n(float(m["power_kw"])), int(m["crew"]), Fmt.n(float(m["mtbf_days"])), int(m["repair"]["parts"]),
		Fmt.n(float(m["repair"]["rd"]), 1), String(m.get("note", "")), ", ".join(kin)]
	var reason := sim.build_block_reason(mid, 0.0)
	var choices := [["close", "닫기", ""]]
	choices.push_front(["build:" + mid, "1기 더 짓기 — 자리 고르기", reason if reason != "" else BuildPanel._cost_text(m["cost"])])
	modal.open("module", Palette.CATEGORY_KO[m["category"]], m["name"], body, choices, Palette.CATEGORY[m["category"]])


func _on_modal_choice(context: String, choice: String) -> void:
	match context:
		"start":
			match choice:
				"continue":
					if not _load_save():
						_new_game(2061, false)
				"new":
					_new_game(2061, false)
				"random":
					_new_game(randi_range(1, 999999), false)
				"auto":
					_new_game(2061, true)
					_set_speed(3)
		"storm":
			sim.resolve_storm(choice)
			_dirty = true
		"menu":
			match choice:
				"save":
					_save()
					_toast("저장했다", "good")
				"help":
					_show_help()
				"restart":
					_show_start()
				"quit":
					_save()
					get_tree().quit()
		"report":
			if choice == "restart":
				_show_start()
		"over":
			_show_start()
		"module":
			if choice.begins_with("build:"):
				_begin_place(choice.trim_prefix("build:"))
	_dirty = true
	_refresh_live()


func _on_auto(on: bool) -> void:
	if sim == null:
		return
	if on:
		sim.autopilot = AutoPolicy.new("good")
		sim.autopilot.configure(sim)
		for key in tabs:
			tabs[key].bind(sim)
		_toast("자동 운영 — 시드가 추천 운영 방침으로 짓고 연구한다", "good")
	else:
		sim.autopilot = null
		_toast("자동 운영 끔 — 이제 직접 짓고 연구를 고른다", "warn")
	_dirty = true
