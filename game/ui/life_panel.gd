class_name LifePanel
extends VBoxContainer
## 생명유지 탭 — 여유(용량 대비 %)와 비축 일수로 읽는다

var sim: CitySim
var o2 := Meter.new("산소")
var co2 := Meter.new("CO₂")
var water := Meter.new("물")
var food := Meter.new("식량")
var shelter := Meter.new("대피")
var dose := Meter.new("선량")
var earth_label := ThemeFactory.muted("")
var ration_slider := HSlider.new()
var ration_label := Label.new()
var express_slider := HSlider.new()
var express_label := Label.new()
var express_button := Button.new()


func _init() -> void:
	add_theme_constant_override("separation", 12)
	add_child(ThemeFactory.heading("생명유지 · 하루 기준"))
	for m in [o2, co2, water, food, shelter, dose]:
		add_child(m)
	add_child(HSeparator.new())
	add_child(ThemeFactory.heading("지구", 16))
	add_child(earth_label)
	add_child(ThemeFactory.heading("식량 위기 방침", 16))
	_slider_row(ration_slider, ration_label, 0, 30, 1)
	_slider_row(express_slider, express_label, 0, 40, 1)
	express_button.text = "지금 긴급 보급선 부르기 (지원 300, 7일)"
	express_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	express_button.pressed.connect(_on_express)
	add_child(express_button)
	ration_slider.value_changed.connect(_on_ration_threshold)
	express_slider.value_changed.connect(_on_express_threshold)


func _on_ration_threshold(v: float) -> void:
	sim.ration_below_days = v
	_labels()


func _on_express_threshold(v: float) -> void:
	sim.express_below_days = v
	_labels()


func _slider_row(slider: HSlider, label: Label, lo: float, hi: float, step: float) -> void:
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # 영어가 길면 줄을 바꾼다 (옆 패널을 넓히지 않게)
	add_child(label)
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.y = 44
	add_child(slider)


func bind(p_sim: CitySim) -> void:
	sim = p_sim
	ration_slider.set_value_no_signal(sim.ration_below_days)
	express_slider.set_value_no_signal(sim.express_below_days)
	_labels()


func _labels() -> void:
	ration_label.text = "식량 비축이 %d일 아래면 배급 (소비 70%%, 사기 −10)" % int(sim.ration_below_days)
	express_label.text = ("식량 비축이 %d일 아래면 긴급 보급선 자동 요청" % int(sim.express_below_days)
		if sim.express_below_days > 0 else "긴급 보급선 자동 요청 끔")


func _on_express() -> void:
	if not sim.request_express():
		express_button.text = "부를 수 없다 — 이미 오는 중이거나 지원 부족"
	update_view()


