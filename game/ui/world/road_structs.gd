class_name RoadStructs
extends RefCounted
## 높은 길의 받침 — 사슬 하나(RoadMesh._chains)를 따라 그 길 종류의 받침 모양(struct)으로 단위 상자를 놓는다 (RoadMesh.box·bar).
## 고가: 기둥(column) · T형(hammerhead) · 문형(portal) · 2층(double) · 보행 지붕(skyway) · 모노레일 · 자기부상(maglev) ·
##       A형(aframe) · 컨베이어 트레슬(trestle) · 아치 열주(arcade)
## 다리: 거더(girder) · 상자(box) · 트러스(truss) · 상로 아치(deck_arch) · 타이드 아치(tied_arch) · 현수(suspension) ·
##       사장(cable) · 엑스트라도즈드(extradosed) · 캔틸레버(cantilever) · 라멘(frame) · 부교(pontoon) · 도개(bascule) ·
##       덮개(covered) · 트레슬 다리(trestle_bridge)
## 받침은 덱이 땅에서 2 m 넘게 뜬 곳에만 (끝의 비탈에는 없다). 높이는 RoadMesh.chain_y — 덱 판의 윗면.

const CONCRETE := Color(0.64, 0.64, 0.62)
const CONCRETE_DARK := Color(0.5, 0.5, 0.49)
const ASPHALT := Color(0.2, 0.2, 0.21)
const STEEL := Color(0.52, 0.56, 0.6)
const STEEL_RED := Color(0.74, 0.27, 0.17)
const STEEL_WHITE := Color(0.88, 0.89, 0.9)
const STEEL_GREEN := Color(0.33, 0.46, 0.39)
const STEEL_BLUE := Color(0.3, 0.43, 0.62)
const MASONRY := Color(0.63, 0.53, 0.43)
const WOOD := Color(0.43, 0.32, 0.21)
const GLASS := Color(0.46, 0.64, 0.74)
const FLOAT := Color(0.28, 0.3, 0.34)
const HAZARD := Color(0.86, 0.7, 0.2)
const MIN_LIFT := 2.0


static func build(rm: RoadMesh, chain: Array) -> void:
	if chain.is_empty():
		return
	var type := String(rm._types[int(chain[0][0])])
	var rd := LayoutData.road(type)
	var hw := LayoutData.road_half(type)
	var ctx := {"rm": rm, "chain": chain, "hw": hw, "span": maxf(float(rd.get("span_m", 24.0)), 6.0),
		"len": float(chain[-1][2]), "deck": float(rd.get("deck_m", 6.0)), "slab": clampf(hw * 0.22, 0.8, 2.2)}
	match String(rd.get("struct", "column")):
		"column":
			for s: float in _stations(ctx, ctx["span"]):
				_column(ctx, _st(ctx, s), 1.4, 0.0, CONCRETE)
				_cap(ctx, _st(ctx, s), hw * 1.2, 0.9, CONCRETE)
		"hammerhead":
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				_column(ctx, st, 2.2, 0.0, CONCRETE)
				_cap(ctx, st, hw * 2.0 - 0.4, 1.4, CONCRETE)
				rm.box(_p(st, 0.0, float(st["bot"]) - 1.9), Vector3(hw * 1.1, 1.0, 2.2), st["dir"], CONCRETE_DARK)
		"portal":
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				for lat: float in [-(hw - 1.6), hw - 1.6]:
					_column(ctx, st, 1.6, lat, CONCRETE)
				_cap(ctx, st, hw * 2.0 + 1.0, 1.6, CONCRETE)
		"double":
			_double(ctx)
		"skyway":
			_skyway(ctx)
		"monorail":
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				_column(ctx, st, 1.1, 0.0, STEEL_WHITE)
				_cap(ctx, st, 2.6, 0.8, STEEL_WHITE)
		"maglev":
			_maglev(ctx)
		"aframe":
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				for lat: float in [-(hw + 2.5), hw + 2.5]:
					rm.bar(_p(st, lat, float(st["g"]) - 0.5), _p(st, lat * 0.25, float(st["bot"])), 0.5, 0.5, STEEL)
				rm.bar(_p(st, -(hw + 1.2), lerpf(float(st["g"]), float(st["bot"]), 0.5)),
					_p(st, hw + 1.2, lerpf(float(st["g"]), float(st["bot"]), 0.5)), 0.35, 0.35, STEEL)
		"trestle":
			_conveyor(ctx)
		"arcade":
			_arcade(ctx)
		"girder":
			_girders(ctx, [-hw * 0.5, hw * 0.5], 0.9, 2.0, STEEL)
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				rm.box(_mid(st, float(st["g"]) - 1.0, float(st["bot"]) - 2.0), Vector3(hw * 1.4, _hgt(st, float(st["g"]) - 1.0,
					float(st["bot"]) - 2.0), 2.0), st["dir"], CONCRETE)
		"box":
			_girders(ctx, [0.0], hw * 1.5, 2.6, CONCRETE)
			for s: float in _stations(ctx, ctx["span"]):
				var st := _st(ctx, s)
				rm.box(_mid(st, float(st["g"]) - 1.0, float(st["bot"]) - 2.6), Vector3(hw * 0.8, _hgt(st, float(st["g"]) - 1.0,
					float(st["bot"]) - 2.6), 2.6), st["dir"], CONCRETE)
		"truss":
			_truss(ctx)
		"deck_arch":
			_deck_arch(ctx)
		"tied_arch":
			_tied_arch(ctx)
		"suspension":
			_suspension(ctx)
		"cable":
			_cable_stayed(ctx)
		"extradosed":
			_extradosed(ctx)
		"cantilever":
			_cantilever(ctx)
		"frame":
			_frame(ctx)
		"pontoon":
			_pontoon(ctx)
		"bascule":
			_bascule(ctx)
		"covered":
			_covered(ctx)
		"trestle_bridge":
			_trestle_bridge(ctx)


