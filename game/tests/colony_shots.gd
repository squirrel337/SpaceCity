extends SceneTree
## (임시) 다른 천체 부지의 3D 땅 확인

var main: Control
var frame := 0
var out_dir := "user://shots"
var _steps: Array = []
var _step := 0
var _wait := 0
var site := "mars_hellas"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--site")
	if i >= 0 and i + 1 < args.size():
		site = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var k := Vector2(img.get_size()) / root.get_visible_rect().size
	var g: Rect2 = main.city_area.get_global_rect()
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k))
	img.get_region(r).save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _process(_delta: float) -> bool:
	frame += 1
	var w: WorldView = main.world if main else null
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		main.modal.visible = false
		var s := CitySim.new(1, 40.0, "good", site)
		for _h in 24 * 30:
			s.advance_hour()
		var guard := 0
		while not s.is_dark() and guard < 24 * 40:
			s.advance_hour()
			guard += 1
		while s.is_dark() and guard < 24 * 80:
			s.advance_hour()
			guard += 1
		var il: Dictionary = s.C["illumination"]
		if String(il.get("model", "")) == "rotation":
			for _h in int(float(il["day_h"]) * float(il["light_frac"]) * 0.4):
				s.advance_hour()
		w.set_sim(s)
		var g: SiteGround = w.ground
		w.set_colonies([{"name": "섀클턴", "site": "moon_shackleton", "body": "moon", "dir": w.moon.site_dir(), "pop": 312, "active": false},
			{"name": String(GameData.site(site)["name"]), "site": site, "body": g.body, "dir": g.site_dir(), "pop": 40, "active": true}])
		_steps = [
			["home", func(): w.home(false)],
			["wide", func(): w.cam.look_at_surface(g.body, g.site_dir(), 4.5, deg_to_rad(62.0), g.site_frame() * Vector3(-1.0, -1.0, 0.0))],
			["region", func(): w.cam.look_at_surface(g.body, g.site_dir(), 60.0, deg_to_rad(50.0), g.site_frame() * Vector3(-1.0, -1.0, 0.0))],
			["globe", func(): w.cam.look_from_space(g.body, g.radius_km() * 3.2, 0.8, -0.35)],
		]
		_wait = 30
		return false
	if frame < 4 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step >= _steps.size() * 2:
		quit(0)
		return true
	var s: Array = _steps[_step / 2]
	if _step % 2 == 0:
		(s[1] as Callable).call()
		_wait = 8
	else:
		_shot("%s_%02d_%s" % [site, _step / 2 + 1, s[0]])
		print("  hour ", w.sim.hour, " dark ", w.sim.is_dark(), " main.sim ", main.sim.site_id, " ground ", w.ground.body)
	_step += 1
	return false
