class_name Music
extends Node
## 배경 음악 — 코드로 합성한다 (음악 파일이 없다). main이 하나 만들어 둔다 (Music.inst).
## 고리 셋을 처음에 뒤 스레드에서 한 번 만들어 둔다 (도시 → 항로 지도 → 긴장 차례 — 다 되기 전에는 조용하다):
##   city    도시: 72 BPM 다장조, Cmaj7 – Am7 – Fmaj7 – G6 (두 마디씩). 현악 패드(살짝 어긋난 두 줄)와 성긴 피아노 선율, 낮은 피아노 베이스
##   map     항로 지도: 104 BPM 가단조, Am – F – C – G. 16분음 신스 아르페지오(점8분 메아리), 8분음 베이스, 옅은 패드
##   tension 폭풍·정전·위급: 84 BPM 라 단조, 낮은 지속음(레·라, 느린 떨림), 8분음 오스티나토, 마디 머리의 낮은 북, 네 마디마다 높은 불협 현악
## 표(2048칸)를 한 번 만들어 위상으로 읽고 엔벌로프를 곱해 버퍼에 더한다. 메아리·잔향은 고리 끝이 처음으로 이어지게 둥글게 감는다.
## 분위기(main): 위급(대피소 추첨·정전 — 축전 15% 아래·산소나 식량 3일 아래·먼지 폭풍)이면 긴장, 항로 지도나 먼 우주면 항로 지도,
## 아니면 도시. 바뀌면 2.5초에 걸쳐 엇갈려 바꾼다. 음량: 설정의 '음악' (audio/music) → 버스 Music

const RATE := 22050
const TABLE := 2048
const PEAK := 0.75
const ORDER := ["city", "map", "tension"]

static var inst: Music

var tracks := {}                     # 이름 → AudioStreamWAV
var mood := ""                       # 지금 나오는 곡
var want := "city"                   # main이 바라는 곡
var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _thread: Thread
var _done_pcm: Array = []            # 스레드가 만든 [이름, PackedByteArray, 표본 수] (메인 스레드가 꺼낸다)
var _mutex := Mutex.new()
var _quit := false
var _tw: Tween


func _init() -> void:
	name = "Music"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	inst = self
	Sound._bus("Music")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)
	Sound.apply_volumes()
	_thread = Thread.new()
	_thread.start(_render_all)


func _exit_tree() -> void:
	_quit = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if inst == self:
		inst = null


static func set_mood(m: String) -> void:
	if inst != null:
		inst.want = m


func _process(_delta: float) -> void:
	_mutex.lock()
	var got := _done_pcm.duplicate()
	_done_pcm.clear()
	_mutex.unlock()
	for g in got:
		var st := AudioStreamWAV.new()
		st.format = AudioStreamWAV.FORMAT_16_BITS
		st.mix_rate = RATE
		st.stereo = false
		st.data = g[1]
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(g[2])
		tracks[String(g[0])] = st
	if want != mood and tracks.has(want):
		_switch(want)


func _switch(to: String) -> void:
	mood = to
	var old: AudioStreamPlayer = _players[_cur]
	_cur = 1 - _cur
	var nu: AudioStreamPlayer = _players[_cur]
	nu.stream = tracks[to]
	nu.volume_db = -40.0
	nu.play()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(nu, "volume_db", 0.0, 2.5)
	if old.playing:
		_tw.tween_property(old, "volume_db", -60.0, 2.5)
	_tw.chain().tween_callback(func():
		if old != _players[_cur]:
			old.stop())


## 시험: 스레드를 기다려 셋을 다 받는다
func finish_all(timeout_ms := 60000) -> void:
	var t0 := Time.get_ticks_msec()
	while tracks.size() < ORDER.size() and Time.get_ticks_msec() - t0 < timeout_ms:
		OS.delay_msec(50)
		_process(0.0)


# ── 만들기 (뒤 스레드) ──────────────────────────────────────────
func _render_all() -> void:
	var tables := _tables()
	for name in ORDER:
		if _quit:
			return
		var buf := _render(String(name), tables)
		var pcm := _pcm(buf)
		_mutex.lock()
		_done_pcm.append([String(name), pcm, buf.size()])
		_mutex.unlock()


