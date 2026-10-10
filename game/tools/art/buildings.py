"""시대 0 건물 29종 + 피복된 거주 모듈 + 공사 비계.

각 함수는 원점(바닥 중심)에 건물 하나를 그린다. 뒤(화면 위)에서 앞(화면 아래) 순서로 부른다.
치수는 미터 — 실제 달 기지 개념 설계를 참고했지만 화면에서 알아보도록 조금 키우거나 줄였다.
"""
from __future__ import annotations

import math

from iso import *  # noqa: F401,F403

BUILDINGS: dict[str, dict] = {}


def building(bid: str, w: float, d: float, h: float, title: str):
    """w×d: 바닥 크기, h: 그림자를 계산할 대표 높이."""
    def deco(fn):
        BUILDINGS[bid] = {"fn": fn, "foot": [w, d], "height": h, "title": title}
        return fn
    return deco


# ── 공용 부품 ────────────────────────────────────────────────────────

def skid(sp: Sprite, x, y, w, d, h=0.35, mat: Mat = STEEL):
    sp.box(x, y, 0, w, d, h, mat)


def door(sp: Sprite, frame, u0, u1, v1, mat: Mat = DARK, light: bool = True):
    o, e1, e2 = frame
    pts = sp.on_face(o, e1, e2, u0, 0.0, u1, v1)
    n = norm(cross(e1, e2))
    sp.face(pts, mat, normal=n, ao=0.0)
    if light:
        top = add(add(o, mul(e1, (u0 + u1) / 2)), mul(e2, min(1.0, v1 + 0.12)))
        sp.lamp(add(top, mul(n, 0.15)), AMBER, 9)


def windows_row(sp: Sprite, frame, n: int, v0=0.45, v1=0.75, margin=0.12, gap=0.05, glow=WARM_WINDOW):
    o, e1, e2 = frame
    span = (1 - 2 * margin - gap * (n - 1)) / n
    for i in range(n):
        u0 = margin + i * (span + gap)
        sp.window(sp.on_face(o, e1, e2, u0, v0, u0 + span, v1), glow)


def band_on(sp: Sprite, frame, v0, v1, mat: Mat):
    o, e1, e2 = frame
    sp.face(sp.on_face(o, e1, e2, 0.0, v0, 1.0, v1), mat, normal=norm(cross(e1, e2)), edge=False, ao=0.0)


def legs(sp: Sprite, pts_top, z_foot=0.0, w=0.12, color="#7d848d"):
    for p in pts_top:
        sp.line((p[0], p[1], z_foot), p, w, color)


def pipe(sp: Sprite, pts, w=0.18, color="#c9ccd1"):
    sp.polyline3(pts, "#5c626b", w + 0.06)
    sp.polyline3(pts, color, w)


def antenna(sp: Sprite, base, h, color="#9aa1aa", tip_light=True):
    sp.line(base, add(base, (0, 0, h)), 0.07, color)
    if tip_light:
        sp.lamp(add(base, (0, 0, h + 0.1)), "#ff5a3c", 6)


def crate(sp: Sprite, x, y, s=1.2, mat: Mat = ORANGE, z=0.0):
    sp.box(x, y, z, s, s, s * 0.8, mat)


# ── 거주 ─────────────────────────────────────────────────────────────

def _hab_core(sp: Sprite, covered: bool):
    p0, p1, r = (-4.4, 0.0, 2.45), (4.4, 0.0, 2.45), 2.2
    if not covered:
        sp.contact_shadow(0, 0, 5.4, 3.0)
        for x in (-3.4, 0.0, 3.4):
            sp.box(x - 0.3, -1.9, 0, 0.6, 3.8, 0.55, STEEL)
            legs(sp, [(x, -1.4, 0.55), (x, 1.4, 0.55)], 0.0)
        sp.cyl(p0, p1, r, FABRIC, bands=[0.1, 0.22, 0.34, 0.46, 0.58, 0.7, 0.82, 0.9],
               band_color="#b9ab92", cap_mat=WHITE)
        ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.35)))
        for s in (0.16, 0.4, 0.64):
            sp.window(Sprite.cyl_patch(p0, p1, r, s, s + 0.09, ang - 13, ang + 13))
        # 끝판: 단단한 고리와 해치
        sp.disc((4.45, 0, 2.45), (1, 0, 0), 1.0, DARK, edge=True)
        sp.disc((4.5, 0, 2.45), (1, 0, 0), 0.75, STEEL)
        sp.ring3((4.47, 0, 2.45), 2.05, "#9c9486", 0.12, normal=(1, 0, 0), front_only=False)
        sp.lamp((4.6, 0.0, 4.2), AMBER, 10)
        # 표시: 청록 줄 (생명유지 계통)
        sp.window(Sprite.cyl_patch(p0, p1, r, 0.93, 0.97, ang - 40, ang + 40), CYAN_LIGHT, frame=None,
                  glass=TEAL, light_alpha=0.6)
    else:
        sp.contact_shadow(0.3, 0, 6.6, 4.2, 0.5)
        sp.ellipsoid((0, 0, 0.4), 6.2, 3.9, 4.3, BERM, clip_z=0.0)
        # 모래주머니 줄
        for zz in (0.9, 1.8, 2.7, 3.5):
            k = math.sqrt(max(0.0, 1 - ((zz - 0.4) / 4.3) ** 2))
            pts = []
            for i in range(49):
                t = 2 * math.pi * i / 48
                radial = (math.cos(t), math.sin(t), 0.0)
                if dot(radial, VIEW) > -0.1:
                    pts.append((6.2 * k * math.cos(t), 3.9 * k * math.sin(t), zz))
            sp.polyline3(pts, "#5f5953", 0.06, 0.8)
        sp.rock((-4.0, 3.6, 0), 0.5)
        sp.rock((3.0, -3.8, 0), 0.4)
        # 드러난 출입 터널
        sp.box(4.7, -1.1, 0, 2.2, 2.2, 2.3, WHITE)
        f = Sprite.box_faces(4.7, -1.1, 0, 2.2, 2.2, 2.3)
        door(sp, f["right"], 0.25, 0.75, 0.78)
        windows_row(sp, f["left"], 1, 0.5, 0.75, 0.3)


@building("hab_module", 10, 5, 4.7, "여압 거주 모듈")
def hab_module(sp: Sprite):
    _hab_core(sp, covered=False)


@building("hab_module_covered", 13, 8, 4.7, "여압 거주 모듈 (레골리스 피복)")
def hab_module_covered(sp: Sprite):
    _hab_core(sp, covered=True)


