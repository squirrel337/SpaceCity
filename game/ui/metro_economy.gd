class_name MetroEconomy
extends RefCounted
## 실제 도시의 상업·금융 (data/earth_cities.json의 economy와 cities[].districts) — 식민지의 지구 지원(support)으로 움직인다.
##   상업 — 우주 상점가: 그 도시의 상권(강남·명동, 긴자·신주쿠, 5번가…)에서 우주 상품을 판다. 계약 비용 한 번, 그다음 날마다 수입:
##     상업 지수(상권 무게의 합 × 도시권 인구 배수) × (기본 + 어제 그 도시에 닿은 국제선 승객) × 우주 화제 × 요일 × 달
##     (주말과 연말에 많이 판다). 수입은 계약한 식민지가 받는다 (채권이 밀려 있으면 그것부터 갚는다).
##   금융 — 우주 채권: 금융 지수(금융가 무게의 합 — 월가·시티 오브 런던이 1)가 클수록 많이·싸게 빌린다. 180일 동안 날마다 갚는다.
##          갚을 돈은 그 식민지의 화물선·유인선 비용 아래로 내려가며 빼지 않는다 — 모자라면 밀린다 (밀리면 새로 빌리거나 넣지 못한다).
##          우주 펀드: 넣은 돈이 '우주 산업 지수'를 따라 날마다 오르내린다. 기대 수익(해마다 약 7%)은 가장 싼 채권 이자보다 낮다 —
##          빌려서 굴려 벌 수는 없다. 가끔 폭락이 며칠 이어진다. 찾을 때 수수료 1%.
##   우주 화제 — 기술 완성·새 도시·비상 구조에 오르고 사망 사고에 떨어진다 (0.5~1.5, 날마다 1로 돌아간다).
## 식민지의 시뮬레이션(CitySim) 밖의 규칙이다. 지수와 펀드의 오르내림은 게임 씨앗으로 정해진다 (시뮬레이션의 난수를 쓰지 않는다).

var buzz := 1.0
var index := 1000.0              # 우주 산업 지수
var history: Array = []          # 지수 (최근 31일)
var crash_left := 0              # 폭락이 이어질 날
var commerce := {}               # 대도시 key → {site, since}
var loans := {}                  # 대도시 key → {site, amount, rate, pay, days_left, arrears, warned}
var funds := {}                  # 대도시 key → {site, paid, value}
var pax := {}                    # 대도시 key → 어제 닿은 국제선 승객
var _pax_today := {}
var _seen := {}                  # {techs, cols, deaths} — 어제까지 (화제의 변화)
var last_return := 0.0           # 어제 지수의 변화 (몫)
var seed_value := 2061
var rev := 0


func reset() -> void:
	buzz = 1.0
	index = 1000.0
	history = []
	crash_left = 0
	commerce = {}
	loans = {}
	funds = {}
	pax = {}
	_pax_today = {}
	_seen = {}
	last_return = 0.0
	rev += 1


static func cfg(k: String) -> Dictionary:
	Metros.load_all()
	return Metros.economy.get(k, {})


# ── 지수 ───────────────────────────────────────────────────────
## 상업 지수: 상권 무게의 합 × 도시권 인구 배수 (도쿄 3.1 · 서울 2.3 · 뉴욕 2.0 · 부산 0.5)
static func commerce_power(key: String) -> float:
	var w := 0.0
	for d in Metros.districts_of(key, "commerce"):
		w += float(d[4])
	return w * Metros.popscale(key)


## 금융 지수: 금융가 무게의 합 (상하이·싱가포르 1.7~1.9, 런던 1.85, 뉴욕·도쿄·홍콩 1.0, 서울 0.8)
static func finance_power(key: String) -> float:
	var w := 0.0
	for d in Metros.districts_of(key, "finance"):
		w += float(d[4])
	return w


static func commerce_cost(key: String) -> int:
	var c := cfg("commerce")
	return int(round(float(c.get("cost_base", 100)) + float(c.get("cost_per_power", 50)) * commerce_power(key)))


