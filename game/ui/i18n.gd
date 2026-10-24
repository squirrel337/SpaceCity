class_name I18n
extends Translation
## 영어 — 실행 중 번역 (자료 res://i18n/en.json: 한국어 원문 → 영어, 만드는 법은 game/tools/i18n_extract.py).
## TranslationServer에 넣으면 컨트롤의 글(라벨·단추·도움말 — 자동 번역)과 tr()이 이 번역을 거친다. 원문은 그대로 두고 화면에서만 바뀐다.
## 찾는 차례:
##   1) 원문이 그대로 있으면 그 번역.
##   2) 형식 틀(%s·%d·%.1f — 숫자와 이름 자리, 이야기의 {name})이 맞으면 그 틀의 영어에 값을 넣는다 — 값도 다시 번역한다
##      (건물·도시 이름, "30일"). 틀은 앞 두 글자로 묶고 가장 긴 글 조각으로 미리 거른다. 여러 틀이 맞으면 한글이 가장 적게 남는 것.
##      영어 틀의 {1}·{2}는 원문의 몇째 값인지.
##   3) 여러 줄이면 줄마다 따로 (여러 줄이 한 원문이면 그 번역). 한 줄은 " · ", " — ", ": ", ", ", " / "로 나눠
##      조각마다 1·2를 하고 다시 잇는다 (여러 글을 이어 붙인 줄).
##      그래도 안 되면 띄어쓰기로 나눠 한글 낱말이 모두 사전에 있을 때만 낱말마다 ("섀클턴 120" → "Shackleton 120").
##   4) 사람 이름(성 + 이름 — "김하늘" → "Kim Haneul"). 그래도 없으면 원문 (한국어 그대로).
## 결과는 찾은 깊이와 함께 캐시에 남긴다 (더 얕은 곳에서 다시 찾으면 새로 — 2만 개가 넘으면 비운다). 언어는 설정의 ui/lang ("ko" 기본 · "en") — apply()가 바꾼다.

const PATH := "res://i18n/en.json"
const LANGS := {"ko": "한국어", "en": "English"}
const SPLITS := ["\n", "  ", " · ", " — ", ": ", ", ", " / "]
## 한국 성 (한 글자 낱말은 뜻이 여럿이라 — "서"는 방향이기도 하다 — 이름에는 이 표를 쓴다)
const FAMILY := {"김": "Kim", "이": "Lee", "박": "Park", "최": "Choi", "정": "Jung", "강": "Kang", "조": "Cho", "윤": "Yoon",
	"장": "Jang", "임": "Lim", "한": "Han", "오": "Oh", "서": "Seo", "신": "Shin", "권": "Kwon", "황": "Hwang", "안": "Ahn",
	"송": "Song", "류": "Ryu", "전": "Jeon", "홍": "Hong", "고": "Ko", "문": "Moon", "양": "Yang", "손": "Son", "배": "Bae",
	"백": "Baek", "허": "Heo", "유": "Yoo", "남": "Nam", "심": "Sim", "노": "Noh", "하": "Ha", "곽": "Kwak", "성": "Sung",
	"차": "Cha", "주": "Joo", "우": "Woo", "구": "Koo", "민": "Min", "진": "Jin", "지": "Ji", "엄": "Eom", "채": "Chae",
	"원": "Won", "천": "Cheon", "방": "Bang", "공": "Kong", "현": "Hyun", "함": "Ham", "변": "Byun", "염": "Yeom", "여": "Yeo",
	"추": "Choo", "도": "Do", "소": "So", "석": "Seok", "선": "Sun", "설": "Seol", "마": "Ma", "길": "Gil", "연": "Yeon",
	"표": "Pyo", "명": "Myung", "기": "Ki", "반": "Ban", "왕": "Wang", "금": "Geum", "옥": "Ok", "인": "In", "제": "Je",
	"모": "Mo", "탁": "Tak", "국": "Kook", "은": "Eun", "용": "Yong", "남궁": "Namgung", "선우": "Sunwoo", "제갈": "Jegal",
	"황보": "Hwangbo", "독고": "Dokgo"}
