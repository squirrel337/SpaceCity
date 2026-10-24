#!/usr/bin/env python3
"""게임이 읽는 데이터(game/data)가 문서의 단일 출처(docs/design/data, docs/concept/examples)와 같은지 확인한다.

    python3 game/tools/sync_data.py          # 다르면 실패
    python3 game/tools/sync_data.py --write  # 문서 쪽 데이터로 덮어쓴다
"""

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "game" / "data"
SOURCES = {
    "city_modules.json": ROOT / "docs" / "design" / "data" / "city_modules.json",
    "city_techs.json": ROOT / "docs" / "design" / "data" / "city_techs.json",
    "city_sites.json": ROOT / "docs" / "design" / "data" / "city_sites.json",
    "sky.json": ROOT / "docs" / "design" / "data" / "sky.json",
    "surfaces.json": ROOT / "docs" / "design" / "data" / "surfaces.json",
    "transport.json": ROOT / "docs" / "design" / "data" / "transport.json",
    "earth_cities.json": ROOT / "docs" / "design" / "data" / "earth_cities.json",
    "city_layout.json": ROOT / "docs" / "design" / "data" / "city_layout.json",
    "city_progress.json": ROOT / "docs" / "design" / "data" / "city_progress.json",
    "city_research.json": ROOT / "docs" / "design" / "data" / "city_research.json",
    "city_hazards.json": ROOT / "docs" / "design" / "data" / "city_hazards.json",
    "city_trade.json": ROOT / "docs" / "design" / "data" / "city_trade.json",
    "scenarios.json": ROOT / "docs" / "design" / "data" / "scenarios.json",
    "city_people.json": ROOT / "docs" / "design" / "data" / "city_people.json",
    "city_politics.json": ROOT / "docs" / "design" / "data" / "city_politics.json",
    "nearby_stars.json": ROOT / "docs" / "concept" / "examples" / "nearby_stars.json",
}
FILES = tuple(SOURCES)


def main():
    parser = argparse.ArgumentParser(description="게임 데이터 사본 확인")
    parser.add_argument("--write", action="store_true", help="문서 쪽 데이터를 game/data로 복사")
    args = parser.parse_args()
    stale = [name for name in FILES
             if not (TARGET / name).exists() or SOURCES[name].read_bytes() != (TARGET / name).read_bytes()]
    if args.write:
        for name in FILES:
            shutil.copyfile(SOURCES[name], TARGET / name)
        print("복사함:", ", ".join(FILES))
        return
    if stale:
        print("game/data가 docs/design/data와 다르다:", ", ".join(stale))
        print("python3 game/tools/sync_data.py --write 로 맞춘다.")
        sys.exit(1)
    print("데이터 일치:", ", ".join(FILES))


if __name__ == "__main__":
    main()
