class_name TransportPanel
extends VBoxContainer
## 교통 탭 — 도시 사이 교통 전체와 노선 하나하나를 켜고 끈다. 노선마다 탈것·거리·걸리는 시간·다음 출발·누계,
## 가는 중인 행성간 수송선의 진행. '보기'를 누르면 3D 지도가 그 노선을 비춘다.

signal changed
signal show_line(id: String)
signal show_metro(key: String)

const GROUPS := [["space", "우주 노선 — 지구-달 셔틀 · 행성간 수송선"], ["local", "천체 안의 노선"],
	["feeder", "지구 항공 — 대도시에서 우주항으로"], ["air", "지구 항공 — 대도시 국제선"]]

var sim: CitySim
var mgr: Colonies
var status := Label.new()
var master := CheckButton.new()
var box := VBoxContainer.new()
var _live: Array = []
var _open := {"space": true, "local": true, "feeder": false, "air": false}
var _shape := ""         # 노선·켜짐·펼침·운영 중인 대도시 — 바뀔 때만 다시 만든다 (나머지는 _live가 고친다)
var _form := {"from": "", "to": "", "key": "water_kg", "amount": 5.0, "every": 7}   # 정기 교역을 더하는 칸 (다시 만들어도 이어 간다)
var _form_note := ""
const ROUTE_AMOUNT := {"water_kg": 5.0, "o2_kg": 2.0, "food_kg": 2.0, "parts": 50.0, "metal_t": 5.0}   # 물건을 고르면 넣는 양


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("교통"))
	master.text = "도시 사이 교통 운행"
	master.button_pressed = true
	master.custom_minimum_size.y = 40
	master.toggled.connect(func(on: bool):
		if mgr != null:
			mgr.transport.set_enabled(mgr, on)
			changed.emit()
			rebuild())
	add_child(master)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	add_child(status)
	var help := ThemeFactory.muted("같은 천체의 도시는 로버 화물 열차·로켓 호퍼·비행기로, 지구 우주항과 달의 고향은 셔틀로, 행성 사이는 " +
		"발사 창마다 수송선으로 잇는다. 떠날 때 받는 도시에 모자란 식량·산소·물·부품·금속을 보내는 도시의 넉넉한 몫에서 싣고, " +
		"주거에 빈자리가 있으면 지구나 붐비는 도시의 정착민이 탄다. 지구에서 우주로 올리는 화물은 보내는 도시가 운임(지원 점수)을 낸다. " +
		"지구의 대도시는 가까운 우주항으로 정착민과 부품을 보낸다 ('도시'를 누르면 그 도시 위로 날아간다). " +
		"3D 지도에서 노선과 오가는 탈것이 보인다.", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	box.add_theme_constant_override("separation", 8)
	add_child(box)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	rebuild()


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func update_view() -> void:
	if mgr == null:
		return
	var tr := mgr.transport
	master.set_pressed_no_signal(tr.enabled)
	var on_n := 0
	for l in tr.lines:
		if l["on"]:
			on_n += 1
	var tt: Dictionary = tr.totals
	status.text = "노선 %d개 (운행 %d) · 지금 움직이는 탈것 %d · 지금까지 화물 %s t · 정착민 %s명 · 승객 %s명%s" % [
		tr.lines.size(), on_n, tr.trips.size(), Fmt.n(float(tt.get("t", 0.0)), 1), Fmt.n(float(tt.get("settlers", 0))),
		Fmt.n(float(tt.get("pax", 0))), "" if tr.enabled else " — 운행을 멈췄다"]
	status.add_theme_color_override("font_color", Palette.TEXT if tr.enabled else Palette.AMBER)
	for f in _live:
		(f as Callable).call()


func _shape_sig() -> String:
	var fn := mgr.metro_fn
	return "%d|%d|%s|%s|%d|%d|%d|%d" % [mgr.transport.lines.size(), mgr.transport.rev, str(_open),
		",".join(PackedStringArray(fn.keys_with_ops())), fn.active_keys().size(), fn.modes.metros.size(), mgr.routes.size(),
		mgr.list.size()]


## 탭을 고를 때·날마다: 모양이 그대로면 글만 고친다 (다시 만들면 노선이 많을 때 수십 ms)
func refresh() -> void:
	if mgr == null:
		return
	if _shape_sig() != _shape:
		rebuild()
	else:
		update_view()


func rebuild() -> void:
	if mgr == null:
		return
	_shape = _shape_sig()
	_live.clear()
	_clear(box)
	var tr := mgr.transport
	var by_group := {"space": [], "local": [], "feeder": [], "air": []}
	for l in tr.lines:
		match String(l["role"]):
			"shuttle", "ship":
				by_group["space"].append(l)
			"local":
				by_group["local"].append(l)
			"feeder":
				by_group["feeder"].append(l)
			_:
				by_group["air"].append(l)
	by_group["local"].sort_custom(func(a, b): return Colonies.BODY_ORDER.find(a["body"]) < Colonies.BODY_ORDER.find(b["body"]))
	_routes_section()
	_metro_section()
	for g in GROUPS:
		var ls: Array = by_group[g[0]]
		if ls.is_empty():
			continue
		box.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		var title := ThemeFactory.heading("%s · %d" % [g[1], ls.size()], 15)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(title)
		var fold := Button.new()
		fold.text = "접기" if _open[g[0]] else "펼치기"
		fold.custom_minimum_size = Vector2(0, 32)
		fold.add_theme_font_size_override("font_size", 12)
		var key: String = g[0]
		fold.pressed.connect(func():
			_open[key] = not _open[key]
			rebuild())
		head.add_child(fold)
		box.add_child(head)
		if not _open[g[0]]:
			box.add_child(_group_summary(ls))
			continue
		var compact: bool = g[0] in ["feeder", "air"]
		for l in ls:
			box.add_child(_compact_row(l) if compact else _line_card(l))
	if tr.lines.is_empty():
		box.add_child(ThemeFactory.muted("아직 이을 도시가 없다."))
	update_view()


## 정기 교역 (CityRoutes): 더하는 칸 (보내는 도시 → 받는 도시 · 물건 · 양 · 며칠마다)과 정한 것들 (켜기 · 지난 번 · 지우기)
func _routes_section() -> void:
	box.add_child(HSeparator.new())
	box.add_child(ThemeFactory.heading("정기 교역 · %d" % mgr.routes.size(), 15))
	box.add_child(ThemeFactory.muted("정한 날마다 보내는 도시의 남는 몫(사람이 쓸 날수·부품 200·금속 20을 남기고)에서 실어 그 노선의 특별편으로 " +
		"보낸다 — 같은 천체의 도시끼리, 지구 우주항과 달 고향 사이 셔틀로. 셔틀은 보내는 도시가 운임(지원 점수)을 낸다. " +
		"행성 사이는 수송선이 발사 창마다 모자란 것을 실어 나른다.", 12))
	var sites: Array = []
	for c in mgr.list:
		sites.append(String(c["site"]))
	if sites.size() < 2:
		box.add_child(ThemeFactory.muted("도시가 둘 이상이어야 한다.", 12))
		return
	if not String(_form["from"]) in sites:
		_form["from"] = sim.site_id if sim != null and sim.site_id in sites else sites[0]
	if not String(_form["to"]) in sites or String(_form["to"]) == String(_form["from"]):
		_form["to"] = ""
		for s2 in sites:
			if not CityRoutes.link(mgr, String(_form["from"]), s2).is_empty():
				_form["to"] = s2
				break
		if String(_form["to"]) == "":
			_form["to"] = sites[1] if sites[0] == String(_form["from"]) else sites[0]
	var form := HFlowContainer.new()
	form.add_theme_constant_override("h_separation", 6)
	form.add_theme_constant_override("v_separation", 6)
	var pick := func(ids: Array, names: Array, cur: String, field: String) -> OptionButton:
		var ob := OptionButton.new()
		ob.add_theme_font_size_override("font_size", 13)
		ob.custom_minimum_size = Vector2(0, 44 if OS.has_feature("mobile") else 32)
		ob.fit_to_longest_item = false
		for i in ids.size():
			ob.add_item(String(names[i]), i)
			if String(ids[i]) == cur:
				ob.select(i)
		ob.item_selected.connect(func(i: int):
			_form[field] = String(ids[i])
			if field == "key":
				_form["amount"] = float(ROUTE_AMOUNT.get(String(ids[i]), 1.0))
			_form_note = ""
			rebuild())
		return ob
	var names: Array = sites.map(func(x): return Transport.node_name(String(x)))
	form.add_child(pick.call(sites, names, String(_form["from"]), "from"))
	form.add_child(ThemeFactory.muted("→", 14))
	form.add_child(pick.call(sites, names, String(_form["to"]), "to"))
	var keys: Array = CityRoutes.GOODS.map(func(g): return String(g[0]))
	form.add_child(pick.call(keys, CityRoutes.GOODS.map(func(g): return String(g[1])), String(_form["key"]), "key"))
	var g := CityRoutes.good_of(String(_form["key"]))
	var amount := SpinBox.new()
	amount.min_value = 0.5 if float(g[2]) > 1.0 else 1.0
	amount.max_value = 300.0 if float(g[2]) > 1.0 else 2000.0
	amount.step = 0.5 if float(g[2]) > 1.0 else 1.0
	amount.value = float(_form["amount"])
	amount.suffix = String(g[3])
	amount.custom_minimum_size = Vector2(110, 32)
	amount.value_changed.connect(func(v: float): _form["amount"] = v)
	form.add_child(amount)
	var every := SpinBox.new()
	every.min_value = 1
	every.max_value = 120
	every.step = 1
	every.value = int(_form["every"])
	every.suffix = "일마다"
	every.custom_minimum_size = Vector2(120, 32)
	every.value_changed.connect(func(v: float): _form["every"] = int(v))
	form.add_child(every)
	var add := Button.new()
	add.text = "정기 교역 추가"
	add.custom_minimum_size = Vector2(0, 44 if OS.has_feature("mobile") else 32)
	add.pressed.connect(func():
		var why := CityRoutes.add(mgr, String(_form["from"]), String(_form["to"]), String(_form["key"]), float(_form["amount"]),
			int(_form["every"]))
		_form_note = why if why != "" else "더했다 — 오늘 하루가 끝날 때 처음 떠난다"
		changed.emit()
		rebuild())
	form.add_child(add)
	box.add_child(form)
	var why_now := CityRoutes.check(mgr, String(_form["from"]), String(_form["to"]), String(_form["key"]), float(_form["amount"]),
		int(_form["every"]))
	var note := ThemeFactory.muted(_form_note if _form_note != "" else (why_now if why_now != "" else "이어진 노선: %s" %
		_route_way(String(_form["from"]), String(_form["to"]))), 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if why_now != "" and _form_note == "":
		note.add_theme_color_override("font_color", Palette.AMBER)
	box.add_child(note)
	for r in mgr.routes:
		box.add_child(_route_row(r))


## 그 정기 교역이 탈 노선: "로버 화물 열차 · 1일 6시간 길"
func _route_way(from: String, to: String) -> String:
	var lk := CityRoutes.link(mgr, from, to)
	if lk.is_empty():
		return "없다"
	var l := mgr.transport.line_by_id(String(lk[0]))
	var h := int(lk[3]) if int(lk[3]) > 0 else int(l["trip_h"])
	return "%s · %s 길%s" % [Transport.mode_name(String(l["mode"])), Fmt.hours(float(h)),
		" · 운임 t마다 지원 %s" % Fmt.n(Transport.freight_per_t() * mgr.metro_fn.modes.freight_k(), 1) if String(l["role"]) == "shuttle" else ""]


func _route_row(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 9))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var on := CheckBox.new()
	on.button_pressed = bool(r["on"])
	on.tooltip_text = "이 정기 교역을 보낸다"
	on.toggled.connect(func(p: bool):
		r["on"] = p
		changed.emit()
		update_view())
	top.add_child(on)
	var title := Label.new()
	title.text = CityRoutes.text(r)
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", 13)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var del := Button.new()
	del.text = "지우기"
	del.custom_minimum_size = Vector2(56, 34)
	del.add_theme_font_size_override("font_size", 12)
	var id := int(r["id"])
	del.pressed.connect(func():
		CityRoutes.remove(mgr, id)
		_form_note = ""
		changed.emit()
		rebuild())
	top.add_child(del)
	var info := ThemeFactory.muted("", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	_live.append(func():
		var g := CityRoutes.good_of(String(r["key"]))
		var when := "멈춤" if not bool(r["on"]) else "다음 %s" % mgr.date_text(float(int(r["next"]) * 24))
		info.text = "%d번 보냄 · 모두 %s %s · %s%s" % [int(r["sent"]), Fmt.n(float(r["moved"]), 1 if float(g[2]) > 1.0 else 0), g[3], when,
			(" · 지난 번: " + String(r["last"])) if String(r["last"]) != "" else ""]
		title.add_theme_color_override("font_color", Palette.TEXT if bool(r["on"]) else Palette.MUTED))
	return card


## 대도시의 우주 시설: 시설이 있는 대도시마다 단계와 어제의 몫, 그리고 26곳으로 가는 단추
func _metro_section() -> void:
	var fn := mgr.metro_fn
	box.add_child(HSeparator.new())
	var keys := fn.keys_with_ops()
	box.add_child(ThemeFactory.heading("대도시 · 우주 시설 %d곳 · 운영 방식 %d곳" % [fn.active_keys().size(), fn.modes.metros.size()], 15))
	box.add_child(ThemeFactory.muted("대도시 위로 가면 (아래 단추, 3D 지도의 대도시 이름) 오른쪽 위 카드에서 우주 산업 단지·이주 지원 센터·" +
		"우주 연구소·우주 홍보관·공항 화물 터미널을 고른 식민지의 지구 지원 점수로 짓고 올린다. 큰 도시일수록, 그 도시의 강점(★)일수록 몫이 크다. " +
		"'운영' 탭에서 운영 방식(①우주 산업 수도 ③연구 동맹 ⑤비상 보급 기지)을 고르면 운영비로 스스로 일하고, '경제' 탭에서 " +
		"그 도시의 상권·금융가와 계약한다. 반도체·AI 데이터센터 지역(◆)과 협력하면 운영 방식의 몫이 커진다.", 12))
	var summary := ThemeFactory.muted("", 12)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Palette.TEXT.darkened(0.1))
	box.add_child(summary)
	var upd_sum := func(): summary.text = _ops_summary(fn)
	upd_sum.call()
	_live.append(upd_sum)
	for key in keys:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lab := Label.new()
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_font_size_override("font_size", 13)
		var k: String = key
		var update := func():
			var bits := PackedStringArray()
			for fac in MetroFunctions.ORDER:
				var lvl := fn.level(k, fac)
				if lvl > 0 or fn.building(k, fac):
					bits.append("%s %s%s" % [String(MetroFunctions.def(fac).get("short", fac)), "●".repeat(lvl),
						"…" if fn.building(k, fac) else ""])
			var y: Dictionary = fn.last.get(k, {})
			var ys := PackedStringArray()
			if float(y.get("parts", 0.0)) > 0.0:
				ys.append("부품 %s" % Fmt.n(float(y["parts"]), 1))
			if float(y.get("settlers", 0.0)) > 0.0:
				ys.append("정착민 %d" % int(y["settlers"]))
			if float(y.get("rp", 0.0)) > 0.0:
				ys.append("연구 %s" % Fmt.n(float(y["rp"]), 1))
			if float(y.get("rp_ally", 0.0)) > 0.0:
				ys.append("동맹 연구 %s" % Fmt.n(float(y["rp_ally"]), 1))
			if float(y.get("support", 0.0)) > 0.0:
				ys.append("지원 %s" % Fmt.n(float(y["support"]), 1))
			if float(y.get("commerce", 0.0)) > 0.0:
				ys.append("상권 +%s" % Fmt.n(float(y["commerce"]), 1))
			if absf(float(y.get("fund", 0.0))) >= 0.05:
				ys.append("펀드 %s%s" % ["+" if float(y["fund"]) >= 0.0 else "", Fmt.n(float(y["fund"]), 1)])
			var lines := PackedStringArray(["%s — %s" % [String(Metros.of(k).get("name", k)),
				" · ".join(bits) if not bits.is_empty() else "우주 시설 없음"]])
			var md := fn.modes.mode_of(k)
			if md != "":
				lines.append("운영: %s · 운영비 %s · %s" % [Metros.mode_name(md), Fmt.n(fn.modes.budget(k)),
					fn.modes.status_short(k, mgr, fn)])
			var ec := PackedStringArray()
			if fn.econ.commerce.has(k):
				ec.append("우주 상점가")
			if fn.econ.loans.has(k):
				ec.append("우주 채권 %s일 남음" % Fmt.n(float(fn.econ.loans[k]["days_left"])))
			if fn.econ.funds.has(k):
				ec.append("우주 펀드 %s" % Fmt.n(float(fn.econ.funds[k]["value"])))
			if not ec.is_empty():
				lines.append("경제: " + " · ".join(ec))
			if not ys.is_empty():
				lines.append("어제: " + ", ".join(ys))
			lab.text = "\n".join(lines)
		update.call()
		_live.append(update)
		row.add_child(lab)
		var go := Button.new()
		go.text = "보기"
		go.custom_minimum_size = Vector2(56, 32)
		go.pressed.connect(func(): show_metro.emit(k))
		row.add_child(go)
		box.add_child(row)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	Metros.load_all()
	for m in Metros.list:
		var b := Button.new()
		var mk := String(m["key"])
		b.text = String(m["name"]) + (" ★" if fn.levels_total(mk) > 0 else "") + (" ◎" if fn.modes.mode_of(mk) != "" else "")
		b.tooltip_text = "%s · %s · 강점: %s%s" % [String(m["country"]), Metros.pop_text(m), Metros.strength_name(m),
			(" · 운영: " + Metros.mode_name(fn.modes.mode_of(mk))) if fn.modes.mode_of(mk) != "" else ""]
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func(): show_metro.emit(mk))
		flow.add_child(b)
	box.add_child(flow)


