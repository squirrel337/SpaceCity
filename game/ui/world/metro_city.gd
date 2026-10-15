class_name MetroCity
extends Node3D
## 지구 대도시의 시가지 — 실제 축척의 건물 수천~수만 채. 시가지 바닥의 길과 같은 블록 격자 위에, 도심·부도심일수록 높게
## 짓고 물(해안·강)과 공원에는 짓지 않는다. 무게 1인 도심에는 그 도시의 가장 높은 건물(max_h)이 선다.
## 모양은 도시의 시가지 모양(styles)을 따른다: 아파트 단지의 판상 동, 옛 시가지의 중정형 블록, 연립의 긴 줄, 마천루, 낮은 집.
## 건물은 단위 상자 하나(tower 셰이더가 층·창·유리 외벽·지붕을 그린다)를 MultiMesh로 2 km 칸마다 묶는다. 밤에는 창이 켜진다.
## 땅(대도시의 SiteSurface)의 모형 좌표 위에 선다: 미터, 원점 = 도심. 땅을 구운 뒤 몇 프레임에 걸쳐 짓는다.

const CHUNK_M := 2000.0
const GEN_R := 12000.0           # 블록을 고르는 반지름 (그 밖의 부도심은 둘레만)
const FAR_CENTER_R := 2600.0
const ROWS_PER_FRAME := 24
const BLOCKS_PER_FRAME := 900

var metro: Dictionary
var ground: SiteSurface
var budget := 26000
var count := 0                   # 지은 건물 수
var _style: Dictionary
var _map: Image
var _half_km := 30.0
var _mat: ShaderMaterial
var _box: ArrayMesh
var _east := Vector3.ZERO
var _north := Vector3.ZERO
var _ax := Vector3.ZERO
var _ay := Vector3.ZERO
var _uu := Vector2(0, 1)         # 큰길 방향 (동·북 좌표)
var _vv := Vector2(1, 0)
var _block := 120.0
var _radius_m := 20000.0
var _gen_r := 12000.0
var _centers: Array = []         # [동, 북, 무게]
var _cands: Array = []           # [점수, 동, 북, 밀도, 영향]
var _phase := 0                  # 0 땅 기다림 · 1 블록 고르기 · 2 짓기 · 3 끝
var _row := 0
var _n := 0
var _cursor := 0
var _chunks := {}                # Vector2i → {xf: Array[Transform3D], col: PackedColorArray, cus: PackedColorArray}
var _rng := RandomNumberGenerator.new()
var _shadows := true
var mgr: Colonies                # 우주 시설 (도시 기능)을 읽는다
var _fac_root: Node3D
var _fac_sig := ""
var _fac_labels: Array = []      # [[모형 좌표 Vector3 (부모 로컬), 이름, 둘째 줄, 색]]
var _beacons: Array = []


func setup(m: Dictionary, g: SiteSurface, hi: bool) -> void:
	metro = m
	ground = g
	budget = int(Settings.q("metro_budget"))
	_shadows = hi
	_style = Metros.style_of(m)
	var c: Vector3 = m["dir"]
	_east = Vector3(-c.y, c.x, 0.0).normalized()
	_north = c.cross(_east)
	_ax = g.site_frame().x
	_ay = g.site_frame().y
	_half_km = float(m["radius_km"]) + 10.0
	var tex := PlanetLook.coast_local(String(m["key"]))
	if tex != null:
		_map = tex.get_image()
		if _map != null and _map.is_compressed():
			_map.decompress()
	var th := deg_to_rad(float(m.get("grid_deg", 0.0)))
	_uu = Vector2(sin(th), cos(th))
	_vv = Vector2(cos(th), -sin(th))
	_block = float(_style.get("block_m", 120.0))
	_radius_m = float(m["radius_km"]) * 1000.0
	_gen_r = minf(_radius_m, GEN_R)
	for cc in m.get("centers", []):
		var en := _en_of(float(cc[1]), float(cc[2]))
		_centers.append([en.x, en.y, float(cc[3])])
	_n = int(ceil(_gen_r / _block)) + 1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/world/shaders/tower.gdshader")
	_box = _box_mesh()


## 위도·경도 → 도심에서 동·북 (m, 접평면)
func _en_of(lat: float, lon: float) -> Vector2:
	var d := Astro.latlon(lat, lon)
	var c: Vector3 = metro["dir"]
	var w := maxf(d.dot(c), 1e-6)
	return Vector2(d.dot(_east), d.dot(_north)) * 6371000.0 / w


