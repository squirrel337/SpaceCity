class_name TechSite
extends MetroCity
## 반도체·AI 데이터센터 지역의 3D 땅 위 단지 (대도시 시가지 밖의 지역 — 평택·신주·애슈번…). 대도시처럼 땅(SiteSurface)을 하나 쓰고
## 그 위에 시가지 대신 TechCampus의 공장·데이터센터·연구소 묶음을 짓는다. 땅을 구운 뒤 한 번에 짓는다.
## 지역의 해안 지도(earth_coast_tech_<id>.png)가 있으면 물가를 피한다.

var region: Dictionary
var _plain: ShaderMaterial
var _labels: Array = []


## 지역을 대도시처럼 꾸민 자료로 MetroCity를 준비한다 (블록 시가지는 짓지 않는다)
func setup_region(r: Dictionary, g: SiteSurface, hi: bool) -> void:
	region = r
	var m := {"key": String(r["key"]), "id": String(r["id"]), "name": String(r["name"]), "lat": float(r["lat"]),
		"lon": float(r["lon"]), "dir": r["dir"], "radius_km": float(r["radius_km"]), "centers": [], "parks": [],
		"style": "sprawl", "max_h": 80.0, "grid_deg": 0.0}
	setup(m, g, hi)
	budget = 40                                  # 사옥(탑 셰이더)만 센다


func update(_view: WorldView) -> void:
	if _mat:
		_mat.set_shader_parameter("night", ground.night_k)
	if _plain:
		_plain.set_shader_parameter("night", ground.night_k)
	for bm in _beacons:
		(bm as ShaderMaterial).set_shader_parameter("night", ground.night_k)
	if _phase == 0 and ground.baked():
		_build_region()
		_phase = 3


func _build_region() -> void:
	var plots := TechCampus.plan(self, region, Vector2.ZERO)
	var out := {"xf": [], "col": [], "cus": [], "labels": []}
	var mx := maxi(2400, int(float(Settings.q("metro_budget")) / 10.0))
	TechCampus.build(self, region, plots, mx, out)
	_commit()
	_plain = _plain_mesh(self, out)
	_labels = out["labels"]
	if _fac_root == null:
		_fac_root = Node3D.new()
		add_child(_fac_root)
	if not plots.is_empty():
		var en: Vector2 = plots[0]["en"]
		_beacon(_pos(en, _ground_y(en)), Metros.region_color(region), false)


## 단색 상자들 (공장·전산동·설비)을 MultiMesh 하나로 — 밤에는 보안등 (bridge 셰이더)
static func _plain_mesh(host: Node3D, out: Dictionary) -> ShaderMaterial:
	var xs: Array = out["xf"]
	if xs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, out["col"][i])
		mm.set_instance_custom_data(i, out["cus"][i])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/world/shaders/bridge.gdshader")
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (host is MetroCity and (host as MetroCity)._shadows) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return mat


func facility_labels() -> Array:
	return _labels
