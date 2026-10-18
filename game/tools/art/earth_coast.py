#!/usr/bin/env python3
"""지구의 해안 거리 지도 — Natural Earth 1:10m(공공 데이터)의 땅·작은 섬·호수에서 만든다 (numpy, Pillow).

    python3 game/tools/art/earth_coast.py --fetch        # Natural Earth v5.1.2 GeoJSON을 내려받아서
    python3 game/tools/art/earth_coast.py --ne DIR       # 이미 받아 둔 DIR/ne_10m_{land,minor_islands,lakes}.geojson으로
    python3 game/tools/art/earth_coast.py --ne DIR --only-metros   # 대도시 시가지 지도만 (강 지도도 DIR에서)
    python3 game/tools/art/earth_coast.py --ne DIR --only-regions  # 반도체·AI 데이터센터 지역 지도만

결과 (game/art/planets/):
  earth_coast.png         정거원통 4096 × 2048: 가장 가까운 해안까지의 거리 (땅 +, 바다 −).
                          ±40 km → 0..255 (127.5 = 해안). 셰이더가 거리를 문턱으로 잘라 해안을 픽셀마다 또렷하게 긋는다.
  earth_coast_<부지>.png  지구 부지(city_sites.json, body = earth) 둘레 256 km 네모 (중심의 접평면, 위 = 북쪽),
                          2048 × 2048 (125 m 칸), ±8 km → 0..255. 도시 가까이서는 이 지도가 해안을 긋는다.
  earth_coast_metro_<id>.png  지구의 대도시(earth_cities.json) 둘레 (반지름 + 10 km) × 2 네모, 1024 × 1024:
                          R = 해안·강 거리 ±2 km (강은 Natural Earth 강 중심선을 도시 자료의 폭만큼 물로 판다),
                          B = R의 자투리 (R + (B − 127.5)/255 칸 — 둘 다 선형이라 걸러 읽어도 맞다; 물가 띠가 m 단위로 곧다),
                          G = 공원·산 (건물이 서지 않는다; 둥근 것은 반지름을 물결로 흔든 덩어리, 가장자리는 고운 격자에서
                          그려 부드럽다). 시가지 바닥과 3D 건물이 쓴다.
                          대도시 축척에서 각진 해안·강 중심선은 차이킨 다듬기로 둥글린다.
  earth_coast_tech_<id>.png  대도시 시가지 밖의 반도체·AI 데이터센터 지역(earth_cities.json의 tech_regions) 둘레
                          (단지 지름/2 + 10 km) × 2 네모, 512 × 512 — 대도시 지도와 같은 R·G·B (강·공원 없이 해안·호수만).

거리는 4배(지역 지도는 2배) 고운 격자에서 땅·바다 경계까지 셈한 뒤 평균으로 줄인다 — 해안의 위치가 칸보다 곱다.
make_art.py와 달리 CI에서 다시 만들지 않는다 (내려받기가 필요하다). 데이터를 바꾸면 이 도구로 다시 만든다.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "game" / "art" / "planets"
SITES = ROOT / "docs" / "design" / "data" / "city_sites.json"
NE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/%s.geojson"
LAYERS = ("ne_10m_land", "ne_10m_minor_islands", "ne_10m_lakes")
R_KM = 6371.0
W, H = 4096, 2048            # 지구 전체 지도
SS = 4                       # 고운 격자 배수
RANGE_KM = 40.0
LOCAL_N = 2048               # 부지 지도
LOCAL_HALF_KM = 128.0
LOCAL_SS = 2
LOCAL_RANGE_KM = 8.0
CITIES = ROOT / "docs" / "design" / "data" / "earth_cities.json"
RIVERS = ("ne_10m_rivers_lake_centerlines", "ne_10m_rivers_europe", "ne_10m_rivers_north_america")
METRO_N = 1024
METRO_SS = 4
METRO_SMOOTH = 2             # 해안 다각형을 다듬는 차이킨 횟수 (대도시 지도만)
RIVER_SMOOTH = 3             # 강 중심선을 다듬는 횟수
METRO_PAD_KM = 10.0          # 대도시 지도의 반 폭 = 시가지 반지름 + 이만큼 (game/ui/metros.gd와 같다)
METRO_RANGE_KM = 2.0


def polygons(geojson: dict):
    """(바깥 고리, [구멍 고리]) — 고리는 [(경도, 위도)]"""
    for ft in geojson["features"]:
        g = ft["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for p in polys:
            yield p[0], p[1:]


def load_layers(src: Path | None, names=LAYERS) -> dict:
    data = {}
    for name in names:
        if src is None:
            with urllib.request.urlopen(NE_URL % name, timeout=120) as r:
                data[name] = json.loads(r.read().decode("utf-8"))
        else:
            data[name] = json.loads((src / (name + ".geojson")).read_text(encoding="utf-8"))
    return data


def chaikin(pts: list, n: int, closed: bool) -> list:
    """차이킨 모서리 깎기 n번 — 각진 선을 둥글린다 (열린 선은 끝점을 지킨다)"""
    if n <= 0 or len(pts) < 3:
        return pts
    p = np.asarray(pts, dtype=np.float64)
    for _ in range(n):
        if closed:
            nx = np.roll(p, -1, axis=0)
            p = np.stack([0.75 * p + 0.25 * nx, 0.25 * p + 0.75 * nx], axis=1).reshape(-1, 2)
        else:
            a, b = p[:-1], p[1:]
            mid = np.stack([0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b], axis=1).reshape(-1, 2)
            p = np.vstack([p[:1], mid, p[-1:]])
    return [tuple(q) for q in p]


def rasterize(data: dict, w: int, h: int, project, smooth: int = 0) -> np.ndarray:
    """땅 = True. 땅(구멍은 물) → 작은 섬 → 호수(구멍은 섬) 순서로 칠한다. project(경도, 위도) → (x, y) 또는 None.
    smooth: 고리를 다듬는 차이킨 횟수"""
    img = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(img)

    def ring_xy(ring):
        pts = [project(lon, lat) for lon, lat in ring]
        if any(p is None for p in pts):
            return None
        return chaikin(pts, smooth, True)

    def fill(layer: str, outer_val: int):
        for outer, holes in polygons(data[layer]):
            pts = ring_xy(outer)
            if pts is None or len(pts) < 3:
                continue
            dr.polygon(pts, fill=outer_val)
            for hole in holes:
                hp = ring_xy(hole)
                if hp is not None and len(hp) >= 3:
                    dr.polygon(hp, fill=255 - outer_val)

    fill("ne_10m_land", 255)
    fill("ne_10m_minor_islands", 255)
    fill("ne_10m_lakes", 0)
    return np.asarray(img) > 127


def dist_to(feature: np.ndarray, sx: np.ndarray, sy: float, k: int, kx: int, wrap_x: bool) -> np.ndarray:
    """가장 가까운 feature 칸까지의 거리 (km, 칸 중심끼리). 세로 k칸, 가로 kx칸까지만 찾는다 (그 너머는 큰 값).
    sx: 줄마다 가로 칸 크기 (km), sy: 세로 칸 크기 (km). 가로·세로로 나눠 셈하는 유클리드 거리 변환."""
    h, w = feature.shape
    far = np.uint16(k + 1)
    g = np.full((h, w), far, dtype=np.uint16)
    g[feature] = 0
    for dy in range(1, k + 1):
        up = np.zeros_like(feature)
        up[:-dy] = feature[dy:]
        down = np.zeros_like(feature)
        down[dy:] = feature[:-dy]
        hit = (up | down) & (g > dy)
        g[hit] = dy
    gy = (g.astype(np.float32) * sy) ** 2
    gy[g == far] = np.float32(1e12)
    best = gy.copy()
    sx2 = (sx.astype(np.float32) ** 2)[:, None]
    for dx in range(1, kx + 1):
        add = sx2 * np.float32(dx * dx)
        for s in (dx, -dx):
            if wrap_x:
                sh = np.roll(gy, s, axis=1)
            else:
                sh = np.full_like(gy, np.float32(1e12))
                if s > 0:
                    sh[:, s:] = gy[:, :-s]
                else:
                    sh[:, :s] = gy[:, -s:]
            np.minimum(best, sh + add, out=best)
    return np.sqrt(best)


def signed(land: np.ndarray, sx: np.ndarray, sy: float, k: int, kx: int, wrap_x: bool) -> np.ndarray:
    """땅 +, 바다 − (km). 해안은 땅 칸과 바다 칸 사이 (반 칸)"""
    to_sea = dist_to(~land, sx, sy, k, kx, wrap_x)
    to_land = dist_to(land, sx, sy, k, kx, wrap_x)
    half = 0.5 * np.minimum(sx[:, None], sy)
    return np.where(land, to_sea - half, -(to_land - half)).astype(np.float32)


def shrink(a: np.ndarray, f: int) -> np.ndarray:
    h, w = a.shape
    return a.reshape(h // f, f, w // f, f).mean(axis=(1, 3))


def encode(sd: np.ndarray, rng: float) -> Image.Image:
    v = np.clip(np.rint(127.5 + sd / rng * 127.5), 0, 255).astype(np.uint8)
    return Image.fromarray(v, "L")


def encode_fine(sd: np.ndarray, rng: float) -> tuple[Image.Image, Image.Image]:
    """(R, B): R = 거친 값, B = 그 자투리 (127.5 + (값 − R) × 255) — 셰이더는 R + (B − 0.5)/255로 읽는다"""
    v = np.clip(127.5 + sd / rng * 127.5, 0.0, 255.0)
    r = np.rint(v)
    b = np.clip(np.rint(127.5 + (v - r) * 255.0), 0, 255)
    return Image.fromarray(r.astype(np.uint8), "L"), Image.fromarray(b.astype(np.uint8), "L")


def global_map(data: dict) -> Image.Image:
    w, h = W * SS, H * SS

    def proj(lon, lat):
        return ((lon + 180.0) / 360.0 * w, (90.0 - lat) / 180.0 * h)

    land = rasterize(data, w, h, proj)
    lat = 90.0 - (np.arange(h) + 0.5) / h * 180.0
    sy = math.pi * R_KM / h
    sx = np.maximum(np.cos(np.radians(lat)), 0.02) * (2.0 * math.pi * R_KM / w)
    k = int(math.ceil(RANGE_KM / sy)) + 2
    out = np.empty((h, w), dtype=np.float32)
    band = 1024
    for y0 in range(0, h, band):
        a, b = max(0, y0 - k), min(h, y0 + band + k)
        sd = signed(land[a:b], sx[a:b], sy, k, 2 * k, True)
        out[y0:min(h, y0 + band)] = sd[y0 - a:y0 - a + min(band, h - y0)]
        print("  줄 %d / %d" % (min(h, y0 + band), h), file=sys.stderr)
    return encode(shrink(out, SS), RANGE_KM)


def latlon(lat: float, lon: float) -> np.ndarray:
    la, lo = math.radians(lat), math.radians(lon)
    return np.array([math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)])


def local_frame(lat: float, lon: float):
    """부지의 접평면: 중심 c, 동쪽 e, 북쪽 n (셰이더의 earth_surface와 같다)"""
    c = latlon(lat, lon)
    n = np.array([0.0, 0.0, 1.0]) - c * c[2]
    if np.linalg.norm(n) < 1e-6:
        n = np.array([1.0, 0.0, 0.0]) - c * c[0]
    n /= np.linalg.norm(n)
    e = np.cross(n, c)
    return c, e, n


def local_map(data: dict, lat: float, lon: float) -> tuple[Image.Image, bool]:
    c, e, n = local_frame(lat, lon)
    size = LOCAL_N * LOCAL_SS
    half = LOCAL_HALF_KM
    reach = math.cos(min(math.pi / 2, half * 3.0 / R_KM))

    def proj(plon, plat):
        d = latlon(plat, plon)
        w = float(d @ c)
        if w < reach:
            # 지도에서 먼 꼭짓점은 바깥 먼 곳으로 (다각형이 끊기지 않게, 방향은 지킨다)
            q = np.array([d @ e, d @ n])
            nq = np.linalg.norm(q)
            if nq < 1e-9:
                return (size * 0.5, size * 0.5)
            q = q / nq * half * 6.0
        else:
            q = np.array([d @ e, d @ n]) * R_KM / w
        return ((q[0] + half) / (2 * half) * size, (half - q[1]) / (2 * half) * size)

    # 지도 둘레의 다각형만 (경계 상자가 멀면 건너뛴다)
    sub = {}
    for name in LAYERS:
        feats = []
        for ft in data[name]["features"]:
            g = ft["geometry"]
            polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
            keep = []
            for p in polys:
                lons = [pt[0] for pt in p[0]]
                lats = [pt[1] for pt in p[0]]
                if max(lats) < lat - 4 or min(lats) > lat + 4:
                    continue
                dlon = 4 / max(math.cos(math.radians(lat)), 0.2)
                if (max(lons) < lon - dlon or min(lons) > lon + dlon) and max(lons) - min(lons) < 300:
                    continue
                keep.append(p)
            if keep:
                feats.append({"geometry": {"type": "MultiPolygon", "coordinates": keep}})
        sub[name] = {"features": feats}
    land = rasterize(sub, size, size, proj)
    px = 2 * half / size
    k = int(math.ceil(LOCAL_RANGE_KM / px)) + 2
    sd = signed(land, np.full(size, px), px, k, k, False)
    centre = bool(land[size // 2, size // 2])
    return encode(shrink(sd, LOCAL_SS), LOCAL_RANGE_KM), centre


def _keep_near(feats: list, lat: float, lon: float, deg: float = 1.5) -> list:
    """대도시 둘레(경계 상자)의 선만"""
    out = []
    dlon = deg / max(math.cos(math.radians(lat)), 0.2)
    for ft in feats:
        g = ft.get("geometry")
        if g is None:
            continue
        lines = g["coordinates"] if g["type"] == "MultiLineString" else [g["coordinates"]]
        keep = []
        for ln in lines:
            lats = [p[1] for p in ln]
            lons = [p[0] for p in ln]
            if max(lats) < lat - deg or min(lats) > lat + deg or max(lons) < lon - dlon or min(lons) > lon + dlon:
                continue
            keep.append(ln)
        if keep:
            out.append((ft["properties"], keep))
    return out


def _river_key(props: dict) -> list:
    keys = []
    for k in ("name", "name_en", "name_alt"):
        if props.get(k):
            keys.append(str(props[k]))
    if props.get("rivernum") is not None:
        keys.append("#%d" % int(props["rivernum"]))
    return keys


def metro_map(data: dict, rivers: dict, city: dict, n_px: int = METRO_N) -> tuple[Image.Image, bool]:
    lat, lon = float(city["lat"]), float(city["lon"])
    c, e, n = local_frame(lat, lon)
    half = float(city["radius_km"]) + METRO_PAD_KM
    size = n_px * METRO_SS
    reach = math.cos(min(math.pi / 2, half * 3.0 / R_KM))

    def proj(plon, plat):
        d = latlon(plat, plon)
        w = float(d @ c)
        if w < reach:
            q = np.array([d @ e, d @ n])
            nq = np.linalg.norm(q)
            if nq < 1e-9:
                return (size * 0.5, size * 0.5)
            q = q / nq * half * 6.0
        else:
            q = np.array([d @ e, d @ n]) * R_KM / w
        return ((q[0] + half) / (2 * half) * size, (half - q[1]) / (2 * half) * size)

    sub = {}
    for name in LAYERS:
        feats = []
        for ft in data[name]["features"]:
            g = ft["geometry"]
            polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
            keep = []
            for p in polys:
                lons = [pt[0] for pt in p[0]]
                lats = [pt[1] for pt in p[0]]
                if max(lats) < lat - 2 or min(lats) > lat + 2:
                    continue
                dlon = 2 / max(math.cos(math.radians(lat)), 0.2)
                if (max(lons) < lon - dlon or min(lons) > lon + dlon) and max(lons) - min(lons) < 300:
                    continue
                keep.append(p)
            if keep:
                feats.append({"geometry": {"type": "MultiPolygon", "coordinates": keep}})
        sub[name] = {"features": feats}
    land = rasterize(sub, size, size, proj, METRO_SMOOTH)
    # 강: 중심선을 폭만큼 물로 판다
    px = 2 * half / size
    want = city.get("rivers", {})
    if want:
        img = Image.fromarray((land * 255).astype(np.uint8), "L")
        dr = ImageDraw.Draw(img)
        for layer in RIVERS:
            if layer not in rivers:
                continue
            for props, lines in _keep_near(rivers[layer]["features"], lat, lon):
                width = next((float(want[k]) for k in _river_key(props) if k in want), None)
                if width is None:
                    continue
                w_px = max(1, int(round(width / px)))
                r = w_px / 2.0
                for ln in lines:
                    pts = chaikin([proj(p[0], p[1]) for p in ln], RIVER_SMOOTH, False)
                    # 굵은 선은 마디마다 틈이 남는다 — 마디마다 네모와 원으로 판다
                    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
                        dx, dy = x1 - x0, y1 - y0
                        ln_ = math.hypot(dx, dy)
                        if ln_ > 1e-9:
                            ox, oy = -dy / ln_ * r, dx / ln_ * r
                            dr.polygon([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy), (x1 - ox, y1 - oy), (x0 - ox, y0 - oy)], fill=0)
                    for (x, y) in pts:
                        dr.ellipse((x - r, y - r, x + r, y + r), fill=0)
        land = np.asarray(img) > 127
    k = int(math.ceil(METRO_RANGE_KM / px)) + 2
    sd = signed(land, np.full(size, px), px, k, k, False)
    red, blue = encode_fine(shrink(sd, METRO_SS), METRO_RANGE_KM)
    # 공원·산: 고운 격자에 그려 줄인다 (가장자리가 부드럽게)
    park = Image.new("L", (size, size), 0)
    pd = ImageDraw.Draw(park)
    kpx = size / (2 * half)

    def to_px(plat, plon):
        return proj(plon, plat)

    for pk in city.get("parks", []):
        x, y = to_px(float(pk[1]), float(pk[2]))
        if len(pk) >= 6:
            hl, hw, ang = float(pk[3]) * kpx, float(pk[4]) * kpx, math.radians(float(pk[5]))
            ux, uy = math.sin(ang), -math.cos(ang)       # 길이 방향 (북에서 시계 방향, 화면 y는 아래)
            vx, vy = -uy, ux
            corners = [(x + ux * a * hl + vx * b * hw, y + uy * a * hl + vy * b * hw) for a, b in ((1, 1), (1, -1), (-1, -1), (-1, 1))]
            pd.polygon(corners, fill=255)
        else:
            # 둥근 공원·산: 반지름을 몇 겹의 물결로 흔든 덩어리 (산자락·숲 가장자리처럼; 이름마다 같은 모양)
            r = float(pk[3]) * kpx
            rng = np.random.default_rng(sum(ord(ch) for ch in str(pk[0])) * 7919 + 17)
            amps = [0.16 / (k ** 0.8) for k in range(2, 8)]
            phases = rng.uniform(0.0, 2.0 * math.pi, len(amps))
            pts = []
            for i in range(144):
                th = 2.0 * math.pi * i / 144
                rr = r * (1.0 + sum(a * math.sin((k + 2) * th + ph) for k, (a, ph) in enumerate(zip(amps, phases))))
                pts.append((x + rr * math.cos(th), y + rr * math.sin(th)))
            pd.polygon(pts, fill=255)
    park = Image.fromarray(np.rint(shrink(np.asarray(park, dtype=np.float32), METRO_SS)).astype(np.uint8), "L")
    centre = bool(land[size // 2, size // 2])
    return Image.merge("RGB", (red, park, blue)), centre


REGION_N = 512


def region_list(cities_data: dict) -> list:
    """대도시 시가지 밖의 첨단 산업 지역 (metros.gd와 같은 셈: 가장 가까운 대도시까지 + 반지름 < 그 대도시 반지름 + 9 km면 시가지 안).
    지도 자료는 대도시 지도와 같은 모양으로 (radius_km = 단지 지름/2, 강·공원 없음)."""
    out = []
    cities = cities_data["cities"]
    for r in cities_data.get("tech_regions", []):
        lat, lon = float(r["lat"]), float(r["lon"])
        d = latlon(lat, lon)
        rad = float(r.get("size_km", 4.0)) * 0.5
        near = min(cities, key=lambda c: float(d @ latlon(float(c["lat"]), float(c["lon"]))) * -1.0)
        km = math.acos(max(-1.0, min(1.0, float(d @ latlon(float(near["lat"]), float(near["lon"])))))) * R_KM
        if km + rad >= float(near["radius_km"]) + 9.0:
            out.append({"id": r["id"], "lat": lat, "lon": lon, "radius_km": rad, "rivers": {}, "parks": []})
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="지구 해안 거리 지도 (Natural Earth 1:10m)")
    ap.add_argument("--ne", type=Path, help="ne_10m_*.geojson이 있는 폴더")
    ap.add_argument("--fetch", action="store_true", help="Natural Earth v5.1.2를 내려받는다")
    ap.add_argument("--only-local", action="store_true", help="부지 지도만")
    ap.add_argument("--only-metros", action="store_true", help="대도시 시가지 지도만")
    ap.add_argument("--metro", action="append", help="이 대도시(id)의 지도만 (여러 번)")
    ap.add_argument("--only-regions", action="store_true", help="반도체·AI 데이터센터 지역 지도만")
    ap.add_argument("--region", action="append", help="이 지역(id)의 지도만 (여러 번)")
    args = ap.parse_args()
    if args.ne is None and not args.fetch:
        ap.error("--ne DIR 또는 --fetch")
    data = load_layers(None if args.fetch else args.ne)
    OUT.mkdir(parents=True, exist_ok=True)
    rivers = load_layers(None if args.fetch else args.ne, RIVERS)
    cities_data = json.loads(CITIES.read_text(encoding="utf-8"))
    if args.only_regions or args.region:
        for reg in region_list(cities_data):
            if args.region and reg["id"] not in args.region:
                continue
            img, on_land = metro_map(data, rivers, reg, REGION_N)
            path = OUT / ("earth_coast_tech_%s.png" % reg["id"])
            img.save(path, optimize=True)
            print("썼다:", path, "" if on_land else "(단지 가운데가 물 위 — 지도를 확인할 것)")
        return
    for city in cities_data["cities"]:
        if args.metro and city["id"] not in args.metro:
            continue
        img, on_land = metro_map(data, rivers, city)
        path = OUT / ("earth_coast_metro_%s.png" % city["id"])
        img.save(path, optimize=True)
        print("썼다:", path, "" if on_land else "(도심이 물 위 — 지도를 확인할 것)")
    if args.only_metros:
        return
    if not args.only_local:
        print("지구 전체 …", file=sys.stderr)
        global_map(data).save(OUT / "earth_coast.png", optimize=True)
        print("썼다:", OUT / "earth_coast.png")
    sites = json.loads(SITES.read_text(encoding="utf-8"))["sites"]
    for s in sites:
        if s.get("body") != "earth":
            continue
        img, on_land = local_map(data, float(s["lat"]), float(s["lon"]))
        path = OUT / ("earth_coast_%s.png" % s["id"])
        img.save(path, optimize=True)
        print("썼다:", path, "(기지 자리: %s)" % ("땅" if on_land else "물 — 셰이더가 기지 둘레를 땅으로 둔다"))


if __name__ == "__main__":
    main()
