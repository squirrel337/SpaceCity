class_name WorldView
extends Control
## 3D 우주 보기 — 달 남극의 도시에서 달 전체, 지구-달, 태양계, 이웃 별까지 이어서 확대·축소한다.
##
## 크기 차이가 20자리를 넘으므로 (건물 10 m ~ 별 10^17 km) 모든 위치를 배정밀도로 셈한 뒤
## 카메라를 원점에 두고, 가까운 천체(시야의 지평선 안)는 실제 비율대로, 그보다 먼 것은
## 거리의 로그로 줄인 껍질 안에 같은 방향·같은 겉보기 크기로 놓는다 (축척 공간).
## 카메라 중심에서 균일하게 줄이면 화면에 보이는 모습은 그대로이고 깊이만 줄어든다.
##
## 조작: 끌기 = 지면을 잡아 옮기기(멀면 지구본 돌리기), 오른쪽 끌기·두 손가락 비틀기 = 방위·기울기,
## 휠·두 손가락 벌리기 = 확대·축소(커서 쪽으로), 두 번 누르기 = 그곳으로 다가가기, 이름표 누르기 = 날아가기.
##
## 평면도(지도): 같은 장면을 기지 바로 위에서 직교 투영으로 내려다본다 — 길이 화면 축과 나란하다.
## 끌기 = 옮기기, 휠·두 손가락 = 확대·축소. 3D와 같은 모형·땅·그림자를 쓰므로 둘이 늘 맞는다.
## 남극의 해는 지평선에 걸려 있어 그림자가 수백 m라, 평면도에서는 해를 40° 높이로 올려 비춘다 (방위는 그대로).

signal module_tapped(mid: String)
signal focus_changed(id: String)

const BG := Color(0.0, 0.0, 0.0)
const SHELL_K := 0.32               # 먼 천체를 껍질에 줄여 넣는 로그 기울기
const LABEL_FONT := 14
const SKY_STARS := 5200
const VIEW_SPEED := [0.0, 1.0, 1.0, 1.0]
const PLAN_FIT_KM := 0.56           # 평면도 '전체' (계획이 없을 때)
const PLAN_SUN_ELEV_DEG := 40.0     # 평면도의 해 높이
const PLAN_CORE_KM := 0.2           # 평면도 '거주구'
const PLAN_RANGE_KM := 1.6          # 평면도 가운데가 기지에서 벗어날 수 있는 거리

var sim: CitySim
var speed_level := 0
var cam := OrbitCam.new()
var vis_hours := 0.0                 # 행성 자전용 시각 (배속이 빨라도 천천히)
var jd := Astro.J2000
var quality_hi := true

var _vp: SubViewport
var _tex: TextureRect
var _overlay: Control
var _camera: Camera3D
var _sun_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _env: Environment
var _space: Node3D
var _bodies := {}                    # id → {node: MeshInstance3D, mat: ShaderMaterial, radius, ...}
var _sky_stars: MeshInstance3D
var _milky: MeshInstance3D
var _near_stars: MeshInstance3D
var _sun_glow: MeshInstance3D
var _rings: MeshInstance3D
var moon: MoonSurface
var city: City3D

var _frame := {}                     # 이번 프레임의 천체 위치·자세 (id → {center, frame, radius, ...})
var _unit := 1.0                     # 렌더 단위 1 = _unit km
var _local := 1.0                    # 실제 비율로 그리는 거리 (km)
var _near_s := 1.0                   # 가장 가까운 천체의 축척 공간 배율
var _labels: Array = []              # [Rect2, id] — 눌러서 날아가기
var _orbit_cache := {}
var _orbit_jd := -1e9
var _scale_px := 1.0
var _touches := {}
var _press := Vector2.ZERO
var _pressed := false
var _dragging := false
var _drag_button := 0
var _pinch := {}
var _last_click_ms := 0
var _hover_label := ""
var _clock := 0.0
var _ready_done := false
var plan: CityPlan
var tool: PlaceTool
var plan_view := false               # 평면도 (위에서 내려다본 직교 투영)
var _saved_3d := {}                  # 평면도로 바꾸기 전의 3D 시점


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	Astro.load_data()
	quality_hi = not OS.has_feature("mobile")
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X if quality_hi else Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(_vp)
	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tex)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_scene()
	cam.body_info = _info
	cam.terrain = _terrain_km
	cam.focus_changed.connect(func(id): focus_changed.emit(id))
	resized.connect(_on_resized)


func _ready() -> void:
	# 게임을 고르기 전(시작 카드 뒤)에도 기지 위 시점으로
	_update_time(0.0)
	home(false)


func set_sim(new_sim: CitySim, p_plan: CityPlan = null, p_tool: PlaceTool = null) -> void:
	sim = new_sim
	if p_plan == null and sim != null:
		p_plan = CityPlan.create(sim, moon.layout if moon else null)
	plan = p_plan
	tool = p_tool
	if city:
		city.set_sim(sim, plan, tool)
	_update_time(0.0)
	if not _ready_done:
		home(false)
		_ready_done = true


