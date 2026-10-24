class_name CityAuto
extends RefCounted
## 위임과 운영 기록. 시뮬레이션 밖의 규칙이다.
##   자동 운영: 시드가 다 맡는다 (CitySim.autopilot이 추천 운영 AutoPolicy).
##   위임: 직접 운영 도시도 분야를 골라 시드에게 맡긴다 — c["delegate"] = {분야: true}
##     build 살림 건설 — 추천 운영의 짓기(생명유지·전력·거주·식량·물·사회·로봇 — DelegatePolicy)와 발전 모드의 건물
##     research 연구 — 연구 차례(추천 순서로 채우고 발전 모드의 기술을 앞으로), 갈림길, 돌파 카드
##     land 땅·구획 — 빈 블록 구획 정하기, 땅 사기·돌려주기, 재건축, 길 넓히기·고가·궤도 노선
##     explore 둘레 탐사 · trade 수출 계약 · mega 메가프로젝트 · politics 평의회 정책
##   운영 기록: 시드가 한 일을 (자동 운영이든 위임이든) 까닭과 함께 c["oplog"]에 [시간, 분야, 글]로 남긴다 (LOG_MAX까지, 저장된다)

const DOMAINS := [
	["build", "살림 건설", "생명유지·전력·거주·식량·물·사회 건물을 추천 운영대로 짓는다 (발전 모드의 건물도)"],
	["research", "연구", "연구 차례를 추천 순서로 채우고, 갈림길과 돌파 카드를 고른다"],
	["land", "땅·구획", "빈 블록의 구획을 정하고, 땅을 사고 돌려주고, 재건축과 길 공사를 한다"],
	["explore", "둘레 탐사", "보름마다 가장 가까운 탐사지로 탐사대를 보낸다"],
	["trade", "수출 계약", "남는 양으로 계약을 받고 보낸다"],
	["mega", "메가프로젝트", "자재가 넉넉하면 메가프로젝트를 짓기 시작한다"],
	["politics", "정치", "평의회 정책을 발전 모드대로 정하고, 회기 앞에 가장 불만인 모임을 달랜다"],
]
const LOG_MAX := 300

## 추천 운영이 그 계열을 짓는 까닭 (AutoPolicy.decide의 문턱)
const REASONS := {
	"co2_scrubber": "CO₂ 제거가 다음 유인선까지의 정착민 1.3배에 못 미친다",
	"electrolyzer": "산소 생산이 다음 유인선까지의 정착민 1.2배에 못 미친다",
	"water_recycler": "물 재활용이 쓰는 물의 1.15배에 못 미친다",
	"storm_shelter": "대피소 좌석이 다음 유인선까지의 정착민보다 적다",
	"regolith_cover": "거주 모듈에 레골리스를 덮어 평소 선량을 줄인다",
	"rfc_unit": "어둠을 버틸 축전이 모자란다 (1·2순위 부하 48시간)",
	"battery_bank": "어둠을 버틸 축전이 모자란다 (1·2순위 부하 48시간)",
	"solar_tower": "발전이 평균 수요의 1.25배에 못 미친다",
	"fission_1mw": "발전이 평균 수요의 1.25배에 못 미친다 (햇빛이 약하거나 밤이 길다)",
	"fission_40kw": "발전이 평균 수요의 1.25배에 못 미친다 (햇빛이 약하거나 밤이 길다)",
	"radiator": "방열이 평균 부하의 1.2배에 못 미친다",
	"hab_module": "다음 유인선이 오면 집이 모자란다",
	"regolith_dome": "다음 유인선이 오면 집이 모자란다",
	"regolith_printer": "레골리스 돔을 찍어 낼 프린터가 없다",
	"hydroponics": "식량 자급률이 올해 목표에 못 미친다",
	"algae_reactor": "식량 자급률이 올해 목표에 못 미친다",
	"food_store": "식량 창고가 120일치에 못 미친다",
	"tank_farm": "산소 탱크가 25일치에 못 미친다",
	"ice_miner": "얼음 채굴이 물의 하루 순손실을 덮지 못한다",
	"research_lab": "정착민 60명마다 연구동 하나",
	"green_commons": "정착민 100명마다 녹지 하나",
	"medical_bay": "의료 좌석이 다음 유인선까지의 정착민보다 적다",
	"excavator": "돔·대피소 공사에 굴착 로봇이 모자란다",
	"mre_plant": "금속을 만들 용융 레골리스 전해 공장이 없다",
	"parts_fab": "부품 공장이 금속 공장의 두 배에 못 미친다",
	"robot": "정착민 40명마다 로봇 하나 더",
}


