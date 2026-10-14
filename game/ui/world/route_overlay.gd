class_name RouteOverlay
extends RefCounted
## 3D 지도 위의 교통과 지구의 대도시 — 화면 위 2D로 그린다 (천체 뒤편은 감춘다).
##   노선: 천체 위의 대원 호 (땅길은 땅에 붙고, 하늘길·호퍼는 거리만큼 솟는다), 지구 우주항과 달 사이의 셔틀 길,
##     행성 사이 수송선의 전이 궤도 (가는 중인 배만). 대도시 항공편은 가늘고 옅게.
##   탈것: 지금 가는 중인 편마다 노선 위의 점 (비행기는 세모, 열차는 네모, 호퍼는 동그라미, 배는 마름모).
##   대도시: 지구가 화면에서 커지면 점과 이름 (누르면 그 도시 위로 날아간다).

const COLORS := {"ground": Color(1.0, 0.72, 0.35), "hop": Color(1.0, 0.52, 0.38), "air": Color(0.55, 0.85, 1.0),
	"ferry": Color(0.86, 0.95, 1.0), "ship": Color(0.82, 0.62, 1.0)}
const METRO_COL := Color(0.93, 0.9, 0.82)
const LABEL_FS := 12

var view: WorldView
var hi_line := ""             # 교통 탭에서 '보기'로 고른 노선 (잠깐 밝게)
var hi_until := 0.0


func _init(v: WorldView) -> void:
	view = v


func highlight(id: String) -> void:
	hi_line = id
	hi_until = view._clock + 8.0


func _hi(id: String) -> bool:
	return id == hi_line and view._clock < hi_until


static func _slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var om := acos(clampf(a.dot(b), -1.0, 1.0))
	if om < 1e-6:
		return a
	return ((a * sin((1.0 - t) * om) + b * sin(t * om)) / sin(om)).normalized()


## 천체 위 노선의 최고 높이 (km): 땅길 0, 호퍼는 거리의 6%, 하늘길은 2.5% (반지름의 4%까지)
static func arc_height(l: Dictionary, r: float) -> float:
	var km := float(l["km"])
	match String(l["kind"]):
		"hop":
			return km * 0.06
		"air":
			return clampf(km * 0.025, 1.0, r * 0.04)
	return 0.0


## 노선 위의 점 (태양 중심 km): 천체 위의 노선, t = 0(a) ~ 1(b)
func surface_point(l: Dictionary, info: Dictionary, t: float) -> PackedFloat64Array:
	var r: float = info["radius"]
	var d := _slerp(Transport.node_dir(l["a"]), Transport.node_dir(l["b"]), t)
	var h := arc_height(l, r) * 4.0 * t * (1.0 - t) + r * 0.0006
	return Astro.add3(info["center"], Astro.bmul(info["frame"], Astro.scale3(Astro.dvec(d), r + h)))


## 지구 우주항 → 달 고향의 셔틀 길 (옆으로 휜 2차 곡선)
func ferry_point(l: Dictionary, t: float) -> PackedFloat64Array:
	var pa := _node_pos(String(l["a"]))
	var pb := _node_pos(String(l["b"]))
	var mid := Astro.scale3(Astro.add3(pa, pb), 0.5)
	var span := Astro.sub3(pb, pa)
	var side := Astro.vec(span).cross(Vector3(0, 0, 1))
	if side.length_squared() < 1e-9:
		side = Vector3(1, 0, 0)
	var ctrl := Astro.add3(mid, Astro.dvec(side.normalized() * Astro.len3(span) * 0.18))
	var u := 1.0 - t
	return Astro.add3(Astro.add3(Astro.scale3(pa, u * u), Astro.scale3(ctrl, 2.0 * u * t)), Astro.scale3(pb, t * t))


## 노드(도시·대도시)의 지금 위치 (태양 중심 km, 땅 위)
func _node_pos(key: String) -> PackedFloat64Array:
	var info := view._info(Transport.node_body(key))
	var r: float = info["radius"]
	return Astro.add3(info["center"], Astro.bmul(info["frame"], Astro.scale3(Astro.dvec(Transport.node_dir(key)), r)))