## 수 뒤에 붙는 단위 — 틀에서 %s 바로 뒤에 오면 그 자리는 수다 ("거주 %s명"이 "거주 60명 · 대피 60명"을 먹지 않게)
const NUM_UNITS := ["명", "일", "만", "대", "광년", "시간", "채", "개", "기", "곳", "번", "회", "배", "분", "년", "달", "주", "층", "칸",
	"단계", "가지", "척", "석"]
const FIELD_SEPS := ["\n", " — ", " · ", ": ", " (", ", ", " / "]                          # 틀이 칸을 나누는 글
const TRAIL := [" ★", " ✓", " ◆", " ◇", " ▸", " ●", " ○", " …", " ⚠"]                       # 줄 끝의 표시
const MARKS := ["✓ ", "✗ ", "▸ ", "▾ ", "◆ ", "◇ ", "★ ", "• ", "· ", "— ", "→ ", "● ", "○ ", "▲ ", "▼ ", "⚠ "]   # 줄 앞의 표시
## 자리표시자: printf 꼴 (빈칸 플래그는 없다 — "20% cheaper"가 자리표시자가 아니게)과 {name} 꼴 (이야기의 이름 자리)
const TOKEN := "%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXcioe]|\\{[a-z_]+\\}"

static var inst: I18n
static var lang := "ko"
static var _fill_re: RegEx
static var record := false        # 번역하지 못한 글을 misses에, 번역한 글을 모두 seen에 모은다 (도구·시험)
static var misses := {}
static var seen := {}

var exact := {}
var buckets := {}                 # 앞 두 글자 → [[RegEx, 영어, 자리 종류들, 꼭 있어야 할 글, 글자 수]]
var loose: Array = []             # 자리표시자로 시작하는 틀
var tails: Array = []             # 구분자로 시작하는 원문 ("  · 지금 보는 곳") — 긴 것부터, 다른 글 뒤에 붙는다
var heads := {}                   # 여러 줄 원문의 첫 줄 → 줄 수 (가장 많은 것)
var _cache := {}                  # 글 → [번역, 찾은 깊이]
var _hangul := RegEx.create_from_string("[\\x{ac00}-\\x{d7a3}]")


func _init() -> void:
	locale = "en"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
	if parsed is Dictionary:
		load_dict(parsed)


