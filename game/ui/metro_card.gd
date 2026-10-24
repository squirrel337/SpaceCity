class_name MetroCard
extends PanelContainer
## 3D 화면 오른쪽 위의 대도시 카드 — 지구의 대도시 위로 가면(고정점으로 고르거나 가까이 내려가면) 뜬다.
## 그 도시의 인구·시가지·강점과 우주항으로 가는 항공편, 그리고 탭 셋:
##   시설 — 우주 시설 다섯(우주 산업 단지·이주 지원 센터·우주 연구소·우주 홍보관·공항 화물 터미널)의 단계와 몫, 짓기·올리기.
##   운영 — 운영 방식(직접 · ①우주 산업 수도 · ③연구 동맹 · ⑤비상 보급 기지): 후원 식민지, 운영비 맡기기·자동 채움,
##          방식마다의 상태, 협력 지역(반도체·AI 데이터센터), 동맹의 과제, '자동으로 한 일'.
##   경제 — 실제 도시의 상권(우주 상점가 계약)과 금융가(우주 채권·우주 펀드), 우주 산업 지수.
## 돈은 고른 식민지(위쪽 바에서 고른 곳)의 지구 지원에서 낸다 — 운영비만 후원 식민지가 낸다.
## 고르는 단추(운영 방식·협력 지역·과제)와 탭은 한 번만 만들고, 나머지 줄만 바뀔 때 다시 만든다 (열린 목록이 닫히지 않게).

signal build_requested(key: String, fac: String)
signal mode_requested(key: String, mode: String)
signal ops_requested(key: String, action: String, arg: Variant)

const TABS := [["fac", "시설"], ["ops", "운영"], ["econ", "경제"]]
const MODE_BUTTONS := [["", "직접"], ["parts_capital", "① 산업 수도"], ["research_alliance", "③ 연구 동맹"],
	["emergency_depot", "⑤ 비상 기지"]]

var key := ""
var mgr: Colonies
var payer_index := 0
var max_h := 700.0                 # 카드 전체가 넘지 않을 높이 (main이 화면에 맞춰 준다)
var _body: VBoxContainer
var _title: Label
var _sub: Label
var _flight: Label
var _tab_row: HBoxContainer
var _tab_btn := {}
var _tab := "fac"
var _scroll: ScrollContainer
var _fac_box: VBoxContainer
var _ops_box: VBoxContainer
var _econ_box: VBoxContainer
var _mode_row: HFlowContainer
var _mode_btn := {}
var _ops_rows: VBoxContainer
var _pick_box: VBoxContainer
var _partner_label: Label
var _partner_pick: OptionButton
var _partner_ids: Array = []
var _project_label: Label
var _project_pick: OptionButton
var _project_ids: Array = []
var _ops_log: VBoxContainer
var _foot: Label
var _fold: Button
var _folded := false
var _sig := ""
var _built_ms := 0
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
	# 탭
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 4)
	_body.add_child(_tab_row)
	var grp := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.button_group = grp
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 44 if ThemeFactory.touch() else 32
		b.add_theme_font_size_override("font_size", 14)
		var id := String(t[0])
		b.pressed.connect(func(): set_tab(id))
		_tab_row.add_child(b)
		_tab_btn[id] = b
	(_tab_btn["fac"] as Button).set_pressed_no_signal(true)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(inner)
	_fac_box = _vbox(8)
	inner.add_child(_fac_box)
	# 운영 탭: 방식 단추·고르기 목록은 그대로 두고 줄만 다시 만든다
	_ops_box = _vbox(6)
	inner.add_child(_ops_box)
	_mode_row = HFlowContainer.new()
	_mode_row.add_theme_constant_override("h_separation", 4)
	_mode_row.add_theme_constant_override("v_separation", 4)
	_ops_box.add_child(_mode_row)
	for mb in MODE_BUTTONS:
		var b2 := Button.new()
		b2.text = String(mb[1])
		b2.toggle_mode = true
		b2.custom_minimum_size = Vector2(76, 44 if ThemeFactory.touch() else 30)
		b2.add_theme_font_size_override("font_size", 13)
		var mode := String(mb[0])
		b2.tooltip_text = Metros.mode_name(mode) + (" — " + String(Metros.mode_def(mode).get("text", "")) if mode != "" else
			" — 운영 방식 없이 플레이어가 시설을 짓는다")
		b2.pressed.connect(func():
			_mode_btn[mode].set_pressed_no_signal(true)
			mode_requested.emit(key, mode))
		_mode_row.add_child(b2)
		_mode_btn[mode] = b2
	_ops_rows = _vbox(4)
	_ops_box.add_child(_ops_rows)
	_pick_box = _vbox(4)
	_ops_box.add_child(_pick_box)
	_partner_label = ThemeFactory.muted("", 12)
	_pick_box.add_child(_partner_label)
	_partner_pick = OptionButton.new()
	_partner_pick.add_theme_font_size_override("font_size", 13)
	_partner_pick.custom_minimum_size.y = 44 if ThemeFactory.touch() else 30
	_partner_pick.fit_to_longest_item = false
	_partner_pick.item_selected.connect(func(i: int):
		if i >= 0 and i < _partner_ids.size():
			ops_requested.emit(key, "partner", _partner_ids[i]))
	_pick_box.add_child(_partner_pick)
	_project_label = ThemeFactory.muted("", 12)
	_pick_box.add_child(_project_label)
	_project_pick = OptionButton.new()
	_project_pick.add_theme_font_size_override("font_size", 13)
	_project_pick.custom_minimum_size.y = 44 if ThemeFactory.touch() else 30
	_project_pick.fit_to_longest_item = false
	_project_pick.item_selected.connect(func(i: int):
		if i >= 0 and i < _project_ids.size():
			ops_requested.emit(key, "project", _project_ids[i]))
	_pick_box.add_child(_project_pick)
	_ops_log = _vbox(2)
	_ops_box.add_child(_ops_log)
	_econ_box = _vbox(6)
	inner.add_child(_econ_box)
	_foot = ThemeFactory.muted("", 12)
	_body.add_child(_foot)


