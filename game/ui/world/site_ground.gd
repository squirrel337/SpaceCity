class_name SiteGround
extends Node3D
## 도시가 앉는 땅의 공통 틀 — 달 남극(MoonSurface)과 다른 천체의 부지(SiteSurface)가 따른다.
## 3D 도시(City3D)는 이 틀만 보고 건물을 땅에 놓는다. 좌표는 기지 모형 좌표: 미터, x·y 수평, 원점 = 기지 평지.
## 자세한 도시는 지금 고른 식민지 하나만 그린다 (active) — 밤의 불빛·그늘도 그 땅만 정한다.

signal terrain_ready

var body := "moon"
var city_root: Node3D
var layout: BaseLayout
var active := false:             # 지금 고른 식민지의 땅인가
	set(v):
		if v != active:
			active = v
			_active_changed()

var _site := Vector3(0, 0, -1)   # 기지 평지 중심 (천체 고정 단위 벡터)
var _site_basis := Basis()       # 모형 x, y, z → 천체 고정
var _plateau_m := 0.0            # 평지 높이 (기준 구 위, m)
var _cam_alt_km := 1e9
var _dark_k := 0.0
var raise_sun := true            # 기지 가까이에서 해를 지평선 위로 올린다 (대도시는 실제 밤을 그대로)
## 지형 조각의 높이 격자 (극좌표: 300 m까지 6 m 고리, 그 바깥은 둘레 간격만큼 커진다) — 굽은 값에 땅 고치기를 더한다
var _segs := 192
var _rings := 0                         # 고리 수 (중심 포함)
var _grow := 1.0
var _hgrid := PackedFloat32Array()      # 높이 (기지 평지 기준 m) [고리 × 둘레] — 고친 땅·길 다듬기를 더한 값
var _hbase := PackedFloat32Array()      # 구운 높이 (고치기 전)
var _wet_base := PackedByteArray()      # 구운 물 몫 (0~255) — 물이 있는 천체의 땅만
var _himg: Image                        # 지형 조각 셰이더가 읽는 높이 지도 (고친 값으로 다시 쓴다)
var _htex: ImageTexture
var _hbytes := PackedByteArray()        # 구운 높이 지도의 바이트 (고치기 전 — 달은 법선, 다른 천체는 물 몫을 되살린다)
var sea_z := NAN                        # 해수면 (기지 평지 기준 m) — 바다가 있는 천체의 땅만
var flooded := {}                       # 물에 잠긴 꼭짓점 번호 → true (해수면 아래로 판 땅)
var _terrain_sig := ""

signal flooded_changed(count: int)


func site_dir() -> Vector3:
	return _site


func site_frame() -> Basis:
	return _site_basis


func radius_km() -> float:
	return 1000.0


func radius_m() -> float:
	return radius_km() * 1000.0


func plateau_km() -> float:
	return _plateau_m / 1000.0


## 고른 도시가 되거나 그만둘 때 (다른 천체의 땅은 이때 굽거나 고운 지도를 내려놓는다)
func _active_changed() -> void:
	pass


## 지형 조각의 반지름 (m) — 그 안의 높이는 height_km이 안다
func patch_radius_m() -> float:
	return 0.0


## 천체 고정 방향이 이 땅의 지형 조각 안인가
func covers(dir_b: Vector3) -> bool:
	return (dir_b.normalized() - _site).length() * radius_m() < patch_radius_m()


## 기지 둘레의 높이 (m, 기지 평지 기준, 모형 좌표 x, y)
func local_height_m(_p: Vector2) -> float:
	return 0.0


## 고치기 전 땅 높이 (m, 기지 평지 기준) — 평탄화·침수 안내가 쓴다
func base_height_m(p: Vector2) -> float:
	if _hbase.is_empty():
		return local_height_m(p)
	return _sample(_hbase, p, _rings - 1)


## 천체 고정 방향의 지형 높이 (km, 기준 구 위)
func height_km(_dir_b: Vector3) -> float:
	return plateau_km()


