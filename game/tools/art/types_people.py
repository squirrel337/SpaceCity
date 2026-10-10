"""사람이 사는·쓰는 건물 종류 28종 — 거주, 돔, 대피소, 의료, 연구, 공원·여가, 교신 계열.

종류마다 함수 하나 fn(sp, v)가 같은 기능의 다섯 모양(v = 0~4)을 그린다. v0이 대표 모양이다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다. 뒤(x+y가 작은 쪽)에서 앞 순서로 그린다.
"""
from __future__ import annotations

import math

from types_common import *  # noqa: F401,F403

# ── 재질 ──────────────────────────────────────────────────────────────
TAN = Mat("#A8926F")                 # 인쇄한 레골리스 (밝은 황갈색)
TAN_TOP = Mat("#B49E7C")
HEAT = Mat("#4A3B31", 0.15)          # 캡슐 열차폐 (그을린 갈색)
CREW_WHITE = Mat("#E9E6DF", 0.12)
POLY = Mat("#EEF0EA", 0.06)          # 폴리에틸렌 패널
POLY_SEAM = "#b9bcb4"
MAROON = Mat("#8E3B3B", 0.1)
CRYO = Mat("#C9D9E6", 0.35)          # 초전도 코일 덮개
SCREEN = Mat("#16304a", 0.6)
VIOLET = Mat("#9B7AD6")              # 연구 계열 띠
BIO_YELLOW = Mat("#E9C24A", 0.1)
TRACK = Mat("#C8553D", 0.1)          # 육상 트랙
TURF = Mat("#5E9E4E")
MONO = Mat("#2E3238", 0.25)          # 기록 보관소의 검은 덩어리
MIRROR = Mat("#DCE6EE", 0.95)

COOL_WINDOW = "#E8F6FF"              # 수술실 불빛
SCREEN_GLOW = "#7FC8FF"
RED_LIGHT = "#FF4A3A"


# ── 공용 도우미 ───────────────────────────────────────────────────────

