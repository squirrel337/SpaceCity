class_name Sound
extends Node
## 소리 — 효과음과 환경음을 코드로 합성한다 (소리 파일이 없다). main이 하나 만들어 둔다 (Sound.inst).
## 효과음: 단추(딸깍·전환), 알림(좋음·정보·경고·위급·사망), 짓기·헐기·안 됨, 결정 카드(이야기·대피소 경보·보고서),
##   수송선 출발·도착, 연구 완료. 같은 소리가 60 ms 안에 겹치면 한 번만 낸다.
## 환경음: 고른 식민지의 천체마다 6초 고리 — 달(기지의 웅웅거림과 환기), 화성(모래바람), 타이탄(짙은 바람), 지구(바깥 소리),
##   우주(항로 지도의 낮은 울림). 사인파의 주파수는 1/6 Hz의 배수라 고리가 이어지고, 잡음은 끝과 처음을 겹쳐 잇는다.
## 처음에 프레임마다 나눠 만든다 (한 프레임에 MAX_US까지) — 다 만들기 전에는 그 소리를 건너뛴다.
## 고른 도시가 절전하면(축전 20% 아래) 환경음을 9 dB 낮춘다 (main).
## 음량: 설정의 소리 (전체·효과음·환경음, 끄기 — user://settings.cfg) → 버스 Master · SFX · Ambient

const RATE := 22050                 # 효과음
const AMB_RATE := 16000             # 환경음
const AMB_SECONDS := 6.0
const MAX_US := 2500                # 한 프레임에 만드는 데 쓰는 시간
const CHUNK := 1024
const POOL := 6
const SFX_PEAK := 0.8
const AMB_PEAK := 0.45
const SFX := {
	"click": 0.06, "toggle": 0.13, "build": 0.48, "demolish": 0.55, "deny": 0.3, "good": 0.62, "info": 0.36, "warn": 0.52,
	"critical": 0.95, "death": 1.5, "alarm": 1.25, "event": 0.9, "milestone": 1.5, "launch": 1.7, "arrive": 0.65, "research": 0.62,
}
const AMBIENT := ["moon", "mars", "titan", "earth", "space"]
## 천체 → 환경음 (없는 천체는 달처럼 — 여압된 기지 안)
const AMB_OF := {"moon": "moon", "mercury": "moon", "ceres": "moon", "callisto": "moon", "mars": "mars", "titan": "titan",
	"earth": "earth", "space": "space"}
## 알림 종류 → 효과음
const KIND_FX := {"good": "good", "info": "info", "warn": "warn", "critical": "critical", "death": "death", "build": "build"}

static var inst: Sound

var played := {}                    # 소리 → 낸 횟수 (시험·확인용)
var _streams := {}                  # 소리 → AudioStreamWAV
var _jobs: Array = []               # 만드는 중 [{name, n, rate, loop, buf, i, st}]
var _players: Array = []
var _amb: AudioStreamPlayer
var _amb_name := ""
var _want_amb := ""
var _amb_db := 0.0                  # 환경음 크기 (절전이면 낮춘다 — set_level)
var _level_tw: Tween
var _last_ms := {}


func _init() -> void:
	name = "Sound"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	inst = self
	_bus("SFX")
	_bus("Ambient")
	for _i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Ambient"
	add_child(_amb)
	apply_volumes()
	for k in SFX:
		_queue(String(k))
	get_tree().node_added.connect(_hook)
	_hook_tree(get_tree().root)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i


## 설정의 음량을 버스에 (0~1 → dB)
static func apply_volumes() -> void:
	var mute := bool(Settings.value("audio/mute", false))
	for spec in [["Master", "audio/master", 0.8], ["SFX", "audio/sfx", 0.8], ["Ambient", "audio/ambient", 0.5]]:
		var i := _bus(String(spec[0]))
		var v := clampf(float(Settings.value(String(spec[1]), spec[2])), 0.0, 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001 or (mute and String(spec[0]) == "Master"))


