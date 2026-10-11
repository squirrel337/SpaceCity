#!/usr/bin/env python3
"""지구의 해안 거리 지도 — Natural Earth 1:10m(공공 데이터)의 땅·작은 섬·호수에서 만든다 (numpy, Pillow).

    python3 game/tools/art/earth_coast.py --fetch        # Natural Earth v5.1.2 GeoJSON을 내려받아서
    python3 game/tools/art/earth_coast.py --ne DIR       # 이미 받아 둔 DIR/ne_10m_{land,minor_islands,lakes}.geojson으로

결과 (game/art/planets/):
  earth_coast.png         정거원통 4096 × 2048: 가장 가까운 해안까지의 거리 (땅 +, 바다 −).
                          ±40 km → 0..255 (127.5 = 해안). 셰이더가 거리를 문턱으로 잘라 해안을 픽셀마다 또렷하게 긋는다.
  earth_coast_<부지>.png  지구 부지(city_sites.json, body = earth) 둘레 256 km 네모 (중심의 접평면, 위 = 북쪽),
                          2048 × 2048 (125 m 칸), ±8 km → 0..255. 도시 가까이서는 이 지도가 해안을 긋는다.

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


def polygons(geojson: dict):
    """(바깥 고리, [구멍 고리]) — 고리는 [(경도, 위도)]"""
    for ft in geojson["features"]:
        g = ft["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for p in polys:
            yield p[0], p[1:]


def load_layers(src: Path | None) -> dict:
    data = {}
    for name in LAYERS:
        if src is None:
            with urllib.request.urlopen(NE_URL % name, timeout=120) as r:
                data[name] = json.loads(r.read().decode("utf-8"))
        else:
            data[name] = json.loads((src / (name + ".geojson")).read_text(encoding="utf-8"))
    return data


def rasterize(data: dict, w: int, h: int, project) -> np.ndarray:
    """땅 = True. 땅(구멍은 물) → 작은 섬 → 호수(구멍은 섬) 순서로 칠한다. project(경도, 위도) → (x, y) 또는 None"""
    img = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(img)

    def ring_xy(ring):
        pts = [project(lon, lat) for lon, lat in ring]
        if any(p is None for p in pts):
            return None
        return pts

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


def main() -> None:
    ap = argparse.ArgumentParser(description="지구 해안 거리 지도 (Natural Earth 1:10m)")
    ap.add_argument("--ne", type=Path, help="ne_10m_*.geojson이 있는 폴더")
    ap.add_argument("--fetch", action="store_true", help="Natural Earth v5.1.2를 내려받는다")
    ap.add_argument("--only-local", action="store_true", help="부지 지도만")
    args = ap.parse_args()
    if args.ne is None and not args.fetch:
        ap.error("--ne DIR 또는 --fetch")
    data = load_layers(None if args.fetch else args.ne)
    OUT.mkdir(parents=True, exist_ok=True)
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
