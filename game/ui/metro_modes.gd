class_name MetroModes
extends RefCounted
## 대도시 운영 방식 (data/earth_cities.json의 modes) — ①우주 산업 수도 ③연구 동맹 ⑤비상 보급 기지.
## 고른 식민지가 후원하고 운영비(지구 지원)를 맡기면 그 대도시가 스스로 일한다: 방식이 정한 시설부터 운영비로 올리고
## (가장 낮은 단계부터, 한 번에 하나), 방식마다의 일을 한다. 운영비가 바닥나면 쉰다. 시작하고 며칠은 준비 중이다.
## 식민지의 시뮬레이션(CitySim) 밖의 규칙이다 — 교통처럼 식민지의 비축·연구·지원에 더하고 뺄 뿐이다.
##   ① 항공편에 부품을 1.5배 싣는다. 달 식민지에 부품이 모자라면 우주항에 쌓인 부품을 급송 셔틀로 보내고 (운임은 운영비),
##      먼 행성으로 가는 수송선에는 부품을 사서 더 싣는다. 대신 그 도시 우주 홍보관의 지원은 들어오지 않는다.
##   ③ 연구소의 연구 점수를 동맹의 과제 하나에 모은다 (함께하는 도시가 많을수록 더). 식민지의 기술은 15% 싸게 마치고
##      모든 식민지가 알게 된다. 동맹만 여는 기술 다섯이 있다 (alliance).
##   ⑤ 우주항 옆 비상 창고에 산소·식량·물·부품을 사 모은다. 3시간마다 식민지를 살펴 산소·식량·물·전력이 위급하면
##      비상편을 띄운다: 달은 지구→달 셔틀로 (72시간), 다른 천체는 같은 천체의 이웃 도시가 남는 것을 나눈다.
## 협력 지역(반도체·AI 데이터센터 지역 하나)이 방식마다 몫을 키운다. 처음 찾아간 지역은 견학으로 연구 점수를 준다.
## 식민지에서 자동으로 빼는 돈(자동 채움)은 그 식민지의 화물선·유인선 비용 아래로 내려가지 않는다.

const KWH_T := 0.005                 # 비상 전지 1 kWh의 무게 (t)

var metros := {}        # 대도시 key → {mode, sponsor, budget, auto_fill, paused, ready_at, partner, depot{}, log[[시각, 글]]}
var alliance := {"project": "", "pool": 0.0, "done": {}}
var visited := {}       # 찾아간 지역 key → true
var rush_h := -100000   # 마지막 부품 급송 셔틀이 떠난 시각
var cool := {}          # 부지 → 비상편을 다시 띄울 수 있는 시각
var _noroute := {}      # 부지 → '길 없음' 알림을 다시 할 수 있는 시각
var short := {}         # 우주 식민지 부지 → 모자란 부품 (날마다 다시 센다)
var shares := {}        # 오늘 동맹에 모은 연구 점수 (대도시 key → 점수)
var last_gain := 0.0    # 어제 동맹이 모은 연구 점수
var rev := 0
var _st := {}           # 대도시 key → [시각표, 한 줄 상태] (status_short)


func reset() -> void:
	metros = {}
	alliance = {"project": "", "pool": 0.0, "done": {}}
	visited = {}
	rush_h = -100000
	cool = {}
	_noroute = {}
	short = {}
	shares = {}
	last_gain = 0.0
	_st = {}
	rev += 1


static func def(mode: String) -> Dictionary:
	return Metros.mode_def(mode)


static func rule(k: String, d: Variant) -> Variant:
	Metros.load_all()
	return Metros.mode_rules.get(k, d)


# ── 읽기 ───────────────────────────────────────────────────────
func entry(key: String) -> Dictionary:
	return metros.get(key, {})


func mode_of(key: String) -> String:
	return String(entry(key).get("mode", ""))


func budget(key: String) -> float:
	return float(entry(key).get("budget", 0.0))


func paused(key: String) -> bool:
	return bool(entry(key).get("paused", false))


func sponsor(key: String) -> String:
	return String(entry(key).get("sponsor", ""))


func partner_of(key: String) -> String:
	return String(entry(key).get("partner", ""))


## 준비가 끝났나 (hour < 0: 시각을 모를 때 — 노선을 짤 때 — 끝난 것으로)
func ready(key: String, hour: int) -> bool:
	var e := entry(key)
	return not e.is_empty() and (hour < 0 or hour >= int(e.get("ready_at", 0)))


## 일하는 중: 준비가 끝났고 쉬지 않는다
func working(key: String, hour: int, mode: String = "") -> bool:
	var e := entry(key)
	if e.is_empty() or bool(e.get("paused", false)) or not ready(key, hour):
		return false
	return mode == "" or String(e["mode"]) == mode


func keys_of(mode: String, hour: int = -1) -> Array:
	var out: Array = []
	for key in metros:
		if String(metros[key]["mode"]) == mode and (hour == -2 or working(String(key), hour)):
			out.append(String(key))
	out.sort()
	return out


## 하루 운영비 (협력 지역이 있으면 더)
func upkeep(key: String) -> float:
	var e := entry(key)
	if e.is_empty():
		return 0.0
	var up := float(def(String(e["mode"])).get("upkeep_day", 0.0))
	if String(e.get("partner", "")) != "":
		up += float(rule("partner_upkeep_day", 0.2))
	return up


## 자동 증설·창고 채우기 뒤에도 남기는 운영비
func keep(key: String) -> float:
	var k := upkeep(key) * float(rule("keep_days", 20))
	if mode_of(key) == "emergency_depot":
		k += float(def("emergency_depot").get("keep_extra", 60))
	return k


func done(id: String) -> bool:
	return alliance["done"].has(id)


## 동맹 기술의 효과 (곱)
func _ally_k(field: String) -> float:
	var k := 1.0
	for id in alliance["done"]:
		k *= float(Metros.alliance.get(id, {}).get(field, 1.0))
	return k


func freight_k() -> float:
	return _ally_k("freight_k")


func build_days_k() -> float:
	return _ally_k("build_days_k")


