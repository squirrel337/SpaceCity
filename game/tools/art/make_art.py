#!/usr/bin/env python3
"""건물·탈것 SVG를 만든다.

    python3 game/tools/art/make_art.py            # game/art/ 에 쓴다
    python3 game/tools/art/make_art.py --check    # 저장된 파일이 생성 결과와 같은지만 본다 (CI)

결과: game/art/<buildings|vehicles>/<id>.svg (낮), <id>_lights.svg (밤 불빛), game/art/art.json (크기·기준점),
game/art/models.json (같은 도형을 3차원 그대로 — 게임의 3D 보기가 메시로 만든다),
game/art/planets/earth_land.png (지구의 땅·얼음·사막 지도, planets.py).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import iso  # noqa: E402
import planets  # noqa: E402
from buildings import BUILDINGS  # noqa: E402
import building_variants  # noqa: E402,F401  (BUILDINGS에 변형을 더한다)

try:
    from vehicles import VEHICLES  # noqa: E402
except ImportError:  # 탈것을 아직 만들기 전
    VEHICLES = {}

ART = HERE.parent.parent / "art"


HEADING_DEG = {"se": 0.0, "sw": 90.0, "nw": 180.0, "ne": 270.0}


def render(group: str, registry: dict) -> tuple[dict[str, str], dict]:
    files: dict[str, str] = {}
    meta: dict = {}
    for sid, spec in registry.items():
        headings = spec.get("headings", ["se"])
        extra = {k: v for k, v in spec.items() if k not in ("fn", "headings", "variants")}
        if spec.get("variants"):
            # 건물 변형: v0은 기본 설계(<id>.svg), v1~ 은 <id>_v1.svg ...
            vlist = []
            for v in range(1 + max(spec["variants"])):
                vs = spec["variants"].get(v) if v else {"fn": spec["fn"], "height": spec.get("height")}
                if vs is None:
                    continue
                iso.set_heading(0.0)
                sp = iso.Sprite(sid)
                vs["fn"](sp)
                vb = sp.viewbox()
                name = sid if v == 0 else "%s_v%d" % (sid, v)
                files["%s/%s.svg" % (group, name)] = sp.svg("body", vb)
                if sp.light:
                    files["%s/%s_lights.svg" % (group, name)] = sp.svg("light", vb)
                vm = sp.meta()
                vm["height"] = vs.get("height") or spec.get("height")
                vlist.append(vm)
            meta[sid] = dict(extra, variants=vlist)
            continue
        views = {}
        for hd in headings:
            iso.set_heading(HEADING_DEG[hd])
            sp = iso.Sprite(sid)
            spec["fn"](sp)
            vb = sp.viewbox()
            name = sid if len(headings) == 1 else "%s_%s" % (sid, hd)
            files["%s/%s.svg" % (group, name)] = sp.svg("body", vb)
            if sp.light:
                files["%s/%s_lights.svg" % (group, name)] = sp.svg("light", vb)
            views[hd] = sp.meta()
        iso.set_heading(0.0)
        if len(headings) == 1:
            meta[sid] = dict(views[headings[0]], **extra)
        else:
            meta[sid] = dict(extra, views=views)
    return files, meta


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://art/%s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
svg/scale=2.0
editor/scale_with_editor_scale=false
editor/convert_colors_with_editor_theme=false
"""


PNG_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://art/%s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def ensure_import(out: Path, rel: str) -> None:
    """새 SVG에는 Godot 가져오기 설정을 미리 둔다: 2배로 래스터화, 밉맵 (확대·축소해도 선명하게).
    Godot가 처음 가져올 때 uid와 경로를 채워 넣으므로, 이미 있는 파일은 건드리지 않는다."""
    p = out / (rel + ".import")
    if not p.exists():
        p.write_text((PNG_IMPORT if rel.endswith(".png") else IMPORT_TEMPLATE) % rel, encoding="utf-8")


