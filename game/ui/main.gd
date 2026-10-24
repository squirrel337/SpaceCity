extends Control
## SpaceCity 시대 0 프로토타입 — 화면 구성과 게임 루프.
## 규칙은 sim/의 CitySim이 맡고, 여기서는 시간을 흘리고 보여 주고 결정을 받는다.
## 식민지가 여럿이면(Colonies) 모두 같은 시계로 흐르고, 화면·탭·도구는 고른 식민지 하나(sim)를 본다.

const SAVE_PATH := "user://spacecity_save.json"
const HOURS_PER_SECOND := [0.0, 3.0, 9.0, 30.0, 0.0]   # 정지 · 1×(하루 8초) · 3×(2.7초) · 10×(0.8초) · 최고(프레임 예산만큼)
const SPEED_LABELS := ["정지", "1×", "3×", "10×", "최고"]
const MAX_SPEED := 4
const MAX_FRAME_US := 12000                         # 최고 속도: 한 프레임에 시뮬레이션에 쓰는 시간 (PC에서 하루 30일쯤)
const HIDDEN_SYNC_US := 1500                         # 보이지 않는 도시 하나의 배치를 한 프레임에 맞추는 몫
const AUTO_JUMP_PAUSE := 1.2                        # 다음 사건 계속 넘기기: 사건마다 알림을 보여 주는 틈 (초)
const REPORT_DAY := 1096                            # 3년 보고서
const JUMP_LIMIT_H := 24 * 30
const TABS := [["life", "생명유지"], ["power", "전력"], ["build", "건설"], ["research", "연구"], ["colony", "개척"],
	["transport", "교통"], ["log", "기록"]]

var sim: CitySim                    # 고른 식민지의 시뮬레이션 (탭·도구·3D 도시가 본다)
var colonies := Colonies.new()
var active := 0                     # 고른 식민지 번호
var speed := 0
var _last_speed := 1
var _acc := 0.0
var _jumping := false
var _auto_jump := false             # 다음 사건을 계속 넘긴다 (사건마다 잠깐 멈췄다 다음으로)
var _auto_wait := 0.0
var _panel_dirty := false           # 날이 바뀌어 탭을 다시 그릴 것 (빠를 때는 0.5초마다 한 번만)
var _saved_ms := -100000              # 마지막으로 저장한 때 (창을 오갈 때마다 저장하지 않게)
var _tab_sim := {}                   # 탭 → 묶인 식민지 (보이지 않는 탭은 고를 때 묶는다 — 식민지를 바꿀 때 7개를 다 만들지 않게)
var _panel_clock := 0.0
var auto_jump_button: Button
var _jump_start := 0
var _last_day := -1
var _hidden_i := 0                     # 배치를 맞출 다음 보이지 않는 도시
var _ui_clock := 0.0
var _report_shown := false
var _game_over := false
var _alarm_day := -100
var _dirty := true

var city_view: CityView
var world: WorldView
var plan: CityPlan
var tool := PlaceTool.new()
var place_bar: PanelContainer
var place_text: Label
var place_reason: Label
var place_buttons := {}
var place_note: Label
var place_opts: HFlowContainer         # 도구의 고를 것: 길 종류·곡선, 구획, 땅 고치기의 방법·붓
var _opts_mode := ""
var _opt_buttons := {}
var _road_group := "ground"        # 길 도구의 단추 묶음: ground 땅 위 · viaduct 고가 · bridge 다리
var road_button: Button
var plan_buttons := {}                 # 도시 계획 도구: 도로 · 구획 · 땅
var city_area: Control
var view_buttons := {}
var world_row: HBoxContainer       # 3D: 확대·축소, 기지 (다른 고정점은 위쪽의 경로 막대)
var anchor_bar: AnchorBar          # 3D: 카메라의 고정점 경로 (우주 › 태양계 › 지구 › 도시)
var metro_card: MetroCard          # 3D: 지구의 대도시 위에서 — 그 도시의 우주 시설 (도시 기능)·운영 방식·경제
var region_card: RegionCard        # 3D: 반도체·AI 데이터센터 지역 위에서 — 그 지역과 협력
var view_mode := "world"
var forecast: ForecastBar
var modal: Modal
var settings_panel: SettingsPanel
var toasts: VBoxContainer
var speed_buttons: Array[Button] = []
var auto_button: Button
var date_label: Label
var colony_button: OptionButton
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
	city_view = CityView.new()
	city_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city_view.module_tapped.connect(_on_module_tapped)
	city_view.visible = false
	city_area.add_child(city_view)
	world = WorldView.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.module_tapped.connect(_on_module_tapped)
	world.colony_picked.connect(_on_colony_view)
	world.colony_entered.connect(_on_colony_entered)
	world.site_picked.connect(_on_site_picked)
	world.mgr = colonies
	city_area.add_child(world)
	city_area.add_child(_build_view_switch())
	city_area.add_child(_build_place_bar())
	anchor_bar = AnchorBar.new()
	anchor_bar.world = world
	anchor_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_bar.offset_left = 8
	anchor_bar.offset_top = 8
	city_area.add_child(anchor_bar)
	metro_card = MetroCard.new()
	metro_card.mgr = colonies
	metro_card.visible = false
	metro_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	metro_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	metro_card.offset_right = -12
	metro_card.offset_top = 64
	metro_card.build_requested.connect(_on_metro_build)
	metro_card.mode_requested.connect(_on_metro_mode)
	metro_card.ops_requested.connect(_on_metro_ops)
	city_area.add_child(metro_card)
	region_card = RegionCard.new()
	region_card.mgr = colonies
	region_card.visible = false
	region_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	region_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	region_card.offset_right = -12
	region_card.offset_top = 64
	region_card.region_ops.connect(_on_region_ops)
	city_area.add_child(region_card)
	tool.changed.connect(_update_place_bar)
	tool.placed.connect(_on_placed)
	tool.bought.connect(func(ok: bool, text: String):
		_toast(text, "good" if ok else "warn")
		if ok:
			_refresh_tab()
		_dirty = true)
	tool.acted.connect(func(ok: bool, text: String):
		_toast(text, "good" if ok else "warn")
		if ok:
			_refresh_tab()
		_dirty = true)
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
	settings_panel = SettingsPanel.new()
	settings_panel.changed.connect(func(): world.apply_settings())
	add_child(settings_panel)


