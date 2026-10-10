class_name PowerPanel
extends VBoxContainer
## 전력 탭 — 발전·수요·축전, 그림자 예보, 절전 정책 문턱

const PRIORITY_KO := {1: "1순위 생존", 2: "2순위 식량", 3: "3순위 산업·로봇", 4: "4순위 연구·사회"}

var sim: CitySim
var summary := Label.new()
var battery := Meter.new("축전")
var shadow := ThemeFactory.muted("", 14)
var priority_rows := {}
var sliders := {}
var slider_labels := {}
var heat := ThemeFactory.muted("")


func _init() -> void:
	add_theme_constant_override("separation", 10)
	add_child(ThemeFactory.heading("전력과 열"))
	summary.add_theme_font_size_override("font_size", 15)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	add_child(battery)
	shadow.add_theme_color_override("font_color", Palette.BLUE)
	add_child(shadow)
	add_child(HSeparator.new())
	add_child(ThemeFactory.heading("부하 순위", 16))
	for p in [1, 2, 3, 4]:
		var row := HBoxContainer.new()
		var row_name := Label.new()
		row_name.text = PRIORITY_KO[p]
		row_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state := Label.new()
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(row_name)
		row.add_child(state)
		add_child(row)
		priority_rows[p] = state
	add_child(heat)
	add_child(HSeparator.new())
	add_child(ThemeFactory.heading("절전 정책 — 어두울 때 축전량이 문턱 아래면 끈다", 16))
	for p in [4, 3, 2]:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 90
		slider.step = 5
		slider.custom_minimum_size.y = 28
		slider.value_changed.connect(_on_threshold.bind(p))
		add_child(slider)
		sliders[p] = slider
		slider_labels[p] = label
	add_child(ThemeFactory.muted("1순위는 끄지 않는다. 그래도 모자라면 생명유지 전체가 비례해서 느려진다(감전). " +
		"문턱을 0으로 두면 '모두 유지' — 축전을 다 쓴 뒤 한꺼번에 꺼진다. 농장은 72시간 넘게 꺼지면 작물이 죽는다."))


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	for p in sliders:
		sliders[p].set_value_no_signal(round(sim.shed_soc[p] * 100.0))
	_slider_labels()


func _on_threshold(value: float, p: int) -> void:
	sim.shed_soc[p] = value / 100.0
	_slider_labels()


func _slider_labels() -> void:
	for p in slider_labels:
		var v: int = int(round(sim.shed_soc[p] * 100.0))
		slider_labels[p].text = "%s을 끄는 축전량: %s" % [PRIORITY_KO[p], ("%d%% 아래" % v) if v > 0 else "끄지 않음"]


func update_view() -> void:
	if sim == null:
		return
	var lit := not sim.is_dark()
	var gen := sim.solar_kw * (1.0 if lit else 0.0) + sim.fission_kw
	var lp: Dictionary = sim.last_power
	var demand := 0.0
	if lp.has("load"):
		for p in lp["load"]:
			demand += lp["load"][p]
	summary.text = "발전 %s kW (태양광 %s · 원자로 %s) · 수요 %s kW" % [
		Fmt.n(gen), Fmt.n(sim.solar_kw if lit else 0.0), Fmt.n(sim.fission_kw), Fmt.n(demand)]
	var cap := sim.bat_cap + sim.rfc_cap
	var stored := sim.battery + sim.rfc
	var soc := stored / cap if cap > 0 else 0.0
	var hold := stored / maxf(1.0, demand - sim.fission_kw) if demand > sim.fission_kw else 999.0
	battery.set_values(soc, Fmt.pct(soc), "%s / %s kWh · 그림자 속에서 지금 수요로 %s" % [
		Fmt.n(stored), Fmt.n(cap), Fmt.hours(hold) if hold < 999 else "충분"],
		Palette.level_color(soc, 0.4, 0.15))
	shadow.text = _shadow_text()
	var on: Dictionary = lp.get("on", {1: true, 2: true, 3: true, 4: true})
	for p in priority_rows:
		var label: Label = priority_rows[p]
		if p == 1:
			var frac: float = lp.get("frac1", 1.0)
			label.text = "가동" if frac >= 1.0 else "감전 %d%%" % int(round(frac * 100))
			label.add_theme_color_override("font_color", Palette.TEAL if frac >= 1.0 else Palette.RED)
		else:
			var kw: float = lp.get("load", {}).get(p, 0.0)
			label.text = ("가동 · %s kW" % Fmt.n(kw)) if on.get(p, true) else "꺼짐"
			label.add_theme_color_override("font_color", Palette.TEAL if on.get(p, true) else Palette.AMBER)
	heat.text = "방열 %s kW / 사용 %s kW — 넘치면 산업부터 느려진다" % [Fmt.n(sim.heat_cap), Fmt.n(demand)]


func _shadow_text() -> String:
	## 시드의 그림자 예보 — 지형과 궤도로 미리 계산한 일정이다
	var h := sim.hour
	if sim.is_dark(h):
		var end := h
		while end < sim.dark.size() and sim.dark[end] == 1:
			end += 1
		return "지금 그림자 속 — %s 뒤에 해가 든다" % Fmt.hours(end - h)
	var start := h
	while start < sim.dark.size() and sim.dark[start] == 0 and start - h < 24 * 40:
		start += 1
	if start >= sim.dark.size() or start - h >= 24 * 40:
		return "40일 안에 그림자 없음"
	var end2 := start
	while end2 < sim.dark.size() and sim.dark[end2] == 1:
		end2 += 1
	return "그림자 예보 — %s 뒤부터 %s (%s)" % [Fmt.hours(start - h), Fmt.hours(end2 - start), sim.date_text(start)]
