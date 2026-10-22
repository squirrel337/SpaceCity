class_name RoadMesh
extends RefCounted
## 길 그물의 3D 메시 — 길마다 종류의 폭으로 땅을 따라가는 띠(2 m마다 땅 높이, 두께와 옆면이 있다),
## 셋 이상 만나는 곳은 교차로 판(가장자리를 둥글게), 둘이 꺾이는 곳은 반지름 있는 굽은 띠, 끝은 둥근 막다른 곳.
## 가압 통로는 띠 위에 반원 껍질을 씌우고 만나는 곳에 둥근 연결 모듈을 둔다.
## 높은 길(고가·다리 — CityPlan.levels의 사슬)은 덱으로: 윗면, 판 두께의 옆면·밑면, 난간. 고가는 땅을 따라, 다리는 사슬 두 끝을
## 잇는 곧은 선 위로 뜨고 끝에서 비탈로 내려앉는다. 받침(교각·주탑·케이블·아치·트러스 …)은 RoadStructs가 단위 상자로 짓는다.
## 높이는 h(p: Vector2, above: float) -> Vector3 (City3D._local — 땅 높이·곡률)로 얻는다.

const STEP_M := 2.0
const THICK := 0.18                      # 길의 두께 (땅 위로)
const SKIRT := 0.7                       # 옆면이 땅 속으로 내려가는 깊이
## 덱 무늬 번호 (셰이더): UV2.x = 무늬 + PART × 부분 (0 길 띠, 1 교차로 판, 2 옆면, 3 통로 껍질, 4 덱 판(콘크리트), 5 난간)
const LOOK_CODE := {"path": 0, "street": 1, "avenue": 2, "highway": 3, "tube": 4, "rail": 5, "runway": 6, "walk": 7,
	"beam": 8, "guide": 9, "belt": 10}
const PART := 100
const RAIL_H := 1.05                     # 덱 난간 높이

var v := PackedVector3Array()
var n := PackedVector3Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var idx := PackedInt32Array()
var h: Callable
# 몇 프레임에 나눠 짓기 (start → step … → mesh): 시작할 때 베낀 길 그물
var _nodes: Array = []
var _edges: Array = []
var _types: Array = []
var _inc: Array = []
var _back: Array = []
var _k := 0
var _i := 0
var _c := 0
var _lv: Array = []                      # 높은 길의 사슬 (CityPlan.levels를 베낀 것)
var _lvn := PackedByteArray()            # 꼭짓점의 높이 갈래 (0 땅, 1 오르내리는 끝, 2 높은 길의 가운데)
var _ends_y := {}                        # 사슬 끝 꼭짓점 → 땅 높이 (다리의 곧은 선)
var _chains: Array = []                  # 사슬마다 [[길, s_a, s_b, a, b] …] (거리 순) — 받침을 짓는다
# 받침 상자 (단위 상자 MultiMesh): 변환, 색, INSTANCE_CUSTOM (r: 밤빛)
var sx: Array = []
var sc := PackedColorArray()
var su := PackedColorArray()


func _init(p_h: Callable) -> void:
	h = p_h


func _vert(p: Vector2, above: float, u: Vector2, code: float, length: float, nrm := Vector3.UP) -> int:
	v.append(h.call(p, above))
	n.append(nrm)
	uv.append(u)
	uv2.append(Vector2(code, length))
	return v.size() - 1


## 이미 잰 땅 위치 g(땅 높이 0)에서 above만큼 위 — 같은 점의 윗면·옆면이 땅 높이를 한 번만 잰다
func _vert_g(g: Vector3, above: float, u: Vector2, code: float, length: float, nrm := Vector3.UP) -> int:
	v.append(Vector3(g.x, g.y + above, g.z))
	n.append(nrm)
	uv.append(u)
	uv2.append(Vector2(code, length))
	return v.size() - 1


