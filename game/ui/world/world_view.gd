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
## 식민지: 천체마다 도시가 앉는 땅(SiteGround — 달은 MoonSurface, 다른 천체는 SiteSurface)이 있고,
## 자세한 도시(City3D)는 지금 고른 식민지 하나에만 세운다. 다른 식민지는 행성 단위에서 점과 이름표로만 보이고,
## 점이나 목록에서 고르면 그 도시로 날아가 내려앉는다 — 식민지가 많아도 그리는 양은 도시 하나다.

signal module_tapped(mid: String)
signal focus_changed(id: String)
signal colony_picked(index: int)
signal colony_entered(index: int)          # 고르지 않은 도시 가까이로 직접 줌인했다 — 그 도시를 고른다
signal site_picked(site_id: String)        # 후보 부지의 점을 눌렀다

const BG := Color(0.0, 0.0, 0.0)
const SHELL_K := 0.32               # 먼 천체를 껍질에 줄여 넣는 로그 기울기
const LABEL_FONT := 14
const SKY_STARS := 5200
const VIEW_SPEED := [0.0, 1.0, 1.0, 1.0]

var sim: CitySim
var speed_level := 0
var cam := OrbitCam.new()
var vis_hours := 0.0                 # 행성 자전용 시각 (배속이 빨라도 천천히)
var hour_frac := 0.0                 # 다음 시뮬레이션 시간까지 흐른 몫 (main이 넣는다 — 해가 매끄럽게 움직이게)
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
var body_baker: BodyBaker            # 암석·얼음 천체의 겉모습을 GPU로 굽는다 (가까이 가면 더 곱게)
var city: City3D                     # 지금 고른 식민지의 자세한 도시 (하나뿐)
var ground: SiteGround               # 그 도시가 앉은 땅
var grounds := {}                    # 부지 id → SiteGround (달 섀클턴은 늘, 다른 부지는 처음 고를 때 만든다)
var colonies: Array = []             # [{name, site, body, dir: 몸체 고정 Vector3, pop, active, candidate?, transit?}] — 점과 이름표
var _fine_sphere := {}               # 천체 id → 지형 조각과 맞닿게 구 메시를 곱게 바꿨나
var _sphere_touched := {}            # ShaderMaterial → true: 고른 도시 둘레의 빛·연무·구멍을 넣은 천체 구
var _descent := {}                   # 식민지로 날아간 뒤 내려앉기
var _enter_cool := 0.0

var _frame := {}                     # 이번 프레임의 천체 위치·자세 (id → {center, frame, radius, ...})
var _unit := 1.0                     # 렌더 단위 1 = _unit km
var _local := 1.0                    # 실제 비율로 그리는 거리 (km)
var _near_s := 1.0                   # 가장 가까운 천체의 축척 공간 배율
var _labels: Array = []              # [Rect2, id] — 눌러서 날아가기
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
var mgr: Colonies                    # 모든 도시와 교통 (노선·탈것을 그린다)
var routes: RouteOverlay
var routes3d: RouteMeshes            # 천체 위 노선과 탈것 (GPU)
var orbits: OrbitLines               # 행성·위성의 궤도선 (GPU)
var galaxy: GalaxyView               # 우리 은하 전체 ('우주' 고정점)
var _galaxy_k := 0.0                 # 은하가 보이는 정도 (해에서 수백 광년 넘게 멀어질 때)
var anchors: CamAnchors              # 카메라의 고정점 (경로·고르기)
var _ship_model: MeshInstance3D      # 따라가는 수송선의 3D 모형
var perf := {}                       # 이번 프레임의 CPU 시간 (μs): place·city·overlay·routes — 성능 측정용
var _fq_t := 0.0                     # 자동 품질: 재는 구간의 시간·프레임 수, 느린 구간이 이어진 수
var _fq_n := 0
var _fq_slow := 0
var _fq_fast := 0
var metro_grounds := {}              # 대도시 key → {ground: SiteSurface, city: MetroCity, used} (가까이 갈 때 만든다, 둘까지)
var _metro_near: SiteSurface         # 카메라가 내려다보는 대도시의 땅 (없으면 null)


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	Astro.load_data()
	quality_hi = Settings.level() in ["high", "ultra"]
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = _msaa_of(int(Settings.q("msaa")))
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
	routes = RouteOverlay.new(self)
	anchors = CamAnchors.new(self)
	_build_scene()
	cam.body_info = _info
	cam.terrain = _terrain_km
	cam.focus_changed.connect(func(id): focus_changed.emit(id))
	resized.connect(_on_resized)


func _ready() -> void:
	# 게임을 고르기 전(시작 카드 뒤)에도 기지 위 시점으로
	_update_time(0.0)
	home(false)
	apply_settings()