## 우주 산업 단지 부품의 배수 (항공편에 싣는 몫): 칩 신속 생산 라인 · 우주 산업 수도 1.5 × (1 + 협력 지역)
func parts_k(key: String, hour: int) -> float:
	var k := _ally_k("parts_k")
	if working(key, hour, "parts_capital"):
		k *= float(def("parts_capital").get("parts_x", 1.5)) * (1.0 + partner_bonus(key))
	return k


## 우주 산업 수도: 그 도시 우주 홍보관의 지원은 들어오지 않는다
func forfeits_outreach(key: String, hour: int) -> bool:
	return working(key, hour, "parts_capital")


## 연구 동맹의 회원: 일하는 중이고 연구소가 있다
func ally_member(key: String, hour: int, fn: MetroFunctions) -> bool:
	return working(key, hour, "research_alliance") and fn.level(key, "research") >= 1


# ── 협력 지역 ───────────────────────────────────────────────────
## 지역 r이 이 방식에 주는 몫 (①부품 ③동맹 몫, 0~max). ⑤는 경보 일수·창고로 따로
static func bonus_for(mode: String, r: Dictionary) -> float:
	Metros.load_all()
	var tb: Dictionary = Metros.tech_bonus.get(mode, {})
	if mode == "emergency_depot" or r.is_empty():
		return 0.0
	var b := 0.0
	for k in r.get("kinds", []):
		b += float(tb.get(String(k), 0.0))
	return minf(float(tb.get("max", 0.5)), b * float(r.get("scale", 1.0)))


static func alarm_days_for(r: Dictionary) -> int:
	Metros.load_all()
	var tb: Dictionary = Metros.tech_bonus.get("emergency_depot", {})
	var n := 0
	for k in r.get("kinds", []):
		if Metros.kind_group(String(k)) == "dc":
			n += int(tb.get("dc_days", 1))
	return mini(n, int(tb.get("dc_days_max", 2)))


static func parts_cap_k_for(r: Dictionary) -> float:
	Metros.load_all()
	var tb: Dictionary = Metros.tech_bonus.get("emergency_depot", {})
	for k in r.get("kinds", []):
		if String(k) in tb.get("parts_kinds", []):
			return float(tb.get("parts_cap_k", 1.5))
	return 1.0


## 협력 효과를 글로: "부품 +31%" · "동맹 몫 +45%" · "경보 2일 일찍 · 창고 부품 ×1.5" ("" = 효과 없음)
static func bonus_text(mode: String, r: Dictionary) -> String:
	match mode:
		"parts_capital":
			var b := bonus_for(mode, r)
			return "부품 +%d%%" % int(round(b * 100.0)) if b > 0.0 else ""
		"research_alliance":
			var b2 := bonus_for(mode, r)
			return "동맹 몫 +%d%%" % int(round(b2 * 100.0)) if b2 > 0.0 else ""
		"emergency_depot":
			var bits := PackedStringArray()
			var d := alarm_days_for(r)
			if d > 0:
				bits.append("경보 %d일 일찍" % d)
			if parts_cap_k_for(r) > 1.0:
				bits.append("창고 부품 ×%s" % Fmt.n(parts_cap_k_for(r), 1))
			return " · ".join(bits)
	return ""


## 협력 계약 비용 (운영비): 기본 × 규모, 가까우면 (150 km 안) 절반
static func partner_cost(metro_key: String, r: Dictionary) -> int:
	Metros.load_all()
	var c: Dictionary = Metros.tech_bonus.get("contract", {})
	var km := Metros.km_between(Metros.of(metro_key).get("dir", Vector3.UP), r.get("dir", Vector3.UP))
	var k := float(c.get("near_k", 0.5)) if km <= float(c.get("near_km", 150.0)) else 1.0
	return int(round(float(c.get("base", 80)) * float(r.get("scale", 1.0)) * k))


func partner_bonus(key: String) -> float:
	return bonus_for(mode_of(key), Metros.region(partner_of(key)))


## 협력 지역을 고른 대도시들 (지역 key → [대도시 key])
func partners_of_region(region_key: String) -> Array:
	var out: Array = []
	for key in metros:
		if String(metros[key].get("partner", "")) == region_key:
			out.append(String(key))
	out.sort()
	return out


# ── 하는 일 (플레이어) ───────────────────────────────────────────
## 운영 방식을 고른다 ("" = 직접 운영으로 되돌린다 — 남은 운영비와 창고를 판 값은 후원 식민지로).
## 처음 고르면 지금 고른 식민지가 후원한다. 다른 방식으로 바꾸면 후원·운영비·협력 지역은 그대로, 창고는 절반 값에 판다.
## 돌려주는 글: "" = 했다, 아니면 못 하는 까닭
func set_mode(key: String, mode: String, col: Colonies, index: int) -> String:
	if Metros.of(key).is_empty():
		return "없는 대도시다"
	var cur := mode_of(key)
	if mode == cur:
		return "이미 그 운영 방식이다" if mode != "" else ""
	if mode == "":
		_stop(key, col)
		return ""
	if not mode in Metros.MODE_IDS:
		return "없는 운영 방식이다"
	var ready_h := col.hour + int(rule("ready_days", 3)) * 24
	if cur == "":
		if index < 0 or index >= col.list.size():
			return "후원할 식민지가 없다"
		metros[key] = {"mode": mode, "sponsor": String(col.list[index]["site"]), "budget": 0.0, "auto_fill": false,
			"paused": false, "ready_at": ready_h, "partner": "", "depot": {}, "log": []}
	else:
		var e: Dictionary = metros[key]
		var sold := _sell_depot(e)
		e["budget"] = float(e["budget"]) + sold
		e["mode"] = mode
		e["ready_at"] = ready_h
		e["paused"] = false
		if sold > 0.0:
			_log(key, col, "비상 창고를 팔았다 — 운영비 +%s" % Fmt.n(sold, 0))
	_log(key, col, "「%s」 시작 — %d일 뒤부터 움직인다" % [Metros.mode_name(mode), int(rule("ready_days", 3))])
	rev += 1
	return ""