## 원문 → 영어 사전을 넣는다 (틀은 정규식으로 미리 만든다)
## 자리표시자: %d는 정수, %f·%.1f는 수, %s는 아무 글 (빈 글도), {name}·{role} 같은 이름 자리는 빈칸이 아닌 글.
## 틀마다 글자 수(자리표시자 밖의 글)를 세어 둔다 — 여러 틀이 맞으면 한글이 가장 적게 남는 것, 같으면 글자가 많은(구체적인) 것
func load_dict(parsed: Dictionary) -> void:
	_cache.clear()
	exact.clear()
	buckets.clear()
	loose.clear()
	tails.clear()
	heads.clear()
	var tok := RegEx.create_from_string(TOKEN)
	var pairs: Array = []
	for k in parsed:
		pairs.append([String(k), String(parsed[k])])
	# 앞뒤 빈칸이나 줄 앞의 표시("· ", "▸ ")가 있는 원문은 그것을 뗀 꼴도 (다른 글과 이어 붙어 나뉘면 떨어진다)
	for i in pairs.size():
		var ks := String(pairs[i][0]).strip_edges()
		var vs := String(pairs[i][1]).strip_edges()
		for mk in MARKS:
			if ks.begins_with(mk):
				ks = ks.substr(mk.length())
				if vs.begins_with(mk):
					vs = vs.substr(mk.length())
				break
		if ks != pairs[i][0] and ks != "" and not parsed.has(ks):
			pairs.append([ks, vs])
	for pr in pairs:
		var src := String(pr[0])
		var dst := String(pr[1])
		if exact.has(src):
			continue
		exact[src] = dst
		if src.contains("\n"):
			var ls := src.split("\n")
			heads[ls[0]] = maxi(int(heads.get(ls[0], 0)), ls.size())
		if src.length() > 2 and _hangul.search(src) != null and not src.contains("%") and \
				(src.begins_with("  ") or src.begins_with(" ·") or src.begins_with(" —") or src.begins_with(" (") or src.begins_with(", ")):
			tails.append(src)
		var marks := tok.search_all(src)
		if marks.is_empty():
			continue
		var pat := "^"
		var pos := 0
		var kinds: Array = []                     # 자리마다 "%" 또는 이름 ("name")
		var lit := 0
		var pieces: Array = []
		for m in marks:
			var piece := src.substr(pos, m.get_start() - pos).replace("%%", "%")
			pieces.append(piece)
			lit += piece.length()
			pat += _esc(piece)
			var t := m.get_string()
			if t.begins_with("{"):
				pat += "(.+?)"
				kinds.append(t.substr(1, t.length() - 2))
			else:
				var c := t[t.length() - 1]
				if c in ["d", "i", "x", "X", "o"]:
					pat += "\\s*([-+]?[0-9]+)"
				elif c in ["f", "e"]:
					pat += "\\s*([-+]?[0-9]+(?:\\.[0-9]+)?)"
				elif _unit_after(src.substr(m.get_end())):
					pat += "([-+−~]?[0-9][0-9,.]*)"        # Fmt.n — "1,234.5"
				else:
					pat += "(.*?)"
				kinds.append("%")
			pos = m.get_end()
		var tail := src.substr(pos).replace("%%", "%")
		pieces.append(tail)
		lit += tail.length()
		pat += _esc(tail) + "$"
		var re := RegEx.new()
		if re.compile(pat) != OK:
			continue
		# 글 자리가 둘 넘으면 욕심껏 나누는 꼴도 ("말수 적은 교사"를 %s %s로 — 앞을 길게)
		var greedy: RegEx = null
		if pat.count("(.*?)") >= 2:
			greedy = RegEx.new()
			if greedy.compile(pat.replace("(.*?)", "(.*)")) != OK:
				greedy = null
		var must := ""
		for piece in pieces:
			if String(piece).length() > must.length():
				must = String(piece)
		var weak := true                          # 칸 구분자가 없는 틀 ("%s %s일", "%s ×%.2f")
		for piece in pieces:
			for sep in FIELD_SEPS:
				if String(piece).contains(sep):
					weak = false
		var entry := [re, dst, kinds, must, lit, greedy, weak]
		var head := String(pieces[0])
		if head.length() >= 2:
			var key := head.substr(0, 2)
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(entry)
		else:
			loose.append(entry)
	tails.sort_custom(func(a, b): return String(a).length() > String(b).length())
	# 구체적인 틀부터 (글자가 많은 것)
	for key in buckets:
		(buckets[key] as Array).sort_custom(func(a, b): return int(a[4]) > int(b[4]))
	loose.sort_custom(func(a, b): return int(a[4]) > int(b[4]))


## 틀에서 자리 바로 뒤가 단위 ("명", "일 동안", "만 km") — 단위 뒤에 한글이 더 붙으면 단위가 아니다
func _unit_after(rest: String) -> bool:
	for u in NUM_UNITS:
		if rest.begins_with(u) and (rest.length() == String(u).length() or _hangul.search(rest[String(u).length()]) == null):
			return true
	return false


static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\" + ch
		elif ch == "\n":
			out += "\\n"
		else:
			out += ch
	return out


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(text(String(src_message)))


## 글 하나를 영어로 (한글이 없으면 그대로)
func text(s: String, depth := 0) -> String:
	if s.is_empty() or _hangul.search(s) == null:
		return s
	# 더 얕은(조각을 더 나눠 볼 수 있던) 곳에서 찾은 번역만 다시 쓴다 — 깊은 곳의 덜 된 번역이 남지 않게
	if _cache.has(s) and int(_cache[s][1]) <= depth:
		return _cache[s][0]
	var out := _lookup(s, depth)
	if _cache.size() > 20000:
		_cache.clear()
	_cache[s] = [out, depth]
	if record and depth == 0:
		seen[s] = out
		if _hangul.search(out) != null:
			misses[s] = out
	return out


