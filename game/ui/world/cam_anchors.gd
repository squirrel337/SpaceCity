class_name CamAnchors
extends RefCounted
## 카메라의 고정점 — 카메라가 바라보고 도는 점을 플레이어가 고른다: 우리 은하 전체, 이웃 별, 태양계, 행성·위성,
## 도시(식민지), 지구의 대도시, 날아가는 수송선. 고른 고정점은 확대·축소해도 화면 가운데에 남는다.
##
## 화면 위쪽의 경로(우주 › 태양계 › 지구 › 나로 우주항)가 지금 고정점까지의 길이다. 어느 단계든 누르면 그 고정점으로,
## '›'를 누르면 그 아래 것(위성·도시·대도시·수송선)을 고른다. 3D 지도의 이름표를 눌러도 고정점이 된다.
## 고정점 하나 = {kind, id, name, body?, dir?} — kind: galaxy · stars · star · system · earth_moon · body · colony · metro · ship

signal changed

var view: WorldView
var current := {}                 # 마지막으로 고른 고정점 (도시·대도시·수송선은 경로 끝에 남는다)


func _init(p_view: WorldView) -> void:
	view = p_view


# ── 고르기 ──────────────────────────────────────────────────────
## 그 고정점으로 카메라를 옮긴다
func go(a: Dictionary) -> void:
	var cam := view.cam
	cam.lock = not bool(Settings.value("camera/auto_parent", false))
	view._descent.clear()
	current = a
	match String(a.get("kind", "")):
		"galaxy":
			# 은하면 위쪽에서 비스듬히 (해 쪽에서 50° 올려다본 자리) — 나선팔이 보이게
			var ax: Array = view.galaxy.axes
			var vd: Vector3 = (ax[2] as Vector3) * sin(deg_to_rad(52.0)) - (ax[0] as Vector3) * cos(deg_to_rad(52.0))
			cam.fly_to("galaxy", GalaxyView.VIEW_KM, 3.2, Vector3.ZERO, vd)
		"stars":
			cam.fly_to("sun", 22.0 * Astro.LY)
		"star":
			cam.fly_to(String(a["id"]), 3.0 * Astro.AU)
		"system":
			cam.fly_to("sun", 1.2e10)
		"earth_moon":
			cam.fly_to("earth", 1.15e6)
		"body":
			view._fly_to_label(String(a["id"]))
		"colony":
			view.colony_picked.emit(int(a["index"]))
		"site":
			view.site_picked.emit(String(a["id"]))
		"metro":
			view.fly_to_metro(String(a["id"]))
		"tech":
			view.fly_to_region(String(a["id"]))
		"ship":
			var key := String(a["id"])
			var near := String(a.get("body", "sun"))
			view.cam.fly_to_track(near, func(): return ship_pos(key), 0.17, 3.0)     # 170 m 뒤에서 배(길이 56 m)를 본다
	changed.emit()


## 그 땅(고른 식민지)의 고정점 — 기지 위로 갈 때 경로 끝에 그 도시를 둔다
func for_ground(g: SiteGround) -> Dictionary:
	var site := ""
	for k in view.grounds:
		if view.grounds[k] == g:
			site = String(k)
	for i in view.colonies.size():
		var c: Dictionary = view.colonies[i]
		if String(c.get("site", "")) == site and not c.get("candidate", false):
			return {"kind": "colony", "id": site, "index": i, "name": String(c["name"]), "body": g.body, "dir": g.site_dir()}
	return {"kind": "colony", "id": site, "index": -1, "name": view.city.title if view.city else site, "body": g.body,
		"dir": g.site_dir()}


## 한 단계 위로 (Backspace): 경로의 바로 앞 단계
func up() -> void:
	var p := path()
	if p.size() >= 2:
		go(p[p.size() - 2])


## 이 고정점이 지금 화면의 것과 같은가 (경로 끝을 다시 누르면 그 자리로 되돌아가게)
func _same(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("kind", "")) == String(b.get("kind", "")) and String(a.get("id", "")) == String(b.get("id", ""))


# ── 경로 ────────────────────────────────────────────────────────
## 지금 카메라의 고정점까지의 길: [우주, (태양계 | 이웃 별), 행성, 위성, 도시]
func path() -> Array:
	var cam := view.cam
	var out: Array = [{"kind": "galaxy", "id": "galaxy", "name": "우주"}]
	var f := cam.focus
	if f == "galaxy":
		return out
	if String(current.get("kind", "")) == "ship" and cam.track.is_valid():
		out.append(system())
		out.append(current)
		return out
	if not Astro.bodies.has(f):
		out.append({"kind": "stars", "id": "stars", "name": "이웃 별"})
		out.append({"kind": "star", "id": f, "name": view._star_name(f)})
		return out
	if f == "sun" and cam.dist > 0.05 * Astro.LY:
		out.append({"kind": "stars", "id": "stars", "name": "이웃 별"})
		return out
	out.append(system())
	if f == "sun":
		return out
	var b: Dictionary = Astro.bodies[f]
	if b.has("parent") and String(b["parent"]) != "sun":
		out.append(body(String(b["parent"])))
	out.append(body(f))
	var k := String(current.get("kind", ""))
	if k in ["colony", "metro", "site", "tech"] and String(current.get("body", "")) == f and cam.mode == "body":
		var r := float(b["radius_km"])
		var t := Astro.vec(cam.t_dir)
		var d: Vector3 = current.get("dir", Vector3.ZERO)
		if d != Vector3.ZERO and t.angle_to(d.normalized()) * r < maxf(60.0, cam.dist * 2.0):
			out.append(current)
	return out