# ── 장면 ────────────────────────────────────────────────────────
func _build_scene() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.32, 0.36, 0.48)
	_env.ambient_light_energy = 0.12
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	we.environment = _env
	_vp.add_child(we)
	_camera = Camera3D.new()
	_camera.fov = OrbitCam.FOV_DEG
	_camera.current = true
	_vp.add_child(_camera)
	_sun_light = DirectionalLight3D.new()
	_sun_light.light_color = Color(1.0, 0.97, 0.92)
	_sun_light.light_energy = 1.6
	_sun_light.shadow_enabled = true
	_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality_hi \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun_light.shadow_bias = 0.04
	_sun_light.shadow_normal_bias = 1.2
	_sun_light.directional_shadow_blend_splits = true
	_vp.add_child(_sun_light)
	# 기지 가까이에서만 켜는 약한 반사광 (레골리스·지구빛) — 그림자 쪽 면도 읽히게
	_fill_light = DirectionalLight3D.new()
	_fill_light.light_color = Color(0.62, 0.7, 0.92)
	_fill_light.light_energy = 0.0
	_fill_light.shadow_enabled = false
	_vp.add_child(_fill_light)
	_space = Node3D.new()
	_vp.add_child(_space)
	_milky = SkyBuilder.milky_way()
	_vp.add_child(_milky)
	_sky_stars = SkyBuilder.sky_stars(SKY_STARS)
	_vp.add_child(_sky_stars)
	_near_stars = SkyBuilder.near_stars(Astro.systems.size())
	_vp.add_child(_near_stars)
	for id in Astro.order:
		_make_body(id)
	_sun_glow = SkyBuilder.glow_sprite()
	_vp.add_child(_sun_glow)
	moon = MoonSurface.new()
	_space.add_child(moon)
	moon.setup(_bodies["moon"]["node"])
	city = City3D.new()
	moon.city_root.add_child(city)
	city.setup(moon)
	city.module_tapped.connect(func(mid): module_tapped.emit(mid))


func _make_body(id: String) -> void:
	var b: Dictionary = Astro.bodies[id]
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var look: String = String(b.get("look", b.get("kind", "rock")))
	var mat: ShaderMaterial
	if id == "sun":
		mi.mesh = SkyBuilder.sphere(48, 24)
		mat = PlanetLook.sun_material()
	elif id == "moon":
		mi.mesh = SkyBuilder.sphere(256, 128)
		mat = null      # MoonSurface가 맡는다
	else:
		var r: float = float(b["radius_km"])
		mi.mesh = SkyBuilder.sphere(96 if r > 2000.0 else 48, 48 if r > 2000.0 else 24)
		mat = PlanetLook.material(id, look)
	if mat:
		mi.material_override = mat
	_space.add_child(mi)
	var entry := {"node": mi, "mat": mat, "radius": float(b["radius_km"]), "look": look}
	if b.has("rings_km"):
		var ring := MeshInstance3D.new()
		ring.mesh = SkyBuilder.ring_mesh(float(b["rings_km"][0]) / float(b["radius_km"]),
			float(b["rings_km"][1]) / float(b["radius_km"]), 160)
		ring.material_override = PlanetLook.ring_material()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(ring)
		entry["ring"] = ring
	_bodies[id] = entry


# ── 천체 정보 (카메라·배치가 함께 쓴다) ──────────────────────────
func _info(id: String) -> Dictionary:
	if _frame.has(id):
		return _frame[id]
	if Astro.bodies.has(id):
		var b: Dictionary = Astro.bodies[id]
		var info := {"center": Astro.position(id, jd), "frame": Astro.frame(id, jd, vis_hours),
			"radius": float(b["radius_km"]), "surface": id != "sun", "chain": _chain(id)}
		if id == "moon":
			info["frame"] = Astro.frame("moon", jd)
		_frame[id] = info
		return info
	for s in Astro.systems:
		if s["id"] == id:
			var info2 := {"center": s["pos"], "frame": Basis(), "radius": 7.0e5 * sqrt(float(s["lum"])) \
				/ pow(float(s["teff"]) / 5772.0, 2.0), "surface": false, "chain": [["sun", float(s["dist_ly"]) * Astro.LY * 0.4,
				float(s["dist_ly"]) * Astro.LY * 4.0]]}
			_frame[id] = info2
			return info2
	return {}


func _chain(id: String) -> Array:
	var b: Dictionary = Astro.bodies[id]
	match id:
		"sun":
			return []
		"moon":
			return [["earth", 1.2e5, 1.6e6], ["sun", 4.0e7, 6.0e8]]
	if b.has("parent"):
		var orbit_r := float(b.get("orbit_km", 4e5))
		var parent_id: String = b["parent"]
		var pa: Dictionary = Astro.bodies[parent_id]
		var a_km := float(pa["elements"][0]) * Astro.AU if pa.has("elements") else Astro.AU
		return [[parent_id, orbit_r * 0.6, orbit_r * 5.0], ["sun", a_km * 0.25, a_km * 3.0]]
	var a := float(b["elements"][0]) * Astro.AU if b.has("elements") else Astro.AU
	return [["sun", a * 0.25, a * 3.0]]


func _terrain_km(id: String, dir_b: Vector3) -> float:
	if id == "moon" and moon:
		return moon.height_km(dir_b)
	return 0.0


# ── 시간 ────────────────────────────────────────────────────────
func _update_time(delta: float) -> void:
	var unix := _idle_unix()
	if sim:
		unix = float(sim.start_unix) + float(sim.hour) * 3600.0
	jd = Astro.jd_from_unix(unix)
	vis_hours += delta * Astro.SPIN_CAP_H * (1.0 if speed_level > 0 else 0.15)


## 게임이 없을 때의 시각: 캠페인 시작일 0시 (UTC)
static func _idle_unix() -> float:
	GameData.load_all()
	var parts := String(GameData.C.get("start", {}).get("date", "2061-01-01")).split("-")
	if parts.size() < 3:
		return 2871763200.0
	return float(Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 0, "minute": 0, "second": 0}))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	_update_time(delta)
	_frame.clear()
	if plan_view:
		_clamp_plan()
	cam.update(delta, jd)
	_place_all()
	if city and sim:
		city.update(delta, speed_level)
	_overlay.queue_redraw()


func _on_resized() -> void:
	_scale_px = get_viewport().get_final_transform().get_scale().x if get_viewport() else 1.0
	_scale_px = clampf(_scale_px, 0.5, 3.0)
	var px := size * _scale_px
	var cap := 2.2e6 if quality_hi else 1.3e6
	if px.x * px.y > cap:
		px *= sqrt(cap / (px.x * px.y))
	_vp.size = Vector2i(maxi(16, int(px.x)), maxi(16, int(px.y)))


