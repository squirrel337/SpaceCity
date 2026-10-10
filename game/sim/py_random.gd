class_name PyRandom
extends RefCounted
## 파이썬 random.Random과 같은 수열을 내는 메르센 트위스터(MT19937).
## 밸런스 시뮬레이터(docs/design/sim/city_balance.py)와 같은 시드에서 같은 결과를 내려고 쓴다.
## 정수 시드만 지원한다 (파이썬의 init_by_array 시드 방식).

const N := 624
const M := 397
const MASK32 := 0xFFFFFFFF
const UPPER := 0x80000000
const LOWER := 0x7FFFFFFF
const MATRIX_A := 0x9908B0DF

var _mt := PackedInt64Array()
var _index := N


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	# 파이썬은 abs(seed)를 32비트 조각(작은 자리부터)으로 나눠 init_by_array에 넣는다
	var n: int = absi(seed_value)
	var key := PackedInt64Array()
	while true:
		key.append(n & MASK32)
		n = n >> 32
		if n == 0:
			break
	_init_by_array(key)


func random() -> float:
	## [0, 1) 실수. 53비트 정밀도 — random.random()과 같다.
	var a: int = _next_u32() >> 5
	var b: int = _next_u32() >> 6
	return (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)


func uniform(a: float, b: float) -> float:
	return a + (b - a) * random()


func getrandbits(k: int) -> int:
	## k는 1~32
	return _next_u32() >> (32 - k)


func randbelow(n: int) -> int:
	## [0, n) 정수 — random._randbelow_with_getrandbits와 같다
	var k := _bit_length(n)
	var r := getrandbits(k)
	while r >= n:
		r = getrandbits(k)
	return r


func randint(a: int, b: int) -> int:
	## [a, b] 정수 — random.randint와 같다
	return a + randbelow(b - a + 1)


func get_state() -> Dictionary:
	return {"mt": Array(_mt), "index": _index}


func set_state(state: Dictionary) -> void:
	_mt = PackedInt64Array(state["mt"])
	_index = int(state["index"])


func _init_genrand(s: int) -> void:
	_mt.resize(N)
	_mt[0] = s & MASK32
	for i in range(1, N):
		var prev: int = _mt[i - 1]
		_mt[i] = (1812433253 * (prev ^ (prev >> 30)) + i) & MASK32
	_index = N


func _init_by_array(key: PackedInt64Array) -> void:
	_init_genrand(19650218)
	var i := 1
	var j := 0
	var k: int = maxi(N, key.size())
	while k > 0:
		var prev: int = _mt[i - 1]
		_mt[i] = ((_mt[i] ^ ((prev ^ (prev >> 30)) * 1664525)) + key[j] + j) & MASK32
		i += 1
		j += 1
		if i >= N:
			_mt[0] = _mt[N - 1]
			i = 1
		if j >= key.size():
			j = 0
		k -= 1
	k = N - 1
	while k > 0:
		var prev: int = _mt[i - 1]
		_mt[i] = ((_mt[i] ^ ((prev ^ (prev >> 30)) * 1566083941)) - i) & MASK32
		i += 1
		if i >= N:
			_mt[0] = _mt[N - 1]
			i = 1
		k -= 1
	_mt[0] = UPPER
	_index = N


func _twist() -> void:
	for kk in range(N):
		var y: int = (_mt[kk] & UPPER) | (_mt[(kk + 1) % N] & LOWER)
		var v: int = _mt[(kk + M) % N] ^ (y >> 1)
		if y & 1:
			v ^= MATRIX_A
		_mt[kk] = v
	_index = 0


func _next_u32() -> int:
	if _index >= N:
		_twist()
	var y: int = _mt[_index]
	_index += 1
	y ^= y >> 11
	y ^= (y << 7) & 0x9D2C5680
	y ^= (y << 15) & 0xEFC60000
	y ^= y >> 18
	return y & MASK32


static func _bit_length(n: int) -> int:
	var bits := 0
	while n > 0:
		bits += 1
		n = n >> 1
	return bits