func _build_view_switch() -> Control:
	## 왼쪽 아래: 3D·목록 전환과 확대 단추
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for pair in [["world", "3D"], ["list", "목록"]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(58, 40)
		b.pressed.connect(_set_view.bind(pair[0]))
		row.add_child(b)
		view_buttons[pair[0]] = b
	for spec in [["road", "도로", "길 내기 — 종류(흙길·도로·대로·고속도로·통로·철도)를 고르고 점을 차례로 눌러 잇는다. 곡선도 된다 (G)"],
			["zone", "구획", "구획 — 길로 둘러싸인 블록을 눌러 용도(거주·산업·농업 …)를 정한다 (Z)"],
			["terrain", "땅", "땅 고치기 — 파기·쌓기·평탄화·되돌리기 (T). 바다가 있는 천체에서 해수면 아래로 파면 물이 찬다"],
			["land", "확장", "기지 넓히기 — 기지에 붙은 땅 구역(대로로 둘러싸인 블록 2×2)을 부품·지구 지원으로 산다 (X). 산 구역에는 길이 깔리고 빈 블록이 생긴다"],
			["demolish", "철거", "건물 헐기 — 건물을 눌러 고르고 한 번 더 누르거나 '헐기' (Del). 지어진 건물은 부품·금속의 절반을 돌려받고, 짓는 중이면 공사를 취소한다"],
			["move", "옮기기", "건물 옮기기 — 건물을 눌러 집어 들고 새 자리를 누른다 (N). 옮긴 건물은 로봇이 다시 세울 때까지 멈춘다"]]:
		var pb := Button.new()
		pb.text = spec[1]
		pb.toggle_mode = true
		pb.tooltip_text = spec[2]
		pb.custom_minimum_size = Vector2(52, 40)
		var which: String = spec[0]
		pb.toggled.connect(func(on: bool):
			if on:
				_begin_tool(which)
			elif tool.mode == which or (which == "road" and tool.mode == "erase"):
				tool.stop())
		row.add_child(pb)
		plan_buttons[which] = pb
	road_button = plan_buttons["road"]
	view_buttons["world"].tooltip_text = "식민지의 도시 — 끌어서 돌리고, 휠·두 손가락으로 확대해 행성과 별까지 (M)"
	view_buttons["list"].tooltip_text = "모듈 목록 (M)"
	world_row = HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 4)
	row.add_child(world_row)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	world_row.add_child(gap)
	for spec in [["−", "축소", func(): world.zoom_by(1.6)], ["+", "확대", func(): world.zoom_by(1.0 / 1.6)],
			["기지", "고른 식민지의 도시 위로 (H) — 다른 곳은 위쪽 경로(우주 › 태양계 › …)에서 고른다", func(): world.fly_to_colony()]]:
		var wb := Button.new()
		wb.text = spec[0]
		wb.tooltip_text = spec[1]
		wb.custom_minimum_size = Vector2(42 if spec[0].length() == 1 else 54, 40)
		wb.pressed.connect(spec[2])
		world_row.add_child(wb)
	var cover := Button.new()
	cover.text = "범위"
	cover.toggle_mode = true
	cover.tooltip_text = "영향 범위 — 의료·여가·대피 시설이 닿는 원. 집이 원 안에 있으면 사기가 오른다 ('개척' 탭의 도시 기능)"
	cover.custom_minimum_size = Vector2(54, 40)
	cover.toggled.connect(func(on: bool): world.show_cover(on))
	world_row.add_child(cover)
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = 10
	row.offset_bottom = -10
	view_buttons["world"].set_pressed_no_signal(true)
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
	place_note = Label.new()
	place_note.add_theme_font_size_override("font_size", 13)
	place_note.add_theme_color_override("font_color", Palette.AMBER)
	v.add_child(place_note)
	place_opts = HFlowContainer.new()
	place_opts.add_theme_constant_override("h_separation", 4)
	place_opts.add_theme_constant_override("v_separation", 4)
	v.add_child(place_opts)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	for spec in [["here", "여기에 짓기", "고른 자리에 짓는다 (Enter). 마우스는 누르는 곳에 바로 짓는다 — Shift를 누르고 있으면 계속 놓는다"],
			["rotate", "돌리기", "90° 돌린다 (R)"], ["variant", "모양", "같은 기능의 다른 설계 (V)"],
			["auto", "빈자리에", "기본 배치의 빈자리에 바로 짓는다"], ["end", "끝", "이어 가던 길을 끝낸다 (오른쪽 클릭)"],
			["demolish", "헐기", "고른 건물을 헌다 (Del)"], ["drop", "여기로 옮기기", "집어 든 건물을 고른 자리에 놓는다 (Enter)"],
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
	place_bar.offset_top = 8                 # 도구를 쓰는 동안 위쪽 경로 막대는 감춘다
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
		"demolish":
			tool.demolish_pick()
		"drop":
			tool.commit_move()
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
	for k in plan_buttons:
		(plan_buttons[k] as Button).set_pressed_no_signal(tool.mode == k or (k == "road" and tool.mode == "erase"))
	if not tool.active():
		return
	var building := tool.mode == "build"
	var carrying := tool.mode == "move" and not tool.carry.is_empty()
	place_text.text = tool.status()
	place_reason.text = tool.reason if tool.has_at else ""
	place_reason.visible = place_reason.text != ""
	place_note.text = tool.note if tool.has_at and tool.reason == "" else ""
	place_note.visible = place_note.text != ""
	_update_place_opts()
	place_buttons["here"].visible = building
	place_buttons["here"].disabled = not tool.has_at or tool.reason != ""
	place_buttons["rotate"].visible = building or carrying
	place_buttons["variant"].visible = building
	place_buttons["demolish"].visible = tool.mode == "demolish"
	place_buttons["demolish"].disabled = tool.pick.is_empty() or tool.reason != ""
	place_buttons["drop"].visible = carrying
	place_buttons["drop"].disabled = not tool.has_at or tool.reason != ""
	place_buttons["auto"].visible = building
	place_buttons["end"].visible = tool.mode == "road"
	place_buttons["end"].disabled = tool.road_from == null
	place_buttons["erase"].visible = tool.mode in ["road", "erase"]
	place_buttons["erase"].set_pressed_no_signal(tool.mode == "erase")
	place_bar.reset_size()
	place_bar.call_deferred("reset_size")


## 도구의 고를 것: 모드가 바뀔 때만 단추를 새로 만들고, 눌린 상태는 매번 맞춘다
func _update_place_opts() -> void:
	var group := tool.mode
	if group == "erase":
		group = "road"
	if group in ["build", "land"]:
		group = ""
	if group == "road":
		_road_group = LayoutData.road_group(tool.road_type)
	var key := group + "|" + tool.body() + ("|" + _road_group if group == "road" else "")
	if key != _opts_mode:
		_opts_mode = key
		for c in place_opts.get_children():
			place_opts.remove_child(c)
			c.queue_free()
		_opt_buttons.clear()
		match group:
			"road":
				# 묶음: 땅 위의 길 · 고가 (땅을 따라 높이 — 밑의 길과 만나지 않는다) · 다리 (물·분화구 위로 곧게)
				var gg := ButtonGroup.new()
				for grp in [["ground", "땅 위", "땅을 따라가는 길 — 만나는 길과 교차로가 된다"],
						["viaduct", "고가", "땅을 따라 높이 뜬 길 — 밑으로 지나는 길과 만나지 않고 끝에서 비탈로 내려앉는다"],
						["bridge", "다리", "두 끝 사이를 곧게 건너는 길 — 물·분화구·골짜기 위로. 땅 위의 길은 물을 건너지 못한다"]]:
					var gk: String = grp[0]
					_opt("g:" + gk, grp[1], grp[2], gg, func():
						for t2 in LayoutData.road_types(tool.body()):
							if LayoutData.road_group(t2) == gk:
								if tool.mode == "erase":
									tool.start_road(t2)
								else:
									tool.set_road_type(t2)
								break)
				_opt_gap()
				var g := ButtonGroup.new()
				for t in LayoutData.road_types(tool.body()):
					if LayoutData.road_group(t) != _road_group:
						continue
					var rd := LayoutData.road(t)
					var type: String = t
					var tip := "폭 %s m · 차로 %d · 속력 ×%s · 100 m마다 %s · 가장 가파른 기울기 %d%%" % [
						Fmt.n(float(rd["width_m"]), 0), int(rd["lanes"]), str(rd["speed"]),
						PlaceTool._cost_text(LayoutData.road_cost(type, 100.0)), int(float(rd["grade"]) * 100.0)]
					if LayoutData.raised(type):
						tip += " · 덱 높이 %s m · 받침 %s m마다" % [Fmt.n(float(rd.get("deck_m", 6.0)), 1), Fmt.n(float(rd.get("span_m", 24.0)), 0)]
					_opt(type, String(rd["name"]), tip, g,
						func():
							if tool.mode == "erase":
								tool.start_road(type)
							else:
								tool.set_road_type(type))
				_opt_gap()
				_opt("curve", "곡선", "이어 가던 길에서 매끄럽게 굽는다 (반지름은 길 종류의 한도 이상)", null,
					func(): tool.set_curve(not tool.curve))
				_opt("snap", "각도 맞춤", "방향을 15°마다 맞춘다 (기본 격자의 축과 나란하게)", null,
					func(): tool.set_angle_snap(not tool.angle_snap))
			"zone":
				var g2 := ButtonGroup.new()
				var zs := LayoutData.zones()
				for z in zs:
					var zk: String = z
					var b := _opt("z:" + zk, LayoutData.zone_name(zk), "이 블록을 '%s'(으)로" % LayoutData.zone_name(zk), g2,
						func(): tool.set_zone_kind(zk))
					b.icon = _swatch(LayoutData.zone_color(zk))
				_opt("z:", "비우기", "블록의 용도를 지운다 (빈 블록)", g2, func(): tool.set_zone_kind(""))
			"terrain":
				var g3 := ButtonGroup.new()
				for op in PlaceTool.TERRAIN_OPS:
					var o: String = op
					_opt("op:" + o, PlaceTool.OP_NAMES[o], {"dig": "누를 때마다 1 m 판다 (가장자리는 비탈)",
						"raise": "누를 때마다 1 m 쌓는다 — 바다를 해수면 위로 메우면 뭍이 된다",
						"flatten": "붓 가운데 높이로 고른다", "restore": "고친 땅을 처음 높이로 되돌린다"}[o], g3,
						func(): tool.set_terrain_op(o))
				_opt_gap()
				var g4 := ButtonGroup.new()
				for r in LayoutData.terrain()["brushes_m"]:
					var rr := float(r)
					_opt("br:%d" % int(rr), "붓 %d m" % int(rr), "붓의 반지름", g4, func(): tool.set_brush(rr))
	# 눌린 상태
	for k in _opt_buttons:
		var b: Button = _opt_buttons[k]
		var on := false
		if group == "road":
			on = k == tool.road_type or (k == "curve" and tool.curve) or (k == "snap" and tool.angle_snap) \
				or k == "g:" + _road_group
		elif group == "zone":
			on = k == "z:" + tool.zone_kind
		elif group == "terrain":
			on = k == "op:" + tool.terrain_op or k == "br:%d" % int(tool.brush)
		b.set_pressed_no_signal(on)
	place_opts.visible = group != ""
	place_opts.custom_minimum_size.x = clampf(city_area.size.x - 120.0, 280.0, 640.0) if group != "" else 0.0


func _opt(key: String, text: String, tip: String, group: ButtonGroup, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	if group != null:
		b.button_group = group
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	place_opts.add_child(b)
	_opt_buttons[key] = b
	return b


func _opt_gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 4)
	place_opts.add_child(gap)


static func _swatch(c: Color) -> Texture2D:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


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
	_begin_tool("road")


## 도시 계획 도구: "road" 길 내기 · "zone" 구획 · "terrain" 땅 고치기 · "land" 땅 구역 사기 (확장)
func _begin_tool(which: String) -> void:
	if sim == null:
		return
	if view_mode == "list":
		_set_view("world")
	if view_mode == "world":
		world.ensure_near_base()
	match which:
		"road":
			tool.start_road()
		"zone":
			tool.start_zone()
		"terrain":
			tool.start_terrain()
		"land":
			tool.start_land()
		"demolish":
			tool.start_demolish()
		"move":
			tool.start_move()


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
	_refresh_tab()
	_dirty = true


func _set_view(mode: String) -> void:
	view_mode = mode
	world.visible = mode == "world"
	city_view.visible = mode == "list"
	world_row.visible = mode == "world"
	for k in view_buttons:
		view_buttons[k].set_pressed_no_signal(k == mode)
	for k in plan_buttons:
		(plan_buttons[k] as Button).visible = mode != "list"
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
	date_label.custom_minimum_size.x = 140
	row.add_child(date_label)
	colony_button = OptionButton.new()
	colony_button.custom_minimum_size = Vector2(96, 42)
	colony_button.fit_to_longest_item = false
	colony_button.clip_text = true
	colony_button.tooltip_text = "식민지 고르기 — 그 도시로 날아간다"
	colony_button.item_selected.connect(func(i: int): _on_colony_view(i))
	row.add_child(colony_button)
	for i in range(SPEED_LABELS.size()):
		var b := Button.new()
		b.text = SPEED_LABELS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 42)
		b.pressed.connect(_on_speed_button.bind(i))
		if i == MAX_SPEED:
			b.tooltip_text = "최고 속도 (4) — 화면이 버티는 만큼 빨리 흐른다 (PC에서 하루에 한 달쯤). 결정할 일·위급하면 멈춘다"
		row.add_child(b)
		speed_buttons.append(b)
	var jump := Button.new()
	jump.text = "다음 사건"
	jump.tooltip_text = "알릴 일이 생길 때까지 시간을 건너뛴다 (최대 30일, F)"
	jump.custom_minimum_size.y = 42
	jump.pressed.connect(func():
		_stop_auto_jump()
		_start_jump())
	row.add_child(jump)
	auto_jump_button = Button.new()
	auto_jump_button.text = "계속"
	auto_jump_button.toggle_mode = true
	auto_jump_button.tooltip_text = "다음 사건을 계속 넘긴다 (Shift+F) — 사건마다 알림을 잠깐 보여 주고 다음 사건으로. " + \
		"결정할 일(대피소 추첨 — 자동 운영이면 추첨으로 정한다)·위급(산소·식량 3일 아래)·사망이면 멈춘다"
	auto_jump_button.custom_minimum_size = Vector2(52, 42)
	auto_jump_button.toggled.connect(func(on: bool):
		if on:
			_begin_auto_jump()
		else:
			_stop_auto_jump())
	row.add_child(auto_jump_button)
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
	chip_row.add_theme_constant_override("separation", 8)
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
	box.custom_minimum_size.x = 54
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
	side.custom_minimum_size.x = 440
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
		b.custom_minimum_size = Vector2(0, 42)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := (theme.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.content_margin_left = 2
			sb.content_margin_right = 2
			b.add_theme_stylebox_override(state, sb)
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
		"research": ResearchPanel.new(), "colony": ColonyPanel.new(), "transport": TransportPanel.new(), "log": LogPanel.new()}
	for key in tabs:
		tabs[key].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs[key].visible = false
		host.add_child(tabs[key])
	tabs["build"].changed.connect(_on_player_change)
	tabs["build"].place_requested.connect(_begin_place)
	tabs["research"].changed.connect(_on_player_change)
	tabs["colony"].mgr = colonies
	tabs["colony"].view_requested.connect(_on_colony_view)
	tabs["colony"].mode_requested.connect(_on_dev_mode)
	tabs["colony"].changed.connect(func():
		_update_colony_ui()
		_on_player_change())
	tabs["transport"].mgr = colonies
	tabs["transport"].changed.connect(_on_player_change)
	tabs["transport"].show_line.connect(func(id: String):
		if view_mode != "world":
			_set_view("world")
		world.show_route(id))
	tabs["transport"].show_metro.connect(func(key: String):
		if view_mode != "world":
			_set_view("world")
		var m := Metros.of(key)
		world.anchors.go({"kind": "metro", "id": key, "name": String(m.get("name", key)), "body": "earth",
			"dir": m.get("dir", Vector3.ZERO)}))
	return side


