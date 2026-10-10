# SpaceCity — 시대 0 프로토타입 (Godot)

달 남극 섀클턴 시드 시티를 직접 운영해 보는 첫 실행 가능한 빌드다. **Windows(.exe)** 와 **Android(.apk)** 로 내보낸다.
규칙은 [상세 디자인 03 도시 레이어](../docs/design/03-city-layer.md)와 [밸런스 시뮬레이터](../docs/design/sim/city_balance.py)를 그대로 옮겼다.

## 받아서 실행하기

빌드는 GitHub Actions의 **Game builds (Windows · Android)** 워크플로가 만든다.

| 플랫폼 | 받는 곳 | 실행 |
|---|---|---|
| Windows 10/11 (64비트) | 실행 결과의 Artifacts → `SpaceCity-windows-x86_64`, 또는 `prototype-latest` 프리릴리스 | zip을 풀고 `SpaceCity.exe`를 실행한다 (파일 하나, 설치 없음). OpenGL 3.3을 못 쓰는 PC에서는 엔진이 Direct3D 11 경로(ANGLE, 실행 파일에 내장)로 바꿔 돈다. 코드 서명이 없어서 SmartScreen이 막으면 '추가 정보 → 실행'. F11은 전체 화면 |
| Android 7.0 이상 | Artifacts → `SpaceCity-android`, 또는 `prototype-latest` 프리릴리스의 APK | 휴대폰에서 APK를 열어 설치 ('출처를 알 수 없는 앱' 허용). 디버그 서명이라 스토어 배포용은 아니다 |

워크플로를 수동으로 실행할 때 `publish`를 켜면 `prototype-latest` 프리릴리스에 두 파일이 올라간다. 휴대폰 브라우저로 그 페이지를 열면 APK를 바로 받을 수 있다.

## 하는 일

- 정착민 120명의 산소·CO₂·물·식량·전력·방사선을 1시간 단위로 굴린다. 41일째에 대형 태양 양성자 폭풍이 온다.
- 가운데 화면은 **3D 세계**다. 도시는 구 모양의 달 남극(섀클턴 크레이터 가장자리)에 서 있고, 구글 어스처럼 끌어서 돌리고 확대·축소한다. 계속 줌아웃하면 크레이터 → 달 전체 → 지구와 달 → 태양계 → 25광년 안의 이웃 별까지 끊기지 않고 이어진다. 천체는 실제 궤도 요소로 게임 날짜의 자리에 있고(지구 위상·달의 칭동·토성 고리 그림자), 이름표를 누르면 그 천체로 날아간다.
- **지도** 단추를 누르면 같은 기지가 아이소메트릭 평면 지도로 보인다. 건물마다 모양이 다섯 가지라 같은 모듈이 늘어서도 복사한 것처럼 보이지 않는다. 공사 중이면 비계가 서고 로봇이 가서 일한다. 고장 난 건물에는 붉은 표시가 깜박이고, 화물선·유인선이 오면 착륙선이 내려앉는다. 해는 지평선을 따라 돌며 긴 그림자를 드리우고, 능선 그늘에 들면 밤이 되어 창과 등만 켜진다.
- **건설** 탭의 '짓기'를 누르면 3D 세계(또는 지도)에서 **지을 자리를 고른다**. 유령 건물이 초록이면 놓을 수 있고, 빨강이면 까닭이 함께 뜬다. 90° 돌리기, 같은 기능의 다른 모양 고르기, '빈자리에'(기본 배치에 바로)도 된다. 태양광 타워는 능선의 일조 구역에만 서고, 세운 구역(A 100% · B 85% · C 70%)이 곧 출력이다.
- **도로** 단추로 길을 원하는 곳에 낸다. 점을 차례로 누르면 이어지고, 다른 길에 닿거나 건너면 교차로가 된다. 로버·로봇·화물차가 이 길을 따라 다닌다.
- **연구** 탭에서 연구 순서를 고르고, **전력** 탭에서 절전 문턱을 정한다.
- 대피소가 모자란 대형 폭풍이면 **대피소 추첨** 카드가 뜬다 — 생명과 동의 사이의 선택이다.
- **자동 운영**을 켜면 시드가 문서의 추천 운영대로 짓고 연구한다. 3년(2063년 말)이 되면 보고서가 나온다.
- 앱을 닫거나 내리면 자동 저장한다. Android의 뒤로 가기는 메뉴를 연다.

