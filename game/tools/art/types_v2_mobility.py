"""이동·첨단 묶음 — 환승 센터·로버 차고지·자기부상 터미널·첨단 제조동·데이터센터·로봇공학 연구소·대용량 축전소·태양광 밭 8종.

종류마다 fn(sp, v) 하나가 같은 기능의 다섯 모양(v0~v4)을 그린다. v0이 대표 모양이고, v1~v4는 색 띠·덧붙인 장치·창 수·
지붕 장비·크기를 조금씩 바꾼다. 모든 모양은 등록한 바닥 칸(w × d, 원점 = 바닥 가운데) 안에 들어간다.
좌표는 미터. x는 화면 오른쪽 아래, y는 왼쪽 아래, z는 위. 뒤(x + y가 작은 쪽)에서 앞으로 그린다.
달·화성 기지에 서는 건물이라 여압 통로·방열판·태양전지를 곁들인다.
"""
from __future__ import annotations

import math

import iso
from types_common import *  # noqa: F401,F403

# ── 재질·불빛 ───────────────────────────────────────────────────────────
TYRE = Mat("#3B3F46", 0.1)
HUBCAP = Mat("#A9B0B8", 0.4)
HUB_FACE = Mat("#C9CED4", 0.5)
ROAD = Mat("#5A5C61", 0.1)             # 소결한 차로·앞마당
PAVE = Mat("#BDB3A0")                  # 승강장 바닥
HALL = Mat("#E6E0D4", 0.05)
ROOF_WARM = Mat("#C9C2B4", 0.35)
ROOF_BLUE = Mat("#9FB3C8", 0.35)
SHED = Mat("#C9BFA9")                  # 차고 벽 (소결 레골리스 판)
SHED_TOP = Mat("#B3AA96")
DOOR = Mat("#B9BEC4", 0.25)            # 말아 올리는 문
CLEAN = Mat("#F3F3EF", 0.05)           # 청정실 흰 판
CLEAN_TOP = Mat("#DADBD6", 0.05)
SERVER = Mat("#444C57", 0.25)          # 데이터센터 벽 (짙은 청회색)
SERVER_TOP = Mat("#56606B", 0.2)
FAN_BOX = Mat("#8E959E", 0.3)
XFMR = Mat("#6F7F75", 0.25)            # 변압기 (회녹색)
XFMR_TOP = Mat("#7F8F85", 0.25)
PORCELAIN = Mat("#D9D4C9", 0.4)        # 애자
SAND = Mat("#CFC2A2")                  # 축전소 벽 (소결 레골리스)
SAND_TOP = Mat("#BBAE8F")
RIB = Mat("#BFB292")
TRAIN = Mat("#EEF1F4", 0.35, 1.0)      # 매끈한 차체 (면 이음이 보이지 않게 테두리 = 채움색)
TRAIN_DARK = Mat("#26303D", 0.7, 1.0)
GUIDE = Mat("#B8B2A6", 0.1)            # 안내 궤도 (콘크리트)
STATOR = Mat("#4A5058", 0.3)           # 궤도 옆 고정자 띠
BLUE_GLASS = Mat("#2f5f9a", 0.8)
ROBOT = Mat("#E8892F", 0.25)           # 산업 로봇 (주황)
GANTRY = Mat("#E9C24A", 0.15)
LAB = Mat("#ECEAE4", 0.06)
VIOLET = Mat("#8E6FD0", 0.1)
LIME = Mat("#9BC53D", 0.1)
FLOOR = Mat("#6B7078", 0.2)

GREEN_LIGHT = "#7CF29A"
RED_LIGHT = "#ff5a3c"
COOL_WINDOW = "#E8F6FF"
SIGN_BLUE = "#8FC4FF"
WHITE_SIGN = "#F4F7FA"


# ── 공용 부품 ───────────────────────────────────────────────────────────

