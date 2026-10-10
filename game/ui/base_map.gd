class_name BaseMap
extends Control
## 기지 지도 — 건물과 탈것을 아이소메트릭으로 그린다 (2.5D, 정사영 30°).
## 해는 지평선을 따라 29.5일에 한 바퀴 돌고, 그림자가 해 반대쪽으로 길게 눕는다.
## 능선 그늘에 들면(시뮬레이션의 어둠) 몸체를 낮추고 창·등만 켠다.
## 끌어서 옮기고, 휠·두 손가락으로 확대한다. 건물을 누르면 정보가 열린다.

signal module_tapped(mid: String)

const NIGHT := Color(0.22, 0.25, 0.36)
const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.4
const VIS_SPEED := [0.0, 1.0, 1.6, 2.4]       # 배속별 탈것 속도 (시간 배속을 그대로 따르면 흐려진다)
const SHADOW_K := 2.4                          # 그림자 길이 = 높이 × K (실제 극지에서는 40배 이상)
const SYNODIC_H := 29.53 * 24.0
const SUN_PHASE := 2.2
const SKY := Color("07090d")
const GROUND_HI := Color("6e675d")             # 능선 비탈 (낮은 해를 받는다)
const GROUND := Color("413d39")
const GROUND_LO := Color("2f2c2a")
const ROAD := Color("57514a")
const ROAD_EDGE := Color("6d665c")

var sim: CitySim
var speed_level := 0
var zoom := 0.55
var center := Vector2.ZERO                     # 화면 가운데에 오는 지도 좌표 (1배 px)
var layout := BaseLayout.new()
var traffic: BaseTraffic
var night_k := 0.0
var sun_dir := Vector2(1, 0)

var _hits: Array = []                          # [PackedVector2Array(지도 px), mid, depth]
var _lights_list: Array = []                   # [Texture2D, Rect2(지도 px)]
var _badges: Array = []                        # [kind, 지도 px 위치, text]
var _hover := ""
var _press := Vector2.ZERO
var _pressed := false
var _dragging := false
var _touches := {}
var _pinch_d := 0.0
var _pinch_zoom := 1.0
var _stars: Array = []
var _craters: Array = []
var _crest := PackedVector2Array()
var _noise: NoiseTexture2D
var _lights: Control
var _hud: Control
var _t := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	traffic = BaseTraffic.new(layout)
	_make_scenery()
	_lights = Control.new()
	_lights.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lights.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = add
	_lights.draw.connect(_draw_lights)
	add_child(_lights)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	resized.connect(_on_resized)
	center = ArtLib.project(layout.hub + Vector3(0, -20, 0))


var _needs_focus := true


func set_sim(new_sim: CitySim) -> void:
	sim = new_sim
	traffic.reset(sim)
	night_k = 1.0 if sim and sim.is_dark() else 0.0
	_needs_focus = true
	if size.x > 0:
		focus_core()


func _on_resized() -> void:
	_lights.size = size
	_hud.size = size
	if _needs_focus and size.x > 0 and sim != null:
		focus_core()
	_clamp()


# ── 풍경 (한 번만 만든다) ─────────────────────────────────────
func _make_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var b := BaseLayout.BOUNDS_UV
	for i in range(160):
		var u := rng.randf_range(b.position.x, b.end.x)
		var v := rng.randf_range(b.position.y, BaseLayout.CREST_V - 8.0)
		_stars.append([Vector2(u * ArtLib.PX_PER_M, v * ArtLib.PX_PER_M * 0.5), rng.randf_range(0.25, 0.9), rng.randf() < 0.1])
	for i in range(int((b.end.x - b.position.x) / 4.0) + 1):
		var u := b.position.x + i * 4.0
		var v := BaseLayout.CREST_V + 5.0 * sin(u * 0.031) + 3.5 * sin(u * 0.083 + 1.3) + 2.0 * sin(u * 0.21)
		v -= 7.0 * exp(-pow(u / 60.0, 2.0))       # 한가운데가 '영원한 빛의 봉우리'
		_crest.append(Vector2(u * ArtLib.PX_PER_M, v * ArtLib.PX_PER_M * 0.5))
	for i in range(90):
		var u := rng.randf_range(b.position.x + 10, b.end.x - 10)
		var v := rng.randf_range(BaseLayout.CREST_V + 30, b.end.y - 10)
		var r := rng.randf_range(2.0, 9.0) if rng.randf() < 0.85 else rng.randf_range(10.0, 18.0)
		_craters.append([BaseLayout.uv_to_xy(Vector2(u, v)), r])
	_noise = NoiseTexture2D.new()
	_noise.width = 256
	_noise.height = 256
	_noise.seamless = true
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.06
	fn.fractal_octaves = 5
	fn.seed = 7
	_noise.noise = fn


