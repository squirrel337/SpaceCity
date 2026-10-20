extends Control
## 시작 화면: 창이 뜨자마자 보인다 (작은 DailyPack 말고는 다른 스크립트를 부르지 않아 곧바로 읽힌다). 게임 화면(main.tscn)과 그 스크립트
## 수십 개를 다른 스레드에서 읽고 엮는 동안 진행을 보이고, 다 되면 게임 화면으로 바꾼다. 곧 쓸 큰 지도(지구 해안)도
## 함께 미리 읽는다. 휴대폰에서는 스크립트를 엮는 데 몇 초가 걸린다 — 그동안 멈춘 빈 화면이 아니게.
## '이어 하기'에 쓸 저장도 다른 스레드에서 읽고 풀어 둔다 — JSON과 식민지마다 수천 줄의 일별 기록 (누른 순간에 풀면 그만큼 멈춘다).

const MAIN := "res://ui/main.tscn"
const AHEAD := ["res://art/planets/earth_coast.png"]
const SAVE := "user://spacecity_save.json"       # main.gd의 SAVE_PATH

var _bar: ProgressBar
var _note: Label
var _t := 0.0
var _save_task := -1
var _save: Array = []                            # [파일 시각, 푼 자료]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("0f1218")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(320, 0)
	box.position -= Vector2(160, 60)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "SpaceCity"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("e8e4da"))
	box.add_child(title)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(320, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("f0a848")
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_note = Label.new()
	_note.text = "불러오는 중"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color("8a909c"))
	box.add_child(_note)
	ResourceLoader.load_threaded_request(MAIN)
	for p in AHEAD:
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
	if FileAccess.file_exists(SAVE):
		_save_task = WorkerThreadPool.add_task(_read_save, false, "save")


func _read_save() -> void:
	var stamp := FileAccess.get_modified_time(SAVE)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if data is Dictionary:
		DailyPack.unpack_save(data)
	_save = [stamp, data]


## 저장 읽기를 기다려 게임에 넘긴다 (main.gd가 파일이 그대로인지 보고 쓴다)
func _hand_over() -> void:
	if _save_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_save_task)
	_save_task = -1
	get_tree().root.set_meta("boot_save", _save)


func _exit_tree() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1


func _process(delta: float) -> void:
	_t += delta
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(MAIN, prog)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_bar.value = maxf(_bar.value, float(prog[0]) * 0.95)
		_note.text = "불러오는 중" + ".".repeat(1 + int(_t * 3.0) % 3)
		return
	if st != ResourceLoader.THREAD_LOAD_LOADED:
		_hand_over()
		get_tree().change_scene_to_file(MAIN)        # 다른 스레드로 못 읽었으면 그냥 (멈추더라도)
		set_process(false)
		return
	_bar.value = 1.0
	_note.text = "화면을 짓는 중"
	set_process(false)
	_go.call_deferred()


## 게임 화면으로 (그 프레임은 화면을 짓느라 길다 — 이 화면이 그대로 보인다). 미리 읽은 지도는 캐시에 남게 받아 둔다
func _go() -> void:
	await get_tree().process_frame                   # '화면을 짓는 중'이 한 번 그려지게
	var scene: PackedScene = ResourceLoader.load_threaded_get(MAIN)
	var keep: Array = []
	for p in AHEAD:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			keep.append(ResourceLoader.load_threaded_get(p))
	get_tree().root.set_meta("boot_keep", keep)       # 게임이 load()로 다시 부를 때까지 캐시에 둔다
	_hand_over()
	get_tree().change_scene_to_packed(scene)