func update_view() -> void:
	if sim == null:
		return
	var per: Dictionary = sim.PER
	var pop := sim.population()
	var wk := sim.wk
	var farms_up: bool = sim.prev[2] and sim.crops_alive()

	# 산소: 생산 능력 대비 소비
	var farm_o2: float = wk["hydroponics"] * sim.recipe("hydroponics", "out", "o2_kg") if farms_up else 0.0
	var bio_o2: float = farm_o2 + wk["algae_reactor"] * sim.recipe("algae_reactor", "out", "o2_kg") \
		+ wk["green_commons"] * sim.recipe("green_commons", "out", "o2_kg")
	var elec_o2: float = wk["electrolyzer"] * sim.recipe("electrolyzer", "out", "o2_kg")
	var o2_use: float = pop * per["o2_kg"]
	var o2_cap := bio_o2 + elec_o2
	var o2_margin := o2_cap / o2_use - 1.0 if o2_use > 0 else 9.99
	var o2_days: float = sim.stock["o2_kg"] / o2_use if o2_use > 0 else 999.0
	o2.set_values(o2_use / maxf(o2_cap, 0.001), "여유 %s" % Fmt.pct(o2_margin),
		"생산 능력 %s kg (식물 %s · 전기분해 %s) / 소비 %s kg · 비축 %s" % [Fmt.n(o2_cap), Fmt.n(bio_o2), Fmt.n(elec_o2), Fmt.n(o2_use), Fmt.days(o2_days)],
		Palette.level_color(minf(o2_margin, o2_days / 10.0 - 1.0), 0.25, 0.0))

	# CO₂: 제거 능력 대비 배출
	var farm_co2: float = wk["hydroponics"] * sim.recipe("hydroponics", "in", "co2_kg") if farms_up else 0.0
	var other_bio: float = wk["algae_reactor"] * sim.recipe("algae_reactor", "in", "co2_kg") \
		+ wk["green_commons"] * sim.recipe("green_commons", "in", "co2_kg")
	var scrub: float = wk["co2_scrubber"] * float(sim.prov("co2_scrubber", "co2_kg_day"))
	var emit: float = pop * per["co2_kg"]
	var co2_margin := (scrub + farm_co2 + other_bio) / emit - 1.0 if emit > 0 else 9.99
	var without_farms := (scrub + other_bio) / emit - 1.0 if emit > 0 else 9.99
	var ppm := sim.co2_ppm()
	var co2_color := Palette.level_color(co2_margin, 0.2, 0.0)
	if ppm > sim.C["co2_ppm"]["warn"]:
		co2_color = Palette.RED if ppm > sim.C["co2_ppm"]["bad"] else Palette.AMBER
	co2.set_values(emit / maxf(scrub + farm_co2 + other_bio, 0.001), "여유 %s" % Fmt.pct(co2_margin),
		"제거 %s kg (제거기 %d기 %s · 식물 %s) / 배출 %s kg · 공기 %s ppm\n농장이 꺼지면 여유 %s" % [
			Fmt.n(scrub + farm_co2 + other_bio), wk["co2_scrubber"], Fmt.n(scrub), Fmt.n(farm_co2 + other_bio),
			Fmt.n(emit), Fmt.n(ppm), Fmt.pct(without_farms)], co2_color)

	# 물: 비축과 하루 수지
	var mined: float = wk["ice_miner"] * sim.recipe("ice_miner", "out", "water_kg") * sim.mining
	var lost: float = pop * per["water_use_kg"] * (1.0 - sim.recovery) + o2_use * 1.125
	var water_cap: float = maxf(1.0, sim.caps["water_kg"])
	water.set_values(sim.stock["water_kg"] / water_cap, "%s t" % Fmt.n(sim.stock["water_kg"] / 1000.0, 1),
		"재활용 %s · 채굴 %s kg/일 (얼음 채굴기 %d기) · 순손실 약 %s kg/일" % [Fmt.pct(sim.recovery), Fmt.n(mined),
			wk["ice_miner"], Fmt.n(lost)], Palette.level_color(mined / maxf(lost, 1.0) - 1.0, 0.2, 0.0))

	# 식량: 자급률과 비축
	var made: float = (wk["hydroponics"] * sim.recipe("hydroponics", "out", "food_kg") if sim.crops_alive() else 0.0) \
		+ wk["algae_reactor"] * sim.recipe("algae_reactor", "out", "food_kg")
	var need: float = pop * per["food_kg"]
	var self_suff := made / need if need > 0 else 0.0
	var food_days: float = sim.stock["food_kg"] / need if need > 0 else 999.0
	var food_text := "농장 %d기 %s kg / 소비 %s kg · 비축 %s" % [wk["hydroponics"], Fmt.n(made), Fmt.n(need), Fmt.days(food_days)]
	if not sim.crops_alive():
		food_text += "\n작물 고사 — 다시 기르는 중"
	if sim.rationing:
		food_text += "\n배급 중 (소비 70%)"
	food.set_values(self_suff, "자급 %s" % Fmt.pct(self_suff), food_text,
		Palette.level_color(food_days / 20.0 - 1.0, 0.5, 0.0) if self_suff < 1.0 else Palette.TEAL)

	# 대피: 폭풍 대피 정원
	var seats := sim.shelter_cap
	shelter.set_values(seats / maxf(pop, 1.0), "%d / %d" % [int(seats), int(pop)],
		"폭풍 대피소 %d기 · 차폐 돔 %d기. 대형 폭풍 때 자리가 모자라면 대피소 추첨이 열린다" % [
			int(sim.counts.get("storm_shelter", 0)), int(sim.counts.get("regolith_dome", 0))],
		Palette.TEAL if seats >= pop else Palette.RED)

	# 선량: 평균 누적 선량과 경력 한도
	var dose_sum := 0.0
	var top := 0.0
	for c in sim.cohorts:
		dose_sum += c[0] * c[1]
		top = maxf(top, c[1])
	var avg := dose_sum / pop if pop > 0 else 0.0
	var limit: float = sim.C["career_dose_limit_msv"]
	dose.set_values(top / limit, "%s mSv" % Fmt.n(avg),
		"평균 누적 %s mSv · 가장 높은 무리 %s mSv / 한도 %s · 오늘 %s mSv\n피복한 거주 모듈 %d / %d기" % [
			Fmt.n(avg), Fmt.n(top), Fmt.n(limit), Fmt.n(sim.last_dose_rate, 2), sim.covered_habs,
			int(sim.counts.get("hab_module", 0))],
		Palette.level_color(1.0 - top / limit, 0.35, 0.15))

	var day := sim.current_day()
	var express := ""
	if sim.express_eta != null:
		express = "\n긴급 보급선 도착까지 %d일" % maxi(0, int(sim.express_eta) - day)
	earth_label.text = "지원 %s · 다음 화물선 %s (D-%d) · 다음 유인선 %s (D-%d, 24석)%s" % [
		Fmt.n(sim.support), sim.date_text(sim.next_cargo * 24, false), maxi(0, sim.next_cargo - day),
		sim.date_text(sim.next_crewed * 24, false), maxi(0, sim.next_crewed - day), express]
	express_button.disabled = sim.express_eta != null or sim.support < sim.C["earth"]["express_cost_support"]
	if not express_button.disabled:
		express_button.text = "지금 긴급 보급선 부르기 (지원 300, 7일)"
