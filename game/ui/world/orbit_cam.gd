class_name OrbitCam
extends RefCounted
## 구글 어스식 카메라. 위치는 배정밀도(km, 태양 중심 황도 좌표).
##
## body 모드 — 천체 가까이: 목표는 천체 고정 좌표의 표면 점(t_dir). 천체가 돌면 같이 돈다.
##   거리(dist)·방위(fwd: 목표 지점의 수평 방향)·기울기(tilt: 0 = 똑바로 내려다봄)로 카메라를 둔다.
##   멀어질수록 목표가 천체 중심으로 옮겨 가고 기울기가 0으로 줄어 지구본처럼 돌린다.
## space 모드 — 천체 반지름의 4배보다 멀 때: 목표는 천체 중심에서 상위 계(지구, 태양)로 옮겨 가고,
##   카메라는 황도 북쪽을 위로 하는 회전대(yaw·pitch)로 돈다.
## fly — 다른 천체·별로 날아간다 (멀어졌다가 다가간다).

signal focus_changed(id: String)

const BODY_TO_SPACE := 4.0          # 반지름의 몇 배에서 space 모드로
const SPACE_TO_BODY := 3.0
const MIN_DIST_KM := 0.025
const MAX_DIST_KM := 4.0e17         # 약 4만 광년
const FOV_DEG := 50.0

var focus := "moon"
var mode := "body"
## body 모드
var t_dir := PackedFloat64Array([0, 0, -1])   # 목표 지점: 천체 고정 좌표 단위 벡터
var fwd := Vector3(1, 0, 0)                   # 목표 지점에서 카메라가 바라보는 수평 방향 (천체 고정)
var tilt := 0.0
var dist := 1.0
## space 모드
var yaw := 0.0
var pitch := 0.6
## 날기
var _fly := {}

## 매 프레임 갱신되는 결과 (황도 좌표)
var pos := PackedFloat64Array([0, 0, 0])      # 카메라 위치 km
var target := PackedFloat64Array([0, 0, 0])   # 바라보는 점 km
var basis := Basis()                          # 열: 오른쪽, 위, 뒤 (Camera3D와 같은 규칙: 앞은 -z)
var jd := Astro.J2000

## 천체 정보 함수 (WorldView가 넣어 준다): id → {center: PackedFloat64Array, frame: Basis, radius: float}
var body_info: Callable
## 지형 높이 (km): (id, 몸체 고정 방향 Vector3) → 높이
var terrain: Callable


func _body(id: String) -> Dictionary:
	return body_info.call(id)


func radius_of(id: String) -> float:
	return float(_body(id).get("radius", 1.0))


# ── 상태 바꾸기 ─────────────────────────────────────────────────
## 천체 표면의 한 점을 바라보게 둔다 (body 모드)
func look_at_surface(id: String, dir_body: Vector3, distance_km: float, tilt_rad: float, heading_fwd: Vector3) -> void:
	focus = id
	mode = "body"
	t_dir = Astro.dvec(dir_body.normalized())
	fwd = _tangent(dir_body.normalized(), heading_fwd)
	tilt = tilt_rad
	dist = clampf(distance_km, MIN_DIST_KM, MAX_DIST_KM)
	_fly.clear()
	focus_changed.emit(focus)


## 천체(또는 별)를 멀리서 본다 (space 모드)
func look_from_space(id: String, distance_km: float, yaw_rad: float, pitch_rad: float) -> void:
	focus = id
	mode = "space"
	dist = clampf(distance_km, MIN_DIST_KM, MAX_DIST_KM)
	yaw = yaw_rad
	pitch = clampf(pitch_rad, -1.55, 1.55)
	_fly.clear()
	focus_changed.emit(focus)


func flying() -> bool:
	return not _fly.is_empty()


