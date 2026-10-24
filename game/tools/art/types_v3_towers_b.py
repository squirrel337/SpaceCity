"""고층 건물 묶음 (v3-b) — 금융 타워·고층 호텔 2종과 고층 공사 현장.

도시가 빽빽해지면 낮은 건물 자리에 고층 건물이 들어선다. 금융 타워는 우주 은행·증권거래소 계열의 마천루,
고층 호텔은 달 관광객을 받는 호화 호텔탑이다. 고층 공사 현장(scaffold_tower)은 높은 건물을 짓는 동안
그 자리에 서는 비계와 크레인으로, 게임이 짓는 건물의 바닥 칸과 지금 높이에 맞춰 늘려 쓴다 (모양 하나).

종류마다 함수 하나 fn(sp, v)가 같은 기능의 다섯 모양(v = 0~4)을 그린다. v0이 대표 모양이다.
모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다. 뒤(x+y가 작은 쪽)에서 앞, 아래에서 위 순서로 그린다.
탑이 높아 창을 칸마다 적으면 모형이 무거워지므로, 3D에는 층마다 면 하나에 유리 띠 하나와 면마다 멀리언 격자 하나만 적는다.
그림(2D)의 밤 불빛은 칸마다 나눠 몇 칸을 끈다. 뒤쪽 면의 창·띠는 3D 모형에만 남는다.
"""
from __future__ import annotations

import math

import iso
from types_common import *  # noqa: F401,F403

# ── 재질 ──────────────────────────────────────────────────────────────
GRANITE = Mat("#7F7B75")             # 광장 바닥 (짙은 소결석)
GRANITE_TOP = Mat("#96918A")
STONE = Mat("#D5CAB6")               # 소결 석재 (차폐 기단부)
STONE_TOP = Mat("#BFB39E")
PLINTH = Mat("#A2967F")              # 밑 띠·계단
PLINTH_TOP = Mat("#B6AA93")
REVEAL = Mat("#5E5446")              # 두꺼운 벽에 깊이 들어간 창 둘레
BRASS = Mat("#CFA247", 0.6)          # 왕관·표장
BRONZE = Mat("#7A5C36", 0.4)         # 청동 문틀
PANEL = Mat("#DCDDD8", 0.1)          # 흰 외장 패널
TICKER_BG = Mat("#15191F", 0.4)      # 시세 띠 바탕
LOBBY_GLASS = Mat("#3B5A6E", 0.85)   # 로비 유리
CROWN_LIT = Mat("#F2D58E", 0.5)      # 빛나는 왕관 띠 (낮)
MAROON = Mat("#8E3B3B", 0.1)

GOLD_LIGHT = "#FFD27A"               # 왕관·간판 불빛
COOL_WHITE = "#E3F1FF"
OFFICE = "#CFE2F4"                   # 사무실 창 불빛 (밤)
LOBBY = "#FFF3D6"                    # 로비 불빛
TICK_GREEN = "#6CF29A"
TICK_RED = "#FF5A4A"
BEACON = "#FF7A2E"
RED_LIGHT = "#ff5a3c"
TICK_DAY = {TICK_GREEN: Mat("#2FA35E", 0.5), TICK_RED: Mat("#C2473B", 0.5), AMBER: Mat("#D0922F", 0.5),
            CYAN_LIGHT: Mat("#2F9C95", 0.5)}


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


def _side_frames(base, z, h):
    """반시계 바닥 다각형을 h만큼 세운 기둥의 옆면 틀 — 가로 × 세로가 바깥 법선."""
    out = []
    for i in range(len(base)):
        a, b = base[i], base[(i + 1) % len(base)]
        out.append(((a[0], a[1], z), (b[0] - a[0], b[1] - a[1], 0.0), (0.0, 0.0, h)))
    return out


def _nrm(frame):
    return norm(cross(frame[1], frame[2]))


def _seen(n) -> bool:
    return dot(n, VIEW) > 1e-6


