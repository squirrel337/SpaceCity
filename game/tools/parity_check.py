#!/usr/bin/env python3
"""파이썬 밸런스 시뮬레이터와 Godot(GDScript) 이식본이 같은 결과를 내는지 하루 단위로 비교한다.

    python3 game/tools/parity_check.py --godot godot                 # 시드 2061·1000, 세 정책, 3년 + 다른 부지 5곳
    python3 game/tools/parity_check.py --godot godot --seeds 7 --years 1
    python3 game/tools/parity_check.py --godot godot --sites mars_hellas --site-policies good naive

달 시드 시티는 모든 시드·정책으로, 다른 부지(city_sites.json)는 첫 시드와 --site-policies로 비교한다.

두 시뮬레이터의 일별 원시 상태(반올림 전)를 모두 비교한다. 상대 오차 1e-9를 넘는 값이 하나라도 있으면 실패다.
"""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "docs" / "design" / "sim"))
import city_balance as cb  # noqa: E402

TOLERANCE = 1e-9


def snapshot(c, day):
    s = c.stock
    return {
        "day": day, "hour": c.hour, "pop": c.pop, "o2_kg": s["o2_kg"], "co2_air": c.co2_air,
        "food_kg": s["food_kg"], "water_kg": s["water_kg"], "h2_kg": s["h2_kg"], "tank_co2_kg": s["co2_kg"],
        "ch4_kg": s["ch4_kg"], "wastewater_kg": s["wastewater_kg"], "regolith_t": s["regolith_t"],
        "metal_t": s["metal_t"], "parts": s["parts"], "battery": c.battery, "rfc": c.rfc, "morale": c.morale,
        "trust": c.trust, "trust_memory": c.trust_memory, "support": c.support, "rp_bank": c.rp_bank,
        "robots": c.robots, "robots_broken": c.robots_broken, "techs": len(c.techs),
        "built": c.stats["built"], "queue_len": len(c.queue), "covered_habs": c.covered_habs,
        "modules": sum(c.counts.values()), "broken": sum(c.broken.values()), "max_co2": c.max_co2,
        "brownout_h": c.stats["brownout_h"], "crop_losses": c.stats["crop_losses"],
        "exposed": c.stats["exposed_person_events"], "departed_dose": c.stats["departed_dose"],
        "deaths": sum(c.deaths.values()), "next_cargo": c.next_cargo, "next_crewed": c.next_crewed,
        "dose_sum": sum(x[0] * x[1] for x in c.cohorts), "rationing": int(c.rationing), "seq": c.seq,
        "type_mix": sum((i + 1) * c.counts[m] for i, m in enumerate(cb.MODULES)),
        "solar_kw": c.solar_kw, "heat_cap": c.heat_cap, "dark_h": sum(c.dark[day * 24:(day + 1) * 24]),
    }


def python_rows(seed, policy, years, site=cb.HOME_SITE):
    city = cb.City(seed=seed, policy=policy, years=years, site=site)
    rows = []
    for day in range(city.days):
        pop = city.pop
        for _ in range(24):
            city.step_hour(pop)
        city.step_day(day)
        rows.append(snapshot(city, day))
    return rows


def godot_rows(godot, seed, policy, years, site=cb.HOME_SITE):
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "dump.jsonl"
        cmd = [godot, "--headless", "--path", str(ROOT / "game"), "--script", "res://tests/parity_dump.gd", "--",
               "--seed", str(seed), "--policy", policy, "--years", str(years), "--site", site, "--out", str(out)]
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if done.returncode != 0 or not out.exists():
            print(done.stdout[-3000:], done.stderr[-3000:], sep="\n")
            raise SystemExit(f"Godot 실행 실패 (종료 코드 {done.returncode})")
        errors = [line for line in done.stderr.splitlines() if "ERROR" in line or "SCRIPT ERROR" in line]
        if errors:
            print("\n".join(errors[:20]))
            raise SystemExit("Godot 스크립트 오류")
        return [json.loads(line) for line in out.read_text(encoding="utf-8").splitlines() if line]


def compare(py, gd):
    worst = (0.0, None)
    if len(py) != len(gd):
        return f"일수가 다르다: 파이썬 {len(py)}, Godot {len(gd)}", worst
    for a, b in zip(py, gd):
        for key, va in a.items():
            vb = b.get(key)
            if vb is None:
                return f"{a['day']}일째: Godot 기록에 '{key}'가 없다", worst
            diff = abs(float(va) - float(vb))
            rel = diff / max(1.0, abs(float(va)))
            if rel > worst[0]:
                worst = (rel, (a["day"], key, va, vb))
            if rel > TOLERANCE:
                return f"{a['day']}일째 '{key}'가 다르다: 파이썬 {va!r}, Godot {vb!r}", worst
    return None, worst


def main():
    parser = argparse.ArgumentParser(description="파이썬 시뮬레이터와 GDScript 이식본 비교")
    parser.add_argument("--godot", default="godot", help="Godot 실행 파일")
    parser.add_argument("--seeds", type=int, nargs="+", default=[2061, 1000])
    parser.add_argument("--policies", nargs="+", default=["good", "naive", "variety"])
    parser.add_argument("--years", type=float, default=3)
    parser.add_argument("--sites", nargs="*", default=[s for s in cb.SITES if s != cb.HOME_SITE],
                        help="다른 부지 (기본: 달 시드 시티 말고 전부, 빈 값이면 건너뛴다)")
    parser.add_argument("--site-policies", nargs="+", default=["good"])
    args = parser.parse_args()
    runs = [(cb.HOME_SITE, seed, policy) for seed in args.seeds for policy in args.policies]
    runs += [(site, args.seeds[0], policy) for site in args.sites for policy in args.site_policies]
    failed = False
    for site, seed, policy in runs:
        py = python_rows(seed, policy, args.years, site)
        gd = godot_rows(args.godot, seed, policy, args.years, site)
        problem, (worst, where) = compare(py, gd)
        status = "실패" if problem else "일치"
        print(f"{site:<18} · 시드 {seed:>5} · {policy:<7} · {len(py)}일: {status} (최대 상대 오차 {worst:.1e})")
        if problem:
            print("  " + problem)
            failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