static func _tables() -> Dictionary:
	var out := {}
	var specs := {"pad": [1.0, 0.5, 0.33, 0.25, 0.2, 0.14, 0.1, 0.07], "piano": [1.0, 0.45, 0.25, 0.12, 0.06],
		"square": [1.0, 0.0, 0.33, 0.0, 0.2, 0.0, 0.12], "sine": [1.0], "saw": [1.0, 0.5, 0.33, 0.25, 0.2, 0.16]}
	for k in specs:
		var amps: Array = specs[k]
		var t := PackedFloat32Array()
		t.resize(TABLE)
		var peak := 0.0
		for i in TABLE:
			var x := TAU * i / TABLE
			var v := 0.0
			for h in amps.size():
				v += float(amps[h]) * sin(x * (h + 1) + 0.3 * h)
			t[i] = v
			peak = maxf(peak, absf(v))
		for i in TABLE:
			t[i] /= peak
		out[k] = t
	return out


static func _freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## 표 table의 소리 하나를 buf의 at(초)부터 dur초 더한다: a초에 오르고 (sustain이면 끝 rel초 동안 내려가고) 아니면 decay초마다 e배로 준다
static func _note(buf: PackedFloat32Array, table: PackedFloat32Array, midi: float, at: float, dur: float, vol: float,
		a: float, decay: float, rel := 0.3, sustain := false, detune := 0.0, trem := 0.0) -> void:
	var n := buf.size()
	var i0 := int(at * RATE)
	var len := int((dur + (rel if sustain else 0.0)) * RATE)
	var inc := _freq(midi) * (1.0 + detune) * TABLE / RATE
	var ph := 0.0
	var a_n := maxf(a * RATE, 1.0)
	var end_n := dur * RATE
	var rel_n := maxf(rel * RATE, 1.0)
	var dk := 1.0 / maxf(decay * RATE, 1.0)
	for j in len:
		var env := 1.0
		if j < a_n:
			env = j / a_n
		elif sustain:
			if j > end_n:
				env = maxf(0.0, 1.0 - (j - end_n) / rel_n)
		else:
			env = exp(-(j - a_n) * dk)
		if trem > 0.0:
			env *= 1.0 - 0.35 * (0.5 + 0.5 * sin(TAU * trem * j / RATE))
		var k := (i0 + j) % n
		buf[k] += table[int(ph) & (TABLE - 1)] * env * vol
		ph += inc


## 고리 내내 울리는 지속음: 고리 길이에 꼭 맞는 정수 번의 주기로 (떨림도) — 끝과 처음이 이어져 딸깍거리지 않는다
static func _drone(buf: PackedFloat32Array, table: PackedFloat32Array, midi: float, vol: float, trem := 0.0) -> void:
	var n := buf.size()
	var cycles := maxf(1.0, roundf(_freq(midi) * n / RATE))
	var inc := cycles * TABLE / n
	var tc := roundf(trem * n / RATE)
	var ph := 0.0
	for j in n:
		var env := 1.0
		if tc > 0.0:
			env = 1.0 - 0.35 * (0.5 + 0.5 * sin(TAU * tc * j / n))
		buf[j] += table[int(ph) & (TABLE - 1)] * env * vol
		ph += inc


## 둥근 메아리: d초 늦은 소리를 fb만큼 더한다 (두 바퀴 — 고리 끝이 처음으로 이어진다)
static func _echo(buf: PackedFloat32Array, d: float, fb: float, mix: float) -> PackedFloat32Array:
	var n := buf.size()
	var dn := int(d * RATE)
	var wet := PackedFloat32Array()
	wet.resize(n)
	for _pass in 2:
		for i in n:
			wet[i] = buf[(i - dn + n) % n] * mix + wet[(i - dn + n) % n] * fb
	for i in n:
		buf[i] += wet[i]
	return buf


static func _hit(buf: PackedFloat32Array, at: float, vol: float, seed: int) -> void:
	var n := buf.size()
	var i0 := int(at * RATE)
	var ph := 0.0
	var s := seed
	for j in int(0.7 * RATE):
		var t := float(j) / RATE
		var f := 40.0 + 45.0 * exp(-t * 9.0)
		ph += f / RATE
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var noise := (float(s) / 1073741824.0 - 1.0) * exp(-t * 40.0) * 0.4
		buf[(i0 + j) % n] += (sin(TAU * ph) * exp(-t * 4.5) + noise) * vol