static func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


## compact: 휴대폰 — 다른 대도시로 가면 접힌 채로 연다
func show_metro(k: String, compact: bool = false) -> void:
	if k != key:
		key = k
		_sig = ""
		_folded = compact
	refresh()


func set_tab(t: String) -> void:
	_tab = t
	for id in _tab_btn:                          # set_pressed_no_signal은 단추 묶음의 다른 단추를 풀지 않는다
		(_tab_btn[id] as Button).set_pressed_no_signal(id == t)
	_sig = ""
	refresh()


## 바뀐 것이 있을 때만 다시 만든다 (시설·운영·경제·지원·시각). 시간만 흐를 때는 1초에 네 번까지
func refresh() -> void:
	if key == "" or mgr == null:
		return
	var fn := mgr.metro_fn
	var payer: Dictionary = mgr.list[payer_index] if payer_index < mgr.list.size() else {}
	var ps: CitySim = payer.get("sim")
	@warning_ignore("integer_division")
	var day := mgr.hour / 24
	var base := "%s|%s|%s|%d" % [key, str(_folded), _tab, payer_index]
	var sig := "%s|%d|%d|%d|%d|%d" % [base, fn.rev, fn.modes.rev, fn.econ.rev, int(ps.support) if ps else -1, day]
	if sig == _sig:
		return
	if _sig.begins_with(base + "|") and Time.get_ticks_msec() - _built_ms < 250:
		return                                   # 시간만 흘렀다 — 잠시 뒤에
	_sig = sig
	_built_ms = Time.get_ticks_msec()
	var m := Metros.of(key)
	_title.text = "%s  ·  %s" % [String(m.get("name", key)), String(m.get("country", ""))]
	var st := Metros.style_of(m)
	var strong := Metros.strength_name(m)
	var md := fn.modes.mode_of(key)
	_sub.text = "%s · %s%s%s" % [Metros.pop_text(m), String(st.get("name", "")), (" · 강점: " + strong) if strong != "" else "",
		(" · 운영: " + Metros.mode_name(md)) if md != "" else ""]
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
		var more := PackedStringArray()
		if float(y.get("settlers", 0.0)) > 0.0:
			more.append("정착민 %d명" % int(y["settlers"]))
		if float(y.get("parts", 0.0)) > 0.0:
			more.append("부품 %s" % Fmt.n(float(y["parts"]), 1))
		var yest := (" · 어제 더 실은 것: " + ", ".join(more)) if not more.is_empty() else ""
		_flight.text = "우주항 항공편: %s까지 %s · %d시간마다%s" % [Transport.node_name(String(feeder["b"])),
			Fmt.distance_km(float(feeder.get("km", 0.0))), int(feeder["every_h"]), yest]
	_fold.text = "펼치기" if _folded else "접기"
	_tab_row.visible = not _folded
	_scroll.visible = not _folded
	_foot.visible = not _folded
	if _folded:
		return
	_fac_box.visible = _tab == "fac"
	_ops_box.visible = _tab == "ops"
	_econ_box.visible = _tab == "econ"
	match _tab:
		"fac":
			_clear(_fac_box)
			for fac in MetroFunctions.ORDER:
				_fac_box.add_child(_fac_row(fn, fac, ps))
			_foot.text = "지원은 고른 식민지 '%s'이(가) 낸다 — 지금 지구 지원 %s" % [String(payer.get("short", payer.get("name", ""))),
				Fmt.n(ps.support) if ps else "-"]
		"ops":
			_ops_view(fn, ps)
		"econ":
			_econ_view(fn, payer, ps)
	_fit.call_deferred()


