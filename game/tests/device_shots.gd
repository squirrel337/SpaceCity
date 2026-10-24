extends SceneTree
## 기기 점검 — 창 크기 하나(--resolution)에서 두 언어마다 위 막대가 화면 폭에 들어오는지, 옆 탭 이름이 잘리는지, 옆 패널이
## 긴 글에 밀려 넓어지는지(탭마다), 화면 밖으로 나간 패널이 있는지, 터치(--touch)면 누르는 곳이 44 px(1280×720 기준 UI 좌표)보다
## 작은지 보고 도시·교통 탭·항로 지도 스크린숏을 남긴다 (디스플레이가 필요하다). 크기마다 한 번씩 띄운다 —
## PC 1280×720·1366×768·1920×1080, 폰 2400×1080·2340×1080·1600×720, 태블릿 2048×1536·2560×1600:
##   for s in 1280x720 1366x768 1920x1080 2400x1080 2340x1080 1600x720 2048x1536 2560x1600; do
##     xvfb-run -a -s "-screen 0 2560x1600x24" godot --path game --rendering-driver opengl3 --resolution $s \
##       --script res://tests/device_shots.gd -- --out /tmp/device --touch [--langs ko,en] [--days 30]; done
## 결과: 언어마다 한 줄 (UI 크기 · 막대 폭 · 잘린 탭 · 작은 단추 수 · 넘친 패널 · 아래 단추 줄 수 · 옆 패널 폭), 작은 단추 목록은
## report_<크기>.txt에. 문제가 있으면 끝에 "문제 N".

const MIN_TOUCH := 44.0

var main: Control
var frame := 0
var out_dir := "user://device"
var langs: Array = ["ko", "en"]
var days := 30
var size_tag := ""
var failures := 0
var _steps: Array = []
var _step := 0
var _wait := 0
var _report := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--langs")
	if i >= 0 and i + 1 < args.size():
		langs = Array(args[i + 1].split(","))
	i = args.find("--days")
	if i >= 0 and i + 1 < args.size():
		days = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)


func _run_hours(n: int) -> void:
	for _i in range(n):
		if main.modal.visible:
			main.modal.visible = false
		main._step()
	main._refresh_live()


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		_steps.append(["", func():
			main.modal.visible = false
			main._on_modal_choice("start", "auto")
			main._set_speed(0)
			_run_hours(24 * days)
			main.modal.visible = false])
		var ws := DisplayServer.window_get_size()
		size_tag = "%dx%d" % [ws.x, ws.y]
		for lang in langs:
			var lg: String = lang
			var sz := size_tag
			_steps.append(["", func():
				I18n.apply(lg)
				main._on_lang_changed()
				main._set_view("world")
				main._select_tab("life")])
			_steps.append(["%s_%s_city" % [lg, sz], func(): _audit("%s %s" % [lg, sz])])
			for tab in ["power", "build", "research", "colony", "log", "transport"]:
				var tb: String = tab
				_steps.append(["", func(): main._select_tab(tb)])
				_steps.append(["%s_%s_%s" % [lg, sz, tb] if tb == "transport" else "", func(): _audit_side("%s %s %s" % [lg, sz, tb])])
			_steps.append(["%s_%s_map" % [lg, sz], func():
				main._set_view("map")
				main.dv_map.selected = "mars"
				main.dv_map.refresh(true)])
			_steps.append(["", func(): _audit_map("%s %s map" % [lg, sz])])
		_wait = 20
		return false
	if frame < 3 or _steps.is_empty():
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _step > 0:
		var name: String = _steps[_step - 1][0]
		if name != "":
			var img := root.get_texture().get_image()
			img.save_png(out_dir.path_join(name + ".png"))
	if _step >= _steps.size():
		var f := FileAccess.open(out_dir.path_join("report_%s.txt" % size_tag), FileAccess.WRITE)
		f.store_string("\n".join(_report) + "\n")
		f.close()
		print("device: %s · 문제 %d → %s" % [size_tag, failures, out_dir])
		I18n.apply("ko")
		quit(0)
		return true
	(_steps[_step][1] as Callable).call()
	_step += 1
	_wait = 12
	return false