# ── 시간 ────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_visible_in_tree() or sim == null:
		return
	_t += delta
	var vis_dt: float = delta * VIS_SPEED[clampi(speed_level, 0, 3)]
	traffic.update(vis_dt, sim, _sites())
	var target := 1.0 if sim.is_dark() else 0.0
	night_k = move_toward(night_k, target, delta / 0.8)
	var phi := TAU * float(sim.hour) / SYNODIC_H + SUN_PHASE
	sun_dir = Vector2(cos(phi), sin(phi))
	queue_redraw()
	_lights.queue_redraw()
	_hud.queue_redraw()


# ── 좌표 ────────────────────────────────────────────────────────
func map_to_screen(mp: Vector2) -> Vector2:
	return (mp - center) * zoom + size * 0.5


func screen_to_map(sp: Vector2) -> Vector2:
	return (sp - size * 0.5) / zoom + center


func _apply_transform(ci: CanvasItem) -> void:
	ci.draw_set_transform(size * 0.5 - center * zoom, 0.0, Vector2(zoom, zoom))


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_map(screen_pos)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	center = before - (screen_pos - size * 0.5) / zoom
	_clamp()


func zoom_by(factor: float) -> void:
	zoom_at(size * 0.5, factor)


func fit() -> void:
	var b := BaseLayout.BOUNDS_UV
	var w := b.size.x * ArtLib.PX_PER_M
	var h := b.size.y * ArtLib.PX_PER_M * 0.5
	zoom = clampf(minf(size.x / w, size.y / h), ZOOM_MIN, ZOOM_MAX)
	center = Vector2(b.get_center().x * ArtLib.PX_PER_M, b.get_center().y * ArtLib.PX_PER_M * 0.5)
	_clamp()


func focus_core() -> void:
	_needs_focus = false
	zoom = 0.6 if size.x >= 900 else 0.42
	center = ArtLib.project(layout.hub + Vector3(-25, -25, 0))
	_clamp()


func _clamp() -> void:
	var b := BaseLayout.BOUNDS_UV
	var lo := Vector2(b.position.x * ArtLib.PX_PER_M, b.position.y * ArtLib.PX_PER_M * 0.5)
	var hi := Vector2(b.end.x * ArtLib.PX_PER_M, b.end.y * ArtLib.PX_PER_M * 0.5)
	var half := size * 0.5 / zoom
	for k in [0, 1]:
		if hi[k] - lo[k] <= half[k] * 2.0:
			center[k] = (lo[k] + hi[k]) * 0.5
		else:
			center[k] = clampf(center[k], lo[k] + half[k], hi[k] - half[k])


# ── 그리기 ──────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SKY)
	if sim == null:
		return
	_apply_transform(self)
	var dim := Color.WHITE.lerp(NIGHT, night_k)
	_draw_sky(dim)
	_draw_ground(dim)
	_draw_roads(dim)
	var items := _collect()
	_draw_shadows(items)
	_hits.clear()
	_lights_list.clear()
	_badges.clear()
	items.sort_custom(func(a, b): return a["depth"] < b["depth"])
	for it in items:
		if it["kind"] == "b":
			_draw_building(it, dim)
		else:
			_draw_agent(it, dim)
	draw_set_transform(Vector2.ZERO)


