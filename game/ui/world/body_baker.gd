class_name BodyBaker
extends Node
## 암석·얼음 천체(data/surfaces.json에 있는 것)의 겉모습을 GPU로 정육면체 지도(법선 + 밝기)에 굽는다.
## 시작할 때 모두 작게 굽고, 카메라가 다가간 천체는 더 곱게 다시 굽는다 (곱게 구운 지도는 최근 몇 개만 둔다).
## 구운 지도는 그 천체 구의 재질(planet.gdshader)과 그 천체 도시의 지형 조각(SiteSurface)이 함께 쓴다.

signal cube_ready(body: String)

const SHADER := "res://ui/world/shaders/body_bake.gdshader"

var surfaces := {}            # 천체 id → BodySurface
var mats := {}                # 천체 id → 구의 ShaderMaterial
var cubes := {}               # 천체 id → {면 크기: Cubemap}
var size_lo := 256
var size_mid := 512
var size_hi := 1024
var keep_fine := 2            # 곱게 구운 지도를 둘 천체 수
var _queue: Array = []        # [천체 id, 면 크기]
var _running := false
var _fine_order: Array = []   # 곱게 구운 천체 (오래된 것부터)


func _init() -> void:
	var bs := Settings.bake_sizes()
	size_lo = int(bs["lo"])
	size_mid = int(bs["mid"])
	size_hi = int(bs["hi"])
	keep_fine = int(bs["keep"])
	if OS.has_environment("WORLD_BAKE_SMALL"):
		size_lo = 64
		size_mid = 256
		size_hi = 256


func add(body: String, mat: ShaderMaterial, radius_km: float) -> void:
	var bs := BodySurface.of(body, radius_km)
	surfaces[body] = bs
	mats[body] = mat
	cubes[body] = {}
	mat.set_shader_parameter("r_km", radius_km)
	bs.apply_look(mat)
	want(body, size_lo)


func has(body: String) -> bool:
	return surfaces.has(body)


## 이 천체를 적어도 이 크기로 (이미 있거나 줄에 있으면 그대로)
func want(body: String, size: int) -> void:
	if not surfaces.has(body) or not Baker.can_bake():
		return
	for s in (cubes[body] as Dictionary):
		if int(s) >= size:
			return
	for q in _queue:
		if q[0] == body and int(q[1]) >= size:
			return
	_queue.append([body, size])


## 지금 쓸 수 있는 가장 고운 지도 (없으면 null)
func cube(body: String) -> Cubemap:
	var best: Cubemap = null
	var bsz := 0
	for s in (cubes.get(body, {}) as Dictionary):
		if int(s) > bsz:
			bsz = int(s)
			best = cubes[body][s]
	return best


func busy() -> bool:
	return _running or not _queue.is_empty()


func _process(_delta: float) -> void:
	if _running or _queue.is_empty():
		return
	# 작은 지도부터 (모두 처음 모습을 갖추게), 같은 크기면 먼저 들어온 것부터
	var best := 0
	for i in _queue.size():
		if int(_queue[i][1]) < int(_queue[best][1]):
			best = i
	var job: Array = _queue.pop_at(best)
	_bake(String(job[0]), int(job[1]))


func _bake(body: String, size: int) -> void:
	_running = true
	var bs: BodySurface = surfaces[body]
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	bs.apply(mat)
	mat.set_shader_parameter("texel", (PI * 0.5) / size)
	mat.set_shader_parameter("mode", 0)
	var images: Array[Image] = []
	for face in 6:
		var m := mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("face", face)
		var img: Image = await Baker.render(self, m, Vector2i(size, size))
		if img == null:
			_running = false
			return
		if OS.has_environment("WORLD_SAVE_BAKE"):
			img.save_png(OS.get_environment("WORLD_SAVE_BAKE").path_join("%s_%d_%d.png" % [body, size, face]))
		img.generate_mipmaps()
		images.append(img)
	var cm := Cubemap.new()
	cm.create_from_images(images)
	var have: Dictionary = cubes[body]
	for s in have.keys():
		if int(s) > size_lo and int(s) < size:
			have.erase(s)
	have[size] = cm
	if size > size_lo:
		_fine_order.erase(body)
		_fine_order.append(body)
		_drop_old()
	_use(body)
	_running = false
	cube_ready.emit(body)


## 곱게 구운 지도가 너무 많으면 오래된 천체의 것을 내려놓는다 (작은 지도로 돌아간다)
func _drop_old() -> void:
	while _fine_order.size() > keep_fine:
		var old: String = _fine_order.pop_front()
		var d: Dictionary = cubes[old]
		for s in d.keys():
			if int(s) > size_lo:
				d.erase(s)
		_use(old)


func _use(body: String) -> void:
	var cm := cube(body)
	var mat: ShaderMaterial = mats[body]
	mat.set_shader_parameter("surf", cm)
	mat.set_shader_parameter("has_surf", cm != null)


## 카메라 둘레: 가까운 천체는 곱게 (화면에서 커질수록)
func update_near(body: String, dist_over_r: float) -> void:
	if not surfaces.has(body):
		return
	if dist_over_r < 5.0:
		want(body, size_hi)
	elif dist_over_r < 14.0:
		want(body, size_mid)
