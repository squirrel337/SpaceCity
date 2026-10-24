"""고층 건물 묶음 A (v3) — 고층 주거 타워(거주)와 연구 타워(연구) 2종.

도시가 빽빽해지면 낮은 공동 주택·연구동 자리에 들어서는 고층 건물이다.
종류마다 함수 하나 fn(sp, v)가 같은 기능의 다섯 모양(v = 0~4)을 그린다. v0이 대표 모양이다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다. 뒤(x+y가 작은 쪽)에서 앞 순서로 그린다.

층이 많아 창을 하나씩 3D에 적으면 모형이 무거워진다. 그래서 탑의 창 줄(_facade)은 3D에 면마다 유리 띠 한 장과
꺼진 창 판 몇 장, 벽색 격자(창 사이 기둥·층 사이 벽·깊은 창 둘레)만 적고, 2D 그림에는 보이는 면에만 창을 하나씩 그린다
(밤에 꺼진 창은 2D와 3D가 같다). 뒤쪽 면의 창·띠는 3D 모형에만 남는다.
"""
from __future__ import annotations

import math

import iso
from types_common import *  # noqa: F401,F403

# ── 재질 ──────────────────────────────────────────────────────────────
TAN = Mat("#A8926F")                 # 소결 레골리스 블록 (밝은 황갈색)
REVEAL = Mat("#6E604C")              # 두꺼운 벽에 깊이 들어간 창 둘레
SLAB = Mat("#C9BDA6")                # 층 바닥판
TERRACE = Mat("#A99D88")             # 기단 지붕 마당
ROOF = Mat("#8F8A83")                # 탑 옥상
PLANTER = Mat("#8a7c68")
SOIL = Mat("#5b4636")
PAVE = Mat("#B9AE98")                # 길 포장
BERM_TOP = Mat("#6e6862")
WATER_WALL = Mat("#6F93A6", 0.45)    # 물을 채운 차폐 판 (물벽)
BASALT = Mat("#7A756E", 0.1)         # 녹여 부은 현무암 블록
PANEL = Mat("#DCDDD8", 0.1)          # 흰 외장 패널 (연구 타워)
VIOLET = Mat("#9B7AD6")              # 연구 계열 띠
LAB_GLASS = Mat("#3A566C", 0.8)      # 실험실 띠창 유리
ATRIUM_GLASS = "#cfe6ff"
LIFT_CAB = Mat("#E6D9B8", 0.3)

GARDEN_LIGHT = "#d8ffb0"
RED_LIGHT = "#ff5a3c"
LAB_LIGHT = "#D8E9FA"                # 실험실 불빛 (차가운 흰빛)
VIOLET_LIGHT = "#C9A8FF"


# ── 공용 도우미 ───────────────────────────────────────────────────────