func _stop(key: String, col: Colonies) -> void:
	var e := entry(key)
	if e.is_empty():
		return
	var back := float(e.get("budget", 0.0)) + _sell_depot(e)
	var s := _sponsor_sim(col, e)
	var m := Metros.of(key)
	if s != null:
		s.support += back
		s.note("%s — 운영 방식 「%s」을(를) 멈췄다. 남은 운영비 %s를 돌려받았다" % [String(m.get("name", key)),
			Metros.mode_name(String(e["mode"])), Fmt.n(back, 0)], "info")
	metros.erase(key)
	rev += 1


func _sell_depot(e: Dictionary) -> float:
	var dep: Dictionary = e.get("depot", {})
	var cfg: Dictionary = def("emergency_depot").get("depot", {})
	var v := 0.0
	for k in dep:
		v += float(dep[k]) * float(cfg.get(k, {}).get("price", 0.0))
	e["depot"] = {}
	return v * float(def("emergency_depot").get("sell_back", 0.5))


## 운영비를 맡긴다 — 후원 식민지의 지구 지원에서 (채권이 밀려 있으면 못 맡긴다)
func deposit(key: String, amount: float, col: Colonies, fn: MetroFunctions) -> String:
	var e := entry(key)
	if e.is_empty():
		return "운영 방식을 먼저 고른다"
	var s := _sponsor_sim(col, e)
	if s == null:
		return "후원 식민지가 없다"
	if fn.econ.arrears_of(String(e["sponsor"])) > 0.0:
		return "채권이 밀려 있어 맡길 수 없다"
	if s.support < amount:
		return "지구 지원이 모자란다 (%s 필요, %s 있음)" % [Fmt.n(amount), Fmt.n(s.support)]
	s.support -= amount
	e["budget"] = float(e["budget"]) + amount
	if bool(e.get("paused", false)) and float(e["budget"]) >= upkeep(key) * float(rule("unpause_x", 3)):
		e["paused"] = false
	_log(key, col, "운영비 +%s (%s)" % [Fmt.n(amount), _site_name(String(e["sponsor"]))])
	rev += 1
	return ""


func set_auto_fill(key: String, on: bool) -> void:
	var e := entry(key)
	if not e.is_empty():
		e["auto_fill"] = on
		rev += 1


## 협력 지역을 고른다 ("" = 없앤다). 계약 비용은 운영비에서
func set_partner(key: String, region_key: String, col: Colonies) -> String:
	var e := entry(key)
	if e.is_empty():
		return "운영 방식을 먼저 고른다"
	if region_key == String(e.get("partner", "")):
		return ""
	if region_key == "":
		e["partner"] = ""
		_log(key, col, "협력 지역을 끝냈다")
		rev += 1
		return ""
	var r := Metros.region(region_key)
	if r.is_empty():
		return "없는 지역이다"
	var cost := float(partner_cost(key, r))
	if float(e["budget"]) < cost:
		return "운영비가 모자란다 (계약 %s, 운영비 %s)" % [Fmt.n(cost), Fmt.n(float(e["budget"]))]
	e["budget"] = float(e["budget"]) - cost
	e["partner"] = region_key
	var bt := bonus_text(String(e["mode"]), r)
	_log(key, col, "협력 지역: %s — 계약 %s%s" % [String(r["name"]), Fmt.n(cost), (" (" + bt + ")") if bt != "" else ""])
	rev += 1
	return ""


## 동맹의 과제를 고른다 ("" = 자동: 고향 식민지의 연구 순서)
func set_project(id: String, col: Colonies) -> String:
	if id != "" and project_cost(id, col) < 0.0:
		return "고를 수 없는 과제다"
	alliance["project"] = id
	rev += 1
	return ""


## 지역을 처음 찾아갔다: 견학 — 고른 식민지의 연구 점수 (게임마다 지역마다 한 번)
func visit(region_key: String, sim: CitySim) -> bool:
	var r := Metros.region(region_key)
	if r.is_empty() or visited.has(region_key) or sim == null:
		return false
	visited[region_key] = true
	var rp := float(Metros.tech_bonus.get("visit_rp", 30))
	sim.rp_bank += rp
	sim.note("견학 — %s (%s). 연구 +%d" % [String(r["name"]), Metros.kinds_text(r), int(rp)], "info")
	rev += 1
	return true


# ── 연구 동맹의 과제 ────────────────────────────────────────────
## 과제의 값 (식민지 기술은 할인한 값, 동맹 기술은 그대로) — 고를 수 없으면 −1
func project_cost(id: String, col: Colonies) -> float:
	if Metros.alliance.has(id):
		return -1.0 if done(id) else float(Metros.alliance[id].get("cost", 0))
	var t: Dictionary = GameData.TECHS.get(id, {})
	if t.is_empty():
		return -1.0
	var known := col.known_techs()
	if known.has(id):
		return -1.0
	for r in t.get("requires", []):
		if not known.has(r):
			return -1.0
	return float(t.get("cost", 0)) * float(def("research_alliance").get("tech_discount", 0.85))


static func project_name(id: String) -> String:
	if Metros.alliance.has(id):
		return String(Metros.alliance[id].get("name", id))
	return String(GameData.TECHS.get(id, {}).get("name", id))


## 지금의 과제 id (고른 것, 아니면 고향 식민지의 연구 순서에서 열 수 있는 첫 기술, 그다음 동맹 기술) — 없으면 ""
func project(col: Colonies) -> String:
	var p := String(alliance.get("project", ""))
	if p != "" and project_cost(p, col) >= 0.0:
		return p
	if p != "":
		alliance["project"] = ""
	var home := col.home()
	if not home.is_empty():
		for id in (home["sim"] as CitySim).research_queue:
			if project_cost(String(id), col) >= 0.0:
				return String(id)
	var best := ""
	var best_c := INF
	for id2 in GameData.TECHS:
		var c := project_cost(String(id2), col)
		if c >= 0.0 and c < best_c:
			best_c = c
			best = String(id2)
	if best != "":
		return best
	for id3 in Metros.alliance:
		if not done(String(id3)):
			return String(id3)
	return ""


