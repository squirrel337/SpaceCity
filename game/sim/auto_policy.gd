class_name AutoPolicy
extends RefCounted
## 자동 운영 — 밸런스 시뮬레이터의 Policy와 City.decide()를 그대로 옮겼다.
## "good"은 문서의 추천 운영, "naive"는 눈앞의 성장만 좇는 운영이다.
## 게임에서는 '시드 자동 운영'으로, 테스트에서는 파이썬과의 결과 비교에 쓴다.

const GOOD_RESEARCH := ["sintered_construction", "regenerative_fuel_cell", "space_weather_forecast",
	"closed_loop_ls2", "polar_prospecting", "autonomous_robots_2", "shielding_2",
	"sunlight_piping", "molten_regolith_electrolysis", "local_manufacturing",
	"robot_fabrication", "tall_towers", "algae_bioreactor", "cryogenic_propellant",
	"low_g_medicine", "megawatt_fission", "seed_distributed", "orbital_assembly",
	"mass_driver", "rotating_habitat"]
const NAIVE_RESEARCH := ["algae_bioreactor", "sunlight_piping", "autonomous_robots_2", "closed_loop_ls2",
	"tall_towers", "polar_prospecting", "sintered_construction", "regenerative_fuel_cell",
	"molten_regolith_electrolysis", "local_manufacturing", "robot_fabrication",
	"cryogenic_propellant", "space_weather_forecast", "shielding_2", "low_g_medicine",
	"megawatt_fission", "seed_distributed", "orbital_assembly", "mass_driver", "rotating_habitat"]

var name: String
var prepared: bool
## 1·2·3년차 식량 자급률 목표
var food_targets: Array


func _init(policy_name: String) -> void:
	name = policy_name
	prepared = policy_name == "good"
	food_targets = [0.5, 0.75, 1.0] if prepared else [0.6, 0.85, 1.0]


func configure(sim: CitySim) -> void:
	## 어두울 때 축전량이 이 비율 아래로 내려가면 4·3·2순위를 미리 끈다 (절전 정책)
	sim.shed_soc = {4: 0.5, 3: 0.4, 2: 0.2} if prepared else {4: 0.0, 3: 0.0, 2: 0.0}
	sim.research_queue = (GOOD_RESEARCH if prepared else NAIVE_RESEARCH).duplicate()
	sim.food_buffer_days = 40.0 if prepared else 25.0
	sim.ration_below_days = 10.0 if prepared else 0.5
	sim.express_below_days = 20.0 if prepared else 2.0
	sim.queue_by_priority = prepared
	sim.seat_limit_by_scrubbers = prepared


