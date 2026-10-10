#!/usr/bin/env python3
"""게임이 읽는 데이터(game/data)가 디자인 문서의 단일 출처(docs/design/data)와 같은지 확인한다.

    python3 game/tools/sync_data.py          # 다르면 실패
    python3 game/tools/sync_data.py --write  # 문서 쪽 데이터로 덮어쓴다
"""

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "design" / "data"
TARGET = ROOT / "game" / "data"
FILES = ("city_modules.json", "city_techs.json")


def main():
    parser = argparse.ArgumentParser(description="게임 데이터 사본 확인")
    parser.add_argument("--write", action="store_true", help="문서 쪽 데이터를 game/data로 복사")
    args = parser.parse_args()
    stale = [name for name in FILES
             if not (TARGET / name).exists() or (SOURCE / name).read_bytes() != (TARGET / name).read_bytes()]
    if args.write:
        for name in FILES:
            shutil.copyfile(SOURCE / name, TARGET / name)
        print("복사함:", ", ".join(FILES))
        return
    if stale:
        print("game/data가 docs/design/data와 다르다:", ", ".join(stale))
        print("python3 game/tools/sync_data.py --write 로 맞춘다.")
        sys.exit(1)
    print("데이터 일치:", ", ".join(FILES))


if __name__ == "__main__":
    main()