## 고를 수 있는 과제들 [[id, 이름, 값, 동맹 기술인가]] (식민지 기술은 값 순서, 그다음 동맹 기술)
func projects(col: Colonies) -> Array:
	var out: Array = []
	for id in GameData.TECHS:
		var c := project_cost(String(id), col)
		if c >= 0.0:
			out.append([String(id), project_name(String(id)), c, false])
	out.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for id2 in Metros.alliance:
		if not done(String(id2)):
			out.append([String(id2), project_name(String(id2)), float(Metros.alliance[id2].get("cost", 0)), true])
	return out


## 회원 수에 따른 배수: 1 + 0.15 × (회원 − 1), 최대 1.6
func synergy(n: int) -> float:
	var d := def("research_alliance")
	return 1.0 + minf(float(d.get("synergy_max", 0.6)), float(d.get("synergy_per_member", 0.15)) * maxf(0.0, n - 1.0))


## 대도시의 연구소 몫을 동맹에 모은다 (MetroFunctions.step_day가 부른다 — 과제가 없으면 false: 식민지가 받는다)
func add_share(key: String, rp: float, col: Colonies) -> bool:
	if project(col) == "":
		return false
	shares[key] = float(shares.get(key, 0.0)) + rp * (1.0 + partner_bonus(key))
	return true


func _ally(col: Colonies) -> void:
	var n := shares.size()
	var gain := 0.0
	for k in shares:
		gain += float(shares[k])
	gain *= synergy(n) * _ally_k("alliance_k")
	shares = {}
	last_gain = gain
	if gain <= 0.0:
		return
	alliance["pool"] = float(alliance["pool"]) + gain
	var id := project(col)
	if id == "":
		return
	var cost := project_cost(id, col)
	if float(alliance["pool"]) < cost:
		return
	alliance["pool"] = float(alliance["pool"]) - cost
	if String(alliance.get("project", "")) == id:
		alliance["project"] = ""
	var members := keys_of("research_alliance", col.hour)
	var names := PackedStringArray()
	for k2 in members:
		names.append(String(Metros.of(k2).get("name", k2)))
	var home := col.home()
	var hs: CitySim = home["sim"] if not home.is_empty() else (col.list[0]["sim"] if not col.list.is_empty() else null)
	if Metros.alliance.has(id):
		alliance["done"][id] = true
		if hs != null:
			hs.note("연구 동맹 — 동맹 기술 「%s」 완성: %s" % [project_name(id), String(Metros.alliance[id].get("text", ""))], "good")
	else:
		for c in col.list:
			(c["sim"] as CitySim).techs[id] = true
		if hs != null:
			hs.note("연구 동맹 — 「%s」을(를) 함께 연구해 마쳤다 (%s). 모든 식민지가 안다" % [project_name(id), ", ".join(names)], "good")
	for k3 in members:
		_log(k3, col, "동맹 과제 「%s」 완성" % project_name(id))
	rev += 1


# ── 날마다 ──────────────────────────────────────────────────────
## 하루 (MetroFunctions.step_day가 시설·몫을 처리한 뒤에 부른다)
func step_day(col: Colonies, fn: MetroFunctions) -> void:
	_update_short(col)
	var ids := metros.keys()
	ids.sort()
	for key in ids:
		var e: Dictionary = metros[key]
		_fix_sponsor(col, e)
		var up := upkeep(key)
		var s := _sponsor_sim(col, e)
		# 자동 채움: 후원 식민지의 지원이 화물선·유인선 비용 + 여유를 넘을 때만
		var af: Dictionary = rule("auto_fill", {})
		if bool(e.get("auto_fill", false)) and s != null and fn.econ.arrears_of(String(e["sponsor"])) <= 0.0:
			var room := minf(float(af.get("per_day", 20)), float(af.get("target", 1000)) - float(e["budget"]))
			var spare := s.support - MetroFunctions.colony_floor(s) - float(af.get("margin", 100))
			var mv := minf(room, spare)
			if mv > 0.0:
				s.support -= mv
				e["budget"] = float(e["budget"]) + mv
				fn.tally(key, "fill", mv)
		# 운영비
		if float(e["budget"]) >= up:
			e["budget"] = float(e["budget"]) - up
			fn.tally(key, "upkeep", up)
			if bool(e.get("paused", false)) and float(e["budget"]) >= up * float(rule("unpause_x", 3)):
				e["paused"] = false
				_log(key, col, "운영비가 찼다 — 다시 움직인다")
				rev += 1
		elif not bool(e.get("paused", false)):
			e["paused"] = true
			_log(key, col, "운영비가 바닥났다 — 쉰다")
			if s != null:
				s.note("%s %s — 운영비가 바닥나 쉰다. 운영비를 맡기면 다시 움직인다" % [String(Metros.of(key).get("name", key)),
					Metros.mode_name(String(e["mode"]))], "warn")
			rev += 1
		if not working(key, col.hour):
			continue
		if String(e["mode"]) == "emergency_depot":
			_fill_depot(key, e, fn)
		_auto_build(key, e, col, fn)
	_ally(col)
	_rush(col, fn)


## 후원 식민지를 잃었으면 고향(목록의 처음)이 잇는다
func _fix_sponsor(col: Colonies, e: Dictionary) -> void:
	if col.index_of_site(String(e["sponsor"])) < 0 and not col.list.is_empty():
		e["sponsor"] = String(col.list[0]["site"])


func _sponsor_sim(col: Colonies, e: Dictionary) -> CitySim:
	var i := col.index_of_site(String(e.get("sponsor", "")))
	if i < 0 and not col.list.is_empty():
		i = 0
	return col.list[i]["sim"] if i >= 0 else null


