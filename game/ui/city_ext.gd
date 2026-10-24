class_name CityExt
extends RefCounted
## 시뮬레이션 밖의 보정을 모아 그 도시의 CitySim.ext로 — 몫(part)마다 c["ext_parts"][몫]에 두고 (services 시설 자리 ·
## mega 메가프로젝트 · cards 연구 카드 …), 더하는 값(morale·housing_add·support_day·rp_day)은 더하고 배율(…_k)은 곱한다.
## 몫이 없거나 기본값이면 시뮬레이션은 파이썬 밸런스 시뮬레이터와 같은 셈을 한다

const ADD := ["morale", "housing_add", "support_day", "rp_day"]
const MUL := ["work_k", "make_k", "build_k", "rp_k"]


static func neutral() -> Dictionary:
	var out := {}
	for k in ADD:
		out[k] = 0.0
	for k in MUL:
		out[k] = 1.0
	return out


static func set_part(c: Dictionary, part: String, values: Dictionary) -> void:
	if not c.get("ext_parts") is Dictionary:
		c["ext_parts"] = {}
	(c["ext_parts"] as Dictionary)[part] = values.duplicate()
	var out := neutral()
	for p in c["ext_parts"]:
		var v: Dictionary = c["ext_parts"][p]
		for k in v:
			if k in MUL:
				out[k] = float(out.get(k, 1.0)) * float(v[k])
			else:
				out[k] = float(out.get(k, 0.0)) + float(v[k])
	var sim: CitySim = c["sim"]
	sim.ext = out
	sim.refresh()


## 보정 한 줄 (패널): 기본값이 아닌 것만
static func text(ext: Dictionary) -> String:
	var parts := PackedStringArray()
	if absf(float(ext.get("morale", 0.0))) >= 0.05:
		parts.append("사기 %+.1f" % float(ext["morale"]))
	for k in ["work_k", "make_k", "build_k", "rp_k"]:
		if absf(float(ext.get(k, 1.0)) - 1.0) >= 0.001:
			parts.append("%s ×%.2f" % [{"work_k": "일하는 효율", "make_k": "만드는 효율", "build_k": "로봇 작업량", "rp_k": "연구"}[k],
				float(ext[k])])
	if float(ext.get("housing_add", 0.0)) > 0.0:
		parts.append("집 +%d" % int(ext["housing_add"]))
	if float(ext.get("support_day", 0.0)) > 0.0:
		parts.append("지원 +%.0f/일" % float(ext["support_day"]))
	if float(ext.get("rp_day", 0.0)) > 0.0:
		parts.append("연구 +%.0f/일" % float(ext["rp_day"]))
	return " · ".join(parts) if not parts.is_empty() else "보정 없음"
