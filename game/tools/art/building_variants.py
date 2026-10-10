"""건물 변형 — 종류마다 겉모습이 다른 설계 4가지를 더한다 (v1~v4, v0은 buildings.py의 기본 설계).

기능과 밸런스는 같고 모양만 다르다. 지도에서는 자리마다 변형을 하나씩 골라 기지가 복사한 것처럼 보이지 않게 한다.
변형은 기본 설계와 같은 바닥 칸 안에 들어가야 한다 (구역 배치가 움직이지 않도록).
"""
from __future__ import annotations

import math

from iso import *  # noqa: F401,F403
from buildings import (BUILDINGS, antenna, band_on, crate, door, legs, pipe, skid,  # noqa: F401
                       windows_row)

PINK_GLASS = Mat("#2a1f33", 0.8)
ALGAE = Mat("#58A64A", 0.7)
ALGAE_DARK = Mat("#3f7f35", 0.6)
FROST = Mat("#E6EEF2", 0.35)
FOAM = Mat("#D9893F", 0.1)
CONCRETE = Mat("#A39581")


def variant(bid: str, v: int, height: float | None = None):
    """BUILDINGS[bid]의 v번째 변형으로 등록한다."""
    def deco(fn):
        spec = BUILDINGS[bid]
        vs = spec.setdefault("variants", {})
        vs[v] = {"fn": fn, "height": height}
        return fn
    return deco


def cyl_windows(sp: Sprite, p0, p1, r, s0, s1, toward=(0.35, 1.0, 0.0), n=3, spread=28.0, width=12.0,
                glow=WARM_WINDOW, glass: Mat = GLASS):
    """원기둥 겉면에 창을 한 줄로 낸다 (보이는 쪽)."""
    ang = Sprite.facing_angle(p0, p1, norm(toward))
    for k in range(n):
        a = ang - spread * (n - 1) / 2 + k * spread
        sp.window(Sprite.cyl_patch(p0, p1, r, s0, s1, a - width / 2, a + width / 2), glow, glass=glass)


def cyl_ring(sp: Sprite, p0, p1, r, s0, s1, mat: Mat, glow: str | None = None, glow_alpha: float = 0.7):
    """원기둥을 두르는 색 띠 (보이는 쪽 소매 모양, 원기둥과 같은 음영). glow를 주면 밤에 빛난다."""
    axis = sub(p1, p0)
    a = add(p0, mul(axis, s0))
    b = add(p0, mul(axis, s1))
    sil = sp.cyl(a, b, r + 0.02, mat, caps=False, edge=False)
    if glow:
        sp.poly2(sil, glow, None, 0, glow_alpha, layer="light")


def sandbag_rings(sp: Sprite, c, rx, ry, rz, levels, color="#5f5953"):
    for zz in levels:
        k = math.sqrt(max(0.0, 1 - ((zz - c[2]) / rz) ** 2))
        pts = []
        for i in range(49):
            t = 2 * math.pi * i / 48
            if dot((math.cos(t), math.sin(t), 0.0), VIEW) > -0.1:
                pts.append((c[0] + rx * k * math.cos(t), c[1] + ry * k * math.sin(t), zz))
        if len(pts) > 1:
            sp.polyline3(pts, color, 0.06, 0.8)


def rounded_rect(x0, y0, x1, y1, c):
    """모서리를 깎은 직사각형 (반시계) — 3D 프린팅 건물의 바닥."""
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def print_lines(sp: Sprite, base, z0, z1, step=0.45, color="#7f7262"):
    """프린팅 층 줄무늬: 보이는 옆면을 따라 수평선을 긋는다."""
    n = len(base)
    z = z0 + step
    while z < z1 - 0.05:
        for i in range(n):
            a, b = base[i], base[(i + 1) % n]
            nrm = norm((b[1] - a[1], -(b[0] - a[0]), 0.0))
            if dot(nrm, VIEW) > 0.02:
                sp.line((a[0], a[1], z), (b[0], b[1], z), 0.04, color)
        z += step


# ── 거주 ─────────────────────────────────────────────────────────────

@variant("hab_module", 1, 7.5)
def hab_tower(sp: Sprite):
    """세운 팽창식 모듈 — 2층."""
    sp.contact_shadow(0, 0, 3.6, 3.6)
    sp.cyl((0, 0, 0), (0, 0, 0.5), 3.0, STEEL)
    p0, p1 = (0, 0, 0.5), (0, 0, 6.2)
    sp.cyl(p0, p1, 2.7, FABRIC, bands=[0.12, 0.27, 0.42, 0.58, 0.73, 0.88], band_color="#b9ab92", cap_mat=WHITE)
    sp.dome((0, 0, 6.2), 2.7, 1.2, WHITE)
    cyl_windows(sp, p0, p1, 2.7, 0.2, 0.3, n=3)
    cyl_windows(sp, p0, p1, 2.7, 0.62, 0.72, n=3)
    sp.box(2.3, -0.9, 0.5, 1.8, 1.8, 2.1, WHITE)
    door(sp, Sprite.box_faces(2.3, -0.9, 0.5, 1.8, 1.8, 2.1)["right"], 0.25, 0.75, 0.8)
    cyl_ring(sp, p0, p1, 2.7, 0.93, 0.97, TEAL, CYAN_LIGHT, 0.5)


@variant("hab_module", 2, 4.0)
def hab_twin(sp: Sprite):
    """단단한 금속 모듈 두 개와 연결 노드."""
    sp.contact_shadow(0, 0, 5.0, 3.6)
    items = []
    for y in (-1.7, 1.7):
        def mod(y=y):
            for x in (-2.6, 1.6):
                sp.box(x - 0.3, y - 1.1, 0, 0.6, 2.2, 0.6, STEEL)
            p0, p1 = (-3.6, y, 1.85), (2.6, y, 1.85)
            sp.cyl(p0, p1, 1.45, WHITE, bands=[0.33, 0.66], band_color="#bdb6a8", cap_mat=STEEL)
            ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.3)))
            for s in (0.12, 0.42, 0.72):
                sp.window(Sprite.cyl_patch(p0, p1, 1.45, s, s + 0.12, ang - 16, ang + 16))
        items.append(((-0.5, y, 1.8), mod))

    def node():
        sp.box(2.5, -0.5, 1.2, 1.2, 1.0, 1.3, STEEL)
        sp.sphere((3.5, 0, 1.85), 1.35, WHITE)
        sp.disc((4.62, 0, 1.85), (1, 0, 0.0), 0.6, DARK)
        sp.lamp((4.7, 0.0, 3.0), AMBER, 9)
    items.append(((3.5, 0, 1.8), node))
    sp.parts(items)
    sp.quad((3.0, -0.9, 3.25), (1.0, 0, 0), (0, 1.8, 0.4), RADIATOR, back=RADIATOR)


@variant("hab_module", 3, 3.6)
def hab_printed(sp: Sprite):
    """레골리스로 찍어 낸 네모난 거주동."""
    sp.contact_shadow(0, 0, 5.2, 3.2)
    base = rounded_rect(-4.6, -2.6, 4.6, 2.6, 1.0)
    sp.prism(base, 0, 3.2, SINTER, top=CONCRETE)
    print_lines(sp, base, 0.0, 3.2)
    o, e1, e2 = (3.6, 2.6, 0.0), (-7.2, 0.0, 0.0), (0.0, 0.0, 3.2)
    for i in range(5):
        u = 0.08 + i * 0.18
        sp.window(sp.on_face(o, e1, e2, u, 0.42, u + 0.08, 0.78))
    o, e1, e2 = (4.6, -1.6, 0.0), (0.0, 3.2, 0.0), (0.0, 0.0, 3.2)
    sp.face(sp.on_face(o, e1, e2, 0.3, 0.0, 0.7, 0.7), DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((4.7, 0.0, 2.6), AMBER, 9)
    sp.quad((-3.0, -1.6, 3.2), (2.4, 0, 0), (0, 0, 1.0), RADIATOR, back=RADIATOR)
    antenna(sp, (2.6, 1.2, 3.2), 1.6)


@variant("hab_module", 4, 4.8)
def hab_porch(sp: Sprite):
    """짧은 팽창식 모듈 + 우주복 출입구가 달린 현관과 태양광 차양."""
    sp.contact_shadow(0, 0, 5.6, 3.2)
    for x in (-3.0, 0.4):
        sp.box(x - 0.3, -1.7, 0, 0.6, 3.4, 0.55, STEEL)
    p0, p1 = (-4.2, 0.0, 2.25), (1.8, 0.0, 2.25)
    sp.cyl(p0, p1, 2.0, FABRIC, bands=[0.17, 0.34, 0.5, 0.67, 0.84], band_color="#b9ab92", cap_mat=WHITE)
    ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.35)))
    for s in (0.2, 0.55):
        sp.window(Sprite.cyl_patch(p0, p1, 2.0, s, s + 0.12, ang - 13, ang + 13))
    sp.box(1.9, -1.7, 0, 2.8, 3.4, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(1.9, -1.7, 0, 2.8, 3.4, 2.4)
    o, e1, e2 = f["right"]
    for u in (0.28, 0.72):
        c = add(add(o, mul(e1, u)), mul(e2, 0.55))
        sp.disc(add(c, (0.02, 0, 0)), (1, 0, 0), 0.5, DARK, two_sided=False)
        sp.ring3(add(c, (0.03, 0, 0)), 0.5, "#c9ccd1", 0.06, normal=(1, 0, 0), front_only=False)
    windows_row(sp, f["left"], 1, 0.45, 0.75, 0.35)
    for x, y in ((2.0, -1.9), (5.2, -1.9), (2.0, 1.9), (5.2, 1.9)):
        sp.line((x, y, 0), (x, y, 3.7), 0.07, "#8a9099")
    sp.quad((1.8, -2.1, 3.7), (3.6, 0, 0.3), (0, 4.2, 0), SOLAR, back=STEEL)
    sp.panel_grid((1.8, -2.1, 3.7), (3.6, 0, 0.3), (0, 4.2, 0), 4, 4, "#6f86b0", 0.45, 0.55)
    sp.lamp((4.8, 1.5, 2.2), AMBER, 9)


@variant("hab_module_covered", 1, 7.4)
def hab_tower_covered(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 4.8, 0.5)
    sp.ellipsoid((0, 0, 0.0), 4.3, 4.3, 6.0, BERM, clip_z=0.0)
    sandbag_rings(sp, (0, 0, 0.0), 4.3, 4.3, 6.0, (1.0, 2.0, 3.0, 4.0, 5.0))
    sp.dome((0, 0, 5.6), 1.5, 1.2, WHITE)
    sp.box(3.0, -0.9, 0, 2.2, 1.8, 2.2, WHITE)
    door(sp, Sprite.box_faces(3.0, -0.9, 0, 2.2, 1.8, 2.2)["right"], 0.25, 0.75, 0.8)


@variant("hab_module_covered", 2, 4.4)
def hab_twin_covered(sp: Sprite):
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.5)
    for y in (-1.9, 1.9):
        sp.ellipsoid((-0.6, y, 0.0), 4.4, 2.3, 3.8, BERM, clip_z=0.0)
        sandbag_rings(sp, (-0.6, y, 0.0), 4.4, 2.3, 3.8, (1.0, 2.0, 3.0))
    sp.sphere((3.6, 0, 1.6), 1.3, WHITE)
    sp.disc((4.7, 0, 1.6), (1, 0, 0), 0.6, DARK)
    sp.lamp((4.8, 0, 2.8), AMBER, 9)


@variant("hab_module_covered", 3, 4.0)
def hab_printed_covered(sp: Sprite):
    sp.contact_shadow(0, 0, 6.2, 4.2, 0.5)
    sp.tbox(-5.8, -3.6, 5.0, 3.6, 2.6, 3.3, BERM, top=Mat("#6e6862"))
    for i in range(3):
        sp.window([(2.2 - i * 2.2, 1.02, 3.3), (1.4 - i * 2.2, 1.02, 3.3), (1.4 - i * 2.2, 0.2, 3.42),
                   (2.2 - i * 2.2, 0.2, 3.42)])
    sp.box(5.0, -1.0, 0, 1.6, 2.0, 2.3, CONCRETE)
    door(sp, Sprite.box_faces(5.0, -1.0, 0, 1.6, 2.0, 2.3)["right"], 0.25, 0.75, 0.78)


