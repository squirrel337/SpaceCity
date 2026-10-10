extends SceneTree
## art/models.json의 3D 모형을 게임과 같은 렌더러로 그려 한 장의 PNG로 모은다 (화면이 있어야 한다: Xvfb).
##   xvfb-run -a godot --path game --rendering-driver opengl3 --script res://tools/art/model_sheet.gd -- \
##       --out models.png [--cols 6] [--cell 320] [--night] [--yaw 45] [--models 다른/models.json] hab_module hab_module:2 ...
## 이름만 주면 건물(변형 0), "이름:v"는 변형 v, "vehicles/이름"은 탈것, "all"은 건물 전부, "all:v"는 그 변형 전부,
## "every"는 건물마다 모든 변형. --models는 이름보다 앞에 둔다.

var _out := "models.png"
var _cols := 6
var _cell := 320
var _night := false
var _yaw := 45.0
var _sun_turn := -40.0
var _items: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--out":
				_out = args[i + 1]
				i += 1
			"--cols":
				_cols = int(args[i + 1])
				i += 1
			"--cell":
				_cell = int(args[i + 1])
				i += 1
			"--yaw":
				_yaw = float(args[i + 1])
				i += 1
			"--night":
				_night = true
			"--sun":
				_sun_turn = float(args[i + 1])
				i += 1
			"--models":
				ModelLib.path = args[i + 1]
				i += 1
			_:
				_add_item(a)
		i += 1
	create_timer(900.0).timeout.connect(func(): printerr("timeout"); quit(2))
	_run.call_deferred()


func _add_item(a: String) -> void:
	if a == "every":
		# 건물마다 모든 변형 (한 줄에 한 건물: --cols 5)
		var all_ids: Array = ModelLib.data()["buildings"].keys()
		all_ids.sort()
		for id in all_ids:
			for v in range(ModelLib.variants(id)):
				_items.append(["buildings", id, v])
		return
	if a.begins_with("all"):
		var v := int(a.get_slice(":", 1)) if a.contains(":") else 0
		var ids: Array = ModelLib.data()["buildings"].keys()
		ids.sort()
		for id in ids:
			if v < ModelLib.variants(id):
				_items.append(["buildings", id, v])
		return
	if a.begins_with("vehicles/"):
		_items.append(["vehicles", a.trim_prefix("vehicles/"), 0])
		return
	var id := a.get_slice(":", 0)
	var v := int(a.get_slice(":", 1)) if a.contains(":") else 0
	_items.append(["buildings", id, v])


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(_cell, _cell)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED if OS.has_environment("SHEET_FAST") else Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2a2b2e")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.45, 0.52)
	e.ambient_light_energy = 1.0 if not _night else 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6 if not _night else 0.05
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#5d5850")
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.01
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	ModelLib.set_night(1.0 if _night else 0.0)
	var images: Array[Image] = []
	for it in _items:
		var m := ModelLib.mesh(it[0], it[1], it[2])
		mi.mesh = m
		var aabb := m.get_aabb()
		var c := aabb.get_center()
		var r := maxf(aabb.size.length() * 0.5, 1.0)
		var yaw := deg_to_rad(_yaw)
		var pitch := deg_to_rad(28.0)
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
		cam.position = c + dir * dist
		cam.look_at(c, Vector3.UP)
		cam.near = maxf(0.05, dist - r * 2.0)
		cam.far = dist + r * 4.0
		# 해: 낮게, 카메라 왼쪽에서 (그림의 빛과 비슷하게)
		sun.rotation = Vector3(deg_to_rad(-26.0), yaw + deg_to_rad(_sun_turn), 0.0)
		sun.directional_shadow_max_distance = dist + r * 3.0
		for k in 3:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_label(img, "%s%s" % [it[1], (":%d" % it[2]) if it[0] == "buildings" else ""])
		images.append(img)
	var rows := ceili(float(images.size()) / _cols)
	var sheet := Image.create(_cell * _cols, _cell * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#1e1f22"))
	for n in images.size():
		sheet.blit_rect(images[n], Rect2i(Vector2i.ZERO, images[n].get_size()), Vector2i((n % _cols) * _cell, (n / _cols) * _cell))
	sheet.save_png(_out)
	print("model sheet: %d models -> %s" % [images.size(), _out])
	quit(0)


func _label(img: Image, _text: String) -> void:
	# 글자 없이 칸 경계만 (이름은 출력 순서로 안다)
	img.fill_rect(Rect2i(0, 0, img.get_width(), 2), Color("#3a3c42"))
	img.fill_rect(Rect2i(0, 0, 2, img.get_height()), Color("#3a3c42"))
