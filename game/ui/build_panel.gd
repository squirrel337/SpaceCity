class_name BuildPanel
extends VBoxContainer
## 건설 탭 — 대기열과 짓기 목록. '짓기'를 누르면 3D 세계나 지도에서 자리를 고른다.
## 목록은 모양(식민지·펼친 계열·로봇 제작)이 바뀔 때만 다시 만들고, 날마다는 글·단추만 고친다 (refresh).

signal changed
signal place_requested(mid: String)

const ORDER := ["habitat", "life_support", "food", "power", "thermal", "safety", "industry", "logistics", "research", "social"]

var sim: CitySim
var res_label := Label.new()
var auto_sort := CheckBox.new()
var queue_box := VBoxContainer.new()
var catalog := VBoxContainer.new()
var message := ThemeFactory.muted("")
var _open := {}          # 계열 → 같은 계열의 다른 종류를 펼쳐 보이나
var _entries := {}       # 모듈 id → {title, detail, base(고정 설명), button}
var _toggles := {}       # 계열 → [단추, 분류 색] (같은 계열 몇 종 · 지음·대기)
var _specials := {}      # 피복·로봇 → {title, button}
var _qrows: Array = []   # 대기열 줄마다 {title, bar}
var _queue_sig := ""
var _shape := ""         # 목록의 모양 — 바뀌면 다시 만든다


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("건설"))
	res_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_label.add_theme_font_size_override("font_size", 14)
	add_child(res_label)
	add_child(ThemeFactory.heading("대기열", 16))
	auto_sort.text = "생명유지 → 대피·주거 → 전력 → 식량 순으로 자동 정렬"
	auto_sort.toggled.connect(_on_sort)
	add_child(auto_sort)
	queue_box.add_theme_constant_override("separation", 6)
	add_child(queue_box)
	message.add_theme_color_override("font_color", Palette.AMBER)
	add_child(message)
	add_child(HSeparator.new())
	add_child(ThemeFactory.heading("짓기", 16))
	catalog.add_theme_constant_override("separation", 6)
	add_child(catalog)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	auto_sort.set_pressed_no_signal(sim.queue_by_priority)
	rebuild()


func _on_sort(on: bool) -> void:
	sim.queue_by_priority = on
	if on:
		sim.queue.sort_custom(sim._queue_order)
	refresh()


func _shape_sig() -> String:
	var open := PackedStringArray()
	for f in _open:
		if _open[f]:
			open.append(String(f))
	return "%d|%s|%s" % [sim.get_instance_id(), str(sim.techs.has("robot_fabrication")), ",".join(open)]


## 날마다·탭을 고를 때: 목록의 모양이 그대로면 글과 단추만 고친다 (다시 만들면 100 ms 넘게 걸린다)
func refresh() -> void:
	if sim == null:
		return
	if _shape_sig() != _shape:
		rebuild()
		return
	update_view()
	_refresh_queue()
	for kind in _specials:
		_special_update(kind)
	for mid in _entries:
		_entry_update(mid)
	for fam in _toggles:
		_toggle_update(fam)


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func update_view() -> void:
	if sim == null:
		return
	var s := sim.stock
	var speed := 1.5 if sim.techs.has("autonomous_robots_2") else 1.0
	res_label.text = "부품 %s · 레골리스 %s t · 금속 %s t · 로봇 %d대%s — 하루 작업량 %s 로봇·일" % [
		Fmt.n(s["parts"]), Fmt.n(s["regolith_t"]), Fmt.n(s["metal_t"], 1), sim.robots,
		(" (고장 %d)" % sim.robots_broken) if sim.robots_broken else "", Fmt.n((sim.robots - sim.robots_broken) * speed, 1)]


