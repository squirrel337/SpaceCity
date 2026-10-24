class_name EventsView
extends Node3D
## 재난의 흔적(CityPlan.scars — CityHazards)과 둘레 탐사(도시의 explore 상태 — CityExplore)의 3D 모습.
##   땅의 자국 — 운석: 둘레로 뻗은 밝은 분출물 광조 (갓 파인 흙은 둘레보다 밝다 — 구덩이는 땅에 남는다) ·
##               월진: 줄을 따라 갈라진 금과 흐트러진 흙 · 먼지 회오리: 고운 먼지가 쓸려 드러난 어두운 띠 (화성) ·
##               화재: 그을음 · 압력 누출: 서리. MARK_H 시간 동안 옅어진다
##   일어난 뒤 LIVE_H 시간 — 운석·월진: 피어오르다 가라앉는 먼지 · 먼지 회오리: 지나간 길을 따라 가는 깔때기 ·
##               화재: 연기 기둥과 불빛 · 압력 누출: 하얀 분출
##   탐사지마다 표지 (모르는 곳 — 호박색 고리와 낮은 기둥, 탐사대가 간 곳 — 깜박이는 파랑, 찾은 곳 — 초록 깃발)와
##   나가 있는 탐사대(가압 로버). 화면 위에는 탐사지·탐사대 이름표, 탐사대가 가는 길(점선), 막 일어난 재난 이름표 (draw_overlay)

const MARK_H := 480.0              # 땅의 자국이 다 옅어지는 시간 (20일)
const LIVE_H := 36.0               # 먼지·연기·깔때기가 보이는 시간
const DUST := Color(0.66, 0.6, 0.52)
const SOOT := Color(0.07, 0.065, 0.06)
const EJECTA := Color(0.8, 0.79, 0.76)
const TRACK := Color(0.2, 0.13, 0.09)
const SMOKE := Color(0.32, 0.31, 0.3)
const FROST := Color(0.9, 0.95, 1.0)
const FIRE := Color(1.0, 0.55, 0.15)
const STEEL := Color(0.62, 0.66, 0.7)
const SITE_COLORS := {"unknown": Color(0.95, 0.72, 0.25), "going": Color(0.35, 0.65, 1.0), "found": Color(0.35, 0.85, 0.45)}

var _sig := ""
var _marks: Array = []             # [MeshInstance3D, 재질 (scar 셰이더), 흔적, 처음 알파]
var _live: Array = []              # {w: 흔적, parts: [[MeshInstance3D, 재질]], light: OmniLight3D 또는 null}
var _beacons: Node3D
var _beacon_sig := ""
var _lamps: Array = []             # [재질, 상태]
var _rover: MeshInstance3D
var _rover_p := Vector2.INF
var _t := 0.0
var _hour := 0
var night := 0.0                   # 밤의 몫 (City3D가 정한다) — 땅의 자국이 밤에 어두워진다


func reset() -> void:
	_sig = ""
	_beacon_sig = ""
	_rover_p = Vector2.INF


## 매 프레임 (City3D.update — 도시가 보일 때). 흔적이 늘거나 땅이 바뀌면 다시 짓고, 그 밖에는 옅어짐·움직임만 고친다
func refresh(plan: CityPlan, sim: CitySim, colony: Dictionary, local: Callable, delta: float) -> void:
	_t += delta
	_hour = sim.hour
	var sig := "%d|%d|%d" % [plan.scars.size(), int(plan.scars[-1]["hour"]) if not plan.scars.is_empty() else -1, plan.terrain_rev]
	if sig != _sig:
		_sig = sig
		_build_scars(plan, local)
	_update_scars(local)
	_update_explore(plan, colony, local, delta)