| 조작 | PC | Android |
|---|---|---|
| 시간 | 정지 · 1× · 3× · 10× 버튼, '다음 사건' | 같은 버튼을 누른다 |
| 3D 세계 | 왼쪽 끌기: 땅을 잡고 돌리기 · 오른쪽 끌기(또는 Shift+끌기): 방향과 기울기 · 휠: 커서 쪽으로 확대·축소 · 더블클릭: 다가가기 · 방향키·Q/E·PgUp/PgDn·+/− · H: 기지로 | 한 손가락 끌기: 돌리기 · 두 손가락 벌리기·모으기: 확대 · 두 손가락 비틀기: 방향 · 두 손가락 위아래: 기울기 · 두 번 누르기: 다가가기 |
| 보기 바꾸기 | 왼쪽 아래 단추 3D · 지도 · 목록, M으로 순환. 3D에서는 − + 기지 · 달 · 지구·달 · 태양계 · 별 단추 | 같은 단추를 누른다 |
| 지도 | 끌어서 옮기기, 휠로 확대, 아래 단추(− + 전체 거주구) | 끌어서 옮기기, 두 손가락으로 확대 |
| 모듈 정보·추가 건설 | 3D·지도의 건물이나 목록의 카드를 클릭 | 건물이나 카드를 누른다 |
| 자리 고르기 | 마우스를 움직여 자리, 클릭으로 짓기 (Shift+클릭: 계속 놓기, Enter), R 돌리기, V 모양, 오른쪽 클릭·Esc 그만두기 | 누른 곳으로 유령이 옮겨 가고 '여기에 짓기' |
| 길 | '도로' 또는 G, 점을 차례로 클릭, 오른쪽 클릭으로 줄 끝내기, '지우기'를 켜고 길을 클릭 | 점을 차례로 누르고 '끝', '지우기' |
| 패널 | 오른쪽 탭, 휠 스크롤 | 탭, 끌어서 스크롤 |

화면은 가로 1280×720을 기준으로 늘어난다 (PC 창 기본 1600×900, 휴대폰은 가로 고정).

## 구조

| 폴더 | 내용 |
|---|---|
| `sim/` | 규칙. 노드·씬을 쓰지 않는 순수 GDScript — `CitySim`(도시), `AutoPolicy`(자동 운영), `PyRandom`(파이썬과 같은 난수), `PyCompat`(파이썬의 반올림·합계 규칙) |
| `ui/` | 화면. 씬 파일 없이 코드로 만든다 — 상단 바, 기지 지도(`base_map`·`base_traffic`, 3D와 함께 쓰는 `base_scene`), 배치(`city_plan`: 건물마다의 자리·방향·모양과 길 그물·길 찾기·배치 규칙·저장, `base_layout`: 기본 배치와 처음 길, `place_tool`: 자리 고르기 도구), 모듈 목록, 일조 예보, 탭 5개, 결정 카드 |
| `ui/world/` | 3D 세계 — `world_view`(화면·입력·이름표), `orbit_cam`(구글 어스식 카메라), `astro`(천체력: 행성·위성 궤도, 달 자전, 별 목록), `moon_surface`(달 구·남극 지형), `city3d`(달 위의 기지), `model_lib`(그림 생성기의 3D 모델), `sky_builder`·`planet_look`(별·은하수·행성), `shaders/` |
| `art/` | 건물·탈것 그림 (SVG + `art.json`), 같은 도형의 3D 모델(`models.json`), 지구 땅 지도(`planets/`). 생성기가 만든 결과라 직접 고치지 않는다 |
| `data/` | `docs/design/data/`(밝은 별·은하 좌표 `sky.json` 포함)와 근거리 항성(`docs/concept/examples/nearby_stars.json`)의 JSON 사본. 단일 출처는 문서 쪽이다 |
| `fonts/` | Pretendard (SIL Open Font License 1.1, `Pretendard-LICENSE.txt`) |
| `tests/` | `parity_dump.gd`(파이썬과 비교할 일별 상태), `smoke_test.gd`(화면을 띄워 자동 운영으로 3년 보고서까지 돌리기, 지도·탈것·3D 카메라·자리 고르기·길 점검), `screenshots.gd`·`map_shots.gd`·`world_shots.gd`(화면 캡처 — 3D는 기지에서 이웃 별까지, 자리 고르기와 길 20장) |
| `tools/` | `parity_check.py`, `sync_data.py`, `art/`(그림 생성기) |

## 시험