## 채권 조건 {amount, rate (총 이자 몫), pay (하루 갚는 돈), days}
static func loan_terms(key: String) -> Dictionary:
	var c := cfg("loan")
	var f := finance_power(key)
	var amount := clampf(roundf((float(c.get("base", 120)) + float(c.get("per_power", 200)) * f) / 10.0) * 10.0,
		float(c.get("min", 100)), float(c.get("max", 600)))
	var rate := clampf(float(c.get("rate_base", 0.14)) - float(c.get("rate_per_power", 0.05)) * f,
		float(c.get("rate_min", 0.04)), float(c.get("rate_max", 0.14)))
	var days := int(c.get("days", 180))
	return {"amount": amount, "rate": rate, "pay": amount * (1.0 + rate) / days, "days": days}


## 펀드의 하루 출렁임 (지수와 따로) — 금융 지수가 클수록 덜 출렁인다
static func fund_sigma(key: String) -> float:
	var c := cfg("fund")
	return float(c.get("sigma_base", 0.003)) + float(c.get("sigma_k", 0.004)) / maxf(finance_power(key), 0.3)


## 게임 씨앗·이름·날로 정해지는 0~1
func _u(name: String, day: int, i: int = 0) -> float:
	return float(absi(("%d|%s|%d|%d" % [seed_value, name, day, i]).hash()) % 100000) / 100000.0


## 정규 분포에 가까운 값 (세 균등 수의 합)
func _z(name: String, day: int) -> float:
	return (_u(name, day, 0) + _u(name, day, 1) + _u(name, day, 2) - 1.5) * 2.0


# ── 상업 ───────────────────────────────────────────────────────
## 오늘 상권 수입 (계약했다면) — 요일·달은 그 시각의 날짜로
func commerce_today(key: String, col: Colonies) -> float:
	var c := cfg("commerce")
	var kp := minf(float(pax.get(key, 0)) / 1000.0, float(c.get("kpax_max", 3.0)))
	var dt := Time.get_datetime_dict_from_unix_time(col.unix_at(float(col.hour)))
	var wd: Array = c.get("weekday", [])
	var wk := float(wd[int(dt["weekday"])]) if int(dt["weekday"]) < wd.size() else 1.0
	var mk := float(c.get("month", {}).get(str(int(dt["month"])), 1.0))
	return commerce_power(key) * (float(c.get("base", 0.2)) + float(c.get("per_kpax", 0.25)) * kp) * buzz * wk * mk


func open_commerce(key: String, col: Colonies, index: int) -> String:
	if commerce_power(key) <= 0.0:
		return "이 도시에는 상권 자료가 없다"
	if commerce.has(key):
		return "이미 우주 상점가가 있다"
	if index < 0 or index >= col.list.size():
		return "계약할 식민지가 없다"
	var s: CitySim = col.list[index]["sim"]
	var cost := float(commerce_cost(key))
	if s.support < cost:
		return "지구 지원이 모자란다 (%s 필요, %s 있음)" % [Fmt.n(cost), Fmt.n(s.support)]
	s.support -= cost
	var site := String(col.list[index]["site"])
	commerce[key] = {"site": site, "since": col.hour}
	s.note("%s 우주 상점가 계약 — 지원 −%s. 날마다 상권 수입이 들어온다" % [String(Metros.of(key).get("name", key)), Fmt.n(cost)], "info")
	rev += 1
	return ""


func close_commerce(key: String) -> void:
	if commerce.erase(key):
		rev += 1


# ── 금융 ───────────────────────────────────────────────────────
func arrears_of(site: String) -> float:
	var a := 0.0
	for key in loans:
		if String(loans[key]["site"]) == site:
			a += float(loans[key]["arrears"])
	return a


func loans_of(site: String) -> int:
	var n := 0
	for key in loans:
		if String(loans[key]["site"]) == site:
			n += 1
	return n


