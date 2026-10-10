#!/usr/bin/env python3
"""SpaceCity 항성계 생성기 — 컨셉 검증용 레퍼런스 구현.

    python3 system_generator.py --seed 2061            # 절차적 항성계 (표)
    python3 system_generator.py --seed 2061 --json     # 같은 결과를 JSON으로
    python3 system_generator.py --preset game          # 게임 보정 분광형 비율 사용
    python3 system_generator.py --real                 # nearby_stars.json 파생값 보고서

표준 라이브러리만 쓴다. 같은 시드·프리셋은 언제나 같은 항성계를 만든다.
"""

import argparse
import json
import math
import random
import unicodedata
from pathlib import Path

import formulas as f

DATA_PATH = Path(__file__).with_name("nearby_stars.json")

# 분광형: 질량 범위(M☉), 실제 주계열 비율(%), 게임 보정 비율(%)
SPECTRAL_CLASSES = {
    "O": ((16.0, 60.0), 0.00003, 0.5),
    "B": ((2.1, 16.0), 0.13, 1.5),
    "A": ((1.4, 2.1), 0.6, 4.0),
    "F": ((1.04, 1.4), 3.0, 9.0),
    "G": ((0.8, 1.04), 7.6, 18.0),
    "K": ((0.45, 0.8), 12.1, 25.0),
    "M": ((0.08, 0.45), 76.45, 42.0),
}

# 행성 유형: 한국어 이름, 반사율, 기본 자원 풍부도(0~5)
PLANET_TYPES = {
    "lava": ("용암 행성", 0.10, {"metals": 4, "silicates": 3, "rare": 3, "fissiles": 2}),
    "barren": ("불모 암석 행성", 0.12, {"silicates": 4, "metals": 3, "rare": 1, "volatiles": 1}),
    "terrestrial": ("지구형 행성", 0.30,
                    {"silicates": 3, "metals": 3, "volatiles": 2, "organics": 1, "fissiles": 2}),
    "super_earth": ("슈퍼지구", 0.30, {"silicates": 3, "metals": 4, "volatiles": 2, "fissiles": 2}),
    "ocean": ("바다 행성", 0.25, {"volatiles": 5, "organics": 2, "fusion": 3}),
    "sub_neptune": ("미니 해왕성", 0.35, {"volatiles": 4, "fusion": 2}),
    "gas_giant": ("가스 거대행성", 0.34, {"fusion": 5, "volatiles": 2}),
    "hot_jupiter": ("뜨거운 목성", 0.10, {"fusion": 3}),
    "ice_giant": ("얼음 거대행성", 0.30, {"volatiles": 3, "fusion": 4}),
    "ice_dwarf": ("얼음 왜행성", 0.50, {"volatiles": 4, "organics": 2}),
    "asteroid_belt": ("소행성대", 0.10, {"metals": 4, "rare": 4, "silicates": 3, "volatiles": 1}),
}

RESOURCE_NAMES = {
    "volatiles": "휘발성", "silicates": "규산염", "metals": "금속", "rare": "희귀원소",
    "fissiles": "핵분열연료", "fusion": "핵융합연료", "organics": "유기물",
}

ATMOSPHERE_NAMES = {
    "none": "없음", "thin": "희박", "earthlike": "지구형", "thick": "고밀도", "envelope": "수소 외피",
}

# 대기 종류별 온실효과 가산(K). 고밀도 대기는 행성마다 편차가 커서 범위로 굴린다.
GREENHOUSE_K = {"none": 0.0, "thin": 8.0, "earthlike": 33.0, "envelope": 0.0}

GIANTS = ("gas_giant", "hot_jupiter", "ice_giant")
ROCKY = ("lava", "barren", "terrestrial", "super_earth", "ocean")
MOON_FEATURES = ("지하 해양 얼음 위성", "화산 위성 (조석 가열)", "두꺼운 대기 위성", "포획 소행성 위성")
NAME_SYLLABLES = ("ka", "ri", "vos", "the", "lun", "mar", "e", "zo", "an", "dra",
                  "kel", "si", "or", "na", "ve", "tal", "u", "rim", "sa", "quo")