# ── 새 게임·저장 ─────────────────────────────────────────────────
func _new_game(seed_value: int, autopilot: bool) -> void:
	_boot_save()                                     # 미리 풀어 둔 저장은 쓰지 않으니 놓는다
	var s := CitySim.new(seed_value, 40.0, "good" if autopilot else "")
	colonies.start(s, CityPlan.create(s, world.ground_for(s.site_id).layout))
	_begin_session(0)
	sim.note("관리 기록 — 가동 확인. 정착민 120명. 시드 %d." % seed_value, "info")
	if autopilot:
		sim.note("자동 운영 — 시드가 추천 운영 방침으로 짓고 연구한다", "info")


## 새 게임·불러오기 뒤: 식민지마다 기록을 잇고, 고른 식민지를 화면에 붙인다
func _begin_session(index: int) -> void:
	sim = null
	for c in colonies.list:
		_wire(c)
	_last_day = colonies.hour / 24
	_report_shown = _last_day >= REPORT_DAY
	_game_over = false
	_acc = 0.0
	_jumping = false
	for c in toasts.get_children():
		c.queue_free()
	_activate(clampi(index, 0, colonies.list.size() - 1), false)
	world.home(false)
	_select_tab("life")
	_set_speed(0)


func _wire(c: Dictionary) -> void:
	var s: CitySim = c["sim"]
	if s.has_meta("wired"):
		return
	s.set_meta("wired", true)
	s.noted.connect(_on_colony_note.bind(s.get_instance_id()))


