class_name SettingsPanel
extends Control
## 설정 카드 — 그래픽 품질(자동·단계와 감지한 GPU), 지도에 보일 것, 성능 표시, 소리(전체·효과음·환경음 음량, 끄기).
## 바꾸면 바로 적용하고 저장한다.

signal changed

var _level_buttons := {}
var _gpu_label: Label
var _now_label: Label
var _checks := {}
var _sliders := {}


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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
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
	for spec in [["audio/master", "전체", 0.8], ["audio/sfx", "효과음", 0.8], ["audio/ambient", "환경음", 0.5]]:
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
		sl.custom_minimum_size.y = 36
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


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ThemeFactory.bold)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Palette.AMBER)
	return l


func open() -> void:
	_refresh()
	visible = true


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
	for key2 in _sliders:
		var sl: HSlider = _sliders[key2][0]
		sl.set_value_no_signal(float(Settings.value(key2, _sliders[key2][1])))