def _orient(pts, outward):
    """다각형 꼭짓점이 outward 쪽에서 반시계가 되게 한다 (창·표시가 앞면으로 그려지도록)."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    return list(pts) if dot(n, outward) >= 0 else list(reversed(pts))


def _fp(frame, u, v):
    """상자 면(frame) 위의 점."""
    o, e1, e2 = frame
    return add(add(o, mul(e1, u)), mul(e2, v))


def _ground(sp: Sprite, x0, y0, x1, y1, mat: Mat, z=0.16):
    """바닥에 깐 판 (차로·마당)."""
    sp.face([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], mat, normal=(0, 0, 1), edge=False, ao=0)


def _decal(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, lift=0.012):
    """상자 면 위의 색 판."""
    o, e1, e2 = frame
    n = norm(cross(e1, e2))
    pts = [add(p, mul(n, lift)) for p in sp.on_face(o, e1, e2, u0, v0, u1, v1)]
    sp.face(pts, mat, normal=n, edge=False, ao=0)
    return pts


def _lit(sp: Sprite, pts, glow: str, alpha=0.85, light2d=True):
    """방금 그린 면이 밤에 glow로 빛난다. 2D 빛 면은 카메라 쪽 면에만 그린다 — 뒷면이나 light2d=False
    (앞의 물건에 가려지는 면: 2D 밤 불빛은 몸체 위에 한꺼번에 겹친다)는 3D에서만 빛난다."""
    sp.mark_light(glow, alpha)
    if light2d and dot(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])), VIEW) > 1e-6:
        sp.light_poly(pts, glow, alpha * 0.9)


def _faces4(x, y, z, w, d, h):
    """상자의 네 옆면 (원점, 가로, 세로 — 가로 × 세로 = 바깥 법선). left·right는 카메라 쪽, back·west는 뒤쪽이라
    2D에서는 가려지고 3D 모형(돌려 보는 게임 화면)에만 남는다."""
    f = Sprite.box_faces(x, y, z, w, d, h)
    f["back"] = ((x, y, z), (w, 0.0, 0.0), (0.0, 0.0, h))
    f["west"] = ((x, y + d, z), (0.0, -d, 0.0), (0.0, 0.0, h))
    return f


def _lit_decal(sp: Sprite, frame, u0, v0, u1, v1, mat: Mat, glow: str, alpha=0.85, light2d=True):
    """밤에 빛나는 색 판 (표지·상태등 띠)."""
    pts = _decal(sp, frame, u0, v0, u1, v1, mat)
    _lit(sp, pts, glow, alpha, light2d)
    return pts


def _glass(sp: Sprite, pts3, color="#cfe6ff", alpha=0.2, frame="#dfe9f2", op: float | None = None):
    """유리판 (2D는 반투명 — op가 있으면 그 불투명도, 3D는 유리 재질)."""
    sp._rec(("poly", list(pts3), iso._Glass(color, alpha), None))
    n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
    if dot(n, VIEW) <= 0:
        n = mul(n, -1)
    sp.poly2([PV(p) for p in pts3], hexc(lit(rgb(color), n, 0.6)), frame, 0.5, alpha + 0.12 if op is None else op)


def _vault(sp: Sprite, x0, x1, yc, hw, z0, rise, mat: Mat, n=16, cap: Mat | None = None):
    """x축을 따라 누운 타원 볼트 지붕 (반폭 hw, 높이 rise). (단면 점, 띠 면 목록) — 띠 0이 +y쪽 맨 아래."""
    prof = [(yc + hw * math.cos(math.pi * i / n), z0 + rise * math.sin(math.pi * i / n)) for i in range(n + 1)]
    strips = []
    for i in range(n):
        (ya, za), (yb, zb) = prof[i], prof[i + 1]
        pts = [(x0, ya, za), (x0, yb, zb), (x1, yb, zb), (x1, ya, za)]
        sp.face(pts, mat, ao=0)
        strips.append(pts)
    cm = cap or mat
    sp.face(_orient([(x1, y, z) for (y, z) in prof], (1, 0, 0)), cm, ao=0)
    sp.face(_orient([(x0, y, z) for (y, z) in prof], (-1, 0, 0)), cm, ao=0)
    return prof, strips


def _on_strip(strip, s0, s1, lift=0.02):
    """볼트 띠 면에서 x 비율 s0~s1 부분 (바깥으로 조금 띄운다)."""
    a, b, c, d = strip
    n = norm(cross(sub(b, a), sub(c, a)))

    def at(p, q, s):
        return add(add(p, mul(sub(q, p), s)), mul(n, lift))
    return [at(a, d, s0), at(b, c, s0), at(b, c, s1), at(a, d, s1)]


def _stadium(xa, xb, yc, r, k=8):
    """양 끝이 반원인 바닥 (반시계): 곧은 변 xa~xb, 반지름 r."""
    pts = [(xb + r * math.cos(-math.pi / 2 + math.pi * i / k), yc + r * math.sin(-math.pi / 2 + math.pi * i / k))
           for i in range(k + 1)]
    pts += [(xa + r * math.cos(math.pi / 2 + math.pi * i / k), yc + r * math.sin(math.pi / 2 + math.pi * i / k))
            for i in range(k + 1)]
    return pts


def _window3d(sp: Sprite, pts, glow=WARM_WINDOW, alpha=0.95, **kw):
    """창 — 3D 모형에서는 밤에 빛나지만 2D에는 빛 면을 그리지 않는다.
    2D의 밤 불빛은 몸체 위에 한꺼번에 겹치므로, 앞의 탈것에 가려지는 창의 빛이 탈것 위로 번지지 않게 한다."""
    sp.window(pts, glow, light_alpha=0.0, **kw)
    if sp.rec and sp._rd == 0 and sp.rec[-1][0] == "win":
        sp.rec[-1] = sp.rec[-1][:4] + (alpha,)


def _ribbon(sp: Sprite, base, z0, z1, glow=WARM_WINDOW, glass: Mat = GLASS, frame="#5c626b", lift=0.02,
            light2d=True):
    """볼록 바닥 둘레를 감아 도는 유리 띠 (변마다 창 하나 — 2D에서는 보이는 변만 그려진다).
    light2d=False면 2D 밤 불빛 없이 3D에서만 빛난다."""
    n = len(base)
    for i in range(n):
        (ax, ay), (bx, by) = base[i], base[(i + 1) % n]
        nrm = norm((by - ay, -(bx - ax), 0.0))
        o = mul(nrm, lift)
        pts = [add((ax, ay, z0), o), add((bx, by, z0), o), add((bx, by, z1), o), add((ax, ay, z1), o)]
        if light2d:
            sp.window(pts, glow, frame=frame, glass=glass)
        else:
            _window3d(sp, pts, glow, frame=frame, glass=glass)


def _hvac(sp: Sprite, x, y, z, w, d, h=0.8, nf=2, mat: Mat = Mat("#C9CED4", 0.25), top: Mat = Mat("#B9C0C8", 0.3)):
    """지붕 공조기: 옆에 루버 줄, 윗면에 팬 nf개."""
    sp.box(x, y, z, w, d, h, mat, top=top)
    f = Sprite.box_faces(x, y, z, w, d, h)
    sp.panel_grid(*f["left"], max(2, int(w / 0.22)), 1, "#8a9099", 0.45, 0.8)
    sp.panel_grid(*f["right"], max(2, int(d / 0.22)), 1, "#8a9099", 0.45, 0.8)
    r = min(w / nf, d) * 0.36
    for k in range(nf):
        c = (x + w * (k + 0.5) / nf, y + d / 2, z + h + 0.01)
        sp.disc(c, (0, 0, 1), r, CHAR)
        sp.ring3(add(c, (0, 0, 0.01)), r, "#9aa1aa", 0.05, seg=16)
        sp.disc(add(c, (0, 0, 0.02)), (0, 0, 1), r * 0.25, STEEL)


def _vtank(sp: Sprite, x, y, z0, h, r, mat: Mat = FROST, band: Mat | None = None, seams="#b5c6cf"):
    """선 탱크 (윗면 반구, 다리 치마)."""
    sp.cyl((x, y, z0), (x, y, z0 + 0.4), r * 0.82, STEEL)
    sp.cyl((x, y, z0 + 0.4), (x, y, z0 + h), r, mat, bands=[0.3, 0.65], band_color=seams)
    if band is not None:
        cyl_ring(sp, (x, y, z0 + 0.4), (x, y, z0 + h), r, 0.78, 0.86, band)
    sp.sphere((x, y, z0 + h), r, mat, clip_z=z0 + h)


def _stack(sp: Sprite, x, y, z0, z1, r=0.26, band="#D9532C"):
    """배기 굴뚝: 회색 관, 위쪽 붉은·흰 띠, 꼭대기 항공등."""
    sp.cyl((x, y, z0), (x, y, z1), r, Mat("#A7ADB5", 0.35), bands=[0.35, 0.7], cap_mat=CHAR)
    cyl_ring(sp, (x, y, z0), (x, y, z1), r, 0.84, 0.9, Mat(band, 0.1))
    cyl_ring(sp, (x, y, z0), (x, y, z1), r, 0.92, 0.97, WHITE)
    sp.lamp((x, y, z1 + 0.12), RED_LIGHT, 6)


def _fence(sp: Sprite, pts, h=1.5, color="#9aa1aa", post=True):
    """울타리 한 줄: 기둥과 위·가운데 줄."""
    if post:
        for p in pts:
            sp.line(p, add(p, (0, 0, h)), 0.06, color)
    sp.polyline3([add(p, (0, 0, h)) for p in pts], color, 0.05)
    sp.polyline3([add(p, (0, 0, h * 0.5)) for p in pts], color, 0.035, 0.8)


def _bushing(sp: Sprite, x, y, z, h=0.7, r=0.09):
    """애자 (갓 여러 겹의 흰 기둥)."""
    sp.cyl((x, y, z), (x, y, z + h), r, PORCELAIN, cap_mat=STEEL)
    for k in (1, 2):
        sp.disc((x, y, z + h * k / 3), (0, 0, 1), r * 2.0, PORCELAIN)


def _transformer(sp: Sprite, x, y, z0=0.15, w=1.6, d=1.2, h=1.5, mat: Mat = XFMR, top: Mat = XFMR_TOP):
    """변압기: 몸통, +y쪽 방열 지느러미, 위의 애자 셋과 보존 탱크."""
    sp.box(x, y, z0, w, d, h, mat, top=top)
    # 보존 탱크 (뒤 위)
    sp.line((x + 0.25, y + 0.2, z0 + h), (x + 0.25, y + 0.2, z0 + h + 0.35), 0.06, "#6a7079")
    sp.cyl((x + 0.05, y + 0.2, z0 + h + 0.48), (x + w - 0.05, y + 0.2, z0 + h + 0.48), 0.2, mat, cap_mat=top)
    for k in range(3):
        _bushing(sp, x + w * (k + 0.5) / 3, y + d * 0.62, z0 + h, 0.6)
    # 방열 지느러미 (+y 면에 세운 판)
    for k in range(5):
        xx = x + 0.2 + k * (w - 0.4) / 4
        sp.quad((xx, y + d, z0 + 0.2), (0, 0.32, 0), (0, 0, h - 0.4), mat, back=mat)
    o, e1, e2 = Sprite.box_faces(x, y, z0, w, d, h)["right"]
    sp.face(sp.on_face(o, e1, e2, 0.3, 0.45, 0.7, 0.7), Mat("#E9C24A", 0.1), normal=(1, 0, 0), edge=False, ao=0)


def _cone(sp: Sprite, x, y, z=0.15):
    """주황 고깔."""
    sp.box(x - 0.2, y - 0.2, z, 0.4, 0.4, 0.05, ORANGE)
    sp.frustum((x, y, z + 0.05), (x, y, z + 0.6), 0.16, 0.03, ORANGE, bands=[0.5], band_color="#F2F2EE")


def _lamp_post(sp: Sprite, x, y, z0=0.15, h=3.4, color=AMBER, r=12):
    sp.line((x, y, z0), (x, y, z0 + h), 0.09, "#8a9099")
    sp.lamp((x, y, z0 + h + 0.08), color, r)


DISH_N = norm((-0.45, 0.55, 0.7))       # 하늘(화면 왼쪽 위)을 보는 접시 — 비스듬히 보여 접시로 읽힌다


def _dish(sp: Sprite, base, h, r, n=DISH_N):
    """기둥 위 접시 안테나: 받침대, 흰 접시와 테두리, 급전부 받침 셋."""
    x, y, z = base
    sp.cyl((x, y, z), (x, y, z + h), 0.09, STEEL)
    sp.box(x - 0.16, y - 0.16, z + h - 0.1, 0.32, 0.32, 0.22, DARK)
    c = add((x, y, z + h + 0.25), mul(n, 0.1))
    sp.disc(c, n, r, WHITE, back=STEEL, seg=36)
    sp.ring3(c, r, "#9a958b", 0.06, normal=n, front_only=False, seg=24)
    sp.ring3(add(c, mul(n, 0.01)), r * 0.55, "#d8d2c6", 0.04, normal=n, front_only=False, seg=16)
    feed = add(c, mul(n, r * 0.75))
    u, w = basis(n)
    for a in (90, 210, 330):
        rim = add(c, add(mul(u, r * 0.92 * math.cos(math.radians(a))), mul(w, r * 0.92 * math.sin(math.radians(a)))))
        sp.line(rim, feed, 0.04, "#8a9099")
    sp.sphere(feed, max(0.07, r * 0.1), GOLD)


def _skylight(sp: Sprite, x, y, z, w, d, glow=WARM_WINDOW):
    """지붕 채광창: 낮은 턱 위의 유리 (밤에 빛난다)."""
    sp.box(x, y, z, w, d, 0.18, STEEL, top=STEEL)
    zg = z + 0.19
    sp.window([(x + 0.08, y + 0.08, zg), (x + w - 0.08, y + 0.08, zg), (x + w - 0.08, y + d - 0.08, zg),
               (x + 0.08, y + d - 0.08, zg)], glow, frame="#5c626b", light_alpha=0.75)


# ── 탈것 ────────────────────────────────────────────────────────────────

class _Veh:
    """탈것을 그릴 자리: 길이 u (앞 = +u), 너비 v (+v = 카메라 쪽 옆), 높이 z.
    along_x면 u = x, v = y, 아니면 u = y, v = x (좌우가 같은 탈것이라 거울상이어도 된다)."""

    def __init__(self, sp: Sprite, cx, cy, z0=0.0, along_x=True):
        self.sp, self.cx, self.cy, self.z0, self.ax = sp, cx, cy, z0, along_x

    def p(self, u, v, z):
        return (self.cx + u, self.cy + v, self.z0 + z) if self.ax else (self.cx + v, self.cy + u, self.z0 + z)

    def d(self, u, v, z):
        return (u, v, z) if self.ax else (v, u, z)

    def box(self, u0, v0, z0, du, dv, dz, mat: Mat, top: Mat | None = None):
        if self.ax:
            self.sp.box(self.cx + u0, self.cy + v0, self.z0 + z0, du, dv, dz, mat, top)
        else:
            self.sp.box(self.cx + v0, self.cy + u0, self.z0 + z0, dv, du, dz, mat, top)

    def face(self, pts, mat: Mat, out, **kw):
        pts3 = _orient([self.p(*q) for q in pts], self.d(*out))
        self.sp.face(pts3, mat, **kw)
        return pts3

    def win(self, pts, out, glow=WARM_WINDOW, **kw):
        self.sp.window(_orient([self.p(*q) for q in pts], self.d(*out)), glow, **kw)

    @staticmethod
    def side(u0, u1, z0, z1, v):
        """옆면(v 고정) 위의 사각형."""
        return [(u0, v, z0), (u1, v, z0), (u1, v, z1), (u0, v, z1)]

    def wheel(self, u, v, r, w):
        axis = self.d(0.0, 1.0, 0.0)
        c = self.p(u, v, r)
        a = mul(axis, w / 2)
        self.sp.cyl(sub(c, a), add(c, a), r, TYRE, cap_mat=HUBCAP, bands=[0.3, 0.7], band_color="#5b6069")
        self.sp.disc(add(c, mul(axis, w / 2 + 0.01)), axis, r * 0.45, HUB_FACE)

    def prism(self, prof, v0, v1, mat: Mat, top: Mat | None = None):
        """(u, z) 볼록 단면을 v0~v1로 민 덩어리. 단면 변마다 면(세계 좌표 점)을 돌려준다."""
        n = len(prof)
        cu = sum(q[0] for q in prof) / n
        cz = sum(q[1] for q in prof) / n
        faces = []
        for i in range(n):
            (ua, za), (ub, zb) = prof[i], prof[(i + 1) % n]
            pts = _orient([self.p(ua, v0, za), self.p(ub, v0, zb), self.p(ub, v1, zb), self.p(ua, v1, za)],
                          self.d((ua + ub) / 2 - cu, 0.0, (za + zb) / 2 - cz))
            m = top if (top is not None and abs(za - zb) < 1e-6 and za > cz) else mat
            self.sp.face(pts, m, ao=0)
            faces.append(pts)
        for vv, s in ((v0, -1.0), (v1, 1.0)):
            self.sp.face(_orient([self.p(u, vv, z) for (u, z) in prof], self.d(0.0, s, 0.0)), mat, ao=0)
        return faces

    def slope_win(self, a, b, v0, v1, s0=0.12, s1=0.88, glow=COOL_WINDOW, lift=0.015, light_alpha=0.4):
        """(u, z) 변 a→b 위의 창 (앞 유리). 바깥 = 변의 오른쪽 법선 (+u·+z 쪽). 밤에는 은은하게만 빛난다."""
        du, dz = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(du, dz)
        nu, nz = dz / ln, -du / ln
        if nu + nz < 0:
            nu, nz = -nu, -nz

        def at(s, v):
            return (a[0] + du * s + nu * lift, v, a[1] + dz * s + nz * lift)
        self.win([at(s0, v0), at(s0, v1), at(s1, v1), at(s1, v0)], (nu, 0.0, nz), glow, frame="#1a1d22",
                 light_alpha=light_alpha)


def _bus(sp: Sprite, cx, cy, livery: Mat, L=7.2, W=2.2, along_x=True, z0=0.15, nwin=5):
    """여섯 바퀴 가압 버스 (앞 = +u): 흰 몸통, 색 띠, 창 줄, 옆 도킹 문, 지붕의 태양전지·공조기."""
    V = _Veh(sp, cx, cy, z0, along_x)
    r, tw = 0.46, 0.34
    us = (-L * 0.34, -L * 0.15, L * 0.28)
    wv = W / 2 - tw / 2 + 0.03
    for u in us:
        V.wheel(u, -wv, r, tw)
    zb, H, nl = 0.6, 2.05, 1.05
    u0, u1 = -L / 2, L / 2 - nl
    V.box(u0, -W / 2, zb, u1 - u0, W, H, WHITE, top=SILVER)
    a, b = (L / 2, zb + 0.9), (u1 + 0.3, zb + H)
    V.prism([(u1, zb), (L / 2, zb), a, b, (u1, zb + H)], -W / 2, W / 2, WHITE, top=SILVER)
    sv = W / 2 + 0.012
    V.face(V.side(u0, L / 2, zb + 0.2, zb + 0.46, sv), livery, (0, 1, 0), edge=False, ao=0)
    V.face([(L / 2 + 0.012, v, z) for v, z in ((-W / 2 + 0.06, zb + 0.2), (W / 2 - 0.06, zb + 0.2),
                                                (W / 2 - 0.06, zb + 0.46), (-W / 2 + 0.06, zb + 0.46))],
           livery, (1, 0, 0), edge=False, ao=0)
    span = u1 - 1.45 - (u0 + 0.35)
    for k in range(nwin):
        ua = u0 + 0.35 + k * span / nwin
        V.win(V.side(ua, ua + span / nwin - 0.14, zb + 1.0, zb + 1.6, sv), (0, 1, 0))
    V.face(V.side(u1 - 1.15, u1 - 0.3, zb + 0.08, zb + 1.78, sv), Mat("#9aa1aa", 0.3), (0, 1, 0), ao=0)
    V.win(V.side(u1 - 1.0, u1 - 0.45, zb + 1.0, zb + 1.6, sv + 0.006), (0, 1, 0))
    V.slope_win(a, b, -W / 2 + 0.16, W / 2 - 0.16)
    # 지붕
    V.box(u0 + 0.35, -W / 2 + 0.22, zb + H, (u1 - u0) * 0.55, W - 0.44, 0.06, SOLAR)
    V.box(u1 - 1.5, -0.5, zb + H, 1.0, 1.0, 0.32, STEEL, top=SILVER)
    sp.lamp(V.p(u1 - 1.0, 0.0, zb + H + 0.45), AMBER, 6)
    for vv in (-0.65, 0.65):
        sp.lamp(V.p(L / 2 + 0.04, vv, zb + 0.62), WARM_WINDOW, 7)
    for u in us:
        V.wheel(u, wv, r, tw)


def _cargo_rover(sp: Sprite, cx, cy, accent: Mat, L=4.8, W=2.1, along_x=False, z0=0.12, load="box",
                 load_mat: Mat | None = None):
    """여섯 바퀴 화물 로버 (앞 = +u): 낮은 차대, 앞 운전칸, 뒤 짐칸 (상자·흙 호퍼·탱크·빈 칸)."""
    V = _Veh(sp, cx, cy, z0, along_x)
    r, tw = 0.48, 0.38
    us = (-L * 0.33, 0.0, L * 0.33)
    wv = W / 2 - tw / 2
    for u in us:
        V.wheel(u, -wv, r, tw)
    V.box(-L / 2, -W / 2 + 0.36, 0.5, L, W - 0.72, 0.32, DARK, top=STEEL)
    cu = L / 2 - 1.45
    b0, b1 = -L / 2 + 0.08, cu - 0.12
    if load == "box":
        lm = load_mat or ORANGE
        V.box(b0, -W / 2 + 0.12, 0.82, b1 - b0, W - 0.24, 1.25, lm, top=Mat(hexc(scale(lm.albedo, 1.08)), 0.1))
        V.face(V.side(b0, b1, 0.82 + 0.9, 0.82 + 1.05, W / 2 - 0.12 + 0.012), WHITE, (0, 1, 0), edge=False, ao=0)
        for k in range(1, 4):
            uu = b0 + (b1 - b0) * k / 4
            sp.line(V.p(uu, W / 2 - 0.1, 0.84), V.p(uu, W / 2 - 0.1, 2.05), 0.04, "#5c626b")
    elif load == "hopper":
        lm = load_mat or YELLOW
        V.prism([(b0 + 0.1, 0.82), (b1 - 0.05, 0.82), (b1, 1.75), (b0, 1.75)], -W / 2 + 0.16, W / 2 - 0.16, lm)
        sp.ellipsoid(V.p((b0 + b1) / 2, 0.0, 1.75), (b1 - b0) * 0.45 if along_x else W * 0.36,
                     W * 0.36 if along_x else (b1 - b0) * 0.45, 0.42, REGOLITH, clip_z=z0 + 1.75)
    elif load == "tank":
        lm = load_mat or WHITE
        for uu in (b0 + 0.35, b1 - 0.35):
            V.box(uu - 0.12, -0.55, 0.82, 0.24, 1.1, 0.35, STEEL)
        sp.cyl(V.p(b0, 0.0, 1.62), V.p(b1, 0.0, 1.62), 0.68, lm, bands=[0.5], band_color="#9fb4c0", cap_mat=lm)
        cyl_ring(sp, V.p(b0, 0.0, 1.62), V.p(b1, 0.0, 1.62), 0.68, 0.2, 0.3, accent)
    else:
        V.box(b0, -W / 2 + 0.15, 0.82, b1 - b0, W - 0.3, 0.12, STEEL, top=Mat("#9AA2AB", 0.3))
        V.box(b0 + 0.15, -0.75, 0.94, 1.1, 1.5, 0.9, ORANGE)
        V.box(b0 + 1.4, -0.6, 0.94, 0.85, 1.2, 0.7, Mat("#C9A23A"))
    # 운전칸
    a, b = (L / 2, 1.45), (L / 2 - 0.42, 2.18)
    V.prism([(cu, 0.82), (L / 2, 0.82), a, b, (cu, 2.18)], -W / 2 + 0.08, W / 2 - 0.08, WHITE, top=SILVER)
    sv = W / 2 - 0.08 + 0.012
    V.face(V.side(cu, L / 2, 0.92, 1.12, sv), accent, (0, 1, 0), edge=False, ao=0)
    V.win(V.side(cu + 0.18, L / 2 - 0.5, 1.32, 1.92, sv), (0, 1, 0), WARM_WINDOW, frame="#1a1d22", light_alpha=0.6)
    V.slope_win(a, b, -W / 2 + 0.22, W / 2 - 0.22)
    sp.lamp(V.p(cu + 0.4, 0.0, 2.28), AMBER, 6)
    for vv in (-0.6, 0.6):
        sp.lamp(V.p(L / 2 + 0.03, vv, 1.15), WARM_WINDOW, 6)
    for u in us:
        V.wheel(u, wv, r, tw)


def _train_sec(hw, h):
    """자기부상 차량 단면 (y, z): 바닥은 평평, 옆은 곧고, 어깨와 지붕은 둥글다 (반시계)."""
    return [(-hw * 0.78, 0.0), (hw * 0.78, 0.0), (hw, h * 0.18), (hw, h * 0.68), (hw * 0.88, h * 0.87),
            (hw * 0.45, h), (-hw * 0.45, h), (-hw * 0.88, h * 0.87), (-hw, h * 0.68), (-hw, h * 0.18)]


def _loft_x(sp: Sprite, secs, mat_of):
    """x를 따라 볼록 단면(같은 개수의 (y, z) 점)을 이은 몸통. secs = [(x, 점들)].
    mat_of(k, i) → Mat이면 면, (빛 색,)이면 창 (k: 단면 사이 번호, i: 단면 변 번호)."""
    for k in range(len(secs) - 1):
        xa, A = secs[k]
        xb, B = secs[k + 1]
        n = len(A)
        cy = sum(q[0] for q in A) / n
        cz = sum(q[1] for q in A) / n
        for i in range(n):
            j = (i + 1) % n
            pts = _orient([(xa, A[i][0], A[i][1]), (xa, A[j][0], A[j][1]), (xb, B[j][0], B[j][1]),
                           (xb, B[i][0], B[i][1])], (0.0, (A[i][0] + A[j][0]) / 2 - cy, (A[i][1] + A[j][1]) / 2 - cz))
            m = mat_of(k, i)
            if isinstance(m, tuple):
                sp.window(pts, m[0], frame=None, glass=TRAIN_DARK, light_alpha=0.5)
            else:
                sp.face(pts, m, ao=0)
    x0, A = secs[0]
    sp.face(_orient([(x0, y, z) for (y, z) in A], (-1, 0, 0)), mat_of(-1, 0), ao=0)
    x1, B = secs[-1]
    sp.face(_orient([(x1, y, z) for (y, z) in B], (1, 0, 0)), mat_of(len(secs), 0), ao=0)


NOSE_T = (0.0, 0.2, 0.42, 0.66, 0.86, 0.97)              # 코 단면 자리 (0 = 몸통, 1 = 끝)


def _maglev(sp: Sprite, xt, xn, yc, zb, livery: Mat, hw=1.3, h=2.1, nose=3.2, tail=0.9, nwin=8,
            stripe_glow=SIGN_BLUE, back="tail", front="nose"):
    """매끈한 자기부상 차량 한 량 (+x가 앞, 뒤 끝 xt → 앞 끝 xn). zb = 차량 바닥 높이.
    back·front: 'nose' (뾰족한 코와 앞 유리), 'tail' (짧게 줄어든 뒤 끝), 'flat' (다른 차량과 잇는 평평한 끝)."""
    base = _train_sec(hw, h)

    def sec(t, sharp):
        sy = (1 - t ** 2.4) ** 0.5 if sharp else (1 - (t * 0.75) ** 2.4) ** 0.5
        sz = 1 - (0.8 if sharp else 0.3) * t ** 1.3
        lift = (0.1 if sharp else 0.05) * h * t
        return [(yc + y * sy, zb + lift + z * sz) for (y, z) in base]

    secs = []
    if back == "nose":
        for t in reversed(NOSE_T):
            secs.append((xt + nose * (1 - t), sec(t, True)))
    elif back == "tail":
        for t in (0.8, 0.4, 0.0):
            secs.append((xt + tail * (0.8 - t) / 0.8, sec(t, False)))
    else:
        secs.append((xt, sec(0.0, False)))
    kb = len(secs) - 1                      # 곧은 몸통 구간 번호
    if front == "nose":
        for t in NOSE_T:
            secs.append((xn - nose * (1 - t), sec(t, True)))
    else:
        secs.append((xn, sec(0.0, False)))
    cab = set()
    if front == "nose":
        cab |= {kb + 2, kb + 3}
    if back == "nose":
        cab |= {kb - 3, kb - 2}

    def mat_of(k, i):
        if k in cab and i in (3, 4, 5, 6, 7):
            return (COOL_WINDOW,)
        return TRAIN
    _loft_x(sp, secs, mat_of)
    # 옆: 색 줄, 창 띠, 창, 문
    xs0, xs1 = secs[kb][0], secs[kb + 1][0]
    xa = xs0 + {"nose": -0.5, "tail": 0.25, "flat": 0.15}[back]
    xb = xs1 + (0.5 if front == "nose" else -0.15)
    sa = xa - 0.7 if back == "nose" else (xa - 0.2 if back == "tail" else xs0 + 0.02)
    sb = xb + 0.9 if front == "nose" else xs1 - 0.02
    sy = yc + hw + 0.012
    sp.face(_orient([(sa, sy, zb + h * 0.2), (sb, sy, zb + h * 0.2), (sb, sy, zb + h * 0.3), (sa, sy, zb + h * 0.3)],
                    (0, 1, 0)), livery, edge=False, ao=0)
    sp.mark_light(stripe_glow, 0.5)
    sp.face(_orient([(xa, sy, zb + h * 0.38), (xb, sy, zb + h * 0.38), (xb, sy, zb + h * 0.64),
                     (xa, sy, zb + h * 0.64)], (0, 1, 0)), TRAIN_DARK, edge=False, ao=0)
    step = (xb - xa - 0.3) / nwin
    for k in range(nwin):
        a = xa + 0.15 + k * step
        if k == nwin // 2:
            sp.face(_orient([(a + 0.05, sy + 0.004, zb + h * 0.08), (a + step - 0.05, sy + 0.004, zb + h * 0.08),
                             (a + step - 0.05, sy + 0.004, zb + h * 0.66), (a + 0.05, sy + 0.004, zb + h * 0.66)],
                            (0, 1, 0)), Mat("#C9CED4", 0.4), ao=0)
            continue
        sp.window(_orient([(a + 0.06, sy + 0.006, zb + h * 0.41), (a + step - 0.06, sy + 0.006, zb + h * 0.41),
                           (a + step - 0.06, sy + 0.006, zb + h * 0.61), (a + 0.06, sy + 0.006, zb + h * 0.61)],
                          (0, 1, 0)), WARM_WINDOW, frame=None, light_alpha=0.9)
    if front == "nose":
        sp.lamp((xn - 0.25, yc + hw * 0.35, zb + h * 0.22), WARM_WINDOW, 8)
    if back == "tail":
        sp.lamp((xt + 0.12, yc + hw * 0.4, zb + h * 0.3), RED_LIGHT, 5)


def _guideway(sp: Sprite, x0, x1, yc, ztop, cols, bw=1.2, bd=0.75):
    """T자 기둥 위의 높은 궤도 들보."""
    for x in cols:
        sp.box(x - 0.28, yc - 0.28, 0.15, 0.56, 0.56, ztop - bd - 0.45, GUIDE)
        sp.box(x - 0.32, yc - bw / 2 - 0.25, ztop - bd - 0.3, 0.64, bw + 0.5, 0.3, GUIDE, top=Mat("#C9C3B7", 0.1))
    sp.box(x0, yc - bw / 2 + 0.15, ztop - bd, x1 - x0, bw - 0.3, bd - 0.18, GUIDE)
    sp.box(x0, yc - bw / 2, ztop - 0.18, x1 - x0, bw, 0.18, STATOR, top=Mat("#8C939C", 0.3))
    sp.line((x0, yc + bw / 2 + 0.01, ztop - 0.09), (x1, yc + bw / 2 + 0.01, ztop - 0.09), 0.05, "#2a2f36")


# ── 로봇 ────────────────────────────────────────────────────────────────

def _robot_arm(sp: Sprite, base, yaw, a1, a2, s1=1.5, s2=1.3, mat: Mat = ROBOT, joint: Mat = DARK, k=1.0):
    """산업용 로봇 팔: 받침, 돌림판, 위팔(어깨 각 a1), 아래팔(팔꿈치 각 a2), 손목과 집게. 각은 도 (수평 0). k = 굵기 배율.
    집게 끝 점을 돌려준다."""
    x, y, z = base
    d = (math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0.0)
    sh = (x, y, z + 0.95 * k)
    el = add(sh, add(mul(d, s1 * math.cos(math.radians(a1))), (0, 0, s1 * math.sin(math.radians(a1)))))
    wr = add(el, add(mul(d, s2 * math.cos(math.radians(a2))), (0, 0, s2 * math.sin(math.radians(a2)))))
    tip = add(wr, (0, 0, -0.4 * k))
    sp.cyl((x, y, z), (x, y, z + 0.3 * k), 0.5 * k, DARK, cap_mat=STEEL)
    sp.cyl((x, y, z + 0.3 * k), (x, y, z + 0.75 * k), 0.38 * k, mat, cap_mat=mat)
    side = (-d[1], d[0], 0.0)

    def gripper():
        sp.cyl(wr, add(wr, (0, 0, -0.2 * k)), 0.13 * k, STEEL)
        for sg in (-1, 1):
            q = add(tip, mul(side, 0.11 * k * sg))
            sp.line(add(q, (0, 0, 0.24 * k)), q, 0.07 * k, "#5c626b")
    items = [(sh, lambda: (sp.cyl((x, y, z + 0.6 * k), sh, 0.27 * k, mat), sp.sphere(sh, 0.31 * k, joint))),
             (mul(add(sh, el), 0.5), lambda: sp.cyl(sh, el, 0.2 * k, mat, cap_mat=mat)),
             (el, lambda: sp.sphere(el, 0.23 * k, joint)),
             (mul(add(el, wr), 0.5), lambda: sp.cyl(el, wr, 0.15 * k, mat, cap_mat=mat)),
             (wr, lambda: (sp.sphere(wr, 0.16 * k, joint), gripper()))]
    sp.parts(items)
    return tip


def _robodog(sp: Sprite, x, y, mat: Mat = YELLOW, s=1.0, z=0.15):
    """네발 걷는 로봇 (앞 = +x): 몸통, 머리 감지기, 굽은 다리 넷."""
    def leg(lx, ly, ph):
        hip = (lx, ly, z + 0.62 * s)
        knee = (lx - 0.16 * s + ph, ly, z + 0.32 * s)
        foot = (lx + 0.04 * s + ph, ly, z)
        sp.polyline3([hip, knee, foot], "#3a3f47", 0.1 * s)
    for lx, ph in ((x - 0.36 * s, 0.0), (x + 0.36 * s, 0.12 * s)):
        leg(lx, y - 0.2 * s, ph)
    sp.box(x - 0.5 * s, y - 0.2 * s, z + 0.55 * s, 1.0 * s, 0.4 * s, 0.26 * s, mat)
    o, e1, e2 = Sprite.box_faces(x - 0.5 * s, y - 0.2 * s, z + 0.55 * s, 1.0 * s, 0.4 * s, 0.26 * s)["left"]
    sp.face(sp.on_face(o, e1, e2, 0.25, 0.35, 0.75, 0.6), CHAR, normal=(0, 1, 0), edge=False, ao=0)
    sp.box(x - 0.3 * s, y - 0.12 * s, z + 0.81 * s, 0.5 * s, 0.24 * s, 0.06 * s, Mat("#3a3f47", 0.3))
    sp.box(x + 0.42 * s, y - 0.13 * s, z + 0.66 * s, 0.24 * s, 0.26 * s, 0.2 * s, DARK)
    sp.lamp((x + 0.68 * s, y, z + 0.76 * s), CYAN_LIGHT, 5)
    for lx, ph in ((x - 0.36 * s, 0.12 * s), (x + 0.36 * s, 0.0)):
        leg(lx, y + 0.2 * s, ph)


def _wheelbot(sp: Sprite, x, y, mat: Mat = WHITE, accent: Mat = ORANGE, z=0.15, k=1.0):
    """네 바퀴 시험 로봇 + 팔 하나 (앞 = +x)."""
    for wx in (x - 0.42 * k, x + 0.42 * k):
        sp.cyl((wx, y - 0.48 * k, z + 0.24 * k), (wx, y - 0.32 * k, z + 0.24 * k), 0.24 * k, TYRE, cap_mat=HUBCAP)
    sp.box(x - 0.6 * k, y - 0.36 * k, z + 0.25 * k, 1.2 * k, 0.72 * k, 0.42 * k, mat, top=SILVER)
    o, e1, e2 = Sprite.box_faces(x - 0.6 * k, y - 0.36 * k, z + 0.25 * k, 1.2 * k, 0.72 * k, 0.42 * k)["left"]
    sp.face(sp.on_face(o, e1, e2, 0.0, 0.2, 1.0, 0.45), accent, normal=(0, 1, 0), edge=False, ao=0)
    sp.box(x - 0.45 * k, y - 0.25 * k, z + 0.67 * k, 0.5 * k, 0.5 * k, 0.08 * k, SOLAR)
    sp.line((x + 0.1 * k, y, z + 0.67 * k), (x + 0.35 * k, y, z + 1.2 * k), 0.09 * k, "#5c626b")
    sp.line((x + 0.35 * k, y, z + 1.2 * k), (x + 0.8 * k, y, z + 0.95 * k), 0.07 * k, "#5c626b")
    sp.box(x + 0.75 * k, y - 0.08 * k, z + 0.82 * k, 0.16 * k, 0.16 * k, 0.16 * k, DARK)
    sp.lamp((x + 0.62 * k, y, z + 0.72 * k), CYAN_LIGHT, 5)
    for wx in (x - 0.42 * k, x + 0.42 * k):
        sp.cyl((wx, y + 0.32 * k, z + 0.24 * k), (wx, y + 0.48 * k, z + 0.24 * k), 0.24 * k, TYRE, cap_mat=HUBCAP)


# ═════════════════════════════════════════════════════════════════════
# 1. 환승 센터
# ═════════════════════════════════════════════════════════════════════

@typed("transit_center", 16, 10, 8.0, "환승 센터", heights=[7.9, 7.9, 8.1, 7.5, 8.1])
def transit_center(sp: Sprite, v: int):
    """긴 타원 볼트 지붕의 역사, 앞 승강장의 차양과 두 정차 칸 (여섯 바퀴 가압 버스), 동쪽 끝의 표지 기둥과 여압 통로."""
    livery = (TEAL, ORANGE, TEAL, BLUE, RED)[v]
    glow = ("#7FE3DA", "#FFB37A", "#7FE3DA", SIGN_BLUE, "#FF8A6A")[v]
    roof = (SILVER, SILVER, ROOF_WARM, SILVER, ROOF_BLUE)[v]
    rise = (3.8, 3.8, 4.0, 3.4, 4.0)[v]
    sp.contact_shadow(-1.0, -0.6, 8.2, 5.2, 0.45)
    sp.box(-7.9, -4.9, 0, 15.8, 9.8, 0.15, CONCRETE)
    # 차로 + 정차 칸 표시
    ly0, ly1 = 2.8, 4.9
    _ground(sp, -7.9, ly0, 7.9, ly1, ROAD)
    for x in (-7.5, -0.1, 7.3):
        sp.line((x, ly0 + 0.12, 0.17), (x, ly1 - 0.12, 0.17), 0.1, "#E9C24A")
    for k in range(13):
        x = -7.3 + k * 1.15
        sp.line((x, ly1 - 0.16, 0.17), (x + 0.6, ly1 - 0.16, 0.17), 0.07, "#D8D2C2")
    # 역사 벽
    hx0, hx1, hy0, hy1, hz = -7.5, 3.3, -4.3, 0.3, 4.1
    sp.box(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hz - 0.15, HALL, top=HALL)
    f = _faces4(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hz - 0.15)
    windows_row(sp, f["left"], 7, 0.08, 0.5, 0.03, 0.025)
    windows_row(sp, f["left"], 9, 0.88, 0.97, 0.03, 0.02, COOL_WINDOW)          # 차양 위 고측창
    windows_row(sp, f["back"], 7, 0.3, 0.7, 0.04, 0.04)
    sp.window(sp.on_face(*f["west"], 0.2, 0.08, 0.8, 0.7), COOL_WINDOW, frame="#c9ccd1")
    sp.window(sp.on_face(*f["right"], 0.64, 0.08, 0.94, 0.6), COOL_WINDOW, frame="#c9ccd1")
    sp.line(add(_fp(f["right"], 0.79, 0.08), (0.03, 0, 0)), add(_fp(f["right"], 0.79, 0.6), (0.03, 0, 0)), 0.05,
            "#c9ccd1")
    _lit_decal(sp, f["right"], 0.64, 0.68, 0.94, 0.8, livery, glow)
    sp.lamp(add(_fp(f["right"], 0.79, 0.64), (0.12, 0, 0)), AMBER, 9)
    # 볼트 지붕: 아래 가장자리 노선 색 띠, 용마루 채광창, 갈비
    vx0, vx1, yc, hw = -7.7, 3.5, -2.0, 2.75
    prof, strips = _vault(sp, vx0, vx1, yc, hw, hz, rise, Mat(hexc(roof.albedo), roof.gloss, 1.0), 16, cap=roof)
    pts = _on_strip(strips[0], 0.0, 1.0, 0.015)
    sp.face(pts, livery, edge=False, ao=0)
    _lit(sp, pts, glow, 0.6)
    nb = 7
    for i in (7, 8):
        for k in range(nb):
            s0 = 0.03 + k * 0.94 / nb
            sp.window(_on_strip(strips[i], s0 + 0.012, s0 + 0.94 / nb - 0.012), WARM_WINDOW, frame="#5c626b",
                      light_alpha=0.7)
    for k in range(nb + 1):
        x = vx0 + (vx1 - vx0) * (0.03 + k * 0.94 / nb)
        rib, hidden = [], []
        for i in range(17):
            t = math.pi * i / 16
            q = (x, yc + (hw + 0.04) * math.cos(t), hz + (rise + 0.04) * math.sin(t))
            if dot(norm((0.0, math.cos(t) / hw, math.sin(t) / rise)), VIEW) > -0.03:
                rib.append(q)
            else:
                hidden.append(q)
        sp.polyline3(rib, "#7d848d", 0.08)
        if hidden:
            sp._rec(("line", [rib[-1]] + hidden, 0.08, "#7d848d", False))      # 뒤쪽 반은 3D에만
    pts = _on_strip(strips[-1], 0.0, 1.0, 0.015)                                # 뒤쪽 띠 (3D에만 보인다)
    sp.face(pts, livery, edge=False, ao=0)
    _lit(sp, pts, glow, 0.6)
    # 동쪽 박공의 부채꼴 유리
    kk = 12
    arc = [(yc + hw * 0.8 * math.cos(math.pi * i / kk), hz + 0.05 + rise * 0.8 * math.sin(math.pi * i / kk))
           for i in range(kk + 1)]
    sp.window(_orient([(vx1 + 0.02, y, z) for (y, z) in arc], (1, 0, 0)), COOL_WINDOW, frame="#2a2f36")
    sp.window(_orient([(vx0 - 0.02, y, z) for (y, z) in arc], (-1, 0, 0)), COOL_WINDOW, frame="#2a2f36")
    for j in range(1, 6):
        t = math.pi * j / 6
        sp.line((vx1 + 0.04, yc, hz + 0.05),
                (vx1 + 0.04, yc + hw * 0.8 * math.cos(t), hz + 0.05 + rise * 0.8 * math.sin(t)), 0.06, "#c9ccd1")
    sp.polyline3([(vx1 + 0.04, yc + hw * 0.45 * math.cos(math.pi * i / kk),
                   hz + 0.05 + rise * 0.45 * math.sin(math.pi * i / kk)) for i in range(kk + 1)], "#c9ccd1", 0.06)
    if v == 2:
        antenna(sp, (vx0 + 1.2, yc, hz + rise), 1.3)
    # 동쪽 여압 통로 (기지로 이어진다) 또는 관리동
    if v != 3:
        sp.half_cyl((hx1, -3.0, 0.15), (7.85, -3.0, 0.15), 1.15, FABRIC, bands=[0.2, 0.4, 0.6, 0.8],
                    band_color="#b9ab92", cap_mat=STEEL)
        sp.disc((7.87, -3.0, 0.6), (1, 0, 0), 0.42, DARK)
        sp.lamp((7.9, -3.0, 1.45), AMBER, 7)
    else:
        sp.box(4.3, -4.6, 0.15, 3.3, 2.9, 2.9, WHITE, top=SILVER)
        ef = Sprite.box_faces(4.3, -4.6, 0.15, 3.3, 2.9, 2.9)
        windows_row(sp, ef["left"], 3, 0.42, 0.78, 0.1, 0.06)
        windows_row(sp, ef["right"], 2, 0.42, 0.78, 0.15, 0.1)
        band_on(sp, ef["left"], 0.86, 0.94, livery)
        band_on(sp, ef["right"], 0.86, 0.94, livery)
        _dish(sp, (6.6, -3.8, 3.05), 0.7, 0.75)
    # 승강장
    sp.box(-7.6, hy1, 0.15, 15.2, ly0 - hy1, 0.3, PAVE)
    _ground(sp, -7.6, ly0 - 0.34, 7.6, ly0 - 0.14, YELLOW, z=0.455)
    # 차양
    cz = 3.25
    cxs = (-6.9, -3.5, -0.1, 3.3)
    for x in cxs:
        sp.line((x, ly0 - 0.32, 0.45), (x, ly0 - 0.32, cz), 0.16, "#a7adb5")
    if v in (2, 4):
        n = 28
        xs = [-7.4 + 11.8 * i / n for i in range(n + 1)]
        zs = [cz + 0.5 * abs(math.sin(math.pi * (x + 6.9) / 3.4)) for x in xs]
        for i in range(n):
            sp.face([(xs[i], hy1, zs[i]), (xs[i + 1], hy1, zs[i + 1]), (xs[i + 1], ly0 + 0.1, zs[i + 1]),
                     (xs[i], ly0 + 0.1, zs[i])], WHITE, ao=0, edge=False)
        sp.polyline3([(x, ly0 + 0.1, z) for x, z in zip(xs, zs)], "#8d949c", 0.12)
        for x in (-5.2, -1.8, 1.6):
            sp.box(x - 0.7, ly0 - 0.25, cz - 0.55, 1.4, 0.12, 0.34, CHAR)
            ff = Sprite.box_faces(x - 0.7, ly0 - 0.25, cz - 0.55, 1.4, 0.12, 0.34)
            _lit_decal(sp, ff["left"], 0.06, 0.2, 0.22, 0.8, livery, glow)
            _lit_decal(sp, ff["left"], 0.3, 0.38, 0.92, 0.62, Mat("#D8DCE0", 0.2), WHITE_SIGN, 0.7)
    else:
        sp.box(-7.4, hy1, cz, 11.8, ly0 + 0.1 - hy1, 0.14, WHITE, top=Mat("#DAD7D0"))
        fy = ly0 - 0.05
        sp.box(-7.4, fy, cz - 0.3, 11.8, 0.16, 0.44, CHAR)
        ff = Sprite.box_faces(-7.4, fy, cz - 0.3, 11.8, 0.16, 0.44)
        for u in (0.04, 0.33, 0.62):
            _lit_decal(sp, ff["left"], u, 0.18, u + 0.035, 0.82, livery, glow)
            _lit_decal(sp, ff["left"], u + 0.05, 0.38, u + 0.21, 0.62, Mat("#D8DCE0", 0.2), WHITE_SIGN, 0.7)
    for x in (-5.2, -1.8, 1.6):
        sp.glow((x, 1.6, cz - 0.25), 30, WARM_WINDOW, 0.35)
    # 동쪽 광장: 표지 기둥과 가로등
    px0, py0 = 6.3, 0.6
    sp.box(px0, py0, 0.45, 0.75, 0.9, 5.6, CHAR, top=DARK)
    pf = Sprite.box_faces(px0, py0, 0.45, 0.75, 0.9, 5.6)
    _lit_decal(sp, pf["right"], 0.1, 0.72, 0.9, 0.94, livery, glow)
    for k in range(3):
        _lit_decal(sp, pf["right"], 0.18, 0.62 - k * 0.07, 0.82, 0.66 - k * 0.07, Mat("#D8DCE0", 0.2), WHITE_SIGN,
                   0.6)
    _lit_decal(sp, pf["left"], 0.25, 0.1, 0.75, 0.94, livery, glow, 0.7)
    _lamp_post(sp, 5.0, 2.4, 0.45, 3.2)
    _lamp_post(sp, 7.6, 2.4, 0.45, 3.2)
    # 정차한 탈것
    _bus(sp, -3.85, 3.82, livery, L=7.2, W=2.2)
    if v in (1, 4):
        _bus(sp, 3.75, 3.82, (ORANGE, ORANGE, TEAL, BLUE, YELLOW)[v], L=6.4 if v == 4 else 7.2, W=2.2,
             nwin=4 if v == 4 else 5)
    elif v == 2:
        _cargo_rover(sp, 3.6, 3.85, YELLOW, L=4.6, W=2.0, along_x=True, z0=0.15, load="box", load_mat=WHITE)


# ═════════════════════════════════════════════════════════════════════
# 2. 로버 차고지
# ═════════════════════════════════════════════════════════════════════

@typed("rover_depot", 14, 10, 5.0, "로버 차고지", heights=[4.9, 4.9, 4.9, 4.6, 4.9])
def rover_depot(sp: Sprite, v: int):
    """낮은 차고 (칸마다 말아 올리는 문, 몇 칸은 열려 불빛), 앞마당의 여섯 바퀴 화물 로버와 충전 기둥, 동쪽의 높은 관제실."""
    band = (ORANGE, ORANGE, YELLOW, TEAL, ORANGE)[v]
    sp.contact_shadow(0.0, -0.6, 7.6, 5.2, 0.45)
    sp.box(-6.9, -4.9, 0, 13.8, 9.8, 0.12, SINTER)
    gx0, gx1, gy0, gy1, gh = -6.7, 2.9, -4.7, -0.8, 3.8
    _ground(sp, -6.9, gy1, 6.9, 4.9, ROAD, 0.125)
    # 차고
    sp.box(gx0, gy0, 0.12, gx1 - gx0, gy1 - gy0, gh, SHED, top=SHED_TOP)
    f = _faces4(gx0, gy0, 0.12, gx1 - gx0, gy1 - gy0, gh)
    for side in ("left", "right", "back", "west"):
        band_on(sp, f[side], 0.88, 0.95, band)
    windows_row(sp, f["back"], 6, 0.5, 0.72, 0.06, 0.05)
    o, e1, e2 = f["left"]
    nb = (4, 3, 4, 4, 3)[v]
    # 로버: 칸에서 막 나온 것 (앞 = +y) 과 앞마당을 가로지르는 것 (앞 = +x)
    lay = {0: (("bay", 0, "hopper", YELLOW), ("x", -4.5, "box", ORANGE)),
           1: (("bay", 0, "tank", WHITE), ("x", -4.3, "flat", None)),
           2: (("bay", 0, "tank", WHITE), ("bay", 2, "box", Mat("#C9CED4", 0.3))),
           3: (("bay", 0, "box", ORANGE), ("x", -4.5, "hopper", YELLOW)),
           4: (("bay", 1, "hopper", YELLOW), ("x", 3.4, "box", TEAL))}[v]
    taken = {k for kind, k, _, _ in lay if kind == "bay"}
    opened = ((1, 2), (2,), (3,), (1,), (2,))[v] + tuple(taken)
    m0, gap = 0.035, 0.04
    span = (1 - 2 * m0 - gap * (nb - 1)) / nb
    bays = []
    for k in range(nb):
        u0 = m0 + k * (span + gap)
        u1 = u0 + span
        vt = 0.74
        pts = sp.on_face(o, e1, e2, u0, 0.0, u1, vt)
        if k in opened:
            sp.face(pts, CHAR, normal=(0, 1, 0), ao=0)
            lp = [add(p, (0, 0.02, 0)) for p in pts]
            gp = add(_fp(f["left"], (u0 + u1) / 2, 0.2), (0, 0.6, 0))
            if k in taken:
                sp._rec(("lpoly", lp, "#ffcf8a", 0.5))                 # 로버에 가리는 칸: 3D에서만
                sp._rec(("glow", gp, 26 / S, "#ffcf8a", 0.4))
            else:
                sp.light_poly(lp, "#ffcf8a", 0.5)
                sp.glow(gp, 26, "#ffcf8a", 0.4)
            sp.face(sp.on_face(o, e1, e2, u0, vt - 0.1, u1, vt), DOOR, normal=(0, 1, 0), ao=0)
        else:
            sp.face(pts, DOOR, normal=(0, 1, 0), ao=0.12)
            sp.panel_grid(add(pts[0], (0, 0.01, 0)), mul(e1, u1 - u0), mul(e2, vt), 1, 10, "#8a9099", 0.45, 0.8)
        sp.stripes(add(_fp(f["left"], u0, vt), (0, 0.012, 0)), mul(e1, u1 - u0), mul(e2, 0.07), n=6,
                   normal=(0, 1, 0))
        sp.lamp(add(_fp(f["left"], (u0 + u1) / 2, vt + 0.12), (0, 0.1, 0)), GREEN_LIGHT if k in opened else AMBER, 7)
        bays.append(gx1 - (gx1 - gx0) * (u0 + u1) / 2)
    door(sp, f["right"], 0.35, 0.6, 0.62, Mat("#8C939C", 0.3))
    # 지붕: 난간 띠와 장비 (채광창·공조기·태양전지·접시)
    zt = 0.12 + gh
    sp.box(gx0, gy0, zt, gx1 - gx0, 0.18, 0.3, SHED_TOP)
    sp.box(gx0, gy0, zt, 0.18, gy1 - gy0, 0.3, SHED_TOP)
    if v == 2:
        for k in range(3):
            o2, a2, b2 = (gx0 + 0.5 + k * 3.0, gy0 + 0.5, zt + 0.25), (2.6, 0, 0), (0, 3.0, -0.2)
            sp.quad(o2, a2, b2, SOLAR, back=STEEL)
            sp.panel_grid(o2, a2, b2, 4, 4, "#6f86b0", 0.45, 0.6)
    else:
        nsk = (4, 3, 0, 4, 3)[v]
        for k in range(nsk):
            _skylight(sp, gx0 + 0.9 + k * (gx1 - gx0 - 3.6) / nsk, gy0 + 1.3, zt, 1.3, 1.3)
        _hvac(sp, gx1 - 1.9, gy0 + 0.5, zt, 1.4, 1.2, 0.55, 1)
        if v == 4:
            _dish(sp, (gx1 - 1.2, gy0 + 2.6, zt), 0.5, 0.7)
    # 관제실 (동쪽 뒤: 받침 위의 유리 방)
    cx0, cx1, cy0, cy1 = 3.5, 6.6, -4.6, -1.5
    if v == 3:
        sp.box(cx0, cy0, 0.12, cx1 - cx0, cy1 - cy0, 2.6, WHITE, top=SILVER)
        cf = Sprite.box_faces(cx0, cy0, 0.12, cx1 - cx0, cy1 - cy0, 2.6)
        windows_row(sp, cf["left"], 3, 0.38, 0.78, 0.08, 0.05, COOL_WINDOW)
        windows_row(sp, cf["right"], 3, 0.38, 0.78, 0.08, 0.05, COOL_WINDOW)
        band_on(sp, cf["left"], 0.86, 0.93, band)
        door(sp, cf["right"], 0.08, 0.26, 0.7, Mat("#8C939C", 0.3))
        _dish(sp, (5.5, -3.7, 2.72), 0.9, 0.85)
        sp.line((4.2, -2.4, 2.72), (4.2, -2.4, 3.6), 0.06, "#9aa1aa")
        sp.lamp((4.2, -2.4, 3.68), RED_LIGHT, 6)
    else:
        sp.box(3.9, -4.2, 0.12, 2.3, 2.3, 2.6, SHED, top=SHED_TOP)
        pf = Sprite.box_faces(3.9, -4.2, 0.12, 2.3, 2.3, 2.6)
        door(sp, pf["left"], 0.55, 0.85, 0.7, Mat("#8C939C", 0.3), light=False)
        zc = 2.72
        sp.box(cx0, cy0, zc, cx1 - cx0, cy1 - cy0, 0.22, STEEL)
        sp.box(cx0 + 0.1, cy0 + 0.1, zc + 0.22, cx1 - cx0 - 0.2, cy1 - cy0 - 0.2, 1.65, WHITE, top=SILVER)
        cf = _faces4(cx0 + 0.1, cy0 + 0.1, zc + 0.22, cx1 - cx0 - 0.2, cy1 - cy0 - 0.2, 1.65)
        for side in ("left", "right", "back", "west"):
            windows_row(sp, cf[side], 3, 0.3, 0.86, 0.05, 0.035, COOL_WINDOW)
        sp.box(cx0 - 0.1, cy0 - 0.1, zc + 1.87, cx1 - cx0 + 0.2, cy1 - cy0 + 0.2, 0.18, band, top=SILVER)
        sp.line((5.9, -2.2, zc + 2.05), (5.9, -2.2, zc + 2.7), 0.06, "#9aa1aa")
        sp.lamp((5.9, -2.2, zc + 2.78), RED_LIGHT, 7)
        sp.lamp((4.4, -3.6, zc + 2.15), AMBER, 8)
        # 계단 (동쪽)
        for k in range(7):
            sp.box(6.25, -3.2 + k * 0.3, 0.12 + k * 0.37, 0.55, 0.3, 0.1, STEEL)
        sp.line((6.8, -3.2, 0.45), (6.8, -1.1, 2.95), 0.05, "#9aa1aa")
    # 충전 기둥 (문 사이)
    posts = [(bays[k] + bays[k + 1]) / 2 for k in range(nb - 1)]
    for px in posts:
        sp.box(px - 0.2, gy1 + 0.15, 0.12, 0.4, 0.4, 1.3, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
        pf = Sprite.box_faces(px - 0.2, gy1 + 0.15, 0.12, 0.4, 0.4, 1.3)
        sp.window(sp.on_face(*pf["left"], 0.2, 0.6, 0.8, 0.85), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
    # 마당 줄
    for k in range(nb + 1):
        x = gx1 - (gx1 - gx0) * (m0 + k * (span + gap) - gap / 2) if k else gx1 - (gx1 - gx0) * m0 * 0.5
        sp.line((x, gy1 + 0.4, 0.135), (x, 4.6, 0.135), 0.08, "#E9C24A")
    # 동쪽 앞마당: 상자 더미와 뒤 가로등
    if v != 3:
        for k, (x, y) in enumerate(((4.0, 0.6), (5.1, 0.6), (4.5, 0.6))):
            crate(sp, x, y, 1.0, (ORANGE, STEEL, Mat("#C9A23A"))[(k + v) % 3], 0.12 + (0.8 if k == 2 else 0.0))
    _lamp_post(sp, 6.6, -0.6, 0.12, 3.6)
    # 로버 (먼 것부터) — 칸 앞 로버에는 충전선
    items = []
    for kind, k, load, lm in lay:
        if kind == "bay":
            bx = bays[k]
            px = posts[min(k, len(posts) - 1)]
            side = 1.0 if px > bx else -1.0
            pipe(sp, [(px, gy1 + 0.4, 1.15), ((px + bx) / 2, gy1 + 0.9, 0.25), (bx + side * 0.95, gy1 + 1.5, 0.9)],
                 0.06, "#2a2d33")
            items.append(((bx, 1.75, 1.0), lambda bx=bx, load=load, lm=lm: _cargo_rover(
                sp, bx, 1.75, band, L=4.6, W=2.0, along_x=False, load=load, load_mat=lm)))
        else:
            items.append(((k, 3.85, 1.0), lambda cx=k, load=load, lm=lm: _cargo_rover(
                sp, cx, 3.85, band, L=4.4, W=2.0, along_x=True, load=load, load_mat=lm)))
    sp.parts(items)
    _lamp_post(sp, 6.6, 4.4, 0.12, 3.6)


# ═════════════════════════════════════════════════════════════════════
# 3. 자기부상 터미널
# ═════════════════════════════════════════════════════════════════════

@typed("maglev_terminal", 18, 8, 9.0, "자기부상 터미널", heights=[9.0, 9.0, 9.0, 9.4, 9.0])
def maglev_terminal(sp: Sprite, v: int):
    """둥근 끝의 유선형 터미널 (유리 띠가 감아 돈다), 그 앞에서 긴 축을 따라 T자 기둥 위 궤도와 매끈한 자기부상 차량."""
    livery = (BLUE, RED, TEAL, BLUE, LIME)[v]
    sglow = (SIGN_BLUE, "#FF8A6A", "#7FE3DA", SIGN_BLUE, "#C8F07A")[v]
    sp.contact_shadow(0.0, -0.4, 9.6, 4.4, 0.45)
    sp.box(-8.9, -3.9, 0, 17.8, 7.8, 0.15, CONCRETE)
    _ground(sp, -8.9, 0.9, 8.9, 3.9, PAVE)
    # 터미널: 1층 유리 대합실, 위층 흰 몸통과 유리 띠, 지붕
    xa, xb, yc, R = -4.6, 3.6, -1.75, 1.95
    zf, zt = 3.0, 7.4
    lobby = _stadium(xa, xb, yc, R - 0.35, 6)
    sp.prism(lobby, 0.15, zf - 0.15, Mat("#3a4656", 0.6), top=SILVER)
    _ribbon(sp, lobby, 0.3, zf - 0.3, COOL_WINDOW, Mat("#1f2a36", 0.8), frame="#9aa1aa", light2d=False)
    body = _stadium(xa, xb, yc, R, 8)
    sp.prism(body, zf, zt - zf, WHITE, top=SILVER)
    _ribbon(sp, body, zf + 1.95, zf + 3.6, (WARM_WINDOW, WARM_WINDOW, WARM_WINDOW, COOL_WINDOW, "#FFE2A0")[v])
    for i in range(len(body)):                  # 지붕 밑 색 띠 (밤에 빛난다)
        (ax, ay), (bx, by) = body[i], body[(i + 1) % len(body)]
        nn = norm((by - ay, -(bx - ax), 0.0))
        o = mul(nn, 0.02)
        pts = [add((ax, ay, zt - 0.5), o), add((bx, by, zt - 0.5), o), add((bx, by, zt - 0.3), o),
               add((ax, ay, zt - 0.3), o)]
        sp.face(pts, livery, edge=False, ao=0)
        _lit(sp, pts, sglow, 0.55)
    roof = _stadium(xa, xb, yc, R + 0.25, 8)
    sp.prism(roof, zt, 0.25, SILVER, top=Mat("#C5CBD2", 0.4))
    if v == 1:
        for k in range(4):
            o2, a2, b2 = (xa - 1.0 + k * 2.2, yc - 1.3, zt + 0.35), (1.9, 0, 0), (0, 2.6, 0.25)
            sp.quad(o2, a2, b2, SOLAR, back=STEEL)
            sp.panel_grid(o2, a2, b2, 3, 4, "#6f86b0", 0.45, 0.6)
    elif v == 3:
        # 서쪽 끝 지붕 위 관제탑 + 공조기
        tx, ty, zr = xa - 0.7, yc, zt + 0.25
        _hvac(sp, xa + 1.0, yc - 1.1, zr, 2.0, 1.4, 0.6, 2)
        _hvac(sp, xa + 3.6, yc - 1.1, zr, 2.0, 1.4, 0.6, 2)
        sp.cyl((tx, ty, zr), (tx, ty, 8.1), 0.5, WHITE, cap_mat=SILVER)
        sp.cyl((tx, ty, 8.1), (tx, ty, 8.9), 1.05, WHITE, cap_mat=SILVER)
        cyl_windows(sp, (tx, ty, 8.1), (tx, ty, 8.9), 1.05, 0.2, 0.82, toward=(0.6, 1.0, 0.0), n=5, spread=26.0,
                    width=20.0, glow=COOL_WINDOW)
        cyl_ring(sp, (tx, ty, 8.1), (tx, ty, 8.9), 1.05, 0.88, 1.0, livery, sglow, 0.5)
        sp.line((tx, ty, 8.9), (tx, ty, 9.4), 0.06, "#9aa1aa")
        sp.lamp((tx, ty, 9.47), RED_LIGHT, 7)
    else:
        sp.ellipsoid(((xa + xb) / 2, yc, zt + 0.25), (xb - xa) / 2 + 1.1, 1.0, 0.75, BLUE_GLASS, clip_z=zt + 0.25)
        for k in range(1, 8):
            x = xa - 1.1 + k * ((xb - xa) + 2.2) / 8
            t = (x - (xa + xb) / 2) / ((xb - xa) / 2 + 1.1)
            k2 = math.sqrt(max(0.0, 1 - t * t))
            sp.polyline3([(x, yc + k2 * math.cos(math.pi * j / 10), zt + 0.25 + 0.75 * k2 * math.sin(math.pi * j / 10))
                          for j in range(11)], "#c9d4de", 0.05, 0.8)
        sp.glow(((xa + xb) / 2, yc, zt + 0.6), 40, WARM_WINDOW, 0.3)
    if v in (2, 4):
        antenna(sp, (xb + 0.8, yc - 0.6, zt + 0.25), 1.3)
    # 동쪽 끝 출입 차양
    sp.box(xb + R - 0.1, yc - 1.2, 2.5, 1.2, 2.4, 0.16, SILVER, top=Mat("#C5CBD2", 0.4))
    for y in (yc - 1.0, yc + 1.0):
        sp.line((xb + R + 0.95, y, 0.15), (xb + R + 0.95, y, 2.5), 0.08, "#9aa1aa")
    sp.lamp((xb + R + 0.95, yc, 2.4), AMBER, 10)
    # 표지 기둥 (동쪽)
    sp.box(7.4, -3.3, 0.15, 0.6, 1.0, 8.85, CHAR, top=DARK)
    pf = Sprite.box_faces(7.4, -3.3, 0.15, 0.6, 1.0, 8.85)
    _lit_decal(sp, pf["right"], 0.12, 0.66, 0.88, 0.95, livery, sglow)
    _lit_decal(sp, pf["left"], 0.2, 0.08, 0.8, 0.95, Mat("#D8DCE0", 0.2), WHITE_SIGN, 0.55)
    # 승강장 판 (터미널 → 궤도)
    zg = 3.25
    sp.box(xa - 1.5, yc + R - 0.1, zg - 0.3, (xb - xa) + 3.0, 1.75 - (yc + R - 0.1), 0.3, PAVE, top=PAVE)
    # 궤도와 차량
    gy = 2.35
    _guideway(sp, -8.9, 8.9, gy, zg, (-6.6, -2.2, 2.2, 6.6))
    for x in (-7.8, -3.6, 0.6, 4.8, 8.4):
        sp.glow((x, gy, zg + 0.05), 16, SIGN_BLUE, 0.4)
    zb = zg + 0.15
    if v == 2:
        _maglev(sp, -8.8, -0.6, gy, zb, livery, nose=2.8, nwin=6, stripe_glow=sglow, back="nose", front="flat")
        sp.box(-0.62, gy - 0.95, zb + 0.15, 0.44, 1.9, 1.75, Mat("#3a3f47", 0.2))
        _maglev(sp, -0.2, 7.6, gy, zb, livery, nose=3.0, nwin=6, stripe_glow=sglow, back="flat")
    elif v == 1:
        _maglev(sp, -7.4, 5.4, gy, zb, livery, stripe_glow=sglow)
    elif v == 3:
        _maglev(sp, -8.8, 2.4, gy, zb, livery, nwin=7, stripe_glow=sglow)
    elif v == 4:
        _maglev(sp, -8.6, 4.4, gy, zb, livery, nose=3.0, nwin=7, stripe_glow=sglow, back="nose")
    else:
        _maglev(sp, -8.6, 4.2, gy, zb, livery, stripe_glow=sglow)
    _lamp_post(sp, 8.4, 3.6, 0.15, 3.0)


# ═════════════════════════════════════════════════════════════════════
# 4. 첨단 제조동
# ═════════════════════════════════════════════════════════════════════

@typed("tech_fab", 16, 12, 8.0, "첨단 제조동", heights=[8.0, 8.0, 8.4, 8.0, 7.6])
def tech_fab(sp: Sprite, v: int):
    """흰 청정실 공장: 지붕의 공조기 줄과 배기 굴뚝, 뒤의 기체 탱크 무리, 앞 모서리의 유리 사무동과 현관."""
    accent = (BLUE, TEAL, BLUE, Mat("#2F5E9E", 0.3), VIOLET)[v]
    sp.contact_shadow(0.0, 0.0, 8.6, 6.6, 0.45)
    sp.box(-7.9, -5.9, 0, 15.8, 11.8, 0.15, CONCRETE)
    # 기체 탱크 무리 (뒤 동쪽)
    _ground(sp, 4.0, -5.7, 7.7, -1.2, Mat("#8f8576"), 0.16)
    tanks = ((4.9, -4.7, 0.72, 4.6, BLUE), (6.7, -4.6, 0.66, 4.0, GREEN), (6.0, -2.7, 0.6, 3.4, ORANGE))
    if v == 2:
        tanks = ((5.0, -4.6, 0.72, 5.2, BLUE), (6.8, -4.6, 0.66, 4.8, GREEN))
    for (x, y, r, h, b) in tanks:
        _vtank(sp, x, y, 0.16, h, r, FROST, band=b)
    if v == 2:
        for k in range(3):
            sp.cyl((4.4, -2.6 + k * 0.55, 0.55), (7.4, -2.6 + k * 0.55, 0.55), 0.26, Mat("#7A8F7E", 0.35),
                   cap_mat=STEEL)
        sp.box(4.3, -2.95, 0.16, 0.2, 1.7, 0.6, STEEL)
        sp.box(7.2, -2.95, 0.16, 0.2, 1.7, 0.6, STEEL)
    _fence(sp, [(4.0, -1.2, 0.16), (7.7, -1.2, 0.16)], 1.2)
    # 공장동
    fx0, fx1, fy0, fy1, fh = -7.5, 3.2, -5.5, 2.0, 5.2
    sp.box(fx0, fy0, 0.15, fx1 - fx0, fy1 - fy0, fh, CLEAN, top=CLEAN_TOP)
    f = _faces4(fx0, fy0, 0.15, fx1 - fx0, fy1 - fy0, fh)
    sp.panel_grid(*f["left"], 16, 3, "#d5d7d9", 0.45, 0.8)
    sp.panel_grid(*f["right"], 11, 3, "#d5d7d9", 0.45, 0.8)
    for side in ("left", "right", "back", "west"):
        band_on(sp, f[side], 0.84, 0.91, accent)
    windows_row(sp, f["back"], 6, 0.62, 0.74, 0.08, 0.03, "#a8d4ff")
    o, e1, e2 = f["left"]
    nwin = (5, 5, 4, 6, 5)[v]
    for i in range(nwin):
        u = 0.36 + i * 0.6 / nwin
        sp.window(sp.on_face(o, e1, e2, u, 0.62, u + 0.6 / nwin - 0.03, 0.74), "#a8d4ff", glass=BLUE_GLASS)
    # 짐 부리는 문
    dpts = sp.on_face(o, e1, e2, 0.78, 0.0, 0.92, 0.5)
    sp.face(dpts, DOOR, normal=(0, 1, 0), ao=0.1)
    sp.panel_grid(add(dpts[0], (0, 0.01, 0)), mul(e1, 0.14), mul(e2, 0.5), 1, 8, "#8a9099", 0.45, 0.8)
    sp.stripes(add(_fp(f["left"], 0.78, 0.5), (0, 0.012, 0)), mul(e1, 0.14), mul(e2, 0.05), n=8, normal=(0, 1, 0))
    sp.lamp(add(_fp(f["left"], 0.85, 0.6), (0, 0.12, 0)), AMBER, 9)
    sp.box(fx0 + 0.9, fy1, 0.15, 1.9, 0.9, 0.9, CONCRETE, top=Mat("#8f8270"))
    pipe(sp, [(fx1 + 0.05, -3.8, 3.6), (4.4, -3.8, 3.6), (4.9, -4.2, 3.6)], 0.2, "#d9dde2")
    # 지붕 공조기 줄
    zt = 0.15 + fh
    ry = (-4.9, -2.7, -0.5) if v == 1 else (-4.9, -2.7)
    ncol = (4, 4, 3, 4, 4)[v]
    for y in ry:
        for k in range(ncol):
            x = -6.9 + k * 2.3
            _hvac(sp, x, y, zt, 1.9, 1.4, 0.8, 2)
    pipe(sp, [(-7.0, -0.9 if v != 1 else 1.3, zt + 0.45), (1.4, -0.9 if v != 1 else 1.3, zt + 0.45)], 0.34,
         "#d9dde2")
    if v == 4:
        for k in range(4):
            o2 = (-6.6 + k * 1.2, 0.2, zt + 0.1)
            sp.quad(o2, (0.9, 0, 0), (0, 0, 1.6), RADIATOR, back=RADIATOR)
            sp.panel_grid(o2, (0.9, 0, 0), (0, 0, 1.6), 3, 1, "#b9bec4", 0.45, 0.7)
        antenna(sp, (-1.0, 1.0, zt), 1.6)
    # 배기 굴뚝
    stacks = ((1.2, -4.6), (2.4, -4.6)) if v != 2 else ((0.6, -4.7), (1.7, -4.7), (2.8, -4.7))
    sh = (7.9, 7.9, 8.3, 7.9, 7.5)[v]
    for (x, y) in stacks:
        _stack(sp, x, y, zt, sh)
    sp.box(0.6, -3.7, zt, 2.4, 1.1, 0.5, STEEL, top=Mat("#9aa1aa", 0.3))
    # 유리 사무동 (앞 모서리)
    ox0, ox1, oy0, oy1 = 0.6, 5.6, 0.5, 5.2
    oh = (4.4, 4.4, 4.4, 6.4, 4.4)[v]
    sp.box(ox0, oy0, 0.15, ox1 - ox0, oy1 - oy0, oh, Mat("#D9DDE2", 0.2), top=SILVER)
    of = Sprite.box_faces(ox0, oy0, 0.15, ox1 - ox0, oy1 - oy0, oh)
    floors = int(round(oh / 2.1))
    for side, ncol2 in (("left", 6), ("right", 6)):
        o, e1, e2 = of[side]
        for fl in range(floors):
            f0 = (fl * 2.1 + 0.3) / oh
            f1 = (fl * 2.1 + 1.95) / oh
            for c in range(ncol2):
                u0 = 0.03 + c * 0.94 / ncol2
                if side == "left" and fl == 0 and c in (1, 2):
                    continue                        # 현관 자리
                sp.window(sp.on_face(o, e1, e2, u0 + 0.006, f0, u0 + 0.94 / ncol2 - 0.006, f1),
                          WARM_WINDOW if (c + fl + v) % 3 else COOL_WINDOW, frame="#c9ccd1", glass=BLUE_GLASS)
        for fl in range(1, floors):
            _decal(sp, of[side], 0.0, fl * 2.1 / oh - 0.02, 1.0, fl * 2.1 / oh + 0.03, Mat("#C9CED4", 0.3), 0.02)
        _decal(sp, of[side], 0.0, 0.94, 1.0, 1.0, accent, 0.02)
    # 현관 (유리문 + 차양)
    o, e1, e2 = of["left"]
    sp.window(sp.on_face(o, e1, e2, 0.2, 0.0, 0.48, 1.85 / oh), COOL_WINDOW, frame="#c9ccd1", glass=BLUE_GLASS)
    sp.box(ox1 - 3.0, oy1, 2.3, 2.4, 0.7, 0.14, SILVER, top=Mat("#C5CBD2", 0.4))
    sp.lamp((ox1 - 1.8, oy1 + 0.55, 2.2), AMBER, 10)
    _hvac(sp, ox0 + 0.6, oy0 + 0.6, 0.15 + oh, 1.6, 1.2, 0.5, 1)
    if v == 3:
        o2, a2, b2 = (ox0 + 2.6, oy0 + 0.5, 0.15 + oh + 0.3), (2.0, 0, 0), (0, 3.6, 0.3)
        sp.quad(o2, a2, b2, SOLAR, back=STEEL)
        sp.panel_grid(o2, a2, b2, 3, 5, "#6f86b0", 0.45, 0.6)
    # 앞마당: 기둥 등과 운반 로버
    _lamp_post(sp, -0.4, 5.4, 0.15, 3.2)
    if v in (1, 3):
        _cargo_rover(sp, -4.3, 4.2, accent, L=4.6, W=2.0, along_x=True, z0=0.15, load="box",
                     load_mat=Mat("#C9CED4", 0.3))
    else:
        for k in range(3):
            sp.cyl((-6.8 + k * 0.6, 4.0, 0.15), (-6.8 + k * 0.6, 4.0, 1.5), 0.2, (GREEN, BLUE, Mat("#C9CED4", 0.3))[k])
        sp.line((-7.0, 4.25, 1.2), (-5.4, 4.25, 1.2), 0.06, "#7d848d")
        crate(sp, -3.6, 3.8, 1.0, Mat("#C9CED4", 0.3), 0.15)
        crate(sp, -2.4, 4.0, 0.8, ORANGE, 0.15)


# ═════════════════════════════════════════════════════════════════════
# 5. 데이터센터
# ═════════════════════════════════════════════════════════════════════

@typed("data_center", 14, 10, 6.0, "데이터센터", heights=[5.8, 5.8, 6.0, 6.4, 5.6])
def data_center(sp: Sprite, v: int):
    """창 없는 서버동: 지붕 가득 냉각 팬, 뒤쪽 방열 지느러미, 앞의 예비 발전기 상자, 동쪽의 울타리 친 변압기 마당."""
    wall = (SERVER, SERVER, SERVER, Mat("#5A626D", 0.25), Mat("#3A414B", 0.3))[v]
    wtop = (SERVER_TOP, SERVER_TOP, SERVER_TOP, Mat("#6A727D", 0.2), Mat("#4A525C", 0.2))[v]
    led = (CYAN_LIGHT, CYAN_LIGHT, GREEN_LIGHT, CYAN_LIGHT, SIGN_BLUE)[v]
    sp.contact_shadow(0.0, 0.0, 7.6, 5.6, 0.45)
    sp.box(-6.9, -4.9, 0, 13.8, 9.8, 0.15, CONCRETE)
    hx0, hx1, hy0, hy1 = -6.6, 2.4, -4.6, 1.2
    hh = (4.2, 4.2, 4.2, 4.6, 3.8)[v]
    # 서버동
    sp.box(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hh, wall, top=wtop)
    f = _faces4(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hh)
    sp.panel_grid(*f["left"], 18, 1, "#2a3038", 0.5, 0.9)
    sp.panel_grid(*f["right"], 12, 1, "#2a3038", 0.5, 0.9)
    o, e1, e2 = f["left"]
    for k in range(18):
        u = (k + 0.5) / 18
        if k % 3 == 1:
            continue
        sp.window(sp.on_face(o, e1, e2, u - 0.012, 0.8, u + 0.012, 0.83), led, frame=None,
                  glass=Mat("#1f4a48", 0.4), light_alpha=0.9)
    for side in ("left", "right", "back", "west"):
        _lit_decal(sp, f[side], 0.0, 0.06, 1.0, 0.085, Mat("#2f6f86", 0.3), led, 0.6, light2d=side != "left")
    # 에어록 현관
    ax0 = hx1 - 2.6
    sp.box(ax0, hy1, 0.15, 1.6, 1.0, 2.5, Mat("#C9CED4", 0.25), top=SILVER)
    af = Sprite.box_faces(ax0, hy1, 0.15, 1.6, 1.0, 2.5)
    door(sp, af["left"], 0.25, 0.75, 0.8, Mat("#8C939C", 0.3))
    band_on(sp, af["left"], 0.88, 0.95, ORANGE)
    # 지붕: 뒤 방열 지느러미 + 팬 격자
    zt = 0.15 + hh
    if v == 2:
        for k in range(3):
            o2 = (hx0 + 0.4 + k * 2.9, hy0 + 0.3, zt)
            sp.quad(o2, (2.6, 0, 0), (0, 0, 1.6), RADIATOR, back=RADIATOR)
            sp.panel_grid(o2, (2.6, 0, 0), (0, 0, 1.6), 8, 1, "#b9bec4", 0.45, 0.7)
    else:
        nf = 22
        for k in range(nf):
            x = hx0 + 0.35 + k * (hx1 - hx0 - 0.7) / (nf - 1)
            sp.quad((x, hy0 + 0.25, zt), (0, 1.3, 0), (0, 0, 1.4), RADIATOR, back=Mat("#D6D9DC", 0.15))
        sp.box(hx0 + 0.2, hy0 + 0.2, zt, hx1 - hx0 - 0.4, 1.4, 0.12, STEEL)
    rows, cols = ((3, 4), (2, 5), (3, 4), (3, 3), (2, 4))[v]
    s = (1.45, 1.2, 1.45, 1.45, 1.45)[v]
    gy0 = hy0 + 1.9
    gx1 = hx1 - 0.5 - s if v != 3 else hx1 - 2.6 - s
    for r in range(rows):
        for c in range(cols):
            x = hx0 + 0.5 + c * (gx1 - hx0 - 0.5) / max(1, cols - 1)
            y = gy0 + r * ((hy1 - 0.3 - s) - gy0) / max(1, rows - 1)
            sp.box(x, y, zt, s, s, 0.45, FAN_BOX, top=Mat("#A3AAB2", 0.3))
            c3 = (x + s / 2, y + s / 2, zt + 0.46)
            sp.disc(c3, (0, 0, 1), s * 0.4, CHAR)
            sp.ring3(add(c3, (0, 0, 0.01)), s * 0.4, "#b9c0c8", 0.05, seg=20)
            for a in (25, 115):
                t = math.radians(a + 20 * ((r + c) % 2))
                sp.line(add(c3, (-math.cos(t) * s * 0.36, -math.sin(t) * s * 0.36, 0.02)),
                        add(c3, (math.cos(t) * s * 0.36, math.sin(t) * s * 0.36, 0.02)), 0.07, "#6a7079")
            sp.disc(add(c3, (0, 0, 0.03)), (0, 0, 1), s * 0.08, STEEL)
    if v == 3:
        _dish(sp, (hx1 - 1.2, hy1 - 2.2, zt), 0.8, 1.0)
    sp.lamp((hx1, hy1, zt + 0.1), RED_LIGHT, 6)
    # 변압기 마당 (동쪽, 울타리)
    yx0, yx1, yy0, yy1 = 3.2, 6.7, -4.6, 1.6
    _ground(sp, yx0, yy0, yx1, yy1, Mat("#8f8576"), 0.16)
    _fence(sp, [(yx0, yy1, 0.15), (yx0, yy0, 0.15), (yx1, yy0, 0.15)], 1.6)
    pipe(sp, [(hx1 + 0.05, -3.0, 3.4), (4.2, -3.0, 3.4), (4.2, -3.0, 2.4)], 0.14, "#3a3f47")
    xs = ((4.2, -3.8), (4.2, -1.4)) if v != 1 else ((4.2, -4.0), (4.2, -1.9), (4.4, 0.1))
    for (x, y) in xs:
        _transformer(sp, x, y, 0.16, 1.6, 1.2, 1.4)
    _fence(sp, [(yx1, yy0, 0.15), (yx1, yy1, 0.15), (yx0, yy1, 0.15)], 1.6)
    sp.lamp((yx1, yy1, 1.9), AMBER, 8)
    # 예비 발전기 상자 (앞)
    ng = (2, 3, 2, 2, 3)[v]
    for k in range(ng):
        gx = -6.3 + k * 2.7
        sp.box(gx, 2.4, 0.15, 2.3, 1.6, 1.8, Mat("#7E8A78", 0.2), top=Mat("#8E9A88", 0.2))
        gf = Sprite.box_faces(gx, 2.4, 0.15, 2.3, 1.6, 1.8)
        o, e1, e2 = gf["left"]
        for j in range(5):
            vv = 0.3 + j * 0.1
            sp.face(sp.on_face(o, e1, e2, 0.1, vv, 0.62, vv + 0.05), CHAR, normal=(0, 1, 0), edge=False, ao=0)
        sp.window(sp.on_face(o, e1, e2, 0.72, 0.5, 0.9, 0.7), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
        sp.stripes(add(_fp(gf["left"], 0.0, 0.0), (0, 0.012, 0.0)), mul(e1, 1.0), mul(e2, 0.08), n=8,
                   normal=(0, 1, 0))
        sp.cyl((gx + 0.5, 3.2, 1.95), (gx + 0.5, 3.2, 2.5), 0.14, STEEL, cap_mat=CHAR)
    if v in (0, 3):
        sp.cyl((-0.6, 2.6, 0.75), (-0.6, 4.2, 0.75), 0.55, WHITE, cap_mat=WHITE, bands=[0.5], band_color="#3FB8AF")
        sp.box(-1.1, 2.8, 0.15, 1.0, 0.25, 0.4, STEEL)
        sp.box(-1.1, 3.75, 0.15, 1.0, 0.25, 0.4, STEEL)
    _lamp_post(sp, 1.2, 4.6, 0.15, 3.0)


# ═════════════════════════════════════════════════════════════════════
# 6. 로봇공학 연구소
# ═════════════════════════════════════════════════════════════════════

@typed("robotics_lab", 12, 9, 7.0, "로봇공학 연구소", heights=[7.0, 7.0, 7.0, 7.0, 7.0])
def robotics_lab(sp: Sprite, v: int):
    """연구동과 유리 시험실 (안에 주황 로봇 팔과 노란 갠트리), 앞의 시험 마당 (경고 줄 테두리, 걷는 로봇·장애물), 안테나."""
    accent = (VIOLET, ORANGE, VIOLET, TEAL, YELLOW)[v]
    sp.contact_shadow(0.0, 0.0, 6.6, 5.0, 0.45)
    sp.box(-5.9, -4.4, 0, 11.8, 8.8, 0.15, CONCRETE)
    # 연구동 (뒤 서쪽)
    lx0, lx1, ly0, ly1, lh = -5.7, -0.7, -4.2, 0.6, 4.6
    sp.box(lx0, ly0, 0.15, lx1 - lx0, ly1 - ly0, lh, LAB, top=SILVER)
    f = _faces4(lx0, ly0, 0.15, lx1 - lx0, ly1 - ly0, lh)
    for side in ("left", "right", "back", "west"):
        band_on(sp, f[side], 0.9, 0.96, accent)
    for side, n in (("back", 4), ("west", 3)):
        windows_row(sp, f[side], n, 0.18, 0.4, 0.08, 0.05)
        windows_row(sp, f[side], n, 0.6, 0.82, 0.08, 0.05)
    nw = (4, 4, 3, 4, 5)[v]
    windows_row(sp, f["left"], nw, 0.18, 0.4, 0.06, 0.04)
    windows_row(sp, f["left"], nw, 0.6, 0.82, 0.06, 0.04)
    door(sp, f["left"], 0.06, 0.2, 0.36, Mat("#cfd6dc", 0.3))
    zt = 0.15 + lh
    # 지붕: 접시 안테나, 채찍 안테나, 공조기 (+ 태양전지)
    _dish(sp, (lx0 + 1.0, ly0 + 1.1, zt), 1.2, 0.75)
    _hvac(sp, lx0 + 2.4, ly0 + 0.6, zt, 1.6, 1.2, 0.5, 1)
    antenna(sp, (lx1 - 0.5, ly0 + 0.5, zt), 1.8)
    if v == 3:
        o2, a2, b2 = (lx0 + 0.4, ly0 + 2.6, zt + 0.3), (4.2, 0, 0), (0, 1.8, 0.2)
        sp.quad(o2, a2, b2, SOLAR, back=STEEL)
        sp.panel_grid(o2, a2, b2, 6, 2, "#6f86b0", 0.45, 0.6)
    # 유리 시험실 (뒤 동쪽): 안벽 → 바닥 → 갠트리 뒤 다리 → 시험대·팔 → 앞 다리·보 → 유리
    bx0, bx1, by0, by1, bh = -0.7, 5.6, -4.2, 0.6, 5.4
    sp.box(bx0, by0, 0.15, bx1 - bx0, 0.25, bh, Mat("#5c626b", 0.2), top=SILVER)
    bwf = _faces4(bx0, by0, 0.15, bx1 - bx0, 0.25, bh)
    band_on(sp, bwf["back"], 0.9, 0.97, accent)
    sp.stripes(add(_fp(bwf["back"], 0.0, 0.8), (0, -0.012, 0)), bwf["back"][1], mul(bwf["back"][2], 0.07), n=14,
               normal=(0, -1, 0))
    for k in range(4):
        _decal(sp, bwf["left"], 0.1 + k * 0.21, 0.25, 0.25 + k * 0.21, 0.55, Mat("#454B55", 0.2))
    floor = [(bx0, by0 + 0.25, 0.17), (bx1, by0 + 0.25, 0.17), (bx1, by1, 0.17), (bx0, by1, 0.17)]
    sp.face(floor, FLOOR, normal=(0, 0, 1), edge=False, ao=0)
    sp.light_poly([add(p, (0, 0, 0.01)) for p in floor], "#d8ecff", 0.25)
    sp.polyline3([(0.4, -3.4, 0.18), (5.0, -3.4, 0.18), (5.0, -0.3, 0.18), (0.4, -0.3, 0.18)], "#E9C24A", 0.1,
                 closed=True)
    gz = 4.5
    gys = (by0 + 0.55, by1 - 0.45)
    gxs = (bx0 + 0.45, bx1 - 0.45)
    for x in gxs:
        sp.box(x - 0.14, gys[0] - 0.14, 0.17, 0.28, 0.28, gz - 0.17, GANTRY)
    tx, ty = 3.9, -1.5                       # 시험대 위 부품 자리
    sp.box(tx - 0.65, ty - 0.55, 0.17, 1.3, 1.1, 0.8, Mat("#8C939C", 0.3), top=STEEL)
    part = (Mat("#3E6FB0", 0.2), ORANGE, Mat("#3E6FB0", 0.2), WHITE, Mat("#3E6FB0", 0.2))[v]
    if v == 2:
        _robot_arm(sp, (4.7, -3.1, 0.17), 150, 58, -35, 1.3, 1.1, Mat("#3E6FB0", 0.25), k=1.0)
    if v != 1:
        crate(sp, tx - 0.25, ty - 0.25, 0.5, part, 0.97)
        pose = {0: (10, 55, -40), 2: (22, 60, -32), 3: (0, 72, -12), 4: (-6, 48, -48)}[v]
        _robot_arm(sp, (1.6, -1.9, 0.17), *pose, s1=1.9, s2=1.7, k=1.25)
    for x in gxs:
        sp.box(x - 0.14, gys[1] - 0.14, 0.17, 0.28, 0.28, gz - 0.17, GANTRY)
    for y in gys:
        sp.box(bx0 + 0.3, y - 0.16, gz, bx1 - bx0 - 0.6, 0.32, 0.3, GANTRY, top=Mat("#F0D27A", 0.15))
    gbx = (1.0, tx, 0.6, 1.2, 0.8)[v]
    sp.box(gbx - 0.25, gys[0] - 0.2, gz + 0.3, 0.5, gys[1] - gys[0] + 0.4, 0.32, ORANGE, top=Mat("#E9965E", 0.1))
    sp.box(gbx - 0.32, ty - 0.32, gz - 0.12, 0.64, 0.64, 0.42, DARK)
    if v == 1:
        # 갠트리 로봇: 늘어나는 기둥과 집게가 부품을 시험대에 내려놓는다
        sp.box(gbx - 0.14, ty - 0.14, 2.3, 0.28, 0.28, gz - 2.42, STEEL)
        sp.box(gbx - 0.2, ty - 0.2, 1.95, 0.4, 0.4, 0.4, ROBOT)
        crate(sp, gbx - 0.3, ty - 0.3, 0.6, part, 1.35)
        for sg in (-1, 1):
            sp.line((gbx + 0.36 * sg, ty, 2.0), (gbx + 0.36 * sg, ty, 1.45), 0.07, "#5c626b")
    else:
        sp.line((gbx, ty, gz - 0.12), (gbx, ty, 3.0), 0.06, "#9aa1aa")
        sp.box(gbx - 0.22, ty - 0.22, 2.6, 0.44, 0.44, 0.4, STEEL)
    # 앞·동쪽 유리벽, 살, 지붕 틀과 경고 줄무늬
    zt2 = 0.15 + bh
    _glass(sp, [(bx1, by0, 0.15), (bx1, by1, 0.15), (bx1, by1, zt2), (bx1, by0, zt2)], alpha=0.14, op=0.14)
    _glass(sp, [(bx0, by1, 0.15), (bx1, by1, 0.15), (bx1, by1, zt2), (bx0, by1, zt2)], alpha=0.14, op=0.14)
    for k in range(7):
        x = bx0 + (bx1 - bx0) * k / 6
        sp.line((x, by1 + 0.02, 0.15), (x, by1 + 0.02, zt2), 0.1, "#c9ccd1")
    for k in range(5):
        y = by0 + (by1 - by0) * k / 4
        sp.line((bx1 + 0.02, y, 0.15), (bx1 + 0.02, y, zt2), 0.1, "#c9ccd1")
    for z in (0.15, 2.8):
        sp.line((bx0, by1 + 0.02, z), (bx1 + 0.02, by1 + 0.02, z), 0.1, "#c9ccd1")
        sp.line((bx1 + 0.02, by0, z), (bx1 + 0.02, by1 + 0.02, z), 0.1, "#c9ccd1")
    sp.box(bx0, by0, zt2, bx1 - bx0, 0.3, 0.3, SILVER)
    sp.box(bx0, by0, zt2, 0.3, by1 - by0, 0.3, SILVER)
    if v == 3:
        sp.box(bx0, by0, zt2, bx1 - bx0, by1 - by0, 0.3, SILVER, top=Mat("#C5CBD2", 0.4))
        for k in range(2):
            o2, a2, b2 = (bx0 + 0.4 + k * 2.9, by0 + 0.4, zt2 + 0.4), (2.6, 0, 0), (0, 4.0, 0.3)
            sp.quad(o2, a2, b2, SOLAR, back=STEEL)
            sp.panel_grid(o2, a2, b2, 4, 5, "#6f86b0", 0.45, 0.6)
    else:
        _glass(sp, [(bx0, by0, zt2 + 0.3), (bx1, by0, zt2 + 0.3), (bx1, by1, zt2 + 0.3), (bx0, by1, zt2 + 0.3)],
               alpha=0.12, op=0.1)
        for k in range(1, 4):
            x = bx0 + (bx1 - bx0) * k / 4
            sp.line((x, by0, zt2 + 0.32), (x, by1, zt2 + 0.32), 0.08, "#c9ccd1")
    sp.box(bx1 - 0.3, by0, zt2, 0.3, by1 - by0, 0.3, SILVER)
    sp.box(bx0, by1 - 0.3, zt2, bx1 - bx0, 0.3, 0.3, SILVER)
    o, e1, e2 = Sprite.box_faces(bx0, by1 - 0.3, zt2, bx1 - bx0, 0.3, 0.3)["left"]
    sp.stripes(add(o, (0, 0.012, 0)), e1, e2, n=16, normal=(0, 1, 0))
    o, e1, e2 = Sprite.box_faces(bx1 - 0.3, by0, zt2, 0.3, by1 - by0, 0.3)["right"]
    sp.stripes(add(o, (0.012, 0, 0)), e1, e2, n=12, normal=(1, 0, 0))
    sp.glow((2.6, -1.8, 2.6), 46, "#d8ecff", 0.4)
    for x in (0.6, 2.6, 4.6):
        sp.lamp((x, -1.6, gz - 0.25), "#d8ecff", 12)
    sp.lamp((bx1 + 0.1, by1 + 0.1, 3.0), AMBER, 9)
    # 시험 마당 (앞): 줄무늬 테두리, 비탈·계단·고깔, 로봇
    qx0, qx1, qy0, qy1 = -5.6, 5.6, 1.3, 4.3
    _ground(sp, qx0, qy0, qx1, qy1, Mat("#6E6A64"), 0.16)
    sp.stripes((qx0, qy0, 0.165), (qx1 - qx0, 0, 0), (0, 0.25, 0), n=22, normal=(0, 0, 1))
    sp.stripes((qx0, qy1 - 0.25, 0.165), (qx1 - qx0, 0, 0), (0, 0.25, 0), n=22, normal=(0, 0, 1))
    rx0 = -5.1 if v != 4 else -4.6
    ramp = Mat("#9aa1aa", 0.3)
    sp.face([(rx0, 2.0, 0.17), (rx0 + 2.2, 2.0, 0.9), (rx0 + 2.2, 3.4, 0.9), (rx0, 3.4, 0.17)], ramp, ao=0)
    sp.face([(rx0 + 2.2, 2.0, 0.17), (rx0 + 2.2, 3.4, 0.17), (rx0 + 2.2, 3.4, 0.9), (rx0 + 2.2, 2.0, 0.9)],
            Mat("#8C939C", 0.3), ao=0)
    for ys, out in ((2.0, -1), (3.4, 1)):                 # 비탈 옆 세모 (뒤쪽은 3D에만)
        sp.face(_orient([(rx0, ys, 0.17), (rx0 + 2.2, ys, 0.17), (rx0 + 2.2, ys, 0.9)], (0, out, 0)),
                Mat("#8C939C", 0.3), ao=0)
    sp.stripes((rx0 + 2.21, 2.0, 0.75), (0, 1.4, 0), (0, 0, 0.15), n=8, normal=(1, 0, 0))
    if v == 0:
        _robodog(sp, -0.9, 2.8, YELLOW, 1.7, 0.16)
    elif v == 1:
        _wheelbot(sp, -0.8, 2.8, WHITE, accent, 0.16, 1.5)
    elif v == 2:
        _wheelbot(sp, -1.6, 2.3, WHITE, ORANGE, 0.16, 1.2)
        _robodog(sp, 0.3, 3.3, YELLOW, 1.35, 0.16)
    elif v == 3:
        _robodog(sp, -0.8, 2.8, Mat("#C9CED4", 0.4), 1.7, 0.16)
    else:
        _robodog(sp, -1.6, 2.4, WHITE, 1.4, 0.16)
        _robodog(sp, 0.2, 3.3, YELLOW, 1.2, 0.16)
    for k in range(3):
        sp.box(1.7 + k * 0.5, 2.0, 0.16, 0.5, 1.4, 0.25 * (3 - k), CONCRETE, top=Mat("#B5A892"))
    for (x, y) in ((4.4, 2.0), (4.4, 3.6), (3.8, 2.8)):
        _cone(sp, x, y, 0.16)
    _fence(sp, [(qx0, qy1, 0.16), (qx1, qy1, 0.16)], 0.9, "#c9ccd1")
    _lamp_post(sp, qx1 - 0.1, qy1 - 0.1, 0.16, 3.0)


# ═════════════════════════════════════════════════════════════════════
# 7. 대용량 축전소
# ═════════════════════════════════════════════════════════════════════

@typed("grid_storage_hall", 12, 8, 5.0, "대용량 축전소", heights=[4.4, 4.4, 4.4, 4.8, 5.0])
def grid_storage_hall(sp: Sprite, v: int):
    """길고 납작한 축전동: 옆을 따라 전지 선반 갈비와 환기창, 칸마다 충전량 상태등, 동쪽의 변압기·케이블 받침대·전봇대."""
    led = (GREEN_LIGHT, GREEN_LIGHT, GREEN_LIGHT, GREEN_LIGHT, SIGN_BLUE)[v]
    ledm = Mat("#2c8f4f", 0.4) if v != 4 else Mat("#2f5f9a", 0.4)
    sp.contact_shadow(0.0, 0.0, 6.6, 4.6, 0.45)
    sp.box(-5.9, -3.9, 0, 11.8, 7.8, 0.15, CONCRETE)
    hx0, hy0, hy1, hh = -5.7, -3.5, 0.9, 3.5
    hx1 = 2.4 if v != 2 else 0.6
    nb = 8 if v != 2 else 6
    sp.box(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hh, SAND, top=SAND_TOP)
    f = _faces4(hx0, hy0, 0.15, hx1 - hx0, hy1 - hy0, hh)
    zt = 0.15 + hh
    for side in ("back", "west"):
        o, e1, e2 = f[side]
        for j in range(3):
            vv = 0.18 + j * 0.13
            sp.face(sp.on_face(o, e1, e2, 0.04, vv, 0.96, vv + 0.06), CHAR, normal=norm(cross(e1, e2)), edge=False,
                    ao=0)
        _lit_decal(sp, f[side], 0.04, 0.66, 0.96, 0.77, ledm, led, 0.7)
        band_on(sp, f[side], 0.88, 0.95, ORANGE)
    # 칸마다: 환기창 + 충전량 상태등 (불 켜진 칸 수가 다르다)
    o, e1, e2 = f["left"]
    for k in range(nb):
        u0, u1 = k / nb + 0.022, (k + 1) / nb - 0.022
        for j in range(3):
            vv = 0.18 + j * 0.13
            sp.face(sp.on_face(o, e1, e2, u0 + 0.01, vv, u1 - 0.01, vv + 0.06), CHAR, normal=(0, 1, 0), edge=False,
                    ao=0)
        _decal(sp, f["left"], u0 + 0.004, 0.63, u1 - 0.004, 0.8, Mat("#2f343b", 0.3))
        lit_n = (5, 4, 5, 3, 4, 5, 2, 4)[(k + v * 3) % 8]
        for j in range(5):
            pts = sp.on_face(o, e1, e2, u0 + 0.012 + j * (u1 - u0 - 0.024) / 5, 0.66,
                             u0 + 0.012 + (j + 0.78) * (u1 - u0 - 0.024) / 5, 0.77)
            pts = [add(p, (0, 0.02, 0)) for p in pts]
            if j < lit_n:
                sp.window(pts, led if (lit_n > 2 or j > 0) else AMBER, frame=None, glass=ledm, light_alpha=0.95)
            else:
                sp.face(pts, Mat("#454b55", 0.3), normal=(0, 1, 0), edge=False, ao=0)
    for k in range(0, nb, 2):
        sp.glow(_fp(f["left"], (k + 1) / nb, 0.72), 14, led, 0.35)
    o, e1, e2 = f["right"]
    for j in range(3):
        vv = 0.18 + j * 0.13
        sp.face(sp.on_face(o, e1, e2, 0.08, vv, 0.45, vv + 0.06), CHAR, normal=(1, 0, 0), edge=False, ao=0)
    door(sp, f["right"], 0.58, 0.82, 0.68, Mat("#8C939C", 0.3))
    _lit_decal(sp, f["right"], 0.08, 0.66, 0.45, 0.77, ledm, led, 0.8)
    band_on(sp, f["left"], 0.88, 0.95, ORANGE)
    band_on(sp, f["right"], 0.88, 0.95, ORANGE)
    # 갈비 (선반 기둥)
    for k in range(nb + 1):
        x = hx1 - (hx1 - hx0) * k / nb
        sp.box(x - 0.11, hy1, 0.15, 0.22, 0.08, hh, RIB, top=SAND_TOP)
    for k in range(5):
        y = hy0 + (hy1 - hy0) * k / 4
        sp.box(hx1, y - 0.11, 0.15, 0.08, 0.22, hh, RIB, top=SAND_TOP)
    # 지붕
    sp.box(hx0, hy0, zt, hx1 - hx0, 0.16, 0.22, SAND_TOP)
    sp.box(hx0, hy0, zt, 0.16, hy1 - hy0, 0.22, SAND_TOP)
    if v == 1:
        for k in range(4):
            o2, a2, b2 = (hx0 + 0.3 + k * 2.0, hy0 + 0.4, zt + 0.25), (1.8, 0, 0), (0, 3.6, 0.35)
            sp.quad(o2, a2, b2, SOLAR, back=STEEL)
            sp.panel_grid(o2, a2, b2, 3, 5, "#6f86b0", 0.45, 0.6)
    elif v == 3:
        # 레골리스 차폐 둔덕 (지붕 위)
        sp.tbox(hx0 + 0.2, hy0 + 0.2, hx1 - 0.2, hy1 - 0.2, 0.75, 0.85, BERM, top=REGOLITH, z=zt)
        for zz in (zt + 0.3, zt + 0.6):
            k = (zz - zt) / 0.85 * 0.75
            sp.polyline3([(hx0 + 0.2 + k, hy1 - 0.2 - k, zz), (hx1 - 0.2 - k, hy1 - 0.2 - k, zz),
                          (hx1 - 0.2 - k, hy0 + 0.2 + k, zz)], "#5f5953", 0.05, 0.8)
        for x in (hx0 + 1.6, hx0 + 4.4):
            sp.cyl((x, -1.3, zt + 0.85), (x, -1.3, zt + 1.3), 0.14, STEEL)
            sp.frustum((x, -1.3, zt + 1.3), (x, -1.3, zt + 1.45), 0.34, 0.1, Mat("#9aa1aa", 0.3))
    else:
        nv = 6 if v != 2 else 4
        for k in range(nv):
            x = hx0 + 0.8 + k * (hx1 - hx0 - 1.6) / (nv - 1)
            for y in (hy0 + 1.2, hy1 - 1.2):
                sp.cyl((x, y, zt), (x, y, zt + 0.45), 0.14, STEEL)
                sp.frustum((x, y, zt + 0.45), (x, y, zt + 0.62), 0.36, 0.1, Mat("#9aa1aa", 0.3))
        if v == 4:
            for k in range(3):
                o2 = (hx0 + 0.6 + k * 2.6, hy0 + 0.25, zt)
                sp.quad(o2, (2.2, 0, 0), (0, 0, 1.3), RADIATOR, back=RADIATOR)
                sp.panel_grid(o2, (2.2, 0, 0), (0, 0, 1.3), 7, 1, "#b9bec4", 0.45, 0.7)
    # 인버터 함 줄 (v2: 축전동과 변압기 사이)
    if v == 2:
        for k in range(3):
            iy = -3.3 + k * 1.3
            sp.box(1.2, iy, 0.15, 1.3, 1.0, 2.0, WHITE, top=SILVER)
            cf = Sprite.box_faces(1.2, iy, 0.15, 1.3, 1.0, 2.0)
            for j in range(4):
                vv = 0.2 + j * 0.1
                sp.face(sp.on_face(*cf["right"], 0.15, vv, 0.85, vv + 0.05), CHAR, normal=(1, 0, 0), edge=False,
                        ao=0)
            sp.window(sp.on_face(*cf["right"], 0.3, 0.72, 0.7, 0.84), led, frame=None, glass=ledm)
            band_on(sp, cf["left"], 0.88, 0.95, ORANGE)
        pipe(sp, [(hx1 + 0.05, -1.3, 2.4), (1.85, -1.3, 2.4)], 0.12, "#3a3f47")
    # 케이블 받침대 (동쪽으로)
    for y in (-2.6, -0.4):
        sp.line((3.3, y, 0.15), (3.3, y, 2.6), 0.1, "#8a9099")
    pipe(sp, [(hx1 + 0.2 if v != 2 else 2.5, -2.6, 2.6), (3.3, -2.6, 2.6), (3.3, -0.4, 2.6)], 0.16, "#3a3f47")
    # 변압기 둘
    for (x, y) in ((3.9, -3.3), (3.9, -1.2)):
        _transformer(sp, x, y, 0.15, 1.5, 1.2, 1.4)
    pipe(sp, [(4.65, -0.9, 2.3), (5.3, 1.0, 4.15)], 0.07, "#2a2d33")
    # 전봇대 (동쪽 앞)
    px, py = 5.4, 1.2
    sp.line((px, py, 0.15), (px, py, 4.4), 0.16, "#8a7a62")
    sp.line((px - 0.1, py - 0.7, 4.1), (px - 0.1, py + 0.7, 4.1), 0.1, "#6a7079")
    for dy in (-0.55, 0.0, 0.55):
        _bushing(sp, px - 0.1, py + dy, 4.15, 0.3, 0.06)
    sp.lamp((px, py, 4.55), RED_LIGHT, 5)
    # 앞 케이블 도랑
    _ground(sp, -5.6, 1.6, 4.8, 2.0, Mat("#4a4f57", 0.2), 0.16)
    for k in range(14):
        x = -5.5 + k * 0.74
        sp.line((x, 1.62, 0.17), (x, 1.98, 0.17), 0.04, "#7d848d")
    sp.lamp((hx1 + 0.15, hy1 + 0.25, 2.9), AMBER, 8)
    _lamp_post(sp, -5.4, 3.4, 0.15, 3.0)


# ═════════════════════════════════════════════════════════════════════
# 8. 태양광 패널 밭
# ═════════════════════════════════════════════════════════════════════

def _tracker(sp: Sprite, x0, x1, yc, depth, tilt, posts, za=1.05, panel: Mat = SOLAR, cols=14, rows=3,
             frame="#c0c6ce", grid="#6f86b0"):
    """한 축 추적식 태양광 줄: 기둥, 회전 관, 해 쪽(+y)으로 tilt만큼 기운 판."""
    t = math.radians(tilt)
    a = (0.0, depth * math.cos(t), -depth * math.sin(t))
    o = (x0, yc - a[1] / 2, za - a[2] / 2)
    e1 = (x1 - x0, 0.0, 0.0)
    for px in posts:
        sp.box(px - 0.16, yc - 0.16, 0.06, 0.32, 0.32, 0.1, CONCRETE)
        sp.line((px, yc, 0.16), (px, yc, za - 0.1), 0.12, "#8a9099")
    pm = posts[len(posts) // 2]
    sp.box(pm - 0.18, yc - 0.18, za - 0.32, 0.36, 0.36, 0.26, DARK)
    sp.cyl((x0 + 0.05, yc, za - 0.08), (x1 - 0.05, yc, za - 0.08), 0.06, STEEL)
    sp.quad(o, e1, a, panel, back=STEEL)
    sp.panel_grid(o, e1, a, cols, rows, grid, 0.5, 0.6)
    sp.polyline3([o, add(o, e1), add(add(o, e1), a), add(o, a), o], frame, 0.06)


def _tracker_ns(sp: Sprite, xc, y0, y1, depth, tilt, posts, za=1.05, panel: Mat = SOLAR, cols=10, rows=3,
                frame="#c0c6ce", grid="#6f86b0"):
    """남북 축 추적 줄 (회전 관 = y축): 판이 +x 쪽(오후 해)으로 tilt만큼 기운다."""
    t = math.radians(tilt)
    a = (depth * math.cos(t), 0.0, -depth * math.sin(t))
    o = (xc - a[0] / 2, y0, za - a[2] / 2)
    e1 = (0.0, y1 - y0, 0.0)
    for py in posts:
        sp.box(xc - 0.16, py - 0.16, 0.06, 0.32, 0.32, 0.1, CONCRETE)
        sp.line((xc, py, 0.16), (xc, py, za - 0.1), 0.12, "#8a9099")
    pm = posts[len(posts) // 2]
    sp.box(xc - 0.18, pm - 0.18, za - 0.32, 0.36, 0.36, 0.26, DARK)
    sp.cyl((xc, y0 + 0.05, za - 0.08), (xc, y1 - 0.05, za - 0.08), 0.06, STEEL)
    sp.quad(o, a, e1, panel, back=STEEL)
    sp.panel_grid(o, a, e1, rows, cols, grid, 0.5, 0.6)
    sp.polyline3([o, add(o, a), add(add(o, a), e1), add(o, e1), o], frame, 0.06)


@typed("solar_field", 9, 6, 3.0, "태양광 패널 밭", heights=[2.8, 2.8, 2.8, 2.8, 2.8])
def solar_field(sp: Sprite, v: int):
    """낮은 한 축 추적식 태양광 판 두세 줄 (해를 따라 기운다), 끝의 인버터 상자와 기상 기둥."""
    sp.box(-4.4, -2.9, 0, 8.8, 5.8, 0.06, SINTER)
    x0, x1 = -4.2, 2.7
    posts = (-3.7, -0.75, 2.2)
    panel = (SOLAR, Mat("#22345A", 0.35), SOLAR, SOLAR, Mat("#1A2233", 0.45))[v]
    rows, cols, nr = [], 14, 3
    if v == 2:
        # 남북 축 네 줄 (오후 해 쪽 +x로 기울었다)
        for xc in (-3.5, -1.75, 0.0, 1.75):
            _tracker_ns(sp, xc, -2.55, 2.55, 1.4, 30.0, (-2.0, 0.0, 2.0), panel=panel, cols=10, rows=3)
    elif v == 1:
        rows, cols, nr = [(-1.45, 2.3, 30.0), (1.45, 2.3, 30.0)], 12, 4          # 크고 깊은 판 두 줄
    else:
        tilt = (28.0, 0.0, 0.0, 28.0, 18.0)[v]
        rows = [(-1.95, 1.55, tilt), (0.0, 1.55, tilt), (1.95, 1.55, tilt)]
    for k, (yc, dep, tl) in enumerate(rows):
        if v == 3 and k == 1:
            tl = 0.0
        if v == 4:
            _tracker(sp, x0, -0.9, yc, dep, tl, (-3.7, -1.4), panel=panel, cols=7, rows=nr)
            _tracker(sp, -0.6, x1, yc, dep, tl, (-0.1, 2.2), panel=panel, cols=7, rows=nr)
        else:
            _tracker(sp, x0, x1, yc, dep, tl, posts, za=1.05 if v != 1 else 1.35, panel=panel, cols=cols, rows=nr)
        if v == 3 and k == 1:
            # 판 닦는 로봇 (평평하게 눕힌 줄 위)
            sp.box(-1.4, -0.75, 1.07, 0.6, 1.5, 0.2, WHITE, top=SILVER)
            sp.cyl((-1.45, -0.7, 1.12), (-1.45, 0.7, 1.12), 0.08, ORANGE)
            sp.lamp((-1.1, 0.0, 1.32), CYAN_LIGHT, 5)
    # 인버터 상자와 기상 기둥
    ix, iy = 3.25, -1.0
    sp.box(ix - 0.1, iy - 0.1, 0.06, 1.2, 1.8, 0.12, CONCRETE)
    sp.box(ix, iy, 0.18, 1.0, 1.6, 1.4, WHITE, top=SILVER)
    f = Sprite.box_faces(ix, iy, 0.18, 1.0, 1.6, 1.4)
    band_on(sp, f["left"], 0.82, 0.9, ORANGE)
    o, e1, e2 = f["right"]
    for j in range(4):
        vv = 0.2 + j * 0.11
        sp.face(sp.on_face(o, e1, e2, 0.15, vv, 0.6, vv + 0.05), CHAR, normal=(1, 0, 0), edge=False, ao=0)
    sp.window(sp.on_face(o, e1, e2, 0.7, 0.45, 0.88, 0.65), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
    pipe(sp, [(ix, iy + 0.8, 0.3), (2.7, iy + 0.8, 0.3), (2.7, 1.95, 0.3)], 0.08, "#3a3f47")
    if v in (1, 4):
        sp.box(ix, iy + 2.0, 0.18, 1.0, 1.0, 1.1, Mat("#5B6470", 0.2), top=Mat("#7A8490", 0.2))
        bf = Sprite.box_faces(ix, iy + 2.0, 0.18, 1.0, 1.0, 1.1)
        sp.window(sp.on_face(*bf["right"], 0.3, 0.55, 0.7, 0.75), GREEN_LIGHT, frame=None, glass=Mat("#2c8f4f", 0.4))
    mx, my = 4.1, -2.3
    sp.line((mx, my, 0.06), (mx, my, 2.7), 0.07, "#9aa1aa")
    sp.line((mx - 0.3, my, 2.4), (mx + 0.3, my, 2.4), 0.05, "#9aa1aa")
    sp.disc((mx - 0.3, my, 2.46), (0, 0, 1), 0.1, SOLAR)
    sp.cyl((mx + 0.3, my, 2.4), (mx + 0.3, my, 2.5), 0.07, WHITE)
    sp.lamp((mx, my, 2.78), RED_LIGHT, 6)
    sp.lamp((ix + 1.05, iy + 1.65, 1.2), AMBER, 7)