## 다른 천체로 날아간다. 끝 거리는 반지름의 몇 배 (별은 km를 직접).
## land_dir(천체 고정 방향)을 주면 그 지점을 똑바로 내려다보며 도착한다 — 식민지로 갈 때
func fly_to(id: String, end_dist_km: float, seconds: float = 2.6, land_dir: Vector3 = Vector3.ZERO) -> void:
	var b := _body(id)
	if b.is_empty():
		return
	var to_center: PackedFloat64Array = b["center"]
	var v0 := Astro.norm3(Astro.sub3(pos, target))
	# 지금 보는 쪽에서 다가가되 해가 비추는 쪽으로 기운다 (밤쪽에서 도착하지 않게)
	var v1 := Astro.norm3(Astro.sub3(pos, to_center))
	if Astro.len3(Astro.sub3(pos, to_center)) < 1e-6:
		v1 = v0
	var sun := _body("sun")
	if land_dir != Vector3.ZERO:
		v1 = Astro.dvec(((b["frame"] as Basis) * land_dir).normalized())
	elif id != "sun" and not sun.is_empty() and b.get("surface", true):
		var to_sun := Astro.norm3(Astro.sub3(sun["center"], to_center))
		v1 = Astro.norm3(Astro.lerp3(v1, to_sun, 0.55))
	_fly = {"id": id, "t": 0.0, "dur": seconds, "a0": target.duplicate(), "v0": v0, "v1": v1,
		"d0": dist, "d1": clampf(end_dist_km, MIN_DIST_KM, MAX_DIST_KM), "land": land_dir.normalized()}
	focus = id
	focus_changed.emit(focus)


# ── 조작 ────────────────────────────────────────────────────────
## 끌기: 화면 픽셀(dx, dy)과 화면 높이(px)
func drag(dx: float, dy: float, view_h: float) -> void:
	if flying():
		return
	if mode == "space":
		var k := deg_to_rad(0.25)
		yaw -= dx * k
		pitch = clampf(pitch + dy * k, -1.55, 1.55)
		return
	var r := radius_of(focus)
	var w := _center_weight(dist, r)
	var to_surface := maxf(dist - w * r, dist * 0.02)
	var km_px := 2.0 * to_surface * tan(deg_to_rad(FOV_DEG) * 0.5) / maxf(view_h, 1.0)
	var t_eff := tilt * (1.0 - w)
	# 화면 오른쪽 = fwd × up... 목표를 끈 방향의 반대로 옮긴다 (땅을 잡아 끄는 느낌)
	var up := Astro.vec(t_dir)
	var right := fwd.cross(up).normalized()
	var move := (right * -dx + fwd * (dy / maxf(cos(t_eff), 0.25))) * km_px
	_pan(move / maxf(r, 1e-6))


## 목표를 천체 고정 좌표의 접선 벡터(라디안 단위)만큼 옮긴다
func _pan(step: Vector3) -> void:
	var ang := step.length()
	if ang < 1e-15:
		return
	var up := Astro.vec(t_dir)
	var axis := up.cross(step / ang)
	if axis.length_squared() < 1e-12:
		return
	axis = axis.normalized()
	t_dir = _rot_d(t_dir, axis, ang)
	fwd = _tangent(Astro.vec(t_dir), fwd.rotated(axis, ang))


## 배정밀도 회전 (로드리게스)
static func _rot_d(v: PackedFloat64Array, axis: Vector3, ang: float) -> PackedFloat64Array:
	var k := Astro.dvec(axis)
	var c := cos(ang)
	var s := sin(ang)
	var kv := PackedFloat64Array([k[1] * v[2] - k[2] * v[1], k[2] * v[0] - k[0] * v[2], k[0] * v[1] - k[1] * v[0]])
	var kd := Astro.dot3(k, v)
	var out := PackedFloat64Array([
		v[0] * c + kv[0] * s + k[0] * kd * (1.0 - c),
		v[1] * c + kv[1] * s + k[1] * kd * (1.0 - c),
		v[2] * c + kv[2] * s + k[2] * kd * (1.0 - c)])
	return Astro.norm3(out)


## 오른쪽 끌기·두 손가락 비틀기: 방위와 기울기
func rotate_view(d_heading: float, d_tilt: float) -> void:
	if flying():
		return
	if mode == "space":
		yaw -= d_heading
		pitch = clampf(pitch - d_tilt, -1.55, 1.55)
		return
	var up := Astro.vec(t_dir)
	fwd = _tangent(up, fwd.rotated(up, -d_heading))
	tilt = clampf(tilt + d_tilt, 0.0, max_tilt())


