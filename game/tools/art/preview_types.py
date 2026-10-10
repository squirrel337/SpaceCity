#!/usr/bin/env python3
"""새 건물 종류의 그림을 따로 그려 본다 — 모듈 하나(types_<묶음>.py)의 종류만, game/art는 건드리지 않는다.

    python3 game/tools/art/preview_types.py types_power --out /tmp/prev [--ids a,b] [--sheet]

결과
  <out>/svg/<id>.svg, <id>_v1.svg ... (+ _lights.svg)  — 바닥 칸을 붉은 점선으로 겹쳐 그린다
  <out>/models.json   — model_sheet.gd --models 로 3D 모형을 본다
  <out>/sheet.png     — --sheet: 종류마다 한 줄(v0~v4)의 대조표 (godot 필요)
"""
from __future__ import annotations

import argparse
import importlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parent.parent
sys.path.insert(0, str(HERE))

import iso  # noqa: E402
from buildings import BUILDINGS  # noqa: E402
import types_common  # noqa: E402
import make_art  # noqa: E402


def _foot_overlay(svg: str, foot) -> str:
    """바닥 칸(원점 가운데 w × d)을 붉은 점선으로 겹친다 (미리보기 전용)."""
    w, d = foot
    pts = [iso.P(-w / 2, -d / 2), iso.P(w / 2, -d / 2), iso.P(w / 2, d / 2), iso.P(-w / 2, d / 2)]
    poly = " ".join("%.1f,%.1f" % p for p in pts)
    tag = ('<polygon points="%s" fill="none" stroke="#ff3b30" stroke-width="1.2" '
           'stroke-dasharray="4,3" opacity="0.9"/>' % poly)
    return svg.replace("</svg>", tag + "</svg>")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("module", help="types_<묶음> (확장자 없이)")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--ids", default="", help="쉼표로 나눈 종류 id (없으면 모듈의 전부)")
    ap.add_argument("--sheet", action="store_true", help="godot로 대조표 PNG를 만든다")
    args = ap.parse_args()
    importlib.import_module(args.module)
    ids = [i for i, m in types_common.TYPES.items() if m == args.module]
    if args.ids:
        want = args.ids.split(",")
        ids = [i for i in ids if i in want]
    if not ids:
        print("그릴 종류가 없다:", args.module)
        return 1
    reg = {i: BUILDINGS[i] for i in ids}
    files, meta = make_art.render("buildings", reg)
    out_svg = args.out / "svg"
    out_svg.mkdir(parents=True, exist_ok=True)
    order = []
    for rel, text in files.items():
        name = rel.split("/", 1)[1]
        sid = name[:-4]
        base = sid.replace("_lights", "")
        bid = base.rsplit("_v", 1)[0] if "_v" in base and base.rsplit("_v", 1)[1].isdigit() else base
        if not name.endswith("_lights.svg"):
            text = _foot_overlay(text, reg[bid]["foot"])
            order.append(str(out_svg / name))
        (out_svg / name).write_text(text, encoding="utf-8")
    pal = make_art.Palette()
    models = {"buildings": {}, "vehicles": {}}
    for sid, spec in reg.items():
        fns = [spec["fn"]] + [spec["variants"][v]["fn"] for v in sorted(spec.get("variants", {}))]
        models["buildings"][sid] = [make_art.serialize(make_art.record(f), pal) for f in fns]
    models["palette"] = pal.items
    (args.out / "models.json").write_text(json.dumps(models, separators=(",", ":")), encoding="utf-8")
    (args.out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    (args.out / "list.txt").write_text("\n".join(order) + "\n", encoding="utf-8")
    print("종류 %d개, 그림 %d장 → %s" % (len(ids), len(order), out_svg))
    if args.sheet:
        cmd = ["godot", "--headless", "--path", str(GAME), "--script", "res://tools/art/contact_sheet.gd", "--",
               "--out", str(args.out / "sheet.png"), "--cols", "5", "--scale", "2"] + order
        subprocess.run(cmd, check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