static func system() -> Dictionary:
	return {"kind": "system", "id": "sun", "name": "태양계"}


static func body(id: String) -> Dictionary:
	return {"kind": "body", "id": id, "name": String(Astro.bodies[id]["name"])}


## 그 고정점 아래에서 고를 것들
func children(a: Dictionary) -> Array:
	var out: Array = []
	match String(a.get("kind", "")):
		"galaxy":
			out.append({"kind": "galaxy", "id": "galaxy", "name": "우리 은하 전체"})
			out.append({"kind": "stars", "id": "stars", "name": "이웃 별 (25광년)"})
			out.append(system())
		"stars":
			var list: Array = Astro.systems.duplicate()
			list.sort_custom(func(x, y): return float(x["dist_ly"]) < float(y["dist_ly"]))
			for s in list.slice(0, 24):
				out.append({"kind": "star", "id": String(s["id"]), "name": "%s · %.1f광년" % [s["name"], float(s["dist_ly"])]})
		"system":
			for id in Astro.order:
				var b: Dictionary = Astro.bodies[id]
				if String(b.get("kind", "")) in ["planet", "dwarf"]:
					out.append(body(id))
			out.append({"kind": "earth_moon", "id": "earth_moon", "name": "지구와 달"})
			out.append_array(ships())
		"body":
			var id := String(a["id"])
			for mid in Astro.order:
				if String(Astro.bodies[mid].get("parent", "")) == id:
					out.append(body(mid))
			out.append_array(cities_on(id))
	return out


## 그 천체의 도시: 식민지(고른 도시 포함), 후보지, 지구의 대도시
func cities_on(id: String) -> Array:
	var out: Array = []
	for i in view.colonies.size():
		var c: Dictionary = view.colonies[i]
		if String(c.get("body", "")) != id or c.get("transit", false):
			continue
		var d: Vector3 = c.get("dir", Vector3.ZERO)
		if c.get("candidate", false):
			out.append({"kind": "site", "id": String(c["site"]), "name": "%s (후보지)" % c["name"], "body": id, "dir": d})
		else:
			out.append({"kind": "colony", "id": String(c["site"]), "index": i, "name": String(c["name"]), "body": id, "dir": d})
	if id == "earth":
		Metros.load_all()
		for m in Metros.list:
			out.append({"kind": "metro", "id": String(m["key"]), "name": "%s · %s" % [m["name"], Metros.pop_text(m)],
				"body": "earth", "dir": m["dir"]})
		for r in Metros.regions:
			out.append({"kind": "tech", "id": String(r["key"]), "name": "%s · %s" % [r["name"], Metros.kinds_text(r)],
				"body": "earth", "dir": r["dir"]})
	return out


## 날아가는 중인 행성 사이 수송선
func ships() -> Array:
	var out: Array = []
	if view.mgr == null:
		return out
	var tr := view.mgr.transport
	for t_rec in tr.trips:
		var l := tr.line_by_id(String(t_rec["line"]))
		if l.is_empty() or String(l["kind"]) != "ship":
			continue
		var left := maxf(0.0, (float(t_rec["arrive"]) - float(view.mgr.hour)) / 24.0)
		var sh := Fleet.ship(view.mgr, int(t_rec["ship"])) if t_rec.has("ship") else {}
		out.append({"kind": "ship", "id": "%s|%d" % [t_rec["line"], int(t_rec["depart"])],
			"body": Transport.window_body(Transport.node_body(String(t_rec["from"]))),
			"name": "%s %s → %s · %d일 남음" % [("%s(%s)" % [String(sh["name"]), Fleet.cls_short(String(sh["cls"]))]) if not sh.is_empty() else "수송선",
				Transport.node_name(String(t_rec["from"])), Transport.node_name(String(t_rec["to"])), int(ceil(left))]})
	return out


## 수송선의 지금 자리 (km, 태양 중심; ahead_h 시간 뒤). 닿아서 사라졌으면 도착 천체
func ship_pos(key: String, ahead_h := 0.0) -> PackedFloat64Array:
	var mgr := view.mgr
	if mgr != null:
		var tr := mgr.transport
		for t_rec in tr.trips:
			if "%s|%d" % [t_rec["line"], int(t_rec["depart"])] == key:
				var l := tr.line_by_id(String(t_rec["line"]))
				var k := RouteOverlay.progress(l, t_rec, float(mgr.hour) + view.hour_frac + ahead_h)
				return view.routes.ship_point(t_rec, k)
	var parts := key.split("|")
	var line := parts[0]
	var to := line.split("~")[-1] if "~" in line else "earth"
	return view._info(Transport.window_body(Transport.node_body(to)))["center"]
