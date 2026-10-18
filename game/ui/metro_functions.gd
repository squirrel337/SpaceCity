class_name MetroFunctions
extends RefCounted
## 지구 대도시의 우주 시설 (도시 기능) — 고른 식민지가 지구 지원 점수로 짓고 3단계까지 올린다 (data/earth_cities.json의 functions).
## 우주 산업 단지(부품)·이주 지원 센터(정착민)는 우주항으로 가는 항공편에 더 싣고, 우주 연구소(연구 점수)·우주 홍보관(지원 점수)은
## 지원을 낸 식민지에 날마다 보탠다. 공항 화물 터미널은 우주항 항공편을 더 자주 띄운다.
## 몫은 도시권 인구로 키우고 (√(인구/1000만)을 0.6~1.8로), 그 도시의 강점 시설이면 1.5배 더.
## 시뮬레이션(CitySim) 밖의 규칙이다 — 교통처럼 식민지의 비축·연구·지원에 더할 뿐이다.
## 대도시 운영 방식(modes — MetroModes)과 상업·금융(econ — MetroEconomy)도 여기서 하루를 보낸다.

const ORDER := ["space_park", "emigration", "research", "outreach", "cargo_hub"]
const MAX_LEVEL := 3
const STRENGTH_K := 1.5

var state := {}          # 대도시 key → 시설 id → {level, until(짓는 중이면 끝나는 게임 시각, 아니면 -1), payer(지원을 낸 부지 id)}
var last := {}           # 대도시 key → 어제의 몫 {parts, settlers, rp, support}
var _today := {}         # 오늘 지금까지의 몫 (하루가 끝나면 last가 된다)
var rev := 0             # 시설이 바뀔 때마다 +1 (3D 대도시·카드가 다시 그린다)
var modes := MetroModes.new()        # 운영 방식 (①우주 산업 수도 ③연구 동맹 ⑤비상 보급 기지)
var econ := MetroEconomy.new()       # 상업·금융
var _in_day := false                 # step_day 안 — 몫을 어제(last)에 적는다


static func defs() -> Dictionary:
	Metros.load_all()
	return Metros.functions


static func def(fac: String) -> Dictionary:
	return defs().get(fac, {})


static func fac_name(fac: String) -> String:
	return String(def(fac).get("name", fac))


static func fac_color(fac: String) -> Color:
	return Color(String(def(fac).get("color", "aab3c8")))


## 단계 lvl(1~3)의 자료
static func level_def(fac: String, lvl: int) -> Dictionary:
	var ls: Array = def(fac).get("levels", [])
	return ls[lvl - 1] if lvl >= 1 and lvl <= ls.size() else {}


## 몫의 배수: 도시권 인구 × 강점
static func scale(key: String, fac: String) -> float:
	var m := Metros.of(key)
	var k := clampf(sqrt(float(m.get("pop_m", 10.0)) / 10.0), 0.6, 1.8)
	if String(m.get("strength", "")) == fac:
		k *= STRENGTH_K
	return k


func reset() -> void:
	state = {}
	last = {}
	_today = {}
	modes.reset()
	econ.reset()
	rev += 1


## 식민지에서 자동으로 빼도 남겨야 하는 지원 — 그 식민지의 화물선·유인선 비용 (달 200, 화성 500, 타이탄 1,200)
static func colony_floor(sim: CitySim) -> float:
	var e: Dictionary = sim.C.get("earth", {})
	return maxf(float(e.get("cargo_cost_support", 150.0)), float(e.get("crewed_cost_support", 200.0)))


func _entry(key: String, fac: String) -> Dictionary:
	return (state.get(key, {}) as Dictionary).get(fac, {})


func level(key: String, fac: String) -> int:
	return int(_entry(key, fac).get("level", 0))


## 짓는 중이면 끝나는 게임 시각, 아니면 -1
func until(key: String, fac: String) -> int:
	return int(_entry(key, fac).get("until", -1))


func building(key: String, fac: String) -> bool:
	return until(key, fac) >= 0


## 짓는 몫 (0~1)
func progress(key: String, fac: String, hour: int) -> float:
	var u := until(key, fac)
	if u < 0:
		return 1.0
	var days := float(_entry(key, fac).get("days", level_def(fac, level(key, fac) + 1).get("days", 1)))
	return clampf(1.0 - float(u - hour) / (maxf(days, 1.0) * 24.0), 0.0, 1.0)


## 그 단계의 몫 (배수를 넣은 값): {parts_day, settlers, rp_day, support_day, every_h}
func output(key: String, fac: String, lvl: int = -1) -> Dictionary:
	if lvl < 0:
		lvl = level(key, fac)
	var out := {}
	if lvl <= 0:
		return out
	var ld := level_def(fac, lvl)
	var k := scale(key, fac)
	for f in ["parts_day", "settlers", "rp_day", "support_day"]:
		if ld.has(f):
			out[f] = float(ld[f]) * k
	if ld.has("every_h"):
		out["every_h"] = int(ld["every_h"])
	return out