func max_tilt() -> float:
	var r := radius_of(focus)
	var near := 1.0 - smoothstep(30.0, maxf(r * 0.8, 60.0), dist)
	return lerpf(deg_to_rad(45.0), deg_to_rad(84.0), near)


## 확대·축소 (k < 1이면 다가감). toward: body 모드에서 다가갈 표면 점(천체 고정 방향), 없으면 목표 그대로
func zoom(k: float, toward: Vector3 = Vector3.ZERO) -> void:
	if flying():
		return
	var old := dist
	dist = clampf(dist * k, MIN_DIST_KM, MAX_DIST_KM)
	if mode == "body" and toward != Vector3.ZERO and k < 1.0:
		var up := Astro.vec(t_dir)
		var tgt := toward.normalized()
		var ang := up.angle_to(tgt)
		if ang > 1e-12:
			var r := radius_of(focus)
			# 커서 아래 점이 화면에서 제자리에 머물도록 거리 줄어든 만큼 다가간다
			var frac := clampf(1.0 - dist / old, 0.0, 1.0) * (1.0 - _center_weight(old, r))
			_pan((tgt - up * up.dot(tgt)).normalized() * ang * frac)
	tilt = minf(tilt, max_tilt())


# ── 매 프레임 ───────────────────────────────────────────────────
func update(delta: float, p_jd: float) -> void:
	jd = p_jd
	if flying():
		_step_fly(delta)
		return
	var b := _body(focus)
	if b.is_empty():
		return
	var r: float = b["radius"]
	if mode == "body" and dist > BODY_TO_SPACE * r:
		_to_space()
	elif mode == "space" and dist < SPACE_TO_BODY * r and b.get("surface", true):
		_to_body()
	if mode == "body":
		_pose_body(b)
	else:
		_pose_space(b)


func _center_weight(d: float, r: float) -> float:
	return smoothstep(0.3, 2.5, d / maxf(r, 1e-9))


## space 모드에서 쓸 '위': 황도 북쪽을 화면 위로
static func _space_up(v: Vector3) -> Vector3:
	var p := asin(clampf(v.z, -1.0, 1.0))
	var y := atan2(v.y, v.x)
	return Vector3(-sin(p) * cos(y), -sin(p) * sin(y), cos(p))


func _pose_body(b: Dictionary) -> void:
	var c: PackedFloat64Array = b["center"]
	var f: Basis = b["frame"]
	var r: float = b["radius"]
	var up_b := Astro.vec(t_dir)
	var h := 0.0
	if terrain.is_valid():
		h = terrain.call(focus, up_b)
	var w := _center_weight(dist, r)
	var s := Astro.add3(c, Astro.bmul(f, Astro.scale3(t_dir, r + h)))
	target = Astro.lerp3(s, c, w)
	var up := f * up_b
	# 멀어지면 화면 위를 황도 북쪽 쪽으로 서서히 맞춘다 (space 모드로 넘어갈 때 돌지 않게)
	var fw := f * fwd
	var k := smoothstep(1.5, 3.5, dist / r)
	if k > 0.0:
		var want := _space_up(up)
		if want.cross(up).length_squared() > 1e-8:
			fw = fw.slerp(_tangent(up, want), k).normalized()
	var t_eff := tilt * (1.0 - w)
	var v := (up * cos(t_eff) - fw * sin(t_eff)).normalized()
	pos = Astro.add3(target, Astro.scale3(Astro.dvec(v), dist))
	# 땅 밑으로 들어가지 않게
	if terrain.is_valid() and w < 0.5:
		var rel := Astro.sub3(pos, c)
		var rl := Astro.len3(rel)
		var dir_b := f.inverse() * Astro.vec(Astro.scale3(rel, 1.0 / rl))
		var ground: float = r + float(terrain.call(focus, dir_b)) + 0.003
		if rl < ground:
			pos = Astro.add3(c, Astro.scale3(rel, ground / rl))
	var cam_up := (fw * cos(t_eff) + up * sin(t_eff)).normalized()
	_set_basis(Astro.vec(Astro.norm3(Astro.sub3(pos, target))), cam_up)


