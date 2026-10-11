#!/usr/bin/env python3
"""SpaceCity 도시 레이어 밸런스 시뮬레이터 — M0 '종이 프로토타입'.

시대 0의 첫 3년(달 남극 섀클턴 시드 시티)을 1시간 단위로 돌려,
생명유지·전력·차폐·식량의 '빠듯함'이 설계 의도대로 나오는지 확인한다.
수치는 ../data/city_modules.json, ../data/city_techs.json 에서 읽는다.

    python3 city_balance.py                      # 추천 정책 1회, 분기별 요약
    python3 city_balance.py --policy naive       # 준비 없이 성장만 좇는 정책
    python3 city_balance.py --monte-carlo 200    # 두 정책을 각각 200회 돌려 비교
    python3 city_balance.py --module-table       # 문서용 모듈 표 (Markdown, 기본 29종)
    python3 city_balance.py --module-catalog     # 전체 모듈 표 (29계열 145종)
    python3 city_balance.py --policy variety     # 계열의 여러 종류를 섞어 짓는 시험 정책
    python3 city_balance.py --csv daily.csv      # 일별 기록 (차트용)
    python3 city_balance.py --site mars_hellas   # 다른 부지 (../data/city_sites.json)

표준 라이브러리만 사용한다. 같은 시드·정책은 언제나 같은 결과를 낸다.
"""

import argparse
import csv
import json
import math
import os
import random
import sys
from collections import Counter
from datetime import date, timedelta
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_DATA = json.loads((DATA_DIR / "city_modules.json").read_text(encoding="utf-8"))
C = _DATA["constants"]
MODULES = {m["id"]: m for m in _DATA["modules"]}
TECHS = {t["id"]: t for t in
         json.loads((DATA_DIR / "city_techs.json").read_text(encoding="utf-8"))["techs"]}

SITES = {s["id"]: s for s in
         json.loads((DATA_DIR / "city_sites.json").read_text(encoding="utf-8"))["sites"]}
HOME_SITE = "moon_shackleton"