## 방식이 정한 시설 가운데 가장 낮은 단계부터 하나씩 (운영비로, 다른 시설을 짓는 중이 아니면)
func _auto_build(key: String, e: Dictionary, col: Colonies, fn: MetroFunctions) -> void:
	for f in MetroFunctions.ORDER:
		if fn.building(key, f):
			return
	var best := ""
	var best_l := MetroFunctions.MAX_LEVEL
	for f2 in def(String(e["mode"])).get("build", []):
		var l := fn.level(key, String(f2))
		if l < best_l:
			best_l = l
			best = String(f2)
	if best == "":
		return
	var cost := fn.next_cost(key, best)
	if cost < 0.0 or float(e["budget"]) - cost < keep(key):
		return
	e["budget"] = float(e["budget"]) - cost
	var days := fn.start_level(key, best, col, String(e["sponsor"]), true)
	fn.tally(key, "build", cost)
	var lvl := fn.level(key, best) + 1
	var what := "%s %s" % [MetroFunctions.fac_name(best), "짓기 시작" if lvl == 1 else "%d단계로 올리기 시작" % lvl]
	_log(key, col, "%s — 운영비 −%s (%d일)" % [what, Fmt.n(cost), days])
	var s := _sponsor_sim(col, e)
	if s != null:
		s.note("%s %s — %s (운영비 −%s, %s 완공 예정)" % [String(Metros.of(key).get("name", key)),
			Metros.mode_name(String(e["mode"])), what, Fmt.n(cost), col.date_text(float(col.hour + days * 24))], "info")


## 자동으로 다음에 올릴 시설 ("" = 다 올렸다) — 짓는 중인 단계는 다 지은 것으로 친다 (그것이 끝나야 다음을 짓는다)
func next_build(key: String, fn: MetroFunctions) -> String:
	var best := ""
	var best_l := MetroFunctions.MAX_LEVEL
	for f in def(mode_of(key)).get("build", []):
		var l := fn.level(key, String(f)) + (1 if fn.building(key, String(f)) else 0)
		if l < best_l:
			best_l = l
			best = String(f)
	return best


## 그 시설을 자동으로 올리면 몇 단계가 되나
func next_level(key: String, fac: String, fn: MetroFunctions) -> int:
	return fn.level(key, fac) + (2 if fn.building(key, fac) else 1)


# ── ① 우주 산업 수도 ─────────────────────────────────────────────
## 우주 식민지의 부품 목표: 300과 (자동 운영이 남기는 부품 + 150) 가운데 큰 것
static func parts_target(sim: CitySim) -> float:
	return maxf(300.0, sim.auto_reserve + float(def("parts_capital").get("target_extra", 150)))


func _update_short(col: Colonies) -> void:
	short = {}
	for c in col.list:
		if String(c["body"]) == "earth":
			continue
		var s: CitySim = c["sim"]
		if s.population() <= 0.0:
			continue
		var site := String(c["site"])
		var have := float(s.stock.get("parts", 0.0)) + float(col.transport.incoming(site).get("parts", 0.0))
		var miss := parts_target(s) - have
		if miss > 0.0:
			short[site] = miss


## 그 천체의 식민지들이 모자란 부품
func short_on(col: Colonies, body: String) -> float:
	var n := 0.0
	for site in short:
		if Transport.node_body(String(site)) == body:
			n += float(short[site])
	return n


## 운임·부품값을 낼 우주 산업 수도 (일하는 중이고 운영비가 가장 많은 곳 — 내고도 keep을 남겨야)
func _payer_of(mode: String, cost: float, hour: int) -> String:
	var best := ""
	var best_b := -1.0
	for key in keys_of(mode, hour):
		var b := budget(key)
		if b - cost >= keep(key) and b > best_b:
			best_b = b
			best = key
	return best


## 부품 급송 셔틀: 달 식민지의 부품이 모자라고 정기 셔틀이 이틀 넘게 남았으면, 우주항에 쌓인 부품을 바로 보낸다 (주 1회)
func _rush(col: Colonies, fn: MetroFunctions) -> void:
	if keys_of("parts_capital", col.hour).is_empty():
		return
	var rc: Dictionary = def("parts_capital").get("rush", {})
	if col.hour - rush_h < int(rc.get("cooldown_h", 168)):
		return
	var tr := col.transport
	var l := tr.shuttle_line()
	if l.is_empty() or not tr.enabled or not bool(l["on"]):
		return
	var dir := Transport.earth_dir(l)
	var hub_sim := Transport._sim(col, String(l["a"] if dir == 0 else l["b"]))
	if hub_sim == null:
		return
	var need := short_on(col, "moon")
	if need < float(rc.get("min_short", 50)) or int(l["next"][dir]) - col.hour <= int(rc.get("wait_h", 48)):
		return
	var spare := float(hub_sim.stock.get("parts", 0.0)) - float(rc.get("keep_parts", 200))
	var n := floorf(minf(minf(need + 50.0, float(rc.get("cap_parts", 250))), spare))
	if n < 30.0:
		return
	var tons := n * float(Transport.cargo_rule("parts").get("t_per", 0.1))
	var cost := tons * Transport.freight_per_t() * freight_k()
	var payer := _payer_of("parts_capital", cost, col.hour)
	if payer == "":
		return
	var t := tr.dispatch(col, String(l["id"]), dir, {"parts": n}, "rush")
	if t.is_empty():
		return
	hub_sim.stock["parts"] = float(hub_sim.stock.get("parts", 0.0)) - n
	metros[payer]["budget"] = budget(payer) - cost
	fn.tally(payer, "rush", cost)
	rush_h = col.hour
	var port := String(t["to"])
	_log(payer, col, "부품 급송 셔틀 — 부품 %s, 운임 −%s" % [Fmt.n(n), Fmt.n(cost, 1)])
	var ps := Transport._sim(col, port)
	if ps != null:
		ps.note("부품 급송 셔틀 출발 — 부품 %s, %s 도착 (%s 우주 산업 수도가 운임 %s를 냈다)" % [Fmt.n(n),
			col.date_text(float(t["arrive"])), String(Metros.of(payer).get("name", payer)), Fmt.n(cost, 1)], "info")
	rev += 1