# ── 재난의 흔적 ─────────────────────────────────────────────────
func _build_scars(plan: CityPlan, local: Callable) -> void:
	for m in _marks:
		(m[0] as Node).queue_free()
	for l in _live:
		for p in l["parts"]:
			(p[0] as Node).queue_free()
		if l["light"] != null:
			(l["light"] as Node).queue_free()
	_marks.clear()
	_live.clear()
	for w in plan.scars:
		var age := float(_hour - int(w["hour"]))
		if age >= MARK_H:
			continue
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var r := float(w["r"])
		var seed := float(int(w["hour"]) % 997) + a.x * 0.37
		match String(w["kind"]):
			"meteor":
				_mark(_disc(local, a, r * 2.6, EJECTA, seed, true), w, 0.85)
			"quake":
				_mark(_crack(local, a, b, seed), w, 0.9)
			"dust_devil":
				_mark(_band(local, a, b, r, seed, TRACK), w, 0.6)
			"fire":
				_mark(_disc(local, a, r * 1.2, SOOT, seed, false), w, 0.75)
			"blowout":
				_mark(_disc(local, a, r * 1.5, FROST, seed, false), w, 0.65)
		if age < LIVE_H:
			_live.append(_live_parts(w, seed))


func _mark(mesh: ArrayMesh, w: Dictionary, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _flat_mat()
	mi.material_override = mat
	add_child(mi)
	_marks.append([mi, mat, w, alpha])


static func _flat_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/world/shaders/scar.gdshader")
	return mat


## 일어난 뒤 잠깐 보이는 것: 먼지 구름·깔때기·연기·분출 (움직임은 _update_scars)
func _live_parts(w: Dictionary, seed: float) -> Dictionary:
	var out := {"w": w, "parts": [], "light": null, "seed": seed}
	var kind := String(w["kind"])
	var n := {"meteor": 5, "quake": 6, "dust_devil": 1, "fire": 6, "blowout": 1}.get(kind, 0) as int
	for i in n:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var col: Color = {"meteor": DUST, "quake": DUST, "dust_devil": DUST, "fire": SMOKE, "blowout": FROST}[kind]
		if kind in ["dust_devil", "blowout"]:
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 0.18 if kind == "dust_devil" else 0.12
			cm.height = 1.0
			cm.radial_segments = 20
			cm.cap_top = false
			cm.cap_bottom = false
			mi.mesh = cm
		else:
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.height = 2.0
			sph.radial_segments = 16
			sph.rings = 8
			mi.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		mi.material_override = mat
		add_child(mi)
		out["parts"].append([mi, mat])
	if kind == "fire":
		var glow := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		glow.mesh = sph
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = FIRE
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.material_override = gm
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)
		out["parts"].append([glow, gm])
		var l := OmniLight3D.new()
		l.light_color = FIRE
		l.omni_range = 40.0
		l.shadow_enabled = false
		add_child(l)
		out["light"] = l
	return out


func _update_scars(local: Callable) -> void:
	for m in _marks:
		var w: Dictionary = m[2]
		var k := clampf(1.0 - float(_hour - int(w["hour"])) / MARK_H, 0.0, 1.0)
		(m[0] as MeshInstance3D).visible = k > 0.0
		(m[1] as ShaderMaterial).set_shader_parameter("fade", float(m[3]) * sqrt(k))
		(m[1] as ShaderMaterial).set_shader_parameter("light", 1.0 - 0.75 * night)
	for l in _live:
		var w: Dictionary = l["w"]
		var age := float(_hour - int(w["hour"]))
		var k := clampf(age / LIVE_H, 0.0, 1.0)
		var on := age >= 0.0 and age < LIVE_H
		for p in l["parts"]:
			(p[0] as MeshInstance3D).visible = on
		if l["light"] != null:
			(l["light"] as OmniLight3D).visible = on
		if on:
			_animate(l, w, k, local)


