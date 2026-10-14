"""탈것 16종.

모형은 앞이 +x를 보도록 적는다. 지상 탈것은 네 방향(se·sw·nw·ne)으로 돌려 그린다.
달에는 공기가 없어 날개·로터가 쓸모없다 — 달의 '헬리콥터'는 로켓 호퍼다.
비행기·헬리콥터·비행선은 대기가 있는 화성·타이탄·금성용이다 (시대 1 이후).
지구의 하늘에는 여객기가 다니고, 지구-달 셔틀이 지구 착륙장과 달 기지를 오간다.
"""
from __future__ import annotations

import math

import iso
from iso import (BLUE, CHAR, COPPER, CREAM, DARK, GLASS, GOLD, ICE, ORANGE, RADIATOR, RED, SILVER, SOLAR,
                 STEEL, TEAL, WHITE, YELLOW, AMBER, WARM_WINDOW, Mat, Sprite, add, basis, cross, dot, mul, norm,
                 rotz, sub)

VEHICLES: dict[str, dict] = {}

HEADINGS = {"se": 0.0, "sw": 90.0, "nw": 180.0, "ne": 270.0}

TIRE = Mat("#3B3F46", 0.1)
HUB = Mat("#A9B0B8", 0.4)
SEAT = Mat("#E07B39", 0.1)
FOIL = Mat("#C9A23A", 0.6)


def vehicle(vid: str, length: float, width: float, height: float, title: str, world: str,
            group: str, headings=("se",), flying: bool = False):
    def deco(fn):
        VEHICLES[vid] = {"fn": fn, "dims": [length, width, height], "title": title, "world": world,
                         "group": group, "headings": list(headings), "flying": flying}
        return fn
    return deco


# ── 부품 ─────────────────────────────────────────────────────────────

def wheel(sp: Sprite, c, r: float, width: float, mat: Mat = TIRE):
    p0 = (c[0], c[1] - width / 2, c[2])
    p1 = (c[0], c[1] + width / 2, c[2])
    sp.cyl(p0, p1, r, mat, cap_mat=HUB, bands=[0.3, 0.7], band_color="#5b6069")
    end = p1 if dot((0, 1, 0), iso.VIEW) > 0 else p0
    sp.disc(end, (0, 1, 0), r * 0.45, Mat("#C9CED4", 0.5), two_sided=True)


def leg_line(sp: Sprite, a, b, w=0.12, color="#8a9099"):
    sp.line(a, b, w, color)


def foot(sp: Sprite, p, r=0.35):
    sp.cyl((p[0], p[1], 0.0), (p[0], p[1], 0.12), r, STEEL, edge=False)


def lamp_front(sp: Sprite, p, color=WARM_WINDOW):
    sp.lamp(p, color, 8)


# ── 달 지상 ──────────────────────────────────────────────────────────

@vehicle("ltv", 3.6, 2.3, 2.2, "비가압 로버", "달", "ground", tuple(HEADINGS))
def ltv(sp: Sprite):
    sp.contact_shadow(0, 0, 2.1, 1.4, 0.45)
    r = 0.42
    wheels = [(x, y, r) for x in (-1.2, 1.2) for y in (-0.98, 0.98)]
    items = [((x, y, r), (lambda x=x, y=y: wheel(sp, (x, y, r), r, 0.32))) for x, y, _ in wheels]

    def chassis():
        sp.box(-1.75, -0.72, 0.5, 3.5, 1.44, 0.22, STEEL, top=Mat("#9AA2AB", 0.3))
        for x in (-1.2, 1.2):          # 바퀴 덮개
            for y in (-0.98, 0.98):
                sp.box(x - 0.5, y - 0.2 if y > 0 else y - 0.2, 0.88, 1.0, 0.4, 0.05, WHITE)

    def seats():
        for y in (-0.36, 0.36):
            sp.box(-0.45, y - 0.24, 0.72, 0.5, 0.48, 0.12, SEAT)
            sp.quad((-0.48, y - 0.24, 0.84), (0.0, 0.48, 0.0), (-0.12, 0.0, 0.55), SEAT, back=DARK)

    def console():
        sp.box(0.55, -0.32, 0.72, 0.3, 0.64, 0.5, WHITE, top=DARK)
        sp.quad((0.86, -0.25, 0.95), (0.0, 0.5, 0.0), (0.0, 0.0, 0.22), GLASS)

    def battery():
        sp.box(-1.72, -0.55, 0.72, 0.55, 1.1, 0.38, FOIL)

    def mast():
        sp.line((-1.45, 0.0, 1.1), (-1.45, 0.0, 2.05), 0.06, "#9aa1aa")
        sp.disc((-1.45, 0.0, 2.1), norm((0.2, 1.0, 0.35)), 0.42, WHITE, back=STEEL)
        sp.line((-1.45, 0.0, 2.1), add((-1.45, 0.0, 2.1), mul(norm((0.2, 1.0, 0.35)), 0.35)), 0.04, "#8a9099")

    items += [((0, 0, 0.6), chassis), ((-0.2, 0, 0.9), seats), ((0.7, 0, 1.0), console),
              ((-1.45, 0, 0.9), battery), ((-1.45, 0, 1.6), mast)]
    sp.parts(items)
    for y in (-0.5, 0.5):
        lamp_front(sp, (1.78, y, 0.62))


