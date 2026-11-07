class_name CrossSection
extends Control
## 건물 단면도 (자료 city_sections.json) — 건물을 누른 카드의 '단면 보기'. 1970년대 NASA 우주 식민지 그림풍:
## 크림색 종이에 남색 선, 주황·황토·청록, 이끌림선 이름표, 아래 오른쪽의 도면 표제란.
## 계열의 모양(누운 원통·돔·탑·탱크·상자 건물·태양광 돛대·방열판·착륙장·원자로·굴착 장비)에 방을 나눠 그리고,
## 방마다 그 일을 하는 이름 있는 정착민(CityPeople — 사는 곳이면 누구나)을 세운다. 왼쪽에서 들어오고 오른쪽으로 나가는
## 공기·물·전력·열의 관에 알갱이가 흐른다 (값은 그 건물의 하루 — 레시피·전력·사람 몫). 닫기·Esc로 닫는다.

signal closed

const PATH := "res://data/city_sections.json"
const PAPER := Color("efe6cf")
const PAPER_2 := Color("e4d6b4")
const INK := Color("23304a")
const RUST := Color("c8552d")
const OCHRE := Color("d9a441")
const TEAL := Color("2f7f7a")
const OLIVE := Color("7d8a3c")
const SKY := Color("7fb6d9")
const GROUND := Color("a99270")
const KIND_COL := {"living": Color("f3c99a"), "work": Color("d7c8a0"), "plant": Color("a8c98a"), "machine": Color("b9c4cc"),
	"tank": Color("9cc5d6"), "store": Color("cdb894"), "care": Color("f2b8a8"), "lab": Color("b7c7e6"), "social": Color("e8d27a"),
	"power": Color("f2d36b")}
const FLOW_COL := {"o2_kg": Color("4f9fd6"), "co2_kg": Color("7f858b"), "water_kg": Color("2f9bb5"), "h2_kg": Color("9a7fd0"),
	"ch4_kg": Color("e08a3c"), "food_kg": Color("4f9c45"), "regolith_t": Color("b08a50"), "metal_t": Color("7e8893"),
	"parts": Color("9a6a42"), "wastewater_kg": Color("7a7a3a"), "power": Color("e0a91c"), "heat": Color("d9473a")}
const FLOW_NAME := {"o2_kg": "산소", "co2_kg": "CO₂", "water_kg": "물", "h2_kg": "수소", "ch4_kg": "메탄", "food_kg": "식량",
	"regolith_t": "레골리스", "metal_t": "금속", "parts": "부품", "wastewater_kg": "폐수", "power": "전력", "heat": "열"}
const ROLE_COL := {"engineer": Color("c8552d"), "scientist": Color("2f5f9f"), "doctor": Color("e9e4da"), "farmer": Color("5f8c3a"),
	"pilot": Color("2f7f7a"), "teacher": Color("8a4f9a"), "artist": Color("d9a441"), "manager": Color("4a4f5a")}

static var D := {}

var sim: CitySim
var colony: Dictionary = {}
var mid := ""
var _t := 0.0
var _grain := PackedVector3Array()          # 종이 결: (x, y, 진하기) — 0~1 비율
var _close: Button
var _rooms: Array = []                      # 그린 방 [Rect2, 이름, 종류] (마지막 그리기)
var _people_drawn: Array = []               # 그린 사람 [이름, 역할] — 시험·스크린숏용


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {"families": {}}
	return D


static func template(module_id: String) -> Dictionary:
	var fam := GameData.family(module_id)
	var t: Dictionary = (data().get("families", {}) as Dictionary).get(fam, {"shape": "hall", "rooms": [["실내", "work"]], "roles": []})
	t = t.duplicate(true)
	if String(t["shape"]) == "capsule" and (module_id.contains("tower") or module_id.contains("block") or module_id.contains("stack")):
		t["shape"] = "tower"                             # 거주 계열의 고층 (타워·아파트·적층 거주)
	return t


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1970
	for i in 900:
		_grain.append(Vector3(rng.randf(), rng.randf(), rng.randf()))
	_close = Button.new()
	_close.text = "닫기"
	_close.custom_minimum_size = Vector2(96, 40)
	_close.pressed.connect(close)
	add_child(_close)


