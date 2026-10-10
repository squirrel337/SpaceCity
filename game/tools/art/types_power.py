"""전력 묶음 — 새 건물 종류 24종 (태양광 타워·핵분열로·배터리·재생 연료전지·방열판 계열).

종류마다 fn(sp, v) 하나가 같은 기능의 다섯 모양(v0~v4)을 그린다. v0이 대표 모양이다.
좌표는 미터, 원점 = 바닥 가운데. x는 화면 오른쪽 아래, y는 왼쪽 아래, z는 위. 뒤(x + y가 작은 쪽)에서 앞으로 그린다.
"""
from __future__ import annotations

import math

from types_common import *  # noqa: F401,F403

# ── 재질·불빛 ───────────────────────────────────────────────────────────
BATT = Mat("#5B6470", 0.2)
BATT_TOP = Mat("#7A8490", 0.2)
SLEEK = Mat("#2D333C", 0.55)
SLEEK_TOP = Mat("#363C46", 0.45)
RUST = Mat("#9A4F2E", 0.15)
RUST_DARK = Mat("#6B3823", 0.1)
BEIGE = Mat("#D9CBA6", 0.08)
BEIGE_TOP = Mat("#E6DBBE", 0.08)
MIRROR = Mat("#DCE6EE", 0.95)
GLASSY = Mat("#2E2A27", 0.85)          # 녹여 굳힌 레골리스의 유리질 윗면
CAN_BLUE = Mat("#2F5E9E", 0.35)
STRIP_BLUE = Mat("#4F94E8", 0.4)
GAS = Mat("#5F7D72", 0.3)              # 압축 기체 실린더 (회녹색)
RTG = Mat("#474D56", 0.3)
WHITE_REF = Mat("#EEF1F2", 0.5)        # 양면 패널 아래 반사 깔개
HALL = Mat("#E4DED2", 0.05)

RED_LIGHT = "#ff5a3c"
HOT = "#ffb35c"
GREEN_LIGHT = "#7CF29A"
BLUE_LIGHT = "#6FB6FF"
SALT = "#ff8a3a"
PLASMA = "#d78cff"

SUN = norm((-0.42, 0.88, 0.50))         # 해 쪽 (화면 왼쪽, 낮게)
SUN_E1 = norm((-5.8, 1.1, 0.0))        # 해를 보는 세운 판의 가로 방향 (기본 타워와 같다)
SUN_N = norm(cross(SUN_E1, (0.0, 0.0, 1.0)))   # 그 판의 앞면 법선 (해 쪽)


# ── 공용 부품 ───────────────────────────────────────────────────────────

def _solar(sp: Sprite, o, e1, e2, cols=4, rows=4, back: Mat = STEEL, frame="#c0c6ce"):
    """태양전지 판 (격자 + 테두리)."""
    sp.quad(o, e1, e2, SOLAR, back=back)
    sp.panel_grid(o, e1, e2, cols, rows, "#6f86b0", 0.55, 0.6)
    sp.polyline3([o, add(o, e1), add(add(o, e1), e2), add(o, e2), o], frame, 0.08)


def _sun_panel(sp: Sprite, cx, cy, z0, w, h, off=0.0, cols=4, rows=4, back: Mat = STEEL):
    """(cx, cy) 기둥에 해 쪽으로 off만큼 띄워 세운 판."""
    o = (cx - SUN_E1[0] * w / 2 + SUN_N[0] * off, cy - SUN_E1[1] * w / 2 + SUN_N[1] * off, z0)
    _solar(sp, o, mul(SUN_E1, w), (0.0, 0.0, h), cols, rows, back)


def _rad(sp: Sprite, o, e1, e2, n1=4, n2=1, mat: Mat = RADIATOR, color="#b9bec4"):
    """양면 방열판."""
    sp.quad(o, e1, e2, mat, back=mat)
    sp.panel_grid(o, e1, e2, n1, n2, color, 0.5, 0.7)


def _circle(c, e1, e2, r, n=20, a0=0.0):
    return [add(c, add(mul(e1, r * math.cos(a0 + 2 * math.pi * i / n)), mul(e2, r * math.sin(a0 + 2 * math.pi * i / n))))
            for i in range(n)]


