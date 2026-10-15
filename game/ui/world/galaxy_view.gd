class_name GalaxyView
extends MeshInstance3D
## 우리 은하 전체 — '우주' 고정점에서 본다. 은하 중심 막대와 팽대부, 나선팔 넷(방패-센타우루스·페르세우스는 굵게,
## 직각자·궁수는 가늘게), 그 사이의 원반, 팔을 따라 붉은 성운을 별 구름(점 수만 개)으로 그린다.
## 해는 은하 중심에서 2만 6,670광년, 은하면 위. 별 하나 = 네 꼭짓점 (자리 = 은하 중심 기준 광년, 황도 축).
## 위치는 고정이고, 축척(먼 것을 줄여 넣는 껍질)은 꼭짓점 셰이더가 셈한다 — 매 프레임 CPU는 중심 위치·밝기만 넣는다.
## 해에서 멀어질수록(수백 광년 넘게) 나타나고, 해 둘레의 하늘(별·은하수 띠)은 그만큼 옅어진다.

const R0_LY := 26670.0                 # 해 ~ 은하 중심
const VIEW_KM := 1.5e18                # '우리 은하 전체'를 볼 때 카메라 거리 (약 16만 광년)
const PITCH_DEG := 12.0
const BAR_DEG := 27.0
## 나선팔: [이름, 시작 각(라디안, 막대 끝 기준), 굵기 몫, 무게]
const ARMS := [["방패-센타우루스", 0.0, 1.0, 0.3], ["페르세우스", PI, 1.0, 0.3], ["직각자", PI * 0.5, 0.6, 0.2],
	["궁수-용골", PI * 1.5, 0.6, 0.2]]

var _mat: ShaderMaterial
var center := PackedFloat64Array([0, 0, 0])    # 은하 중심 (km, 해 중심 황도)
var axes := []                                  # [해→중심 c, 은하 동쪽 e, 은하 북극 n] (황도 단위 벡터)


func _init() -> void:
	name = "galaxy"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gal: Dictionary = Astro.sky.get("galaxy", {})
	var np: Array = gal.get("north_pole", [192.859, 27.128])
	var gc: Array = gal.get("center", [266.405, -28.936])
	var n := Astro.vec(Astro.radec_dir(float(np[0]), float(np[1]))).normalized()
	var c := Astro.vec(Astro.radec_dir(float(gc[0]), float(gc[1])))
	c = (c - n * c.dot(n)).normalized()
	var e := n.cross(c).normalized()
	axes = [c, e, n]
	center = Astro.dvec(c * R0_LY * Astro.LY)
	var count := int({"low": 24000, "medium": 42000, "high": 70000, "ultra": 120000}.get(Settings.level(), 42000))
	mesh = _build(count)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/world/shaders/galaxy_points.gdshader")
	material_override = _mat
	custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))
	visible = false


## 카메라·축척에 맞춰 둔다. 해에서 수백 광년 넘게 멀어질수록 밝아진다 (그 몫을 돌려준다 — 하늘을 그만큼 옅게)
func place(view: WorldView) -> float:
	var d_sun := Astro.len3(view.cam.pos) / Astro.LY
	var k := smoothstep(400.0, 6000.0, d_sun)
	visible = k > 0.01
	if not visible:
		return 0.0
	var rel := Astro.sub3(center, view.cam.pos)
	_mat.set_shader_parameter("origin_rel", Vector3(rel[0], rel[1], rel[2]))
	_mat.set_shader_parameter("local_km", view._local)
	_mat.set_shader_parameter("shell_k", WorldView.SHELL_K)
	_mat.set_shader_parameter("unit_km", view._unit)
	_mat.set_shader_parameter("gain", k)
	_mat.set_shader_parameter("px_scale", view.px_scale())
	return k


## 은하 중심 기준 (x: 해→중심, y: 은하 동쪽, z: 북극; 광년) → 황도 축 (광년)
func _to_ecl(p: Vector3) -> Vector3:
	return axes[0] * p.x + axes[1] * p.y + axes[2] * p.z