## 흔적 하나의 이번 프레임: k = 일어난 뒤 지난 몫 (0 → 1)
func _animate(l: Dictionary, w: Dictionary, k: float, local: Callable) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var r := float(w["r"])
	var seed: float = l["seed"]
	var parts: Array = l["parts"]
	match String(w["kind"]):
		"meteor":
			# 둘레로 퍼지며 피어올랐다가 가라앉는 먼지
			for i in parts.size():
				var ang := seed + TAU * i / parts.size()
				var spread := r * (0.4 + 1.6 * sqrt(k))
				var p := a + Vector2(cos(ang), sin(ang)) * spread * 0.55
				var s := r * (0.5 + 1.1 * sqrt(k)) * (0.8 + 0.25 * sin(seed + i))
				_place(parts[i], local.call(p, s * 0.45 + r * 0.6 * k * (1.0 - k)), Vector3(s, s * 0.55, s), 0.5 * pow(1.0 - k, 1.5))
		"quake":
			for i in parts.size():
				var f := (float(i) + 0.5) / parts.size()
				var p := a.lerp(b, f)
				var s := 4.0 + 10.0 * sqrt(k)
				_place(parts[i], local.call(p, s * 0.4), Vector3(s, s * 0.45, s), 0.45 * pow(1.0 - minf(k * 2.0, 1.0), 1.3))
		"dust_devil":
			# 지나간 길을 따라 가는 깔때기 (빙빙 돈다) — 길 끝에 닿으면 흩어진다
			var f := minf(k * 1.6, 1.0)
			var p := _devil_path(a, b, r, seed, f)
			var h := r * 6.0
			var fade := (1.0 - pow(f, 6.0)) * minf(k * 20.0, 1.0)
			var mi: MeshInstance3D = parts[0][0]
			mi.transform = Transform3D(Basis(Vector3.UP, _t * 4.0).scaled(Vector3(r * 1.3, h, r * 1.3)),
				local.call(p, h * 0.5))
			(parts[0][1] as StandardMaterial3D).albedo_color = Color(DUST, 0.4 * fade)
		"fire":
			# 오르며 커지는 연기 덩이 (되풀이) · 바닥의 불빛 — 다 꺼질 때까지 줄어든다
			var fade := 1.0 - k
			var n := parts.size() - 1
			for i in n:
				var ph := fmod(_t * 0.18 + float(i) / n, 1.0)
				var s := 3.0 + ph * 11.0
				var drift := Vector2(cos(seed), sin(seed)) * ph * 14.0
				_place(parts[i], local.call(a + drift, 5.0 + ph * 42.0), Vector3.ONE * s, 0.5 * (1.0 - ph) * minf(ph * 6.0, 1.0) * fade)
			var flick := 0.8 + 0.2 * sin(_t * 23.0 + seed) * sin(_t * 7.0)
			var g: Array = parts[n]
			_place(g, local.call(a, 1.5), Vector3.ONE * r * 0.35 * flick * fade, 0.75 * fade)
			var light: OmniLight3D = l["light"]
			light.position = local.call(a, 4.0)
			light.light_energy = 2.5 * flick * fade
		"blowout":
			# 벽의 틈에서 비스듬히 뿜는 하얀 기둥 — 반나절이면 막힌다
			var fade := 1.0 - minf(k * 2.5, 1.0)
			var tilt := Basis(Vector3(cos(seed), 0, sin(seed)), 0.55)
			var h := 16.0 * (0.9 + 0.1 * sin(_t * 17.0))
			var mi: MeshInstance3D = parts[0][0]
			mi.visible = fade > 0.0
			mi.transform = Transform3D(tilt * Basis().scaled(Vector3(4.0, h, 4.0)), local.call(a, 3.0) + tilt * Vector3(0, h * 0.5, 0))
			(parts[0][1] as StandardMaterial3D).albedo_color = Color(FROST, 0.55 * fade)


static func _place(part: Array, at: Vector3, s: Vector3, alpha: float) -> void:
	var mi: MeshInstance3D = part[0]
	mi.visible = alpha > 0.005
	mi.transform = Transform3D(Basis().scaled(s.max(Vector3.ONE * 0.05)), at)
	var mat: StandardMaterial3D = part[1]
	mat.albedo_color = Color(mat.albedo_color, alpha)


