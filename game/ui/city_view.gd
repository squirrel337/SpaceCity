class_name CityView
extends Control
## 기지 개요도 — 능선과 해, 그리고 모듈을 분류별 카드로 그린다. 카드를 누르면 모듈 정보가 열린다.

signal module_tapped(mid: String)

const ORDER := ["habitat", "life_support", "food", "power", "thermal", "safety", "industry", "logistics", "research", "social",
	"commerce"]
const HEADER := 92.0
const PAD := 12.0
const GAP := 8.0
const MIN_CARD_W := 150.0

var sim: CitySim
var title := "섀클턴 시드 시티"     # 고른 식민지 이름
var ridge := true                  # 능선형 부지(그림자) / 평지형(낮·밤)
var _cards := []


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for card in _cards:
			if card[0].has_point(event.position):
				module_tapped.emit(card[1])
				accept_event()
				return


func _draw() -> void:
	_cards.clear()
	var box := Palette.box(Palette.PANEL, Palette.LINE, 10, 0)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if sim == null:
		return
	_draw_header()
	var items := _items()
	if items.is_empty():
		return
	var area_h := size.y - HEADER - PAD * 2
	var cols := maxi(1, int((size.x - PAD * 2 + GAP) / (MIN_CARD_W + GAP)))
	var rows := int(ceil(items.size() / float(cols)))
	var card_w := (size.x - PAD * 2 - GAP * (cols - 1)) / cols
	var card_h := clampf((area_h - GAP * (rows - 1)) / rows, 46.0, 78.0)
	for i in range(items.size()):
		@warning_ignore("integer_division")
		var r := Rect2(PAD + (i % cols) * (card_w + GAP), HEADER + PAD + (i / cols) * (card_h + GAP), card_w, card_h)
		_draw_card(r, items[i])
		_cards.append([r, items[i]["mid"]])


