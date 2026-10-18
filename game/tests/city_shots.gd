extends SceneTree
## 도시 계획 스크린숏 — 길이 먼저 나고 블록이 구획이 되는 기본 도시, 길 종류와 교차로, 길 내기(곡선)·구획·땅 고치기 도구,
## 지구 도시에서 해수면 아래로 판 땅에 물이 차는 모습.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/city_shots.gd -- --out /tmp/shots [--days 60] [--only moon_top,flood]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 60
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


func _shot(name: String, full := false) -> void:
	var img := root.get_texture().get_image()
	if not full:
		var k := Vector2(img.get_size()) / root.get_visible_rect().size
		var g: Rect2 = main.city_area.get_global_rect()
		img = img.get_region(Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)))
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _settled(w: WorldView) -> bool:
	return not w.cam.flying() and w._descent.is_empty()


## 카메라: 기지 모형 좌표 p 위로 (dist km, 기울기 °, 바라보는 방향 = 모형 좌표 수평 단위 벡터)
func _aim(w: WorldView, p: Vector2, dist: float, tilt_deg: float, look := Vector2(-1, -1)) -> void:
	var g: SiteGround = w.ground
	var dir := (g.site_dir() * g.radius_m() + g.site_frame().x * p.x + g.site_frame().y * p.y).normalized()
	w._descent.clear()
	var f := g.site_frame() * Vector3(look.x, look.y, 0.0).normalized()
	w.cam.look_at_surface(g.body, dir, dist, deg_to_rad(tilt_deg), f)


## 그 도시가 해를 볼 때까지 시간을 흘린다 (그늘이면 땅의 높낮이가 보이지 않는다)
func _until_lit() -> void:
	for _i in 24 * 30:
		if not main.sim.is_dark():
			break
		_run_hours(1)


