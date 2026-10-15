class_name MetroCard
extends PanelContainer
## 3D 화면 오른쪽 위의 대도시 카드 — 지구의 대도시 위로 가면(고정점으로 고르거나 가까이 내려가면) 뜬다.
## 그 도시의 인구·시가지·강점, 우주항으로 가는 항공편, 우주 시설 다섯(우주 산업 단지·이주 지원 센터·우주 연구소·
## 우주 홍보관·공항 화물 터미널)의 단계와 몫, 짓기·올리기 단추. 지원은 고른 식민지가 낸다.

signal build_requested(key: String, fac: String)

var key := ""
var mgr: Colonies
var payer_index := 0
var _body: VBoxContainer
var _rows: VBoxContainer
var _title: Label
var _sub: Label
var _flight: Label
var _foot: Label
var _fold: Button
var _folded := false
var _sig := ""
var dismissed := ""                # 닫은 대도시 (다른 곳으로 가면 다시 뜬다)


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.93), Palette.AMBER.darkened(0.45), 10, 10))
	custom_minimum_size.x = 340
	mouse_filter = Control.MOUSE_FILTER_STOP
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_body.add_child(head)
	_title = ThemeFactory.heading("", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_fold = Button.new()
	_fold.text = "접기"
	_fold.flat = true
	_fold.add_theme_font_size_override("font_size", 13)
	_fold.pressed.connect(func():
		_folded = not _folded
		_sig = ""
		refresh())
	head.add_child(_fold)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = "닫기 — 다른 곳으로 갔다가 오면 다시 뜬다"
	close.pressed.connect(func():
		dismissed = key
		visible = false)
	head.add_child(close)
	_sub = ThemeFactory.muted("", 13)
	_body.add_child(_sub)
	_flight = ThemeFactory.muted("", 13)
	_flight.add_theme_color_override("font_color", Palette.TEXT.darkened(0.12))
	_body.add_child(_flight)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_body.add_child(_rows)
	_foot = ThemeFactory.muted("", 12)
	_body.add_child(_foot)


## compact: 좁은 화면 (휴대폰) — 다른 대도시로 가면 접힌 채로 연다
func show_metro(k: String, compact: bool = false) -> void:
	if k != key:
		key = k
		_sig = ""
		_folded = compact
	refresh()


## 바뀐 것이 있을 때만 다시 만든다 (시설·지원·시각)
func refresh() -> void:
	if key == "" or mgr == null:
		return
	var fn := mgr.metro_fn
	var payer: Dictionary = mgr.list[payer_index] if payer_index < mgr.list.size() else {}
	var ps: CitySim = payer.get("sim")
	@warning_ignore("integer_division")
	var day := mgr.hour / 24
	var sig := "%s|%d|%d|%d|%s" % [key, fn.rev, int(ps.support) if ps else -1, day, str(_folded)]
	if sig == _sig:
		return
	_sig = sig
	var m := Metros.of(key)
	_title.text = "%s  ·  %s" % [String(m.get("name", key)), String(m.get("country", ""))]
	var st := Metros.style_of(m)
	var strong := Metros.strength_name(m)
	_sub.text = "%s · %s%s" % [Metros.pop_text(m), String(st.get("name", "")), (" · 강점: " + strong) if strong != "" else ""]
	# 우주항 항공편
	var feeder := {}
	for l in mgr.transport.lines:
		if String(l["role"]) == "feeder" and String(l["a"]) == key:
			feeder = l
			break
	if feeder.is_empty():
		_flight.text = "지구에 우주항 도시가 없다 — 우주항 항공편이 뜨지 않는다 (연구소·홍보관의 몫은 들어온다)"
	else:
		var y: Dictionary = fn.last.get(key, {})
		var yest := ""
		if float(y.get("settlers", 0.0)) > 0.0 or float(y.get("parts", 0.0)) > 0.0:
			yest = " · 어제 더 실은 것: 정착민 %d명, 부품 %s" % [int(y.get("settlers", 0.0)), Fmt.n(float(y.get("parts", 0.0)), 1)]
		_flight.text = "우주항 항공편: %s까지 %s · %d시간마다%s" % [Transport.node_name(String(feeder["b"])),
			Fmt.distance_km(float(feeder.get("km", 0.0))), int(feeder["every_h"]), yest]
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_fold.text = "펼치기" if _folded else "접기"
	_rows.visible = not _folded
	_foot.visible = not _folded
	if _folded:
		return
	for fac in MetroFunctions.ORDER:
		_rows.add_child(_fac_row(fn, fac, ps))
	_foot.text = "지원은 고른 식민지 '%s'이(가) 낸다 — 지금 지구 지원 %s" % [String(payer.get("short", payer.get("name", ""))),
		Fmt.n(ps.support) if ps else "-"]


func _fac_row(fn: MetroFunctions, fac: String, ps: CitySim) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var dot := ColorRect.new()
	dot.color = MetroFunctions.fac_color(fac)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var lvl := fn.level(key, fac)
	var name := Label.new()
	name.text = MetroFunctions.fac_name(fac)
	name.add_theme_font_size_override("font_size", 15)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if String(Metros.of(key).get("strength", "")) == fac:
		name.text += " ★"
		name.tooltip_text = "이 도시의 강점 — 몫이 1.5배"
	h.add_child(name)
	var dots := Label.new()
	dots.text = "●".repeat(lvl) + "○".repeat(MetroFunctions.MAX_LEVEL - lvl)
	dots.add_theme_color_override("font_color", MetroFunctions.fac_color(fac))
	dots.add_theme_font_size_override("font_size", 13)
	h.add_child(dots)
	var b := Button.new()
	b.custom_minimum_size = Vector2(118, 32)
	b.add_theme_font_size_override("font_size", 13)
	var cost := fn.next_cost(key, fac)
	if fn.building(key, fac):
		b.text = "짓는 중 %d%%" % int(fn.progress(key, fac, mgr.hour) * 100.0)
		b.disabled = true
	elif cost < 0.0:
		b.text = "다 올렸다"
		b.disabled = true
	else:
		b.text = ("짓기" if lvl == 0 else "%d단계로" % (lvl + 1)) + " · 지원 %s" % Fmt.n(cost)
		var why := fn.block_reason(key, fac, ps)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "%d일 걸린다" % int(MetroFunctions.level_def(fac, lvl + 1).get("days", 0))
		b.pressed.connect(func(): build_requested.emit(key, fac))
	h.add_child(b)
	var now := fn.output(key, fac)
	var nxt := fn.output(key, fac, lvl + 1) if lvl < MetroFunctions.MAX_LEVEL else {}
	var t := ""
	if not now.is_empty():
		t = "지금: " + MetroFunctions.output_text(now)
	if not nxt.is_empty():
		t += ("  →  " if t != "" else "") + "%d단계: %s" % [lvl + 1, MetroFunctions.output_text(nxt)]
	if t == "":
		t = String(MetroFunctions.def(fac).get("text", ""))
	var info := ThemeFactory.muted(t, 12)
	info.tooltip_text = String(MetroFunctions.def(fac).get("text", ""))
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(info)
	return v