## 먼지 회오리가 지나간 길: a → b를 굽이치며 (폭 r 안)
static func _devil_path(a: Vector2, b: Vector2, r: float, seed: float, f: float) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return a.lerp(b, f) + n * sin(f * TAU * 1.3 + seed) * r * 0.5


## 땅을 따라 깐 원판: 가운데가 진하고 둘레로 옅어진다. rays면 분출물처럼 둘레가 들쭉날쭉 뻗는다
static func _disc(local: Callable, c: Vector2, r: float, col: Color, seed: float, rays: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	var rings := 5
	var grid: Array = []
	for k in rings + 1:
		var f := float(k) / rings
		var row: Array = []
		for i in segs:
			var ang := TAU * i / segs
			var wob := 1.0 + 0.12 * sin(ang * 3.0 + seed) + 0.07 * sin(ang * 7.0 + seed * 1.7)
			if rays:
				wob += 0.9 * pow(absf(sin(ang * 4.5 + seed)), 6.0) * f
			var p := c + Vector2(cos(ang), sin(ang)) * r * f * wob
			var al := (1.0 - pow(f, 2.5)) if k < rings else 0.0
			if rays and k > 0:
				al *= 0.3 + 0.7 * pow(absf(sin(ang * 4.5 + seed)), 2.0)
			row.append([local.call(p, 0.3), al])
		grid.append(row)
	for k in rings:
		for i in segs:
			var j := (i + 1) % segs
			var q: Array = [grid[k][i], grid[k + 1][i], grid[k + 1][j], grid[k][i], grid[k + 1][j], grid[k][j]]
			for v in q:
				st.set_normal(Vector3.UP)
				st.set_color(Color(col, float(v[1])))
				st.add_vertex(v[0])
	return st.commit()


## 월진의 금: a → b를 들쭉날쭉 가는 좁은 띠 (곁가지 몇)
static func _crack(local: Callable, a: Vector2, b: Vector2, seed: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed * 1000.0)
	var pts: Array = []
	var n := maxi(int(a.distance_to(b) / 7.0), 4)
	var d := (b - a).normalized()
	var nrm := Vector2(-d.y, d.x)
	for i in n + 1:
		var f := float(i) / n
		var off := 0.0 if i == 0 or i == n else rng.randf_range(-2.6, 2.6)
		pts.append(a.lerp(b, f) + nrm * off)
	_ribbon(st, local, pts, 7.0, EJECTA, 0.3, 0.28)                # 흐트러진 흙 (둘레보다 밝다)
	_ribbon(st, local, pts, 1.6, SOOT, 1.0, 0.34)
	for k in 3:
		var at: Vector2 = pts[rng.randi_range(1, n - 1)]
		var dir := d.rotated(rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0))
		_ribbon(st, local, [at, at + dir * rng.randf_range(10.0, 22.0)], 0.8, SOOT, 0.85, 0.34)
	return st.commit()