## 점에서 가장 가까운 블록의 가운데 (블록 안의 점)
func _block_near(plan: CityPlan, p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	for bl in plan.blocks():
		var c: Vector2 = bl["center"]
		if Geometry2D.is_point_in_polygon(c, bl["poly"]) and c.distance_to(p) < best_d:
			best_d = c.distance_to(p)
			best = c
	return best


## 교차로가 많은 곳: 기지 가운데에서 가장 가까운, 길이 넷 모이는 꼭짓점
func _crossing(plan: CityPlan) -> Vector2:
	var best := plan.hub()
	var best_d := INF
	for i in plan.nodes.size():
		if plan.degree(i) >= 4:
			var d := (plan.nodes[i] as Vector2).distance_to(plan.hub() + Vector2(60, 30))
			if d < best_d:
				best_d = d
				best = plan.nodes[i]
	return best


## 바다에 가장 가까운 땅 (지구 도시): 물 몫이 있는 꼭짓점 가운데 기지에 가장 가까운 것 → 그 앞의 뭍
func _shore(g: SiteGround) -> Vector2:
	var best := Vector2.INF
	for idx in g._wet_base.size():
		if g._wet_base[idx] > 200:
			@warning_ignore("integer_division")
			var p := g._vert_pos(idx / g._segs, idx % g._segs)
			if p.length() < best.length():
				best = p
	return best


func _flood_setup(w: WorldView) -> void:
	var g: SiteGround = w.ground
	var plan: CityPlan = main.plan
	var shore := _shore(g)
	print("earth sea_z %.1f m, plateau %.1f m, nearest sea %s (%.0f m)" % [g.sea_z, g._plateau_m, str(shore), shore.length()])
	# 바다 쪽으로, 둘레 110 m 안에 건물·길이 없는 곳을 판다 (해수면 아래까지 — 비탈이 넓다)
	var dir := shore.normalized() if shore != Vector2.INF else Vector2(1, 0)
	var spot := Vector2.INF
	var fixed: Dictionary = plan._fixed_cells()
	var cm := CityPlan.cell_m()
	for rr in range(200, 680, 30):
		for da in [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6]:
			var p := dir.rotated(da) * float(rr)
			var clear := true
			for key in fixed:
				if (Vector2(key) * cm).distance_to(p) < 110.0:
					clear = false
					break
			if clear:
				spot = p
				break
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		print("no free spot to dig")
		return
	var need := g.base_height_m(spot) - g.sea_z + 3.0
	var steps := clampi(int(ceil(need)), 1, int(LayoutData.terrain()["max_depth_m"]))
	print("dig at %s, ground %.1f m, %d m deep" % [str(spot), g.base_height_m(spot), steps])
	for _i in steps:
		plan.edit_terrain(spot, 24.0, "dig", 1.0)
	w.city.update(0.0, 0)
	print("flooded cells %d, vertices %d" % [plan.flood.size(), g.flooded.size()])
	_aim(w, spot, 0.3, 48.0)


## 서울에 우주 시설을 짓는다: 넷은 1~2단계까지 다 짓고, 하나는 짓는 중
func _metro_setup() -> void:
	var col: Colonies = main.colonies
	var fn := col.metro_fn
	var home: CitySim = col.list[0]["sim"]
	home.support = 9000.0
	for fac in ["space_park", "research", "cargo_hub", "outreach"]:
		fn.build("metro_seoul", fac, col, 0)
	_run_hours(24 * 31)
	for fac in ["space_park", "research"]:
		fn.build("metro_seoul", fac, col, 0)
	_run_hours(24 * 46)
	fn.build("metro_seoul", "emigration", col, 0)
	_run_hours(24 * 6)
	main._set_speed(0)


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
		var tool: PlaceTool = main.tool
		_steps = [
			["moon_top", func():
				_until_lit()
				_aim(w, main.plan.hub() + Vector2(10, 10), 0.75, 0.0), func(): return _settled(w)],
			["moon_tilt", func(): _aim(w, main.plan.hub() + Vector2(40, 40), 0.42, 58.0), func(): return _settled(w)],
			["moon_cross", func(): _aim(w, _crossing(main.plan), 0.11, 52.0), func(): return _settled(w)],
			["road_tool", func():
				# 빈 블록의 모서리에서 길을 따라 나가다 블록 안으로 굽는 도로 (곡선)
				var plan: CityPlan = main.plan
				var bl := {}
				var best := INF
				for b in plan.blocks():
					var c: Vector2 = b["center"]
					var empty := true
					for e in plan.buildings:
						if Geometry2D.is_point_in_polygon(Vector2(float(e["x"]), float(e["y"])), b["poly"]):
							empty = false
							break
					if empty and c.distance_to(plan.hub()) < best:
						best = c.distance_to(plan.hub())
						bl = b
				var face: PackedVector2Array = bl["face"]
				var c0 := face[0]
				var c1 := face[1]
				var side := c0.distance_to(c1)
				var t := (c1 - c0).normalized()
				var inward := Vector2(-t.y, t.x)
				if not Geometry2D.is_point_in_polygon(c0 + t * side * 0.5 + inward * 6.0, face):
					inward = -inward
				_aim(w, (c0 + c1) * 0.5 + inward * side * 0.45, 0.13, 38.0, -inward)
				main._begin_tool("road")
				tool.set_road_type("street")
				tool.road_from = c0
				tool.road_dir = t
				tool.set_curve(true)
				tool.hover(c0 + t * side * 0.82 + inward * side * 0.8), func(): return _settled(w)],
			["zone_tool", func():
				main._begin_tool("zone")
				tool.set_zone_kind("farm")
				tool.hover(_block_near(main.plan, main.plan.hub() + Vector2(60, 50))), func(): return _settled(w)],
			["mars_city", func():
				tool.stop()
				main._on_colony_view(main.colonies.index_of_site("mars_hellas")), func(): return _settled(w)],
			["mars_roads", func():
				_until_lit()
				_aim(w, main.plan.hub() + Vector2(40, 40), 0.4, 60.0), func(): return _settled(w)],
			["terrain_tool", func():
				main._begin_tool("terrain")
				var p: Vector2 = main.plan.hub() + Vector2(-150, 210)
				for _i in 8:
					main.plan.edit_terrain(p, 24.0, "dig", 1.0)
				for _i in 6:
					main.plan.edit_terrain(p + Vector2(70, -30), 12.0, "raise", 1.0)
				tool.hover(p + Vector2(40, 0))
				_aim(w, p + Vector2(30, -10), 0.3, 55.0), func(): return _settled(w)],
			["land_tool", func():
				# 확장: 기지 밖의 구역을 가리킨다
				main._begin_tool("land")
				var plan: CityPlan = main.plan
				main.sim.stock["parts"] = float(main.sim.stock["parts"]) + 800.0
				main.sim.support += 3000.0
				var pick := {}
				for st in plan.land_candidates():
					if bool(st["ok"]) and plan._parcel_base(st["cell"]) == 0:
						pick = st
						break
				var c: Vector2 = (pick["rect"] as Rect2).get_center() if not pick.is_empty() else plan.hub()
				tool.hover(c)
				_aim(w, c.lerp(plan.hub(), 0.4), 0.7, 48.0), func(): return _settled(w)],
			["land_bought", func():
				# 구역 넷을 사서 빈 블록에 농장을 세운다 (비탈이면 기초 위에)
				_until_lit()
				var plan: CityPlan = main.plan
				var last := Rect2()
				var n := 0
				for st in plan.land_candidates():
					if n >= 4:
						break
					if bool(st["ok"]) and plan._parcel_base(st["cell"]) == 0 and plan.buy_parcel(st["cell"], main.sim):
						n += 1
						last = st["rect"]
				var fresh: Array = []
				for b in plan.blocks():
					if String(b["district"]) == "" and not plan.layout.base_has(b["center"]):
						plan.set_district(b["center"], "farm")
						fresh.append(b)
				tool.stop()
				main.sim.stock["parts"] = float(main.sim.stock["parts"]) + 800.0
				for b in fresh:
					for kind in ["hydroponics", "food_store"]:
						var at := CityPlan.snap_center(kind, b["center"], 0)
						if plan.check(kind, at, 0, main.sim)["reason"] == "":
							tool.start_build(kind)
							tool.hover(at)
							tool.commit(false)
							break
				tool.stop()
				var placed := 0
				for e in plan.buildings:
					if not plan.layout.base_has(Vector2(float(e["x"]), float(e["y"]))):
						placed += 1
				print("land shots: bought %d, fresh blocks %d, buildings on new land %d" % [n, fresh.size(), placed])
				_aim(w, last.get_center().lerp(plan.hub(), 0.25), 0.5, 55.0), func(): return _settled(w)],
			["metro_card", func():
				tool.stop()
				_metro_setup()
				var m := Metros.of("metro_seoul")
				w.anchors.go({"kind": "metro", "id": "metro_seoul", "name": m["name"], "body": "earth", "dir": m["dir"]}),
				func(): return _metro_done(w, "metro_seoul")],
			["metro_campus", func():
				w.cam.dist = 9.0
				w.cam.tilt = deg_to_rad(55.0), func(): return _settled(w)],
			["flood", func():
				tool.stop()
				main._on_colony_view(main.colonies.index_of_site("earth_naro"))
				_until_lit(), func(): return _settled(w)],
			["flood_dug", func(): _flood_setup(w), func(): return _settled(w)],
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
		_wait = 40
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	@warning_ignore("integer_division")
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 10
		if s.size() > 2:
			_until = s[2]
			_wait = 0
	else:
		@warning_ignore("integer_division")
		_shot("city_%02d_%s" % [_step / 2 + 1, s[0]], String(s[0]).ends_with("_tool") or String(s[0]) in ["metro_card", "land_bought"])
	_step += 1
	return false
