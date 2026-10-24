class_name WorksView
extends MultiMeshInstance3D
## 길 공사의 3D 모습 (RoadWorks — 배치 계획의 works): 단위 상자 하나의 멀티메시를 색으로 칠해 쓴다.
##   넓히기: 넓어질 폭의 두 가장자리에 차단막(주황·흰 줄)과 고깔이 5 m마다 선다
##   노선: 공정의 앞 60%에 기둥이 시작점부터 차례로 올라가고(받침이 서는 곳 — 덱이 땅에서 2 m 넘게 뜬 곳), 뒤 40%에 덱 판이
##         그 차례로 놓인다. 공사의 앞머리에 노란 크레인이 선다
## 공정이 바뀔 때만 다시 놓는다 (CityPlan.works_rev와 공정 1% 단위)

const BARRIER := Color(0.93, 0.47, 0.13)
const BARRIER_W := Color(0.92, 0.92, 0.9)
const CONE := Color(1.0, 0.55, 0.12)
const PILLAR := Color(0.62, 0.62, 0.6)
const DECK := Color(0.42, 0.42, 0.43)
const CRANE := Color(0.95, 0.76, 0.18)
const PILLAR_PART := 0.6

var _sig := ""


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	material_override = mat


## local: 기지 모형 좌표(m) → 3D (땅 위 above m) — City3D._local
func refresh(plan: CityPlan, local: Callable) -> void:
	var parts := PackedStringArray([str(plan.works_rev), str(plan.terrain_rev)])
	for w in plan.works:
		parts.append(str(int(float(w["p"]) * 100.0)))
	var sig := ",".join(parts)
	if sig == _sig:
		return
	_sig = sig
	var boxes: Array = []                 # [Transform3D, Color]
	for w in plan.works:
		if String(w["kind"]) == "widen":
			_barriers(boxes, w, local)
		else:
			_line(boxes, w, local)
	multimesh.instance_count = boxes.size()
	for i in boxes.size():
		multimesh.set_instance_transform(i, boxes[i][0])
		multimesh.set_instance_color(i, boxes[i][1])
	visible = not boxes.is_empty()


static func _box(boxes: Array, center: Vector3, size: Vector3, dir: Vector2, col: Color) -> void:
	var yaw := atan2(dir.y, dir.x)          # 모형 좌표 (x, y) → 3D (x, -z)
	boxes.append([Transform3D(Basis(Vector3.UP, yaw).scaled(size), center), col])


## a3에서 b3까지 이어진 판 (기울어도 된다): 폭 w, 두께 t
static func _slab(boxes: Array, a3: Vector3, b3: Vector3, w: float, t: float, col: Color) -> void:
	var along := b3 - a3
	var l := along.length()
	if l < 0.01:
		return
	var x := along / l
	var z := x.cross(Vector3.UP).normalized()
	if z.length_squared() < 1e-6:
		z = Vector3(0, 0, 1)
	var y := z.cross(x).normalized()
	boxes.append([Transform3D(Basis(x * l, y * t, z * w), (a3 + b3) * 0.5), col])


static func _barriers(boxes: Array, w: Dictionary, local: Callable) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var hw := LayoutData.road_half(String(w["type"])) + 0.4
	var n := maxi(1, int(a.distance_to(b) / 5.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / n)
		for s: float in [-1.0, 1.0]:
			var q := p + side * hw * s
			var g: Vector3 = local.call(q, 0.0)
			if i % 3 == 1:
				_box(boxes, g + Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.5), dir, CONE)
			else:
				_box(boxes, g + Vector3(0, 0.55, 0), Vector3(2.4, 0.5, 0.25), dir, BARRIER if i % 2 == 0 else BARRIER_W)
				_box(boxes, g + Vector3(0, 0.2, 0), Vector3(2.2, 0.35, 0.18), dir, BARRIER_W)


static func _line(boxes: Array, w: Dictionary, local: Callable) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var type := String(w["type"])
	var rd := LayoutData.road(type)
	var len_m := a.distance_to(b)
	var deck := float(rd.get("deck_m", 6.0))
	var grade := float(rd.get("grade", 0.1))
	var hw := LayoutData.road_half(type)
	var span := maxf(float(rd.get("span_m", 24.0)), 8.0)
	var dir := (b - a) / maxf(len_m, 0.01)
	var p := float(w["p"])
	var n := maxi(2, int(ceil(len_m / span)))
	var front := a
	var front_y := 0.0
	# 기둥: 덱이 2 m 넘게 뜬 곳에, 시작점부터 차례로 올라간다
	for i in range(n + 1):
		var s := len_m * float(i) / n
		var lift := minf(deck, grade * minf(s, len_m - s))
		var at := a + dir * s
		var grow := clampf(p / PILLAR_PART * (n + 1) - i, 0.0, 1.0)
		if grow <= 0.0:
			continue
		front = at
		front_y = lift * grow
		if lift < 2.0:
			continue
		var g: Vector3 = local.call(at, 0.0)
		var h := (lift - 0.9) * grow
		_box(boxes, g + Vector3(0, h * 0.5, 0), Vector3(1.6, h, minf(2.4, hw)), dir, PILLAR)
		if grow >= 1.0:
			_box(boxes, g + Vector3(0, lift - 0.5, 0), Vector3(2.0, 0.9, hw * 1.9), dir, PILLAR)
	# 덱: 뒤 40%에 기둥 사이마다 차례로
	var dp := clampf((p - PILLAR_PART) / (1.0 - PILLAR_PART), 0.0, 1.0)
	var m := int(floor(dp * n))
	for i in range(m):
		var s0 := len_m * float(i) / n
		var s1 := len_m * float(i + 1) / n
		var g0: Vector3 = local.call(a + dir * s0, minf(deck, grade * minf(s0, len_m - s0)))
		var g1: Vector3 = local.call(a + dir * s1, minf(deck, grade * minf(s1, len_m - s1)))
		_slab(boxes, g0, g1, hw * 2.0, 0.9, DECK)
		front = a + dir * s1
		front_y = minf(deck, grade * minf(s1, len_m - s1))
	# 크레인: 공사의 앞머리 옆에
	if p < 1.0:
		var side := Vector2(-dir.y, dir.x)
		var c2 := front + side * (hw + 4.0)
		var g2: Vector3 = local.call(c2, 0.0)
		var mast := maxf(front_y, deck) + 9.0
		_box(boxes, g2 + Vector3(0, mast * 0.5, 0), Vector3(1.1, mast, 1.1), dir, CRANE)
		var jib_dir := -side
		var jib := g2 + Vector3(0, mast, 0) + Vector3(jib_dir.x, 0, -jib_dir.y) * 6.0
		_box(boxes, jib, Vector3(16.0, 0.7, 0.7), jib_dir, CRANE)
		_box(boxes, g2 + Vector3(0, 0.6, 0), Vector3(4.0, 1.2, 4.0), dir, CRANE.darkened(0.35))