func borrow(key: String, col: Colonies, index: int) -> String:
	if finance_power(key) <= 0.0:
		return "이 도시에는 금융가 자료가 없다"
	if loans.has(key):
		return "이 도시에서 빌린 채권을 아직 갚는 중이다"
	if index < 0 or index >= col.list.size():
		return "빌릴 식민지가 없다"
	var site := String(col.list[index]["site"])
	if arrears_of(site) > 0.0:
		return "밀린 채권이 있어 새로 빌릴 수 없다"
	if loans_of(site) >= int(cfg("loan").get("max_per_colony", 3)):
		return "한 식민지는 채권을 %d건까지 빌린다" % int(cfg("loan").get("max_per_colony", 3))
	var t := loan_terms(key)
	var s: CitySim = col.list[index]["sim"]
	s.support += float(t["amount"])
	loans[key] = {"site": site, "amount": float(t["amount"]), "rate": float(t["rate"]), "pay": float(t["pay"]),
		"days_left": int(t["days"]), "arrears": 0.0, "warned": false}
	s.note("%s 우주 채권 — 지원 +%s을(를) 빌렸다. %d일 동안 날마다 %s씩 갚는다 (이자 %s%%)" % [
		String(Metros.of(key).get("name", key)), Fmt.n(float(t["amount"])), int(t["days"]), Fmt.n(float(t["pay"]), 2),
		Fmt.n(float(t["rate"]) * 100.0, 1)], "info")
	rev += 1
	return ""


func invest(key: String, amount: float, col: Colonies, index: int) -> String:
	if finance_power(key) <= 0.0:
		return "이 도시에는 금융가 자료가 없다"
	if index < 0 or index >= col.list.size():
		return "넣을 식민지가 없다"
	var site := String(col.list[index]["site"])
	var f: Dictionary = funds.get(key, {})
	if not f.is_empty() and String(f["site"]) != site:
		return "다른 식민지(%s)의 펀드다 — 그 식민지에서 넣는다" % Transport.node_name(String(f["site"]))
	if arrears_of(site) > 0.0:
		return "밀린 채권이 있어 넣을 수 없다"
	var mx := float(cfg("fund").get("max", 1500))
	if float(f.get("paid", 0.0)) + amount > mx:
		return "한 도시의 펀드에는 %s까지 넣는다" % Fmt.n(mx)
	var s: CitySim = col.list[index]["sim"]
	if s.support < amount:
		return "지구 지원이 모자란다 (%s 필요, %s 있음)" % [Fmt.n(amount), Fmt.n(s.support)]
	s.support -= amount
	if f.is_empty():
		f = {"site": site, "paid": 0.0, "value": 0.0}
		funds[key] = f
	f["paid"] = float(f["paid"]) + amount
	f["value"] = float(f["value"]) + amount
	s.note("%s 우주 펀드에 %s을(를) 넣었다" % [String(Metros.of(key).get("name", key)), Fmt.n(amount)], "info")
	rev += 1
	return ""


func withdraw(key: String, col: Colonies) -> String:
	var f: Dictionary = funds.get(key, {})
	if f.is_empty():
		return "넣은 펀드가 없다"
	var i := col.index_of_site(String(f["site"]))
	if i < 0:
		i = 0
	var s: CitySim = col.list[i]["sim"]
	var back := float(f["value"]) * (1.0 - float(cfg("fund").get("fee", 0.01)))
	s.support += back
	var gain := (float(f["value"]) / maxf(float(f["paid"]), 1.0) - 1.0) * 100.0
	s.note("%s 우주 펀드에서 %s을(를) 찾았다 (넣은 것 %s, %s%s%%)" % [String(Metros.of(key).get("name", key)), Fmt.n(back),
		Fmt.n(float(f["paid"])), "+" if gain >= 0.0 else "", Fmt.n(gain, 1)], "info")
	funds.erase(key)
	rev += 1
	return ""


# ── 날마다 ──────────────────────────────────────────────────────
## 국제선 승객이 그 대도시에 닿았다 (Transport가 부른다)
func note_pax(key: String, n: int) -> void:
	_pax_today[key] = int(_pax_today.get(key, 0)) + n


## 비상 구조 소식 (화제가 오른다)
func on_rescue() -> void:
	buzz = clampf(buzz + float(cfg("buzz").get("rescue", 0.02)), float(cfg("buzz").get("min", 0.5)),
		float(cfg("buzz").get("max", 1.5)))