func rebuild() -> void:
	if sim == null:
		return
	_shape = _shape_sig()
	_entries = {}
	_toggles = {}
	_specials = {}
	update_view()
	_queue_sig = "-"
	_refresh_queue()
	_clear(catalog)
	catalog.add_child(_special_entry("regolith_cover"))
	if sim.techs.has("robot_fabrication"):
		catalog.add_child(_special_entry("robot"))
	# 분류마다 계열(기본 모듈 29종)을 보이고, 같은 계열의 다른 종류 4가지는 펼쳐서 본다
	for cat in ORDER:
		var fams := []
		for fam in GameData.FAMILY:
			if sim.M[fam]["category"] == cat:
				fams.append(fam)
		if fams.is_empty():
			continue
		var head := ThemeFactory.heading(Palette.CATEGORY_KO[cat], 15)
		head.add_theme_color_override("font_color", Palette.CATEGORY[cat])
		catalog.add_child(head)
		for fam in fams:
			catalog.add_child(_entry(fam))
			var members: Array = GameData.FAMILY[fam].slice(1)
			if members.is_empty():
				continue
			var toggle := Button.new()
			toggle.flat = true
			toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			toggle.custom_minimum_size.y = 34
			toggle.add_theme_font_size_override("font_size", 13)
			toggle.add_theme_color_override("font_color", Palette.CATEGORY[cat].lightened(0.2))
			_toggles[fam] = toggle
			_toggle_update(fam)
			toggle.clip_text = true
			toggle.tooltip_text = "같은 일을 하는 다른 설계 — 비용·전력·크기·고장 간격이 다르다"
			toggle.pressed.connect(func():
				_open[fam] = not _open.get(fam, false)
				rebuild())
			catalog.add_child(toggle)
			if _open.get(fam, false):
				for m in members:
					var indent := MarginContainer.new()
					indent.add_theme_constant_override("margin_left", 16)
					indent.add_child(_entry(m))
					catalog.add_child(indent)


## 같은 계열 단추의 글 (펼침 · 지음·대기 수)
func _toggle_update(fam: String) -> void:
	var toggle: Button = _toggles[fam]
	var members: Array = GameData.FAMILY[fam].slice(1)
	var built := 0
	var names := []
	for m in members:
		built += int(sim.counts.get(m, 0)) + sim.queued(m)
		names.append(sim.M[m]["name"])
	toggle.text = ("▾ " if _open.get(fam, false) else "▸ ") + "같은 계열 %d종 — %s%s" % [members.size(),
		", ".join(names), ("  (지음·대기 %d)" % built) if built else ""]


## 대기열: 같은 공사들이면 줄의 글·진척만 고치고, 바뀌었으면 줄을 다시 만든다
func _refresh_queue() -> void:
	var seqs := PackedStringArray()
	for item in sim.queue:
		seqs.append(str(int(item["seq"])))
	var qsig := ",".join(seqs)
	if qsig != _queue_sig:
		_queue_sig = qsig
		_clear(queue_box)
		_qrows = []
		if sim.queue.is_empty():
			queue_box.add_child(ThemeFactory.muted("비어 있다. 아래에서 지을 모듈을 고른다."))
		for i in range(sim.queue.size()):
			queue_box.add_child(_queue_row(i, sim.queue[i]))
		return
	for i in range(mini(_qrows.size(), sim.queue.size())):
		_queue_update(_qrows[i], sim.queue[i])


func _queue_update(r: Dictionary, item: Dictionary) -> void:
	var done: float = 1.0 - item["rd"] / maxf(item["rd_total"], 0.001)
	var text := "%s · %d%%" % [GameData.module_name(item["id"]), int(round(done * 100))]
	if item["print_total"] > 0:
		text += " · 인쇄 %s / %s t" % [Fmt.n(item["print_total"] - item["print_t"]), Fmt.n(item["print_total"])]
	(r["title"] as Label).text = text
	(r["bar"] as ProgressBar).value = done


