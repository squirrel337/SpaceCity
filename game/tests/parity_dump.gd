extends SceneTree
## 파이썬 시뮬레이터와 비교할 일별 원시 상태를 JSON Lines로 쓴다. tools/parity_check.py가 부른다.
##   godot --headless --path game --script res://tests/parity_dump.gd -- --seed 2061 --policy good --years 3 --out out.jsonl


func _initialize() -> void:
	var args := {}
	var user_args := OS.get_cmdline_user_args()
	for i in range(0, user_args.size() - 1, 2):
		args[user_args[i].trim_prefix("--")] = user_args[i + 1]
	var sim := CitySim.new(int(args.get("seed", "2061")), float(args.get("years", "3")), String(args.get("policy", "good")))
	var out := FileAccess.open(String(args["out"]), FileAccess.WRITE)
	for d in range(sim.days):
		var pop := sim.population()
		for _i in range(24):
			sim.step_hour(pop)
		sim.step_day(d)
		out.store_line(JSON.stringify(snapshot(sim, d), "", false, true))
	out.close()
	quit(0)


static func snapshot(sim: CitySim, d: int) -> Dictionary:
	var s := sim.stock
	var modules := 0
	for v in sim.counts.values():
		modules += v
	var broken_total := 0
	for v in sim.broken.values():
		broken_total += v
	var deaths := 0.0
	for v in sim.deaths.values():
		deaths += v
	var dose_sum := 0.0
	for c in sim.cohorts:
		dose_sum += c[0] * c[1]
	return {
		"day": d, "hour": sim.hour, "pop": sim.population(), "o2_kg": s["o2_kg"], "co2_air": sim.co2_air,
		"food_kg": s["food_kg"], "water_kg": s["water_kg"], "h2_kg": s["h2_kg"], "tank_co2_kg": s["co2_kg"],
		"ch4_kg": s["ch4_kg"], "wastewater_kg": s["wastewater_kg"], "regolith_t": s["regolith_t"],
		"metal_t": s["metal_t"], "parts": s["parts"], "battery": sim.battery, "rfc": sim.rfc, "morale": sim.morale,
		"trust": sim.trust, "trust_memory": sim.trust_memory, "support": sim.support, "rp_bank": sim.rp_bank,
		"robots": sim.robots, "robots_broken": sim.robots_broken, "techs": sim.techs.size(),
		"built": sim.stats.get("built", 0), "queue_len": sim.queue.size(), "covered_habs": sim.covered_habs,
		"modules": modules, "broken": broken_total, "max_co2": sim.max_co2,
		"brownout_h": sim.stats.get("brownout_h", 0), "crop_losses": sim.stats.get("crop_losses", 0),
		"exposed": sim.stats.get("exposed_person_events", 0), "departed_dose": sim.stats.get("departed_dose", 0),
		"deaths": deaths, "next_cargo": sim.next_cargo, "next_crewed": sim.next_crewed, "dose_sum": dose_sum,
		"rationing": 1 if sim.rationing else 0, "seq": sim.seq,
	}
