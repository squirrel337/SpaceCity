class_name TechCampus
extends RefCounted
## 반도체·AI 데이터센터 단지의 3D 상자들 — 대도시의 땅(MetroCity — 또는 지역의 땅 TechSite) 위에 동·북 좌표(m)로 짓는다.
## 지역의 종류에 따라 묶음(1~4곳)마다:
##   반도체 공장 (메모리·파운드리·반도체 공장) — 넓고 낮은 흰 공정동(팹) 두세 동, 지붕의 배기 설비 줄, 배기탑, 중앙 유틸리티동,
##       가스·약품 탱크 마당, 유리 사옥, 주차장
##   패키징·시험 — 중간 크기 공장동 여럿과 창고, 주차장
##   칩 설계·연구 — 유리 사옥 여러 동(탑 셰이더 — 밤에 창이 켜진다)과 가운데 잔디 마당
##   데이터센터 (AI·허브) — 긴 전산동 줄, 지붕 냉각기 격자, 비상 발전기 마당, 변전소(변압기·철탑)
## 공장·전산동은 창 없는 단색 상자(bridge 셰이더 — 밤에 은은한 보안등), 사옥만 탑 셰이더로. 비탈이면 낮은 쪽까지 기단을 내린다.

const GLASS_OFFICE := 0.75


## 단지 묶음 자리 [{en, kind, group, rot}] — 지역 가운데 하나와 둘레 고리 (큰 지역일수록 많이: 지름 3 km마다 하나, 2~8곳).
## 종류는 지역의 종류를 돌아가며, 묶음끼리 1.4 km 넘게 떨어지고 물가(250 m)를 피한다
static func plan(host: MetroCity, r: Dictionary, center: Vector2) -> Array:
	var kinds: Array = r.get("kinds", [])
	if kinds.is_empty():
		return []
	var n := clampi(int(round(float(r.get("size_km", 6.0)) / 3.0)) + 1, 2, 8)
	var rad := float(r.get("radius_km", 3.0)) * 1000.0 * 0.6
	if n > 1:
		rad = maxf(rad, maxf(1400.0, 1400.0 / (2.0 * sin(PI / maxf(n - 1.0, 2.0)))))
	var h := absi(String(r.get("id", "")).hash())
	var a0 := float(h % 360) * PI / 180.0
	var rot := atan2(host._vv.y, host._vv.x)          # 대도시의 길 격자와 나란히 (지역만 있는 땅은 정북 격자)
	var plots: Array = []
	for i in n:
		var a := a0 + TAU * (i - 1) / maxf(n - 1.0, 1.0)
		var dist := 0.0 if i == 0 else rad * (0.8 + 0.2 * float(posmod(int(h / (7.0 + i)), 100)) / 100.0)
		var en := center + Vector2(cos(a), sin(a)) * dist
		# 물이면 가운데 쪽으로 당기고, 그래도 물이면 돌려 본다
		var ok := false
		for t in 10:
			if host._sample(en).x >= 0.25:
				ok = true
				break
			en = center + (en - center).rotated(0.6) * 0.85
		for p in plots:
			if ok and ((p["en"] as Vector2) - en).length() < 1200.0:
				ok = false
		if not ok:
			continue
		var kind := String(kinds[i % kinds.size()])
		plots.append({"en": en, "kind": kind, "group": _group_of(kind), "rot": rot})
	return plots


static func _group_of(kind: String) -> String:
	match kind:
		"memory", "foundry", "fab":
			return "fab"
		"packaging":
			return "pack"
		"research":
			return "lab"
		"ai_dc", "dc_hub":
			return "dc"
	return "pack"


## 그 묶음의 이름 (지역의 종류마다)
static func plot_name(kind: String) -> String:
	return {"memory": "메모리 반도체 공장", "foundry": "파운드리 공장", "fab": "반도체 공장", "packaging": "패키징·시험 공장",
		"research": "칩 설계 연구소", "ai_dc": "AI 데이터센터", "dc_hub": "데이터센터 허브"}.get(kind, "단지")