# ── 바탕 ────────────────────────────────────────────────────────
## 사슬 위 거리 s의 자리: {p, dir, side, y(덱 판 윗면), g(땅), bot(판 밑면), lift}
static func _st(ctx: Dictionary, s: float) -> Dictionary:
	var rm: RoadMesh = ctx["rm"]
	var at := RoadMesh.chain_at(ctx["chain"], s)
	var p: Vector2 = at[0]
	var dir: Vector2 = at[1]
	var y := rm.chain_y(ctx["chain"], s)
	var g: float = (rm.h.call(p, 0.0) as Vector3).y
	return {"s": s, "p": p, "dir": dir, "side": Vector2(-dir.y, dir.x), "y": y, "g": g, "bot": y - float(ctx["slab"]),
		"lift": y - g}


static func _p(st: Dictionary, lat: float, y: float, along := 0.0) -> Vector3:
	var p: Vector2 = (st["p"] as Vector2) + (st["side"] as Vector2) * lat + (st["dir"] as Vector2) * along
	return RoadMesh.at3(p, y)


static func _mid(st: Dictionary, y0: float, y1: float, lat := 0.0) -> Vector3:
	return _p(st, lat, (y0 + y1) * 0.5)


static func _hgt(_st0: Dictionary, y0: float, y1: float) -> float:
	return maxf(y1 - y0, 0.05)


## 받침을 둘 자리들: every마다 (사슬 끝은 비탈 — 덱이 MIN_LIFT 넘게 뜬 곳만)
static func _stations(ctx: Dictionary, every: float, min_lift := MIN_LIFT) -> Array:
	var out: Array = []
	var length := float(ctx["len"])
	var n := int(floor(length / every))
	var off := (length - n * every) * 0.5
	for i in range(0, n + 1):
		var s := off + i * every
		if s <= 0.5 or s >= length - 0.5:
			continue
		if float(_st(ctx, s)["lift"]) >= min_lift:
			out.append(s)
	return out


## 사슬을 step마다 나눈 거리들 (양 끝 포함)
static func _samples(ctx: Dictionary, step: float) -> Array:
	var length := float(ctx["len"])
	var n := maxi(1, int(ceil(length / step)))
	var out: Array = []
	for i in n + 1:
		out.append(length * i / n)
	return out


