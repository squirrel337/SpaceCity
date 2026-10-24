class_name Tutorial
extends Control
## 튜토리얼 — 첫 한 시간을 열한 단계로 짚는다. 단계마다 할 일과 까닭을 카드로 말하고, 화면의 그 자리를 주황 테로 가리킨다.
## 할 일을 하면 (시간 흘리기, 화면 돌리기, 짓기, 연구 고르기, 탭 열기, 항로 지도) 다음 단계로 넘어간다 — 읽기만 하는 단계는 '다음'.
## 화면을 가리지 않는다 (카드만 누를 수 있다). 카드는 가리키는 자리가 아래쪽이면 위에, 위쪽이면 아래에 뜬다.
## 끝내거나 건너뛰면 설정에 남는다 (tutorial/done) — 새 게임 카드의 첫 선택지가 바뀐다. 메뉴의 '튜토리얼'로 다시 본다.

signal finished(skipped: bool)

const STEPS := [
	{"id": "hello", "title": "섀클턴 시드 시티에 온 것을 환영한다",
		"text": "당신은 달 남극 기지를 돌보는 관리 AI, 시드다. 정착민 120명이 숨 쉬고 먹고 일하는 도시를 직접 운영해 본다. " +
			"열한 단계로 첫 한 시간을 짚는다 — 언제든 '건너뛰기'로 끝낼 수 있다.", "target": "", "next": true},
	{"id": "chips", "title": "도시의 숨 — 위쪽 지표",
		"text": "산소 비축(일), CO₂, 축전, 식량, 인구, 사기, 신뢰. 숫자가 주황·빨강이면 위험하다. 가장 먼저 볼 것은 산소 비축 일수 — " +
			"0이 되면 사람이 죽는다.", "target": "chips", "next": true},
	{"id": "time", "title": "시간을 흘린다",
		"text": "'1×'를 눌러 시간을 흘려 본다 (3×·10×·최고는 더 빠르다, '정지'로 멈춘다). 반나절이 지나면 다음으로 넘어간다.",
		"target": "speed", "done": "time"},
	{"id": "camera", "title": "3D로 둘러본다",
		"text": "도시 화면을 끌어서 돌리고, 휠이나 두 손가락으로 확대·축소한다. 멀리 물러나면 달 전체와 지구, 태양계까지 간다. " +
			"'기지'를 누르면 돌아온다.", "target": "city", "done": "camera"},
	{"id": "life", "title": "생명유지 탭",
		"text": "오른쪽 첫 탭은 공기·물·식량·대피·선량의 하루 흐름이다. 막대가 짧아지면 무엇이 모자란지 여기서 본다. " +
			"CO₂ 제거기는 1기뿐이라 농장이 꺼지면 여유가 없다.", "target": "tab:life", "next": true},
	{"id": "build", "title": "짓는다",
		"text": "'건설' 탭에서 건물을 고르고 (태양광·축전지·전해조·농장 …) 도시 화면의 빈자리를 누르면 로봇이 짓기 시작한다. " +
			"하나를 지어 본다.", "target": "tab:build", "done": "build"},
	{"id": "research", "title": "연구를 고른다",
		"text": "'연구' 탭에서 기술 하나를 연구 차례에 넣는다. 기술은 새 건물과 규칙을 연다 — 극저온 추진제 생산은 행성간 함선의 연료 값을, " +
			"메가와트급 원자로는 핵열 화물선을 연다.", "target": "tab:research", "done": "research"},
	{"id": "auto", "title": "자동 운영과 위임",
		"text": "'자동 운영'을 켜면 시드가 추천 운영대로 짓고 연구한다. 직접 운영하면서 일부 분야(살림 건설·연구·땅·탐사·교역 …)만 " +
			"맡길 수도 있다 — '개척' 탭의 '위임'.", "target": "auto", "next": true},
	{"id": "colony", "title": "개척 — 다른 천체의 도시",
		"text": "'개척' 탭에서 천체마다의 도시와 후보 부지, 원정대, 이정표, 탐사, 수출 계약, 사람들과 평의회를 본다. 열어 본다.",
		"target": "tab:colony", "done": "tab:colony"},
	{"id": "map", "title": "항로 지도",
		"text": "왼쪽 아래 '항로'를 누르면 태양계를 Δv 지하철 지도로 본다 — 발사 창, 오가는 수송선, 함대. 열어 본다 (단축키 J).",
		"target": "view:map", "done": "view:map"},
	{"id": "end", "title": "준비 끝",
		"text": "41일째에 대형 태양 양성자 폭풍이 온다 — 대피소는 80석이다. 남극 겨울(150~240일째)에는 그림자가 90시간까지 이어진다. " +
			"메뉴의 도움말과 '튜토리얼'에서 언제든 다시 본다. 행운을 빈다.", "target": "", "next": true},
]

