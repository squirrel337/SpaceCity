class_name Settings
extends RefCounted
## 사용자 설정 (user://settings.cfg) — 그래픽 품질, 지도에 보일 것, 조작. 게임 저장과 따로 남는다.
##
## 그래픽 품질: "auto"(GPU를 보고 고르고, 프레임이 느려지면 한 단계씩 낮춘다) 또는 low · medium · high · ultra.
## 단계마다 화면 해상도 상한, 안티앨리어싱, 그림자, 대도시 건물 수, 지형 격자, 굽기 해상도가 정해진다 (PRESETS).

const PATH := "user://settings.cfg"
const LEVELS := ["low", "medium", "high", "ultra"]
const LEVEL_NAMES := {"auto": "자동", "low": "낮음", "medium": "보통", "high": "높음", "ultra": "최고"}
## 단계마다: render_px(3D 화면의 픽셀 상한), msaa(0·2·4), shadow_splits(0이면 끔), shadow_size, metro_budget(대도시
## 건물 수), metro_keep(동시에 지어 두는 대도시), patch_segs(지형 조각 둘레 칸), bake(천체 겉모습 굽기), stars, aniso
const PRESETS := {
	"low": {"render_px": 0.9e6, "msaa": 0, "shadow_splits": 2, "shadow_size": 2048, "metro_budget": 6000, "metro_keep": 1,
		"patch_segs": 128, "bake": 512, "stars": 3000, "aniso": 2},
	"medium": {"render_px": 1.4e6, "msaa": 0, "shadow_splits": 2, "shadow_size": 2048, "metro_budget": 12000,
		"metro_keep": 1, "patch_segs": 160, "bake": 512, "stars": 4200, "aniso": 4},
	"high": {"render_px": 2.4e6, "msaa": 2, "shadow_splits": 4, "shadow_size": 4096, "metro_budget": 26000,
		"metro_keep": 2, "patch_segs": 192, "bake": 1024, "stars": 5200, "aniso": 8},
	"ultra": {"render_px": 4.2e6, "msaa": 4, "shadow_splits": 4, "shadow_size": 4096, "metro_budget": 52000,
		"metro_keep": 3, "patch_segs": 256, "bake": 2048, "stars": 7000, "aniso": 16},
}

static var _cfg: ConfigFile
static var _gpu := {}
static var _auto_level := ""          # 자동일 때 지금 쓰는 단계 (프레임 시간을 보고 내려간다)
static var _auto_cap := 99            # 자동: 이 게임에서 느렸던 단계 바로 아래 (그 위로는 다시 올리지 않는다)


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)


static func value(key: String, default: Variant) -> Variant:
	_load()
	var parts := key.split("/", true, 1)
	return _cfg.get_value(parts[0], parts[1] if parts.size() > 1 else "", default)


static func set_value(key: String, v: Variant) -> void:
	_load()
	var parts := key.split("/", true, 1)
	_cfg.set_value(parts[0], parts[1] if parts.size() > 1 else "", v)
	_cfg.save(PATH)


# ── GPU ────────────────────────────────────────────────────────
## 그래픽 장치: {name, vendor, type, kind ("discrete"·"integrated"·"mobile"·"cpu"·"unknown"), level(추천 단계)}
static func gpu() -> Dictionary:
	if not _gpu.is_empty():
		return _gpu
	var name := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var t := int(RenderingServer.get_video_adapter_type())
	_gpu = classify(name, vendor, t, OS.has_feature("mobile"))
	return _gpu