PER = C["per_person_day"]
START = date.fromisoformat(C["start"]["date"])
STOCK_KEYS = ("o2_kg", "water_kg", "h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "food_kg")
CAUSES_KO = {"hypoxia": "산소 결핍", "co2": "이산화탄소 중독", "starvation": "기아"}
# 가동률이 시간마다 달라지는 계열 — 나머지는 하루 단위로 미리 합산해 둔다
VARIABLE = {"electrolyzer", "sabatier", "water_recycler", "hydroponics"}
# 추천 정책의 건설 순서: 생명유지 → 대피·주거 → 전력 → 식량 → 나머지
BUILD_PRIORITY = {
    "co2_scrubber": 0, "electrolyzer": 0, "water_recycler": 0,
    "storm_shelter": 1, "regolith_printer": 1, "medical_bay": 1,
    "regolith_dome": 2, "hab_module": 2,
    "rfc_unit": 3, "battery_bank": 3, "regolith_cover": 3, "solar_tower": 3,
    "fission_40kw": 3, "fission_1mw": 3, "radiator": 3,
    "hydroponics": 4, "tank_farm": 4, "food_store": 4,
}


def family(mid):
    """모듈의 계열 (기본 모듈 29종의 id). 계열이 같으면 같은 규칙에 들어가고, 수치는 저마다 다르다."""
    m = MODULES.get(mid)
    return m.get("family", mid) if m else mid


# 계열 → 모듈 id (데이터 순서, 기본 모듈이 맨 앞)
FAMILY = {}
for _mid in MODULES:
    FAMILY.setdefault(family(_mid), []).append(_mid)
# provides 열쇠 → 그 값이 0이 아닌 모듈 (데이터 순서) — 0을 더하지 않을 뿐 합은 같다
WITH = {}
for _mid, _m in MODULES.items():
    for _key, _value in _m.get("provides", {}).items():
        if _value:
            WITH.setdefault(_key, []).append(_mid)


def spec(mid, key, default=0.0):
    return MODULES[mid].get(key, default)


def provided(mid, key, default=0.0):
    return MODULES[mid].get("provides", {}).get(key, default)


def recipe(mid, side, key):
    return MODULES[mid].get("recipe", {}).get(side, {}).get(key, 0.0)


def merged(base, over):
    """사전을 깊게 합친다 (over가 이긴다). 원본은 건드리지 않는다."""
    out = dict(base)
    for k, v in over.items():
        out[k] = merged(base[k], v) if isinstance(v, dict) and isinstance(base.get(k), dict) else v
    return out


def site_constants(site):
    """부지의 도시 상수: 기본 상수에 부지 값을 덮어쓴 것 (달 시드 시티는 기본 상수 그대로)."""
    over = SITES.get(site, {}).get("constants", {})
    return merged(C, over) if over else C


def illumination_schedule(rng, hours, il):
    """시간별 그림자 여부(1 = 어두움). 평소엔 드물고 짧게, 남극 겨울엔 잦고 길게."""
    dark = bytearray(hours)
    t = 0.0
    while t < hours:
        day_of_year = (t / 24.0) % 365.25
        winter = il["winter_day_of_year"][0] <= day_of_year < il["winter_day_of_year"][1]
        t += rng.uniform(*il["winter_gap_h" if winter else "normal_gap_h"])
        length = rng.uniform(*il["winter_dark_h" if winter else "normal_dark_h"])
        for hour in range(int(t), min(hours, int(t + length))):
            dark[hour] = 1
        t += length
    return dark


def rotation_schedule(hours, il):
    """자전하는 천체의 낮과 밤 (1 = 어두움): 하루(day_h)의 앞 light_frac이 낮이고, 아침에 시작한다."""
    day_h, light = il["day_h"], il["light_frac"]
    return bytearray(1 if ((hour + 0.5) / day_h + 0.02) % 1.0 >= light else 0 for hour in range(hours))


def dust_schedule(rng, hours, dust):
    """먼지 폭풍 시간(1 = 폭풍): 해마다 rate_per_year번쯤, 한 번에 days[0]~days[1]일."""
    storm = bytearray(hours)
    mean_gap_h = 8766.0 / dust["rate_per_year"]
    t = 0.0
    while t < hours:
        t += rng.uniform(0.5 * mean_gap_h, 1.5 * mean_gap_h)
        length = rng.uniform(dust["days"][0], dust["days"][1]) * 24.0
        for hour in range(int(t), min(hours, int(t + length))):
            storm[hour] = 1
        t += length
    return storm


def solar_activity(year):
    """0(극소기) ~ 1(극대기). 11년 주기, 극대기 2069년."""
    spe = C["spe"]
    return 0.5 + 0.5 * math.cos(2 * math.pi * (year - spe["cycle_max_year"]) / spe["cycle_years"])


class Policy:
    """플레이어 대역. 'good'은 문서의 추천 운영, 'naive'는 눈앞의 성장만 좇는 운영.
    'variety'는 추천 운영과 같되 계열마다 여러 종류를 돌아가며 짓는다 (새 건물 규칙을 시험하는 용도)."""

    def __init__(self, name):
        self.name = name
        self.prepared = name in ("good", "variety")
        self.variety = name == "variety"
        # 어두울 때 축전량이 이 비율 아래로 내려가면 4·3·2순위를 미리 끈다 (절전 정책)
        self.shed_soc = {4: 0.5, 3: 0.4, 2: 0.2} if self.prepared else {4: 0.0, 3: 0.0, 2: 0.0}
        self.research = (
            ["sintered_construction", "regenerative_fuel_cell", "space_weather_forecast",
             "closed_loop_ls2", "polar_prospecting", "autonomous_robots_2", "shielding_2",
             "sunlight_piping", "molten_regolith_electrolysis", "local_manufacturing",
             "robot_fabrication", "tall_towers", "algae_bioreactor", "cryogenic_propellant",
             "low_g_medicine", "megawatt_fission", "seed_distributed", "orbital_assembly",
             "mass_driver", "rotating_habitat"]
            if self.prepared else
            ["algae_bioreactor", "sunlight_piping", "autonomous_robots_2", "closed_loop_ls2",
             "tall_towers", "polar_prospecting", "sintered_construction", "regenerative_fuel_cell",
             "molten_regolith_electrolysis", "local_manufacturing", "robot_fabrication",
             "cryogenic_propellant", "space_weather_forecast", "shielding_2", "low_g_medicine",
             "megawatt_fission", "seed_distributed", "orbital_assembly", "mass_driver", "rotating_habitat"])
        # 1·2·3년차 식량 자급률 목표, 화물선 식량 비축 목표(일), 배급·긴급 보급을 시작하는 비축(일)
        self.food_targets = (0.5, 0.75, 1.0) if self.prepared else (0.6, 0.85, 1.0)
        self.food_buffer_days = 40 if self.prepared else 25
        self.ration_below_days = 10 if self.prepared else 0.5
        self.express_below_days = 20 if self.prepared else 2


class City:
    def __init__(self, seed=2061, policy="good", years=3, site=HOME_SITE, start_date=None):
        # 부지: 도시 상수(덮어쓴 값)와 시뮬레이션 보정. 달 시드 시티는 보정이 모두 1이다
        self.site_id = site
        self.site = SITES.get(site, {})
        rules = self.site.get("rules", {})
        self.C = site_constants(site)
        self.sun_k = rules.get("sun_k", 1.0)          # 태양광 출력
        self.ice_k = rules.get("ice_k", 1.0)          # 얼음 채굴
        self.heat_k = rules.get("heat_k", 1.0)        # 방열 능력
        self.build_k = rules.get("build_k", 1.0)      # 로봇 작업량
        self.contact_k = rules.get("contact_k", 1.0)  # 지구 교신의 사기
        self.air_co2 = rules.get("co2_air", False)    # 대기의 CO₂로 사바티에가 돈다
        # 자동 운영이 남겨 두는 부품 — 보급이 드문 부지일수록 많이 (달 40)
        self.reserve = 40 * max(1.0, self.C["earth"]["cargo_interval_days"] / 60)
        self.start_date = start_date or date.fromisoformat(self.C["start"]["date"])
        self.start_year = self.start_date.year + (self.start_date.timetuple().tm_yday - 1) / 365.25
        self.rng = random.Random(seed)
        self.policy = Policy(policy)
        self.days = int(round(365.25 * years))
        il = self.C["illumination"]
        hours = self.days * 24 + 48
        if il.get("model") == "rotation":
            self.dark = rotation_schedule(hours, il)
        else:
            self.dark = illumination_schedule(random.Random(seed * 7919 + 1), hours, il)
        dust = rules.get("dust")
        self.dust = dust_schedule(random.Random(seed * 104729 + 7), hours, dust) if dust else None
        self.dust_factor = dust["sun_factor"] if dust else 1.0
        start = self.C["start"]
        self.hour = 0
        if "counts" in start:
            self.counts = Counter({mid: n for mid, n in start["counts"].items() if n})
        else:
            self.counts = Counter({mid: m["start"] for mid, m in MODULES.items() if m["start"]})
        self.broken = Counter()
        self.tiles = Counter(start["solar_tiles_used"])
        self.covered_habs = 0
        self.robots = self.C["robots"]["start"]
        self.robots_broken = 0
        self.queue = []          # 건설 대기열: {"id", "rd", "print_t", "seq"}
        self.seq = 0
        self.stock = {k: 0.0 for k in STOCK_KEYS}
        self.stock.update({k: float(v) for k, v in start["stocks"].items()})
        self.cohorts = [[float(start["population"]), 0.0, False]]   # [인원, 누적 선량 mSv, 귀환 대기]
        self.morale = float(start["morale"])
        self.trust = float(start["trust"])
        self.trust_memory = 0.0  # 사건이 남긴 신뢰의 흔적. 반감기 약 1년
        self.support = float(self.C["earth"]["support_start"])
        self.techs = set()
        self.rp_bank = 0.0
        self.research_queue = list(self.policy.research)
        self.variety_turn = 0
        self.farm_dark_h = 0
        self.crops_dead_until = -1
        self.prev = {2: True, 3: True, 4: True}
        earth = self.C["earth"]
        self.next_cargo = earth["cargo_first_day"]
        self.next_crewed = earth["crewed_first_day"]
        self.express_eta = None
        self.rationing = False
        self.hungry_days = 0
        self.algae_food_share = 0.0
        self.recent_deaths = 0.0
        self.recent_exposure = 0.0
        self.p4_off_week = []
        self.day = Counter()
        self.stats = Counter()
        self.deaths = Counter()
        self.max_co2 = 0.0
        self.min_reserve_days = 1e9
        self.log = []
        self.daily = []
        self.refresh()
        self.battery = self.bat_cap
        self.rfc = 0.0
        self.co2_air = self.co2_floor

    # ── 파생값 (하루 한 번 갱신) ─────────────────────────────────────
    def refresh(self):
        wk = {mid: max(0, self.counts[mid] - self.broken[mid]) for mid in MODULES}
        self.wk = wk
        # 계열마다 가동 중인(1기 이상) 모듈 — 0기를 건너뛰어도 합은 같다
        self.active = {fam: [m for m in members if wk[m]] for fam, members in FAMILY.items()}
        fs = self.fam_sum
        o2_out = lambda m: recipe(m, "out", "o2_kg")  # noqa: E731
        power = lambda m: spec(m, "power_kw")  # noqa: E731
        # 한 시간마다 쓰는 계열 합 (가동 수가 바뀌는 refresh 때만 다시 센다)
        self.hourly = {
            "o2_hydro": fs("hydroponics", o2_out), "o2_algae": fs("algae_reactor", o2_out),
            "o2_green": fs("green_commons", o2_out), "o2_mre": fs("mre_plant", o2_out),
            "e_o2": fs("electrolyzer", o2_out), "e_water": fs("electrolyzer", lambda m: recipe(m, "in", "water_kg")),
            "sab_n": self.fam_n("sabatier"), "sab_h2": fs("sabatier", lambda m: recipe(m, "in", "h2_kg")),
            "sab_co2": fs("sabatier", lambda m: recipe(m, "in", "co2_kg")),
            "rec_day": fs("water_recycler", lambda m: provided(m, "wastewater_kg_day")),
            "e_kw": fs("electrolyzer", power), "sab_kw": fs("sabatier", power), "rec_kw": fs("water_recycler", power),
            "hydro_kw": fs("hydroponics", power), "scrub_day": fs("co2_scrubber", lambda m: provided(m, "co2_kg_day")),
            "hydro_n": self.fam_n("hydroponics"),
        }
        self.caps = {key: sum(provided(m, "storage", {}).get(key, 0.0) * wk[m] for m in WITH["storage"])
                     for key in STOCK_KEYS}
        self.housing_cap = sum(provided(m, "housing") * self.counts[m] for m in WITH["housing"])
        self.air = max(1.0, self.housing_cap) * self.C["air_kg_per_housing"]
        self.co2_floor = self.ppm_to_kg(self.C["co2_ppm"]["floor"])
        bonus = 1.5 if "shielding_2" in self.techs else 1.0
        self.shelter_cap = 0.0
        for m in WITH["shelter"]:
            if provided(m, "shelter"):
                if family(m) == "storm_shelter":
                    self.shelter_cap += provided(m, "shelter") * self.counts[m] * bonus
                else:
                    self.shelter_cap += provided(m, "shelter") * self.counts[m]
        self.bat_cap = self.fam_sum("battery_bank", lambda m: provided(m, "storage_kwh"))
        self.rfc_cap = self.fam_sum("rfc_unit", lambda m: provided(m, "storage_kwh"))
        towers = sum(self.tiles.values())
        tile_factor = self.C["illumination"]["tile_factor"]
        factor = sum(tile_factor[t] * n for t, n in self.tiles.items()) / towers if towers else 0.0
        boost = 1.2 if "tall_towers" in self.techs else 1.0
        self.solar_kw = self.fam_sum("solar_tower", lambda m: provided(m, "generation_kw")) * factor * boost * self.sun_k
        self.fission_kw = 0.0          # 일조와 상관없이 늘 같은 출력 (핵분열·동위원소·핵융합)
        for m in WITH["generation_kw"]:
            if family(m) != "solar_tower":
                self.fission_kw += provided(m, "generation_kw") * wk[m]
        self.heat_cap = 0.0
        for m in WITH["heat_kw"]:
            if provided(m, "heat_kw"):
                self.heat_cap += provided(m, "heat_kw") * wk[m]
        self.heat_cap *= self.heat_k
        printing = any(item["print_t"] > 0 for item in self.queue)
        s = self.stock
        static = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
        robots_powered = False
        for mid in MODULES:
            if not wk[mid]:
                continue
            p = spec(mid, "priority")
            fam = family(mid)
            if not p or fam in VARIABLE:
                continue
            kw = spec(mid, "power_kw") * wk[mid]
            if fam == "regolith_printer" and not printing:
                kw *= 0.1
            elif fam == "mre_plant" and s.get("regolith_t", 0) < recipe(mid, "in", "regolith_t"):
                kw = 0.0
            elif fam == "parts_fab" and s.get("metal_t", 0) < recipe(mid, "in", "metal_t"):
                kw = 0.0
            elif fam == "robot_bay" and not robots_powered:
                kw += self.C["robots"]["power_kw"] * (self.robots - self.robots_broken)
                robots_powered = True       # 로봇 충전은 정비고 계열 한 번만
            static[p] += kw
        self.static_load = static
        self.recovery = 0.98 if "closed_loop_ls2" in self.techs else provided("water_recycler", "recovery")
        self.mining = (1.4 if "polar_prospecting" in self.techs else 1.0) * self.ice_k

    def fam_sum(self, fam, value):
        """계열의 가동 중인 모듈마다 value(모듈)를 곱해 더한다 (데이터 순서, 보통 덧셈)."""
        total = 0.0
        for m in self.active[fam]:
            total += self.wk[m] * value(m)
        return total

    def fam_n(self, fam):
        return sum(self.wk[m] for m in self.active[fam])

    def ppm_to_kg(self, ppm):
        return ppm / 1e6 * (self.air / 29.0) * 44.0

    def co2_ppm(self):
        return (self.co2_air / 44.0) / (self.air / 29.0) * 1e6

    @property
    def pop(self):
        return sum(c[0] for c in self.cohorts)

    def year(self):
        return self.start_year + self.hour / 8766.0

    def queued(self, mid):
        return sum(1 for item in self.queue if item["id"] == mid)

    def planned(self, mid):
        return self.counts[mid] + self.queued(mid)

    def crops_alive(self):
        return self.hour >= self.crops_dead_until

    # ── 1시간 ──────────────────────────────────────────────────────
    def step_hour(self, pop):
        lit = 1.0 - self.dark[self.hour]
        if self.dust is not None and self.dust[self.hour]:
            lit *= self.dust_factor
        s = self.stock
        wk = self.wk
        h = 1.0 / 24.0

        # 가변 가동률: 전기분해기는 필요한 만큼, 사바티에·재활용기는 원료만큼
        farms_on_before = self.prev[2] and self.crops_alive()
        hr = self.hourly
        bio_o2 = ((hr["o2_hydro"] if farms_on_before else 0.0)
                  + (hr["o2_algae"] if self.prev[2] else 0.0)
                  + (hr["o2_green"] if self.prev[4] else 0.0)
                  + (hr["o2_mre"] if self.prev[3] else 0.0))
        want = pop * PER["o2_kg"] - bio_o2 + max(0.0, 0.95 * self.caps["o2_kg"] - s["o2_kg"])
        e_cap = hr["e_o2"]
        u_elec = min(1.0, max(0.0, want) / e_cap) if e_cap else 0.0
        water_need = hr["e_water"] * u_elec * h
        if water_need > s["water_kg"] > 0:
            u_elec *= s["water_kg"] / water_need
        elif s["water_kg"] <= 0:
            u_elec = 0.0
        n_sab = hr["sab_n"]
        u_sab = 0.0
        if n_sab and self.air_co2:
            u_sab = max(0.0, min(1.0, s["h2_kg"] / (hr["sab_h2"] * h)))     # CO₂는 대기에서
        elif n_sab:
            u_sab = max(0.0, min(1.0, s["h2_kg"] / (hr["sab_h2"] * h), s["co2_kg"] / (hr["sab_co2"] * h)))
        rec_rate = hr["rec_day"] * h
        u_rec = min(1.0, s["wastewater_kg"] / rec_rate) if rec_rate else 0.0
        light_cut = 0.6 if (lit > 0 and "sunlight_piping" in self.techs) else 1.0

        load = dict(self.static_load)
        load[1] += hr["e_kw"] * u_elec + hr["sab_kw"] * u_sab + hr["rec_kw"] * max(u_rec, 0.2)
        load[2] += hr["hydro_kw"] * light_cut

        # 전력 배분: 정책 문턱으로 미리 끄고, 그래도 모자라면 낮은 순위부터 강제로 끈다
        gen = self.solar_kw * lit + self.fission_kw
        self.battery = min(self.battery, self.bat_cap)
        self.rfc = min(self.rfc, self.rfc_cap)
        stored = self.battery + self.rfc
        total_cap = self.bat_cap + self.rfc_cap
        soc = stored / total_cap if total_cap else 0.0
        on = {1: True, 2: True, 3: True, 4: True}
        if gen < sum(load.values()):
            for p in (4, 3, 2):
                if soc < self.policy.shed_soc[p]:
                    on[p] = False
        for p in (4, 3, 2):
            if on[p] and sum(load[q] for q in on if on[q]) > gen + stored:
                on[p] = False
        used = sum(load[p] for p in on if on[p])
        frac1 = 1.0
        if used > gen + stored:
            frac1 = (gen + stored) / load[1] if load[1] else 0.0
            used = gen + stored
            self.stats["brownout_h"] += 1
            self.day["brownout"] = 1
        run3 = 1.0 if on[3] else 0.0
        if used > self.heat_cap and on[3] and load[3] > 0:      # 방열 한계: 산업부터 감속
            run3 = max(0.0, 1.0 - (used - self.heat_cap) / load[3])
            used -= load[3] * (1.0 - run3)
            self.stats["overheat_h"] += 1
        net = gen - used
        if net >= 0:
            eff_b = provided("battery_bank", "efficiency", 1.0)
            charge = min(self.bat_cap - self.battery, net * eff_b)
            self.battery += charge
            rest = net - charge / eff_b
            self.rfc = min(self.rfc_cap, self.rfc + rest * provided("rfc_unit", "efficiency", 1.0))
        else:
            take = min(self.battery, -net)
            self.battery -= take
            self.rfc = max(0.0, self.rfc + net + take)
        if lit == 0 and soc < 0.1:
            self.day["low_soc"] = 1
        if not on[4]:
            self.day["p4_off_h"] += 1
        if not on[2]:
            self.day["p2_off_h"] += 1

        # 사람
        s["o2_kg"] -= pop * PER["o2_kg"] * h
        self.co2_air += pop * PER["co2_kg"] * h
        use = pop * PER["water_use_kg"] * h
        s["water_kg"] -= use
        s["wastewater_kg"] += use
        s["food_kg"] -= pop * PER["food_kg"] * h * (self.C["rationing"]["consumption_factor"] if self.rationing else 1.0)

        # 식량·생물 (2·4순위)
        bio_removal = 0.0
        food = 0.0
        if on[2] and self.crops_alive():
            for m in self.active["hydroponics"]:
                n = wk[m]
                food += n * recipe(m, "out", "food_kg") * h
                s["o2_kg"] += n * recipe(m, "out", "o2_kg") * h
                bio_removal += n * recipe(m, "in", "co2_kg") * h
                s["water_kg"] -= n * recipe(m, "in", "water_kg") * h
        algae = 0.0
        if on[2]:
            for m in self.active["algae_reactor"]:
                n = wk[m]
                a = n * recipe(m, "out", "food_kg") * h
                algae += a
                food += a
                s["o2_kg"] += n * recipe(m, "out", "o2_kg") * h
                bio_removal += n * recipe(m, "in", "co2_kg") * h
                s["water_kg"] -= n * recipe(m, "in", "water_kg") * h
        if on[4]:
            for m in self.active["green_commons"]:
                n = wk[m]
                s["o2_kg"] += n * recipe(m, "out", "o2_kg") * h
                bio_removal += n * recipe(m, "in", "co2_kg") * h
        s["food_kg"] += food
        self.day["food_made"] += food
        if food > 0:
            self.algae_food_share = 0.98 * self.algae_food_share + 0.02 * (algae / food)

        # CO₂: 식물이 먼저 흡수하고, 나머지는 제거기가 농축 탱크로 옮긴다
        self.co2_air = max(self.co2_floor, self.co2_air - bio_removal)
        scrub = hr["scrub_day"] * h * frac1
        moved = min(scrub, self.co2_air - self.co2_floor)
        self.co2_air -= moved
        s["co2_kg"] += moved

        # 1순위 화학 공정 (전력이 모자라면 frac1만큼만)
        k = h * frac1
        for m in self.active["electrolyzer"]:
            n = wk[m] * u_elec * k
            s["water_kg"] -= n * recipe(m, "in", "water_kg")
            s["o2_kg"] += n * recipe(m, "out", "o2_kg")
            s["h2_kg"] += n * recipe(m, "out", "h2_kg")
        for m in self.active["sabatier"]:
            n = wk[m] * u_sab * k
            if not self.air_co2:
                s["co2_kg"] -= n * recipe(m, "in", "co2_kg")
            s["h2_kg"] -= n * recipe(m, "in", "h2_kg")
            s["ch4_kg"] += n * recipe(m, "out", "ch4_kg")
            s["water_kg"] += n * recipe(m, "out", "water_kg")
        processed = min(s["wastewater_kg"], rec_rate * frac1)
        s["wastewater_kg"] -= processed
        s["water_kg"] += processed * self.recovery

        # 3순위 산업
        if run3:
            k3 = h * run3
            for m in self.active["ice_miner"]:
                s["water_kg"] += wk[m] * recipe(m, "out", "water_kg") * self.mining * k3
            for m in self.active["excavator"]:
                s["regolith_t"] += wk[m] * recipe(m, "out", "regolith_t") * k3
            for m in self.active["mre_plant"]:
                n = min(wk[m] * k3, s["regolith_t"] / recipe(m, "in", "regolith_t"))
                s["regolith_t"] -= n * recipe(m, "in", "regolith_t")
                s["metal_t"] += n * recipe(m, "out", "metal_t")
                s["o2_kg"] += n * recipe(m, "out", "o2_kg")
            for m in self.active["parts_fab"]:
                n = min(wk[m] * k3, s["metal_t"] / recipe(m, "in", "metal_t"))
                s["metal_t"] -= n * recipe(m, "in", "metal_t")
                s["parts"] += n * recipe(m, "out", "parts")

        # 저장 한도: 넘치는 수소·CO₂·메탄은 배출, 넘치는 폐수는 손실
        caps = self.caps
        for key in ("h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "o2_kg", "water_kg", "food_kg"):
            if s[key] > caps[key]:
                if key == "wastewater_kg":
                    self.stats["wastewater_lost_kg"] += s[key] - caps[key]
                s[key] = caps[key]

        # 작물: 72시간 넘게 전력을 못 받으면 고사
        self.farm_dark_h = 0 if (on[2] or not hr["hydro_n"]) else self.farm_dark_h + 1
        if self.farm_dark_h >= self.C["crops"]["dead_after_unpowered_h"] and self.crops_alive():
            self.crops_dead_until = self.hour + self.C["crops"]["regrow_days"] * 24
            self.stats["crop_losses"] += 1
            self.trust_event(-3)
            self.note("작물 고사 — 수경 농장 전력이 72시간 끊김")

        self.hazards(pop)
        self.prev = {2: on[2], 3: on[3], 4: on[4]}
        self.hour += 1

    def hazards(self, pop):
        s = self.stock
        ppm = self.co2_ppm()
        if ppm > self.max_co2:
            self.max_co2 = ppm
        limits = self.C["co2_ppm"]
        if ppm > limits["warn"]:
            self.day["co2_warn"] = 1
        if ppm > limits["bad"]:
            self.stats["co2_bad_h"] += 1
        if ppm > limits["lethal"]:
            self.kill(max(1, round(pop * 0.01)), "co2")
        if s["o2_kg"] < 0:
            s["o2_kg"] = 0.0
            self.kill(max(1, round(pop * 0.05)), "hypoxia")
        if s["water_kg"] < 0:
            s["water_kg"] = 0.0
            self.stats["no_water_h"] += 1
        if s["food_kg"] < 0:
            s["food_kg"] = 0.0
            self.stats["no_food_h"] += 1
            self.day["no_food"] = 1
        if pop:
            reserve = s["o2_kg"] / (pop * PER["o2_kg"])
            if reserve < self.min_reserve_days:
                self.min_reserve_days = reserve

    def kill(self, n, cause):
        n = min(n, int(self.pop))
        if n <= 0:
            return
        for cohort in self.cohorts:
            take = min(cohort[0], n)
            cohort[0] -= take
            n -= take
            self.deaths[cause] += take
            if n <= 0:
                break
        self.cohorts = [c for c in self.cohorts if c[0] > 0]
        self.recent_deaths = 1.0
        self.trust_event(-10)
        self.note(f"사망 — {CAUSES_KO[cause]}")

    def trust_event(self, delta):
        self.trust_memory += delta

    # ── 하루 ───────────────────────────────────────────────────────
    def step_day(self, day):
        self.failures()
        self.work_robots()
        self.decide(day)
        self.research()
        self.earth(day)
        self.space_weather(day)
        self.dose_and_departures()
        self.update_morale()
        self.record(day)
        self.refresh()

    def failures(self):
        rng = self.rng
        for mid, n in self.counts.items():
            working = n - self.broken[mid]
            mtbf = spec(mid, "mtbf_days")
            if working <= 0 or not mtbf:
                continue
            failed = sum(1 for _ in range(working) if rng.random() < 1.0 / mtbf)
            if failed:
                self.broken[mid] += failed
                self.stats["failures"] += failed
        working = self.robots - self.robots_broken
        self.robots_broken += sum(1 for _ in range(working) if rng.random() < 1.0 / self.C["robots"]["mtbf_days"])

    def work_robots(self):
        s = self.stock
        speed = 1.5 if "autonomous_robots_2" in self.techs else 1.0
        rd = (self.robots - self.robots_broken) * speed * self.build_k
        while self.robots_broken and s["parts"] >= self.C["robots"]["repair_parts"] and rd >= 0.5:
            self.robots_broken -= 1
            s["parts"] -= self.C["robots"]["repair_parts"]
            rd -= 0.5
        # 수리: 1순위 모듈 → 발전·저장·방열 → 2·3·4순위
        for mid in sorted(self.broken, key=lambda m: (spec(m, "priority") or 1.5, m)):
            repair = MODULES[mid]["repair"]
            while self.broken[mid] and rd >= repair["rd"] and s["parts"] >= repair["parts"]:
                self.broken[mid] -= 1
                rd -= repair["rd"]
                s["parts"] -= repair["parts"]
        # 건설: 추천 정책은 우선순위대로, 준비 없는 정책은 들어온 순서대로 작업량을 준다
        if self.policy.prepared:
            self.queue.sort(key=lambda item: (BUILD_PRIORITY.get(family(item["id"]), 5), item["seq"]))
        print_cap = self.fam_sum("regolith_printer", lambda m: provided(m, "print_t_day"))
        for item in self.queue:
            if rd <= 0 and print_cap <= 0:
                break
            spend = min(rd, item["rd"])
            item["rd"] -= spend
            rd -= spend
            if item["print_t"] > 0 and print_cap > 0:
                printed = min(print_cap, item["print_t"])
                item["print_t"] -= printed
                print_cap -= printed
        done = [item for item in self.queue if item["rd"] <= 1e-9 and item["print_t"] <= 1e-9]
        self.queue = [item for item in self.queue if item["rd"] > 1e-9 or item["print_t"] > 1e-9]
        for item in done:
            if item["id"] == "regolith_cover":
                self.covered_habs += 1
            elif item["id"] == "robot":
                self.robots += 1
            else:
                self.counts[item["id"]] += 1
                self.stats["built"] += 1

    def can_afford(self, cost, reserve=40):
        s = self.stock
        return (s["parts"] - cost.get("parts", 0) >= reserve
                and s["regolith_t"] >= cost.get("regolith_t", 0)
                and s["metal_t"] >= cost.get("metal_t", 0)
                and all(s.get(k, 0.0) >= v for k, v in cost.items() if k not in ("parts", "regolith_t", "metal_t")))

    def enqueue(self, mid, tile=None):
        m = MODULES[mid]
        if m["tech"] and m["tech"] not in self.techs:
            return False
        if not self.can_afford(m["cost"], self.reserve):
            self.day["short_parts"] = 1
            return False
        for key, value in m["cost"].items():
            self.stock[key] -= value
        print_t = m["cost"].get("regolith_t", 0) if m.get("printed") else 0
        self.seq += 1
        self.queue.append({"id": mid, "rd": m["build_rd"], "print_t": print_t, "seq": self.seq})
        if tile:
            self.tiles[tile] += 1
        return True

    def enqueue_special(self, kind):
        s = self.stock
        self.seq += 1
        if kind == "regolith_cover":
            need = self.C["regolith_cover"]
            if s["regolith_t"] < need["regolith_t"]:
                return False
            s["regolith_t"] -= need["regolith_t"]
            self.queue.append({"id": kind, "rd": need["build_rd"], "print_t": 0, "seq": self.seq})
            return True
        if kind == "robot" and "robot_fabrication" in self.techs and s["parts"] >= self.C["robots"]["local_parts"] + self.reserve:
            s["parts"] -= self.C["robots"]["local_parts"]
            self.queue.append({"id": "robot", "rd": self.C["robots"]["local_rd"], "print_t": 0, "seq": self.seq})
            return True
        return False

    def free_tile(self):
        for tile in ("A", "B", "C"):
            if self.tiles[tile] < self.C["illumination"]["tiles"][tile]:
                return tile
        return None

    def decide(self, day):
        """정책이 하루에 한 번 건설을 결정한다. 계획 수량(완공 + 대기)을 기준으로 판단한다."""
        prepared = self.policy.prepared
        pop = self.pop
        pop_next = pop + self.C["earth"]["crewed_seats"]
        year_index = min(2, day // 365)
        p = self.fam_planned
        cap = self.planned_cap
        build = self.build

        # 생명유지: 추천 정책은 여유분을, 준비 없는 정책은 문제가 터진 뒤에 짓는다
        if prepared or self.co2_ppm() > self.C["co2_ppm"]["bad"]:
            if cap(lambda m: family(m) == "co2_scrubber", lambda m: provided(m, "co2_kg_day")) < 1.3 * pop_next * PER["co2_kg"]:
                build("co2_scrubber")
        if cap(lambda m: family(m) == "electrolyzer", lambda m: recipe(m, "out", "o2_kg")) < 1.2 * pop_next * PER["o2_kg"]:
            build("electrolyzer")
        if (cap(lambda m: family(m) == "water_recycler", lambda m: provided(m, "wastewater_kg_day"))
                < 1.15 * pop_next * PER["water_use_kg"]):
            build("water_recycler")
        if prepared:
            bonus = 1.5 if "shielding_2" in self.techs else 1.0
            shelter = cap(lambda m: provided(m, "shelter"),
                          lambda m: provided(m, "shelter") * (bonus if family(m) == "storm_shelter" else 1.0))
            if shelter < pop_next:
                build("storm_shelter")
            if self.covered_habs + self.queued("regolith_cover") < self.counts["hab_module"]:
                self.enqueue_special("regolith_cover")

        # 저장: 1·2순위 부하를 48시간 버티는 축전 (추천 정책만)
        p1p2 = sum(spec(m, "power_kw") * self.counts[m] for m in MODULES if spec(m, "priority") in (1, 2))
        fission = cap(lambda m: provided(m, "generation_kw") and family(m) != "solar_tower",
                      lambda m: provided(m, "generation_kw"))
        storage_planned = cap(lambda m: family(m) in ("battery_bank", "rfc_unit"), lambda m: provided(m, "storage_kwh"))
        if prepared and storage_planned < max(0.0, p1p2 * 0.7 - fission) * 48:
            if not build("rfc_unit") and "regenerative_fuel_cell" not in self.techs:
                build("battery_bank")

        # 발전: 평균 발전량이 평균 수요의 1.25배(준비 없는 정책은 1.05배)
        avg_load = 0.85 * sum(spec(m, "power_kw") * self.planned(m) for m in MODULES if spec(m, "priority"))
        tile_factor = self.C["illumination"]["tile_factor"]
        towers_gen = sum(tile_factor[t] * n for t, n in self.tiles.items()) * 100 * 0.9 * self.sun_k
        if towers_gen + fission < (1.25 if prepared else 1.05) * avg_load:
            tile = self.free_tile()
            # 햇빛이 약한 부지(세레스·목성·토성계)는 타워 대신 원자로
            if tile and self.sun_k >= 0.2 and not (prepared and tile == "C" and "megawatt_fission" in self.techs):
                build("solar_tower", tile)
            elif not build("fission_1mw"):
                build("fission_40kw")
        if cap(lambda m: provided(m, "heat_kw"), lambda m: provided(m, "heat_kw")) < 1.2 * avg_load:
            build("radiator")

        # 거주: 다음 유인선 도착분까지 집을 준비
        housing = cap(lambda m: provided(m, "housing"), lambda m: provided(m, "housing"))
        if housing < pop_next:
            if "sintered_construction" in self.techs:
                if p("regolith_printer") or build("regolith_printer"):
                    build("regolith_dome")
            elif not prepared:
                build("hab_module")
            elif day > 60:
                build("hab_module")

        # 식량 자급률 목표
        target = self.policy.food_targets[year_index]
        food_of = lambda m: recipe(m, "out", "food_kg")  # noqa: E731
        need = target * pop * PER["food_kg"] - cap(lambda m: family(m) == "algae_reactor", food_of)
        if cap(lambda m: family(m) == "hydroponics", food_of) < need:
            build("hydroponics")
        if not prepared and "algae_bioreactor" in self.techs and p("algae_reactor") < pop / 60:
            build("algae_reactor")
        if self.caps["food_kg"] < pop * PER["food_kg"] * 120 and not self.fam_queued("food_store"):
            build("food_store")
        if self.caps["o2_kg"] < pop * PER["o2_kg"] * 25 and not self.fam_queued("tank_farm"):
            build("tank_farm")

        # 물: 하루 순손실을 얼음 채굴이 넉넉히 덮도록
        loss = pop * PER["water_use_kg"] * (1 - self.recovery) + pop * PER["o2_kg"] * 0.6 * 1.125
        if (cap(lambda m: family(m) == "ice_miner", lambda m: recipe(m, "out", "water_kg")) * self.mining * 0.8
                < loss + 150):
            build("ice_miner")

        # 사회·연구·산업
        if p("research_lab") < math.ceil(pop / 60):
            build("research_lab")
        if prepared and p("green_commons") < pop // 100:
            build("green_commons")
        if cap(lambda m: provided(m, "care"), lambda m: provided(m, "care")) < pop_next:
            build("medical_bay")
        if p("excavator") < 1 + (self.fam_queued("regolith_dome") + self.fam_queued("storm_shelter")) // 2:
            build("excavator")
        if "molten_regolith_electrolysis" in self.techs and p("mre_plant") < 1:
            build("mre_plant")
        if "local_manufacturing" in self.techs and p("parts_fab") < 2 * max(1, p("mre_plant")):
            build("parts_fab")
        if self.robots + self.queued("robot") < 8 + pop / 40:
            self.enqueue_special("robot")

    def fam_planned(self, fam):
        """계열의 계획 수량 (완공 + 대기)."""
        return sum(self.planned(m) for m in FAMILY[fam])

    def fam_queued(self, fam):
        return sum(self.queued(m) for m in FAMILY[fam])

    def planned_cap(self, which, value):
        """which(모듈)이 참인 모듈마다 계획 수량 × value(모듈)을 더한다 (데이터 순서)."""
        total = 0.0
        for m in MODULES:
            if which(m):
                total += self.planned(m) * value(m)
        return total

    def build(self, fam, tile=None):
        """정책의 건설: 보통은 계열의 기본 모듈. 'variety' 정책은 계열의 종류를 돌아가며 고르고, 못 지으면 기본 모듈."""
        if not self.policy.variety:
            return self.enqueue(fam, tile)
        options = [m for m in FAMILY[fam] if not MODULES[m]["tech"] or MODULES[m]["tech"] in self.techs]
        if not options:
            return self.enqueue(fam, tile)
        pick = options[self.variety_turn % len(options)]
        self.variety_turn += 1
        if pick != fam and self.enqueue(pick, tile):
            return True
        return self.enqueue(fam, tile)

    def research(self):
        prod = 0.8 + 0.4 * self.morale / 100
        p4_share = 1.0 - self.day["p4_off_h"] / 24.0
        scientists = min(self.fam_sum("research_lab", lambda m: spec(m, "crew")),
                         self.pop * self.C["workforce_share"] * 0.3)
        rp_direct = 0.0           # 연구원 없이 나오는 연구 (교신·천문대 등)
        for m in WITH["rp_day"]:
            if family(m) != "research_lab":
                rp_direct += self.wk[m] * provided(m, "rp_day")
        rp = (scientists * prod * p4_share
              + rp_direct * p4_share
              + self.C["earth"]["earth_rp_day"])
        self.rp_bank += rp
        self.support += rp * self.C["earth"]["support_per_rp"]
        for _ in range(len(self.research_queue)):
            if not self.research_queue:
                break
            if self.research_queue[0] in self.techs:        # 다른 식민지에서 이미 알아냈다
                self.research_queue.pop(0)
                continue
            tech = TECHS[self.research_queue[0]]
            if any(r not in self.techs for r in tech["requires"]):
                self.research_queue.append(self.research_queue.pop(0))   # 선행 기술이 없으면 뒤로
                continue
            if self.rp_bank < tech["cost"]:
                break
            self.rp_bank -= tech["cost"]
            self.techs.add(tech["id"])
            self.research_queue.pop(0)
            self.note(f"연구 완료 — {tech['name']}")
            break

    def earth(self, day):
        earth = self.C["earth"]
        rng = self.rng
        self.support += earth["support_per_month"] / 30.0
        self.food_emergency(day)
        if day >= self.next_cargo:
            if self.support < earth["cargo_cost_support"]:
                self.next_cargo = day + 30
                self.stats["cargo_skipped"] += 1
                self.note("지원 점수 부족 — 화물선 연기")
            elif rng.random() < earth["delay_chance"]:
                self.next_cargo = day + rng.randint(*earth["delay_days"])
                self.note("화물선 지연")
            else:
                self.support -= earth["cargo_cost_support"]
                self.next_cargo = day + earth["cargo_interval_days"]
                if rng.random() < earth["loss_chance"]:
                    self.stats["cargo_lost"] += 1
                    self.trust_event(-1)
                    self.note("화물선 발사 실패 — 화물 손실")
                else:
                    self.deliver_cargo()
        if day >= self.next_crewed:
            self.next_crewed = day + earth["crewed_interval_days"]
            seats_back = earth["crewed_seats"]
            for cohort in self.cohorts:
                if cohort[2] and seats_back:
                    go = min(cohort[0], seats_back)
                    cohort[0] -= go
                    seats_back -= go
                    self.stats["departed_dose"] += go
            if self.morale < 40 and seats_back:
                unhappy = min(seats_back, round(self.pop * 0.1))
                self.send_home(unhappy)
                self.stats["departed_morale"] += unhappy
                self.trust_event(-3)
            self.cohorts = [c for c in self.cohorts if c[0] > 0]
            if self.support < earth["crewed_cost_support"]:
                self.stats["crewed_skipped"] += 1
                return
            seats = min(earth["crewed_seats"], int(self.housing_cap - self.pop))
            if self.policy.prepared:
                scrub = self.fam_sum("co2_scrubber", lambda m: provided(m, "co2_kg_day"))
                seats = min(seats, int(scrub / PER["co2_kg"] / 1.1 - self.pop))
            if seats > 0:
                self.support -= earth["crewed_cost_support"]
                self.cohorts.append([float(seats), 0.0, False])
                self.stats["arrived"] += seats
                self.note(f"유인 착륙선 도착 — {seats}명")
            else:
                self.stats["crewed_unused"] += 1

    def food_emergency(self, day):
        """배급과 긴급 보급선. 기아 사망은 식량 없이 14일이 지난 뒤부터 하루 2%."""
        earth = self.C["earth"]
        s = self.stock
        need = self.pop * PER["food_kg"]
        reserve = s["food_kg"] / need if need else 99.0
        self.rationing = reserve < self.policy.ration_below_days
        if self.express_eta is not None and day >= self.express_eta:
            self.express_eta = None
            s["food_kg"] += earth["express_capacity_units"] / earth["food_units_per_t"] * 1000.0
            self.note("긴급 보급선 도착 — 식량 10 t")
        elif (self.express_eta is None and reserve < self.policy.express_below_days
              and self.next_cargo - day > reserve and self.support >= earth["express_cost_support"]):
            self.support -= earth["express_cost_support"]
            self.express_eta = day + earth["express_days"]
            self.stats["express"] += 1
            self.trust_event(-1)
            self.note("긴급 보급선 요청 (지원 −300)")
        self.hungry_days = self.hungry_days + 1 if self.day["no_food"] else 0
        if self.hungry_days > self.C["starvation_grace_days"]:
            self.kill(max(1, round(self.pop * 0.02)), "starvation")

    def send_home(self, n):
        """사기가 떨어져 지구로 돌아가는 사람 (사망이 아님). 선량이 높은 사람부터."""
        for cohort in sorted(self.cohorts, key=lambda c: -c[1]):
            take = min(cohort[0], n)
            cohort[0] -= take
            n -= take
            if n <= 0:
                break

    def deliver_cargo(self):
        earth = self.C["earth"]
        s = self.stock
        capacity = earth["cargo_capacity_units"]
        horizon = earth["cargo_interval_days"] + 15
        food_of = lambda m: recipe(m, "out", "food_kg")  # noqa: E731
        produced = (self.fam_sum("hydroponics", food_of) * (1 if self.crops_alive() else 0)
                    + self.fam_sum("algae_reactor", food_of))
        deficit = (self.pop * PER["food_kg"] - produced) * horizon
        reserve = self.pop * PER["food_kg"] * self.policy.food_buffer_days
        food_t = max(0.0, deficit + reserve - s["food_kg"]) / 1000.0
        food_units = min(capacity, math.ceil(food_t * earth["food_units_per_t"]))
        s["food_kg"] += food_units / earth["food_units_per_t"] * 1000.0
        capacity -= food_units
        if "robot_fabrication" not in self.techs and self.robots < 8 + self.pop / 40 and capacity >= 10:
            self.robots += 2
            capacity -= 2 * self.C["robots"]["earth_units"]
        s["parts"] += capacity
        self.stats["cargo_delivered"] += 1

    def space_weather(self, day):
        spe = self.C["spe"]
        activity = solar_activity(self.year())
        major = spe["major_rate_per_year"]["solar_min"] + spe["major_rate_per_year"]["added_at_solar_max"] * activity
        minor = spe["minor_rate_per_year"]["solar_min"] + spe["minor_rate_per_year"]["added_at_solar_max"] * activity
        if day == spe["scripted_major_day"] or self.rng.random() < major / 365.25:
            self.solar_storm(spe["major_dose_msv"], "major")
        elif self.rng.random() < minor / 365.25:
            self.solar_storm(spe["minor_dose_msv"], "minor")

    def solar_storm(self, dose, kind):
        pop = self.pop
        exposed = max(0.0, pop - self.shelter_cap)
        factor = self.C["spe"]["shelter_factor"]
        exposed_share = exposed / pop if pop else 0.0
        for cohort in self.cohorts:
            cohort[1] += dose * factor + dose * (1 - factor) * exposed_share
        self.stats[f"spe_{kind}"] += 1
        if exposed > 0:
            self.stats["exposed_person_events"] += exposed
            self.recent_exposure = 1.0
            self.trust_event(-20 * exposed_share if kind == "major" else -3 * exposed_share)
            self.note(f"태양 양성자 폭풍({'대형' if kind == 'major' else '소형'}) — 대피소 밖 {exposed:.0f}명 {dose} mSv 피폭")
        else:
            self.trust_event(2)
            self.note(f"태양 양성자 폭풍({'대형' if kind == 'major' else '소형'}) — 전원 대피 완료")

    def dose_and_departures(self):
        rates = self.C["dose_msv_day"]
        pop = self.pop
        domes = 0                 # 돔 계열 (두꺼운 차폐)
        covered_more = 0          # 벽 자체가 피복인 거주 (인쇄 거주동 등)
        for m in WITH["housing"]:
            if family(m) == "regolith_dome" or provided(m, "dose", "") == "dome":
                domes += self.counts[m] * provided(m, "housing")
            elif provided(m, "dose", "") == "covered":
                covered_more += self.counts[m] * provided(m, "housing")
        covered = min(self.covered_habs, self.counts["hab_module"]) * provided("hab_module", "housing") + covered_more
        in_dome = min(pop, domes)
        in_covered = min(pop - in_dome, covered)
        bare = max(0.0, pop - in_dome - in_covered)
        rate = (in_dome * rates["dome"] + in_covered * rates["covered_hab"] + bare * rates["bare_hab"]) / pop if pop else 0.0
        for cohort in self.cohorts:
            cohort[1] += rate
            if not cohort[2] and cohort[1] >= self.C["career_dose_limit_msv"]:
                cohort[2] = True
                self.trust_event(-0.1 * cohort[0])
                self.note(f"선량 한도 도달 — {cohort[0]:.0f}명이 다음 유인선으로 귀환 예정")

    def update_morale(self):
        target = 70.0
        ppm = self.co2_ppm()
        limits = self.C["co2_ppm"]
        if ppm > limits["bad"]:
            target -= 15
        elif ppm > limits["warn"]:
            target -= 5
        pop = self.pop
        if pop:
            if self.stock["o2_kg"] / (pop * PER["o2_kg"]) < 3:
                target -= 10
            if self.stock["food_kg"] / (pop * PER["food_kg"]) < 10:
                target -= 10
            crowd = pop / max(1.0, self.housing_cap)
            target -= 15 if crowd > 1.0 else (5 if crowd > 0.95 else 0)
            if self.shelter_cap < pop:
                target -= 5
            care = 0.0
            for m in WITH["care"]:
                care += self.wk[m] * provided(m, "care")
            if care < pop:
                target -= 5
        if self.algae_food_share > 0.25:
            target -= 5
        if self.rationing:
            target -= self.C["rationing"]["morale_penalty"]
        leisure = 0.0             # 공원·체육관·주방… (합쳐서 최대 +15)
        for m in WITH["morale"]:
            if family(m) != "comms_center":
                leisure += self.wk[m] * provided(m, "morale")
        target += min(15, leisure)
        contact = 0               # 지구와의 연결 — 가동 중인 교신 계열 중 가장 좋은 것 하나
        for m in FAMILY["comms_center"]:
            if self.wk[m] and provided(m, "morale") > contact:
                contact = provided(m, "morale")
        target += contact * self.contact_k     # 지연이 길면 영상 통화가 안 된다
        self.p4_off_week = (self.p4_off_week + [self.day["p4_off_h"]])[-7:]
        if sum(self.p4_off_week) > 48:
            target -= 5
        target -= 20 * self.recent_deaths + 10 * self.recent_exposure
        if any(c[1] > 400 for c in self.cohorts):
            target -= 5
        self.recent_deaths *= 0.97
        self.recent_exposure *= 0.97
        self.morale += (target - self.morale) * 0.1
        self.trust_memory *= 0.998
        self.trust += ((self.morale - 5 + self.trust_memory) - self.trust) * 0.05
        self.trust = max(0.0, min(100.0, self.trust))

    def record(self, day):
        pop = self.pop
        s = self.stock
        food_need = pop * PER["food_kg"]
        total_cap = self.bat_cap + self.rfc_cap
        self.daily.append({
            "day": day,
            "date": (self.start_date + timedelta(days=day)).isoformat(),
            "population": round(pop),
            "o2_reserve_days": round(s["o2_kg"] / (pop * PER["o2_kg"]), 1) if pop else 0,
            "co2_ppm": round(self.co2_ppm()),
            "food_self_sufficiency": round(self.day["food_made"] / food_need, 3) if food_need else 0,
            "food_reserve_days": round(s["food_kg"] / food_need, 1) if food_need else 0,
            "water_t": round(s["water_kg"] / 1000, 1),
            "storage_kwh": round(total_cap),
            "soc": round((self.battery + self.rfc) / total_cap, 2) if total_cap else 0,
            "dark_h": sum(self.dark[day * 24:(day + 1) * 24]),
            "farms_off_h": self.day["p2_off_h"],
            "parts": round(s["parts"]),
            "robots": self.robots,
            "housing": round(self.housing_cap),
            "shelter": round(self.shelter_cap),
            "morale": round(self.morale, 1),
            "trust": round(self.trust, 1),
            "techs": len(self.techs),
            "avg_dose_msv": round(sum(c[0] * c[1] for c in self.cohorts) / pop, 1) if pop else 0,
            "brownout_total_h": self.stats["brownout_h"],
            "crop_losses_total": self.stats["crop_losses"],
        })
        near_miss = (self.day["low_soc"] or self.day["co2_warn"] or self.day["brownout"]
                     or (pop and s["o2_kg"] / (pop * PER["o2_kg"]) < 5)
                     or (pop and s["food_kg"] / food_need < 7))
        self.stats["near_miss_days"] += 1 if near_miss else 0
        self.stats["rationing_days"] += 1 if self.rationing else 0
        self.day = Counter()

    def note(self, text):
        self.log.append((self.start_date + timedelta(hours=self.hour), text))

    def run(self):
        for day in range(self.days):
            pop = self.pop
            for _ in range(24):
                self.step_hour(pop)
            self.step_day(day)
        return self

    def summary(self):
        daily = self.daily
        years = []
        for y in range(len(daily) // 365):
            chunk = daily[y * 365:(y + 1) * 365]
            years.append({
                "food_self_sufficiency": round(sum(d["food_self_sufficiency"] for d in chunk[-30:]) / 30, 2),
                "population": chunk[-1]["population"],
                "near_miss_days": None,
            })
        return {
            "deaths": sum(self.deaths.values()),
            "death_causes": dict(self.deaths),
            "crop_losses": self.stats["crop_losses"],
            "exposed_person_events": round(self.stats["exposed_person_events"]),
            "spe_major": self.stats["spe_major"],
            "max_co2_ppm": round(self.max_co2),
            "co2_bad_hours": self.stats["co2_bad_h"],
            "brownout_hours": self.stats["brownout_h"],
            "min_o2_reserve_days": round(self.min_reserve_days, 1),
            "near_miss_days_per_year": round(self.stats["near_miss_days"] / (len(daily) / 365.25), 1),
            "departed_dose": round(self.stats["departed_dose"]),
            "departed_morale": round(self.stats["departed_morale"]),
            "arrived": self.stats["arrived"],
            "crewed_unused": self.stats["crewed_unused"],
            "population_end": round(self.pop),
            "years": years,
            "morale_avg": round(sum(d["morale"] for d in daily) / len(daily), 1),
            "trust_end": round(self.trust, 1),
            "techs": len(self.techs),
            "avg_dose_end": daily[-1]["avg_dose_msv"],
            "cargo_lost": self.stats["cargo_lost"],
            "express": self.stats["express"],
            "rationing_days": self.stats["rationing_days"],
            "failures": self.stats["failures"],
            "built": self.stats["built"],
        }


# ── 출력 ────────────────────────────────────────────────────────────
def print_run(city):
    print(f"부지: {city.site.get('name', city.site_id)} · 정책: {city.policy.name} · {city.days}일 · 시작 {city.start_date.isoformat()}")
    print("  분기말        인구 주거 대피  O₂비축  CO₂ppm  식량자급 식량비축 축전kWh  부품 로봇 사기 신뢰 평균선량 기술")
    for d in city.daily[89::91]:
        print(f"  {d['date']}  {d['population']:>4} {d['housing']:>4} {d['shelter']:>4} {d['o2_reserve_days']:>7} "
              f"{d['co2_ppm']:>7} {d['food_self_sufficiency']:>8.0%} {d['food_reserve_days']:>8} {d['storage_kwh']:>7} "
              f"{d['parts']:>5} {d['robots']:>4} {d['morale']:>4.0f} {d['trust']:>4.0f} {d['avg_dose_msv']:>8.0f} {d['techs']:>4}")
    print("\n요약")
    for key, value in city.summary().items():
        print(f"  {key}: {value}")
    print("\n사건 기록 (처음 30개)")
    for when, text in city.log[:30]:
        print(f"  {when:%Y-%m-%d}  {text}")


def monte_carlo(runs, years):
    results = {policy: [City(seed=1000 + i, policy=policy, years=years).run().summary() for i in range(runs)]
               for policy in ("good", "naive")}

    def share(rows, f):
        return f"{sum(1 for r in rows if f(r)) / len(rows):.0%}"

    def mean(rows, f):
        return sum(f(r) for r in rows) / len(rows)

    metrics = [
        ("사망자가 나온 판", lambda rows: share(rows, lambda r: r["deaths"] > 0)),
        ("작물 고사를 한 번 이상 겪은 판", lambda rows: share(rows, lambda r: r["crop_losses"] > 0)),
        ("평균 작물 고사", lambda rows: f"{mean(rows, lambda r: r['crop_losses']):.1f}회"),
        ("폭풍 때 대피소 밖에 있던 사람 (연인원)", lambda rows: f"{mean(rows, lambda r: r['exposed_person_events']):.0f}명"),
        ("CO₂ 5,000 ppm 초과", lambda rows: f"{mean(rows, lambda r: r['co2_bad_hours']):,.0f}시간"),
        ("최고 CO₂", lambda rows: f"{mean(rows, lambda r: r['max_co2_ppm']):,.0f} ppm"),
        ("생명유지 전력 부족", lambda rows: f"{mean(rows, lambda r: r['brownout_hours']):,.0f}시간"),
        ("아슬아슬한 날", lambda rows: f"연 {mean(rows, lambda r: r['near_miss_days_per_year']):.0f}일"),
        ("선량 한도로 귀환", lambda rows: f"{mean(rows, lambda r: r['departed_dose']):.0f}명"),
        ("1년차 말 식량 자급률", lambda rows: f"{mean(rows, lambda r: r['years'][0]['food_self_sufficiency']):.0%}"),
        ("3년차 말 식량 자급률", lambda rows: f"{mean(rows, lambda r: r['years'][-1]['food_self_sufficiency']):.0%}"),
        ("3년차 말 인구", lambda rows: f"{mean(rows, lambda r: r['population_end']):.0f}명"),
        ("3년차 말 평균 누적 선량", lambda rows: f"{mean(rows, lambda r: r['avg_dose_end']):.0f} mSv"),
        ("평균 사기", lambda rows: f"{mean(rows, lambda r: r['morale_avg']):.0f}"),
        ("3년차 말 신뢰", lambda rows: f"{mean(rows, lambda r: r['trust_end']):.0f}"),
        ("완료한 기술", lambda rows: f"{mean(rows, lambda r: r['techs']):.1f}개"),
    ]
    print(f"| 지표 ({runs}회 평균, {years:g}년) | 추천 정책 | 준비 없는 정책 |")
    print("|---|---|---|")
    for label, fn in metrics:
        print(f"| {label} | {fn(results['good'])} | {fn(results['naive'])} |")


CATEGORY_KO = {"habitat": "거주", "life_support": "생명유지", "food": "식량", "power": "전력",
               "thermal": "열", "industry": "산업", "logistics": "물류", "safety": "안전",
               "research": "연구", "social": "사회"}


def module_table(families=False):
    """문서용 모듈 표. families=True면 계열마다 기본 모듈 아래에 같은 계열의 다른 종류를 둔다 (145종)."""
    names = CATEGORY_KO
    print("| 모듈 | 분류 | 절전 순위 | 필요 기술 | 시작 | 비용 | 건설 (로봇·일) | 전력 (kW) | 인원 | 고장 간격 (일) "
          "| 수리 (부품 · 로봇·일) | 기능 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    units = (("parts", "부품 {}"), ("regolith_t", "레골리스 {} t"), ("metal_t", "금속 {} t"), ("water_kg", "물 {:,} kg"))
    if families:
        rows = [(m, MODULES[m]["id"] != fam) for fam in FAMILY for m in FAMILY[fam]]
    else:
        rows = [(m, False) for m in MODULES if family(m) == m]
    for mid, member in rows:
        m = MODULES[mid]
        cost = " + ".join(fmt.format(m["cost"][k]) for k, fmt in units if m["cost"].get(k))
        tech = TECHS[m["tech"]]["name"] if m["tech"] else "–"
        name = f"└ {m['name']}" if member else f"**{m['name']}**" if families else m["name"]
        print(f"| {name} | {names[m['category']]} | {m['priority'] or '–'} | {tech} | {m['start'] or '–'} | "
              f"{cost} | {m['build_rd']:g} | {m['power_kw'] or '–'} | {m['crew'] or '–'} | {m['mtbf_days']:,} | "
              f"{m['repair']['parts']} · {m['repair']['rd']:g} | {describe(m)} |")


RESOURCE_KO = {"o2_kg": "산소", "h2_kg": "수소", "water_kg": "물", "co2_kg": "CO₂", "ch4_kg": "메탄",
               "food_kg": "식량", "regolith_t": "레골리스", "metal_t": "금속", "parts": "부품",
               "propellant_t": "추진제", "wastewater_kg": "폐수"}


def amount(key, value):
    unit = "t" if key.endswith("_t") else ("" if key == "parts" else "kg")
    return f"{RESOURCE_KO[key]} {value:,g}{(' ' + unit) if unit else ''}"


def describe(m):
    out = []
    pv = m.get("provides", {})
    labels = {"housing": "거주 {}명", "shelter": "대피 {}명", "generation_kw": "발전 {:,} kW", "landing_slots": "착륙 슬롯 {}",
              "storage_kwh": "축전 {:,} kWh", "heat_kw": "방열 {} kW", "co2_kg_day": "CO₂ 제거 {} kg/일",
              "wastewater_kg_day": "폐수 처리 {:,} kg/일", "rp_day": "연구 {} RP/일", "morale": "사기 +{}",
              "care": "진료 {}명", "robot_slots": "로봇 {}대 정비", "print_t_day": "인쇄 {} t/일"}
    for key, fmt in labels.items():
        if key in pv:
            out.append(fmt.format(pv[key]))
    if "efficiency" in pv:
        out.append(f"왕복 효율 {pv['efficiency']:.0%}")
    elif "storage_kwh" in pv and "family" in m:
        base = MODULES[m["family"]].get("provides", {})
        if "efficiency" in base:
            out.append(f"왕복 효율 {base['efficiency']:.0%}")
    if pv.get("dose") == "covered":
        out.append("두꺼운 벽 — 피복 모듈 수준 선량")
    if "clearance_m" in m:
        out.append(f"거리 규칙 {m['clearance_m']} m")
    if "recovery" in pv:
        out.append(f"회수 {pv['recovery']:.0%}")
    if "storage" in pv:
        out.append("저장: " + ", ".join(amount(k, v) for k, v in pv["storage"].items()))
    if "recipe" in m:
        ins = ", ".join(amount(k, v) for k, v in m["recipe"]["in"].items())
        outs = ", ".join(amount(k, v) for k, v in m["recipe"]["out"].items())
        out.append(f"{ins or '채굴'} → {outs} (하루)")
    return " · ".join(out)


def tech_table():
    plausibility = {"proven": "검증됨", "engineering": "공학적", "theoretical": "이론적"}
    print("| 기술 | 분야 | 현실성 | 비용 (RP) | 선행 기술 | 효과 |")
    print("|---|---|---|---|---|---|")
    for t in TECHS.values():
        requires = ", ".join(TECHS[r]["name"] for r in t["requires"]) or "–"
        print(f"| {t['name']} | {t['category']} | {plausibility[t['plausibility']]} | {t['cost']:,} | {requires} | {t['effect']} |")


def main():
    parser = argparse.ArgumentParser(description="SpaceCity 도시 레이어 밸런스 시뮬레이터")
    parser.add_argument("--seed", type=int, default=2061)
    parser.add_argument("--policy", choices=("good", "naive", "variety"), default="good")
    parser.add_argument("--years", type=float, default=3)
    parser.add_argument("--site", choices=list(SITES), default=HOME_SITE, help="부지 (../data/city_sites.json)")
    parser.add_argument("--monte-carlo", type=int, metavar="N", help="두 정책을 N회씩 돌려 비교")
    parser.add_argument("--module-table", action="store_true", help="문서용 모듈 표 출력 (기본 모듈 29종)")
    parser.add_argument("--module-catalog", action="store_true", help="문서용 전체 모듈 표 (29계열 145종)")
    parser.add_argument("--tech-table", action="store_true", help="문서용 기술 표 출력")
    parser.add_argument("--csv", metavar="PATH", help="일별 기록을 CSV로 저장")
    args = parser.parse_args()

    if args.module_table or args.module_catalog:
        module_table(families=args.module_catalog)
        return
    if args.tech_table:
        tech_table()
        return
    if args.monte_carlo:
        monte_carlo(args.monte_carlo, args.years)
        return
    city = City(seed=args.seed, policy=args.policy, years=args.years, site=args.site).run()
    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(city.daily[0]))
            writer.writeheader()
            writer.writerows(city.daily)
    print_run(city)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:  # `| head`처럼 출력을 일찍 닫아도 조용히 끝낸다
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(1)