func px_scale() -> float:
	return float(_vp.size.x) / maxf(size.x, 1.0)


# ── 배치 (매 프레임) ─────────────────────────────────────────────
## 실제 거리 d(km)를 렌더 거리로: 가까우면 그대로, 멀면 로그로 줄인다
func _compress(d: float) -> float:
	if d <= _local:
		return d
	return _local * (1.0 + SHELL_K * log(d / _local))


## 실제 위치(km) → 렌더 좌표 (카메라 원점, Godot 축: 황도 북쪽 = +Y)
func to_render(p: PackedFloat64Array) -> Vector3:
	var rel := Astro.sub3(p, cam.pos)
	var d := Astro.len3(rel)
	if d <= 0.0:
		return Vector3.ZERO
	var k := _compress(d) / d / _unit
	return Vector3(rel[0] * k, rel[2] * k, -rel[1] * k)


## 천체 하나의 배율 (중심 거리로 정한다 — 그 천체에 딸린 것은 모두 같은 배율)
func body_scale(center: PackedFloat64Array) -> float:
	var d := Astro.len3(Astro.sub3(center, cam.pos))
	return (_compress(d) / d if d > 0.0 else 1.0) / _unit


static func g_vec(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


## 황도 좌표의 기저 → Godot 축의 기저 (모형 좌표도 (x, z, -y) 규칙)
static func g_basis(b: Basis) -> Basis:
	var x := g_vec(b.x)
	var y := g_vec(b.y)
	var z := g_vec(b.z)
	# 몸체 고정 (x, y, z) → 메시 (x, z, -y): 메시의 열 = [몸체 x, 몸체 z, -몸체 y]
	return Basis(x, z, -y)


func _place_all() -> void:
	# 가장 가까운 천체 표면까지의 거리로 근거리 범위·단위를 정한다
	var near_id := cam.focus
	var near_gap := INF
	for id in Astro.order:
		var info := _info(id)
		var gap := Astro.len3(Astro.sub3(info["center"], cam.pos)) - float(info["radius"])
		if gap < near_gap:
			near_gap = gap
			near_id = id
	var near_info := _info(near_id)
	var r: float = near_info["radius"]
	var h := near_gap
	if near_id == "moon" and moon:
		var rel := Astro.sub3(cam.pos, near_info["center"])
		var dir_b: Vector3 = (near_info["frame"] as Basis).inverse() * Astro.vec(Astro.norm3(rel))
		h = Astro.len3(rel) - r - moon.height_km(dir_b)
	h = maxf(h, 0.0015)
	var horizon := sqrt(h * (2.0 * r + h))
	_local = maxf(horizon * 1.25, cam.dist * 3.0)
	# 가장 가까운 천체도 중심이 근거리 범위 밖이면 카메라 쪽으로 줄어든다 — 가까운 면도 그만큼 다가온다
	var d_near := Astro.len3(Astro.sub3(near_info["center"], cam.pos))
	_near_s = _compress(d_near) / d_near if d_near > 0.0 else 1.0
	var near_km := clampf(h * 0.35, 0.0006, 1e30) * _near_s
	# 렌더 단위: 가까운 면까지의 거리 × 0.35가 150 단위가 되게 (기지 가까이서 1 단위 ≈ 1 m — 그림자 계산이 편하다)
	_unit = near_km / 150.0
	_camera.near = 150.0
	_camera.far = _compress(1.0e19) / _unit * 1.05
	if plan_view:
		# 직교 투영: 세로로 plan_km가 보인다. 깊이는 건물 꼭대기 위부터 땅 조금 아래까지만 (깊이 정밀도·그림자)
		var s_km := _near_s / _unit
		_camera.size = cam.plan_km * s_km
		_camera.near = maxf(cam.dist - 0.25, 0.05) * s_km
		_camera.far = (cam.dist + 0.35) * s_km
	_camera.global_transform = Transform3D(g_basis_cam(cam.basis), Vector3.ZERO)
	# 천체
	var sun_c: PackedFloat64Array = _info("sun")["center"]
	for id in Astro.order:
		var e: Dictionary = _bodies[id]
		var info := _info(id)
		var c: PackedFloat64Array = info["center"]
		var s := body_scale(c)
		var node: MeshInstance3D = e["node"]
		var rad: float = info["radius"]
		node.global_transform = Transform3D(g_basis(info["frame"]).scaled(Vector3.ONE * rad * s), to_render(c))
		var mat: ShaderMaterial = e["mat"]
		if mat:
			var sun_dir := g_vec(Astro.vec(Astro.norm3(Astro.sub3(sun_c, c)))) if id != "sun" else Vector3.UP
			mat.set_shader_parameter("sun_dir", sun_dir)
			mat.set_shader_parameter("spin_h", vis_hours)
		if e.has("ring"):
			var rmat: ShaderMaterial = (e["ring"] as MeshInstance3D).material_override
			rmat.set_shader_parameter("sun_dir", g_vec(Astro.vec(Astro.norm3(Astro.sub3(sun_c, c)))))
	_place_sun(sun_c)
	_place_light(near_id, sun_c)
	_place_sky()
	if moon:
		moon.update_frame(self, _info("moon"), sun_c)


static func g_basis_cam(b: Basis) -> Basis:
	return Basis(g_vec(b.x), g_vec(b.y), g_vec(b.z))


func _place_sun(sun_c: PackedFloat64Array) -> void:
	var p := to_render(sun_c)
	var d := Astro.len3(Astro.sub3(sun_c, cam.pos))
	var ang := 695700.0 / maxf(d, 1.0)                  # 겉보기 반지름 (라디안)
	var screen_h := float(_vp.size.y)
	var px_per_rad := screen_h / deg_to_rad(OrbitCam.FOV_DEG)
	var want_px := clampf(ang * px_per_rad * 6.0, 18.0, screen_h * 0.9)
	var r_render := p.length() * want_px / px_per_rad
	_sun_glow.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r_render), p)
	var gm: ShaderMaterial = _sun_glow.material_override
	gm.set_shader_parameter("strength", clampf(1.4 - log(maxf(d / Astro.AU, 1e-3)) / log(10.0) * 0.25, 0.25, 1.6))


