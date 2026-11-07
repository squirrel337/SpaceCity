class_name Palette
## 색과 기본 스타일. 목업(docs/design/mockups)의 어두운 관제실 톤을 따른다.

const BG := Color("0f1218")
const PANEL := Color("161b25")
const PANEL_2 := Color("1d2330")
const LINE := Color("2a3142")
const TEXT := Color("e8e6dc")
const MUTED := Color("8a90a2")
const DIM := Color("5d6477")
const SHADOW := Color("0b1530")

## 상태 색 — 색각 팔레트(설정 ui/cvd)에 따라 바뀐다 (use). 상태 넷(TEAL 괜찮음 · GREEN 좋음 · AMBER 경고 · RED 위험)은
## 그 색각의 시뮬레이션(Machado 2009, 심도 1)에서 OKLab ΔE×100이 서로 13 넘게, 정상 시각에서도 20 넘게 떨어지게 골랐다
## (기본 팔레트는 녹색약에서 GREEN↔RED가 4.3). 모두 패널 바탕에 대비 5:1 넘게
static var TEAL := Color("3fb8af")
static var BLUE := Color("4cc9f0")
static var AMBER := Color("f2a541")
static var RED := Color("f28482")
static var GREEN := Color("7ad08a")
static var PURPLE := Color("c86bfa")
static var kind := ""

## 색각 팔레트: [TEAL, GREEN, AMBER, RED, BLUE, PURPLE]
const CVD := {
	"": ["3fb8af", "7ad08a", "f2a541", "f28482", "4cc9f0", "c86bfa"],
	"protan": ["32b08d", "c8d72a", "d6810c", "e263b1", "2fb5d8", "c780f7"],    # 적색약 — 위험은 자홍, 좋음은 연두, 경고는 짙은 주황
	"deutan": ["7fdddd", "56b138", "faab3f", "d76fad", "1aa2eb", "e1b9f3"],    # 녹색약 — 괜찮음은 옅은 청록, 위험은 자홍
	"tritan": ["55e1f0", "56b138", "fdbe45", "d47795", "5db2cc", "8d92cf"],    # 청색약 — 위험은 장밋빛, 경고는 노랑
}
const CVD_NAMES := {"": "기본", "protan": "적색약", "deutan": "녹색약", "tritan": "청색약"}

## 모듈 분류별 색
const CATEGORY := {
	"habitat": Color("7aa7f0"),
	"life_support": Color("3fb8af"),
	"food": Color("8fcf6e"),
	"power": Color("f2c14e"),
	"thermal": Color("e9875a"),
	"industry": Color("b49a7a"),
	"logistics": Color("9aa3b8"),
	"safety": Color("f28482"),
	"research": Color("c86bfa"),
	"social": Color("f4a6c6"),
	"commerce": Color("e9c46a"),
}

const CATEGORY_KO := {
	"habitat": "거주", "life_support": "생명유지", "food": "식량", "power": "전력", "thermal": "열",
	"industry": "산업", "logistics": "물류", "safety": "안전", "research": "연구", "social": "사회",
	"commerce": "상업",
}


## 색각 팔레트를 고른다 (없는 이름이면 기본). 바뀌면 true — 테마를 다시 만들고 화면을 다시 그려야 한다 (Access.apply)
static func use(name: String) -> bool:
	var k := name if CVD.has(name) else ""
	if k == kind:
		return false
	kind = k
	var c: Array = CVD[k]
	TEAL = Color(c[0])
	GREEN = Color(c[1])
	AMBER = Color(c[2])
	RED = Color(c[3])
	BLUE = Color(c[4])
	PURPLE = Color(c[5])
	return true


static func box(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 8, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	if border.a > 0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


static func level_color(margin: float, warn: float, bad: float) -> Color:
	## 여유가 bad 아래면 빨강, warn 아래면 주황, 아니면 청록
	if margin < bad:
		return RED
	if margin < warn:
		return AMBER
	return TEAL