## 운영 방식·경제·첨단 산업 지역을 줄 몇 개로
func _ops_summary(fn: MetroFunctions) -> String:
	var m := fn.modes
	var e := fn.econ
	var out := PackedStringArray()
	var ally := m.keys_of("research_alliance", -2)
	if not ally.is_empty():
		var id := m.project(mgr)
		var cost := m.project_cost(id, mgr) if id != "" else 0.0
		out.append("연구 동맹 %d곳 (회원 %d) — 과제 %s · 모은 점수 %s%s · 어제 +%s · 동맹 기술 %d/%d" % [ally.size(),
			m.keys_of("research_alliance", mgr.hour).filter(func(k): return fn.level(String(k), "research") >= 1).size(),
			("「%s」" % MetroModes.project_name(id)) if id != "" else "없음", Fmt.n(float(m.alliance["pool"])),
			(" / " + Fmt.n(cost)) if cost > 0.0 else "", Fmt.n(m.last_gain, 1), m.alliance["done"].size(), Metros.alliance.size()])
	var depots := m.keys_of("emergency_depot", -2)
	if not depots.is_empty():
		var sum := {}
		for k in depots:
			var dep := m.depot(String(k))
			for kind in dep:
				sum[kind] = float(sum.get(kind, 0.0)) + float(dep[kind])
		out.append("비상 보급 기지 %d곳 — 창고: 산소 %s kg · 식량 %s kg · 물 %s kg · 부품 %s" % [depots.size(),
			Fmt.n(float(sum.get("o2_kg", 0.0))), Fmt.n(float(sum.get("food_kg", 0.0))), Fmt.n(float(sum.get("water_kg", 0.0))),
			Fmt.n(float(sum.get("parts", 0.0)))])
	var pc := m.keys_of("parts_capital", -2)
	if not pc.is_empty():
		var miss := 0.0
		for site in m.short:
			miss += float(m.short[site])
		out.append("우주 산업 수도 %d곳 — 우주 식민지에 모자란 부품 %s" % [pc.size(), Fmt.n(miss)])
	var ch := e.index_change(7) * 100.0
	out.append("우주 산업 지수 %s (7일 %s%s%%)%s · 우주 화제 %s · 우주 상점가 %d곳 · 우주 채권 %d건 · 우주 펀드 %d곳" % [
		Fmt.n(e.index), "+" if ch >= 0.0 else "", Fmt.n(ch, 1), " — 폭락 중" if e.crash_left > 0 else "", Fmt.n(e.buzz, 2),
		e.commerce.size(), e.loans.size(), e.funds.size()])
	var partners := 0
	for k2 in m.metros:
		if m.partner_of(String(k2)) != "":
			partners += 1
	out.append("반도체·AI 데이터센터 지역 %d곳 · 둘러본 곳 %d곳 · 협력 %d건" % [Metros.regions.size(), m.visited.size(), partners])
	return "\n".join(out)


