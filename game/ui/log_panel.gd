class_name LogPanel
extends VBoxContainer
## 기록 탭 — 관리 기록 (최근 것부터)

const KIND_COLOR := {"info": Palette.MUTED, "build": Palette.MUTED, "good": Palette.GREEN, "warn": Palette.AMBER,
	"critical": Palette.RED, "death": Palette.RED}

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


func update_view() -> void:
	if sim != null and sim.notes.size() != _shown:
		rebuild()


func rebuild() -> void:
	if sim == null:
		return
	_shown = sim.notes.size()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var start := maxi(0, sim.notes.size() - 120)
	for i in range(sim.notes.size() - 1, start - 1, -1):
		var n: Array = sim.notes[i]
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s  %s" % [sim.date_text(n[0]), n[1]]
		label.add_theme_color_override("font_color", KIND_COLOR.get(n[2], Palette.TEXT))
		list.add_child(label)
	if sim.notes.is_empty():
		list.add_child(ThemeFactory.muted("아직 기록이 없다."))