func _hangul_n(s: String) -> int:
	return _hangul.search_all(s).size()


func _lookup(s: String, depth: int) -> String:
	if exact.has(s):
		return exact[s]
	# 앞뒤 빈칸은 떼고 찾는다
	var core := s.strip_edges()
	if core != s and core != "":
		var at := s.find(core)
		var t0 := text(core, depth)
		if t0 != core:
			return s.substr(0, at) + t0 + s.substr(at + core.length())
	# 사람 이름 ("김하늘")
	if s.length() <= 5 and not s.contains(" "):
		var nm0 := _name(s)
		if nm0 != "":
			return nm0
	# 줄 끝의 표시 (" ★")
	for tm in TRAIL:
		if s.ends_with(tm) and s.length() > tm.length():
			var head := s.substr(0, s.length() - tm.length())
			var th := text(head, depth)
			if th != head:
				return th + tm
	# 줄 앞의 표시 ("✓ ", "▸ ")와 꼬리표 ("[나로] ")
	for mk in MARKS:
		if s.begins_with(mk) and s.length() > mk.length():
			var rest := s.substr(mk.length())
			var tr0 := text(rest, depth)
			if tr0 != rest:
				return mk + tr0
	if s.begins_with("[") and s.find("] ") > 1:
		var e := s.find("] ")
		return "[" + text(s.substr(1, e - 1), depth + 1) + "] " + text(s.substr(e + 2), depth)
	var best := _template(s, depth)
	if best != "" and _hangul.search(best) == null:
		return best
	if s.contains("\n"):
		var ln := _lines(s, depth)
		return ln if best == "" or _hangul_n(ln) <= _hangul_n(best) else best
	if depth >= 8:
		return best if best != "" else s
	var cands: Array = []
	if best != "":
		cands.append(best)
	# 아는 글로 끝난다 ("…  · 지금 보는 곳")
	for tl in tails:
		if s.ends_with(tl) and s.length() > String(tl).length():
			var c_: String = text(s.substr(0, s.length() - String(tl).length()), depth + 1) + String(exact[tl])
			if _hangul.search(c_) == null:
				return c_
			cands.append(c_)
			break
	# 아는 글로 시작하고 구분자 뒤에 다른 글이 붙는다 (가장 긴 것)
	var c0 := _prefix(s, SPLITS + [" ("], depth)
	if c0 != "":
		if _hangul.search(c0) == null:
			return c0
		cands.append(c0)
	# 괄호 덧붙임 "글 (덧붙임)" · "글(덧붙임)"
	if s.ends_with(")") and s.contains("("):
		var o := s.rfind("(")
		var sp := " " if o > 0 and s[o - 1] == " " else ""
		var c_: String = text(s.substr(0, o - sp.length()), depth + 1) + sp + "(" + text(s.substr(o + 1, s.length() - o - 2), depth + 1) + ")"
		if _hangul.search(c_) == null:
			return c_
		cands.append(c_)
	# 한 곳에서만 나눈다 (처음·마지막 구분자) — 틀 뒤에 다른 글이 붙은 줄 ("…짓는다: 까닭", "…부품 189, 로봇 2대")
	for sep in [": ", " — ", ", ", " · "]:
		for i in [s.find(sep), s.rfind(sep)]:
			if i > 0:
				var c_: String = text(s.substr(0, i), depth + 1) + sep + text(s.substr(i + sep.length()), depth + 1)
				if _hangul.search(c_) == null:
					return c_
				cands.append(c_)
	# 구분자로 나눠 조각마다
	for sep in SPLITS:
		if s.contains(sep):
			var parts := s.split(sep)
			var changed := false
			for i in parts.size():
				var p := text(parts[i], depth + 1)
				if p != parts[i]:
					parts[i] = p
					changed = true
			if changed:
				var c_: String = sep.join(parts)
				if _hangul.search(c_) == null:
					return c_
				cands.append(c_)
				break
	# 아는 글 뒤에 빈칸과 다른 글 ("일하는 효율 ×1.04") — 칸 구분자로 나눠 본 뒤에 ("거주 60명 · 대피 60명"을 "거주" + 나머지로 읽지 않게)
	var c1 := _prefix(s, [" "], depth)
	if c1 != "":
		if _hangul.search(c1) == null:
			return c1
		cands.append(c1)
	# 낱말: 띄어쓰기로 나눠 한글 낱말이 모두 사전에 있을 때만 ("섀클턴 120" → "Shackleton 120")
	if s.contains(" "):
		var words := s.split(" ")
		var all_ok := true
		for i in words.size():
			if _hangul.search(words[i]) == null:
				continue
			var w := _word(words[i])
			if w == "":
				all_ok = false
				break
			words[i] = w
		if all_ok:
			var c_: String = " ".join(words)
			if _hangul.search(c_) == null:
				return c_
			cands.append(c_)
	var nm := _name(s)
	if nm != "":
		var c_: String = nm
		if _hangul.search(c_) == null:
			return c_
		cands.append(c_)
	# 한글이 가장 적게 남는 것 (같으면 먼저 찾은 것)
	var pick := s
	var pick_n := _hangul_n(s)
	for c in cands:
		var n := _hangul_n(String(c))
		if n < pick_n:
			pick = String(c)
			pick_n = n
			if n == 0:
				break
	return pick


