class_name StatsView
extends VBoxContainer
## 통계 — 고른 도시의 날마다 기록(CitySim.daily)과 지원 점수(Colonies의 c["hist"])를 작은 그래프 여럿으로 (그래프마다 단위 하나),
## 모든 도시의 정착민은 한 그래프에 (도시마다 범주 색 — 목록 순서로 정해져 걸러도 바뀌지 않는다).
## 가로축은 게임을 시작한 날부터의 날 (모든 그래프가 같다). 기간(전체·1년·90일·30일)은 위에서 고른다.
## 그래프를 가리키면 모든 그래프가 같은 날을 가리키고 그날의 값을 읽어 준다

const RANGES := [["all", "전체", 0], ["year", "1년", 365], ["q", "90일", 90], ["m", "30일", 30]]

var mgr: Colonies
var colony: Dictionary = {}
var _range := "all"
var _charts: Array = []              # [StatsChart, 만드는 Callable(from, to) — 줄들]
var _sig := ""
var _head: Label
var _box := VBoxContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_head = ThemeFactory.muted("", 13)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var g := ButtonGroup.new()
	for r in RANGES:
		var b := Button.new()
		b.text = r[1]
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = r[0] == _range
		b.custom_minimum_size = Vector2(0, 32)
		var id: String = r[0]
		b.pressed.connect(func():
			_range = id
			_sig = ""
			refresh())
		row.add_child(b)
	add_child(row)
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	_add("정착민 · 집", "명", func(c: Dictionary): return [_daily(c, "population", "정착민", 0), _daily(c, "housing", "집", 1)])
	_add("사기 · 신뢰", "", func(c: Dictionary): return [_daily(c, "morale", "사기", 0), _daily(c, "trust", "신뢰", 1)], 0.0, 100.0)
	_add("비축 일수 · 산소 · 식량", "일", func(c: Dictionary): return [_daily(c, "o2_reserve_days", "산소", 0),
		_daily(c, "food_reserve_days", "식량", 1)])
	_add("축전량", "%", func(c: Dictionary): return [_daily(c, "soc", "축전", 0, 100.0)], 0.0, 100.0)
	_add("CO₂", " ppm", func(c: Dictionary): return [_daily(c, "co2_ppm", "CO₂", 0)])
	_add("부품", "", func(c: Dictionary): return [_daily(c, "parts", "부품", 0)])
	_add("지구 지원 점수", "", func(c: Dictionary): return [_hist(c, "support", "지원 점수", 0)])
	_add("기술", "가지", func(c: Dictionary): return [_daily(c, "techs", "기술", 0)], null, null, true)
	_add("모든 도시의 정착민", "명", func(_c: Dictionary): return _all_cities())


func _add(title: String, unit: String, make: Callable, lo: Variant = null, hi: Variant = null, step := false) -> void:
	var ch := StatsChart.new()
	ch.title = title
	ch.unit = unit
	ch.y_min = lo
	ch.y_max = hi
	ch.step = step
	ch.hovered.connect(_on_hover)
	_box.add_child(ch)
	_charts.append([ch, make])


func _on_hover(day: int) -> void:
	for e in _charts:
		var ch: StatsChart = e[0]
		ch.hover_day = day
		ch.queue_redraw()


## 그 도시의 날 0이 게임의 몇째 날인가 (도시를 세운 시각)
static func _day0(c: Dictionary) -> int:
	return int(floor(float(c.get("founded", 0)) / 24.0))


## 날마다 기록의 한 칸 → 줄 (가로축은 게임의 날)
func _daily(c: Dictionary, key: String, name: String, slot: int, k := 1.0) -> Dictionary:
	var sim: CitySim = c["sim"]
	var d0 := _day0(c)
	var days := PackedInt32Array()
	var vals := PackedFloat32Array()
	for rec in sim.daily:
		days.append(d0 + int(rec["day"]))
		vals.append(float(rec.get(key, 0.0)) * k)
	return {"name": name, "days": days, "values": vals, "color": StatsChart.SERIES[slot]}


func _hist(c: Dictionary, key: String, name: String, slot: int) -> Dictionary:
	var h: Dictionary = c.get("hist", {}) if c.get("hist") is Dictionary else {}
	var days := PackedInt32Array()
	var vals := PackedFloat32Array()
	var hd: Array = h.get("days", [])
	var hv: Array = h.get(key, [])
	for i in mini(hd.size(), hv.size()):
		days.append(int(hd[i]))
		vals.append(float(hv[i]))
	return {"name": name, "days": days, "values": vals, "color": StatsChart.SERIES[slot]}


## 모든 도시: 목록 순서로 색 자리 (여덟 넘으면 아홉째부터는 묶지 않고 그리지 않는다 — 도시는 많아야 여덟 남짓)
func _all_cities() -> Array:
	var out: Array = []
	if mgr == null:
		return out
	for i in mini(mgr.list.size(), StatsChart.SERIES.size()):
		var c: Dictionary = mgr.list[i]
		var l := _daily(c, "population", String(c.get("short", c["name"])), i)
		out.append(l)
	return out


func refresh() -> void:
	if colony.is_empty() or not colony.get("sim") is CitySim:
		return
	var sim: CitySim = colony["sim"]
	var today := int(floor(float(mgr.hour if mgr != null else sim.hour) / 24.0))
	var sig := "%d|%d|%s|%d" % [sim.get_instance_id(), sim.daily.size(), _range, mgr.list.size() if mgr != null else 0]
	if sig == _sig:
		return
	_sig = sig
	var span := 0
	for r in RANGES:
		if r[0] == _range:
			span = int(r[2])
	var first := maxi(0, _day0(colony))
	if _range == "all" and mgr != null:
		for c in mgr.list:
			first = mini(first, maxi(0, _day0(c)))
	var from := maxi(first, today - span) if span > 0 else first
	_head.text = "%s — 날마다 기록 %d일 · 가로축은 게임을 시작한 날부터 · 그래프를 가리키면 그날의 값" % [String(colony.get("name", "")),
		sim.daily.size()]
	for e in _charts:
		var ch: StatsChart = e[0]
		ch.set_data(ch.title, (e[1] as Callable).call(colony), from, maxi(today, from + 1))