static func _msaa_of(n: int) -> Viewport.MSAA:
	return {2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(n, Viewport.MSAA_DISABLED)


## 설정을 3D 화면에 적용한다 (품질 단계, 지도 표시). 지형 격자·굽기 해상도는 다음에 땅을 만들 때 쓴다
func apply_settings() -> void:
	quality_hi = Settings.level() in ["high", "ultra"]
	_vp.msaa_3d = _msaa_of(int(Settings.q("msaa")))
	var splits := int(Settings.q("shadow_splits"))
	if _sun_light:
		_sun_light.shadow_enabled = splits > 0
		_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if splits >= 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(int(Settings.q("shadow_size")), true)
	routes.show = Settings.show_routes()
	cam.lock = not bool(Settings.value("camera/auto_parent", false))
	_on_resized()


func set_sim(new_sim: CitySim, p_plan: CityPlan = null, p_tool: PlaceTool = null) -> void:
	sim = new_sim
	var g := ground_for(sim.site_id if sim != null else GameData.HOME_SITE)
	if p_plan == null and sim != null:
		p_plan = CityPlan.create(sim, g.layout)
	plan = p_plan
	tool = p_tool
	if g != ground or city == null:
		_mount_city(g)
	city.transport = mgr.transport if mgr != null else null
	city.site_key = sim.site_id if sim != null else ""
	city.set_sim(sim, plan, tool)
	_update_time(0.0)
	if not _ready_done:
		home(false)
		_ready_done = true


## 부지의 땅 (없으면 만든다). 도시마다 제 땅이 있고, 자세한 지형 조각은 고른 도시의 것만 그린다
func ground_for(site_id: String) -> SiteGround:
	if grounds.has(site_id):
		return grounds[site_id]
	var site := GameData.site(site_id)
	var body := String(site.get("body", "moon"))
	if site_id == GameData.HOME_SITE or site.is_empty() or not _bodies.has(body):
		return moon
	var node: MeshInstance3D = _bodies[body]["node"]
	if not _fine_sphere.has(body) and body != "moon":
		node.mesh = SkyBuilder.sphere(256, 128)          # 지형 조각과 맞닿게 구를 곱게
		_fine_sphere[body] = true
	var g := SiteSurface.new()
	_space.add_child(g)
	g.setup(body, site, node, float(_bodies[body]["radius"]), body_baker, moon)
	grounds[site_id] = g
	return g


## 그 천체에서 지형을 그리는 땅: 지구의 대도시 위면 그 땅, 고른 도시의 땅이 그 천체에 있으면 그것, 달이면 섀클턴, 아니면 없다
func _ground_on(body: String) -> SiteGround:
	if body == "earth" and _metro_near != null:
		var t := Astro.vec(cam.t_dir)
		if _metro_near.covers(t) and not (ground != null and ground.body == "earth" and ground.covers(t)):
			return _metro_near
	if ground != null and ground.body == body:
		return ground
	if body == "moon":
		return moon
	return null


## 자세한 도시를 이 땅에 세운다 (다른 땅의 도시는 없앤다)
func _mount_city(g: SiteGround) -> void:
	if city != null:
		city.get_parent().remove_child(city)
		city.queue_free()
		city = null
	for k in grounds:
		(grounds[k] as SiteGround).active = grounds[k] == g
	ground = g
	city = City3D.new()
	g.city_root.add_child(city)
	city.setup(g)
	city.module_tapped.connect(func(mid): module_tapped.emit(mid))


## 행성 단위의 점과 이름표 (main이 식민지가 바뀔 때마다 넣는다)
func set_colonies(list: Array) -> void:
	colonies = list


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
	_sun_light.shadow_enabled = int(Settings.q("shadow_splits")) > 0
	_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(Settings.q("shadow_splits")) >= 4 \
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
	body_baker = BodyBaker.new()
	_space.add_child(body_baker)
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
	routes3d = RouteMeshes.new(self)
	_space.add_child(routes3d)
	orbits = OrbitLines.new(self)
	_space.add_child(orbits)
	galaxy = GalaxyView.new()
	_space.add_child(galaxy)
	moon = MoonSurface.new()
	_space.add_child(moon)
	moon.setup(_bodies["moon"]["node"])
	grounds[GameData.HOME_SITE] = moon
	_mount_city(moon)


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
		mat = PlanetLook.material(id, look)
		if BodySurface.has_body(id):
			# 구운 지도로 그리는 천체: 가까이서도 둥근 윤곽이 보이게 곱게
			mi.mesh = SkyBuilder.sphere(192, 96)
			_fine_sphere[id] = true
			body_baker.add(id, mat, r)
		else:
			mi.mesh = SkyBuilder.sphere(96 if r > 2000.0 else 48, 48 if r > 2000.0 else 24)
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
		var info := {"center": Astro.position(id, jd), "frame": Astro.frame(id, jd, _spin_hours(id)),
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
	if id == "galaxy" and galaxy != null:
		var gi := galaxy.info()
		_frame[id] = gi
		return gi
	return {}


## 천체의 자전 시각 (Astro.frame에 넣는 시). 멀리서는 보기 좋은 속도로 돌고,
## 고른 식민지가 있는 천체에 다가가면 그 도시의 낮밤(시뮬레이션)에 해의 위치가 맞도록 자전 각을 옮긴다
func _spin_hours(id: String) -> float:
	var b: Dictionary = Astro.bodies[id]
	var rot := float(b.get("rot_h", 0.0))
	if id == "earth" and rot != 0.0 and not (ground is SiteSurface and ground.body == "earth"):
		# 지구에 고른 도시가 없으면: 가까이 갈수록 실제 항성시 (대도시의 낮밤이 게임 시각의 그 도시 시각과 맞는다)
		var alt_e := _cam_alt(id)
		var ke := 1.0 - smoothstep(4.0 * float(b["radius_km"]), 12.0 * float(b["radius_km"]), alt_e)
		var g_vis0 := deg_to_rad(280.46061837 + 360.98564736629 * vis_hours / 24.0)
		var g_real := deg_to_rad(280.46061837 + 360.98564736629 * (jd - Astro.J2000))
		var g0 := g_vis0 + wrapf(g_real - g_vis0, -PI, PI) * ke
		return (rad_to_deg(g0) - 280.46061837) / 360.98564736629 * 24.0
	if rot == 0.0 or sim == null or ground == null or ground.body != id or not (ground is SiteSurface):
		return vis_hours
	var il: Dictionary = sim.C["illumination"]
	if String(il.get("model", "")) != "rotation":
		return vis_hours
	var pole: Vector3 = Astro.vec(b.get("pole_ecl", Astro.v3(0, 0, 1)))
	if id == "earth":
		pole = Astro.vec(Astro.eq_to_ecl(Astro.v3(0, 0, 1)))
	var node := Vector3(0, 0, 1).cross(pole)
	if node.length_squared() < 1e-8:
		node = Vector3(1, 0, 0)
	node = node.normalized()
	var c := Astro.position(id, jd)
	var to_sun := Astro.vec(Astro.norm3(Astro.sub3(Astro.position("sun", jd), c)))
	var sun_az := atan2(to_sun.dot(pole.cross(node)), to_sun.dot(node))
	var site := ground.site_dir()
	var site_lon := atan2(site.y, site.x)
	# 시뮬레이션의 하루: 위상 0에서 해가 뜨고 light_frac에서 진다 → 그 부지의 실제 해돋이·해넘이 시간각에 맞춘다
	# (해의 적위와 부지의 위도로: cos H0 = −tan φ · tan δ)
	var light := clampf(float(il.get("light_frac", 0.5)), 0.05, 0.95)
	var ph := fposmod((float(sim.hour) + hour_frac) / float(il["day_h"]) + 0.02, 1.0)
	var decl := asin(clampf(to_sun.dot(pole), -1.0, 1.0))
	var lat := asin(clampf(site.z, -1.0, 1.0))
	var h0 := acos(clampf(-tan(lat) * tan(decl), -0.94, 0.94))
	var hour_angle := -h0 + 2.0 * h0 * ph / light if ph < light \
		else h0 + (TAU - 2.0 * h0) * (ph - light) / (1.0 - light)
	var r := float(b["radius_km"])
	var alt := _cam_alt(id)
	var k := 1.0 - smoothstep(4.0 * r, 12.0 * r, alt)      # 행성 단위(반지름의 몇 배)로 다가오면 그 도시의 시각
	if id == "earth":
		# 지구는 항성시로 돈다 (Astro.frame): 그 도시의 시간각 = 지방 항성시 − 해의 적경이 되게 그리니치 항성시를 맞춘다
		var cs := cos(Astro.OBLIQ)
		var sn := sin(Astro.OBLIQ)
		var se := Vector3(to_sun.x, to_sun.y * cs - to_sun.z * sn, to_sun.y * sn + to_sun.z * cs)
		var g_sim := hour_angle + atan2(se.y, se.x) - site_lon
		var g_vis := deg_to_rad(280.46061837 + 360.98564736629 * vis_hours / 24.0)
		var g := g_vis + wrapf(g_sim - g_vis, -PI, PI) * k
		return (rad_to_deg(g) - 280.46061837) / 360.98564736629 * 24.0
	var w_sim := hour_angle + sun_az - site_lon
	var w_vis := TAU * fposmod(vis_hours / rot, 1.0)
	return rot * (w_vis + wrapf(w_sim - w_vis, -PI, PI) * k) / TAU


## 카메라가 그 천체에서 떨어진 거리 (km, 겉면 위). 그 천체를 보고 있으면 카메라의 거리로 — 시간이 한꺼번에 흘러
## 천체가 궤도를 따라 옮겨 가도 (지난 프레임의 카메라 위치와 어긋나도) 흔들리지 않게
func _cam_alt(id: String) -> float:
	if cam.focus == id and cam.mode == "body" and not cam.flying():
		return cam.dist
	var b: Dictionary = Astro.bodies[id]
	return Astro.len3(Astro.sub3(cam.pos, Astro.position(id, jd))) - float(b["radius_km"])


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


## 천체 고정 방향의 지형 높이 (km): 그 자리를 덮는 땅(고른 도시의 지형 조각, 달 남극)이 있으면 그 값
func _terrain_km(id: String, dir_b: Vector3) -> float:
	if ground != null and ground.body == id and ground.covers(dir_b):
		return ground.height_km(dir_b)
	if id == "earth" and _metro_near != null and _metro_near.covers(dir_b):
		return _metro_near.height_km(dir_b)
	if id == "moon" and moon:
		return moon.height_km(dir_b)
	return 0.0


# ── 시간 ────────────────────────────────────────────────────────
func _update_time(delta: float) -> void:
	var unix := _idle_unix()
	if sim:
		unix = float(sim.start_unix) + (float(sim.hour) + hour_frac) * 3600.0
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
	var t0 := Time.get_ticks_usec()
	_clock += delta
	_update_time(delta)
	_frame.clear()
	cam.update(delta, jd)
	_step_descent(delta)
	_check_enter(delta)
	_place_all()
	var t1 := Time.get_ticks_usec()
	if city and sim:
		city.update(delta, speed_level)
	_overlay.queue_redraw()
	_auto_quality(delta)
	var t2 := Time.get_ticks_usec()
	perf["place_us"] = t1 - t0
	perf["city_us"] = t2 - t1


func _on_resized() -> void:
	_scale_px = get_viewport().get_final_transform().get_scale().x if get_viewport() else 1.0
	_scale_px = clampf(_scale_px, 0.5, 3.0)
	var px := size * _scale_px
	var cap := float(Settings.q("render_px"))
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
	_update_metros()
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
	if _ground_on(near_id) != null:
		var rel := Astro.sub3(cam.pos, near_info["center"])
		var dir_b: Vector3 = (near_info["frame"] as Basis).inverse() * Astro.vec(Astro.norm3(rel))
		h = Astro.len3(rel) - r - _terrain_km(near_id, dir_b)
	# 따라가는 수송선이 천체보다 가까우면 그 배가 가장 가까운 것 (근평면에 잘리지 않게, 축척 공간 밖으로 줄이지 않게)
	var ship_near := cam.track.is_valid() and cam.dist * 0.6 < h
	if ship_near:
		h = cam.dist * 0.6
		r = 0.0
	h = maxf(h, 0.0015)
	var horizon := sqrt(h * (2.0 * r + h))
	_local = maxf(horizon * 1.25, cam.dist * 3.0)
	# 가장 가까운 천체도 중심이 근거리 범위 밖이면 카메라 쪽으로 줄어든다 — 가까운 면도 그만큼 다가온다
	var d_near := Astro.len3(Astro.sub3(near_info["center"], cam.pos))
	_near_s = _compress(d_near) / d_near if d_near > 0.0 and not ship_near else 1.0
	var near_km := clampf(h * 0.35, 0.0006, 1e30) * _near_s
	# 렌더 단위: 가까운 면까지의 거리 × 0.35가 150 단위가 되게 (기지 가까이서 1 단위 ≈ 1 m — 그림자 계산이 편하다)
	_unit = near_km / 150.0
	_camera.near = 150.0
	_camera.far = _compress(1.0e19) / _unit * 1.05
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
			if id == "earth":
				# 지구의 구름은 땅 가까이서 옅어진다 (도시와 해안이 보이게)
				var alt_e := Astro.len3(Astro.sub3(c, cam.pos)) - rad
				mat.set_shader_parameter("cloud_k", smoothstep(120.0, 900.0, alt_e))
			if body_baker.has(id):
				var bs: BodySurface = body_baker.surfaces[id]
				if bs.veil.r + bs.veil.g + bs.veil.b > 0.0:
					# 짙은 대기(타이탄): 멀리서는 땅이 연무 뒤로 흐릿하고, 내려갈수록 또렷하다
					var alt := Astro.len3(Astro.sub3(c, cam.pos)) - rad
					mat.set_shader_parameter("veil", Color(bs.veil.r, bs.veil.g, bs.veil.b, 0.72 * smoothstep(150.0, 3000.0, alt)))
		if e.has("ring"):
			var rmat: ShaderMaterial = (e["ring"] as MeshInstance3D).material_override
			rmat.set_shader_parameter("sun_dir", g_vec(Astro.vec(Astro.norm3(Astro.sub3(sun_c, c)))))
	# 가까운 천체는 겉모습 지도를 더 곱게 굽는다
	body_baker.update_near(near_id, (near_gap + r) / r)
	_place_sun(sun_c)
	_place_light(near_id, sun_c)
	_place_sky()
	for k in grounds:
		var gk: SiteGround = grounds[k]
		gk.update_frame(self, _info(gk.body), sun_c)
	for k in metro_grounds:
		var me: Dictionary = metro_grounds[k]
		(me["ground"] as SiteSurface).update_frame(self, _info("earth"), sun_c)
		(me["city"] as MetroCity).update(self)
	routes3d.update()
	orbits.update()
	_galaxy_k = galaxy.place(self)
	_place_ship_model()


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
	var g: SiteGround = _ground_on(near_id)
	if g:
		dir = g.adjust_light(dir, self)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	_sun_light.global_transform = Transform3D(Basis.looking_at(dir, up), Vector3.ZERO)
	var energy := 1.6
	var near_base := 0.0
	if g:
		energy *= g.local_light_factor()
		near_base = g.near_base_factor()
	_sun_light.light_energy = energy
	var shadow_km := clampf(cam.dist * 5.0, 0.2, 60.0)
	_sun_light.directional_shadow_max_distance = shadow_km * _near_s / _unit
	_sun_light.shadow_enabled = near_base > 0.05 and cam.mode == "body" and int(Settings.q("shadow_splits")) > 0 \
		and not OS.has_environment("WORLD_NO_SHADOW")
	# 반사광: 해의 방위 반대쪽, 높이 25°
	if near_base > 0.01:
		var f: Basis = _info(near_id)["frame"]
		var up_r := g_vec(f * g.site_dir())
		var horiz := (dir - up_r * dir.dot(up_r))
		if horiz.length_squared() > 1e-8:
			var fill_dir := (-horiz.normalized() * cos(deg_to_rad(25.0)) - up_r * sin(deg_to_rad(25.0))).normalized()
			_fill_light.global_transform = Transform3D(Basis.looking_at(fill_dir, up_r if absf(fill_dir.dot(up_r)) < 0.95 else Vector3.RIGHT), Vector3.ZERO)
	_fill_light.light_energy = 0.32 * near_base * (0.35 if energy < 0.5 else 1.0)
	_env.ambient_light_energy = lerpf(0.1, 0.2, near_base)
	# 고른 도시가 다른 천체에 있으면 그 구도 땅 조각과 같은 빛을 받는다
	# (가까이서는 올린 해, 그 땅의 밤이면 어둡게, 주변광·반사광까지). 고르지 않은 천체의 구는 기본값으로
	var now := {}
	var sg := ground as SiteSurface
	if g is SiteSurface and (g as SiteSurface).standalone:
		sg = g as SiteSurface              # 대도시 위: 지구 구도 그 땅 조각과 같은 빛
	if sg != null and sg.sphere_mat != null:
		# 지형 조각이 보이는 고도(2500 km 아래)에서는 구도 조각과 같은 햇빛 세기·색
		var near_k := 1.0 - smoothstep(1800.0, 2600.0, sg.cam_alt_km()) if sg.body == near_id else 0.0
		sg.sphere_mat.set_shader_parameter("lit_k", sg.local_light_factor() * lerpf(1.0, 1.6 / 1.75, near_k))
		sg.sphere_mat.set_shader_parameter("rim_k", smoothstep(0.03, 0.4, sg.cam_alt_km() / sg.radius_km()))
		if sg.body == near_id:
			sg.sphere_mat.set_shader_parameter("sun_dir", -dir)
		var amb := Vector3.ZERO
		var fill := Vector3.ZERO
		var sc := Color.WHITE.lerp(_sun_light.light_color.srgb_to_linear(), near_k)
		sg.sphere_mat.set_shader_parameter("sun_col", Vector3(sc.r, sc.g, sc.b))
		if near_k > 0.0:
			var ac := _env.ambient_light_color.srgb_to_linear() * _env.ambient_light_energy * near_k
			amb = Vector3(ac.r, ac.g, ac.b)
			var fc := _fill_light.light_color.srgb_to_linear() * _fill_light.light_energy * near_k
			fill = Vector3(fc.r, fc.g, fc.b)
			sg.sphere_mat.set_shader_parameter("fill_dir", _fill_light.global_transform.basis.z)
		sg.sphere_mat.set_shader_parameter("amb_light", amb)
		sg.sphere_mat.set_shader_parameter("fill_light", fill)
		now[sg.sphere_mat] = true
	for m in _sphere_touched:
		if not now.has(m):
			_reset_sphere(m)
	_sphere_touched = now
	_place_air(g, energy)


## 지구의 대도시: 카메라가 내려다보는 곳(고도 1500 km 아래)에서 가까운 대도시의 땅(지형 조각)과 시가지를 만든다.
## 둘까지 두고 (오래 안 본 것부터 치운다), 지형 조각은 내려다보는 대도시 하나만 그린다
func _update_metros() -> void:
	var near_key := ""
	if cam.mode == "body" and cam.focus == "earth" and _bodies.has("earth"):
		var alt := Astro.len3(Astro.sub3(cam.pos, _info("earth")["center"])) - 6371.0
		if alt < 1500.0:
			var m := Metros.nearest(Astro.vec(cam.t_dir), 250.0)
			if not m.is_empty():
				near_key = String(m["key"])
				if not metro_grounds.has(near_key):
					_make_metro(m)
	_metro_near = null
	for k in metro_grounds:
		var me: Dictionary = metro_grounds[k]
		var g: SiteSurface = me["ground"]
		g.shown = k == near_key
		if g.shown:
			me["used"] = _clock
			_metro_near = g
	if _metro_near == null and _bodies.has("earth"):
		var em: ShaderMaterial = _bodies["earth"]["mat"]
		em.set_shader_parameter("hole2_chord", 0.0)


func _make_metro(m: Dictionary) -> void:
	var node: MeshInstance3D = _bodies["earth"]["node"]
	if not _fine_sphere.has("earth"):
		node.mesh = SkyBuilder.sphere(256, 128)
		_fine_sphere["earth"] = true
	var g := SiteSurface.new()
	g.standalone = true
	_space.add_child(g)
	var site := {"id": String(m["key"]), "name": String(m["name"]), "lat": float(m["lat"]), "lon": float(m["lon"]),
		"layout": "open", "map_half_km": float(m["radius_km"]) + 10.0, "map_range_km": 2.0, "parks_map": true}
	g.setup("earth", site, node, 6371.0, body_baker, moon)
	var mc := MetroCity.new()
	g.city_root.add_child(mc)
	mc.setup(m, g, quality_hi)
	metro_grounds[String(m["key"])] = {"ground": g, "city": mc, "used": _clock}
	while metro_grounds.size() > int(Settings.q("metro_keep")):
		var oldest := ""
		var t := INF
		for k in metro_grounds:
			if float(metro_grounds[k]["used"]) < t and k != String(m["key"]):
				t = float(metro_grounds[k]["used"])
				oldest = k
		if oldest == "":
			break
		(metro_grounds[oldest]["ground"] as SiteSurface).dispose()
		metro_grounds.erase(oldest)


## 고른 도시가 떠난 천체의 구: 땅 둘레 값을 지운다
static func _reset_sphere(m: ShaderMaterial) -> void:
	m.set_shader_parameter("lit_k", 1.0)
	m.set_shader_parameter("rim_k", 1.0)
	m.set_shader_parameter("sun_col", Vector3.ONE)
	m.set_shader_parameter("amb_light", Vector3.ZERO)
	m.set_shader_parameter("fill_light", Vector3.ZERO)
	m.set_shader_parameter("air", Color(0, 0, 0, 0))
	m.set_shader_parameter("hole_chord", 0.0)


## 대기가 있는 천체(화성·타이탄)의 땅 가까이: 낮에는 하늘이 그 색으로 밝고, 먼 땅은 연무에 잠긴다
func _place_air(g: SiteGround, energy: float) -> void:
	var sky := Color(0, 0, 0, 0)
	var k := 0.0
	if g is SiteSurface and cam.mode == "body" and cam.focus == g.body:
		sky = (g as SiteSurface).sky_color()
		k = (1.0 - smoothstep(6.0, 90.0, g.cam_alt_km())) * clampf(energy / 1.6, 0.0, 1.0)
		if (g as SiteSurface).standalone:
			k *= 1.0 - 0.92 * (g as SiteSurface).night_k     # 대도시의 밤: 하늘과 연무가 어둡다
	var sg := ground as SiteSurface
	if sg != null and sg.sphere_mat != null and (sg != g or sky.a <= 0.0 or k <= 0.001):
		sg.sphere_mat.set_shader_parameter("air", Color(0, 0, 0, 0))
	if sky.a <= 0.0 or k <= 0.001:
		_env.background_color = BG
		_env.fog_enabled = false
		_star_gain(1.0)
		return
	# 먼지 폭풍 (고른 식민지): 하늘이 탁해지고 연무가 짙어진다
	var storm := 1.0
	if g.active and sim != null and sim.in_dust_storm():
		storm = 4.0
		sky = sky.darkened(0.25)
	_env.background_color = BG.lerp(sky, k)
	_env.fog_enabled = true
	_env.fog_light_color = sky
	_env.fog_light_energy = k
	# 연무: 실제 거리 약 25 km에서 절반쯤 (렌더 단위로 바꾼다)
	_env.fog_density = 0.028 * storm * (g as SiteSurface).air_density() * _unit / maxf(_near_s, 1e-6) * k
	# 구에도 같은 연무 (행성 셰이더는 장면 연무를 받지 않는다)
	var air := (sky.srgb_to_linear() * k).linear_to_srgb()
	air.a = _env.fog_density
	(g as SiteSurface).sphere_mat.set_shader_parameter("air", air)
	# 낮 하늘에는 별이 보이지 않는다
	_star_gain(1.0 - 0.97 * k)


func _star_gain(v: float) -> void:
	v *= 1.0 - 0.97 * _galaxy_k          # 은하 밖으로 멀어지면 해 둘레의 하늘(별·은하수 띠) 대신 은하 전체가 보인다
	for mi in [_sky_stars, _milky, _near_stars]:
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m:
			m.set_shader_parameter("gain", v)


func _place_sky() -> void:
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
	var g: SiteGround = ground if ground != null else moon
	if g == null:
		return
	_descent.clear()
	cam.look_at_surface(g.body, g.site_dir(), 0.52, deg_to_rad(60.0), _home_heading(g))
	cam.lock = not bool(Settings.value("camera/auto_parent", false))
	anchors.current = anchors.for_ground(g)


## 해를 등지고 (35° 비껴) 바라보는 방향 — 건물의 해 받는 면이 보이게
func _home_heading(g: SiteGround) -> Vector3:
	var sun_m := g.sun_in_site(self)
	var away := Vector3(-sun_m.x, -sun_m.y, 0.0)
	if away.length_squared() < 1e-6:
		away = Vector3(-0.35, -1.0, 0.0)
	away = away.normalized().rotated(Vector3(0, 0, 1), deg_to_rad(35.0))
	return g.site_frame() * away


## 고른 식민지로 날아가 내려앉는다: 멀면 그 천체로 날아가 도시를 마주 본 뒤, 고도를 낮추며 기울인다
func fly_to_colony() -> void:
	var g: SiteGround = ground
	if g == null:
		return
	cam.lock = not bool(Settings.value("camera/auto_parent", false))
	anchors.current = anchors.for_ground(g)
	var r := g.radius_km()
	if cam.focus == g.body and cam.mode == "body" and not cam.flying() and cam.dist < r * 0.5:
		_begin_descent(g)
		return
	cam.fly_to(g.body, r * 3.2, 2.4, g.site_dir())
	_descent = {"wait": true}


## 고르지 않은 식민지 위로 직접 내려가면 (고도 30 km 아래, 도시에서 수십 km 안) 그 도시를 고르게 알린다
func _check_enter(delta: float) -> void:
	_enter_cool = maxf(0.0, _enter_cool - delta)
	if _enter_cool > 0.0 or cam.mode != "body" or cam.flying() or not _descent.is_empty() or cam.dist > 30.0:
		return
	var r := cam.radius_of(cam.focus)
	var t := Astro.vec(cam.t_dir)
	for i in colonies.size():
		var c: Dictionary = colonies[i]
		if c.get("active", false) or c.get("transit", false) or c.get("candidate", false) \
				or String(c.get("body", "")) != cam.focus:
			continue
		var d: Vector3 = c.get("dir", Vector3.ZERO)
		if t.dot(d.normalized()) > cos(minf(80.0 / maxf(r, 1.0), 0.5)):
			_enter_cool = 2.0
			colony_entered.emit(i)
			return


func _begin_descent(g: SiteGround) -> void:
	var d0 := maxf(cam.dist, 1.0)
	cam.look_at_surface(g.body, g.site_dir(), d0, 0.0, _home_heading(g))
	_descent = {"t": 0.0, "d0": d0, "d1": 0.52, "tilt": deg_to_rad(60.0), "body": g.body}


## 천체의 한 점 위로 내려간다 (대도시): 고도 d1 km, 기울기 tilt
func _begin_descent_at(body: String, dir: Vector3, d1: float, tilt: float) -> void:
	var d0 := maxf(cam.dist, d1)
	var north := Vector3(0, 0, 1) - dir * dir.z
	cam.look_at_surface(body, dir, d0, 0.0, north if north.length_squared() > 1e-8 else Vector3(1, 0, 0))
	_descent = {"t": 0.0, "d0": d0, "d1": d1, "tilt": tilt, "body": body}


func _step_descent(delta: float) -> void:
	if _descent.is_empty():
		return
	if _descent.get("wait", false):
		if not cam.flying():
			if _descent.has("dir"):
				_begin_descent_at(String(_descent["body"]), _descent["dir"], float(_descent["d1"]), float(_descent["tilt"]))
			elif ground != null:
				_begin_descent(ground)
		return
	_descent["t"] += delta / 2.2
	var t: float = clampf(_descent["t"], 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	cam.dist = exp(lerpf(log(float(_descent["d0"])), log(float(_descent["d1"])), e))
	cam.tilt = float(_descent["tilt"]) * e * e
	if t >= 1.0:
		_descent.clear()


## 지구의 대도시 위로 날아가 시가지를 비스듬히 내려다본다
func fly_to_metro(key: String) -> void:
	var m := Metros.of(key)
	if m.is_empty():
		return
	var dir: Vector3 = m["dir"]
	var r := 6371.0
	_descent = {"wait": true, "body": "earth", "dir": dir, "d1": maxf(14.0, float(m.get("radius_km", 20.0)) * 0.9),
		"tilt": deg_to_rad(58.0)}
	if cam.focus == "earth" and cam.mode == "body" and not cam.flying() and cam.dist < r * 0.5:
		_begin_descent_at("earth", dir, float(_descent["d1"]), float(_descent["tilt"]))
		return
	cam.fly_to("earth", r * 2.4, 2.4, dir)


## 교통 탭의 '보기': 노선 전체가 보이게 날아가고 잠깐 밝게 그린다
func show_route(id: String) -> void:
	if mgr == null:
		return
	var l := mgr.transport.line_by_id(id)
	if l.is_empty():
		return
	routes.highlight(id)
	_descent.clear()
	match String(l["kind"]):
		"ferry":
			show_earth_moon()
		"ship":
			cam.fly_to("sun", 4.2e8 if String(l["b"]).begins_with("mercury") or String(l["a"]).begins_with("mercury") else 9.0e8)
		_:
			var body := String(l["body"])
			var r := float(Astro.bodies[body]["radius_km"])
			var a := Transport.node_dir(l["a"])
			var b := Transport.node_dir(l["b"])
			var mid := (a + b).normalized() if (a + b).length() > 1e-6 else a
			var span := acos(clampf(a.dot(b), -1.0, 1.0)) * r
			cam.fly_to(body, clampf(span * 1.5 + r * 0.15, r * 0.25, r * 3.2), 2.2, mid)


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
				if _drag_button == MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_SHIFT):
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
		KEY_BACKSPACE:
			anchors.up()
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
	if cam.mode == "body" and k < 1.0:
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
	var body := ground.body if ground != null else "moon"
	if cam.focus != body or cam.mode != "body" or cam.dist > 3.0:
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
			if String(item[1]).begins_with("colony:"):
				colony_picked.emit(int(String(item[1]).substr(7)))
			elif String(item[1]).begins_with("site:"):
				site_picked.emit(String(item[1]).substr(5))
			elif String(item[1]).begins_with("metro:"):
				var key := String(item[1]).substr(6)
				var m := Metros.of(key)
				anchors.go({"kind": "metro", "id": key, "name": String(m.get("name", key)), "body": "earth",
					"dir": m.get("dir", Vector3.ZERO)})
			elif String(item[1]).begins_with("ship:"):
				var key2 := String(item[1]).substr(5)
				for a in anchors.ships():
					if String(a["id"]) == key2:
						anchors.go(a)
			elif Astro.bodies.has(String(item[1])):
				anchors.go(CamAnchors.body(String(item[1])))
			else:
				anchors.go({"kind": "star", "id": String(item[1]), "name": _star_name(String(item[1]))})
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
	var t0 := Time.get_ticks_usec()
	_labels.clear()
	var font := ThemeFactory.regular if ThemeFactory.regular else get_theme_default_font()
	var t1 := Time.get_ticks_usec()
	routes.draw_lines()
	perf["routes_us"] = Time.get_ticks_usec() - t1
	var placed: Array = []
	# 태양계 천체
	# 식민지: 행성 단위에서는 점과 이름만 (자세한 도시는 고른 식민지에 내려앉을 때)
	for i in colonies.size():
		_label_colony(i, font, placed)
	routes.draw_metros(font, placed)
	var order := ["sun", "earth", "moon", "mars", "venus", "mercury", "jupiter", "saturn", "uranus", "neptune",
		"pluto", "ceres", "io", "europa", "ganymede", "callisto", "titan", "triton", "phobos", "deimos", "charon"]
	for id in order:
		_label_body(id, font, placed)
	# 이웃 별 (은하 전체를 볼 때는 해 둘레에 겹치므로 감춘다)
	if (cam.dist > 2.0e9 or not Astro.bodies.has(cam.focus)) and _galaxy_k < 0.3:
		for s in Astro.systems:
			_label_star(s, font, placed)
	if _galaxy_k > 0.3:
		_label_galaxy(font, placed)
	if city and city.visible_now():
		city.draw_overlay(self, _overlay, font)
	_draw_readout(font)
	perf["overlay_us"] = Time.get_ticks_usec() - t0
	if Settings.show_perf():
		_draw_perf(font)


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
	if id == "sun" and _galaxy_k > 0.3:
		text = "태양계 — 우리가 사는 곳 (은하 중심에서 2만 6,670광년)"
	var n_col := 0
	for col_d in colonies:
		if String(col_d.get("body", "")) == id and not col_d.get("candidate", false) and not col_d.get("transit", false):
			n_col += 1
	if n_col > 0 and rad_px < 9.0:
		text += "  · 도시 %d" % n_col
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


## 식민지 하나의 점·이름·인구. 천체 뒤편이면 숨기고, 고른 도시에 내려앉으면 3D 도시에 자리를 내준다
func _label_colony(i: int, font: Font, placed: Array) -> void:
	var col_d: Dictionary = colonies[i]
	var body := String(col_d.get("body", "moon"))
	if not Astro.bodies.has(body):
		return
	var info := _info(body)
	var c: PackedFloat64Array = info["center"]
	var r: float = info["radius"]
	var dir: Vector3 = col_d.get("dir", Vector3(0, 0, -1))
	var h := _terrain_km(body, dir)
	var p := Astro.add3(c, Astro.bmul(info["frame"], Astro.scale3(Astro.dvec(dir), r + h)))
	# 천체 뒤편 (지평선 너머)
	var out := Astro.norm3(Astro.sub3(p, c))
	var to_cam := Astro.sub3(cam.pos, p)
	if Astro.dot3(out, to_cam) < -0.02 * Astro.len3(to_cam):
		return
	if body != cam.focus and _occluded(p):
		return
	var rad_px := _apparent_px(c, r)
	var alpha := smoothstep(3.0, 9.0, rad_px)           # 천체가 점만 할 때는 천체 이름표에 맡긴다
	var active: bool = col_d.get("active", false)
	if active and ground != null and ground.body == body:
		alpha *= smoothstep(20.0, 60.0, ground.cam_alt_km())
	if alpha < 0.05:
		return
	var sp: Variant = screen_of(to_render(p))
	if sp == null:
		return
	var pos2: Vector2 = sp
	if not Rect2(Vector2(-40, -40), size + Vector2(80, 80)).has_point(pos2):
		return
	var id := String(col_d.get("id", "colony:%d" % i))
	var hot := _hover_label == id
	var accent := Color(1.0, 0.72, 0.3) if active else Color(0.55, 0.85, 1.0)
	var candidate: bool = col_d.get("candidate", false)
	if col_d.get("transit", false):
		accent = Color(0.62, 0.66, 0.74)
	if candidate:
		accent = Color(0.7, 0.74, 0.8)
		alpha *= 0.85
	if hot:
		accent = Color(1.0, 0.86, 0.55)
	var text := String(col_d.get("name", ""))
	var sub := String(col_d["sub"]) if col_d.has("sub") else "%s명" % Fmt.n(float(col_d.get("pop", 0)))
	var off := Vector2(12, 5)
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT + 1)
	var ssize := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT - 2)
	var rect := Rect2(pos2 + Vector2(-9, -9), Vector2(maxf(tsize.x, ssize.x) + off.x + 12, 18 + ssize.y + 2))
	for other in placed:
		if (other as Rect2).intersects(rect):
			return
	placed.append(rect)
	if candidate:
		_overlay.draw_arc(pos2, 5.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5 * alpha), 3.0, true)
		_overlay.draw_arc(pos2, 5.0, 0.0, TAU, 20, Color(accent, alpha), 1.4, true)
	else:
		_overlay.draw_circle(pos2, 7.5, Color(0, 0, 0, 0.55 * alpha))
		_overlay.draw_arc(pos2, 7.0, 0.0, TAU, 24, Color(accent, alpha), 2.0, true)
		_overlay.draw_circle(pos2, 3.2, Color(accent, alpha))
	_overlay.draw_string(font, pos2 + off + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT + 1,
		Color(0, 0, 0, 0.75 * alpha))
	_overlay.draw_string(font, pos2 + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT + 1, Color(accent, alpha))
	var sub_at := pos2 + off + Vector2(0, ssize.y + 1)
	_overlay.draw_string(font, sub_at + Vector2(1, 1), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT - 2,
		Color(0, 0, 0, 0.7 * alpha))
	_overlay.draw_string(font, sub_at, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT - 2, Color(0.85, 0.88, 0.92, 0.9 * alpha))
	_labels.append([rect, id])