def _trefoil(sp: Sprite, c, e1, e2, r, bg: Mat | None = YELLOW, square: bool = False):
    """방사능 표지 (노란 바탕에 검은 세 날개). e1·e2는 판 위의 단위 벡터 (e1 × e2 = 바깥 법선)."""
    n = norm(cross(e1, e2))
    if bg is not None:
        if square:
            pts = [add(c, add(mul(e1, sx * r * 1.25), mul(e2, sy * r * 1.25)))
                   for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        else:
            pts = _circle(c, e1, e2, r * 1.2, 24)
        sp.face(pts, bg, normal=n, ao=0, edge=False)
    for k in range(3):
        mid = math.radians(90 + k * 120)
        outer = [mid - math.radians(30) + math.radians(60) * i / 6 for i in range(7)]
        pts = [add(c, add(mul(e1, r * math.cos(a)), mul(e2, r * math.sin(a)))) for a in outer]
        pts += [add(c, add(mul(e1, r * 0.32 * math.cos(a)), mul(e2, r * 0.32 * math.sin(a)))) for a in reversed(outer)]
        sp.face(pts, CHAR, normal=n, ao=0, edge=False)
    sp.face(_circle(c, e1, e2, r * 0.18, 12), CHAR, normal=n, ao=0, edge=False)


def _louvers(sp: Sprite, frame, u0, u1, v0, v1, n, mat: Mat = CHAR, fill=0.5):
    """상자 면 위의 가로 루버."""
    o, e1, e2 = frame
    nrm = norm(cross(e1, e2))
    step = (v1 - v0) / n
    for i in range(n):
        v = v0 + i * step
        sp.face(sp.on_face(o, e1, e2, u0, v, u1, v + step * fill), mat, normal=nrm, edge=False, ao=0)


def _strip(sp: Sprite, frame, u0, u1, v0, v1, mat: Mat, glow: str, alpha=0.8):
    """면 위의 색 띠 — 밤에 glow로 빛난다."""
    o, e1, e2 = frame
    pts = sp.on_face(o, e1, e2, u0, v0, u1, v1)
    sp.face(pts, mat, normal=norm(cross(e1, e2)), edge=False, ao=0)
    sp.mark_light(glow, alpha)
    sp.light_poly(pts, glow, alpha * 0.9)


def _guy(sp: Sprite, a, b, color="#b3b8bf"):
    sp.line(a, b, 0.05, color, 0.9)


def _depth(p) -> float:
    return dot(p, VIEW)


# ── 태양광 타워 계열 ────────────────────────────────────────────────────

def _lattice(sp: Sprite, z0, z1, a0, a1, bay=1.8, leg="#a7adb5", brace="#8a9098", bands=None):
    """네 다리 격자 탑 (아래 반너비 a0 → 위 a1). bands=(색1, 색2, 길이)면 다리를 번갈아 칠한다 (항공 표지)."""
    n = max(1, int(round((z1 - z0) / bay)))

    def at(sx, sy, t):
        a = a0 + (a1 - a0) * t
        return (sx * a, sy * a, z0 + (z1 - z0) * t)

    def braces(ca, cb):
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            p, q = (at(*ca, t0), at(*cb, t1)) if i % 2 == 0 else (at(*cb, t0), at(*ca, t1))
            sp.line(p, q, 0.05, brace)
            sp.line(at(*ca, t1), at(*cb, t1), 0.05, brace)

    def legline(c):
        if not bands:
            sp.line(at(*c, 0.0), at(*c, 1.0), 0.13, leg)
            return
        c1, c2, step = bands
        m = max(1, int(round((z1 - z0) / step)))
        for i in range(m):
            sp.line(at(*c, i / m), at(*c, (i + 1) / m), 0.15, c1 if i % 2 == 0 else c2)

    braces((-1, -1), (1, -1))
    braces((-1, 1), (-1, -1))
    for c in ((-1, -1), (1, -1), (-1, 1)):
        legline(c)
    braces((1, -1), (1, 1))
    braces((1, 1), (-1, 1))
    legline((1, 1))


@typed("tall_solar_tower", 7, 7, 36.0, "50 m 트러스 타워", heights=[36.4, 36.4, 36.4, 36.4, 37.2])
def tall_solar_tower(sp: Sprite, v: int):
    """아주 높은 격자 철탑 + 당김줄. 위쪽 절반에 판 세 단, 꼭대기에 붉은 항공등."""
    H = 35.8
    sp.contact_shadow(0, 0, 3.2, 3.2, 0.5)
    k = -1 if v == 4 else 1
    anchors = [(-3.0, -3.0), (3.0, -3.0), (3.0, 3.0), (-3.0, 3.0)]
    if v == 2:
        anchors = [(-3.1, 0.2), (1.2, -3.1), (2.6, 2.6)]
    lv = (9.0, 17.0) if v != 3 else (6.0, 12.0, 17.0)
    a0, a1 = 0.75, 0.42

    def mast_pt(ax, ay, z):
        t = (z - 0.5) / (H - 0.5)
        a = a0 + (a1 - a0) * t
        return (math.copysign(a, ax) if abs(ax) > 0.5 else 0.0, math.copysign(a, ay) if abs(ay) > 0.5 else 0.0, z)

    def guys(front):
        for ax, ay in anchors:
            if (ax + ay > 0.5) != front:
                continue
            for z in lv:
                _guy(sp, (ax, ay, 0.35), mast_pt(ax, ay, z))
            sp.box(ax - 0.35, ay - 0.35, 0, 0.7, 0.7, 0.35, CONCRETE)

    guys(False)
    sp.box(-1.3, -1.3, 0, 2.6, 2.6, 0.5, CONCRETE)
    bands = ("#d9532c", "#ece7dc", 3.0) if v == 1 else None
    _lattice(sp, 0.5, H, a0, a1, 1.8, bands=bands)
    # 판 세 단 (위쪽 절반) — 짧은 팔로 해 쪽에 단다
    tiers = [(18.4, 5.0), (24.2, 5.0), (30.0, 5.0)]
    widths = [6.2, 6.2, 6.2] if v != 4 else [5.0, 5.8, 6.4]
    for (z0, h), w in zip(tiers, widths):
        for zz in (z0 + 0.6, z0 + h - 0.6):
            sp.line((0.0, 0.3, zz), (SUN_N[0] * 1.0, SUN_N[1] * 1.0, zz), 0.16, "#7d848d")
        if v == 2:
            for s in (-1, 1):
                _sun_panel(sp, -SUN_E1[0] * s * w / 4, -SUN_E1[1] * s * w / 4, z0, w / 2 - 0.15, h, 1.0, 2, 4)
        elif v == 3:
            o = (-SUN_E1[0] * w / 2 + SUN_N[0], -SUN_E1[1] * w / 2 + SUN_N[1], z0)
            _solar(sp, o, mul(SUN_E1, w), (0.0, -0.9, h), 5, 4)
        else:
            _sun_panel(sp, 0.0, 0.0, z0, w, h, 1.0, 5, 4)
    # 바닥의 변환기 상자
    bx = 1.4 if k > 0 else -2.6
    sp.box(bx, 1.5, 0, 1.3, 1.1, 1.2, WHITE, top=SILVER)
    f = Sprite.box_faces(bx, 1.5, 0, 1.3, 1.1, 1.2)
    band_on(sp, f["left"], 0.78, 0.9, ORANGE)
    sp.window(sp.on_face(*f["left"], 0.3, 0.35, 0.6, 0.6), GREEN_LIGHT, glass=Mat("#2c8f4f", 0.4))
    sp.lamp((bx + 1.35, 2.0, 1.5), AMBER, 8)
    guys(True)
    # 항공등: 꼭대기 + 중간
    sp.line((0, 0, H), (0, 0, H + 0.6), 0.08, "#9aa1aa")
    sp.lamp((0, 0, H + 0.7), RED_LIGHT, 9)
    sp.lamp((a0 * 0.75, a0 * 0.75, 17.6), RED_LIGHT, 6)
    if v == 4:
        sp.line((0.2, 0.2, H), (0.2, 0.2, H + 1.4), 0.06, "#9aa1aa")
        sp.disc((0.3, 0.0, H + 0.9), (0.4, 1.0, 0.3), 0.45, WHITE, back=STEEL)


@typed("light_solar_tower", 5, 4, 16.0, "경량 타워", heights=[16.0, 15.4, 16.0, 16.6, 16.0])
def light_solar_tower(sp: Sprite, v: int):
    """가는 기둥 하나 + 좁은 세운 판 + 작은 세 다리 받침."""
    H = 15.6 if v != 1 else 15.0
    sp.contact_shadow(0, 0, 1.9, 1.7, 0.45)
    rot = 15.0 * (v % 3)
    feet = []
    for i in range(3):
        a = math.radians(rot + 30 + i * 120)
        feet.append((1.55 * math.cos(a), 1.35 * math.sin(a)))
    feet.sort(key=lambda p: p[0] + p[1])

    def leg(p):
        sp.line((p[0] * 0.12, p[1] * 0.12, 2.6), (p[0], p[1], 0.12), 0.11, "#8a9099")
        sp.box(p[0] - 0.2, p[1] - 0.2, 0, 0.4, 0.4, 0.12, STEEL)

    for p in feet[:2]:
        leg(p)
    if v == 2:
        sp.box(-0.75, -1.4, 0, 0.8, 0.6, 0.7, BATT, top=BATT_TOP)
        sp.window(sp.on_face(*Sprite.box_faces(-0.75, -1.4, 0, 0.8, 0.6, 0.7)["left"], 0.35, 0.55, 0.65, 0.75),
                  GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
    sp.cyl((0, 0, 0.3), (0, 0, H), 0.16, SILVER)
    sp.cyl((0, 0, 2.3), (0, 0, 2.8), 0.24, STEEL)
    leg(feet[2])
    w, h, z0 = (2.0, 9.4, 5.8) if v != 1 else (2.5, 8.0, 6.4)
    if v == 3:
        w, h = 1.7, 10.2
    if v == 4:
        o = (-SUN_E1[0] * w / 2 + SUN_N[0] * 0.3, -SUN_E1[1] * w / 2 + SUN_N[1] * 0.3, z0)
        _solar(sp, o, mul(SUN_E1, w), (0.0, -0.9, h), 2, 8)
    else:
        _sun_panel(sp, 0.0, 0.0, z0, w, h, 0.3, 2, 8 if v != 1 else 6)
    if v == 2:
        sp.box(-0.2, 0.25, 3.0, 0.4, 0.3, 0.5, ORANGE)
    if v == 3:
        sp.line((0, 0, H), (0, 0, H + 0.8), 0.05, "#9aa1aa")
        sp.line((-0.4, 0, H + 0.6), (0.4, 0, H + 0.6), 0.05, "#9aa1aa")
    if v == 1:
        sp.box(1.0, 0.5, 0, 0.7, 0.6, 0.6, WHITE, top=SILVER)
        pipe(sp, [(0.1, 0.1, 0.5), (0.6, 0.5, 0.3), (1.0, 0.75, 0.3)], 0.06, "#3a3f47")
        sp.lamp((1.75, 0.8, 0.5), AMBER, 6)
    sp.lamp((0, 0, H + 0.25 if v != 3 else H + 0.95), RED_LIGHT, 6)


@typed("bifacial_tower", 7, 5, 22.0, "양면 패널 타워", heights=[22.0, 22.0, 22.0, 22.4, 22.0])
def bifacial_tower(sp: Sprite, v: int):
    """돛대에 두 날개 판을 책처럼 V자로 펼친다. 앞뒤 면 모두 전지 칸 (한 날개는 해 쪽 면, 다른 날개는 뒷면이 보인다)."""
    mx, my = ((0.9, 1.0), (0.9, 1.0), (0.7, 1.1), (1.0, 0.9), (1.2, 1.0))[v]
    half = (40.0, 40.0, 47.0, 34.0, 40.0)[v]
    axis = 225.0 if v != 4 else 236.0
    L = 3.1 if v != 2 else 2.9
    da = (math.cos(math.radians(axis + half)), math.sin(math.radians(axis + half)), 0.0)    # 오른쪽 위로
    db = (math.cos(math.radians(axis - half)), math.sin(math.radians(axis - half)), 0.0)    # 왼쪽 위로
    sp.contact_shadow(mx - 1.0, my - 1.0, 2.8, 2.6, 0.5)
    if v in (0, 2, 4):
        # 흰 반사 깔개 — 판 뒷면에도 빛이 들게
        pad = rounded_rect(mx - 1.9, my - 1.9, mx + 1.5, my + 1.4, 0.5)
        sp.face([(x, y_, 0.03) for x, y_ in pad], WHITE_REF, normal=(0, 0, 1), ao=0)
    tiers = [(8.0, 12.6)] if v != 1 else [(7.0, 6.0), (13.8, 6.0)]
    top = 21.0
    for zb, h in tiers:
        for d in (da, db):
            o = add((mx, my, zb), mul(d, 0.4))
            _solar(sp, o, mul(d, L), (0.0, 0.0, h), 3, 8 if h > 8 else 4, back=SOLAR)
    if v == 3:
        for d in (da, db):
            sp.line((mx, my, top - 0.2), add((mx, my, 20.6), mul(d, L + 0.3)), 0.05, "#9aa1aa")
    sp.cyl((mx, my, 0), (mx, my, 0.5), 1.25, CONCRETE)
    sp.box(mx - 0.55, my - 0.55, 0.5, 1.1, 1.1, 0.8, STEEL)
    sp.cyl((mx, my, 1.3), (mx, my, top), 0.3, SILVER)
    for z in (4.6, top - 0.5):
        sp.ring3((mx, my, z), 0.32, "#7d848d", 0.06)
    for zb, h in tiers:
        for zz in (zb + 0.5, zb + h * 0.5, zb + h - 0.5):
            sp.box(mx - 0.22, my - 0.22, zz - 0.15, 0.44, 0.44, 0.3, STEEL)
    if v == 2:
        sp.box(1.9, -1.9, 0, 1.2, 1.0, 1.0, WHITE, top=SILVER)
        band_on(sp, Sprite.box_faces(1.9, -1.9, 0, 1.2, 1.0, 1.0)["left"], 0.75, 0.88, TEAL)
        sp.lamp((3.15, -1.4, 1.1), AMBER, 7)
    if v == 4:
        sp.box(-2.9, 1.2, 0, 1.0, 0.9, 0.9, WHITE, top=SILVER)
        sp.lamp((-2.4, 2.15, 1.0), AMBER, 6)
    sp.line((mx, my, top), (mx, my, top + 0.9), 0.06, "#9aa1aa")
    sp.lamp((mx, my, top + 1.0), RED_LIGHT, 6)


def _aim(az, el):
    """방위각 az, 고도 el(도)로 해를 보는 판의 (법선, 가로, 세로) 단위 벡터."""
    a, e = math.radians(az), math.radians(el)
    n = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
    up = (-math.sin(e) * math.cos(a), -math.sin(e) * math.sin(a), math.cos(e))
    return n, cross(up, n), up


@typed("tracking_tower", 7, 7, 24.0, "추적식 타워", heights=[24.0, 23.6, 24.2, 24.0, 23.6])
def tracking_tower(sp: Sprite, v: int):
    """굵은 기둥 꼭대기의 회전 포탑과 모터 상자, 짐벌에 단 큰 정사각 판 (해를 따라 돈다)."""
    az, el = ((112, 26), (118, 36), (108, 16), (114, 32), (104, 12))[v]
    n, e1, up = _aim(az, el)
    zt = 16.4
    sp.contact_shadow(0, 0, 2.8, 2.8, 0.5)
    if v == 3:
        for i in range(3):
            a = math.radians(-60 + i * 120)
            sp.line((0.4 * math.cos(a), 0.4 * math.sin(a), 3.0), (2.4 * math.cos(a), 2.4 * math.sin(a), 0), 0.14,
                    "#8a9099")
    sp.box(-1.5, -1.5, 0, 3.0, 3.0, 0.6, SINTER)
    sp.box(-0.7, -0.7, 0.6, 1.4, 1.4, 1.0, STEEL)
    sp.cyl((0, 0, 1.6), (0, 0, zt), 0.42, SILVER)
    for z in (6.0, 11.0):
        sp.ring3((0, 0, z), 0.44, "#7d848d", 0.06)
    # 회전 포탑 + 모터 상자
    sp.cyl((0, 0, zt), (0, 0, zt + 1.1), 0.8, WHITE, bands=[0.5], band_color=("#E07B39" if v != 2 else "#3FB8AF"))
    mm = YELLOW if v == 4 else (ORANGE if v != 2 else WHITE)
    sp.box(0.55, -0.55, zt + 0.1, 1.2, 1.1, 0.9, mm, top=SILVER)
    _louvers(sp, Sprite.box_faces(0.55, -0.55, zt + 0.1, 1.2, 1.1, 0.9)["right"], 0.15, 0.85, 0.2, 0.8, 4)
    sp.lamp((1.2, 0.6, zt + 0.7), AMBER, 6)
    # 짐벌 (포크) — 판 뒤
    c = add((0, 0, zt + 4.2), mul(n, 0.7))
    hinge = add((0, 0, zt + 4.2), mul(n, -0.1))
    for s in (-1, 1):
        base = add((0, 0, zt + 1.1), mul(e1, s * 0.6))
        arm = add(hinge, mul(e1, s * 1.5))
        sp.polyline3([base, add(base, (0, 0, 1.2)), arm], "#7d848d", 0.22)
    sp.line(add(hinge, mul(e1, -1.6)), add(hinge, mul(e1, 1.6)), 0.24, "#5c626b")
    W = 6.2
    if v == 2:
        for i in (0, 1):
            for j in (0, 1):
                o = add(add(c, mul(e1, -W / 2 + i * (W / 2 + 0.1))), mul(up, -W / 2 + j * (W / 2 + 0.1)))
                _solar(sp, o, mul(e1, W / 2 - 0.1), mul(up, W / 2 - 0.1), 3, 3)
    else:
        o = add(add(c, mul(e1, -W / 2)), mul(up, -W / 2))
        _solar(sp, o, mul(e1, W), mul(up, W), 6, 6)
        if v == 1:
            sp.polyline3([add(o, mul(up, W / 2)), add(add(o, mul(up, W / 2)), mul(e1, W))], "#c0c6ce", 0.1)
    sp.lamp(add(add(c, mul(up, W / 2 + 0.2)), mul(n, 0.05)), RED_LIGHT, 6)
    if v == 4:
        sp.box(1.6, 1.4, 0, 1.4, 1.2, 1.2, WHITE, top=SILVER)
        sp.lamp((3.05, 2.0, 1.3), AMBER, 7)


# ── 소형 핵분열로 계열 ──────────────────────────────────────────────────

@typed("kilopower_10", 4, 4, 4.5, "킬로파워 10 kW", heights=[4.6, 4.6, 4.6, 4.8, 4.6])
def kilopower_10(sp: Sprite, v: int):
    """가늘고 긴 노심 통 위에 열관을 꿴 얇은 방열 지느러미 기둥 (작은 받침 위)."""
    sp.contact_shadow(0, 0, 1.9, 1.9, 0.5)
    sp.box(-1.25, -1.25, 0, 2.5, 2.5, 0.3, STEEL, top=DARK)
    sp.stripes((1.25, -1.25, 0.0), (0, 2.5, 0), (0, 0, 0.3), n=8, normal=(1, 0, 0))
    sp.stripes((1.25, 1.25, 0.0), (-2.5, 0, 0), (0, 0, 0.3), n=8, normal=(0, 1, 0))
    if v == 3:
        sp.box(0.35, 0.55, 0.3, 0.7, 0.55, 0.6, WHITE, top=SILVER)
        sp.lamp((1.1, 0.85, 0.75), AMBER, 6)
    zc = 2.1 if v != 3 else 2.4
    sp.cyl((0, 0, 0.3), (0, 0, 0.65), 0.62, DARK, cap_mat=STEEL)
    core = GOLD if v != 3 else Mat("#6B6F76", 0.25)
    sp.cyl((0, 0, 0.65), (0, 0, zc), 0.46, core, bands=[0.33, 0.66] if v != 3 else [0.5])
    if v == 3:
        cyl_ring(sp, (0, 0, 0.65), (0, 0, zc), 0.46, 0.82, 0.92, YELLOW)
    sp.cyl((0, 0, zc), (0, 0, zc + 0.35), 0.58, SILVER)
    cyl_ring(sp, (0, 0, zc), (0, 0, zc + 0.35), 0.58, 0.3, 0.7, ORANGE)
    # 열관 기둥: 얇은 판을 층층이 꿴다
    z0, z1 = zc + 0.5, 4.3
    n = 9 if v not in (2, 3) else 7
    hw = 0.62
    pipes = [(-hw - 0.05, -hw - 0.05), (hw + 0.05, -hw - 0.05), (-hw - 0.05, hw + 0.05), (hw + 0.05, hw + 0.05)]
    if v == 1:
        pipes = [(0.7 * math.cos(math.radians(a)), 0.7 * math.sin(math.radians(a))) for a in (225, 315, 135, 45)]
    if v == 2:
        pipes = [(-0.76, -0.76), (0.76, -0.76), (-0.76, 0.76), (0.76, 0.76)]
    for x, y in pipes[:3]:
        sp.line((x * 0.5, y * 0.5, zc + 0.35), (x, y, z0), 0.07, "#B8733F")
        sp.line((x, y, z0), (x, y, z1 + 0.12), 0.07, "#B8733F")
    sp.cyl((0, 0, zc + 0.35), (0, 0, z1 + 0.15), 0.1, STEEL)
    for i in range(n):
        z = z0 + i * (z1 - z0) / (n - 1)
        if v == 1:
            sp.cyl((0, 0, z), (0, 0, z + 0.05), 0.66, RADIATOR, cap_mat=RADIATOR)
        elif v == 2:
            sp.box(-0.7, -0.7, z, 1.4, 1.4, 0.06, RADIATOR)
        else:
            w = hw if v != 4 else 0.75 - 0.3 * i / (n - 1)
            sp.box(-w, -w, z, 2 * w, 2 * w, 0.05, RADIATOR)
    x, y = pipes[3]
    sp.line((x * 0.5, y * 0.5, zc + 0.35), (x, y, z0), 0.07, "#B8733F")
    sp.line((x, y, z0), (x, y, z1 + 0.12), 0.07, "#B8733F")
    sp.lamp((0, 0, z1 + 0.3), RED_LIGHT, 6)
    sp.glow((0, 0, 1.4), 12, HOT, 0.3)


RTG_FIN = Mat("#6A707A", 0.3)


def _mmrtg(sp: Sprite, cx, cy, z, r=0.24, fin=0.3, h=0.9, nfin=8):
    """MMRTG: 어두운 지느러미가 둘러싼 짧은 원통 (서 있다). 밤에는 열로 붉게 번진다."""
    sp.box(cx - 0.34, cy - 0.34, z, 0.68, 0.68, 0.1, STEEL)
    z0 = z + 0.1

    def ang(k):
        return 2 * math.pi * k / nfin + math.pi / nfin

    order = sorted(range(nfin), key=lambda k: dot((math.cos(ang(k)), math.sin(ang(k)), 0.0), VIEW))

    def fin_at(k):
        d = (math.cos(ang(k)), math.sin(ang(k)), 0.0)
        sp.quad((cx + d[0] * r, cy + d[1] * r, z0 + 0.06), mul(d, fin), (0, 0, h - 0.12), RTG_FIN, back=RTG_FIN)

    for k in order[:nfin // 2]:
        fin_at(k)
    sp.cyl((cx, cy, z0), (cx, cy, z0 + h), r, RTG, cap_mat=STEEL, bands=[0.15, 0.85], band_color="#c9a75a")
    for k in order[nfin // 2:]:
        fin_at(k)
    sp.cyl((cx, cy, z0 + h), (cx, cy, z0 + h + 0.1), r * 0.7, SILVER)
    sp.glow((cx, cy, z0 + h * 0.5), 10, "#ff7a4a", 0.4)


def _sign(sp: Sprite, x, y, h, s, post="#8a9099"):
    """기둥 위의 방사능 표지판 (화면 쪽을 본다)."""
    sp.line((x, y, 0.1), (x, y, h), 0.06, post)
    e1 = norm((-1.0, 1.0, 0.0))
    c = (x + 0.05, y + 0.05, h - s / 2)
    o = add(add(c, mul(e1, -s / 2)), (0, 0, -s / 2))
    sp.quad(o, mul(e1, s), (0, 0, s), YELLOW, back=STEEL)
    _trefoil(sp, c, e1, (0.0, 0.0, 1.0), s * 0.36, bg=None)


@typed("rtg_pack", 2, 2, 1.8, "방사성동위원소 발전기", heights=[1.8, 1.8, 1.7, 1.8, 1.8])
def rtg_pack(sp: Sprite, v: int):
    """받침 위에 선 MMRTG (지느러미 원통) + 기둥에 단 방사능 표지판."""
    sp.contact_shadow(0, 0, 1.2, 1.2, 0.45)
    sp.box(-0.95, -0.95, 0, 1.9, 1.9, 0.12, CONCRETE)
    sp.stripes((0.95, -0.95, 0.0), (0, 1.9, 0), (0, 0, 0.12), n=6, normal=(1, 0, 0))
    sp.stripes((0.95, 0.95, 0.0), (-1.9, 0, 0), (0, 0, 0.12), n=6, normal=(0, 1, 0))
    sx, sy = (0.55, -0.72) if v not in (3, 4) else (-0.72, 0.55)
    _sign(sp, sx, sy, 1.8 if v != 2 else 1.7, 0.6)
    if v == 1:
        for x, y in ((-0.85, -0.85), (0.85, -0.85), (-0.85, 0.85)):
            sp.line((x, y, 0.12), (x, y, 0.75), 0.05, "#E9C24A")
        sp.polyline3([(-0.85, 0.85, 0.7), (-0.85, -0.85, 0.7), (0.85, -0.85, 0.7)], "#E9C24A", 0.03)
    if v == 2:
        sp.quad((-0.9, -0.85, 0.12), (1.2, 0, 0), (0, 0, 1.3), WHITE, back=STEEL)
        sp.quad((-0.85, -0.9, 0.12), (0, 1.2, 0), (0, 0, 1.3), WHITE, back=STEEL)
    if v == 3:
        _mmrtg(sp, -0.35, -0.45, 0.12, 0.18, 0.22, 0.75)
        _mmrtg(sp, 0.3, -0.05, 0.12, 0.18, 0.22, 0.75)
        pipe(sp, [(-0.35, -0.2, 0.2), (0.3, 0.3, 0.2), (0.3, 0.75, 0.15)], 0.05, "#2a2f36")
    else:
        cz = 0.12 if v != 2 else 0.32
        if v == 2:
            sp.box(-0.45, -0.45, 0.12, 0.7, 0.7, 0.2, DARK)
        _mmrtg(sp, -0.1, -0.1, cz)
        pipe(sp, [(-0.1, 0.25, 0.2), (-0.1, 0.8, 0.14)], 0.05, "#2a2f36")
    if v == 1:
        sp.polyline3([(-0.85, 0.85, 0.7), (0.6, 0.85, 0.7)], "#E9C24A", 0.03)
        sp.polyline3([(0.85, -0.85, 0.7), (0.85, 0.6, 0.7)], "#E9C24A", 0.03)
        for x, y in ((0.85, 0.85),):
            sp.line((x, y, 0.12), (x, y, 0.75), 0.05, "#E9C24A")
    if v == 4:
        sp.box(0.35, 0.3, 0.12, 0.5, 0.5, 0.45, WHITE, top=SILVER)
        sp.lamp((0.6, 0.85, 0.5), AMBER, 5)
        sp.line((0.75, 0.4, 0.57), (0.75, 0.4, 1.4), 0.03, "#9aa1aa")
    if v in (0, 3):
        sp.lamp((sx, sy, 1.9), AMBER, 5)


@typed("fission_100kw", 8, 8, 8.0, "100 kW 원자로", heights=[8.0, 7.6, 8.0, 8.0, 8.4])
def fission_100kw(sp: Sprite, v: int):
    """흙 둑을 두른 구덩이 속 원자로 + 가운데 기둥에 단 큰 세로 방열 날개 한 쌍."""
    sp.contact_shadow(0, 0, 4.2, 4.2, 0.5)
    rin, rout, hb = 1.9, 3.5, 1.5
    sp.berm_ring((0, 0, 0), rin, rout, hb, front=False)
    sp.disc((0, 0, 0.02), (0, 0, 1), rin, DARK)
    sp.cyl((0, 0, 0), (0, 0, 0.9), 1.5, DARK, cap_mat=STEEL)
    sp.cyl((0, 0, 0.9), (0, 0, 1.5), 0.95, GOLD, bands=[0.5])
    ang = (-45.0, 0.0, -45.0, -30.0, -45.0)[v]
    d = (math.cos(math.radians(ang)), math.sin(math.radians(ang)), 0.0)
    zb, h = (1.9, 5.6) if v != 4 else (2.0, 6.0)
    span = 3.3 if v != 1 else 3.0
    top = zb + h + 0.3
    sp.box(-0.3, -0.3, 1.5, 0.6, 0.6, top - 1.5, STEEL, top=SILVER)
    for s in (-1, 1):
        dd = mul(d, s)
        if v == 2:
            dd = norm(add(dd, (0.25, 0.25, 0.0)))
        o = add((0, 0, zb), mul(dd, 0.45))
        _rad(sp, o, mul(dd, span), (0, 0, h), 6, 1)
        pipe(sp, [add(o, (0, 0, h)), add(add(o, mul(dd, span)), (0, 0, h))], 0.14, "#B8733F")
        pipe(sp, [add(o, (0, 0, 0)), add(add(o, mul(dd, span)), (0, 0, 0))], 0.14, "#B8733F")
        sp.line((0, 0, top), add(add(o, mul(dd, span)), (0, 0, h)), 0.05, "#9aa1aa")
    sp.berm_ring((0, 0, 0), rin, rout, hb, front=True)
    sandbag_rings(sp, (0, 0, 0.0), rout - 0.35, rout - 0.35, hb * 1.3, (0.45, 0.9) if v == 4 else (0.6,))
    # 전력선 홈과 변환기 상자
    bx, by = ((2.3, 2.0), (2.3, 2.0), (2.3, 2.0), (2.2, -3.6), (-3.7, 2.2))[v]
    sp.box(bx, by, 0, 1.4, 1.4, 1.3, WHITE, top=SILVER)
    f = Sprite.box_faces(bx, by, 0, 1.4, 1.4, 1.3)
    band_on(sp, f["left"], 0.75, 0.88, ORANGE)
    door(sp, f["right"], 0.3, 0.7, 0.75)
    _trefoil(sp, (bx + 0.7, by + 1.42, 0.6), (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.26, square=True)
    sp.lamp((0, 0, top + 0.2), RED_LIGHT, 7)
    sp.glow((0, 0, 1.4), 22, HOT, 0.3)


@typed("buried_reactor", 7, 7, 3.0, "매립형 원자로", heights=[2.9, 2.9, 2.9, 3.1, 2.9])
def buried_reactor(sp: Sprite, v: int):
    """낮은 모래주머니 둑 고리 + 방사능 표지를 칠한 강철 뚜껑, 둘레에 선 작은 방열판 넷, 전력 도관."""
    sp.contact_shadow(0, 0, 3.6, 3.6, 0.45)
    rin, rout, hb = 1.45, 2.35, 0.7
    rh = 2.75 if v != 3 else 3.0
    dirs = [(-1, 0), (0, -1), (1, 0), (0, 1)]

    def radiator(dx, dy):
        if v == 1:
            # 둘레를 따라 (접선 방향으로) 세운다
            c = (dx * 2.95, dy * 2.95, 0.0)
            e1 = (-dy * 1.3, dx * 1.3, 0.0)
            _rad(sp, sub(c, mul(e1, 0.5)), e1, (0, 0, rh), 3, 1)
            sp.box(c[0] - 0.1, c[1] - 0.1, 0, 0.2, 0.2, 0.25, STEEL)
            return
        r0, r1 = 2.45, 3.45
        o = (dx * r0, dy * r0, 0.15)
        _rad(sp, o, (dx * (r1 - r0), dy * (r1 - r0), 0), (0, 0, rh), 3, 1)
        sp.box(dx * (r0 + r1) / 2 - 0.12, dy * (r0 + r1) / 2 - 0.12, 0, 0.24, 0.24, 0.18, STEEL)

    back = [d for d in dirs if d[0] + d[1] < -0.1]
    front = [d for d in dirs if d[0] + d[1] > 0.1]
    side = [d for d in dirs if abs(d[0] + d[1]) <= 0.1]
    for d in back + side:
        radiator(*d)
    sp.berm_ring((0, 0, 0), rin, rout, hb, front=False)
    sp.disc((0, 0, 0.02), (0, 0, 1), rin, Mat("#3b3f45"))
    sp.cyl((0, 0, 0), (0, 0, 0.32), 1.2, STEEL, cap_mat=Mat("#9AA0A8", 0.3))
    e1, e2 = norm((-1.0, 1.0, 0.0)), norm((-1.0, -1.0, 0.0))
    _trefoil(sp, (0, 0, 0.33), e1, e2, 0.8)
    if v == 3:
        for i in range(6):
            a = 2 * math.pi * i / 6 + 0.5
            if dot((math.cos(a), math.sin(a), 0), VIEW) > -0.3:
                sp.lamp((1.1 * math.cos(a), 1.1 * math.sin(a), 0.4), AMBER, 5)
    # 전력 도관: 뚜껑에서 둑을 넘어 접속함으로
    jx, jy = (2.35, -2.75) if v != 4 else (-2.75, 2.35)
    if v != 4:
        pts = [(0.9, -0.55, 0.25), (1.75, -1.05, hb + 0.12), (2.3, -1.55, 0.25), (2.55, -2.2, 0.2)]
    else:
        pts = [(-0.55, 0.9, 0.25), (-1.05, 1.75, hb + 0.12), (-1.55, 2.3, 0.25), (-2.2, 2.55, 0.2)]
    sp.berm_ring((0, 0, 0), rin, rout, hb, front=True)
    for zz in (0.25, 0.48):
        k = 1 - zz / hb
        r = (rin + rout) / 2 + (rout - (rin + rout) / 2) * k
        sp.ring3((0, 0, zz), r, "#5f5953", 0.05, opacity=0.7)
    for d in front:
        radiator(*d)
    pipe(sp, pts, 0.2, "#d8853b" if v != 2 else "#c9ccd1")
    sp.box(jx - 0.4, jy - 0.35, 0, 0.8, 0.7, 0.75, WHITE, top=SILVER)
    sp.lamp((jx + 0.45, jy, 0.85), AMBER, 6)
    if v == 2:
        pipe(sp, [(-0.55, 0.9, 0.25), (-1.05, 1.75, hb + 0.12), (-1.55, 2.3, 0.25), (-2.2, 2.6, 0.2)], 0.2, "#c9ccd1")
        sp.box(-2.8, 2.3, 0, 0.7, 0.8, 0.75, WHITE, top=SILVER)
    sp.line((-1.9, -1.9, 0), (-1.9, -1.9, 2.4), 0.06, "#8a9099")
    sp.lamp((-1.9, -1.9, 2.5), RED_LIGHT, 6)
    sp.glow((0, 0, 0.5), 18, HOT, 0.22)


# ── 메가와트급 원자로 계열 ──────────────────────────────────────────────

ROOF_BERM = Mat("#8F8577")


def _gable_hall(sp: Sprite, x0, y0, x1, y1, hw, hr, wall: Mat = HALL, roof: Mat = ROOF_BERM, eave=0.25):
    """박공지붕 홀 (용마루는 x 방향). 보이는 면(앞 +y, 박공 +x)의 틀을 돌려준다."""
    sp.box(x0, y0, 0, x1 - x0, y1 - y0, hw, wall)
    ym = (y0 + y1) / 2
    a0, a1, b0, b1 = x0 - eave, x1 + eave, y0 - eave, y1 + eave
    zr = hw + hr
    sp.face([(x1, y0, hw), (x1, y1, hw), (x1, ym, zr)], wall, normal=(1, 0, 0), ao=0)
    sp.face([(a0, b0, hw - 0.1), (a1, b0, hw - 0.1), (a1, ym, zr), (a0, ym, zr)], roof, ao=0)
    sp.face([(a0, ym, zr), (a1, ym, zr), (a1, b1, hw - 0.1), (a0, b1, hw - 0.1)], roof, ao=0)
    sp.face([(a1, b0, hw - 0.1), (a1, b1, hw - 0.1), (a1, ym, zr)], roof, normal=(1, 0, 0), ao=0)
    sp.line((a0, ym, zr + 0.02), (a1, ym, zr + 0.02), 0.12, "#6f675c")
    for k in (0.33, 0.66):
        zz = hw - 0.1 + (zr - hw + 0.1) * k
        yy = b1 + (ym - b1) * k
        sp.line((a0, yy, zz), (a1, yy, zz), 0.05, "#6f675c")
    return Sprite.box_faces(x0, y0, 0, x1 - x0, y1 - y0, hw)


def _skirt(sp: Sprite, x0, y0, x1, y1, h, s, gap=None, mat: Mat = BERM):
    """건물 벽에 기대 쌓은 모래주머니 둑 (보이는 앞(+y)·오른쪽(+x) 두 면). gap=(ya, yb)는 오른쪽 벽의 문 자리."""
    segs = [(y0, y1)] if gap is None else [(y0, gap[0]), (gap[1], y1)]
    for i, (ya, yb) in enumerate(segs):
        last = i == len(segs) - 1
        sp.face([(x1, ya, h), (x1 + s, ya, 0), (x1 + s, yb + (s if last else 0), 0), (x1, yb, h)], mat, ao=0)
        if not last:
            sp.face([(x1, yb, 0), (x1 + s, yb, 0), (x1, yb, h)], mat, normal=(0, 1, 0), ao=0)
    sp.face([(x0, y1, h), (x1, y1, h), (x1 + s, y1 + s, 0), (x0, y1 + s, 0)], mat, ao=0)
    for k in (0.35, 0.7):
        z = h * (1 - k)
        sp.polyline3([(x0, y1 + s * k, z), (x1 + s * k, y1 + s * k, z), (x1 + s * k, (gap or (y0, y0))[1], z)],
                     "#5f5953", 0.05, 0.8)


def _wing_pair(sp: Sprite, mx, my, z0, h, w, ang=0.0, dihedral=0.0, mast_h=None, header="#B8733F"):
    """가운데 기둥 + 양쪽으로 펼친 세로 방열 날개 한 쌍 (+ 꼭대기에서 날개 끝으로 당김줄)."""
    top = mast_h or (z0 + h + 0.5)
    wings = []
    for s in (-1, 1):
        a = math.radians(ang + (0 if s > 0 else 180) + s * dihedral)
        d = (math.cos(a), math.sin(a), 0.0)
        wings.append((dot(mul(d, w / 2), VIEW), d))
    wings.sort()
    sp.box(mx - 0.25, my - 0.25, 0, 0.5, 0.5, top, STEEL, top=SILVER)
    for _, d in wings:
        o = add((mx, my, z0), mul(d, 0.35))
        _rad(sp, o, mul(d, w), (0, 0, h), 5, 1)
        for zz in (0.0, h):
            pipe(sp, [add(o, (0, 0, zz)), add(add(o, mul(d, w)), (0, 0, zz))], 0.14, header)
        sp.line((mx, my, top - 0.1), add(add(o, mul(d, w)), (0, 0, h)), 0.05, "#9aa1aa")
        foot = add(o, mul(d, w * 0.9))
        sp.line(foot, (foot[0], foot[1], 0.0), 0.08, "#8a9099")
    sp.lamp((mx, my, top + 0.2), RED_LIGHT, 7)


@typed("fission_500kw", 12, 10, 7.0, "500 kW 원자로", heights=[7.0, 7.0, 7.4, 7.0, 6.6])
def fission_500kw(sp: Sprite, v: int):
    """작은 원자로 홀 (흙을 덮은 박공지붕) + 옆에 선 방열 날개 한 쌍."""
    sp.contact_shadow(0, 0, 6.4, 5.4, 0.5)
    x0, y0, x1, y1 = -5.4, -3.2, 0.4, 1.8
    hw = 3.4
    # 날개 한 쌍 (홀 오른쪽, +y를 본다)
    mx, my = (3.4, -0.6)
    wing_h = 6.0 if v != 2 else 6.4
    if v == 1:
        sp.box(x0, y0, 0, x1 - x0, y1 - y0, 2.4, HALL)
        f = Sprite.box_faces(x0, y0, 0, x1 - x0, y1 - y0, 2.4)
        r = (y1 - y0) / 2
        sp.half_cyl((x0, (y0 + y1) / 2, 2.4), (x1, (y0 + y1) / 2, 2.4), r, ROOF_BERM,
                    bands=[0.2, 0.4, 0.6, 0.8], band_color="#6f675c", cap_mat=HALL)
        hw = 2.4
    elif v == 4:
        sp.box(x0, y0, 0, x1 - x0, y1 - y0, 4.0, HALL, top=ROOF_BERM)
        f = Sprite.box_faces(x0, y0, 0, x1 - x0, y1 - y0, 4.0)
        hw = 4.0
        sp.box(-4.6, -2.6, 4.0, 1.6, 1.4, 0.7, STEEL, top=SILVER)
        sp.cyl((-1.4, -0.6, 4.0), (-1.4, -0.6, 5.2), 0.35, SILVER)
    else:
        f = _gable_hall(sp, x0, y0, x1, y1, hw, 1.4)
    o, e1, e2 = f["left"]
    band_on(sp, f["left"], 0.82, 0.92, ORANGE)
    windows_row(sp, f["left"], 3 if v != 4 else 4, 0.42, 0.68, 0.3, 0.06)
    _trefoil(sp, add(add(o, mul(e1, 0.13)), mul(e2, 0.55)), (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.42, square=True)
    door(sp, f["right"], 0.32, 0.68, 0.72 if v != 1 else 0.8, STEEL)
    sp.stripes(add(f["right"][0], (0.01, 0, 0)), (0, y1 - y0, 0), (0, 0, 0.3), n=12, normal=(1, 0, 0))
    if v == 3:
        _skirt(sp, x0, y0, x1, y1, 1.1, 0.9, gap=(-1.75, 0.35))
    _wing_pair(sp, mx, my, 0.8, wing_h, 2.2, 0.0, 14.0 if v == 2 else 0.0)
    pipe(sp, [(x1, -1.2, 1.4), (mx - 0.3, -1.2, 1.4), (mx - 0.3, my, 0.9)], 0.22, "#d8853b")
    # 앞마당: 변압기 상자
    tx, ty = (1.6, 2.6) if v != 3 else (-1.0, 2.8)
    sp.box(tx, ty, 0, 1.6, 1.2, 1.5, DARK, top=STEEL)
    _louvers(sp, Sprite.box_faces(tx, ty, 0, 1.6, 1.2, 1.5)["left"], 0.1, 0.9, 0.15, 0.85, 5, Mat("#30353c"))
    sp.lamp((tx + 1.65, ty + 0.6, 1.6), AMBER, 8)
    if v == 3:
        for x in (-5.6, -4.4):
            crate(sp, x, 3.4, 1.0, ORANGE if x < -5 else Mat("#C9A23A"))
    if v == 0:
        crate(sp, -5.0, 2.6, 1.1)
    sp.lamp((x1 + 0.1, y1 - 0.5, hw + 0.4), AMBER, 8)
    sp.glow((-2.5, -0.7, 2.0), 30, HOT, 0.18)


TURBINE_BODY = Mat("#D9D2C2", 0.2)


def _turbine(sp: Sprite, x0, y, z, m=1, k=1.0, accent: Mat = ORANGE):
    """누운 터빈·발전기 덮개: 압축기 원뿔 → 터빈 → 플랜지 → 발전기 → 끝 원뿔 (x0에서 m 방향으로, 먼 쪽부터)."""
    seg = [(0.0, 1.8, 0.95, 1.3, SILVER), (1.8, 3.8, 1.3, 1.3, STEEL), (3.8, 4.0, 1.45, 1.45, DARK),
           (4.0, 6.6, 1.12, 1.12, TURBINE_BODY), (6.6, 7.4, 1.12, 0.55, STEEL)]
    for s_ in (0.8, 2.8, 5.2):
        sp.box(x0 + s_ * m - 0.3, y - 0.8 * k, 0, 0.6, 1.6 * k, z - 0.7 * k, STEEL)
    for a, b, r0, r1, mat in (seg if m > 0 else reversed(seg)):
        bands = [0.25, 0.5, 0.75] if mat is STEEL and b - a > 1.5 else ()
        if m > 0:
            sp.frustum((x0 + a, y, z), (x0 + b, y, z), r0 * k, r1 * k, mat, bands=bands)
        else:
            sp.frustum((x0 - b, y, z), (x0 - a, y, z), r1 * k, r0 * k, mat, bands=bands)
    cyl_ring(sp, (x0 + 4.0 * m, y, z), (x0 + 6.6 * m, y, z), 1.12 * k, 0.45, 0.55, accent)


@typed("brayton_reactor", 16, 12, 9.0, "브레이턴 원자로", heights=[8.6, 8.6, 8.6, 8.6, 8.0])
def brayton_reactor(sp: Sprite, v: int):
    """원자로 돔 + 옆으로 누운 터빈·발전기 덮개 + 뒤쪽의 큰 방열판 벽."""
    sp.contact_shadow(0, 0, 8.4, 6.4, 0.5)
    m = -1 if v == 4 else 1
    # 뒤쪽 방열판 벽 (+y를 본다)
    yb = -5.3
    hr = 7.8 if v != 4 else 7.2
    xs = [-7.4, -3.7, 0.0, 3.7] if v != 1 else [-7.4, -3.7, 0.9, 4.6]
    for x in xs:
        sp.line((x - 0.05, yb, 0), (x - 0.05, yb, hr + 0.6), 0.12, "#8a9099")
        _rad(sp, (x, yb, 0.6), (3.5 if v != 1 else 2.8, 0, 0), (0, 0, hr), 6, 1)
    pipe(sp, [(-7.4, yb + 0.1, hr + 0.7), (7.4, yb + 0.1, hr + 0.7)], 0.24, "#B8733F")
    pipe(sp, [(-7.4, yb + 0.1, 0.5), (7.4, yb + 0.1, 0.5)], 0.2, "#B8733F")
    # 복열기 상자 (터빈과 방열판 사이)
    rx = 1.0 if m > 0 else -4.6
    sp.box(rx, -3.4, 0, 3.6, 2.0, 2.6, WHITE, top=SILVER)
    fr = Sprite.box_faces(rx, -3.4, 0, 3.6, 2.0, 2.6)
    _louvers(sp, fr["left"], 0.08, 0.92, 0.2, 0.8, 5, Mat("#9aa0a8"))
    pipe(sp, [(rx + 0.8, -3.4, 2.2), (rx + 0.8, yb + 0.2, 2.2), (rx + 0.8, yb + 0.2, hr + 0.6)], 0.24, "#d8853b")
    # 원자로 돔
    cx, cy = (-3.9 * m, 0.4)
    sp.cyl((cx, cy, 0), (cx, cy, 1.4), 3.0, CONCRETE, cap_mat=CONCRETE)
    if v == 3:
        sandbag_rings(sp, (cx, cy, 0.0), 3.05, 3.05, 1.6, (0.45, 0.95))
    sp.dome((cx, cy, 1.4), 2.85, 3.0, Mat("#E8E4DA", 0.15))
    for zz in (2.4, 3.4):
        k = math.sqrt(max(0.0, 1 - ((zz - 1.4) / 3.0) ** 2))
        sp.ring3((cx, cy, zz), 2.85 * k, "#b9b2a5", 0.06)
    sp.cyl((cx, cy, 4.3), (cx, cy, 4.55), 0.7, STEEL)
    ang = 25.0 if m > 0 else 75.0
    a = math.radians(ang)
    hx, hy = cx + 3.02 * math.cos(a), cy + 3.02 * math.sin(a)
    n = (math.cos(a), math.sin(a), 0.0)
    t = (-math.sin(a), math.cos(a), 0.0)
    pts = [add((hx, hy, 0.0), mul(t, -0.55)), add((hx, hy, 0.0), mul(t, 0.55)),
           add((hx, hy, 1.15), mul(t, 0.55)), add((hx, hy, 1.15), mul(t, -0.55))]
    sp.face(pts, DARK, normal=n, ao=0)
    _trefoil(sp, add((cx, cy, 0.75), mul(norm((0.0, 1.0, 0.0)), 3.03)), (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.35,
             square=True)
    sp.lamp(add((hx, hy, 1.5), mul(n, 0.1)), AMBER, 8)
    # 터빈·발전기 (누운 원기둥)
    accent = ORANGE if v != 1 else TEAL
    if v == 2:
        _turbine(sp, cx + 2.4 * m, 0.9, 1.5, m, 0.75, accent)
        _turbine(sp, cx + 2.4 * m, 3.4, 1.5, m, 0.75, accent)
    else:
        _turbine(sp, cx + 2.4 * m, 1.7, 1.9, m, 1.0, accent)
    pipe(sp, [(cx, cy, 4.5), (cx + 2.2 * m, cy - 1.8, 4.5), (rx + 1.8, -2.4, 2.6)], 0.3, "#B8733F")
    # 앞 오른쪽 제어실
    bx, by = (4.6, 3.4) if m > 0 else (4.4, 3.4)
    _hut(sp, bx, by, 2.8, 2.2, 2.6)
    antenna(sp, (bx + 2.4, by + 0.4, 2.6), 1.8)
    sp.lamp((cx, cy, 4.8), RED_LIGHT, 7)
    sp.glow((cx, cy, 2.2), 30, HOT, 0.25)


def _hut(sp: Sprite, x, y, w, d, h, accent: Mat = ORANGE, nwin=2, both=False):
    """창 달린 작은 흰 건물 (제어실). 앞(+y) 면에 색 띠와 창, 오른쪽(+x) 면에 문."""
    sp.box(x, y, 0, w, d, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x, y, 0, w, d, h)
    for side in (("left", "right") if both else ("left",)):
        band_on(sp, f[side], 0.82, 0.92, accent)
    windows_row(sp, f["left"], nwin, 0.42, 0.68, 0.18 if nwin < 3 else 0.08, 0.12 if nwin < 3 else 0.06)
    door(sp, f["right"], 0.35, 0.7, 0.72)
    return f


def _aframe_row(sp: Sprite, x0, x1, yc, half, h, z0=0.3, cols=6):
    """두 장의 방열판을 서로 기대 세운 텐트 모양 줄 (용마루는 x 방향)."""
    L = x1 - x0
    _rad(sp, (x0, yc - half, z0), (L, 0, 0), (0, half, h), cols, 1)
    for x in (x0, x1):
        sp.polyline3([(x, yc - half, z0), (x, yc, z0 + h), (x, yc + half, z0)], "#7d848d", 0.1)
    sp.quad((x0, yc, z0 + h), (L, 0, 0), (0, half, -h), RADIATOR, back=RADIATOR)
    sp.panel_grid((x0, yc, z0 + h), (L, 0, 0), (0, half, -h), cols, 2, "#b9bec4", 0.5, 0.7)
    sp.line((x0 - 0.1, yc, z0 + h + 0.05), (x1 + 0.1, yc, z0 + h + 0.05), 0.14, "#d8853b")


@typed("molten_salt_reactor", 18, 14, 10.0, "용융염 원자로", heights=[10.0, 10.0, 10.0, 10.4, 9.6])
def molten_salt_reactor(sp: Sprite, v: int):
    """커다란 상자형 발전동 + 높은 열교환탑 + 주황 단열 배관 + 텐트형 방열판 밭."""
    sp.contact_shadow(0, 0, 9.4, 7.4, 0.5)
    # 열교환탑 (뒤 왼쪽)
    tx, ty = (-5.6, -4.6) if v != 4 else (-1.6, -4.8)
    th = 9.2 if v != 3 else 9.6
    sp.cyl((tx, ty, 0), (tx, ty, 0.6), 1.9, CONCRETE)
    p0, p1 = (tx, ty, 0.6), (tx, ty, th)
    sp.cyl(p0, p1, 1.35, SILVER, bands=[0.2, 0.4, 0.6, 0.8])
    rings = ((0.47, 0.53), (0.86, 0.9)) if v != 3 else ((0.3, 0.35), (0.55, 0.6), (0.8, 0.85))
    for s0, s1 in rings:
        cyl_ring(sp, p0, p1, 1.35, s0, s1, Mat("#E2742E", 0.3), SALT, 0.8)
    sp.dome((tx, ty, th), 1.35, 0.7, SILVER)
    if v == 2:
        sp.cyl((tx + 2.6, ty - 0.4, 0), (tx + 2.6, ty - 0.4, 6.4), 0.8, SILVER, bands=[0.33, 0.66])
        sp.dome((tx + 2.6, ty - 0.4, 6.4), 0.8, 0.4, SILVER)
    # 방열판 밭 (오른쪽, 텐트형 줄)
    rows = [-5.6, -2.8, 0.0, 2.8, 5.6] if v != 1 else [-5.4, -1.8, 1.8, 5.4]
    for yc in rows:
        _aframe_row(sp, 3.0, 8.6, yc, 1.0, 3.0 if v != 3 else 3.4)
    pipe(sp, [(2.6, rows[0], 0.6), (2.6, rows[-1], 0.6)], 0.26, "#d8853b")
    # 발전동 (큰 상자)
    bx0, by0, bx1, by1 = -7.8, -2.4, 1.6, 4.2
    hb = 5.2 if v != 4 else 4.6
    sp.box(bx0, by0, 0, bx1 - bx0, by1 - by0, hb, WHITE, top=SILVER)
    f = Sprite.box_faces(bx0, by0, 0, bx1 - bx0, by1 - by0, hb)
    band_on(sp, f["left"], 0.84, 0.92, ORANGE if v != 3 else TEAL)
    band_on(sp, f["right"], 0.84, 0.92, ORANGE if v != 3 else TEAL)
    windows_row(sp, f["left"], 5, 0.5, 0.7, 0.06, 0.05)
    _trefoil(sp, add(add(f["left"][0], mul(f["left"][1], 0.05)), mul(f["left"][2], 0.25)),
             (-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.45, square=True)
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.25, 0.0, 0.6, 0.62), STEEL, normal=(1, 0, 0), ao=0.1)
    for k in range(5):
        vv = 0.1 + k * 0.1
        sp.line(add(add(o, mul(e1, 0.25)), mul(e2, vv)), add(add(o, mul(e1, 0.6)), mul(e2, vv)), 0.03, "#7d848d")
    sp.lamp(add(add(o, mul(e1, 0.425)), mul(e2, 0.7)), AMBER, 9)
    # 지붕 설비
    sp.box(-6.8, -1.6, hb, 2.4, 2.0, 1.0, STEEL, top=SILVER)
    sp.box(-3.4, -1.8, hb, 1.6, 1.6, 0.8, WHITE)
    if v != 1:
        for i in range(3):
            sp.cyl((-0.8 + i * 0.0, -1.2 + i * 1.6, hb), (-0.8, -1.2 + i * 1.6, hb + 0.5), 0.5, STEEL, cap_mat=CHAR)
    # 주황 단열 배관: 탑 → 지붕 → 방열판 머리관
    pipe(sp, [(tx + 1.0, ty + 0.9, 6.2), (tx + 1.0, by0 + 0.4, 6.2), (tx + 1.0, by0 + 0.4, hb)], 0.32, "#d8853b")
    pipe(sp, [(tx + 1.3, ty + 0.3, 3.0), (bx1 - 0.6, ty + 0.3, 3.0), (bx1 - 0.6, by0, 3.0)], 0.3, "#d8853b")
    pipe(sp, [(bx1, 0.4, 1.2), (2.6, 0.4, 1.2), (2.6, 0.4, 0.6)], 0.3, "#d8853b")
    # 배수 탱크 (앞)
    if v != 2:
        for i, x in enumerate((-7.2, -4.2)):
            sp.box(x + 0.4, 4.8, 0, 0.4, 1.4, 0.7, STEEL)
            sp.box(x + 2.0, 4.8, 0, 0.4, 1.4, 0.7, STEEL)
            sp.cyl((x, 5.5, 1.2), (x + 2.6, 5.5, 1.2), 0.75, FOAM, cap_mat=FOAM, bands=[0.5])
    sp.lamp((tx, ty, th + 0.9), RED_LIGHT, 8)
    sp.lamp((1.7, 4.3, 3.0), AMBER, 8)
    sp.glow((tx, ty, th * 0.5), 26, SALT, 0.3)


def _torus_items(sp: Sprite, c, R, r, mat: Mat, seg=28):
    items = []
    ext = r * math.tan(math.pi / seg) * 1.1
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        p0 = (c[0] + R * math.cos(a0), c[1] + R * math.sin(a0), c[2])
        p1 = (c[0] + R * math.cos(a1), c[1] + R * math.sin(a1), c[2])
        d = norm(sub(p1, p0))
        q0, q1 = sub(p0, mul(d, ext)), add(p1, mul(d, ext))
        am = (a0 + a1) / 2
        mid = (c[0] + R * math.cos(am), c[1] + R * math.sin(am), c[2])
        items.append((mid, lambda q0=q0, q1=q1: sp.cyl(q0, q1, r, mat, caps=False, edge=False)))
    return items


def _coil_items(sp: Sprite, c, R, r, n=12, color="#C98A4B", width=0.32, phase=0.0):
    """토카막의 D자 자석 코일: 바깥 호와 안쪽 다리를 따로 (깊이 순서용)."""
    items = []
    ri, ro, hz = R - r - 0.3, R + r + 0.42, r + 0.55
    for k in range(n):
        phi = 2 * math.pi * k / n + phase
        rho = (math.cos(phi), math.sin(phi), 0.0)

        def P_(rad, z, rho=rho):
            return (c[0] + rho[0] * rad, c[1] + rho[1] * rad, c[2] + z)

        arc = [P_(ri + (ro - ri) * math.cos(t), hz * math.sin(t))
               for t in [-math.pi / 2 + math.pi * j / 10 for j in range(11)]]
        leg = [P_(ri, hz), P_(ri, -hz)]
        items.append((P_(ro, 0), lambda arc=arc: sp.polyline3(arc, color, width)))
        items.append((P_(ri, 0), lambda leg=leg: sp.polyline3(leg, color, width)))
    return items


def _glass_dome(sp: Sprite, c, r, h, rib="#c9d6e2", n_mer=12, rings=(0.25, 0.5, 0.72, 0.9)):
    """반투명 돔 (2D는 흐린 채움 + 갈빗대, 3D는 유리 껍질)."""
    pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            pts.append(P(c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th),
                         c[2] + h * math.sin(ph)))
    sil = hull(pts)
    hl = PV((c[0] - r * 0.3, c[1] + r * 0.45, c[2] + h * 0.75))
    fill = sp.radial([(0, "#ffffff", 0.30), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.06)], hl[0], hl[1], r * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_shell(c, r, r, h, c[2])
    for k in rings:
        zz = c[2] + h * k
        rr = r * math.sqrt(max(0.0, 1 - k * k))
        sp.ring3((c[0], c[1], zz), rr, rib, 0.06, opacity=0.6)
    for i in range(n_mer):
        th = 2 * math.pi * i / n_mer
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.2:
            continue
        mer = [(c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th), c[2] + h * math.sin(ph))
               for ph in [k * math.pi / 2 / 12 for k in range(13)]]
        sp.polyline3(mer, rib, 0.06, 0.55)


def _pylon(sp: Sprite, x, y, h, arm=(1.0, 0.0, 0.0), w=1.0):
    sp.line((x, y, 0), (x, y, h), 0.2, "#8a9099")
    a = mul(norm(arm), w)
    sp.line((x - a[0], y - a[1], h - 0.6), (x + a[0], y + a[1], h - 0.6), 0.14, "#8a9099")
    for s in (-1, 1):
        sp.line((x + a[0] * s * 0.9, y + a[1] * s * 0.9, h - 0.6), (x + a[0] * s * 0.9, y + a[1] * s * 0.9, h - 0.95),
                0.1, "#d8d2c6")
    sp.line((x, y, h), (x, y, h - 0.35), 0.1, "#d8d2c6")
    return [(x + a[0] * 0.9, y + a[1] * 0.9, h - 0.95), (x, y, h - 0.35), (x - a[0] * 0.9, y - a[1] * 0.9, h - 0.95)]


def _wire(sp: Sprite, a, b, sag=0.7, color="#3a3f47"):
    pts = []
    for i in range(9):
        t = i / 8
        p = add(a, mul(sub(b, a), t))
        pts.append((p[0], p[1], p[2] - sag * 4 * t * (1 - t)))
    sp.polyline3(pts, color, 0.04)


VESSEL = Mat("#AEB5BE", 0.45)


def _tokamak(sp: Sprite, c, n=12, color="#C98A4B", width=0.32, R=3.3, r=1.12):
    """도넛형 진공 용기 + D자 코일 + 가운데 솔레노이드 + 받침 + 위쪽 고리 코일 (뒤에서 앞으로 섞어 그린다)."""
    cx, cy, zc = c
    items = _torus_items(sp, c, R, r, VESSEL)
    items += _coil_items(sp, c, R, r, n, color, width)
    items.append((c, lambda: sp.cyl((cx, cy, zc - 2.1), (cx, cy, zc + 1.9), 0.85, COPPER, bands=[0.25, 0.5, 0.75])))
    for x, y in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        items.append(((cx + x * 2.3, cy + y * 2.3, zc - 1.7),
                      lambda x=x, y=y: sp.box(cx + x * 2.3 - 0.3, cy + y * 2.3 - 0.3, zc - 2.1, 0.6, 0.6, 2.2 - r, STEEL)))
    # 고리 코일: 뒤쪽 반은 솔레노이드보다 먼저, 앞쪽 반은 맨 나중에
    zr, rr = zc + r + 0.75, R - 0.2
    ring = [(cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a)), zr) for a in range(-45, 316, 10)]
    items.append(((cx - 0.01, cy - 0.01, zc), lambda: sp.polyline3(ring[18:], "#7d848d", 0.16)))
    items.append(((cx + 9.0, cy + 9.0, zc), lambda: sp.polyline3(ring[:19], "#7d848d", 0.16)))
    sp.parts(items)
    sp.glow(c, 40, PLASMA, 0.55)


def _power_line(sp: Sprite, x, ys, transformer, h=9.6):
    """철탑 줄과 늘어진 전선 + 첫 철탑으로 이어지는 변압기."""
    tops = [_pylon(sp, x, y, h) for y in ys]
    for t0, t1 in zip(tops, tops[1:]):
        for a, b in zip(t0, t1):
            _wire(sp, a, b)
    bx, by = transformer
    sp.box(bx, by, 0, 1.8, 1.6, 2.0, DARK, top=STEEL)
    _louvers(sp, Sprite.box_faces(bx, by, 0, 1.8, 1.6, 2.0)["left"], 0.1, 0.9, 0.15, 0.85, 6, Mat("#30353c"))
    sp.line((bx + 0.9, by + 0.8, 2.0), (bx + 0.9, by + 0.8, 2.4), 0.1, "#d8d2c6")
    for a in tops[0]:
        _wire(sp, (bx + 0.9, by + 0.8, 2.3), a, 0.4)


@typed("he3_fusion_pilot", 20, 20, 12.0, "헬륨-3 핵융합 시험로", heights=[12.0, 12.0, 12.0, 12.0, 12.0])
def he3_fusion_pilot(sp: Sprite, v: int):
    """자석 코일을 감은 토카막 고리 + 그 위를 덮은 저온 유지 돔 + 제어동 + 송전선."""
    sp.contact_shadow(0, 0, 10.4, 10.4, 0.45)
    cx, cy = (-2.2, -1.8)
    rd = 6.4
    hd = 8.8 if v != 4 else 8.0
    # 돔 뒤: 송전선 (오른쪽 가장자리)·변압기·방열판
    _power_line(sp, 8.6, [-8.4, -1.6] if v != 3 else [-8.4, -3.6, 1.2], (4.6, -5.6))
    if v == 2:
        for i in range(3):
            _rad(sp, (-9.6 + i * 2.3, -9.4, 0.3), (2.1, 0, 0), (0, 0, 4.2), 4, 1)
        pipe(sp, [(-9.6, -9.0, 0.5), (-2.8, -9.0, 0.5), (-2.8, -7.9, 0.5)], 0.18, "#B8733F")
    # 저온 유지 돔의 받침 벽
    sp.cyl((cx, cy, 0), (cx, cy, 1.6), rd + 0.3, CONCRETE, cap_mat=Mat("#3e434b"))
    _tokamak(sp, (cx, cy, 3.7), 12 if v != 1 else 16, "#C98A4B" if v != 2 else "#3E6FB0", 0.32 if v != 1 else 0.26)
    _glass_dome(sp, (cx, cy, 1.6), rd, hd, n_mer=14 if v != 1 else 10)
    top = 1.6 + hd
    sp.cyl((cx, cy, top - 0.15), (cx, cy, top + 0.3), 0.9, STEEL)
    sp.line((cx, cy, top + 0.3), (cx, cy, 11.8), 0.08, "#9aa1aa")
    sp.lamp((cx, cy, 11.9), RED_LIGHT, 8)
    # 받침 벽의 창
    for ang in (35.0, 75.0):
        a = math.radians(ang)
        n = (math.cos(a), math.sin(a), 0.0)
        t = (-math.sin(a), math.cos(a), 0.0)
        c = add((cx, cy, 0.0), mul(n, rd + 0.32))
        sp.window([add(add(c, mul(t, -0.6)), (0, 0, 0.6)), add(add(c, mul(t, 0.6)), (0, 0, 0.6)),
                   add(add(c, mul(t, 0.6)), (0, 0, 1.2)), add(add(c, mul(t, -0.6)), (0, 0, 1.2))])
    # 헬륨-3 탱크 (앞 왼쪽)
    if v == 3:
        for y in (4.4, 6.6):
            sp.box(-8.6, y - 0.6, 0, 0.4, 1.2, 0.6, STEEL)
            sp.box(-5.6, y - 0.6, 0, 0.4, 1.2, 0.6, STEEL)
            sp.cyl((-9.2, y, 1.25), (-4.8, y, 1.25), 0.8, WHITE, cap_mat=WHITE, bands=[0.15, 0.85],
                   band_color="#3E6FB0")
        pipe(sp, [(-4.8, 4.4, 1.25), (cx - 2.4, cy + rd - 0.6, 0.6)], 0.16)
    elif v == 4:
        sp.box(-9.0, 3.6, 0, 3.6, 3.0, 2.4, WHITE, top=SILVER)
        fb = Sprite.box_faces(-9.0, 3.6, 0, 3.6, 3.0, 2.4)
        _louvers(sp, fb["left"], 0.1, 0.6, 0.2, 0.75, 5)
        for x in (-8.0, -6.4):
            sp.cyl((x, 5.1, 2.4), (x, 5.1, 2.8), 0.55, STEEL, cap_mat=CHAR)
        pipe(sp, [(-5.4, 5.0, 1.4), (cx - 2.4, cy + rd - 0.6, 0.6)], 0.2, "#B8733F")
        sp.lamp((-5.3, 6.6, 2.0), CYAN_LIGHT, 7)
    else:
        for x, y, rr in ((-8.0, 4.6, 1.1), (-7.4, 7.4, 0.9)):
            legs(sp, [(x - rr * 0.6, y - rr * 0.6, rr + 0.2), (x + rr * 0.6, y - rr * 0.6, rr + 0.2),
                      (x - rr * 0.6, y + rr * 0.6, rr + 0.2), (x + rr * 0.6, y + rr * 0.6, rr + 0.2)], 0.0)
            sp.sphere((x, y, rr + 0.5), rr, WHITE)
            sp.ring3((x, y, rr + 0.5), rr, "#3E6FB0", 0.1)
        pipe(sp, [(-6.9, 4.6, 0.4), (cx - 2.0, cy + rd - 0.4, 0.4)], 0.16)
    # 제어동 (앞 오른쪽)
    qx0, qy0 = (3.6, 4.0) if v != 1 else (2.6, 5.0)
    f = _hut(sp, qx0, qy0, 5.2, 3.8, 3.4, Mat("#9B7AD6"), 4, both=True)
    windows_row(sp, f["right"], 1, 0.42, 0.68, 0.72, 0.08)
    sp.disc((qx0 + 1.2, qy0 + 1.2, 4.1), (0.3, 0.6, 0.75), 0.8, WHITE, back=STEEL)
    sp.line((qx0 + 1.2, qy0 + 1.2, 3.4), (qx0 + 1.2, qy0 + 1.2, 4.0), 0.1, "#9aa1aa")
    sp.lamp((qx0 + 5.3, qy0 + 3.9, 3.0), AMBER, 9)
    pipe(sp, [(qx0, qy0 + 1.0, 0.3), (cx + rd * 0.72, cy + rd * 0.72, 0.3)], 0.14, "#5c626b")
    sp.lamp((cx + rd * 0.7, cy + rd * 0.7, 1.9), AMBER, 8)


# ── 배터리 계열 ─────────────────────────────────────────────────────────

def _xprism(sp: Sprite, x0, x1, prof, mat: Mat, top: Mat | None = None):
    """yz 단면(반시계, +x에서 볼 때) prof를 x0→x1로 민 기둥. 윗면(법선이 위로 가까운 면)은 top."""
    n = len(prof)
    for i in range(n):
        (ay, az), (by, bz) = prof[i], prof[(i + 1) % n]
        up = (bz - az) == 0 and by < ay
        sp.face([(x0, ay, az), (x0, by, bz), (x1, by, bz), (x1, ay, az)], (top or mat) if up else mat, ao=0.15)
    sp.face([(x1, y, z) for y, z in prof], mat, normal=(1, 0, 0), ao=0)


def _sleek_box(sp: Sprite, x0, x1, y0, y1, z0, h, ch=0.3):
    prof = [(y0, z0), (y1, z0), (y1, z0 + h - ch), (y1 - ch, z0 + h), (y0 + ch, z0 + h), (y0, z0 + h - ch)]
    _xprism(sp, x0, x1, prof, SLEEK, SLEEK_TOP)
    L = x1 - x0
    front = ((x1, y1, z0), (-L, 0.0, 0.0), (0.0, 0.0, h - ch))
    end = ((x1, y0, z0), (0.0, y1 - y0, 0.0), (0.0, 0.0, h - ch))
    return front, end


@typed("solid_state_bank", 7, 4, 2.4, "전고체 배터리", heights=[2.4, 2.9, 2.4, 2.4, 2.4])
def solid_state_bank(sp: Sprite, v: int):
    """매끈한 검은 컨테이너 + 파란 상태 표시등 띠 + 냉각 루버."""
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.4, -1.7, 0, 6.8, 3.4, 0.2, Mat("#3a3f46", 0.2))
    if v == 2:
        boxes = [(-3.2, -0.2), (0.2, 3.2)]
    else:
        boxes = [(-3.2, 3.2)] if v != 4 else [(-3.2, 2.0)]
    for a, b in boxes:
        front, end = _sleek_box(sp, a, b, -1.4, 1.4, 0.2, 2.2)
        L = b - a
        if v == 4:
            for k in range(6):
                u = 0.12 + k * 0.13
                _strip(sp, front, u, u + 0.03, 0.25, 0.85, STRIP_BLUE, BLUE_LIGHT, 0.85)
        else:
            _strip(sp, front, 0.04, 0.96, 0.83, 0.88, STRIP_BLUE, BLUE_LIGHT, 0.9)
            _louvers(sp, front, 0.08, 0.92 if v != 3 else 0.6, 0.15, 0.62, 6, Mat("#15181d", 0.2))
        _louvers(sp, end, 0.15, 0.85, 0.2, 0.75, 6, Mat("#15181d", 0.2))
        _strip(sp, end, 0.1, 0.9, 0.85, 0.9, STRIP_BLUE, BLUE_LIGHT, 0.9)
        if v == 1:
            for x in (a + L * 0.3, a + L * 0.7):
                sp.cyl((x, 0, 2.4), (x, 0, 2.75), 0.55, Mat("#30353c", 0.3), cap_mat=CHAR)
                sp.ring3((x, 0, 2.77), 0.42, "#6a717b", 0.05)
                sp.line((x - 0.4, 0, 2.77), (x + 0.4, 0, 2.77), 0.06, "#6a717b")
    if v == 2:
        pipe(sp, [(-0.2, 0.0, 1.8), (0.2, 0.0, 1.8)], 0.2, "#2a2f36")
    if v == 3:
        for x in (-3.0, -1.0, 1.0, 3.0):
            sp.line((x, 1.65, 0.2), (x, 1.65, 1.3), 0.06, "#7d848d")
        sp.box(-3.2, 1.45, 1.3, 6.4, 0.4, 0.12, STEEL)
        sp.line((-3.1, 1.65, 1.46), (3.1, 1.65, 1.46), 0.12, "#2a2f36")
        sp.lamp((3.3, 1.6, 1.6), BLUE_LIGHT, 7)
    if v == 4:
        sp.box(2.3, -1.2, 0.2, 0.9, 2.4, 1.4, WHITE, top=SILVER)
        fb = Sprite.box_faces(2.3, -1.2, 0.2, 0.9, 2.4, 1.4)
        sp.disc((3.22, 0.0, 0.95), (1, 0, 0), 0.45, CHAR, two_sided=False)
        sp.ring3((3.23, 0.0, 0.95), 0.45, "#9aa1aa", 0.05, normal=(1, 0, 0), front_only=False)
        band_on(sp, fb["left"], 0.82, 0.92, BLUE)
    sp.lamp((3.3, -1.3, 0.5) if v != 3 else (-3.3, 1.5, 0.5), BLUE_LIGHT, 6)


@typed("nickel_hydrogen_bank", 6, 4, 2.8, "니켈-수소 전지", heights=[2.8, 2.8, 2.6, 2.8, 2.8])
def nickel_hydrogen_bank(sp: Sprite, v: int):
    """강철 틀에 세워 꽂은 캡슐 모양 압력 용기 셀들."""
    sp.contact_shadow(0, 0, 3.4, 2.4)
    sp.box(-3.0, -2.0, 0, 6.0, 4.0, 0.2, SINTER)
    cols = 6 if v != 2 else 5
    rows = (-0.85, 0.85) if v != 3 else (-1.1, 0.0, 1.1)
    r = 0.34 if v != 3 else 0.3
    x0, x1 = -2.3, 1.9 if v != 4 else 1.0
    zt = 2.6 if v != 2 else 2.4
    sleeve = (Mat("#C9A75A", 0.4), TEAL, Mat("#C9A75A", 0.4), Mat("#E6E2D8", 0.2), Mat("#C9A75A", 0.4))[v]
    fr = "#7d848d"
    # 틀: 뒤쪽 기둥·난간
    X0, X1, Y0, Y1 = x0 - 0.55, x1 + 0.55, rows[0] - 0.55, rows[-1] + 0.55
    for x, y in ((X0, Y0), (X1, Y0), (X0, Y1)):
        sp.line((x, y, 0.2), (x, y, zt - 0.3), 0.1, fr)
    sp.polyline3([(X0, Y1, zt - 0.3), (X0, Y0, zt - 0.3), (X1, Y0, zt - 0.3)], fr, 0.08)
    sp.polyline3([(X0, Y1, 0.5), (X0, Y0, 0.5), (X1, Y0, 0.5)], fr, 0.08)
    for y in rows:
        for i in range(cols):
            x = x0 + i * (x1 - x0) / (cols - 1)
            sp.cyl((x, y, 0.2), (x, y, 0.45), r + 0.08, STEEL)
            p0, p1 = (x, y, 0.45), (x, y, zt - r)
            sp.cyl(p0, p1, r, SILVER, caps=False)
            cyl_ring(sp, p0, p1, r, 0.2, 0.7, sleeve)
            sp.sphere((x, y, zt - r), r, SILVER, clip_z=zt - r)
            sp.line((x, y, zt - 0.05), (x, y, zt + 0.12), 0.07, "#B8733F")
        sp.line((x0, y, zt + 0.12), (x1, y, zt + 0.12), 0.08, "#B8733F")
    sp.polyline3([(X1, Y0, zt - 0.3), (X1, Y1, zt - 0.3), (X0, Y1, zt - 0.3)], fr, 0.08)
    sp.polyline3([(X1, Y0, 0.5), (X1, Y1, 0.5), (X0, Y1, 0.5)], fr, 0.08)
    sp.line((X1, Y1, 0.2), (X1, Y1, zt - 0.3), 0.1, fr)
    # 제어 상자
    if v == 4:
        sp.box(1.8, -1.6, 0.2, 1.0, 3.2, 1.6, BATT, top=BATT_TOP)
        f = Sprite.box_faces(1.8, -1.6, 0.2, 1.0, 3.2, 1.6)
        windows_row(sp, f["right"], 2, 0.5, 0.75, 0.15, 0.2, GREEN_LIGHT)
    else:
        sp.box(X1 + 0.05, Y1 - 0.9, 0.2, 0.45, 0.8, 1.2, BATT, top=BATT_TOP)
        sp.window(sp.on_face(*Sprite.box_faces(X1 + 0.05, Y1 - 0.9, 0.2, 0.45, 0.8, 1.2)["right"],
                             0.25, 0.6, 0.75, 0.8), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
    sp.lamp((X1 + 0.3, Y1 + 0.2, 1.2), GREEN_LIGHT, 6)


@typed("supercap_bank", 4, 3, 2.0, "초고용량 축전기", heights=[2.0, 2.1, 2.2, 2.0, 2.0])
def supercap_bank(sp: Sprite, v: int):
    """작은 함 위에 원통 축전기 깡통을 빽빽이 세운다."""
    sp.contact_shadow(0, 0, 2.4, 1.9)
    hb = 1.05
    sp.box(-1.8, -1.3, 0, 3.6, 2.6, hb, WHITE if v != 3 else BATT, top=SILVER if v != 3 else BATT_TOP)
    f = Sprite.box_faces(-1.8, -1.3, 0, 3.6, 2.6, hb)
    _louvers(sp, f["left"], 0.08, 0.55, 0.2, 0.8, 4, Mat("#5c626b"))
    _strip(sp, f["left"], 0.62, 0.92, 0.55, 0.68, Mat("#2c8f4f", 0.4), GREEN_LIGHT, 0.8)
    _louvers(sp, f["right"], 0.15, 0.85, 0.25, 0.75, 3, Mat("#5c626b"))
    can = (CAN_BLUE, Mat("#C9CED6", 0.5), Mat("#2E3238", 0.35), TEAL, CAN_BLUE)[v]
    cap = SILVER if v != 1 else Mat("#2F5E9E", 0.4)
    nx, ny = (5, 3) if v != 2 else (4, 2)
    r = 0.24 if v != 2 else 0.32
    h = 0.85 if v != 2 else 1.1
    xs = [-1.4 + i * 2.8 / (nx - 1) for i in range(nx)]
    ys = [-0.85 + j * 1.7 / (ny - 1) for j in range(ny)]
    cans = sorted([(x, y) for x in xs for y in ys], key=lambda p: p[0] + p[1])
    for x, y in cans:
        if v == 4 and x > 0.9 and y > 0.5:
            continue
        sp.cyl((x, y, hb), (x, y, hb + h), r, can, cap_mat=cap)
        sp.ring3((x, y, hb + h + 0.01), r * 0.6, "#8a9099", 0.03)
    for y in ys:
        sp.line((xs[0], y + r * 0.6, hb + h + 0.06), (xs[-1], y + r * 0.6, hb + h + 0.06), 0.07, "#B8733F")
    if v == 4:
        sp.box(1.0, 0.45, hb, 0.75, 0.75, 0.5, STEEL, top=SILVER)
        sp.lamp((1.4, 1.25, hb + 0.3), AMBER, 5)
    if v == 1:
        sp.line((1.9, 1.3, 0), (1.9, 1.3, 1.9), 0.05, "#9aa1aa")
        sp.lamp((1.9, 1.3, 1.95), CYAN_LIGHT, 6)
    else:
        sp.lamp((1.85, 0.9, 0.6), CYAN_LIGHT, 6)


@typed("sodium_bank", 7, 4, 2.6, "나트륨이온 배터리", heights=[2.6, 2.6, 2.4, 2.6, 2.6])
def sodium_bank(sp: Sprite, v: int):
    """베이지색 모듈 상자를 한 줄로 늘어놓고 주황 커넥터와 케이블 받침을 단다."""
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.5, -2.0, 0, 7.0, 4.0, 0.2, SINTER)
    n = 5 if v != 2 else 4
    w = 1.1 if v != 2 else 1.45
    gap = (6.6 - n * w) / (n - 1)
    hb = 2.0 if v != 2 else 1.8
    y0, d = -1.5, 2.4
    tray_z = hb + 0.45
    # 뒤쪽 케이블 받침 기둥
    if v != 3:
        for x in (-3.2, 3.2):
            sp.line((x, y0 + 0.2, 0.2), (x, y0 + 0.2, tray_z), 0.08, "#7d848d")
    for i in range(n):
        x = -3.3 + i * (w + gap)
        sp.box(x, y0, 0.2, w, d, hb, BEIGE, top=BEIGE_TOP)
        f = Sprite.box_faces(x, y0, 0.2, w, d, hb)
        o, e1, e2 = f["left"]
        sp.face(sp.on_face(o, e1, e2, 0.1, 0.06, 0.9, 0.12), Mat("#B8A983"), normal=(0, 1, 0), ao=0, edge=False)
        for u in (0.28, 0.72):
            c = add(add(o, mul(e1, u)), mul(e2, 0.72))
            sp.cyl(c, add(c, (0, 0.16, 0)), 0.15, ORANGE, cap_mat=Mat("#F08A45", 0.15))
            sp.disc(add(c, (0, 0.17, 0)), (0, 1, 0), 0.07, CHAR, two_sided=False)
        sp.window(sp.on_face(o, e1, e2, 0.4, 0.4, 0.6, 0.48), GREEN_LIGHT if v != 4 else AMBER, frame=None,
                  glass=Mat("#2c8f4f", 0.4) if v != 4 else Mat("#8f6a2c", 0.4), light_alpha=0.8)
        if v == 4:
            sp.box(x + 0.2, y0 + 0.9, 0.2 + hb, w - 0.4, 1.0, 0.3, STEEL, top=SILVER)
            _louvers(sp, Sprite.box_faces(x + 0.2, y0 + 0.9, 0.2 + hb, w - 0.4, 1.0, 0.3)["left"], 0.1, 0.9, 0.2, 0.8, 2)
    # 앞쪽 주황 케이블 (모듈을 잇는다)
    zc = 0.2 + hb * 0.72
    pts = []
    for i in range(n):
        x = -3.3 + i * (w + gap)
        pts += [(x + w * 0.28, y0 + d + 0.2, zc), (x + w * 0.28, y0 + d + 0.28, zc - 0.4),
                (x + w * 0.72, y0 + d + 0.28, zc - 0.4), (x + w * 0.72, y0 + d + 0.2, zc)]
    sp.polyline3(pts, "#E8823E", 0.08)
    # 위쪽 케이블 받침 (얕은 홈통)
    if v != 3:
        sp.box(-3.3, y0 + 0.05, tray_z - 0.12, 6.6, 0.45, 0.12, STEEL)
        sp.line((-3.2, y0 + 0.28, tray_z + 0.02), (3.2, y0 + 0.28, tray_z + 0.02), 0.1, "#2a2f36")
        sp.line((-3.2, y0 + 0.16, tray_z + 0.02), (3.2, y0 + 0.16, tray_z + 0.02), 0.08, "#E07B39")
        for i in range(n):
            x = -3.3 + i * (w + gap) + w * 0.5
            sp.polyline3([(x, y0 + 0.3, tray_z - 0.12), (x, y0 + 0.3, hb + 0.2)], "#2a2f36", 0.07)
    else:
        sp.box(-3.4, 1.15, 0.2, 6.8, 0.5, 0.12, STEEL)
        sp.line((-3.3, 1.4, 0.34), (3.3, 1.4, 0.34), 0.12, "#2a2f36")
    if v == 1:
        sp.box(3.0, -1.7, 0.2, 0.45, 1.2, 1.2, WHITE, top=SILVER)
    if v != 3:
        sp.line((3.2, y0 + 0.2, 0.2), (3.2, y0 + 0.2, tray_z), 0.08, "#7d848d")
    sp.lamp((3.4, 1.85, 0.8), AMBER, 6)


# ── 재생 연료전지 계열 ──────────────────────────────────────────────────

def _capsule_y(sp: Sprite, x, y0, y1, z, r, mat: Mat, band=None, band_at=0.8):
    """y 방향으로 누운 캡슐 탱크 (반구 끝). 뒤 끝 → 몸통 → 앞 끝 순서."""
    sp.sphere((x, y0, z), r, mat)
    sp.cyl((x, y0, z), (x, y1, z), r, mat, caps=False, bands=[0.5])
    if band:
        sp.ring3((x, y0 + (y1 - y0) * band_at, z), r + 0.01, band, 0.22, normal=(0, 1, 0))
    sp.sphere((x, y1, z), r, mat)


def _capsule_x(sp: Sprite, x0, x1, y, z, r, mat: Mat, band=None, band_at=0.8):
    sp.sphere((x0, y, z), r, mat)
    sp.cyl((x0, y, z), (x1, y, z), r, mat, caps=False, bands=[0.5])
    if band:
        sp.ring3((x0 + (x1 - x0) * band_at, y, z), r + 0.01, band, 0.22, normal=(1, 0, 0))
    sp.sphere((x1, y, z), r, mat)


@typed("rfc_large", 8, 6, 4.0, "대형 재생 연료전지", heights=[3.9, 3.9, 3.8, 4.2, 3.9])
def rfc_large(sp: Sprite, v: int):
    """큰 수소 캡슐 탱크(왼쪽)와 작은 산소 캡슐 탱크(오른쪽), 그 사이의 연료전지·전해조 상자."""
    sp.contact_shadow(0, 0, 4.4, 3.4)
    sp.box(-4.0, -3.0, 0, 8.0, 6.0, 0.25, SINTER)
    hx, hr, hz = -2.4, 1.42, 1.85
    ox, orr, oz = 2.55, 0.95, 1.35
    hy0, hy1 = (-1.45, 1.45) if v != 2 else (-1.2, 1.2)
    oy0, oy1 = -1.0, 1.0
    if v == 4:
        hx, ox = -2.3, 2.6
    # 받침
    for y in (hy0 + 0.3, hy1 - 0.3):
        sp.box(hx - 0.9, y - 0.25, 0.25, 1.8, 0.5, hz - hr * 0.6 - 0.25, STEEL)
    _capsule_y(sp, hx, hy0, hy1, hz, hr, WHITE, "#d8853b", 0.75)
    if v == 3:
        sp.line((hx, 0.0, hz + hr), (hx, 0.0, 4.2), 0.12, "#9aa1aa")
        sp.lamp((hx, 0.0, 4.3), RED_LIGHT, 6)
    # 가운데 상자 (연료전지·전해조)
    bx0, bx1 = -0.7, 1.3
    by0, by1 = -1.6, 1.4
    hb = 2.9
    sp.box(bx0, by0, 0.25, bx1 - bx0, by1 - by0, hb, BATT, top=SILVER)
    f = Sprite.box_faces(bx0, by0, 0.25, bx1 - bx0, by1 - by0, hb)
    windows_row(sp, f["left"], 2, 0.45, 0.72, 0.15, 0.12, CYAN_LIGHT)
    band_on(sp, f["left"], 0.84, 0.92, TEAL)
    _louvers(sp, f["right"], 0.1, 0.9, 0.2, 0.75, 5, Mat("#3a3f46"))
    sp.box(bx0 + 0.3, by0 + 0.5, hb + 0.25, 1.2, 1.4, 0.45, STEEL, top=SILVER)
    sp.cyl((bx0 + 0.9, by0 + 1.2, hb + 0.7), (bx0 + 0.9, by0 + 1.2, 3.95), 0.1, SILVER)
    if v == 1:
        _rad(sp, (bx0 + 0.2, by0 + 0.3, hb + 0.7), (1.6, 0, 0), (0, 0, 0.7), 3, 1)
    # 배관: 탱크 ↔ 상자
    pipe(sp, [(hx + hr * 0.7, 0.8, hz + 0.5), (bx0, 0.8, hz + 0.5)], 0.16)
    pipe(sp, [(bx1, 0.6, 1.4), (ox - orr * 0.7, 0.6, 1.4)], 0.16)
    # 산소 탱크 (작다)
    for y in (oy0 + 0.25, oy1 - 0.25):
        sp.box(ox - 0.6, y - 0.22, 0.25, 1.2, 0.44, oz - orr * 0.6 - 0.25, STEEL)
    _capsule_y(sp, ox, oy0, oy1, oz, orr, WHITE, "#3FB8AF", 0.75)
    if v == 2:
        sp.box(-3.8, 2.0, 0.25, 1.0, 0.8, 0.8, ORANGE)
        sp.box(2.2, 1.9, 0.25, 1.1, 0.9, 0.9, Mat("#C9A23A"))
    if v == 4:
        sp.box(bx1 + 0.1, 1.9, 0.25, 1.3, 0.9, 1.1, WHITE, top=SILVER)
        sp.lamp((bx1 + 1.45, 2.35, 1.2), AMBER, 7)
    sp.lamp((bx1 + 0.05, by1 + 0.05, 2.7), CYAN_LIGHT, 7)


@typed("iron_air_bank", 8, 5, 2.8, "철-공기 장주기 전지", heights=[2.8, 2.8, 2.6, 2.8, 2.8])
def iron_air_bank(sp: Sprite, v: int):
    """길고 낮은 홈통들 속에 녹슨 빛 전극 더미 + 공기 흡입구."""
    sp.contact_shadow(0, 0, 4.4, 2.8)
    sp.box(-4.0, -2.5, 0, 8.0, 5.0, 0.2, SINTER)
    ys = (-1.55, 0.05, 1.65) if v != 2 else (-1.2, 1.2)
    tw = 1.3 if v != 2 else 1.9
    x0, x1 = -3.6, 2.6 if v != 4 else 3.2
    th = 0.85
    # 뒤쪽 흡입구 (버섯 갓)
    vents = [(-3.0, -2.15), (-0.6, -2.15), (1.8, -2.15)] if v != 3 else [(-3.4, -2.1), (3.3, -2.1)]
    if v == 1:
        sp.cyl((-3.6, -2.15, 1.5), (2.4, -2.15, 1.5), 0.3, Mat("#8B9097", 0.3), bands=[0.2, 0.4, 0.6, 0.8],
               cap_mat=STEEL)
    for x, y in vents:
        sp.cyl((x, y, 0.2), (x, y, 2.3), 0.16, STEEL)
        sp.cyl((x, y, 2.3), (x, y, 2.5), 0.38, STEEL, cap_mat=SILVER)
        sp.frustum((x, y, 2.5), (x, y, 2.8), 0.4, 0.1, SILVER)
    for yc in ys:
        a, b = yc - tw / 2, yc + tw / 2
        sp.box(x0, a, 0.2, x1 - x0, tw, th, Mat("#8B9097", 0.2), top=Mat("#3A2E28", 0.3))
        f = Sprite.box_faces(x0, a, 0.2, x1 - x0, tw, th)
        band_on(sp, f["left"], 0.75, 0.85, Mat("#6E737A"))
        # 전극 더미
        n = 7 if v != 4 else 8
        sl = (x1 - x0 - 0.4) / n
        for i in range(n):
            sx = x0 + 0.2 + i * sl
            hs = 0.55 + 0.12 * ((i * 7 + int(yc * 10)) % 3) if v != 1 else 0.6
            sp.box(sx + 0.05, a + 0.15, 0.2 + th, sl - 0.1, tw - 0.3, hs, RUST, top=RUST_DARK)
            fo, fe1, fe2 = Sprite.box_faces(sx + 0.05, a + 0.15, 0.2 + th, sl - 0.1, tw - 0.3, hs)["left"]
            for k in (0.25, 0.5, 0.75):
                sp.line(add(fo, mul(fe1, k)), add(add(fo, mul(fe1, k)), fe2), 0.03, "#5a2e1c")
        # 홈통 끝의 흡입 루버
        sp.box(x1, a + 0.15, 0.2, 0.7, tw - 0.3, 1.25, STEEL, top=SILVER)
        _louvers(sp, Sprite.box_faces(x1, a + 0.15, 0.2, 0.7, tw - 0.3, 1.25)["right"], 0.12, 0.88, 0.2, 0.85, 5)
    if v == 4:
        sp.lamp((3.95, 2.3, 0.8), AMBER, 6)
    else:
        sp.box(x1 + 0.15, 1.9 if v != 2 else 2.0, 0.2, 0.9, 0.5, 1.4, WHITE, top=SILVER)
        sp.window(sp.on_face(*Sprite.box_faces(x1 + 0.15, 1.9 if v != 2 else 2.0, 0.2, 0.9, 0.5, 1.4)["left"],
                             0.3, 0.55, 0.7, 0.8), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
        sp.lamp((x1 + 1.1, 2.15, 1.5), AMBER, 6)


@typed("thermal_wadi", 7, 7, 2.2, "열 저장 와디", heights=[2.6, 2.6, 2.8, 2.5, 2.6])
def thermal_wadi(sp: Sprite, v: int):
    """소결 레골리스로 구운 낮은 덩어리 (검은 유리질 윗면) + 해를 덩어리로 비추는 반사경 + 작은 스털링 기관."""
    sp.contact_shadow(0, 0, 3.8, 3.8, 0.5)
    m = 1 if v != 4 else -1
    base = rounded_rect(-2.4, -1.4, 2.2, 3.0, 0.7) if m > 0 else rounded_rect(-1.4, -2.4, 3.0, 2.2, 0.7)
    cx = sum(p_[0] for p_ in base) / len(base)
    cy = sum(p_[1] for p_ in base) / len(base)
    hb = 1.5 if v != 3 else 1.3
    # 반사경 (덩어리 뒤): 해와 덩어리 사이를 보도록 기운 거울
    mx, my = (-0.6, -2.6) if m > 0 else (-2.4, -0.8)
    if v == 1:
        mx, my = (0.6, -2.7)
    mz = 2.0 if v != 2 else 2.2
    n = norm(add(SUN, norm(sub((cx, cy, hb), (mx, my, mz)))))
    up = norm(sub((0.0, 0.0, 1.0), mul(n, n[2])))
    e1 = cross(up, n)
    W, H = ((2.8, 1.6), (2.8, 1.6), (3.2, 1.8), (2.8, 1.6), (2.2, 1.6))[v]
    sp.box(mx - 0.35, my - 0.35, 0, 0.7, 0.7, 0.25, CONCRETE)
    sp.line((mx, my, 0.25), (mx, my, mz), 0.16, "#8a9099")
    c = (mx, my, mz)
    o = add(add(c, mul(e1, -W / 2)), mul(up, -H / 2))
    sp.quad(o, mul(e1, W), mul(up, H), MIRROR, back=STEEL)
    sp.panel_grid(o, mul(e1, W), mul(up, H), 3, 2, "#9fb3c4", 0.5, 0.6)
    sp.polyline3([o, add(o, mul(e1, W)), add(add(o, mul(e1, W)), mul(up, H)), add(o, mul(up, H)), o], "#8a9099", 0.08)
    # 열 저장 덩어리
    sp.prism(base, 0, hb, SINTER, top=GLASSY)
    print_lines(sp, base, 0.0, hb, 0.38)
    top_pts = [(x, y, hb + 0.01) for x, y in base]
    sp.light_poly(top_pts, "#ff7a3a", 0.35)
    sp.glow((cx, cy, hb + 0.2), 30, "#ff7a3a", 0.3)
    for a in (20, 110, 200, 290):
        r_ = 1.4 if v != 1 else 1.7
        t = math.radians(a)
        sp.line((cx + 0.3 * math.cos(t), cy + 0.3 * math.sin(t), hb + 0.02),
                (cx + r_ * math.cos(t), cy + r_ * math.sin(t), hb + 0.02), 0.04, "#5a4a3e", 0.8)
    # 스털링 기관 (앞 오른쪽)
    sx, sy = (2.6, -0.6) if m > 0 else (-0.6, 2.6)
    ax = (0.0, 1.0, 0.0) if m > 0 else (1.0, 0.0, 0.0)
    if m > 0:
        sp.box(sx - 0.6, sy - 0.8, 0, 1.2, 1.6, 0.35, STEEL)
    else:
        sp.box(sx - 0.8, sy - 0.6, 0, 1.6, 1.2, 0.35, STEEL)
    p0 = (sx - 0.6 * ax[0], sy - 0.6 * ax[1], 0.9)
    p1 = add(p0, mul(ax, 1.2))
    if v in (0, 3):
        side = (1.0, 0.0, 0.0) if m > 0 else (0.0, 1.0, 0.0)
        _rad(sp, add((sx, sy, 0.35), mul(side, -0.55)), mul(ax, -1.2 if m > 0 else 1.2), (0, 0, 1.3), 3, 1)
    sp.cyl(p0, p1, 0.42, SILVER, bands=[0.2, 0.3, 0.4, 0.5, 0.6], band_color="#6f757d", cap_mat=STEEL)
    sp.cyl(p1, add(p1, mul(ax, 0.3)), 0.25, GOLD)
    pipe(sp, [(cx + 1.6 * (1 if m > 0 else 0.4), cy + (-0.4 if m > 0 else 1.6), 0.8), p0], 0.16, "#B8733F")
    if v == 1:
        sp.box(-3.2, 2.6, 0, 1.0, 0.7, 0.9, WHITE, top=SILVER)
    sp.lamp(add(p1, (0.1, 0.1, 0.6)), AMBER, 7)


@typed("gas_store", 6, 4, 3.0, "압축 기체 축전기", heights=[3.0, 3.2, 3.0, 3.0, 3.0])
def gas_store(sp: Sprite, v: int):
    """틀에 위아래로 얹은 긴 고압 실린더 두 개 + 압축기·터빈 상자 (나선 케이싱)."""
    sp.contact_shadow(0, 0, 3.4, 2.4)
    sp.box(-3.0, -2.0, 0, 6.0, 4.0, 0.2, SINTER)
    gas = (GAS, GAS, Mat("#6B7E95", 0.3), GAS, Mat("#9A9CA3", 0.4))[v]
    band = ("#E9C24A", "#ECE7DC", "#E9C24A", "#E9C24A", "#D9532C")[v]
    y = -0.85
    x0, x1 = (-2.3, 2.0) if v != 3 else (-1.9, 2.3)
    r = 0.62
    zs = (0.95, 2.3)
    posts = (x0 + 0.3, x1 - 0.3)
    for x in posts:
        sp.line((x, y - 0.7, 0.2), (x, y - 0.7, 2.95), 0.1, "#7d848d")
    for z in zs:
        for x in posts:
            sp.box(x - 0.15, y - 0.7, z - r - 0.12, 0.3, 1.4, 0.12, STEEL)
        _capsule_x(sp, x0, x1, y, z, r, gas, band, 0.15)
        if v == 1:
            sp.ring3((x0 + (x1 - x0) * 0.85, y, z), r + 0.01, band, 0.22, normal=(1, 0, 0))
    for x in posts:
        sp.line((x, y + 0.7, 0.2), (x, y + 0.7, 2.95), 0.1, "#7d848d")
    sp.line((posts[0], y + 0.7, 2.95), (posts[1], y + 0.7, 2.95), 0.08, "#7d848d")
    if v == 1:
        sp.line((x1 - 0.3, y, 2.95), (x1 - 0.3, y, 3.2), 0.1, "#c9ccd1")
        sp.lamp((x1 - 0.3, y, 3.25), RED_LIGHT, 5)
    # 압축기·터빈 상자 (앞) + 나선 케이싱 (앞을 보는 짧은 원통) + 전동기
    if v == 3:
        bx0, vx = 0.2, -0.9
    else:
        bx0, vx = -2.6, 0.6
    sp.box(bx0, 0.5, 0.2, 2.4, 1.3, 1.5, WHITE, top=SILVER)
    f = Sprite.box_faces(bx0, 0.5, 0.2, 2.4, 1.3, 1.5)
    _louvers(sp, f["left"], 0.08, 0.5, 0.2, 0.8, 4, Mat("#7d848d"))
    band_on(sp, f["left"], 0.84, 0.92, ORANGE if v != 2 else BLUE)
    sp.window(sp.on_face(*f["left"], 0.62, 0.45, 0.88, 0.7), CYAN_LIGHT)
    if v == 4:
        _rad(sp, (bx0 + 0.3, 0.6, 1.7), (1.8, 0, 0), (0, 0, 1.1), 4, 1)
    sp.cyl((vx, 0.9, 0.95), (vx, 1.5, 0.95), 0.72, SILVER, cap_mat=STEEL)
    sp.ring3((vx, 1.52, 0.95), 0.4, "#7d848d", 0.06, normal=(0, 1, 0), front_only=False)
    sp.disc((vx, 1.53, 0.95), (0, 1, 0), 0.18, CHAR, two_sided=False)
    sp.cyl((vx, 0.3, 0.95), (vx, 0.9, 0.95), 0.4, Mat("#3E6FB0", 0.25) if v != 2 else ORANGE)
    sp.polyline3([(vx + 0.55, 1.2, 1.4), (vx + 0.55, 1.2, 2.0), (vx + 0.55, y, 2.0)], "#5c626b", 0.22)
    sp.polyline3([(vx + 0.55, 1.2, 1.4), (vx + 0.55, 1.2, 2.0), (vx + 0.55, y, 2.0)], "#c9ccd1", 0.16)
    sp.lamp((2.8, 1.8, 0.9), AMBER, 6)


# ── 방열 계열 ───────────────────────────────────────────────────────────

@typed("heatpipe_radiator", 8, 3, 7.0, "히트파이프 방열판", heights=[7.0, 7.0, 7.0, 7.4, 6.6])
def heatpipe_radiator(sp: Sprite, v: int):
    """한 장의 세운 판에 가는 세로 열관(구리) 줄 + 위쪽의 굵은 머리관."""
    sp.contact_shadow(0, 0, 4.4, 1.8, 0.4)
    zt = (6.3, 6.3, 6.3, 6.7, 5.9)[v]
    zb = 0.7
    x0, x1 = -3.7, 3.7
    # 뒤쪽 버팀대
    for x in ((-3.2, 0.0, 3.2) if v != 1 else (-3.2, -0.1, 0.1, 3.2)):
        sp.line((x, -1.3, 0), (x, -0.08, zt * 0.72), 0.1, "#8a9099")
        sp.box(x - 0.15, -1.45, 0, 0.3, 0.3, 0.12, STEEL)
    sp.box(-3.9, -0.35, 0, 7.8, 0.7, 0.45, STEEL)
    if v == 3:
        sp.stripes((3.9, -0.35, 0.0), (0, 0.7, 0), (0, 0, 0.45), n=4, normal=(1, 0, 0))
        sp.stripes((3.9, 0.35, 0.0), (-7.8, 0, 0), (0, 0, 0.45), n=24, normal=(0, 1, 0))
    panels = [(x0, x1)] if v != 1 else [(x0, -0.1), (0.1, x1)]
    n = 26 if v != 4 else 34
    for a, b in panels:
        sp.quad((a, 0.0, zb), (b - a, 0, 0), (0, 0, zt - zb), RADIATOR, back=RADIATOR)
        sp.polyline3([(a, 0.02, zb), (b, 0.02, zb), (b, 0.02, zt), (a, 0.02, zt), (a, 0.02, zb)], "#b9bec4", 0.06)
        k = max(2, int(round(n * (b - a) / (x1 - x0))))
        for i in range(k):
            x = a + (i + 0.5) * (b - a) / k
            sp.line((x, 0.05, zb + 0.08), (x, 0.05, zt + 0.1), 0.045, "#B8733F")
    if v == 1:
        sp.line((0.0, 0.0, 0.45), (0.0, 0.0, zt + 0.4), 0.16, "#8a9099")
    # 머리관
    hm = COPPER if v != 2 else WHITE
    sp.cyl((x0 - 0.15, 0.0, zt + 0.3), (x1 + 0.15, 0.0, zt + 0.3), 0.26, hm, cap_mat=COPPER,
           bands=[0.1, 0.3, 0.5, 0.7, 0.9], band_color="#8a5a32" if v != 2 else "#bdb6a8")
    pipe(sp, [(x1 + 0.15, 0.0, zt + 0.3), (x1 + 0.3, 0.25, zt + 0.3), (x1 + 0.3, 0.25, 0.45)], 0.16, "#B8733F")
    if v in (0, 2, 4):
        pipe(sp, [(x0 - 0.15, 0.0, zt + 0.3), (x0 - 0.2, 0.3, zt + 0.3), (x0 - 0.2, 0.3, 0.45)], 0.16, "#B8733F")
    if v == 2:
        sp.box(2.7, 0.45, 0, 1.2, 0.9, 1.1, WHITE, top=SILVER)
        band_on(sp, Sprite.box_faces(2.7, 0.45, 0, 1.2, 0.9, 1.1)["left"], 0.75, 0.88, ORANGE)
        sp.lamp((3.95, 0.9, 1.2), AMBER, 7)
    if v == 4:
        sp.box(-3.9, 0.45, 0, 1.0, 0.8, 0.9, WHITE, top=SILVER)
        sp.disc((-3.4, 1.26, 0.55), (0, 1, 0), 0.22, Mat("#E6E2D8"), two_sided=False)
        sp.lamp((-2.85, 0.85, 1.0), AMBER, 6)
    sp.lamp((x1 + 0.3, 0.0, zt + 0.75), RED_LIGHT, 6)


@typed("tall_radiator", 6, 3, 12.0, "수직 방열탑", heights=[12.0, 12.0, 12.4, 11.6, 12.0])
def tall_radiator(sp: Sprite, v: int):
    """가운데 기둥에 양쪽으로 지느러미를 단 높고 좁은 방열탑 (앞뒤 양면이 다 방열면)."""
    sp.contact_shadow(0, 0, 3.0, 1.6, 0.45)
    H = (11.6, 11.6, 12.0, 11.2, 11.6)[v]
    zb = 0.9
    wx = 2.45 if v != 3 else 2.1
    wy = 1.15
    sp.box(-1.0, -0.8, 0, 2.0, 1.6, 0.6, CONCRETE)
    fins = [((-1, 0), wx), ((1, 0), wx), ((0, -1), wy), ((0, 1), wy)]
    if v == 4:
        fins = [((-1, 0), wx), ((1, 0), wx)]
    fins.sort(key=lambda f: f[0][0] + f[0][1])
    grid = 4 if v != 1 else 2

    def fin(d, w):
        o = (d[0] * 0.3, d[1] * 0.3, zb)
        e1 = (d[0] * w, d[1] * w, 0.0)
        _rad(sp, o, e1, (0, 0, H - zb), grid, 1 if v != 2 else 5)
        for k in (0.25, 0.5, 0.75):
            z = zb + (H - zb) * k
            sp.line(add(o, (0, 0, z - zb)), add(add(o, e1), (0, 0, z - zb)), 0.06, "#9aa1aa")
        sp.line(add(o, (0, 0, H - zb)), add(add(o, e1), (0, 0, H - zb)), 0.14, "#B8733F")

    for d, w in fins:
        if d[0] + d[1] < 0:
            fin(d, w)
    sp.box(-0.3, -0.3, 0.6, 0.6, 0.6, H - 0.2, STEEL, top=SILVER)
    if v == 1:
        zp = H * 0.55
        sp.box(-0.9, -0.9, zp, 1.8, 1.8, 0.12, STEEL, top=Mat("#9aa0a8", 0.3))
        sp.polyline3([(-0.9, 0.9, zp + 0.9), (0.9, 0.9, zp + 0.9), (0.9, -0.9, zp + 0.9)], "#E9C24A", 0.06)
        sp.lamp((0.95, 0.95, zp + 1.0), AMBER, 7)
    for d, w in fins:
        if d[0] + d[1] > 0:
            fin(d, w)
    if v == 4:
        for y in (-1.3, 1.3):
            sp.line((0.0, y, 0.0), (0.0, 0.3 * (1 if y > 0 else -1), H * 0.6), 0.08, "#8a9099")
        sp.box(-0.15, -1.45, 0, 0.3, 0.3, 0.15, STEEL)
        sp.box(-0.15, 1.15, 0, 0.3, 0.3, 0.15, STEEL)
    if v == 3:
        sp.box(1.4, 0.6, 0, 1.2, 0.8, 1.0, WHITE, top=SILVER)
        sp.lamp((2.65, 1.0, 1.1), AMBER, 7)
    pipe(sp, [(0.35, 0.35, 0.6), (0.35, 0.35, H - 0.4)], 0.12, "#B8733F")
    sp.line((0, 0, H + 0.4), (0, 0, H + 0.9), 0.06, "#9aa1aa")
    sp.lamp((0, 0, H + 1.0), RED_LIGHT, 7)


DROP = "#ff9a4a"


@typed("droplet_radiator", 10, 6, 5.0, "액적 방열기", heights=[5.0, 5.0, 5.0, 5.4, 4.6])
def droplet_radiator(sp: Sprite, v: int):
    """높은 노즐 막대에서 빛나는 주황 물방울 막을 뿌려 앞쪽 받이 홈통으로 떨군다."""
    sp.contact_shadow(0, 0, 5.4, 3.2, 0.45)
    zb = (4.6, 4.6, 4.6, 5.0, 4.2)[v]
    yb, yt = -2.0, 1.55
    x0, x1 = -4.3, 4.3
    # 끝 기둥 (뒤 다리)
    for x in (-4.75, 4.75):
        sp.line((x, -2.7, 0), (x, yb, zb * 0.62), 0.12, "#8a9099")
        sp.line((x, yb, 0), (x, yb, zb + 0.3), 0.18, "#8a9099")
        sp.box(x - 0.2, -2.9, 0, 0.4, 0.4, 0.15, STEEL)
    # 노즐 막대
    sp.cyl((-4.75, yb, zb), (4.75, yb, zb), 0.3, SILVER, bands=[0.1, 0.3, 0.5, 0.7, 0.9], cap_mat=STEEL)
    sp.box(x0, yb - 0.08, zb - 0.45, x1 - x0, 0.16, 0.18, DARK)
    # 물방울 막 (포물선): y = yb + (yt - yb) s, z = zt0 - (zt0 - zr) s^2
    zt0, zr = zb - 0.45, 0.95
    steps = 8
    sv = [i / steps for i in range(steps + 1)]

    def at(x, s):
        return (x, yb + (yt - yb) * s, zt0 - (zt0 - zr) * s * s)

    spans = [(x0, x1)] if v != 1 else [(x0, -0.35), (0.35, x1)]
    if v == 1:
        sp.line((0.0, yb, 0.0), (0.0, yb, zb), 0.16, "#8a9099")
    g0, g1 = PV(at(0, 0)), PV(at(0, 1))
    for a, b in spans:
        outline = [PV(at(a, s)) for s in sv] + [PV(at(b, s)) for s in reversed(sv)]
        fill = sp.gradient([(0, "#ffd29a", 0.5), (1, "#ff8a3a", 0.25)], g0[0], g0[1], g1[0], g1[1])
        sp.poly2(outline, fill, None, 0)
        for i in range(steps):
            sp.light_poly([at(a, sv[i]), at(b, sv[i]), at(b, sv[i + 1]), at(a, sv[i + 1])], SALT, 0.45)
    ns = 22 if v != 2 else 16
    for k in range(ns):
        x = x0 + 0.15 + k * (x1 - x0 - 0.3) / (ns - 1)
        if v == 1 and abs(x) < 0.4:
            continue
        ph = (k * 0.37) % 1.0
        for j in range(5):
            s0 = min(1.0, (j + ph) / 5.0)
            s1 = min(1.0, s0 + 0.09)
            sp.line(at(x, s0), at(x, s1), 0.06, "#ffb070" if j < 2 else DROP)
    # 받이 홈통 (앞)
    sp.box(-4.6, yt - 0.35, 0, 9.2, 1.3, 0.85, STEEL, top=Mat("#4a2c1c", 0.6))
    ft = Sprite.box_faces(-4.6, yt - 0.35, 0, 9.2, 1.3, 0.85)
    sp.light_poly([(-4.5, yt - 0.25, 0.86), (4.5, yt - 0.25, 0.86), (4.5, yt + 0.85, 0.86), (-4.5, yt + 0.85, 0.86)],
                  SALT, 0.5)
    band_on(sp, ft["left"], 0.7, 0.85, ORANGE if v != 1 else YELLOW)
    # 되돌림 관과 펌프 (오른쪽 끝)
    sp.box(3.9, -1.3, 0, 1.0, 1.4, 1.1, WHITE, top=SILVER)
    sp.lamp((4.95, -0.6, 1.0), AMBER, 7)
    pipe(sp, [(4.4, yt - 0.35, 0.5), (4.4, -0.1, 0.5)], 0.2, "#B8733F")
    pipe(sp, [(4.4, -1.3, 0.9), (4.6, yb + 0.35, 0.9), (4.6, yb + 0.35, zb)], 0.2, "#B8733F")
    for x in (-4.75, 4.75):
        sp.line((x, yb, zb + 0.3), (x, yb, zb + 0.6), 0.06, "#9aa1aa")
    if v == 3:
        sp.lamp((-4.75, yb, zb + 0.7), RED_LIGHT, 6)
    sp.glow((0, 0, 2.6), 46, SALT, 0.35)


def _ridge(sp: Sprite, p0, p1, w, h, mat: Mat):
    """두 바닥 점 사이의 낮은 사다리꼴 두둑 (묻은 관 위로 솟은 흙)."""
    d = norm(sub(p1, p0))
    sd = (-d[1] * w / 2, d[0] * w / 2, 0.0)
    st = mul(sd, 0.35)
    up = (0.0, 0.0, h)
    a0, a1, b0, b1 = sub(p0, sd), sub(p1, sd), add(p0, sd), add(p1, sd)
    t0, t1, u0, u1 = add(sub(p0, st), up), add(sub(p1, st), up), add(add(p0, st), up), add(add(p1, st), up)
    for q in ([a0, a1, t1, t0], [b1, b0, u0, u1], [t0, t1, u1, u0], [a1, b1, u1, t1], [b0, a0, t0, u0]):
        sp.face(q, mat, edge=False, ao=0)


@typed("regolith_sink", 8, 6, 1.2, "레골리스 열 저장소", heights=[1.2, 1.2, 1.2, 1.4, 1.2])
def regolith_sink(sp: Sprite, v: int):
    """묻은 관 고리가 두둑으로 드러난 평평한 밭 + 분배 상자."""
    sp.contact_shadow(0, 0, 4.4, 3.4, 0.35)
    z = 0.22
    sp.tbox(-3.9, -2.9, 3.9, 2.9, 0.35, z, REGOLITH, top=Mat("#958D81"))
    ridge = Mat("#A19885")
    xa, xb = -3.2, 2.1 if v != 4 else 2.4
    loops = [(-2.3, -0.2), (0.35, 2.45)] if v != 2 else [(-2.3, 2.45)]
    runs = 4 if v != 2 else 8          # 짝수 줄이라야 두 끝이 모두 분배 상자 쪽에 온다
    segs = []
    for ya, yb in loops:
        ys = [ya + i * (yb - ya) / (runs - 1) for i in range(runs)]
        for i, y in enumerate(ys):
            segs.append(((xa, y, z), (xb + (0.55 if i in (0, runs - 1) else 0.0), y, z)))
            if i < runs - 1:
                x = xa if i % 2 == 0 else xb      # 짝수 줄은 왼쪽 끝, 홀수 줄은 오른쪽 끝에서 굽는다
                segs.append(((x, y - 0.12, z), (x, ys[i + 1] + 0.12, z)))
    segs.sort(key=lambda s_: _depth(mul(add(s_[0], s_[1]), 0.5)))
    for a, b in segs:
        _ridge(sp, a, b, 0.5, 0.2 if v != 1 else 0.26, ridge)
    # 분배 상자 + 관 머리
    mx0 = 2.75 if v != 4 else 3.0
    hb = 1.2 if v != 3 else 1.4
    sp.box(mx0, -1.5, z, 0.95, 3.0, hb - z, WHITE, top=SILVER)
    f = Sprite.box_faces(mx0, -1.5, z, 0.95, 3.0, hb - z)
    band_on(sp, f["right"], 0.78, 0.9, ORANGE if v != 1 else TEAL)
    for u in (0.2, 0.4, 0.6, 0.8):
        c = add(add(f["right"][0], mul(f["right"][1], u)), mul(f["right"][2], 0.4))
        sp.disc(add(c, (0.01, 0, 0)), (1, 0, 0), 0.12, Mat("#E6E2D8"), two_sided=False)
    for ya, yb in loops:
        for y in (ya, yb):
            pipe(sp, [(xb + 0.55, y, 0.32), (mx0 - 0.05, y if abs(y) < 1.4 else math.copysign(1.3, y), 0.6)], 0.12,
                 "#B8733F")
    sp.lamp((mx0 + 1.0, 1.6, hb - 0.1), AMBER, 7)
    if v != 2:
        for x, y in ((-3.6, -2.6), (-3.6, 2.6)):
            sp.line((x, y, 0.2), (x, y, 1.0), 0.05, "#E9C24A")
            sp.lamp((x, y, 1.05), AMBER, 5)
    sp.glow((-0.6, 0.0, 0.3), 36, "#ff7a3a", 0.15)
