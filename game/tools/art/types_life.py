"""생명유지·식량 계열의 새 건물 종류 32종.

전기분해기·CO₂ 제거기·사바티에·물 재활용·저장 탱크·수경 농장·조류 반응기·식량 저장 계열마다 넷씩.
종류마다 fn(sp, v) 하나: v0은 대표 모양, v1~v4는 같은 종류의 세부(색 띠, 덧붙인 장치, 배치, 비율)를 바꾼다.
"""
from __future__ import annotations

import math

from types_common import *  # noqa: F401,F403

# ── 재질 ─────────────────────────────────────────────────────────────
H2_RED = Mat("#C8412E", 0.25)          # 수소 병
INSUL = Mat("#646A72", 0.15)           # 고온 단열 외피
INSUL_PANEL = Mat("#7A8088", 0.15)
CARBON = Mat("#2A2C30", 0.05)          # 그을음 (보시 탄소)
BRASS = Mat("#B8964E", 0.5)
AMINE = Mat("#D9B65A", 0.2)            # 아민 흡착제 알갱이
IONIC = Mat("#B8742A", 0.5)            # 이온성 액체 (호박색)
COMPOSITE = Mat("#55595F", 0.3)        # 복합재 고압 용기
SOIL = Mat("#6B5038")
WHEAT = Mat("#D9B24A", 0.1)
WATER_GREEN = Mat("#3F8F5A", 0.75)     # 초록빛 물 (유리 너머)
SPIRULINA = Mat("#1F6B66", 0.7)        # 짙은 청록 배양액
CHLORELLA = Mat("#7CC94E", 0.75)
CYANO = Mat("#2E9C8A", 0.25)
POUCH = Mat("#CFE2EC", 0.45)
CANVAS = Mat("#D9C9A3")
SNOW = Mat("#F4F8FA", 0.3)
FROST_BLUE = Mat("#CFE3F0", 0.5)       # 탱크 겉의 성에
ROOF_GLASS = Mat("#2a1f33", 0.22)      # 해를 보는 비탈 유리 (번쩍이지 않게)
ALGAE_GLOW = "#9BEA7A"
WATER_LIGHT = "#7fb6ff"
HOT = "#FF8A3A"
WHITE_LIGHT = "#FFF4DC"


# ── 공용 부품 ─────────────────────────────────────────────────────────

def _panel(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, edge=False):
    """상자 면 위의 판 (색 판·문·표시)."""
    o, e1, e2 = frame
    sp.face(sp.on_face(o, e1, e2, u0, v0, u1, v1), mat, normal=norm(cross(e1, e2)), edge=edge, ao=0)


def _slots(sp: Sprite, frame, n, u0, u1, v0, v1, mat: Mat = DARK, vertical=False):
    """루버·통풍 슬롯 n줄."""
    for i in range(n):
        if vertical:
            s = (u1 - u0) / n
            _panel(sp, frame, u0 + i * s, v0, u0 + i * s + s * 0.5, v1, mat)
        else:
            s = (v1 - v0) / n
            _panel(sp, frame, u0, v0 + i * s, u1, v0 + i * s + s * 0.5, mat)


def _vtank(sp: Sprite, x, y, z0, h, r, mat: Mat, top="dome", bands=(), band_color=None, cap: Mat | None = None):
    """세운 탱크: 원기둥 + 반구 / 접시 / 원뿔 머리."""
    p0, p1 = (x, y, z0), (x, y, z0 + h)
    sp.cyl(p0, p1, r, mat, bands=bands, band_color=band_color, cap_mat=cap or mat)
    if top == "dome":
        sp.sphere(p1, r, mat, clip_z=z0 + h)
    elif top == "dish":
        sp.ellipsoid(p1, r, r, r * 0.45, mat, clip_z=z0 + h)
    elif top == "cone":
        sp.frustum(p1, (x, y, z0 + h + r * 0.9), r, r * 0.18, mat)
    return p0, p1


def _bottle(sp: Sprite, x, y, z0, h, r, mat: Mat, cap: Mat = STEEL):
    """세운 가스 병 (둥근 어깨 + 밸브 머리)."""
    sp.cyl((x, y, z0), (x, y, z0 + h), r, mat)
    sp.sphere((x, y, z0 + h), r, mat, clip_z=z0 + h)
    sp.cyl((x, y, z0 + h + r * 0.8), (x, y, z0 + h + r + 0.16), r * 0.32, cap)


def _fan(sp: Sprite, cx, cy, z, r, mat: Mat = STEEL):
    """지붕 환기 팬 (둥근 통 + 날개 십자)."""
    sp.cyl((cx, cy, z), (cx, cy, z + 0.3), r, mat, cap_mat=CHAR)
    sp.ring3((cx, cy, z + 0.32), r * 0.75, "#9aa1aa", 0.05)
    sp.line((cx - r * 0.7, cy, z + 0.32), (cx + r * 0.7, cy, z + 0.32), 0.07, "#9aa1aa")
    sp.line((cx, cy - r * 0.7, z + 0.32), (cx, cy + r * 0.7, z + 0.32), 0.07, "#9aa1aa")


def _radiator(sp: Sprite, o, e1, e2, n=5):
    sp.quad(o, e1, e2, RADIATOR, back=RADIATOR)
    sp.panel_grid(o, e1, e2, n, 1, "#b7bcc2", 0.5, 0.8)


def _cpipe(sp: Sprite, pts, w=0.18, color="#5d8fd0", edge: str | None = None):
    """색이 뜻을 갖는 관 (물·액체). 어두운 테두리를 조금 아래에 깔아 3D에서도 위쪽에 제 색이 보인다."""
    edge = edge or hexc(scale(rgb(color), 0.5))
    sp.polyline3([add(q, (0, 0, -0.03)) for q in pts], edge, w + 0.06)
    sp.polyline3(pts, color, w)


def _valve(sp: Sprite, p, color="#D9532C", normal=(0, 1, 0), r=0.16):
    """손잡이 바퀴가 달린 밸브."""
    sp.disc(p, normal, r, Mat(color, 0.2), edge=True)
    sp.ring3(p, r, "#5c2a1a", 0.03, normal=normal, front_only=False)


def _frame_back(sp: Sprite, x0, y0, x1, y1, z0, z1, color="#8a9099", w=0.1):
    """상자 틀의 뒤쪽 기둥 셋과 뒤쪽 보 (안의 것보다 먼저 그린다)."""
    for x, y in ((x0, y0), (x1, y0), (x0, y1)):
        sp.line((x, y, z0), (x, y, z1), w, color)
    sp.polyline3([(x0, y1, z1), (x0, y0, z1), (x1, y0, z1)], color, w)


def _frame_front(sp: Sprite, x0, y0, x1, y1, z0, z1, color="#8a9099", w=0.1):
    sp.line((x1, y1, z0), (x1, y1, z1), w, color)
    sp.polyline3([(x0, y1, z1), (x1, y1, z1), (x1, y0, z1)], color, w)


def _glass_vault_2d(sp: Sprite, p0, p1, r, rz, ribs=5, rib_color="#dfe9f2"):
    """x축 방향 유리 볼트: 반투명 껍질(2D) + 3D 유리 + 갈비."""
    rim = []
    for i in range(25):
        t = math.pi * i / 24
        for p in (p0, p1):
            rim.append(PV((p[0], p[1] + r * math.cos(t), p[2] + rz * math.sin(t))))
    sil = hull(rim)
    mid = ((p0[0] + p1[0]) / 2, p0[1], p0[2])
    hl = PV((mid[0] - (p1[0] - p0[0]) * 0.18, mid[1] + r * 0.45, mid[2] + rz * 0.85))
    span = max(abs(p1[0] - p0[0]), 2 * r) * S * 0.7
    fill = sp.radial([(0, "#ffffff", 0.34), (0.45, "#cfe6ff", 0.14), (1, "#9fc0e0", 0.06)], hl[0], hl[1], span)
    sp.poly2(sil, fill, "#cfe0ef", 0.6, 1.0)
    sp.glass_vault(p0, p1, r, rz=rz)
    for k in range(ribs + 1):
        x = p0[0] + (p1[0] - p0[0]) * k / ribs
        pts = [(x, p0[1] + r * math.cos(math.pi * i / 16), p0[2] + rz * math.sin(math.pi * i / 16)) for i in range(17)]
        sp.polyline3(pts, rib_color, 0.06, 0.6)
    # 용마루와 앞쪽 처마
    sp.polyline3([(p0[0], p0[1], p0[2] + rz), (p1[0], p1[1], p1[2] + rz)], rib_color, 0.05, 0.5)


def _puff(sp: Sprite, c, r, opacity=0.55):
    """하얀 김·안개 덩이 (그림 전용)."""
    cc = PV(c)
    pts = [(cc[0] + r * S * math.cos(2 * math.pi * i / 16), cc[1] + r * S * 0.8 * math.sin(2 * math.pi * i / 16))
           for i in range(16)]
    fill = sp.radial([(0, "#ffffff", opacity), (0.6, "#f2f6f8", opacity * 0.6), (1, "#e8eef2", 0.0)],
                     cc[0], cc[1], r * S)
    sp.poly2(pts, fill)


