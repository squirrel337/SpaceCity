class_name Palette
## 색과 기본 스타일. 목업(docs/design/mockups)의 어두운 관제실 톤을 따른다.

const BG := Color("0f1218")
const PANEL := Color("161b25")
const PANEL_2 := Color("1d2330")
const LINE := Color("2a3142")
const TEXT := Color("e8e6dc")
const MUTED := Color("8a90a2")
const DIM := Color("5d6477")
const TEAL := Color("3fb8af")
const BLUE := Color("4cc9f0")
const AMBER := Color("f2a541")
const RED := Color("f28482")
const GREEN := Color("7ad08a")
const PURPLE := Color("c86bfa")
const SHADOW := Color("0b1530")

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