func step_day(col: Colonies, fn: MetroFunctions) -> void:
	@warning_ignore("integer_division")
	var day := col.hour / 24
	pax = _pax_today
	_pax_today = {}
	# 우주 화제: 날마다 1로 돌아가고, 기술·새 도시에 오르고 사망 사고에 떨어진다
	var bz := cfg("buzz")
	var techs := col.known_techs().size()
	var cols := col.list.size()
	var deaths := 0
	for c in col.list:
		for cause in (c["sim"] as CitySim).deaths:
			deaths += int((c["sim"] as CitySim).deaths[cause])
	var d_tech := maxi(0, techs - int(_seen.get("techs", techs)))
	var d_col := maxi(0, cols - int(_seen.get("cols", cols)))
	var died := deaths > int(_seen.get("deaths", deaths))
	_seen = {"techs": techs, "cols": cols, "deaths": deaths}
	buzz += (1.0 - buzz) * float(bz.get("decay", 0.03)) + float(bz.get("tech", 0.04)) * d_tech \
		+ float(bz.get("colony", 0.1)) * d_col + (float(bz.get("death", -0.2)) if died else 0.0)
	buzz = clampf(buzz, float(bz.get("min", 0.5)), float(bz.get("max", 1.5)))
	# 우주 산업 지수: 작은 상승 기대 + 출렁임 + 소식, 가끔 며칠 이어지는 폭락
	var fc := cfg("fund")
	var sh: Dictionary = fc.get("shock", {})
	var r := float(fc.get("mu_day", 0.0003)) + float(fc.get("sigma_index", 0.009)) * _z("index", day) \
		+ float(sh.get("tech", 0.003)) * d_tech + float(sh.get("colony", 0.01)) * d_col \
		+ (float(sh.get("death", -0.015)) if died else 0.0)
	var cr: Dictionary = fc.get("crash", {})
	if crash_left > 0:
		r -= float(cr.get("day_drop", 0.015))
		crash_left -= 1
	elif _u("crash", day) < float(cr.get("chance", 0.0012)):
		crash_left = int(cr.get("days", 6))
		r -= float(cr.get("day_drop", 0.015))
		var told := {}
		for key in funds:
			var site0 := String(funds[key]["site"])
			var fs := _sim_of(col, site0)
			if fs != null and not told.has(site0):
				told[site0] = true
				fs.note("우주 산업 지수가 떨어지기 시작했다 — 우주 펀드가 며칠 동안 줄어든다 (%s)" % String(Metros.of(key).get("name", key)), "warn")
	last_return = r
	index *= 1.0 + r
	history.append(index)
	while history.size() > 31:
		history.pop_front()
	# 펀드
	for key in funds:
		var f: Dictionary = funds[key]
		var v0 := float(f["value"])
		f["value"] = maxf(v0 * (1.0 + r + fund_sigma(key) * _z(key, day)), float(fc.get("floor", 0.2)) * float(f["paid"]))
		fn.tally(key, "fund", float(f["value"]) - v0)
	# 상권
	for key in commerce.keys():
		var s := _sim_of(col, String(commerce[key]["site"]))
		if s == null:
			commerce.erase(key)
			continue
		var v := commerce_today(key, col)
		var site := String(commerce[key]["site"])
		var paid := _pay_arrears(site, v)
		s.support += v - paid
		fn.tally(key, "commerce", v)
	# 채권: 화물선·유인선 비용 아래로 내려가며 갚지 않는다 — 모자라면 밀린다
	for key2 in loans.keys():
		var l: Dictionary = loans[key2]
		var s2 := _sim_of(col, String(l["site"]))
		if s2 == null:
			loans.erase(key2)
			continue
		var due := float(l["arrears"]) + (float(l["pay"]) if int(l["days_left"]) > 0 else 0.0)
		var avail := maxf(0.0, s2.support - MetroFunctions.colony_floor(s2))
		var paid2 := minf(due, avail)
		s2.support -= paid2
		l["arrears"] = due - paid2
		l["days_left"] = maxi(0, int(l["days_left"]) - 1)
		fn.tally(key2, "loan", paid2)
		var nm := String(Metros.of(key2).get("name", key2))
		if float(l["arrears"]) > 0.01 and not bool(l.get("warned", false)):
			l["warned"] = true
			s2.note("%s 우주 채권 — 지원이 모자라 다 갚지 못했다 (밀린 것 %s). 밀린 동안 새로 빌리거나 넣지 못한다" % [nm,
				Fmt.n(float(l["arrears"]), 1)], "warn")
		elif float(l["arrears"]) <= 0.01:
			l["arrears"] = 0.0
			l["warned"] = false
			if int(l["days_left"]) <= 0:
				loans.erase(key2)
				s2.note("%s 우주 채권을 다 갚았다" % nm, "info")
	rev += 1