## 행성간 수송선이 떠날 때 (Transport가 부른다): 우주 산업 수도가 그 천체의 모자란 부품을 사서 더 싣는다 (부품값·운임은 운영비)
func ship_parts(col: Colonies, body: String, room_t: float, fn: MetroFunctions) -> float:
	if keys_of("parts_capital", col.hour).is_empty() or room_t < 1.0:
		return 0.0
	var sc: Dictionary = def("parts_capital").get("ship", {})
	var t_per := float(Transport.cargo_rule("parts").get("t_per", 0.1))
	var n := floorf(minf(minf(float(sc.get("max_parts", 400)), room_t / t_per), short_on(col, body)))
	var per := float(sc.get("cost_per_part", 0.5)) * freight_k()
	var payer := ""
	while n >= 10.0:
		payer = _payer_of("parts_capital", n * per, col.hour)
		if payer != "":
			break
		n = floorf(n * 0.5)
	if payer == "" or n < 10.0:
		return 0.0
	metros[payer]["budget"] = budget(payer) - n * per
	fn.tally(payer, "ship_parts", n * per)
	_log(payer, col, "%s행 수송선에 부품 %s을 사서 실었다 — 운영비 −%s" % [ColonyPanel.body_name(body), Fmt.n(n), Fmt.n(n * per, 0)])
	rev += 1
	return n


# ── ⑤ 비상 보급 기지 ─────────────────────────────────────────────
func depot_cap(key: String, kind: String, fn: MetroFunctions) -> float:
	var d := def("emergency_depot")
	var cfg: Dictionary = d.get("depot", {}).get(kind, {})
	var k := 1.0 + float(d.get("hub_k", 0.5)) * fn.level(key, "cargo_hub")
	if kind == "parts":
		k *= parts_cap_k_for(Metros.region(partner_of(key)))
	return float(cfg.get("cap", 0.0)) * k


func depot(key: String) -> Dictionary:
	return entry(key).get("depot", {})


func _fill_depot(key: String, e: Dictionary, fn: MetroFunctions) -> void:
	var d := def("emergency_depot")
	var hubk := 1.0 + float(d.get("hub_k", 0.5)) * fn.level(key, "cargo_hub")
	var dep: Dictionary = e["depot"]
	var spent := 0.0
	for kind in d.get("depot", {}):
		var cfg: Dictionary = d["depot"][kind]
		var have := float(dep.get(kind, 0.0))
		var n := minf(float(cfg.get("fill", 0.0)) * hubk, depot_cap(key, String(kind), fn) - have)
		var cost := n * float(cfg.get("price", 0.0))
		if n > 0.0 and float(e["budget"]) - cost >= keep(key):
			dep[kind] = have + n
			e["budget"] = float(e["budget"]) - cost
			spent += cost
	if spent > 0.0:
		fn.tally(key, "depot", spent)
		rev += 1


## 위급 경보를 며칠 일찍 알아채나 (위기 예측망 + 협력 지역의 데이터센터)
func alarm_plus(hour: int) -> int:
	var n := 0
	for id in alliance["done"]:
		n += int(Metros.alliance.get(id, {}).get("alarm_plus_days", 0))
	var best := 0
	for key in keys_of("emergency_depot", hour):
		best = maxi(best, alarm_days_for(Metros.region(partner_of(key))))
	return n + best


## 3시간마다 (Colonies.step이 교통 뒤에 부른다): 비상 보급 기지가 있으면 우주 식민지를 살펴 위급하면 비상편을 띄운다
func step_hour(col: Colonies, fn: MetroFunctions) -> void:
	var d := def("emergency_depot")
	if col.hour % maxi(1, int(d.get("scan_h", 3))) != 0:
		return
	var resp := keys_of("emergency_depot", col.hour)
	if resp.is_empty():
		return
	var plus := alarm_plus(col.hour)
	for c in col.list:
		if String(c["body"]) == "earth":
			continue
		var s: CitySim = c["sim"]
		var site := String(c["site"])
		if s.population() <= 0.0 or int(cool.get(site, -1)) > col.hour or col.transport.has_tagged(site, "emergency"):
			continue
		var why := PackedStringArray()
		var want := alarm_want(s, col.transport.incoming(site), plus, why)
		if want.is_empty():
			continue
		if not col.transport.enabled:
			if int(_noroute.get(site, -1)) <= col.hour:
				_noroute[site] = col.hour + 24 * 10
				s.note("비상 보급 — %s 위급하지만 교통이 꺼져 있어 비상편을 띄우지 못했다" % ", ".join(why), "warn")
			continue
		_respond(col, fn, c, want, why)


## 위급한 것과 보낼 양 {o2_kg, food_kg, water_kg, parts, kwh} — why에 까닭을 ("산소 4.8일")
func alarm_want(s: CitySim, inc: Dictionary, plus: int, why: PackedStringArray) -> Dictionary:
	var d := def("emergency_depot")
	var al: Dictionary = d.get("alarm_days", {})
	var tg: Dictionary = d.get("target_days", {})
	var pop := maxf(s.population(), 1.0)
	var out := {}
	var per_key := {"o2_kg": "o2_kg", "food_kg": "food_kg", "water_kg": "water_use_kg"}
	var names := {"o2_kg": "산소", "food_kg": "식량", "water_kg": "물"}
	for k in ["o2_kg", "food_kg", "water_kg"]:
		if k == "o2_kg" and s.open_air:
			continue
		var per := float(s.PER.get(per_key[k], 0.0))
		if per <= 0.0:
			continue
		var have := float(s.stock.get(k, 0.0))
		var days := have / (pop * per)
		if days >= float(al.get(k, 0)) + plus:
			continue
		if k == "food_kg":
			# 식민지가 스스로 식량 급송선을 부를 수 있으면 맡긴다 (이미 오거나, 지원이 넉넉하고 3일 넘게 남았으면)
			if s.express_eta != null:
				continue
			if s.support >= float(s.C["earth"].get("express_cost_support", 300)) and days >= 3.0:
				continue
		var amt := float(tg.get(k, 15)) * pop * per - have - float(inc.get(k, 0.0))
		if s.caps.has(k):
			amt = minf(amt, float(s.caps[k]) * 0.98 - have - float(inc.get(k, 0.0)))
		if amt > 1.0:
			out[k] = floorf(amt)
			why.append("%s %s일" % [names[k], Fmt.n(days, 1)])
	# 전력: 지금 전기가 모자라 끊고 (frac1 < 1) 축전이 15% 아래 — 고칠 부품과 비상 전지
	var cap := s.bat_cap + s.rfc_cap
	var soc := (s.battery + s.rfc) / maxf(cap, 1.0)
	if float(s.last_power.get("frac1", 1.0)) < 0.999 and soc < float(d.get("alarm_soc", 0.15)) and cap > 0.0:
		if float(s.stock.get("parts", 0.0)) + float(inc.get("parts", 0.0)) < 300.0:
			out["parts"] = float(d.get("power_parts", 60))
		var kwh := floorf(minf(float(d.get("power_kwh", 600)), cap - s.battery - s.rfc))
		if kwh > 10.0:
			out["kwh"] = kwh
		why.append("전력 축전 %d%%" % int(soc * 100.0))
	return out