static func code_of(type: String, part: int) -> float:
	return float(LOOK_CODE.get(LayoutData.look(type), 1) + part * PART)


## 띠 하나: a → b, 반폭 hw. 옆면(두께)도 붙인다. 가압 통로면 반원 껍질을 씌운다
func ribbon(a: Vector2, b: Vector2, hw: float, type: String, uv_y0 := 0.0, total := -1.0, ends := true) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var steps := maxi(1, int(ceil(length / STEP_M)))
	var tot := length if total < 0.0 else total
	var code := code_of(type, 0)
	var base := v.size()
	var left := PackedVector3Array()      # 양쪽 가장자리의 땅 위치 (옆면이 다시 쓴다)
	var right := PackedVector3Array()
	for k in steps + 1:
		var t := float(k) / steps
		var c := a.lerp(b, t)
		var yy := uv_y0 + t * length
		var gl: Vector3 = h.call(c - side * hw, 0.0)
		var gr: Vector3 = h.call(c + side * hw, 0.0)
		left.append(gl)
		right.append(gr)
		_vert_g(gl, THICK, Vector2(0.0, yy), code, tot)
		_vert_g(gr, THICK, Vector2(1.0, yy), code, tot)
	for k in steps:
		var o := base + k * 2
		idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	# 옆면: 가장자리에서 땅 속으로
	for si in 2:
		var s := -1.0 if si == 0 else 1.0
		var sb := v.size()
		var out := Vector3(side.x * s, 0.0, -side.y * s)
		var pts := left if si == 0 else right
		for k in steps + 1:
			var t := float(k) / steps
			_vert_g(pts[k], THICK, Vector2(0.0, uv_y0 + t * length), code_of(type, 2), tot, out)
			_vert_g(pts[k], -SKIRT, Vector2(1.0, uv_y0 + t * length), code_of(type, 2), tot, out)
		for k in steps:
			var o := sb + k * 2
			idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))
	if LayoutData.look(type) == "tube":
		shell(a, b, hw * 0.92, uv_y0)