## 상자들을 짓는다 — out: {xf: Array[Transform3D], col: Array[Color], cus: Array[Color], labels: Array} (모두 Array — 꾸러미 배열은 값이라 사전 안에서 늘지 않는다).
## 사옥은 host._add로 (탑 셰이더). max_boxes를 넘으면 그만
static func build(host: MetroCity, r: Dictionary, plots: Array, max_boxes: int, out: Dictionary) -> void:
	# 지역마다의 난수·이름표는 out에 둔다 — 묶음을 한 번에 하나씩 나눠 지어도 한 번에 지은 것과 같게
	var rid := String(r.get("id", ""))
	if not out.has("rng|" + rid):
		var rng0 := RandomNumberGenerator.new()
		rng0.seed = absi(rid.hash()) + 11
		out["rng|" + rid] = rng0
		out["named|" + rid] = {}
	var rng: RandomNumberGenerator = out["rng|" + rid]
	var sc := clampf(float(r.get("scale", 1.0)), 0.6, 1.5)
	var named: Dictionary = out["named|" + rid]
	for p in plots:
		if _full(out, max_boxes):
			break                                    # 빈 마당만 남기지 않게 묶음째로 그만
		var en: Vector2 = p["en"]
		var rot: float = p["rot"]
		var u := Vector2(cos(rot), sin(rot))
		var v := Vector2(-u.y, u.x)
		var top := 0.0
		out.erase("y0")
		match String(p.get("group", _group_of(String(p["kind"])))):
			"fab":
				top = _fab(host, out, en, u, v, sc, rng, max_boxes)
			"pack":
				top = _pack(host, out, en, u, v, sc, rng, max_boxes)
			"lab":
				top = _lab(host, out, en, u, v, sc, rng, max_boxes)
			"dc":
				top = _dc(host, out, en, u, v, sc, rng, max_boxes)
		out.erase("y0")
		if named.has(String(p["kind"])):
			continue                                 # 같은 종류는 이름표 하나만
		named[String(p["kind"])] = true
		var gy := host._ground_y(en)
		out["labels"].append([host._pos(en, gy + top + 40.0), plot_name(String(p["kind"])), String(r.get("name", "")),
			Metros.region_color(r)])


static func _full(out: Dictionary, max_boxes: int) -> bool:
	return (out["xf"] as Array).size() >= max_boxes


## 단색 상자 하나: 가운데 en, 방향 u, 너비 w(u 쪽)·깊이 d·높이 h. z0 < -1e8이면 바닥에서 — 고른 마당(out.y0) 위,
## 마당이 없으면 땅에서 (비탈이면 낮은 쪽까지 기단). 아니면 그 높이(모형 좌표의 땅 높이 기준 m)에서. 윗면 높이를 돌려준다
static func box(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, w: float, d: float, h: float, col: Color,
		glow: float = 0.0, z0: float = -1e9) -> float:
	var v := Vector2(-u.y, u.x)
	var base := z0
	var top := 0.0
	if z0 < -1e8 and out.has("y0"):
		base = float(out["y0"]) - 0.5
		top = float(out["y0"]) + h
	elif z0 < -1e8:
		var lo := INF
		var hi := -INF
		for c in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1), Vector2.ZERO]:
			var q: Vector2 = en + u * (w * 0.5 * c.x) + v * (d * 0.5 * c.y)
			var gh := host.ground.local_height_m(host._model(q))
			lo = minf(lo, gh)
			hi = maxf(hi, gh)
		base = lo - 2.5
		top = hi + h
	else:
		top = z0 + h
	var p0 := host._model(en)
	var p1 := host._model(en + u)
	var x := Vector3(p1.x - p0.x, 0.0, -(p1.y - p0.y)).normalized()
	var z := x.cross(Vector3.UP).normalized()
	var c3 := host._pos(en, (base + top) * 0.5)
	(out["xf"] as Array).append(Transform3D(Basis(x * w, Vector3.UP * (top - base), z * d), c3))
	(out["col"] as Array).append(col)
	(out["cus"] as Array).append(Color(glow, 0.0, 0.0, 0.0))
	return top


## 단지 바닥: 실제 반도체 단지처럼 땅을 골라 밝은 콘크리트 마당을 만든다 (가장 높은 땅 높이 — 비탈이면 낮은 쪽이 옹벽,
## 밤에는 마당 조명). 앞쪽에 짙은 진입로 띠. 묶음의 다른 상자·사옥은 이 마당(out.y0) 위에 선다
static func _pad(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, w: float, d: float) -> void:
	var v := Vector2(-u.y, u.x)
	var lo := INF
	var hi := -INF
	for a in [-0.5, 0.0, 0.5]:
		for b in [-0.5, 0.0, 0.5]:
			var gh := host.ground.local_height_m(host._model(en + u * (w * a) + v * (d * b)))
			lo = minf(lo, gh)
			hi = maxf(hi, gh)
	var top := hi + 0.3
	box(host, out, en, u, w, d, top - (lo - 3.0), Color(0.5, 0.51, 0.5), 0.3, lo - 3.0)
	box(host, out, en + v * (d * 0.5 + 9.0), u, w + 36.0, 14.0, 0.35, Color(0.2, 0.2, 0.21), 0.5)
	out["y0"] = top


