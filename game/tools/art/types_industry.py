"""산업 묶음 — 얼음 채굴·굴착·레골리스 프린터·전해·부품 공장·로봇·추진제·착륙장 계열의 새 건물 32종.

종류마다 fn(sp, v) 하나: v0이 대표 모양, v1~v4는 같은 기계의 세부(색 띠, 덧붙인 장치, 방향, 크기 조금)를 바꾼다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 그린다.
"""
from __future__ import annotations

import math

import iso
from types_common import *  # noqa: F401,F403

TRACK = Mat("#3B3F46", 0.1)
ICE_FLOOR = Mat("#8E9AA3", 0.2)
HOT = "#ff7b2e"
GREY_BRICK = Mat("#9C9A94")
DARK_GLASSY = Mat("#3A3634", 0.55)


# ── 공용 부품 ────────────────────────────────────────────────────────

def _pyr(sp: Sprite, cx, cy, z0, z1, ax0, ay0, ax1, ay1, mat: Mat, top: Mat | None = None):
    """사각뿔대: z0에서 반폭 (ax0, ay0), z1에서 (ax1, ay1). 보이는 면만 그려진다."""
    b = [(cx - ax0, cy - ay0, z0), (cx + ax0, cy - ay0, z0), (cx + ax0, cy + ay0, z0), (cx - ax0, cy + ay0, z0)]
    t = [(cx - ax1, cy - ay1, z1), (cx + ax1, cy - ay1, z1), (cx + ax1, cy + ay1, z1), (cx - ax1, cy + ay1, z1)]
    for i in range(4):
        sp.face([b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]], mat, ao=0.0)
    sp.face(t, top or mat, normal=(0, 0, 1))
    return b, t


HORN = Mat("#A8703F", 0.5)


def _horn(sp: Sprite, hx, hy, z0, z1, a0):
    """아래를 향한 사각 나팔 (마이크로파 혼): 넓은 입 + 테두리 + 좁은 목."""
    zm = z0 + (z1 - z0) * 0.62
    am = a0 * 0.34
    sp.box(hx - a0 - 0.08, hy - a0 - 0.08, z0 - 0.1, 2 * a0 + 0.16, 2 * a0 + 0.16, 0.14, DARK)
    _pyr(sp, hx, hy, z0 + 0.04, zm, a0, a0, am, am, HORN, top=HORN)
    for sx, sy in ((1, 1), (1, -1), (-1, 1)):
        sp.line((hx + sx * a0, hy + sy * a0, z0 + 0.04), (hx + sx * am, hy + sy * am, zm), 0.05, "#6e4423")
    for t in (0.35, 0.7):
        z = z0 + (zm - z0) * t
        a = a0 + (am - a0) * t
        sp.polyline3([(hx - a, hy + a, z), (hx + a, hy + a, z), (hx + a, hy - a, z)], "#7d5230", 0.04)
    sp.box(hx - am * 0.8, hy - am * 0.8, zm, am * 1.6, am * 1.6, z1 - zm, Mat("#C08A52", 0.45), top=DARK)
    sp.glow((hx, hy, 0.2), 24 if a0 > 0.9 else 18, "#ff9b7a", 0.55)


def _waveguide(sp: Sprite, pts):
    """네모 도파관 (구리)."""
    sp.polyline3(pts, "#6e4423", 0.32)
    sp.polyline3(pts, "#c48a52", 0.24)


def _track(sp: Sprite, x0, x1, y, tw=0.9, r=0.5, mat: Mat = TRACK):
    """x0~x1을 달리는 무한궤도 (가운데 y, 폭 tw, 높이 2r)."""
    ya, yb = y - tw / 2, y + tw / 2
    sp.cyl((x0 + r, ya, r), (x0 + r, yb, r), r, mat, cap_mat=STEEL)
    sp.box(x0 + r, ya, 0, x1 - x0 - 2 * r, tw, 2 * r, mat)
    sp.panel_grid((x0 + r, ya, 2 * r), (x1 - x0 - 2 * r, 0, 0), (0, tw, 0), max(2, int((x1 - x0) / 0.35)), 1,
                  "#23262b", 0.5, 0.7)
    sp.cyl((x1 - r, ya, r), (x1 - r, yb, r), r, mat, cap_mat=STEEL)
    n = max(2, int((x1 - x0 - 2 * r) / (1.2 * r)))
    for i in range(n + 1):
        x = x0 + r + (x1 - x0 - 2 * r) * i / n
        sp.disc((x, yb + 0.02, r * 0.9), (0, 1, 0), r * 0.36, STEEL)


def _track_y(sp: Sprite, y0, y1, x, tw=0.9, r=0.5, mat: Mat = TRACK):
    """y0~y1을 달리는 무한궤도 (가운데 x)."""
    xa, xb = x - tw / 2, x + tw / 2
    sp.cyl((xa, y0 + r, r), (xb, y0 + r, r), r, mat, cap_mat=STEEL)
    sp.box(xa, y0 + r, 0, tw, y1 - y0 - 2 * r, 2 * r, mat)
    sp.panel_grid((xa, y0 + r, 2 * r), (tw, 0, 0), (0, y1 - y0 - 2 * r, 0), 1, max(2, int((y1 - y0) / 0.35)),
                  "#23262b", 0.5, 0.7)
    sp.cyl((xa, y1 - r, r), (xb, y1 - r, r), r, mat, cap_mat=STEEL)
    n = max(2, int((y1 - y0 - 2 * r) / (1.2 * r)))
    for i in range(n + 1):
        y = y0 + r + (y1 - y0 - 2 * r) * i / n
        sp.disc((xb + 0.02, y, r * 0.9), (1, 0, 0), r * 0.36, STEEL)


def _ice_ground(sp: Sprite, cx, cy, rx, ry, lumps=()):
    sp.ellipsoid((cx, cy, 0), rx, ry, 0.14, ICE_FLOOR, clip_z=0.0)
    for (x, y, s) in lumps:
        sp.ellipsoid((x, y, 0.0), 0.6 * s, 0.45 * s, 0.12, ICE, clip_z=0.0)


def _mast(sp: Sprite, x, y, h=3.4, color=AMBER, r=18, z=0.0):
    sp.line((x, y, z), (x, y, z + h), 0.08, "#8a9099")
    sp.lamp((x, y, z + h + 0.1), color, r)


def _vtank(sp: Sprite, x, y, z0, h, r, mat: Mat, bands=(), band_color=None, dome=True):
    """선 탱크 (윗면은 반구)."""
    sp.cyl((x, y, z0), (x, y, z0 + h), r, mat, bands=bands, band_color=band_color)
    if dome:
        sp.sphere((x, y, z0 + h), r, mat, clip_z=z0 + h)


def _glass_pane(sp: Sprite, pts3, color="#cfe6ff", alpha=0.22, frame="#dfe9f2"):
    """유리판 (2D는 반투명, 3D는 유리 재질)."""
    sp._rec(("poly", list(pts3), iso._Glass(color, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if dot(n, VIEW) <= 0:
        n = mul(n, -1)
    sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(color), n, 0.6)), frame, 0.5, alpha + 0.12)


def _pile(sp: Sprite, x, y, rx, ry, rz, mat: Mat = REGOLITH):
    sp.ellipsoid((x, y, 0), rx, ry, rz, mat, clip_z=0.0)


def _pad(sp: Sprite, w, d, h=0.3, mat: Mat = SINTER, m=0.2):
    sp.box(-w / 2 + m, -d / 2 + m, 0, w - 2 * m, d - 2 * m, h, mat)


# ── 얼음 채굴 계열 ───────────────────────────────────────────────────

@typed("microwave_extractor", 9, 6, 4.0, "마이크로파 추출기", heights=[4.0, 4.0, 4.4, 4.2, 3.6])
def microwave_extractor(sp: Sprite, v: int):
    """궤도차에 아래를 향한 큰 마이크로파 혼과 수증기 탱크를 싣고 얼음 흙을 데운다."""
    sp.contact_shadow(0.2, 0, 4.6, 3.1, 0.45)
    _ice_ground(sp, 0.4, 0, 4.0, 2.7, ((-3.4, -2.0, 1.0), (-2.2, 2.3, 0.8), (1.4, -2.3, 0.9)))
    accent = (BLUE, ORANGE, TEAL, BLUE, RED)[v]
    twin = v == 4
    hx = 3.2
    # 데운 자리: 서리가 녹아 젖은 얼음과 혼의 그림자
    sp.ellipsoid((hx, 0, 0), 1.25 if not twin else 1.1, 1.3 if not twin else 2.4, 0.06, Mat("#B9C9D2", 0.5), clip_z=0.0)
    for hy in ((-1.15, 1.15) if twin else (0.0,)):
        sp.ellipsoid((hx + 0.1, hy + 0.1, 0), 0.95 if not twin else 0.75, 0.9 if not twin else 0.7, 0.03,
                     Mat("#4a5058"), clip_z=0.0)
    _track(sp, -3.9, 1.9, -1.75, 0.9, 0.5)
    sp.box(-3.6, -1.35, 0.55, 5.2, 2.7, 0.8, WHITE, top=SILVER)
    f = Sprite.box_faces(-3.6, -1.35, 0.55, 5.2, 2.7, 0.8)
    band_on(sp, f["left"], 0.55, 0.8, accent)
    _track(sp, -3.9, 1.9, 1.75, 0.9, 0.5)
    # 수증기 탱크
    if v in (0, 2):
        for x in (-3.0, -1.4):
            sp.box(x - 0.2, -0.7, 1.35, 0.4, 1.4, 0.35, STEEL)
        sp.sphere((-3.2, 0, 2.3), 0.85, FROST)
        sp.cyl((-3.2, 0, 2.3), (-1.2, 0, 2.3), 0.85, FROST, bands=[0.3, 0.7], band_color="#9fb4c0", caps=False)
        sp.sphere((-1.2, 0, 2.3), 0.85, FROST)
        sp.ring3((-2.2, 0, 2.3), 0.87, "#3E6FB0", 0.12, normal=(1, 0, 0))
    elif v in (1, 4):
        for y in (-0.6, 0.6):
            legs(sp, [(-2.6, y - 0.4, 1.8), (-2.6, y + 0.4, 1.8)], 1.35)
            sp.sphere((-2.6, y, 2.2), 0.62, FROST)
            sp.ring3((-2.6, y, 2.2), 0.63, "#9fb4c0", 0.06)
    else:
        _vtank(sp, -2.6, 0.0, 1.35, 1.6, 0.8, FROST, bands=[0.5], band_color="#3E6FB0")
    # 발생기 상자
    sp.box(-0.9, -1.0, 1.35, 2.0, 2.0, 1.05, WHITE, top=SILVER)
    g = Sprite.box_faces(-0.9, -1.0, 1.35, 2.0, 2.0, 1.05)
    band_on(sp, g["left"], 0.72, 0.88, accent)
    sp.window(sp.on_face(*g["left"], 0.15, 0.25, 0.45, 0.6), CYAN_LIGHT)
    o, e1, e2 = g["right"]
    for k in range(4):
        sp.face(sp.on_face(o, e1, e2, 0.15, 0.2 + k * 0.15, 0.85, 0.27 + k * 0.15), DARK, normal=(1, 0, 0),
                edge=False, ao=0)
    if v == 2:
        # 해를 향한 태양전지 날개
        sp.line((-0.2, 0.0, 2.4), (-0.2, 0.0, 3.4), 0.1, "#8a9099")
        o2, a2, b2 = (-1.6, 0.4, 3.0), (2.6, 0, 0), (0, 0.4, 1.2)
        sp.quad(o2, a2, b2, SOLAR, back=STEEL)
        sp.panel_grid(o2, a2, b2, 4, 2, "#6f86b0", 0.5, 0.6)
    elif v == 3:
        antenna(sp, (0.6, -0.6, 2.4), 1.6)
    # 혼을 거는 팔과 도파관
    horns = [(hx, -1.15), (hx, 1.15)] if twin else [(hx, 0.0)]
    a0 = 0.8 if twin else 1.05
    for _, hy in horns:
        sp.line((1.6, hy * 0.5 - 0.6, 1.25), (hx - 0.3, hy - 0.3, 2.3), 0.13, "#7d848d")
    for _, hy in horns:
        _waveguide(sp, [(1.1, hy * 0.4, 2.0), (1.9, hy * 0.7, 2.0), (1.9, hy * 0.7, 3.05), (hx, hy, 3.05)])
    for _, hy in horns:
        sp.line((1.6, hy * 0.5 + 0.6, 1.25), (hx - 0.3, hy + 0.3, 2.3), 0.13, "#7d848d")
        _horn(sp, hx, hy, 0.75, 3.1, a0)
    sp.lamp((1.1, 0.9, 2.5), AMBER, 9)
    sp.lamp((hx, 0.0 if not twin else 1.15, 3.45), "#ff5a3c", 6)
    if v != 2:
        _mast(sp, -4.1, 2.5, 3.0, AMBER, 16)


@typed("ice_harvester", 14, 10, 6.0, "대형 얼음 수확기", heights=[6.0, 6.0, 6.0, 6.4, 6.0])
def ice_harvester(sp: Sprite, v: int):
    """앞에 넓은 삽을 단 큰 궤도 기계: 위에 얹은 가마로 얼음을 날리고 서리 섞인 수증기를 뿜는다."""
    sp.contact_shadow(0, 0, 7.2, 5.1, 0.5)
    _ice_ground(sp, 0, 0, 6.8, 4.8, ((-6.0, -3.2, 1.0), (-5.4, 3.6, 1.2), (4.6, -3.9, 0.8), (1.0, 4.4, 0.9)))
    body = YELLOW
    roof = Mat("#F0D27A")
    side = -1 if v == 1 else 1          # 가마·운전실 배치 뒤집기
    _track(sp, -5.6, 2.4, -3.1, 1.4, 0.75)
    sp.box(-5.4, -2.5, 0.9, 7.6, 5.0, 1.4, body, top=roof)
    f = Sprite.box_faces(-5.4, -2.5, 0.9, 7.6, 5.0, 1.4)
    sp.stripes(f["left"][0], (-7.6, 0, 0), (0, 0, 0.3), n=16)
    _track(sp, -5.6, 2.4, 3.1, 1.4, 0.75)
    # 가마 받침과 회전 가마
    ky = -0.7 * side
    kz0, kz1 = (3.5, 3.1)
    for x in (-3.8, -0.4):
        sp.box(x - 0.35, ky - 0.8, 2.3, 0.7, 1.6, 0.6, STEEL)
    k0, k1 = (-5.0, ky, kz0), (1.2, ky, kz1)
    sp.cyl(k0, k1, 1.15, Mat("#C9CED4", 0.25), bands=[0.08, 0.5, 0.92], band_color="#6b7079", cap_mat=STEEL)
    for s in (0.22, 0.72):
        cyl_ring(sp, k0, k1, 1.15, s - 0.03, s + 0.03, DARK)
    cyl_ring(sp, k0, k1, 1.15, 0.45, 0.52, Mat("#E07B39", 0.1), glow=HOT, glow_alpha=0.35)
    # 배출 후드 (뜨거운 흙)
    sp.box(1.0, ky - 1.0, 2.3, 1.0, 2.0, 1.9, STEEL, top=DARK)
    sp.window(sp.on_face(*Sprite.box_faces(1.0, ky - 1.0, 2.3, 1.0, 2.0, 1.9)["right"], 0.25, 0.25, 0.75, 0.5),
              HOT, glass=Mat("#b5481c", 0.3))
    sp.glow((1.6, ky, 3.0), 18, HOT, 0.45)
    # 서리 낀 냉각 포집 탱크와 뚜껑 덮인 배기관 (수증기는 탱크에 얼려 모은다)
    cy = 1.4 * side
    sp.box(-5.3, cy - 1.0, 2.3, 2.0, 2.0, 0.45, STEEL, top=DARK)
    tanks = [(-4.75, cy - 0.45), (-3.85, cy + 0.45)] if v != 4 else [(-4.3, cy)]
    tr = 0.55 if v != 4 else 0.85
    th = (1.9, 1.9, 1.9, 1.6, 1.7)[v]
    vents = [(-5.0, cy + 0.65)] + ([(-3.6, cy - 0.65)] if v == 3 else [])
    for (x, y) in sorted(tanks + vents, key=lambda p: p[0] + p[1]):
        if (x, y) in vents:
            sp.cyl((x, y, 2.75), (x, y, 5.3), 0.2, STEEL, bands=[0.5], cap_mat=CHAR)
            sp.cyl((x, y, 5.3), (x, y, 5.42), 0.42, DARK, cap_mat=STEEL)
            sp.ring3((x, y, 2.8), 0.32, "#dfe9f2", 0.12)
            sp.lamp((x, y, 5.6), "#ff5a3c", 6)
        else:
            _vtank(sp, x, y, 2.75, th, tr, FROST, bands=[0.3, 0.6], band_color="#b5c6cf")
            cyl_ring(sp, (x, y, 2.75), (x, y, 2.75 + th), tr, 0.82, 0.88, BLUE)
            sp.ellipsoid((x, y, 2.75), tr + 0.18, tr + 0.18, 0.28, ICE, clip_z=2.75)
    # 운전실
    cab_y0 = 0.4 if side > 0 else -2.4
    sp.box(0.4, cab_y0, 2.3, 1.8, 2.0, 1.5, WHITE, top=SILVER)
    c = Sprite.box_faces(0.4, cab_y0, 2.3, 1.8, 2.0, 1.5)
    sp.window(sp.on_face(*c["right"], 0.1, 0.4, 0.9, 0.85))
    sp.window(sp.on_face(*c["left"], 0.1, 0.45, 0.55, 0.85))
    band_on(sp, c["left"], 0.0, 0.18, ORANGE if v != 2 else RED)
    if v == 4:
        antenna(sp, (1.6, cab_y0 + 1.6, 3.8), 1.6)
    sp.lamp((2.2, cab_y0 + 1.0, 3.9), AMBER, 10)
    # 앞 삽: 팔 둘 + 넓은 바가지 (안에 얼음 섞인 흙)
    lift = 1.0 if v == 2 else 0.0
    for y in (-2.2, 2.2):
        sp.box(2.2, y - 0.25, 1.1, 1.3, 0.5, 0.5, DARK)
        sp.line((2.6, y, 1.6), (3.4, y, 1.3 + lift), 0.32, "#5c626b")
    bx0, bx1, bw = 3.3, 6.1, 4.2
    z0 = 0.06 + lift
    inner = Mat("#7d848d", 0.2)
    sp.face([(bx0, -bw, z0), (bx0, bw, z0), (bx0, bw, z0 + 1.5), (bx0, -bw, z0 + 1.5)], inner, normal=(1, 0, 0), ao=0.3)
    sp.face([(bx0, -bw, z0), (bx1, -bw, z0), (bx1 - 0.9, -bw, z0 + 0.9), (bx0, -bw, z0 + 1.5)], body,
            two_sided=True, back=Mat("#b8962f"))
    sp.face([(bx0, -bw, z0), (bx1, -bw, z0), (bx1, bw, z0), (bx0, bw, z0)], Mat("#5c626b"), normal=(0, 0, 1), ao=0)
    sp.ellipsoid((4.1, 0.0, z0), 1.3, 3.7, 0.95, Mat("#A39C92"), clip_z=z0)
    for (x, y) in ((4.3, -2.0), (4.7, -0.2), (4.2, 1.5), (3.9, 2.9), (3.8, -3.0)):
        sp.ellipsoid((x, y, z0 + 0.45), 0.32, 0.28, 0.22, ICE)
    sp.face([(bx0, bw, z0), (bx0, bw, z0 + 1.5), (bx1 - 0.9, bw, z0 + 0.9), (bx1, bw, z0)], body, normal=(0, 1, 0))
    sp.box(bx0 - 0.2, -bw - 0.05, z0 + 1.45, 0.35, 2 * bw + 0.1, 0.3, body, top=roof)
    sp.box(bx1 - 0.1, -bw, z0, 0.25, 2 * bw, 0.12, STEEL)
    for i in range(12):
        y = -bw + 0.35 + i * (2 * bw - 0.7) / 11
        sp.face([(bx1 + 0.15, y - 0.16, z0 + 0.1), (bx1 + 0.4, y, z0 + 0.1), (bx1 + 0.15, y + 0.16, z0 + 0.1)], STEEL,
                normal=(0, 0, 1), ao=0)
    sp.lamp((bx0, bw + 0.1, z0 + 1.9), AMBER, 10)
    sp.lamp((bx0, -bw - 0.1, z0 + 1.9), AMBER, 10)
    sp.glow((0, 0, 1.0), 50, AMBER, 0.18)


@typed("heat_probe_field", 10, 8, 1.6, "열 탐침 밭", heights=[1.6, 1.6, 1.8, 1.6, 1.8])
def heat_probe_field(sp: Sprite, v: int):
    """땅에 꽂은 가는 열 탐침 격자 — 가는 관이 모음관으로, 작은 냉각 포집 탱크로 이어진다."""
    sp.contact_shadow(0, 0, 5.2, 4.2, 0.3)
    _ice_ground(sp, 0, 0, 4.9, 3.9, ((-4.0, 2.6, 1.0), (1.9, 3.2, 0.8), (-0.6, -3.3, 0.7), (4.2, -1.0, 0.7)))
    cols, rows = ((5, 4), (5, 4), (6, 3), (5, 4), (4, 4))[v]
    head = (COPPER, COPPER, COPPER, RED, ORANGE)[v]
    xs = [-4.0 + i * (6.4 / (cols - 1)) for i in range(cols)]
    ys = [-2.8 + j * (4.8 / (rows - 1)) for j in range(rows)]
    hx = 3.35                           # 모음관 (y 방향)
    tank = (4.05, 2.85) if v != 4 else (4.05, -2.6)
    for j, y in enumerate(ys):
        off = 0.55 if (v == 1 and j % 2) else 0.0
        row = [x + off for x in xs if x + off < hx - 0.3]
        pipe(sp, [(row[0], y, 0.8), (hx, y, 0.8)], 0.09, "#dfe3e8")
        for x in row:
            sp.disc((x, y, 0.04), (0, 0, 1), 0.32, Mat("#D5E2E8", 0.3))
            sp.cyl((x, y, 0.0), (x, y, 1.05), 0.08, STEEL, edge=False)
            sp.cyl((x, y, 1.0), (x, y, 1.3), 0.21, head, cap_mat=Mat("#5c626b", 0.3))
            sp.glow((x, y, 1.2), 6, "#ffb35c", 0.7)
    pipe(sp, [(hx, ys[0], 0.8), (hx, ys[-1], 0.8), (hx, tank[1], 0.8), (tank[0] - 0.5, tank[1], 0.8)], 0.15)
    # 냉각 포집 탱크와 제어함
    _vtank(sp, tank[0], tank[1], 0.0, 1.1, 0.62, FROST, bands=[0.5], band_color="#3E6FB0")
    if v == 2:
        _vtank(sp, tank[0] - 1.35, tank[1] + 0.2, 0.0, 1.2, 0.5, FROST, bands=[0.5], band_color="#3E6FB0")
    if v == 4:
        _vtank(sp, tank[0], tank[1] + 1.3, 0.0, 1.2, 0.5, FROST, bands=[0.5], band_color="#3E6FB0")
    sx, sy = (4.0, -3.0) if v != 4 else (4.0, 1.2)
    sp.box(sx - 0.45, sy - 0.4, 0, 0.9, 0.8, 0.9, WHITE, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(sx - 0.45, sy - 0.4, 0, 0.9, 0.8, 0.9)["left"], 0.25, 0.45, 0.75, 0.75),
              CYAN_LIGHT, glass=TEAL)
    if v == 3:
        o, e1, e2 = (-4.6, 3.3, 0.5), (3.0, 0, 0), (0, 0.3, 0.9)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 6, 1, "#b9bec4", 0.5, 0.7)
    if v == 2 or v == 4:
        o, e1, e2 = (sx - 0.7, sy + 0.5, 1.0), (1.4, 0, 0), (0, 0.5, 0.6)
        sp.quad(o, e1, e2, SOLAR, back=STEEL)
    sp.lamp((tank[0], tank[1], 1.7), CYAN_LIGHT, 8)
    _mast(sp, -4.5, -3.4, 2.4, AMBER, 14)