func _place_light(near_id: String, sun_c: PackedFloat64Array) -> void:
	var c: PackedFloat64Array = _info(near_id)["center"]
	var dir := g_vec(Astro.vec(Astro.norm3(Astro.sub3(c, sun_c))))    # 빛이 나아가는 방향
	if near_id == "moon" and moon:
		dir = moon.adjust_light(dir, self)
		if plan_view:
			dir = _raise_light(dir, deg_to_rad(PLAN_SUN_ELEV_DEG))
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	_sun_light.global_transform = Transform3D(Basis.looking_at(dir, up), Vector3.ZERO)
	var energy := 1.6
	var near_base := 0.0
	if near_id == "moon" and moon:
		energy *= moon.local_light_factor()
		near_base = moon.near_base_factor()
	_sun_light.light_energy = energy
	var shadow_km := clampf(cam.dist * 5.0, 0.2, 60.0)
	_sun_light.directional_shadow_max_distance = shadow_km * _near_s / _unit
	if plan_view:
		# 평면도: 그림자 한 장을 보이는 상자(건물 꼭대기~땅)에 맞춘다
		_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		_sun_light.directional_shadow_max_distance = _camera.far
	else:
		_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality_hi \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun_light.shadow_enabled = near_base > 0.05 and cam.mode == "body" and not OS.has_environment("WORLD_NO_SHADOW")
	# 반사광: 해의 방위 반대쪽, 높이 25°
	if near_base > 0.01:
		var f: Basis = _info("moon")["frame"]
		var up_r := g_vec(f * moon.site_dir())
		var horiz := (dir - up_r * dir.dot(up_r))
		if horiz.length_squared() > 1e-8:
			var fill_dir := (-horiz.normalized() * cos(deg_to_rad(25.0)) - up_r * sin(deg_to_rad(25.0))).normalized()
			_fill_light.global_transform = Transform3D(Basis.looking_at(fill_dir, up_r if absf(fill_dir.dot(up_r)) < 0.95 else Vector3.RIGHT), Vector3.ZERO)
	_fill_light.light_energy = 0.32 * near_base * (0.35 if energy < 0.5 else 1.0)
	_env.ambient_light_energy = lerpf(0.1, 0.2, near_base)


## 빛의 방위는 두고 높이만 elev_min 이상으로 (평면도)
func _raise_light(dir: Vector3, elev_min: float) -> Vector3:
	var f: Basis = _info("moon")["frame"]
	var up := g_vec(f * moon.site_dir())
	var to_sun := -dir
	var horiz := to_sun - up * to_sun.dot(up)
	if horiz.length_squared() < 1e-10:
		return dir
	var e := maxf(asin(clampf(to_sun.dot(up), -1.0, 1.0)), elev_min)
	return -(horiz.normalized() * cos(e) + up * sin(e)).normalized()


func _place_sky() -> void:
	# 평면도는 땅만 내려다본다 — 하늘(별·은하수·해 번짐)은 끈다
	for n in [_milky, _sky_stars, _near_stars, _sun_glow]:
		(n as Node3D).visible = not plan_view
	if plan_view:
		return
	var r := _camera.far * 0.9
	_milky.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r), Vector3.ZERO)
	_sky_stars.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r * 0.97), Vector3.ZERO)
	# 이웃 별: 실제 3차원 위치, 밝기는 지금 카메라에서의 겉보기 등급
	var pos4 := PackedVector4Array()
	var col4 := PackedVector4Array()
	for s in Astro.systems:
		var p := to_render(s["pos"])
		var d := Astro.len3(Astro.sub3(s["pos"], cam.pos))
		var mag := Astro.apparent_mag(float(s["lum"]), d)
		var col := Astro.star_color(float(s["teff"]))
		pos4.append(Vector4(p.x, p.y, p.z, clampf(4.2 - mag * 0.45, 1.2, 9.0)))
		col4.append(Vector4(col.r, col.g, col.b, clampf((7.5 - mag) / 9.0, 0.06, 1.0)))
	var nm: ShaderMaterial = _near_stars.material_override
	nm.set_shader_parameter("spos", pos4)
	nm.set_shader_parameter("scol", col4)
	nm.set_shader_parameter("count", pos4.size())


# ── 시점 바로가기 ───────────────────────────────────────────────
## 기지 위 (처음 화면)
func home(animate: bool = true) -> void:
	if moon == null:
		return
	if plan_view:
		plan_fit()
		return
	# 해를 등지고 (35° 비껴) 바라본다 — 건물의 해 받는 면이 보이게
	var sun_m := moon.sun_in_site(self)
	var away := Vector3(-sun_m.x, -sun_m.y, 0.0)
	if away.length_squared() < 1e-6:
		away = Vector3(-0.35, -1.0, 0.0)
	away = away.normalized().rotated(Vector3(0, 0, 1), deg_to_rad(35.0))
	var heading := moon.site_frame() * away
	cam.look_at_surface("moon", moon.site_dir(), 0.52, deg_to_rad(60.0), heading)


func show_moon() -> void:
	_go("moon", 1737.4 * 3.2)


func show_earth_moon() -> void:
	cam.fly_to("earth", 1.15e6)


func show_solar_system() -> void:
	cam.fly_to("sun", 1.2e10)


func show_neighbors() -> void:
	cam.fly_to("sun", 22.0 * Astro.LY)


func _go(id: String, d: float) -> void:
	cam.fly_to(id, d)