## 기둥: 땅 밑 1 m에서 덱 판 밑까지
static func _column(ctx: Dictionary, st: Dictionary, w: float, lat: float, col: Color) -> void:
	var rm: RoadMesh = ctx["rm"]
	var y0 := float(st["g"]) - 1.0
	var y1 := float(st["bot"])
	if y1 - y0 < 0.3:
		return
	rm.box(_mid(st, y0, y1, lat), Vector3(w, y1 - y0, w), st["dir"], col)


## 기둥머리 (덱 밑의 가로보)
static func _cap(ctx: Dictionary, st: Dictionary, across: float, tall: float, col: Color) -> void:
	var rm: RoadMesh = ctx["rm"]
	rm.box(_p(st, 0.0, float(st["bot"]) - tall * 0.5), Vector3(across, tall, minf(2.2, tall * 1.6)), st["dir"], col)


## 덱 밑을 따라가는 거더 (lats: 가로 자리들)
static func _girders(ctx: Dictionary, lats: Array, w: float, depth: float, col: Color) -> void:
	var rm: RoadMesh = ctx["rm"]
	var ss := _samples(ctx, 8.0)
	for i in ss.size() - 1:
		var a := _st(ctx, ss[i])
		var b := _st(ctx, ss[i + 1])
		if float(a["lift"]) < 1.0 and float(b["lift"]) < 1.0:
			continue
		for lat in lats:
			rm.bar(_p(a, lat, float(a["bot"]) - depth * 0.5), _p(b, lat, float(b["bot"]) - depth * 0.5), w, depth, col)


## 덱 위 lat 자리를 따라가는 막대 (난간 위 지붕·벽·케이블 받침): 높이 dy (덱 판 윗면에서), 굵기 w × d
static func _rail(ctx: Dictionary, lat: float, dy: float, w: float, d: float, col: Color, glow := 0.0, min_lift := 0.5) -> void:
	var rm: RoadMesh = ctx["rm"]
	var ss := _samples(ctx, 8.0)
	for i in ss.size() - 1:
		var a := _st(ctx, ss[i])
		var b := _st(ctx, ss[i + 1])
		if float(a["lift"]) < min_lift and float(b["lift"]) < min_lift:
			continue
		rm.bar(_p(a, lat, float(a["y"]) + dy), _p(b, lat, float(b["y"]) + dy), w, d, col, glow)


## 포물선 아치 (사슬 위 s0~s1, 가로 lat): 양 끝 높이 y0·y1, 가운데가 rise만큼 높다 — 막대 n개의 점들을 돌려준다
static func _arch(ctx: Dictionary, s0: float, s1: float, lat: float, y0: float, y1: float, rise: float, w: float, d: float,
		col: Color, n := 12) -> Array:
	var rm: RoadMesh = ctx["rm"]
	var pts: Array = []
	for i in n + 1:
		var f := float(i) / n
		var s := lerpf(s0, s1, f)
		var st := _st(ctx, s)
		var y := lerpf(y0, y1, f) + rise * 4.0 * f * (1.0 - f)
		pts.append([st, _p(st, lat, y), y])
	for i in n:
		rm.bar(pts[i][1], pts[i + 1][1], w, d, col)
	return pts