## 원문 사전에 있는 가장 긴 앞부분(구분자 앞에서 끊는다)의 번역 + 나머지 번역. 없으면 ""
func _prefix(s: String, seps: Array, depth: int) -> String:
	var cut := -1
	for sep in seps:
		var from := 0
		while true:
			var i := s.find(sep, from)
			if i <= 0:
				break
			if i > cut and exact.has(s.substr(0, i)):
				cut = i
			from = i + 1
	if cut <= 0:
		return ""
	return String(exact[s.substr(0, cut)]) + text(s.substr(cut), depth + 1)


## 여러 줄: 줄마다 같은 깊이로 (줄이 많아도 깊어지지 않게) — 몇 줄이 이어서 한 원문이면 그 번역 (가장 긴 것)
func _lines(s: String, depth: int) -> String:
	var lines := s.split("\n")
	var out := PackedStringArray()
	var i := 0
	while i < lines.size():
		var took := 1
		var n := mini(int(heads.get(lines[i], 0)), lines.size() - i)
		while n > 1:
			var chunk := "\n".join(lines.slice(i, i + n))
			if exact.has(chunk):
				out.append(String(exact[chunk]))
				took = n
				break
			n -= 1
		if took == 1:
			out.append(text(lines[i], depth + 1))
		i += took
	return "\n".join(out)


## 낱말 하나: 사전에 있거나 사람 이름(성 + 이름)이면 그 영어, 아니면 ""
func _word(w: String) -> String:
	if exact.has(w):
		return exact[w]
	return _name(w)


## 한국 사람 이름 "김하늘" → "Kim Haneul" (성 한두 글자와 이름이 사전에 있을 때만)
func _name(w: String) -> String:
	if w.length() < 2 or w.length() > 4 or w.contains(" "):
		return ""
	for fl in [2, 1]:
		if w.length() - fl < 1:
			continue
		var fam := w.substr(0, fl)
		var giv := w.substr(fl)
		if FAMILY.has(fam) and exact.has(giv) and _hangul.search(String(exact[giv])) == null:
			return "%s %s" % [FAMILY[fam], exact[giv]]
	return ""