## 스크롤 높이: 내용만큼, 카드 전체가 max_h를 넘지 않게 (머리·탭·아랫줄을 뺀 만큼)
func _fit() -> void:
	var box: Control = _fac_box if _tab == "fac" else (_ops_box if _tab == "ops" else _econ_box)
	var rest := get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	_scroll.custom_minimum_size.y = clampf(box.get_combined_minimum_size().y + 4.0, 0.0, maxf(140.0, max_h - rest))
	reset_size()


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


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
	var b := _button("", 118)
	var cost := fn.next_cost(key, fac)
	var why := ""
	if fn.building(key, fac):
		b.text = "짓는 중 %d%%" % int(fn.progress(key, fac, mgr.hour) * 100.0)
		b.disabled = true
	elif cost < 0.0:
		b.text = "다 올렸다"
		b.disabled = true
	else:
		b.text = ("짓기" if lvl == 0 else "%d단계로" % (lvl + 1)) + " · 지원 %s" % Fmt.n(cost)
		why = fn.block_reason(key, fac, ps)
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
	if fac == "outreach" and fn.modes.forfeits_outreach(key, mgr.hour):
		t += " — 우주 산업 수도라 들어오지 않는다"
	if fac == "research" and fn.modes.ally_member(key, mgr.hour, fn):
		t += " — 연구 동맹에 모은다"
	if fac == next_auto(fn):
		t += " · 다음 자동 증설"
	if why != "" and not fn.building(key, fac) and cost >= 0.0:
		t += " (%s)" % why
	var info := ThemeFactory.muted(t, 12)
	info.tooltip_text = String(MetroFunctions.def(fac).get("text", ""))
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(info)
	return v


## 운영 방식이 다음에 올릴 시설 ("" = 운영 방식이 없거나 다 올렸다)
func next_auto(fn: MetroFunctions) -> String:
	return fn.modes.next_build(key, fn) if fn.modes.mode_of(key) != "" else ""


func _button(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 44 if ThemeFactory.touch() else 32)
	b.add_theme_font_size_override("font_size", 13)
	return b