@typed("sublimation_plant", 11, 8, 5.0, "승화 정제 공장", heights=[5.0, 5.0, 5.0, 4.6, 5.0])
def sublimation_plant(sp: Sprite, v: int):
    """호퍼 → 기울어진 회전 가마 → 서리 낀 냉각 포집 탱크. 얼음 흙을 데워 물을 뽑는다."""
    sp.contact_shadow(0, 0, 5.8, 4.2, 0.5)
    _pad(sp, 11, 8)
    kiln = Mat("#C8743A", 0.15) if v != 2 else Mat("#B0614A", 0.15)
    # 호퍼
    hx, hy = -4.0, -2.3
    legs(sp, [(hx - 0.8, hy - 0.8, 3.2), (hx + 0.8, hy - 0.8, 3.2), (hx - 0.8, hy + 0.8, 3.2), (hx + 0.8, hy + 0.8, 3.2)], 0.3)
    sp.frustum((hx, hy, 3.0), (hx, hy, 4.85), 0.35, 1.25, STEEL)
    sp.ring3((hx, hy, 4.85), 1.25, "#5c626b", 0.08)
    # 회전 가마 (받침 둘)
    twin = v == 3
    rows = [(-1.2, 0.75), (0.6, 0.75)] if twin else [(-0.6, 1.0)]
    for ky, kr in rows:
        k0, k1 = (-3.0, ky, 3.0), (2.4, ky, 2.2)
        for x in (-1.8, 1.0):
            t = (x - k0[0]) / (k1[0] - k0[0])
            zt = k0[2] + (k1[2] - k0[2]) * t - kr
            sp.box(x - 0.3, ky - 0.6, 0.3, 0.6, 1.2, zt - 0.3, CONCRETE)
        sp.line((hx, hy, 3.0), (k0[0] + 0.3, ky, k0[2] + 0.4), 0.3, "#7d848d")
        sp.cyl(k0, k1, kr, kiln, bands=[0.06, 0.94], band_color="#6b4a33", cap_mat=STEEL)
        for s in (0.2, 0.72):
            cyl_ring(sp, k0, k1, kr, s - 0.035, s + 0.035, DARK)
        cyl_ring(sp, k0, k1, kr, 0.44, 0.5, Mat("#5c626b", 0.3))
    # 배출 후드
    sp.box(2.3, -1.9, 0.3, 1.1, 2.4, 2.9, STEEL, top=DARK)
    hood = Sprite.box_faces(2.3, -1.9, 0.3, 1.1, 2.4, 2.9)
    sp.window(sp.on_face(*hood["right"], 0.25, 0.2, 0.75, 0.42), HOT, glass=Mat("#b5481c", 0.3))
    sp.glow((3.0, -0.7, 1.2), 16, HOT, 0.4)
    _pile(sp, 4.3, -2.7, 0.9, 0.8, 0.6, Mat("#9b7f66"))
    # 앞쪽 처리동
    bx1 = -1.0 if v != 1 else -2.0
    sp.box(-5.0, 0.9, 0.3, bx1 + 5.0, 2.7, 2.4, WHITE, top=SILVER)
    f = Sprite.box_faces(-5.0, 0.9, 0.3, bx1 + 5.0, 2.7, 2.4)
    band_on(sp, f["left"], 0.8, 0.9, BLUE if v != 4 else TEAL)
    windows_row(sp, f["left"], 3 if v != 1 else 2, 0.4, 0.66, 0.12, 0.08)
    door(sp, f["right"], 0.3, 0.7, 0.72)
    # 냉각 포집 탱크 (서리)
    if v == 1:
        tanks = [(-0.6, 2.6), (1.4, 2.6), (3.4, 2.6)]
    elif v == 4:
        tanks = [(3.6, 0.9), (3.6, 2.8)]
    else:
        tanks = [(3.7, 0.9), (3.7, 2.8)] if v != 3 else [(4.3, 1.4), (2.6, 2.9)]
    pipe(sp, [(2.85, -0.7, 3.2), (2.85, tanks[0][1], 3.6), (tanks[-1][0], tanks[-1][1], 3.6)], 0.2)
    for (x, y) in tanks:
        if v == 4:
            legs(sp, [(x - 0.5, y - 0.5, 1.4), (x + 0.5, y - 0.5, 1.4), (x - 0.5, y + 0.5, 1.4), (x + 0.5, y + 0.5, 1.4)], 0.3)
            sp.sphere((x, y, 2.3), 0.9, FROST)
            sp.ring3((x, y, 2.3), 0.91, "#9fb4c0", 0.07)
        else:
            _vtank(sp, x, y, 0.3, 3.0, 0.8, FROST, bands=[0.25, 0.5, 0.75], band_color="#b5c6cf")
            sp.window(Sprite.cyl_patch((x, y, 0.3), (x, y, 3.3), 0.8, 0.6, 0.7, -10, 110), "#9fd8ff", frame=None,
                      glass=BLUE, light_alpha=0.0)
    if v == 2:
        antenna(sp, (-4.6, 1.4, 2.7), 1.8)
        crate(sp, -0.6, 3.0, 0.8, ORANGE, 0.3)
    sp.lamp((bx1, 3.65, 2.4), AMBER, 9)
    sp.lamp((hx, hy, 5.1), "#ff5a3c", 6)


# ── 굴착 계열 ────────────────────────────────────────────────────────

def _bucket_wheel(sp: Sprite, c, r, y0, y1, mat: Mat, n=10, phase=0.0):
    """세로로 선 버킷 휠 (축은 y): 둘레에 바가지, 앞면에 살."""
    cx, _, cz = c
    for i in range(n):
        t = 2 * math.pi * (i + phase) / n
        px, pz = cx + r * math.cos(t), cz + r * math.sin(t)
        sp.cyl((px, y0 - 0.12, pz), (px, y1 + 0.12, pz), 0.34, DARK, cap_mat=Mat("#5c626b", 0.2))
    sp.cyl((cx, y0, cz), (cx, y1, cz), r, mat, cap_mat=mat)
    sp.ring3((cx, y1 + 0.02, cz), r * 0.82, "#8f4a1e", 0.08, normal=(0, 1, 0), front_only=False)
    for i in range(n // 2):
        t = 2 * math.pi * (i + 0.5 + phase) / (n // 2)
        sp.line((cx, y1 + 0.03, cz), (cx + r * 0.8 * math.cos(t), y1 + 0.03, cz + r * 0.8 * math.sin(t)), 0.1, "#8f4a1e")
    sp.disc((cx, y1 + 0.05, cz), (0, 1, 0), r * 0.25, STEEL)


@typed("bucket_wheel", 12, 8, 6.0, "버킷휠 굴착기", heights=[6.0, 6.4, 6.0, 6.0, 5.6])
def bucket_wheel(sp: Sprite, v: int):
    """궤도 받침 위 회전 상부, 붐 끝의 큰 버킷 휠, 붐을 따라 흙을 나르는 컨베이어."""
    sp.contact_shadow(0.0, 0, 6.0, 4.0, 0.45)
    house = ORANGE
    wheel = (ORANGE, ORANGE, YELLOW, ORANGE, RED)[v]
    hub_z = 2.4 if v != 1 else 2.8
    wr = 1.9 if v != 4 else 1.7
    hx = 3.55 if v != 4 else 3.75
    # 뒤로 버리는 컨베이어와 흙더미
    spoil_y = -2.9 if v != 3 else 2.9
    _pile(sp, -4.5, spoil_y, 1.3, 0.9, 1.0 if v != 2 else 1.3)
    if v == 2:
        _pile(sp, -2.6, -3.2, 0.9, 0.6, 0.6)
    if spoil_y < 0:
        sp.face([(-3.2, -0.9, 2.4), (-3.2, -0.3, 2.4), (-4.5, spoil_y + 0.3, 2.2), (-4.5, spoil_y - 0.3, 2.2)][::-1],
                DARK, two_sided=True)
        sp.line((-3.9, (spoil_y - 0.9) / 2, 0.0), (-3.9, (spoil_y - 0.9) / 2, 2.3), 0.12, "#7d848d")
    _track(sp, -4.0, 0.0, -1.5, 1.0, 0.55)
    sp.cyl((-2.0, 0, 1.0), (-2.0, 0, 1.45), 1.4, STEEL, cap_mat=DARK)
    # 평형추 팔
    sp.box(-5.8, -0.9, 1.7, 1.0, 1.8, 1.3, CONCRETE, top=Mat("#b3a690"))
    sp.box(-4.9, -0.35, 2.5, 1.6, 0.7, 0.4, house)
    sp.box(-3.4, -1.2, 1.45, 3.0, 2.4, 1.6, house, top=Mat("#E9965E"))
    f = Sprite.box_faces(-3.4, -1.2, 1.45, 3.0, 2.4, 1.6)
    band_on(sp, f["left"], 0.0, 0.14, DARK)
    windows_row(sp, f["left"], 2, 0.45, 0.7, 0.5, 0.06)
    _track(sp, -4.0, 0.0, 1.5, 1.0, 0.55)
    if spoil_y > 0:
        sp.face([(-2.9, 1.2, 2.6), (-2.3, 1.2, 2.6), (-4.2, spoil_y - 0.2, 2.0), (-4.8, spoil_y - 0.2, 2.0)][::-1],
                DARK, two_sided=True)
    # 돛대와 붐 줄
    top = (-1.9, 0.0, 5.9 if v != 1 else 6.3)
    for y in (-0.9, 0.9):
        sp.line((-2.6, y, 3.05), top, 0.14, "#8a9099")
    sp.line(top, (-5.3, 0, 2.9), 0.05, "#c9ccd1")
    sp.line(top, (hx - 0.6, 0.0, hub_z + 0.4), 0.05, "#c9ccd1")
    # 운전실
    sp.box(-0.5, 0.45, 2.0, 0.85, 0.8, 1.0, WHITE, top=SILVER)
    c = Sprite.box_faces(-0.5, 0.45, 2.0, 0.85, 0.8, 1.0)
    sp.window(sp.on_face(*c["right"], 0.1, 0.45, 0.9, 0.85))
    sp.window(sp.on_face(*c["left"], 0.15, 0.45, 0.85, 0.85))
    # 붐 (격자 보) 와 컨베이어 띠
    b0, b1 = (-0.4, 0.0, 2.2), (hx - 0.4, 0.0, hub_z)
    seg = 7
    for yy in (-0.42, 0.42):
        for i in range(seg):
            t0, t1 = i / seg, (i + 1) / seg
            za, zb = b0[2] + (b1[2] - b0[2]) * t0, b0[2] + (b1[2] - b0[2]) * t1
            xa, xb = b0[0] + (b1[0] - b0[0]) * t0, b0[0] + (b1[0] - b0[0]) * t1
            sp.line((xa, yy, za - 0.3), (xb, yy, zb + 0.3), 0.07, "#b85f22")
        sp.polyline3([(b0[0], yy, b0[2] + 0.3), (b1[0], yy, b1[2] + 0.3)], "#c86a2a", 0.15)
        sp.polyline3([(b0[0], yy, b0[2] - 0.3), (b1[0], yy, b1[2] - 0.3)], "#c86a2a", 0.15)
        if yy < 0:
            sp.face([(b0[0], -0.36, b0[2] + 0.32), (b1[0], -0.36, b1[2] + 0.32), (b1[0], 0.36, b1[2] + 0.32),
                     (b0[0], 0.36, b0[2] + 0.32)], DARK, two_sided=True, ao=0)
            for t in (0.15, 0.4, 0.65, 0.88):
                sp.ellipsoid((b0[0] + (b1[0] - b0[0]) * t, 0, b0[2] + 0.36 + (b1[2] - b0[2]) * t), 0.28, 0.22, 0.12,
                             Mat("#8A8378"))
    # 휠 아래 흙과 휠
    _pile(sp, hx + 0.3, -1.0, 1.3, 1.0, 0.7)
    _bucket_wheel(sp, (hx, 0, hub_z), wr, 0.5, 1.2, wheel, 10, 0.25 * v)
    sp.lamp((0.4, 1.3, 3.1), AMBER, 9)
    sp.lamp(top, "#ff5a3c", 6)
    if v == 4:
        _mast(sp, -5.2, 2.9, 3.2, AMBER, 16)


@typed("rassor", 4, 3, 1.6, "래서 굴착 로봇", heights=[1.6, 1.8, 1.4, 1.8, 1.6])
def rassor(sp: Sprite, v: int):
    """작고 납작한 굴착 로봇: 양 끝 팔에 서로 반대로 도는 바가지 드럼 둘."""
    sp.contact_shadow(0, 0, 2.1, 1.5, 0.4)
    accent = (ORANGE, ORANGE, YELLOW, TEAL, ORANGE)[v]
    if v == 4:
        sp.box(-1.9, -1.4, 0, 3.8, 2.8, 0.06, DARK)
        sp.stripes((-1.9, 1.4, 0.06), (3.8, 0, 0), (0, -0.25, 0), n=10, normal=(0, 0, 1))
    if v == 2:
        _pile(sp, -1.45, 0.0, 0.5, 0.9, 0.35)
        _pile(sp, 1.45, 0.1, 0.5, 0.8, 0.3)
    else:
        _pile(sp, 1.5, 0.35, 0.45, 0.6, 0.22)
    zf = (0.5, 1.05, 0.47, 0.5, 0.5)[v]          # 앞 드럼 높이 (들어 올리면 흙을 쏟는다)
    zb = (0.5, 0.5, 0.47, 0.9, 0.5)[v]

    def drum(x, z):
        p0, p1 = (x, -0.72, z), (x, 0.72, z)
        sp.cyl(p0, p1, 0.46, STEEL, bands=[0.12, 0.88], band_color="#5c626b", cap_mat=Mat("#5c626b", 0.3))
        ang = Sprite.facing_angle(p0, p1, norm((0.6, 0.3, 0.75)))
        for k in range(4):
            s0 = 0.2 + k * 0.16
            a = ang - 40 + (k % 2) * 34
            sp.face(Sprite.cyl_patch(p0, p1, 0.46, s0, s0 + 0.1, a, a + 26), CHAR, ao=0, edge=False)
    _track(sp, -0.75, 0.75, -0.62, 0.32, 0.24)
    drum(-1.45, zb)
    for y in (-0.42, 0.42):
        sp.line((-0.7, y, 0.75), (-1.45, y, zb), 0.13, "#8a9099")
    sp.box(-0.78, -0.58, 0.42, 1.56, 1.16, 0.55, WHITE, top=SILVER)
    f = Sprite.box_faces(-0.78, -0.58, 0.42, 1.56, 1.16, 0.55)
    band_on(sp, f["left"], 0.15, 0.4, accent)
    sp.box(-0.62, -0.46, 0.97, 1.24, 0.92, 0.06, SOLAR)
    sp.panel_grid((-0.62, -0.46, 1.03), (1.24, 0, 0), (0, 0.92, 0), 3, 2, "#6f86b0", 0.4, 0.6)
    _track(sp, -0.75, 0.75, 0.62, 0.32, 0.24)
    for y in (-0.42, 0.42):
        sp.line((0.7, y, 0.75), (1.45, y, zf), 0.13, "#8a9099")
    drum(1.45, zf)
    if v == 1:
        for k in range(3):
            sp.rock((1.62 + 0.08 * k, -0.2 + 0.25 * k, 0.15 + 0.25 * k), 0.08)
    if v in (1, 3):
        antenna(sp, (-0.5, -0.4, 1.03), 0.6)
    sp.cyl((0.55, 0.0, 1.03), (0.55, 0.0, 1.35), 0.05, STEEL, edge=False)
    sp.box(0.42, -0.14, 1.35, 0.26, 0.28, 0.16, DARK)
    sp.lamp((0.7, 0.0, 1.43), AMBER, 7)


@typed("dragline", 10, 8, 7.0, "드래그라인", heights=[7.0, 6.4, 7.0, 5.6, 7.0])
def dragline(sp: Sprite, v: int):
    """궤도 위 기계실과 긴 격자 붐, 줄에 매달린 끌개 바가지."""
    sp.contact_shadow(-0.4, 0, 4.9, 3.8, 0.45)
    house = Mat("#C9553A", 0.1)
    roof = SILVER if v != 4 else WHITE
    tip = ((4.4, 0.0, 6.8), (4.5, 0.4, 6.2), (4.4, -0.3, 6.9), (4.6, 0.3, 5.4), (4.3, 0.0, 6.8))[v]
    bx, by, bz = ((3.8, 0.0, 1.5), (2.9, 0.4, 0.25), (3.9, -0.3, 2.7), (4.0, 0.3, 1.0), (3.6, 0.0, 1.9))[v]
    # 판 구덩이와 버린 흙
    sp.face([(3.4 + 1.3 * math.cos(t * math.pi / 8), 0.2 + 1.0 * math.sin(t * math.pi / 8), 0.02)
             for t in range(16)], Mat("#4a4540"), normal=(0, 0, 1), ao=0)
    _pile(sp, -3.4, -3.0, 1.4, 0.9, 1.1 if v != 2 else 1.4)
    if v == 2:
        _pile(sp, -1.4, -3.2, 0.9, 0.7, 0.7)
    _track(sp, -4.4, -0.6, -1.4, 1.0, 0.5)
    sp.cyl((-2.5, 0, 0.95), (-2.5, 0, 1.2), 1.5, STEEL, cap_mat=DARK)
    sp.box(-4.2, -1.2, 1.2, 3.4, 2.4, 1.8, house, top=roof)
    f = Sprite.box_faces(-4.2, -1.2, 1.2, 3.4, 2.4, 1.8)
    band_on(sp, f["left"], 0.8, 0.9, WHITE if v != 4 else Mat("#5c626b"))
    sp.window(sp.on_face(*f["left"], 0.04, 0.42, 0.3, 0.72))
    sp.window(sp.on_face(*f["right"], 0.62, 0.42, 0.95, 0.72))
    o, e1, e2 = f["left"]
    for k in range(3):
        sp.face(sp.on_face(o, e1, e2, 0.45 + k * 0.15, 0.2, 0.55 + k * 0.15, 0.6), Mat("#8f3a24"), normal=(0, 1, 0),
                ao=0, edge=False)
    _track(sp, -4.4, -0.6, 1.4, 1.0, 0.5)
    # A자 틀과 붐
    afr = (-2.5, 0.0, 5.0)
    for y in (-0.95, 0.95):
        sp.line((-3.2, y, 3.0), afr, 0.13, "#8a9099")
    sp.line(afr, (-4.1, 0, 3.0), 0.1, "#8a9099")
    foot = (-0.7, 0.0, 1.7)
    sp.line(afr, tip, 0.05, "#c9ccd1")
    bd = norm(sub(tip, foot))
    sp.truss(foot, tip, 0.8, "#E9C24A", 0.11, 9, side=norm(cross(bd, (0, 1, 0))))
    sp.line((afr[0], 0.12, afr[2]), (tip[0], tip[1] + 0.12, tip[2]), 0.05, "#c9ccd1")
    sp.disc(tip, (0, 1, 0), 0.34, STEEL)
    # 끌개 바가지: 끌줄은 기계실로, 들줄은 붐 끝으로
    sp.line((-0.6, 0.0, 1.5), (bx - 0.75, by, bz + 0.35), 0.06, "#3a3f47")
    sp.line((tip[0], tip[1], tip[2] - 0.2), (bx, by, bz + 1.3), 0.06, "#3a3f47")
    sp.polyline3([(bx - 0.6, by - 0.55, bz + 0.75), (bx, by, bz + 1.3), (bx - 0.6, by + 0.55, bz + 0.75)], "#5c626b", 0.07)
    sp.box(bx - 0.75, by - 0.6, bz, 1.5, 1.2, 0.85, STEEL, top=Mat("#4a4f57"))
    sp.ellipsoid((bx + 0.05, by, bz + 0.85), 0.6, 0.5, 0.22, REGOLITH)
    for k in range(4):
        y = by - 0.4 + k * 0.27
        sp.line((bx - 0.7, y, bz + 0.05), (bx - 0.95, y, bz - 0.02), 0.08, "#c9ccd1")
    if v == 2:
        for k in range(4):
            sp.rock((bx - 0.2 + 0.15 * k, by + 0.2 - 0.1 * k, bz - 0.4 - 0.5 * k), 0.12)
    sp.lamp((tip[0], tip[1], tip[2] + 0.25), "#ff5a3c", 6)
    sp.lamp((-0.75, 1.0, 2.9), AMBER, 10)
    if v == 3:
        _mast(sp, -4.5, 3.4, 3.0, AMBER, 16)


@typed("regolith_sorter", 7, 5, 3.6, "레골리스 체질기", heights=[3.6, 3.6, 3.8, 3.6, 3.6])
def regolith_sorter(sp: Sprite, v: int):
    """다리 위의 기울어진 진동 체 — 위에 호퍼, 아래로 고운 흙 더미와 굵은 돌 더미."""
    sp.contact_shadow(0, 0, 3.7, 2.6, 0.4)
    frame = (Mat("#5E9E4B", 0.15), Mat("#3FB8AF", 0.15), Mat("#5E9E4B", 0.15), YELLOW, Mat("#E07B39", 0.1))[v]
    fcol = hexc(scale(frame.albedo, 0.7))
    # 호퍼
    hx, hy = -2.45, -0.5
    legs(sp, [(hx - 0.6, hy - 0.6, 2.8), (hx + 0.6, hy - 0.6, 2.8), (hx - 0.6, hy + 0.6, 2.8), (hx + 0.6, hy + 0.6, 2.8)], 0.0,
         0.1, fcol)
    sp.frustum((hx, hy, 2.55), (hx, hy, 3.5), 0.3, 0.95, frame)
    sp.ring3((hx, hy, 3.5), 0.95, "#3a3f47", 0.07)
    sp.ellipsoid((hx, hy, 3.45), 0.8, 0.8, 0.22, REGOLITH)
    if v == 2:
        # 호퍼로 올리는 경사 컨베이어
        sp.face([(-3.4, 1.9, 0.3), (-3.4, 2.5, 0.3), (hx, hy + 0.3, 3.5), (hx, hy - 0.3, 3.5)][::-1], DARK, two_sided=True)
        sp.line((-3.4, 1.9, 0.3), (hx, hy - 0.3, 3.5), 0.08, "#E9C24A")
    # 체 (진동 판): 위 끝 x0, 아래 끝 x1
    x0, z0, x1, z1, w = -1.8, 2.35, 1.9, 1.25, 0.85
    for (x, y) in ((x0 + 0.3, -w), (x1 - 0.3, -w)):
        z = z0 + (z1 - z0) * (x - x0) / (x1 - x0)
        sp.line((x, y, 0), (x, y, z - 0.35), 0.12, fcol)
        sp.cyl((x, y, z - 0.35), (x, y, z - 0.08), 0.1, STEEL, edge=False)
    sp.face([(x0, -w, z0 + 0.35), (x1, -w, z1 + 0.35), (x1, -w, z1), (x0, -w, z0)], frame, two_sided=True,
            back=Mat(hexc(scale(frame.albedo, 0.8))))
    deck = [(x0, -w, z0), (x1, -w, z1), (x1, w, z1), (x0, w, z0)]
    sp.face(deck, Mat("#4a4f57", 0.2), normal=(0, 0, 1), ao=0)
    sp.panel_grid(deck[0], sub(deck[1], deck[0]), sub(deck[3], deck[0]), 12, 5, "#9aa1aa", 0.45, 0.8)
    for t in (0.15, 0.4, 0.62):
        sp.ellipsoid((x0 + (x1 - x0) * t, 0.0, z0 + (z1 - z0) * t + 0.05), 0.35, 0.5, 0.12, Mat("#8A8378"))
    sp.line((hx + 0.2, hy, 2.55), (x0 + 0.3, -0.2, z0 + 0.2), 0.3, "#7d848d")
    # 고운 흙: 체 아래 슈트로 앞쪽에
    sp.face([(-0.2, w, 1.55), (0.7, w, 1.45), (0.7, 1.45, 0.8), (-0.2, 1.45, 0.8)], Mat("#6a7079", 0.2), two_sided=True)
    _pile(sp, 0.25, 1.7, 1.05, 0.7, 0.62, Mat("#B2AA9A"))
    for (x, y) in ((x0 + 0.3, w), (x1 - 0.3, w)):
        z = z0 + (z1 - z0) * (x - x0) / (x1 - x0)
        sp.line((x, y, 0), (x, y, z - 0.35), 0.12, fcol)
        sp.cyl((x, y, z - 0.35), (x, y, z - 0.08), 0.1, STEEL, edge=False)
    sp.face([(x0, w, z0), (x1, w, z1), (x1, w, z1 + 0.35), (x0, w, z0 + 0.35)], frame, normal=(0, 1, 0))
    mx = -0.2
    mz = z0 + (z1 - z0) * (mx - x0) / (x1 - x0)
    sp.cyl((mx, w, mz + 0.1), (mx, w + 0.4, mz + 0.1), 0.24, DARK, cap_mat=STEEL)
    # 굵은 돌: 체 끝에서 굴러 떨어진다
    _pile(sp, 2.75, -0.1, 0.75, 1.05, 0.45, Mat("#77706A"))
    for (x, y, r) in ((2.5, -0.7, 0.26), (3.0, -0.3, 0.22), (2.6, 0.2, 0.3), (3.1, 0.5, 0.2), (2.75, -0.05, 0.25),
                      (2.3, 0.75, 0.18)):
        sp.rock((x, y, 0.18 if r > 0.24 else 0.1), r, Mat("#6E675F"))
    # 제어함
    sp.box(-3.2, 1.0, 0, 0.8, 0.7, 1.0, WHITE, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(-3.2, 1.0, 0, 0.8, 0.7, 1.0)["right"], 0.2, 0.5, 0.8, 0.8), "#9BEA7A",
              glass=Mat("#2c8f4f", 0.4))
    if v in (3, 4):
        crate(sp, -1.2, 1.7, 0.7, Mat("#C9A23A") if v == 3 else ORANGE)
    sp.lamp((x1, w, z1 + 0.6), AMBER, 9)
    if v != 2:
        _mast(sp, -3.2, 2.1, 2.8, AMBER, 14)


# ── 레골리스 프린터 계열 ──────────────────────────────────────────────

def _wall(sp: Sprite, x0, y0, x1, y1, h, mat: Mat = SINTER, step=0.4):
    """프린팅으로 쌓는 벽 토막 (층 줄무늬)."""
    sp.box(x0, y0, 0, x1 - x0, y1 - y0, h, mat, top=Mat("#A89A84"))
    print_lines(sp, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], 0.0, h, step)


