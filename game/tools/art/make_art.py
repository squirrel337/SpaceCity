#!/usr/bin/env python3
"""건물·탈것 SVG를 만든다.

    python3 game/tools/art/make_art.py            # game/art/ 에 쓴다
    python3 game/tools/art/make_art.py --check    # 저장된 파일이 생성 결과와 같은지만 본다 (CI)

결과: game/art/<buildings|vehicles>/<id>.svg (낮), <id>_lights.svg (밤 불빛), game/art/art.json (크기·기준점).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import iso  # noqa: E402
from buildings import BUILDINGS  # noqa: E402

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
        extra = {k: v for k, v in spec.items() if k not in ("fn", "headings")}
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


def ensure_import(out: Path, rel: str) -> None:
    """새 SVG에는 Godot 가져오기 설정을 미리 둔다: 2배로 래스터화, 밉맵 (확대·축소해도 선명하게).
    Godot가 처음 가져올 때 uid와 경로를 채워 넣으므로, 이미 있는 파일은 건드리지 않는다."""
    p = out / (rel + ".import")
    if not p.exists():
        p.write_text(IMPORT_TEMPLATE % rel, encoding="utf-8")


def build() -> dict[str, str]:
    files: dict[str, str] = {}
    meta = {"px_per_m": iso.S, "projection": "orthographic, azimuth 45°, elevation 30°"}
    for group, reg in (("buildings", BUILDINGS), ("vehicles", VEHICLES)):
        f, m = render(group, reg)
        files.update(f)
        meta[group] = m
    files["art.json"] = json.dumps(meta, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    return files


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="파일이 생성 결과와 같은지만 확인")
    ap.add_argument("--out", type=Path, default=ART)
    args = ap.parse_args()
    files = build()
    if args.check:
        bad = []
        for rel, text in files.items():
            p = args.out / rel
            if not p.exists() or p.read_text(encoding="utf-8") != text:
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
        if not p.exists() or p.read_text(encoding="utf-8") != text:
            p.write_text(text, encoding="utf-8")
        if rel.endswith(".svg") and args.out == ART:
            ensure_import(args.out, rel)
    print("그림 %d개를 %s 에 썼다" % (len(files), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
