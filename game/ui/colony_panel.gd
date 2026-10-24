class_name ColonyPanel
extends VBoxContainer
## 개척 탭 — 천체마다: 도시(고르면 그 도시로 날아간다), 이동 중인 원정대, 새 도시를 세울 후보 부지
## (환경·가는 길·필요 기술·비용·발사 창·출발)

signal view_requested(index: int)
signal changed
signal mode_requested(index: int, mode: String)     # 도시 발전 모드를 골랐다 (자동 운영이 꺼져 있으면 켠다)

const ENV_ROWS := [["sun", "햇빛"], ["day", "하루"], ["dose", "방사선"], ["resources", "자원"], ["rule", "규칙"]]

var sim: CitySim
var mgr: Colonies
var status := Label.new()
var body_box := VBoxContainer.new()
var _live: Array = []            # 새로 고칠 때마다 부르는 갱신 함수들 (Callable)
var _cards := {}                 # 부지 id → 후보 카드 (점을 누르면 그리로)
var _open := {}                  # 부지 id → 자세히 펼쳤나
var _shape := ""                 # 도시·원정대·후보 부지 — 바뀔 때만 다시 만든다 (날마다 바뀌는 글은 _live가 고친다)
var _live_ms := 0                # _live를 마지막으로 부른 때 (발사 창·비용 셈이 무거워 1초에 두세 번만)


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("개척"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	add_child(status)
	var help := ThemeFactory.muted("천체마다 기본 도시가 있고, 후보 부지에 원정대를 보내 도시를 더 세운다. 같은 천체의 도시에서는 " +
		"로버 행렬(지구는 비행편)로 며칠~몇 주 만에 닿고, 도시가 없는 천체로는 고향에서 발사 창을 기다려 건너간다. " +
		"3D 지도에서는 행성마다 도시의 점과 이름만 보이고, '보기'나 점을 누르면 그 도시로 날아가 내려앉는다.", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	body_box.add_theme_constant_override("separation", 8)
	add_child(body_box)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	rebuild()


func _shape_sig() -> String:
	if mgr == null:
		return ""
	var parts := PackedStringArray([str(sim.get_instance_id() if sim != null else 0)])
	for c in mgr.list:
		parts.append(String(c["site"]))
	parts.append("|")
	for e in mgr.expeditions:
		parts.append(String(e["site"]))
	parts.append("|")
	parts.append_array(PackedStringArray(mgr.candidates()))
	return ",".join(parts)


## 날마다·탭을 고를 때: 도시·원정대·후보가 그대로면 글만 고친다
func refresh() -> void:
	if mgr == null:
		return
	if _shape_sig() != _shape:
		rebuild()
	else:
		_live_ms = 0
		update_view()


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func update_view() -> void:
	if mgr == null or mgr.list.is_empty():
		return
	var pop := 0.0
	for c in mgr.list:
		pop += (c["sim"] as CitySim).population()
	status.text = "도시 %d곳 · 정착민 %s명 · 이동 중인 원정대 %d" % [mgr.list.size(), Fmt.n(pop), mgr.expeditions.size()]
	var now := Time.get_ticks_msec()
	if _live_ms > 0 and now - _live_ms < 400:
		return
	_live_ms = now
	for f in _live:
		(f as Callable).call()


func rebuild() -> void:
	if mgr == null:
		return
	_shape = _shape_sig()
	_live_ms = 0
	_live.clear()
	_cards.clear()
	_clear(body_box)
	var here := mgr.index_of_sim(sim) if sim != null else -1
	if here >= 0:
		body_box.add_child(_dev_section(here))
		body_box.add_child(_delegate_section(here))
		body_box.add_child(_services_section(here))
		body_box.add_child(_progress_section(here))
		body_box.add_child(_explore_section(here))
		body_box.add_child(_trade_section(here))
	var cands := mgr.candidates()
	for body in Colonies.BODY_ORDER:
		var cities := []
		for i in mgr.list.size():
			if String(mgr.list[i]["body"]) == body:
				cities.append(i)
		var trips := []
		for e in mgr.expeditions:
			if String(GameData.site(e["site"]).get("body", "")) == body:
				trips.append(e)
		var open_sites := []
		for id in cands:
			if String(GameData.site(id).get("body", "")) == body and mgr.index_of_site(id) < 0 and mgr.in_transit(id).is_empty():
				open_sites.append(id)
		if cities.is_empty() and trips.is_empty() and open_sites.is_empty():
			continue
		body_box.add_child(HSeparator.new())
		var head := ThemeFactory.heading("%s · 도시 %d곳" % [body_name(body), cities.size()], 16)
		body_box.add_child(head)
		for i in cities:
			body_box.add_child(_colony_row(i))
		for e in trips:
			body_box.add_child(_transit_row(e))
		for id in open_sites:
			var card := _site_card(id)
			_cards[id] = card
			body_box.add_child(card)
	update_view()


## 고른 도시의 발전 모드: 열 가지 방향(과 균형) 단추, 목표 건물, 땅 (자동 운영일 때 그 방향으로 짓고 땅을 넓히거나 줄인다)
func _dev_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var s: CitySim = c["sim"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(ThemeFactory.heading("도시 발전 모드 · %s" % c["name"], 16))
	var now := Label.new()
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	now.add_theme_font_size_override("font_size", 13)
	v.add_child(now)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var cur := String(c.get("mode", ""))
	for id in LayoutData.dev_modes():
		var m: Dictionary = LayoutData.dev_mode(id)
		var b := Button.new()
		b.text = String(m.get("name", id))
		b.toggle_mode = true
		b.button_pressed = id == cur
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_pressed_color", Color(String(m.get("color", "aab3c8"))).lightened(0.3))
		b.tooltip_text = String(m.get("text", ""))
		var mode_id := String(id)
		b.pressed.connect(func(): mode_requested.emit(i, mode_id))
		grid.add_child(b)
	var text := ThemeFactory.muted(String(LayoutData.dev_mode(cur).get("text", "")), 12)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text)
	var goal := ThemeFactory.muted("", 12)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_theme_color_override("font_color", Palette.TEXT.darkened(0.1))
	v.add_child(goal)
	_live.append(func():
		var st := CityDev.status(c)
		var auto := "자동 운영 — 이 방향으로 짓는다" if CityAuto.full(s) else (
			"직접 운영 · 위임 %d가지 — 맡긴 분야는 이 방향으로" % CityAuto.count(c) if CityAuto.count(c) > 0
			else "직접 운영 — 방향을 고르면 자동 운영을 켠다")
		now.text = "지금: %s · %s · 산 땅 구역 %d/%d · 구획이 찬 정도 %s" % [CityDev.mode_name(cur), auto, int(st["land"]),
			int(st["max"]), Fmt.pct(float(st["fill"]))]
		var parts := PackedStringArray()
		for r in st["rows"]:
			var q := " (+%d 짓는 중)" % int(r[2]) if int(r[2]) > 0 else ""
			parts.append("%s %d/%d%s" % [GameData.module_name(r[0]), int(r[1]), int(r[3]), q])
		goal.text = ("목표: " + " · ".join(parts)) if not parts.is_empty() else "목표 건물 없음 — 살림에 필요한 것만 짓는다"
		if String(st["redev"]) != "":
			goal.text += "\n재건축 중: %s" % String(st["redev"])
		if not (st["works"] as PackedStringArray).is_empty():
			goal.text += "\n길 공사: " + " · ".join(st["works"]))
	return card


## 위임: 직접 운영하면서 분야를 골라 시드에게 맡긴다 (CityAuto). 맡긴 분야에서 시드가 한 일은 '기록' 탭의 운영 기록에 남는다
func _delegate_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var s: CitySim = c["sim"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(ThemeFactory.heading("위임 — 시드에게 맡길 분야", 16))
	var now := ThemeFactory.muted("", 13)
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(now)
	var checks: Array = []
	for d in CityAuto.DOMAINS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var cb := CheckButton.new()
		cb.text = d[1]
		cb.custom_minimum_size = Vector2(170, 36)
		cb.button_pressed = bool((c.get("delegate", {}) as Dictionary).get(d[0], false))
		var dom: String = d[0]
		cb.toggled.connect(func(on: bool):
			CityAuto.set_delegate(c, dom, on)
			_live_ms = 0
			update_view()
			changed.emit())
		row.add_child(cb)
		var t := ThemeFactory.muted(d[2], 12)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		v.add_child(row)
		checks.append(cb)
	_live.append(func():
		var lg: Array = c.get("oplog", []) if c.get("oplog") is Array else []
		var last := ""
		if not lg.is_empty():
			var e: Array = lg[-1]
			last = "\n최근: %s · %s" % [CityAuto.domain_name(String(e[1])), String(e[2])]
		if CityAuto.full(s):
			now.text = "자동 운영 중 — 시드가 모든 분야를 맡는다. 자동 운영을 끄면 아래에서 고른 분야만 맡는다." + last
		else:
			now.text = ("직접 운영 · 맡긴 분야 %d가지 — 시드가 한 일은 '기록' 탭의 운영 기록에 까닭과 함께 남는다." % CityAuto.count(c)) + last
		for cb in checks:
			(cb as CheckButton).modulate = Color(1, 1, 1, 0.55 if CityAuto.full(s) else 1.0))
	return card


## 고른 도시의 기능 자리 (CityServices): 의료·여가·대피가 닿는 사람의 몫, 통근 시간, 물류 거리, 시뮬레이션에 건넨 보정
func _services_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(ThemeFactory.heading("도시 기능 · 자리", 16))
	var lines := ThemeFactory.muted("", 13)
	lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_theme_color_override("font_color", Palette.TEXT.darkened(0.05))
	v.add_child(lines)
	var hint := ThemeFactory.muted("집 둘레에 의료·여가·대피 시설이 닿으면 사기가 오르고, 일터·저장 시설이 가까우면(고가·궤도 노선, 환승 시설) 일과 생산이 빨라진다. "
		+ "3D 지도의 '범위' 단추로 닿는 곳을 본다.", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	_live.append(func():
		var m: Dictionary = c.get("services", {})
		if m.is_empty():
			lines.text = "아직 재지 않았다 — 하루가 지나면 잰다"
			return
		var cv: Dictionary = m.get("cover", {})
		lines.text = "닿는 사람: 의료 %s · 여가 %s · 대피 %s\n통근 평균 %.1f분 · 물류 평균 %s km\n보정: %s" % [
			Fmt.pct(float(cv.get("care", 0.0))), Fmt.pct(float(cv.get("leisure", 0.0))), Fmt.pct(float(cv.get("shelter", 0.0))),
			float(m.get("commute_min", 0.0)), Fmt.n(float(m.get("freight_km", 0.0)), 2), CityExt.text((c["sim"] as CitySim).ext)])
	return card


## 고른 도시의 시대·이정표·메가프로젝트 (CityProgress): 지금 시대와 다음 시대에 필요한 이정표, 아직 이루지 못한 이정표,
## 메가프로젝트마다 지은 것·짓는 공정·짓기 단추(직접 운영 — 자동 운영은 자재가 넉넉하면 스스로 짓는다)
func _progress_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := ThemeFactory.heading("", 16)
	v.add_child(head)
	var lines := ThemeFactory.muted("", 13)
	lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_theme_color_override("font_color", Palette.TEXT.darkened(0.05))
	v.add_child(lines)
	var rows: Array = []                   # [메가프로젝트 id, 설명 Label, 짓기 Button]
	for m in CityProgress.data()["megaprojects"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := ThemeFactory.muted("", 12)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var b := Button.new()
		b.text = "짓기"
		b.custom_minimum_size = Vector2(64, 34)
		var id := String(m["id"])
		b.pressed.connect(func():
			if CityProgress.start(c, id):
				update_view())
		row.add_child(b)
		v.add_child(row)
		rows.append([id, label, b])
	_live.append(func():
		var st := CityProgress.state(c)
		var era := int(st["era"])
		var eras: Array = CityProgress.data()["eras"]
		head.text = "%s · %s" % [CityProgress.era_name(era), String(eras[era].get("text", ""))] if era < eras.size() else ""
		var done: Dictionary = st["done"]
		var txt := "이룬 이정표 %d / %d" % [done.size(), (CityProgress.data()["milestones"] as Array).size()]
		if era + 1 < eras.size():
			var need := PackedStringArray()
			for id in eras[era + 1].get("needs", []):
				need.append(("✓ " if done.has(id) else "· ") + CityProgress.milestone_name(String(id)))
			txt += "\n다음 — %s: %s" % [String(eras[era + 1]["name"]), ", ".join(need)]
		var todo := PackedStringArray()
		for ms in CityProgress.data()["milestones"]:
			if not done.has(String(ms["id"])) and todo.size() < 4:
				todo.append("%s(%s)" % [String(ms["name"]), String(ms.get("text", ""))])
		if not todo.is_empty():
			txt += "\n남은 이정표: " + " · ".join(todo)
		lines.text = txt
		var plan: CityPlan = c["plan"]
		for r in rows:
			var m := CityProgress.mega(String(r[0]))
			var label: Label = r[1]
			var b: Button = r[2]
			var stages: Array = m["stages"]
			var desc := "%s — %s (%s)" % [String(m["name"]), String(m.get("text", "")), CityProgress.effect_text(m.get("effect", {}))]
			b.visible = false
			if String(r[0]) in st["built"]:
				label.text = "✓ " + desc
				continue
			var going := {}
			for w in plan.mega:
				if String(w["id"]) == String(r[0]):
					going = w
			if not going.is_empty():
				label.text = "%s\n짓는 중: %d/%d단계 %s — %s" % [desc, int(going["stage"]) + 1, stages.size(),
					String(stages[int(going["stage"])]["name"]), Fmt.pct(float(going["p"]))]
				continue
			var why := CityProgress.can_start(c, String(r[0]))
			b.visible = why == ""
			label.text = desc + ("\n첫 단계 %s · %d단계" % [CityPlan.cost_text(stages[0]["cost"]), stages.size()] if why == "" else "\n" + why))
	return card


## 고른 도시의 둘레 탐사 (CityExplore): 탐사지마다 거리·방향과 발견, 탐사대 보내기 (한 번에 한 탐사대)
func _explore_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(ThemeFactory.heading("둘레 탐사", 16))
	var status := ThemeFactory.muted("", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	var rows: Array = []
	var st := CityExplore.state(c)
	for k in (st["sites"] as Array).size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := ThemeFactory.muted("", 12)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var b := Button.new()
		b.text = "보내기"
		b.custom_minimum_size = Vector2(70, 32)
		var idx := k
		b.pressed.connect(func():
			if CityExplore.send(c, idx):
				update_view())
		row.add_child(b)
		v.add_child(row)
		rows.append([label, b])
	_live.append(func():
		var s2 := CityExplore.state(c)
		var trip: Dictionary = s2["trip"]
		var sim2: CitySim = c["sim"]
		if trip.is_empty():
			status.text = "탐사대가 기지에 있다 — 한 번에 %s (가서 %d일 조사하고 돌아온다)" % [CityPlan.cost_text(CityExplore.data().get("cost", {})),
				int(CityExplore.data().get("survey_days", 4))]
		else:
			var left := ceili((float(trip["back"]) - sim2.hour) / 24.0)
			var phase := "가는 중" if sim2.hour < int(trip["arrive"]) else ("조사 중" if sim2.hour < int(trip["done"]) else "돌아오는 중")
			status.text = "탐사대 %s — 돌아오기까지 %d일" % [phase, maxi(left, 0)]
		for k in rows.size():
			var site: Dictionary = s2["sites"][k]
			var where := (c["plan"] as CityPlan).where_text(CityExplore.site_pos(site))
			var label: Label = rows[k][0]
			var b: Button = rows[k][1]
			match String(site["state"]):
				"found":
					var f := CityExplore.find(String(site["find"]))
					label.text = "✓ %s — %s (%s)" % [where, String(f.get("name", "?")), CityExplore.reward_text(f.get("reward", {}))]
				"going":
					label.text = "… %s — 탐사대가 가 있다" % where
				_:
					label.text = "? %s — 아직 모른다" % where
			b.visible = String(site["state"]) == "unknown"
			b.disabled = CityExplore.can_send(c, k) != "")
	return card


## 수출 계약: 받은 계약(보내기)과 들어온 제안(받기). 목록이 바뀌면 그 칸만 다시 만들고, 날마다 바뀌는 글은 고친다
func _trade_section(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(ThemeFactory.heading("수출 계약", 16))
	var status := ThemeFactory.muted("", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	v.add_child(rows)
	var shape := [""]
	var items: Array = []            # [Label, Button, 받은 계약인가, 계약 번호]
	_live.append(func():
		var st := CityTrade.state(c)
		var sim2: CitySim = c["sim"]
		status.text = "보낸 계약 %d건 · 지원 점수 +%d · 놓친 계약 %d건 · 한 번에 %d건까지%s" % [int(st["done"]), int(st["earned"]),
			int(st["failed"]), CityTrade.max_active(c), " — 시드가 남는 양으로 받고 보낸다" if CityAuto.on(c, "trade") else ""]
		var parts := PackedStringArray()
		for a in st["active"]:
			parts.append("a%d" % int(a["id"]))
		for o in st["offers"]:
			parts.append("o%d" % int(o["id"]))
		var sig := ",".join(parts)
		if sig != shape[0]:
			shape[0] = sig
			_clear(rows)
			items.clear()
			for list_key in ["active", "offers"]:
				for e in st[list_key]:
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 8)
					var label := ThemeFactory.muted("", 12)
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					row.add_child(label)
					var b := Button.new()
					b.custom_minimum_size = Vector2(70, 32)
					var id := int(e["id"])
					var is_active: bool = list_key == "active"
					b.text = "보내기" if is_active else "받기"
					b.pressed.connect(func():
						if CityTrade.deliver(c, id, mgr) if is_active else CityTrade.accept(c, id):
							_live_ms = 0
							update_view())
					row.add_child(b)
					rows.add_child(row)
					items.append([label, b, is_active, id])
			if items.is_empty():
				rows.add_child(ThemeFactory.muted("들어온 제안이 없다 — %d일마다 그 도시가 만드는 것에 제안이 온다" % int(CityTrade.data().get("every_days", 20)), 12))
		for it in items:
			var label: Label = it[0]
			var b: Button = it[1]
			var e := {}
			for x in st["active" if it[2] else "offers"]:
				if int(x["id"]) == int(it[3]):
					e = x
			if e.is_empty():
				continue
			var g := CityTrade.good(String(e["good"]))
			var have := "비축 %s %s" % [CityTrade._num(CityTrade.have(sim2, g), g), String(g.get("unit", ""))]
			if it[2]:
				var left := ceili((float(e["due"]) - sim2.hour) / 24.0)
				label.text = "%s → %s · 지원 점수 +%d · 남은 날 %d일 (%s)" % [CityTrade.amount_text(e), String(e["buyer"]),
					int(e["reward"]), maxi(left, 0), have]
				var why := CityTrade.can_deliver(c, int(it[3]))
				b.disabled = why != ""
				b.tooltip_text = why
			else:
				var gone := ceili((float(e["expires"]) - sim2.hour) / 24.0)
				label.text = "제안: %s → %s · 지원 점수 +%d · 받으면 %d일 안에 · %d일 뒤 사라진다 (%s)" % [CityTrade.amount_text(e),
					String(e["buyer"]), int(e["reward"]), int(e["days"]), maxi(gone, 0), have]
				b.disabled = (st["active"] as Array).size() >= CityTrade.max_active(c)
				b.tooltip_text = "받은 계약이 가득 찼다" if b.disabled else "")
	return card


## 3D 지도의 후보지 점을 눌렀을 때: 그 카드를 펼친다
func focus_site(site_id: String) -> Control:
	_open[site_id] = true
	rebuild()
	return _cards.get(site_id)


static func body_name(body: String) -> String:
	Astro.load_data()
	return String(Astro.bodies.get(body, {}).get("name", body))


func _colony_row(i: int) -> Control:
	var c: Dictionary = mgr.list[i]
	var s: CitySim = c["sim"]
	var here := s == sim
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var title := Label.new()
	title.text = "%s%s" % [c["name"], "  · 지금 보는 곳" if here else ""]
	title.add_theme_color_override("font_color", Palette.AMBER if here else Palette.TEXT)
	info.add_child(title)
	var line := ThemeFactory.muted("", 12)
	info.add_child(line)
	row.add_child(info)
	var b := Button.new()
	b.text = "보기"
	b.tooltip_text = "이 도시로 날아가 내려앉는다"
	b.custom_minimum_size = Vector2(64, 40)
	b.pressed.connect(func(): view_requested.emit(i))
	row.add_child(b)
	_live.append(func():
		var lit := "그늘" if s.is_dark() else "일조"
		if String(GameData.site(c["site"]).get("layout", "open")) != "ridge":
			lit = "밤" if s.is_dark() else "낮"
		if s.in_dust_storm():
			lit = "먼지 폭풍"
		line.text = "%s명 · %d일째 · %s · %s · 사기 %d · 신뢰 %d" % [Fmt.n(s.population()), s.current_day() + 1,
			"자동 운영" if CityAuto.full(s) else ("직접 운영 · 위임 %d" % CityAuto.count(c) if CityAuto.count(c) > 0 else "직접 운영"),
			lit, int(round(s.morale)), int(round(s.trust))])
	return row


func _transit_row(e: Dictionary) -> Control:
	var site := GameData.site(e["site"])
	var m := Meter.new("원정")
	var total := maxf(1.0, float(e["arrive"]) - float(e["depart"]))
	var from := GameData.site(String(e.get("from", GameData.HOME_SITE)))
	_live.append(func():
		var left := maxf(0.0, (float(e["arrive"]) - mgr.hour) / 24.0)
		m.set_values((mgr.hour - float(e["depart"])) / total, "D-%d" % ceili(left),
			"%s → %s · %s 도착 예정 (%d일 길)" % [String(from.get("short", "")), site["name"], mgr.date_text(float(e["arrive"])),
				ceili(total / 24.0)], Palette.BLUE))
	return m


func _site_card(id: String) -> Control:
	var site := GameData.site(id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = "후보 · %s" % site["name"]
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var more := Button.new()
	more.text = "접기" if _open.get(id, false) else "자세히"
	more.custom_minimum_size = Vector2(0, 32)
	more.add_theme_font_size_override("font_size", 12)
	top.add_child(more)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 3)
	detail.visible = _open.get(id, false)
	more.pressed.connect(func():
		_open[id] = not _open.get(id, false)
		detail.visible = _open[id]
		more.text = "접기" if _open[id] else "자세히")
	var summary := ThemeFactory.muted(String(site.get("summary", "")), 12)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(summary)
	var env: Dictionary = site.get("env", {})
	var lines := []
	for pair in ENV_ROWS:
		if env.has(pair[0]):
			lines.append("· %s — %s" % [pair[1], env[pair[0]]])
	var env_label := ThemeFactory.muted("\n".join(lines), 12)
	env_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	env_label.add_theme_color_override("font_color", Palette.TEXT.darkened(0.15))
	detail.add_child(env_label)
	v.add_child(detail)
	var way := Label.new()
	way.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	way.add_theme_font_size_override("font_size", 13)
	v.add_child(way)
	var cost := Label.new()
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.add_theme_font_size_override("font_size", 13)
	v.add_child(cost)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var reason := ThemeFactory.muted("", 12)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason.add_theme_color_override("font_color", Palette.AMBER)
	row.add_child(reason)
	var go := Button.new()
	go.text = "출발"
	go.custom_minimum_size = Vector2(84, 42)
	go.pressed.connect(func():
		if mgr.launch(id):
			changed.emit()
			rebuild())
	row.add_child(go)
	_live.append(func():
		var r := mgr.route(id)
		var now_d := mgr.hour / 24.0
		if r["mode"] == "local":
			var from: Dictionary = mgr.list[int(r["from"])]
			var how := "비행편" if String(site.get("body", "")) == "earth" else "로버 행렬"
			way.text = "가는 길: %s에서 %s · %s km · 약 %d일" % [from["short"], how,
				Fmt.n(mgr.surface_km(String(from["site"]), id)), ceili(mgr.travel_days(id, r))]
			way.add_theme_color_override("font_color", Palette.GREEN)
		elif r["mode"] == "space":
			var w := mgr.window(id)
			var when := ""
			if w["open"]:
				when = "발사 창 열림 — %d일 남음" % ceili(float(w["end"]) - now_d)
			else:
				when = "다음 발사 창 %s (D-%d)" % [mgr.date_text(float(w["start"]) * 24.0), ceili(float(w["start"]) - now_d)]
			way.text = "가는 길: 고향에서 행성 사이 전이 %d일 · %s" % [int(mgr.travel_days(id, r)), when]
			way.add_theme_color_override("font_color", Palette.GREEN if w["open"] else Palette.BLUE)
		else:
			way.text = "가는 길: 떠날 도시가 없다"
			way.add_theme_color_override("font_color", Palette.MUTED)
		var cs := []
		var enough := true
		if r["mode"] != "":
			for c in mgr.cost_rows(id, r):
				cs.append("%s %s/%s" % [Colonies.cost_name(c[0]), Fmt.n(c[1]), Fmt.n(c[2])])
				enough = enough and float(c[2]) >= float(c[1])
			var req := []
			var known := mgr.known_techs()
			for t in (mgr.expedition(id).get("local", {}) if r["mode"] == "local" else mgr.expedition(id)).get("requires", []):
				var tname := String(GameData.TECHS[t]["name"]) if GameData.TECHS.has(t) else String(t)
				req.append(tname + (" ✓" if known.has(t) else " —"))
			cost.text = "비용 (필요/%s 비축): %s%s" % [mgr.list[int(r["from"])]["short"], " · ".join(cs),
				("  · 기술: " + " · ".join(req)) if not req.is_empty() else ""]
		else:
			cost.text = ""
		cost.add_theme_color_override("font_color", Palette.TEXT if enough else Palette.MUTED)
		var why := mgr.block_reason(id)
		go.disabled = why != ""
		go.tooltip_text = why if why != "" else "원정대를 보낸다 — 떠나는 도시가 비용을 낸다"
		reason.text = why)
	return card
