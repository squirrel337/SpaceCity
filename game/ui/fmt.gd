class_name Fmt
## 숫자·단위 표기


static func n(value: float, decimals: int = 0) -> String:
	## 천 단위 쉼표를 넣은 고정 소수점
	var text: String = ("%." + str(decimals) + "f") % absf(value)
	var parts := text.split(".")
	var out := _group(parts[0])
	if parts.size() > 1:
		out += "." + parts[1]
	if value < 0 and float(text) != 0.0:
		out = "-" + out
	return out


static func _group(digits: String) -> String:
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


static func pct(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


static func days(value: float) -> String:
	if value >= 999:
		return "충분"
	if value >= 10:
		return "%d일" % int(round(value))
	return "%s일" % n(value, 1)


static func hours(value: float) -> String:
	if value >= 48:
		return "%s일" % n(value / 24.0, 1)
	return "%d시간" % int(round(value))
