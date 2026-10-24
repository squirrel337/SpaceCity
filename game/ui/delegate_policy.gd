class_name DelegatePolicy
extends AutoPolicy
## 위임 — 살림 건설만 시드에게 맡긴 직접 운영 도시의 정책 (CityAuto). 추천 운영의 짓기(decide)는 그대로 하되, 플레이어가 정한
## 연구 차례·절전 문턱·배급·특급 보급 같은 운영 방침은 건드리지 않는다 (configure를 하지 않는다).
## 이름이 비어 있어 시뮬레이션 저장에는 자동 운영으로 남지 않는다 — 불러올 때 위임 상태(c["delegate"])로 다시 붙인다


func _init() -> void:
	super("good")
	name = ""


func configure(_sim: CitySim) -> void:
	pass
