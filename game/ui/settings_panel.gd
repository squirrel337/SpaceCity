class_name SettingsPanel
extends Control
## 설정 카드 — 언어(한국어 · English), 보기·접근성(UI 배율 · 글자 크기 · 색각 팔레트 · 움직임 줄이기 — Access),
## 그래픽 품질(자동·단계와 감지한 GPU), 지도에 보일 것, 성능 표시, 소리(전체·효과음·환경음·음악 음량, 끄기).
## 바꾸면 바로 적용하고 저장한다. 화면보다 길면 굴린다.

signal changed
signal lang_changed
signal access_changed(kind: String, value: String)   # scale · font · cvd · calm — main이 테마·패널을 다시 만든다

var _level_buttons := {}
var _gpu_label: Label
var _now_label: Label
var _checks := {}
var _sliders := {}
var _lang_buttons := {}
var _access_buttons := {}           # "scale:1.15" · "font:large" · "cvd:deutan" → 단추
var _scale_label: Label
var _scroll := ScrollContainer.new()
var _panel: PanelContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, Palette.TEAL.darkened(0.25), 12, 22))
	center.add_child(panel)
	_panel = panel
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)
	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", Access.fs(24))
	v.add_child(title)
	v.add_child(_section("언어 · Language"))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 6)
	var lgroup := ButtonGroup.new()
	for code in I18n.LANGS:
		var lb := Button.new()
		lb.text = String(I18n.LANGS[code])
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # 언어 이름은 그 언어로
		lb.toggle_mode = true
		lb.button_group = lgroup
		lb.custom_minimum_size = Vector2(120, 44)
		var c2: String = code
		lb.pressed.connect(func():
			if I18n.lang != c2:
				I18n.set_lang(c2)
				lang_changed.emit())
		lrow.add_child(lb)
		_lang_buttons[code] = lb
	v.add_child(lrow)
	v.add_child(_section("보기 · 접근성"))
	v.add_child(_choice_row("UI 배율", "scale", Access.SCALES, Access.SCALE_NAMES, 84))
	_scale_label = ThemeFactory.muted("", 13)
	v.add_child(_scale_label)
	v.add_child(_choice_row("글자 크기", "font", Access.FONTS.keys(), Access.FONT_NAMES, 96))
	v.add_child(_choice_row("색", "cvd", Palette.CVD.keys(), Palette.CVD_NAMES, 104))
	var calm := CheckButton.new()
	calm.text = "움직임 줄이기 — 카메라가 날아가지 않고 곧바로 옮겨 가고, 깜박이는 불빛·흔들리는 작물·도는 기계가 멈춘다"
	calm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calm.custom_minimum_size.y = 40
	calm.toggled.connect(func(on: bool):
		Access.set_calm(on)
		access_changed.emit("calm", "1" if on else ""))
	v.add_child(calm)
	_checks["ui/calm"] = [calm, false]
	v.add_child(_section("그래픽 품질"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for key in ["auto", "low", "medium", "high", "ultra"]:
		var b := Button.new()
		b.text = Settings.LEVEL_NAMES[key]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(96, 44)
		b.pressed.connect(_pick_level.bind(key))
		row.add_child(b)
		_level_buttons[key] = b
	v.add_child(row)
	_gpu_label = ThemeFactory.muted("", 14)
	_gpu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_gpu_label)
	_now_label = ThemeFactory.muted("", 13)
	_now_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_now_label)
	v.add_child(_section("지도와 카메라"))
	for spec in [["map/routes", "도시 사이 노선과 탈것", true], ["map/orbits", "행성·위성의 궤도선", true],
			["camera/auto_parent", "멀리 물러나면 고정점을 상위 천체로 옮기기 (끄면 고른 고정점에 머문다)", false],
			["debug/perf", "성능 표시 (초당 프레임 · CPU 시간 · 그리기 호출)", false]]:
		var c := CheckButton.new()
		c.text = spec[1]
		c.custom_minimum_size.y = 40
		c.toggled.connect(func(on: bool):
			Settings.set_value(spec[0], on)
			changed.emit())
		v.add_child(c)
		_checks[spec[0]] = [c, spec[2]]
	v.add_child(_section("소리"))
	for spec in [["audio/master", "전체", 0.8], ["audio/sfx", "효과음", 0.8], ["audio/ambient", "환경음", 0.5], ["audio/music", "음악", 0.45]]:
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		var lab := Label.new()
		lab.text = spec[1]
		lab.custom_minimum_size.x = 80
		row2.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size.y = 44
		var key: String = spec[0]
		sl.value_changed.connect(func(x: float):
			Settings.set_value(key, x)
			Sound.apply_volumes())
		sl.drag_ended.connect(func(_changed: bool): Sound.fx("click"))
		row2.add_child(sl)
		v.add_child(row2)
		_sliders[key] = [sl, spec[2]]
	var mute := CheckButton.new()
	mute.text = "소리 끄기"
	mute.custom_minimum_size.y = 40
	mute.toggled.connect(func(on: bool):
		Settings.set_value("audio/mute", on)
		Sound.apply_volumes())
	v.add_child(mute)
	_checks["audio/mute"] = [mute, false]
	var close_b := Button.new()
	close_b.text = "닫기"
	close_b.custom_minimum_size.y = 46
	close_b.pressed.connect(close)
	v.add_child(close_b)


