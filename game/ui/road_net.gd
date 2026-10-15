class_name RoadNet
extends RefCounted
## 길 그물의 기하 — 길이 둘러싼 블록(평면 그래프의 면)을 찾고, 교차로·굽은 곳의 모양을 셈한다.
## 좌표는 기지 모형 좌표 (m, x·y 수평). 길은 꼭짓점(Vector2)과 길(Vector2i 두 꼭짓점) + 길마다의 종류.


## 블록: 길이 둘러싼 면 (바깥 면은 뺀다). [PackedVector2Array (반시계)]
static func faces(nodes: Array, edges: Array) -> Array:
	var n := nodes.size()
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = []
	for e in edges:
		var a: int = e.x
		var b: int = e.y
		if a == b:
			continue
		adj[a].append(b)
		adj[b].append(a)
	# 꼭짓점마다 이웃을 각도 순으로
	for i in n:
		var p: Vector2 = nodes[i]
		(adj[i] as Array).sort_custom(func(x, y):
			var ax: float = ((nodes[x] as Vector2) - p).angle()
			var ay: float = ((nodes[y] as Vector2) - p).angle()
			return ax < ay)
	var used := {}
	var out: Array = []
	for i in n:
		for j in adj[i]:
			var key := Vector2i(i, j)
			if used.has(key):
				continue
			# 반쪽 길 i→j에서 시작해 늘 '오른쪽으로 가장 덜 꺾이는' 길을 따라 돈다 (면 하나)
			var poly := PackedVector2Array()
			var u := i
			var v: int = j
			var guard := 0
			while guard < 4096:
				guard += 1
				used[Vector2i(u, v)] = true
				poly.append(nodes[u])
				var nb: Array = adj[v]
				var k := nb.find(u)
				# 들어온 쪽(v→u)의 바로 앞(시계 방향 다음) 이웃
				var w: int = nb[(k - 1 + nb.size()) % nb.size()]
				u = v
				v = w
				if u == i and v == j:
					break
			if poly.size() >= 3 and _area(poly) > 1.0:
				out.append(poly)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func area(poly: PackedVector2Array) -> float:
	return absf(_area(poly))


static func centroid(poly: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var cr := p.x * q.y - q.x * p.y
		a += cr
		c += (p + q) * cr
	if absf(a) < 1e-6:
		var s := Vector2.ZERO
		for p in poly:
			s += p
		return s / maxf(1.0, poly.size())
	return c / (3.0 * a)


## 블록의 안쪽 (길 반폭 + 보도만큼 줄인 것). 오목한 면은 여럿으로 나뉠 수 있다
static func inset(poly: PackedVector2Array, d: float) -> Array:
	var res := Geometry2D.offset_polygon(poly, -d, Geometry2D.JOIN_MITER)
	var out: Array = []
	for p in res:
		if area(p) > 60.0:          # 단순한 면을 줄인 것이라 구멍은 없다
			out.append(p)
	return out


## 축 정렬 사각형이 다각형 안에 다 들어가나
static func rect_inside(r: Rect2, poly: PackedVector2Array) -> bool:
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		if not Geometry2D.is_point_in_polygon(c, poly):
			return false
	return true


# ── 교차로·굽은 곳 ───────────────────────────────────────────────
## 꼭짓점마다 이어진 길 [{edge, other, dir, hw, type}] (각도 순)
static func incident(nodes: Array, edges: Array, types: Array) -> Array:
	var out: Array = []
	out.resize(nodes.size())
	for i in nodes.size():
		out[i] = []
	for k in edges.size():
		var e: Vector2i = edges[k]
		var t: String = types[k] if k < types.size() else "street"
		var hw := LayoutData.road_half(t)
		var a: Vector2 = nodes[e.x]
		var b: Vector2 = nodes[e.y]
		if a.distance_to(b) < 0.01:
			continue
		out[e.x].append({"edge": k, "other": e.y, "dir": (b - a).normalized(), "hw": hw, "type": t, "len": a.distance_to(b)})
		out[e.y].append({"edge": k, "other": e.x, "dir": (a - b).normalized(), "hw": hw, "type": t, "len": a.distance_to(b)})
	for i in nodes.size():
		(out[i] as Array).sort_custom(func(x, y): return (x["dir"] as Vector2).angle() < (y["dir"] as Vector2).angle())
	return out


## 두 직선(점 p·방향 d)의 만나는 점. 거의 나란하면 null
static func line_hit(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2) -> Variant:
	var cr := d1.cross(d2)
	if absf(cr) < 1e-4:
		return null
	var t := (p2 - p1).cross(d2) / cr
	return p1 + d1 * t


## 교차로의 물러남: 꼭짓점에서 길마다 띠가 시작하는 거리 (이웃 길과 가장자리가 만나는 곳까지)
## 반환: edge 번호 → 물러난 거리 (m). 꼭짓점이 둘(곧게 잇거나 굽는 곳)이면 굽은 곳의 접점 거리
static func setbacks(nodes: Array, inc: Array) -> Array:
	var out: Array = []
	out.resize(nodes.size())
	for i in nodes.size():
		var list: Array = inc[i]
		var d := {}
		var n := list.size()
		if n == 2:
			var a: Dictionary = list[0]
			var b: Dictionary = list[1]
			var turn := PI - absf((a["dir"] as Vector2).angle_to(b["dir"]))     # 0 = 곧게, 클수록 많이 꺾임
			if turn < deg_to_rad(8.0) and a["type"] == b["type"]:
				d[a["edge"]] = 0.0
				d[b["edge"]] = 0.0
			else:
				var r := maxf(float(LayoutData.road(a["type"])["turn_r_m"]), float(LayoutData.road(b["type"])["turn_r_m"]))
				r = maxf(r, maxf(float(a["hw"]), float(b["hw"])) * 1.2)
				var t := r * tan(turn * 0.5)
				t = minf(t, minf(float(a["len"]), float(b["len"])) * 0.45)
				d[a["edge"]] = t
				d[b["edge"]] = t
		elif n >= 3:
			for j in n:
				var e: Dictionary = list[j]
				var best := float(e["hw"])
				for side in [-1, 1]:
					var o: Dictionary = list[(j + side + n) % n]
					var de: Vector2 = e["dir"]
					var do: Vector2 = o["dir"]
					var ne := Vector2(-de.y, de.x) * float(e["hw"]) * side
					var no := Vector2(do.y, -do.x) * float(o["hw"]) * side
					var hit: Variant = line_hit(ne, de, no, do)
					if hit != null:
						var along := (hit as Vector2).dot(de)
						if along > 0.0 and along < float(e["len"]) * 0.45:
							best = maxf(best, along)
				d[e["edge"]] = best + 0.5
		else:
			for e in list:
				d[e["edge"]] = 0.0
		out[i] = d
	return out
