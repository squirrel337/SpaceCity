#!/usr/bin/env python3
"""번역 목록 — 게임 코드(game/ui, game/sim)의 한글 문자열과 게임 자료(game/data)의 한글 글을 모은다.

  python3 game/tools/i18n_extract.py            # game/i18n/catalog.json을 새로 쓰고, en.json이 덮는 비율을 알린다
  python3 game/tools/i18n_extract.py --check    # 쓰지 않고 비율만 (en.json에 없는 것이 있으면 목록 앞부분)
  python3 game/tools/i18n_extract.py --derive   # 앞뒤 구분자를 뗀 꼴("기술이 모자란다: " → "기술이 모자란다")의 영어를 en.json에 더한다

코드: 주석은 건너뛰고, '+'로만 이어진 문자열 조각은 하나로 합친다 (실행 중에 화면에 오는 글과 같게).
형식 문자열(%s·%d·%.1f …)은 그대로 둔다 — 실행 중 번역(I18n)이 자리표시자를 틀로 맞춘다.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "i18n" / "catalog.json"
EN = ROOT / "i18n" / "en.json"
HANGUL = re.compile(r"[가-힣]")
GAP = re.compile(r"^\s*\+\s*(?:\\\s*)?$")          # "a" + "b", 줄을 넘기는 "a" + \ (다음 줄) "b"
ESC = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}


def literals(text: str):
    """(시작, 끝, 값) — 큰따옴표 문자열만 (이 코드베이스의 글은 모두 큰따옴표)"""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == '"':
            if text.startswith('"""', i):
                j = text.find('"""', i + 3)
                j = n if j < 0 else j + 3
                i = j
                continue
            buf = []
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    buf.append(ESC.get(text[j + 1], text[j + 1]))
                    j += 2
                    continue
                if text[j] == "\n":
                    break
                buf.append(text[j])
                j += 1
            out.append((i, j + 1, "".join(buf)))
            i = j + 1
            continue
        if c == "'":
            j = text.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        i += 1
    return out


SKIP = {"ui/i18n.gd"}                              # 번역기 자신의 표 (성씨·단위) — 화면 글이 아니다


def code_strings():
    found = {}
    files = sorted(ROOT.glob("ui/**/*.gd")) + sorted(ROOT.glob("sim/*.gd"))
    for f in files:
        if str(f.relative_to(ROOT)) in SKIP:
            continue
        text = f.read_text(encoding="utf-8")
        lits = literals(text)
        k = 0
        while k < len(lits):
            s, e, v = lits[k]
            # '+'로만 이어진 조각을 합친다 (뒤 조각이 메서드를 부르면 — ", ".join(…) — 합치지 않는다)
            while k + 1 < len(lits) and GAP.match(text[e:lits[k + 1][0]]) and not text[lits[k + 1][1]:].startswith("."):
                k += 1
                e = lits[k][1]
                v += lits[k][2]
            if HANGUL.search(v):
                found.setdefault(v, str(f.relative_to(ROOT)))
            k += 1
    return found


SEPS = (": ", " · ", " — ", ", ", " / ", " (", "\n")


def trimmed(k: str) -> str:
    """앞뒤 구분자를 뗀 꼴 ("기술이 모자란다: " → "기술이 모자란다") — 실행 중에는 그 뒤에 다른 글이 붙는다"""
    t = k
    changed = True
    while changed:
        changed = False
        for sep in SEPS:
            if t.endswith(sep):
                t = t[: -len(sep)]
                changed = True
            if t.startswith(sep):
                t = t[len(sep):]
                changed = True
    return t.strip()


def derive(cat: dict, en: dict) -> dict:
    """떼어 낸 꼴의 영어: 원문과 영어가 같은 구분자로 끝나거나 시작하면 영어도 같이 뗀다"""
    out = {}
    for k in list(cat):
        t = trimmed(k)
        if t == k or not t or not HANGUL.search(t) or t in en or k not in en:
            continue
        v = en[k]
        tv = v
        ok = True
        head = k[: k.find(t)]
        tail = k[k.find(t) + len(t):]
        for part, at_end in ((tail, True), (head, False)):
            p2 = part.strip(" ")
            if not p2:
                continue
            core = tv.rstrip(" ") if at_end else tv.lstrip(" ")
            if at_end and core.endswith(p2):
                tv = core[: -len(p2)]
            elif not at_end and core.startswith(p2):
                tv = core[len(p2):]
            else:
                ok = False
        tv = tv.strip()
        if ok and tv and not HANGUL.search(tv):
            out[t] = tv
    return out


def data_strings():
    found = {}
    for f in sorted((ROOT / "data").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))

        def walk(x):
            if isinstance(x, dict):
                for key, v in x.items():
                    if str(key).startswith("_"):
                        continue
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
            elif isinstance(x, str) and HANGUL.search(x):
                found.setdefault(x, str(f.relative_to(ROOT)))

        walk(d)
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--derive", action="store_true", help="앞뒤 구분자를 뗀 꼴의 영어를 en.json에 더한다")
    args = ap.parse_args()
    cat = code_strings()
    for k, v in data_strings().items():
        cat.setdefault(k, v)
    for k in list(cat):
        t = trimmed(k)
        if t != k and t and HANGUL.search(t):
            cat.setdefault(t, cat[k])
    en = json.loads(EN.read_text(encoding="utf-8")) if EN.exists() else {}
    if args.derive:
        add = derive(cat, en)
        en.update(add)
        EN.write_text(json.dumps(en, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print("떼어 낸 꼴의 영어 %d개를 더했다" % len(add))
    missing = [k for k in cat if k not in en]
    if not args.check:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(dict(sorted(cat.items(), key=lambda kv: (kv[1], kv[0]))), ensure_ascii=False, indent=1) + "\n",
                       encoding="utf-8")
    print("번역 목록 %d개 · 영어 %d개 (%.1f%%)" % (len(cat), len(cat) - len(missing), 100.0 * (len(cat) - len(missing)) / max(1, len(cat))))
    if args.check and missing:
        for k in missing[:20]:
            print("  없음:", k[:80].replace("\n", "\\n"), "—", cat[k])
    return 0


if __name__ == "__main__":
    sys.exit(main())
