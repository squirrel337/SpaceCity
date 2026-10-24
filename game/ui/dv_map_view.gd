class_name DvMapView
extends Control
## 항로 지도 — 태양계를 축척 대신 장소(노드)와 기동(선)으로 그린 Δv 지하철 지도 (자료 system_map.json, 함대 Fleet).
## 왼쪽 큰 화면의 '항로'. 노드의 깊이가 중력 우물이다: 전이 궤도는 위 줄, 저궤도·표면은 그 구간의 Δv만큼 아래로 내려간다.
## 지구–달 L1에서 행성마다의 전이로 선이 갈라진다 (가까운 행성의 선이 전이 줄에 가장 가깝게 — 선이 서로 엇갈리지 않는다).
## 선 곁의 숫자는 Δv(km/s — 내릴 때와 오를 때가 다르면 ↓·↑ 둘), 점선은 대기 제동·포획. 발사 창이 열린 항로는 청록, 고른 항로는 주황.
## 가는 중인 수송선은 길 위의 마름모, 부두에 머무는 배는 저궤도 곁의 작은 마름모. 노드·선을 누르면 오른쪽 카드에 자세히:
## 항로는 Δv·전이·다음 출항·지난 창·배·등급마다 한 번 건너는 값과 주문, 표면은 그 천체의 도시들(누르면 그 도시로)

signal colony_picked(index: int)
signal changed

const CARD_W := 350.0
const LANE_ORDER := ["titan", "callisto", "ceres", "mars"]      # 위에서 아래로 — 가까운 항로의 선이 전이 줄에 가장 가깝다
const BODY_COLOR := {"moon": Color("b9b5aa"), "earth": Color("5b9be0"), "mars": Color("d9774c"), "mercury": Color("a8a092"),
	"ceres": Color("948f86"), "callisto": Color("a38f70"), "titan": Color("d9a24c")}
const MIN_GAP := 30.0
const REFRESH_MS := 250

var mgr: Colonies
var active := -1                    # 고른 식민지 번호 (main이 넣는다 — 그 도시 이름을 밝게)
var selected := ""                  # 항로(천체 id) 또는 "n:<노드 id>"
var _pos := {}                      # 노드 id → 화면 자리
var _lane := {}                     # 항로 → 꺾은선 [L1, 꺾임, 꺾임, 전이]
var _map := Rect2()
var _card: PanelContainer
var _box: VBoxContainer
var _live: Array = []
var _sig := ""
var _last_ms := -100000


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.97), Palette.LINE, 10, 10))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	add_child(_card)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


## 처음 열 때: 고른 식민지의 천체 항로 (없으면 화성)
func open(body: String) -> void:
	if selected == "":
		selected = body if mgr != null and Fleet.routes(mgr).has(body) else "mars"
	_sig = ""
	_layout()
	refresh(true)


func refresh(force := false) -> void:
	if mgr == null or not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_ms < REFRESH_MS:
		return
	_last_ms = now
	var st := Fleet.state(mgr)
	var sig := "%s|%d|%d|%d|%d|%d" % [selected, (st["ships"] as Array).size(), (st["orders"] as Array).size(),
		mgr.known_techs().size(), mgr.list.size(), mgr.transport.lines.size()]
	if sig != _sig:
		_sig = sig
		_build_card()
	for f in _live:
		(f as Callable).call()
	queue_redraw()


