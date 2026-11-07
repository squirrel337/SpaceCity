extends SceneTree
## 시뮬레이션 한 시간의 갈래별 시간 — 기본 도시들로 며칠 흐른 뒤, 며칠 동안 Colonies.profiling을 켜고 한 시간마다 걸린 시간의 분포와
## 갈래(도시의 한 시간 · 하루 끝의 발전 모드·시설·… · 교통 · 대도시)마다 합·횟수·가장 긴 시간을 적는다 (화면 없이).
##   godot --headless --path game --script res://tests/sim_profile.gd -- [--days 400] [--measure 30]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days := 400
	var measure := 30
	var i := args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	i = args.find("--measure")
	if i >= 0 and i + 1 < args.size():
		measure = maxi(1, int(args[i + 1]))
	var home := CitySim.new(2061, 40.0, "good")
	var plan := CityPlan.create(home, BaseLayout.new("ridge"))
	var col := Colonies.new()
	col.start(home, plan)
	for _d in days:
		for _h in 24:
			col.step()
	Colonies.profiling = true
	Colonies.prof = {}
	var worst := 0
	var sum := 0
	var n := 0
	var hist := {}
	for _d in measure:
		for _h in 24:
			var t0 := Time.get_ticks_usec()
			col.step()
			var dt := Time.get_ticks_usec() - t0
			worst = maxi(worst, dt)
			sum += dt
			n += 1
			var b := "<2ms" if dt < 2000 else ("<8ms" if dt < 8000 else ("<16ms" if dt < 16000 else ("<33ms" if dt < 33000 else ">=33ms")))
			hist[b] = int(hist.get(b, 0)) + 1
	Colonies.profiling = false
	print("sim: %d일 뒤 %d일 — 한 시간 평균 %.2f ms · 가장 긴 %.1f ms · 분포 %s" % [days, measure, sum / 1000.0 / n, worst / 1000.0,
		str(hist)])
	var keys := Colonies.prof.keys()
	keys.sort_custom(func(a, b): return int(Colonies.prof[a][2]) > int(Colonies.prof[b][2]))
	for k in keys.slice(0, 30):
		var e: Array = Colonies.prof[k]
		print("sim: %-28s 합 %8.1f ms · %5d번 · 평균 %7.2f ms · 가장 긴 %7.2f ms" % [k, e[0] / 1000.0, e[1],
			e[0] / 1000.0 / maxf(e[1], 1), e[2] / 1000.0])
	var pops := PackedStringArray()
	for c in col.list:
		pops.append("%s %d명/%d채" % [String(c["short"]), int((c["sim"] as CitySim).population()), (c["plan"] as CityPlan).buildings.size()])
	print("sim: ", ", ".join(pops))
	quit(0)