func _queue_row(i: int, item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 14)
	info.add_child(title)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size.y = 6
	bar.add_theme_stylebox_override("background", Palette.box(Palette.PANEL_2, Color.TRANSPARENT, 3, 0))
	bar.add_theme_stylebox_override("fill", Palette.box(Palette.AMBER, Color.TRANSPARENT, 3, 0))
	info.add_child(bar)
	row.add_child(info)
	var r := {"title": title, "bar": bar}
	_qrows.append(r)
	_queue_update(r, item)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.tooltip_text = "손대지 않았으면 자재를 모두, 시작했으면 절반을 돌려받는다"
	cancel.pressed.connect(_on_cancel.bind(i))
	row.add_child(cancel)
	return row


func _on_cancel(i: int) -> void:
	sim.cancel_queued(i)
	refresh()
	changed.emit()


func _entry(mid: String) -> Control:
	var m: Dictionary = sim.M[mid]
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var title := Label.new()
	info.add_child(title)
	var cost := _cost_text(m["cost"])
	var power := float(m["power_kw"])
	var line := "%s · %s 로봇·일%s" % [cost, Fmt.n(float(m["build_rd"])), (" · %s kW" % Fmt.n(power)) if power > 0 else ""]
	var base := line + "\n" + describe(m)
	var detail := ThemeFactory.muted(base, 12)
	info.add_child(detail)
	row.add_child(info)
	var button := Button.new()
	button.text = "짓기"
	button.custom_minimum_size = Vector2(72, 44)
	button.pressed.connect(_on_build.bind(mid))
	row.add_child(button)
	_entries[mid] = {"title": title, "detail": detail, "base": base, "button": button}
	_entry_update(mid)
	return row


## 한 모듈의 바뀌는 것: 지은·대기 수, 지을 수 없는 까닭 (글이 같으면 Label이 다시 모양을 잡지 않는다)
func _entry_update(mid: String) -> void:
	var r: Dictionary = _entries[mid]
	var m: Dictionary = sim.M[mid]
	var count := int(sim.counts.get(mid, 0))
	var waiting := sim.queued(mid)
	(r["title"] as Label).text = m["name"] + ("  ×%d" % count if count else "") + ("  (+%d 대기)" % waiting if waiting else "")
	var reason := sim.build_block_reason(mid, 0.0)
	var button: Button = r["button"]
	button.disabled = reason != ""
	button.tooltip_text = reason if reason != "" else "지을 자리를 고른다"
	(r["detail"] as Label).text = String(r["base"]) + ("\n" + reason if reason != "" else "")


func _special_entry(kind: String) -> Control:
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	var detail: Label
	var button := Button.new()
	button.text = "짓기"
	button.custom_minimum_size = Vector2(72, 44)
	if kind == "regolith_cover":
		detail = ThemeFactory.muted("레골리스 50 t · 5 로봇·일\n거주 모듈 1기를 덮어 만성 선량을 하루 1.0 → 0.45 mSv로 줄인다", 12)
	else:
		detail = ThemeFactory.muted("부품 5 · 4 로봇·일 — 로봇 자가 제작 기술", 12)
	info.add_child(title)
	info.add_child(detail)
	row.add_child(info)
	button.pressed.connect(_on_special.bind(kind))
	row.add_child(button)
	_specials[kind] = {"title": title, "button": button}
	_special_update(kind)
	return row


func _special_update(kind: String) -> void:
	var title: Label = _specials[kind]["title"]
	var button: Button = _specials[kind]["button"]
	if kind == "regolith_cover":
		var habs := int(sim.counts.get("hab_module", 0))
		title.text = "레골리스 피복  %d / %d기" % [sim.covered_habs + sim.queued("regolith_cover"), habs]
		button.disabled = sim.stock["regolith_t"] < sim.C["regolith_cover"]["regolith_t"] \
			or sim.covered_habs + sim.queued("regolith_cover") >= habs
	else:
		title.text = "건설 로봇 제작  (지금 %d대)" % sim.robots
		button.disabled = sim.stock["parts"] < sim.C["robots"]["local_parts"]


func _on_build(mid: String) -> void:
	message.text = "%s — 3D 세계나 지도에서 지을 자리를 누른다" % sim.M[mid]["name"]
	place_requested.emit(mid)