## 상권 수입이 들어오면 그 식민지의 밀린 채권부터 갚는다 — 갚은 몫을 돌려준다
func _pay_arrears(site: String, v: float) -> float:
	var left := v
	for key in loans:
		var l: Dictionary = loans[key]
		if String(l["site"]) != site or float(l["arrears"]) <= 0.0 or left <= 0.0:
			continue
		var p := minf(left, float(l["arrears"]))
		l["arrears"] = float(l["arrears"]) - p
		left -= p
	return v - left


func _sim_of(col: Colonies, site: String) -> CitySim:
	var i := col.index_of_site(site)
	return col.list[i]["sim"] if i >= 0 else null


## 식민지를 잃었다: 그 식민지의 상권 계약은 끝나고 빚은 사라지며, 펀드는 고향이 찾는다
func on_colony_removed(site: String, col: Colonies) -> void:
	for key in commerce.keys():
		if String(commerce[key]["site"]) == site:
			commerce.erase(key)
	for key2 in loans.keys():
		if String(loans[key2]["site"]) == site:
			loans.erase(key2)
	for key3 in funds.keys():
		if String(funds[key3]["site"]) == site and not col.list.is_empty():
			funds[key3]["site"] = String(col.list[0]["site"])
			withdraw(key3, col)
	rev += 1


## 30일 변화 (몫)
func index_change(days: int) -> float:
	if history.size() < 2:
		return 0.0
	var i := maxi(0, history.size() - 1 - days)
	return float(history[-1]) / maxf(float(history[i]), 1e-6) - 1.0


# ── 저장 ───────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"v": 1, "buzz": buzz, "index": index, "history": history.duplicate(), "crash_left": crash_left,
		"commerce": commerce.duplicate(true), "loans": loans.duplicate(true), "funds": funds.duplicate(true),
		"pax": pax.duplicate(), "seen": _seen.duplicate()}


func load_save(data: Dictionary) -> void:
	reset()
	buzz = clampf(float(data.get("buzz", 1.0)), 0.5, 1.5)
	index = maxf(1.0, float(data.get("index", 1000.0)))
	for v in data.get("history", []):
		history.append(float(v))
	crash_left = int(data.get("crash_left", 0))
	var cm: Variant = data.get("commerce", {})
	if cm is Dictionary:
		for key in cm:
			if not Metros.of(String(key)).is_empty() and cm[key] is Dictionary:
				commerce[String(key)] = {"site": String(cm[key].get("site", "")), "since": int(cm[key].get("since", 0))}
	var ln: Variant = data.get("loans", {})
	if ln is Dictionary:
		for key2 in ln:
			var l: Variant = ln[key2]
			if Metros.of(String(key2)).is_empty() or not l is Dictionary:
				continue
			loans[String(key2)] = {"site": String(l.get("site", "")), "amount": float(l.get("amount", 0.0)),
				"rate": float(l.get("rate", 0.0)), "pay": float(l.get("pay", 0.0)), "days_left": int(l.get("days_left", 0)),
				"arrears": maxf(0.0, float(l.get("arrears", 0.0))), "warned": bool(l.get("warned", false))}
	var fd: Variant = data.get("funds", {})
	if fd is Dictionary:
		for key3 in fd:
			var f: Variant = fd[key3]
			if Metros.of(String(key3)).is_empty() or not f is Dictionary:
				continue
			funds[String(key3)] = {"site": String(f.get("site", "")), "paid": maxf(0.0, float(f.get("paid", 0.0))),
				"value": maxf(0.0, float(f.get("value", 0.0)))}
	var px: Variant = data.get("pax", {})
	if px is Dictionary:
		for key4 in px:
			pax[String(key4)] = int(px[key4])
	var sn: Variant = data.get("seen", {})
	if sn is Dictionary:
		for k in sn:
			_seen[String(k)] = int(sn[k])
	rev += 1