func _draw_sky(dim: Color) -> void:
	var top := Vector2(BaseLayout.BOUNDS_UV.position.x * ArtLib.PX_PER_M, BaseLayout.BOUNDS_UV.position.y * ArtLib.PX_PER_M * 0.5)
	for s in _stars:
		var c := Color(1, 1, 1, s[1])
		draw_rect(Rect2(s[0], Vector2(2.5, 2.5) if s[2] else Vector2(1.6, 1.6)), c)
	# 지구는 북쪽 지평선 가까이 늘 같은 자리에 떠 있다
	var earth := Vector2(150.0 * ArtLib.PX_PER_M, (BaseLayout.CREST_V - 34.0) * ArtLib.PX_PER_M * 0.5)
	var er := maxf(22.0, 11.0 / zoom)
	draw_circle(earth, er * 1.5, Color(0.35, 0.55, 0.9, 0.12))
	draw_circle(earth, er, Color("2f5d9e"))
	var lit_side := Vector2(-sun_dir.x + sun_dir.y, 0.0).normalized() if absf(sun_dir.x - sun_dir.y) > 0.01 else Vector2.RIGHT
	draw_circle(earth + lit_side * er * 0.2, er * 0.8, Color("a9c8ee"))
	draw_circle(earth + Vector2(-0.2, -0.15) * er, er * 0.3, Color(1, 1, 1, 0.5))
	# 해: 카메라 반대편(지도 위쪽)에 있을 때만 능선 위로 보인다
	var away := (-sun_dir.x - sun_dir.y) * 0.7071
	if away > 0.05 and night_k < 0.95:
		var u := (sun_dir.x - sun_dir.y) * 0.7071 * 215.0
		var p := Vector2(u * ArtLib.PX_PER_M, (BaseLayout.CREST_V - 4.0) * ArtLib.PX_PER_M * 0.5)
		var a := (1.0 - night_k) * clampf(away * 3.0, 0.0, 1.0)
		for k in range(6, 0, -1):
			draw_circle(p, 10.0 + k * 14.0, Color(1.0, 0.82, 0.5, 0.05 * a))
		draw_circle(p, 12.0, Color(1.0, 0.96, 0.85, a))


func _draw_ground(dim: Color) -> void:
	var bottom := BaseLayout.BOUNDS_UV.end.y * ArtLib.PX_PER_M * 0.5 + 40.0
	var slope := 46.0 * ArtLib.PX_PER_M * 0.5
	var hi := GROUND_HI * dim
	var mid := GROUND * dim
	var lo := GROUND_LO * dim
	for i in range(_crest.size() - 1):
		var a := _crest[i]
		var b := _crest[i + 1]
		var a2 := Vector2(a.x, a.y + slope)
		var b2 := Vector2(b.x, b.y + slope)
		draw_polygon(PackedVector2Array([a, b, b2, a2]), PackedColorArray([hi, hi, mid, mid]))
		draw_polygon(PackedVector2Array([a2, b2, Vector2(b.x, bottom), Vector2(a.x, bottom)]),
			PackedColorArray([mid, mid, lo, lo]))
	draw_polyline(_crest, Color(1.0, 0.86, 0.62, 0.55 * (1.0 - night_k)), 2.0)
	# 레골리스 결
	var x0 := _crest[0].x
	var top := BaseLayout.CREST_V * ArtLib.PX_PER_M * 0.5
	draw_texture_rect(_noise, Rect2(Vector2(x0, top), Vector2(_crest[-1].x - x0, bottom - top)), true,
		Color(dim.r, dim.g, dim.b, 0.12))
	# 얼음 분화구 (영구 그늘)
	var ic := ArtLib.project(layout.ice_center)
	var r := BaseLayout.ICE_CRATER_R * ArtLib.PX_PER_M
	_ellipse(ic + Vector2(0, -3), r * 1.08, Color(0.62, 0.58, 0.52, 0.5) * dim)
	_ellipse(ic, r, Color("1b1d22") * dim)
	_ellipse(ic + Vector2(0, 4), r * 0.82, Color("15171b") * dim)
	_ellipse(ic + Vector2(0, 6), r * 0.5, Color(0.55, 0.68, 0.8, 0.12))
	# 작은 분화구
	for c in _craters:
		var p := ArtLib.project(Vector3(c[0].x, c[0].y, 0))
		var rr: float = c[1] * ArtLib.PX_PER_M
		_ellipse(p, rr, Color(0, 0, 0, 0.18))
		_ellipse(p + Vector2(0, rr * 0.08), rr * 0.82, Color(0.06, 0.06, 0.07, 0.22))
		var lit := Vector2(-sun_dir.x + sun_dir.y, -(sun_dir.x + sun_dir.y) * 0.5).normalized()
		_arc(p, rr, lit, Color(1.0, 0.92, 0.78, 0.16 * (1.0 - night_k)))