def _decal(sp, frame, u0, v0, u1, v1, mat, lift=0.0, edge=False):
    """면 위의 색 판 (띠·패널·문)."""
    n = _nrm(frame)
    pts = [add(p, mul(n, lift)) for p in sp.on_face(*frame, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=edge, ao=0)
    return pts


def _lit(sp, pts, mat, glow, alpha=0.85):
    """밤에 빛나는 면 (간판·시세 띠·왕관 띠). 3D는 면이 스스로 빛나고, 2D 밤 그림에는 보이는 면만 칠한다."""
    n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    sp.mark_light(glow, alpha)
    if _seen(n):
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


def _grid(sp, frame, n1, n2, color, width_px=0.7, opacity=0.7, lift=0.05):
    """면 위의 멀리언 격자 (n1 × n2 칸). 보이는 면만 2D에 긋고, 뒤쪽 면은 3D에만 적는다."""
    o, e1, e2 = frame
    n = _nrm(frame)
    o = add(o, mul(n, lift))
    if _seen(n):
        sp.panel_grid(o, e1, e2, n1, n2, color, width_px, opacity)
    else:
        sp._rec(("grid", o, e1, e2, n1, n2, color, width_px / S))


def _pane_on(i, seed, alpha) -> bool:
    """2D 밤 그림에서 칸 i가 켜졌나 — 층의 불빛 세기(alpha)만큼 켠다."""
    return ((i * 37 + seed * 11 + (i * seed) % 5) % 17) / 17.0 < alpha + 0.08


def _strip(sp, pts3, glass, glow, alpha, frame_col="#c3ccd4", panes=1, seed=0, lo=0.0):
    """층 하나 너비의 유리 띠. 3D는 창 하나 (밤 세기 alpha), 2D 밤 불빛은 panes칸으로 나눠 몇 칸은 끈다.
    lo: 2D 불빛을 아래에서 이 비율만큼 비운다 (앞의 막힌 난간에 가려지는 자리 — 불빛이 난간 위로 새지 않게)."""
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if sp._on():
        sp.rec.append(("win", sp._lift(pts3, n), glow, glass, alpha))
    if not _seen(n):
        return
    with sp._nest():
        sp.window(pts3, glow, frame=frame_col, glass=glass, light_alpha=0.0)
    a, b, c, d = pts3
    a, b = add(a, mul(sub(d, a), lo)), add(b, mul(sub(c, b), lo))
    for i in range(panes):
        t0, t1 = (i + 0.07) / panes, (i + 0.93) / panes
        q = [add(a, mul(sub(b, a), t0)), add(a, mul(sub(b, a), t1)), add(d, mul(sub(c, d), t1)),
             add(d, mul(sub(c, d), t0))]
        on = _pane_on(i, seed, alpha)
        sp.poly2([PV(p) for p in q], glow, None, 0, 0.88 if on else 0.1, layer="light")


def _floor_alpha(k, face, seed):
    """층 k, 면 face의 밤 불빛 세기 (3D 유리 띠 하나의 세기 — 층마다 켜진 사무실 수가 다르다)."""
    return (0.8, 0.35, 0.75, 0.12, 0.6, 0.8, 0.25, 0.1, 0.7, 0.45)[(k * 3 + face * 7 + seed * 5) % 10]


def _curtain_faces(sp, frames, z0, fh, nf, glass, glow, frame_col, mull, seed=0, margin=0.24, sill=0.55, head=0.2,
                   pane=1.45, zskip=None, k0=0):
    """세운 면들(frames: 원점·가로·세로)에 층마다 유리 띠와 면마다 세로 멀리언을 붙인다 (k0: 첫 층 번호)."""
    for fi, fr in enumerate(frames):
        L = length(fr[1])
        H = length(fr[2])
        mu = margin / L
        nc = max(2, int(round((L - 2 * margin) / pane)))
        for k in range(nf):
            zb = k * fh
            if zskip and zskip(k):
                continue
            pts = sp.on_face(*fr, mu, (zb + sill) / H, 1 - mu, (zb + fh - head) / H)
            _strip(sp, pts, glass, glow, _floor_alpha(k + k0, fi, seed), frame_col, nc, seed + (k + k0) * 3 + fi)
        o, e1, e2 = fr
        _grid(sp, (_fp(fr, mu, 0.0), mul(e1, 1 - 2 * mu), e2), nc, 1, mull)


def _glass_tower(sp, x0, y0, x1, y1, z0, nf, fh, body, top, glass, glow=OFFICE, frame_col="#c3ccd4", mull="#d5dbe1",
                 seed=0, margin=0.24, pane=1.45):
    """유리 커튼월 덩어리: 몸통 상자(층 사이·모서리에 띠로 남는다) → 네 면에 층마다 유리 띠 → 세로 멀리언."""
    H = nf * fh
    sp.box(x0, y0, z0, x1 - x0, y1 - y0, H, body, top=top)
    _curtain_faces(sp, list(_faces4(x0, y0, z0, x1 - x0, y1 - y0, H).values()), z0, fh, nf, glass, glow, frame_col,
                   mull, seed, margin, pane=pane)
    return z0 + H


def _ticker(sp, frame, colors, seed=0, v0=0.2, v1=0.8, lift=0.03):
    """시세 띠: 길이가 다른 빛 조각이 줄지어 흐른다 (낮에도 색이 보인다)."""
    L = length(frame[1])
    u, k = 0.15 / L, seed
    while u < 1 - 0.35 / L:
        u1 = min(1 - 0.15 / L, u + (0.9, 1.7, 1.2, 2.2, 1.0, 1.9)[k % 6] / L)
        col = colors[k % len(colors)]
        _lit_decal(sp, frame, u, v0, u1, v1, TICK_DAY[col], col, 0.95, lift)
        u = u1 + 0.25 / L
        k += 1


def _ticker_band(sp, x0, y0, x1, y1, z0, z1, colors, seed=0, out=0.15):
    """덩어리를 두르는 시세 띠 (조금 내민 검은 띠 + 빛 조각, 네 면 모두)."""
    sp.box(x0 - out, y0 - out, z0, x1 - x0 + 2 * out, y1 - y0 + 2 * out, z1 - z0, TICKER_BG, top=Mat("#8E959D", 0.3))
    for i, fr in enumerate(_faces4(x0 - out, y0 - out, z0, x1 - x0 + 2 * out, y1 - y0 + 2 * out, z1 - z0).values()):
        _ticker(sp, fr, colors, seed + i * 2)


def _lamp_post(sp, x, y, h=2.6, color=COOL_WHITE, r=12, z=0.0):
    sp.line((x, y, z), (x, y, z + h), 0.09, "#5c626b")
    sp.box(x - 0.14, y - 0.14, z + h - 0.05, 0.28, 0.28, 0.08, DARK)
    sp.lamp((x, y, z + h + 0.1), color, r)


def _spire(sp, c, z0, top, r0=0.28, mat=STEEL, ring_col="#c9ccd1", beacon=RED_LIGHT):
    """가는 첨탑 + 꼭대기 항공 장애등 (top = 첨탑 끝 높이)."""
    sp.frustum((c[0], c[1], z0), (c[0], c[1], top - 0.12), r0, 0.04, mat, bands=[0.3, 0.6], band_color=ring_col)
    sp.lamp((c[0], c[1], top - 0.1), beacon, 7)


def _emblem(sp, c, n, r):
    """금빛 둥근 표장: 원판 + 안쪽 원판 + 별."""
    sp.disc(c, n, r, BRASS, two_sided=False)
    sp.disc(add(c, mul(n, 0.02)), n, r * 0.72, Mat("#8C6A33", 0.4), two_sided=False)
    u, w = basis(n)
    star = []
    for k in range(10):
        a = math.pi / 2 + math.pi * k / 5
        rr = r * (0.55 if k % 2 == 0 else 0.24)
        star.append(add(add(c, mul(n, 0.04)), add(mul(u, rr * math.cos(a)), mul(w, rr * math.sin(a)))))
    sp.face(_orient(star, n), Mat("#F2D58E", 0.5), normal=n, edge=False, ao=0)


# ═════════════════════════════════════════════════════════════════════
# 금융 타워
# ═════════════════════════════════════════════════════════════════════

FIN_GLASS = (Mat("#2F5878", 0.85), Mat("#2C6B6E", 0.85), Mat("#4C4A44", 0.85), Mat("#24456B", 0.85),
             Mat("#4D7090", 0.85))
FIN_FRAME = (Mat("#B3BCC5", 0.35), PANEL, Mat("#C4C9CD", 0.5), PANEL, Mat("#4A525C", 0.3))
FIN_MULL = ("#d5dbe1", "#e9ecec", "#e8eaec", "#eef0f0", "#2f343b")
FIN_STONE = (STONE, Mat("#B9AE9A"), Mat("#8F877B"), STONE, Mat("#C7BCA8"))
FIN_TICK = ((TICK_GREEN, TICK_RED, AMBER), (CYAN_LIGHT, AMBER), (TICK_GREEN, TICK_RED),
            (AMBER, TICK_GREEN, TICK_RED, TICK_GREEN), (TICK_RED, TICK_GREEN, AMBER))
FIN_HEIGHTS = [64.0, 63.0, 62.0, 66.0, 60.0]


def _fin_podium(sp, v, x0, y0, x1, y1, zg, zp, door_x):
    """방사선을 막는 두꺼운 석재 기단부: 밑 띠 → 벽 (깊은 띠창) → 시세 띠 → 정면(+y)의 높은 유리 현관."""
    wall = FIN_STONE[v]
    top = Mat("#A9A08F") if v == 2 else STONE_TOP
    W, D = x1 - x0, y1 - y0
    sp.box(x0 - 0.12, y0 - 0.12, zg, W + 0.24, D + 0.24, 0.8, PLINTH, top=PLINTH_TOP)
    zw = zg + 0.8
    H = zp - zw
    sp.box(x0, y0, zw, W, D, H, wall, top=top)
    fr = _faces4(x0, y0, zw, W, D, H)
    zt0, zt1 = zp - 1.35, zp - 0.55                   # 시세 띠 높이
    rv0, rv1 = (zt0 - 2.3 - zw) / H, (zt0 - 0.5 - zw) / H     # 띠창 높이 (비율)
    # 정문 자리 (+y 면 비율)
    du0, du1 = (x1 - door_x - 2.0) / W, (x1 - door_x + 2.0) / W
    for i, (key, f) in enumerate(fr.items()):
        L = length(f[1])
        spans = [(0.35 / L, 1 - 0.35 / L)]
        if key == "+y":
            spans = [(0.35 / L, du0 - 0.5 / L), (du1 + 0.5 / L, 1 - 0.35 / L)]
        for (a, b) in spans:
            if b - a < 0.6 / L:
                continue
            _decal(sp, f, a - 0.12 / L, rv0 - 0.16 / H, b + 0.12 / L, rv1 + 0.08 / H, REVEAL, 0.0)
            pts = sp.on_face(*f, a, rv0, b, rv1)
            nc = max(2, int(round((b - a) * L / 1.1)))
            _strip(sp, pts, LOBBY_GLASS, WARM_WINDOW, 0.75 if (i + v) % 3 else 0.45, "#d8d2c4", nc, i + v)
            _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), nc, 1, "#d8d2c4", 0.6, 0.8, 0.03)
    # 옆문 (+x 면 오른쪽 끝)
    f = fr["+x"]
    D_ = length(f[1])
    _lit_decal(sp, f, 1 - 1.9 / D_, 0.0, 1 - 0.7 / D_, 2.6 / H, Mat("#5C7E99", 0.8), LOBBY, 0.8, 0.03)
    sp.lamp(add(_fp(f, 1 - 1.3 / D_, 3.0 / H), (0.15, 0, 0)), WARM_WINDOW, 8)
    # 정문: 청동 틀 → 아래 문 유리 (빛) → 차양 자리 띠 → 위 채광 유리 (빛) → 표장
    f = fr["+y"]
    zc = zw + min(3.4, (zt0 - zw) * 0.62)             # 차양 높이
    _decal(sp, f, du0, 0.0, du1, (zt0 - 0.25 - zw) / H, BRONZE, 0.02, edge=True)
    m = 0.25 / W
    _lit_decal(sp, f, du0 + m, 0.0, du1 - m, (zc - 0.25 - zw) / H, Mat("#5C7E99", 0.8), "#FFE2B0", 0.8, 0.04)
    _grid(sp, (_fp(f, du0 + m, 0.0), mul(f[1], du1 - du0 - 2 * m), (0, 0, zc - 0.25 - zw)), 4, 1, "#c9a868", 0.8,
          0.9, 0.07)
    up0, up1 = (zc + 0.55 - zw) / H, (zt0 - 0.55 - zw) / H
    if (up1 - up0) * H > 1.0:
        pts = sp.on_face(*f, du0 + m, up0, du1 - m, up1)
        pts = [add(p, (0, 0.04, 0)) for p in pts]
        _strip(sp, pts, LOBBY_GLASS, LOBBY, 0.85, "#c9a868", 5, 3)
        _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), 5, 2, "#c9a868", 0.8, 0.9, 0.03)
    # 시세 띠
    _ticker_band(sp, x0, y0, x1, y1, zt0, zt1, FIN_TICK[v], seed=v)
    return zc


def _fin_entrance(sp, v, y1, zc, door_x, zg, depth=1.55):
    """정문 앞: 내민 차양과 기둥 둘, 차양 밑 등, 광장 가로등과 깃대."""
    cx0, cx1 = door_x - 2.3, door_x + 2.3
    sp.box(cx0, y1, zc - 0.3, cx1 - cx0, depth, 0.3, PANEL, top=Mat("#C9CED3", 0.2))
    ef = Sprite.box_faces(cx0, y1, zc - 0.3, cx1 - cx0, depth, 0.3)
    _lit_decal(sp, ef["left"], 0.06, 0.25, 0.94, 0.75, Mat("#C9A04A", 0.5), GOLD_LIGHT, 0.8)
    for x in (cx0 + 0.25, cx1 - 0.25):
        sp.line((x, y1 + depth - 0.2, zg), (x, y1 + depth - 0.2, zc - 0.3), 0.12, "#9aa1aa")
    for x in (door_x - 1.0, door_x + 1.0):
        sp.lamp((x, y1 + depth * 0.5, zc - 0.38), LOBBY, 10)
    # 가로등 (광장 앞 모서리)
    for (x, y) in ((-5.55, 5.55), (5.55, 5.55), (5.55, -1.0)):
        _lamp_post(sp, x, y, 2.7, COOL_WHITE, 12, zg)
    if v in (0, 3):
        # 깃대 셋 (+x 쪽 광장, 깃발은 +y 쪽으로 날린다)
        for i, y in enumerate((0.6, 1.8, 3.0)):
            sp.line((5.6, y, zg), (5.6, y, zg + 5.6), 0.05, "#c9ccd1")
            sp.face(_orient([(5.6, y, zg + 4.5), (5.6, y + 0.65, zg + 4.5), (5.6, y + 0.65, zg + 5.45),
                             (5.6, y, zg + 5.45)], (1, 0, 0)), (BLUE, RED, TEAL)[i % 3], two_sided=True, ao=0)


def _fin_crown_steps(sp, cx, cy, z, sizes, h=1.3, glow=GOLD_LIGHT, mat=BRASS, lit=CROWN_LIT):
    """계단식 왕관: 단마다 네 면에 빛나는 띠. 꼭대기 높이를 돌려준다."""
    for a in sizes:
        sp.box(cx - a / 2, cy - a / 2, z, a, a, h, mat, top=Mat("#A8843A", 0.5))
        for fr in _faces4(cx - a / 2, cy - a / 2, z, a, a, h).values():
            _lit_decal(sp, fr, 0.08, 0.3, 0.92, 0.7, lit, glow, 0.85)
        z += h
    return z


def _pyramid(sp, cx, cy, z, a, apex, mat, glow, alpha=0.5, base=None):
    """빛나는 뿔 지붕 (base: 반시계 바닥 꼭짓점, 없으면 한 변 a인 정사각형)."""
    c = [(p[0], p[1], z) for p in base] if base else \
        [(cx - a / 2, cy - a / 2, z), (cx + a / 2, cy - a / 2, z), (cx + a / 2, cy + a / 2, z), (cx - a / 2, cy + a / 2, z)]
    for i in range(len(c)):
        _lit(sp, [c[i], c[(i + 1) % len(c)], (cx, cy, z + apex)], mat, glow, alpha)
    return z + apex