func decide(sim: CitySim, day: int) -> void:
	## 하루에 한 번 건설을 결정한다. 계획 수량(완공 + 대기)을 기준으로 판단한다.
	var C: Dictionary = sim.C
	var PER: Dictionary = sim.PER
	var pop := sim.population()
	var pop_next: float = pop + C["earth"]["crewed_seats"]
	@warning_ignore("integer_division")
	var year_index := mini(2, day / 365)

	# 생명유지: 추천 운영은 여유분을, 준비 없는 운영은 문제가 터진 뒤에 짓는다
	if prepared or sim.co2_ppm() > C["co2_ppm"]["bad"]:
		if sim.planned("co2_scrubber") * float(sim.prov("co2_scrubber", "co2_kg_day")) < 1.3 * pop_next * PER["co2_kg"]:
			sim.enqueue("co2_scrubber")
	if sim.planned("electrolyzer") * sim.recipe("electrolyzer", "out", "o2_kg") < 1.2 * pop_next * PER["o2_kg"]:
		sim.enqueue("electrolyzer")
	if sim.planned("water_recycler") * float(sim.prov("water_recycler", "wastewater_kg_day")) < 1.15 * pop_next * PER["water_use_kg"]:
		sim.enqueue("water_recycler")
	if prepared:
		var bonus := 1.5 if sim.techs.has("shielding_2") else 1.0
		if sim.planned("storm_shelter") * 40 * bonus + sim.planned("regolith_dome") * 60 < pop_next:
			sim.enqueue("storm_shelter")
		if sim.covered_habs + sim.queued("regolith_cover") < int(sim.counts.get("hab_module", 0)):
			sim.enqueue_special("regolith_cover")

	# 저장: 1·2순위 부하를 48시간 버티는 축전 (추천 운영만)
	var p1p2 := 0.0
	for m in sim.M:
		var pr := sim.priority_of(m)
		if pr == 1 or pr == 2:
			p1p2 += float(sim.M[m]["power_kw"]) * int(sim.counts.get(m, 0))
	var fission := 0.0
	for m in ["fission_40kw", "fission_1mw"]:
		fission += float(sim.prov(m, "generation_kw")) * sim.planned(m)
	var storage_planned: float = (sim.planned("battery_bank") * float(sim.prov("battery_bank", "storage_kwh"))
		+ sim.planned("rfc_unit") * float(sim.prov("rfc_unit", "storage_kwh")))
	if prepared and storage_planned < maxf(0.0, p1p2 * 0.7 - fission) * 48:
		if not sim.enqueue("rfc_unit") and not sim.techs.has("regenerative_fuel_cell"):
			sim.enqueue("battery_bank")

	# 발전: 평균 발전량이 평균 수요의 1.25배(준비 없는 운영은 1.05배)
	var load_sum := 0.0
	for m in sim.M:
		if sim.priority_of(m):
			load_sum += float(sim.M[m]["power_kw"]) * sim.planned(m)
	var avg_load := 0.85 * load_sum
	var tile_factor: Dictionary = C["illumination"]["tile_factor"]
	var tower_parts := []
	for t in sim.tiles:
		tower_parts.append(float(tile_factor[t]) * int(sim.tiles[t]))
	var towers_gen := PyCompat.fsum(tower_parts) * 100 * 0.9
	if towers_gen + fission < (1.25 if prepared else 1.05) * avg_load:
		var tile := sim.free_tile()
		if tile != "" and not (prepared and tile == "C" and sim.techs.has("megawatt_fission")):
			sim.enqueue("solar_tower", tile)
		elif not sim.enqueue("fission_1mw"):
			sim.enqueue("fission_40kw")
	if sim.planned("radiator") * float(sim.prov("radiator", "heat_kw")) < 1.2 * avg_load:
		sim.enqueue("radiator")

	# 거주: 다음 유인선 도착분까지 집을 준비
	var housing: float = (sim.planned("hab_module") * float(sim.prov("hab_module", "housing"))
		+ sim.planned("regolith_dome") * float(sim.prov("regolith_dome", "housing")))
	if housing < pop_next:
		if sim.techs.has("sintered_construction"):
			if sim.planned("regolith_printer") or sim.enqueue("regolith_printer"):
				sim.enqueue("regolith_dome")
		elif not prepared:
			sim.enqueue("hab_module")
		elif day > 60:
			sim.enqueue("hab_module")

	# 식량 자급률 목표
	var target: float = food_targets[year_index]
	var need: float = target * pop * PER["food_kg"] - sim.planned("algae_reactor") * sim.recipe("algae_reactor", "out", "food_kg")
	if sim.planned("hydroponics") * sim.recipe("hydroponics", "out", "food_kg") < need:
		sim.enqueue("hydroponics")
	if not prepared and sim.techs.has("algae_bioreactor") and sim.planned("algae_reactor") < pop / 60:
		sim.enqueue("algae_reactor")
	if sim.caps["food_kg"] < pop * PER["food_kg"] * 120 and not sim.queued("food_store"):
		sim.enqueue("food_store")
	if sim.caps["o2_kg"] < pop * PER["o2_kg"] * 25 and not sim.queued("tank_farm"):
		sim.enqueue("tank_farm")

	# 물: 하루 순손실을 얼음 채굴이 넉넉히 덮도록
	var loss: float = pop * PER["water_use_kg"] * (1 - sim.recovery) + pop * PER["o2_kg"] * 0.6 * 1.125
	if sim.planned("ice_miner") * sim.recipe("ice_miner", "out", "water_kg") * sim.mining * 0.8 < loss + 150:
		sim.enqueue("ice_miner")

	# 사회·연구·산업
	if sim.planned("research_lab") < ceil(pop / 60):
		sim.enqueue("research_lab")
	if prepared and sim.planned("green_commons") < floor(pop / 100):
		sim.enqueue("green_commons")
	if sim.planned("medical_bay") * float(sim.prov("medical_bay", "care")) < pop_next:
		sim.enqueue("medical_bay")
	@warning_ignore("integer_division")
	if sim.planned("excavator") < 1 + (sim.queued("regolith_dome") + sim.queued("storm_shelter")) / 2:
		sim.enqueue("excavator")
	if sim.techs.has("molten_regolith_electrolysis") and sim.planned("mre_plant") < 1:
		sim.enqueue("mre_plant")
	if sim.techs.has("local_manufacturing") and sim.planned("parts_fab") < 2 * maxi(1, sim.planned("mre_plant")):
		sim.enqueue("parts_fab")
	if sim.robots + sim.queued("robot") < 8 + pop / 40:
		sim.enqueue_special("robot")