@building("regolith_dome", 15, 13, 5.2, "레골리스 차폐 돔")
def regolith_dome(sp: Sprite):
    sp.contact_shadow(0, 0, 7.2, 7.2, 0.5)
    sp.dome((0, 0, 0), 6.6, 5.2, SINTER)
    for zz in (0.7, 1.5, 2.3, 3.1, 3.8, 4.4, 4.85):
        k = math.sqrt(max(0.0, 1 - (zz / 5.2) ** 2))
        sp.ring3((0, 0, zz), 6.6 * k, "#83745f", 0.045, opacity=0.8)
    # 둥근 창 (위쪽에 작은 채광창 셋)
    for ang in (20, 55, 90):
        t = math.radians(ang)
        c = (5.2 * math.cos(t) * 0.82, 5.2 * math.sin(t) * 0.82, 2.6)
        n = norm((math.cos(t), math.sin(t), 0.55))
        u, v = basis(n)
        pts = [add(c, add(mul(u, 0.45 * math.cos(2 * math.pi * i / 12)), mul(v, 0.45 * math.sin(2 * math.pi * i / 12))))
               for i in range(12)]
        sp.window(pts, frame="#5f5446")
    # 출입 터널 (반원통)
    sp.half_cyl((5.4, 0, 0), (7.6, 0, 0), 1.45, SINTER, bands=[0.33, 0.66], band_color="#83745f")
    sp.disc((7.62, 0, 0.75), (1, 0, 0), 0.62, DARK, edge=False)
    sp.face([(7.65, -0.55, 0), (7.65, 0.55, 0), (7.65, 0.55, 1.15), (7.65, -0.55, 1.15)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((7.7, -0.9, 1.6), AMBER, 10)
    sp.lamp((7.7, 0.9, 1.6), AMBER, 10)


# ── 생명유지 ─────────────────────────────────────────────────────────

@building("electrolyzer", 6, 4, 3.6, "물 전기분해기")
def electrolyzer(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    # 뒤쪽 탱크 둘 (산소: 청록 띠, 수소: 주황 띠)
    sp.cyl((-1.6, -1.0, 0.35), (-1.6, -1.0, 3.6), 0.75, WHITE, bands=[0.2, 0.8])
    sp.frustum((-1.6, -1.0, 3.6), (-1.6, -1.0, 4.05), 0.75, 0.2, WHITE, caps=True)
    sp.cyl((0.4, -1.1, 0.35), (0.4, -1.1, 3.0), 0.6, WHITE, bands=[0.25, 0.75])
    sp.frustum((0.4, -1.1, 3.0), (0.4, -1.1, 3.35), 0.6, 0.15, WHITE)
    sp.window(Sprite.cyl_patch((-1.6, -1.0, 0.35), (-1.6, -1.0, 3.6), 0.75, 0.42, 0.55, 0, 120), CYAN_LIGHT,
              frame=None, glass=TEAL, light_alpha=0.0)
    sp.window(Sprite.cyl_patch((0.4, -1.1, 0.35), (0.4, -1.1, 3.0), 0.6, 0.42, 0.55, 0, 120), "#ffb37a",
              frame=None, glass=ORANGE, light_alpha=0.0)
    # 앞쪽 전해조 상자
    sp.box(-2.6, 0.2, 0.35, 4.6, 1.6, 1.9, WHITE, top=SILVER)
    f = Sprite.box_faces(-2.6, 0.2, 0.35, 4.6, 1.6, 1.9)
    band_on(sp, f["left"], 0.78, 0.9, TEAL)
    for i in range(5):
        o, e1, e2 = f["left"]
        sp.face(sp.on_face(o, e1, e2, 0.1 + i * 0.17, 0.2, 0.2 + i * 0.17, 0.65), CHAR, normal=(0, 1, 0), ao=0)
    pipe(sp, [(-1.6, -0.3, 2.6), (-1.6, 0.3, 2.6), (-1.6, 0.3, 2.25)])
    pipe(sp, [(0.4, -0.5, 2.2), (0.4, 0.3, 2.2)])
    sp.lamp((2.05, 1.0, 1.9), CYAN_LIGHT, 7)


@building("co2_scrubber", 5, 4, 3.4, "CO₂ 제거기")
def co2_scrubber(sp: Sprite):
    sp.contact_shadow(0, 0, 3.2, 2.6)
    skid(sp, -2.5, -2, 5, 4)
    sp.box(-2.2, -1.6, 0.35, 4.4, 3.2, 2.2, WHITE, top=SILVER)
    f = Sprite.box_faces(-2.2, -1.6, 0.35, 4.4, 3.2, 2.2)
    # 흡착 베드 루버
    o, e1, e2 = f["left"]
    for i in range(7):
        v = 0.18 + i * 0.09
        sp.face(sp.on_face(o, e1, e2, 0.08, v, 0.62, v + 0.045), DARK, normal=(0, 1, 0), edge=False, ao=0)
    band_on(sp, f["left"], 0.86, 0.94, TEAL)
    sp.window(sp.on_face(o, e1, e2, 0.72, 0.35, 0.9, 0.62), CYAN_LIGHT, frame="#2a2f36")
    o, e1, e2 = f["right"]
    for i in range(5):
        v = 0.2 + i * 0.12
        sp.face(sp.on_face(o, e1, e2, 0.15, v, 0.85, v + 0.06), DARK, normal=(1, 0, 0), edge=False, ao=0)
    # 지붕 팬 둘
    for cx in (-1.0, 1.0):
        sp.cyl((cx, 0, 2.55), (cx, 0, 2.95), 0.75, STEEL, cap_mat=CHAR)
        sp.ring3((cx, 0, 2.97), 0.55, "#9aa1aa", 0.05)
        sp.line((cx - 0.5, 0, 2.97), (cx + 0.5, 0, 2.97), 0.08, "#9aa1aa")
        sp.line((cx, -0.5, 2.97), (cx, 0.5, 2.97), 0.08, "#9aa1aa")


@building("sabatier", 6, 4, 3.4, "사바티에 반응기")
def sabatier(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    # 뒤쪽 방열 핀
    o, e1, e2 = (-2.6, -1.7, 0.35), (2.2, 0, 0), (0, 0, 2.8)
    sp.quad(o, e1, e2, RADIATOR)
    sp.panel_grid(o, e1, e2, 6, 1, "#b7bcc2", 0.5, 0.8)
    # 반응기 (누운 원기둥)
    sp.box(-0.3, -0.9, 0.35, 0.4, 1.8, 0.8, STEEL)
    sp.box(2.0, -0.9, 0.35, 0.4, 1.8, 0.8, STEEL)
    sp.cyl((-0.8, 0, 1.75), (2.9, 0, 1.75), 0.85, SILVER, bands=[0.12, 0.88], cap_mat=STEEL)
    # 메탄 구형 탱크
    sp.sphere((-1.7, 1.0, 1.25), 0.95, WHITE)
    sp.ring3((-1.7, 1.0, 1.25), 0.95, "#c9a75a", 0.07)
    legs(sp, [(-2.3, 1.5, 0.6), (-1.1, 1.5, 0.6), (-1.7, 0.4, 0.6)], 0.35)
    pipe(sp, [(-1.0, 1.0, 1.3), (-0.6, 0.5, 1.6), (-0.6, 0.0, 1.75)])
    pipe(sp, [(2.9, 0, 1.75), (3.0, 0.9, 1.75), (3.0, 0.9, 0.4)])
    sp.lamp((2.95, 0, 2.7), AMBER, 7)


@building("water_recycler", 6, 4, 5.2, "물 재활용기")
def water_recycler(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    # 증류탑
    sp.cyl((-1.8, -1.0, 0.35), (-1.8, -1.0, 5.0), 0.55, SILVER, bands=[0.25, 0.5, 0.75])
    sp.sphere((-1.8, -1.0, 5.0), 0.55, SILVER)
    sp.box(-0.9, -1.6, 0.35, 3.6, 2.4, 2.3, WHITE, top=SILVER)
    f = Sprite.box_faces(-0.9, -1.6, 0.35, 3.6, 2.4, 2.3)
    band_on(sp, f["left"], 0.82, 0.92, BLUE)
    windows_row(sp, f["left"], 2, 0.4, 0.66, 0.15, 0.1, CYAN_LIGHT)
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.3, 0.0, 0.7, 0.7), STEEL, normal=(1, 0, 0), ao=0.1)
    # 물 탱크 (파란 띠)
    sp.cyl((-2.0, 1.1, 0.35), (-2.0, 1.1, 2.0), 0.75, WHITE, bands=[0.5])
    sp.window(Sprite.cyl_patch((-2.0, 1.1, 0.35), (-2.0, 1.1, 2.0), 0.75, 0.62, 0.78, -10, 120), "#7fb6ff",
              frame=None, glass=BLUE, light_alpha=0.0)
    pipe(sp, [(-1.8, -0.45, 3.8), (-0.9, -0.45, 3.8), (-0.9, -0.45, 2.65)])
    pipe(sp, [(-2.0, 1.1, 2.0), (-2.0, 0.5, 2.0), (-0.9, 0.5, 1.8)])


@building("tank_farm", 8, 6, 4.2, "저장 탱크")
def tank_farm(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 3.6)
    sp.box(-4, -3, 0, 8, 6, 0.3, SINTER)
    for (cx, cy, r, mat) in ((-2.0, -1.3, 1.45, WHITE), (1.3, -1.6, 1.35, WHITE),
                             (-2.3, 1.6, 1.2, ORANGE), (1.4, 1.4, 1.45, WHITE)):
        legs(sp, [(cx - r * 0.6, cy - r * 0.6, r * 0.9 + 0.3), (cx + r * 0.6, cy - r * 0.6, r * 0.9 + 0.3),
                  (cx - r * 0.6, cy + r * 0.6, r * 0.9 + 0.3), (cx + r * 0.6, cy + r * 0.6, r * 0.9 + 0.3)], 0.3)
        sp.sphere((cx, cy, r + 0.6), r, mat)
        sp.ring3((cx, cy, r + 0.6), r, "#a29a8c" if mat is WHITE else "#9a4f22", 0.06)
    pipe(sp, [(-2.0, -1.3, 0.5), (1.3, -1.6, 0.5)])
    pipe(sp, [(-2.3, 1.6, 0.5), (1.4, 1.4, 0.5)])
    sp.lamp((3.9, 2.9, 1.2), AMBER, 8)


# ── 식량 ─────────────────────────────────────────────────────────────

@building("hydroponics", 9, 5, 4.0, "수경 농장")
def hydroponics(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.0)
    p0, p1, r = (-4.2, 0, 1.0), (4.2, 0, 1.0), 2.1
    sp.box(-4.4, -2.0, 0, 8.8, 4.0, 1.0, SINTER)          # 반쯤 묻힌 받침
    sp.half_cyl(p0, p1, r, WHITE, bands=[0.2, 0.4, 0.6, 0.8], band_color="#b8b2a6", cap_mat=WHITE)
    # 위쪽 채광창 (식물 줄이 보인다)
    gx0, gx1 = -3.7, 3.7
    for i in range(4):
        x0 = gx0 + i * (gx1 - gx0) / 4 + 0.15
        x1 = gx0 + (i + 1) * (gx1 - gx0) / 4 - 0.15
        pts = [(x0, -0.75, 1.0 + 1.95), (x1, -0.75, 1.0 + 1.95), (x1, 0.75, 1.0 + 1.95), (x0, 0.75, 1.0 + 1.95)]
        sp.face(pts, GLASS, normal=(0, 0, 1), ao=0)
        # 식물 줄
        for k in range(3):
            yy = -0.45 + k * 0.45
            a, b = PV((x0 + 0.1, yy, 2.97)), PV((x1 - 0.1, yy, 2.97))
            sp.path2("M%.2f,%.2fL%.2f,%.2f" % (a[0], a[1], b[0], b[1]), "none", "#6DAE57", 1.4)
        sp.poly2([PV(p) for p in pts], GROW, None, 0, 0.85, layer="light")
    sp.face([(4.25, -0.6, 1.0), (4.25, 0.6, 1.0), (4.25, 0.6, 2.4), (4.25, -0.6, 2.4)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((4.4, 0, 2.75), AMBER, 8)
    sp.glow((0, 0, 3.2), 34, GROW, 0.35)


@building("algae_reactor", 6, 4, 3.6, "조류 생물반응기")
def algae_reactor(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    sp.box(-2.8, -1.8, 0.35, 0.3, 3.6, 3.0, STEEL)
    sp.box(2.5, -1.8, 0.35, 0.3, 3.6, 3.0, STEEL)
    for row, y in enumerate((-1.1, 0.0, 1.1)):
        sp.line((-2.5, y, 0.6 + row * 0.0), (2.5, y, 0.6), 0.1, "#7d848d")
        for i in range(7):
            x = -2.1 + i * 0.7
            sp.cyl((x, y, 0.55), (x, y, 3.2), 0.22, Mat("#58A64A", 0.7), edge=False)
            sp.glow((x, y, 2.0), 7, "#9BEA7A", 0.35)
    sp.line((-2.65, -1.8, 3.35), (-2.65, 1.8, 3.35), 0.1, "#7d848d")
    sp.line((2.65, -1.8, 3.35), (2.65, 1.8, 3.35), 0.1, "#7d848d")
    sp.box(1.2, 1.9, 0.35, 1.5, 0.9, 1.1, WHITE)
    sp.lamp((2.9, 2.0, 1.6), "#9BEA7A", 7)


@building("food_store", 7, 5, 2.8, "식량 저장고")
def food_store(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 3.2)
    # 묻힌 냉장 창고: 흙 경사면 + 앞쪽 하역문
    sp.tbox(-3.5, -2.6, 2.6, 2.6, 1.2, 2.4, BERM)
    # 앞쪽 콘크리트 면과 문
    sp.box(2.6, -2.0, 0, 0.6, 4.0, 2.5, SINTER)
    f = Sprite.box_faces(2.6, -2.0, 0, 0.6, 4.0, 2.5)
    door(sp, f["right"], 0.2, 0.62, 0.7, STEEL)
    sp.stripes(*sp.on_face(*f["right"], 0.66, 0.0, 0.95, 0.12)[0:1], (0, 1.1, 0), (0, 0, 0.3), n=4, normal=(1, 0, 0))
    # 냉각 방열판
    o, e1, e2 = (-2.0, -0.9, 2.4), (2.6, 0, 0), (0, 0, 1.4)
    sp.quad(o, e1, e2, RADIATOR)
    sp.panel_grid(o, e1, e2, 5, 1, "#b7bcc2", 0.5, 0.8)
    sp.lamp((3.3, 1.4, 2.3), "#7fe3da", 7)


# ── 전력 ─────────────────────────────────────────────────────────────

@building("solar_tower", 7, 5, 22.0, "수직 태양광 타워")
def solar_tower(sp: Sprite):
    sp.contact_shadow(0, 0, 2.4, 2.4, 0.5)
    sp.box(-1.4, -1.4, 0, 2.8, 2.8, 0.6, SINTER)
    sp.box(-0.6, -0.6, 0.6, 1.2, 1.2, 0.8, STEEL)
    sp.cyl((0, 0, 1.4), (0, 0, 21.0), 0.32, SILVER)
    for z in (5.0, 9.5, 14.0, 18.5):
        sp.ring3((0, 0, z), 0.34, "#7d848d", 0.06)
    # 태양 쪽(왼쪽)으로 선 패널. 전지 면이 보이도록 둔다
    o, e1, e2 = (2.9, -0.55, 7.0), (-5.8, 1.1, 0.0), (0.0, 0.0, 13.5)
    sp.quad(o, e1, e2, SOLAR, back=STEEL)
    sp.panel_grid(o, e1, e2, 4, 9, "#6f86b0", 0.55, 0.6)
    # 테두리
    sp.polyline3([o, add(o, e1), add(add(o, e1), e2), add(o, e2), o], "#c0c6ce", 0.08)
    sp.line((0, 0, 21.0), (0, 0, 22.3), 0.06, "#9aa1aa")
    sp.lamp((0, 0, 22.4), "#ff5a3c", 6)


@building("fission_40kw", 6, 6, 6.5, "소형 핵분열로")
def fission_40kw(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 3.6, 0.5)
    # 육각 받침
    hexa = [(2.6 * math.cos(math.radians(a)), 2.6 * math.sin(math.radians(a))) for a in range(0, 360, 60)]
    sp.prism(hexa, 0, 0.5, STEEL, top=DARK)
    sp.stripes((2.6, 0.0, 0.0), (-1.3, 2.25, 0.0), (0, 0, 0.5), n=6)
    # 원자로 차폐체(원뿔대)와 전력 변환기
    sp.frustum((0, 0, 0.5), (0, 0, 2.6), 1.35, 1.05, GOLD, bands=[0.5])
    sp.cyl((0, 0, 2.6), (0, 0, 3.4), 0.8, SILVER)
    # 별 모양으로 선 방열 지느러미 6장 (뒤에서 앞 순서)
    fins = []
    for k in range(6):
        a = math.radians(15 + k * 60)
        fins.append((dot((math.cos(a), math.sin(a), 0.0), VIEW), a))
    fins.sort()
    for _, a in fins[:3]:
        d = (math.cos(a), math.sin(a), 0.0)
        o = add((0, 0, 3.2), mul(d, 0.3))
        sp.quad(o, mul(d, 2.3), (0, 0, 3.2), RADIATOR, back=RADIATOR)
        sp.panel_grid(o, mul(d, 2.3), (0, 0, 3.2), 3, 1, "#b9bec4", 0.5, 0.7)
    sp.cyl((0, 0, 3.2), (0, 0, 6.5), 0.28, STEEL)
    for _, a in fins[3:]:
        d = (math.cos(a), math.sin(a), 0.0)
        o = add((0, 0, 3.2), mul(d, 0.3))
        sp.quad(o, mul(d, 2.3), (0, 0, 3.2), RADIATOR, back=RADIATOR)
        sp.panel_grid(o, mul(d, 2.3), (0, 0, 3.2), 3, 1, "#b9bec4", 0.5, 0.7)
    sp.lamp((0, 0, 6.6), "#ff5a3c", 6)
    sp.glow((0, 0, 1.6), 16, "#ffb35c", 0.25)


@building("fission_1mw", 16, 12, 8.5, "메가와트급 원자로")
def fission_1mw(sp: Sprite):
    sp.contact_shadow(0, 0, 8.4, 6.4, 0.5)
    # 원자로는 구덩이 속, 둘레를 흙 둑으로 막는다
    sp.berm_ring((-3.5, 0, 0), 2.6, 5.0, 2.2, front=False)
    sp.cyl((-3.5, 0, 0), (-3.5, 0, 2.6), 2.1, DARK, cap_mat=STEEL)
    sp.cyl((-3.5, 0, 2.6), (-3.5, 0, 3.4), 1.2, GOLD)
    sp.berm_ring((-3.5, 0, 0), 2.6, 5.0, 2.2, front=True)
    # 전력 변환 건물
    sp.box(0.5, -1.6, 0, 3.0, 3.2, 2.6, WHITE, top=SILVER)
    f = Sprite.box_faces(0.5, -1.6, 0, 3.0, 3.2, 2.6)
    sp.stripes(*f["left"][:1], (-3.0, 0, 0), (0, 0, 0.35), n=10, normal=(0, 1, 0))
    door(sp, f["right"], 0.3, 0.7, 0.7, STEEL)
    pipe(sp, [(-3.5, 0, 3.0), (0.5, 0, 2.2)], 0.3)
    # 방열판 두 줄
    for y in (-4.6, -2.2, 0.2, 2.6):
        sp.line((3.9, y, 0.3), (7.9, y, 0.3), 0.2, "#7d848d")
        for x in (3.9, 5.95):
            o, e1, e2 = (x, y, 0.4), (1.95, 0.0, 0.0), (0.0, 0.0, 7.6)
            sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
            sp.panel_grid(o, e1, e2, 1, 7, "#c5c9cd", 0.5, 0.7)
    sp.lamp((-3.5, 0, 3.8), "#ff5a3c", 7)
    sp.glow((-3.5, 0, 2.4), 26, "#ffb35c", 0.3)


@building("battery_bank", 7, 4, 2.6, "배터리 뱅크")
def battery_bank(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.25, SINTER)
    for i, x in enumerate((-3.2, -1.0, 1.2)):
        sp.box(x, -1.5, 0.25, 2.0, 3.0, 2.1, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
        f = Sprite.box_faces(x, -1.5, 0.25, 2.0, 3.0, 2.1)
        o, e1, e2 = f["left"]
        for k in range(4):
            v = 0.2 + k * 0.17
            sp.face(sp.on_face(o, e1, e2, 0.12, v, 0.88, v + 0.07), CHAR, normal=(0, 1, 0), edge=False, ao=0)
        sp.window(sp.on_face(o, e1, e2, 0.42, 0.86, 0.58, 0.93), "#7CF29A", frame=None, glass=Mat("#2c8f4f", 0.4))
    sp.lamp((3.4, 1.8, 1.0), "#7CF29A", 6)


@building("rfc_unit", 5, 4, 2.8, "재생 연료전지")
def rfc_unit(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2.0, 5, 4)
    # 수소·산소 탱크 (누운 원기둥)
    for y, band in ((-1.1, "#d8853b"), (0.15, "#3FB8AF")):
        sp.box(-1.9, y - 0.45, 0.35, 0.3, 0.9, 0.5, STEEL)
        sp.box(0.9, y - 0.45, 0.35, 0.3, 0.9, 0.5, STEEL)
        sp.cyl((-2.2, y, 1.25), (1.5, y, 1.25), 0.55, WHITE, cap_mat=WHITE)
        sp.ring3((1.0, y, 1.25), 0.56, band, 0.14, normal=(1, 0, 0), front_only=True)
    # 연료전지 상자
    sp.box(-1.6, 0.9, 0.35, 3.0, 1.0, 1.5, Mat("#5B6470", 0.2), top=SILVER)
    f = Sprite.box_faces(-1.6, 0.9, 0.35, 3.0, 1.0, 1.5)
    windows_row(sp, f["left"], 3, 0.5, 0.75, 0.1, 0.08, "#7fe3da")
    sp.lamp((2.0, 1.9, 1.0), "#7fe3da", 6)


# ── 열 ───────────────────────────────────────────────────────────────

@building("radiator", 8, 3, 6.8, "방열판")
def radiator(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 1.8, 0.4)
    sp.box(-3.8, -0.6, 0, 7.6, 1.2, 0.4, STEEL)
    for i in range(3):
        x = -3.4 + i * 2.5
        o, e1, e2 = (x, 0.0, 0.4), (2.2, 0.0, 0.0), (0.0, 0.0, 6.2)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 6, 1, "#b9bec4", 0.5, 0.7)
        sp.line((x + 1.1, 0, 0.4), (x + 1.1, 0, 6.6), 0.1, "#8a9099")
    pipe(sp, [(-3.6, 0.3, 0.6), (3.8, 0.3, 0.6)], 0.16)


# ── 산업 ─────────────────────────────────────────────────────────────

@building("ice_miner", 12, 9, 5.0, "얼음 채굴기")
def ice_miner(sp: Sprite):
    sp.contact_shadow(0, 0, 6.4, 4.8, 0.5)
    # 영구 그늘의 얼음 퇴적층 위에 세운 가열 천막
    sp.ellipsoid((0, 0, 0), 5.6, 4.2, 0.18, Mat("#8E9AA3", 0.2), clip_z=0.0)
    for k, (x, y) in enumerate(((-3.8, -2.6), (2.2, 2.8), (-1.0, 3.4), (4.2, -2.2))):
        sp.ellipsoid((x, y, 0.0), 0.7, 0.5, 0.12, ICE, clip_z=0.0)
    # 얼음을 데워 증기로 모으는 금빛 단열 천막
    sp.ellipsoid((-1.0, 0, 0), 3.6, 2.8, 2.6, GOLD, clip_z=0.0)
    for zz in (0.8, 1.6, 2.2):
        k = math.sqrt(max(0.0, 1 - (zz / 2.6) ** 2))
        pts = [(-1.0 + 3.6 * k * math.cos(t / 24 * math.pi * 2), 2.8 * k * math.sin(t / 24 * math.pi * 2), zz)
               for t in range(25) if dot((math.cos(t / 24 * math.pi * 2), math.sin(t / 24 * math.pi * 2), 0), VIEW) > -0.1]
        sp.polyline3(pts, "#8f6d22", 0.05, 0.8)
    # 수증기 회수관과 탱크
    pipe(sp, [(-1.0, 0, 2.6), (-1.0, 0, 3.3), (3.4, 0, 3.3), (3.4, 0, 2.6)], 0.22)
    sp.cyl((3.4, -0.2, 0), (3.4, -0.2, 2.6), 0.9, WHITE, bands=[0.3, 0.7])
    sp.sphere((3.4, -0.2, 2.6), 0.9, WHITE)
    sp.window(Sprite.cyl_patch((3.4, -0.2, 0), (3.4, -0.2, 2.6), 0.9, 0.45, 0.6, -20, 110), "#9fd8ff",
              frame=None, glass=BLUE, light_alpha=0.0)
    # 투광등 (어두운 분화구 바닥)
    for p in ((5.2, 2.8, 0), (-4.4, 3.8, 0), (4.6, -3.6, 0)):
        sp.line(p, add(p, (0, 0, 3.4)), 0.08, "#8a9099")
        sp.lamp(add(p, (0, 0, 3.5)), AMBER, 22)
    sp.glow((0, 0, 1.0), 48, AMBER, 0.22)


@building("excavator", 9, 6, 3.0, "레골리스 굴착기")
def excavator(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.4)
    # 파 놓은 흙더미
    sp.ellipsoid((-2.6, -0.8, 0), 2.4, 2.0, 1.6, REGOLITH, clip_z=0.0)
    sp.ellipsoid((-1.2, 1.4, 0), 1.6, 1.3, 1.0, REGOLITH, clip_z=0.0)
    # 드럼 굴착 로봇 (RASSOR 계열)
    body = (1.6, 0.6, 0.9)
    sp.box(0.7, -0.1, 0.55, 1.8, 1.4, 0.75, WHITE, top=SILVER)
    for x in (0.25, 2.95):
        sp.line((1.6, 0.6, 0.95), (x, 0.6, 0.65), 0.18, "#7d848d")
        sp.cyl((x, -0.35, 0.65), (x, 1.55, 0.65), 0.62, STEEL, bands=[0.2, 0.4, 0.6, 0.8], cap_mat=DARK)
    sp.box(1.2, 0.2, 1.3, 0.8, 0.8, 0.3, SOLAR)
    sp.lamp((2.55, 1.35, 1.2), AMBER, 7)
    # 차고 표시판
    sp.box(3.2, -2.6, 0, 0.3, 0.3, 2.6, STEEL)
    sp.lamp((3.35, -2.45, 2.7), AMBER, 10)


@building("regolith_printer", 12, 9, 7.2, "레골리스 3D 프린터")
def regolith_printer(sp: Sprite):
    sp.contact_shadow(0, 0, 6.4, 4.8, 0.45)
    # 인쇄 중인 벽 (아래 반만 찍힌 돔)
    for zz, r in ((0.0, 4.0), (0.6, 3.92), (1.2, 3.75), (1.8, 3.5)):
        sp.cyl((0, 0, zz), (0, 0, zz + 0.6), r, SINTER, edge=True, cap_mat=SINTER)
    sp.ring3((0, 0, 2.4), 3.5, "#83745f", 0.05)
    # 갠트리
    posts = [(-5.0, -3.6), (5.0, -3.6), (-5.0, 3.6), (5.0, 3.6)]
    back = [p for p in posts if p[0] + p[1] < 0.5]
    for x, y in back:
        sp.box(x - 0.25, y - 0.25, 0, 0.5, 0.5, 6.6, ORANGE)
    sp.box(-5.25, -3.85, 6.6, 10.5, 0.5, 0.5, ORANGE)
    sp.box(-5.25, 3.35, 6.6, 10.5, 0.5, 0.5, ORANGE)
    sp.box(1.0, -3.85, 6.1, 0.6, 7.7, 0.5, YELLOW)
    # 노즐
    sp.line((1.3, 0.6, 6.1), (1.3, 0.6, 2.7), 0.18, "#7d848d")
    sp.frustum((1.3, 0.6, 2.9), (1.3, 0.6, 2.45), 0.35, 0.12, DARK)
    sp.glow((1.3, 0.6, 2.4), 12, "#ff8a3a", 0.8)
    for x, y in posts:
        if (x, y) not in back:
            sp.box(x - 0.25, y - 0.25, 0, 0.5, 0.5, 6.6, ORANGE)
    sp.lamp((5.0, 3.6, 7.3), AMBER, 10)


@building("mre_plant", 9, 7, 6.5, "용융 레골리스 전해조")
def mre_plant(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    # 원료 깔때기
    sp.frustum((-2.6, -1.6, 3.6), (-2.6, -1.6, 5.6), 0.35, 1.3, STEEL)
    legs(sp, [(-3.4, -2.4, 4.0), (-1.8, -2.4, 4.0), (-3.4, -0.8, 4.0), (-1.8, -0.8, 4.0)], 0.3)
    # 반응로 (두꺼운 단열 원기둥)
    sp.cyl((-0.6, -0.4, 0.3), (-0.6, -0.4, 4.2), 1.7, Mat("#6B5A4C", 0.15), bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
    sp.window(Sprite.cyl_patch((-0.6, -0.4, 0.3), (-0.6, -0.4, 4.2), 1.7, 0.3, 0.45, 10, 70), "#ff7b2e",
              frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
    pipe(sp, [(-2.6, -1.6, 3.6), (-1.4, -1.0, 4.1)], 0.25)
    sp.glow((-0.6, -0.4, 1.3), 26, "#ff7b2e", 0.55)
    # 산소 탱크와 금속 주괴
    sp.sphere((2.6, -1.8, 1.4), 1.1, WHITE)
    sp.ring3((2.6, -1.8, 1.4), 1.1, "#3FB8AF", 0.12)
    pipe(sp, [(1.1, -0.6, 3.0), (2.6, -1.8, 2.5)])
    for i in range(3):
        for k in range(2 - (i == 2)):
            sp.box(1.3 + k * 1.0, 1.3 + i * 0.0, 0.3 + i * 0.32, 0.9, 1.8, 0.3, Mat("#C2C7CD", 0.6))
    sp.lamp((3.9, 3.0, 1.5), AMBER, 8)


@building("parts_fab", 10, 8, 4.6, "부품 공장")
def parts_fab(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.box(-4.6, -3.6, 0, 7.4, 7.2, 3.6, WHITE, top=SILVER)
    f = Sprite.box_faces(-4.6, -3.6, 0, 7.4, 7.2, 3.6)
    # 톱니 지붕 (채광 대신 방열·설비)
    for i in range(4):
        y = -3.6 + i * 1.8
        sp.face([(-4.6, y, 3.6), (2.8, y, 3.6), (2.8, y + 1.8, 4.5), (-4.6, y + 1.8, 4.5)], SOLAR, ao=0)
        sp.face([(2.8, y + 1.8, 3.6), (-4.6, y + 1.8, 3.6), (-4.6, y + 1.8, 4.5), (2.8, y + 1.8, 4.5)], WHITE, ao=0)
        sp.face([(2.8, y, 3.6), (2.8, y + 1.8, 3.6), (2.8, y + 1.8, 4.5)], WHITE, ao=0)
    band_on(sp, f["left"], 0.82, 0.9, ORANGE)
    windows_row(sp, f["left"], 4, 0.45, 0.7, 0.08, 0.06)
    door(sp, f["right"], 0.3, 0.72, 0.7, Mat("#8C939C", 0.3))
    # 밖의 로봇 팔과 상자
    sp.box(3.4, -2.6, 0, 0.8, 0.8, 0.5, DARK)
    sp.polyline3([(3.8, -2.2, 0.5), (3.8, -2.2, 2.4), (4.8, -1.4, 3.0), (5.0, -0.8, 2.2)], "#E07B39", 0.22)
    crate(sp, 3.6, 0.6, 1.1)
    crate(sp, 3.6, 1.9, 1.1, Mat("#C9A23A"))
    crate(sp, 3.6, 1.25, 1.0, ORANGE, 0.88)


@building("robot_bay", 10, 7, 4.2, "로봇 정비고")
def robot_bay(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.5)
    sp.box(-4.8, -3.2, 0, 9.6, 6.4, 0.2, SINTER)
    sp.half_cyl((-4.2, 0, 0.2), (3.4, 0, 0.2), 3.0, Mat("#DAD3C4"), bands=[0.15, 0.3, 0.45, 0.6, 0.75, 0.9],
                band_color="#ada594", caps=True, cap_mat=WHITE)
    # 열린 문 (어두운 속에 로봇 실루엣)
    sp.face([(3.45, -1.8, 0.2), (3.45, 1.8, 0.2), (3.45, 1.8, 2.4), (3.45, -1.8, 2.4)], CHAR, normal=(1, 0, 0), ao=0)
    sp.box(3.46, -0.6, 0.2, 0.02, 1.2, 1.3, Mat("#3a3f47"))
    sp.poly2([PV((3.47, -1.8, 0.2)), PV((3.47, 1.8, 0.2)), PV((3.47, 1.8, 2.4)), PV((3.47, -1.8, 2.4))],
             "#ffcf8a", None, 0, 0.55, layer="light")
    sp.stripes((3.48, -1.8, 2.4), (0, 3.6, 0), (0, 0, 0.3), n=10, normal=(1, 0, 0))
    # 충전 패드
    for y in (-2.4, 2.4):
        sp.box(3.8, y - 0.5, 0.2, 1.0, 1.0, 0.08, DARK)
        sp.lamp((4.3, y, 0.35), AMBER, 7)


@building("propellant_plant", 9, 7, 9.5, "추진제 공장")
def propellant_plant(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    # 큰 탱크 둘: 액체산소(흰색, 성에), 액체수소(주황 단열재)
    sp.cyl((-2.4, -1.6, 0.3), (-2.4, -1.6, 8.4), 1.3, ICE, bands=[0.2, 0.4, 0.6, 0.8], band_color="#b5c6cf")
    sp.sphere((-2.4, -1.6, 8.4), 1.3, ICE)
    sp.cyl((0.6, -2.0, 0.3), (0.6, -2.0, 7.0), 1.15, Mat("#D9893F", 0.1), bands=[0.5])
    sp.sphere((0.6, -2.0, 7.0), 1.15, Mat("#D9893F", 0.1))
    # 냉각 상자와 방열판
    sp.box(-1.6, 0.6, 0.3, 3.4, 2.4, 2.6, WHITE, top=SILVER)
    f = Sprite.box_faces(-1.6, 0.6, 0.3, 3.4, 2.4, 2.6)
    band_on(sp, f["left"], 0.8, 0.9, BLUE)
    sp.window(sp.on_face(*f["left"], 0.6, 0.35, 0.85, 0.6), "#9fd8ff")
    o, e1, e2 = (2.4, -0.4, 0.3), (0.0, 3.6, 0.0), (0.0, 0.0, 3.4)
    sp.quad(o, e1, e2, RADIATOR)
    sp.panel_grid(o, e1, e2, 5, 1, "#b9bec4", 0.5, 0.7)
    pipe(sp, [(-2.4, -0.3, 1.5), (-1.6, 1.0, 1.5)])
    pipe(sp, [(0.6, -0.85, 1.2), (0.2, 0.6, 1.2)])
    sp.lamp((-2.4, -1.6, 9.9), "#ff5a3c", 6)


# ── 물류·안전·연구·사회 ───────────────────────────────────────────────

@building("landing_pad", 34, 34, 2.0, "착륙장")
def landing_pad(sp: Sprite):
    r = 13.5
    sp.berm_ring((0, 0, 0), r + 1.0, r + 3.2, 1.6, front=False)
    # 소결 포장면
    pts = [(r * math.cos(2 * math.pi * i / 64), r * math.sin(2 * math.pi * i / 64), 0.05) for i in range(64)]
    sp.face(pts, SINTER, normal=(0, 0, 1), ao=0)
    for rr in (3.5, 7.0, 10.5):
        sp.ring3((0, 0, 0.06), rr, "#8a7c68", 0.08, front_only=False)
    for i in range(12):
        a = 2 * math.pi * i / 12
        sp.line((3.5 * math.cos(a), 3.5 * math.sin(a), 0.06), (r * math.cos(a), r * math.sin(a), 0.06), 0.06, "#8a7c68")
    # 표적 표시
    sp.ring3((0, 0, 0.07), 2.4, "#E9C24A", 0.35, front_only=False)
    sp.line((-1.4, -1.4, 0.07), (1.4, 1.4, 0.07), 0.35, "#E9C24A")
    sp.line((-1.4, 1.4, 0.07), (1.4, -1.4, 0.07), 0.35, "#E9C24A")
    # 둘레 등
    for i in range(16):
        a = 2 * math.pi * i / 16
        p = (r * 0.97 * math.cos(a), r * 0.97 * math.sin(a), 0.1)
        sp.lamp(p, AMBER, 9)
    sp.berm_ring((0, 0, 0), r + 1.0, r + 3.2, 1.6, front=True)


@building("storm_shelter", 11, 8, 4.4, "폭풍 대피소")
def storm_shelter(sp: Sprite):
    sp.contact_shadow(0, 0, 6.0, 4.4, 0.5)
    # 3 m 두께의 흙을 덮은 벙커
    sp.ellipsoid((-0.6, 0, 0), 5.4, 3.9, 4.0, BERM, clip_z=0.0)
    for zz in (1.0, 2.0, 3.0):
        k = math.sqrt(max(0.0, 1 - (zz / 4.0) ** 2))
        pts = []
        for i in range(49):
            t = 2 * math.pi * i / 48
            if dot((math.cos(t), math.sin(t), 0), VIEW) > -0.1:
                pts.append((-0.6 + 5.4 * k * math.cos(t), 3.9 * k * math.sin(t), zz))
        sp.polyline3(pts, "#5f5953", 0.06, 0.8)
    # 콘크리트 출입구 (경고 줄)
    sp.box(3.6, -1.4, 0, 1.9, 2.8, 2.6, SINTER, top=Mat("#a39581"))
    f = Sprite.box_faces(3.6, -1.4, 0, 1.9, 2.8, 2.6)
    door(sp, f["right"], 0.25, 0.75, 0.72, Mat("#5c626b", 0.3))
    o, e1, e2 = f["right"]
    sp.stripes(add(o, (0.01, 0, 2.6 * 0.8)), (0, 2.8, 0), (0, 0, 0.42), n=8, normal=(1, 0, 0))
    o, e1, e2 = f["left"]
    sp.stripes(add(o, (0, 0.01, 2.6 * 0.8)), (-1.9, 0, 0), (0, 0, 0.42), n=6, normal=(0, 1, 0))
    antenna(sp, (-2.4, -1.0, 3.5), 2.2)


@building("medical_bay", 8, 6, 4.0, "의료실")
def medical_bay(sp: Sprite):
    sp.contact_shadow(0, 0, 4.6, 3.6)
    sp.box(-3.6, -2.6, 0, 7.2, 5.2, 0.4, STEEL)
    sp.box(-3.4, -2.4, 0.4, 6.4, 4.8, 3.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.4, -2.4, 0.4, 6.4, 4.8, 3.0)
    band_on(sp, f["left"], 0.84, 0.94, TEAL)
    windows_row(sp, f["left"], 3, 0.4, 0.68, 0.32, 0.06)
    # 청록 십자
    o, e1, e2 = f["left"]
    cu, cv = 0.15, 0.55
    sp.face(sp.on_face(o, e1, e2, cu - 0.03, cv - 0.16, cu + 0.03, cv + 0.16), TEAL, normal=(0, 1, 0), ao=0)
    sp.face(sp.on_face(o, e1, e2, cu - 0.075, cv - 0.065, cu + 0.075, cv + 0.065), TEAL, normal=(0, 1, 0), ao=0)
    door(sp, f["right"], 0.3, 0.7, 0.68, Mat("#cfd6dc", 0.3))
    sp.box(-0.6, -1.0, 3.4, 2.0, 2.0, 0.5, STEEL)
    sp.lamp((3.1, 2.5, 3.0), CYAN_LIGHT, 8)


@building("research_lab", 9, 7, 7.5, "연구동")
def research_lab(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.4, STEEL)
    # 관측 돔 (뒤)
    sp.cyl((-2.2, -1.6, 3.6), (-2.2, -1.6, 4.4), 1.2, WHITE)
    sp.sphere((-2.2, -1.6, 4.4), 1.2, WHITE, clip_z=4.4)
    sp.face([(-1.6, -2.3, 4.6), (-1.6, -0.9, 4.6), (-1.4, -0.9, 5.3), (-1.4, -2.3, 5.3)], CHAR, two_sided=True)
    sp.box(-3.8, -2.8, 0.4, 7.4, 5.4, 3.2, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.8, -2.8, 0.4, 7.4, 5.4, 3.2)
    band_on(sp, f["left"], 0.84, 0.94, Mat("#9B7AD6"))
    windows_row(sp, f["left"], 4, 0.42, 0.7, 0.08, 0.05)
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.15, 0.25, 0.45, 0.6), GLASS, normal=(1, 0, 0), ao=0)   # 시료 글러브박스
    door(sp, f["right"], 0.6, 0.85, 0.66)
    # 장비 기둥 (분광계·안테나)
    sp.line((2.6, 2.0, 3.6), (2.6, 2.0, 7.2), 0.1, "#9aa1aa")
    sp.box(2.3, 1.7, 5.6, 0.6, 0.6, 0.5, GOLD)
    sp.disc((2.6, 2.0, 7.0), (0.3, 0.6, 0.75), 0.7, WHITE, back=STEEL)
    sp.lamp((2.6, 2.0, 7.4), "#ff5a3c", 6)


@building("green_commons", 16, 16, 7.0, "녹지 공원")
def green_commons(sp: Sprite):
    r = 7.2
    sp.contact_shadow(0, 0, 7.8, 7.8, 0.45)
    sp.cyl((0, 0, 0), (0, 0, 0.6), r + 0.3, SINTER, cap_mat=Mat("#7FA864"))
    # 안의 잔디와 나무 (유리 너머로 보인다)
    sp.ring3((0, 0, 0.62), r - 0.4, "#5b8a4a", 0.25, front_only=False)
    trees = [(-3.0, -2.6, 4.6, 1.5), (0.6, -3.6, 3.8, 1.2), (-4.2, 1.0, 3.6, 1.1), (2.8, -0.6, 4.2, 1.4),
             (-0.8, 1.2, 5.0, 1.7), (3.4, 2.8, 3.2, 1.0), (-2.4, 3.8, 3.0, 1.0), (1.2, 4.4, 2.6, 0.9)]
    trees.sort(key=lambda t: t[0] + t[1])
    for x, y, h, rr in trees:
        sp.tree((x, y, 0.6), h, rr, LEAF if (x + y) % 2 > 1 else GREEN)
    sp.box(1.6, 1.0, 0.6, 1.4, 0.4, 0.45, COPPER)       # 벤치
    sp.glow((0, 0, 2.4), 60, WARM_WINDOW, 0.35)
    # 유리 돔: 반투명 + 측지선
    dome_pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            dome_pts.append(P(r * math.cos(ph) * math.cos(th), r * math.cos(ph) * math.sin(th), 0.6 + 6.2 * math.sin(ph)))
    sil = hull(dome_pts)
    hl = PV((-2.0, 3.5, 5.6))
    fill = sp.radial([(0, "#ffffff", 0.32), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.05)], hl[0], hl[1], r * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    for zz in (1.8, 3.4, 4.8, 6.0):
        k = math.sqrt(max(0.0, 1 - ((zz - 0.6) / 6.2) ** 2))
        sp.ring3((0, 0, zz), r * k, "#dfe9f2", 0.05, opacity=0.55)
    for i in range(12):
        th = 2 * math.pi * i / 12
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.2:
            continue
        pts = [(r * math.cos(ph) * math.cos(th), r * math.cos(ph) * math.sin(th), 0.6 + 6.2 * math.sin(ph))
               for ph in [k * math.pi / 2 / 12 for k in range(13)]]
        sp.polyline3(pts, "#dfe9f2", 0.05, 0.5)
    sp.half_cyl((7.0, 0, 0), (8.4, 0, 0), 1.3, WHITE)
    sp.face([(8.45, -0.5, 0), (8.45, 0.5, 0), (8.45, 0.5, 1.05), (8.45, -0.5, 1.05)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((8.5, 0.9, 1.4), AMBER, 8)


@building("comms_center", 9, 7, 9.0, "지구 교신 센터")
def comms_center(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.8)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.3, SINTER)
    # 큰 접시: 극지에서 지구는 지평선 가까이 있으므로 거의 옆을 본다
    sp.box(-3.0, -2.4, 0.3, 2.4, 2.4, 1.6, STEEL)
    sp.cyl((-1.8, -1.2, 1.9), (-1.8, -1.2, 5.4), 0.45, SILVER)
    c = (-1.6, -0.9, 6.0)
    n = norm((0.15, 1.0, 0.18))
    sp.disc(c, n, 3.0, WHITE, back=STEEL, seg=48)
    sp.ring3(c, 3.0, "#b9b2a5", 0.1, normal=n, front_only=False)
    sp.ring3(c, 1.8, "#d8d2c6", 0.05, normal=n, front_only=False)
    feed = add(c, mul(n, 1.9))
    for a in (0, 120, 240):
        u, v = basis(n)
        rim = add(c, add(mul(u, 2.6 * math.cos(math.radians(a))), mul(v, 2.6 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.06, "#8a9099")
    sp.sphere(feed, 0.22, GOLD)
    # 교신실
    sp.box(0.4, -0.6, 0.3, 3.2, 3.2, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(0.4, -0.6, 0.3, 3.2, 3.2, 2.4)
    band_on(sp, f["left"], 0.82, 0.92, Mat("#F2A541"))
    windows_row(sp, f["left"], 2, 0.4, 0.66, 0.18, 0.12)
    door(sp, f["right"], 0.35, 0.7, 0.72)
    antenna(sp, (3.0, 2.0, 2.7), 3.2)


# ── 공사 비계 ────────────────────────────────────────────────────────

def _scaffold(sp: Sprite, w: float, d: float, h: float):
    sp.contact_shadow(0, 0, w * 0.55, d * 0.55, 0.3)
    sp.box(-w / 2, -d / 2, 0, w, d, 0.15, Mat("#6f685f"))
    xs = [-w / 2, 0.0, w / 2]
    ys = [-d / 2, 0.0, d / 2]
    col = "#E9C24A"
    def pole(x, y):
        sp.line((x, y, 0.15), (x, y, h), 0.12, col)
    # 뒤쪽 기둥
    for x in xs:
        pole(x, -d / 2)
    for y in ys[1:]:
        pole(-w / 2, y)
    for z in (h * 0.5, h):
        sp.polyline3([(-w / 2, d / 2, z), (-w / 2, -d / 2, z), (w / 2, -d / 2, z)], col, 0.1)
    # 반쯤 지은 몸체
    sp.box(-w / 2 + 0.6, -d / 2 + 0.6, 0.15, w - 1.2, d - 1.2, h * 0.45, Mat("#cfc6b6"))
    for x in xs[1:]:
        pole(x, d / 2)
    for y in ys[:2]:
        pole(w / 2, y)
    for z in (h * 0.5, h):
        sp.polyline3([(-w / 2, d / 2, z), (w / 2, d / 2, z), (w / 2, -d / 2, z)], col, 0.1)
    sp.line((-w / 2, d / 2, 0.15), (w / 2, d / 2, h * 0.5), 0.08, col)
    sp.line((w / 2, -d / 2, 0.15), (w / 2, d / 2, h * 0.5), 0.08, col)
    sp.lamp((w / 2, d / 2, h + 0.2), AMBER, 9)


@building("scaffold_s", 5, 4, 3.0, "공사 중 (작은 건물)")
def scaffold_s(sp: Sprite):
    _scaffold(sp, 5.0, 4.0, 3.0)


@building("scaffold_m", 9, 6, 4.0, "공사 중 (중간 건물)")
def scaffold_m(sp: Sprite):
    _scaffold(sp, 9.0, 6.0, 4.0)


@building("scaffold_l", 14, 12, 5.0, "공사 중 (큰 건물)")
def scaffold_l(sp: Sprite):
    _scaffold(sp, 14.0, 12.0, 5.0)