## 식민지를 고른다: 탭·목록·도구·3D 도시가 그 식민지를 본다. fly면 카메라가 그 도시로 날아가 내려앉는다
func _activate(index: int, fly: bool = true) -> void:
	if index < 0 or index >= colonies.list.size():
		return
	tool.stop()
	if sim != null:
		sim.interactive = false
	active = index
	var c: Dictionary = colonies.list[index]
	sim = c["sim"]
	plan = c["plan"]
	sim.interactive = true
	tool.bind(sim, plan)
	_tab_sim.clear()
	_bind_tab(current_tab)
	city_view.sim = sim
	city_view.title = String(c["name"])
	city_view.ridge = plan.layout.kind == "ridge"
	world.set_sim(sim, plan, tool)
	world.city.title = String(c["name"])
	world.city.colony = c
	tabs["research"].colony = c
	tabs["log"].colony = c
	tabs["log"].mgr = colonies
	forecast.sim = sim
	auto_button.set_pressed_no_signal(CityAuto.full(sim))
	_update_colony_ui()
	if fly:
		if view_mode != "world":
			_set_view("world")
		world.fly_to_colony()
	_dirty = true
	_refresh_live()


func _on_colony_view(index: int) -> void:
	if index < 0 or index >= colonies.list.size():
		return
	if index == active:
		if view_mode != "world":
			_set_view("world")
		world.fly_to_colony()
		return
	_activate(index, true)


## 3D에서 고르지 않은 도시 위로 직접 줌인했다: 카메라는 그대로 두고 그 도시를 고른다 (자세한 도시가 나타난다)
func _on_colony_entered(index: int) -> void:
	if index < 0 or index >= colonies.list.size() or index == active or tool.active() or modal.visible:
		return
	_activate(index, false)
	_toast("%s — 이 도시를 본다" % colonies.list[index]["name"], "info")


## 3D 지도에서 후보 부지의 점을 눌렀다: 개척 탭에서 그 부지 카드를 펼친다
func _on_site_picked(site_id: String) -> void:
	_select_tab("colony")
	var card: Control = tabs["colony"].focus_site(site_id)
	if card != null:
		await get_tree().process_frame
		panel_scroll.ensure_control_visible(card)


## 식민지 고르기 단추·3D 지도의 점·개척 탭을 맞춘다
func _update_colony_ui() -> void:
	colony_button.clear()
	for c in colonies.list:
		colony_button.add_item(String(c.get("short", c["name"])))
	colony_button.select(active)
	colony_button.visible = colonies.list.size() > 1        # 식민지가 하나뿐이면 감춘다 (윗줄 자리)
	_update_markers()
	if current_tab in ["colony", "transport"]:
		tabs[current_tab].rebuild()


func _update_markers() -> void:
	var dirs := {}
	for k in world.grounds:
		dirs[k] = (world.grounds[k] as SiteGround).site_dir()
	world.set_colonies(colonies.markers(active, dirs))


func _save() -> void:
	if sim == null or _game_over:
		return
	_saved_ms = Time.get_ticks_msec()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		var data := colonies.to_save()
		data["active"] = active
		f.store_string(JSON.stringify(data, "", false, true))
		f.close()


func _load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = _boot_save()
	if data == null:
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary or not colonies.load_save(data):
		return false
	_begin_session(int(data.get("active", 0)))
	sim.note("관리 기록 — 저장한 지점에서 다시 가동했다", "info")
	return true


## 시작 화면(boot.gd)이 다른 스레드에서 미리 풀어 둔 저장 — 그 뒤로 파일이 그대로일 때만. 한 번 꺼내면 놓는다
func _boot_save() -> Variant:
	var root := get_tree().root
	if not root.has_meta("boot_save"):
		return null
	var pre: Array = root.get_meta("boot_save")
	root.remove_meta("boot_save")
	return pre[1] if pre.size() == 2 and int(pre[0]) == FileAccess.get_modified_time(SAVE_PATH) else null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			_save()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Time.get_ticks_msec() - _saved_ms > 30000:     # 창을 오갈 때마다 멈추지 않게 (30초에 한 번)
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
	world.speed_level = mini(i, 3)
	_jumping = false
	for k in range(speed_buttons.size()):
		speed_buttons[k].set_pressed_no_signal(k == i)


## 속도 단추를 눌렀다: 다음 사건 계속 넘기기는 그만둔다
func _on_speed_button(i: int) -> void:
	_stop_auto_jump()
	_set_speed(i)


func _begin_auto_jump() -> void:
	if sim == null:
		return
	_auto_jump = true
	if auto_jump_button:
		auto_jump_button.set_pressed_no_signal(true)
	_auto_wait = 0.0
	_start_jump()


## 다음 사건 계속 넘기기를 멈춘다 (why가 있으면 알린다)
func _stop_auto_jump(why: String = "") -> void:
	if not _auto_jump:
		return
	_auto_jump = false
	_jumping = false
	if auto_jump_button:
		auto_jump_button.set_pressed_no_signal(false)
	if why != "":
		_toast("계속 넘기기를 멈췄다 — " + why, "warn")


## 빠르게 흐르는 중인가 (최고 속도·계속 넘기기) — 자동 운영이면 결정 카드를 시드가 정한다
func _fast() -> bool:
	return speed == MAX_SPEED or _auto_jump


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
		if not tool.back():
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
				elif tool.mode == "move":
					tool.commit_move()
				elif tool.mode == "demolish":
					tool.demolish_pick()
				else:
					tool.end_chain()
				get_viewport().set_input_as_handled()
				return
			KEY_DELETE:
				if tool.mode == "demolish":
					tool.demolish_pick()
					get_viewport().set_input_as_handled()
					return
	match event.keycode:
		KEY_G:
			if tool.mode in ["road", "erase"]:
				tool.stop()
			else:
				_begin_road()
		KEY_Z:
			if tool.mode == "zone":
				tool.stop()
			else:
				_begin_tool("zone")
		KEY_T:
			if tool.mode == "terrain":
				tool.stop()
			else:
				_begin_tool("terrain")
		KEY_X:
			if tool.mode == "land":
				tool.stop()
			else:
				_begin_tool("land")
		KEY_DELETE:
			if tool.mode == "demolish":
				tool.stop()
			else:
				_begin_tool("demolish")
		KEY_N:
			if tool.mode == "move":
				tool.stop()
			else:
				_begin_tool("move")
		KEY_SPACE:
			var was := _auto_jump or _jumping
			_stop_auto_jump()
			_set_speed(0 if speed > 0 or was else maxi(1, _last_speed))
		KEY_1:
			_on_speed_button(1)
		KEY_2:
			_on_speed_button(2)
		KEY_3:
			_on_speed_button(3)
		KEY_4:
			_on_speed_button(MAX_SPEED)
		KEY_F:
			if event.shift_pressed:
				if _auto_jump:
					_stop_auto_jump()
				else:
					_begin_auto_jump()
			else:
				_stop_auto_jump()
				_start_jump()
		KEY_B:
			_select_tab("build")
		KEY_R:
			_select_tab("research")
		KEY_L:
			_select_tab("log")
		KEY_P:
			_select_tab("colony")
		KEY_M:
			_set_view("list" if view_mode == "world" else "world")
		_:
			return
	get_viewport().set_input_as_handled()


