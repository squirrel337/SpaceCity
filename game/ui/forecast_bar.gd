class_name ForecastBar
extends Control
## 일조 예보 — 앞으로 96시간의 그림자. 시드는 지형과 궤도로 그림자를 미리 안다.

const HOURS := 96
const LABEL_W := 92.0

var sim: CitySim


func _draw() -> void:
	draw_style_box(Palette.box(Palette.PANEL, Palette.LINE, 10, 0), Rect2(Vector2.ZERO, size))
	if sim == null:
		return
	var font := get_theme_default_font()
	draw_string(font, Vector2(12, size.y * 0.5 - 2), I18n.t("일조 예보"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)
	draw_string(font, Vector2(12, size.y * 0.5 + 14), I18n.t("96시간"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
	var x0 := LABEL_W
	var w := size.x - x0 - 12
	var slot := w / HOURS
	var y := 8.0
	var h := size.y - 26.0
	for i in range(HOURS):
		var hh := sim.hour + i
		var dark := sim.is_dark(hh)
		var c := Color("26355c") if dark else Color("8a6a2c")
		draw_rect(Rect2(x0 + i * slot, y, slot + 0.5, h), c)
	for i in range(HOURS + 1):
		var hh := sim.hour + i
		if hh % 24 == 0:
			var x := x0 + i * slot
			draw_line(Vector2(x, y - 2), Vector2(x, y + h + 2), Palette.TEXT.darkened(0.3), 1.0)
			var dt := sim.date_dict(hh)
			draw_string(font, Vector2(x + 3, size.y - 4), I18n.t("%d.%d" % [dt["month"], dt["day"]]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
	draw_rect(Rect2(x0 - 1, y - 3, 3, h + 6), Palette.TEXT)