@vehicle("pressurized_rover", 6.4, 3.4, 3.5, "가압 로버", "달", "ground", tuple(HEADINGS))
def pressurized_rover(sp: Sprite):
    sp.contact_shadow(0, 0, 3.5, 2.0, 0.5)
    r = 0.56
    items = []
    for x in (-2.1, 0.0, 2.1):
        for y in (-1.58, 1.58):
            items.append(((x, y, r), (lambda x=x, y=y: wheel(sp, (x, y, r), r, 0.42))))

    def body():
        sp.box(-3.0, -1.4, 0.95, 5.2, 2.8, 2.25, WHITE, top=Mat("#D9D4C8"))
        f = Sprite.box_faces(-3.0, -1.4, 0.95, 5.2, 2.8, 2.25)
        o, e1, e2 = f["left"]
        sp.face(sp.on_face(o, e1, e2, 0.0, 0.18, 1.0, 0.27), ORANGE, normal=(0, 1, 0), edge=False, ao=0)
        for i in range(3):
            u = 0.12 + i * 0.22
            sp.window(sp.on_face(o, e1, e2, u, 0.5, u + 0.14, 0.75))
        # 반대쪽 면에도 같은 줄과 창 (돌려 그릴 때 보인다)
        o2, e12, e22 = (-3.0, -1.4, 0.95), (5.2, 0.0, 0.0), (0.0, 0.0, 2.25)
        sp.face(sp.on_face(o2, e12, e22, 0.0, 0.18, 1.0, 0.27), ORANGE, normal=(0, -1, 0), edge=False, ao=0)
        for i in range(3):
            u = 0.22 + i * 0.22
            pts = sp.on_face(o2, e12, e22, u, 0.5, u + 0.14, 0.75)
            sp.window([pts[1], pts[0], pts[3], pts[2]])
        # 뒤쪽 도킹 해치
        sp.disc((-3.02, 0.0, 2.0), (-1, 0, 0), 0.75, STEEL, two_sided=False)
        sp.disc((-3.04, 0.0, 2.0), (-1, 0, 0), 0.5, DARK, two_sided=False)
        # 지붕 태양전지와 안테나
        sp.box(-2.6, -1.1, 3.2, 3.4, 2.2, 0.08, SOLAR)
        sp.panel_grid((-2.6, -1.1, 3.29), (3.4, 0, 0), (0, 2.2, 0), 6, 3, "#6f86b0", 0.45, 0.6)
        sp.line((1.4, 0.8, 3.2), (1.4, 0.8, 3.9), 0.05, "#9aa1aa")
        sp.lamp((1.4, 0.8, 3.95), "#ff5a3c", 5)

    def nose():
        A, B, C, D = (2.2, -1.4, 0.95), (2.2, 1.4, 0.95), (2.2, 1.4, 3.2), (2.2, -1.4, 3.2)
        E, F, G, H = (3.1, -1.25, 1.05), (3.1, 1.25, 1.05), (3.1, 1.25, 2.0), (3.1, -1.25, 2.0)
        sp.face([H, G, C, D], GLASS)
        sp.face([E, F, G, H], WHITE)
        sp.face([C, G, F, B], WHITE)
        sp.face([E, H, D, A], WHITE)
        # 앞 유리 불빛
        if dot(norm(cross(sub(G, H), sub(C, H))), iso.VIEW) > 0:
            sp.light_poly([H, G, C, D], WARM_WINDOW, 0.75)
        for y in (-0.8, 0.8):
            lamp_front(sp, (3.12, y, 1.35))

    items += [((-0.4, 0, 2.0), body), ((2.7, 0, 2.0), nose)]
    sp.parts(items)


@vehicle("cargo_hauler", 5.6, 2.9, 3.1, "화물 운반차", "달", "ground", tuple(HEADINGS))
def cargo_hauler(sp: Sprite):
    sp.contact_shadow(0, 0, 3.1, 1.8, 0.45)
    r = 0.5
    items = []
    for x in (-1.9, 0.0, 1.9):
        for y in (-1.3, 1.3):
            items.append(((x, y, r), (lambda x=x, y=y: wheel(sp, (x, y, r), r, 0.36))))

    def deck():
        sp.box(-2.7, -1.1, 0.7, 5.4, 2.2, 0.32, DARK, top=STEEL)
        sp.box(2.15, -0.9, 1.02, 0.55, 1.8, 0.7, WHITE, top=DARK)

    def sensor():
        sp.line((2.45, 0.0, 1.72), (2.45, 0.0, 2.5), 0.06, "#9aa1aa")
        sp.cyl((2.45, 0.0, 2.5), (2.45, 0.0, 2.75), 0.18, CHAR)
        sp.lamp((2.72, 0.6, 1.4), WARM_WINDOW, 7)
        sp.lamp((2.72, -0.6, 1.4), WARM_WINDOW, 7)

    def cont1():
        sp.box(-2.5, -0.95, 1.02, 2.1, 1.9, 1.7, ORANGE, top=Mat("#E9965E"))

    def cont2():
        sp.box(-0.2, -0.95, 1.02, 2.1, 1.9, 1.7, WHITE)
        f = Sprite.box_faces(-0.2, -0.95, 1.02, 2.1, 1.9, 1.7)
        o, e1, e2 = f["left"]
        sp.face(sp.on_face(o, e1, e2, 0.0, 0.72, 1.0, 0.84), TEAL, normal=(0, 1, 0), edge=False, ao=0)
        o, e1, e2 = f["right"]
        sp.face(sp.on_face(o, e1, e2, 0.0, 0.72, 1.0, 0.84), TEAL, normal=(1, 0, 0), edge=False, ao=0)

    items += [((0, 0, 0.85), deck), ((-1.45, 0, 1.9), cont1), ((0.85, 0, 1.9), cont2), ((2.45, 0, 2.0), sensor)]
    sp.parts(items)


@vehicle("excavator_robot", 3.4, 2.0, 1.8, "굴착 로봇", "달", "ground", tuple(HEADINGS))
def excavator_robot(sp: Sprite):
    sp.contact_shadow(0, 0, 1.9, 1.2, 0.45)
    items = []
    for x in (-1.25, 1.25):
        def drum(x=x):
            sp.line((0.0, 0.0, 0.95), (x, 0.0, 0.62), 0.2, "#7d848d")
            sp.cyl((x, -0.92, 0.6), (x, 0.92, 0.6), 0.58, STEEL, bands=[0.2, 0.4, 0.6, 0.8], cap_mat=DARK)
        items.append(((x, 0, 0.6), drum))

    def body():
        sp.box(-0.85, -0.65, 0.55, 1.7, 1.3, 0.75, WHITE, top=SILVER)
        sp.box(-0.5, -0.45, 1.3, 1.0, 0.9, 0.08, SOLAR)
        sp.lamp((0.87, 0.4, 1.05), WARM_WINDOW, 6)

    items.append(((0, 0, 0.9), body))
    sp.parts(items)


@vehicle("builder_robot", 6.0, 6.0, 3.4, "건설 로봇", "달", "ground", tuple(HEADINGS))
def builder_robot(sp: Sprite):
    """여섯 다리 끝에 바퀴가 달린 짐 나르기·조립 로봇 (ATHLETE 계열)."""
    sp.contact_shadow(0, 0, 2.9, 2.9, 0.4)
    hexa = [(1.55 * math.cos(math.radians(a)), 1.55 * math.sin(math.radians(a))) for a in range(0, 360, 60)]
    items = []
    for k in range(6):
        a = math.radians(30 + k * 60)
        d = (math.cos(a), math.sin(a), 0.0)
        hip = (1.45 * d[0], 1.45 * d[1], 2.05)
        knee = (2.4 * d[0], 2.4 * d[1], 2.7)
        ft = (2.75 * d[0], 2.75 * d[1], 0.38)

        def leg(hip=hip, knee=knee, ft=ft, d=d):
            sp.line(hip, knee, 0.2, "#c9ccd1")
            sp.line(knee, (ft[0], ft[1], ft[2] + 0.35), 0.18, "#c9ccd1")
            tang = rotz(d, 90)
            sp.cyl(sub(ft, mul(tang, 0.16)), add(ft, mul(tang, 0.16)), 0.36, TIRE, cap_mat=HUB)
        items.append(((knee[0] * 0.8, knee[1] * 0.8, 1.4), leg))

    def deck():
        sp.prism(hexa, 1.85, 0.42, WHITE, top=Mat("#D8D2C4"))
        sp.box(-0.9, -0.9, 2.27, 1.8, 1.8, 1.0, ORANGE, top=Mat("#E9965E"))     # 실은 짐
        sp.lamp((1.5, 0.0, 2.05), WARM_WINDOW, 7)

    def arm():
        sp.polyline3([(1.1, 0.6, 2.27), (1.6, 0.9, 3.3), (2.4, 0.9, 3.0), (2.7, 0.9, 2.4)], "#E9C24A", 0.16)
        sp.box(2.55, 0.75, 2.15, 0.3, 0.3, 0.25, DARK)

    items += [((0, 0, 2.2), deck), ((2.0, 0.9, 3.0), arm)]
    sp.parts(items)