# ── 자리 ────────────────────────────────────────────────────────
func _layout() -> void:
	if _card == null or size.x < 10.0:
		return
	var bottom_pad := 62.0                 # 왼쪽 아래 단추 줄
	var top := 62.0
	_map = Rect2(16, top, size.x - 32, maxf(size.y - top - bottom_pad, 160.0))
	var nodes: Array = Fleet.data().get("nodes", [])
	var cols := 7.0
	var lane_gap := 13.0
	var y0 := _map.position.y + 14.0
	var y_tr := y0 + lane_gap * 3.0 + 34.0
	var y_l1 := y_tr + 46.0
	var bottom := _map.end.y - 50.0             # 표면 아래 도시 이름 자리
	var k := maxf(minf((bottom - y_l1) / 13.2, (bottom - y_tr) / 10.6), 4.0)
	_pos.clear()
	for n in nodes:
		var id := String(n["id"])
		if String(n["kind"]) == "transfer":
			_pos[id] = Vector2(_x(float(n["col"]), cols), y_tr)
		elif id == "l1":
			_pos[id] = Vector2(_x(float(n["col"]), cols), y_l1)
	var edges: Array = Fleet.data().get("edges", [])
	for _pass in 4:
		for e in edges:
			var a := String(e["a"])
			var b := String(e["b"])
			if _is_lane(e) or not _pos.has(a) or _pos.has(b):
				continue
			var depth := maxf(float(e["dv"]), float(e.get("back", e["dv"])))
			_pos[b] = Vector2(_x(float(Fleet.node(b)["col"]), cols), (_pos[a] as Vector2).y + maxf(MIN_GAP, depth * k))
	_lane.clear()
	var l1: Vector2 = _pos.get("l1", Vector2.ZERO)
	for n in nodes:
		if String(n["kind"]) != "transfer":
			continue
		var r := String(n["body"])
		var idx := LANE_ORDER.find(r)
		var yl := y0 + lane_gap * float(idx if idx >= 0 else 3)
		var t: Vector2 = _pos[String(n["id"])]
		_lane[r] = PackedVector2Array([l1, Vector2(l1.x, yl), Vector2(t.x, yl), t])
	# 카드: 오른쪽 아래 — 바깥 행성들(세레스·목성·토성)의 우물은 얕아 그 아래가 빈다. 좁으면 아래에 가로로 길게
	var free_top := _map.position.y + 120.0
	for n in nodes:
		if float(n["col"]) >= 4.0 and _pos.has(String(n["id"])):
			free_top = maxf(free_top, (_pos[String(n["id"])] as Vector2).y + 66.0)
	var cw := clampf(size.x * 0.46, 300.0, 400.0)
	if size.x < 640.0 or size.y - free_top - 12.0 < 170.0:
		var ch := clampf(size.y * 0.4, 170.0, 420.0)
		_card.position = Vector2(12, size.y - ch - bottom_pad)
		_card.size = Vector2(size.x - 24, ch)
	else:
		_card.position = Vector2(size.x - cw - 12, free_top)
		_card.size = Vector2(cw, size.y - free_top - 12)


## 카드 위쪽 끝 (main이 알림을 그 위로 올린다)
func card_top() -> float:
	return _card.position.y


func _x(col: float, cols: float) -> float:
	return _map.position.x + (col + 0.5) / cols * _map.size.x


static func _is_lane(e: Dictionary) -> bool:
	return String(e["a"]) == "l1" and String(Fleet.node(String(e["b"])).get("kind", "")) == "transfer"


## 세로 구간의 꺾은선: 같은 줄이면 곧게, 아니면 가로로 간 뒤 내려간다 (L1 → 지구·달 저궤도)
func _edge_points(e: Dictionary) -> PackedVector2Array:
	if _is_lane(e):
		var r := String(Fleet.node(String(e["b"]))["body"])
		return _lane.get(r, PackedVector2Array())
	var a: Vector2 = _pos.get(String(e["a"]), Vector2.ZERO)
	var b: Vector2 = _pos.get(String(e["b"]), Vector2.ZERO)
	if absf(a.x - b.x) < 1.0:
		return PackedVector2Array([a, b])
	return PackedVector2Array([a, Vector2(b.x, a.y), b])


