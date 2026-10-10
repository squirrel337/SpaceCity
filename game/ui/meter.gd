class_name Meter
extends VBoxContainer
## 대시보드의 한 줄: 이름 · 막대 · 값, 그 아래 설명

var title := Label.new()
var value := Label.new()
var detail := Label.new()
var bar := ProgressBar.new()
var _fill: StyleBoxFlat


func _init(name_text: String) -> void:
	add_theme_constant_override("separation", 3)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	title.text = name_text
	title.custom_minimum_size.x = 58
	row.add_child(title)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size = Vector2(60, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", Palette.box(Palette.PANEL_2, Color.TRANSPARENT, 5, 0))
	_fill = Palette.box(Palette.TEAL, Color.TRANSPARENT, 5, 0)
	bar.add_theme_stylebox_override("fill", _fill)
	row.add_child(bar)
	value.custom_minimum_size.x = 104
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	add_child(row)
	detail.add_theme_color_override("font_color", Palette.MUTED)
	detail.add_theme_font_size_override("font_size", 13)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(detail)


func set_values(ratio: float, value_text: String, detail_text: String, color: Color) -> void:
	bar.value = clampf(ratio, 0.0, 1.0)
	_fill.bg_color = color
	value.text = value_text
	value.add_theme_color_override("font_color", Palette.TEXT if color == Palette.TEAL else color)
	detail.text = detail_text