@typed("gantry_printer", 14, 10, 7.5, "대형 갠트리 프린터", heights=[7.5, 7.5, 7.5, 7.5, 7.5])
def gantry_printer(sp: Sprite, v: int):
    """레일 위를 오가는 큰 문형 갠트리가 직사각형 건물 벽을 반쯤 찍어 올렸다."""
    sp.contact_shadow(0, 0, 7.2, 5.2, 0.4)
    frame = Mat("#2F6DA8", 0.2)
    ftop = Mat("#4C86BE", 0.2)
    gx = (1.35, 1.35, -1.6, -1.8, 1.35)[v]          # 갠트리 위치 (x)
    hy = (0.6, -1.0, 1.2, 0.0, 1.6)[v]              # 인쇄 머리 위치 (y)
    wh = (2.4, 1.6, 3.0, 2.0, 2.4)[v]               # 찍은 벽 높이
    # 레일과 침목
    for ry in (-4.3, 4.3):
        for i in range(12):
            x = -6.6 + i * 1.2
            sp.box(x, ry - 0.45, 0, 0.35, 0.9, 0.12, DARK)
        sp.box(-6.8, ry - 0.15, 0.12, 13.6, 0.3, 0.18, STEEL)
    sp.face([(x, y, 0.03) for x, y in rounded_rect(-5.3, -3.1, 1.9, 3.1, 0.3)], Mat("#A39581"), normal=(0, 0, 1), ao=0)

    def bogie(y):
        sp.box(gx - 0.75, y - 0.45, 0.3, 1.5, 0.9, 0.45, DARK)
        for x in (gx - 0.45, gx + 0.45):
            sp.disc((x, y + 0.47, 0.42), (0, 1, 0), 0.2, STEEL)
        sp.box(gx - 0.35, y - 0.35, 0.75, 0.7, 0.7, 6.0, frame, top=ftop)
        o, e1, e2 = Sprite.box_faces(gx - 0.35, y - 0.35, 0.75, 0.7, 0.7, 6.0)["left"]
        sp.panel_grid(o, e1, e2, 1, 10, "#244f7a", 0.5, 0.8)
    bogie(-4.3)
    # 재료 혼합기 (뒤 왼쪽)
    if v != 3:
        _vtank(sp, -6.2, -3.3, 0.0, 2.2, 0.55, WHITE, bands=[0.5], band_color="#9a8f7c")
        sp.frustum((-6.2, -3.3, 2.75), (-6.2, -3.3, 3.2), 0.55, 0.2, STEEL)
    # 찍고 있는 벽 (뒤·왼쪽 → 오른쪽·앞)
    _wall(sp, -5.0, -2.8, 1.6, -2.3, wh)
    _wall(sp, -5.0, -2.3, -4.5, 2.3, wh)
    if v == 1:
        _wall(sp, -2.0, -2.3, -1.6, 1.0, wh * 0.8)
    if v == 3:
        crate(sp, -3.6, -1.4, 0.9, Mat("#C9A23A"))
    rwh = wh if gx < 0 else wh - 0.4             # 머리 아래 벽이 덜 올라갔다
    _wall(sp, 1.1, -2.3, 1.6, 2.3, rwh)
    _wall(sp, -5.0, 2.3, -1.6, 2.8, wh)
    if v == 2:
        _wall(sp, -1.6, 2.3, -0.4, 2.8, wh * 0.45)    # 문 위 상인방 자리 (낮게)
    _wall(sp, -0.4, 2.3, 1.6, 2.8, wh if gx < 0 else wh - 0.4)
    if v == 2:
        for x0 in (-4.2, -2.6):
            sp.window(sp.on_face(*Sprite.box_faces(x0, 2.3, 0, 1.0, 0.5, wh)["left"], 0.1, 0.45, 0.9, 0.8), frame=None,
                      light_alpha=0.0)
    # 위 보와 수레, 노즐
    sp.box(gx - 0.45, -4.7, 6.6, 0.9, 9.4, 0.8, frame, top=ftop)
    o, e1, e2 = Sprite.box_faces(gx - 0.45, -4.7, 6.6, 0.9, 9.4, 0.8)["right"]
    sp.panel_grid(o, e1, e2, 14, 1, "#244f7a", 0.5, 0.8)
    o, e1, e2 = Sprite.box_faces(gx - 0.45, -4.7, 6.6, 0.9, 9.4, 0.8)["left"]
    sp.stripes(o, e1, (0, 0, 0.2), n=4)
    sp.box(gx - 0.55, hy - 0.5, 6.25, 1.1, 1.0, 1.35, YELLOW, top=Mat("#F0D27A"))
    sp.frustum((gx, hy, 7.6), (gx, hy, 8.0), 0.3, 0.55, STEEL)
    nz = (rwh if abs(gx - 1.35) < 0.1 else wh) + 0.15
    sp.cyl((gx, hy, nz + 0.3), (gx, hy, 6.25), 0.13, STEEL)
    sp.frustum((gx, hy, nz + 0.35), (gx, hy, nz), 0.28, 0.08, DARK)
    sp.glow((gx, hy, nz), 12, "#ff8a3a", 0.8)
    sp.ellipsoid((gx, hy, nz - 0.12), 0.18, 0.18, 0.1, Mat("#C98A5A", 0.3))
    pipe(sp, [(gx, hy + 0.3, 7.4), (gx, 4.3, 7.4), (gx + 0.3, 4.3, 7.0)], 0.12, "#3a3f47")
    bogie(4.3)
    sp.lamp((gx, 4.3, 7.6), AMBER, 10)
    sp.lamp((gx, -4.3, 7.6), "#ff5a3c", 6)
    if v == 4:
        _mast(sp, -6.6, 3.6, 3.4, AMBER, 18)


@typed("solar_sinterer", 9, 8, 6.0, "태양 집광 소결기", heights=[6.0, 6.0, 6.0, 4.8, 6.0])
def solar_sinterer(sp: Sprite, v: int):
    """큰 포물면 거울이 햇빛을 모아 레골리스 판 위의 한 점을 달군다."""
    sp.contact_shadow(-0.3, 0, 4.6, 4.1, 0.4)
    mirror = Mat("#D9E2EA", 0.9) if v != 2 else Mat("#E6C98A", 0.8)
    dishes = [((-1.6, -1.4, 3.5), 2.5)] if v != 3 else [((-2.7, -1.6, 2.6), 1.6), ((0.9, -1.9, 2.6), 1.6)]
    n = norm((0.15, 0.77, -0.62))
    bed_mat = Mat("#A39C92")
    # 받침대
    for (c, r) in dishes:
        back = sub(c, mul(n, 0.7))
        sp.box(back[0] - 0.45, back[1] - 0.45, 0, 0.9, 0.9, 0.5, CONCRETE)
        sp.cyl((back[0], back[1], 0.5), (back[0], back[1], back[2]), 0.24, STEEL)
        sp.line((back[0], back[1], back[2]), sub(c, mul(n, 0.05)), 0.3, "#7d848d")
    # 레골리스 판 (소결 자국)
    bx0, by0, bx1, by1 = (-2.6, 0.5, 2.6, 3.6) if v != 1 else (-3.0, 0.3, 2.2, 3.7)
    sp.box(bx0, by0, 0, bx1 - bx0, by1 - by0, 0.5, CONCRETE, top=bed_mat)
    spots = []
    for (c, r) in dishes:
        t = (c[2] - 0.51) / -n[2]
        spots.append(add(c, mul(n, t)))
    for sx, sy, _ in spots:
        for k in range(4):
            x = sx - 0.6 - k * 0.65
            if x > bx0 + 0.2:
                sp.face([(x - 0.28, sy - 0.28, 0.51), (x + 0.28, sy - 0.28, 0.51), (x + 0.28, sy + 0.28, 0.51),
                         (x - 0.28, sy + 0.28, 0.51)], DARK_GLASSY, normal=(0, 0, 1), ao=0)
    # 거울
    for (c, r) in dishes:
        u, w = basis(n)
        sp.disc(c, n, r + 0.14, DARK, back=STEEL)
        sp.disc(add(c, mul(n, 0.04)), n, r, mirror, back=STEEL)
        # 오목한 느낌: 가운데로 갈수록 어두운 반사
        cc = PV(add(c, mul(n, 0.05)))
        with sp._nest():
            fill = sp.radial([(0, "#5d6a78", 0.55), (0.55, "#9fb0c0", 0.25), (1, "#ffffff", 0.0)], cc[0], cc[1], r * S)
            pts = []
            for k in range(36):
                a = 2 * math.pi * k / 36
                pts.append(PV(add(add(c, mul(n, 0.05)), mul(add(mul(u, math.cos(a)), mul(w, math.sin(a))), r * 0.97))))
            sp.poly2(pts, fill)
        for rr in (r * 0.36, r * 0.68):
            sp.ring3(add(c, mul(n, 0.06)), rr, "#8d99a6", 0.05, normal=n, front_only=False)
        for k in range(12):
            a = math.pi * k / 6
            d = add(mul(u, math.cos(a)), mul(w, math.sin(a)))
            sp.line(add(add(c, mul(n, 0.06)), mul(d, r * 0.36)), add(add(c, mul(n, 0.06)), mul(d, r * 0.98)), 0.035,
                    "#8d99a6")
        sp.ring3(add(c, mul(n, 0.07)), r, "#5c626b", 0.12, normal=n, front_only=False)
        sp.disc(add(c, mul(n, 0.08)), n, r * 0.12, DARK)
    # 빛줄기 (2D만)와 뜨거운 점
    with sp._nest():
        for (c, r), p in zip(dishes, spots):
            u, w = basis(n)
            for k in range(6):
                a = math.pi * k / 3 + 0.3
                rim = add(c, mul(add(mul(u, math.cos(a)), mul(w, math.sin(a))), r * 0.92))
                sp.line(rim, p, 0.05, "#fff1c4", 0.28)
    for p in spots:          # 햇빛이 모일 때만 뜨겁다 — 밤에는 빛나지 않는다
        sp.disc(add(p, (0, 0, 0.01)), (0, 0, 1), 0.42, Mat("#E88A3C", 0.4))
        sp.disc(add(p, (0, 0, 0.02)), (0, 0, 1), 0.2, Mat("#FFF0C0", 0.6))
    # 조종함
    hxx, hyy = (3.2, -2.6) if v != 4 else (3.0, -1.0)
    sp.box(hxx - 0.6, hyy - 0.5, 0, 1.2, 1.0, 1.4, WHITE, top=SILVER)
    hf = Sprite.box_faces(hxx - 0.6, hyy - 0.5, 0, 1.2, 1.0, 1.4)
    band_on(sp, hf["left"], 0.8, 0.9, ORANGE)
    sp.window(sp.on_face(*hf["left"], 0.25, 0.4, 0.75, 0.65))
    if v == 4:
        for k in range(3):
            sp.box(3.0 - 0.5, 1.2 + k * 0.0, k * 0.3, 1.0, 1.0, 0.28, Mat("#5a524a", 0.4))
    if v in (1, 2):
        antenna(sp, (hxx, hyy, 1.4), 1.4)
    sp.lamp((hxx + 0.6, hyy + 0.5, 1.6), AMBER, 8)


@typed("binder_jet_printer", 10, 7, 4.0, "결합제 분사 프린터", heights=[4.0, 4.0, 3.6, 4.0, 4.0])
def binder_jet_printer(sp: Sprite, v: int):
    """가루를 깐 상자 모양 인쇄판 위로 분사 막대가 오가고, 결합제 탱크가 옆에 선다."""
    sp.contact_shadow(0, 0, 5.2, 3.7, 0.45)
    accent = (TEAL, TEAL, GREEN, BLUE, TEAL)[v]
    acc_top = Mat(hexc(scale(accent.albedo, 1.15)), 0.1)
    bx0, bx1 = (-4.3, 2.3) if v != 2 else (-4.3, 1.5)
    by = 2.4
    bh = 1.5 if v != 2 else 1.2
    bar_x = (-0.6, -2.6, -1.4, 0.4, -0.6)[v]
    sp.box(bx0, -by, 0, bx1 - bx0, 2 * by, bh, Mat("#E4E0D6", 0.05), top=Mat("#AEA597"))
    f = Sprite.box_faces(bx0, -by, 0, bx1 - bx0, 2 * by, bh)
    band_on(sp, f["left"], 0.75, 0.88, accent)
    band_on(sp, f["right"], 0.75, 0.88, accent)
    sp.window(sp.on_face(*f["left"], 0.06, 0.3, 0.2, 0.6), CYAN_LIGHT)
    # 가루 위에 찍힌 부품 (젖은 결합제)
    wet = Mat("#6f6658", 0.2)
    if v in (0, 4):
        parts = [(-3.6, -1.6, -2.2, -0.6), (-3.6, 0.4, -2.2, 1.6), (-1.6, -1.6, -0.9, 1.6)]
    elif v == 1:
        parts = [(-1.8, -1.8, 1.6, -1.2), (-1.8, -1.2, -1.2, 1.8), (1.0, -1.2, 1.6, 1.8)]
    elif v == 2:
        parts = [(-3.8, -1.8, -2.8, -0.8), (-2.4, -1.8, -1.4, -0.8), (-3.8, 0.6, -2.8, 1.6), (-2.4, 0.6, -1.4, 1.6)]
    else:
        parts = [(-3.8, -1.9, -0.4, -1.4), (-3.8, -0.4, -0.4, 0.1), (-3.8, 1.1, -0.4, 1.6)]
    for (x0, y0, x1, y1) in parts:
        if x1 <= bar_x - 0.4 or x0 >= bar_x + 0.4:
            sp.face([(x0, y0, bh + 0.01), (x1, y0, bh + 0.01), (x1, y1, bh + 0.01), (x0, y1, bh + 0.01)], wet,
                    normal=(0, 0, 1), ao=0)
    for yy in (-by, by - 0.25):
        sp.box(bx0, yy, bh, bx1 - bx0, 0.25, 0.12, STEEL)
    # 분사 막대: 양 끝 수레 + 막대 + 가루 호퍼
    sp.box(bar_x - 0.55, -by - 0.3, bh, 1.1, 0.6, 0.95, DARK)
    sp.box(bar_x - 0.35, -by - 0.1, bh + 0.5, 0.7, 2 * by + 0.2, 0.45, accent, top=acc_top)
    sp.light_poly([(bar_x + 0.36, -by, bh + 0.5), (bar_x + 0.36, by, bh + 0.5), (bar_x + 0.36, by, bh + 0.6),
                   (bar_x + 0.36, -by, bh + 0.6)], "#7fd0ff", 0.7)
    _pyr(sp, bar_x, 0.0, bh + 0.95, bh + 1.75, 0.3, 1.6, 0.6, 1.9, Mat("#C9CED4", 0.3), top=REGOLITH)
    sp.box(bar_x - 0.55, by - 0.3, bh, 1.1, 0.6, 0.95, DARK)
    sp.lamp((bar_x, by, bh + 1.05), AMBER, 7)
    # 결합제 탱크
    tx = 3.5 if v != 2 else 2.8
    ty = [(-1.7, 2.6), (-0.1, 2.6), (1.5, 2.2)] if v != 3 else [(-1.4, 2.8), (0.6, 2.8)]
    sp.box(tx - 0.9, -2.6, 0, 1.8 + (0.6 if v == 2 else 0), 4.9, 0.25, STEEL)
    hose = []
    for (y, h) in ty:
        _vtank(sp, tx, y, 0.25, h, 0.65, WHITE, bands=[0.5], band_color=hexc(scale(accent.albedo, 0.8)))
        sp.window(Sprite.cyl_patch((tx, y, 0.25), (tx, y, 0.25 + h), 0.65, 0.18, 0.42, 60, 100), "#7fe3da", frame=None,
                  glass=accent, light_alpha=0.5)
        hose.append((tx - 0.4, y, 0.25 + h * 0.8))
    pipe(sp, [hose[0], (bx1 + 0.2, hose[0][1], hose[0][2]), (bar_x + 0.2, -by - 0.1, bh + 0.95)], 0.08, "#3a3f47")
    if v == 2:
        sp.box(3.3, 1.9, 0, 1.2, 1.0, 1.6, WHITE, top=SILVER)
        sp.window(sp.on_face(*Sprite.box_faces(3.3, 1.9, 0, 1.2, 1.0, 1.6)["left"], 0.2, 0.4, 0.8, 0.7), CYAN_LIGHT)
    if v == 4:
        antenna(sp, (tx, ty[0][0], 0.25 + ty[0][1] + 0.6), 1.0)
    sp.lamp((bx1, by, bh + 0.3), AMBER, 8)


def _brick_stack(sp: Sprite, x, y, h, pallet: Mat = Mat("#9C7B55")):
    sp.box(x, y, 0, 1.3, 1.1, 0.16, pallet)
    if h <= 0:
        return
    sp.box(x + 0.05, y + 0.05, 0.16, 1.2, 1.0, h, GREY_BRICK, top=Mat("#AEACA6"))
    f = Sprite.box_faces(x + 0.05, y + 0.05, 0.16, 1.2, 1.0, h)
    rows = max(1, int(round(h / 0.22)))
    sp.panel_grid(*f["left"], 4, rows, "#6d6b66", 0.45, 0.85)
    sp.panel_grid(*f["right"], 3, rows, "#6d6b66", 0.45, 0.85)
    sp.panel_grid(*f["top"], 4, 3, "#7d7b76", 0.4, 0.7)


