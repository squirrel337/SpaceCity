class_name ModelLib
extends RefCounted
## art/models.json → 3D 메시. 그림 생성기(tools/art)가 SVG와 같은 도형을 3차원 그대로 적어 둔 것이다.
## 모형 좌표는 미터: x·y 바닥, z 위. Godot로는 (x, z, -y) — 바닥이 XZ 평면, 위가 +Y (회전이라 거울상이 아니다).
## 면은 세 갈래로 나눈다: 몸체(불투명, 밤에 창이 빛난다), 유리(반투명), 불빛(더하기 혼합, 밤에만).
## 처음 쓸 때 만들어 둔다.

const PATH := "res://art/models.json"
const SHADERS := ["res://ui/world/shaders/model_body.gdshader", "res://ui/world/shaders/model_glass.gdshader",
	"res://ui/world/shaders/model_glow.gdshader"]
const BODY := 0
const GLASS := 1
const GLOW := 2
const LAMP_COLOR := Color(1.0, 0.95, 0.82)

static var path := PATH              # 모형 파일 (미리보기 도구가 바꿀 수 있다)
static var _data: Dictionary = {}
static var _pal: Array = []          # [Color(선형), gloss, alpha]
static var _cache: Dictionary = {}
static var _mats: Array = []


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_data = parsed if parsed is Dictionary else {"palette": [], "buildings": {}, "vehicles": {}}
		_pal.clear()
		for p in _data.get("palette", []):
			_pal.append([Color(String(p[0])).srgb_to_linear(), float(p[1]), float(p[2])])
	return _data


static func has(group: String, id: String) -> bool:
	return data().get(group, {}).has(id)


static func variants(id: String) -> int:
	return (data()["buildings"].get(id, []) as Array).size()


## 몸체·유리·불빛 재질 (모든 모형이 함께 쓴다 — 밤 정도를 한 번에 바꾼다)
static func materials() -> Array:
	if _mats.is_empty():
		for i in SHADERS.size():
			var m := ShaderMaterial.new()
			m.shader = load(SHADERS[i])
			m.render_priority = i
			_mats.append(m)
	return _mats


static func set_night(k: float) -> void:
	for m in materials():
		(m as ShaderMaterial).set_shader_parameter("night", k)


## 건물(변형 v) 또는 탈것의 메시 (다른 스레드에서 만드는 중이면 끝날 때까지 기다린다)
static func mesh(group: String, id: String, v: int = 0) -> ArrayMesh:
	var key := "%s/%s/%d" % [group, id, v]
	if _cache.has(key):
		return _cache[key]
	if _jobs.has(key):
		WorkerThreadPool.wait_for_task_completion(_jobs[key])
		_jobs.erase(key)
		_lock.lock()
		var made: ArrayMesh = _made.get(key)
		_made.erase(key)
		_lock.unlock()
		_cache[key] = made
		return made
	var b := _Builder.new()
	for p in _prims(group, id, v):
		b.prim(p)
	var m := b.commit(materials())
	_cache[key] = m
	return m


static func _prims(group: String, id: String, v: int) -> Array:
	var g: Dictionary = data().get(group, {})
	if not g.has(id):
		return []
	if group == "buildings":
		var vs: Array = g[id]
		return vs[clampi(v, 0, vs.size() - 1)]
	return g[id]


# ── 다른 스레드에서 만들기 ──────────────────────────────────────
## 모형 하나에 수 ms (휴대폰은 몇 배) — 처음 보는 모형이 여럿이면 프레임이 멈춘다. 그래서 도시는 ready()로 묻고,
## 아직이면 다른 스레드가 만드는 동안 그 모형만 빼고 그린 뒤 다 되면 다시 그린다
static var _jobs := {}               # 열쇠 → 작업 번호
static var _made := {}               # 열쇠 → 다 만든 메시 (작업이 넣는다 — _lock으로 지킨다)
static var _lock := Mutex.new()


## 메시가 있나 — 없으면 다른 스레드에서 만들기 시작한다
static func ready(group: String, id: String, v: int = 0) -> bool:
	var key := "%s/%s/%d" % [group, id, v]
	if _cache.has(key):
		return true
	_collect()
	if _cache.has(key):
		return true
	if not _jobs.has(key):
		_jobs[key] = WorkerThreadPool.add_task(_make.bind(key, _prims(group, id, v), materials()), false, "model " + key)
	return false