def _square(cx, cy, half, ang):
    """가운데 (cx, cy), 반 변 half, ang(도)만큼 돌린 정사각형 (반시계)."""
    R = half * math.sqrt(2.0)
    return [(cx + R * math.cos(math.radians(45 + 90 * j + ang)), cy + R * math.sin(math.radians(45 + 90 * j + ang)))
            for j in range(4)]


def _drum_band(sp, c, r, z0, z1, glass, glow, alpha, panes=24, seed=0):
    """원통을 두르는 한 층의 유리 띠: 3D는 빛나는 원통 하나, 2D 밤 불빛은 보이는 쪽 칸마다."""
    p0, p1 = (c[0], c[1], z0), (c[0], c[1], z1)
    sp.cyl(p0, p1, r, glass, caps=False, edge=False)
    sp.mark_light(glow, alpha)
    face = Sprite.facing_angle(p0, p1)
    step = 360.0 / panes
    for i in range(panes):
        a = i * step
        if math.cos(math.radians(a - face)) < 0.12:
            continue
        pts = Sprite.cyl_patch(p0, p1, r, 0.0, 1.0, a - step * 0.42, a + step * 0.42, 0.01)
        sp.poly2([PV(p) for p in pts], glow, None, 0, 0.88 if _pane_on(i, seed, alpha) else 0.1, layer="light")


def _drum_mullions(sp, c, r, z0, z1, n, color, w=0.07, phase=0.0):
    """원통 둘레의 세로 멀리언 n개: 보이는 쪽만 2D에 긋고 모두 3D에 적는다."""
    for i in range(n):
        a = 2 * math.pi * i / n + phase
        d = (math.cos(a), math.sin(a), 0.0)
        p = (c[0] + r * d[0], c[1] + r * d[1])
        _edge(sp, (p[0], p[1], z0), (p[0], p[1], z1), color, w, dot(d, VIEW) > 0.1)


def _fin_bridge(sp, z0, z1, A, B, half, W, glass, frame, mull):
    """대각선(1, -1)으로 마주 선 두 탑(가운데 A·B, 반 변 half)을 잇는 하늘 다리. 끝은 탑 면에서 자른다."""
    ax, ay = A[0] + half, A[1] - half               # A의 마주 보는 모서리 (+x, -y)
    bx, by = B[0] - half, B[1] + half               # B의 마주 보는 모서리 (-x, +y)
    k = W * math.sqrt(2.0)
    base = [(-k - ay, ay), (bx, -k - bx), (bx, by), (k - by, by), (ax, k - ax), (ax, ay)]
    front = _orient([(ax, k - ax, z0), (k - by, by, z0), (k - by, by, z1), (ax, k - ax, z1)], (1, 1, 0))
    back = _orient([(-k - ay, ay, z0), (bx, -k - bx, z0), (bx, -k - bx, z1), (-k - ay, ay, z1)], (-1, -1, 0))
    sp.face([(x, y, z0) for x, y in reversed(base)], frame, normal=(0, 0, -1), ao=0)
    for q, n in ((back, (-1, -1, 0)), (front, (1, 1, 0))):
        sp.face(q, frame, ao=0)
        o, e1, e2 = q[0], sub(q[1], q[0]), sub(q[3], q[0])
        fr = (o, e1, e2)
        L = length(e1)
        pts = sp.on_face(*fr, 0.03, 0.18, 0.97, 0.88)
        _strip(sp, pts, glass, OFFICE, 0.85, "#c3ccd4", max(2, int(L / 1.2)), 5)
        _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), max(2, int(L / 1.2)), 1, mull, 0.7, 0.7, 0.03)
    sp.face([(x, y, z1) for x, y in base], Mat("#9AA3AC", 0.3), normal=(0, 0, 1), ao=0)
    # 받침: 다리 밑 가운데에서 두 탑 모서리로 내려가는 V 버팀대
    m = ((ax + bx) / 2, (ay + by) / 2, z0)
    for (x, y) in ((ax, ay), (bx, by)):
        sp.line(m, (x, y, z0 - 6.5), 0.3, "#b8bec6")


