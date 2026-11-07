class_name Access
extends RefCounted
## 접근성과 화면 배율 (설정 카드의 '보기 · 접근성') — user://settings.cfg에 남고 바꾸면 바로 적용된다.
##   UI 배율 (ui/scale): 자동 · 90 · 100 · 115 · 130% — 창의 content_scale_factor (글·단추·패널이 함께 커진다).
##     자동은 작은 휴대폰(화면 대각선 7.5인치 아래)이면 115%, 아니면 100%. 화면이 UI 좌표로 가로 1100 · 세로 540보다
##     작아지지 않게 줄인다 — 위 막대와 440 폭 옆 패널이 들어가게 (16:9 PC는 116%까지, 20:9 휴대폰은 133%까지)
##   글자 크기 (ui/font): 작게 ×0.9 · 보통 · 크게 ×1.2 — fs()가 곱한다 (테마 기본 16, 덮어쓴 글자 크기, 직접 그리는 글).
##     바꾸면 테마를 다시 만들고 이미 있는 컨트롤의 글자 크기를 비율로 고친다 (처음 크기는 메타 fs_base에)
##   색 (ui/cvd): 기본 · 적색약 · 녹색약 · 청색약 — Palette.use (상태 색 여섯)
##   움직임 줄이기 (ui/calm): 카메라가 날아가지 않고 곧바로 옮겨 가고, 깜박이는 불빛·흔들리는 작물·도는 기계가 멈춘다

const SCALES := ["auto", "0.9", "1.0", "1.15", "1.3"]
const SCALE_NAMES := {"auto": "자동", "0.9": "90%", "1.0": "100%", "1.15": "115%", "1.3": "130%"}
const FONTS := {"small": 0.9, "normal": 1.0, "large": 1.2}
const FONT_NAMES := {"small": "작게", "normal": "보통", "large": "크게"}
const MIN_UI := Vector2(1100.0, 540.0)    # UI 배율을 올려도 남아야 하는 UI 좌표 크기
const BASE := Vector2(1280.0, 720.0)      # project.godot의 기준 화면 (canvas_items · expand)
const PHONE_INCH := 7.5
const FLY_CALM_S := 0.05                  # 움직임 줄이기: 카메라 날기 시간 (곧바로)

static var font_k := 1.0
static var calm := false
static var _loaded := false


## 설정을 읽는다 (화면을 만들기 전에 — boot·main)
static func load_settings() -> void:
	_loaded = true
	font_k = float(FONTS.get(String(Settings.value("ui/font", "normal")), 1.0))
	calm = bool(Settings.value("ui/calm", false))
	Palette.use(String(Settings.value("ui/cvd", "")))


## 글자 크기: 설정의 배율을 곱한 정수
static func fs(n: float) -> int:
	if not _loaded:
		load_settings()
	return maxi(1, int(round(n * font_k)))


## 카메라 날기 시간 (움직임 줄이기면 곧바로)
static func fly_s(seconds: float) -> float:
	return minf(seconds, FLY_CALM_S) if calm else seconds


## 움직이는 연출의 시간 (움직임 줄이기면 멈춘 시각 0)
static func anim_t(t: float) -> float:
	return 0.0 if calm else t


# ── UI 배율 ─────────────────────────────────────────────────────
## 작은 휴대폰 (모바일이고 화면 대각선이 7.5인치 아래 — dpi를 모르면 모바일이면 휴대폰으로)
static func small_phone() -> bool:
	if not OS.has_feature("mobile"):
		return false
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return true
	var px := Vector2(DisplayServer.screen_get_size())
	return px.length() / float(dpi) < PHONE_INCH


## 고른 배율 (자동이면 기기로)
static func chosen_scale() -> float:
	var pick := String(Settings.value("ui/scale", "auto"))
	if pick == "auto" or not SCALES.has(pick):
		return 1.15 if small_phone() else 1.0
	return float(pick)


## 창 크기에서 쓸 배율: 고른 배율을 UI 좌표가 MIN_UI 아래로 내려가지 않게 줄인다 (줄이는 쪽 90%는 그대로)
static func scale_for(win_size: Vector2) -> float:
	var k := chosen_scale()
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return k
	var stretch := minf(win_size.x / BASE.x, win_size.y / BASE.y)
	var ui := win_size / maxf(stretch, 1e-6)                       # 배율 1의 UI 좌표 크기 (expand)
	var cap := minf(ui.x / MIN_UI.x, ui.y / MIN_UI.y)
	return minf(k, maxf(1.0, cap)) if k > 1.0 else k


## 창에 건다 (바뀌었으면 true)
static func apply_scale(win: Window) -> bool:
	if win == null:
		return false
	var k := scale_for(Vector2(win.size))
	if absf(win.content_scale_factor - k) < 1e-3:
		return false
	win.content_scale_factor = k
	return true


# ── 바꾸기 (설정 카드) ──────────────────────────────────────────
## 글자 크기를 바꾼다: 테마를 다시 만들고 root 아래 컨트롤의 덮어쓴 글자 크기를 새 배율로
static func set_font(key: String, root: Control) -> void:
	if not FONTS.has(key):
		return
	Settings.set_value("ui/font", key)
	var old := font_k
	font_k = float(FONTS[key])
	if absf(old - font_k) < 1e-6 or root == null:
		return
	root.theme = ThemeFactory.build()
	rescale(root, old)


## 이미 있는 컨트롤의 덮어쓴 글자 크기를 old 배율에서 지금 배율로 (처음 크기는 메타 fs_base에 남긴다)
static func rescale(n: Node, old: float) -> void:
	if n is Control:
		var c := n as Control
		if c.has_theme_font_size_override("font_size"):
			var base: float = float(c.get_meta("fs_base")) if c.has_meta("fs_base") else float(c.get_theme_font_size("font_size")) / maxf(old, 0.1)
			c.set_meta("fs_base", base)
			c.add_theme_font_size_override("font_size", fs(base))
		if n is CanvasItem:
			(n as CanvasItem).queue_redraw()
	for ch in n.get_children():
		rescale(ch, old)


## 색각 팔레트를 바꾼다: 테마를 다시 만든다 (상태 색이 든 단추·막대) — 패널은 main이 다시 그린다
static func set_cvd(key: String, root: Control) -> void:
	Settings.set_value("ui/cvd", key)
	if Palette.use(key) and root != null:
		root.theme = ThemeFactory.build()
		_redraw(root)


static func set_calm(on: bool) -> void:
	Settings.set_value("ui/calm", on)
	calm = on


static func set_scale(key: String, win: Window) -> void:
	if not SCALES.has(key):
		return
	Settings.set_value("ui/scale", key)
	apply_scale(win)


static func _redraw(n: Node) -> void:
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for ch in n.get_children():
		_redraw(ch)


## 한 줄 (도움말·시험): "UI 배율 자동(100%) · 글자 보통 · 색 기본 · 움직임 그대로"
static func summary(win: Window) -> String:
	var pick := String(Settings.value("ui/scale", "auto"))
	var k := win.content_scale_factor if win != null else chosen_scale()
	var fk := String(Settings.value("ui/font", "normal"))
	return "UI 배율 %s(%d%%) · 글자 %s · 색 %s · 움직임 %s" % [String(SCALE_NAMES.get(pick, pick)), int(round(k * 100.0)),
		String(FONT_NAMES.get(fk, fk)), String(Palette.CVD_NAMES.get(Palette.kind, "")), "줄임" if calm else "그대로"]
