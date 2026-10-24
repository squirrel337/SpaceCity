class_name StatsChart
extends Control
## 통계 탭의 선 그래프 하나 — 한 가지 단위의 값 몇 줄을 날짜 축 하나에 (축은 하나뿐: 단위가 다르면 그래프를 나눈다).
## 범주 색은 정해진 순서로만 쓴다 (SERIES — 어두운 판에서 검증한 여덟 색). 줄이 둘 이상이면 범례를 붙이고, 글은 글자 색으로만 쓴다.
## 가리키면 (마우스·터치) 그 날의 세로선과 값 읽기가 보이고, 같은 통계의 다른 그래프도 같은 날을 가리킨다 (hovered 신호)

signal hovered(day: int)            # 가리키는 날 (-1: 놓았다)

## 범주 색 (자리 순서 — 파랑·주황·청록·노랑·자홍·초록·보라·빨강). 어두운 판(#1d2330)에서 인접 쌍 CVD ΔE 8.4 이상
const SERIES := [Color("3987e5"), Color("d95926"), Color("199e70"), Color("c98500"), Color("d55181"), Color("008300"),
	Color("9085e9"), Color("e66767")]
const PAD_L := 46.0
const PAD_R := 10.0
const PAD_T := 26.0                  # 제목 줄 (범례가 넘치면 줄마다 LEGEND_H씩 더)
const LEGEND_H := 15.0
const PAD_B := 20.0

var title := ""
var unit := ""                       # 값 뒤에 붙일 단위 ("명", "%" …)
var lines: Array = []                # [{name, days: PackedInt32Array, values: PackedFloat32Array, color}]
var y_min: Variant = null            # 고정 범위 (없으면 값에서)
var y_max: Variant = null
var step := false                    # 계단 (기술 수처럼 정수로 오르는 값)
var hover_day := -1
var _x0 := 0
var _x1 := 1


func _init() -> void:
	custom_minimum_size = Vector2(0, 168)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func(): hovered.emit(-1))


## 그릴 값을 정한다: x 범위(날)는 [from, to]
func set_data(p_title: String, p_lines: Array, from_day: int, to_day: int) -> void:
	title = p_title
	lines = p_lines
	_x0 = from_day
	_x1 = maxi(to_day, from_day + 1)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventMouseMotion:
		pos = (event as InputEventMouseMotion).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	if pos == Vector2.INF:
		return
	var w := size.x - PAD_L - PAD_R
	if w <= 1.0:
		return
	var f := clampf((pos.x - PAD_L) / w, 0.0, 1.0)
	hovered.emit(int(round(lerpf(_x0, _x1, f))))


func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for l in lines:
		var days: PackedInt32Array = l["days"]
		var vals: PackedFloat32Array = l["values"]
		for i in vals.size():
			if days[i] < _x0 or days[i] > _x1:
				continue
			lo = minf(lo, vals[i])
			hi = maxf(hi, vals[i])
	if lo == INF:
		lo = 0.0
		hi = 1.0
	if y_min != null:
		lo = float(y_min)
	else:
		lo = minf(lo, 0.0) if lo >= 0.0 and lo < hi * 0.35 else lo
	if y_max != null:
		hi = float(y_max)
	if hi - lo < 1e-6:
		hi = lo + 1.0
	return Vector2(lo, hi)


## 눈금: 1·2·5 × 10ⁿ 가운데 서너 칸이 되는 것
static func _ticks(lo: float, hi: float) -> Array:
	var span := hi - lo
	var raw := span / 3.0
	var mag := pow(10.0, floor(log(raw) / log(10.0)))
	var stp := mag
	for k in [1.0, 2.0, 5.0, 10.0]:
		if mag * k >= raw:
			stp = mag * k
			break
	var out: Array = []
	var v: float = ceil(lo / stp) * stp
	while v <= hi + stp * 1e-6:
		out.append(v)
		v += stp
	return out


static func _num(v: float) -> String:
	if absf(v) >= 1000.0:
		return Fmt.n(v)
	if absf(v - round(v)) < 1e-6:
		return str(int(round(v)))
	return str(snappedf(v, 0.1))