def log_uniform(rng, lo, hi):
    return math.exp(rng.uniform(math.log(lo), math.log(hi)))


def make_name(rng):
    return "".join(rng.choice(NAME_SYLLABLES) for _ in range(rng.randint(2, 3))).capitalize()


# ── 항성 ────────────────────────────────────────────────────────────
def generate_star(rng, preset):
    classes = list(SPECTRAL_CLASSES)
    weights = [SPECTRAL_CLASSES[c][1 if preset == "realistic" else 2] for c in classes]
    spectral_class = rng.choices(classes, weights=weights)[0]
    (lo, hi), _, _ = SPECTRAL_CLASSES[spectral_class]
    mass = log_uniform(rng, lo, hi)
    # 같은 분광형 안에서 무거울수록 뜨겁다 → 아형 숫자가 작다 (G0이 G9보다 뜨거움)
    position = (math.log(mass) - math.log(lo)) / (math.log(hi) - math.log(lo))
    subclass = min(9, int((1.0 - position) * 10))
    lifetime = f.main_sequence_lifetime_gyr(mass)
    return {
        "name": make_name(rng),
        "spectral": f"{spectral_class}{subclass}V",
        "spectral_class": spectral_class,
        "mass_sun": round(mass, 3),
        "luminosity_sun": round(f.star_luminosity(mass), 5),
        "radius_sun": round(f.star_radius(mass), 3),
        "teff_k": round(f.star_temperature(mass)),
        "age_gyr": round(rng.uniform(0.02, 0.9) * min(lifetime, 13.0), 2),
        "lifetime_gyr": round(lifetime, 1),
    }


# ── 행성 ────────────────────────────────────────────────────────────
def pick_type(rng, a_au, frost_au, teq_k, spectral_class, giants_so_far, innermost):
    roll = rng.random()
    if a_au < frost_au:
        if teq_k > 1000.0:  # 암석이 녹을 만큼 뜨거움
            return "hot_jupiter" if roll < 0.05 else "lava"
        if not innermost and a_au > 0.6 * frost_au and roll < 0.15:
            return "asteroid_belt"
        size_roll = rng.random()
        if size_roll < 0.25:
            return "barren"
        if size_roll < 0.55:
            return "terrestrial"
        if size_roll < 0.80:
            return "super_earth"
        return "sub_neptune"
    if spectral_class == "M":  # 적색왜성은 원반이 가벼워 거대행성이 드물고 얼음 덮인 암석행성이 많다
        if roll < 0.08 * 0.5 ** giants_so_far:
            return "gas_giant"
        if roll < 0.30:
            return "ice_giant"
        return "barren" if roll < 0.75 else "ice_dwarf"
    giant_chance = 0.6
    if giants_so_far == 0:
        giant_chance += 0.15  # 설선 바로 바깥은 거대행성이 잘 생긴다
    if roll < giant_chance * 0.8 ** giants_so_far:
        return "gas_giant"
    if roll < 0.75:
        return "ice_giant"
    return "ice_dwarf"


def roll_mass_radius(rng, kind, spectral_class):
    """유형별 질량(M⊕)과 반지름(R⊕)."""
    if kind == "lava":
        mass = log_uniform(rng, 0.3, 8.0)
        return mass, mass ** 0.27
    if kind == "barren":
        mass = log_uniform(rng, 0.02, 0.5)
        return mass, mass ** 0.3
    if kind == "terrestrial":
        mass = log_uniform(rng, 0.5, 2.0)
        return mass, mass ** 0.27
    if kind == "super_earth":
        mass = log_uniform(rng, 2.0, 8.0)
        return mass, mass ** 0.27
    if kind == "ocean":
        mass = log_uniform(rng, 0.5, 6.0)
        return mass, 1.1 * mass ** 0.27  # 물이 많아 밀도가 낮다
    if kind == "sub_neptune":
        return log_uniform(rng, 4.0, 15.0), rng.uniform(1.8, 3.5)
    if kind == "gas_giant":
        top = 600.0 if spectral_class == "M" else 3000.0  # 적색왜성 원반은 재료가 적다
        return log_uniform(rng, 50.0, top), rng.uniform(8.5, 12.5)
    if kind == "hot_jupiter":
        return log_uniform(rng, 100.0, 3000.0), rng.uniform(11.0, 16.0)  # 가열로 부풀어 있음
    if kind == "ice_giant":
        return log_uniform(rng, 10.0, 30.0), rng.uniform(3.5, 4.5)
    if kind == "ice_dwarf":
        mass = log_uniform(rng, 0.001, 0.05)
        return mass, 1.3 * mass ** 0.3
    return 0.0005, 0.0  # 소행성대: 총질량만 의미가 있다