# ── 평면도 ──────────────────────────────────────────────────────
## 평면도(위에서 내려다본 지도)를 켜고 끈다. 끄면 3D는 평면도에서 보던 곳을 같은 각도로 본다
func set_plan_view(on: bool) -> void:
	if on == plan_view or moon == null:
		return
	plan_view = on
	if on:
		_saved_3d = {"focus": cam.focus, "mode": cam.mode, "fwd": cam.fwd, "tilt": cam.tilt, "dist": cam.dist}
		if cam.focus == "moon" and cam.mode == "body" and cam.dist < 3.0 and not cam.flying():
			# 3D에서 보던 곳을 비슷한 범위로
			var km := clampf(2.0 * cam.dist * tan(deg_to_rad(OrbitCam.FOV_DEG) * 0.5), PLAN_CORE_KM, PLAN_FIT_KM)
			cam.look_plan("moon", Astro.vec(cam.t_dir), _plan_up(), km)
			_clamp_plan()
		else:
			plan_fit()
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	else:
		var center2 := Astro.vec(cam.t_dir)
		cam.plan = false
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		if _saved_3d.get("focus", "") == "moon" and _saved_3d.get("mode", "") == "body" and float(_saved_3d["dist"]) < 3.0:
			cam.look_at_surface("moon", center2, _saved_3d["dist"], _saved_3d["tilt"], _saved_3d["fwd"])
		else:
			home(false)


## 평면도의 화면 위: 기지 모형 좌표의 −y (화면 오른쪽은 −x). 길이 x·y 축을 따르므로 화면 축과 나란해진다
func _plan_up() -> Vector3:
	return moon.site_frame() * Vector3(0.0, -1.0, 0.0)


## 기지 모형 좌표(m) → 달 고정 방향
func _site_point(xy: Vector2) -> Vector3:
	return (moon.site_dir() * MoonSurface.R_KM * 1000.0 + moon.site_frame() * Vector3(xy.x, xy.y, 0.0)).normalized()


## 평면도: 기지 전체 (건물과 길이 모두 들어오게)
func plan_fit() -> void:
	if plan == null or plan.buildings.is_empty():
		plan_look(BaseLayout.uv_to_xy(BaseLayout.BOUNDS_UV.get_center()), PLAN_FIT_KM)
		return
	var box := Rect2(Vector2(plan.buildings[0]["x"], plan.buildings[0]["y"]), Vector2.ZERO)
	for e in plan.buildings:
		box = box.expand(Vector2(e["x"], e["y"]))
	for n in plan.nodes:
		box = box.expand(n)
	box = box.grow(25.0)
	# 화면 가로 = x, 세로 = y
	var aspect := size.x / maxf(size.y, 1.0) if size.y > 0.0 else 1.5
	var km := maxf(box.size.y, box.size.x / maxf(aspect, 0.2)) / 1000.0
	plan_look(box.get_center(), clampf(km, PLAN_CORE_KM, OrbitCam.PLAN_MAX_KM))


## 평면도: 모형 좌표 xy를 가운데에, 세로 view_km
func plan_look(xy: Vector2, view_km: float) -> void:
	if not plan_view:
		set_plan_view(true)
	cam.look_plan("moon", _site_point(xy), _plan_up(), view_km)


## 평면도: 거주 구역
func plan_core() -> void:
	plan_look(BaseLayout.uv_to_xy(BaseLayout.DISTRICTS["core"]["uv"]), PLAN_CORE_KM)


## 평면도 가운데가 기지에서 너무 멀어지지 않게
func _clamp_plan() -> void:
	var site := moon.site_dir()
	var d := Astro.vec(cam.t_dir)
	var lim := PLAN_RANGE_KM / MoonSurface.R_KM
	var ang := site.angle_to(d)
	if ang <= lim:
		return
	var axis := site.cross(d)
	if axis.length_squared() < 1e-20:
		return
	var nd := site.rotated(axis.normalized(), lim)
	cam.t_dir = Astro.dvec(nd)
	cam.fwd = OrbitCam._tangent(nd, cam.fwd)


func zoom_by(k: float) -> void:
	cam.zoom(k)


# ── 입력 ────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_touch_drag(event)
		accept_event()
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()          # 터치는 위에서 직접 처리한다
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.18)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_press = mb.position
				_pressed = true
				_dragging = false
				_drag_button = mb.button_index
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					_zoom_at(mb.position, 0.35)
					_pressed = false
			else:
				if _pressed and not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position, false, mb.shift_pressed)
				elif _pressed and not _dragging and mb.button_index == MOUSE_BUTTON_RIGHT and _tool_on():
					_tool_back()
				_pressed = false
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and _touches.is_empty():
			if not _dragging and mm.position.distance_to(_press) > 4.0:
				_dragging = true
			if _dragging:
				if plan_view or (_drag_button == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_SHIFT)):
					cam.drag(mm.relative.x, mm.relative.y, size.y)
				else:
					cam.rotate_view(mm.relative.x * 0.006, mm.relative.y * 0.006)
		else:
			_hover(mm.position)
		accept_event()
	elif event is InputEventMagnifyGesture and _touches.size() < 2:
		_zoom_at((event as InputEventMagnifyGesture).position, 1.0 / (event as InputEventMagnifyGesture).factor)
		accept_event()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_zoom_at(pg.position, pow(1.08, pg.delta.y))
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed():
		return
	var k := event as InputEventKey
	var step := 40.0
	match k.keycode:
		KEY_LEFT:
			cam.drag(step, 0.0, size.y)
		KEY_RIGHT:
			cam.drag(-step, 0.0, size.y)
		KEY_UP:
			cam.drag(0.0, step, size.y)
		KEY_DOWN:
			cam.drag(0.0, -step, size.y)
		KEY_Q:
			cam.rotate_view(-0.12, 0.0)
		KEY_E:
			cam.rotate_view(0.12, 0.0)
		KEY_PAGEUP:
			cam.rotate_view(0.0, -0.08)
		KEY_PAGEDOWN:
			cam.rotate_view(0.0, 0.08)
		KEY_EQUAL, KEY_KP_ADD:
			cam.zoom(1.0 / 1.4)
		KEY_MINUS, KEY_KP_SUBTRACT:
			cam.zoom(1.4)
		KEY_H, KEY_HOME:
			home()
		_:
			return
	get_viewport().set_input_as_handled()