## 가압 통로의 반원 껍질 (가로 0~1 = 한쪽 땅 → 꼭대기 → 다른 쪽 땅)
func shell(a: Vector2, b: Vector2, r: float, uv_y0 := 0.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	var side := Vector2(-dir.y, dir.x)
	var steps := maxi(1, int(ceil(length / STEP_M)))
	var segs := 10
	var base := v.size()
	for k in steps + 1:
		var t := float(k) / steps
		var c := a.lerp(b, t)
		for j in segs + 1:
			var ang := PI * float(j) / segs
			var off := side * cos(ang) * r
			var up := sin(ang) * r * 0.9
			var nrm := Vector3(side.x * cos(ang), sin(ang), -side.y * cos(ang)).normalized()
			_vert(c + off, THICK + up, Vector2(float(j) / segs, uv_y0 + t * length), code_of("tube", 3), length, nrm)
	for k in steps:
		for j in segs:
			var o := base + k * (segs + 1) + j
			idx.append_array(PackedInt32Array([o, o + segs + 1, o + 1, o + 1, o + segs + 1, o + segs + 2]))


## 교차로 판: 꼭짓점 둘레의 다각형 (pts — 반시계)을 꼭짓점 가운데에서 부채꼴로
func junction(center: Vector2, pts: PackedVector2Array, type: String) -> void:
	var code := code_of(type, 1)
	var c := _vert(center, THICK + 0.005, Vector2(0.5, 0.0), code, 0.0)
	var first := v.size()
	var gs := PackedVector3Array()
	for p in pts:
		var g: Vector3 = h.call(p, 0.0)
		gs.append(g)
		_vert_g(g, THICK + 0.005, Vector2(0.5, 0.0), code, 0.0)
	for i in pts.size():
		var a := first + i
		var b := first + (i + 1) % pts.size()
		idx.append_array(PackedInt32Array([c, b, a]))
	# 옆면
	for i in pts.size():
		var j := (i + 1) % pts.size()
		var e := (pts[j] - pts[i]).normalized()
		var out := Vector3(e.y, 0.0, e.x)
		var sb := v.size()
		_vert_g(gs[i], THICK, Vector2(0.0, 0.0), code_of(type, 2), 0.0, out)
		_vert_g(gs[i], -SKIRT, Vector2(1.0, 0.0), code_of(type, 2), 0.0, out)
		_vert_g(gs[j], THICK, Vector2(0.0, 1.0), code_of(type, 2), 0.0, out)
		_vert_g(gs[j], -SKIRT, Vector2(1.0, 1.0), code_of(type, 2), 0.0, out)
		idx.append_array(PackedInt32Array([sb, sb + 2, sb + 1, sb + 1, sb + 2, sb + 3]))


## 가압 통로가 만나는 곳의 둥근 연결 모듈 (낮은 원기둥 + 돔)
func hub_module(center: Vector2, r: float) -> void:
	var segs := 16
	var rings := 5
	var base := v.size()
	for j in rings + 1:
		var phi := PI * 0.5 * float(j) / rings
		for k in segs + 1:
			var a := TAU * float(k) / segs
			var dir := Vector2(cos(a), sin(a))
			var rr := r * cos(phi)
			var up := r * 0.75 + r * 0.55 * sin(phi)
			var nrm := Vector3(dir.x * cos(phi), sin(phi), -dir.y * cos(phi)).normalized()
			_vert(center + dir * rr, THICK + (up if j > 0 else r * 0.75), Vector2(float(k) / segs, float(j) * 2.0),
				code_of("tube", 3), 8.0, nrm)
	for j in rings:
		for k in segs:
			var o := base + j * (segs + 1) + k
			idx.append_array(PackedInt32Array([o, o + 1, o + segs + 1, o + 1, o + segs + 2, o + segs + 1]))
	# 원기둥 벽
	var wb := v.size()
	for k in segs + 1:
		var a := TAU * float(k) / segs
		var dir := Vector2(cos(a), sin(a))
		var nrm := Vector3(dir.x, 0.0, -dir.y)
		_vert(center + dir * r, THICK - 0.2, Vector2(float(k) / segs, 0.0), code_of("tube", 3), 8.0, nrm)
		_vert(center + dir * r, THICK + r * 0.75, Vector2(float(k) / segs, 1.0), code_of("tube", 3), 8.0, nrm)
	for k in segs:
		var o := wb + k * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))


func mesh() -> ArrayMesh:
	var m := ArrayMesh.new()
	if idx.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ── 높은 길 (고가·다리) ─────────────────────────────────────────
## 사슬마다 [[길, s_a, s_b, a, b] …] — 사슬 앞 끝에서 거리 순 (받침을 지을 때 사슬을 따라간다)
func _chain_list() -> Array:
	var by := {}
	for k in _lv.size():
		var d: Dictionary = _lv[k]
		if d.is_empty():
			continue
		var key := "%d:%d" % [int(d["ends"][0]), int(d["ends"][1])]
		if not by.has(key):
			by[key] = []
		var e: Vector2i = _edges[k]
		var s0 := float(d["s0"])
		var s1 := float(d["s1"])
		if s0 <= s1:
			by[key].append([k, s0, s1, _nodes[e.x], _nodes[e.y]])
		else:
			by[key].append([k, s1, s0, _nodes[e.y], _nodes[e.x]])
	var out: Array = []
	for key in by:
		var segs: Array = by[key]
		segs.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) < float(y[1]))
		out.append(segs)
	return out


## 사슬 끝 꼭짓점의 땅 높이 (지역 y) — 다리는 두 끝을 곧게 잇는다
func _end_y(n: int) -> float:
	if not _ends_y.has(n):
		_ends_y[n] = (h.call(_nodes[n], 0.0) as Vector3).y
	return float(_ends_y[n])


