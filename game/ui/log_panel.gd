class_name LogPanel
extends VBoxContainer
## 기록 탭 — 관리 기록 (최근 것부터, 120개까지). 새 기록은 맨 위에 더하고 넘치는 것만 뺀다 (다 다시 만들지 않는다)

const KIND_COLOR := {"info": Palette.MUTED, "build": Palette.MUTED, "good": Palette.GREEN, "warn": Palette.AMBER,
	"critical": Palette.RED, "death": Palette.RED}

const SHOW := 120

var sim: CitySim
var list := VBoxContainer.new()
var _shown := -1


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("관리 기록"))
	list.add_theme_constant_override("separation", 4)
	add_child(list)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	_shown = -1
	rebuild()


func refresh() -> void:
	update_view()


func update_view() -> void:
	if sim == null or sim.notes.size() == _shown:
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


func rebuild() -> void:
	if sim == null:
		return
	_shown = sim.notes.size()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var start := maxi(0, sim.notes.size() - SHOW)
	for i in range(sim.notes.size() - 1, start - 1, -1):
		list.add_child(_label(sim.notes[i]))
	if sim.notes.is_empty():
		list.add_child(ThemeFactory.muted("아직 기록이 없다."))