@variant("hab_module_covered", 4, 4.6)
def hab_porch_covered(sp: Sprite):
    sp.contact_shadow(-0.6, 0, 6.0, 3.8, 0.5)
    sp.ellipsoid((-1.4, 0, 0.0), 4.4, 3.3, 4.2, BERM, clip_z=0.0)
    sandbag_rings(sp, (-1.4, 0, 0.0), 4.4, 3.3, 4.2, (1.0, 2.0, 3.0))
    sp.box(1.9, -1.7, 0, 2.8, 3.4, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(1.9, -1.7, 0, 2.8, 3.4, 2.4)
    door(sp, f["right"], 0.35, 0.65, 0.75)
    for x, y in ((2.0, -1.9), (5.2, -1.9), (2.0, 1.9), (5.2, 1.9)):
        sp.line((x, y, 0), (x, y, 3.7), 0.07, "#8a9099")
    sp.quad((1.8, -2.1, 3.7), (3.6, 0, 0.3), (0, 4.2, 0), SOLAR, back=STEEL)


@variant("regolith_dome", 1, 5.4)
def dome_oculus(sp: Sprite):
    """천창 고리가 있는 돔과 두 출입구."""
    sp.contact_shadow(0, 0, 7.0, 7.0, 0.5)
    sp.half_cyl((-0.6, 5.0, 0), (-0.6, 7.6, 0), 1.3, SINTER)
    sp.dome((0, 0, 0), 6.2, 5.0, SINTER)
    for zz in (0.8, 1.7, 2.6, 3.4, 4.1):
        k = math.sqrt(max(0.0, 1 - (zz / 5.0) ** 2))
        sp.ring3((0, 0, zz), 6.2 * k, "#83745f", 0.045, opacity=0.8)
    sp.disc((0, 0, 4.86), (0, 0, 1), 1.6, GLASS, edge=False)
    sp.ring3((0, 0, 4.88), 1.6, "#cfc6b6", 0.12, front_only=False)
    sp.poly2([PV((1.6 * math.cos(t / 20 * 2 * math.pi), 1.6 * math.sin(t / 20 * 2 * math.pi), 4.88)) for t in range(20)],
             WARM_WINDOW, None, 0, 0.8, layer="light")
    sp.glow((0, 0, 5.5), 30, WARM_WINDOW, 0.35)
    sp.half_cyl((5.2, 0, 0), (7.4, 0, 0), 1.3, SINTER, bands=[0.5], band_color="#83745f")
    sp.face([(7.45, -0.5, 0), (7.45, 0.5, 0), (7.45, 0.5, 1.0), (7.45, -0.5, 1.0)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((7.5, 0.9, 1.5), AMBER, 10)


@variant("regolith_dome", 2, 4.4)
def dome_twin(sp: Sprite):
    """작은 돔 두 개를 터널로 잇는다."""
    sp.contact_shadow(0, 0, 7.2, 6.4, 0.5)
    sp.dome((-3.0, -2.2, 0), 4.0, 3.5, SINTER)
    for zz in (0.8, 1.6, 2.4, 3.0):
        k = math.sqrt(max(0.0, 1 - (zz / 3.5) ** 2))
        sp.ring3((-3.0, -2.2, zz), 4.0 * k, "#83745f", 0.045, opacity=0.8)
    sp.half_cyl((-0.8, 0.0, 0), (1.6, 1.6, 0), 1.2, SINTER)
    sp.dome((3.0, 2.2, 0), 4.4, 4.0, SINTER)
    for zz in (0.8, 1.6, 2.4, 3.2):
        k = math.sqrt(max(0.0, 1 - (zz / 4.0) ** 2))
        sp.ring3((3.0, 2.2, zz), 4.4 * k, "#83745f", 0.045, opacity=0.8)
    for c in ((-1.8, -0.4, 2.0), (4.6, 4.2, 2.2)):
        n = norm((c[0] - (-3.0 if c[0] < 0 else 3.0), c[1] - (-2.2 if c[0] < 0 else 2.2), 0.6))
        u, v = basis(n)
        pts = [add(c, add(mul(u, 0.4 * math.cos(2 * math.pi * i / 12)), mul(v, 0.4 * math.sin(2 * math.pi * i / 12))))
               for i in range(12)]
        sp.window(pts, frame="#5f5446")
    sp.half_cyl((7.0, 1.6, 0), (8.4, 1.6, 0), 1.1, SINTER)
    sp.face([(8.45, 1.15, 0), (8.45, 2.05, 0), (8.45, 2.05, 0.9), (8.45, 1.15, 0.9)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((8.5, 2.6, 1.3), AMBER, 9)


@variant("regolith_dome", 3, 4.6)
def dome_vault(sp: Sprite):
    """긴 아치형 볼트 — 레골리스로 찍은 터널 거주동."""
    sp.contact_shadow(0, 0, 7.0, 4.8, 0.5)
    sp.half_cyl((-6.2, 0, 0), (5.6, 0, 0), 4.3, SINTER, bands=[0.12, 0.25, 0.37, 0.5, 0.62, 0.75, 0.87],
                band_color="#83745f", cap_mat=CONCRETE)
    sp.face([(5.65, -1.0, 0), (5.65, 1.0, 0), (5.65, 1.0, 2.2), (5.65, -1.0, 2.2)], DARK, normal=(1, 0, 0), ao=0)
    for y in (-2.4, 2.4):
        sp.window([(5.66, y - 0.5, 2.0), (5.66, y + 0.5, 2.0), (5.66, y + 0.5, 2.8), (5.66, y - 0.5, 2.8)])
    sp.lamp((5.8, 1.4, 2.6), AMBER, 10)
    sp.lamp((5.8, -1.4, 2.6), AMBER, 10)


@variant("regolith_dome", 4, 5.6)
def dome_ribbed(sp: Sprite):
    """바깥 갈비대로 보강한 돔."""
    sp.contact_shadow(0, 0, 7.2, 7.2, 0.5)
    sp.dome((0, 0, 0), 6.4, 5.2, Mat("#A89A84"))
    for i in range(12):
        th = 2 * math.pi * i / 12
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.15:
            continue
        pts = [(6.45 * math.cos(ph) * math.cos(th), 6.45 * math.cos(ph) * math.sin(th), 5.25 * math.sin(ph))
               for ph in [k * math.pi / 2 / 10 for k in range(11)]]
        sp.polyline3(pts, "#6f6252", 0.22, 0.95)
    for i in range(10):
        t = 2 * math.pi * i / 10
        if dot((math.cos(t), math.sin(t), 0), VIEW) > 0:
            sp.lamp((6.6 * math.cos(t), 6.6 * math.sin(t), 0.2), AMBER, 8)
    sp.half_cyl((5.6, 0, 0), (7.8, 0, 0), 1.4, Mat("#A89A84"))
    sp.face([(7.85, -0.55, 0), (7.85, 0.55, 0), (7.85, 0.55, 1.1), (7.85, -0.55, 1.1)], DARK, normal=(1, 0, 0), ao=0)


# ── 생명유지 ─────────────────────────────────────────────────────────

@variant("electrolyzer", 1, 3.4)
def electrolyzer_container(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    for x, mat in ((-1.6, WHITE), (0.6, WHITE)):
        sp.sphere((x, -1.2, 1.3), 0.95, mat)
        sp.ring3((x, -1.2, 1.3), 0.95, "#3FB8AF" if x < 0 else "#d8853b", 0.12)
        legs(sp, [(x - 0.5, -1.7, 0.6), (x + 0.5, -1.7, 0.6), (x, -0.6, 0.6)], 0.0)
    sp.box(-3.0, 0.0, 0, 6.0, 2.0, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.0, 0.0, 0, 6.0, 2.0, 2.4)
    band_on(sp, f["left"], 0.1, 0.2, TEAL)
    o, e1, e2 = f["left"]
    for i in range(6):
        u = 0.06 + i * 0.15
        sp.face(sp.on_face(o, e1, e2, u, 0.35, u + 0.1, 0.85), Mat("#d9d4c8"), normal=(0, 1, 0), ao=0)
    sp.lamp((3.05, 1.0, 2.0), CYAN_LIGHT, 7)


@variant("electrolyzer", 2, 3.0)
def electrolyzer_horizontal(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for y, band in ((-1.0, "#3FB8AF"), (0.4, "#d8853b")):
        for x in (-2.2, 0.4):
            sp.box(x - 0.2, y - 0.5, 0.35, 0.4, 1.0, 0.6, STEEL)
        sp.cyl((-2.8, y, 1.4), (1.0, y, 1.4), 0.62, WHITE, cap_mat=WHITE)
        sp.ring3((0.6, y, 1.4), 0.63, band, 0.16, normal=(1, 0, 0))
    sp.box(1.4, -1.6, 0.35, 1.5, 3.2, 1.9, Mat("#5B6470", 0.2), top=SILVER)
    o, e1, e2 = Sprite.box_faces(1.4, -1.6, 0.35, 1.5, 3.2, 1.9)["right"]
    for i in range(6):
        u = 0.1 + i * 0.14
        sp.face(sp.on_face(o, e1, e2, u, 0.15, u + 0.06, 0.85), CHAR, normal=(1, 0, 0), ao=0, edge=False)
    pipe(sp, [(1.0, -1.0, 1.4), (1.4, -1.0, 1.4)])
    sp.lamp((2.95, 1.5, 2.0), CYAN_LIGHT, 7)


@variant("electrolyzer", 3, 4.8)
def electrolyzer_stack(sp: Sprite):
    sp.contact_shadow(0, 0, 3.4, 2.6)
    skid(sp, -3, -2, 6, 4)
    sp.cyl((-1.9, -1.0, 0.35), (-1.9, -1.0, 4.4), 0.7, WHITE, bands=[0.25, 0.5, 0.75])
    sp.sphere((-1.9, -1.0, 4.4), 0.7, WHITE)
    cyl_ring(sp, (-1.9, -1.0, 0.35), (-1.9, -1.0, 4.4), 0.7, 0.6, 0.66, TEAL)
    for (x, y, z, m) in ((-0.6, -0.8, 0.35, WHITE), (0.9, -0.8, 0.35, Mat("#C9CED4", 0.3)), (-0.6, 0.7, 0.35, TEAL),
                         (0.15, -0.05, 1.7, WHITE)):
        sp.box(x, y, z, 1.4, 1.4, 1.3, m, top=SILVER if m is not TEAL else Mat("#5fc7bf"))
    pipe(sp, [(-1.9, -0.3, 2.4), (-0.6, -0.3, 2.4)])
    sp.lamp((2.4, 0.8, 1.2), CYAN_LIGHT, 7)


@variant("electrolyzer", 4, 3.2)
def electrolyzer_open(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for x, y in ((-2.7, -1.5), (1.3, -1.5), (-2.7, 0.5), (1.3, 0.5)):
        sp.line((x, y, 0.35), (x, y, 2.4), 0.08, "#8a9099")
    sp.polyline3([(-2.7, -1.5, 2.4), (1.3, -1.5, 2.4), (1.3, 0.5, 2.4), (-2.7, 0.5, 2.4), (-2.7, -1.5, 2.4)], "#8a9099", 0.08)
    for i in range(9):
        x = -2.4 + i * 0.42
        sp.quad((x, -1.3, 0.6), (0.0, 1.6, 0.0), (0.0, 0.0, 1.5), Mat("#D9D4C8", 0.2), back=Mat("#B9B3A6"))
    sp.box(-2.7, -1.5, 0.35, 4.0, 2.0, 0.2, STEEL)
    for y in (-1.2, 0.3):
        sp.sphere((2.4, y, 1.0), 0.6, WHITE)
    sp.lamp((1.4, 0.6, 2.6), CYAN_LIGHT, 7)


@variant("co2_scrubber", 1, 4.4)
def scrubber_tower(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.6)
    skid(sp, -2.5, -2, 5, 4)
    p0, p1 = (-0.8, -0.4, 0.35), (-0.8, -0.4, 4.0)
    sp.cyl(p0, p1, 1.15, WHITE, bands=[0.15, 0.3, 0.45, 0.6, 0.75, 0.9], band_color="#8a8f96", cap_mat=STEEL)
    sp.cyl((-0.8, -0.4, 4.0), (-0.8, -0.4, 4.4), 0.6, CHAR)
    cyl_ring(sp, p0, p1, 1.15, 0.03, 0.09, TEAL, CYAN_LIGHT, 0.6)
    sp.box(0.6, 0.2, 0.35, 1.6, 1.5, 1.3, WHITE, top=SILVER)
    pipe(sp, [(0.35, 0.2, 1.2), (0.6, 0.6, 1.2)])
    sp.lamp((2.25, 1.0, 1.2), CYAN_LIGHT, 7)


@variant("co2_scrubber", 2, 3.2)
def scrubber_twin(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.6)
    skid(sp, -2.5, -2, 5, 4)
    for x in (-1.5, 1.3):
        p0, p1 = (x, -0.6, 0.35), (x, -0.6, 3.1)
        sp.cyl(p0, p1, 0.75, Mat("#C9CED4", 0.35), bands=[0.33, 0.66], cap_mat=STEEL)
        sp.sphere((x, -0.6, 3.1), 0.75, Mat("#C9CED4", 0.35), clip_z=3.1)
    sp.box(-0.6, 0.1, 0.35, 1.2, 1.6, 1.7, WHITE, top=SILVER)
    sp.cyl((0.0, 0.9, 2.05), (0.0, 0.9, 2.3), 0.5, STEEL, cap_mat=CHAR)
    pipe(sp, [(-1.5, 0.1, 2.2), (-0.6, 0.6, 1.6)])
    pipe(sp, [(1.3, 0.1, 2.2), (0.6, 0.6, 1.6)])
    band_on(sp, Sprite.box_faces(-0.6, 0.1, 0.35, 1.2, 1.6, 1.7)["left"], 0.8, 0.9, TEAL)
    sp.lamp((0.7, 1.8, 1.4), CYAN_LIGHT, 7)


@variant("co2_scrubber", 3, 2.4)
def scrubber_rack(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2, 5, 4)
    sp.box(-2.3, -1.4, 0.35, 4.6, 2.8, 1.5, WHITE, top=SILVER)
    f = Sprite.box_faces(-2.3, -1.4, 0.35, 4.6, 2.8, 1.5)
    band_on(sp, f["left"], 0.75, 0.88, TEAL)
    for i in range(4):
        cx = -1.7 + i * 1.15
        sp.cyl((cx, 0, 1.85), (cx, 0, 2.15), 0.48, STEEL, cap_mat=CHAR)
        sp.line((cx - 0.35, 0, 2.17), (cx + 0.35, 0, 2.17), 0.05, "#9aa1aa")
    o, e1, e2 = f["left"]
    for i in range(10):
        u = 0.05 + i * 0.093
        sp.face(sp.on_face(o, e1, e2, u, 0.18, u + 0.05, 0.62), DARK, normal=(0, 1, 0), edge=False, ao=0)
    sp.lamp((2.35, 1.3, 1.2), CYAN_LIGHT, 7)


@variant("co2_scrubber", 4, 3.0)
def scrubber_drum(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.6)
    skid(sp, -2.5, -2, 5, 4)
    for y in (-1.3, 1.3):
        sp.box(-0.4, y - 0.15, 0.35, 0.8, 0.3, 1.2, STEEL)
    sp.cyl((0, -1.5, 1.55), (0, 1.5, 1.55), 1.15, Mat("#C9CED4", 0.4), bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
    sp.ring3((0, 1.52, 1.55), 0.8, "#3FB8AF", 0.12, normal=(0, 1, 0), front_only=False)
    sp.box(1.4, -1.6, 0.35, 0.9, 1.4, 1.6, WHITE)
    pipe(sp, [(1.4, -1.0, 1.6), (1.1, -1.0, 1.6)], 0.3)
    pipe(sp, [(-1.15, 0.0, 2.2), (-2.0, 0.0, 2.2), (-2.0, 0.0, 0.4)], 0.3)
    sp.lamp((2.35, -0.3, 1.5), CYAN_LIGHT, 7)


@variant("sabatier", 1, 4.6)
def sabatier_column(sp: Sprite):
    sp.contact_shadow(0, 0, 3.4, 2.6)
    skid(sp, -3, -2, 6, 4)
    o, e1, e2 = (-2.7, -1.7, 0.35), (2.0, 0, 0), (0, 0, 2.6)
    sp.quad(o, e1, e2, RADIATOR)
    sp.panel_grid(o, e1, e2, 5, 1, "#b7bcc2", 0.5, 0.8)
    sp.cyl((0.2, -0.6, 0.35), (0.2, -0.6, 4.2), 0.7, SILVER, bands=[0.2, 0.4, 0.6, 0.8], cap_mat=STEEL)
    sp.sphere((-1.6, 1.0, 1.3), 1.0, WHITE)
    sp.ring3((-1.6, 1.0, 1.3), 1.0, "#c9a75a", 0.08)
    legs(sp, [(-2.2, 1.5, 0.6), (-1.0, 1.5, 0.6), (-1.6, 0.4, 0.6)], 0.35)
    pipe(sp, [(-0.5, 0.2, 1.2), (-0.5, -0.4, 1.2), (-0.5, -0.6, 2.0)])
    sp.box(1.2, 0.4, 0.35, 1.4, 1.2, 1.1, WHITE)
    sp.lamp((0.2, -0.6, 4.4), AMBER, 6)


@variant("sabatier", 2, 3.2)
def sabatier_twin(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for y in (-0.9, 0.9):
        for x in (-1.8, 1.6):
            sp.box(x - 0.2, y - 0.45, 0.35, 0.4, 0.9, 0.6, STEEL)
        sp.cyl((-2.6, y, 1.4), (2.4, y, 1.4), 0.68, SILVER, bands=[0.15, 0.85], cap_mat=STEEL)
    pipe(sp, [(2.4, -0.9, 1.4), (2.8, -0.9, 1.4), (2.8, 0.9, 1.4), (2.4, 0.9, 1.4)], 0.22)
    pipe(sp, [(2.8, 0.0, 1.4), (2.8, 0.0, 2.6)], 0.22)
    sp.lamp((2.9, 0.0, 2.8), AMBER, 7)


@variant("sabatier", 3, 3.8)
def sabatier_box(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    sp.box(-1.6, -1.2, 0.35, 3.2, 2.4, 1.8, WHITE, top=SILVER)
    f = Sprite.box_faces(-1.6, -1.2, 0.35, 3.2, 2.4, 1.8)
    band_on(sp, f["left"], 0.8, 0.9, Mat("#c9a75a"))
    sp.window(sp.on_face(*f["right"], 0.3, 0.4, 0.7, 0.7), "#ffb37a")
    for side in (-1, 1):
        o = (-1.4, side * 1.25, 2.15)
        sp.quad(o, (2.8, 0, 0), (0, side * 1.5, 1.6), RADIATOR, back=RADIATOR)
        sp.panel_grid(o, (2.8, 0, 0), (0, side * 1.5, 1.6), 5, 1, "#b7bcc2", 0.5, 0.8)
    sp.lamp((1.7, 1.25, 1.6), AMBER, 7)


@variant("sabatier", 4, 5.0)
def sabatier_tank(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    sp.cyl((-1.8, -0.8, 0.35), (-1.8, -0.8, 4.6), 0.85, WHITE, bands=[0.5])
    sp.sphere((-1.8, -0.8, 4.6), 0.85, WHITE, clip_z=4.6)
    cyl_ring(sp, (-1.8, -0.8, 0.35), (-1.8, -0.8, 4.6), 0.85, 0.7, 0.77, ORANGE)
    sp.box(-0.2, -0.6, 0.35, 0.4, 1.2, 0.8, STEEL)
    sp.box(2.0, -0.6, 0.35, 0.4, 1.2, 0.8, STEEL)
    sp.cyl((-0.6, 0.0, 1.6), (2.8, 0.0, 1.6), 0.75, SILVER, cap_mat=STEEL)
    pipe(sp, [(-1.0, 0.0, 1.6), (-1.0, -0.8, 2.6)])
    sp.lamp((2.9, 0.0, 2.6), AMBER, 7)


@variant("water_recycler", 1, 5.2)
def recycler_columns(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for x, h, r in ((-2.1, 4.8, 0.45), (-1.0, 3.8, 0.4)):
        sp.cyl((x, -1.1, 0.35), (x, -1.1, h), r, SILVER, bands=[0.33, 0.66])
        sp.sphere((x, -1.1, h), r, SILVER)
    sp.box(0.0, -1.6, 0.35, 2.8, 2.2, 2.0, WHITE, top=SILVER)
    f = Sprite.box_faces(0.0, -1.6, 0.35, 2.8, 2.2, 2.0)
    band_on(sp, f["left"], 0.8, 0.9, BLUE)
    sp.cyl((-1.6, 1.1, 0.35), (-1.6, 1.1, 1.8), 0.7, WHITE, bands=[0.5])
    pipe(sp, [(-2.1, -0.6, 3.0), (-1.0, -0.6, 3.0)])
    pipe(sp, [(-1.0, -0.6, 2.4), (0.0, -0.6, 2.0)])
    sp.lamp((2.85, 0.5, 1.6), "#7fb6ff", 7)


@variant("water_recycler", 2, 3.0)
def recycler_drum(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for x in (-2.0, 0.8):
        sp.box(x - 0.2, -1.4, 0.35, 0.4, 1.4, 0.8, STEEL)
    sp.cyl((-2.8, -0.7, 1.7), (1.6, -0.7, 1.7), 1.0, Mat("#C9CED4", 0.4), bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
    sp.box(1.4, 0.2, 0.35, 1.4, 1.6, 1.6, WHITE, top=SILVER)
    sp.box(-2.6, 0.8, 0.35, 2.4, 1.0, 1.0, Mat("#3E6FB0", 0.2))
    pipe(sp, [(1.6, -0.7, 1.7), (2.1, -0.7, 1.7), (2.1, 0.2, 1.7)])
    sp.lamp((2.85, 1.0, 1.6), "#7fb6ff", 7)


@variant("water_recycler", 3, 3.6)
def recycler_tank(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    p0, p1 = (-1.1, -0.3, 0.35), (-1.1, -0.3, 3.2)
    sp.cyl(p0, p1, 1.6, WHITE, bands=[0.35], cap_mat=SILVER)
    cyl_ring(sp, p0, p1, 1.6, 0.55, 0.68, BLUE)
    sp.box(1.0, -1.4, 0.35, 1.7, 2.8, 1.4, Mat("#5B6470", 0.2), top=SILVER)
    o, e1, e2 = Sprite.box_faces(1.0, -1.4, 0.35, 1.7, 2.8, 1.4)["right"]
    for i in range(4):
        u = 0.12 + i * 0.2
        sp.face(sp.on_face(o, e1, e2, u, 0.2, u + 0.1, 0.8), Mat("#3E6FB0", 0.3), normal=(1, 0, 0), ao=0, edge=False)
    pipe(sp, [(0.5, -0.3, 1.2), (1.0, -0.3, 1.2)])
    sp.lamp((2.75, 1.3, 1.4), "#7fb6ff", 7)


@variant("water_recycler", 4, 2.8)
def recycler_membrane(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    sp.box(-2.6, -1.2, 0.35, 3.6, 1.6, 2.2, WHITE, top=SILVER)
    f = Sprite.box_faces(-2.6, -1.2, 0.35, 3.6, 1.6, 2.2)
    sp.panel_grid(*f["left"], 8, 4, "#8e959e", 0.6, 0.8)
    band_on(sp, f["left"], 0.88, 0.95, BLUE)
    for x in (1.6, 2.4):
        sp.cyl((x, -0.4, 0.35), (x, -0.4, 1.9), 0.35, WHITE)
        sp.sphere((x, -0.4, 1.9), 0.35, WHITE)
    sp.cyl((1.9, 1.2, 0.35), (1.9, 1.2, 1.2), 0.6, Mat("#3E6FB0", 0.3))
    sp.lamp((1.1, 0.5, 1.6), "#7fb6ff", 7)


@variant("tank_farm", 1, 3.4)
def tanks_horizontal(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 3.6)
    sp.box(-4, -3, 0, 8, 6, 0.3, SINTER)
    items = []
    for y, m in ((-2.0, WHITE), (0.0, ORANGE), (2.0, WHITE)):
        def tank(y=y, m=m):
            for x in (-2.4, 2.0):
                sp.box(x - 0.25, y - 0.6, 0.3, 0.5, 1.2, 0.7, STEEL)
            sp.cyl((-3.4, y, 1.75), (3.0, y, 1.75), 0.85, m, cap_mat=m, bands=[0.5],
                   band_color="#a29a8c" if m is WHITE else "#9a4f22")
        items.append(((0, y, 1.7), tank))
    sp.parts(items)
    pipe(sp, [(3.0, -2.0, 1.2), (3.6, -2.0, 1.2), (3.6, 2.0, 1.2), (3.0, 2.0, 1.2)])
    sp.lamp((3.9, 2.9, 1.2), AMBER, 8)


@variant("tank_farm", 2, 5.4)
def tanks_tall(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 3.6)
    sp.box(-4, -3, 0, 8, 6, 0.3, SINTER)
    for x, y in ((-2.2, -1.4), (0.6, -1.8)):
        sp.cyl((x, y, 0.3), (x, y, 4.6), 1.05, WHITE, bands=[0.33, 0.66])
        sp.sphere((x, y, 4.6), 1.05, WHITE, clip_z=4.6)
    for x, y in ((-1.4, 1.8), (1.8, 1.4)):
        legs(sp, [(x - 0.6, y - 0.6, 1.3), (x + 0.6, y - 0.6, 1.3), (x - 0.6, y + 0.6, 1.3), (x + 0.6, y + 0.6, 1.3)], 0.3)
        sp.sphere((x, y, 1.9), 1.15, ORANGE if x < 0 else WHITE)
    pipe(sp, [(-2.2, -0.4, 0.6), (1.8, 0.3, 0.6)])
    sp.lamp((3.9, 2.9, 1.2), AMBER, 8)


@variant("tank_farm", 3, 3.0)
def tanks_rack(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 3.6)
    sp.box(-4, -3, 0, 8, 6, 0.3, SINTER)
    for row, y in enumerate((-1.4, 1.4)):
        sp.box(-3.4, y - 0.9, 0.3, 6.8, 1.8, 0.6, STEEL)
        for i in range(3):
            x = -2.3 + i * 2.3
            sp.sphere((x, y, 1.75), 0.85, WHITE if (i + row) % 2 == 0 else Mat("#D9893F", 0.1))
    sp.lamp((3.9, 2.9, 1.2), AMBER, 8)


@variant("tank_farm", 4, 5.0)
def tanks_big(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 3.6)
    sp.box(-4, -3, 0, 8, 6, 0.3, SINTER)
    legs(sp, [(-2.4, -2.0, 1.6), (0.4, -2.0, 1.6), (-2.4, 0.8, 1.6), (0.4, 0.8, 1.6)], 0.3)
    sp.sphere((-1.0, -0.6, 2.6), 2.2, WHITE)
    sp.ring3((-1.0, -0.6, 2.6), 2.2, "#a29a8c", 0.08)
    sp.sphere((2.4, 1.8, 1.3), 1.0, ORANGE)
    pipe(sp, [(1.1, -0.2, 0.6), (2.4, 1.0, 0.6)])
    sp.lamp((3.9, 2.9, 1.2), AMBER, 8)


# ── 식량 ─────────────────────────────────────────────────────────────

@variant("hydroponics", 1, 3.4)
def farm_sawtooth(sp: Sprite):
    """유리 톱니 지붕의 상자형 온실."""
    sp.contact_shadow(0, 0, 5.0, 3.0)
    sp.box(-4.4, -2.2, 0, 8.8, 4.4, 2.2, WHITE, top=SILVER)
    for i in range(3):
        x = -4.2 + i * 2.85
        pts = [(x, -2.1, 2.2), (x + 2.6, -2.1, 2.2), (x + 2.6, 2.1, 3.2), (x, 2.1, 3.2)]
        sp.face([(x, -2.1, 2.2), (x + 2.6, -2.1, 2.2), (x + 2.6, 2.1, 3.2), (x, 2.1, 3.2)], PINK_GLASS, ao=0)
        for k in range(3):
            yy = -1.4 + k * 1.4
            zz = 2.2 + (yy + 2.1) / 4.2 * 1.0
            a, b = PV((x + 0.2, yy, zz + 0.02)), PV((x + 2.4, yy, zz + 0.02))
            sp.path2("M%.2f,%.2fL%.2f,%.2f" % (a[0], a[1], b[0], b[1]), "none", "#6DAE57", 1.2)
        sp.poly2([PV(p) for p in pts], GROW, None, 0, 0.85, layer="light")
        sp.face([(x + 2.6, 2.1, 2.2), (x, 2.1, 2.2), (x, 2.1, 3.2), (x + 2.6, 2.1, 3.2)], WHITE, ao=0)
    f = Sprite.box_faces(-4.4, -2.2, 0, 8.8, 4.4, 2.2)
    door(sp, f["right"], 0.35, 0.65, 0.8)
    sp.glow((0, 0, 3.0), 34, GROW, 0.35)


@variant("hydroponics", 2, 6.2)
def farm_tower(sp: Sprite):
    """수직 농장 — 원통형 3층."""
    sp.contact_shadow(0, 0, 3.4, 3.4)
    p0, p1 = (0, 0, 0), (0, 0, 5.4)
    sp.cyl(p0, p1, 2.3, WHITE, bands=[0.33, 0.66], band_color="#b8b2a6", cap_mat=SILVER)
    for s0 in (0.08, 0.41, 0.74):
        cyl_windows(sp, p0, p1, 2.3, s0, s0 + 0.18, n=4, spread=24, width=16, glow=GROW, glass=PINK_GLASS)
    sp.cyl((0, 0, 5.4), (0, 0, 6.1), 0.9, STEEL)
    sp.box(2.0, -0.8, 0, 1.8, 1.6, 2.1, WHITE)
    door(sp, Sprite.box_faces(2.0, -0.8, 0, 1.8, 1.6, 2.1)["right"], 0.25, 0.75, 0.8)
    sp.glow((0, 0, 3.0), 34, GROW, 0.35)


@variant("hydroponics", 3, 2.6)
def farm_buried(sp: Sprite):
    """흙에 묻은 온실 — 위에 빛 파이프 돔이 셋."""
    sp.contact_shadow(0, 0, 5.2, 3.2, 0.5)
    sp.tbox(-4.6, -2.6, 4.6, 2.6, 1.0, 1.8, BERM, top=Mat("#6e6862"))
    for x in (-2.4, 0.0, 2.4):
        sp.sphere((x, 0.0, 1.8), 0.95, Mat("#cfe6f5", 0.8), clip_z=1.8)
        sp.ring3((x, 0.0, 1.82), 0.95, "#a7b4bd", 0.08, front_only=False)
        sp.glow((x, 0.0, 2.3), 16, GROW, 0.7)
    sp.box(4.2, -0.9, 0, 1.4, 1.8, 1.9, CONCRETE)
    door(sp, Sprite.box_faces(4.2, -0.9, 0, 1.4, 1.8, 1.9)["right"], 0.25, 0.75, 0.8)


@variant("hydroponics", 4, 2.8)
def farm_twin(sp: Sprite):
    """작은 반원통 온실 두 동."""
    sp.contact_shadow(0, 0, 5.0, 3.0)
    for y in (-1.35, 1.35):
        sp.box(-4.2, y - 1.25, 0, 8.4, 2.5, 0.6, SINTER)
        sp.half_cyl((-4.0, y, 0.6), (4.0, y, 0.6), 1.2, WHITE, bands=[0.25, 0.5, 0.75], band_color="#b8b2a6")
        pts = [(-3.6, y - 0.35, 1.76), (3.6, y - 0.35, 1.76), (3.6, y + 0.35, 1.76), (-3.6, y + 0.35, 1.76)]
        sp.face(pts, PINK_GLASS, normal=(0, 0, 1), ao=0)
        a, b = PV((-3.4, y, 1.78)), PV((3.4, y, 1.78))
        sp.path2("M%.2f,%.2fL%.2f,%.2f" % (a[0], a[1], b[0], b[1]), "none", "#6DAE57", 1.4)
        sp.poly2([PV(p) for p in pts], GROW, None, 0, 0.85, layer="light")
        sp.face([(4.05, y - 0.4, 0.6), (4.05, y + 0.4, 0.6), (4.05, y + 0.4, 1.5), (4.05, y - 0.4, 1.5)], DARK,
                normal=(1, 0, 0), ao=0)
    sp.lamp((4.3, 0.0, 1.6), AMBER, 8)
    sp.glow((0, 0, 2.0), 32, GROW, 0.3)


@variant("algae_reactor", 1, 3.0)
def algae_panels(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for i in range(5):
        x = -2.4 + i * 1.1
        sp.quad((x, -1.5, 0.45), (0.0, 3.0, 0.0), (0.0, 0.0, 2.3), Mat("#5fae4f", 0.7), back=ALGAE_DARK)
        sp.glow((x, 0.0, 1.6), 9, "#9BEA7A", 0.35)
    sp.box(2.4, -1.6, 0.35, 0.5, 3.2, 0.3, STEEL)
    sp.lamp((2.9, 1.8, 1.2), "#9BEA7A", 7)


@variant("algae_reactor", 2, 3.8)
def algae_coil(sp: Sprite):
    sp.contact_shadow(0, 0, 3.4, 2.6)
    skid(sp, -3, -2, 6, 4)
    c = (-0.8, -0.2, 0.35)
    sp.cyl(c, (c[0], c[1], 3.5), 1.4, Mat("#cfe6f5", 0.8), cap_mat=STEEL)
    pts = []
    for i in range(121):
        t = i / 120
        ang = t * 2 * math.pi * 6
        pts.append((c[0] + 1.42 * math.cos(ang), c[1] + 1.42 * math.sin(ang), c[2] + 0.2 + t * 2.8))
    run = []
    for p in pts:
        if dot((p[0] - c[0], p[1] - c[1], 0.0), VIEW) > 0:
            run.append(p)
        elif run:
            sp.polyline3(run, "#58A64A", 0.16)
            run = []
    if run:
        sp.polyline3(run, "#58A64A", 0.16)
    sp.glow((c[0], c[1], 1.8), 18, "#9BEA7A", 0.4)
    sp.box(1.2, 0.2, 0.35, 1.5, 1.4, 1.2, WHITE)
    sp.lamp((2.75, 1.5, 1.2), "#9BEA7A", 7)


@variant("algae_reactor", 3, 2.8)
def algae_racks(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 2.6)
    skid(sp, -3, -2, 6, 4)
    for x in (-2.7, 2.4):
        for y in (-1.6, 1.4):
            sp.line((x, y, 0.35), (x, y, 2.6), 0.08, "#8a9099")
    for k in range(4):
        z = 0.7 + k * 0.6
        for y in (-1.0, -0.3, 0.4, 1.1):
            sp.cyl((-2.6, y, z), (2.3, y, z), 0.13, ALGAE, edge=False, caps=False)
    sp.glow((0, 0, 1.6), 22, "#9BEA7A", 0.35)
    sp.lamp((2.5, 1.5, 2.7), "#9BEA7A", 7)


@variant("algae_reactor", 4, 3.6)
def algae_tank(sp: Sprite):
    sp.contact_shadow(0, 0, 3.4, 2.6)
    skid(sp, -3, -2, 6, 4)
    p0, p1 = (-0.9, -0.3, 0.35), (-0.9, -0.3, 3.2)
    sp.cyl(p0, p1, 1.5, Mat("#4f9a42", 0.8), bands=[0.33, 0.66], band_color="#2f6a28", cap_mat=STEEL)
    sp.glow((-0.9, -0.3, 2.0), 22, "#9BEA7A", 0.45)
    sp.box(1.2, -1.2, 0.35, 1.4, 1.2, 1.1, WHITE)
    sp.box(1.2, 0.4, 0.35, 1.4, 1.2, 0.8, STEEL)
    pipe(sp, [(0.6, -0.6, 0.8), (1.2, -0.6, 0.8)])
    sp.lamp((2.65, 1.0, 1.0), "#9BEA7A", 7)


@variant("food_store", 1, 4.4)
def store_silos(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 3.0)
    sp.box(-3.5, -2.5, 0, 7.0, 5.0, 0.3, SINTER)
    for x, y in ((-1.8, -1.0), (0.6, -1.4)):
        sp.cyl((x, y, 0.3), (x, y, 3.9), 1.1, WHITE, bands=[0.33, 0.66])
        sp.frustum((x, y, 3.9), (x, y, 4.5), 1.1, 0.3, WHITE)
    o, e1, e2 = (1.0, 0.6, 0.3), (2.4, 0, 0), (0, 0, 1.6)
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, 5, 1, "#b7bcc2", 0.5, 0.8)
    sp.box(-2.6, 0.9, 0.3, 2.0, 1.4, 1.3, WHITE)
    door(sp, Sprite.box_faces(-2.6, 0.9, 0.3, 2.0, 1.4, 1.3)["left"], 0.3, 0.7, 0.8)


@variant("food_store", 2, 3.6)
def store_containers(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 3.0)
    sp.box(-3.5, -2.5, 0, 7.0, 5.0, 0.3, SINTER)
    for (x, y, z, m) in ((-3.0, -2.0, 0.3, WHITE), (-3.0, 0.2, 0.3, Mat("#3E6FB0", 0.2)), (0.2, -2.0, 0.3, WHITE),
                         (-3.0, -2.0, 1.85, Mat("#C9CED4", 0.3))):
        sp.box(x, y, z, 3.0, 2.0, 1.55, m)
    for x in (1.2, 2.3):
        sp.box(x - 0.4, 0.6, 0.3, 0.8, 1.2, 1.0, Mat("#5B6470", 0.2))
        sp.cyl((x, 1.2, 1.3), (x, 1.2, 1.45), 0.35, STEEL, cap_mat=CHAR)
    sp.lamp((3.3, 1.6, 1.4), "#7fe3da", 7)


@variant("food_store", 3, 3.6)
def store_rotunda(sp: Sprite):
    """원형 냉장 창고 — 원뿔 지붕과 둘레 방열 지느러미."""
    sp.contact_shadow(0, 0, 3.4, 3.4, 0.5)
    fins = []
    for k in range(10):
        a = 2 * math.pi * k / 10
        fins.append((dot((math.cos(a), math.sin(a), 0.0), VIEW), a))
    fins.sort()
    def fin(a):
        d = (math.cos(a), math.sin(a), 0.0)
        sp.quad(add((0, 0, 0.3), mul(d, 2.3)), mul(d, 0.9), (0, 0, 1.8), RADIATOR, back=RADIATOR)
    for _, a in fins[:5]:
        fin(a)
    sp.cyl((0, 0, 0), (0, 0, 2.4), 2.3, Mat("#E6EEF2", 0.3), bands=[0.5], band_color="#b5c6cf")
    sp.frustum((0, 0, 2.4), (0, 0, 3.5), 2.45, 0.4, WHITE)
    for _, a in fins[5:]:
        fin(a)
    sp.box(1.9, -0.7, 0, 1.0, 1.4, 1.8, CONCRETE)
    door(sp, Sprite.box_faces(1.9, -0.7, 0, 1.0, 1.4, 1.8)["right"], 0.2, 0.8, 0.8, STEEL)


@variant("food_store", 4, 3.0)
def store_dome(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 3.0)
    sp.box(-3.5, -2.5, 0, 7.0, 5.0, 0.3, SINTER)
    sp.dome((-0.8, -0.3, 0.3), 2.6, 2.4, WHITE)
    sp.ring3((-0.8, -0.3, 1.3), 2.35, "#c9c3b6", 0.05)
    sp.box(1.6, -1.0, 0.3, 1.4, 2.0, 1.6, WHITE, top=SILVER)
    door(sp, Sprite.box_faces(1.6, -1.0, 0.3, 1.4, 2.0, 1.6)["right"], 0.25, 0.75, 0.8)
    sp.quad((-2.8, 1.6, 0.3), (2.4, 0, 0), (0, 0, 1.5), RADIATOR, back=RADIATOR)


# ── 전력 ─────────────────────────────────────────────────────────────

def _tower_base(sp: Sprite):
    sp.contact_shadow(0, 0, 2.4, 2.4, 0.5)
    sp.box(-1.4, -1.4, 0, 2.8, 2.8, 0.6, SINTER)
    sp.box(-0.6, -0.6, 0.6, 1.2, 1.2, 0.8, STEEL)


def _panel(sp: Sprite, o, e1, e2, cols=4, rows=9):
    sp.quad(o, e1, e2, SOLAR, back=STEEL)
    sp.panel_grid(o, e1, e2, cols, rows, "#6f86b0", 0.55, 0.6)
    sp.polyline3([o, add(o, e1), add(add(o, e1), e2), add(o, e2), o], "#c0c6ce", 0.08)


@variant("solar_tower", 1, 21.0)
def tower_stacked(sp: Sprite):
    _tower_base(sp)
    sp.cyl((0, 0, 1.4), (0, 0, 20.2), 0.32, SILVER)
    _panel(sp, (2.9, -0.55, 4.6), (-5.8, 1.1, 0.0), (0.0, 0.0, 6.6), 4, 5)
    _panel(sp, (2.9, -0.55, 12.2), (-5.8, 1.1, 0.0), (0.0, 0.0, 6.6), 4, 5)
    sp.lamp((0, 0, 20.5), "#ff5a3c", 6)


@variant("solar_tower", 2, 20.0)
def tower_twin(sp: Sprite):
    _tower_base(sp)
    sp.cyl((0, 0, 1.4), (0, 0, 19.6), 0.32, SILVER)
    sp.line((3.3, -0.62, 13.0), (-3.3, 0.62, 13.0), 0.14, "#9aa1aa")
    _panel(sp, (3.6, -0.68, 6.4), (-3.0, 0.57, 0.0), (0.0, 0.0, 13.0), 2, 9)
    _panel(sp, (-0.6, 0.11, 6.4), (-3.0, 0.57, 0.0), (0.0, 0.0, 13.0), 2, 9)
    sp.lamp((0, 0, 19.9), "#ff5a3c", 6)


@variant("solar_tower", 3, 26.0)
def tower_tall(sp: Sprite):
    _tower_base(sp)
    sp.cyl((0, 0, 1.4), (0, 0, 25.4), 0.38, SILVER)
    for z in (6.0, 11.0, 16.0, 21.0):
        sp.ring3((0, 0, z), 0.4, "#7d848d", 0.06)
    _panel(sp, (2.2, -0.42, 9.0), (-4.4, 0.84, 0.0), (0.0, 0.0, 15.6), 3, 11)
    sp.lamp((0, 0, 25.8), "#ff5a3c", 6)


@variant("solar_tower", 4, 22.0)
def tower_truss(sp: Sprite):
    _tower_base(sp)
    sp.truss((0, 0, 1.4), (0, 0, 21.4), 1.1, "#a7adb5", 0.09, 14, side=(1, 0, 0))
    sp.truss((0, 0, 1.4), (0, 0, 21.4), 1.1, "#8f959d", 0.07, 14, side=(0, 1, 0))
    _panel(sp, (3.1, -0.6, 7.2), (-6.2, 1.18, 0.0), (0.0, 0.0, 13.0), 4, 9)
    sp.lamp((0, 0, 21.8), "#ff5a3c", 6)


@variant("fission_40kw", 1, 6.0)
def fission_buried(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 3.6, 0.5)
    sp.berm_ring((0.4, 0.4, 0), 1.2, 2.6, 1.4, front=False)
    sp.cyl((0.4, 0.4, 0), (0.4, 0.4, 1.8), 1.0, GOLD)
    sp.berm_ring((0.4, 0.4, 0), 1.2, 2.6, 1.4, front=True)
    for i in range(3):
        x = -2.4 + i * 1.6
        o, e1, e2 = (x, -2.4, 0.2), (1.3, 0, 0), (0, 0, 5.6)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 1, 5, "#b9bec4", 0.5, 0.7)
    pipe(sp, [(0.4, 0.4, 1.8), (0.4, -2.0, 1.8)], 0.2)
    sp.lamp((0.4, 0.4, 2.2), "#ff5a3c", 6)
    sp.glow((0.4, 0.4, 1.2), 14, "#ffb35c", 0.25)


@variant("fission_40kw", 2, 6.8)
def fission_umbrella(sp: Sprite):
    """세 다리 받침 위의 원자로와 원뿔형 방열판."""
    sp.contact_shadow(0, 0, 3.0, 3.0, 0.45)
    for k in range(3):
        a = math.radians(30 + k * 120)
        sp.line((1.0 * math.cos(a), 1.0 * math.sin(a), 1.6), (2.2 * math.cos(a), 2.2 * math.sin(a), 0.0), 0.12, "#8a9099")
    sp.cyl((0, 0, 0.6), (0, 0, 2.2), 0.8, GOLD, bands=[0.5])
    sp.cyl((0, 0, 2.2), (0, 0, 2.8), 0.55, SILVER)
    sp.frustum((0, 0, 2.8), (0, 0, 6.4), 0.5, 2.6, RADIATOR, cap_mat=Mat("#D5D8DB", 0.2),
               bands=[0.25, 0.5, 0.75], band_color="#b9bec4")
    sp.lamp((0, 0, 6.6), "#ff5a3c", 6)
    sp.glow((0, 0, 1.4), 14, "#ffb35c", 0.25)


@variant("fission_40kw", 3, 5.6)
def fission_twin(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 3.0, 0.5)
    sp.box(-2.8, -2.2, 0, 5.6, 4.4, 0.4, STEEL, top=DARK)
    sp.stripes((2.8, -2.2, 0.0), (0.0, 4.4, 0.0), (0, 0, 0.4), n=10)
    o, e1, e2 = (-2.6, -2.0, 0.4), (5.2, 0, 0), (0, 0, 5.0)
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, 8, 1, "#b9bec4", 0.5, 0.7)
    for x in (-1.2, 1.2):
        sp.cyl((x, 0.4, 0.4), (x, 0.4, 2.6), 0.8, GOLD, bands=[0.5])
        sp.cyl((x, 0.4, 2.6), (x, 0.4, 3.2), 0.5, SILVER)
    sp.lamp((0, 0.4, 3.6), "#ff5a3c", 6)


@variant("fission_40kw", 4, 6.4)
def fission_box(sp: Sprite):
    sp.contact_shadow(0, 0, 3.6, 3.2, 0.5)
    sp.box(-1.6, -0.6, 0, 3.2, 2.8, 2.4, Mat("#6B6F76", 0.2), top=DARK)
    sp.stripes((1.6, -0.6, 2.0), (0.0, 2.8, 0.0), (0, 0, 0.4), n=8, normal=(1, 0, 0))
    for i in range(5):
        x = -2.4 + i * 1.2
        o, e1, e2 = (x, -2.6, 0.3), (0, 1.6, 0), (0, 0, 6.0)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.lamp((0, 0.8, 2.8), "#ff5a3c", 6)


@variant("fission_1mw", 1, 7.0)
def mw_fan(sp: Sprite):
    """방열판을 변환동 둘레에 해바라기처럼 세운다."""
    sp.contact_shadow(0, 0, 8.0, 6.0, 0.5)
    sp.berm_ring((-4.8, 0, 0), 2.2, 4.2, 2.0, front=False)
    sp.cyl((-4.8, 0, 0), (-4.8, 0, 2.4), 1.8, DARK, cap_mat=STEEL)
    sp.cyl((-4.8, 0, 2.4), (-4.8, 0, 3.1), 1.0, GOLD)
    sp.berm_ring((-4.8, 0, 0), 2.2, 4.2, 2.0, front=True)
    hub = (3.0, 0.0)
    fins = []
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        fins.append((dot((math.cos(a), math.sin(a), 0.0), VIEW), a))
    fins.sort()
    def fin(a):
        d = (math.cos(a), math.sin(a), 0.0)
        sp.quad((hub[0] + 1.8 * d[0], hub[1] + 1.8 * d[1], 0.3), mul(d, 3.4), (0, 0, 6.2), RADIATOR, back=RADIATOR)
    for _, a in fins[:5]:
        fin(a)
    sp.cyl((hub[0], hub[1], 0), (hub[0], hub[1], 3.0), 1.7, WHITE, bands=[0.5], cap_mat=SILVER)
    for _, a in fins[5:]:
        fin(a)
    pipe(sp, [(-4.8, 0, 2.8), (1.3, 0, 2.2)], 0.3)
    sp.lamp((-4.8, 0, 3.5), "#ff5a3c", 7)
    sp.glow((-4.8, 0, 2.2), 24, "#ffb35c", 0.3)


@variant("fission_1mw", 2, 7.6)
def mw_dome(sp: Sprite):
    sp.contact_shadow(0, 0, 8.0, 6.0, 0.5)
    sp.dome((-4.2, 0, 0), 4.0, 3.6, BERM)
    sp.ring3((-4.2, 0, 1.2), 3.8, "#5f5953", 0.06)
    sp.ring3((-4.2, 0, 2.4), 3.0, "#5f5953", 0.06)
    sp.box(-0.6, -1.4, 0, 2.8, 2.8, 2.4, WHITE, top=SILVER)
    for row, y in enumerate((-4.4, -1.8, 0.8, 3.4)):
        for x in (3.0, 5.1):
            o = (x, y, 0.3)
            sp.quad(o, (1.9, 0, 0), (0, 0, 7.2), RADIATOR, back=RADIATOR)
            sp.panel_grid(o, (1.9, 0, 0), (0, 0, 7.2), 1, 6, "#c5c9cd", 0.5, 0.7)
    sp.lamp((-4.2, 0, 3.8), "#ff5a3c", 7)


@variant("fission_1mw", 3, 4.6)
def mw_racks(sp: Sprite):
    sp.contact_shadow(0, 0, 8.0, 6.0, 0.5)
    sp.berm_ring((-5.0, 0, 0), 2.4, 4.4, 2.0, front=False)
    sp.cyl((-5.0, 0, 0), (-5.0, 0, 2.4), 1.9, DARK, cap_mat=STEEL)
    sp.berm_ring((-5.0, 0, 0), 2.4, 4.4, 2.0, front=True)
    for row, y in enumerate((-4.6, -2.0, 0.6, 3.2)):
        for x in (0.0, 4.0):
            sp.line((x, y, 0), (x, y, 2.6), 0.1, "#8a9099")
            sp.line((x + 3.6, y, 0), (x + 3.6, y, 2.6), 0.1, "#8a9099")
            o = (x, y - 1.1, 2.3)
            sp.quad(o, (3.6, 0, 0), (0, 2.2, 0.6), RADIATOR, back=RADIATOR)
            sp.panel_grid(o, (3.6, 0, 0), (0, 2.2, 0.6), 6, 1, "#c5c9cd", 0.5, 0.7)
    pipe(sp, [(-5.0, 0, 2.6), (-0.4, 0, 2.6)], 0.3)
    sp.lamp((-5.0, 0, 3.0), "#ff5a3c", 7)


@variant("fission_1mw", 4, 6.8)
def mw_twin(sp: Sprite):
    sp.contact_shadow(0, 0, 8.0, 6.0, 0.5)
    for y in (-3.2, 3.2):
        sp.berm_ring((-4.4, y, 0), 1.6, 3.2, 1.8, front=False)
        sp.cyl((-4.4, y, 0), (-4.4, y, 2.2), 1.3, DARK, cap_mat=STEEL)
        sp.cyl((-4.4, y, 2.2), (-4.4, y, 2.9), 0.8, GOLD)
        sp.berm_ring((-4.4, y, 0), 1.6, 3.2, 1.8, front=True)
    sp.box(-1.2, -1.6, 0, 3.4, 3.2, 3.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-1.2, -1.6, 0, 3.4, 3.2, 3.0)
    windows_row(sp, f["left"], 2, 0.5, 0.75, 0.2, 0.1)
    for y in (-5.0, -2.2, 0.6, 3.4):
        o = (2.8, y, 0.3)
        sp.quad(o, (5.0, 0, 0), (0, 0, 6.6), RADIATOR, back=RADIATOR)
        sp.panel_grid(o, (5.0, 0, 0), (0, 0, 6.6), 8, 1, "#c5c9cd", 0.5, 0.7)
    pipe(sp, [(-4.4, -3.2, 2.6), (-1.2, -0.8, 2.6)], 0.25)
    pipe(sp, [(-4.4, 3.2, 2.6), (-1.2, 0.8, 2.6)], 0.25)
    sp.lamp((0.5, 0, 3.4), "#ff5a3c", 7)


@variant("battery_bank", 1, 2.6)
def battery_long(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.25, SINTER)
    for y in (-1.6, 0.3):
        sp.box(-3.2, y, 0.25, 6.4, 1.3, 1.6, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
        for i in range(8):
            x = -3.0 + i * 0.8
            sp.quad((x, y + 0.15, 1.85), (0, 1.0, 0), (0, 0, 0.5), RADIATOR, back=RADIATOR)
        o, e1, e2 = Sprite.box_faces(-3.2, y, 0.25, 6.4, 1.3, 1.6)["left"]
        sp.window(sp.on_face(o, e1, e2, 0.45, 0.7, 0.55, 0.85), "#7CF29A", frame=None, glass=Mat("#2c8f4f", 0.4))
    sp.lamp((3.4, 1.8, 1.0), "#7CF29A", 6)


@variant("battery_bank", 2, 2.4)
def battery_cubes(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.25, SINTER)
    for x in (-3.0, 0.2):
        for y in (-1.7, 0.1):
            sp.box(x, y, 0.25, 2.6, 1.6, 1.9, Mat("#4E5A66", 0.25), top=Mat("#6E7A86", 0.2))
            o, e1, e2 = Sprite.box_faces(x, y, 0.25, 2.6, 1.6, 1.9)["left"]
            sp.face(sp.on_face(o, e1, e2, 0.1, 0.25, 0.9, 0.35), Mat("#7CF29A", 0.2), normal=(0, 1, 0), ao=0, edge=False)
    sp.lamp((3.4, 1.8, 1.0), "#7CF29A", 6)


@variant("battery_bank", 3, 3.0)
def battery_hut(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.25, SINTER)
    sp.box(-3.2, -1.7, 0.25, 3.6, 3.4, 2.0, WHITE)
    sp.face([(-3.3, -1.8, 2.25), (0.5, -1.8, 2.25), (0.5, 1.8, 3.0), (-3.3, 1.8, 3.0)], SOLAR, ao=0)
    sp.panel_grid((-3.3, -1.8, 2.26), (3.8, 0, 0), (0, 3.6, 0.75), 4, 3, "#6f86b0", 0.45, 0.6)
    door(sp, Sprite.box_faces(-3.2, -1.7, 0.25, 3.6, 3.4, 2.0)["right"], 0.35, 0.65, 0.75)
    for y in (-1.5, 0.3):
        sp.box(1.2, y, 0.25, 1.8, 1.4, 1.5, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
    sp.lamp((3.1, 1.8, 1.0), "#7CF29A", 6)


@variant("battery_bank", 4, 3.4)
def battery_flywheels(sp: Sprite):
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.25, SINTER)
    for x in (-2.2, 0.0, 2.2):
        sp.cyl((x, -0.2, 0.25), (x, -0.2, 3.0), 0.9, Mat("#6E7A86", 0.3), bands=[0.2, 0.8], cap_mat=Mat("#8A949E", 0.3))
        sp.window(Sprite.cyl_patch((x, -0.2, 0.25), (x, -0.2, 3.0), 0.9, 0.55, 0.62, 30, 100), "#7CF29A",
                  frame=None, glass=Mat("#2c8f4f", 0.4))
    sp.lamp((3.3, 1.8, 0.9), "#7CF29A", 6)


@variant("rfc_unit", 1, 2.6)
def rfc_spheres(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2.0, 5, 4)
    for x, band in ((-1.3, "#d8853b"), (0.8, "#3FB8AF")):
        legs(sp, [(x - 0.5, -1.4, 0.8), (x + 0.5, -1.4, 0.8), (x, -0.4, 0.8)], 0.35)
        sp.sphere((x, -0.9, 1.45), 0.85, WHITE)
        sp.ring3((x, -0.9, 1.45), 0.85, band, 0.12)
    sp.box(-1.8, 0.6, 0.35, 3.6, 1.1, 1.3, Mat("#5B6470", 0.2), top=SILVER)
    windows_row(sp, Sprite.box_faces(-1.8, 0.6, 0.35, 3.6, 1.1, 1.3)["left"], 3, 0.5, 0.75, 0.1, 0.08, "#7fe3da")
    sp.lamp((2.0, 1.7, 1.0), "#7fe3da", 6)


@variant("rfc_unit", 2, 3.2)
def rfc_vertical(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2.0, 5, 4)
    for x, band in ((-1.6, "#d8853b"), (-0.2, "#3FB8AF")):
        sp.cyl((x, -0.8, 0.35), (x, -0.8, 2.7), 0.6, WHITE)
        sp.sphere((x, -0.8, 2.7), 0.6, WHITE, clip_z=2.7)
        sp.ring3((x, -0.8, 1.9), 0.61, band, 0.14)
    sp.box(0.8, -0.6, 0.35, 1.4, 1.8, 1.4, Mat("#5B6470", 0.2), top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(0.8, -0.6, 0.35, 1.4, 1.8, 1.4)["right"], 0.3, 0.45, 0.7, 0.75), "#7fe3da")
    sp.lamp((2.25, 1.0, 1.0), "#7fe3da", 6)


@variant("rfc_unit", 3, 2.8)
def rfc_topped(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2.0, 5, 4)
    sp.box(-2.0, -1.4, 0.35, 4.0, 2.8, 1.2, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
    f = Sprite.box_faces(-2.0, -1.4, 0.35, 4.0, 2.8, 1.2)
    windows_row(sp, f["left"], 4, 0.4, 0.7, 0.08, 0.06, "#7fe3da")
    for y in (-0.75, 0.75):
        sp.box(-1.4, y - 0.3, 1.55, 0.3, 0.6, 0.3, STEEL)
        sp.box(1.1, y - 0.3, 1.55, 0.3, 0.6, 0.3, STEEL)
        sp.cyl((-1.8, y, 2.2), (1.8, y, 2.2), 0.45, WHITE, cap_mat=WHITE)
    sp.lamp((2.05, 1.3, 0.9), "#7fe3da", 6)


@variant("rfc_unit", 4, 2.6)
def rfc_pyramid(sp: Sprite):
    sp.contact_shadow(0, 0, 3.0, 2.4)
    skid(sp, -2.5, -2.0, 5, 4)
    for y, z, band in ((-0.55, 0.85, "#d8853b"), (0.55, 0.85, "#3FB8AF"), (0.0, 1.8, "#3e6fb0")):
        sp.cyl((-2.0, y, z), (1.4, y, z), 0.5, WHITE, cap_mat=WHITE)
        sp.ring3((1.0, y, z), 0.51, band, 0.14, normal=(1, 0, 0))
    sp.box(1.6, -1.5, 0.35, 0.8, 3.0, 1.2, Mat("#5B6470", 0.2))
    sp.lamp((2.45, 0.0, 1.2), "#7fe3da", 6)


# ── 열 ───────────────────────────────────────────────────────────────

@variant("radiator", 1, 6.4)
def radiator_wide(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 1.8, 0.4)
    sp.box(-3.8, -0.6, 0, 7.6, 1.2, 0.4, STEEL)
    for x in (-3.6, 0.1):
        o, e1, e2 = (x, 0.0, 0.4), (3.5, 0, 0), (0, 0, 5.8)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 9, 1, "#b9bec4", 0.5, 0.7)
    pipe(sp, [(-3.6, 0.3, 0.6), (3.8, 0.3, 0.6)], 0.16)


@variant("radiator", 2, 7.4)
def radiator_narrow(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 1.8, 0.4)
    sp.box(-3.8, -0.6, 0, 7.6, 1.2, 0.4, STEEL)
    for i in range(5):
        x = -3.6 + i * 1.5
        o, e1, e2 = (x, 0.0, 0.4), (1.2, 0, 0), (0, 0, 6.8)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 3, 1, "#b9bec4", 0.5, 0.7)
    pipe(sp, [(-3.6, 0.3, 0.6), (3.8, 0.3, 0.6)], 0.16)


@variant("radiator", 3, 5.6)
def radiator_vee(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 2.0, 0.4)
    sp.box(-3.8, -0.4, 0, 7.6, 0.8, 0.5, STEEL)
    for side in (-1, 1):
        o = (-3.6, 0.0, 0.5)
        sp.quad(o, (7.2, 0, 0), (0, side * 1.4, 5.0), RADIATOR, back=RADIATOR)
        sp.panel_grid(o, (7.2, 0, 0), (0, side * 1.4, 5.0), 10, 1, "#b9bec4", 0.5, 0.7)


@variant("radiator", 4, 3.2)
def radiator_roof(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 1.8, 0.4)
    for x in (-3.4, 0.0, 3.4):
        for y in (-1.2, 1.2):
            sp.line((x, y, 0), (x, y, 2.4 + (y + 1.2) * 0.25), 0.08, "#8a9099")
    o = (-3.8, -1.4, 2.4)
    sp.quad(o, (7.6, 0, 0), (0, 2.8, 0.7), RADIATOR, back=RADIATOR)
    sp.panel_grid(o, (7.6, 0, 0), (0, 2.8, 0.7), 12, 2, "#b9bec4", 0.5, 0.7)
    pipe(sp, [(-3.6, 0.0, 0.5), (3.6, 0.0, 0.5)], 0.18)


# ── 산업 ─────────────────────────────────────────────────────────────

def _ice_floor(sp: Sprite, rx=5.6, ry=4.2):
    sp.ellipsoid((0, 0, 0), rx, ry, 0.18, Mat("#8E9AA3", 0.2), clip_z=0.0)
    for (x, y) in ((-3.8, -2.6), (2.2, 2.8), (-1.0, 3.4), (4.2, -2.2)):
        sp.ellipsoid((x, y, 0.0), 0.7, 0.5, 0.12, ICE, clip_z=0.0)


def _floodlights(sp: Sprite, pts):
    for p in pts:
        sp.line(p, add(p, (0, 0, 3.4)), 0.08, "#8a9099")
        sp.lamp(add(p, (0, 0, 3.5)), AMBER, 22)


@variant("ice_miner", 1, 4.0)
def ice_wheel(sp: Sprite):
    """버킷 휠 굴착차가 얼음 섞인 흙을 퍼서 호퍼에 붓는다."""
    sp.contact_shadow(0, 0, 6.4, 4.8, 0.5)
    _ice_floor(sp)
    sp.cyl((-2.4, -2.2, 0), (-2.4, -2.2, 2.6), 1.2, WHITE, bands=[0.5])
    sp.frustum((-2.4, -2.2, 2.6), (-2.4, -2.2, 3.4), 1.2, 0.5, STEEL)
    for x in (-0.6, 1.6):
        for y in (-0.2, 1.8):
            sp.cyl((x, y - 0.25, 0.5), (x, y + 0.25, 0.5), 0.5, Mat("#3B3F46", 0.1), cap_mat=STEEL)
    sp.box(-1.0, -0.1, 0.6, 3.0, 2.0, 1.0, ORANGE, top=Mat("#E9965E"))
    sp.line((2.0, 0.9, 1.2), (3.6, 0.9, 2.0), 0.2, "#7d848d")
    sp.cyl((3.6, 0.3, 2.0), (3.6, 1.5, 2.0), 1.3, STEEL, bands=[0.5], cap_mat=DARK)
    _floodlights(sp, ((5.2, 2.8, 0), (-4.4, 3.8, 0)))
    sp.glow((0, 0, 1.0), 44, AMBER, 0.2)


@variant("ice_miner", 2, 8.6)
def ice_drill(sp: Sprite):
    """드릴 탑으로 얼음층을 데워 뽑는다."""
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.5)
    _ice_floor(sp)
    sp.box(-1.2, -1.2, 0, 2.4, 2.4, 0.4, STEEL)
    sp.truss((-0.8, -0.8, 0.4), (-0.2, -0.2, 8.2), 0.9, "#E9C24A", 0.1, 9, side=(1, -1, 0))
    sp.truss((0.8, 0.8, 0.4), (0.2, 0.2, 8.2), 0.9, "#E9C24A", 0.1, 9, side=(1, -1, 0))
    sp.box(-0.5, -0.5, 8.0, 1.0, 1.0, 0.5, DARK)
    sp.cyl((3.0, -1.0, 0), (3.0, -1.0, 2.6), 1.0, WHITE, bands=[0.33, 0.66])
    sp.sphere((3.0, -1.0, 2.6), 1.0, WHITE, clip_z=2.6)
    pipe(sp, [(0.0, 0.0, 1.0), (2.0, -1.0, 1.0)], 0.22)
    _floodlights(sp, ((4.6, 2.6, 0), (-4.4, 3.0, 0), (-3.6, -3.0, 0)))
    sp.glow((0, 0, 0.5), 30, "#ff8a3a", 0.35)


@variant("ice_miner", 3, 3.0)
def ice_tents(sp: Sprite):
    """작은 가열 천막 둘과 증기 회수관."""
    sp.contact_shadow(0, 0, 6.4, 4.8, 0.5)
    _ice_floor(sp)
    for c in ((-2.8, -1.4), (1.4, 1.8)):
        sp.ellipsoid((c[0], c[1], 0), 2.2, 1.8, 2.0, GOLD, clip_z=0.0)
    pipe(sp, [(-2.8, -1.4, 2.0), (-2.8, -1.4, 2.6), (3.6, -1.4, 2.6)], 0.2)
    pipe(sp, [(1.4, 1.8, 2.0), (1.4, 1.8, 2.6), (3.6, 1.8, 2.6), (3.6, -1.4, 2.6)], 0.2)
    sp.sphere((4.0, -2.2, 1.1), 1.0, WHITE)
    _floodlights(sp, ((5.0, 2.8, 0), (-4.6, 2.8, 0)))
    sp.glow((0, 0, 1.0), 44, AMBER, 0.2)


@variant("ice_miner", 4, 3.6)
def ice_dome_plant(sp: Sprite):
    """은박 가열 돔과 선별 공장."""
    sp.contact_shadow(0, 0, 6.4, 4.8, 0.5)
    _ice_floor(sp)
    sp.dome((-1.8, -0.4, 0), 3.2, 2.8, SILVER)
    sp.ring3((-1.8, -0.4, 1.0), 3.0, "#8a9099", 0.06)
    sp.line((1.0, 0.0, 0.8), (2.6, 0.6, 2.2), 0.4, "#5c626b")
    sp.box(2.2, -0.4, 0, 2.8, 2.6, 2.4, WHITE, top=SILVER)
    band_on(sp, Sprite.box_faces(2.2, -0.4, 0, 2.8, 2.6, 2.4)["left"], 0.8, 0.9, BLUE)
    sp.window(sp.on_face(*Sprite.box_faces(2.2, -0.4, 0, 2.8, 2.6, 2.4)["left"], 0.3, 0.4, 0.7, 0.65), "#9fd8ff")
    _floodlights(sp, ((5.2, 2.8, 0), (-4.4, 3.4, 0)))
    sp.glow((0, 0, 1.0), 44, AMBER, 0.2)


@variant("excavator", 1, 3.8)
def excavator_conveyor(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.4)
    sp.ellipsoid((-2.8, -0.6, 0), 2.2, 1.8, 1.4, REGOLITH, clip_z=0.0)
    sp.face([(-1.4, -0.5, 0.4), (2.0, -0.5, 3.0), (2.0, 0.5, 3.0), (-1.4, 0.5, 0.4)], DARK, ao=0, two_sided=True)
    sp.line((-1.4, -0.55, 0.4), (2.0, -0.55, 3.0), 0.12, "#E9C24A")
    sp.line((-1.4, 0.55, 0.4), (2.0, 0.55, 3.0), 0.12, "#E9C24A")
    for t in (0.3, 0.7):
        x = -1.4 + 3.4 * t
        sp.line((x, 0.5, 0), (x, 0.5, 0.4 + 2.6 * t), 0.08, "#8a9099")
    sp.frustum((2.6, 0.0, 1.6), (2.6, 0.0, 3.6), 0.4, 1.3, STEEL)
    legs(sp, [(2.0, -0.6, 1.8), (3.2, -0.6, 1.8), (2.6, 0.7, 1.8)], 0.0)
    sp.lamp((3.6, 0.0, 3.8), AMBER, 8)


@variant("excavator", 2, 3.2)
def excavator_loader(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.4)
    sp.ellipsoid((-2.8, 1.0, 0), 2.4, 1.9, 1.5, REGOLITH, clip_z=0.0)
    for x in (-0.4, 2.2):
        for y in (-1.6, 0.4):
            sp.cyl((x, y, 0.75), (x, y + 0.5, 0.75), 0.75, Mat("#3B3F46", 0.1), cap_mat=STEEL)
    sp.box(-0.9, -1.1, 0.8, 3.4, 1.5, 1.2, YELLOW, top=Mat("#F0D27A"))
    sp.box(0.8, -1.0, 2.0, 1.2, 1.3, 1.0, GLASS)
    sp.line((2.5, -0.35, 1.4), (3.6, -0.35, 1.0), 0.18, "#7d848d")
    sp.box(3.4, -1.2, 0.2, 0.9, 1.7, 0.9, Mat("#8C939C", 0.3))
    sp.lamp((2.5, 0.2, 2.2), AMBER, 8)


@variant("excavator", 3, 2.0)
def excavator_trench(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.4, 0.35)
    sp.face([(-3.6, -1.2, 0.02), (2.6, -1.2, 0.02), (2.6, 1.2, 0.02), (-3.6, 1.2, 0.02)], Mat("#2b2925"), normal=(0, 0, 1), ao=0)
    sp.face([(-3.6, -1.2, 0.02), (2.6, -1.2, 0.02), (2.6, -0.6, -0.9), (-3.6, -0.6, -0.9)], Mat("#4a4540"), ao=0, two_sided=True)
    sp.ellipsoid((-0.4, 2.6, 0), 4.0, 1.2, 1.0, REGOLITH, clip_z=0.0)
    sp.box(2.8, -0.6, 0.5, 1.6, 1.2, 0.7, WHITE, top=SILVER)
    for x in (2.6, 4.6):
        sp.cyl((x, -0.9, 0.55), (x, 0.9, 0.55), 0.5, STEEL, bands=[0.33, 0.66], cap_mat=DARK)
    sp.lamp((4.4, 0.6, 1.4), AMBER, 8)


@variant("excavator", 4, 2.6)
def excavator_bagging(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.4)
    sp.ellipsoid((-3.0, -1.0, 0), 2.0, 1.6, 1.3, REGOLITH, clip_z=0.0)
    sp.box(-1.0, -1.6, 0, 2.2, 2.0, 2.2, WHITE, top=SILVER)
    sp.frustum((0.1, -0.6, 2.2), (0.1, -0.6, 3.0), 0.3, 0.8, STEEL)
    for i in range(3):
        for k in range(3 - i):
            sp.box(1.8 + k * 0.9 + i * 0.45, 0.4, i * 0.55, 0.85, 1.6, 0.55, Mat("#9B8C77"))
    sp.lamp((1.25, -0.6, 1.8), AMBER, 8)


@variant("regolith_printer", 1, 6.0)
def printer_arm(sp: Sprite):
    """큰 로봇 팔이 굽은 벽을 찍는다."""
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.45)
    pts = []
    for i in range(13):
        t = math.radians(200 + i * 10)
        pts.append((3.0 * math.cos(t) + 1.0, 3.0 * math.sin(t) + 1.0))
    for k in range(5):
        z = k * 0.4
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            sp.face([(a[0], a[1], z), (b[0], b[1], z), (b[0], b[1], z + 0.4), (a[0], a[1], z + 0.4)], SINTER, ao=0,
                    two_sided=True, back=Mat("#8c7f6c"))
    sp.cyl((-3.0, -2.0, 0), (-3.0, -2.0, 1.0), 1.0, ORANGE, cap_mat=Mat("#E9965E"))
    sp.polyline3([(-3.0, -2.0, 1.0), (-3.0, -2.0, 3.6), (-0.8, -0.6, 5.0), (0.6, 0.4, 2.6)], "#E07B39", 0.4)
    sp.frustum((0.6, 0.4, 2.6), (0.6, 0.4, 2.1), 0.3, 0.1, DARK)
    sp.glow((0.6, 0.4, 2.0), 12, "#ff8a3a", 0.8)
    sp.lamp((-3.0, -2.0, 1.2), AMBER, 8)


@variant("regolith_printer", 2, 7.4)
def printer_cable(sp: Sprite):
    """기둥 네 개와 줄로 매단 인쇄 머리 (케이블 로봇)."""
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.45)
    sp.face([(-3.6, -2.6, 0.05), (3.6, -2.6, 0.05), (3.6, 2.6, 0.05), (-3.6, 2.6, 0.05)], SINTER, normal=(0, 0, 1), ao=0)
    sp.box(-3.0, -2.0, 0.05, 6.0, 4.0, 0.6, Mat("#A89A84"))
    head = (0.6, 0.2, 3.4)
    posts = [(-5.0, -3.6), (5.0, -3.6), (-5.0, 3.6), (5.0, 3.6)]
    for x, y in posts:
        if x + y < 0.5:
            sp.cyl((x, y, 0), (x, y, 7.0), 0.22, YELLOW)
            sp.line((x, y, 7.0), head, 0.04, "#c9ccd1")
    sp.box(head[0] - 0.4, head[1] - 0.4, head[2] - 0.2, 0.8, 0.8, 0.6, DARK)
    sp.glow((head[0], head[1], 0.7), 12, "#ff8a3a", 0.7)
    for x, y in posts:
        if x + y >= 0.5:
            sp.line((x, y, 7.0), head, 0.04, "#c9ccd1")
            sp.cyl((x, y, 0), (x, y, 7.0), 0.22, YELLOW)
    sp.lamp((5.0, 3.6, 7.2), AMBER, 9)


@variant("regolith_printer", 3, 6.6)
def printer_vault(sp: Sprite):
    """갠트리 아래에서 절반쯤 찍힌 볼트."""
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.45)
    sp.half_cyl((-4.4, 0, 0), (0.6, 0, 0), 3.2, SINTER, bands=[0.25, 0.5, 0.75], band_color="#83745f", cap_mat=CONCRETE)
    for k in range(3):
        sp.face([(0.6, -3.2 + k * 0.1, k * 0.5), (2.6, -3.2 + k * 0.1, k * 0.5), (2.6, -3.2 + k * 0.1, k * 0.5 + 0.5),
                 (0.6, -3.2 + k * 0.1, k * 0.5 + 0.5)], SINTER, two_sided=True)
    for x, y in ((-5.0, -3.8), (-5.0, 3.8)):
        sp.box(x - 0.25, y - 0.25, 0, 0.5, 0.5, 6.0, ORANGE)
    sp.box(-5.25, -4.05, 6.0, 9.0, 0.5, 0.5, ORANGE)
    sp.box(-5.25, 3.55, 6.0, 9.0, 0.5, 0.5, ORANGE)
    sp.box(1.6, -4.05, 5.6, 0.6, 8.1, 0.5, YELLOW)
    sp.line((1.9, 0.0, 5.6), (1.9, 0.0, 3.0), 0.16, "#7d848d")
    sp.glow((1.9, 0.0, 2.9), 12, "#ff8a3a", 0.8)
    for x, y in ((3.5, -3.8), (3.5, 3.8)):
        sp.box(x - 0.25, y - 0.25, 0, 0.5, 0.5, 6.0, ORANGE)
    sp.lamp((3.5, 3.8, 6.4), AMBER, 9)


@variant("regolith_printer", 4, 2.4)
def printer_sinter_rover(sp: Sprite):
    """마이크로파로 땅을 구워 포장하는 차와 포장된 판."""
    sp.contact_shadow(0, 0, 6.0, 4.6, 0.35)
    for i in range(6):
        for k in range(4):
            x = -5.2 + i * 1.6
            y = -2.8 + k * 1.6
            m = Mat("#A89A84") if (i + k) % 2 == 0 else Mat("#9B8C77")
            sp.face([(x, y, 0.04), (x + 1.5, y, 0.04), (x + 1.5, y + 1.5, 0.04), (x, y + 1.5, 0.04)], m, normal=(0, 0, 1),
                    ao=0, edge=False)
    for x in (2.6, 4.6):
        for y in (-1.2, 1.0):
            sp.cyl((x, y, 0.45), (x, y + 0.35, 0.45), 0.45, Mat("#3B3F46", 0.1), cap_mat=STEEL)
    sp.box(2.2, -1.0, 0.6, 2.8, 2.0, 0.9, WHITE, top=SILVER)
    sp.box(1.4, -0.9, 0.2, 0.8, 1.8, 0.4, DARK)
    sp.glow((1.6, 0.0, 0.1), 18, "#ff8a3a", 0.7)
    sp.box(3.0, -0.6, 1.5, 1.2, 1.2, 0.08, SOLAR)
    sp.lamp((5.05, 0.6, 1.0), AMBER, 8)


@variant("mre_plant", 1, 5.4)
def mre_twin(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    sp.frustum((-0.6, -1.0, 3.8), (-0.6, -1.0, 5.4), 0.3, 1.2, STEEL)
    legs(sp, [(-1.4, -1.8, 4.0), (0.2, -1.8, 4.0), (-1.4, -0.2, 4.0), (0.2, -0.2, 4.0)], 0.3)
    for x in (-2.6, 1.6):
        sp.cyl((x, 0.2, 0.3), (x, 0.2, 3.4), 1.3, Mat("#6B5A4C", 0.15), bands=[0.33, 0.66], cap_mat=STEEL)
        sp.window(Sprite.cyl_patch((x, 0.2, 0.3), (x, 0.2, 3.4), 1.3, 0.3, 0.45, 20, 70), "#ff7b2e",
                  frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
        sp.glow((x, 0.2, 1.2), 20, "#ff7b2e", 0.5)
    pipe(sp, [(-0.6, -1.0, 3.8), (-2.6, 0.2, 3.4)], 0.22)
    pipe(sp, [(-0.6, -1.0, 3.8), (1.6, 0.2, 3.4)], 0.22)
    sp.sphere((3.4, -2.4, 1.2), 0.9, WHITE)
    sp.ring3((3.4, -2.4, 1.2), 0.9, "#3FB8AF", 0.12)
    sp.lamp((4.0, 3.0, 1.5), AMBER, 8)


@variant("mre_plant", 2, 7.6)
def mre_tower(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    sp.cyl((-1.0, -0.8, 0.3), (-1.0, -0.8, 6.8), 1.5, Mat("#6B5A4C", 0.15), bands=[0.2, 0.4, 0.6, 0.8], cap_mat=STEEL)
    sp.cyl((-1.0, -0.8, 6.8), (-1.0, -0.8, 7.6), 0.6, STEEL)
    sp.window(Sprite.cyl_patch((-1.0, -0.8, 0.3), (-1.0, -0.8, 6.8), 1.5, 0.15, 0.25, 15, 75), "#ff7b2e",
              frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
    sp.glow((-1.0, -0.8, 1.6), 24, "#ff7b2e", 0.5)
    sp.face([(3.8, 1.6, 0.3), (0.2, 1.6, 6.0), (0.2, 2.6, 6.0), (3.8, 2.6, 0.3)], DARK, two_sided=True)
    sp.line((3.8, 1.55, 0.3), (0.2, 1.55, 6.0), 0.12, "#E9C24A")
    sp.sphere((3.0, -2.2, 1.1), 0.9, WHITE)
    sp.lamp((-1.0, -0.8, 7.8), "#ff5a3c", 6)


@variant("mre_plant", 3, 4.2)
def mre_box(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    sp.box(-3.8, -2.8, 0.3, 5.6, 4.0, 3.2, Mat("#7A6A5C", 0.15), top=Mat("#8C7C6E"))
    f = Sprite.box_faces(-3.8, -2.8, 0.3, 5.6, 4.0, 3.2)
    o, e1, e2 = f["left"]
    for i in range(4):
        u = 0.1 + i * 0.22
        sp.window(sp.on_face(o, e1, e2, u, 0.55, u + 0.12, 0.7), "#ff7b2e", frame="#2a2f36", glass=Mat("#b5481c", 0.3))
    for x in (-2.8, -1.0):
        sp.cyl((x, -1.0, 3.5), (x, -1.0, 4.4), 0.35, STEEL, cap_mat=CHAR)
        sp.glow((x, -1.0, 4.6), 10, "#ff7b2e", 0.4)
    for y in (-1.8, 0.6):
        sp.sphere((3.0, y, 1.3), 1.0, WHITE)
        sp.ring3((3.0, y, 1.3), 1.0, "#3FB8AF", 0.12)
    sp.lamp((2.2, 2.6, 1.6), AMBER, 8)


@variant("mre_plant", 4, 5.0)
def mre_casting(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    sp.cyl((-2.4, -1.2, 0.3), (-2.4, -1.2, 4.2), 1.6, Mat("#6B5A4C", 0.15), bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
    sp.frustum((-2.4, -1.2, 4.2), (-2.4, -1.2, 5.0), 1.0, 0.4, STEEL)
    sp.glow((-2.4, -1.2, 1.4), 22, "#ff7b2e", 0.5)
    sp.box(-0.8, 0.4, 0.3, 4.8, 1.2, 0.8, DARK, top=Mat("#5c626b"))
    for i in range(5):
        x = -0.5 + i * 0.95
        sp.box(x, 0.6, 1.1, 0.7, 0.8, 0.25, Mat("#ffa25a", 0.6) if i == 0 else Mat("#C2C7CD", 0.6))
    sp.glow((-0.15, 1.0, 1.3), 10, "#ff7b2e", 0.7)
    sp.sphere((2.8, -2.0, 1.1), 0.9, WHITE)
    sp.lamp((4.0, 1.8, 1.4), AMBER, 8)


@variant("parts_fab", 1, 5.0)
def fab_dome(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.dome((-1.2, -0.4, 0), 4.0, 3.8, WHITE)
    for zz in (1.2, 2.4, 3.2):
        k = math.sqrt(max(0.0, 1 - (zz / 3.8) ** 2))
        sp.ring3((-1.2, -0.4, zz), 4.0 * k, "#c9c3b6", 0.05)
    sp.half_cyl((2.4, -0.4, 0), (4.2, -0.4, 0), 1.5, WHITE)
    sp.face([(4.25, -1.1, 0), (4.25, 0.3, 0), (4.25, 0.3, 1.3), (4.25, -1.1, 1.3)], Mat("#8C939C", 0.3), normal=(1, 0, 0), ao=0)
    crate(sp, 2.4, 1.8, 1.1)
    crate(sp, 3.6, 1.8, 1.1, Mat("#C9A23A"))
    crate(sp, 3.0, 1.8, 1.0, ORANGE, 0.88)
    sp.lamp((4.3, 0.6, 1.6), AMBER, 8)


@variant("parts_fab", 2, 4.4)
def fab_inflatable(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.box(-4.8, -3.2, 0, 8.0, 6.4, 0.2, SINTER)
    sp.half_cyl((-4.4, -0.2, 0.2), (2.8, -0.2, 0.2), 3.0, FABRIC, bands=[0.15, 0.3, 0.45, 0.6, 0.75, 0.9],
                band_color="#b9ab92", cap_mat=WHITE)
    sp.face([(2.85, -1.4, 0.2), (2.85, 1.0, 0.2), (2.85, 1.0, 2.2), (2.85, -1.4, 2.2)], Mat("#8C939C", 0.3), normal=(1, 0, 0), ao=0)
    sp.box(3.4, -2.6, 0, 0.8, 0.8, 0.5, DARK)
    sp.polyline3([(3.8, -2.2, 0.5), (3.8, -2.2, 2.4), (4.8, -1.4, 3.0), (5.0, -0.8, 2.2)], "#E07B39", 0.22)
    crate(sp, 3.6, 1.2, 1.1)
    sp.lamp((2.9, 1.4, 2.4), AMBER, 8)


@variant("parts_fab", 3, 6.4)
def fab_crane(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.box(-4.6, -3.4, 0, 6.0, 6.8, 3.4, WHITE, top=SILVER)
    f = Sprite.box_faces(-4.6, -3.4, 0, 6.0, 6.8, 3.4)
    door(sp, f["right"], 0.15, 0.85, 0.75, Mat("#8C939C", 0.3))
    windows_row(sp, f["left"], 3, 0.55, 0.78, 0.1, 0.08)
    band_on(sp, f["left"], 0.86, 0.94, ORANGE)
    for y in (-3.0, 3.0):
        sp.box(5.2, y - 0.2, 0, 0.4, 0.4, 6.0, YELLOW)
    sp.box(1.4, -3.2, 6.0, 4.2, 0.4, 0.4, YELLOW)
    sp.box(1.4, 2.8, 6.0, 4.2, 0.4, 0.4, YELLOW)
    sp.box(3.6, -3.0, 5.6, 0.5, 6.0, 0.4, ORANGE)
    sp.line((3.85, 0.4, 5.6), (3.85, 0.4, 2.0), 0.05, "#9aa1aa")
    crate(sp, 3.2, 0.0, 1.2)
    crate(sp, 3.2, -2.0, 1.2, Mat("#C9A23A"))
    sp.lamp((5.4, 3.0, 6.2), AMBER, 9)


@variant("parts_fab", 4, 3.8)
def fab_linked(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.box(-4.6, -3.4, 0, 4.0, 3.2, 3.0, WHITE, top=SILVER)
    sp.box(-0.6, -1.0, 0, 1.8, 1.4, 2.0, STEEL)
    sp.box(1.2, -3.0, 0, 3.6, 3.4, 3.4, WHITE, top=SILVER)
    f = Sprite.box_faces(1.2, -3.0, 0, 3.6, 3.4, 3.4)
    door(sp, f["right"], 0.3, 0.7, 0.65, Mat("#8C939C", 0.3))
    windows_row(sp, Sprite.box_faces(-4.6, -3.4, 0, 4.0, 3.2, 3.0)["left"], 2, 0.5, 0.75, 0.15, 0.1)
    sp.box(-4.4, 0.6, 0.4, 8.6, 1.0, 0.3, DARK)
    for i in range(6):
        crate(sp, -4.0 + i * 1.4, 0.7, 0.7, ORANGE if i % 2 else Mat("#C9A23A"), 0.7)
    sp.lamp((4.9, 0.4, 2.8), AMBER, 8)


@variant("robot_bay", 1, 3.6)
def bay_garage(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.5)
    sp.box(-4.8, -3.2, 0, 9.6, 6.4, 0.2, SINTER)
    sp.box(-4.2, -2.8, 0.2, 7.0, 5.6, 3.2, WHITE, top=SILVER)
    f = Sprite.box_faces(-4.2, -2.8, 0.2, 7.0, 5.6, 3.2)
    o, e1, e2 = f["right"]
    for u0 in (0.08, 0.54):
        sp.face(sp.on_face(o, e1, e2, u0, 0.0, u0 + 0.38, 0.75), Mat("#8C939C", 0.3), normal=(1, 0, 0), ao=0)
        for k in range(6):
            v = 0.08 + k * 0.11
            pts = sp.on_face(o, e1, e2, u0, v, u0 + 0.38, v + 0.01)
            sp.face(pts, DARK, normal=(1, 0, 0), ao=0, edge=False)
    band_on(sp, f["left"], 0.82, 0.9, ORANGE)
    for y in (-2.0, 1.2):
        sp.box(3.4, y - 0.5, 0.2, 1.0, 1.0, 0.08, DARK)
        sp.lamp((3.9, y, 0.35), AMBER, 7)


@variant("robot_bay", 2, 3.6)
def bay_shelter(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.45)
    sp.box(-4.8, -3.2, 0, 9.6, 6.4, 0.2, SINTER)
    for k in range(3):
        x = -3.2 + k * 2.8
        sp.box(x - 0.9, -1.6, 0.2, 1.8, 1.8, 0.9, ORANGE, top=Mat("#E9965E"))
        sp.box(x - 0.6, 0.6, 0.2, 1.2, 1.2, 0.7, Mat("#C9CED4", 0.3))
    for x in (-4.4, 4.0):
        for y in (-2.8, 2.6):
            sp.line((x, y, 0.2), (x, y, 3.4), 0.1, "#8a9099")
    sp.quad((-4.6, -3.0, 3.4), (8.8, 0, 0), (0, 5.8, 0.4), SOLAR, back=STEEL)
    sp.panel_grid((-4.6, -3.0, 3.4), (8.8, 0, 0), (0, 5.8, 0.4), 10, 4, "#6f86b0", 0.45, 0.55)
    sp.lamp((4.0, 2.6, 3.0), AMBER, 8)


@variant("robot_bay", 3, 4.0)
def bay_dome(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.5)
    sp.box(-4.8, -3.2, 0, 9.6, 6.4, 0.2, SINTER)
    sp.dome((-1.0, 0.0, 0.2), 3.8, 3.6, Mat("#DAD3C4"))
    sp.half_cyl((2.2, 0.0, 0.2), (4.2, 0.0, 0.2), 2.0, Mat("#DAD3C4"))
    sp.face([(4.25, -1.4, 0.2), (4.25, 1.4, 0.2), (4.25, 1.4, 1.8), (4.25, -1.4, 1.8)], CHAR, normal=(1, 0, 0), ao=0)
    sp.poly2([PV((4.27, -1.4, 0.2)), PV((4.27, 1.4, 0.2)), PV((4.27, 1.4, 1.8)), PV((4.27, -1.4, 1.8))],
             "#ffcf8a", None, 0, 0.5, layer="light")
    sp.stripes((4.28, -1.4, 1.8), (0, 2.8, 0), (0, 0, 0.25), n=8, normal=(1, 0, 0))
    sp.lamp((4.4, 2.0, 0.4), AMBER, 7)


@variant("robot_bay", 4, 3.2)
def bay_double(sp: Sprite):
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.5)
    sp.box(-4.8, -3.2, 0, 9.6, 6.4, 0.2, SINTER)
    for y in (-1.5, 1.5):
        sp.half_cyl((-4.0, y, 0.2), (3.0, y, 0.2), 1.45, Mat("#DAD3C4"), bands=[0.25, 0.5, 0.75], band_color="#ada594")
        sp.face([(3.05, y - 1.0, 0.2), (3.05, y + 1.0, 0.2), (3.05, y + 1.0, 1.4), (3.05, y - 1.0, 1.4)], CHAR,
                normal=(1, 0, 0), ao=0)
        sp.poly2([PV((3.07, y - 1.0, 0.2)), PV((3.07, y + 1.0, 0.2)), PV((3.07, y + 1.0, 1.4)), PV((3.07, y - 1.0, 1.4))],
                 "#ffcf8a", None, 0, 0.5, layer="light")
    sp.lamp((3.6, 0.0, 0.4), AMBER, 7)


@variant("propellant_plant", 1, 4.6)
def prop_spheres(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    legs(sp, [(-3.2, -2.6, 1.6), (-1.0, -2.6, 1.6), (-3.2, -0.4, 1.6), (-1.0, -0.4, 1.6)], 0.3)
    sp.sphere((-2.1, -1.5, 2.6), 1.8, FROST)
    sp.ring3((-2.1, -1.5, 2.6), 1.8, "#b5c6cf", 0.08)
    legs(sp, [(0.6, -2.4, 1.4), (2.4, -2.4, 1.4), (0.6, -0.6, 1.4), (2.4, -0.6, 1.4)], 0.3)
    sp.sphere((1.5, -1.5, 2.3), 1.5, FOAM)
    sp.box(-1.6, 1.0, 0.3, 3.0, 2.0, 2.2, WHITE, top=SILVER)
    band_on(sp, Sprite.box_faces(-1.6, 1.0, 0.3, 3.0, 2.0, 2.2)["left"], 0.8, 0.9, BLUE)
    sp.quad((2.4, 0.8, 0.3), (0, 2.4, 0), (0, 0, 2.8), RADIATOR, back=RADIATOR)
    sp.lamp((1.5, -1.5, 4.0), "#ff5a3c", 6)


@variant("propellant_plant", 2, 3.6)
def prop_horizontal(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    for y, m in ((-2.2, FROST), (-0.4, FOAM)):
        for x in (-3.0, 1.0):
            sp.box(x - 0.25, y - 0.6, 0.3, 0.5, 1.2, 0.8, STEEL)
        sp.cyl((-3.8, y, 1.75), (2.0, y, 1.75), 0.85, m, bands=[0.33, 0.66], cap_mat=m)
    sp.box(-2.0, 1.2, 0.3, 2.6, 1.8, 2.0, WHITE, top=SILVER)
    o, e1, e2 = (1.2, 1.0, 0.3), (2.8, 0, 0), (0, 0, 3.0)
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, 5, 1, "#b9bec4", 0.5, 0.7)
    sp.lamp((2.1, -2.2, 2.8), "#ff5a3c", 6)


@variant("propellant_plant", 3, 10.4)
def prop_tall(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    sp.cyl((-1.2, -1.2, 0.3), (-1.2, -1.2, 9.2), 1.6, FROST, bands=[0.2, 0.4, 0.6, 0.8], band_color="#b5c6cf")
    sp.sphere((-1.2, -1.2, 9.2), 1.6, FROST, clip_z=9.2)
    for x in (1.4, 2.6, 3.8):
        sp.quad((x, -2.8, 0.3), (0, 2.4, 0), (0, 0, 4.4), RADIATOR, back=RADIATOR)
    sp.box(-3.6, 1.0, 0.3, 2.4, 1.8, 1.8, WHITE, top=SILVER)
    pipe(sp, [(-1.2, 0.4, 1.6), (-1.2, 1.0, 1.6)])
    sp.lamp((-1.2, -1.2, 10.9), "#ff5a3c", 6)


@variant("propellant_plant", 4, 8.4)
def prop_cluster(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0, 0.5)
    skid(sp, -4.5, -3.5, 9, 7, 0.3, SINTER)
    for (x, y, h, m) in ((-2.6, -1.8, 7.6, FROST), (0.2, -2.2, 6.4, FOAM), (-1.0, 0.6, 5.2, FROST)):
        sp.cyl((x, y, 0.3), (x, y, h), 1.05, m, bands=[0.5], band_color="#b5c6cf" if m is FROST else "#a45a1c")
        sp.sphere((x, y, h), 1.05, m, clip_z=h)
    sp.box(1.6, 0.0, 0.3, 2.4, 2.4, 2.2, WHITE, top=SILVER)
    band_on(sp, Sprite.box_faces(1.6, 0.0, 0.3, 2.4, 2.4, 2.2)["left"], 0.8, 0.9, BLUE)
    pipe(sp, [(-1.6, -1.8, 1.0), (1.6, 0.6, 1.0)])
    sp.lamp((-2.6, -1.8, 8.9), "#ff5a3c", 6)


# ── 물류·안전·연구·사회 ───────────────────────────────────────────────

def _pad_lights(sp: Sprite, pts):
    for p in pts:
        sp.lamp(p, AMBER, 9)


@variant("landing_pad", 1, 2.0)
def pad_square(sp: Sprite):
    """네모난 착륙장과 모서리 등, 한쪽 폭발막이 벽."""
    h = 14.0
    sp.face([(-h, -h, 0.05), (h, -h, 0.05), (h, h, 0.05), (-h, h, 0.05)], SINTER, normal=(0, 0, 1), ao=0)
    for k in range(1, 7):
        t = -h + k * (2 * h / 7)
        sp.line((t, -h, 0.06), (t, h, 0.06), 0.06, "#8a7c68")
        sp.line((-h, t, 0.06), (h, t, 0.06), 0.06, "#8a7c68")
    sp.polyline3([(-h + 1, -h + 1, 0.07), (h - 1, -h + 1, 0.07), (h - 1, h - 1, 0.07), (-h + 1, h - 1, 0.07)], "#E9C24A",
                 0.3, closed=True)
    sp.ring3((0, 0, 0.07), 3.0, "#E9C24A", 0.35, front_only=False)
    _pad_lights(sp, [(x, y, 0.1) for x in (-h, h) for y in (-h, h)] + [(0, -h, 0.1), (0, h, 0.1), (-h, 0, 0.1), (h, 0, 0.1)])
    sp.box(-h - 3.0, -h, 0, 1.2, 2 * h, 2.4, CONCRETE)


@variant("landing_pad", 2, 2.6)
def pad_fence(sp: Sprite):
    """둥근 착륙장 둘레에 조각 폭발막이 벽."""
    r = 13.0
    segs = []
    for i in range(12):
        a0 = 2 * math.pi * i / 12 + 0.06
        a1 = 2 * math.pi * (i + 1) / 12 - 0.06
        am = (a0 + a1) / 2
        segs.append((dot((math.cos(am), math.sin(am), 0.0), VIEW), a0, a1))
    segs.sort()
    R = r + 2.4
    def wall(a0, a1):
        p0 = (R * math.cos(a0), R * math.sin(a0), 0.0)
        p1 = (R * math.cos(a1), R * math.sin(a1), 0.0)
        sp.face([p0, p1, add(p1, (0, 0, 2.4)), add(p0, (0, 0, 2.4))], CONCRETE, two_sided=True, back=Mat("#8f8270"))
    for _, a0, a1 in segs[:6]:
        wall(a0, a1)
    pts = [(r * math.cos(2 * math.pi * i / 48), r * math.sin(2 * math.pi * i / 48), 0.05) for i in range(48)]
    sp.face(pts, Mat("#A89A84"), normal=(0, 0, 1), ao=0)
    for rr in (4.0, 8.0):
        sp.ring3((0, 0, 0.06), rr, "#8a7c68", 0.08, front_only=False)
    sp.ring3((0, 0, 0.07), 2.2, "#E9C24A", 0.35, front_only=False)
    _pad_lights(sp, [(r * 0.95 * math.cos(2 * math.pi * i / 12), r * 0.95 * math.sin(2 * math.pi * i / 12), 0.1) for i in range(12)])
    for _, a0, a1 in segs[6:]:
        wall(a0, a1)


@variant("landing_pad", 3, 1.4)
def pad_hex(sp: Sprite):
    """육각 판으로 깐 착륙장."""
    r = 14.0
    hexa = [(r * math.cos(math.radians(30 + 60 * i)), r * math.sin(math.radians(30 + 60 * i)), 0.05) for i in range(6)]
    sp.face(hexa, SINTER, normal=(0, 0, 1), ao=0)
    cell = 2.6
    for i in range(-6, 7):
        for k in range(-6, 7):
            x = i * cell * 1.5
            y = k * cell * math.sqrt(3) + (i % 2) * cell * math.sqrt(3) / 2
            if math.hypot(x, y) > r - 2.5:
                continue
            pts = [(x + cell * math.cos(math.radians(60 * j)), y + cell * math.sin(math.radians(60 * j)), 0.06)
                   for j in range(7)]
            sp.polyline3(pts, "#8a7c68", 0.05, 0.8)
    sp.ring3((0, 0, 0.07), 2.4, "#E9C24A", 0.35, front_only=False)
    _pad_lights(sp, [(p[0] * 0.97, p[1] * 0.97, 0.1) for p in hexa])
    sp.berm_ring((0, 0, 0), r + 0.8, r + 2.6, 1.2, front=True)


@variant("landing_pad", 4, 10.0)
def pad_tower(sp: Sprite):
    """정비탑과 연료관이 있는 착륙장."""
    r = 12.5
    sp.berm_ring((0, 0, 0), r + 1.0, r + 3.0, 1.5, front=False)
    pts = [(r * math.cos(2 * math.pi * i / 48), r * math.sin(2 * math.pi * i / 48), 0.05) for i in range(48)]
    sp.face(pts, SINTER, normal=(0, 0, 1), ao=0)
    sp.ring3((0, 0, 0.06), 6.0, "#8a7c68", 0.08, front_only=False)
    sp.ring3((0, 0, 0.07), 2.4, "#E9C24A", 0.35, front_only=False)
    sp.truss((-9.0, -9.0, 0.0), (-9.0, -9.0, 10.0), 1.6, "#E07B39", 0.12, 8, side=(1, -1, 0))
    sp.box(-9.8, -9.8, 9.6, 1.6, 1.6, 0.6, DARK)
    sp.line((-9.0, -9.0, 8.0), (-4.0, -4.0, 8.0), 0.18, "#E07B39")
    pipe(sp, [(-9.0, -9.0, 0.3), (-15.5, -9.0, 0.3)], 0.25)
    _pad_lights(sp, [(r * 0.95 * math.cos(2 * math.pi * i / 16), r * 0.95 * math.sin(2 * math.pi * i / 16), 0.1) for i in range(16)])
    sp.lamp((-9.0, -9.0, 10.4), "#ff5a3c", 6)
    sp.berm_ring((0, 0, 0), r + 1.0, r + 3.0, 1.5, front=True)


@variant("storm_shelter", 1, 3.6)
def shelter_water(sp: Sprite):
    """물탱크 벽으로 두른 대피소 — 물이 양성자를 막는다."""
    sp.contact_shadow(0, 0, 5.6, 4.2, 0.5)
    sp.box(-4.6, -3.2, 0, 8.4, 6.4, 0.3, CONCRETE)
    sp.box(-4.2, -2.8, 0.3, 7.6, 5.6, 3.0, Mat("#3E6FB0", 0.35), top=Mat("#5c86c2", 0.3))
    f = Sprite.box_faces(-4.2, -2.8, 0.3, 7.6, 5.6, 3.0)
    sp.panel_grid(*f["left"], 6, 3, "#2c4f80", 0.6, 0.9)
    sp.panel_grid(*f["right"], 5, 3, "#2c4f80", 0.6, 0.9)
    sp.box(3.4, -1.0, 0, 1.8, 2.0, 2.4, CONCRETE)
    door(sp, Sprite.box_faces(3.4, -1.0, 0, 1.8, 2.0, 2.4)["right"], 0.2, 0.8, 0.75, Mat("#5c626b", 0.3))
    o, e1, e2 = Sprite.box_faces(3.4, -1.0, 0, 1.8, 2.0, 2.4)["right"]
    sp.stripes(add(o, (0.01, 0, 1.95)), (0, 2.0, 0), (0, 0, 0.4), n=6, normal=(1, 0, 0))


@variant("storm_shelter", 2, 4.0)
def shelter_long(sp: Sprite):
    """양쪽에 출입구가 있는 긴 흙 벙커."""
    sp.contact_shadow(0, 0, 6.2, 4.0, 0.5)
    sp.ellipsoid((0.0, 0, 0), 5.8, 3.4, 3.8, BERM, clip_z=0.0)
    sandbag_rings(sp, (0, 0, 0), 5.8, 3.4, 3.8, (1.0, 2.0, 3.0))
    for y, face in ((-1.4, "right"),):
        pass
    sp.box(4.6, -1.0, 0, 1.6, 2.0, 2.2, CONCRETE)
    door(sp, Sprite.box_faces(4.6, -1.0, 0, 1.6, 2.0, 2.2)["right"], 0.2, 0.8, 0.75, Mat("#5c626b", 0.3))
    sp.box(-1.0, 2.6, 0, 2.0, 1.6, 2.2, CONCRETE)
    door(sp, Sprite.box_faces(-1.0, 2.6, 0, 2.0, 1.6, 2.2)["left"], 0.2, 0.8, 0.75, Mat("#5c626b", 0.3))
    sp.stripes((6.21, -1.0, 1.8), (0, 2.0, 0), (0, 0, 0.35), n=6, normal=(1, 0, 0))
    antenna(sp, (-2.0, -1.0, 3.3), 2.0)


@variant("storm_shelter", 3, 2.6)
def shelter_ramp(sp: Sprite):
    """땅 아래로 내려가는 경사로와 지하 대피소 입구."""
    sp.contact_shadow(0, 0, 5.6, 4.0, 0.4)
    sp.ellipsoid((-1.6, 0, 0), 4.2, 3.4, 1.6, BERM, clip_z=0.0)
    sp.face([(1.0, -1.2, 0.02), (5.0, -1.2, 0.02), (5.0, 1.2, 0.02), (1.0, 1.2, 0.02)], Mat("#2f2c28"), normal=(0, 0, 1), ao=0)
    sp.face([(1.0, -1.2, 0.02), (5.0, -1.2, 0.02), (5.0, -1.2, 0.9), (1.0, -1.2, 0.9)], CONCRETE, two_sided=True)
    sp.box(0.4, -1.6, 0, 0.8, 3.2, 2.6, CONCRETE)
    sp.face([(1.21, -1.0, 0.0), (1.21, 1.0, 0.0), (1.21, 1.0, 1.9), (1.21, -1.0, 1.9)], DARK, normal=(1, 0, 0), ao=0)
    sp.stripes((1.22, -1.6, 2.1), (0, 3.2, 0), (0, 0, 0.4), n=8, normal=(1, 0, 0))
    sp.lamp((1.3, 1.4, 2.4), AMBER, 9)
    sp.lamp((1.3, -1.4, 2.4), AMBER, 9)


@variant("storm_shelter", 4, 3.4)
def shelter_dome(sp: Sprite):
    """두꺼운 프린팅 껍질의 낮은 돔 대피소."""
    sp.contact_shadow(0, 0, 5.8, 4.6, 0.5)
    sp.dome((-0.6, 0, 0), 5.0, 3.2, Mat("#A89A84"))
    for zz in (0.6, 1.2, 1.8, 2.4, 2.9):
        k = math.sqrt(max(0.0, 1 - (zz / 3.2) ** 2))
        sp.ring3((-0.6, 0, zz), 5.0 * k, "#83745f", 0.05, opacity=0.8)
    sp.box(3.8, -1.1, 0, 1.8, 2.2, 2.3, CONCRETE)
    door(sp, Sprite.box_faces(3.8, -1.1, 0, 1.8, 2.2, 2.3)["right"], 0.25, 0.75, 0.75, Mat("#5c626b", 0.3))
    sp.stripes((5.61, -1.1, 1.85), (0, 2.2, 0), (0, 0, 0.4), n=6, normal=(1, 0, 0))


@variant("medical_bay", 1, 4.2)
def med_inflatable(sp: Sprite):
    sp.contact_shadow(0, 0, 4.6, 3.0)
    for x in (-2.4, 1.4):
        sp.box(x - 0.3, -1.6, 0, 0.6, 3.2, 0.5, STEEL)
    p0, p1 = (-3.6, 0, 2.15), (2.6, 0, 2.15)
    sp.cyl(p0, p1, 1.9, WHITE, bands=[0.2, 0.4, 0.6, 0.8], band_color="#c9c3b6", cap_mat=WHITE)
    ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.3)))
    c = add(p0, mul(sub(p1, p0), 0.3))
    for (s0, s1, a0, a1) in ((0.26, 0.34, ang - 6, ang + 6), (0.22, 0.38, ang - 2, ang + 2)):
        pass
    sp.face(Sprite.cyl_patch(p0, p1, 1.9, 0.28, 0.32, ang - 14, ang + 14), TEAL, ao=0, edge=False)
    sp.face(Sprite.cyl_patch(p0, p1, 1.9, 0.24, 0.36, ang - 4, ang + 4), TEAL, ao=0, edge=False)
    for s in (0.5, 0.68):
        sp.window(Sprite.cyl_patch(p0, p1, 1.9, s, s + 0.1, ang - 12, ang + 12))
    sp.box(2.5, -0.9, 0, 1.4, 1.8, 2.0, WHITE)
    door(sp, Sprite.box_faces(2.5, -0.9, 0, 1.4, 1.8, 2.0)["right"], 0.25, 0.75, 0.8, Mat("#cfd6dc", 0.3))
    sp.lamp((3.0, 1.0, 2.2), CYAN_LIGHT, 8)


@variant("medical_bay", 2, 4.6)
def med_domed(sp: Sprite):
    sp.contact_shadow(0, 0, 4.4, 3.4)
    sp.box(-3.2, -2.4, 0, 6.4, 4.8, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.2, -2.4, 0, 6.4, 4.8, 2.4)
    band_on(sp, f["left"], 0.82, 0.92, TEAL)
    windows_row(sp, f["left"], 3, 0.4, 0.68, 0.28, 0.06)
    o, e1, e2 = f["left"]
    cu, cv = 0.13, 0.55
    sp.face(sp.on_face(o, e1, e2, cu - 0.03, cv - 0.18, cu + 0.03, cv + 0.18), TEAL, normal=(0, 1, 0), ao=0)
    sp.face(sp.on_face(o, e1, e2, cu - 0.07, cv - 0.07, cu + 0.07, cv + 0.07), TEAL, normal=(0, 1, 0), ao=0)
    sp.dome((0, 0, 2.4), 2.0, 1.8, Mat("#cfe6f5", 0.6))
    sp.glow((0, 0, 3.4), 18, CYAN_LIGHT, 0.4)
    door(sp, f["right"], 0.35, 0.65, 0.75, Mat("#cfd6dc", 0.3))


@variant("medical_bay", 3, 5.4)
def med_twostory(sp: Sprite):
    sp.contact_shadow(0, 0, 4.2, 3.2)
    sp.box(-3.0, -2.2, 0, 6.0, 4.4, 5.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.0, -2.2, 0, 6.0, 4.4, 5.0)
    windows_row(sp, f["left"], 4, 0.18, 0.32, 0.08, 0.05)
    windows_row(sp, f["left"], 4, 0.58, 0.72, 0.08, 0.05)
    band_on(sp, f["left"], 0.46, 0.5, TEAL)
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.42, 0.5, 0.58, 0.9), TEAL, normal=(1, 0, 0), ao=0)
    sp.face(sp.on_face(o, e1, e2, 0.34, 0.63, 0.66, 0.77), TEAL, normal=(1, 0, 0), ao=0)
    door(sp, f["right"], 0.38, 0.62, 0.4, Mat("#cfd6dc", 0.3))
    sp.lamp((3.1, 1.8, 4.4), CYAN_LIGHT, 8)


@variant("medical_bay", 4, 3.8)
def med_ambulance(sp: Sprite):
    sp.contact_shadow(0, 0, 4.6, 3.4)
    sp.box(-3.6, -2.4, 0, 4.8, 4.8, 3.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.6, -2.4, 0, 4.8, 4.8, 3.0)
    band_on(sp, f["left"], 0.84, 0.94, TEAL)
    windows_row(sp, f["left"], 2, 0.42, 0.7, 0.35, 0.08)
    o, e1, e2 = f["left"]
    sp.face(sp.on_face(o, e1, e2, 0.12, 0.38, 0.18, 0.72), TEAL, normal=(0, 1, 0), ao=0)
    sp.face(sp.on_face(o, e1, e2, 0.07, 0.5, 0.23, 0.6), TEAL, normal=(0, 1, 0), ao=0)
    for x, y in ((1.4, -2.2), (3.8, -2.2), (1.4, 2.2), (3.8, 2.2)):
        sp.line((x, y, 0), (x, y, 2.6), 0.07, "#8a9099")
    sp.quad((1.2, -2.4, 2.6), (2.8, 0, 0), (0, 4.8, 0), WHITE, back=STEEL)
    for x in (1.9, 3.3):
        for y in (-1.1, 0.9):
            sp.cyl((x, y, 0.35), (x, y + 0.25, 0.35), 0.35, Mat("#3B3F46", 0.1), cap_mat=STEEL)
    sp.box(1.6, -1.0, 0.45, 2.0, 2.0, 1.1, WHITE, top=Mat("#3FB8AF", 0.2))
    sp.lamp((3.6, 0.0, 1.8), CYAN_LIGHT, 8)


@variant("research_lab", 1, 6.4)
def lab_telescope(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.4, STEEL)
    sp.box(-3.6, -2.6, 0.4, 7.0, 5.2, 3.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.6, -2.6, 0.4, 7.0, 5.2, 3.0)
    band_on(sp, f["left"], 0.84, 0.94, Mat("#9B7AD6"))
    windows_row(sp, f["left"], 4, 0.42, 0.7, 0.08, 0.05)
    door(sp, f["right"], 0.4, 0.7, 0.66)
    sp.cyl((0.0, 0.0, 3.4), (0.0, 0.0, 4.2), 1.7, WHITE)
    sp.sphere((0.0, 0.0, 4.2), 1.7, WHITE, clip_z=4.2)
    sp.face([(0.5, -0.9, 4.6), (0.5, 0.9, 4.6), (0.9, 0.9, 5.7), (0.9, -0.9, 5.7)], CHAR, two_sided=True)
    sp.lamp((3.45, 2.6, 3.0), "#c86bfa", 7)


@variant("research_lab", 2, 7.2)
def lab_antennas(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.4, STEEL)
    sp.half_cyl((-3.6, 0.0, 0.4), (2.8, 0.0, 0.4), 2.6, WHITE, bands=[0.25, 0.5, 0.75], band_color="#c9c3b6", cap_mat=WHITE)
    sp.face([(2.85, -0.6, 0.4), (2.85, 0.6, 0.4), (2.85, 0.6, 2.0), (2.85, -0.6, 2.0)], DARK, normal=(1, 0, 0), ao=0)
    for (x, y, h) in ((3.2, -2.2, 6.8), (3.6, 2.2, 5.6), (-3.6, 2.6, 4.8)):
        sp.line((x, y, 0.4), (x, y, h), 0.08, "#9aa1aa")
        sp.disc((x, y, h), norm((0.2, 1.0, 0.8)), 0.5, WHITE, back=STEEL)
        sp.lamp((x, y, h + 0.3), "#ff5a3c", 5)
    sp.window(Sprite.cyl_patch((-3.6, 0, 0.4), (2.8, 0, 0.4), 2.6, 0.3, 0.42, 60, 82))
    sp.window(Sprite.cyl_patch((-3.6, 0, 0.4), (2.8, 0, 0.4), 2.6, 0.55, 0.67, 60, 82))


@variant("research_lab", 3, 4.0)
def lab_geology(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.4, STEEL)
    sp.box(-3.8, -2.8, 0.4, 5.2, 4.0, 2.8, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.8, -2.8, 0.4, 5.2, 4.0, 2.8)
    band_on(sp, f["left"], 0.84, 0.94, Mat("#9B7AD6"))
    windows_row(sp, f["left"], 3, 0.42, 0.7, 0.1, 0.06)
    sp.face(sp.on_face(*f["right"], 0.2, 0.3, 0.55, 0.7), GLASS, normal=(1, 0, 0), ao=0)
    for i in range(3):
        y = -2.4 + i * 1.6
        sp.box(2.2, y, 0.4, 1.4, 1.1, 0.9, Mat("#8C939C", 0.3))
        sp.rock((2.9, y + 0.55, 1.3), 0.35, Mat("#7A746B"))
    sp.rock((-3.0, 2.4, 0.4), 0.6)
    sp.lamp((1.5, 1.4, 2.8), "#c86bfa", 7)


@variant("research_lab", 4, 4.6)
def lab_seismic(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 4.0)
    sp.box(-4.0, -3.0, 0, 6.0, 6.0, 0.4, STEEL)
    sp.prism(rounded_rect(-3.8, -2.6, 1.6, 2.6, 0.8), 0.4, 3.2, WHITE, top=SILVER)
    o, e1, e2 = (0.8, 2.6, 0.4), (-3.8, 0, 0), (0, 0, 3.2)
    for i in range(3):
        u = 0.1 + i * 0.28
        sp.window(sp.on_face(o, e1, e2, u, 0.45, u + 0.18, 0.75))
    sp.face([(1.6, -0.6, 0.4), (1.6, 0.6, 0.4), (1.6, 0.6, 2.4), (1.6, -0.6, 2.4)], DARK, normal=(1, 0, 0), ao=0)
    sp.dome((3.6, 2.4, 0), 0.9, 0.7, GOLD)
    sp.polyline3([(3.6, 2.4, 0.05), (2.6, 2.4, 0.05), (1.8, 1.4, 0.05)], "#E9C24A", 0.06)
    for (x, y) in ((3.4, -2.2), (4.2, -0.4)):
        sp.cyl((x, y, 0), (x, y, 0.5), 0.25, STEEL)
    antenna(sp, (-1.0, 0.0, 3.6), 3.0)


def _glass_dome(sp: Sprite, c, r, h, z0=0.6):
    pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            pts.append(P(c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th), z0 + h * math.sin(ph)))
    sil = hull(pts)
    hl = PV((c[0] - r * 0.28, c[1] + r * 0.5, z0 + h * 0.8))
    fill = sp.radial([(0, "#ffffff", 0.32), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.05)], hl[0], hl[1], r * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    for zz in (0.25, 0.5, 0.72, 0.9):
        k = math.sqrt(max(0.0, 1 - zz ** 2))
        sp.ring3((c[0], c[1], z0 + h * zz), r * k, "#dfe9f2", 0.05, opacity=0.55)
    for i in range(12):
        th = 2 * math.pi * i / 12
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.2:
            continue
        pts = [(c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th), z0 + h * math.sin(ph))
               for ph in [k * math.pi / 2 / 12 for k in range(13)]]
        sp.polyline3(pts, "#dfe9f2", 0.05, 0.5)


def _trees(sp: Sprite, trees, z=0.6):
    trees = sorted(trees, key=lambda t: t[0] + t[1])
    for x, y, h, rr in trees:
        sp.tree((x, y, z), h, rr, LEAF if (x + y) % 2 > 1 else GREEN)


@variant("green_commons", 1, 6.0)
def commons_vault(sp: Sprite):
    """유리 볼트 정원."""
    sp.contact_shadow(0, 0, 7.6, 5.0, 0.45)
    sp.box(-7.4, -4.6, 0, 14.4, 9.2, 0.6, SINTER, top=Mat("#7FA864"))
    _trees(sp, [(-5.0, -1.6, 3.6, 1.2), (-2.0, 1.4, 4.0, 1.3), (1.0, -1.2, 3.4, 1.1), (3.8, 1.2, 3.8, 1.2),
                (-4.0, 2.2, 3.0, 1.0), (5.2, -1.6, 3.0, 1.0)])
    sp.glow((0, 0, 2.4), 56, WARM_WINDOW, 0.3)
    p0, p1 = (-7.2, 0.0, 0.6), (6.8, 0.0, 0.6)
    rim = []
    for i in range(25):
        t = math.pi * i / 24
        for p in (p0, p1):
            rim.append(PV((p[0], p[1] + 4.4 * math.cos(t), p[2] + 4.6 * math.sin(t))))
    sil = hull(rim)
    hl = PV((-3.0, 2.0, 4.4))
    fill = sp.radial([(0, "#ffffff", 0.3), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.05)], hl[0], hl[1], 9 * S)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    for x in (-5.0, -2.5, 0.0, 2.5, 5.0):
        pts = [(x, 4.4 * math.cos(math.pi * i / 16), 0.6 + 4.6 * math.sin(math.pi * i / 16)) for i in range(17)]
        sp.polyline3([q for q in pts if dot((0, q[1], q[2] - 0.6), VIEW) > -0.5], "#dfe9f2", 0.06, 0.55)
    sp.lamp((7.0, 1.2, 1.4), AMBER, 8)


@variant("green_commons", 2, 7.0)
def commons_terraced(sp: Sprite):
    """계단식 정원 돔."""
    r = 7.2
    sp.contact_shadow(0, 0, 7.8, 7.8, 0.45)
    sp.cyl((0, 0, 0), (0, 0, 0.6), r + 0.3, SINTER, cap_mat=Mat("#7FA864"))
    sp.cyl((0, 0, 0.6), (0, 0, 1.6), 4.6, Mat("#9B8C77"), cap_mat=Mat("#86B46E"))
    sp.cyl((0, 0, 1.6), (0, 0, 2.6), 2.4, Mat("#9B8C77"), cap_mat=Mat("#93BE79"))
    _trees(sp, [(-5.6, -1.0, 2.8, 1.0), (1.0, -5.4, 2.8, 1.0), (-3.0, 3.6, 3.0, 1.0), (5.0, 2.6, 2.6, 0.9)], 0.6)
    _trees(sp, [(-3.0, -2.6, 3.0, 1.0), (2.6, 2.6, 2.8, 0.9)], 1.6)
    _trees(sp, [(0.0, 0.0, 3.4, 1.2)], 2.6)
    sp.glow((0, 0, 2.6), 60, WARM_WINDOW, 0.35)
    _glass_dome(sp, (0, 0), r, 6.4)
    sp.half_cyl((7.0, 0, 0), (8.4, 0, 0), 1.3, WHITE)
    sp.face([(8.45, -0.5, 0), (8.45, 0.5, 0), (8.45, 0.5, 1.05), (8.45, -0.5, 1.05)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((8.5, 0.9, 1.4), AMBER, 8)


@variant("green_commons", 3, 5.0)
def commons_twin(sp: Sprite):
    """작은 유리 돔 두 개."""
    sp.contact_shadow(0, 0, 7.8, 6.4, 0.45)
    for c, r in (((-3.4, -2.6), 4.4), ((3.2, 2.8), 4.6)):
        sp.cyl((c[0], c[1], 0), (c[0], c[1], 0.5), r + 0.2, SINTER, cap_mat=Mat("#7FA864"))
        _trees(sp, [(c[0] - 1.6, c[1] - 1.0, 3.2, 1.1), (c[0] + 1.2, c[1] + 0.6, 2.8, 1.0), (c[0] - 0.4, c[1] + 1.8, 2.4, 0.8)], 0.5)
        sp.glow((c[0], c[1], 1.8), 34, WARM_WINDOW, 0.3)
        _glass_dome(sp, c, r, 4.0, 0.5)
    sp.half_cyl((-0.2, -0.6, 0), (0.6, 0.8, 0), 1.0, WHITE)
    sp.lamp((7.8, 2.8, 1.2), AMBER, 8)


@variant("green_commons", 4, 7.0)
def commons_pond(sp: Sprite):
    """연못이 있는 유리 돔."""
    r = 7.2
    sp.contact_shadow(0, 0, 7.8, 7.8, 0.45)
    sp.cyl((0, 0, 0), (0, 0, 0.6), r + 0.3, SINTER, cap_mat=Mat("#7FA864"))
    pond = [(1.0 + 3.0 * math.cos(2 * math.pi * i / 24), -0.6 + 2.0 * math.sin(2 * math.pi * i / 24), 0.62) for i in range(24)]
    sp.face(pond, Mat("#3E7FB8", 0.8), normal=(0, 0, 1), ao=0, edge=False)
    sp.ring3((1.0, -0.6, 0.63), 3.0, "#cfc6b6", 0.15, front_only=False)
    _trees(sp, [(-4.0, -3.0, 4.0, 1.4), (-4.6, 1.8, 3.6, 1.2), (-1.4, 4.2, 3.2, 1.1), (4.4, 3.0, 3.4, 1.1),
                (3.4, -4.4, 2.8, 0.9)])
    sp.box(-1.2, 1.6, 0.6, 1.4, 0.4, 0.45, COPPER)
    sp.glow((0, 0, 2.4), 60, WARM_WINDOW, 0.35)
    _glass_dome(sp, (0, 0), r, 6.2)
    sp.half_cyl((7.0, 0, 0), (8.4, 0, 0), 1.3, WHITE)
    sp.face([(8.45, -0.5, 0), (8.45, 0.5, 0), (8.45, 0.5, 1.05), (8.45, -0.5, 1.05)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((8.5, 0.9, 1.4), AMBER, 8)


def _dish(sp: Sprite, c, n, r, feed_len=None):
    sp.disc(c, n, r, WHITE, back=STEEL, seg=48)
    sp.ring3(c, r, "#b9b2a5", 0.08, normal=n, front_only=False)
    feed = add(c, mul(n, feed_len or r * 0.63))
    u, v = basis(n)
    for a in (0, 120, 240):
        rim = add(c, add(mul(u, r * 0.87 * math.cos(math.radians(a))), mul(v, r * 0.87 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.05, "#8a9099")
    sp.sphere(feed, max(0.12, r * 0.07), GOLD)


@variant("comms_center", 1, 7.0)
def comms_two(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 3.8)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.3, SINTER)
    for (x, y) in ((-2.4, -1.6), (1.6, -2.0)):
        sp.box(x - 0.8, y - 0.8, 0.3, 1.6, 1.6, 1.0, STEEL)
        sp.cyl((x, y, 1.3), (x, y, 3.6), 0.3, SILVER)
        _dish(sp, (x + 0.2, y + 0.3, 4.3), norm((0.15, 1.0, 0.25)), 1.9)
    sp.box(-1.6, 1.0, 0.3, 3.4, 1.8, 2.2, WHITE, top=SILVER)
    f = Sprite.box_faces(-1.6, 1.0, 0.3, 3.4, 1.8, 2.2)
    band_on(sp, f["left"], 0.82, 0.92, Mat("#F2A541"))
    windows_row(sp, f["left"], 2, 0.4, 0.66, 0.18, 0.12)
    sp.lamp((1.85, 2.0, 2.0), AMBER, 8)


@variant("comms_center", 2, 8.4)
def comms_array(sp: Sprite):
    """평판 위상 배열 안테나 탑."""
    sp.contact_shadow(0, 0, 5.0, 3.8)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.3, SINTER)
    sp.box(-2.2, -2.2, 0.3, 2.6, 2.6, 5.4, WHITE, top=SILVER)
    for side in (((0.4, -2.2, 0.3), (0, 2.6, 0)), ((0.4, 0.4, 0.3), (-2.6, 0, 0))):
        o, e1 = side
        sp.quad(add(o, (0.02 if e1[0] == 0 else 0, 0.02 if e1[1] == 0 else 0, 2.0)), e1, (0, 0, 3.4), Mat("#2E3A50", 0.5), back=STEEL)
        sp.panel_grid(add(o, (0.03 if e1[0] == 0 else 0, 0.03 if e1[1] == 0 else 0, 2.0)), e1, (0, 0, 3.4), 6, 6,
                      "#4c5f80", 0.5, 0.8)
    sp.line((-0.9, -0.9, 5.7), (-0.9, -0.9, 8.2), 0.06, "#9aa1aa")
    sp.lamp((-0.9, -0.9, 8.3), "#ff5a3c", 6)
    sp.box(1.4, 0.0, 0.3, 2.2, 2.4, 2.0, WHITE)
    windows_row(sp, Sprite.box_faces(1.4, 0.0, 0.3, 2.2, 2.4, 2.0)["left"], 1, 0.4, 0.7, 0.3)


@variant("comms_center", 3, 9.6)
def comms_mast(sp: Sprite):
    """높은 탑의 작은 접시와 레이저 통신 망원경."""
    sp.contact_shadow(0, 0, 5.0, 3.8)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.3, SINTER)
    sp.truss((-1.8, -1.2, 0.3), (-1.8, -1.2, 8.4), 1.0, "#a7adb5", 0.08, 10, side=(1, 0, 0))
    sp.truss((-1.8, -1.2, 0.3), (-1.8, -1.2, 8.4), 1.0, "#8f959d", 0.07, 10, side=(0, 1, 0))
    _dish(sp, (-1.6, -0.8, 8.8), norm((0.15, 1.0, 0.25)), 1.4)
    sp.box(1.0, -2.2, 0.3, 1.2, 1.2, 1.4, STEEL)
    sp.cyl((1.6, -1.6, 1.7), add((1.6, -1.6, 1.7), mul(norm((0.1, 1.0, 0.35)), 1.6)), 0.4, WHITE, cap_mat=GLASS)
    sp.glow(add((1.6, -1.6, 1.7), mul(norm((0.1, 1.0, 0.35)), 1.7)), 8, "#7fe3da", 0.8)
    sp.box(0.4, 0.6, 0.3, 3.2, 2.0, 2.2, WHITE, top=SILVER)
    f = Sprite.box_faces(0.4, 0.6, 0.3, 3.2, 2.0, 2.2)
    band_on(sp, f["left"], 0.82, 0.92, Mat("#F2A541"))
    door(sp, f["right"], 0.35, 0.7, 0.72)


@variant("comms_center", 4, 7.6)
def comms_farm(sp: Sprite):
    """큰 접시와 중계 안테나 숲."""
    sp.contact_shadow(0, 0, 5.0, 3.8)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.3, SINTER)
    sp.cyl((-2.0, -1.4, 0.3), (-2.0, -1.4, 4.6), 0.4, SILVER)
    _dish(sp, (-1.8, -1.0, 5.2), norm((0.15, 1.0, 0.18)), 2.4)
    for i in range(4):
        for k in range(2):
            x = 0.8 + i * 0.9
            y = 0.6 + k * 1.2
            sp.line((x, y, 0.3), (x, y, 2.6 + (i % 2) * 0.6), 0.05, "#9aa1aa")
            sp.line((x - 0.3, y, 2.2 + (i % 2) * 0.6), (x + 0.3, y, 2.2 + (i % 2) * 0.6), 0.04, "#9aa1aa")
    sp.box(1.0, -2.6, 0.3, 2.4, 1.8, 1.8, WHITE, top=SILVER)
    sp.lamp((3.4, -1.7, 1.6), AMBER, 8)