## 접힌 묶음: 운행 편수·누계 한 줄
func _group_summary(ls: Array) -> Control:
	var label := ThemeFactory.muted("", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tr := mgr.transport
	_live.append(func():
		var n_on := 0
		var t := 0.0
		var settlers := 0
		var pax := 0
		var moving := 0
		for l in ls:
			if l["on"]:
				n_on += 1
			t += float(l["stats"]["t"])
			settlers += int(l["stats"]["settlers"])
			pax += int(l["stats"]["pax"])
			moving += tr.running(l["id"])
		label.text = "노선 %d개 중 %d개 운행 · 하늘에 %d편 · 누적 화물 %s t · 정착민 %s명 · 승객 %s명" % [ls.size(), n_on, moving,
			Fmt.n(t, 1), Fmt.n(float(settlers)), Fmt.n(float(pax))])
	return label


func _line_title(l: Dictionary) -> String:
	var arrow := " ↔ "
	if l["role"] == "feeder":
		arrow = " → "
	return "%s · %s%s%s" % [Transport.mode_name(l["mode"]), Transport.node_name(l["a"]), arrow, Transport.node_name(l["b"])]


static func _trip_len(l: Dictionary) -> String:
	var h := int(l["trip_h"])
	if h >= 24 * 60:
		return "%s일 길" % Fmt.n(h / 24.0)
	return "%s 길" % Fmt.hours(float(h))


func _line_card(l: Dictionary) -> Control:
	var tr := mgr.transport
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 9))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var on := CheckBox.new()
	on.button_pressed = l["on"]
	on.tooltip_text = "이 노선 운행"
	var id := String(l["id"])
	on.toggled.connect(func(p: bool):
		tr.set_line_on(mgr, id, p)
		changed.emit()
		update_view())
	top.add_child(on)
	var title := Label.new()
	title.text = _line_title(l)
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", 14)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var see := Button.new()
	see.text = "보기"
	see.tooltip_text = "3D 지도에서 이 노선을 본다"
	see.custom_minimum_size = Vector2(56, 34)
	see.add_theme_font_size_override("font_size", 12)
	see.pressed.connect(func(): show_line.emit(id))
	top.add_child(see)
	var plan := ThemeFactory.muted("", 12)
	plan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(plan)
	var sums := ThemeFactory.muted("", 12)
	sums.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sums.add_theme_color_override("font_color", Palette.TEXT.darkened(0.15))
	v.add_child(sums)
	var last := ThemeFactory.muted("", 12)
	last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(last)
	var ships := VBoxContainer.new()
	ships.add_theme_constant_override("separation", 4)
	v.add_child(ships)
	var ship_meters := {}
	_live.append(func():
		var dist := ""
		if l["kind"] == "ship":
			dist = "발사 창마다"
		elif l["kind"] == "ferry":
			dist = "38만 km"
		else:
			dist = "%s km" % Fmt.n(float(l["km"]))
		var nxt := tr.next_in(mgr, l)
		var when := "다음 출발 %s 뒤" % (Fmt.hours(float(nxt)) if nxt < 24 * 60 else "%s일" % Fmt.n(nxt / 24.0))
		if not l["on"] or not tr.enabled:
			when = "멈춤"
		plan.text = "%s · %s · %s · 지금 %d편 운행" % [dist, _trip_len(l), when, tr.running(l["id"])]
		var st: Dictionary = l["stats"]
		sums.text = "누적 %d편 · 화물 %s t · 정착민 %s명" % [int(st["trips"]), Fmt.n(float(st["t"]), 1), Fmt.n(float(st["settlers"]))]
		last.text = ("지난 운행: " + String(l["last"])) if String(l["last"]) != "" else "아직 닿은 편이 없다"
		# 가는 중인 수송선·셔틀
		if l["kind"] in ["ship", "ferry"]:
			var seen := {}
			for t in tr.trips:
				if t["line"] != l["id"]:
					continue
				var key := "%s/%d" % [t["from"], int(t["depart"])]
				seen[key] = true
				var m: Meter = ship_meters.get(key)
				if m == null:
					m = Meter.new("가는 중")
					ships.add_child(m)
					ship_meters[key] = m
				var span := maxf(1.0, float(t["arrive"]) - float(t["depart"]))
				var left := maxf(0.0, (float(t["arrive"]) - mgr.hour) / 24.0)
				m.set_values((mgr.hour - float(t["depart"])) / span, "D-%d" % ceili(left),
					"%s → %s · %s · %s 도착" % [Transport.node_name(t["from"]), Transport.node_name(t["to"]),
						Transport.load_text(t["cargo"], Transport.count_people(t["people"])), mgr.date_text(float(t["arrive"]))],
					Palette.BLUE)
			for key2 in ship_meters.keys():
				if not seen.has(key2):
					(ship_meters[key2] as Node).queue_free()
					ship_meters.erase(key2))
	return card