## 높은 길 k의 앞 끝(edges[k].x)에서 t(0~1)만큼 간 곳 p의 덱 윗면 높이 (지역 y — 판의 윗면, 길 띠는 THICK 위)
func deck_y(k: int, t: float, p: Vector2) -> float:
	var d: Dictionary = _lv[k]
	var s := lerpf(float(d["s0"]), float(d["s1"]), t)
	var length := float(d["len"])
	var up := minf(float(d["deck"]), float(d["grade"]) * minf(s, length - s))
	var g: float = (h.call(p, 0.0) as Vector3).y
	if bool(d["bridge"]):
		var ends: Array = d["ends"]
		return maxf(lerpf(_end_y(ends[0]), _end_y(ends[1]), s / maxf(length, 0.01)) + up, g + 0.4)
	return g + up


## 사슬 위 거리 s의 자리: [위치, 방향, 길, t]
static func chain_at(chain: Array, s: float) -> Array:
	var seg: Array = chain[-1]
	for sg in chain:
		if s <= float(sg[2]) + 1e-4:
			seg = sg
			break
	var a: Vector2 = seg[3]
	var b: Vector2 = seg[4]
	var f := clampf((s - float(seg[1])) / maxf(float(seg[2]) - float(seg[1]), 0.01), 0.0, 1.0)
	return [a.lerp(b, f), (b - a).normalized(), int(seg[0]), f]


## 사슬 위 거리 s의 덱 높이
func chain_y(chain: Array, s: float) -> float:
	var at := chain_at(chain, s)
	var k: int = at[2]
	var d: Dictionary = _lv[k]
	var t := clampf((s - float(d["s0"])) / (float(d["s1"]) - float(d["s0"])), 0.0, 1.0) if absf(float(d["s1"]) - float(d["s0"])) > 0.01 else 0.0
	return deck_y(k, t, at[0])


static func at3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, -p.y)


## 높은 길 하나의 덱 (a·b: 교차로에서 물러난 끝, off: a가 길의 앞 끝에서 떨어진 거리, length: 길 전체 길이)
func deck_edge(k: int, a: Vector2, b: Vector2, off: float, length: float) -> void:
	var t := String(_types[k])
	var hw := LayoutData.road_half(t)
	var d := b - a
	var seg := d.length()
	if seg < 0.05:
		return
	var steps := maxi(1, int(ceil(seg / STEP_M)))
	var cs := PackedVector2Array()
	var ys := PackedFloat32Array()
	for j in steps + 1:
		var f := float(j) / steps
		var c := a.lerp(b, f)
		cs.append(c)
		ys.append(deck_y(k, (off + f * seg) / maxf(length, 0.01), c))
	deck_strip(cs, ys, hw, t, off)