# ── 내기 ────────────────────────────────────────────────────────
## 효과음 하나 (inst가 없으면 아무것도 않는다)
static func fx(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if inst != null:
		inst.play(sfx_name, volume_db, pitch)


## 알림 종류의 효과음
static func note(kind: String) -> void:
	if KIND_FX.has(kind):
		fx(String(KIND_FX[kind]))


static func ambient(body: String) -> void:
	if inst != null:
		inst.set_ambient(String(AMB_OF.get(body, "moon")))


func play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sfx_name, -1000)) < 60:
		return
	_last_ms[sfx_name] = now
	played[sfx_name] = int(played.get(sfx_name, 0)) + 1
	var st: AudioStreamWAV = _streams.get(sfx_name)
	if st == null:
		return
	var pick: AudioStreamPlayer = null
	for p in _players:
		if not (p as AudioStreamPlayer).playing:
			pick = p
			break
	if pick == null:
		pick = _players[0]
		_players.push_back(_players.pop_front())
	pick.stream = st
	pick.volume_db = volume_db
	pick.pitch_scale = pitch
	pick.play()


func set_ambient(amb: String) -> void:
	_want_amb = amb
	if amb == _amb_name and _amb.playing:
		return
	var key := "amb_" + amb
	if not _streams.has(key):
		_queue(key, true)
		return
	_amb_name = amb
	var tw := create_tween()
	if _amb.playing:
		tw.tween_property(_amb, "volume_db", -40.0, 0.6)
	tw.tween_callback(func():
		_amb.stream = _streams[key]
		_amb.volume_db = -40.0
		_amb.play())
	tw.tween_property(_amb, "volume_db", _amb_db, 1.2)


## 환경음 크기 (dB): 기지가 절전하면 웅웅거림이 줄어 '어둠'을 귀로 느낀다
static func level(db: float) -> void:
	if inst != null:
		inst.set_level(db)


func set_level(db: float) -> void:
	if absf(db - _amb_db) < 0.5:
		return
	_amb_db = db
	if _amb.playing:
		if _level_tw != null and _level_tw.is_valid():
			_level_tw.kill()
		_level_tw = create_tween()
		_level_tw.tween_property(_amb, "volume_db", db, 1.5)