## 매 프레임: 땅과 도시 뿌리를 카메라 둘레의 렌더 좌표에 놓는다
func update_frame(_view: WorldView, _info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	pass


## 기지 가까이에서는 해를 지평선 위 7° 이상으로 올린다 (낮은 해 아래 땅이 거의 검지 않게)
func adjust_light(dir: Vector3, view: WorldView) -> Vector3:
	var k := 1.0 - smoothstep(30.0, 600.0, _cam_alt_km)
	if k <= 0.0 or view == null or not raise_sun:
		return dir
	var f: Basis = view._info(body)["frame"]
	var up := WorldView.g_vec(f * _site)
	var to_sun := -dir
	var elev := asin(clampf(to_sun.dot(up), -1.0, 1.0))
	var want := maxf(elev, deg_to_rad(7.0))
	var horiz := (to_sun - up * to_sun.dot(up))
	if horiz.length_squared() < 1e-10:
		return dir
	horiz = horiz.normalized()
	var adj := (horiz * cos(want) + up * sin(want)).normalized()
	return -(to_sun.slerp(adj, k)).normalized()


## 기지 가까이(고도 40 km 아래)일수록 1 — 그림자·반사광을 켠다
func near_base_factor() -> float:
	return 1.0 - smoothstep(12.0, 40.0, _cam_alt_km)


## 시뮬레이션이 '어둠'이면 기지 가까이에서 햇빛을 끈다 (멀리서 보면 천체 전체는 그대로 밝다)
func local_light_factor() -> float:
	var k := 1.0 - smoothstep(40.0, 900.0, _cam_alt_km)
	return lerpf(1.0, 0.03, _dark_k * k)


## 해의 방향 (기지 모형 좌표: x·y 수평, z 위)
func sun_in_site(view: WorldView) -> Vector3:
	var info: Dictionary = view._info(body)
	var sun := view._info("sun")
	var rel := Astro.vec(Astro.norm3(Astro.sub3(sun["center"], info["center"])))
	var b: Vector3 = (info["frame"] as Basis).inverse() * rel
	return _site_basis.inverse() * b


func cam_alt_km() -> float:
	return _cam_alt_km


## 고른 식민지의 땅이면 시뮬레이션의 어둠을 따라 밤으로 (건물 불빛도 함께)
func _follow_dark(view: WorldView) -> void:
	var target := 1.0 if (active and view.sim and view.sim.is_dark()) else 0.0
	_dark_k = move_toward(_dark_k, target, get_process_delta_time() / 0.8 if is_inside_tree() else 1.0)
	if active:
		ModelLib.set_night(_dark_k)


## 천체 고정 → 렌더 좌표의 기지 변환 (평지 원점, 모형 축). 땅 조각과 도시 뿌리가 함께 쓴다
func _site_transform(view: WorldView, info: Dictionary) -> Transform3D:
	var c: PackedFloat64Array = info["center"]
	var f: Basis = info["frame"]
	var s := view.body_scale(c)
	var site_e := Astro.bmul(f, Astro.dvec(_site))
	var origin := Astro.add3(c, Astro.scale3(site_e, radius_km() + _plateau_m / 1000.0))
	var rel := Astro.sub3(origin, view.cam.pos)
	var o := Vector3(rel[0] * s, rel[2] * s, -rel[1] * s)
	var bs := f * _site_basis
	var cam_rel := Astro.sub3(view.cam.pos, c)
	var cam_d := Astro.len3(cam_rel)
	_cam_alt_km = cam_d - radius_km() - _plateau_m / 1000.0
	return Transform3D(WorldView.g_basis(bs).scaled(Vector3.ONE * s * 0.001), o)


## 카메라가 기지 쪽 반구에 있나 (천체 반대편이면 땅 조각을 감춘다)
func _near_site(view: WorldView, info: Dictionary) -> bool:
	var c: PackedFloat64Array = info["center"]
	var f: Basis = info["frame"]
	var cam_rel := Astro.sub3(view.cam.pos, c)
	var cam_d := Astro.len3(cam_rel)
	return (f.inverse() * Astro.vec(Astro.scale3(cam_rel, 1.0 / cam_d))).dot(_site) > cos(0.6)


# ── 땅 고치기 ───────────────────────────────────────────────────
## 고리 k의 반지름 (m) — 지형 조각 메시와 같다
func ring_m(k: int) -> float:
	if k <= 50:
		return 6.0 * k
	return minf(300.0 * pow(_grow, k - 50), 60000.0)


## 반지름 r(m)의 고리 번호 (소수)
func _ring_of(r: float) -> float:
	if r <= 300.0:
		return r / 6.0
	return 50.0 + log(r / 300.0) / log(_grow)


func _vert_pos(k: int, i: int) -> Vector2:
	var a := TAU * i / _segs
	var r := ring_m(k)
	return Vector2(cos(a) * r, sin(a) * r)


## 굽은 높이를 받아 둔다 (굽기가 끝날 때 하위 클래스가 부른다). img = 지형 조각 셰이더의 높이 지도.
## wet_from_alpha: 알파가 물 몫인 지도 (다른 천체) — 물에 잠긴 꼭짓점의 높이 가운데값을 해수면으로 본다
func _keep_baked(img: Image, tex: ImageTexture, wet_from_alpha: bool) -> void:
	_hbase = _hgrid.duplicate()
	_himg = img
	_htex = tex
	_hbytes = img.get_data() if img != null else PackedByteArray()
	_terrain_sig = ""
	sea_z = NAN
	flooded = {}
	_wet_base = PackedByteArray()
	if wet_from_alpha and img != null:
		_wet_base.resize(_rings * _segs)
		var lows := PackedFloat32Array()
		for idx in _rings * _segs:
			var w := _hbytes[idx * 4 + 3]
			_wet_base[idx] = w
			@warning_ignore("integer_division")
			var k := idx / _segs
			if w > 200 and ring_m(k) < 0.8 * patch_radius_m():
				lows.append(_hbase[idx])
		if lows.size() > 8:
			lows.sort()
			@warning_ignore("integer_division")
			sea_z = lows[lows.size() / 2]       # 바다 칸은 해수면으로 고르게 구워졌다


## 계획의 땅 고치기와 길을 지형에 넣는다 (바뀌었을 때만): 구운 높이 + 고친 높이 → 길 밑 다듬기 → 해수면 아래로 판 땅은 물.
## 바뀐 꼭짓점만 높이 지도에 다시 쓰고, 도시가 건물·길을 새 높이에 놓도록 알린다
func apply_terrain(plan: CityPlan) -> void:
	if _hbase.is_empty() or plan == null:
		return
	var sig := "%d|%d|%d" % [plan.get_instance_id(), plan.terrain_rev, plan.road_rev]
	if sig == _terrain_sig:
		return
	_terrain_sig = sig
	var t := LayoutData.terrain()
	var kmax := mini(int(ceil(_ring_of(plan.edit_radius()))) + 1, _rings - 1)
	var n := (kmax + 1) * _segs
	var hh := _hbase.slice(0, n)
	var dug := PackedByteArray()
	dug.resize(n)
	if not plan.terrain.is_empty():
		for idx in n:
			@warning_ignore("integer_division")
			var p := _vert_pos(idx / _segs, idx % _segs)
			var dlt := plan.terrain_delta(p)
			if absf(dlt) > 0.004:
				hh[idx] += dlt
				dug[idx] = 1 if dlt < -0.05 else 0
	_grade_roads(plan, hh, kmax, float(t["road_shoulder_m"]))
	for i in range(1, _segs):
		hh[i] = hh[0]            # 고리 0은 한 점 (가운데)
	# 물: 바다가 있는 천체에서 해수면 아래로 판 땅 (꼭짓점은 그림, 칸은 계획 — 건물·길이 본다)
	var new_flood := {}
	var cells := {}
	if not is_nan(sea_z):
		for idx in n:
			if dug[idx] == 1 and hh[idx] < sea_z - 0.05:
				new_flood[idx] = true
		var cm := CityPlan.cell_m()
		for key in plan.terrain:
			var dv := float(plan.terrain[key])
			if dv >= -0.05:
				continue
			var p := Vector2(key) * cm
			if p.length() > ring_m(kmax):
				continue
			var depth := sea_z - (_sample(_hbase, p, kmax) + dv)
			if depth > 0.05:
				cells[key] = snappedf(depth, 0.1)
	plan.set_flood(cells)
	var changed := PackedInt32Array()
	for idx in n:
		var was_wet := flooded.has(idx)
		if absf(hh[idx] - _hgrid[idx]) > 0.003 or was_wet != new_flood.has(idx):
			changed.append(idx)
	var n_before := flooded.size()
	flooded = new_flood
	for idx in changed:
		_hgrid[idx] = hh[idx]
	if not changed.is_empty():
		_encode_heights(changed)
		if _htex != null and _himg != null:
			_htex.update(_himg)
		terrain_ready.emit()
	if flooded.size() != n_before:
		flooded_changed.emit(flooded.size())


## 길 밑 다듬기: 길을 따라 2 m마다 땅 높이를 재어 고르게 하고 (기울기는 길 종류의 한도까지), 길 폭 + 어깨 안의
## 꼭짓점을 그 높이로 맞춘다 (가장자리는 비탈로). 평평한 땅이면 건너뛴다
func _grade_roads(plan: CityPlan, hh: PackedFloat32Array, kmax: int, shoulder: float) -> void:
	var target := {}
	var weight := {}
	for k in plan.edges.size():
		var e: Vector2i = plan.edges[k]
		var a: Vector2 = plan.nodes[e.x]
		var b: Vector2 = plan.nodes[e.y]
		var length := a.distance_to(b)
		if length < 0.5:
			continue
		var type := plan.edge_type(k)
		var hw := LayoutData.road_half(type)
		var grade := float(LayoutData.road(type)["grade"])
		var steps := maxi(1, int(ceil(length / 2.0)))
		var prof := PackedFloat32Array()
		var lo := INF
		var hi := -INF
		for j in steps + 1:
			var hj := _sample(hh, a.lerp(b, float(j) / steps), kmax)
			prof.append(hj)
			lo = minf(lo, hj)
			hi = maxf(hi, hj)
		if hi - lo < 0.06:
			continue            # 평평한 땅 (기지 평지): 다듬을 것이 없다
		# 고르게: 앞뒤 5칸 평균, 그다음 기울기 한도 (앞으로·뒤로 한 번씩)
		var sm := PackedFloat32Array()
		sm.resize(prof.size())
		for j in prof.size():
			var acc := 0.0
			var cnt := 0
			for q in range(maxi(0, j - 5), mini(prof.size(), j + 6)):
				acc += prof[q]
				cnt += 1
			sm[j] = acc / cnt
		var dmax := grade * length / steps
		for j in range(1, sm.size()):
			sm[j] = clampf(sm[j], sm[j - 1] - dmax, sm[j - 1] + dmax)
		for j in range(sm.size() - 2, -1, -1):
			sm[j] = clampf(sm[j], sm[j + 1] - dmax, sm[j + 1] + dmax)
		var reach := hw + shoulder
		for j in sm.size():
			var c := a.lerp(b, float(j) / steps)
			for idx in _near_verts(c, reach + 4.0, kmax):
				@warning_ignore("integer_division")
				var p := _vert_pos(idx / _segs, idx % _segs)
				var q := CityPlan._seg_point(a, b, p)
				var d := q.distance_to(p)
				if d > reach:
					continue
				var w := 1.0 - smoothstep(hw + 0.5, reach, d)
				if w > float(weight.get(idx, 0.0)):
					var tq := clampf(a.distance_to(q) / length, 0.0, 1.0) * steps
					var j0 := int(floor(tq))
					var j1 := mini(j0 + 1, steps)
					weight[idx] = w
					target[idx] = lerpf(sm[j0], sm[j1], tq - j0)
	for idx in target:
		hh[idx] = lerpf(hh[idx], float(target[idx]), float(weight[idx]))


## 높이 배열 hh(고리 0~kmax)의 점 p 높이 (이중선형)
func _sample(hh: PackedFloat32Array, p: Vector2, kmax: int) -> float:
	var rk := clampf(_ring_of(p.length()), 0.0, float(kmax))
	var k0 := int(floor(rk))
	var k1 := mini(k0 + 1, kmax)
	var fk := rk - k0
	var a := fposmod(atan2(p.y, p.x), TAU) / TAU * _segs
	var i0 := int(floor(a)) % _segs
	var i1 := (i0 + 1) % _segs
	var fi := a - floorf(a)
	return lerpf(lerpf(hh[k0 * _segs + i0], hh[k0 * _segs + i1], fi), lerpf(hh[k1 * _segs + i0], hh[k1 * _segs + i1], fi), fk)


## 점 p에서 r(m) 안의 꼭짓점 번호들 (고리 0~kmax)
func _near_verts(p: Vector2, r: float, kmax: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var rr := p.length()
	var k_lo := maxi(0, int(floor(_ring_of(maxf(rr - r, 0.0)))))
	var k_hi := mini(kmax, int(ceil(_ring_of(rr + r))))
	var a := fposmod(atan2(p.y, p.x), TAU)
	var da := r / maxf(rr, r) + 0.0001
	var i_c := int(round(a / TAU * _segs))
	var i_r := int(ceil(da / TAU * _segs)) + 1
	if rr < r * 1.5:
		@warning_ignore("integer_division")
		i_r = _segs / 2
	for k in range(k_lo, k_hi + 1):
		if k == 0:
			out.append(0)
			continue
		for di in range(-i_r, i_r + 1):
			out.append(k * _segs + posmod(i_c + di, _segs))
	return out


## 높이를 구웠나 (구운 높이가 있어야 땅 구역의 비탈·물을 제대로 잰다)
func baked_heights() -> bool:
	return not _hbase.is_empty()


## 높이 격자를 곧 굽나 — 그러면 도시는 길·구획을 구운 뒤에 깐다 (굽기 전 높이는 셈이 몇 배 느리고 다시 깔아야 한다)
func will_bake() -> bool:
	return false


## 이 점이 물인가: 바다·호수(구운 물 몫, 메워 뭍이 된 곳은 뺀다) 또는 해수면 아래로 판 땅
func water_at(p: Vector2) -> bool:
	if _rings == 0 or _hgrid.is_empty():
		return false
	var rk := clampf(_ring_of(p.length()), 0.0, float(_rings - 1))
	var k := int(round(rk))
	var i := int(round(fposmod(atan2(p.y, p.x), TAU) / TAU * _segs)) % _segs
	var idx := k * _segs + i
	if flooded.has(idx):
		return true
	if _wet_base.is_empty() or idx >= _wet_base.size():
		return false
	return _wet_base[idx] > 127 and (is_nan(sea_z) or _hgrid[idx] <= sea_z + 0.25)


## 이 점이 물에 잠겼나 (둘레 꼭짓점 넷 중 하나라도)
func flooded_at(p: Vector2) -> bool:
	if flooded.is_empty() or _rings == 0:
		return false
	var rk := _ring_of(p.length())
	var k0 := int(floor(rk))
	var a := fposmod(atan2(p.y, p.x), TAU) / TAU * _segs
	var i0 := int(floor(a)) % _segs
	for k in [k0, k0 + 1]:
		for i in [i0, (i0 + 1) % _segs]:
			if flooded.has(k * _segs + i):
				return true
	return false


## 바뀐 꼭짓점을 높이 지도에 다시 쓴다 (하위 클래스: 달은 16비트 높이 + 법선, 다른 천체는 24비트 높이 + 물 몫)
func _encode_heights(_changed: PackedInt32Array) -> void:
	pass