def roll_atmosphere(rng, kind, mass):
    if kind in GIANTS or kind == "sub_neptune":
        return "envelope"
    if kind in ("lava", "asteroid_belt") or mass < 0.1:
        return "none"
    if kind in ("barren", "ice_dwarf"):
        return "thin" if rng.random() < 0.25 else "none"
    return rng.choices(["none", "thin", "earthlike", "thick"], weights=[10, 25, 40, 25])[0]


def habitability(planet, spectral_class):
    """게임용 거주성 0~100. 지구 = 100. 돔·궤도 거주구 없이 '맨몸으로' 살 수 있는 정도."""
    if planet["type"] not in ROCKY or planet["type"] == "lava":
        return 0
    temp = math.exp(-((planet["surface_temp_k"] - 288.0) / 40.0) ** 2)
    gravity = math.exp(-((planet["gravity_g"] - 1.0) / 0.6) ** 2)
    atmosphere = {"none": 0.05, "thin": 0.35, "earthlike": 1.0, "thick": 0.1}[planet["atmosphere"]]
    water = 0.3 + 0.7 * min(1.0, planet["hydrosphere"] / 0.7)
    flare = 0.7 if spectral_class == "M" else 1.0
    lock = 0.8 if planet["tidally_locked"] else 1.0
    return round(100.0 * temp * gravity ** 0.5 * atmosphere * water * flare * lock)


def roll_biosphere(rng, hab, age_gyr):
    if hab < 25 or age_gyr < 1.0:
        return "없음"
    roll = rng.random()
    if age_gyr > 3.0 and roll < 0.05:
        return "복합 생명"
    return "미생물" if roll < 0.35 else "없음"


def roll_resources(rng, kind, beyond_frost):
    resources = {}
    for key, base in PLANET_TYPES[kind][2].items():
        resources[key] = max(0, min(5, base + rng.randint(-1, 1)))
    if beyond_frost and kind in ("barren", "terrestrial", "super_earth", "asteroid_belt"):
        resources["volatiles"] = min(5, resources.get("volatiles", 0) + 2)  # 얼음
    return resources