## 몫을 읽기 좋은 글로: "부품 하루 6.4" · "정착민 한 편에 +32명" · "연구 하루 +5.6" · "지원 하루 +0.6" · "항공편 16시간마다"
static func output_text(o: Dictionary) -> String:
	var parts := PackedStringArray()
	if o.has("parts_day"):
		parts.append("부품 하루 +%s" % Fmt.n(float(o["parts_day"]), 1))
	if o.has("settlers"):
		parts.append("정착민 한 편에 +%d명" % int(round(float(o["settlers"]))))
	if o.has("rp_day"):
		parts.append("연구 하루 +%s" % Fmt.n(float(o["rp_day"]), 1))
	if o.has("support_day"):
		parts.append("지원 하루 +%s" % Fmt.n(float(o["support_day"]), 1))
	if o.has("every_h"):
		parts.append("항공편 %d시간마다" % int(o["every_h"]))
	return " · ".join(parts)


## 다음 단계의 지원 비용 (다 올렸으면 -1)
func next_cost(key: String, fac: String) -> float:
	var lvl := level(key, fac)
	if lvl >= MAX_LEVEL:
		return -1.0
	return float(level_def(fac, lvl + 1).get("cost", 0))


## 지을 수 없는 까닭 ("" = 지을 수 있다). sim = 지원을 낼 식민지
func block_reason(key: String, fac: String, sim: CitySim) -> String:
	if not defs().has(fac) or Metros.of(key).is_empty():
		return "없는 시설이다"
	if building(key, fac):
		return "짓는 중이다"
	var cost := next_cost(key, fac)
	if cost < 0.0:
		return "다 올렸다"
	if sim == null:
		return "지원을 낼 식민지가 없다"
	if sim.support < cost:
		return "지구 지원이 모자란다 (%s 필요, %s 있음)" % [Fmt.n(cost), Fmt.n(sim.support)]
	return ""


## 짓기·올리기: 고른 식민지(payer_index)가 지원을 내고, days만큼 뒤에 그 단계가 된다
func build(key: String, fac: String, col: Colonies, payer_index: int) -> bool:
	if payer_index < 0 or payer_index >= col.list.size():
		return false
	var sim: CitySim = col.list[payer_index]["sim"]
	if block_reason(key, fac, sim) != "":
		return false
	var lvl := level(key, fac)
	var ld := level_def(fac, lvl + 1)
	sim.support -= float(ld.get("cost", 0))
	var days := start_level(key, fac, col, String(col.list[payer_index]["site"]), false)
	var m := Metros.of(key)
	sim.note("%s %s %s — 지원 −%d, %s 완공 예정" % [String(m.get("name", key)), fac_name(fac),
		"짓기 시작" if lvl == 0 else "%d단계로 올리기 시작" % (lvl + 1), int(ld.get("cost", 0)),
		col.date_text(float(col.hour + days * 24))], "info")
	return true


## 다음 단계를 짓기 시작한다 (값은 부른 쪽이 이미 냈다) — 짓는 날을 돌려준다. auto: 운영 방식이 운영비로 지었다
func start_level(key: String, fac: String, col: Colonies, payer_site: String, auto: bool) -> int:
	var lvl := level(key, fac)
	var days := maxi(1, int(round(float(level_def(fac, lvl + 1).get("days", 10)) * modes.build_days_k())))
	if not state.has(key):
		state[key] = {}
	state[key][fac] = {"level": lvl, "until": col.hour + days * 24, "payer": payer_site, "days": days, "auto": auto}
	rev += 1
	return days


## 하루: 다 지은 시설은 다음 단계가 되고, 연구소·홍보관은 지원을 낸 식민지에 몫을 더한다
func step_day(col: Colonies) -> void:
	var hub_changed := false
	last = _today
	_today = {}
	_in_day = true
	for key in state:
		var facs: Dictionary = state[key]
		for fac in facs:
			var e: Dictionary = facs[fac]
			if int(e.get("until", -1)) >= 0 and col.hour >= int(e["until"]):
				e["level"] = int(e.get("level", 0)) + 1
				e["until"] = -1
				rev += 1
				if fac == "cargo_hub":
					hub_changed = true
				var ps := _payer(col, String(e.get("payer", "")))
				if ps != null:
					# 운영 방식이 운영비로 지은 것은 'info' (시간 건너뛰기를 멈추지 않게)
					ps.note("%s %s %d단계 완공 — %s" % [String(Metros.of(key).get("name", key)), fac_name(fac), int(e["level"]),
						output_text(output(key, fac))], "info" if bool(e.get("auto", false)) else "good")
				e.erase("days")
				e.erase("auto")
			var o := output(key, fac)
			if o.is_empty():
				continue
			var sim := _payer(col, String(e.get("payer", "")))
			if sim == null:
				continue
			if o.has("rp_day"):
				# 연구 동맹의 회원이면 동맹의 과제에 모은다 (과제가 없으면 식민지가 받는다)
				if modes.ally_member(key, col.hour, self) and modes.add_share(key, float(o["rp_day"]), col):
					_tally(last, key, "rp_ally", float(o["rp_day"]))
				else:
					sim.rp_bank += float(o["rp_day"])
					_tally(last, key, "rp", float(o["rp_day"]))
			if o.has("support_day"):
				# 우주 산업 수도는 그 도시 홍보관의 지원을 받지 않는다
				if modes.forfeits_outreach(key, col.hour):
					_tally(last, key, "forfeit", float(o["support_day"]))
				else:
					sim.support += float(o["support_day"])
					_tally(last, key, "support", float(o["support_day"]))
	modes.step_day(col, self)
	econ.step_day(col, self)
	_in_day = false
	if hub_changed:
		col.transport.rebuild(col)