@vehicle("hopper", 4.4, 4.4, 3.8, "로켓 호퍼", "달", "air")
def hopper(sp: Sprite):
    """달의 '헬리콥터'. 공기가 없으니 로터 대신 로켓으로 짧게 뛰어 오른다."""
    sp.contact_shadow(0, 0, 2.2, 2.2, 0.4)
    items = []
    for k in range(4):
        a = math.radians(45 + k * 90)
        d = (math.cos(a), math.sin(a), 0.0)
        top = (0.85 * d[0], 0.85 * d[1], 1.55)
        ft = (2.05 * d[0], 2.05 * d[1], 0.12)

        def leg(top=top, ft=ft):
            sp.line(top, ft, 0.12, "#9aa1aa")
            sp.line((top[0] * 0.8, top[1] * 0.8, 1.0), ft, 0.08, "#9aa1aa")
            foot(sp, ft, 0.32)
        items.append(((ft[0] * 0.7, ft[1] * 0.7, 0.8), leg))

    def core():
        sp.frustum((0, 0, 1.15), (0, 0, 0.55), 0.32, 0.6, DARK, cap_mat=CHAR)
        sp.cyl((0, 0, 1.15), (0, 0, 2.5), 0.95, WHITE, bands=[0.5])
        for y in (-1.05, 1.05):
            sp.sphere((0.0, y, 1.85), 0.55, FOIL)
        sp.box(-0.7, -0.7, 2.5, 1.4, 1.4, 0.9, ORANGE, top=Mat("#E9965E"))
        for d in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            sp.box(d[0] * 0.98 - 0.08, d[1] * 0.98 - 0.08, 2.3, 0.16, 0.16, 0.16, DARK)
        sp.lamp((0.0, 0.0, 3.5), "#ff5a3c", 5)

    items.append(((0, 0, 1.8), core))
    sp.parts(items)


# ── 우주선 ───────────────────────────────────────────────────────────

@vehicle("crew_lander", 10.0, 10.0, 16.5, "유인 착륙선", "달", "space")
def crew_lander(sp: Sprite):
    sp.contact_shadow(0, 0, 5.0, 5.0, 0.45)
    items = []
    for k in range(4):
        a = math.radians(45 + k * 90)
        d = (math.cos(a), math.sin(a), 0.0)
        top = (2.5 * d[0], 2.5 * d[1], 4.2)
        ft = (4.6 * d[0], 4.6 * d[1], 0.12)

        def leg(top=top, ft=ft, d=d):
            sp.line(top, ft, 0.3, "#9aa1aa")
            sp.line((2.4 * d[0], 2.4 * d[1], 1.6), ft, 0.18, "#9aa1aa")
            foot(sp, ft, 0.6)
        items.append(((ft[0] * 0.8, ft[1] * 0.8, 1.5), leg))

    def hull_():
        sp.frustum((0, 0, 0.9), (0, 0, 2.2), 1.9, 2.6, CHAR, caps=False)
        sp.cyl((0, 0, 2.2), (0, 0, 12.8), 2.6, WHITE, bands=[0.14, 0.42, 0.7], band_color="#b3ad9f")
        sp.cyl((0, 0, 2.6), (0, 0, 3.9), 2.62, FOIL, caps=False)
        sp.frustum((0, 0, 12.8), (0, 0, 15.2), 2.6, 1.0, WHITE, cap_mat=STEEL)
        sp.cyl((0, 0, 15.2), (0, 0, 15.9), 0.75, STEEL)
        ang = Sprite.facing_angle((0, 0, 0), (0, 0, 1), norm((0.3, 1.0, 0.0)))
        for k in range(5):
            a0 = ang - 44 + k * 18
            sp.window(Sprite.cyl_patch((0, 0, 10.6), (0, 0, 11.6), 2.6, 0.0, 1.0, a0, a0 + 9))
        sp.lamp((0, 0, 16.05), "#ff5a3c", 6)
        sp.glow((0, 0, 11.1), 46, WARM_WINDOW, 0.25)

    def elevator():
        sp.line((0.0, 2.75, 0.2), (0.0, 2.75, 10.4), 0.12, "#8a9099")
        sp.box(-0.8, 2.7, 0.15, 1.6, 1.3, 0.12, STEEL)
        sp.polyline3([(-0.8, 4.0, 0.27), (-0.8, 4.0, 1.3), (0.8, 4.0, 1.3), (0.8, 4.0, 0.27)], "#E9C24A", 0.06)

    items += [((0, 0, 6.0), hull_), ((0, 3.2, 2.0), elevator)]
    sp.parts(items)


