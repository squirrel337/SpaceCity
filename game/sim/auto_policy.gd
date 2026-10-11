class_name AutoPolicy
extends RefCounted
## 자동 운영 — 밸런스 시뮬레이터의 Policy와 City.decide()를 그대로 옮겼다.
## "good"은 문서의 추천 운영, "naive"는 눈앞의 성장만 좇는 운영이다.
## "variety"는 추천 운영과 같되 계열마다 여러 종류를 돌아가며 짓는다 (새 건물 규칙을 파이썬과 맞춰 보는 용도).
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
var variety: bool
## 1·2·3년차 식량 자급률 목표
var food_targets: Array


func _init(policy_name: String) -> void:
	name = policy_name
	prepared = policy_name in ["good", "variety"]
	variety = policy_name == "variety"
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

	# 생명유지: 추천 운영은 여유분을, 준비 없는 운영은 문제가 터진 뒤에 짓는다 (바깥 공기·상수도가 있으면 짓지 않는다)
	var open_air := sim.open_air
	if not open_air and (prepared or sim.co2_ppm() > C["co2_ppm"]["bad"]):
		if _cap(sim, "co2_scrubber", "prov", "co2_kg_day") < 1.3 * pop_next * PER["co2_kg"]:
			build(sim, "co2_scrubber")
	if not open_air and _cap(sim, "electrolyzer", "out", "o2_kg") < 1.2 * pop_next * PER["o2_kg"]:
		build(sim, "electrolyzer")
	if not sim.supply.has("water_kg") and _cap(sim, "water_recycler", "prov", "wastewater_kg_day") < 1.15 * pop_next * PER["water_use_kg"]:
		build(sim, "water_recycler")
	if prepared and not open_air:           # 지구에는 태양 양성자 폭풍이 닿지 않는다
		var bonus := 1.5 if sim.techs.has("shielding_2") else 1.0
		var shelter := 0.0
		for m in sim.with_prov("shelter"):
			var sh := float(sim.prov(m, "shelter"))
			if sh:
				shelter += sim.planned(m) * (sh * (bonus if sim.family(m) == "storm_shelter" else 1.0))
		if shelter < pop_next:
			build(sim, "storm_shelter")
		if sim.covered_habs + sim.queued("regolith_cover") < int(sim.counts.get("hab_module", 0)):
			sim.enqueue_special("regolith_cover")

	# 저장: 1·2순위 부하를 48시간 버티는 축전 (추천 운영만)
	var p1p2 := 0.0
	for m in sim.M:
		var pr := sim.priority_of(m)
		if pr == 1 or pr == 2:
			p1p2 += float(sim.M[m]["power_kw"]) * int(sim.counts.get(m, 0))
	var fission := 0.0
	for m in sim.with_prov("generation_kw"):
		if sim.family(m) != "solar_tower":
			fission += sim.planned(m) * float(sim.prov(m, "generation_kw"))
	var storage_planned := 0.0
	for m in sim.with_prov("storage_kwh"):
		if sim.family(m) in ["battery_bank", "rfc_unit"]:
			storage_planned += sim.planned(m) * float(sim.prov(m, "storage_kwh"))
	var store_h := maxf(48.0, sim.night_h)          # 긴 밤(달 적도 354시간, 칼리스토 200시간)은 밤 내내
	if prepared and storage_planned < maxf(0.0, p1p2 * 0.7 - fission) * store_h:
		if not build(sim, "rfc_unit") and not sim.techs.has("regenerative_fuel_cell"):
			build(sim, "battery_bank")

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
	var towers_gen := PyCompat.fsum(tower_parts) * 100 * 0.9 * sim.sun_k
	var long_night := sim.night_h > 72                # 밤이 사흘보다 길면 타워를 믿지 않는다
	if long_night:
		towers_gen = 0.0
	if towers_gen + fission < (1.25 if prepared else 1.05) * avg_load:
		var tile := sim.free_tile()
		# 햇빛이 약하거나 밤이 긴 부지(세레스·목성·토성계·달 적도)는 타워 대신 원자로
		if (tile != "" and sim.sun_k >= 0.2 and not long_night
				and not (prepared and tile == "C" and sim.techs.has("megawatt_fission"))):
			build(sim, "solar_tower", tile)
		elif not build(sim, "fission_1mw"):
			build(sim, "fission_40kw")
	var heat := 0.0
	for m in sim.with_prov("heat_kw"):
		if sim.prov(m, "heat_kw"):
			heat += sim.planned(m) * float(sim.prov(m, "heat_kw"))
	if heat < 1.2 * avg_load:
		build(sim, "radiator")

	# 거주: 다음 유인선 도착분까지 집을 준비
	var housing := 0.0
	for m in sim.with_prov("housing"):
		if sim.prov(m, "housing"):
			housing += sim.planned(m) * float(sim.prov(m, "housing"))
	if housing < pop_next:
		if sim.techs.has("sintered_construction"):
			if fam_planned(sim, "regolith_printer") or build(sim, "regolith_printer"):
				build(sim, "regolith_dome")
		elif not prepared:
			build(sim, "hab_module")
		elif day > 60:
			build(sim, "hab_module")

	# 식량 자급률 목표
	var target: float = food_targets[year_index]
	var need: float = target * pop * PER["food_kg"] - _cap(sim, "algae_reactor", "out", "food_kg")
	if not sim.supply.has("food_kg") and _cap(sim, "hydroponics", "out", "food_kg") < need:
		build(sim, "hydroponics")
	if not prepared and sim.techs.has("algae_bioreactor") and fam_planned(sim, "algae_reactor") < pop / 60:
		build(sim, "algae_reactor")
	if not sim.supply.has("food_kg") and sim.caps["food_kg"] < pop * PER["food_kg"] * 120 and not fam_queued(sim, "food_store"):
		build(sim, "food_store")
	if not open_air and sim.caps["o2_kg"] < pop * PER["o2_kg"] * 25 and not fam_queued(sim, "tank_farm"):
		build(sim, "tank_farm")

	# 물: 하루 순손실을 얼음 채굴이 넉넉히 덮도록
	var loss: float = pop * PER["water_use_kg"] * (1 - sim.recovery) + pop * PER["o2_kg"] * 0.6 * 1.125
	if not sim.supply.has("water_kg") and _cap(sim, "ice_miner", "out", "water_kg") * sim.mining * 0.8 < loss + 150:
		build(sim, "ice_miner")

	# 사회·연구·산업
	if fam_planned(sim, "research_lab") < ceil(pop / 60):
		build(sim, "research_lab")
	if prepared and fam_planned(sim, "green_commons") < floor(pop / 100):
		build(sim, "green_commons")
	var care := 0.0
	for m in sim.with_prov("care"):
		if sim.prov(m, "care"):
			care += sim.planned(m) * float(sim.prov(m, "care"))
	if care < pop_next:
		build(sim, "medical_bay")
	@warning_ignore("integer_division")
	if fam_planned(sim, "excavator") < 1 + (fam_queued(sim, "regolith_dome") + fam_queued(sim, "storm_shelter")) / 2:
		build(sim, "excavator")
	if sim.techs.has("molten_regolith_electrolysis") and fam_planned(sim, "mre_plant") < 1:
		build(sim, "mre_plant")
	if sim.techs.has("local_manufacturing") and fam_planned(sim, "parts_fab") < 2 * maxi(1, fam_planned(sim, "mre_plant")):
		build(sim, "parts_fab")
	if sim.robots + sim.queued("robot") < 8 + pop / 40:
		sim.enqueue_special("robot", sim.auto_reserve)