## 행성 사이 전이 궤도 위의 점: 떠난 날의 출발 천체 → 닿는 날의 도착 천체, 황경은 순행으로, 거리는 매끄럽게
func ship_point(t_rec: Dictionary, t: float) -> PackedFloat64Array:
	var mgr := view.mgr
	var fb := Transport.window_body(Transport.node_body(String(t_rec["from"])))
	var tb := Transport.window_body(Transport.node_body(String(t_rec["to"])))
	var jd0 := Astro.jd_from_unix(float(mgr.start_unix) + float(t_rec["depart"]) * 3600.0)
	var jd1 := Astro.jd_from_unix(float(mgr.start_unix) + float(t_rec["arrive"]) * 3600.0)
	var a := Astro.position(fb, jd0)
	var b := Astro.position(tb, jd1)
	var ra := sqrt(a[0] * a[0] + a[1] * a[1])
	var rb := sqrt(b[0] * b[0] + b[1] * b[1])
	var th0 := atan2(a[1], a[0])
	var dth := fposmod(atan2(b[1], b[0]) - th0, TAU)
	if dth < 0.3:
		dth += TAU
	var s := 0.5 - 0.5 * cos(PI * t)
	var rr := lerpf(ra, rb, s)
	var th := th0 + dth * t
	return Astro.v3(rr * cos(th), rr * sin(th), lerpf(a[2], b[2], t))


## 카메라에서 p로 가는 시선이 천체(중심 c, 반지름 r)에 먼저 닿나
func _behind(c: PackedFloat64Array, r: float, p: PackedFloat64Array) -> bool:
	var cam_p := view.cam.pos
	var dvec := Astro.sub3(p, cam_p)
	var dl := Astro.len3(dvec)
	if dl <= 0.0:
		return false
	var dn := Astro.scale3(dvec, 1.0 / dl)
	var oc := Astro.sub3(cam_p, c)
	var bq := Astro.dot3(oc, dn)
	var cq := Astro.dot3(oc, oc) - r * r
	var disc := bq * bq - cq
	if disc < 0.0:
		return false
	var tt := -bq - sqrt(disc)
	return tt > 0.0 and tt < dl - r * 2e-4


func _screen(p: PackedFloat64Array) -> Variant:
	return view.screen_of(view.to_render(p))


## 이 천체 위의 노선을 그릴 만큼 보이나 (0~1): 천체가 화면에서 작으면, 또는 땅에 아주 가까우면 흐리게
func _body_alpha(body: String) -> float:
	var info := view._info(body)
	if info.is_empty():
		return 0.0
	var rad_px := view._apparent_px(info["center"], info["radius"])
	var alt := Astro.len3(Astro.sub3(view.cam.pos, info["center"])) - float(info["radius"])
	return smoothstep(26.0, 70.0, rad_px) * smoothstep(25.0, 140.0, alt)


# ── 노선 ────────────────────────────────────────────────────────
func draw_lines() -> void:
	var mgr := view.mgr
	if mgr == null:
		return
	var tr := mgr.transport
	var hour_f := float(mgr.hour) + view.hour_frac
	var alphas := {}
	for l in tr.lines:
		var kind := String(l["kind"])
		var hot := _hi(l["id"])
		var col: Color = COLORS.get(kind, Color.WHITE)
		var base_a := 0.85 if l["role"] in ["local", "shuttle"] else (0.26 if l["role"] == "feeder" else 0.18)
		var width := 2.0 if l["role"] in ["local", "shuttle"] else 1.0
		if not l["on"] or not tr.enabled:
			base_a *= 0.3
		if hot:
			base_a = 1.0
			width = 3.2
			col = col.lightened(0.25)
		if kind == "ship":
			continue
		if kind == "ferry":
			var ea := _ferry_alpha()
			if ea > 0.02:
				_polyline(func(t): return ferry_point(l, t), 48, col, base_a * ea, width, [])
			continue
		var body := String(l["body"])
		if not alphas.has(body):
			alphas[body] = _body_alpha(body)
		var a: float = alphas[body]
		if a < 0.02 and not hot:
			continue
		var info := view._info(body)
		var n := clampi(int(float(l["km"]) / 120.0) + 8, 8, 64)
		_polyline(func(t): return surface_point(l, info, t), n, col, base_a * maxf(a, 0.6 if hot else 0.0), width,
			[info["center"], info["radius"]])
	# 가는 중인 탈것
	for t_rec in tr.trips:
		var l2 := tr.line_by_id(String(t_rec["line"]))
		if l2.is_empty():
			continue
		_draw_vehicle(l2, t_rec, hour_f, alphas)


