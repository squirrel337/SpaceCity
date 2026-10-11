class_name ColonyPanel
extends VBoxContainer
## 개척 탭 — 식민지 목록(고르면 그 도시로 날아간다), 이동 중인 원정대, 후보 부지(환경·필요 기술·비용·발사 창·출발)

signal view_requested(index: int)
signal changed

const ENV_ROWS := [["sun", "햇빛"], ["day", "하루"], ["dose", "방사선"], ["resources", "자원"], ["rule", "규칙"]]

var sim: CitySim
var mgr: Colonies
var status := Label.new()
var colony_box := VBoxContainer.new()
var transit_box := VBoxContainer.new()
var site_box := VBoxContainer.new()
var _live: Array = []            # 새로 고칠 때마다 부르는 갱신 함수들 (Callable)


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("개척"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	add_child(status)
	add_child(ThemeFactory.heading("식민지", 16))
	add_child(ThemeFactory.muted("3D 지도에서는 행성마다 도시의 점과 이름만 보인다. '보기'나 점을 누르면 그 도시로 날아가 내려앉고, " +
		"자세한 도시는 고른 식민지 하나만 그린다.", 12))
	colony_box.add_theme_constant_override("separation", 6)
	add_child(colony_box)
	add_child(ThemeFactory.heading("이동 중", 16))
	transit_box.add_theme_constant_override("separation", 6)
	add_child(transit_box)
	add_child(HSeparator.new())
	add_child(ThemeFactory.heading("후보 부지", 16))
	add_child(ThemeFactory.muted("원정은 고향(섀클턴)에서 떠나고 비용도 고향이 낸다. 발사 창은 지구와 목적지 행성의 실제 위치로 " +
		"열린다 — 호만 전이의 위상각이 맞는 날 앞뒤로 며칠. 도착하면 시드가 자동 운영으로 기지를 세운다.", 12))
	site_box.add_theme_constant_override("separation", 8)
	add_child(site_box)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	rebuild()


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
	var h := mgr.home()
	var support_text := ""
	if not h.is_empty():
		var hs: CitySim = h["sim"]
		support_text = " · 고향 비축: 부품 %s · 금속 %s t · 지구 지원 %s" % [Fmt.n(hs.stock["parts"]), Fmt.n(hs.stock["metal_t"], 1),
			Fmt.n(hs.support)]
	status.text = "식민지 %d곳 · 정착민 %s명 · 이동 중인 원정대 %d%s" % [mgr.list.size(), Fmt.n(pop), mgr.expeditions.size(),
		support_text]
	for f in _live:
		(f as Callable).call()


func rebuild() -> void:
	if mgr == null:
		return
	_live.clear()
	_clear(colony_box)
	_clear(transit_box)
	_clear(site_box)
	for i in mgr.list.size():
		colony_box.add_child(_colony_row(i))
	for e in mgr.expeditions:
		transit_box.add_child(_transit_row(e))
	if mgr.expeditions.is_empty():
		transit_box.add_child(ThemeFactory.muted("없음", 13))
	var open := 0
	for id in mgr.candidates():
		if mgr.index_of_site(id) < 0 and mgr.in_transit(id).is_empty():
			site_box.add_child(_site_card(id))
			open += 1
	if open == 0:
		site_box.add_child(ThemeFactory.muted("모든 후보 부지에 식민지가 있거나 원정대가 가는 중이다.", 13))
	update_view()


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
	title.text = "%s · %s%s" % [c["name"], body_name(c["body"]), "  · 지금 보는 곳" if here else ""]
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
			"자동 운영" if s.autopilot != null else "직접 운영", lit, int(round(s.morale)), int(round(s.trust))])
	return row


func _transit_row(e: Dictionary) -> Control:
	var site := GameData.site(e["site"])
	var m := Meter.new("원정")
	var total := maxf(1.0, float(e["arrive"]) - float(e["depart"]))
	_live.append(func():
		var left := maxf(0.0, (float(e["arrive"]) - mgr.hour) / 24.0)
		m.set_values((mgr.hour - float(e["depart"])) / total, "D-%d" % ceili(left),
			"%s (%s) · %s 도착 예정 · 전이 %d일" % [site["name"], body_name(site["body"]), mgr.date_text(float(e["arrive"])),
				int(round(total / 24.0))], Palette.BLUE))
	return m


func _site_card(id: String) -> Control:
	var site := GameData.site(id)
	var ex: Dictionary = site.get("expedition", {})
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL_2, Palette.LINE, 8, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var title := Label.new()
	title.text = "%s · %s" % [site["name"], body_name(site["body"])]
	title.add_theme_font_override("font", ThemeFactory.bold)
	title.add_theme_font_size_override("font_size", 15)
	v.add_child(title)
	var summary := ThemeFactory.muted(String(site.get("summary", "")), 12)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary)
	var env: Dictionary = site.get("env", {})
	var lines := []
	for pair in ENV_ROWS:
		if env.has(pair[0]):
			lines.append("· %s — %s" % [pair[1], env[pair[0]]])
	var env_label := ThemeFactory.muted("\n".join(lines), 12)
	env_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	env_label.add_theme_color_override("font_color", Palette.TEXT.darkened(0.15))
	v.add_child(env_label)
	var req := Label.new()
	req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	req.add_theme_font_size_override("font_size", 13)
	v.add_child(req)
	var cost := Label.new()
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.add_theme_font_size_override("font_size", 13)
	v.add_child(cost)
	var win := Label.new()
	win.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win.add_theme_font_size_override("font_size", 13)
	v.add_child(win)
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
		var known := mgr.known_techs()
		var parts := []
		for t in ex.get("requires", []):
			var tname := String(GameData.TECHS[t]["name"]) if GameData.TECHS.has(t) else String(t)
			parts.append(tname + (" ✓" if known.has(t) else " —"))
		req.text = "필요 기술: " + " · ".join(parts)
		req.add_theme_color_override("font_color", Palette.GREEN if mgr.missing_techs(id).is_empty() else Palette.MUTED)
		var cs := []
		var enough := true
		for c in mgr.cost_rows(id):
			cs.append("%s %s/%s" % [Colonies.cost_name(c[0]), Fmt.n(c[1]), Fmt.n(c[2])])
			enough = enough and float(c[2]) >= float(c[1])
		cost.text = "비용 (필요/고향 비축): %s · 전이 %d일" % [" · ".join(cs), int(ex.get("transfer_days", 0))]
		cost.add_theme_color_override("font_color", Palette.TEXT if enough else Palette.MUTED)
		var w := mgr.window(id)
		var now_d := mgr.hour / 24.0
		if w["open"]:
			win.text = "발사 창 열림 — %d일 남음 (가장 좋은 날 %s)" % [ceili(float(w["end"]) - now_d), mgr.date_text(float(w["best"]) * 24.0)]
			win.add_theme_color_override("font_color", Palette.GREEN)
		else:
			win.text = "다음 발사 창 %s ~ %s (D-%d)" % [mgr.date_text(float(w["start"]) * 24.0), mgr.date_text(float(w["end"]) * 24.0),
				ceili(float(w["start"]) - now_d)]
			win.add_theme_color_override("font_color", Palette.BLUE)
		var why := mgr.block_reason(id)
		go.disabled = why != ""
		go.tooltip_text = why if why != "" else "원정대를 보낸다 — 고향이 비용을 낸다"
		reason.text = why)
	return card
