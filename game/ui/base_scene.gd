class_name BaseScene
extends RefCounted
## 기지에 보여 줄 것 — 2D 지도와 3D 도시가 함께 쓴다.
## 시뮬레이션의 개수·고장·공사 대기열을 자리(BaseLayout)마다의 건물·공사 현장으로 바꾼다.


## 건물과 공사 현장: {id, sprite, pos, variant, broken, building, progress, more}
static func collect(sim: CitySim, layout: BaseLayout) -> Array:
	var items := []
	var queued := {}
	for item in sim.queue:
		var kind: String = item["id"]
		if kind == "regolith_cover" or kind == "robot":
			continue
		queued[kind] = int(queued.get(kind, 0)) + 1
	var kinds := {}
	for kind in sim.counts:
		kinds[kind] = true
	for kind in queued:
		kinds[kind] = true
	for kind in kinds:
		var cap := layout.capacity(kind)
		if cap == 0:
			continue
		var n := int(sim.counts.get(kind, 0))
		var broken := int(sim.broken.get(kind, 0))
		var q := int(queued.get(kind, 0))
		var shown := mini(n, cap)
		for i in range(shown):
			var sprite: String = kind
			if kind == "hab_module" and i < sim.covered_habs:
				sprite = "hab_module_covered"
			items.append({"id": kind, "sprite": sprite, "pos": layout.slot(kind, i), "index": i,
				"variant": variant_of(kind, i), "broken": i >= shown - broken, "building": false, "progress": 1.0,
				"more": (n - cap) if (i == shown - 1 and n > cap) else 0})
		for k in range(q):
			var i := n + k
			if i >= cap:
				break
			items.append({"id": kind, "sprite": scaffold_for(kind), "pos": layout.slot(kind, i), "index": i,
				"variant": 0, "building": true, "progress": queue_progress(sim, kind, k), "broken": false, "more": 0})
	return items


## 자리마다 고정된 변형 (0~4). 같은 종류가 나란히 서도 이웃끼리 모양이 다르다
static func variant_of(kind: String, i: int) -> int:
	return (absi(kind.hash()) + i * 3) % 5


## k번째로 기다리는 같은 종류 공사의 진척 (0~1)
static func queue_progress(sim: CitySim, kind: String, k: int) -> float:
	var seen := 0
	for item in sim.queue:
		if item["id"] != kind:
			continue
		if seen == k:
			var total: float = maxf(1e-6, item["rd_total"])
			return clampf(1.0 - item["rd"] / total, 0.0, 1.0)
		seen += 1
	return 0.0


static func scaffold_for(kind: String) -> String:
	var f := ArtLib.footprint(kind)
	var m := maxf(f.x, f.y)
	if m <= 6.5:
		return "scaffold_s"
	if m <= 11.0:
		return "scaffold_m"
	return "scaffold_l"


## 로봇이 가야 할 곳: 공사 현장(대기열 앞쪽부터)과 고장 난 건물
static func sites(sim: CitySim, layout: BaseLayout) -> Array:
	var out := []
	if sim == null:
		return out
	var counted := {}
	for item in sim.queue:
		var kind: String = item["id"]
		if kind == "regolith_cover" or kind == "robot":
			continue
		var k := int(counted.get(kind, 0))
		counted[kind] = k + 1
		var i := int(sim.counts.get(kind, 0)) + k
		if i >= layout.capacity(kind):
			continue
		out.append(_site(layout, kind, i, "q%s%d" % [kind, i]))
		if out.size() >= 6:
			break
	for kind in sim.broken:
		var b := int(sim.broken[kind])
		var n := mini(int(sim.counts.get(kind, 0)), layout.capacity(kind))
		for j in range(mini(b, n)):
			out.append(_site(layout, kind, n - 1 - j, "b%s%d" % [kind, j]))
	return out


static func _site(layout: BaseLayout, kind: String, i: int, key: String) -> Dictionary:
	return {"pos": layout.slot(kind, i), "foot": ArtLib.footprint(kind), "key": key,
		"district": "ridge" if kind == "solar_tower" else layout.district_of.get(kind, "core")}