## 고르는 단추 줄: 이름표 + 단추들 (하나만 눌린다)
func _choice_row(title: String, kind: String, keys: Array, names: Dictionary, width: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lab := Label.new()
	lab.text = title
	lab.custom_minimum_size.x = 84
	row.add_child(lab)
	var group := ButtonGroup.new()
	for key in keys:
		var b := Button.new()
		b.text = String(names.get(key, key))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(width, 44)
		var k: String = key
		b.pressed.connect(func(): access_changed.emit(kind, k))
		row.add_child(b)
		_access_buttons["%s:%s" % [kind, k]] = b
	return row


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ThemeFactory.bold)
	l.add_theme_font_size_override("font_size", Access.fs(16))
	l.add_theme_color_override("font_color", Palette.AMBER)
	return l


func open() -> void:
	_refresh()
	visible = true
	_fit.call_deferred()


## 화면 높이 안에 (넘치면 굴린다)
func _fit() -> void:
	var content := (_scroll.get_child(0) as Control).get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - 44.0 - 60.0
	_scroll.custom_minimum_size.y = clampf(content, 160.0, maxf(room, 160.0))


func close() -> void:
	visible = false


func _pick_level(key: String) -> void:
	Settings.set_preset(key)
	_refresh()
	changed.emit()


func _refresh() -> void:
	var p := Settings.preset()
	for k in _level_buttons:
		(_level_buttons[k] as Button).set_pressed_no_signal(k == p)
	var g := Settings.gpu()
	_gpu_label.text = "감지한 장치: %s — %s · 추천 '%s'" % [String(g["name"]) if String(g["name"]) != "" else "?",
		Settings.kind_name(String(g["kind"])), Settings.LEVEL_NAMES[String(g["level"])]]
	var lv := Settings.level()
	var q: Dictionary = Settings.PRESETS[lv]
	_now_label.text = "지금 '%s'%s — 3D 화면 %s만 화소 · 안티앨리어싱 %s · 그림자 %s · 대도시 건물 %s채. 지형 격자와 굽기 해상도는 다음에 도시를 열 때 적용된다." % [
		Settings.LEVEL_NAMES[lv], " (자동 — 느려지면 한 단계씩 낮춘다)" if p == "auto" else "",
		Fmt.n(float(q["render_px"]) / 10000.0), ("%d×" % int(q["msaa"])) if int(q["msaa"]) > 0 else "끔",
		"%d단" % int(q["shadow_splits"]) if int(q["shadow_splits"]) > 0 else "끔", Fmt.n(float(q["metro_budget"]))]
	for key in _checks:
		var c: CheckButton = _checks[key][0]
		c.set_pressed_no_signal(bool(Settings.value(key, _checks[key][1])))
	for code in _lang_buttons:
		(_lang_buttons[code] as Button).set_pressed_no_signal(code == I18n.lang)
	var now := {"scale": String(Settings.value("ui/scale", "auto")), "font": String(Settings.value("ui/font", "normal")),
		"cvd": Palette.kind}
	for key3 in _access_buttons:
		var parts := String(key3).split(":", true, 1)
		(_access_buttons[key3] as Button).set_pressed_no_signal(String(now.get(parts[0], "")) == parts[1])
	var win := get_window()
	var k := win.content_scale_factor if win != null else 1.0
	_scale_label.text = "지금 UI 배율 %d%% — 고른 배율 %d%%%s" % [int(round(k * 100.0)), int(round(Access.chosen_scale() * 100.0)),
		" (화면이 허락하는 만큼 — 위 막대와 옆 패널이 들어가게)" if Access.chosen_scale() - k > 0.005 else ""]
	for key2 in _sliders:
		var sl: HSlider = _sliders[key2][0]
		sl.set_value_no_signal(float(Settings.value(key2, _sliders[key2][1])))
