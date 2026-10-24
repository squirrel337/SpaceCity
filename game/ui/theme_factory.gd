class_name ThemeFactory
## 게임 전체의 테마. 한글은 Pretendard(OFL)를 쓴다.

static var regular: Font
static var bold: Font
static var _touch := -1
const TOUCH_MIN := 44.0             # 터치에서 누르는 곳의 최소 폭·높이 (1280×720 기준 UI 좌표)


## 터치 화면 (Android, 터치스크린이 있는 PC, 시험의 --touch): 누르는 곳을 최소 44 px로 — 마우스면 조금 촘촘하게
static func touch() -> bool:
	if _touch < 0:
		_touch = 1 if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
			or OS.get_cmdline_user_args().has("--touch") else 0
	return _touch == 1


static func build() -> Theme:
	regular = load("res://fonts/Pretendard-Regular.otf")
	bold = load("res://fonts/Pretendard-Bold.otf")
	var theme := Theme.new()
	theme.default_font = regular
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", Palette.TEXT)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat
		match state:
			"normal":
				sb = Palette.box(Palette.PANEL_2, Palette.LINE, 8, 8)
			"hover":
				sb = Palette.box(Palette.PANEL_2.lightened(0.08), Palette.TEAL.darkened(0.3), 8, 8)
			"pressed":
				sb = Palette.box(Palette.TEAL.darkened(0.55), Palette.TEAL, 8, 8)
			"disabled":
				sb = Palette.box(Palette.PANEL.darkened(0.1), Palette.LINE.darkened(0.3), 8, 8)
			"focus":
				sb = Palette.box(Color.TRANSPARENT, Palette.TEAL.darkened(0.2), 8, 8)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		var pad_y := 12 if touch() else 8   # 글 한 줄(16 px)이면 터치 44 px (08 UX), 마우스 36 px
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
		theme.set_stylebox(state, "Button", sb)
	theme.set_color("font_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_color", "Button", Palette.TEXT)
	theme.set_color("font_pressed_color", "Button", Palette.TEXT)
	theme.set_color("font_hover_pressed_color", "Button", Palette.TEXT)
	theme.set_color("font_disabled_color", "Button", Palette.DIM)
	theme.set_color("font_focus_color", "Button", Palette.TEXT)

	theme.set_stylebox("panel", "PanelContainer", Palette.box(Palette.PANEL, Palette.LINE, 10, 12))
	theme.set_stylebox("panel", "Panel", Palette.box(Palette.PANEL, Palette.LINE, 10, 12))

	theme.set_stylebox("slider", "HSlider", Palette.box(Palette.PANEL_2, Palette.LINE, 4, 3))
	theme.set_stylebox("grabber_area", "HSlider", Palette.box(Palette.AMBER.darkened(0.25), Color.TRANSPARENT, 4, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", Palette.box(Palette.AMBER, Color.TRANSPARENT, 4, 3))
	theme.set_icon("grabber", "HSlider", _dot(22, Palette.AMBER))
	theme.set_icon("grabber_highlight", "HSlider", _dot(24, Palette.AMBER.lightened(0.2)))

	theme.set_color("font_color", "CheckBox", Palette.TEXT)
	theme.set_color("font_hover_color", "CheckBox", Palette.TEXT)
	theme.set_color("font_pressed_color", "CheckBox", Palette.TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", Palette.TEXT)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckBox", Palette.box(Color.TRANSPARENT, Color.TRANSPARENT, 6, 4))

	theme.set_stylebox("panel", "TooltipPanel", Palette.box(Palette.PANEL_2, Palette.LINE, 6, 8))
	theme.set_color("font_color", "TooltipLabel", Palette.TEXT)

	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_stylebox("scroll", "VScrollBar", Palette.box(Color.TRANSPARENT, Color.TRANSPARENT, 4, 2))
	theme.set_stylebox("grabber", "VScrollBar", Palette.box(Palette.LINE, Color.TRANSPARENT, 4, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", Palette.box(Palette.DIM, Color.TRANSPARENT, 4, 4))
	theme.set_stylebox("grabber_pressed", "VScrollBar", Palette.box(Palette.MUTED, Color.TRANSPARENT, 4, 4))
	return theme


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)


static func heading(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", bold)
	l.add_theme_font_size_override("font_size", size)
	return l


static func muted(text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