@typed("brick_press", 9, 6, 3.6, "레골리스 벽돌 압착기", heights=[3.6, 3.6, 3.6, 3.8, 3.6])
def brick_press(sp: Sprite, v: int):
    """유압 압착기가 레골리스를 벽돌로 찍고, 컨베이어가 잿빛 벽돌을 팔레트에 쌓는다."""
    sp.contact_shadow(0, 0, 4.8, 3.2, 0.45)
    paint = (RED, RED, ORANGE, RED, Mat("#3E6FB0", 0.2))[v]
    ptop = Mat(hexc(scale(paint.albedo, 1.12)), 0.1)
    px, py = -2.75, -1.1
    # 호퍼 (뒤)
    legs(sp, [(px - 0.5, py - 1.4, 2.8), (px + 0.5, py - 1.4, 2.8)], 0.0)
    sp.frustum((px, py - 1.2, 2.7), (px, py - 1.2, 3.55), 0.25, 0.68, STEEL)
    sp.ellipsoid((px, py - 1.2, 3.5), 0.56, 0.56, 0.16, REGOLITH)
    sp.line((px, py - 1.2, 2.7), (px, py - 0.5, 1.8), 0.2, "#7d848d")
    # 압착기 틀
    sp.box(px - 1.0, py - 1.0, 0, 2.0, 2.0, 0.9, DARK, top=Mat("#5c626b"))
    sp.box(px - 0.7, py - 1.0, 0.9, 0.5, 0.4, 2.2, paint, top=ptop)
    sp.box(px - 0.5, py - 0.7, 0.9, 1.0, 1.4, 0.4, Mat("#4a4f57"))
    sp.cyl((px, py, 3.0), (px, py, 1.75), 0.27, SILVER)
    sp.box(px - 0.45, py - 0.6, 1.4, 0.9, 1.2, 0.35, STEEL)
    sp.box(px - 0.7, py + 0.6, 0.9, 0.5, 0.4, 2.2, paint, top=ptop)
    sp.box(px - 0.85, py - 1.15, 2.9, 1.25, 2.3, 0.6, paint, top=ptop)
    band_on(sp, Sprite.box_faces(px - 0.85, py - 1.15, 2.9, 1.25, 2.3, 0.6)["left"], 0.35, 0.65, YELLOW)
    sp.box(px + 0.55, py - 0.8, 0.9, 0.5, 1.6, 2.0, paint, top=ptop)
    sp.lamp((px + 0.8, py + 0.85, 3.6), AMBER, 8)
    # 컨베이어 (벽돌이 줄지어 나온다)
    cy0, cy1, cz = py - 0.4, py + 0.4, 0.85
    cx1 = 2.3 if v != 3 else 1.4
    for x in (-1.4, 0.4, cx1 - 0.3):
        sp.line((x, cy0, 0), (x, cy0, cz), 0.08, "#7d848d")
        sp.line((x, cy1, 0), (x, cy1, cz), 0.08, "#7d848d")
    sp.box(-1.75, cy0, cz - 0.15, cx1 + 1.75, cy1 - cy0, 0.15, Mat("#3a3f47"), top=CHAR)
    for k in range(4 if v != 3 else 3):
        x = -1.5 + k * 0.95
        sp.box(x, py - 0.22, cz, 0.55, 0.44, 0.26, GREY_BRICK, top=Mat("#AEACA6"))
    sp.box(-1.75, cy1, cz - 0.2, cx1 + 1.75, 0.08, 0.3, YELLOW)
    # 쌓는 장치 (노란 문형)
    if v != 3:
        gx0 = 2.0
        for (x, y) in ((gx0 + 0.2, -2.5), (gx0 + 2.0, -2.5)):
            sp.box(x - 0.12, y - 0.12, 0, 0.24, 0.24, 2.9, YELLOW)
        for x in (gx0 + 0.08, gx0 + 1.88):
            sp.box(x, -2.62, 2.9, 0.24, 5.0, 0.24, YELLOW, top=Mat("#F0D27A"))
        sp.box(gx0 + 0.1, 0.25, 3.14, 2.0, 0.7, 0.2, ORANGE, top=Mat("#E9965E"))
        sp.box(gx0 + 0.8, 0.35, 2.75, 0.5, 0.5, 0.4, DARK)
        sp.line((gx0 + 1.05, 0.6, 2.75), (gx0 + 1.05, 0.6, 2.0), 0.07, "#9aa1aa")
        sp.box(gx0 + 0.8, 0.35, 1.85, 0.5, 0.5, 0.15, DARK)
        sp.box(gx0 + 0.82, 0.37, 1.58, 0.46, 0.46, 0.27, GREY_BRICK)
    else:
        sp.cyl((2.0, -1.8, 0), (2.0, -1.8, 0.6), 0.45, DARK, cap_mat=STEEL)
        sp.polyline3([(2.0, -1.8, 0.6), (2.0, -1.8, 2.2), (2.6, -0.4, 2.6), (2.8, 0.6, 1.6)], "#E07B39", 0.22)
    # 팔레트
    stacks = ((0.0, 1.0, 0.9), (1.6, 1.4, 0.66), (3.1, 1.4, 0.22), (3.1, -1.3, 0.9))
    hs = ((0.88, 0.66, 0.22, 0.88), (0.88, 0.88, 0.44, 0.66), (0.66, 0.44, 0.0, 0.88), (0.88, 0.88, 0.66, 0.0),
          (0.88, 0.66, 0.44, 0.88))[v]
    order = sorted(range(4), key=lambda i: stacks[i][0] + stacks[i][1])
    for i in order:
        x, y, _ = stacks[i]
        if v == 3 and i == 3:
            continue
        _brick_stack(sp, x - 0.65, y - 0.55, hs[i])
    if v != 3:
        for x in (2.2, 4.0):
            sp.box(x - 0.12, 2.26, 0, 0.24, 0.24, 2.9, YELLOW)
    if v == 4:
        sp.box(-4.2, 1.2, 0, 1.0, 1.2, 1.5, WHITE, top=SILVER)
        sp.window(sp.on_face(*Sprite.box_faces(-4.2, 1.2, 0, 1.0, 1.2, 1.5)["left"], 0.2, 0.45, 0.8, 0.75))
    sp.lamp((-1.6, cy1 + 0.1, 1.4), AMBER, 8)


# ── 용융 레골리스 전해 계열 ───────────────────────────────────────────

FURNACE = Mat("#6B5A4C", 0.15)


@typed("ffc_reducer", 9, 6, 4.0, "FFC 환원로", heights=[4.0, 4.0, 4.0, 4.4, 4.0])
def ffc_reducer(sp: Sprite, v: int):
    """용융염 전해조 한 줄: 네모난 셀 통마다 전극 막대가 솟고, 위를 배기 후드가 덮는다."""
    sp.contact_shadow(0, 0, 4.8, 3.2, 0.5)
    _pad(sp, 9, 6)
    ncell = 4 if v != 2 else 3
    cell = Mat("#5a4c42", 0.15)
    x0 = -3.9
    pitch = 1.75 if ncell == 4 else 2.2
    cw = pitch - 0.35
    y0, y1 = -1.6, 0.6
    hood = (SILVER, SILVER, WHITE, SILVER, Mat("#C9CED4", 0.3))[v]
    # 정류기 (전원) — 뒤 오른쪽
    sp.box(3.2, -2.7, 0.3, 1.1, 1.6, 1.8, WHITE, top=SILVER)
    rf = Sprite.box_faces(3.2, -2.7, 0.3, 1.1, 1.6, 1.8)
    sp.stripes(add(rf["right"][0], (0.01, 0, 1.3)), (0, 1.6, 0), (0, 0, 0.3), n=6, normal=(1, 0, 0))
    sp.window(sp.on_face(*rf["left"], 0.2, 0.35, 0.8, 0.6), "#9BEA7A", glass=Mat("#2c8f4f", 0.4))
    # 셀 통 (앞뒤 순서: x 작은 것부터)
    for i in range(ncell):
        x = x0 + i * pitch
        sp.box(x, y0, 0.3, cw, y1 - y0, 1.3, cell, top=Mat("#4a4038"))
        f = Sprite.box_faces(x, y0, 0.3, cw, y1 - y0, 1.3)
        band_on(sp, f["left"], 0.78, 0.86, Mat("#8a6a50"))
        sp.window([(x + 0.18, y0 + 0.2, 1.61), (x + cw - 0.18, y0 + 0.2, 1.61), (x + cw - 0.18, y1 - 0.2, 1.61),
                   (x + 0.18, y1 - 0.2, 1.61)], HOT, frame="#2a2f36", glass=Mat("#c4581f", 0.35), light_alpha=0.85)
        sp.glow((x + cw / 2, (y0 + y1) / 2, 1.8), 13, HOT, 0.45)
    # 전극 막대와 모선
    bus_z = 2.45
    for i in range(ncell):
        x = x0 + i * pitch
        for (ex, ey) in ((x + cw * 0.3, -0.95), (x + cw * 0.7, -0.05)):
            sp.cyl((ex, ey, 1.4), (ex, ey, bus_z), 0.09, COPPER, edge=False)
    for ey in (-0.95, -0.05):
        sp.box(x0 - 0.1, ey - 0.12, bus_z, (ncell - 1) * pitch + cw + 0.2, 0.24, 0.2, COPPER)
    pipe(sp, [(x0 + (ncell - 1) * pitch + cw, -0.95, bus_z + 0.1), (3.4, -0.95, bus_z + 0.1), (3.4, -1.9, 2.1)],
         0.14, "#c48a52")
    # 배기 후드 (네 기둥 위 깔때기 모양 덮개) 와 덕트
    hx0, hx1 = x0 - 0.2, x0 + (ncell - 1) * pitch + cw + 0.2
    hcx, hcy = (hx0 + hx1) / 2, -0.5
    for x in (hx0 + 0.1, hx1 - 0.1):
        sp.line((x, y0 - 0.25, 0.3), (x, y0 - 0.25, 3.1), 0.1, "#7d848d")
    sp.box(hx0, hcy - 1.45, 2.85, hx1 - hx0, 2.9, 0.2, Mat("#5c626b"))
    sp.stripes((hx1 + 0.005, hcy + 1.45, 2.85), (0, -2.9, 0), (0, 0, 0.2), n=10, normal=(1, 0, 0))
    _pyr(sp, hcx, hcy, 3.05, 3.8, (hx1 - hx0) / 2, 1.45, (hx1 - hx0) / 2 - 0.45, 0.45, hood, top=hood)
    dx = hx0 + 0.9
    sp.cyl((dx, hcy, 3.7), (dx, hcy, 4.3), 0.32, STEEL, cap_mat=CHAR)
    if v in (1, 3):
        pipe(sp, [(dx, hcy, 4.2), (dx, -2.5, 4.2), (dx, -2.5, 1.6)], 0.24)
        sp.box(dx - 0.6, -2.85, 0.3, 1.2, 0.7, 1.4, WHITE, top=SILVER)
    for x in (hx0 + 0.1, hx1 - 0.1):
        sp.line((x, hcy + 1.4, 0.3), (x, hcy + 1.4, 3.0), 0.1, "#7d848d")
    # 앞: 금속 가루 통
    for k in range(2 if v != 4 else 3):
        bx = -3.4 + k * 1.3
        sp.box(bx, 1.6, 0.3, 1.0, 0.9, 0.7, STEEL, top=Mat("#C2C7CD", 0.6))
        sp.ellipsoid((bx + 0.5, 2.05, 1.0), 0.38, 0.33, 0.14, Mat("#B8BEC6", 0.5))
    if v == 3:
        antenna(sp, (4.0, -1.0, 2.1), 1.8)
    sp.lamp((hx1, hcy + 1.45, 3.15), AMBER, 9)
    sp.lamp((4.1, 2.6, 1.0), AMBER, 8)


@typed("hydrogen_reducer", 6, 6, 7.0, "수소 환원로", heights=[7.0, 7.0, 7.4, 6.6, 7.0])
def hydrogen_reducer(sp: Sprite, v: int):
    """세운 유동층 반응 탑 (위에 호퍼), 옆의 응축기와 물탱크 — 수소로 일메나이트를 환원한다."""
    sp.contact_shadow(0, 0, 3.3, 3.3, 0.5)
    _pad(sp, 6, 6)
    col = SILVER
    band = (ORANGE, ORANGE, ORANGE, Mat("#D9893F", 0.1), RED)[v]
    cx, cy = -0.7, -0.7
    top = 5.6 if v != 2 else 6.0
    # 수소 탱크 (뒤 오른쪽, 주황 띠)
    hx, hy = 1.6, -1.9
    sp.box(hx - 0.25, hy - 0.8, 0.3, 0.5, 1.6, 0.5, STEEL)
    sp.cyl((hx - 1.0, hy, 1.25), (hx + 1.2, hy, 1.25), 0.6, WHITE, cap_mat=WHITE)
    sp.ring3((hx + 0.8, hy, 1.25), 0.61, "#d8853b", 0.14, normal=(1, 0, 0))
    # 받침 틀
    for (x, y) in ((cx - 1.2, cy - 1.2), (cx + 1.2, cy - 1.2), (cx - 1.2, cy + 1.2)):
        sp.line((x, y, 0.3), (x, y, 3.4), 0.12, "#7d848d")
    # 반응 탑
    sp.cyl((cx, cy, 0.3), (cx, cy, 0.95), 0.28, DARK)
    sp.frustum((cx, cy, 0.9), (cx, cy, 1.6), 0.35, 0.95, STEEL)
    sp.cyl((cx, cy, 1.6), (cx, cy, top), 0.95, col, bands=[0.25, 0.5, 0.75], band_color="#8a9099", cap_mat=STEEL)
    cyl_ring(sp, (cx, cy, 1.6), (cx, cy, top), 0.95, 0.06, 0.12, band)
    cyl_ring(sp, (cx, cy, 1.6), (cx, cy, top), 0.95, 0.86, 0.92, band)
    sp.window(Sprite.cyl_patch((cx, cy, 1.6), (cx, cy, top), 0.95, 0.3, 0.42, 15, 70), HOT, frame="#2a2f36",
              glass=Mat("#ff7b2e", 0.3))
    sp.glow((cx, cy, 2.8), 14, HOT, 0.45)
    # 걸침 발판
    sp.ring3((cx, cy, 3.4), 1.35, "#9aa1aa", 0.08)
    sp.ring3((cx, cy, 3.9), 1.35, "#9aa1aa", 0.05)
    # 호퍼 (위)
    sp.cyl((cx, cy, top), (cx, cy, top + 0.3), 0.35, STEEL)
    sp.frustum((cx, cy, top + 0.3), (cx, cy, top + 1.3), 0.3, 1.05, Mat("#C9CED4", 0.3))
    sp.ring3((cx, cy, top + 1.3), 1.05, "#5c626b", 0.08)
    for (x, y) in ((cx + 1.2, cy + 1.2),):
        sp.line((x, y, 0.3), (x, y, 3.4), 0.12, "#7d848d")
    # 응축기: 지느러미 달린 누운 원통
    ky = 1.6
    pipe(sp, [(cx + 0.5, cy + 0.5, top - 0.3), (1.6, cy + 0.5, top - 0.3), (1.6, ky, 2.6)], 0.2)
    for x in (0.2, 2.0):
        sp.box(x - 0.2, ky - 0.45, 0.3, 0.4, 0.9, 1.3, STEEL)
    sp.cyl((-0.4, ky, 2.0), (2.5, ky, 2.0), 0.6, WHITE, cap_mat=STEEL)
    for k in range(7):
        s0 = 0.12 + k * 0.11
        cyl_ring(sp, (-0.4, ky, 2.0), (2.5, ky, 2.0), 0.62, s0, s0 + 0.03, Mat("#9aa1aa", 0.3))
    # 물탱크 (파란 띠)
    wx, wy = (2.1, 0.1) if v != 4 else (-2.2, 1.8)
    _vtank(sp, wx, wy, 0.3, 1.3, 0.55, WHITE, bands=[0.5], band_color="#3E6FB0")
    sp.window(Sprite.cyl_patch((wx, wy, 0.3), (wx, wy, 1.6), 0.55, 0.6, 0.75, -10, 120), "#7fb6ff", frame=None,
              glass=BLUE, light_alpha=0.0)
    if v == 3:
        o, e1, e2 = (-2.8, 1.0, 0.3), (0, 1.6, 0), (0, 0, 2.4)
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 4, 1, "#b9bec4", 0.5, 0.7)
    if v == 1:
        sp.box(-2.6, 1.2, 0.3, 1.4, 1.2, 1.4, WHITE, top=SILVER)
        sp.window(sp.on_face(*Sprite.box_faces(-2.6, 1.2, 0.3, 1.4, 1.2, 1.4)["left"], 0.2, 0.4, 0.8, 0.7))
    sp.lamp((cx, cy, top + 1.55), "#ff5a3c", 6)
    sp.lamp((2.5, 1.6, 2.8), AMBER, 8)


@typed("carbothermal_reactor", 8, 7, 5.5, "탄소열 환원로", heights=[5.5, 5.5, 5.5, 5.0, 5.8])
def carbothermal_reactor(sp: Sprite, v: int):
    """둥근 로 지붕에 집광 창이 나 있고, 위 거울이 햇빛을 그 창에 내리꽂는다. 메탄 관이 들어온다."""
    sp.contact_shadow(0, 0, 4.2, 3.7, 0.5)
    _pad(sp, 8, 7)
    shell = (Mat("#D8CBB0"), Mat("#D8CBB0"), Mat("#C9B48F"), Mat("#E2D8C3"), Mat("#D8CBB0"))[v]
    fc = (-0.6, -0.4)
    r = 2.0
    # 메탄 탱크 (노란 띠) — 뒤
    mx, my = (2.2, -2.2) if v != 2 else (-2.6, -2.4)
    legs(sp, [(mx - 0.6, my - 0.6, 0.9), (mx + 0.6, my - 0.6, 0.9), (mx - 0.6, my + 0.6, 0.9), (mx + 0.6, my + 0.6, 0.9)], 0.3)
    sp.sphere((mx, my, 1.6), 0.95, WHITE)
    sp.ring3((mx, my, 1.6), 0.96, "#E9C24A", 0.14)
    # 거울 탑 (뒤): 모은 햇빛을 아래 창으로 꺾어 넣는다
    port = (fc[0], fc[1], 3.2)
    mn = norm((0.55, 0.55, -0.62))
    mc = sub(port, mul(mn, 2.1 if v != 3 else 1.8))
    tx, ty = mc[0] - 0.5, mc[1] - 0.5
    sp.line((tx, ty, 0.3), (tx, ty, mc[2] + 0.25), 0.16, "#8a9099")
    sp.line((tx, ty, mc[2] - 0.6), sub(mc, mul(mn, 0.03)), 0.1, "#8a9099")
    sp.disc(mc, mn, 1.0 if v != 4 else 1.2, Mat("#D9E2EA", 0.9), back=STEEL)
    sp.ring3(add(mc, mul(mn, 0.02)), 1.0 if v != 4 else 1.2, "#5c626b", 0.1, normal=mn, front_only=False)
    sp.ring3(add(mc, mul(mn, 0.02)), 0.5, "#9aa7b3", 0.05, normal=mn, front_only=False)
    # 로: 원통 받침 + 돔
    sp.cyl((fc[0], fc[1], 0.3), (fc[0], fc[1], 1.3), r, Mat("#8C939C", 0.3), bands=[0.5], cap_mat=STEEL)
    sp.dome((fc[0], fc[1], 1.3), r, 1.9, shell)
    for zz in (1.9, 2.5):
        k = math.sqrt(max(0.0, 1 - ((zz - 1.3) / 1.9) ** 2))
        sp.ring3((fc[0], fc[1], zz), r * k, "#a8987c", 0.05)
    # 집광 창 (꼭대기) — 빛줄기
    sp.cyl((fc[0], fc[1], 2.95), (fc[0], fc[1], 3.25), 0.45, DARK, cap_mat=Mat("#FFE3A0", 0.6))
    sp.mark_light("#ffd27a", 0.9)
    with sp._nest():
        u, w = basis(mn)
        for k in range(5):
            a = 2 * math.pi * k / 5
            rim = add(mc, mul(add(mul(u, math.cos(a)), mul(w, math.sin(a))), 0.8))
            sp.line(rim, (port[0], port[1], port[2] + 0.05), 0.06, "#fff1c4", 0.4)
    sp.glow(port, 18, "#ffd27a", 0.9)
    sp.window(Sprite.cyl_patch((fc[0], fc[1], 0.3), (fc[0], fc[1], 1.3), r, 0.25, 0.75, 20, 50), HOT,
              glass=Mat("#b5481c", 0.3))
    sp.glow((fc[0] + 1.2, fc[1] + 1.6, 0.8), 14, HOT, 0.4)
    # 메탄 관 (노랑) 과 일산화탄소 관
    pipe(sp, [(mx - 0.7, my + 0.3, 1.0), (fc[0] + 1.6, fc[1] - 0.2, 1.0)], 0.16, "#E9C24A")
    pipe(sp, [(mx - 0.3, my + 0.8, 0.7), (mx - 0.3, fc[1] + 1.4, 0.7), (fc[0] + 1.3, fc[1] + 1.4, 0.7)], 0.16, "#E9C24A")
    if v == 4:
        pipe(sp, [(mx, my + 0.95, 1.6), (mx, 2.6, 1.6), (fc[0] + 1.0, 2.6, 1.6)], 0.16, "#E9C24A")
    # 앞: 금속 받이 상자와 슬래그
    sp.box(1.4, 1.2, 0.3, 1.6, 1.4, 0.9, STEEL, top=Mat("#C2C7CD", 0.6))
    f = Sprite.box_faces(1.4, 1.2, 0.3, 1.6, 1.4, 0.9)
    sp.stripes(add(f["right"][0], (0.01, 0, 0.6)), (0, 1.4, 0), (0, 0, 0.25), n=6, normal=(1, 0, 0))
    if v in (1, 3):
        _pile(sp, -2.6, 2.4, 0.9, 0.7, 0.5, Mat("#5b4a3e"))
    if v == 3:
        antenna(sp, (2.9, -2.9, 0.3), 2.6)
    sp.lamp((3.0, 2.6, 1.4), AMBER, 8)
    sp.lamp((tx, ty, mc[2] + 0.35), "#ff5a3c", 6)