## 동·북 (m) → 땅의 모형 좌표 (m)
func _model(en: Vector2) -> Vector2:
	var t := _east * en.x + _north * en.y
	return Vector2(t.dot(_ax), t.dot(_ay))


## 시가지 지도: [해안·강까지의 거리 km (땅 +), 공원(0~1)]
func _sample(en: Vector2) -> Vector2:
	if _map == null:
		return Vector2(2.0, 0.0)
	var u := 0.5 + en.x / 1000.0 / (2.0 * _half_km)
	var v := 0.5 - en.y / 1000.0 / (2.0 * _half_km)
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return Vector2(2.0, 0.0)
	var px := _map.get_pixel(int(u * _map.get_width()), int(v * _map.get_height()))
	return Vector2((px.r - 0.5) * 4.0, px.g)


func _influence(en: Vector2) -> float:
	var best := 0.0
	for c in _centers:
		var w: float = c[2]
		var sig := 650.0 + 900.0 * w
		var d2 := (en - Vector2(c[0], c[1])).length_squared()
		best = maxf(best, w * exp(-d2 / (sig * sig)))
	return best


# ── 매 프레임: 몇 프레임에 걸쳐 짓는다 ──────────────────────────
func update(_view: WorldView) -> void:
	if _mat:
		_mat.set_shader_parameter("night", ground.night_k)
	if _phase == 3 and mgr != null:
		_update_facilities()
	for bm in _beacons:
		(bm as ShaderMaterial).set_shader_parameter("night", ground.night_k)
	match _phase:
		0:
			if ground.baked():
				_phase = 1
				_row = -_n
		1:
			_pick_rows()
		2:
			_build_some()


## 블록 고르기: 격자를 줄마다 훑어 물·공원이 아닌 블록에 점수를 매긴다 (도심 영향 + 밀도)
func _pick_rows() -> void:
	var end := mini(_row + ROWS_PER_FRAME, _n)
	var far: Array = []
	for c in _centers:
		if Vector2(c[0], c[1]).length() > _gen_r - 600.0:
			far.append(Vector2(c[0], c[1]))
	for i in range(_row, end):
		for j in range(-_n, _n):
			_consider(Vector2(i + 0.5, j + 0.5) * _block, far, false)
	# 먼 부도심 둘레
	if end >= _n:
		for fc in far:
			var nf := int(ceil(FAR_CENTER_R / _block)) + 1
			var gi := int(floor((fc as Vector2).dot(_vv) / _block))
			var gj := int(floor((fc as Vector2).dot(_uu) / _block))
			for i2 in range(gi - nf, gi + nf):
				for j2 in range(gj - nf, gj + nf):
					_consider(Vector2(i2 + 0.5, j2 + 0.5) * _block, [fc], true)
		_cands.sort_custom(func(a, b): return a[0] > b[0])
		_phase = 2
		_cursor = 0
		_landmarks()
	_row = end


func _consider(g: Vector2, far: Array, only_far: bool) -> void:
	if only_far and absf(g.x) < _n * _block and absf(g.y) < _n * _block:
		return                                  # 큰 격자에서 이미 본 블록
	var en := _vv * g.x + _uu * g.y
	var dist := en.length()
	if only_far or dist > _gen_r:
		var ok := false
		for fc in far:
			if en.distance_to(fc) < FAR_CENTER_R:
				ok = true
				break
		if not ok or (only_far and dist <= _gen_r):
			return
	var s := _sample(en)
	if s.x < 0.035 or s.y > 0.5:
		return
	var h := _hash(g)
	# 가장자리는 성기게 (짓는 반지름의 75%부터) — 둥근 경계가 보이지 않게
	if not only_far and dist > _gen_r * 0.72 and h < (dist - _gen_r * 0.72) / (_gen_r * 0.28):
		return
	var dens := 1.0 - smoothstep(_radius_m * 0.08, _radius_m * (0.92 + 0.25 * (h - 0.5)), dist)
	var infl := _influence(en)
	if dens < 0.04 and infl < 0.05:
		return
	# 도심에서 바깥으로 차례로 (부도심 둘레는 앞당긴다) — 예산이 다하면 바깥은 바닥의 시가지 무늬가 맡는다
	_cands.append([dens + 0.9 * infl + h * 0.08, en.x, en.y, dens, infl, minf(s.x, 0.6), dist])