def _outward(pts, center):
    """다각형 꼭짓점 순서를 바깥(center 반대쪽)을 보도록 맞춘다."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    c = mul(tuple(sum(p[i] for p in pts) for i in range(3)), 1.0 / len(pts))
    return pts if dot(n, sub(c, center)) >= 0 else pts[::-1]


def _solid(sp: Sprite, faces):
    """볼록한 다면체: (꼭짓점들, 재질) 면을 모두 바깥을 보게 그린다 (보이지 않는 면은 그림에서 빠진다)."""
    allp = [p for pts, _ in faces for p in pts]
    center = mul(tuple(sum(p[i] for p in allp) for i in range(3)), 1.0 / len(allp))
    for pts, mat in faces:
        sp.face(_outward(pts, center), mat)
    return center


# ── 전기분해기 계열 ───────────────────────────────────────────────────

@typed("pem_electrolyzer", 6, 5, 3.2, "고분자막 전기분해기", heights=[3.2, 3.3, 3.2, 3.3, 3.5])
def pem_electrolyzer(sp: Sprite, v: int):
    acc = (BLUE, Mat("#2F5D9E", 0.2), Mat("#4A7FC4", 0.2), BLUE, Mat("#35609A", 0.2))[v]
    bw = (3.9, 3.9, 4.2, 3.6, 3.9)[v]
    bh = (2.75, 2.75, 2.75, 2.75, 3.0)[v]
    sp.contact_shadow(0, 0, 3.6, 3.0)
    sp.box(-2.9, -2.4, 0, 5.8, 4.8, 0.15, SINTER)
    x0, y0, z0, d = -2.7, -1.9, 0.15, 3.4
    sp.box(x0, y0, z0, bw, d, bh, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, z0, bw, d, bh)
    # 옆 창으로 보이는 셀 스택 (얇은 판 + 파란 끝판 + 조임 막대)
    wu0, wu1 = 0.36, 0.93
    sp.window(sp.on_face(*f["left"], wu0, 0.17, wu1, 0.8), CYAN_LIGHT)
    n = 17
    for i in range(n):
        u = wu0 + 0.06 + (wu1 - wu0 - 0.12) * i / (n - 1)
        _panel(sp, f["left"], u - 0.006, 0.25, u + 0.006, 0.72, SILVER)
    for u in (wu0 + 0.03, wu1 - 0.03):
        _panel(sp, f["left"], u - 0.018, 0.21, u + 0.018, 0.76, acc)
    o, e1, e2 = f["left"]
    for vv in (0.3, 0.67):
        a = add(add(o, mul(e1, wu0 + 0.02)), mul(e2, vv))
        sp.line(add(a, (0, 0.03, 0)), add(add(a, mul(e1, wu1 - wu0 - 0.04)), (0, 0.03, 0)), 0.05, "#8a9099")
    # 파란 정비 문과 띠
    _panel(sp, f["left"], 0.05, 0.05, 0.3, 0.86, acc, edge=True)
    sp.window(sp.on_face(*f["left"], 0.1, 0.62, 0.25, 0.76), CYAN_LIGHT, frame=None)
    _panel(sp, f["right"], 0.0, 0.84, 1.0, 0.93, acc)
    _slots(sp, f["right"], 5, 0.15, 0.85, 0.12, 0.6)
    if v in (2, 4):
        sp.window(sp.on_face(*f["right"], 0.55, 0.62, 0.85, 0.78), CYAN_LIGHT)
    zt = z0 + bh
    # 지붕 설비
    if v in (0, 2):
        sp.box(x0 + 0.5, y0 + 0.6, zt, 1.2, 0.9, 0.3, STEEL)
        sp.line((x0 + 1.7, y0 + 1.05, zt + 0.15), (x0 + bw - 0.3, y0 + 1.05, zt + 0.15), 0.12, "#7d848d")
    elif v in (1, 4):
        for cx in (x0 + 1.0, x0 + 2.3):
            _fan(sp, cx, y0 + 1.6, zt, 0.42)
    else:
        _radiator(sp, (x0 + 0.4, y0 + 0.5, zt), (2.6, 0, 0), (0, 0, 0.55), 6)
    if v == 4:
        antenna(sp, (x0 + 0.4, y0 + 0.4, zt), 1.4)
    # 기체 병: 산소(흰색)·수소(빨강)
    bx = x0 + bw + 0.7
    ys = ((-0.7, 0.45), (-1.75, -0.6), (-1.35, -0.5, 0.35), (-0.7, 0.45), (-0.7, 0.45))[v]
    sp.box(bx - 0.5, ys[0] - 0.55, 0.15, 1.0, ys[-1] - ys[0] + 1.1, 0.08, STEEL)
    sp.line((bx - 0.42, ys[0] - 0.5, 1.45), (bx - 0.42, ys[-1] + 0.5, 1.45), 0.08, "#8a9099")
    for y, m in zip(ys, (WHITE, H2_RED, H2_RED)):       # 뒤에서 앞으로
        _bottle(sp, bx, y, 0.23, 1.65, 0.33, m)
        sp.polyline3([(bx, y, 2.45), (bx, y, 2.6), (x0 + bw, y, 2.6)], "#c9ccd1", 0.09)
    sp.lamp((x0 + bw + 0.05, y0 + d + 0.05, zt - 0.25), CYAN_LIGHT, 7)


@typed("soe_electrolyzer", 7, 5, 3.8, "고체산화물 전기분해기", heights=[3.8, 3.8, 3.9, 3.6, 3.8])
def soe_electrolyzer(sp: Sprite, v: int):
    sp.contact_shadow(0, 0, 4.1, 3.0)
    sp.box(-3.4, -2.4, 0, 6.8, 4.8, 0.25, CONCRETE)
    x0, y0, z0 = -3.1, -2.0, 0.25
    w, d, h = (4.9, 4.9, 5.2, 4.6, 4.9)[v], 3.6, (2.5, 2.5, 2.6, 2.3, 2.5)[v]
    # 두꺼운 단열 판으로 싼 고온 상자 (판 사이 이음매)
    sp.box(x0, y0, z0, w, d, h, INSUL, top=Mat("#70757D", 0.15))
    f = Sprite.box_faces(x0, y0, z0, w, d, h)
    for face, nu in (("left", 4), ("right", 3)):
        for i in range(nu):
            for j in range(2):
                _panel(sp, f[face], i / nu + 0.02, j * 0.5 + 0.04, (i + 1) / nu - 0.02, (j + 1) * 0.5 - 0.04, INSUL_PANEL)
    # 주황빛 통풍구
    nv = (3, 4, 3, 3, 2)[v]
    for i in range(nv):
        u = 0.1 + i * (0.8 / nv)
        sp.window(sp.on_face(*f["left"], u, 0.52, u + 0.8 / nv - 0.06, 0.68), HOT, frame="#2a2f36",
                  glass=Mat("#E8662A", 0.3))
    sp.window(sp.on_face(*f["right"], 0.3, 0.52, 0.7, 0.68), HOT, frame="#2a2f36", glass=Mat("#E8662A", 0.3))
    sp.glow((x0 + w / 2, y0 + d, z0 + h * 0.6), 26, HOT, 0.45)
    # 지붕의 열교환 지느러미 (구리)
    zt = z0 + h
    sp.box(x0 + 0.3, y0 + 0.3, zt, w - 0.6, d - 0.6, 0.25, STEEL)
    nf = (8, 7, 11, 6, 9)[v]
    if v in (2, 4):
        cu = Mat("#E3A26E", 0.45)
        for i in range(nf):
            x = x0 + 0.55 + (w - 1.1) * i / (nf - 1)
            sp.quad((x, y0 + 0.5, zt + 0.25), (0, d - 1.0, 0), (0, 0, 0.75), cu, back=cu)
    else:
        for i in range(nf):
            y = y0 + 0.5 + (d - 1.0) * i / (nf - 1)
            sp.quad((x0 + w - 0.5, y, zt + 0.25), (-(w - 1.0), 0, 0), (0, 0, 0.75), COPPER, back=COPPER)
    # 증기 입구 탱크와 전력 변환함 (옆)
    sx = x0 + w + 0.75
    if v != 3:
        _vtank(sp, sx, -1.2, 0.25, 1.9, 0.5, WHITE, top="dish")
        sp.polyline3([(sx, -1.2, 1.8), (x0 + w, -1.2, 1.8)], "#E6DCC8", 0.24)
    sp.box(sx - 0.55, 0.0, 0.25, 1.1, 1.3 if v != 4 else 2.0, 1.5, Mat("#5B6470", 0.2), top=SILVER)
    fb = Sprite.box_faces(sx - 0.55, 0.0, 0.25, 1.1, 1.3 if v != 4 else 2.0, 1.5)
    sp.stripes(add(fb["right"][0], (0.01, 0, 1.15)), (0, 1.3 if v != 4 else 2.0, 0), (0, 0, 0.25), n=6, normal=(1, 0, 0))
    sp.window(sp.on_face(*fb["left"], 0.3, 0.45, 0.7, 0.65), HOT)
    if v == 2:
        sp.cyl((x0 + 0.6, y0 + 0.6, zt + 0.25), (x0 + 0.6, y0 + 0.6, zt + 1.4), 0.22, STEEL, cap_mat=CHAR)
    sp.lamp((x0 + w + 0.05, y0 + d + 0.05, z0 + h - 0.2), AMBER, 8)


@typed("mini_electrolyzer", 4, 3, 2.4, "소형 전기분해기", heights=[2.4, 2.4, 2.4, 2.6, 2.4])
def mini_electrolyzer(sp: Sprite, v: int):
    acc = (TEAL, BLUE, TEAL, ORANGE, BLUE)[v]
    bmat = (H2_RED, WHITE, H2_RED, WHITE, Mat("#5FA35A", 0.2))[v]
    sp.contact_shadow(0, 0, 2.4, 1.9)
    for y in (-1.3, 1.0):
        sp.box(-1.9, y, 0, 3.8, 0.3, 0.2, STEEL)
    sp.box(-1.9, -1.3, 0.2, 3.8, 2.6, 0.08, Mat("#7d848d", 0.2))
    by = (-0.55, 0.55, -0.55, 0.55, -0.55)[v]
    cx0 = (-1.6, -1.6, -1.2, -1.6, -1.6)[v]
    parts = []

    def cabinet():
        sp.box(cx0, -1.0, 0.28, 2.0, 1.9, 1.55, WHITE, top=SILVER)
        f = Sprite.box_faces(cx0, -1.0, 0.28, 2.0, 1.9, 1.55)
        _panel(sp, f["left"], 0.0, 0.82, 1.0, 0.92, acc)
        sp.window(sp.on_face(*f["left"], 0.12, 0.45, 0.42, 0.68), CYAN_LIGHT)
        _slots(sp, f["left"], 4, 0.55, 0.9, 0.15, 0.6, DARK, vertical=True)
        _slots(sp, f["right"], 4, 0.2, 0.8, 0.2, 0.6)
        zt = 0.28 + 1.55
        if v == 2:
            sp.quad((cx0 + 0.15, -0.85, zt + 0.15), (1.7, 0, 0), (0, 1.3, 0.35), SOLAR, back=STEEL)
            sp.panel_grid((cx0 + 0.15, -0.85, zt + 0.15), (1.7, 0, 0), (0, 1.3, 0.35), 4, 2, "#6f86b0", 0.5, 0.6)
        elif v == 4:
            _fan(sp, cx0 + 1.0, -0.05, zt, 0.45)
        if v in (1, 3):
            antenna(sp, (cx0 + 0.3, -0.7, zt), 1.0 if v == 1 else 1.3)
        # 짧은 배관 끝 (플랜지)
        px = cx0 + 2.0
        pipe(sp, [(px, -by * 0.6, 1.0), (px + 0.45, -by * 0.6, 1.0), (px + 0.45, -by * 0.6, 1.35)], 0.14)
        sp.cyl((px + 0.45, -by * 0.6, 1.35), (px + 0.45, -by * 0.6, 1.42), 0.16, STEEL)
    parts.append(((cx0 + 1.0, -0.05, 1.0), cabinet))
    parts.append(((1.25, by, 1.0), lambda: _bottle(sp, 1.25, by, 0.28, 1.6, 0.3, bmat)))
    if v == 4:
        parts.append(((-1.3, 1.25, 0.3), lambda: crate(sp, -1.75, 0.95, 0.55, ORANGE, 0.28)))
    sp.parts(parts)
    sp.lamp((cx0 + 2.05, 0.95, 1.6), CYAN_LIGHT, 6)


@typed("alkaline_electrolyzer", 8, 4, 3.4, "알칼리 전기분해기", heights=[3.4, 3.4, 3.6, 3.4, 3.6])
def alkaline_electrolyzer(sp: Sprite, v: int):
    band = (YELLOW, YELLOW, Mat("#E07B39", 0.1), TEAL, YELLOW)[v]
    cab_back = v in (1, 3)
    th = (2.55, 2.55, 2.8, 2.55, 2.8)[v]
    sp.contact_shadow(0, 0, 4.6, 2.6)
    sp.box(-3.9, -1.9, 0, 7.8, 3.8, 0.25, CONCRETE)
    xs = [-1.2, 0.2, 1.6, 3.0] if cab_back else [-3.1, -1.7, -0.3, 1.1]
    cx = -3.6 if cab_back else 2.1

    def cabinet():
        sp.box(cx, -1.5, 0.25, 1.5, 2.6, 1.9, Mat("#5B6470", 0.2), top=SILVER)
        f = Sprite.box_faces(cx, -1.5, 0.25, 1.5, 2.6, 1.9)
        _slots(sp, f["right"], 6, 0.12, 0.88, 0.15, 0.85, CHAR, vertical=True)
        _panel(sp, f["left"], 0.15, 0.55, 0.45, 0.8, YELLOW)
        sp.window(sp.on_face(*f["left"], 0.6, 0.5, 0.85, 0.75), "#7CF29A", frame=None, glass=Mat("#2c8f4f", 0.4))
        if v == 4:
            antenna(sp, (cx + 0.4, -1.2, 2.15), 1.4)
    if cab_back:
        cabinet()
    for i, x in enumerate(xs):
        p0, p1 = _vtank(sp, x, -0.55, 0.25, th, 0.6, WHITE, top="dish", bands=[0.12], band_color="#a29a8c")
        cyl_ring(sp, p0, p1, 0.6, 0.78, 0.86, band)
        # 액위계
        sp.window(Sprite.cyl_patch(p0, p1, 0.6, 0.2, 0.62, 95, 105), "#cfe9ff", frame=None, glass=Mat("#9fb7c9", 0.5),
                  light_alpha=0.0)
    # 공통 헤더 관 (위: 기체, 아래: 전해액)
    zt = 0.25 + th - 0.3
    for x in xs:
        pipe(sp, [(x, 0.0, zt), (x, 0.35, zt)], 0.16)
        pipe(sp, [(x, 0.0, 0.7), (x, 0.35, 0.7)], 0.16)
    hx = cx + 0.75
    pipe(sp, [(xs[0], 0.35, zt), (xs[-1], 0.35, zt), (hx, 0.35, zt), (hx, 0.35, 2.15)], 0.22, "#d8dbe0")
    _cpipe(sp, [(xs[0], 0.35, 0.7), (hx, 0.35, 0.7)], 0.2, "#c9b26a" if band is YELLOW else "#c9ccd1")
    if v == 2:
        # 기체 분리 드럼 (앞쪽 바닥에 누운)
        for x in (xs[0] + 0.4, xs[1] + 0.2):
            sp.box(x - 0.15, 0.95, 0.25, 0.3, 0.7, 0.3, STEEL)
        sp.cyl((xs[0] - 0.2, 1.3, 0.85), (xs[1] + 0.6, 1.3, 0.85), 0.38, SILVER, cap_mat=STEEL, bands=[0.5])
    if v == 3:
        zc = 0.25 + th + 0.27                       # 접시 머리 꼭대기에 얹은 통로
        sp.box(xs[0] - 0.35, -0.8, zc, xs[-1] - xs[0] + 0.7, 0.5, 0.06, Mat("#C9A23A", 0.2))
        for y in (-0.8, -0.3):
            sp.line((xs[-1] + 0.35, y, 0.25), (xs[-1] + 0.35, y, zc + 0.6), 0.05, "#E9C24A")
    if not cab_back:
        cabinet()
    lx = xs[0] if not cab_back else xs[-1]
    sp.line((lx, 0.35, zt + 0.1), (lx, 0.35, zt + 0.55), 0.06, "#8a9099")
    sp.lamp((lx, 0.35, zt + 0.6), AMBER, 7)
    sp.lamp((cx + 1.55, 1.15, 1.9), "#7CF29A", 6)


# ── CO₂ 제거기 계열 ───────────────────────────────────────────────────

def _rbox(sp: Sprite, x0, y0, x1, y1, z0, h, mat: Mat, top: Mat | None = None, c=0.3):
    """모서리를 깎은 상자. 보이는 두 면의 틀(원점, 가로, 세로)을 돌려준다."""
    sp.prism(rounded_rect(x0, y0, x1, y1, c), z0, h, mat, top=top)
    return {"left": ((x1 - c, y1, z0), (-(x1 - x0 - 2 * c), 0.0, 0.0), (0.0, 0.0, h)),
            "right": ((x1, y0 + c, z0), (0.0, y1 - y0 - 2 * c, 0.0), (0.0, 0.0, h))}


@typed("amine_scrubber", 5, 4, 3.0, "고체 아민 흡착기", heights=[3.0, 3.0, 3.1, 3.3, 3.0])
def amine_scrubber(sp: Sprite, v: int):
    body = (WHITE, SILVER, WHITE, WHITE, Mat("#E4DED0"))[v]
    acc = (TEAL, TEAL, YELLOW, TEAL, ORANGE)[v]
    sp.contact_shadow(0, 0, 3.0, 2.6)
    sp.box(-2.4, -1.9, 0, 4.8, 3.8, 0.2, CONCRETE)
    vx = (2.05, 2.05, 2.05, 1.95, -2.05)[v]          # 진공 배기관 자리
    if v != 4:
        sp.box(1.85, -1.6, 0.2, 0.45, 1.3, 1.1, Mat("#5B6470", 0.2), top=SILVER)
    beds = ((-2.15, -0.35), (-0.05, 1.75))
    hh = ((2.1, 2.1), (2.1, 2.1), (2.1, 2.3), (2.1, 2.1), (2.1, 1.8))[v]
    for (x0, x1), h in zip(beds, hh):
        f = _rbox(sp, x0, -1.55, x1, 0.45, 0.2, h, body, top=SILVER, c=0.32)
        _panel(sp, f["left"], 0.0, 0.84, 1.0, 0.92, acc)
        sp.window(sp.on_face(*f["left"], 0.2, 0.3, 0.8, 0.66), "#F2C14E", frame="#2a2f36", glass=AMINE,
                  light_alpha=0.55)
        for vv in (0.4, 0.5, 0.6):
            _panel(sp, f["left"], 0.22, vv, 0.78, vv + 0.012, Mat("#b9953e"))
        _slots(sp, f["right"], 3, 0.2, 0.8, 0.15, 0.45)
        cx = (x0 + x1) / 2
        if v == 2:
            sp.ellipsoid((cx, -0.55, 0.2 + h), 0.75, 0.85, 0.3, body, clip_z=0.2 + h)
        sp.cyl((cx, -0.55, 0.2 + h), (cx, -0.55, 0.2 + h + 0.35), 0.16, STEEL)
    # 위 배관: 두 베드 → 배기관
    zt = 0.2 + max(hh) + 0.42
    xc = [(a + b) / 2 for a, b in beds]
    for c in xc:
        pipe(sp, [(c, -0.55, zt - 0.1), (c, -0.55, zt)], 0.16)
    pipe(sp, [(min(xc + [vx]), -0.55, zt), (max(xc + [vx]), -0.55, zt)], 0.16)
    pipe(sp, [(vx, -0.55, zt), (vx, 0.95, zt)], 0.16)
    # 앞쪽 밸브 다발 (빨간 손잡이)
    pipe(sp, [(min(-1.95, vx), 0.95, 0.7), (max(1.6, vx), 0.95, 0.7)], 0.2)
    nvalve = 3 if v == 2 else 2
    for x0, x1 in beds:
        for k in range(nvalve):
            x = x0 + (x1 - x0) * (k + 1) / (nvalve + 1)
            pipe(sp, [(x, 0.45, 0.7), (x, 0.95, 0.7)], 0.14)
            _valve(sp, (x, 0.75, 0.92), "#D9532C" if k % 2 == 0 else "#E9C24A", normal=(0, 0, 1), r=0.14)
    if v == 3:
        # 진공 펌프 (누운 몸통 + 모터)
        sp.box(0.6, 1.25, 0.2, 1.2, 0.5, 0.25, STEEL)
        sp.cyl((0.65, 1.5, 0.75), (1.75, 1.5, 0.75), 0.3, Mat("#3E6FB0", 0.2), cap_mat=STEEL)
        pipe(sp, [(1.75, 1.5, 0.75), (vx, 1.5, 0.75), (vx, 0.95, 0.75)], 0.14)
    # 위로 솟은 진공 배기관 (빗물 갓)
    top = 3.0 if v != 3 else 3.25
    pipe(sp, [(vx, 0.95, 0.7), (vx, 0.95, top)], 0.3)
    sp.cyl((vx, 0.95, top - 0.55), (vx, 0.95, top - 0.4), 0.19, YELLOW)
    sp.frustum((vx, 0.95, top), (vx, 0.95, top + 0.22), 0.34, 0.06, STEEL)
    if v == 4:
        sp.box(1.85, 0.75, 0.2, 0.5, 0.9, 1.0, Mat("#5B6470", 0.2), top=SILVER)
        antenna(sp, (2.1, 1.2, 1.2), 1.2)
    sp.lamp((1.8, 0.5, 1.6), CYAN_LIGHT, 7)


@typed("molecular_sieve", 6, 4, 3.4, "분자체 흡착기", heights=[3.4, 3.4, 3.4, 3.6, 3.4])
def molecular_sieve(sp: Sprite, v: int):
    tag = (TEAL, ORANGE, TEAL, YELLOW, BLUE)[v]
    pcol = ("#c9ccd1", "#C98A55", "#c9ccd1", "#C98A55", "#c9ccd1")[v]
    hf = v in (1, 3)                       # 가열기를 왼쪽 앞에 둔다
    sp.contact_shadow(0, 0, 3.6, 2.6)
    sp.box(-2.9, -1.9, 0, 5.8, 3.8, 0.2, CONCRETE)
    x0, y0, w, d = (-2.6, -1.7, 3.8, 2.9) if not hf else (-1.0, -1.7, 3.5, 2.6)
    hx, hy, hw, hd = (1.6, -1.3, 1.1, 1.6) if not hf else (-2.7, 0.9, 1.3, 0.8)

    def heater():
        sp.box(hx, hy, 0.2, hw, hd, 1.5, Mat("#6B5A4C", 0.15), top=STEEL)
        fh = Sprite.box_faces(hx, hy, 0.2, hw, hd, 1.5)
        sp.window(sp.on_face(*fh["right" if not hf else "left"], 0.2, 0.4, 0.8, 0.7), "#ff7b2e",
                  frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
        sp.stripes(add(fh["left"][0], (0, 0.01, 1.2)), (-hw, 0, 0), (0, 0, 0.22), n=6, normal=(0, 1, 0))
    # 넷으로 쌓인 층 (번갈아 조금 내민 띠)
    greys = (Mat("#9AA0A8", 0.25), Mat("#868D96", 0.25))
    for k in range(4):
        o = 0.07 if k % 2 == 0 else 0.0
        z = 0.2 + k * 0.76
        sp.box(x0 - o, y0 - o, z, w + 2 * o, d + 2 * o, 0.72, greys[k % 2], top=Mat("#AAB0B7", 0.25))
        fk = Sprite.box_faces(x0 - o, y0 - o, z, w + 2 * o, d + 2 * o, 0.72)
        _panel(sp, fk["left"], 0.06, 0.3, 0.12, 0.7, tag)
        _panel(sp, fk["left"], 0.7, 0.2, 0.9, 0.8, Mat("#787f88", 0.25), edge=True)
    zt = 0.2 + 4 * 0.76
    # 가는 관 여럿: 앞면을 오르는 관, 옆면에서 가열기·바닥으로 가는 관
    for i in range(5):
        x = x0 + w - (0.2 + i * 0.09) * w
        sp.polyline3([(x, y0 + d + 0.12, 0.2), (x, y0 + d + 0.12, 0.45 + i * 0.6), (x, y0 + d, 0.45 + i * 0.6)],
                     pcol, 0.08)
    if hf:
        heater()
    for k in range(4):
        y = y0 + 0.4 + k * (d - 0.8) / 3
        z = 0.55 + k * 0.76
        if not hf:
            sp.polyline3([(x0 + w + 0.07, y, z), (x0 + w + 0.3, y, z), (x0 + w + 0.3, y, 1.8), (hx + 0.55, y, 1.8)],
                         pcol, 0.09)
        else:
            sp.polyline3([(x0 + w + 0.07, y, z), (x0 + w + 0.3, y, z), (x0 + w + 0.3, y, 0.25)], pcol, 0.09)
    if not hf:
        heater()
    # 지붕: 밸브 묶음
    for i in range(3):
        cx = x0 + 0.7 + i * 1.1
        sp.cyl((cx, y0 + d / 2, zt), (cx, y0 + d / 2, zt + 0.3), 0.14, STEEL)
        _valve(sp, (cx, y0 + d / 2, zt + 0.32), "#D9532C", normal=(0, 0, 1), r=0.17)
    sp.polyline3([(x0 + 0.7, y0 + d / 2, zt + 0.15), (x0 + 2.9, y0 + d / 2, zt + 0.15)], pcol, 0.1)
    if v == 3:
        _fan(sp, x0 + w - 0.7, y0 + 0.7, zt, 0.45)
    if v == 4:
        antenna(sp, (x0 + 0.3, y0 + 0.3, zt), 1.5)
    sp.lamp((x0 + w + 0.05, y0 + d + 0.05, zt - 0.3), CYAN_LIGHT, 7)


@typed("lioh_canister", 3, 3, 1.6, "수산화리튬 정화기", heights=[1.6, 1.6, 1.6, 2.0, 1.6])
def lioh_canister(sp: Sprite, v: int):
    label = (ORANGE, ORANGE, Mat("#9B7AD6"), RED, YELLOW)[v]
    fcol = ("#8a9099", "#8a9099", "#8a9099", "#8a9099", "#E9C24A")[v]
    sp.contact_shadow(0, 0, 1.9, 1.9)
    sp.box(-1.4, -1.4, 0, 2.8, 2.8, 0.12, STEEL)
    fx0, fy0, fx1, fy1, ztop = -1.3, -1.3, 0.2, 1.25, 1.45
    _frame_back(sp, fx0, fy0, fx1, fy1, 0.12, ztop, fcol, 0.08)
    s = 0.66
    missing = {1: (1, 2, 1), 4: (0, 0, 1)}.get(v)
    cells = []
    for layer in range(2):
        for i in range(2):
            for j in range(3):
                if missing and (i, j, layer) == missing:
                    continue
                cells.append((layer, -1.25 + i * 0.72, -1.25 + j * 0.84))
    cells.sort(key=lambda c: (c[0], c[1] + c[2]))
    for layer, x, y in cells:
        z = 0.14 + layer * 0.64
        sp.box(x, y, z, s, s * 1.1, 0.6, WHITE, top=SILVER)
        fc = Sprite.box_faces(x, y, z, s, s * 1.1, 0.6)
        _panel(sp, fc["left"], 0.0, 0.5, 1.0, 0.7, label)
        _panel(sp, fc["right"], 0.0, 0.5, 1.0, 0.7, label)
        sp.line((x + 0.15, y + s * 0.55, z + 0.62), (x + s - 0.15, y + s * 0.55, z + 0.62), 0.05, "#5c626b")
    _frame_front(sp, fx0, fy0, fx1, fy1, 0.12, ztop, fcol, 0.08)
    # 송풍기 (옆) — v3은 지붕 위
    if v == 3:
        sp.box(-1.2, -1.1, ztop, 1.3, 2.2, 0.15, STEEL)
        _fan(sp, -0.55, 0.0, ztop + 0.15, 0.5)
    else:
        fy = (-0.65, -0.65, 0.1, 0.0, -0.65)[v]
        sp.box(0.45, fy - 0.55, 0.12, 0.75, 1.1 + (0.45 if v == 2 else 0.0), 1.15, Mat("#C9CED4", 0.3), top=SILVER)
        c = (1.21, fy, 0.72)
        sp.disc(c, (1, 0, 0), 0.42, DARK)
        sp.ring3(c, 0.42, "#9aa1aa", 0.05, normal=(1, 0, 0), front_only=False)
        sp.ring3(c, 0.24, "#9aa1aa", 0.04, normal=(1, 0, 0), front_only=False)
        sp.line((1.22, fy - 0.38, 0.72), (1.22, fy + 0.38, 0.72), 0.05, "#9aa1aa")
        sp.line((1.22, fy, 0.34), (1.22, fy, 1.1), 0.05, "#9aa1aa")
        pipe(sp, [(0.83, fy, 1.27), (0.83, fy, 1.6), (0.0, fy, 1.6)], 0.2)
    if v == 1:
        crate(sp, 0.35, 0.75, 0.55, WHITE, 0.12)
    sp.lamp((0.25, 1.3, 1.5), CYAN_LIGHT, 6)


@typed("ionic_scrubber", 7, 5, 4.2, "이온성 액체 흡수기", heights=[4.2, 4.2, 4.0, 4.4, 4.2])
def ionic_scrubber(sp: Sprite, v: int):
    flip = v in (1, 3)                     # 탈거탑을 앞뒤로 바꾼다
    ah = (3.3, 3.3, 3.1, 3.5, 3.3)[v]
    acc = (ORANGE, ORANGE, TEAL, ORANGE, YELLOW)[v]
    sp.contact_shadow(0, 0, 4.0, 3.0)
    sp.box(-3.4, -2.4, 0, 6.8, 4.8, 0.25, CONCRETE)
    (ax, ay), (sx, sy) = ((-2.0, -1.0), (0.6, -1.1)) if not flip else ((0.4, -1.1), (-2.4, 1.0))

    def absorber():
        p0, p1 = _vtank(sp, ax, ay, 0.25, ah, 0.85, WHITE, top="dish", bands=[0.25, 0.5, 0.75], band_color="#9a9a96")
        sp.window(Sprite.cyl_patch(p0, p1, 0.85, 0.06, 0.2, 60, 100), "#F2A541", frame="#2a2f36", glass=IONIC)
        cyl_ring(sp, p0, p1, 0.85, 0.9, 0.95, acc)
        sp.cyl((ax, ay, 0.25 + ah + 0.3), (ax, ay, 0.25 + ah + 0.6), 0.18, STEEL)

    def stripper():
        p0, p1 = _vtank(sp, sx, sy, 0.25, 2.6, 0.6, SILVER, top="dish", bands=[0.33, 0.66])
        cyl_ring(sp, p0, p1, 0.6, 0.06, 0.2, Mat("#C2502A", 0.2), HOT, 0.6)
        sp.window(Sprite.cyl_patch(p0, p1, 0.6, 0.25, 0.4, 60, 100), "#F2A541", frame="#2a2f36", glass=IONIC)
    for _, fn in sorted(((ax + ay, absorber), (sx + sy, stripper)), key=lambda t: t[0]):
        fn()
    # 펌프 둘 (모터 + 몸통)
    pumps = ((-1.6, 1.3) if not flip else (-1.1, 1.55), (1.4, 0.9))
    if v == 2:
        pumps += ((0.0, 1.6),)
    for px, py in sorted(pumps, key=lambda p: p[0] + p[1]):
        sp.box(px - 0.4, py - 0.3, 0.25, 0.9, 0.6, 0.15, STEEL)
        sp.cyl((px - 0.35, py, 0.65), (px + 0.1, py, 0.65), 0.24, Mat("#3E6FB0", 0.2), cap_mat=STEEL)
        sp.box(px + 0.1, py - 0.2, 0.4, 0.4, 0.4, 0.45, DARK)
    # 호박색 액체 순환관
    ac = "#C98A2B"
    top_a = 0.25 + ah - 0.2
    lo = [(ax, ay + 0.85, 0.65), (ax, pumps[0][1], 0.65), (pumps[0][0] - 0.35, pumps[0][1], 0.65)]
    _cpipe(sp, lo, 0.18, ac, "#6b4a1e")
    rise = [(pumps[0][0] + 0.5, pumps[0][1], 0.65), (pumps[0][0] + 1.1, pumps[0][1], 0.65),
            (pumps[0][0] + 1.1, pumps[0][1], 2.9), (pumps[0][0] + 1.1, sy, 2.9), (sx - 0.6, sy, 2.9)]
    if flip:
        rise = [(pumps[0][0] + 0.5, pumps[0][1], 0.65), (pumps[0][0] + 0.9, pumps[0][1], 0.65),
                (pumps[0][0] + 0.9, pumps[0][1], 2.6), (sx + 0.6, pumps[0][1], 2.6), (sx + 0.6, sy, 2.6)]
    _cpipe(sp, rise, 0.18, ac, "#6b4a1e")
    d = norm((pumps[1][0] - sx, pumps[1][1] - sy, 0.0))
    bx0, by0 = sx + d[0] * 0.6, sy + d[1] * 0.6           # 탈거탑에서 펌프 쪽 옆면
    back = [(bx0, by0, 0.65), (bx0, pumps[1][1], 0.65), (pumps[1][0] - 0.35, pumps[1][1], 0.65)]
    ret = [(pumps[1][0] + 0.5, pumps[1][1], 0.65), (2.6, pumps[1][1], 0.65), (2.6, pumps[1][1], top_a + 0.45),
           (2.6, ay, top_a + 0.45), (ax + 0.85, ay, top_a + 0.45)]
    for pts in (back, ret):
        _cpipe(sp, pts, 0.18, ac, "#6b4a1e")
    if v == 4:
        sp.box(2.2, -2.1, 0.25, 1.0, 1.0, 1.4, Mat("#5B6470", 0.2), top=SILVER)
        antenna(sp, (2.7, -1.6, 1.65), 1.6)
    if v == 3:
        _radiator(sp, (1.4, -2.2, 0.25), (1.8, 0, 0), (0, 0, 2.2), 5)
    sp.lamp((2.65, pumps[1][1], top_a + 0.7), AMBER, 8)
    sp.lamp((pumps[0][0] + 0.6, pumps[0][1] + 0.4, 1.0), CYAN_LIGHT, 6)


# ── 사바티에 계열 ─────────────────────────────────────────────────────

SAB_GOLD = Mat("#c9a75a", 0.3)          # 사바티에 계열 표시 띠


def _drawer_y(sp: Sprite, x0, x1, y, out, z0, z1, soot=True):
    """+y 쪽으로 빼낸 탄소 수집 서랍 (윗면에 그을음)."""
    sp.box(x0, y, z0, x1 - x0, out, z1 - z0, STEEL, top=CARBON if soot else STEEL)
    f = Sprite.box_faces(x0, y, z0, x1 - x0, out, z1 - z0)
    _panel(sp, f["left"], 0.3, 0.55, 0.7, 0.7, CHAR)
    if soot:
        for i in range(3):
            xx = x0 + 0.15 + (x1 - x0 - 0.3) * (i + 0.5) / 3
            sp.ellipsoid((xx, y + out * 0.5, z1), 0.18, out * 0.3, 0.08, CARBON, clip_z=z1)


def _drawer_x(sp: Sprite, x, y0, y1, out, z0, z1):
    """+x 쪽으로 빼낸 서랍."""
    sp.box(x, y0, z0, out, y1 - y0, z1 - z0, STEEL, top=CARBON)
    f = Sprite.box_faces(x, y0, z0, out, y1 - y0, z1 - z0)
    _panel(sp, f["right"], 0.3, 0.55, 0.7, 0.7, CHAR)


def _soot_bin(sp: Sprite, x, y, z, r=0.33, h=0.75):
    sp.cyl((x, y, z), (x, y, z + h), r, CARBON, cap_mat=Mat("#3a3d42", 0.2), bands=[0.8], band_color="#55595f")
    sp.line((x - r * 0.5, y, z + h + 0.06), (x + r * 0.5, y, z + h + 0.06), 0.05, "#7d848d")


@typed("bosch_reactor", 6, 5, 3.6, "보시 반응기", heights=[3.6, 3.6, 3.6, 3.6, 3.4])
def bosch_reactor(sp: Sprite, v: int):
    side = v == 2                           # 서랍이 오른쪽(+x) 면에 있다
    sp.contact_shadow(0, 0, 3.6, 3.0)
    sp.box(-2.9, -2.4, 0, 5.8, 4.8, 0.2, CONCRETE)
    hx0, hy0, hw, hd, hh = (-2.6, -2.0, 3.8, 2.8, 1.7) if not side else (-2.6, -2.2, 3.4, 3.2, 1.7)
    if v == 3:
        _radiator(sp, (-2.7, -2.25, 0.2), (2.6, 0, 0), (0, 0, 2.4), 5)
    # 서랍 상자
    sp.box(hx0, hy0, 0.2, hw, hd, hh, WHITE, top=SILVER)
    f = Sprite.box_faces(hx0, hy0, 0.2, hw, hd, hh)
    nd = (4, 5, 4, 4, 3)[v]
    pulled = ((1,), (0, 3), (2,), (), (1,))[v]
    face = f["right"] if side else f["left"]
    for i in range(nd):
        u0, u1 = 0.04 + i * 0.92 / nd + 0.015, 0.04 + (i + 1) * 0.92 / nd - 0.015
        _panel(sp, face, u0, 0.12, u1, 0.82, Mat("#B9C0C8", 0.3), edge=True)
        _panel(sp, face, u0 + (u1 - u0) * 0.3, 0.6, u1 - (u1 - u0) * 0.3, 0.68, CHAR)
    _panel(sp, f["left"] if not side else f["right"], 0.0, 0.88, 1.0, 0.95, SAB_GOLD)
    # 반응 용기 (위, 금빛 띠와 뜨거운 띠)
    zt = 0.2 + hh
    rx = [(-1.4, -1.0, 0.85)] if v != 4 else [(-1.9, -1.0, 0.6), (-0.5, -1.0, 0.6)]
    for x, y, r in rx:
        p0, p1 = _vtank(sp, x, y, zt, (1.2 if v != 4 else 1.0), r, SILVER, top="dish", bands=[0.5])
        cyl_ring(sp, p0, p1, r, 0.12, 0.26, Mat("#C2502A", 0.2), HOT, 0.55)
        cyl_ring(sp, p0, p1, r, 0.7, 0.8, SAB_GOLD)
        sp.cyl(add(p1, (0, 0, r * 0.4)), add(p1, (0, 0, r * 0.4 + 0.25)), 0.14, STEEL)
    pipe(sp, [(rx[-1][0] + rx[-1][2], -1.0, zt + 0.8), (0.6, -1.0, zt + 0.8), (0.6, -1.0, zt)], 0.18)
    # 빼낸 서랍 (그을음 수집통)
    for i in pulled:
        u0, u1 = 0.04 + i * 0.92 / nd + 0.03, 0.04 + (i + 1) * 0.92 / nd - 0.03
        if side:
            _drawer_x(sp, hx0 + hw, hy0 + hd * u0, hy0 + hd * u1, 0.9, 0.4, 1.0)
        else:
            _drawer_y(sp, hx0 + hw * (1 - u1), hx0 + hw * (1 - u0), hy0 + hd, 0.9, 0.4, 1.0)
    # 검은 탄소 통 (팔레트 위)
    bins = (((2.0, -1.5), (2.0, -0.7), (2.0, 0.1)), ((1.9, -1.4), (1.9, -0.6)), ((-1.8, 1.5), (-1.0, 1.5)),
            ((1.9, -1.4), (1.9, -0.6), (1.9, 0.2)), ((2.0, -1.2), (2.0, -0.4), (2.0, 0.4), (2.0, 1.2)))[v]
    xs = [b[0] for b in bins]
    ys = [b[1] for b in bins]
    sp.box(min(xs) - 0.45, min(ys) - 0.45, 0.2, max(xs) - min(xs) + 0.9, max(ys) - min(ys) + 0.9, 0.12,
           Mat("#9a7b54"))
    for x, y in sorted(bins, key=lambda b: b[0] + b[1]):
        _soot_bin(sp, x, y, 0.32)
    if v == 1:
        sp.cyl((2.1, 0.4, 0.62), (2.1, 1.3, 0.62), 0.3, CARBON, cap_mat=Mat("#3a3d42", 0.2))
    sp.lamp((hx0 + hw + 0.05, hy0 + hd + 0.05, zt - 0.2), AMBER, 8)


@typed("sabatier_large", 8, 5, 4.0, "대형 사바티에 반응기", heights=[4.0, 4.0, 4.2, 3.8, 4.0])
def sabatier_large(sp: Sprite, v: int):
    fin = (Mat("#E3A26E", 0.45), Mat("#E3A26E", 0.45), Mat("#C9CED4", 0.4), Mat("#D9B86A", 0.5),
           Mat("#E3A26E", 0.45))[v]
    tx0, tx1 = (-3.6, 1.6) if v != 3 else (-3.6, 1.2)
    ty, tz, tr = -0.4, 1.75, 0.68
    nfin = (15, 15, 13, 12, 15)[v]
    sp.contact_shadow(0, 0, 4.6, 3.0)
    sp.box(-3.9, -2.4, 0, 7.8, 4.8, 0.25, CONCRETE)
    if v == 4:
        _radiator(sp, (-3.7, -2.2, 0.25), (3.2, 0, 0), (0, 0, 2.8), 6)
    # 받침
    for x in (tx0 + 0.6, (tx0 + tx1) / 2, tx1 - 0.6):
        sp.box(x - 0.2, ty - 0.6, 0.25, 0.4, 1.2, tz - 0.6, STEEL)
    # 긴 반응관 + 냉각 재킷 (지느러미가 재킷 밖으로 빗살처럼 나온다)
    sp.cyl((tx0, ty, tz), (tx1, ty, tz), tr, SILVER, cap_mat=STEEL)
    j0, j1 = tx0 + 0.35, tx1 - 0.35
    for i in range(nfin):
        x = j0 + 0.1 + (j1 - j0 - 0.2) * i / (nfin - 1)
        sp.disc((x, ty, tz), (1, 0, 0), tr + 0.42, fin, edge=True)
    bands = [(i + 0.5) / nfin for i in range(nfin)]
    sp.cyl((j0, ty, tz), (j1, ty, tz), tr + 0.3, fin, cap_mat=fin, bands=bands,
           band_color=hexc(scale(fin.albedo, 0.55)))
    sp.cyl((tx1, ty, tz), (tx1 + 0.15, ty, tz), tr + 0.12, STEEL)
    cyl_ring(sp, (tx0, ty, tz), (tx1, ty, tz), tr, 0.0, 0.05, SAB_GOLD)
    # 큰 응축기 (세운 원기둥, 냉각 코일 띠)
    cx, cy = (2.85, -0.6) if v != 2 else (2.75, 0.3)
    cr = (1.0, 1.0, 1.05, 0.9, 1.0)[v]
    ch = (3.1, 3.1, 3.3, 2.8, 3.1)[v]
    pipe(sp, [(tx1 + 0.15, ty, tz), (cx - cr, ty, tz)], 0.3)
    p0, p1 = _vtank(sp, cx, cy, 0.25, ch, cr, WHITE, top="dish", bands=[0.2, 0.3, 0.4, 0.5, 0.6, 0.7],
                    band_color="#8fa3b5")
    cyl_ring(sp, p0, p1, cr, 0.82, 0.9, SAB_GOLD)
    sp.cyl(add(p1, (0, 0, cr * 0.4)), add(p1, (0, 0, cr * 0.4 + 0.3)), 0.2, STEEL)
    # 물 받이와 메탄 출구
    wx, wy = cx - 0.2, 1.6
    sp.cyl((wx, wy, 0.25), (wx, wy, 1.2), 0.42, Mat("#3E6FB0", 0.25), cap_mat=STEEL)
    pipe(sp, [(cx, cy + cr, 0.6), (cx, wy - 0.42, 0.6)], 0.16)
    if v in (1, 2):
        sp.sphere((-2.6, 1.5, 1.0), 0.8, WHITE)
        sp.ring3((-2.6, 1.5, 1.0), 0.8, "#c9a75a", 0.07)
        pipe(sp, [(-1.8, 1.5, 1.0), (-1.2, 1.5, 1.0), (-1.2, ty + tr, 1.0)], 0.16)
    # 입구 관 (CO₂·H₂)
    for k, col in enumerate(("#c9ccd1", "#D9532C")):
        _cpipe(sp, [(tx0 + 0.2, 0.9 + k * 0.4, 0.25), (tx0 + 0.2, 0.9 + k * 0.4, tz - 0.2), (tx0 + 0.2, ty + 0.3, tz - 0.2)],
               0.14, col)
    sp.lamp((cx + 0.2, cy + cr, ch + 0.4), AMBER, 8)
    sp.lamp((3.85, 2.3, 1.0), AMBER, 7)


@typed("microchannel_sabatier", 4, 4, 2.6, "마이크로채널 반응기", heights=[2.6, 2.6, 2.6, 2.9, 2.4])
def microchannel_sabatier(sp: Sprite, v: int):
    body = (BRASS, Mat("#C07A48", 0.5), Mat("#B9C0C8", 0.5), BRASS, Mat("#A8884A", 0.45))[v]
    grid = ("#6b5428", "#6e3f22", "#5f6670", "#6b5428", "#5e4a24")[v]
    cs = (2.1, 2.1, 2.1, 1.7, 2.3)[v]
    ch = (2.0, 2.0, 2.0, 1.5, 1.7)[v]
    sp.contact_shadow(0, 0, 2.4, 2.4)
    sp.box(-1.9, -1.9, 0, 3.8, 3.8, 0.2, CONCRETE)
    x0, y0 = -1.4, -1.4
    blocks = [(x0, y0, 0.2, cs, ch)]
    if v == 3:
        blocks.append((x0 + 0.25, y0 + 0.25, 0.2 + ch, cs - 0.5, 1.0))
    for bx, by, bz, s, h in blocks:
        sp.box(bx, by, bz, s, s, h, body, top=Mat("#D2B878", 0.5) if body is BRASS else body)
        f = Sprite.box_faces(bx, by, bz, s, s, h)
        n = int(s * 9)
        sp.panel_grid(*f["left"], n, int(h * 6), grid, 0.45, 0.7)
        sp.panel_grid(*f["right"], n, int(h * 6), grid, 0.45, 0.7)
        sp.panel_grid(*f["top"], n, n, grid, 0.4, 0.5)
        # 테두리 틀
        sp.polyline3([(bx, by + s, bz + h), (bx + s, by + s, bz + h), (bx + s, by, bz + h)], "#8a9099", 0.07)
        sp.line((bx + s, by + s, bz), (bx + s, by + s, bz + h), 0.07, "#8a9099")
    top = blocks[-1][2] + blocks[-1][4]
    # 위 헤더 둘과 가는 관
    for yy in (y0 + 0.4, y0 + cs - 0.4):
        sp.cyl((x0 + 0.2, yy, top + 0.12), (x0 + cs - 0.2, yy, top + 0.12), 0.1, STEEL, cap_mat=STEEL)
    tcol = ("#C98A55", "#c9ccd1", "#C98A55", "#C98A55", "#c9ccd1")[v]
    for k in range(5):
        y = y0 + 0.3 + k * (cs - 0.6) / 4
        sp.polyline3([(x0 + cs - 0.3, y, top + 0.12), (x0 + cs + 0.25 + k * 0.08, y, top + 0.12),
                      (x0 + cs + 0.25 + k * 0.08, y, 0.2)], tcol, 0.05)
    for k in range(3):
        x = x0 + cs - 0.5 - k * 0.45
        sp.polyline3([(x, y0 + cs, 0.5 + k * 0.4), (x, y0 + cs + 0.3 + k * 0.1, 0.5 + k * 0.4),
                      (x, y0 + cs + 0.3 + k * 0.1, 0.2)], tcol, 0.05)
    # 작은 제어함과 상태등
    bx, by = (1.15, 1.0) if v != 1 else (1.15, -1.6)
    sp.box(bx, by, 0.2, 0.6, 0.65, 0.9, Mat("#5B6470", 0.2), top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(bx, by, 0.2, 0.6, 0.65, 0.9)["right"], 0.2, 0.5, 0.8, 0.75), CYAN_LIGHT,
              frame=None)
    if v == 4:
        _fan(sp, x0 + cs / 2, y0 + cs / 2, top, 0.4)
    if v == 2:
        antenna(sp, (x0 + 0.2, y0 + 0.2, top), 1.0)
    sp.lamp((x0 + cs + 0.05, y0 + cs + 0.05, top - 0.15), AMBER, 7)


@typed("sabatier_compact", 3, 3, 2.4, "소형 사바티에 반응기", heights=[2.4, 2.4, 2.4, 2.4, 2.6])
def sabatier_compact(sp: Sprite, v: int):
    flip = v in (1, 3)                      # 반응기와 코일 자리를 바꾼다
    body = (SILVER, SILVER, WHITE, SILVER, WHITE)[v]
    rx, ry = (-0.42, -0.42) if not flip else (0.42, -0.5)
    kx, ky = (0.8, -0.55) if not flip else (-0.62, 0.72)
    rr, rh = 0.52, (1.15, 1.15, 1.15, 1.15, 1.35)[v]
    sp.contact_shadow(0, 0, 1.9, 1.9)
    sp.box(-1.4, -1.4, 0, 2.8, 2.8, 0.1, STEEL)
    pz = 0.7
    top = pz + 0.09 + rh + rr * 0.45 + 0.3

    def reactor():
        px0, py0, ps = rx - 0.72, ry - 0.72, 1.44
        for x, y in ((px0, py0), (px0 + ps, py0), (px0, py0 + ps)):
            sp.line((x, y, 0.1), (x, y, pz), 0.09, "#7d848d")
        sp.box(px0 - 0.05, py0 - 0.05, pz, ps + 0.1, ps + 0.1, 0.09, STEEL)
        sp.line((px0 + ps, py0 + ps, 0.1), (px0 + ps, py0 + ps, pz), 0.09, "#7d848d")
        p0, p1 = _vtank(sp, rx, ry, pz + 0.09, rh, rr, body, top="dish", bands=[0.15, 0.85])
        cyl_ring(sp, p0, p1, rr, 0.45, 0.58, SAB_GOLD)
        sp.window(Sprite.cyl_patch(p0, p1, rr, 0.22, 0.36, 55, 95), HOT, frame=None, glass=Mat("#E8662A", 0.3),
                  light_alpha=0.6)
        sp.cyl((rx, ry, top - 0.3), (rx, ry, top - 0.1), 0.11, STEEL)
        sp.lamp((px0 + ps + 0.05, py0 + ps + 0.05, pz + 0.25), AMBER, 6)

    def coil():
        # 응축 코일 (나선, 뒤쪽 반 → 받침대 → 앞쪽 반) + 물받이
        sp.cyl((kx, ky, 0.1), (kx, ky, 0.42), 0.34, Mat("#3E6FB0", 0.25) if v != 2 else WHITE, cap_mat=STEEL)
        turns, kr, z0, z1 = 6, 0.36, 0.6, 1.6
        pts = []
        for i in range(turns * 16 + 1):
            t = i / (turns * 16)
            ang = 2 * math.pi * turns * t
            pts.append((kx + kr * math.cos(ang), ky + kr * math.sin(ang), z0 + (z1 - z0) * t))

        def runs(front):
            out, cur = [], []
            for q in pts:
                if (dot((q[0] - kx, q[1] - ky, 0.0), VIEW) > 0) == front:
                    cur.append(q)
                elif cur:
                    out.append(cur + [q])
                    cur = []
            return out + ([cur] if len(cur) > 1 else [])
        for run in runs(False):
            sp.polyline3(run, "#8a5a32", 0.07)
        sp.line((kx, ky, 0.42), (kx, ky, z1 + 0.15), 0.07, "#7d848d")
        for run in runs(True):
            sp.polyline3(run, "#D08A50", 0.08)
    sp.parts([((rx, ry, 0.5), reactor), ((kx, ky, 0.5), coil)])
    pipe(sp, [(rx, ry, top - 0.1), (rx, ry, top + 0.1), (kx, ky, top + 0.1), (kx, ky, 1.6)], 0.12)
    if v == 3:
        _bottle(sp, 1.0, 0.95, 0.1, 1.1, 0.25, WHITE)
    if v == 4:
        sp.box(-1.25, 0.55, 0.1, 0.75, 0.7, 0.8, Mat("#5B6470", 0.2), top=SILVER)
        antenna(sp, (-0.88, 0.9, 0.9), 1.3)


# ── 물 재활용 계열 ───────────────────────────────────────────────────

@typed("vapor_compressor", 5, 4, 3.0, "증기 압축 증류기", heights=[3.0, 3.0, 3.0, 3.2, 3.0])
def vapor_compressor(sp: Sprite, v: int):
    drum = (Mat("#C3D5E6", 0.35), Mat("#C3D5E6", 0.35), WHITE, Mat("#C3D5E6", 0.35), Mat("#9FB8CC", 0.35))[v]
    acc = (BLUE, TEAL, BLUE, BLUE, WHITE)[v]
    dx, dz, dr = -0.75, 1.5, 1.05
    dy0, dy1 = -1.6, (0.75, 0.75, 0.55, 0.75, 0.75)[v]
    tank_left = v == 2
    sp.contact_shadow(0, 0, 3.0, 2.6)
    sp.box(-2.4, -1.9, 0, 4.8, 3.8, 0.2, CONCRETE)
    if v == 3:
        _radiator(sp, (0.6, -1.85, 0.2), (1.7, 0, 0), (0, 0, 2.6), 5)
    # 받침 + 회전 드럼 (축이 y 방향, 끝판이 보인다)
    for y in (dy0 + 0.5, dy1 - 0.5):
        sp.box(dx - 0.85, y - 0.15, 0.2, 1.7, 0.3, 0.55, STEEL)
    pd0, pd1 = (dx, dy0, dz), (dx, dy1, dz)
    sp.cyl(pd0, pd1, dr, drum, bands=[0.2, 0.5, 0.8], band_color="#8fa3b5", cap_mat=Mat("#E8E4DA", 0.1))
    cyl_ring(sp, pd0, pd1, dr, 0.33, 0.4, acc)
    c = (dx, dy1 + 0.01, dz)
    sp.ring3(c, dr * 0.92, "#8a9099", 0.06, normal=(0, 1, 0), front_only=False)
    for k in range(8):                      # 끝판의 바퀴살 (도는 드럼)
        a = 2 * math.pi * k / 8 + 0.3
        sp.line(add(c, (0.35 * math.cos(a), 0.0, 0.35 * math.sin(a))),
                add(c, (0.9 * dr * math.cos(a + 0.25), 0.0, 0.9 * dr * math.sin(a + 0.25))), 0.06, "#9aa1aa")
    # 모터 하우징 (드럼 축 끝)
    mlen = (0.75, 0.9, 0.75, 0.75, 0.75)[v]
    sp.cyl((dx, dy1, dz), (dx, dy1 + mlen, dz), 0.5, Mat("#5B6470", 0.25), cap_mat=STEEL,
           bands=[0.2, 0.4, 0.6, 0.8], band_color="#3a3f47")
    sp.ring3((dx, dy1 + mlen + 0.01, dz), 0.32, "#9aa1aa", 0.05, normal=(0, 1, 0), front_only=False)
    sp.box(dx - 0.3, dy1 + 0.1, 0.2, 0.6, mlen - 0.1, dz - 0.6, STEEL)
    # 응축수 탱크 (파란 띠)
    tx, ty = (1.55, -0.9) if not tank_left else (1.55, 1.2)
    p0, p1 = _vtank(sp, tx, ty, 0.2, 1.5, 0.55, WHITE)
    cyl_ring(sp, p0, p1, 0.55, 0.55, 0.68, BLUE)
    sp.window(Sprite.cyl_patch(p0, p1, 0.55, 0.2, 0.45, 40, 80), "#cfe9ff", frame=None, glass=Mat("#7fa7cf", 0.5),
              light_alpha=0.0)
    pipe(sp, [(dx, -0.4, dz + dr), (dx, -0.4, dz + dr + 0.25), (tx, -0.4, dz + dr + 0.25), (tx, ty, dz + dr + 0.25),
              (tx, ty, 2.25)], 0.16)
    if v != 2:
        sp.box(0.8, 0.6, 0.2, 1.3, 1.0, 1.0, Mat("#5B6470", 0.2), top=SILVER)
        fb = Sprite.box_faces(0.8, 0.6, 0.2, 1.3, 1.0, 1.0)
        _slots(sp, fb["right"], 4, 0.15, 0.85, 0.2, 0.8, CHAR)
        sp.window(sp.on_face(*fb["left"], 0.2, 0.5, 0.5, 0.75), WATER_LIGHT, frame=None)
    if v == 4:
        antenna(sp, (-2.1, -1.6, 0.2), 2.6)
    sp.lamp((dx + 0.6, dy1 + mlen, dz + 0.65), WATER_LIGHT, 7)


@typed("membrane_bioreactor", 8, 5, 3.6, "막 생물반응기", heights=[3.6, 3.6, 3.4, 3.6, 3.6])
def membrane_bioreactor(sp: Sprite, v: int):
    nc = (3, 2, 4, 3, 3)[v]
    blower_back = v in (1, 3)
    sp.contact_shadow(0, 0, 4.6, 3.0)
    x0, y0, w, d, h = (-3.8, -2.2, 6.3, 4.0, 1.9) if not blower_back else (-2.4, -2.2, 6.0, 4.0, 1.9)
    # 콘크리트 수조 + 초록 물이 비치는 유리 덮개
    sp.box(x0, y0, 0, w, d, h, CONCRETE, top=Mat("#8E8273"))
    f = Sprite.box_faces(x0, y0, 0, w, d, h)
    _panel(sp, f["left"], 0.0, 0.86, 1.0, 0.93, Mat("#3E6FB0", 0.2))
    zt = h
    gx0, gx1 = x0 + 0.25, x0 + w - 0.25
    for k in range(4):
        a = gx0 + (gx1 - gx0) * k / 4 + 0.06
        b = gx0 + (gx1 - gx0) * (k + 1) / 4 - 0.06
        sp.window([(a, y0 + 0.25, zt), (b, y0 + 0.25, zt), (b, y0 + d - 0.25, zt), (a, y0 + d - 0.25, zt)],
                  ALGAE_GLOW, frame="#5f6670", glass=WATER_GREEN, light_alpha=0.45)
    for i in range(6):                     # 물속 기포 줄
        yy = y0 + 0.6 + i * (d - 1.2) / 5
        sp.line2((gx0 + 0.3, yy, zt + 0.01), (gx1 - 0.3, yy, zt + 0.01), "#7fc48f", 0.6)
    # 막 카세트 (흰 틀에 세운 막판)
    for i in range(nc):
        cx = gx0 + 0.5 + (gx1 - gx0 - 1.0 - 1.4) * (i / max(1, nc - 1))
        sp.box(cx, y0 + 1.0, zt, 1.4, 0.75, 1.25, WHITE, top=SILVER)
        fc = Sprite.box_faces(cx, y0 + 1.0, zt, 1.4, 0.75, 1.25)
        sp.panel_grid(*fc["left"], 9, 1, "#9aa3ad", 0.6, 0.9)
        _panel(sp, fc["left"], 0.0, 0.88, 1.0, 0.95, Mat("#3E6FB0", 0.2))
        sp.line((cx + 0.7, y0 + 1.37, zt + 1.25), (cx + 0.7, y0 + 1.37, zt + 1.5), 0.06, "#7d848d")
    if v == 3:
        sp.line((gx0 + 0.2, y0 + 1.37, zt + 1.55), (gx1 - 0.2, y0 + 1.37, zt + 1.55), 0.14, "#E9C24A")
        for x in (gx0 + 0.2, gx1 - 0.2):
            sp.line((x, y0 + 1.37, zt), (x, y0 + 1.37, zt + 1.6), 0.12, "#E9C24A")
    # 폭기관 (파란 관이 앞면을 따라 가다가 수조로 내려간다)
    yp = y0 + d + 0.2
    _cpipe(sp, [(x0 + 0.3, yp, 0.5), (x0 + w + 0.2, yp, 0.5)], 0.2, "#5d8fd0")
    for i in range(5):
        x = x0 + 0.6 + i * (w - 1.2) / 4
        _cpipe(sp, [(x, yp, 0.5), (x, yp, zt + 0.25), (x, y0 + d - 0.3, zt + 0.25)], 0.12, "#5d8fd0")
    # 송풍기 (상자 + 팬) — 끝
    bx = x0 + w + 0.2 if not blower_back else -3.9
    if not blower_back:
        sp.box(bx, -1.6, 0, 1.25, 1.8, 1.3, WHITE, top=SILVER)
        _fan(sp, bx + 0.62, -0.7, 1.3, 0.48)
        fb = Sprite.box_faces(bx, -1.6, 0, 1.25, 1.8, 1.3)
        _slots(sp, fb["right"], 4, 0.15, 0.85, 0.2, 0.75)
        sp.cyl((bx + 0.6, 1.2, 0), (bx + 0.6, 1.2, 1.2), 0.45, Mat("#3E6FB0", 0.25), cap_mat=STEEL)
    else:
        sp.box(bx, -1.0, 0, 1.3, 1.8, 1.3, WHITE, top=SILVER)
        _fan(sp, bx + 0.65, -0.1, 1.3, 0.48)
        sp.cyl((-3.3, 1.6, 0), (-3.3, 1.6, 1.3), 0.45, Mat("#3E6FB0", 0.25), cap_mat=STEEL)
    if v == 4:
        antenna(sp, (x0 + 0.3, y0 + 0.3, zt), 1.8)
    sp.lamp((x0 + w + 0.05, y0 + d + 0.05, zt - 0.3), WATER_LIGHT, 8)
    sp.glow((x0 + w / 2, y0 + d / 2, zt + 0.3), 40, ALGAE_GLOW, 0.25)


@typed("forward_osmosis", 5, 3, 2.4, "정삼투 정수기", heights=[2.4, 2.4, 2.4, 2.6, 2.4])
def forward_osmosis(sp: Sprite, v: int):
    n = (7, 6, 8, 7, 6)[v]
    pm = (POUCH, Mat("#D8E8D8", 0.45), POUCH, Mat("#E4E8EE", 0.45), POUCH)[v]
    fcol = ("#8a9099", "#8a9099", "#E9C24A", "#8a9099", "#8a9099")[v]
    tx = (1.85, 1.85, -1.85, 1.85, 1.85)[v]          # 유도 용액 탱크 자리
    zt = (2.25, 2.25, 2.25, 2.4, 2.25)[v]
    x0, x1 = (-2.15, 1.15) if tx > 0 else (-1.15, 2.15)
    sp.contact_shadow(0, 0, 2.9, 1.9)
    # 받침 수조 (파란 유도 용액)
    sp.box(-2.35, -1.3, 0, 4.7, 2.6, 0.3, STEEL, top=Mat("#3E6FB0", 0.6))
    yr = 0.15                               # 매단 줄의 y
    # 틀: 양 끝 문형 기둥 + 위 막대
    def portal(x):
        for y in (-0.75, 1.05):
            sp.line((x, y, 0.3), (x, y, zt), 0.09, fcol)
        sp.line((x, -0.75, zt), (x, 1.05, zt), 0.09, fcol)
    portal(x0)
    if tx > 0:
        p0, p1 = _vtank(sp, tx, -0.6, 0.3, 1.3, 0.38, WHITE)
        cyl_ring(sp, p0, p1, 0.38, 0.5, 0.62, BLUE)
    sp.line((x0, yr, zt), (x1, yr, zt), 0.12, fcol)
    # 매단 막 주머니 (넓은 면이 해를 본다)
    span = x1 - x0 - 0.6
    for i in range(n):
        x = x0 + 0.3 + span * i / (n - 1)
        sp.line((x, yr, zt), (x, yr, zt - 0.22), 0.04, "#7d848d")
        sp.ellipsoid((x, yr, 1.3), 0.22, 0.09, 0.8, pm)
        sp.line((x - 0.16, yr + 0.08, 0.95), (x + 0.16, yr + 0.08, 0.95), 0.05, "#7fa7cf")
        sp.line((x, yr + 0.09, 0.55), (x, yr + 0.09, 0.4), 0.04, "#5d8fd0")
    portal(x1)
    if tx < 0:
        p0, p1 = _vtank(sp, tx, -0.6, 0.3, 1.3, 0.38, WHITE)
        cyl_ring(sp, p0, p1, 0.38, 0.5, 0.62, BLUE)
    # 모음관
    _cpipe(sp, [(x0 + 0.2, yr + 0.1, 0.42), (x1 - 0.2, yr + 0.1, 0.42)], 0.1, "#5d8fd0")
    _cpipe(sp, [(tx, -0.22, 0.6), (tx, 0.9, 0.6), (x1 if tx > 0 else x0, 0.9, 0.6)], 0.12, "#5d8fd0")
    if v == 3:
        sp.quad((x0 - 0.05, -0.85, zt + 0.08), (x1 - x0 + 0.1, 0, 0), (0, 2.0, 0.0), Mat("#D9C9A3"),
                back=Mat("#B9AA88"))
    if v == 4:
        sp.box(tx - 0.35, 0.55, 0.3, 0.7, 0.6, 0.7, Mat("#5B6470", 0.2), top=SILVER)
    sp.lamp((tx, -0.6, 2.15), WATER_LIGHT, 6)


@typed("multifilter_plant", 9, 5, 4.0, "다중 여과 정수장", heights=[4.0, 4.0, 3.8, 4.0, 4.2])
def multifilter_plant(sp: Sprite, v: int):
    body = (WHITE, WHITE, Mat("#DDE6EE", 0.2), WHITE, WHITE)[v]
    pc = ("#5d8fd0", "#c9ccd1", "#5d8fd0", "#5d8fd0", "#c9ccd1")[v]
    zig = v in (1, 3)
    media = (Mat("#C9B48A"), CHAR, AMINE, Mat("#E8EEF2", 0.4), Mat("#9B7AD6", 0.4))
    sp.contact_shadow(0, 0, 5.0, 3.0)
    sp.box(-4.4, -2.4, 0, 8.8, 4.8, 0.25, CONCRETE)
    cols = [(-3.5, 0.85, 3.2), (-1.95, 0.72, 2.7), (-0.6, 0.6, 2.25), (0.55, 0.5, 1.85), (1.5, 0.4, 1.45)]
    if v == 2:
        cols = [(x, r, h * 0.92) for x, r, h in cols]
    if v == 4:
        cols = [(x, r, h + 0.2) for x, r, h in cols]
    yp = 0.75
    tops = []
    for i, (x, r, h) in enumerate(cols):
        y = -0.6 + (0.35 if zig and i % 2 else 0.0)
        p0, p1 = _vtank(sp, x, y, 0.25, h, r, body, top="dish", bands=[0.15, 0.85], band_color="#a8b4c0")
        cyl_ring(sp, p0, p1, r, 0.7, 0.76, BLUE)
        sp.window(Sprite.cyl_patch(p0, p1, r, 0.25, 0.6, 70, 105), WATER_LIGHT, frame="#2a2f36", glass=media[i],
                  light_alpha=0.0)
        sp.cyl(add(p1, (0, 0, r * 0.4)), add(p1, (0, 0, r * 0.4 + 0.2)), 0.1 + r * 0.1, STEEL)
        tops.append((x, y, r, h))
    # 단마다 이어지는 관 (위에서 나와 다음 칸 아래로)
    for i in range(4):
        x, y, r, h = tops[i]
        xn, yn, rn, hn = tops[i + 1]
        zt = 0.25 + h - 0.35
        xm = (x + r + xn - rn) / 2
        _cpipe(sp, [(x, y + r, zt), (x, yp, zt), (xm, yp, zt), (xm, yp, 0.6), (xn, yp, 0.6), (xn, yn + rn, 0.6)], 0.15, pc)
    # 촉매 반응 상자 (끝)
    bx = 2.35
    sp.box(bx, -1.5, 0.25, 1.75, 2.7, 1.7, Mat("#6B5A4C", 0.15), top=STEEL)
    fb = Sprite.box_faces(bx, -1.5, 0.25, 1.75, 2.7, 1.7)
    sp.window(sp.on_face(*fb["left"], 0.25, 0.4, 0.75, 0.68), "#ff7b2e", frame="#2a2f36", glass=Mat("#ff7b2e", 0.3))
    _slots(sp, fb["right"], 4, 0.15, 0.85, 0.2, 0.75, CHAR)
    sp.stripes(add(fb["left"][0], (0, 0.01, 1.35)), (-1.75, 0, 0), (0, 0, 0.22), n=6, normal=(0, 1, 0))
    sp.cyl((bx + 0.5, -0.9, 1.95), (bx + 0.5, -0.9, 2.9 if v != 4 else 3.4), 0.16, STEEL, cap_mat=CHAR)
    x, y, r, h = tops[-1]
    _cpipe(sp, [(x, y + r, 0.25 + h - 0.3), (x, yp + 0.4, 0.25 + h - 0.3), (bx + 0.3, yp + 0.4, 0.25 + h - 0.3),
                (bx + 0.3, yp + 0.4, 1.95)], 0.15, pc)
    if v in (0, 3):
        p0, p1 = _vtank(sp, 3.6, 1.75, 0.25, 1.1, 0.45, Mat("#3E6FB0", 0.25))
    if v == 2:
        antenna(sp, (4.0, -2.0, 0.25), 3.2)
    sp.lamp((bx + 1.8, 1.25, 1.7), WATER_LIGHT, 7)


# ── 저장 탱크 계열 ───────────────────────────────────────────────────

def _frost(sp: Sprite, p0, p1, r, s, a, size=0.12, mat: Mat = SNOW, k=0):
    """원기둥 겉면의 들쭉날쭉한 성에 조각 (축 방향 s, 각도 a[도])."""
    axis = sub(p1, p0)
    L = length(axis)
    u, w = basis(axis)
    pts = []
    for i in range(9):
        t = 2 * math.pi * i / 9
        rr = size * (0.75 + 0.35 * math.sin(3.7 * i + k))
        ds = rr * math.sin(t) / L
        da = math.degrees(rr * math.cos(t) * 1.6 / r)
        ang = math.radians(a + da)
        radial = add(mul(u, math.cos(ang)), mul(w, math.sin(ang)))
        pts.append(add(add(p0, mul(axis, s + ds)), mul(radial, r + 0.02)))
    sp.face(pts, mat, edge=False, ao=0)


@typed("cryo_tank", 7, 6, 6.0, "극저온 탱크", heights=[6.0, 6.0, 5.6, 6.0, 6.2])
def cryo_tank(sp: Sprite, v: int):
    th = (2.75, 2.75, 2.35, 2.75, 2.95)[v]
    cool_left = v in (1, 3)
    band = (BLUE, BLUE, TEAL, BLUE, BLUE)[v]
    frost_n = (6, 9, 6, 4, 7)[v]
    sp.contact_shadow(0, 0, 4.0, 3.4)
    sp.box(-3.4, -2.9, 0, 6.8, 5.8, 0.25, CONCRETE)
    sp.polyline3([(-3.2, 2.7, 0.26), (3.2, 2.7, 0.26), (3.2, -2.7, 0.26)], "#5d8fd0", 0.12)
    tanks = ((-1.75, -1.15), (0.95, -1.4)) if v != 4 else ((-1.85, -1.3), (0.85, -1.55))
    r, zb = 1.12, 1.95
    for i, (x, y) in enumerate(tanks):
        lg = [(x - 0.8, y - 0.8), (x + 0.8, y - 0.8), (x - 0.8, y + 0.8), (x + 0.8, y + 0.8)]
        legs(sp, [(lx, ly, zb - 0.2) for lx, ly in lg[:3]], 0.25, 0.14)
        sp.sphere((x, y, zb), r, WHITE)
        p0, p1 = (x, y, zb), (x, y, zb + th)
        sp.cyl(p0, p1, r, WHITE, bands=[0.33, 0.66], band_color="#c3cbd2")
        sp.sphere(p1, r, WHITE, clip_z=zb + th)
        cyl_ring(sp, p0, p1, r, 0.8, 0.86, band)
        # 성에: 아래쪽에 많이, 위로 갈수록 드물게
        for k in range(frost_n):
            s = 0.06 + 0.8 * ((k * 0.37 + i * 0.21) % 1.0) ** 1.6
            a = Sprite.facing_angle(p0, p1) + (-75 + 150 * ((k * 0.61 + i * 0.3) % 1.0))
            _frost(sp, p0, p1, r, s, a, 0.24 + 0.14 * ((k * 0.43) % 1.0), FROST_BLUE, k)
        legs(sp, [(x + 0.8, y + 0.8, zb - 0.2)], 0.25, 0.14)
        sp.cyl((x, y, zb + th + r * 0.92), (x, y, zb + th + r + 0.2), 0.16, STEEL)
    # 저온 냉각기 + 방열 지느러미
    cx, cy = (1.1, 1.0) if not cool_left else (-2.9, 1.1)
    sp.box(cx, cy, 0.25, 1.7, 1.4, 1.2, WHITE, top=SILVER)
    fc = Sprite.box_faces(cx, cy, 0.25, 1.7, 1.4, 1.2)
    _panel(sp, fc["left"], 0.0, 0.8, 1.0, 0.9, band)
    sp.window(sp.on_face(*fc["left"], 0.15, 0.35, 0.4, 0.6), CYAN_LIGHT, frame=None)
    nfin = (5, 5, 4, 6, 5)[v]
    for k in range(nfin):
        y = cy + 0.15 + 1.1 * k / (nfin - 1)
        _radiator(sp, (cx + 1.6, y, 1.45), (-1.5, 0, 0), (0, 0, 1.3), 4)
    sp.cyl((cx + 0.3, cy + 0.3, 1.45), (cx + 0.3, cy + 0.3, 2.0), 0.18, STEEL)
    # 단열 배관 (성에 낀 굵은 관)
    tx, ty = tanks[1] if not cool_left else tanks[0]
    sp.polyline3([(cx + 0.3, cy + 0.3, 2.0), (cx + 0.3, ty + 0.4, 2.0), (tx + 0.3, ty + 0.4, 2.0)], "#c3cbd2", 0.26)
    sp.polyline3([(cx + 0.3, cy + 0.3, 2.0), (cx + 0.3, ty + 0.4, 2.0), (tx + 0.3, ty + 0.4, 2.0)], "#EEF4F7", 0.18)
    # 앞쪽 충전대 (밸브 상자) 와 아래 배관
    fx = -0.4 if not cool_left else 1.4
    for x, y in tanks:
        _cpipe(sp, [(x, y + 0.9, 0.85), (x, 1.9, 0.85), (fx + 0.5, 1.9, 0.85)], 0.2, "#EEF4F7", "#9fb3c2")
    sp.box(fx, 1.6, 0.25, 1.0, 0.9, 1.0, STEEL, top=SILVER)
    for k in range(2):
        _valve(sp, (fx + 0.3 + k * 0.4, 2.52, 0.75), "#3E6FB0", normal=(0, 1, 0), r=0.13)
    if v == 2:
        sp.cyl((2.9, -2.4, 0.25), (2.9, -2.4, 3.6), 0.13, STEEL, cap_mat=CHAR)
        sp.lamp((2.9, -2.4, 3.7), "#ff5a3c", 6)
    if v == 3:
        antenna(sp, (tanks[0][0], tanks[0][1], zb + th + r + 0.2), 1.0)
    sp.lamp((3.0, 2.4, 1.6), CYAN_LIGHT, 8)
    sp.lamp((tanks[1][0], tanks[1][1] + r, zb + th - 0.3), AMBER, 6)


@typed("water_cistern", 10, 8, 1.5, "매립 물탱크", heights=[1.5, 1.5, 1.6, 1.5, 1.5])
def water_cistern(sp: Sprite, v: int):
    shed_left = v in (1, 4)
    nvent = (2, 3, 2, 1, 3)[v]
    sp.contact_shadow(0, 0, 5.4, 4.4, 0.4)
    mx, my = (-0.6, -0.4) if not shed_left else (0.5, -0.5)
    rx, ry, rz = 4.3, 3.3, 1.4
    mound = Mat("#8A8378")
    sp.ellipsoid((mx, my, 0), rx, ry, rz, mound, clip_z=0.0)
    sandbag_rings(sp, (mx, my, 0), rx, ry, rz, (0.3, 0.65, 0.95, 1.2), "#6c665f")

    def zon(x, y):
        k = 1 - ((x - mx) / rx) ** 2 - ((y - my) / ry) ** 2
        return rz * math.sqrt(max(0.0, k))
    for x, y, sz in ((-4.3, 3.4, 0.4), (4.4, -3.4, 0.35), (-3.7, -3.5, 0.3)):
        sp.rock((x, y, 0), sz)
    # 납작한 점검 뚜껑 (파란 테두리)
    hatches = [(mx - 0.6, my - 0.6)] + ([(mx + 1.4, my + 0.5)] if v == 2 else [])
    for hx, hy in hatches:
        z = zon(hx + 0.6, hy + 0.6)
        sp.box(hx - 0.1, hy - 0.1, z - 0.12, 1.4, 1.4, 0.18, Mat("#5d8fd0", 0.2))
        sp.box(hx, hy, z - 0.1, 1.2, 1.2, 0.24, STEEL, top=Mat("#A8AFB8", 0.35))
        sp.line((hx + 0.35, hy + 0.6, z + 0.16), (hx + 0.85, hy + 0.6, z + 0.16), 0.07, "#2a2f36")
    # 환기관 (갈고리 머리)
    vents = [(mx - 2.3, my - 1.1), (mx + 1.9, my - 1.5), (mx - 1.3, my + 1.6)][:nvent]
    for vx, vy in vents:
        z = zon(vx, vy)
        pts = [(vx, vy, z - 0.1), (vx, vy, z + 0.85), (vx + 0.22, vy + 0.22, z + 1.05), (vx + 0.38, vy + 0.38, z + 0.88)]
        sp.polyline3(pts, "#5c626b", 0.28)
        sp.polyline3(pts, "#d4d7db", 0.2)
    # 작은 양수 오두막 (둔덕 옆) — 관이 둔덕으로 들어간다
    sx, sy = ((2.9, 1.6) if not shed_left else (-4.4, 1.8)) if v != 3 else (3.0, -0.9)
    px0, px1 = (sx, sx - 0.9) if not shed_left else (sx + 1.7, sx + 2.6)
    _cpipe(sp, [(px0, sy + 0.4, 0.45), (px1, sy + 0.4, 0.45)], 0.22, "#5d8fd0")
    sp.box(sx, sy, 0, 1.7, 1.5, 1.4, WHITE, top=SILVER)
    fs = Sprite.box_faces(sx, sy, 0, 1.7, 1.5, 1.4)
    _panel(sp, fs["left"], 0.0, 0.8, 1.0, 0.9, BLUE)
    door(sp, fs["right"], 0.25, 0.7, 0.75, STEEL)
    sp.window(sp.on_face(*fs["left"], 0.25, 0.4, 0.6, 0.65), WATER_LIGHT)
    if v == 4:
        sp.quad((sx + 0.1, sy + 0.1, 1.45), (1.5, 0, 0), (0, 1.3, 0.35), SOLAR, back=STEEL)
    if v in (0, 2):
        sp.line((sx - 0.3, sy + 1.3, 0), (sx - 0.3, sy + 1.3, 1.6), 0.08, "#8a9099")
        sp.box(sx - 0.42, sy + 1.18, 1.0, 0.25, 0.25, 0.5, Mat("#5d8fd0", 0.2))
    sp.lamp((sx + 1.75, sy + 1.55, 1.5), WATER_LIGHT, 8)


@typed("gas_rack", 7, 4, 3.0, "고압 기체 저장대", heights=[3.0, 3.0, 2.4, 3.0, 3.2])
def gas_rack(sp: Sprite, v: int):
    rack = ("#8a9099", "#8a9099", "#D9893F", "#E9C24A", "#8a9099")[v]
    tiers = (0.72, 1.36, 2.0) if v != 2 else (0.72, 1.36)
    palettes = ((RED, WHITE, BLUE, Mat("#5FA35A", 0.2), YELLOW, WHITE),
                (WHITE, WHITE, RED, BLUE, BLUE, YELLOW),
                (YELLOW, RED, WHITE, BLUE),
                (Mat("#5FA35A", 0.2), WHITE, RED, WHITE, BLUE, RED),
                (RED, RED, WHITE, WHITE, BLUE, BLUE))[v]
    sp.contact_shadow(0, 0, 4.0, 2.6)
    sp.box(-3.4, -1.9, 0, 6.8, 3.8, 0.2, CONCRETE)
    ya, yb, r = -1.45, 1.3, 0.27
    zt = tiers[-1] + 0.45
    posts = (-3.2, 0.0, 3.2)
    yr, yf = ya + 0.15, yb + 0.3            # 뒤·앞 기둥 줄 (앞 기둥은 색 뚜껑보다 앞)
    for x in posts:
        sp.line((x, yr, 0.2), (x, yr, zt), 0.12, rack)
    sp.polyline3([(posts[0], yf, zt), (posts[0], yr, zt), (posts[-1], yr, zt)], rack, 0.12)
    xs = [-2.85, -2.25, -1.65, -1.05, -0.45, 0.45, 1.05, 1.65, 2.25, 2.85]
    for t, z in enumerate(tiers):
        for y in (ya + 0.3, yb - 0.4):
            sp.line((posts[0], y, z - r - 0.05), (posts[-1], y, z - r - 0.05), 0.1, rack)
        for i, x in enumerate(xs):
            cap = palettes[(t * 2 + (i >= 5)) % len(palettes)]
            sp.cyl((x, ya, z), (x, yb, z), r, COMPOSITE, cap_mat=Mat("#6a6f76", 0.3), bands=[0.08, 0.92],
                   band_color="#3a3d42")
            sp.cyl((x, yb, z), (x, yb + 0.16, z), 0.16, cap)
    # 분배 관과 압력계 (오른쪽 끝)
    pipe(sp, [(3.25, ya + 0.3, 0.5), (3.25, yb - 0.2, 0.5), (3.25, yb - 0.2, zt - 0.2)], 0.14)
    for z in tiers:
        sp.disc((3.33, yb - 0.2, z), (1, 0, 0), 0.14, WHITE, edge=True)
    for x in posts:
        sp.line((x, yf, 0.2), (x, yf, zt), 0.12, rack)
    sp.polyline3([(posts[0], yf, zt), (posts[-1], yf, zt), (posts[-1], yr, zt)], rack, 0.12)
    if v in (0, 3):
        sp.quad((-3.3, ya, zt + 0.15), (6.6, 0, 0), (0, yf - ya + 0.1, 0.25), Mat("#C9CED4", 0.3), back=STEEL)
    if v == 4:
        sp.box(-3.3, -1.85, zt + 0.05, 6.6, 0.25, 0.25, STEEL)
        antenna(sp, (3.2, -1.3, zt), 1.0)
    sp.lamp((3.2, yf, zt + 0.12), AMBER, 8)


@typed("bladder_store", 8, 6, 1.8, "팽창식 저장 주머니", heights=[1.8, 1.8, 1.6, 1.8, 2.0])
def bladder_store(sp: Sprite, v: int):
    layouts = (((-2.0, -1.45, 1.8, 1.25), (1.85, -1.5, 1.8, 1.2), (-2.0, 1.4, 1.8, 1.25), (1.6, 1.45, 1.6, 1.15)),
               ((-1.9, -1.4, 1.9, 1.3), (2.0, -1.2, 1.7, 1.4), (-1.6, 1.55, 2.1, 1.1)),
               ((-2.5, -1.5, 1.3, 1.2), (0.3, -1.6, 1.3, 1.1), (-2.4, 1.3, 1.35, 1.25), (0.5, 1.2, 1.3, 1.2),
                (2.75, -0.6, 1.0, 1.6)),
               ((-1.9, -1.45, 1.9, 1.25), (1.9, -1.45, 1.8, 1.25), (-0.1, 1.45, 3.4, 1.2)),
               ((-2.0, -1.45, 1.8, 1.25), (1.85, -1.5, 1.8, 1.2), (-2.0, 1.4, 1.8, 1.25), (1.6, 1.45, 1.6, 1.15)))[v]
    rz = (1.05, 1.05, 0.9, 1.05, 1.2)[v]
    fab = (CANVAS, Mat("#E2D8C3"), CANVAS, Mat("#D9C9A3"), Mat("#E8E1D0"))[v]
    stripes = ("#3E6FB0", "#3E6FB0", "#E07B39", "#3E6FB0", "#3FB8AF")[v]
    sp.contact_shadow(0, 0, 4.6, 3.4, 0.35)
    sp.box(-3.9, -2.9, 0, 7.8, 5.8, 0.1, SINTER)
    mx, my = (3.25, 2.3) if v != 3 else (3.25, -2.2)
    ports = []
    for x, y, rx, ry in sorted(layouts, key=lambda b: b[0] + b[1]):
        sp.ellipsoid((x, y, 0.1), rx, ry, rz, fab, clip_z=0.1)
        # 솔기 띠와 손잡이 고리
        pts = []
        for i in range(41):
            t = 2 * math.pi * i / 40
            if dot((math.cos(t), math.sin(t), 0.0), VIEW) > -0.05:
                pts.append((x + rx * 0.93 * math.cos(t), y + ry * 0.93 * math.sin(t), 0.1 + rz * 0.37))
        sp.polyline3(pts, stripes, 0.09, 0.9)
        px, py = x + rx * 0.35, y + ry * 0.35
        pz = 0.1 + rz * math.sqrt(max(0.0, 1 - 0.35 ** 2 * 2))
        sp.cyl((px, py, pz - 0.1), (px, py, pz + 0.15), 0.14, STEEL)
        ports.append((px, py, pz + 0.12))
    # 굵은 호스: 포트 → 분배함 (늘어진 곡선)
    for px, py, pz in ports:
        pts = []
        for i in range(13):
            t = i / 12
            x = px + (mx - px) * t
            y = py + (my - py) * t
            z = pz * (1 - t) + 0.5 * t + 0.35 * math.sin(math.pi * t) - 0.5 * t * (1 - t) * 2
            pts.append((x, y, max(0.18, z)))
        sp.polyline3(pts, "#2f3338", 0.15)
    sp.box(mx - 0.45, my - 0.45, 0.1, 0.8, 0.8, 0.9, Mat("#5B6470", 0.2), top=SILVER)
    fb = Sprite.box_faces(mx - 0.45, my - 0.45, 0.1, 0.8, 0.8, 0.9)
    sp.window(sp.on_face(*fb["left"], 0.2, 0.45, 0.8, 0.75), WATER_LIGHT, frame=None)
    if v == 4:
        sp.box(-3.7, 2.3, 0.1, 0.9, 0.5, 0.6, ORANGE)
    sp.lamp((mx + 0.4, my + 0.4, 1.2), AMBER, 8)


# ── 수경 농장 계열 ───────────────────────────────────────────────────

def _a_frame(sp: Sprite, x, y, z0, h, half, col="#5f9e4a"):
    """끝 유리창 너머로 보이는 A자 재배탑 (끝에서 본 모습) + 잎 점."""
    a, top, b = (x, y - half, z0), (x, y, z0 + h), (x, y + half, z0)
    sp.polyline3([a, top, b], col, 0.13)
    sp.line((x, y - half * 0.5, z0 + h * 0.5), (x, y + half * 0.5, z0 + h * 0.5), 0.06, "#8a9099")
    for k in range(1, 5):
        t = k / 5
        for p, q in ((a, top), (b, top)):
            c = add(p, mul(sub(q, p), t))
            sp.line(add(c, (0, -0.06, 0)), add(c, (0, 0.06, 0.04)), 0.12, "#8fd16a")


@typed("aeroponic_farm", 9, 5, 3.6, "공기분무 농장", heights=[3.6, 3.6, 3.6, 3.4, 3.6])
def aeroponic_farm(sp: Sprite, v: int):
    x0, x1 = -4.3, (3.9, 3.9, 3.3, 3.9, 3.9)[v]
    hw, zw, zr = 2.15, 1.0, (3.45, 3.45, 3.45, 3.2, 3.45)[v]
    acc = (Mat("#C04FB3", 0.2), Mat("#C04FB3", 0.2), ORANGE, Mat("#C04FB3", 0.2), TEAL)[v]
    sp.contact_shadow(0, 0, 5.0, 3.0)
    sp.box(-4.45, -2.4, 0, 8.9, 4.8, 0.2, SINTER)
    L = x1 - x0
    sp.face([(x0, -hw, zw), (x0, 0, zr), (x0, hw, zw)], WHITE)            # 뒤 박공 (3D에서만 보인다)
    # 낮은 벽
    sp.box(x0, -hw, 0.2, L, 2 * hw, zw - 0.2, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, -hw, 0.2, L, 2 * hw, zw - 0.2)
    _panel(sp, f["left"], 0.0, 0.62, 1.0, 0.78, acc)
    _slots(sp, f["left"], 8, 0.04, 0.96, 0.15, 0.45, Mat("#C9C3B6"), vertical=True)
    # 지붕 두 비탈: 흰 틀 위의 유리판 (앞 비탈에는 재배탑 줄이 비친다, 뒤 비탈은 3D에서만 보인다)
    nb = (6, 6, 5, 6, 7)[v]
    slopes = (((x0, -hw, zw), (L, 0, 0), (0, hw, zr - zw)), ((x1, hw, zw), (-L, 0, 0), (0, -hw, zr - zw)))
    for k, (o, e1, e2) in enumerate(slopes):
        sp.face(sp.on_face(o, e1, e2, 0.0, 0.0, 1.0, 1.0), Mat("#d9d4ca"), ao=0)
        for i in range(nb):
            u0, u1 = i / nb + 0.01, (i + 1) / nb - 0.01
            sp.window(sp.on_face(o, e1, e2, u0, 0.05, u1, 0.96), GROW, frame="#d9d4ca", glass=ROOF_GLASS,
                      light_alpha=0.8)
            if k == 0:
                continue
            for vv in (0.22, 0.5, 0.78):
                a = add(add(o, mul(e1, u0 + 0.01)), mul(e2, vv))
                b = add(add(o, mul(e1, u1 - 0.01)), mul(e2, vv))
                sp.line2(add(a, (0, 0.02, 0.02)), add(b, (0, 0.02, 0.02)), "#6DAE57", 1.3)
    sp.line((x0, 0, zr + 0.03), (x1, 0, zr + 0.03), 0.12, "#e8e3d8")
    # 끝 유리벽: A자 재배탑과 안개
    end = [(x1, -hw + 0.15, 0.35), (x1, hw - 0.15, 0.35), (x1, hw - 0.15, zw + 0.05), (x1, 0, zr - 0.15),
           (x1, -hw + 0.15, zw + 0.05)]
    sp.face([(x1, -hw, zw), (x1, hw, zw), (x1, 0, zr)], WHITE, normal=(1, 0, 0))
    sp.window(end, GROW, frame="#d9d4ca", glass=PINK_GLASS, light_alpha=0.8)
    for yy in (-1.05, 1.05):
        _a_frame(sp, x1 + 0.03, yy, 0.4, 2.0, 0.65)
    for yy, zz in ((-1.05, 0.7), (1.05, 0.75), (0.0, 1.2)):
        _puff(sp, (x1 + 0.05, yy, zz), 0.32, 0.5)
    sp.face([(x1 + 0.02, -0.35, 0.2), (x1 + 0.02, 0.35, 0.2), (x1 + 0.02, 0.35, 1.35), (x1 + 0.02, -0.35, 1.35)],
            Mat("#d9d4ca"), normal=(1, 0, 0), ao=0)
    sp.light_poly([(x1 + 0.03, -0.3, 0.2), (x1 + 0.03, 0.3, 0.2), (x1 + 0.03, 0.3, 1.3), (x1 + 0.03, -0.3, 1.3)],
                  "#ffcf8a", 0.5)
    # 용마루 환기구와 김
    nv = (2, 3, 2, 2, 1)[v]
    for k in range(nv):
        vx = x0 + L * (k + 1) / (nv + 1)
        sp.box(vx - 0.3, -0.25, zr - 0.05, 0.6, 0.5, 0.3, SILVER)
        _puff(sp, (vx, 0, zr + 0.55), 0.38, 0.6)
        _puff(sp, (vx + 0.25, 0.15, zr + 0.85), 0.28, 0.45)
    if v == 2:
        sp.box(x1 + 0.1, -2.1, 0.2, 0.95, 1.5, 1.6, WHITE, top=SILVER)
        sp.cyl((x1 + 0.6, 1.5, 0.2), (x1 + 0.6, 1.5, 1.4), 0.4, Mat("#3E6FB0", 0.25), cap_mat=STEEL)
    if v == 4:
        # 용마루 위 분무수 탱크
        for x in (x0 + 1.0, x0 + 2.6):
            sp.box(x - 0.1, -0.2, zr - 0.05, 0.2, 0.4, 0.3, STEEL)
        sp.cyl((x0 + 0.6, 0, zr + 0.5), (x0 + 3.0, 0, zr + 0.5), 0.32, WHITE, cap_mat=WHITE, bands=[0.5])
        cyl_ring(sp, (x0 + 0.6, 0, zr + 0.5), (x0 + 3.0, 0, zr + 0.5), 0.32, 0.2, 0.28, TEAL)
    sp.lamp((x1 + 0.1, 0.55, 1.55), AMBER, 8)
    sp.glow((0, 0, 2.4), 40, GROW, 0.4)


@typed("vertical_farm", 8, 8, 12.0, "수직 농장", heights=[12.0, 11.4, 12.0, 11.4, 12.4])
def vertical_farm(sp: Sprite, v: int):
    mirror = v in (1, 3)                    # 설비 기둥을 왼쪽 앞(+y)으로
    nfl = (8, 7, 8, 7, 8)[v]
    fh = 1.4 if v != 4 else 1.45
    H = nfl * fh
    acc = (ORANGE, TEAL, ORANGE, ORANGE, Mat("#C04FB3", 0.2))[v]
    sp.contact_shadow(0, 0, 4.4, 4.4, 0.5)
    sp.box(-3.9, -3.9, 0, 7.8, 7.8, 0.3, CONCRETE)
    if not mirror:
        gx0, gy0, gw, gd = -3.5, -3.5, 5.3, 7.0
        cx0, cy0, cw, cd = 1.8, -3.1, 1.9, 3.6
    else:
        gx0, gy0, gw, gd = -3.5, -3.5, 7.0, 5.3
        cx0, cy0, cw, cd = -3.1, 1.8, 3.6, 1.9
    zc = 0.3 + H + 0.9

    def core():
        sp.box(cx0, cy0, 0.3, cw, cd, H + 0.9, WHITE, top=SILVER)
        fc = Sprite.box_faces(cx0, cy0, 0.3, cw, cd, H + 0.9)
        face = fc["right"] if not mirror else fc["left"]
        _panel(sp, face, 0.42, 0.0, 0.58, 1.0, acc)
        for k in range(nfl):
            vv = (k * fh + 0.75) / (H + 0.9)
            sp.window(sp.on_face(*face, 0.15, vv, 0.32, vv + 0.25 / (H + 0.9) * 2), WARM_WINDOW)
            sp.window(sp.on_face(*face, 0.68, vv, 0.85, vv + 0.25 / (H + 0.9) * 2), WARM_WINDOW)
        door(sp, face, 0.36, 0.64, 1.9 / (H + 0.9))
        sp.box(cx0 + 0.3, cy0 + 0.3, zc, cw - 0.6, cd - 0.6, 0.5, STEEL)
    # 유리 재배탑: 층마다 분홍 유리 + 초록 선반
    sp.box(gx0, gy0, 0.3, gw, gd, H, WHITE, top=SILVER)
    fg = Sprite.box_faces(gx0, gy0, 0.3, gw, gd, H)
    # 네 면 모두 유리 (뒤 두 면은 3D에서만 보인다)
    faces = [fg["left"], fg["right"], ((gx0, gy0, 0.3), (gw, 0.0, 0.0), (0.0, 0.0, H)),
             ((gx0, gy0 + gd, 0.3), (0.0, -gd, 0.0), (0.0, 0.0, H))]
    for fi, frame in enumerate(faces):
        o, e1, e2 = frame
        for k in range(nfl):
            v0, v1 = (k * fh + 0.12) / H, ((k + 1) * fh - 0.1) / H
            sp.window(sp.on_face(o, e1, e2, 0.015, v0, 0.985, v1), GROW, frame=None, glass=PINK_GLASS,
                      light_alpha=0.85)
            for s in (0.18, 0.55):
                vs = v0 + (v1 - v0) * s
                _panel(sp, frame, 0.02, vs, 0.98, vs + 0.16 / H, Mat("#5E9E4A", 0.1))
                _panel(sp, frame, 0.02, vs + 0.16 / H, 0.98, vs + 0.2 / H, Mat("#9aa1aa", 0.2))
        if fi < 2:                          # 보이는 면의 세로 창살
            ncol = max(3, int(length(e1) / 1.1))
            out = mul(norm(cross(e1, e2)), 0.03)
            for i in range(1, ncol):
                a = add(o, mul(e1, i / ncol))
                sp.line(add(a, out), add(add(a, e2), out), 0.06, "#e6e1d6")
    # 지붕: 난간, 채광 돔 또는 방열판
    zt = 0.3 + H
    if v in (0, 3):
        sp.dome((gx0 + gw * 0.45, gy0 + gd * 0.45, zt), 1.4, 0.9, Mat("#cfe6f5", 0.8))
    elif v == 2:
        _radiator(sp, (gx0 + 0.6, gy0 + 1.0, zt), (gw - 1.2, 0, 0), (0, 0, 1.1), 6)
    else:
        sp.quad((gx0 + 0.5, gy0 + 0.5, zt + 0.3), (gw - 1.0, 0, 0), (0, gd * 0.5, 0.6), SOLAR, back=STEEL)
    core()
    antenna(sp, (cx0 + 0.5, cy0 + 0.5, zc + 0.5), 1.4)
    for k in range(2, nfl, 3):
        sp.glow((gx0 + gw * 0.5, gy0 + gd, 0.3 + k * fh), 30, GROW, 0.35)


@typed("potato_bay", 7, 5, 3.0, "감자 재배실", heights=[3.0, 3.0, 2.9, 3.0, 3.2])
def potato_bay(sp: Sprite, v: int):
    leaf = (LEAF, GREEN, LEAF, Mat("#5E9440"), LEAF)[v]
    rows = (3, 3, 2, 3, 3)[v]
    zf = 0.8
    vx0, vx1 = -2.9, 2.35
    r, rz = 1.85, (2.05, 2.05, 1.9, 2.05, 2.25)[v]
    sp.contact_shadow(0, 0, 4.0, 3.0, 0.5)
    sp.tbox(-3.45, -2.45, 2.9, 2.45, 0.55, zf, BERM, top=SOIL)
    # 흙 두둑과 감자 잎 (유리 너머)
    rw = 3.0 / rows
    items = []
    for k in range(rows):
        y = -1.5 + rw * (k + 0.5)
        sp.box(vx0 + 0.2, y - rw * 0.32, zf, vx1 - vx0 - 0.4, rw * 0.64, 0.18, SOIL, top=Mat("#5a422e"))
        for i in range(9):
            x = vx0 + 0.55 + (vx1 - vx0 - 1.1) * i / 8
            items.append(((x, y, zf + 0.3), x, y))
    for _, x, y in sorted(items, key=lambda t: t[1] + t[2]):
        sp.ellipsoid((x, y, zf + 0.18), 0.26, 0.24, 0.3, leaf, clip_z=zf + 0.18)
        if v == 3:
            sp.sphere((x + 0.05, y + 0.08, zf + 0.5), 0.05, Mat("#E9E2F2"))
    sp.glow((-0.3, 0, zf + 1.2), 46, GROW, 0.6)
    # 유리 반원통 (퀀셋)
    _glass_vault_2d(sp, (vx0, 0, zf), (vx1, 0, zf), r, rz, ribs=6)
    # 출입 전실 (끝)
    sp.box(vx1, -0.8, 0, 0.85, 1.6, 2.1, WHITE, top=SILVER)
    fv = Sprite.box_faces(vx1, -0.8, 0, 0.85, 1.6, 2.1)
    door(sp, fv["right"], 0.25, 0.75, 0.75, STEEL)
    _panel(sp, fv["left"], 0.0, 0.82, 1.0, 0.9, (Mat("#C04FB3", 0.2), Mat("#C04FB3", 0.2), ORANGE, TEAL, ORANGE)[v])
    if v in (1, 4):
        sp.cyl((-2.4, -2.0, 0.4), (-2.4, -2.0, 2.0), 0.13, STEEL, cap_mat=CHAR)
    if v == 2:
        for x, y, s in ((-3.1, 2.0, 0.35), (2.6, 2.2, 0.3)):
            sp.rock((x, y, 0), s)
    if v == 4:
        p0, p1 = _vtank(sp, 3.18, 1.75, 0.0, 1.25, 0.28, WHITE)
        cyl_ring(sp, p0, p1, 0.28, 0.55, 0.66, Mat("#C04FB3", 0.2))
    sp.lamp((vx1 + 0.9, 0.95, 1.9), AMBER, 8)


@typed("wheat_bay", 11, 6, 3.8, "밀 재배실", heights=[3.8, 3.8, 3.8, 3.6, 3.8])
def wheat_bay(sp: Sprite, v: int):
    wheat = (WHEAT, WHEAT, Mat("#C9B04E", 0.1), Mat("#E2C060", 0.1), WHEAT)[v]
    vest_left = v in (1, 3)
    sp.contact_shadow(0, 0, 6.0, 3.4, 0.45)
    sp.box(-5.4, -2.9, 0, 10.8, 5.8, 0.3, SINTER)
    x0, x1 = (-5.2, 4.4) if not vest_left else (-4.4, 5.2)
    zf = 1.15
    r, rz = 2.6, (2.45, 2.45, 2.45, 2.25, 2.45)[v]
    sp.box(x0, -2.7, 0.3, x1 - x0, 5.4, zf - 0.3, WHITE, top=Mat("#8a8174"))
    f = Sprite.box_faces(x0, -2.7, 0.3, x1 - x0, 5.4, zf - 0.3)
    _panel(sp, f["left"], 0.0, 0.7, 1.0, 0.85, YELLOW)
    nwin = (6, 6, 8, 5, 6)[v]
    for i in range(nwin):
        u = 0.05 + i * 0.9 / nwin
        sp.window(sp.on_face(*f["left"], u + 0.02, 0.2, u + 0.9 / nwin - 0.03, 0.55), WHITE_LIGHT)
    # 밀 두둑 셋 (빽빽한 금빛 이삭)
    for y0b, y1b in ((-2.0, -0.85), (-0.6, 0.6), (0.85, 2.0)):
        bx0, bx1 = x0 + 0.3, x1 - 0.3
        sp.box(bx0, y0b, zf, bx1 - bx0, y1b - y0b, 0.55, Mat("#B8923A", 0.1), top=wheat)
        fb = Sprite.box_faces(bx0, y0b, zf, bx1 - bx0, y1b - y0b, 0.55)
        sp.panel_grid(*fb["top"], 40, 4, "#a8822e", 0.5, 0.75)
        sp.panel_grid(*fb["left"], 60, 1, "#9c7a2c", 0.45, 0.8)
    # 수확 레일 (길이 방향 노란 보 + 매달린 수확기)
    hz = zf + rz - 0.45
    sp.line((x0 + 0.2, 0, hz), (x1 - 0.2, 0, hz), 0.18, "#E9C24A")
    gx = (1.2, -1.6, 2.4, 0.4, -2.8)[v]
    sp.box(gx - 0.4, -0.35, hz - 0.75, 0.8, 0.7, 0.6, YELLOW)
    sp.line((gx, 0, hz - 0.15), (gx, 0, hz), 0.1, "#8a9099")
    sp.glow((-1.5, 0, zf + 1.4), 44, WHITE_LIGHT, 0.5)
    sp.glow((1.8, 0, zf + 1.4), 44, WHITE_LIGHT, 0.5)
    _glass_vault_2d(sp, (x0 + 0.05, 0, zf), (x1 - 0.05, 0, zf), r, rz, ribs=8)
    # 출입 전실
    vx = x1 if not vest_left else x0 - 0.85
    sp.box(vx, -0.9, 0.3, 0.85, 1.8, 2.0, WHITE, top=SILVER)
    fv = Sprite.box_faces(vx, -0.9, 0.3, 0.85, 1.8, 2.0)
    door(sp, fv["right"] if not vest_left else fv["left"], 0.25, 0.75, 0.75, STEEL)
    if v == 4:
        sp.cyl((x0 + 0.6, -2.3, 0.3), (x0 + 0.6, -2.3, 3.3), 0.15, STEEL, cap_mat=CHAR)
    sp.lamp((vx + 0.85 if not vest_left else vx + 0.45, 1.0 if not vest_left else 0.95, 2.3), WHITE_LIGHT, 9)


# ── 조류 반응기 계열 ─────────────────────────────────────────────────

def _paddle_wheel(sp: Sprite, x, y0, y1, z, r, n=8, col=Mat("#C9CED4", 0.3)):
    """축이 y 방향인 물레방아 (배양액을 휘젓는 날개)."""
    sp.cyl((x, y0, z), (x, y1, z), 0.08, STEEL, cap_mat=STEEL)
    blades = []
    for k in range(n):
        a = 2 * math.pi * k / n + 0.2
        rad = (math.cos(a), 0.0, math.sin(a))
        blades.append((dot(rad, VIEW), rad))
    for _, rad in sorted(blades, key=lambda b: b[0]):
        o = (x + rad[0] * 0.1, y0 + 0.05, z + rad[2] * 0.1)
        sp.quad(o, (0, y1 - y0 - 0.1, 0), mul(rad, r - 0.1), col, back=Mat("#9aa1aa", 0.3))
    sp.disc((x, y1 + 0.01, z), (0, 1, 0), r * 0.35, STEEL)


def _stadium(a, R, cx=0.0, cy=0.0, n=12):
    """두 반원 + 직선의 경주로 모양 (반시계)."""
    pts = [(cx + a + R * math.cos(t), cy + R * math.sin(t))
           for t in [-math.pi / 2 + math.pi * i / n for i in range(n + 1)]]
    pts += [(cx - a + R * math.cos(t), cy + R * math.sin(t))
            for t in [math.pi / 2 + math.pi * i / n for i in range(n + 1)]]
    return pts


@typed("spirulina_tank", 6, 4, 3.0, "스피룰리나 배양조", heights=[3.0, 2.4, 3.0, 3.0, 3.0])
def spirulina_tank(sp: Sprite, v: int):
    liquid = (SPIRULINA, SPIRULINA, SPIRULINA, SPIRULINA, Mat("#2A7A5E", 0.7))[v]
    tx0, tx1 = -2.65, (2.0, 2.0, 2.0, 1.6, 2.0)[v]
    wheel_x = ((-2.0, -2.0), (-2.0, -2.0), (-2.0, 1.4), (-2.0, -2.0), (1.4, -2.0))[v]
    sp.contact_shadow(0, 0, 3.6, 2.6)
    sp.box(-2.9, -1.9, 0, 5.8, 3.8, 0.2, CONCRETE)
    zl, zr = 0.8, 0.95
    tanks = ((-1.75, -0.15), (0.15, 1.75))
    for (y0, y1), wx in zip(tanks, wheel_x):
        sp.box(tx0, y0, 0.2, tx1 - tx0, y1 - y0, zl - 0.2, WHITE, top=liquid)
        # 가장자리 벽 (뒤 둘 → 앞 둘)
        sp.box(tx0, y0, zl, tx1 - tx0, 0.1, zr - zl, WHITE)
        sp.box(tx0, y0, zl, 0.1, y1 - y0, zr - zl, WHITE)
        for k in range(3):
            yy = y0 + 0.35 + k * (y1 - y0 - 0.7) / 2
            sp.line2((tx0 + 0.6, yy, zl + 0.01), (tx1 - 0.6, yy, zl + 0.01), "#2f8a83", 0.7)
        _paddle_wheel(sp, wx, y0 + 0.1, y1 - 0.1, zl + 0.45, 0.45)
        sp.box(tx1 - 0.1, y0, zl, 0.1, y1 - y0, zr - zl, WHITE)
        sp.box(tx0, y1 - 0.1, zl, tx1 - tx0, 0.1, zr - zl, WHITE)
        f = Sprite.box_faces(tx0, y0, 0.2, tx1 - tx0, y1 - y0, zl - 0.2)
        _panel(sp, f["left"], 0.0, 0.45, 1.0, 0.62, TEAL)
    sp.glow((-0.3, 0, 1.4), 34, "#5fe0c8", 0.35)
    # 투명 덮개
    if v == 1:
        for y0, y1 in tanks:
            _glass_vault_2d(sp, (tx0 + 0.05, (y0 + y1) / 2, zr), (tx1 - 0.05, (y0 + y1) / 2, zr), (y1 - y0) / 2, 1.2,
                            ribs=4)
    else:
        _glass_vault_2d(sp, (tx0 - 0.05, 0, zr), (tx1 + 0.05, 0, zr), 1.85, 1.95, ribs=5)
    # 수확·펌프 상자
    hx = tx1 + 0.3
    sp.box(hx, -1.3, 0.2, 2.75 - hx, 2.4, 1.1, WHITE, top=SILVER)
    fh = Sprite.box_faces(hx, -1.3, 0.2, 2.75 - hx, 2.4, 1.1)
    sp.window(sp.on_face(*fh["right"], 0.2, 0.45, 0.5, 0.75), "#5fe0c8")
    _slots(sp, fh["right"], 3, 0.6, 0.9, 0.2, 0.75)
    if v == 3:
        _vtank(sp, hx + 0.55, 1.45, 0.2, 1.0, 0.4, WHITE)
    sp.lamp((2.8, 1.15, 1.2), ALGAE_GLOW, 7)


@typed("chlorella_column", 5, 4, 4.6, "클로렐라 기둥", heights=[4.6, 4.6, 4.4, 4.6, 4.8])
def chlorella_column(sp: Sprite, v: int):
    tube = (CHLORELLA, CHLORELLA, Mat("#A6D84A", 0.75), CHLORELLA, Mat("#62B84A", 0.75))[v]
    acc = (TEAL, BLUE, TEAL, ORANGE, TEAL)[v]
    cx, cy = (-0.4, -0.1) if v != 3 else (0.0, -0.3)
    rings = ((1.25, 13), (0.65, 7), (0.0, 1)) if v != 2 else ((1.2, 11), (0.55, 5))
    th = (3.45, 3.45, 3.3, 3.45, 3.65)[v]
    sp.contact_shadow(0, 0, 2.9, 2.5)
    sp.box(-2.4, -1.9, 0, 4.8, 3.8, 0.15, CONCRETE)
    # 둥근 펌프 받침
    zb = 0.85
    sp.cyl((cx, cy, 0.15), (cx, cy, zb), 1.65, WHITE, cap_mat=STEEL, bands=[0.75], band_color="#a9a39a")
    cyl_ring(sp, (cx, cy, 0.15), (cx, cy, zb), 1.65, 0.45, 0.6, acc)
    # 뒤쪽 틀 기둥
    posts = [(cx + 1.5 * math.cos(a), cy + 1.5 * math.sin(a)) for a in (math.pi * 0.25, math.pi * 0.75,
                                                                     math.pi * 1.25, math.pi * 1.75)]
    zt = zb + th
    back = [p for p in posts if dot((p[0] - cx, p[1] - cy, 0), VIEW) < 0]
    front = [p for p in posts if p not in back]
    for x, y in back:
        sp.line((x, y, zb), (x, y, zt + 0.1), 0.09, "#8a9099")
    # 가늘고 긴 초록 유리관 다발
    tubes = []
    for R, n in rings:
        for k in range(n):
            a = 2 * math.pi * k / n + R
            tubes.append((cx + R * math.cos(a), cy + R * math.sin(a)))
    for x, y in sorted(tubes, key=lambda p: p[0] + p[1]):
        sp.cyl((x, y, zb), (x, y, zt), 0.11, tube, edge=False, cap_mat=Mat("#d6e9c8", 0.5))
        sp.mark_light(ALGAE_GLOW, 0.55)
    sp.ring3((cx, cy, zt + 0.05), 1.45, "#b9c0c8", 0.12, front_only=False)
    sp.ring3((cx, cy, zb + 1.6), 1.45, "#8a9099", 0.07)
    for x, y in front:
        sp.line((x, y, zb), (x, y, zt + 0.1), 0.09, "#8a9099")
    # 위 머리판과 이산화탄소 관
    sp.cyl((cx, cy, zt + 0.05), (cx, cy, zt + 0.25), 0.35, STEEL)
    pipe(sp, [(cx, cy, zt + 0.25), (cx, cy, zt + 0.45), (1.9, cy, zt + 0.45), (1.9, cy, 0.15)], 0.12)
    for k in range(3):
        sp.glow((cx, cy, zb + 0.8 + k * 1.1), 22, ALGAE_GLOW, 0.4)
    # 수확 탱크 (옆)
    hx, hy = (1.75, 1.3) if v != 1 else (1.75, -1.3)
    _vtank(sp, hx, hy, 0.15, 1.0, 0.45, WHITE)
    cyl_ring(sp, (hx, hy, 0.15), (hx, hy, 1.15), 0.45, 0.55, 0.68, Mat("#58A64A", 0.5))
    if v == 4:
        antenna(sp, (cx, cy, zt + 0.25), 0.9)
    sp.lamp((cx + 1.2, cy + 1.2, zb + 0.25), ALGAE_GLOW, 7)


@typed("algae_raceway", 10, 5, 2.2, "조류 수로", heights=[2.2, 2.2, 2.2, 2.2, 2.0])
def algae_raceway(sp: Sprite, v: int):
    water = (Mat("#4E9A3E", 0.6), Mat("#4E9A3E", 0.6), Mat("#5AA845", 0.6), Mat("#3F8A3A", 0.6), Mat("#4E9A3E", 0.6))[v]
    a, R = (2.6, 2.6, 2.6, 2.6, 2.2)[v], 2.05
    wheels = ((0.9, 1),), ((-1.2, 1),), ((1.4, 1), (-1.4, -1)), ((0.9, 1),), ((0.5, 1),)
    wheels = wheels[v]
    sp.contact_shadow(0, 0, 5.4, 2.9, 0.4)
    sp.box(-4.9, -2.4, 0, 9.8, 4.8, 0.12, SINTER)
    zw = 0.55
    outer = _stadium(a, R)
    sp.prism(outer, 0.12, zw - 0.12, CONCRETE, top=water)
    # 물결 줄 (흐름)
    for Rc, col in ((1.55, "#6fbf55"), (0.75, "#3d7f31")):
        pts = [(x, y, zw + 0.01) for x, y in _stadium(a, Rc, n=16)]
        sp.polyline3(pts, col, 0.06, 0.8, closed=True)
    sp.polyline3([(x, y, zw + 0.02) for x, y in outer], "#a39581", 0.16, closed=True)
    sp.prism(_stadium(a, 0.2), zw, 0.14, CONCRETE)
    # 물레방아 + 모터
    for wx, side in wheels:
        y0, y1 = (0.3, 1.95) if side > 0 else (-1.95, -0.3)
        _paddle_wheel(sp, wx, y0, y1, zw + 0.42, 0.42)
        my = 2.1 if side > 0 else -2.4
        sp.box(wx - 0.3, my, 0.12, 0.6, 0.3, 1.05, Mat("#5B6470", 0.2), top=SILVER)
    # 낮은 유리 지붕
    _glass_vault_2d(sp, (-a - R - 0.1, 0, zw), (a + R + 0.1, 0, zw), 2.2, 1.6, ribs=6)
    if v == 4:
        sp.box(a + R + 0.35, -1.0, 0.12, 4.85 - (a + R + 0.35), 2.0, 1.2, WHITE, top=SILVER)
        sp.lamp((4.85, 1.05, 1.0), ALGAE_GLOW, 7)
    if v == 3:
        _vtank(sp, -4.55, 2.05, 0.12, 0.9, 0.3, WHITE)
    sp.glow((0, 0, 1.0), 44, ALGAE_GLOW, 0.3)
    sp.lamp((a + R + 0.1, 0.0, 1.0), ALGAE_GLOW, 7)


@typed("cyanobacteria_reactor", 6, 5, 3.4, "남세균 반응기", heights=[3.4, 3.4, 3.4, 3.2, 3.6])
def cyanobacteria_reactor(sp: Sprite, v: int):
    pm = (CYANO, CYANO, Mat("#38A08F", 0.25), Mat("#2A8C9C", 0.25), CYANO)[v]
    back_m = Mat("#1f6f63", 0.2)
    n = (5, 6, 5, 4, 5)[v]
    zt = (3.05, 3.05, 3.05, 2.8, 3.3)[v]
    spines = (-1.15, 1.0) if v != 2 else (-0.9, 1.1)
    sp.contact_shadow(0, 0, 3.6, 3.0)
    sp.box(-2.9, -2.4, 0, 5.8, 4.8, 0.15, SINTER)
    x0, x1 = -2.65, 1.65
    pw = (x1 - x0) / n
    foot, head = 0.72, 0.1                  # 판 아래·위 끝의 받침대에서 떨어진 거리

    def panels(ys, side):
        for i in range(n):
            x = x0 + i * pw + 0.05
            o = (x, ys + side * foot, 0.2)
            e_up = (0, -side * (foot - head), zt - 0.3)
            e_w = (pw - 0.1, 0, 0)
            if side > 0:
                sp.quad(o, e_up, e_w, pm, back=back_m)
            else:
                sp.quad(o, e_w, e_up, pm, back=back_m)
            sp.panel_grid(o, e_w, e_up, 1, 7, "#5fc0ae", 0.5, 0.6)
            sp.polyline3([o, add(o, e_w), add(add(o, e_w), e_up), add(o, e_up), o], "#c3c9cf", 0.05)
            sp.line(add(o, (0.05, 0, 0.05)), add(o, (pw - 0.15, 0, 0.05)), 0.09, "#5d8fd0")

    for ys in spines:                       # 뒤 받침대부터
        panels(ys, -1)
        for x in (x0 - 0.05, (x0 + x1) / 2, x1 + 0.05):
            sp.line((x, ys, 0.15), (x, ys, zt + 0.05), 0.1, "#8a9099")
        sp.line((x0 - 0.1, ys, zt), (x1 + 0.1, ys, zt), 0.16, "#c9ccd1")
        panels(ys, 1)
        sp.glow(((x0 + x1) / 2, ys + 0.6, 1.5), 26, "#5fe0c8", 0.35)
    # 배양액 모음관 → 수확 탱크와 펌프 상자
    tx, ty = (2.4, -1.25) if v != 4 else (2.4, 1.55)
    for ys in spines:
        _cpipe(sp, [(x1 + 0.05, ys, 0.35), (tx - 0.4, ys, 0.35)], 0.14, "#5d8fd0")
    _vtank(sp, tx, ty, 0.15, 1.5, 0.45, WHITE)
    cyl_ring(sp, (tx, ty, 0.15), (tx, ty, 1.65), 0.45, 0.6, 0.72, Mat("#2E9C8A", 0.3))
    by = 0.45 if v != 4 else -1.6
    sp.box(2.0, by, 0.15, 0.8, 1.0, 0.9, Mat("#5B6470", 0.2), top=SILVER)
    sp.window(sp.on_face(*Sprite.box_faces(2.0, by, 0.15, 0.8, 1.0, 0.9)["left"], 0.25, 0.45, 0.75, 0.7), "#5fe0c8",
              frame=None)
    if v == 3:
        antenna(sp, (2.4, by + 0.5, 1.05), 1.2)
    sp.lamp((2.85, by + 1.0, 1.0), "#5fe0c8", 7)


# ── 식량 저장 계열 ───────────────────────────────────────────────────

def _frost_band(sp: Sprite, frame, v_top=0.16, n=14, seed=0.0, mat: Mat = FROST_BLUE):
    """벽 아래쪽을 타고 오르는 들쭉날쭉한 성에."""
    o, e1, e2 = frame
    nrm = norm(cross(e1, e2))
    pts = [add(o, mul(e1, 1.0)), o]
    for i in range(n + 1):
        u = i / n
        vv = v_top * (0.45 + 0.55 * abs(math.sin(i * 1.9 + seed)))
        pts.append(add(add(o, mul(e1, u)), mul(e2, vv)))
    sp.face(pts[1:] + pts[:1], mat, normal=nrm, edge=False, ao=0)


def _icicles(sp: Sprite, frame, n=10, length_v=0.1, seed=0.0):
    """윗모서리에 매달린 고드름."""
    o, e1, e2 = frame
    nrm = norm(cross(e1, e2))
    for i in range(n):
        u = (i + 0.5) / n
        L = length_v * (0.5 + 0.5 * abs(math.sin(i * 2.3 + seed)))
        a = add(add(o, mul(e1, u - 0.25 / n)), e2)
        b = add(add(o, mul(e1, u + 0.25 / n)), e2)
        c = add(add(o, mul(e1, u)), mul(e2, 1.0 - L))
        sp.face([a, c, b] if dot(cross(sub(c, a), sub(b, a)), nrm) > 0 else [a, b, c], SNOW, normal=nrm, edge=False,
                ao=0)


@typed("cold_store", 7, 5, 3.4, "냉동 저장고", heights=[3.4, 3.4, 3.4, 3.4, 3.8])
def cold_store(sp: Sprite, v: int):
    band = (BLUE, BLUE, TEAL, BLUE, Mat("#5d8fd0", 0.2))[v]
    nunit = (2, 3, 2, 2, 3)[v]
    door_left = v == 1
    sp.contact_shadow(0, 0, 4.1, 3.0)
    sp.box(-3.4, -2.4, 0, 6.8, 4.8, 0.2, CONCRETE)
    x0, y0, w, d, h = -3.1, -2.1, (5.6, 5.6, 5.8, 5.2, 5.6)[v], 4.0, 2.5
    if v == 3:
        sp.box(2.45, -1.9, 0.2, 0.8, 1.2, 1.0, STEEL, top=SILVER)
        _fan(sp, 2.85, -1.3, 1.2, 0.35)
    sp.box(x0, y0, 0.2, w, d, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.2, w, d, h)
    # 단열 판 이음매, 띠, 성에
    sp.panel_grid(*f["left"], int(w / 0.7), 1, "#c9c4b8", 0.5, 0.9)
    sp.panel_grid(*f["right"], int(d / 0.7), 1, "#c9c4b8", 0.5, 0.9)
    _panel(sp, f["left"], 0.0, 0.66, 1.0, 0.74, band)
    _panel(sp, f["right"], 0.0, 0.66, 1.0, 0.74, band)
    ft = (0.16, 0.24, 0.16, 0.2, 0.14)[v]
    _frost_band(sp, f["left"], ft, 18, v)
    _frost_band(sp, f["right"], ft, 12, v + 1.0)
    _icicles(sp, f["left"], 14, 0.1, v)
    _icicles(sp, f["right"], 10, 0.1, v + 0.5)
    corner = (x0 + w, y0 + d, 0.2)
    sp.line(add(corner, (0.03, 0.03, 0)), add(corner, (0.03, 0.03, h)), 0.16, "#E3EEF5")
    # 하역문 (두꺼운 단열문, 경고 줄, 띠 커튼)
    face = f["left"] if door_left else f["right"]
    du0, du1 = (0.08, 0.36) if door_left else (0.3, 0.72)
    _panel(sp, face, du0 - 0.02, 0.0, du1 + 0.02, 0.62, Mat("#3a3f47"), edge=True)
    _panel(sp, face, du0, 0.0, du1, 0.56, Mat("#C9D6E2", 0.3))
    for k in range(6):
        u = du0 + (du1 - du0) * (k + 0.5) / 6
        _panel(sp, face, u - 0.004, 0.02, u + 0.004, 0.54, Mat("#8fa3b5"))
    o, e1, e2 = face
    sp.stripes(add(add(o, mul(e1, du0 - 0.02)), add(mul(e2, 0.62), mul(norm(cross(e1, e2)), 0.01))),
               mul(e1, du1 - du0 + 0.04), mul(e2, 0.1), n=8, normal=norm(cross(e1, e2)))
    sp.window(sp.on_face(*(f["left"] if not door_left else f["right"]), 0.06, 0.3, 0.18, 0.5), CYAN_LIGHT)
    # 지붕 냉동기 (응축기 + 팬)
    zt = 0.2 + h
    for i in range(nunit):
        ux = x0 + 0.5 + i * (w - 1.0 - 1.3) / max(1, nunit - 1)
        sp.box(ux, y0 + 1.2, zt, 1.3, 1.5, 0.55, Mat("#C9CED4", 0.3), top=SILVER)
        fu = Sprite.box_faces(ux, y0 + 1.2, zt, 1.3, 1.5, 0.55)
        _slots(sp, fu["left"], 3, 0.1, 0.9, 0.15, 0.85, DARK)
        _fan(sp, ux + 0.65, y0 + 1.95, zt + 0.55, 0.42)
    pipe(sp, [(x0 + 0.6, y0 + 1.0, zt + 0.25), (x0 + w - 0.6, y0 + 1.0, zt + 0.25)], 0.12)
    if v == 4:
        antenna(sp, (x0 + 0.3, y0 + 0.3, zt), 1.2)
    lp = add(add(o, mul(e1, (du0 + du1) / 2)), add(mul(e2, 0.75), mul(norm(cross(e1, e2)), 0.15)))
    sp.lamp(lp, CYAN_LIGHT, 8)


@typed("seed_vault", 6, 6, 2.6, "종자 금고", heights=[2.6, 2.6, 2.8, 2.4, 2.6])
def seed_vault(sp: Sprite, v: int):
    glow = ("#9FF2FF", "#9FF2FF", "#CFE8FF", "#9FF2FF", "#B5FFE0")[v]
    gl_glass = Mat("#6FD3DC", 0.6) if v != 2 else Mat("#A9C8F0", 0.6)
    hz = (2.6, 2.6, 2.8, 2.4, 2.6)[v]
    hw = (0.6, 0.6, 0.55, 0.7, 0.6)[v]
    sp.contact_shadow(0, 0, 3.4, 3.4, 0.45)
    mx, my, mh = -0.6, -0.55, 2.0
    hill = Mat("#8A8378")
    if v != 3:
        sp.ellipsoid((-1.0, 1.3, 0), 1.75, 1.35, 1.05, hill, clip_z=0.0)
    sp.ellipsoid((mx, my, 0), 2.3, 2.15, mh, hill, clip_z=0.0)
    sp.ellipsoid((1.1, -1.7, 0), 1.3, 1.05, 0.9, hill, clip_z=0.0)
    for x, y, sz in ((-2.5, 2.4, 0.35), (2.3, -2.5, 0.3), (1.0, 2.5, 0.25), (2.5, 1.9, 0.22)):
        sp.rock((x, y, 0), sz)
    if v in (1, 4):
        pts = [(-1.6, -1.3, 1.6), (-1.6, -1.3, 2.6), (-1.4, -1.1, 2.8), (-1.25, -0.95, 2.65)]
        sp.polyline3(pts, "#5c626b", 0.24)
        sp.polyline3(pts, "#c9ccd1", 0.17)
    # 비스듬한 쐐기 입구 (앞이 높고 뒤로 둔덕에 묻힌다, 앞면은 앞으로 기운다)
    yc = -0.05
    ya, yb = yc - hw, yc + hw
    xb, xf0, xf1 = -0.3, 2.45, 2.8           # 묻힌 끝, 앞면 아래·위
    zb = 1.1
    C = Mat("#B5ADA0")
    A0, B0, C0, D0 = (xb, ya, 0.0), (xf0, ya, 0.0), (xf1, ya, hz), (xb, ya, zb)
    A1, B1, C1, D1 = (xb, yb, 0.0), (xf0, yb, 0.0), (xf1, yb, hz), (xb, yb, zb)
    center = _solid(sp, [([A0, B0, C0, D0], C), ([A1, B1, C1, D1], C), ([A0, A1, D1, D0], C),
                         ([D0, D1, C1, C0], Mat("#C4BCAF")), ([B0, B1, C1, C0], C), ([A0, A1, B1, B0], C)])

    def front(u, z, out=0.02):
        t = z / hz
        return (xf0 + (xf1 - xf0) * t + out, ya + (yb - ya) * u, z)
    # 빛나는 틈: 앞면 세로 (v3은 가로) + 지붕 끝을 따라 한 줄
    if v != 3:
        slit = [front(0.38, 0.95), front(0.62, 0.95), front(0.62, hz - 0.12), front(0.38, hz - 0.12)]
    else:
        slit = [front(0.1, 1.6), front(0.9, 1.6), front(0.9, 1.85), front(0.1, 1.85)]
    sp.window(_outward(slit, center), glow, frame=None, glass=gl_glass, light_alpha=1.0)
    sp.poly2([PV(q) for q in slit], glow, None, 0, 0.85)          # 낮에도 빛나 보이는 틈
    rt = [add(q, (0, 0, 0.02)) for q in (add(C0, mul(sub(D0, C0), 0.03)), add(C1, mul(sub(D1, C1), 0.03)),
                                         add(C1, mul(sub(D1, C1), 0.12)), add(C0, mul(sub(D0, C0), 0.12)))]
    rt = [(q[0], ya + 0.12 if q[1] < yc else yb - 0.12, q[2]) for q in rt]
    sp.window(_outward(rt, center), glow, frame=None, glass=gl_glass, light_alpha=0.9)
    sp.poly2([PV(q) for q in rt], glow, None, 0, 0.6)
    sp.glow(front(0.5, hz * 0.65), 24, glow, 0.6)
    # 문
    sp.face(_outward([front(0.28, 0.0), front(0.72, 0.0), front(0.72, 0.85), front(0.28, 0.85)], center),
            Mat("#4a5059", 0.3), ao=0)
    sp.lamp(add(front(0.85, 1.0), (0.15, 0, 0)), AMBER, 7)
    if v == 2:
        antenna(sp, (mx, my, mh), 1.2)


@typed("grain_silo", 5, 5, 7.0, "곡물 사일로", heights=[7.0, 7.0, 6.6, 7.0, 7.2])
def grain_silo(sp: Sprite, v: int):
    body = (Mat("#D5D8DC", 0.35), Mat("#E6E0D2", 0.2), Mat("#D5D8DC", 0.35), Mat("#C9CED4", 0.4),
            Mat("#D5D8DC", 0.35))[v]
    cone = (Mat("#C9CED4", 0.4), Mat("#B5533A", 0.2), Mat("#C9CED4", 0.4), Mat("#B5533A", 0.2), Mat("#C9CED4", 0.4))[v]
    sh = (5.5, 5.5, 5.2, 5.5, 5.7)[v]
    silos = ((-1.3, -1.3, 0.95), (0.85, -1.4, 0.95), (-1.4, 0.85, 0.95)) if v != 2 else \
        ((-1.2, -1.15, 1.15), (1.0, -1.2, 1.05))
    sp.contact_shadow(0, 0, 2.9, 2.9, 0.5)
    sp.box(-2.4, -2.4, 0, 4.8, 4.8, 0.2, CONCRETE)
    tops = []
    for x, y, r in sorted(silos, key=lambda s: s[0] + s[1]):
        p0, p1 = (x, y, 0.2), (x, y, 0.2 + sh)
        sp.cyl(p0, p1, r, body, bands=[k / 14 for k in range(1, 14)], band_color="#9aa0a8")
        cyl_ring(sp, p0, p1, r, 0.86, 0.9, WHEAT)
        sp.frustum(p1, (x, y, 0.2 + sh + r * 1.1), r, 0.16, cone)
        sp.cyl((x, y, 0.2 + sh + r * 1.1), (x, y, 0.2 + sh + r * 1.1 + 0.18), 0.2, STEEL)
        # 사다리
        a = Sprite.facing_angle(p0, p1, norm((1.0, 0.25, 0.0)))
        for s0 in (-6, 6):
            q = Sprite.cyl_patch(p0, p1, r, 0.02, 0.97, a + s0, a + s0)
            sp.line(q[0], q[3], 0.04, "#8a9099")
        tops.append((x, y, 0.2 + sh + r * 1.1 + 0.18))
    # 꼭대기를 잇는 덮인 컨베이어 (회랑)
    gz = max(t[2] for t in tops) + 0.05
    hub = tops[0] if v == 2 else min(tops, key=lambda t: t[0] + t[1])
    for t in tops:
        if t is hub:
            continue
        sp.polyline3([(hub[0], hub[1], gz), (t[0], t[1], gz)], "#7d848d", 0.42)
        sp.polyline3([(hub[0], hub[1], gz + 0.06), (t[0], t[1], gz + 0.06)], "#E6E0D2", 0.32)
    sp.box(hub[0] - 0.35, hub[1] - 0.35, gz - 0.25, 0.7, 0.7, 0.55, Mat("#E6E0D2"), top=SILVER)
    # 비스듬한 올림 컨베이어 (바닥 깔때기 → 꼭대기)
    right = v not in (1, 4)
    end = (tops[1][0], tops[1][1], gz) if right else (tops[-1][0], tops[-1][1], gz)
    if right:
        start = (2.05, 1.75, 0.6)
        mid = (2.05, end[1] + 0.2, gz)
    else:
        start = (1.75, 2.05, 0.6)
        mid = (end[0] + 0.2, 2.05, gz)
    for t in (0.35, 0.7):
        p = add(start, mul(sub(mid, start), t))
        sp.line((p[0], p[1], 0.2), p, 0.09, "#8a9099")
    sp.polyline3([start, mid, end], "#6f757d", 0.38)
    sp.polyline3([add(start, (0, 0, 0.06)), add(mid, (0, 0, 0.06)), add(end, (0, 0, 0.06))], "#D9B24A", 0.26)
    sp.frustum((start[0], start[1], 0.2), (start[0], start[1], 0.75), 0.18, 0.42, STEEL)
    sp.lamp((hub[0], hub[1], gz + 0.45), AMBER, 8)
    sp.lamp((start[0], start[1], 1.0), AMBER, 7)


@typed("galley", 8, 6, 3.4, "공동 주방", heights=[3.4, 3.4, 3.4, 3.6, 3.4])
def galley(sp: Sprite, v: int):
    stripe = ((ORANGE, CREAM), (Mat("#3FB8AF", 0.1), CREAM), (RED, CREAM), (ORANGE, CREAM), (YELLOW, Mat("#7A5A3A")))[v]
    nwin = (3, 3, 4, 2, 3)[v]
    sp.contact_shadow(0, 0, 4.6, 3.4)
    sp.box(-3.9, -2.9, 0, 7.8, 5.8, 0.2, SINTER)
    x0, y0, w, d, h = -3.6, -2.5, 4.7, 4.4, 2.5
    sp.box(x0, y0, 0.2, w, d, h, WHITE, top=SILVER)
    f = Sprite.box_faces(x0, y0, 0.2, w, d, h)
    _panel(sp, f["left"], 0.0, 0.86, 1.0, 0.94, stripe[0])
    _panel(sp, f["right"], 0.0, 0.86, 1.0, 0.94, stripe[0])
    # 큰 따뜻한 창
    for i in range(nwin):
        u0 = 0.06 + i * 0.88 / nwin
        sp.window(sp.on_face(*f["left"], u0 + 0.02, 0.22, u0 + 0.88 / nwin - 0.02, 0.8), WARM_WINDOW)
        sp.line(add(sp.on_face(*f["left"], u0 + 0.44 / nwin, 0.22, 0, 0)[0], (0, 0.02, 0)),
                add(sp.on_face(*f["left"], u0 + 0.44 / nwin, 0.8, 0, 0)[0], (0, 0.02, 0)), 0.05, "#d9d4ca")
    door(sp, f["right"], 0.55, 0.8, 0.78, Mat("#8C939C", 0.3), light=False)
    sp.window(sp.on_face(*f["right"], 0.12, 0.3, 0.45, 0.78), WARM_WINDOW)
    # 지붕: 환기 굴뚝과 배기 상자
    zt = 0.2 + h
    sx, sy = (x0 + 1.0, y0 + 1.2) if v != 2 else (x0 + 3.4, y0 + 1.0)
    sp.box(sx - 0.5, sy - 0.5, zt, 1.0, 1.0, 0.4, STEEL)
    sp.cyl((sx, sy, zt + 0.4), (sx, sy, zt + (1.15 if v != 3 else 1.4)), 0.2, SILVER)
    sp.frustum((sx, sy, zt + (1.15 if v != 3 else 1.4)), (sx, sy, zt + (1.3 if v != 3 else 1.55)), 0.34, 0.08, STEEL)
    zs = zt + (1.3 if v != 3 else 1.55)
    _puff(sp, (sx + 0.1, sy + 0.05, zs + 0.4), 0.28, 0.6)
    _puff(sp, (sx + 0.35, sy + 0.15, zs + 0.75), 0.22, 0.45)
    if v == 4:
        sp.quad((x0 + 2.2, y0 + 0.4, zt + 0.1), (2.2, 0, 0), (0, 1.6, 0.5), SOLAR, back=STEEL)
    # 바깥 식탁과 줄무늬 차양
    ax0, ax1, ay0, ay1 = x0 + w, 3.75, -1.7, 1.7
    sp.line((ax1 - 0.05, ay0, 0.2), (ax1 - 0.05, ay0, 2.15), 0.08, "#8a9099")
    for ty in ((-0.55,) if v != 2 else (-0.9, 0.65)):
        tx = (ax0 + ax1) / 2
        sp.box(tx - 0.5, ty - 0.95, 0.2, 1.0, 0.25, 0.45, Mat("#9a7b54"))
        sp.line((tx, ty, 0.2), (tx, ty, 0.8), 0.12, "#5c626b")
        sp.box(tx - 0.55, ty - 0.65, 0.8, 1.1, 1.3, 0.08, Mat("#B8865A", 0.2))
        sp.box(tx - 0.5, ty + 0.7, 0.2, 1.0, 0.25, 0.45, Mat("#9a7b54"))
    if v in (0, 3):
        for k in range(2):
            sp.box(x0 + 0.4 + k * 1.6, y0 + d + 0.05, 0.2, 1.0, 0.3, 0.4, Mat("#8a7d68"), top=LEAF)
    sp.line((ax1 - 0.05, ay1, 0.2), (ax1 - 0.05, ay1, 2.15), 0.08, "#8a9099")
    o, e_out, e_y = (ax0, ay0, 2.45), (ax1 - ax0, 0, -0.3), (0, ay1 - ay0, 0)
    ns = 8
    for k in range(ns):
        a = add(o, mul(e_y, k / ns))
        sp.quad(a, e_out, mul(e_y, 1 / ns), stripe[k % 2], back=stripe[k % 2])
    sp.polyline3([add(o, e_out), add(add(o, e_out), e_y)], "#8a9099", 0.06)
    for k in range(4):
        sp.lamp(add(add(o, e_out), add(mul(e_y, (k + 0.5) / 4), (0, 0, -0.15))), WARM_WINDOW, 6)
    sp.glow((x0 + w / 2, y0 + d, 1.2), 30, WARM_WINDOW, 0.35)
