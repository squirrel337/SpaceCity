class_name HabitatGround
extends SiteGround
## 궤도 도시(L5 아일랜드)의 땅: 회전 원통의 안쪽 바닥. 원통의 겉모습·안벽은 그 천체 노드의 HabitatView가 그리고,
## 이 땅은 도시 뿌리를 바닥에 놓고 원통의 휨(가로로 위로 굽는다)을 도시에 알린다.
## 카메라는 '가상 구'를 쓴다 — 구의 꼭대기(몸체 z)가 바닥이고 '위'가 축 쪽이다 (Astro.habitat_center). 모형 축: x = 원통 축,
## y = 가로 (바닥이 위로 휘는 쪽), z = 위. 땅을 팔 수 없다 (높이 격자가 없다 — 고치기는 그대로 남는다).
## 밤이 없고 해는 거울로 늘 위에서 든다 (기지 가까이에서 빛을 위로 옮긴다).

var hab: HabitatView                  # 그 천체의 원통 (도시 자리를 알려 안벽 무늬를 바꾼다)
var _r_km := 3.0


func setup(p_body: String, p_site: Dictionary, p_radius_km: float, p_hab: HabitatView) -> void:
	body = p_body
	_r_km = p_radius_km
	hab = p_hab
	layout = BaseLayout.new(String(p_site.get("layout", "open")))
	_site = Vector3(0, 0, 1)
	_site_basis = Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	_plateau_m = 0.0
	raise_sun = false
	city_root = Node3D.new()
	add_child(city_root)
	terrain_ready.emit.call_deferred()


func radius_km() -> float:
	return _r_km


## 도시의 휨: 굽은 천체와 달리 원통 안쪽은 가로(y)로 위로 휜다 — 아래로 '떨어지는' 몫이 음수
func drop_m(p: Vector2) -> float:
	var r := _r_km * 1000.0
	return -(r - sqrt(maxf(r * r - p.y * p.y, 0.0)))


func patch_radius_m() -> float:
	return _r_km * 1000.0 * 0.9


func covers(dir_b: Vector3) -> bool:
	return dir_b.normalized().z > 0.55


## 가상 구 위로 바닥까지의 높이 (km) — 카메라가 휜 바닥 밑으로 들어가지 않게: 구 중심에서 그 방향으로 바닥 평면에 닿는 점의
## 가로 자리로 원통 바닥의 휨을 더한다
func height_km(dir_b: Vector3) -> float:
	var d := dir_b.normalized()
	if d.z < 0.3:
		return 0.0
	var r := _r_km
	var px := r * d.x / d.z
	var py := r * d.y / d.z
	var plane := sqrt(px * px + py * py + r * r) - r            # 바닥 평면이 구보다 높은 만큼
	var rise := r - sqrt(maxf(r * r - py * py, 0.0))
	return plane + rise


func update_frame(view: WorldView, info: Dictionary, _sun_c: PackedFloat64Array) -> void:
	var t := _site_transform(view, info)
	city_root.global_transform = t
	city_root.visible = active and _cam_alt_km < 400.0 and hab != null and hab.visible
	if hab != null:
		hab.city_on = active
	_follow_dark(view)


## 기지 가까이에서는 빛을 원통 축 쪽(위)에서 조금 비껴 비춘다 — 거울이 들인 햇빛
func adjust_light(dir: Vector3, view: WorldView) -> Vector3:
	var k := 1.0 - smoothstep(8.0, 40.0, _cam_alt_km)
	if k <= 0.0 or view == null:
		return dir
	var f: Basis = view._info(body)["frame"]
	var to_sun := WorldView.g_vec((f * Vector3(0.42, 0.25, 0.87)).normalized())
	return -((-dir).slerp(to_sun, k)).normalized()


func sun_in_site(_view: WorldView) -> Vector3:
	return Vector3(0.42, 0.25, 0.87).normalized()


func local_light_factor() -> float:
	return 1.0