func _on_special(kind: String) -> void:
	if sim.enqueue_special(kind, 0.0):
		message.text = "%s — 대기열에 넣었다" % GameData.module_name(kind)
	refresh()
	changed.emit()


static func _cost_text(cost: Dictionary) -> String:
	var parts := []
	if cost.get("parts", 0):
		parts.append("부품 %s" % Fmt.n(cost["parts"]))
	if cost.get("regolith_t", 0):
		parts.append("레골리스 %s t" % Fmt.n(cost["regolith_t"]))
	if cost.get("metal_t", 0):
		parts.append("금속 %s t" % Fmt.n(cost["metal_t"]))
	if cost.get("water_kg", 0):
		parts.append("물 %s t" % Fmt.n(float(cost["water_kg"]) / 1000.0))
	return " + ".join(parts)


static func describe(m: Dictionary) -> String:
	## 시뮬레이터의 describe()와 같은 기능 설명
	var out := []
	var pv: Dictionary = m.get("provides", {})
	var labels := {"housing": "거주 %s명", "shelter": "대피 %s명", "generation_kw": "발전 %s kW", "landing_slots": "착륙 슬롯 %s",
		"storage_kwh": "축전 %s kWh", "heat_kw": "방열 %s kW", "co2_kg_day": "CO₂ 제거 %s kg/일",
		"wastewater_kg_day": "폐수 처리 %s kg/일", "rp_day": "연구 %s RP/일", "morale": "사기 +%s",
		"care": "진료 %s명", "robot_slots": "로봇 %s대 정비", "print_t_day": "인쇄 %s t/일"}
	for key in labels:
		if pv.has(key):
			out.append(labels[key] % Fmt.n(pv[key]))
	if pv.has("efficiency"):
		out.append("왕복 효율 %s" % Fmt.pct(pv["efficiency"]))
	elif pv.has("storage_kwh") and m.has("family"):
		# 축전 계열은 같은 왕복 효율을 쓴다 (배터리 90%, 재생 연료전지 50%)
		var base: Dictionary = GameData.MODULES[m["family"]].get("provides", {})
		if base.has("efficiency"):
			out.append("왕복 효율 %s" % Fmt.pct(base["efficiency"]))
	if String(pv.get("dose", "")) == "covered":
		out.append("두꺼운 벽 — 피복 모듈 수준 선량")
	if m.has("clearance_m"):
		out.append("거리 규칙 %d m" % int(m["clearance_m"]))
	if pv.has("recovery"):
		out.append("회수 %s" % Fmt.pct(pv["recovery"]))
	if pv.has("storage"):
		var st := []
		for k in pv["storage"]:
			st.append(_amount(k, pv["storage"][k]))
		out.append("저장: " + ", ".join(st))
	if m.has("recipe"):
		var ins := []
		for k in m["recipe"]["in"]:
			ins.append(_amount(k, m["recipe"]["in"][k]))
		var outs := []
		for k in m["recipe"]["out"]:
			outs.append(_amount(k, m["recipe"]["out"][k]))
		out.append("%s → %s (하루)" % [", ".join(ins) if ins.size() else "채굴", ", ".join(outs)])
	return " · ".join(out)


const RESOURCE_KO := {"o2_kg": "산소", "h2_kg": "수소", "water_kg": "물", "co2_kg": "CO₂", "ch4_kg": "메탄",
	"food_kg": "식량", "regolith_t": "레골리스", "metal_t": "금속", "parts": "부품",
	"propellant_t": "추진제", "wastewater_kg": "폐수"}


static func _amount(key: String, value: float) -> String:
	var unit := "t" if key.ends_with("_t") else ("" if key == "parts" else "kg")
	var num := Fmt.n(value, 0 if is_equal_approx(value, round(value)) else 1)
	return "%s %s%s" % [RESOURCE_KO.get(key, key), num, (" " + unit) if unit != "" else ""]