func open(p_sim: CitySim, p_colony: Dictionary, p_mid: String) -> void:
	sim = p_sim
	colony = p_colony
	mid = p_mid
	_t = 0.0
	visible = true
	_layout_close()
	queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func _layout_close() -> void:
	_close.position = Vector2(size.x - _close.size.x - 30.0, 26.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_close()


func _process(delta: float) -> void:
	if visible:
		if not Access.calm:                       # 움직임 줄이기 — 작물·기계·흐름이 멈춘 그림으로
			_t += delta
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ── 그리기 ──────────────────────────────────────────────────────
func _font(bold := false) -> Font:
	var f: Font = (ThemeFactory.bold if bold else ThemeFactory.regular) if ThemeFactory.regular else get_theme_default_font()
	return f if f != null else get_theme_default_font()


func _text(p: Vector2, s: String, px: int, col: Color, bold := false, width := -1.0) -> void:
	draw_string(_font(bold), p, I18n.t(s), HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(px), col)


func _draw() -> void:
	if sim == null or mid == "" or not sim.M.has(mid):
		return
	var m: Dictionary = sim.M[mid]
	var t := template(mid)
	_rooms.clear()
	_people_drawn.clear()
	# 종이와 테두리
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12, 0.82))
	var paper := Rect2(Vector2(18, 18), size - Vector2(36, 36))
	draw_rect(paper, PAPER)
	for g in _grain:
		draw_rect(Rect2(paper.position + Vector2(g.x, g.y) * paper.size, Vector2(2, 2)), Color(0.45, 0.35, 0.2, 0.05 + 0.06 * g.z))
	draw_rect(paper.grow(-8), INK, false, 2.0)
	draw_rect(paper.grow(-12), INK, false, 1.0)
	var inner := paper.grow(-24)
	# 제목
	var count := int(sim.counts.get(mid, 0))
	_text(inner.position + Vector2(4, 30), "단면도 — %s" % String(m["name"]), 26, INK, true)
	var cat := String(Palette.CATEGORY_KO.get(String(m.get("category", "")), ""))
	_text(inner.position + Vector2(6, 54), "%s · %d기 · %s · %s" % [cat, count, String(colony.get("name", "")), sim.date_text()], 14, INK.lightened(0.25))
	# 그림 자리: 제목 아래, 흐름 설명 위
	var area := Rect2(inner.position + Vector2(150, 78), Vector2(inner.size.x - 300, inner.size.y - 78 - 120))
	var ground_y := area.end.y - 18.0
	_draw_ground(Rect2(Vector2(inner.position.x, ground_y), Vector2(inner.size.x, area.end.y - ground_y + 4.0)))
	var bound := _draw_shape(String(t["shape"]), t, Rect2(area.position, Vector2(area.size.x, ground_y - area.position.y)), m)
	_draw_people(t)
	_draw_flows(m, bound, inner)
	_draw_title_block(inner, t)


func _draw_ground(r: Rect2) -> void:
	draw_rect(r, GROUND.lightened(0.15))
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.end.y), Vector2(x + 14.0, r.position.y), GROUND.darkened(0.25), 1.0)
		x += 9.0
	draw_line(r.position, Vector2(r.end.x, r.position.y), INK, 2.0)


