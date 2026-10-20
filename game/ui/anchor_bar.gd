class_name AnchorBar
extends PanelContainer
## 3D 화면 위쪽의 고정점 경로: 우주 › 태양계 › 지구 › 나로 우주항 ▾
## 단계를 누르면 그 고정점으로 날아가 고정하고, '›'·'▾'를 누르면 그 단계 아래의 것(행성·위성·도시·대도시·수송선)을 고른다.
## 한 단계 위로는 Backspace. 카메라가 움직여 경로가 바뀔 때만 단추를 다시 만든다.

var world: WorldView
var _row: HBoxContainer
var _popup: PopupMenu
var _popup_items: Array = []
var _sig := ""
var _head := ""
var _kids_n := 0
var _kids_ms := 0


func _init() -> void:
	add_theme_stylebox_override("panel", Palette.box(Color(0.04, 0.05, 0.08, 0.62), Color(1, 1, 1, 0.08), 8, 4))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)
	_popup = PopupMenu.new()
	_popup.add_theme_font_size_override("font_size", 15)
	_popup.id_pressed.connect(_on_pick)
	add_child(_popup)


func refresh() -> void:
	if world == null:
		return
	var path := world.anchors.path()
	var parts := PackedStringArray()
	for a in path:
		parts.append(String(a["name"]))
	# 마지막 단계 아래의 수 ('▾'를 보일지): 목록을 만들어야 알 수 있다 (지구는 대도시·지역 50여 곳) — 경로가 같으면 0.5초에 한 번
	var head := "|".join(parts)
	var now := Time.get_ticks_msec()
	if head != _head or now - _kids_ms > 500:
		_head = head
		_kids_ms = now
		_kids_n = world.anchors.children(path[-1]).size()
	parts.append(str(_kids_n))
	var sig := "|".join(parts)
	if sig == _sig:
		return
	_sig = sig
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for i in path.size():
		var a: Dictionary = path[i]
		var b := Button.new()
		b.text = String(a["name"])
		b.flat = true
		b.custom_minimum_size.y = 36
		b.add_theme_font_size_override("font_size", 14)
		var last := i == path.size() - 1
		b.add_theme_color_override("font_color", Palette.AMBER if last else Color(0.86, 0.88, 0.92))
		b.tooltip_text = "%s — 여기를 고정점으로" % a["name"]
		b.pressed.connect(func(): world.anchors.go(a))
		_row.add_child(b)
		var kids := world.anchors.children(a)
		if last and kids.is_empty():
			continue
		var ch := Button.new()
		ch.text = "▾" if last else "›"
		ch.flat = true
		ch.custom_minimum_size = Vector2(26, 36)
		ch.add_theme_font_size_override("font_size", 15)
		ch.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
		ch.tooltip_text = "%s 안에서 고르기" % a["name"]
		ch.disabled = kids.is_empty()
		ch.pressed.connect(func(): _open_children(a, ch))
		_row.add_child(ch)


func _open_children(a: Dictionary, at: Control) -> void:
	_popup.clear()
	_popup_items.clear()
	var kids := world.anchors.children(a)
	var last_kind := ""
	for k in kids:
		var kind := String(k["kind"])
		var group := _group_name(kind, k)
		if group != last_kind and not _popup_items.is_empty():
			_popup.add_separator(group)
		elif _popup_items.is_empty() and group != "":
			_popup.add_separator(group)
		last_kind = group
		_popup.add_item(String(k["name"]), _popup_items.size())
		_popup_items.append(k)
	var r := at.get_global_rect()
	_popup.position = Vector2i(get_window().position) + Vector2i(int(r.position.x), int(r.end.y))
	_popup.reset_size()
	_popup.popup()


static func _group_name(kind: String, k: Dictionary) -> String:
	match kind:
		"colony", "site":
			return "도시"
		"metro":
			return "대도시"
		"tech":
			return "첨단 산업 지역"
		"ship":
			return "날아가는 수송선"
		"star":
			return "이웃 별"
		"body":
			var b: Dictionary = Astro.bodies.get(String(k["id"]), {})
			return "위성" if String(b.get("kind", "")) == "moon" else "행성"
	return ""


func _on_pick(id: int) -> void:
	if id >= 0 and id < _popup_items.size():
		world.anchors.go(_popup_items[id])