@vehicle("cargo_lander", 9.6, 9.6, 6.2, "화물 착륙선", "달", "space")
def cargo_lander(sp: Sprite):
    sp.contact_shadow(0, 0, 4.8, 4.8, 0.45)
    octa = [(3.2 * math.cos(math.radians(22.5 + 45 * i)), 3.2 * math.sin(math.radians(22.5 + 45 * i)))
            for i in range(8)]
    items = []
    for k in range(4):
        a = math.radians(45 + k * 90)
        d = (math.cos(a), math.sin(a), 0.0)
        top = (3.0 * d[0], 3.0 * d[1], 2.6)
        ft = (4.5 * d[0], 4.5 * d[1], 0.12)

        def leg(top=top, ft=ft, d=d):
            sp.line(top, ft, 0.24, "#9aa1aa")
            sp.line((2.6 * d[0], 2.6 * d[1], 1.4), ft, 0.14, "#9aa1aa")
            foot(sp, ft, 0.5)
        items.append(((ft[0] * 0.75, ft[1] * 0.75, 1.0), leg))
    for k in range(4):
        a = math.radians(k * 90)
        c = (1.7 * math.cos(a), 1.7 * math.sin(a), 1.7)
        items.append(((c[0], c[1], 1.7), (lambda c=c: sp.sphere(c, 0.85, WHITE))))

    def engine():
        sp.frustum((0, 0, 1.9), (0, 0, 0.9), 0.5, 0.95, DARK, cap_mat=CHAR)

    def deck():
        sp.prism(octa, 2.35, 0.6, FOIL, top=STEEL)
        sp.box(-2.2, -1.9, 2.95, 2.0, 1.8, 1.7, ORANGE, top=Mat("#E9965E"))
        sp.box(-0.3, -1.9, 2.95, 2.0, 1.8, 1.7, WHITE)
        sp.box(-1.2, 0.3, 2.95, 2.4, 1.8, 1.4, Mat("#C9CED4", 0.3))
        # 하역 크레인
        sp.polyline3([(2.0, 1.4, 2.95), (2.0, 1.4, 5.6), (0.2, 0.6, 6.0)], "#E9C24A", 0.14)
        sp.line((0.2, 0.6, 6.0), (0.2, 0.6, 4.5), 0.04, "#9aa1aa")
        sp.lamp((2.0, 1.4, 5.75), AMBER, 8)

    items += [((0, 0, 1.4), engine), ((0, 0, 3.2), deck)]
    sp.parts(items)


@vehicle("space_shuttle", 10.6, 10.6, 12.0, "지구-달 셔틀", "지구-달", "space")
def space_shuttle(sp: Sprite):
    """지구 착륙장과 달 기지를 오가며 사람과 짐을 나르는 재사용 셔틀.
    바닥의 열 차폐로 지구 대기에 들어와 엔진을 켜고 내려앉는다. 다리 넷으로 선다."""
    sp.contact_shadow(0, 0, 5.2, 5.2, 0.45)
    rb, zb, rt, zt = 3.8, 4.2, 2.1, 9.6      # 객실 원뿔: 밑(반지름·높이)·위

    def rad(z):
        """몸통 반지름 (원뿔 밑은 원기둥)."""
        return rb + (rt - rb) * (z - zb) / (zt - zb) if z > zb else rb

    def at(z, a, lift=0.03):
        """몸통 겉면의 점 (a: 도)."""
        r = rad(z) + lift
        return (r * math.cos(math.radians(a)), r * math.sin(math.radians(a)), z)

    items = []
    for k in range(4):
        a = math.radians(45 + k * 90)
        d = (math.cos(a), math.sin(a), 0.0)
        top = (3.55 * d[0], 3.55 * d[1], 2.7)
        ft = (4.8 * d[0], 4.8 * d[1], 0.12)

        def leg(top=top, ft=ft, d=d):
            sp.line(top, ft, 0.28, "#9aa1aa")
            sp.line((3.4 * d[0], 3.4 * d[1], 1.2), ft, 0.16, "#9aa1aa")
            foot(sp, ft, 0.5)
        items.append(((ft[0] * 0.8, ft[1] * 0.8, 1.5), leg))

    def engines():
        for k in range(4):
            a = math.radians(45 + k * 90)
            c = (1.5 * math.cos(a), 1.5 * math.sin(a))
            sp.frustum((c[0], c[1], 1.0), (c[0], c[1], 0.45), 0.32, 0.55, DARK, cap_mat=CHAR)

    def hull_():
        sp.frustum((0, 0, 1.0), (0, 0, 1.6), 3.2, rb, CHAR, cap_mat=CHAR)      # 열 차폐
        sp.cyl((0, 0, 1.6), (0, 0, zb), rb, WHITE, caps=False, bands=[0.12], band_color="#b3ad9f")
        sp.frustum((0, 0, zb), (0, 0, zt), rb, rt, WHITE, bands=[0.36, 0.66], band_color="#b3ad9f")
        sp.frustum((0, 0, zb + 0.15), (0, 0, zb + 0.55), rad(zb + 0.15) + 0.02, rad(zb + 0.55) + 0.02, TEAL,
                   caps=False)
        sp.frustum((0, 0, zt), (0, 0, 10.7), rt, 1.15, WHITE, cap_mat=STEEL)
        sp.cyl((0, 0, zt - 0.08), (0, 0, zt + 0.08), rt + 0.05, STEEL, caps=False)  # 이음 고리
        sp.cyl((0, 0, 10.7), (0, 0, 11.6), 0.8, STEEL, cap_mat=DARK)           # 도킹 포트
        # 창 (꼭대기 가까이 한 바퀴)
        for k in range(12):
            a = 45 + 30 * k
            sp.window([at(8.0, a - 6.5), at(8.0, a + 6.5), at(8.6, a + 6.5), at(8.6, a - 6.5)])
        sp.glow((0, 0, 8.3), 44, WARM_WINDOW, 0.25)
        # 짐칸 문 (+y쪽)
        door = ([at(1.85, a) for a in range(68, 113, 11)] + [at(4.0, a) for a in range(112, 67, -11)])
        sp.polyline3(door, "#7d848d", 0.07, closed=True)
        sp.line(at(1.85, 90), at(4.0, 90), 0.05, "#7d848d")
        for a in (76, 104):
            sp.lamp(at(4.12, a, 0.1), WARM_WINDOW, 7)
        # 자세 제어 분사기 (RCS)
        for k in range(4):
            a = k * 90
            c = at(9.2, a, 0.1)
            sp.box(c[0] - 0.15, c[1] - 0.15, 9.05, 0.3, 0.3, 0.34, STEEL, top=DARK)
        sp.lamp(at(9.5, 90, 0.25), "#ff4a3a", 5)
        sp.lamp(at(9.5, 0, 0.25), "#7CF29A", 5)
        sp.lamp((0, 0, 11.78), "#ff5a3c", 6)

    items += [((0, 0, 0.7), engines), ((0, 0, 6.0), hull_)]
    sp.parts(items)