# ── 고가 ─────────────────────────────────────────────────────────
static func _double(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	# 아래층 덱: 땅과 위층 사이 (위층이 7 m 넘게 뜬 곳)
	var ss := _samples(ctx, 8.0)
	for i in ss.size() - 1:
		var a := _st(ctx, ss[i])
		var b := _st(ctx, ss[i + 1])
		if float(a["lift"]) < 9.0 or float(b["lift"]) < 9.0:
			continue
		var ya := lerpf(float(a["g"]), float(a["y"]), 0.45)
		var yb := lerpf(float(b["g"]), float(b["y"]), 0.45)
		rm.bar(_p(a, 0.0, ya), _p(b, 0.0, yb), hw * 2.0, 0.9, ASPHALT, 0.15)
		for lat: float in [-(hw - 0.2), hw - 0.2]:
			rm.bar(_p(a, lat, ya + 0.9), _p(b, lat, yb + 0.9), 0.25, 0.9, CONCRETE)
	for s: float in _stations(ctx, ctx["span"]):
		var st := _st(ctx, s)
		for lat: float in [-(hw - 1.0), hw - 1.0]:
			_column(ctx, st, 1.5, lat, CONCRETE)
		_cap(ctx, st, hw * 2.0 + 0.8, 1.4, CONCRETE)
		if float(st["lift"]) >= 9.0:
			rm.box(_p(st, 0.0, lerpf(float(st["g"]), float(st["y"]), 0.45) - 0.9), Vector3(hw * 2.0 + 0.8, 1.2, 1.8),
				st["dir"], CONCRETE)


static func _skyway(ctx: Dictionary) -> void:
	var hw := float(ctx["hw"])
	for s: float in _stations(ctx, ctx["span"]):
		_column(ctx, _st(ctx, s), 0.6, 0.0, STEEL_WHITE)
	for lat: float in [-(hw - 0.05), hw - 0.05]:
		_rail(ctx, lat, 1.45, 0.12, 2.5, GLASS, 0.7)
	_rail(ctx, 0.0, 2.8, hw * 2.0 + 0.4, 0.22, STEEL_WHITE)


static func _maglev(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for s: float in _stations(ctx, ctx["span"]):
		var st := _st(ctx, s)
		_column(ctx, st, 1.8, 0.0, CONCRETE)
		_cap(ctx, st, hw * 2.0 + 0.6, 1.2, CONCRETE)
		rm.box(_p(st, 0.0, float(st["g"]) + 0.4), Vector3(4.0, 0.8, 4.0), st["dir"], CONCRETE_DARK)
	for lat: float in [-(hw - 0.35), hw - 0.35]:
		_rail(ctx, lat, 0.75, 0.6, 1.3, CONCRETE)
		_rail(ctx, lat * 0.9, 0.35, 0.12, 0.12, STEEL, 1.0)


static func _conveyor(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for s: float in _stations(ctx, 12.0, 1.5):
		var st := _st(ctx, s)
		var g := float(st["g"]) - 0.5
		var top := float(st["bot"])
		for dl: float in [-1.0, 1.0]:
			for lat: float in [-(hw + 1.0), hw + 1.0]:
				rm.bar(_p(st, lat * 1.3, g, dl * 1.2), _p(st, lat * 0.8, top, dl * 0.6), 0.22, 0.22, STEEL)
			rm.bar(_p(st, -(hw + 1.2), g + 0.3, dl * 1.1), _p(st, hw + 1.2, top - 0.2, dl * 0.7), 0.12, 0.12, STEEL)
			rm.bar(_p(st, hw + 1.2, g + 0.3, dl * 1.1), _p(st, -(hw + 1.2), top - 0.2, dl * 0.7), 0.12, 0.12, STEEL)
	for lat: float in [-(hw + 0.15), hw + 0.15]:
		_rail(ctx, lat, 1.1, 0.1, 2.2, STEEL)
	_rail(ctx, 0.0, 2.3, hw * 2.0 + 0.6, 0.18, STEEL)


static func _arcade(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var span := float(ctx["span"])
	var piers := _stations(ctx, span, 3.0)
	for s in piers:
		var st := _st(ctx, s)
		rm.box(_mid(st, float(st["g"]) - 1.0, float(st["bot"])), Vector3(hw * 2.0, float(st["bot"]) - float(st["g"]) + 1.0, 3.0),
			st["dir"], MASONRY)
	for i in piers.size() - 1:
		var s0 := float(piers[i]) + 1.5
		var s1 := float(piers[i + 1]) - 1.5
		var a := _st(ctx, s0)
		var b := _st(ctx, s1)
		var r := (s1 - s0) * 0.5
		var spring := minf(float(a["bot"]), float(b["bot"])) - 0.6 - r
		var pts: Array = []
		for k in 13:
			var ang := PI * float(k) / 12.0
			var s := lerpf(s0, s1, 0.5 - 0.5 * cos(ang))
			var st := _st(ctx, s)
			pts.append(_p(st, 0.0, spring + sin(ang) * r))
		for k in 12:
			rm.bar(pts[k], pts[k + 1], hw * 2.0, 1.1, MASONRY)
		# 아치 어깨와 덱 사이 (벽돌)
		for f: float in [0.12, 0.88]:
			var st2 := _st(ctx, lerpf(s0, s1, f))
			var y_arc := spring + sin(PI * (0.5 - 0.5 * cos(PI * f))) * r
			var y_top := float(st2["bot"])
			if y_top - y_arc > 0.4:
				rm.box(_mid(st2, y_arc, y_top), Vector3(hw * 2.0, y_top - y_arc, (s1 - s0) * 0.22), st2["dir"], MASONRY)


# ── 다리 ─────────────────────────────────────────────────────────
static func _truss(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var panel := 7.0
	var tall := 7.0
	var ss := _samples(ctx, panel)
	for side: float in [-1.0, 1.0]:
		var lat := side * (hw + 0.3)
		for i in ss.size():
			var st := _st(ctx, ss[i])
			if float(st["lift"]) < 1.0:
				continue
			var y := float(st["y"])
			rm.bar(_p(st, lat, y), _p(st, lat, y + tall), 0.35, 0.35, STEEL_GREEN)
			if i + 1 < ss.size():
				var nx := _st(ctx, ss[i + 1])
				if float(nx["lift"]) < 1.0:
					continue
				var yn := float(nx["y"])
				rm.bar(_p(st, lat, y + tall), _p(nx, lat, yn + tall), 0.45, 0.45, STEEL_GREEN)
				rm.bar(_p(st, lat, y + 0.3), _p(nx, lat, yn + 0.3), 0.45, 0.45, STEEL_GREEN)
				if i % 2 == 0:
					rm.bar(_p(st, lat, y + 0.3), _p(nx, lat, yn + tall), 0.28, 0.28, STEEL_GREEN)
				else:
					rm.bar(_p(st, lat, y + tall), _p(nx, lat, yn + 0.3), 0.28, 0.28, STEEL_GREEN)
	for i in ss.size():
		var st := _st(ctx, ss[i])
		if float(st["lift"]) >= 1.0 and i % 2 == 0:
			rm.bar(_p(st, -(hw + 0.3), float(st["y"]) + tall), _p(st, hw + 0.3, float(st["y"]) + tall), 0.3, 0.3, STEEL_GREEN)
	_bridge_piers(ctx, 2.4, CONCRETE)


static func _deck_arch(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for seg: Array in _arch_spans(ctx, 0.12):
		var s0: float = seg[0]
		var s1: float = seg[1]
		var a := _st(ctx, s0)
		var b := _st(ctx, s1)
		var y_top := float(_st(ctx, (s0 + s1) * 0.5)["bot"]) - 0.6
		var ya := float(a["g"])
		var yb := float(b["g"])
		var rise := y_top - maxf(ya, yb)
		if rise < 3.0:
			continue
		var pts := _arch(ctx, s0, s1, 0.0, ya, yb, y_top - (ya + yb) * 0.5, hw * 1.3, 1.6, CONCRETE)
		for i in range(1, pts.size() - 1):
			var st: Dictionary = pts[i][0]
			var y_arc: float = pts[i][2]
			for lat: float in [-hw * 0.6, hw * 0.6]:
				if float(st["bot"]) - y_arc > 0.5:
					rm.bar(_p(st, lat, y_arc), _p(st, lat, float(st["bot"])), 0.6, 0.6, CONCRETE)


static func _tied_arch(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for seg: Array in _arch_spans(ctx, 0.08):
		var s0: float = seg[0]
		var s1: float = seg[1]
		var a := _st(ctx, s0)
		var b := _st(ctx, s1)
		var rise := clampf((s1 - s0) * 0.18, 8.0, 40.0)
		var arches: Array = []
		for lat: float in [-(hw + 0.4), hw + 0.4]:
			var pts := _arch(ctx, s0, s1, lat, float(a["y"]) + 0.2, float(b["y"]) + 0.2, rise, 0.9, 1.1, STEEL_BLUE)
			arches.append(pts)
			for i in range(1, pts.size() - 1):
				var st: Dictionary = pts[i][0]
				rm.bar(pts[i][1], _p(st, lat, float(st["y"]) + 0.2), 0.14, 0.14, STEEL_WHITE)
		for i in range(2, (arches[0] as Array).size() - 2, 2):
			rm.bar(arches[0][i][1], arches[1][i][1], 0.4, 0.4, STEEL_BLUE)
		for st: Dictionary in [a, b]:
			rm.box(_mid(st, float(st["g"]) - 1.0, float(st["bot"])), Vector3(hw * 2.2, maxf(float(st["bot"]) - float(st["g"]) + 1.0, 0.1),
				3.0), st["dir"], CONCRETE)


static func _suspension(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var length := float(ctx["len"])
	var f1 := 0.22 if length >= 120.0 else 0.3
	var t1 := _st(ctx, length * f1)
	var t2 := _st(ctx, length * (1.0 - f1))
	var main := length * (1.0 - 2.0 * f1)
	var ht := clampf(main * 0.12, 18.0, 60.0)
	for tw: Dictionary in [t1, t2]:
		var top := float(tw["y"]) + ht
		for lat: float in [-(hw + 1.2), hw + 1.2]:
			rm.box(_mid(tw, float(tw["g"]) - 1.0, top, lat), Vector3(1.6, top - float(tw["g"]) + 1.0, 2.2), tw["dir"], STEEL_RED)
		for yy: float in [float(tw["bot"]) - 0.6, float(tw["y"]) + ht * 0.6, top - 0.6]:
			rm.box(_p(tw, 0.0, yy), Vector3(hw * 2.0 + 4.0, 1.2, 1.6), tw["dir"], STEEL_RED)
	var ya := float(_st(ctx, 1.0)["y"]) + 1.0
	var yb := float(_st(ctx, length - 1.0)["y"]) + 1.0
	for lat: float in [-(hw + 1.2), hw + 1.2]:
		# 큰 케이블: 닻 → 탑 꼭대기 → (처짐) → 탑 꼭대기 → 닻, 그리고 행어
		var keys := [[1.0, ya], [length * f1, float(t1["y"]) + ht], [length * (1.0 - f1), float(t2["y"]) + ht], [length - 1.0, yb]]
		for part in 3:
			var s0: float = keys[part][0]
			var s1: float = keys[part + 1][0]
			var y0: float = keys[part][1]
			var y1: float = keys[part + 1][1]
			var n := maxi(3, int(ceil((s1 - s0) / 7.0)))
			var prev := Vector3.ZERO
			for i in n + 1:
				var f := float(i) / n
				var s := lerpf(s0, s1, f)
				var st := _st(ctx, s)
				var sag := (ht - 2.5) if part == 1 else ht * 0.12
				var y := lerpf(y0, y1, f) - sag * 4.0 * f * (1.0 - f)
				var q := _p(st, lat, y)
				if i > 0:
					rm.bar(prev, q, 0.55, 0.55, STEEL_RED)
				if i > 0 and i < n and y - float(st["y"]) > 1.5:
					rm.bar(q, _p(st, lat, float(st["y"]) + 0.3), 0.12, 0.12, STEEL_RED)
				prev = q
	for s: float in [2.0, length - 2.0]:
		var st := _st(ctx, s)
		for lat: float in [-(hw + 1.2), hw + 1.2]:
			rm.box(_p(st, lat, float(st["y"]) - 0.5), Vector3(4.0, 4.0, 5.0), st["dir"], CONCRETE)


static func _cable_stayed(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var length := float(ctx["len"])
	var n := 1 if length < 220.0 else 2
	for k in n:
		var sp := length * float(k + 1) / (n + 1)
		var tw := _st(ctx, sp)
		var reach := length / (n + 1) * 0.92
		var hp := clampf(reach * 0.6, 25.0, 90.0)
		var apex := _p(tw, 0.0, float(tw["y"]) + hp)
		for lat: float in [-(hw + 1.5), hw + 1.5]:
			rm.bar(_p(tw, lat, float(tw["g"]) - 1.0), apex, 2.0, 2.4, STEEL_WHITE)
		rm.box(_p(tw, 0.0, float(tw["bot"]) - 0.7), Vector3(hw * 2.0 + 4.0, 1.4, 2.4), tw["dir"], STEEL_WHITE)
		for d: float in [-1.0, 1.0]:
			var m := maxi(3, int(reach / 9.0))
			for i in range(1, m + 1):
				var s := sp + d * reach * float(i) / m
				if s <= 1.0 or s >= length - 1.0:
					continue
				var st := _st(ctx, s)
				var top := _p(tw, 0.0, float(tw["y"]) + hp * (0.98 - 0.32 * float(i) / m))
				for lat: float in [-(hw - 0.3), hw - 0.3]:
					rm.bar(top, _p(st, lat, float(st["y"]) + 0.3), 0.16, 0.16, STEEL_WHITE)


static func _extradosed(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var span := float(ctx["span"])
	for s: float in _stations(ctx, span, 3.0):
		var st := _st(ctx, s)
		rm.box(_mid(st, float(st["g"]) - 1.0, float(st["bot"])), Vector3(hw * 1.2, maxf(float(st["bot"]) - float(st["g"]) + 1.0, 0.1),
			3.0), st["dir"], CONCRETE)
		var hp := span * 0.13
		for lat: float in [-(hw + 0.6), hw + 0.6]:
			var top := _p(st, lat, float(st["y"]) + hp)
			rm.box(_p(st, lat, float(st["y"]) + hp * 0.5), Vector3(1.2, hp, 1.6), st["dir"], CONCRETE)
			for d: float in [-1.0, 1.0]:
				for i in range(2, 6):
					var s2 := s + d * span * 0.08 * i
					if s2 <= 1.0 or s2 >= float(ctx["len"]) - 1.0:
						continue
					var st2 := _st(ctx, s2)
					rm.bar(top, _p(st2, lat * 0.95, float(st2["y"]) + 0.3), 0.14, 0.14, STEEL_WHITE)


static func _cantilever(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var span := float(ctx["span"])
	var piers := _stations(ctx, span, 3.0)
	var ss := _samples(ctx, 4.0)
	for i in ss.size() - 1:
		var a := _st(ctx, ss[i])
		var b := _st(ctx, ss[i + 1])
		if float(a["lift"]) < 1.5 or float(b["lift"]) < 1.5:
			continue
		var da := _depth(float(ss[i]), piers, span)
		var db := _depth(float(ss[i + 1]), piers, span)
		var dm := (da + db) * 0.5
		rm.bar(_p(a, 0.0, float(a["bot"]) - dm * 0.5), _p(b, 0.0, float(b["bot"]) - dm * 0.5), hw * 1.3, dm, CONCRETE)
	for s in piers:
		var st := _st(ctx, s)
		for lat: float in [-hw * 0.45, hw * 0.45]:
			var y1 := float(st["bot"]) - 6.5
			if y1 > float(st["g"]):
				rm.box(_mid(st, float(st["g"]) - 1.0, y1, lat), Vector3(2.4, y1 - float(st["g"]) + 1.0, 4.0), st["dir"], CONCRETE)


## 캔틸레버의 거더 깊이: 받침에서 깊고(7 m) 가운데에서 얕다(2 m)
static func _depth(s: float, piers: Array, span: float) -> float:
	var near := span
	for p: float in piers:
		near = minf(near, absf(s - float(p)))
	var f := clampf(near / (span * 0.5), 0.0, 1.0)
	return lerpf(7.0, 2.0, sqrt(f))


static func _frame(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var span := float(ctx["span"])
	_girders(ctx, [0.0], hw * 1.3, 1.5, CONCRETE)
	for s: float in _stations(ctx, span, 4.0):
		var st := _st(ctx, s)
		var foot := _p(st, 0.0, float(st["g"]) - 1.0)
		for d: float in [-1.0, 1.0]:
			var s2 := s + d * span * 0.2
			if s2 <= 0.0 or s2 >= float(ctx["len"]):
				continue
			var st2 := _st(ctx, s2)
			rm.bar(foot, _p(st2, 0.0, float(st2["bot"]) - 1.4), hw * 1.0, 1.4, CONCRETE)


static func _pontoon(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for s: float in _samples(ctx, 5.0):
		var st := _st(ctx, s)
		if float(st["g"]) > float(st["y"]) - 1.2:
			continue                            # 뭍 위 (끝의 비탈)
		rm.box(_p(st, 0.0, float(st["y"]) - 1.3), Vector3(hw * 2.6, 1.6, 3.6), st["dir"], FLOAT)


static func _bascule(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	var length := float(ctx["len"])
	_girders(ctx, [-hw * 0.5, hw * 0.5], 0.8, 1.8, STEEL)
	_bridge_piers(ctx, 2.4, CONCRETE)
	for d: float in [-1.0, 1.0]:
		var st := _st(ctx, length * 0.5 + d * 9.0)
		for lat: float in [-(hw + 2.2), hw + 2.2]:
			var top := float(st["y"]) + 14.0
			rm.box(_mid(st, float(st["g"]) - 1.0, top, lat), Vector3(3.2, top - float(st["g"]) + 1.0, 3.2), st["dir"], MASONRY)
			rm.box(_p(st, lat, top + 1.2), Vector3(3.8, 2.4, 3.8), st["dir"], STEEL_GREEN)
			rm.box(_p(st, lat, top - 4.0), Vector3(3.4, 1.4, 3.4), st["dir"], GLASS, 0.8)
		rm.box(_p(st, 0.0, float(st["bot"]) - 2.0), Vector3(hw * 1.6, 3.0, 4.0), st["dir"], HAZARD)


static func _covered(ctx: Dictionary) -> void:
	var hw := float(ctx["hw"])
	for lat: float in [-(hw + 0.1), hw + 0.1]:
		_rail(ctx, lat, 1.75, 0.25, 3.5, STEEL_WHITE, 0.0, 1.0)
		_rail(ctx, lat * 1.02, 2.0, 0.08, 1.0, GLASS, 1.0, 1.0)
	_rail(ctx, 0.0, 3.6, hw * 2.0 + 0.7, 0.35, STEEL_WHITE, 0.0, 1.0)
	_bridge_piers(ctx, 2.0, CONCRETE)


static func _trestle_bridge(ctx: Dictionary) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for s: float in _stations(ctx, 9.0, 2.0):
		var st := _st(ctx, s)
		var g := float(st["g"]) - 0.5
		var top := float(st["bot"])
		var spread := hw + 0.15 * (top - g)
		for lat: float in [-spread, -spread * 0.35, spread * 0.35, spread]:
			rm.bar(_p(st, lat, g), _p(st, lat * hw * 0.6 / maxf(spread, 0.01), top), 0.4, 0.4, WOOD)
		for f: float in [0.33, 0.66]:
			var y := lerpf(g, top, f)
			var w := lerpf(spread, hw * 0.6, f)
			rm.bar(_p(st, -w, y), _p(st, w, y), 0.25, 0.25, WOOD)
		rm.bar(_p(st, -spread, g + 0.5), _p(st, hw * 0.6, top - 0.3), 0.18, 0.18, WOOD)
		rm.bar(_p(st, spread, g + 0.5), _p(st, -hw * 0.6, top - 0.3), 0.18, 0.18, WOOD)
	_girders(ctx, [0.0], hw * 1.1, 0.6, WOOD)


## 다리의 교각: span마다 (덱 밑 깊이 under만큼 비운다)
static func _bridge_piers(ctx: Dictionary, under: float, col: Color) -> void:
	var rm: RoadMesh = ctx["rm"]
	var hw := float(ctx["hw"])
	for s: float in _stations(ctx, ctx["span"], 3.0):
		var st := _st(ctx, s)
		var y1 := float(st["bot"]) - under
		if y1 - float(st["g"]) < 0.5:
			continue
		rm.box(_mid(st, float(st["g"]) - 1.0, y1), Vector3(hw * 1.5, y1 - float(st["g"]) + 1.0, 2.4), st["dir"], col)


## 아치를 놓을 구간들: 사슬이 span의 1.6배를 넘지 않으면 하나 (양 끝에서 inset 몫 안쪽), 길면 받침 사이마다
static func _arch_spans(ctx: Dictionary, inset: float) -> Array:
	var length := float(ctx["len"])
	var span := float(ctx["span"])
	if length <= span * 1.6:
		return [[length * inset, length * (1.0 - inset)]]
	var out: Array = []
	var piers := _stations(ctx, span, 3.0)
	var prev := length * inset * 0.5
	for p: float in piers:
		out.append([prev, float(p)])
		prev = float(p)
	out.append([prev, length * (1.0 - inset * 0.5)])
	return out