@typed("finance_tower", 12, 12, 64.0, "금융 타워", heights=FIN_HEIGHTS)
def finance_tower(sp: Sprite, v: int):
    """은행·증권거래소 계열의 마천루: 두꺼운 석재 기단부와 높은 유리 현관, 층선이 보이는 유리 커튼월 탑,
    시세 띠, 빛나는 왕관과 첨탑. 다섯 모양은 실루엣이 다르다 — 계단식(v0), 비틀린 판(v1), 쌍둥이 탑과 하늘 다리(v2),
    원통(v3), 하늘 로비가 있는 판상(v4)."""
    zg = 0.3
    zp = (8.3, 8.3, 7.3, 8.3, 8.3)[v]
    glass, frame, mull = FIN_GLASS[v], FIN_FRAME[v], FIN_MULL[v]
    top_mat = Mat("#8E959D", 0.3)
    px0, py0, px1, py1 = (-5.4, -5.4, 5.0, 5.0) if v == 2 else (-5.5, -5.5, 5.2, 4.0)
    door_x = (0.0, 0.0, 2.4, 0.0, 0.2)[v]
    sp.contact_shadow(0, 0, 5.9, 5.9, 0.5)
    sp.box(-5.95, -5.95, 0, 11.9, 11.9, zg, GRANITE, top=GRANITE_TOP)
    zc = _fin_podium(sp, v, px0, py0, px1, py1, zg, zp, door_x)
    fh = 4.0
    if v == 0:
        # 계단식으로 물러나는 탑 셋 + 단마다 금빛 띠 → 금빛 계단 왕관 → 첨탑
        cx, cy = -0.3, -1.0
        z = zp
        for i, (half, nf) in enumerate(((4.0, 6), (3.3, 4), (2.6, 2))):
            z1 = _glass_tower(sp, cx - half, cy - half, cx + half, cy + half, z, nf, fh, frame, top_mat, glass,
                              frame_col="#c3ccd4", mull=mull, seed=i * 4)
            for fr in _faces4(cx - half, cy - half, z, 2 * half, 2 * half, z1 - z).values():
                H = z1 - z
                _lit_decal(sp, fr, 0.0, 1 - 0.32 / H, 1.0, 1 - 0.08 / H, CROWN_LIT, GOLD_LIGHT, 0.75, 0.04)
            z = z1
        z = _fin_crown_steps(sp, cx, cy, z, (4.0, 3.0), 1.3)
        z = _pyramid(sp, cx, cy, z, 2.0, 1.8, BRASS, GOLD_LIGHT, 0.55)
        sp.glow((cx, cy, z - 2.0), 46, GOLD_LIGHT, 0.4)
        _spire(sp, (cx, cy), z - 0.2, FIN_HEIGHTS[0], 0.24)
    elif v == 1:
        # 층마다 4.5°씩 돌아가는 판: 바닥판(옆면이 층 띠) → 유리 띠 → 멀리언, 꼭대기는 돌린 청록 왕관
        cx, cy, half = -0.3, -0.9, 3.55
        z = zp
        nf = 11
        for k in range(nf):
            base = _square(cx, cy, half, 4.5 * k)
            sp.prism(base, z, fh, frame, top=top_mat)
            _curtain_faces(sp, _side_frames(base, z, fh), z, fh, 1, glass, OFFICE, "#e3e8ea", mull, seed=1, k0=k)
            z += fh
        base = _square(cx, cy, half - 0.7, 4.5 * nf)
        sp.prism(base, z, 2.4, Mat("#2F8F8A", 0.4), top=Mat("#3B6E6A", 0.3))
        for fr in _side_frames(base, z, 2.4):
            _lit_decal(sp, fr, 0.08, 0.25, 0.92, 0.75, Mat("#7FD6CC", 0.4), CYAN_LIGHT, 0.85)
        z += 2.4
        z = _pyramid(sp, cx, cy, z, 0, 2.6, Mat("#9FD8D0", 0.5), CYAN_LIGHT, 0.45,
                     base=_square(cx, cy, half - 0.9, 4.5 * nf + 4.5))
        sp.glow((cx, cy, z - 2.5), 44, CYAN_LIGHT, 0.4)
        _spire(sp, (cx, cy), z - 0.3, FIN_HEIGHTS[1], 0.22)
    elif v == 2:
        # 쌍둥이 탑 (화면 왼쪽 A, 오른쪽 B) + 가운데 높이의 하늘 다리 + 탑마다 빛나는 첨탑
        A, B, half = (-2.7, 2.7), (2.7, -2.7), 2.0
        tops = []
        for (cx, cy) in (A, B):
            z = _glass_tower(sp, cx - half, cy - half, cx + half, cy + half, zp, 8, fh, frame, top_mat, glass,
                             frame_col="#dfe3e6", mull=mull, seed=3 + int(cx), pane=1.3)
            h2 = half - 0.45
            z = _glass_tower(sp, cx - h2, cy - h2, cx + h2, cy + h2, z, 3, fh, frame, top_mat, glass,
                             frame_col="#dfe3e6", mull=mull, seed=5 + int(cx), pane=1.3)
            tops.append(z)
            sp.cyl((cx, cy, z), (cx, cy, z + 1.6), 1.2, Mat("#C9B48A", 0.4), cap_mat=Mat("#A89670", 0.3))
            cyl_ring(sp, (cx, cy, z), (cx, cy, z + 1.6), 1.2, 0.3, 0.75, CROWN_LIT, GOLD_LIGHT, 0.85)
            sp.frustum((cx, cy, z + 1.6), (cx, cy, z + 4.4), 1.0, 0.25, Mat("#D9DCDF", 0.5), bands=[0.35, 0.7],
                       band_color="#9aa1aa")
            sp.glow((cx, cy, z + 1.0), 30, GOLD_LIGHT, 0.4)
            _spire(sp, (cx, cy), z + 4.3, FIN_HEIGHTS[2], 0.16)
        _fin_bridge(sp, zp + 5 * fh, zp + 5 * fh + 3.4, A, B, half, 0.8, glass, frame, mull)
    elif v == 3:
        # 원통 유리탑: 흰 몸통 원통 → 층마다 빛나는 유리 띠 → 멀리언 → 등불 원통 왕관 → 첨탑
        cx, cy, r = -0.3, -0.9, 4.1
        nf = 11
        ztop = zp + nf * fh
        sp.cyl((cx, cy, zp), (cx, cy, ztop + 0.3), r, frame, cap_mat=top_mat)
        for k in range(nf):
            z0 = zp + k * fh
            _drum_band(sp, (cx, cy), r + 0.03, z0 + 0.55, z0 + fh - 0.2, glass, OFFICE, _floor_alpha(k, 0, 7), 24,
                       k * 3 + 1)
        _drum_mullions(sp, (cx, cy), r + 0.06, zp, ztop, 24, mull, 0.07, math.pi / 24)
        z = ztop + 0.3
        sp.cyl((cx, cy, z), (cx, cy, z + 3.6), 3.0, Mat("#3A5F86", 0.8), cap_mat=top_mat)
        cyl_ring(sp, (cx, cy, z), (cx, cy, z + 3.6), 3.0, 0.15, 0.85, Mat("#E8C46A", 0.5), GOLD_LIGHT, 0.7)
        _drum_mullions(sp, (cx, cy), 3.05, z, z + 3.6, 16, "#f3e2b0", 0.08)
        z += 3.6
        sp.frustum((cx, cy, z), (cx, cy, z + 2.4), 3.2, 1.0, PANEL, cap_mat=top_mat, bands=[0.5])
        sp.glow((cx, cy, z - 1.6), 48, GOLD_LIGHT, 0.45)
        _spire(sp, (cx, cy), z + 2.3, FIN_HEIGHTS[3], 0.3)
    else:
        # 판상 탑 (긴 면이 +y): 아래 6층 → 나무가 있는 하늘 로비 (두 층 높이, 안으로 들인 유리) → 위 4층 → 내민 지붕판과
        # 시세 띠 → 헬기장 표시와 안테나 탑
        x0, y0, x1, y1 = -4.6, -4.7, 4.3, 1.3
        z = _glass_tower(sp, x0, y0, x1, y1, zp, 6, fh, frame, top_mat, glass, frame_col="#59616b", mull=mull,
                         seed=2, pane=1.5)
        zl0, zl1 = z, z + 6.0
        ins = 0.8
        sp.box(x0 + ins, y0 + ins, zl0, x1 - x0 - 2 * ins, y1 - y0 - 2 * ins, zl1 - zl0, Mat("#6B5A48", 0.3),
               top=top_mat)
        lf = list(_faces4(x0 + ins, y0 + ins, zl0, x1 - x0 - 2 * ins, y1 - y0 - 2 * ins, zl1 - zl0).values())
        for i, fr in enumerate(lf):
            L = length(fr[1])
            pts = sp.on_face(*fr, 0.02, 0.04, 0.98, 0.96)
            _strip(sp, pts, Mat("#4F7393", 0.85), WARM_WINDOW, 0.9, "#59616b", max(2, int(L / 1.6)), 9 + i)
            _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), max(2, int(L / 1.6)), 2, "#2f343b", 0.7,
                  0.8, 0.03)
        # 하늘 로비 앞 화단과 나무 (+y·+x 둘레의 들인 자리)
        for (tx, ty) in ((-3.0, y1 - 0.42), (0.2, y1 - 0.42), (x1 - 0.42, -2.6)):
            sp.box(tx - 0.35, ty - 0.3, zl0, 0.7, 0.6, 0.4, Mat("#8a7c68"), top=Mat("#5b4636"))
            sp.tree((tx, ty, zl0 + 0.4), 2.6, 0.75)
        sp.glow(((x0 + x1) / 2, (y0 + y1) / 2, zl0 + 3.0), 60, WARM_WINDOW, 0.35)
        # 모서리 기둥 넷 (하늘 로비를 지나 위층을 받친다)
        for (qx, qy) in ((x0, y0), (x1 - 0.55, y0), (x0, y1 - 0.55), (x1 - 0.55, y1 - 0.55)):
            sp.box(qx, qy, zl0, 0.55, 0.55, zl1 - zl0, frame, top=frame)
        z = _glass_tower(sp, x0, y0, x1, y1, zl1, 4, fh, frame, top_mat, glass, frame_col="#59616b", mull=mull,
                         seed=6, pane=1.5)
        _ticker_band(sp, x0, y0, x1, y1, z, z + 0.9, FIN_TICK[4], seed=3, out=0.25)
        z += 0.9
        sp.box(x0 - 0.25, y0 - 0.25, z, x1 - x0 + 0.5, y1 - y0 + 0.5, 0.3, Mat("#4A525C", 0.3), top=Mat("#5D646C"))
        z += 0.3
        # 헬기장 (지붕 위 둥근 판과 H)
        hx, hy = -1.4, -1.7
        sp.cyl((hx, hy, z), (hx, hy, z + 0.25), 2.2, DARK, cap_mat=Mat("#3B4049", 0.2))
        sp.ring3((hx, hy, z + 0.27), 1.75, "#E9C24A", 0.12, front_only=False, seg=24)
        for dx in (-0.45, 0.45):
            sp.line((hx + dx, hy - 0.6, z + 0.27), (hx + dx, hy + 0.6, z + 0.27), 0.16, "#ECE7DC")
        sp.line((hx - 0.45, hy, z + 0.27), (hx + 0.45, hy, z + 0.27), 0.16, "#ECE7DC")
        for (lx, ly) in ((hx + 2.0, hy), (hx - 2.0, hy), (hx, hy + 2.0), (hx, hy - 2.0)):
            sp.lamp((lx, ly, z + 0.32), "#7FE3DA", 6)
        # 안테나 탑과 접시 (앞 오른쪽)
        mx, my = 2.9, -0.4
        top = FIN_HEIGHTS[4]
        sp.truss((mx, my, z), (mx, my, top - 1.0), 0.5, "#9aa1aa", 0.05, 6, side=(1, -1, 0))
        sp.line((mx, my, top - 1.0), (mx, my, top - 0.12), 0.06, "#9aa1aa")
        sp.lamp((mx, my, top - 0.1), RED_LIGHT, 7)
        sp.disc((mx + 0.4, my + 0.5, z + 2.2), norm((0.6, 1.0, 0.5)), 0.8, WHITE, back=STEEL)
    _fin_entrance(sp, v, py1, zc, door_x, zg, 0.8 if v == 2 else 1.55)


# ═════════════════════════════════════════════════════════════════════
# 고층 호텔
# ═════════════════════════════════════════════════════════════════════

PLAZA = Mat("#B3AB9C")               # 호텔 앞 광장 포장
PLAZA_TOP = Mat("#BDB5A6")
H_SLAB = Mat("#F1EEE6", 0.1)         # 층 바닥판 (발코니 끝)
H_GLASS = Mat("#2C4D63", 0.85)       # 객실 유리
BRONZE_GLASS = Mat("#5B4D3D", 0.85)
WATER = Mat("#5FB7D9", 0.7)
CARPET = Mat("#A8322C", 0.1)
SOIL = Mat("#5b4636")
PLANTER = Mat("#8a7c68")
LAWN = Mat("#5E8C4A")
RAIL_GLASS = "#cfe6ff"
RAIL = "#e3e7ea"
HOTEL_HEIGHTS = [52.0, 51.0, 54.0, 53.0, 54.0]


def _cone_patch(c0, c1, r0, r1, s0, s1, a0, a1, lift=0.02):
    """원뿔대 겉면의 작은 사각형 (축 비율 s, 각도 a[도])."""
    axis = sub(c1, c0)
    u, w = basis(axis)

    def at(s, ang):
        t = math.radians(ang)
        radial = add(mul(u, math.cos(t)), mul(w, math.sin(t)))
        return add(add(c0, mul(axis, s)), mul(radial, r0 + (r1 - r0) * s + lift))
    return [at(s0, a0), at(s0, a1), at(s1, a1), at(s1, a0)]


def _front_arc(c, r, z, k=18):
    """수평 원의 앞(카메라 쪽) 반 둘레."""
    return [(c[0] + r * math.cos(math.radians(-45 + 180 * i / k)), c[1] + r * math.sin(math.radians(-45 + 180 * i / k)), z)
            for i in range(k + 1)]


def _room_band(sp, c, r0, r1, z0, z1, glass, glow, alpha, panes=24, seed=0, mull=None):
    """객실 한 층의 둥근 유리 띠: 3D는 빛나는 원뿔대 하나, 2D는 보이는 쪽 칸마다 밤 불빛과 멀리언."""
    p0, p1 = (c[0], c[1], z0), (c[0], c[1], z1)
    sp.frustum(p0, p1, r0, r1, glass, caps=False, edge=False)
    sp.mark_light(glow, alpha)
    face = Sprite.facing_angle(p0, p1)
    step = 360.0 / panes
    for i in range(panes):
        a = i * step
        cs = math.cos(math.radians(a - face))
        if cs < 0.12:
            continue
        pts = _cone_patch(p0, p1, r0, r1, 0.0, 1.0, a - step * 0.42, a + step * 0.42, 0.01)
        sp.poly2([PV(p) for p in pts], glow, None, 0, 0.88 if _pane_on(i, seed, alpha) else 0.1, layer="light")
        if mull and cs > 0.2:
            q = _cone_patch(p0, p1, r0, r1, 0.0, 1.0, a + step / 2, a + step / 2, 0.02)
            sp.path2("M%.2f,%.2fL%.2f,%.2f" % (*PV(q[0]), *PV(q[3])), "none", mull, 0.5, 0.75)