## 비상편: 달은 지구 우주항에서 셔틀로 (창고에서, 모자라면 비싸게 사서), 다른 천체는 같은 천체 이웃 도시가 나눈다
func _respond(col: Colonies, fn: MetroFunctions, c: Dictionary, want: Dictionary, why: PackedStringArray) -> void:
	var d := def("emergency_depot")
	var tr := col.transport
	var site := String(c["site"])
	var s: CitySim = c["sim"]
	var cargo := {}
	var cost := 0.0
	var payer := ""
	var t := {}
	if String(c["body"]) == "moon":
		var l := tr.shuttle_line()
		if not l.is_empty() and bool(l["on"]):
			var cap_t := float(Transport.mode(String(l["mode"])).get("cap_t", 25.0))
			# 창고가 가장 넉넉한 기지부터
			var best_k := ""
			var best_v := -1.0
			for key in keys_of("emergency_depot", col.hour):
				var v := 0.0
				for k in want:
					v += minf(float(want[k]), float(depot(key).get(k, 0.0)))
				if v > best_v:
					best_v = v
					best_k = key
			if best_k != "":
				var dep: Dictionary = metros[best_k]["depot"]
				var cfg: Dictionary = d.get("depot", {})
				var buy := 0.0
				var room_t := cap_t
				for k in ["o2_kg", "food_kg", "water_kg", "parts", "kwh"]:
					if not want.has(k) or room_t <= 0.01:
						continue
					var tp := KWH_T if k == "kwh" else float(Transport.cargo_rule(k).get("t_per", 0.001))
					var n := minf(float(want[k]), room_t / tp)
					var from_dep := minf(n, float(dep.get(k, 0.0)))
					var price := float(cfg.get(k, {}).get("price", 0.0)) if k != "kwh" else 0.3
					buy += (n - from_dep) * price * float(d.get("buy_x", 2.0))
					cargo[k] = floorf(n)
					room_t -= floorf(n) * tp
				var tons := Transport.cargo_t(cargo)
				cost = float(d.get("shuttle_fee", 100)) + buy + tons * Transport.freight_per_t() * freight_k()
				if budget(best_k) >= cost:
					payer = best_k
					var extra_h := 0
					var dir := Transport.earth_dir(l)
					var port := String(l["b"] if dir == 0 else l["a"])
					if port != site:
						extra_h = int(ceil(Transport.surface_km(port, site) / 2400.0 + 3.0))
					t = tr.dispatch(col, String(l["id"]), dir, cargo, "emergency", int(d.get("fast_trip_h", 72)) + extra_h, site)
					if not t.is_empty():
						for k2 in cargo:
							if dep.has(k2):
								dep[k2] = maxf(0.0, float(dep[k2]) - float(cargo[k2]))
	else:
		# 같은 천체에서 바로 이어진 이웃 도시가 남는 것을 나눈다
		var best_sib := -1
		var best_score := 0.0
		var best_cargo := {}
		var best_line := {}
		for j in col.list.size():
			var sc: Dictionary = col.list[j]
			if String(sc["site"]) == site or String(sc["body"]) != String(c["body"]):
				continue
			var l2 := tr.line_by_id("local:" + Transport._pair(String(sc["site"]), site))
			if l2.is_empty() or not bool(l2["on"]):
				continue
			var sib: CitySim = sc["sim"]
			var cap2 := float(Transport.mode(String(l2["mode"])).get("cap_t", 10.0))
			var cg := {}
			var score := 0.0
			for k3 in ["o2_kg", "food_kg", "water_kg", "parts"]:
				if not want.has(k3):
					continue
				var spare := float(sib.stock.get(k3, 0.0)) - Transport._need(sib, Transport.cargo_rule(k3))
				var tp2 := float(Transport.cargo_rule(k3).get("t_per", 0.001))
				var n2 := floorf(minf(minf(float(want[k3]), spare), cap2 / tp2))
				if n2 >= 1.0:
					cg[k3] = n2
					cap2 -= n2 * tp2
					score += n2 / maxf(float(want[k3]), 1.0)
			if score > best_score:
				best_score = score
				best_sib = j
				best_cargo = cg
				best_line = l2
		if best_sib >= 0:
			cost = float(d.get("local_fee", 40))
			payer = _payer_of("emergency_depot", 0.0, col.hour)
			if payer != "" and budget(payer) >= cost:
				var sib2: CitySim = col.list[best_sib]["sim"]
				var src := String(col.list[best_sib]["site"])
				var dir2 := 0 if String(best_line["a"]) == src else 1
				t = tr.dispatch(col, String(best_line["id"]), dir2, best_cargo, "emergency")
				if not t.is_empty():
					Transport._load(sib2, best_cargo, 0.0)
					cargo = best_cargo
			else:
				payer = ""
	if t.is_empty() or payer == "":
		if int(_noroute.get(site, -1)) <= col.hour:
			_noroute[site] = col.hour + 24 * 10
			s.note("비상 보급 — %s 위급하지만 빨리 닿는 길이나 운영비가 없다 (같은 천체에 바로 이어진 이웃 도시가 없거나 비상 보급 기지의 운영비가 모자란다)" % ", ".join(why), "warn")
		return
	metros[payer]["budget"] = budget(payer) - cost
	fn.tally(payer, "relief", cost)
	cool[site] = col.hour + int(d.get("cooldown_h", 72))
	fn.econ.on_rescue()
	var what := Transport.cargo_text(cargo)
	_log(payer, col, "%s %s — 비상편 출발 (%s · 운영비 −%s)" % [Transport.node_name(site), ", ".join(why), what, Fmt.n(cost, 0)])
	s.note("비상 보급 — %s %s. %s 비상 보급 기지가 비상편을 띄웠다 (%s, %s 도착)" % [String(c["name"]), ", ".join(why),
		String(Metros.of(payer).get("name", payer)), what, col.date_text(float(t["arrive"]))], "critical")
	rev += 1


