class_name Difficulty
extends RefCounted
## 난이도와 샌드박스 (자료 city_difficulty.json) — 시뮬레이션 밖의 규칙. 고른 id는 Colonies.difficulty에 (저장된다).
## 새 게임에서 고르고 메뉴에서 바꿀 수 있다 (시작 자원은 새 게임 때 한 번). 시나리오를 하는 동안은 늘 보통이다.
## 보통은 규칙이 비어 있다 — 시뮬레이션은 파이썬 밸런스 시뮬레이터와 같은 셈을 한다.
## 거는 곳: CityHazards.rate_k (Scenario.apply_rules가 시나리오 규칙과 곱한다) · CityExt의 difficulty 몫 (모든 도시 —
##   고장·태양 폭풍·지구 지원·짓는 값·로봇 작업량·연구·사기) · main의 패배 (trust_days · no_fail) · 날마다 샌드박스 채우기 (step_day)

const PATH := "res://data/city_difficulty.json"
const EXT_KEYS := ["break_k", "storm_k", "support_k", "cost_k", "build_k", "rp_k", "morale"]

static var D := {}


static func data() -> Dictionary:
	if D.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		D = parsed if parsed is Dictionary else {"default": "normal", "trust_days": 365, "levels": []}
	return D


static func levels() -> Array:
	return data().get("levels", [])


static func find(id: String) -> Dictionary:
	for l in levels():
		if String(l.get("id", "")) == id:
			return l
	return {}


static func name_of(id: String) -> String:
	return String(find(id).get("name", id))


## 시나리오를 하는 중인가 (끝나지 않은 시나리오)
static func in_scenario(col: Colonies) -> bool:
	return not col.scenario.is_empty() and String(col.scenario.get("result", "")) == ""


## 지금 걸린 난이도 — 시나리오를 하는 동안은 보통
static func id_of(col: Colonies) -> String:
	if col == null or in_scenario(col) or find(col.difficulty).is_empty():
		return "normal"
	return col.difficulty


static func rule(col: Colonies, key: String, default: Variant = null) -> Variant:
	return (find(id_of(col)).get("rules", {}) as Dictionary).get(key, default)


## 신뢰가 10 아래로 며칠이면 시드가 꺼지나 — 0이면 꺼지지 않는다
static func trust_days(col: Colonies) -> int:
	return int(rule(col, "trust_days", int(data().get("trust_days", 365))))


## 지지 않는다 (샌드박스): 시드가 꺼지지 않고, 정착민이 다 사라지면 새로 온다
static func no_fail(col: Colonies) -> bool:
	return bool(rule(col, "no_fail", false))


## 새 게임 (Colonies.start 뒤): 난이도를 정하고 고향의 시작 자원을 고친 뒤 모든 도시에 건다
static func begin(col: Colonies, id: String) -> void:
	col.difficulty = id if not find(id).is_empty() else "normal"
	var home: CitySim = col.list[0]["sim"]
	home.stock["parts"] = float(home.stock["parts"]) * float(rule(col, "start_parts_k", 1.0))
	home.support *= float(rule(col, "start_support_k", 1.0))
	apply(col)
	if col.difficulty != "normal":
		home.note("난이도 — %s: %s" % [name_of(col.difficulty), String(find(col.difficulty).get("text", ""))], "info")


## 게임 중에 바꾼다 (메뉴 — 시작 자원은 그대로). 시나리오 중이거나 없는 난이도면 false
static func change(col: Colonies, id: String) -> bool:
	if find(id).is_empty() or in_scenario(col):
		return false
	col.difficulty = id
	apply(col)
	(col.list[0]["sim"] as CitySim).note("난이도를 바꿨다 — %s" % name_of(id), "info")
	return true


## 모든 도시에 건다 (새 게임·불러오기·바꾸기·시나리오가 끝났을 때)
static func apply(col: Colonies) -> void:
	for c in col.list:
		apply_city(col, c)
	Scenario.apply_rules(col)