## 다른 스레드에서 만드는 모형 수 (다 만든 것은 거둔다)
static func pending() -> int:
	_collect()
	return _jobs.size()


static func _make(key: String, prims: Array, mats: Array) -> void:
	var b := _Builder.new()
	for p in prims:
		b.prim(p)
	var m := b.commit(mats)
	_lock.lock()
	_made[key] = m
	_lock.unlock()


static func _collect() -> void:
	if _jobs.is_empty():
		return
	_lock.lock()
	var made := _made
	_made = {}
	_lock.unlock()
	for key in made:
		WorkerThreadPool.wait_for_task_completion(_jobs[key])
		_jobs.erase(key)
		_cache[key] = made[key]


static func color(i: int) -> Color:
	return _pal[i][0] if i >= 0 and i < _pal.size() else Color(0.5, 0.5, 0.5)


static func gloss(i: int) -> float:
	return _pal[i][1] if i >= 0 and i < _pal.size() else 0.0


static func alpha(i: int) -> float:
	return _pal[i][2] if i >= 0 and i < _pal.size() else 1.0


## 모형 좌표 → Godot 좌표
static func g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


class _Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()


class _Builder:
	var s: Array = [_Surf.new(), _Surf.new(), _Surf.new()]

	func commit(mats: Array) -> ArrayMesh:
		var m := ArrayMesh.new()
		for i in 3:
			var sf: _Surf = s[i]
			if sf.idx.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = sf.v
			arr[Mesh.ARRAY_NORMAL] = sf.n
			arr[Mesh.ARRAY_COLOR] = sf.c
			arr[Mesh.ARRAY_TEX_UV] = sf.uv
			arr[Mesh.ARRAY_TEX_UV2] = sf.uv2
			arr[Mesh.ARRAY_INDEX] = sf.idx
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(m.get_surface_count() - 1, mats[i])
		return m

	# ── 정점 ──────────────────────────────────────────────────────
	## 모형 좌표 p(미터, z 위)를 Godot 좌표로 바꿔 넣는다. ao: 바닥 쪽을 어둡게 (세운 면)
	func vert(si: int, p: Vector3, nrm: Vector3, col: Color, gl: float, em: Vector2, ao: bool) -> int:
		var sf: _Surf = s[si]
		var k := 1.0
		if ao:
			k = 0.74 + 0.26 * smoothstep(0.0, 2.6, p.z)
		sf.v.append(Vector3(p.x, p.z, -p.y))
		sf.n.append(Vector3(nrm.x, nrm.z, -nrm.y))
		sf.c.append(Color(col.r * k, col.g * k, col.b * k, col.a))
		sf.uv.append(Vector2(gl, 0.0))
		sf.uv2.append(em)
		return sf.v.size() - 1

	## 삼각형 (바깥에서 볼 때 반시계로 받는다. Godot의 앞면은 시계 방향이라 뒤집어 넣는다)
	func tri(si: int, a: int, b: int, c: int) -> void:
		var sf: _Surf = s[si]
		sf.idx.append(a)
		sf.idx.append(c)
		sf.idx.append(b)

	## 빛 색 → UV2 (r·g, b·세기를 0~255 정수 둘씩 묶는다. 셰이더가 flat으로 풀어 쓴다)
	static func pack(col: Color, strength: float) -> Vector2:
		if strength <= 0.0:
			return Vector2.ZERO
		var r := clampi(roundi(col.r * 255.0), 0, 255)
		var gg := clampi(roundi(col.g * 255.0), 0, 255)
		var b := clampi(roundi(col.b * 255.0), 0, 255)
		var st := clampi(roundi(strength * 255.0), 1, 255)
		return Vector2(r * 256 + gg, b * 256 + st)

	## 평면 다각형 (모형 좌표, 반시계 = 바깥 법선). want를 주면 그쪽을 바깥으로 돌려 놓는다
	func poly(si: int, pts: PackedVector3Array, col: Color, gl: float, em: Vector2 = Vector2.ZERO,
			want := Vector3.ZERO) -> void:
		var cnt := pts.size()
		if cnt < 3:
			return
		var nrm := _newell(pts)
		if nrm.length_squared() < 1e-12:
			return
		nrm = nrm.normalized()
		if want != Vector3.ZERO and nrm.dot(want) < 0.0:
			pts.reverse()
			nrm = -nrm
		var ao := absf(nrm.z) < 0.5
		var base := -1
		for i in cnt:
			var id := vert(si, pts[i], nrm, col, gl, em, ao)
			if i == 0:
				base = id
		if cnt <= 4 and _convex(pts, nrm):
			for i in range(1, cnt - 1):
				tri(si, base, base + i, base + i + 1)
			return
		# 오목할 수 있다: 평면에 펼쳐 귀 자르기
		var u := (pts[1] - pts[0]).normalized()
		var w := nrm.cross(u)
		var flat := PackedVector2Array()
		for p in pts:
			var d := p - pts[0]
			flat.append(Vector2(d.dot(u), d.dot(w)))
		var tris := Geometry2D.triangulate_polygon(flat)
		if tris.is_empty():
			for i in range(1, cnt - 1):
				tri(si, base, base + i, base + i + 1)
			return
		for i in range(0, tris.size(), 3):
			tri(si, base + tris[i], base + tris[i + 1], base + tris[i + 2])

	static func _newell(pts: PackedVector3Array) -> Vector3:
		var nrm := Vector3.ZERO
		var cnt := pts.size()
		for i in cnt:
			var a := pts[i]
			var b := pts[(i + 1) % cnt]
			nrm.x += (a.y - b.y) * (a.z + b.z)
			nrm.y += (a.z - b.z) * (a.x + b.x)
			nrm.z += (a.x - b.x) * (a.y + b.y)
		return nrm

	func _convex(pts: PackedVector3Array, nrm: Vector3) -> bool:
		var cnt := pts.size()
		for i in cnt:
			var a := pts[i]
			var b := pts[(i + 1) % cnt]
			var c := pts[(i + 2) % cnt]
			if (b - a).cross(c - b).dot(nrm) < -1e-9:
				return false
		return true

	func quad(si: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, gl: float, em := Vector2.ZERO,
			want := Vector3.ZERO) -> void:
		poly(si, PackedVector3Array([a, b, c, d]), col, gl, em, want)

	# ── 도형 ──────────────────────────────────────────────────────
	func prim(p: Array) -> void:
		match String(p[0]):
			"box":
				_box(p)
			"poly":
				_poly(p)
			"fru":
				_frustum(p)
			"ell":
				_ellipsoid(p)
			"hcyl":
				_half_cyl(p)
			"disc":
				_disc(p)
			"line":
				_line(p)
			"win":
				_window(p)
			"lamp":
				_lamp(p)
			"glow":
				_glow(Vector3(p[1], p[2], p[3]), float(p[4]), ModelLib.color(int(p[5])), float(p[6]))
			"lpoly":
				var col := ModelLib.color(int(p[1]))
				col.a = float(p[2])
				poly(GLOW, _pts(p[3]), col, 0.0)
			"grid":
				_grid(p)

	func _pts(flat: Array) -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in range(0, flat.size() - 2, 3):
			out.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
		return out

	func _surf_of(ci: int) -> int:
		return GLASS if ModelLib.alpha(ci) < 0.99 else BODY

	func _col(ci: int) -> Color:
		var c := ModelLib.color(ci)
		c.a = ModelLib.alpha(ci)
		return c

	func _emit(e: Variant) -> Vector2:
		if e is Array and (e as Array).size() == 2:
			return pack(ModelLib.color(int(e[0])), float(e[1]))
		return Vector2.ZERO

	func _box(p: Array) -> void:
		var x0: float = p[1]
		var y0: float = p[2]
		var z0: float = p[3]
		var x1: float = x0 + float(p[4])
		var y1: float = y0 + float(p[5])
		var z1: float = z0 + float(p[6])
		var ci := int(p[7])
		var col := _col(ci)
		var gl := ModelLib.gloss(ci)
		var si := _surf_of(ci)
		quad(si, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col, gl)
		quad(si, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), col, gl)
		quad(si, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), col, gl)
		quad(si, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), col, gl)
		var ti := int(p[8])
		quad(_surf_of(ti), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1),
			_col(ti), ModelLib.gloss(ti))
		quad(si, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), col, gl)

	func _poly(p: Array) -> void:
		var ci := int(p[1])
		poly(_surf_of(ci), _pts(p[2]), _col(ci), ModelLib.gloss(ci), _emit(p[3]))

	static func _basis(axis: Vector3) -> Array:
		var a := axis.normalized()
		var helper := Vector3(0, 0, 1) if absf(a.z) < 0.9 else Vector3(1, 0, 0)
		var u := a.cross(helper).normalized()
		return [u, a.cross(u)]

	static func _seg(r: float) -> int:
		return clampi(int(r * 9.0) + 12, 12, 40)

	## 옆면 띠: 축 위치 s0~s1, 반지름 ra~rb (원뿔대 한 토막)
	func _ring_side(si: int, p0: Vector3, axis: Vector3, u: Vector3, w: Vector3, s0: float, s1: float, ra: float,
			rb: float, seg: int, col: Color, gl: float, em: Vector2, smooth_ao: bool) -> void:
		var a := axis.normalized()
		var length := axis.length()
		var slope := (ra - rb) / (length * (s1 - s0)) if length * (s1 - s0) > 1e-6 else 0.0
		var c0 := p0 + axis * s0
		var c1 := p0 + axis * s1
		var base: int = (s[si] as _Surf).v.size()
		for i in seg + 1:
			var t := TAU * i / seg
			var radial := u * cos(t) + w * sin(t)
			var nrm := (radial + a * slope).normalized()
			vert(si, c0 + radial * ra, nrm, col, gl, em, smooth_ao)
			vert(si, c1 + radial * rb, nrm, col, gl, em, smooth_ao)
		for i in seg:
			var k: int = base + i * 2
			tri(si, k, k + 2, k + 3)
			tri(si, k, k + 3, k + 1)

	func _cap(si: int, c: Vector3, nrm: Vector3, u: Vector3, w: Vector3, r: float, seg: int, col: Color, gl: float) -> void:
		if r <= 0.0:
			return
		var center := vert(si, c, nrm, col, gl, Vector2.ZERO, false)
		for i in seg + 1:
			var t := TAU * i / seg
			vert(si, c + (u * cos(t) + w * sin(t)) * r, nrm, col, gl, Vector2.ZERO, false)
		var flip := u.cross(w).dot(nrm) < 0.0
		for i in seg:
			if flip:
				tri(si, center, center + 2 + i, center + 1 + i)
			else:
				tri(si, center, center + 1 + i, center + 2 + i)

	func _frustum(p: Array) -> void:
		var p0 := Vector3(p[1], p[2], p[3])
		var p1 := Vector3(p[4], p[5], p[6])
		var r0: float = p[7]
		var r1: float = p[8]
		var ci := int(p[9])
		var axis := p1 - p0
		if axis.length() < 1e-5:
			return
		var bw: Array = _basis(axis)
		var u: Vector3 = bw[0]
		var w: Vector3 = bw[1]
		var seg := _seg(maxf(r0, r1))
		var si := _surf_of(ci)
		_ring_side(si, p0, axis, u, w, 0.0, 1.0, r0, r1, seg, _col(ci), ModelLib.gloss(ci), _emit(p[14]), true)
		if int(p[10]) == 1:
			var cc := int(p[11])
			var a := axis.normalized()
			_cap(_surf_of(cc), p1, a, u, w, r1, seg, _col(cc), ModelLib.gloss(cc))
			_cap(_surf_of(cc), p0, -a, w, u, r0, seg, _col(cc), ModelLib.gloss(cc))
		var bands: Array = p[12]
		if not bands.is_empty():
			var bc := _col(int(p[13]))
			var length := axis.length()
			var d := clampf(0.05 / length, 0.002, 0.05)
			for b in bands:
				var sb := float(b)
				var rr := lerpf(r0, r1, sb) + 0.03
				_ring_side(si, p0, axis, u, w, sb - d, sb + d, rr, rr, seg, bc, 0.0, Vector2.ZERO, false)

	func _ellipsoid(p: Array) -> void:
		var c := Vector3(p[1], p[2], p[3])
		var rx: float = p[4]
		var ry: float = p[5]
		var rz: float = p[6]
		var ci := int(p[8])
		var si := _surf_of(ci)
		var col := _col(ci)
		var gl := ModelLib.gloss(ci)
		var lo := -PI * 0.5
		if p[7] != null:
			lo = asin(clampf((float(p[7]) - c.z) / maxf(rz, 1e-4), -1.0, 1.0))
		var n_lon := clampi(int(maxf(rx, ry) * 7.0) + 14, 14, 40)
		var n_lat := maxi(4, int(n_lon * (PI * 0.5 - lo) / TAU) + 2)
		var base: int = (s[si] as _Surf).v.size()
		for j in n_lat + 1:
			var ph := lerpf(lo, PI * 0.5, float(j) / n_lat)
			for i in n_lon + 1:
				var th := TAU * i / n_lon
				var d := Vector3(cos(ph) * cos(th), cos(ph) * sin(th), sin(ph))
				var pos := c + Vector3(d.x * rx, d.y * ry, d.z * rz)
				var nrm := Vector3(d.x / maxf(rx, 1e-4), d.y / maxf(ry, 1e-4), d.z / maxf(rz, 1e-4)).normalized()
				vert(si, pos, nrm, col, gl, Vector2.ZERO, si == BODY)
		for j in n_lat:
			for i in n_lon:
				var k: int = base + j * (n_lon + 1) + i
				tri(si, k, k + 1, k + n_lon + 2)
				tri(si, k, k + n_lon + 2, k + n_lon + 1)

	func _half_cyl(p: Array) -> void:
		var p0 := Vector3(p[1], p[2], p[3])
		var p1 := Vector3(p[4], p[5], p[6])
		var r: float = p[7]
		var ci := int(p[8])
		var rz: float = r if p[13] == null else float(p[13])
		var axis := p1 - p0
		if axis.length() < 1e-5:
			return
		var a := axis.normalized()
		var up := Vector3(0, 0, 1)
		var side := up.cross(a).normalized()
		var si := _surf_of(ci)
		var col := _col(ci)
		var gl := ModelLib.gloss(ci)
		var seg := _seg(maxf(r, rz))
		var base: int = (s[si] as _Surf).v.size()
		for i in seg + 1:
			var t := PI * i / seg
			var off := side * cos(t) * r + up * sin(t) * rz
			var nrm := (side * cos(t) / r + up * sin(t) / rz).normalized()
			vert(si, p0 + off, nrm, col, gl, Vector2.ZERO, si == BODY)
			vert(si, p1 + off, nrm, col, gl, Vector2.ZERO, si == BODY)
		for i in seg:
			var k: int = base + i * 2
			tri(si, k, k + 2, k + 3)
			tri(si, k, k + 3, k + 1)
		if int(p[9]) == 1:
			var cc := int(p[10])
			for end in [[p0, -a], [p1, a]]:
				var e: Vector3 = end[0]
				var nrm: Vector3 = end[1]
				var csi := _surf_of(cc)
				var center := vert(csi, e, nrm, _col(cc), ModelLib.gloss(cc), Vector2.ZERO, false)
				for i in seg + 1:
					var t := PI * i / seg
					vert(csi, e + side * cos(t) * r + up * sin(t) * rz, nrm, _col(cc), ModelLib.gloss(cc), Vector2.ZERO, false)
				var flip := side.cross(up).dot(nrm) < 0.0
				for i in seg:
					if flip:
						tri(csi, center, center + 2 + i, center + 1 + i)
					else:
						tri(csi, center, center + 1 + i, center + 2 + i)
		var bands: Array = p[11]
		if not bands.is_empty():
			var bc := _col(int(p[12]))
			var d := clampf(0.05 / axis.length(), 0.002, 0.05)
			for b in bands:
				var sb := float(b)
				var b0 := p0 + axis * (sb - d)
				var b1 := p0 + axis * (sb + d)
				var bb: int = (s[BODY] as _Surf).v.size()
				for i in seg + 1:
					var t := PI * i / seg
					var nrm := (side * cos(t) / r + up * sin(t) / rz).normalized()
					var off := side * cos(t) * (r + 0.03) + up * sin(t) * (rz + 0.03)
					vert(BODY, b0 + off, nrm, bc, 0.0, Vector2.ZERO, false)
					vert(BODY, b1 + off, nrm, bc, 0.0, Vector2.ZERO, false)
				for i in seg:
					var k: int = bb + i * 2
					tri(BODY, k, k + 2, k + 3)
					tri(BODY, k, k + 3, k + 1)

	func _disc(p: Array) -> void:
		var c := Vector3(p[1], p[2], p[3])
		var nrm := Vector3(p[4], p[5], p[6]).normalized()
		var r: float = p[7]
		var ci := int(p[8])
		var back := int(p[9])
		var bw: Array = _basis(nrm)
		var seg := _seg(r)
		if back >= 0:
			_cap(_surf_of(ci), c + nrm * 0.004, nrm, bw[0], bw[1], r, seg, _col(ci), ModelLib.gloss(ci))
			_cap(_surf_of(back), c - nrm * 0.004, -nrm, bw[1], bw[0], r, seg, _col(back), ModelLib.gloss(back))
		else:
			_cap(_surf_of(ci), c, nrm, bw[0], bw[1], r, seg, _col(ci), ModelLib.gloss(ci))

	func _line(p: Array) -> void:
		var wdt := maxf(float(p[1]), 0.04)
		var col := _col(int(p[2]))
		var pts := _pts(p[3])
		var night := int(p[4]) == 1
		var si := GLOW if night else BODY
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := b - a
			if d.length() < 1e-4:
				continue
			var bw: Array = _basis(d)
			var u: Vector3 = bw[0] * (wdt * 0.5)
			var w: Vector3 = bw[1] * (wdt * 0.5)
			var corners := [u + w, -u + w, -u - w, u - w]
			for k in 4:
				var c0: Vector3 = corners[k]
				var c1: Vector3 = corners[(k + 1) % 4]
				quad(si, a + c0, a + c1, b + c1, b + c0, col, 0.1)

	func _grid(p: Array) -> void:
		var o := Vector3(p[1], p[2], p[3])
		var e1 := Vector3(p[4], p[5], p[6])
		var e2 := Vector3(p[7], p[8], p[9])
		var n1 := int(p[10])
		var n2 := int(p[11])
		var col := _col(int(p[12]))
		var wdt := maxf(float(p[13]), 0.03)
		var nrm := e1.cross(e2).normalized()
		for side in [1.0, -1.0]:
			var lift: Vector3 = nrm * 0.012 * side
			for i in range(1, n1):
				var a := o + e1 * (float(i) / n1) + lift
				var hw := e1.normalized() * (wdt * 0.5)
				_strip(a - hw, a + hw, e2, col, nrm * side)
			for j in range(1, n2):
				var a := o + e2 * (float(j) / n2) + lift
				var hw := e2.normalized() * (wdt * 0.5)
				_strip(a - hw, a + hw, e1, col, nrm * side)

	func _strip(a: Vector3, b: Vector3, along: Vector3, col: Color, want: Vector3) -> void:
		quad(BODY, a, b, b + along, a + along, col, 0.2, Vector2.ZERO, want)

	func _window(p: Array) -> void:
		var gi := int(p[1])
		var glow := ModelLib.color(int(p[2]))
		poly(BODY, _pts(p[4]), _col(gi), ModelLib.gloss(gi), pack(glow, float(p[3])))

	func _lamp(p: Array) -> void:
		var c := Vector3(p[1], p[2], p[3])
		var lc := ModelLib.color(int(p[4]))
		var h := 0.12
		var em := pack(lc, 1.0)
		var x0 := c.x - h
		var x1 := c.x + h
		var y0 := c.y - h
		var y1 := c.y + h
		var z0 := c.z - h
		var z1 := c.z + h
		var col := LAMP_COLOR
		quad(BODY, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), col, 0.3, em)
		quad(BODY, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), col, 0.3, em)
		quad(BODY, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), col, 0.3, em)
		quad(BODY, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), col, 0.3, em)
		quad(BODY, Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), col, 0.3, em)
		_glow(c, float(p[5]) * 0.8, lc, 0.8)

	## 밤의 불빛 번짐: 네 꼭짓점이 한 점에 있고, 셰이더가 화면 쪽으로 펼친다 (UV = 모서리, UV2.x = 반지름)
	func _glow(c: Vector3, r: float, col: Color, strength: float) -> void:
		var sf: _Surf = s[GLOW]
		var base := sf.v.size()
		var cc := Color(col.r, col.g, col.b, strength)
		for k in 4:
			sf.v.append(Vector3(c.x, c.z, -c.y))
			sf.n.append(Vector3.UP)
			sf.c.append(cc)
			sf.uv.append(Vector2(float(k == 1 or k == 2), float(k >= 2)))
			sf.uv2.append(Vector2(r, 0.0))
		tri(GLOW, base, base + 1, base + 2)
		tri(GLOW, base, base + 2, base + 3)
