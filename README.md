# SpaceCity

달 남극의 작은 기지에서 별을 감싸는 문명까지 — 물리 법칙이 곧 게임 규칙인 우주 문명 시뮬레이터 (가제).

> 당신은 달 남극 기지를 돌보도록 만들어진 AI, '시드'다. 120명의 숨에서 시작해 별 사이로 흩어지는 문명까지 — 빛보다 빠른 명령은 없다.

현재 상세 컨셉 디자인 단계다. 확정안은 [docs/design](docs/design/README.md)에서 시작한다.

## 실행해 보기 — 시대 0 프로토타입

달 남극 기지의 첫 3년을 직접 운영하는 [Godot 프로토타입](game/README.md)이 있다. **Windows(.exe)와 Android(.apk)** 로 내보낸다.

- 빌드 받기: GitHub Actions의 **Game builds (Windows · Android)** 실행 결과 → Artifacts, 또는 `prototype-latest` 프리릴리스
- 소스에서 실행: Godot 4.7.2로 `game/` 폴더를 연다
- 규칙은 디자인 문서의 밸런스 시뮬레이터와 같다 — `python3 game/tools/parity_check.py`가 하루 단위로 확인한다
- 3D 세계: 도시가 구 모양의 달 남극에 서 있다. 구글 어스처럼 돌려 보고, 줌아웃하면 달 전체 → 지구와 달 → 태양계 → 이웃 별까지 이어진다. 천체는 실제 궤도 요소로 게임 날짜의 자리에 있다
- 자유 배치: 건물과 길을 원하는 자리에 놓는다 (유령 건물, 회전, 모양 고르기). 태양광 타워는 능선의 일조 구역에, 착륙장·원자로는 거리를 두어야 한다
- 건물 145종: 기본 모듈 29종마다 같은 일을 하는 다른 설계 4종(계열) — 킬로파워, 매립형 원자로, 팽창 거주동, RASSOR 굴착 로봇 …. 종류마다 모양 다섯 가지, 모두 725가지
- 지도: 같은 3D 장면을 기지 바로 위에서 내려다본 평면도(직교 투영). 건물·탈것의 3D 모델은 [game/tools/art](game/tools/art/make_art.py) 생성기가 만든다

## 상세 컨셉 디자인 v1.0

| 문서 | 내용 |
|---|---|
| [개요·확정된 결정](docs/design/README.md) | 결정 표, 한 페이지 요약, 문서 지도, 카탈로그에서 바뀐 점 |
| [01 비전·세계관](docs/design/01-vision-world.md) | 주제, 세계관 연표, 시드와 헌장, 인물, 다섯 막 |
| [02 구조·진행](docs/design/02-structure-progression.md) | 시대 전환, 시간 시스템, K·인구·플레이 시간 곡선, 엔딩 |
| [03 도시 레이어](docs/design/03-city-layer.md) | 시대 0 상세 규칙, 모듈 29계열 145종([전체 목록](docs/design/03a-module-catalog.md)), 기술 20종, 밸런스 시뮬레이션 결과 |
| [04 항성계 레이어](docs/design/04-system-layer.md) | Δv 지하철 지도, 항로, 함선, 메가프로젝트, 지구 정치 |
| [05 성간 레이어](docs/design/05-interstellar-layer.md) | 식민선, 딸 시드, 메시지 버스와 정보 연령, 표준 지침, 자치 사다리 |
| [06 은하·페르미](docs/design/06-galaxy-fermi.md) | 탐지 서명, 위협 달력, 가설 보드, 페르미 시나리오 |
| [07 사회·기술·이벤트](docs/design/07-society-tech-events.md) | 세력, 신뢰·위임, 법령, 기술 트리, 스토리텔러 |
| [08 UX·아트·오디오](docs/design/08-ux-art-audio.md) | 화면 구성과 목업, 알림, 접근성, 아트·사운드 |
| [09 온보딩·제작](docs/design/09-onboarding-production.md) | 첫 1시간, MVP 수직 슬라이스, 마일스톤, 리스크 |
| [용어집](docs/design/glossary.md) | 게임 용어 정의 |
| [시대 0 데이터](docs/design/data/) · [밸런스 시뮬레이터](docs/design/sim/) · [목업](docs/design/mockups/) | JSON 데이터, Python 시뮬레이터(표준 라이브러리만), HTML 목업 |

```bash
cd docs/design
python3 sim/city_balance.py                  # 시드 2061, 추천 정책으로 3년
python3 sim/city_balance.py --monte-carlo 200 # 두 정책 200판 비교 (약 6분)
python3 sim/plot_balance.py                   # images/balance_2061.svg
```

## 컨셉 카탈로그 v0.1 (선택지 모음)

상세 디자인 전 단계에서 고를 수 있던 디자인 옵션과 예시를 모은 문서다.

| 문서 | 내용 |
|---|---|
| [컨셉 카탈로그](docs/concept/README.md) | 컨셉 방향 3가지와 추천안, 디자인 필러, 차별화 포인트, 결정 목록 |
| [지식 DB 범위](docs/concept/01-knowledge-db.md) | 바로 채울 수 있는 데이터·콘텐츠와 신뢰도 |
| [핵심 시스템](docs/concept/02-core-systems.md) | 12개 시스템의 디자인 옵션과 예시 |
| [콘텐츠 샘플](docs/concept/03-content-samples.md) | 도시 부지, 실제 근거리 항성, 기술·모듈·법령·이벤트·종족 |
| [아키텍처·로드맵](docs/concept/04-architecture-roadmap.md) | 시뮬레이션 구조, 데이터 스키마, 엔진 비교, MVP |
| [공식 모음](docs/concept/05-formulas.md) | 게임 공식과 검증된 예시 값 |
| [예제 코드](docs/concept/examples/README.md) | 항성계 생성기, 공식 라이브러리, 근거리 항성 시드 데이터 |