@typed("mre_line", 16, 8, 7.0, "대형 전해 라인", heights=[7.0, 7.0, 7.0, 7.0, 7.4])
def mre_line(sp: Sprite, v: int):
    """긴 전력동 앞에 큰 도가니 반응로 셋이 한 줄로 서고, 위로 천장 크레인, 끝에는 빛나는 슬래그."""
    sp.contact_shadow(0, 0, 8.4, 4.2, 0.5)
    _pad(sp, 16, 8)
    band = (ORANGE, ORANGE, YELLOW, ORANGE, TEAL)[v]
    # 뒤 긴 동
    sp.box(-7.6, -3.7, 0.3, 13.0, 2.0, 3.0, WHITE, top=SILVER)
    f = Sprite.box_faces(-7.6, -3.7, 0.3, 13.0, 2.0, 3.0)
    band_on(sp, f["left"], 0.82, 0.92, band)
    windows_row(sp, f["left"], 7, 0.4, 0.66, 0.05, 0.06)
    door(sp, f["right"], 0.25, 0.75, 0.72)
    # 크레인 기둥 (뒤 줄)
    rail_y0, rail_y1 = -1.5, 2.8
    cols = (-7.3, -0.2, 6.9)
    for x in cols:
        sp.box(x - 0.2, rail_y0 - 0.2, 0.3, 0.4, 0.4, 6.0, YELLOW)
    sp.box(-7.5, rail_y0 - 0.25, 6.3, 14.6, 0.5, 0.4, YELLOW, top=Mat("#F0D27A"))
    # 도가니 반응로 셋
    xs = (-5.0, -1.6, 1.8)
    for i, x in enumerate(xs):
        c0, c1 = (x, 0.6, 0.3), (x, 0.6, 4.6)
        sp.cyl(c0, c1, 1.45, FURNACE, bands=[0.25, 0.5, 0.75], cap_mat=STEEL)
        sp.window(Sprite.cyl_patch(c0, c1, 1.45, 0.2, 0.36, 15, 75), HOT, frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
        sp.glow((x, 0.6, 1.4), 22, HOT, 0.5)
        sp.frustum((x, 0.6, 4.6), (x, 0.6, 5.3), 0.9, 0.4, STEEL)
        sp.ring3((x, 0.6, 4.62), 1.2, "#5c626b", 0.08)
        pipe(sp, [(x, 0.6, 5.3), (x, -1.0, 5.3), (x, -1.7, 3.3)], 0.2)
    # 크레인 다리 (앞 줄) 와 다리보
    bx = (-3.3, 0.2, -3.3, 3.4, -3.3)[v]
    sp.box(bx - 0.3, rail_y0, 5.9, 0.6, rail_y1 - rail_y0, 0.45, ORANGE, top=Mat("#E9965E"))
    sp.box(bx - 0.4, 0.4, 5.5, 0.8, 0.8, 0.4, DARK)
    sp.line((bx, 0.8, 5.5), (bx, 0.8, 3.6), 0.06, "#9aa1aa")
    sp.frustum((bx, 0.8, 3.6), (bx, 0.8, 2.8), 0.55, 0.4, Mat("#5c626b", 0.3), cap_mat=Mat("#ff9a4a", 0.5))
    sp.mark_light(HOT)
    sp.glow((bx, 0.8, 3.7), 12, HOT, 0.6)
    for x in cols:
        sp.box(x - 0.2, rail_y1 - 0.2, 0.3, 0.4, 0.4, 6.0, YELLOW)
    sp.box(-7.5, rail_y1 - 0.25, 6.3, 14.6, 0.5, 0.4, YELLOW, top=Mat("#F0D27A"))
    # 끝: 빛나는 슬래그 통과 금속 주괴
    for (x, y) in ((5.0, 1.0), (6.4, 2.6)) if v != 3 else ((5.0, 2.6),):
        sp.frustum((x, y, 0.3), (x, y, 1.3), 0.5, 0.75, DARK, cap_mat=Mat("#ff8a3a", 0.5))
        sp.mark_light(HOT)
        sp.glow((x, y, 1.4), 16, HOT, 0.7)
    _pile(sp, 6.2, -0.4, 1.2, 0.9, 0.7, Mat("#7a4a32", 0.3))
    sp.glow((6.2, -0.4, 0.5), 22, "#ff6a2a", 0.5)
    for k in range(3):
        sp.box(-6.8 + k * 0.0, 2.6, 0.3 + k * 0.3, 1.8, 1.0, 0.3, Mat("#C2C7CD", 0.6))
    if v == 4:
        antenna(sp, (-6.0, -2.8, 3.3), 2.6)
    sp.lamp((6.9, 2.8, 6.9), "#ff5a3c", 6)
    sp.lamp((-7.3, 3.4, 1.2), AMBER, 9)
    sp.lamp((4.6, 3.6, 1.0), AMBER, 9)


# ── 부품 공장 계열 ───────────────────────────────────────────────────

def _glass_box(sp: Sprite, x0, y0, z0, x1, y1, z1, frame="#9aa1aa", color="#cfe6ff", alpha=0.2):
    """유리 상자 (뒤 두 면 → 앞 두 면 순서): 안쪽을 먼저 그린 뒤 부른다."""
    _glass_pane(sp, [(x0, y0, z0), (x0, y0, z1), (x1, y0, z1), (x1, y0, z0)], color, alpha)
    _glass_pane(sp, [(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], color, alpha)
    _glass_pane(sp, [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], color, alpha)
    _glass_pane(sp, [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], color, alpha)
    for (x, y) in ((x1, y0), (x0, y1), (x1, y1)):
        sp.line((x, y, z0), (x, y, z1), 0.08, frame)
    sp.polyline3([(x0, y1, z1), (x1, y1, z1), (x1, y0, z1)], frame, 0.08)


@typed("metal_printer", 5, 4, 3.0, "금속 3D 프린터", heights=[3.0, 3.0, 3.0, 3.2, 3.0])
def metal_printer(sp: Sprite, v: int):
    """유리로 둘러싼 작은 금속 프린터 칸: 위의 레이저 머리가 빛나는 부품을 녹여 쌓는다."""
    sp.contact_shadow(0, 0, 2.6, 2.1, 0.45)
    accent = (BLUE, ORANGE, BLUE, TEAL, Mat("#9B7AD6"))[v]
    sp.box(-2.3, -1.85, 0, 4.6, 3.7, 0.18, STEEL)
    # 옆 장치: 가루 공급·냉각기 + 아르곤 병
    sp.box(1.0, -1.6, 0.18, 1.1, 1.9, 1.6, WHITE, top=SILVER)
    sf = Sprite.box_faces(1.0, -1.6, 0.18, 1.1, 1.9, 1.6)
    o, e1, e2 = sf["right"]
    for k in range(4):
        sp.face(sp.on_face(o, e1, e2, 0.15, 0.25 + k * 0.13, 0.85, 0.3 + k * 0.13), DARK, normal=(1, 0, 0), edge=False, ao=0)
    sp.frustum((1.55, -0.65, 1.78), (1.55, -0.65, 2.3), 0.15, 0.4, STEEL)
    for k, y in enumerate((0.75, 1.15) if v != 4 else (0.6, 1.0, 1.4)):
        sp.cyl((1.75, y, 0.18), (1.75, y, 1.55), 0.17, GREEN if k % 2 == 0 else Mat("#C9CED4", 0.3))
        sp.sphere((1.75, y, 1.55), 0.17, GREEN if k % 2 == 0 else Mat("#C9CED4", 0.3), clip_z=1.55)
    # 몸체 (아래 장)
    sp.box(-1.95, -1.45, 0.18, 2.85, 2.9, 0.95, WHITE, top=SILVER)
    f = Sprite.box_faces(-1.95, -1.45, 0.18, 2.85, 2.9, 0.95)
    band_on(sp, f["left"], 0.8, 0.95, accent)
    band_on(sp, f["right"], 0.8, 0.95, accent)
    sp.window(sp.on_face(*f["left"], 0.08, 0.25, 0.3, 0.62), CYAN_LIGHT, glass=Mat("#1f4f5a", 0.6))
    sp.face(sp.on_face(*f["left"], 0.4, 0.08, 0.92, 0.65), STEEL, normal=(0, 1, 0), ao=0)
    # 유리 칸 안: 판, 빛나는 부품, 레이저 머리
    z0, z1 = 1.13, 2.45
    sp.box(-1.25, -0.75, z0, 1.5, 1.5, 0.12, Mat("#5c626b", 0.3))
    if v in (1, 4):
        sp.cyl((-0.5, 0.0, z0 + 0.12), (-0.5, 0.0, z0 + 0.6), 0.28, Mat("#FFA45C", 0.5), cap_mat=Mat("#FFE0A0", 0.6))
    elif v == 2:
        for (x, y) in ((-0.85, -0.35), (-0.15, -0.35), (-0.85, 0.35), (-0.15, 0.35)):
            sp.box(x - 0.15, y - 0.15, z0 + 0.12, 0.3, 0.3, 0.3, Mat("#FFA45C", 0.5), top=Mat("#FFE0A0", 0.6))
    else:
        sp.box(-0.8, -0.3, z0 + 0.12, 0.6, 0.6, 0.45, Mat("#FFA45C", 0.5), top=Mat("#FFE0A0", 0.6))
    sp.mark_light(HOT)
    sp.glow((-0.5, 0.0, z0 + 0.5), 12, "#ffb35c", 0.8)
    sp.box(-0.75, -0.25, z1 - 0.35, 0.5, 0.5, 0.3, DARK)
    sp.frustum((-0.5, 0.0, z1 - 0.35), (-0.5, 0.0, z1 - 0.6), 0.16, 0.05, STEEL)
    sp.line((-0.5, 0.0, z1 - 0.6), (-0.5, 0.0, z0 + 0.6), 0.03, "#ff5a3c", 0.9)
    sp.line((-0.5, 0.0, z1 - 0.6), (-0.5, 0.0, z0 + 0.6), 0.05, "#ff8a5a", 0.8, layer="light")
    _glass_box(sp, -1.75, -1.25, z0, 0.7, 1.25, z1)
    sp.light_poly([(-1.75, 1.26, z0), (0.7, 1.26, z0), (0.7, 1.26, z1), (-1.75, 1.26, z1)], "#ffcf8a", 0.3)
    # 지붕 덮개와 배기
    sp.box(-1.85, -1.35, z1, 2.65, 2.7, 0.25, WHITE, top=SILVER)
    sp.cyl((-1.0, -0.6, z1 + 0.25), (-1.0, -0.6, z1 + 0.45), 0.35, STEEL, cap_mat=CHAR)
    if v == 3:
        sp.polyline3([(0.4, 1.2, z1 + 0.25), (0.4, 1.2, z1 + 0.7)], "#9aa1aa", 0.06)
        sp.lamp((0.4, 1.2, z1 + 0.75), "#7CF29A", 6)
    if v == 2:
        crate(sp, -2.25, 1.0, 0.7, ORANGE, 0.18)
    sp.lamp((0.8, 1.35, z1 + 0.35), AMBER if v != 1 else "#ff5a3c", 7)


@typed("machine_shop", 11, 8, 5.0, "기계 공작소", heights=[5.0, 5.0, 5.2, 5.0, 5.0])
def machine_shop(sp: Sprite, v: int):
    """박공지붕 작업동: 크게 열린 문 안으로 선반·밀링기가 보이고, 문 밖으로 크레인 레일이 뻗는다."""
    sp.contact_shadow(0, 0, 5.8, 4.2, 0.5)
    sp.box(-5.3, -3.8, 0, 10.6, 7.6, 0.15, CONCRETE)
    wall = Mat("#C9CED4", 0.15)
    roof = (SILVER, Mat("#8a5a4a", 0.2), SILVER, Mat("#5c7a96", 0.2), SILVER)[v]
    x0, x1, y0, y1, zw, zr = -5.0, 2.6, -3.4, 2.4, 3.4, 4.9
    ym = (y0 + y1) / 2
    # 크레인 레일 기둥 (뒤 줄)
    rx1 = 5.0
    sp.box(rx1 - 0.15, -2.55, 0.15, 0.3, 0.3, 3.85, Mat("#6a7079", 0.3))
    sp.box(x0, y0, 0.15, x1 - x0, y1 - y0, zw - 0.15, wall, top=wall)
    f = Sprite.box_faces(x0, y0, 0.15, x1 - x0, y1 - y0, zw - 0.15)
    sp.panel_grid(*f["left"], 16, 1, "#a3a9b0", 0.45, 0.8)
    band_on(sp, f["left"], 0.0, 0.08, YELLOW)
    # 높은 창 줄
    windows_row(sp, f["left"], 6 if v != 2 else 4, 0.66, 0.84, 0.05, 0.05)
    door(sp, f["left"], 0.06, 0.13, 0.58, Mat("#5c626b", 0.3))
    # 박공 지붕
    eave = 0.25
    sp.face([(x0 - eave, y0 - eave, zw), (x1 + eave, y0 - eave, zw), (x1 + eave, ym, zr), (x0 - eave, ym, zr)], roof)
    sp.face([(x0 - eave, ym, zr), (x1 + eave, ym, zr), (x1 + eave, y1 + eave, zw), (x0 - eave, y1 + eave, zw)], roof)
    sp.face([(x1, y0, zw), (x1, y1, zw), (x1, ym, zr)], wall)
    sp.panel_grid((x0 - eave, ym, zr), (x1 - x0 + 2 * eave, 0, 0), (0, y1 + eave - ym, zw - zr), 18, 1, "#7d848d", 0.45, 0.7)
    if v == 2:
        for k in range(3):
            xx = x0 + 1.0 + k * 2.3
            t0, t1 = 0.25, 0.6
            pts = [(xx, ym + (y1 + eave - ym) * t0, zr + (zw - zr) * t0), (xx + 1.2, ym + (y1 + eave - ym) * t0, zr + (zw - zr) * t0),
                   (xx + 1.2, ym + (y1 + eave - ym) * t1, zr + (zw - zr) * t1), (xx, ym + (y1 + eave - ym) * t1, zr + (zw - zr) * t1)]
            sp.window(pts, WARM_WINDOW, frame="#5c626b")
    # 큰 문: 어두운 안, 기계 (선반·밀링기)
    dy0, dy1, dz = -2.7, 0.9, 2.9
    o, e1, e2 = f["right"]
    sp.face([(x1 + 0.01, dy0, 0.15), (x1 + 0.01, dy1, 0.15), (x1 + 0.01, dy1, dz), (x1 + 0.01, dy0, dz)], CHAR,
            normal=(1, 0, 0), ao=0)
    sp.light_poly([(x1 + 0.02, dy0, 0.15), (x1 + 0.02, dy1, 0.15), (x1 + 0.02, dy1, dz), (x1 + 0.02, dy0, dz)], "#ffcf8a", 0.5)
    sp.box(x1 - 0.7, -2.4, 0.15, 0.68, 1.7, 0.75, Mat("#4f7a5a", 0.2), top=Mat("#5f8c6a", 0.2))
    sp.cyl((x1 - 0.36, -2.0, 1.1), (x1 - 0.36, -1.4, 1.1), 0.22, STEEL, cap_mat=SILVER)
    sp.box(x1 - 0.65, -0.5, 0.15, 0.6, 0.7, 1.9, Mat("#4f7a5a", 0.2), top=Mat("#5f8c6a", 0.2))
    sp.box(x1 - 0.62, -0.42, 1.45, 0.6, 0.55, 0.35, STEEL)
    sp.stripes((x1 + 0.03, dy0, dz), (0, dy1 - dy0, 0), (0, 0, 0.3), n=12, normal=(1, 0, 0))
    # 문 밖 크레인 레일 (노랑) 과 다리보
    for ry in (-2.4, 0.6):
        sp.box(x1 - 0.4, ry - 0.15, 3.85, rx1 - x1 + 0.55, 0.3, 0.3, Mat("#6a7079", 0.3), top=Mat("#8C939C", 0.3))
    cx = (4.2, 4.2, 3.6, 4.4, 4.0)[v]
    sp.box(cx - 0.2, -2.6, 4.15, 0.4, 3.4, 0.3, Mat("#C9553A", 0.1), top=Mat("#D9735A", 0.1))
    sp.box(cx - 0.25, -0.9, 3.85, 0.5, 0.5, 0.3, YELLOW)
    hook_z = 1.6 if v != 3 else 0.9
    sp.line((cx, -0.65, 3.85), (cx, -0.65, hook_z + 0.3), 0.05, "#9aa1aa")
    if v == 3:
        sp.box(cx - 0.5, -1.15, hook_z - 0.3, 1.0, 1.0, 0.6, Mat("#8C939C", 0.3))
    else:
        sp.polyline3([(cx - 0.12, -0.65, hook_z + 0.3), (cx - 0.12, -0.65, hook_z), (cx + 0.12, -0.65, hook_z + 0.1)],
                     "#5c626b", 0.08)
    sp.box(rx1 - 0.15, 0.45, 0.15, 0.3, 0.3, 3.85, Mat("#6a7079", 0.3))
    # 밖: 쇠막대 걸이와 상자
    for k in range(5):
        sp.line((3.2, 1.7 + k * 0.08, 0.35 + k * 0.03), (5.0, 1.7 + k * 0.08, 0.35 + k * 0.03), 0.09, "#9aa1aa")
    for x in (3.3, 4.9):
        sp.box(x - 0.08, 1.6, 0.15, 0.16, 0.5, 0.4, DARK)
    crate(sp, 3.4, 2.6, 0.9, ORANGE, 0.15)
    if v in (1, 4):
        crate(sp, 4.4, 2.7, 0.8, Mat("#C9A23A"), 0.15)
    if v == 4:
        antenna(sp, (-4.0, -1.0, zr - 0.6), 1.6)
    sp.lamp((x1 + 0.15, dy1 + 0.4, 3.1), AMBER, 10)
    sp.lamp((rx1, 0.6, 4.4), AMBER, 9)


@typed("electronics_fab", 10, 8, 4.4, "전자 부품 공장", heights=[4.4, 4.4, 4.2, 4.4, 4.6])
def electronics_fab(sp: Sprite, v: int):
    """흰 벽의 청정실 건물: 지붕에 공기 조화기, 푸른 유리창, 작은 에어록 현관."""
    sp.contact_shadow(0, 0, 5.4, 4.2, 0.45)
    sp.box(-4.8, -3.8, 0, 9.6, 7.6, 0.15, CONCRETE)
    white = Mat("#F2F1EC", 0.05)
    accent = (BLUE, BLUE, TEAL, Mat("#9B7AD6"), BLUE)[v]
    bglass = Mat("#2f5f9a", 0.8)
    x0, x1, y0, y1, h = -4.4, 2.6, -3.4, 2.6, 3.2
    # 질소 탱크 (뒤 오른쪽)
    _vtank(sp, 3.8, -2.6, 0.15, 2.2, 0.6, FROST, bands=[0.5], band_color="#9fb4c0")
    sp.box(x0, y0, 0.15, x1 - x0, y1 - y0, h - 0.15, white, top=Mat("#E2E2DE"))
    f = Sprite.box_faces(x0, y0, 0.15, x1 - x0, y1 - y0, h - 0.15)
    band_on(sp, f["left"], 0.88, 0.95, accent)
    band_on(sp, f["right"], 0.88, 0.95, accent)
    # 푸른 유리창 띠
    o, e1, e2 = f["left"]
    nwin = (3, 3, 1, 4, 2)[v]
    windows_row(sp, f["left"], nwin, 0.32, 0.7, 0.06, 0.04, "#a8d4ff") if nwin > 1 else None
    if nwin == 1:
        sp.window(sp.on_face(o, e1, e2, 0.06, 0.32, 0.94, 0.7), "#a8d4ff", glass=bglass)
    if nwin > 1:
        span = (1 - 0.12 - 0.04 * (nwin - 1)) / nwin
        for i in range(nwin):
            u0 = 0.06 + i * (span + 0.04)
            sp.window(sp.on_face(o, e1, e2, u0, 0.32, u0 + span, 0.7), "#a8d4ff", glass=bglass)
    o, e1, e2 = f["right"]
    sp.window(sp.on_face(o, e1, e2, 0.08, 0.4, 0.4, 0.68), "#a8d4ff", glass=bglass)
    # 지붕 공기 조화기 (뒤부터)
    units = [(-3.8, -2.8, 2.2, 1.6), (-0.9, -2.8, 2.2, 1.6)] if v != 2 else [(-3.8, -2.8, 4.8, 1.8)]
    if v == 4:
        units.append((-3.8, -0.4, 1.6, 1.4))
    for (ux, uy, uw, ud) in units:
        sp.box(ux, uy, h, uw, ud, 0.9, Mat("#C9CED4", 0.25), top=Mat("#B9C0C8", 0.3))
        uf = Sprite.box_faces(ux, uy, h, uw, ud, 0.9)
        sp.panel_grid(*uf["left"], 8, 1, "#8a9099", 0.45, 0.8)
        nf = max(1, int(uw / 1.1))
        for k in range(nf):
            fx = ux + uw * (k + 0.5) / nf
            sp.disc((fx, uy + ud / 2, h + 0.92), (0, 0, 1), min(0.45, ud * 0.3), CHAR)
            sp.ring3((fx, uy + ud / 2, h + 0.93), min(0.45, ud * 0.3), "#9aa1aa", 0.05)
    pipe(sp, [(-1.0, -1.2, h + 0.4), (1.6, -1.2, h + 0.4), (1.6, 0.6, h + 0.4)], 0.3, "#d9dde2")
    sp.box(1.2, 0.4, h, 0.8, 0.8, 0.6, STEEL)
    # 에어록 현관
    sp.box(x1, -0.9, 0.15, 1.1, 1.8, 2.3, white, top=Mat("#E2E2DE"))
    af = Sprite.box_faces(x1, -0.9, 0.15, 1.1, 1.8, 2.3)
    door(sp, af["right"], 0.25, 0.75, 0.82, Mat("#cfd6dc", 0.3), light=False)
    band_on(sp, af["right"], 0.88, 0.95, accent)
    sp.lamp((x1 + 1.15, 0.0, 2.3), CYAN_LIGHT, 9)
    # 가스병 걸이
    for k in range(4 if v != 3 else 3):
        sp.cyl((4.0 + k * 0.0, 0.9 + k * 0.4, 0.15), (4.0, 0.9 + k * 0.4, 1.5), 0.15,
               (GREEN, Mat("#C9CED4", 0.3), BLUE, Mat("#C9CED4", 0.3))[k])
    sp.line((4.0, 0.7, 1.2), (4.0, 2.4, 1.2), 0.06, "#7d848d")
    if v == 1:
        crate(sp, -3.8, 2.9, 0.7, Mat("#C9CED4", 0.3), 0.15)
        crate(sp, -2.9, 2.95, 0.6, Mat("#C9CED4", 0.3), 0.15)
    if v == 4:
        antenna(sp, (2.0, -2.8, h), 1.4)
    sp.lamp((x0 + 0.2, y1 + 0.1, 2.6), AMBER, 8)


@typed("foundry", 10, 8, 6.0, "주조소", heights=[6.0, 6.0, 6.4, 5.6, 6.0])
def foundry(sp: Sprite, v: int):
    """어두운 쇠 헛간과 그 앞의 빛나는 도가니로, 부어 놓은 주형 줄, 높은 배기 굴뚝."""
    sp.contact_shadow(0, 0, 5.4, 4.2, 0.5)
    sp.box(-4.8, -3.8, 0, 9.6, 7.6, 0.15, CONCRETE)
    shed = Mat("#5f646c", 0.2)
    band = (RED, RED, ORANGE, RED, YELLOW)[v]
    sx = (2.9, 2.9, 2.6, 3.3, -4.2)[v]
    sy = -2.7 if v != 4 else -2.9
    stack_h = (6.0, 6.0, 6.4, 5.6, 6.0)[v]
    # 굴뚝
    def stack():
        sp.cyl((sx, sy, 0.15), (sx, sy, stack_h), 0.42, Mat("#8C939C", 0.3), bands=[0.3, 0.6], cap_mat=CHAR)
        cyl_ring(sp, (sx, sy, 0.15), (sx, sy, stack_h), 0.42, 0.84, 0.9, RED)
        cyl_ring(sp, (sx, sy, 0.15), (sx, sy, stack_h), 0.42, 0.93, 0.98, WHITE)
        sp.lamp((sx, sy, stack_h + 0.15), "#ff5a3c", 6)
    if v == 4:
        stack()
    # 헛간 (외벽 + 외쪽 경사 지붕)
    x0, x1, y0, y1 = -3.9, 1.9, -3.5, -0.4
    sp.box(x0, y0, 0.15, x1 - x0, y1 - y0, 3.2, shed, top=shed)
    f = Sprite.box_faces(x0, y0, 0.15, x1 - x0, y1 - y0, 3.2)
    sp.panel_grid(*f["left"], 14, 1, "#4a4f57", 0.5, 0.9)
    band_on(sp, f["left"], 0.85, 0.93, band)
    sp.face([(x0 - 0.2, y0 - 0.2, 4.1), (x1 + 0.2, y0 - 0.2, 4.1), (x1 + 0.2, y1 + 0.3, 3.35), (x0 - 0.2, y1 + 0.3, 3.35)],
            Mat("#4a4f57", 0.2))
    sp.panel_grid((x0 - 0.2, y0 - 0.2, 4.1), (x1 - x0 + 0.4, 0, 0), (0, y1 - y0 + 0.5, -0.75), 14, 1, "#3a3f47", 0.45, 0.8)
    sp.face([(x1, y0, 3.35), (x1, y0, 4.0), (x1, y1, 3.35)][::-1], shed)
    # 열린 문: 안쪽 따뜻한 빛
    o, e1, e2 = f["left"]
    dpts = sp.on_face(o, e1, e2, 0.18, 0.0, 0.55, 0.72)
    sp.face(dpts, CHAR, normal=(0, 1, 0), ao=0)
    sp.light_poly([add(p, (0, 0.02, 0)) for p in dpts], "#ffb35c", 0.6)
    sp.glow(add(sp.on_face(o, e1, e2, 0.36, 0.3, 0.36, 0.3)[0], (0, 0.3, 0)), 20, HOT, 0.35)
    if v != 4:
        stack()
    # 도가니로와 후드
    fx, fy = -2.4, 1.0
    pipe(sp, [(fx, fy, 3.4), (fx, fy - 1.0, 4.2), (sx, sy, 4.2)], 0.36, "#8a9099")
    sp.cyl((fx, fy, 0.15), (fx, fy, 1.5), 1.0, FURNACE, bands=[0.4], cap_mat=Mat("#ff9a4a", 0.5))
    sp.mark_light(HOT)
    sp.ring3((fx, fy, 1.52), 0.75, "#ffd27a", 0.1)
    sp.glow((fx, fy, 1.7), 24, HOT, 0.75)
    for (x, y) in ((fx - 1.0, fy + 1.0), (fx + 1.0, fy + 1.0)):
        sp.line((x, y, 0.15), (x, y, 2.6), 0.1, "#7d848d")
    sp.frustum((fx, fy, 2.4), (fx, fy, 3.4), 1.25, 0.4, STEEL)
    # 주형 줄 (몇 개는 막 부어 빛난다)
    hot = ((0, 2), (0, 1), (1, 2, 3), (0,), (1, 3))[v]
    for k in range(4):
        mx = -0.4 + k * 1.15
        sp.box(mx, 2.3, 0.15, 0.9, 0.9, 0.45, CONCRETE, top=Mat("#8f8270"))
        if k in hot:
            sp.disc((mx + 0.45, 2.75, 0.61), (0, 0, 1), 0.25, Mat("#ff9a4a", 0.5))
            sp.mark_light(HOT)
            sp.glow((mx + 0.45, 2.75, 0.7), 10, HOT, 0.7)
        else:
            sp.disc((mx + 0.45, 2.75, 0.61), (0, 0, 1), 0.25, Mat("#9aa1aa", 0.5))
    # 부을 국자 (거치대)
    lx, ly = 0.6, 0.8
    sp.line((lx - 0.5, ly, 0.15), (lx - 0.5, ly, 1.4), 0.1, "#7d848d")
    sp.line((lx + 0.5, ly, 0.15), (lx + 0.5, ly, 1.4), 0.1, "#7d848d")
    sp.frustum((lx, ly, 0.75), (lx, ly, 1.35), 0.32, 0.45, DARK, cap_mat=Mat("#ff9a4a", 0.5))
    sp.mark_light(HOT)
    sp.glow((lx, ly, 1.4), 10, HOT, 0.6)
    # 주괴 더미
    if v in (1, 3):
        for k in range(3):
            sp.box(3.0, 0.6 + k * 0.0, 0.15 + k * 0.25, 1.4, 0.8, 0.25, Mat("#C2C7CD", 0.6))
    else:
        crate(sp, 3.2, 0.5, 0.9, Mat("#8C939C", 0.3), 0.15)
    sp.lamp((x1, y1 + 0.1, 3.0), AMBER, 9)
    sp.lamp((4.4, 3.4, 1.2), AMBER, 8)


# ── 로봇 정비 계열 ───────────────────────────────────────────────────

def _rover(sp: Sprite, x, y, s=1.0, body: Mat = WHITE, accent: Mat = ORANGE, z=0.0, mast=True):
    """작은 네 바퀴 로봇 (x 방향으로 놓임). (x, y)는 가운데."""
    L, W = 1.5 * s, 1.0 * s
    wr = 0.28 * s
    for wx in (x - L * 0.32, x + L * 0.32):
        sp.cyl((wx, y - W / 2 - 0.12 * s, z + wr), (wx, y - W / 2 + 0.06 * s, z + wr), wr, TRACK, cap_mat=STEEL)
    sp.box(x - L / 2, y - W / 2, z + wr * 0.9, L, W, 0.5 * s, body, top=SILVER)
    f = Sprite.box_faces(x - L / 2, y - W / 2, z + wr * 0.9, L, W, 0.5 * s)
    band_on(sp, f["left"], 0.15, 0.4, accent)
    sp.box(x - L * 0.35, y - W * 0.38, z + wr * 0.9 + 0.5 * s, L * 0.6, W * 0.76, 0.05 * s, SOLAR)
    if mast:
        sp.line((x + L * 0.38, y, z + wr * 0.9 + 0.5 * s), (x + L * 0.38, y, z + wr + 0.95 * s), 0.05 * s, "#9aa1aa")
        sp.box(x + L * 0.38 - 0.1 * s, y - 0.15 * s, z + wr + 0.95 * s, 0.2 * s, 0.3 * s, 0.14 * s, DARK)
    for wx in (x - L * 0.32, x + L * 0.32):
        sp.cyl((wx, y + W / 2 - 0.06 * s, z + wr), (wx, y + W / 2 + 0.12 * s, z + wr), wr, TRACK, cap_mat=STEEL)


@typed("robot_garage", 6, 5, 3.0, "로봇 차고", heights=[3.0, 3.0, 3.0, 3.2, 3.0])
def robot_garage(sp: Sprite, v: int):
    """옆이 트인 지붕만 있는 차고: 충전 기둥 둘과 쉬고 있는 작은 로봇."""
    sp.contact_shadow(0, 0, 3.1, 2.6, 0.4)
    sp.box(-2.9, -2.4, 0, 5.8, 4.8, 0.15, SINTER)
    sp.stripes((-2.9, 2.4, 0.15), (5.8, 0, 0), (0, -0.3, 0), n=14, normal=(0, 0, 1))
    canopy = (WHITE, WHITE, WHITE, Mat("#E07B39", 0.1), WHITE)[v]
    edge = ORANGE if v != 3 else WHITE
    posts = [(-2.6, -2.15), (0.0, -2.15), (2.6, -2.15), (-2.6, 2.15), (0.0, 2.15), (2.6, 2.15)]
    for (x, y) in posts[:3]:
        sp.line((x, y, 0.15), (x, y, 2.45), 0.14, "#8a9099")
    # 충전 기둥 (뒤)
    peds = [(-1.7, -1.55), (0.5, -1.55)] if v != 2 else [(-0.6, -1.55)]
    for (px, py) in peds:
        sp.box(px - 0.3, py - 0.3, 0.15, 0.6, 0.6, 1.1, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
        pf = Sprite.box_faces(px - 0.3, py - 0.3, 0.15, 0.6, 0.6, 1.1)
        sp.window(sp.on_face(*pf["left"], 0.2, 0.55, 0.8, 0.8), "#7CF29A", frame=None, glass=Mat("#2c8f4f", 0.4))
        sp.window(sp.on_face(*pf["right"], 0.2, 0.55, 0.8, 0.8), "#7CF29A", frame=None, glass=Mat("#2c8f4f", 0.4))
    # 로봇
    if v == 2:
        _rover(sp, -1.3, 0.4, 0.95, WHITE, ORANGE)
        _rover(sp, 1.3, 0.2, 0.95, WHITE, TEAL)
        pipe(sp, [(-0.6, -1.25, 0.7), (-0.6, 0.0, 0.3), (-1.0, 0.0, 0.3)], 0.06, "#2a2d33")
    else:
        rx, ry = (0.6, 0.35) if v != 4 else (-0.4, 0.5)
        _rover(sp, rx, ry, 1.1, WHITE, (ORANGE, ORANGE, ORANGE, YELLOW, BLUE)[v])
        pipe(sp, [(0.5, -1.25, 0.7), (0.5, -0.4, 0.3), (rx - 0.4, -0.3, 0.45)], 0.06, "#2a2d33")
    if v == 4:
        crate(sp, 1.4, 0.8, 0.8, ORANGE, 0.15)
        crate(sp, 1.6, -0.6, 0.6, Mat("#C9A23A"), 0.15)
    # 지붕
    n = 8
    prof = [(-2.35 + 4.7 * i / n, 2.3 + 0.75 * math.sin(math.pi * i / n)) for i in range(n + 1)]
    for i in range(n):
        (ya, za), (yb, zb) = prof[i], prof[i + 1]
        m = SOLAR if (v == 1 and i in (2, 3, 4, 5)) else canopy
        sp.face([(-2.8, ya, za), (2.8, ya, za), (2.8, yb, zb), (-2.8, yb, zb)][::-1], m, two_sided=True,
                back=Mat("#9aa1aa", 0.2), ao=0)
        if m is SOLAR:
            sp.panel_grid((-2.8, ya, za + 0.01), (5.6, 0, 0), (0, yb - ya, zb - za), 7, 1, "#6f86b0", 0.45, 0.6)
    for x in (-2.8, -0.93, 0.93, 2.8):
        sp.polyline3([(x, ya, za) for (ya, za) in prof], "#9aa1aa", 0.05)
    sp.polyline3([(-2.8, prof[-1][0], prof[-1][1]), (2.8, prof[-1][0], prof[-1][1])],
                 hexc(edge.albedo) if v != 1 else "#3FB8AF", 0.16)
    for (x, y) in posts[3:]:
        sp.line((x, y, 0.15), (x, y, 2.4), 0.14, "#8a9099")
    sp.lamp((2.6, 2.15, 2.3), AMBER, 9)
    sp.glow((0.0, 0.0, 1.8), 30, WARM_WINDOW, 0.3)


def _hopper_drone(sp: Sprite, x, y, z=0.12, s=1.0, foil: Mat = GOLD):
    """달 표면용 로켓 호퍼 드론: 금박 몸통, 벌린 다리 넷, 아래 엔진 종."""
    feet = [(x + dx * 0.75 * s, y + dy * 0.75 * s) for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1))]
    for (fx, fy) in feet[:2]:
        sp.line((fx, fy, z + 0.05), (x + (fx - x) * 0.45, y + (fy - y) * 0.45, z + 0.75 * s), 0.07, "#9aa1aa")
    sp.frustum((x, y, z + 0.55 * s), (x, y, z + 0.25 * s), 0.18 * s, 0.32 * s, DARK)
    sp.cyl((x, y, z + 0.55 * s), (x, y, z + 1.0 * s), 0.5 * s, foil, cap_mat=SILVER)
    for (tx, ty) in ((x - 0.15 * s, y - 0.5 * s), (x + 0.5 * s, y + 0.1 * s)):
        sp.sphere((tx, ty, z + 0.78 * s), 0.22 * s, WHITE)
    sp.box(x - 0.12 * s, y - 0.12 * s, z + 1.0 * s, 0.24 * s, 0.24 * s, 0.18 * s, DARK)
    for (fx, fy) in feet[2:]:
        sp.line((fx, fy, z + 0.05), (x + (fx - x) * 0.45, y + (fy - y) * 0.45, z + 0.75 * s), 0.07, "#9aa1aa")
    for (fx, fy) in feet:
        sp.disc((fx, fy, z + 0.05), (0, 0, 1), 0.12 * s, STEEL)
    sp.lamp((x, y, z + 1.25 * s), "#ff5a3c", 5)


def _small_pad(sp: Sprite, x, y, r, mark="X"):
    sp.cyl((x, y, 0.0), (x, y, 0.12), r, CONCRETE, cap_mat=Mat("#A89A84"))
    sp.ring3((x, y, 0.13), r * 0.75, "#E9C24A", 0.12, front_only=False)
    if mark == "X":
        d = r * 0.45
        sp.line((x - d, y - d, 0.13), (x + d, y + d, 0.13), 0.12, "#E9C24A")
        sp.line((x - d, y + d, 0.13), (x + d, y - d, 0.13), 0.12, "#E9C24A")
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        sp.lamp((x + r * 0.95 * math.cos(a), y + r * 0.95 * math.sin(a), 0.16), AMBER, 6)


@typed("drone_hangar", 10, 8, 4.0, "드론 격납고", heights=[3.4, 3.4, 3.4, 3.8, 3.4])
def drone_hangar(sp: Sprite, v: int):
    """지붕 판을 뒤 레일 위로 밀어 연 낮은 격납고 (안에 승강대 위 드론) 와 옆 패드의 작은 호퍼 드론들."""
    sp.contact_shadow(0, 0, 5.4, 4.2, 0.45)
    sp.box(-4.8, -3.8, 0, 9.6, 7.6, 0.12, SINTER)
    wall = Mat("#C9CED4", 0.2)
    x0, x1, y0, y1, zt, t = -4.4, 0.6, -2.6, 1.0, 2.6, 0.2
    open_y = (-2.0, -2.0, -2.3, -1.6, -2.0)[v]       # 닫힌 쪽 끝 (그 앞이 열려 있다)
    pads = [(3.3, -2.35, 1.3), (3.3, 1.2, 1.3)] + ([(-2.4, 2.75, 1.05)] if v in (0, 3) else [])
    filled = ((0, 2), (0, 1), (1,), (0, 1, 2), (0,))[v]
    # 레일 뒤 연장 기둥
    for x in (x0 + 0.1, x1 - 0.1):
        sp.line((x, -3.75, 0.12), (x, -3.75, zt), 0.14, "#8a9099")
    # 안쪽: 뒤·왼쪽 벽 (안쪽 면), 바닥, 승강대 위 드론
    sp.box(x0, y0, 0.12, x1 - x0, t, zt - 0.12, wall, top=Mat("#B9C0C8", 0.2))
    sp.box(x0, y0 + t, 0.12, t, y1 - y0 - t, zt - 0.12, wall, top=Mat("#B9C0C8", 0.2))
    floor = [(x0 + t, y0 + t, 0.14), (x1 - t, y0 + t, 0.14), (x1 - t, y1 - t, 0.14), (x0 + t, y1 - t, 0.14)]
    sp.face(floor, Mat("#4a4f57"), normal=(0, 0, 1), ao=0)
    sp.light_poly(floor, "#ffcf8a", 0.45)
    lx, ly = -1.9, -0.75
    lift_z = (0.9, 0.9, 1.2, 0.6, 0.9)[v]
    sp.box(lx - 1.0, ly - 0.95, 0.14, 2.0, 1.9, lift_z - 0.14, Mat("#5c626b", 0.3), top=Mat("#7d848d", 0.3))
    sp.stripes((lx + 1.0, ly + 0.95, lift_z), (-2.0, 0, 0), (0, 0, -0.15), n=8)
    _hopper_drone(sp, lx, ly, lift_z, 0.95)
    if v == 2:
        crate(sp, -4.0, 0.0, 0.6, ORANGE, 0.14)
    # 앞·오른쪽 벽 (바깥 면)
    sp.box(x0, y1 - t, 0.12, x1 - x0, t, zt - 0.12, wall, top=Mat("#B9C0C8", 0.2))
    fl = Sprite.box_faces(x0, y1 - t, 0.12, x1 - x0, t, zt - 0.12)
    sp.panel_grid(*fl["left"], 14, 1, "#a3a9b0", 0.45, 0.8)
    sp.stripes(add(fl["left"][0], (0, 0.01, zt - 0.42)), (-(x1 - x0), 0, 0), (0, 0, 0.28), n=18, normal=(0, 1, 0))
    windows_row(sp, fl["left"], 3, 0.35, 0.6, 0.45, 0.06)
    sp.box(x1 - t, y0 + t, 0.12, t, y1 - y0 - 2 * t, zt - 0.12, wall, top=Mat("#B9C0C8", 0.2))
    fr = Sprite.box_faces(x1 - t, y0 + t, 0.12, t, y1 - y0 - 2 * t, zt - 0.12)
    sp.panel_grid(*fr["right"], 10, 1, "#a3a9b0", 0.45, 0.8)
    sp.stripes(add(fr["right"][0], (0.01, 0, zt - 0.42)), (0, y1 - y0 - 2 * t, 0), (0, 0, 0.28), n=12, normal=(1, 0, 0))
    door(sp, fr["right"], 0.55, 0.85, 0.75, Mat("#8C939C", 0.3))
    # 미닫이 지붕: 레일과 뒤로 밀린 판 둘
    for x in (x0 - 0.05, x1 - 0.15):
        sp.box(x, -3.9, zt, 0.2, y1 + 3.9, 0.14, STEEL)
    sp.box(x0 - 0.1, -3.9, zt + 0.14, x1 - x0 + 0.2, open_y + 3.9, 0.14, Mat("#B9C0C8", 0.3))
    sp.box(x0 - 0.05, -3.75, zt + 0.28, x1 - x0 + 0.1, open_y + 3.75 + 0.1, 0.14, WHITE, top=Mat("#E2E2DE"))
    sp.panel_grid((x0 - 0.05, -3.75, zt + 0.42), (x1 - x0 + 0.1, 0, 0), (0, open_y + 3.85, 0), 6, 1, "#b9b4a8", 0.45, 0.8)
    if v == 3:
        antenna(sp, (x0 + 0.3, -3.4, zt + 0.42), 1.0)
    for i, (px, py, pr) in enumerate(pads):
        _small_pad(sp, px, py, pr)
        if i in filled:
            _hopper_drone(sp, px, py, 0.13, 1.05 if pr > 1.2 else 0.85, GOLD if i != 1 or v != 4 else SILVER)
    if v in (1, 4):
        _vtank(sp, 1.6, -3.2, 0.12, 1.4, 0.45, WHITE, bands=[0.5], band_color="#d8853b")
        pipe(sp, [(1.6, -2.75, 0.5), (2.2, -2.4, 0.2)], 0.08, "#3a3f47")
    sp.lamp((x1 + 0.1, y1 + 0.1, zt), AMBER, 9)
    sp.lamp((x0, y1 + 0.1, zt), AMBER, 9)


@typed("teleop_center", 8, 6, 4.6, "원격 조종실", heights=[4.6, 4.6, 4.6, 4.4, 4.6])
def teleop_center(sp: Sprite, v: int):
    """화면이 가득 보이는 조종실 모듈과 하늘을 향한 큰 접시 안테나."""
    sp.contact_shadow(0, 0, 4.2, 3.2, 0.45)
    sp.box(-3.9, -2.9, 0, 7.8, 5.8, 0.15, SINTER)
    band = (TEAL, TEAL, ORANGE, BLUE, TEAL)[v]
    dish_left = v == 3
    dx, dy = (2.4, -1.3) if not dish_left else (-2.6, -1.6)
    # 큰 접시 (뒤)
    def dish():
        sp.box(dx - 0.5, dy - 0.5, 0.15, 1.0, 1.0, 0.5, CONCRETE)
        sp.cyl((dx, dy, 0.65), (dx, dy, 2.6), 0.22, STEEL)
        sp.box(dx - 0.3, dy - 0.3, 2.3, 0.6, 0.6, 0.45, DARK)
        sp.cyl((dx, dy, 2.75), (dx, dy, 3.2), 0.15, STEEL, edge=False)
        c = (dx, dy, 3.25)
        n = norm((0.35, 0.55, 0.75))
        r = 1.45 if v != 4 else 1.25
        sp.disc(c, n, r, WHITE, back=STEEL, seg=40)
        sp.ring3(c, r, "#b9b2a5", 0.09, normal=n, front_only=False)
        sp.ring3(c, r * 0.6, "#d8d2c6", 0.05, normal=n, front_only=False)
        feed = add(c, mul(n, 1.0))
        u, w = basis(n)
        for a in (0, 120, 240):
            rim = add(c, add(mul(u, r * 0.9 * math.cos(math.radians(a))), mul(w, r * 0.9 * math.sin(math.radians(a)))))
            sp.line(rim, feed, 0.05, "#8a9099")
        sp.sphere(feed, 0.16, GOLD)
    if not dish_left:
        dish()
    x0, x1, y0, y1, z0, z1 = -3.5, 1.2, -2.4, 1.6, 0.15, 2.9
    if dish_left:
        x0, x1 = -1.6, 3.3
        dish()
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, z1 - z0, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, z0, x1 - x0, y1 - y0, z1 - z0)
    band_on(sp, f["left"], 0.86, 0.94, band)
    band_on(sp, f["right"], 0.86, 0.94, band)
    # 큰 창 안의 화면들
    scr = ("#7FE3DA", "#9BEA7A", "#7fb6ff", "#FFC56E")
    o, e1, e2 = f["left"]
    sp.window(sp.on_face(o, e1, e2, 0.05, 0.3, 0.72, 0.78), "#4a6a80", frame="#2a2f36", glass=Mat("#1a2530", 0.8),
              light_alpha=0.6)
    cols = 6 if v != 1 else 5
    for r in range(2):
        for k in range(cols):
            u0 = 0.08 + k * (0.61 / cols)
            v0 = 0.36 + r * 0.2
            c = scr[(k + r * 2 + v) % 4]
            sp.window(sp.on_face(o, e1, e2, u0, v0, u0 + 0.61 / cols - 0.02, v0 + 0.15), c, frame="#1a1d22",
                      glass=Mat(c, 0.3), light_alpha=0.9)
    door(sp, f["left"], 0.78, 0.92, 0.7, Mat("#8C939C", 0.3))
    o, e1, e2 = f["right"]
    sp.window(sp.on_face(o, e1, e2, 0.1, 0.35, 0.9, 0.75), "#4a6a80", frame="#2a2f36", glass=Mat("#1a2530", 0.8),
              light_alpha=0.6)
    for k in range(4):
        u0 = 0.14 + k * 0.19
        c = scr[(k + 1 + v) % 4]
        sp.window(sp.on_face(o, e1, e2, u0, 0.42, u0 + 0.16, 0.66), c, frame="#1a1d22", glass=Mat(c, 0.3),
                  light_alpha=0.9)
    # 지붕 장비
    sp.box(x0 + 0.4, y0 + 0.4, z1, 1.2, 1.0, 0.45, STEEL)
    antenna(sp, (x0 + 2.4, y0 + 0.5, z1), 1.5)
    if v in (2, 4):
        o2, a2, b2 = (x0 + 0.3, y0 + 1.7, z1 + 0.2), (2.6, 0, 0), (0, 1.8, 0.3)
        sp.quad(o2, a2, b2, SOLAR, back=STEEL)
        sp.panel_grid(o2, a2, b2, 4, 2, "#6f86b0", 0.45, 0.6)
    if v == 1:
        sp.disc((x1 - 0.6, y1 - 0.6, z1 + 0.7), norm((0.3, 0.6, 0.75)), 0.5, WHITE, back=STEEL)
        sp.line((x1 - 0.6, y1 - 0.6, z1), (x1 - 0.6, y1 - 0.6, z1 + 0.68), 0.06, "#8a9099")
    sp.lamp((x1, y1 + 0.1, 2.5), AMBER, 8)