func _draw() -> void:
	var font: Font = ThemeFactory.regular if ThemeFactory.regular else get_theme_default_font()
	var bold: Font = ThemeFactory.bold if ThemeFactory.bold else font
	# 제목과 범례 (줄이 둘 이상일 때 — 색은 표시에만, 글은 글자 색). 범례가 넘치면 다음 줄로
	draw_string(bold, Vector2(2, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)
	var lx := 8.0 + bold.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
	var ly := 0.0
	if lines.size() >= 2:
		for l in lines:
			var name := String(l["name"])
			var lw := 26.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			if lx + lw > size.x - 4.0 and lx > 60.0:
				lx = 2.0
				ly += LEGEND_H
			draw_rect(Rect2(Vector2(lx, 6 + ly), Vector2(14, 3)), l["color"])
			draw_string(font, Vector2(lx + 18, 15 + ly), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MUTED)
			lx += lw
	var top := PAD_T + ly
	var w := size.x - PAD_L - PAD_R
	var h := size.y - top - PAD_B
	if w <= 10.0 or h <= 10.0:
		return
	var r := _range()
	var to_px := func(day: float, v: float) -> Vector2:
		return Vector2(PAD_L + (day - _x0) / float(_x1 - _x0) * w, top + h - (v - r.x) / (r.y - r.x) * h)
	# 눈금 (옅게) — 값 글은 왼쪽
	for t in _ticks(r.x, r.y):
		var y: float = (to_px.call(_x0, t) as Vector2).y
		draw_line(Vector2(PAD_L, y), Vector2(PAD_L + w, y), Color(Palette.LINE, 0.9), 1.0)
		draw_string(font, Vector2(0, y + 4), _num(t), HORIZONTAL_ALIGNMENT_RIGHT, PAD_L - 6, 10, Palette.DIM)
	draw_string(font, Vector2(PAD_L, size.y - 4), "%d일" % _x0, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.DIM)
	draw_string(font, Vector2(PAD_L + w - 60, size.y - 4), "%d일" % _x1, HORIZONTAL_ALIGNMENT_RIGHT, 60, 10, Palette.DIM)
	# 줄 (2 px, 화면 너비만큼만 — 하루가 한 점보다 촘촘하면 건너뛴다)
	for l in lines:
		var days: PackedInt32Array = l["days"]
		var vals: PackedFloat32Array = l["values"]
		var pts := PackedVector2Array()
		var stride := maxi(1, int(ceil(float(_x1 - _x0) / maxf(w, 1.0))))
		var last_x := -INF
		for i in vals.size():
			if days[i] < _x0 or days[i] > _x1:
				continue
			if i % stride != 0 and i != vals.size() - 1:
				continue
			var p: Vector2 = to_px.call(float(days[i]), vals[i])
			if step and not pts.is_empty():
				pts.append(Vector2(p.x, pts[-1].y))
			if p.x - last_x >= 0.5 or i == vals.size() - 1:
				pts.append(p)
				last_x = p.x
		if pts.size() >= 2:
			draw_polyline(pts, l["color"], 2.0, true)
		elif pts.size() == 1:
			draw_circle(pts[0], 3.0, l["color"])
	# 가리키는 날: 세로선과 값 읽기 (오른쪽 위)
	if hover_day >= _x0 and hover_day <= _x1:
		var hx: float = (to_px.call(float(hover_day), r.x) as Vector2).x
		draw_line(Vector2(hx, top), Vector2(hx, top + h), Color(Palette.TEXT, 0.5), 1.0)
		var parts := PackedStringArray(["%d일" % hover_day])
		for l in lines:
			var v: Variant = value_at(l, hover_day)
			if v == null:
				continue
			draw_circle(to_px.call(float(hover_day), float(v)), 4.0, l["color"])
			draw_arc(to_px.call(float(hover_day), float(v)), 4.0, 0.0, TAU, 16, Palette.PANEL_2, 2.0)   # 겹치는 표시의 테
			parts.append("%s %s%s" % [String(l["name"]), _num(float(v)), unit])
		var txt := " · ".join(parts)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var at := Vector2(clampf(hx + 8.0, PAD_L, size.x - tw - 8.0), top + 12.0)
		draw_rect(Rect2(at - Vector2(4, 11), Vector2(tw + 8, 15)), Color(Palette.PANEL, 0.92))
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT)


## 그 날의 값 (그날 기록이 없으면 그 앞의 마지막 값, 기록 전이면 null)
static func value_at(l: Dictionary, day: int) -> Variant:
	var days: PackedInt32Array = l["days"]
	var vals: PackedFloat32Array = l["values"]
	if days.is_empty() or day < days[0]:
		return null
	var i := days.bsearch(day, false) - 1
	i = clampi(i, 0, days.size() - 1)
	return vals[i]
