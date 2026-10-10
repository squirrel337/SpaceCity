#!/usr/bin/env python3
"""첫 3년 밸런스 차트 — 추천 정책 vs 준비 없는 정책 (SVG, 작은 다중 차트 4개).

    python3 plot_balance.py                          # ../images/balance_2061.svg
    python3 plot_balance.py --seed 1234 --out a.svg

표준 라이브러리만 쓴다. 같은 수치를 표로 보려면 city_balance.py --csv 를 쓴다.
"""

import argparse
from pathlib import Path

from city_balance import City

SURFACE, INK, INK2, MUTED, GRID, AXIS, BAND = "#1a1a19", "#f0efec", "#c3c2b7", "#898781", "#2c2c2a", "#383835", "#222220"
SERIES = {"good": ("추천 정책", "#3987e5"), "naive": ("준비 없는 정책", "#d95926")}
FONT = "Pretendard Variable, Pretendard, 'Noto Sans KR', system-ui, sans-serif"
PANELS = [
    # (제목, 일별 기록의 키, y축 최대, 눈금 간격, 단위, 기준선)
    ("신뢰 — 인간이 시드를 믿는 정도", "trust", 100, 25, "", [(30, "위임 강등선 30")]),
    ("평균 누적 선량", "avg_dose_msv", 700, 200, " mSv", [(600, "경력 한도 600 mSv")]),
    ("인구", "population", 400, 100, "명", []),
    ("생명유지 감전 누적 시간 — 1순위까지 전력이 모자란 시간", "brownout_total_h", 2000, 500, "시간", []),
]
W, H = 1600, 900
PW, PH = 740, 352               # 패널 크기
ML, MR, MT, MB = 64, 150, 46, 36  # 패널 안쪽 여백 (오른쪽은 끝 라벨 자리)


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def panel(out, x0, y0, title, key, ymax, step, unit, refs, runs, days):
    left, right, top, bottom = x0 + ML, x0 + PW - MR, y0 + MT, y0 + PH - MB
    sx = lambda d: left + (right - left) * d / (days - 1)
    sy = lambda v: bottom - (bottom - top) * min(v, ymax) / ymax
    out.append(f'<text x="{x0}" y="{y0 + 20}" fill="{INK}" font-size="17" font-weight="650">{esc(title)}</text>')
    for year in range(3):  # 남극 겨울(해마다 150~240일째)
        a, b = sx(min(days - 1, 365.25 * year + 150)), sx(min(days - 1, 365.25 * year + 240))
        out.append(f'<rect x="{a:.1f}" y="{top}" width="{b - a:.1f}" height="{bottom - top}" fill="{BAND}"/>')
    for v in range(0, ymax + 1, step):
        y = sy(v)
        out.append(f'<line x1="{left}" y1="{y:.1f}" x2="{right}" y2="{y:.1f}" stroke="{GRID if v else AXIS}" stroke-width="1"/>')
        out.append(f'<text x="{left - 10}" y="{y + 4:.1f}" fill="{MUTED}" font-size="12" text-anchor="end">{v:,}</text>')
    for year in range(4):
        d = min(days - 1, round(365.25 * year))
        out.append(f'<text x="{sx(d):.1f}" y="{bottom + 22}" fill="{MUTED}" font-size="12" text-anchor="middle">{2061 + year}</text>')
    for value, label in refs:
        y = sy(value)
        out.append(f'<line x1="{left}" y1="{y:.1f}" x2="{right}" y2="{y:.1f}" stroke="{INK2}" stroke-width="1" opacity="0.7"/>')
        out.append(f'<text x="{left + 6}" y="{y - 6:.1f}" fill="{INK2}" font-size="12">{esc(label)}</text>')
    ends = []
    for policy, daily in runs.items():
        name, color = SERIES[policy]
        points = " ".join(f"{sx(i):.1f},{sy(d[key]):.1f}" for i, d in enumerate(daily))
        out.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="2" '
                   f'stroke-linejoin="round" stroke-linecap="round"/>')
        last = daily[-1][key]
        ends.append((sy(last), last, name, color))
    # 끝 라벨: 값과 정책 이름을 잉크색으로, 정체성은 옆의 점이 맡는다
    ends.sort()
    if len(ends) == 2 and ends[1][0] - ends[0][0] < 34:
        ends[1] = (ends[0][0] + 34,) + ends[1][1:]
    for i, (y, value, name, color) in enumerate(ends):
        real_y = sy(value)
        out.append(f'<circle cx="{right:.1f}" cy="{real_y:.1f}" r="4" fill="{color}" stroke="{SURFACE}" stroke-width="2"/>')
        if abs(y - real_y) > 1:
            out.append(f'<line x1="{right + 6}" y1="{real_y:.1f}" x2="{right + 12}" y2="{y:.1f}" stroke="{MUTED}" stroke-width="1"/>')
        out.append(f'<text x="{right + 14}" y="{y - 2:.1f}" fill="{INK}" font-size="15" font-weight="650">{value:,.0f}{esc(unit)}</text>')
        out.append(f'<text x="{right + 14}" y="{y + 14:.1f}" fill="{INK2}" font-size="11.5">{esc(name)}</text>')


def build(seed):
    runs = {policy: City(seed=seed, policy=policy, years=3).run().daily for policy in SERIES}
    days = len(runs["good"])
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" '
           f'font-family="{FONT}">',
           f'<rect width="{W}" height="{H}" fill="{SURFACE}"/>',
           f'<text x="40" y="52" fill="{INK}" font-size="26" font-weight="700">첫 3년 — 같은 기지, 같은 운, 다른 준비</text>',
           f'<text x="40" y="82" fill="{INK2}" font-size="14">달 남극 섀클턴 시드 시티 · 시드 {seed} · 1시간 단위 시뮬레이션. '
           f'회색 띠는 남극 겨울 (그림자가 최대 90시간).</text>']
    lx = 1080
    for policy, (name, color) in SERIES.items():  # 범례
        out.append(f'<line x1="{lx}" y1="66" x2="{lx + 26}" y2="66" stroke="{color}" stroke-width="3" stroke-linecap="round"/>')
        out.append(f'<text x="{lx + 34}" y="71" fill="{INK}" font-size="14">{esc(name)}</text>')
        lx += 190
    for i, (title, key, ymax, step, unit, refs) in enumerate(PANELS):
        x0 = 40 + (i % 2) * (PW + 40)
        y0 = 118 + (i // 2) * (PH + 30)
        panel(out, x0, y0, title, key, ymax, step, unit, refs, runs, days)
    out.append("</svg>")
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="첫 3년 밸런스 차트 (SVG)")
    parser.add_argument("--seed", type=int, default=2061)
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "images" / "balance_2061.svg"))
    args = parser.parse_args()
    Path(args.out).write_text(build(args.seed), encoding="utf-8")
    print(args.out)


if __name__ == "__main__":
    main()