func _hash(g: Vector2) -> float:
	return float(absi(hash(Vector3i(int(floor(g.x)), int(floor(g.y)), String(metro["id"]).hash()))) % 100000) / 100000.0


## 도심의 마천루: 무게 1이면 그 도시의 가장 높은 건물, 둘레에 몇 채 더 (물이면 가까운 땅으로)
func _landmarks() -> void:
	var max_h := float(metro.get("max_h", 200.0))
	for c in _centers:
		var w: float = c[2]
		if w < 0.6:
			continue
		var en := _land_near(Vector2(c[0], c[1]))
		if en.x == INF:
			continue
		_rng.seed = absi(hash(Vector2i(int(en.x), int(en.y))))
		var h := max_h * pow(w, 2.2) if w < 0.98 else max_h
		var side := clampf(h * 0.11, 28.0, 80.0)
		_add(en, side, side, h, 0.85, 0.0)
		for k in int(2 + w * 4):
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(side * 1.4, 420.0)
			var p := en + Vector2(cos(a), sin(a)) * r
			if _sample(p).x < 0.06:
				continue
			var h2 := h * _rng.randf_range(0.3, 0.7)
			var s2 := clampf(h2 * 0.14, 22.0, 60.0)
			_add(p, s2, s2 * _rng.randf_range(0.8, 1.3), h2, 0.8, _rng.randf() * 0.3)


func _land_near(en: Vector2) -> Vector2:
	if _sample(en).x >= 0.08:
		return en
	for ring in range(1, 12):
		for k in 12:
			var a := TAU * k / 12.0
			var p := en + Vector2(cos(a), sin(a)) * ring * 120.0
			if _sample(p).x >= 0.08:
				return p
	return Vector2(INF, INF)


func _build_some() -> void:
	var end := mini(_cursor + BLOCKS_PER_FRAME, _cands.size())
	for k in range(_cursor, end):
		if count >= budget:
			end = _cands.size()
			break
		var c: Array = _cands[k]
		_block_buildings(Vector2(c[1], c[2]), float(c[3]), float(c[4]), float(c[5]), float(c[6]))
	_cursor = end
	if _cursor >= _cands.size():
		_commit()
		_phase = 3
		_cands.clear()