## 반도체 공장: 공정동(팹) 두세 동 + 지붕 배기 설비 + 배기탑 + 유틸리티동 + 탱크 마당 + 사옥 + 주차장
static func _fab(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, v: Vector2, sc: float,
		rng: RandomNumberGenerator, mx: int) -> float:
	var top := 0.0
	var n := 2 + int(rng.randf() * 1.99)
	var x0 := -float(n - 1) * 0.5
	_pad(host, out, en, u, (float(n - 1) * 320.0 + 380.0) * sc, 620.0 * sc)
	for i in n:
		if _full(out, mx):
			break
		var w := rng.randf_range(220.0, 300.0) * sc
		var d := rng.randf_range(110.0, 140.0) * sc
		var h := rng.randf_range(26.0, 36.0)
		var at := en + u * ((x0 + i) * 320.0 * sc)
		var white := Color(0.88, 0.89, 0.9) if rng.randf() < 0.6 else Color(0.8, 0.86, 0.92)
		var t := box(host, out, at, u, w, d, h, white, 0.12)
		top = maxf(top, t - host._ground_y(at))
		# 지붕의 배기 설비 줄
		for k in 8:
			if _full(out, mx):
				break
			var q := at + u * (-w * 0.4 + w * 0.8 * k / 7.0) + v * (d * 0.28)
			box(host, out, q, u, 12.0, 7.0, 5.0, Color(0.58, 0.6, 0.62), 0.0, t)
			box(host, out, q - v * (d * 0.56), u, 12.0, 7.0, 4.0, Color(0.6, 0.62, 0.64), 0.0, t)
		# 배기탑
		for k2 in 3:
			var s := at + u * (w * 0.5 + 14.0) + v * (-d * 0.3 + d * 0.3 * k2)
			box(host, out, s, u, 5.0, 5.0, h + 22.0, Color(0.82, 0.83, 0.84))
	# 중앙 유틸리티동과 가스·약품 탱크 마당
	var cub := en + v * (230.0 * sc)
	box(host, out, cub, u, 140.0 * sc, 60.0, 22.0, Color(0.7, 0.71, 0.7), 0.08)
	for k3 in 10:
		if _full(out, mx):
			break
		var tk := cub + u * (-90.0 + 20.0 * (k3 % 5) + 180.0) * sc + v * (-14.0 + 28.0 * int(k3 / 5))
		box(host, out, tk, u, 9.0, 9.0, 14.0, Color(0.9, 0.9, 0.88))
	# 사옥 (유리, 창이 켜진다)
	var off := en - v * (230.0 * sc) + u * (rng.randf_range(-120.0, 120.0) * sc)
	host._add(off, 44.0, 32.0, rng.randf_range(45.0, 85.0), GLASS_OFFICE, atan2(u.y, u.x), float(out.get("y0", NAN)))
	# 주차장
	box(host, out, en - v * (230.0 * sc) + u * (200.0 * sc), u, 140.0, 70.0, 0.4, Color(0.26, 0.26, 0.27))
	box(host, out, en - v * (230.0 * sc) - u * (200.0 * sc), u, 120.0, 70.0, 0.4, Color(0.26, 0.26, 0.27))
	return top


## 패키징·시험: 중간 공장동 서넛과 창고, 주차장
static func _pack(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, v: Vector2, sc: float,
		rng: RandomNumberGenerator, mx: int) -> float:
	var top := 0.0
	_pad(host, out, en, u, 640.0 * sc, 520.0 * sc)
	for i in 4:
		if _full(out, mx):
			break
		var at := en + u * ((i % 2) * 190.0 - 95.0) * sc + v * (int(i / 2) * 120.0 - 60.0) * sc
		var t := box(host, out, at, u, rng.randf_range(130.0, 170.0) * sc, rng.randf_range(65.0, 85.0) * sc, rng.randf_range(13.0, 18.0),
			Color(0.8, 0.78, 0.74), 0.1)
		top = maxf(top, t - host._ground_y(at))
		for k in 5:
			box(host, out, at + u * (-50.0 + 25.0 * k), u, 8.0, 6.0, 3.5, Color(0.6, 0.6, 0.6), 0.0, t)
	box(host, out, en + v * (190.0 * sc), u, 180.0 * sc, 80.0, 12.0, Color(0.72, 0.7, 0.66), 0.06)
	box(host, out, en - v * (190.0 * sc), u, 160.0, 60.0, 0.4, Color(0.26, 0.26, 0.27))
	host._add(en + u * (260.0 * sc), 36.0, 26.0, rng.randf_range(20.0, 36.0), 0.6, atan2(u.y, u.x), float(out.get("y0", NAN)))
	return top