## 이름·종류로 장치를 나누고 추천 단계를 고른다 (시험할 수 있게 따로)
static func classify(name: String, vendor: String, t: int, mobile: bool) -> Dictionary:
	var n := (name + " " + vendor).to_lower()
	var kind := "unknown"
	if t == RenderingDevice.DEVICE_TYPE_CPU or n.contains("llvmpipe") or n.contains("softpipe") or n.contains("swiftshader") \
			or n.contains("lavapipe") or n.contains("microsoft basic render"):
		kind = "cpu"
	elif mobile or n.contains("adreno") or n.contains("mali") or n.contains("powervr") or n.contains("xclipse") \
			or n.contains("immortalis"):
		kind = "mobile"
	elif t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU or n.contains("geforce") or n.contains("rtx") or n.contains("gtx") \
			or n.contains("quadro") or n.contains("radeon rx") or n.contains("radeon pro") or n.contains("arc a") \
			or n.contains("arc b") or (n.contains("nvidia") and not n.contains("tegra")):
		kind = "discrete"
	elif t == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or n.contains("intel") or n.contains("radeon") or n.contains("apple") \
			or n.contains("iris") or n.contains("uhd"):
		kind = "integrated"
	var level := "medium"
	match kind:
		"cpu":
			level = "low"
		"mobile":
			level = "medium" if (n.contains("adreno (tm) 7") or n.contains("adreno 7") or n.contains("immortalis") \
				or n.contains("xclipse")) else "low"
		"discrete":
			level = "ultra" if (n.contains("rtx 40") or n.contains("rtx 50") or n.contains("rtx 30") or n.contains("rx 7") \
				or n.contains("rx 9")) else "high"
		"integrated":
			level = "high" if (n.contains("apple m") or n.contains("radeon 7") or n.contains("radeon 8") \
				or n.contains("arc")) else "medium"
	return {"name": name, "vendor": vendor, "type": t, "kind": kind, "level": level}


static func kind_name(kind: String) -> String:
	return {"discrete": "외장 GPU", "integrated": "내장 GPU", "mobile": "휴대기기 GPU", "cpu": "GPU 없음 (CPU 렌더링)"}.get(
		kind, "알 수 없는 장치")


# ── 품질 ────────────────────────────────────────────────────────
## 고른 품질 ("auto" 또는 단계)
static func preset() -> String:
	var p := String(value("graphics/preset", "auto"))
	return p if p == "auto" or PRESETS.has(p) else "auto"


static func set_preset(p: String) -> void:
	set_value("graphics/preset", p)
	_auto_level = ""
	_auto_cap = 99


## 지금 쓰는 단계 (자동이면 GPU 추천에서 시작해 느려지면 내려간 단계)
static func level() -> String:
	var p := preset()
	if p != "auto":
		return p
	if _auto_level == "":
		_auto_level = String(gpu()["level"])
	return _auto_level


## 자동 품질: 한 단계 내리거나(dir < 0) 올린다 (GPU 추천보다 높이지는 않는다). 바뀌었으면 true
static func step_auto(dir: int) -> bool:
	if preset() != "auto":
		return false
	var i := LEVELS.find(level())
	if dir < 0:
		_auto_cap = i - 1
	var top := mini(LEVELS.find(String(gpu()["level"])), _auto_cap)
	var j := clampi(i + dir, 0, maxi(top, 0))
	if j == i:
		return false
	_auto_level = LEVELS[j]
	return true


static func q(key: String) -> Variant:
	return PRESETS[level()][key]


## 굽기 크기: lo·mid·hi (천체 겉모습 정육면체 면), keep (곱게 둘 천체 수), cap (도시 둘레 지역 지도), cube (달 정육면체)
static func bake_sizes() -> Dictionary:
	match level():
		"low":
			return {"lo": 128, "mid": 256, "hi": 512, "keep": 1, "cap": 512, "cube": 512}
		"medium":
			return {"lo": 128, "mid": 512, "hi": 512, "keep": 1, "cap": 1024, "cube": 512}
		"ultra":
			return {"lo": 256, "mid": 1024, "hi": 2048, "keep": 3, "cap": 2048, "cube": 2048}
	return {"lo": 256, "mid": 512, "hi": 1024, "keep": 2, "cap": 2048, "cube": 1024}


# ── 지도·조작 ───────────────────────────────────────────────────
static func show_routes() -> bool:
	return bool(value("map/routes", true))


static func show_orbits() -> bool:
	return bool(value("map/orbits", true))


static func show_perf() -> bool:
	return bool(value("debug/perf", false))
