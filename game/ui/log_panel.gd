class_name LogPanel
extends VBoxContainer
## 기록 탭 — 셋 가운데 하나를 본다:
##   관리 기록: 도시의 모든 기록 (최근 것부터, 120개까지). 새 기록은 맨 위에 더하고 넘치는 것만 뺀다 (다 다시 만들지 않는다)
##   운영 기록: 시드가 한 일 (자동 운영이든 맡긴 분야든 — CityAuto) 과 그 까닭. 분야로 거른다
##   통계: 날마다 기록의 그래프 (StatsView)

const KIND_COLOR := {"info": Palette.MUTED, "build": Palette.MUTED, "good": Palette.GREEN, "warn": Palette.AMBER,
	"critical": Palette.RED, "death": Palette.RED}
const DOMAIN_COLOR := {"build": Palette.AMBER, "research": Palette.BLUE, "land": Palette.GREEN, "explore": Palette.TEXT,
	"trade": Palette.AMBER, "mega": Palette.GREEN, "politics": Palette.PURPLE}

const SHOW := 120

var sim: CitySim
var colony: Dictionary = {}        # 고른 식민지 (운영 기록 — c["oplog"], 통계)
var mgr: Colonies                  # 모든 도시 (통계의 '모든 도시의 정착민')
var stats := StatsView.new()
var list := VBoxContainer.new()
var _shown := -1
var _view := "notes"               # notes 관리 기록 · ops 운영 기록
var _filter := ""                  # 운영 기록의 분야 ("" = 전부)
var _ops_sig := ""
var _heading: Label
var _chips := HFlowContainer.new()
var _summary: Label
var _view_buttons := {}            # 보기 → 단추 (코드로 보기를 바꿀 때도 눌린 단추를 맞춘다)


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_heading = ThemeFactory.heading("관리 기록")
	add_child(_heading)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for v in [["notes", "관리 기록", "관리 기록 — 알림과 사건"], ["ops", "운영 기록", "운영 기록 — 시드가 한 일"], ["stats", "통계", "통계 — 지난 날들의 그래프"]]:
		var b := Button.new()
		b.text = v[1]
		b.tooltip_text = v[2]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = v[0] == _view
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(0, 44)
		var id: String = v[0]
		b.pressed.connect(func(): _set_view(id))
		views.add_child(b)
		_view_buttons[id] = b
	add_child(views)
	_summary = ThemeFactory.muted("", 13)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.visible = false
	add_child(_summary)
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	_chips.visible = false
	var chip_group := ButtonGroup.new()
	for d in [["", "전부"]] + CityAuto.DOMAINS:
		var b := Button.new()
		b.text = d[1]
		b.toggle_mode = true
		b.button_group = chip_group
		b.button_pressed = d[0] == ""
		b.custom_minimum_size = Vector2(0, 32)
		var id: String = d[0]
		b.pressed.connect(func():
			_filter = id
			_ops_sig = ""
			update_view())
		_chips.add_child(b)
	add_child(_chips)
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	stats.visible = false
	add_child(stats)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	_shown = -1
	_ops_sig = ""
	rebuild()


func refresh() -> void:
	update_view()


func _set_view(v: String) -> void:
	_view = v
	if _view_buttons.has(v):
		(_view_buttons[v] as Button).set_pressed_no_signal(true)
	_heading.text = {"notes": "관리 기록", "ops": "운영 기록", "stats": "통계"}.get(v, "관리 기록")
	_chips.visible = v == "ops"
	_summary.visible = v == "ops"
	list.visible = v != "stats"
	stats.visible = v == "stats"
	_shown = -1
	_ops_sig = ""
	rebuild()


func update_view() -> void:
	if sim == null:
		return
	if _view == "stats":
		stats.colony = colony if colony.get("sim") == sim else {}
		stats.mgr = mgr
		stats.refresh()
		return
	if _view == "ops":
		_update_ops()
		return
	if sim.notes.size() == _shown:
		return
	var n := sim.notes.size()
	if _shown <= 0 or n < _shown or n - _shown > SHOW:
		rebuild()
		return
	for i in range(_shown, n):
		var label := _label(sim.notes[i])
		list.add_child(label)
		list.move_child(label, 0)
	while list.get_child_count() > SHOW:
		var last := list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	_shown = n


func _label(n: Array) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.text = "%s  %s" % [sim.date_text(n[0]), n[1]]
	label.add_theme_color_override("font_color", KIND_COLOR.get(n[2], Palette.TEXT))
	return label


func _clear() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


func rebuild() -> void:
	if sim == null:
		return
	if _view == "stats":
		update_view()
		return
	if _view == "ops":
		_ops_sig = ""
		_update_ops()
		return
	_shown = sim.notes.size()
	_clear()
	var start := maxi(0, sim.notes.size() - SHOW)
	for i in range(sim.notes.size() - 1, start - 1, -1):
		list.add_child(_label(sim.notes[i]))
	if sim.notes.is_empty():
		list.add_child(ThemeFactory.muted("아직 기록이 없다."))


## 운영 기록: 맡긴 분야 요약 · 분야로 거른 기록 (최근 것부터). 기록이나 거르개가 바뀔 때만 다시 만든다
func _update_ops() -> void:
	var lg: Array = colony.get("oplog", []) if colony.get("sim") == sim and colony.get("oplog") is Array else []
	var sig := "%d|%d|%s|%d" % [sim.get_instance_id(), lg.size(), _filter, int(lg[-1][0]) if not lg.is_empty() else -1]
	if colony.get("sim") == sim:
		if CityAuto.full(sim):
			_summary.text = "자동 운영 — 시드가 모든 분야를 맡는다. 자동 운영을 끄면 개척 탭의 '위임'에서 고른 분야만 맡는다."
		else:
			var names := PackedStringArray()
			for d in CityAuto.DOMAINS:
				if CityAuto.on(colony, d[0]):
					names.append(d[1])
			_summary.text = ("맡긴 분야: %s" % " · ".join(names)) if not names.is_empty() else \
				"직접 운영 — 맡긴 분야가 없다. 개척 탭의 '위임'에서 분야를 골라 시드에게 맡길 수 있다."
	if sig == _ops_sig:
		return
	_ops_sig = sig
	_clear()
	var shown := 0
	for k in range(lg.size() - 1, -1, -1):
		var e: Array = lg[k]
		if _filter != "" and String(e[1]) != _filter:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tag := Label.new()
		tag.text = CityAuto.domain_name(String(e[1]))
		tag.custom_minimum_size = Vector2(92, 0)
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", DOMAIN_COLOR.get(String(e[1]), Palette.MUTED))
		row.add_child(tag)
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s  %s" % [CityAuto.when_text(sim, int(e[0])), String(e[2])]
		row.add_child(label)
		list.add_child(row)
		shown += 1
		if shown >= SHOW:
			break
	if shown == 0:
		list.add_child(ThemeFactory.muted("아직 시드가 한 일이 없다." if _filter == "" else "이 분야에서 시드가 한 일이 없다."))