@typed("robot_depot", 14, 10, 6.0, "대형 정비 기지", heights=[6.0, 6.0, 6.0, 6.0, 6.4])
def robot_depot(sp: Sprite, v: int):
    """큰 정비동의 열린 칸마다 로봇, 앞마당의 문형 크레인, 밖에 선 부품 선반."""
    sp.contact_shadow(0, 0, 7.2, 5.2, 0.5)
    sp.box(-6.8, -4.8, 0, 13.6, 9.6, 0.15, SINTER)
    band = (ORANGE, ORANGE, YELLOW, TEAL, ORANGE)[v]
    hall = Mat("#DAD3C4")
    x0, x1, y0, y1, h = -6.4, 2.6, -4.4, 0.8, 4.4
    sp.box(x0, y0, 0.15, x1 - x0, y1 - y0, h - 0.15, hall, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.15, x1 - x0, y1 - y0, h - 0.15)
    band_on(sp, f["left"], 0.88, 0.95, band)
    band_on(sp, f["right"], 0.88, 0.95, band)
    o, e1, e2 = f["left"]
    nb = 3 if v != 2 else 4
    bays = []
    for k in range(nb):
        u0 = 0.05 + k * (0.92 / nb)
        u1 = u0 + 0.92 / nb - 0.05
        pts = sp.on_face(o, e1, e2, u0, 0.0, u1, 0.62)
        sp.face(pts, CHAR, normal=(0, 1, 0), ao=0)
        sp.light_poly([add(p, (0, 0.02, 0)) for p in pts], "#ffcf8a", 0.5)
        sp.stripes(add(sp.on_face(o, e1, e2, u0, 0.62, u1, 0.7)[0], (0, 0.01, 0)), mul(e1, u1 - u0), (0, 0, 0.3), n=8,
                   normal=(0, 1, 0))
        bays.append((x1 - (x1 - x0) * (u0 + u1) / 2))
    # 칸 안의 로봇 (문 바로 안쪽)
    for k, bx in enumerate(bays):
        if (k + v) % 4 == 3:
            continue
        _rover(sp, bx, y1 - 0.75, 1.0, WHITE, (ORANGE, TEAL, YELLOW)[k % 3])
    o, e1, e2 = f["right"]
    windows_row(sp, f["right"], 3, 0.45, 0.65, 0.12, 0.08)
    door(sp, f["right"], 0.08, 0.22, 0.5, Mat("#8C939C", 0.3))
    # 지붕 장비
    if v in (1, 4):
        for k in range(3):
            o2, a2, b2 = (x0 + 0.6 + k * 2.6, y0 + 0.6, h + 0.2), (2.2, 0, 0), (0, 3.6, 0.6)
            sp.quad(o2, a2, b2, SOLAR, back=STEEL)
            sp.panel_grid(o2, a2, b2, 3, 4, "#6f86b0", 0.45, 0.6)
    else:
        sp.box(x0 + 1.0, y0 + 1.0, h, 2.0, 1.6, 0.6, STEEL)
        sp.box(x0 + 4.0, y0 + 1.0, h, 1.2, 1.2, 0.4, STEEL)
    if v == 4:
        antenna(sp, (x1 - 0.6, y0 + 0.6, h), 1.8)
    # 앞마당 크레인: 레일 둘, 다리 넷, 다리보, 매단 로봇
    gx = (-2.2, -2.2, -3.6, -0.6, -2.2)[v]
    ry0, ry1 = 1.3, 4.3
    for ry in (ry0, ry1):
        sp.box(-6.4, ry - 0.12, 0.15, 9.0, 0.24, 0.12, STEEL)
    for ry in (ry0,):
        for lx in (gx - 1.0, gx + 1.0):
            sp.box(lx - 0.18, ry - 0.18, 0.27, 0.36, 0.36, 5.2, YELLOW)
    for lx in (gx - 1.0, gx + 1.0):
        sp.box(lx - 0.22, ry0 - 0.3, 5.45, 0.44, ry1 - ry0 + 0.6, 0.5, YELLOW, top=Mat("#F0D27A"))
    sp.box(gx - 1.1, 2.35, 5.5, 2.2, 0.9, 0.55, ORANGE, top=Mat("#E9965E"))
    sp.box(gx - 0.4, 2.45, 5.05, 0.8, 0.7, 0.45, DARK)
    lift = (1.4, 1.4, 0.0, 2.2, 1.4)[v]
    sp.line((gx, 2.8, 5.0), (gx, 2.8, lift + 1.4), 0.05, "#9aa1aa")
    for dxx in (-0.5, 0.5):
        sp.line((gx, 2.8, lift + 1.4), (gx + dxx, 2.8, lift + 0.9), 0.04, "#9aa1aa")
    _rover(sp, gx, 2.8, 1.1, WHITE, ORANGE, z=lift)
    for lx in (gx - 1.0, gx + 1.0):
        sp.box(lx - 0.18, ry1 - 0.18, 0.27, 0.36, 0.36, 5.2, YELLOW)
    sp.lamp((gx + 1.0, ry1, 5.7), AMBER, 10)
    # 부품 선반 (밖, 오른쪽)
    for (rx, ry) in ((4.2, -3.6), (4.2, -0.6)) if v != 3 else ((4.2, -3.6),):
        for (px, py) in ((rx, ry), (rx + 2.2, ry)):
            sp.line((px, py, 0.15), (px, py, 2.6), 0.08, "#7d848d")
        for z in (0.5, 1.4, 2.3):
            sp.box(rx, ry, z, 2.2, 1.0, 0.08, Mat("#8C939C", 0.3))
        for k in range(3):
            crate(sp, rx + 0.15 + k * 0.7, ry + 0.2, 0.55, (ORANGE, Mat("#C9A23A"), STEEL)[(k + v) % 3], 0.58)
        sp.cyl((rx + 0.6, ry + 0.1, 1.85), (rx + 0.6, ry + 0.4, 1.85), 0.35, TRACK, cap_mat=STEEL)
        sp.cyl((rx + 1.5, ry + 0.1, 1.85), (rx + 1.5, ry + 0.4, 1.85), 0.35, TRACK, cap_mat=STEEL)
        sp.box(rx + 0.2, ry + 0.2, 2.38, 1.8, 0.6, 0.3, WHITE)
        for (px, py) in ((rx, ry + 1.0), (rx + 2.2, ry + 1.0)):
            sp.line((px, py, 0.15), (px, py, 2.6), 0.08, "#7d848d")
    if v == 3:
        _rover(sp, 5.2, 0.4, 1.0, WHITE, TEAL)
    sp.lamp((x1 + 0.1, y1 + 0.1, 4.0), AMBER, 10)
    sp.lamp((6.5, 3.6, 1.4), AMBER, 9)