## 수송선을 고정점으로 따라갈 때: 그 배의 3D 모형 (가까이 — 수백 km 안 — 에서만), 가는 쪽으로 돌린다
func _place_ship_model() -> void:
	var on := cam.track.is_valid() and String(anchors.current.get("kind", "")) == "ship" and cam.dist < 400.0
	if not on:
		if _ship_model:
			_ship_model.visible = false
		return
	if _ship_model == null:
		_ship_model = MeshInstance3D.new()
		_ship_model.mesh = ModelLib.mesh("vehicles", "transport_ship")
		_ship_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_space.add_child(_ship_model)
	var key := String(anchors.current["id"])
	var p: PackedFloat64Array = cam.track.call()
	var ahead := anchors.ship_pos(key, 6.0)
	var fwd := Astro.vec(Astro.norm3(Astro.sub3(ahead, p)))
	if fwd.length_squared() < 0.5:
		fwd = Vector3(1, 0, 0)
	var x := g_vec(fwd).normalized()
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	var d := maxf(Astro.len3(Astro.sub3(p, cam.pos)), 1e-6)
	var sc := _compress(d) / d / _unit * 0.001          # 모형은 미터
	_ship_model.global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * sc), to_render(p))
	_ship_model.visible = true


## 우리 은하 전체를 볼 때: 은하 중심의 이름
func _label_galaxy(font: Font, placed: Array) -> void:
	var sp: Variant = screen_of(to_render(galaxy.center))
	if sp == null:
		return
	var text := "우리 은하 중심 · 궁수자리 A* (블랙홀)"
	var pos2: Vector2 = (sp as Vector2) + Vector2(10, -10)
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT)
	placed.append(Rect2(pos2 - Vector2(0, tsize.y), tsize))
	var a := clampf((_galaxy_k - 0.3) / 0.4, 0.0, 1.0)
	_overlay.draw_string(font, pos2 + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, Color(0, 0, 0, 0.7 * a))
	_overlay.draw_string(font, pos2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, Color(1.0, 0.86, 0.62, a))


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