## 시드가 다 맡는 자동 운영인가 (위임만 한 도시는 아니다)
static func full(sim: CitySim) -> bool:
	return sim != null and sim.autopilot != null and not sim.autopilot is DelegatePolicy


## 그 분야를 시드가 하는가: 자동 운영이거나 그 분야를 맡겼다
static func on(c: Dictionary, domain: String) -> bool:
	return full(c.get("sim")) or bool((c.get("delegate", {}) as Dictionary).get(domain, false))


## 맡긴 분야 수 (자동 운영이면 전부)
static func count(c: Dictionary) -> int:
	if full(c.get("sim")):
		return DOMAINS.size()
	var n := 0
	for d in DOMAINS:
		if bool((c.get("delegate", {}) as Dictionary).get(d[0], false)):
			n += 1
	return n


static func domain_name(id: String) -> String:
	for d in DOMAINS:
		if d[0] == id:
			return d[1]
	return id


## 분야를 맡기거나 되찾는다 (직접 운영 도시 — 자동 운영 도시는 적어만 두었다가 자동 운영을 끄면 그대로 맡는다)
static func set_delegate(c: Dictionary, domain: String, value: bool) -> void:
	var d: Dictionary = c.get("delegate", {}) if c.get("delegate") is Dictionary else {}
	if bool(d.get(domain, false)) == value:
		return
	d[domain] = value
	c["delegate"] = d
	sync_policy(c)
	if value and domain == "research":
		fill_research(c["sim"])
	record(c, domain, ("위임 — %s을(를) 시드에게 맡겼다" if value else "위임 — %s을(를) 되찾았다") % domain_name(domain))


## 살림 건설을 맡긴 직접 운영 도시에 위임 정책을 붙이고, 아니면 뗀다 (자동 운영 도시는 그대로)
static func sync_policy(c: Dictionary) -> void:
	var sim: CitySim = c["sim"]
	if full(sim):
		return
	var want := bool((c.get("delegate", {}) as Dictionary).get("build", false))
	if want and sim.autopilot == null:
		sim.autopilot = DelegatePolicy.new()
	elif not want and sim.autopilot is DelegatePolicy:
		sim.autopilot = null


## 연구를 맡겼을 때: 비어 있거나 모자란 연구 차례를 추천 순서(남은 기술은 자료 순서)로 채운다. 채웠으면 true
static func fill_research(sim: CitySim) -> bool:
	var added := false
	for t in AutoPolicy.GOOD_RESEARCH + GameData.TECHS.keys():
		if GameData.TECHS.has(t) and not sim.techs.has(t) and not t in sim.research_queue:
			sim.research_queue.append(t)
			added = true
	return added


## 운영 기록에 한 줄
static func record(c: Dictionary, domain: String, text: String) -> void:
	var lg: Array = c.get("oplog", []) if c.get("oplog") is Array else []
	lg.append([(c["sim"] as CitySim).hour, domain, text])
	if lg.size() > LOG_MAX:
		lg = lg.slice(lg.size() - LOG_MAX)
	c["oplog"] = lg


## 배치 계획이 스스로 한 일(땅 사기·돌려주기·구획)을 이 도시의 운영 기록으로 (CityPlan.on_auto)
static func recorder(c: Dictionary) -> Callable:
	return func(domain: String, text: String) -> void: record(c, domain, text)


## 한 시간 동안 시뮬레이션이 스스로 대기열에 넣은 건물 (추천 운영·위임의 짓기 — seq0 뒤의 번호)을 까닭과 함께 적는다
static func record_builds(c: Dictionary, seq0: int) -> void:
	var sim: CitySim = c["sim"]
	if sim.seq <= seq0 or not on(c, "build"):
		return
	for q in sim.queue:
		if int(q["seq"]) <= seq0:
			continue
		var mid := String(q["id"])
		var fam := sim.family(mid) if sim.M.has(mid) else mid
		var name := GameData.module_name(mid) if sim.M.has(mid) else ("레골리스 덮기" if mid == "regolith_cover" else "로봇")
		record(c, "build", "짓기 시작 — %s: %s" % [name, String(REASONS.get(fam, "추천 운영"))])


## 운영 기록의 날짜 글 (날짜와 시각)
static func when_text(sim: CitySim, hour: int) -> String:
	return sim.date_text(hour)