func _touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			_press = ev.position
			_pressed = true
			_dragging = false
			if ev.double_tap:
				_zoom_at(ev.position, 0.35)
				_pressed = false
		_pinch.clear()
	else:
		if _touches.size() == 1 and _pressed and not _dragging:
			_click(ev.position, true)
		_touches.erase(ev.index)
		_pinch.clear()
		_pressed = false
		_dragging = false


func _touch_drag(ev: InputEventScreenDrag) -> void:
	if not _touches.has(ev.index):
		return
	var prev: Vector2 = _touches[ev.index]
	_touches[ev.index] = ev.position
	if _touches.size() == 1:
		if not _dragging and ev.position.distance_to(_press) > 8.0:
			_dragging = true
		if _dragging:
			cam.drag(ev.position.x - prev.x, ev.position.y - prev.y, size.y)
		return
	var keys := _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var mid := (a + b) * 0.5
	var span := a.distance_to(b)
	var ang := (b - a).angle()
	if not _pinch.is_empty():
		var k: float = float(_pinch["span"]) / maxf(span, 1.0)
		_zoom_at(mid, k)
		var da := wrapf(ang - float(_pinch["ang"]), -PI, PI)
		var dy := mid.y - (_pinch["mid"] as Vector2).y
		cam.rotate_view(-da, dy * 0.006)
	_pinch = {"span": span, "ang": ang, "mid": mid}
	_dragging = true


func _zoom_at(p: Vector2, k: float) -> void:
	var toward := Vector3.ZERO
	if cam.mode == "body" and (k < 1.0 or plan_view):
		var hit := pick_surface(p)
		if hit != Vector3.ZERO:
			toward = hit
	cam.zoom(k, toward)


## 화면 점 → 초점 천체 표면의 방향 (천체 고정 좌표). 없으면 ZERO
func pick_surface(p: Vector2) -> Vector3:
	var info := _info(cam.focus)
	if info.is_empty():
		return Vector3.ZERO
	var vp_pos := p * px_scale()
	var o := _camera.project_ray_origin(vp_pos)
	var dir := _camera.project_ray_normal(vp_pos)
	# 렌더 공간의 구: 중심 to_render(c), 반지름 R × s
	var c := to_render(info["center"])
	var rr: float = float(info["radius"]) * body_scale(info["center"])
	var oc := o - c
	var bq := oc.dot(dir)
	var cq := oc.dot(oc) - rr * rr
	var disc := bq * bq - cq
	if disc < 0.0:
		return Vector3.ZERO
	var t := -bq - sqrt(disc)
	if t < 0.0:
		return Vector3.ZERO
	var hit_r := (o + dir * t - c).normalized()
	# 렌더 축 → 황도 → 몸체 고정
	var ecl := Vector3(hit_r.x, -hit_r.z, hit_r.y)
	return ((info["frame"] as Basis).inverse() * ecl).normalized()


## 자리 고르기 도구가 켜져 있고 기지 가까이에 있나
func _tool_on() -> bool:
	return tool != null and tool.active() and city != null and city.visible_now()


## 오른쪽 클릭: 길을 잇던 중이면 그 줄을 끝내고, 아니면 도구를 끈다
func _tool_back() -> void:
	if tool.mode == "road" and tool.road_from != null:
		tool.end_chain()
	else:
		tool.stop()


## 도구를 쓰려면 기지가 보여야 한다: 멀리 있으면 기지 위로 돌아온다
func ensure_near_base() -> void:
	if plan_view:
		return
	if cam.focus != "moon" or cam.mode != "body" or cam.dist > 3.0:
		home()


func _click(p: Vector2, touch: bool = false, keep: bool = false) -> void:
	if _tool_on():
		var g: Variant = city.ground_at(self, p)
		if g != null:
			if touch:
				tool.tap(g)
			else:
				tool.click(g, keep)
		return
	for item in _labels:
		var rect: Rect2 = item[0]
		if rect.grow(6.0).has_point(p):
			_fly_to_label(item[1])
			return
	if city and city.visible_now():
		var mid := city.pick(self, p)
		if mid != "":
			module_tapped.emit(mid)


func _fly_to_label(id: String) -> void:
	if Astro.bodies.has(id):
		var r: float = float(Astro.bodies[id]["radius_km"])
		if id == "sun":
			cam.fly_to("sun", r * 8.0)
		else:
			var b: Dictionary = Astro.bodies[id]
			var extra := 3.2
			if b.has("rings_km"):
				extra = 6.0
			cam.fly_to(id, r * extra)
	else:
		cam.fly_to(id, 3.0 * Astro.AU)


func _hover(p: Vector2) -> void:
	var over := ""
	for item in _labels:
		if (item[0] as Rect2).grow(6.0).has_point(p):
			over = item[1]
			break
	_hover_label = over
	if _tool_on():
		var g: Variant = city.ground_at(self, p)
		if g != null:
			tool.hover(g)
	if city and city.visible_now():
		city.hover(self, p)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over != "" or (city and city.hovered != "") \
		else Control.CURSOR_ARROW


# ── 화면 위 그리기 (이름표·궤도·축척) ───────────────────────────
## 렌더 좌표 → 이 Control의 좌표. 카메라 뒤면 null
func screen_of(rp: Vector3) -> Variant:
	if _camera.is_position_behind(rp):
		return null
	return _camera.unproject_position(rp) / px_scale()