# ── 3차원 모형 (models.json) ───────────────────────────────────────────
# 도형 하나가 배열 하나다. 좌표는 미터 (x·y 바닥, z 위), 색은 palette의 번호.
#   ["box", x, y, z, w, d, h, 색, 윗면 색]
#   ["poly", 색, [x, y, z, ...], 빛]                  평면 다각형 (빛: 0 또는 [색, 세기] — 밤에 빛난다)
#   ["fru", x0, y0, z0, x1, y1, z1, r0, r1, 색, 뚜껑, 뚜껑 색, [띠 위치], 띠 색, 빛]
#   ["ell", cx, cy, cz, rx, ry, rz, 자를 높이|null, 색]  구·돔·타원체
#   ["hcyl", x0, y0, z0, x1, y1, z1, r, 색, 뚜껑, 뚜껑 색, [띠 위치], 띠 색, 높이 반지름|null]
#   ["disc", cx, cy, cz, nx, ny, nz, r, 색, 뒷면 색|-1]
#   ["line", 굵기, 색, [x, y, z, ...], 밤에만]
#   ["win", 유리 색, 불빛 색, 세기, [x, y, z, ...]]
#   ["lamp", x, y, z, 색, 번짐 반지름]
#   ["glow", x, y, z, 반지름, 색, 세기]                밤의 불빛 번짐
#   ["lpoly", 색, 세기, [x, y, z, ...]]               밤에만 보이는 빛 면
#   ["grid", ox, oy, oz, e1(3), e2(3), n1, n2, 색, 굵기]  판 위의 격자선

def _r(v: float):
    v = round(v, 3) + 0.0
    return int(v) if v == int(v) else v


class Palette:
    def __init__(self):
        self.index: dict = {}
        self.items: list = []

    def __call__(self, m) -> int:
        if m is None:
            return -1
        if isinstance(m, str):
            key = (m.lower(), 0.0, 1.0)
        else:
            key = (iso.hexc(m.albedo), round(getattr(m, "gloss", 0.0), 2), round(getattr(m, "alpha", 1.0), 2))
        if key not in self.index:
            self.index[key] = len(self.items)
            self.items.append([key[0], key[1], key[2]])
        return self.index[key]


def _pts(pts):
    out = []
    for p in pts:
        out.extend(_r(c) for c in p)
    return out


def _emit(e, pal):
    return [pal(e[0]), _r(e[1])] if e else 0


def serialize(rec: list, pal: Palette) -> list:
    out = []
    for it in rec:
        k = it[0]
        if k == "box":
            _, x, y, z, w, d, h, m, t = it
            out.append(["box", _r(x), _r(y), _r(z), _r(w), _r(d), _r(h), pal(m), pal(t)])
        elif k == "poly":
            _, pts, m, e = it
            out.append(["poly", pal(m), _pts(pts), _emit(e, pal)])
        elif k == "fru":
            _, p0, p1, r0, r1, m, caps, cm, bands, bc, e = it
            out.append(["fru", *[_r(c) for c in p0], *[_r(c) for c in p1], _r(r0), _r(r1), pal(m), 1 if caps else 0,
                        pal(cm), [_r(s) for s in bands], pal(bc or iso.hexc(iso.scale(m.albedo, 0.55))), _emit(e, pal)])
        elif k == "ell":
            _, c, rx, ry, rz, clip, m = it
            out.append(["ell", *[_r(v) for v in c], _r(rx), _r(ry), _r(rz), None if clip is None else _r(clip), pal(m)])
        elif k == "hcyl":
            _, p0, p1, r, m, caps, cm, bands, bc, rz = it
            out.append(["hcyl", *[_r(c) for c in p0], *[_r(c) for c in p1], _r(r), pal(m), 1 if caps else 0, pal(cm),
                        [_r(s) for s in bands], pal(bc or iso.hexc(iso.scale(m.albedo, 0.55))),
                        None if rz is None else _r(rz)])
        elif k == "disc":
            _, c, n, r, m, back = it
            out.append(["disc", *[_r(v) for v in c], *[_r(v) for v in n], _r(r), pal(m), pal(back)])
        elif k == "line":
            _, pts, w, color, night = it
            out.append(["line", _r(w), pal(color), _pts(pts), 1 if night else 0])
        elif k == "win":
            _, pts, glow, glass, a = it
            out.append(["win", pal(glass), pal(glow), _r(a), _pts(pts)])
        elif k == "lamp":
            _, p, color, r = it
            out.append(["lamp", *[_r(c) for c in p], pal(color), _r(r)])
        elif k == "glow":
            _, p, r, color, s = it
            out.append(["glow", *[_r(c) for c in p], _r(r), pal(color), _r(s)])
        elif k == "lpoly":
            _, pts, color, a = it
            out.append(["lpoly", pal(color), _r(a), _pts(pts)])
        elif k == "grid":
            _, o, e1, e2, n1, n2, color, w = it
            out.append(["grid", *[_r(c) for c in o], *[_r(c) for c in e1], *[_r(c) for c in e2], n1, n2, pal(color), _r(w)])
        else:
            raise ValueError(k)
    return out