var main: Control
var step := -1
var _card: PanelContainer
var _title: Label
var _text: Label
var _count: Label
var _next: Button
var _base := {}
var _clock := 0.0
var _t := 0.0
var _rect := Rect2()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.97), Palette.AMBER.darkened(0.15), 12, 16))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.custom_minimum_size = Vector2(520, 0)
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_card.add_child(v)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 12)
	_count.add_theme_color_override("font_color", Palette.AMBER)
	v.add_child(_count)
	_title = Label.new()
	_title.add_theme_font_override("font", ThemeFactory.bold)
	_title.add_theme_font_size_override("font_size", 18)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 14)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("font_color", Palette.TEXT.darkened(0.08))
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var skip := Button.new()
	skip.text = "건너뛰기"
	skip.custom_minimum_size = Vector2(0, 44 if ThemeFactory.touch() else 36)
	skip.pressed.connect(func(): stop(true))
	row.add_child(skip)
	_next = Button.new()
	_next.text = "다음"
	_next.custom_minimum_size = Vector2(110, 44 if ThemeFactory.touch() else 36)
	_next.pressed.connect(_on_next)
	row.add_child(_next)
	v.add_child(row)


func active() -> bool:
	return visible and step >= 0


func start() -> void:
	visible = true
	_enter(0)


## 끝내기 (skipped: 건너뛰었다) — 다시 보지 않도록 설정에 남긴다
func stop(skipped := false) -> void:
	if not visible:
		return
	visible = false
	step = -1
	Settings.set_value("tutorial/done", true)
	finished.emit(skipped)


## 새 게임·불러오기로 그만둔다 (끝냈다고 남기지 않는다)
func cancel() -> void:
	visible = false
	step = -1


func _on_next() -> void:
	if step < 0:
		return
	if step >= STEPS.size() - 1:
		stop(false)
		return
	_enter(step + 1)


func _enter(i: int) -> void:
	step = i
	var s: Dictionary = STEPS[i]
	_count.text = "튜토리얼 %d / %d" % [i + 1, STEPS.size()]
	_title.text = String(s["title"])
	_text.text = String(s["text"])
	_next.visible = bool(s.get("next", false))
	_next.text = "끝" if i == STEPS.size() - 1 else "다음"
	_base = _snapshot()
	_clock = 0.4
	_place()


## 단계를 시작할 때의 값 — 할 일을 했는지 견준다
func _snapshot() -> Dictionary:
	var out := {"hour": 0, "queue": 0, "built": 0, "research": 0, "yaw": 0.0, "pitch": 0.0, "dist": 0.0}
	if main == null or main.get("sim") == null:
		return out
	var sim: CitySim = main.sim
	out["hour"] = int(main.colonies.hour)
	out["queue"] = sim.queue.size()
	out["built"] = int(sim.stats.get("built", 0))
	out["research"] = sim.research_queue.size()
	if main.world != null and main.world.cam != null:
		out["yaw"] = float(main.world.cam.yaw)
		out["pitch"] = float(main.world.cam.pitch)
		out["dist"] = float(main.world.cam.dist)
	return out