func _build(n: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var kpc := 3261.56
	var bar_dir := Vector3(-cos(deg_to_rad(BAR_DEG)), sin(deg_to_rad(BAR_DEG)), 0.0)
	var bar_side := Vector3(-bar_dir.y, bar_dir.x, 0.0)
	var add := func(p: Vector3, col: Color, px: float) -> void:
		var q: Vector3 = _to_ecl(p)
		var base := verts.size()
		for k in 4:
			verts.append(q)
			cols.append(col)
			uvs.append(Vector2(float(k == 1 or k == 2), float(k >= 2)))
			uv2s.append(Vector2(px, 0.0))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	var warm := Color(1.0, 0.82, 0.58)
	var white := Color(0.92, 0.93, 1.0)
	var blue := Color(0.7, 0.8, 1.0)
	var pink := Color(1.0, 0.5, 0.62)
	for i in n:
		var u := rng.randf()
		if u < 0.12:
			# 팽대부: 납작한 공
			var p := Vector3(rng.randfn(0.0, 1.1), rng.randfn(0.0, 0.85), rng.randfn(0.0, 0.55)) * kpc
			add.call(p, Color(warm, rng.randf_range(0.25, 0.55)), rng.randf_range(0.6, 1.6))
		elif u < 0.22:
			# 막대: 중심을 지나는 긴 막대 (반 길이 4.5 kpc)
			var t := rng.randfn(0.0, 0.5) * 4.5
			var p2 := (bar_dir * t + bar_side * rng.randfn(0.0, 0.55)) * kpc + Vector3(0, 0, rng.randfn(0.0, 0.3) * kpc)
			add.call(p2, Color(warm.lerp(white, 0.2), rng.randf_range(0.2, 0.45)), rng.randf_range(0.5, 1.4))
		elif u < 0.72:
			# 나선팔: 막대 끝에서 로그 나선으로 (해 쪽 팔은 해 둘레를 지난다)
			var w := rng.randf()
			var arm: Array = ARMS[0]
			var acc := 0.0
			for a in ARMS:
				acc += float(a[3])
				if w <= acc:
					arm = a
					break
			var r := 4.5 + pow(rng.randf(), 1.35) * 12.0
			var th := log(r / 4.5) / tan(deg_to_rad(PITCH_DEG)) + float(arm[1]) + atan2(bar_dir.y, bar_dir.x)
			var spread := (0.25 + r * 0.035) * float(arm[2])
			var p3 := Vector3(cos(th) * r + rng.randfn(0.0, spread), sin(th) * r + rng.randfn(0.0, spread),
				rng.randfn(0.0, 0.12)) * kpc
			var hot := rng.randf()
			var col := blue if hot < 0.45 else white
			var bright := rng.randf_range(0.18, 0.5) * float(arm[2]) + 0.08
			var size := rng.randf_range(0.6, 1.8)
			if hot > 0.965:
				col = pink
				bright = 0.6
				size = 2.4
			add.call(p3, Color(col, bright), size)
		else:
			# 원반: 지수 분포 (축척 길이 2.6 kpc)
			var rr := -2.6 * log(maxf(1e-4, rng.randf() * rng.randf()))
			rr = minf(rr, 18.0)
			var th2 := rng.randf() * TAU
			var p4 := Vector3(cos(th2) * rr, sin(th2) * rr, rng.randfn(0.0, 0.22)) * kpc
			add.call(p4, Color(white.lerp(warm, rng.randf()), rng.randf_range(0.08, 0.22)), rng.randf_range(0.5, 1.2))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 고정점으로 쓸 정보 (WorldView._info): 중심, 반지름(5만 광년), 표면 없음
func info() -> Dictionary:
	return {"center": center, "frame": Basis(), "radius": 5.0e4 * Astro.LY, "surface": false, "chain": []}
