"""새 건물 종류 (29계열 × 4 = 116종)의 그림 — 공용 등록기와 부품.

종류마다 함수 하나 fn(sp, v)로 그린다. v = 0~4는 같은 기능의 다섯 가지 모양이다 (지도는 자리마다 하나를 고른다).
v0이 그 종류의 대표 모양이고, v1~v4는 세부(색 띠, 덧붙인 장치, 창 수, 방향, 크기 조금)를 바꾼다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어가야 한다.

    @typed("transhab", 12, 7, 6.0, "대형 팽창 거주동")
    def transhab(sp: Sprite, v: int):
        ...

종류별 그림은 types_<묶음>.py에 둔다. make_art.py가 모두 불러온다 (load_types).
"""
from __future__ import annotations

from iso import *  # noqa: F401,F403
from buildings import (BUILDINGS, antenna, band_on, building, crate, door, legs, pipe, skid,  # noqa: F401
                       windows_row)
from building_variants import (ALGAE, ALGAE_DARK, CONCRETE, FOAM, FROST, PINK_GLASS, cyl_ring,  # noqa: F401
                               cyl_windows, print_lines, rounded_rect, sandbag_rings)

TYPES: dict[str, str] = {}      # 종류 id → 그린 모듈 이름 (미리보기·확인용)


def typed(bid: str, w: float, d: float, h: float, title: str, heights: list[float] | None = None):
    """fn(sp, v)를 v0(기본)과 v1~v4(변형)로 등록한다. heights[v]가 있으면 그 모양의 대표 높이 (그림자·누를 자리)."""
    def deco(fn):
        building(bid, w, d, h, title)(lambda sp, fn=fn: fn(sp, 0))
        spec = BUILDINGS[bid]
        vs = spec.setdefault("variants", {})
        for v in range(1, 5):
            vs[v] = {"fn": (lambda sp, v=v, fn=fn: fn(sp, v)),
                     "height": heights[v] if heights else None}
        if heights:
            spec["height"] = heights[0]
        TYPES[bid] = fn.__module__
        return fn
    return deco