def record(fn) -> list:
    iso.set_heading(0.0)
    sp = iso.Sprite("model", record=True)
    fn(sp)
    return sp.rec


def models() -> str:
    pal = Palette()
    out = {"buildings": {}, "vehicles": {}}
    for sid, spec in BUILDINGS.items():
        fns = [spec["fn"]]
        for v in range(1, 1 + max(spec.get("variants", {0: None}))):
            if v in spec.get("variants", {}):
                fns.append(spec["variants"][v]["fn"])
        out["buildings"][sid] = [serialize(record(f), pal) for f in fns]
    for vid, spec in VEHICLES.items():
        out["vehicles"][vid] = serialize(record(spec["fn"]), pal)
    out["palette"] = pal.items
    # 한 줄에 모형 하나 (diff가 읽히도록)
    lines = ["{", ' "palette": ' + json.dumps(out["palette"], separators=(",", ":")) + ","]
    for group in ("buildings", "vehicles"):
        lines.append(' "%s": {' % group)
        keys = sorted(out[group])
        for i, k in enumerate(keys):
            lines.append('  "%s": %s%s' % (k, json.dumps(out[group][k], separators=(",", ":")), "," if i < len(keys) - 1 else ""))
        lines.append(" }" + ("," if group == "buildings" else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def build() -> dict[str, str]:
    files: dict[str, str] = {}
    meta = {"px_per_m": iso.S, "projection": "orthographic, azimuth 45°, elevation 30°"}
    for group, reg in (("buildings", BUILDINGS), ("vehicles", VEHICLES)):
        f, m = render(group, reg)
        files.update(f)
        meta[group] = m
    files["art.json"] = json.dumps(meta, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    files["models.json"] = models()
    for rel, fn in planets.FILES.items():
        files[rel] = planets.png(fn())
    return files


def _same(p: Path, content) -> bool:
    if not p.exists():
        return False
    if isinstance(content, bytes):
        # PNG: 압축을 푼 화소만 비교한다 (zlib 판마다 압축 결과가 다를 수 있다)
        return planets.png_pixels(p.read_bytes()) == planets.png_pixels(content)
    return p.read_text(encoding="utf-8") == content


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="파일이 생성 결과와 같은지만 확인")
    ap.add_argument("--out", type=Path, default=ART)
    args = ap.parse_args()
    files = build()
    if args.check:
        bad = []
        for rel, text in files.items():
            if not _same(args.out / rel, text):
                bad.append(rel)
        known = set(files)
        for p in args.out.rglob("*.svg"):
            rel = p.relative_to(args.out).as_posix()
            if rel not in known:
                bad.append(rel + " (생성기에 없음)")
        if bad:
            print("그림이 생성기와 다르다 — python3 game/tools/art/make_art.py 를 실행하라:")
            for b in bad[:30]:
                print("  ", b)
            return 1
        print("그림 %d개: 생성기와 같다" % len(files))
        return 0
    for rel, text in files.items():
        p = args.out / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if not _same(p, text):
            if isinstance(text, bytes):
                p.write_bytes(text)
            else:
                p.write_text(text, encoding="utf-8")
        if rel.endswith((".svg", ".png")) and args.out == ART:
            ensure_import(args.out, rel)
    print("그림 %d개를 %s 에 썼다" % (len(files), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