def _glass_ring(sp, c, r, z0, z1, alpha=0.22):
    """둥근 유리 난간: 3D는 비치는 원통 하나, 2D는 앞쪽 반만 옅게 칠하고 위 손잡이를 긋는다."""
    g = iso._Glass(RAIL_GLASS, alpha)
    sp._rec(("fru", (c[0], c[1], z0), (c[0], c[1], z1), r, r, g, False, g, (), None, None))
    lo, hi = _front_arc(c, r, z0), _front_arc(c, r, z1)
    sp.poly2([PV(p) for p in lo + hi[::-1]], hexc(lit(rgb(RAIL_GLASS), norm((0.6, 0.6, 0.2)), 0.6)), None, 0,
             alpha + 0.1)
    sp.path2("M" + " L".join("%.2f,%.2f" % PV(p) for p in hi), "none", RAIL, 0.5, 0.9)


def _glass_wall(sp, pts3, alpha=0.2):
    """곧은 유리 난간 판 (3D는 비치는 판, 2D는 옅은 판과 위 손잡이)."""
    sp._rec(("poly", list(pts3), iso._Glass(RAIL_GLASS, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if dot(n, VIEW) <= 0:
        n = mul(n, -1)
    sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(RAIL_GLASS), n, 0.6)), None, 0, alpha + 0.1)
    a, b = sorted(pts3, key=lambda p: -p[2])[:2]
    sp.path2("M%.2f,%.2fL%.2f,%.2f" % (*PV(a), *PV(b)), "none", RAIL, 0.5, 0.9)


def _round_floors(sp, c, z0, nf, fh, r0, r_top, slab_out, glass, slab, seed=0, rails=True, panes=24, glow=WARM_WINDOW,
                  mull="#c9d3db", dark=0.0):
    """둥근 객실 층: 층마다 바닥판(발코니) → 빛나는 유리 띠 → 유리 난간. 반지름은 r0에서 r_top으로 줄어든다.
    3D 멀리언은 맨 아래에서 맨 위까지 이어 긋는다 (뒤쪽 것도 적는다). 맨 위 바닥 높이를 돌려준다."""
    def rad(k):
        return r0 + (r_top - r0) * (k / max(1, nf - 1))
    for k in range(nf):
        z = z0 + k * fh
        r, rn = rad(k), rad(min(nf - 1, k + 1))
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.24), r + slab_out, slab, cap_mat=Mat("#D8D9D4", 0.15))
        a = (0.75, 0.35, 0.7, 0.15, 0.8, 0.45, 0.65, 0.2, 0.55, 0.75)[(k * 3 + seed) % 10]
        _room_band(sp, c, r, rn if k < nf - 1 else r, z + 0.24, z + fh, glass, glow, max(0.1, a - dark), panes,
                   seed + k * 3, mull)
        if rails:
            _glass_ring(sp, c, r + slab_out - 0.06, z + 0.24, z + 1.15)
    for i in range(16):
        t = 2 * math.pi * (i + 0.5) / 16
        p0 = (c[0] + (r0 + 0.03) * math.cos(t), c[1] + (r0 + 0.03) * math.sin(t), z0)
        p1 = (c[0] + (r_top + 0.03) * math.cos(t), c[1] + (r_top + 0.03) * math.sin(t), z0 + nf * fh)
        sp._rec(("line", [p0, p1], 0.07, mull, False))
    return z0 + nf * fh


def _dome_lounge(sp, c, r, h, glow=WARM_WINDOW, mat=Mat("#6F9CBF", 0.9), rib_col="#dfe9f2", ribs=8):
    """옥상 유리 돔 라운지: 2D는 짙은 유리 돔과 갈비, 3D는 비치는 껍질·갈비·밤에 빛나는 바닥과 가운데 바."""
    with sp._nest():
        sil = sp.dome(c, r, h, mat)
    sp.glass_shell(c, r, r, h, c[2], color="#bcd8ee", alpha=0.3)
    sp._rec(("lpoly", [(c[0] + r * 0.92 * math.cos(2 * math.pi * k / 16), c[1] + r * 0.92 * math.sin(2 * math.pi * k / 16),
                        c[2] + 0.04) for k in range(16)], glow, 0.55))
    sp._rec(("fru", (c[0], c[1], c[2]), (c[0], c[1], c[2] + 1.0), r * 0.25, r * 0.25, Mat("#C9A04A", 0.5), True,
             Mat("#3B4049", 0.3), (), None, (glow, 0.6)))
    for i in range(ribs):
        th = 2 * math.pi * (i + 0.5) / ribs
        pts = [(c[0] + r * 1.005 * math.cos(ph) * math.cos(th), c[1] + r * 1.005 * math.cos(ph) * math.sin(th),
                c[2] + h * 1.005 * math.sin(ph)) for ph in [k * math.pi / 10 for k in range(6)]]
        if dot((math.cos(th), math.sin(th), 0.0), VIEW) < -0.15:
            sp._rec(("line", pts, 0.06, rib_col, False))
        else:
            sp.polyline3(pts, rib_col, 0.06, 0.8)
    with sp._nest():
        for t in (0.42, 0.78):
            sp.ring3((c[0], c[1], c[2] + h * t), r * math.sqrt(1 - t * t) * 1.005, rib_col, 0.05, opacity=0.7)
    sp.poly2(sil, glow, None, 0, 0.5, layer="light")
    sp.glow(add(c, (0, 0, h * 0.45)), r * S * 1.1, glow, 0.35)
    return c[2] + h


def _blade_sign(sp, x0, y0, z0, w, dep, h, mat, glow, face="+y", rows=7):
    """세로 간판: 얇은 상자, 넓은 두 면에 빛나는 판과 글자 줄 (보이지 않는 면은 3D에만)."""
    sp.box(x0, y0, z0, w, dep, h, mat, top=mat)
    fr = _faces4(x0, y0, z0, w, dep, h)
    for key in ((face, "-y") if face == "+y" else (face, "-x")):
        f = fr[key]
        pts = _lit_decal(sp, f, 0.16, 0.04, 0.84, 0.96, Mat("#F4E7C2", 0.3), glow, 0.92, 0.03)
        _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), 1, rows, hexc(scale(mat.albedo, 0.7)), 1.2, 0.9,
              0.02)


def _hotel_podium(sp, v, x0, y0, x1, y1, zg, zp, ex, slab, accent, aglow):
    """로비 기단: 흰 상자 → 1층 높은 로비 유리와 2층 창 띠 (앞 두 면은 넓게, 뒤 두 면은 좁게) → 처마판과 이름 띠."""
    W, D = x1 - x0, y1 - y0
    zl, ze = zg + 3.1, zp - 0.4                       # 1층 위, 처마 아래
    sp.box(x0, y0, zg, W, D, ze - zg, WHITE, top=SILVER)
    fr = _faces4(x0, y0, zg, W, D, ze - zg)
    H = ze - zg
    for i, (key, f) in enumerate(fr.items()):
        L = length(f[1])
        front = key in ("+y", "+x")
        nc = max(3, int(L / (1.5 if front else 2.4)))
        if front:
            spans = [(0.03, 0.97)]
            if key == "+y":                            # 정문 자리 (밝은 문 유리를 따로 단다)
                du0, du1 = (x1 - ex - 1.3) / W, (x1 - ex + 1.3) / W
                spans = [(0.03, du0 - 0.02), (du1 + 0.02, 0.97)]
            for (a, b) in spans:
                pts = sp.on_face(*f, a, 0.04, b, (zl - 0.15 - zg) / H)
                n = max(2, int(nc * (b - a)))
                _strip(sp, pts, LOBBY_GLASS, WARM_WINDOW, 0.8, "#e6e8ea", n, i + v)
                _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), n, 1, "#e6e8ea", 0.7, 0.9, 0.03)
        pts = sp.on_face(*f, 0.04, (zl + 0.45 - zg) / H, 0.96, (ze - 0.35 - zg) / H)
        _strip(sp, pts, LOBBY_GLASS, WARM_WINDOW, 0.6 if front else 0.35, "#e6e8ea", nc, i * 3 + v)
        _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), nc, 1, "#e6e8ea", 0.7, 0.9, 0.03)
    # 정문 유리 (밝은 불빛)
    f = fr["+y"]
    du0, du1 = (x1 - ex - 1.2) / W, (x1 - ex + 1.2) / W
    _lit_decal(sp, f, du0, 0.0, du1, (zl - 0.15 - zg) / H, Mat("#5C7E99", 0.8), "#FFE2B0", 0.85, 0.04)
    # 처마판 + 이름 띠 (앞 두 면)
    sp.box(x0 - 0.15, y0 - 0.15, ze, W + 0.3, D + 0.3, zp - ze, slab, top=Mat("#C9CED3", 0.2))
    ef = _faces4(x0 - 0.15, y0 - 0.15, ze, W + 0.3, D + 0.3, zp - ze)
    pts = _lit_decal(sp, ef["+y"], 0.06, 0.2, 0.42, 0.8, accent, aglow, 0.85)
    _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), 6, 1, "#F8F4EA", 1.0, 0.9, 0.02)
    _lit_decal(sp, ef["+x"], 0.55, 0.25, 0.95, 0.75, accent, aglow, 0.85)


def _hotel_entrance(sp, v, ex, y1, zg, accent):
    """정문: 반원 차양(기둥 둘, 밑 등), 붉은 깔개, 화분 나무, 광장 가로등."""
    can = [(ex + 2.0 * math.cos(math.pi * i / 10), y1 + 1.85 * math.sin(math.pi * i / 10)) for i in range(11)]
    sp.face([(ex - 0.6, y1, zg + 0.02), (ex + 0.6, y1, zg + 0.02), (ex + 0.6, 5.85, zg + 0.02),
             (ex - 0.6, 5.85, zg + 0.02)], CARPET, normal=(0, 0, 1), ao=0)
    for x in (ex - 1.45, ex + 1.45):
        sp.line((x, y1 + 1.15, zg), (x, y1 + 1.15, zg + 2.85), 0.1, "#c9ccd1")
    sp.prism(can, zg + 2.85, 0.24, H_SLAB, top=Mat("#D8D9D4", 0.15))
    cf = [((can[i][0], can[i][1], zg + 2.85), (can[i + 1][0] - can[i][0], can[i + 1][1] - can[i][1], 0.0), (0, 0, 0.24))
          for i in range(len(can) - 1)]
    for f in cf:
        if _seen(_nrm(f)):
            _lit_decal(sp, f, 0.0, 0.25, 1.0, 0.75, accent, GOLD_LIGHT, 0.6, 0.02)
    for x in (ex - 0.8, ex + 0.8):
        sp.lamp((x, y1 + 0.9, zg + 2.78), WARM_WINDOW, 10)
    for x in (ex - 2.55, ex + 2.55):
        sp.cyl((x, 4.75, zg), (x, 4.75, zg + 0.55), 0.38, Mat("#A39581"), cap_mat=SOIL)
        sp.tree((x, 4.75, zg + 0.55), 1.7, 0.55)
    for (x, y) in ((-5.5, 5.5), (5.55, 5.55), (5.55, -2.2)):
        _lamp_post(sp, x, y, 2.6, WARM_WINDOW, 11, zg)


