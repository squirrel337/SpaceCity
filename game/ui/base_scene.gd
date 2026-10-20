class_name BaseScene
extends RefCounted
## 기지에 보여 줄 것 — 2D 지도와 3D 도시가 함께 쓴다.
## 배치 계획(CityPlan)의 건물마다 시뮬레이션의 고장·공사 진척·피복을 붙인다.


## 건물과 공사 현장: {id, sprite, pos, rot, variant, uid, broken, building, progress}
static func collect(sim: CitySim, plan: CityPlan) -> Array:
	plan.sync(sim, CityPlan.SYNC_FRAME_US)
	var items := []
	var progress := {}
	for item in sim.queue:
		progress[int(item["seq"])] = clampf(1.0 - float(item["rd"]) / maxf(1e-6, float(item["rd_total"])), 0.0, 1.0)
	var built := {}
	for e in plan.buildings:
		if int(e["seq"]) >= 0:
			continue
		var kind: String = e["id"]
		if not built.has(kind):
			built[kind] = []
		built[kind].append(e)
	for kind in built:
		var list: Array = built[kind]
		var nb := int(sim.broken.get(kind, 0))
		for i in list.size():
			var e: Dictionary = list[i]
			var sprite: String = kind
			if kind == "hab_module" and i < sim.covered_habs:
				sprite = "hab_module_covered"
			items.append({"id": kind, "sprite": sprite, "pos": Vector3(e["x"], e["y"], 0), "rot": int(e["rot"]),
				"variant": int(e["variant"]), "uid": int(e["uid"]), "broken": i >= list.size() - nb,
				"building": false, "progress": 1.0})
	for e in plan.buildings:
		var seq := int(e["seq"])
		if seq < 0:
			continue
		var kind: String = e["id"]
		items.append({"id": kind, "sprite": scaffold_for(kind), "pos": Vector3(e["x"], e["y"], 0), "rot": int(e["rot"]),
			"variant": 0, "uid": int(e["uid"]), "broken": false, "building": true,
			"progress": float(progress.get(seq, 0.0))})
	return items


## 기본 배치의 자리마다 정한 변형 (0~4). 같은 종류가 나란히 서도 이웃끼리 모양이 다르다
static func variant_of(kind: String, i: int) -> int:
	return (absi(kind.hash()) + i * 3) % 5


static func scaffold_for(kind: String) -> String:
	var f := ArtLib.footprint(kind)
	var m := maxf(f.x, f.y)
	if m <= 6.5:
		return "scaffold_s"
	if m <= 11.0:
		return "scaffold_m"
	return "scaffold_l"


## 로봇이 가야 할 곳: 공사 현장(대기열 앞쪽부터)과 고장 난 건물. {pos, foot, key}
static func sites(sim: CitySim, plan: CityPlan) -> Array:
	var out := []
	if sim == null:
		return out
	plan.sync(sim, CityPlan.SYNC_FRAME_US)
	for item in sim.queue:
		var e := plan.entry_of_seq(int(item["seq"]))
		if e.is_empty():
			continue
		out.append({"pos": Vector3(e["x"], e["y"], 0), "foot": CityPlan.foot_of(String(e["id"]), int(e["rot"])),
			"key": "q%d" % int(e["uid"])})
		if out.size() >= 6:
			break
	for kind in sim.broken:
		var b := int(sim.broken[kind])
		if b <= 0:
			continue
		var list := []
		for e in plan.buildings:
			if e["id"] == kind and int(e["seq"]) < 0:
				list.append(e)
		for j in range(mini(b, list.size())):
			var e: Dictionary = list[list.size() - 1 - j]
			out.append({"pos": Vector3(e["x"], e["y"], 0), "foot": CityPlan.foot_of(kind, int(e["rot"])),
				"key": "b%d" % int(e["uid"])})
	return out