@vehicle("orbital_tug", 16.0, 26.0, 4.0, "궤도 예인선", "지구-달 궤도", "space", flying=True)
def orbital_tug(sp: Sprite):
    items = []

    def wing(side):
        def f():
            sp.line((0.4, side * 1.6, 0.0), (0.4, side * 2.6, 0.0), 0.12, "#9aa1aa")
            o = (-1.0, side * 2.6, 0.0)
            e1 = (2.8, 0.0, 0.0)
            e2 = (0.0, side * 10.0, 0.0)
            sp.quad(o, e1, e2, SOLAR, back=Mat("#5b6470"))
            sp.panel_grid(o, e1, e2, 2, 8, "#6f86b0", 0.45, 0.6)
        return f

    def core():
        sp.frustum((-4.2, 0, 0), (-5.8, 0, 0), 0.5, 1.15, COPPER, cap_mat=CHAR)
        sp.cyl((-4.2, 0, 0), (4.0, 0, 0), 1.6, WHITE, bands=[0.1, 0.5, 0.9], band_color="#b3ad9f", cap_mat=STEEL)
        sp.cyl((-1.0, 0, 0), (1.4, 0, 0), 1.63, FOIL, caps=False)
        sp.cyl((4.0, 0, 0), (4.6, 0, 0), 0.6, STEEL)
        sp.box(4.6, -1.3, -1.3, 2.8, 2.6, 2.6, ORANGE, top=Mat("#E9965E"))
        sp.lamp((4.3, 0, 1.0), "#7CF29A", 5)

    items += [((0.4, -6.0, 0), wing(-1)), ((0, 0, 0), core), ((0.4, 6.0, 0), wing(1))]
    sp.parts(items)