def _orient(pts, outward):
    """다각형 꼭짓점이 outward 쪽에서 반시계가 되게 한다 (창·표시가 앞면으로 그려지도록)."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return pts if dot(n, outward) >= 0 else list(reversed(pts))


def _circle(c, n, r, k=14):
    """중심 c, 법선 n인 평면 위의 원 (반시계)."""
    u, w = basis(n)
    pts = [add(c, add(mul(u, r * math.cos(2 * math.pi * i / k)), mul(w, r * math.sin(2 * math.pi * i / k))))
           for i in range(k)]
    return _orient(pts, n)


def _cyl_round(p0, p1, r, s, ang, rad, k=12, lift=0.03):
    """원기둥 겉면의 둥근 창 (축 위치 s, 각도 ang[도], 반지름 rad m)."""
    axis = sub(p1, p0)
    L = length(axis)
    u, w = basis(axis)
    pts = []
    for i in range(k):
        t = 2 * math.pi * i / k
        aa = math.radians(ang) + rad * math.sin(t) / r
        radial = add(mul(u, math.cos(aa)), mul(w, math.sin(aa)))
        pts.append(add(add(p0, mul(axis, s + rad * math.cos(t) / L)), mul(radial, r + lift)))
    a0 = math.radians(ang)
    return _orient(pts, add(mul(u, math.cos(a0)), mul(w, math.sin(a0))))


def _cone_patch(c0, c1, r0, r1, s0, s1, a0, a1, lift=0.03):
    """원뿔대 겉면의 사각형 (축 위치 s, 각도 a[도])."""
    axis = sub(c1, c0)
    u, w = basis(axis)

    def at(s, ang):
        t = math.radians(ang)
        radial = add(mul(u, math.cos(t)), mul(w, math.sin(t)))
        return add(add(c0, mul(axis, s)), mul(radial, r0 + (r1 - r0) * s + lift))
    pts = [at(s0, a0), at(s0, a1), at(s1, a1), at(s1, a0)]
    am = math.radians((a0 + a1) / 2)
    return _orient(pts, add(mul(u, math.cos(am)), mul(w, math.sin(am))))


def _face_pt(frame, u, v):
    o, e1, e2 = frame
    return add(add(o, mul(e1, u)), mul(e2, v))


def _decal(sp, frame, u0, v0, u1, v1, mat, lift=0.0):
    """상자 면 위의 색 판 (표시·패널)."""
    o, e1, e2 = frame
    n = norm(cross(e1, e2))
    pts = [add(p, mul(n, lift)) for p in sp.on_face(o, e1, e2, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    return pts


def _cross_sign(sp, frame, cu, cv, size, mat=RED, glow=None):
    """면 위의 십자 (의료). size는 면 높이 비율."""
    o, e1, e2 = frame
    k = length(e2) / max(1e-6, length(e1))          # 가로 비율 보정 → 정사각 십자
    a, b = size * 0.32, size
    for (du, dv) in ((a * k, b), (b * k, a)):
        pts = _decal(sp, frame, cu - du / 2, cv - dv / 2, cu + du / 2, cv + dv / 2, mat, 0.01)
        if glow:
            sp.light_poly(pts, glow, 0.8)


def _trefoil(sp, c, n, r, bg=YELLOW, fg=CHAR):
    """방사선 표지 (노란 원판 + 검은 세 날개)."""
    u, w = basis(n)
    cn = add(c, mul(n, 0.01))
    sp.face(_circle(cn, n, r, 16), bg, normal=n, edge=False, ao=0)
    c2 = add(c, mul(n, 0.02))
    for k in range(3):
        a0 = math.radians(90 + k * 120 - 30)
        a1 = math.radians(90 + k * 120 + 30)
        pts = []
        for j in range(5):
            t = a0 + (a1 - a0) * j / 4
            pts.append(add(c2, add(mul(u, r * 0.82 * math.cos(t)), mul(w, r * 0.82 * math.sin(t)))))
        for j in range(5):
            t = a1 - (a1 - a0) * j / 4
            pts.append(add(c2, add(mul(u, r * 0.3 * math.cos(t)), mul(w, r * 0.3 * math.sin(t)))))
        sp.face(_orient(pts, n), fg, normal=n, edge=False, ao=0)
    sp.face(_circle(c2, n, r * 0.17, 10), fg, normal=n, edge=False, ao=0)


def _dish(sp, c, n, r, mat=WHITE):
    sp.disc(c, n, r, mat, back=STEEL, seg=40)
    sp.ring3(c, r, "#b9b2a5", 0.07, normal=n, front_only=False)
    feed = add(c, mul(n, r * 0.62))
    u, w = basis(n)
    for a in (0, 120, 240):
        rim = add(c, add(mul(u, r * 0.85 * math.cos(math.radians(a))), mul(w, r * 0.85 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.045, "#8a9099")
    sp.sphere(feed, max(0.1, r * 0.08), GOLD)


def _rail(sp, pts, h=0.9, color="#c9ccd1", posts=True, closed=False):
    """난간: 위 막대와 기둥."""
    top = [(p[0], p[1], p[2] + h) for p in pts]
    if posts:
        for p, t in zip(pts, top):
            sp.line(p, t, 0.05, color)
    sp.polyline3(top, color, 0.06, closed=closed)


def _ring_pts(c, r, a0, a1, k=24, z=None):
    """수평 원호의 점들 (도)."""
    zz = c[2] if z is None else z
    return [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * i / k)),
             c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * i / k)), zz) for i in range(k + 1)]


def _front_arc(c, r, z, k=36, front=True, margin=0.0):
    """수평 원의 앞(카메라 쪽) 또는 뒤 반쪽."""
    pts = []
    out = []
    for i in range(k + 1):
        t = 2 * math.pi * i / k
        d = (math.cos(t), math.sin(t), 0.0)
        vis = dot(d, VIEW) > margin
        if vis == front:
            pts.append((c[0] + r * d[0], c[1] + r * d[1], z))
        elif pts:
            out.append(pts)
            pts = []
    if pts:
        out.append(pts)
    # 원의 시작점에서 끊긴 두 조각을 잇는다
    if len(out) > 1 and out[0][0] == (c[0] + r, c[1], z) and out[-1][-1] == (c[0] + r, c[1], z):
        out = [out[-1] + out[0][1:]] + out[1:-1]
    return out


def _glass_cap(sp, c, rx, ry, h, z0, rings=(0.3, 0.58, 0.82), ribs=12, rib_col="#dfe9f2", alpha=0.3):
    """유리 돔 (타원 바닥 rx × ry, 높이 h): 2D는 반투명 채움과 갈비, 3D는 유리 껍질."""
    pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            pts.append(P(c[0] + rx * math.cos(ph) * math.cos(th), c[1] + ry * math.cos(ph) * math.sin(th),
                         z0 + h * math.sin(ph)))
    sil = hull(pts)
    hl = PV((c[0] - rx * 0.28, c[1] + ry * 0.5, z0 + h * 0.8))
    fill = sp.radial([(0, "#ffffff", alpha), (0.4, "#cfe6ff", alpha * 0.4), (1, "#9fc0e0", alpha * 0.16)],
                     hl[0], hl[1], max(rx, ry) * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_shell((c[0], c[1], z0), rx, ry, h, z0)
    for zz in rings:
        k = math.sqrt(max(0.0, 1 - zz ** 2))
        for seg in _front_arc((c[0], c[1], 0), 1.0, z0 + h * zz, 48, True, -0.05):
            sp.polyline3([(c[0] + (p[0] - c[0]) * rx * k, c[1] + (p[1] - c[1]) * ry * k, p[2]) for p in seg],
                         rib_col, 0.05, 0.55)
    for i in range(ribs):
        th = 2 * math.pi * i / ribs
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.2:
            continue
        sp.polyline3([(c[0] + rx * math.cos(ph) * math.cos(th), c[1] + ry * math.cos(ph) * math.sin(th),
                       z0 + h * math.sin(ph)) for ph in [k * math.pi / 2 / 12 for k in range(13)]], rib_col, 0.05, 0.5)
    return sil


def _ladder(sp, p_top, p_bot, side, w=0.45, rungs=5, color="#9aa1aa"):
    s = mul(norm(side), w / 2)
    sp.line(sub(p_top, s), sub(p_bot, s), 0.05, color)
    sp.line(add(p_top, s), add(p_bot, s), 0.05, color)
    for i in range(1, rungs + 1):
        q = add(p_bot, mul(sub(p_top, p_bot), i / (rungs + 1)))
        sp.line(sub(q, s), add(q, s), 0.04, color)


# ═════════════════════════════════════════════════════════════════════
# 거주 (hab_module 계열)
# ═════════════════════════════════════════════════════════════════════

def _pillow_tube(sp, x0, x1, zc, r, n, mat=FABRIC, strap="#a99c84", bulge=0.16, cap=0.58):
    """둥근 끝을 가진 부푼 천 원통: 띠(스트랩) 사이가 베개처럼 부풀었다."""
    sp.ellipsoid((x0, 0, zc), r * cap, r, r, mat)
    L = (x1 - x0) / n
    for i in range(n):
        a = x0 + i * L
        sp.frustum((a, 0, zc), (a + L / 2, 0, zc), r, r + bulge, mat, caps=False)
        sp.frustum((a + L / 2, 0, zc), (a + L, 0, zc), r + bulge, r, mat, caps=False)
    sp.ellipsoid((x1, 0, zc), r * cap, r, r, mat)
    for i in range(n + 1):
        sp.ring3((x0 + i * L, 0, zc), r + 0.03, strap, 0.16, normal=(1, 0, 0))
    # 세로 띠 (구속층)
    for ang in (35.0, 75.0):
        t = math.radians(ang)
        pts = []
        for i in range(n * 6 + 1):
            x = x0 + (x1 - x0) * i / (n * 6)
            ph = ((x - x0) / L) % 1.0
            rr = r + 0.02 + bulge * (1 - abs(2 * ph - 1))
            pts.append((x, rr * math.cos(t), zc + rr * math.sin(t)))
        sp.polyline3(pts, strap, 0.07, 0.75)


@typed("transhab", 12, 7, 6.0, "대형 팽창 거주동", heights=[6.0, 6.2, 6.0, 5.6, 6.1])
def transhab(sp: Sprite, v: int):
    r = (2.7, 2.85, 2.7, 2.5, 2.75)[v]
    n = (4, 3, 4, 5, 4)[v]
    zc = r + 0.6
    x0, x1 = (-3.9, -3.6, -3.9, -4.3, -3.9)[v], (3.0, 2.8, 3.0, 3.3, 3.0)[v]
    sp.contact_shadow(-0.3, 0, 6.2, 3.4, 0.5)
    # 낮은 강철 받침 (안장 넷 + 긴 보)
    sp.box(-4.6, -2.0, 0, 8.4, 0.3, 0.35, STEEL)
    for x in (-3.4, -1.1, 1.2, 3.1)[: 4 if v != 1 else 3]:
        sp.box(x - 0.35, -2.1, 0, 0.7, 4.2, 0.95, STEEL, top=DARK)
    mat = FABRIC if v != 4 else Mat("#E8E1D0")
    _pillow_tube(sp, x0, x1, zc, r, n, mat, strap=("#a99c84", "#9c8f77", "#a99c84", "#b07a4a", "#8f8a80")[v])
    sp.box(-4.6, 1.7, 0, 8.4, 0.3, 0.35, STEEL)
    # 단단한 금속 에어록 고리와 해치 (+x 끝)
    xe = x1 + r * 0.58 - 0.35
    sp.cyl((xe, 0, zc), (xe + 0.9, 0, zc), 1.35, SILVER, cap_mat=STEEL, bands=[0.5])
    sp.disc((xe + 0.92, 0, zc), (1, 0, 0), 0.95, DARK)
    sp.disc((xe + 0.95, 0, zc), (1, 0, 0), 0.7, STEEL)
    sp.window(_circle((xe + 0.97, 0, zc + 0.25), (1, 0, 0), 0.2, 10))
    sp.lamp((xe + 0.95, 0, zc + 1.6), AMBER, 10)
    # 작은 둥근 창 (보이는 옆)
    p0, p1 = (x0, 0, zc), (x1, 0, zc)
    ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.45)))
    spots = {0: (0.2, 0.45, 0.7), 1: (0.3, 0.68), 2: (0.15, 0.4, 0.62, 0.86), 3: (0.25, 0.5, 0.75), 4: (0.33, 0.6)}[v]
    for s in spots:
        sp.window(_cyl_round(p0, p1, r + 0.14, s, ang, 0.36), frame="#6f675a")
    if v == 4:
        for s in spots:
            sp.window(_cyl_round(p0, p1, r + 0.14, s, ang - 26, 0.3), frame="#6f675a")
    # 모양마다 덧붙이는 것
    if v == 1:
        sp.quad((-2.4, -1.1, zc + r + 0.25), (3.6, 0, 0), (0, 2.2, 0.0), RADIATOR, back=RADIATOR)
        sp.panel_grid((-2.4, -1.1, zc + r + 0.25), (3.6, 0, 0), (0, 2.2, 0.0), 6, 1, "#b9bec4", 0.5, 0.7)
        legs(sp, [(-2.0, 0.0, zc + r + 0.25), (0.8, 0.0, zc + r + 0.25)], zc + r - 0.05)
    elif v == 2:
        sp.cyl((-5.2, 2.3, 0), (-5.2, 2.3, 1.8), 0.55, WHITE, bands=[0.5], band_color="#3FB8AF")
        crate(sp, 4.4, 1.7, 1.1)
        crate(sp, 4.4, -2.9, 1.0, Mat("#C9A23A"))
    elif v == 3:
        antenna(sp, (-0.5, 0, zc + r + 0.1), 1.6)
        crate(sp, 4.6, 1.9, 1.0)
    elif v == 4:
        sp.cyl((-1.5, 0, zc + r + 0.05), (-1.5, 0, zc + r + 0.35), 0.5, STEEL)
        sp.lamp((-1.5, 0, zc + r + 0.5), "#ff5a3c", 6)
    else:
        crate(sp, 4.3, 1.8, 1.0)
        sp.window(Sprite.cyl_patch(p0, p1, r + 0.02, 0.93, 0.97, ang - 40, ang + 40), CYAN_LIGHT, frame=None,
                  glass=TEAL, light_alpha=0.6)


@typed("crew_capsule", 5, 5, 4.2, "승무원 캡슐", heights=[4.2, 4.2, 4.6, 4.0, 4.2])
def crew_capsule(sp: Sprite, v: int):
    body = (CREW_WHITE, SILVER, CREW_WHITE, Mat("#DAD4C6", 0.1), CREW_WHITE)[v]
    accent = (RED, ORANGE, BLUE, RED, TEAL)[v]
    sp.contact_shadow(0, 0, 2.5, 2.5, 0.5)
    if v == 3:          # 그을린 착륙 패드
        sp.disc((0, 0, 0.02), (0, 0, 1), 2.4, Mat("#4b4740"), edge=False)
        sp.ring3((0, 0, 0.03), 2.1, "#E9C24A", 0.12, front_only=False)
    zb, zt, rb, rt = 1.05, 3.35, 1.95, 0.78
    feet = [(2.2 * math.cos(math.radians(a)), 2.2 * math.sin(math.radians(a))) for a in (45, 135, 225, 315)]
    feet.sort(key=lambda f: f[0] + f[1])

    def leg(f):
        d = norm((f[0], f[1], 0))
        sp.line((d[0] * 1.55, d[1] * 1.55, zb + 0.1), (f[0], f[1], 0.14), 0.14, "#8a9099")
        sp.line((d[0] * 1.25, d[1] * 1.25, zb - 0.25), (f[0] * 0.9, f[1] * 0.9, 0.3), 0.08, "#6f767f")
        sp.cyl((f[0], f[1], 0), (f[0], f[1], 0.12), 0.3, STEEL)
    for f in feet[:2]:
        leg(f)
    # 열차폐 (어두운 밑판)와 원뿔 몸체
    sp.frustum((0, 0, zb - 0.32), (0, 0, zb), rb - 0.35, rb + 0.05, HEAT, cap_mat=HEAT)
    c0, c1 = (0, 0, zb), (0, 0, zt)
    sp.frustum(c0, c1, rb, rt, body, bands=[0.33, 0.66], band_color="#b5b0a6")
    sp.frustum((0, 0, zb + 0.02), (0, 0, zb + 0.3), rb + 0.02, rb - 0.13, accent, caps=False, edge=False)
    sp.cyl((0, 0, zt), (0, 0, zt + 0.45), 0.6, STEEL, cap_mat=DARK)
    sp.ring3((0, 0, zt + 0.46), 0.42, "#c9ccd1", 0.06)
    # 반동 추진기 (RCS) 네 묶음
    for a in (0, 90, 180, 270):
        d = (math.cos(math.radians(a + 45)), math.sin(math.radians(a + 45)), 0.0)
        if dot(d, VIEW) < -0.1:
            continue
        s = 0.78
        rr = rb + (rt - rb) * s
        p = (d[0] * rr, d[1] * rr, zb + (zt - zb) * s)
        sp.box(p[0] - 0.11, p[1] - 0.11, p[2] - 0.1, 0.22, 0.22, 0.2, Mat("#5b616b", 0.2))
    for f in feet[2:]:
        leg(f)
    # 옆 해치 (불 켜진 창)와 짧은 사다리
    face_dir = ((0.25, 1.0, 0), (1.0, 0.3, 0), (0.6, 1.0, 0), (0.25, 1.0, 0), (1.0, 0.55, 0))[v]
    ha = math.degrees(math.atan2(face_dir[1], face_dir[0]))
    ang = Sprite.facing_angle(c0, c1, norm(face_dir))
    sp.face(_cone_patch(c0, c1, rb, rt, 0.12, 0.62, ang - 17, ang + 17, 0.03), Mat("#C9CCD1", 0.3), ao=0)
    sp.window(_cone_patch(c0, c1, rb, rt, 0.4, 0.56, ang - 8, ang + 8, 0.05))
    sp.window(_cone_patch(c0, c1, rb, rt, 0.55, 0.68, ang + 30, ang + 44, 0.03))
    sp.window(_cone_patch(c0, c1, rb, rt, 0.55, 0.68, ang - 44, ang - 30, 0.03))
    d = (math.cos(math.radians(ha)), math.sin(math.radians(ha)), 0.0)
    side = (-d[1], d[0], 0.0)
    top = (d[0] * (rb - 0.12), d[1] * (rb - 0.12), zb + 0.3)
    _ladder(sp, top, (d[0] * 2.25, d[1] * 2.25, 0.0), side, 0.5, 4)
    sp.lamp((0, 0, zt + 0.75), "#ff5a3c", 6)
    if v == 2:          # 지상 지원 탑과 탯줄
        sp.truss((-2.0, -2.0, 0), (-2.0, -2.0, 4.2), 0.6, "#C9A23A", 0.07, 8, side=(1, -1, 0))
        sp.polyline3([(-2.0, -2.0, 3.6), (-1.2, -1.2, 3.5), (-0.62, -0.62, 3.0)], "#3a3f47", 0.12)
        sp.lamp((-2.0, -2.0, 4.35), AMBER, 8)
    elif v == 4:
        sp.box(1.2, -2.3, 0, 1.0, 0.9, 0.8, ORANGE)
        sp.lamp((1.7, -1.85, 0.95), AMBER, 7)
    elif v == 1:
        sp.lamp((d[0] * 2.3 + side[0] * 0.5, d[1] * 2.3 + side[1] * 0.5, 0.9), AMBER, 8)


def _beehive(sp, cx, cy, R, H, mat=TAN, n=9, top=None):
    """현수선 모양으로 찍은 벌집형 껍질 — 인쇄 층마다 선이 보인다."""
    def rad(t):
        return R * max(0.0, 1 - t ** 1.7) ** 0.62
    zs = [H * i / n for i in range(n + 1)]
    for i in range(n - 1):
        sp.frustum((cx, cy, zs[i]), (cx, cy, zs[i + 1]), rad(i / n), rad((i + 1) / n), mat)
    zt = zs[n - 1]
    sp.ellipsoid((cx, cy, zt), rad((n - 1) / n), rad((n - 1) / n), H - zt, top or mat, clip_z=zt)
    return rad


def _deep_window(sp, c, R, H, rad, z0, z1, ang, half):
    """껍질 깊숙이 들어간 작은 창."""
    t0, t1 = z0 / H, z1 / H
    c0, c1 = (c[0], c[1], z0), (c[0], c[1], z1)
    r0, r1 = rad(t0), rad(t1)
    sp.face(_cone_patch(c0, c1, r0, r1, -0.12, 1.12, ang - half - 4, ang + half + 4, 0.02), Mat("#6E604C"), ao=0,
            edge=False)
    sp.window(_cone_patch(c0, c1, r0, r1, 0.0, 1.0, ang - half, ang + half, 0.03), frame="#4d4437")


@typed("printed_hab", 14, 10, 5.0, "인쇄 거주동", heights=[5.0, 5.0, 5.4, 4.6, 5.0])
def printed_hab(sp: Sprite, v: int):
    sp.contact_shadow(0, 0, 7.0, 5.0, 0.5)
    mat = (TAN, TAN, Mat("#9E8E74"), TAN, Mat("#B39A76"))[v]
    big = ((-3.8, -1.3, 3.1, 5.0), (-3.8, -1.1, 3.1, 5.0), (-3.6, -1.5, 3.3, 5.4), (-3.7, -1.4, 3.0, 4.6),
           (-3.8, -1.3, 3.1, 5.0))[v]
    left = (-0.9, 2.4, 2.45, 3.9)
    right = (2.1, -1.3, 2.55, 4.1)
    if v == 3:
        left, right = (2.0, 2.2, 2.4, 3.8), (1.0, -2.6, 2.3, 3.6)
    shells = sorted([big, left, right], key=lambda s: s[0] + s[1])
    # 껍질 사이의 짧은 터널 (뒤쪽 먼저)
    def tunnel(a, b):
        d = norm((b[0] - a[0], b[1] - a[1], 0))
        p0 = (a[0] + d[0] * (a[2] - 0.6), a[1] + d[1] * (a[2] - 0.6), 0)
        p1 = (b[0] - d[0] * (b[2] - 0.6), b[1] - d[1] * (b[2] - 0.6), 0)
        sp.half_cyl(p0, p1, 1.15, mat, bands=[0.5], band_color="#7f7262")
    tunnel(big, right)
    tunnel(big, left)
    for (cx, cy, R, H) in shells:
        rad = _beehive(sp, cx, cy, R, H, mat)
        vis = math.degrees(math.atan2(0.85, 0.45 if cx < 0 else 0.25))
        for k, a in enumerate((-25, 22) if R > 2.8 else (0,)):
            ang = Sprite.facing_angle((cx, cy, 0), (cx, cy, 1), norm((math.cos(math.radians(vis + a)),
                                                                        math.sin(math.radians(vis + a)), 0)))
            _deep_window(sp, (cx, cy), R, H, rad, H * 0.32, H * 0.46, ang, 6)
        if R > 2.8 and v in (0, 2, 4):
            ang = Sprite.facing_angle((cx, cy, 0), (cx, cy, 1), norm((0.5, 1.0, 0)))
            _deep_window(sp, (cx, cy), R, H, rad, H * 0.58, H * 0.68, ang, 5)
    # 아치형 출입구와 에어록 상자 (+x 쪽)
    ex, ey = (right[0], right[1]) if v != 3 else (left[0], left[1])
    er = right[2] if v != 3 else left[2]
    sp.half_cyl((ex + er - 0.8, ey, 0), (ex + er + 0.7, ey, 0), 1.25, mat, bands=[0.4, 0.75], band_color="#7f7262")
    bx = ex + er + 0.5
    sp.box(bx, ey - 1.0, 0, 1.3, 2.0, 2.1, CONCRETE, top=Mat("#b3a48e"))
    f = Sprite.box_faces(bx, ey - 1.0, 0, 1.3, 2.0, 2.1)
    door(sp, f["right"], 0.25, 0.75, 0.78, Mat("#5c626b", 0.3))
    windows_row(sp, f["left"], 1, 0.5, 0.75, 0.32)
    if v == 1:
        sp.cyl((5.4, 2.6, 0), (5.4, 2.6, 1.9), 0.75, WHITE, bands=[0.5], band_color="#3FB8AF")
        sp.dome((5.4, 2.6, 1.9), 0.75, 0.35, WHITE)
        antenna(sp, (left[0], left[1], left[3] - 0.1), 1.3)
    elif v == 2:
        antenna(sp, (big[0], big[1], big[3] - 0.1), 1.6)
    elif v == 4:
        for x, y in ((-6.2, 3.6), (5.6, 3.6)):
            sp.line((x, y, 0), (x, y, 2.6), 0.07, "#8a9099")
            sp.lamp((x, y, 2.7), AMBER, 10)
    sp.lamp((bx + 1.35, ey + 0.8, 1.8), AMBER, 9)


@typed("hab_stack", 9, 9, 13.0, "수직 거주탑", heights=[13.0, 13.4, 12.6, 13.0, 13.2])
def hab_stack(sp: Sprite, v: int):
    floors = 4
    r = (2.85, 2.85, 2.6, 2.85, 2.75)[v]
    fh = 2.65
    z0 = 0.4
    top = z0 + floors * fh
    a = 3.55
    steel = "#7d848d"
    accents = ((TEAL, TEAL, TEAL, TEAL), (ORANGE, TEAL, ORANGE, TEAL), (BLUE,) * 4, (YELLOW,) * 4,
               (RED, ORANGE, YELLOW, TEAL))[v]
    sp.contact_shadow(0, 0, 4.4, 4.4, 0.5)
    sp.box(-4.2, -4.2, 0, 8.4, 8.4, 0.4, CONCRETE)
    # 뒤쪽 외골격 (두 면)
    def column(x, y):
        sp.box(x - 0.17, y - 0.17, 0.4, 0.34, 0.34, top - 0.4, STEEL)
    column(-a, -a)
    for k in range(floors + 1):
        z = z0 + k * fh
        sp.polyline3([(-a, a, z), (-a, -a, z), (a, -a, z)], steel, 0.12)
    for k in range(floors):
        zb, zt = z0 + k * fh, z0 + (k + 1) * fh
        sp.line((-a, -a, zb), (a, -a, zt), 0.08, steel)
        sp.line((-a, a, zb), (-a, -a, zt), 0.08, steel)
    column(-a, a)
    column(a, -a)
    # 모듈 넷
    for k in range(floors):
        zb = z0 + k * fh + 0.12
        zt = zb + fh - 0.24
        p0, p1 = (0, 0, zb), (0, 0, zt)
        sp.cyl(p0, p1, r, WHITE, cap_mat=SILVER, bands=[0.12, 0.88], band_color="#bdb6a8")
        cyl_ring(sp, p0, p1, r, 0.8, 0.86, accents[k], None)
        cyl_windows(sp, p0, p1, r, 0.34, 0.66, toward=(1.0, 1.0, 0), n=6 if v != 2 else 5, spread=21, width=12)
        if k < floors - 1:
            sp.cyl((0, 0, zt), (0, 0, zt + 0.26), r - 0.35, STEEL)
    # 꼭대기 전망대
    sp.cyl((0, 0, top), (0, 0, top + 0.3), r + 0.45, STEEL, cap_mat=Mat("#9aa1aa", 0.3))
    for seg in _front_arc((0, 0, 0), r + 0.3, top + 0.3, 40, False, 0.0):
        _rail(sp, seg[::4] + [seg[-1]], 0.85)
    if v == 2:
        sp.dome((0, 0, top + 0.3), 1.5, 1.2, Mat("#cfe6f5", 0.6))
        sp.glow((0, 0, top + 0.9), 14, WARM_WINDOW, 0.5)
    else:
        sp.cyl((0, 0, top + 0.3), (0, 0, top + 1.2), 1.0, WHITE, cap_mat=SILVER)
        cyl_windows(sp, (0, 0, top + 0.3), (0, 0, top + 1.2), 1.0, 0.3, 0.8, toward=(1, 1, 0), n=3, spread=40,
                    width=24)
    if v == 1:
        _dish(sp, (-0.4, -0.4, top + 2.0), norm((0.3, 1.0, 0.7)), 0.9)
        sp.line((-0.4, -0.4, top + 1.2), (-0.4, -0.4, top + 1.9), 0.08, "#9aa1aa")
    elif v == 3:
        for x, y in ((-2.2, 1.4), (1.4, -2.2)):
            sp.lamp((x, y, top + 1.3), AMBER, 9)
    antenna(sp, (0.5, -0.5, top + 1.2 if v != 2 else top + 0.3), 1.0 if v != 4 else 1.8)
    for seg in _front_arc((0, 0, 0), r + 0.3, top + 0.3, 40, True, 0.0):
        _rail(sp, seg[::4] + [seg[-1]], 0.85)
    # 앞쪽 외골격 (두 면)
    for k in range(floors + 1):
        z = z0 + k * fh
        sp.polyline3([(-a, a, z), (a, a, z), (a, -a, z)], steel, 0.12)
    for k in range(floors):
        zb, zt = z0 + k * fh, z0 + (k + 1) * fh
        if (k + v) % 2 == 0:
            sp.line((-a, a, zb), (a, a, zt), 0.07, steel)
        else:
            sp.line((a, a, zb), (a, -a, zt), 0.07, steel)
    column(a, a)
    # 바깥 승강기 통로 (+y 또는 +x 면)
    if v in (0, 2, 4):
        sx, sy, sw, sd = -0.75, a - 0.1, 1.5, 0.9
        face = "left"
    else:
        sx, sy, sw, sd = a - 0.1, -0.75, 0.9, 1.5
        face = "right"
    sp.box(sx, sy, 0.4, sw, sd, top - 0.4, Mat("#D9D4C8"), top=SILVER)
    f = Sprite.box_faces(sx, sy, 0.4, sw, sd, top - 0.4)
    o, e1, e2 = f[face]
    sp.window(sp.on_face(o, e1, e2, 0.28, 0.05, 0.72, 0.97), "#ffd99a")
    door(sp, f[face], 0.25, 0.75, 0.16, Mat("#5c626b", 0.3), light=False)
    sp.lamp(add(_face_pt(f[face], 0.5, 1.0), (0, 0, 0.25)), AMBER, 9)


# ═════════════════════════════════════════════════════════════════════
# 돔 (regolith_dome 계열)
# ═════════════════════════════════════════════════════════════════════

def _stack(sp, c, prof, z0, z1, n, mat, cap_mat=None, edge=None):
    """반지름 prof(z)를 따라 원뿔대를 쌓은 회전체 (맨 위는 cap_mat 뚜껑).
    edge=False면 층 사이 선 없이 바깥 윤곽만 긋는다."""
    zs = [z0 + (z1 - z0) * i / n for i in range(n + 1)]
    for i in range(n):
        sp.frustum((c[0], c[1], zs[i]), (c[0], c[1], zs[i + 1]), prof(zs[i]), prof(zs[i + 1]), mat,
                   cap_mat=(cap_mat or mat) if i == n - 1 else mat, edge=edge)
    if edge is False:
        rims = []
        for z in zs:
            r = prof(z)
            rims += [PV((c[0] + r * math.cos(2 * math.pi * k / 48), c[1] + r * math.sin(2 * math.pi * k / 48), z))
                     for k in range(48)]
        sil = hull(rims)
        col = hexc(scale(lit(mat.albedo, (0, 0, 1)), mat.edge * 0.8))
        sp.path2("M" + " L".join("%.2f,%.2f" % q for q in sil) + "Z", "none", col, 0.5)


def _ice_facets(R, H, z0, nlon, nlat):
    """측지선처럼 어긋난 삼각형 면들 (반시계, 바깥 법선)."""
    def vtx(k, i):
        ph = (math.pi / 2) * k / nlat
        th = 2 * math.pi * (i + 0.5 * k) / nlon
        return (R * math.cos(ph) * math.cos(th), R * math.cos(ph) * math.sin(th), z0 + H * math.sin(ph))
    tris = []
    for k in range(nlat):
        for i in range(nlon):
            if k == nlat - 1:
                tris.append([vtx(k, i), vtx(k, i + 1), (0.0, 0.0, z0 + H)])
                continue
            tris.append([vtx(k, i), vtx(k, i + 1), vtx(k + 1, i)])
            tris.append([vtx(k + 1, i), vtx(k, i + 1), vtx(k + 1, i + 1)])
    out = []
    for t in tris:
        cx = sum(p[0] for p in t) / 3
        cy = sum(p[1] for p in t) / 3
        cz = sum(p[2] for p in t) / 3
        out.append(_orient(t, (cx / R, cy / R, (cz - z0) / H)))
    return out


@typed("ice_dome", 14, 14, 6.5, "얼음 차폐 돔", heights=[6.5, 5.8, 6.9, 6.3, 6.5])
def ice_dome(sp: Sprite, v: int):
    R, H = ((5.3, 6.0), (5.7, 5.3), (5.0, 6.5), (5.3, 5.8), (5.4, 6.0))[v]
    nlon, nlat = ((10, 4), (12, 4), (9, 5), (10, 4), (12, 5))[v]
    z0 = 0.25
    sp.contact_shadow(0, 0, 6.6, 6.6, 0.45)
    sp.berm_ring((0, 0, 0), R - 0.3, R + 1.3, 0.9, front=False)
    sp.disc((0, 0, z0), (0, 0, 1), R, Mat("#7d7a74"), edge=False)
    # 안의 거주 모듈 (얼음 너머로 비친다)
    hh = 2.6 if v != 2 else 3.6
    sp.cyl((0, 0, z0), (0, 0, z0 + hh), 1.7, WHITE, cap_mat=SILVER, bands=[0.5] if v == 2 else [])
    cyl_windows(sp, (0, 0, z0), (0, 0, z0 + hh), 1.7, 0.3 if v != 2 else 0.18, 0.55 if v != 2 else 0.36,
                toward=(1, 1, 0), n=3, spread=40, width=18)
    if v == 2:
        cyl_windows(sp, (0, 0, z0), (0, 0, z0 + hh), 1.7, 0.6, 0.78, toward=(1, 1, 0), n=3, spread=40, width=18)
    sp.glow((0, 0, z0 + 2.4), 70, WARM_WINDOW, 0.45)
    # 얼음 껍질: 뒷면 모서리 → 반투명 면 → 앞면 모서리
    facets = _ice_facets(R, H, z0, nlon, nlat)
    edges = {}
    for t in facets:
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            key = tuple(sorted((tuple(round(c, 3) for c in a), tuple(round(c, 3) for c in b))))
            edges[key] = (a, b)
    def is_front(a, b):
        m = mul(add(a, b), 0.5)
        return dot(norm((m[0], m[1], (m[2] - z0) * R / H)), VIEW) > 0.0
    edge_col = "#f2f9fd"
    for a, b in edges.values():
        if not is_front(a, b):
            sp.line(a, b, 0.04, "#9dbfd2", 0.4)
    tints = (("#CFE5F1", "#DDEEF6", "#C3DDEC", "#E6F2F8"), ("#C8E2F0", "#D8EBF5", "#BCD8EA", "#E2F0F7"),
             ("#D3E8F3", "#E2F1F8", "#C8E0EE", "#EAF4F9"), ("#C2DCEB", "#D3E6F1", "#B7D4E6", "#DDEDF5"),
             ("#CFE5F1", "#DDEEF6", "#C3DDEC", "#E6F2F8"))[v]
    for i, t in enumerate(facets):
        n = norm(cross(sub(t[1], t[0]), sub(t[2], t[0])))
        if dot(n, VIEW) <= 0:
            continue
        tint = tints[(i * 7 + i // 3) % 4]
        zc_ = sum(p[2] for p in t) / 3
        base = mix(rgb(tint), rgb("#8FB8D2"), max(0.0, 0.45 - (zc_ - z0) / H) * 0.9)
        col = lit(base, n, 0.5)
        pts = [PV(p) for p in t]
        sp.poly2(pts, hexc(col), None, 0, 0.84)
        warm = 0.12 + 0.22 * max(0.0, n[2])
        sp.poly2(pts, WARM_WINDOW if v != 4 else "#ffd8a8", None, 0, warm, layer="light")
    sp.glass_shell((0, 0, z0), R, R, H, z0, color="#d8ecf7", alpha=0.55)
    for a, b in edges.values():
        if is_front(a, b):
            sp.line(a, b, 0.04, edge_col, 0.7)
    sp.berm_ring((0, 0, 0), R - 0.3, R + 1.3, 0.9, front=True)
    # 짧은 여압 출입 터널
    if v == 1:
        p0, p1, n_out = (0, R - 0.8, 1.15), (0, 6.6, 1.15), (0, 1, 0)
    else:
        p0, p1, n_out = (R - 0.8, 0, 1.15), (6.6, 0, 1.15), (1, 0, 0)
    sp.cyl(p0, p1, 1.0, FROST, bands=[0.35, 0.7], band_color="#a9bfcc", cap_mat=STEEL)
    sp.disc(add(p1, mul(n_out, 0.03)), n_out, 0.62, DARK)
    sp.lamp(add(p1, (0, 0, 1.35)), AMBER, 10)
    if v == 3:
        sp.quad((-6.4, -3.0, 0.3), (0, 2.6, 0), (0, 0, 2.2), RADIATOR, back=RADIATOR)
        sp.panel_grid((-6.4, -3.0, 0.3), (0, 2.6, 0), (0, 0, 2.2), 4, 1, "#b9bec4", 0.5, 0.7)
    elif v == 4:
        for p in ((4.8, 4.8, 0), (-4.8, 4.8, 0)):
            sp.line(p, add(p, (0, 0, 2.6)), 0.07, "#8a9099")
            sp.lamp(add(p, (0, 0, 2.7)), AMBER, 12)


@typed("crater_roof", 26, 26, 4.0, "크레이터 지붕", heights=[4.0, 3.6, 4.3, 3.8, 4.0])
def crater_roof(sp: Sprite, v: int):
    rr = 10.6                       # 지붕 가장자리
    hz = (2.9, 2.5, 3.2, 2.7, 2.9)[v]
    zr = 1.05
    nrib = (20, 16, 24, 18, 20)[v]
    sp.contact_shadow(0, 0, 12.6, 12.6, 0.4)
    sp.berm_ring((0, 0, 0), rr - 0.4, 12.8, 1.35, front=False)
    sp.disc((0, 0, 0.04), (0, 0, 1), rr - 0.2, Mat("#6a655d"), edge=False)
    # 분화구 바닥: 계단 고리, 건물, 녹지
    for k, r in enumerate((8.6, 6.4)):
        sp.ring3((0, 0, 0.06), r, "#5a554e", 0.12, front_only=False)
    if v in (0, 2, 4):
        sp.disc((0, 0, 0.07), (0, 0, 1), 3.2, Mat("#7FA864"), edge=False)
    else:
        sp.disc((0, 0, 0.07), (0, 0, 1), 3.2, Mat("#3E7FB8", 0.6), edge=False)
    blocks = [(-6.8, -1.2, 1.6), (-4.2, -5.6, 1.4), (1.0, -7.4, 1.8), (5.6, -4.8, 1.3), (-6.0, 3.6, 1.5),
              (-2.2, 6.6, 1.3), (6.8, 1.2, 1.5), (3.4, 5.8, 1.6)]
    for i, (x, y, h) in enumerate(sorted(blocks, key=lambda b: b[0] + b[1])):
        if (i + v) % 4 == 3:
            sp.tree((x, y, 0.07), 2.4, 0.9, LEAF if i % 2 else GREEN)
            continue
        sp.box(x - 0.9, y - 0.7, 0.07, 1.8, 1.4, h, WHITE, top=SILVER)
        windows_row(sp, Sprite.box_faces(x - 0.9, y - 0.7, 0.07, 1.8, 1.4, h)["left"], 2, 0.4, 0.7, 0.15, 0.12)
    for x, y in ((-1.8, -1.6), (1.6, 1.4), (2.0, -1.8)):
        sp.tree((x, y, 0.07), 2.0, 0.75, LEAF)
    sp.glow((0, 0, 1.2), 110, WARM_WINDOW, 0.3)
    # 뒤쪽 갈비 → 유리 → 앞쪽 갈비
    def rib(th):
        return [((rr * math.cos(ph)) * math.cos(th), (rr * math.cos(ph)) * math.sin(th), zr + hz * math.sin(ph))
                for ph in [k * math.pi / 2 / 10 * 0.82 for k in range(11)]]
    ribs = [2 * math.pi * i / nrib for i in range(nrib)]
    for th in ribs:
        if dot((math.cos(th), math.sin(th), 0), VIEW) < -0.1:
            sp.polyline3(rib(th), "#7d848d", 0.1, 0.55)
    _glass_cap(sp, (0, 0), rr, rr, hz, zr, rings=(0.45, 0.75), ribs=0, alpha=0.26)
    for th in ribs:
        if dot((math.cos(th), math.sin(th), 0), VIEW) >= -0.1:
            sp.polyline3(rib(th), "#8a9099", 0.14, 0.95)
    for seg in _front_arc((0, 0, 0), rr, zr, 64, True, -0.05):
        sp.polyline3(seg, "#7d848d", 0.2)
    # 꼭대기 천창 고리 (빛나는 띠)
    zt = zr + hz * math.sin(math.pi / 2 * 0.82)
    rt = rr * math.cos(math.pi / 2 * 0.82)
    sp.cyl((0, 0, zt - 0.1), (0, 0, zt + 0.55), rt, Mat("#cdd3da", 0.3), cap_mat=Mat("#aab1b9", 0.3))
    cyl_ring(sp, (0, 0, zt - 0.1), (0, 0, zt + 0.55), rt, 0.2, 0.78, Mat("#3a5670", 0.8), WARM_WINDOW, 0.85)
    for k in range(16):
        a = 2 * math.pi * k / 16
        if dot((math.cos(a), math.sin(a), 0), VIEW) > -0.1:
            sp.line((rt * 1.01 * math.cos(a), rt * 1.01 * math.sin(a), zt + 0.02),
                    (rt * 1.01 * math.cos(a), rt * 1.01 * math.sin(a), zt + 0.42), 0.06, "#aab1b9")
    sp.dome((0, 0, zt + 0.55), rt * 0.7, 0.5, Mat("#bfc6ce", 0.4))
    sp.berm_ring((0, 0, 0), rr - 0.4, 12.8, 1.35, front=True)
    # 둑을 가르는 출입 경사로와 에어록
    ex = (1, 0, 0) if v != 3 else (0, 1, 0)
    side = (-ex[1], ex[0], 0)
    def at(a, s, z):
        return (ex[0] * a + side[0] * s, ex[1] * a + side[1] * s, z)
    sp.face(_orient([at(10.0, -1.5, 0.05), at(12.95, -1.5, 0.05), at(12.95, 1.5, 0.05), at(10.0, 1.5, 0.05)],
                    (0, 0, 1)), Mat("#3a3631"), ao=0)
    for s in (-1.6, 1.6):
        sp.face(_orient([at(10.4, s, 0), at(12.9, s, 0), at(12.9, s, 0.35), at(10.4, s, 1.45)], (side[0] * s, side[1] * s, 0)),
                CONCRETE, two_sided=True)
    bx0 = at(9.6, -1.4, 0)
    if ex == (1, 0, 0):
        sp.box(9.4, -1.4, 0, 1.2, 2.8, 2.3, CONCRETE, top=Mat("#b3a48e"))
        f = Sprite.box_faces(9.4, -1.4, 0, 1.2, 2.8, 2.3)["right"]
    else:
        sp.box(-1.4, 9.4, 0, 2.8, 1.2, 2.3, CONCRETE, top=Mat("#b3a48e"))
        f = Sprite.box_faces(-1.4, 9.4, 0, 2.8, 1.2, 2.3)["left"]
    door(sp, f, 0.25, 0.75, 0.75, Mat("#5c626b", 0.3))
    sp.stripes(add(f[0], add(mul(f[2], 0.84), mul(norm(cross(f[1], f[2])), 0.01))), f[1], mul(f[2], 0.16), n=8,
               normal=norm(cross(f[1], f[2])))
    sp.lamp(at(12.8, 1.7, 1.0), AMBER, 10)
    sp.lamp(at(12.8, -1.7, 1.0), AMBER, 10)
    # 모서리 장비
    if v == 1:
        for (x, y) in ((-11.8, 8.4), (8.4, -11.8)):
            sp.quad((x, y + 1.3, 0.35), (0, -1.3, 0.9), (2.6, 0, 0), SOLAR, back=STEEL)
            sp.panel_grid((x, y + 1.3, 0.35), (0, -1.3, 0.9), (2.6, 0, 0), 2, 4, "#6f86b0", 0.45, 0.6)
    elif v == 2:
        _dish(sp, (-10.4, -10.4, 3.0), norm((0.3, 1.0, 0.5)), 1.4)
        sp.line((-10.4, -10.4, 0), (-10.4, -10.4, 2.6), 0.12, "#9aa1aa")
    elif v == 4:
        for (x, y) in ((10.6, 10.6), (-10.8, 10.4), (10.4, -10.8)):
            sp.line((x, y, 0), (x, y, 3.0), 0.08, "#8a9099")
            sp.lamp((x, y, 3.1), AMBER, 12)


def _rdome(sp, c, R, H, mat=SINTER, rings=4, line="#83745f"):
    sp.dome((c[0], c[1], 0), R, H, mat)
    for k in range(1, rings + 1):
        zz = H * k / (rings + 1)
        kk = math.sqrt(max(0.0, 1 - (zz / H) ** 2))
        sp.ring3((c[0], c[1], zz), R * kk, line, 0.045, opacity=0.8)


def _dome_window(sp, c, R, H, ang, zf=0.42, r=0.36):
    t = math.radians(ang)
    kk = math.sqrt(max(0.0, 1 - zf ** 2))
    p = (c[0] + R * kk * math.cos(t) * 1.01, c[1] + R * kk * math.sin(t) * 1.01, H * zf)
    n = norm((math.cos(t), math.sin(t), 0.55))
    sp.window(_circle(p, n, r, 12), frame="#5f5446")


@typed("dome_cluster", 18, 16, 5.5, "돔 마을", heights=[5.5, 5.5, 5.2, 5.6, 6.2])
def dome_cluster(sp: Sprite, v: int):
    Rh, Hh = 3.5, 4.5
    Rs, Hs = 2.35, 3.0
    angs, dist, ent = [((0, 125, 235), 6.5, 62), ((60, 180, 300), 6.3, 0), ((0, 125, 235), 6.5, 62),
                       ((45, 165, 285), 5.75, 345), ((0, 125, 235), 6.5, 62)][v]
    mat = (SINTER, SINTER, Mat("#A89A84"), SINTER, Mat("#958670"))[v]
    sp.contact_shadow(0, 0, 8.6, 7.6, 0.45)
    items = []
    for a in angs:
        d = (math.cos(math.radians(a)), math.sin(math.radians(a)), 0)
        c = (d[0] * dist, d[1] * dist)
        tc = mul(d, (Rh + dist - Rs) / 2)

        def tun(d=d):
            sp.half_cyl(mul(d, Rh - 0.5), mul(d, dist - Rs + 0.5), 1.0, mat, bands=[0.5], band_color="#83745f")
        items.append((tc, tun))

        def small(c=c, a=a):
            _rdome(sp, c, Rs, Hs, mat, 3)
            _dome_window(sp, c, Rs, Hs, 50 if a not in (0, 30) else 75, 0.4, 0.3)
            if v == 2:
                sp.disc((c[0], c[1], Hs - 0.04), (0, 0, 1), 0.7, GLASS, edge=False)
                sp.ring3((c[0], c[1], Hs - 0.02), 0.7, "#cfc6b6", 0.08, front_only=False)
                sp.light_poly(_circle((c[0], c[1], Hs - 0.01), (0, 0, 1), 0.7, 14), WARM_WINDOW, 0.8)
            else:
                sp.lamp((c[0], c[1], Hs + 0.05), AMBER, 6)
        items.append(((c[0], c[1], 1.0), small))
    de = (math.cos(math.radians(ent)), math.sin(math.radians(ent)), 0)

    def entrance():
        e0, e1 = mul(de, Rh - 0.5), mul(de, Rh + 2.0)
        sp.half_cyl(e0, e1, 1.15, mat, bands=[0.5], band_color="#83745f")
        q = add(e1, mul(de, 0.02))
        side = (-de[1], de[0], 0)
        sp.face(_orient([add(q, mul(side, -0.5)), add(q, mul(side, 0.5)), add(add(q, mul(side, 0.5)), (0, 0, 0.95)),
                         add(add(q, mul(side, -0.5)), (0, 0, 0.95))], de), DARK, ao=0)
        sp.lamp(add(add(q, mul(side, 0.85)), (0, 0, 1.3)), AMBER, 9)
    items.append((mul(de, Rh + 1.0), entrance))

    def hub():
        _rdome(sp, (0, 0), Rh, Hh, mat, 4)
        for a in (ent - 40, ent + 40):
            _dome_window(sp, (0, 0), Rh, Hh, a, 0.45, 0.4)
        if v == 4:
            sp.cyl((0, 0, Hh - 0.1), (0, 0, Hh + 0.3), 0.5, STEEL)
            sp.line((0, 0, Hh + 0.3), (0, 0, Hh + 1.7), 0.08, "#9aa1aa")
            sp.lamp((0, 0, Hh + 1.8), "#ff5a3c", 6)
        else:
            sp.cyl((0, 0, Hh - 0.15), (0, 0, Hh + 0.55), 0.85, Mat("#cfc6b6"), cap_mat=Mat("#2a3a4a", 0.7))
            cyl_ring(sp, (0, 0, Hh - 0.15), (0, 0, Hh + 0.55), 0.85, 0.45, 0.8, Mat("#2a3a4a", 0.7), WARM_WINDOW, 0.8)
            antenna(sp, (0.4, -0.4, Hh + 0.55), 0.9)
    items.append(((0, 0, 1.5), hub))
    sp.parts(items)
    if v == 3:
        for p in ((7.6, 6.6, 0), (-7.8, 6.4, 0)):
            sp.line(p, add(p, (0, 0, 2.4)), 0.07, "#8a9099")
            sp.lamp(add(p, (0, 0, 2.5)), AMBER, 10)


@typed("garden_dome", 16, 14, 6.5, "정원 돔", heights=[6.5, 6.2, 6.8, 6.4, 6.5])
def garden_dome(sp: Sprite, v: int):
    R, H = (6.2, 5.4)
    ro = (3.5, 3.0, 3.9, 3.3, 3.6)[v]
    zc = H * math.sqrt(1 - (ro / R) ** 2)
    mat = (SINTER, SINTER, Mat("#A89A84"), SINTER, Mat("#958670"))[v]
    sp.contact_shadow(0, 0, 7.4, 7.0, 0.5)
    _rdome(sp, (0, 0), R, H, mat, 4)
    # 천창 안: 정원 바닥과 나무 꼭대기 (3D에서는 돔 꼭대기 위에 얹힌다)
    sp.disc((0, 0, zc), (0, 0, 1), ro, Mat("#2f3a2a"), edge=False)
    crowns = [(-1.3, -1.0, 0.85), (0.9, -1.4, 0.75), (-0.4, 0.6, 0.9), (1.5, 0.6, 0.7), (-1.9, 0.9, 0.65),
              (0.4, 1.9, 0.6)]
    if v == 3:
        crowns = crowns[:4]
    leafs = (LEAF, GREEN, Mat("#7BB661"))
    if v == 4:
        leafs = (LEAF, Mat("#C9A23A"), Mat("#D9893F"))
    k = ro / 3.5
    for i, (x, y, r) in enumerate(sorted(crowns, key=lambda t: t[0] + t[1])):
        zs_ = H * math.sqrt(max(0.0, 1 - ((x * k) ** 2 + (y * k) ** 2) / R ** 2)) - 0.1
        sp.ellipsoid((x * k, y * k, zs_), r * k, r * k, r * 0.75, leafs[i % 3], clip_z=zs_)
    sp.glow((0, 0, zc + 0.6), 30, "#d8ffb0", 0.45)
    sp.cyl((0, 0, zc - 0.3), (0, 0, zc + 0.2), ro + 0.1, Mat("#cfc6b6"), caps=False)
    _glass_cap(sp, (0, 0), ro + 0.05, ro + 0.05, (1.8, 1.7, 1.9, 1.7, 1.8)[v], zc + 0.2, rings=(0.5,), ribs=8,
               alpha=0.28)
    # 출입 터널
    sp.half_cyl((5.4, 0, 0), (7.8, 0, 0), 1.3, mat, bands=[0.5], band_color="#83745f")
    sp.face([(7.85, -0.5, 0), (7.85, 0.5, 0), (7.85, 0.5, 1.0), (7.85, -0.5, 1.0)], DARK, normal=(1, 0, 0), ao=0)
    sp.lamp((7.9, 0.9, 1.5), AMBER, 10)
    # 빛 관 헬리오스탯 (어깨 위의 작은 거울)
    nh = (5, 4, 6, 4, 5)[v]
    rh = (ro + R) / 2 + 0.15
    for i in range(nh):
        th = math.radians(-150 + 300 * i / (nh - 1)) if nh > 1 else 0.0
        d = (math.cos(th), math.sin(th), 0.0)
        if dot(d, VIEW) < -0.55:
            continue
        zs = H * math.sqrt(max(0.0, 1 - (rh / R) ** 2))
        b = (d[0] * rh, d[1] * rh, zs - 0.15)
        sp.cyl(b, add(b, (0, 0, 0.55)), 0.2, SILVER, cap_mat=GLASS)
        m = add(b, (0, 0, 1.0))
        sp.line(add(b, (0, 0, 0.5)), m, 0.05, "#9aa1aa")
        tilt = norm((-0.42 + d[0] * 0.3, 0.88 + d[1] * 0.3, 1.2))
        u, w = basis(tilt)
        o = add(m, add(mul(u, -0.4), mul(w, -0.35)))
        sp.quad(o, mul(u, 0.8), mul(w, 0.7), MIRROR, back=STEEL)


# ═════════════════════════════════════════════════════════════════════
# 대피소 (storm_shelter 계열)
# ═════════════════════════════════════════════════════════════════════

def _clip01(poly):
    """(u, v) 다각형을 단위 정사각형으로 자른다 (Sutherland–Hodgman)."""
    for axis, bound, less in ((0, 0.0, False), (0, 1.0, True), (1, 0.0, False), (1, 1.0, True)):
        out = []
        for i in range(len(poly)):
            a, b = poly[i - 1], poly[i]
            ia = a[axis] <= bound if less else a[axis] >= bound
            ib = b[axis] <= bound if less else b[axis] >= bound
            if ia != ib:
                t = (bound - a[axis]) / (b[axis] - a[axis])
                out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            if ib:
                out.append(b)
        poly = out
        if len(poly) < 3:
            return []
    return poly


def _quilt(sp, frame, nu, nv, mat=POLY, hi=Mat("#F8F9F5", 0.05), lift=0.035):
    """마름모로 누빈 패드 판: 칸마다 부푼 베개 (바깥 판 + 밝은 가운데)."""
    o, e1, e2 = frame
    n = norm(cross(e1, e2))
    hu, hv = 0.5 / nu, 0.5 / nv

    def put(uv, k, m, dz):
        cu = sum(q[0] for q in uv) / len(uv)
        cv = sum(q[1] for q in uv) / len(uv)
        pts = [add(add(add(o, mul(e1, cu + (q[0] - cu) * k)), mul(e2, cv + (q[1] - cv) * k)), mul(n, dz)) for q in uv]
        sp.face(_orient(pts, n), m, normal=n, edge=False, ao=0)
    for j in range(-1, 2 * nv + 2):
        for i in range(-1, nu + 2):
            cu, cv = (i + 0.5 * (j % 2)) * 2 * hu, j * hv
            dia = _clip01([(cu - hu, cv), (cu, cv - hv), (cu + hu, cv), (cu, cv + hv)])
            if len(dia) < 3:
                continue
            area = 0.5 * abs(sum(dia[k - 1][0] * dia[k][1] - dia[k][0] * dia[k - 1][1] for k in range(len(dia))))
            if area < hu * hv * 0.25:
                continue
            put(dia, 0.86, mat, lift)
            put(dia, 0.42, hi, lift * 2)


def _heavy_door(sp, frame, beacon=True):
    """두꺼운 강철 문: 문짝, 돌림 손잡이, 경첩, 경고 줄."""
    o, e1, e2 = frame
    n = norm(cross(e1, e2))
    _decal(sp, frame, 0.1, 0.04, 0.9, 0.86, Mat("#5c626b", 0.35), 0.01)
    c = add(_face_pt(frame, 0.5, 0.45), mul(n, 0.04))
    u, w = norm(e1), norm(e2)
    sp.ring3(c, 0.28, "#d0d3d8", 0.07, normal=n, front_only=False)
    sp.line(sub(c, mul(u, 0.28)), add(c, mul(u, 0.28)), 0.05, "#d0d3d8")
    sp.line(sub(c, mul(w, 0.28)), add(c, mul(w, 0.28)), 0.05, "#d0d3d8")
    for vv in (0.2, 0.68):
        _decal(sp, frame, 0.04, vv, 0.12, vv + 0.08, Mat("#3a3f47"), 0.03)
    sp.stripes(add(_face_pt(frame, 0.0, 0.88), mul(n, 0.02)), e1, mul(e2, 0.12), n=8, normal=n)
    if beacon:
        sp.lamp(add(_face_pt(frame, 0.5, 1.0), add(mul(n, 0.15), (0, 0, 0.18))), AMBER, 9)


@typed("poly_shelter", 8, 6, 3.4, "폴리에틸렌 대피소", heights=[3.4, 3.1, 3.6, 3.4, 3.3])
def poly_shelter(sp: Sprite, v: int):
    L, W, h = ((6.2, 4.8, 2.9), (5.4, 4.6, 2.6), (5.8, 4.4, 3.1), (6.6, 4.8, 2.9), (6.0, 5.0, 2.8))[v]
    x0 = -3.6
    x1, y0, y1, zb, c = x0 + L, -W / 2, W / 2, 0.25, 0.45
    sp.contact_shadow(-0.2, 0, 4.4, 3.2, 0.5)
    sp.box(x0 - 0.2, y0 - 0.2, 0, L + 0.4, W + 0.4, zb, CONCRETE)
    seam = Mat("#C3C6BD", 0.05)
    sp.prism(rounded_rect(x0, y0, x1, y1, c), zb, h, seam, top=seam)
    nu = max(3, int(round((L - 2 * c) / 1.15)))
    nw = max(3, int(round((W - 2 * c) / 1.15)))
    rows = 2
    _quilt(sp, ((x1 - c, y1, zb), (-(L - 2 * c), 0, 0), (0, 0, h)), nu, rows)
    _quilt(sp, ((x1, y0 + c, zb), (0, W - 2 * c, 0), (0, 0, h)), nw, rows)
    _quilt(sp, ((x0 + c, y0 + c, zb + h), (L - 2 * c, 0, 0), (0, W - 2 * c, 0)), nu, nw, lift=0.03)
    zt = zb + h + 0.07
    # 지붕 설비
    sp.cyl((x0 + 1.2, y0 + 1.1, zt), (x0 + 1.2, y0 + 1.1, zt + 0.45), 0.35, STEEL, cap_mat=DARK)
    if v != 1:
        antenna(sp, (x0 + 0.9, y1 - 0.9, zt), 1.4)
    if v == 3:
        sp.cyl((x1 - 1.6, y0 + 1.2, zt), (x1 - 1.6, y0 + 1.2, zt + 0.45), 0.35, STEEL, cap_mat=DARK)
        sp.lamp((x0 + 2.6, 0.0, zt + 0.2), "#ff5a3c", 8)
    # 무거운 문 (두꺼운 문틀이 앞으로 나온다)
    if v == 1:
        sp.box(-0.9, y1, zb, 1.8, 0.28, 2.2, STEEL, top=DARK)
        _heavy_door(sp, Sprite.box_faces(-0.9, y1, zb, 1.8, 0.28, 2.2)["left"])
    elif v == 2:
        sp.prism(rounded_rect(x1 - 0.2, -1.2, x1 + 0.75, 1.2, 0.2), zb, 2.5, seam, top=seam)
        _quilt(sp, ((x1 + 0.55, 1.2, zb), (-0.55, 0, 0), (0, 0, 2.5)), 1, 2)
        sp.box(x1 + 0.75, -0.85, zb, 0.25, 1.7, 2.15, STEEL, top=DARK)
        _heavy_door(sp, Sprite.box_faces(x1 + 0.75, -0.85, zb, 0.25, 1.7, 2.15)["right"])
    else:
        sp.box(x1, -0.9, zb, 0.3, 1.8, 2.25, STEEL, top=DARK)
        _heavy_door(sp, Sprite.box_faces(x1, -0.9, zb, 0.3, 1.8, 2.25)["right"])
    if v == 4:          # 지붕의 물주머니 (파란 띠)
        for k in range(3):
            y = y0 + 0.9 + k * 1.1
            sp.cyl((x0 + 1.0, y, zt + 0.25), (x1 - 1.2, y, zt + 0.25), 0.3, Mat("#3E6FB0", 0.35), cap_mat=Mat("#5c86c2"))
    sp.lamp((x1 - 0.2, y1 - 0.2, zb + h + 0.2), "#7CF29A", 6)


@typed("deep_shelter", 12, 10, 3.0, "지하 대피소", heights=[3.0, 3.0, 3.2, 2.8, 3.0])
def deep_shelter(sp: Sprite, v: int):
    D = (2.0, 2.0, 2.3, 1.8, 2.0)[v]               # 경사로 바닥 깊이
    xb, xt, w = -0.8, 5.0, (1.6, 1.6, 1.8, 1.4, 1.6)[v]
    sp.contact_shadow(-1.0, 0, 6.2, 4.8, 0.45)
    # 3D 보기의 구덩이 입구 (2D는 아래 그림이 덮는다)
    sp.face([(xb, -w, 0.01), (xt, -w, 0.01), (xt, w, 0.01), (xb, w, 0.01)], Mat("#24221f"), ao=0)
    sp.tbox(-6.0, -4.7, xb, 4.7, 1.6, 2.4, BERM, top=Mat("#6e6862"))
    for zz in (0.8, 1.6):
        k = zz / 2.4 * 1.6
        sp.polyline3([(-6.0 + k, 4.7 - k, zz), (xb - k, 4.7 - k, zz), (xb - k, -4.7 + k, zz)], "#5f5953", 0.06, 0.7)
    # 환기구 둘 (버섯 뚜껑)
    for y in ((-2.2, 2.2), (-2.2, 2.2), (-2.6, 2.6), (-1.8, 1.8), (-2.2, 2.2))[v]:
        p = (-3.6, y, 2.35)
        sp.cyl(p, add(p, (0, 0, 0.75)), 0.3, STEEL, bands=[0.5])
        sp.frustum(add(p, (0, 0, 0.75)), add(p, (0, 0, 0.92)), 0.3, 0.62, Mat("#9aa1aa", 0.3), caps=False)
        sp.cyl(add(p, (0, 0, 0.92)), add(p, (0, 0, 1.02)), 0.62, Mat("#9aa1aa", 0.3), cap_mat=STEEL)
    # 머리벽 (콘크리트 문틀)
    sp.box(xb - 0.9, -w - 1.0, 0, 0.9, 2 * w + 2.0, 2.7, CONCRETE, top=Mat("#b3a48e"))
    hf = Sprite.box_faces(xb - 0.9, -w - 1.0, 0, 0.9, 2 * w + 2.0, 2.7)["right"]
    sp.stripes(add(_face_pt(hf, 0.0, 0.78), (0.01, 0, 0)), hf[1], mul(hf[2], 0.13), n=12, normal=(1, 0, 0))
    sp.box(xb, -w - 0.3, 0, xt - xb, 0.3, 0.35, CONCRETE)
    # 구덩이: 먼 옆벽, 땅속 머리벽, 큰 방폭문, 경사 바닥
    def zr(x):
        return -D * (xt - x) / (xt - xb)
    sp.face(_orient([(xb, -w, zr(xb)), (xt, -w, 0.0), (xb, -w, 0.0)], (0, 1, 0)), CONCRETE, ao=0.3)
    sp.face(_orient([(xb, -w, -D), (xb, w, -D), (xb, w, 0), (xb, -w, 0)], (1, 0, 0)), CONCRETE, ao=0.3)
    dz0, dz1 = -D, 1.0
    fr = ((xb + 0.02, -w + 0.15, dz0), (0, 2 * w - 0.3, 0), (0, 0, dz1 - dz0))
    sp.face(_orient(sp.on_face(*fr, 0, 0, 1, 1), (1, 0, 0)), Mat("#4a4f57", 0.3), ao=0)
    sp.face(_orient(sp.on_face(*fr, 0.08, 0.0, 0.92, 0.94), (1, 0, 0)), Mat("#7d848d", 0.35), ao=0.25)
    for k in range(1, 6):
        q0 = _face_pt(fr, 0.08, 0.94 * k / 6)
        sp.line(add(q0, (0.03, 0, 0)), add(_face_pt(fr, 0.92, 0.94 * k / 6), (0.03, 0, 0)), 0.05, "#5c626b")
    sp.line(add(_face_pt(fr, 0.5, 0.0), (0.04, 0, 0)), add(_face_pt(fr, 0.5, 0.94), (0.04, 0, 0)), 0.06, "#3a3f47")
    floor = _orient([(xb, -w, -D), (xt, -w, 0), (xt, w, 0), (xb, w, -D)], (0, 0, 1))
    sp.face(floor, Mat("#5a554e"), ao=0)
    for k in range(4):
        x = xb + (xt - xb) * (0.18 + 0.2 * k)
        sp.line((x, -w + 0.2, zr(x) + 0.02), (x + 0.5, 0, zr(x + 0.5) + 0.02), 0.12, "#E9C24A", 0.85)
        sp.line((x + 0.5, 0, zr(x + 0.5) + 0.02), (x, w - 0.2, zr(x) + 0.02), 0.12, "#E9C24A", 0.85)
    sp.light_poly(_orient([(xb + 0.05, -w + 0.3, -D + 0.1), (xb + 0.05, w - 0.3, -D + 0.1),
                           (xb + 0.05, w - 0.3, -D + 0.4), (xb + 0.05, -w + 0.3, -D + 0.4)], (1, 0, 0)), "#ffcf8a", 0.45)
    # 가까운 쪽 포장 (땅 아래를 가린다)와 난간
    sp.box(xb, w, 0, xt - xb + 0.5, 2.8, 0.12, CONCRETE, top=Mat("#8f8576"))
    sp.box(xb, w, 0.12, xt - xb, 0.25, 0.35, CONCRETE)
    _rail(sp, [(xb + 0.3 + i * (xt - xb - 0.6) / 4, w + 0.12, 0.47) for i in range(5)], 0.75, "#E9C24A")
    _rail(sp, [(xb + 0.3 + i * (xt - xb - 0.6) / 4, -w - 0.15, 0.35) for i in range(5)], 0.75, "#E9C24A")
    # 경고등
    sp.cyl((xb - 0.45, 0, 2.7), (xb - 0.45, 0, 2.95), 0.18, STEEL)
    sp.lamp((xb - 0.45, 0, 3.05), RED_LIGHT, 11)
    sp.lamp((xb + 0.1, w + 0.6, 1.4), AMBER, 9)
    if v != 3:
        sp.lamp((xb + 0.1, -w - 0.5, 1.4), AMBER, 9)
    if v == 2:
        sp.line((-4.8, -0.2, 2.4), (-4.8, -0.2, 3.1), 0.1, "#9aa1aa")
        sp.quad((-5.6, -1.0, 3.0), (1.6, 0, 0.0), (0, 1.6, 0.45), SOLAR, back=STEEL)
        sp.panel_grid((-5.6, -1.0, 3.0), (1.6, 0, 0.0), (0, 1.6, 0.45), 2, 2, "#6f86b0", 0.45, 0.6)
    elif v == 4:
        antenna(sp, (-4.6, 0.0, 2.4), 1.8)


def _wheel(sp, x, y, z, r, wdt, near):
    y0, y1 = y - wdt / 2, y + wdt / 2
    sp.cyl((x, y0, z), (x, y1, z), r, Mat("#2f3238", 0.1), cap_mat=Mat("#3a3e45", 0.1), bands=[0.25, 0.75],
           band_color="#24272c")
    if near:
        sp.disc((x, y1 + 0.01, z), (0, 1, 0), r * 0.55, STEEL)
        sp.disc((x, y1 + 0.02, z), (0, 1, 0), r * 0.2, DARK)


@typed("rover_shelter", 9, 5, 3.6, "대피 차량", heights=[3.6, 3.6, 3.9, 3.3, 3.7])
def rover_shelter(sp: Sprite, v: int):
    body = (WHITE, Mat("#E5DCC8", 0.05), WHITE, Mat("#D8DDE2", 0.1), WHITE)[v]
    stripe = (ORANGE, RED, ORANGE, YELLOW, TEAL)[v]
    xs, yw, rw, ww = (-2.9, -0.1, 2.7), 1.82, 0.72, 0.46
    zc0, zc1, xc0, xc1 = 1.05, 3.3 if v != 3 else 3.0, -4.1, 2.8
    sp.contact_shadow(0, 0, 4.8, 2.6, 0.5)
    for x in xs:
        _wheel(sp, x, -yw, rw, rw, ww, False)
    sp.box(-3.9, -1.45, 0.55, 7.9, 2.9, 0.5, DARK)
    sp.box(xc0, -1.7, zc0, xc1 - xc0, 3.4, zc1 - zc0, body, top=SILVER)
    f = Sprite.box_faces(xc0, -1.7, zc0, xc1 - xc0, 3.4, zc1 - zc0)
    sp.panel_grid(*f["left"], 5, 2, "#b5b0a4", 0.5, 0.75)
    band_on(sp, f["left"], 0.1, 0.2, stripe)
    # 앞 조종석 (비스듬한 앞유리)
    zn = 2.0
    nose = [((2.8, 1.6, zc0), (4.3, 1.6, zc0), (4.3, 1.6, zn), (2.8, 1.6, zc1)),
            ((2.8, -1.6, zc0), (2.8, -1.6, zc1), (4.3, -1.6, zn), (4.3, -1.6, zc0))]
    sp.face(_orient(list(nose[1]), (0, -1, 0)), body)
    sp.face(_orient([(4.3, -1.6, zc0), (4.3, 1.6, zc0), (4.3, 1.6, zn), (4.3, -1.6, zn)], (1, 0, 0)), body)
    sp.face(_orient([(4.3, -1.6, zn), (4.3, 1.6, zn), (2.8, 1.6, zc1), (2.8, -1.6, zc1)], (1, 0, 0.8)), body)
    sp.face(_orient(list(nose[0]), (0, 1, 0)), body)
    sp.window(_orient([(4.22, -1.35, zn + 0.12), (4.22, 1.35, zn + 0.12), (2.95, 1.35, zc1 - 0.08),
                       (2.95, -1.35, zc1 - 0.08)], (1, 0, 0.8)))
    sp.window(_orient([(3.0, 1.62, zc0 + 0.95), (3.75, 1.62, zc0 + 0.95), (3.0, 1.62, zc1 - 0.25)], (0, 1, 0)))
    for y in (-1.15, 1.15):
        sp.face(_orient([(4.31, y - 0.25, 1.45), (4.31, y + 0.25, 1.45), (4.31, y + 0.25, 1.75),
                         (4.31, y - 0.25, 1.75)], (1, 0, 0)), Mat("#fff4d6", 0.6), ao=0, edge=False)
        sp.lamp((4.4, y, 1.6), "#fff1c9", 12)
    # 두꺼운 차폐 옆면: 방사선 표지, 작은 둥근 창, 해치
    _trefoil(sp, (-1.4 if v != 2 else 0.6, 1.71, 2.25), (0, 1, 0), 0.55)
    for x in ((0.6, 1.7), (1.8,), (-2.6, 1.8), (0.6, 1.7), (1.8,))[v]:
        sp.window(_circle((x, 1.72, 2.35), (0, 1, 0), 0.24, 12), frame="#8a9099")
    hx = -3.6
    sp.face(_orient(sp.on_face(*f["left"], 0.82, 0.08, 0.95, 0.82), (0, 1, 0)), Mat("#9aa1aa", 0.3), ao=0)
    sp.lamp((hx + 0.45, 1.85, zc1 - 0.05), AMBER, 8)
    # 지붕
    zt = zc1
    if v == 0:
        sp.quad((-3.6, -1.3, zt + 0.35), (3.2, 0, 0), (0, 2.6, 0.0), RADIATOR, back=RADIATOR)
        sp.panel_grid((-3.6, -1.3, zt + 0.35), (3.2, 0, 0), (0, 2.6, 0.0), 5, 1, "#b9bec4", 0.5, 0.7)
        legs(sp, [(-3.4, -1.1, zt + 0.35), (-0.6, 1.1, zt + 0.35)], zt)
    elif v == 1:
        sp.quad((-3.4, -1.4, zt + 0.3), (3.6, 0, 0), (0, 2.8, 0.2), SOLAR, back=STEEL)
        sp.panel_grid((-3.4, -1.4, zt + 0.3), (3.6, 0, 0), (0, 2.8, 0.2), 4, 3, "#6f86b0", 0.45, 0.6)
    elif v == 2:
        for k in range(3):
            sp.cyl((-3.6, -1.0 + k * 1.0, zt + 0.4), (0.6, -1.0 + k * 1.0, zt + 0.4), 0.4, Mat("#3E6FB0", 0.35),
                   cap_mat=Mat("#5c86c2"))
    elif v == 4:
        crate(sp, -3.4, -1.2, 1.0, ORANGE, zt)
        crate(sp, -2.2, -1.2, 1.0, Mat("#C9A23A"), zt)
    sp.box(1.4, -1.3, zt, 1.1, 2.6, 0.2, DARK)
    for y in (-0.9, -0.3, 0.3, 0.9):
        sp.lamp((2.5, y, zt + 0.12), "#fff1c9", 5)
    antenna(sp, (0.6, -1.2, zt), 1.3 if v != 3 else 0.9)
    for x in xs:
        _wheel(sp, x, yw, rw, rw, ww, True)


def _coil(sp, c, R, tube, front, mat=CRYO, n=28):
    """x축을 둘러싼 고리 코일의 앞 또는 뒤 반쪽 (짧은 원기둥을 이어 그린다)."""
    segs = []
    for k in range(n):
        t0, t1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        tm = (t0 + t1) / 2
        radial = (0.0, math.cos(tm), math.sin(tm))
        if (dot(radial, VIEW) > 0) != front:
            continue
        a = (c[0], c[1] + R * math.cos(t0), c[2] + R * math.sin(t0))
        b = (c[0], c[1] + R * math.cos(t1), c[2] + R * math.sin(t1))
        d = mul(norm(sub(b, a)), 0.035)
        segs.append((dot(add(a, b), VIEW), sub(a, d), add(b, d)))
    for _, a, b in sorted(segs):
        sp.cyl(a, b, tube, mat, caps=False, edge=False)


@typed("magnetic_shelter", 10, 8, 5.0, "자기 차폐실", heights=[5.0, 5.0, 4.8, 5.0, 5.2])
def magnetic_shelter(sp: Sprite, v: int):
    zc, rm = 2.45, 1.4
    Rc, tube = (2.0, 2.0, 1.9, 2.0, 2.1)[v], 0.22
    xs = ((-2.6, -0.4, 1.8), (-2.6, -0.4, 1.8), (-2.4, -0.5, 1.4), (-2.8, -0.5, 1.8), (-2.6, -0.4, 1.8))[v]
    coil_mat = (CRYO, Mat("#D9893F", 0.3), CRYO, Mat("#B8733F", 0.45), CRYO)[v]
    sp.contact_shadow(-0.2, 0, 5.4, 3.6, 0.5)
    # 받침과 코일 받침 상자
    for x in xs:
        sp.box(x - 0.45, -0.9, 0, 0.9, 1.8, zc - Rc + 0.05, Mat("#5b6470", 0.2), top=Mat("#7A8490", 0.2))
    for x in (-3.6, -1.5, 0.7, 2.6):
        sp.box(x - 0.25, -1.2, 0, 0.5, 2.4, zc - rm + 0.15, STEEL)
    for x in xs:
        _coil(sp, (x, 0, zc), Rc, tube, False, coil_mat)
    p0, p1 = (-4.3, 0, zc), (3.1, 0, zc)
    sp.cyl(p0, p1, rm, WHITE, bands=[0.25, 0.5, 0.75], band_color="#bdb6a8", cap_mat=STEEL)
    ang = Sprite.facing_angle(p0, p1, norm((0.0, 1.0, 0.35)))
    for s in ((0.08, 0.38, 0.66), (0.08, 0.38, 0.66), (0.24, 0.52), (0.08, 0.38, 0.66), (0.38, 0.66))[v]:
        sp.window(Sprite.cyl_patch(p0, p1, rm, s, s + 0.08, ang - 14, ang + 14))
    for x in xs:
        _coil(sp, (x, 0, zc), Rc, tube, True, coil_mat)
        pts = [(x, Rc * math.cos(t), zc + Rc * math.sin(t)) for t in [math.radians(-40 + 8 * k) for k in range(21)]]
        sp.polyline3([add(p, mul(norm((0, p[1], p[2] - zc)), tube + 0.02)) for p in pts], CYAN_LIGHT, 0.05, 0.6,
                     layer="light")
        # 냉각 상자 (크라이오스탯): 코일 꼭대기에 걸터앉는다
        zt = zc + Rc - 0.1
        sp.box(x - 0.35, -0.55, zt, 0.7, 1.1, 0.55, FROST, top=Mat("#cfe0ea", 0.3))
        cf = Sprite.box_faces(x - 0.35, -0.55, zt, 0.7, 1.1, 0.55)
        band_on(sp, cf["left"], 0.7, 0.85, BLUE)
        sp.lamp(add(_face_pt(cf["right"], 0.5, 0.5), (0.05, 0, 0)), CYAN_LIGHT, 5)
    # 에어록
    sp.box(3.15, -1.0, 0, 1.55, 2.0, 3.6, WHITE, top=SILVER)
    f = Sprite.box_faces(3.15, -1.0, 0, 1.55, 2.0, 3.6)
    door(sp, f["right"], 0.25, 0.75, 0.62, Mat("#5c626b", 0.3))
    band_on(sp, f["left"], 0.86, 0.94, Mat("#3E6FB0", 0.2))
    windows_row(sp, f["left"], 1, 0.5, 0.72, 0.3)
    if v == 2:
        sp.quad((-4.8, -3.6, 0.3), (2.6, 0, 0), (0, 0, 1.6), RADIATOR, back=RADIATOR)
        sp.panel_grid((-4.8, -3.6, 0.3), (2.6, 0, 0), (0, 0, 1.6), 4, 1, "#b9bec4", 0.5, 0.7)
    elif v == 4:
        antenna(sp, (4.2, 0.6, 3.6), 1.5)
    elif v == 1:
        sp.box(-4.6, 2.2, 0, 1.4, 1.2, 1.1, Mat("#5b6470", 0.2), top=SILVER)
        sp.lamp((-3.9, 3.45, 0.8), CYAN_LIGHT, 6)


# ═════════════════════════════════════════════════════════════════════
# 의료 (medical_bay 계열)
# ═════════════════════════════════════════════════════════════════════

def _awning(sp, o, e1, e2, n, colors, valance=0.22):
    """줄무늬 차양: o에서 e1(벽에서 바깥)·e2(옆) 방향으로 펼친 판, 앞 가장자리에 늘어진 천."""
    for i in range(n):
        q = add(o, mul(e2, i / n))
        sp.quad(q, e1, mul(e2, 1 / n), colors[i % len(colors)], back=colors[i % len(colors)])
        f0 = add(q, e1)
        sp.quad(f0, mul(e2, 1 / n), (0, 0, -valance), colors[i % len(colors)], back=colors[i % len(colors)])


def _gurney(sp, c, along=(1, 0, 0)):
    """바퀴 달린 들것."""
    a = norm(along)
    s_ = (-a[1], a[0], 0.0)
    for du in (-0.55, 0.55):
        for dv in (-0.22, 0.22):
            p = add(add(c, mul(a, du)), mul(s_, dv))
            sp.line(p, add(p, (0, 0, 0.72)), 0.04, "#9aa1aa")
    o = add(add(c, mul(a, -0.65)), add(mul(s_, -0.27), (0, 0, 0.72)))
    sp.quad(o, mul(a, 1.3), mul(s_, 0.54), WHITE, back=STEEL)
    sp.quad(add(add(c, mul(a, 0.28)), add(mul(s_, -0.2), (0, 0, 0.75))), mul(a, 0.3), mul(s_, 0.4), Mat("#cfe6f5"),
            back=WHITE)


@typed("clinic", 6, 4, 3.2, "진료소", heights=[3.2, 3.6, 3.4, 3.0, 3.2])
def clinic(sp: Sprite, v: int):
    h = (2.55, 2.55, 2.8, 2.35, 2.55)[v]
    x1 = (1.15, 1.15, 1.15, 0.95, 1.15)[v]
    awn = ((RED, WHITE), (TEAL, WHITE), (ORANGE, WHITE), (WHITE,), (BLUE, WHITE))[v]
    sp.contact_shadow(-0.2, 0, 3.4, 2.4, 0.5)
    sp.box(-2.95, -1.85, 0, x1 + 3.05, 3.7, 0.3, STEEL)
    sp.box(-2.85, -1.75, 0.3, x1 + 2.85, 3.5, h, WHITE, top=SILVER)
    f = Sprite.box_faces(-2.85, -1.75, 0.3, x1 + 2.85, 3.5, h)
    band_on(sp, f["left"], 0.86, 0.95, RED if v != 1 else TEAL)
    o, e1, e2 = f["left"]
    for u in ((0.42, 0.68), (0.42, 0.68), (0.42, 0.68), (0.5,), (0.42, 0.68))[v]:
        sp.window(sp.on_face(o, e1, e2, u, 0.42, u + 0.2, 0.72))
    # 붉은 십자 표지판 (밤에 빛난다)
    o, e1, e2 = f["left"]
    sp.face(sp.on_face(o, e1, e2, 0.08, 0.3, 0.32, 0.8), WHITE, normal=(0, 1, 0), ao=0)
    _cross_sign(sp, f["left"], 0.2, 0.55, 0.38, RED, "#ff6a5a")
    if v == 1:          # 지붕 가장자리의 빛나는 간판
        zt = 0.3 + h
        sp.box(-1.2, 1.35, zt, 1.0, 0.2, 0.75, WHITE)
        bf = Sprite.box_faces(-1.2, 1.35, zt, 1.0, 0.2, 0.75)
        _cross_sign(sp, bf["left"], 0.5, 0.5, 0.7, RED, "#ff6a5a")
        legs(sp, [(-1.1, 1.3, zt + 0.3), (-0.3, 1.3, zt + 0.3)], zt)
    # 들것 출입구: 넓은 문, 경사로, 차양
    door(sp, f["right"], 0.22, 0.78, 0.74, Mat("#cfd6dc", 0.3), light=False)
    o, e1, e2 = f["right"]
    sp.line(add(_face_pt(f["right"], 0.5, 0.0), (0.02, 0, 0.0)), add(_face_pt(f["right"], 0.5, 0.74), (0.02, 0, 0)),
            0.04, "#8a9099")
    ramp = _orient([(x1, -0.75, 0.3), (2.7, -0.75, 0.02), (2.7, 0.75, 0.02), (x1, 0.75, 0.3)], (0, 0, 1))
    sp.face(ramp, CONCRETE, ao=0)
    for y in (-0.8, 0.8):
        sp.polyline3([(x1 + 0.1, y, 1.2), (2.6, y, 0.85), (2.6, y, 0.0)], "#c9ccd1", 0.05)
    if v in (0, 2, 4):
        _gurney(sp, (1.95, 1.2, 0.0))
    for x, y in ((2.8, -1.5), (2.8, 1.5)):
        sp.line((x, y, 0), (x, y, 0.3 + h - 0.35), 0.06, "#8a9099")
    _awning(sp, (x1, -1.6, 0.3 + h - 0.05), (2.85 - x1, 0, -0.3), (0, 3.2, 0), 8 if v != 3 else 1, awn)
    if v == 3:
        sp.line((2.85, -1.6, 0.3 + h - 0.36), (2.85, 1.6, 0.3 + h - 0.36), 0.08, "#D9532C")
    sp.lamp((x1 + 0.15, 0.0, 0.3 + h - 0.45), WARM_WINDOW, 9)
    if v == 2:
        sp.cyl((-2.2, -1.0, 0.3 + h), (-2.2, -1.0, 0.3 + h + 0.6), 0.45, WHITE, bands=[0.5], band_color="#3FB8AF")
    elif v == 4:
        sp.box(-2.3, -1.3, 0.3 + h, 1.2, 1.0, 0.4, STEEL, top=DARK)
    else:
        sp.box(-2.0, -1.2, 0.3 + h, 0.9, 0.9, 0.35, STEEL, top=DARK)


@typed("surgery_center", 11, 8, 4.6, "수술 센터", heights=[4.6, 4.6, 4.8, 4.4, 4.6])
def surgery_center(sp: Sprite, v: int):
    hb, hs = (3.7, 3.7, 4.0, 3.5, 3.7)[v], (3.0, 3.0, 3.0, 2.8, 3.2)[v]
    ys1 = 3.0
    accent = (RED, RED, Mat("#3E6FB0", 0.2), RED, TEAL)[v]
    sp.contact_shadow(0, 0, 6.0, 4.4, 0.5)
    sp.box(-5.4, -3.9, 0, 10.8, 3.4, 0.3, STEEL)
    sp.box(1.6, -0.5, 0, 3.8, ys1 + 0.7, 0.3, STEEL)
    # 뒤 날개 (수술동)
    sp.box(-5.2, -3.7, 0.3, 10.4, 3.0, hb, WHITE, top=SILVER)
    fb = Sprite.box_faces(-5.2, -3.7, 0.3, 10.4, 3.0, hb)
    band_on(sp, fb["left"], 0.88, 0.96, accent)
    band_on(sp, fb["right"], 0.88, 0.96, accent)
    # 밝은 수술실 창 (낮에도 푸르게 빛난다)
    o, e1, e2 = fb["left"]
    win = sp.on_face(o, e1, e2, 0.42, 0.28, 0.66, 0.78)
    sp.window(win, COOL_WINDOW, glass=Mat("#9fd0ea", 0.6))
    c = add(_face_pt(fb["left"], 0.54, 0.62), (0, 0.04, 0))
    sp.face(_circle(c, (0, 1, 0), 0.45, 14), Mat("#5c6670", 0.3), normal=(0, 1, 0), edge=False, ao=0)
    sp.face(_circle(add(c, (0, 0.01, 0)), (0, 1, 0), 0.28, 12), Mat("#ffffff", 0.6), normal=(0, 1, 0), edge=False, ao=0)
    sp.line(add(c, (0, 0.02, 0.45)), add(c, (0, 0.02, 1.0)), 0.05, "#5c6670")
    sp.glow(add(c, (0, 0.3, -0.2)), 26, COOL_WINDOW, 0.7)
    windows_row(sp, (o, e1, e2), 2, 0.4, 0.66, 0.72, 0.04)
    sp.face(sp.on_face(o, e1, e2, 0.68, 0.0, 0.84, 0.62), Mat("#2a3a4a", 0.7), normal=(0, 1, 0), ao=0)
    sp.light_poly(sp.on_face(o, e1, e2, 0.68, 0.0, 0.84, 0.62), WARM_WINDOW, 0.7)
    sp.lamp(_face_pt((add(o, (0, 0.15, 0)), e1, e2), 0.76, 0.72), AMBER, 8)
    windows_row(sp, fb["right"], 2, 0.42, 0.68, 0.15, 0.1)
    # 지붕 채광 상자 (수술실 위)
    sx = (-1.6, -1.6, -2.4, -1.2, -1.6)[v]
    sp.box(sx, -3.0, 0.3 + hb, 1.8, 1.6, 0.6, WHITE, top=SILVER)
    sf = Sprite.box_faces(sx, -3.0, 0.3 + hb, 1.8, 1.6, 0.6)
    sp.window(sp.on_face(*sf["left"], 0.08, 0.2, 0.92, 0.8), COOL_WINDOW, glass=Mat("#9fd0ea", 0.6))
    sp.box(-4.6, -3.2, 0.3 + hb, 1.4, 1.2, 0.5, STEEL, top=DARK)
    if v != 3:
        sp.box(2.6, -3.3, 0.3 + hb, 1.1, 1.1, 0.45, STEEL, top=DARK)
    # 옆 날개 (구급차 출입)
    sp.box(1.8, -0.7, 0.3, 3.4, ys1 + 0.7, hs, WHITE, top=SILVER)
    fs = Sprite.box_faces(1.8, -0.7, 0.3, 3.4, ys1 + 0.7, hs)
    band_on(sp, fs["left"], 0.86, 0.95, accent)
    band_on(sp, fs["right"], 0.86, 0.95, accent)
    o, e1, e2 = fs["left"]
    sp.face(sp.on_face(o, e1, e2, 0.12, 0.0, 0.88, 0.72), Mat("#9aa1aa", 0.35), normal=(0, 1, 0), ao=0.15)
    for k in range(1, 7):
        sp.line(add(_face_pt(fs["left"], 0.12, 0.72 * k / 7), (0, 0.02, 0)),
                add(_face_pt(fs["left"], 0.88, 0.72 * k / 7), (0, 0.02, 0)), 0.03, "#7d848d")
    sp.stripes(add(_face_pt(fs["left"], 0.0, 0.74), (0, 0.02, 0)), e1, mul(e2, 0.1), n=10,
               colors=("#D9532C", "#F1F2F0"), normal=(0, 1, 0))
    yc = ys1 + 0.02
    for x in (2.0, 5.0):
        sp.line((x, yc + 0.85, 0), (x, yc + 0.85, 0.3 + hs * 0.8), 0.06, "#8a9099")
    sp.quad((1.8, yc, 0.3 + hs * 0.8), (3.4, 0, 0), (0, 0.95, -0.12), WHITE, back=STEEL)
    sp.lamp((3.5, yc + 0.1, 0.3 + hs * 0.78), RED_LIGHT, 9)
    windows_row(sp, fs["right"], 2, 0.42, 0.68, 0.14, 0.1)
    _cross_sign(sp, fs["right"], 0.5, 0.82, 0.14, RED, "#ff6a5a")
    sp.lamp((5.3, 1.3, 0.3 + hs - 0.3), AMBER, 8)
    if v == 2:
        antenna(sp, (4.6, 0.0, 0.3 + hs), 1.2)
    elif v == 4:
        sp.cyl((3.0, 1.2, 0.3 + hs), (3.0, 1.2, 0.3 + hs + 0.5), 0.5, WHITE, cap_mat=SILVER)


@typed("telemedicine", 6, 5, 4.0, "원격 진료실", heights=[4.0, 4.2, 3.8, 4.0, 4.1])
def telemedicine(sp: Sprite, v: int):
    sp.contact_shadow(-0.2, 0, 3.4, 2.8, 0.5)
    x0, x1, y0, y1, h = -2.7, 2.0, -2.1, 1.9, 2.5
    sp.box(x0 - 0.15, y0 - 0.15, 0, x1 - x0 + 0.3, y1 - y0 + 0.3, 0.3, STEEL)
    sp.box(x0, y0, 0.3, x1 - x0, y1 - y0, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.3, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.88, 0.96, BLUE)
    band_on(sp, f["right"], 0.88, 0.96, BLUE)
    # 화면 벽이 보이는 큰 창
    o, e1, e2 = f["left"]
    u0, u1 = ((0.12, 0.66), (0.1, 0.7), (0.14, 0.62), (0.12, 0.66), (0.3, 0.88))[v]
    sp.window(sp.on_face(o, e1, e2, u0, 0.24, u1, 0.8), "#ffd9a0", light_alpha=0.5)
    cols, rows = ((3, 2), (4, 2), (3, 2), (2, 2), (3, 2))[v]
    du = (u1 - u0 - 0.04) / cols
    for i in range(cols):
        for j in range(rows):
            a, b = u0 + 0.02 + i * du + 0.012, u0 + 0.02 + (i + 1) * du - 0.012
            c, d = 0.4 + j * 0.19, 0.56 + j * 0.19
            pts = [add(p, (0, 0.03, 0)) for p in sp.on_face(o, e1, e2, a, c, b, d)]
            sp.face(pts, Mat(("#6fb6e8", "#8fd0f0", "#5aa0dc")[(i + j) % 3], 0.5), normal=(0, 1, 0), edge=False, ao=0)
            sp.light_poly(pts, SCREEN_GLOW, 0.9)
    sp.face([add(p, (0, 0.03, 0)) for p in sp.on_face(o, e1, e2, u0 + 0.02, 0.26, u1 - 0.02, 0.33)],
            Mat("#3a3f47"), normal=(0, 1, 0), edge=False, ao=0)
    _cross_sign(sp, f["left"], (0.84 if v != 4 else 0.15), 0.55, 0.3, TEAL, CYAN_LIGHT)
    door(sp, f["right"], 0.35, 0.72, 0.74, Mat("#cfd6dc", 0.3))
    # 지붕 접시 안테나
    zt = 0.3 + h
    dx, dy, dr = ((-1.0, -0.7, 0.95), (-0.6, -0.4, 1.15), (0.6, -0.8, 0.85), (-1.2, -0.9, 0.9), (-1.0, -0.6, 0.95))[v]
    sp.cyl((dx, dy, zt), (dx, dy, zt + 0.45), 0.22, STEEL)
    sp.box(dx - 0.35, dy - 0.35, zt, 0.7, 0.7, 0.18, DARK)
    _dish(sp, (dx + 0.05, dy + 0.12, zt + 0.95), norm((0.25, 0.75, 0.62)), dr)
    if v == 1:
        sp.sphere((1.2, -1.2, zt + 0.5), 0.45, WHITE)
        sp.cyl((1.2, -1.2, zt), (1.2, -1.2, zt + 0.2), 0.2, STEEL)
    elif v == 3:
        o2, e12, e22 = (0.4, -1.6, zt + 0.2), (1.4, 0, 0), (0, 1.6, 0.4)
        sp.quad(o2, e12, e22, SOLAR, back=STEEL)
        sp.panel_grid(o2, e12, e22, 2, 2, "#6f86b0", 0.45, 0.6)
    elif v == 4:
        antenna(sp, (1.5, 1.4, zt), 1.2)
    sp.lamp((x1 + 0.1, y1 - 0.2, 2.4), CYAN_LIGHT, 7)


@typed("rehab_center", 8, 6, 4.2, "재활 운동실", heights=[4.2, 4.0, 4.4, 4.2, 4.2])
def rehab_center(sp: Sprite, v: int):
    x0, x1, y0, y1, h = -3.7, 3.0, -2.7, 2.7, 2.2
    rd, hd = (2.35, 2.2, 2.5, 2.35, 2.35)[v], (1.7, 1.5, 1.9, 1.7, 1.7)[v]
    accent = (ORANGE, TEAL, ORANGE, YELLOW, Mat("#9B7AD6"))[v]
    pod = (ORANGE, WHITE, Mat("#3E6FB0", 0.3), ORANGE, YELLOW)[v]
    sp.contact_shadow(-0.2, 0, 4.4, 3.4, 0.5)
    sp.box(x0 - 0.15, y0 - 0.15, 0, x1 - x0 + 0.3, y1 - y0 + 0.3, 0.3, STEEL)
    sp.box(x0, y0, 0.3, x1 - x0, y1 - y0, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.3, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.84, 0.94, accent)
    band_on(sp, f["right"], 0.84, 0.94, accent)
    windows_row(sp, f["left"], 4 if v != 1 else 3, 0.4, 0.68, 0.08, 0.05)
    door(sp, f["right"], 0.35, 0.68, 0.74, Mat("#cfd6dc", 0.3))
    # 유리 돔 아래 짧은 팔 원심기 (팔 끝에 탈것 둘)
    zt = 0.3 + h
    cx = -0.4
    sp.cyl((cx, 0, zt), (cx, 0, zt + 0.12), rd + 0.1, Mat("#cdd3da", 0.3), cap_mat=Mat("#8f969e", 0.2))
    sp.ring3((cx, 0, zt + 0.13), rd * 0.82, "#6f767f", 0.08, front_only=False)
    ang = math.radians((25, 60, 15, 40, 25)[v])
    arm = (math.cos(ang), math.sin(ang), 0.0)
    L = rd * 0.72
    za = zt + 0.95
    ends = sorted([mul(arm, L), mul(arm, -L)], key=lambda e: e[0] + e[1])

    def pod_at(e):
        c = (cx + e[0], e[1], za - 0.1)
        sp.ellipsoid(c, 0.42, 0.42, 0.34, pod)
        sp.window(_circle(add(c, mul(norm((1, 1, 0.6)), 0.4)), norm((1, 1, 0.6)), 0.13, 10))
    pod_at(ends[0])
    sp.cyl((cx, 0, zt + 0.12), (cx, 0, za + 0.15), 0.16, STEEL, cap_mat=DARK)
    sp.line((cx + ends[0][0], ends[0][1], za + 0.05), (cx + ends[1][0], ends[1][1], za + 0.05), 0.14, "#8a9099")
    sp.cyl((cx, 0, za - 0.05), (cx, 0, za + 0.2), 0.3, Mat("#5b6470", 0.3), cap_mat=STEEL)
    pod_at(ends[1])
    sp.glow((cx, 0, zt + 0.8), 26, WARM_WINDOW, 0.45)
    _glass_cap(sp, (cx, 0), rd, rd, hd, zt + 0.12, rings=(0.45, 0.8), ribs=10, alpha=0.3)
    if v == 2:
        o2, e12, e22 = (1.4, -2.4, zt + 0.15), (1.4, 0, 0), (0, 1.5, 0.35)
        sp.quad(o2, e12, e22, SOLAR, back=STEEL)
    elif v == 3:
        sp.box(1.5, 1.2, zt, 1.0, 1.0, 0.4, STEEL, top=DARK)
    sp.lamp((x1 + 0.1, y1 - 0.3, 2.0), AMBER, 8)


# ═════════════════════════════════════════════════════════════════════
# 연구 (research_lab 계열)
# ═════════════════════════════════════════════════════════════════════

def _sample_rack(sp, o, along, depth, n=5, h=0.9, colors=("#E07B39", "#ECE7DC", "#3E6FB0", "#6DAE57")):
    """시료 선반: 두 단의 작은 통."""
    a = norm(along)
    L = length(along)
    out = (-a[1], a[0], 0.0)
    for k, z in enumerate((0.0, h * 0.5)):
        base = add(o, (0, 0, z))
        sp.quad(base, along, mul(out, depth), Mat("#9aa1aa", 0.3), back=STEEL)
        for i in range(n):
            c = add(add(base, mul(a, L * (i + 0.5) / n)), mul(out, depth * 0.5))
            sp.cyl(c, add(c, (0, 0, h * 0.32)), min(0.09, L / n * 0.3), Mat(colors[(i + k) % len(colors)], 0.3))
    for u in (0.0, 1.0):
        p = add(o, mul(along, u))
        sp.line(p, add(p, (0, 0, h)), 0.04, "#8a9099")


@typed("field_lab", 6, 4, 3.2, "현장 실험실", heights=[3.2, 3.2, 3.0, 3.4, 3.2])
def field_lab(sp: Sprite, v: int):
    x0, x1, y0, y1, zb, zt = -2.7, 1.3, -1.15, 1.15, 0.75, 2.55
    body = (WHITE, Mat("#E5DCC8", 0.05), WHITE, Mat("#D9DEE3", 0.1), WHITE)[v]
    band = (VIOLET, VIOLET, ORANGE, VIOLET, TEAL)[v]
    sp.contact_shadow(-0.4, 0, 3.2, 1.9, 0.5)
    ax = (-1.55, -0.6)
    for x in ax:
        _wheel(sp, x, -1.22, 0.42, 0.42, 0.24, False)
    sp.box(-2.5, -0.9, 0.42, 3.7, 1.8, 0.33, DARK)
    for x, y in ((-2.55, -1.0), (-2.55, 1.0), (1.15, -1.0), (1.15, 1.0)):
        sp.line((x, y, zb), (x + (0.2 if x > 0 else -0.2), y * 1.25, 0.05), 0.06, "#7d848d")
    # 견인 막대와 받침 다리
    sp.polyline3([(x1, -0.65, 0.6), (2.45, 0.0, 0.55), (x1, 0.65, 0.6)], "#7d848d", 0.09)
    sp.line((2.1, 0.0, 0.58), (2.1, 0.0, 0.05), 0.08, "#9aa1aa")
    sp.box(1.95, -0.15, 0, 0.3, 0.3, 0.06, DARK)
    sp.box(x0, y0, zb, x1 - x0, y1 - y0, zt - zb, body, top=SILVER)
    f = Sprite.box_faces(x0, y0, zb, x1 - x0, y1 - y0, zt - zb)
    band_on(sp, f["left"], 0.82, 0.92, band)
    band_on(sp, f["right"], 0.82, 0.92, band)
    o, e1, e2 = f["left"]
    door(sp, f["left"], 0.8, 0.95, 0.85, Mat("#9aa1aa", 0.3), light=False)
    sp.box(-2.55, y1, 0.3, 0.55, 0.35, 0.45, STEEL)
    sp.window(sp.on_face(o, e1, e2, 0.45, 0.45, 0.72, 0.72), CYAN_LIGHT)
    windows_row(sp, f["right"], 1, 0.45, 0.72, 0.3)
    # 접이식 작업대와 시료 선반 (옆으로 펼친다)
    zbench = 1.35
    sp.quad((1.15, y1, zbench), (-1.3, 0, 0), (0, 0.6, 0), Mat("#cfd3d8", 0.2), back=STEEL)
    for x in (1.1, -0.1):
        sp.line((x, y1 + 0.55, zbench), (x, y1 + 0.05, zbench - 0.5), 0.04, "#8a9099")
    _sample_rack(sp, (1.05, y1 + 0.08, zbench + 0.01), (-1.1, 0, 0), 0.4, 5 if v != 2 else 4, 0.75)
    sp.quad((1.2, y1, zt - 0.05), (-1.4, 0, 0), (0, 0.75, -0.25), band, back=STEEL)
    for x in ax:
        _wheel(sp, x, 1.22, 0.42, 0.42, 0.24, True)
    # 펼치는 조명 기둥
    mx, my = (-2.25, -0.6) if v != 4 else (0.9, -0.6)
    tops = ((4.4, 3), (4.4, 3), (3.4, 2), (4.9, 3), (4.2, 3))[v]
    zz = zt
    for k in range(tops[1]):
        z1 = zt + (tops[0] - zt) * (k + 1) / tops[1]
        sp.cyl((mx, my, zz), (mx, my, z1), 0.13 - k * 0.03, Mat("#C9CCD1", 0.4), cap_mat=STEEL)
        zz = z1
    sp.box(mx - 0.08, my - 0.55, zz, 0.16, 1.1, 0.16, DARK)
    for d in (-0.38, 0.0, 0.38):
        sp.lamp((mx + 0.1, my + d, zz + 0.08), "#fff1c9", 12)
    if v == 1:
        sp.quad((-1.6, -0.9, zt + 0.25), (2.0, 0, 0), (0, 1.8, 0.0), SOLAR, back=STEEL)
        sp.panel_grid((-1.6, -0.9, zt + 0.25), (2.0, 0, 0), (0, 1.8, 0.0), 3, 2, "#6f86b0", 0.45, 0.6)
    elif v == 3:
        antenna(sp, (0.8, 0.6, zt), 1.2)
    else:
        sp.box(-0.2, -0.7, zt, 0.9, 0.8, 0.35, STEEL, top=DARK)


def _biohazard(sp, c, n, r):
    """생물 위험 표지 (노란 마름모 위 검은 세 고리)."""
    u, w = basis(n)
    dia = [add(c, mul(u, r)), add(c, mul(w, r)), add(c, mul(u, -r)), add(c, mul(w, -r))]
    sp.face(_orient([add(p, mul(n, 0.01)) for p in dia], n), BIO_YELLOW, normal=n, edge=False, ao=0)
    c2 = add(c, mul(n, 0.02))
    up = (0.0, 0.0, 1.0)
    side = norm(cross(n, up)) if abs(n[2]) < 0.9 else u
    for k in range(3):
        t = math.radians(90 + 120 * k)
        p = add(c2, add(mul(up, r * 0.26 * math.sin(t)), mul(side, r * 0.26 * math.cos(t))))
        sp.face(_circle(p, n, r * 0.24, 12), CHAR, normal=n, edge=False, ao=0)
        sp.face(_circle(add(add(p, mul(n, 0.005)), add(mul(up, r * 0.07 * math.sin(t)), mul(side, r * 0.07 * math.cos(t)))),
                        n, r * 0.14, 10), BIO_YELLOW, normal=n, edge=False, ao=0)
    sp.face(_circle(add(c2, mul(n, 0.008)), n, r * 0.09, 8), BIO_YELLOW, normal=n, edge=False, ao=0)


def _plant_rows(sp, x0, x1, ys, z, h=0.5, grow=True):
    for y in sorted(ys):
        sp.box(x0, y - 0.3, z, x1 - x0, 0.6, 0.25, Mat("#8a8f96"))
        n = max(2, int((x1 - x0) / 0.55))
        for i in range(n):
            x = x0 + (x1 - x0) * (i + 0.5) / n
            sp.ellipsoid((x, y, z + 0.25), 0.3, 0.3, h * 0.6, (LEAF, GREEN)[(i + int(y * 3)) % 2], clip_z=z + 0.25)


@typed("biology_lab", 10, 7, 4.4, "생명과학 연구소", heights=[4.4, 4.4, 4.6, 4.2, 4.4])
def biology_lab(sp: Sprite, v: int):
    xl = (0.8, 0.8, 0.4, 1.2, 0.8)[v]
    hl = (3.4, 3.4, 3.6, 3.2, 3.4)[v]
    sp.contact_shadow(0, 0, 5.4, 3.8, 0.5)
    sp.box(-4.95, -3.35, 0, xl + 4.95, 6.7, 0.3, STEEL)
    sp.box(-4.8, -3.2, 0.3, xl + 4.8, 6.4, hl, WHITE, top=SILVER)
    f = Sprite.box_faces(-4.8, -3.2, 0.3, xl + 4.8, 6.4, hl)
    band_on(sp, f["left"], 0.86, 0.95, BIO_YELLOW)
    band_on(sp, f["right"], 0.86, 0.95, BIO_YELLOW)
    o, e1, e2 = f["left"]
    nwin = (3, 3, 4, 2, 3)[v]
    for i in range(nwin):
        u = 0.32 + i * 0.6 / nwin
        sp.window(sp.on_face(o, e1, e2, u, 0.42, u + 0.6 / nwin - 0.05, 0.72), "#ffe9a8")
    door(sp, f["left"], 0.07, 0.2, 0.7, Mat("#cfd6dc", 0.3))
    sp.stripes(add(_face_pt(f["left"], 0.05, 0.72), (0, 0.01, 0)), mul(e1, 0.17), mul(e2, 0.06), n=6, normal=(0, 1, 0))
    _biohazard(sp, add(_face_pt(f["left"], 0.25, 0.55), (0, 0.01, 0)), (0, 1, 0), 0.42)
    # 지붕: 흄후드 배기구
    zt = 0.3 + hl
    for k, (x, y) in enumerate(((-3.6, -2.0), (-2.4, -2.0), (-3.0, 1.6))[: (3 if v != 3 else 2)]):
        sp.cyl((x, y, zt), (x, y, zt + 0.7), 0.22, STEEL, bands=[0.7], band_color="#E9C24A")
        sp.cyl((x, y, zt + 0.7), (x, y, zt + 0.82), 0.34, Mat("#9aa1aa", 0.3), cap_mat=DARK)
    sp.box(-1.2, -2.4, zt, 1.4, 1.2, 0.5, STEEL, top=DARK)
    # 온실 날개 (유리 볼트, 안에 작물 줄)
    gx0, gx1 = xl, 4.85
    gw = (2.3, 2.3, 2.5, 2.1, 2.3)[v]
    gh = (2.6, 2.6, 2.8, 2.4, 2.7)[v]
    sp.box(gx0, -gw, 0, gx1 - gx0, 2 * gw, 0.45, SINTER, top=Mat("#6f7a5e"))
    _plant_rows(sp, gx0 + 0.3, gx1 - 0.3, (-gw * 0.55, 0.0, gw * 0.55), 0.45)
    sp.glow(((gx0 + gx1) / 2, 0, 1.4), 40, GROW, 0.45)
    rim = []
    for i in range(25):
        t = math.pi * i / 24
        for x in (gx0, gx1):
            rim.append(PV((x, gw * math.cos(t), 0.45 + gh * math.sin(t))))
    sil = hull(rim)
    hlp = PV((gx0 + 1.0, gw * 0.5, 0.45 + gh * 0.9))
    fill = sp.radial([(0, "#ffffff", 0.3), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.05)], hlp[0], hlp[1], 6 * S)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_vault((gx0, 0, 0.45), (gx1, 0, 0.45), gw, rz=gh)
    for x in [gx0 + (gx1 - gx0) * k / 4 for k in range(5)]:
        pts = [(x, gw * math.cos(math.pi * i / 16), 0.45 + gh * math.sin(math.pi * i / 16)) for i in range(17)]
        sp.polyline3([q for q in pts if dot((0, q[1], q[2] - 0.45), VIEW) > -0.6], "#dfe9f2", 0.05, 0.6)
    sp.polyline3([(gx0, 0, 0.45 + gh), (gx1, 0, 0.45 + gh)], "#dfe9f2", 0.05, 0.6)
    sp.light_poly(_orient([(gx1 + 0.02, -gw * 0.7, 0.5), (gx1 + 0.02, gw * 0.7, 0.5),
                           (gx1 + 0.02, gw * 0.7, 0.45 + gh * 0.7), (gx1 + 0.02, -gw * 0.7, 0.45 + gh * 0.7)], (1, 0, 0)),
                  GROW, 0.35)
    sp.lamp((4.9, gw + 0.2, 1.2), AMBER, 8)
    if v == 2:
        antenna(sp, (-0.5, 1.8, zt), 1.4)
    elif v == 4:
        sp.cyl((-0.4, 1.6, zt), (-0.4, 1.6, zt + 0.8), 0.45, WHITE, bands=[0.5], band_color="#E9C24A")


@typed("materials_lab", 10, 8, 6.0, "재료 연구소", heights=[6.0, 6.2, 5.6, 6.0, 6.4])
def materials_lab(sp: Sprite, v: int):
    hall = Mat("#D8D4CC", 0.05)
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.5)
    sp.box(-4.9, -3.9, 0, 9.8, 7.8, 0.25, CONCRETE)
    x0, x1, y0, y1, h = -4.6, 1.8, -3.7, 1.3, 3.6
    # 뒤쪽 시험대 (+x 뒤 마당)
    def rig():
        rx, ry = (2.6, -3.4)
        sp.box(rx, ry, 0.25, 2.1, 2.2, 0.35, DARK)
        for yy in (ry + 0.2, ry + 1.7):
            sp.box(rx + 0.85, yy, 0.6, 0.3, 0.3, 2.6, YELLOW)
        sp.box(rx + 0.7, ry + 0.1, 3.2, 0.6, 2.0, 0.4, YELLOW)
        sp.cyl((rx + 1.0, ry + 1.1, 3.2), (rx + 1.0, ry + 1.1, 2.3), 0.22, SILVER, cap_mat=STEEL)
        sp.box(rx + 0.75, ry + 0.85, 0.6, 0.5, 0.5, 0.8, DARK)
        sp.box(rx + 0.82, ry + 0.95, 1.4, 0.36, 0.3, 0.9, ORANGE)
        sp.box(rx + 0.75, ry + 0.85, 2.3, 0.5, 0.5, 0.25, DARK)
        sp.lamp((rx + 1.8, ry + 2.0, 1.0), AMBER, 8)
    if v != 2:
        rig()
    # 공장동
    sp.box(x0, y0, 0.25, x1 - x0, y1 - y0, h, hall, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.25, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.8, 0.88, ORANGE)
    band_on(sp, f["right"], 0.8, 0.88, ORANGE)
    windows_row(sp, f["left"], 5, 0.58, 0.74, 0.06, 0.04)
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.2, 0.0, 0.75, 0.62), Mat("#9aa1aa", 0.35), normal=(1, 0, 0), ao=0.15)
    for k in range(1, 8):
        sp.line(add(_face_pt(f["right"], 0.2, 0.62 * k / 8), (0.02, 0, 0)),
                add(_face_pt(f["right"], 0.75, 0.62 * k / 8), (0.02, 0, 0)), 0.03, "#7d848d")
    sp.stripes(add(_face_pt(f["right"], 0.2, 0.64), (0.02, 0, 0)), mul(e1, 0.55), mul(e2, 0.08), n=8, normal=(1, 0, 0))
    sp.lamp(add(_face_pt(f["right"], 0.85, 0.7), (0.1, 0, 0)), AMBER, 9)
    sp.box(-2.6, -2.6, 0.25 + h, 1.6, 1.4, 0.5, STEEL, top=DARK)
    if v == 2:
        rig()
    # 용광로와 굴뚝
    fx, fy = ((-3.0, 2.5), (-3.0, 2.5), (-2.6, 2.6), (-3.2, 2.4), (-3.0, 2.5))[v]
    stack_h = (6.0, 6.2, 5.6, 6.0, 6.4)[v]
    sp.cyl((fx, fy, 0.25), (fx, fy, 2.4), 1.05, Mat("#6B5A4C", 0.15), bands=[0.33, 0.66], cap_mat=STEEL)
    sp.window(Sprite.cyl_patch((fx, fy, 0.25), (fx, fy, 2.4), 1.05, 0.25, 0.48, 50, 85), "#ff7b2e",
              glass=Mat("#ff7b2e", 0.3))
    sp.glow((fx + 0.5, fy + 0.8, 1.0), 20, "#ff7b2e", 0.6)
    sp.frustum((fx, fy, 2.4), (fx, fy, 2.9), 0.7, 0.4, STEEL)
    sp.cyl((fx, fy, 2.9), (fx, fy, stack_h - 0.3), 0.36, Mat("#9aa1aa", 0.3), bands=[0.3, 0.6, 0.9],
           band_color="#D9532C")
    sp.cyl((fx, fy, stack_h - 0.3), (fx, fy, stack_h), 0.45, DARK, cap_mat=CHAR)
    sp.lamp((fx, fy, stack_h + 0.12), "#ff5a3c", 6)
    pipe(sp, [(fx + 0.9, fy - 0.5, 1.6), (fx + 0.9, y1 + 0.05, 1.6)], 0.16)
    # 크레인 팔 (지브 크레인)
    mx, my = (3.9, 2.9) if v != 3 else (3.9, -2.9)
    sp.box(mx - 0.2, my - 0.2, 0.25, 0.4, 0.4, 4.6, YELLOW)
    bx = (0.2, 0.4, 0.6, 0.6, 0.2)[v]
    sp.box(bx, my - 0.15, 4.55, mx + 0.2 - bx, 0.3, 0.3, YELLOW)
    sp.line((mx, my, 3.4), (mx - 1.6, my, 4.55), 0.1, "#C9A23A")
    hx = bx + 1.2
    sp.box(hx - 0.2, my - 0.2, 4.4, 0.4, 0.4, 0.2, DARK)
    sp.line((hx, my, 4.4), (hx, my, 2.0), 0.04, "#3a3f47")
    load = (ORANGE, Mat("#C2C7CD", 0.6), ORANGE, Mat("#C9A23A"), Mat("#C2C7CD", 0.6))[v]
    sp.box(hx - 0.45, my - 0.35, 1.3, 0.9, 0.7, 0.7, load)
    sp.lamp((mx, my, 4.95), AMBER, 8)
    if v == 4:
        antenna(sp, (0.8, -3.0, 0.25 + h), 1.4)


def _cryo_tank(sp, x, y, r, h, sphere=False):
    if sphere:
        legs(sp, [(x - r * 0.6, y - r * 0.6, r + 0.4), (x + r * 0.6, y - r * 0.6, r + 0.4),
                  (x - r * 0.6, y + r * 0.6, r + 0.4), (x + r * 0.6, y + r * 0.6, r + 0.4)], 0.0)
        sp.sphere((x, y, r + 0.9), r, FROST)
        sp.ring3((x, y, r + 0.9), r, "#3E6FB0", 0.1)
        sp.ring3((x, y, r + 1.3), r * 0.92, "#b5c6cf", 0.05)
        return 2 * r + 0.9
    sp.cyl((x, y, 0), (x, y, 0.3), r * 0.85, STEEL)
    sp.cyl((x, y, 0.3), (x, y, h), r, FROST, bands=[0.2, 0.45, 0.7], band_color="#b5c6cf")
    cyl_ring(sp, (x, y, 0.3), (x, y, h), r, 0.8, 0.86, BLUE)
    sp.ellipsoid((x, y, h), r, r, r * 0.45, FROST, clip_z=h)
    sp.cyl((x, y, h + r * 0.4), (x, y, h + r * 0.4 + 0.3), 0.1, STEEL)
    sp.cyl((x + 0.25, y, h + r * 0.3), (x + 0.25, y, h + r * 0.3 + 0.25), 0.07, Mat("#3E6FB0", 0.3))
    return h + r * 0.45


@typed("cryo_lab", 9, 7, 4.6, "극저온 연구소", heights=[4.6, 4.4, 4.6, 4.8, 4.6])
def cryo_lab(sp: Sprite, v: int):
    sp.contact_shadow(0, 0, 5.0, 3.8, 0.5)
    x0, x1, y0, y1, h = -4.2, 2.8, -3.2, 0.2, 3.1
    sp.box(x0 - 0.15, y0 - 0.15, 0, x1 - x0 + 0.3, y1 - y0 + 0.3, 0.3, STEEL)
    sp.box(x0, y0, 0.3, x1 - x0, y1 - y0, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.3, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.84, 0.93, BLUE)
    band_on(sp, f["right"], 0.84, 0.93, BLUE)
    band_on(sp, f["right"], 0.76, 0.79, Mat("#9fd8ff", 0.4))
    o, e1, e2 = f["left"]
    for u in (0.04, 0.2, 0.36):
        sp.window(sp.on_face(o, e1, e2, u, 0.4, u + 0.12, 0.7), CYAN_LIGHT)
    door(sp, f["right"], 0.3, 0.62, 0.72, Mat("#cfd6dc", 0.3))
    sp.window(sp.on_face(*f["right"], 0.72, 0.4, 0.9, 0.68), CYAN_LIGHT)
    zt = 0.3 + h
    sp.box(-3.4, -2.6, zt, 1.6, 1.2, 0.55, STEEL, top=DARK)
    for cx in (-3.0, -2.2):
        sp.ring3((cx, -2.0, zt + 0.57), 0.32, "#9aa1aa", 0.05)
    # 단열 배관 (도관) — 탱크에서 실험동 벽으로
    zc = (2.1, 2.1, 1.9, 2.3, 2.1)[v]
    cond = Mat("#EEF3F6", 0.2)
    for x in (-1.0, 0.6):
        sp.line((x, 1.0, 0), (x, 1.0, zc - 0.25), 0.1, "#8a9099")
    sp.cyl((-3.9, 1.0, zc), (1.4, 1.0, zc), 0.24, cond, cap_mat=STEEL,
           bands=[0.06 + 0.08 * k for k in range(12)], band_color="#a9bfcf")
    sp.cyl((1.4, 1.0, zc), (1.4, y1, zc), 0.24, cond, cap_mat=STEEL)
    sp.cyl((1.4, 1.0, zc + 0.24), (1.4, 1.0, zc - 0.24), 0.3, Mat("#C9CCD1", 0.4))
    sp.box(1.0, y1, zc - 0.45, 0.8, 0.12, 0.9, STEEL)
    sp.polyline3([(-3.9, 1.0 + 0.25, zc), (1.4, 1.0 + 0.25, zc)], CYAN_LIGHT, 0.04, 0.5, layer="light")
    # 서리 낀 극저온 탱크
    tanks = (((-3.1, 2.15, 0.9, 3.6), (-1.1, 2.4, 0.8, 3.2)),
             ((-3.4, 2.2, 0.7, 3.2), (-1.9, 2.5, 0.65, 2.9), (-0.5, 2.3, 0.6, 2.6)),
             ((-3.0, 2.1, 0.95, 0.0), (-0.9, 2.45, 0.75, 3.1)),
             ((-3.1, 2.15, 0.9, 3.9), (-1.1, 2.4, 0.8, 3.6)),
             ((-3.1, 2.15, 0.9, 3.6), (-1.1, 2.4, 0.8, 3.2)))[v]
    for (x, y, r, hh) in sorted(tanks, key=lambda t: t[0] + t[1]):
        top = _cryo_tank(sp, x, y, r, hh, sphere=hh == 0.0)
        sp.lamp((x + r * 0.7, y + r * 0.7, 1.0), CYAN_LIGHT, 5)
    if v == 4:          # 바깥 냉동기 상자와 팬
        sp.box(1.6, 1.4, 0, 1.6, 1.4, 1.2, WHITE, top=SILVER)
        for cx in (2.0, 2.8):
            sp.ring3((cx, 2.1, 1.22), 0.3, "#9aa1aa", 0.05)
            sp.disc((cx, 2.1, 1.21), (0, 0, 1), 0.28, CHAR, edge=False)
        band_on(sp, Sprite.box_faces(1.6, 1.4, 0, 1.6, 1.4, 1.2)["left"], 0.75, 0.85, BLUE)
    elif v == 2:
        o2, e12, e22 = (1.8, 1.4, 0.3), (1.8, 0, 0), (0, 0, 1.8)
        sp.quad(o2, e12, e22, RADIATOR, back=RADIATOR)
        sp.panel_grid(o2, e12, e22, 4, 1, "#b9bec4", 0.5, 0.7)
    sp.lamp((x1 + 0.1, y1 - 0.2, 2.6), CYAN_LIGHT, 8)


# ═════════════════════════════════════════════════════════════════════
# 여가 (green_commons 계열)
# ═════════════════════════════════════════════════════════════════════

def _barrel_roof(sp, x0, x1, y0, y1, z, rise, mat, n=8, skylight=None):
    """x 방향으로 누운 낮은 원호 지붕 (띠 n장) + 양 끝 박공. skylight=(k0, k1) 띠는 유리."""
    def prof(t):
        return (y0 + (y1 - y0) * t, z + rise * (1 - (2 * t - 1) ** 2))
    strips = [(prof(i / n), prof((i + 1) / n)) for i in range(n)]
    for i, ((ya, za), (yb, zb)) in enumerate(strips):
        pts = _orient([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], (0, (ya + yb) / 2 - (y0 + y1) / 2, 1))
        if skylight and skylight[0] <= i < skylight[1]:
            sp.window(pts, WARM_WINDOW, frame="#9aa1aa", light_alpha=0.6)
        else:
            sp.face(pts, mat, ao=0)
    for x, nx in ((x0, -1), (x1, 1)):
        gable = [(x, prof(i / 16)[0], prof(i / 16)[1]) for i in range(17)]
        sp.face(_orient(gable, (nx, 0, 0)), mat, ao=0)
    return prof


@typed("gym", 10, 8, 4.2, "체육관", heights=[4.2, 4.0, 4.4, 4.2, 4.2])
def gym(sp: Sprite, v: int):
    x0, x1, y0, y1, h = -4.6, 4.2, -3.5, 3.5, 2.4
    rise = (1.45, 1.25, 1.65, 1.45, 1.45)[v]
    accent = (TEAL, ORANGE, TEAL, Mat("#3E6FB0", 0.2), YELLOW)[v]
    roofm = (Mat("#C9CCD1", 0.35), Mat("#D9D4C8", 0.1), Mat("#C9CCD1", 0.35), Mat("#BFC6CE", 0.4),
             Mat("#D9D4C8", 0.1))[v]
    sp.contact_shadow(-0.2, 0, 5.4, 4.2, 0.5)
    sp.box(x0 - 0.2, y0 - 0.3, 0, x1 - x0 + 0.4, y1 - y0 + 0.6, 0.25, CONCRETE)
    sp.box(x0, y0, 0.25, x1 - x0, y1 - y0, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.25, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.0, 0.1, accent)
    band_on(sp, f["right"], 0.0, 0.1, accent)
    # 긴 창 띠: 안에 육상 트랙과 운동 기구 그림자
    o, e1, e2 = f["left"]
    n = norm(cross(e1, e2))
    sp.window(sp.on_face(o, e1, e2, 0.04, 0.3, 0.96, 0.86), WARM_WINDOW)
    def inside(u0, v0, u1, v1, mat):
        sp.face([add(p, mul(n, 0.025)) for p in sp.on_face(o, e1, e2, u0, v0, u1, v1)], mat, normal=n, edge=False, ao=0)
    inside(0.05, 0.31, 0.95, 0.43, TRACK)
    for vv in (0.35, 0.39):
        sp.line(add(_face_pt(f["left"], 0.05, vv), mul(n, 0.03)), add(_face_pt(f["left"], 0.95, vv), mul(n, 0.03)),
                0.025, "#f1f2f0", 0.9)
    for u in ((0.12, 0.3, 0.55, 0.72, 0.86), (0.18, 0.4, 0.66, 0.84), (0.12, 0.3, 0.55, 0.72, 0.86),
              (0.1, 0.34, 0.6, 0.8), (0.15, 0.38, 0.62, 0.86))[v]:
        k = int(u * 10) % 3
        if k == 0:      # 달리기 기계
            inside(u, 0.44, u + 0.06, 0.5, Mat("#2e3238"))
            inside(u + 0.045, 0.5, u + 0.06, 0.66, Mat("#2e3238"))
        elif k == 1:    # 자전거
            inside(u, 0.44, u + 0.015, 0.6, Mat("#2e3238"))
            inside(u - 0.02, 0.58, u + 0.04, 0.62, Mat("#2e3238"))
            inside(u - 0.02, 0.44, u + 0.05, 0.48, Mat("#2e3238"))
        else:           # 역기
            inside(u, 0.52, u + 0.07, 0.54, Mat("#2e3238"))
            inside(u, 0.47, u + 0.012, 0.59, Mat("#2e3238"))
            inside(u + 0.058, 0.47, u + 0.07, 0.59, Mat("#2e3238"))
    for k in range(1, 8):
        sp.line(add(_face_pt(f["left"], k / 8, 0.3), mul(n, 0.04)), add(_face_pt(f["left"], k / 8, 0.86), mul(n, 0.04)),
                0.04, "#9aa1aa")
    # 박공 끝 (+x): 출입문과 창
    door(sp, f["right"], 0.4, 0.6, 0.78, Mat("#cfd6dc", 0.3))
    windows_row(sp, f["right"], 2, 0.4, 0.78, 0.1, 0.5)
    # 둥근 지붕 (등마루에 채광 띠)
    _barrel_roof(sp, x0 - 0.15, x1 + 0.15, y0 - 0.2, y1 + 0.2, 0.25 + h, rise, roofm, 8,
                 skylight=(3, 5) if v in (0, 2, 4) else None)
    if v == 1:
        for x in (-3.0, 0.0):
            sp.box(x, -1.0, 0.25 + h + rise - 0.05, 1.0, 0.8, 0.35, STEEL, top=DARK)
    elif v == 3:
        antenna(sp, (-3.6, 0.0, 0.25 + h + rise * 0.9), 1.2)
    sp.lamp((x1 + 0.15, 0.0, 2.35), AMBER, 9)
    sp.lamp((x1 + 0.15, y1 - 0.3, 1.0), CYAN_LIGHT if accent is TEAL else AMBER, 7)


def _fan_ring(sp, apex, r0, r1, a0, a1, z0, z1, wall, roof, k=10):
    """부채꼴 고리 기둥 (apex 중심, 반지름 r0~r1, 각 a0~a1 도)."""
    def at(r, t, z):
        return (apex[0] + r * math.cos(math.radians(t)), apex[1] + r * math.sin(math.radians(t)), z)
    ts = [a0 + (a1 - a0) * i / k for i in range(k + 1)]
    # 옆벽 (보이는 쪽만 그려진다)과 바깥 호 벽
    for t, sgn in ((a0, -1), (a1, 1)):
        sp.face(_orient([at(r0, t, z0), at(r1, t, z0), at(r1, t, z1), at(r0, t, z1)],
                        (-math.sin(math.radians(t)) * sgn, math.cos(math.radians(t)) * sgn, 0)), wall)
    for i in range(k):
        tm = math.radians((ts[i] + ts[i + 1]) / 2)
        sp.face(_orient([at(r1, ts[i], z0), at(r1, ts[i + 1], z0), at(r1, ts[i + 1], z1), at(r1, ts[i], z1)],
                        (math.cos(tm), math.sin(tm), 0)), wall)
        sp.face(_orient([at(r0, ts[i], z0), at(r0, ts[i + 1], z0), at(r0, ts[i + 1], z1), at(r0, ts[i], z1)],
                        (-math.cos(tm), -math.sin(tm), 0)), wall)
    top = [at(r1, t, z1) for t in ts] + [at(r0, t, z1) for t in reversed(ts)]
    sp.face(_orient(top, (0, 0, 1)), roof, normal=(0, 0, 1))
    return at


@typed("theater", 12, 10, 5.0, "공연장", heights=[5.0, 5.0, 5.4, 4.6, 5.0])
def theater(sp: Sprite, v: int):
    apex = (-8.0, 0.0)
    half = 23.0
    wall = (CREAM, WHITE, CREAM, Mat("#D8CBB0"), WHITE)[v]
    roof = (Mat("#9aa1aa", 0.3), Mat("#8E3B3B", 0.15), Mat("#9aa1aa", 0.3), Mat("#7d848d", 0.3), Mat("#3E6FB0", 0.2))[v]
    accent = (MAROON, MAROON, Mat("#3E6FB0", 0.2), MAROON, ORANGE)[v]
    steps = ((3.8, 5.6, 4.3), (5.6, 8.6, 3.5), (8.6, 12.4, 2.5))
    if v == 3:
        steps = ((3.8, 6.6, 3.9), (6.6, 12.4, 2.6))
    tower_h = (5.0, 5.0, 5.4, 4.6, 5.0)[v]
    sp.contact_shadow(-0.4, 0, 6.4, 5.0, 0.5)
    # 무대탑 (뒤)
    sp.box(-6.0, -1.7, 0, 2.1, 3.4, tower_h, wall, top=SILVER)
    band_on(sp, Sprite.box_faces(-6.0, -1.7, 0, 2.1, 3.4, tower_h)["left"], 0.9, 0.97, accent)
    for r0, r1, hh in steps:
        _fan_ring(sp, apex, r0, r1, -half, half, 0.0, hh, wall, roof)
    # 앞면: 유리문, 포스터, 차양(마키)과 전구 줄
    r1 = steps[-1][1]

    def P_(r, t, z):
        return (apex[0] + r * math.cos(math.radians(t)), apex[1] + r * math.sin(math.radians(t)), z)
    hh = steps[-1][2]
    for t0, t1 in ((-8, -3), (-2.5, 2.5), (3, 8)):
        sp.window(_orient([P_(r1 + 0.03, t0, 0.05), P_(r1 + 0.03, t1, 0.05), P_(r1 + 0.03, t1, 1.55),
                           P_(r1 + 0.03, t0, 1.55)], (1, 0, 0)), WARM_WINDOW)
    for t0, t1, c in ((-19, -12, RED), (12, 19, YELLOW)):
        q = _orient([P_(r1 + 0.03, t0, 0.5), P_(r1 + 0.03, t1, 0.5), P_(r1 + 0.03, t1, 1.9), P_(r1 + 0.03, t0, 1.9)],
                    (1, 0, 0))
        sp.face(q, c, ao=0, edge=False)
        sp.light_poly(q, WARM_WINDOW, 0.35)
    for i in range(10):
        t0 = -half + 2 * half * i / 10
        t1 = t0 + 2 * half / 10
        sp.face(_orient([P_(r1 + 0.02, t0, hh - 0.35), P_(r1 + 0.02, t1, hh - 0.35), P_(r1 + 0.02, t1, hh - 0.1),
                         P_(r1 + 0.02, t0, hh - 0.1)], (math.cos(math.radians((t0 + t1) / 2)), 0.1, 0)), accent,
                ao=0, edge=False)
    zm = 2.05
    ta, tb = -15.0, 15.0
    k = 8
    can = [P_(r1, ta + (tb - ta) * i / k, zm) for i in range(k + 1)] + \
          [P_(r1 + 0.95, tb - (tb - ta) * i / k, zm) for i in range(k + 1)]
    sp.face(_orient(can, (0, 0, 1)), Mat("#2e3238", 0.2), normal=(0, 0, 1))
    for i in range(k):
        a, b = ta + (tb - ta) * i / k, ta + (tb - ta) * (i + 1) / k
        q = _orient([P_(r1 + 0.95, a, zm - 0.32), P_(r1 + 0.95, b, zm - 0.32), P_(r1 + 0.95, b, zm),
                     P_(r1 + 0.95, a, zm)], (math.cos(math.radians((a + b) / 2)), math.sin(math.radians((a + b) / 2)), 0))
        sp.face(q, Mat("#F2C14E", 0.4), ao=0, edge=False)
        sp.mark_light("#FFE08A", 0.9)
        sp.light_poly(q, "#FFE08A", 0.9)
    for i in range(k * 2 + 1):
        t = ta + (tb - ta) * i / (k * 2)
        sp.lamp(P_(r1 + 0.97, t, zm - 0.16), "#FFE9B0", 4)
    for t in (ta + 1, tb - 1):
        sp.line(P_(r1 + 0.85, t, 0), P_(r1 + 0.85, t, zm - 0.32), 0.07, "#8a9099")
    sp.glow(P_(r1 + 1.0, 0, 1.0), 40, WARM_WINDOW, 0.4)
    if v == 2:
        antenna(sp, (-5.0, 0.0, tower_h), 1.0)
    elif v == 4:
        sp.box(-5.6, -1.2, tower_h, 1.2, 1.2, 0.4, STEEL, top=DARK)


def _cafe_table(sp, c, umbrella=None, seats=3):
    for k in range(seats):
        a = math.radians(200 + 360 * k / seats)
        p = (c[0] + 0.62 * math.cos(a), c[1] + 0.62 * math.sin(a), 0.0)
        if dot((math.cos(a), math.sin(a), 0), VIEW) < 0:
            sp.cyl(p, add(p, (0, 0, 0.42)), 0.16, Mat("#8a5a3c", 0.2), cap_mat=Mat("#a8714c", 0.2))
    sp.cyl((c[0], c[1], 0), (c[0], c[1], 0.7), 0.05, STEEL)
    sp.cyl((c[0], c[1], 0.7), (c[0], c[1], 0.76), 0.42, WHITE, cap_mat=WHITE)
    for k in range(seats):
        a = math.radians(200 + 360 * k / seats)
        p = (c[0] + 0.62 * math.cos(a), c[1] + 0.62 * math.sin(a), 0.0)
        if dot((math.cos(a), math.sin(a), 0), VIEW) >= 0:
            sp.cyl(p, add(p, (0, 0, 0.42)), 0.16, Mat("#8a5a3c", 0.2), cap_mat=Mat("#a8714c", 0.2))
    if umbrella:
        sp.line((c[0], c[1], 0.76), (c[0], c[1], 2.2), 0.05, "#c9ccd1")
        sp.dome((c[0], c[1], 1.85), 0.95, 0.38, umbrella)


@typed("cafe", 7, 7, 3.4, "카페", heights=[3.4, 3.4, 3.6, 3.2, 3.4])
def cafe(sp: Sprite, v: int):
    cx, cy, r = -0.8, -0.8, 1.85
    roofm = (Mat("#B5583A", 0.15), TEAL, Mat("#3E6FB0", 0.2), MAROON, Mat("#C9A23A", 0.2))[v]
    stripes = ((RED, WHITE), (TEAL, WHITE), (BLUE, WHITE), (MAROON, CREAM), (ORANGE, WHITE))[v]
    umb = (RED, TEAL, BLUE, None, ORANGE)[v]
    zb, zt = 0.2, (2.45, 2.45, 2.65, 2.3, 2.45)[v]
    sp.contact_shadow(0, 0, 3.6, 3.6, 0.45)
    sp.disc((0.15, 0.15, 0.02), (0, 0, 1), 3.25, Mat("#9b927f"), edge=False)
    sp.ring3((0.15, 0.15, 0.03), 3.25, "#7d7566", 0.08, front_only=False)

    ri, ro, zi, zo = r + 0.03, r + 0.85, zt - 0.2, zt - 0.6
    def awning(front):
        n = 24
        for k in range(n):
            t0, t1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
            tm = (t0 + t1) / 2
            if (dot((math.cos(tm), math.sin(tm), 0), VIEW) > -0.1) != front:
                continue
            def at(rr, t, z):
                return (cx + rr * math.cos(t), cy + rr * math.sin(t), z)
            q = _orient([at(ri, t0, zi), at(ri, t1, zi), at(ro, t1, zo), at(ro, t0, zo)],
                        (math.cos(tm) * 0.45, math.sin(tm) * 0.45, 1.0))
            sp.face(q, stripes[k % 2], ao=0)
            if front:
                sp.face(_orient([at(ro, t0, zo), at(ro, t1, zo), at(ro, t1, zo - 0.22), at(ro, t0, zo - 0.22)],
                                (math.cos(tm), math.sin(tm), 0)), stripes[k % 2], ao=0, edge=False)
    awning(False)
    sp.cyl((cx, cy, 0), (cx, cy, zb), r + 0.2, CONCRETE)
    p0, p1 = (cx, cy, zb), (cx, cy, zt)
    sp.cyl(p0, p1, r, CREAM, cap_mat=WHITE)
    cyl_windows(sp, p0, p1, r, 0.22, 0.72, toward=(1, 1, 0), n=4, spread=36, width=27)
    sp.dome((cx, cy, zt), r + 0.12, 0.75, roofm)
    sp.sphere((cx, cy, zt + 0.82), 0.18, GOLD)
    sp.lamp((cx, cy, zt + 1.05), WARM_WINDOW, 8)
    awning(True)
    sp.glow((cx + 1.0, cy + 1.0, 1.2), 30, WARM_WINDOW, 0.4)
    tables = (((1.6, 0.9), (0.5, 2.3), (2.4, -1.4), (-2.0, 2.1)), ((1.8, 1.4), (-0.2, 2.4), (2.4, -0.9)),
              ((1.6, 0.9), (0.5, 2.3), (2.4, -1.4)), ((1.7, 1.0), (0.3, 2.4), (2.5, -1.2), (-2.1, 2.0)),
              ((1.9, 1.2), (0.0, 2.4), (2.5, -1.1)))[v]
    lamps = (((2.9, 2.6), (-2.6, 0.6)), ((2.9, 2.9),), ((2.9, 2.6), (-2.6, 0.6), (2.9, -2.6)), ((2.9, 2.6),),
             ((2.8, 2.8), (-2.7, 0.8)))[v]
    items = [((x, y, 0), (lambda x=x, y=y, i=i: _cafe_table(sp, (x, y), umb if (i + v) % 2 == 0 else None)))
             for i, (x, y) in enumerate(tables)]
    for (x, y) in lamps:
        def lp(x=x, y=y):
            sp.line((x, y, 0), (x, y, 2.5), 0.06, "#5c626b")
            sp.lamp((x, y, 2.6), WARM_WINDOW, 12)
        items.append(((x, y, 0), lp))
    sp.parts(items)


@typed("sports_dome", 20, 16, 7.0, "저중력 스포츠 돔", heights=[7.0, 6.6, 7.4, 7.0, 7.0])
def sports_dome(sp: Sprite, v: int):
    rx, ry, H = ((9.3, 7.3, 6.1), (9.3, 7.3, 5.7), (9.4, 7.4, 6.5), (9.3, 7.3, 6.1), (9.3, 7.3, 6.1))[v]
    zb = 0.8
    sp.contact_shadow(0, 0, 10.0, 8.0, 0.45)
    ell = [(rx * math.cos(2 * math.pi * k / 48), ry * math.sin(2 * math.pi * k / 48)) for k in range(48)]
    sp.prism(ell, 0, zb, SINTER, top=Mat("#6a6458"))
    # 트랙과 경기장
    if v in (0, 2, 4):
        sp.face([(rx * 0.86 * math.cos(2 * math.pi * k / 40), ry * 0.84 * math.sin(2 * math.pi * k / 40), zb + 0.01)
                 for k in range(40)], TRACK, normal=(0, 0, 1), ao=0, edge=False)
    fx, fy = 6.0, 3.4
    turf = (TURF, TURF, TURF, Mat("#3E7FB8", 0.4), Mat("#C9A066"))[v]
    sp.face([(-fx, -fy, zb + 0.02), (fx, -fy, zb + 0.02), (fx, fy, zb + 0.02), (-fx, fy, zb + 0.02)], turf,
            normal=(0, 0, 1), ao=0, edge=False)
    lc, lw, z = "#f1f2f0", 0.08, zb + 0.03
    sp.polyline3([(-fx + 0.3, -fy + 0.3, z), (fx - 0.3, -fy + 0.3, z), (fx - 0.3, fy - 0.3, z), (-fx + 0.3, fy - 0.3, z)],
                 lc, lw, closed=True)
    sp.line((0, -fy + 0.3, z), (0, fy - 0.3, z), lw, lc)
    sp.ring3((0, 0, z), 1.3, lc, lw, front_only=False)
    for s in (-1, 1):
        x = s * (fx - 0.3)
        sp.polyline3([(x, -1.6, z), (x - s * 1.4, -1.6, z), (x - s * 1.4, 1.6, z), (x, 1.6, z)], lc, lw)
    # 골대 (또는 높은 고리)
    for s in (-1, 1):
        x = s * (fx - 0.3)
        if v in (1, 3):
            sp.line((x + s * 0.4, 0, zb), (x + s * 0.4, 0, zb + 3.2), 0.1, "#c9ccd1")
            sp.ring3((x, 0, zb + 3.1), 0.45, "#E07B39", 0.08, front_only=False)
            sp.quad((x + s * 0.4, -0.5, zb + 3.0), (0, 1.0, 0), (0, 0, 0.8), WHITE, back=WHITE)
        else:
            for y in (-1.0, 1.0):
                sp.line((x, y, zb), (x, y, zb + 1.3), 0.08, lc)
                sp.line((x, y, zb + 1.3), (x + s * 0.6, y, zb), 0.04, "#b9bcc0")
            sp.line((x, -1.0, zb + 1.3), (x, 1.0, zb + 1.3), 0.08, lc)
            sp.line((x + s * 0.6, -1.0, zb), (x + s * 0.6, 1.0, zb), 0.04, "#b9bcc0")
    # 조명탑 넷
    for (x, y) in ((-5.6, -4.0), (5.6, -4.0), (-5.6, 4.0), (5.6, 4.0)):
        sp.line((x, y, zb), (x, y, zb + 3.2), 0.1, "#8a9099")
        sp.box(x - 0.35, y - 0.12, zb + 3.2, 0.7, 0.24, 0.25, DARK)
        sp.lamp((x, y, zb + 3.45), "#fff4d6", 14)
    sp.glow((0, 0, zb + 2.0), 90, "#fff4d6", 0.3)
    # 투명 돔
    _glass_cap(sp, (0, 0), rx, ry, H, zb, rings=(0.28, 0.55, 0.8), ribs=16, alpha=0.26)
    # 출입 에어록 (+x)
    sp.box(8.6, -1.1, 0, 1.2, 2.2, 2.3, CONCRETE, top=Mat("#b3a48e"))
    f = Sprite.box_faces(8.6, -1.1, 0, 1.2, 2.2, 2.3)
    door(sp, f["right"], 0.25, 0.75, 0.75, Mat("#5c626b", 0.3))
    if v == 4:
        for (x, y) in ((8.6, 6.4), (-8.6, 6.4), (8.6, -6.4)):
            sp.line((x, y, 0), (x, y, 2.8), 0.08, "#8a9099")
            sp.lamp((x, y, 2.9), AMBER, 11)
    elif v == 2:
        sp.box(-2.0, 7.0, 0, 4.0, 0.9, 1.6, WHITE, top=SILVER)
        windows_row(sp, Sprite.box_faces(-2.0, 7.0, 0, 4.0, 0.9, 1.6)["left"], 3, 0.4, 0.75, 0.1, 0.08)


# ═════════════════════════════════════════════════════════════════════
# 교신 (comms_center 계열)
# ═════════════════════════════════════════════════════════════════════

@typed("laser_terminal", 6, 6, 5.0, "레이저 통신소", heights=[5.0, 4.8, 5.2, 5.0, 4.8])
def laser_terminal(sp: Sprite, v: int):
    tx, ty = (-0.5, -0.6)
    el = math.radians((55, 40, 65, 55, 48)[v])
    d = (0.0, math.cos(el), math.sin(el))
    tube = (WHITE, WHITE, Mat("#D8DDE2", 0.2), WHITE, Mat("#E5DCC8", 0.05))[v]
    sp.contact_shadow(0, 0, 3.2, 3.2, 0.5)
    sp.box(-2.85, -2.85, 0, 5.7, 5.7, 0.25, SINTER, top=Mat("#a39581"))
    sp.ring3((tx, ty, 0.26), 1.6, "#E9C24A", 0.08, front_only=False)
    # 받침대와 방위 회전 북
    sp.cyl((tx, ty, 0.25), (tx, ty, 1.85), 0.72, WHITE, bands=[0.5], band_color="#bdb6a8", cap_mat=STEEL)
    sp.cyl((tx, ty, 1.85), (tx, ty, 2.3), 1.0, Mat("#5b6470", 0.3), cap_mat=Mat("#7A8490", 0.3))
    c = (tx, ty, 3.2)
    arm = Mat("#C9CCD1", 0.35)
    sp.box(tx - 1.02, ty - 0.32, 2.3, 0.24, 0.64, 1.15, arm)
    sp.disc((tx - 0.78, ty, c[2]), (1, 0, 0), 0.3, DARK)
    # 망원경 같은 광학 머리 (위를 본다)
    b0, b1 = sub(c, mul(d, 0.85)), add(c, mul(d, 1.45))
    sp.cyl(b0, b1, 0.62, tube, bands=[0.25, 0.7], band_color="#a8a294", cap_mat=STEEL)
    b2 = add(b1, mul(d, 0.38))
    sp.frustum(b1, b2, 0.64, 0.74, Mat("#3a3f47", 0.3), caps=False)
    sp.disc(add(b1, mul(d, 0.05)), d, 0.55, Mat("#1d3a4a", 0.9), edge=False)
    sp.ring3(add(b1, mul(d, 0.06)), 0.5, "#D2A43C", 0.07, normal=d, front_only=False)
    sp.disc(add(b1, mul(d, 0.07)), d, 0.16, Mat("#7FE3DA", 0.9), edge=False)
    sp.glow(add(b2, mul(d, 0.2)), 12, "#7CF29A", 0.75)
    sp.line(add(b2, mul(d, 0.1)), add(b2, mul(d, 1.6)), 0.05, "#7CF29A", 0.55, layer="light")
    sp.box(tx + 0.78, ty - 0.32, 2.3, 0.24, 0.64, 1.15, arm)
    sp.disc((tx + 1.03, ty, c[2]), (1, 0, 0), 0.3, DARK)
    sp.disc((tx + 1.04, ty, c[2]), (1, 0, 0), 0.12, GOLD)
    # 냉각 상자 (방열 지느러미, 팬)
    bx, by = (-2.55, 0.9) if v not in (3,) else (0.9, 0.9)
    sp.box(bx, by, 0.25, 1.7, 1.5, 1.15, WHITE, top=SILVER)
    cf = Sprite.box_faces(bx, by, 0.25, 1.7, 1.5, 1.15)
    o, e1, e2 = cf["left"]
    for k in range(6):
        u = 0.1 + k * 0.14
        _decal(sp, cf["left"], u, 0.15, u + 0.07, 0.8, DARK, 0.01)
    band_on(sp, cf["right"], 0.8, 0.9, Mat("#3E6FB0", 0.2))
    sp.ring3((bx + 0.85, by + 0.75, 1.42), 0.45, "#9aa1aa", 0.05)
    sp.disc((bx + 0.85, by + 0.75, 1.41), (0, 0, 1), 0.42, CHAR, edge=False)
    pipe(sp, [(bx + 1.7, by + 0.4, 0.6), (tx - 0.2, by + 0.4, 0.6), (tx - 0.2, ty + 0.7, 0.6)], 0.14)
    sp.lamp((bx + 1.7, by + 1.5, 1.2), CYAN_LIGHT, 6)
    if v == 1:
        sp.box(1.2, -2.5, 0.25, 1.2, 1.0, 1.4, Mat("#5b6470", 0.2), top=SILVER)
        sp.lamp((2.45, -2.0, 1.2), AMBER, 7)
    elif v == 2:
        antenna(sp, (2.3, -2.3, 0.25), 2.6)
    elif v == 4:
        o2, e12, e22 = (0.6, 1.2, 0.5), (1.9, 0, 0), (0, 1.3, 0.5)
        sp.quad(o2, e12, e22, SOLAR, back=STEEL)
        sp.panel_grid(o2, e12, e22, 3, 2, "#6f86b0", 0.45, 0.6)
        legs(sp, [(0.8, 1.4, 0.55), (2.3, 1.4, 0.55)], 0.25)


@typed("lunar_observatory", 8, 8, 7.0, "광학 천문대", heights=[7.0, 6.6, 7.2, 6.8, 7.0])
def lunar_observatory(sp: Sprite, v: int):
    cx, cy = -0.8, -0.8
    R = (2.7, 2.5, 2.8, 2.6, 2.7)[v]
    zt = (3.7, 3.4, 3.9, 3.6, 3.7)[v]
    Rd = R + 0.08
    th = math.radians((45, 70, 40, 55, 45)[v])
    sp.contact_shadow(0.2, 0.2, 4.0, 4.0, 0.5)
    sp.cyl((cx, cy, 0), (cx, cy, 0.3), R + 0.4, CONCRETE)
    # 제어실 (+x 쪽, 뒤)
    def annex():
        sp.box(1.3, -3.6, 0, 2.4, 2.6, 2.4, WHITE, top=SILVER)
        f = Sprite.box_faces(1.3, -3.6, 0, 2.4, 2.6, 2.4)
        band_on(sp, f["left"], 0.82, 0.92, Mat("#F2A541"))
        band_on(sp, f["right"], 0.82, 0.92, Mat("#F2A541"))
        windows_row(sp, f["left"], 2, 0.4, 0.68, 0.15, 0.1)
        door(sp, f["right"], 0.3, 0.7, 0.75)
        sp.box(1.0, -2.8, 0.3, 0.5, 1.2, 2.0, WHITE)
        if v in (1, 3):
            antenna(sp, (3.2, -3.2, 2.4), 1.4)
    if v != 4:
        annex()
    p0, p1 = (cx, cy, 0.3), (cx, cy, zt)
    sp.cyl(p0, p1, R, WHITE, bands=[0.94], band_color="#b9b2a5", cap_mat=SILVER)
    cyl_windows(sp, p0, p1, R, 0.5, 0.6, toward=(1, 1, 0), n=2, spread=30, width=8)
    ang = Sprite.facing_angle(p0, p1, (0.2, 1.0, 0))
    sp.face(Sprite.cyl_patch(p0, p1, R, 0.0, 0.62, ang - 9, ang + 9), Mat("#9aa1aa", 0.3), ao=0)
    sp.lamp(add((cx, cy, 2.55), mul(norm((0.2, 1.0, 0)), R + 0.15)), AMBER, 8)
    # 슬릿 돔 (슬릿이 열려 있다)
    sp.sphere((cx, cy, zt), Rd, Mat("#F1F2F0", 0.3), clip_z=zt)
    h = (math.cos(th), math.sin(th), 0.0)
    side = (-math.sin(th), math.cos(th), 0.0)
    al = math.asin(0.48 / Rd)
    def on(phi, s):
        m = add(mul(h, math.cos(phi)), (0, 0, math.sin(phi)))
        q = add(mul(m, math.cos(al)), mul(side, s * math.sin(al)))
        return (cx + Rd * 1.005 * q[0], cy + Rd * 1.005 * q[1], zt + Rd * 1.005 * q[2])
    phis = [math.radians(4 + (100 - 4) * k / 12) for k in range(13)]
    for a, b in zip(phis, phis[1:]):
        nm = add(mul(h, math.cos((a + b) / 2)), (0, 0, math.sin((a + b) / 2)))
        sp.face(_orient([on(a, -1), on(a, 1), on(b, 1), on(b, -1)], nm), Mat("#1b1e24"), ao=0, edge=False)
    for s in (-1, 1):
        sp.polyline3([on(p, s * 1.25) for p in phis], "#b9bcc0", 0.08)
    q = add(mul(h, math.cos(math.radians(38))), (0, 0, math.sin(math.radians(38))))
    tc = (cx + Rd * 0.8 * q[0], cy + Rd * 0.8 * q[1], zt + Rd * 0.8 * q[2])
    sp.disc(tc, q, 0.36, Mat("#E9E6DF", 0.3))
    sp.disc(add(tc, mul(q, 0.02)), q, 0.24, Mat("#1d3a4a", 0.9), edge=False)
    sp.light_poly(_orient([on(phis[1], -1), on(phis[1], 1), on(phis[7], 1), on(phis[7], -1)], q), "#ff4a3a", 0.3)
    if v == 4:
        annex()
    sp.lamp((cx, cy, zt + Rd + 0.15), "#ff5a3c", 6)
    if v == 2:
        sp.line((cx + 2.8, cy + 2.8, 0), (cx + 2.8, cy + 2.8, 2.6), 0.07, "#8a9099")
        sp.lamp((cx + 2.8, cy + 2.8, 2.7), "#ff5a3c", 8)


@typed("broadcast_studio", 8, 6, 4.6, "방송 스튜디오", heights=[4.6, 4.4, 4.8, 4.6, 4.6])
def broadcast_studio(sp: Sprite, v: int):
    x0, x1, y0, y1, h = -3.75, 2.7, -2.7, 2.0, (3.0, 2.8, 3.2, 3.0, 3.0)[v]
    body = (WHITE, Mat("#4A4F57", 0.2), WHITE, Mat("#D8DDE2", 0.1), WHITE)[v]
    sp.contact_shadow(-0.3, -0.2, 4.4, 3.2, 0.5)
    sp.box(x0 - 0.15, y0 - 0.15, 0, x1 - x0 + 0.3, y1 - y0 + 0.3, 0.3, STEEL)
    sp.box(x0, y0, 0.3, x1 - x0, y1 - y0, h, body, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.3, x1 - x0, y1 - y0, h)
    band_on(sp, f["right"], 0.9, 0.97, RED)
    # 바깥을 보는 큰 화면 벽
    o, e1, e2 = f["left"]
    n = (0.0, 1.0, 0.0)
    _decal(sp, f["left"], 0.03, 0.1, 0.97, 0.97, Mat("#22262c", 0.3), 0.02)
    scr = _decal(sp, f["left"], 0.05, 0.14, 0.95, 0.93, Mat("#1b3560", 0.5), 0.04)
    sp.light_poly(scr, "#2a5aa0", 0.75)
    W = length(e1)
    Hh = length(e2)
    def at(u, vv, lift=0.06):
        return add(_face_pt(f["left"], u, vv), mul(n, lift))
    eu, ev = ((0.72, 0.56), (0.7, 0.56), (0.74, 0.58), (0.28, 0.56), (0.72, 0.56))[v]
    ec = at(eu, ev)
    er = 0.27 * Hh
    sp.face(_circle(ec, n, er, 20), Mat("#2f6db5", 0.4), normal=n, edge=False, ao=0)
    sp.light_poly(_circle(add(ec, (0, 0.01, 0)), n, er, 20), "#4f8fe0", 0.85)
    for (du, dv, rr) in ((-0.25, 0.2, 0.42), (0.2, -0.25, 0.32), (0.3, 0.35, 0.22)):
        cc = add(ec, (-du * er, 0.015, dv * er))
        sp.face(_circle(cc, n, er * rr, 10), Mat("#5aa04f", 0.3), normal=n, edge=False, ao=0)
        sp.light_poly(_circle(add(cc, (0, 0.01, 0)), n, er * rr, 10), "#7fd06a", 0.8)
    bu0, bu1 = (0.08, 0.6) if eu > 0.5 else (0.45, 0.93)
    ban = [at(bu0, 0.2, 0.07), at(bu1, 0.2, 0.07), at(bu1, 0.36, 0.07), at(bu0, 0.36, 0.07)]
    sp.face(_orient(ban, n), Mat("#E07B39", 0.3), normal=n, edge=False, ao=0)
    sp.light_poly(ban, "#ffa060", 0.9)
    for vv in (0.25, 0.31):
        sp.line(at(bu0 + 0.04, vv, 0.08), at(bu0 + (bu1 - bu0) * 0.7, vv, 0.08), 0.06, "#f8f4ea", 0.9)
    lg = [at(0.08 if eu > 0.5 else 0.86, 0.8, 0.07), at(0.14 if eu > 0.5 else 0.92, 0.8, 0.07),
          at(0.14 if eu > 0.5 else 0.92, 0.9, 0.07), at(0.08 if eu > 0.5 else 0.86, 0.9, 0.07)]
    sp.face(_orient(lg, n), RED, normal=n, edge=False, ao=0)
    sp.light_poly(lg, "#ff6a5a", 0.9)
    sp.glow(at(0.5, 0.55, 0.5), 40, "#4f8fe0", 0.3)
    # 문과 붉은 방송 중 등
    door(sp, f["right"], 0.35, 0.68, 0.7, Mat("#5c626b", 0.3), light=False)
    oa = _face_pt(f["right"], 0.515, 0.82)
    sp.box(oa[0], oa[1] - 0.45, oa[2], 0.12, 0.9, 0.32, DARK)
    sign = _orient([(oa[0] + 0.13, oa[1] - 0.4, oa[2] + 0.04), (oa[0] + 0.13, oa[1] + 0.4, oa[2] + 0.04),
                    (oa[0] + 0.13, oa[1] + 0.4, oa[2] + 0.28), (oa[0] + 0.13, oa[1] - 0.4, oa[2] + 0.28)], (1, 0, 0))
    sp.face(sign, Mat("#D9332C", 0.4), ao=0, edge=False)
    sp.mark_light(RED_LIGHT, 0.95)
    sp.light_poly(sign, RED_LIGHT, 0.95)
    sp.glow((oa[0] + 0.3, oa[1], oa[2] + 0.16), 14, RED_LIGHT, 0.8)
    # 지붕: 작은 접시와 기둥
    zt = 0.3 + h
    sp.box(-2.9, -2.0, zt, 0.8, 0.8, 0.3, STEEL, top=DARK)
    _dish(sp, (-2.4, -1.5, zt + 0.95), norm((0.3, 0.8, 0.6)), (0.8, 0.7, 0.95, 0.8, 0.75)[v])
    sp.line((-2.5, -1.6, zt + 0.3), (-2.4, -1.5, zt + 0.7), 0.1, "#9aa1aa")
    if v != 1:
        antenna(sp, (1.6, -1.8, zt), 1.4)
    if v == 3:
        sp.box(0.0, -2.2, zt, 1.4, 1.0, 0.45, STEEL, top=DARK)
    elif v == 4:
        for x in (-1.0, 0.2):
            sp.lamp((x, y1 + 0.1, zt + 0.15), "#fff1c9", 7)


@typed("data_archive", 7, 5, 4.0, "기록 보관소", heights=[4.0, 3.8, 4.3, 4.0, 3.7])
def data_archive(sp: Sprite, v: int):
    zb = (2.0, 2.2, 1.8, 2.0, 2.0)[v]
    top = (4.0, 3.8, 4.3, 4.0, 3.7)[v]
    mx0, mx1, my0, my1 = ((-2.0, 1.6, -1.05, 1.05), (-2.0, 1.6, -1.05, 1.05), (-1.8, 1.4, -1.0, 1.0),
                          (-2.2, 1.8, -0.95, 0.95), (-2.0, 1.6, -1.05, 1.05))[v]
    sp.contact_shadow(0, 0, 3.9, 2.9, 0.5)
    # 흙 둑: 바깥 네모(바닥)에서 덩어리를 감싼 안쪽 네모(높이 zb)로 비탈
    ox0, ox1, oy0, oy1 = -3.45, 3.3, -2.45, 2.45
    ix0, ix1, iy0, iy1 = mx0 - 0.25, mx1 + 0.25, my0 - 0.25, my1 + 0.25
    b = [(ox0, oy0, 0), (ox1, oy0, 0), (ox1, oy1, 0), (ox0, oy1, 0)]
    t = [(ix0, iy0, zb), (ix1, iy0, zb), (ix1, iy1, zb), (ix0, iy1, zb)]
    for i in range(4):
        sp.face([b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]], BERM, ao=0)
    sp.face(t, Mat("#6e6862"), normal=(0, 0, 1))
    for k in (0.33, 0.66):
        lerp = [add(mul(b[i], 1 - k), mul(t[i], k)) for i in range(4)]
        sp.polyline3([lerp[3], lerp[2], lerp[1]], "#5f5953", 0.06, 0.7)
    sp.rock((-2.9, 2.0, 0), 0.35)
    sp.rock((2.6, -2.1, 0), 0.3)
    # 검은 덩어리 (아래 절반은 둑 속)
    z0 = zb - 0.1
    sp.box(mx0, my0, z0, mx1 - mx0, my1 - my0, top - z0, MONO, top=Mat("#3a3f47", 0.3))
    f = Sprite.box_faces(mx0, my0, z0, mx1 - mx0, my1 - my0, top - z0)
    groove = "#17191d"
    sp.panel_grid(*f["left"], 6, 2, groove, 0.7, 0.9)
    sp.panel_grid(*f["right"], 3, 2, groove, 0.7, 0.9)
    sp.panel_grid(*f["top"], 6, 3, groove, 0.6, 0.8)
    glyph = Mat("#4d5560", 0.3)
    for (u, vv) in ((0.06, 0.12), (0.4, 0.12), (0.73, 0.12), (0.23, 0.12), (0.56, 0.12))[: 3 + v % 3]:
        _decal(sp, f["left"], u, vv, u + 0.1, vv + 0.3, glyph, 0.01)
        _decal(sp, f["left"], u + 0.025, vv + 0.08, u + 0.075, vv + 0.12, Mat("#22262c"), 0.015)
        _decal(sp, f["left"], u + 0.025, vv + 0.18, u + 0.075, vv + 0.22, Mat("#22262c"), 0.015)
    # 빛나는 자료 띠와 깜박이는 작은 불빛 (밤)
    vv0, vv1 = (0.8, 0.86) if v != 4 else (0.62, 0.68)
    for face in ("left", "right"):
        strip = _decal(sp, f[face], 0.0, vv0, 1.0, vv1, Mat("#2f8f8a", 0.6), 0.02)
        sp.light_poly(strip, CYAN_LIGHT, 0.95)
    for k in range(5):
        sp.glow(add(_face_pt(f["left"], 0.1 + k * 0.08, 0.72), (0, 0.05, 0)), 3, ("#7CF29A", CYAN_LIGHT)[k % 2], 0.9)
    # 둑 발치의 작은 출입구 (+x)
    sp.box(2.3, -0.6, 0, 1.0, 1.2, 1.6, CONCRETE, top=Mat("#b3a48e"))
    df = Sprite.box_faces(2.3, -0.6, 0, 1.0, 1.2, 1.6)
    door(sp, df["right"], 0.22, 0.78, 0.78, Mat("#5c626b", 0.3))
    if v == 2:
        antenna(sp, (mx0 + 0.4, my0 + 0.4, top), 1.0)
    elif v == 3:
        sp.lamp((mx1 + 0.05, my1 + 0.05, top + 0.05), CYAN_LIGHT, 6)
