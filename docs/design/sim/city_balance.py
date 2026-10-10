#!/usr/bin/env python3
"""SpaceCity 도시 레이어 밸런스 시뮬레이터 — M0 '종이 프로토타입'.

시대 0의 첫 3년(달 남극 섀클턴 시드 시티)을 1시간 단위로 돌려,
생명유지·전력·차폐·식량의 '빠듯함'이 설계 의도대로 나오는지 확인한다.
수치는 ../data/city_modules.json, ../data/city_techs.json 에서 읽는다.

    python3 city_balance.py                      # 추천 정책 1회, 분기별 요약
    python3 city_balance.py --policy naive       # 준비 없이 성장만 좇는 정책
    python3 city_balance.py --monte-carlo 200    # 두 정책을 각각 200회 돌려 비교
    python3 city_balance.py --module-table       # 문서용 모듈 표 (Markdown)
    python3 city_balance.py --csv daily.csv      # 일별 기록 (차트용)

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

PER = C["per_person_day"]
START = date.fromisoformat(C["start"]["date"])
STOCK_KEYS = ("o2_kg", "water_kg", "h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "food_kg")
CAUSES_KO = {"hypoxia": "산소 결핍", "co2": "이산화탄소 중독", "starvation": "기아"}
# 가동률이 시간마다 달라지는 모듈 — 나머지는 하루 단위로 미리 합산해 둔다
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


def spec(mid, key, default=0.0):
    return MODULES[mid].get(key, default)


def provided(mid, key, default=0.0):
    return MODULES[mid].get("provides", {}).get(key, default)


def recipe(mid, side, key):
    return MODULES[mid].get("recipe", {}).get(side, {}).get(key, 0.0)


def illumination_schedule(rng, hours):
    """시간별 그림자 여부(1 = 어두움). 평소엔 드물고 짧게, 남극 겨울엔 잦고 길게."""
    il = C["illumination"]
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


def solar_activity(year):
    """0(극소기) ~ 1(극대기). 11년 주기, 극대기 2069년."""
    spe = C["spe"]
    return 0.5 + 0.5 * math.cos(2 * math.pi * (year - spe["cycle_max_year"]) / spe["cycle_years"])


class Policy:
    """플레이어 대역. 'good'은 문서의 추천 운영, 'naive'는 눈앞의 성장만 좇는 운영."""

    def __init__(self, name):
        self.name = name
        self.prepared = name == "good"
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
    def __init__(self, seed=2061, policy="good", years=3):
        self.rng = random.Random(seed)
        self.policy = Policy(policy)
        self.days = int(round(365.25 * years))
        self.dark = illumination_schedule(random.Random(seed * 7919 + 1), self.days * 24 + 48)
        start = C["start"]
        self.hour = 0
        self.counts = Counter({mid: m["start"] for mid, m in MODULES.items() if m["start"]})
        self.broken = Counter()
        self.tiles = Counter(start["solar_tiles_used"])
        self.covered_habs = 0
        self.robots = C["robots"]["start"]
        self.robots_broken = 0
        self.queue = []          # 건설 대기열: {"id", "rd", "print_t", "seq"}
        self.seq = 0
        self.stock = {k: 0.0 for k in STOCK_KEYS}
        self.stock.update({k: float(v) for k, v in start["stocks"].items()})
        self.cohorts = [[float(start["population"]), 0.0, False]]   # [인원, 누적 선량 mSv, 귀환 대기]
        self.morale = float(start["morale"])
        self.trust = float(start["trust"])
        self.trust_memory = 0.0  # 사건이 남긴 신뢰의 흔적. 반감기 약 1년
        self.support = float(C["earth"]["support_start"])
        self.techs = set()
        self.rp_bank = 0.0
        self.research_queue = list(self.policy.research)
        self.farm_dark_h = 0
        self.crops_dead_until = -1
        self.prev = {2: True, 3: True, 4: True}
        earth = C["earth"]
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
        self.caps = {key: sum(provided(m, "storage", {}).get(key, 0.0) * wk[m] for m in MODULES)
                     for key in STOCK_KEYS}
        self.housing_cap = sum(provided(m, "housing") * self.counts[m] for m in MODULES)
        self.air = max(1.0, self.housing_cap) * C["air_kg_per_housing"]
        self.co2_floor = self.ppm_to_kg(C["co2_ppm"]["floor"])
        bonus = 1.5 if "shielding_2" in self.techs else 1.0
        self.shelter_cap = (provided("storm_shelter", "shelter") * self.counts["storm_shelter"] * bonus
                            + provided("regolith_dome", "shelter") * self.counts["regolith_dome"])
        self.bat_cap = provided("battery_bank", "storage_kwh") * wk["battery_bank"]
        self.rfc_cap = provided("rfc_unit", "storage_kwh") * wk["rfc_unit"]
        towers = sum(self.tiles.values())
        tile_factor = C["illumination"]["tile_factor"]
        factor = sum(tile_factor[t] * n for t, n in self.tiles.items()) / towers if towers else 0.0
        boost = 1.2 if "tall_towers" in self.techs else 1.0
        self.solar_kw = provided("solar_tower", "generation_kw") * wk["solar_tower"] * factor * boost
        self.fission_kw = sum(provided(m, "generation_kw") * wk[m] for m in ("fission_40kw", "fission_1mw"))
        self.heat_cap = provided("radiator", "heat_kw") * wk["radiator"]
        printing = any(item["print_t"] > 0 for item in self.queue)
        s = self.stock
        static = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
        for mid in MODULES:
            p = spec(mid, "priority")
            if not p or mid in VARIABLE or not wk[mid]:
                continue
            kw = spec(mid, "power_kw") * wk[mid]
            if mid == "regolith_printer" and not printing:
                kw *= 0.1
            elif mid == "mre_plant" and s.get("regolith_t", 0) < recipe("mre_plant", "in", "regolith_t"):
                kw = 0.0
            elif mid == "parts_fab" and s.get("metal_t", 0) < recipe("parts_fab", "in", "metal_t"):
                kw = 0.0
            elif mid == "robot_bay":
                kw += C["robots"]["power_kw"] * (self.robots - self.robots_broken)
            static[p] += kw
        self.static_load = static
        self.recovery = 0.98 if "closed_loop_ls2" in self.techs else provided("water_recycler", "recovery")
        self.mining = 1.4 if "polar_prospecting" in self.techs else 1.0

    def ppm_to_kg(self, ppm):
        return ppm / 1e6 * (self.air / 29.0) * 44.0

    def co2_ppm(self):
        return (self.co2_air / 44.0) / (self.air / 29.0) * 1e6

    @property
    def pop(self):
        return sum(c[0] for c in self.cohorts)

    def year(self):
        return START.year + self.hour / 8766.0

    def queued(self, mid):
        return sum(1 for item in self.queue if item["id"] == mid)

    def planned(self, mid):
        return self.counts[mid] + self.queued(mid)

    def crops_alive(self):
        return self.hour >= self.crops_dead_until

    # ── 1시간 ──────────────────────────────────────────────────────
    def step_hour(self, pop):
        lit = 1.0 - self.dark[self.hour]
        s = self.stock
        wk = self.wk
        h = 1.0 / 24.0

        # 가변 가동률: 전기분해기는 필요한 만큼, 사바티에·재활용기는 원료만큼
        farms_on_before = self.prev[2] and self.crops_alive()
        bio_o2 = ((wk["hydroponics"] * recipe("hydroponics", "out", "o2_kg") if farms_on_before else 0.0)
                  + (wk["algae_reactor"] * recipe("algae_reactor", "out", "o2_kg") if self.prev[2] else 0.0)
                  + (wk["green_commons"] * recipe("green_commons", "out", "o2_kg") if self.prev[4] else 0.0)
                  + (wk["mre_plant"] * recipe("mre_plant", "out", "o2_kg") if self.prev[3] else 0.0))
        want = pop * PER["o2_kg"] - bio_o2 + max(0.0, 0.95 * self.caps["o2_kg"] - s["o2_kg"])
        e_cap = wk["electrolyzer"] * recipe("electrolyzer", "out", "o2_kg")
        u_elec = min(1.0, max(0.0, want) / e_cap) if e_cap else 0.0
        water_need = wk["electrolyzer"] * recipe("electrolyzer", "in", "water_kg") * u_elec * h
        if water_need > s["water_kg"] > 0:
            u_elec *= s["water_kg"] / water_need
        elif s["water_kg"] <= 0:
            u_elec = 0.0
        n_sab = wk["sabatier"]
        u_sab = 0.0
        if n_sab:
            u_sab = max(0.0, min(1.0, s["h2_kg"] / (n_sab * recipe("sabatier", "in", "h2_kg") * h),
                                 s["co2_kg"] / (n_sab * recipe("sabatier", "in", "co2_kg") * h)))
        n_rec = wk["water_recycler"]
        rec_rate = n_rec * provided("water_recycler", "wastewater_kg_day") * h
        u_rec = min(1.0, s["wastewater_kg"] / rec_rate) if rec_rate else 0.0
        light_cut = 0.6 if (lit > 0 and "sunlight_piping" in self.techs) else 1.0

        load = dict(self.static_load)
        load[1] += (spec("electrolyzer", "power_kw") * wk["electrolyzer"] * u_elec
                    + spec("sabatier", "power_kw") * n_sab * u_sab
                    + spec("water_recycler", "power_kw") * n_rec * max(u_rec, 0.2))
        load[2] += spec("hydroponics", "power_kw") * wk["hydroponics"] * light_cut

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
        s["food_kg"] -= pop * PER["food_kg"] * h * (C["rationing"]["consumption_factor"] if self.rationing else 1.0)

        # 식량·생물 (2·4순위)
        bio_removal = 0.0
        food = 0.0
        if on[2] and self.crops_alive():
            n = wk["hydroponics"]
            food += n * recipe("hydroponics", "out", "food_kg") * h
            s["o2_kg"] += n * recipe("hydroponics", "out", "o2_kg") * h
            bio_removal += n * recipe("hydroponics", "in", "co2_kg") * h
            s["water_kg"] -= n * recipe("hydroponics", "in", "water_kg") * h
        algae = 0.0
        if on[2]:
            n = wk["algae_reactor"]
            algae = n * recipe("algae_reactor", "out", "food_kg") * h
            food += algae
            s["o2_kg"] += n * recipe("algae_reactor", "out", "o2_kg") * h
            bio_removal += n * recipe("algae_reactor", "in", "co2_kg") * h
            s["water_kg"] -= n * recipe("algae_reactor", "in", "water_kg") * h
        if on[4]:
            n = wk["green_commons"]
            s["o2_kg"] += n * recipe("green_commons", "out", "o2_kg") * h
            bio_removal += n * recipe("green_commons", "in", "co2_kg") * h
        s["food_kg"] += food
        self.day["food_made"] += food
        if food > 0:
            self.algae_food_share = 0.98 * self.algae_food_share + 0.02 * (algae / food)

        # CO₂: 식물이 먼저 흡수하고, 나머지는 제거기가 농축 탱크로 옮긴다
        self.co2_air = max(self.co2_floor, self.co2_air - bio_removal)
        scrub = wk["co2_scrubber"] * provided("co2_scrubber", "co2_kg_day") * h * frac1
        moved = min(scrub, self.co2_air - self.co2_floor)
        self.co2_air -= moved
        s["co2_kg"] += moved

        # 1순위 화학 공정 (전력이 모자라면 frac1만큼만)
        k = h * frac1
        n = wk["electrolyzer"] * u_elec * k
        s["water_kg"] -= n * recipe("electrolyzer", "in", "water_kg")
        s["o2_kg"] += n * recipe("electrolyzer", "out", "o2_kg")
        s["h2_kg"] += n * recipe("electrolyzer", "out", "h2_kg")
        n = n_sab * u_sab * k
        s["co2_kg"] -= n * recipe("sabatier", "in", "co2_kg")
        s["h2_kg"] -= n * recipe("sabatier", "in", "h2_kg")
        s["ch4_kg"] += n * recipe("sabatier", "out", "ch4_kg")
        s["water_kg"] += n * recipe("sabatier", "out", "water_kg")
        processed = min(s["wastewater_kg"], rec_rate * frac1)
        s["wastewater_kg"] -= processed
        s["water_kg"] += processed * self.recovery

        # 3순위 산업
        if run3:
            k3 = h * run3
            s["water_kg"] += wk["ice_miner"] * recipe("ice_miner", "out", "water_kg") * self.mining * k3
            s["regolith_t"] += wk["excavator"] * recipe("excavator", "out", "regolith_t") * k3
            n = min(wk["mre_plant"] * k3, s["regolith_t"] / recipe("mre_plant", "in", "regolith_t"))
            s["regolith_t"] -= n * recipe("mre_plant", "in", "regolith_t")
            s["metal_t"] += n * recipe("mre_plant", "out", "metal_t")
            s["o2_kg"] += n * recipe("mre_plant", "out", "o2_kg")
            n = min(wk["parts_fab"] * k3, s["metal_t"] / recipe("parts_fab", "in", "metal_t"))
            s["metal_t"] -= n * recipe("parts_fab", "in", "metal_t")
            s["parts"] += n * recipe("parts_fab", "out", "parts")

        # 저장 한도: 넘치는 수소·CO₂·메탄은 배출, 넘치는 폐수는 손실
        caps = self.caps
        for key in ("h2_kg", "ch4_kg", "co2_kg", "wastewater_kg", "o2_kg", "water_kg", "food_kg"):
            if s[key] > caps[key]:
                if key == "wastewater_kg":
                    self.stats["wastewater_lost_kg"] += s[key] - caps[key]
                s[key] = caps[key]

        # 작물: 72시간 넘게 전력을 못 받으면 고사
        self.farm_dark_h = 0 if (on[2] or not wk["hydroponics"]) else self.farm_dark_h + 1
        if self.farm_dark_h >= C["crops"]["dead_after_unpowered_h"] and self.crops_alive():
            self.crops_dead_until = self.hour + C["crops"]["regrow_days"] * 24
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
        limits = C["co2_ppm"]
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
        self.robots_broken += sum(1 for _ in range(working) if rng.random() < 1.0 / C["robots"]["mtbf_days"])

    def work_robots(self):
        s = self.stock
        speed = 1.5 if "autonomous_robots_2" in self.techs else 1.0
        rd = (self.robots - self.robots_broken) * speed
        while self.robots_broken and s["parts"] >= C["robots"]["repair_parts"] and rd >= 0.5:
            self.robots_broken -= 1
            s["parts"] -= C["robots"]["repair_parts"]
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
            self.queue.sort(key=lambda item: (BUILD_PRIORITY.get(item["id"], 5), item["seq"]))
        print_cap = provided("regolith_printer", "print_t_day") * self.wk["regolith_printer"]
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
                and s["metal_t"] >= cost.get("metal_t", 0))

    def enqueue(self, mid, tile=None):
        m = MODULES[mid]
        if m["tech"] and m["tech"] not in self.techs:
            return False
        if not self.can_afford(m["cost"]):
            self.day["short_parts"] = 1
            return False
        for key, value in m["cost"].items():
            self.stock[key] -= value
        print_t = m["cost"].get("regolith_t", 0) if mid == "regolith_dome" else 0
        self.seq += 1
        self.queue.append({"id": mid, "rd": m["build_rd"], "print_t": print_t, "seq": self.seq})
        if tile:
            self.tiles[tile] += 1
        return True

    def enqueue_special(self, kind):
        s = self.stock
        self.seq += 1
        if kind == "regolith_cover":
            need = C["regolith_cover"]
            if s["regolith_t"] < need["regolith_t"]:
                return False
            s["regolith_t"] -= need["regolith_t"]
            self.queue.append({"id": kind, "rd": need["build_rd"], "print_t": 0, "seq": self.seq})
            return True
        if kind == "robot" and "robot_fabrication" in self.techs and s["parts"] >= C["robots"]["local_parts"] + 40:
            s["parts"] -= C["robots"]["local_parts"]
            self.queue.append({"id": "robot", "rd": C["robots"]["local_rd"], "print_t": 0, "seq": self.seq})
            return True
        return False

    def free_tile(self):
        for tile in ("A", "B", "C"):
            if self.tiles[tile] < C["illumination"]["tiles"][tile]:
                return tile
        return None

    def decide(self, day):
        """정책이 하루에 한 번 건설을 결정한다. 계획 수량(완공 + 대기)을 기준으로 판단한다."""
        prepared = self.policy.prepared
        pop = self.pop
        pop_next = pop + C["earth"]["crewed_seats"]
        year_index = min(2, day // 365)
        p = self.planned

        # 생명유지: 추천 정책은 여유분을, 준비 없는 정책은 문제가 터진 뒤에 짓는다
        if prepared or self.co2_ppm() > C["co2_ppm"]["bad"]:
            if p("co2_scrubber") * provided("co2_scrubber", "co2_kg_day") < 1.3 * pop_next * PER["co2_kg"]:
                self.enqueue("co2_scrubber")
        if p("electrolyzer") * recipe("electrolyzer", "out", "o2_kg") < 1.2 * pop_next * PER["o2_kg"]:
            self.enqueue("electrolyzer")
        if p("water_recycler") * provided("water_recycler", "wastewater_kg_day") < 1.15 * pop_next * PER["water_use_kg"]:
            self.enqueue("water_recycler")
        if prepared:
            bonus = 1.5 if "shielding_2" in self.techs else 1.0
            if p("storm_shelter") * 40 * bonus + p("regolith_dome") * 60 < pop_next:
                self.enqueue("storm_shelter")
            if self.covered_habs + self.queued("regolith_cover") < self.counts["hab_module"]:
                self.enqueue_special("regolith_cover")

        # 저장: 1·2순위 부하를 48시간 버티는 축전 (추천 정책만)
        p1p2 = sum(spec(m, "power_kw") * self.counts[m] for m in MODULES if spec(m, "priority") in (1, 2))
        fission = sum(provided(m, "generation_kw") * p(m) for m in ("fission_40kw", "fission_1mw"))
        storage_planned = (p("battery_bank") * provided("battery_bank", "storage_kwh")
                           + p("rfc_unit") * provided("rfc_unit", "storage_kwh"))
        if prepared and storage_planned < max(0.0, p1p2 * 0.7 - fission) * 48:
            if not self.enqueue("rfc_unit") and "regenerative_fuel_cell" not in self.techs:
                self.enqueue("battery_bank")

        # 발전: 평균 발전량이 평균 수요의 1.25배(준비 없는 정책은 1.05배)
        avg_load = 0.85 * sum(spec(m, "power_kw") * p(m) for m in MODULES if spec(m, "priority"))
        tile_factor = C["illumination"]["tile_factor"]
        towers_gen = sum(tile_factor[t] * n for t, n in self.tiles.items()) * 100 * 0.9
        if towers_gen + fission < (1.25 if prepared else 1.05) * avg_load:
            tile = self.free_tile()
            if tile and not (prepared and tile == "C" and "megawatt_fission" in self.techs):
                self.enqueue("solar_tower", tile)
            elif not self.enqueue("fission_1mw"):
                self.enqueue("fission_40kw")
        if p("radiator") * provided("radiator", "heat_kw") < 1.2 * avg_load:
            self.enqueue("radiator")

        # 거주: 다음 유인선 도착분까지 집을 준비
        housing = p("hab_module") * provided("hab_module", "housing") + p("regolith_dome") * provided("regolith_dome", "housing")
        if housing < pop_next:
            if "sintered_construction" in self.techs:
                if self.planned("regolith_printer") or self.enqueue("regolith_printer"):
                    self.enqueue("regolith_dome")
            elif not prepared:
                self.enqueue("hab_module")
            elif day > 60:
                self.enqueue("hab_module")

        # 식량 자급률 목표
        target = self.policy.food_targets[year_index]
        need = target * pop * PER["food_kg"] - p("algae_reactor") * recipe("algae_reactor", "out", "food_kg")
        if p("hydroponics") * recipe("hydroponics", "out", "food_kg") < need:
            self.enqueue("hydroponics")
        if not prepared and "algae_bioreactor" in self.techs and p("algae_reactor") < pop / 60:
            self.enqueue("algae_reactor")
        if self.caps["food_kg"] < pop * PER["food_kg"] * 120 and not self.queued("food_store"):
            self.enqueue("food_store")
        if self.caps["o2_kg"] < pop * PER["o2_kg"] * 25 and not self.queued("tank_farm"):
            self.enqueue("tank_farm")

        # 물: 하루 순손실을 얼음 채굴이 넉넉히 덮도록
        loss = pop * PER["water_use_kg"] * (1 - self.recovery) + pop * PER["o2_kg"] * 0.6 * 1.125
        if p("ice_miner") * recipe("ice_miner", "out", "water_kg") * self.mining * 0.8 < loss + 150:
            self.enqueue("ice_miner")

        # 사회·연구·산업
        if p("research_lab") < math.ceil(pop / 60):
            self.enqueue("research_lab")
        if prepared and p("green_commons") < pop // 100:
            self.enqueue("green_commons")
        if p("medical_bay") * provided("medical_bay", "care") < pop_next:
            self.enqueue("medical_bay")
        if p("excavator") < 1 + (self.queued("regolith_dome") + self.queued("storm_shelter")) // 2:
            self.enqueue("excavator")
        if "molten_regolith_electrolysis" in self.techs and p("mre_plant") < 1:
            self.enqueue("mre_plant")
        if "local_manufacturing" in self.techs and p("parts_fab") < 2 * max(1, p("mre_plant")):
            self.enqueue("parts_fab")
        if self.robots + self.queued("robot") < 8 + pop / 40:
            self.enqueue_special("robot")

    def research(self):
        prod = 0.8 + 0.4 * self.morale / 100
        p4_share = 1.0 - self.day["p4_off_h"] / 24.0
        scientists = min(self.wk["research_lab"] * spec("research_lab", "crew"),
                         self.pop * C["workforce_share"] * 0.3)
        rp = (scientists * prod * p4_share
              + self.wk["comms_center"] * provided("comms_center", "rp_day") * p4_share
              + C["earth"]["earth_rp_day"])
        self.rp_bank += rp
        self.support += rp * C["earth"]["support_per_rp"]
        for _ in range(len(self.research_queue)):
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
        earth = C["earth"]
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
                scrub = self.wk["co2_scrubber"] * provided("co2_scrubber", "co2_kg_day")
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
        earth = C["earth"]
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
        if self.hungry_days > C["starvation_grace_days"]:
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
        earth = C["earth"]
        s = self.stock
        capacity = earth["cargo_capacity_units"]
        horizon = earth["cargo_interval_days"] + 15
        produced = (self.wk["hydroponics"] * recipe("hydroponics", "out", "food_kg") * (1 if self.crops_alive() else 0)
                    + self.wk["algae_reactor"] * recipe("algae_reactor", "out", "food_kg"))
        deficit = (self.pop * PER["food_kg"] - produced) * horizon
        reserve = self.pop * PER["food_kg"] * self.policy.food_buffer_days
        food_t = max(0.0, deficit + reserve - s["food_kg"]) / 1000.0
        food_units = min(capacity, math.ceil(food_t * earth["food_units_per_t"]))
        s["food_kg"] += food_units / earth["food_units_per_t"] * 1000.0
        capacity -= food_units
        if "robot_fabrication" not in self.techs and self.robots < 8 + self.pop / 40 and capacity >= 10:
            self.robots += 2
            capacity -= 2 * C["robots"]["earth_units"]
        s["parts"] += capacity
        self.stats["cargo_delivered"] += 1

    def space_weather(self, day):
        spe = C["spe"]
        activity = solar_activity(self.year())
        major = spe["major_rate_per_year"][0] + spe["major_rate_per_year"][1] * activity
        minor = spe["minor_rate_per_year"][0] + spe["minor_rate_per_year"][1] * activity
        if day == spe["scripted_major_day"] or self.rng.random() < major / 365.25:
            self.solar_storm(spe["major_dose_msv"], "major")
        elif self.rng.random() < minor / 365.25:
            self.solar_storm(spe["minor_dose_msv"], "minor")

    def solar_storm(self, dose, kind):
        pop = self.pop
        exposed = max(0.0, pop - self.shelter_cap)
        factor = C["spe"]["shelter_factor"]
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
        rates = C["dose_msv_day"]
        pop = self.pop
        domes = self.counts["regolith_dome"] * provided("regolith_dome", "housing")
        covered = min(self.covered_habs, self.counts["hab_module"]) * provided("hab_module", "housing")
        in_dome = min(pop, domes)
        in_covered = min(pop - in_dome, covered)
        bare = max(0.0, pop - in_dome - in_covered)
        rate = (in_dome * rates["dome"] + in_covered * rates["covered_hab"] + bare * rates["bare_hab"]) / pop if pop else 0.0
        for cohort in self.cohorts:
            cohort[1] += rate
            if not cohort[2] and cohort[1] >= C["career_dose_limit_msv"]:
                cohort[2] = True
                self.trust_event(-0.1 * cohort[0])
                self.note(f"선량 한도 도달 — {cohort[0]:.0f}명이 다음 유인선으로 귀환 예정")

    def update_morale(self):
        target = 70.0
        ppm = self.co2_ppm()
        limits = C["co2_ppm"]
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
            if self.wk["medical_bay"] * provided("medical_bay", "care") < pop:
                target -= 5
        if self.algae_food_share > 0.25:
            target -= 5
        if self.rationing:
            target -= C["rationing"]["morale_penalty"]
        target += min(15, self.wk["green_commons"] * provided("green_commons", "morale"))
        target += provided("comms_center", "morale") if self.wk["comms_center"] else 0
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
            "date": (START + timedelta(days=day)).isoformat(),
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
        self.log.append((START + timedelta(hours=self.hour), text))

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
    print(f"정책: {city.policy.name} · {city.days}일 · 시작 {START.isoformat()}")
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


def module_table():
    names = {"habitat": "거주", "life_support": "생명유지", "food": "식량", "power": "전력",
             "thermal": "열", "industry": "산업", "logistics": "물류", "safety": "안전",
             "research": "연구", "social": "사회"}
    print("| 모듈 | 분류 | 절전 순위 | 필요 기술 | 시작 | 비용 | 건설 (로봇·일) | 전력 (kW) | 인원 | 고장 간격 (일) | 기능 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    units = (("parts", "부품 {}"), ("regolith_t", "레골리스 {} t"), ("metal_t", "금속 {} t"))
    for m in MODULES.values():
        cost = " + ".join(fmt.format(m["cost"][k]) for k, fmt in units if m["cost"].get(k))
        tech = TECHS[m["tech"]]["name"] if m["tech"] else "–"
        print(f"| {m['name']} | {names[m['category']]} | {m['priority'] or '–'} | {tech} | {m['start'] or '–'} | "
              f"{cost} | {m['build_rd']:g} | {m['power_kw'] or '–'} | {m['crew'] or '–'} | {m['mtbf_days']:,} | "
              f"{describe(m)} |")


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
    parser.add_argument("--policy", choices=("good", "naive"), default="good")
    parser.add_argument("--years", type=float, default=3)
    parser.add_argument("--monte-carlo", type=int, metavar="N", help="두 정책을 N회씩 돌려 비교")
    parser.add_argument("--module-table", action="store_true", help="문서용 모듈 표 출력")
    parser.add_argument("--tech-table", action="store_true", help="문서용 기술 표 출력")
    parser.add_argument("--csv", metavar="PATH", help="일별 기록을 CSV로 저장")
    args = parser.parse_args()

    if args.module_table:
        module_table()
        return
    if args.tech_table:
        tech_table()
        return
    if args.monte_carlo:
        monte_carlo(args.monte_carlo, args.years)
        return
    city = City(seed=args.seed, policy=args.policy, years=args.years).run()
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
