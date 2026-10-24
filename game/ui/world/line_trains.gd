class_name LineTrains
extends MultiMeshInstance3D
## 궤도 노선의 열차: 모노레일·자기부상 궤도의 사슬(같은 종류로 이어진 길)마다 열차 한 편이 끝에서 끝까지 오간다 — 덱 위에 뜬다.
## 단위 상자 하나의 멀티메시를 색으로 칠해 쓴다 (차량마다 몸통 + 띠 + 창). 보여 주기만 한다

const KINDS := {
	"monorail": {"cars": 3, "len": 9.0, "w": 2.6, "h": 2.8, "speed": 16.0, "body": Color(0.92, 0.93, 0.95), "band": Color(0.82, 0.2, 0.17)},
	"maglev": {"cars": 4, "len": 14.0, "w": 3.2, "h": 2.4, "speed": 34.0, "body": Color(0.95, 0.96, 0.97), "band": Color(0.2, 0.42, 0.78)},
}
const WINDOW := Color(0.16, 0.22, 0.3)
const GAP := 0.8
const DWELL_S := 4.0

var _sig := ""
var _lines: Array = []            # {type, pts: PackedVector2Array, ks: 토막마다 길 번호, len, s, dir, wait}


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mat.metallic = 0.2
	material_override = mat


## 길 그물이 바뀌면 노선을 다시 찾는다 (열차는 그 노선의 처음에서 다시 떠난다)
func refresh(plan: CityPlan) -> void:
	var sig := "%d|%d" % [plan.road_rev, plan.edges.size()]
	if sig == _sig:
		return
	_sig = sig
	_lines.clear()
	for type in KINDS:
		for chain in chains(plan, type):
			var pts := PackedVector2Array()
			for n: int in chain["nodes"]:
				pts.append(plan.nodes[n])
			var total := 0.0
			for i in range(1, pts.size()):
				total += pts[i].distance_to(pts[i - 1])
			if total < 30.0:
				continue
			_lines.append({"type": type, "pts": pts, "ks": chain["edges"], "len": total, "s": 0.0, "dir": 1.0, "wait": 0.0})
	visible = not _lines.is_empty()
	if _lines.is_empty():
		multimesh.instance_count = 0


## 그 종류의 길로만 이어진 사슬: [{nodes: 꼭짓점 차례, edges: 토막마다 길 번호}] (갈래가 있으면 거기서 끊는다)
static func chains(plan: CityPlan, type: String) -> Array:
	var inc := {}
	for k in plan.edges.size():
		if plan.edge_type(k) != type:
			continue
		var e: Vector2i = plan.edges[k]
		for n in [e.x, e.y]:
			if not inc.has(n):
				inc[n] = []
			(inc[n] as Array).append(k)
	var used := {}
	var out: Array = []
	for start in inc:
		if (inc[start] as Array).size() == 2:
			continue                      # 사슬의 가운데 — 끝에서부터 걷는다
		for k0 in inc[start]:
			if used.has(k0):
				continue
			var nodes: Array = [start]
			var ks: Array = []
			var at: int = start
			var k: int = k0
			while true:
				used[k] = true
				ks.append(k)
				var e: Vector2i = plan.edges[k]
				at = e.y if e.x == at else e.x
				nodes.append(at)
				var nexts: Array = inc[at]
				if nexts.size() != 2:
					break
				k = nexts[0] if nexts[0] != k else nexts[1]
				if used.has(k):
					break
			out.append({"nodes": nodes, "edges": ks})
	return out


## local: City3D._local. 열차를 delta초만큼 움직이고 차량 상자를 놓는다
func step(plan: CityPlan, local: Callable, delta: float) -> void:
	if _lines.is_empty():
		return
	var boxes: Array = []
	for l in _lines:
		var kd: Dictionary = KINDS[l["type"]]
		var train := float(kd["cars"]) * (float(kd["len"]) + GAP)
		var run := maxf(float(l["len"]) - train, 0.0)
		if float(l["wait"]) > 0.0:
			l["wait"] = float(l["wait"]) - delta
		else:
			l["s"] = float(l["s"]) + float(l["dir"]) * float(kd["speed"]) * delta
			if float(l["s"]) >= run or float(l["s"]) <= 0.0:
				l["s"] = clampf(float(l["s"]), 0.0, run)
				l["dir"] = -float(l["dir"])
				l["wait"] = DWELL_S
		for c in int(kd["cars"]):
			var s0 := float(l["s"]) + c * (float(kd["len"]) + GAP)
			var a3 := _at(plan, local, l, s0)
			var b3 := _at(plan, local, l, s0 + float(kd["len"]))
			_car(boxes, a3, b3, kd)
	multimesh.instance_count = boxes.size()
	for i in boxes.size():
		multimesh.set_instance_transform(i, boxes[i][0])
		multimesh.set_instance_color(i, boxes[i][1])


## 노선 위 s m 자리의 3D 점 (덱 위)
static func _at(plan: CityPlan, local: Callable, l: Dictionary, s: float) -> Vector3:
	var pts: PackedVector2Array = l["pts"]
	var ks: Array = l["ks"]
	var left := s
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if left <= seg or i == pts.size() - 1:
			var f := clampf(left / maxf(seg, 0.01), 0.0, 1.0)
			var k: int = ks[i - 1]
			var e: Vector2i = plan.edges[k]
			var t := f if (plan.nodes[e.x] as Vector2).distance_to(pts[i - 1]) < 0.05 else 1.0 - f
			return local.call(pts[i - 1].lerp(pts[i], f), plan.deck_offset(k, t) + 0.35)
		left -= seg
	return local.call(pts[-1], 0.0)


static func _car(boxes: Array, a3: Vector3, b3: Vector3, kd: Dictionary) -> void:
	var along := b3 - a3
	var l := along.length()
	if l < 0.01:
		return
	var x := along / l
	var z := x.cross(Vector3.UP).normalized()
	if z.length_squared() < 1e-6:
		z = Vector3(0, 0, 1)
	var y := z.cross(x).normalized()
	var h := float(kd["h"])
	var w := float(kd["w"])
	var c := (a3 + b3) * 0.5 + y * (h * 0.5)
	boxes.append([Transform3D(Basis(x * l, y * h, z * w), c), kd["body"]])
	boxes.append([Transform3D(Basis(x * (l * 1.002), y * (h * 0.16), z * (w * 1.02)), c - y * (h * 0.3)), kd["band"]])
	boxes.append([Transform3D(Basis(x * (l * 0.86), y * (h * 0.28), z * (w * 1.03)), c + y * (h * 0.12)), WINDOW])