## 블록 하나의 건물들 (시가지 모양에 따라). 도심에서 먼 블록(부도심 밖 5 km 너머)은 덩어리 건물 하나로
func _block_buildings(en: Vector2, dens: float, infl: float, shore_km: float, dist: float) -> void:
	_rng.seed = absi(hash(Vector2i(int(en.x), int(en.y)))) + 7
	var b := _block
	var inner := b - 16.0                       # 길 폭을 뺀 블록
	if shore_km < 0.12:
		inner = minf(inner, shore_km * 1000.0 * 1.6)
	if inner < 12.0:
		return
	var mid_h := float(_style.get("mid_h", 25.0))
	var low_h := float(_style.get("low_h", 8.0))
	var slab := float(_style.get("slab", 0.0))
	var max_h := float(metro.get("max_h", 200.0))
	var style := String(metro.get("style", "dense"))
	var base_h := lerpf(low_h, mid_h, pow(dens, 1.1))
	if dist > 5000.0 and infl < 0.2:
		# 먼 블록: 크기·높이·자리가 제각각인 덩어리 한두 채 (빈 블록도 있다)
		if _rng.randf() < 0.18:
			return
		var cover := float(_style.get("cover", 0.5))
		var n_far := 1 if _rng.randf() < 0.65 else 2
		for k3 in n_far:
			var side := inner * sqrt(clampf(cover * 1.3, 0.25, 0.85)) * _rng.randf_range(0.5, 1.0) / sqrt(float(n_far))
			var off5 := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (inner - side) * 0.5
			_add(_local_en(en, off5), side, side * _rng.randf_range(0.55, 1.0), base_h * _rng.randf_range(0.5, 1.6), 0.15, 0.0)
		return
	# 마천루 (도심·부도심)
	if _rng.randf() < infl * 0.9:
		var n_t := 1 + int(_rng.randf() * 2.0 * infl)
		for t in n_t:
			var h := lerpf(mid_h * 1.6, max_h * 0.7, pow(infl, 1.4) * pow(_rng.randf(), 0.7))
			var s := clampf(h * _rng.randf_range(0.12, 0.2), 24.0, minf(inner * 0.6, 70.0))
			var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (inner - s) * 0.5
			_add(_local_en(en, off), s, s * _rng.randf_range(0.8, 1.4), h, _rng.randf_range(0.65, 0.95), 0.0)
		if infl > 0.35:
			return
	# 아파트 단지: 길이 60~90 m의 판상 동이 줄지어 (넓은 블록은 두 줄)
	if slab > 0.0 and _rng.randf() < slab * (0.35 + 0.65 * dens):
		var rows := 3 + int(_rng.randf() * 2.0)
		var cols := 2 if inner > 120.0 else 1
		var gap := inner / rows
		var length := minf(inner / cols * 0.82, 92.0)
		var h2 := mid_h * _rng.randf_range(0.75, 1.3)
		for r in rows:
			for c in cols:
				var off2 := Vector2(-inner * 0.5 + inner / cols * (c + 0.5) + _rng.randf_range(-3, 3), -inner * 0.5 + gap * (r + 0.5))
				_add(_local_en(en, off2), length * _rng.randf_range(0.8, 1.0), 13.0, h2 + _rng.randf_range(-6, 6), 0.18, 0.0)
		return
	match style:
		"haussmann":
			# 중정형 블록: 네 변을 따라 같은 높이의 건물
			var t2 := 14.0
			var hh := base_h + _rng.randf_range(-2.0, 2.0)
			_add(_local_en(en, Vector2(0, (inner - t2) * 0.5)), inner, t2, hh, 0.15, 0.0)
			_add(_local_en(en, Vector2(0, -(inner - t2) * 0.5)), inner, t2, hh, 0.15, 0.0)
			_add(_local_en(en, Vector2((inner - t2) * 0.5, 0)), t2, inner - t2 * 2.0, hh, 0.15, 0.0)
			_add(_local_en(en, Vector2(-(inner - t2) * 0.5, 0)), t2, inner - t2 * 2.0, hh, 0.15, 0.0)
		"terrace":
			for side in [-1.0, 1.0]:
				_add(_local_en(en, Vector2(0, side * inner * 0.3)), inner * 0.92, 11.0, base_h * _rng.randf_range(0.8, 1.2), 0.12, 0.0)
		"sprawl", "desert":
			var n_h := 2 + int(dens * 4.0 * _rng.randf())
			for k in n_h:
				var s3 := _rng.randf_range(12.0, 22.0) * (1.0 + dens)
				var off3 := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (inner - s3) * 0.5
				_add(_local_en(en, off3), s3, s3 * _rng.randf_range(0.7, 1.3), base_h * _rng.randf_range(0.6, 1.5), 0.15, 0.0)
		_:
			var n_b := 1 + int(dens * 3.0 * _rng.randf() + 0.5)
			var cover := float(_style.get("cover", 0.5))
			for k2 in n_b:
				var w := inner * _rng.randf_range(0.3, 0.55) * sqrt(cover * 2.0)
				var d := inner * _rng.randf_range(0.3, 0.55) * sqrt(cover * 2.0)
				var off4 := Vector2(_rng.randf_range(-1, 1) * (inner - w) * 0.5, _rng.randf_range(-1, 1) * (inner - d) * 0.5)
				_add(_local_en(en, off4), w, d, base_h * _rng.randf_range(0.6, 1.45), _rng.randf_range(0.12, 0.4), 0.0)


## 블록 안의 자리 (블록 좌표 → 동·북)
func _local_en(en: Vector2, off: Vector2) -> Vector2:
	return en + _vv * off.x + _uu * off.y


## 건물 하나: 동·북 자리, 너비(큰길과 나란한 가로), 깊이, 높이, 유리 몫, 돌림(라디안)
func _add(en: Vector2, w: float, d: float, h: float, glass: float, turn: float) -> void:
	if count >= budget + 64 or h < 3.0:
		return
	var p := _model(en)
	var gy := ground.local_height_m(p) - p.length_squared() / (2.0 * ground.radius_m())
	var dir_m := _model(en + _vv) - p
	var yaw := atan2(dir_m.y, dir_m.x) + turn
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h + 3.0, d)), Vector3(p.x, gy - 3.0, -p.y))
	var tones: Array = _style.get("tone", ["#c8c4bc"])
	var col := Color(String(tones[_rng.randi() % tones.size()]))
	col = col * _rng.randf_range(0.72, 0.95)
	col.a = glass
	var key := Vector2i(int(floor(en.x / CHUNK_M)), int(floor(en.y / CHUNK_M)))
	if not _chunks.has(key):
		_chunks[key] = {"xf": [], "col": PackedColorArray(), "cus": PackedColorArray()}
	var ch: Dictionary = _chunks[key]
	ch["xf"].append(xf)
	ch["col"].append(col)
	ch["cus"].append(Color(h + 3.0, w, d, _rng.randf() * 100.0))
	count += 1