# ── 기록 ───────────────────────────────────────────────────────
func _log(key: String, col: Colonies, text: String) -> void:
	var e := entry(key)
	if e.is_empty():
		return
	var lg: Array = e["log"]
	lg.append([col.hour, text])
	while lg.size() > int(rule("log_max", 12)):
		lg.pop_front()


func log_of(key: String) -> Array:
	return entry(key).get("log", [])


## 한 줄 상태 (3D 운영 단지의 이름표·교통 탭): 준비 중 / 쉰다 / 방식마다의 일 — 하루에 한 번만 다시 센다
func status_short(key: String, col: Colonies, fn: MetroFunctions) -> String:
	var e := entry(key)
	if e.is_empty():
		return ""
	var stamp := "%d|%d|%d" % [floori(col.hour / 24.0), rev, fn.rev]
	var c: Array = _st.get(key, [])
	if not c.is_empty() and String(c[0]) == stamp:
		return String(c[1])
	var text := ""
	if not ready(key, col.hour):
		text = "준비 중 — %d일 남음" % maxi(1, ceili((int(e.get("ready_at", 0)) - col.hour) / 24.0))
	elif paused(key):
		text = "운영비 바닥 — 쉰다"
	else:
		match String(e["mode"]):
			"parts_capital":
				var miss := 0.0
				for site in short:
					miss += float(short[site])
				text = "식민지 부품 %s 모자람" % Fmt.n(miss) if miss >= 1.0 \
					else "부품 ×%s · 식민지 부품 넉넉" % Fmt.n(parts_k(key, col.hour), 2)
			"research_alliance":
				var id := project(col)
				if fn.level(key, "research") < 1:
					text = "연구소를 기다린다 — 아직 회원이 아니다"
				elif id == "":
					text = "모을 과제가 없다"
				else:
					var cost := maxf(1.0, project_cost(id, col))
					text = "「%s」 %d%%" % [project_name(id), int(minf(1.0, float(alliance["pool"]) / cost) * 100.0)]
			"emergency_depot":
				var fill := 0.0
				var n := 0
				for kind in def("emergency_depot").get("depot", {}):
					var cap := depot_cap(key, String(kind), fn)
					if cap > 0.0:
						fill += minf(1.0, float(depot(key).get(kind, 0.0)) / cap)
						n += 1
				text = "비상 창고 %d%% 찼다" % int(100.0 * fill / maxf(1.0, float(n)))
	_st[key] = [stamp, text]
	return text


static func _site_name(site: String) -> String:
	return Transport.node_name(site)


## 식민지를 잃었다: 후원은 고향이 잇고, 기다리던 비상편 시각은 지운다
func on_colony_removed(site: String, col: Colonies) -> void:
	for key in metros:
		_fix_sponsor(col, metros[key])
	cool.erase(site)
	_noroute.erase(site)
	rev += 1


# ── 저장 ───────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"v": 1, "metros": metros.duplicate(true), "alliance": {"project": String(alliance["project"]),
		"pool": float(alliance["pool"]), "done": alliance["done"].keys()}, "visited": visited.keys(), "rush_h": rush_h,
		"cool": cool.duplicate()}


func load_save(data: Dictionary) -> void:
	reset()
	var ms: Variant = data.get("metros", {})
	if ms is Dictionary:
		for key in ms:
			var e: Variant = ms[key]
			if Metros.of(String(key)).is_empty() or not e is Dictionary or not String(e.get("mode", "")) in Metros.MODE_IDS:
				continue
			var dep := {}
			var dd: Variant = e.get("depot", {})
			if dd is Dictionary:
				for k in dd:
					if def("emergency_depot").get("depot", {}).has(String(k)):
						dep[String(k)] = maxf(0.0, float(dd[k]))
			var lg: Array = []
			for row in e.get("log", []):
				if row is Array and row.size() >= 2:
					lg.append([int(row[0]), String(row[1])])
			var partner := String(e.get("partner", ""))
			if Metros.region(partner).is_empty():
				partner = ""
			metros[String(key)] = {"mode": String(e["mode"]), "sponsor": String(e.get("sponsor", "")),
				"budget": maxf(0.0, float(e.get("budget", 0.0))), "auto_fill": bool(e.get("auto_fill", false)),
				"paused": bool(e.get("paused", false)), "ready_at": int(e.get("ready_at", 0)), "partner": partner,
				"depot": dep, "log": lg}
	var al: Variant = data.get("alliance", {})
	if al is Dictionary:
		var p := String(al.get("project", ""))
		alliance["project"] = p if (Metros.alliance.has(p) or GameData.TECHS.has(p)) else ""
		alliance["pool"] = maxf(0.0, float(al.get("pool", 0.0)))
		for id in al.get("done", []):
			if Metros.alliance.has(String(id)):
				alliance["done"][String(id)] = true
	for rk in data.get("visited", []):
		if not Metros.region(String(rk)).is_empty():
			visited[String(rk)] = true
	rush_h = int(data.get("rush_h", -100000))
	var cl: Variant = data.get("cool", {})
	if cl is Dictionary:
		for site in cl:
			cool[String(site)] = int(cl[site])
	rev += 1