func _start_jump() -> void:
	if sim == null or modal.visible:
		return
	_set_speed(0)
	_jumping = true
	_jump_start = colonies.hour


func _process(delta: float) -> void:
	if anchor_bar:
		anchor_bar.visible = view_mode == "world" and not tool.active()
		if anchor_bar.visible:
			anchor_bar.refresh()
	_update_metro_card()
	if sim == null or modal.visible or _game_over:
		return
	var stepped := false
	if _auto_jump and not _jumping:
		_auto_wait -= delta
		if _auto_wait <= 0.0:
			_start_jump()
	if _jumping:
		var t_jump := Time.get_ticks_usec()
		for _i in range(maxi(24, 96 / maxi(1, colonies.list.size()))):
			_step()
			stepped = true
			if not _jumping or modal.visible or _game_over:
				break
			if colonies.hour - _jump_start >= JUMP_LIMIT_H:
				_jumping = false
				_auto_wait = 0.0          # 30일 동안 아무 일도 없었다 — 계속 넘기는 중이면 바로 이어서
				break
			if _auto_jump and Time.get_ticks_usec() - t_jump > MAX_FRAME_US:
				break
	elif speed == MAX_SPEED:
		# 최고 속도: 프레임 예산 안에서 될 만큼 (결정 카드·위급이면 멈춘다)
		var t0 := Time.get_ticks_usec()
		var budget := MAX_FRAME_US / (2 if OS.has_feature("mobile") else 1)
		while true:
			_step()
			stepped = true
			if speed != MAX_SPEED or modal.visible or _game_over or Time.get_ticks_usec() - t0 > budget:
				break
		_acc = 0.0
	elif speed > 0:
		_acc += delta * HOURS_PER_SECOND[speed]
		var steps := 0
		while _acc >= 1.0 and steps < 64:
			_acc -= 1.0
			_step()
			stepped = true
			steps += 1
			if speed == 0 or modal.visible or _game_over:
				_acc = 0.0
				break
	world.hour_frac = clampf(_acc, 0.0, 1.0) if speed > 0 else 0.0
	_sync_hidden()
	_ui_clock += delta
	if stepped:
		_dirty = true
	if _dirty and _ui_clock >= 0.1:
		_ui_clock = 0.0
		_refresh_live()
	_panel_clock += delta
	if _panel_dirty and _panel_clock >= (0.5 if _fast() or _jumping else 0.0):
		_panel_dirty = false
		_panel_clock = 0.0
		if tabs[current_tab] is BuildPanel or tabs[current_tab] is ResearchPanel or tabs[current_tab] is ColonyPanel:
			tabs[current_tab].refresh()


## 대도시 카드·지역 카드: 카메라가 대도시(또는 반도체·AI 데이터센터 지역) 위에 있으면 (닫지 않았으면) 그곳의 카드를 보인다.
## 고정점으로 지역을 골랐으면 (대도시 시가지 안의 지역이라도) 지역 카드가 먼저다. 처음 찾아온 지역은 견학 — 연구 점수
func _update_metro_card() -> void:
	if metro_card == null:
		return
	var on := view_mode == "world" and sim != null and not tool.active() and not modal.visible
	var rk := world.region_focus() if on else ""
	var mk := world.metro_focus() if on and String(world.anchors.current.get("kind", "")) != "tech" else ""
	if mk != "":
		rk = ""
	if mk != metro_card.dismissed:
		metro_card.dismissed = ""
	if rk != region_card.dismissed:
		region_card.dismissed = ""
	metro_card.visible = mk != "" and mk != metro_card.dismissed
	region_card.visible = rk != "" and rk != region_card.dismissed
	if metro_card.visible:
		metro_card.payer_index = active
		metro_card.max_h = maxf(240.0, city_area.size.y - metro_card.offset_top - 12.0)
		metro_card.show_metro(mk, OS.has_feature("mobile"))       # 휴대폰은 접힌 채로 연다 (화면을 덜 가리게)
	if region_card.visible:
		if rk != region_card.key:
			region_card.visit_text = ""
		if colonies.metro_fn.modes.visit(rk, sim):
			var r := Metros.region(rk)
			region_card.visit_text = "견학 — %s 연구 +%d" % [_colony_tag(sim), int(Metros.tech_bonus.get("visit_rp", 30))]
			_toast("견학 — %s (%s). %s연구 +%d" % [String(r.get("name", rk)), Metros.kinds_text(r), _colony_tag(sim),
				int(Metros.tech_bonus.get("visit_rp", 30))], "good")
			_dirty = true
		region_card.payer_index = active
		region_card.show_region(rk, OS.has_feature("mobile"))


func _on_metro_build(key: String, fac: String) -> void:
	var name := "%s %s" % [String(Metros.of(key).get("name", key)), MetroFunctions.fac_name(fac)]
	var why := colonies.metro_fn.block_reason(key, fac, sim)
	if colonies.metro_fn.build(key, fac, colonies, active):
		var lvl := colonies.metro_fn.level(key, fac) + 1
		_toast("%s — %s (%d일)" % [name, "짓기 시작" if lvl == 1 else "%d단계로 올리기 시작" % lvl,
			int(MetroFunctions.level_def(fac, lvl).get("days", 0))], "good")
	else:
		_toast("%s — 지을 수 없다 (%s)" % [name, why], "warn")
	_after_metro_ops()


## 운영 방식을 고른다 ("" = 직접 운영으로 — 남은 운영비·비상 창고는 후원 식민지로 돌아간다)
func _on_metro_mode(key: String, mode: String) -> void:
	var name := String(Metros.of(key).get("name", key))
	var modes := colonies.metro_fn.modes
	var was := modes.mode_of(key)
	var why := modes.set_mode(key, mode, colonies, active)
	if why != "":
		_toast("%s — %s" % [name, why], "warn")
	elif mode == "":
		_toast("%s — 「%s」을(를) 멈췄다. 남은 운영비는 후원 식민지로 돌아갔다" % [name, Metros.mode_name(was)], "info")
	else:
		_toast("%s — 「%s」 %s. %d일 준비한 뒤 움직인다 — 운영비를 맡긴다" % [name, Metros.mode_name(mode),
			"시작" if was == "" else "로 바꿨다", int(MetroModes.rule("ready_days", 3))], "good")
	_after_metro_ops()


