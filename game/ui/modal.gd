class_name Modal
extends Control
## 게임을 멈추고 결정을 받는 카드 (대피소 추첨, 보고서, 메뉴 등)

## 결정 카드마다 효과음 (없으면 정보 소리)
const CONTEXT_FX := {"storm": "alarm", "event": "event", "report": "milestone", "scenario_end": "milestone", "death": "death",
	"over": "death", "start": "info", "menu": "click", "help": "click", "module": "click"}

signal chosen(context: String, choice: String)

var context := ""
var _panel := PanelContainer.new()
var _title := Label.new()
var _tag := Label.new()
var _body := Label.new()
var _choices := VBoxContainer.new()
var _scroll := ScrollContainer.new()   # 고를 것이 많으면 (시나리오 고르기) 화면 높이 안에서 굴린다


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	_tag.add_theme_font_size_override("font_size", 13)
	v.add_child(_tag)
	_title.add_theme_font_override("font", ThemeFactory.bold)
	_title.add_theme_font_size_override("font_size", 24)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 16)
	_body.custom_minimum_size.x = 600
	v.add_child(_body)
	_choices.add_theme_constant_override("separation", 8)
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_choices)
	v.add_child(_scroll)


## choices: [[id, 버튼 문구, 설명(없으면 "")], ...]
func open(p_context: String, tag: String, title: String, body: String, choices: Array, accent: Color = Palette.TEAL) -> void:
	context = p_context
	Sound.fx(String(CONTEXT_FX.get(p_context, "info")))
	_tag.text = tag
	_tag.add_theme_color_override("font_color", accent)
	_title.text = title
	_body.text = body
	_panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, accent.darkened(0.25), 12, 22))
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	for ch in choices:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.text = ch[1]
		b.custom_minimum_size.y = 48
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_pick.bind(ch[0]))
		row.add_child(b)
		if ch.size() > 2 and ch[2] != "":
			row.add_child(ThemeFactory.muted(ch[2], 13))
		_choices.add_child(row)
	visible = true
	_fit.call_deferred()


## 고를 것의 높이만큼 (화면 아래·위 여백을 남기고 그보다 길면 굴린다)
func _fit() -> void:
	var need := _choices.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y - (_panel.get_combined_minimum_size().y - _scroll.custom_minimum_size.y) - 60.0
	_scroll.custom_minimum_size.y = clampf(need, 0.0, maxf(room, 160.0))


func _pick(choice: String) -> void:
	visible = false
	chosen.emit(context, choice)