## 모양을 그리고 방을 나눈다 — 건물의 바깥 사각형(관이 닿는 곳)을 돌려준다
func _draw_shape(shape: String, t: Dictionary, a: Rect2, m: Dictionary) -> Rect2:
	var rooms: Array = t.get("rooms", [])
	match shape:
		"capsule":
			var w := minf(a.size.x * 0.84, 660.0)
			var h := minf(a.size.y * 0.78, 300.0)
			var r := Rect2(Vector2(a.get_center().x - w * 0.5, a.end.y - h - 10.0), Vector2(w, h))
			# 레골리스 피복 (덮였으면)
			if sim.covered_habs > 0:
				var cov := r.grow(16)
				_round_rect(cov, cov.size.y * 0.5, GROUND.lightened(0.05), INK, 1.5)
				for i in 40:
					var px := cov.position.x + cov.size.x * (i + 0.5) / 40.0
					draw_line(Vector2(px, cov.position.y + 4), Vector2(px - 8, cov.position.y + 14), GROUND.darkened(0.3), 1.0)
			_round_rect(r, r.size.y * 0.5, Color("dfe3e6"), INK, 2.5)
			var body := r.grow_individual(-r.size.y * 0.42, -10, -r.size.y * 0.42, -10)
			_grid_rooms(body, rooms, 2)
			return r
		"dome":
			var rad := minf(a.size.x * 0.4, a.size.y * 0.95)
			var c := Vector2(a.get_center().x, a.end.y)
			var pts := PackedVector2Array()
			for i in 49:
				var ang := PI + PI * i / 48.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(pts, GROUND.lightened(0.1))
			var inner_pts := PackedVector2Array()
			for i in 49:
				var ang2 := PI + PI * i / 48.0
				inner_pts.append(c + Vector2(cos(ang2), sin(ang2)) * rad * 0.86)
			draw_colored_polygon(inner_pts, Color("f6ecd6"))
			draw_polyline(pts, INK, 2.5, true)
			draw_polyline(inner_pts, INK, 1.5, true)
			var box := Rect2(c + Vector2(-rad * 0.62, -rad * 0.62), Vector2(rad * 1.24, rad * 0.6))
			_grid_rooms(box, rooms.filter(func(x): return String(x[1]) != "store"), 2)
			for x in rooms:
				if String(x[1]) == "store":
					_label_leader(c + Vector2(rad * 0.66, -rad * 0.55), c + Vector2(rad * 1.05, -rad * 0.85), String(x[0]))
			return Rect2(c - Vector2(rad, rad), Vector2(rad * 2.0, rad))
		"tower":
			var floors := 8
			var w2 := minf(a.size.x * 0.34, 260.0)
			var h2 := a.size.y * 0.96
			var r2 := Rect2(Vector2(a.get_center().x - w2 * 0.5, a.end.y - h2), Vector2(w2, h2))
			draw_rect(r2, Color("dfe3e6"))
			draw_rect(r2, INK, false, 2.5)
			var fh := r2.size.y / floors
			for f in floors:
				var fr := Rect2(Vector2(r2.position.x + 6, r2.end.y - fh * (f + 1) + 4), Vector2(r2.size.x - 12, fh - 8))
				var room: Array = rooms[f % rooms.size()]
				_room(fr, String(room[0]) if f == floors - 1 or f % rooms.size() == 0 else "", String(room[1]))
			return r2
		"tank":
			var n := rooms.size()
			var tw := minf(a.size.x * 0.7 / n, 150.0)
			var th := a.size.y * 0.82
			var x0 := a.get_center().x - tw * n * 0.5
			for i in n:
				var tr := Rect2(Vector2(x0 + i * tw + 8, a.end.y - th), Vector2(tw - 16, th))
				_round_rect(tr, tr.size.x * 0.5, Color("dfe3e6"), INK, 2.0)
				var kind := String(rooms[i][1])
				var lvl := _level(String(rooms[i][0]))
				var fill := Rect2(Vector2(tr.position.x + 5, tr.end.y - (tr.size.y - 10) * lvl - 5), Vector2(tr.size.x - 10, (tr.size.y - 10) * lvl))
				draw_rect(fill, KIND_COL.get(kind, SKY))
				draw_line(Vector2(fill.position.x, fill.position.y), Vector2(fill.end.x, fill.position.y), INK.lightened(0.3), 1.0)
				_rooms.append([tr, String(rooms[i][0]), kind])
				_text(Vector2(tr.position.x, tr.position.y - 8), String(rooms[i][0]), 13, INK, true)
				if lvl < 0.999:
					_text(Vector2(tr.position.x + 4, fill.position.y - 4), "%d%%" % int(lvl * 100.0), 11, INK.lightened(0.3))
			return Rect2(Vector2(x0, a.end.y - th), Vector2(tw * n, th))
		"mast":
			var base := Rect2(Vector2(a.get_center().x - 60, a.end.y - 70), Vector2(120, 70))
			var top := a.position.y + 20.0
			draw_line(Vector2(a.get_center().x, base.position.y), Vector2(a.get_center().x, top + 30), INK, 5.0)
			for i in 6:
				var py := top + 30.0 + i * (base.position.y - top - 60.0) / 6.0
				var pr := Rect2(Vector2(a.get_center().x - 120, py), Vector2(240, 18))
				draw_rect(pr, Color("2f4f7f"))
				for j in 8:
					draw_line(Vector2(pr.position.x + j * 30.0, py), Vector2(pr.position.x + j * 30.0, py + 18), Color("9fb8d9"), 1.0)
				draw_rect(pr, INK, false, 1.5)
			_rooms.append([Rect2(Vector2(a.get_center().x - 120, top + 30), Vector2(240, 120)), String(rooms[0][0]), "power"])
			_label_leader(Vector2(a.get_center().x + 120, top + 40), Vector2(a.get_center().x + 210, top + 10), String(rooms[0][0]))
			_room(base, String(rooms[-1][0]), String(rooms[-1][1]))
			if rooms.size() > 2:
				_label_leader(Vector2(a.get_center().x, top + 28), Vector2(a.get_center().x - 200, top + 4), String(rooms[1][0]))
			return Rect2(Vector2(a.get_center().x - 120, top), Vector2(240, a.end.y - top))
		"panel":
			var pr2 := Rect2(Vector2(a.position.x + a.size.x * 0.12, a.end.y - a.size.y * 0.55), Vector2(a.size.x * 0.76, a.size.y * 0.3))
			for i in 9:
				var fx := pr2.position.x + i * pr2.size.x / 9.0
				draw_rect(Rect2(Vector2(fx + 3, pr2.position.y), Vector2(pr2.size.x / 9.0 - 6, pr2.size.y)), Color("e9e9e2"))
				draw_rect(Rect2(Vector2(fx + 3, pr2.position.y), Vector2(pr2.size.x / 9.0 - 6, pr2.size.y)), INK, false, 1.2)
				var glow := 0.5 + 0.5 * sin(_t * 2.0 + i)
				draw_line(Vector2(fx + pr2.size.x / 18.0, pr2.position.y + 4), Vector2(fx + pr2.size.x / 18.0, pr2.end.y - 4),
					Color(FLOW_COL["heat"], 0.25 + 0.3 * glow), 3.0)
			_rooms.append([pr2, String(rooms[0][0]), "machine"])
			_label_leader(pr2.position + Vector2(pr2.size.x * 0.5, 0), pr2.position + Vector2(pr2.size.x * 0.5, -40), String(rooms[0][0]))
			var pump := Rect2(Vector2(pr2.get_center().x - 50, pr2.end.y + 8), Vector2(100, a.end.y - pr2.end.y - 8))
			_room(pump, String(rooms[-1][0]), "machine")
			return pr2.merge(pump)
		"pad":
			var pad := Rect2(Vector2(a.position.x + a.size.x * 0.1, a.end.y - 18), Vector2(a.size.x * 0.62, 18))
			draw_rect(pad, Color("c9c4b8"))
			draw_rect(pad, INK, false, 2.0)
			for i in 7:
				draw_line(pad.position + Vector2(i * pad.size.x / 7.0 + 10, 9), pad.position + Vector2(i * pad.size.x / 7.0 + 40, 9), OCHRE, 3.0)
			var c2 := pad.get_center() + Vector2(0, -12)
			var lander := PackedVector2Array([c2 + Vector2(-50, 0), c2 + Vector2(-36, -70), c2 + Vector2(-14, -130), c2 + Vector2(14, -130),
				c2 + Vector2(36, -70), c2 + Vector2(50, 0)])
			draw_colored_polygon(lander, Color("e6e2d8"))
			draw_polyline(lander + PackedVector2Array([lander[0]]), INK, 2.0, true)
			draw_line(c2 + Vector2(-50, 0), c2 + Vector2(-70, 10), INK, 2.0)
			draw_line(c2 + Vector2(50, 0), c2 + Vector2(70, 10), INK, 2.0)
			_rooms.append([Rect2(c2 + Vector2(-50, -130), Vector2(100, 130)), String(rooms[0][0]), "work"])
			var booth := Rect2(Vector2(pad.end.x + 30, a.end.y - 90), Vector2(110, 90))
			_room(booth, String(rooms[-1][0]), String(rooms[-1][1]))
			return Rect2(Vector2(pad.position.x, c2.y - 130), Vector2(booth.end.x - pad.position.x, a.end.y - (c2.y - 130)))
		"reactor":
			var c3 := Vector2(a.position.x + a.size.x * 0.32, a.end.y - a.size.y * 0.42)
			var rr := minf(a.size.y * 0.4, 130.0)
			draw_circle(c3, rr, GROUND.lightened(0.1))
			draw_arc(c3, rr, 0, TAU, 64, INK, 2.5)
			draw_circle(c3, rr * 0.62, Color("dfe3e6"))
			draw_arc(c3, rr * 0.62, 0, TAU, 48, INK, 2.0)
			var core := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(c3, rr * 0.34, Color(1.0, 0.55 + 0.15 * core, 0.2))
			draw_arc(c3, rr * 0.34, 0, TAU, 32, INK, 1.5)
			_rooms.append([Rect2(c3 - Vector2(rr, rr) * 0.34, Vector2(rr, rr) * 0.68), String(rooms[0][0]), "power"])
			_label_leader(c3 + Vector2(0, -rr * 0.34), c3 + Vector2(-rr * 0.9, -rr * 1.25), String(rooms[0][0]))
			_label_leader(c3 + Vector2(rr * 0.8, -rr * 0.5), c3 + Vector2(rr * 1.2, -rr * 1.2), String(rooms[1][0]))
			var side := Rect2(Vector2(c3.x + rr + 30, a.end.y - rr * 1.3), Vector2(a.end.x - (c3.x + rr + 30) - 20, rr * 1.3))
			_grid_rooms(side, rooms.slice(2), 1)
			return Rect2(c3 - Vector2(rr, rr), Vector2(side.end.x - (c3.x - rr), rr * 2.0))
		"rig":
			var body := Rect2(Vector2(a.position.x + a.size.x * 0.25, a.end.y - 110), Vector2(a.size.x * 0.4, 70))
			_round_rect(body, 14, Color("e0b75a"), INK, 2.0)
			for i in 6:
				draw_circle(Vector2(body.position.x + 20 + i * (body.size.x - 40) / 5.0, a.end.y - 22), 16, Color("3c3f46"))
				draw_arc(Vector2(body.position.x + 20 + i * (body.size.x - 40) / 5.0, a.end.y - 22), 16, 0, TAU, 20, INK, 1.5)
			var tip := Vector2(body.end.x + 70, a.end.y - 4)
			draw_line(Vector2(body.end.x - 10, body.position.y + 20), tip + Vector2(0, -60), INK, 6.0)
			var spin := _t * 4.0
			for i in 4:
				var ang3 := spin + i * PI * 0.5
				draw_line(tip + Vector2(0, -60), tip + Vector2(0, -60) + Vector2(cos(ang3), sin(ang3)) * 26, Color("6b6f78"), 4.0)
			_grid_rooms(body.grow(-8), rooms.slice(0, 2), 2)
			if rooms.size() > 2:
				_label_leader(tip + Vector2(0, -60), tip + Vector2(40, -140), String(rooms[2][0]))
			return body.merge(Rect2(tip - Vector2(0, 90), Vector2(30, 90)))
		_:
			# 상자 건물: 기울어진 지붕, 방은 한두 줄
			var w4 := minf(a.size.x * 0.86, 640.0)
			var h4 := minf(a.size.y * 0.8, 280.0)
			var r4 := Rect2(Vector2(a.get_center().x - w4 * 0.5, a.end.y - h4), Vector2(w4, h4))
			var roof := PackedVector2Array([r4.position + Vector2(-12, 0), Vector2(r4.position.x + w4 * 0.5, r4.position.y - 34),
				Vector2(r4.end.x + 12, r4.position.y)])
			draw_colored_polygon(roof, GROUND.lightened(0.05))
			draw_polyline(roof, INK, 2.0, true)
			draw_rect(r4, Color("dfe3e6"))
			draw_rect(r4, INK, false, 2.5)
			_grid_rooms(r4.grow(-8), rooms, 2 if rooms.size() > 3 else 1)
			return r4


