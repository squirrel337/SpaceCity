class_name PyCompat
## 파이썬 시뮬레이터와 결과를 맞추는 데 필요한 파이썬 수치 규칙.


## round(x) — 정확히 반이면 짝수 쪽으로 (banker's rounding)
static func round_half_even(x: float) -> int:
	var f := floorf(x)
	var diff := x - f
	if diff > 0.5:
		return int(f) + 1
	if diff < 0.5:
		return int(f)
	return int(f) if int(f) % 2 == 0 else int(f) + 1


## sum() — 파이썬 3.12부터 실수 합은 노이마이어 보정 합이다.
## 모두 실수인 목록에만 쓴다 (정수 항목은 파이썬도 보정하지 않는다).
static func fsum(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var f: float = values[0]
	var c := 0.0
	for i in range(1, values.size()):
		var x: float = values[i]
		var t := f + x
		if absf(f) >= absf(x):
			c += (f - t) + x
		else:
			c += (x - t) + f
		f = t
	if c != 0.0 and is_finite(c):
		f += c
	return f
