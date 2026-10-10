# SpaceCity — 시대 0 프로토타입 (Godot)

달 남극 섀클턴 시드 시티를 직접 운영해 보는 첫 실행 가능한 빌드다. **Windows(.exe)** 와 **Android(.apk)** 로 내보낸다.
규칙은 [상세 디자인 03 도시 레이어](../docs/design/03-city-layer.md)와 [밸런스 시뮬레이터](../docs/design/sim/city_balance.py)를 그대로 옮겼다.

## 받아서 실행하기

빌드는 GitHub Actions의 **Game builds (Windows · Android)** 워크플로가 만든다.

| 플랫폼 | 받는 곳 | 실행 |
|---|---|---|
| Windows 10/11 (64비트) | 실행 결과의 Artifacts → `SpaceCity-windows-x86_64`, 또는 `prototype-latest` 프리릴리스 | zip을 풀고 `SpaceCity.exe`. 코드 서명이 없어서 SmartScreen이 막으면 '추가 정보 → 실행' |
| Android 7.0 이상 | Artifacts → `SpaceCity-android`, 또는 `prototype-latest` 프리릴리스의 APK | 휴대폰에서 APK를 열어 설치 ('출처를 알 수 없는 앱' 허용). 디버그 서명이라 스토어 배포용은 아니다 |

워크플로를 수동으로 실행할 때 `publish`를 켜면 `prototype-latest` 프리릴리스에 두 파일이 올라간다. 휴대폰 브라우저로 그 페이지를 열면 APK를 바로 받을 수 있다.

## 하는 일

- 정착민 120명의 산소·CO₂·물·식량·전력·방사선을 1시간 단위로 굴린다. 41일째에 대형 태양 양성자 폭풍이 온다.
- **건설** 탭에서 모듈을 대기열에 넣고, **연구** 탭에서 연구 순서를 고르고, **전력** 탭에서 절전 문턱을 정한다.
- 대피소가 모자란 대형 폭풍이면 **대피소 추첨** 카드가 뜬다 — 생명과 동의 사이의 선택이다.
- **자동 운영**을 켜면 시드가 문서의 추천 운영대로 짓고 연구한다. 3년(2063년 말)이 되면 보고서가 나온다.
- 앱을 닫거나 내리면 자동 저장한다. Android의 뒤로 가기는 메뉴를 연다.

| 조작 | PC | Android |
|---|---|---|
| 시간 | 정지 · 1× · 3× · 10× 버튼, '다음 사건' | 같은 버튼을 누른다 |
| 모듈 정보·추가 건설 | 기지 개요도의 카드를 클릭 | 카드를 누른다 |
| 패널 | 오른쪽 탭, 휠 스크롤 | 탭, 끌어서 스크롤 |

화면은 가로 1280×720을 기준으로 늘어난다 (PC 창 기본 1600×900, 휴대폰은 가로 고정).

## 구조

| 폴더 | 내용 |
|---|---|
| `sim/` | 규칙. 노드·씬을 쓰지 않는 순수 GDScript — `CitySim`(도시), `AutoPolicy`(자동 운영), `PyRandom`(파이썬과 같은 난수), `PyCompat`(파이썬의 반올림·합계 규칙) |
| `ui/` | 화면. 씬 파일 없이 코드로 만든다 — 상단 바, 기지 개요도, 일조 예보, 탭 5개, 결정 카드 |
| `data/` | `docs/design/data/`의 JSON 사본. 단일 출처는 문서 쪽이다 |
| `fonts/` | Pretendard (SIL Open Font License 1.1, `Pretendard-LICENSE.txt`) |
| `tests/` | `parity_dump.gd`(파이썬과 비교할 일별 상태), `smoke_test.gd`(화면을 띄워 60일 돌리기) |
| `tools/` | `parity_check.py`, `sync_data.py` |

## 시험

```bash
godot --headless --path game --import                         # 처음 한 번 (스크립트 클래스 등록)
python3 game/tools/sync_data.py                                # game/data가 문서 데이터와 같은가
python3 game/tools/parity_check.py --godot godot               # 파이썬 시뮬레이터와 하루 단위로 같은 결과인가
godot --headless --path game --script res://tests/smoke_test.gd
```

`parity_check.py`는 같은 시드·같은 자동 운영으로 두 시뮬레이터를 3년씩 돌려 날마다 40여 개 값을 비교한다.
이를 위해 GDScript 쪽은 파이썬의 메르센 트위스터(시드 방식 포함), 짝수 쪽 반올림, 3.12 이후의 보정 합(`sum()`)을 그대로 따른다.
규칙을 고칠 때는 파이썬 시뮬레이터와 이 코드를 함께 고치고, 이 시험으로 확인한다.

## 직접 내보내기

Godot 4.7.2와 같은 버전의 내보내기 템플릿이 필요하다.

```bash
godot --headless --path game --export-release "Windows Desktop" "$PWD/build/windows/SpaceCity.exe"
# Android: ANDROID_HOME(빌드 도구 28 이상, platform-tools)과 JAVA_HOME(JDK 17 이상), 디버그 키스토어가 필요하다
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=~/debug.keystore GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
godot --headless --path game --export-debug "Android" "$PWD/build/android/SpaceCity.apk"
```

## 프로토타입 규칙 — 디자인 문서에 아직 없는 것

| 항목 | 규칙 |
|---|---|
| 대피소 추첨 | 필수 인력 먼저: 신뢰 −2 · 추첨: 기본 · 평의회에 맡김: 신뢰 +3, 결정이 늦어 대피소 안 선량 2% → 10% |
| 플레이어 건설 | 부품 비축 40 규칙(자동 운영의 안전 재고)을 강제하지 않는다. 40 아래로 내려가면 경고만 한다 |
| 대기열 취소 | 손대지 않은 일이면 자재를 모두, 시작한 일이면 절반을 돌려받는다 |
| 패배 | 신뢰 10 미만 1년 → 시드 정지, 정착민 0명 → 절멸 |
| 위급 정지 | 산소·식량 비축 3일 미만, 사망, 대피소 추첨에서 자동으로 멈춘다 |

## 아직 없는 것

평의회·법령·세력, 이름 있는 정착민, 사운드, 영어, 아이소메트릭 도시 화면, 시대 1 이후 레이어. 순서는 [09 온보딩·제작](../docs/design/09-onboarding-production.md)의 마일스톤을 따른다.
