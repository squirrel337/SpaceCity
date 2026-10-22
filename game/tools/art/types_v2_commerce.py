"""상업·관광 묶음 (v2) — 은행·증권거래소·보험회관·교역소·보세 창고·시장·호텔·박물관·전망 타워 9종.

종류마다 함수 하나 fn(sp, v)가 같은 기능의 다섯 모양(v = 0~4)을 그린다. v0이 대표 모양이다.
달·화성의 여압 건물이지만 작게 보여도 시민·상업 건물로 읽히도록 열주·간판·유리·차양·전시물을 앞세운다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다. 뒤(x+y가 작은 쪽)에서 앞 순서로 그린다.
"""
from __future__ import annotations

import math

from types_common import *  # noqa: F401,F403

# ── 재질 ──────────────────────────────────────────────────────────────
STONE = Mat("#D5CAB6")               # 소결 석재 (밝은 트래버틴 빛)
STONE_TOP = Mat("#BFB39E")
PLINTH = Mat("#A2967F")              # 기단·계단
PLINTH_TOP = Mat("#B6AA93")
MARBLE = Mat("#EFEAE0", 0.12)        # 기둥
VAULT = Mat("#5A606A", 0.35)         # 금고 (두꺼운 강철)
VAULT_TOP = Mat("#70777F", 0.3)
BRASS = Mat("#CFA247", 0.6)          # 금고 문·표장·간판
BRONZE = Mat("#7A5C36", 0.4)         # 청동 문
PATINA = Mat("#6FA391", 0.15)        # 녹청 지붕
ROOF_GLASS = Mat("#36536B", 0.85)    # 지붕 유리 (낮)
BLUE_GLASS = Mat("#2F5878", 0.85)    # 푸른 커튼월
PANEL = Mat("#DCDDD8", 0.1)          # 흰 외장 패널
TICKER_BG = Mat("#15191F", 0.4)      # 시세 띠 바탕
NAVY = Mat("#2D4A7A", 0.2)
MAROON = Mat("#8E3B3B", 0.1)

GOLD_LIGHT = "#FFD27A"               # 간판 불빛
COOL_WHITE = "#E3F1FF"               # 차가운 흰 불빛
OFFICE = "#CFE2F4"                   # 사무실 창 불빛 (밤)
TICK_GREEN = "#6CF29A"
TICK_RED = "#FF5A4A"
BEACON = "#FF7A2E"


# ── 공용 도우미 ───────────────────────────────────────────────────────

