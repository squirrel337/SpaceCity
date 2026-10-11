extends SceneTree
## 천체 겉모습 스크린숏 — 암석·얼음 천체의 기본 도시마다: 행성 전체, 도시 둘레 지역(수백 km), 지형 조각(수십 km),
## 도시 (디스플레이가 필요하다). GPU 굽기가 끝날 때까지 기다린다.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/body_shots.gd -- --out /tmp/bodies [--sites mars_hellas,titan_kraken] [--views globe,region,patch,city]

const SITES := ["mars_hellas", "mercury_prokofiev", "ceres_occator", "callisto_valhalla", "titan_adiri", "titan_kraken",
	"earth_naro", "earth_kourou", "mars_jezero", "ceres_ahuna", "moon_marius"]
const VIEWS := ["globe", "region", "patch", "city"]

var main: Control
var frame := 0
var out_dir := "user://bodies"
var sites: Array = SITES
var views: Array = VIEWS
var _steps: Array = []
var _step := 0
var _wait := 0
var _until: Callable


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--sites")
	if i >= 0 and i + 1 < args.size():
		sites = Array(args[i + 1].split(","))
	i = args.find("--views")
	if i >= 0 and i + 1 < args.size():
		views = Array(args[i + 1].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	img = img.get_region(Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)))
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name, " (bakes ", Baker.count, ")")


## 그 도시가 낮이 될 때까지 (모든 도시가 함께 흐른다), 해가 조금 높이 뜨게 몇 시간 더
func _to_light(s: CitySim) -> void:
	var guard := 0
	while s.is_dark() and guard < 24 * 60:
		main._step()
		guard += 1
	var day_h := float(s.C["illumination"].get("day_h", 24.0))
	var extra := int(clampf(day_h * 0.18, 0.0, 30.0))
	for _i in extra:
		if s.is_dark():
			break
		main._step()


## 굽기가 모두 끝났나 (천체 지도, 도시의 조각·지역 지도)
func _settled(w: WorldView) -> bool:
	if w.body_baker.busy() or Baker._busy:
		return false
	var g := w.ground as SiteSurface
	return g == null or (g.baked() and (g.has_cap() or not g.needs_cap()))


func _site_steps(w: WorldView, site_id: String) -> Array:
	var col: Colonies = main.colonies
	var idx := col.index_of_site(site_id)
	if idx < 0:
		# 기본 도시가 아닌 부지: 시험이라 바로 세운다
		col._found_at(site_id, int(col.hour), 7)
		idx = col.index_of_site(site_id)
		main._update_colony_ui()
	var sim: CitySim = col.list[idx]["sim"]
	var site := GameData.site(site_id)
	var body := String(site["body"])
	var r := float(Astro.bodies[body]["radius_km"])
	var steps: Array = []
	steps.append(["%s_city" % site_id, func():
		_to_light(sim)
		main._on_colony_view(idx),
		func(): return not w.cam.flying() and w._descent.is_empty() and _settled(w)])
	var dir := Astro.latlon(float(site["lat"]), float(site["lon"]))
	var g: SiteGround = w.ground_for(site_id)
	var head := g.site_frame() * Vector3(-0.3, -1.0, 0.0)
	if "patch" in views:
		steps.append(["%s_patch" % site_id, func(): w.cam.look_at_surface(body, dir, 22.0, deg_to_rad(62.0), head),
			func(): return _settled(w)])
	if "region" in views:
		steps.append(["%s_region" % site_id, func(): w.cam.look_at_surface(body, dir, minf(r * 0.25, 650.0), deg_to_rad(35.0), head),
			func(): return _settled(w)])
	if "globe" in views:
		steps.append(["%s_globe" % site_id, func(): w.cam.look_at_surface(body, dir, r * 2.2, 0.0, head),
			func(): return _settled(w)])
	if not "city" in views:
		steps[0][0] = ""
	return steps


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		main.modal.visible = false
		main._set_view("world")
		for sid in sites:
			_steps.append_array(_site_steps(w, String(sid)))
		_wait = 20
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _until.is_valid():
		if not _until.call() and _wait > -6000:
			_wait -= 1
			return false
		_until = Callable()
		_wait = 8
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
	elif String(s[0]) != "":
		_shot("body_%02d_%s" % [_step / 2 + 1, s[0]])
	_step += 1
	return false