## 덱 띠: 점들 cs (높이 ys)를 따라 반폭 hw — 윗면(길 무늬), 판 두께의 옆면·밑면, 양쪽 난간 (가압 통로는 껍질)
func deck_strip(cs: PackedVector2Array, ys: PackedFloat32Array, hw: float, type: String, uv_y0 := 0.0) -> void:
	if cs.size() < 2:
		return
	var look := LayoutData.look(type)
	var slab := clampf(hw * 0.22, 0.8, 2.2)
	var code := code_of(type, 0)
	var concrete := code_of(type, 4)
	var total := 0.0
	var acc := PackedFloat32Array([0.0])
	for j in range(1, cs.size()):
		total += cs[j].distance_to(cs[j - 1])
		acc.append(total)
	var sides := PackedVector2Array()
	for j in cs.size():
		var dj := (cs[mini(j + 1, cs.size() - 1)] - cs[maxi(j - 1, 0)]).normalized()
		sides.append(Vector2(-dj.y, dj.x))
	var base := v.size()
	for j in cs.size():
		var yy := uv_y0 + acc[j]
		_vert_g(at3(cs[j] - sides[j] * hw, ys[j]), THICK, Vector2(0.0, yy), code, total)
		_vert_g(at3(cs[j] + sides[j] * hw, ys[j]), THICK, Vector2(1.0, yy), code, total)
	for j in cs.size() - 1:
		var o := base + j * 2
		idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	# 판: 양 옆면과 밑면 (콘크리트)
	for si in 2:
		var sgn := -1.0 if si == 0 else 1.0
		var sb := v.size()
		for j in cs.size():
			var p := cs[j] + sides[j] * hw * sgn
			var out := Vector3(sides[j].x * sgn, 0.0, -sides[j].y * sgn)
			_vert_g(at3(p, ys[j]), THICK, Vector2(0.0, acc[j]), concrete, total, out)
			_vert_g(at3(p, ys[j]), -slab, Vector2(1.0, acc[j]), concrete, total, out)
		for j in cs.size() - 1:
			var o := sb + j * 2
			idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))
	var bb := v.size()
	for j in cs.size():
		_vert_g(at3(cs[j] - sides[j] * hw, ys[j]), -slab, Vector2(0.0, acc[j]), concrete, total, Vector3.DOWN)
		_vert_g(at3(cs[j] + sides[j] * hw, ys[j]), -slab, Vector2(1.0, acc[j]), concrete, total, Vector3.DOWN)
	for j in cs.size() - 1:
		var o := bb + j * 2
		idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))
	if look == "tube":
		shell_strip(cs, ys, sides, hw * 0.92, uv_y0, acc)
		return
	if look in ["beam", "belt"]:
		return                  # 모노레일 빔·컨베이어는 난간이 없다
	var rail := code_of(type, 5)
	for si in 2:
		var sgn := -1.0 if si == 0 else 1.0
		var rb := v.size()
		for j in cs.size():
			var p := cs[j] + sides[j] * (hw - 0.15) * sgn
			var out := Vector3(sides[j].x * sgn, 0.0, -sides[j].y * sgn)
			_vert_g(at3(p, ys[j]), THICK, Vector2(0.0, acc[j]), rail, total, out)
			_vert_g(at3(p, ys[j]), THICK + RAIL_H, Vector2(1.0, acc[j]), rail, total, out)
		for j in cs.size() - 1:
			var o := rb + j * 2
			idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))


## 높은 가압 통로의 반원 껍질 (덱 높이를 따라)
func shell_strip(cs: PackedVector2Array, ys: PackedFloat32Array, sides: PackedVector2Array, r: float, uv_y0: float,
		acc: PackedFloat32Array) -> void:
	var segs := 10
	var base := v.size()
	for k in cs.size():
		for j in segs + 1:
			var ang := PI * float(j) / segs
			var off := sides[k] * cos(ang) * r
			var up := sin(ang) * r * 0.9
			var nrm := Vector3(sides[k].x * cos(ang), sin(ang), -sides[k].y * cos(ang)).normalized()
			_vert_g(at3(cs[k] + off, ys[k]), THICK + up, Vector2(float(j) / segs, uv_y0 + acc[k]), code_of("tube", 3),
				acc[-1], nrm)
	for k in cs.size() - 1:
		for j in segs:
			var o := base + k * (segs + 1) + j
			idx.append_array(PackedInt32Array([o, o + segs + 1, o + 1, o + 1, o + segs + 1, o + segs + 2]))