def _capsule_floors(sp, c, a, r, z0, nf, fh, glass, slab, dep=0.9, seed=0, glow=WARM_WINDOW):
    """캡슐(가운데 곧은 몸 + 둥근 두 끝) 객실 층. 곧은 긴 면(±y)에는 발코니 판과 막힌 난간, 둥근 끝은 유리 띠.
    그림 순서 (층마다): 뒤 발코니 → 끝 바닥판 둘 → 앞 발코니 판 → 끝 유리 띠 둘 → 곧은 면 유리 → 앞 난간.
    곧은 면 멀리언은 2D에는 층마다, 3D에는 면마다 하나로 적는다."""
    cx, cy = c
    xa, xb = cx - a, cx + a
    rim = Mat("#D8D9D4", 0.15)
    zt = z0 + nf * fh
    for k in range(nf):
        z = z0 + k * fh
        al = (0.75, 0.35, 0.7, 0.15, 0.8, 0.45, 0.65, 0.2, 0.55, 0.75)[(k * 3 + seed) % 10]
        # 뒤(-y) 발코니와 난간
        sp.box(xa, cy - r - dep, z, xb - xa, dep + 0.05, 0.24, slab, top=rim)
        sp.box(xa, cy - r - dep, z + 0.24, xb - xa, 0.14, 0.95, slab, top=rim)
        # 둥근 끝 바닥판 (뒤 → 앞)
        for ex_ in (xa, xb):
            sp.cyl((ex_, cy, z), (ex_, cy, z + 0.24), r + 0.15, slab, cap_mat=rim)
        # 앞(+y) 발코니 판
        sp.box(xa, cy + r - 0.05, z, xb - xa, dep + 0.05, 0.24, slab, top=rim)
        # 둥근 끝 유리 띠
        for i, ex_ in enumerate((xa, xb)):
            _room_band(sp, (ex_, cy), r, r, z + 0.24, z + fh, glass, glow, al if i else max(0.12, al - 0.3), 16,
                       seed + k * 5 + i, "#c9d3db")
        # 곧은 면 유리 (앞은 그림에도, 뒤는 3D에만) + 2D 멀리언
        nc = max(2, int((xb - xa) / 1.1))
        for yy, sgn in ((cy + r, 1), (cy - r, -1)):
            pts = [(xb, yy, z + 0.24), (xa, yy, z + 0.24), (xa, yy, z + fh), (xb, yy, z + fh)]
            pts = _orient(pts, (0, sgn, 0))
            _strip(sp, pts, glass, glow, al, "#c9d3db", nc, seed + k * 7 + sgn, lo=1.45 / (fh - 0.24))
            if sgn > 0:
                with sp._nest():
                    sp.panel_grid(add(pts[0], (0, 0.03, 0)), sub(pts[1], pts[0]), sub(pts[3], pts[0]), nc, 1, "#c9d3db",
                                  0.6, 0.75)
        # 앞 난간 (막힌 흰 난간 + 위 손잡이)
        sp.box(xa, cy + r + dep - 0.14, z + 0.24, xb - xa, 0.14, 0.95, slab, top=rim)
    for yy, sgn in ((cy + r, 1), (cy - r, -1)):
        o = (xb if sgn > 0 else xa, yy + 0.04 * sgn, z0)
        sp._rec(("grid", o, ((xa - xb) * sgn, 0.0, 0.0), (0.0, 0.0, zt - z0), max(2, int((xb - xa) / 1.1)), 1,
                 "#c9d3db", 0.6 / S))
    return zt


@typed("hotel_tower", 12, 12, 52.0, "고층 호텔", heights=HOTEL_HEIGHTS)
def hotel_tower(sp: Sprite, v: int):
    """달 관광객을 받는 호화 호텔탑: 유리 로비 기단과 반원 차양, 층마다 발코니 판이 두른 둥근 객실탑,
    옥상의 유리 돔 라운지나 전망대, 빛나는 세로 간판. 다섯 모양 — 원통과 돔(v0), 캡슐 판상과 옥상 수영장(v1),
    세 단 웨딩케이크(v2), 가는 줄기 위 전망 원반(v3), 위로 좁아지는 원뿔대와 등불 왕관(v4)."""
    zg, zp = 0.25, 5.6
    fh = 3.3
    glass = (H_GLASS, BRONZE_GLASS, Mat("#2F5878", 0.85), Mat("#2E5F66", 0.85), Mat("#28456A", 0.85))[v]
    slab = (H_SLAB, Mat("#E8D9B5", 0.2), H_SLAB, Mat("#DCE4E2", 0.1), Mat("#E9E0CC", 0.15))[v]
    accent = (Mat("#C9A04A", 0.5), Mat("#2F8F8A", 0.4), Mat("#C4566A", 0.4), Mat("#6A4FA0", 0.4), MAROON)[v]
    aglow = (GOLD_LIGHT, CYAN_LIGHT, "#FF8AA0", "#C9A0FF", "#FF9C8A")[v]
    top = HOTEL_HEIGHTS[v]
    px0, py0, px1, py1 = -5.5, -5.5, 5.1, 3.7
    ex = (1.8, 1.6, 2.0, 1.8, 1.4)[v]
    sp.contact_shadow(0, 0, 5.9, 5.9, 0.5)
    sp.box(-5.95, -5.95, 0, 11.9, 11.9, zg, PLAZA, top=PLAZA_TOP)
    _hotel_podium(sp, v, px0, py0, px1, py1, zg, zp, ex, slab, accent, aglow)
    if v == 0:
        # 둥근 객실탑 (층마다 발코니) → 옥상판 → 유리 돔 라운지 → 첨탑, 앞에 세로 간판
        c = (-0.4, -1.1)
        z = _round_floors(sp, c, zp, 12, fh, 3.7, 3.7, 0.6, glass, slab, seed=v)
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.45), 4.45, slab, cap_mat=Mat("#BFC5CB", 0.2))
        z += 0.45
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.3), 3.25, STEEL, cap_mat=DARK)
        zt = _dome_lounge(sp, (c[0], c[1], z + 0.3), 3.0, 2.8)
        sp.frustum((c[0], c[1], zt - 0.1), (c[0], c[1], top - 0.15), 0.18, 0.04, STEEL)
        sp.lamp((c[0], c[1], top - 0.1), RED_LIGHT, 7)
        _glass_ring(sp, c, 4.35, z, z + 0.9)
        _blade_sign(sp, 1.15, 2.98, zp + fh + 0.4, 1.1, 0.34, 7 * fh, accent, aglow)
    elif v == 1:
        # 캡슐 판상 (긴 면에 발코니, 둥근 끝은 유리) → 옥상: 수영장과 갑판, 유리 바 정자, 전망 난간, 돛대
        c, a, r = (-0.3, -1.25), 2.2, 2.7
        cx, cy = c
        z = _capsule_floors(sp, c, a, r, zp, 12, fh, glass, slab, seed=3)
        roof = Mat("#BFC5CB", 0.2)
        for ex_ in (cx - a, cx + a):
            sp.cyl((ex_, cy, z), (ex_, cy, z + 0.4), r + 0.2, slab, cap_mat=roof)
        sp.box(cx - a, cy - r - 0.2, z, 2 * a, 2 * r + 0.4, 0.4, slab, top=roof)
        z += 0.4
        # 유리 바 정자 (뒤 -x 끝)
        bx0, by0 = cx - a - 1.9, cy - 1.6
        sp.box(bx0, by0, z, 2.6, 3.2, 2.4, Mat("#3B5A6E", 0.85), top=Mat("#D8D9D4", 0.15))
        for i, fr in enumerate(_faces4(bx0, by0, z, 2.6, 3.2, 2.4).values()):
            pts = sp.on_face(*fr, 0.04, 0.05, 0.96, 0.86)
            _strip(sp, pts, Mat("#4F7A99", 0.85), WARM_WINDOW, 0.9, "#e6e8ea", 3, 4 + i)
        sp.box(bx0 - 0.2, by0 - 0.2, z + 2.4, 3.0, 3.6, 0.2, slab, top=roof)
        sp.glow((bx0 + 1.3, by0 + 1.6, z + 1.2), 26, WARM_WINDOW, 0.4)
        # 옥상 수영장 (가운데) 과 갑판 의자
        qx0, qx1, qy0, qy1 = cx - 0.6, cx + a + 0.6, cy - 1.2, cy + 1.3
        sp.box(qx0 - 0.15, qy0 - 0.15, z, qx1 - qx0 + 0.3, qy1 - qy0 + 0.3, 0.15, Mat("#E8E2D6"), top=Mat("#E8E2D6"))
        _lit(sp, [(qx0, qy0, z + 0.16), (qx1, qy0, z + 0.16), (qx1, qy1, z + 0.16), (qx0, qy1, z + 0.16)], WATER,
             "#5FC8F0", 0.55)
        for k in range(3):
            sp.box(qx0 + 0.3 + k * 1.0, qy1 + 0.35, z, 0.5, 0.8, 0.18, WHITE)
        # 전망 난간 (앞 긴 면과 둥근 앞 끝)
        _glass_wall(sp, [(cx + a, cy + r + 0.05, z), (cx - a, cy + r + 0.05, z), (cx - a, cy + r + 0.05, z + 1.0),
                         (cx + a, cy + r + 0.05, z + 1.0)])
        # 돛대 (앞 +x 끝)
        mx, my = cx + a + 1.2, cy - 0.4
        sp.line((mx, my, z), (mx, my, top - 0.15), 0.1, "#9aa1aa")
        sp.lamp((mx, my, top - 0.1), RED_LIGHT, 7)
        # 세로 간판 (+x 둥근 끝 바깥)
        _blade_sign(sp, cx + a + r + 0.2, cy - 0.55, zp + fh + 0.4, 0.34, 1.1, 7 * fh, accent, aglow, face="+x")
    elif v == 2:
        # 세 단 웨딩케이크: 단마다 둥근 객실층, 물러난 테라스에 잔디와 산울타리 → 꼭대기 작은 돔 → 첨탑
        c = (-0.4, -0.8)
        z = zp
        tiers = ((4.3, 5), (3.0, 4), (2.1, 3))
        later = []
        for i, (r, nf) in enumerate(tiers):
            z = _round_floors(sp, c, z, nf, fh, r, r, 0.5, glass, slab, seed=v + i * 4)
            ro = r + 0.55
            sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.4), ro, slab, cap_mat=Mat("#BFC5CB", 0.2))
            z += 0.4
            if i < 2:
                sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.12), ro - 0.15, PLANTER, cap_mat=LAWN)
                later.append((ro, tiers[i + 1][0] + 0.5, z, i))
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.25), 2.2, STEEL, cap_mat=DARK)
        zt = _dome_lounge(sp, (c[0], c[1], z + 0.25), 1.95, 1.9)
        sp.frustum((c[0], c[1], zt - 0.1), (c[0], c[1], top - 0.15), 0.16, 0.04, STEEL, bands=[0.3])
        sp.lamp((c[0], c[1], top - 0.1), RED_LIGHT, 7)
        _glass_ring(sp, c, 2.59, z, z + 0.9)
        for (ro, rn, zz, i) in reversed(later):
            sp.frustum((c[0], c[1], zz), (c[0], c[1], zz + 0.6), ro - 0.2, ro - 0.25, Mat("#4C8B41"), caps=False)
            for ang in ((22, 68) if i == 0 else (45,)):
                t = math.radians(ang)
                rr = (ro + rn) / 2 + 0.05
                sp.tree((c[0] + rr * math.cos(t), c[1] + rr * math.sin(t), zz + 0.12), 1.9, 0.5)
            _glass_ring(sp, c, ro - 0.06, zz, zz + 0.9)
        _blade_sign(sp, 1.0, 3.35, zp + 0.9, 1.0, 0.32, 4 * fh, accent, aglow)
    elif v == 3:
        # 가는 줄기 탑 → 내민 전망 원반 (아래 깔때기 · 빛나는 유리 띠 · 지붕) → 작은 돔 → 돛대
        c = (-0.3, -0.6)
        z = _round_floors(sp, c, zp, 11, fh, 3.2, 3.2, 0.5, glass, slab, seed=v)
        sp.frustum((c[0], c[1], z), (c[0], c[1], z + 1.4), 3.4, 5.1, PANEL, caps=False)
        z += 1.4
        cyl_ring(sp, (c[0], c[1], z), (c[0], c[1], z + 0.45), 5.0, 0.0, 1.0, accent, aglow, 0.85)
        _room_band(sp, c, 5.0, 5.0, z + 0.45, z + 2.8, Mat("#3E6E8E", 0.85), WARM_WINDOW, 0.9, 32, 5, "#e6e8ea")
        z += 2.8
        sp.frustum((c[0], c[1], z), (c[0], c[1], z + 0.5), 5.15, 4.3, PANEL, cap_mat=Mat("#BFC5CB", 0.2))
        z += 0.5
        sp.glow((c[0], c[1], z - 1.6), 70, WARM_WINDOW, 0.3)
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.25), 2.5, STEEL, cap_mat=DARK)
        zt = _dome_lounge(sp, (c[0], c[1], z + 0.25), 2.3, 2.0)
        sp.frustum((c[0], c[1], zt - 0.1), (c[0], c[1], top - 0.15), 0.2, 0.04, STEEL, bands=[0.4])
        sp.lamp((c[0], c[1], top - 0.1), RED_LIGHT, 7)
        _glass_ring(sp, c, 4.2, z, z + 0.9)
        _blade_sign(sp, 0.55, 2.62, zp + fh + 0.4, 1.0, 0.32, 6 * fh, accent, aglow)
    else:
        # 위로 좁아지는 원뿔대 객실탑 → 옥상판 → 빛나는 등불 원통과 세로 지느러미 → 뿔 → 첨탑, 광장의 세로 간판 기둥
        c = (-0.3, -0.8)
        z = _round_floors(sp, c, zp, 12, fh, 4.3, 2.75, 0.55, glass, slab, seed=v)
        sp.cyl((c[0], c[1], z), (c[0], c[1], z + 0.4), 3.4, slab, cap_mat=Mat("#BFC5CB", 0.2))
        z += 0.4
        _room_band(sp, c, 2.1, 2.1, z, z + 3.2, Mat("#B65B57", 0.6), aglow, 0.9, 12, 2)
        _drum_mullions(sp, c, 2.16, z, z + 3.2, 12, "#f1e4d6", 0.09)
        _glass_ring(sp, c, 3.3, z, z + 0.9)
        z += 3.2
        sp.frustum((c[0], c[1], z), (c[0], c[1], z + 1.8), 2.4, 0.35, slab, cap_mat=Mat("#BFC5CB", 0.2),
                   bands=[0.4], band_color="#c9a868")
        sp.glow((c[0], c[1], z - 1.6), 44, aglow, 0.45)
        _spire(sp, c, z + 1.7, top, 0.22)
        # 세로 간판 기둥 (광장 앞 오른쪽)
        _blade_sign(sp, 4.55, 4.35, zg, 0.9, 0.36, 8.5, accent, aglow)
    _hotel_entrance(sp, v, ex, py1, zg, accent)


