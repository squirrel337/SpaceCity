"""SpaceCity 아이소메트릭 스프라이트 도구.

건물과 탈것을 3차원 도형(상자·원기둥·원뿔·구·돔·판·막대)으로 적으면
30° 정사영(바닥 2:1)으로 투영해 SVG를 만든다. 표준 라이브러리만 쓴다.

- 좌표: 미터. x는 화면 오른쪽 아래, y는 왼쪽 아래, z는 위.
- 빛: 화면 왼쪽에서 낮게 드는 따뜻한 햇빛 + 오른쪽의 차가운 반사광.
  극지의 낮은 해라서 해를 향한 옆면이 가장 밝고, 윗면은 그다음이다.
- 레이어: 'body'는 낮의 모습, 'light'는 밤에 더해 그리는 창·등 불빛.
"""
from __future__ import annotations

import math

S = 8.0                                  # SVG px / m
_R2 = math.sqrt(0.5)
C1 = _R2 * S                             # x·y → 화면 가로
C2 = _R2 * 0.5 * S                       # x·y → 화면 세로 (바닥 2:1)
C3 = math.sqrt(3.0) / 2.0 * S            # z → 화면 세로
VIEW = (0.6123724356957945, 0.6123724356957945, 0.5)   # 장면에서 카메라 쪽


_HEADING = 0.0
_HC, _HS = 1.0, 0.0


def P(x: float, y: float, z: float = 0.0) -> tuple[float, float]:
    if _HEADING:
        x, y = x * _HC - y * _HS, x * _HS + y * _HC
    return ((x - y) * C1, (x + y) * C2 - z * C3)


def PV(v) -> tuple[float, float]:
    return P(v[0], v[1], v[2])


# ── 벡터 ──────────────────────────────────────────────────────────────

def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    n = length(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n else (0.0, 0.0, 1.0)


def basis(axis):
    """축에 수직인 두 단위 벡터."""
    a = norm(axis)
    helper = (0.0, 0.0, 1.0) if abs(a[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = norm(cross(a, helper))
    v = cross(a, u)
    return u, v


def rotz(v, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2])


# ── 색 ────────────────────────────────────────────────────────────────

def rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hexc(c) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(x * 255)))) for x in c)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def scale(c, k):
    return tuple(x * k for x in c)


KEY = norm((-0.42, 0.88, 0.50))          # 햇빛 (화면 왼쪽, 낮게)
KEY_COL = (1.00, 0.90, 0.74)
FILL = norm((0.90, 0.05, 0.45))          # 반사광 (화면 오른쪽)
FILL_COL = (0.52, 0.64, 0.86)
AMB = (0.22, 0.24, 0.30)
_HALF = norm(add(KEY, VIEW))
_VIEW0, _KEY0, _FILL0 = VIEW, KEY, FILL


def set_heading(deg: float) -> None:
    """모형을 z축으로 deg만큼 돌려 그린다 (탈것의 네 방향). 카메라와 빛은 그대로다."""
    global _HEADING, _HC, _HS, VIEW, KEY, FILL, _HALF
    _HEADING = deg % 360.0
    r = math.radians(_HEADING)
    _HC, _HS = math.cos(r), math.sin(r)
    VIEW = rotz(_VIEW0, -_HEADING)
    KEY = rotz(_KEY0, -_HEADING)
    FILL = rotz(_FILL0, -_HEADING)
    _HALF = norm(add(KEY, VIEW))


def lit(albedo, n, gloss: float = 0.0):
    """표면 법선 n에서 보이는 색."""
    k = max(0.0, dot(n, KEY))
    f = max(0.0, dot(n, FILL))
    c = [albedo[i] * (AMB[i] + 1.0 * k * KEY_COL[i] + 0.38 * f * FILL_COL[i]) for i in range(3)]
    if gloss:
        s = max(0.0, dot(n, _HALF)) ** 24 * gloss
        c = [c[i] + s * KEY_COL[i] for i in range(3)]
    return tuple(c)


# ── 재질 ──────────────────────────────────────────────────────────────

class Mat:
    def __init__(self, color: str, gloss: float = 0.0, edge: float = 0.62):
        self.albedo = rgb(color)
        self.gloss = gloss
        self.edge = edge      # 테두리 선 밝기 배율