## 도시 하나 (새로 세운 도시도): CityExt의 difficulty 몫 — 보통이면 빈 몫
static func apply_city(col: Colonies, c: Dictionary) -> void:
	if not c.has("sim"):
		return
	var r: Dictionary = find(id_of(col)).get("rules", {})
	var values := {}
	for k in EXT_KEYS:
		if r.has(k):
			values[k] = float(r[k])
	var parts: Dictionary = c.get("ext_parts", {}) if c.get("ext_parts") is Dictionary else {}
	if parts.has("difficulty") and parts["difficulty"] == values:
		return
	CityExt.set_part(c, "difficulty", values)


## 날마다 (Colonies.step — 모든 도시): 샌드박스면 자원을 채우고, 산소·물·식량을 지키고, 정착민이 다 사라졌으면 새로 내린다
static func step_day(col: Colonies) -> void:
	var r: Dictionary = find(id_of(col)).get("rules", {})
	var top: Dictionary = r.get("topup", {}) if r.get("topup") is Dictionary else {}
	var days := float(r.get("reserve_days", 0.0))
	var relief := int(r.get("relief", 0))
	if top.is_empty() and days <= 0.0 and relief <= 0:
		return
	for c in col.list:
		var s: CitySim = c["sim"]
		for k in top:
			if String(k) == "support":
				s.support = maxf(s.support, float(top[k]))
			elif s.stock.has(k):
				s.stock[k] = maxf(float(s.stock[k]), float(top[k]))
		if relief > 0 and s.population() <= 0.0:
			s.cohorts.append([float(relief), 0.0, false])
			s.note("샌드박스 — 정착민이 모두 사라져 지구가 %d명을 새로 보냈다" % relief, "warn")
		var pop := s.population()
		if days > 0.0 and pop > 0.0:
			for key in CitySim.SUPPLY_PER:
				var want := minf(pop * float(s.PER[CitySim.SUPPLY_PER[key]]) * days, float(s.caps.get(key, INF)))
				if float(s.stock[key]) < want:
					s.stock[key] = want


# ── 글 ──────────────────────────────────────────────────────────
## 규칙 조각들: "재난 ×0.5 · 고장 ×0.7 · 짓는 값 ×0.8 · …" (보통이면 빈 배열)
static func rule_parts(id: String) -> PackedStringArray:
	var r: Dictionary = find(id).get("rules", {})
	var out := PackedStringArray()
	var k_rules := [["hazard_k", "재난 ×%s", "재난 없음"], ["storm_k", "태양 폭풍 ×%s", "태양 폭풍 없음"], ["break_k", "고장 ×%s", ""],
		["cost_k", "짓는 값 ×%s", ""], ["support_k", "지구 지원 ×%s", ""], ["start_parts_k", "시작 부품 ×%s", ""],
		["start_support_k", "시작 지원 ×%s", ""], ["build_k", "짓기 ×%s", ""], ["rp_k", "연구 ×%s", ""]]
	for kr in k_rules:
		if not r.has(kr[0]):
			continue
		var v := float(r[kr[0]])
		if v <= 0.0 and String(kr[2]) != "":
			out.append(String(kr[2]))
		else:
			out.append(String(kr[1]) % _k(v))
	if r.has("morale"):
		out.append("사기 %+d" % int(round(float(r["morale"]))))
	if r.get("topup") is Dictionary:
		out.append("자원을 날마다 채움")
	if bool(r.get("no_fail", false)):
		out.append("지지 않음")
	elif r.has("trust_days"):
		out.append("신뢰 바닥 %d일이면 시드 정지" % int(r["trust_days"]))
	return out


static func _k(v: float) -> String:
	var t := "%.2f" % v
	while t.ends_with("0"):
		t = t.left(t.length() - 1)
	return t.trim_suffix(".")


## 한 줄 (메뉴·패널): "쉬움 — 재난 ×0.5 · 고장 ×0.7 · …" / "보통 — 디자인 문서의 규칙 그대로"
static func summary(col: Colonies) -> String:
	var id := id_of(col)
	var parts := rule_parts(id)
	var head := name_of(id) + (" (시나리오)" if in_scenario(col) else "")
	return head + " — " + (" · ".join(parts) if not parts.is_empty() else "디자인 문서의 규칙 그대로")