## 대도시 카드의 운영·경제 단추 (운영비 맡기기·자동 채움·협력 지역·동맹 과제·상점가·채권·펀드)
func _on_metro_ops(key: String, action: String, arg: Variant) -> void:
	var fn := colonies.metro_fn
	var name := String(Metros.of(key).get("name", key))
	var why := ""
	var ok := ""
	match action:
		"deposit":
			why = fn.modes.deposit(key, float(arg), colonies, fn)
			ok = "운영비 +%s" % Fmt.n(float(arg))
		"auto_fill":
			fn.modes.set_auto_fill(key, bool(arg))
			ok = "자동 채움 %s" % ("켬 — 후원 식민지의 지원이 넉넉할 때 하루 %s씩" % Fmt.n(float(MetroModes.rule("auto_fill", {}).get("per_day", 20)))
				if bool(arg) else "끔")
		"partner":
			why = fn.modes.set_partner(key, String(arg), colonies)
			ok = "협력 지역: %s" % String(Metros.region(String(arg)).get("name", "없음")) if String(arg) != "" else "협력 지역을 끝냈다"
		"project":
			why = fn.modes.set_project(String(arg), colonies)
			ok = "동맹 과제: %s" % (MetroModes.project_name(String(arg)) if String(arg) != "" else "자동 (고향의 연구 순서)")
		"commerce":
			why = fn.econ.open_commerce(key, colonies, active)
			ok = "우주 상점가를 열었다 — 날마다 상권 수입"
		"commerce_close":
			fn.econ.close_commerce(key)
			ok = "우주 상점가 계약을 끝냈다"
		"borrow":
			why = fn.econ.borrow(key, colonies, active)
			ok = "우주 채권을 발행했다"
		"invest":
			why = fn.econ.invest(key, float(arg), colonies, active)
			ok = "우주 펀드에 %s를 넣었다" % Fmt.n(float(arg))
		"withdraw":
			var back := float(fn.econ.funds.get(key, {}).get("value", 0.0)) * (1.0 - float(MetroEconomy.cfg("fund").get("fee", 0.01)))
			why = fn.econ.withdraw(key, colonies)
			ok = "우주 펀드를 찾았다 — 약 %s" % Fmt.n(back)
		_:
			return
	_toast("%s — %s" % [name, ok if why == "" else why], "good" if why == "" else "warn")
	_after_metro_ops()


## 지역 카드의 단추: 협력(그 대도시의 운영비로 계약) · 가까운 대도시로 가기
func _on_region_ops(region_key: String, action: String, metro_key: String) -> void:
	var r := Metros.region(region_key)
	match action:
		"partner":
			var name := String(Metros.of(metro_key).get("name", metro_key))
			var why := colonies.metro_fn.modes.set_partner(metro_key, region_key, colonies)
			if why == "":
				var bt := MetroModes.bonus_text(colonies.metro_fn.modes.mode_of(metro_key), r)
				_toast("%s — %s와(과) 협력한다%s" % [name, String(r.get("name", region_key)), (" (" + bt + ")") if bt != "" else ""], "good")
			else:
				_toast("%s — %s" % [name, why], "warn")
			_after_metro_ops()
		"go":
			var m := Metros.of(metro_key)
			if not m.is_empty():
				world.anchors.go({"kind": "metro", "id": metro_key, "name": String(m.get("name", metro_key)), "body": "earth",
					"dir": m.get("dir", Vector3.ZERO)})


func _after_metro_ops() -> void:
	metro_card.refresh()
	region_card.refresh()
	if current_tab == "transport":
		tabs["transport"].rebuild()
	_dirty = true


## 한 시간: 모든 식민지가 함께 흐른다 (고른 식민지만 결정 카드를 띄운다)
func _step() -> void:
	for i in colonies.step():
		_on_founded(i)
	var here: Dictionary = colonies.list[active]
	if not CityPeople.pending(here).is_empty() and not modal.visible and not CityAuto.full(sim):
		_jumping = false
		_set_speed(0)
		_show_event(here)
		return
	if colonies.scenario_news != "":
		var result := colonies.scenario_news
		colonies.scenario_news = ""
		_jumping = false
		_set_speed(0)
		_show_scenario_end(result)
		return
	if not sim.pending_storm.is_empty():
		if CityAuto.full(sim) and _fast():
			# 빠르게 흐르는 중이고 자동 운영이면: 시드가 추첨으로 정한다 (다른 식민지와 같은 규칙)
			sim.resolve_storm("lottery")
			_toast("자동 운영 — 태양 양성자 폭풍: 대피소 추첨으로 정했다", "warn")
		else:
			_jumping = false
			_set_speed(0)
			_show_storm()
			return
	@warning_ignore("integer_division")
	var day := colonies.hour / 24
	if day != _last_day:
		_last_day = day
		_on_new_day(day)


## 보이지 않는 도시도 배치를 조금씩 맞춰 둔다 (프레임마다 한 도시씩 돌아가며) — 그 도시를 고르거나 불러올 때
## 수백 채가 밀려 있지 않게. 한 번 본 도시만 (땅의 높이·물을 알아야 새 땅에 제대로 놓는다)
func _sync_hidden() -> void:
	var n := colonies.list.size()
	for _k in n:
		_hidden_i = (_hidden_i + 1) % n
		if _hidden_i == active:
			continue
		var c: Dictionary = colonies.list[_hidden_i]
		var p: CityPlan = c["plan"]
		if p.ground != null:
			p.sync(c["sim"], HIDDEN_SYNC_US)
			return


func _on_new_day(day: int) -> void:
	_panel_dirty = true
	# 식민지를 잃는다: 절멸, 또는 신뢰가 10 아래로 1년 — 고향을 잃으면 게임이 끝난다
	for i in range(colonies.list.size() - 1, -1, -1):
		var c: Dictionary = colonies.list[i]
		var cs: CitySim = c["sim"]
		var why := ""
		var text := ""
		if cs.population() <= 0:
			why = "절멸"
			text = "시드가 돌보던 정착민이 모두 사라졌다."
		elif cs.trust_low_days >= 365:
			why = "시드 정지"
			text = "신뢰가 10 아래로 1년이 지났다. 평의회가 시드를 끄기로 했다."
		if why == "":
			continue
		if String(c["site"]) == GameData.HOME_SITE or colonies.list.size() == 1:
			_end_game(why, text)
			return
		_lose_colony(i, why)
	for c in colonies.list:
		_flood_damage(c)
	var pop := sim.population()
	if pop <= 0:
		return
	var o2_days: float = sim.stock["o2_kg"] / (pop * sim.PER["o2_kg"])
	var food_days: float = sim.stock["food_kg"] / (pop * sim.PER["food_kg"])
	if ((o2_days < 3 and not sim.open_air) or food_days < 3) and day - _alarm_day > 2:
		_alarm_day = day
		_stop_auto_jump("위급")
		_set_speed(0)
		_toast("위급 — %s%s 비축이 3일 아래다" % [_colony_tag(sim), "산소" if o2_days < 3 else "식량"], "critical")
	if day >= REPORT_DAY and not _report_shown:
		_report_shown = true
		_set_speed(0)
		_show_report()


## 침수: 해수면 아래로 판 땅에 선 건물은 날마다 물에 잠겨 멈춘다 (고장 — 고쳐도 다음 날 다시). 땅을 메우면 그친다
func _flood_damage(c: Dictionary) -> void:
	var cp: CityPlan = c["plan"]
	if cp == null or cp.flood.is_empty():
		return
	var cs: CitySim = c["sim"]
	var fb := cp.flooded_built()
	for kind in fb:
		var n := mini(int(fb[kind]), int(cs.counts.get(kind, 0)))
		var was := int(cs.broken.get(kind, 0))
		if was < n:
			cs.broken[kind] = n
			cs.note("침수 — %s %d동이 물에 잠겨 멈췄다. 땅을 메우거나(쌓기) 다른 곳에 짓는다" % [GameData.module_name(kind), n - was],
				"warn")