func _commit() -> void:
	for key in _chunks:
		var ch: Dictionary = _chunks[key]
		var xs: Array = ch["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _box
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_color(i, ch["col"][i])
			mm.set_instance_custom_data(i, ch["cus"][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_chunks.clear()


# ── 우주 시설 (도시 기능) ────────────────────────────────────────
## 시설이 바뀌거나 짓는 몫이 오르면 다시 놓는다: 시설마다 도심에서 몇 km 떨어진 땅에 단지(색 외벽의 건물 몇 채)와 빛기둥
func _update_facilities() -> void:
	var fn := mgr.metro_fn
	var key := String(metro["key"])
	var parts := PackedStringArray([str(fn.rev)])
	for fac in MetroFunctions.ORDER:
		parts.append("%d%s%d" % [fn.level(key, fac), "b" if fn.building(key, fac) else "", int(fn.progress(key, fac, mgr.hour) * 4.0)])
	var sig := ",".join(parts)
	if sig == _fac_sig:
		return
	_fac_sig = sig
	if _fac_root != null:
		_fac_root.queue_free()
	_fac_root = Node3D.new()
	add_child(_fac_root)
	_fac_labels.clear()
	_beacons.clear()
	var xs: Array = []
	var cols := PackedColorArray()
	var cus := PackedColorArray()
	for i in MetroFunctions.ORDER.size():
		var fac: String = MetroFunctions.ORDER[i]
		var lvl := fn.level(key, fac)
		var busy := fn.building(key, fac)
		if lvl == 0 and not busy:
			continue
		var en := _facility_site(i)
		if en.x == INF:
			continue
		var grow := lvl + (fn.progress(key, fac, mgr.hour) if busy else 0.0)
		var top := _campus(fac, en, maxf(grow, 0.35), xs, cols, cus)
		var col := MetroFunctions.fac_color(fac)
		var p := _model(en)
		var gy := ground.local_height_m(p) - p.length_squared() / (2.0 * ground.radius_m())
		_beacon(Vector3(p.x, gy, -p.y), col, busy)
		var sub := "%d단계" % lvl if not busy else ("짓는 중 %d%%" % int(fn.progress(key, fac, mgr.hour) * 100.0)
			+ (" (%d단계로)" % (lvl + 1) if lvl > 0 else ""))
		_fac_labels.append([Vector3(p.x, gy + top + 30.0, -p.y), MetroFunctions.fac_name(fac), sub, col])
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _box
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
		mm.set_instance_color(k, cols[k])
		mm.set_instance_custom_data(k, cus[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fac_root.add_child(mi)


## 시설 i의 자리 (동·북 m): 도시마다 다른 방향에서 72°씩, 도심에서 시가지 반지름의 20% (1.8~4.5 km) — 물·공원이면 가까운 땅
func _facility_site(i: int) -> Vector2:
	var base := float(absi(String(metro["id"]).hash()) % 360)
	var a := deg_to_rad(base + 72.0 * i)
	var r := clampf(_radius_m * 0.2, 1800.0, 4500.0)
	var en := Vector2(sin(a), cos(a)) * r
	for _try in 8:
		var s := _sample(en)
		if s.x >= 0.12 and s.y < 0.4:
			return en
		en = en.rotated(0.18) * 1.06
	return _land_near(en)


## 단지 하나 (시설마다 모양이 다르다). grow = 단계 (짓는 중이면 소수). 가장 높은 건물의 높이를 돌려준다
func _campus(fac: String, en: Vector2, grow: float, xs: Array, cols: PackedColorArray, cus: PackedColorArray) -> float:
	var col := MetroFunctions.fac_color(fac)
	var wall := Color(0.86, 0.87, 0.88).lerp(col, 0.55)
	var g := clampf(grow, 0.0, 3.0)
	var top := 0.0
	# [동·북 자리 (m, 단지 가운데에서), 너비, 깊이, 높이, 유리 몫]
	var parts: Array = []
	match fac:
		"space_park":
			for k in 3:
				parts.append([Vector2(-120.0 + 120.0 * k, -70.0), 100.0, 46.0, 16.0 + 3.0 * g, 0.2])
			parts.append([Vector2(-40.0, 60.0), 26.0, 26.0, 50.0 + 28.0 * g, 0.3])
			parts.append([Vector2(40.0, 60.0), 26.0, 26.0, 40.0 + 24.0 * g, 0.3])
			if g > 1.5:
				parts.append([Vector2(140.0, 40.0), 120.0, 50.0, 22.0, 0.2])
		"emigration":
			parts.append([Vector2(0.0, 0.0), 120.0, 70.0, 18.0 + 6.0 * g, 0.6])
			for k in int(1 + g):
				parts.append([Vector2(-110.0 + 75.0 * k, 90.0), 60.0, 15.0, 26.0 + 10.0 * g, 0.35])
		"research":
			for k in int(3 + g):
				var aa := TAU * k / (3.0 + floorf(g))
				parts.append([Vector2(cos(aa), sin(aa)) * 95.0, 46.0, 40.0, 14.0 + 7.0 * g, 0.7])
			parts.append([Vector2.ZERO, 24.0, 24.0, 50.0 + 25.0 * g, 0.8])
		"outreach":
			parts.append([Vector2.ZERO, 20.0, 20.0, 90.0 + 55.0 * g, 0.85])
			parts.append([Vector2(0.0, -70.0), 90.0, 60.0, 10.0 + 3.0 * g, 0.6])
		"cargo_hub":
			for k in int(1 + ceilf(g * 0.67)):
				parts.append([Vector2(-150.0 + 170.0 * k, 0.0), 150.0, 64.0, 20.0 + 3.0 * g, 0.15])
			parts.append([Vector2(0.0, 90.0), 14.0, 14.0, 46.0 + 6.0 * g, 0.7])
	var p0 := _model(en)
	var dir_m := _model(en + _vv) - p0
	var yaw := atan2(dir_m.y, dir_m.x)
	for q in parts:
		var e2 := _local_en(en, q[0])
		var p := _model(e2)
		var gy := ground.local_height_m(p) - p.length_squared() / (2.0 * ground.radius_m())
		var h: float = q[3]
		top = maxf(top, h)
		xs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(q[1], h + 3.0, q[2])), Vector3(p.x, gy - 3.0, -p.y)))
		var c := wall * (0.9 + 0.1 * _hash(e2))
		c.a = float(q[4])
		cols.append(c)
		cus.append(Color(h + 3.0, q[1], q[2], _hash(e2) * 100.0))
	return top


## 빛기둥 (멀리서도 보이게)
func _beacon(at: Vector3, col: Color, busy: bool) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 16.0
	cm.height = 900.0
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/world/shaders/beacon.gdshader")
	mat.set_shader_parameter("color", Color(1.0, 0.62, 0.25) if busy else col)
	mat.set_shader_parameter("height", 900.0)
	mat.set_shader_parameter("blink", 1.0 if busy else 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, 450.0, 0)
	_fac_root.add_child(mi)
	_beacons.append(mat)


## 시설 이름표: [[부모(땅의 도시 뿌리) 로컬 좌표, 이름, 둘째 줄, 색]]
func facility_labels() -> Array:
	return _fac_labels


## 단위 상자 (바닥 없음): x·z −0.5~0.5, y 0~1. UV = 면 안의 (가로, 세로), UV2.x = 면 (0 너비 쪽, 1 깊이 쪽, 2 지붕)
static func _box_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	# [바깥 법선, 가로 축, 면 종류]
	var faces := [[Vector3(0, 0, 1), Vector3(1, 0, 0), 0.0], [Vector3(0, 0, -1), Vector3(-1, 0, 0), 0.0],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), 1.0], [Vector3(-1, 0, 0), Vector3(0, 0, 1), 1.0]]
	for f in faces:
		var nn: Vector3 = f[0]
		var t: Vector3 = f[1]
		var base := v.size()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var p: Vector3 = nn * 0.5 + t * (corner.x - 0.5) + Vector3(0, corner.y, 0)
			v.append(p)
			n.append(nn)
			uv.append(Vector2(corner.x, 1.0 - corner.y))
			uv2.append(Vector2(f[2], 0.0))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	var top := v.size()
	for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		v.append(Vector3(corner.x, 1.0, corner.y))
		n.append(Vector3.UP)
		uv.append(corner + Vector2(0.5, 0.5))
		uv2.append(Vector2(2.0, 0.0))
	idx.append_array(PackedInt32Array([top, top + 1, top + 2, top, top + 2, top + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