## t(0~1)의 점 함수를 화면 선으로. 천체(occ = [중심, 반지름]) 뒤편과 카메라 뒤는 끊는다
func _polyline(f: Callable, n: int, col: Color, alpha: float, width: float, occ: Array) -> void:
	var ov := view._overlay
	var pts := PackedVector2Array()
	var c := Color(col, alpha)
	for i in n + 1:
		var p: PackedFloat64Array = f.call(float(i) / n)
		var sp: Variant = null
		if occ.is_empty() or not _behind(occ[0], float(occ[1]) * 0.999, p):
			sp = _screen(p)
		if sp == null:
			if pts.size() >= 2:
				ov.draw_polyline(pts, c, width, true)
			pts.clear()
			continue
		pts.append(sp)
	if pts.size() >= 2:
		ov.draw_polyline(pts, c, width, true)


## 지구-달 셔틀 길이 보일 만큼 (지구·달을 함께 볼 때)
func _ferry_alpha() -> float:
	var e := view._info("earth")
	var d := Astro.len3(Astro.sub3(view.cam.pos, e["center"]))
	return smoothstep(2.5e4, 9.0e4, d) * (1.0 - smoothstep(4.0e6, 3.0e7, d))


func _ship_alpha() -> float:
	var e := view._info("earth")
	var d := Astro.len3(Astro.sub3(view.cam.pos, e["center"]))
	return smoothstep(4.0e6, 4.0e7, d)


## 탈것 하나: 싣고 내리는 시간을 빼고 노선 위를 간다
func _draw_vehicle(l: Dictionary, t_rec: Dictionary, hour_f: float, alphas: Dictionary) -> void:
	var span := maxf(1.0, float(t_rec["arrive"]) - float(t_rec["depart"]))
	var load_h := float(Transport.mode(l["mode"]).get("load_h", 1)) if l["kind"] != "ship" else 0.0
	load_h = minf(load_h, span * 0.5)
	var k := clampf((hour_f - float(t_rec["depart"]) - load_h * 0.5) / maxf(span - load_h, 0.5), 0.0, 1.0)
	var fwd := String(t_rec["from"]) == String(l["a"])
	var kk := k if fwd else 1.0 - k
	var kind := String(l["kind"])
	var col: Color = COLORS.get(kind, Color.WHITE)
	var p: PackedFloat64Array
	var p2: PackedFloat64Array
	var alpha := 1.0
	var step := 0.01 if fwd else -0.01
	match kind:
		"ship":
			alpha = _ship_alpha()
			if alpha < 0.02:
				return
			# 배의 길도 함께 (가는 중인 배만)
			_polyline(func(t): return ship_point(t_rec, t), 64, col, 0.5 * alpha, 1.4, [])
			p = ship_point(t_rec, k)
			p2 = ship_point(t_rec, minf(k + 0.01, 1.0))
		"ferry":
			alpha = _ferry_alpha()
			if alpha < 0.02:
				return
			p = ferry_point(l, kk)
			p2 = ferry_point(l, clampf(kk + step, 0.0, 1.0))
		_:
			var body := String(l["body"])
			alpha = float(alphas.get(body, _body_alpha(body)))
			if alpha < 0.02:
				return
			var info := view._info(body)
			p = surface_point(l, info, kk)
			if _behind(info["center"], float(info["radius"]) * 0.999, p):
				return
			p2 = surface_point(l, info, clampf(kk + step, 0.0, 1.0))
	var sp: Variant = _screen(p)
	if sp == null:
		return
	var s2: Vector2 = sp
	var sq: Variant = _screen(p2)
	var dir := Vector2.RIGHT
	if sq != null and (sq as Vector2).distance_to(s2) > 0.01:
		dir = ((sq as Vector2) - s2).normalized()
	if (kind in ["ship", "ferry"]) and k <= 0.0:
		return
	marker(view._overlay, s2, dir, kind, col, alpha * (1.0 if l["role"] in ["local", "shuttle", "ship"] else 0.75))