## 칩 설계·연구: 유리 사옥 대여섯 동이 잔디 마당을 둘러싼다
static func _lab(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, v: Vector2, sc: float,
		rng: RandomNumberGenerator, _mx: int) -> float:
	_pad(host, out, en, u, 520.0 * sc, 420.0 * sc)
	box(host, out, en, u, 220.0 * sc, 160.0 * sc, 0.5, Color(0.27, 0.42, 0.22))
	var top := 0.0
	var n := 5 + int(rng.randf() * 2.0)
	for i in n:
		var a := TAU * i / n
		var at := en + (u * cos(a) * 170.0 + v * sin(a) * 130.0) * sc
		var h := rng.randf_range(22.0, 48.0)
		host._add(at, rng.randf_range(50.0, 72.0), rng.randf_range(28.0, 40.0), h, GLASS_OFFICE, a + atan2(u.y, u.x),
			float(out.get("y0", NAN)))
		top = maxf(top, h)
	box(host, out, en + v * (185.0 * sc), u, 150.0, 40.0, 0.4, Color(0.26, 0.26, 0.27))
	return top


## 데이터센터: 긴 전산동 줄 + 지붕 냉각기 격자 + 비상 발전기 마당 + 변전소
static func _dc(host: MetroCity, out: Dictionary, en: Vector2, u: Vector2, v: Vector2, sc: float,
		rng: RandomNumberGenerator, mx: int) -> float:
	var top := 0.0
	var n := 3 + int(rng.randf() * 2.99)
	_pad(host, out, en, u, 900.0 * sc, (float(n) * 110.0 + 120.0) * sc)
	for i in n:
		if _full(out, mx):
			break
		var at := en + v * ((i - (n - 1) * 0.5) * 110.0 * sc)
		var w := rng.randf_range(190.0, 250.0) * sc
		var col := Color(0.38, 0.39, 0.42) if i % 2 == 0 else Color(0.62, 0.63, 0.66)
		var t := box(host, out, at, u, w, 60.0, rng.randf_range(15.0, 20.0), col, 0.22)
		top = maxf(top, t - host._ground_y(at))
		# 지붕 냉각기: 두 줄
		for k in 10:
			if _full(out, mx):
				break
			var q := at + u * (-w * 0.42 + w * 0.84 * k / 9.0)
			box(host, out, q + v * 14.0, u, 9.0, 9.0, 3.0, Color(0.78, 0.79, 0.8), 0.0, t)
			box(host, out, q - v * 14.0, u, 9.0, 9.0, 3.0, Color(0.78, 0.79, 0.8), 0.0, t)
		# 비상 발전기 마당 (전산동 끝)
		for k2 in 6:
			box(host, out, at + u * (w * 0.5 + 18.0) + v * (-25.0 + 10.0 * k2), u, 12.0, 4.0, 4.0, Color(0.3, 0.31, 0.32))
	# 변전소: 자갈 마당, 변압기, 철탑
	var sub := en + u * (380.0 * sc)
	box(host, out, sub, u, 120.0, 80.0, 0.3, Color(0.5, 0.5, 0.48))
	for k3 in 8:
		box(host, out, sub + u * (-40.0 + 26.0 * (k3 % 4)) + v * (-15.0 + 30.0 * int(k3 / 4)), u, 8.0, 6.0, 6.0, Color(0.52, 0.54, 0.55), 0.05)
	for k4 in 4:
		box(host, out, sub + v * (55.0 + 40.0 * k4), u, 2.5, 2.5, 34.0, Color(0.62, 0.63, 0.64))
	box(host, out, en - u * (330.0 * sc), u, 120.0, 60.0, 0.4, Color(0.26, 0.26, 0.27))
	return top