# ── 추진제 계열 ──────────────────────────────────────────────────────

def _frost_pipe(sp: Sprite, pts, w=0.2):
    """서리 앉은 극저온 관."""
    sp.polyline3(pts, "#9fb4c0", w + 0.1)
    sp.polyline3(pts, "#eef4f7", w)


@typed("liquefier", 6, 5, 5.0, "소형 액화기", heights=[5.0, 5.0, 5.0, 5.0, 5.2])
def liquefier(sp: Sprite, v: int):
    """작은 냉각 상자: 위에 극저온 냉동기와 방열판, 서리가 앉은 탱크 하나."""
    sp.contact_shadow(0, 0, 3.2, 2.7, 0.5)
    _pad(sp, 6, 5)
    band = (BLUE, BLUE, Mat("#D9893F", 0.1), BLUE, TEAL)[v]
    # 냉각 상자
    x0, y0, x1, y1, h = -2.5, -2.0, 0.1, 0.5, 3.7
    sp.box(x0, y0, 0.3, x1 - x0, y1 - y0, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.3, x1 - x0, y1 - y0, h)
    band_on(sp, f["left"], 0.84, 0.92, band)
    band_on(sp, f["right"], 0.84, 0.92, band)
    band_on(sp, f["left"], 0.0, 0.16, FROST)
    band_on(sp, f["right"], 0.0, 0.16, FROST)
    sp.panel_grid(*f["left"], 3, 1, "#c9c3b6", 0.45, 0.8)
    sp.window(sp.on_face(*f["left"], 0.6, 0.5, 0.88, 0.66), "#9fd8ff")
    o, e1, e2 = f["right"]
    sp.face(sp.on_face(o, e1, e2, 0.2, 0.25, 0.8, 0.55), STEEL, normal=(1, 0, 0), ao=0)
    for k in range(3):
        sp.face(sp.on_face(o, e1, e2, 0.28, 0.3 + k * 0.08, 0.72, 0.33 + k * 0.08), DARK, normal=(1, 0, 0), ao=0, edge=False)
    # 위: 냉동기 머리와 방열판
    zt = 0.3 + h
    rad = (-2.35, -1.95) if v != 3 else (-2.35, 0.35)
    o2, a2, b2 = (rad[0], rad[1], zt), (2.2, 0, 0), (0, 0, 1.15)
    sp.quad(o2, a2, b2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o2, a2, b2, 6, 1, "#b9bec4", 0.5, 0.7)
    heads = [(-1.6, -0.6)] if v != 4 else [(-1.9, -0.4), (-0.8, -0.4)]
    for (hx, hy) in heads:
        sp.cyl((hx, hy, zt), (hx, hy, zt + 0.35), 0.45, STEEL, cap_mat=DARK)
        sp.cyl((hx, hy, zt + 0.35), (hx, hy, zt + 0.95), 0.25, SILVER, bands=[0.25, 0.5, 0.75], band_color="#7d848d")
    sp.box(-0.7, -1.7, zt, 0.7, 0.9, 0.5, STEEL)
    # 서리 앉은 탱크
    tx, ty = 1.6, 0.6
    sp.ellipsoid((tx, ty, 0.3), 1.1, 1.0, 0.12, ICE, clip_z=0.3)
    if v == 1:
        legs(sp, [(tx - 0.6, ty - 0.6, 1.4), (tx + 0.6, ty - 0.6, 1.4), (tx - 0.6, ty + 0.6, 1.4), (tx + 0.6, ty + 0.6, 1.4)], 0.3)
        sp.sphere((tx, ty, 2.0), 0.95, FROST)
        sp.ring3((tx, ty, 2.0), 0.96, "#3E6FB0", 0.1)
        top_z = 2.95
    else:
        _vtank(sp, tx, ty, 0.3, 2.3, 0.8, FROST, bands=[0.33, 0.66], band_color="#b5c6cf")
        cyl_ring(sp, (tx, ty, 0.3), (tx, ty, 2.6), 0.8, 0.8, 0.88, band)
        top_z = 3.1
    _frost_pipe(sp, [(x1, -0.4, 1.5), (tx, -0.4, 1.5), (tx, ty - 0.6, 1.5)], 0.18)
    _frost_pipe(sp, [(x1, 0.2, 2.6), (tx - 0.4, 0.2, top_z - 0.1)], 0.14)
    sp.ellipsoid((tx + 0.3, ty + 0.9, 0.3), 0.5, 0.35, 0.1, ICE, clip_z=0.3)
    if v == 2:
        crate(sp, 1.0, -2.2, 0.7, ORANGE, 0.3)
    sp.lamp((x1 + 0.05, y1 + 0.05, 3.6), CYAN_LIGHT, 8)
    sp.lamp((tx, ty, top_z + 0.2), "#ff5a3c", 6)


@typed("large_propellant_plant", 14, 10, 11.0, "대형 추진제 공장", heights=[11.0, 11.0, 10.4, 11.0, 11.4])
def large_propellant_plant(sp: Sprite, v: int):
    """키 큰 탱크 여럿, 액화 탑, 관 걸이 — 산소·수소를 대량으로 만들어 얼린다."""
    sp.contact_shadow(0, 0, 7.4, 5.2, 0.5)
    _pad(sp, 14, 10)
    lox, lh2 = FROST, FOAM
    tanks = ((-5.6, lox, 8.4), (-3.2, lox, 8.8), (-0.8, lh2, 9.2), (1.6, lh2, 8.0))
    if v == 1:
        tanks = ((-5.6, lh2, 8.0), (-3.2, lox, 9.2), (-0.8, lox, 9.2), (1.6, lh2, 8.4))
    ty, tr = -3.25, 1.15
    tower_x = 4.6 if v != 3 else -6.0
    # 액화 탑 (뒤 왼쪽 판이면 먼저)
    def tower():
        tx = tower_x
        sp.box(tx - 0.9, -3.9, 0.3, 1.8, 1.8, 9.6, WHITE, top=SILVER)
        f = Sprite.box_faces(tx - 0.9, -3.9, 0.3, 1.8, 1.8, 9.6)
        for vv in (0.3, 0.62, 0.9):
            band_on(sp, f["left"], vv, vv + 0.03, BLUE)
            band_on(sp, f["right"], vv, vv + 0.03, BLUE)
        sp.panel_grid(*f["left"], 2, 10, "#c9c3b6", 0.45, 0.8)
        sp.window(sp.on_face(*f["left"], 0.25, 0.08, 0.75, 0.14), "#9fd8ff")
        sp.cyl((tx, -3.0, 9.9), (tx, -3.0, 10.5), 0.5, STEEL, cap_mat=DARK)
        sp.cyl((tx, -3.0, 10.5), (tx, -3.0, 11.0), 0.28, SILVER, bands=[0.5])
        o2, a2, b2 = (tx + 0.9, -3.8, 6.0), (0, 1.6, 0), (1.2, 0, 3.4)
        if tx + 2.1 <= 6.9:
            sp.quad(o2, a2, b2, RADIATOR, back=RADIATOR)
            sp.panel_grid(o2, a2, b2, 1, 6, "#b9bec4", 0.5, 0.7)
        sp.lamp((tx, -3.0, 11.15), "#ff5a3c", 7)
    if tower_x < 0:
        tower()
    for (x, m, h) in tanks:
        if v == 2 and x == 1.6:
            legs(sp, [(x - 0.8, ty - 0.8, 2.0), (x + 0.8, ty - 0.8, 2.0), (x - 0.8, ty + 0.8, 2.0), (x + 0.8, ty + 0.8, 2.0)], 0.3)
            sp.sphere((x, ty, 2.8), 1.3, m)
            sp.ring3((x, ty, 2.8), 1.31, "#a45a1c", 0.08)
            continue
        sp.cyl((x, ty, 0.3), (x, ty, h), tr, m, bands=[0.2, 0.4, 0.6, 0.8],
               band_color="#b5c6cf" if m is lox else "#a45a1c")
        sp.sphere((x, ty, h), tr, m, clip_z=h)
    if tower_x > 0:
        tower()
    # 관 걸이 (세 줄)
    py = -0.9
    for x in (-6.2, -3.8, -1.4, 1.0, 3.4):
        for yy in (py - 0.35, py + 0.35):
            sp.line((x, yy, 0.3), (x, yy, 2.6), 0.1, "#7d848d")
        sp.line((x, py - 0.4, 2.6), (x, py + 0.4, 2.6), 0.12, "#7d848d")
    for k, (col, w) in enumerate((("#eef4f7", 0.22), ("#7fb6ff", 0.18), ("#e0a060", 0.18))):
        yy = py - 0.25 + k * 0.25
        pipe(sp, [(-6.4, yy, 2.75), (5.4, yy, 2.75)], w, col)
    for (x, m, h) in tanks:
        pipe(sp, [(x, ty + tr, 1.4), (x, py - 0.25, 1.4), (x, py - 0.25, 2.65)], 0.14,
             "#eef4f7" if m is lox else "#e0a060")
    # 앞: 처리동, 방열판, 조종함
    sp.box(-6.4, 1.0, 0.3, 4.8, 3.2, 2.8, WHITE, top=SILVER)
    f = Sprite.box_faces(-6.4, 1.0, 0.3, 4.8, 3.2, 2.8)
    band_on(sp, f["left"], 0.82, 0.9, BLUE)
    windows_row(sp, f["left"], 4, 0.4, 0.64, 0.08, 0.06)
    door(sp, f["right"], 0.35, 0.7, 0.7)
    for k, yy in enumerate((1.5, 3.0) if v != 3 else (1.5, 2.6, 3.7)):
        o, e1, e2 = (-0.6, yy, 0.3), (4.8, 0, 0), (0, 0, 2.6)
        sp.line((-0.5, yy, 0.3), (-0.5, yy, 2.9), 0.1, "#7d848d")
        sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
        sp.panel_grid(o, e1, e2, 8, 1, "#b9bec4", 0.5, 0.7)
    if v == 4:
        sp.cyl((5.8, 3.4, 0.3), (5.8, 3.4, 6.0), 0.18, STEEL)
        sp.lamp((5.8, 3.4, 6.2), "#ff5a3c", 6)
    sp.box(5.0, 1.6, 0.3, 1.4, 1.2, 1.6, WHITE, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(5.0, 1.6, 0.3, 1.4, 1.2, 1.6)["left"], 0.2, 0.45, 0.8, 0.75), "#9fd8ff")
    sp.lamp((-3.2, ty, 9.0 if v != 1 else 9.4), "#ff5a3c", 6)
    sp.lamp((6.4, 4.4, 1.2), AMBER, 9)
    sp.lamp((-1.6, 4.3, 2.6), AMBER, 9)


@typed("boiloff_depot", 10, 8, 7.0, "무증발 저장소", heights=[7.0, 7.0, 6.6, 7.0, 7.0])
def boiloff_depot(sp: Sprite, v: int):
    """받침 위에 누운 아주 큰 흰 단열 탱크 하나, 위에 햇빛 가림막, 끝에 극저온 냉동기."""
    sp.contact_shadow(0, 0, 5.3, 4.2, 0.5)
    sp.box(-4.8, -3.8, 0, 9.6, 7.6, 0.2, CONCRETE)
    shield = (Mat("#D9B45A", 0.5), Mat("#D9B45A", 0.5), SILVER, Mat("#D9B45A", 0.5), Mat("#C9CED4", 0.4))[v]
    band = (BLUE, Mat("#D9893F", 0.1), BLUE, BLUE, TEAL)[v]
    r = 2.15
    cz = 0.25 + r + 0.35
    xa, xb = -2.4, 1.6
    # 받침 (뒤 반은 탱크에 가린다)
    for x in (-2.0, 0.0, 2.0) if v != 2 else (-1.6, 1.6):
        sp.box(x - 0.35, -1.7, 0.2, 0.7, 3.4, 1.1, CONCRETE, top=Mat("#b3a690"))
    sp.ellipsoid((xa, 0, cz), 1.25, r, r, WHITE)
    sp.cyl((xa, 0, cz), (xb, 0, cz), r, WHITE, bands=[0.25, 0.5, 0.75], band_color="#c9c3b6", caps=False)
    cyl_ring(sp, (xa, 0, cz), (xb, 0, cz), r, 0.1, 0.16, band)
    sp.ellipsoid((xb, 0, cz), 1.25, r, r, WHITE)
    sp.ring3((xb + 0.02, 0, cz), r * 0.98, "#c9c3b6", 0.06, normal=(1, 0, 0))
    # 냉동기 + 방열판 (끝)
    cx0 = xb + 1.35
    sp.box(cx0, -1.9, 0.2, 1.0, 1.2, 1.5, STEEL, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(cx0, -1.9, 0.2, 1.0, 1.2, 1.5)["right"], 0.2, 0.5, 0.8, 0.75), "#9fd8ff")
    _frost_pipe(sp, [(xb + 0.9, -0.9, cz - 0.6), (cx0 + 0.5, -1.3, 1.7)], 0.16)
    if v != 3:
        o, e1, e2 = (cx0 + 0.1, 0.2, 0.2), (0, 2.6, 0), (0, 0, 2.6)
    else:
        o, e1, e2 = (-4.6, 2.9, 0.2), (3.0, 0, 0), (0, 0, 2.4)
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, 6, 1, "#b9bec4", 0.5, 0.7)
    # 햇빛 가림막: 해 쪽(+y)이 낮게 기울인 판, 기둥 넷
    zb, zf = (6.9, 5.9) if v != 4 else (6.4, 6.4)
    post_pts = [(-4.4, -3.0), (3.6, -3.0), (-4.4, 3.0), (3.6, 3.0)]
    for (x, y) in post_pts[:2]:
        sp.line((x, y, 0.2), (x, y, zb), 0.12, "#8a9099")
    o, e1, e2 = (-4.6, -3.2, zb), (8.4, 0, 0), (0, 6.4, zf - zb)
    sp.quad(o, e1, e2, shield, back=Mat("#8a7a52", 0.3) if shield is not SILVER else STEEL)
    sp.panel_grid(o, e1, e2, 6, 4, "#a8853a" if shield is not SILVER else "#8a9099", 0.5, 0.8)
    for (x, y) in post_pts[2:]:
        sp.line((x, y, 0.2), (x, y, zf), 0.12, "#8a9099")
    sp.lamp((3.6, 3.0, zf + 0.2), AMBER, 9)
    sp.lamp((-4.4, 3.0, zf + 0.2), AMBER, 9)
    if v == 1:
        antenna(sp, (cx0 + 0.5, -1.3, 1.7), 1.4)