static func _render(name: String, tb: Dictionary) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(name.hash())
	match name:
		"city":
			var beat := 60.0 / 72.0
			var bar := beat * 4.0
			buf.resize(int(bar * 8.0 * RATE))
			# Cmaj7 · Am7 · Fmaj7 · G6 — 두 마디씩
			var chords := [[48, 52, 55, 59], [45, 48, 52, 55], [41, 45, 48, 52], [43, 47, 50, 52]]
			for c in 4:
				var t0 := c * 2.0 * bar
				for m in chords[c]:
					_note(buf, tb["pad"], float(m) + 12.0, t0, bar * 2.0, 0.07, 1.1, 0.0, 0.9, true, 0.0)
					_note(buf, tb["pad"], float(m) + 12.0, t0, bar * 2.0, 0.05, 1.3, 0.0, 0.9, true, 0.004)
				_note(buf, tb["piano"], float(chords[c][0]) - 12.0, t0, 0.0, 0.22, 0.004, 1.6)
				_note(buf, tb["piano"], float(chords[c][0]) - 12.0, t0 + bar, 0.0, 0.16, 0.004, 1.4)
				# 선율: 마디마다 화음 음에서 서너 개 (박 1 · 2½ · 3 · 4)
				for b in 2:
					var tb0 := t0 + b * bar
					for on in [0.0, 1.5, 2.0, 3.0]:
						if rng.randf() < 0.22 and on > 0.0:
							continue
						var pick: int = chords[c][rng.randi() % 4] + 24
						if rng.randf() < 0.25:
							pick += 2                      # 지나가는 음
						_note(buf, tb["piano"], float(pick), tb0 + on * beat, 0.0, 0.18 + rng.randf() * 0.06, 0.003, 0.9)
			buf = _echo(buf, 0.31, 0.32, 0.22)
		"map":
			var beat2 := 60.0 / 104.0
			var bar2 := beat2 * 4.0
			buf.resize(int(bar2 * 8.0 * RATE))
			var ch := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]       # Am F C G
			var shape := [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 2, 3, 4, 5, 6, 5]
			for c in 8:
				var cc: Array = ch[(c / 2) % 4]
				var t1 := c * bar2
				for s in 16:
					var step: int = shape[s]
					var m2: int = cc[step % 3] + 12 * (step / 3)
					_note(buf, tb["square"], float(m2), t1 + s * beat2 * 0.25, 0.0, 0.13, 0.003, 0.11)
				for e in 8:
					_note(buf, tb["sine"], float(cc[0]) - 24.0, t1 + e * beat2 * 0.5, 0.0, 0.26, 0.004, 0.18)
				if c % 2 == 0:
					for m3 in cc:
						_note(buf, tb["pad"], float(m3), t1, bar2 * 2.0, 0.035, 0.6, 0.0, 0.5, true)
			buf = _echo(buf, beat2 * 0.75, 0.3, 0.28)
		"tension":
			var beat3 := 60.0 / 84.0
			var bar3 := beat3 * 4.0
			var total := bar3 * 8.0
			buf.resize(int(total * RATE))
			_drone(buf, tb["sine"], 38.0, 0.3, 0.35)
			_drone(buf, tb["saw"], 45.0, 0.08, 0.21)
			var ost := [50, 53, 50, 51, 50, 53, 55, 51]
			for c in 8:
				var t2 := c * bar3
				for e in 8:
					_note(buf, tb["saw"], float(ost[e]) + (0.0 if c < 4 else -2.0), t2 + e * beat3 * 0.5, 0.0, 0.11, 0.004, 0.16)
				_hit(buf, t2, 0.42, 7 + c)
				if c % 4 == 0:
					_note(buf, tb["pad"], 74.0, t2 + beat3, bar3 * 3.0, 0.05, 2.0, 0.0, 1.2, true)
					_note(buf, tb["pad"], 75.0, t2 + beat3, bar3 * 3.0, 0.045, 2.2, 0.0, 1.2, true, 0.003)
			buf = _echo(buf, beat3 * 1.5, 0.25, 0.18)
	return buf


static func _pcm(buf: PackedFloat32Array) -> PackedByteArray:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var k := PEAK / peak if peak > 1e-6 else 1.0
	var pcm := PackedByteArray()
	pcm.resize(buf.size() * 2)
	for i in buf.size():
		pcm.encode_s16(i * 2, int(clampf(buf[i] * k, -1.0, 1.0) * 32000.0))
	return pcm