func _round_rect(r: Rect2, rad: float, fill: Color, line: Color, w: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = line
	sb.set_border_width_all(int(round(w)))
	sb.set_corner_radius_all(int(minf(rad, minf(r.size.x, r.size.y) * 0.5)))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


## 방을 줄 rows개로 나눠 그린다
func _grid_rooms(r: Rect2, rooms: Array, rows: int) -> void:
	if rooms.is_empty():
		return
	rows = clampi(rows, 1, rooms.size())
	var per := int(ceil(float(rooms.size()) / rows))
	var rh := r.size.y / rows
	for i in rooms.size():
		@warning_ignore("integer_division")
		var row := i / per
		var col := i % per
		var n_in_row := mini(per, rooms.size() - row * per)
		var rw := r.size.x / n_in_row
		var cell := Rect2(Vector2(r.position.x + col * rw + 3, r.position.y + row * rh + 3), Vector2(rw - 6, rh - 6))
		_room(cell, String(rooms[i][0]), String(rooms[i][1]))


func _room(r: Rect2, name: String, kind: String) -> void:
	draw_rect(r, KIND_COL.get(kind, Color("e0d8c0")))
	# 1970년대 그림의 망점 그늘
	var y := r.position.y + 5.0
	while y < r.end.y:
		var x := r.position.x + 5.0 + fmod(y, 10.0)
		while x < r.end.x - 2.0:
			draw_rect(Rect2(Vector2(x, y), Vector2(1.5, 1.5)), Color(0.2, 0.15, 0.1, 0.12))
			x += 10.0
		y += 8.0
	draw_rect(r, INK, false, 1.5)
	if kind == "plant":
		for i in int(r.size.x / 22.0):
			var px := r.position.x + 12.0 + i * 22.0
			var sway := sin(_t * 1.5 + i) * 2.0
			draw_line(Vector2(px, r.end.y - 6), Vector2(px + sway, r.end.y - r.size.y * 0.45), OLIVE.darkened(0.2), 2.0)
			draw_circle(Vector2(px + sway, r.end.y - r.size.y * 0.45), 5.0, OLIVE.lightened(0.15))
		draw_line(Vector2(r.position.x + 6, r.position.y + 8), Vector2(r.end.x - 6, r.position.y + 8), Color(0.95, 0.45, 0.85, 0.8), 3.0)
	elif kind == "machine":
		var gear := r.get_center() + Vector2(0, r.size.y * 0.12)
		var gr := minf(r.size.x, r.size.y) * 0.2
		draw_arc(gear, gr, _t, _t + TAU * 0.85, 18, INK.lightened(0.25), 3.0)
	elif kind == "power":
		var bolt := PackedVector2Array([r.get_center() + Vector2(-6, -14), r.get_center() + Vector2(4, -2), r.get_center() + Vector2(-2, 0),
			r.get_center() + Vector2(6, 14)])
		draw_polyline(bolt, FLOW_COL["power"].darkened(0.1), 3.0, true)
	if name != "":
		_text(r.position + Vector2(6, 16), name, 13, INK, true, r.size.x - 8.0)
	_rooms.append([r, name, kind])


func _label_leader(at: Vector2, to: Vector2, text: String) -> void:
	draw_circle(at, 3.0, INK)
	draw_line(at, to, INK, 1.2, true)
	draw_line(to, to + Vector2(70, 0), INK, 1.2)
	_text(to + Vector2(2, -4), text, 13, INK, true)


## 탱크의 찬 몫: 그 도시의 그 물건 비축 / 한도
func _level(name: String) -> float:
	var key := ""
	for k in FLOW_NAME:
		if String(FLOW_NAME[k]) == name:
			key = k
	if name.contains("산소"):
		key = "o2_kg"
	elif name.contains("수소"):
		key = "h2_kg"
	elif name.contains("메탄"):
		key = "ch4_kg"
	if key == "" or not sim.caps.has(key) or float(sim.caps[key]) <= 0.0:
		return 0.62
	return clampf(float(sim.stock.get(key, 0.0)) / float(sim.caps[key]), 0.04, 1.0)


## 방마다 사람: 사는 곳이면 이름 있는 정착민 누구나, 일터면 그 역할의 사람 (없으면 이름 없는 정착민)
func _draw_people(t: Dictionary) -> void:
	var roles: Array = t.get("roles", [])
	var named: Array = []
	if not colony.is_empty():
		named = (CityPeople.state(colony)["people"] as Array).duplicate()
	var pick: Array = []
	var living := (t.get("rooms", []) as Array).any(func(x): return String(x[1]) == "living")
	for p in named:
		if living or roles.has(String(p.get("role", ""))):
			pick.append(p)
	var k := 0
	for room in _rooms:
		var r: Rect2 = room[0]
		var kind := String(room[2])
		if not kind in ["living", "work", "care", "lab", "social", "plant"] or r.size.x < 40.0 or r.size.y < 40.0:
			continue
		var n := 2 if r.size.x > 120.0 else 1
		for j in n:
			var px := r.position.x + r.size.x * (j + 1.0) / (n + 1.0)
			var py := r.end.y - 6.0
			var p: Dictionary = pick[k] if k < pick.size() else {}          # 이름 있는 사람을 다 세우면 이름 없는 정착민
			_person(Vector2(px, py), p, k)
			k += 1
			if k >= maxi(pick.size(), 1) * 3:
				return


func _person(foot: Vector2, p: Dictionary, k: int) -> void:
	var skins: Array[Color] = [Color("f1c9a5"), Color("d9a77c"), Color("a8714a"), Color("7a4b2e")]
	var skin: Color = skins[k % 4]
	var role := String(p.get("role", ""))
	var body_c: Color = ROLE_COL.get(role, Color("6f7f8f"))
	var bob := sin(_t * 2.0 + k) * 1.2
	draw_line(foot + Vector2(-4, 0), foot + Vector2(-3, -12), INK, 2.0)
	draw_line(foot + Vector2(4, 0), foot + Vector2(3, -12), INK, 2.0)
	_round_rect(Rect2(foot + Vector2(-6, -28 + bob), Vector2(12, 18)), 5.0, body_c, INK, 1.0)
	draw_circle(foot + Vector2(0, -33 + bob), 5.5, skin)
	draw_arc(foot + Vector2(0, -33 + bob), 5.5, 0, TAU, 14, INK, 1.0)
	if not p.is_empty():
		var nm := String(p.get("name", ""))
		_text(foot + Vector2(-26, -42), nm, 11, INK, true)
		_people_drawn.append([nm, role])


## 흐름: 왼쪽에서 들어오고 오른쪽으로 나간다 — 관 위에 알갱이가 흐르고 하루 값이 붙는다
func _draw_flows(m: Dictionary, bound: Rect2, inner: Rect2) -> void:
	var ins: Array = []
	var outs: Array = []
	var rec: Variant = m.get("recipe")
	if rec is Dictionary:
		for k in (rec as Dictionary).get("in", {}):
			ins.append([String(k), float(rec["in"][k])])
		for k in (rec as Dictionary).get("out", {}):
			outs.append([String(k), float(rec["out"][k])])
	var prov: Dictionary = m.get("provides", {}) if m.get("provides") is Dictionary else {}
	if prov.has("housing"):
		var ppl := float(prov["housing"])
		ins.append(["o2_kg", ppl * float(sim.PER.get("o2_kg", 0.84))])
		ins.append(["water_kg", ppl * float(sim.PER.get("water_use_kg", 25.0))])
		ins.append(["food_kg", ppl * float(sim.PER.get("food_kg", 0.62))])
		outs.append(["co2_kg", ppl * float(sim.PER.get("co2_kg", 1.0))])
		outs.append(["wastewater_kg", ppl * float(sim.PER.get("water_use_kg", 25.0)) * 0.95])
	if float(m.get("power_kw", 0.0)) > 0.0:
		ins.append(["power", float(m["power_kw"])])
	if prov.has("generation_kw"):
		outs.append(["power", float(prov["generation_kw"])])
	if prov.has("heat_kw"):
		outs.append(["heat", float(prov["heat_kw"])])
	_pipes(ins, Vector2(inner.position.x + 8, 0), Vector2(bound.position.x, 0), bound, true)
	_pipes(outs, Vector2(bound.end.x, 0), Vector2(inner.end.x - 8, 0), bound, false)
	# 아래 설명
	var y := inner.end.y - 100.0
	draw_line(Vector2(inner.position.x, y - 12), Vector2(inner.end.x - 250, y - 12), INK.lightened(0.4), 1.0)
	_text(Vector2(inner.position.x + 4, y + 6), "들어옴 — %s" % _flow_list(ins), 14, INK, false, inner.size.x - 270)
	_text(Vector2(inner.position.x + 4, y + 28), "나감 — %s" % _flow_list(outs), 14, INK, false, inner.size.x - 270)
	var note := String(m.get("note", ""))
	if note != "":
		_text(Vector2(inner.position.x + 4, y + 52), note, 12, INK.lightened(0.25), false, inner.size.x - 270)


func _flow_list(list: Array) -> String:
	if list.is_empty():
		return "없음"
	var bits := PackedStringArray()
	for f in list:
		bits.append(_flow_label(String(f[0]), float(f[1])))
	return " · ".join(bits)


func _flow_label(key: String, v: float) -> String:
	if key == "power" or key == "heat":
		return "%s %s kW" % [String(FLOW_NAME.get(key, key)), Fmt.n(v)]
	if key == "parts":
		return "%s %s개/일" % [String(FLOW_NAME.get(key, key)), Fmt.n(v, 1)]
	if key.ends_with("_t"):
		return "%s %s t/일" % [String(FLOW_NAME.get(key, key)), Fmt.n(v, 1)]
	return "%s %s kg/일" % [String(FLOW_NAME.get(key, key)), Fmt.n(v, 1)]


func _pipes(list: Array, from: Vector2, to: Vector2, bound: Rect2, incoming: bool) -> void:
	var n := list.size()
	for i in n:
		var key := String(list[i][0])
		var col: Color = FLOW_COL.get(key, INK)
		var y := bound.position.y + bound.size.y * (i + 1.0) / (n + 1.0)
		var a := Vector2(from.x, y)
		var b := Vector2(to.x, y)
		var width := 3.0 if key == "power" else 7.0
		if key == "power":
			draw_dashed_line(a, b, col, width, 8.0)
		else:
			draw_line(a, b, col.darkened(0.35), width + 2.0)
			draw_line(a, b, col, width)
		var len := absf(b.x - a.x)
		var step := 26.0
		var off := fmod(_t * 40.0, step)
		var x := 0.0
		while x < len:
			var px := a.x + x + off if b.x > a.x else a.x - x - off
			if (b.x > a.x and px < b.x) or (b.x < a.x and px > b.x):
				draw_circle(Vector2(px, y), 2.6 if key != "power" else 2.0, col.lightened(0.55))
			x += step
		var tip := b if incoming else b
		var dir := 1.0 if b.x > a.x else -1.0
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-10 * dir, -7), tip + Vector2(-10 * dir, 7)]), col.darkened(0.2))
		var label := _flow_label(key, float(list[i][1]))
		_text(Vector2(minf(a.x, b.x) + 6, y - 10), label, 12, INK, true)


