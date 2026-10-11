class_name Baker
extends RefCounted
## GPU 굽기: 캔버스 셰이더 하나를 정해진 크기로 한 번 그려 이미지로 받는다.
## 굽기는 한 번에 하나씩 (여러 장을 한 프레임에 그리면 프레임이 길어진다) — 달·다른 천체·도시 둘레가 함께 쓴다.

static var _busy := false
static var count := 0               # 지금까지 구운 장 수 (시험용)


## 화면이 없으면(헤드리스) 굽지 않는다
static func can_bake() -> bool:
	return DisplayServer.get_name() != "headless"


static func render(host: Node, mat: Material, size: Vector2i) -> Image:
	if not can_bake() or host == null or not host.is_inside_tree():
		return null
	while _busy:
		await host.get_tree().process_frame
		if not is_instance_valid(host) or not host.is_inside_tree():
			return null
	_busy = true
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_busy = false
	count += 1
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## 24비트 높이 ((m + 32768) × 256) 한 칸
static func h24(data: PackedByteArray, o: int) -> float:
	return (data[o] * 65536 + data[o + 1] * 256 + data[o + 2]) / 256.0 - 32768.0