func _draw_readout(font: Font) -> void:
	var text := ""
	var info := _info(cam.focus)
	if cam.mode == "body" and not info.is_empty() and Astro.bodies.has(cam.focus):
		var rel := Astro.sub3(cam.pos, info["center"])
		var alt := Astro.len3(rel) - float(info["radius"])
		if _ground_on(cam.focus) != null:
			var dir_b: Vector3 = (info["frame"] as Basis).inverse() * Astro.vec(Astro.norm3(rel))
			alt -= _terrain_km(cam.focus, dir_b)
		text = "%s 위 고도 %s" % [String(Astro.bodies[cam.focus]["name"]), Fmt.distance_km(alt)]
	else:
		var name := String(Astro.bodies[cam.focus]["name"]) if Astro.bodies.has(cam.focus) else _star_name(cam.focus)
		if cam.track.is_valid():
			name = "수송선"
		text = "%s에서 %s" % [name, Fmt.distance_km(cam.dist)]
	var pos2 := Vector2(14, size.y - 66)
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


## 성능 표시 (설정): 초당 프레임, 이번 프레임의 CPU 시간(배치·도시·화면 위 그리기), 그리기 호출, 품질 단계
func _draw_perf(font: Font) -> void:
	var fps := Engine.get_frames_per_second()
	var lines := [
		"%d FPS · %s" % [fps, Settings.LEVEL_NAMES[Settings.level()] + (" (자동)" if Settings.preset() == "auto" else "")],
		"배치 %.1f · 도시 %.1f · 화면 %.1f ms" % [float(perf.get("place_us", 0)) / 1000.0, float(perf.get("city_us", 0)) / 1000.0,
			float(perf.get("overlay_us", 0)) / 1000.0],
		"그리기 %d · 물체 %d · 삼각형 %s" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			Fmt.n(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))],
	]
	var y := 64.0
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var p := Vector2(size.x - w - 14.0, y)
		_overlay.draw_rect(Rect2(p - Vector2(6, 13), Vector2(w + 12, 18)), Color(0, 0, 0, 0.55))
		_overlay.draw_string(font, p, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.95, 0.8))
		y += 19.0