WHITE = Mat("#ECE7DC", 0.05)
FABRIC = Mat("#E2D8C3", 0.0)
CREAM = Mat("#D8CBB0")
GOLD = Mat("#D2A43C", 0.55)
SILVER = Mat("#B9C0C8", 0.45)
STEEL = Mat("#8C939C", 0.3)
DARK = Mat("#454B55", 0.15)
CHAR = Mat("#2C3038", 0.1)
SOLAR = Mat("#22345A", 0.65)
GLASS = Mat("#1C2A38", 0.8)
REGOLITH = Mat("#8A8378")
SINTER = Mat("#9B8C77")
BERM = Mat("#77706A")
ORANGE = Mat("#E07B39", 0.1)
TEAL = Mat("#3FB8AF", 0.1)
RED = Mat("#D9532C", 0.1)
YELLOW = Mat("#E9C24A", 0.1)
GREEN = Mat("#6DAE57")
LEAF = Mat("#4C8B41")
RADIATOR = Mat("#F1F2F0", 0.15)
COPPER = Mat("#B8733F", 0.4)
BLUE = Mat("#3E6FB0", 0.2)
ICE = Mat("#DCEBF2", 0.4)

AMBER = "#F2A541"         # 나트륨 등
WARM_WINDOW = "#FFC56E"
GROW = "#E07BD6"          # 수경 재배 LED (분홍)
CYAN_LIGHT = "#7FE3DA"


def _fmt(v: float) -> str:
    s = "%.2f" % v
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def pts_attr(pts) -> str:
    return " ".join(_fmt(x) + "," + _fmt(y) for x, y in pts)