## 대도시 항공편: 한 줄 (켜기 · 이름 · 거리 · 누계)
func _compact_row(l: Dictionary) -> Control:
	var tr := mgr.transport
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var on := CheckBox.new()
	on.button_pressed = l["on"]
	var id := String(l["id"])
	on.toggled.connect(func(p: bool):
		tr.set_line_on(mgr, id, p)
		changed.emit()
		update_view())
	row.add_child(on)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 12)
	row.add_child(text)
	var see := Button.new()
	see.text = "보기"
	see.tooltip_text = "3D 지도에서 이 노선을 본다"
	see.custom_minimum_size = Vector2(48, 30)
	see.add_theme_font_size_override("font_size", 11)
	see.pressed.connect(func(): show_line.emit(id))
	row.add_child(see)
	if l["role"] == "feeder" and Metros.is_metro(String(l["a"])):
		var go := Button.new()
		go.text = "도시"
		go.tooltip_text = "%s 위로 날아가 시가지를 본다" % Transport.node_name(l["a"])
		go.custom_minimum_size = Vector2(48, 30)
		go.add_theme_font_size_override("font_size", 11)
		var key := String(l["a"])
		go.pressed.connect(func(): show_metro.emit(key))
		row.add_child(go)
	_live.append(func():
		var st: Dictionary = l["stats"]
		var extra := ""
		if int(st["settlers"]) > 0:
			extra = " · 정착민 %s명" % Fmt.n(float(st["settlers"]))
		text.text = "%s %s %s · %s km · %s · 승객 %s명%s" % [Transport.node_name(l["a"]), "→" if l["role"] == "feeder" else "↔",
			Transport.node_name(l["b"]), Fmt.n(float(l["km"])), _trip_len(l), Fmt.n(float(st["pax"])), extra]
		text.add_theme_color_override("font_color", Palette.TEXT if l["on"] else Palette.MUTED))
	return row