def _orient(pts, outward):
    """다각형 꼭짓점이 outward 쪽에서 반시계가 되게 한다."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return pts if dot(n, outward) >= 0 else list(reversed(pts))


def _faces4(x, y, z, w, d, h):
    """상자의 옆면 넷 (원점, 가로, 세로) — 가로 × 세로 = 바깥 법선. 2D에는 +x·+y만 보인다."""
    return {"+y": ((x + w, y + d, z), (-w, 0.0, 0.0), (0.0, 0.0, h)),
            "+x": ((x + w, y, z), (0.0, d, 0.0), (0.0, 0.0, h)),
            "-y": ((x, y, z), (w, 0.0, 0.0), (0.0, 0.0, h)),
            "-x": ((x, y + d, z), (0.0, -d, 0.0), (0.0, 0.0, h))}


def _edge_frames(base, z, h):
    """반시계 바닥 다각형을 h만큼 세운 기둥의 옆면 틀 (원점, 가로, 세로)."""
    out = []
    for i in range(len(base)):
        a, b = base[i], base[(i + 1) % len(base)]
        out.append(((a[0], a[1], z), (b[0] - a[0], b[1] - a[1], 0.0), (0.0, 0.0, h)))
    return out


def _band(frame, z0, z1):
    """틀의 높이 z0~z1 (m) 부분만 떼어 낸 틀."""
    o, e1, _ = frame
    return (add(o, (0.0, 0.0, z0)), e1, (0.0, 0.0, z1 - z0))


def _nrm(frame):
    return norm(cross(frame[1], frame[2]))


def _decal(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, lift=0.0):
    """면 위의 색 판 (띠·패널·문)."""
    n = _nrm(frame)
    pts = [add(p, mul(n, lift)) for p in sp.on_face(*frame, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    return pts


def _lit(sp: Sprite, pts, mat: Mat, glow, alpha=0.85):
    """밤에 빛나는 면 (색 띠·간판). 3D는 면이 스스로 빛나고, 2D 밤 그림에는 보이는 면만 칠한다."""
    n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    sp.mark_light(glow, alpha)
    if dot(n, VIEW) > 1e-6:
        sp.poly2([PV(p) for p in pts], glow, None, 0, alpha, layer="light")
    return pts


def _lit_decal(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, glow, alpha=0.85, lift=0.02):
    n = _nrm(frame)
    return _lit(sp, [add(p, mul(n, lift)) for p in sp.on_face(*frame, u0, v0, u1, v1)], mat, glow, alpha)


def _glass_pane(sp: Sprite, pts3, color=ATRIUM_GLASS, alpha=0.22, frame="#dfe9f2"):
    """유리판 (그림은 반투명, 3D는 유리 재질)."""
    sp._rec(("poly", list(pts3), iso._Glass(color, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if dot(n, VIEW) <= 0:
        n = mul(n, -1)
    sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(color), n, 0.6)), frame, 0.5, alpha + 0.12)


def _box_pts(x0, y0, z0, x1, y1, z1):
    return [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def _screen_hull(pts3):
    return hull([PV(p) for p in pts3])


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


def _joints(sp: Sprite, frame, n1, n2, color, w=0.06, opacity=0.8):
    """면 위의 줄눈 격자 (블록·물벽 판). 3D는 늘, 2D는 보이는 면에만."""
    o, e1, e2 = frame
    if dot(_nrm(frame), VIEW) > 1e-6:
        sp.panel_grid(o, e1, e2, n1, n2, color, w * S, opacity)
    else:
        sp._rec(("grid", o, e1, e2, n1, n2, color, w))


def _facade(sp: Sprite, frame, nf, fh, cols, wall: Mat, sill=0.75, head=2.05, pier=0.5, margin=0.4,
            reveal: Mat | None = REVEAL, rm=0.1, glow=WARM_WINDOW, glass: Mat = GLASS, frame_col="#2a2f36",
            seed=0, dark=0.25, lit=0.95, dim=0.1, banded=True, hide=None, spandrel: Mat | None = None):
    """면 하나의 창 줄: nf층 × cols칸 (층 높이 fh, 창은 층 바닥에서 sill~head m, 칸 사이 기둥 pier m).
    banded면 3D에는 유리 띠 한 장 + 꺼진 창 판 + 벽색 격자(기둥·층 사이 벽, reveal이면 깊은 창 둘레까지)만 적는다
    (겹 순서: 둘레 판 → 유리 띠 → 꺼진 창 → 둘레색 격자 → 벽색 격자, 면에서 조금씩 띄운다)
    — 창이 몇 개든 도형 여남은 개. banded가 아니면 창을 하나씩 적는다 (창이 적은 기단).
    2D는 보이는 면에만 창을 하나씩 그린다. hide(화면 볼록 껍질)에 든 창은 2D 밤 불빛을 뺀다 (앞 덩어리에 가려진 창).
    spandrel을 주면 층 사이 벽을 그 색 띠로 칠한다."""
    o, e1, e2 = frame
    L = length(e1)
    ue, up = norm(e1), norm(e2)
    n = norm(cross(e1, e2))
    cw = (L - 2 * margin) / cols
    gap = fh - (head - sill)
    r = rm if reveal is not None else 0.0

    def pt(u, z, lift=0.0):
        return add(add(add(o, mul(ue, u)), mul(up, z)), mul(n, lift))

    def rect(u0, z0, u1, z1, lift=0.0):
        return [pt(u0, z0, lift), pt(u1, z0, lift), pt(u1, z1, lift), pt(u0, z1, lift)]

    def on(k, i):
        """밤에 몇 집은 불이 꺼져 있다."""
        return (k * 41 + i * 67 + seed * 29 + (k * i * 13) % 11) % 100 >= dark * 100

    def win_uv(k, i, j):
        return margin + i * cw + pier / 2, k * fh + sill, margin + (j + 1) * cw - pier / 2, k * fh + head

    # 3D
    if banded:
        ua, ub = margin + pier / 2, L - margin - pier / 2
        za, zb = sill, (nf - 1) * fh + head
        if reveal is not None:
            sp._rec(("poly", rect(ua - r, za - r * 1.4, ub + r, zb + r * 0.6, 0.016), reveal, None))
        sp._rec(("win", rect(ua, za, ub, zb, 0.024), glow, glass, lit))
        for k in range(nf):                              # 꺼진 창: 이웃한 것끼리 한 판 (사이 기둥은 격자가 덮는다)
            i = 0
            while i < cols:
                if on(k, i):
                    i += 1
                    continue
                j = i
                while j + 1 < cols and not on(k, j + 1):
                    j += 1
                u0, z0, u1, z1 = win_uv(k, i, j)
                sp._rec(("win", rect(u0, z0, u1, z1, 0.032), glow, glass, dim))
                i = j + 1
        if reveal is not None:
            rc = hexc(reveal.albedo)
            if cols > 1:
                sp._rec(("grid", pt(margin, za, 0.04), mul(ue, cols * cw), mul(up, zb - za), cols, 1, rc, pier))
            if nf > 1:
                sp._rec(("grid", pt(ua, sill - gap / 2, 0.04), mul(ue, ub - ua), mul(up, nf * fh), 1, nf, rc, gap))
        if cols > 1:
            sp._rec(("grid", pt(margin, za - r * 1.4, 0.06), mul(ue, cols * cw), mul(up, zb - za + r * 2.0), cols, 1,
                     hexc(wall.albedo), pier - 2 * r))
        if nf > 1:
            sp._rec(("grid", pt(0.0, sill - gap / 2 - r * 0.4, 0.07), mul(ue, L), mul(up, nf * fh), 1, nf,
                     hexc((spandrel or wall).albedo), gap - 2 * r))
    else:
        for k in range(nf):
            for i in range(cols):
                u0, z0, u1, z1 = win_uv(k, i, i)
                if reveal is not None:
                    sp._rec(("poly", rect(u0 - r, z0 - r * 1.4, u1 + r, z1 + r * 0.6, 0.016), reveal, None))
                sp._rec(("win", rect(u0, z0, u1, z1, 0.024), glow, glass, lit if on(k, i) else dim))
    # 2D (보이는 면만)
    if dot(n, VIEW) <= 1e-6:
        return
    with sp._nest():
        if spandrel is not None and banded:
            for k in range(1, nf):
                zc = k * fh + sill - gap / 2 - r * 0.4
                sp.face(rect(0.0, zc - (gap - 2 * r) / 2, L, zc + (gap - 2 * r) / 2), spandrel, normal=n, edge=False,
                        ao=0)
        for k in range(nf):
            for i in range(cols):
                u0, z0, u1, z1 = win_uv(k, i, i)
                if reveal is not None:
                    sp.face(rect(u0 - r, z0 - r * 1.4, u1 + r, z1 + r * 0.6), reveal, normal=n, edge=False, ao=0)
                q = rect(u0, z0, u1, z1)
                a = lit if on(k, i) else dim
                if hide is not None and _covered(hide, q):
                    a = 0.0
                sp.window(q, glow, frame=frame_col, glass=glass, light_alpha=a)


def _slab_ring(sp: Sprite, x0, y0, x1, y1, z, t=0.18, out=0.12, mat: Mat = SLAB):
    """층 바닥판이 벽 밖으로 조금 내민 띠. 3D는 상자 하나 (속은 탑 안에 묻힌다),
    2D는 앞 두 옆면과 윗면의 앞 띠만 그린다 (윗면 전체를 칠하면 위층 벽을 덮는다)."""
    X0, Y0, X1, Y1, zt = x0 - out, y0 - out, x1 + out, y1 + out, z + t
    sp._rec(("box", X0, Y0, z, X1 - X0, Y1 - Y0, t, mat, mat))
    with sp._nest():
        sp.face([(X0, y1, zt), (X1, y1, zt), (X1, Y1, zt), (X0, Y1, zt)], mat, normal=(0, 0, 1), edge=False, ao=0)
        sp.face([(x1, Y0, zt), (X1, Y0, zt), (X1, y1, zt), (x1, y1, zt)], mat, normal=(0, 0, 1), edge=False, ao=0)
        sp.face([(X0, Y1, z), (X1, Y1, z), (X1, Y1, zt), (X0, Y1, zt)], mat, normal=(0, 1, 0), ao=0)
        sp.face([(X1, Y0, z), (X1, Y0, zt), (X1, Y1, zt), (X1, Y1, z)], mat, normal=(1, 0, 0), ao=0)


def _shaft(sp: Sprite, x0, y0, x1, y1, z0, nf, fh, wall: Mat, top: Mat = ROOF, cell=1.05, seed=0, slabs=True,
           hide=None, **kw):
    """창 줄이 있는 탑 몸통 (상자): 몸통 → 네 면의 창 줄 → 층마다 내민 바닥판. 면 틀을 돌려준다."""
    H = nf * fh
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, H, wall, top=top)
    f = _faces4(x0, y0, z0, x1 - x0, y1 - y0, H)
    for key, fr in f.items():
        L = length(fr[1])
        cols = max(2, int(round((L - 0.8) / cell)))
        _facade(sp, fr, nf, fh, cols, wall, seed=seed + len(key) * 7 + (key[0] == "+") * 3,
                hide=(hide or {}).get(key), **kw)
    if slabs:
        for k in range(1, nf):
            _slab_ring(sp, x0, y0, x1, y1, z0 + k * fh - 0.09)
    return f


def _winter_garden(sp: Sprite, xa, xb, y, dp, z0, z1, leaf: Mat = LEAF, glow=GARDEN_LIGHT, frame_col="#d9d4ca"):
    """+y 벽에 내단 한 층짜리 유리 겨울 정원: 바닥판 → 먼 옆 유리 → 화단과 생울타리 → 앞·옆 유리 → 창살 → 지붕판."""
    yf = y + dp
    sp.box(xa - 0.06, y, z0 - 0.16, xb - xa + 0.12, dp + 0.06, 0.16, SLAB)
    _glass_pane(sp, [(xa, y, z0), (xa, yf, z0), (xa, yf, z1), (xa, y, z1)], alpha=0.12)
    sp.box(xa + 0.15, y + 0.08, z0, xb - xa - 0.3, 0.42, 0.3, PLANTER, top=SOIL)
    sp.ellipsoid(((xa + xb) / 2, y + 0.3, z0 + 0.3), (xb - xa) / 2 - 0.22, 0.3, 0.62, leaf, clip_z=z0 + 0.3)
    front = [(xb, yf, z0), (xa, yf, z0), (xa, yf, z1), (xb, yf, z1)]
    side = [(xb, y, z0), (xb, yf, z0), (xb, yf, z1), (xb, y, z1)]
    _glass_pane(sp, front, alpha=0.16)
    _glass_pane(sp, side, alpha=0.16)
    sp.light_poly(_orient(front, (0, 1, 0)), glow, 0.4)
    sp.light_poly(_orient(side, (1, 0, 0)), glow, 0.28)
    sp.line(((xa + xb) / 2, yf, z0), ((xa + xb) / 2, yf, z1), 0.05, frame_col)
    sp.line((xb, yf, z0), (xb, yf, z1), 0.07, frame_col)
    sp.box(xa - 0.08, y, z1, xb - xa + 0.16, dp + 0.08, 0.1, WHITE, top=SILVER)


def _rail(sp: Sprite, pts, z, h=0.9, alpha=0.14):
    """유리 난간 (꺾인 줄 pts 위): 유리판 → 손잡이."""
    for a, b in zip(pts, pts[1:]):
        _glass_pane(sp, [(a[0], a[1], z), (b[0], b[1], z), (b[0], b[1], z + h), (a[0], a[1], z + h)], alpha=alpha)
    sp.polyline3([(p[0], p[1], z + h + 0.03) for p in pts], "#c9ccd1", 0.06)


def _radiator(sp: Sprite, o, e1, e2, n=5):
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, n, 1, "#b7bcc2", 0.5, 0.8)


def _shrub(sp: Sprite, x, y, z, r, mat: Mat = LEAF, k=0.9):
    sp.ellipsoid((x, y, z), r, r, r * k, mat, clip_z=z)


def _planter_row(sp: Sprite, xa, xb, y, z, d=0.6, leaf=(LEAF, GREEN), along="x"):
    """화분 줄 (along 방향): 화분 상자 → 관목."""
    L = xb - xa
    if along == "x":
        sp.box(xa, y - d / 2, z, L, d, 0.35, PLANTER, top=SOIL)
    else:
        sp.box(y - d / 2, xa, z, d, L, 0.35, PLANTER, top=SOIL)
    m = max(2, int(L / 0.7))
    for i in range(m):
        t = xa + L * (i + 0.5) / m
        x, yy = (t, y) if along == "x" else (y, t)
        _shrub(sp, x, yy, z + 0.35, 0.27 + 0.05 * (i % 2), leaf[i % 2])


def _lamp_post(sp: Sprite, x, y, h=2.6, color=WARM_WINDOW, r=11, z=0.0):
    sp.line((x, y, z), (x, y, z + h), 0.07, "#5c626b")
    sp.lamp((x, y, z + h + 0.1), color, r)


def _dish(sp: Sprite, c, n, r, mat: Mat = WHITE):
    """작은 접시 안테나: 판, 테두리, 급전 다리와 금빛 급전부."""
    sp.disc(c, n, r, mat, back=STEEL, seg=40)
    sp.ring3(c, r, "#b9b2a5", 0.07, normal=n, front_only=False)
    feed = add(c, mul(n, r * 0.62))
    u, w = basis(n)
    for a in (0, 120, 240):
        rim = add(c, add(mul(u, r * 0.85 * math.cos(math.radians(a))), mul(w, r * 0.85 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.045, "#8a9099")
    sp.sphere(feed, max(0.1, r * 0.08), GOLD)


def _beacon_mast(sp: Sprite, base, h, w=0.07, color="#9aa1aa"):
    """안테나 기둥 + 꼭대기 붉은 표시등 (높은 건물의 항공 표시)."""
    sp.line(base, add(base, (0, 0, h)), w, color)
    sp.line(add(base, (-0.35, 0, h * 0.7)), add(base, (0.35, 0, h * 0.7)), 0.05, color)
    sp.lamp(add(base, (0, 0, h + 0.1)), RED_LIGHT, 7)


def _airlock(sp: Sprite, x0, y0, w, d, h, accent: Mat, z=0.25):
    """1층 출입 에어록 (+x 쪽으로 낸다): 상자 → 문(불 켜진 등) → 색 띠 → 작은 창."""
    sp.box(x0, y0, z, w, d, h, CONCRETE, top=Mat("#b3a48e"))
    f = Sprite.box_faces(x0, y0, z, w, d, h)
    front, side = f["right"], f["left"]
    door(sp, front, 0.3, 0.7, 0.78, Mat("#5c626b", 0.3))
    band_on(sp, side, 0.82, 0.93, accent)
    band_on(sp, front, 0.86, 0.95, accent)
    sp.window(sp.on_face(*side, 0.22, 0.42, 0.78, 0.7))


# ═════════════════════════════════════════════════════════════════════
# 고층 주거 타워 (거주 계열)
# ═════════════════════════════════════════════════════════════════════

def _skirt(sp: Sprite, b, t, z0, z1, mat: Mat = BERM, lines=(0.3, 0.6), color="#5f5953"):
    """경사 차폐벽: 바닥 사각형 b(x0, y0, x1, y1)에서 벽 둘레 t까지 z1 높이로 기운 네 면 (윗면 없음 — 벽에 붙는다).
    뒤 두 면 → 앞 두 면 → 앞 두 면의 모래주머니 줄."""
    bx0, by0, bx1, by1 = b
    tx0, ty0, tx1, ty1 = t
    B = [(bx0, by0, z0), (bx1, by0, z0), (bx1, by1, z0), (bx0, by1, z0)]
    T = [(tx0, ty0, z1), (tx1, ty0, z1), (tx1, ty1, z1), (tx0, ty1, z1)]
    for i in (3, 0, 1, 2):
        q = [B[i], B[(i + 1) % 4], T[(i + 1) % 4], T[i]]
        sp.face(q, mat, ao=0.0)
    for s in lines:
        zz = z0 + (z1 - z0) * s
        p = [(bx0 + (tx0 - bx0) * s, by1 + (ty1 - by1) * s, zz), (bx1 + (tx1 - bx1) * s, by1 + (ty1 - by1) * s, zz),
             (bx1 + (tx1 - bx1) * s, by0 + (ty0 - by0) * s, zz)]
        sp.polyline3(p, color, 0.06, 0.75)


def _hab_podium(sp: Sprite, v, x0, y0, x1, y1, zb, fhp, accent: Mat):
    """기단 3층: 두꺼운 차폐벽과 깊은 창 몇 개. v0 소결 블록, v1 경사 차폐벽, v2 물벽 판, v3 둥근 인쇄 소결, v4 현무암."""
    H = 3 * fhp
    mat = (TAN, Mat("#9C8B72"), WATER_WALL, SINTER, BASALT)[v]
    joint = ("#8d7a5c", "#7f705b", "#4f7286", "#7f7262", "#5f5a54")[v]
    if v == 3:
        base = rounded_rect(x0, y0, x1, y1, 1.1)
        sp.prism(base, zb, H, mat, top=TERRACE)
        frames = _edge_frames(base, zb, H)
        sides = {"-y": frames[0], "+x": frames[2], "+y": frames[4], "-x": frames[6]}
        for fr in frames:
            _joints(sp, fr, 1, 16, joint, 0.05, 0.7)
    else:
        sp.box(x0, y0, zb, x1 - x0, y1 - y0, H, mat, top=TERRACE)
        sides = _faces4(x0, y0, zb, x1 - x0, y1 - y0, H)
        for key, fr in sides.items():
            L = length(fr[1])
            if v in (2, 4):
                _joints(sp, fr, max(2, int(L / 1.3)), 6 if v == 2 else 9, joint, 0.07, 0.85)
            else:
                _joints(sp, fr, max(2, int(L / 1.7)), 12, joint, 0.05, 0.75)
    # 깊은 창 (2·3층, 면마다 둘셋) — v1은 3층만 (아래는 경사 차폐벽)
    for key, fr in sides.items():
        L = length(fr[1])
        cols = 3 if L > 6.5 else 2
        k0 = 2 if v == 1 else 1
        _facade(sp, _band(fr, k0 * fhp, H), 3 - k0, fhp, cols, mat, sill=0.85, head=2.05, pier=(L - 0.8) / cols - 0.8,
                margin=0.4, rm=0.16, banded=False, seed=v + len(key), dark=0.3)
    # 기단 꼭대기 띠 (색)
    if v != 3:
        for key, fr in sides.items():
            _decal(sp, fr, 0.0, 1 - 0.32 / H, 1.0, 1 - 0.14 / H, accent, 0.02)
    return sides


@typed("hab_tower", 10, 8, 48.0, "고층 주거 타워", heights=[48.4, 47.9, 48.3, 47.7, 48.6])
def hab_tower(sp: Sprite, v: int):
    """두꺼운 차폐 기단(깊은 창 몇 개, 출입 에어록) 위의 날씬한 주거 탑. 층마다 작은 창 줄과 바닥판 띠,
    몇 층은 유리 겨울 정원·발코니, 꼭대기에는 방열판·안테나·빛나는 색 띠와 붉은 항공 표시등.
    v0 곧은 탑과 겨울 정원 줄, v1 세 단으로 물러서는 탑과 옥상 정원, v2 승강 코어로 이은 두 판상 동,
    v3 모서리를 깎은 팔각 탑과 발코니·옥상 유리 정원 돔, v4 바깥 유리 승강기 관과 중간층 하늘 정원."""
    accent = (TEAL, ORANGE, BLUE, YELLOW, RED)[v]
    aglow = (CYAN_LIGHT, "#FFB37A", "#9CC4FF", "#FFE08A", "#FF8A7A")[v]
    wall = (Mat("#D3C6AE"), Mat("#CDB894"), Mat("#D6D2C8"), Mat("#DDD2BC"), Mat("#CBBFA9"))[v]
    zb, fhp, fh = 0.25, 3.0, 2.9
    zp = zb + 3 * fhp                                   # 기단 지붕 (9.25)
    px0, py0, px1, py1 = ((-4.6, -3.6, 3.2, 3.0), (-4.0, -3.1, 3.0, 2.7), (-4.6, -3.6, 3.2, 3.0),
                          (-4.6, -3.6, 3.2, 3.0), (-4.6, -3.6, 3.2, 3.0))[v]
    sp.contact_shadow(-0.3, -0.3, 5.4, 4.4, 0.5)
    sp.box(-4.9, -3.9, 0, 9.8, 7.8, zb, CONCRETE)
    sp.face([(px1, -0.7, zb + 0.01), (4.85, -0.7, zb + 0.01), (4.85, 0.7, zb + 0.01), (px1, 0.7, zb + 0.01)], PAVE,
            normal=(0, 0, 1), ao=0, edge=False)
    _hab_podium(sp, v, px0, py0, px1, py1, zb, fhp, accent)
    if v == 1:
        _skirt(sp, (-4.85, -3.85, 3.85, 3.55), (px0, py0, px1, py1), zb, zb + 5.6, Mat("#8B7E6C"))
    kw = dict(dark=0.24)
    if v == 0:
        # 곧은 탑 + 해 드는 +y 면의 겨울 정원 줄
        tx0, ty0, tx1, ty1, nf = -3.7, -2.9, 2.3, 2.1, 12
        _terrace_back(sp, px0, py0, px1, py1, zp)
        _shaft(sp, tx0, ty0, tx1, ty1, zp, nf, fh, wall, seed=1, **kw)
        for k in (2, 3, 6, 7, 10):
            xa, xb = (-3.35, -1.15) if k % 4 in (2, 3) else (-0.2, 1.95)
            _winter_garden(sp, xa, xb, ty1, 0.95, zp + k * fh + 0.12, zp + (k + 1) * fh - 0.22,
                           (LEAF, GREEN)[k % 2])
        zt = zp + nf * fh
        _terrace_front(sp, px0, py0, px1, py1, tx0, ty0, tx1, ty1, zp)
        _crown_flat(sp, tx0, ty0, tx1, ty1, zt, accent, aglow, v)
    elif v == 1:
        # 세 단으로 물러서는 탑 (단마다 앞쪽 옥상 정원)
        tiers = ((-3.7, -2.8, 2.6, 2.3, 5), (-3.5, -2.6, 1.5, 1.3, 4), (-3.3, -2.4, 0.5, 0.4, 3))
        z = zp
        _terrace_back(sp, px0, py0, px1, py1, zp)
        zs = []
        for i, (x0, y0, x1, y1, n) in enumerate(tiers):
            _shaft(sp, x0, y0, x1, y1, z, n, fh, wall, seed=4 + i, **kw)
            z += n * fh
            zs.append(z)
        for i in (0, 1):                                   # 물러선 자리의 정원은 위 단보다 앞이라 나중에
            _setback_garden(sp, tiers[i][:4], tiers[i + 1][:4], zs[i], i)
        for k in (1, 3):                                   # 아래 단의 겨울 정원
            _winter_garden(sp, -3.4, -1.3, tiers[0][3], 0.9, zp + k * fh + 0.12, zp + (k + 1) * fh - 0.22,
                           (GREEN, LEAF)[k % 2])
        _terrace_front(sp, px0, py0, px1, py1, *tiers[0][:4], zp)
        _crown_pyramid(sp, *tiers[2][:4], z, accent, aglow)
    elif v == 2:
        _twin_slabs(sp, zp, fh, wall, accent, aglow, px0, py0, px1, py1, kw)
    elif v == 3:
        _octagon_tower(sp, zp, fh, wall, accent, aglow, px0, py0, px1, py1, kw)
    else:
        _lift_tube_tower(sp, zp, fh, wall, accent, aglow, px0, py0, px1, py1, kw)
    # 1층 출입 에어록 (+x 면)과 앞마당
    _airlock(sp, px1, -1.05, 4.55 - px1, 2.1, 2.8, accent, zb)
    sp.box(px1 + 0.2, -1.25, zb + 2.8, 4.65 - px1, 2.5, 0.16, Mat("#D9D4CA", 0.1), top=SILVER)
    sp.lamp((4.6, 1.05, zb + 2.55), AMBER, 9)
    sp.lamp((4.6, -1.05, zb + 2.55), AMBER, 9)
    if v != 1:
        for (bx0, bx1) in ((-4.3, -2.4), (-1.6, 0.4)):
            sp.box(bx0, py1 + 0.15, zb, bx1 - bx0, 0.6, 0.35, PLANTER, top=SOIL)
            m = max(2, int((bx1 - bx0) / 0.55))
            for i in range(m):
                _shrub(sp, bx0 + (bx1 - bx0) * (i + 0.5) / m, py1 + 0.45, zb + 0.35, 0.25, (LEAF, GREEN)[(i + v) % 2])
    _lamp_post(sp, 2.3, 3.6, 2.6, WARM_WINDOW, 11, zb)
    if v in (2, 4):
        _lamp_post(sp, -4.6, 3.6, 2.6, WARM_WINDOW, 11, zb)


def _terrace_back(sp: Sprite, px0, py0, px1, py1, zp):
    """기단 지붕 뒤쪽 (탑보다 먼저): 공조 상자."""
    sp.box(px0 + 0.3, py0 + 0.25, zp, 1.4, 0.5, 0.6, STEEL, top=DARK)


def _terrace_front(sp: Sprite, px0, py0, px1, py1, tx0, ty0, tx1, ty1, zp, c=0.0, xrow=None):
    """기단 지붕 앞 마당 (탑 다음에): 자리가 있는 쪽에 화분 줄 → 유리 난간 (c: 기단 모서리를 깎은 길이) → 등.
    xrow: +x 쪽 화분 줄의 y 범위 (없으면 탑 옆 전체)."""
    sy, sx = py1 - ty1, px1 - tx1
    if sy >= 0.8:
        d = min(0.55, sy - 0.35)
        _planter_row(sp, tx0 + 0.3, tx1 - 0.2, ty1 + 0.1 + d / 2, zp, d)
    if sx >= 0.8:
        d = min(0.55, sx - 0.35)
        ya, yb = xrow or (ty0 + 0.3, ty1 - 0.2)
        _planter_row(sp, ya, yb, tx1 + 0.1 + d / 2, zp, d, (GREEN, LEAF), along="y")
    if c > 0:
        pts = [(px0 + c, py1 - 0.1), (px1 - c - 0.04, py1 - 0.1), (px1 - 0.1, py1 - c - 0.04), (px1 - 0.1, py0 + c)]
    else:
        pts = [(px0 + 0.1, py1 - 0.1), (px1 - 0.1, py1 - 0.1), (px1 - 0.1, py0 + 0.1)]
    _rail(sp, pts, zp, 0.85)
    sp.lamp((px1 - 0.3 - c * 0.6, py1 - 0.3 - c * 0.6, zp + 1.0), WARM_WINDOW, 8)


def _crown_flat(sp: Sprite, x0, y0, x1, y1, zt, accent: Mat, aglow, v):
    """평지붕 왕관: 처마 띠(밤에 빛난다) → 기계실 → 방열판 둘 → 접시 → 안테나와 붉은 표시등."""
    b = 0.12
    sp.box(x0 - b, y0 - b, zt, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.8, Mat("#E2DACB"), top=ROOF)
    for fr in _faces4(x0 - b, y0 - b, zt, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.8).values():
        _lit_decal(sp, fr, 0.0, 0.3, 1.0, 0.62, accent, aglow, 0.8)
    zr = zt + 0.8
    for i in range(2):                                  # 뒤쪽 방열판 (높은 지느러미 둘)
        ry = y0 + 0.4 + i * 0.6
        legs(sp, [(x0 + 0.5, ry, zr + 0.25), (x1 - 0.5, ry, zr + 0.25)], zr)
        _radiator(sp, (x0 + 0.3, ry, zr + 0.25), (x1 - x0 - 0.6, 0, 0), (0, 0, 1.7), 8)
    mx0, my0 = x0 + 0.9, y0 + 1.65
    sp.box(mx0, my0, zr, 2.9, 2.2, 1.8, Mat("#C9C3B6"), top=DARK)
    mf = _faces4(mx0, my0, zr, 2.9, 2.2, 1.8)
    for key in ("+y", "+x", "-y", "-x"):
        for i in range(4):
            _decal(sp, mf[key], 0.12 + i * 0.2, 0.3, 0.24 + i * 0.2, 0.75, DARK, 0.02)
    door(sp, mf["+x"], 0.3, 0.7, 0.85, Mat("#5c626b", 0.3), light=False)
    sp.line((x1 - 0.75, y1 - 0.8, zr), (x1 - 0.75, y1 - 0.8, zr + 0.6), 0.1, "#9aa1aa")
    _dish(sp, (x1 - 0.75, y1 - 0.8, zr + 0.95), norm((0.45, 0.6, 0.65)), 0.7)
    _beacon_mast(sp, (mx0 + 1.45, my0 + 1.1, zr + 1.8), 1.5)


def _crown_pyramid(sp: Sprite, x0, y0, x1, y1, zt, accent: Mat, aglow):
    """작은 탑 위의 빛나는 각뿔 지붕 + 안테나."""
    b = 0.15
    sp.box(x0 - b, y0 - b, zt, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.45, Mat("#E2DACB"), top=ROOF)
    for fr in _faces4(x0 - b, y0 - b, zt, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.45).values():
        _lit_decal(sp, fr, 0.0, 0.25, 1.0, 0.75, accent, aglow, 0.8)
    z = zt + 0.45
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    c = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    apex = (cx, cy, z + 1.9)
    for i in range(4):
        _lit(sp, [c[i], c[(i + 1) % 4], apex], Mat("#B8BEC4", 0.35), aglow, 0.3)
    _beacon_mast(sp, apex, 1.3)


def _setback_garden(sp: Sprite, lower, upper, z, i):
    """물러선 자리 (아래 단 지붕 앞쪽 ㄱ자 띠)의 옥상 정원: 화분 줄 → 유리 난간."""
    x0, y0, x1, y1 = lower
    ux0, uy0, ux1, uy1 = upper
    _planter_row(sp, x0 + 0.3, ux1 + 0.2, (uy1 + y1) / 2, z, 0.55, (GREEN, LEAF))
    _planter_row(sp, uy0 + 0.3, y1 - 0.4, (ux1 + x1) / 2, z, 0.55, (LEAF, GREEN), along="y")
    _rail(sp, [(x0 + 0.05, y1 - 0.08), (x1 - 0.08, y1 - 0.08), (x1 - 0.08, y0 + 0.05)], z, 0.8)
    sp.glow(((ux1 + x1) / 2, (uy1 + y1) / 2, z + 0.6), 22, GARDEN_LIGHT, 0.3)


def _twin_slabs(sp: Sprite, zp, fh, wall: Mat, accent: Mat, aglow, px0, py0, px1, py1, kw):
    """v2: 엇갈려 선 얇은 판상 동 둘 (뒤 동이 두 층 높고 오른쪽으로 더 나온다)을 가운데 유리 승강 코어와
    색 테를 두른 유리 하늘 다리로 잇는다."""
    bx0, by0, bx1, by1, nb = -3.4, -3.3, 2.9, -1.05, 12          # 뒤 동
    fx0, fy0, fx1, fy1, nfr = -4.25, 0.55, 1.8, 2.65, 10         # 앞 동
    cx0, cy0, cx1, cy1 = -1.6, -1.05, 0.4, 0.55                   # 코어
    front_hull = _screen_hull(_box_pts(fx0 - 0.15, fy0, zp, fx1 + 0.15, fy1 + 0.15, zp + nfr * fh + 0.7))
    _terrace_back(sp, px0, py0, px1, py1, zp)
    _shaft(sp, bx0, by0, bx1, by1, zp, nb, fh, wall, seed=7, hide={"+y": front_hull}, **kw)
    # 코어: 유리 승강로 (층마다 테, 불 켜진 승강 칸)
    zc1 = zp + nb * fh + 2.2
    sp.box(cx0, cy0, zp, cx1 - cx0, cy1 - cy0, zc1 - zp, Mat("#2F4659", 0.7), top=DARK)
    for key, fr in _faces4(cx0, cy0, zp, cx1 - cx0, cy1 - cy0, zc1 - zp).items():
        _joints(sp, fr, 2, int((zc1 - zp) / fh), "#c3ccd4", 0.07, 0.9)
    sp.box(cx0 + 0.6, cy0 + 0.4, zp + 9.4 * fh, 0.8, 0.8, 2.0, LIFT_CAB)
    sp.glow((cx0 + 1.0, cy0 + 0.8, zp + 9.4 * fh + 1.0), 12, "#ffe2a0", 0.6)
    # 하늘 다리 (두 동 사이 틈, 4·8층): 바닥 테 → 유리 둘 → 불빛 → 지붕 테
    for k in (3, 7):
        z0 = zp + k * fh + 0.1
        bxa, bxb = 0.8, fx1
        sp.box(bxa, by1, z0 - 0.25, bxb - bxa, fy0 - by1, 0.25, accent)
        _glass_pane(sp, [(bxa, fy0, z0), (bxa, by1, z0), (bxa, by1, z0 + 2.4), (bxa, fy0, z0 + 2.4)], alpha=0.12)
        pane = [(bxb, by1, z0), (bxb, fy0, z0), (bxb, fy0, z0 + 2.4), (bxb, by1, z0 + 2.4)]
        _glass_pane(sp, pane, alpha=0.2)
        sp.light_poly([add(p, (0.02, 0, 0)) for p in pane], WARM_WINDOW, 0.35)
        sp.line((bxb, (by1 + fy0) / 2, z0), (bxb, (by1 + fy0) / 2, z0 + 2.4), 0.06, "#d9d4ca")
        sp.box(bxa, by1, z0 + 2.4, bxb - bxa, fy0 - by1, 0.22, accent)
    _shaft(sp, fx0, fy0, fx1, fy1, zp, nfr, fh, wall, seed=11, **kw)
    for k in (2, 5, 8):                                    # 앞 동의 겨울 정원
        _winter_garden(sp, -0.7, 1.45, fy1, 0.9, zp + k * fh + 0.12, zp + (k + 1) * fh - 0.22, (LEAF, GREEN)[k % 2])
    # 지붕: 뒤 동 방열판, 앞 동 옥상 정원, 코어 꼭대기 빛 띠와 안테나
    zt_b, zt_f = zp + nb * fh, zp + nfr * fh
    for zt, (x0, y0, x1, y1) in ((zt_b, (bx0, by0, bx1, by1)), (zt_f, (fx0, fy0, fx1, fy1))):
        sp.box(x0 - 0.1, y0 - 0.1, zt, x1 - x0 + 0.2, y1 - y0 + 0.2, 0.6, Mat("#E2DACB"), top=ROOF)
        for fr in _faces4(x0 - 0.1, y0 - 0.1, zt, x1 - x0 + 0.2, y1 - y0 + 0.2, 0.6).values():
            _lit_decal(sp, fr, 0.0, 0.3, 1.0, 0.65, accent, aglow, 0.75)
    zr = zt_b + 0.6
    legs(sp, [(bx1 - 3.6, by0 + 0.8, zr + 0.25), (bx1 - 0.5, by0 + 0.8, zr + 0.25)], zr)
    _radiator(sp, (bx1 - 3.8, by0 + 0.8, zr + 0.25), (3.5, 0, 0), (0, 0, 1.3), 6)
    _planter_row(sp, fx0 + 0.5, fx1 - 0.5, (fy0 + fy1) / 2, zt_f + 0.6, 0.6)
    sp.lamp((fx1 - 0.3, fy1 - 0.3, zt_f + 1.4), WARM_WINDOW, 9)
    sp.box(cx0 - 0.1, cy0 - 0.1, zc1, cx1 - cx0 + 0.2, cy1 - cy0 + 0.2, 0.5, STEEL, top=DARK)
    for fr in _faces4(cx0 - 0.1, cy0 - 0.1, zc1, cx1 - cx0 + 0.2, cy1 - cy0 + 0.2, 0.5).values():
        _lit_decal(sp, fr, 0.0, 0.25, 1.0, 0.75, accent, aglow, 0.9)
    _beacon_mast(sp, ((cx0 + cx1) / 2, (cy0 + cy1) / 2, zc1 + 0.5), 1.3)
    _terrace_front(sp, px0, py0, px1, py1, fx0, fy0, fx1, fy1, zp)


def _octagon_tower(sp: Sprite, zp, fh, wall: Mat, accent: Mat, aglow, px0, py0, px1, py1, kw):
    """v3: 모서리를 깎은 팔각 탑. 층 사이는 밝은 띠, +y·+x 면에 번갈아 발코니, 꼭대기에 유리 정원 돔."""
    nf = 12
    base = rounded_rect(-3.6, -2.8, 2.2, 2.0, 0.9)
    H = nf * fh
    _terrace_back(sp, px0, py0, px1, py1, zp)
    sp.prism(base, zp, H, wall, top=ROOF)
    frames = _edge_frames(base, zp, H)
    band = Mat("#EEE6D6")
    for i, fr in enumerate(frames):
        L = length(fr[1])
        if i % 2 == 0:
            cols = max(2, int(round((L - 0.6) / 1.0)))
            _facade(sp, fr, nf, fh, cols, wall, margin=0.3, seed=20 + i, spandrel=band, **kw)
        else:
            _facade(sp, fr, nf, fh, 1, wall, margin=0.2, pier=0.3, seed=30 + i, spandrel=band, **kw)
    # 발코니 (+y·+x 면, 번갈아)
    for k in range(1, nf):
        z = zp + k * fh + 0.02
        if k % 2 == 1:
            _balcony_y(sp, -2.6, 1.2, 2.0, 0.9, z)
        else:
            _balcony_x(sp, 2.2, -1.8, 1.0, 0.85, z)
    zt = zp + H
    sp.prism(rounded_rect(-3.75, -2.95, 2.35, 2.15, 1.0), zt, 0.5, Mat("#E2DACB"), top=ROOF)
    for i, fr in enumerate(_edge_frames(rounded_rect(-3.75, -2.95, 2.35, 2.15, 1.0), zt, 0.5)):
        _lit_decal(sp, fr, 0.0, 0.3, 1.0, 0.7, accent, aglow, 0.8)
    zr = zt + 0.5
    _garden_dome(sp, (-0.7, -0.4), 2.1, 2.6, zr)
    _terrace_front(sp, px0, py0, px1, py1, -3.6, -2.8, 2.2, 2.0, zp, c=1.1)


def _balcony_y(sp: Sprite, xa, xb, y, dp, z):
    """+y 면의 열린 발코니: 바닥판 → 유리 난간 (앞·옆) → 손잡이."""
    sp.box(xa, y, z - 0.15, xb - xa, dp, 0.15, SLAB)
    yf = y + dp - 0.04
    _glass_pane(sp, [(xb, yf, z), (xa, yf, z), (xa, yf, z + 0.85), (xb, yf, z + 0.85)], alpha=0.14)
    sp.polyline3([(xa, y, z + 0.9), (xa, yf, z + 0.9), (xb, yf, z + 0.9), (xb, y, z + 0.9)], "#c9ccd1", 0.06)


def _balcony_x(sp: Sprite, x, ya, yb, dp, z):
    """+x 면의 열린 발코니."""
    sp.box(x, ya, z - 0.15, dp, yb - ya, 0.15, SLAB)
    xf = x + dp - 0.04
    _glass_pane(sp, [(xf, ya, z), (xf, yb, z), (xf, yb, z + 0.85), (xf, ya, z + 0.85)], alpha=0.14)
    sp.polyline3([(x, yb, z + 0.9), (xf, yb, z + 0.9), (xf, ya, z + 0.9), (x, ya, z + 0.9)], "#c9ccd1", 0.06)


def _garden_dome(sp: Sprite, c, r, h, z0, ribs=12):
    """옥상 유리 정원 돔: 바닥 테 → 나무 → 유리 껍질과 갈비 (밤에 초록빛) → 꼭대기 등."""
    cx, cy = c
    sp.cyl((cx, cy, z0), (cx, cy, z0 + 0.3), r + 0.15, STEEL, cap_mat=Mat("#5E7A4A"))
    zf = z0 + 0.3
    sp.tree((cx - 0.5, cy - 0.3, zf), 1.9, 0.75, LEAF)
    sp.tree((cx + 0.7, cy + 0.4, zf), 1.5, 0.6, GREEN)
    _shrub(sp, cx + 0.2, cy + 1.1, zf, 0.4, LEAF)
    pts = []
    for i in range(48):
        th = 2 * math.pi * i / 48
        for j in range(10):
            ph = (math.pi / 2) * j / 9
            pts.append(P(cx + r * math.cos(ph) * math.cos(th), cy + r * math.cos(ph) * math.sin(th), zf + h * math.sin(ph)))
    sil = hull(pts)
    hl = PV((cx - r * 0.28, cy + r * 0.5, zf + h * 0.8))
    fill = sp.radial([(0, "#ffffff", 0.3), (0.4, "#cfe6ff", 0.12), (1, "#9fc0e0", 0.05)], hl[0], hl[1], r * S * 1.6)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_shell((cx, cy, zf), r, r, h, zf)
    for i in range(ribs):
        th = 2 * math.pi * i / ribs
        q = [(cx + r * 1.005 * math.cos(ph) * math.cos(th), cy + r * 1.005 * math.cos(ph) * math.sin(th),
              zf + h * 1.005 * math.sin(ph)) for ph in [k * math.pi / 16 for k in range(9)]]
        if dot((math.cos(th), math.sin(th), 0.0), VIEW) < -0.15:
            sp._rec(("line", q, 0.05, "#dfe9f2", False))
        else:
            sp.polyline3(q, "#dfe9f2", 0.05, 0.7)
    sp.ring3((cx, cy, zf + h * 0.5), r * math.sqrt(0.75), "#dfe9f2", 0.05, opacity=0.6)
    sp.poly2(sil, GARDEN_LIGHT, None, 0, 0.3, layer="light")
    sp._rec(("lpoly", [(cx + r * 0.9 * math.cos(2 * math.pi * k / 20), cy + r * 0.9 * math.sin(2 * math.pi * k / 20),
                        zf + 0.04) for k in range(20)], GARDEN_LIGHT, 0.5))
    sp.glow((cx, cy, zf + h * 0.45), r * S * 1.1, GARDEN_LIGHT, 0.35)
    sp.lamp((cx, cy, zf + h + 0.12), RED_LIGHT, 7)


def _lift_tube_tower(sp: Sprite, zp, fh, wall: Mat, accent: Mat, aglow, px0, py0, px1, py1, kw):
    """v4: 곧은 탑 가운데에 기둥만 남긴 하늘 정원 층, +x 면에 바깥 유리 승강기 관, 붉은 띠 왕관과 접시."""
    x0, y0, x1, y1 = -3.6, -2.9, 1.8, 1.9
    n1, n2 = 6, 5
    _terrace_back(sp, px0, py0, px1, py1, zp)
    _shaft(sp, x0, y0, x1, y1, zp, n1, fh, wall, seed=13, **kw)
    zg = zp + n1 * fh                                         # 하늘 정원 층
    sp.box(x0 - 0.12, y0 - 0.12, zg - 0.09, x1 - x0 + 0.24, y1 - y0 + 0.24, 0.3, SLAB, top=Mat("#6E8C55"))
    sp.box(-1.9, -1.6, zg + 0.21, 1.6, 1.5, fh - 0.3, Mat("#C9C3B6"), top=DARK)
    for (tx, ty, s) in ((-2.6, -1.9, 1.0), (0.6, -1.9, 0.85)):
        sp.tree((tx, ty, zg + 0.21), 2.2 * s, 0.75 * s, LEAF)
    for (cx, cy) in ((x0 + 0.2, y0 + 0.2), (x1 - 0.2, y0 + 0.2), (x0 + 0.2, y1 - 0.2)):
        sp.cyl((cx, cy, zg + 0.21), (cx, cy, zg + fh), 0.2, wall, edge=False)
    _planter_row(sp, x0 + 0.5, x1 - 0.6, y1 - 0.5, zg + 0.21, 0.55)
    sp.tree((x1 - 0.9, y1 - 1.3, zg + 0.21), 1.9, 0.7, GREEN)
    sp.cyl((x1 - 0.2, y1 - 0.2, zg + 0.21), (x1 - 0.2, y1 - 0.2, zg + fh), 0.2, wall, edge=False)
    _rail(sp, [(x0, y1 + 0.05), (x1 + 0.05, y1 + 0.05), (x1 + 0.05, y0)], zg + 0.21, 0.9, 0.1)
    sp.glow(((x0 + x1) / 2, (y0 + y1) / 2, zg + 1.4), 40, GARDEN_LIGHT, 0.35)
    zu = zg + fh
    sp.box(x0 - 0.12, y0 - 0.12, zu - 0.21, x1 - x0 + 0.24, y1 - y0 + 0.24, 0.3, SLAB)
    _shaft(sp, x0, y0, x1, y1, zu + 0.09, n2, fh, wall, seed=17, **kw)
    zt = zu + 0.09 + n2 * fh
    # 왕관 띠: 붉은 빛 띠 둘 (승강기 관보다 뒤라 먼저)
    b = 0.12
    for i, zz in enumerate((zt, zt + 0.8)):
        sp.box(x0 - b, y0 - b, zz, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.8, Mat("#E2DACB") if i == 0 else Mat("#D4CCBD"),
               top=ROOF)
        for fr in _faces4(x0 - b, y0 - b, zz, x1 - x0 + 2 * b, y1 - y0 + 2 * b, 0.8).values():
            _lit_decal(sp, fr, 0.0, 0.35, 1.0, 0.65, accent, aglow, 0.85)
    # 바깥 유리 승강기 관 (+x 면): 그림은 옅은 푸른 원통, 3D는 비치는 유리 원통 (층마다 테) → 승강 칸 → 받침 → 기계실
    lx, ly, lr = x1 + 0.62, -0.5, 0.5
    z1 = zt + 0.9
    nb = int((z1 - zp) / fh)
    with sp._nest():
        sp.cyl((lx, ly, zp), (lx, ly, z1), lr, Mat("#9FC3DA", 0.85), cap_mat=STEEL)
        for k in range(1, nb + 1):
            sp.ring3((lx, ly, zp + k * fh), lr + 0.01, "#dfe9f2", 0.05)
    sp._rec(("fru", (lx, ly, zp), (lx, ly, z1), lr, lr, iso._Glass(ATRIUM_GLASS, 0.25), True, STEEL,
             tuple(k * fh / (z1 - zp) for k in range(1, nb + 1)), "#dfe9f2", None))
    sp.line((lx - 0.25, ly - 0.3, zp), (lx - 0.25, ly - 0.3, z1), 0.06, "#8a9099")
    sp.box(lx - 0.3, ly - 0.3, zp + 5.3 * fh, 0.6, 0.6, 1.9, LIFT_CAB)
    sp.glow((lx, ly, zp + 5.3 * fh + 1.0), 14, "#ffe2a0", 0.7)
    for k in (1, 4, 8, 11):                                  # 관을 벽에 잡아 두는 받침 (빈 정원 층은 건너뛴다)
        sp.box(x1, ly - 0.25, zp + k * fh + 0.4, 0.15, 0.5, 2.2, STEEL)
    sp.box(lx - 0.6, ly - 0.6, z1, 1.2, 1.2, 0.6, STEEL, top=DARK)
    # 옥상: 기계실 → 접시 → 안테나
    zr = zt + 1.6
    sp.box(x0 + 0.6, y0 + 0.6, zr, 2.2, 1.8, 1.2, Mat("#C9C3B6"), top=DARK)
    sp.cyl((x1 - 1.1, y0 + 1.2, zr), (x1 - 1.1, y0 + 1.2, zr + 0.8), 0.18, STEEL)
    _dish(sp, (x1 - 1.1, y0 + 1.2, zr + 1.6), norm((0.35, 0.75, 0.55)), 1.0)
    _beacon_mast(sp, (x0 + 1.7, y0 + 1.5, zr + 1.2), 1.4)
    _terrace_front(sp, px0, py0, px1, py1, x0, y0, x1, y1, zp, xrow=(0.4, y1 - 0.2))


# ═════════════════════════════════════════════════════════════════════
# 연구 타워 (연구 계열)
# ═════════════════════════════════════════════════════════════════════

def _obs_dome(sp: Sprite, c, R, z, body: Mat = WHITE, face=(1.0, 0.35)):
    """관측 돔: 원통 받침 → 흰 반구 → 하늘을 보는 어두운 틈 (두 토막) → 붉은 등."""
    cx, cy = c
    sp.cyl((cx, cy, z), (cx, cy, z + 0.7 * R), R, body, cap_mat=SILVER)
    zc = z + 0.7 * R
    sp.sphere((cx, cy, zc), R, Mat("#F1F2F0", 0.3), clip_z=zc)
    d = norm((face[0], face[1], 0.0))
    side = (-d[1], d[0], 0.0)
    for (a0, a1) in ((0.3, 0.85), (0.85, 1.45)):
        q = []
        for a, s in ((a0, -1), (a0, 1), (a1, 1), (a1, -1)):
            rad = add(mul(d, math.cos(a)), (0.0, 0.0, math.sin(a)))
            q.append(add(add((cx, cy, zc), mul(rad, R * 1.06)), mul(side, s * R * 0.2)))
        sp.face(_orient(q, add(mul(d, math.cos((a0 + a1) / 2)), (0, 0, math.sin((a0 + a1) / 2)))), Mat("#1b1e24"),
                ao=0, edge=False)
    sp.lamp((cx, cy, zc + R + 0.15), RED_LIGHT, 6)
    return zc + R


def _stacks(sp: Sprite, x, y, z, n=3, step=0.8, band="#9B7AD6"):
    """실험실 배기구 줄."""
    for i in range(n):
        xx = x + i * step
        sp.cyl((xx, y, z), (xx, y, z + 0.9), 0.2, STEEL, bands=[0.7], band_color=band)
        sp.cyl((xx, y, z + 0.9), (xx, y, z + 1.0), 0.3, Mat("#9aa1aa", 0.3), cap_mat=DARK)


def _weather_mast(sp: Sprite, x, y, z, h=3.0):
    """기상 기둥: 기둥 → 금빛 계기 상자 → 가로대와 공 → 붉은 등."""
    sp.box(x - 0.3, y - 0.3, z, 0.6, 0.6, 0.3, STEEL)
    sp.line((x, y, z + 0.3), (x, y, z + h), 0.1, "#9aa1aa")
    sp.box(x - 0.25, y - 0.25, z + h * 0.55, 0.5, 0.5, 0.45, GOLD)
    sp.line((x - 0.6, y, z + h * 0.85), (x + 0.6, y, z + h * 0.85), 0.06, "#9aa1aa")
    sp.sphere((x + 0.6, y, z + h * 0.85), 0.12, WHITE)
    sp.lamp((x, y, z + h + 0.12), RED_LIGHT, 6)


def _lab_block(sp: Sprite, x0, y0, x1, y1, z0, nl, fl, body: Mat, band: Mat, bglow, seed=0, faces=None, hide=None,
               cell=1.25, top: Mat = SILVER):
    """실험실 층 (상자): 몸통 → 면마다 띠창 (흰 띠 사이 긴 창, 가는 창살) → 꼭대기 색 띠. 면 틀을 돌려준다."""
    H = nl * fl
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, H, body, top=top)
    f = _faces4(x0, y0, z0, x1 - x0, y1 - y0, H)
    for key, fr in f.items():
        if faces is not None and key not in faces:
            continue
        L = length(fr[1])
        cols = max(2, int(round((L - 0.4) / cell)))
        _facade(sp, fr, nl, fl, cols, body, sill=0.95, head=2.85, pier=0.12, margin=0.2, reveal=None,
                glow=LAB_LIGHT, glass=LAB_GLASS, frame_col="#c3ccd4", seed=seed + len(key) * 5, dark=0.3, lit=0.8,
                dim=0.12, hide=(hide or {}).get(key))
        _lit_decal(sp, fr, 0.0, 1 - 0.5 / H, 1.0, 1 - 0.2 / H, band, bglow, 0.7)
    return f


def _lobby(sp: Sprite, x0, y0, x1, y1, z0, h, band: Mat, bglow, seed=0):
    """유리 로비 (1층): 몸통 → 큰 유리 창 줄 → 위 색 띠."""
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, h, Mat("#2F4659", 0.7), top=SILVER)
    for key, fr in _faces4(x0, y0, z0, x1 - x0, y1 - y0, h).items():
        L = length(fr[1])
        cols = max(2, int(round(L / 1.6)))
        _facade(sp, fr, 1, h, cols, PANEL, sill=0.1, head=h - 0.55, pier=0.14, margin=0.1, reveal=None,
                glow=WARM_WINDOW, glass=Mat("#3B5A6E", 0.85), frame_col="#e6e8ea", seed=seed + len(key), dark=0.1,
                lit=0.85, dim=0.3)
        _lit_decal(sp, fr, 0.0, 1 - 0.45 / h, 1.0, 1 - 0.15 / h, band, bglow, 0.8)


def _sky_bridge(sp: Sprite, x0, x1, y0, y1, z, h=2.6, glow=LAB_LIGHT, frame: Mat = PANEL):
    """두 동 사이 유리 하늘 다리 (x 방향): 바닥 테 → 뒤 유리 → 앞 유리와 불빛 → 창살 → 지붕 테."""
    sp.box(x0, y0, z - 0.25, x1 - x0, y1 - y0, 0.25, frame, top=Mat("#C9CED3", 0.2))
    _glass_pane(sp, [(x0, y0, z), (x1, y0, z), (x1, y0, z + h), (x0, y0, z + h)], alpha=0.12)
    front = [(x1, y1, z), (x0, y1, z), (x0, y1, z + h), (x1, y1, z + h)]
    _glass_pane(sp, front, alpha=0.2)
    sp.light_poly(_orient([add(p, (0, 0.02, 0)) for p in front], (0, 1, 0)), glow, 0.35)
    for t in (0.33, 0.66):
        x = x0 + (x1 - x0) * t
        sp.line((x, y1, z), (x, y1, z + h), 0.05, "#d7dde3")
    sp.box(x0, y0, z + h, x1 - x0, y1 - y0, 0.22, frame, top=Mat("#C9CED3", 0.2))


@typed("research_tower", 9, 9, 36.0, "연구 타워", heights=[36.2, 36.3, 35.7, 36.0, 35.7])
def research_tower(sp: Sprite, v: int):
    """흰 패널 연구 고층동: 유리 로비 위로 실험실 층마다 긴 띠창, 보라·청록 연구 띠, 유리 아트리움·하늘 다리,
    옥상에는 관측 돔·접시 안테나·배기구·기상 기둥과 붉은 표시등.
    v0 모서리 통유리 아트리움, v1 하늘 다리로 이은 두 동, v2 둥근 탑과 큰 관측 돔, v3 앞쪽으로 물러서는 단과 접시들,
    v4 가는 탑 위로 사방에 내민 관측층과 큰 접시."""
    band = (VIOLET, VIOLET, TEAL, ORANGE, TEAL)[v]
    bglow = (VIOLET_LIGHT, VIOLET_LIGHT, CYAN_LIGHT, "#FFB37A", CYAN_LIGHT)[v]
    body = (PANEL, PANEL, Mat("#E5E1D6", 0.08), PANEL, Mat("#D9DEE3", 0.1))[v]
    zb, hl = 0.3, 4.4
    zl = zb + hl                                         # 실험실 층 시작
    sp.contact_shadow(0, 0, 4.9, 4.9, 0.5)
    sp.box(-4.45, -4.45, 0, 8.9, 8.9, zb, CONCRETE, top=Mat("#b3a690"))
    sp.face([(0.8, 2.6, zb + 0.01), (4.4, 2.6, zb + 0.01), (4.4, 4.4, zb + 0.01), (0.8, 4.4, zb + 0.01)], PAVE,
            normal=(0, 0, 1), ao=0, edge=False)
    if v == 0:
        _rt_atrium(sp, zb, zl, 3.6, body, band, bglow)
    elif v == 1:
        _rt_twin(sp, zb, zl, 3.6, body, band, bglow)
    elif v == 2:
        _rt_round(sp, zb, zl, 3.8, body, band, bglow)
    elif v == 3:
        _rt_stepped(sp, zb, zl, 3.6, body, band, bglow)
    else:
        _rt_cantilever(sp, zb, zl, 3.4, body, band, bglow)
    for (x, y) in ((4.1, 4.1), (-3.9, 4.15), (4.15, -3.9)):
        _lamp_post(sp, x, y, 2.6, LAB_LIGHT, 11, zb)


def _rt_atrium(sp: Sprite, zb, zl, fl, body: Mat, band: Mat, bglow):
    """v0: ㄱ자 실험동 두 덩어리 안쪽 앞 모서리를 통유리 아트리움이 채운다 (층마다 푸른 화단 난간).
    지붕에 관측 돔·접시·배기구·기상 기둥."""
    nl = 8
    ax0, ay0, ax1, ay1 = -3.8, -3.8, 3.4, 0.9           # 뒤 동 (x 방향)
    bx0, by0, bx1, by1 = -3.8, 0.9, 0.9, 3.4            # 앞 왼 동
    zt = zl + nl * fl
    _lobby(sp, ax0 + 0.4, ay0 + 0.4, ax1 - 0.4, ay1, zb, zl - zb, band, bglow, 1)
    _lab_block(sp, ax0, ay0, ax1, ay1, zl, nl, fl, body, band, bglow, seed=2, faces=("+x", "-y", "-x"))
    fa = _faces4(ax0, ay0, zl, ax1 - ax0, ay1 - ay0, nl * fl)["+y"]
    _facade(sp, (fa[0], mul(fa[1], (ax1 - bx1) / (ax1 - ax0)), fa[2]), nl, fl, 2, body, sill=0.95, head=2.85, pier=0.12,
            margin=0.2, reveal=None, glow=LAB_LIGHT, glass=LAB_GLASS, frame_col="#c3ccd4", seed=9, dark=0.3, lit=0.7)
    _lobby(sp, bx0 + 0.4, by0, bx1, by1 - 0.4, zb, zl - zb, band, bglow, 2)
    _lab_block(sp, bx0, by0, bx1, by1, zl, nl, fl, body, band, bglow, seed=5, faces=("+y", "+x", "-x"))
    # 지붕 (뒤에서 앞으로): 배기구 → 관측 돔 → 공조 상자 → 접시 → 기상 기둥
    _stacks(sp, ax0 + 0.8, ay0 + 0.8, zt, 3, 0.8, "#9B7AD6")
    _obs_dome(sp, (-1.2, -1.6), 1.45, zt)
    sp.box(1.2, -3.2, zt, 1.6, 1.2, 0.7, STEEL, top=DARK)
    sp.cyl((-2.3, 2.3, zt), (-2.3, 2.3, zt + 0.6), 0.2, STEEL)
    _dish(sp, (-2.3, 2.3, zt + 1.3), norm((0.3, 0.75, 0.6)), 0.95)
    _weather_mast(sp, 2.6, -0.2, zt, 2.4)
    # 아트리움 (앞 오른 모서리): 층 바닥판과 화단 난간 → 나무 → 통유리 두 면 + 유리 지붕 (밤에 빛난다)
    gx0, gy0, gx1, gy1 = bx1, ay1, ax1, by1
    for k in range(0, nl, 2):
        z = zl + k * fl
        sp.box(gx0, gy0, z - 0.2, gx1 - gx0, 0.9, 0.2, PANEL)
        sp.box(gx0, gy0 + 0.9, z - 0.2, 0.9, gy1 - gy0 - 0.9, 0.2, PANEL)
        sp.box(gx0 + 0.9, gy0 + 0.72, z, gx1 - gx0 - 0.9, 0.18, 0.32, Mat("#5E8C4A"))
        sp.box(gx0 + 0.72, gy0 + 0.9, z, 0.18, gy1 - gy0 - 0.9, 0.32, Mat("#6DAE57"))
    sp.tree((gx0 + 1.5, gy0 + 1.5, zb), 3.4, 1.0, LEAF)
    _shrub(sp, gx1 - 0.6, gy1 - 0.6, zb, 0.5, GREEN)
    zt2 = zt - 0.3
    front = [(gx1, gy1, zb), (gx0, gy1, zb), (gx0, gy1, zt2), (gx1, gy1, zt2)]
    side = [(gx1, gy0, zb), (gx1, gy1, zb), (gx1, gy1, zt2), (gx1, gy0, zt2)]
    _glass_pane(sp, front, color="#bcd8ee", alpha=0.26)
    _glass_pane(sp, side, color="#bcd8ee", alpha=0.26)
    _glass_pane(sp, [(gx0, gy0, zt2), (gx1, gy0, zt2), (gx1, gy1, zt2), (gx0, gy1, zt2)], color="#bcd8ee", alpha=0.3)
    sp.light_poly(_orient([add(p, (0, 0.02, 0)) for p in front], (0, 1, 0)), WARM_WINDOW, 0.25)
    sp.light_poly(_orient([add(p, (0.02, 0, 0)) for p in side], (1, 0, 0)), WARM_WINDOW, 0.2)
    for fr in (((gx1, gy1, zb), (gx0 - gx1, 0, 0), (0, 0, zt2 - zb)), ((gx1, gy0, zb), (0, gy1 - gy0, 0), (0, 0, zt2 - zb))):
        sp.panel_grid(fr[0], fr[1], fr[2], 3, nl + 1, "#e6ebf0", 0.6, 0.9)
    sp.polyline3([(gx0, gy1, zt2), (gx1, gy1, zt2), (gx1, gy0, zt2)], "#e6ebf0", 0.08)
    sp.line((gx1, gy1, zb), (gx1, gy1, zt2), 0.1, "#e6ebf0")
    sp.glow((gx0 + 1.2, gy0 + 1.2, zl + 6.0), 40, WARM_WINDOW, 0.25)
    # 정문 차양 (아트리움 +y 면)
    sp.box(gx0 + 0.4, gy1, zb + 2.6, 1.6, 0.9, 0.16, PANEL, top=Mat("#C9CED3", 0.2))
    _lit_decal(sp, ((gx0 + 2.0, gy1 + 0.9, zb + 2.6), (-1.6, 0, 0), (0, 0, 0.16)), 0.0, 0.0, 1.0, 1.0, band, bglow,
               0.9, 0.01)
    sp.lamp((gx0 + 1.2, gy1 + 0.6, zb + 2.5), WARM_WINDOW, 9)


def _rt_twin(sp: Sprite, zb, zl, fl, body: Mat, band: Mat, bglow):
    """v1: 틈을 두고 선 두 동 (왼쪽이 한 층 높다)을 색 테를 두른 유리 하늘 다리 셋이 잇는다. 지붕에 접시와 관측 돔."""
    wx0, wx1, ex0, ex1, y0, y1 = -4.2, -1.0, 1.0, 4.2, -3.7, 3.4
    nw, ne = 8, 7
    ztw, zte = zl + nw * fl, zl + ne * fl
    e_hull = _screen_hull(_box_pts(ex0, y0, zb, ex1, y1, zte + 1.0))
    _lobby(sp, wx0 + 0.3, y0 + 0.3, wx1, y1 - 0.3, zb, zl - zb, band, bglow, 3)
    _lab_block(sp, wx0, y0, wx1, y1, zl, nw, fl, body, band, bglow, seed=3, hide={"+x": e_hull})
    # 틈의 1층 유리 아트리움과 하늘 다리
    sp.box(wx1, y0 + 1.0, zb, ex0 - wx1, y1 - y0 - 2.0, zl - zb - 0.3, Mat("#3B5A6E", 0.85), top=SILVER)
    gf = _faces4(wx1, y0 + 1.0, zb, ex0 - wx1, y1 - y0 - 2.0, zl - zb - 0.3)["+y"]
    _facade(sp, gf, 1, zl - zb - 0.3, 2, PANEL, sill=0.1, head=zl - zb - 0.6, pier=0.12, margin=0.05, reveal=None,
            glow=WARM_WINDOW, glass=Mat("#3B5A6E", 0.85), frame_col="#e6e8ea", seed=1, dark=0.0, lit=0.85)
    for k in (1, 3, 5):
        _sky_bridge(sp, wx1, ex0, y1 - 2.4, y1 - 0.5, zl + k * fl + 0.6, 2.3, frame=band)
    _lobby(sp, ex0, y0 + 0.3, ex1 - 0.3, y1 - 0.3, zb, zl - zb, band, bglow, 4)
    _lab_block(sp, ex0, y0, ex1, y1, zl, ne, fl, body, band, bglow, seed=8)
    # 왼 동 지붕: 큰 접시 + 배기구 + 기상 기둥 / 오른 동 지붕: 관측 돔 + 공조 상자
    _stacks(sp, wx0 + 0.7, y0 + 0.9, ztw, 2, 0.9, "#9B7AD6")
    _weather_mast(sp, -2.0, -2.7, ztw, 2.2)
    sp.cyl((-2.6, 1.0, ztw), (-2.6, 1.0, ztw + 0.9), 0.35, STEEL)
    _dish(sp, (-2.6, 1.0, ztw + 1.75), norm((0.35, 0.7, 0.62)), 1.3)
    _obs_dome(sp, (2.6, -1.2), 1.35, zte)
    sp.box(1.7, 1.4, zte, 1.8, 1.2, 0.7, STEEL, top=DARK)
    sp.lamp((ex1 - 0.3, y1 - 0.3, zte + 0.3), RED_LIGHT, 6)


def _rt_round(sp: Sprite, zb, zl, fl, body: Mat, band: Mat, bglow):
    """v2: 둥근 실험 탑. 층마다 둘레 띠창 (밤에 빛난다), 세로 지느러미, 청록 띠, 꼭대기 큰 관측 돔과 접시."""
    R, nl = 3.55, 7
    zt = zl + nl * fl
    # 로비 (넓은 유리 원통)
    sp.cyl((0, 0, zb), (0, 0, zl), R + 0.5, Mat("#3B5A6E", 0.85), cap_mat=SILVER)
    for k in range(16):
        a = 360 * k / 16 + 11.25
        sp.window(Sprite.cyl_patch((0, 0, zb), (0, 0, zl), R + 0.5, 0.04, 0.82, a - 9.5, a + 9.5), WARM_WINDOW,
                  frame="#e6e8ea", glass=Mat("#3B5A6E", 0.85), light_alpha=0.85)
    cyl_ring(sp, (0, 0, zb), (0, 0, zl), R + 0.5, 0.86, 0.97, band, bglow, 0.8)
    # 실험실 원통: 몸통 → 층마다 띠창 → 세로 지느러미 → 꼭대기 띠
    p0, p1 = (0, 0, zl), (0, 0, zt)
    sp.cyl(p0, p1, R, body, cap_mat=SILVER)
    for k in range(nl):
        sil = sp.cyl(add(p0, (0, 0, k * fl + 0.95)), add(p0, (0, 0, k * fl + 2.95)), R + 0.02, LAB_GLASS, caps=False,
                     edge=False)
        al = 0.7 if k % 3 != 1 else 0.4
        sp.mark_light(LAB_LIGHT, al)
        sp.poly2(sil, LAB_LIGHT, None, 0, al * 0.85, layer="light")
    for k in range(18):
        t = 2 * math.pi * (k + 0.5) / 18
        d = (math.cos(t), math.sin(t), 0.0)
        q0, q1 = (d[0] * (R + 0.05), d[1] * (R + 0.05), zl), (d[0] * (R + 0.05), d[1] * (R + 0.05), zt)
        if dot(d, VIEW) > 0.05:
            sp.line(q0, q1, 0.09, "#e8e9e6")
        else:
            sp._rec(("line", [q0, q1], 0.09, "#e8e9e6", False))
    cyl_ring(sp, p0, p1, R, 1 - 0.55 / (zt - zl), 1 - 0.2 / (zt - zl), band, bglow, 0.8)
    # 지붕: 난간 테 → 배기구 → 큰 관측 돔 → 접시
    sp.cyl((0, 0, zt), (0, 0, zt + 0.35), R + 0.1, Mat("#E2DACB"), cap_mat=ROOF)
    zr = zt + 0.35
    _stacks(sp, -2.4, -1.2, zr, 2, 0.8, "#3FB8AF")
    _obs_dome(sp, (-0.3, -0.3), 2.2, zr, body=body, face=(1.0, 0.6))
    sp.cyl((2.2, 1.3, zr), (2.2, 1.3, zr + 0.5), 0.18, STEEL)
    _dish(sp, (2.2, 1.3, zr + 1.1), norm((0.5, 0.65, 0.6)), 0.75)


def _rt_stepped(sp: Sprite, zb, zl, fl, body: Mat, band: Mat, bglow):
    """v3: 앞(+x·+y)으로 두 번 물러서는 실험동. 물러선 마당마다 앞 모서리에 접시, 꼭대기에 관측 돔."""
    blocks = ((-3.9, -3.9, 3.9, 3.9, 2), (-3.9, -3.9, 2.5, 2.5, 3), (-3.9, -3.9, 1.0, 1.0, 3))
    _lobby(sp, -3.5, -3.5, 3.9, 3.9, zb, zl - zb, band, bglow, 5)
    z = zl
    tops = []
    for i, (x0, y0, x1, y1, n) in enumerate(blocks):
        _lab_block(sp, x0, y0, x1, y1, z, n, fl, body, band, bglow, seed=6 + i)
        z += n * fl
        tops.append(z)
    # 물러선 마당 (위 덩어리보다 앞이라 나중에): 공조 상자 → 접시 → 난간
    for i in (0, 1):
        x0, y0, x1, y1, _ = blocks[i]
        zt = tops[i]
        sp.box(x0 + 0.5, y1 - 0.85, zt, 1.2, 0.6, 0.5, STEEL, top=DARK)
        dx, dy = x1 - 0.75, y1 - 0.75
        sp.cyl((dx, dy, zt), (dx, dy, zt + 0.55), 0.2, STEEL)
        _dish(sp, (dx, dy, zt + 1.25), norm((0.4, 0.7, 0.62)), 0.75)
        _rail(sp, [(x0 + 0.05, y1 - 0.05), (x1 - 0.05, y1 - 0.05), (x1 - 0.05, y0 + 0.05)], zt, 0.8, 0.12)
    zt = tops[2]
    _stacks(sp, -3.3, -3.3, zt, 2, 0.8, "#E07B39")
    _obs_dome(sp, (-1.4, -1.4), 1.3, zt)
    _weather_mast(sp, 0.4, -3.2, zt, 2.0)


def _rt_cantilever(sp: Sprite, zb, zl, fl, body: Mat, band: Mat, bglow):
    """v4: 가는 탑 위에 사방으로 내민 세 층짜리 관측층, 탑 모서리의 청록 지느러미, 옥상의 큰 접시."""
    x0, y0, x1, y1, nl = -3.1, -3.1, 3.1, 3.1, 5
    _lobby(sp, x0 + 0.4, y0 + 0.4, x1 - 0.4, y1 - 0.4, zb, zl - zb, band, bglow, 6)
    for (cx, cy) in ((x1 - 0.2, y1 - 0.2), (x0 + 0.2, y1 - 0.2), (x1 - 0.2, y0 + 0.2)):
        sp.cyl((cx, cy, zb), (cx, cy, zl), 0.22, body, edge=False)
    _lab_block(sp, x0, y0, x1, y1, zl, nl, fl, body, band, bglow, seed=12)
    z = zl + nl * fl
    for (cx, cy) in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
        sp.box(cx - 0.15, cy - 0.15, zl, 0.3, 0.3, nl * fl, band, top=band)
    # 내민 관측층: 아래 판 (밑면에 등) → 세 층 띠창 → 처마 띠
    c0, c1 = -4.2, 4.2
    sp.box(c0, c0, z, c1 - c0, c1 - c0, 0.5, PANEL, top=SILVER)
    for (lx, ly) in ((c1 - 0.5, c1 - 0.5), (c0 + 0.5, c1 - 0.5), (c1 - 0.5, c0 + 0.5)):
        sp.lamp((lx, ly, z - 0.1), LAB_LIGHT, 8)
    _lab_block(sp, c0 + 0.1, c0 + 0.1, c1 - 0.1, c1 - 0.1, z + 0.5, 3, fl, body, band, bglow, seed=14, cell=1.0)
    zt = z + 0.5 + 3 * fl
    sp.box(c0, c0, zt, c1 - c0, c1 - c0, 0.4, Mat("#E2DACB"), top=ROOF)
    for fr in _faces4(c0, c0, zt, c1 - c0, c1 - c0, 0.4).values():
        _lit_decal(sp, fr, 0.0, 0.2, 1.0, 0.8, band, bglow, 0.8)
    zr = zt + 0.4
    _stacks(sp, -3.4, -3.4, zr, 3, 0.8, "#3FB8AF")
    sp.cyl((0.4, 0.4, zr), (0.4, 0.4, zr + 0.9), 0.4, STEEL)
    _dish(sp, (0.4, 0.4, zr + 1.8), norm((0.35, 0.6, 0.72)), 1.55)
    _weather_mast(sp, 3.2, -3.2, zr, 2.0)