@vehicle("transport_ship", 60.0, 30.0, 16.0, "행성간 수송선", "태양계", "space", flying=True)
def transport_ship(sp: Sprite):
    items = []

    def spine():
        sp.truss((-29.0, 0, 0), (23.0, 0, 0), 1.6, "#9aa1aa", 0.14, 26, side=(0, 0, 1))

    def reactor():
        sp.frustum((-30.0, 0, 0), (-33.5, 0, 0), 0.9, 2.2, COPPER, cap_mat=CHAR)
        sp.cyl((-28.0, 0, 0), (-30.0, 0, 0), 1.3, DARK)
        sp.frustum((-27.8, 0, 0), (-26.6, 0, 0), 2.4, 1.2, STEEL)
        sp.glow((-33.5, 0, 0), 30, "#9fd8ff", 0.5)

    def radiators(side):
        def f():
            o = (-24.0, side * 1.0, 0.0)
            sp.quad(o, (13.0, 0, 0), (0, side * 9.0, 0), RADIATOR, back=RADIATOR)
            sp.panel_grid(o, (13.0, 0, 0), (0, side * 9.0, 0), 10, 1, "#b9bec4", 0.5, 0.7)
        return f

    def tanks():
        for x0, x1, m in ((-22.0, -13.0, WHITE), (-11.0, -2.0, Mat("#D9893F", 0.1)), (0.0, 9.0, WHITE)):
            sp.cyl((x0, 0, 2.8), (x1, 0, 2.8), 2.4, m, bands=[0.5], cap_mat=m)
            sp.cyl((x0, 0, -2.8), (x1, 0, -2.8), 2.4, m, bands=[0.5], cap_mat=m)

    def crew():
        sp.cyl((12.0, 0, 0), (21.0, 0, 0), 2.2, WHITE, bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
        ang = Sprite.facing_angle((12.0, 0, 0), (21.0, 0, 0), norm((0.0, 1.0, 0.6)))
        for s in (0.15, 0.4, 0.65):
            sp.window(Sprite.cyl_patch((12.0, 0, 0), (21.0, 0, 0), 2.2, s, s + 0.08, ang - 12, ang + 12))
        sp.cyl((21.0, 0, 0), (22.6, 0, 0), 0.8, STEEL)
        sp.lamp((22.7, 0, 1.0), "#7CF29A", 6)

    def ring():
        # 인공중력 고리 (회전)
        sp.ring3((16.5, 0, 0), 8.0, "#d9d4c8", 1.0, normal=(1, 0, 0), front_only=False)
        sp.ring3((16.5, 0, 0), 8.0, "#9a958a", 0.25, normal=(1, 0, 0), front_only=False, opacity=0.6)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            sp.line((16.5, 0, 0), (16.5, 8.0 * math.cos(a), 8.0 * math.sin(a)), 0.2, "#b8b2a6")

    items += [((-6.0, 0, 0), spine), ((-30.0, 0, 0), reactor), ((-17.5, -5.5, 0), radiators(-1)),
              ((-17.5, 5.5, 0), radiators(1)), ((-6.0, 0, 0.5), tanks), ((16.5, 0, -0.5), ring),
              ((16.6, 0, 0.6), crew)]
    sp.parts(items)


# ── 대기가 있는 세계의 비행체 ─────────────────────────────────────────

def rotor(sp: Sprite, c, r: float, blades: int = 2, phase: float = 20.0, color="#3a3f47"):
    """도는 로터: 반투명 원판 + 날개깃."""
    pts = [iso.P(c[0] + r * math.cos(2 * math.pi * i / 36), c[1] + r * math.sin(2 * math.pi * i / 36), c[2])
           for i in range(36)]
    sp.poly2(pts, "#ffffff", "#d0d4da", 0.4, 0.14)
    sp.glass_disc(c, (0, 0, 1), r)
    for b in range(blades):
        a = math.radians(phase + 360.0 * b / blades)
        tip = (c[0] + r * math.cos(a), c[1] + r * math.sin(a), c[2])
        sp.line(c, tip, 0.12, color)
    sp.cyl((c[0], c[1], c[2] - 0.12), (c[0], c[1], c[2] + 0.08), 0.12, DARK, edge=False)


@vehicle("mars_helicopter", 6.0, 6.0, 2.6, "화성 헬리콥터", "화성", "air", flying=True)
def mars_helicopter(sp: Sprite):
    """대기가 지구의 1%라 로터가 크고 빠르게 돈다. 무인 정찰·짐 나르기."""
    sp.contact_shadow(0, 0, 1.6, 1.6, 0.35)
    items = []
    for k in range(6):
        a = math.radians(k * 60)
        hub = (2.0 * math.cos(a), 2.0 * math.sin(a), 1.75)

        def arm(hub=hub):
            sp.line((0, 0, 1.45), hub, 0.1, "#c9ccd1")
            rotor(sp, hub, 1.15, 2, 25 + hub[0] * 20)
        items.append(((hub[0], hub[1], 1.75), arm))

    def body():
        for k in range(4):
            a = math.radians(45 + 90 * k)
            sp.line((0.45 * math.cos(a), 0.45 * math.sin(a), 0.9), (1.0 * math.cos(a), 1.0 * math.sin(a), 0.05), 0.07,
                    "#9aa1aa")
        sp.cyl((0, 0, 0.8), (0, 0, 1.5), 0.62, WHITE, bands=[0.5])
        sp.sphere((0, 0, 1.5), 0.62, WHITE, clip_z=1.5)
        sp.quad((-0.7, -0.7, 2.25), (1.4, 0, 0), (0, 1.4, 0), SOLAR, back=STEEL)
        sp.line((0, 0, 1.9), (0, 0, 2.25), 0.08, "#9aa1aa")
        sp.lamp((0.6, 0.0, 1.0), WARM_WINDOW, 6)

    items.append(((0, 0, 1.4), body))
    sp.parts(items)


@vehicle("titan_rotorcraft", 6.0, 5.0, 2.8, "타이탄 회전익기", "타이탄", "air", flying=True)
def titan_rotorcraft(sp: Sprite):
    """대기가 지구의 1.5배, 중력은 1/7 — 태양계에서 가장 날기 쉬운 곳. 로터 여덟 개 (위아래 한 쌍씩)."""
    sp.contact_shadow(0, 0, 2.2, 1.4, 0.35)
    items = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            hub = (sx * 2.1, sy * 1.7, 1.75)

            def arm(hub=hub, sx=sx, sy=sy):
                sp.line((sx * 1.2, sy * 0.6, 1.5), hub, 0.12, "#c9ccd1")
                rotor(sp, (hub[0], hub[1], hub[2] + 0.35), 0.85, 2, 40 + sx * 30)
                rotor(sp, (hub[0], hub[1], hub[2] - 0.05), 0.85, 2, 100 + sy * 30)
            items.append(((hub[0], hub[1], hub[2]), arm))

    def body():
        for y in (-0.75, 0.75):
            sp.line((-1.4, y, 0.05), (1.6, y, 0.05), 0.1, "#9aa1aa")
            for x in (-0.9, 0.9):
                sp.line((x, y, 0.05), (x, y * 0.8, 0.75), 0.07, "#9aa1aa")
        sp.box(-1.6, -0.85, 0.75, 3.2, 1.7, 1.05, FOIL, top=WHITE)
        sp.disc((0.2, 0.0, 2.0), norm((0.4, 0.3, 1.0)), 0.55, WHITE, back=STEEL)
        sp.line((0.2, 0.0, 1.8), (0.2, 0.0, 2.0), 0.06, "#9aa1aa")
        # 뒤쪽 원자력 전지 (방열 지느러미)
        sp.cyl((-1.6, 0, 1.3), (-2.4, 0, 1.3), 0.35, DARK, cap_mat=CHAR)
        for k in range(6):
            a = math.radians(k * 60)
            sp.line((-2.0, 0.35 * math.cos(a), 1.3 + 0.35 * math.sin(a)),
                    (-2.0, 0.6 * math.cos(a), 1.3 + 0.6 * math.sin(a)), 0.5, "#454b55")
        sp.lamp((1.62, 0.4, 1.2), WARM_WINDOW, 6)
        sp.lamp((1.62, -0.4, 1.2), WARM_WINDOW, 6)

    items.append(((0, 0, 1.2), body))
    sp.parts(items)


@vehicle("mars_plane", 9.0, 22.0, 2.0, "화성 비행기", "화성", "air", flying=True)
def mars_plane(sp: Sprite):
    """대기가 얇아 날개가 길다 (날개폭 22 m). 태양전지 날개와 큰 프로펠러로 넓은 지역을 조사한다."""
    items = []

    def wing():
        o = (0.0, -11.0, 0.6)
        sp.quad(o, (1.4, 0, 0), (0, 22.0, 0), Mat("#E6E2D8", 0.2), back=Mat("#B9B4AA"))
        sp.panel_grid(o, (1.4, 0, 0), (0, 22.0, 0), 1, 14, "#9aa4b5", 0.45, 0.5)
        sp.quad((0.15, -9.5, 0.62), (1.0, 0, 0), (0, 7.5, 0), SOLAR, back=STEEL)
        sp.quad((0.15, 2.0, 0.62), (1.0, 0, 0), (0, 7.5, 0), SOLAR, back=STEEL)

    def fuselage():
        sp.cyl((-4.6, 0, 0.4), (2.2, 0, 0.4), 0.42, WHITE, cap_mat=WHITE)
        sp.frustum((2.2, 0, 0.4), (3.4, 0, 0.4), 0.42, 0.08, WHITE)
        sp.quad((-4.6, -2.2, 0.45), (0.9, 0, 0), (0, 4.4, 0), Mat("#E6E2D8"), back=Mat("#B9B4AA"))
        sp.quad((-4.6, 0.0, 0.45), (0.9, 0, 0), (0.3, 0, 1.4), ORANGE, back=ORANGE)
        sp.lamp((3.3, 0, 0.45), WARM_WINDOW, 5)

    def props(side):
        def f():
            c = (1.3, side * 4.0, 0.6)
            sp.cyl((1.0, side * 4.0, 0.6), (1.7, side * 4.0, 0.6), 0.22, STEEL, edge=False)
            pts = []
            for i in range(36):
                t = 2 * math.pi * i / 36
                pts.append(iso.P(1.75, side * 4.0 + 1.7 * math.cos(t), 0.6 + 1.7 * math.sin(t)))
            sp.poly2(pts, "#ffffff", "#d0d4da", 0.4, 0.15)
            sp.glass_disc((1.75, side * 4.0, 0.6), (1, 0, 0), 1.7)
            sp.line((1.75, side * 4.0 - 1.6, 0.6), (1.75, side * 4.0 + 1.6, 0.6), 0.12, "#3a3f47")
        return f

    items += [((0.7, 0, 0.6), wing), ((-1.0, 0, 0.4), fuselage), ((1.7, -4.0, 0.6), props(-1)),
              ((1.7, 4.0, 0.6), props(1))]
    sp.parts(items)


@vehicle("venus_airship", 32.0, 10.0, 10.0, "금성 비행선", "금성", "air", flying=True)
def venus_airship(sp: Sprite):
    """고도 50 km의 금성 구름은 1기압·30~70°C — 사람이 숨 쉬는 공기(질소·산소)만으로도 뜬다."""
    items = []

    def fins():
        for (a, b) in (((-14.0, 0, 6.0), (0, 0, 3.4)), ((-14.0, 0, 6.0), (0, 0, -3.4)),
                       ((-14.0, 0, 6.0), (0, 3.4, 0)), ((-14.0, 0, 6.0), (0, -3.4, 0))):
            sp.quad(a, (2.6, 0, 0), b, Mat("#C9A23A", 0.4), back=Mat("#A88A35", 0.3))

    def envelope():
        sp.ellipsoid((0, 0, 6.0), 15.0, 4.2, 4.2, Mat("#E8DEC6", 0.3))
        for x in (-9.0, -4.5, 0.0, 4.5, 9.0):
            k = math.sqrt(max(0.0, 1 - (x / 15.0) ** 2))
            sp.ring3((x, 0, 6.0), 4.2 * k, "#bfb39a", 0.08, normal=(1, 0, 0), opacity=0.7)
        sp.polyline3([(x, 0.0, 6.0 + 4.2 * math.sqrt(max(0.0, 1 - (x / 15.0) ** 2))) for x in
                      [-12 + i for i in range(25)]], "#2a3d66", 0.8, 0.9)

    def gondola():
        sp.line((-2.0, 0.0, 1.9), (-2.0, 0.0, 2.6), 0.1, "#8a9099")
        sp.line((3.0, 0.0, 1.9), (3.0, 0.0, 2.4), 0.1, "#8a9099")
        sp.cyl((-4.0, 0, 1.2), (4.5, 0, 1.2), 0.85, WHITE, cap_mat=WHITE)
        ang = Sprite.facing_angle((-4.0, 0, 1.2), (4.5, 0, 1.2), norm((0.0, 1.0, 0.1)))
        for s in (0.15, 0.35, 0.55, 0.75):
            sp.window(Sprite.cyl_patch((-4.0, 0, 1.2), (4.5, 0, 1.2), 0.85, s, s + 0.1, ang - 15, ang + 15))
        for y in (-4.6, 4.6):
            sp.line((-11.5, y * 0.75, 4.2), (-11.5, y, 4.2), 0.1, "#8a9099")
            pts = [iso.P(-11.6, y + 1.3 * math.cos(2 * math.pi * i / 30), 4.2 + 1.3 * math.sin(2 * math.pi * i / 30))
                   for i in range(30)]
            sp.poly2(pts, "#ffffff", "#d0d4da", 0.4, 0.15)
            sp.glass_disc((-11.6, y, 4.2), (1, 0, 0), 1.3)

    items += [((-13.0, 0, 6.0), fins), ((0, 0, 6.0), envelope), ((0, 0, 1.0), gondola)]
    sp.parts(items)


# ── 지구의 하늘 ──────────────────────────────────────────────────────

PAINT = Mat("#F3F2EE", 0.3)              # 여객기 흰 도장
WING = Mat("#C9CED4", 0.3)               # 날개 회색 도장
WING_UNDER = Mat("#AEB4BB", 0.2)
LIVERY = BLUE                            # 꼬리 날개·윙렛
COCKPIT = Mat("#1C2A38", 0.25)           # 조종석 유리 (눈부심이 적다)


def toward(pts, want):
    """법선이 want 쪽을 보도록 꼭짓점 순서를 맞춘다."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return list(pts) if dot(n, want) > 0 else list(reversed(pts))


def lerp3(a, b, t):
    return add(a, mul(sub(b, a), t))


def slab(sp: Sprite, le0, te0, le1, te1, t0: float, t1: float, up, mat: Mat, under: Mat | None = None):
    """두께 있는 날개: 뿌리(le0·te0)와 끝(le1·te1)의 앞·뒷전 (가운데 면), 두께 t0·t1, up = 두께 방향.
    뿌리 면은 동체 속이라 적지 않는다. 윗면·아랫면 꼭짓점(뿌리 앞전·뿌리 뒷전·끝 뒷전·끝 앞전)을 돌려준다."""
    h0, h1 = mul(up, t0 / 2), mul(up, t1 / 2)
    a0, b0, a1, b1 = add(le0, h0), add(te0, h0), add(le1, h1), add(te1, h1)
    c0, d0, c1, d1 = sub(le0, h0), sub(te0, h0), sub(le1, h1), sub(te1, h1)
    fwd = sub(le0, te0)
    sp.face(toward([c0, d0, d1, c1], mul(up, -1)), under or mat)
    sp.face(toward([b0, b1, d1, d0], mul(fwd, -1)), mat)
    sp.face(toward([a1, b1, d1, c1], sub(add(le1, te1), add(le0, te0))), mat)
    sp.face(toward([a0, a1, c1, c0], fwd), mat)
    sp.face(toward([a0, b0, b1, a1], up), mat)
    return (a0, b0, b1, a1), (c0, d0, d1, c1)


@vehicle("airliner", 40.0, 36.0, 12.0, "여객기", "지구", "air", flying=True)
def airliner(sp: Sprite):
    """쌍발 제트 여객기 (A320·737 크기). 바퀴를 내린 모습 — 바퀴 밑이 z=0이라 활주로에 그대로 닿는다."""
    R, zc = 2.0, 3.9                         # 동체 반지름·중심 높이
    xn, rx = 16.2, 3.8                       # 기수 타원체 (끝이 x=20)
    x0 = -11.5                               # 원통 동체 뒤끝
    tail = (-20.0, 0.0, zc + 1.65)           # 꼬리 원뿔 끝 (보조 동력 장치 배기구)

    def surf(x, t, lift=0.03):
        """원통 동체 겉면의 점. t: cyl_patch의 각도 (+y쪽은 180°+올려본 각, -y쪽은 -올려본 각)."""
        r = R + lift
        return (x, -r * math.cos(math.radians(t)), zc - r * math.sin(math.radians(t)))

    def nose(x, a, lift=0.06):
        """기수 겉면의 점. a: +y에서 위로 잰 각."""
        k = math.sqrt(max(0.0, 1.0 - ((x - xn) / rx) ** 2))
        p = (x, R * k * math.cos(math.radians(a)), zc + R * k * math.sin(math.radians(a)))
        return add(p, mul(norm(((p[0] - xn) / rx ** 2, p[1] / R ** 2, (p[2] - zc) / R ** 2)), lift))

    def gear(x, y, top, r, w):
        sp.line((x, y, top), (x, y, r), 0.24 if r > 0.5 else 0.16, "#9aa1aa")
        sp.cyl((x, y - w, r), (x, y + w, r), r, TIRE, cap_mat=HUB, bands=[0.5], band_color="#24272c")

    def engine(side):
        y, z, r = side * 5.75, 1.6, 1.08
        sp.frustum((-1.5, y, z), (-2.5, y, z), 0.55, 0.12, STEEL)                    # 배기 원뿔
        sp.frustum((-1.5, y, z), (3.4, y, z), 0.82, r, PAINT, cap_mat=DARK)          # 나셀 (앞 뚜껑이 팬)
        sp.ring3((3.4, y, z), r - 0.04, "#c9ced4", 0.16, normal=(1, 0, 0), front_only=False)
        sp.frustum((3.4, y, z), (3.65, y, z), 0.3, 0.03, SILVER)                      # 스피너
        sp.face(toward([(-1.0, y, 2.35), (2.7, y, 2.35), (0.9, y, 3.05), (-1.0, y, 3.05)], (0, side, 0)),
                WING, two_sided=True, back=WING)                                      # 파일런

    def wing(side):
        def f():
            le1, te1 = (-5.2, side * 17.55, 4.0), (-6.8, side * 17.55, 4.0)
            near = [lambda: engine(side), lambda: gear(-1.0, side * 3.8, 2.6, 0.58, 0.5)]
            for fn in (near if side < 0 else near[::-1]):        # 카메라에서 먼 것부터
                fn()
            slab(sp, (3.2, side * 1.3, 2.6), (-4.4, side * 1.3, 2.6), le1, te1, 0.7, 0.2, (0, 0, 1), WING,
                 WING_UNDER)
            a, b = add(le1, (-0.15, 0, 0.1)), add(te1, (0.05, 0, 0.1))           # 윙렛
            sp.face(toward([a, b, add(b, (-0.5, side * 0.45, 1.9)), add(a, (-1.3, side * 0.45, 1.9))], (0, side, 0)),
                    LIVERY, two_sided=True, back=LIVERY)
            sp.lamp(add(le1, (0.1, side * 0.15, 0.0)), "#ff4a3a" if side > 0 else "#7CF29A", 8)
        return f

    def hstab(side):
        sp.face(toward([(-14.4, side * 0.3, 5.0), (-18.4, side * 0.3, 5.0), (-19.5, side * 6.3, 5.6),
                        (-17.8, side * 6.3, 5.6)], (0, 0, 1)), WING, two_sided=True, back=WING_UNDER)

    def cabin(side):
        """창 줄 (긴 유리 하나를 흰 칸막이로 나눈다)과 앞뒤 문."""
        a0, a1 = (186.0, 197.0) if side > 0 else (-17.0, -6.0)
        L = xn - x0
        pts = Sprite.cyl_patch((x0, 0, zc), (xn, 0, zc), R, (-9.2 - x0) / L, (13.8 - x0) / L, a0, a1, 0.03)
        sp.window(pts)
        sp.panel_grid(pts[0], sub(pts[3], pts[0]), sub(pts[1], pts[0]), 30, 1, "#f3f2ee", 2.8, 1.0)
        d0, d1 = (160.0, 215.0) if side > 0 else (-35.0, 20.0)
        ts = [d0 + (d1 - d0) * i / 4 for i in range(5)]
        for xa in (14.3, -10.4):
            sp.polyline3([surf(xa, t) for t in ts] + [surf(xa + 0.85, t) for t in reversed(ts)], "#a3a9b1",
                         0.06, closed=True)

    def body():
        hstab(-1)
        gear(15.0, 0.0, zc - 1.0, 0.38, 0.32)                                # 앞바퀴
        sp.lamp((-0.6, 0.0, zc - R - 0.42), "#ff5a3c", 6)                    # 배 쪽 충돌 방지등
        sp.ellipsoid((-0.6, 0.0, zc - 1.6), 6.6, 1.8, 0.8, PAINT)            # 날개 뿌리 덮개
        sp.frustum((x0 + 0.5, 0, zc), tail, R, 0.35, PAINT, caps=False)       # 기운 원뿔: 동체 속에서 시작
        sp.disc(tail, norm(sub(tail, (x0 + 0.5, 0, zc))), 0.35, DARK, two_sided=False)
        cabin(-1)                                  # 먼 쪽: 선은 가려지지 않으니 동체보다 먼저
        sp.ellipsoid((xn, 0, zc), rx, R, R, PAINT)
        sp.cyl((x0, 0, zc), (xn, 0, zc), R, PAINT, caps=False)
        cabin(1)
        for s in (1, -1):                          # 조종석 창: 앞 두 장, 옆 두 장씩
            for xa, xb, a0, a1 in ((18.85, 18.05, 60, 88), (18.45, 17.7, 31, 56), (17.55, 16.95, 33, 52)):
                if s < 0:
                    a0, a1 = 180 - a1, 180 - a0
                pts = [nose(xa, a0), nose(xa, a1), nose(xb, a1), nose(xb, a0)]
                c = mul(add(pts[0], pts[2]), 0.5)
                sp.window(toward(pts, sub(c, (xn, 0, zc))), glass=COCKPIT, light_alpha=0.7)
        top, bot = slab(sp, (-12.6, 0, 5.75), (-19.3, 0, 5.75), (-17.0, 0, 12.0), (-19.9, 0, 12.0), 0.55, 0.2,
                        (0, 1, 0), PAINT)
        for c, s in ((top, 1), (bot, -1)):         # 꼬리 날개 도장
            def P(u, v, c=c):
                return lerp3(lerp3(c[0], c[1], u), lerp3(c[3], c[2], u), v)
            sp.face(toward([P(0, 0.4), P(1, 0.04), P(1, 1), P(0, 1)], (0, s, 0)), LIVERY)
        hstab(1)
        sp.lamp((-1.0, 0.0, zc + R + 0.08), "#ff5a3c", 6)                    # 위 충돌 방지등
        sp.lamp(add(tail, (-0.1, 0, 0)), "#ffffff", 6)                       # 꼬리등
        sp.lamp((15.25, 0.0, 1.25), WARM_WINDOW, 9)                          # 착륙등

    sp.parts([((-1.0, -9.0, 2.5), wing(-1)), ((0.0, 0.0, zc), body), ((-1.0, 9.0, 2.5), wing(1))])


# ── 사람 (크기 기준) ─────────────────────────────────────────────────

@vehicle("astronaut", 0.8, 0.7, 1.85, "우주비행사 (키 1.85 m)", "달", "people", tuple(HEADINGS))
def astronaut(sp: Sprite):
    sp.contact_shadow(0, 0, 0.45, 0.35, 0.45)
    suit = Mat("#ECE7DC", 0.1)
    items = []
    for y in (-0.13, 0.13):
        items.append(((0.0, y, 0.4), (lambda y=y: sp.cyl((0.0, y, 0.0), (0.0, y, 0.82), 0.11, suit, edge=False))))

    def torso():
        sp.box(-0.16, -0.24, 0.8, 0.32, 0.48, 0.62, suit)
        sp.box(-0.2, -0.05, 1.2, 0.06, 0.1, 0.12, ORANGE)
        for y in (-0.3, 0.3):
            sp.line((0.0, y, 1.35), (0.12, y * 1.1, 0.95), 0.18, "#d9d3c6")

    def pack():
        sp.box(-0.42, -0.22, 0.86, 0.26, 0.44, 0.62, Mat("#C9CED4", 0.2))

    def head():
        sp.sphere((0.0, 0.0, 1.62), 0.19, suit)
        sp.disc((0.12, 0.0, 1.62), (1.0, 0.0, 0.1), 0.13, FOIL, two_sided=False, edge=False)

    items += [((0.0, 0.0, 1.1), torso), ((-0.29, 0.0, 1.15), pack), ((0.0, 0.0, 1.62), head)]
    sp.parts(items)