func _draw_overlay() -> void:
	_labels.clear()
	var font := ThemeFactory.regular if ThemeFactory.regular else get_theme_default_font()
	if not plan_view:
		_draw_orbits()
		var placed: Array = []
		# 태양계 천체
		var order := ["sun", "earth", "moon", "mars", "venus", "mercury", "jupiter", "saturn", "uranus", "neptune",
			"pluto", "io", "europa", "ganymede", "callisto", "titan", "triton", "phobos", "deimos", "charon"]
		for id in order:
			_label_body(id, font, placed)
		# 이웃 별
		if cam.dist > 2.0e9 or not Astro.bodies.has(cam.focus):
			for s in Astro.systems:
				_label_star(s, font, placed)
	if city and city.visible_now():
		city.draw_overlay(self, _overlay, font)
	_draw_readout(font)


func _apparent_px(center: PackedFloat64Array, radius_km: float) -> float:
	var d := Astro.len3(Astro.sub3(center, cam.pos))
	if d <= radius_km:
		return 1e6
	var px_per_rad := size.y / deg_to_rad(OrbitCam.FOV_DEG)
	return asin(clampf(radius_km / d, 0.0, 1.0)) * px_per_rad


func _occluded(p: PackedFloat64Array) -> bool:
	## 가까운 큰 천체(초점) 뒤에 가려졌나
	var info := _info(cam.focus)
	if info.is_empty() or not info.get("surface", true):
		return false
	var c: PackedFloat64Array = info["center"]
	var r: float = info["radius"]
	var dvec := Astro.sub3(p, cam.pos)
	var dl := Astro.len3(dvec)
	var dn := Astro.scale3(dvec, 1.0 / dl)
	var oc := Astro.sub3(cam.pos, c)
	var bq := Astro.dot3(oc, dn)
	var cq := Astro.dot3(oc, oc) - r * r
	var disc := bq * bq - cq
	if disc < 0.0:
		return false
	var t := -bq - sqrt(disc)
	return t > 0.0 and t < dl


func _label_body(id: String, font: Font, placed: Array) -> void:
	var info := _info(id)
	var b: Dictionary = Astro.bodies[id]
	var c: PackedFloat64Array = info["center"]
	if id != cam.focus and _occluded(c):
		return
	var sp: Variant = screen_of(to_render(c))
	if sp == null:
		return
	var pos2: Vector2 = sp
	if not Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(pos2):
		return
	var rad_px := _apparent_px(c, info["radius"])
	var kind: String = String(b.get("kind", "planet"))
	var d_cam := Astro.len3(Astro.sub3(c, cam.pos))
	# 이름을 보일지: 위성은 모행성을 볼 때만, 너무 먼 것은 흐리게
	var alpha := 1.0
	if kind == "moon" and id != "moon":
		var parent_d := Astro.len3(Astro.sub3(_info(b["parent"])["center"], cam.pos))
		alpha = 1.0 - smoothstep(float(b["orbit_km"]) * 30.0, float(b["orbit_km"]) * 90.0, parent_d)
	if id == "moon" and cam.focus == "moon" and cam.dist < 1737.4 * 6.0:
		return
	if id == cam.focus and rad_px > 30.0:
		return
	if d_cam > 3.0e11 and id != "sun":
		alpha *= 1.0 - smoothstep(3.0e11, 2.0e12, d_cam)
	if alpha < 0.05:
		return
	if rad_px < 2.5 and id != "sun":
		var dot_col: Color = PlanetLook.dot_color(id)
		dot_col.a = alpha
		_overlay.draw_circle(pos2, 2.5, dot_col)
	var text: String = String(b["name"])
	var off := Vector2(maxf(rad_px, 4.0) + 6.0, 5.0)
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT)
	var rect := Rect2(pos2 + off - Vector2(0, tsize.y - 3), tsize)
	for other in placed:
		if (other as Rect2).intersects(rect):
			return
	placed.append(rect)
	var col := Color(0.92, 0.9, 0.84, alpha)
	if _hover_label == id:
		col = Color(1.0, 0.8, 0.45, alpha)
	_overlay.draw_string(font, pos2 + off + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT,
		Color(0, 0, 0, 0.7 * alpha))
	_overlay.draw_string(font, pos2 + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, col)
	_labels.append([rect, id])


func _label_star(s: Dictionary, font: Font, placed: Array) -> void:
	var p: PackedFloat64Array = s["pos"]
	var sp: Variant = screen_of(to_render(p))
	if sp == null:
		return
	var pos2: Vector2 = sp
	if not Rect2(Vector2.ZERO, size).has_point(pos2):
		return
	var alpha := smoothstep(2.0e9, 3.0e10, cam.dist)
	if String(s["category"]) == "landmark":
		alpha *= smoothstep(Astro.LY * 2.0, Astro.LY * 40.0, cam.dist)
	elif String(s["category"]) == "notable":
		alpha *= smoothstep(Astro.LY * 0.3, Astro.LY * 6.0, cam.dist)
	if alpha < 0.05:
		return
	var text: String = String(s["name"])
	if cam.dist > Astro.LY * 0.5:
		text += "  %s" % Fmt.light_years(float(s["dist_ly"]))
	var off := Vector2(7, 4)
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT - 1)
	var rect := Rect2(pos2 + off - Vector2(0, tsize.y - 3), tsize)
	for other in placed:
		if (other as Rect2).intersects(rect):
			return
	placed.append(rect)
	var col := Color(0.78, 0.84, 0.95, alpha)
	if _hover_label == s["id"]:
		col = Color(1.0, 0.8, 0.45, alpha)
	_overlay.draw_string(font, pos2 + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT - 1, col)
	_labels.append([rect, s["id"]])