func _ellipse(c: Vector2, rx: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(28):
		var t := TAU * i / 28.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * rx * 0.5))
	draw_colored_polygon(pts, color)


func _arc(c: Vector2, rx: float, toward: Vector2, color: Color) -> void:
	var a0 := atan2(toward.y * 2.0, toward.x)
	var pts := PackedVector2Array()
	for i in range(9):
		var t := a0 - 1.1 + 2.2 * i / 8.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * rx * 0.5))
	draw_polyline(pts, color, maxf(1.0, rx * 0.12))


func _draw_roads(dim: Color) -> void:
	var w := BaseLayout.ROAD_W * 0.5
	for road in layout.roads:
		for i in range(road.size() - 1):
			var a: Vector3 = road[i]
			var b: Vector3 = road[i + 1]
			var d := (b - a)
			if d.length() < 0.01:
				continue
			var n := Vector3(-d.y, d.x, 0).normalized() * w
			var ext := d.normalized() * w
			var q := PackedVector2Array([ArtLib.project(a - ext + n), ArtLib.project(b + ext + n),
				ArtLib.project(b + ext - n), ArtLib.project(a - ext - n)])
			draw_colored_polygon(q, ROAD * dim)
			draw_line(q[0], q[1], ROAD_EDGE * dim, 1.2)
			draw_line(q[3], q[2], Color(0, 0, 0, 0.25), 1.2)
	_ellipse(ArtLib.project(layout.hub), 7.0 * ArtLib.PX_PER_M, ROAD * dim)


# ── 그릴 것 모으기 ──────────────────────────────────────────────
func _collect() -> Array:
	var items := []
	var queued := {}
	for item in sim.queue:
		var kind: String = item["id"]
		if kind == "regolith_cover" or kind == "robot":
			continue
		queued[kind] = int(queued.get(kind, 0)) + 1
	var kinds := {}
	for kind in sim.counts:
		kinds[kind] = true
	for kind in queued:
		kinds[kind] = true
	for kind in kinds:
		var cap := layout.capacity(kind)
		if cap == 0:
			continue
		var n := int(sim.counts.get(kind, 0))
		var broken := int(sim.broken.get(kind, 0))
		var q := int(queued.get(kind, 0))
		var shown := mini(n, cap)
		for i in range(shown):
			var sprite: String = kind
			if kind == "hab_module" and i < sim.covered_habs:
				sprite = "hab_module_covered"
			var pos := layout.slot(kind, i)
			items.append({"kind": "b", "id": kind, "sprite": sprite, "pos": pos, "depth": pos.x + pos.y,
				"broken": i >= shown - broken, "more": (n - cap) if (i == shown - 1 and n > cap) else 0})
		for k in range(q):
			var i := n + k
			if i >= cap:
				break
			var pos := layout.slot(kind, i)
			var item := _queue_item(kind, k)
			items.append({"kind": "b", "id": kind, "sprite": _scaffold_for(kind), "pos": pos, "depth": pos.x + pos.y,
				"building": true, "progress": item, "broken": false, "more": 0})
	for a in traffic.agents:
		var p: Vector3 = a["pos"]
		items.append({"kind": "v", "agent": a, "pos": p, "depth": p.x + p.y + 0.5})
	return items


func _queue_item(kind: String, k: int) -> float:
	## k번째로 기다리는 같은 종류 공사의 진척 (0~1)
	var seen := 0
	for item in sim.queue:
		if item["id"] != kind:
			continue
		if seen == k:
			var total: float = maxf(1e-6, item["rd_total"])
			return clampf(1.0 - item["rd"] / total, 0.0, 1.0)
		seen += 1
	return 0.0


func _scaffold_for(kind: String) -> String:
	var f := ArtLib.footprint(kind)
	var m := maxf(f.x, f.y)
	if m <= 6.5:
		return "scaffold_s"
	if m <= 11.0:
		return "scaffold_m"
	return "scaffold_l"


func _sites() -> Array:
	## 로봇이 가야 할 곳: 공사 현장(대기열 앞쪽부터)과 고장 난 건물
	var out := []
	if sim == null:
		return out
	var counted := {}
	for item in sim.queue:
		var kind: String = item["id"]
		if kind == "regolith_cover" or kind == "robot":
			continue
		var k := int(counted.get(kind, 0))
		counted[kind] = k + 1
		var i := int(sim.counts.get(kind, 0)) + k
		if i >= layout.capacity(kind):
			continue
		out.append(_site(kind, i, "q%s%d" % [kind, i]))
		if out.size() >= 6:
			break
	for kind in sim.broken:
		var b := int(sim.broken[kind])
		var n := mini(int(sim.counts.get(kind, 0)), layout.capacity(kind))
		for j in range(mini(b, n)):
			out.append(_site(kind, n - 1 - j, "b%s%d" % [kind, j]))
	return out