## 단추를 누르면 딸깍 (켜고 끄는 단추는 전환 소리). set_meta("silent", true)인 단추는 조용히
func _hook(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sound_hooked"):
		n.set_meta("sound_hooked", true)
		var b := n as BaseButton
		b.pressed.connect(func():
			if not b.has_meta("silent"):
				play("toggle" if b.toggle_mode else "click", -4.0))


func _hook_tree(n: Node) -> void:
	_hook(n)
	for c in n.get_children():
		_hook_tree(c)


# ── 만들기 ──────────────────────────────────────────────────────
func ready_count() -> int:
	return _streams.size()


func is_ready(sfx_name: String) -> bool:
	return _streams.has(sfx_name)


func _queue(key: String, first := false) -> void:
	for j in _jobs:
		if String(j["name"]) == key:
			return
	if _streams.has(key):
		return
	var amb := key.begins_with("amb_")
	var rate := AMB_RATE if amb else RATE
	var secs := AMB_SECONDS if amb else float(SFX.get(key, 0.3))
	var n := int(secs * rate)
	var fade := int(0.4 * rate) if amb else 0
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var job := {"name": key, "n": n, "fade": fade, "rate": rate, "loop": amb, "buf": buf, "i": 0,
		"st": {"seed": absi(key.hash()) % 2147483647 + 1, "lp": 0.0, "lp2": 0.0, "lp3": 0.0, "ph": 0.0, "ph2": 0.0}}
	if first:
		_jobs.push_front(job)
	else:
		_jobs.append(job)


func _process(_delta: float) -> void:
	if _jobs.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	while not _jobs.is_empty() and Time.get_ticks_usec() - t0 < MAX_US:
		_step_job()


## 남은 소리를 모두 지금 만든다 (시험)
func finish_all() -> void:
	for a in AMBIENT:
		_queue("amb_" + String(a))
	while not _jobs.is_empty():
		_step_job()


func _step_job() -> void:
	var job: Dictionary = _jobs[0]
	var total := int(job["n"]) + int(job["fade"])
	var i0 := int(job["i"])
	var i1 := mini(i0 + CHUNK, total)
	_fill(job, i0, i1)
	job["i"] = i1
	if i1 >= total:
		_jobs.pop_front()
		_finish(job)


func _finish(job: Dictionary) -> void:
	var buf: PackedFloat32Array = job["buf"]
	var n := int(job["n"])
	var fade := int(job["fade"])
	# 고리: 끝 다음 fade만큼을 처음에 겹친다 (잡음·필터가 끊기지 않게)
	for i in fade:
		var w := float(i) / float(fade)
		buf[i] = buf[i] * w + buf[n + i] * (1.0 - w)
	# 크기 맞추기: 환경음은 봉우리를 AMB_PEAK로 (우주는 더 낮게), 효과음은 SFX_PEAK를 넘지 않게
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var key := String(job["name"])
	var want := (AMB_PEAK * (0.6 if key == "amb_space" else 1.0)) if bool(job["loop"]) else minf(peak, SFX_PEAK)
	var k := want / peak if peak > 1e-6 else 1.0
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(clampf(buf[i] * k, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = int(job["rate"])
	st.stereo = false
	st.data = pcm
	if bool(job["loop"]):
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = n
	_streams[String(job["name"])] = st
	if String(job["name"]) == "amb_" + _want_amb:
		set_ambient(_want_amb)


## 엔벌로프: a초에 올라 d초마다 e배로 줄어든다
static func _env(t: float, a: float, d: float) -> float:
	if t < 0.0:
		return 0.0
	return t / a if t < a else exp(-(t - a) / d)


static func _tone(t: float, f: float) -> float:
	return sin(TAU * f * t)


## 잡음 (선형 합동 — 소리마다 같은 씨앗이라 늘 같은 소리)
static func _noise(st: Dictionary) -> float:
	var s := (int(st["seed"]) * 1103515245 + 12345) & 0x7fffffff
	st["seed"] = s
	return float(s) / 1073741824.0 - 1.0


func _fill(job: Dictionary, i0: int, i1: int) -> void:
	# Packed 배열은 값처럼 복사된다 — 사전의 참조를 잠시 떼어 내 제자리에 쓰고 다시 넣는다
	var buf: PackedFloat32Array = job["buf"]
	job["buf"] = PackedFloat32Array()
	var rate := float(job["rate"])
	var st: Dictionary = job["st"]
	var key := String(job["name"])
	for i in range(i0, i1):
		var t := float(i) / rate
		var v := 0.0
		match key:
			"click":
				v = (_tone(t, 1800.0) * 0.8 + _noise(st) * 0.2) * _env(t, 0.001, 0.012) * 0.35
			"toggle":
				v = (_tone(t, 1300.0) * _env(t, 0.001, 0.014) + _tone(t, 1950.0) * _env(t - 0.05, 0.001, 0.016)) * 0.3
			"build":
				var tri1 := asin(sin(TAU * 659.25 * t)) * 0.64
				var tri2 := asin(sin(TAU * 987.77 * t)) * 0.64
				v = (tri1 * _env(t, 0.005, 0.11) + tri2 * _env(t - 0.12, 0.005, 0.14)) * 0.36
			"demolish":
				var cut := 0.25 * exp(-t / 0.15) + 0.02
				st["lp"] = float(st["lp"]) + cut * (_noise(st) - float(st["lp"]))
				v = (float(st["lp"]) * 2.2 * _env(t, 0.004, 0.13) + _tone(t, 55.0) * _env(t, 0.004, 0.09)) * 0.5
			"deny":
				var sq := sin(TAU * 196.0 * t) + sin(TAU * 588.0 * t) / 3.0
				v = sq * (_env(t, 0.004, 0.05) * (1.0 if t < 0.11 else 0.0) + _env(t - 0.14, 0.004, 0.05)) * 0.28
			"good":
				for k in 3:
					var f: float = [523.25, 659.25, 783.99][k]
					var e := _env(t - 0.09 * k, 0.004, 0.2)
					v += (_tone(t, f) + 0.3 * _tone(t, f * 2.0)) * e
				v *= 0.22
			"info":
				v = (_tone(t, 880.0) + 0.2 * _tone(t, 1760.0)) * _env(t, 0.004, 0.09) * 0.24
			"warn":
				v = (_tone(t, 739.99) * _env(t, 0.005, 0.08) * (1.0 if t < 0.2 else 0.0)
					+ _tone(t, 554.37) * _env(t - 0.2, 0.005, 0.12)) * 0.3
			"critical":
				var hi := int(floor(t / 0.15)) % 2 == 0
				var f2 := 880.0 if hi else 660.0
				var sq2 := sin(TAU * f2 * t) + sin(TAU * 3.0 * f2 * t) / 4.0
				v = sq2 * minf(1.0, t / 0.01) * clampf((0.95 - t) / 0.2, 0.0, 1.0) * 0.22
			"death":
				v = (_tone(t, 220.0) + 0.8 * _tone(t, 261.63) + 0.25 * _tone(t, 110.0)) * _env(t, 0.06, 0.55) * 0.22
			"alarm":
				var f3 := 600.0 + 300.0 * sin(TAU * 1.6 * t)
				st["ph"] = fmod(float(st["ph"]) + f3 / rate, 1.0)
				v = sin(TAU * float(st["ph"])) * minf(1.0, t / 0.05) * clampf((1.25 - t) / 0.25, 0.0, 1.0) * 0.26
			"event":
				var f4 := 660.0
				v = (_tone(t, f4) * _env(t, 0.003, 0.5) + 0.5 * _tone(t, f4 * 2.76) * _env(t, 0.003, 0.22)
					+ 0.25 * _tone(t, f4 * 5.4) * _env(t, 0.003, 0.1)) * 0.22
			"milestone":
				var vib := 1.0 + 0.003 * sin(TAU * 5.0 * t)
				for f5 in [261.63, 329.63, 392.0, 523.25]:
					v += _tone(t, f5 * vib)
				v *= _env(t, 0.15, 0.6) * 0.12
			"launch":
				var cut2 := 0.01 + 0.08 * minf(1.0, t / 1.2)
				st["lp"] = float(st["lp"]) + cut2 * (_noise(st) - float(st["lp"]))
				st["lp2"] = float(st["lp2"]) + cut2 * (float(st["lp"]) - float(st["lp2"]))
				v = (float(st["lp2"]) * 5.0 + 0.4 * _tone(t, 45.0)) * _env(t, 0.35, 0.55) * 0.55
			"arrive":
				v = (_tone(t, 783.99) * _env(t, 0.004, 0.12) * (1.0 if t < 0.16 else 0.0) + _tone(t, 587.33) * _env(t - 0.16, 0.004, 0.18)) * 0.26
			"research":
				for k2 in 5:
					var f6: float = [1046.5, 1174.66, 1318.51, 1567.98, 1760.0][k2]
					v += _tone(t, f6) * _env(t - 0.07 * k2, 0.002, 0.07)
				v *= 0.16
			"amb_moon":
				st["lp"] = float(st["lp"]) + 0.02 * (_noise(st) - float(st["lp"]))
				var mod := 1.0 + 0.15 * sin(TAU * t / AMB_SECONDS)
				v = (0.05 * _tone(t, 60.0) + 0.03 * _tone(t, 120.0) + 0.012 * _tone(t, 180.0)) + float(st["lp"]) * 1.4 * mod
			"amb_mars":
				st["lp"] = float(st["lp"]) + 0.03 * (_noise(st) - float(st["lp"]))
				st["lp2"] = float(st["lp2"]) + 0.03 * (float(st["lp"]) - float(st["lp2"]))
				var gust := 0.55 + 0.35 * sin(TAU * t / AMB_SECONDS) + 0.18 * sin(TAU * 2.0 * t / AMB_SECONDS + 1.0)
				v = float(st["lp2"]) * 5.5 * gust + 0.015 * _tone(t, 60.0)
			"amb_titan":
				st["lp"] = float(st["lp"]) + 0.008 * (_noise(st) - float(st["lp"]))
				st["lp2"] = float(st["lp2"]) + 0.008 * (float(st["lp"]) - float(st["lp2"]))
				var swell := 0.6 + 0.4 * sin(TAU * t / AMB_SECONDS)
				v = float(st["lp2"]) * 16.0 * swell + 0.03 * _tone(t, 40.0)
			"amb_earth":
				st["lp"] = float(st["lp"]) + 0.05 * (_noise(st) - float(st["lp"]))
				st["lp3"] = float(st["lp3"]) + 0.004 * (_noise(st) - float(st["lp3"]))
				v = float(st["lp"]) * 0.7 * (0.8 + 0.2 * sin(TAU * t / AMB_SECONDS)) + float(st["lp3"]) * 6.0
			"amb_space":
				v = (0.04 * _tone(t, 55.0) + 0.03 * _tone(t, 82.5) + 0.02 * _tone(t, 110.0 + 1.0 / AMB_SECONDS)) \
					* (0.8 + 0.2 * sin(TAU * t / AMB_SECONDS))
		buf[i] = v
	job["buf"] = buf