## 맞는 틀 가운데 한글이 가장 적게 남는 것 (같으면 앞의 — 더 구체적인 — 것). 한글이 남지 않으면 바로
func _template(s: String, depth: int) -> String:
	var best := ""
	var best_n := 1 << 30
	for list in [buckets.get(s.substr(0, 2), []), loose]:
		for e in list:
			if String(e[3]) != "" and not s.contains(String(e[3])):
				continue
			for re in [e[0], e[5]]:
				if re == null:
					continue
				var m: RegExMatch = (re as RegEx).search(s)
				if m == null or not _fits(m, (e[2] as Array).size(), bool(e[6])):
					continue
				var vals: Array = []
				var kinds: Array = e[2]
				for i in range(1, kinds.size() + 1):
					var v := m.get_string(i)
					vals.append(text(v, depth + 1) if depth < 6 else v)
				var out := _fill(String(e[1]), vals, kinds)
				var n := _hangul_n(out)
				if n < best_n:
					best = out
					best_n = n
					if n == 0:
						return best
	return best


## 틀의 자리 값이 글의 칸을 넘지 않는다: 값이 구분자로 시작하거나 끝나면 틀이 칸 사이의 빈칸에서 나눈 것
## ("하루 — 하루 16일"을 "%s %s일"로 읽으면 둘째 값이 "— 하루 16"이 된다). 구분자가 없는 틀("%s %s일", "연구 %s")의 값은
## " — "·": "를 품지 않고 (욕심껏 읽으면 첫 값이 "하루 — 하루", "연구 완료 — 극지 자원 탐사"는 "연구" + "완료 — …"), 값이 둘 넘으면
## " · "도 품지 않는다. 구분자가 있는 틀("최근: %s · %s")이나 값이 하나인 틀의 " · "("%s부터" — "시대 1 · 정착 도시부터")는 괜찮다
static func _fits(m: RegExMatch, n: int, weak: bool) -> bool:
	for i in range(1, n + 1):
		var v := m.get_string(i)
		if v.begins_with("— ") or v.begins_with("· ") or v.begins_with(", ") or v.ends_with(" —") or v.ends_with(" ·"):
			return false
		if weak and (v.contains(" — ") or v.contains(": ") or (n >= 2 and v.contains(" · "))):
			return false
	return true


## 영어 틀에 값: {1}·{2}(몇째 자리), {name}(이름 자리), 그리고 남은 %자리표시자는 % 값을 차례로
static func _fill(dst: String, vals: Array, kinds: Array = []) -> String:
	var out := dst
	if out.contains("{1}"):
		for i in vals.size():
			out = out.replace("{%d}" % (i + 1), String(vals[i]))
		return out
	var pct: Array = []
	for i in vals.size():
		var kind := String(kinds[i]) if i < kinds.size() else "%"
		if kind == "%":
			pct.append(vals[i])
		else:
			out = out.replace("{%s}" % kind, String(vals[i]))
	if _fill_re == null:
		_fill_re = RegEx.create_from_string("%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXcioe%]")
	var out2 := ""
	var pos := 0
	var k := 0
	for m in _fill_re.search_all(out):
		out2 += out.substr(pos, m.get_start() - pos)
		if m.get_string() == "%%":
			out2 += "%"
		else:
			out2 += String(pct[k]) if k < pct.size() else ""
			k += 1
		pos = m.get_end()
	return out2 + out.substr(pos)


# ── 언어 ────────────────────────────────────────────────────────
## 설정의 언어를 적용한다 (게임을 시작할 때와 설정을 바꿀 때)
static func apply(code := "") -> void:
	if code == "":
		code = String(Settings.value("ui/lang", "ko"))
	lang = code if LANGS.has(code) else "ko"
	if lang == "en":
		if inst == null:
			inst = I18n.new()
		if not TranslationServer.get_loaded_locales().has("en"):
			TranslationServer.add_translation(inst)
	elif inst != null:
		TranslationServer.remove_translation(inst)
	TranslationServer.set_locale(lang)


static func set_lang(code: String) -> void:
	Settings.set_value("ui/lang", code)
	apply(code)


static func is_en() -> bool:
	return lang == "en"


## 코드에서 직접 (그리기 글·정적 함수): 지금 언어로
static func t(s: String) -> String:
	return inst.text(s) if lang == "en" and inst != null else s
