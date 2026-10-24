class_name RegionCard
extends PanelContainer
## 3D 화면 오른쪽 위의 첨단 산업 지역 카드 — 반도체·AI 데이터센터 지역(◆) 위로 가면 뜬다 (대도시 카드 자리).
## 지역의 종류(메모리·파운드리·패키징·칩 설계·AI 데이터센터…), 실제 모습, 가장 가까운 대도시, 운영 방식마다의 협력 몫,
## 협력 중인 대도시, 그리고 운영 방식이 있는 대도시와 협력하는 단추 (계약은 그 대도시의 운영비에서).
## 처음 찾아온 지역은 견학으로 고른 식민지에 연구 점수를 준다 (main이 visit을 부른다).

signal region_ops(region_key: String, action: String, metro_key: String)

var key := ""
var mgr: Colonies
var payer_index := 0
var dismissed := ""
var visit_text := ""               # 이번에 견학했으면 그 줄
var _body: VBoxContainer
var _title: Label
var _kinds: HFlowContainer
var _text: Label
var _rows: VBoxContainer
var _fold: Button
var _folded := false
var _sig := ""


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.93), Color("5ec8e5").darkened(0.45), 10, 10))
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
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_kinds = HFlowContainer.new()
	_kinds.add_theme_constant_override("h_separation", 6)
	_body.add_child(_kinds)
	_text = ThemeFactory.muted("", 13)
	_body.add_child(_text)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	_body.add_child(_rows)


func show_region(k: String, compact: bool = false) -> void:
	if k != key:
		key = k
		_sig = ""
		_folded = compact
	refresh()


func refresh() -> void:
	if key == "" or mgr == null:
		return
	var fn := mgr.metro_fn
	var sig := "%s|%d|%d|%s|%s" % [key, fn.modes.rev, payer_index, str(_folded), visit_text]
	if sig == _sig:
		return
	_sig = sig
	var r := Metros.region(key)
	_title.text = String(r.get("name", key))
	for c in _kinds.get_children():
		_kinds.remove_child(c)
		c.queue_free()
	for kd in r.get("kinds", []):
		var chip := Label.new()
		chip.text = Metros.kind_name(String(kd))
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", Color(String(Metros.tech_kinds.get(String(kd), {}).get("color", "aab3c8"))))
		_kinds.add_child(chip)
	_text.text = "%s — %s" % [String(r.get("country", "")), String(r.get("text", ""))]
	_fold.text = "펼치기" if _folded else "접기"
	_text.visible = not _folded
	_rows.visible = not _folded
	for c2 in _rows.get_children():
		_rows.remove_child(c2)
		c2.queue_free()
	if _folded:
		reset_size.call_deferred()
		return
	var near := Metros.of(String(r.get("near_key", "")))
	_line("단지 지름 약 %s km · 비중 %s · 가장 가까운 대도시: %s %s%s" % [Fmt.n(float(r.get("size_km", 0.0))), Fmt.n(float(r.get("scale", 1.0)), 1),
		String(near.get("name", "-")), Fmt.distance_km(float(r.get("near_km", 0.0))),
		" (그 도시 시가지 안)" if String(r.get("in_metro", "")) != "" else ""], Palette.TEXT.darkened(0.1))
	var bits := PackedStringArray()
	for md in Metros.MODE_IDS:
		var bt := MetroModes.bonus_text(md, r)
		if bt != "":
			bits.append("%s: %s" % [String(Metros.mode_def(md).get("short", md)), bt])
	_line("협력하면 — " + (" · ".join(bits) if not bits.is_empty() else "운영 방식에 주는 몫이 없다"))
	var ps := fn.modes.partners_of_region(key)
	if ps.is_empty():
		_line("아직 협력하는 대도시가 없다 — 운영 방식이 있는 대도시가 운영비로 계약한다")
	else:
		var names := PackedStringArray()
		for mk in ps:
			names.append("%s (%s)" % [String(Metros.of(mk).get("name", mk)), String(Metros.mode_def(fn.modes.mode_of(mk)).get("short", ""))])
		_line("협력 중: " + ", ".join(names), Palette.GREEN)
	# 운영 방식이 있는 대도시들과 협력 (가까운 순서로 넷까지)
	var cands: Array = []
	for mk2 in fn.modes.metros:
		if fn.modes.partner_of(String(mk2)) != key:
			cands.append(String(mk2))
	var here: Vector3 = r.get("dir", Vector3.UP)
	cands.sort_custom(func(a, b): return Metros.km_between(here, Metros.of(a)["dir"]) < Metros.km_between(here, Metros.of(b)["dir"]))
	for i in mini(4, cands.size()):
		var mk3 := String(cands[i])
		var cost := MetroModes.partner_cost(mk3, r)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_rows.add_child(row)
		var bt2 := MetroModes.bonus_text(fn.modes.mode_of(mk3), r)
		var lb := ThemeFactory.muted("%s (%s) — %s" % [String(Metros.of(mk3).get("name", mk3)), String(Metros.mode_def(fn.modes.mode_of(mk3)).get("short", "")),
			bt2 if bt2 != "" else "효과 없음"], 12)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var b := Button.new()
		b.text = "협력 · 운영비 %s" % Fmt.n(cost)
		b.custom_minimum_size = Vector2(120, 44 if ThemeFactory.touch() else 30)
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = fn.modes.budget(mk3) < cost or bt2 == ""
		if bt2 == "":
			b.tooltip_text = "이 지역은 그 운영 방식에 주는 몫이 없다"
		elif b.disabled:
			b.tooltip_text = "운영비가 모자란다 (%s 있음)" % Fmt.n(fn.modes.budget(mk3))
		b.pressed.connect(func(): region_ops.emit(key, "partner", mk3))
		row.add_child(b)
	if fn.modes.metros.is_empty():
		_line("운영 방식이 있는 대도시가 없다 — 대도시 카드의 '운영' 탭에서 고른다")
	if visit_text != "":
		_line(visit_text, Palette.GREEN)
	if not near.is_empty():
		var go := Button.new()
		go.text = "%s(으)로 가기" % String(near.get("name", ""))
		go.custom_minimum_size.y = 44 if ThemeFactory.touch() else 30
		go.add_theme_font_size_override("font_size", 13)
		go.pressed.connect(func(): region_ops.emit(key, "go", String(near["key"])))
		_rows.add_child(go)
	reset_size()
	reset_size.call_deferred()                   # 줄바꿈 글의 높이는 너비가 정해진 뒤에야 맞다


func _line(text: String, color: Color = Palette.MUTED) -> void:
	var l := ThemeFactory.muted(text, 12)
	l.add_theme_color_override("font_color", color)
	_rows.add_child(l)