func _line(box: Node, text: String, color: Color = Palette.MUTED, size: int = 12) -> Label:
	var l := ThemeFactory.muted(text, size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


# ── 운영 ───────────────────────────────────────────────────────
func _ops_view(fn: MetroFunctions, ps: CitySim) -> void:
	var mo := fn.modes
	var md := mo.mode_of(key)
	for id in _mode_btn:
		(_mode_btn[id] as Button).set_pressed_no_signal(id == md)
		(_mode_btn[id] as Button).modulate = Metros.mode_color(id).lightened(0.25) if id == md and id != "" else Color.WHITE
	_clear(_ops_rows)
	_clear(_ops_log)
	var hour := mgr.hour
	if md == "":
		_line(_ops_rows, "운영 방식을 고르면 지금 고른 식민지가 후원한다. 운영비(지구 지원)를 맡기면 그 도시가 스스로 시설을 올리고 일한다 — " +
			"① 부품을 더 보내고 · ③ 연구를 함께 하고 · ⑤ 위급하면 비상편을 띄운다.", Palette.MUTED, 12)
		_pick_box.visible = false
		_foot.text = "운영비는 후원 식민지가 맡긴다 — 자동으로 빼는 돈은 그 식민지의 화물선·유인선 비용 아래로 내려가지 않는다"
		return
	var e := mo.entry(key)
	_line(_ops_rows, String(Metros.mode_def(md).get("text", "")), Palette.MUTED, 12)
	var up := mo.upkeep(key)
	var b := mo.budget(key)
	var spons := Transport.node_name(mo.sponsor(key))
	var status := "후원: %s · 운영비 %s · 하루 −%s" % [spons, Fmt.n(b), Fmt.n(up, 1)]
	if up > 0.0:
		status += " (약 %s일)" % Fmt.n(floorf(b / up))
	_line(_ops_rows, status, Palette.TEXT.darkened(0.08), 13)
	if mo.paused(key):
		_line(_ops_rows, "운영비가 바닥나 쉬는 중이다 — 운영비를 맡기면 다시 움직인다", Palette.RED, 12)
	elif not mo.ready(key, hour):
		_line(_ops_rows, "준비 중 — %s일 뒤부터 움직인다" % Fmt.n(ceilf(float(int(e.get("ready_at", 0)) - hour) / 24.0)), Palette.AMBER, 12)
	# 맡기기·자동 채움
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ops_rows.add_child(row)
	var why := ""
	var sp: CitySim = null
	var si := mgr.index_of_site(mo.sponsor(key))
	if si >= 0:
		sp = mgr.list[si]["sim"]
	for amt in MetroModes.rule("deposit_steps", [100, 500]):
		var a := float(amt)
		var db := _button("운영비 +%s" % Fmt.n(a), 96)
		if sp == null or sp.support < a:
			db.disabled = true
			why = "후원 식민지 %s의 지구 지원이 모자란다 (%s)" % [spons, Fmt.n(sp.support) if sp != null else "-"]
		elif fn.econ.arrears_of(mo.sponsor(key)) > 0.0:
			db.disabled = true
			why = "후원 식민지의 채권이 밀려 있어 맡길 수 없다"
		db.pressed.connect(func(): ops_requested.emit(key, "deposit", a))
		row.add_child(db)
	var af := CheckButton.new()
	af.text = "자동 채움"
	af.add_theme_font_size_override("font_size", 13)
	af.button_pressed = bool(e.get("auto_fill", false))
	var afr: Dictionary = MetroModes.rule("auto_fill", {})
	af.tooltip_text = "후원 식민지의 지원이 화물선·유인선 비용 + %s를 넘으면 날마다 %s까지 채운다 (운영비 %s까지)" % [
		Fmt.n(float(afr.get("margin", 100))), Fmt.n(float(afr.get("per_day", 20))), Fmt.n(float(afr.get("target", 1000)))]
	af.toggled.connect(func(on: bool): ops_requested.emit(key, "auto_fill", on))
	row.add_child(af)
	if why != "":
		_line(_ops_rows, why, Palette.AMBER, 12)
	# 다음 증설
	var nb := mo.next_build(key, fn)
	if nb == "":
		_line(_ops_rows, "자동 증설: 다 올렸다 — 운영비는 상시 비용과 일에만 쓴다")
	elif _any_building(fn):
		_line(_ops_rows, "자동 증설: 짓는 중인 시설이 끝나면 %s %d단계" % [MetroFunctions.fac_name(nb), mo.next_level(key, nb, fn)])
	else:
		_line(_ops_rows, "자동 증설: %s %d단계 · 운영비 %s (그 뒤에도 %s를 남긴다)" % [MetroFunctions.fac_name(nb), mo.next_level(key, nb, fn),
			Fmt.n(fn.next_cost(key, nb)), Fmt.n(mo.keep(key))])
	match md:
		"parts_capital":
			_parts_lines(fn)
		"research_alliance":
			_ally_lines(fn)
		"emergency_depot":
			_depot_lines(fn)
	_pickers(fn, md)
	# 자동으로 한 일
	var lg := mo.log_of(key)
	if not lg.is_empty():
		_line(_ops_log, "자동으로 한 일", Palette.TEXT.darkened(0.1), 12)
		for i in range(lg.size() - 1, maxi(-1, lg.size() - 5), -1):
			var r: Array = lg[i]
			_line(_ops_log, "%s  %s" % [mgr.date_text(float(r[0])).substr(5), String(r[1])], Palette.MUTED, 11)
	_foot.text = "운영비는 후원 식민지 '%s'이(가) 맡긴다 — 협력 지역·자동 증설·창고는 운영비에서" % spons


func _any_building(fn: MetroFunctions) -> bool:
	for f in MetroFunctions.ORDER:
		if fn.building(key, f):
			return true
	return false


func _parts_lines(fn: MetroFunctions) -> void:
	var mo := fn.modes
	var moon := mo.short_on(mgr, "moon")
	var far := 0.0
	for site in mo.short:
		if Transport.node_body(String(site)) != "moon":
			far += float(mo.short[site])
	_line(_ops_rows, "항공편 부품 ×%s (협력 지역 +%d%%) · 홍보관의 지원은 들어오지 않는다" % [Fmt.n(mo.parts_k(key, mgr.hour), 2),
		int(round(mo.partner_bonus(key) * 100.0))])
	if moon >= 1.0:
		var rc: Dictionary = Metros.mode_def("parts_capital").get("rush", {})
		var next_ok := mo.rush_h + int(rc.get("cooldown_h", 168))
		_line(_ops_rows, "달 식민지에 부품 %s 모자람 — 50 넘게 모자라고 정기 셔틀이 이틀 넘게 남으면 우주항의 부품을 급송 셔틀로 보낸다%s" % [
			Fmt.n(moon), (" (다음 급송 %s부터)" % mgr.date_text(float(next_ok))) if next_ok > mgr.hour else ""], Palette.AMBER)
	else:
		_line(_ops_rows, "달 식민지의 부품이 넉넉하다 — 급송 셔틀은 쉰다")
	if far >= 1.0:
		_line(_ops_rows, "먼 행성 식민지에 부품 %s 모자람 — 수송선이 떠날 때 부품을 사서 더 싣는다 (부품 하나 %s)" % [Fmt.n(far),
			Fmt.n(float(Metros.mode_def("parts_capital").get("ship", {}).get("cost_per_part", 0.5)) * mo.freight_k(), 2)])
	var y: Dictionary = fn.last.get(key, {})
	var bits := PackedStringArray()
	if float(y.get("forfeit", 0.0)) > 0.0:
		bits.append("못 받은 지원 %s" % Fmt.n(float(y["forfeit"]), 1))
	if float(y.get("rush", 0.0)) > 0.0:
		bits.append("급송 운임 %s" % Fmt.n(float(y["rush"]), 1))
	if float(y.get("ship_parts", 0.0)) > 0.0:
		bits.append("수송선 부품값 %s" % Fmt.n(float(y["ship_parts"]), 0))
	if not bits.is_empty():
		_line(_ops_rows, "어제: " + " · ".join(bits))


func _ally_lines(fn: MetroFunctions) -> void:
	var mo := fn.modes
	var members := mo.keys_of("research_alliance", mgr.hour)
	var names := PackedStringArray()
	for k in members:
		names.append(String(Metros.of(k).get("name", k)))
	_line(_ops_rows, "동맹 %d곳 (%s) · 함께 +%d%%" % [members.size(), ", ".join(names),
		int(round((mo.synergy(members.size()) - 1.0) * 100.0))], Palette.TEXT.darkened(0.1))
	if fn.level(key, "research") < 1:
		_line(_ops_rows, "이 도시는 우주 연구소를 지어야 동맹에 연구 점수를 보탠다 — 운영비로 곧 짓는다", Palette.AMBER)
	var id := mo.project(mgr)
	if id == "":
		_line(_ops_rows, "과제가 없다 — 연구 점수는 식민지가 받는다")
	else:
		var cost := mo.project_cost(id, mgr)
		var pool := float(mo.alliance["pool"])
		var eta := ""
		if mo.last_gain > 0.0 and cost > pool:
			eta = " · 약 %s일" % Fmt.n(ceilf((cost - pool) / mo.last_gain))
		_line(_ops_rows, "과제: %s%s — %s / %s (%d%%) · 하루 +%s%s" % [MetroModes.project_name(id),
			" (동맹 기술)" if Metros.alliance.has(id) else " (15% 싸게)", Fmt.n(pool), Fmt.n(cost),
			int(clampf(pool / maxf(cost, 1.0), 0.0, 1.0) * 100.0), Fmt.n(mo.last_gain, 1), eta])
	var done := PackedStringArray()
	for d in mo.alliance["done"]:
		done.append(MetroModes.project_name(String(d)))
	if not done.is_empty():
		_line(_ops_rows, "동맹 기술: " + " · ".join(done) + " ✓")


func _depot_lines(fn: MetroFunctions) -> void:
	var mo := fn.modes
	var dep := mo.depot(key)
	var names := {"o2_kg": "산소", "food_kg": "식량", "water_kg": "물", "parts": "부품"}
	var bits := PackedStringArray()
	for k in ["o2_kg", "food_kg", "water_kg", "parts"]:
		var have := float(dep.get(k, 0.0))
		var cap := mo.depot_cap(key, k, fn)
		if k == "parts":
			bits.append("%s %s/%s" % [names[k], Fmt.n(have), Fmt.n(cap)])
		else:
			bits.append("%s %s/%s t" % [names[k], Fmt.n(have / 1000.0, 1), Fmt.n(cap / 1000.0, 1)])
	_line(_ops_rows, "비상 창고 (우주항 옆): " + " · ".join(bits), Palette.TEXT.darkened(0.1))
	var al: Dictionary = Metros.mode_def("emergency_depot").get("alarm_days", {})
	var plus := mo.alarm_plus(mgr.hour)
	_line(_ops_rows, "경보: 산소 %d일 · 식량 %d일 · 물 %d일 아래, 정전에 축전 15%% 아래%s — 3시간마다 살핀다" % [
		int(al.get("o2_kg", 6)) + plus, int(al.get("food_kg", 8)) + plus, int(al.get("water_kg", 5)) + plus,
		(" (예측 +%d일)" % plus) if plus > 0 else ""])
	var going := PackedStringArray()
	for t in mgr.transport.trips:
		if String(t.get("tag", "")) == "emergency":
			going.append("%s행 %s 도착" % [Transport.node_name(String(t["to"])), mgr.date_text(float(t["arrive"])).substr(5)])
	_line(_ops_rows, ("비상편 가는 중: " + ", ".join(going)) if not going.is_empty() else "지금 가는 비상편 없음",
		Palette.RED if not going.is_empty() else Palette.MUTED)
	var d := Metros.mode_def("emergency_depot")
	_line(_ops_rows, "달은 지구→달 셔틀로 72시간 (수수료 %s + 운임 t당 %s), 다른 천체는 같은 천체의 이웃 도시가 나눈다 (수수료 %s)" % [
		Fmt.n(float(d.get("shuttle_fee", 100))), Fmt.n(Transport.freight_per_t() * mo.freight_k(), 1), Fmt.n(float(d.get("local_fee", 40)))])


## 협력 지역·과제 고르기 (목록은 바뀔 때만 다시 채운다 — 열린 목록이 닫히지 않게)
func _pickers(fn: MetroFunctions, md: String) -> void:
	var mo := fn.modes
	_pick_box.visible = true
	var cur := mo.partner_of(key)
	var r := Metros.region(cur)
	if r.is_empty():
		_partner_label.text = "협력 지역 없음 — 반도체·AI 데이터센터 지역과 손잡으면 몫이 커진다 (계약은 운영비에서, 하루 %s)" % Fmt.n(
			float(MetroModes.rule("partner_upkeep_day", 0.2)), 1)
	else:
		var bt := MetroModes.bonus_text(md, r)
		_partner_label.text = "협력 지역: %s (%s) — %s" % [String(r["name"]), Fmt.distance_km(Metros.km_between(Metros.of(key)["dir"], r["dir"])),
			bt if bt != "" else "이 운영 방식에는 효과가 없다"]
	if not _partner_pick.get_popup().visible:
		var regs := Metros.regions.duplicate()
		var here: Vector3 = Metros.of(key)["dir"]
		regs.sort_custom(func(a, b):
			var ba := MetroModes.bonus_for(md, a) + 0.1 * MetroModes.alarm_days_for(a)
			var bb := MetroModes.bonus_for(md, b) + 0.1 * MetroModes.alarm_days_for(b)
			if absf(ba - bb) > 1e-6:
				return ba > bb
			return Metros.km_between(here, a["dir"]) < Metros.km_between(here, b["dir"]))
		var items: Array = [["", "협력 지역 고르기…" if cur == "" else "협력 끝내기"]]
		for rr in regs:
			var bt2 := MetroModes.bonus_text(md, rr)
			items.append([String(rr["key"]), "%s · %s · %s · 계약 %s" % [String(rr["name"]), bt2 if bt2 != "" else "효과 없음",
				Fmt.distance_km(Metros.km_between(here, rr["dir"])), Fmt.n(MetroModes.partner_cost(key, rr))]])
		_fill_pick(_partner_pick, items, cur, true)
	_partner_ids = []
	for i in _partner_pick.item_count:
		_partner_ids.append(String(_partner_pick.get_item_metadata(i)))
	var ally := md == "research_alliance"
	_project_label.visible = ally
	_project_pick.visible = ally
	if ally:
		_project_label.text = "과제 — 자동이면 고향 식민지의 연구 순서를 따른다"
		if not _project_pick.get_popup().visible:
			var items2: Array = [["", "자동 (고향의 연구 순서)"]]
			for p in mo.projects(mgr):
				items2.append([String(p[0]), "%s · %s%s" % [String(p[1]), Fmt.n(float(p[2])), " (동맹 기술)" if bool(p[3]) else ""]])
			_fill_pick(_project_pick, items2, String(mo.alliance["project"]), false)
		_project_ids = []
		for i2 in _project_pick.item_count:
			_project_ids.append(String(_project_pick.get_item_metadata(i2)))


## 목록이 바뀔 때만 다시 채운다. first_is_action: 고른 것이 없으면 첫 항목(안내)을 보인다
static func _fill_pick(pick: OptionButton, items: Array, cur: String, first_is_action: bool) -> void:
	var sig := ""
	for it in items:
		sig += String(it[0]) + ":" + String(it[1]) + "|"
	if String(pick.get_meta("sig", "")) != sig:
		pick.clear()
		for i in items.size():
			pick.add_item(String(items[i][1]))
			pick.set_item_metadata(i, String(items[i][0]))
		pick.set_meta("sig", sig)
	var sel := 0
	for i2 in items.size():
		if String(items[i2][0]) == cur and (cur != "" or not first_is_action):
			sel = i2
	pick.select(sel)


# ── 경제 ───────────────────────────────────────────────────────
func _econ_view(fn: MetroFunctions, payer: Dictionary, ps: CitySim) -> void:
	_clear(_econ_box)
	var ec := fn.econ
	var site := String(payer.get("site", ""))
	var y: Dictionary = fn.last.get(key, {})
	# 상업
	var comm := Metros.districts_of(key, "commerce")
	var cnames := PackedStringArray()
	for d in comm:
		cnames.append(String(d[0]))
	_line(_econ_box, "상업 — %s (상업 지수 %s)" % [" · ".join(cnames) if not cnames.is_empty() else "상권 자료 없음",
		Fmt.n(MetroEconomy.commerce_power(key), 2)], Palette.AMBER.lightened(0.2), 14)
	if not comm.is_empty():
		var dt := Time.get_datetime_dict_from_unix_time(mgr.unix_at(float(mgr.hour)))
		var wd: Array = MetroEconomy.cfg("commerce").get("weekday", [])
		var days_ko := ["일", "월", "화", "수", "목", "금", "토"]
		var wdi := int(dt["weekday"])
		_line(_econ_box, "어제 닿은 국제선 승객 %s명 · 우주 화제 %s · 오늘(%s) ×%s" % [Fmt.n(float(ec.pax.get(key, 0))), Fmt.n(ec.buzz, 2),
			days_ko[wdi], Fmt.n(float(wd[wdi]) if wdi < wd.size() else 1.0, 2)])
		var c: Dictionary = ec.commerce.get(key, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_econ_box.add_child(row)
		if c.is_empty():
			var cost := MetroEconomy.commerce_cost(key)
			var lb := _line(row, "우주 상점가를 열면 날마다 오늘은 약 +%s (계약한 식민지가 받는다)" % Fmt.n(ec.commerce_today(key, mgr), 2))
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := _button("상점가 계약 · 지원 %s" % Fmt.n(cost), 150)
			b.disabled = ps == null or ps.support < cost
			b.pressed.connect(func(): ops_requested.emit(key, "commerce", null))
			row.add_child(b)
			if b.disabled:
				_line(_econ_box, "지구 지원이 모자란다 (%s 필요)" % Fmt.n(cost), Palette.AMBER)
		else:
			var lb2 := _line(row, "계약 중 — %s이(가) 받는다 · 어제 +%s" % [Transport.node_name(String(c["site"])), Fmt.n(float(y.get("commerce", 0.0)), 2)],
				Palette.GREEN)
			lb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b2 := _button("끝내기", 72)
			b2.pressed.connect(func(): ops_requested.emit(key, "commerce_close", null))
			row.add_child(b2)
	# 금융
	var fin := Metros.districts_of(key, "finance")
	var fnames := PackedStringArray()
	for d2 in fin:
		fnames.append(String(d2[0]))
	_line(_econ_box, "금융 — %s (금융 지수 %s)" % [" · ".join(fnames) if not fnames.is_empty() else "금융가 자료 없음",
		Fmt.n(MetroEconomy.finance_power(key), 2)], Palette.TEAL.lightened(0.2), 14)
	if not fin.is_empty():
		var l: Dictionary = ec.loans.get(key, {})
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		_econ_box.add_child(row2)
		if l.is_empty():
			var t := MetroEconomy.loan_terms(key)
			var lb3 := _line(row2, "우주 채권: %s 빌리기 — %d일 동안 하루 %s씩 갚는다 (이자 %s%%)" % [Fmt.n(float(t["amount"])), int(t["days"]),
				Fmt.n(float(t["pay"]), 2), Fmt.n(float(t["rate"]) * 100.0, 1)])
			lb3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b3 := _button("빌리기", 72)
			var why := ""
			if ec.arrears_of(site) > 0.0:
				why = "밀린 채권이 있다"
			elif ec.loans_of(site) >= int(MetroEconomy.cfg("loan").get("max_per_colony", 3)):
				why = "이 식민지는 채권을 더 빌릴 수 없다"
			b3.disabled = why != "" or ps == null
			b3.pressed.connect(func(): ops_requested.emit(key, "borrow", null))
			row2.add_child(b3)
			if why != "":
				_line(_econ_box, why, Palette.AMBER)
		else:
			_line(row2, "갚는 중 (%s) — 남은 %d일 · 하루 %s%s" % [Transport.node_name(String(l["site"])), int(l["days_left"]),
				Fmt.n(float(l["pay"]), 2), (" · 밀린 것 %s" % Fmt.n(float(l["arrears"]), 1)) if float(l["arrears"]) > 0.0 else ""],
				Palette.RED if float(l["arrears"]) > 0.0 else Palette.TEXT.darkened(0.1))
		var f: Dictionary = ec.funds.get(key, {})
		var row3 := HBoxContainer.new()
		row3.add_theme_constant_override("separation", 6)
		_econ_box.add_child(row3)
		var ft := ""
		if f.is_empty():
			ft = "우주 펀드: 아직 넣지 않았다 — 기대 수익 해마다 약 7%, 손해를 볼 수도 있다"
		else:
			var g := (float(f["value"]) / maxf(float(f["paid"]), 1.0) - 1.0) * 100.0
			ft = "우주 펀드 (%s): 넣은 %s → 지금 %s (%s%s%%)" % [Transport.node_name(String(f["site"])), Fmt.n(float(f["paid"])),
				Fmt.n(float(f["value"])), "+" if g >= 0.0 else "", Fmt.n(g, 1)]
		var lb4 := _line(row3, ft)
		lb4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for amt in MetroEconomy.cfg("fund").get("steps", [100, 250]):
			var a := float(amt)
			var bi := _button("+%s" % Fmt.n(a), 56)
			bi.disabled = ps == null or ps.support < a or (not f.is_empty() and String(f["site"]) != site)
			bi.pressed.connect(func(): ops_requested.emit(key, "invest", a))
			row3.add_child(bi)
		if not f.is_empty():
			var bw := _button("찾기", 56)
			bw.tooltip_text = "수수료 1%를 떼고 펀드를 가진 식민지가 받는다"
			bw.pressed.connect(func(): ops_requested.emit(key, "withdraw", null))
			row3.add_child(bw)
	var ch := ec.index_change(30) * 100.0
	_line(_econ_box, "우주 산업 지수 %s · 어제 %s%s%% · 30일 %s%s%%%s" % [Fmt.n(ec.index), "+" if ec.last_return >= 0.0 else "",
		Fmt.n(ec.last_return * 100.0, 2), "+" if ch >= 0.0 else "", Fmt.n(ch, 1), " · 떨어지는 중" if ec.crash_left > 0 else ""])
	_foot.text = "돈은 고른 식민지 '%s'의 지구 지원이다 — 지금 %s" % [String(payer.get("short", payer.get("name", ""))),
		Fmt.n(ps.support) if ps else "-"]
