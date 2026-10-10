class_name SkyBuilder
extends RefCounted
## 하늘과 천체 메시: 별(밝은 별 목록 + 은하면에 몰린 흐린 별), 은하수, 태양 빛무리, 고리, 구.
## 별은 화면에서 일정한 픽셀 크기로 그린다 (셰이더가 점을 화면 쪽으로 펼친다).

const SHADER_DIR := "res://ui/world/shaders/"


static func _mat(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + file)
	return m


static func sphere(segments: int, rings: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


## 황도 좌표 → Godot 축
static func g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


static func galaxy_axes() -> Array:
	var gal: Dictionary = Astro.sky.get("galaxy", {})
	var np: Array = gal.get("north_pole", [192.859, 27.128])
	var gc: Array = gal.get("center", [266.405, -28.936])
	var north := g(Astro.vec(Astro.radec_dir(float(np[0]), float(np[1])))).normalized()
	var center := g(Astro.vec(Astro.radec_dir(float(gc[0]), float(gc[1])))).normalized()
	return [north, center]


static func milky_way() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = sphere(64, 32)
	var m := _mat("milky_way.gdshader")
	m.render_priority = -100
	var ax := galaxy_axes()
	m.set_shader_parameter("gal_north", ax[0])
	m.set_shader_parameter("gal_center", ax[1])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## 밝은 별(이름 있는 별) + 흐린 별 n개. 메시 하나, 별 하나 = 한 점에 모인 네 꼭짓점
static func sky_stars(n: int) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var add_star := func(dir: Vector3, mag: float, teff: float) -> void:
		var c := Astro.star_color(teff)
		var bright := clampf(1.6 - (mag - 0.5) * 0.2, 0.22, 2.2)
		c.a = bright
		var px := clampf(3.6 - mag * 0.4, 1.1, 4.8)
		var base := verts.size()
		for k in 4:
			verts.append(dir)
			cols.append(c)
			uvs.append(Vector2(float(k == 1 or k == 2), float(k >= 2)))
			uv2s.append(Vector2(px, 0.0))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	for s in Astro.bright:
		add_star.call(g(Astro.vec(s[1])).normalized(), float(s[2]), float(s[3]))
	var ax := galaxy_axes()
	var gn: Vector3 = ax[0]
	var gc: Vector3 = ax[1]
	var ge := gn.cross(gc).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2061
	for i in n:
		var dir: Vector3
		if rng.randf() < 0.45:
			# 은하면 쪽: 은위가 좁게 모인다
			var l := rng.randf() * TAU
			var b := rng.randfn(0.0, 0.16)
			dir = (gc * cos(l) * cos(b) + ge * sin(l) * cos(b) + gn * sin(b)).normalized()
		else:
			dir = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var u := rng.randf()
		var mag := 3.6 + 4.2 * pow(u, 0.42)
		var tr := rng.randf()
		var teff := 3400.0 + 2600.0 * tr if tr < 0.55 else (6000.0 + 4000.0 * (tr - 0.55) / 0.35 if tr < 0.9 else 11000.0 + 14000.0 * (tr - 0.9) * 10.0)
		add_star.call(dir, mag, teff)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat("star_points.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## 이웃 항성계: 별 n개의 판을 메시 하나에 (UV2.x = 번호). 위치·색·크기는 매 프레임 셰이더 배열로 넘긴다
## (멀티메시를 쓰면 호환 렌더러에서 다음 별 그리기가 사라지는 문제가 있었다)
static func near_stars(n: int) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var base := verts.size()
		for k in 4:
			verts.append(Vector3.ZERO)
			uvs.append(Vector2(float(k == 1 or k == 2), float(k >= 2)))
			uv2s.append(Vector2(float(i), 0.0))
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat("star_instances.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


static func glow_sprite() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	mi.material_override = _mat("sun_glow.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	return mi


## 고리: 적도면(메시 XZ)의 고리, UV.x = 반지름(행성 반지름 단위)
static func ring_mesh(r0: float, r1: float, seg: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var a := TAU * i / seg
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d * r0)
		verts.append(d * r1)
		uvs.append(Vector2(r0, float(i) / seg))
		uvs.append(Vector2(r1, float(i) / seg))
		nrm.append(Vector3.UP)
		nrm.append(Vector3.UP)
	for i in seg:
		var k := i * 2
		idx.append_array(PackedInt32Array([k, k + 1, k + 3, k, k + 3, k + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