func _draw_header() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var lit := not sim.is_dark()
	var sky_top := Color("1a2340") if lit else Color("0a0f1f")
	var sky := Rect2(1, 1, w - 2, HEADER)
	draw_rect(sky, sky_top)
	# 해: 극지의 해는 지평선을 따라 돈다 — 하루에 한 바퀴
	var phase := fmod(sim.hour / 24.0, 1.0)
	var sun := Vector2(240 + phase * (w - 280), HEADER * 0.62)
	if lit:
		for k in range(5, 0, -1):
			draw_circle(sun, 9.0 + k * 6.0, Color(1.0, 0.85, 0.5, 0.05))
		draw_circle(sun, 9.0, Color("fff3c4"))
	else:
		draw_circle(sun, 9.0, Color(1.0, 0.85, 0.5, 0.18))
	# 능선 실루엣 — 섀클턴 크레이터 가장자리
	var ridge := PackedVector2Array()
	ridge.append(Vector2(1, HEADER))
	var steps := 48
	for i in range(steps + 1):
		var x := 1 + (w - 2) * i / float(steps)
		var y := HEADER * 0.7 - 10.0 * sin(i * 0.45) - 6.0 * sin(i * 1.3 + 1.0) - (16.0 if i > 30 and i < 38 else 0.0)
		ridge.append(Vector2(x, y))
	ridge.append(Vector2(w - 1, HEADER))
	draw_colored_polygon(ridge, Color("10141c"))
	draw_polyline(ridge.slice(1, ridge.size() - 1), Color("3a4256"), 1.5)
	if not lit:
		draw_rect(sky, Color(0.05, 0.08, 0.2, 0.35))
	var state := "일조" if ridge else "낮"
	if sim.solar_kw > 0.0:
		state += " — 태양광 %s kW" % Fmt.n(sim.solar_kw)
	if not lit:
		state = "그림자" if ridge else "밤"
		if sim.bat_cap + sim.rfc_cap > 0.0:
			state += " — 태양광 0 kW, 축전 %s" % Fmt.pct((sim.battery + sim.rfc) / maxf(1.0, sim.bat_cap + sim.rfc_cap))
	draw_string(font, Vector2(16, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Palette.TEXT)
	draw_string(font, Vector2(16, 46), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.AMBER if lit else Palette.BLUE)
	if not sim.pending_storm.is_empty():
		_draw_right(font, w - 16, 26, "태양 양성자 폭풍 경보", 15, Palette.RED)
	elif sim.rationing:
		_draw_right(font, w - 16, 26, "식량 배급 중", 14, Palette.AMBER)
	var brown: float = sim.last_power.get("frac1", 1.0)
	if brown < 1.0:
		_draw_right(font, w - 16, 46, "생명유지 감전 %d%%" % int(round(brown * 100)), 14, Palette.RED)
	draw_line(Vector2(1, HEADER), Vector2(w - 1, HEADER), Palette.LINE, 1.0)


func _draw_right(font: Font, right_x: float, y: float, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(right_x - width, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _items() -> Array:
	var out := []
	for cat in ORDER:
		for mid in sim.M:
			if sim.M[mid]["category"] != cat:
				continue
			var count := int(sim.counts.get(mid, 0))
			var waiting := sim.queued(mid)
			if count == 0 and waiting == 0:
				continue
			out.append({"mid": mid, "cat": cat, "count": count, "broken": int(sim.broken.get(mid, 0)), "waiting": waiting})
	return out


func _draw_card(r: Rect2, item: Dictionary) -> void:
	var font := get_theme_default_font()
	var mid: String = item["mid"]
	var m: Dictionary = sim.M[mid]
	var color: Color = Palette.CATEGORY[item["cat"]]
	var broken: int = item["broken"]
	var border := Palette.RED if broken else Palette.LINE
	draw_style_box(Palette.box(Palette.PANEL_2, border, 8, 0), r)
	draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(4, r.size.y - 12)), color)
	var x := r.position.x + 12
	var name_size := 14 if r.size.x > 165 else 13
	draw_string(font, Vector2(x, r.position.y + 21), m["name"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 64, name_size, Palette.TEXT)
	if item["count"]:
		_draw_right(ThemeFactory.bold, r.end.x - 10, r.position.y + 23, "×%d" % item["count"], 18, color.lightened(0.15))
	var parts := []
	var line_color := Palette.MUTED
	if broken:
		parts.append("고장 %d" % broken)
		line_color = Palette.RED
	if item["waiting"]:
		parts.append("건설 중 %d" % item["waiting"])
		if not broken:
			line_color = Palette.AMBER
	if mid == "hab_module":
		parts.append("피복 %d/%d" % [sim.covered_habs, item["count"]])
	if mid == "hydroponics" and not sim.crops_alive():
		parts.append("작물 고사")
		line_color = Palette.RED
	if parts.is_empty():
		parts.append(_function_line(mid, item["count"]))
	if r.size.y >= 52:
		draw_string(font, Vector2(x, r.position.y + r.size.y - 12), " · ".join(parts), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 20, 12, line_color)


func _function_line(mid: String, count: int) -> String:
	var pv: Dictionary = sim.M[mid].get("provides", {})
	if pv.has("housing"):
		return "거주 %d명" % int(pv["housing"] * count)
	if pv.has("shelter"):
		return "대피 %d석" % int(pv["shelter"] * count)
	if pv.has("generation_kw"):
		return "발전 %s kW" % Fmt.n(pv["generation_kw"] * count)
	if pv.has("storage_kwh"):
		return "축전 %s kWh" % Fmt.n(pv["storage_kwh"] * count)
	if pv.has("heat_kw"):
		return "방열 %s kW" % Fmt.n(pv["heat_kw"] * count)
	if pv.has("co2_kg_day"):
		return "CO₂ 제거 %s kg/일" % Fmt.n(pv["co2_kg_day"] * count)
	var kw := float(sim.M[mid]["power_kw"]) * count
	return ("%s kW" % Fmt.n(kw)) if kw > 0 else "가동"