## 계열의 계획 수량 (완공 + 대기)
static func fam_planned(sim: CitySim, fam: String) -> int:
	var n := 0
	for m in GameData.FAMILY[fam]:
		n += sim.planned(m)
	return n


static func fam_queued(sim: CitySim, fam: String) -> int:
	var n := 0
	for m in GameData.FAMILY[fam]:
		n += sim.queued(m)
	return n


## 계열의 계획 수량 × 값 ("prov" 열쇠, 또는 조리법 "out"·"in" 열쇠) — 데이터 순서로 더한다
static func _cap(sim: CitySim, fam: String, side: String, key: String) -> float:
	var total := 0.0
	for m in GameData.FAMILY[fam]:
		var v: float = float(sim.prov(m, key)) if side == "prov" else sim.recipe(m, side, key)
		total += sim.planned(m) * v
	return total


## 정책의 건설: 보통은 계열의 기본 모듈. 'variety'는 계열의 종류를 돌아가며 고르고, 못 지으면 기본 모듈
func build(sim: CitySim, fam: String, tile: String = "") -> bool:
	if not variety:
		return sim.enqueue(fam, tile, sim.auto_reserve)
	var options := []
	for m in GameData.FAMILY[fam]:
		if sim.M[m]["tech"] == null or sim.techs.has(sim.M[m]["tech"]):
			options.append(m)
	if options.is_empty():
		return sim.enqueue(fam, tile, sim.auto_reserve)
	var pick: String = options[sim.variety_turn % options.size()]
	sim.variety_turn += 1
	if pick != fam and sim.enqueue(pick, tile, sim.auto_reserve):
		return true
	return sim.enqueue(fam, tile, sim.auto_reserve)