func _draw_orbits() -> void:
	if absf(jd - _orbit_jd) > 5.0:
		_orbit_cache.clear()
		_orbit_jd = jd
	var planets := ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "pluto"]
	var a_sys := smoothstep(1.5e7, 1.2e8, cam.dist)
	for id in planets:
		var col: Color = PlanetLook.dot_color(id)
		var aa := a_sys
		if id in ["uranus", "neptune", "pluto"]:
			aa *= 1.0 - smoothstep(Astro.LY * 0.05, Astro.LY * 0.5, cam.dist)
		else:
			aa *= 1.0 - smoothstep(Astro.LY * 0.002, Astro.LY * 0.05, cam.dist)
		if aa > 0.02:
			_orbit_line(id, Astro.v3(0, 0, 0), Color(col.r, col.g, col.b, 0.42 * aa))
	# 달의 궤도 (지구-달을 볼 때)
	var a_moon := smoothstep(1.5e4, 1.2e5, cam.dist) * (1.0 - smoothstep(2.0e7, 2.0e8, cam.dist))
	if a_moon > 0.02:
		_orbit_line("moon", _info("earth")["center"], Color(0.8, 0.8, 0.78, 0.4 * a_moon))
	# 다른 행성의 위성
	for id in ["io", "europa", "ganymede", "callisto", "titan", "triton", "phobos", "deimos", "charon"]:
		var b: Dictionary = Astro.bodies[id]
		var pc: PackedFloat64Array = _info(b["parent"])["center"]
		var pd := Astro.len3(Astro.sub3(pc, cam.pos))
		var orb := float(b["orbit_km"])
		var am := smoothstep(orb * 0.2, orb * 1.2, pd) * (1.0 - smoothstep(orb * 25.0, orb * 80.0, pd))
		if am > 0.02:
			_orbit_line(id, pc, Color(0.75, 0.78, 0.82, 0.32 * am))


func _orbit_line(id: String, origin: PackedFloat64Array, col: Color) -> void:
	if not _orbit_cache.has(id):
		_orbit_cache[id] = Astro.orbit_points(id, jd, 160 if id in ["moon"] else 256)
	var pts: PackedFloat64Array = _orbit_cache[id]
	var line := PackedVector2Array()
	var n := pts.size() / 3
	for k in n + 1:
		var i := (k % n) * 3
		var p := PackedFloat64Array([origin[0] + pts[i], origin[1] + pts[i + 1], origin[2] + pts[i + 2]])
		var rp := to_render(p)
		if _camera.is_position_behind(rp):
			if line.size() >= 2:
				_overlay.draw_polyline(line, col, 1.2, true)
			line.clear()
			continue
		line.append(_camera.unproject_position(rp) / px_scale())
	if line.size() >= 2:
		_overlay.draw_polyline(line, col, 1.2, true)


func _draw_readout(font: Font) -> void:
	var text := ""
	var info := _info(cam.focus)
	if plan_view:
		_draw_scale_bar(font)
	elif cam.mode == "body" and not info.is_empty():
		var rel := Astro.sub3(cam.pos, info["center"])
		var alt := Astro.len3(rel) - float(info["radius"])
		if cam.focus == "moon" and moon:
			var dir_b: Vector3 = (info["frame"] as Basis).inverse() * Astro.vec(Astro.norm3(rel))
			alt -= moon.height_km(dir_b)
		text = "%s 위 고도 %s" % [String(Astro.bodies[cam.focus]["name"]), Fmt.distance_km(alt)]
	else:
		var name := String(Astro.bodies[cam.focus]["name"]) if Astro.bodies.has(cam.focus) else _star_name(cam.focus)
		text = "%s에서 %s" % [name, Fmt.distance_km(cam.dist)]
	var pos2 := Vector2(14, size.y - 66)
	if text != "":
		_overlay.draw_string(font, pos2 + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.7))
		_overlay.draw_string(font, pos2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.88, 0.92, 0.9))
	var hd := cam.heading_deg()
	if not is_nan(hd):
		# 나침반: 북쪽(N) 화살표
		var c := Vector2(size.x - 34, 34)
		_overlay.draw_circle(c, 18, Color(0, 0, 0, 0.45))
		_overlay.draw_arc(c, 18, 0, TAU, 32, Color(1, 1, 1, 0.35), 1.2, true)
		var a := deg_to_rad(-hd) - PI * 0.5
		var tip := c + Vector2(cos(a), sin(a)) * 14.0
		_overlay.draw_line(c, tip, Color(0.95, 0.45, 0.35), 2.4, true)
		_overlay.draw_string(font, tip + Vector2(-4, -4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))


## 평면도의 축척 막대 (왼쪽 아래)
func _draw_scale_bar(font: Font) -> void:
	var px_per_m := size.y / maxf(cam.plan_km * 1000.0, 1.0)
	var len_m := 10.0
	for m in [10.0, 20.0, 50.0, 100.0, 200.0, 500.0]:
		len_m = m
		if m * px_per_m >= 70.0:
			break
	var w := len_m * px_per_m
	var a := Vector2(16, size.y - 70)
	var ink := Color(0.92, 0.9, 0.84, 0.95)
	_overlay.draw_rect(Rect2(a - Vector2(2, 5), Vector2(w + 4, 9)), Color(0, 0, 0, 0.45))
	_overlay.draw_line(a, a + Vector2(w, 0), ink, 2.0)
	for x in [0.0, w * 0.5, w]:
		_overlay.draw_line(a + Vector2(x, -4), a + Vector2(x, 3), ink, 1.5)
	var label := "%d m" % int(len_m)
	_overlay.draw_string(font, a + Vector2(w + 9, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.7))
	_overlay.draw_string(font, a + Vector2(w + 8, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)


func _star_name(id: String) -> String:
	for s in Astro.systems:
		if s["id"] == id:
			return String(s["name"])
	return id


## 다른 화면에서 쓰는 정보: 지금 보는 범위
func view_scale_text() -> String:
	return Fmt.distance_km(cam.dist)