## 지금 단계의 할 일을 했나
func done_now() -> bool:
	if step < 0 or main == null or main.get("sim") == null:
		return false
	var s: Dictionary = STEPS[step]
	var what := String(s.get("done", ""))
	var sim: CitySim = main.sim
	match what:
		"time":
			return int(main.colonies.hour) >= int(_base["hour"]) + 12
		"camera":
			var cam = main.world.cam
			return absf(float(cam.yaw) - float(_base["yaw"])) > 0.05 or absf(float(cam.pitch) - float(_base["pitch"])) > 0.05 \
				or absf(float(cam.dist) / maxf(float(_base["dist"]), 1e-6) - 1.0) > 0.1
		"build":
			return sim.queue.size() > int(_base["queue"]) or int(sim.stats.get("built", 0)) > int(_base["built"])
		"research":
			return sim.research_queue.size() > int(_base["research"]) or (sim.research_queue.size() > 0 and main.current_tab == "research")
		"view:map":
			return main.view_mode == "map"
		_:
			if what.begins_with("tab:"):
				return main.current_tab == what.substr(4)
	return false


func _process(delta: float) -> void:
	if not active():
		return
	_t += delta
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.25
		if String(STEPS[step].get("done", "")) != "" and done_now():
			Sound.fx("good")
			_enter(step + 1) if step < STEPS.size() - 1 else stop(false)
			return
	_place()
	queue_redraw()


## 가리키는 자리 (전역 사각형 — 없으면 크기 0)
func target_rect() -> Rect2:
	if step < 0 or main == null:
		return Rect2()
	var key := String(STEPS[step].get("target", ""))
	var r := Rect2()
	match key:
		"chips":
			for c in main.chips.values():
				for part in ([c] if c is Control else (c as Dictionary).values() if c is Dictionary else []):
					if part is Control and (part as Control).is_visible_in_tree():
						var pr := (part as Control).get_global_rect()
						r = pr if r.size == Vector2.ZERO else r.merge(pr)
		"speed":
			for b in main.speed_buttons:
				r = b.get_global_rect() if r.size == Vector2.ZERO else r.merge(b.get_global_rect())
		"city":
			r = (main.city_area as Control).get_global_rect().grow(-40.0)
		"auto":
			r = (main.auto_button as Control).get_global_rect()
		_:
			if key.begins_with("tab:") and main.tab_buttons.has(key.substr(4)):
				r = (main.tab_buttons[key.substr(4)] as Control).get_global_rect()
			elif key.begins_with("view:") and main.view_buttons.has(key.substr(5)):
				r = (main.view_buttons[key.substr(5)] as Control).get_global_rect()
	return r


## 카드 자리: 도시 화면의 가운데 — 가리키는 곳이 아래쪽이면 위에, 아니면 아래에
func _place() -> void:
	_rect = target_rect()
	var area := Rect2(Vector2.ZERO, size)
	if main != null and main.get("city_area") != null:
		area = Rect2((main.city_area as Control).get_global_rect().position - global_position, (main.city_area as Control).size)
	var w := minf(560.0, maxf(area.size.x - 24.0, 280.0))
	_card.custom_minimum_size.x = w
	_card.size = Vector2(w, 0)
	var h := _card.get_combined_minimum_size().y
	var x := clampf(area.position.x + (area.size.x - w) * 0.5, 12.0, maxf(size.x - w - 12.0, 12.0))
	var low := _rect.size != Vector2.ZERO and _rect.get_center().y > size.y * 0.5
	var y := 96.0 if low else size.y - h - 110.0
	if _rect.size != Vector2.ZERO and Rect2(Vector2(x, y), Vector2(w, h)).intersects(_rect.grow(8.0)):
		y = 96.0 if not low else size.y - h - 110.0
	_card.position = Vector2(x, clampf(y, 8.0, maxf(size.y - h - 8.0, 8.0)))


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	var a := 0.55 + 0.45 * sin(_t * 4.0)
	var r := Rect2(_rect.position - global_position, _rect.size).grow(5.0)
	draw_rect(r, Color(Palette.AMBER, a), false, 3.0)
	draw_rect(r.grow(4.0), Color(Palette.AMBER, a * 0.35), false, 2.0)
