extends Node
## Разговор с жителями голосом (экспериментально, настройки → «Звук» → «Голосом с жителями»): пока зажата B —
## запись микрофоном игры (её распознавание речи, Whisper: Main.hearing), отпустили — текст. Отзывается только тот
## житель, чьё имя прозвучало (рядом, в radius м; имя — в любом падеже, с одной ошибкой распознавания): у него
## открывается разговор, и фраза уходит нейросети так же, как набранная текстом (talk.gd → say_text).
## Чтобы игра сама не отправила текст своему ассистенту, на время записи — её режим «проверки» (hearing_for_check).

signal heard(text: String)                # распознано (для подсказки на экране)

const KEY := KEY_B
var mod: PaxMod
var game: PaxGame
var radius := 30.0
var _hearing: Object
var _down := false
var _busy := false
var _hint: Label


func setup(m: PaxMod, g: PaxGame) -> void:
	mod = m
	game = g
	name = "PaxRpgVoiceTalk"
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 170
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.85))
	_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.04, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	layer.add_child(_hint)


func enabled() -> bool:
	return bool(mod.get_setting("voice_talk", false))


func _find_hearing() -> Object:
	if is_instance_valid(_hearing):
		return _hearing
	var main: Object = game.main if game != null else null
	if main == null:
		return null
	for k: String in ["hearing", "слух"]:
		var h: Variant = main.get(k)
		if h is Object and is_instance_valid(h) and (h as Object).has_signal("recognized"):
			_hearing = h
			(h as Object).connect("recognized", _on_text)
			(h as Object).connect("failed", _on_failed)
			return _hearing
	return null


func hint(text: String) -> void:
	_show(text)


var _hint_tw: Tween


func _show(text: String, sec := 2.5) -> void:
	# прежнее угасание — прочь: иначе подсказка «слушаю» (без срока) гасла по таймеру предыдущей
	if _hint_tw != null and _hint_tw.is_valid():
		_hint_tw.kill()
	_hint.text = text
	_hint.visible = text != ""
	_hint.modulate.a = 1.0
	if sec > 0.0:
		_hint_tw = _hint.create_tween()
		_hint_tw.tween_interval(sec)
		_hint_tw.tween_property(_hint, "modulate:a", 0.0, 0.6)
		_hint_tw.tween_callback(_hint.hide)               # угасла — не рисуется


## Опрос клавиши — каждый кадр (location.gd → tick): зажата — запись, отпущена — распознавание.
func tick(can_listen: bool) -> void:
	if not enabled():
		if _down:
			_stop()
		return
	var on := can_listen and Input.is_physical_key_pressed(KEY)
	if on and not _down and not _busy:
		_start()
	elif not on and _down:
		_stop()


func _start() -> void:
	var h := _find_hearing()
	if h == null:
		_show(mod.tr_key("pax_rpg_voice_no_mic"))
		return
	var hv: Variant = h                                # класс игры, а не мода: методы — через Variant
	if h.has_method("ready_m") and not bool(hv.ready_m()):
		var why := str(hv.why_not_ready()) if h.has_method("why_not_ready") else ""
		_show(mod.tr_key("pax_rpg_voice_no_mic") + ("\n" + why if why != "" else ""), 4.0)
		return
	if bool(h.get("recognizing")):
		return
	h.set("hearing_for_check", true)                   # игра не отправит текст своему ассистенту
	_down = true
	hv.toggle()                                   # запись
	_show("🎙 " + mod.tr_key("pax_rpg_voice_listening"), 0.0)


func _stop() -> void:
	_down = false
	var h := _find_hearing()
	if h == null:
		return
	_busy = true
	var hv: Variant = h
	hv.toggle()                                   # конец записи → распознавание
	_show("… " + mod.tr_key("pax_rpg_voice_thinking"), 0.0)


func _on_failed(why: String) -> void:
	if not _busy:
		return
	_busy = false
	if is_instance_valid(_hearing):
		_hearing.set("hearing_for_check", false)
	_show(str(why), 3.0)


func _on_text(text: String) -> void:
	if not _busy:
		return                                         # не наша запись (меню игры, её окна)
	_busy = false
	if is_instance_valid(_hearing):
		_hearing.set("hearing_for_check", false)
	text = text.strip_edges()
	if text == "":
		_show(mod.tr_key("pax_rpg_voice_silence"), 2.0)
		return
	heard.emit(text)


static func _norm(s: String) -> String:
	return s.to_lower().replace("ё", "е")


static func _lev(a: String, b: String) -> int:
	var prev: Array = range(b.length() + 1)
	for i: int in a.length():
		var cur: Array = [i + 1]
		for j: int in b.length():
			cur.append(mini(mini(int(prev[j + 1]) + 1, int(cur[j]) + 1), int(prev[j]) + (0 if a[i] == b[j] else 1)))
		prev = cur
	return int(prev[b.length()])


## Похоже ли слово фразы на имя: то же слово, падеж (основа + 1–3 буквы окончания) или одна ошибка распознавания.
static func name_hit(word: String, npc_name: String) -> bool:
	var w := _norm(word)
	var n := _norm(npc_name)
	if w == n:
		return true
	if n.length() >= 4 and w.begins_with(n.substr(0, n.length() - 1)) and w.length() <= n.length() + 3:
		return true
	return n.length() >= 4 and absi(w.length() - n.length()) <= 1 and _lev(w, n) <= 1


## Кого назвали: ближайший к герою житель (в radius м), чьё имя есть во фразе. Возвращает [житель, фраза без имени].
func addressee(text: String, npcs: Array, from: Vector3) -> Array:
	var words := _norm(text).replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false)
	var best: Node = null
	var bd := radius
	for n: Variant in npcs:
		if not is_instance_valid(n):
			continue
		var npc := n as Node3D
		var nm := str(npc.get("npc_name"))
		if nm == "":
			continue
		var d := npc.global_position.distance_to(from)
		if d > bd:
			continue
		for w: String in words:
			if name_hit(w, nm):
				best = npc
				bd = d
				break
	if best == null:
		return []
	var rest := text
	for w: String in text.split(" ", false):              # обращение по имени из фразы убираем — остальное житель слышит
		if name_hit(w.strip_edges().trim_suffix(",").trim_suffix("!"), str(best.get("npc_name"))):
			rest = rest.replace(w, "").strip_edges().trim_prefix(",").strip_edges()
			break
	return [best, rest if rest != "" else text]