# ═════════════════════════════════════════════════════════════════════
# 고층 공사 현장 (모양 하나)
# ═════════════════════════════════════════════════════════════════════

SITE = Mat("#6f685f")                # 공사장 바닥 (다진 레골리스)
SITE_TOP = Mat("#7a736a")
CONC = Mat("#BDB6AA")                # 새 콘크리트 (코어·바닥판·기둥)
CONC_TOP = Mat("#CCC6BA")
FORM = Mat("#E2B93B", 0.2)           # 오르는 거푸집 (노랑)
CRANE_Y = Mat("#E9B92F", 0.2)
HOARD = Mat("#2F5E9E", 0.15)         # 공사장 울타리 판
SCAF = "#E9C24A"                     # 비계 관
CRANE_C = "#E0AE2A"
NET = "#3E9E62"                      # 안전망
WORK = "#FFE7B0"                     # 작업등


def _net(sp, pts3, alpha=0.32):
    """안전망 판: 3D는 비치는 초록 판, 2D는 옅은 초록 판 (보이는 면만)."""
    sp._rec(("poly", list(pts3), iso._Glass(NET, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if _seen(n):
        sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(NET), n)), None, 0, alpha + 0.2)


def _scaf_face(sp, frame, lifts, cols, z0, z1, nets):
    """비계 한 면: 기둥·띠장 격자, 두 칸마다 꺾이는 가새, 안전망 띠 (보이지 않는 면도 3D에 적는다)."""
    o, e1, e2 = frame
    n = _nrm(frame)
    show = _seen(n)
    for (a, b) in nets:
        _net(sp, [add(_fp(frame, 0.0, a), mul(n, 0.06)), add(_fp(frame, 1.0, a), mul(n, 0.06)),
                  add(_fp(frame, 1.0, b), mul(n, 0.06)), add(_fp(frame, 0.0, b), mul(n, 0.06))])
    if show:
        sp.panel_grid(o, e1, e2, cols, lifts, SCAF, 0.9, 0.95)
    else:
        sp._rec(("grid", o, e1, e2, cols, lifts, SCAF, 0.9 / S))
    pts = []
    for i in range(lifts // 2 + 1):
        pts.append(add(_fp(frame, float(i % 2), min(1.0, 2.0 * i / lifts)), mul(n, 0.03)))
    if show:
        sp.polyline3(pts, "#c9a23a", 0.07, 0.9)
    else:
        sp._rec(("line", pts, 0.07, "#c9a23a", False))


def _lattice(sp, x, y, z0, z1, a, color=CRANE_C, n=4, w=0.07):
    """네모 격자 마스트: 네 모서리 기둥과 면마다 지그재그 가새 (뒤 면부터)."""
    cs = [(x - a, y - a), (x + a, y - a), (x + a, y + a), (x - a, y + a)]
    faces = sorted(range(4), key=lambda i: (cs[i][0] + cs[(i + 1) % 4][0] + cs[i][1] + cs[(i + 1) % 4][1]))
    for i in faces:
        p, q = cs[i], cs[(i + 1) % 4]
        pts = [((p, q)[k % 2][0], (p, q)[k % 2][1], z0 + (z1 - z0) * k / n) for k in range(n + 1)]
        sp.polyline3(pts, color, w * 0.7)
    for (px, py) in sorted(cs, key=lambda c: c[0] + c[1]):
        sp.line((px, py, z0), (px, py, z1), w, color)


@building("scaffold_tower", 10, 10, 30.0, "공사 중 (고층)")
def scaffold_tower(sp: Sprite):
    """고층 건물 공사 현장: 앞서 오르는 콘크리트 코어와 오르는 거푸집, 층마다 바닥판과 기둥 (아래 두 층은 유리를 단다),
    둘레의 격자 비계와 위쪽 안전망 띠, 코어 위 타워 크레인 (마스트·운전실·지브·평형추·A틀·갈고리와 매단 철골 — 모두 바닥 칸
    안), 밤의 작업등. 게임이 짓는 건물의 바닥 칸과 지금 높이에 맞춰 늘려 쓰므로 위아래로 고른 모양을 지킨다."""
    zb = 0.2
    sp.contact_shadow(0, 0, 4.9, 4.9, 0.35)
    sp.box(-4.95, -4.95, 0, 9.9, 9.9, zb, SITE, top=SITE_TOP)
    E = 4.62                                          # 비계 면 (±)
    zs = 21.0                                         # 비계 꼭대기
    lifts, cols = 10, 6
    nets = [(0.6, 1.0)]
    fr = _faces4(-E, -E, zb, 2 * E, 2 * E, zs - zb)
    # 뒤 울타리와 뒤 비계 (-x, -y)
    sp.box(-4.95, -4.95, zb, 9.87, 0.08, 2.0, HOARD, top=HOARD)
    sp.box(-4.95, -4.87, zb, 0.08, 9.71, 2.0, HOARD, top=HOARD)
    for key in ("-y", "-x"):
        _scaf_face(sp, fr[key], lifts, cols, zb, zs, nets)
    # 층: 바닥판 → 뒤 기둥 → 코어 토막 → 앞 기둥 → (아래 두 층) 유리
    H2 = 4.3                                          # 바닥판 반 너비
    zf = [zb + 3.4 * k for k in range(6)]             # 층 바닥 (맨 아래는 땅)
    cols_xy = [(-3.9, -3.9), (0.0, -3.9), (3.9, -3.9), (-3.9, 0.0), (3.9, 0.0), (-3.9, 3.9), (0.0, 3.9), (3.9, 3.9)]
    cols_xy.sort(key=lambda c: c[0] + c[1])
    glass = Mat("#2F5878", 0.85)
    for k in range(len(zf) - 1):
        z = zf[k]
        if k > 0:
            sp.box(-H2, -H2, z, 2 * H2, 2 * H2, 0.3, CONC, top=CONC_TOP)
            z += 0.3
        zn = zf[k + 1]
        for (cx, cy) in cols_xy:
            if cx + cy < -0.1:
                sp.box(cx - 0.2, cy - 0.2, z, 0.4, 0.4, zn - z, CONC, top=CONC_TOP)
        sp.box(-2.0, -2.0, z, 4.0, 4.0, zn - z, CONC, top=CONC_TOP)
        for (cx, cy) in cols_xy:
            if cx + cy >= -0.1:
                sp.box(cx - 0.2, cy - 0.2, z, 0.4, 0.4, zn - z, CONC, top=CONC_TOP)
        if k < 2:
            for i, f in enumerate(_faces4(-H2 + 0.05, -H2 + 0.05, z, 2 * H2 - 0.1, 2 * H2 - 0.1, zn - z).values()):
                pts = sp.on_face(*f, 0.02, 0.06, 0.98, 0.97)
                _strip(sp, pts, glass, WORK, 0.5 if (i + k) % 2 else 0.25, "#c3ccd4", 5, i + k)
                _grid(sp, (pts[0], sub(pts[1], pts[0]), sub(pts[3], pts[0])), 5, 1, "#d5dbe1", 0.7, 0.8, 0.03)
    zd = zf[-1]
    sp.box(-H2, -H2, zd, 2 * H2, 2 * H2, 0.3, CONC, top=CONC_TOP)
    zd += 0.3                                         # 작업 바닥
    # 작업 바닥: 철근 내민 기둥, 쌓은 거푸집 판과 철근 다발, 작업등 번짐
    for (cx, cy) in cols_xy:
        sp.line((cx, cy, zd), (cx, cy, zd + 1.1), 0.12, "#8a6a50")
    sp.box(-3.5, 1.7, zd, 1.2, 1.8, 0.35, Mat("#7d848d", 0.3))
    sp.glow((0.0, 0.0, zd + 1.5), 60, WORK, 0.4)
    # 코어 윗부분 (작업 바닥 위로 앞서 오른다) + 오르는 거푸집 (발판 → 노란 거푸집 상자, 줄눈 격자)
    zc = 21.8
    sp.box(-2.0, -2.0, zd, 4.0, 4.0, zc - 3.2 - zd, CONC, top=CONC_TOP)
    sp.box(-2.45, -2.45, zc - 3.2, 4.9, 4.9, 0.2, Mat("#7d848d", 0.3), top=Mat("#8a9099", 0.3))
    sp.box(-2.3, -2.3, zc - 3.0, 4.6, 4.6, 3.0, FORM, top=Mat("#C9A23A", 0.2))
    for f in _faces4(-2.3, -2.3, zc - 3.0, 4.6, 4.6, 3.0).values():
        _grid(sp, f, 4, 3, "#8a6a2a", 0.8, 0.9, 0.03)
    sp.box(1.4, 2.0, zd, 1.7, 1.1, 0.45, Mat("#C98A3A", 0.1), top=Mat("#D69A4A", 0.1))
    # 타워 크레인: 코어 위 격자 마스트 → 선회대 → 평형 지브(-x)와 평형추 → 지브(+x) → 운전실 → A틀과 당김줄 → 등
    zm1 = 26.0
    _lattice(sp, 0.0, 0.0, zc, zm1, 0.6, n=4, w=0.09)
    sp.box(-0.85, -0.85, zm1, 1.7, 1.7, 0.6, CRANE_Y, top=Mat("#C9A23A", 0.2))
    zj = zm1 + 0.7
    xt, xc = 4.75, -3.9                               # 지브 끝, 평형 지브 끝
    for yy in (-0.4, 0.4):
        sp.line((-0.85, yy, zj), (xc, yy, zj), 0.12, CRANE_C)
    sp.polyline3([(-0.85 - (xc + 0.85) * -i / 6, (-0.4, 0.4)[i % 2], zj) for i in range(7)], CRANE_C, 0.07)
    sp.box(xc, -0.6, zj - 1.1, 1.05, 1.2, 1.0, CONC, top=CONC_TOP)
    sp.box(xc + 0.05, -0.55, zj - 0.1, 0.95, 1.1, 0.12, DARK)
    # 지브: 아래 두 줄 + 위 한 줄 (삼각 단면) + 두 옆면 가새
    zt_ = zj + 0.75
    for yy in (-0.35, 0.35):
        sp.line((0.85, yy, zj), (xt, yy, zj), 0.12, CRANE_C)
    sp.line((0.85, 0.0, zt_), (xt - 0.35, 0.0, zj + 0.12), 0.12, CRANE_C)
    n = 8
    for yy in (-0.35, 0.35):
        pts = []
        for i in range(n + 1):
            x = 0.85 + (xt - 0.35 - 0.85) * i / n
            zz = zt_ + (zj + 0.12 - zt_) * i / n
            pts.append((x, 0.0, zz) if i % 2 else (x, yy, zj))
        sp.polyline3(pts, CRANE_C, 0.06)
    # 운전실 (선회대 앞 +y, 지브 뿌리)
    sp.box(0.2, 0.85, zm1 - 0.25, 0.9, 0.8, 0.9, CRANE_Y, top=Mat("#C9A23A", 0.2))
    cab = _faces4(0.2, 0.85, zm1 - 0.25, 0.9, 0.8, 0.9)
    _lit_decal(sp, cab["+y"], 0.1, 0.35, 0.9, 0.88, Mat("#3B5A6E", 0.85), WORK, 0.85)
    _lit_decal(sp, cab["+x"], 0.12, 0.35, 0.88, 0.88, Mat("#3B5A6E", 0.85), WORK, 0.85)
    # 꼭대기 A틀과 당김줄, 붉은 등
    apex = (0.0, 0.0, 30.0 - 0.15)
    for yy in (-0.5, 0.5):
        sp.line((0.0, yy, zm1 + 0.6), apex, 0.1, CRANE_C)
    sp.line(apex, (3.4, 0.0, zt_ - 0.22), 0.05, "#9aa1aa")
    sp.line(apex, (xc + 0.4, 0.0, zj), 0.05, "#9aa1aa")
    sp.lamp((0.0, 0.0, 30.0 - 0.1), RED_LIGHT, 7)
    sp.lamp((xt - 0.05, 0.0, zj + 0.2), RED_LIGHT, 6)
    sp.lamp((xc + 0.1, 0.0, zj + 0.2), RED_LIGHT, 5)
    # 트롤리 → 줄 → 갈고리 → 매단 철골 다발
    tx = 3.2
    sp.box(tx - 0.3, -0.3, zj - 0.3, 0.6, 0.6, 0.3, DARK)
    zh = zd + 2.0
    sp.line((tx, 0.0, zj - 0.3), (tx, 0.0, zh + 0.55), 0.05, "#5c626b")
    sp.box(tx - 0.2, -0.2, zh + 0.2, 0.4, 0.4, 0.35, Mat("#E07B39", 0.2))
    for dy in (-0.4, 0.4):
        sp.line((tx, 0.0, zh + 0.2), (tx, dy, zh - 0.1), 0.035, "#5c626b")
    sp.box(tx - 1.1, -0.45, zh - 0.4, 2.2, 0.9, 0.3, Mat("#A0522D", 0.3), top=Mat("#B8653A", 0.3))
    # 앞 비계 (+x, +y) — 안전망 띠, 꼭대기 모서리 작업등
    for key in ("+x", "+y"):
        _scaf_face(sp, fr[key], lifts, cols, zb, zs, nets)
    for (x, y) in ((-E, -E), (E, -E), (-E, E), (E, E)):
        sp.lamp((x, y, zs + 0.25), WORK, 14)
    # 앞 울타리 (+x 통째, +y는 차 드나드는 문 자리를 비운다) + 공사 안내판
    sp.box(4.84, -4.95, zb, 0.08, 9.87, 2.0, HOARD, top=HOARD)
    sp.box(-4.95, 4.84, zb, 4.6, 0.08, 2.0, HOARD, top=HOARD)
    sp.box(2.3, 4.84, zb, 2.54, 0.08, 2.0, HOARD, top=HOARD)
    bf = _faces4(-4.95, 4.84, zb, 4.6, 0.08, 2.0)["+y"]
    _lit_decal(sp, bf, 0.15, 0.25, 0.85, 0.85, Mat("#ECE7DC", 0.1), WORK, 0.5, 0.02)
    sp.stripes(add(_fp(bf, 0.15, 0.08), (0, 0.03, 0)), mul(bf[1], 0.7), (0, 0, 0.3), n=10, normal=(0, 1, 0))
    for x in (-0.35, 2.3):
        sp.lamp((x, 4.8, zb + 2.2), AMBER, 9)


TYPES["scaffold_tower"] = __name__                   # 미리보기(preview_types)에도 나오게 목록에 올린다