## 지금 화면 크기에서 넘치는 것·잘리는 것·작은 단추
func _audit(tag: String) -> void:
	var ui := root.get_visible_rect().size
	var bar: Control = main.date_label.get_parent().get_parent()
	var bar_min := bar.get_combined_minimum_size().x
	var clipped: Array = []
	for k in main.tab_buttons:
		var b: Button = main.tab_buttons[k]
		var font := b.get_theme_font("font")
		var fs := b.get_theme_font_size("font_size")
		var tw := font.get_string_size(I18n.t(b.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if b.autowrap_mode != TextServer.AUTOWRAP_OFF:      # 두 줄로 — 낱말마다 들어가나
			tw = 0.0
			for w in I18n.t(b.text).split(" "):
				tw = maxf(tw, font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if tw > b.size.x - 4.0:
			clipped.append("%s(%d>%d)" % [I18n.t(b.text), int(tw), int(b.size.x - 4.0)])
	var small: Array = []
	_small_buttons(main, small)
	var over: Array = []
	for c in main.get_children():
		if c is Control and (c as Control).visible:
			var r := (c as Control).get_global_rect()
			if r.end.x > ui.x + 1.0 or r.end.y > ui.y + 1.0 or r.position.x < -1.0 or r.position.y < -1.0:
				over.append("%s %s" % [c.name, r])
	# 아래 단추 줄 (3D·목록·항로 … 범위): 줄 수와 도시 화면 밖으로 나간 단추
	var vs: Control = main.view_switch
	var lines := {}
	var out_of_area := 0
	var area := (main.city_area as Control).get_global_rect()
	for b in vs.get_children():
		if (b as Control).is_visible_in_tree():
			lines[int((b as Control).get_global_rect().position.y)] = true
			if (b as Control).get_global_rect().end.x > area.end.x + 1.0:
				out_of_area += 1
	# 옆 패널: 440 px보다 넓어졌으면 무엇이 넓힌 것인지 (줄바꿈 없는 긴 글)
	var side: Control = (main.tab_buttons.values()[0] as Control).get_parent().get_parent().get_parent()
	var wide: Array = []
	if side.size.x > 441.0:
		_wide(side, side.size.x - 30.0, wide)
	var bad := bar_min > ui.x or not clipped.is_empty() or not over.is_empty() or out_of_area > 0 or not wide.is_empty() \
		or (ThemeFactory.touch() and not small.is_empty())
	if bad:
		failures += 1
	var line := "%s · UI %dx%d · 위 막대 %d%s · 잘린 탭 %d %s · 작은 단추 %d · 넘친 패널 %d %s · 아래 단추 %d줄%s · 옆 패널 %d%s" % [tag,
		int(ui.x), int(ui.y), int(bar_min), " (넘침)" if bar_min > ui.x else "", clipped.size(), ", ".join(clipped), small.size(),
		over.size(), ", ".join(over), lines.size(), " (도시 화면 밖 %d)" % out_of_area if out_of_area > 0 else "", int(side.size.x),
		(" — 넓힌 것: " + " | ".join(wide.slice(0, 4))) if not wide.is_empty() else ""]
	print("device: ", line)
	_report.append(line)
	for s in small:
		_report.append("    " + String(s))


## 항로 지도: 오른쪽 아래 카드가 지도 안에 있나 (글이 길면 카드가 넓어져 오른쪽이 잘린다)
func _audit_map(tag: String) -> void:
	var map: Control = main.dv_map
	var card: Control = map._card
	var r := card.get_rect()
	if r.end.x <= map.size.x + 1.0 and r.end.y <= map.size.y + 1.0:
		return
	var wide: Array = []
	_wide(card, map.size.x - r.position.x - 12.0 - 30.0, wide)
	failures += 1
	var line := "%s · 카드 %dx%d가 지도 %dx%d 밖으로 — 넓힌 것: %s" % [tag, int(r.size.x), int(r.size.y), int(map.size.x), int(map.size.y),
		" | ".join(wide.slice(0, 4))]
	print("device: ", line)
	_report.append(line)


## 탭마다: 옆 패널이 440 px보다 넓어졌나, (터치면) 작은 단추
func _audit_side(tag: String) -> void:
	var side: Control = (main.tab_buttons.values()[0] as Control).get_parent().get_parent().get_parent()
	var small: Array = []
	if ThemeFactory.touch():
		_small_buttons(side, small)
	if side.size.x <= 441.0 and small.is_empty():
		return
	var wide: Array = []
	if side.size.x > 441.0:
		_wide(side, side.size.x - 30.0, wide)
	failures += 1
	var line := "%s · 옆 패널 %d%s · 작은 단추 %d" % [tag, int(side.size.x), (" — 넓힌 것: " + " | ".join(wide.slice(0, 4))) if not wide.is_empty() else "",
		small.size()]
	print("device: ", line)
	_report.append(line)
	for s_ in small:
		_report.append("    " + String(s_))


## 최소 폭이 limit를 넘는 가장 깊은 컨트롤 (글이 있으면 글 앞부분)
func _wide(n: Node, limit: float, out: Array) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		if (c as Control).get_combined_minimum_size().x <= limit:
			continue
		var before := out.size()
		_wide(c, limit, out)
		if out.size() == before:
			var kids := PackedStringArray()
			if c is Container:
				for k in c.get_children():
					if k is Control and (k as Control).is_visible_in_tree():
						kids.append("%s %d '%s'" % [k.get_class(), int((k as Control).get_combined_minimum_size().x), _text_of(k).left(24)])
			# 넘지는 않지만 가장 넓은 자식을 끝까지 따라간다 (어느 글이 폭을 정하나)
			var chain := PackedStringArray()
			var at: Node = c
			for _d in 8:
				var best: Control = null
				for k in at.get_children():
					if k is Control and (k as Control).is_visible_in_tree() and (best == null or
							(k as Control).get_combined_minimum_size().x > best.get_combined_minimum_size().x):
						best = k
				if best == null:
					break
				chain.append("%s %d '%s'" % [best.get_class(), int(best.get_combined_minimum_size().x), _text_of(best).left(40)])
				at = best
			out.append("%s %d '%s'%s%s" % [c.get_class(), int((c as Control).get_combined_minimum_size().x), _text_of(c).left(50),
				(" [" + ", ".join(kids) + "]") if not kids.is_empty() else "", (" → " + " → ".join(chain)) if not chain.is_empty() else ""])


func _text_of(c: Node) -> String:
	if c is Label:
		return I18n.t((c as Label).text).replace("\n", " ")
	if c is Button:
		return I18n.t((c as Button).text).replace("\n", " ")
	return ""


func _small_buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is BaseButton and (c as Control).is_visible_in_tree():
			var b := c as Control
			var sz := b.size
			if sz.y < MIN_TOUCH - 0.5 or sz.x < MIN_TOUCH - 0.5:
				var label := ""
				if c is Button:
					label = I18n.t((c as Button).text)
				out.append("%dx%d %s · %s" % [int(sz.x), int(sz.y), label.left(30).replace("\n", " "), str(b.get_path()).trim_prefix(str(main.get_path()))])
		if c is Node:
			_small_buttons(c, out)
