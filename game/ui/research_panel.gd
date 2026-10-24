class_name ResearchPanel
extends VBoxContainer
## 연구 탭 — 시대 0 기술 20종

signal changed

const PLAUSIBILITY := {"proven": "검증됨", "engineering": "공학적", "theoretical": "이론적"}

var sim: CitySim
var colony: Dictionary = {}       # 고른 식민지 (연구 갈림길·돌파 카드 — CityResearch)
var status := Label.new()
var progress := Meter.new("진행")
var paths := VBoxContainer.new()  # 갈림길·돌파 카드
var list := VBoxContainer.new()
var _shape := ""         # 완료·대기 순서·지금 과제 — 바뀔 때만 목록을 다시 만든다


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("연구"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	add_child(status)
	add_child(progress)
	paths.add_theme_constant_override("separation", 6)
	add_child(paths)
	add_child(HSeparator.new())
	list.add_theme_constant_override("separation", 8)
	add_child(list)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	rebuild()


func _shape_sig() -> String:
	var rs := str(CityResearch.state(colony)) if not colony.is_empty() else ""
	return "%d|%d|%s|%s|%s" % [sim.get_instance_id(), sim.techs.size(), ",".join(PackedStringArray(sim.research_queue)),
		current_target(), rs]


## 날마다·탭을 고를 때: 기술의 상태가 그대로면 진행만 고친다
func refresh() -> void:
	if sim == null:
		return
	if _shape_sig() != _shape:
		rebuild()
	else:
		update_view()


func current_target() -> String:
	for tid in sim.research_queue:
		var ok := true
		for r in sim.T[tid]["requires"]:
			if not sim.techs.has(r):
				ok = false
				break
		if ok:
			return tid
	return ""


func update_view() -> void:
	if sim == null:
		return
	var target := current_target()
	status.text = "하루 약 %s RP (연구동 %d기 · 지구 교신 센터 · 지구 공동 연구) · 쌓인 RP %s · 완료 %d / %d" % [
		Fmt.n(sim.last_rp, 1), int(sim.wk.get("research_lab", 0)), Fmt.n(sim.rp_bank), sim.techs.size(), sim.T.size()]
	if target == "":
		progress.set_values(0.0, "—", "연구할 기술을 고른다. RP는 그동안에도 쌓인다.", Palette.AMBER)
	else:
		var cost: float = sim.T[target]["cost"]
		var days_left := (cost - sim.rp_bank) / maxf(sim.last_rp, 0.1)
		progress.set_values(sim.rp_bank / cost, "%s / %s" % [Fmt.n(minf(sim.rp_bank, cost)), Fmt.n(cost)],
			"%s — 약 %s 남음" % [sim.T[target]["name"], Fmt.days(maxf(days_left, 0.0))], Palette.PURPLE)


func rebuild() -> void:
	if sim == null:
		return
	_shape = _shape_sig()
	update_view()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var target := current_target()
	for tid in sim.T:
		list.add_child(_entry(tid, target))
	_rebuild_paths()


## 갈림길과 돌파 카드: 고른 방향, 고를 차례의 방향 단추 둘, 가진 카드, 고를 카드 단추 셋
func _rebuild_paths() -> void:
	for c in paths.get_children():
		paths.remove_child(c)
		c.queue_free()
	if colony.is_empty():
		return
	var st := CityResearch.state(colony)
	paths.add_child(ThemeFactory.heading("연구 갈림길 · 돌파", 16))
	var brs: Array = CityResearch.data()["branches"]
	var due := CityResearch.branch_due(colony)
	for i in brs.size():
		var br: Dictionary = brs[i]
		var chosen := String((st["branches"] as Dictionary).get(str(i), ""))
		if chosen != "":
			var o := CityResearch.option(chosen)
			paths.add_child(ThemeFactory.muted("✓ %s — %s (%s)" % [String(br["name"]), String(o["name"]), CityResearch.effect_text(o["effect"])], 13))
		elif i == due:
			paths.add_child(ThemeFactory.muted("%s — 하나를 고른다 (바꿀 수 없다)" % String(br["name"]), 13))
			for o in br["options"]:
				paths.add_child(_choice_button("%s — %s\n%s" % [String(o["name"]), String(o["text"]), CityResearch.effect_text(o["effect"])],
					func(): CityResearch.choose_branch(colony, i, String(o["id"]))))
		else:
			var names := PackedStringArray()
			for o in br["options"]:
				names.append(String(o["name"]))
			paths.add_child(ThemeFactory.muted("· 기술 %d가지에 %s: %s" % [int(br["at"]), String(br["name"]), " / ".join(names)], 12))
	var owned := PackedStringArray()
	for id in st["cards"]:
		owned.append(String(CityResearch.card(String(id))["name"]))
	paths.add_child(ThemeFactory.muted("돌파 카드 %d장%s" % [owned.size(), (": " + " · ".join(owned)) if not owned.is_empty() else
		" — 기술을 알아낼 때마다 %d%%의 확률로 셋 가운데 하나를 고른다" % int(float(CityResearch.data().get("chance", 0.35)) * 100.0)], 12))
	if not (st["pending"] as Array).is_empty():
		paths.add_child(ThemeFactory.muted("돌파 — 하나를 고른다", 13))
		for id in st["pending"]:
			var cd := CityResearch.card(String(id))
			paths.add_child(_choice_button("%s — %s\n%s" % [String(cd["name"]), String(cd["text"]), CityResearch.effect_text(cd["effect"])],
				func(): CityResearch.choose_card(colony, String(id))))


func _choice_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 52)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(func():
		on_press.call()
		rebuild()
		changed.emit())
	return b


func _entry(tid: String, target: String) -> Control:
	var t: Dictionary = sim.T[tid]
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var title := Label.new()
	var state := ""
	var color := Palette.TEXT
	if sim.techs.has(tid):
		state = "완료"
		color = Palette.GREEN
	elif tid == target:
		state = "연구 중"
		color = Palette.PURPLE
	elif tid in sim.research_queue:
		state = "대기 %d번째" % (sim.research_queue.find(tid) + 1)
		color = Palette.BLUE
	title.text = t["name"] + ("  · " + state if state != "" else "")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", color)
	info.add_child(title)
	var req := []
	for r in t["requires"]:
		req.append(sim.T[r]["name"])
	var line := "%s · %s · %s RP%s" % [t["category"], PLAUSIBILITY.get(t["plausibility"], t["plausibility"]),
		Fmt.n(t["cost"]), ("  · 선행: " + ", ".join(req)) if req.size() else ""]
	info.add_child(ThemeFactory.muted(line + "\n" + String(t["effect"]), 12))
	row.add_child(info)
	if not sim.techs.has(tid):
		var button := Button.new()
		button.text = "먼저" if tid != target else "진행 중"
		button.disabled = tid == target
		button.custom_minimum_size = Vector2(72, 44)
		button.tooltip_text = String(t.get("science_note", ""))
		button.pressed.connect(_on_prioritize.bind(tid))
		row.add_child(button)
	return row


func _on_prioritize(tid: String) -> void:
	## 고른 기술과 아직 없는 선행 기술을 대기열 맨 앞에 둔다
	var chain := []
	_collect(tid, chain)
	for x in chain:
		sim.research_queue.erase(x)
	for i in range(chain.size()):
		sim.research_queue.insert(i, chain[i])
	rebuild()
	changed.emit()


func _collect(tid: String, chain: Array) -> void:
	if sim.techs.has(tid) or tid in chain:
		return
	for r in sim.T[tid]["requires"]:
		_collect(r, chain)
	chain.append(tid)