## 원정대가 도착해 새 식민지가 섰다
func _on_founded(i: int) -> void:
	var c: Dictionary = colonies.list[i]
	_wire(c)
	_jumping = false
	_toast("%s 도착 — 개척을 시작한다. 개척 탭이나 3D 지도의 점을 눌러 그 도시로 날아간다" % c["name"], "good")
	var h := colonies.home()
	if not h.is_empty():
		(h["sim"] as CitySim).note("원정대 도착 — %s. 시드가 새 기지를 세우기 시작했다" % c["name"], "good")
	_update_colony_ui()


func _lose_colony(i: int, why: String) -> void:
	var was_active := i == active
	var c := colonies.remove(i)
	if active > i or active >= colonies.list.size():
		active = maxi(0, active - 1)
	_toast("%s — %s. 식민지를 잃었다" % [c["name"], why], "critical")
	var h := colonies.home()
	if not h.is_empty():
		(h["sim"] as CitySim).note("식민지 소실 — %s (%s)" % [c["name"], why], "death")
	if was_active:
		sim = null
		_activate(maxi(0, colonies.index_of_site(GameData.HOME_SITE)), true)
	else:
		_update_colony_ui()


## 다른 식민지의 일을 알릴 때 붙이는 이름 (고른 식민지 하나뿐이면 없다)
func _colony_tag(s: CitySim) -> String:
	if colonies.list.size() < 2:
		return ""
	var i := colonies.index_of_sim(s)
	return "[%s] " % colonies.list[i]["short"] if i >= 0 else ""


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
	var shade := "그림자" if plan.layout.kind == "ridge" else "밤"
	_set_chip("soc", Fmt.pct(soc), "축전" + (" · " + shade if sim.is_dark() else ""), Palette.level_color(soc, 0.4, 0.15))
	_set_chip("food", Fmt.days(food_days), "식량 · 자급 %s" % Fmt.pct(made / food_need if food_need > 0 else 0.0),
		Palette.level_color(food_days, 20, 7))
	_set_chip("pop", "%d명" % int(pop), "인구 · 주거 %d" % int(sim.housing_cap), Palette.AMBER if pop > sim.housing_cap else Palette.TEXT)
	_set_chip("morale", str(int(round(sim.morale))), "사기", Palette.level_color(sim.morale, 50, 35))
	_set_chip("trust", str(int(round(sim.trust))), "신뢰", Palette.level_color(sim.trust, 40, 30))
	if world.city != null and active >= 0 and active < colonies.list.size():
		world.city.era_text = String(CityProgress.data()["eras"][CityProgress.era_of(colonies.list[active])].get("short", ""))
		world.city.goal_text = Scenario.summary(colonies)
	city_view.queue_redraw()
	forecast.queue_redraw()
	tabs[current_tab].update_view()
	_update_markers()


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
		_bind_tab(key)
		tabs[key].update_view()
	panel_scroll.scroll_vertical = 0


## 탭을 고른 식민지에 묶는다: 처음이면 bind (다시 만들기), 이미 묶였으면 바뀐 것만 (refresh — 없으면 rebuild)
func _bind_tab(key: String) -> void:
	var t: Control = tabs[key]
	if _tab_sim.get(key) != sim:
		_tab_sim[key] = sim
		t.bind(sim)
	elif t.has_method("refresh"):
		t.refresh()
	elif t.has_method("rebuild"):
		t.rebuild()


## 지금 보이는 탭을 새로 그린다 (모양이 그대로면 글·단추만)
func _refresh_tab() -> void:
	if sim == null:
		return
	var t: Control = tabs[current_tab]
	if t.has_method("refresh"):
		t.refresh()
	elif t.has_method("rebuild"):
		t.rebuild()


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


## 식민지의 기록: 고른 식민지는 평소처럼, 다른 식민지는 위급한 일만 이름을 붙여 알린다
func _on_colony_note(hour: int, text: String, kind: String, sim_id: int) -> void:
	if sim != null and sim.get_instance_id() == sim_id:
		_on_note(hour, text, kind)
		return
	if kind in ["critical", "death"]:
		for c in colonies.list:
			if (c["sim"] as CitySim).get_instance_id() == sim_id:
				_toast("[%s] %s" % [c["short"], text], kind)
				break
	_dirty = true


func _on_note(_hour: int, text: String, kind: String) -> void:
	if kind in ["good", "warn", "critical", "death"]:
		_toast(text, kind)
	if _jumping and kind in ["good", "warn", "critical", "death"]:
		_jumping = false
		_auto_wait = AUTO_JUMP_PAUSE          # 계속 넘기는 중이면 알림을 잠깐 보여 주고 다음으로
	if kind == "death":
		_stop_auto_jump("사망 사고")
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
	choices.append(["scenario", "시나리오·도전", "목표와 기한이 있는 판 %d가지 — 도전은 규칙이 더 까다롭고 가장 좋은 기록이 남는다" %
		(Scenario.data()["scenarios"] as Array).size()])
	modal.open("start", "시대 0 · 씨앗 — 프로토타입", "섀클턴 시드 시티, 2061년 1월 1일",
		"당신은 달 남극 기지를 돌보도록 만들어진 관리 AI, 시드다. 정착민 120명의 공기와 전력, 식량과 방사선을 책임진다.\n\n" +
		"첫날의 숙제: CO₂ 제거기는 1기뿐이라 농장이 꺼지면 여유가 없다. 41일째에 대형 태양 양성자 폭풍이 오는데 대피소는 80석이다. " +
		"남극 겨울(150~240일째)에는 그림자가 최대 90시간 이어진다. 건설 탭에서 짓고, 연구 탭에서 연구를 고르고, 1×로 시간을 흘린다.",
		choices)


## 시나리오 고르기: 이름·기한·목표·규칙·가장 좋은 기록
func _show_scenarios() -> void:
	var choices := []
	for s in Scenario.data()["scenarios"]:
		var goals := PackedStringArray()
		for g in s["goals"]:
			goals.append(Scenario.goal_text(g))
		var desc := "%s\n목표: %s" % [String(s.get("text", "")), " · ".join(goals)]
		var rec := Scenario.record_text(String(s["id"]))
		if rec != "":
			desc += "\n" + rec
		choices.append([String(s["id"]), "%s — %d일" % [String(s["name"]), int(s["days"])], desc])
	choices.append(["back", "돌아가기", ""])
	modal.open("scenarios", "시나리오·도전", "어떤 판을 할까",
		"기한 안에 목표를 다 이루면 이긴다. 지킬 목표(사망·신뢰)를 어기거나 기한이 지나면 진다. 이기면 점수가 기록에 남는다 — " +
		"남은 날, 정착민, 신뢰가 많고 사망이 적을수록 높다. 끝난 뒤에도 그 도시로 계속할 수 있다.", choices)


func _start_scenario(id: String) -> void:
	var s := Scenario.find(id)
	if s.is_empty():
		_show_start()
		return
	_new_game(int(s.get("seed", 2061)), false)
	Scenario.begin(colonies, id)
	_toast("시나리오 — %s (%d일)" % [String(s["name"]), int(s["days"])], "good")
	_dirty = true