func _draw_title_block(inner: Rect2, t: Dictionary) -> void:
	var r := Rect2(Vector2(inner.end.x - 240, inner.end.y - 92), Vector2(240, 92))
	draw_rect(r, PAPER_2)
	draw_rect(r, INK, false, 1.5)
	draw_line(Vector2(r.position.x, r.position.y + 30), Vector2(r.end.x, r.position.y + 30), INK, 1.0)
	draw_line(Vector2(r.position.x, r.position.y + 60), Vector2(r.end.x, r.position.y + 60), INK, 1.0)
	_text(r.position + Vector2(8, 21), "시드 개척국 · 단면도", 14, INK, true)
	_text(r.position + Vector2(8, 51), "도면 SC-%s-%02d" % [GameData.family(mid).to_upper().left(10), int(sim.counts.get(mid, 0))], 12, INK)
	_text(r.position + Vector2(8, 81), "모양 %s · 방 %d · 사람 %d" % [String(t.get("shape", "")), _rooms.size(), _people_drawn.size()], 12, INK.lightened(0.2))
	# 오른쪽 위 둥근 도장
	var c := Vector2(inner.end.x - 300, inner.position.y + 40)
	draw_arc(c, 30, 0, TAU, 40, RUST, 2.0)
	draw_arc(c, 24, 0, TAU, 40, RUST, 1.0)
	_text(c + Vector2(-22, 5), "2061", 14, RUST, true)


## 시험용: 그린 방 이름과 사람 수
func summary() -> Dictionary:
	return {"rooms": _rooms.map(func(x): return String(x[1])), "people": _people_drawn.duplicate()}