```bash
godot --headless --path game --import                         # 처음 한 번 (스크립트 클래스 등록)
python3 game/tools/sync_data.py                                # game/data가 문서 데이터와 같은가
python3 game/tools/art/make_art.py --check                      # game/art가 그림 생성기의 결과와 같은가
python3 game/tools/parity_check.py --godot godot               # 파이썬 시뮬레이터와 하루 단위로 같은 결과인가
godot --headless --path game --script res://tests/smoke_test.gd
```

`parity_check.py`는 같은 시드·같은 자동 운영으로 두 시뮬레이터를 3년씩 돌려 날마다 40여 개 값을 비교한다.
이를 위해 GDScript 쪽은 파이썬의 메르센 트위스터(시드 방식 포함), 짝수 쪽 반올림, 3.12 이후의 보정 합(`sum()`)을 그대로 따른다.
규칙을 고칠 때는 파이썬 시뮬레이터와 이 코드를 함께 고치고, 이 시험으로 확인한다.

## 그림

`tools/art/`의 파이썬 생성기(표준 라이브러리만)가 모든 건물·탈것을 3차원 도형으로 적어 SVG로 그린다 — 빛·축척·투영이 같도록.
규칙은 [디자인 08 §7](../docs/design/08-ux-art-audio.md)에 있다.

| 파일 | 내용 |
|---|---|
| `iso.py` | 투영(정사영 30°, 1 m = 8 px), 빛, 도형 — 상자·원기둥·원뿔·구·돔·판·막대, 창(밤 불빛 레이어), 접지 그림자. 그리는 도형을 3차원으로도 기록해서 같은 설계가 3D 모델이 된다 (몸체·유리·불빛 면) |
| `buildings.py` | 시대 0 건물 29종의 기본 설계, 피복된 거주 모듈, 공사 비계 3종 |
| `building_variants.py` | 건물마다 모양이 다른 설계 4가지 더 (`<id>_v1.svg`~`_v4.svg`). 기능은 같고, 지도는 자리마다 하나를 고른다 |
| `vehicles.py` | 탈것 14종과 우주비행사. 지상 탈것은 네 방향 |
| `make_art.py` | `game/art/`에 SVG·`art.json`·`models.json`(3D 모델)·지구 땅 지도를 쓰고, 새 그림에는 Godot 가져오기 설정(2배 래스터화, 밉맵)을 둔다 |
| `planets.py` | 지구 땅 지도(대륙·만년설·사막 다각형을 래스터화한 PNG) |
| `contact_sheet.gd` | 여러 SVG를 게임과 같은 래스터라이저로 한 장에 모아 본다 |
| `model_sheet.gd` | 3D 모델을 게임과 같은 셰이더로 그려 한 장에 모아 본다 (화면이 필요하다 — `xvfb-run`) |

```bash
python3 game/tools/art/make_art.py                  # 그림을 다시 만든다
godot --headless --path game --import               # 새 그림을 가져온다
godot --headless --path game --script res://tools/art/contact_sheet.gd -- --out sheet.png --scale 2 game/art/buildings/*.svg
xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --script res://tests/map_shots.gd -- --out /tmp/shots
xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --script res://tests/world_shots.gd -- --out /tmp/world
xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 --script res://tools/art/model_sheet.gd -- --out /tmp/models.png all
```

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
| 배치 | 일조 구역(타워만), 영구음영(얼음 채굴기만), 착륙장 둘레 30 m, 원자로–거주 60 m, 겹침 금지. 자리를 고르지 않은 건물은 기본 배치의 빈자리 ([03 §9](../docs/design/03-city-layer.md#9-건설과-로봇)) |
| 길 | 자재 없이 바로 깔린다. 다 지은 건물은 옮기거나 허물 수 없다 |
| 저장 | 배치 계획(건물 자리·방향·모양, 길)이 게임과 함께 저장된다. 계획이 없는 옛 저장은 기본 배치로 채운다 |
| 패배 | 신뢰 10 미만 1년 → 시드 정지, 정착민 0명 → 절멸 |
| 위급 정지 | 산소·식량 비축 3일 미만, 사망, 대피소 추첨에서 자동으로 멈춘다 |

## 아직 없는 것

평의회·법령·세력, 이름 있는 정착민, 사운드, 영어, 건물 단면 보기, 다 지은 건물 옮기기·허물기, 시대 1 이후 레이어 (화성·타이탄·금성 비행체와 우주선 그림은 이미 있다). 순서는 [09 온보딩·제작](../docs/design/09-onboarding-production.md)의 마일스톤을 따른다.