## 높은 길의 가운데 꼭짓점: 곧게 이어지면 그대로 (틈은 덱 판 하나로), 꺾이면 덱 높이의 원호
func _raised_joint(i: int, c: Vector2, list: Array, back: Dictionary) -> void:
	if list.size() != 2:
		return
	var ea: Dictionary = list[0]
	var eb: Dictionary = list[1]
	var k := int(ea["edge"])
	var d: Dictionary = _lv[k] if k < _lv.size() else {}
	if d.is_empty():
		return
	var t_at := 0.0 if (_edges[k] as Vector2i).x == i else 1.0
	var y := deck_y(k, t_at, c)
	var sa := float(back.get(ea["edge"], 0.0))
	var hw := maxf(float(ea["hw"]), float(eb["hw"]))
	var da: Vector2 = ea["dir"]
	var db: Vector2 = eb["dir"]
	var tp := String(ea["type"]) if float(ea["hw"]) >= float(eb["hw"]) else String(eb["type"])
	if sa <= 0.01:
		# 곧게 잇는 곳: 두 덱 끝 사이의 쐐기 틈을 짧은 덱으로
		var pa := c + da * minf(1.0, float(ea["len"]) * 0.2)
		var pb := c + db * minf(1.0, float(eb["len"]) * 0.2)
		deck_strip(PackedVector2Array([pa, c, pb]), PackedFloat32Array([y, y, y]), hw, tp)
		return
	var pa2 := c + da * sa
	var pb2 := c + db * sa
	var bis := (da + db).normalized()
	var turn := PI - absf(da.angle_to(db))
	var r := sa / maxf(tan(turn * 0.5), 1e-3)
	var center := c + bis * sqrt(sa * sa + r * r)
	var a0 := (pa2 - center).angle()
	var a1 := (pb2 - center).angle()
	var span := wrapf(a1 - a0, -PI, PI)
	var steps := maxi(4, int(ceil(absf(span) * r / STEP_M)))
	var cs := PackedVector2Array()
	var ys := PackedFloat32Array()
	for j in steps + 1:
		cs.append(center + Vector2.from_angle(a0 + span * float(j) / steps) * r)
		ys.append(y)
	deck_strip(cs, ys, hw, tp)


## 받침 상자: 가운데 p, 크기 size (x 가로·y 높이·z 깊이), 수평 방향 dir(2D — 상자의 z가 그쪽), 색, 밤빛
func box(p: Vector3, size: Vector3, dir: Vector2, col: Color, glow := 0.0) -> void:
	var fwd := Vector3(dir.x, 0.0, -dir.y).normalized()
	if fwd.length_squared() < 1e-6:
		fwd = Vector3(0, 0, 1)
	var right := Vector3.UP.cross(fwd).normalized()
	sx.append(Transform3D(Basis(right * size.x, Vector3.UP * size.y, fwd * size.z), p))
	sc.append(col)
	su.append(Color(glow, 0, 0, 0))


## 받침 막대: a에서 b까지 (굵기 w × d) — 기울어진 다리·케이블·트러스
func bar(a: Vector3, b: Vector3, w: float, d: float, col: Color, glow := 0.0) -> void:
	var ax := b - a
	var length := ax.length()
	if length < 0.01:
		return
	var up := ax / length
	var ref := Vector3.UP if absf(up.y) < 0.95 else Vector3(1, 0, 0)
	var side := up.cross(ref).normalized()
	var third := side.cross(up).normalized()
	sx.append(Transform3D(Basis(side * w, up * length, third * d), (a + b) * 0.5))
	sc.append(col)
	su.append(Color(glow, 0, 0, 0))


## 받침 상자들을 MultiMesh 버퍼로 (없으면 빈 배열)
func struct_buffer() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(sx.size() * 20)
	var o := 0
	for i in sx.size():
		var t: Transform3D = sx[i]
		var bs := t.basis
		buf[o] = bs.x.x
		buf[o + 1] = bs.y.x
		buf[o + 2] = bs.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = bs.x.y
		buf[o + 5] = bs.y.y
		buf[o + 6] = bs.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = bs.x.z
		buf[o + 9] = bs.y.z
		buf[o + 10] = bs.z.z
		buf[o + 11] = t.origin.z
		var c := sc[i]
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = c.a
		var u := su[i]
		buf[o + 16] = u.r
		buf[o + 17] = u.g
		buf[o + 18] = u.b
		buf[o + 19] = u.a
		o += 20
	return buf