## 자동 품질: 2초마다 평균 프레임 시간을 보고, 느린 구간(24 FPS 아래)이 세 번 이어지면 한 단계 내리고,
## 넉넉한 구간(55 FPS 위)이 30초 이어지면 한 단계 올린다
func _auto_quality(delta: float) -> void:
	if Settings.preset() != "auto" or DisplayServer.get_name() == "headless":
		return
	_fq_t += delta
	_fq_n += 1
	if _fq_t < 2.0:
		return
	var avg := _fq_t / maxf(float(_fq_n), 1.0)
	_fq_t = 0.0
	_fq_n = 0
	if cam.flying() or not _descent.is_empty():
		return                  # 날아가는 동안(굽기·짓기)은 세지 않는다
	_fq_slow = _fq_slow + 1 if avg > 1.0 / 24.0 else 0
	_fq_fast = _fq_fast + 1 if avg < 1.0 / 55.0 else 0
	if _fq_slow >= 3:
		_fq_slow = 0
		if Settings.step_auto(-1):
			apply_settings()
	elif _fq_fast >= 15:
		_fq_fast = 0            # 30초 넘게 넉넉하면 한 단계 올린다 (GPU 추천 단계까지)
		if Settings.step_auto(1):
			apply_settings()


func _star_name(id: String) -> String:
	if id == "galaxy":
		return "우리 은하 중심"
	for s in Astro.systems:
		if s["id"] == id:
			return String(s["name"])
	return id


## 다른 화면에서 쓰는 정보: 지금 보는 범위
func view_scale_text() -> String:
	return Fmt.distance_km(cam.dist)