def generate_planets(rng, star):
    mass_sun, lum = star["mass_sun"], star["luminosity_sun"]
    hz_inner, hz_outer = f.habitable_zone_au(lum, star["teff_k"])
    frost = f.frost_line_au(lum)
    # 적색왜성은 트라피스트-1처럼 촘촘한 계, 그 외는 태양계처럼 넓은 계 (간격 비율 평균 약 1.7)
    first_orbit, spacing = ((0.01, 0.06), (1.3, 1.7)) if star["spectral_class"] == "M" \
        else ((0.02, 0.3), (1.4, 2.0))
    min_orbit = max(0.01, 3.0 * star["radius_sun"] * 0.00465)  # 항성 반지름의 3배 바깥
    a_au = max(min_orbit, rng.uniform(*first_orbit) * mass_sun ** (1.0 / 3.0))
    count = max(1, min(10, round(rng.gauss(5, 2))))

    planets, giants = [], 0
    for index in range(count):
        if index > 0:
            a_au *= rng.uniform(*spacing)
        kind = pick_type(rng, a_au, frost, f.equilibrium_temperature_k(lum, a_au),
                         star["spectral_class"], giants, innermost=index == 0)
        in_hz = hz_inner <= a_au <= hz_outer
        if kind in ("terrestrial", "super_earth") and in_hz and rng.random() < 0.25:
            kind = "ocean"
        giants += kind in GIANTS
        mass, radius = roll_mass_radius(rng, kind, star["spectral_class"])
        atmosphere = roll_atmosphere(rng, kind, mass)
        albedo = PLANET_TYPES[kind][1]
        teq = f.equilibrium_temperature_k(lum, a_au, albedo)
        greenhouse = rng.uniform(80.0, 450.0) if atmosphere == "thick" else GREENHOUSE_K[atmosphere]
        surface_temp = teq + greenhouse
        hydrosphere = 0.0
        if kind == "ocean":
            hydrosphere = rng.uniform(0.92, 1.0)
        elif kind in ("terrestrial", "super_earth") and 250.0 <= surface_temp <= 380.0:
            hydrosphere = rng.uniform(0.0, 0.9)

        planet = {
            "name": f"{star['name']} {'bcdefghijk'[index]}",
            "type": kind,
            "type_ko": PLANET_TYPES[kind][0],
            "a_au": round(a_au, 4),
            "period_d": round(f.orbital_period_days(a_au, mass_sun), 2),
            "mass_earth": round(mass, 3),
            "radius_earth": round(radius, 2),
            "gravity_g": round(f.surface_gravity_g(mass, radius), 2) if radius else None,
            "atmosphere": atmosphere,
            "equilibrium_temp_k": round(teq),
            "surface_temp_k": round(surface_temp),
            "hydrosphere": round(hydrosphere, 2),
            "in_habitable_zone": in_hz,
            "tidally_locked": kind != "asteroid_belt" and f.is_tidally_locked(a_au, mass_sun),
            "resources": roll_resources(rng, kind, a_au >= frost),
        }
        if kind in ROCKY:
            density = mass / radius ** 3
            v_escape = math.sqrt(mass / radius)
            planet["esi"] = round(f.earth_similarity_index(radius, density, v_escape, surface_temp), 2)
        planet["habitability"] = habitability(planet, star["spectral_class"])
        planet["biosphere"] = roll_biosphere(rng, planet["habitability"], star["age_gyr"])
        if kind in ("gas_giant", "ice_giant"):
            moon_count = rng.randint(2, 9) if kind == "gas_giant" else rng.randint(1, 5)
            planet["moons"] = moon_count
            planet["notable_moons"] = sorted(set(rng.choices(MOON_FEATURES, k=min(2, moon_count))))
        planets.append(planet)
    return planets


def generate_system(seed, preset="realistic"):
    rng = random.Random(seed)
    star = generate_star(rng, preset)
    hz_inner, hz_outer = f.habitable_zone_au(star["luminosity_sun"], star["teff_k"])
    return {
        "seed": seed,
        "preset": preset,
        "star": star,
        "habitable_zone_au": [round(hz_inner, 3), round(hz_outer, 3)],
        "frost_line_au": round(f.frost_line_au(star["luminosity_sun"]), 3),
        "planets": generate_planets(rng, star),
    }


# ── 출력 ────────────────────────────────────────────────────────────
def display_width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def pad(text, width):
    text = str(text)
    return text + " " * max(0, width - display_width(text))


def print_table(rows, widths):
    for row in rows:
        print("  " + " ".join(pad(cell, width) for cell, width in zip(row, widths)))


