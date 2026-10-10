extends SceneTree
## SVG 여러 장을 게임과 같은 래스터라이저(ThorVG)로 그려 한 장의 PNG로 모은다.
##   godot --headless --script res://tools/art/contact_sheet.gd -- --out sheet.png --cols 6 --scale 2 a.svg b.svg ...
## --bg로 바탕색, --cell로 칸 크기(px)를 바꾼다. 밤 레이어를 보려면 --night를 준다 (몸체를 어둡게 + 불빛).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "sheet.png"
	var cols := 6
	var k := 2.0
	var cell := 0
	var bg := Color("#2a2b2e")
	var night := false
	var files: Array[String] = []
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--out":
			out = args[i + 1]
			i += 1
		elif a == "--cols":
			cols = int(args[i + 1])
			i += 1
		elif a == "--scale":
			k = float(args[i + 1])
			i += 1
		elif a == "--cell":
			cell = int(args[i + 1])
			i += 1
		elif a == "--bg":
			bg = Color(args[i + 1])
			i += 1
		elif a == "--night":
			night = true
		else:
			files.append(a)
		i += 1
	var images: Array[Image] = []
	var max_w := 0
	var max_h := 0
	for f in files:
		var img := _load(f, k)
		if img == null:
			printerr("cannot load ", f)
			quit(1)
			return
		if night:
			var lights := f.replace(".svg", "_lights.svg")
			img = _night(img, _load(lights, k) if FileAccess.file_exists(lights) else null)
		images.append(img)
		max_w = maxi(max_w, img.get_width())
		max_h = maxi(max_h, img.get_height())
	var cw := maxi(cell, max_w + 16)
	var ch := maxi(cell, max_h + 16)
	var rows := ceili(float(images.size()) / cols)
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(bg)
	for n in images.size():
		var img := images[n]
		var x := (n % cols) * cw + (cw - img.get_width()) / 2
		var y := (n / cols) * ch + (ch - img.get_height()) - 8
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))
	sheet.save_png(out)
	print("sheet: %d images -> %s (%dx%d)" % [images.size(), out, sheet.get_width(), sheet.get_height()])
	quit(0)


func _load(path: String, k: float) -> Image:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	var img := Image.new()
	if img.load_svg_from_string(text, k) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _night(body: Image, lights: Image) -> Image:
	## 밤: 몸체를 푸르게 어둡게 하고 불빛을 더한다 (게임의 밤 그리기와 같은 식)
	var out: Image = body.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r * 0.22, c.g * 0.25, c.b * 0.36, c.a))
	if lights != null:
		for y in mini(out.get_height(), lights.get_height()):
			for x in mini(out.get_width(), lights.get_width()):
				var l := lights.get_pixel(x, y)
				if l.a <= 0.0:
					continue
				var c := out.get_pixel(x, y)
				out.set_pixel(x, y, Color(minf(1, c.r + l.r * l.a), minf(1, c.g + l.g * l.a), minf(1, c.b + l.b * l.a), maxf(c.a, l.a)))
	return out