@typed("launch_fueler", 7, 7, 14.0, "발사대 급유탑", heights=[14.0, 14.0, 13.0, 14.0, 14.0])
def launch_fueler(sp: Sprite, v: int):
    """높은 붉은 격자 정비탑: 연료 팔과 늘어진 탯줄 호스, 밑동에 작은 탱크들."""
    sp.contact_shadow(-0.3, -0.3, 3.6, 3.6, 0.5)
    sp.box(-3.4, -3.4, 0, 6.8, 6.8, 0.3, CONCRETE, top=Mat("#b3a690"))
    sp.stripes((3.4, 3.4, 0.3), (-6.8, 0, 0), (0, -0.35, 0), n=16, normal=(0, 0, 1))
    red = "#C9553A"
    cx, cy, hw = -1.6, -1.6, 0.9
    H = 13.2 if v != 2 else 12.2
    # 뒤 기둥
    for (x, y) in ((cx - hw, cy - hw), (cx + hw, cy - hw), (cx - hw, cy + hw)):
        sp.line((x, y, 0.3), (x, y, H), 0.16, red)
    # 탑 안: 승강기와 관
    sp.box(cx - 0.45, cy - 0.45, 4.6 if v != 3 else 8.0, 0.9, 0.9, 1.3, WHITE, top=SILVER)
    pipe(sp, [(cx + 0.3, cy + 0.6, 0.3), (cx + 0.3, cy + 0.6, H - 2.4)], 0.16, "#eef4f7")
    pipe(sp, [(cx + 0.6, cy + 0.3, 0.3), (cx + 0.6, cy + 0.3, H - 2.4)], 0.16, "#e0a060")
    # 발판 층
    for z in [z for z in (3.3, 6.3, 9.3, 12.3) if z < H - 0.5] + [H]:
        sp.box(cx - hw - 0.15, cy - hw - 0.15, z, 2 * hw + 0.3, 2 * hw + 0.3, 0.15, Mat("#8C939C", 0.3))
    # 앞 기둥과 가새 (보이는 두 면)
    sp.line((cx + hw, cy + hw, 0.3), (cx + hw, cy + hw, H), 0.16, red)
    n = int(H / 1.5)
    for k in range(n):
        za, zb = 0.3 + k * (H - 0.3) / n, 0.3 + (k + 1) * (H - 0.3) / n
        if k % 2 == 0:
            sp.line((cx + hw, cy - hw, za), (cx + hw, cy + hw, zb), 0.08, red)
            sp.line((cx - hw, cy + hw, za), (cx + hw, cy + hw, zb), 0.08, red)
        else:
            sp.line((cx + hw, cy + hw, za), (cx + hw, cy - hw, zb), 0.08, red)
            sp.line((cx + hw, cy + hw, za), (cx - hw, cy + hw, zb), 0.08, red)
    # 꼭대기
    sp.box(cx - 0.5, cy - 0.5, H + 0.15, 1.0, 1.0, 0.5, WHITE, top=SILVER)
    antenna(sp, (cx, cy, H + 0.65), 0.6)
    # 연료 팔 (붐) 과 늘어진 탯줄 호스
    arm_list = [((10.4, 3.4), (1, 0, 0))]
    if v in (1, 4):
        arm_list.append(((6.9, 2.8), (1, 0, 0)))
    if v == 3:
        arm_list = [((10.4, 3.2), (0, 1, 0))]
    if v == 2:
        arm_list = [((9.4, 3.0), (1, 0, 0))]
    for (z, L), d in arm_list:
        p0 = (cx + hw * d[0], cy + hw * d[1], z)
        p1 = add(p0, mul(d, L))
        sp.truss(p0, p1, 0.55, red, 0.08, 6, side=(0, 0, 1))
        sp.box(p1[0] - 0.3, p1[1] - 0.3, z - 0.75, 0.6, 0.6, 0.5, DARK)
        for k, col in enumerate(("#eef4f7", "#2a2d33")):
            off = (-0.15 + 0.3 * k) * (1 - abs(d[0])), (-0.15 + 0.3 * k) * (1 - abs(d[1]))
            a0 = add(p0, add(mul(d, 0.6), (off[1], off[0], -0.25)))
            a1 = add(p1, (off[1], off[0], -0.75))
            pts = []
            for i in range(11):
                t = i / 10
                q = add(a0, mul(sub(a1, a0), t))
                pts.append((q[0], q[1], q[2] - 1.8 * math.sin(math.pi * t)))
            sp.polyline3(pts, col, 0.13)
            sp.polyline3([a1, add(a1, (0, 0, -1.2))], col, 0.13)
        sp.lamp((p1[0], p1[1], z + 0.35), "#ff5a3c", 6)
    # 밑동 탱크
    if v != 4:
        legs(sp, [(1.2, -2.6, 1.0), (2.4, -2.6, 1.0), (1.2, -1.4, 1.0), (2.4, -1.4, 1.0)], 0.3)
        sp.sphere((1.8, -2.0, 1.6), 0.85, FROST)
        sp.ring3((1.8, -2.0, 1.6), 0.86, "#3E6FB0", 0.1)
        legs(sp, [(-2.6, 1.2, 1.0), (-1.4, 1.2, 1.0), (-2.6, 2.4, 1.0), (-1.4, 2.4, 1.0)], 0.3)
        sp.sphere((-2.0, 1.8, 1.6), 0.85, FOAM)
        sp.ring3((-2.0, 1.8, 1.6), 0.86, "#a45a1c", 0.1)
    else:
        sp.cyl((1.8, -2.0, 0.3), (1.8, -2.0, 2.6), 0.75, FROST, bands=[0.5], band_color="#3E6FB0")
        sp.sphere((1.8, -2.0, 2.6), 0.75, FROST, clip_z=2.6)
        sp.cyl((-2.0, 1.8, 0.3), (-2.0, 1.8, 2.2), 0.75, FOAM, bands=[0.5], band_color="#a45a1c")
        sp.sphere((-2.0, 1.8, 2.2), 0.75, FOAM, clip_z=2.2)
    pipe(sp, [(1.8, -1.2, 0.6), (cx + hw + 0.3, -1.2, 0.6), (cx + hw + 0.3, cy + 0.6, 0.6)], 0.14, "#eef4f7")
    pipe(sp, [(-1.2, 1.8, 0.6), (-1.2, cy + hw + 0.3, 0.6), (cx + 0.6, cy + hw + 0.3, 0.6)], 0.14, "#e0a060")
    sp.box(1.6, 1.4, 0.3, 1.2, 1.0, 1.2, WHITE, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(1.6, 1.4, 0.3, 1.2, 1.0, 1.2)["left"], 0.2, 0.45, 0.8, 0.75))
    sp.lamp((cx, cy, H + 1.3), "#ff5a3c", 7)
    sp.lamp((3.0, 3.0, 0.5), AMBER, 9)


# ── 착륙장 계열 ──────────────────────────────────────────────────────

def _berm_arc(sp: Sprite, r_in, r_out, h, gap_deg, gap_w=34.0, front=None, seg=60, mat: Mat = BERM):
    """한 곳이 트인 둥근 흙 둑 (gap_deg 방향, 폭 gap_w도). front=False면 뒤 반, True면 앞 반."""
    rm = (r_in + r_out) / 2
    g = math.radians(gap_deg)
    half = math.radians(gap_w / 2)

    def in_gap(t):
        d = (t - g + math.pi) % (2 * math.pi) - math.pi
        return abs(d) < half

    def P3(r, t, z):
        return (r * math.cos(t), r * math.sin(t), z)
    items = []
    for i in range(seg):
        t0, t1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        if in_gap((t0 + t1) / 2):
            continue
        items.append((dot((math.cos((t0 + t1) / 2), math.sin((t0 + t1) / 2), 0.0), VIEW), t0, t1))
    # 트인 자리의 두 끝면
    caps = []
    for t, sgn in ((g - half, -1), (g + half, 1)):
        caps.append((dot((math.cos(t), math.sin(t), 0.0), VIEW), t, sgn))
    for key, t0, t1 in sorted(items):
        is_front = key > 0
        if front is not None and is_front != front:
            continue
        o0, o1 = P3(r_out, t0, 0), P3(r_out, t1, 0)
        m0, m1 = P3(rm, t0, h), P3(rm, t1, h)
        i0, i1 = P3(r_in, t0, 0), P3(r_in, t1, 0)
        sp.face([o0, o1, m1, m0], mat, edge=False, ao=0.0)
        sp.face([i1, i0, m0, m1], mat, edge=False, ao=0.0)
    for key, t, sgn in caps:
        if front is not None and (key > 0) != front:
            continue
        tri = [P3(r_out, t, 0), P3(rm, t, h), P3(r_in, t, 0)]
        if sgn < 0:
            tri = tri[::-1]
        sp.face(tri, Mat("#6a645e"), edge=False, ao=0.0)


def _arc_line(sp: Sprite, r, z, gap_deg, gap_w, color, w=0.06, seg=72):
    g = math.radians(gap_deg)
    half = math.radians(gap_w / 2)
    run = []
    for i in range(seg + 1):
        t = 2 * math.pi * i / seg
        d = (t - g + math.pi) % (2 * math.pi) - math.pi
        vis = dot((math.cos(t), math.sin(t), 0.0), VIEW) > -0.05
        if abs(d) >= half and vis:
            run.append((r * math.cos(t), r * math.sin(t), z))
        elif run:
            if len(run) > 1:
                sp.polyline3(run, color, w, 0.8)
            run = []
    if len(run) > 1:
        sp.polyline3(run, color, w, 0.8)


@typed("sintered_pad", 30, 30, 0.6, "소결 착륙장", heights=[0.6, 0.6, 0.6, 0.6, 0.6])
def sintered_pad(sp: Sprite, v: int):
    """마이크로파로 구워 유리처럼 매끈하고 어두운 둥근 착륙장: 동심원 줄과 가장자리 등."""
    r = 14.0
    glassy = Mat("#3A3634", 0.6)
    sp.cyl((0, 0, 0), (0, 0, 0.35), r + 0.5, Mat("#7a6e60"), cap_mat=Mat("#8a7c68"))
    sp.cyl((0, 0, 0.35), (0, 0, 0.42), r, glassy, cap_mat=glassy, edge=False)
    # 유리질 윤기 (2D만)
    with sp._nest():
        c = PV((-4.0, 4.0, 0.42))
        fill = sp.radial([(0, "#ffffff", 0.16), (0.5, "#cfd8e0", 0.06), (1, "#cfd8e0", 0.0)], c[0], c[1], r * S * 0.9)
        sp.poly2([PV((r * 0.97 * math.cos(2 * math.pi * k / 48), r * 0.97 * math.sin(2 * math.pi * k / 48), 0.43))
                  for k in range(48)], fill)
    ring_col = "#6b6058" if v != 2 else "#7a6a58"
    for rr in ((3.5, 7.0, 10.5) if v != 1 else (4.5, 9.0)):
        sp.ring3((0, 0, 0.44), rr, ring_col, 0.12, front_only=False)
    if v in (1, 2):
        for i in range(8 if v == 1 else 12):
            a = 2 * math.pi * i / (8 if v == 1 else 12)
            sp.line((3.5 * math.cos(a), 3.5 * math.sin(a), 0.44), (r * 0.98 * math.cos(a), r * 0.98 * math.sin(a), 0.44),
                    0.08, ring_col)
    # 가운데 표시
    if v == 3:
        sp.line((-2.2, 0, 0.45), (2.2, 0, 0.45), 0.45, "#E9C24A")
        sp.line((0, -2.2, 0.45), (0, 2.2, 0.45), 0.45, "#E9C24A")
        sp.ring3((0, 0, 0.45), 3.0, "#E9C24A", 0.25, front_only=False)
    else:
        sp.ring3((0, 0, 0.45), 2.6, "#E9C24A" if v != 1 else "#ECE7DC", 0.4, front_only=False)
        sp.disc((0, 0, 0.45), (0, 0, 1), 0.7, Mat("#E9C24A") if v != 1 else Mat("#ECE7DC"))
    sp.ring3((0, 0, 0.44), r - 0.25, "#8a7c68", 0.18, front_only=False)
    # 가장자리 등
    light = CYAN_LIGHT if v in (0, 2, 3) else AMBER
    n = 24 if v != 2 else 32
    for i in range(n):
        a = 2 * math.pi * i / n
        sp.lamp((r * 0.985 * math.cos(a), r * 0.985 * math.sin(a), 0.5), light, 8)
    if v == 4:
        # 모서리로 나가는 유도로
        for k in range(6):
            t = k / 5
            p = (r * 0.72 + t * 4.2, r * 0.72 + t * 4.2, 0.44 if t < 0.3 else 0.05)
        sp.face([(9.6, 10.6, 0.06), (10.6, 9.6, 0.06), (14.6, 13.6, 0.06), (13.6, 14.6, 0.06)], glassy, normal=(0, 0, 1), ao=0)
        sp.line((10.1, 10.1, 0.08), (14.1, 14.1, 0.08), 0.12, "#E9C24A")
    for (x, y) in ((13.4, -13.4), (-13.4, 13.4)):
        sp.box(x - 0.3, y - 0.3, 0, 0.6, 0.6, 0.4, CONCRETE)
        _mast(sp, x, y, 2.2, AMBER, 16, z=0.4)


@typed("bermed_pad", 34, 34, 3.0, "방벽 착륙장", heights=[3.0, 3.0, 3.0, 3.0, 3.0])
def bermed_pad(sp: Sprite, v: int):
    """높은 레골리스 둑을 둘러친 착륙장 — 둑 한 곳만 트여 드나든다."""
    gap = (45.0, 0.0, 90.0, 45.0, 20.0)[v]
    gw = (34.0, 30.0, 30.0, 42.0, 30.0)[v]
    r_in, r_out, h = 12.6, 16.6, 3.0
    _berm_arc(sp, r_in, r_out, h, gap, gw, front=False)
    sp.face([(12.6 * math.cos(2 * math.pi * k / 64), 12.6 * math.sin(2 * math.pi * k / 64), 0.04) for k in range(64)],
            SINTER, normal=(0, 0, 1), ao=0)
    for rr in (4.0, 8.0):
        sp.ring3((0, 0, 0.05), rr, "#8a7c68", 0.08, front_only=False)
    # 표시: 노란 고리 + 네모, 트인 자리에서 가운데로 오는 유도선
    sp.ring3((0, 0, 0.06), 2.6, "#E9C24A", 0.35, front_only=False)
    q = 1.3
    sp.polyline3([(-q, -q, 0.06), (q, -q, 0.06), (q, q, 0.06), (-q, q, 0.06)], "#ECE7DC", 0.3, closed=True)
    g = math.radians(gap)
    sp.line((3.0 * math.cos(g), 3.0 * math.sin(g), 0.06), (r_out * math.cos(g), r_out * math.sin(g), 0.06), 0.3, "#E9C24A")
    hw_ = math.radians(gw / 2)
    sp.face([(r_in * math.cos(g - hw_), r_in * math.sin(g - hw_), 0.04), (r_out * math.cos(g - hw_), r_out * math.sin(g - hw_), 0.04),
             (r_out * math.cos(g + hw_), r_out * math.sin(g + hw_), 0.04), (r_in * math.cos(g + hw_), r_in * math.sin(g + hw_), 0.04)],
            SINTER, normal=(0, 0, 1), ao=0)
    for i in range(12):
        a = 2 * math.pi * i / 12
        sp.lamp((r_in * 0.95 * math.cos(a), r_in * 0.95 * math.sin(a), 0.1), AMBER, 8)
    _berm_arc(sp, r_in, r_out, h, gap, gw, front=True)
    _arc_line(sp, (r_in + r_out) / 2 - 0.9, h * 0.55, gap, gw, "#5f5953", 0.07)
    _arc_line(sp, (r_in + r_out) / 2 + 0.9, h * 0.55, gap, gw, "#5f5953", 0.07)
    # 둑 위 등과 출입구 기둥
    for i in range(16):
        a = 2 * math.pi * i / 16
        d = (a - g + math.pi) % (2 * math.pi) - math.pi
        if abs(d) > math.radians(gw / 2 + 6):
            rm = (r_in + r_out) / 2
            sp.lamp((rm * math.cos(a), rm * math.sin(a), h + 0.15), AMBER if v != 4 else "#ff5a3c", 8)
    for s in (-1, 1):
        a = g + s * math.radians(gw / 2 - 4)
        rr = (r_in + r_out) / 2 + 0.6
        p = (rr * math.cos(a), rr * math.sin(a), 0)
        sp.box(p[0] - 0.3, p[1] - 0.3, 0, 0.6, 0.6, 0.5, CONCRETE)
        _mast(sp, p[0], p[1], 3.6, "#7CF29A" if v != 3 else AMBER, 14, z=0.5)


@typed("hopper_pad", 14, 14, 0.8, "호퍼 발착장", heights=[0.8, 0.8, 0.8, 0.8, 0.8])
def hopper_pad(sp: Sprite, v: int):
    """작은 팔각 패드: 가운데 H 표시, 모서리에 연료 호스 받침."""
    R = 5.9
    octo = [(R * math.cos(math.radians(22.5 + 45 * k)), R * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
    top = Mat("#A89A84") if v != 2 else Mat("#8f8a84")
    corner = ((5.3, -5.3), (5.3, -5.3), (-5.3, 5.3), (5.3, -5.3), (5.3, 5.3))[v]
    # 연료 받침 (뒤 모서리면 먼저)
    def stand():
        sx, sy = corner
        tx, ty = sx + 0.9 * (1 if sx > 0 else -1), sy + 0.9 * (1 if sy > 0 else -1)
        sp.box(tx - 0.55, ty - 0.55, 0, 1.1, 1.1, 0.2, CONCRETE)
        sp.sphere((tx, ty, 0.85), 0.6, WHITE if v != 4 else FOAM)
        sp.ring3((tx, ty, 0.85), 0.61, "#d8853b", 0.1)
        sp.box(sx - 0.35, sy - 0.35, 0, 0.7, 0.7, 1.3, YELLOW, top=Mat("#F0D27A"))
        sf = Sprite.box_faces(sx - 0.35, sy - 0.35, 0, 0.7, 0.7, 1.3)
        sp.stripes(sf["left"][0], (-0.7, 0, 0), (0, 0, 0.25), n=4)
        sp.cyl((sx, sy + 0.35, 1.0), (sx, sy + 0.6, 1.0), 0.32, DARK, cap_mat=STEEL)
        mid = (sx * 0.85, sy * 0.85)
        sp.polyline3([(sx, sy + 0.5, 0.75), (sx - 0.1 * sx / abs(sx), sy + 0.7, 0.3), (mid[0], mid[1], 0.4),
                      (mid[0] * 0.92, mid[1] * 0.92, 0.42)], "#2a2d33", 0.1)
        sp.lamp((sx, sy, 1.45), AMBER, 8)
    if corner[0] + corner[1] <= 0:
        stand()
    sp.prism(octo, 0, 0.35, CONCRETE, top=top)
    sp.polyline3([(x * 0.94, y * 0.94, 0.36) for x, y in octo], "#ECE7DC" if v != 3 else "#E9C24A", 0.18, closed=True)
    sp.ring3((0, 0, 0.36), 3.6, "#E9C24A" if v != 1 else "#ECE7DC", 0.3, front_only=False)
    hc = Mat("#ECE7DC") if v != 1 else YELLOW
    for (x0, y0, x1, y1) in ((-1.5, -1.6, -0.9, 1.6), (0.9, -1.6, 1.5, 1.6), (-0.9, -0.3, 0.9, 0.3)):
        sp.face([(x0, y0, 0.37), (x1, y0, 0.37), (x1, y1, 0.37), (x0, y1, 0.37)], hc, normal=(0, 0, 1), ao=0, edge=False)
    light = AMBER if v != 3 else "#7CF29A"
    for (x, y) in octo:
        sp.lamp((x * 0.97, y * 0.97, 0.42), light, 7)
    if corner[0] + corner[1] > 0:
        stand()
    if v == 3:
        _mast(sp, -5.4, -5.4, 2.6, AMBER, 14)


@typed("heavy_pad", 44, 44, 6.0, "대형 착륙장", heights=[6.0, 6.0, 6.0, 6.0, 6.4])
def heavy_pad(sp: Sprite, v: int):
    """아주 큰 네모 착륙장: 굵은 표시, 두 변의 폭발막이 벽, 모서리의 정비탑."""
    L = 20.4
    wall_h = (5.0, 5.0, 4.4, 5.0, 5.6)[v]
    wall = CONCRETE if v != 2 else SINTER
    # 폭발막이 벽 (뒤 두 변, 안쪽으로 기울어진 면)
    sp.tbox(-22.0, -22.0, -20.6, L, 0.45, wall_h, wall, top=Mat("#b3a690"))
    sp.tbox(-20.6, -22.0, L, -20.6, 0.45, wall_h, wall, top=Mat("#b3a690"))
    for k in range(9):
        y = -18.0 + k * 4.5
        sp.line((-20.6 + 0.02, y, 0.2), (-20.6 + 0.02 - 0.0, y, wall_h - 0.4), 0.06, "#8a7c68")
    sp.stripes((-20.55, L, wall_h - 1.2), (0, -(L + 20.6), 0), (0, 0, 0.6), n=40, normal=(1, 0, 0))
    sp.stripes((L, -20.55, wall_h - 1.2), (-(L + 20.6), 0, 0), (0, 0, 0.6), n=40, normal=(0, 1, 0))
    # 판
    sp.box(-L, -L, 0, 2 * L, 2 * L, 0.35, Mat("#8a7c68"), top=Mat("#A39581"))
    step = 2 * L / 10
    for k in range(1, 10):
        t = -L + k * step
        sp.line((t, -L, 0.36), (t, L, 0.36), 0.07, "#8a7c68")
        sp.line((-L, t, 0.36), (L, t, 0.36), 0.07, "#8a7c68")
    m = L - 2.0
    yel = "#E9C24A"
    sp.polyline3([(-m, -m, 0.37), (m, -m, 0.37), (m, m, 0.37), (-m, m, 0.37)], yel, 0.5, closed=True)
    sp.ring3((0, 0, 0.37), 8.0, yel, 0.6, front_only=False)
    sp.ring3((0, 0, 0.37), 6.6, "#ECE7DC" if v != 3 else yel, 0.25, front_only=False)
    if v in (0, 2, 4):
        for (a, b) in (((-4.5, -4.5), (4.5, 4.5)), ((-4.5, 4.5), (4.5, -4.5))):
            sp.line((a[0], a[1], 0.38), (b[0], b[1], 0.38), 0.7, "#ECE7DC")
    else:
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            sp.line((3.0 * math.cos(a), 3.0 * math.sin(a), 0.38), (6.2 * math.cos(a), 6.2 * math.sin(a), 0.38), 0.6, "#ECE7DC")
    # 모서리 갈매기 표시
    for (sx, sy) in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        cx, cy = sx * (m - 2.4), sy * (m - 2.4)
        sp.polyline3([(cx - sx * 2.0, cy, 0.38), (cx, cy, 0.38), (cx, cy - sy * 2.0, 0.38)], yel, 0.45)
    # 가장자리 등
    for k in range(17):
        t = -L + k * (2 * L / 16)
        for p in ((t, L, 0.4), (L, t, 0.4)):
            sp.lamp(p, AMBER, 9)
    for k in range(17):
        t = -L + k * (2 * L / 16)
        for p in ((t, -L + 0.3, 0.4), (-L + 0.3, t, 0.4)):
            sp.lamp(p, AMBER, 7)
    # 정비탑 (오른쪽 모서리) + 연료 팔
    tx, ty = (18.6, -18.6) if v != 3 else (-18.4, 18.4)
    hw, H = 1.2, 8.0 if v != 4 else 8.8
    red = "#C9553A"
    sp.box(tx - 1.8, ty - 1.8, 0.35, 3.6, 3.6, 0.3, CONCRETE)
    for (x, y) in ((tx - hw, ty - hw), (tx + hw, ty - hw), (tx - hw, ty + hw)):
        sp.line((x, y, 0.65), (x, y, H), 0.18, red)
    sp.cyl((tx, ty, 0.65), (tx, ty, H - 0.6), 0.3, Mat("#eef4f7", 0.3))
    for z in (2.8, 5.4, H):
        sp.box(tx - hw - 0.15, ty - hw - 0.15, z, 2 * hw + 0.3, 2 * hw + 0.3, 0.18, Mat("#8C939C", 0.3))
    sp.line((tx + hw, ty + hw, 0.65), (tx + hw, ty + hw, H), 0.18, red)
    for k in range(5):
        za, zb = 0.65 + k * (H - 0.65) / 5, 0.65 + (k + 1) * (H - 0.65) / 5
        sp.line((tx + hw, ty - hw, za), (tx + hw, ty + hw, zb), 0.09, red)
        sp.line((tx - hw, ty + hw, za), (tx + hw, ty + hw, zb), 0.09, red)
    d = norm((-tx, -ty, 0))
    p0 = (tx + d[0] * hw, ty + d[1] * hw, H - 1.4)
    p1 = add(p0, mul(d, 5.0))
    sp.truss(p0, p1, 0.6, red, 0.09, 6, side=(0, 0, 1))
    sp.polyline3([p1, (p1[0], p1[1], p1[2] - 2.2), (p1[0] + d[0] * 0.8, p1[1] + d[1] * 0.8, 1.0)], "#2a2d33", 0.14)
    sp.box(tx - 0.6, ty - 0.6, H + 0.18, 1.2, 1.2, 0.6, WHITE, top=SILVER)
    sp.lamp((tx, ty, H + 1.0), "#ff5a3c", 8)
    sp.lamp(p1, AMBER, 9)
    if v == 1:
        _vtank(sp, tx - 3.2, ty + 0.4, 0.35, 2.2, 0.9, FROST, bands=[0.5], band_color="#3E6FB0")
        _vtank(sp, tx - 0.4, ty + 3.2, 0.35, 2.2, 0.9, FOAM, bands=[0.5], band_color="#a45a1c")
