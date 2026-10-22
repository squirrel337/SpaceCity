"""기존 계열에 더하는 큰 건물 종류 8종 — 공동 주택·계단식 주거(거주), 종합 연구원·전파 망원경 배열(연구),
레골리스 채석장(굴착), 광석 정련소(용융 전해), 조립 공장(부품 공장), 식물원 돔(녹지 공원).

종류마다 함수 하나 fn(sp, v)가 같은 기능의 다섯 모양(v = 0~4)을 그린다. v0이 대표 모양이다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다. 뒤(x+y가 작은 쪽)에서 앞 순서로 그린다.
뒤쪽 면의 창·띠는 3D 모형에만 남는다 (그림에서는 보이지 않는 면이라 빠진다).
"""
from __future__ import annotations

import math

import iso
from types_common import *  # noqa: F401,F403

# ── 재질 ──────────────────────────────────────────────────────────────
TAN = Mat("#A8926F")                 # 인쇄한 레골리스 (밝은 황갈색)
TAN_TOP = Mat("#B49E7C")
REVEAL = Mat("#6E604C")              # 두꺼운 벽에 깊이 들어간 창 둘레
SLAB = Mat("#C9BDA6")                # 층 띠 (소결 슬래브)
ROOF_BERM = Mat("#6e6862")           # 지붕 흙 둑 윗면
VIOLET = Mat("#9B7AD6")              # 연구 계열 띠
FURNACE = Mat("#6B5A4C", 0.15)       # 용융로 단열 외피
INGOT = Mat("#C2C7CD", 0.6)          # 금속 주괴·판
HOT_INGOT = Mat("#FFA25A", 0.6)
PLANTER = Mat("#8a7c68")
SOIL = Mat("#5b4636")
POND = Mat("#3D7FA6", 0.7)
PAVE = Mat("#B9AE98")                # 길 포장
HALL = Mat("#E4DED2", 0.05)          # 큰 공장동 벽
CRANE = Mat("#E9C24A", 0.15)
CRANE_TOP = Mat("#F0D27A", 0.15)

HOT = "#ff7b2e"
GARDEN_LIGHT = "#d8ffb0"
RED_LIGHT = "#ff5a3c"


# ── 공용 도우미 ───────────────────────────────────────────────────────

