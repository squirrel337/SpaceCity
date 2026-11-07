extends SceneTree
## 건물 단면도 스크린숏 — 30일을 돌린 고향에서 여러 계열의 단면도를 연다 (디스플레이가 필요하다).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
##     --script res://tests/section_shots.gd -- --out /tmp/shots [--days 30] [--ids hab_module,hydroponics]

var main: Control
var frame := 0
var out_dir := "user://shots"
var days := 30
var ids := ["hab_module", "regolith_dome", "hab_tower", "hydroponics", "electrolyzer", "tank_farm", "fission_1mw", "solar_tower",
	"radiator", "landing_pad", "excavator", "research_lab", "medical_bay", "green_commons"]
var _i := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var k := args.find("--out")
	if k >= 0 and k + 1 < args.size():
		out_dir = args[k + 1]
	k = args.find("--days")
	if k >= 0 and k + 1 < args.size():
		days = int(args[k + 1])
	k = args.find("--ids")
	if k >= 0 and k + 1 < args.size():
		ids = Array(args[k + 1].split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 4:
		main._on_modal_choice("start", "auto")
		main._set_speed(0)
		for _h in range(days * 24):
			if main.modal.visible:
				main.modal.visible = false
			main._step()
		main._set_speed(0)
		main.modal.visible = false
		main._refresh_live()
		_wait = 20
		return false
	if frame < 4:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= ids.size() * 2:
		quit(0)
		return true
	var id := String(ids[_i / 2])
	if _i % 2 == 0:
		main.cross.open(main.sim, main.colonies.list[main.active], id)
		_wait = 8
	else:
		var img := root.get_texture().get_image()
		img.save_png(out_dir.path_join("section_%02d_%s.png" % [_i / 2 + 1, id]))
		print("shot ", id, " ", main.cross.summary())
	_i += 1
	return false