func _anchor(d: float) -> PackedFloat64Array:
	var b := _body(focus)
	var a: PackedFloat64Array = b["center"]
	for step in b.get("chain", []):
		var anc := _body(step[0])
		if anc.is_empty():
			continue
		var lo: float = step[1]
		var hi: float = step[2]
		var wt := smoothstep(log(lo), log(hi), log(maxf(d, 1e-9)))
		if wt > 0.0:
			a = Astro.lerp3(a, anc["center"], wt)
	return a


func _pose_space(_b: Dictionary) -> void:
	target = _anchor(dist)
	var v := Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
	pos = Astro.add3(target, Astro.scale3(Astro.dvec(v), dist))
	_set_basis(v, _space_up(v))


func _set_basis(back: Vector3, up_hint: Vector3) -> void:
	var z := back.normalized()
	var x := up_hint.cross(z)
	if x.length_squared() < 1e-10:
		x = Vector3(1, 0, 0).cross(z) if absf(z.x) < 0.9 else Vector3(0, 1, 0).cross(z)
	x = x.normalized()
	basis = Basis(x, z.cross(x), z)


func _to_space() -> void:
	var b := _body(focus)
	var f: Basis = b["frame"]
	var v := (f * Astro.vec(t_dir)).normalized()
	mode = "space"
	yaw = atan2(v.y, v.x)
	pitch = asin(clampf(v.z, -1.0, 1.0))


func _to_body() -> void:
	var b := _body(focus)
	var f: Basis = b["frame"]
	var v := Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
	var dir_b := (f.inverse() * v).normalized()
	mode = "body"
	t_dir = Astro.dvec(dir_b)
	tilt = 0.0
	fwd = _tangent(dir_b, f.inverse() * _space_up(v))


static func _tangent(up: Vector3, v: Vector3) -> Vector3:
	var t := v - up * v.dot(up)
	if t.length_squared() < 1e-12:
		t = Vector3(0, 0, 1) - up * up.z
		if t.length_squared() < 1e-12:
			t = Vector3(1, 0, 0) - up * up.x
	return t.normalized()


func _step_fly(delta: float) -> void:
	_fly["t"] += delta / float(_fly["dur"])
	var t: float = clampf(_fly["t"], 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	var b := _body(_fly["id"])
	var c: PackedFloat64Array = b["center"]
	var a0: PackedFloat64Array = _fly["a0"]
	var d0: float = _fly["d0"]
	var d1: float = _fly["d1"]
	var gap := Astro.len3(Astro.sub3(c, a0))
	var bump := maxf(0.0, log(maxf(gap, 1e-9) / maxf(d0, d1)) * 0.85)
	dist = exp(lerpf(log(d0), log(d1), e) + bump * sin(PI * t))
	target = Astro.lerp3(a0, c, e)
	var v0 := Astro.vec(_fly["v0"])
	var v1 := Astro.vec(_fly["v1"])
	var land: Vector3 = _fly["land"]
	if land != Vector3.ZERO:
		v1 = ((b["frame"] as Basis) * land).normalized()    # 천체가 도는 동안에도 그 지점 위로
	var v := v0.slerp(v1, e).normalized() if v0.dot(v1) > -0.999 else v1
	pos = Astro.add3(target, Astro.scale3(Astro.dvec(v), dist))
	_set_basis(v, _space_up(v))
	if t >= 1.0:
		var id: String = _fly["id"]
		_fly.clear()
		focus = id
		mode = "space"
		yaw = atan2(v.y, v.x)
		pitch = asin(clampf(v.z, -1.0, 1.0))
		dist = d1
		if b.get("surface", true) and dist < SPACE_TO_BODY * float(b["radius"]):
			_to_body()


## 화면 위 회전 방향 표시용: 북쪽에서 시계 방향으로 잰 방위(도). body 모드가 아니면 NAN
func heading_deg() -> float:
	if mode != "body":
		return NAN
	var up := Astro.vec(t_dir)
	var north := _tangent(up, Vector3(0, 0, 1))
	var east := north.cross(up)
	return fposmod(rad_to_deg(atan2(fwd.dot(east), fwd.dot(north))), 360.0)
