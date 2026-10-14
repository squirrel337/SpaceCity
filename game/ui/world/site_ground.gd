class_name SiteGround
extends Node3D
## 도시가 앉는 땅의 공통 틀 — 달 남극(MoonSurface)과 다른 천체의 부지(SiteSurface)가 따른다.
## 3D 도시(City3D)는 이 틀만 보고 건물을 땅에 놓는다. 좌표는 기지 모형 좌표: 미터, x·y 수평, 원점 = 기지 평지.
## 자세한 도시는 지금 고른 식민지 하나만 그린다 (active) — 밤의 불빛·그늘도 그 땅만 정한다.

signal terrain_ready

var body := "moon"
var city_root: Node3D
var layout: BaseLayout
var active := false:             # 지금 고른 식민지의 땅인가
	set(v):
		if v != active:
			active = v
			_active_changed()

var _site := Vector3(0, 0, -1)   # 기지 평지 중심 (천체 고정 단위 벡터)
var _site_basis := Basis()       # 모형 x, y, z → 천체 고정
var _plateau_m := 0.0            # 평지 높이 (기준 구 위, m)
var _cam_alt_km := 1e9
var _dark_k := 0.0
var raise_sun := true            # 기지 가까이에서 해를 지평선 위로 올린다 (대도시는 실제 밤을 그대로)


func site_dir() -> Vector3:
	return _site


func site_frame() -> Basis:
	return _site_basis


func radius_km() -> float:
	return 1000.0


func radius_m() -> float:
	return radius_km() * 1000.0


func plateau_km() -> float:
	return _plateau_m / 1000.0


## 고른 도시가 되거나 그만둘 때 (다른 천체의 땅은 이때 굽거나 고운 지도를 내려놓는다)
func _active_changed() -> void:
	pass


## 지형 조각의 반지름 (m) — 그 안의 높이는 height_km이 안다
func patch_radius_m() -> float:
	return 0.0


## 천체 고정 방향이 이 땅의 지형 조각 안인가
func covers(dir_b: Vector3) -> bool:
	return (dir_b.normalized() - _site).length() * radius_m() < patch_radius_m()


## 기지 둘레의 높이 (m, 기지 평지 기준, 모형 좌표 x, y)
func local_height_m(_p: Vector2) -> float:
	return 0.0


## 천체 고정 방향의 지형 높이 (km, 기준 구 위)
func height_km(_dir_b: Vector3) -> float:
	return plateau_km()


## 매 프레임: 땅과 도시 뿌리를 카메라 둘레의 렌더 좌표에 놓는다
func update_frame(_view: WorldView, _info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	pass


## 기지 가까이에서는 해를 지평선 위 7° 이상으로 올린다 (낮은 해 아래 땅이 거의 검지 않게)
func adjust_light(dir: Vector3, view: WorldView) -> Vector3:
	var k := 1.0 - smoothstep(30.0, 600.0, _cam_alt_km)
	if k <= 0.0 or view == null or not raise_sun:
		return dir
	var f: Basis = view._info(body)["frame"]
	var up := WorldView.g_vec(f * _site)
	var to_sun := -dir
	var elev := asin(clampf(to_sun.dot(up), -1.0, 1.0))
	var want := maxf(elev, deg_to_rad(7.0))
	var horiz := (to_sun - up * to_sun.dot(up))
	if horiz.length_squared() < 1e-10:
		return dir
	horiz = horiz.normalized()
	var adj := (horiz * cos(want) + up * sin(want)).normalized()
	return -(to_sun.slerp(adj, k)).normalized()


## 기지 가까이(고도 40 km 아래)일수록 1 — 그림자·반사광을 켠다
func near_base_factor() -> float:
	return 1.0 - smoothstep(12.0, 40.0, _cam_alt_km)


## 시뮬레이션이 '어둠'이면 기지 가까이에서 햇빛을 끈다 (멀리서 보면 천체 전체는 그대로 밝다)
func local_light_factor() -> float:
	var k := 1.0 - smoothstep(40.0, 900.0, _cam_alt_km)
	return lerpf(1.0, 0.03, _dark_k * k)


## 해의 방향 (기지 모형 좌표: x·y 수평, z 위)
func sun_in_site(view: WorldView) -> Vector3:
	var info: Dictionary = view._info(body)
	var sun := view._info("sun")
	var rel := Astro.vec(Astro.norm3(Astro.sub3(sun["center"], info["center"])))
	var b: Vector3 = (info["frame"] as Basis).inverse() * rel
	return _site_basis.inverse() * b


func cam_alt_km() -> float:
	return _cam_alt_km


## 고른 식민지의 땅이면 시뮬레이션의 어둠을 따라 밤으로 (건물 불빛도 함께)
func _follow_dark(view: WorldView) -> void:
	var target := 1.0 if (active and view.sim and view.sim.is_dark()) else 0.0
	_dark_k = move_toward(_dark_k, target, get_process_delta_time() / 0.8 if is_inside_tree() else 1.0)
	if active:
		ModelLib.set_night(_dark_k)


## 천체 고정 → 렌더 좌표의 기지 변환 (평지 원점, 모형 축). 땅 조각과 도시 뿌리가 함께 쓴다
func _site_transform(view: WorldView, info: Dictionary) -> Transform3D:
	var c: PackedFloat64Array = info["center"]
	var f: Basis = info["frame"]
	var s := view.body_scale(c)
	var site_e := Astro.bmul(f, Astro.dvec(_site))
	var origin := Astro.add3(c, Astro.scale3(site_e, radius_km() + _plateau_m / 1000.0))
	var rel := Astro.sub3(origin, view.cam.pos)
	var o := Vector3(rel[0] * s, rel[2] * s, -rel[1] * s)
	var bs := f * _site_basis
	var cam_rel := Astro.sub3(view.cam.pos, c)
	var cam_d := Astro.len3(cam_rel)
	_cam_alt_km = cam_d - radius_km() - _plateau_m / 1000.0
	return Transform3D(WorldView.g_basis(bs).scaled(Vector3.ONE * s * 0.001), o)


## 카메라가 기지 쪽 반구에 있나 (천체 반대편이면 땅 조각을 감춘다)
func _near_site(view: WorldView, info: Dictionary) -> bool:
	var c: PackedFloat64Array = info["center"]
	var f: Basis = info["frame"]
	var cam_rel := Astro.sub3(view.cam.pos, c)
	var cam_d := Astro.len3(cam_rel)
	return (f.inverse() * Astro.vec(Astro.scale3(cam_rel, 1.0 / cam_d))).dot(_site) > cos(0.6)