def _orient(pts, outward):
    """다각형 꼭짓점이 outward 쪽에서 반시계가 되게 한다."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return pts if dot(n, outward) >= 0 else list(reversed(pts))


def _face_pt(frame, u, v):
    o, e1, e2 = frame
    return add(add(o, mul(e1, u)), mul(e2, v))


def _decal(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, lift=0.0):
    """면 위의 색 판 (표시·패널·창 둘레)."""
    o, e1, e2 = frame
    n = norm(cross(e1, e2))
    pts = [add(p, mul(n, lift)) for p in sp.on_face(o, e1, e2, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    return pts


def _edge_frames(base, z, h):
    """반시계 바닥 다각형을 h만큼 세운 기둥의 옆면 틀 (원점, 가로, 세로) — 가로×세로가 바깥 법선."""
    out = []
    for i in range(len(base)):
        a, b = base[i], base[(i + 1) % len(base)]
        out.append(((a[0], a[1], z), (b[0] - a[0], b[1] - a[1], 0.0), (0.0, 0.0, h)))
    return out


def _box_sides(x, y, z, w, d, h):
    """상자 옆 네 면 틀: 가로×세로 = 바깥 법선 (+y, +x는 그림에 보이고 -y, -x는 3D에만)."""
    return {"+y": ((x + w, y + d, z), (-w, 0.0, 0.0), (0.0, 0.0, h)),
            "+x": ((x + w, y, z), (0.0, d, 0.0), (0.0, 0.0, h)),
            "-y": ((x, y, z), (w, 0.0, 0.0), (0.0, 0.0, h)),
            "-x": ((x, y + d, z), (0.0, -d, 0.0), (0.0, 0.0, h))}


def _deep_win(sp: Sprite, frame, u0, v0, u1, v1, glow=WARM_WINDOW, reveal: Mat = REVEAL, m=0.12, lit_a=0.95):
    """두꺼운 벽에 깊이 들어간 창: 어두운 둘레(벽 두께)와 유리. m은 둘레 폭(m)."""
    o, e1, e2 = frame
    du, dv = m / max(1e-6, length(e1)), m / max(1e-6, length(e2))
    _decal(sp, frame, u0 - du, v0 - dv * 1.4, u1 + du, v1 + dv * 0.6, reveal)
    sp.window(sp.on_face(o, e1, e2, u0, v0, u1, v1), glow, light_alpha=lit_a)


def _win(sp: Sprite, pts3, glow=WARM_WINDOW, alpha=0.95, dark2d=False, **kw):
    """창. dark2d면 그림에서는 불빛을 빼고 (앞의 덩어리에 가려진 창) 3D 모형에만 불빛을 남긴다."""
    if not dark2d:
        sp.window(pts3, glow, light_alpha=alpha, **kw)
        return
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if sp._on():
        sp.rec.append(("win", sp._lift(pts3, n), glow, kw.get("glass", GLASS), alpha))
    with sp._nest():
        sp.window(pts3, glow, light_alpha=0.0, **kw)


def _screen_hull(pts3):
    return hull([PV(p) for p in pts3])


def _cyl_pts(cx, cy, r, z0, z1, k=24):
    return [(cx + r * math.cos(2 * math.pi * i / k), cy + r * math.sin(2 * math.pi * i / k), z)
            for i in range(k) for z in (z0, z1)]


def _covered(hull2, pts3) -> bool:
    """3D 점들 중 하나라도 화면에서 볼록 껍질 hull2 안에 들면 참 (앞 덩어리에 가려진 창 찾기)."""
    n = len(hull2)
    for p in pts3:
        q = PV(p)
        sgn = 0
        inside = True
        for i in range(n):
            a, b = hull2[i], hull2[(i + 1) % n]
            c = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
            if abs(c) < 1e-9:
                continue
            s_ = 1 if c > 0 else -1
            if sgn == 0:
                sgn = s_
            elif s_ != sgn:
                inside = False
                break
        if inside:
            return True
    return False


def _glass_pane(sp: Sprite, pts3, color="#cfe6ff", alpha=0.22, frame="#dfe9f2"):
    """유리판 (그림은 반투명, 3D는 유리 재질)."""
    sp._rec(("poly", list(pts3), iso._Glass(color, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if dot(n, VIEW) <= 0:
        n = mul(n, -1)
    sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(color), n, 0.6)), frame, 0.5, alpha + 0.12)


def _radiator(sp: Sprite, o, e1, e2, n=5):
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, n, 1, "#b7bcc2", 0.5, 0.8)


def _mast(sp: Sprite, x, y, h=3.4, color=AMBER, r=16, z=0.0):
    """투광등 기둥."""
    sp.line((x, y, z), (x, y, z + h), 0.08, "#8a9099")
    sp.box(x - 0.22, y - 0.08, z + h - 0.05, 0.44, 0.16, 0.14, DARK)
    sp.lamp((x, y, z + h + 0.12), color, r)


def _shrub(sp: Sprite, x, y, z, r, mat: Mat = LEAF, k=0.75):
    sp.ellipsoid((x, y, z), r, r, r * k, mat, clip_z=z)


def _sandbag_lines(sp: Sprite, x0, y0, x1, y1, z, inset, h, levels=(0.35, 0.7), color="#5f5953"):
    """흙 둑(tbox) 앞 두 비탈의 모래주머니 줄."""
    for t in levels:
        k = inset * t
        zz = z + h * t
        sp.polyline3([(x0 + k, y1 - k, zz), (x1 - k, y1 - k, zz), (x1 - k, y0 + k, zz)], color, 0.06, 0.75)


# ═════════════════════════════════════════════════════════════════════
# 거주 (hab_module 계열)
# ═════════════════════════════════════════════════════════════════════

def _sunroom(sp: Sprite, xa, xb, y, dp, z0, z1, glow=GARDEN_LIGHT, leaf=(LEAF, GREEN), frame_col="#d9d4ca"):
    """+y 벽에 내단 유리 온실 띠 (안에 화분 줄). xa < xb, 벽면 y, 내민 깊이 dp."""
    yf = y + dp
    sp.box(xa - 0.05, y, z0 - 0.14, xb - xa + 0.1, dp + 0.06, 0.14, SLAB)
    # 먼 옆 유리 (그림에서는 식물 뒤에 비친다)
    _glass_pane(sp, [(xa, y, z0), (xa, yf, z0), (xa, yf, z1), (xa, y, z1)], alpha=0.12)
    n = max(2, int((xb - xa) / 0.85))
    for i in range(n):
        x = xa + (xb - xa) * (i + 0.5) / n
        zz = z0 + 0.02
        sp.box(x - 0.26, y + dp * 0.25, z0, 0.52, dp * 0.5, 0.28, PLANTER)
        _shrub(sp, x, y + dp * 0.5, zz + 0.26, 0.33 if i % 2 else 0.39, leaf[i % 2], 1.1)
    front = [(xb, yf, z0), (xa, yf, z0), (xa, yf, z1), (xb, yf, z1)]
    side = [(xb, y, z0), (xb, yf, z0), (xb, yf, z1), (xb, y, z1)]
    _glass_pane(sp, front, alpha=0.16)
    _glass_pane(sp, side, alpha=0.16)
    sp.light_poly(_orient(front, (0, 1, 0)), glow, 0.42)
    sp.light_poly(_orient(side, (1, 0, 0)), glow, 0.3)
    # 창살과 지붕 판
    k = max(2, int((xb - xa) / 1.0))
    for i in range(k + 1):
        x = xa + (xb - xa) * i / k
        sp.line((x, yf, z0), (x, yf, z1), 0.06, frame_col)
    sp.line((xb, y, z0 + (z1 - z0) * 0.5), (xb, yf, z0 + (z1 - z0) * 0.5), 0.05, frame_col)
    sp.line((xb, yf, z0), (xb, yf, z1), 0.07, frame_col)
    sp.box(xa - 0.08, y, z1, xb - xa + 0.16, dp + 0.08, 0.12, WHITE, top=SILVER)


def _balcony(sp: Sprite, xa, xb, y, dp, z0, leaf=(LEAF, GREEN), rail="#c9ccd1"):
    """열린 발코니: 슬래브, 화분 줄, 유리 난간."""
    sp.box(xa, y, z0 - 0.15, xb - xa, dp, 0.15, SLAB)
    n = max(2, int((xb - xa) / 1.4))
    for i in range(n):
        x = xa + (xb - xa) * (i + 0.5) / n
        sp.box(x - 0.35, y + 0.1, z0, 0.7, 0.35, 0.3, PLANTER)
        _shrub(sp, x, y + 0.28, z0 + 0.28, 0.28, leaf[i % 2], 1.0)
    yf = y + dp - 0.04
    _glass_pane(sp, [(xb, yf, z0), (xa, yf, z0), (xa, yf, z0 + 0.85), (xb, yf, z0 + 0.85)], alpha=0.14)
    _glass_pane(sp, [(xb, y, z0), (xb, yf, z0), (xb, yf, z0 + 0.85), (xb, y, z0 + 0.85)], alpha=0.14)
    sp.polyline3([(xa, yf, z0 + 0.9), (xb, yf, z0 + 0.9), (xb, y, z0 + 0.9)], rail, 0.06)


def _lift_shaft(sp: Sprite, x0, y0, w, d, z0, z1, fh, zc, frame_col="#c9ccd1"):
    """벽(-x 쪽)에 붙인 유리 승강기 통: 뒤 기둥·유리 → 승강 칸 → 앞 유리·기둥 → 기계실."""
    x1, y1 = x0 + w, y0 + d
    for (x, y) in ((x0, y0), (x1, y0)):
        sp.line((x, y, z0), (x, y, z1), 0.1, frame_col)
    _glass_pane(sp, [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], alpha=0.1)
    sp.line((x0 + w / 2, y0 + d / 2, z0), (x0 + w / 2, y0 + d / 2, z1), 0.05, "#5c626b")
    sp.box(x0 + 0.12, y0 + 0.12, zc, w - 0.24, d - 0.24, 2.1, Mat("#d9d4ca", 0.2), top=SILVER)
    cf = Sprite.box_faces(x0 + 0.12, y0 + 0.12, zc, w - 0.24, d - 0.24, 2.1)
    for nm in ("left", "right"):
        sp.window(sp.on_face(*cf[nm], 0.15, 0.2, 0.85, 0.85), "#ffe2a0", frame=None)
    _glass_pane(sp, [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], alpha=0.14)
    _glass_pane(sp, [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], alpha=0.14)
    sp.light_poly([(x1 + 0.01, y0, z0), (x1 + 0.01, y1, z0), (x1 + 0.01, y1, z1), (x1 + 0.01, y0, z1)], "#ffe2a0", 0.22)
    for (x, y) in ((x0, y1), (x1, y1)):
        sp.line((x, y, z0), (x, y, z1), 0.1, frame_col)
    z = z0
    while z < z1 - 0.1:
        sp.polyline3([(x0, y1, z), (x1, y1, z), (x1, y0, z)], frame_col, 0.07)
        z += fh
    sp.box(x0 - 0.05, y0 - 0.05, z1, w + 0.1, d + 0.1, 0.7, STEEL, top=DARK)
    sp.lamp((x1 + 0.08, y1 + 0.08, z1 + 0.85), RED_LIGHT, 6)


def _dish(sp: Sprite, c, n, r, mat: Mat = WHITE, legs3=True):
    """작은 접시 안테나: 판, 테두리, 급전 다리와 금빛 급전부."""
    sp.disc(c, n, r, mat, back=STEEL, seg=40)
    sp.ring3(c, r, "#b9b2a5", 0.07, normal=n, front_only=False)
    sp.ring3(add(c, mul(n, 0.01)), r * 0.55, "#d8d2c6", 0.04, normal=n, front_only=False)
    feed = add(c, mul(n, r * 0.62))
    if legs3:
        u, w = basis(n)
        for a in (0, 120, 240):
            rim = add(c, add(mul(u, r * 0.85 * math.cos(math.radians(a))), mul(w, r * 0.85 * math.sin(math.radians(a)))))
            sp.line(rim, feed, 0.045, "#8a9099")
    sp.sphere(feed, max(0.1, r * 0.08), GOLD)


@typed("apartment_block", 12, 9, 18.0, "공동 주택 블록", heights=[18.2, 19.4, 16.8, 18.2, 18.2])
def apartment_block(sp: Sprite, v: int):
    """두꺼운 소결 레골리스 벽의 여러 층 공동 주택: 층마다 깊은 창 줄, 내단 유리 온실 띠, 지붕 흙 둑과 방열판."""
    nf = (5, 6, 4, 5, 5)[v]
    fh = (3.0, 2.75, 3.25, 3.0, 3.0)[v]
    wall = (TAN, SINTER, Mat("#B39A76"), Mat("#C4B8A2"), TAN)[v]
    accent = (TEAL, ORANGE, BLUE, TEAL, RED)[v]
    nb = (5, 6, 4, 5, 5)[v]                  # 긴 면(+y)의 창 칸 수
    x0, x1, y0, y1, c = -5.3, 3.7, -3.9, 2.3, 0.7
    zb = 0.25
    H = nf * fh
    zt = zb + H
    sp.contact_shadow(-0.4, -0.3, 6.0, 4.4, 0.5)
    sp.box(-5.9, -4.4, 0, 11.8, 8.8, zb, CONCRETE)
    sp.face([(x1 + 1.5, -0.75, zb + 0.01), (5.85, -0.75, zb + 0.01), (5.85, 0.35, zb + 0.01), (x1 + 1.5, 0.35, zb + 0.01)],
            PAVE, normal=(0, 0, 1), ao=0, edge=False)
    base = rounded_rect(x0, y0, x1, y1, c)
    sp.prism(base, zb, H, wall, top=TAN_TOP if wall is TAN else wall)
    frames = _edge_frames(base, zb, H)
    fy, fx, fyb, fxb = frames[4], frames[2], frames[0], frames[6]     # +y, +x, -y, -x 면
    # 층 띠와 꼭대기 색 띠 (모든 면, 보이지 않는 면은 3D에만)
    for fr in frames:
        for k in range(1, nf):
            vv = k * fh / H
            band_on(sp, fr, vv - 0.1 / H, vv + 0.08 / H, SLAB)
        band_on(sp, fr, 1 - 0.55 / H, 1 - 0.3 / H, accent)
    # 온실 띠가 들어갈 자리: 층 → (시작 칸, 끝 칸)
    rooms = {0: {1: (1, 3), 3: (1, 3)}, 1: {1: (0, 2), 2: (3, 5), 3: (0, 2), 4: (3, 5)},
             2: {1: (0, 3), 2: (0, 3), 3: (0, 3)}, 3: {}, 4: {k: (0, 1) for k in range(1, 5)}}[v]
    bw = 1.0 / nb

    def on(k, b, face):
        """밤에 몇 집은 불이 꺼져 있다."""
        return 0.0 if (k * 5 + b * 3 + face + v) % 7 == 0 else 0.95
    for k in range(nf):
        v0, v1 = (k * fh + 0.85) / H, (k * fh + fh - 0.75) / H
        skip = range(rooms[k][0], rooms[k][1] + 1) if k in rooms else ()
        for b in range(nb):
            u0 = b * bw + bw * 0.22
            if b not in skip:
                _deep_win(sp, fy, u0, v0, u0 + bw * 0.56, v1, lit_a=on(k, b, 0))
            _deep_win(sp, fyb, u0, v0, u0 + bw * 0.56, v1, lit_a=on(k, b, 1))
        for b in range(3):
            u0 = b / 3 + 0.08
            if not (k == 0 and b == 1):
                _deep_win(sp, fx, u0, v0, u0 + 0.17, v1, lit_a=on(k, b, 2))
            _deep_win(sp, fxb, u0, v0, u0 + 0.17, v1, lit_a=on(k, b, 3))
    # 지붕: 차폐 흙 둑, 방열판, 승강구, 안테나
    a = c / 2 + 0.15
    bx0, by0, bx1, by1, ins, bh = x0 + a, y0 + a, x1 - a, y1 - a, 1.25, (1.5, 1.4, 1.6, 1.5, 1.5)[v]
    sp.tbox(bx0, by0, bx1, by1, ins, bh, BERM, top=ROOF_BERM, z=zt)
    _sandbag_lines(sp, bx0, by0, bx1, by1, zt, ins, bh)
    zr = zt + bh
    tx0, ty0, tx1, ty1 = bx0 + ins, by0 + ins, bx1 - ins, by1 - ins
    sp.box(tx1 - 1.3, ty1 - 1.1, zr, 1.1, 0.9, 0.9, STEEL, top=DARK)
    door(sp, Sprite.box_faces(tx1 - 1.3, ty1 - 1.1, zr, 1.1, 0.9, 0.9)["right"], 0.2, 0.8, 0.8, Mat("#5c626b", 0.3),
         light=False)
    if v == 2:
        sp.cyl((tx0 + 1.0, ty0 + 0.8, zr), (tx0 + 1.0, ty0 + 0.8, zr + 0.3), 0.35, STEEL)
        sp.line((tx0 + 1.0, ty0 + 0.8, zr + 0.3), (tx0 + 1.0, ty0 + 0.8, zr + 0.9), 0.1, "#9aa1aa")
        _dish(sp, (tx0 + 1.0, ty0 + 0.8, zr + 1.25), norm((0.25, 0.85, 0.55)), 0.95)
    else:
        nrad = 2 if v in (1, 4) else 1
        for i in range(nrad):
            ry = ty0 + 0.35 + i * 0.9
            legs(sp, [(tx0 + 0.4, ry, zr + 0.25), (tx0 + 2.8, ry, zr + 0.25)], zr)
            _radiator(sp, (tx0 + 0.2, ry, zr + 0.25), (2.8, 0, 0), (0, 0, 1.1), 6)
        pipe(sp, [(tx0 + 3.0, ty0 + 0.35, zr + 0.4), (tx1 - 1.3, ty0 + 0.35, zr + 0.4)], 0.12)
    antenna(sp, (tx1 - 0.3, ty0 + 0.2, zr), (1.2, 1.6, 1.0, 1.2, 1.4)[v])
    # 내단 온실 띠 (아래층부터) 또는 열린 발코니
    span = x1 - x0 - 2 * c
    if v == 3:
        for k in range(1, nf):
            _balcony(sp, x0 + c + 0.3, x1 - c - 0.3, y1, 0.95, zb + k * fh + 0.02)
    for k in sorted(rooms):
        b0, b1 = rooms[k]
        xa = (x1 - c) - span * (b1 + 1) * bw + 0.15
        xb = (x1 - c) - span * b0 * bw - 0.15
        _sunroom(sp, xa, xb, y1, 0.85, zb + k * fh + 0.2, zb + (k + 1) * fh - 0.35)
    # 바깥 승강기 (v4: +x 면의 유리 통과 불 켜진 승강 칸)
    if v == 4:
        _lift_shaft(sp, x1, -3.05, 1.15, 1.25, zb, zt + 0.5, fh, zb + 2 * fh + 0.3)
    # 출입 에어록 (+x 면, 1층)
    vx0, vy0, vw, vd, vh = x1, -1.15, 1.5, 1.9, 2.5
    sp.box(vx0, vy0, zb, vw, vd, vh, CONCRETE, top=Mat("#b3a48e"))
    vf = Sprite.box_faces(vx0, vy0, zb, vw, vd, vh)
    door(sp, vf["right"], 0.28, 0.72, 0.8, Mat("#5c626b", 0.3))
    band_on(sp, vf["left"], 0.82, 0.92, accent)
    sp.window(sp.on_face(*vf["left"], 0.25, 0.4, 0.75, 0.7))
    sp.lamp((x1 + vw + 0.1, vy0 + vd + 0.15, 1.6), AMBER, 9)
    # 앞마당: 화단 줄과 가로등
    beds = ((-4.8, -2.6), (-1.9, 0.3)) if v != 2 else ((-4.8, -0.6),)
    for (bx0_, bx1_) in beds:
        sp.box(bx0_, 3.3, zb, bx1_ - bx0_, 0.75, 0.35, PLANTER, top=SOIL)
        n = max(2, int((bx1_ - bx0_) / 0.55))
        for i in range(n):
            _shrub(sp, bx0_ + (bx1_ - bx0_) * (i + 0.5) / n, 3.68, zb + 0.35, 0.27, (LEAF, GREEN)[(i + v) % 2], 1.0)
    for (lx, ly) in ((2.4, 3.7),) if v != 4 else ((2.4, 3.7), (-5.5, 3.9)):
        sp.line((lx, ly, zb), (lx, ly, zb + 2.6), 0.07, "#5c626b")
        sp.lamp((lx, ly, zb + 2.7), WARM_WINDOW, 11)


@typed("terrace_housing", 12, 9, 10.0, "계단식 주거동", heights=[10.2, 10.6, 10.2, 10.4, 10.6])
def terrace_housing(sp: Sprite, v: int):
    """해를 보는 쪽으로 층마다 물러서는 계단식 주거동: 층마다 긴 창 띠와 볕 드는 정원 띠, 꼭대기에 빛 관과 천창."""
    along_x = v == 2                          # v2는 +x 쪽으로 계단이 진다
    nt = (3, 4, 3, 3, 3)[v]
    th = (2.8, 2.2, 2.8, 2.7, 2.95)[v]
    wall = (TAN, SINTER, Mat("#B39A76"), Mat("#D3C9B6"), TAN)[v]
    accent = (TEAL, ORANGE, BLUE, YELLOW, RED)[v]
    flowers = ((LEAF, GREEN, LEAF), (GREEN, LEAF, Mat("#7BB661")), (LEAF, GREEN, LEAF),
               (LEAF, Mat("#E2B93B"), Mat("#D96FA8")), (LEAF, GREEN, Mat("#7BB661")))[v]
    zb = 0.3
    if not along_x:
        tdir, sdir = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)
        t0, t1, sb, sf0 = -5.6, 4.6, -4.0, 3.6
    else:
        tdir, sdir = (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)
        t0, t1, sb, sf0 = -2.9, 4.1, -5.6, 4.3
    dtop = 3.6 if along_x else (2.4 if nt == 3 else 1.9)      # 꼭대기 층 깊이
    depth = (sf0 - sb - dtop) / (nt - 1)
    sfs = [sf0 - k * depth for k in range(nt)]
    zs = [zb + k * th for k in range(nt + 1)]
    sn = norm(sdir)

    def X(t, s, z):
        return (t * tdir[0] + s * sdir[0], t * tdir[1] + s * sdir[1], z)

    def bx(ta, sa, tb, s_b, za, zh, mat, top=None):
        p, q = X(ta, sa, 0), X(tb, s_b, 0)
        x0_, y0_ = min(p[0], q[0]), min(p[1], q[1])
        w_, d_ = abs(p[0] - q[0]), abs(p[1] - q[1])
        sp.box(x0_, y0_, za, w_, d_, zh, mat, top=top)
        return x0_, y0_, w_, d_

    sp.contact_shadow(0, 0, 5.9, 4.4, 0.5)
    sp.box(-5.9, -4.4, 0, 11.8, 8.8, zb, CONCRETE)
    # 층 몸체 (아래층부터), 창 띠와 끝면 창
    L = t1 - t0
    for k in range(nt):
        x0_, y0_, w_, d_ = bx(t0, sb, t1, sfs[k], zs[k], th, wall, top=PAVE)
        sides = _box_sides(x0_, y0_, zs[k], w_, d_, th)
        front = sides["+x" if along_x else "+y"]
        back = sides["-x" if along_x else "-y"]
        ends = (sides["+y"], sides["-y"]) if along_x else (sides["+x"], sides["-x"])
        band_on(sp, front, 0.9, 0.97, accent)
        nu = 3 if L > 8 else 2
        for i in range(nu):
            ua, ub = i / nu + 0.035, (i + 1) / nu - 0.035
            _decal(sp, front, ua - 0.01, 0.1, ub + 0.01, 0.84, REVEAL)
            on = 0.0 if (i + k + v) % 5 == 4 else 0.95
            sp.window(sp.on_face(*front, ua, 0.14, ub, 0.8), WARM_WINDOW, light_alpha=on)
            m = 4
            for j in range(1, m):
                uu = ua + (ub - ua) * j / m
                q0 = add(_face_pt(front, uu, 0.14), mul(sn, 0.03))
                q1 = add(_face_pt(front, uu, 0.8), mul(sn, 0.03))
                sp.line(q0, q1, 0.05, "#cfc6b6")
            _decal(sp, front, ua + (ub - ua) * 0.62, 0.14, ua + (ub - ua) * 0.74, 0.7, Mat("#3a3f47", 0.3), 0.02)
        for e, fr in enumerate(ends):
            band_on(sp, fr, 0.9, 0.97, accent)
            nw = max(1, int(length(fr[1]) / 2.2))
            for i in range(nw):
                ua = (i + 0.3) / nw
                _deep_win(sp, fr, ua, 0.35, ua + 0.4 / nw, 0.72, lit_a=0.0 if (i + k + e) % 4 == 3 else 0.9)
        for i in range(3):
            ua = (i + 0.35) / 3
            _deep_win(sp, back, ua, 0.45, ua + 0.1, 0.72, lit_a=0.8)
    # 꼭대기: 얇은 흙 둑, 빛 관, 천창
    ztop = zs[nt]
    sa, sbk = sb + 0.25, sfs[-1] - 0.25
    p, q = X(t0 + 0.25, sa, 0), X(t1 - 0.25, sbk, 0)
    rx0, ry0, rx1, ry1 = min(p[0], q[0]), min(p[1], q[1]), max(p[0], q[0]), max(p[1], q[1])
    sp.tbox(rx0, ry0, rx1, ry1, 0.45, 0.45, BERM, top=ROOF_BERM, z=ztop)
    zr = ztop + 0.45
    sm = (sa + sbk) / 2
    npipe = (3, 4, 3, 3, 2)[v]
    for i in range(npipe):
        t = t0 + L * (i + 0.5) / npipe
        c = X(t - L * 0.12 / npipe * 2, sm - 0.35, zr)
        sp.window(_orient([X(t + 0.15, sm - 0.5, zr + 0.01), X(t + 1.1, sm - 0.5, zr + 0.01),
                           X(t + 1.1, sm + 0.45, zr + 0.01), X(t + 0.15, sm + 0.45, zr + 0.01)], (0, 0, 1)),
                  WARM_WINDOW, frame="#9aa1aa", light_alpha=0.7)
        sp.cyl(c, add(c, (0, 0, 0.75)), 0.24, SILVER, bands=[0.5], band_color="#8a9099")
        sp.sphere(add(c, (0, 0, 0.75)), 0.3, Mat("#cfe6f5", 0.8), clip_z=c[2] + 0.75)
        sp.glow(add(c, (0, 0, 0.9)), 7, WARM_WINDOW, 0.5)
        if v == 3:
            m = add(c, (0, 0, 1.45))
            sp.line(add(c, (0, 0, 1.0)), m, 0.05, "#9aa1aa")
            tilt = norm((-0.42, 0.88, 1.2))
            u_, w2 = basis(tilt)
            sp.quad(add(m, add(mul(u_, -0.38), mul(w2, -0.32))), mul(u_, 0.76), mul(w2, 0.64), Mat("#DCE6EE", 0.95),
                    back=STEEL)
    if v == 2:
        legs(sp, [X(t0 + 0.8, sb + 0.6, zr + 0.2), X(t0 + 3.2, sb + 0.6, zr + 0.2)], zr)
        _radiator(sp, X(t0 + 0.6, sb + 0.6, zr + 0.2), mul(tdir, 2.9), (0, 0, 0.9), 5)
    antenna(sp, X(t1 - 0.6, sb + 0.6, zr), 1.3)
    # 정원 띠 (위층부터: 앞의 층 몸체에 가려지지 않게 모든 몸체 다음에)
    for k in range(nt - 2, -1, -1):
        z = zs[k + 1]
        s_front = sfs[k]
        bed = 0.95 if depth > 2.0 else 0.8
        bx(t0 + 0.12, s_front - bed, t1 - 0.12, s_front - 0.06, z, 0.42, PLANTER, top=SOIL)
        n = max(4, int(L / 1.05))
        for i in range(n):
            t = t0 + 0.12 + (L - 0.24) * (i + 0.5) / n
            r = 0.38 + 0.08 * ((i * 7 + k) % 3)
            _shrub(sp, *X(t, s_front - bed / 2, 0)[:2], z + 0.4, r, flowers[(i + k) % 3], 1.0)
        for i in (1, 3) if L > 8 else (1,):
            t = t0 + L * i / 4
            sp.tree(X(t, s_front - bed * 0.5, z + 0.4), 1.6, 0.55, flowers[i % 2])
    # 바닥층 앞: 길과 화단, 출입 에어록, 가로등
    z = zb
    if not along_x:
        sp.box(t1, -1.0, zb, 1.05, 2.0, 2.4, CONCRETE, top=Mat("#b3a48e"))
        vf = Sprite.box_faces(t1, -1.0, zb, 1.05, 2.0, 2.4)
        door(sp, vf["right"], 0.25, 0.75, 0.8, Mat("#5c626b", 0.3))
        band_on(sp, vf["left"], 0.85, 0.95, accent)
    else:
        sp.box(-2.6, -t0, zb, 2.0, 1.25, 2.4, CONCRETE, top=Mat("#b3a48e"))
        vf = Sprite.box_faces(-2.6, -t0, zb, 2.0, 1.25, 2.4)
        door(sp, vf["left"], 0.25, 0.75, 0.8, Mat("#5c626b", 0.3))
        band_on(sp, vf["right"], 0.85, 0.95, accent)
    p = X(t0 + 0.4, sf0 + 0.15, 0)
    q = X(t1 - 0.4, sf0 + 0.55, 0)
    sp.box(min(p[0], q[0]), min(p[1], q[1]), zb, abs(q[0] - p[0]), abs(q[1] - p[1]), 0.3, PLANTER, top=SOIL)
    n = max(4, int(L / 1.3))
    for i in range(n):
        t = t0 + 0.4 + (L - 0.8) * (i + 0.5) / n
        _shrub(sp, *X(t, sf0 + 0.35, 0)[:2], zb + 0.3, 0.26, flowers[i % 3], 1.0)
    for t in (t0 + 0.2, t1 - 0.2):
        lp = X(t, sf0 + 0.6, 0)
        sp.line((lp[0], lp[1], zb), (lp[0], lp[1], zb + 2.4), 0.06, "#5c626b")
        sp.lamp((lp[0], lp[1], zb + 2.5), WARM_WINDOW, 10)
    for k in range(nt - 1):
        sp.glow(X((t0 + t1) / 2, sfs[k] - 0.6, zs[k + 1] + 0.8), 26, GARDEN_LIGHT, 0.25)


# ═════════════════════════════════════════════════════════════════════
# 연구 (research_lab 계열)
# ═════════════════════════════════════════════════════════════════════

def _front_arc(c, r, z, k=36, front=True, margin=0.0):
    """수평 원의 앞(카메라 쪽) 또는 뒤 반쪽 점들."""
    pts, out = [], []
    for i in range(k + 1):
        t = 2 * math.pi * i / k
        d = (math.cos(t), math.sin(t), 0.0)
        if (dot(d, VIEW) > margin) == front:
            pts.append((c[0] + r * d[0], c[1] + r * d[1], z))
        elif pts:
            out.append(pts)
            pts = []
    if pts:
        out.append(pts)
    if len(out) > 1 and out[0][0] == (c[0] + r, c[1], z) and out[-1][-1] == (c[0] + r, c[1], z):
        out = [out[-1] + out[0][1:]] + out[1:-1]
    return out


def _glass_dome(sp: Sprite, c, rx, ry, h, z0, rings=(0.3, 0.58, 0.82), ribs=12, rib_col="#dfe9f2", alpha=0.3):
    """유리 돔 (타원 바닥 rx × ry, 높이 h): 그림은 반투명 채움과 갈비, 3D는 유리 껍질."""
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


def _curtain_drum(sp: Sprite, cx, cy, r, z0, z1, storeys=2, cols=16, glass=Mat("#3b5269", 0.75),
                  frame="#d7dde3", glow=WARM_WINDOW, slab=WHITE):
    """유리 커튼월 원통: 층마다 둘레를 판으로 나눈 창 (뒤쪽 판은 3D에만)."""
    p0, p1 = (cx, cy, z0), (cx, cy, z1)
    sp.cyl(p0, p1, r, glass, cap_mat=SILVER)
    fh = (z1 - z0) / storeys
    for k in range(storeys):
        for j in range(cols):
            a0 = 360.0 * j / cols + 1.2
            a1 = 360.0 * (j + 1) / cols - 1.2
            s0, s1 = (k * fh + 0.12) / (z1 - z0), ((k + 1) * fh - 0.2) / (z1 - z0)
            on = 0.0 if (j * 3 + k) % 7 == 5 else 0.9
            sp.window(Sprite.cyl_patch(p0, p1, r, s0, s1, a0, a1, 0.02), glow, frame=frame, glass=glass,
                      light_alpha=on)
        if k > 0:
            cyl_ring(sp, p0, p1, r, (k * fh - 0.12) / (z1 - z0), (k * fh + 0.06) / (z1 - z0), slab)


@typed("research_institute", 16, 12, 12.0, "종합 연구원", heights=[11.2, 11.6, 11.4, 11.0, 11.4])
def research_institute(sp: Sprite, v: int):
    """ㄱ자로 꺾인 두 실험동 안쪽 모서리에 유리 원형 홀(돔)이 서고, 앞은 광장. 지붕에 관측 돔과 기둥 장비."""
    band = (VIOLET, VIOLET, VIOLET, ORANGE, TEAL)[v]
    body = (WHITE, WHITE, Mat("#E5DCC8", 0.05), WHITE, Mat("#D9DEE3", 0.1))[v]
    zb = 0.3
    hA = (6.2, 6.2, 9.0, 6.2, 6.2)[v]              # 뒤 실험동 (x 방향) 높이
    hB = (6.2, 9.0, 6.2, 6.2, 6.2)[v]              # 왼 실험동 (y 방향) 높이
    nsA, nsB = (2 if hA < 8 else 3), (2 if hB < 8 else 3)
    ax0, ax1, ay0, ay1 = -4.0, 7.5, -5.6, -2.0
    bx0, bx1, by0, by1 = -7.6, -4.0, -5.6, 5.4
    R = (2.8, 2.8, 2.8, 3.1, 2.8)[v]
    cx, cy = -0.8, 1.0
    zd = (7.2, 6.4, 7.2, 6.6, 7.2)[v]              # 원형 홀 유리벽 꼭대기
    sp.contact_shadow(-0.2, -0.2, 7.8, 5.8, 0.5)
    sp.box(-7.85, -5.85, 0, 15.7, 11.7, zb, CONCRETE, top=Mat("#b3a690"))
    # 광장 포장과 길
    sp.face([(-3.9, -1.9, zb + 0.01), (7.6, -1.9, zb + 0.01), (7.6, 5.7, zb + 0.01), (-3.9, 5.7, zb + 0.01)], PAVE,
            normal=(0, 0, 1), ao=0, edge=False)
    for k in range(1, 5):
        x = -3.9 + k * 2.3
        sp.line((x, -1.9, zb + 0.02), (x, 5.7, zb + 0.02), 0.05, "#a39784")
    for k in range(1, 4):
        y = -1.9 + k * 1.9
        sp.line((-3.9, y, zb + 0.02), (7.6, y, zb + 0.02), 0.05, "#a39784")

    zdt = zd + 0.5 + (2.5, 2.2, 2.7, 2.4, 3.4)[v]
    drum2d = _screen_hull(_cyl_pts(cx, cy, R + 0.15, zb, zd + 0.5) + _cyl_pts(cx, cy, R * 0.55, zd, zdt))

    def wing(x0, y0, x1, y1, h, ns, long_face):
        sp.box(x0, y0, zb, x1 - x0, y1 - y0, h, body, top=SILVER)
        sides = _box_sides(x0, y0, zb, x1 - x0, y1 - y0, h)
        for nm, fr in sides.items():
            band_on(sp, fr, 1 - 0.55 / h, 1 - 0.2 / h, band)
            n = max(1, int(length(fr[1]) / 1.55))
            for k in range(ns):
                vv0 = (k * (h - 0.4) / ns + 0.9) / h
                vv1 = vv0 + 1.15 / h
                for i in range(n):
                    if nm == long_face and k == 0 and i in (n // 2,):
                        continue
                    ua = (i + 0.18) / n
                    on = 0.0 if (i * 2 + k + v + len(nm)) % 6 == 0 else 0.95
                    q = sp.on_face(*fr, ua, vv0, ua + 0.64 / n, vv1)
                    _win(sp, q, WARM_WINDOW, on, dark2d=_covered(drum2d, q))
        return sides

    # 왼 실험동 (y 방향, 꺾인 모서리 포함) → 뒤 실험동 (x 방향)
    sB = wing(bx0, by0, bx1, by1, hB, nsB, "+x")
    sA = wing(ax0, ay0, ax1, ay1, hA, nsA, "+y")
    n = max(1, int(length(sB["+x"][1]) / 1.55))
    door(sp, sB["+x"], (n // 2 + 0.1) / n, (n // 2 + 0.9) / n, 2.1 / hB, Mat("#cfd6dc", 0.3))
    n = max(1, int(length(sA["+y"][1]) / 1.55))
    door(sp, sA["+y"], (n // 2 + 0.1) / n, (n // 2 + 0.9) / n, 2.1 / hA, Mat("#cfd6dc", 0.3))
    # 지붕 설비: 공조 상자와 배기구 줄
    zA, zB = zb + hA, zb + hB
    for (x, y, z) in ((ax0 + 1.0, ay0 + 0.6, zA), (bx0 + 0.6, by0 + 2.6, zB)):
        sp.box(x, y, z, 1.8, 1.2, 0.6, STEEL, top=DARK)
    for i in range(3):
        x = ax0 + 4.0 + i * 0.9
        sp.cyl((x, ay0 + 1.1, zA), (x, ay0 + 1.1, zA + 0.6), 0.2, STEEL, bands=[0.7], band_color="#9B7AD6")
        sp.cyl((x, ay0 + 1.1, zA + 0.6), (x, ay0 + 1.1, zA + 0.7), 0.3, Mat("#9aa1aa", 0.3), cap_mat=DARK)
    # 관측 돔 (뒤 실험동 끝) 또는 접시
    ox, oy = ax1 - 1.7, (ay0 + ay1) / 2
    if v != 1:
        sp.cyl((ox, oy, zA), (ox, oy, zA + 0.8), 1.25, body, cap_mat=SILVER)
        sp.sphere((ox, oy, zA + 0.8), 1.25, Mat("#F1F2F0", 0.3), clip_z=zA + 0.8)
        sp.face(_orient([(ox + 0.45, oy - 0.35, zA + 1.0), (ox + 0.45, oy + 0.75, zA + 1.0),
                         (ox + 0.05, oy + 0.75, zA + 2.0), (ox + 0.05, oy - 0.35, zA + 2.0)], (1, 0.3, 0.6)),
                Mat("#1b1e24"), ao=0, edge=False)
        sp.lamp((ox, oy, zA + 2.15), RED_LIGHT, 6)
    else:
        sp.cyl((ox, oy, zA), (ox, oy, zA + 0.5), 0.6, STEEL)
        sp.line((ox, oy, zA + 0.5), (ox, oy, zA + 1.6), 0.12, "#9aa1aa")
        _dish(sp, (ox, oy, zA + 2.2), norm((0.25, 0.8, 0.75)), 1.5)
    # 기둥 장비 (왼 실험동 앞 끝): 기상 기둥과 작은 접시, 안테나
    mx, my = bx0 + 1.2, by1 - 1.4
    mh = (5.2, 2.6, 5.2, 5.0, 4.4)[v]
    sp.box(mx - 0.3, my - 0.3, zB, 0.6, 0.6, 0.3, STEEL)
    sp.line((mx, my, zB + 0.3), (mx, my, zB + mh), 0.1, "#9aa1aa")
    sp.box(mx - 0.25, my - 0.25, zB + mh * 0.55, 0.5, 0.5, 0.45, GOLD)
    sp.line((mx - 0.6, my, zB + mh * 0.85), (mx + 0.6, my, zB + mh * 0.85), 0.06, "#9aa1aa")
    sp.sphere((mx + 0.6, my, zB + mh * 0.85), 0.12, WHITE)
    sp.lamp((mx, my, zB + mh + 0.12), RED_LIGHT, 6)
    _dish(sp, (bx1 - 1.0, by1 - 2.6, zB + 1.0), norm((0.3, 0.9, 0.7)), 0.7)
    sp.line((bx1 - 1.0, by1 - 2.6, zB), (bx1 - 1.0, by1 - 2.6, zB + 0.7), 0.08, "#9aa1aa")
    if v == 4:
        antenna(sp, (ax0 + 2.4, ay0 + 0.4, zA), 2.6)
    if v == 3:
        for k in range(3):
            o = (ax0 + 3.6 + k * 1.3, ay0 + 0.5, zA + 0.25)
            sp.quad(o, (1.15, 0, 0), (0, 2.4, 0.35), SOLAR, back=STEEL)
            sp.panel_grid(o, (1.15, 0, 0), (0, 2.4, 0.35), 2, 3, "#6f86b0", 0.45, 0.6)
    # 원형 홀과 이음 통로
    sp.box(cx - 0.9, ay1, zb, 1.8, cy - R - ay1 + 0.6, 3.2, body, top=SILVER)
    sp.box(bx1, cy - 0.9, zb, cx - R - bx1 + 0.6, 1.8, 3.2, body, top=SILVER)
    _curtain_drum(sp, cx, cy, R, zb, zd, storeys=2, cols=16)
    sp.cyl((cx, cy, zd), (cx, cy, zd + 0.5), R + 0.15, body, cap_mat=SILVER)
    cyl_ring(sp, (cx, cy, zd), (cx, cy, zd + 0.5), R + 0.15, 0.35, 0.7, band)
    zt = zd + 0.5
    if v in (0, 2, 3):
        hd = (2.5, 0.0, 2.7, 2.4, 0.0)[v]
        sp.disc((cx, cy, zt + 0.01), (0, 0, 1), R, Mat("#2f3a44", 0.3), edge=False)
        sp.tree((cx + 0.3, cy - 0.4, zt - 1.2), 2.4, 1.0, LEAF)
        sp.glow((cx, cy, zt + 0.8), 34, WARM_WINDOW, 0.4)
        _glass_dome(sp, (cx, cy), R, R, hd, zt, rings=(0.35, 0.68), ribs=12, alpha=0.3)
        sp.cyl((cx, cy, zt + hd - 0.15), (cx, cy, zt + hd + 0.45), 0.45, body, cap_mat=SILVER)
        sp.lamp((cx, cy, zt + hd + 0.6), RED_LIGHT, 6)
    else:
        hd = (0.0, 2.2, 0.0, 0.0, 2.4)[v]
        sp.dome((cx, cy, zt), R + 0.1, hd, Mat("#ECE7DC", 0.15))
        for zz in (0.35, 0.65):
            k = math.sqrt(max(0.0, 1 - zz ** 2))
            sp.ring3((cx, cy, zt + hd * zz), (R + 0.1) * k, "#c9c3b6", 0.05)
        if v == 1:
            sp.disc((cx, cy, zt + hd - 0.02), (0, 0, 1), 0.9, GLASS, edge=False)
            sp.ring3((cx, cy, zt + hd), 0.9, "#cfc6b6", 0.1, front_only=False)
            sp.light_poly([(cx + 0.9 * math.cos(t / 16 * 2 * math.pi), cy + 0.9 * math.sin(t / 16 * 2 * math.pi),
                            zt + hd + 0.01) for t in range(16)], WARM_WINDOW, 0.8)
        else:
            # 꼭대기 작은 관측 돔
            sp.cyl((cx, cy, zt + hd - 0.3), (cx, cy, zt + hd + 0.3), 0.9, body, cap_mat=SILVER)
            sp.sphere((cx, cy, zt + hd + 0.3), 0.9, Mat("#F1F2F0", 0.3), clip_z=zt + hd + 0.3)
            sp.face(_orient([(cx + 0.35, cy - 0.25, zt + hd + 0.45), (cx + 0.35, cy + 0.55, zt + hd + 0.45),
                             (cx + 0.05, cy + 0.55, zt + hd + 1.15), (cx + 0.05, cy - 0.25, zt + hd + 1.15)],
                            (1, 0.3, 0.6)), Mat("#1b1e24"), ao=0, edge=False)
            sp.lamp((cx, cy, zt + hd + 1.3), RED_LIGHT, 6)
    # 홀 정문 (광장 쪽) 차양과 등
    ang = math.radians(45)
    d = (math.cos(ang), math.sin(ang), 0.0)
    side = (-d[1], d[0], 0.0)
    c0 = (cx + d[0] * R, cy + d[1] * R, zb)
    can = [add(add(c0, mul(side, -1.3)), (0, 0, 2.6)), add(add(c0, mul(side, 1.3)), (0, 0, 2.6)),
           add(add(add(c0, mul(side, 1.3)), mul(d, 1.6)), (0, 0, 2.6)),
           add(add(add(c0, mul(side, -1.3)), mul(d, 1.6)), (0, 0, 2.6))]
    for q in (can[2], can[3]):
        sp.line((q[0], q[1], zb), q, 0.08, "#9aa1aa")
    sp.face(_orient(can, (0, 0, 1)), SILVER, ao=0)
    sp.face(_orient([can[3], can[2], add(can[2], (0, 0, -0.28)), add(can[3], (0, 0, -0.28))], d), band, ao=0,
            edge=False)
    dg = [add(add(c0, mul(side, -0.75)), (0, 0, 0.0)), add(add(c0, mul(side, 0.75)), (0, 0, 0.0)),
          add(add(c0, mul(side, 0.75)), (0, 0, 2.2)), add(add(c0, mul(side, -0.75)), (0, 0, 2.2))]
    sp.window(_orient([add(p, mul(d, 0.06)) for p in dg], d), "#ffe9b8", frame="#d7dde3", glass=Mat("#3a4d60", 0.6))
    sp.lamp(add(add(c0, mul(d, 1.5)), (0, 0, 2.45)), WARM_WINDOW, 9)
    # 광장: 화단 나무, 가로등, 시료 장비 (밖에 놓인 지진계 돔)
    plants = (((3.6, 3.6), (6.2, 0.6), (1.2, 4.8)), ((4.0, 3.4), (6.4, 1.0)), ((3.6, 3.6), (6.2, 0.6), (1.2, 4.8)),
              ((4.4, 4.2), (6.2, 0.4)), ((3.6, 3.6), (6.2, 0.6), (1.2, 4.8)))[v]
    items = []
    for i, (x, y) in enumerate(plants):
        def bed(x=x, y=y, i=i):
            sp.cyl((x, y, zb), (x, y, zb + 0.45), 0.8, PLANTER, cap_mat=SOIL)
            sp.tree((x, y, zb + 0.45), 2.2, 0.75, (LEAF, GREEN)[i % 2])
        items.append(((x, y, 0), bed))
    for (x, y) in ((7.2, 5.2), (-3.4, 5.3), (7.2, -1.5)):
        def post(x=x, y=y):
            sp.line((x, y, zb), (x, y, zb + 2.8), 0.07, "#5c626b")
            sp.lamp((x, y, zb + 2.9), WARM_WINDOW, 11)
        items.append(((x, y, 0), post))
    if v in (0, 3, 4):
        def seismo():
            sp.cyl((5.8, 3.6, zb), (5.8, 3.6, zb + 0.25), 0.7, STEEL)
            sp.dome((5.8, 3.6, zb + 0.25), 0.6, 0.45, GOLD)
            sp.lamp((6.5, 3.6, zb + 0.4), CYAN_LIGHT, 5)
        items.append(((5.8, 3.6, 0), seismo))
    sp.parts(items)


def _radio_dish(sp: Sprite, bx, by, r, n, ze, mat: Mat = WHITE, feed="quad", tower: Mat = WHITE, band: Mat = VIOLET):
    """경위대 위의 포물면 전파 접시. 받침 탑 → 방위 머리 → 고도 축 팔 → 뒤 받침 → 접시 → 급전 다리·급전부.
    그림은 테두리 원판에 포물면 위의 고리·갈비를 얹어 오목함을 보이고, 3D에는 오목한 그릇(원뿔대)을 남긴다."""
    n = norm(n)
    side = norm((-n[1], n[0], 0.0))
    u, w = basis(n)
    depth = r * 0.28
    f = r * r / (4 * depth)
    E = (bx, by, ze)
    V = add(E, mul(n, 0.6))                       # 접시 꼭지 (가운데 밑)
    C = add(V, mul(n, depth))                     # 테두리 가운데
    F = add(V, mul(n, f))                         # 초점 (급전부)

    def bowl(rho, th):
        return add(add(V, mul(n, depth * (rho / r) ** 2)), mul(add(mul(u, math.cos(th)), mul(w, math.sin(th))), rho))
    facing = dot(n, VIEW) > 0

    def mount():
        sp.cyl((bx, by, 0), (bx, by, 0.3), 1.6, CONCRETE, cap_mat=Mat("#b3a690"))
        sp.frustum((bx, by, 0.3), (bx, by, ze - 1.45), 0.95, 0.62, tower, bands=[0.5], band_color="#b9b2a5")
        cyl_ring(sp, (bx, by, 0.3), (bx, by, ze - 1.45), 0.95, 0.06, 0.12, band)
        ang = Sprite.facing_angle((bx, by, 0.3), (bx, by, ze - 1.45), norm((0.6, 1.0, 0)))
        sp.face(Sprite.cyl_patch((bx, by, 0.3), (bx, by, ze - 1.45), 0.92, 0.02, 0.32, ang - 14, ang + 14), DARK, ao=0)
        sp.cyl((bx, by, ze - 1.45), (bx, by, ze - 1.0), 1.0, STEEL, cap_mat=Mat("#9aa1aa", 0.3))
        for s in (-1, 1):
            a = add(E, mul(side, s * 1.05))
            sp.polyline3([(a[0], a[1], ze - 1.0), a], "#c9ccd1", 0.32)
            sp.disc(add(a, mul(side, s * 0.18)), side, 0.28, STEEL)
        # 뒤 받침 구조와 수신기 칸 (평형추)
        sp.frustum(sub(V, mul(n, 0.05)), sub(V, mul(n, 1.0)), r * 0.42, 0.45, Mat("#C9CCD1", 0.3), caps=True)

    def dish():
        # 그림: 테두리 원판 (앞면은 위가 밝고 아래가 조금 어두운 오목 음영)
        rim = [PV(add(C, mul(add(mul(u, math.cos(2 * math.pi * i / 48)), mul(w, math.sin(2 * math.pi * i / 48))), r)))
               for i in range(48)]
        if facing:
            col = lit(mat.albedo, n, mat.gloss)
            ys = [q[1] for q in rim]
            xm = sum(q[0] for q in rim) / len(rim)
            fill = sp.gradient([(0, hexc(scale(col, 1.04)), 1.0), (0.55, hexc(col), 1.0), (1, hexc(scale(col, 0.8)), 1.0)],
                               xm, min(ys), xm, max(ys))
            sp.poly2(rim, fill, hexc(scale(col, 0.62)), 0.6)
        else:
            col = lit(STEEL.albedo, mul(n, -1), STEEL.gloss)
            sp.poly2(rim, hexc(col), hexc(scale(col, 0.62)), 0.6)
        # 3D: 오목한 그릇
        rings = (0.0, 0.3, 0.58, 0.82, 1.0)
        for a, b in zip(rings, rings[1:]):
            p0 = add(V, mul(n, depth * a * a))
            p1 = add(V, mul(n, depth * b * b))
            sp._rec(("fru", p0, p1, r * a, r * b, mat, False, mat, (), None, None))
        sp.ring3(C, r, "#b9b2a5", 0.09, normal=n, front_only=False, seg=32)
        for k in (0.36, 0.7):
            sp.ring3(add(V, mul(n, depth * k * k + 0.02)), r * k, "#cfc8bb", 0.045, normal=n, front_only=False, seg=24)
        for i in range(12):
            th = 2 * math.pi * (i + 0.5) / 12
            sp.polyline3([add(bowl(r * t / 6, th), mul(n, 0.02)) for t in (1, 3, 4.5, 6)], "#d8d2c6", 0.035, 0.85)
        sp.disc(add(V, mul(n, 0.03)), n, r * 0.12, Mat("#C9CCD1", 0.3))

    def feedpart():
        if feed == "quad":
            for i in range(4):
                th = math.radians(45 + 90 * i)
                sp.line(bowl(r * 0.92, th), F, 0.1, "#8a9099")
            sp.cyl(sub(F, mul(n, 0.35)), add(F, mul(n, 0.3)), 0.26, STEEL, cap_mat=GOLD)
        else:                                     # 카세그레인: 부반사경과 다리 셋
            for i in range(3):
                th = math.radians(90 + 120 * i)
                sp.line(bowl(r * 0.6, th), F, 0.1, "#8a9099")
            sp.disc(F, mul(n, -1), r * 0.16, WHITE, back=STEEL)
            sp.cyl(add(V, mul(n, 0.02)), add(V, mul(n, 0.9)), 0.28, STEEL, cap_mat=GOLD)
        sp.lamp(add(F, (0, 0, 0.45)), RED_LIGHT, 6)
    mount()
    if facing:
        dish()
        feedpart()
    else:
        feedpart()
        dish()
    return C, F


def _hut(sp: Sprite, x0, y0, w, d, h, band: Mat = VIOLET, rad=True):
    """작은 제어실: 흰 상자, 연구 띠, 불 켜진 창, 문, 방열판과 안테나."""
    sp.box(x0 - 0.15, y0 - 0.15, 0, w + 0.3, d + 0.3, 0.25, STEEL)
    sp.box(x0, y0, 0.25, w, d, h, WHITE, top=SILVER)
    f = _box_sides(x0, y0, 0.25, w, d, h)
    for nm, fr in f.items():
        band_on(sp, fr, 0.84, 0.94, band)
    windows_row(sp, f["+y"], 3 if w > 3 else 2, 0.4, 0.7, 0.1, 0.08)
    windows_row(sp, f["-y"], 2, 0.4, 0.7, 0.15, 0.1)
    door(sp, f["+x"], 0.3, 0.7, 0.75, Mat("#cfd6dc", 0.3))
    zt = 0.25 + h
    sp.box(x0 + 0.3, y0 + 0.3, zt, 1.0, 0.8, 0.45, STEEL, top=DARK)
    if rad:
        _radiator(sp, (x0 + 1.6, y0 + 0.5, zt + 0.15), (w - 2.0, 0, 0), (0, 0, 0.9), 4)
        legs(sp, [(x0 + 1.7, y0 + 0.5, zt + 0.15), (x0 + w - 0.5, y0 + 0.5, zt + 0.15)], zt)
    antenna(sp, (x0 + w - 0.3, y0 + d - 0.3, zt), 1.8)
    return zt


@typed("deep_space_array", 16, 16, 12.0, "전파 망원경 배열", heights=[9.4, 9.8, 9.8, 8.2, 11.8])
def deep_space_array(sp: Sprite, v: int):
    """경위대에 얹은 포물면 전파 접시 서넛이 모두 같은 하늘을 본다. 앞쪽에 제어실, 땅에는 케이블 길."""
    n = ((0.24, 0.55, 0.8), (0.14, 0.4, 0.9), (0.72, 0.3, 0.62), (0.22, 0.52, 0.82), (0.28, 0.66, 0.7))[v]
    dishes = {
        0: [(-4.4, -4.7, 3.0), (4.1, -4.6, 3.0), (-4.7, 3.1, 3.0), (3.1, 2.3, 3.0)],
        1: [(-4.3, -4.6, 3.4), (4.0, -4.3, 3.4), (-4.6, 3.3, 3.4)],
        2: [(-4.6, -4.4, 3.3), (3.6, -4.4, 3.3), (-4.4, 3.6, 3.3)],
        3: [(-5.0, -2.2, 2.7), (-1.6, -5.2, 2.7), (3.6, -4.6, 2.7), (-4.8, 4.0, 2.7)],
        4: [(-2.2, -2.6, 4.3), (4.9, -3.6, 2.3), (-4.9, 4.7, 2.3)],
    }[v]
    feed = ("quad", "quad", "quad", "sub", "sub")[v]
    hx, hy, hw, hd = ((-0.9, 4.7, 3.2, 2.4), (2.2, 3.4, 3.4, 2.6), (2.0, 3.0, 3.4, 2.6), (2.0, 2.6, 3.4, 2.6),
                      (2.0, 3.4, 3.6, 2.6))[v]
    sp.contact_shadow(0, 0, 7.6, 7.6, 0.28)
    # 케이블 길: 접시마다 받침에서 접속함으로, 거기서 제어실로 (노란 표시 줄)
    jx, jy = ((-0.6, -0.8), (-0.6, -0.6), (-0.6, -0.6), (-0.8, -1.0), (0.6, 0.0))[v]
    for (bx, by, r) in dishes:
        sp.polyline3([(bx, by, 0.04), (bx, jy, 0.04), (jx, jy, 0.04)], "#3a3f47", 0.22)
        sp.polyline3([(bx, by, 0.06), (bx, jy, 0.06), (jx, jy, 0.06)], "#E9C24A", 0.05, 0.6)
    hcx = hx + hw * 0.5
    sp.polyline3([(jx, jy, 0.04), (hcx, jy, 0.04), (hcx, hy, 0.04)], "#3a3f47", 0.26)
    sp.polyline3([(jx, jy, 0.06), (hcx, jy, 0.06), (hcx, hy, 0.06)], "#E9C24A", 0.05, 0.6)
    sp.box(jx - 0.45, jy - 0.35, 0, 0.9, 0.7, 0.6, Mat("#5b6470", 0.2), top=Mat("#7A8490", 0.2))
    for (x, y) in ((-6.8, -0.4), (6.6, 6.2), (0.6, -6.9), (-6.5, 6.9), (6.9, 0.8)):
        sp.rock((x, y, 0), 0.35)
    items = []
    for i, (bx, by, r) in enumerate(dishes):
        ze = 2.0 + r * 1.25
        items.append(((bx, by, 0), lambda bx=bx, by=by, r=r, ze=ze: _radio_dish(sp, bx, by, r, n, ze, feed=feed)))
    items.append(((hx + hw / 2, hy + hd / 2, 0), lambda: _hut(sp, hx, hy, hw, hd, 2.5, rad=v != 3)))
    for (x, y) in ((7.3, 7.3), (-7.2, 7.0), (7.3, -6.2)) if v else ((7.3, 7.3), (7.3, -6.2)):
        items.append(((x, y, 0), lambda x=x, y=y: _mast(sp, x, y, 2.8, AMBER, 14)))
    sp.parts(items)


# ═════════════════════════════════════════════════════════════════════
# 굴착 (excavator 계열)
# ═════════════════════════════════════════════════════════════════════

TRACK = Mat("#3B3F46", 0.1)
PIT_MATS = (Mat("#8A8378"), Mat("#78716a"), Mat("#655f58"), Mat("#544f49"), Mat("#45413c"))
PIT_WALL = Mat("#857d71")


class _Only3D:
    """이 안에서 그린 것은 3D 모형에만 남고 그림(2D)에서는 지운다."""
    def __init__(self, sp: Sprite):
        self.sp = sp

    def __enter__(self):
        s = self.sp
        self.keep = (len(s.body), len(s.light), len(s.defs), len(s.ldefs), s.minx, s.miny, s.maxx, s.maxy)

    def __exit__(self, *a):
        s = self.sp
        nb, nl, nd, nld, s.minx, s.miny, s.maxx, s.maxy = self.keep
        del s.body[nb:], s.light[nl:], s.defs[nd:], s.ldefs[nld:]


class _Clip2D:
    """그림(2D)에서 화면 다각형 안쪽만 보이게 묶는다 (땅 아래로 판 곳: 앞 가장자리 너머는 땅에 가린다)."""
    def __init__(self, sp: Sprite, poly2d):
        self.sp, self.poly = sp, poly2d

    def __enter__(self):
        s = self.sp
        self.cid = s._id("cp")
        clip = '<clipPath id="%s"><polygon points="%s"/></clipPath>' % (self.cid, pts_attr(self.poly))
        s.defs.append(clip)
        s.body.append('<g clip-path="url(#%s)">' % self.cid)
        self.nl, self.nld = len(s.light), len(s.ldefs)
        s.ldefs.append(clip)
        s.light.append('<g clip-path="url(#%s)">' % self.cid)

    def __exit__(self, *a):
        s = self.sp
        s.body.append("</g>")
        if len(s.light) == self.nl + 1:          # 불빛이 없었다
            del s.light[self.nl:], s.ldefs[self.nld:]
        else:
            s.light.append("</g>")


def _rect_face(sp: Sprite, x0, y0, x1, y1, z, mat: Mat, edge=None):
    if x1 - x0 > 1e-3 and y1 - y0 > 1e-3:
        sp.face([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], mat, normal=(0, 0, 1), ao=0, edge=edge)


def _terraced_pit(sp: Sprite, rects, zs, foot, contents=None, mats=PIT_MATS, wall: Mat = PIT_WALL,
                  slope: Mat = BERM):
    """계단식 노천 구덩이. rects = [가장자리, 단 1, 단 2, ..., 바닥] (x0, y0, x1, y1), zs = 각 단의 높이 (안쪽일수록 낮다).
    가장자리 밖은 foot (z = 0)까지 흙 둑 비탈. 그리는 순서: 뒤 비탈 → 먼 쪽 단·벽 → 바닥 → 안의 것 →
    가까운 쪽 단 (안쪽부터) → 앞 비탈. 깊은 단일수록 어둡게 칠한다."""
    O = rects[0]
    zr = zs[0]
    top = [(O[0], O[1], zr), (O[2], O[1], zr), (O[2], O[3], zr), (O[0], O[3], zr)]
    if foot:
        fx0, fy0, fx1, fy1 = foot
        bot = [(fx0, fy0, 0.0), (fx1, fy0, 0.0), (fx1, fy1, 0.0), (fx0, fy1, 0.0)]
    order = ((3, 0), (0, 1), (1, 2), (2, 3))       # -x, -y 비탈 (뒤) 다음 +x, +y (앞)
    outs = {(0, 1): (0.0, -1.0, 0.0), (1, 2): (1.0, 0.0, 0.0), (2, 3): (0.0, 1.0, 0.0), (3, 0): (-1.0, 0.0, 0.0)}

    def slope_face(i):
        if not foot:
            return
        a, b = order[i]
        sp.face(_orient([bot[a], bot[b], top[b], top[a]], outs[(a, b)]), slope, ao=0.0, edge=False)
    slope_face(0)
    slope_face(1)
    n = len(rects)
    for k in range(n - 1):
        A, B = rects[k], rects[k + 1]
        m = mats[min(k, len(mats) - 1)]
        _rect_face(sp, A[0], A[1], A[2], B[1], zs[k], m)            # 먼 쪽 (-y) 띠
        _rect_face(sp, A[0], B[1], B[0], A[3], zs[k], m)            # 먼 쪽 (-x) 띠
        zl, zh = zs[k + 1], zs[k]
        sp.face(_orient([(B[0], B[1], zl), (B[2], B[1], zl), (B[2], B[1], zh), (B[0], B[1], zh)], (0, 1, 0)), wall,
                ao=0.35)
        sp.face(_orient([(B[0], B[1], zl), (B[0], B[3], zl), (B[0], B[3], zh), (B[0], B[1], zh)], (1, 0, 0)), wall,
                ao=0.35)
        sp.face(_orient([(B[0], B[3], zl), (B[2], B[3], zl), (B[2], B[3], zh), (B[0], B[3], zh)], (0, -1, 0)), wall)
        sp.face(_orient([(B[2], B[1], zl), (B[2], B[3], zl), (B[2], B[3], zh), (B[2], B[1], zh)], (-1, 0, 0)), wall)
    F = rects[-1]
    _rect_face(sp, F[0], F[1], F[2], F[3], zs[-1], mats[min(n - 1, len(mats) - 1)])
    # 그림 전용: 바닥 쪽이 더 어둡게 (깊이감)
    B1 = rects[1]
    q = [PV((B1[0], B1[1], zs[1])), PV((B1[2], B1[1], zs[1])), PV((B1[2], B1[3], zs[1])), PV((B1[0], B1[3], zs[1]))]
    c = PV(((F[0] + F[2]) / 2, (F[1] + F[3]) / 2, zs[-1]))
    rad = max(math.hypot(p[0] - c[0], p[1] - c[1]) for p in q)
    sp.poly2(q, sp.radial([(0, "#000000", 0.32), (0.6, "#000000", 0.14), (1, "#000000", 0.0)], c[0], c[1], rad))
    if contents:
        contents()
    for k in range(n - 2, -1, -1):
        A, B = rects[k], rects[k + 1]
        m = mats[min(k, len(mats) - 1)]
        _rect_face(sp, B[2], B[1], A[2], A[3], zs[k], m)            # 가까운 (+x) 띠
        _rect_face(sp, B[0], B[3], B[2], A[3], zs[k], m)            # 가까운 (+y) 띠
    slope_face(2)
    slope_face(3)


def _pit_z(rects, zs, x, y):
    """구덩이 안 점 (x, y)의 바닥 높이 (가장 안쪽 사각형 기준)."""
    z = None
    for R, zz in zip(rects, zs):
        if R[0] <= x <= R[2] and R[1] <= y <= R[3]:
            z = zz
    return 0.0 if z is None else z


def _track(sp: Sprite, x0, x1, y, tw=0.4, r=0.28, z=0.0, mat: Mat = TRACK):
    """x0~x1을 달리는 무한궤도 (가운데 y, 폭 tw, 높이 2r)."""
    ya, yb = y - tw / 2, y + tw / 2
    sp.cyl((x0 + r, ya, z + r), (x0 + r, yb, z + r), r, mat, cap_mat=STEEL)
    sp.box(x0 + r, ya, z, x1 - x0 - 2 * r, tw, 2 * r, mat)
    sp.panel_grid((x0 + r, ya, z + 2 * r), (x1 - x0 - 2 * r, 0, 0), (0, tw, 0), max(2, int((x1 - x0) / 0.3)), 1,
                  "#23262b", 0.5, 0.7)
    sp.cyl((x1 - r, ya, z + r), (x1 - r, yb, z + r), r, mat, cap_mat=STEEL)


def _loader(sp: Sprite, x, y, z, body: Mat = YELLOW, reach=-1.0, bucket_z=None, cab_side=1):
    """작은 궤도 굴삭기 (x 방향): 궤도 둘, 몸체, 운전실, 붐과 바가지. reach < 0이면 -x 쪽을 판다."""
    bz = z + 0.5 if bucket_z is None else bucket_z
    _track(sp, x - 1.1, x + 1.1, y - 0.55, 0.42, 0.27, z)
    sp.box(x - 0.85, y - 0.6, z + 0.5, 1.7, 1.2, 0.62, body, top=Mat("#F0D27A"))
    f = Sprite.box_faces(x - 0.85, y - 0.6, z + 0.5, 1.7, 1.2, 0.62)
    band_on(sp, f["left"], 0.0, 0.2, DARK)
    sp.box(x - 0.75, y - 0.55, z + 1.12, 0.6, 1.1, 0.35, Mat("#5c626b", 0.3))
    cx = x + 0.25 if cab_side > 0 else x - 0.65
    sp.box(cx, y - 0.05, z + 1.12, 0.62, 0.62, 0.78, GLASS, top=body)
    sp.light_poly([(cx + 0.63, y - 0.02, z + 1.25), (cx + 0.63, y + 0.54, z + 1.25), (cx + 0.63, y + 0.54, z + 1.8),
                   (cx + 0.63, y - 0.02, z + 1.8)], "#ffe2a0", 0.6)
    sx = x + (0.7 if reach > 0 else -0.7)
    ex = x + reach * 1.0
    tip = (x + reach * 1.9, y - 0.1, bz + 0.35)
    sp.polyline3([(sx, y - 0.1, z + 1.0), (ex, y - 0.1, z + 2.1), tip], "#C9A23A", 0.24)
    sp.polyline3([(sx, y - 0.1, z + 1.0), (ex, y - 0.1, z + 2.1), tip], "#E9C24A", 0.16)
    bx0 = tip[0] - (0.5 if reach < 0 else 0.0)
    sp.box(bx0, y - 0.45, bz - 0.05, 0.5, 0.7, 0.45, DARK, top=Mat("#5c626b"))
    sp.ellipsoid((bx0 + 0.25, y - 0.1, bz + 0.38), 0.24, 0.3, 0.12, REGOLITH)
    _track(sp, x - 1.1, x + 1.1, y + 0.55, 0.42, 0.27, z)
    sp.lamp((x + 0.9 * (1 if reach > 0 else -1), y + 0.35, z + 1.3), AMBER, 8)


def _conveyor(sp: Sprite, p0, p1, w=0.75, ground=lambda x, y: 0.0, legs_at=(0.35, 0.65, 0.92), rail="#E9C24A",
              lumps=True, legs=True, belt=True):
    """경사 컨베이어: 받침 다리 → 어두운 띠 → 흙덩이 → 노란 옆 난간 → 머리 굴대."""
    a = norm(sub(p1, p0))
    side = norm(cross((0.0, 0.0, 1.0), a))
    hw = mul(side, w / 2)
    for t in legs_at if legs else ():
        q = add(p0, mul(sub(p1, p0), t))
        for s in (-1, 1):
            b = add(q, mul(hw, s * 0.9))
            sp.line((b[0], b[1], ground(b[0], b[1])), (b[0], b[1], b[2] - 0.1), 0.09, "#7d848d")
        sp.line(add(add(q, mul(hw, -0.9)), (0, 0, -0.45)), add(add(q, mul(hw, 0.9)), (0, 0, -0.45)), 0.06, "#7d848d")
    if not belt:
        return
    belt = [sub(p0, hw), sub(p1, hw), add(p1, hw), add(p0, hw)]
    sp.face(_orient(belt, (0, 0, 1)), Mat("#2f3238", 0.1), two_sided=True, back=Mat("#5c626b"))
    if lumps:
        L = length(sub(p1, p0))
        for i in range(max(2, int(L / 0.9))):
            t = (i + 0.5) / max(2, int(L / 0.9))
            q = add(p0, mul(sub(p1, p0), t))
            sp.ellipsoid(add(q, (0, 0, 0.02)), 0.22, 0.2, 0.12, Mat("#8A8378"), clip_z=q[2] + 0.02)
    for s in (-1, 1):
        sp.line(add(add(p0, mul(hw, s)), (0, 0, 0.12)), add(add(p1, mul(hw, s)), (0, 0, 0.12)), 0.1, rail)
    sp.cyl(sub(p1, mul(hw, 1.1)), add(p1, mul(hw, 1.1)), 0.24, STEEL, cap_mat=DARK)
    sp.cyl(sub(p0, mul(hw, 1.1)), add(p0, mul(hw, 1.1)), 0.2, STEEL, cap_mat=DARK)


@typed("regolith_quarry", 14, 10, 4.0, "레골리스 채석장", heights=[3.6, 3.8, 3.6, 3.4, 3.8])
def regolith_quarry(sp: Sprite, v: int):
    """계단식 노천 구덩이 (깊은 단일수록 어둡다): 바닥의 굴삭기가 깔때기에 퍼 담으면 경사 컨베이어가
    가장자리 너머 흙더미 위로 올린다.
    그림은 땅 아래로 판 구덩이 (앞 가장자리 너머는 땅에 가린다), 3D 모형은 지형이 땅 아래를 덮으므로
    같은 계단을 낮은 흙 둑 안에 올려 앉힌다."""
    nlev = (4, 5, 4, 4, 4)[v]
    zr = (1.2, 1.5, 1.2, 1.0, 1.2)[v]                       # 깊이 (3D는 둑 높이)
    O = (-6.1, -4.1, 2.0, 2.9)
    far, near = (0.75, 0.6, 0.75, 0.85, 0.75)[v], (0.55, 0.45, 0.55, 0.6, 0.55)[v]
    rects = [O]
    for k in range(1, nlev):
        R = rects[-1]
        rects.append((R[0] + far, R[1] + far, R[2] - near, R[3] - near))
    zs2 = [-zr * k / (nlev - 1) + (0.04 if k == nlev - 1 else 0.0) for k in range(nlev)]
    zb3 = min(zr, 0.9)                                      # 3D 둑 높이 (뒤 비탈이 벽처럼 서지 않게 낮춘다)
    zs3 = [zb3 * (1 - k / (nlev - 1)) + (0.04 if k == nlev - 1 else 0.0) for k in range(nlev)]
    foot = (-7.0, -5.0, 4.2, 4.9)
    F = rects[-1]
    mats = (Mat("#8A8378"), Mat("#76706a"), Mat("#655f58"), Mat("#555049"), Mat("#47433e"))
    if v == 2:                                   # 얼음 섞인 층: 깊을수록 푸른 회색
        mats = (Mat("#8A8378"), Mat("#76716c"), Mat("#626a70", 0.15), Mat("#56656e", 0.25))
    hx, hy = F[2] - 0.7, (F[1] + F[3]) / 2 - 0.3          # 깔때기 (바닥 앞쪽 끝)
    lx, ly = (F[0] + 1.9, F[1] + 1.3) if v != 4 else (F[0] + 2.0, F[3] - 1.2)
    hd = (5.3, hy, (3.3, 3.5, 3.3, 3.0, 3.3)[v])           # 컨베이어 머리

    def ground3(x, y):
        """3D: 구덩이·둑 비탈을 포함한 땅 높이."""
        if O[0] <= x <= O[2] and O[1] <= y <= O[3]:
            return _pit_z(rects, zs3, x, y)
        kx = (x - O[2]) / (foot[2] - O[2]) if x > O[2] else ((O[0] - x) / (O[0] - foot[0]) if x < O[0] else 0.0)
        ky = (y - O[3]) / (foot[3] - O[3]) if y > O[3] else ((O[1] - y) / (O[1] - foot[1]) if y < O[1] else 0.0)
        return max(0.0, zb3 * (1 - max(kx, ky)))

    def ground2(x, y):
        return _pit_z(rects, zs2, x, y) if (O[0] <= x <= O[2] and O[1] <= y <= O[3]) else 0.0

    def contents(zf):
        for k in range(3):
            y = F[1] + 0.6 + k * 0.9
            sp.line((F[0] + 0.3, y, zf + 0.01), (hx - 0.8, y + 0.2, zf + 0.01), 0.07, "#3f3b37", 0.7)
        for (x, y, r) in ((F[0] + 0.5, F[3] - 0.45, 0.22), (F[0] + 0.9, F[1] + 0.3, 0.18), (hx - 1.4, F[3] - 0.3, 0.2)):
            sp.rock((x, y, zf), r, Mat("#6E675F"))
        sp.ellipsoid((F[0] + 0.25, F[1] + 0.5, zf), 0.9, 0.7, 0.45, Mat("#6f6861"), clip_z=zf)
        sp.box(hx - 0.55, hy - 0.55, zf, 1.1, 1.1, 0.5, STEEL, top=DARK)
        sp.frustum((hx, hy, zf + 0.5), (hx, hy, zf + 1.15), 0.35, 0.75, Mat("#8C939C", 0.3))
        sp.ellipsoid((hx, hy, zf + 1.05), 0.6, 0.6, 0.18, REGOLITH)
        if v == 4:
            _loader(sp, F[0] + 2.1, F[1] + 1.0, zf, ORANGE, reach=-1.0, bucket_z=zf + 0.1)
        _loader(sp, lx, ly, zf, YELLOW if v != 3 else ORANGE, reach=-1.0, bucket_z=zf + 0.15)

    sp.contact_shadow(1.8, -0.4, 4.6, 4.2, 0.25)
    # 3D 모형: 둑 안에 올려 앉힌 계단과 컨베이어
    with _Only3D(sp):
        _terraced_pit(sp, rects, zs3, foot, lambda: contents(zs3[-1]), mats, slope=mats[0])
        _conveyor(sp, (hx + 0.2, hy, zs3[-1] + 1.05), hd, 0.75, ground=ground3, legs_at=(0.3, 0.55, 0.8, 0.97))
        sp.glow(((F[0] + F[2]) / 2, (F[1] + F[3]) / 2, zs3[-1] + 0.6), 44, AMBER, 0.22)
    # 그림: 땅 아래로 판 구덩이 (앞 두 가장자리 아래를 잘라 낸다)
    with sp._nest():
        L_, B_, R_ = P(O[0], O[3], 0), P(O[2], O[3], 0), P(O[2], O[1], 0)
        clip = [L_, B_, R_, (R_[0], R_[1] - 400), (L_[0], L_[1] - 400)]
        tail2 = (hx + 0.2, hy, zs2[-1] + 1.05)
        legs_in = tuple(t for t in (0.3, 0.55, 0.8, 0.97) if tail2[0] + (hd[0] - tail2[0]) * t < O[2] - 0.3)
        legs_out = tuple(t for t in (0.3, 0.55, 0.8, 0.97) if t not in legs_in)
        with _Clip2D(sp, clip):
            _terraced_pit(sp, rects, zs2, None, lambda: contents(zs2[-1]), mats)
            _conveyor(sp, tail2, hd, 0.75, ground=ground2, legs_at=legs_in, belt=False)
            sp.glow(((F[0] + F[2]) / 2, (F[1] + F[3]) / 2, zs2[-1] + 0.6), 44, AMBER, 0.22)
        sp.polyline3([(O[0], O[3], 0.0), (O[2], O[3], 0.0), (O[2], O[1], 0.0)], "#a39886", 0.08, 0.8)
        _conveyor(sp, tail2, hd, 0.75, ground=ground2, legs_at=legs_out)
    for (x, y, r) in ((-6.0, 4.3, 0.3), (-2.4, 4.4, 0.24), (3.4, -4.5, 0.3), (1.2, 4.5, 0.22), (3.8, 3.9, 0.2)):
        sp.rock((x, y, 0.0), r)
    # 흙더미 (원뿔), 굴러 떨어지는 돌, 고른 흙 더미
    px, py = hd[0] + 0.2, hy - 0.1
    hh = hd[2] - 0.5
    sp.ellipsoid((px - 0.9, py - 0.7, 0), 0.9, 0.8, 0.6, REGOLITH, clip_z=0.0)
    sp.frustum((px, py, 0), (px, py, hh), 1.5, 0.4, REGOLITH, caps=False, edge=False)
    sp.ellipsoid((px, py, hh - 0.1), 0.48, 0.48, 0.25, REGOLITH, clip_z=hh - 0.1)
    sp.ellipsoid((px + 0.5, py + 0.9, 0), 0.75, 0.7, 0.5, REGOLITH, clip_z=0.0)
    for (x, y, r) in ((px - 1.3, py + 1.0, 0.2), (px + 1.0, py + 1.5, 0.16), (px - 0.5, py + 1.6, 0.18)):
        sp.rock((x, y, 0), r, Mat("#77706A"))
    for k in range(3):
        sp.rock((hd[0] + 0.3 + 0.05 * k, hy + 0.05 * k, hd[2] - 0.4 - 0.42 * k), 0.12)
    sp.frustum((5.6, 3.5, 0), (5.6, 3.5, (1.1, 1.1, 1.1, 0.8, 1.1)[v]), 1.1, 0.3, Mat("#B2AA9A"), caps=False, edge=False)
    sp.ellipsoid((5.6, 3.5, (1.1, 1.1, 1.1, 0.8, 1.1)[v] - 0.05), 0.34, 0.34, 0.16, Mat("#B2AA9A"),
                 clip_z=(1.1, 1.1, 1.1, 0.8, 1.1)[v] - 0.05)
    if v in (1, 3):
        sp.box(4.5, -4.7, 0, 2.1, 1.3, 1.3, WHITE, top=SILVER)
        bf = Sprite.box_faces(4.5, -4.7, 0, 2.1, 1.3, 1.3)
        band_on(sp, bf["left"], 0.8, 0.92, ORANGE)
        sp.window(sp.on_face(*bf["left"], 0.15, 0.4, 0.6, 0.72))
        door(sp, bf["right"], 0.3, 0.7, 0.75, Mat("#5c626b", 0.3))
    for (x, y) in ((-6.7, 4.7), (6.7, 4.7), (3.9, -4.8)) if v != 1 else ((-6.7, 4.7), (6.7, 4.7)):
        _mast(sp, x, y, (3.4, 3.6, 3.4, 3.2, 3.6)[v], AMBER, 16)


# ═════════════════════════════════════════════════════════════════════
# 용융 전해·정련 (mre_plant 계열)
# ═════════════════════════════════════════════════════════════════════

def _stack(sp: Sprite, x, y, z0, h, r, band=RED):
    """높은 배기 굴뚝: 회색 몸통, 위의 붉은·흰 띠, 꼭대기 붉은 등."""
    sp.cyl((x, y, z0), (x, y, z0 + 0.6), r + 0.25, CONCRETE, cap_mat=Mat("#b3a690"))
    sp.cyl((x, y, z0 + 0.6), (x, y, z0 + h), r, Mat("#8C939C", 0.3), bands=[0.25, 0.5, 0.7], cap_mat=CHAR)
    cyl_ring(sp, (x, y, z0 + 0.6), (x, y, z0 + h), r, 0.8, 0.86, band)
    cyl_ring(sp, (x, y, z0 + 0.6), (x, y, z0 + h), r, 0.9, 0.96, band)
    sp.ring3((x, y, z0 + h * 0.62), r + 0.25, "#9aa1aa", 0.06)
    sp.lamp((x, y, z0 + h + 0.15), RED_LIGHT, 6)


@typed("ore_refinery", 14, 10, 10.0, "광석 정련소", heights=[10.0, 10.6, 9.6, 10.0, 10.2])
def ore_refinery(sp: Sprite, v: int):
    """단열 용융로 덩어리 (앞면에 빛나는 출탕 틈), 높은 굴뚝, 경사 컨베이어로 채우는 광석 깔때기,
    빛나는 주괴가 식어 가는 주조 줄과 주괴 마당, 뒤쪽 방열판."""
    zb = 0.3
    band = (ORANGE, ORANGE, YELLOW, ORANGE, RED)[v]
    sp.contact_shadow(0, 0, 6.8, 4.8, 0.5)
    sp.box(-6.8, -4.8, 0, 13.6, 9.6, zb, SINTER, top=Mat("#A89A84"))
    if v == 4:                               # 뒤 구석의 식어 가는 슬래그 더미
        sp.ellipsoid((-6.0, -4.0, zb), 0.9, 0.7, 0.5, Mat("#7a4a32", 0.3), clip_z=zb)
        sp.glow((-6.0, -4.0, 0.6), 14, "#ff6a2a", 0.45)
    # 뒤: 굴뚝, 방열판, 산소 탱크
    sx, sy = (-4.8, -3.4) if v != 2 else (-1.0, -3.9)
    sh = (9.7, 10.3, 9.3, 9.7, 9.9)[v]
    _stack(sp, sx, sy, zb, sh, 0.5, RED)
    nrad = (3, 2, 3, 0, 3)[v]
    for i in range(nrad):
        x = 2.6 + i * 1.4
        o, e1, e2 = (x, -4.4, zb + 0.4), (0.0, 3.0, 0.0), (0.0, 0.0, 3.4)
        sp.line((x, -4.4, zb), (x, -1.4, zb), 0.16, "#7d848d")
        _radiator(sp, o, e1, e2, 5)
    if nrad:
        pipe(sp, [(1.9, -2.9, 2.6), (2.6 + (nrad - 1) * 1.4, -2.9, 2.6)], 0.16)
    # 용융로 (단열 덩어리) + 앞면의 출탕 틈
    fx0, fx1, fy0, fy1 = -3.2, 1.8, -3.6, 0.4
    fh = (4.4, 4.4, 4.0, 4.4, 4.6)[v]
    sp.box(fx0, fy0, zb, fx1 - fx0, fy1 - fy0, fh, FURNACE, top=Mat("#7A6A5C", 0.15))
    ff = _box_sides(fx0, fy0, zb, fx1 - fx0, fy1 - fy0, fh)
    for fr in ff.values():
        for vv in (0.55, 0.78):
            band_on(sp, fr, vv, vv + 0.05, Mat("#5a4c42", 0.15))
        band_on(sp, fr, 0.9, 0.97, band)
    cells = (1, 2, 1, 1, 2)[v]
    o, e1, e2 = ff["+y"]
    for c in range(cells):
        u0 = 0.08 + c * (0.86 / cells)
        u1 = u0 + 0.86 / cells - 0.06
        _decal(sp, ff["+y"], u0 - 0.01, 0.2, u1 + 0.01, 0.34, Mat("#2a2f36"), 0.01)
        sp.window(sp.on_face(o, e1, e2, u0, 0.235, u1, 0.305), HOT, frame=None, glass=Mat("#ff7b2e", 0.3),
                  light_alpha=0.95)
        sp.glow(add(_face_pt(ff["+y"], (u0 + u1) / 2, 0.27), (0, 0.5, 0)), 22, HOT, 0.55)
    sp.window(sp.on_face(*ff["+x"], 0.64, 0.235, 0.92, 0.305), HOT, frame=None, glass=Mat("#ff7b2e", 0.3))
    # 지붕 후드와 굴뚝으로 가는 배기관
    zt = zb + fh
    hx, hy = (fx0 + fx1) / 2 + 0.6, (fy0 + fy1) / 2
    sp.box(fx0 + 0.6, fy0 + 0.5, zt, 2.4, 2.0, 0.35, STEEL, top=DARK)
    sp.frustum((hx - 0.6, hy - 0.1, zt + 0.35), (hx - 0.6, hy - 0.1, zt + 1.2), 0.9, 0.42, STEEL)
    pipe(sp, [(hx - 0.6, hy - 0.1, zt + 1.15), (hx - 0.6, sy, zt + 1.15), (sx + 0.5, sy, zt + 1.15)], 0.42, "#9aa1aa")
    # 제어실 (+x 면에 붙은 흰 상자)
    sp.box(fx1, -3.0, zb, 1.3, 2.0, 2.6, WHITE, top=SILVER)
    cf = _box_sides(fx1, -3.0, zb, 1.3, 2.0, 2.6)
    band_on(sp, cf["+x"], 0.84, 0.94, band)
    windows_row(sp, cf["+x"], 2, 0.45, 0.72, 0.12, 0.1)
    windows_row(sp, cf["+y"], 1, 0.45, 0.72, 0.25)
    # 광석 깔때기 (-x 쪽 다리 위)와 용융로로 들어가는 미끄럼관
    ox, oy = -5.2, -0.6
    oz0, oz1 = 2.5, 4.1
    legs(sp, [(ox - 0.8, oy - 0.8, oz0 + 0.2), (ox + 0.8, oy - 0.8, oz0 + 0.2), (ox - 0.8, oy + 0.8, oz0 + 0.2),
              (ox + 0.8, oy + 0.8, oz0 + 0.2)], zb, 0.14)
    sp.frustum((ox, oy, oz0), (ox, oy, oz1), 0.35, 1.2, Mat("#8C939C", 0.3))
    sp.ring3((ox, oy, oz1), 1.2, "#5c626b", 0.08)
    sp.ellipsoid((ox, oy, oz1 - 0.05), 1.0, 1.0, 0.3, Mat("#6b5d50"))
    pipe(sp, [(ox + 0.3, oy, oz0 + 0.1), (fx0 + 0.05, oy, oz0 - 0.6)], 0.3, "#8a9099")
    # 광석 받는 통과 경사 컨베이어 (앞에서 깔때기 위로)
    bx, by = -5.2, 3.6
    sp.box(bx - 0.9, by - 0.7, zb, 1.8, 1.4, 0.8, Mat("#5c626b", 0.3), top=DARK)
    sp.ellipsoid((bx, by, zb + 0.8), 0.75, 0.55, 0.32, Mat("#6b5d50"))
    _conveyor(sp, (bx, by - 0.3, zb + 1.0), (ox, oy + 0.6, oz1 + 0.35), 0.7,
              ground=lambda x, y: zb, legs_at=(0.4, 0.75))
    # 주조 줄: 출탕구에서 흐르는 쇳물 → 거푸집 (앞쪽은 빛나고 끝은 식었다)
    cy0 = 1.1
    sp.box(-2.6, cy0, zb, 8.2, 1.0, 0.55, DARK, top=Mat("#5c626b", 0.3))
    sp.face(_orient([(-1.6, fy1, zb + 1.3), (-1.2, fy1, zb + 1.3), (-1.2, cy0 + 0.5, zb + 0.75),
                     (-1.6, cy0 + 0.5, zb + 0.75)], (0, 0.3, 1)), Mat("#ff9a4a", 0.5), ao=0, edge=False)
    sp.mark_light(HOT)
    sp.glow((-1.4, cy0 + 0.1, zb + 1.0), 12, HOT, 0.7)
    nm = (7, 7, 6, 7, 7)[v]
    hot = (2, 3, 2, 2, 3)[v]
    for i in range(nm):
        x = -2.3 + i * 1.12
        hotm = i < hot
        zi = zb + 0.77
        sp.box(x, cy0 + 0.15, zb + 0.55, 0.85, 0.7, 0.22, HOT_INGOT if hotm else INGOT,
               top=Mat("#FFD08A", 0.6) if hotm else INGOT)
        if hotm:
            sp.light_poly([(x, cy0 + 0.15, zi + 0.01), (x + 0.85, cy0 + 0.15, zi + 0.01),
                           (x + 0.85, cy0 + 0.85, zi + 0.01), (x, cy0 + 0.85, zi + 0.01)], HOT, 0.75)
            sp.glow((x + 0.42, cy0 + 0.5, zb + 0.85), 9, HOT, 0.6)
    # 주괴 마당: 쌓은 판과 주괴 더미
    stacks = ((3.2, 3.0, 3), (4.9, 3.0, 2), (3.2, 4.0, 2), (4.9, 4.0, 4)) if v != 3 else ((3.6, 3.4, 3), (5.2, 3.4, 2))
    for (x, y, k) in stacks:
        sp.box(x - 0.1, y - 0.05, zb, 1.5, 0.9, 0.12, Mat("#8a6a50"))
        for j in range(k):
            sp.box(x + 0.02 * (j % 2), y + 0.05, zb + 0.12 + j * 0.24, 1.3, 0.7, 0.22, INGOT)
    # 산소 탱크 (전해 계열의 표시)
    if v in (0, 2, 4):
        sp.sphere((5.7, 0.0, 1.25), 0.9, WHITE)
        sp.ring3((5.7, 0.0, 1.25), 0.9, "#3FB8AF", 0.12)
        legs(sp, [(5.2, -0.5, 0.7), (6.2, -0.5, 0.7), (5.7, 0.55, 0.7)], zb)
    if v == 3:
        _radiator(sp, (fx0 + 0.4, fy0 + 0.3, zt + 0.5), (fx1 - fx0 - 0.8, 0, 0), (0, 0, 1.3), 6)
        legs(sp, [(fx0 + 0.6, fy0 + 0.3, zt + 0.5), (fx1 - 0.6, fy0 + 0.3, zt + 0.5)], zt)
        sp.sphere((4.6, -2.6, 1.15), 0.85, WHITE)
        sp.ring3((4.6, -2.6, 1.15), 0.85, "#3FB8AF", 0.12)
        sp.sphere((5.9, -1.0, 1.15), 0.85, WHITE)
        sp.ring3((5.9, -1.0, 1.15), 0.85, "#3FB8AF", 0.12)
    sp.lamp((6.5, 4.5, 1.6), AMBER, 9)
    sp.lamp((fx1 + 1.4, -1.0, 2.6), AMBER, 8)


# ═════════════════════════════════════════════════════════════════════
# 부품 공장 (parts_fab 계열)
# ═════════════════════════════════════════════════════════════════════

def _sawtooth(sp: Sprite, x0, x1, y0, y1, z, rise, n, slope: Mat = SOLAR, wall: Mat = WHITE, glow=WARM_WINDOW):
    """톱니 지붕 (용마루는 x 방향): 비탈은 태양전지, 서 있는 면(+y)은 불 켜진 채광창."""
    d = (y1 - y0) / n
    for i in range(n):
        ya, yb = y0 + i * d, y0 + (i + 1) * d
        sp.face(_orient([(x0, ya, z), (x1, ya, z), (x1, yb, z + rise), (x0, yb, z + rise)], (0, -0.5, 1)), slope, ao=0)
        sp.panel_grid((x0, ya, z), (x1 - x0, 0, 0), (0, d, rise), max(2, int((x1 - x0) / 1.2)), 2, "#6f86b0", 0.45, 0.5)
        fr = ((x1, yb, z), (x0 - x1, 0.0, 0.0), (0.0, 0.0, rise))
        sp.face(_orient(sp.on_face(*fr, 0, 0, 1, 1), (0, 1, 0)), wall, ao=0)
        sp.window(sp.on_face(*fr, 0.03, 0.15, 0.97, 0.85), glow, frame="#5c626b", light_alpha=0.7)
        sp.face(_orient([(x1, ya, z), (x1, yb, z), (x1, yb, z + rise)], (1, 0, 0)), wall, ao=0)
        sp.face(_orient([(x0, ya, z), (x0, yb, z), (x0, yb, z + rise)], (-1, 0, 0)), wall, ao=0)


def _barrel_roof(sp: Sprite, x0, x1, y0, y1, z, rise, mat: Mat, n=8, skylight=None):
    """x 방향으로 누운 낮은 원호 지붕 (띠 n장) + 양 끝 박공. skylight=(k0, k1) 띠는 유리."""
    def prof(t):
        return (y0 + (y1 - y0) * t, z + rise * (1 - (2 * t - 1) ** 2))
    for i in range(n):
        (ya, za), (yb, zb_) = prof(i / n), prof((i + 1) / n)
        pts = _orient([(x0, ya, za), (x1, ya, za), (x1, yb, zb_), (x0, yb, zb_)], (0, (ya + yb) / 2 - (y0 + y1) / 2, 1))
        if skylight and skylight[0] <= i < skylight[1]:
            sp.window(pts, WARM_WINDOW, frame="#9aa1aa", light_alpha=0.6)
        else:
            sp.face(pts, mat, ao=0)
    for x, nx in ((x0, -1), (x1, 1)):
        gable = [(x, prof(i / 16)[0], prof(i / 16)[1]) for i in range(17)]
        sp.face(_orient(gable, (nx, 0, 0)), mat, ao=0)


def _gantry_legs(sp: Sprite, xc, y, z0, z1, col: Mat, top: Mat, half=0.9):
    """문형 크레인의 한쪽 다리 틀: 바퀴 차, 두 기둥, 가로보, 버팀."""
    sp.box(xc - half - 0.45, y - 0.35, z0, 2 * half + 0.9, 0.7, 0.45, DARK, top=Mat("#5c626b", 0.3))
    for x in (xc - half - 0.2, xc + half - 0.2):
        sp.disc((x + 0.2, y + 0.37, z0 + 0.22), (0, 1, 0), 0.18, STEEL)
    for x in (xc - half, xc + half):
        sp.box(x - 0.2, y - 0.2, z0 + 0.45, 0.4, 0.4, z1 - z0 - 0.45, col, top=top)
    sp.box(xc - half - 0.25, y - 0.25, z1 - 0.5, 2 * half + 0.5, 0.5, 0.5, col, top=top)
    sp.line((xc - half, y, z0 + 1.0), (xc + half, y, z1 - 1.2), 0.1, hexc(scale(col.albedo, 0.75)))


@typed("assembly_plant", 16, 12, 9.0, "조립 공장", heights=[8.6, 8.6, 8.8, 8.6, 8.6])
def assembly_plant(sp: Sprite, v: int):
    """큰 끝문이 열린 높은 조립동과, 그 앞 바깥 마당을 덮는 문형(갠트리) 크레인 — 큰 부품과 상자가 놓여 있다."""
    zb = 0.15
    x0, x1, y0, y1 = -7.6, 0.4, -5.5, 1.6
    hw = (6.2, 6.0, 6.6, 6.2, 5.8)[v]           # 벽 높이
    band = (ORANGE, ORANGE, ORANGE, TEAL, YELLOW)[v]
    ccol, ctop = ((CRANE, CRANE_TOP), (CRANE, CRANE_TOP), (ORANGE, Mat("#E9965E", 0.1)), (CRANE, CRANE_TOP),
                  (Mat("#3E6FB0", 0.2), Mat("#5c86c2", 0.2)))[v]
    xc = (2.6, 2.3, 2.8, 2.5, 2.6)[v]           # 크레인 위치: 큰 문 앞을 걸터서 (다리보는 문 위로 지난다)
    yt = (-4.0, -3.8, -4.1, -3.9, -4.0)[v]      # 수레 위치 (문 옆에 짐을 내린다)
    zg = 7.2                                    # 다리보 밑
    sp.contact_shadow(-0.2, -0.2, 7.8, 5.8, 0.45)
    sp.box(-7.9, -5.9, 0, 15.8, 11.8, zb, CONCRETE, top=Mat("#b3a690"))
    # 크레인 레일
    for ry in (-5.35, 5.35):
        sp.box(1.0, ry - 0.2, zb, 6.8, 0.4, 0.12, STEEL, top=Mat("#9aa1aa", 0.4))
    sp.face([(1.4, -4.6, zb + 0.01), (7.6, -4.6, zb + 0.01), (7.6, 4.6, zb + 0.01), (1.4, 4.6, zb + 0.01)],
            Mat("#9b927f"), normal=(0, 0, 1), ao=0, edge=False)
    sp.stripes((1.4, 4.6, zb + 0.02), (6.2, 0, 0), (0, -0.25, 0), n=14, normal=(0, 0, 1))
    _gantry_legs(sp, xc, -5.35, zb + 0.12, zg, ccol, ctop)
    # 조립동
    sp.box(x0, y0, zb, x1 - x0, y1 - y0, hw, HALL, top=SILVER)
    hf = _box_sides(x0, y0, zb, x1 - x0, y1 - y0, hw)
    for nm, fr in hf.items():
        band_on(sp, fr, 0.0, 0.06, Mat("#7d848d", 0.2))
        band_on(sp, fr, 0.86, 0.93, band)
        if nm in ("+y", "-y"):
            sp.panel_grid(*fr, 14, 1, "#c9c3b6", 0.45, 0.8)
            windows_row(sp, fr, 6, 0.64, 0.8, 0.05, 0.04)
    door(sp, hf["+y"], 0.86, 0.94, 2.2 / hw, Mat("#5c626b", 0.3))
    windows_row(sp, hf["-x"], 3, 0.64, 0.8, 0.1, 0.08)
    # 큰 끝문 (+x): 어두운 안, 불빛, 조립 중인 것의 그림자, 경고 줄
    o, e1, e2 = hf["+x"]
    du0, du1, dv1 = 0.3, 0.86, 4.8 / hw
    dp = sp.on_face(o, e1, e2, du0, 0.0, du1, dv1)
    sp.face([add(p, (0.01, 0, 0)) for p in dp], CHAR, normal=(1, 0, 0), ao=0)
    sp.light_poly([add(p, (0.02, 0, 0)) for p in dp], "#ffcf8a", 0.5)
    for (u0_, v0_, u1_, v1_) in ((0.2, 0.0, 0.42, 0.42), (0.5, 0.0, 0.76, 0.3), (0.58, 0.3, 0.68, 0.62)):
        _decal(sp, hf["+x"], du0 + (du1 - du0) * u0_, dv1 * v0_, du0 + (du1 - du0) * u1_, dv1 * v1_, Mat("#3a3f47"), 0.02)
    sp.stripes(add(_face_pt(hf["+x"], du0, dv1), (0.03, 0, 0)), mul(e1, du1 - du0), (0, 0, 0.35), n=14, normal=(1, 0, 0))
    for u in (du0 - 0.03, du1):
        _decal(sp, hf["+x"], u, 0.0, u + 0.03, dv1 + 0.06, Mat("#5c626b", 0.3), 0.03)
    sp.lamp(add(_face_pt(hf["+x"], (du0 + du1) / 2, dv1 + 0.08), (0.15, 0, 0.1)), AMBER, 10)
    # 지붕
    zt = zb + hw
    if v == 0:
        _sawtooth(sp, x0, x1, y0, y1, zt, 1.0, 4, SOLAR)
    elif v == 3:
        sp.box(x0 + 0.3, y0 + 0.3, zt, x1 - x0 - 0.6, y1 - y0 - 0.6, 0.3, Mat("#C9CCD1", 0.3), top=Mat("#B9C0C8", 0.3))
        for i in range(3):
            sp.window([(x0 + 0.9 + i * 2.5, y1 - 2.4, zt + 0.31), (x0 + 2.4 + i * 2.5, y1 - 2.4, zt + 0.31),
                       (x0 + 2.4 + i * 2.5, y1 - 1.2, zt + 0.31), (x0 + 0.9 + i * 2.5, y1 - 1.2, zt + 0.31)],
                      WARM_WINDOW, frame="#9aa1aa", light_alpha=0.6)
    elif v in (1, 4):
        _barrel_roof(sp, x0 - 0.1, x1 + 0.1, y0 - 0.15, y1 + 0.15, zt, (1.9, 1.9, 0, 0, 2.2)[v], Mat("#C9CCD1", 0.35),
                     8, skylight=(3, 5))
    else:
        ym = (y0 + y1) / 2
        roof = Mat("#8a5a4a", 0.2)
        sp.face(_orient([(x0 - 0.2, y0 - 0.2, zt), (x1 + 0.2, y0 - 0.2, zt), (x1 + 0.2, ym, zt + 1.8), (x0 - 0.2, ym, zt + 1.8)],
                        (0, -1, 1)), roof)
        sp.face(_orient([(x0 - 0.2, ym, zt + 1.8), (x1 + 0.2, ym, zt + 1.8), (x1 + 0.2, y1 + 0.2, zt),
                         (x0 - 0.2, y1 + 0.2, zt)], (0, 1, 1)), roof)
        sp.face(_orient([(x1, y0, zt), (x1, y1, zt), (x1, ym, zt + 1.8)], (1, 0, 0)), HALL)
        sp.face(_orient([(x0, y0, zt), (x0, y1, zt), (x0, ym, zt + 1.8)], (-1, 0, 0)), HALL)
        sp.panel_grid((x0 - 0.2, ym, zt + 1.8), (x1 - x0 + 0.4, 0, 0), (0, y1 + 0.2 - ym, -1.8), 16, 1, "#6d4538", 0.45, 0.7)
    if v == 3:
        for i in range(2):
            xr = x0 + 0.9 + i * 3.6
            legs(sp, [(xr + 0.2, y0 + 1.0, zt + 0.55), (xr + 2.6, y0 + 1.0, zt + 0.55)], zt + 0.3)
            _radiator(sp, (xr, y0 + 1.0, zt + 0.55), (2.8, 0, 0), (0, 0, 1.2), 5)
    # 바깥 마당의 큰 부품 (뒤에서 앞 순서), 크레인에 매달린 짐
    items = []

    def tank(x=2.9, y=-3.2, L=3.6):
        for cx in (x + 0.7, x + L - 0.7):
            sp.box(cx - 0.3, y - 0.9, zb, 0.6, 1.8, 0.75, Mat("#5c626b", 0.3))
        sp.cyl((x, y, 1.45), (x + L, y, 1.45), 1.15, WHITE, bands=[0.33, 0.66], band_color="#bdb6a8", cap_mat=Mat("#C9CCD1", 0.3))
        cyl_ring(sp, (x, y, 1.45), (x + L, y, 1.45), 1.15, 0.12, 0.18, band)
    if v != 3:
        items.append(((4.7, -3.2, 0), tank))

    def crates(x=4.6, y=2.9):
        crate(sp, x, y, 1.3, ORANGE, zb)
        crate(sp, x + 1.4, y, 1.3, Mat("#C9A23A"), zb)
        crate(sp, x + 0.6, y, 1.2, ORANGE, zb + 1.04)
    items.append(((5.3, 3.5, 0), crates))

    def truss():
        for yy in (2.2, 3.4):
            sp.line((1.6, yy, zb + 0.15), (4.6, yy, zb + 0.15), 0.12, "#8a9099")
            sp.line((1.6, yy, zb + 0.95), (4.6, yy, zb + 0.95), 0.12, "#8a9099")
        for k in range(6):
            x = 1.6 + k * 0.6
            sp.line((x, 2.2, zb + 0.15), (x + 0.6, 2.2, zb + 0.95), 0.07, "#8a9099")
            sp.line((x, 3.4, zb + 0.15), (x + 0.6, 3.4, zb + 0.95), 0.07, "#8a9099")
            sp.line((x, 2.2, zb + 0.95), (x, 3.4, zb + 0.95), 0.06, "#8a9099")
    if v in (0, 2, 4):
        items.append(((3.1, 2.8, 0), truss))
    if v == 3:
        def stack():
            for i in range(3):
                for k in range(2):
                    crate(sp, 2.8 + i * 1.5, -4.4 + k * 1.5, 1.3, (ORANGE, Mat("#C9A23A"), WHITE)[(i + k) % 3], zb)
        items.append(((4.8, -3.6, 0), stack))
    zh = (3.4, 2.8, 4.0, 2.6, 3.6)[v]           # 매단 짐 높이

    def load():
        sp.line((xc - 0.2, yt, zg), (xc - 0.2, yt, zh + 1.0), 0.04, "#3a3f47")
        sp.line((xc + 0.2, yt, zg), (xc + 0.2, yt, zh + 1.0), 0.04, "#3a3f47")
        sp.box(xc - 0.3, yt - 0.25, zh + 0.8, 0.6, 0.5, 0.3, YELLOW)
        if v == 1:              # 팽창 거주 모듈 껍질
            sp.cyl((xc - 1.6, yt, zh), (xc + 1.6, yt, zh), 0.8, FABRIC, bands=[0.2, 0.4, 0.6, 0.8], band_color="#b9ab92",
                   cap_mat=WHITE)
        elif v == 3:
            crate(sp, xc - 0.7, yt - 0.7, 1.4, Mat("#C9A23A"), zh - 0.6)
        else:
            sp.box(xc - 1.2, yt - 0.8, zh - 0.5, 2.4, 1.6, 1.1, Mat("#8C939C", 0.3), top=Mat("#a9b0b8", 0.3))
            band_on(sp, Sprite.box_faces(xc - 1.2, yt - 0.8, zh - 0.5, 2.4, 1.6, 1.1)["left"], 0.7, 0.85, band)
        for k in range(2):
            sp.line((xc - 1.0 + 2.0 * k, yt, zh + 0.6), (xc, yt, zh + 0.95), 0.03, "#5c626b")
    items.append(((xc, yt, zh), load))
    sp.parts(items)
    # 다리보와 수레
    sp.box(xc - 0.45, -5.7, zg, 0.9, 11.4, 0.75, ccol, top=ctop)
    gf = Sprite.box_faces(xc - 0.45, -5.7, zg, 0.9, 11.4, 0.75)
    sp.panel_grid(*gf["right"], 16, 1, hexc(scale(ccol.albedo, 0.7)), 0.5, 0.8)
    sp.box(xc - 0.65, yt - 0.6, zg + 0.75, 1.3, 1.2, 0.55, DARK, top=Mat("#5c626b", 0.3))
    sp.box(xc - 0.62, yt - 0.62, zg - 0.45, 1.24, 1.24, 0.45, Mat("#5c626b", 0.3))
    sp.lamp((xc, 5.6, zg + 0.9), AMBER, 10)
    sp.lamp((xc, -5.6, zg + 0.9), RED_LIGHT, 6)
    _gantry_legs(sp, xc, 5.35, zb + 0.12, zg, ccol, ctop)
    sp.lamp((7.7, 5.7, 1.2), AMBER, 8)


# ═════════════════════════════════════════════════════════════════════
# 녹지·여가 (green_commons 계열)
# ═════════════════════════════════════════════════════════════════════

def _geo_edges(c, rx, ry, h, z0, nlon=16, nlat=5, twist=0.0):
    """측지 돔 격자의 모서리 (a, b, 바깥 법선): 위도 고리마다 반 칸씩 어긋난 삼각형 그물."""
    def vtx(k, i):
        if k >= nlat:
            return (c[0], c[1], z0 + h)
        ph = (math.pi / 2) * k / nlat
        th = 2 * math.pi * (i + 0.5 * k) / nlon + twist
        return (c[0] + rx * math.cos(ph) * math.cos(th), c[1] + ry * math.cos(ph) * math.sin(th), z0 + h * math.sin(ph))
    edges = []
    for k in range(nlat):
        for i in range(nlon):
            a = vtx(k, i)
            edges.append((a, vtx(k, i + 1)))
            edges.append((a, vtx(k + 1, i)))
            if k < nlat - 1:
                edges.append((vtx(k, i + 1), vtx(k + 1, i)))
    out = []
    for a, b in edges:
        m = mul(add(a, b), 0.5)
        n = norm(((m[0] - c[0]) / rx ** 2, (m[1] - c[1]) / ry ** 2, (m[2] - z0) / h ** 2))
        out.append((a, b, n))
    return out


def _palm(sp: Sprite, base, h, lean=(0.25, 0.15), leaf="#4C8B41", trunk="#8a6a50"):
    """야자: 조금 휜 줄기와 처진 잎 일곱 장."""
    top = add(base, (lean[0], lean[1], h))
    mid = add(base, (lean[0] * 0.3, lean[1] * 0.3, h * 0.55))
    sp.polyline3([base, mid, top], trunk, 0.17)
    for k in range(7):
        a = 2 * math.pi * (k + 0.3) / 7
        d = (math.cos(a), math.sin(a), 0.0)
        p1 = add(top, add(mul(d, 0.8), (0, 0, 0.3)))
        p2 = add(top, add(mul(d, 1.5), (0, 0, -0.25)))
        sp.polyline3([top, p1, p2], leaf, 0.2)
    sp.sphere(top, 0.18, Mat("#3f6f35"))


@typed("botanical_dome", 16, 14, 9.0, "식물원 돔", heights=[8.8, 8.0, 7.0, 8.8, 8.6])
def botanical_dome(sp: Sprite, v: int):
    """세모난 유리판으로 짠 큰 측지 돔 안에 야자·둥근 나무·꽃나무와 연못·길이 보인다. +x에 유리 현관."""
    cx, cy = -0.9, 0.0
    rx, ry = (6.6, 6.4, 6.75, 6.6, 6.4)[v], (6.0, 5.9, 6.3, 6.0, 5.8)[v]
    H = (7.7, 7.3, 6.4, 7.7, 7.5)[v]
    zb = 0.6
    frame = ("#e8eef3", "#f4f4f0", "#c9a66b", "#e8eef3", "#dfe9f2")[v]
    nlon, nlat = ((16, 5), (14, 5), (18, 4), (16, 5), (12, 4))[v]
    sp.contact_shadow(cx, cy, rx + 0.6, ry + 0.6, 0.45)
    # 바깥 길 (현관에서 바닥 끝까지)
    sp.face([(5.6, -0.9, 0.02), (7.95, -0.9, 0.02), (7.95, 0.9, 0.02), (5.6, 0.9, 0.02)], PAVE, normal=(0, 0, 1), ao=0,
            edge=False)
    # 받침 (낮은 소결 벽) 과 정원 바닥
    ell = [(cx + (rx + 0.25) * math.cos(2 * math.pi * k / 48), cy + (ry + 0.25) * math.sin(2 * math.pi * k / 48))
           for k in range(48)]
    sp.prism(ell, 0, zb, SINTER, top=Mat("#6f9a55"))
    edges = _geo_edges((cx, cy), rx, ry, H, zb, nlon, nlat)
    # 뒤쪽 격자 (유리 너머로 흐리게)
    for a, b, n in edges:
        if dot(n, VIEW) <= 0:
            sp.polyline3([a, b], frame, 0.05, 0.3)
    # 길과 연못
    path = "#cdbf9f"
    ring = [(cx + rx * 0.55 * math.cos(2 * math.pi * k / 40), cy + ry * 0.55 * math.sin(2 * math.pi * k / 40), zb + 0.02)
            for k in range(41)]
    sp.polyline3(ring, path, 0.5)
    sp.line((cx + rx * 0.55, cy, zb + 0.02), (cx + rx, cy, zb + 0.02), 0.6, path)
    sp.line((cx - rx * 0.55, cy, zb + 0.02), (cx + rx * 0.55, cy, zb + 0.02), 0.4, path)
    px, py, pr = ((cx - 1.2, cy - 1.0, 1.5), (cx - 1.0, cy + 0.8, 1.3), (cx - 0.6, cy - 0.4, 2.2), (cx - 1.4, cy - 1.2, 1.3),
                  (cx - 1.0, cy - 0.9, 1.6))[v]
    pond = [(px + pr * math.cos(2 * math.pi * k / 24), py + pr * 0.75 * math.sin(2 * math.pi * k / 24), zb + 0.03)
            for k in range(24)]
    sp.face(pond, POND, normal=(0, 0, 1), ao=0, edge=False)
    sp.polyline3(pond + [pond[0]], "#a39886", 0.12)
    sp.light_poly(pond, "#7FE3DA", 0.35)
    # 나무 (뒤에서 앞 순서)
    if v == 3:
        trees = [("big", cx + 0.2, cy + 0.3, 6.6, 2.4)]
        trees += [("round", cx + 3.2, cy - 2.6, 3.2, 1.0), ("pink", cx - 3.4, cy + 2.6, 3.0, 1.0),
                  ("palm", cx + 3.6, cy + 2.4, 4.2, 0), ("cone", cx - 3.8, cy - 2.0, 4.0, 0.9),
                  ("yellow", cx + 1.0, cy - 4.0, 2.6, 0.8), ("pink", cx - 0.6, cy + 4.3, 2.4, 0.8)]
    else:
        trees = [("palm", cx - 2.6, cy - 3.0, 5.4, 0), ("palm", cx + 1.8, cy - 2.6, 6.2, 0),
                 ("round", cx - 4.2, cy + 0.6, 3.6, 1.2), ("cone", cx - 1.8, cy + 3.4, 4.4, 1.0),
                 ("pink", cx + 1.2, cy + 1.6, 3.2, 1.1), ("round", cx + 3.6, cy - 0.4, 3.0, 1.0),
                 ("palm", cx - 0.2, cy + 0.2, 6.8, 0), ("yellow", cx + 2.6, cy + 3.6, 2.6, 0.9),
                 ("round", cx - 4.0, cy - 2.4, 3.2, 1.1)]
        if v == 2:
            trees = [t for t in trees if t[0] != "palm"] + [("orange", cx + 0.4, cy - 3.2, 3.0, 1.1),
                                                           ("round", cx + 0.2, cy + 0.0, 3.6, 1.3)]
        if v == 4:
            trees = trees[:6] + [("cone", cx + 0.2, cy + 0.2, 5.6, 1.2)]
    leafs = {"round": LEAF, "pink": Mat("#C77FA3"), "yellow": Mat("#C9A84E"), "orange": Mat("#C98446"),
             "cone": Mat("#3f7a3a")}
    items = []
    for (kind, x, y, h, r) in trees:
        def tr(kind=kind, x=x, y=y, h=h, r=r):
            if kind == "palm":
                _palm(sp, (x, y, zb), h, (0.3 if x < cx else -0.2, 0.2))
            elif kind == "big":
                sp.cyl((x, y, zb), (x, y, zb + h * 0.5), 0.35, COPPER, edge=False)
                for (dx, dy, dz, rr) in ((-0.9, -0.4, 0.0, 1.5), (0.9, -0.6, 0.2, 1.4), (0.0, 0.8, 0.1, 1.5), (0.0, 0.0, 1.0, 1.7)):
                    sp.sphere((x + dx, y + dy, zb + h - 1.6 + dz), rr, LEAF if dz < 0.5 else GREEN)
            else:
                sp.tree((x, y, zb), h, r, leafs[kind], kind="cone" if kind == "cone" else "round")
        items.append(((x, y, 0), tr))
    for (x, y) in ((cx + 1.8, cy + 0.9), (cx - 2.4, cy + 1.9), (cx + 2.4, cy - 1.4), (cx - 1.6, cy - 4.4)):
        items.append(((x, y, 0), lambda x=x, y=y: _shrub(sp, x, y, zb, 0.5, GREEN, 0.9)))
    items.append(((cx + 2.9, cy + 0.6, 0), lambda: sp.box(cx + 2.6, cy + 0.6, zb, 0.9, 0.35, 0.4, COPPER)))
    sp.parts(items)
    sp.glow((cx, cy, zb + 2.6), 70, GARDEN_LIGHT, 0.32)
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        sp.lamp((cx + rx * 0.62 * math.cos(a), cy + ry * 0.62 * math.sin(a), zb + 0.9), WARM_WINDOW, 6)
    # 유리 껍질 (반투명) 과 앞쪽 격자
    pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            pts.append(P(cx + rx * math.cos(ph) * math.cos(th), cy + ry * math.cos(ph) * math.sin(th), zb + H * math.sin(ph)))
    sil = hull(pts)
    hl = PV((cx - rx * 0.3, cy + ry * 0.45, zb + H * 0.78))
    fill = sp.radial([(0, "#ffffff", 0.3), (0.4, "#cfe6ff", 0.11), (1, "#9fc0e0", 0.05)], hl[0], hl[1], max(rx, ry) * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_shell((cx, cy, zb), rx, ry, H, zb)
    for a, b, n in edges:
        if dot(n, VIEW) > 0:
            sp.polyline3([a, b], frame, 0.06, 0.62)
    # 꼭대기 환기 등롱
    zt = zb + H
    if v in (0, 3, 4):
        sp.cyl((cx, cy, zt - 0.25), (cx, cy, zt + 0.45), 0.75, WHITE, cap_mat=SILVER)
        cyl_ring(sp, (cx, cy, zt - 0.25), (cx, cy, zt + 0.45), 0.75, 0.35, 0.75, GLASS, WARM_WINDOW, 0.7)
        sp.lamp((cx, cy, zt + 0.6), RED_LIGHT, 6)
    # 유리 현관 (+x): 흰 틀 상자, 유리문, 차양, 등
    vx0, vx1 = cx + rx - 0.9, 7.2
    sp.box(vx0, -1.3, 0, vx1 - vx0, 2.6, 2.7, WHITE, top=SILVER)
    vf = _box_sides(vx0, -1.3, 0, vx1 - vx0, 2.6, 2.7)
    band_on(sp, vf["+y"], 0.86, 0.95, Mat("#5E9E4E"))
    band_on(sp, vf["+x"], 0.86, 0.95, Mat("#5E9E4E"))
    sp.window(sp.on_face(*vf["+y"], 0.08, 0.15, 0.6, 0.78), GARDEN_LIGHT, frame="#d7dde3")
    sp.window(sp.on_face(*vf["+x"], 0.22, 0.0, 0.78, 0.78), "#ffe9b8", frame="#d7dde3", glass=Mat("#3a4d60", 0.6))
    sp.box(vx1 - 0.1, -1.6, 2.7, 0.6, 3.2, 0.12, SILVER)
    sp.lamp((vx1 + 0.3, 1.45, 2.3), AMBER, 9)
    sp.lamp((vx1 + 0.3, -1.45, 2.3), AMBER, 9)
    if v == 4:
        for k in range(5):
            a = math.radians(70 + k * 22)
            x, y = cx + (rx + 0.75) * math.cos(a), cy + (ry + 0.75) * math.sin(a)
            sp.box(x - 0.35, y - 0.35, 0, 0.7, 0.7, 0.4, PLANTER, top=SOIL)
            _shrub(sp, x, y, 0.4, 0.35, (LEAF, Mat("#D96FA8"))[k % 2], 1.0)