def print_system(system):
    star = system["star"]
    hz_inner, hz_outer = system["habitable_zone_au"]
    print(f"★ {star['name']} — {star['spectral']}  질량 {star['mass_sun']} M☉  광도 {star['luminosity_sun']} L☉  "
          f"{star['teff_k']:,} K  나이 {star['age_gyr']} / 수명 {star['lifetime_gyr']:,} Gyr")
    print(f"  거주가능영역 {hz_inner}–{hz_outer} AU · 설선 {system['frost_line_au']} AU · "
          f"시드 {system['seed']} ({system['preset']})")
    rows = [("이름", "유형", "a(AU)", "주기(일)", "질량(M⊕)", "중력(g)", "대기", "표면(K)",
             "ESI", "거주성", "생명", "특징")]
    for p in system["planets"]:
        tags = []
        if p["in_habitable_zone"]:
            tags.append("HZ")
        if p["tidally_locked"]:
            tags.append("조석고정")
        if p.get("moons"):
            tags.append(f"위성 {p['moons']}: " + ", ".join(p["notable_moons"]))
        best = sorted(p["resources"].items(), key=lambda item: -item[1])[:2]
        tags.append("자원 " + ", ".join(f"{RESOURCE_NAMES[k]}{v}" for k, v in best))
        rows.append((p["name"], p["type_ko"], p["a_au"], f"{p['period_d']:,}", p["mass_earth"],
                     p["gravity_g"] if p["gravity_g"] is not None else "-",
                     ATMOSPHERE_NAMES[p["atmosphere"]], p["surface_temp_k"], p.get("esi", "-"),
                     p["habitability"], p["biosphere"], " · ".join(tags)))
    print_table(rows, (14, 14, 7, 9, 9, 7, 9, 7, 5, 6, 9, 0))


def real_systems_report():
    """실제 항성 데이터에 같은 공식을 적용해 거주가능영역과 평형 온도를 계산한다."""
    data = json.loads(DATA_PATH.read_text(encoding="utf-8"))
    for system in data["systems"]:
        primary = system["stars"][0]
        head = f"■ {system['name']['ko']} ({system['distance_ly']:,} ly, {primary['spectral']})"
        if system["category"] == "landmark" or primary["mass_sun"] is None:
            print(head + " — 랜드마크: 거주가능영역 계산 생략")
            continue
        lum, teff = primary["luminosity_sun"], primary["teff_k"]
        estimated = lum is None
        if estimated:
            lum = f.star_luminosity(primary["mass_sun"])
        if teff is None:
            teff = f.star_temperature(primary["mass_sun"])
        hz_inner, hz_outer = f.habitable_zone_au(lum, teff)
        wide_inner, wide_outer = f.habitable_zone_au(lum, teff, optimistic=True)
        print(head + f"  L={lum:.4g}{' (질량으로 추정)' if estimated else ''}  "
              f"HZ {hz_inner:.3f}–{hz_outer:.3f} AU (낙관 {wide_inner:.3f}–{wide_outer:.3f})")
        for planet in system["planets"]:
            a_au = planet["a_au"]
            if a_au is None and planet["period_d"] is not None:
                a_au = f.semi_major_axis_au(planet["period_d"], primary["mass_sun"])
            if a_au is None:
                print(f"    {planet['name']}: 궤도 정보 없음 [{planet['status']}]")
                continue
            teq = f.equilibrium_temperature_k(lum, a_au)
            if hz_inner <= a_au <= hz_outer:
                zone = "HZ 안"
            elif wide_inner <= a_au <= wide_outer:
                zone = "HZ 안 (낙관 기준)"
            else:
                zone = "안쪽" if a_au < hz_inner else "바깥쪽"
            print(f"    {planet['name']}: a={a_au:.4f} AU  평형온도 {teq:.0f} K  {zone}  [{planet['status']}]")


def main():
    parser = argparse.ArgumentParser(description="SpaceCity 항성계 생성기 (레퍼런스 구현)")
    parser.add_argument("--seed", type=int, default=2061, help="난수 시드 (기본 2061)")
    parser.add_argument("--preset", choices=("realistic", "game"), default="realistic",
                        help="분광형 비율: 실제 통계 또는 게임 보정")
    parser.add_argument("--json", action="store_true", help="JSON으로 출력")
    parser.add_argument("--real", action="store_true", help="nearby_stars.json 파생값 보고서")
    args = parser.parse_args()

    if args.real:
        real_systems_report()
        return
    system = generate_system(args.seed, args.preset)
    if args.json:
        print(json.dumps(system, ensure_ascii=False, indent=2))
    else:
        print_system(system)


if __name__ == "__main__":
    main()