func _site(kind: String, i: int, key: String) -> Dictionary:
	return {"pos": layout.slot(kind, i), "foot": ArtLib.footprint(kind), "key": key,
		"district": "ridge" if kind == "solar_tower" else layout.district_of.get(kind, "core")}


# ── 그림자 ──────────────────────────────────────────────────────
## 그림자를 드리우는 상자: [중심 x, 중심 y, 가로, 세로, 아래 높이, 위 높이] (m, 건물 원점 기준).
## 적지 않은 건물은 바닥의 80% × 대표 높이 상자 하나로 본다.
const CASTERS := {
	"solar_tower": [[0, 0, 0.7, 0.7, 0, 21], [-0.1, 0.0, 5.8, 1.1, 7, 20.5]],
	"radiator": [[0, 0, 7.4, 0.3, 0, 6.6]],
	"fission_40kw": [[0, 0, 2.6, 2.6, 0, 3.4], [0, 0, 4.6, 4.6, 3.2, 6.4]],
	"comms_center": [[0, 0, 7.0, 5.0, 0, 2.7], [-1.6, -0.9, 4.0, 4.0, 3.0, 9.0]],
}
const NO_SHADOW := ["landing_pad"]          # 바닥에 붙은 것


func _draw_shadows(items: Array) -> void:
	var a := 0.36 * (1.0 - night_k)
	if a <= 0.01:
		return
	var away := Vector2(-sun_dir.x, -sun_dir.y)
	var color := Color(0.02, 0.03, 0.06, a)
	for it in items:
		if it["kind"] != "b":
			continue
		if it["sprite"] in NO_SHADOW:
			continue
		var p: Vector3 = it["pos"]
		var boxes: Array = CASTERS.get(it["sprite"], [])
		if boxes.is_empty():
			var f := ArtLib.footprint(it["sprite"]) * 0.8
			var h := ArtLib.height(it["sprite"]) * (0.5 if it.get("building", false) else 1.0)
			boxes = [[0, 0, f.x, f.y, 0, h]]
		for bx in boxes:
			var c := Vector2(p.x + bx[0], p.y + bx[1])
			var hx: float = bx[2] * 0.5
			var hy: float = bx[3] * 0.5
			var pts := PackedVector2Array()
			for corner in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
				pts.append(c + corner + away * (bx[4] * SHADOW_K))
				pts.append(c + corner + away * (bx[5] * SHADOW_K))
			var hull := Geometry2D.convex_hull(pts)
			var poly := PackedVector2Array()
			for q in hull:
				poly.append(ArtLib.project(Vector3(q.x, q.y, 0)))
			if poly.size() >= 3:
				draw_colored_polygon(poly, color)


# ── 건물 ────────────────────────────────────────────────────────
func _draw_building(it: Dictionary, dim: Color) -> void:
	var info := ArtLib.info("buildings", it["sprite"])
	if info.is_empty():
		return
	var tex := ArtLib.texture(info["file"])
	if tex == null:
		return
	var p: Vector3 = it["pos"]
	var mp := ArtLib.project(p)
	var rect := Rect2(mp - info["anchor"], info["px"])
	var mod := dim
	if it["broken"]:
		mod = dim * Color(0.62, 0.52, 0.5)
	draw_texture_rect(tex, rect, false, mod)
	if info["lights"] and not it["broken"]:
		_lights_list.append([ArtLib.texture(info["file"], true), rect])
	# 누를 자리: 바닥 크기 × 높이의 상자
	var f := ArtLib.footprint(it["sprite"]) * 0.5
	var h := ArtLib.height(it["sprite"])
	var hex := PackedVector2Array([
		ArtLib.project(p + Vector3(-f.x, -f.y, h)), ArtLib.project(p + Vector3(f.x, -f.y, h)),
		ArtLib.project(p + Vector3(f.x, -f.y, 0)), ArtLib.project(p + Vector3(f.x, f.y, 0)),
		ArtLib.project(p + Vector3(-f.x, f.y, 0)), ArtLib.project(p + Vector3(-f.x, f.y, h))])
	_hits.append([hex, it["id"], it["depth"], it.get("building", false), it["broken"]])
	var top := Vector2(rect.get_center().x, rect.position.y + 6.0)
	if it["broken"]:
		_badges.append(["broken", top, "!"])
	if it.get("building", false):
		_badges.append(["progress", Vector2(rect.get_center().x, rect.end.y - 4.0), it["progress"]])
	if it["more"] > 0:
		_badges.append(["more", Vector2(rect.end.x - 6.0, rect.position.y + 10.0), "+%d" % it["more"]])