## 3시간마다 (Colonies.step이 교통 뒤에 부른다): 비상 보급 기지가 식민지를 살핀다
func step_hour(col: Colonies) -> void:
	if not modes.metros.is_empty():
		modes.step_hour(col, self)


## 운영 방식·상업·금융의 몫을 적는다 (하루 안에서는 어제 몫에, 아니면 오늘 몫에)
func tally(key: String, what: String, v: float) -> void:
	_tally(last if _in_day else _today, key, what, v)


## 식민지를 잃었다 (Colonies.remove가 부른다)
func on_colony_removed(site: String, col: Colonies) -> void:
	modes.on_colony_removed(site, col)
	econ.on_colony_removed(site, col)
	rev += 1


## 지원을 낸 식민지 (없어졌으면 고향 — 목록의 처음)
func _payer(col: Colonies, site: String) -> CitySim:
	var i := col.index_of_site(site)
	if i < 0 and not col.list.is_empty():
		i = 0
	return col.list[i]["sim"] if i >= 0 else null


static func _tally(into: Dictionary, key: String, what: String, v: float) -> void:
	if not into.has(key):
		into[key] = {}
	into[key][what] = float(into[key].get(what, 0.0)) + v


## 우주항으로 가는 항공편: 한 편에 더 싣는 정착민·부품과 간격 (시설이 없으면 기본값).
## 부품은 운영 방식(우주 산업 수도)·동맹 기술(칩 신속 생산 라인)의 배수를 탄다 — hour < 0이면 준비 중이어도 센다
func feeder(key: String, base_every_h: int, hour: int = -1) -> Dictionary:
	var every := base_every_h
	var hub := output(key, "cargo_hub")
	if hub.has("every_h"):
		every = mini(every, int(hub["every_h"]))
	var o := {"every_h": every, "settlers": 0, "parts": 0.0}
	var em := output(key, "emigration")
	if em.has("settlers"):
		o["settlers"] = int(round(float(em["settlers"])))
	var sp := output(key, "space_park")
	if sp.has("parts_day"):
		o["parts"] = float(sp["parts_day"]) * every / 24.0 * modes.parts_k(key, hour)
	return o


## 항공편이 떠날 때 (교통이 부른다): 오늘의 몫에 더한다
func note_flight(key: String, parts: float, settlers: int) -> void:
	if parts > 0.0:
		_tally(_today, key, "parts", parts)
	if settlers > 0:
		_tally(_today, key, "settlers", float(settlers))


func levels_total(key: String) -> int:
	var n := 0
	for fac in state.get(key, {}):
		n += level(key, fac)
	return n


## 시설·운영 방식·상권·채권·펀드가 하나라도 있는 대도시들 (교통 탭이 늘어놓는다)
func keys_with_ops() -> Array:
	var keys := {}
	for k in active_keys():
		keys[k] = true
	for k2 in modes.metros:
		keys[k2] = true
	for d in [econ.commerce, econ.loans, econ.funds]:
		for k3 in d:
			keys[k3] = true
	var out := keys.keys()
	out.sort()
	return out


## 시설이 있거나 짓는 중인 대도시들
func active_keys() -> Array:
	var out := []
	for key in state:
		for fac in state[key]:
			if level(key, fac) > 0 or building(key, fac):
				out.append(key)
				break
	return out


func to_save() -> Dictionary:
	return {"state": state.duplicate(true), "modes": modes.to_save(), "econ": econ.to_save()}


func load_save(data: Dictionary) -> void:
	reset()
	var st: Variant = data.get("state", {})
	if st is Dictionary:
		for key in st:
			if Metros.of(String(key)).is_empty() or not st[key] is Dictionary:
				continue
			for fac in st[key]:
				var e: Variant = st[key][fac]
				if not defs().has(String(fac)) or not e is Dictionary:
					continue
				if not state.has(key):
					state[key] = {}
				var ent := {"level": clampi(int(e.get("level", 0)), 0, MAX_LEVEL), "until": int(e.get("until", -1)),
					"payer": String(e.get("payer", ""))}
				if e.has("days"):
					ent["days"] = maxi(1, int(e["days"]))
				if bool(e.get("auto", false)):
					ent["auto"] = true
				state[key][String(fac)] = ent
	modes.load_save(data.get("modes", {}) if data.get("modes") is Dictionary else {})
	econ.load_save(data.get("econ", {}) if data.get("econ") is Dictionary else {})
	rev += 1