# ── 길 그물 전체 ────────────────────────────────────────────────
## 계획의 길 그물을 한 메시로: 교차로의 물러남·판, 굽은 곳의 둥근 띠, 막다른 곳의 둥근 끝
static func build(plan: CityPlan, p_h: Callable) -> ArrayMesh:
	var rm := start(plan, p_h)
	rm.step(0)
	return rm.mesh()


## 나눠 짓기를 시작한다: 길 그물을 베껴 둔다 (짓는 동안 계획이 바뀌면 부르는 쪽이 새로 시작한다)
static func start(plan: CityPlan, p_h: Callable) -> RoadMesh:
	var rm := RoadMesh.new(p_h)
	rm._nodes = plan.nodes.duplicate()
	rm._edges = plan.edges.duplicate()
	rm._types = plan.etypes.duplicate()
	rm._inc = RoadNet.incident(rm._nodes, rm._edges, rm._types)
	rm._back = RoadNet.setbacks(rm._nodes, rm._inc)
	rm._lv = plan.levels().duplicate(true)
	rm._lvn = plan._node_levels()
	rm._chains = rm._chain_list()
	return rm


## 길마다, 그다음 꼭짓점마다 budget_us까지 짓는다 (0이면 끝까지). 다 지었으면 true
func step(budget_us: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while _k < _edges.size():
		_edge(_k)
		_k += 1
		if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
			return false
	while _i < _nodes.size():
		_node(_i)
		_i += 1
		if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
			return false
	while _c < _chains.size():
		RoadStructs.build(self, _chains[_c])
		_c += 1
		if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
			return false
	return true


func _edge(k: int) -> void:
	var e: Vector2i = _edges[k]
	var a: Vector2 = _nodes[e.x]
	var b: Vector2 = _nodes[e.y]
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var dir := (b - a) / length
	var sa := float((_back[e.x] as Dictionary).get(k, 0.0))
	var sb := float((_back[e.y] as Dictionary).get(k, 0.0))
	if sa + sb > length - 0.2:
		var f := (length - 0.2) / maxf(sa + sb, 0.01)
		sa *= f
		sb *= f
	var t := String(_types[k]) if k < _types.size() else "street"
	if k < _lv.size() and not (_lv[k] as Dictionary).is_empty():
		deck_edge(k, a + dir * sa, b - dir * sb, sa, length)
		return
	ribbon(a + dir * sa, b - dir * sb, LayoutData.road_half(t), t, sa)


func _node(i: int) -> void:
	var list: Array = _inc[i]
	var c: Vector2 = _nodes[i]
	if i < _lvn.size() and _lvn[i] == 2:
		_raised_joint(i, c, list, _back[i])
		return
	match list.size():
		1:
			_cap(c, list[0])
		2:
			_bend(c, list[0], list[1], _back[i])
		_:
			if list.size() >= 3:
				_crossing(c, list, _back[i])


## 막다른 곳: 둥근 끝 (가압 통로는 연결 모듈)
func _cap(c: Vector2, e: Dictionary) -> void:
	var hw := float(e["hw"])
	var t := String(e["type"])
	if t == "tube":
		hub_module(c, hw * 1.25)
		return
	if t == "rail":
		return
	var d: Vector2 = e["dir"]
	var pts := PackedVector2Array()
	var side := Vector2(-d.y, d.x)
	for k in 9:
		var a := PI * float(k) / 8.0
		pts.append(c + side * cos(a) * hw - d * sin(a) * hw)
	pts.reverse()
	junction(c, pts, t)


## 두 길이 만나는 곳: 곧게 이어지면 그대로(틈만 메운다), 꺾이면 반지름 있는 굽은 띠
func _bend(c: Vector2, ea: Dictionary, eb: Dictionary, back: Dictionary) -> void:
	var ta := String(ea["type"])
	var tb := String(eb["type"])
	var sa := float(back.get(ea["edge"], 0.0))
	var hw := maxf(float(ea["hw"]), float(eb["hw"]))
	if ta == "tube" or tb == "tube":
		hub_module(c, hw * 1.15)
		if sa <= 0.01:
			return
	var da: Vector2 = ea["dir"]
	var db: Vector2 = eb["dir"]
	if sa <= 0.01:
		# 곧게 잇는 곳: 두 띠 끝 사이의 쐐기 틈을 판으로 메운다
		var pts := PackedVector2Array([c + Vector2(-da.y, da.x) * hw, c - Vector2(-da.y, da.x) * hw,
			c + Vector2(-db.y, db.x) * hw, c - Vector2(-db.y, db.x) * hw])
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() >= 4:
			hull.remove_at(hull.size() - 1)
			junction(c, hull, ta)
		return
	# 굽은 띠: 두 접점 사이를 원호로 (접점 = 꼭짓점에서 물러난 곳)
	var pa := c + da * sa
	var pb := c + db * sa
	var bis := (da + db).normalized()
	var turn := PI - absf(da.angle_to(db))
	var r := sa / maxf(tan(turn * 0.5), 1e-3)
	var center := c + bis * sqrt(sa * sa + r * r)
	var a0 := (pa - center).angle()
	var a1 := (pb - center).angle()
	var span := wrapf(a1 - a0, -PI, PI)
	var steps := maxi(4, int(ceil(absf(span) * r / STEP_M)))
	var prev := pa
	var t := ta if float(ea["hw"]) >= float(eb["hw"]) else tb
	var acc := 0.0
	for k in range(1, steps + 1):
		var q := center + Vector2.from_angle(a0 + span * float(k) / steps) * r
		ribbon(prev, q, hw, t, acc, -1.0)
		acc += prev.distance_to(q)
		prev = q
	# 이음매(띠와 띠 사이 쐐기)는 짧은 띠라 거의 보이지 않는다


## 셋 이상 만나는 교차로: 길마다 물러난 끝의 두 모서리를 이웃 길과 둥글게 이은 판
func _crossing(c: Vector2, list: Array, back: Dictionary) -> void:
	var tubes := list.filter(func(e): return String(e["type"]) == "tube").size()
	var widest := ""
	var w := 0.0
	for e in list:
		if float(e["hw"]) > w and String(e["type"]) != "tube":
			w = float(e["hw"])
			widest = String(e["type"])
	if tubes > 0:
		var hw_max := 0.0
		for e in list:
			hw_max = maxf(hw_max, float(e["hw"]))
		hub_module(c, hw_max * 1.4)
		if widest == "":
			return
	var pts := PackedVector2Array()
	var cnt := list.size()
	for j in cnt:
		var e: Dictionary = list[j]
		var o: Dictionary = list[(j + 1) % cnt]
		var de: Vector2 = e["dir"]
		var do: Vector2 = o["dir"]
		var se := float(back.get(e["edge"], 0.0))
		var so := float(back.get(o["edge"], 0.0))
		var right_e := c + de * se - Vector2(-de.y, de.x) * float(e["hw"])
		var left_e := c + de * se + Vector2(-de.y, de.x) * float(e["hw"])
		var right_o := c + do * so - Vector2(-do.y, do.x) * float(o["hw"])
		pts.append(right_e)
		pts.append(left_e)
		# 이웃 길까지 둥글게: 두 가장자리선이 만나는 점을 조절점으로
		var hit: Variant = RoadNet.line_hit(left_e, -de, right_o, -do)
		var ctrl: Vector2 = c if hit == null or (hit as Vector2).distance_to(c) > w * 4.0 else hit
		for k in range(1, 4):
			var tt := float(k) / 4.0
			var u := 1.0 - tt
			pts.append(left_e * u * u + ctrl * 2.0 * u * tt + right_o * tt * tt)
	junction(c, pts, widest)