## 고향 부두 → 항로의 부두 길 (수송선이 그 위를 간다)
func _ship_path(route: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pb := Fleet.port_body(mgr)
	var pd := Fleet.dock(pb)
	if not _pos.has(pd) or not _lane.has(route):
		return out
	var p0: Vector2 = _pos[pd]
	var l1: Vector2 = _pos["l1"]
	out.append(p0)
	out.append(Vector2(p0.x, l1.y))
	out.append_array(_lane[route])
	out.append(_pos.get(Fleet.dock(route), (_lane[route] as PackedVector2Array)[-1]))
	return out


static func _along(pts: PackedVector2Array, k: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := clampf(k, 0.0, 1.0) * total
	for i in range(1, pts.size()):
		var d := pts[i - 1].distance_to(pts[i])
		if want <= d:
			return pts[i - 1].lerp(pts[i], want / maxf(d, 1e-6))
		want -= d
	return pts[-1]


# ── 그리기 ──────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	if mgr == null or _pos.is_empty():
		return
	var font: Font = ThemeFactory.regular if ThemeFactory.regular else get_theme_default_font()
	var bold: Font = ThemeFactory.bold if ThemeFactory.bold else font
	draw_string(bold, Vector2(18, 30), "항로 지도 — Δv (km/s)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.TEXT)
	draw_string(font, Vector2(18, 50), "깊을수록 중력 우물이 깊다 · 선 곁의 숫자는 그 구간의 Δv · 점선은 대기 제동 · 청록 = 발사 창이 열린 항로",
		HORIZONTAL_ALIGNMENT_LEFT, maxf(_map.size.x, 200.0), 12, Palette.MUTED)
	var routes := Fleet.routes(mgr)
	var sel_route := selected if not selected.begins_with("n:") else ""
	var open := {}
	for r in _lane:
		var w := _window(String(r))
		open[r] = bool(w.get("open", false))
	# 우물: 저궤도에서 표면까지 옅은 띠
	for body in Fleet.data().get("dock", {}):
		var o: Vector2 = _pos.get(Fleet.dock(String(body)), Vector2.INF)
		var s: Vector2 = _pos.get(Fleet.surface(String(body)), Vector2.INF)
		if o == Vector2.INF or s == Vector2.INF:
			continue
		var c: Color = BODY_COLOR.get(body, Palette.MUTED)
		draw_rect(Rect2(Vector2(s.x - 15, o.y), Vector2(30, s.y - o.y + 6)), Color(c, 0.07))
	# 선
	for e in Fleet.data().get("edges", []):
		var pts := _edge_points(e)
		if pts.size() < 2:
			continue
		var r := String(Fleet.node(String(e["b"]))["body"])
		var on_sel := sel_route != "" and r == sel_route
		var col := Color(Palette.MUTED, 0.55)
		var w := 3.0
		if _is_lane(e) and bool(open.get(r, false)):
			col = Palette.TEAL
		if on_sel:
			col = Palette.AMBER
			w = 4.0
		if not routes.has(r) and _is_lane(e):
			col = Color(Palette.DIM, 0.6)
		var aero := String(e.get("aero", "")) != ""
		for i in range(1, pts.size()):
			if aero:
				draw_dashed_line(pts[i - 1], pts[i], col, w, 7.0)
			else:
				draw_line(pts[i - 1], pts[i], col, w, true)
		_edge_label(e, pts, font)
	# 가는 중인 배
	var st := Fleet.state(mgr)
	var pb := Fleet.port_body(mgr)
	for sh in st["ships"]:
		if String(sh["at"]) != "":
			continue
		var t := Fleet.trip_of(mgr, int(sh["id"]))
		var route := String(sh["route"])
		var path := _ship_path(route)
		if t.is_empty() or path.size() < 2:
			continue
		var kk := clampf((float(mgr.hour) - float(t["depart"])) / maxf(1.0, float(t["arrive"]) - float(t["depart"])), 0.0, 1.0)
		var outbound := Transport.node_body(String(t["from"])) == pb
		var p := _along(path, kk if outbound else 1.0 - kk)
		_diamond(p, 7.0, Palette.BLUE)
		draw_string(font, p + Vector2(10, -8), String(sh["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT)
	# 노드
	for n in Fleet.data().get("nodes", []):
		var id := String(n["id"])
		var p2: Vector2 = _pos.get(id, Vector2.INF)
		if p2 == Vector2.INF:
			continue
		var kind := String(n["kind"])
		var body := String(n["body"])
		var c2: Color = BODY_COLOR.get(body, Palette.TEXT)
		var picked := selected == "n:" + id or (sel_route != "" and body == sel_route and kind != "surface")
		match kind:
			"hub":
				_diamond(p2, 10.0, Palette.AMBER)
			"transfer":
				draw_circle(p2, 7.0, Palette.BG)
				draw_arc(p2, 7.0, 0.0, TAU, 20, Palette.TEAL if bool(open.get(body, false)) else Palette.TEXT, 2.0, true)
			"orbit":
				draw_circle(p2, 7.0, Palette.PANEL_2)
				draw_arc(p2, 7.0, 0.0, TAU, 20, c2, 2.5, true)
			_:
				draw_circle(p2, 9.0, c2)
				draw_arc(p2, 9.0, 0.0, TAU, 20, Palette.PANEL_2, 2.0, true)
		if picked:
			draw_arc(p2, 13.0, 0.0, TAU, 24, Palette.AMBER, 2.0, true)
		var label := String(n["name"])
		if kind == "hub":
			draw_string(font, p2 + Vector2(-40, 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT)
			draw_string(font, p2 + Vector2(-40, 40), "연료 기지 — 시대 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.DIM)
			continue
		draw_string(font, p2 + Vector2(12, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.TEXT if kind != "transfer" else Palette.MUTED)
		if kind == "transfer":
			var w2 := _window(body)
			if not w2.is_empty():
				var left := int(ceil(float(w2["start"]) - mgr.hour / 24.0))
				var txt := "발사 창 열림" if bool(w2["open"]) else "창 D-%d" % maxi(left, 0)
				draw_string(font, p2 + Vector2(10, -9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Palette.TEAL if bool(w2["open"]) else Palette.DIM)
		elif kind == "orbit":
			# 부두에 머무는 배 — 이름 뒤에 작은 마름모
			var here := (st["ships"] as Array).filter(func(sh): return String(sh["at"]) == body)
			var x0 := p2.x + 12.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 9.0
			for i in mini(here.size(), 4):
				_diamond(Vector2(x0 + 11.0 * i, p2.y), 4.5, Palette.BLUE if String(here[i]["route"]) != "" else Palette.MUTED)
			if here.size() > 4:
				draw_string(font, Vector2(x0 + 44.0, p2.y + 4.0), "+%d" % (here.size() - 4), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
		elif kind == "surface":
			# 그 천체의 도시들
			var y := p2.y + 24.0
			var shown := 0
			for i in mgr.list.size():
				var c: Dictionary = mgr.list[i]
				if String(c["body"]) != body:
					continue
				if shown >= 3:
					draw_string(font, Vector2(p2.x - 40, y), "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
					break
				var pop := int((c["sim"] as CitySim).population())
				draw_string(font, Vector2(p2.x - 40, y), "%s %s명" % [String(c.get("short", c["name"])), Fmt.n(float(pop))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT if i == active else Palette.MUTED)
				y += 14.0
				shown += 1


func _diamond(p: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, c)
	pts.append(pts[0])
	draw_polyline(pts, Palette.BG, 1.5, true)


## 구간의 Δv 글: 내릴 때·오를 때가 다르면 "↓0.7 ↑4.1". 갈래 선은 꺾이기 전 가로 줄 위에, 세로 선은 그 왼쪽에
func _edge_label(e: Dictionary, pts: PackedVector2Array, font: Font) -> void:
	var dv := float(e["dv"])
	var back := float(e.get("back", dv))
	var txt := Fmt.n(dv, 1) if absf(dv - back) < 0.05 else "↓%s ↑%s" % [Fmt.n(dv, 1), Fmt.n(back, 1)]
	var col := Palette.AMBER.lerp(Palette.TEXT, 0.35)
	if _is_lane(e):
		var right := pts[2].x >= pts[1].x
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var x := pts[2].x - w - 6.0 if right else pts[2].x + 6.0
		draw_string(font, Vector2(x, pts[2].y - 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		return
	var a := pts[-2]
	var b := pts[-1]
	var y := a.y + clampf((b.y - a.y) * 0.5, 12.0, 60.0)          # 긴 선(지구 우물)은 위쪽에 — 옆 줄의 이름과 겹치지 않게
	draw_string(font, Vector2(b.x - 78.0, y + 4.0), txt, HORIZONTAL_ALIGNMENT_RIGHT, 70, 11, col)


## 그 천체로 가는 발사 창 (고향 쪽에서) — {} = 없다
func _window(body: String) -> Dictionary:
	var s := Transport._site_with_transfer(body)
	if s.is_empty():
		return {}
	return mgr.window(String(s["id"]))


# ── 누르기 ──────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	var p := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		p = (event as InputEventScreenTouch).position
	if p == Vector2.INF:
		return
	var pick := hit(p)
	if pick != "":
		selected = pick
		_sig = ""
		refresh(true)
		accept_event()


## 그 자리에서 고를 것 (항로 천체 또는 "n:<노드>", 없으면 "")
func hit(p: Vector2) -> String:
	var best := ""
	var best_d := 22.0
	for id in _pos:
		var d := p.distance_to(_pos[id])
		if d < best_d:
			best_d = d
			best = String(id)
	if best != "":
		var n := Fleet.node(best)
		var body := String(n["body"])
		match String(n["kind"]):
			"transfer":
				return body
			"orbit":
				return body if Fleet.routes(mgr).has(body) else "n:" + best
			_:
				return "n:" + best
	for r in _lane:
		var pts: PackedVector2Array = _lane[r]
		for i in range(1, pts.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
			if q.distance_to(p) < 9.0:
				return String(r)
	return ""


# ── 카드 ────────────────────────────────────────────────────────
func _build_card() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_live.clear()
	if selected.begins_with("n:"):
		_node_card(selected.substr(2))
	else:
		_route_card(selected)


func _label(text: String, size_px := 13, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	_box.add_child(l)
	return l


func _route_card(r: String) -> void:
	var pb := Fleet.port_body(mgr)
	var l := Fleet.line_of(mgr, r)
	_box.add_child(ThemeFactory.heading("%s 항로" % Fleet.body_name(r), 17))
	var out_dv := Fleet.route_dv(pb, r)
	var back_dv := Fleet.route_dv(r, pb)
	var up := Fleet.edge_dv(Fleet.surface(r), Fleet.dock(r))
	var down := Fleet.edge_dv(Fleet.dock(r), Fleet.surface(r))
	_label("고향 부두(%s) ↔ %s · Δv 갈 때 %s · 올 때 %s km/s · 호만 전이 %s일. 표면 ↔ 궤도는 착륙선이 오간다 (오를 때 %s · 내릴 때 %s)." % [
		Fleet.dock_name(pb), Fleet.dock_name(r), Fmt.n(out_dv, 1), Fmt.n(back_dv, 1), Fmt.n(Transport._transfer_days(r)),
		Fmt.n(up, 1), Fmt.n(down, 1)], 12, Palette.MUTED)
	if l.is_empty():
		_label("이 항로를 잇는 수송선 노선이 없다 — 그 천체에 도시가 생기면 열린다.", 13, Palette.AMBER)
	else:
		var when := _label("", 13)
		var last := _label("", 12, Palette.MUTED)
		_live.append(func():
			var n0 := int(l["next"][0])
			var n1 := int(l["next"][1])
			when.text = "다음 출항 — 고향 → %s: %s (D-%d) · %s → 고향: %s (D-%d)" % [Fleet.body_name(r), mgr.date_text(float(n0)),
				maxi(0, int(ceil((n0 - mgr.hour) / 24.0))), Fleet.body_name(r), mgr.date_text(float(n1)), maxi(0, int(ceil((n1 - mgr.hour) / 24.0)))]
			var s: Variant = (Fleet.state(mgr)["status"] as Dictionary).get(r)
			last.text = ("지난 창 (%s): %s" % [mgr.date_text(float(s[0])), String(s[1])]) if s is Array else "아직 이 항로의 창이 지나지 않았다")
	# 배
	_box.add_child(HSeparator.new())
	var ships := Fleet.ships_of(mgr, r)
	_box.add_child(ThemeFactory.heading("배 %d척" % ships.size(), 14))
	for sh in ships:
		var lab := _label("", 12)
		var ship_ref: Dictionary = sh
		_live.append(func(): lab.text = "◆ " + Fleet.ship_text(mgr, ship_ref))
	for o in Fleet.state(mgr)["orders"]:
		if String(o["route"]) == r:
			_label("◇ %s · %s · %s 완성 (주문)" % [String(o["name"]), Fleet.cls_name(String(o["cls"])), mgr.date_text(float(o["ready"]))],
				12, Palette.MUTED)
	if ships.is_empty():
		_label("배가 없다 — 이 항로의 수송선은 떠나지 못한다.", 12, Palette.AMBER)
	# 등급마다
	_box.add_child(HSeparator.new())
	var typ := float(Fleet.data().get("auto", {}).get("typical_t", 10))
	_box.add_child(ThemeFactory.heading("등급마다 한 번 건너는 값 (화물 %s t)" % Fmt.n(typ), 14))
	var known := mgr.known_techs()
	var best := Fleet.best_class(mgr, r, known)
	var ps := Fleet.port_sim(mgr)
	var hub := Fleet.hub_sim(mgr, r)
	for c_id in Fleet.data().get("classes", {}):
		var c := Fleet.cls(String(c_id))
		var a := Fleet.trip(mgr, String(c_id), pb, r, typ, 0, ps, known)
		var b := Fleet.trip(mgr, String(c_id), r, pb, typ, 0, hub, known)
		var head := _label("%s%s — 비추력 %d s · 빈 배 %d t · 자리 %d · %s" % [Fleet.cls_name(String(c_id)), " ★" if String(c_id) == best else "",
			int(c["isp"]), int(c["dry_t"]), int(c["seats"]), String(c["prop"])], 13)
		head.add_theme_font_override("font", ThemeFactory.bold)
		_label("갈 때 추진제 %s t · 지원 %s%s / 올 때 %s t · 지원 %s%s · 전이 %s일" % [Fmt.n(float(a["prop_t"])), Fmt.n(float(a["cost"])),
			" (현지)" if bool(a["local"]) else "", Fmt.n(float(b["prop_t"])), Fmt.n(float(b["cost"])), " (현지)" if bool(b["local"]) else "",
			Fmt.n(Fleet.route_days(r, String(c_id)))], 12, Palette.MUTED)
		var why := Fleet.order_reason(mgr, String(c_id), r)
		var btn := Button.new()
		btn.text = "주문 — %s" % Fleet.cost_text(Fleet.order_cost(mgr, String(c_id), known))
		btn.custom_minimum_size = Vector2(0, 40 if OS.has_feature("mobile") else 32)
		btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = why != ""
		btn.tooltip_text = why if why != "" else String(c.get("text", ""))
		var cid := String(c_id)
		btn.pressed.connect(func():
			var w := Fleet.order(mgr, cid, r)
			if w == "":
				changed.emit()
			_sig = ""
			refresh(true))
		_box.add_child(btn)
		if why != "" and why.ends_with("있어야 한다"):
			_label(why, 11, Palette.AMBER)
	_box.add_child(HSeparator.new())
	var auto := CheckBox.new()
	auto.text = "함대 자동 운영 — 항로마다 배 둘 (★ 등급으로 주문)"
	auto.button_pressed = bool(Fleet.state(mgr).get("auto", true))
	auto.toggled.connect(func(on: bool):
		Fleet.state(mgr)["auto"] = on
		changed.emit())
	_box.add_child(auto)


func _node_card(id: String) -> void:
	var n := Fleet.node(id)
	var body := String(n.get("body", ""))
	_box.add_child(ThemeFactory.heading(String(n.get("name", id)), 17))
	match String(n.get("kind", "")):
		"hub":
			_label("지구와 달 사이의 균형점. 행성으로 가는 전이가 여기서 갈라진다 — 지구 가까이 내려가 엔진을 켜면 (오베르트 효과) 화성 전이까지 1.0 km/s. " +
				"시대 1에 달의 물로 만든 추진제를 쌓는 연료 기지가 들어선다.", 13, Palette.MUTED)
		"orbit":
			_label("%s의 저궤도 — 행성간 함선이 머무는 부두. 표면까지는 착륙선이 오간다 (오를 때 %s · 내릴 때 %s km/s)." % [Fleet.body_name(body),
				Fmt.n(Fleet.edge_dv(Fleet.surface(body), id), 1), Fmt.n(Fleet.edge_dv(id, Fleet.surface(body)), 1)], 13, Palette.MUTED)
			if body == "earth":
				_label("지구 우주항(나로)과 달 고향 사이는 지구-달 셔틀이 오간다 — 교통 탭.", 12, Palette.MUTED)
		_:
			var up := Fleet.edge_dv(id, Fleet.dock(body))
			var down := Fleet.edge_dv(Fleet.dock(body), id)
			_label("궤도까지 오를 때 %s · 내릴 때 %s km/s%s" % [Fmt.n(up, 1), Fmt.n(down, 1), " (대기 제동)" if down < up - 0.05 else ""],
				13, Palette.MUTED)
	if body != "":
		var any := false
		for i in mgr.list.size():
			var c: Dictionary = mgr.list[i]
			if String(c["body"]) != body:
				continue
			any = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var lab := Label.new()
			lab.text = "%s · %s명" % [String(c["name"]), Fmt.n((c["sim"] as CitySim).population())]
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.add_theme_font_size_override("font_size", 13)
			row.add_child(lab)
			var go := Button.new()
			go.text = "그 도시로"
			go.custom_minimum_size = Vector2(0, 40 if OS.has_feature("mobile") else 32)
			var idx := i
			go.pressed.connect(func(): colony_picked.emit(idx))
			row.add_child(go)
			_box.add_child(row)
		if not any and String(n.get("kind", "")) == "surface":
			_label("아직 도시가 없다 — 개척 탭에서 원정대를 보낸다.", 12, Palette.MUTED)
		if Fleet.routes(mgr).has(body):
			var rb := Button.new()
			rb.text = "%s 항로 보기" % Fleet.body_name(body)
			rb.custom_minimum_size = Vector2(0, 40 if OS.has_feature("mobile") else 32)
			rb.pressed.connect(func():
				selected = body
				_sig = ""
				refresh(true))
			_box.add_child(rb)
