class_name CitySim
extends RefCounted
## 시대 0 도시 시뮬레이션. docs/design/sim/city_balance.py의 규칙을 줄 단위로 옮겼다.
## 같은 시드·같은 결정이면 파이썬 시뮬레이터와 같은 수치가 나온다 (tools/parity_check.py).
## 엔진 기능은 쓰지 않는다 — 노드·씬과 분리된 순수 규칙이다.

signal noted(hour: int, text: String, kind: String)

## 시장·상수도가 채우는 비축 → 한 사람이 하루에 쓰는 양의 열쇠 (파이썬 SUPPLY_PER와 같다)
const SUPPLY_PER := {"o2_kg": "o2_kg", "water_kg": "water_use_kg", "food_kg": "food_kg"}
const STOCK_KEYS := ["o2_kg", "water_kg", "h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "food_kg"]
const VARIABLE := ["electrolyzer", "sabatier", "water_recycler", "hydroponics"]   # 가동률이 시간마다 달라지는 계열
const CAUSES_KO := {"hypoxia": "산소 결핍", "co2": "이산화탄소 중독", "starvation": "기아"}
## 추천 운영의 건설 순서: 생명유지 → 대피·주거 → 전력 → 식량 → 나머지
const BUILD_PRIORITY := {
	"co2_scrubber": 0, "electrolyzer": 0, "water_recycler": 0,
	"storm_shelter": 1, "regolith_printer": 1, "medical_bay": 1,
	"regolith_dome": 2, "hab_module": 2,
	"rfc_unit": 3, "battery_bank": 3, "regolith_cover": 3, "solar_tower": 3,
	"fission_40kw": 3, "fission_1mw": 3, "radiator": 3,
	"hydroponics": 4, "tank_farm": 4, "food_store": 4,
}
const SHELTER_CHOICES := ["essential", "lottery", "council"]

var C: Dictionary
var M: Dictionary
var T: Dictionary
var PER: Dictionary
var start_unix := 0
var start_year := 2061.0         # 시작 날짜 (연, 소수) — 태양 활동 주기에 쓴다

## 부지 (data/city_sites.json): 도시 상수(C)에 덮어쓴 값과 시뮬레이션 보정. 달 시드 시티는 보정이 모두 1이다
var site_id := GameData.HOME_SITE
var site := {}
var sun_k := 1.0                 # 태양광 출력
var ice_k := 1.0                 # 얼음 채굴
var heat_k := 1.0                # 방열 능력
var build_k := 1.0               # 로봇 작업량
var contact_k := 1.0             # 지구 교신의 사기
var air_co2 := false             # 대기의 CO₂로 사바티에가 돈다 (화성)
var open_air := false            # 바깥 공기를 마신다 (지구): 산소를 쓰지 않고 내쉰 CO₂는 환기로 나간다
var supply := {}                 # 시장·상수도가 날마다 채우는 비축 (stock 열쇠 → 일수)
var night_h := 0.0               # 자전하는 천체의 밤 길이 (시) — 길면 자동 운영이 원자로·긴 축전을 고른다
var dust := PackedByteArray()    # 먼지 폭풍 시간 (1 = 폭풍)
var dust_factor := 1.0           # 폭풍 때 태양광 비율
var auto_reserve := 40.0         # 자동 운영이 남겨 두는 부품 — 보급이 드문 부지일수록 많이

var seed_value := 2061
var rng: PyRandom
var days := 0
var dark := PackedByteArray()
var hour := 0
var counts := {}
var broken := {}
var tiles := {}
var covered_habs := 0
var robots := 0
var robots_broken := 0
var queue: Array = []            # 건설 대기열: {"id", "rd", "rd_total", "print_t", "seq", "cost"}
var seq := 0
var stock := {}
var cohorts: Array = []          # [인원, 누적 선량 mSv, 귀환 대기]
var morale := 0.0
var trust := 0.0
var trust_memory := 0.0          # 사건이 남긴 신뢰의 흔적. 반감기 약 1년
var support := 0.0
var techs := {}                  # 완료한 기술 id -> true
var rp_bank := 0.0
var research_queue: Array = []
var farm_dark_h := 0
var crops_dead_until := -1
var prev := {2: true, 3: true, 4: true}
var next_cargo := 0
var next_crewed := 0
var express_eta: Variant = null
var rationing := false
var hungry_days := 0
var algae_food_share := 0.0
var recent_deaths := 0.0
var recent_exposure := 0.0
var p4_off_week: Array = []
var today := {}
var stats := {}
var deaths := {}
var max_co2 := 0.0
var min_reserve_days := 1e9
var notes: Array = []            # [시각(시간), 문장, 종류]
var daily: Array = []
var _daily_cols: Array = []       # 저장용 일별 기록 (열 이름 · 배수 · 줄) — 늘어난 날만 더 싼다
var _daily_k: Array = []
var _daily_rows: Array = []

# 파생값 — refresh()가 하루에 한 번 갱신한다
var wk := {}
var active := {}                 # 계열 -> 가동 중인(1기 이상) 모듈 id (데이터 순서). 0기를 건너뛰어도 합은 같다
var hourly := {}                 # 계열 합 중 한 시간마다 쓰는 것 (가동 수가 바뀌는 refresh 때만 다시 센다)
var caps := {}
var housing_cap := 0.0
var air := 0.0
var co2_floor := 0.0
var shelter_cap := 0.0
var bat_cap := 0.0
var rfc_cap := 0.0
var solar_kw := 0.0
var fission_kw := 0.0
var heat_cap := 0.0
var static_load := {}
var recovery := 0.0
var mining := 1.0
var battery := 0.0
var rfc := 0.0
var co2_air := 0.0

# 운영 방침 — 플레이어가 바꾼다 (기본값은 문서의 추천 운영)
var shed_soc := {4: 0.5, 3: 0.4, 2: 0.2}
var food_buffer_days := 40.0
var ration_below_days := 10.0
var express_below_days := 20.0
var queue_by_priority := true
var seat_limit_by_scrubbers := true

## 자동 운영 (AutoPolicy). null이면 플레이어가 짓고 연구를 고른다.
var autopilot: AutoPolicy = null
## 'variety' 자동 운영이 계열의 종류를 돌아가며 고르는 차례
var variety_turn := 0
## 대화형: 대피소가 모자란 대형 폭풍이면 대피 원칙을 플레이어에게 묻는다
var interactive := false
var pending_storm := {}
var trust_low_days := 0
var _day_pop := 0.0


func _init(p_seed: int = 2061, years: float = 3.0, policy_name: String = "", p_site: String = "",
		p_start_unix: int = -1) -> void:
	GameData.load_all()
	site_id = p_site if p_site != "" else GameData.HOME_SITE
	site = GameData.site(site_id)
	var rules: Dictionary = site.get("rules", {})
	C = GameData.site_constants(site_id)
	M = GameData.MODULES
	T = GameData.TECHS
	PER = C["per_person_day"]
	sun_k = float(rules.get("sun_k", 1.0))
	ice_k = float(rules.get("ice_k", 1.0))
	heat_k = float(rules.get("heat_k", 1.0))
	build_k = float(rules.get("build_k", 1.0))
	contact_k = float(rules.get("contact_k", 1.0))
	air_co2 = bool(rules.get("co2_air", false))
	open_air = bool(rules.get("open_air", false))
	supply = rules.get("supply_days", {})
	auto_reserve = 40 * maxf(1.0, float(C["earth"]["cargo_interval_days"]) / 60)
	var start_date: PackedStringArray = String(C["start"]["date"]).split("-")
	start_unix = Time.get_unix_time_from_datetime_dict({
		"year": int(start_date[0]), "month": int(start_date[1]), "day": int(start_date[2]),
		"hour": 0, "minute": 0, "second": 0})
	if p_start_unix >= 0:
		start_unix = p_start_unix          # 식민지: 원정대가 도착한 날
	var sd := Time.get_datetime_dict_from_unix_time(start_unix)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": sd["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	@warning_ignore("integer_division")
	start_year = sd["year"] + ((start_unix - jan1) / 86400) / 365.25
	seed_value = p_seed
	rng = PyRandom.new(p_seed)
	days = PyCompat.round_half_even(365.25 * years)
	var il: Dictionary = C["illumination"]
	night_h = float(il["day_h"]) * (1 - float(il["light_frac"])) if String(il.get("model", "ridge")) == "rotation" else 0.0
	if String(il.get("model", "ridge")) == "rotation":
		dark = rotation_schedule(days * 24 + 48, il)
	else:
		dark = illumination_schedule(PyRandom.new(p_seed * 7919 + 1), days * 24 + 48, il)
	if rules.has("dust"):
		dust = dust_schedule(PyRandom.new(p_seed * 104729 + 7), days * 24 + 48, rules["dust"])
		dust_factor = float(rules["dust"]["sun_factor"])
	var start: Dictionary = C["start"]
	if start.has("counts"):
		for mid in start["counts"]:
			if int(start["counts"][mid]):
				counts[mid] = int(start["counts"][mid])
	else:
		for mid in M:
			var n := int(M[mid]["start"])
			if n:
				counts[mid] = n
	for t in start["solar_tiles_used"]:
		tiles[t] = int(start["solar_tiles_used"][t])
	robots = int(C["robots"]["start"])
	for k in STOCK_KEYS:
		stock[k] = 0.0
	for k in start["stocks"]:
		stock[k] = float(start["stocks"][k])
	cohorts = [[float(start["population"]), 0.0, false]]
	morale = float(start["morale"])
	trust = float(start["trust"])
	support = float(C["earth"]["support_start"])
	next_cargo = int(C["earth"]["cargo_first_day"])
	next_crewed = int(C["earth"]["crewed_first_day"])
	if policy_name != "":
		autopilot = AutoPolicy.new(policy_name)
		autopilot.configure(self)
	refresh()
	battery = bat_cap
	rfc = 0.0
	co2_air = co2_floor


static func illumination_schedule(r: PyRandom, hours: int, il: Dictionary) -> PackedByteArray:
	## 시간별 그림자 여부(1 = 어두움). 평소엔 드물고 짧게, 남극 겨울엔 잦고 길게.
	var d := PackedByteArray()
	d.resize(hours)
	d.fill(0)
	var t := 0.0
	while t < hours:
		var day_of_year := fmod(t / 24.0, 365.25)
		var winter: bool = il["winter_day_of_year"][0] <= day_of_year and day_of_year < il["winter_day_of_year"][1]
		var gap: Array = il["winter_gap_h"] if winter else il["normal_gap_h"]
		t += r.uniform(gap[0], gap[1])
		var dark_h: Array = il["winter_dark_h"] if winter else il["normal_dark_h"]
		var length := r.uniform(dark_h[0], dark_h[1])
		for hh in range(int(t), mini(hours, int(t + length))):
			d[hh] = 1
		t += length
	return d


## 자전하는 천체의 낮과 밤 (1 = 어두움): 하루(day_h)의 앞 light_frac이 낮이고, 아침에 시작한다 — 파이썬과 같다.
## 40년치를 한 시간씩 세면 25 ms쯤 (새 게임에 도시마다) — 정수 p시간이 하루의 정수배에 맞으면(지구 24, 화성 1233 = 50일)
## 한 주기만 세고 이어 붙인다. 어느 시각도 낮밤 경계에 (40년 동안 어긋나는 만큼보다) 가깝지 않을 때만 — 그래서 한 시간씩 센 것과
## 한 칸도 다르지 않다. 아니면 끝까지 한 시간씩
static func rotation_schedule(hours: int, il: Dictionary) -> PackedByteArray:
	var day_h := float(il["day_h"])
	var light := float(il["light_frac"])
	var p := 0
	var drift := 0.0
	for k in range(1, 200):
		var c := roundi(k * day_h)
		if c >= hours or c > 20000:
			break
		var e := absf(c / day_h - k) * (float(hours) / c + 1.0)
		if c > 0 and e < 1e-7:
			p = c
			drift = e
			break
	var n := p if p > 0 else hours
	var d := PackedByteArray()
	d.resize(n)
	var margin := 1.0
	for hh in n:
		var f := fposmod((hh + 0.5) / day_h + 0.02, 1.0)
		d[hh] = 1 if f >= light else 0
		margin = minf(margin, minf(absf(f - light), minf(f, 1.0 - f)))
	if p > 0 and margin > drift + 1e-9:
		while d.size() < hours:
			d.append_array(d.slice(0, mini(d.size(), hours - d.size())))
		return d
	d.resize(hours)
	for hh in range(n, hours):
		d[hh] = 1 if fposmod((hh + 0.5) / day_h + 0.02, 1.0) >= light else 0
	return d


## 먼지 폭풍 시간 (1 = 폭풍): 해마다 rate_per_year번쯤, 한 번에 days[0]~days[1]일
static func dust_schedule(r: PyRandom, hours: int, dust_rule: Dictionary) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(hours)
	d.fill(0)
	var mean_gap_h := 8766.0 / float(dust_rule["rate_per_year"])
	var t := 0.0
	while t < hours:
		t += r.uniform(0.5 * mean_gap_h, 1.5 * mean_gap_h)
		var length := r.uniform(float(dust_rule["days"][0]), float(dust_rule["days"][1])) * 24.0
		for hh in range(int(t), mini(hours, int(t + length))):
			d[hh] = 1
		t += length
	return d


func solar_activity(year_value: float) -> float:
	## 0(극소기) ~ 1(극대기). 11년 주기, 극대기 2069년.
	var spe: Dictionary = C["spe"]
	return 0.5 + 0.5 * cos(2 * PI * (year_value - spe["cycle_max_year"]) / spe["cycle_years"])


# ── 데이터 접근 ────────────────────────────────────────────────────
func prov(mid: String, key: String, default: Variant = 0.0) -> Variant:
	return M[mid].get("provides", {}).get(key, default)


func recipe(mid: String, side: String, key: String) -> float:
	return float(M[mid].get("recipe", {}).get(side, {}).get(key, 0.0))


func family(mid: String) -> String:
	return GameData.FAM_OF.get(mid, mid)


## provides[key]가 0이 아닌 모듈 (데이터 순서)
func with_prov(key: String) -> Array:
	return GameData.WITH.get(key, [])


## 계열의 가동 중인 모듈마다 provides[key]를 곱해 더한다 (데이터 순서, 보통 덧셈 — 파이썬 fam_sum과 같다)
func fam_prov(fam: String, key: String) -> float:
	var total := 0.0
	for m in active[fam]:
		total += wk[m] * float(prov(m, key))
	return total


func fam_recipe(fam: String, side: String, key: String) -> float:
	var total := 0.0
	for m in active[fam]:
		total += wk[m] * recipe(m, side, key)
	return total


func fam_spec(fam: String, key: String) -> float:
	var total := 0.0
	for m in active[fam]:
		total += wk[m] * float(M[m][key])
	return total


func fam_n(fam: String) -> int:
	var n := 0
	for m in active[fam]:
		n += int(wk[m])
	return n


func priority_of(mid: String) -> int:
	var p: Variant = M[mid].get("priority")
	return int(p) if p != null else 0


# ── 파생값 (하루 한 번 갱신) ─────────────────────────────────────
func refresh() -> void:
	wk = {}
	for mid in M:
		wk[mid] = maxi(0, int(counts.get(mid, 0)) - int(broken.get(mid, 0)))
	active = {}
	for fam in GameData.FAMILY:
		var on: Array = []
		for m in GameData.FAMILY[fam]:
			if wk[m]:
				on.append(m)
		active[fam] = on
	hourly = {
		"o2_hydro": fam_recipe("hydroponics", "out", "o2_kg"), "o2_algae": fam_recipe("algae_reactor", "out", "o2_kg"),
		"o2_green": fam_recipe("green_commons", "out", "o2_kg"), "o2_mre": fam_recipe("mre_plant", "out", "o2_kg"),
		"e_o2": fam_recipe("electrolyzer", "out", "o2_kg"), "e_water": fam_recipe("electrolyzer", "in", "water_kg"),
		"sab_n": fam_n("sabatier"), "sab_h2": fam_recipe("sabatier", "in", "h2_kg"),
		"sab_co2": fam_recipe("sabatier", "in", "co2_kg"), "rec_day": fam_prov("water_recycler", "wastewater_kg_day"),
		"e_kw": fam_spec("electrolyzer", "power_kw"), "sab_kw": fam_spec("sabatier", "power_kw"),
		"rec_kw": fam_spec("water_recycler", "power_kw"), "hydro_kw": fam_spec("hydroponics", "power_kw"),
		"scrub_day": fam_prov("co2_scrubber", "co2_kg_day"), "hydro_n": fam_n("hydroponics"),
	}
	caps = {}
	for key in STOCK_KEYS:
		var total := 0.0
		for mid in with_prov("storage"):
			total += float(prov(mid, "storage", {}).get(key, 0.0)) * wk[mid]
		caps[key] = total
	housing_cap = 0.0
	for mid in with_prov("housing"):
		housing_cap += float(prov(mid, "housing")) * int(counts.get(mid, 0))
	air = maxf(1.0, housing_cap) * float(C["air_kg_per_housing"])
	co2_floor = ppm_to_kg(C["co2_ppm"]["floor"])
	var bonus := 1.5 if techs.has("shielding_2") else 1.0
	shelter_cap = 0.0
	for mid in with_prov("shelter"):
		var sh := float(prov(mid, "shelter"))
		if sh:
			if family(mid) == "storm_shelter":
				shelter_cap += sh * int(counts.get(mid, 0)) * bonus
			else:
				shelter_cap += sh * int(counts.get(mid, 0))
	bat_cap = fam_prov("battery_bank", "storage_kwh")
	rfc_cap = fam_prov("rfc_unit", "storage_kwh")
	var towers := 0
	var parts := []
	var tile_factor: Dictionary = C["illumination"]["tile_factor"]
	for t in tiles:
		towers += int(tiles[t])
		parts.append(float(tile_factor[t]) * int(tiles[t]))
	var factor := PyCompat.fsum(parts) / towers if towers else 0.0
	var boost := 1.2 if techs.has("tall_towers") else 1.0
	solar_kw = fam_prov("solar_tower", "generation_kw") * factor * boost * sun_k
	fission_kw = 0.0           # 일조와 상관없이 늘 같은 출력 (핵분열·동위원소·핵융합)
	for mid in with_prov("generation_kw"):
		if family(mid) != "solar_tower":
			fission_kw += float(prov(mid, "generation_kw")) * wk[mid]
	heat_cap = 0.0
	for mid in with_prov("heat_kw"):
		if prov(mid, "heat_kw"):
			heat_cap += float(prov(mid, "heat_kw")) * wk[mid]
	heat_cap *= heat_k
	var printing := false
	for item in queue:
		if item["print_t"] > 0:
			printing = true
			break
	var loads := {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
	var robots_powered := false
	for mid in M:
		if not wk[mid]:
			continue
		var p := priority_of(mid)
		var fam := family(mid)
		if not p or fam in VARIABLE:
			continue
		var kw: float = float(M[mid]["power_kw"]) * wk[mid]
		if fam == "regolith_printer" and not printing:
			kw *= 0.1
		elif fam == "mre_plant" and stock.get("regolith_t", 0.0) < recipe(mid, "in", "regolith_t"):
			kw = 0.0
		elif fam == "parts_fab" and stock.get("metal_t", 0.0) < recipe(mid, "in", "metal_t"):
			kw = 0.0
		elif fam == "robot_bay" and not robots_powered:
			kw += float(C["robots"]["power_kw"]) * (robots - robots_broken)
			robots_powered = true       # 로봇 충전은 정비고 계열 한 번만
		loads[p] += kw
	static_load = loads
	recovery = 0.98 if techs.has("closed_loop_ls2") else float(prov("water_recycler", "recovery"))
	mining = (1.4 if techs.has("polar_prospecting") else 1.0) * ice_k


func ppm_to_kg(ppm: float) -> float:
	return ppm / 1e6 * (air / 29.0) * 44.0


func co2_ppm() -> float:
	return (co2_air / 44.0) / (air / 29.0) * 1e6


func population() -> float:
	var total := 0.0
	for c in cohorts:
		total += c[0]
	return total


func year() -> float:
	return start_year + hour / 8766.0


func queued(mid: String) -> int:
	var n := 0
	for item in queue:
		if item["id"] == mid:
			n += 1
	return n


func planned(mid: String) -> int:
	return int(counts.get(mid, 0)) + queued(mid)


func crops_alive() -> bool:
	return hour >= crops_dead_until


func is_dark(h: int = -1) -> bool:
	var i := hour if h < 0 else h
	return i < dark.size() and dark[i] == 1


## 먼지 폭풍 중인가 (화성)
func in_dust_storm(h: int = -1) -> bool:
	var i := hour if h < 0 else h
	return i < dust.size() and dust[i] == 1


# ── 1시간 ──────────────────────────────────────────────────────
func step_hour(pop: float) -> void:
	var lit: float = 1.0 - (dark[hour] if hour < dark.size() else 0)
	if hour < dust.size() and dust[hour]:
		lit *= dust_factor
	var s := stock
	var h := 1.0 / 24.0

	# 가변 가동률: 전기분해기는 필요한 만큼, 사바티에·재활용기는 원료만큼
	var farms_on_before: bool = prev[2] and crops_alive()
	var hr := hourly
	var bio_o2: float = ((hr["o2_hydro"] if farms_on_before else 0.0)
		+ (hr["o2_algae"] if prev[2] else 0.0)
		+ (hr["o2_green"] if prev[4] else 0.0)
		+ (hr["o2_mre"] if prev[3] else 0.0))
	var want: float = (0.0 if open_air else pop * PER["o2_kg"]) - bio_o2 + maxf(0.0, 0.95 * caps["o2_kg"] - s["o2_kg"])
	var e_cap: float = hr["e_o2"]
	var u_elec := 0.0
	if e_cap:
		u_elec = minf(1.0, maxf(0.0, want) / e_cap)
	var water_need: float = hr["e_water"] * u_elec * h
	if water_need > s["water_kg"] and s["water_kg"] > 0:
		u_elec *= s["water_kg"] / water_need
	elif s["water_kg"] <= 0:
		u_elec = 0.0
	var n_sab: int = hr["sab_n"]
	var u_sab := 0.0
	if n_sab and air_co2:
		u_sab = maxf(0.0, minf(1.0, s["h2_kg"] / (hr["sab_h2"] * h)))     # CO₂는 대기에서
	elif n_sab:
		u_sab = maxf(0.0, minf(1.0, minf(s["h2_kg"] / (hr["sab_h2"] * h), s["co2_kg"] / (hr["sab_co2"] * h))))
	var rec_rate: float = hr["rec_day"] * h
	var u_rec := 0.0
	if rec_rate:
		u_rec = minf(1.0, s["wastewater_kg"] / rec_rate)
	var light_cut := 0.6 if (lit > 0 and techs.has("sunlight_piping")) else 1.0

	var loads: Dictionary = static_load.duplicate()
	loads[1] += (hr["e_kw"] * u_elec + hr["sab_kw"] * u_sab + hr["rec_kw"] * maxf(u_rec, 0.2))
	loads[2] += hr["hydro_kw"] * light_cut

	# 전력 배분: 정책 문턱으로 미리 끄고, 그래도 모자라면 낮은 순위부터 강제로 끈다
	var gen: float = solar_kw * lit + fission_kw
	battery = minf(battery, bat_cap)
	rfc = minf(rfc, rfc_cap)
	var stored := battery + rfc
	var total_cap := bat_cap + rfc_cap
	var soc := stored / total_cap if total_cap else 0.0
	var on := {1: true, 2: true, 3: true, 4: true}
	if gen < PyCompat.fsum(loads.values()):
		for p in [4, 3, 2]:
			if soc < shed_soc[p]:
				on[p] = false
	for p in [4, 3, 2]:
		if on[p] and _sum_on(loads, on) > gen + stored:
			on[p] = false
	var used := _sum_on(loads, on)
	var frac1 := 1.0
	if used > gen + stored:
		frac1 = (gen + stored) / loads[1] if loads[1] else 0.0
		used = gen + stored
		_add(stats, "brownout_h", 1)
		today["brownout"] = 1
	var run3 := 1.0 if on[3] else 0.0
	if used > heat_cap and on[3] and loads[3] > 0:      # 방열 한계: 산업부터 감속
		run3 = maxf(0.0, 1.0 - (used - heat_cap) / loads[3])
		used -= loads[3] * (1.0 - run3)
		_add(stats, "overheat_h", 1)
	var net := gen - used
	if net >= 0:
		var eff_b := float(prov("battery_bank", "efficiency", 1.0))
		var charge := minf(bat_cap - battery, net * eff_b)
		battery += charge
		var rest := net - charge / eff_b
		rfc = minf(rfc_cap, rfc + rest * float(prov("rfc_unit", "efficiency", 1.0)))
	else:
		var take := minf(battery, -net)
		battery -= take
		rfc = maxf(0.0, rfc + net + take)
	if lit == 0 and soc < 0.1:
		today["low_soc"] = 1
	if not on[4]:
		_add(today, "p4_off_h", 1)
	if not on[2]:
		_add(today, "p2_off_h", 1)
	last_power = {"gen": gen, "load": loads, "on": on, "frac1": frac1, "soc": soc, "lit": lit > 0}

	# 사람 (바깥 공기를 마시면 산소를 쓰지 않고, 내쉰 CO₂는 환기로 나간다)
	if not open_air:
		s["o2_kg"] -= pop * PER["o2_kg"] * h
		co2_air += pop * PER["co2_kg"] * h
	var use: float = pop * PER["water_use_kg"] * h
	s["water_kg"] -= use
	s["wastewater_kg"] += use
	s["food_kg"] -= pop * PER["food_kg"] * h * (C["rationing"]["consumption_factor"] if rationing else 1.0)

	# 식량·생물 (2·4순위)
	var bio_removal := 0.0
	var food := 0.0
	if on[2] and crops_alive():
		for m in active["hydroponics"]:
			var n_farm: int = wk[m]
			food += n_farm * recipe(m, "out", "food_kg") * h
			s["o2_kg"] += n_farm * recipe(m, "out", "o2_kg") * h
			bio_removal += n_farm * recipe(m, "in", "co2_kg") * h
			s["water_kg"] -= n_farm * recipe(m, "in", "water_kg") * h
	var algae := 0.0
	if on[2]:
		for m in active["algae_reactor"]:
			var n_algae: int = wk[m]
			var a: float = n_algae * recipe(m, "out", "food_kg") * h
			algae += a
			food += a
			s["o2_kg"] += n_algae * recipe(m, "out", "o2_kg") * h
			bio_removal += n_algae * recipe(m, "in", "co2_kg") * h
			s["water_kg"] -= n_algae * recipe(m, "in", "water_kg") * h
	if on[4]:
		for m in active["green_commons"]:
			var n_green: int = wk[m]
			s["o2_kg"] += n_green * recipe(m, "out", "o2_kg") * h
			bio_removal += n_green * recipe(m, "in", "co2_kg") * h
	s["food_kg"] += food
	_add(today, "food_made", food)
	if food > 0:
		algae_food_share = 0.98 * algae_food_share + 0.02 * (algae / food)

	# CO₂: 식물이 먼저 흡수하고, 나머지는 제거기가 농축 탱크로 옮긴다
	co2_air = maxf(co2_floor, co2_air - bio_removal)
	var scrub: float = hr["scrub_day"] * h * frac1
	var moved := minf(scrub, co2_air - co2_floor)
	co2_air -= moved
	s["co2_kg"] += moved

	# 1순위 화학 공정 (전력이 모자라면 frac1만큼만)
	var k := h * frac1
	for m in active["electrolyzer"]:
		var n_e: float = wk[m] * u_elec * k
		s["water_kg"] -= n_e * recipe(m, "in", "water_kg")
		s["o2_kg"] += n_e * recipe(m, "out", "o2_kg")
		s["h2_kg"] += n_e * recipe(m, "out", "h2_kg")
	for m in active["sabatier"]:
		var n_s: float = wk[m] * u_sab * k
		if not air_co2:
			s["co2_kg"] -= n_s * recipe(m, "in", "co2_kg")
		s["h2_kg"] -= n_s * recipe(m, "in", "h2_kg")
		s["ch4_kg"] += n_s * recipe(m, "out", "ch4_kg")
		s["water_kg"] += n_s * recipe(m, "out", "water_kg")
	var processed := minf(s["wastewater_kg"], rec_rate * frac1)
	s["wastewater_kg"] -= processed
	s["water_kg"] += processed * recovery

	# 3순위 산업
	if run3:
		var k3 := h * run3
		for m in active["ice_miner"]:
			s["water_kg"] += wk[m] * recipe(m, "out", "water_kg") * mining * k3
		for m in active["excavator"]:
			s["regolith_t"] += wk[m] * recipe(m, "out", "regolith_t") * k3
		for m in active["mre_plant"]:
			var n_m := minf(wk[m] * k3, s["regolith_t"] / recipe(m, "in", "regolith_t"))
			s["regolith_t"] -= n_m * recipe(m, "in", "regolith_t")
			s["metal_t"] += n_m * recipe(m, "out", "metal_t")
			s["o2_kg"] += n_m * recipe(m, "out", "o2_kg")
		for m in active["parts_fab"]:
			var n_p := minf(wk[m] * k3, s["metal_t"] / recipe(m, "in", "metal_t"))
			s["metal_t"] -= n_p * recipe(m, "in", "metal_t")
			s["parts"] += n_p * recipe(m, "out", "parts")

	# 저장 한도: 넘치는 수소·CO₂·메탄은 배출, 넘치는 폐수는 손실
	for key in ["h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "o2_kg", "water_kg", "food_kg"]:
		if s[key] > caps[key]:
			if key == "wastewater_kg":
				_add(stats, "wastewater_lost_kg", s[key] - caps[key])
			s[key] = caps[key]
	# 시장·상수도: 정해진 일수만큼의 비축을 늘 채운다 (저장 한도와 상관없이 — 바깥에 있다)
	for key in supply:
		var floor_kg: float = pop * PER[SUPPLY_PER[key]] * float(supply[key])
		if s[key] < floor_kg:
			s[key] = floor_kg

	# 작물: 72시간 넘게 전력을 못 받으면 고사
	farm_dark_h = 0 if (on[2] or not hr["hydro_n"]) else farm_dark_h + 1
	if farm_dark_h >= int(C["crops"]["dead_after_unpowered_h"]) and crops_alive():
		crops_dead_until = hour + int(C["crops"]["regrow_days"]) * 24
		_add(stats, "crop_losses", 1)
		trust_event(-3)
		note("작물 고사 — 수경 농장 전력이 72시간 끊겼다", "critical")

	hazards(pop)
	prev = {2: on[2], 3: on[3], 4: on[4]}
	hour += 1


var last_power := {}


func _sum_on(loads: Dictionary, on: Dictionary) -> float:
	var values := []
	for q in on:
		if on[q]:
			values.append(loads[q])
	return PyCompat.fsum(values)


func hazards(pop: float) -> void:
	var s := stock
	var ppm := co2_ppm()
	if ppm > max_co2:
		max_co2 = ppm
	var limits: Dictionary = C["co2_ppm"]
	if ppm > limits["warn"]:
		today["co2_warn"] = 1
	if ppm > limits["bad"]:
		_add(stats, "co2_bad_h", 1)
	if ppm > limits["lethal"]:
		kill(maxi(1, PyCompat.round_half_even(pop * 0.01)), "co2")
	if s["o2_kg"] < 0:
		s["o2_kg"] = 0.0
		kill(maxi(1, PyCompat.round_half_even(pop * 0.05)), "hypoxia")
	if s["water_kg"] < 0:
		s["water_kg"] = 0.0
		_add(stats, "no_water_h", 1)
	if s["food_kg"] < 0:
		s["food_kg"] = 0.0
		_add(stats, "no_food_h", 1)
		today["no_food"] = 1
	if pop:
		var reserve: float = s["o2_kg"] / (pop * PER["o2_kg"])
		if reserve < min_reserve_days:
			min_reserve_days = reserve


func kill(n: int, cause: String) -> void:
	var remaining := float(mini(n, int(population())))
	if remaining <= 0:
		return
	for cohort in cohorts:
		var take := minf(cohort[0], remaining)
		cohort[0] -= take
		remaining -= take
		_add(deaths, cause, take)
		if remaining <= 0:
			break
	cohorts = cohorts.filter(func(c): return c[0] > 0)
	recent_deaths = 1.0
	trust_event(-10)
	note("사망 — " + CAUSES_KO[cause], "death")


func trust_event(delta: float) -> void:
	trust_memory += delta


# ── 하루 ───────────────────────────────────────────────────────
func step_day(d: int) -> void:
	failures()
	work_robots()
	if autopilot != null:
		autopilot.decide(self, d)
	research()
	commerce()
	earth(d)
	space_weather(d)
	dose_and_departures()
	update_morale()
	record(d)
	refresh()


func failures() -> void:
	for mid in counts:
		var working: int = int(counts[mid]) - int(broken.get(mid, 0))
		var mtbf := float(M[mid].get("mtbf_days", 0.0))
		if working <= 0 or not mtbf:
			continue
		var failed := 0
		for _i in range(working):
			if rng.random() < 1.0 / mtbf:
				failed += 1
		if failed:
			broken[mid] = int(broken.get(mid, 0)) + failed
			_add(stats, "failures", failed)
			note("고장 — %s %d기" % [GameData.module_name(mid), failed], "warn")
	var working_robots := robots - robots_broken
	var robot_mtbf := float(C["robots"]["mtbf_days"])
	for _i in range(working_robots):
		if rng.random() < 1.0 / robot_mtbf:
			robots_broken += 1


func _repair_order(a: String, b: String) -> bool:
	var pa: float = priority_of(a) if priority_of(a) else 1.5
	var pb: float = priority_of(b) if priority_of(b) else 1.5
	if pa != pb:
		return pa < pb
	return a < b


func _queue_order(a: Dictionary, b: Dictionary) -> bool:
	var ka: int = BUILD_PRIORITY.get(family(a["id"]), 5)
	var kb: int = BUILD_PRIORITY.get(family(b["id"]), 5)
	if ka != kb:
		return ka < kb
	return a["seq"] < b["seq"]


func work_robots() -> void:
	var s := stock
	var speed := 1.5 if techs.has("autonomous_robots_2") else 1.0
	var rd: float = (robots - robots_broken) * speed * build_k
	var boost := 0.0           # 교통·로봇 시설: 자재와 로봇이 빨리 돌아 작업량이 는다 (합은 50%까지)
	for m in with_prov("build_boost"):
		boost += wk[m] * float(prov(m, "build_boost"))
	if boost:
		rd *= 1.0 + minf(boost, 0.5)
	var repair_parts := float(C["robots"]["repair_parts"])
	while robots_broken and s["parts"] >= repair_parts and rd >= 0.5:
		robots_broken -= 1
		s["parts"] -= repair_parts
		rd -= 0.5
	# 수리: 1순위 모듈 → 발전·저장·방열 → 2·3·4순위
	var order: Array = broken.keys()
	order.sort_custom(_repair_order)
	for mid in order:
		var repair: Dictionary = M[mid]["repair"]
		while broken[mid] and rd >= repair["rd"] and s["parts"] >= repair["parts"]:
			broken[mid] -= 1
			rd -= repair["rd"]
			s["parts"] -= repair["parts"]
	# 건설: 우선순위 정렬을 켜면 생명유지부터, 끄면 들어온 순서대로 작업량을 준다
	if queue_by_priority:
		queue.sort_custom(_queue_order)
	var print_cap: float = fam_prov("regolith_printer", "print_t_day")
	for item in queue:
		if rd <= 0 and print_cap <= 0:
			break
		var spend := minf(rd, item["rd"])
		item["rd"] -= spend
		rd -= spend
		if item["print_t"] > 0 and print_cap > 0:
			var printed := minf(print_cap, item["print_t"])
			item["print_t"] -= printed
			print_cap -= printed
	var done := []
	var waiting := []
	for item in queue:
		if item["rd"] <= 1e-9 and item["print_t"] <= 1e-9:
			done.append(item)
		else:
			waiting.append(item)
	queue = waiting
	for item in done:
		if item["id"] == "regolith_cover":
			covered_habs += 1
		elif item["id"] == "robot":
			robots += 1
		else:
			counts[item["id"]] = int(counts.get(item["id"], 0)) + 1
			_add(stats, "built", 1)
		note("완공 — " + GameData.module_name(item["id"]), "build")


func can_afford(cost: Dictionary, reserve: float = 40.0) -> bool:
	var s := stock
	if not (s["parts"] - float(cost.get("parts", 0.0)) >= reserve
			and s["regolith_t"] >= float(cost.get("regolith_t", 0.0))
			and s["metal_t"] >= float(cost.get("metal_t", 0.0))):
		return false
	for key in cost:
		if not key in ["parts", "regolith_t", "metal_t"] and float(s.get(key, 0.0)) < float(cost[key]):
			return false            # 물 등 (얼음 차폐 돔)
	return true


func build_block_reason(mid: String, reserve: float = 0.0) -> String:
	## 지금 지을 수 없으면 이유, 지을 수 있으면 빈 문자열
	var m: Dictionary = M[mid]
	if m["tech"] != null and not techs.has(m["tech"]):
		return "연구 필요: " + T[m["tech"]]["name"]
	if family(mid) == "solar_tower" and free_tile() == "":
		return "타워를 세울 능선 자리가 없다"
	if not can_afford(m["cost"], reserve):
		return "자재 부족"
	return ""


func enqueue(mid: String, tile: String = "", reserve: float = 40.0) -> bool:
	var m: Dictionary = M[mid]
	if m["tech"] != null and not techs.has(m["tech"]):
		return false
	if not can_afford(m["cost"], reserve):
		today["short_parts"] = 1
		return false
	for key in m["cost"]:
		stock[key] -= float(m["cost"][key])
	var print_t: float = float(m["cost"].get("regolith_t", 0.0)) if m.get("printed", false) else 0.0
	seq += 1
	queue.append({"id": mid, "rd": float(m["build_rd"]), "rd_total": float(m["build_rd"]),
		"print_t": print_t, "print_total": print_t, "seq": seq, "cost": m["cost"].duplicate(), "tile": tile})
	if tile != "":
		tiles[tile] = int(tiles.get(tile, 0)) + 1
	return true


func enqueue_special(kind: String, reserve: float = 40.0) -> bool:
	var s := stock
	seq += 1
	if kind == "regolith_cover":
		var need: Dictionary = C["regolith_cover"]
		if s["regolith_t"] < need["regolith_t"]:
			return false
		s["regolith_t"] -= need["regolith_t"]
		queue.append({"id": kind, "rd": float(need["build_rd"]), "rd_total": float(need["build_rd"]),
			"print_t": 0.0, "print_total": 0.0, "seq": seq, "cost": {"regolith_t": need["regolith_t"]}, "tile": ""})
		return true
	var robots_c: Dictionary = C["robots"]
	if kind == "robot" and techs.has("robot_fabrication") and s["parts"] >= robots_c["local_parts"] + reserve:
		s["parts"] -= robots_c["local_parts"]
		queue.append({"id": "robot", "rd": float(robots_c["local_rd"]), "rd_total": float(robots_c["local_rd"]),
			"print_t": 0.0, "print_total": 0.0, "seq": seq, "cost": {"parts": robots_c["local_parts"]}, "tile": ""})
		return true
	return false


## 다 지은 건물 하나를 헌다 (재건축 — 시뮬레이션 밖의 규칙이 부른다. 두 시뮬레이터의 자동 운영은 헐지 않는다).
## 성한 것을 헐고 (고장 수는 남은 수까지만), 지은 값의 부품·금속을 refund만큼 돌려받는다. 헐었으면 true
func demolish(mid: String, refund: float = 0.3) -> bool:
	var n := int(counts.get(mid, 0))
	if n <= 0 or family(mid) == "solar_tower":
		return false
	counts[mid] = n - 1
	if int(broken.get(mid, 0)) > n - 1:
		broken[mid] = n - 1
	if mid == "hab_module":
		covered_habs = mini(covered_habs, n - 1)
	var cost: Dictionary = M[mid]["cost"]
	for key in ["parts", "metal_t"]:
		if cost.has(key):
			stock[key] = float(stock.get(key, 0.0)) + float(cost[key]) * refund
	refresh()
	return true


func cancel_queued(index: int) -> void:
	## 플레이어가 대기열에서 뺀다. 손대지 않은 일이면 자재를 모두, 시작한 일이면 절반을 돌려받는다.
	if index < 0 or index >= queue.size():
		return
	var item: Dictionary = queue[index]
	var share := 1.0 if item["rd"] >= item["rd_total"] - 1e-9 else 0.5
	for key in item["cost"]:
		stock[key] += float(item["cost"][key]) * share
	if item.get("tile", "") != "":
		tiles[item["tile"]] = int(tiles[item["tile"]]) - 1
	queue.remove_at(index)


func free_tile() -> String:
	for tile in ["A", "B", "C"]:
		if int(tiles.get(tile, 0)) < int(C["illumination"]["tiles"][tile]):
			return tile
	return ""


func research() -> void:
	var prod := 0.8 + 0.4 * morale / 100
	var p4_share := 1.0 - float(today.get("p4_off_h", 0)) / 24.0
	var scientists := minf(fam_spec("research_lab", "crew"), population() * C["workforce_share"] * 0.3)
	var rp_direct := 0.0          # 연구원 없이 나오는 연구 (교신·천문대 등)
	for m in with_prov("rp_day"):
		if family(m) != "research_lab":
			rp_direct += wk[m] * float(prov(m, "rp_day"))
	var rp: float = (scientists * prod * p4_share
		+ rp_direct * p4_share
		+ C["earth"]["earth_rp_day"])
	last_rp = rp
	rp_bank += rp
	support += rp * C["earth"]["support_per_rp"]
	for _i in range(research_queue.size()):
		if research_queue.is_empty():
			break
		if techs.has(research_queue[0]):          # 다른 식민지에서 이미 알아냈다
			research_queue.pop_front()
			continue
		var tech: Dictionary = T[research_queue[0]]
		var missing := false
		for r in tech["requires"]:
			if not techs.has(r):
				missing = true
				break
		if missing:
			research_queue.append(research_queue.pop_front())   # 선행 기술이 없으면 뒤로
			continue
		if rp_bank < tech["cost"]:
			break
		rp_bank -= tech["cost"]
		techs[tech["id"]] = true
		research_queue.pop_front()
		note("연구 완료 — " + tech["name"], "good")
		break


var last_rp := 0.0


## 상업·교통 시설: 날마다 지구 지원 점수(금융·관광·교역)와 들여오는 자재(교역·첨단 제조).
## 4순위 시설은 절전으로 꺼진 시간만큼 덜 낸다 — 파이썬 commerce와 같다
func commerce() -> void:
	var share := 1.0 - float(today.get("p4_off_h", 0)) / 24.0
	var made := 0.0
	for m in with_prov("support_day"):
		made += wk[m] * float(prov(m, "support_day"))
	if made:
		support += made * share
	for m in with_prov("make"):
		var n: int = wk[m]
		if n:
			var k4 := share if priority_of(m) == 4 else 1.0
			var mk: Dictionary = prov(m, "make", {})
			for k in mk:
				stock[k] = float(stock.get(k, 0.0)) + n * float(mk[k]) * k4


func earth(d: int) -> void:
	var e: Dictionary = C["earth"]
	support += e["support_per_month"] / 30.0
	food_emergency(d)
	if d >= next_cargo:
		if support < e["cargo_cost_support"]:
			next_cargo = d + 30
			_add(stats, "cargo_skipped", 1)
			note("지원 점수 부족 — 화물선이 한 달 미뤄졌다", "warn")
		elif rng.random() < e["delay_chance"]:
			next_cargo = d + rng.randint(int(e["delay_days"][0]), int(e["delay_days"][1]))
			note("화물선 지연", "warn")
		else:
			support -= e["cargo_cost_support"]
			next_cargo = d + int(e["cargo_interval_days"])
			if rng.random() < e["loss_chance"]:
				_add(stats, "cargo_lost", 1)
				trust_event(-1)
				note("화물선 발사 실패 — 화물을 잃었다", "critical")
			else:
				deliver_cargo()
	if d >= next_crewed:
		next_crewed = d + int(e["crewed_interval_days"])
		var seats_back := float(e["crewed_seats"])
		for cohort in cohorts:
			if cohort[2] and seats_back:
				var go := minf(cohort[0], seats_back)
				cohort[0] -= go
				seats_back -= go
				_add(stats, "departed_dose", go)
				note("선량 한도에 닿은 %d명이 지구로 돌아갔다" % int(go), "warn")
		if morale < 40 and seats_back:
			var unhappy := minf(seats_back, PyCompat.round_half_even(population() * 0.1))
			send_home(unhappy)
			_add(stats, "departed_morale", unhappy)
			trust_event(-3)
			note("사기 저하 — %d명이 지구로 돌아갔다" % int(unhappy), "warn")
		cohorts = cohorts.filter(func(c): return c[0] > 0)
		if support < e["crewed_cost_support"]:
			_add(stats, "crewed_skipped", 1)
			note("지원 점수 부족 — 유인선이 오지 않았다", "warn")
			return
		var seats: int = mini(int(e["crewed_seats"]), int(housing_cap - population()))
		if seat_limit_by_scrubbers and not open_air:      # 바깥 공기를 마시면 제거기가 좌석을 막지 않는다
			var scrub: float = fam_prov("co2_scrubber", "co2_kg_day")
			seats = mini(seats, int(scrub / PER["co2_kg"] / 1.1 - population()))
		if seats > 0:
			support -= e["crewed_cost_support"]
			cohorts.append([float(seats), 0.0, false])
			_add(stats, "arrived", seats)
			note("유인 착륙선 도착 — %d명" % seats, "good")
		else:
			_add(stats, "crewed_unused", 1)
			note("유인선이 빈자리 없이 돌아갔다 — 주거나 CO₂ 제거 여유가 없다", "warn")


func food_emergency(d: int) -> void:
	## 배급과 긴급 보급선. 기아 사망은 식량 없이 14일이 지난 뒤부터 하루 2%.
	var e: Dictionary = C["earth"]
	var s := stock
	var need: float = population() * PER["food_kg"]
	var reserve: float = s["food_kg"] / need if need else 99.0
	var was_rationing := rationing
	rationing = reserve < ration_below_days
	if rationing and not was_rationing:
		note("식량 배급 시작 — 소비 70%", "warn")
	if express_eta != null and d >= int(express_eta):
		express_eta = null
		s["food_kg"] += e["express_capacity_units"] / e["food_units_per_t"] * 1000.0
		note("긴급 보급선 도착 — 식량 10 t", "good")
	elif (express_eta == null and reserve < express_below_days
			and next_cargo - d > reserve and support >= e["express_cost_support"]):
		_order_express(d)
	hungry_days = hungry_days + 1 if today.get("no_food", 0) else 0
	if hungry_days > int(C["starvation_grace_days"]):
		kill(maxi(1, PyCompat.round_half_even(population() * 0.02)), "starvation")


func _order_express(d: int) -> void:
	var e: Dictionary = C["earth"]
	support -= e["express_cost_support"]
	express_eta = d + int(e["express_days"])
	_add(stats, "express", 1)
	trust_event(-1)
	note("긴급 보급선 요청 — 지원 −%d, 7일 뒤 도착" % int(e["express_cost_support"]), "warn")


func request_express() -> bool:
	## 플레이어가 직접 부르는 긴급 보급선
	if express_eta != null or support < C["earth"]["express_cost_support"]:
		return false
	_order_express(current_day())
	return true


func send_home(n: float) -> void:
	## 사기가 떨어져 지구로 돌아가는 사람 (사망이 아님). 선량이 높은 사람부터.
	var order := range(cohorts.size())
	# 파이썬 sorted()는 안정 정렬이다 — 선량이 같으면 원래 순서를 지킨다
	order.sort_custom(func(a, b): return cohorts[a][1] > cohorts[b][1] or (cohorts[a][1] == cohorts[b][1] and a < b))
	for i in order:
		var cohort: Array = cohorts[i]
		var take := minf(cohort[0], n)
		cohort[0] -= take
		n -= take
		if n <= 0:
			break


func deliver_cargo() -> void:
	var e: Dictionary = C["earth"]
	var s := stock
	var capacity := int(e["cargo_capacity_units"])
	var horizon: float = e["cargo_interval_days"] + 15
	var produced: float = (fam_recipe("hydroponics", "out", "food_kg") * (1 if crops_alive() else 0)
		+ fam_recipe("algae_reactor", "out", "food_kg"))
	var deficit: float = (population() * PER["food_kg"] - produced) * horizon
	var reserve: float = population() * PER["food_kg"] * food_buffer_days
	var food_t := maxf(0.0, deficit + reserve - s["food_kg"]) / 1000.0
	var food_units := mini(capacity, int(ceil(food_t * e["food_units_per_t"])))
	s["food_kg"] += food_units / float(e["food_units_per_t"]) * 1000.0
	capacity -= food_units
	var robots_added := 0
	if not techs.has("robot_fabrication") and robots < 8 + population() / 40 and capacity >= 10:
		robots += 2
		robots_added = 2
		capacity -= 2 * int(C["robots"]["earth_units"])
	s["parts"] += capacity
	_add(stats, "cargo_delivered", 1)
	var text := "화물선 도착 — 식량 %.1f t, 부품 %d" % [food_units / float(e["food_units_per_t"]), capacity]
	if robots_added:
		text += ", 로봇 %d대" % robots_added
	note(text, "good")


func space_weather(d: int) -> void:
	var spe: Dictionary = C["spe"]
	var activity := solar_activity(year())
	var major: float = spe["major_rate_per_year"]["solar_min"] + spe["major_rate_per_year"]["added_at_solar_max"] * activity
	var minor: float = spe["minor_rate_per_year"]["solar_min"] + spe["minor_rate_per_year"]["added_at_solar_max"] * activity
	if d == int(spe["scripted_major_day"]) or rng.random() < major / 365.25:
		_incoming_storm(float(spe["major_dose_msv"]), "major")
	elif rng.random() < minor / 365.25:
		_incoming_storm(float(spe["minor_dose_msv"]), "minor")


func _incoming_storm(dose: float, kind: String) -> void:
	if interactive and kind == "major" and shelter_cap < population():
		pending_storm = {"dose": dose, "kind": kind, "seats": shelter_cap, "pop": population()}
		var warning: int = int(C["spe"]["warning_h_with_forecast" if techs.has("space_weather_forecast") else "warning_h"])
		note("태양 양성자 폭풍 경보 — %d시간 뒤 도착. 대피소 %d석, 정착민 %d명" % [warning, int(shelter_cap), int(population())], "critical")
		return
	solar_storm(dose, kind)


func resolve_storm(choice: String) -> void:
	## 대피소 추첨 — 프로토타입 규칙. 피폭 인원은 같고, 신뢰가 다르게 움직인다.
	##   essential: 필수 인력 먼저 (생명) — 공정성 논란, 신뢰 −2
	##   lottery: 추첨 (동의) — 기본
	##   council: 평의회에 맡긴다 (동의) — 3시간이 걸려 대피가 늦는다. 대피소 안 선량 2% → 10%, 신뢰 +3
	if pending_storm.is_empty():
		return
	var dose: float = pending_storm["dose"]
	var kind: String = pending_storm["kind"]
	pending_storm = {}
	match choice:
		"essential":
			trust_event(-2)
			note("대피 원칙: 필수 인력 먼저 — 공유지 연합이 반발한다", "warn")
			solar_storm(dose, kind)
		"council":
			trust_event(3)
			note("대피 원칙: 평의회 표결 — 결정이 늦어 대피소 안 선량이 늘었다", "warn")
			solar_storm(dose, kind, 0.10)
		_:
			note("대피 원칙: 추첨 — 결과를 모두가 받아들였다", "info")
			solar_storm(dose, kind)


func solar_storm(dose: float, kind: String, shelter_factor: float = -1.0) -> void:
	var pop := population()
	var exposed := maxf(0.0, pop - shelter_cap)
	var factor: float = C["spe"]["shelter_factor"] if shelter_factor < 0 else shelter_factor
	var exposed_share := exposed / pop if pop else 0.0
	for cohort in cohorts:
		cohort[1] += dose * factor + dose * (1 - factor) * exposed_share
	_add(stats, "spe_" + kind, 1)
	var label := "대형" if kind == "major" else "소형"
	if exposed > 0:
		_add(stats, "exposed_person_events", exposed)
		recent_exposure = 1.0
		trust_event(-20 * exposed_share if kind == "major" else -3 * exposed_share)
		note("태양 양성자 폭풍(%s) — 대피소 밖 %d명이 %d mSv 피폭" % [label, int(round(exposed)), int(dose)], "critical")
	else:
		trust_event(2)
		note("태양 양성자 폭풍(%s) — 전원 대피 완료" % label, "good")


func dose_and_departures() -> void:
	var rates: Dictionary = C["dose_msv_day"]
	var pop := population()
	var domes := 0.0              # 돔 계열 (두꺼운 차폐)
	var covered_more := 0.0       # 벽 자체가 피복인 거주 (인쇄 거주동 등)
	for m in with_prov("housing"):
		var dose_class := String(prov(m, "dose", ""))
		if family(m) == "regolith_dome" or dose_class == "dome":
			domes += int(counts.get(m, 0)) * float(prov(m, "housing"))
		elif dose_class == "covered":
			covered_more += int(counts.get(m, 0)) * float(prov(m, "housing"))
	var covered: float = mini(covered_habs, int(counts.get("hab_module", 0))) * float(prov("hab_module", "housing")) + covered_more
	var in_dome := minf(pop, domes)
	var in_covered := minf(pop - in_dome, covered)
	var bare := maxf(0.0, pop - in_dome - in_covered)
	var rate := 0.0
	if pop:
		rate = (in_dome * rates["dome"] + in_covered * rates["covered_hab"] + bare * rates["bare_hab"]) / pop
	last_dose_rate = rate
	for cohort in cohorts:
		cohort[1] += rate
		if not cohort[2] and cohort[1] >= C["career_dose_limit_msv"]:
			cohort[2] = true
			trust_event(-0.1 * cohort[0])
			note("선량 한도 도달 — %d명이 다음 유인선으로 귀환한다" % int(cohort[0]), "warn")


var last_dose_rate := 0.0


func update_morale() -> void:
	var target := 70.0
	var ppm := co2_ppm()
	var limits: Dictionary = C["co2_ppm"]
	if ppm > limits["bad"]:
		target -= 15
	elif ppm > limits["warn"]:
		target -= 5
	var pop := population()
	if pop:
		if not open_air and stock["o2_kg"] / (pop * PER["o2_kg"]) < 3:
			target -= 10
		if stock["food_kg"] / (pop * PER["food_kg"]) < 10:
			target -= 10
		var crowd := pop / maxf(1.0, housing_cap)
		target -= 15 if crowd > 1.0 else (5 if crowd > 0.95 else 0)
		if shelter_cap < pop:
			target -= 5
		var care := 0.0
		for m in with_prov("care"):
			care += wk[m] * float(prov(m, "care"))
		if care < pop:
			target -= 5
	if algae_food_share > 0.25:
		target -= 5
	if rationing:
		target -= C["rationing"]["morale_penalty"]
	var leisure := 0.0            # 공원·체육관·주방… (합쳐서 최대 +15)
	for m in with_prov("morale"):
		if family(m) != "comms_center":
			leisure += wk[m] * float(prov(m, "morale"))
	target += minf(15, leisure)
	var contact := 0.0            # 지구와의 연결 — 가동 중인 교신 계열 중 가장 좋은 것 하나
	for m in GameData.FAMILY["comms_center"]:
		if wk[m] and float(prov(m, "morale")) > contact:
			contact = float(prov(m, "morale"))
	target += contact * contact_k     # 지연이 길면 영상 통화가 안 된다
	p4_off_week.append(int(today.get("p4_off_h", 0)))
	if p4_off_week.size() > 7:
		p4_off_week = p4_off_week.slice(p4_off_week.size() - 7)
	var off_sum := 0
	for v in p4_off_week:
		off_sum += v
	if off_sum > 48:
		target -= 5
	target -= 20 * recent_deaths + 10 * recent_exposure
	for c in cohorts:
		if c[1] > 400:
			target -= 5
			break
	recent_deaths *= 0.97
	recent_exposure *= 0.97
	morale += (target - morale) * 0.1
	trust_memory *= 0.998
	trust += ((morale - 5 + trust_memory) - trust) * 0.05
	trust = maxf(0.0, minf(100.0, trust))
	trust_low_days = trust_low_days + 1 if trust < 10 else 0


func record(d: int) -> void:
	var pop := population()
	var s := stock
	var food_need: float = pop * PER["food_kg"]
	var total_cap := bat_cap + rfc_cap
	var dark_h := 0
	for hh in range(d * 24, mini(dark.size(), (d + 1) * 24)):
		dark_h += dark[hh]
	var dose_sum := 0.0
	for c in cohorts:
		dose_sum += c[0] * c[1]
	daily.append({
		"day": d,
		"population": pop,
		"o2_reserve_days": s["o2_kg"] / (pop * PER["o2_kg"]) if pop else 0.0,
		"co2_ppm": co2_ppm(),
		"food_self_sufficiency": float(today.get("food_made", 0.0)) / food_need if food_need else 0.0,
		"food_reserve_days": s["food_kg"] / food_need if food_need else 0.0,
		"water_t": s["water_kg"] / 1000.0,
		"storage_kwh": total_cap,
		"soc": (battery + rfc) / total_cap if total_cap else 0.0,
		"dark_h": dark_h,
		"farms_off_h": int(today.get("p2_off_h", 0)),
		"parts": s["parts"],
		"robots": robots,
		"housing": housing_cap,
		"shelter": shelter_cap,
		"morale": morale,
		"trust": trust,
		"techs": techs.size(),
		"avg_dose_msv": dose_sum / pop if pop else 0.0,
		"brownout_total_h": int(stats.get("brownout_h", 0)),
		"crop_losses_total": int(stats.get("crop_losses", 0)),
	})
	var near_miss: bool = (today.get("low_soc", 0) or today.get("co2_warn", 0) or today.get("brownout", 0)
		or (pop and s["o2_kg"] / (pop * PER["o2_kg"]) < 5)
		or (pop and s["food_kg"] / food_need < 7))
	_add(stats, "near_miss_days", 1 if near_miss else 0)
	_add(stats, "rationing_days", 1 if rationing else 0)
	today = {}


func note(text: String, kind: String = "info") -> void:
	notes.append([hour, text, kind])
	noted.emit(hour, text, kind)


func run() -> CitySim:
	## 파이썬 City.run()과 같은 순서로 정해진 기간을 돈다 (테스트·자동 운영용)
	for d in range(days):
		var pop := population()
		for _i in range(24):
			step_hour(pop)
		step_day(d)
	return self


func advance_hour() -> void:
	## 게임 루프용 한 시간. 하루가 끝나는 시간에 step_day를 부른다.
	if hour % 24 == 0:
		_day_pop = population()
	step_hour(_day_pop)
	if hour % 24 == 0:
		@warning_ignore("integer_division")
		step_day(hour / 24 - 1)


func current_day() -> int:
	@warning_ignore("integer_division")
	return hour / 24


func date_dict(at_hour: int = -1) -> Dictionary:
	var h := hour if at_hour < 0 else at_hour
	return Time.get_datetime_dict_from_unix_time(start_unix + h * 3600)


func date_text(at_hour: int = -1, with_time: bool = true) -> String:
	var dt := date_dict(at_hour)
	if with_time:
		return "%04d.%02d.%02d %02d:00" % [dt["year"], dt["month"], dt["day"], dt["hour"]]
	return "%04d.%02d.%02d" % [dt["year"], dt["month"], dt["day"]]


static func _add(counter: Dictionary, key: Variant, amount: Variant) -> void:
	counter[key] = counter.get(key, 0) + amount


func summary() -> Dictionary:
	var dsum := 0.0
	for v in deaths.values():
		dsum += v
	var morale_sum := 0.0
	for rec in daily:
		morale_sum += rec["morale"]
	return {
		"deaths": dsum,
		"crop_losses": int(stats.get("crop_losses", 0)),
		"exposed_person_events": float(stats.get("exposed_person_events", 0)),
		"max_co2_ppm": max_co2,
		"co2_bad_hours": int(stats.get("co2_bad_h", 0)),
		"brownout_hours": int(stats.get("brownout_h", 0)),
		"near_miss_days": int(stats.get("near_miss_days", 0)),
		"departed_dose": float(stats.get("departed_dose", 0)),
		"population_end": population(),
		"morale_avg": morale_sum / daily.size() if daily.size() else morale,
		"trust_end": trust,
		"techs": techs.size(),
		"express": int(stats.get("express", 0)),
		"built": int(stats.get("built", 0)),
	}


# ── 저장 ───────────────────────────────────────────────────────
const SAVE_FIELDS := ["seed_value", "days", "hour", "counts", "broken", "tiles", "covered_habs", "robots",
	"robots_broken", "queue", "seq", "stock", "cohorts", "morale", "trust", "trust_memory", "support", "techs",
	"rp_bank", "research_queue", "farm_dark_h", "crops_dead_until", "prev", "next_cargo", "next_crewed",
	"express_eta", "rationing", "hungry_days", "algae_food_share", "recent_deaths", "recent_exposure",
	"p4_off_week", "today", "stats", "deaths", "max_co2", "min_reserve_days", "notes", "daily", "battery", "rfc",
	"co2_air", "shed_soc", "food_buffer_days", "ration_below_days", "express_below_days", "queue_by_priority",
	"seat_limit_by_scrubbers", "pending_storm", "trust_low_days", "_day_pop", "variety_turn"]


func to_save() -> Dictionary:
	var data := {"version": 1, "rng": rng.get_state(),
		"autopilot": autopilot.name if autopilot != null else "", "site_id": site_id, "start_unix": start_unix}
	for f in SAVE_FIELDS:
		data[f] = get(f)
	data["daily"] = _pack_daily()
	return data


## 일별 기록을 저장에 작게: 열 이름 한 번과 줄마다 숫자 (실수는 1/1000 단위 정수 — 보고서의 평균에만 쓰는 기록이다).
## 저장 파일의 대부분이 이것이었다 (3년이면 식민지마다 1,100줄). 지난번에 싼 줄은 다시 싸지 않는다
func _pack_daily() -> Dictionary:
	if daily.is_empty():
		return {"cols": [], "k": [], "rows": []}
	if _daily_cols.is_empty() or _daily_rows.size() > daily.size():
		_daily_cols = (daily[0] as Dictionary).keys()
		_daily_k = []
		for c in _daily_cols:
			_daily_k.append(1 if typeof(daily[0][c]) == TYPE_INT else 1000)
		_daily_rows = []
	for i in range(_daily_rows.size(), daily.size()):
		var rec: Dictionary = daily[i]
		var row: Array = []
		for j in _daily_cols.size():
			var v: Variant = rec.get(_daily_cols[j], 0)
			row.append(int(v) if int(_daily_k[j]) == 1 else int(round(float(v) * 1000.0)))
		_daily_rows.append(row)
	return {"cols": _daily_cols, "k": _daily_k, "rows": _daily_rows}


static func from_save(data: Dictionary) -> CitySim:
	var years: float = float(data["days"]) / 365.25
	var sim := CitySim.new(int(data["seed_value"]), years, "", String(data.get("site_id", GameData.HOME_SITE)),
		int(data.get("start_unix", -1)))
	for f in SAVE_FIELDS:
		if data.has(f) and not (f == "daily" and data[f] is Dictionary):
			sim.set(f, data[f])
	if data.get("daily") is Dictionary:          # 시작 화면이 미리 풀었으면 이미 줄의 목록이다
		sim.daily = DailyPack.unpack(data["daily"])
	sim._restore_types()
	sim.rng.set_state(data["rng"])
	if String(data.get("autopilot", "")) != "":
		sim.autopilot = AutoPolicy.new(String(data["autopilot"]))
	sim.refresh()
	return sim


func _restore_types() -> void:
	## JSON을 거치면 정수 키가 문자열로, 정수가 실수로 바뀐다 — 되돌린다
	hour = int(hour)
	days = int(days)
	seq = int(seq)
	robots = int(robots)
	robots_broken = int(robots_broken)
	covered_habs = int(covered_habs)
	farm_dark_h = int(farm_dark_h)
	crops_dead_until = int(crops_dead_until)
	next_cargo = int(next_cargo)
	next_crewed = int(next_crewed)
	hungry_days = int(hungry_days)
	trust_low_days = int(trust_low_days)
	if express_eta != null:
		express_eta = int(express_eta)
	for d in [counts, broken, tiles]:
		for k in d:
			d[k] = int(d[k])
	prev = {2: bool(prev.get("2", prev.get(2, true))), 3: bool(prev.get("3", prev.get(3, true))),
		4: bool(prev.get("4", prev.get(4, true)))}
	shed_soc = {4: float(shed_soc.get("4", shed_soc.get(4, 0.5))), 3: float(shed_soc.get("3", shed_soc.get(3, 0.4))),
		2: float(shed_soc.get("2", shed_soc.get(2, 0.2)))}
	for n in notes:
		n[0] = int(n[0])
	var fixed := []
	for v in p4_off_week:
		fixed.append(int(v))
	p4_off_week = fixed