# ── 탈것 ────────────────────────────────────────────────────────
func _draw_agent(it: Dictionary, dim: Color) -> void:
	var a: Dictionary = it["agent"]
	var info := ArtLib.info("vehicles", a["id"], a["heading"])
	if info.is_empty():
		return
	var tex := ArtLib.texture(info["file"])
	if tex == null:
		return
	var p: Vector3 = a["pos"]
	if p.z > 0.5:
		# 나는 동안: 땅에 그림자
		var g := ArtLib.project(Vector3(p.x, p.y, 0))
		var s := clampf(1.0 - p.z / 200.0, 0.3, 1.0)
		_ellipse(g, 3.4 * ArtLib.PX_PER_M * s, Color(0, 0, 0, 0.35 * s * (1.0 - night_k * 0.5)))
	var mp := ArtLib.project(p)
	var rect := Rect2(mp - info["anchor"], info["px"])
	draw_texture_rect(tex, rect, false, dim)
	if info["lights"]:
		_lights_list.append([ArtLib.texture(info["file"], true), rect])
	if a.get("thrust", false):
		_lights_list.append(["plume", mp, p.z])
	if a["role"] == "robot" and a["state"] == "work":
		_lights_list.append(["spark", mp + Vector2(0, -16), 0.0])


func _draw_lights() -> void:
	if sim == null:
		return
	_apply_transform(_lights)
	var k := night_k
	for item in _lights_list:
		if item[0] is String:
			if item[0] == "plume":
				_plume(item[1], item[2])
			elif item[0] == "spark":
				var flick := 0.5 + 0.5 * sin(_t * 23.0 + item[1].x)
				_lights.draw_circle(item[1] + Vector2(randf_range(-3, 3), randf_range(-3, 3)), 3.0,
					Color(1.0, 0.85, 0.45, 0.8 * flick))
			continue
		if k <= 0.02 or item[0] == null:
			continue
		_lights.draw_texture_rect(item[0], item[1], false, Color(1, 1, 1, k))
	_lights.draw_set_transform(Vector2.ZERO)


func _plume(mp: Vector2, z: float) -> void:
	## 엔진 불꽃: 노즐의 밝은 점과 아래로 퍼지는 빛. 땅에 가까우면 먼지 고리
	var flick := 0.85 + 0.15 * sin(_t * 40.0)
	_lights.draw_circle(mp + Vector2(0, 2), 9.0 * flick, Color(1.0, 0.85, 0.55, 0.9))
	var cone := PackedVector2Array([mp + Vector2(-6, 2), mp + Vector2(6, 2), mp + Vector2(16, 70), mp + Vector2(-16, 70)])
	_lights.draw_colored_polygon(cone, Color(1.0, 0.7, 0.35, 0.28 * flick))
	if z < 25.0:
		var g := mp + Vector2(0, z * ArtLib.C3)
		var spread := (25.0 - z) / 25.0
		for k in range(3):
			var rx := (14.0 + k * 10.0 + spread * 20.0) * ArtLib.PX_PER_M * 0.25
			var pts := PackedVector2Array()
			for i in range(24):
				var t := TAU * i / 24.0
				pts.append(g + Vector2(cos(t) * rx, sin(t) * rx * 0.5))
			pts.append(pts[0])
			_lights.draw_polyline(pts, Color(0.9, 0.85, 0.75, 0.18 * spread), 3.0)


