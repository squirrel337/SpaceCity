extends SceneTree
## 성능 측정 — 장면마다 프레임의 CPU 시간(배치·도시·화면 위 그리기·노선)과 그리기 호출·물체·삼각형 수를 잰다.
## 기본 도시로 시작해 며칠 흐른 뒤 (수송선이 날아가는 중이게) 기지, 지구, 지구-달, 태양계, 서울, 화성 도시를 차례로 본다.
## 화면이 필요하다:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/perf_probe.gd -- [--days 400] [--frames 90] [--only seoul,mars]

var main: Control
var frame := 0
var days := 400
var frames := 90
var only := PackedStringArray()
var _steps: Array = []
var _step := 0
var _wait := 0
var _until: Callable
var _samples: Array = []
var _last_us := 0
var _rows: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	i = args.find("--frames")
	if i >= 0 and i + 1 < args.size():
		frames = int(args[i + 1])
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_hours(n: int) -> void:
	for _i in range(n):
		if main.modal.visible:
			if main.modal.context == "storm":
				main.modal.visible = false
				main._on_modal_choice("storm", "lottery")
			else:
				main.modal.visible = false
		main._step()
	main._refresh_live()


func _settled(w: WorldView) -> bool:
	return not w.cam.flying() and w._descent.is_empty()


func _metro_done(w: WorldView, key: String) -> bool:
	if not _settled(w) or not w.metro_grounds.has(key):
		return false
	return (w.metro_grounds[key]["city"] as MetroCity)._phase == 3


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		_run_hours(days * 24)
		main._set_speed(0)
		main.modal.visible = false
		main._set_view("world")
		var korea := Astro.latlon(36.0, 128.0)
		_steps = [
			["moon_base", func(): main._on_colony_view(main.colonies.index_of_site("moon_shackleton")), func(): return _settled(w)],
			["moon_base_low", func(): w.cam.dist = 0.25; w.cam.tilt = deg_to_rad(70.0)],
			["earth_globe", func(): w.cam.look_at_surface("earth", korea, 6371.0 * 1.2, 0.0, Vector3(0, 0, 1))],
			["earth_moon", func(): w.show_earth_moon(), func(): return _settled(w)],
			["solar", func(): w.cam.look_from_space("sun", 3.4e8, 0.9, 0.75)],
			["seoul", func(): w.fly_to_metro("metro_seoul"), func(): return _metro_done(w, "metro_seoul")],
			["seoul_low", func(): w.cam.dist = 4.5; w.cam.tilt = deg_to_rad(72.0)],
			["mars", func(): main._on_colony_view(main.colonies.index_of_site("mars_hellas")), func(): return _settled(w)],
			["mars_low", func(): w.cam.dist = 0.3; w.cam.tilt = deg_to_rad(65.0)],
		]
		if not only.is_empty():
			_steps = _steps.filter(func(st: Array) -> bool: return String(st[0]) in only)
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _until.is_valid():
		if not _until.call() and _wait > -3000:
			_wait -= 1
			return false
		_until = Callable()
		_wait = 20
		return false
	if _step >= _steps.size() * 2:
		_report()
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 20
		if s.size() > 2:
			_until = s[2]
			_wait = 0
		_samples.clear()
		_last_us = 0
		_step += 1
		return false
	# 재기: frames 프레임 동안
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_samples.append({
			"frame_ms": (now - _last_us) / 1000.0,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"place_us": float(w.perf.get("place_us", 0)), "city_us": float(w.perf.get("city_us", 0)),
			"overlay_us": float(w.perf.get("overlay_us", 0)), "routes_us": float(w.perf.get("routes_us", 0)),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	_last_us = now
	if _samples.size() >= frames:
		_rows.append([s[0], _avg(_samples)])
		_step += 1
	return false


func _avg(list: Array) -> Dictionary:
	var out := {}
	for k in list[0]:
		var sum := 0.0
		for d in list:
			sum += float(d[k])
		out[k] = sum / list.size()
	return out


func _report() -> void:
	print("perf: %-14s %9s %9s %8s %8s %9s %8s %7s %7s %10s" % ["scene", "frame_ms", "proc_ms", "place", "city",
		"overlay", "routes", "draws", "objs", "prims"])
	for r in _rows:
		var d: Dictionary = r[1]
		print("perf: %-14s %9.1f %9.2f %8.0f %8.0f %9.0f %8.0f %7.0f %7.0f %10.0f" % [r[0], d["frame_ms"], d["process_ms"],
			d["place_us"], d["city_us"], d["overlay_us"], d["routes_us"], d["draws"], d["objects"], d["prims"]])
	print("perf: gpu ", RenderingServer.get_video_adapter_name(), " · ", RenderingServer.get_video_adapter_vendor(),
		" · type ", RenderingServer.get_video_adapter_type())
