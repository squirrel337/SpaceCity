class_name RoadMesh
extends RefCounted
## 길 그물의 3D 메시 — 길마다 종류의 폭으로 땅을 따라가는 띠(2 m마다 땅 높이, 두께와 옆면이 있다),
## 셋 이상 만나는 곳은 교차로 판(가장자리를 둥글게), 둘이 꺾이는 곳은 반지름 있는 굽은 띠, 끝은 둥근 막다른 곳.
## 가압 통로는 띠 위에 반원 껍질을 씌우고 만나는 곳에 둥근 연결 모듈을 둔다.
## 높이는 h(p: Vector2, above: float) -> Vector3 (City3D._local — 땅 높이·곡률)로 얻는다.

const STEP_M := 2.0
const THICK := 0.18                      # 길의 두께 (땅 위로)
const SKIRT := 0.7                       # 옆면이 땅 속으로 내려가는 깊이
const TYPE_CODE := {"path": 0, "street": 1, "avenue": 2, "highway": 3, "tube": 4, "rail": 5, "runway": 6}

var v := PackedVector3Array()
var n := PackedVector3Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var idx := PackedInt32Array()
var h: Callable


func _init(p_h: Callable) -> void:
	h = p_h


func _vert(p: Vector2, above: float, u: Vector2, code: float, length: float, nrm := Vector3.UP) -> int:
	v.append(h.call(p, above))
	n.append(nrm)
	uv.append(u)
	uv2.append(Vector2(code, length))
	return v.size() - 1


static func code_of(type: String, part: int) -> float:
	return float(TYPE_CODE.get(type, 1) + part * 10)


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
	for k in steps + 1:
		var t := float(k) / steps
		var c := a.lerp(b, t)
		var yy := uv_y0 + t * length
		for s in [-1.0, 1.0]:
			_vert(c + side * hw * s, THICK, Vector2(0.5 + s * 0.5, yy), code, tot)
	for k in steps:
		var o := base + k * 2
		idx.append_array(PackedInt32Array([o, o + 1, o + 2, o + 1, o + 3, o + 2]))
	# 옆면: 가장자리에서 땅 속으로
	for s: float in [-1.0, 1.0]:
		var sb := v.size()
		var out := Vector3(side.x * s, 0.0, -side.y * s)
		for k in steps + 1:
			var t := float(k) / steps
			var c := a.lerp(b, t) + side * hw * s
			_vert(c, THICK, Vector2(0.0, uv_y0 + t * length), code_of(type, 2), tot, out)
			_vert(c, -SKIRT, Vector2(1.0, uv_y0 + t * length), code_of(type, 2), tot, out)
		for k in steps:
			var o := sb + k * 2
			idx.append_array(PackedInt32Array([o, o + 2, o + 1, o + 1, o + 2, o + 3]))
	if type == "tube":
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
	for p in pts:
		_vert(p, THICK + 0.005, Vector2(0.5, 0.0), code, 0.0)
	for i in pts.size():
		var a := first + i
		var b := first + (i + 1) % pts.size()
		idx.append_array(PackedInt32Array([c, b, a]))
	# 옆면
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		var e := (q - p).normalized()
		var out := Vector3(e.y, 0.0, e.x)
		var sb := v.size()
		_vert(p, THICK, Vector2(0.0, 0.0), code_of(type, 2), 0.0, out)
		_vert(p, -SKIRT, Vector2(1.0, 0.0), code_of(type, 2), 0.0, out)
		_vert(q, THICK, Vector2(0.0, 1.0), code_of(type, 2), 0.0, out)
		_vert(q, -SKIRT, Vector2(1.0, 1.0), code_of(type, 2), 0.0, out)
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


# ── 길 그물 전체 ────────────────────────────────────────────────
## 계획의 길 그물을 한 메시로: 교차로의 물러남·판, 굽은 곳의 둥근 띠, 막다른 곳의 둥근 끝
static func build(plan: CityPlan, p_h: Callable) -> ArrayMesh:
	var rm := RoadMesh.new(p_h)
	var nodes := plan.nodes
	var inc := RoadNet.incident(nodes, plan.edges, plan.etypes)
	var back := RoadNet.setbacks(nodes, inc)
	for k in plan.edges.size():
		var e: Vector2i = plan.edges[k]
		var a: Vector2 = nodes[e.x]
		var b: Vector2 = nodes[e.y]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var dir := (b - a) / length
		var sa := float((back[e.x] as Dictionary).get(k, 0.0))
		var sb := float((back[e.y] as Dictionary).get(k, 0.0))
		if sa + sb > length - 0.2:
			var f := (length - 0.2) / maxf(sa + sb, 0.01)
			sa *= f
			sb *= f
		var t := plan.edge_type(k)
		rm.ribbon(a + dir * sa, b - dir * sb, LayoutData.road_half(t), t, sa)
	for i in nodes.size():
		var list: Array = inc[i]
		var c: Vector2 = nodes[i]
		match list.size():
			1:
				rm._cap(c, list[0])
			2:
				rm._bend(c, list[0], list[1], back[i])
			_:
				if list.size() >= 3:
					rm._crossing(c, list, back[i])
	return rm.mesh()


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
