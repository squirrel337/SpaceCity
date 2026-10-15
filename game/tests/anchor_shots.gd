extends SceneTree
## 카메라 고정점 스크린숏 — 기본 도시로 시작해 며칠 흐른 뒤, 위쪽 경로 막대로 고정점을 차례로 고른다:
## 우리 은하 전체, 이웃 별, 태양계, 날아가는 수송선, 지구, 서울, 화성의 도시, 달 기지 (화면 전체를 찍어 경로 막대도 보이게).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/anchor_shots.gd -- --out /tmp/shots [--days 400] [--only galaxy,ship]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 400
var only := PackedStringArray()
var _steps: Array = []
var _step := 0
var _wait := 0
var _until: Callable


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	i = args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
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


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name, " · ", " › ".join(main.world.anchors.path().map(func(a): return String(a["name"]))))


func _settled(w: WorldView) -> bool:
	return not w.cam.flying() and w._descent.is_empty()


func _go(w: WorldView, kind: String, id: String) -> void:
	var a := {}
	if kind == "ship":
		var ships := w.anchors.ships()
		if ships.is_empty():
			print("no ship in flight")
			return
		a = ships[0]
	elif kind == "metro":
		var m := Metros.of(id)
		a = {"kind": "metro", "id": id, "name": m["name"], "body": "earth", "dir": m["dir"]}
	elif kind == "body":
		a = CamAnchors.body(id)
	else:
		a = {"kind": kind, "id": id, "name": id}
	w.anchors.go(a)


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
		_steps = [
			["galaxy", func(): _go(w, "galaxy", "galaxy"), func(): return _settled(w)],
			["stars", func(): _go(w, "stars", "stars"), func(): return _settled(w)],
			["system", func(): _go(w, "system", "sun"), func(): return _settled(w)],
			["ship", func(): _go(w, "ship", ""), func(): return _settled(w)],
			["earth", func(): _go(w, "body", "earth"), func(): return _settled(w)],
			["seoul", func(): _go(w, "metro", "metro_seoul"), func(): return _settled(w)],
			["mars_city", func(): main._on_colony_view(main.colonies.index_of_site("mars_hellas")), func(): return _settled(w)],
			["moon_base", func(): main._on_colony_view(main.colonies.index_of_site("moon_shackleton")), func(): return _settled(w)],
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
		if not _until.call() and _wait > -2000:
			_wait -= 1
			return false
		_until = Callable()
		_wait = 30
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 10
		if s.size() > 2:
			_until = s[2]
			_wait = 0
	else:
		_shot("anchor_%02d_%s" % [_step / 2 + 1, s[0]])
	_step += 1
	return false