# ── 화면 위 글자 (확대와 상관없이 같은 크기) ─────────────────────
func _draw_hud() -> void:
	if sim == null:
		return
	var font := get_theme_default_font()
	var bold: Font = ThemeFactory.bold if ThemeFactory.bold else font
	for b in _badges:
		var sp := map_to_screen(b[1])
		match b[0]:
			"broken":
				var blink := 0.55 + 0.45 * sin(_t * 6.0)
				_hud.draw_circle(sp, 11.0, Color(0.89, 0.34, 0.18, blink))
				_hud.draw_string(bold, sp + Vector2(-3.5, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			"progress":
				var w := clampf(46.0 * zoom * 2.0, 26.0, 70.0)
				var r := Rect2(sp - Vector2(w * 0.5, 0), Vector2(w, 5))
				_hud.draw_rect(r, Color(0, 0, 0, 0.6))
				_hud.draw_rect(Rect2(r.position, Vector2(w * float(b[2]), 5)), Palette.AMBER)
			"more":
				_hud.draw_string(bold, sp + Vector2(-8, 0), String(b[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Palette.AMBER)
	# 상태 글자 (왼쪽 위)
	var lit := not sim.is_dark()
	var state := "일조 — 태양광 %s kW" % Fmt.n(sim.solar_kw)
	if not lit:
		state = "능선 그늘 — 태양광 0 kW, 축전 %s" % Fmt.pct((sim.battery + sim.rfc) / maxf(1.0, sim.bat_cap + sim.rfc_cap))
	_shadow_text(bold, Vector2(16, 28), "섀클턴 시드 시티", 17, Palette.TEXT)
	_shadow_text(font, Vector2(16, 48), state, 13, Palette.AMBER if lit else Palette.BLUE)
	var warn := ""
	if not sim.pending_storm.is_empty():
		warn = "태양 양성자 폭풍 경보"
	elif sim.rationing:
		warn = "식량 배급 중"
	var brown: float = sim.last_power.get("frac1", 1.0)
	if brown < 1.0:
		warn = "생명유지 감전 %d%%" % int(round(brown * 100))
	if warn != "":
		_shadow_text(bold, Vector2(16, 70), warn, 14, Palette.RED)
	# 가리킨 건물 이름
	if _hover != "":
		for h in _hits:
			if h[1] == _hover:
				var poly := PackedVector2Array()
				for q in h[0]:
					poly.append(map_to_screen(q))
				poly.append(poly[0])
				_hud.draw_polyline(poly, Color(Palette.AMBER, 0.9), 1.5)
				break
		var label := String(sim.M[_hover]["name"]) if sim.M.has(_hover) else _hover
		var mp := get_local_mouse_position()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		_hud.draw_rect(Rect2(mp + Vector2(14, 6), Vector2(w + 14, 22)), Color(0.06, 0.07, 0.1, 0.88))
		_hud.draw_string(font, mp + Vector2(21, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)


func _shadow_text(font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	_hud.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	_hud.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ── 입력 ────────────────────────────────────────────────────────
func pick(screen_pos: Vector2) -> String:
	var mp := screen_to_map(screen_pos)
	var best := ""
	var best_depth := -INF
	for h in _hits:
		if h[2] > best_depth and Geometry2D.is_point_in_polygon(mp, h[0]):
			best = h[1]
			best_depth = h[2]
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_d = (pts[0] as Vector2).distance_to(pts[1])
			_pinch_zoom = zoom
			_dragging = true
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and _pinch_d > 0.0:
			var pts: Array = _touches.values()
			var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			var d := (pts[0] as Vector2).distance_to(pts[1])
			zoom_at(mid, (_pinch_zoom * d / _pinch_d) / zoom)
			accept_event()
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, 1.12)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, 1.0 / 1.12)
				accept_event()
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pressed = true
					_dragging = false
					_press = event.position
				else:
					if _pressed and not _dragging and _touches.size() < 2:
						var mid := pick(event.position)
						if mid != "":
							module_tapped.emit(mid)
					_pressed = false
					_dragging = false
				accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and _touches.size() < 2:
			if not _dragging and event.position.distance_to(_press) > 8.0:
				_dragging = true
			if _dragging:
				center -= event.relative / zoom
				_clamp()
		else:
			var h := pick(event.position)
			if h != _hover:
				_hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
	elif event is InputEventMagnifyGesture:
		if _touches.size() < 2:          # 두 손가락 집기를 직접 처리하는 중이면 겹쳐 적용하지 않는다
			zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		center += event.delta * 12.0 / zoom
		_clamp()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""
