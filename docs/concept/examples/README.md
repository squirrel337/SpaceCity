# examples — 레퍼런스 코드와 시드 데이터

컨셉 문서의 수치를 직접 확인할 수 있는 예제다. Python 3.8 이상, 표준 라이브러리만 쓴다.

| 파일 | 내용 |
|---|---|
| `formulas.py` | 항성·행성·문명·이동·공학 공식. 직접 실행하면 문서에 인용한 예시 값을 출력 |
| `system_generator.py` | 시드 기반 결정론적 항성계 생성기 + 실제 항성 데이터 보고서 |
| `nearby_stars.json` | 실제 근거리 항성·유명 외계행성계 시드 데이터 (33개 계, 행성 55개, 게임용 근사값) |

```bash
cd docs/concept/examples

python3 formulas.py                                  # 공식 예시 값
python3 system_generator.py --seed 2061              # 실제 분광형 비율로 항성계 생성
python3 system_generator.py --seed 1707 --preset game  # 게임 보정 비율
python3 system_generator.py --seed 1707 --json       # JSON 출력 (게임 데이터 형식 예)
python3 system_generator.py --real                   # 실제 항성 데이터의 거주가능영역·평형온도
```

`nearby_stars.json` 의 수치는 Claude의 내장 지식(2026년 6월까지 학습)에서 나온 근사값이다.
출시 전 SIMBAD, Gaia DR3, NASA Exoplanet Archive로 교차 검증할 것.