## 먼지 회오리가 지나간 자리: 굽이치는 넓은 띠, 가운데 절반이 진하고 가장자리·끝으로 옅어진다
static func _band(local: Callable, a: Vector2, b: Vector2, r: float, seed: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(int(a.distance_to(b) / 8.0), 4)
	var d := (b - a).normalized()
	var nrm := Vector2(-d.y, d.x)
	var rows: Array = []
	for i in n + 1:
		var f := float(i) / n
		var c := _devil_path(a, b, r, seed, f)
		var end := minf(minf(f, 1.0 - f) * 6.0, 1.0)
		rows.append([[local.call(c - nrm * r, 0.3), 0.0], [local.call(c - nrm * r * 0.5, 0.3), end], [local.call(c + nrm * r * 0.5, 0.3), end],
			[local.call(c + nrm * r, 0.3), 0.0]])
	for i in n:
		for s in 3:
			var q: Array = [rows[i][s], rows[i + 1][s], rows[i + 1][s + 1], rows[i][s], rows[i + 1][s + 1], rows[i][s + 1]]
			for v in q:
				st.set_normal(Vector3.UP)
				st.set_color(Color(col, float(v[1])))
				st.add_vertex(v[0])
	return st.commit()


## 점들을 잇는 폭 w의 띠를 땅 위 above m에 (끝으로 갈수록 alpha가 줄어든다)
static func _ribbon(st: SurfaceTool, local: Callable, pts: Array, w: float, col: Color, alpha: float, above: float) -> void:
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var d := (p1 - p0).normalized()
		var nrm := Vector2(-d.y, d.x) * w * 0.5
		var a0 := alpha * (1.0 - 0.6 * float(i) / pts.size())
		var a1 := alpha * (1.0 - 0.6 * float(i + 1) / pts.size())
		var q: Array = [[p0 - nrm, a0], [p1 - nrm, a1], [p1 + nrm, a1], [p0 - nrm, a0], [p1 + nrm, a1], [p0 + nrm, a0]]
		for v in q:
			st.set_normal(Vector3.UP)
			st.set_color(Color(col, float(v[1])))
			st.add_vertex(local.call(v[0], above))


# ── 둘레 탐사 ───────────────────────────────────────────────────
func _update_explore(plan: CityPlan, colony: Dictionary, local: Callable, delta: float) -> void:
	if colony.is_empty() or colony.get("plan") != plan:
		if _beacons:
			_beacons.visible = false
		if _rover:
			_rover.visible = false
		return
	var st := CityExplore.state(colony)
	var parts := PackedStringArray([str(plan.terrain_rev), str(plan.get_instance_id())])
	for s in st["sites"]:
		parts.append(String(s["state"]))
	var sig := ",".join(parts)
	if sig != _beacon_sig:
		_beacon_sig = sig
		_build_beacons(st, local)
	_beacons.visible = true
	for l in _lamps:
		var blink := 0.35 + 0.65 * absf(sin(_t * 3.0)) if String(l[1]) == "going" else 1.0
		var col: Color = SITE_COLORS.get(String(l[1]), SITE_COLORS["unknown"])
		(l[0] as StandardMaterial3D).albedo_color = Color(col, blink)
	var r := CityExplore.rover_at(colony)
	if r.is_empty():
		if _rover:
			_rover.visible = false
		_rover_p = Vector2.INF
		return
	if _rover == null:
		_rover = MeshInstance3D.new()
		_rover.mesh = ModelLib.mesh("vehicles", "pressurized_rover")
		add_child(_rover)
	var at: Vector2 = r["at"]
	if _rover_p == Vector2.INF or _rover_p.distance_to(at) > 400.0:
		_rover_p = at
	else:
		# 시뮬레이션 시간은 한 시간씩 가므로 화면에서는 부드럽게 따라간다
		_rover_p = _rover_p.move_toward(at, maxf(_rover_p.distance_to(at) * delta * 3.0, delta * 6.0))
	var h: Vector2 = r["heading"]
	_rover.visible = true
	_rover.transform = Transform3D(Basis(Vector3.UP, atan2(h.y, h.x)), local.call(_rover_p, 0.0))


func _build_beacons(st: Dictionary, local: Callable) -> void:
	if _beacons:
		_beacons.queue_free()
	_beacons = Node3D.new()
	add_child(_beacons)
	_lamps.clear()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = STEEL
	steel.roughness = 0.6
	for s in st["sites"]:
		var state := String(s["state"])
		var col: Color = SITE_COLORS.get(state, SITE_COLORS["unknown"])
		var c := CityExplore.site_pos(s)
		var root := Node3D.new()
		root.position = local.call(c, 0.0)
		_beacons.add_child(root)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_band(local, c, 13.0, 16.0, col, root.position)
		var rm := _flat_mat()
		rm.set_shader_parameter("glow", 0.8)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var mast_h := 7.0 if state == "unknown" else 16.0
		var mast := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.3
		cm.height = mast_h
		cm.radial_segments = 8
		mast.mesh = cm
		mast.material_override = steel
		mast.position = Vector3(0, mast_h * 0.5, 0)
		root.add_child(mast)
		var lamp := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.1
		sph.height = 2.2
		lamp.mesh = sph
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = col
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lamp.material_override = lm
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(0, mast_h + 0.9, 0)
		root.add_child(lamp)
		_lamps.append([lm, state])
		if state == "found":
			var flag := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(5.0, 3.0, 0.12)
			flag.mesh = bm
			var fm := StandardMaterial3D.new()
			fm.albedo_color = col
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.material_override = fm
			flag.position = Vector3(2.6, mast_h - 1.7, 0)
			root.add_child(flag)


## 땅을 따라 깐 고리 띠 (root 기준 좌표)
static func _ring_band(local: Callable, c: Vector2, r0: float, r1: float, col: Color, origin: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var q: Array = [c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d0 * r0, c + d1 * r1, c + d1 * r0]
		for p in q:
			st.set_color(Color(col, 0.85))
			st.add_vertex((local.call(p, 0.35) as Vector3) - origin)
	return st.commit()


# ── 화면 위 표시 ────────────────────────────────────────────────
## 탐사지·탐사대 이름표, 탐사대가 가는 길(점선), 막 일어난 재난 (City3D.draw_overlay)
func draw_overlay(view: WorldView, ov: Control, font: Font, plan: CityPlan, colony: Dictionary, local: Callable) -> void:
	if view.cam.dist > 14.0:
		return
	var gx := global_transform
	for w in plan.scars:
		var age := float(_hour - int(w["hour"]))
		if age < 0.0 or age >= LIVE_H or view.cam.dist > 2.5:
			continue                         # 멀리서는 탐사지 이름표만 (도시 가운데에 겹친다)
		var p: Vector2 = ((w["a"] as Vector2) + (w["b"] as Vector2)) * 0.5
		var sp: Variant = view.screen_of(gx * (local.call(p, 34.0) as Vector3))
		if sp != null:
			_tag(ov, font, sp, "재난 · " + String(CityHazards.hazard(String(w["kind"])).get("name", "")), Palette.RED)
	if colony.is_empty() or colony.get("plan") != plan:
		return
	var st := CityExplore.state(colony)
	var trip: Dictionary = st["trip"]
	if not trip.is_empty():
		var hub := plan.hub()
		var site := CityExplore.site_pos(st["sites"][int(trip["site"])])
		var prev: Variant = null
		for k in 33:
			var q: Variant = view.screen_of(gx * (local.call(hub.lerp(site, k / 32.0), 1.0) as Vector3))
			if prev != null and q != null and k % 2 == 1:
				ov.draw_line(prev, q, Color(SITE_COLORS["going"], 0.75), 2.0, true)
			prev = q
		if _rover and _rover.visible:
			var rp: Variant = view.screen_of(gx * (local.call(_rover_p, 9.0) as Vector3))
			if rp != null:
				_tag(ov, font, rp, "탐사대", SITE_COLORS["going"])
	for s in st["sites"]:
		var state := String(s["state"])
		var sp: Variant = view.screen_of(gx * (local.call(CityExplore.site_pos(s), 22.0) as Vector3))
		if sp == null:
			continue
		var text := "? 탐사지"
		if state == "going":
			text = "탐사 중"
		elif state == "found":
			text = "✓ " + String(CityExplore.find(String(s["find"])).get("name", ""))
		_tag(ov, font, sp, text, SITE_COLORS.get(state, SITE_COLORS["unknown"]))


static func _tag(ov: Control, font: Font, at: Vector2, text: String, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var r := Rect2(at + Vector2(-w * 0.5 - 7.0, -22.0), Vector2(w + 14.0, 19.0))
	if not Rect2(Vector2.ZERO, ov.size).intersects(r):
		return
	ov.draw_rect(r, Color(0.05, 0.06, 0.09, 0.8))
	ov.draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), col)
	ov.draw_string(font, r.position + Vector2(8.0, 14.0), I18n.t(text), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.35))