## 탈것 표시: 비행기 세모, 열차 네모, 호퍼 동그라미, 셔틀·배 마름모 (어두운 테두리)
static func marker(ov: Control, p: Vector2, dir: Vector2, kind: String, col: Color, alpha: float) -> void:
	if not (is_finite(p.x) and is_finite(p.y)) or dir.length() < 0.5:
		return
	var c := Color(col, alpha)
	var dark := Color(0, 0, 0, 0.6 * alpha)
	var side := Vector2(-dir.y, dir.x)
	match kind:
		"air":
			for pass_i in 2:
				var k := 1.25 if pass_i == 0 else 1.0
				var cc := dark if pass_i == 0 else c
				var tip := p + dir * 5.0 * k
				var back := p - dir * 1.6 * k
				_tri(ov, tip, p - dir * 3.2 * k + side * 2.8 * k, back, cc)
				_tri(ov, tip, back, p - dir * 3.2 * k - side * 2.8 * k, cc)
		"ground":
			ov.draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), dark)
			ov.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), c)
		"hop":
			ov.draw_circle(p, 4.0, dark)
			ov.draw_circle(p, 2.8, c)
		_:
			ov.draw_circle(p, 7.0, Color(col, 0.18 * alpha))
			for pass_i in 2:
				var k := 1.3 if pass_i == 0 else 1.0
				var cc := dark if pass_i == 0 else c
				_tri(ov, p + dir * 5.0 * k, p + side * 3.0 * k, p - side * 3.0 * k, cc)
				_tri(ov, p - dir * 5.0 * k, p - side * 3.0 * k, p + side * 3.0 * k, cc)


static func _tri(ov: Control, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	ov.draw_primitive(PackedVector2Array([a, b, c]), PackedColorArray([col, col, col]), PackedVector2Array())


# ── 지구의 대도시 ───────────────────────────────────────────────
## 점과 이름 (지구가 화면에서 크면). 식민지 이름표가 먼저 자리를 잡는다
func draw_metros(font: Font, placed: Array) -> void:
	Metros.load_all()
	var info := view._info("earth")
	if info.is_empty():
		return
	var c: PackedFloat64Array = info["center"]
	var r: float = info["radius"]
	var rad_px := view._apparent_px(c, r)
	var alpha := smoothstep(40.0, 110.0, rad_px)
	if alpha < 0.03:
		return
	var alt := Astro.len3(Astro.sub3(view.cam.pos, c)) - r
	var ov := view._overlay
	var show_pop := rad_px > 650.0
	for m in Metros.list:
		var p := Astro.add3(c, Astro.bmul(info["frame"], Astro.scale3(Astro.dvec(m["dir"]), r)))
		if _behind(c, r * 0.999, p):
			continue
		var sp: Variant = _screen(p)
		if sp == null:
			continue
		var pos2: Vector2 = sp
		if not Rect2(Vector2(-30, -30), view.size + Vector2(60, 60)).has_point(pos2):
			continue
		# 그 도시 위에 내려가면 (3D 시가지) 이름표를 거둔다
		var a := alpha
		var near_km := Metros.km_between(m["dir"], Astro.vec(view.cam.t_dir)) if view.cam.mode == "body" else 1e9
		if near_km < float(m.get("radius_km", 20.0)) * 2.0:
			a *= smoothstep(12.0, 45.0, alt)
		if a < 0.03:
			continue
		var id := "metro:" + String(m["key"])
		var hot := view._hover_label == id
		var col := Color(1.0, 0.86, 0.55) if hot else METRO_COL
		ov.draw_circle(pos2, 3.6, Color(0, 0, 0, 0.55 * a))
		ov.draw_circle(pos2, 2.4, Color(col, a))
		var text := String(m["name"])
		var sub := Metros.pop_text(m) if show_pop else ""
		var fs := LABEL_FS
		var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var ssize := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2) if sub != "" else Vector2.ZERO
		var off := Vector2(7, 4)
		var rect := Rect2(pos2 + Vector2(-5, -tsize.y + 2), Vector2(maxf(tsize.x, ssize.x) + off.x + 8, tsize.y + ssize.y + 4))
		var clash := false
		for other in placed:
			if (other as Rect2).intersects(rect):
				clash = true
				break
		if clash:
			continue
		placed.append(rect)
		ov.draw_string(font, pos2 + off + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75 * a))
		ov.draw_string(font, pos2 + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
		if sub != "":
			var at := pos2 + off + Vector2(0, ssize.y + 1)
			ov.draw_string(font, at + Vector2(1, 1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0, 0, 0, 0.7 * a))
			ov.draw_string(font, at, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, Color(0.8, 0.82, 0.86, 0.9 * a))
		view._labels.append([rect, id])