def _orient(pts, outward):
    """다각형 꼭짓점이 outward 쪽에서 반시계가 되게 한다."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return pts if dot(n, outward) >= 0 else list(reversed(pts))


def _fp(frame, u, v):
    o, e1, e2 = frame
    return add(add(o, mul(e1, u)), mul(e2, v))


def _faces4(x, y, z, w, d, h):
    """상자의 옆면 넷 (원점, 가로, 세로) — 가로 × 세로 = 바깥 법선. 2D에는 +x·+y만 보인다."""
    return {"+y": ((x + w, y + d, z), (-w, 0.0, 0.0), (0.0, 0.0, h)),
            "+x": ((x + w, y, z), (0.0, d, 0.0), (0.0, 0.0, h)),
            "-y": ((x, y, z), (w, 0.0, 0.0), (0.0, 0.0, h)),
            "-x": ((x, y + d, z), (0.0, -d, 0.0), (0.0, 0.0, h))}


def _nrm(frame):
    return norm(cross(frame[1], frame[2]))


def _decal(sp, frame, u0, v0, u1, v1, mat, lift=0.0, edge=False):
    """면 위의 색 판 (띠·패널·문)."""
    n = _nrm(frame)
    pts = [add(p, mul(n, lift)) for p in sp.on_face(*frame, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=edge, ao=0)
    return pts


def _lit(sp, pts, mat, glow, alpha=0.85):
    """밤에 빛나는 면 (간판·시세 띠). 3D는 면이 스스로 빛나고, 2D 밤 그림에는 보이는 면만 칠한다."""
    n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    sp.mark_light(glow, alpha)
    if dot(n, VIEW) > 1e-6:
        sp.poly2([PV(p) for p in pts], glow, None, 0, alpha, layer="light")
    return pts


def _lit_decal(sp, frame, u0, v0, u1, v1, mat, glow, alpha=0.85, lift=0.02):
    n = _nrm(frame)
    return _lit(sp, [add(p, mul(n, lift)) for p in sp.on_face(*frame, u0, v0, u1, v1)], mat, glow, alpha)


def _edge(sp, a, b, color, w=0.05, show=True, opacity=1.0):
    """3D에는 늘 적고 2D에는 show일 때만 긋는 선 (뒤 모서리가 앞면 위에 그려지지 않게)."""
    if show:
        sp.line(a, b, w, color, opacity)
    else:
        sp._rec(("line", [a, b], w, color, False))


def _grid_windows(sp, frame, nu, nv, u0=0.08, u1=0.92, v0=0.12, v1=0.88, gu=0.22, gv=0.3,
                  glow=WARM_WINDOW, glass=GLASS, frame_col="#2a2f36", seed=0, dark=0.0, alpha=0.95, dim=0.3):
    """면에 nu × nv 창 격자. gu·gv: 칸 사이 틈 비율, dark: 불 꺼진 창 비율 (alpha: 켜진 창, dim: 꺼진 창 세기)."""
    cu, cv = (u1 - u0) / nu, (v1 - v0) / nv
    for j in range(nv):
        for i in range(nu):
            a0 = u0 + i * cu + cu * gu / 2
            b0 = v0 + j * cv + cv * gv / 2
            on = ((i * 7 + j * 11 + seed * 5) % 10) >= dark * 10
            sp.window(sp.on_face(*frame, a0, b0, a0 + cu * (1 - gu), b0 + cv * (1 - gv)), glow, frame=frame_col,
                      glass=glass, light_alpha=alpha if on else dim)


def _lamp_post(sp, x, y, h=2.4, color=WARM_WINDOW, r=11, z=0.0):
    sp.line((x, y, z), (x, y, z + h), 0.09, "#5c626b")
    sp.box(x - 0.14, y - 0.14, z + h - 0.05, 0.28, 0.28, 0.08, DARK)
    sp.lamp((x, y, z + h + 0.1), color, r)


def _column(sp, x, y, z0, z1, r=0.3, mat=MARBLE):
    """대좌·기둥몸·주두가 있는 둥근 기둥."""
    b = r * 1.4
    sp.box(x - b, y - b, z0, 2 * b, 2 * b, 0.2, mat)
    sp.cyl((x, y, z0 + 0.2), (x, y, z1 - 0.24), r, mat, caps=False, bands=[0.04, 0.96], band_color="#c9c2b4")
    sp.box(x - b, y - b, z1 - 0.24, 2 * b, 2 * b, 0.24, mat)


def _steps_y(sp, x0, x1, y0, depth, h, n=3, mat=PLINTH, top=PLINTH_TOP):
    """y0에서 +y 쪽으로 내려가는 계단 (맨 위 높이 h, n단)."""
    dd = depth / n
    for i in range(n):
        sp.box(x0, y0 + i * dd, 0, x1 - x0, dd, h * (n - i) / (n + 1), mat, top=top)


def _glass_lantern(sp, x0, y0, x1, y1, z0, z1, apex, n=(3, 2), glow=WARM_WINDOW):
    """유리 아트리움 지붕등: 틀 → 유리 벽 넷 → 유리 피라미드 지붕 (밤에 빛난다)."""
    sp.box(x0 - 0.15, y0 - 0.15, z0, x1 - x0 + 0.3, y1 - y0 + 0.3, 0.2, STEEL, top=DARK)
    za = z0 + 0.2
    sp.box(x0, y0, za, x1 - x0, y1 - y0, z1 - za, Mat("#2E4458", 0.8), top=DARK)
    for key, fr in _faces4(x0, y0, za, x1 - x0, y1 - y0, z1 - za).items():
        _grid_windows(sp, fr, n[0] if key in ("+y", "-y") else n[1], 1, 0.03, 0.97, 0.06, 0.94, gu=0.1, gv=0.0,
                      glow=glow, glass=ROOF_GLASS, frame_col="#c9ccd1")
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    c = [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    top = (cx, cy, apex)
    vis = []
    for i in range(4):
        tri = [c[i], c[(i + 1) % 4], top]
        vis.append(dot(norm(cross(sub(tri[1], tri[0]), sub(tri[2], tri[0]))), VIEW) > 0)
        _lit(sp, tri, ROOF_GLASS, glow, 0.45)
    for i in range(4):
        _edge(sp, c[i], top, "#c9ccd1", 0.06, vis[i] or vis[i - 1])
        m = mul(add(c[i], c[(i + 1) % 4]), 0.5)
        _edge(sp, m, top, "#c9ccd1", 0.04, vis[i], 0.8)
    sp.line(top, add(top, (0, 0, 0.35)), 0.06, "#C9A04A")
    sp.sphere(add(top, (0, 0, 0.4)), 0.12, BRASS)
    sp.glow((cx, cy, (z1 + apex) / 2), 26, glow, 0.35)


def _vault_door(sp, c, n, r):
    """금고의 둥근 문: 테 → 문판 → 놋쇠 고리·바퀴살·손잡이."""
    sp.disc(c, n, r * 1.15, CHAR)
    sp.disc(add(c, mul(n, 0.03)), n, r, Mat("#A3ABB4", 0.55))
    sp.ring3(add(c, mul(n, 0.05)), r * 0.8, "#C9A04A", 0.09, normal=n, front_only=False)
    u, w = basis(n)
    hub = add(c, mul(n, 0.07))
    for k in range(3):
        a = math.pi * k / 3
        d = add(mul(u, math.cos(a)), mul(w, math.sin(a)))
        sp.line(add(hub, mul(d, -r * 0.62)), add(hub, mul(d, r * 0.62)), 0.08, "#C9A04A")
    sp.disc(add(c, mul(n, 0.09)), n, r * 0.22, BRASS)
    # 경첩 두 개 (문 옆)
    for s in (-0.55, 0.55):
        p = add(add(c, mul(w, s * r)), mul(u, r * 1.05))
        a, b = (0.06, 0.12) if abs(n[0]) > 0.5 else (0.12, 0.06)
        sp.box(p[0] - a, p[1] - b, p[2] - 0.12, 2 * a, 2 * b, 0.24, DARK)


def _letters(sp, frame, u0, u1, v0, v1, n=7, mat=CHAR, lift=0.03):
    """간판 위의 글자 (작은 네모 줄)."""
    step = (u1 - u0) / n
    for i in range(n):
        a = u0 + i * step + step * 0.18
        _decal(sp, frame, a, v0, a + step * 0.64, v1, mat, lift)


def _emblem_disc(sp, c, n, r, mat=BRASS, mark="#7A5C36"):
    """둥근 표장: 놋쇠 원판 + 고리 + 가운데 별."""
    sp.disc(c, n, r, mat, two_sided=False)
    sp.ring3(add(c, mul(n, 0.02)), r * 0.78, mark, 0.06, normal=n, front_only=False)
    u, w = basis(n)
    star = []
    for k in range(10):
        a = math.pi / 2 + math.pi * k / 5
        rr = r * (0.5 if k % 2 == 0 else 0.22)
        star.append(add(add(c, mul(n, 0.03)), add(mul(u, rr * math.cos(a)), mul(w, rr * math.sin(a)))))
    sp.face(_orient(star, n), Mat(mark, 0.3), normal=n, edge=False, ao=0)


GRANITE = Mat("#7F7B75")             # 광장 바닥 (짙은 소결석)
GRANITE_TOP = Mat("#96918A")
TICK_DAY = {TICK_GREEN: Mat("#2FA35E", 0.5), TICK_RED: Mat("#C2473B", 0.5), AMBER: Mat("#D0922F", 0.5),
            CYAN_LIGHT: Mat("#2F9C95", 0.5)}


def _front_pts(cx, cy, rx, ry, z, k=24, margin=0.0):
    """수평 타원의 앞(카메라 쪽) 반 둘레."""
    a0, a1 = math.radians(-45 - margin), math.radians(135 + margin)
    return [(cx + rx * math.cos(a0 + (a1 - a0) * i / k), cy + ry * math.sin(a0 + (a1 - a0) * i / k), z)
            for i in range(k + 1)]


def _glass_dome(sp, c, r, h, glow=WARM_WINDOW, ribs=10, mat=ROOF_GLASS, rib_col="#c9ccd1", alpha=0.35, shell=True):
    """유리 돔 + 갈비. 그림(2D)은 짙은 유리, 3D는 비치는 유리 껍질과 밤에 빛나는 안쪽 바닥 (shell=False면 불투명)."""
    if shell:
        with sp._nest():
            sil = sp.dome(c, r, h, mat)
        sp.glass_shell(c, r, r, h, c[2], color="#bcd8ee", alpha=0.3)
        sp._rec(("lpoly", [(c[0] + r * 0.92 * math.cos(2 * math.pi * k / 24), c[1] + r * 0.92 * math.sin(2 * math.pi * k / 24),
                            c[2] + 0.04) for k in range(24)], glow, 0.55))
    else:
        sil = sp.dome(c, r, h, mat)
    for i in range(ribs):
        th = 2 * math.pi * i / ribs
        pts = [(c[0] + r * 1.005 * math.cos(ph) * math.cos(th), c[1] + r * 1.005 * math.cos(ph) * math.sin(th),
                c[2] + h * 1.005 * math.sin(ph)) for ph in [k * math.pi / 20 for k in range(11)]]
        if dot((math.cos(th), math.sin(th), 0.0), VIEW) < -0.15:
            sp._rec(("line", pts, 0.05, rib_col, False))          # 뒤쪽 갈비는 3D에만
        else:
            sp.polyline3(pts, rib_col, 0.05, 0.8)
    for t in (0.4, 0.75):
        k = math.sqrt(1 - t * t) * 1.005
        sp.ring3((c[0], c[1], c[2] + h * t), r * k, rib_col, 0.05, opacity=0.7)
    sp.poly2(sil, glow, None, 0, alpha, layer="light")
    sp.glow(add(c, (0, 0, h * 0.45)), r * S * 1.1, glow, 0.35)
    return sil


def _dish(sp, c, n, r, mat=WHITE):
    """접시 안테나 (지구와 잇는 고리)."""
    sp.disc(c, n, r, mat, back=STEEL, seg=40)
    sp.ring3(c, r, "#b9b2a5", 0.07, normal=n, front_only=False)
    feed = add(c, mul(n, r * 0.62))
    u, w = basis(n)
    for a in (0, 120, 240):
        rim = add(c, add(mul(u, r * 0.85 * math.cos(math.radians(a))), mul(w, r * 0.85 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.045, "#8a9099")
    sp.sphere(feed, max(0.1, r * 0.08), GOLD)


def _mast(sp, base, h, w=0.45, color="#9aa1aa", side=(1, -1, 0)):
    """격자 안테나 탑 + 꼭대기 붉은 표시등."""
    top = add(base, (0, 0, h))
    sp.truss(base, top, w, color, 0.05, max(3, int(h / 0.8)), side=side)
    sp.line(top, add(top, (0, 0, 0.9)), 0.05, color)
    sp.lamp(add(top, (0, 0, 1.0)), "#ff5a3c", 6)


def _glass_block(sp, x0, y0, z0, x1, y1, z1, nx, ny, nv, glow=OFFICE, glass=BLUE_GLASS, frame_col="#c3ccd4",
                 body=Mat("#22384C", 0.7), top=None, seed=0, dark=0.35, fins=PANEL, alpha=0.72):
    """유리 커튼월 상자: 몸통 + 네 면의 창 격자 + 모서리 흰 띠 (뒤 두 면은 3D에만 남는다)."""
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, z1 - z0, body, top=top or Mat("#9AA3AC", 0.3))
    for key, fr in _faces4(x0, y0, z0, x1 - x0, y1 - y0, z1 - z0).items():
        _grid_windows(sp, fr, nx if key in ("+y", "-y") else ny, nv, 0.0, 1.0, 0.0, 1.0, gu=0.07, gv=0.1, glow=glow,
                      glass=glass, frame_col=frame_col, seed=seed + len(key) * 3 + (key == "+x"), dark=dark,
                      alpha=alpha, dim=0.12)
        if fins:
            L = length(fr[1])
            _decal(sp, fr, 0.0, 0.0, 0.18 / L, 1.0, fins, 0.04)
            _decal(sp, fr, 1 - 0.18 / L, 0.0, 1.0, 1.0, fins, 0.04)


def _ticker(sp, frame, colors, seed=0, v0=0.2, v1=0.8, lift=0.03):
    """시세 띠: 길이가 다른 빛 조각이 줄지어 흐른다 (낮에도 색이 보인다)."""
    L = length(frame[1])
    u, k = 0.15 / L, seed
    while u < 1 - 0.35 / L:
        u1 = min(1 - 0.15 / L, u + (0.5, 1.1, 0.8, 1.6, 0.6, 1.3)[k % 6] / L)
        col = colors[k % len(colors)]
        _lit_decal(sp, frame, u, v0, u1, v1, TICK_DAY[col], col, 0.95, lift)
        u = u1 + 0.22 / L
        k += 1


def _crown(sp, cx, cy, a, z, steps=2, apex=0.9, mat=BRASS, glow=GOLD_LIGHT):
    """계단식 금빛 왕관 + 작은 피라미드 (밤에 빛난다). 꼭대기 높이를 돌려준다."""
    for i in range(steps):
        s = a * (1 - 0.2 * i)
        sp.box(cx - s / 2, cy - s / 2, z, s, s, 0.4, mat)
        for fr in _faces4(cx - s / 2, cy - s / 2, z, s, s, 0.4).values():
            _lit_decal(sp, fr, 0.05, 0.3, 0.95, 0.7, Mat("#F2D58E", 0.5), glow, 0.8)
        z += 0.4
    s = a * (1 - 0.2 * steps)
    c = [(cx - s / 2, cy - s / 2, z), (cx + s / 2, cy - s / 2, z), (cx + s / 2, cy + s / 2, z), (cx - s / 2, cy + s / 2, z)]
    for i in range(4):
        _lit(sp, [c[i], c[(i + 1) % 4], (cx, cy, z + apex)], mat, glow, 0.45)
    return z + apex


# ═════════════════════════════════════════════════════════════════════
# 우주 은행
# ═════════════════════════════════════════════════════════════════════

@typed("space_bank", 12, 10, 9.0, "우주 은행", heights=[9.0, 8.6, 9.0, 8.4, 9.0])
def space_bank(sp: Sprite, v: int):
    """돌 기단과 계단, 열주 현관, 지붕 위 유리 아트리움, 창 없는 강철 금고동 (둥근 금고 문)."""
    side = v == 2                                     # 금고동을 본관 오른쪽 옆에 세운다 (문이 정면을 본다)
    sign, sign_glow = ((BRASS, GOLD_LIGHT), (Mat("#2F8F8A", 0.5), CYAN_LIGHT), (BRASS, GOLD_LIGHT),
                       (MAROON, "#FFB0A0"), (BRASS, GOLD_LIGHT))[v]
    wall = (STONE, PANEL, STONE, Mat("#CDBFA6"), STONE)[v]
    zp = 0.8                                          # 기단 높이
    hx0, hx1, hy0, hy1 = (-5.3, 2.0, -2.9, 2.2) if side else (-5.3, 4.0, -1.9, 2.2)
    hz = 4.2 if v == 3 else 4.6
    vx0, vx1, vy0, vy1 = (2.0, 5.5, -4.6, -0.2) if side else (0.8, 5.4, -4.5, -1.9)
    vz = (6.0, 5.4, 6.6, 6.8, 6.0)[v]
    px0, px1 = {1: (-4.4, 3.95), 2: (-5.0, 1.8), 3: (-5.2, 3.95)}.get(v, (-4.2, 3.95))
    sp.contact_shadow(0, 0, 6.4, 5.4, 0.45)
    sp.box(-5.7, -4.7, 0, 11.4, 8.5, zp, PLINTH, top=PLINTH_TOP)
    _steps_y(sp, px0 + 0.1, px1 - 0.1, 3.8, 0.9, zp)

    def vault():
        # 금고동: 창 없는 강철 덩어리, 가로 이음매, 둥근 문
        sp.box(vx0, vy0, zp, vx1 - vx0, vy1 - vy0, vz, VAULT, top=VAULT_TOP)
        vf = _faces4(vx0, vy0, zp, vx1 - vx0, vy1 - vy0, vz)
        for fr in (vf["+x"], vf["+y"]):
            sp.panel_grid(*fr, 1, 6, "#3d4249", 0.6, 0.8)
        if side:
            dc, dn = ((vx0 + vx1) / 2, vy1 + 0.03, zp + 2.3), (0, 1, 0)
        else:
            dc, dn = (vx1 + 0.03, (vy0 + vy1) / 2, zp + 2.3), (1, 0, 0)
        _vault_door(sp, dc, dn, 0.95)
        sp.lamp(add(dc, add(mul(dn, 0.1), (0, 0, 1.7))), "#ff5a3c", 7)
        if v == 1:                                        # 금고동 위 냉각 방열판 둘
            for k in range(2):
                o, e1, e2 = (vx0 + 0.5 + k * 2.1, vy0 + 1.3, zp + vz), (1.8, 0, 0), (0, 0, 1.0)
                sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
                sp.panel_grid(o, e1, e2, 5, 1, "#b9bec4", 0.5, 0.7)
        elif v == 3:
            antenna(sp, (vx1 - 0.6, vy0 + 0.5, zp + vz), 1.6)

    if not side:
        vault()
    # 본관
    sp.box(hx0, hy0, zp, hx1 - hx0, hy1 - hy0, hz, wall, top=STONE_TOP)
    f = Sprite.box_faces(hx0, hy0, zp, hx1 - hx0, hy1 - hy0, hz)
    zt = zp + hz
    W = hx1 - hx0
    ncol = (6, 8, 4, 8, 6)[v]
    cr = (0.3, 0.16, 0.42, 0.28, 0.3)[v]
    yc = 3.05
    xs = [px0 + 0.45 + (px1 - px0 - 0.9) * i / (ncol - 1) for i in range(ncol)]
    # 정면: 기둥 사이로 보이는 높은 창 (기둥에 가려지는 만큼 비켜 둔다), 가운데 칸은 청동 문
    shift = yc - hy1
    wv0, wv1 = (0.05, 0.95) if v == 1 else (0.12, 0.86)
    for i in range(ncol - 1):
        xm = (xs[i] + xs[i + 1]) / 2 - shift
        half = ((xs[i + 1] - xs[i]) - 2 * cr * 1.4 - 0.16) / 2
        u0, u1 = (hx1 - xm - half) / W, (hx1 - xm + half) / W
        if i == (ncol - 2) // 2:
            _decal(sp, f["left"], u0, 0.0, u1, 0.5, BRONZE, 0.03, edge=True)
            sp.window(sp.on_face(*f["left"], u0, 0.58, u1, wv1), WARM_WINDOW, frame="#d8d2c4")
        else:
            sp.window(sp.on_face(*f["left"], u0, wv0, u1, wv1), WARM_WINDOW, frame="#d8d2c4")
    if px0 - hx0 > 0.8:
        u = (hx1 - (hx0 + px0) / 2) / W
        sp.window(sp.on_face(*f["left"], u - 0.025, 0.2, u + 0.025, 0.8), WARM_WINDOW, frame="#d8d2c4")
    D = hy1 - hy0
    for y in ((0.3, 1.4) if side else ((-1.2, -0.1, 1.0) if v == 3 else (-0.9, 0.6))):
        u = (y - hy0) / D
        sp.window(sp.on_face(*f["right"], u - 0.26 / D, 0.2, u + 0.26 / D, 0.8), WARM_WINDOW, frame="#d8d2c4")
    hf = _faces4(hx0, hy0, zp, W, D, hz)
    _grid_windows(sp, hf["-x"], 2, 1, 0.2, 0.8, 0.2, 0.8, gu=0.6, gv=0.0, frame_col="#d8d2c4")
    # 처마 돌림띠
    sp.box(hx0 - 0.1, hy0, zt, W + (0.1 if side else 0.2), D + 0.1, 0.25, STONE_TOP)
    if side:
        vault()
    zr = zt + 0.25
    # 지붕 위 유리 아트리움 (빛나는 지붕등 · 유리 상자 · 유리 돔)
    if v in (0, 3, 4):
        lx0, lx1 = (-5.0, -2.0) if v == 4 else (-3.4, 0.6)
        _glass_lantern(sp, lx0, -1.4, lx1, 1.5, zr, zr + 1.25, (8.6, 0, 0, 8.0, 8.6)[v], n=(3 if v != 4 else 2, 2))
    elif v == 1:
        ax0, ay0, ax1, ay1 = -4.6, -1.5, -1.6, 1.6
        _glass_block(sp, ax0, ay0, zr, ax1, ay1, 8.6, 3, 3, 2, glow=WARM_WINDOW, glass=Mat("#4F7A99", 0.85),
                     frame_col="#e6e8ea", dark=0.0, fins=None)
        sp.glow((ax0 + 1.5, ay0 + 1.5, zr + 1.4), 24, WARM_WINDOW, 0.35)
    else:
        sp.cyl((-1.6, -0.4, zr), (-1.6, -0.4, zr + 0.4), 2.05, STEEL, cap_mat=DARK)
        _glass_dome(sp, (-1.6, -0.4, zr + 0.4), 1.9, 9.0 - zr - 0.55)
        sp.lamp((-1.6, -0.4, 9.05), GOLD_LIGHT, 6)
    # 열주 현관
    cmat = Mat("#4A4F57", 0.3) if v == 1 else MARBLE
    ze = zp + (3.8 if v == 3 else 4.2)
    for x in xs:
        if v == 1:
            sp.cyl((x, yc, zp), (x, yc, ze), cr, cmat, caps=False)
        else:
            _column(sp, x, yc, zp, ze, cr, cmat)
    # 처마도리 (간판 띠) 와 다락 또는 박공
    ey1 = 4.5 if v == 1 else 3.7
    eh = 0.4 if v == 1 else 0.75
    sp.box(px0, hy1, ze, px1 - px0, ey1 - hy1, eh, wall, top=STONE_TOP)
    ef = Sprite.box_faces(px0, hy1, ze, px1 - px0, ey1 - hy1, eh)
    if v == 1:
        _lit_decal(sp, ef["left"], 0.0, 0.25, 1.0, 0.75, sign, sign_glow, 0.9)
        _lit_decal(sp, ef["right"], 0.0, 0.25, 1.0, 0.75, sign, sign_glow, 0.9)
        for x in (px0 + 1.0, px1 - 1.0):
            sp.lamp((x, ey1 - 0.4, ze - 0.1), WARM_WINDOW, 9)
    else:
        _lit_decal(sp, ef["left"], 0.08, 0.28, 0.92, 0.72, sign, sign_glow, 0.8)
        _letters(sp, ef["left"], 0.25, 0.75, 0.38, 0.62, 7, Mat("#3a2c1a", 0.2), 0.04)
    xm = (px0 + px1) / 2
    if v == 4:
        za, zb = ze + eh, ze + eh + 1.5
        sp.face(_orient([(px1, ey1, za), (xm, ey1, zb), (px0, ey1, za)], (0, 1, 0)), wall, ao=0)
        sp.face(_orient([(px0, hy1, za), (xm, hy1, zb), (px1, hy1, za)], (0, -1, 0)), wall, ao=0)
        sp.face(_orient([(px0, hy1, za), (px0, ey1 + 0.1, za), (xm, ey1 + 0.1, zb), (xm, hy1, zb)], (-1.5, 0, 4)),
                PATINA, ao=0)
        sp.face(_orient([(xm, hy1, zb), (xm, ey1 + 0.1, zb), (px1, ey1 + 0.1, za), (px1, hy1, za)], (1.5, 0, 4)),
                PATINA, ao=0)
        _emblem_disc(sp, (xm, ey1 + 0.03, za + 0.55), (0, 1, 0), 0.42)
    elif v != 1:
        sp.box(px0 + 0.3, hy1, ze + eh, px1 - px0 - 0.6, ey1 - hy1 - 0.3, 0.45, STONE_TOP)
        _emblem_disc(sp, (xm, ey1 - 0.27, ze + eh + 0.23), (0, 1, 0), 0.3)
    # 앞 등과 덧붙이
    for x in (-5.15, 4.95):
        _lamp_post(sp, x, 4.35, 2.2, WARM_WINDOW, 11)
    if v == 3:                                        # 깃대 둘
        for x in (-3.0, 2.8):
            sp.line((x, 4.55, 0), (x, 4.55, 4.2), 0.06, "#c9ccd1")
            sp.face(_orient([(x, 4.55, 3.0), (x + 0.9, 4.55, 3.0), (x + 0.9, 4.55, 4.0), (x, 4.55, 4.0)], (0, 1, 0)),
                    MAROON, two_sided=True, ao=0)
    elif v == 4:                                      # 현금 인출기 부스
        sp.box(4.3, 0.8, zp, 1.0, 1.2, 1.9, PANEL, top=STEEL)
        af = Sprite.box_faces(4.3, 0.8, zp, 1.0, 1.2, 1.9)
        _lit_decal(sp, af["right"], 0.2, 0.45, 0.8, 0.75, Mat("#1b3560", 0.5), "#7FC8FF", 0.85)
        _decal(sp, af["right"], 0.0, 0.85, 1.0, 1.0, BRASS, 0.02)
    elif side:                                        # 금고동 앞 화단
        sp.box(3.9, 2.0, zp, 1.5, 1.5, 0.45, PLINTH, top=Mat("#5E8C4A"))
        sp.tree((4.65, 2.75, zp + 0.45), 1.6, 0.55)


# ═════════════════════════════════════════════════════════════════════
# 우주 증권거래소
# ═════════════════════════════════════════════════════════════════════

@typed("stock_exchange", 16, 12, 14.0, "우주 증권거래소", heights=[14.0, 13.4, 14.4, 13.7, 13.4])
def stock_exchange(sp: Sprite, v: int):
    """높은 유리 거래장을 시세 띠가 두르고, 지붕에는 탑과 금빛 왕관, 지구와 잇는 안테나 탑."""
    tick = ((TICK_GREEN, TICK_RED, AMBER), (AMBER, TICK_GREEN), (TICK_GREEN, TICK_RED),
            (TICK_RED, TICK_GREEN, AMBER, TICK_GREEN), (CYAN_LIGHT, AMBER))[v]
    x0, x1, y0, y1, z0 = -7.2, 6.4, -5.2, 3.8, 0.5
    tz0, tz1 = (4.4, 5.3) if v != 1 else (5.0, 5.9)
    zt = (8.9, 8.9, 8.9, 8.9, 8.4)[v]
    sp.contact_shadow(0, 0, 8.6, 6.6, 0.45)
    sp.box(-7.8, -5.8, 0, 15.6, 11.6, z0, GRANITE, top=GRANITE_TOP)
    # 아래층 유리벽 → 시세 띠 (조금 내민 띠) → 위층 유리벽
    _glass_block(sp, x0, y0, z0, x1, y1, tz0, 10, 7, 2 if v != 1 else 3, seed=v, dark=0.2)
    b = 0.2
    sp.box(x0 - b, y0 - b, tz0, x1 - x0 + 2 * b, y1 - y0 + 2 * b, tz1 - tz0, TICKER_BG, top=Mat("#8E959D", 0.3))
    for key, fr in _faces4(x0 - b, y0 - b, tz0, x1 - x0 + 2 * b, y1 - y0 + 2 * b, tz1 - tz0).items():
        _ticker(sp, fr, tick, seed=len(key) + v)
    ux0, ux1, uy0, uy1 = (x0 + 0.7, x1 - 1.6, y0 + 0.7, y1 - 1.6) if v == 1 else (x0, x1, y0, y1)
    nx, ny = (8, 5) if v == 1 else (10, 7)
    if v == 3:
        # 위층 +x 면은 커다란 시세 화면 (오르는 그래프)
        _glass_block(sp, ux0, uy0, tz1, ux1, uy1, zt, nx, ny, 2, seed=v + 3, dark=0.25)
        scr = Sprite.box_faces(ux0, uy0, tz1, ux1 - ux0, uy1 - uy0, zt - tz1)["right"]
        _decal(sp, scr, 0.08, 0.1, 0.92, 0.92, Mat("#1A1E25", 0.4), 0.06)
        _lit_decal(sp, scr, 0.1, 0.13, 0.9, 0.89, Mat("#0F2A3A", 0.6), "#1E4D6B", 0.6, 0.08)
        pts = [(0.12, 0.3), (0.25, 0.42), (0.36, 0.36), (0.5, 0.55), (0.62, 0.5), (0.75, 0.72), (0.88, 0.8)]
        line = [add(_fp(scr, a, c), (0.12, 0, 0)) for a, c in pts]
        sp.polyline3(line, TICK_GREEN, 0.12)
        sp.polyline3(line, TICK_GREEN, 0.12, 0.9, layer="light")
    else:
        _glass_block(sp, ux0, uy0, tz1, ux1, uy1, zt, nx, ny, 2, seed=v + 3, dark=0.25)
    # 정문: 내민 차양과 밝은 유리문
    fy = Sprite.box_faces(x0, y0, z0, x1 - x0, y1 - y0, tz0 - z0)["left"]
    W = x1 - x0
    dx0, dx1 = -2.6, 1.8
    _lit_decal(sp, fy, (x1 - dx1 + 0.6) / W, 0.0, (x1 - dx0 - 0.6) / W, 0.55, Mat("#5C7E99", 0.8), "#FFF3D6", 0.9, 0.05)
    sp.box(dx0, y1, 3.0, dx1 - dx0, 1.6, 0.3, PANEL, top=Mat("#C9CED3", 0.2))
    for x in (dx0 + 0.2, dx1 - 0.2):
        sp.line((x, y1 + 1.4, z0), (x, y1 + 1.4, 3.0), 0.1, "#9aa1aa")
    for x in (dx0 + 1.0, dx1 - 1.0):
        sp.lamp((x, y1 + 0.9, 2.92), "#FFF3D6", 10)
    # 지붕: 안테나 탑 (뒤) → 가운데 탑과 왕관 → 접시
    zr = zt
    masts = (((-6.2, -4.4, 4.2), (5.4, -4.3, 4.8)), ((-5.6, -3.8, 3.6), (3.6, -4.0, 4.4), (-6.0, 1.2, 3.0)),
             ((-6.2, -4.4, 4.6),), ((-6.2, -4.4, 4.2), (5.4, -4.3, 4.8)), ((5.4, -4.3, 5.0),))[v]
    for (mx, my, mh) in masts:
        _mast(sp, (mx, my, zr), mh)
    if v == 2:
        # 뒤 오른쪽 모서리의 더 높고 날씬한 탑 + 빛나는 고리 + 첨탑
        tx0, ty0, tx1, ty1, th = 1.0, -4.4, 4.6, -1.0, 13.0
    elif v == 4:
        tx0, ty0, tx1, ty1, th = -2.0, -3.0, 1.6, 0.6, 12.0
    else:
        tx0, ty0, tx1, ty1, th = -2.6, -3.6, 1.8, 0.8, (12.3, 11.8, 0, 12.0)[v]
    if v == 1:
        sp.box(tx0 - 0.3, ty0 - 0.3, zr, tx1 - tx0 + 0.6, ty1 - ty0 + 0.6, 0.3, STEEL, top=DARK)
        _glass_block(sp, tx0, ty0, zr + 0.3, tx1, ty1, th, 4, 4, 2, seed=7, dark=0.3)
        top = _crown(sp, (tx0 + tx1) / 2, (ty0 + ty1) / 2, 4.0, th, steps=1, apex=1.2)
    elif v == 2:
        _glass_block(sp, tx0, ty0, zr, tx1, ty1, th, 3, 3, 3, seed=5, dark=0.3)
        cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
        sp.cyl((cx, cy, th), (cx, cy, th + 0.5), 1.5, STEEL, cap_mat=DARK)
        cyl_ring(sp, (cx, cy, th), (cx, cy, th + 0.5), 1.5, 0.25, 0.75, Mat("#F2D58E", 0.5), GOLD_LIGHT, 0.85)
        sp.frustum((cx, cy, th + 0.5), (cx, cy, th + 1.4), 1.1, 0.15, BRASS)
        top = th + 1.4
        sp.line((cx, cy, top), (cx, cy, top + 1.6), 0.08, "#c9ccd1")
        sp.lamp((cx, cy, top + 1.7), "#ff5a3c", 6)
    elif v == 4:
        # 둥근 시계탑 같은 원통 + 유리 돔 왕관
        cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
        sp.cyl((cx, cy, zr), (cx, cy, th), 1.8, PANEL, cap_mat=STEEL, bands=[0.5])
        cyl_windows(sp, (cx, cy, zr), (cx, cy, th), 1.8, 0.15, 0.4, toward=(1, 1, 0), n=4, spread=30, width=18,
                    glow=COOL_WHITE, glass=BLUE_GLASS)
        cyl_windows(sp, (cx, cy, zr), (cx, cy, th), 1.8, 0.6, 0.85, toward=(1, 1, 0), n=4, spread=30, width=18,
                    glow=COOL_WHITE, glass=BLUE_GLASS)
        cyl_ring(sp, (cx, cy, zr), (cx, cy, th), 1.8, 0.45, 0.55, Mat("#2F9C95", 0.5), CYAN_LIGHT, 0.85)
        _glass_dome(sp, (cx, cy, th), 1.6, 1.4, glow=GOLD_LIGHT, mat=Mat("#C9A04A", 0.6), rib_col="#7A5C36", shell=False)
        top = th + 1.4
    else:
        _glass_block(sp, tx0, ty0, zr, tx1, ty1, th, 4, 4, 2, seed=6, dark=0.3)
        top = _crown(sp, (tx0 + tx1) / 2, (ty0 + ty1) / 2, 3.8, th, steps=2, apex=0.9)
    if v in (0, 2, 3):
        dr = 1.3 if v != 2 else 1.7
        sp.box(3.6, 1.0, zr, 1.0, 1.0, 0.6, STEEL, top=DARK)
        _dish(sp, (4.1, 1.5, zr + 0.6 + dr * 0.75), norm((1.0, -0.5, 0.42)), dr)
    if v == 1:
        _dish(sp, (4.0, 1.2, zt + 1.4), norm((1.0, -0.4, 0.5)), 1.0)
        sp.line((4.0, 1.0, zt), (4.0, 1.1, zt + 0.9), 0.1, "#9aa1aa")
    # 광장: 가로등과 깃대
    for (x, y) in ((-7.3, 5.3), (7.3, 5.3), (7.3, -2.0)):
        _lamp_post(sp, x, y, 2.6, COOL_WHITE, 12, z0)
    if v in (0, 4):
        for x in (3.6, 4.6, 5.6):
            sp.line((x, 5.3, z0), (x, 5.3, z0 + 4.4), 0.05, "#c9ccd1")
            sp.face(_orient([(x, 5.3, z0 + 3.4), (x + 0.75, 5.3, z0 + 3.4), (x + 0.75, 5.3, z0 + 4.3),
                             (x, 5.3, z0 + 4.3)], (0, 1, 0)), (BLUE, RED, TEAL)[int(x) % 3], two_sided=True, ao=0)


# ═════════════════════════════════════════════════════════════════════
# 우주 보험회관
# ═════════════════════════════════════════════════════════════════════

def _shield(sp, frame, cu, cv, size, fill=NAVY, rim=BRASS, mark=WHITE, glow=None):
    """면 위의 방패 표장 (size: 면 높이 비율). 안에 흰 갈매기 표시."""
    o, e1, e2 = frame
    n = _nrm(frame)
    k = length(e2) / max(1e-6, length(e1))
    hw, hh = size * 0.4 * k, size * 0.5

    def outline(s):
        pts = [(-hw * s, hh * s), (hw * s, hh * s), (hw * s, 0.05 * s)]
        for i in range(1, 8):
            t = i / 8
            pts.append((hw * s * math.cos(t * math.pi / 2), 0.05 * s - hh * 1.1 * s * math.sin(t * math.pi / 2)))
        pts += [(-x, y) for (x, y) in reversed(pts[2:-1])]
        return [add(_fp(frame, cu + du, cv + dv), mul(n, 0.03 + 0.01 * (1 - s))) for du, dv in pts]
    sp.face(_orient(outline(1.0), n), rim, normal=n, edge=False, ao=0)
    inner = outline(0.82)
    sp.face(_orient(inner, n), fill, normal=n, edge=False, ao=0)
    if glow:
        sp.mark_light(glow, 0.5)
        if dot(n, VIEW) > 0:
            sp.poly2([PV(p) for p in inner], glow, None, 0, 0.5, layer="light")
    c = [(-hw * 0.5, hh * 0.25), (0, -hh * 0.2), (hw * 0.5, hh * 0.25)]
    sp.polyline3([add(_fp(frame, cu + du, cv + dv), mul(n, 0.06)) for du, dv in c], mark if isinstance(mark, str)
                 else hexc(mark.albedo), 0.16)


def _rail_xy(sp, pts, h=0.85, color="#c9ccd1"):
    """옥상 난간 (위 막대 + 기둥)."""
    top = [(p[0], p[1], p[2] + h) for p in pts]
    for p, t in zip(pts, top):
        sp.line(p, t, 0.04, color)
    sp.polyline3(top, color, 0.05)


@typed("insurance_hall", 11, 9, 11.0, "우주 보험회관", heights=[11.0, 11.0, 11.3, 11.2, 11.0])
def insurance_hall(sp: Sprite, v: int):
    """계단식으로 물러나는 사무동: 아래층은 레골리스로 두껍게 덮고, 방패 표장, 옥상에 폭풍 경보등."""
    band, band_glow = ((NAVY, "#7FB2FF"), (NAVY, "#7FB2FF"), (Mat("#2F8F8A", 0.4), CYAN_LIGHT),
                       (MAROON, "#FF9C8A"), (NAVY, "#7FB2FF"))[v]
    zb = (3.4, 3.4, 3.0, 3.6, 3.4)[v]
    sp.contact_shadow(0, 0, 6.0, 5.0, 0.45)
    # 레골리스를 두껍게 덮은 아래층 (비탈 벽 + 쌓은 자국 + 깊은 창)
    bx0, by0, bx1, by1, ins = -5.3, -4.3, 5.3, 4.3, 0.75
    berm = (BERM, BERM, Mat("#857C70"), BERM, Mat("#7E766C"))[v]
    if v == 3:
        sp.box(bx0, by0, 0, bx1 - bx0, by1 - by0, zb, Mat("#8D857A"), top=Mat("#9C948A"))
        bf = Sprite.box_faces(bx0, by0, 0, bx1 - bx0, by1 - by0, zb)
        sp.panel_grid(*bf["left"], 14, 5, "#6c655c", 0.6, 0.8)
        sp.panel_grid(*bf["right"], 11, 5, "#6c655c", 0.6, 0.8)
        ins = 0.0
    else:
        sp.tbox(bx0, by0, bx1, by1, ins, zb, berm, top=Mat("#8A8279"))
        for t in (0.25, 0.5, 0.75):
            z = zb * t
            e = ins * t
            sp.polyline3([(bx0 + e, by1 - e, z), (bx1 - e, by1 - e, z), (bx1 - e, by0 + e, z)], "#5f5953", 0.06, 0.8)
    # 깊은 창 (비탈면 위쪽)
    def slope_y(z):
        return by1 - ins * z / zb

    def slope_x(z):
        return bx1 - ins * z / zb
    za, zc = zb * 0.5, zb * 0.78
    for x in (-4.0, -2.9, 2.6, 3.7):
        q = [(x, slope_y(za) + 0.02, za), (x + 0.6, slope_y(za) + 0.02, za), (x + 0.6, slope_y(zc) + 0.02, zc),
             (x, slope_y(zc) + 0.02, zc)]
        sp.window(_orient(q, (0, zb, ins)), WARM_WINDOW, frame="#4d4437")
    for y in (-3.0, -1.8, 1.2, 2.4):
        q = [(slope_x(za) + 0.02, y, za), (slope_x(za) + 0.02, y + 0.6, za), (slope_x(zc) + 0.02, y + 0.6, zc),
             (slope_x(zc) + 0.02, y, zc)]
        sp.window(_orient(q, (zb, 0, ins)), WARM_WINDOW, frame="#4d4437")
    # 층층이 물러나는 사무동
    if v == 1:                      # 앞(+x, +y)으로만 물러나는 테라스
        tiers = [(-4.5, -3.5, 4.5, 3.5, 2.5), (-4.5, -3.5, 3.1, 2.1, 2.3), (-4.5, -3.5, 1.7, 0.7, 1.9)]
    elif v == 2:
        tiers = [(-4.4, -3.4, 4.4, 3.4, 2.0), (-3.7, -2.8, 3.6, 2.7, 1.9), (-3.0, -2.3, 2.8, 2.0, 1.8),
                 (-2.2, -1.8, 1.9, 1.3, 1.6)]
    elif v == 4:                    # 왼쪽 뒤로만 물러난다
        tiers = [(-4.5, -3.5, 4.5, 3.5, 2.5), (-4.5, -2.4, 3.3, 3.5, 2.3), (-4.5, -1.3, 2.1, 3.5, 1.9)]
    else:
        tiers = [(-4.4, -3.4, 4.4, 3.4, 2.5), (-3.6, -2.8, 3.4, 2.6, 2.3), (-2.7, -2.2, 2.3, 1.8, 1.9)]
        if v == 3:
            tiers = [(x0_, y0_, x1_, y1_, h_ - 0.1) for (x0_, y0_, x1_, y1_, h_) in tiers]
    z = zb
    for i, (tx0, ty0, tx1, ty1, th) in enumerate(tiers):
        sp.box(tx0, ty0, z, tx1 - tx0, ty1 - ty0, th, PANEL, top=Mat("#B8BEC4", 0.2))
        f = Sprite.box_faces(tx0, ty0, z, tx1 - tx0, ty1 - ty0, th)
        for key in ("left", "right"):
            L = length(f[key][1])
            band_on(sp, f[key], 0.84, 0.97, band)
            n = max(2, int(L / 1.15))
            _grid_windows(sp, f[key], n, 1, 0.04, 0.96, 0.22, 0.72, gu=0.18, gv=0.0, glow=COOL_WHITE if i else WARM_WINDOW,
                          seed=i + v, dark=0.2)
        for key, fr in _faces4(tx0, ty0, z, tx1 - tx0, ty1 - ty0, th).items():
            if key in ("-x", "-y"):                   # 뒤 두 면 창 (3D 모형)
                _grid_windows(sp, fr, max(2, int(length(fr[1]) / 1.15)), 1, 0.04, 0.96, 0.22, 0.72, gu=0.18, gv=0.0,
                              glow=COOL_WHITE, seed=i)
        if i == 0:
            # 방패 표장: 첫 층 정면 (v2는 오른쪽 면)
            if v == 2:
                _shield(sp, f["right"], 0.5, 0.5, 1.0, glow="#7FB2FF")
            else:
                _shield(sp, f["left"], 0.5 if v != 1 else 0.35, 0.5, 1.0, glow="#7FB2FF")
        z += th
        # 다음 층 둘레의 테라스 난간 (앞쪽 두 변)
        if i + 1 < len(tiers):
            _rail_xy(sp, [(tx0, ty1, z), (tx1, ty1, z), (tx1, ty0, z)], 0.8)
            if v == 1:
                for (px, py) in ((tx1 - 0.5, ty1 - 0.5), (tx1 - 0.5, ty0 + 0.6), (tx0 + 0.6, ty1 - 0.5)):
                    sp.box(px - 0.3, py - 0.3, z, 0.6, 0.6, 0.35, CONCRETE, top=Mat("#5E8C4A"))
                    sp.sphere((px, py, z + 0.6), 0.32, LEAF)
    # 옥상 폭풍 경보등
    tx0, ty0, tx1, ty1, th = tiers[-1]
    cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
    zt = z
    if v == 3:
        _mast(sp, (cx, cy, zt), 0.8, 0.4)
        bz = zt + 0.8
    else:
        sp.cyl((cx, cy, zt), (cx, cy, zt + 0.45), 0.42, STEEL, cap_mat=DARK)
        bz = zt + 0.45
    col = (BEACON, BEACON, "#FF4A3A", BEACON, "#FFB02E")[v]
    p0, p1 = (cx, cy, bz), (cx, cy, bz + 0.5)
    sp.cyl(p0, p1, 0.36, Mat("#E8743A", 0.6), cap_mat=DARK)
    cyl_ring(sp, p0, p1, 0.36, 0.1, 0.9, Mat("#F08A4B", 0.7), col, 0.9)
    sp.disc((cx, cy, bz + 0.52), (0, 0, 1), 0.42, DARK)
    sp.lamp((cx, cy, bz + 0.25), col, 26)
    sp.glow((cx, cy, bz + 0.25), 44, col, 0.35)
    if v in (0, 2, 4):              # 경보 나팔 둘
        for s in (-1, 1):
            p = (cx + s * 0.9, cy + 0.6, zt)
            sp.line(p, add(p, (0, 0, 0.55)), 0.06, "#9aa1aa")
            sp.frustum(add(p, (0, 0, 0.6)), add(p, (0.0, 0.32, 0.7)), 0.06, 0.17, Mat("#9AA1AA", 0.4), cap_mat=DARK)
    # 출입구: 비탈을 뚫은 콘크리트 문간 + 차양
    if v == 4:
        ex0, ex1 = 1.4, 3.6
    else:
        ex0, ex1 = -1.2, 1.2
    sp.box(ex0, by1 - 1.3, 0, ex1 - ex0, 1.4, 2.8, CONCRETE, top=Mat("#b3a48e"))
    ef = Sprite.box_faces(ex0, by1 - 1.3, 0, ex1 - ex0, 1.4, 2.8)
    _lit_decal(sp, ef["left"], 0.2, 0.0, 0.8, 0.7, Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
    sp.box(ex0 - 0.3, by1 - 0.3, 2.5, ex1 - ex0 + 0.6, 0.45, 0.18, band, top=band)
    sp.lamp(((ex0 + ex1) / 2, by1 + 0.05, 2.35), WARM_WINDOW, 10)


# ═════════════════════════════════════════════════════════════════════
# 교역소 · 보세 창고 (컨테이너 계열)
# ═════════════════════════════════════════════════════════════════════

CONTAINERS = (Mat("#C8642F", 0.15), Mat("#2F5E9E", 0.15), Mat("#B23A33", 0.15), Mat("#2E8C84", 0.15),
              Mat("#C9A23A", 0.15), Mat("#6F7F3A", 0.15), Mat("#D5D8D9", 0.15))
YARD = Mat("#6F6B65")                # 짐마당 포장
YARD_TOP = Mat("#77736C")
CRANE = Mat("#E2B93B", 0.2)          # 갠트리 크레인 (노랑)
ROLL_DOOR = Mat("#D9822F", 0.15)     # 말아 올리는 문
SHED = Mat("#8C9BA7", 0.15)          # 골진 강판 벽
SHED_TOP = Mat("#A7B0B8", 0.25)
HALL_ROOF = Mat("#7D5A44", 0.15)     # 교역소 지붕 (녹슨 구리빛)
LINE_YELLOW = "#D9B53A"


def _container(sp, x, y, z, mat, along="y", L=6.0, W=2.4, H=2.5):
    """선적 컨테이너: 골진 긴 옆면 + 문 쪽 끝의 이음과 잠금 막대."""
    w, d = (W, L) if along == "y" else (L, W)
    dark = hexc(scale(mat.albedo, 0.6))
    sp.box(x, y, z, w, d, H, mat, top=Mat(hexc(scale(mat.albedo, 0.92)), 0.1))
    f = Sprite.box_faces(x, y, z, w, d, H)
    side, end = (f["right"], f["left"]) if along == "y" else (f["left"], f["right"])
    sp.panel_grid(*side, max(4, int(L / 0.38)), 1, dark, 0.5, 0.7)
    sp.panel_grid(*end, 2, 1, dark, 0.7, 0.9)
    n = _nrm(end)
    for u in (0.18, 0.36, 0.64, 0.82):
        sp.line(add(_fp(end, u, 0.06), mul(n, 0.03)), add(_fp(end, u, 0.94), mul(n, 0.03)), 0.04, dark)


def _roll_door(sp, frame, u0, u1, v0, v1, mat=ROLL_DOOR, lamp=True, slats=7):
    """말아 올리는 문: 테 → 문판 → 가로 살 (+ 위의 등)."""
    _decal(sp, frame, u0 - 0.012, v0, u1 + 0.012, min(1.0, v1 + 0.05), CHAR, 0.02)
    pts = _decal(sp, frame, u0, v0, u1, v1, mat, 0.04)
    sp.panel_grid(pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0]), 1, slats, hexc(scale(mat.albedo, 0.6)), 0.5, 0.8)
    if lamp:
        n = _nrm(frame)
        sp.lamp(add(_fp(frame, (u0 + u1) / 2, min(1.0, v1 + 0.1)), mul(n, 0.2)), AMBER, 9)


def _fence(sp, a, b, h=1.8, color="#a3a9b0", step=1.6):
    """철망 울타리: 기둥 + 위·가운데 막대 + 옅은 철망."""
    L = length(sub(b, a))
    n = max(1, int(round(L / step)))
    for i in range(n + 1):
        p = add(a, mul(sub(b, a), i / n))
        sp.line(p, add(p, (0, 0, h)), 0.06, color)
    sp.line(add(a, (0, 0, h)), add(b, (0, 0, h)), 0.05, color)
    sp.line(add(a, (0, 0, h * 0.5)), add(b, (0, 0, h * 0.5)), 0.035, color, 0.8)
    sp.panel_grid(a, sub(b, a), (0, 0, h), max(2, int(L / 0.3)), 6, color, 0.35, 0.35)


def _barrier(sp, base, d, L, z=1.0, up=0.0):
    """빨강·흰 줄무늬 차단봉 (base에서 d 방향으로 L만큼, up: 들린 각도[도])."""
    sp.box(base[0] - 0.2, base[1] - 0.2, 0, 0.4, 0.4, z + 0.15, Mat("#D5D8D9", 0.2), top=RED)
    a = math.radians(up)
    dd = (d[0] * math.cos(a), d[1] * math.cos(a), math.sin(a))
    p0 = (base[0], base[1], z)
    n = 8
    for i in range(n):
        q0 = add(p0, mul(dd, L * i / n))
        q1 = add(p0, mul(dd, L * (i + 1) / n))
        sp.line(q0, q1, 0.12, "#D9332C" if i % 2 == 0 else "#F2F2EE")
    sp.lamp(add(p0, (0, 0, 0.3)), "#FF4A3A", 6)


def _gable_hall(sp, x0, x1, y0, y1, ze, zr, wall, roof, eave=0.35):
    """박공지붕 집 (용마루는 x 방향): 벽 상자 → 박공 세모 → 지붕 두 면 (처마가 조금 나온다)."""
    ym = (y0 + y1) / 2
    sp.box(x0, y0, 0, x1 - x0, y1 - y0, ze, wall, top=wall)
    for x, n in ((x0, (-1, 0, 0)), (x1, (1, 0, 0))):
        sp.face(_orient([(x, y0, ze), (x, y1, ze), (x, ym, zr)], n), wall, ao=0)
    k = eave / (y1 - ym)
    zl = ze - (zr - ze) * k
    for (ya, yb, out) in ((y1 + eave, ym, (0, 1, 1.4)), (y0 - eave, ym, (0, -1, 1.4))):
        sp.face(_orient([(x0 - eave, ya, zl), (x1 + eave, ya, zl), (x1 + eave, yb, zr), (x0 - eave, yb, zr)], out),
                roof, ao=0)
    return ym


@typed("trade_exchange", 14, 10, 7.0, "교역소", heights=[7.0, 6.6, 7.0, 6.8, 7.0])
def trade_exchange(sp: Sprite, v: int):
    """박공지붕 교역 회관 (시계탑·시세판·간판·유리 박공·하역문) 옆에 컨테이너 짐마당과 갠트리 크레인."""
    wall = (CREAM, WHITE, CREAM, Mat("#D9CDB8"), CREAM)[v]
    roof = (HALL_ROOF, Mat("#5C6670", 0.25), HALL_ROOF, Mat("#6B4A3A", 0.15), Mat("#4F6A5C", 0.2))[v]
    crane = (CRANE, CRANE, Mat("#3E6FB0", 0.2), CRANE, Mat("#D9532C", 0.15))[v]
    sign = (Mat("#2F8F8A", 0.4), Mat("#2D4A7A", 0.3), Mat("#2F8F8A", 0.4), MAROON, Mat("#C9A23A", 0.3))[v]
    sglow = (CYAN_LIGHT, "#7FB2FF", CYAN_LIGHT, "#FF9C8A", GOLD_LIGHT)[v]
    dmat = (ROLL_DOOR, Mat("#C9A23A", 0.15), ROLL_DOOR, Mat("#3E6FB0", 0.2), ROLL_DOOR)[v]
    sp.contact_shadow(0, 0, 7.4, 5.4, 0.4)
    sp.box(-6.95, -4.95, 0, 13.9, 9.9, 0.08, YARD, top=YARD_TOP)
    ra, rb = 0.95, 6.55                               # 크레인 다리·레일 x
    for x in (ra, rb):
        sp.line((x, -4.8, 0.09), (x, 1.8, 0.09), 0.1, "#5c626b")
    sp.line((0.6, 3.6, 0.09), (6.8, 3.6, 0.09), 0.08, LINE_YELLOW, 0.8)
    # 회관: 박공지붕 (용마루 x 방향)
    hx0, hx1, hy0, hy1 = -6.6, 0.2, -4.4, 2.2
    ze, zr = (4.0, 3.8, 4.0, 4.0, 4.0)[v], (5.8, 5.4, 5.8, 5.6, 5.8)[v]
    ym = _gable_hall(sp, hx0, hx1, hy0, hy1, ze, zr, wall, roof)
    f = Sprite.box_faces(hx0, hy0, 0, hx1 - hx0, hy1 - hy0, ze)
    W, D = hx1 - hx0, hy1 - hy0

    def ux(x):
        return (hx1 - x) / W
    band_on(sp, f["left"], 0.0, 0.07, Mat("#8A7F70"))
    band_on(sp, f["right"], 0.0, 0.07, Mat("#8A7F70"))
    _grid_windows(sp, _faces4(hx0, hy0, 0, W, D, ze)["-y"], 5, 1, 0.08, 0.92, 0.3, 0.7, gu=0.45, gv=0.0)
    # 정면(+y): 간판 띠 → 시세판 → 유리문과 차양 → 하역문 둘
    _lit_decal(sp, f["left"], 0.03, 0.84, 0.97, 0.96, sign, sglow, 0.85)
    _letters(sp, f["left"], 0.3, 0.7, 0.87, 0.93, 6, Mat("#F2F0EA"), 0.04)
    bx0, bx1 = -4.95, -3.15
    _decal(sp, f["left"], ux(bx1), 0.28, ux(bx0), 0.76, Mat("#1C1F24", 0.3), 0.03)
    for r_ in range(5):
        vv = 0.33 + r_ * 0.085
        k, u = 0, ux(bx1) + 0.012
        while u < ux(bx0) - 0.03:
            seg = (0.03, 0.05, 0.022, 0.042, 0.028)[(k + r_ + v) % 5]
            _lit_decal(sp, f["left"], u, vv, min(ux(bx0) - 0.012, u + seg), vv + 0.04,
                       Mat("#B98A2E", 0.4), TICK_GREEN if (k + r_) % 4 == 0 else "#FFC34D", 0.95, 0.05)
            u += seg + 0.012
            k += 1
    ex0, ex1 = -6.35, -5.15
    _lit_decal(sp, f["left"], ux(ex1), 0.0, ux(ex0), 0.6, Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
    sp.panel_grid(_fp(f["left"], ux(ex1), 0.0), (ex0 - ex1, 0, 0), (0, 0, ze * 0.6), 2, 2, "#d8d2c4", 0.6, 0.9)
    sp.box(ex0 - 0.25, hy1, ze * 0.64, ex1 - ex0 + 0.5, 1.0, 0.14, sign, top=sign)
    sp.lamp(((ex0 + ex1) / 2, hy1 + 0.7, ze * 0.64 - 0.1), WARM_WINDOW, 10)
    for (xa, xb) in ((-2.95, -1.75), (-1.45, -0.25)):
        _roll_door(sp, f["left"], ux(xb), ux(xa), 1.0 / ze, 3.15 / ze, dmat)
    # 하역대 (정면 오른쪽) + 짐
    sp.box(-3.15, hy1, 0, 3.3, 1.2, 1.0, CONCRETE, top=Mat("#B3A48E"))
    sp.stripes((0.15, hy1 + 1.21, 0.75), (-3.3, 0, 0), (0, 0, 0.25), n=10)
    for x in (-2.75, -1.6, -0.45):
        sp.box(x, hy1 + 1.2, 0.4, 0.3, 0.12, 0.45, CHAR)
    if v in (0, 2, 4):
        crate(sp, -2.6, hy1 + 0.15, 0.8, Mat("#C9A23A"), 1.0)
        crate(sp, -1.0, hy1 + 0.2, 0.75, ORANGE, 1.0)
    # +x 박공 끝: 지붕선을 따라 잘린 유리 칸 + 옆문
    xg = hx1 + 0.02
    for i in range(6):
        ya = hy0 + 0.5 + (D - 1.0) * i / 6 + 0.06
        yb = hy0 + 0.5 + (D - 1.0) * (i + 1) / 6 - 0.06

        def ztop(y):
            return ze + (zr - ze) * (1 - abs(y - ym) / (D / 2)) - 0.3
        zb = ze + 0.12
        if max(ztop(ya), ztop(yb)) - zb < 0.3:
            continue
        q = [(xg, ya, zb), (xg, yb, zb), (xg, yb, max(zb + 0.1, ztop(yb))), (xg, ya, max(zb + 0.1, ztop(ya)))]
        sp.window(_orient(q, (1, 0, 0)), WARM_WINDOW, frame="#d8d2c4")
    door(sp, f["right"], 0.72, 0.86, 0.58, Mat("#5c626b", 0.3))
    sp.window(sp.on_face(*f["right"], 0.45, 0.3, 0.6, 0.62), WARM_WINDOW)
    # 용마루의 시계탑 (교역 회관 표시)
    cx = -3.4
    cz0 = zr - 0.5
    sp.box(cx - 0.55, ym - 0.55, cz0, 1.1, 1.1, 1.05, wall, top=wall)
    cf = _faces4(cx - 0.55, ym - 0.55, cz0, 1.1, 1.1, 1.05)
    for key, fr in cf.items():
        n = _nrm(fr)
        c = add(_fp(fr, 0.5, 0.55), mul(n, 0.03))
        if v == 3:
            sp.window(sp.on_face(*fr, 0.25, 0.25, 0.75, 0.85), WARM_WINDOW)
            continue
        sp.disc(c, n, 0.36, Mat("#F4F1E8", 0.2), two_sided=False)
        if dot(n, VIEW) > 0:
            sp.poly2([PV(add(c, mul(add(mul(basis(n)[0], math.cos(t)), mul(basis(n)[1], math.sin(t))), 0.36)))
                      for t in [k * math.pi / 8 for k in range(16)]], "#FFF1C9", None, 0, 0.75, layer="light")
            sp.line(add(c, mul(n, 0.02)), add(add(c, mul(n, 0.02)), (0, 0, 0.26)), 0.05, "#2a2f36")
            u_ = norm(cross(n, (0, 0, 1)))
            sp.line(add(c, mul(n, 0.02)), add(add(c, mul(n, 0.02)), mul(u_, 0.18)), 0.05, "#2a2f36")
    pz = cz0 + 1.05
    c4 = [(cx - 0.7, ym - 0.7, pz), (cx + 0.7, ym - 0.7, pz), (cx + 0.7, ym + 0.7, pz), (cx - 0.7, ym + 0.7, pz)]
    for i in range(4):
        sp.face(_orient([c4[i], c4[(i + 1) % 4], (cx, ym, pz + 0.75)],
                        (c4[i][0] + c4[(i + 1) % 4][0] - 2 * cx, c4[i][1] + c4[(i + 1) % 4][1] - 2 * ym, 1.0)), roof, ao=0)
    sp.line((cx, ym, pz + 0.75), (cx, ym, pz + 1.15), 0.05, "#C9A04A")
    # 짐마당: 크레인 뒤 다리 → 컨테이너 줄 → 앞 다리 → 위 보와 수레·집게
    yg = -1.5
    legs_y = (yg - 1.3, yg + 1.3)
    zg = (6.3, 5.9, 6.3, 6.1, 6.3)[v]

    def leg(x, y):
        sp.box(x - 0.17, y - 0.17, 0.1, 0.34, 0.34, zg - 0.1, crane, top=crane)
        sp.box(x - 0.3, y - 0.45, 0.1, 0.6, 0.9, 0.35, DARK)
    for y in legs_y:
        leg(ra, y)
    sp.box(ra - 0.12, legs_y[0], 0.75, 0.24, legs_y[1] - legs_y[0], 0.25, crane)
    rows = {0: ((1.25, 2, (0, 1)), (3.95, 1, (3,))), 1: ((1.25, 2, (1, 6)), (3.95, 2, (2, 4))),
            2: ((1.25, 1, (2,)), (3.95, 2, (6, 1))), 3: ((1.25, 2, (4, 0)), (3.95, 1, (5,))),
            4: ((1.25, 2, (3, 2)), (3.95, 2, (0, 1)))}[v]
    for (x, hgt, cols) in rows:
        for k in range(hgt):
            _container(sp, x, -4.55, 0.1 + k * 2.55, CONTAINERS[cols[k]], "y")
    for y in legs_y:
        leg(rb, y)
    sp.box(rb - 0.12, legs_y[0], 0.75, 0.24, legs_y[1] - legs_y[0], 0.25, crane)
    for y in (legs_y[0] - 0.1, legs_y[1] + 0.1):
        sp.box(ra - 0.3, y - 0.18, zg, rb - ra + 0.6, 0.36, 0.45, crane, top=crane)
    tx = (2.45, 5.15, 2.45, 5.15, 2.45)[v]
    sp.box(tx - 0.6, legs_y[0] - 0.15, zg + 0.45, 1.2, legs_y[1] - legs_y[0] + 0.3, 0.32, DARK, top=STEEL)
    sp.box(tx + 0.65, legs_y[1] - 0.7, zg - 1.15, 0.85, 0.85, 1.0, WHITE, top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(tx + 0.65, legs_y[1] - 0.7, zg - 1.15, 0.85, 0.85, 1.0)["right"],
                         0.15, 0.35, 0.85, 0.85), WARM_WINDOW)
    zs = 0.1 + 2.55 * [h for (x, h, c) in rows if abs(x + 1.2 - tx) < 0.2][0] + 0.3
    for dy in (-0.5, 0.5):
        sp.line((tx, yg + dy, zg), (tx, yg + dy, zs + 0.15), 0.04, "#2a2f36")
    sp.box(tx - 1.0, yg - 1.4, zs, 2.0, 2.8, 0.15, DARK, top=crane)
    sp.lamp((tx, yg, zg - 0.15), AMBER, 10)
    sp.lamp((rb, legs_y[1], zg + 0.6), "#ff5a3c", 6)
    # 앞마당: 상자와 마당 등
    if v in (1, 3):
        crate(sp, 4.4, 3.9, 0.9, Mat("#C9A23A"), 0.1)
        crate(sp, 5.4, 3.95, 0.8, ORANGE, 0.1)
        crate(sp, 4.9, 3.9, 0.75, Mat("#8E6A3E"), 0.82)
    sp.line((6.7, 4.7, 0.1), (6.7, 4.7, 5.0), 0.09, "#8a9099")
    sp.lamp((6.7, 4.7, 5.1), AMBER, 18)
    if v in (0, 2, 4):
        for x in (-6.4, -5.6):
            sp.line((x, 4.6, 0.1), (x, 4.6, 4.0), 0.05, "#c9ccd1")
            sp.face(_orient([(x, 4.6, 3.1), (x + 0.7, 4.6, 3.1), (x + 0.7, 4.6, 3.9), (x, 4.6, 3.9)], (0, 1, 0)),
                    (BLUE, TEAL)[int(-x) % 2], two_sided=True, ao=0)


@typed("bonded_warehouse", 16, 10, 6.0, "보세 창고", heights=[6.0, 6.0, 6.0, 5.6, 6.4])
def bonded_warehouse(sp: Sprite, v: int):
    """긴 골진 창고: 한쪽 긴 벽을 따라 말아 올리는 문과 하역대, 지붕 갈비, 울타리 친 세관 검문소와 컨테이너."""
    wall = (SHED, Mat("#9AA59B", 0.15), SHED, Mat("#B7A68C", 0.12), Mat("#7F8C96", 0.15))[v]
    dmat = (ROLL_DOOR, Mat("#C9A23A", 0.15), Mat("#B23A33", 0.15), Mat("#2E8C84", 0.15), ROLL_DOOR)[v]
    ndoor = (4, 3, 5, 4, 4)[v]
    wx0, wx1, wy0, wy1 = -7.4, (3.8, 3.8, 3.8, 2.6, 3.8)[v], -4.5, 0.6
    ze, zr = (4.4, 4.1, 4.4, 4.2, 4.4)[v], (5.95, 5.5, 5.95, 5.6, 5.85)[v]
    sp.contact_shadow(-1.0, -1.0, 7.6, 4.6, 0.4)
    sp.box(-7.95, -4.95, 0, 15.9, 9.9, 0.08, YARD, top=YARD_TOP)
    # 뒤쪽 울타리 (창고 오른쪽 뒤)
    _fence(sp, (wx1 + 0.4, -4.85, 0.08), (7.85, -4.85, 0.08))
    _fence(sp, (7.85, -4.85, 0.08), (7.85, -1.3, 0.08))
    # 컨테이너 (검문소 뒤)
    cx0 = wx1 + 0.7
    _container(sp, cx0, -4.6, 0.08, CONTAINERS[(1, 0, 3, 2, 6)[v]], "x", L=2.95, W=2.35, H=2.4)
    _container(sp, cx0, -4.6, 2.48, CONTAINERS[(2, 4, 5, 1, 0)[v]], "x", L=2.95, W=2.35, H=2.4)
    if v != 3:
        _container(sp, cx0, -2.1, 0.08, CONTAINERS[(4, 6, 0, 5, 3)[v]], "x", L=2.95, W=2.35, H=2.4)
    # 창고: 벽 → 지붕 (낮은 박공) → 갈비
    ym = (wy0 + wy1) / 2
    sp.box(wx0, wy0, 0, wx1 - wx0, wy1 - wy0, ze, wall, top=wall)
    f = Sprite.box_faces(wx0, wy0, 0, wx1 - wx0, wy1 - wy0, ze)
    W, D = wx1 - wx0, wy1 - wy0
    for key, nn in (("left", int(W / 0.42)), ("right", int(D / 0.42))):
        sp.panel_grid(*f[key], nn, 1, hexc(scale(wall.albedo, 0.72)), 0.45, 0.6)
        band_on(sp, f[key], 0.0, 0.07, Mat("#5c626b", 0.2))
    for x, n in ((wx0, (-1, 0, 0)), (wx1, (1, 0, 0))):
        sp.face(_orient([(x, wy0, ze), (x, wy1, ze), (x, ym, zr)], n), wall, ao=0)
    roofm = SHED_TOP if v != 3 else Mat("#9C8B74", 0.15)
    for (ya, out) in ((wy1 + 0.25, (0, 1, 2.6)), (wy0 - 0.25, (0, -1, 2.6))):
        zl = ze - (zr - ze) * 0.25 / (D / 2)
        sp.face(_orient([(wx0 - 0.25, ya, zl), (wx1 + 0.25, ya, zl), (wx1 + 0.25, ym, zr), (wx0 - 0.25, ym, zr)], out),
                roofm, ao=0)
    nrib = int(W / 1.6)
    for i in range(nrib):                             # 갈비 사이의 채광창 (앞·뒤 지붕)
        xa = wx0 - 0.1 + (W + 0.2) * i / nrib + 0.35
        xb = wx0 - 0.1 + (W + 0.2) * (i + 1) / nrib - 0.35
        for (ya, yb) in ((ym + 0.35, ym + 1.1), (ym - 1.1, ym - 0.35)):
            za_ = zr - (zr - ze) * abs(ya - ym) / (D / 2 + 0.25) + 0.03
            zb_ = zr - (zr - ze) * abs(yb - ym) / (D / 2 + 0.25) + 0.03
            q = [(xa, ya, za_), (xb, ya, za_), (xb, yb, zb_), (xa, yb, zb_)]
            sp.window(_orient(q, (0, 1 if ya > ym else -1, 2.6)), WARM_WINDOW, frame="#5c646d",
                      glass=Mat("#5D7488", 0.6), light_alpha=0.55)
    for i in range(nrib + 1):
        x = wx0 - 0.1 + (W + 0.2) * i / nrib
        sp.polyline3([(x, wy1 + 0.25, ze - 0.02), (x, ym, zr + 0.1), (x, wy0 - 0.25, ze - 0.02)], "#5c646d", 0.16)
    if v in (1, 4):                                   # 지붕 환기구
        for x in (wx0 + 2.5, wx0 + 6.0, wx0 + 9.5)[: 2 if v == 1 else 3]:
            sp.cyl((x, ym, zr - 0.1), (x, ym, zr + 0.55), 0.35, STEEL, cap_mat=DARK)
    # +x 끝 벽: 세관 표시 띠와 작은 문
    band_on(sp, f["right"], 0.78, 0.92, NAVY)
    door(sp, f["right"], 0.55, 0.78, 0.6, Mat("#5c626b", 0.3))
    # 하역대와 말아 올리는 문 (+y 긴 벽)
    zd = 1.1
    sp.box(wx0 + 0.2, wy1, 0, W - 0.4, 1.3, zd, CONCRETE, top=Mat("#B3A48E"))
    sp.stripes((wx1 - 0.2, wy1 + 1.31, zd - 0.22), (-(W - 0.4), 0, 0), (0, 0, 0.22), n=int(W * 1.6))
    band_on(sp, f["left"], 0.86, 0.96, NAVY)
    _letters(sp, f["left"], 0.06, 0.26, 0.885, 0.935, 5, Mat("#F2F0EA"), 0.03)
    span = (W - 0.8) / ndoor
    for i in range(ndoor):
        xa = wx0 + 0.4 + span * i + span * 0.18
        xb = xa + span * 0.64
        _roll_door(sp, f["left"], (wx1 - xb) / W, (wx1 - xa) / W, zd / ze, (zd + 2.3) / ze, dmat)
        for x in (xa - 0.12, xb + 0.02):
            sp.box(x, wy1 + 1.3, zd - 0.5, 0.1, 0.12, 0.42, CHAR)
    if v == 2:                                        # 하역대 차양
        sp.box(wx0 + 0.2, wy1, zd + 2.75, W - 0.4, 1.5, 0.14, SHED_TOP)
    # 트럭 칸 선
    for i in range(ndoor + 1):
        x = wx0 + 0.4 + span * i
        sp.line((x, wy1 + 1.5, 0.09), (x, 4.6, 0.09), 0.07, LINE_YELLOW, 0.8)
    # 세관 검문소: 유리 초소 + 넓은 지붕 + 표시등, 차단봉, 앞 울타리
    bx, by = (5.3, 0.9) if v != 3 else (4.3, 0.9)
    sp.box(bx - 0.2, by - 0.2, 0, 2.0, 2.0, 0.25, CONCRETE)
    sp.box(bx, by, 0.25, 1.6, 1.6, 2.2, PANEL, top=STEEL)
    bf = _faces4(bx, by, 0.25, 1.6, 1.6, 2.2)
    for fr in bf.values():
        sp.window(sp.on_face(*fr, 0.1, 0.38, 0.9, 0.88), WARM_WINDOW)
        _decal(sp, fr, 0.0, 0.0, 1.0, 0.14, NAVY, 0.02)
    sp.box(bx - 0.45, by - 0.45, 2.45, 2.5, 2.5, 0.22, NAVY, top=Mat("#C9CED3", 0.2))
    rf = Sprite.box_faces(bx - 0.45, by - 0.45, 2.45, 2.5, 2.5, 0.22)
    _lit_decal(sp, rf["left"], 0.05, 0.2, 0.95, 0.8, Mat("#3E6FB0", 0.3), "#7FB2FF", 0.8)
    _lit_decal(sp, rf["right"], 0.05, 0.2, 0.95, 0.8, Mat("#3E6FB0", 0.3), "#7FB2FF", 0.8)
    sp.lamp((bx + 0.8, by + 0.8, 2.85), "#FFB02E", 12)
    _barrier(sp, (bx + 0.8, by + 1.85), (0, 1, 0), 2.05, 1.0, (0, 0, 28, 0, 0)[v])
    _fence(sp, (-7.85, 4.85, 0.08), (bx - 0.5, 4.85, 0.08))
    _fence(sp, (7.85, -1.3, 0.08), (7.85, by - 0.1, 0.08))
    sp.lamp((7.85, 4.85, 2.4), AMBER, 10)
    if v == 4:                                        # 검역 탐지 기둥 둘
        for y in (2.5, 4.3):
            sp.cyl((bx + 1.9, y, 0.08), (bx + 1.9, y, 1.9), 0.14, Mat("#D5D8D9", 0.3), cap_mat=DARK)
            sp.lamp((bx + 1.9, y, 2.0), CYAN_LIGHT, 7)


# ═════════════════════════════════════════════════════════════════════
# 우주 시장
# ═════════════════════════════════════════════════════════════════════

AWNINGS = ((RED, WHITE), (TEAL, WHITE), (YELLOW, WHITE), (BLUE, WHITE), (ORANGE, CREAM), (Mat("#6DAE57"), WHITE))
VAULT_TERRA = Mat("#D2A07A", 0.1)    # 시장 볼트 (테라코타)
SIDE_GLASS = Mat("#2A4258", 0.35)    # 볼트 옆구리 유리 (해를 받아도 덜 번들거린다)
VAULT_RIB = "#8C5A3C"
TILE = Mat("#A79D8B")                # 광장 타일


def _vault_patch(p0, p1, r, s0, s1, side, e0, e1, lift=0.03):
    """누운 반원통 겉면의 네모 (side 쪽에서 앙각 e0~e1[도]). 창·띠에 쓴다."""
    a = norm(sub(p1, p0))
    out = norm(cross((0.0, 0.0, 1.0), a))
    if dot(out, side) < 0:
        out = mul(out, -1)
    t0 = Sprite.facing_angle(p0, p1, norm(add(mul(out, math.cos(math.radians(e0))), (0, 0, math.sin(math.radians(e0))))))
    t1 = Sprite.facing_angle(p0, p1, norm(add(mul(out, math.cos(math.radians(e1))), (0, 0, math.sin(math.radians(e1))))))
    if t1 < t0 - 180:
        t1 += 360
    elif t1 > t0 + 180:
        t1 -= 360
    pts = Sprite.cyl_patch(p0, p1, r, s0, s1, min(t0, t1), max(t0, t1), lift)
    return pts


def _kiosk(sp, x, y, cols, goods=None, w=1.8, d=1.3, h=2.3, along="x"):
    """시장 가판대: 계산대 → 물건 → 기둥 넷 → 줄무늬 박공 차양 (밤에 등)."""
    goods = goods or (ORANGE, GREEN, RED, YELLOW)
    sp.box(x - w / 2, y - d / 2, 0.1, w, d, 0.9, Mat("#8A5A3C", 0.2), top=Mat("#A8714C", 0.2))
    for i, g in enumerate(goods):
        gx = x - w / 2 + 0.25 + (w - 0.5) * i / max(1, len(goods) - 1)
        sp.sphere((gx, y + d * 0.15, 1.12), 0.2, g)
    for (px, py) in ((x - w / 2, y - d / 2), (x + w / 2, y - d / 2), (x - w / 2, y + d / 2), (x + w / 2, y + d / 2)):
        sp.line((px, py, 0.1), (px, py, h), 0.05, "#5c626b")
    n = 6
    zr, ze = h + 0.55, h - 0.05
    for i in range(n):
        xa = x - w / 2 - 0.15 + (w + 0.3) * i / n
        xb = x - w / 2 - 0.15 + (w + 0.3) * (i + 1) / n
        c = cols[i % 2]
        sp.face(_orient([(xa, y - d / 2 - 0.25, ze), (xb, y - d / 2 - 0.25, ze), (xb, y, zr), (xa, y, zr)], (0, -1, 1.5)),
                c, ao=0)
        sp.face(_orient([(xa, y, zr), (xb, y, zr), (xb, y + d / 2 + 0.25, ze), (xa, y + d / 2 + 0.25, ze)], (0, 1, 1.5)),
                c, ao=0)
        sp.face(_orient([(xa, y + d / 2 + 0.25, ze), (xb, y + d / 2 + 0.25, ze), (xb, y + d / 2 + 0.25, ze - 0.22),
                         (xa, y + d / 2 + 0.25, ze - 0.22)], (0, 1, 0)), c, ao=0, edge=False)
    sp.lamp((x, y + d / 2 - 0.1, h - 0.15), WARM_WINDOW, 9)


def _cross_vault(sp, xc, yc, R, r, zb, y_end, mat, aw, n=16):
    """큰 볼트(축 x, 반지름 R)를 가로지르는 작은 볼트 (축 y, 반지름 r): 두 원통이 만나는 선에서 y_end까지 띠로 그린다."""
    def at(t, y):
        return (xc + r * math.cos(t), y, zb + r * math.sin(t))

    def y0(t):
        return yc + math.sqrt(max(0.0, R * R - (r * math.sin(t)) ** 2))
    for i in range(n):
        t0, t1 = math.pi * i / n, math.pi * (i + 1) / n
        tm = (t0 + t1) / 2
        sp.face(_orient([at(t0, y0(t0)), at(t1, y0(t1)), at(t1, y_end), at(t0, y_end)], (math.cos(tm), 0, math.sin(tm))),
                mat, ao=0, edge=False)
    for y in (y_end - 0.08, (y0(math.pi / 2) + y_end) / 2):
        sp.polyline3([at(math.pi * k / 16, y) for k in range(17) if y >= y0(math.pi * k / 16)], VAULT_RIB, 0.07, 0.85)
    for k in range(3):                                # 용마루 유리
        ya = y0(math.pi / 2) + 0.15 + (y_end - y0(math.pi / 2) - 0.3) * k / 3
        yb = ya + (y_end - y0(math.pi / 2) - 0.3) / 3 - 0.1
        sp.window(_orient([at(math.radians(70), ya), at(math.radians(110), ya), at(math.radians(110), yb),
                           at(math.radians(70), yb)], (0, 0, 1)), WARM_WINDOW, frame="#d8d2c4", glass=ROOF_GLASS)
    cap = [at(math.pi * k / 16, y_end + 0.01) for k in range(17)]
    sp.face(_orient(cap, (0, 1, 0)), Mat("#D8CBB0"), normal=(0, 1, 0), ao=0)
    hub = (xc, y_end + 0.03, zb + 1.3)
    rr = r * 0.62
    fan = [(xc + rr * math.cos(math.pi * k / 8), y_end + 0.03, zb + 1.3 + rr * math.sin(math.pi * k / 8)) for k in range(9)]
    for k in range(8):
        sp.window(_orient([hub, fan[k], fan[k + 1]], (0, 1, 0)), WARM_WINDOW, frame="#d8d2c4", glass=ROOF_GLASS)
    _lit(sp, _orient([(xc - 0.7, y_end + 0.03, 0.1), (xc + 0.7, y_end + 0.03, 0.1), (xc + 0.7, y_end + 0.03, 1.2),
                      (xc - 0.7, y_end + 0.03, 1.2)], (0, 1, 0)), Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85)
    for i in range(6):
        xa, xb = xc - 1.1 + 2.2 * i / 6, xc - 1.1 + 2.2 * (i + 1) / 6
        q = [(xa, y_end, 1.35), (xb, y_end, 1.35), (xb, y_end + 0.7, 1.0), (xa, y_end + 0.7, 1.0)]
        sp.face(_orient(q, (0, 1, 1.5)), aw[i % 2], ao=0)
    sp.lamp((xc, y_end + 0.3, 1.6), WARM_WINDOW, 9)


def _string_lights(sp, pts, sag=0.35, every=0.7, color="#FFE9B0"):
    """늘어진 전구 줄 (기둥 사이)."""
    for a, b in zip(pts, pts[1:]):
        L = length(sub(b, a))
        n = max(2, int(L / every))
        line = []
        for i in range(n + 1):
            t = i / n
            p = add(a, mul(sub(b, a), t))
            line.append((p[0], p[1], p[2] - sag * 4 * t * (1 - t)))
        sp.polyline3(line, "#3a3f47", 0.03)
        for p in line[1:-1]:
            sp.lamp(p, color, 4)


@typed("market_hall", 14, 12, 6.0, "우주 시장", heights=[6.0, 5.5, 6.0, 6.0, 6.0])
def market_hall(sp: Sprite, v: int):
    """여압한 반원통 볼트 시장: 꼭대기·옆구리 유리 띠, 끝벽의 부채꼴 유리, 줄무늬 차양과 가판대, 전구 줄."""
    vm = (VAULT_TERRA, Mat("#E4DED2", 0.1), VAULT_TERRA, Mat("#C9B48E", 0.1), Mat("#B9C7B0", 0.1))[v]
    aw = (AWNINGS[0], AWNINGS[1], AWNINGS[4], AWNINGS[3], AWNINGS[5])[v]
    along_y = v == 2                                  # 볼트를 y 방향으로 눕힌다
    sp.contact_shadow(0, 0, 7.4, 6.4, 0.4)
    sp.box(-6.95, -5.95, 0, 13.9, 11.9, 0.1, TILE, top=Mat("#B4AA97"))
    sp.panel_grid((-6.95, -5.95, 0.1), (13.9, 0, 0), (0, 11.9, 0), 14, 12, "#9a907e", 0.4, 0.5)
    r = (4.6, 4.2, 4.6, 4.6, 4.6)[v]
    zb = 1.3 if v != 1 else 1.2
    if along_y:
        c0, c1, side = (-0.8, -5.7, zb), (-0.8, 3.3, zb), (1, 0, 0)
        sp.box(-0.8 - r, -5.7, 0.1, 2 * r, 9.0, zb - 0.1, SINTER, top=SINTER)
    else:
        c0, c1, side = (-6.3, -0.9, zb), (3.9, -0.9, zb), (0, 1, 0)
        sp.box(-6.3, -0.9 - r, 0.1, 10.2, 2 * r, zb - 0.1, SINTER, top=SINTER)
    L = length(sub(c1, c0))
    nb = int(L / 1.5)
    bands = [i / nb for i in range(1, nb)]
    sp.half_cyl(c0, c1, r, vm, bands=bands, band_color=VAULT_RIB, cap_mat=Mat("#D8CBB0"))
    # 유리 띠: 꼭대기 (용마루) + 보이는 옆구리 한 줄 (뒤쪽 옆구리는 3D에만)
    for i in range(nb):
        s0, s1 = i / nb + 0.012, (i + 1) / nb - 0.012
        for sd in (side, mul(side, -1)):
            sp.window(_vault_patch(c0, c1, r, s0, s1, sd, 74, 89), WARM_WINDOW, frame="#d8d2c4", glass=ROOF_GLASS)
            sp.window(_vault_patch(c0, c1, r, s0, s1, sd, 28, 44), WARM_WINDOW, frame="#d8d2c4", glass=SIDE_GLASS)
    sp.glow(add(mul(add(c0, c1), 0.5), (0, 0, r * 0.7)), 60, WARM_WINDOW, 0.3)
    # 끝벽(보이는 쪽)의 부채꼴 유리와 출입구
    ax = norm(sub(c1, c0))
    endc = add(c1, mul(ax, 0.03))
    lat = norm(cross((0, 0, 1), ax))
    R2 = r * 0.6
    fan = [add(add(endc, mul(lat, R2 * math.cos(math.pi * i / 10))), (0, 0, 1.6 + R2 * math.sin(math.pi * i / 10)))
           for i in range(11)]
    hub = add(endc, (0, 0, 1.6))
    for i in range(10):
        sp.window(_orient([hub, fan[i], fan[i + 1]], ax), WARM_WINDOW, frame="#d8d2c4", glass=ROOF_GLASS)
    # 앞 현관 (끝벽 앞으로 내민 상자) + 줄무늬 차양
    if along_y:
        vb = (-2.2, 3.3, 0.1, 2.8, 1.2, 2.5)
        vf = Sprite.box_faces(*vb)["left"]
    else:
        vb = (3.9, -2.3, 0.1, 1.2, 2.8, 2.5)
        vf = Sprite.box_faces(*vb)["right"]
    sp.box(*vb, Mat("#D8CBB0"), top=Mat("#BFB39E"))
    _lit_decal(sp, vf, 0.18, 0.0, 0.82, 0.75, Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
    n_ = _nrm(vf)
    for i in range(8):
        a0, a1 = i / 8, (i + 1) / 8
        p0, p1 = _fp(vf, a0, 0.98), _fp(vf, a1, 0.98)
        q0, q1 = add(add(p0, mul(n_, 1.1)), (0, 0, -0.5)), add(add(p1, mul(n_, 1.1)), (0, 0, -0.5))
        sp.face(_orient([p0, p1, q1, q0], add(n_, (0, 0, 1.6))), aw[i % 2], ao=0)
        sp.face(_orient([q0, q1, add(q1, (0, 0, -0.25)), add(q0, (0, 0, -0.25))], n_), aw[i % 2], ao=0, edge=False)
    sp.lamp(add(_fp(vf, 0.5, 1.0), add(mul(n_, 0.3), (0, 0, 0.35))), WARM_WINDOW, 10)
    # 가판대 줄 (볼트 옆, 보이는 쪽)
    if along_y:
        spots = [(4.6, y) for y in (-4.6, -2.2, 0.2)]
    else:
        spots = [(x, 4.6) for x in {1: (-5.4, -3.0, -0.6, 1.8), 4: (-5.4, -3.0, -0.6, 1.8),
                                    3: (-5.4, -3.2, 4.4)}.get(v, (-5.2, -2.6, 0.0))]
    items = []
    for i, (kx, ky) in enumerate(spots):
        cols = AWNINGS[(i + v) % len(AWNINGS)] if v != 1 else aw
        items.append(((kx, ky, 0), (lambda kx=kx, ky=ky, cols=cols, i=i: _kiosk(
            sp, kx, ky, cols, (ORANGE, GREEN, RED, YELLOW)[i % 2:] + (ORANGE,), d=1.3 if not along_y else 1.8,
            w=1.8 if not along_y else 1.3))))
    if v == 3:
        items.append(((0.6, 3.6, 0), lambda: _cross_vault(sp, 0.6, -0.9, r, 2.8, zb, 4.5, vm, aw)))
    elif not along_y and v not in (1, 4):
        # 옆 출입구 (볼트 옆구리로 내민 현관)
        def porch():
            sp.box(1.4, 2.4, 0.1, 2.2, 1.6, 2.6, Mat("#D8CBB0"), top=Mat("#BFB39E"))
            pf = Sprite.box_faces(1.4, 2.4, 0.1, 2.2, 1.6, 2.6)
            _lit_decal(sp, pf["left"], 0.2, 0.0, 0.8, 0.72, Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
            band_on(sp, pf["left"], 0.82, 0.95, aw[0])
        items.append(((2.5, 3.2, 0), porch))
    sp.parts(items)
    # 전구 줄과 기둥
    if along_y:
        poles = [(5.9, -5.6, 3.0), (5.9, -1.0, 3.0), (5.9, 1.6, 3.0)]
    else:
        poles = [(-6.6, 5.7, 3.0), (-1.8, 5.7, 3.0), (3.0, 5.7, 3.0)] if v not in (1, 4) else \
            [(-6.6, 5.7, 3.0), (-2.0, 5.7, 3.0), (2.6, 5.7, 3.0), (6.4, 5.7, 3.0)]
    for p in poles:
        sp.line((p[0], p[1], 0.1), p, 0.07, "#5c626b")
    _string_lights(sp, poles)


# ═════════════════════════════════════════════════════════════════════
# 우주 호텔
# ═════════════════════════════════════════════════════════════════════

HOTEL_GLASS = Mat("#2C4D63", 0.85)
BRONZE_GLASS = Mat("#4A3F33", 0.85)
SLAB = Mat("#F1EEE6", 0.1)           # 층 바닥판 (발코니 끝)
WATER = Mat("#5FB7D9", 0.7)


def _ell(cx, cy, rx, ry, n=28):
    """타원 둘레 점 (반시계)."""
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def _ell_wall(sp, pts, z0, z1, glow=WARM_WINDOW, glass=HOTEL_GLASS, seed=0, dark=0.3, frame="#c3ccd4"):
    """타원 둘레의 유리벽: 칸마다 창 하나 (뒤쪽 칸은 3D에만 남는다)."""
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        on = ((i * 7 + seed * 3 + (i // 3) * 5) % 10) >= dark * 10
        sp.window([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], glow, frame=frame,
                  glass=glass, light_alpha=0.85 if on else 0.12)


def _rail_ring(sp, pts, z, h=0.9, color="#dfe3e6"):
    """둘레 난간: 앞쪽 반은 그리고, 뒤쪽 반은 3D에만 적는다 (2D에서 유리벽 위로 그려지지 않게)."""
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        front = dot(norm(((a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy, 0.0)), VIEW) > -0.05
        _edge(sp, (a[0], a[1], z + h), (b[0], b[1], z + h), color, 0.05, front)
        if i % 2 == 0:
            _edge(sp, (a[0], a[1], z), (a[0], a[1], z + h), color, 0.035, front)


@typed("space_hotel", 12, 10, 16.0, "우주 호텔", heights=[16.0, 16.0, 16.0, 15.4, 16.2])
def space_hotel(sp: Sprite, v: int):
    """날씬한 타원 호텔탑: 층마다 발코니 판과 불 켜진 굽은 유리, 옥상의 유리 돔 라운지, 로비와 둥근 차양."""
    cx, cy = ((0.2, -1.3), (0.0, -1.2), (0.6, -1.4), (0.2, -1.3), (-0.4, -1.2))[v]
    rx, ry = ((2.9, 2.3), (2.5, 2.4), (2.8, 2.2), (3.0, 2.3), (2.3, 2.8))[v]
    nf = (5, 6, 5, 5, 5)[v]
    zp = 2.5                                          # 로비 지붕
    ft = (13.6 - zp - 0.3) / nf                       # 층 높이
    glass = (HOTEL_GLASS, HOTEL_GLASS, HOTEL_GLASS, BRONZE_GLASS, HOTEL_GLASS)[v]
    slab = (SLAB, Mat("#E8D9B5", 0.2), SLAB, Mat("#DCE4E2", 0.1), SLAB)[v]
    accent = (Mat("#C9A04A", 0.5), BRASS, TEAL, Mat("#2F8F8A", 0.4), MAROON)[v]
    aglow = (GOLD_LIGHT, GOLD_LIGHT, CYAN_LIGHT, CYAN_LIGHT, "#FF9C8A")[v]
    sp.contact_shadow(0, 0, 6.2, 5.2, 0.45)
    # 로비 (유리벽 상자 + 위 처마판 + 이름 띠)
    px0, py0, px1, py1 = -5.6, -4.6, 5.4, 3.0
    sp.box(px0, py0, 0, px1 - px0, py1 - py0, zp - 0.3, WHITE, top=SILVER)
    for key, fr in _faces4(px0, py0, 0, px1 - px0, py1 - py0, zp - 0.3).items():
        L = length(fr[1])
        _grid_windows(sp, fr, max(3, int(L / 1.3)), 1, 0.03, 0.97, 0.06, 0.92, gu=0.08, gv=0.0, glow=WARM_WINDOW,
                      glass=Mat("#3B5A6E", 0.85), frame_col="#e6e8ea", seed=v + len(key), dark=0.15)
    sp.box(px0 - 0.15, py0 - 0.15, zp - 0.3, px1 - px0 + 0.3, py1 - py0 + 0.3, 0.3, slab, top=Mat("#C9CED3", 0.2))
    lf = Sprite.box_faces(px0 - 0.15, py0 - 0.15, zp - 0.3, px1 - px0 + 0.3, py1 - py0 + 0.3, 0.3)
    _lit_decal(sp, lf["left"], 0.08, 0.2, 0.42, 0.8, accent, aglow, 0.85)
    _letters(sp, lf["left"], 0.12, 0.38, 0.3, 0.7, 5, Mat("#F8F4EA"), 0.04)
    # 로비 지붕의 수영장 (v0·v2) 또는 화단
    if v in (0, 2):
        qx0, qx1 = (-5.2, -1.6) if v == 0 else (-5.2, -2.6)
        sp.box(qx0 - 0.15, 1.75, zp, qx1 - qx0 + 0.3, 1.2, 0.12, slab, top=slab)
        _lit(sp, [(qx0, 1.9, zp + 0.13), (qx1, 1.9, zp + 0.13), (qx1, 2.8, zp + 0.13), (qx0, 2.8, zp + 0.13)], WATER,
             "#5FC8F0", 0.55)
        for k in range(3):
            sp.box(qx0 + 0.4 + k * 0.9, 1.0, zp, 0.5, 0.75, 0.15, WHITE)
    else:
        for x in (-5.0, -4.0):
            sp.box(x - 0.3, 1.9, zp, 0.6, 0.6, 0.3, CONCRETE, top=Mat("#5E8C4A"))
            sp.tree((x, 2.2, zp + 0.3), 1.3, 0.45)
    # 탑: 층마다 바닥판 → 굽은 유리벽 → 발코니 난간
    ring = _ell(cx, cy, rx, ry, 28)
    for k in range(nf):
        z0 = zp + k * ft
        sp.prism(_ell(cx, cy, rx + 0.4, ry + 0.4, 28), z0, 0.22, slab, top=Mat("#D8D9D4", 0.15))
        _ell_wall(sp, ring, z0 + 0.22, z0 + ft, WARM_WINDOW, glass, seed=k * 3 + v, dark=0.45 if k % 2 else 0.35)
        if v != 3 or k % 2 == 0:
            _rail_ring(sp, _ell(cx, cy, rx + 0.34, ry + 0.34, 28), z0 + 0.22, 0.85)
    zt = zp + nf * ft
    sp.prism(_ell(cx, cy, rx + 0.55, ry + 0.55, 28), zt, 0.3, slab, top=Mat("#BFC5CB", 0.2))
    ztop = zt + 0.3
    # 옥상 유리 돔 라운지
    dr = (2.0, 1.9, 1.9, 1.8, 1.9)[v]
    dh = (16.0, 16.0, 16.0, 15.4, 16.2)[v] - ztop - 0.25
    sp.cyl((cx, cy, ztop), (cx, cy, ztop + 0.25), dr + 0.2, STEEL, cap_mat=DARK)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        tx, ty = cx + dr * 0.55 * math.cos(a), cy + dr * 0.55 * math.sin(a)
        sp.cyl((tx, ty, ztop + 0.25), (tx, ty, ztop + 0.95), 0.05, STEEL, edge=False)
        sp.cyl((tx, ty, ztop + 0.95), (tx, ty, ztop + 1.0), 0.32, WHITE)
    if v == 1:
        sp.cyl((cx, cy, ztop + 0.25), (cx, cy, ztop + 0.6), 0.6, STEEL)
        _glass_dome(sp, (cx, cy, ztop + 0.3), dr, dh - 0.05, glow=WARM_WINDOW, mat=Mat("#6F9CBF", 0.9), alpha=0.5)
    else:
        _glass_dome(sp, (cx, cy, ztop + 0.25), dr, dh, glow=WARM_WINDOW, mat=Mat("#6F9CBF", 0.9), alpha=0.5)
    sp.lamp((cx, cy, ztop + 0.25 + dh + 0.1), "#ff5a3c", 6)
    _rail_ring(sp, _ell(cx, cy, rx + 0.45, ry + 0.45, 28), ztop, 0.8)
    # 세로 간판 (탑 앞)
    a = math.radians(70 if v != 4 else 20)
    bx, by = cx + (rx + 0.4) * math.cos(a), cy + (ry + 0.4) * math.sin(a)
    if v != 4:
        sp.box(bx - 0.5, by, zp + 0.6, 1.0, 0.35, ft * 3, accent, top=accent)
        _lit_decal(sp, Sprite.box_faces(bx - 0.5, by, zp + 0.6, 1.0, 0.35, ft * 3)["left"], 0.2, 0.06, 0.8, 0.94,
                   Mat("#F4E7C2", 0.3), aglow, 0.9)
    else:
        sp.box(bx, by - 0.5, zp + 0.6, 0.35, 1.0, ft * 3, accent, top=accent)
        _lit_decal(sp, Sprite.box_faces(bx, by - 0.5, zp + 0.6, 0.35, 1.0, ft * 3)["right"], 0.2, 0.06, 0.8, 0.94,
                   Mat("#F4E7C2", 0.3), aglow, 0.9)
    # 정문: 둥근 차양 (기둥 둘, 아래 등), 붉은 깔개, 화분
    ex = (1.6, 1.8, 2.2, 1.6, 0.8)[v]
    can = [(ex + 2.0 * math.cos(math.pi * i / 12), py1 + 1.7 * math.sin(math.pi * i / 12)) for i in range(13)]
    sp.face([(ex - 0.6, py1, 0.02), (ex + 0.6, py1, 0.02), (ex + 0.6, 4.85, 0.02), (ex - 0.6, 4.85, 0.02)],
            Mat("#A8322C", 0.1), normal=(0, 0, 1), ao=0)
    for x in (ex - 1.5, ex + 1.5):
        sp.line((x, py1 + 1.1, 0), (x, py1 + 1.1, 2.05), 0.08, "#c9ccd1")
    sp.prism(can, 2.05, 0.22, slab, top=Mat("#D8D9D4", 0.15))
    for x in (ex - 0.8, ex + 0.8):
        sp.lamp((x, py1 + 0.9, 1.98), WARM_WINDOW, 10)
    for x in (ex - 2.6, ex + 2.6):
        sp.cyl((x, 4.2, 0), (x, 4.2, 0.55), 0.35, CONCRETE, cap_mat=Mat("#5E8C4A"))
        sp.tree((x, 4.2, 0.55), 1.5, 0.5)


# ═════════════════════════════════════════════════════════════════════
# 우주 박물관
# ═════════════════════════════════════════════════════════════════════

MUSEUM = Mat("#ECEAE4", 0.1)         # 흰 조형 외장
PLAZA = Mat("#B3AB9C")
FOIL = Mat("#C99A3A", 0.6)           # 착륙선 금박
ROCKET = Mat("#F1F0EC", 0.2)


def _cone_patch(c0, c1, r0, r1, s0, s1, a0, a1, lift=0.03):
    """원뿔대 겉면의 네모 (축 위치 s, 각도 a[도])."""
    axis = sub(c1, c0)
    u, w = basis(axis)

    def at(s, ang):
        t = math.radians(ang)
        return add(add(c0, mul(axis, s)), mul(add(mul(u, math.cos(t)), mul(w, math.sin(t))), r0 + (r1 - r0) * s + lift))
    pts = [at(s0, a0), at(s0, a1), at(s1, a1), at(s1, a0)]
    am = math.radians((a0 + a1) / 2)
    return _orient(pts, add(mul(u, math.cos(am)), mul(w, math.sin(am))))


def _fins(sp, c, z0, z1, span, r, angles, mat, front):
    """로켓 꼬리 날개 (front: 카메라 쪽 날개만 / 뒤쪽 날개만)."""
    for a in angles:
        d = (math.cos(math.radians(a)), math.sin(math.radians(a)), 0.0)
        if (dot(d, VIEW) > 0) != front:
            continue
        p0 = (c[0] + d[0] * r, c[1] + d[1] * r, z1)
        p1 = (c[0] + d[0] * r, c[1] + d[1] * r, z0)
        p2 = (c[0] + d[0] * (r + span), c[1] + d[1] * (r + span), z0 - 0.25)
        p3 = (c[0] + d[0] * (r + span), c[1] + d[1] * (r + span), z0 + (z1 - z0) * 0.35)
        sp.face([p0, p1, p2, p3], mat, two_sided=True, ao=0)


def _rocket(sp, c, z0, h, body=ROCKET, accent=CHAR, nose=RED, boosters=False):
    """전시 로켓: 발사대 고리 → 뒤 날개 → 몸통 (굴림 무늬) → 원뿔 머리 → 앞 날개."""
    r = 0.46
    zb, zn = z0 + 0.7, z0 + h * 0.78
    for a in (45, 135, 225, 315):
        d = (math.cos(math.radians(a)), math.sin(math.radians(a)), 0)
        sp.line((c[0] + d[0] * 1.3, c[1] + d[1] * 1.3, z0), (c[0] + d[0] * 0.6, c[1] + d[1] * 0.6, zb + 0.4), 0.08, "#8a9099")
    _fins(sp, c, zb + 0.1, zb + 1.7, 0.75, r, (0, 90, 180, 270), accent, False)
    if boosters:
        for a in (0, 180):
            d = (math.cos(math.radians(a + 45)), math.sin(math.radians(a + 45)), 0)
            if dot(d, VIEW) < 0:
                bc = (c[0] + d[0] * 0.78, c[1] + d[1] * 0.78)
                sp.cyl((bc[0], bc[1], zb), (bc[0], bc[1], zb + h * 0.35), 0.3, body, cap_mat=body)
                sp.frustum((bc[0], bc[1], zb + h * 0.35), (bc[0], bc[1], zb + h * 0.35 + 0.7), 0.3, 0.05, body)
    p0, p1 = (c[0], c[1], zb), (c[0], c[1], zn)
    sp.cyl(p0, p1, r, body, cap_mat=body, bands=[0.33, 0.66], band_color="#9a9a96")
    face = Sprite.facing_angle(p0, p1)
    for k in range(4):                                # 굴림 무늬 (검은 칸)
        s0 = 0.06 + k * 0.23
        a0 = face - 90 + (k % 2) * 90
        sp.face(Sprite.cyl_patch(p0, p1, r, s0, s0 + 0.2, a0, a0 + 90, 0.02), accent, ao=0, edge=False)
    sp.frustum(p1, (c[0], c[1], z0 + h - 0.35), r, 0.12, body)
    sp.frustum((c[0], c[1], z0 + h - 0.35), (c[0], c[1], z0 + h), 0.12, 0.02, nose)
    if boosters:
        for a in (0, 180):
            d = (math.cos(math.radians(a + 45)), math.sin(math.radians(a + 45)), 0)
            if dot(d, VIEW) >= 0:
                bc = (c[0] + d[0] * 0.78, c[1] + d[1] * 0.78)
                sp.cyl((bc[0], bc[1], zb), (bc[0], bc[1], zb + h * 0.35), 0.3, body, cap_mat=body)
                sp.frustum((bc[0], bc[1], zb + h * 0.35), (bc[0], bc[1], zb + h * 0.35 + 0.7), 0.3, 0.05, body)
    _fins(sp, c, zb + 0.1, zb + 1.7, 0.75, r, (0, 90, 180, 270), accent, True)


def _lander(sp, c, z0, foil=FOIL, cabin=Mat("#B9BEC4", 0.4)):
    """전시 착륙선: 금박 하강단 (팔각) + 다리 넷 + 각진 상승단 (세모 창, 접시)."""
    oc = [(c[0] + 1.25 * math.cos(math.radians(22.5 + 45 * i)), c[1] + 1.25 * math.sin(math.radians(22.5 + 45 * i)))
          for i in range(8)]
    feet = [(c[0] + 2.0 * math.cos(math.radians(a)), c[1] + 2.0 * math.sin(math.radians(a))) for a in (0, 90, 180, 270)]
    zl = z0 + 1.0

    def leg(fx, fy, front):
        if (dot(norm((fx - c[0], fy - c[1], 0)), VIEW) > 0.1) != front:
            return
        d = norm((fx - c[0], fy - c[1], 0))
        top = (c[0] + d[0] * 1.15, c[1] + d[1] * 1.15, zl + 1.1)
        sp.line(top, (fx, fy, z0 + 0.15), 0.1, "#C9A04A")
        sp.line((c[0] + d[0] * 1.2, c[1] + d[1] * 1.2, zl + 0.1), (fx - d[0] * 0.3, fy - d[1] * 0.3, z0 + 0.6), 0.06,
                "#8a9099")
        sp.disc((fx, fy, z0 + 0.08), (0, 0, 1), 0.35, Mat("#C9CCD1", 0.4))
    for fx, fy in feet:
        leg(fx, fy, False)
    sp.prism(oc, zl, 1.2, foil, top=Mat("#B58A33", 0.5))
    sp.box(c[0] - 0.9, c[1] - 0.8, zl + 1.2, 1.7, 1.6, 1.25, cabin, top=Mat("#A9AEB4", 0.4))
    cf = Sprite.box_faces(c[0] - 0.9, c[1] - 0.8, zl + 1.2, 1.7, 1.6, 1.25)
    for key in ("left", "right"):
        n = _nrm(cf[key])
        w0, w1, w2 = _fp(cf[key], 0.3, 0.45), _fp(cf[key], 0.7, 0.45), _fp(cf[key], 0.5, 0.85)
        sp.window(_orient([add(w0, mul(n, 0.03)), add(w1, mul(n, 0.03)), add(w2, mul(n, 0.03))], n), WARM_WINDOW,
                  light_alpha=0.6)
    sp.cyl((c[0] - 0.05, c[1], zl + 2.45), (c[0] - 0.05, c[1], zl + 2.75), 0.4, cabin, cap_mat=DARK)
    sp.line((c[0] - 0.6, c[1] - 0.6, zl + 2.45), (c[0] - 0.9, c[1] - 0.9, zl + 3.2), 0.05, "#9aa1aa")
    _dish(sp, (c[0] - 0.9, c[1] - 0.9, zl + 3.3), norm((0.2, 0.6, 0.8)), 0.35)
    for fx, fy in feet:
        leg(fx, fy, True)


def _wedge_profile(x0, x1, lean, z0, ztop, m=10, power=1.8):
    """흰 쐐기 건물의 옆 윤곽 (x, z): 바닥 → 앞 뱃머리 → 쓸어 올린 지붕 곡선 → 뒤 낮은 끝."""
    xt = x1 + lean
    prof = [(x0, 0.0), (x1, 0.0), (xt, ztop)]
    for j in range(1, m + 1):
        x = xt - (xt - x0) * j / m
        prof.append((x, z0 + (ztop - z0) * max(0.0, (x - x0) / (xt - x0)) ** power))
    return prof


@typed("space_museum", 16, 12, 8.0, "우주 박물관", heights=[8.0, 7.0, 8.2, 7.8, 6.8])
def space_museum(sp: Sprite, v: int):
    """쓸어 올린 흰 쐐기 지붕과 기울어진 유리 뱃머리의 박물관 + 바깥 전시대에 선 로켓 또는 착륙선."""
    x0, x1, lean = -7.4, (3.0, 3.0, 2.6, 3.0, 2.8)[v], (0.9, 0.7, 1.1, 0.9, 0.6)[v]
    y0, y1 = -5.4, (1.4, 1.2, 1.6, 1.4, 1.2)[v]
    z0, ztop = (1.6, 2.2, 1.6, 1.8, 2.6)[v], (7.6, 7.0, 7.8, 7.4, 6.8)[v]
    skin = (MUSEUM, MUSEUM, Mat("#E5E1D6", 0.1), Mat("#DCE6EC", 0.6), Mat("#E9E2D8", 0.1))[v]
    slash = (BLUE_GLASS, BLUE_GLASS, Mat("#3B4A5C", 0.85), BLUE_GLASS, Mat("#2F5C59", 0.85))[v]
    banner = ((RED, BLUE), (ORANGE, TEAL), (MAROON, YELLOW), (BLUE, RED), (TEAL, ORANGE))[v]
    sp.contact_shadow(-0.6, -1.0, 7.8, 5.6, 0.4)
    sp.box(-7.95, -5.95, 0, 15.9, 11.9, 0.08, PLAZA, top=Mat("#BDB5A6"))
    sp.panel_grid((-7.95, -5.95, 0.08), (15.9, 0, 0), (0, 11.9, 0), 16, 12, "#a39b8c", 0.4, 0.5)
    prof = _wedge_profile(x0, x1, lean, z0, ztop, 12, (1.8, 1.4, 2.2, 1.8, 1.0)[v])
    # 3D용 뒤 두 면 (그림에서는 앞면에 가려진다)
    sp.face(_orient([(x, y0, z) for (x, z) in prof], (0, -1, 0)), skin, ao=0)
    for (xa, za), (xb, zb) in list(zip(prof[3:], prof[4:]))[:-1]:
        sp.window(_orient([(xa, y0 - 0.02, za - 1.5), (xb, y0 - 0.02, zb - 1.5), (xb, y0 - 0.02, zb - 0.55),
                           (xa, y0 - 0.02, za - 0.55)], (0, -1, 0)), WARM_WINDOW, frame="#e6e8ea", glass=BLUE_GLASS)
    sp.face(_orient([(x0, y0, 0), (x0, y1, 0), (x0, y1, z0), (x0, y0, z0)], (-1, 0, 0)), skin, ao=0)
    # 지붕 띠 (뒤 끝 → 뱃머리 꼭대기)
    curve = prof[2:]
    for (xa, za), (xb, zb) in zip(curve, curve[1:]):
        sp.face(_orient([(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], (zb - za, 0, xa - xb)), skin, ao=0)
    # 보이는 옆벽 (+y) + 지붕선을 따르는 유리 띠 + 현수막
    wall = [(x, y1, z) for (x, z) in prof]
    sp.face(_orient(wall, (0, 1, 0)), skin, normal=(0, 1, 0), ao=0.15)
    for (xa, za), (xb, zb) in list(zip(curve, curve[1:]))[1:-1]:
        if v == 3:
            for (zl, zh) in ((0.25, 0.42), (0.5, 0.68)):
                sp.window(_orient([(xa, y1 + 0.02, za * zl), (xb, y1 + 0.02, zb * zl), (xb, y1 + 0.02, zb * zh),
                                   (xa, y1 + 0.02, za * zh)], (0, 1, 0)), WARM_WINDOW, frame="#e6e8ea", glass=slash)
        sp.window(_orient([(xa, y1 + 0.02, za - 1.5), (xb, y1 + 0.02, zb - 1.5), (xb, y1 + 0.02, zb - 0.55),
                           (xa, y1 + 0.02, za - 0.55)], (0, 1, 0)), WARM_WINDOW, frame="#e6e8ea", glass=slash)
    for i, xb_ in enumerate((x0 + 1.2, x0 + 2.4)):
        sp.face(_orient([(xb_, y1 + 0.05, 0.4), (xb_ + 0.8, y1 + 0.05, 0.4), (xb_ + 0.8, y1 + 0.05, z0 - 0.15 + 0.6),
                         (xb_, y1 + 0.05, z0 - 0.15 + 0.6)], (0, 1, 0)), banner[i], ao=0, edge=False)
        sp.line((xb_ - 0.05, y1 + 0.08, z0 + 0.5), (xb_ + 0.85, y1 + 0.08, z0 + 0.5), 0.05, "#c9ccd1")
    # 기울어진 유리 뱃머리 (+x) + 정문
    fr = ((x1, y0, 0.0), (0.0, y1 - y0, 0.0), (lean, 0.0, ztop))
    _grid_windows(sp, fr, 6, 5, 0.02, 0.98, 0.02, 0.98, gu=0.06, gv=0.06, glow=WARM_WINDOW, glass=slash,
                  frame_col="#e6e8ea", seed=v, dark=0.1)
    _lit_decal(sp, fr, 0.62, 0.0, 0.86, 0.27, Mat("#9DB6C8", 0.8), "#FFF1D6", 0.9, 0.06)
    sp.box(x1 - 0.1, y1 - 2.6, 2.1, 1.6, 2.4, 0.18, skin, top=Mat("#C9CED3", 0.2))
    sp.lamp((x1 + 1.1, y1 - 1.4, 2.0), WARM_WINDOW, 10)
    sp.glow((x1 + 0.6, y1 - 2.0, 1.2), 30, WARM_WINDOW, 0.35)
    # 전시대: 둥근 받침 + 노란 테 + 안내판, 그 위에 로켓 또는 착륙선
    pc = ((5.2, 3.5), (5.1, 3.4), (5.2, 3.6), (5.2, 3.5), (5.1, 3.4))[v]
    pr = 2.2 if v in (0, 2, 3) else 2.5
    sp.cyl((pc[0], pc[1], 0.08), (pc[0], pc[1], 0.38), pr, CONCRETE, cap_mat=Mat("#9C948A"))
    sp.ring3((pc[0], pc[1], 0.39), pr - 0.25, "#E9C24A", 0.12, front_only=False)
    qx, qy = pc[0] - pr * 0.72, pc[1] + pr * 0.72
    sp.box(qx - 0.5, qy - 0.1, 0.08, 1.0, 0.25, 0.75, DARK, top=BRASS)
    for a in (30, 150, 270):
        d = (math.cos(math.radians(a)), math.sin(math.radians(a)), 0)
        sp.lamp((pc[0] + d[0] * (pr - 0.2), pc[1] + d[1] * (pr - 0.2), 0.5), "#FFF1D6", 9)
    if v in (0, 2, 3):
        _rocket(sp, (pc[0], pc[1]), 0.38, (7.6, 0, 7.8, 7.4)[v],
                body=(ROCKET, 0, Mat("#E7E3D8", 0.2), ROCKET)[v], accent=(CHAR, 0, ORANGE, Mat("#3E6FB0", 0.2))[v],
                nose=(RED, 0, CHAR, RED)[v], boosters=v == 3)
    else:
        _lander(sp, (pc[0], pc[1]), 0.38, foil=FOIL if v == 1 else Mat("#B9963F", 0.5))
    sp.glow((pc[0], pc[1], 2.5), 40, "#FFF1D6", 0.25)
    # 광장 왼쪽 앞: 고리 달린 행성 조형 (v3은 달 지구본)
    gx, gy = (-5.4, 3.7) if v != 2 else (-4.6, 4.0)
    sp.box(gx - 0.55, gy - 0.55, 0.08, 1.1, 1.1, 0.75, DARK, top=Mat("#6b7079", 0.3))
    sp.lamp((gx + 0.6, gy + 0.6, 0.2), "#FFF1D6", 8)
    if v == 3:
        sp.sphere((gx, gy, 1.75), 0.95, Mat("#C9C6BE", 0.15))
        for (dx, dy, dz, rr) in ((0.3, 0.55, 0.45, 0.22), (-0.25, 0.7, -0.1, 0.16), (0.65, 0.2, -0.3, 0.18)):
            sp.ellipsoid((gx + dx, gy + dy, 1.75 + dz), rr, rr, rr * 0.4, Mat("#9C988F"))
    else:
        rn = norm((0.35, -0.25, 1.0))
        u, w = basis(rn)
        ring = [add((gx, gy, 1.75), add(mul(u, 1.55 * math.cos(2 * math.pi * k / 40)), mul(w, 1.55 * math.sin(2 * math.pi * k / 40))))
                for k in range(41)]
        back = [p for p in ring if dot(sub(p, (gx, gy, 1.75)), VIEW) <= 0]
        front = [p for p in ring if dot(sub(p, (gx, gy, 1.75)), VIEW) > 0]
        sp.polyline3(back, "#C9A04A", 0.16)
        sp.sphere((gx, gy, 1.75), 0.85, (Mat("#D9A86A", 0.2), Mat("#C98B5E", 0.2), Mat("#E0C48A", 0.2), 0,
                                          Mat("#7FA8C8", 0.3))[v])
        sp.polyline3(front, "#E2C27A", 0.16)


# ═════════════════════════════════════════════════════════════════════
# 전망 타워
# ═════════════════════════════════════════════════════════════════════

BRICK = Mat("#A27F63")               # 소결 벽돌
POD_GLASS = Mat("#2A4A63", 0.85)


@typed("view_tower", 8, 8, 28.0, "전망 타워", heights=[28.0, 27.4, 28.0, 27.6, 27.0])
def view_tower(sp: Sprite, v: int):
    """소결 벽돌 기둥 위의 둥근 유리 전망 원반 (둘레 창), 빛나는 왕관과 안테나, 밑동의 매표 원형관."""
    crown_glow = (CYAN_LIGHT, GOLD_LIGHT, "#FF8AA0", CYAN_LIGHT, "#9BEA7A")[v]
    crown_mat = (Mat("#2F9C95", 0.5), Mat("#C9A04A", 0.5), Mat("#C4566A", 0.4), Mat("#2F9C95", 0.5), Mat("#5E9E4E", 0.4))[v]
    shaft = (BRICK, BRICK, Mat("#9C8B77"), BRICK, Mat("#D8D3C8", 0.1))[v]
    sp.contact_shadow(0, 0, 3.9, 3.9, 0.5)
    sp.cyl((0, 0, 0), (0, 0, 0.12), 3.95, PLAZA, cap_mat=Mat("#BDB5A6"))
    sp.ring3((0, 0, 0.13), 3.6, "#a39b8c", 0.06, front_only=False)
    # 밑동 원형관 (창 둘레 + 정문 차양)
    br = (3.0, 3.0, 2.8, 3.0, 3.2)[v]
    sp.cyl((0, 0, 0.12), (0, 0, 2.3), br, CREAM, cap_mat=Mat("#B8BEC4", 0.2), bands=[0.92], band_color="#9a9387")
    for k in range(12):
        a = 360 * k / 12 + 15
        sp.window(Sprite.cyl_patch((0, 0, 0.12), (0, 0, 2.3), br, 0.12, 0.78, a - 11, a + 11), WARM_WINDOW,
                  frame="#e6e8ea", glass=Mat("#3B5A6E", 0.85), light_alpha=0.85)
    ex, ey = (0.0, br - 0.3) if v != 4 else (br - 0.3, 0.0)
    if v != 4:
        sp.box(ex - 1.0, ey, 0.12, 2.0, 0.9, 2.5, Mat("#D8CBB0"), top=SILVER)
        _lit_decal(sp, Sprite.box_faces(ex - 1.0, ey, 0.12, 2.0, 0.9, 2.5)["left"], 0.2, 0.0, 0.8, 0.75,
                   Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
        sp.box(ex - 1.3, ey + 0.4, 2.5, 2.6, 0.7, 0.14, crown_mat, top=crown_mat)
    else:
        sp.box(ex, ey - 1.0, 0.12, 0.9, 2.0, 2.5, Mat("#D8CBB0"), top=SILVER)
        _lit_decal(sp, Sprite.box_faces(ex, ey - 1.0, 0.12, 0.9, 2.0, 2.5)["right"], 0.2, 0.0, 0.8, 0.75,
                   Mat("#5C7E99", 0.8), WARM_WINDOW, 0.85, 0.03)
        sp.box(ex + 0.4, ey - 1.3, 2.5, 0.7, 2.6, 0.14, crown_mat, top=crown_mat)
    # 기둥: 소결 벽돌 (켜마다 줄) + 빛나는 승강기 띠
    zs0, zs1 = 2.3, (19.2, 19.0, 19.2, 19.4, 19.6)[v]
    rs0, rs1 = (1.5, 1.3, 1.5, 1.45, 1.35)[v], (0.95, 1.3, 0.95, 0.9, 1.0)[v]
    nb = int((zs1 - zs0) / 1.1)
    p0, p1 = (0, 0, zs0), (0, 0, zs1)
    sp.frustum(p0, p1, rs0, rs1, shaft, bands=[i / nb for i in range(1, nb)], band_color=hexc(scale(shaft.albedo, 0.72)))
    face = Sprite.facing_angle(p0, p1)
    sp.window(_cone_patch(p0, p1, rs0, rs1, 0.02, 0.97, face - 7, face + 7, 0.03), "#FFE6B0", frame="#5c4a3c",
              glass=Mat("#3B4A55", 0.6), light_alpha=0.85)
    if v == 3:                                        # 바깥 유리 승강기 관
        lx, ly = 1.35, 1.35
        sp.cyl((lx, ly, zs0), (lx, ly, zs1 + 0.6), 0.42, Mat("#9FC3DA", 0.85), cap_mat=STEEL, bands=[0.25, 0.5, 0.75],
               band_color="#dfe9f2")
        sp.box(lx - 0.28, ly - 0.28, 9.0, 0.56, 0.56, 1.2, Mat("#F4E7C2", 0.3))
        sp.glow((lx, ly, 9.6), 14, WARM_WINDOW, 0.7)
    # 전망 원반: 아래 깔때기 → 유리 띠 (둘레 창) → 지붕 → 난간
    zp0 = zs1 - 0.2
    pr = (3.0, 2.7, 2.9, 3.0, 3.5)[v]
    if v == 2:                                        # 아래쪽 작은 원반
        zq = 14.2
        sp.frustum((0, 0, zq), (0, 0, zq + 0.6), 1.15, 2.0, PANEL)
        sp.cyl((0, 0, zq + 0.6), (0, 0, zq + 1.5), 2.0, POD_GLASS, cap_mat=PANEL)
        for k in range(12):
            a = 360 * k / 12
            sp.window(Sprite.cyl_patch((0, 0, zq + 0.6), (0, 0, zq + 1.5), 2.0, 0.1, 0.9, a - 12, a + 12), WARM_WINDOW,
                      frame="#e6e8ea", glass=POD_GLASS, light_alpha=0.9)
        sp.cyl((0, 0, zq + 1.5), (0, 0, zq + 1.75), 2.1, PANEL, cap_mat=Mat("#B8BEC4", 0.2))
    if v == 1:
        c = (0, 0, zp0 + 2.4)
        sp.sphere(c, pr, Mat("#E8E6E0", 0.2))
        for k in range(16):
            a = 360 * k / 16
            sp.window(Sprite.cyl_patch((0, 0, c[2] - 0.6), (0, 0, c[2] + 0.6), pr - 0.08, 0.0, 1.0, a - 10, a + 10, 0.06),
                      WARM_WINDOW, frame="#e6e8ea", glass=POD_GLASS, light_alpha=0.9)
        sp.ring3((0, 0, c[2] + 0.75), pr * 0.97, "#b9bcc0", 0.08)
        sp.ring3((0, 0, c[2] - 0.75), pr * 0.97, "#b9bcc0", 0.08)
        zr = c[2] + pr
    else:
        zg0 = zp0 + (1.3 if v != 4 else 0.8)
        zg1 = zg0 + (2.0 if v != 4 else 1.3)
        sp.frustum((0, 0, zp0), (0, 0, zg0), rs1, pr, PANEL)
        sp.cyl((0, 0, zg0), (0, 0, zg1), pr, POD_GLASS, cap_mat=PANEL)
        nw = 18 if pr > 3.2 else 16
        for k in range(nw):
            a = 360 * k / nw
            sp.window(Sprite.cyl_patch((0, 0, zg0), (0, 0, zg1), pr, 0.08, 0.92, a - 180 / nw + 1.2, a + 180 / nw - 1.2),
                      WARM_WINDOW, frame="#e6e8ea", glass=POD_GLASS, light_alpha=0.9)
        cyl_ring(sp, (0, 0, zg0), (0, 0, zg1), pr, 0.0, 0.08, PANEL)
        cyl_ring(sp, (0, 0, zg0), (0, 0, zg1), pr, 0.92, 1.0, PANEL)
        sp.frustum((0, 0, zg1), (0, 0, zg1 + 0.6), pr + 0.08, pr - 0.7, PANEL, cap_mat=Mat("#B8BEC4", 0.2))
        zr = zg1 + 0.6
        rr = pr - 0.75
        pts = [(rr * math.cos(2 * math.pi * k / 32), rr * math.sin(2 * math.pi * k / 32)) for k in range(32)]
        _rail_ring(sp, pts, zr, 0.8)
    sp.glow((0, 0, zr - 1.2), 70, WARM_WINDOW, 0.3)
    # 왕관 (빛나는 띠) + 안테나 + 붉은 등
    ch = (1.2, 1.0, 1.2, 1.2, 1.0)[v]
    cr = (1.0, 0.8, 0.9, 1.0, 1.1)[v]
    sp.cyl((0, 0, zr), (0, 0, zr + ch), cr, PANEL, cap_mat=Mat("#B8BEC4", 0.2))
    cyl_ring(sp, (0, 0, zr), (0, 0, zr + ch), cr, 0.25, 0.75, crown_mat, crown_glow, 0.95)
    sp.glow((0, 0, zr + ch * 0.5), 30, crown_glow, 0.45)
    top = (28.0, 27.4, 28.0, 27.6, 27.0)[v]
    sp.frustum((0, 0, zr + ch), (0, 0, top - 0.2), 0.24, 0.05, STEEL)
    sp.lamp((0, 0, top - 0.1), "#ff5a3c", 7)
    for zz in (zr + ch + (top - zr - ch) * 0.4,):
        sp.ring3((0, 0, zz), 0.35, "#c9ccd1", 0.05)
