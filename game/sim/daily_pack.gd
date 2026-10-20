class_name DailyPack
extends RefCounted
## 저장 속 일별 기록의 꼴: 열 이름 한 번과 줄마다 숫자 (실수는 1/1000 단위 정수 — CitySim._pack_daily가 싼다).
## 다른 스크립트를 부르지 않는다 — 시작 화면(boot.gd)이 저장을 다른 스레드에서 미리 풀 때도 쓴다.


## {cols, k, rows} → 줄마다 {열: 값} (k가 1인 열은 정수)
static func unpack(d: Dictionary) -> Array:
	var cols: Array = d.get("cols", [])
	var ks: Array = d.get("k", [])
	var names: Array[String] = []
	var div := PackedInt32Array()
	for j in cols.size():
		names.append(String(cols[j]))
		div.append(int(ks[j]) if j < ks.size() else 1000)
	var out: Array = []
	for row: Array in d.get("rows", []):
		var rec := {}
		for j in mini(names.size(), row.size()):
			rec[names[j]] = int(row[j]) if div[j] == 1 else float(row[j]) / div[j]
		out.append(rec)
	return out


## 저장 전체의 싼 일별 기록을 제자리에서 푼다 (식민지마다 — 식민지 하나뿐이던 판 1은 맨 위)
static func unpack_save(data: Dictionary) -> void:
	var sims: Array = []
	if data.get("colonies") is Array:
		for cd in data["colonies"]:
			if cd is Dictionary and cd.get("sim") is Dictionary:
				sims.append(cd["sim"])
	else:
		sims.append(data)
	for sd: Dictionary in sims:
		if sd.get("daily") is Dictionary:
			sd["daily"] = unpack(sd["daily"])