func _show_scenario_end(result: String) -> void:
	var s := Scenario.active(colonies)
	var won := result == "won"
	var lines := PackedStringArray()
	for l in Scenario.lines(colonies):
		lines.append("%s %s (%s)" % ["✓" if l[1] == true else ("✗" if l[1] == false else "·"), String(l[0]), String(l[2])])
	var body := "%s\n\n%s" % [String(colonies.scenario.get("why", "")), "\n".join(lines)]
	if won:
		body += "\n\n점수 %d · %s" % [int(colonies.scenario.get("score", 0)), Scenario.record_text(String(s.get("id", "")))]
	modal.open("scenario_end", "시나리오 · " + String(s.get("name", "")), "이겼다" if won else "졌다", body,
		[["continue", "이 도시로 계속", "목표 없이 자유롭게 이어 간다"], ["scenarios", "다른 시나리오", ""], ["restart", "처음 화면으로", ""]],
		Palette.GREEN if won else Palette.RED)


func _show_menu() -> void:
	if sim == null:
		_show_start()
		return
	_set_speed(0)
	modal.open("menu", "메뉴", "일시정지", "저장은 앱을 닫거나 내릴 때 자동으로 된다.", [
		["resume", "계속", ""],
		["save", "지금 저장", ""],
		["settings", "설정", "그래픽 품질 (GPU에 맞춰 자동) · 지도에 보일 것"],
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
		"· 신뢰가 30 아래면 위임이 줄고, 10 아래로 1년이 지나면 시드가 정지된다.\n" +
		"· 개척 탭(P): 화성·수성·세레스·칼리스토·타이탄으로 원정대를 보낸다. 필요한 기술, 고향의 부품·지원 점수, " +
		"열린 발사 창이 있어야 떠난다. 도착하면 시드가 자동 운영으로 기지를 세우고, 모든 식민지가 같은 시계로 흐른다.\n" +
		"· 3D 지도에서 행성을 보면 도시는 점과 이름뿐이다. 점이나 개척 탭의 '보기'를 누르면 그 도시로 날아가 내려앉는다.\n" +
		"· 카메라의 고정점: 3D 화면 위쪽의 경로(우주 › 태양계 › 지구 › 도시)가 지금 카메라가 바라보고 도는 점이다. " +
		"단계를 누르면 그곳으로, '›'·'▾'를 누르면 그 안의 행성·위성·도시·대도시·날아가는 수송선을 고른다. " +
		"이름표를 눌러도 고정점이 되고, Backspace는 한 단계 위로. '우주'에서는 우리 은하 전체를 본다.\n" +
		"· 도시 계획 (왼쪽 아래): '도로'(G) — 길 종류(흙길·도로·대로·고속도로·통로·철도)를 고르고 점을 차례로 누른다, '곡선'은 " +
		"이어 가던 길에서 굽는다. '구획'(Z) — 길로 둘러싸인 블록을 눌러 용도를 정한다. '땅'(T) — 파기·쌓기·평탄화·되돌리기 " +
		"(굴착기나 로봇 정비소가 있어야 한다). 지구·타이탄에서 해수면 아래로 파면 물이 차서 그 위의 건물이 멈춘다.\n" +
		"· 지구의 대도시 위로 가면 오른쪽 위 카드에서 우주 시설(산업 단지·이주 센터·연구소·홍보관·화물 터미널)을 " +
		"지구 지원 점수로 짓는다 — 부품·정착민·연구·지원이 더 들어온다. '운영' 탭에서 운영 방식(① 우주 산업 수도 · ③ 연구 동맹 · " +
		"⑤ 비상 보급 기지)을 고르고 운영비를 맡기면 그 도시가 스스로 일하고, '경제' 탭에서 그 도시의 상권·금융가와 계약한다 " +
		"(우주 상점가 · 우주 채권 · 우주 펀드).\n" +
		"· 3D 지도의 ◆는 반도체·AI 데이터센터 지역이다 — 내려가면 단지가 보이고, 처음 찾아가면 견학으로 연구 점수를 받는다. " +
		"운영 방식이 있는 대도시가 협력하면 그 방식의 몫이 커진다.\n" +
		"· 조작: 끌기 = 땅을 잡아 옮기기(멀면 고정점 둘레 돌기), 오른쪽 끌기·Shift 끌기·두 손가락 비틀기 = 방위·기울기, " +
		"휠·두 손가락 벌리기 = 확대·축소. 그래픽 품질은 메뉴 › 설정.",
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


## 이야기 이벤트 (CityPeople): 주인공·사정과 고를 것 — 고를 때까지 시간이 멈춘다
func _show_event(c: Dictionary) -> void:
	var inst := CityPeople.pending(c)
	var choices := []
	for i in (inst["choices"] as Array).size():
		var ch: Dictionary = inst["choices"][i]
		choices.append([str(i), String(ch["label"]), String(ch["text"])])
	modal.open("event", "이야기 · %s" % String(c["name"]), String(inst["title"]), String(inst["text"]), choices, Palette.AMBER)


func _show_report() -> void:
	var h := colonies.home()
	var s: Dictionary = (h["sim"] if not h.is_empty() else sim).summary()
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
				"scenario":
					_show_scenarios()
					return
		"scenarios":
			if choice == "back":
				_show_start()
				return
			_start_scenario(choice)
		"scenario_end":
			match choice:
				"scenarios":
					_show_scenarios()
					return
				"restart":
					_show_start()
					return
		"storm":
			sim.resolve_storm(choice)
			var sc: Dictionary = colonies.list[active]
			match choice:                               # 모임의 지지 (CityPolitics)
				"essential":
					CityPolitics.nudge(sc, "commons", -12.0)
					CityPolitics.nudge(sc, "engineers", 3.0)
				"council":
					CityPolitics.nudge(sc, "commons", 8.0)
			_dirty = true
		"event":
			CityPeople.resolve(colonies.list[active], int(choice), colonies)
			_refresh_tab()
			_dirty = true
		"menu":
			match choice:
				"save":
					_save()
					_toast("저장했다", "good")
				"help":
					_show_help()
				"settings":
					settings_panel.open()
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


## 도시 발전 모드를 골랐다: 그 도시에 적고, 자동 운영이 꺼져 있으면 켠다
func _on_dev_mode(index: int, mode: String) -> void:
	if index < 0 or index >= colonies.list.size():
		return
	var c: Dictionary = colonies.list[index]
	var s: CitySim = c["sim"]
	c["mode"] = mode
	if not CityAuto.full(s) and not bool(Scenario.rule(colonies, "no_auto", false)):
		s.autopilot = AutoPolicy.new("good")
		s.autopilot.configure(s)
		if s == sim:
			auto_button.set_pressed_no_signal(true)
			_tab_sim.clear()
			_bind_tab(current_tab)
	s.note("발전 모드 — %s: %s" % [CityDev.mode_name(mode), String(LayoutData.dev_mode(mode).get("text", ""))], "info")
	_toast("%s — 발전 모드 %s" % [c["name"], CityDev.mode_name(mode)], "good")
	tabs["colony"].rebuild()
	_dirty = true


func _on_auto(on: bool) -> void:
	if sim == null:
		return
	if on and bool(Scenario.rule(colonies, "no_auto", false)):
		auto_button.set_pressed_no_signal(false)
		_toast("이 도전에서는 자동 운영을 쓸 수 없다", "warn")
		return
	if on:
		sim.autopilot = AutoPolicy.new("good")
		sim.autopilot.configure(sim)
		_tab_sim.clear()
		_bind_tab(current_tab)
		_toast("자동 운영 — 시드가 추천 운영 방침으로 짓고 연구한다", "good")
	else:
		sim.autopilot = null
		var c: Dictionary = colonies.list[active]
		CityAuto.sync_policy(c)                      # 살림 건설을 맡겼으면 위임 정책을 붙인다
		var n := CityAuto.count(c)
		_toast("자동 운영 끔 — 이제 직접 짓고 연구를 고른다" + (" (맡긴 분야 %d가지는 시드가 한다)" % n if n > 0 else ""), "warn")
	_dirty = true