def hull(points):
    """2차원 볼록 껍질 (Andrew)."""
    pts = sorted(set((round(x, 3), round(y, 3)) for x, y in points))
    if len(pts) <= 2:
        return pts

    def turn(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


# ── 스프라이트 ────────────────────────────────────────────────────────

class Sprite:
    """한 장의 그림. 도형을 뒤에서 앞 순서로 부른다."""

    def __init__(self, sid: str):
        self.sid = sid
        self.body: list[str] = []
        self.light: list[str] = []
        self.defs: list[str] = []
        self.ldefs: list[str] = []
        self.minx = self.miny = 1e9
        self.maxx = self.maxy = -1e9
        self.gid = 0
        self.edges = True

    # 경계 ---------------------------------------------------------
    def _track(self, pts, pad: float = 0.0):
        for x, y in pts:
            self.minx = min(self.minx, x - pad)
            self.maxx = max(self.maxx, x + pad)
            self.miny = min(self.miny, y - pad)
            self.maxy = max(self.maxy, y + pad)

    def _id(self, prefix: str) -> str:
        self.gid += 1
        return "%s%d" % (prefix, self.gid)

    # 기본 그리기 ---------------------------------------------------
    def poly2(self, pts, fill: str, stroke: str | None = None, sw: float = 0.6,
              opacity: float = 1.0, layer: str = "body"):
        if len(pts) < 3:
            return
        self._track(pts, sw)
        attrs = 'points="%s" fill="%s"' % (pts_attr(pts), fill)
        if stroke:
            attrs += ' stroke="%s" stroke-width="%s" stroke-linejoin="round"' % (stroke, _fmt(sw))
        if opacity < 1.0:
            attrs += ' opacity="%s"' % _fmt(opacity)
        (self.light if layer == "light" else self.body).append("<polygon %s/>" % attrs)

    def path2(self, d: str, fill: str = "none", stroke: str | None = None, sw: float = 0.6,
              opacity: float = 1.0, layer: str = "body", track=None):
        if track:
            self._track(track, sw)
        attrs = 'd="%s" fill="%s"' % (d, fill)
        if stroke:
            attrs += ' stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"' % (stroke, _fmt(sw))
        if opacity < 1.0:
            attrs += ' opacity="%s"' % _fmt(opacity)
        (self.light if layer == "light" else self.body).append("<path %s/>" % attrs)

    def polyline3(self, pts3, color: str, width_m: float = 0.08, opacity: float = 1.0,
                  layer: str = "body", closed: bool = False):
        pts = [PV(p) for p in pts3]
        if closed:
            pts.append(pts[0])
        sw = max(0.5, width_m * S)
        self._track(pts, sw)
        d = "M" + " L".join(_fmt(x) + "," + _fmt(y) for x, y in pts)
        self.path2(d, "none", color, sw, opacity, layer)

    def line(self, p0, p1, width_m: float = 0.08, color: str = "#4a4f57", opacity: float = 1.0,
             layer: str = "body"):
        self.polyline3([p0, p1], color, width_m, opacity, layer)

    def gradient(self, stops, x1, y1, x2, y2, layer: str = "body") -> str:
        gid = self._id("g")
        s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (
            _fmt(o), c, (' stop-opacity="%s"' % _fmt(a)) if a < 1 else "") for o, c, a in stops)
        (self.ldefs if layer == "light" else self.defs).append(
            '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
            % (gid, _fmt(x1), _fmt(y1), _fmt(x2), _fmt(y2), s))
        return "url(#%s)" % gid

    def radial(self, stops, cx, cy, r, fx=None, fy=None, layer: str = "body") -> str:
        gid = self._id("r")
        s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (
            _fmt(o), c, (' stop-opacity="%s"' % _fmt(a)) if a < 1 else "") for o, c, a in stops)
        f = ""
        if fx is not None:
            f = ' fx="%s" fy="%s"' % (_fmt(fx), _fmt(fy))
        (self.ldefs if layer == "light" else self.defs).append(
            '<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s"%s>%s</radialGradient>'
            % (gid, _fmt(cx), _fmt(cy), _fmt(r), f, s))
        return "url(#%s)" % gid

    # 면 -----------------------------------------------------------
    def face(self, pts3, mat: Mat, two_sided: bool = False, back: Mat | None = None,
             edge: bool | None = None, normal=None, ao: float = 0.22):
        """평면 다각형. 점은 바깥 법선에서 볼 때 반시계 방향."""
        n = normal or norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
        if dot(n, VIEW) <= 1e-6:
            if not two_sided:
                return False
            n = mul(n, -1)
            mat = back or mat
        col = lit(mat.albedo, n, mat.gloss)
        pts = [PV(p) for p in pts3]
        show_edge = self.edges if edge is None else edge
        fill = hexc(col)
        zs = [p[2] for p in pts3]
        if ao and abs(n[2]) < 0.3 and max(zs) - min(zs) > 0.3:
            # 바닥 쪽이 어두운 접지 음영 (밑에서 위로 3 m까지)
            z0 = min(zs)
            cx = sum(p[0] for p in pts3) / len(pts3)
            cy = sum(p[1] for p in pts3) / len(pts3)
            b = P(cx, cy, z0)
            t = P(cx, cy, z0 + min(3.0, max(zs) - z0))
            k0 = 1.0 - ao if z0 < 0.2 else 1.0 - ao * 0.4
            fill = self.gradient([(0, hexc(scale(col, k0)), 1.0), (1, hexc(scale(col, 1.03)), 1.0)],
                                 b[0], b[1], t[0], t[1])
        self.poly2(pts, fill, hexc(scale(col, mat.edge)) if show_edge else None, 0.5)
        return True

    def box(self, x, y, z, w, d, h, mat: Mat, top: Mat | None = None, edge: bool | None = None):
        """(x, y, z)에서 시작하는 축 정렬 상자. 보이는 세 면만 그린다."""
        x1, y1, z1 = x + w, y + d, z + h
        # 여섯 면 중 카메라를 향한 면만 그려진다 (탈것을 돌려 그릴 때 보이는 면이 바뀐다)
        self.face([(x, y1, z), (x1, y1, z), (x1, y1, z1), (x, y1, z1)], mat, edge=edge, normal=(0, 1, 0))
        self.face([(x1, y, z), (x1, y, z1), (x1, y1, z1), (x1, y1, z)], mat, edge=edge, normal=(1, 0, 0))
        self.face([(x, y, z), (x, y, z1), (x1, y, z1), (x1, y, z)], mat, edge=edge, normal=(0, -1, 0))
        self.face([(x, y, z), (x, y1, z), (x, y1, z1), (x, y, z1)], mat, edge=edge, normal=(-1, 0, 0))
        self.face([(x, y, z1), (x, y1, z1), (x1, y1, z1), (x1, y, z1)], top or mat, edge=edge, normal=(0, 0, 1))
        self.face([(x, y, z), (x1, y, z), (x1, y1, z), (x, y1, z)], mat, edge=edge, normal=(0, 0, -1))

    def tbox(self, x0, y0, x1, y1, inset, h, mat: Mat, top: Mat | None = None, z: float = 0.0):
        """윗면이 안으로 들어간 상자 (흙 둑·묻힌 창고)."""
        b = [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        t = [(x0 + inset, y0 + inset, z + h), (x1 - inset, y0 + inset, z + h),
             (x1 - inset, y1 - inset, z + h), (x0 + inset, y1 - inset, z + h)]
        for i in range(4):
            self.face([b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]], mat, ao=0.0)
        self.face(t, top or mat, normal=(0, 0, 1))

    def prism(self, base_xy, z, h, mat: Mat, top: Mat | None = None):
        """볼록 다각형 바닥(반시계)을 h만큼 세운 기둥."""
        n = len(base_xy)
        for i in range(n):
            ax, ay = base_xy[i]
            bx, by = base_xy[(i + 1) % n]
            self.face([(ax, ay, z), (bx, by, z), (bx, by, z + h), (ax, ay, z + h)], mat)
        self.face([(x, yy, z + h) for x, yy in base_xy], top or mat, normal=(0, 0, 1))

    def quad(self, origin, e1, e2, mat: Mat, back: Mat | None = None, edge: bool | None = None):
        """origin에서 e1, e2로 펼친 판 (양면)."""
        p = [origin, add(origin, e1), add(add(origin, e1), e2), add(origin, e2)]
        return self.face(p, mat, two_sided=True, back=back, edge=edge)

    def panel_grid(self, origin, e1, e2, n1: int, n2: int, color: str, width_px: float = 0.45,
                   opacity: float = 0.55):
        """판 위의 격자선 (태양전지 칸, 방열판 줄 등)."""
        segs = []
        for i in range(1, n1):
            a = add(origin, mul(e1, i / n1))
            segs.append((a, add(a, e2)))
        for j in range(1, n2):
            a = add(origin, mul(e2, j / n2))
            segs.append((a, add(a, e1)))
        d = ""
        for a, b in segs:
            pa, pb = PV(a), PV(b)
            d += "M%s,%sL%s,%s" % (_fmt(pa[0]), _fmt(pa[1]), _fmt(pb[0]), _fmt(pb[1]))
        if d:
            self.path2(d, "none", color, width_px, opacity)

    def on_face(self, origin, e1, e2, u0, v0, u1, v1):
        """판 위의 (u, v) 사각형 → 3차원 꼭짓점 (0~1 비율)."""
        def at(u, v):
            return add(add(origin, mul(e1, u)), mul(e2, v))
        return [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]

    def window(self, pts3, glow: str = WARM_WINDOW, frame: str | None = "#2a2f36",
               glass: Mat = GLASS, light_alpha: float = 0.95):
        """창. 낮에는 어두운 유리, 밤에는 불빛."""
        n = norm(cross(sub(pts3[1], pts3[0]), sub(pts3[2], pts3[0])))
        if dot(n, VIEW) <= 1e-6:
            return
        pts = [PV(p) for p in pts3]
        col = lit(glass.albedo, n, glass.gloss)
        self.poly2(pts, hexc(col), frame, 0.45)
        if len(pts) == 4:
            # 위쪽 절반에 하늘 반사
            a, b, c, d = pts
            hi = [a, b, (b[0] * 0.55 + c[0] * 0.45, b[1] * 0.55 + c[1] * 0.45),
                  (a[0] * 0.55 + d[0] * 0.45, a[1] * 0.55 + d[1] * 0.45)]
            self.poly2(hi, "#ffffff", None, 0, 0.10)
        if light_alpha > 0:
            self.poly2(pts, glow, None, 0, light_alpha, layer="light")

    # 곡면 ---------------------------------------------------------
    def frustum(self, p0, p1, r0, r1, mat: Mat, caps: bool = True, seg: int = 48,
                cap_mat: Mat | None = None, bands=(), band_color: str | None = None,
                edge: bool | None = None):
        """p0(반지름 r0)에서 p1(반지름 r1)까지의 원기둥·원뿔대."""
        axis = sub(p1, p0)
        L = length(axis)
        a = norm(axis)
        u, v = basis(a)
        rim0, rim1 = [], []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
            rim0.append(add(p0, mul(radial, r0)))
            rim1.append(add(p1, mul(radial, r1)))
        if caps:
            sil = hull([PV(p) for p in rim0 + rim1])
        else:
            # 뚜껑 없이 옆면만: 보이는 쪽 둘레(반원)를 위아래로 이은 소매 모양
            vis = []
            for i in range(seg):
                t = 2 * math.pi * i / seg
                radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
                vis.append(dot(norm(add(radial, mul(a, (r0 - r1) / L if L else 0.0))), VIEW) > 0)
            start = next((i for i in range(seg) if vis[i] and not vis[i - 1]), 0)
            arc = []
            for k in range(seg + 1):
                i = (start + k) % seg
                if not vis[i] and k > 0:
                    arc.append(i)          # 경계까지 한 점 더
                    break
                arc.append(i)
            sil = [PV(rim0[i]) for i in arc] + [PV(rim1[i]) for i in reversed(arc)]
        # 몸통 그라데이션: 화면에서 축에 수직인 방향
        ax2 = PV(axis)
        al = math.hypot(ax2[0], ax2[1])
        mid = PV(mul(add(p0, p1), 0.5))
        rr = max(r0, r1) * S
        slope = (r0 - r1) / L if L else 0.0
        if al > 1e-3:
            q = (-ax2[1] / al, ax2[0] / al)
            samples = []
            for i in range(73):
                t = 2 * math.pi * i / 72
                radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
                n = norm(add(radial, mul(a, slope)))
                if dot(n, VIEW) <= 0:
                    continue
                off = PV(mul(radial, (r0 + r1) / 2))
                o = off[0] * q[0] + off[1] * q[1]
                samples.append((o, hexc(lit(mat.albedo, n, mat.gloss))))
            samples.sort()
            if samples:
                rmean = max(1e-6, (r0 + r1) / 2 * S)
                stops = [((o / rmean + 1) / 2, c, 1.0) for o, c in samples]
                # 양 끝을 0과 1로 맞춘다
                stops = [(min(1, max(0, o)), c, al_) for o, c, al_ in stops]
                fill = self.gradient(stops, mid[0] - q[0] * rmean, mid[1] - q[1] * rmean,
                                     mid[0] + q[0] * rmean, mid[1] + q[1] * rmean)
            else:
                fill = hexc(lit(mat.albedo, a))
        else:
            fill = hexc(lit(mat.albedo, mul(a, -1)))
        show_edge = self.edges if edge is None else edge
        edge_col = hexc(scale(lit(mat.albedo, (0, 0, 1)), mat.edge * 0.8)) if show_edge else None
        self.poly2(sil, fill, edge_col, 0.5)
        # 띠 (팽창식 모듈의 갈비, 탱크 이음매)
        for s in bands:
            c = add(p0, mul(axis, s))
            rr_s = r0 + (r1 - r0) * s
            pts = []
            for i in range(seg + 1):
                t = 2 * math.pi * i / seg
                radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
                n = norm(add(radial, mul(a, slope)))
                if dot(n, VIEW) > 0.02:
                    pts.append(PV(add(c, mul(radial, rr_s))))
                elif pts:
                    self._band(pts, band_color or hexc(scale(mat.albedo, 0.55)))
                    pts = []
            if pts:
                self._band(pts, band_color or hexc(scale(mat.albedo, 0.55)))
        if caps:
            cm = cap_mat or mat
            for center, rim, n in ((p1, rim1, a), (p0, rim0, mul(a, -1))):
                if dot(n, VIEW) > 1e-6 and (r1 if center is p1 else r0) > 0:
                    col = lit(cm.albedo, n, cm.gloss)
                    self.poly2([PV(p) for p in rim], hexc(col),
                               hexc(scale(col, cm.edge)) if show_edge else None, 0.5)
        return sil

    def _band(self, pts, color):
        if len(pts) < 2:
            return
        d = "M" + " L".join(_fmt(x) + "," + _fmt(y) for x, y in pts)
        self.path2(d, "none", color, 0.55, 0.85)

    def cyl(self, p0, p1, r, mat: Mat, **kw):
        return self.frustum(p0, p1, r, r, mat, **kw)

    def disc(self, center, normal, r, mat: Mat, seg: int = 40, two_sided: bool = True,
             back: Mat | None = None, edge: bool | None = None):
        u, v = basis(normal)
        pts = [add(center, add(mul(u, r * math.cos(2 * math.pi * i / seg)),
                                mul(v, r * math.sin(2 * math.pi * i / seg)))) for i in range(seg)]
        n = norm(normal)
        if dot(n, VIEW) <= 0:
            if not two_sided:
                return
            n = mul(n, -1)
            mat = back or mat
        col = lit(mat.albedo, n, mat.gloss)
        show_edge = self.edges if edge is None else edge
        self.poly2([PV(p) for p in pts], hexc(col), hexc(scale(col, mat.edge)) if show_edge else None, 0.5)

    def sphere(self, c, r, mat: Mat, clip_z: float | None = None):
        """구. clip_z가 있으면 그 높이 위만 (돔)."""
        pts = []
        for i in range(24):
            th = 2 * math.pi * i / 24
            for j in range(13):
                ph = -math.pi / 2 + math.pi * j / 12
                p = (c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th),
                     c[2] + r * math.sin(ph))
                if clip_z is not None and p[2] < clip_z:
                    p = (p[0], p[1], clip_z)
                pts.append(PV(p))
        sil = hull(pts)
        self._shaded_round(sil, c, r, mat)
        return sil

    def dome(self, c, r, h: float | None = None, mat: Mat = SINTER, seg: int = 36):
        """바닥 원 반지름 r, 높이 h인 돔 (h=r이면 반구)."""
        h = r if h is None else h
        pts = []
        for i in range(seg):
            th = 2 * math.pi * i / seg
            for j in range(10):
                ph = (math.pi / 2) * j / 9
                pts.append(P(c[0] + r * math.cos(ph) * math.cos(th), c[1] + r * math.cos(ph) * math.sin(th),
                             c[2] + h * math.sin(ph)))
        sil = hull(pts)
        self._shaded_round(sil, c, r, mat, squash=h / r)
        return sil

    def _shaded_round(self, sil, c, r, mat: Mat, squash: float = 1.0):
        """구·돔 음영: 하이라이트에서 빛 반대쪽으로 갈수록 법선이 돌아간다."""
        hl_n = norm(add(KEY, mul(VIEW, 0.9)))
        hl = PV((c[0] + hl_n[0] * r * 0.92, c[1] + hl_n[1] * r * 0.92, c[2] + hl_n[2] * r * 0.92 * squash))
        away = sub(mul(KEY, -1), mul(hl_n, dot(mul(KEY, -1), hl_n)))
        away = norm(away)
        rad = r * S * 1.9
        stops = []
        for i in range(10):
            t = i / 9
            ang = min(math.pi, t * rad / (r * S))
            n = norm(add(mul(hl_n, math.cos(ang)), mul(away, math.sin(ang))))
            stops.append((t, hexc(lit(mat.albedo, n, mat.gloss)), 1.0))
        fill = self.radial(stops, hl[0], hl[1], rad)
        edge_col = hexc(scale(lit(mat.albedo, (0, 0, 1)), mat.edge * 0.75)) if self.edges else None
        self.poly2(sil, fill, edge_col, 0.5)

    # 면 위치 도우미 -------------------------------------------------
    @staticmethod
    def box_faces(x, y, z, w, d, h):
        """상자의 보이는 세 면: (원점, 가로 벡터, 세로 벡터). 가로×세로 = 바깥 법선."""
        return {
            "left": ((x + w, y + d, z), (-w, 0.0, 0.0), (0.0, 0.0, h)),
            "right": ((x + w, y, z), (0.0, d, 0.0), (0.0, 0.0, h)),
            "top": ((x, y, z + h), (w, 0.0, 0.0), (0.0, d, 0.0)),
        }

    @staticmethod
    def cyl_patch(p0, p1, r, s0, s1, a0, a1, lift: float = 0.02):
        """원기둥 겉면의 작은 사각형 (축 방향 s, 각도 a[도]). 창·문·표시에 쓴다."""
        axis = sub(p1, p0)
        u, v = basis(axis)

        def at(s, ang):
            t = math.radians(ang)
            radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
            return add(add(p0, mul(axis, s)), mul(radial, r + lift))
        return [at(s0, a0), at(s0, a1), at(s1, a1), at(s1, a0)]

    @staticmethod
    def facing_angle(p0, p1, direction=None):
        """원기둥 둘레에서 주어진 방향(기본: 카메라)을 가장 많이 향하는 각도[도]."""
        direction = direction or VIEW
        u, v = basis(sub(p1, p0))
        return math.degrees(math.atan2(dot(direction, v), dot(direction, u)))

    def ring3(self, center, r, color: str, width_m: float = 0.06, normal=(0, 0, 1), front_only: bool = True,
              opacity: float = 0.9, seg: int = 48, layer: str = "body"):
        """원 테두리 (보이는 앞쪽 반만)."""
        u, v = basis(normal)
        run = []
        for i in range(seg + 1):
            t = 2 * math.pi * i / seg
            radial = add(mul(u, math.cos(t)), mul(v, math.sin(t)))
            p = add(center, mul(radial, r))
            vis = (not front_only) or dot(radial, VIEW) > -0.05
            if vis:
                run.append(p)
            elif run:
                self.polyline3(run, color, width_m, opacity, layer)
                run = []
        if run:
            self.polyline3(run, color, width_m, opacity, layer)

    def ellipsoid(self, c, rx, ry, rz, mat: Mat, clip_z: float | None = None, seg: int = 28):
        """타원체 (clip_z 아래는 잘라 낸다 — 흙더미·피복에 쓴다)."""
        pts = []
        for i in range(seg):
            th = 2 * math.pi * i / seg
            for j in range(15):
                ph = -math.pi / 2 + math.pi * j / 14
                p = [c[0] + rx * math.cos(ph) * math.cos(th), c[1] + ry * math.cos(ph) * math.sin(th),
                     c[2] + rz * math.sin(ph)]
                if clip_z is not None and p[2] < clip_z:
                    p[2] = clip_z
                pts.append(P(*p))
        sil = hull(pts)
        self._shaded_round(sil, c, max(rx, ry), mat, squash=rz / max(rx, ry))
        return sil

    def half_cyl(self, p0, p1, r, mat: Mat, caps: bool = True, bands=(), band_color: str | None = None,
                 cap_mat: Mat | None = None):
        """바닥에 누운 반원통 (아치형 격납고·터널). 축은 수평."""
        axis = sub(p1, p0)
        a = norm(axis)
        side = norm(cross((0.0, 0.0, 1.0), a))       # 수평, 축에 수직
        up = (0.0, 0.0, 1.0)
        rim0, rim1 = [], []
        for i in range(25):
            t = math.pi * i / 24
            radial = add(mul(side, math.cos(t)), mul(up, math.sin(t)))
            rim0.append(add(p0, mul(radial, r)))
            rim1.append(add(p1, mul(radial, r)))
        sil = hull([PV(p) for p in rim0 + rim1])
        ax2 = PV(axis)
        al = math.hypot(ax2[0], ax2[1])
        q = (-ax2[1] / al, ax2[0] / al)
        mid = PV(mul(add(p0, p1), 0.5))
        samples = []
        for i in range(49):
            t = math.pi * i / 48
            radial = add(mul(side, math.cos(t)), mul(up, math.sin(t)))
            if dot(radial, VIEW) <= 0:
                continue
            off = PV(mul(radial, r))
            samples.append((off[0] * q[0] + off[1] * q[1], hexc(lit(mat.albedo, radial, mat.gloss))))
        samples.sort()
        rs = r * S
        stops = [(min(1, max(0, (o / rs + 1) / 2)), c, 1.0) for o, c in samples]
        fill = self.gradient(stops, mid[0] - q[0] * rs, mid[1] - q[1] * rs, mid[0] + q[0] * rs, mid[1] + q[1] * rs)
        edge_col = hexc(scale(lit(mat.albedo, (0, 0, 1)), mat.edge * 0.8)) if self.edges else None
        self.poly2(sil, fill, edge_col, 0.5)
        for s in bands:
            c = add(p0, mul(axis, s))
            pts = []
            for i in range(25):
                t = math.pi * i / 24
                radial = add(mul(side, math.cos(t)), mul(up, math.sin(t)))
                if dot(radial, VIEW) > 0.02:
                    pts.append(PV(add(c, mul(radial, r))))
            self._band(pts, band_color or hexc(scale(mat.albedo, 0.55)))
        if caps:
            cm = cap_mat or mat
            for rim, n in ((rim1, a), (rim0, mul(a, -1))):
                if dot(n, VIEW) > 1e-6:
                    col = lit(cm.albedo, n, cm.gloss)
                    self.poly2([PV(p) for p in rim], hexc(col), hexc(scale(col, cm.edge)) if self.edges else None, 0.5)
        return sil

    def stripes(self, origin, e1, e2, n: int = 6, colors=("#E9C24A", "#2A2D33"), normal=None):
        """판 위의 사선 경고 줄무늬 (노랑·검정)."""
        nrm = normal or norm(cross(e1, e2))
        if dot(nrm, VIEW) <= 0:
            return
        for i in range(n):
            u0, u1 = i / n, (i + 1) / n
            col = rgb(colors[i % 2])
            c = lit(col, nrm)
            quad = [add(add(origin, mul(e1, u0)), (0, 0, 0)), add(origin, mul(e1, u1)),
                    add(add(origin, mul(e1, min(1.0, u1 + 0.5 / n))), e2),
                    add(add(origin, mul(e1, min(1.0, u0 + 0.5 / n))), e2)]
            self.poly2([PV(p) for p in quad], hexc(c), None)

    def tree(self, base, h: float, r: float, mat: Mat = LEAF, trunk: Mat = COPPER, kind: str = "round"):
        """녹지 공원의 나무."""
        self.cyl(base, add(base, (0, 0, h * 0.45)), r * 0.12, trunk, edge=False)
        if kind == "cone":
            self.frustum(add(base, (0, 0, h * 0.25)), add(base, (0, 0, h)), r, 0.02, mat, caps=False, edge=False)
        else:
            self.sphere(add(base, (0, 0, h - r * 0.9)), r, mat)

    def truss(self, p0, p1, w_m: float, color: str = "#8a9099", width_m: float = 0.06, n: int = 6,
              side=None):
        """두 줄 기둥과 지그재그 보 (탑·크레인)."""
        axis = sub(p1, p0)
        sd = norm(side) if side else basis(axis)[0]
        off = mul(sd, w_m / 2)
        a0, a1 = sub(p0, off), sub(p1, off)
        b0, b1 = add(p0, off), add(p1, off)
        self.line(a0, a1, width_m, color)
        self.line(b0, b1, width_m, color)
        for i in range(n):
            s0, s1 = i / n, (i + 1) / n
            pa = add(a0, mul(axis, s0))
            pb = add(b0, mul(axis, s1))
            self.line(pa, pb, width_m * 0.7, color)
            self.line(add(a0, mul(axis, s1)), pb, width_m * 0.5, color)

    def berm_ring(self, c, r_in: float, r_out: float, h: float, mat: Mat = BERM, seg: int = 48,
                  front: bool | None = None):
        """둥근 흙 둑 (착륙장 둘레·원자로 차폐). front=True면 앞쪽 반, False면 뒤쪽 반만."""
        rm = (r_in + r_out) / 2
        order = sorted(range(seg), key=lambda k: dot((math.cos(2 * math.pi * (k + 0.5) / seg),
                                                      math.sin(2 * math.pi * (k + 0.5) / seg), 0.0), VIEW))
        for i in order:
            t0 = 2 * math.pi * i / seg
            t1 = 2 * math.pi * (i + 1) / seg
            tm = (t0 + t1) / 2
            radial = (math.cos(tm), math.sin(tm), 0.0)
            is_front = dot(radial, VIEW) > 0
            if front is not None and is_front != front:
                continue
            o0 = (c[0] + r_out * math.cos(t0), c[1] + r_out * math.sin(t0), c[2])
            o1 = (c[0] + r_out * math.cos(t1), c[1] + r_out * math.sin(t1), c[2])
            m0 = (c[0] + rm * math.cos(t0), c[1] + rm * math.sin(t0), c[2] + h)
            m1 = (c[0] + rm * math.cos(t1), c[1] + rm * math.sin(t1), c[2] + h)
            i0 = (c[0] + r_in * math.cos(t0), c[1] + r_in * math.sin(t0), c[2])
            i1 = (c[0] + r_in * math.cos(t1), c[1] + r_in * math.sin(t1), c[2])
            # 바깥 사면과 안쪽 사면 중 보이는 것
            self.face([o0, o1, m1, m0], mat, edge=False, ao=0.0)
            self.face([i1, i0, m0, m1], mat, edge=False, ao=0.0)

    def rock(self, c, r: float, mat: Mat = REGOLITH):
        """작은 바위 (돔을 납작하게)."""
        self.ellipsoid(c, r, r * 0.8, r * 0.55, mat, clip_z=c[2])

    def parts(self, items):
        """(중심점, 그리기 함수) 목록을 카메라에서 먼 것부터 그린다."""
        for _, fn in sorted(items, key=lambda it: dot(it[0], VIEW)):
            fn()

    # 바닥 그림자·불빛 ---------------------------------------------
    def contact_shadow(self, cx, cy, rx_m, ry_m, opacity: float = 0.45, z: float = 0.0):
        """밑동의 접지 그림자 (부드러운 타원)."""
        c = P(cx, cy, z)
        pts = []
        for i in range(32):
            t = 2 * math.pi * i / 32
            pts.append(P(cx + rx_m * math.cos(t), cy + ry_m * math.sin(t), z))
        rad = max(rx_m, ry_m) * S * 1.05
        fill = self.radial([(0, "#000000", opacity), (0.65, "#000000", opacity * 0.6), (1, "#000000", 0.0)],
                           c[0], c[1], rad)
        self.poly2(hull(pts), fill)

    def glow(self, p3, r_px: float, color: str = AMBER, strength: float = 0.9):
        """밤 레이어의 불빛 번짐."""
        c = PV(p3)
        fill = self.radial([(0, color, strength), (0.35, color, strength * 0.45), (1, color, 0.0)],
                           c[0], c[1], r_px, layer="light")
        pts = [(c[0] + r_px * math.cos(2 * math.pi * i / 20), c[1] + r_px * math.sin(2 * math.pi * i / 20))
               for i in range(20)]
        self._track(pts)
        self.light.append('<polygon points="%s" fill="%s"/>' % (pts_attr(pts), fill))

    def lamp(self, p3, color: str = AMBER, r_px: float = 10.0):
        c = PV(p3)
        self.poly2([(c[0] - 0.9, c[1] - 0.9), (c[0] + 0.9, c[1] - 0.9), (c[0] + 0.9, c[1] + 0.9),
                    (c[0] - 0.9, c[1] + 0.9)], "#fff2d0", None)
        self.glow(p3, r_px, color)

    # 출력 ---------------------------------------------------------
    def viewbox(self, pad: float = 3.0):
        x0 = math.floor(self.minx - pad)
        y0 = math.floor(self.miny - pad)
        x1 = math.ceil(self.maxx + pad)
        y1 = math.ceil(self.maxy + pad)
        return x0, y0, x1 - x0, y1 - y0

    def svg(self, layer: str = "body", vb=None) -> str:
        x0, y0, w, h = vb or self.viewbox()
        items = self.light if layer == "light" else self.body
        defs = self.ldefs if layer == "light" else self.defs
        out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d">'
               % (w, h, x0, y0, w, h)]
        if defs:
            out.append("<defs>" + "".join(defs) + "</defs>")
        out.extend(items)
        out.append("</svg>")
        return "\n".join(out) + "\n"

    def meta(self, extra: dict | None = None) -> dict:
        x0, y0, w, h = self.viewbox()
        m = {"px": [w, h], "anchor": [-x0, -y0], "lights": bool(self.light)}
        if extra:
            m.update(extra)
        return m
